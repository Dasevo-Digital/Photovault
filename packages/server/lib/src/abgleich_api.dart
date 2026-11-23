import 'package:kern/abgleich/grenzen.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:kern/abgleich/befehlsbasis.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// Der Abgleich mit verbundenen Geräten (Stufe 2): Abzug der ganzen
/// Bibliothek, der Strom der Änderungen danach, Befehle im Stapel und
/// Dateien nach ihrem Pfad.
///
/// **Der Server ist der einzige Schreiber.** Ein Gerät hält eine Kopie,
/// liest die Änderungen und schickt seine eigenen als Befehle. Was der
/// Server sonst schreibt – Importe, Auswertungen –, steht genauso im
/// Protokoll und kommt auf demselben Weg an.
class Abgleichsapi {
  Abgleichsapi(
    this.bibliotheken, {
    this.takt = const Duration(milliseconds: 500),
    this.abzugsordner,
    this.ohneLeser = const Duration(minutes: 1),
  });

  final Bibliotheken bibliotheken;

  /// Wie oft eine wartende Abfrage nachsieht, ob sich etwas getan hat.
  final Duration takt;

  /// Wo die Abzüge entstehen; sonst im Systemtemp.
  final Directory? abzugsordner;

  /// So lange darf eine Antwort mit einem Abzug ohne Fortschritt stehen –
  /// ungelesen oder mit einem Leser, der nicht weiterliest; danach bricht
  /// sie ab und gibt ihre Kopie frei.
  final Duration ohneLeser;

  /// Höchstens so viele Abzüge je Bibliothek zugleich. Gleichzeitige
  /// Anfragen auf denselben Stand teilen sich einen; ein zweiter entsteht
  /// nur, wenn sich in der Zwischenzeit etwas geändert hat.
  static const hoechstensAbzuege = 2;

  /// Die Abzüge, die gerade ausgeliefert werden, je Bibliothek.
  final _abzuege = <String, List<_Abzug>>{};

  /// Je Bibliothek nur ein `VACUUM INTO` zugleich.
  final _abzugReihe = <String, Future<void>>{};

  final _dateiwechsel = <String, Future<void>>{};

  Future<void> _uebernehme(
    File teil,
    File ziel,
    AppDatabase db,
    String relativ,
  ) {
    final pfad = ziel.path;
    final vorher = _dateiwechsel[pfad] ?? Future<void>.value();
    final fertig = Completer<void>();
    _dateiwechsel[pfad] = fertig.future;
    return vorher
        .then((_) async {
          final verwender = await db
              .customSelect(
                'SELECT DISTINCT sha256 FROM develop_variant_files WHERE relative_path=? LIMIT 2',
                variables: [Variable.withString(relativ)],
              )
              .get();
          if (verwender.isNotEmpty &&
              (verwender.length != 1 ||
                  (await sha256.bind(teil.openRead()).first).toString() !=
                      verwender.single.read<String>('sha256'))) {
            throw const FormatException('pv_variante_unveraenderlich');
          }
          await teil.rename(pfad);
        })
        .whenComplete(() {
          fertig.complete();
          if (identical(_dateiwechsel[pfad], fertig.future)) {
            _dateiwechsel.remove(pfad);
          }
        });
  }

  Future<Bibliothek> _bib(Request r) async =>
      (await bibliotheken.fuer(kontoVon(r).id)).bibliothek;

  /// `{stand, schema}` – wie weit das Protokoll reicht.
  Future<Response> stand(Request anfrage) async {
    final b = await _bib(anfrage);
    return _json({
      'stand': await b.protokoll.stand(),
      'schema': b.db.schemaVersion,
    });
  }

  /// `?nach=N&anzahl=500&warten=25` → `{bis, mehr, zeilen}`.
  ///
  /// Mit `warten` (Sekunden, höchstens 30) hält die Anfrage an, bis sich
  /// etwas ändert oder die Zeit um ist – so erfährt ein Gerät von einer
  /// Änderung, ohne ständig zu fragen, und ein Reverse Proxy mit 60
  /// Sekunden Geduld schneidet nichts ab.
  Future<Response> aenderungen(Request anfrage) async {
    final b = await _bib(anfrage);
    final q = anfrage.url.queryParameters;
    final nach = int.tryParse(q['nach'] ?? '') ?? 0;
    final anzahl = (int.tryParse(q['anzahl'] ?? '') ?? 500).clamp(1, 2000);
    final warten = Duration(
      seconds: (int.tryParse(q['warten'] ?? '') ?? 0).clamp(0, 30),
    );
    try {
      final ende = DateTime.now().add(warten);
      while (!b.wirdGeschlossen &&
          await b.protokoll.stand() <= nach &&
          DateTime.now().isBefore(ende)) {
        await Future<void>.delayed(takt);
      }
      if (b.wirdGeschlossen) {
        return _json({'fehler': 'Server wird beendet.'}, status: 503);
      }
      final s = await b.protokoll.seit(nach, anzahl: anzahl);
      return _json({
        'bis': s.bis,
        'mehr': s.mehr,
        'zeilen': [for (final z in s.zeilen) z.alsJson()],
      });
    } catch (_) {
      // Beim Beenden kann die Datenbank genau zwischen der Schleifenprüfung
      // und einer Abfrage geschlossen werden. Das ist kein Serverfehler und
      // darf nicht als unbehandelte Ausnahme im Protokoll landen.
      if (b.wirdGeschlossen) {
        return _json({'fehler': 'Server wird beendet.'}, status: 503);
      }
      rethrow;
    }
  }

  /// `{schluessel: [{t, s}]}` → `{zeilen}`: der jetzige Stand einzelner
  /// Zeilen – für ein Gerät, das prüft, ob seine vorweggenommenen
  /// Änderungen so auch auf dem Server stehen.
  Future<Response> zeilen(Request anfrage) async {
    final b = await _bib(anfrage);
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'ungültiges JSON'}, status: 400);
    }
    final liste = k is Map ? k['schluessel'] : null;
    if (liste is! List || liste.length > 5000) {
      return _json({'fehler': 'schluessel fehlt'}, status: 400);
    }
    final tabellen = (await b.protokoll.abgeglicheneTabellen()).toSet();
    final aus = <Map<String, Object?>>[];
    for (final e in liste) {
      if (e is! Map) {
        return _json({'fehler': 'schluessel ungültig'}, status: 400);
      }
      final t = e['t'];
      final roh = e['s'];
      if (t is! String || roh is! List || roh.length > 16) {
        return _json({'fehler': 'schluessel ungültig'}, status: 400);
      }
      if (!tabellen.contains(t)) continue;
      if (roh.length != await b.protokoll.schluessellaenge(t)) {
        return _json({'fehler': 'schluessel ungültig'}, status: 400);
      }
      final werte = <Object?>[];
      try {
        for (final w in roh) {
          if (w is bool || w is List || (w is Map && w['b'] is! String)) {
            throw const FormatException('kein SQLite-Wert');
          }
          werte.add(wertAusJson(w));
        }
      } on FormatException {
        return _json({'fehler': 'schluessel ungültig'}, status: 400);
      } on TypeError {
        return _json({'fehler': 'schluessel ungültig'}, status: 400);
      }
      final z = await b.protokoll.lies(t, werte);
      aus.add(z.alsJson());
    }
    return _json({'zeilen': aus});
  }

  /// Die ganze Bibliothek als SQLite-Datei – der Anfang einer Kopie. Ihr
  /// eigenes Protokoll reist mit; dessen höchste Nummer ist der Stand, ab
  /// dem das Gerät weiterliest.
  ///
  /// **Eine Kopie für alle, die gleichzeitig fragen (#436).** Vorher legte
  /// jede Anfrage ihre eigene volle Kopie an, die erst verschwand, wenn
  /// ihre Antwort ganz gelesen war. N gleichzeitige Anfragen – ein Gerät,
  /// das hängt, oder eines, das es darauf anlegt – füllten so das
  /// Systemtemp mit N Bibliotheken, und die Vacuums hielten die Datenbank
  /// des Kontos nacheinander auf. Jetzt entsteht je Bibliothek nur ein
  /// Abzug zugleich; wer fragt, während einer auf demselben Stand
  /// ausgeliefert wird, bekommt denselben. Mehr als [hoechstensAbzuege]
  /// gibt es nicht (503). Geht die Antwort [ohneLeser] lang nicht weiter
  /// – niemand liest sie, oder der Leser steht –, bricht sie ab und gibt
  /// ihre Kopie frei.
  Future<Response> abzug(Request anfrage) async {
    final b = await _bib(anfrage);
    // shelf_router nimmt HEAD mit; der Körper liefe nie, und nur er räumt auf.
    if (anfrage.method == 'HEAD') return Response.ok(null);
    final kopie = await _abzugFuer(b);
    if (kopie == null) {
      return Response(
        503,
        body: jsonEncode({'fehler': 'pv_abzug_belegt'}),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          'retry-after': '30',
        },
      );
    }
    StreamSubscription<List<int>>? abo;
    var frei = false;
    Timer? wache;
    void gibFrei() {
      if (frei) return;
      frei = true;
      wache?.cancel();
      unawaited(kopie.gibFrei());
    }

    late final StreamController<List<int>> aus;
    // Ging [ohneLeser] lang nichts weiter: abbrechen und die Kopie
    // freigeben. Das Gerät sieht eine unvollständige Antwort und fragt neu.
    void abbrechen() {
      if (frei) return;
      unawaited(abo?.cancel());
      abo = null;
      gibFrei();
      aus.addError(TimeoutException('Abzug: niemand liest weiter', ohneLeser));
      unawaited(aus.close());
    }

    // **Die Frist misst den Fortschritt (#485).** Sie endete früher, sobald
    // der Server der Antwort zuhörte – und das tut er sofort, auch wenn das
    // Gerät nie etwas liest. Zwei Verbindungen, die stehen blieben (eine App
    // hängt, ein Telefon geht in den Hintergrund), hielten so ihre Kopien,
    // bis sie endeten, und jedes weitere Gerät des Kontos bekam
    // `pv_abzug_belegt`. Jetzt stellt jedes gelieferte Stück sie neu.
    void wacheStellen() {
      wache?.cancel();
      wache = Timer(ohneLeser, abbrechen);
    }

    wacheStellen();
    aus = StreamController<List<int>>(
      onListen: () {
        // Schon abgebrochen: Fehler und Ende liegen bereit, die Kopie ist weg.
        if (frei) return;
        wacheStellen();
        abo = kopie.datei.openRead().listen(
          (stueck) {
            wacheStellen();
            aus.add(stueck);
          },
          onError: aus.addError,
          onDone: () {
            unawaited(aus.close());
            gibFrei();
          },
        );
      },
      onPause: () => abo?.pause(),
      onResume: () => abo?.resume(),
      onCancel: () async {
        await abo?.cancel();
        gibFrei();
      },
    );
    return Response.ok(
      aus.stream,
      headers: {
        'content-type': 'application/vnd.sqlite3',
        'content-length': '${kopie.laenge}',
        'cache-control': 'no-store',
      },
    );
  }

  /// Der Abzug von [b] für eine weitere Antwort: ein laufender auf dem
  /// jetzigen Stand oder ein neuer; `null`, wenn schon
  /// [hoechstensAbzuege] laufen. Je Bibliothek eins nach dem anderen.
  Future<_Abzug?> _abzugFuer(Bibliothek b) {
    final schluessel = b.ordner.path;
    final lauf = (_abzugReihe[schluessel] ?? Future<void>.value()).then((
      _,
    ) async {
      final stand = await b.protokoll.stand();
      final laufend = _abzuege[schluessel] ?? const <_Abzug>[];
      for (final k in laufend) {
        if (k.stand == stand && k.nimm()) return k;
      }
      if (laufend.length >= hoechstensAbzuege) return null;
      final tmp = await (abzugsordner ?? Directory.systemTemp).createTemp(
        'pv_abzug_',
      );
      final datei = File(p.join(tmp.path, 'library.sqlite'));
      try {
        await b.db.customStatement('VACUUM INTO ?', [datei.path]);
      } catch (_) {
        await tmp.delete(recursive: true);
        rethrow;
      }
      final neu = _Abzug(stand, tmp, datei, await datei.length(), () {
        final liste = _abzuege[schluessel];
        liste?.removeWhere((x) => x.ordner.path == tmp.path);
        if (liste != null && liste.isEmpty) _abzuege.remove(schluessel);
      })..nimm();
      _abzuege.putIfAbsent(schluessel, () => []).add(neu);
      return neu;
    });
    final weiter = lauf.then<void>((_) {}, onError: (_) {});
    _abzugReihe[schluessel] = weiter;
    unawaited(
      weiter.then((_) {
        if (identical(_abzugReihe[schluessel], weiter)) {
          _abzugReihe.remove(schluessel);
        }
      }),
    );
    return lauf;
  }

  /// Befehle: einzeln (`{art, werte}`) oder im Stapel
  /// (`{befehle: [{kennung, art, werte}]}`).
  ///
  /// Im Stapel in ihrer Reihenfolge, jeder mit seiner Kennung höchstens
  /// einmal: Kommt eine Kennung wieder (die Antwort ging verloren), wird
  /// der Befehl nicht noch einmal ausgeführt. Scheitert einer, laufen die
  /// übrigen weiter; die Antwort sagt je Befehl, wie es ausging, und bis
  /// zu welchem Stand das Protokoll danach reicht.
  Future<Response> befehle(Request anfrage) async {
    final b = await _bib(anfrage);
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    if (k is! Map) return _json({'fehler': 'kein Befehl'}, status: 400);
    final stapel = k['befehle'];
    if (stapel == null) {
      // Einzeln, wie bisher.
      final Befehl<Object?> befehl;
      try {
        befehl = Befehl.ausJson(k.cast<String, Object?>());
      } on Object catch (e) {
        return _json({'fehler': 'Befehl nicht lesbar: $e'}, status: 400);
      }
      final Object? ergebnis;
      try {
        ergebnis = await b.db.fuehreAus(befehl);
      } on StateError catch (e) {
        // Was die Bibliothek ablehnt – etwa einen schon vergebenen Namen
        // (#273) –, mit Grund statt als 500.
        return _json({'fehler': e.message}, status: 409);
      }
      return _json({
        'ergebnis': ergebnisAlsJson(ergebnis),
        'stand': await b.protokoll.stand(),
      });
    }
    if (stapel is! List || stapel.length > 500) {
      return _json({'fehler': 'befehle fehlt'}, status: 400);
    }
    final ergebnisse = <Map<String, Object?>>[];
    for (final e in stapel) {
      final eintrag = e is Map ? e.cast<String, Object?>() : null;
      if (utf8.encode(jsonEncode(e)).length > Abgleichsgrenzen.befehlBytes) {
        return _json({'fehler': 'pv_sync_auswahl'}, status: 413);
      }
      final kennung = eintrag?['kennung'];
      if (eintrag == null || kennung is! String || kennung.isEmpty) {
        return _json({
          'fehler': 'jeder Befehl braucht eine kennung',
        }, status: 400);
      }
      final ergebnis = await b.db.transaction(() async {
        final gespeichert = await b.db
            .customSelect(
              'SELECT antwort FROM pv_erledigt WHERE kennung = ?',
              variables: [Variable<String>(kennung)],
            )
            .getSingleOrNull();
        if (gespeichert != null) {
          final antwort = gespeichert.readNullable<String>('antwort');
          return antwort == null
              ? <String, Object?>{'kennung': kennung, 'ok': true, 'schon': true}
              : <String, Object?>{
                  ...(jsonDecode(antwort) as Map).cast<String, Object?>(),
                  'schon': true,
                };
        }
        Map<String, Object?> antwort;
        try {
          antwort = await b.db.transaction(() async {
            final befehl = Befehl.ausJson(eintrag);
            final roh = eintrag['basis'];
            if (roh != null &&
                (roh is! List || roh.length > Abgleichsgrenzen.basisZeilen)) {
              throw const FormatException('pv_sync_basis');
            }
            final basis = [
              for (final r in roh as List? ?? const [])
                Befehlsbasis.ausJson((r as Map).cast<String, Object?>()),
            ];
            if (!await Befehlsbasis.passt(b.protokoll, basis)) {
              return <String, Object?>{
                'kennung': kennung,
                'ok': false,
                'fehler': 'pv_sync_konflikt',
                'konflikt': true,
              };
            }
            final r = await b.db.fuehreAus(befehl);
            return <String, Object?>{
              'kennung': kennung,
              'ok': true,
              'ergebnis': ergebnisAlsJson(r),
            };
          }, requireNew: true);
        } on Object {
          antwort = {
            'kennung': kennung,
            'ok': false,
            'fehler': 'pv_befehl_abgelehnt',
          };
        }
        await b.db.customStatement(
          'INSERT INTO pv_erledigt (kennung, stand, am, antwort) VALUES (?, '
          '(SELECT coalesce(max(seq), 0) FROM pv_aenderungen), ?, ?)',
          [kennung, DateTime.now().millisecondsSinceEpoch, jsonEncode(antwort)],
        );
        return antwort;
      });
      ergebnisse.add(ergebnis);
    }
    return _json({
      'ergebnisse': ergebnisse,
      'stand': await b.protokoll.stand(),
    });
  }

  /// Eine Datei der Bibliothek nach ihrem Pfad (wie in der Datenbank):
  /// Miniaturen, Vorschauen, Originale, Gesichter, Masken … Mit `Range`.
  Future<Response> datei(Request anfrage, String pfad) async {
    final b = await _bib(anfrage);
    final relativ = Uri.decodeComponent(pfad);
    final ziel = File(p.normalize(p.join(b.pfade.root.path, relativ)));
    if (relativ.isEmpty ||
        p.isAbsolute(relativ) ||
        !p.isWithin(b.pfade.root.path, ziel.path) ||
        !await ziel.exists()) {
      return Response.notFound(null);
    }
    return dateiAntwort(anfrage, ziel);
  }

  /// Ein Gerät legt eine abgeleitete Datei ab – das Bild einer Entwicklung,
  /// eine Maske, einen Schnitt (Issue #109). Erst die Datei, dann der
  /// Befehl, der auf sie zeigt: So sieht kein anderes Gerät je einen Pfad,
  /// hinter dem nichts liegt. Nur in die Ordner aus [abgeleiteteOrdner],
  /// nie darüber hinaus; geschrieben wird neben das Ziel und dann getauscht.
  Future<Response> dateiAblegen(Request anfrage, String pfad) async {
    final b = await _bib(anfrage);
    final relativ = Uri.decodeComponent(pfad);
    final teile = p.posix.split(relativ);
    final ziel = File(p.normalize(p.join(b.pfade.root.path, relativ)));
    if (relativ.isEmpty ||
        p.isAbsolute(relativ) ||
        teile.length != 2 ||
        !abgeleiteteOrdner.contains(teile.first) ||
        teile.last.startsWith('.') ||
        !p.isWithin(b.pfade.root.path, ziel.path) ||
        !p.equals(ziel.parent.path, p.join(b.pfade.root.path, teile.first))) {
      return _json({'fehler': 'dorthin legt der Server nichts'}, status: 403);
    }
    final laenge = int.tryParse(anfrage.headers['content-length'] ?? '');
    if (laenge == null || laenge <= 0) {
      return _json({'fehler': 'Content-Length fehlt'}, status: 411);
    }
    if (laenge > hoechstensAbgeleitet) {
      return _json({'fehler': 'zu gross'}, status: 413);
    }
    await ziel.parent.create(recursive: true);
    // Jede Anfrage besitzt ihren eigenen Schreiber. Das Umbenennen eines
    // gemeinsamen .teil-Pfads liesse andere offene Schreiber das fertige
    // Ziel nachträglich verändern.
    final teil = File('${ziel.path}.${const Uuid().v4()}.teil');
    final aus = teil.openWrite();
    var bytes = 0;
    try {
      await aus.addStream(
        anfrage.read().map((stueck) {
          bytes += stueck.length;
          if (bytes > laenge) {
            throw const FormatException('mehr als angekündigt');
          }
          return stueck;
        }),
      );
      await aus.close();
      if (bytes != laenge) {
        throw const FormatException('weniger als angekündigt');
      }
      await _uebernehme(teil, ziel, b.db, relativ);
    } catch (e) {
      await aus.close().catchError((_) {});
      if (await teil.exists()) await teil.delete();
      return _json({'fehler': 'unvollständig: $e'}, status: 400);
    }
    return Response(204);
  }
}

/// Mehr nimmt der Server als abgeleitete Datei nicht an – ein geschnittenes
/// Video ist das Grösste, was hier kommt.
const hoechstensAbgeleitet = 2 * 1024 * 1024 * 1024;

/// Wohin ein Gerät Dateien legen darf: nur Abgeleitetes. Originale kommen
/// über den Import, Miniaturen und Vorschauen rechnet der Server selbst.
const abgeleiteteOrdner = {'developed', 'masks', 'luts', 'trimmed', 'restored'};

/// Was ein Befehl zurückgibt, als JSON.
Object? ergebnisAlsJson(Object? e) => switch (e) {
  null || bool() || num() || String() => e,
  DateTime() => e.toIso8601String(),
  Enum() => e.name,
  List() => [for (final x in e) ergebnisAlsJson(x)],
  _ => e.toString(),
};

/// Ein Abzug einer Bibliothek, den eine oder mehrere Antworten ausliefern.
class _Abzug {
  _Abzug(this.stand, this.ordner, this.datei, this.laenge, this._weg);

  /// Der Stand des Protokolls, als er entstand.
  final int stand;
  final Directory ordner;
  final File datei;
  final int laenge;
  final void Function() _weg;
  var _nutzer = 0;
  var _geloescht = false;

  /// Eine weitere Antwort liefert ihn aus – `false`, wenn er schon weg ist.
  bool nimm() {
    if (_geloescht) return false;
    _nutzer++;
    return true;
  }

  /// Eine Antwort ist fertig; die letzte löscht ihn.
  Future<void> gibFrei() async {
    if (--_nutzer > 0 || _geloescht) return;
    _geloescht = true;
    _weg();
    if (await ordner.exists()) await ordner.delete(recursive: true);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

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
  });

  final Bibliotheken bibliotheken;

  /// Wie oft eine wartende Abfrage nachsieht, ob sich etwas getan hat.
  final Duration takt;

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
    final ende = DateTime.now().add(warten);
    while (await b.protokoll.stand() <= nach && DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(takt);
    }
    final s = await b.protokoll.seit(nach, anzahl: anzahl);
    return _json({
      'bis': s.bis,
      'mehr': s.mehr,
      'zeilen': [for (final z in s.zeilen) z.alsJson()],
    });
  }

  /// `{schluessel: [{t, s}]}` → `{zeilen}`: der jetzige Stand einzelner
  /// Zeilen – für ein Gerät, das prüft, ob seine vorweggenommenen
  /// Änderungen so auch auf dem Server stehen.
  Future<Response> zeilen(Request anfrage) async {
    final b = await _bib(anfrage);
    final k = jsonDecode(await anfrage.readAsString());
    final liste = k is Map ? k['schluessel'] : null;
    if (liste is! List || liste.length > 5000) {
      return _json({'fehler': 'schluessel fehlt'}, status: 400);
    }
    final tabellen = (await b.protokoll.abgeglicheneTabellen()).toSet();
    final aus = <Map<String, Object?>>[];
    for (final e in liste.cast<Map>()) {
      final t = e['t'];
      if (t is! String || !tabellen.contains(t)) continue;
      final z = await b.protokoll.lies(t, [
        for (final w in (e['s']! as List)) wertAusJson(w),
      ]);
      aus.add(z.alsJson());
    }
    return _json({'zeilen': aus});
  }

  /// Die ganze Bibliothek als SQLite-Datei – der Anfang einer Kopie. Ihr
  /// eigenes Protokoll reist mit; dessen höchste Nummer ist der Stand, ab
  /// dem das Gerät weiterliest.
  Future<Response> abzug(Request anfrage) async {
    final b = await _bib(anfrage);
    final tmp = await Directory.systemTemp.createTemp('pv_abzug_');
    final datei = File(p.join(tmp.path, 'library.sqlite'));
    await b.db.customStatement('VACUUM INTO ?', [datei.path]);
    Stream<List<int>> undWeg() async* {
      try {
        yield* datei.openRead();
      } finally {
        await tmp.delete(recursive: true);
      }
    }

    return Response.ok(
      undWeg(),
      headers: {
        'content-type': 'application/vnd.sqlite3',
        'content-length': '${await datei.length()}',
        'cache-control': 'no-store',
      },
    );
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
      final ergebnis = await b.db.fuehreAus(befehl);
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
      final kennung = eintrag?['kennung'];
      if (eintrag == null || kennung is! String || kennung.isEmpty) {
        return _json({
          'fehler': 'jeder Befehl braucht eine kennung',
        }, status: 400);
      }
      if (await _erledigt(b, kennung)) {
        ergebnisse.add({'kennung': kennung, 'ok': true, 'schon': true});
        continue;
      }
      try {
        final befehl = Befehl.ausJson(eintrag);
        final ergebnis = await b.db.transaction(() async {
          final r = await b.db.fuehreAus(befehl);
          await _merke(b, kennung);
          return r;
        });
        ergebnisse.add({
          'kennung': kennung,
          'ok': true,
          'ergebnis': ergebnisAlsJson(ergebnis),
        });
      } on Object catch (fehler) {
        // Auch ein gescheiterter Befehl ist erledigt: Ihn noch einmal zu
        // schicken, änderte nichts daran.
        await _merke(b, kennung);
        ergebnisse.add({'kennung': kennung, 'ok': false, 'fehler': '$fehler'});
      }
    }
    return _json({
      'ergebnisse': ergebnisse,
      'stand': await b.protokoll.stand(),
    });
  }

  Future<bool> _erledigt(Bibliothek b, String kennung) async =>
      (await b.db
          .customSelect(
            'SELECT 1 FROM pv_erledigt WHERE kennung = ?',
            variables: [Variable<String>(kennung)],
          )
          .getSingleOrNull()) !=
      null;

  Future<void> _merke(Bibliothek b, String kennung) => b.db.customStatement(
    'INSERT OR IGNORE INTO pv_erledigt (kennung, stand, am) '
    'VALUES (?, (SELECT coalesce(max(seq), 0) FROM pv_aenderungen), ?)',
    [kennung, DateTime.now().millisecondsSinceEpoch],
  );

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
}

/// Was ein Befehl zurückgibt, als JSON.
Object? ergebnisAlsJson(Object? e) => switch (e) {
  null || bool() || num() || String() => e,
  DateTime() => e.toIso8601String(),
  Enum() => e.name,
  _ => e.toString(),
};

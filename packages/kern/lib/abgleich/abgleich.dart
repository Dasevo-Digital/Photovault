import 'grenzen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' as roh;

import '../db/database.dart';
import '../protokoll.dart' as meldung;
import 'abgleichsplan.dart';
import 'protokoll.dart';
import 'befehlsbasis.dart';
import 'abgleichsfall.dart';
import 'package:cryptography/cryptography.dart';

export 'abgleichsfall.dart';

import 'verbindung.dart';
import 'verbindungsdatei.dart';

part 'abgleichsfaelle.dart';

/// Wie es um den Abgleich steht – für die Anzeige.
class Abgleichszustand {
  const Abgleichszustand({
    required this.erreichbar,
    required this.ausstehend,
    this.abgelehnt = const [],
    this.abgemeldet = false,
    this.serverSchema,
    this.hierSchema,
    this.ungeklaert = false,
    this.faelle = 0,
    this.serverOhneKonfliktpruefung = false,
  });

  /// Ob der Server zuletzt geantwortet hat.
  final bool erreichbar;

  /// Noch nicht gefragt: Gleich nach dem Start ist der Server weder
  /// erreichbar noch nicht erreichbar. Vorher stand hier „nicht
  /// erreichbar“, und jede App zeigte das bei jedem Start ein paar
  /// Sekunden lang – bis die erste Runde samt allen neuen Änderungen
  /// durch war.
  final bool ungeklaert;

  /// Befehle, die der Server noch nicht bestätigt hat.
  final int ausstehend;
  final int faelle;
  final bool serverOhneKonfliktpruefung;

  /// Befehle, die der Server abgelehnt hat (Art und Grund) – ihre Wirkung
  /// ist zurückgenommen.
  final List<String> abgelehnt;

  /// Das Gerät ist beim Server nicht mehr angemeldet.
  final bool abgemeldet;

  /// Der Schemastand des Servers, wenn er nicht zu dem dieser Kopie passt –
  /// dann gleicht nichts mehr ab, bis App oder Server aktualisiert sind.
  /// Ist er höher, ist die App zu alt; ist er niedriger, der Server.
  final int? serverSchema;

  /// Der Schemastand dieser Kopie, wenn [serverSchema] gesetzt ist.
  final int? hierSchema;

  /// Ob die Schemastände nicht zusammenpassen …
  bool get schemaAnders => serverSchema != null;

  /// … und ob es an der App liegt (sonst am Server).
  bool get appZuAlt => (serverSchema ?? 0) > (hierSchema ?? 0);
}

/// Hält die Kopie einer Bibliothek auf einem Gerät mit dem Server gleich.
///
/// **Lesen:** Die Kopie ist eine gewöhnliche Bibliothek (dasselbe Schema
/// wie ohne Server); sie entsteht aus einem Abzug ([holeAbzug]) und folgt
/// danach dem Protokoll des Servers.
///
/// **Schreiben:** Jeder Befehl wird sofort hier angewandt – vorweggenommen,
/// damit die Oberfläche nicht auf den Server wartet – und in die
/// Warteschlange `pv_ausgang` gestellt. Welche Zeilen er dabei geändert
/// hat, schreibt das Protokoll unter seiner Nummer mit. Ist der Server
/// erreichbar, gehen die Befehle im Stapel hinaus; sonst warten sie, auch
/// über einen Neustart hinweg.
///
/// **Angleichen:** Hat der Server einen Befehl ausgeführt und ist das
/// Protokoll bis dorthin abgeholt, steht seine Wirkung so in der Kopie,
/// wie der Server sie sieht. Was die Vorwegnahme darüber hinaus geändert
/// hat – eine Zeile mit einer Nummer, die der Server anders vergab, die
/// Wirkung eines abgelehnten Befehls –, holt [gleicheAn] beim Server nach
/// und überschreibt es. Danach ist die Kopie wieder genau der Stand des
/// Servers.
///
/// **Obenauf:** Ändert der Server eine Zeile, die ein noch nicht
/// bestätigter Befehl vorweggenommen hat, überschriebe das Abholen die
/// Vorwegnahme. Die offenen Befehle werden deshalb danach noch einmal
/// angewandt – dieselbe Reihenfolge wie später auf dem Server.
class Abgleich {
  Abgleich(this.db, this.verbindung, {SecretKey? fallschluessel})
    : protokoll = Protokoll(db),
      _festerFallschluessel = fallschluessel;

  final SecretKey? _festerFallschluessel;

  final AppDatabase db;
  final Serververbindung verbindung;
  final Protokoll protokoll;
  final Zone _betriebszone = Zone.current;

  final _zustand = StreamController<Abgleichszustand>.broadcast();
  Abgleichszustand _letzter = const Abgleichszustand(
    erreichbar: false,
    ausstehend: 0,
    ungeklaert: true,
  );

  /// Wie es steht; der letzte Stand in [zustandJetzt].
  Stream<Abgleichszustand> get zustand => _zustand.stream;
  Abgleichszustand get zustandJetzt => _letzter;

  bool _laeuft = false;
  Future<void>? _schleife;
  Future<void>? _senden;
  Future<void>? _sendelauf;
  bool _serverOhneKonfliktpruefung = false;
  Completer<void>? _wecker;

  /// Tritt mit [beende] ein und bricht die wartende Abfrage ab – sonst
  /// hinge das Beenden bis zu 25 s an ihr.
  final _halt = Completer<void>();
  final _abgelehnt = <String>[];

  /// Tritt mit [jetzt] ein und bricht die wartende Abfrage ab.
  var _neuAnfangen = Completer<void>();

  /// Ob [jetzt] die Abfrage abgebrochen hat – dann ist das kein Aussetzer.
  var _selbstAbgebrochen = false;

  /// Wie lange nach einem Aussetzer gewartet wird; verdoppelt sich bis 60 s.
  var _pause = const Duration(seconds: 2);

  /// Gleich noch einmal fragen – etwa wenn die App aus dem Hintergrund
  /// zurückkommt.
  ///
  /// Im Hintergrund reisst auf dem Telefon die wartende Abfrage ab, ohne
  /// dass jemand es merkt. Zurück in der App wartete die Schleife dann
  /// erst ab, bis die Anfrage nach bis zu 55 s aufgab, oder sie schlief
  /// nach einem Aussetzer ihre Pause aus (bis 60 s) – und so lange stand
  /// „Server nicht erreichbar“ da, obwohl er längst wieder antwortete.
  void jetzt() {
    if (!_laeuft) return;
    _pause = const Duration(seconds: 2);
    _selbstAbgebrochen = true;
    if (!_neuAnfangen.isCompleted) _neuAnfangen.complete();
    if (_wecker case final w? when !w.isCompleted) w.complete();
  }

  /// Lädt die Bibliothek vom Server nach [ziel] und bereitet sie als Kopie
  /// vor. Gibt den Stand zurück, ab dem sie dem Server folgt.
  static Future<int> holeAbzug(Serververbindung v, File ziel) async {
    final teil = File('${ziel.path}.abzug');
    await v.ladeHerunter('api/v1/abgleich/abzug', teil);
    final db = roh.sqlite3.open(teil.path);
    final int stand;
    try {
      stand =
          db
                  .select(
                    'SELECT coalesce(max(seq), 0) AS s FROM pv_aenderungen',
                  )
                  .first['s']
              as int;
      // Das Protokoll des Servers gehört dem Server; hier beginnt ein
      // eigenes – für vorweggenommene Befehle.
      db.execute('DELETE FROM pv_aenderungen');
      db.execute('UPDATE pv_schalter SET mitschreiben = 0');
      db.execute('DROP TABLE IF EXISTS pv_erledigt');
      final da = {
        for (final z in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          z['name'] as String,
      };
      for (final t in Abgleichsplan.nurLokal) {
        if (da.contains(t)) db.execute('DELETE FROM "$t"');
      }
      _richteTabellenEin((sql, [werte = const []]) => db.execute(sql, werte));
      db.execute('UPDATE pv_abgleich SET stand = ? WHERE id = 0', [stand]);
    } finally {
      db.close();
    }
    await teil.rename(ziel.path);
    return stand;
  }

  static void _richteTabellenEin(
    void Function(String sql, [List<Object?> werte]) fuehreAus,
  ) {
    fuehreAus(
      'CREATE TABLE IF NOT EXISTS pv_abgleich ('
      'id INTEGER PRIMARY KEY CHECK (id = 0), stand INTEGER NOT NULL)',
    );
    fuehreAus('INSERT OR IGNORE INTO pv_abgleich (id, stand) VALUES (0, 0)');
    fuehreAus(
      'CREATE TABLE IF NOT EXISTS pv_ausgang ('
      'nr INTEGER PRIMARY KEY AUTOINCREMENT, '
      'kennung TEXT NOT NULL UNIQUE, befehl TEXT NOT NULL, '
      'bestaetigt INTEGER, ok INTEGER, fehler TEXT)',
    );
  }

  /// Richtet die Kopie ein und lenkt Befehle durch den Abgleich. Erst
  /// [starte] verbindet sich mit dem Server.
  Future<void> richteEin() async {
    await protokoll.richteEin(mitschreiben: 0);
    await protokoll.richteSchutzEin();
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_abgleich ('
      'id INTEGER PRIMARY KEY CHECK (id = 0), stand INTEGER NOT NULL)',
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO pv_abgleich (id, stand) VALUES (0, 0)',
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_ausgang ('
      'nr INTEGER PRIMARY KEY AUTOINCREMENT, '
      'kennung TEXT NOT NULL UNIQUE, befehl TEXT NOT NULL, '
      'bestaetigt INTEGER, ok INTEGER, fehler TEXT)',
    );
    final spalten = {
      for (final r
          in await db.customSelect('PRAGMA table_info(pv_ausgang)').get())
        r.read<String>('name'),
    };
    for (final e in {
      'basis': "TEXT NOT NULL DEFAULT '[]'",
      'angelegt': 'INTEGER NOT NULL DEFAULT 0',
    }.entries) {
      if (!spalten.contains(e.key)) {
        await db.customStatement(
          'ALTER TABLE pv_ausgang ADD COLUMN ${e.key} ${e.value}',
        );
      }
    }
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_abgleichsfaelle ('
      'kennung TEXT PRIMARY KEY, am INTEGER NOT NULL, grund TEXT NOT NULL, inhalt TEXT NOT NULL)',
    );
    // Ältere Warteschlangen trugen den Befehl im Klartext. Deren
    // ursprüngliche Konfliktbasis lässt sich nachträglich nicht ableiten,
    // der gespeicherte Inhalt wird dennoch mit dem Geräteschlüssel geschützt.
    await db.transaction(() async {
      for (final r
          in await db.customSelect('SELECT nr, befehl FROM pv_ausgang').get()) {
        final j = (jsonDecode(r.read<String>('befehl')) as Map)
            .cast<String, Object?>();
        if (j['art'] is String) {
          final inhalt = await _verpackeFall({'befehl': j, 'basis': const []});
          await db.customStatement(
            'UPDATE pv_ausgang SET befehl = ? WHERE nr = ?',
            [inhalt, r.read<int>('nr')],
          );
        }
      }
    });
    db.umleitung = vorwegnehmen;
    await _melde();
  }

  /// Gleicht im Hintergrund ab, bis [beende].
  void starte() {
    if (_laeuft) return;
    _laeuft = true;
    _schleife = _laufe();
  }

  Future<void> beende() async {
    _laeuft = false;
    if (_wecker case final w? when !w.isCompleted) w.complete();
    if (!_halt.isCompleted) _halt.complete();
    await _schleife;
    await _senden;
    await _sendelauf;
    db.umleitung = null;
    await _zustand.close();
  }

  // --- Schreiben ---------------------------------------------------------

  /// Wendet [befehl] hier an und stellt ihn in die Warteschlange.
  Future<T> _stelleEin<T>(Befehl<T> befehl) => db.transaction(() async {
    final basis = await Befehlsbasis.ermittle(protokoll, befehl);
    final draht = {
      'kennung': '0' * 32,
      ...befehl.alsJson(),
      'basis': [for (final b in basis) b.alsJson()],
    };
    if (utf8.encode(jsonEncode(draht)).length > Abgleichsgrenzen.befehlBytes) {
      throw const FormatException('pv_sync_auswahl');
    }
    final vorschau = await _verpackeFall({
      'befehl': befehl.alsJson(),
      'basis': [for (final b in basis) b.vorschauJson()],
    });
    final nr = await db.customInsert(
      'INSERT INTO pv_ausgang (kennung, befehl, basis, angelegt) VALUES (?, ?, ?, ?)',
      variables: [
        Variable<String>(_neueKennung()),
        Variable<String>(vorschau),
        Variable<String>(jsonEncode([for (final b in basis) b.alsJson()])),
        Variable<int>(DateTime.now().millisecondsSinceEpoch),
      ],
    );
    return _mitSchalter(nr, () => befehl.anwenden(db));
  });

  Future<T> vorwegnehmen<T>(Befehl<T> befehl) async {
    final ergebnis = await _stelleEin(befehl);
    await _melde();
    sendeBald();
    return ergebnis;
  }

  Future<T> _mitSchalter<T>(int nr, Future<T> Function() arbeit) async {
    await db.customStatement('UPDATE pv_schalter SET mitschreiben = ?', [nr]);
    try {
      return await arbeit();
    } finally {
      await db.customStatement('UPDATE pv_schalter SET mitschreiben = 0');
    }
  }

  /// Schickt die Warteschlange bald – einmal, auch wenn mehrere fragen.
  void sendeBald() {
    if (!_laeuft || _senden != null) return;
    _senden = _betriebszone
        .run(sende)
        .catchError((Object _) {})
        .whenComplete(() => _senden = null);
  }

  /// Schickt alle unbestätigten Befehle im Stapel.
  Future<void> sende() =>
      _sendelauf ??= _sende().whenComplete(() => _sendelauf = null);

  Future<void> _sende() async {
    while (true) {
      final offen = await db
          .customSelect(
            'SELECT kennung, befehl, basis, angelegt FROM pv_ausgang '
            'WHERE bestaetigt IS NULL ORDER BY nr LIMIT 100',
          )
          .get();
      if (offen.isEmpty) return;
      if (offen.any((r) => r.read<String>('basis') != '[]')) {
        final z = await verbindung.hole('api/v1/zustand');
        _serverOhneKonfliktpruefung =
            (z['funktionen'] as Map?)?['konfliktpruefung'] != 1;
        if (_serverOhneKonfliktpruefung) {
          await _melde(erreichbar: true);
          return;
        }
      }
      final stapel = <Map<String, Object?>>[];
      var bytes = utf8.encode('{"befehle":[]}').length;
      for (final z in offen) {
        final eintrag = <String, Object?>{
          'kennung': z.read<String>('kennung'),
          ...((await _leseAuftrag(z.read<String>('befehl')))['befehl'] as Map)
              .cast<String, Object?>(),
          'basis': jsonDecode(z.read<String>('basis')),
        };
        final groesse = utf8.encode(jsonEncode(eintrag)).length;
        if (groesse > Abgleichsgrenzen.befehlBytes) {
          // Altbestand kann vor Einführung des Budgets entstanden sein.
          // Er bleibt als Fall erhalten und blockiert spätere Befehle nicht.
          await db.transaction(() async {
            await db.customStatement(
              'UPDATE pv_ausgang SET bestaetigt = ?, ok = 0, fehler = ? WHERE kennung = ?',
              [await _stand(), 'pv_sync_auswahl', z.read<String>('kennung')],
            );
            await db.customStatement(
              'INSERT OR IGNORE INTO pv_abgleichsfaelle (kennung, am, grund, inhalt) VALUES (?, ?, ?, ?)',
              [
                z.read<String>('kennung'),
                z.read<int>('angelegt'),
                'pv_sync_auswahl',
                await _verpackeFall(
                  await _leseAuftrag(z.read<String>('befehl')),
                ),
              ],
            );
          });
          continue;
        }
        if (bytes + groesse + 1 > Abgleichsgrenzen.stapelBytes) break;
        stapel.add(eintrag);
        bytes += groesse + 1;
      }
      if (stapel.isEmpty) {
        await _melde();
        continue;
      }
      final antwort = await verbindung.schicke('api/v1/befehle', {
        'befehle': stapel,
      });
      final ergebnisse = (antwort['ergebnisse']! as List).cast<Map>();
      final gesendet = stapel.map((z) => z['kennung']).toSet();
      final erhalten = ergebnisse.map((z) => z['kennung']).toSet();
      if (ergebnisse.length != gesendet.length ||
          erhalten.length != gesendet.length ||
          !erhalten.containsAll(gesendet)) {
        throw Serverfehler(502, 'pv_sync_antwort');
      }
      final stand = antwort['stand']! as int;
      await db.transaction(() async {
        for (final e in ergebnisse) {
          final ok = e['ok'] == true;
          await db.customStatement(
            'UPDATE pv_ausgang SET bestaetigt = ?, ok = ?, fehler = ? '
            'WHERE kennung = ?',
            [stand, ok ? 1 : 0, e['fehler'], e['kennung']],
          );
          if (!ok) {
            _abgelehnt.add('${e['fehler']}');
            final quelle = offen
                .where((r) => r.read<String>('kennung') == e['kennung'])
                .firstOrNull;
            if (quelle != null) {
              await db.customStatement(
                'INSERT OR IGNORE INTO pv_abgleichsfaelle (kennung, am, grund, inhalt) VALUES (?, ?, ?, ?)',
                [
                  e['kennung'],
                  quelle.read<int>('angelegt'),
                  e['konflikt'] == true
                      ? 'pv_sync_konflikt'
                      : 'pv_befehl_abgelehnt',
                  await _verpackeFall(
                    await _leseAuftrag(quelle.read<String>('befehl')),
                  ),
                ],
              );
            }
          }
        }
      });
      await _melde(erreichbar: true);
    }
  }

  // --- Lesen -------------------------------------------------------------

  Future<int> _stand() async =>
      (await db
              .customSelect('SELECT stand FROM pv_abgleich WHERE id = 0')
              .getSingle())
          .read<int>('stand');

  /// Holt die Änderungen seit dem eigenen Stand – mit [warten] als Long-Poll
  /// – und wendet sie an; danach [gleicheAn].
  Future<void> empfange({Duration warten = Duration.zero}) async {
    var stand = await _stand();
    var w = warten;
    while (true) {
      final a = await verbindung.hole(
        'api/v1/abgleich/aenderungen',
        parameter: {
          'nach': '$stand',
          'anzahl': '500',
          'warten': '${w.inSeconds}',
        },
        zeitlimit: w + const Duration(seconds: 30),
        abbruch: w == Duration.zero
            ? null
            : Future.any([_halt.future, _neuAnfangen.future]),
      );
      // Nach einem Aussetzer: erreichbar, sobald er wieder antwortet.
      if (!_letzter.erreichbar) await _melde(erreichbar: true);
      final zeilen = [
        for (final z in (a['zeilen']! as List).cast<Map>())
          Zeilenstand.ausJson(z.cast<String, Object?>()),
      ];
      final bis = a['bis']! as int;
      if (zeilen.isNotEmpty || bis != stand) {
        final tabellen = await db.transaction(() async {
          if (bis <= await _stand()) return <String>{};
          final t = await protokoll.frei(() => protokoll.wendeAn(zeilen));
          await db.customStatement(
            'UPDATE pv_abgleich SET stand = ? WHERE id = 0',
            [bis],
          );
          if (await _beruehrtOffenes(zeilen)) {
            t.addAll(await _wendeOffeneAn());
          }
          return t;
        });
        _meldeAenderung(tabellen);
      }
      stand = bis;
      w = Duration.zero;
      if (a['mehr'] != true) break;
    }
    await gleicheAn();
  }

  /// Ob [zeilen] eine Zeile treffen, die ein unbestätigter Befehl
  /// vorweggenommen hat.
  Future<bool> _beruehrtOffenes(List<Zeilenstand> zeilen) async {
    if (zeilen.isEmpty) return false;
    final offen = await _schluesselVon(
      'SELECT nr FROM pv_ausgang WHERE bestaetigt IS NULL',
    );
    if (offen.isEmpty) return false;
    return zeilen.any(
      (z) => offen.contains('${z.tabelle}\u0000${jsonEncode(z.schluessel)}'),
    );
  }

  /// Wendet die unbestätigten Befehle noch einmal an, in ihrer Reihenfolge.
  Future<Set<String>> _wendeOffeneAn() async {
    final tabellen = <String>{};
    for (final z
        in await db
            .customSelect(
              'SELECT nr, befehl FROM pv_ausgang WHERE bestaetigt IS NULL '
              'ORDER BY nr',
            )
            .get()) {
      final befehl = Befehl.ausJson(
        ((await _leseAuftrag(z.read<String>('befehl')))['befehl'] as Map)
            .cast<String, Object?>(),
      );
      try {
        await _mitSchalter(z.read<int>('nr'), () => befehl.anwenden(db));
      } catch (e) {
        meldung.protokoll(
          'Vorwegnahme ${befehl.art} liess sich nicht wiederholen: $e',
        );
      }
    }
    for (final z
        in await db
            .customSelect('SELECT DISTINCT tabelle FROM pv_aenderungen')
            .get()) {
      tabellen.add(z.read<String>('tabelle'));
    }
    return tabellen;
  }

  /// Gleicht die Zeilen bestätigter Befehle mit dem Server ab, sobald das
  /// Protokoll bis zu ihrer Bestätigung abgeholt ist (siehe Klasse).
  Future<void> gleicheAn() async {
    final stand = await _stand();
    final fertig = [
      for (final z
          in await db
              .customSelect(
                'SELECT nr FROM pv_ausgang WHERE bestaetigt IS NOT NULL '
                'AND bestaetigt <= ?',
                variables: [Variable<int>(stand)],
              )
              .get())
        z.read<int>('nr'),
    ];
    if (fertig.isEmpty) return;
    final liste = fertig.join(',');
    // Zeilen, die ein noch offener Befehl ebenfalls vorweggenommen hat,
    // bleiben, wie sie sind – sonst verschwände dessen Wirkung, bis er
    // bestätigt ist.
    final offen = await _schluesselVon(
      'SELECT nr FROM pv_ausgang WHERE bestaetigt IS NULL OR bestaetigt > $stand',
    );
    final pruefen = <Map<String, Object?>>[];
    final gesehen = <String>{};
    for (final z
        in await db
            .customSelect(
              'SELECT DISTINCT tabelle, schluessel FROM pv_aenderungen '
              'WHERE ausgang IN ($liste)',
            )
            .get()) {
      final k =
          '${z.read<String>('tabelle')}\u0000${z.read<String>('schluessel')}';
      if (offen.contains(k) || !gesehen.add(k)) continue;
      pruefen.add({
        't': z.read<String>('tabelle'),
        's': jsonDecode(z.read<String>('schluessel')),
      });
    }
    final zeilen = <Zeilenstand>[];
    for (var i = 0; i < pruefen.length; i += 500) {
      final a = await verbindung.schicke('api/v1/abgleich/zeilen', {
        'schluessel': pruefen.sublist(i, min(i + 500, pruefen.length)),
      });
      zeilen.addAll([
        for (final z in (a['zeilen']! as List).cast<Map>())
          Zeilenstand.ausJson(z.cast<String, Object?>()),
      ]);
    }
    final tabellen = await db.transaction(() async {
      final t = await protokoll.frei(() => protokoll.wendeAn(zeilen));
      await db.customStatement(
        'DELETE FROM pv_aenderungen WHERE ausgang IN ($liste)',
      );
      await db.customStatement('DELETE FROM pv_ausgang WHERE nr IN ($liste)');
      return t;
    });
    _meldeAenderung(tabellen);
    await _melde();
  }

  Future<Set<String>> _schluesselVon(String nummern) async => {
    for (final z
        in await db
            .customSelect(
              'SELECT DISTINCT tabelle, schluessel FROM pv_aenderungen '
              'WHERE ausgang IN ($nummern)',
            )
            .get())
      '${z.read<String>('tabelle')}\u0000${z.read<String>('schluessel')}',
  };

  void _meldeAenderung(Set<String> tabellen) {
    if (tabellen.isEmpty) return;
    db.notifyUpdates({for (final t in tabellen) TableUpdate(t)});
  }

  // --- Schleife ----------------------------------------------------------

  Future<void> _laufe() async {
    // Die erste Runde wartet nicht: Gibt es nichts Neues, kehrte die lange
    // Abfrage erst nach 25 s zurück – so lange stünde „verbindet …“ da,
    // obwohl der Server längst antwortet.
    var warten = Duration.zero;
    var geprueft = false;
    while (_laeuft) {
      // Ein [jetzt] aus der letzten Runde gilt als erledigt – sonst bräche
      // die nächste wartende Abfrage gleich wieder ab.
      if (_neuAnfangen.isCompleted) _neuAnfangen = Completer<void>();
      try {
        if (!geprueft) {
          // Ein anderes Schema hiesse, Zeilen anzuwenden, deren Spalten es
          // hier nicht gibt (oder umgekehrt) – dann lieber gar nicht.
          final stand = await verbindung.hole('api/v1/abgleich/stand');
          final schema = stand['schema'];
          if (schema is int && schema != db.schemaVersion) {
            await _melde(erreichbar: true, serverSchema: schema);
            _laeuft = false;
            return;
          }
          geprueft = true;
          // Der Server hat geantwortet – das gilt ab jetzt, nicht erst,
          // wenn alles Neue geholt und eingespielt ist.
          await _melde(erreichbar: true);
        }
        await sende();
        await empfange(warten: warten);
        warten = const Duration(seconds: 25);
        _pause = const Duration(seconds: 2);
        _selbstAbgebrochen = false;
        await _melde(erreichbar: true);
      } on KeineVerbindung {
        if (!_laeuft) return;
        warten = Duration.zero;
        // Selbst abgebrochen ([jetzt]): kein Aussetzer – gleich weiter.
        if (_selbstAbgebrochen) {
          _selbstAbgebrochen = false;
          continue;
        }
        await _melde(erreichbar: false);
        await _schlafe(_pause);
        _pause = Duration(seconds: min(_pause.inSeconds * 2, 60));
      } on Serverfehler catch (f) {
        if (f.abgemeldet) {
          await _melde(erreichbar: true, abgemeldet: true);
          _laeuft = false;
          return;
        }
        if (!_laeuft) return;
        warten = Duration.zero;
        meldung.protokoll('Abgleich: $f');
        await _schlafe(_pause);
        _pause = Duration(seconds: min(_pause.inSeconds * 2, 60));
      }
    }
  }

  Future<void> _schlafe(Duration d) async {
    final w = _wecker = Completer<void>();
    await Future.any([w.future, Future<void>.delayed(d)]);
    _wecker = null;
  }

  Future<void> _melde({
    bool? erreichbar,
    bool abgemeldet = false,
    int? serverSchema,
  }) async {
    if (_zustand.isClosed) return;
    final n =
        (await db
                .customSelect(
                  'SELECT count(*) AS n FROM pv_ausgang WHERE bestaetigt IS NULL',
                )
                .getSingle())
            .read<int>('n');
    _letzter = Abgleichszustand(
      erreichbar: erreichbar ?? _letzter.erreichbar,
      ausstehend: n,
      faelle:
          (await db
                  .customSelect('SELECT count(*) AS n FROM pv_abgleichsfaelle')
                  .getSingle())
              .read<int>('n'),
      serverOhneKonfliktpruefung: _serverOhneKonfliktpruefung,
      abgelehnt: List.unmodifiable(_abgelehnt),
      abgemeldet: abgemeldet,
      serverSchema: serverSchema,
      hierSchema: serverSchema == null ? null : db.schemaVersion,
      ungeklaert: erreichbar == null && _letzter.ungeklaert,
    );
    _zustand.add(_letzter);
  }

  static String _neueKennung() {
    final z = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        z.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}

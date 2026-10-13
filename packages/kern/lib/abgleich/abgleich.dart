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
import 'verbindung.dart';

/// Wie es um den Abgleich steht – für die Anzeige.
class Abgleichszustand {
  const Abgleichszustand({
    required this.erreichbar,
    required this.ausstehend,
    this.abgelehnt = const [],
    this.abgemeldet = false,
  });

  /// Ob der Server zuletzt geantwortet hat.
  final bool erreichbar;

  /// Befehle, die der Server noch nicht bestätigt hat.
  final int ausstehend;

  /// Befehle, die der Server abgelehnt hat (Art und Grund) – ihre Wirkung
  /// ist zurückgenommen.
  final List<String> abgelehnt;

  /// Das Gerät ist beim Server nicht mehr angemeldet.
  final bool abgemeldet;
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
  Abgleich(this.db, this.verbindung) : protokoll = Protokoll(db);

  final AppDatabase db;
  final Serververbindung verbindung;
  final Protokoll protokoll;

  final _zustand = StreamController<Abgleichszustand>.broadcast();
  Abgleichszustand _letzter = const Abgleichszustand(
    erreichbar: false,
    ausstehend: 0,
  );

  /// Wie es steht; der letzte Stand in [zustandJetzt].
  Stream<Abgleichszustand> get zustand => _zustand.stream;
  Abgleichszustand get zustandJetzt => _letzter;

  bool _laeuft = false;
  Future<void>? _schleife;
  Future<void>? _senden;
  Completer<void>? _wecker;
  final _abgelehnt = <String>[];

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
    db.umleitung = vorwegnehmen;
    await _melde(erreichbar: false);
  }

  /// Gleicht im Hintergrund ab, bis [beende].
  void starte() {
    if (_laeuft) return;
    _laeuft = true;
    _schleife = _laufe();
  }

  Future<void> beende() async {
    _laeuft = false;
    _wecker?.complete();
    await _schleife;
    await _senden;
    db.umleitung = null;
    await _zustand.close();
  }

  // --- Schreiben ---------------------------------------------------------

  /// Wendet [befehl] hier an und stellt ihn in die Warteschlange.
  Future<T> vorwegnehmen<T>(Befehl<T> befehl) async {
    final ergebnis = await db.transaction(() async {
      final nr = await db.customInsert(
        'INSERT INTO pv_ausgang (kennung, befehl) VALUES (?, ?)',
        variables: [
          Variable<String>(_neueKennung()),
          Variable<String>(jsonEncode(befehl.alsJson())),
        ],
      );
      return _mitSchalter(nr, () => befehl.anwenden(db));
    });
    unawaited(_melde());
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
    _senden = sende()
        .catchError((Object _) {})
        .whenComplete(() => _senden = null);
  }

  /// Schickt alle unbestätigten Befehle im Stapel.
  Future<void> sende() async {
    while (true) {
      final offen = await db
          .customSelect(
            'SELECT kennung, befehl FROM pv_ausgang '
            'WHERE bestaetigt IS NULL ORDER BY nr LIMIT 100',
          )
          .get();
      if (offen.isEmpty) return;
      final antwort = await verbindung.schicke('api/v1/befehle', {
        'befehle': [
          for (final z in offen)
            {
              'kennung': z.read<String>('kennung'),
              ...(jsonDecode(z.read<String>('befehl')) as Map),
            },
        ],
      });
      final stand = antwort['stand']! as int;
      await db.transaction(() async {
        for (final e in (antwort['ergebnisse']! as List).cast<Map>()) {
          final ok = e['ok'] == true;
          await db.customStatement(
            'UPDATE pv_ausgang SET bestaetigt = ?, ok = ?, fehler = ? '
            'WHERE kennung = ?',
            [stand, ok ? 1 : 0, e['fehler'], e['kennung']],
          );
          if (!ok) _abgelehnt.add('${e['fehler']}');
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
      );
      final zeilen = [
        for (final z in (a['zeilen']! as List).cast<Map>())
          Zeilenstand.ausJson(z.cast<String, Object?>()),
      ];
      final bis = a['bis']! as int;
      if (zeilen.isNotEmpty || bis != stand) {
        final tabellen = await db.transaction(() async {
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
        (jsonDecode(z.read<String>('befehl')) as Map).cast<String, Object?>(),
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
    var pause = const Duration(seconds: 2);
    while (_laeuft) {
      try {
        await sende();
        await empfange(warten: const Duration(seconds: 25));
        pause = const Duration(seconds: 2);
        await _melde(erreichbar: true);
      } on KeineVerbindung {
        await _melde(erreichbar: false);
        await _schlafe(pause);
        pause = Duration(seconds: min(pause.inSeconds * 2, 60));
      } on Serverfehler catch (f) {
        if (f.abgemeldet) {
          await _melde(erreichbar: true, abgemeldet: true);
          _laeuft = false;
          return;
        }
        meldung.protokoll('Abgleich: $f');
        await _schlafe(pause);
        pause = Duration(seconds: min(pause.inSeconds * 2, 60));
      }
    }
  }

  Future<void> _schlafe(Duration d) async {
    final w = _wecker = Completer<void>();
    await Future.any([w.future, Future<void>.delayed(d)]);
    _wecker = null;
  }

  Future<void> _melde({bool? erreichbar, bool abgemeldet = false}) async {
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
      abgelehnt: List.unmodifiable(_abgelehnt),
      abgemeldet: abgemeldet,
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

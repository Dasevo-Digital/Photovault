import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Was die Sicherung der Kamerarolle sich merkt – in einer eigenen kleinen
/// Datei neben der Kopie der Bibliothek (`sicherung.sqlite`).
///
/// **Warum nicht nur fragen, was der Server hat.** Der Server kennt seine
/// Dateien nach Prüfsumme; wer etwas endgültig löscht, löscht auch die.
/// Ohne eigenes Gedächtnis lüde das Telefon jedes gelöschte Foto beim
/// nächsten Lauf wieder hoch. Was hier als erledigt steht, geht nie mehr
/// zum Server – es sei denn, es wurde am Telefon bearbeitet.
///
/// Liegt im Ordner der Kopie und verschwindet mit ihr beim Abmelden: Ein
/// anderer Server oder ein anderes Konto beginnt von vorn (und der Server
/// sagt dann, was er schon hat).
///
/// Die App und die Hintergrundaufgabe öffnen dieselbe Datei, unter Android
/// womöglich gleichzeitig: WAL, eine Wartezeit für Sperren und eine
/// [sperre] mit Ablauf, damit nie zwei Läufe dieselben Dateien hochladen.
class Sicherungsstand {
  Sicherungsstand._(this._db);

  /// Öffnet (oder legt an) den Stand in [ordner].
  factory Sicherungsstand.oeffne(Directory ordner) {
    ordner.createSync(recursive: true);
    final db = sqlite3.open(p.join(ordner.path, 'sicherung.sqlite'));
    db
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA busy_timeout = 10000')
      ..execute('''
        CREATE TABLE IF NOT EXISTS erledigt (
          lokal TEXT PRIMARY KEY,
          geaendert INTEGER NOT NULL,
          ausgang TEXT NOT NULL,
          aufnahme TEXT,
          zeit INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS laufend (
          lokal TEXT NOT NULL,
          teil TEXT NOT NULL,
          pruefsumme TEXT NOT NULL,
          ort TEXT NOT NULL,
          PRIMARY KEY (lokal, teil)
        )''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS fehler (
          lokal TEXT PRIMARY KEY,
          text TEXT NOT NULL,
          versuche INTEGER NOT NULL,
          zeit INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS einstellung (
          schluessel TEXT PRIMARY KEY,
          wert TEXT NOT NULL
        )''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS sperre (
          id INTEGER PRIMARY KEY CHECK (id = 0),
          wer TEXT NOT NULL,
          bis INTEGER NOT NULL
        )''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS lauf (
          id INTEGER PRIMARY KEY CHECK (id = 0),
          wert TEXT NOT NULL
        )''');
    // Seit 3.33: warum der Server etwas abgelehnt hat. Ein Stand von davor
    // hat die Spalte noch nicht.
    if (!db
        .select('PRAGMA table_info(erledigt)')
        .any((z) => z['name'] == 'grund')) {
      db.execute('ALTER TABLE erledigt ADD COLUMN grund TEXT');
    }
    return Sicherungsstand._(db);
  }

  final Database _db;

  /// Nach so vielen Fehlschlägen wartet ein Eintrag bis [fehlerPause]
  /// vorbei ist – ein kaputtes Video soll nicht jeden Lauf aufhalten.
  static const fehlerGrenze = 3;
  static const fehlerPause = Duration(hours: 12);

  static int _ms(DateTime t) => t.millisecondsSinceEpoch;
  static int get _jetzt => _ms(DateTime.now());

  void schliesse() => _db.close();

  // --- Einstellungen -------------------------------------------------------

  Sicherungseinstellungen get einstellungen {
    final z = _db.select(
      "SELECT wert FROM einstellung WHERE schluessel = 'sicherung'",
    );
    if (z.isEmpty) return const Sicherungseinstellungen();
    return Sicherungseinstellungen.ausJson(
      (jsonDecode(z.first['wert'] as String) as Map).cast<String, Object?>(),
    );
  }

  set einstellungen(Sicherungseinstellungen e) => _db.execute(
    "INSERT OR REPLACE INTO einstellung VALUES ('sicherung', ?)",
    [jsonEncode(e.alsJson())],
  );

  // --- Was erledigt ist ----------------------------------------------------

  /// Die Kennungen, die mit diesem Änderungsstand schon sicher sind (mit
  /// ihrem Änderungsstand), die der Server abgelehnt hat, und die, die
  /// nach [fehlerGrenze] Fehlschlägen gerade pausieren.
  ({
    Map<String, int> erledigt,
    Map<String, int> abgelehnt,
    Set<String> pausiert,
  })
  bekannt() {
    final erledigt = <String, int>{};
    final abgelehnt = <String, int>{};
    for (final z in _db.select(
      'SELECT lokal, geaendert, ausgang FROM erledigt',
    )) {
      (z['ausgang'] == 'abgelehnt' ? abgelehnt : erledigt)[z['lokal']
              as String] =
          z['geaendert'] as int;
    }
    final grenze = _jetzt - fehlerPause.inMilliseconds;
    final pausiert = {
      for (final z in _db.select(
        'SELECT lokal FROM fehler WHERE versuche >= ? AND zeit > ?',
        [fehlerGrenze, grenze],
      ))
        z['lokal'] as String,
    };
    return (erledigt: erledigt, abgelehnt: abgelehnt, pausiert: pausiert);
  }

  void erledige(
    String lokal,
    DateTime geaendert, {
    required String ausgang,
    String? aufnahme,
    String? grund,
  }) {
    _db
      ..execute('INSERT OR REPLACE INTO erledigt VALUES (?, ?, ?, ?, ?, ?)', [
        lokal,
        _ms(geaendert),
        ausgang,
        aufnahme,
        _jetzt,
        grund,
      ])
      ..execute('DELETE FROM laufend WHERE lokal = ?', [lokal])
      ..execute('DELETE FROM fehler WHERE lokal = ?', [lokal]);
  }

  int get anzahlErledigt =>
      _db.select('SELECT count(*) AS n FROM erledigt').first['n'] as int;

  // --- Angefangene Uploads -------------------------------------------------

  /// Wo der Upload dieser Datei weitergeht – nur, wenn es dieselbe Datei
  /// ist (gleiche Prüfsumme).
  String? ort(String lokal, String teil, String pruefsumme) {
    final z = _db.select(
      'SELECT ort FROM laufend WHERE lokal = ? AND teil = ? AND pruefsumme = ?',
      [lokal, teil, pruefsumme],
    );
    return z.isEmpty ? null : z.first['ort'] as String;
  }

  void merkeOrt(String lokal, String teil, String pruefsumme, String ort) =>
      _db.execute('INSERT OR REPLACE INTO laufend VALUES (?, ?, ?, ?)', [
        lokal,
        teil,
        pruefsumme,
        ort,
      ]);

  // --- Fehler --------------------------------------------------------------

  void fehlschlag(String lokal, String text) => _db.execute(
    '''INSERT INTO fehler VALUES (?, ?, 1, ?)
       ON CONFLICT (lokal) DO UPDATE SET
         text = excluded.text, versuche = versuche + 1, zeit = excluded.zeit''',
    [lokal, text, _jetzt],
  );

  /// Die Einträge, die zuletzt scheiterten, mit Grund.
  Map<String, String> get fehler => {
    for (final z in _db.select('SELECT lokal, text FROM fehler'))
      z['lokal'] as String: z['text'] as String,
  };

  /// Was der Server beim Import abgelehnt hat (`ausgang = abgelehnt`).
  int get anzahlAbgelehnt =>
      _db
              .select(
                "SELECT count(*) AS n FROM erledigt WHERE ausgang = 'abgelehnt'",
              )
              .first['n']
          as int;

  /// Warum der Server etwas abgelehnt hat, je Kennung – soweit er es sagte.
  Map<String, String> get abgelehnteGruende => {
    for (final z in _db.select(
      "SELECT lokal, grund FROM erledigt WHERE ausgang = 'abgelehnt' AND grund IS NOT NULL",
    ))
      z['lokal'] as String: z['grund'] as String,
  };

  /// Alles noch einmal versuchen – auch, was der Server abgelehnt hat.
  void vergissFehler() => _db
    ..execute('DELETE FROM fehler')
    ..execute("DELETE FROM erledigt WHERE ausgang = 'abgelehnt'");

  // --- Sperre --------------------------------------------------------------

  /// Nimmt die Sperre für [wer] bis [dauer] von jetzt – wenn sie frei,
  /// abgelaufen oder schon die eigene ist. Ein Lauf verlängert sie
  /// unterwegs; stirbt er, läuft sie von selbst ab.
  bool sperre(String wer, {Duration dauer = const Duration(minutes: 2)}) {
    final bis = _jetzt + dauer.inMilliseconds;
    _db.execute(
      '''INSERT INTO sperre VALUES (0, ?, ?)
         ON CONFLICT (id) DO UPDATE SET wer = excluded.wer, bis = excluded.bis
         WHERE sperre.bis < ? OR sperre.wer = excluded.wer''',
      [wer, bis, _jetzt],
    );
    return _db.updatedRows == 1;
  }

  void gibFrei(String wer) =>
      _db.execute('DELETE FROM sperre WHERE wer = ?', [wer]);

  // --- Letzter Lauf --------------------------------------------------------

  Laufbericht? get letzterLauf {
    final z = _db.select('SELECT wert FROM lauf WHERE id = 0');
    if (z.isEmpty) return null;
    return Laufbericht.ausJson(
      (jsonDecode(z.first['wert'] as String) as Map).cast<String, Object?>(),
    );
  }

  set letzterLauf(Laufbericht? b) => b == null
      ? _db.execute('DELETE FROM lauf')
      : _db.execute('INSERT OR REPLACE INTO lauf VALUES (0, ?)', [
          jsonEncode(b.alsJson()),
        ]);
}

/// Was der Nutzer eingestellt hat.
class Sicherungseinstellungen {
  const Sicherungseinstellungen({
    this.an = false,
    this.videos = true,
    this.nurWlan = true,
    this.nurBeimLaden = false,
    this.alben = const [],
  });

  factory Sicherungseinstellungen.ausJson(Map<String, Object?> j) =>
      Sicherungseinstellungen(
        an: j['an'] == true,
        videos: j['videos'] != false,
        nurWlan: j['nurWlan'] != false,
        nurBeimLaden: j['nurBeimLaden'] == true,
        alben: [...?(j['alben'] as List?)?.cast<String>()],
      );

  final bool an;
  final bool videos;
  final bool nurWlan;

  /// Gilt im Hintergrund; in der offenen App sichert sie auch ohne Kabel.
  final bool nurBeimLaden;

  /// Die Kennungen der Alben; leer heisst alle Fotos.
  final List<String> alben;

  Map<String, Object?> alsJson() => {
    'an': an,
    'videos': videos,
    'nurWlan': nurWlan,
    'nurBeimLaden': nurBeimLaden,
    'alben': alben,
  };

  Sicherungseinstellungen mit({
    bool? an,
    bool? videos,
    bool? nurWlan,
    bool? nurBeimLaden,
    List<String>? alben,
  }) => Sicherungseinstellungen(
    an: an ?? this.an,
    videos: videos ?? this.videos,
    nurWlan: nurWlan ?? this.nurWlan,
    nurBeimLaden: nurBeimLaden ?? this.nurBeimLaden,
    alben: alben ?? this.alben,
  );
}

/// Wie der letzte Lauf ausging – für die Anzeige, auch nach einem Lauf im
/// Hintergrund.
class Laufbericht {
  const Laufbericht({
    required this.ende,
    required this.gesamt,
    required this.offen,
    required this.hochgeladen,
    required this.vorhanden,
    required this.fehlgeschlagen,
    required this.vollstaendig,
  });

  factory Laufbericht.ausJson(Map<String, Object?> j) => Laufbericht(
    ende: DateTime.fromMillisecondsSinceEpoch(j['ende']! as int),
    gesamt: j['gesamt']! as int,
    offen: j['offen']! as int,
    hochgeladen: j['hochgeladen']! as int,
    vorhanden: j['vorhanden']! as int,
    fehlgeschlagen: j['fehlgeschlagen']! as int,
    vollstaendig: j['vollstaendig'] == true,
  );

  final DateTime ende;

  /// Einträge in den gewählten Alben.
  final int gesamt;

  /// Davon nach dem Lauf noch zu tun (ohne die fehlgeschlagenen).
  final int offen;

  /// In diesem Lauf hochgeladen.
  final int hochgeladen;

  /// In diesem Lauf als schon vorhanden erkannt (Prüfsumme bekannt).
  final int vorhanden;

  /// Wegen eines Fehlers nicht sicher (siehe `Fortschritt`).
  final int fehlgeschlagen;

  /// Ob der Lauf bis zum Ende kam (und nicht abgebrochen wurde).
  final bool vollstaendig;

  Map<String, Object?> alsJson() => {
    'ende': ende.millisecondsSinceEpoch,
    'gesamt': gesamt,
    'offen': offen,
    'hochgeladen': hochgeladen,
    'vorhanden': vorhanden,
    'fehlgeschlagen': fehlgeschlagen,
    'vollstaendig': vollstaendig,
  };
}

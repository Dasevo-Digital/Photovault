import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'stand.dart';

/// Was die Sicherung über das Abmelden hinaus behält (#431).
///
/// Der [Sicherungsstand] liegt im Ordner der Kopie und ging beim Abmelden
/// mit ihr. Meldete der Server das Telefon ab und verband man es neu mit
/// demselben Konto, war die Sicherung danach still aus (keine Aufgaben,
/// kein Wächter, die Zeitleiste zählte nichts mehr als „nur auf dem
/// Telefon“), und wer sie wieder einschaltete, lud alles noch einmal hoch,
/// was am Server inzwischen endgültig gelöscht war – genau das, wovor der
/// Stand schützen soll.
///
/// Darum hebt [bewahre] den Stand vor dem Löschen der Kopie auf, je Server
/// und Konto, ohne angefangene Uploads und ohne Sperre. [stelleWiederHer]
/// legt ihn nach der nächsten Anmeldung bei demselben Server und Konto
/// zurück. Die Datei enthält nur Kennungen, Zeiten und Einstellungen,
/// keine Bilder; ihr Name verrät weder Server noch Konto.
class Sicherungsgedaechtnis {
  Sicherungsgedaechtnis(this.ablage);

  /// Neben dem Ordner der Kopie [kopie] (den löscht das Abmelden).
  factory Sicherungsgedaechtnis.neben(Directory kopie) => Sicherungsgedaechtnis(
    Directory(p.join(p.dirname(kopie.path), 'sicherungsgedaechtnis')),
  );

  final Directory ablage;

  /// Die Datei für [server] und [konto].
  File datei(Uri server, String konto) {
    // Ein abschliessender Schrägstrich macht keinen anderen Server.
    final adresse = server.toString().replaceAll(RegExp(r'/+$'), '');
    final name = sha256.convert(utf8.encode('$adresse\n$konto'));
    return File(p.join(ablage.path, '$name.sqlite'));
  }

  /// Hebt den Stand aus [kopie] für [server] und [konto] auf – vor dem
  /// Löschen der Kopie. Gibt es keinen, bleibt ein früher aufgehobener.
  void bewahre(Directory kopie, {required Uri server, required String konto}) {
    final quelle = File(p.join(kopie.path, Sicherungsstand.dateiname));
    if (!quelle.existsSync()) return;
    ablage.createSync(recursive: true);
    final ziel = datei(server, konto);
    final teil = File('${ziel.path}.neu');
    if (teil.existsSync()) teil.deleteSync();
    // VACUUM INTO schreibt einen in sich stimmigen Stand in eine neue
    // Datei, auch wenn gerade noch ein Lauf schreibt (WAL).
    final db = sqlite3.open(quelle.path);
    try {
      db
        ..execute('PRAGMA busy_timeout = 10000')
        ..execute('VACUUM INTO ?', [teil.path]);
    } finally {
      db.close();
    }
    final neu = sqlite3.open(teil.path);
    try {
      for (final tabelle in _vorhandene(neu, const ['laufend', 'sperre'])) {
        neu.execute('DELETE FROM $tabelle');
      }
    } finally {
      neu.close();
    }
    teil.renameSync(ziel.path);
  }

  /// Legt den aufgehobenen Stand für [server] und [konto] in [kopie]
  /// zurück – nach dem Holen der Bibliothek, vor dem Öffnen der Kopie.
  ///
  /// **Nur, wenn er zu dieser Bibliothek passt.** Was der Stand als
  /// erledigt führt, geht nie mehr zum Server. Wurde der Server unter
  /// derselben Adresse und mit demselben Kontonamen neu aufgesetzt, kennt
  /// seine Bibliothek keine der gesicherten Aufnahmen; dann gelten nur die
  /// Einstellungen weiter, und die Sicherung beginnt von vorn. Gibt zurück,
  /// ob das Gesicherte mitkam.
  bool stelleWiederHer(
    Directory kopie, {
    required Uri server,
    required String konto,
  }) {
    final quelle = datei(server, konto);
    if (!quelle.existsSync()) return false;
    final ziel = File(p.join(kopie.path, Sicherungsstand.dateiname));
    quelle.copySync(ziel.path);
    // Ergänzt, was einem älteren Stand fehlt.
    Sicherungsstand.oeffne(kopie).schliesse();
    final db = sqlite3.open(ziel.path);
    try {
      if (_passt(db, File(p.join(kopie.path, 'library.sqlite')))) return true;
      for (final tabelle in const ['erledigt', 'fehler', 'lauf', 'serie']) {
        db.execute('DELETE FROM $tabelle');
      }
      return false;
    } finally {
      db.close();
    }
  }

  /// Ob die Bibliothek [bibliothek] wenigstens eine der Aufnahmen kennt,
  /// die der Stand [stand] als gesichert führt – auch im Papierkorb. Ein
  /// Stand ohne solche passt immer.
  static bool _passt(Database stand, File bibliothek) {
    final aufnahmen = [
      for (final z in stand.select(
        'SELECT DISTINCT aufnahme FROM erledigt WHERE aufnahme IS NOT NULL',
      ))
        z['aufnahme'] as String,
    ];
    if (aufnahmen.isEmpty) return true;
    if (!bibliothek.existsSync()) return false;
    final db = sqlite3.open(bibliothek.path, mode: OpenMode.readOnly);
    try {
      for (var i = 0; i < aufnahmen.length; i += 500) {
        final teil = aufnahmen.sublist(
          i,
          i + 500 > aufnahmen.length ? aufnahmen.length : i + 500,
        );
        final z = db.select(
          'SELECT 1 FROM assets WHERE id IN '
          '(${List.filled(teil.length, '?').join(', ')}) LIMIT 1',
          teil,
        );
        if (z.isNotEmpty) return true;
      }
      return false;
    } finally {
      db.close();
    }
  }

  static Iterable<String> _vorhandene(Database db, List<String> tabellen) => [
    for (final z in db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ))
      if (tabellen.contains(z['name'])) z['name'] as String,
  ];
}

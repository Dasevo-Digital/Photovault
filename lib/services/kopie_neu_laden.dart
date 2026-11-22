import 'dart:io';

import 'package:kern/abgleich/abgleichsplan.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as roh;

/// Lädt die Kopie einer Server-Bibliothek neu – „Datenbank zurücksetzen“
/// in einer verbundenen Bibliothek (GRU-145).
///
/// **Warum nicht einfach löschen.** Das Zurücksetzen löschte auch hier
/// `library.sqlite` und `library/`, liess aber `verbindung.json` liegen.
/// Nach dem Neustart war die geleerte Bibliothek weiter verbunden – mit
/// einer leeren Datenbank, die nie aus einem Abzug entstanden war: Eine
/// Kopie beginnt mit dem Abzug des Servers und folgt erst danach dessen
/// Protokoll (siehe `Abgleich.holeAbzug`).
///
/// **Der Ablauf.** Erst kommt der neue Abzug neben die alte Datenbank
/// ([holeAbzug]); scheitert das (Server nicht erreichbar), bleibt alles,
/// wie es war. Dann [vorDemTausch] (die offene Datenbank schliessen), dann
/// tauscht die neue Datenbank die alte aus, und `library/` – Vorschauen und
/// zwischengespeicherte Originale – wird geleert. `verbindung.json` und
/// die Anmeldung bleiben.
///
/// **Was bleibt, obwohl die Datenbank neu ist:** was ohnehin nur auf
/// diesem Gerät gilt und nie beim Server liegt – die Spalten aus
/// [Abgleichsplan.lokaleSpalten] (Ansicht, Karte, überwachter Ordner und
/// vor allem PIN und Schlüssel des Tresors) und die Einstellungen der
/// Sicherung samt deren Schlüssel. Ohne den Tresorschlüssel liessen sich
/// gesperrte Aufnahmen auf diesem Gerät nicht mehr öffnen.
Future<void> ladeKopieNeu(
  Directory wurzel, {
  required Future<void> Function(File ziel) holeAbzug,
  required Future<void> Function() vorDemTausch,
}) async {
  final alt = File(p.join(wurzel.path, 'library.sqlite'));
  final neu = File(p.join(wurzel.path, 'library.sqlite.neu'));
  if (await neu.exists()) await neu.delete();
  await holeAbzug(neu);
  await vorDemTausch();
  if (await alt.exists()) _uebernimmGeraeteeigenes(von: alt, nach: neu);
  for (final suffix in ['', '-wal', '-shm']) {
    final f = File('${alt.path}$suffix');
    if (await f.exists()) await f.delete();
  }
  await neu.rename(alt.path);
  final ablage = Directory(p.join(wurzel.path, 'library'));
  if (await ablage.exists()) await ablage.delete(recursive: true);
}

/// Die Tabellen, die als Ganzes auf dem Gerät bleiben.
const _ganzeTabellen = ['backup_settings'];

void _uebernimmGeraeteeigenes({required File von, required File nach}) {
  final quelle = roh.sqlite3.open(von.path, mode: roh.OpenMode.readOnly);
  final ziel = roh.sqlite3.open(nach.path);
  try {
    Set<String> spalten(roh.Database db, String tabelle) => {
      for (final z in db.select('PRAGMA table_info("$tabelle")'))
        z['name'] as String,
    };
    ziel.execute('BEGIN');

    /// Alle Zeilen von [tabelle] aus der alten Datenbank, mit den Spalten,
    /// die es in beiden gibt.
    void kopiereGanz(String tabelle) {
      final gemeinsam = spalten(
        quelle,
        tabelle,
      ).intersection(spalten(ziel, tabelle)).toList();
      if (gemeinsam.isEmpty) return;
      final liste = gemeinsam.map((s) => '"$s"').join(', ');
      ziel.execute('DELETE FROM "$tabelle"');
      for (final z in quelle.select('SELECT $liste FROM "$tabelle"')) {
        ziel.execute(
          'INSERT INTO "$tabelle" ($liste) '
          'VALUES (${List.filled(gemeinsam.length, '?').join(', ')})',
          [for (final s in gemeinsam) z[s]],
        );
      }
    }

    for (final MapEntry(key: tabelle, value: lokal)
        in Abgleichsplan.lokaleSpalten.entries) {
      final gemeinsam = lokal
          .intersection(spalten(quelle, tabelle))
          .intersection(spalten(ziel, tabelle))
          .toList();
      if (gemeinsam.isEmpty) continue;
      final zeile = quelle.select(
        'SELECT ${gemeinsam.map((s) => '"$s"').join(', ')} '
        'FROM "$tabelle" WHERE id = 0',
      );
      if (zeile.isEmpty) continue;
      // Hat der Abzug die Zeile nicht, kommt die alte ganz herüber: Eine
      // leere Zeile anzulegen hiesse, jede Pflichtspalte zu kennen.
      if (ziel.select('SELECT 1 FROM "$tabelle" WHERE id = 0').isEmpty) {
        kopiereGanz(tabelle);
        continue;
      }
      ziel.execute(
        'UPDATE "$tabelle" SET '
        '${gemeinsam.map((s) => '"$s" = ?').join(', ')} WHERE id = 0',
        [for (final s in gemeinsam) zeile.first[s]],
      );
    }
    _ganzeTabellen.forEach(kopiereGanz);
    ziel.execute('COMMIT');
  } catch (_) {
    if (!ziel.autocommit) ziel.execute('ROLLBACK');
    rethrow;
  } finally {
    quelle.close();
    ziel.close();
  }
}

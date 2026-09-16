import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Nachträge an einer echten Bibliothek.**
///
/// Läuft nur, wenn `PV_ECHTE_BIBLIOTHEK` auf ein Verzeichnis zeigt, das
/// eine `library.sqlite` und einen `bibliothek/`-Ordner enthält. Sonst
/// meldet sich der Prüfstand ausdrücklich ab, statt still durchzulaufen.
///
/// **Wie die Probe entsteht, ohne 87 GB zu kopieren:** Die Originale
/// werden als **Hardlinks** in ein Probeverzeichnis gelegt. Ein Umbenennen
/// verschiebt dann nur den Verzeichniseintrag der Probe; die Datei der
/// echten Bibliothek bleibt, wo sie ist. So läuft die Korrektur an echten
/// Bytes und echten Metadaten, ohne die Produktivbibliothek anzufassen.
///
/// ```sh
/// PROBE=~/Desktop/_pv_probe
/// LIB=~/Pictures/Photo_Vault_Productive
/// mkdir -p $PROBE/bibliothek && cp $LIB/library.sqlite $PROBE/
/// (cd $LIB/library && find originals -type d -exec mkdir -p "$PROBE/bibliothek/{}" \;
///                    find originals -type f -exec ln {} "$PROBE/bibliothek/{}" \;)
/// PV_ECHTE_BIBLIOTHEK=$PROBE flutter test test/datumskorrektur_echt_test.dart
/// ```
void main() {
  final wurzel = Platform.environment['PV_ECHTE_BIBLIOTHEK'];

  Future<({AppDatabase db, StoragePaths pfade, LibraryState library})>
      oeffne() async {
    final dbDatei = File(p.join(wurzel!, 'library.sqlite'));
    expect(dbDatei.existsSync(), isTrue, reason: '${dbDatei.path} fehlt');
    final db = AppDatabase(NativeDatabase(dbDatei));
    addTearDown(db.close);
    final pfade =
        await StoragePaths.forTesting(Directory(p.join(wurzel, 'bibliothek')));
    return (
      db: db,
      pfade: pfade,
      library: LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = ImportService(db, pfade),
    );
  }

  test('Videos bekommen ihren Aufnahmezeitpunkt und ziehen um', () async {
    if (wurzel == null) {
      markTestSkipped('PV_ECHTE_BIBLIOTHEK nicht gesetzt – siehe Kopf');
      return;
    }
    final (:db, :pfade, :library) = await oeffne();

    final vorher = {
      for (final a in await db.assetsFuerDatumskorrektur())
        a.id: (zeit: a.fileCreatedAt, pfad: a.relativePath)
    };
    stdout.writeln('Kandidaten: ${vorher.length}');

    final uhr = Stopwatch()..start();
    var letzte = 0;
    await for (final fortschritt in library.korrigiereAufnahmedaten()) {
      letzte = fortschritt.done;
    }
    stdout.writeln('$letzte in ${uhr.elapsedMilliseconds} ms');
    expect(letzte, vorher.length, reason: 'jeder Kandidat muss angefasst werden');

    var geaendert = 0, verschoben = 0, fehlend = 0;
    for (final eintrag in vorher.entries) {
      final jetzt = (await db.assetById(eintrag.key))!;
      if (jetzt.fileCreatedAt != eintrag.value.zeit) geaendert++;
      if (jetzt.relativePath != eintrag.value.pfad) verschoben++;
      // Der eigentliche Punkt: Nach dem Umbenennen muss die Zeile auf eine
      // Datei zeigen, die auch dort liegt.
      if (!File(pfade.absolute(jetzt.relativePath).path).existsSync()) {
        fehlend++;
        stdout.writeln('  FEHLT: ${jetzt.relativePath}');
      }
      // Und der Ablageordner muss zum Datum passen – sonst wäre das
      // Verschieben nur halb geschehen.
      final soll = '${jetzt.fileCreatedAt.year}/'
          '${jetzt.fileCreatedAt.month.toString().padLeft(2, '0')}';
      expect(jetzt.relativePath, contains(soll),
          reason: '${jetzt.originalFileName}: Ordner passt nicht zum Datum');
    }
    stdout.writeln('geändert: $geaendert, verschoben: $verschoben');
    expect(fehlend, 0, reason: 'keine Zeile darf ins Leere zeigen');
    expect(geaendert, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('die Ablage wird geordnet, ohne ein Datum anzufassen', () async {
    if (wurzel == null) {
      markTestSkipped('PV_ECHTE_BIBLIOTHEK nicht gesetzt – siehe Kopf');
      return;
    }
    final (:db, :pfade, :library) = await oeffne();

    final vorher = {
      for (final a in await db.assetsFuerAblageordnung())
        a.id: (zeit: a.fileCreatedAt, pfad: a.relativePath)
    };
    stdout.writeln('im falschen Monatsordner: ${vorher.length}');
    expect(vorher, isNotEmpty, reason: 'sonst prüft dieser Lauf nichts');

    final uhr = Stopwatch()..start();
    await library.ordneAblageNeu().drain<void>();
    stdout.writeln('${vorher.length} umgelegt in ${uhr.elapsedMilliseconds} ms');

    var fehlend = 0, datumGeaendert = 0;
    for (final eintrag in vorher.entries) {
      final jetzt = (await db.assetById(eintrag.key))!;
      if (jetzt.fileCreatedAt != eintrag.value.zeit) datumGeaendert++;
      if (!File(pfade.absolute(jetzt.relativePath).path).existsSync()) {
        fehlend++;
        stdout.writeln('  FEHLT: ${jetzt.relativePath}');
      }
    }
    expect(datumGeaendert, 0,
        reason: 'diese Aufgabe ordnet die Ablage, sie datiert nicht um');
    expect(fehlend, 0, reason: 'keine Zeile darf ins Leere zeigen');
    expect(await db.countAblageordnung(), 0,
        reason: 'ein zweiter Lauf hätte sonst wieder etwas zu tun');
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('der Ortsnachtrag läuft einmal und danach nicht mehr', () async {
    if (wurzel == null) {
      markTestSkipped('PV_ECHTE_BIBLIOTHEK nicht gesetzt – siehe Kopf');
      return;
    }
    final (:db, pfade: _, :library) = await oeffne();

    final offen = await db.countLocationBackfill();
    stdout.writeln('ohne Ort und noch nie angesehen: $offen');

    final uhr = Stopwatch()..start();
    await library.backfillLocations().drain<void>();
    final ersteRunde = uhr.elapsedMilliseconds;
    final gefunden = offen - await db.countLocationBackfill(alle: true);
    stdout.writeln('$offen gelesen in $ersteRunde ms, $gefunden Orte gefunden');

    expect(await db.countLocationBackfill(), 0);
    uhr.reset();
    await library.backfillLocations().drain<void>();
    stdout.writeln('zweiter Lauf: ${uhr.elapsedMilliseconds} ms');
    expect(uhr.elapsedMilliseconds, lessThan(ersteRunde ~/ 10),
        reason: 'der zweite Lauf darf die Dateien nicht noch einmal lesen');
  }, timeout: const Timeout(Duration(minutes: 30)));

  /// **Die liegengebliebenen Beipackzettel an der echten Bibliothek.**
  ///
  /// 1244 von 7370 lagen dort, wo ihr Foto einmal war. Der Lauf muss sie
  /// alle einsammeln und keinen einzigen verlieren – ein `.xmp` trägt
  /// Beschreibung, Schlagwörter, Personennamen und Ort.
  test('jeder verirrte Beipackzettel findet zu seinem Foto zurueck', () async {
    if (wurzel == null) {
      markTestSkipped('PV_ECHTE_BIBLIOTHEK nicht gesetzt – siehe Kopf');
      return;
    }
    final (:db, :pfade, :library) = await oeffne();

    final vorher = await library.verirrteBeipackzettel();
    stdout.writeln('verirrte Beipackzettel: ${vorher.length}');
    expect(vorher, isNotEmpty, reason: 'sonst prueft dieser Lauf nichts');

    final inhalt = {
      for (final z in vorher.take(50))
        z.von: pfade.absolute(z.von).readAsStringSync()
    };

    final uhr = Stopwatch()..start();
    await library.ordneAblageNeu().drain<void>();
    stdout.writeln('${vorher.length} umgelegt in ${uhr.elapsedMilliseconds} ms');

    var fehlt = 0, verfaelscht = 0;
    for (final z in vorher) {
      if (!pfade.absolute(z.nach).existsSync()) {
        fehlt++;
        stdout.writeln('  FEHLT: ${z.nach}');
      } else if (inhalt.containsKey(z.von) &&
          pfade.absolute(z.nach).readAsStringSync() != inhalt[z.von]) {
        verfaelscht++;
      }
      expect(pfade.absolute(z.von).existsSync(), isFalse,
          reason: '${z.von} liegt immer noch am alten Platz');
    }
    expect(fehlt, 0, reason: 'kein Zettel darf unterwegs verlorengehen');
    expect(verfaelscht, 0, reason: 'der Inhalt muss unveraendert ankommen');
    expect(await library.verirrteBeipackzettel(), isEmpty,
        reason: 'ein zweiter Lauf haette sonst wieder etwas zu tun');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

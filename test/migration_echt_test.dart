import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

/// Die jüngste Migration an **Kopien echter Bibliotheken**.
///
/// Läuft nur, wenn die Kopien dort liegen, wo die Umgebungsvariable
/// `PV_MIGRATION_DIR` hinzeigt – sonst hinge die ganze Suite an Dateien,
/// die es auf keiner anderen Maschine gibt. Der Grund für den Test:
/// Eine Migration, die auf einer leeren Datenbank läuft, sagt nichts
/// darüber, ob sie auf einer gewachsenen läuft.
void main() {
  final ordner = Platform.environment['PV_MIGRATION_DIR'];

  test('drei gewachsene Bibliotheken kommen auf die neueste Fassung',
      () async {
    if (ordner == null) {
      markTestSkipped('PV_MIGRATION_DIR nicht gesetzt');
      return;
    }
    // Fehlt eine der drei Vorlagen, wird sie übersprungen statt den Lauf
    // zu Fall zu bringen: Sie sind Kopien gewachsener Bibliotheken und
    // liegen nicht dauerhaft irgendwo. Fehlen ALLE, meldet sich der
    // Prüfstand ausdrücklich ab – ein stiller Durchlauf wäre das
    // Schlechteste von beidem.
    final vorhanden = [
      for (final name in ['gross.sqlite', 'alt32.sqlite', 'alt27.sqlite'])
        if (File('$ordner/$name').existsSync()) name
    ];
    if (vorhanden.isEmpty) {
      markTestSkipped('keine der drei Vorlagen liegt in $ordner');
      return;
    }
    for (final name in vorhanden) {
      final datei = File('$ordner/$name');

      // **Vor** der Migration nachsehen, von wo aus sie startet. Zwei
      // Erwartungen unten gelten nur fuer eine Vorlage, die den
      // jeweiligen Schritt wirklich noch vor sich hat – eine Kopie, die
      // laengst darueber hinaus ist, wuerde daran scheitern, ohne dass
      // etwas kaputt waere.
      final startfassung = sqlite3.open(datei.path).select('PRAGMA user_version')
          .first.values.first as int;

      final db = AppDatabase(NativeDatabase(datei));
      // Die erste Abfrage löst die Migration aus.
      final vorher = await db.customSelect('SELECT count(*) AS n FROM assets')
          .map((r) => r.read<int>('n'))
          .getSingle();
      final fassung = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(fassung, db.schemaVersion, reason: name);

      final tabellen = {
        for (final z in await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get())
          z.data['name'] as String
      };
      for (final erwartet in [
        'aktivitaeten',
        'aktivitaet_aufnahmen',
        'verworfene_aktivitaeten',
        'spuren',
        'spurpunkte',
      ]) {
        expect(tabellen, contains(erwartet), reason: '$name: $erwartet');
      }

      // Die damals neuen Tabellen lassen sich lesen, und an den Aufnahmen
      // hat sich nichts geändert.
      //
      // Früher stand hier `isEmpty`: Als die Tabellen dazukamen, war das die
      // richtige Prüfung. Inzwischen sind in der grossen Bibliothek
      // Aktivitäten und Reisen erkannt worden, und eine leere Tabelle wäre
      // gerade das Alarmzeichen. Geprüft wird deshalb, dass die Abfrage
      // durchläuft – die Migration darf sie weder verlieren noch
      // unlesbar machen.
      await db.alleAktivitaeten();
      await db.alleSpuren();
      final nachher = await db.customSelect('SELECT count(*) AS n FROM assets')
          .map((r) => r.read<int>('n'))
          .getSingle();
      expect(nachher, vorher, reason: name);

      // Und die Reisen stehen noch – die Tabelle daneben.
      await db.alleReisen();

      // Schema 60: die Spalte ist da, und der bereits erkannte Text ist
      // unangetastet geblieben. Die Stellen dazu holt erst ein neuer Lauf
      // der Texterkennung – bis dahin steht dort überall null, und genau
      // diese Fotos muss der Nachlauf wieder aufgreifen.
      final offen = await db.countOcrBackfill();
      // Dieselben Filter wie [_ocrOffen]: Papierkorb und Tresor bleiben
      // aussen vor. In der grossen Bibliothek trennt genau das 2406
      // erkannte Texte von 2256 erneut erreichbaren – der Rest liegt im
      // Papierkorb oder gesperrt, und beides soll die Texterkennung nicht
      // anfassen.
      final mitText = await db
          .customSelect('SELECT count(*) AS n FROM assets '
              "WHERE type = 'IMAGE' AND is_trashed = 0 AND is_locked = 0 "
              "AND ocr_text IS NOT NULL AND ocr_text <> '' AND ocr_boxen IS NULL")
          .map((r) => r.read<int>('n'))
          .getSingle();
      expect(offen, greaterThanOrEqualTo(mitText), reason: name);
      // ignore: avoid_print
      print('$name: $mitText Aufnahmen mit Text, aber ohne Stellen; '
          '$offen offen fuer die Texterkennung');
      // Schema 64: die Spalte ist da und steht überall auf `false`. Das
      // ist Absicht – der erste Ortsnachtrag nach dem Umstieg geht noch
      // einmal über alles und findet dabei die Videos, an die er vorher
      // nie herankam. Erst danach ist er still.
      //
      // Nur fuer eine Vorlage, die diesen Schritt noch vor sich hatte:
      // In einer Bibliothek, die seither gelaufen ist, stehen die
      // angesehenen Aufnahmen laengst auf `true`, und das ist der
      // Normalfall und kein Fehler.
      if (startfassung < 64) {
        final nochNieAngesehen = await db
            .customSelect(
                'SELECT count(*) AS n FROM assets WHERE gps_geprueft = 0')
            .map((r) => r.read<int>('n'))
            .getSingle();
        expect(nochNieAngesehen, nachher, reason: '$name: alle unangesehen');
      }
      expect(await db.countLocationBackfill(),
          (await db.assetsForLocationBackfill()).length,
          reason: '$name: Zahl und Liste');

      // Schema 64 daneben: Wie viele Aufnahmen liegen im Ordner eines
      // anderen Monats, als ihr Datum sagt (siehe [ordneAblageNeu])?
      final schief = await db.countAblageordnung();
      // ignore: avoid_print
      print('$name: $schief Aufnahmen im falschen Monatsordner');

      await db.close();
      // ignore: avoid_print
      print('$name: $vorher Aufnahmen, Fassung $fassung');
    }
  });
}

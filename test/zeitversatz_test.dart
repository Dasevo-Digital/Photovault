import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/zeitversatz.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Jede vierte Datei weiss ihre Zeitzone, die App fragte nie.**
///
/// 126 Dateien quer durch die echte Bibliothek gezogen: 34 tragen
/// `OffsetTimeOriginal`, also 27 %. Im ganzen Quelltext gab es für dieses
/// Feld **null** Fundstellen. digiKam hat im Juni 2026 dafür sein
/// Datenbankschema erweitert.
///
/// Praktisch heisst das: Die 228 Aufnahmen aus Mazār-e Sharīf standen
/// unter der Uhrzeit der Kamera, und die App konnte nicht sagen, ob das
/// 16 Uhr in Berlin oder 18:30 vor Ort war.
///
/// **Der Aufnahmezeitpunkt bleibt, was er war** – die Ortszeit der
/// Kamera. Das ist die Zeit, an die man sich erinnert; der Versatz sagt
/// nur dazu, in welcher Zone sie galt.
void main() {
  group('den Versatz lesen', () {
    test('die üblichen Schreibweisen', () {
      expect(zeitversatzAusText('+02:00'), 120);
      expect(zeitversatzAusText('-05:00'), -300);
      expect(zeitversatzAusText('+04:30'), 270, reason: 'Afghanistan');
      expect(zeitversatzAusText('-03:30'), -210, reason: 'Neufundland');
      expect(zeitversatzAusText('+05:45'), 345, reason: 'Nepal');
      expect(zeitversatzAusText('Z'), 0, reason: 'ausdrueckliche Angabe');
      expect(zeitversatzAusText('+0200'), 120, reason: 'ohne Doppelpunkt');
      expect(zeitversatzAusText(' +02:00 '), 120);
    });

    test('„+00:00" ist die Werkseinstellung, kein Befund', () {
      // Nachgezaehlt, nicht vermutet: In der echten Bibliothek tragen 131
      // Aufnahmen diesen Wert, alle von einer Canon EOS R10, davon 34 als
      // in DEUTSCHLAND verortet und die uebrigen aus November und
      // Dezember zwischen 04:32 und 18:56. Deutschland ist nie UTC+0.
      expect(zeitversatzAusText('+00:00'), isNull);
      expect(zeitversatzAusText('-00:00'), isNull);
      // „Z" dagegen ist eine ausdrueckliche Angabe.
      expect(zeitversatzAusText('Z'), 0);
    });

    test('drei Leerzeichen sind KEINE Zeitzone', () {
      // Der Standardwert einer Kamera, die keine Zone kennt. Als 0
      // gelesen behauptete jede solche Datei, sie sei in Greenwich
      // entstanden – und das waere eine erfundene Angabe an genau der
      // Stelle, an der es um Ehrlichkeit geht.
      expect(zeitversatzAusText('   '), isNull);
      expect(zeitversatzAusText(''), isNull);
      expect(zeitversatzAusText(null), isNull);
    });

    test('was keine Zeitzone sein kann, wird keine', () {
      // Es ist ein Freitextfeld. Die aeussersten echten Zonen sind -12:00
      // und +14:00.
      expect(zeitversatzAusText('+15:00'), isNull);
      expect(zeitversatzAusText('+14:00'), 14 * 60, reason: 'Kiribati');
      expect(zeitversatzAusText('+02:99'), isNull);
      expect(zeitversatzAusText('2026:08:27'), isNull);
      expect(zeitversatzAusText('02:00'), isNull, reason: 'ohne Vorzeichen');
    });
  });

  group('den Versatz anschreiben', () {
    test('volle und halbe Stunden', () {
      expect(zeitversatzText(120), 'UTC+2');
      expect(zeitversatzText(270), 'UTC+4:30');
      expect(zeitversatzText(345), 'UTC+5:45');
      expect(zeitversatzText(0), 'UTC');
      expect(zeitversatzText(-300), 'UTC−5');
      expect(zeitversatzText(-210), 'UTC−3:30');
    });

    test('mit typografischem Minus, nicht mit Bindestrich', () {
      // Neben einer Uhrzeit gelesen ist der Bindestrich zu leicht ein
      // Trennstrich.
      expect(zeitversatzText(-120), contains('−'));
      expect(zeitversatzText(-120), isNot(contains('-')));
    });
  });

  group('am ganzen Weg', () {
    late Directory wurzel;
    late Directory eingang;
    late AppDatabase db;
    late StoragePaths paths;
    late ImportService importService;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_zone_');
      eingang = Directory(p.join(wurzel.path, 'eingang'))..createSync();
      paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
      db = AppDatabase(NativeDatabase.memory());
      importService = ImportService(db, paths);
      library = LibraryState()
        ..db = db
        ..paths = paths
        ..importService = importService;
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    List<int> jpeg({String? versatz, int inhalt = 0}) {
      final bild = img.Image(width: 8, height: 8);
      bild.setPixelRgb(0, 0, inhalt % 256, 0, 0);
      bild.exif.exifIfd['DateTimeOriginal'] = '2013:07:04 15:22:08';
      if (versatz != null) {
        bild.exif.exifIfd['OffsetTimeOriginal'] = versatz;
      }
      return img.encodeJpg(bild);
    }

    test('der Import übernimmt den Versatz', () async {
      final datei = File(p.join(eingang.path, 'mit.jpg'))
        ..writeAsBytesSync(jpeg(versatz: '+04:30'));
      final e = await importService.importFile(datei.path);
      final a = (await db.assetById(e.assetId!))!;

      expect(a.zeitversatzMinuten, 270);
      // Und der Zeitstempel bleibt die Ortszeit der Kamera.
      expect(a.fileCreatedAt, DateTime(2013, 7, 4, 15, 22, 8),
          reason: 'der Versatz verschiebt die Aufnahmezeit NICHT');
    });

    test('ohne Angabe in der Datei bleibt die Spalte leer', () async {
      // Die Gegenprobe: Ein erfundener Versatz waere schlimmer als keiner.
      final datei = File(p.join(eingang.path, 'ohne.jpg'))
        ..writeAsBytesSync(jpeg(inhalt: 1));
      final e = await importService.importFile(datei.path);
      expect((await db.assetById(e.assetId!))!.zeitversatzMinuten, isNull);
    });

    test('der Nachtrag holt ihn im selben Lauf wie die Datumsherkunft',
        () async {
      // Der springende Punkt: Die Datei ist fuer die Frage nach dem
      // Aufnahmedatum ohnehin offen. Ein eigener Lauf hiesse,
      // achttausend Dateien ein zweites Mal zu lesen.
      for (final (id, versatz) in [('a', '+04:30'), ('b', null)]) {
        await db.insertAsset(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/2013/07/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2013, 7, 4, 15, 22, 8),
          importedAt: DateTime(2026),
        ));
        final datei = paths.absolute('originals/2013/07/$id.jpg');
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(jpeg(versatz: versatz, inhalt: id.hashCode));
      }

      await for (final _ in library.backfillDatumsherkunft()) {}

      expect((await db.assetById('a'))!.zeitversatzMinuten, 270);
      expect((await db.assetById('b'))!.zeitversatzMinuten, isNull);
      // Und die Datumsherkunft ist im selben Zug mit erledigt.
      expect(await db.countDatumsherkunft(), 0);
      expect((await db.assetById('a'))!.datumGeschaetzt, isFalse);
    });

    test('ein zweiter Lauf nimmt einen weggefallenen Versatz zurück',
        () async {
      await db.insertAsset(AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.jpg',
        relativePath: 'originals/2013/07/a.jpg',
        checksum: 'pruef-a',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2013, 7, 4),
        importedAt: DateTime(2026),
      ));
      final datei = paths.absolute('originals/2013/07/a.jpg');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg(versatz: '+04:30'));
      await for (final _ in library.backfillDatumsherkunft()) {}
      expect((await db.assetById('a'))!.zeitversatzMinuten, 270);

      await datei.writeAsBytes(jpeg(inhalt: 9));
      await for (final _ in library.backfillDatumsherkunft(alle: true)) {}
      expect((await db.assetById('a'))!.zeitversatzMinuten, isNull);
    });
  });
}

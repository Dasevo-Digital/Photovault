import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Datumskorrektur ist der einzige Nachtrage-Lauf, der vorhandene
/// Nutzerdaten ÄNDERT statt nur Fehlendes zu ergänzen: Er schreibt das
/// Aufnahmedatum um und verschiebt die Datei in einen anderen
/// Monatsordner. Deshalb wird hier nicht nur das Ergebnis geprüft,
/// sondern auch, was er in Ruhe lässt.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_datum_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Ein Bild mit EXIF-Aufnahmedatum, abgelegt unter der gewünschten
  /// Endung.
  ///
  /// Bewusst JPEG-Bytes unter einer RAW-Endung: `readExifFromBytes` sieht
  /// den Dateinamen nicht, die Auswahl der Kandidaten dagegen schon. So
  /// lässt sich der ganze Weg prüfen, ohne eine echte CR3-Datei und ohne
  /// die nativen Werkzeuge, die es im Testlauf nicht gibt.
  Future<String> legeAn({
    required String id,
    required DateTime inDerDatenbank,
    required DateTime? imBild,
    String endung = '.dng',
  }) async {
    final bild = img.Image(width: 8, height: 8);
    if (imBild != null) {
      String z(int v, int n) => v.toString().padLeft(n, '0');
      bild.exif.exifIfd['DateTimeOriginal'] =
          '${z(imBild.year, 4)}:${z(imBild.month, 2)}:${z(imBild.day, 2)} '
          '${z(imBild.hour, 2)}:${z(imBild.minute, 2)}:${z(imBild.second, 2)}';
    }
    final rel = paths.originalRelativePath(inDerDatenbank, id, endung);
    final datei = paths.absolute(rel);
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(img.encodeJpg(bild));
    await db.insertAsset(AssetsCompanion.insert(
      id: id,
      originalFileName: '$id$endung',
      relativePath: rel,
      checksum: id,
      type: 'IMAGE',
      fileCreatedAt: inDerDatenbank,
      importedAt: DateTime.now(),
      fileSizeBytes: const Value(1),
    ));
    return rel;
  }

  Future<void> lauf() async {
    await for (final _ in library.korrigiereAufnahmedaten()) {}
  }

  test('falsches Datum wird richtiggestellt und die Datei umgehängt', () async {
    // Der gemessene Normalfall: Import trug den Dateizeitstempel ein
    // (Mai 2026), aufgenommen wurde im November 2025.
    final alt = await legeAn(
      id: 'a1',
      inDerDatenbank: DateTime(2026, 5, 8, 23, 40),
      imBild: DateTime(2025, 11, 30, 8, 11),
    );
    expect(alt, contains(p.join('2026', '05')));

    await lauf();

    final asset = (await db.assetsFuerDatumskorrektur()).single;
    expect(asset.fileCreatedAt, DateTime(2025, 11, 30, 8, 11));
    expect(asset.relativePath, contains(p.join('2025', '11')));
    // Und die Datei liegt wirklich dort – nicht nur der Eintrag.
    expect(await paths.absolute(asset.relativePath).exists(), isTrue);
    expect(await paths.absolute(alt).exists(), isFalse);
  });

  test('gleicher Monat: Datum wird gesetzt, die Datei bleibt liegen', () async {
    final alt = await legeAn(
      id: 'a2',
      inDerDatenbank: DateTime(2026, 6, 21, 7, 34),
      imBild: DateTime(2026, 6, 21, 11, 34),
    );

    await lauf();

    final asset = (await db.assetsFuerDatumskorrektur()).single;
    expect(asset.fileCreatedAt, DateTime(2026, 6, 21, 11, 34));
    expect(asset.relativePath, alt, reason: 'gleicher Monat, kein Umzug');
    expect(await paths.absolute(alt).exists(), isTrue);
  });

  test('Abweichung unter einer Minute löst nichts aus', () async {
    // Sonst schriebe jeder Lauf dieselben Fotos erneut um, nur wegen
    // Rundungen zwischen den Lesewegen.
    final alt = await legeAn(
      id: 'a3',
      inDerDatenbank: DateTime(2026, 6, 21, 11, 34, 10),
      imBild: DateTime(2026, 6, 21, 11, 34, 40),
    );

    await lauf();

    final asset = (await db.assetsFuerDatumskorrektur()).single;
    expect(asset.fileCreatedAt, DateTime(2026, 6, 21, 11, 34, 10));
    expect(asset.relativePath, alt);
  });

  test('ohne Datum im Bild bleibt alles, wie es war', () async {
    final alt = await legeAn(
      id: 'a4',
      inDerDatenbank: DateTime(2026, 5, 8),
      imBild: null,
    );

    await lauf();

    final asset = (await db.assetsFuerDatumskorrektur()).single;
    expect(asset.fileCreatedAt, DateTime(2026, 5, 8));
    expect(asset.relativePath, alt);
  });

  test('JPEG-Fotos werden nicht angefasst', () async {
    // Bei ihnen gab es den Rückfall auf den Dateizeitstempel nie – ihr
    // Datum kam immer aus den EXIF-Daten. Ein Lauf über die ganze
    // Bibliothek wäre teuer und könnte nur schaden.
    final alt = await legeAn(
      id: 'a5',
      inDerDatenbank: DateTime(2026, 5, 8),
      imBild: DateTime(2020, 1, 2, 3, 4, 5),
      endung: '.jpg',
    );

    await lauf();

    // Seit die RAW-Bedingung in der Abfrage steht, taucht ein JPEG dort
    // gar nicht erst auf – das ist die schärfere Aussage als „wurde nicht
    // verändert", und sie schliesst zugleich aus, dass die Datei für
    // nichts von der Platte gelesen wird.
    expect(await db.assetsFuerDatumskorrektur(), isEmpty);
    expect(await db.countDatumskorrektur(), 0);

    final asset = (await db.assetById('a5'))!;
    expect(asset.fileCreatedAt, DateTime(2026, 5, 8));
    expect(asset.relativePath, alt);
  });

  test('fehlende Datei überspringt den Eintrag, statt zu werfen', () async {
    final alt = await legeAn(
      id: 'a6',
      inDerDatenbank: DateTime(2026, 5, 8),
      imBild: DateTime(2025, 11, 30),
    );
    await paths.absolute(alt).delete();

    await lauf();

    final asset = (await db.assetsFuerDatumskorrektur()).single;
    expect(asset.fileCreatedAt, DateTime(2026, 5, 8));
  });

  group('aus dem Papierkorb zurückholen', () {
    /// Der Korrekturlauf überspringt den Papierkorb – dort stört ein
    /// falsches Datum niemanden. Beim Zurückholen ändert sich das, und
    /// genau dort muss nachgelesen werden.
    test('holt zurück UND stellt das Datum richtig', () async {
      final alt = await legeAn(
        id: 'p1',
        inDerDatenbank: DateTime(2026, 5, 8, 23, 40),
        imBild: DateTime(2025, 11, 30, 8, 11),
      );
      await db.moveToTrash(['p1']);
      // Der normale Lauf lässt es liegen – das ist Absicht.
      await lauf();
      expect((await db.assetById('p1'))!.fileCreatedAt,
          DateTime(2026, 5, 8, 23, 40));

      await library.ausPapierkorbHolen(['p1']);

      final asset = (await db.assetById('p1'))!;
      expect(asset.isTrashed, isFalse);
      expect(asset.fileCreatedAt, DateTime(2025, 11, 30, 8, 11));
      expect(asset.relativePath, contains(p.join('2025', '11')));
      expect(await paths.absolute(asset.relativePath).exists(), isTrue);
      expect(await paths.absolute(alt).exists(), isFalse);
    });

    test('JPEG kommt unverändert zurück', () async {
      final alt = await legeAn(
        id: 'p2',
        inDerDatenbank: DateTime(2026, 5, 8),
        imBild: DateTime(2020, 1, 2, 3, 4, 5),
        endung: '.jpg',
      );
      await db.moveToTrash(['p2']);
      await library.ausPapierkorbHolen(['p2']);
      final asset = (await db.assetById('p2'))!;
      expect(asset.isTrashed, isFalse);
      expect(asset.fileCreatedAt, DateTime(2026, 5, 8));
      expect(asset.relativePath, alt);
    });

    test('fehlende Datei verhindert das Zurückholen nicht', () async {
      final alt = await legeAn(
        id: 'p3',
        inDerDatenbank: DateTime(2026, 5, 8),
        imBild: DateTime(2025, 11, 30),
      );
      await db.moveToTrash(['p3']);
      await paths.absolute(alt).delete();

      await library.ausPapierkorbHolen(['p3']);

      // Zurückgeholt ist wichtiger als datiert: Wer sein Foto wiederhaben
      // will, soll es wiederbekommen, auch wenn die Datei fehlt.
      expect((await db.assetById('p3'))!.isTrashed, isFalse);
    });
  });

  test('zweiter Lauf ändert nichts mehr', () async {
    await legeAn(
      id: 'a7',
      inDerDatenbank: DateTime(2026, 5, 8, 23, 40),
      imBild: DateTime(2025, 11, 30, 8, 11),
    );
    await lauf();
    final nachEins = (await db.assetsFuerDatumskorrektur()).single;
    await lauf();
    final nachZwei = (await db.assetsFuerDatumskorrektur()).single;
    expect(nachZwei.relativePath, nachEins.relativePath);
    expect(nachZwei.fileCreatedAt, nachEins.fileCreatedAt);
  });
}

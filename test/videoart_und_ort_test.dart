import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Videos bekommen ihren Ort, und Standbilder ihre Art zurück.**
///
/// Zwei Funde derselben Messung an der echten Bibliothek:
///
/// - 216 von 440 Videos tragen einen Ort in der Datei, keines trug einen
///   in der Datenbank. `package:exif` liest weder MOV noch MP4, und
///   `assetsForLocationBackfill` schloss Videos zusätzlich ausdrücklich aus.
/// - 31 der 440 „Videos" sind in Wahrheit JPEG oder HEIC – Standbilder
///   unter einem `.mov`-Namen. Als Video geführt fielen sie aus jeder
///   Auswertung heraus und bekamen nicht einmal ein Vorschaubild: Der
///   Videowandler bekam ein Standbild und lieferte nichts (gemessen: 33
///   der 440 hatten keine Miniatur).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService imp;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_videoart_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    imp = ImportService(db, pfade);
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Uint8List kasten(String art, List<int> inhalt) {
    final b = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, 8 + inhalt.length)).buffer.asUint8List())
      ..add(art.codeUnits)
      ..add(inhalt);
    return b.toBytes();
  }

  /// Ein Video, dessen `moov` – wie im Regelfall – hinter den Rohdaten
  /// steht. [ort] als ISO 6709 im `©xyz`-Atom, oder gar kein Ort.
  Uint8List videobytes({String? ort, int mdatBytes = 4000}) {
    final udta = ort == null
        ? <int>[]
        : kasten(
            'udta',
            kasten('©xyz', [
              ...(ByteData(2)..setUint16(0, ort.length)).buffer.asUint8List(),
              0xFF,
              0x7F,
              ...ort.codeUnits,
            ]));
    final b = BytesBuilder()
      ..add(kasten('ftyp', 'qt  '.codeUnits))
      ..add(kasten('mdat', List.filled(mdatBytes, 7)))
      ..add(kasten('moov', [
        ...kasten('mvhd', List.filled(100, 0)),
        ...udta,
      ]));
    return b.toBytes();
  }

  /// Ein winziges, echtes JPEG.
  Uint8List jpegbytes() {
    final bild = img.Image(width: 24, height: 18);
    img.fill(bild, color: img.ColorRgb8(120, 140, 160));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  File lege(String name, Uint8List inhalt) {
    final rein = Directory(p.join(temp.path, 'rein'))..createSync();
    return File(p.join(rein.path, name))..writeAsBytesSync(inhalt);
  }

  group('Der Ort im Video', () {
    test('kommt beim Import in die Datenbank', () async {
      final r = await imp
          .importFile(lege('urlaub.mov', videobytes(ort: '+52.2375+10.5738')).path);
      expect(r.outcome, ImportOutcome.imported);
      final asset = (await db.assetById(r.assetId!))!;
      expect(asset.type, 'VIDEO');
      expect(asset.latitude, closeTo(52.2375, 1e-6));
      expect(asset.longitude, closeTo(10.5738, 1e-6));
    });

    test('ein Video ohne Ort bleibt ohne Ort', () async {
      final r = await imp.importFile(lege('ohne.mov', videobytes()).path);
      final asset = (await db.assetById(r.assetId!))!;
      expect(asset.latitude, isNull);
    });

    test('der Nachtrag sieht Videos an – vorher tat er das nicht', () async {
      // `assetsForLocationBackfill` filterte auf `type = 'IMAGE'` und
      // liess damit genau die Gruppe aus, bei der noch etwas zu holen war.
      await db.insertAsset(AssetsCompanion.insert(
        id: 'v1',
        relativePath: 'originals/v1.mov',
        originalFileName: 'v1.mov',
        type: 'VIDEO',
        checksum: 'v1',
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024),
      ));
      final offen = await db.assetsForLocationBackfill();
      expect([for (final a in offen) a.id], contains('v1'));
      expect(await db.countLocationBackfill(), 1);
    });

    test('ein Video ohne Ort wird nicht ganz gelesen', () async {
      // Der gefährliche Weg wäre der Rückfall auf `readAsBytes` für EXIF –
      // bei einer echten Aufnahme wären das mehrere Gigabyte im Speicher,
      // für ein sicheres `null`. Hier steht nur, dass nichts herauskommt
      // und nichts wirft; die Grenze zieht die Prüfung der Inhaltskennung.
      final datei = lege('gross.mov', videobytes(mdatBytes: 2 * 1024 * 1024));
      expect(await imp.readGpsLocation(datei), isNull);
    });
  });

  group('Standbild unter Videonamen', () {
    test('wird beim Import als Bild eingeordnet', () async {
      final r = await imp.importFile(lege('IMG_0042.mov', jpegbytes()).path);
      expect(r.outcome, ImportOutcome.imported);
      final asset = (await db.assetById(r.assetId!))!;
      expect(asset.type, 'IMAGE',
          reason: 'die Bytes sagen JPEG, der Name sagt Video');
      // Und weil es als Bild durchlief, entstand auch eine Miniatur.
      expect(asset.thumbnailRelativePath, isNotNull);
    });

    test('ein echtes Video bleibt ein Video', () async {
      // Gegenprobe: Die Regel darf nicht jede Datei zum Bild erklären.
      final r = await imp.importFile(lege('echt.mov', videobytes()).path);
      expect((await db.assetById(r.assetId!))!.type, 'VIDEO');
    });

    test('der Nachlauf berichtigt, was schon in der Bibliothek liegt',
        () async {
      // So sieht der Bestand aus: als Video geführt, ohne Miniatur, weil
      // der Videowandler an einem Standbild scheiterte.
      const rel = 'originals/2024/01/alt.mov';
      pfade.absolute(rel)
        ..createSync(recursive: true)
        ..writeAsBytesSync(jpegbytes());
      await db.insertAsset(AssetsCompanion.insert(
        id: 'alt',
        relativePath: rel,
        originalFileName: 'alt.mov',
        type: 'VIDEO',
        checksum: 'alt',
        dateiformat: const Value('mov'),
        durationSeconds: const Value(3.0),
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024),
      ));
      // Und ein echtes Video daneben, das unangetastet bleiben muss.
      const relEcht = 'originals/2024/01/echt.mov';
      pfade.absolute(relEcht)
        ..createSync(recursive: true)
        ..writeAsBytesSync(videobytes());
      await db.insertAsset(AssetsCompanion.insert(
        id: 'echt',
        relativePath: relEcht,
        originalFileName: 'echt.mov',
        type: 'VIDEO',
        checksum: 'echt',
        fileCreatedAt: DateTime(2024),
        importedAt: DateTime(2024),
      ));

      final library = LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = imp;
      await library.repariereDateiarten().drain<void>();

      final berichtigt = (await db.assetById('alt'))!;
      expect(berichtigt.type, 'IMAGE');
      expect(berichtigt.dateiformat, 'jpg');
      // Die Laufzeit eines Standbildes ist keine Zahl, sondern keine.
      expect(berichtigt.durationSeconds, isNull);
      expect((await db.assetById('echt'))!.type, 'VIDEO');
    });
  });
}

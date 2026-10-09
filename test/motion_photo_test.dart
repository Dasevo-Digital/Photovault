import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/motion_photo.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Motion Photos: das Video, das Google und Samsung hinten ans JPEG
/// hängen – gebaut wie von der Kamera, mit einem Platzhalter-MP4.
void main() {
  final jpeg = img.encodeJpg(img.Image(width: 16, height: 16));
  // Der Anfang eines MP4: Länge, „ftyp“, Marke – mehr prüft der Parser
  // nicht, und mehr braucht der Import nicht, um es als Video zu führen.
  final mp4 = Uint8List.fromList([
    0,
    0,
    0,
    24,
    ...ascii.encode('ftypmp42'),
    0,
    0,
    0,
    0,
    ...ascii.encode('mp42isom'),
    ...List.filled(200, 7),
  ]);

  /// Ein JPEG mit [xmp] direkt hinter dem Anfangsmarker – so weit vorn,
  /// wie es auch die Kamera schreibt.
  Uint8List mitXmp(String xmp, List<int> anhang) => Uint8List.fromList([
    ...jpeg.sublist(0, 2),
    ...ascii.encode(xmp),
    ...jpeg.sublist(2),
    ...anhang,
  ]);

  test('Google, neu: Länge aus dem Container-Verzeichnis', () {
    final d = mitXmp(
      '<Container:Directory><rdf:Seq><rdf:li>'
      '<Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary"/>'
      '</rdf:li><rdf:li>'
      '<Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" '
      'Item:Length="${mp4.length}"/></rdf:li></rdf:Seq>'
      '</Container:Directory>',
      mp4,
    );
    expect(
      siehtNachMotionPhotoAus(d.sublist(0, 200), d.sublist(d.length - 10)),
      isTrue,
    );
    expect(motionPhotoAnfang(d), d.length - mp4.length);
  });

  test('Google, alt: MicroVideoOffset', () {
    final d = mitXmp(
      'GCamera:MicroVideo="1" GCamera:MicroVideoOffset="${mp4.length}"',
      mp4,
    );
    expect(motionPhotoAnfang(d), d.length - mp4.length);
  });

  test('Samsung: hinter der Kennung, nicht im Verzeichnis am Ende', () {
    final d = Uint8List.fromList([
      ...jpeg,
      ...ascii.encode('MotionPhoto_Data'),
      ...mp4,
      ...ascii.encode('xxxxMotionPhoto_Data\u0000\u0000SEFT'),
    ]);
    final kopf = d.sublist(0, 100);
    expect(siehtNachMotionPhotoAus(kopf, d.sublist(d.length - 40)), isTrue);
    expect(motionPhotoAnfang(d), jpeg.length + 16);
  });

  test('eine Länge, die nicht stimmt, liefert nichts statt Unsinn', () {
    final d = mitXmp(
      '<Container:Item Item:Semantic="MotionPhoto" Item:Length="99"/>',
      mp4,
    );
    expect(motionPhotoAnfang(d), isNull);
  });

  test('ein gewöhnliches JPEG ist keins', () {
    expect(siehtNachMotionPhotoAus(jpeg, jpeg), isFalse);
    expect(motionPhotoAnfang(jpeg), isNull);
  });

  test('beim Import wird das Video gelöst und verknüpft', () async {
    final wurzel = Directory.systemTemp.createTempSync('pv_motion_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = ImportService(db, pfade);

    final quelle = File(p.join(wurzel.path, 'PXL_20250712_101500123.MP.jpg'))
      ..writeAsBytesSync(
        mitXmp(
          'GCamera:MicroVideo="1" GCamera:MicroVideoOffset="${mp4.length}"',
          mp4,
        ),
      );
    await library.importFiles([quelle.path]).drain<void>();

    final alle = await db.select(db.assets).get();
    final foto = alle.singleWhere((a) => a.type == 'IMAGE');
    final video = alle.singleWhere((a) => a.type == 'VIDEO');
    expect(foto.linkedAssetId, video.id);
    expect(video.originalFileName, 'PXL_20250712_101500123.MP.mp4');
    expect(video.fileCreatedAt, foto.fileCreatedAt);
    expect(
      await pfade.absolute(video.relativePath).readAsBytes(),
      mp4,
      reason: 'genau das angehängte Video',
    );
  });
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_plan.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Regeln und Kameravorgaben, deren Zielalbum gelöscht wurde (IMP-024), am
/// Server: Hochladen mit und ohne Regelstand und die Freigabe aus der
/// Fotokammer nehmen das Foto an, das fehlende Album fällt weg, der Rest
/// der Regel gilt.
///
/// Vorher scheiterte ein Upload mit Regelstand an
/// „pv_import_regeln_geaendert“ – das Foto liess sich nicht hochladen, auch
/// nicht nach neuer Prüfung –, und ohne Regelstand landete es in einem
/// Album, das es nicht gibt: eine Zeile, die nirgends zu sehen ist.
void main() {
  const konto = '00000000-0000-4000-8000-000000000001';
  late Directory ordner;
  late Bibliotheken bibliotheken;
  late Kontobereich bereich;
  late AppDatabase db;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_regel_ohne_album_');
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    bereich = await bibliotheken.fuer(konto);
    db = bereich.bibliothek.db;
    await db.fuehreAus(AlbumAnlegen('weg', 'Bald weg', DateTime(2026)));
    await db.fuehreAus(
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: 'r1',
          name: 'Urlaubsbilder',
          triggerType: 'dateiname',
          aiTagTerm: const Value('urlaub'),
          targetAlbumId: const Value('weg'),
          autoFavorite: const Value(true),
        ),
      ),
    );
    await db.upsertCameraPreset(
      CameraPresetsCompanion.insert(
        id: 'k1',
        cameraMake: 'Testkamera',
        cameraModel: 'T1',
        targetAlbumId: const Value('weg'),
      ),
    );
    // Gelöscht, wie es ein Gerät über den Abgleich tun kann.
    await (db.delete(db.albums)..where((a) => a.id.equals('weg'))).go();
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    await ordner.delete(recursive: true);
  });

  /// Ein JPEG der Testkamera, allein in einem eigenen Ordner – so, wie
  /// Hochladen es an den Import gibt.
  File foto(String name, int farbe) {
    final bild = img.Image(width: 32, height: 24)
      ..clear(img.ColorRgb8(farbe, 90, 200 - farbe));
    bild.exif.imageIfd['Make'] = 'Testkamera';
    bild.exif.imageIfd['Model'] = 'T1';
    return File('${ordner.path}/quelle_$farbe/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(bild));
  }

  Future<int> albumzeilen() async =>
      (await db.select(db.albumAssets).get()).length;

  test('Hochladen mit Regelstand nimmt das Foto an, ohne das Album', () async {
    final datei = foto('urlaub.jpg', 20);
    final stand = await ImportPlanDienst(
      db,
      bereich.bibliothek.importe,
    ).aktuellerRegelstand();
    final r = await bereich.hochladen.importiereDatei(datei, {
      'name': 'urlaub.jpg',
      'sha256': sha256.convert(datei.readAsBytesSync()).toString(),
      'regelstand': stand,
    });
    expect(r['ausgang'], 'imported', reason: '${r['fehler']}');
    final a = (await db.assetById(r['aufnahme']! as String))!;
    expect(a.cameraMake, 'Testkamera');
    expect(a.isFavorite, isTrue, reason: 'der Rest der Regel gilt');
    expect(await albumzeilen(), 0, reason: 'kein Album, das es nicht gibt');
  });

  test('ohne Regelstand und aus der Fotokammer: kein Foto in einem gelöschten '
      'Album', () async {
    final r = await bereich.hochladen.importiereDatei(foto('urlaub.jpg', 40), {
      'name': 'urlaub.jpg',
    });
    expect(r['ausgang'], 'imported', reason: '${r['fehler']}');
    expect((await db.assetById(r['aufnahme']! as String))!.isFavorite, isTrue);

    final gelegt = await bereich.kammer.lege(foto('urlaub.jpg', 60));
    expect(gelegt['ausgang'], 'kammer', reason: '${gelegt['fehler']}');
    final frei = await bereich.kammer.freigeben(gelegt['kammer']! as String);
    expect(frei['ausgang'], 'imported', reason: '${frei['fehler']}');
    expect(
      (await db.assetById(frei['aufnahme']! as String))!.isFavorite,
      isTrue,
    );

    expect(await albumzeilen(), 0, reason: 'kein Album, das es nicht gibt');
  });
}

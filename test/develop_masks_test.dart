import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Prüft die DB-Seite der KI-Objektmasken (siehe MaskEditor in
/// develop_screen.dart): Erstellen/Auflisten/Aktualisieren/Löschen,
/// insbesondere dass mehrere Masken pro Asset unabhängig voneinander
/// verwaltet werden und in Erstellreihenfolge zurückkommen (die native
/// Kompositierung legt sie in genau dieser Reihenfolge übereinander).
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> insertAsset(String id) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'checksum_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
        ));
    return id;
  }

  DevelopMasksCompanion mask({
    required String assetId,
    required String label,
    String path = 'masks/x.png',
  }) =>
      DevelopMasksCompanion.insert(
        assetId: assetId,
        maskRelativePath: path,
        label: label,
        createdAt: DateTime(2024, 1, 1),
      );

  test('createDevelopMask legt eine Maske mit neutralen Standard-Reglern an', () async {
    final assetId = await insertAsset('a');

    await db.createDevelopMask(mask(assetId: assetId, label: 'Himmel'));

    final masks = await db.masksForAsset(assetId);
    expect(masks, hasLength(1));
    expect(masks.single.label, 'Himmel');
    expect(masks.single.maskRelativePath, 'masks/x.png');
    expect(masks.single.exposure, 0);
    expect(masks.single.temperature, isNull);
    expect(masks.single.lensCorrectionEnabled, isTrue);
  });

  test('masksForAsset liefert nur Masken des angefragten Assets, in Erstellreihenfolge', () async {
    final a = await insertAsset('a');
    final b = await insertAsset('b');

    await db.createDevelopMask(mask(assetId: a, label: 'Erste', path: 'masks/1.png'));
    await db.createDevelopMask(mask(assetId: b, label: 'Andere', path: 'masks/2.png'));
    await db.createDevelopMask(mask(assetId: a, label: 'Zweite', path: 'masks/3.png'));

    final masksForA = await db.masksForAsset(a);
    expect(masksForA.map((m) => m.label), ['Erste', 'Zweite']);
  });

  test('updateDevelopMaskAdjustments ändert nur die Regler, Label/Pfad bleiben unverändert', () async {
    final assetId = await insertAsset('a');
    final id = await db.createDevelopMask(mask(assetId: assetId, label: 'Himmel'));

    await db.updateDevelopMaskAdjustments(
      id,
      const DevelopMasksCompanion(
        exposure: Value(0.8),
        contrast: Value(0.3),
        temperature: Value(5000),
        tint: Value(-5),
      ),
    );

    final updated = (await db.masksForAsset(assetId)).single;
    expect(updated.exposure, closeTo(0.8, 1e-9));
    expect(updated.contrast, closeTo(0.3, 1e-9));
    expect(updated.temperature, closeTo(5000, 1e-9));
    expect(updated.tint, closeTo(-5, 1e-9));
    expect(updated.label, 'Himmel'); // unverändert
    expect(updated.maskRelativePath, 'masks/x.png'); // unverändert
  });

  test('updateDevelopMaskShape aktualisiert nur shapeDefinitionJson, Regler bleiben unverändert', () async {
    final assetId = await insertAsset('a');
    final id = await db.createDevelopMask(mask(assetId: assetId, label: 'Himmel'));
    await db.updateDevelopMaskAdjustments(id, const DevelopMasksCompanion(exposure: Value(0.5)));

    await db.updateDevelopMaskShape(id, '{"type":"ellipse","cx":0.5,"cy":0.5,"rx":0.2,"ry":0.2}');

    final updated = (await db.masksForAsset(assetId)).single;
    expect(updated.shapeDefinitionJson, '{"type":"ellipse","cx":0.5,"cy":0.5,"rx":0.2,"ry":0.2}');
    expect(updated.exposure, closeTo(0.5, 1e-9)); // unverändert
  });

  test('createDevelopMask ohne shapeDefinitionJson (SAM-Maske) speichert null', () async {
    final assetId = await insertAsset('a');
    await db.createDevelopMask(mask(assetId: assetId, label: 'KI-Auswahl'));

    final saved = (await db.masksForAsset(assetId)).single;
    expect(saved.shapeDefinitionJson, isNull);
  });

  test('deleteDevelopMask entfernt nur die angegebene Maske, andere bleiben bestehen', () async {
    final assetId = await insertAsset('a');
    final keepId = await db.createDevelopMask(mask(assetId: assetId, label: 'Bleibt', path: 'masks/1.png'));
    final removeId = await db.createDevelopMask(mask(assetId: assetId, label: 'Weg', path: 'masks/2.png'));

    await db.deleteDevelopMask(removeId);

    final remaining = await db.masksForAsset(assetId);
    expect(remaining.map((m) => m.id), [keepId]);
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Benannte Entwicklungs-Vorgaben. Der Schritt über die Zwischenablage
/// hinaus: Sie haben einen Namen und bleiben.
///
/// Geprüft wird vor allem, dass Vorgaben und Zwischenablage **denselben**
/// Übertragungsweg benutzen – zwei Wege nebeneinander wären die
/// naheliegendste Art, dass einer beim nächsten neuen Regler etwas
/// vergisst.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService imp;
  late LibraryState lib;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_vorgaben_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    imp = ImportService(db, paths);
    lib = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<String> importiere(String name, int fuellung) async {
    final inc = Directory(p.join(tempRoot.path, 'in'))..createSync(recursive: true);
    final f = File(p.join(inc.path, name))..writeAsBytesSync(List.filled(64, fuellung));
    return (await imp.importFile(f.path)).assetId!;
  }

  Future<DevelopPresetData> legeVorgabe(String name) async {
    await db.upsertDevelopPreset(DevelopPresetsCompanion.insert(
      name: name,
      exposure: const Value(0.8),
      contrast: const Value(0.3),
      shadows: const Value(0.2),
      highlights: const Value(-0.6),
      clarity: const Value(0.4),
      vignette: const Value(-0.25),
      lutStrength: const Value(0.75),
      erstelltAm: DateTime.now(),
    ));
    return (await db.alleDevelopPresets()).firstWhere((v) => v.name == name);
  }

  test('eine Vorgabe laesst sich sichern und wiederfinden', () async {
    await legeVorgabe('Winterlandschaft');
    final alle = await db.alleDevelopPresets();
    expect(alle, hasLength(1));
    expect(alle.single.name, 'Winterlandschaft');
    expect(alle.single.highlights, -0.6);
  });

  test('der Name ist eindeutig', () async {
    await legeVorgabe('Kunstlicht');
    expect(await db.developPresetNameVergeben('Kunstlicht'), isTrue);
    expect(await db.developPresetNameVergeben('Tageslicht'), isFalse);
  });

  test('die eigene Vorgabe kollidiert beim Bearbeiten nicht mit sich selbst',
      () async {
    final v = await legeVorgabe('Portraet');
    expect(await db.developPresetNameVergeben('Portraet', ausserId: v.id), isFalse);
  });

  test('alle Werte wandern in die Reglerwerte - auch die vier, die das '
      'Kopieren frueher weggelassen hat', () async {
    // Klarheit, Vignette, Farbtabellenpfad und -staerke fehlten bis 1.9.5
    // beim Uebertragen. Ein kopierter "Look" liess damit ausgerechnet das
    // weg, was ihn ausmacht.
    final v = await legeVorgabe('Vollstaendig');
    final werte = await lib.werteAusVorgabe(v);

    expect(werte.regler.exposure, 0.8);
    expect(werte.regler.contrast, 0.3);
    expect(werte.regler.shadows, 0.2);
    expect(werte.regler.highlights, -0.6);
    expect(werte.regler.clarity, 0.4, reason: 'Klarheit muss mitwandern');
    expect(werte.regler.vignette, -0.25, reason: 'Vignette muss mitwandern');
    expect(werte.regler.lutStrength, 0.75, reason: 'LUT-Staerke muss mitwandern');
    expect(werte.quellAssetId, isNull,
        reason: 'eine Vorgabe gehoert zu keinem Foto');
  });

  test('eine Vorgabe wird als Quelle angenommen', () async {
    // Was dieser Test zeigen kann und was nicht: Das eigentliche Rendern
    // laeuft ueber den nativen Weg, den es im Unittest nicht gibt - die
    // Zielfotos bekommen hier also keine fertige Datei. Pruefbar ist der
    // Schritt davor, und genau der ist neu: dass eine Vorgabe ohne
    // Zwischenablage als Quelle zaehlt und die Ziele ausgewaehlt werden.
    // Ohne beides waere total 0 (siehe der Test darunter).
    final a = await importiere('a.jpg', 1);
    final b = await importiere('b.jpg', 2);
    final v = await legeVorgabe('Anwenden');

    final schritte = await lib
        .uebertrageEntwicklung([a, b], vorgabe: await lib.werteAusVorgabe(v))
        .toList();

    expect(schritte.first.total, 2,
        reason: 'beide Fotos muessen als Ziel angenommen werden');
    expect(lib.hatKopierteEntwicklung, isFalse,
        reason: 'und zwar ohne dass etwas in der Zwischenablage liegt');
  });

  test('ohne Vorgabe und ohne Zwischenablage passiert nichts', () async {
    final a = await importiere('c.jpg', 3);
    final schritte = await lib.uebertrageEntwicklung([a]).toList();
    expect(schritte.single.total, 0);
    expect(await db.developSettingsForAsset(a), isNull);
  });

  test('Loeschen entfernt nur die genannte Vorgabe', () async {
    final eins = await legeVorgabe('Eins');
    await legeVorgabe('Zwei');
    await db.deleteDevelopPreset(eins.id);
    final rest = await db.alleDevelopPresets();
    expect(rest.map((v) => v.name), ['Zwei']);
  });
}

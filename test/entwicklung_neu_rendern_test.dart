import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/develop_color.dart';
import 'package:kern/services/entwicklungswerte.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// „Alle Entwicklungen neu rendern“ (#283).
///
/// Bis 3.51 nahm der Lauf nur die acht Grundregler: Jedes Foto kam ohne
/// Tonwertkurve, Farbmischer, Farbtabelle, Klarheit und Vignette zurück –
/// in der Datei, die die App und jedes verbundene Gerät zeigen. Die Werte
/// selbst blieben in der Datenbank stehen, man sah sie nur nicht mehr.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kurve = ToneCurve(
    zusammen: [CurvePoint(0, 0), CurvePoint(0.5, 0.65), CurvePoint(1, 1)],
  );
  final mischer = ColorMixer.neutral.mitBand(
    ColorBand.blau,
    const BandAnpassung(saettigung: -0.5),
  );

  DevelopSettingsData einstellungen(String id, {String? lutPath}) =>
      DevelopSettingsData(
        assetId: id,
        exposure: 0.4,
        temperature: 5200,
        tint: 6,
        contrast: 0.2,
        shadows: 0.1,
        highlights: -0.3,
        sharpness: 0.25,
        noiseReduction: 0.15,
        lensCorrectionEnabled: false,
        clarity: 0.4,
        vignette: -0.3,
        lutPath: lutPath,
        lutStrength: 0.5,
        toneCurveJson: kurve.encode(),
        colorMixerJson: mischer.encode(),
        updatedAt: DateTime(2026, 9, 1, 10),
      );

  test('jede Spalte der Entwicklung kommt beim Renderer an', () {
    final r = reglerAusEinstellungen(einstellungen('a'));
    expect(
      [
        r.exposure,
        r.temperature,
        r.tint,
        r.contrast,
        r.shadows,
        r.highlights,
        r.sharpness,
        r.noiseReduction,
        r.clarity,
        r.vignette,
        r.lutStrength,
      ],
      [0.4, 5200, 6, 0.2, 0.1, -0.3, 0.25, 0.15, 0.4, -0.3, 0.5],
    );
    expect(r.lensCorrectionEnabled, isFalse);
    expect(r.toneCurve.encode(), kurve.encode());
    expect(r.colorMixer.encode(), mischer.encode());
  });

  test('eine neue Spalte muss auch hier ankommen', () {
    // Schlägt dieser Test fehl, hat die Tabelle eine Spalte bekommen, die
    // [reglerAusEinstellungen] noch nicht kennt. Genau so ist #283
    // entstanden: Klarheit, Vignette, Kurve, Mischer und Farbtabelle kamen
    // nach den Grundreglern dazu, und ein Weg kannte sie nicht.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      {for (final c in db.developSettings.$columns) c.name},
      {
        'asset_id', 'updated_at', //
        'exposure', 'temperature', 'tint', 'contrast', 'shadows',
        'highlights', 'sharpness', 'noise_reduction',
        'lens_correction_enabled', 'clarity', 'vignette', 'lut_path',
        'lut_strength', 'tone_curve_json', 'color_mixer_json',
      },
    );
  });

  test(
    'neu rendern schickt Kurve, Mischer und Farbtabelle mit und lässt die '
    'Einstellungen, wie sie sind',
    () async {
      final temp = Directory.systemTemp.createTempSync('pv_neu_rendern_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'lib')),
      );
      final lib = LibraryState()
        ..db = db
        ..paths = paths;

      final f = File(p.join(temp.path, 'foto.jpg'))
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 6)));
      final id = (await ImportService(db, paths).importFile(f.path)).assetId!;

      // Eine Farbtabelle, die nur Rot durchreicht.
      const lutPfad = 'luts/nur_rot.cube';
      final zeilen = <String>['LUT_3D_SIZE 2'];
      for (var b = 0; b < 2; b++) {
        for (var g = 0; g < 2; g++) {
          for (var r = 0; r < 2; r++) {
            zeilen.add('${r.toDouble()} 0.0 0.0');
          }
        }
      }
      paths.absolute(lutPfad)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(zeilen.join('\n'));

      final vorher = einstellungen(id, lutPath: lutPfad);
      await db.saveDevelopResult(
        id,
        settings: vorher.toCompanion(false),
        developedRelativePath: 'developed/$id-alt.jpg',
      );

      final gerendert = <Map<Object?, Object?>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('photo_vault/image_convert'),
            (aufruf) async {
              if (aufruf.method == 'developImage') {
                gerendert.add(aufruf.arguments as Map<Object?, Object?>);
                return Uint8List.fromList(
                  img.encodeJpg(img.Image(width: 8, height: 6)),
                );
              }
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('photo_vault/image_convert'),
              null,
            ),
      );

      await lib.redevelopAll().drain<void>();

      final a = gerendert.single;
      expect(a['toneCurveLut'], isNotNull, reason: 'die Kurve');
      expect(a['colorCube'], isNotNull, reason: 'Mischer und Farbtabelle');
      expect(a['clarity'], 0.4);
      expect(a['vignette'], -0.3);
      expect(a['lensCorrectionEnabled'], isFalse);

      final nachher = (await db.developSettingsForAsset(id))!;
      expect(nachher.toneCurveJson, vorher.toneCurveJson);
      expect(nachher.colorMixerJson, vorher.colorMixerJson);
      expect(nachher.lutPath, lutPfad);
      expect(nachher.lutStrength, 0.5);
      expect(nachher.clarity, 0.4);
      expect(nachher.vignette, -0.3);
      expect(
        nachher.updatedAt,
        vorher.updatedAt,
        reason: 'neu gerendert, nicht neu eingestellt',
      );
      final asset = (await db.assetById(id))!;
      expect(asset.developedRelativePath, isNot('developed/$id-alt.jpg'));
    },
    // Ausserhalb von macOS rendert der Shader (DevelopRender), nicht der
    // Kanal; den ersetzt dieser Test.
    skip: Platform.isMacOS ? false : 'der native Kanal gibt es nur unter macOS',
  );
}

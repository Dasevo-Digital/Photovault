import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/bearbeitung_zuruecknehmen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';

/// **Nicht-destruktiv heisst: es gibt einen Weg zurueck.**
///
/// Es gab ihn – aber nur dort, wo die Aenderung entstanden war: die
/// Entwicklung im Entwickeln-Bildschirm, die Restaurierung daneben, der
/// Zuschnitt im Video-Werkzeug. Wer eine Aufnahme vor sich hatte, musste
/// erst wissen, welches der drei Werkzeuge sie veraendert hatte.
///
/// [originalWiederherstellen] nimmt alle drei auf einmal zurueck – und
/// laesst das Original in Ruhe. Genau das prueft der letzte Fall: Nach
/// dem Wiederherstellen muss die Originaldatei noch da sein, mit
/// unveraendertem Inhalt. Ein „Zuruecksetzen", das das Original mit
/// loescht, waere schlimmer als gar keines.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_zurueck_');
    db = AppDatabase(NativeDatabase.memory());
    pfade =
        await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    for (var versuch = 0; versuch < 40 && wurzel.existsSync(); versuch++) {
      try {
        await wurzel.delete(recursive: true);
      } on FileSystemException {
        if (versuch == 39) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  /// Legt eine Datei mit Inhalt an und gibt ihren Pfad relativ zur
  /// Bibliothek zurueck.
  Future<String> datei(String relativ, String inhalt) async {
    final f = pfade.absolute(relativ);
    await f.parent.create(recursive: true);
    await f.writeAsString(inhalt);
    return relativ;
  }

  Future<AssetData> hole(String id) =>
      (db.select(db.assets)..where((t) => t.id.equals(id))).getSingle();

  Future<AssetData> aufnahme(String id, {String type = 'IMAGE'}) async {
    await datei('originals/$id.jpg', 'DAS ORIGINAL');
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c_$id',
          type: type,
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 1),
        ));
    return hole(id);
  }

  Future<void> entwickle(String id) async {
    final pfad = await datei('developed/$id.jpg', 'ENTWICKELT');
    await db.saveDevelopResult(id,
        settings: DevelopSettingsCompanion.insert(
          assetId: id,
          exposure: const Value(0.5),
          updatedAt: DateTime(2026, 2, 1),
        ),
        developedRelativePath: pfad);
    await db.createDevelopMask(DevelopMasksCompanion.insert(
      assetId: id,
      maskRelativePath: await datei('masks/$id-1.png', 'MASKE'),
      label: 'Himmel',
      createdAt: DateTime(2026, 2, 1),
    ));
  }

  test('eine unveraenderte Aufnahme hat nichts zurueckzunehmen', () async {
    final a = await aufnahme('a1');
    expect(bearbeitungsarten(a), isEmpty);
    expect(await originalWiederherstellen(db: db, paths: pfade, asset: a),
        isEmpty);
  });

  test('die Entwicklung samt Masken faellt weg', () async {
    await aufnahme('a1');
    await entwickle('a1');
    final bearbeitet = await hole('a1');
    expect(bearbeitungsarten(bearbeitet), {Bearbeitungsart.entwickelt});

    final genommen =
        await originalWiederherstellen(db: db, paths: pfade, asset: bearbeitet);
    expect(genommen, {Bearbeitungsart.entwickelt});

    final nachher = await hole('a1');
    expect(nachher.developedRelativePath, isNull);
    expect(await db.developSettingsForAsset('a1'), isNull);
    // Die Maskenbilder bleiben sonst als Waisen liegen – derselbe Rest,
    // den die 8. Pruefrunde bei den Gesichtsausschnitten gefunden hat.
    expect(await db.masksForAsset('a1'), isEmpty);
    expect(pfade.absolute('developed/a1.jpg').existsSync(), isFalse);
    expect(pfade.absolute('masks/a1-1.png').existsSync(), isFalse);
  });

  test('Restaurierung und Zuschnitt ebenso', () async {
    await aufnahme('v1', type: 'VIDEO');
    await db.into(db.restoreJobs).insert(RestoreJobsCompanion.insert(
          id: 'j1',
          assetId: 'v1',
          status: 'queued',
          createdAt: DateTime(2026, 2, 1),
        ));
    await db.completeRestoreJob(
        'j1', 'v1', await datei('restored/v1.jpg', 'RESTAURIERT'));
    await db.saveVideoTrim('v1',
        startSeconds: 1,
        endSeconds: 2,
        trimmedRelativePath: await datei('trimmed/v1.mp4', 'GESCHNITTEN'));

    final bearbeitet = await hole('v1');
    expect(bearbeitungsarten(bearbeitet),
        {Bearbeitungsart.restauriert, Bearbeitungsart.zugeschnitten});

    await originalWiederherstellen(db: db, paths: pfade, asset: bearbeitet);

    final nachher = await hole('v1');
    expect(nachher.restoredRelativePath, isNull);
    expect(nachher.trimmedRelativePath, isNull);
    expect(await db.videoTrimForAsset('v1'), isNull);
    expect(pfade.absolute('restored/v1.jpg').existsSync(), isFalse);
    expect(pfade.absolute('trimmed/v1.mp4').existsSync(), isFalse);
  });

  testWidgets('die Info-Ansicht zeigt den Weg zurueck', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // **Der Kachelspeicher der Karte braucht einen Ordner.** Die
    // Info-Ansicht baut eine kleine Karte mit auf; ohne Antwort auf die
    // Frage nach dem Zwischenspeicher wirft sie eine
    // `MissingPluginException` mitten in den Lauf - sichtbar erst unter
    // `runAsync`, weil erst dort die Zusagen wirklich zu Ende laufen.
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const ablage = MethodChannel('plugins.flutter.io/path_provider');
    bote.setMockMethodCallHandler(ablage, (_) async => wurzel.path);
    addTearDown(() => bote.setMockMethodCallHandler(ablage, null));

    // **Alles in `runAsync`.** Der Knopf loescht wirklich Dateien, und
    // ein `await` auf die Platte haengt unter der Uhr eines
    // Widget-Tests wortlos - dieselbe Falle wie beim Speicherbelegungs-
    // Test. Feste Takte statt `pumpAndSettle`, weil die Info-Ansicht
    // an Datenstroemen haengt, die nie zur Ruhe kommen.
    await tester.runAsync(() async {
      await aufnahme('a1');

      Future<void> takte() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      // Mit Schluessel, wie in der Vollbildansicht: Ohne ihn behielte
      // Flutter beim zweiten Aufbau denselben State, und der merkt sich
      // seine Aufnahme beim ersten Mal.
      var lauf = 0;
      Future<void> zeige(AssetData a) async {
        lauf++;
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: AssetInfoSheet(
              key: ValueKey(lauf),
              asset: a,
              db: db,
              paths: pfade,
              onUpdated: (_) {},
              onClose: () {},
            ),
          ),
        ));
        await takte();
      }

      // Unbearbeitet: kein Wort davon. Eine Zeile "Bearbeitet: nichts"
      // waere Rauschen an jeder einzelnen Aufnahme.
      await zeige(await hole('a1'));
      expect(find.text('Bearbeitet'), findsNothing);

      await entwickle('a1');
      await zeige(await hole('a1'));
      expect(find.text('Bearbeitet'), findsOneWidget);
      expect(find.textContaining('entwickelt'), findsOneWidget);

      // Und der Knopf daneben nimmt es zurueck - nach einer Rueckfrage.
      await tester
          .tapAt(tester.getCenter(find.byTooltip('Original wiederherstellen')));
      await takte();
      // Der Ja-Knopf traegt den Namen der Handlung. Stuende dort wie
      // ueberall sonst "Löschen", laese es sich, als werde das Original
      // geloescht.
      await tester.tapAt(tester.getCenter(
          find.widgetWithText(FilledButton, 'Original wiederherstellen')));
      await takte();

      expect((await hole('a1')).developedRelativePath, isNull);
      expect(find.text('Bearbeitet'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      // Der eingebaute Kachelspeicher hält auf Windows seinen
      // Größenwächter offen, bis er ausdrücklich beendet wird.
      await BuiltInMapCachingProvider.getOrCreateInstance()
          .destroy(deleteCache: true);
    });
  });

  test('das Original bleibt, wie es war', () async {
    await aufnahme('a1');
    await entwickle('a1');
    await originalWiederherstellen(
        db: db, paths: pfade, asset: await hole('a1'));

    final original = pfade.absolute('originals/a1.jpg');
    expect(original.existsSync(), isTrue);
    expect(original.readAsStringSync(), 'DAS ORIGINAL');
    // Und die Aufnahme selbst zeigt weiterhin darauf.
    expect((await hole('a1')).relativePath, 'originals/a1.jpg');
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';
import 'package:photo_vault/widgets/zoomsteuerung.dart';

class _LeereKacheln extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_pixel);
}

final _pixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// **Die Zoomknöpfe des Globus an den Grenzen.**
///
/// Sie hingen an der gemerkten Stufe, neu gebaut wurde aber nur beim
/// Zoomhinweis (Stufe 3). An Stufe 6 und an der kleinsten Stufe blieben
/// „Näher heran“ bzw. „Weiter weg“ bedienbar, ohne etwas zu tun.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    kachelAnbieterFuerTest = _LeereKacheln();
    wurzel = Directory.systemTemp.createTempSync('pv_globusknoepfe_');
    // Der Kachelspeicher des Globus fragt nach seinem Ordner. Ins Netz
    // geht im Prüfstand nichts: Jeder Abruf bekommt dort 400.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (aufruf) async => wurzel.path,
        );
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    await db.setzeKartenansicht('globus');
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'f',
            originalFileName: 'f.jpg',
            relativePath: 'o/f.jpg',
            checksum: 'c',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2025),
            latitude: const Value(47.0),
            longitude: const Value(11.0),
          ),
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    kachelAnbieterFuerTest = null;
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('an Stufe 6 und an der kleinsten Stufe werden die Knöpfe grau', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: MapScreen(library: library),
      ),
    );
    await warte(tester);
    Zoomsteuerung knoepfe() =>
        tester.widget<Zoomsteuerung>(find.byType(Zoomsteuerung));
    expect(knoepfe().beiNaeher, isNotNull);
    for (var i = 0; i < 12 && knoepfe().beiNaeher != null; i++) {
      knoepfe().beiNaeher!();
      await warte(tester);
    }
    expect(knoepfe().beiNaeher, isNull, reason: 'an Stufe 6 grau');
    expect(knoepfe().beiWeiter, isNotNull);
    for (var i = 0; i < 12 && knoepfe().beiWeiter != null; i++) {
      knoepfe().beiWeiter!();
      await warte(tester);
    }
    expect(knoepfe().beiWeiter, isNull, reason: 'an der kleinsten Stufe grau');
    expect(knoepfe().beiNaeher, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

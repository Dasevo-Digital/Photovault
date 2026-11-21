import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

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

/// **Stilwechsel bei hohem Zoom.**
///
/// Dunkel reicht bis 21, Topografie weniger weit. Nach dem Wechsel blieb
/// die Kamera über der neuen Grenze stehen, und gruppiert wurde wie bei
/// Stufe 6: drei Fotos als ein Sammelmarker.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = AppTexteDe();

  setUp(() async {
    kachelAnbieterFuerTest = _LeereKacheln();
    wurzel = Directory.systemTemp.createTempSync('pv_stilwechsel_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    await db.setzeKartenansicht('dunkel');
    // Drei Fotos je rund 150 m auseinander: bei Stufe 6 eine Gruppe,
    // ganz nah drei.
    for (var i = 0; i < 3; i++) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'f$i',
              originalFileName: 'f$i.jpg',
              relativePath: 'o/f$i.jpg',
              checksum: 'c$i',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025, 1, 1 + i),
              importedAt: DateTime(2025),
              latitude: const Value(47.0),
              longitude: Value(11.0 + i * 0.002),
            ),
          );
    }
  });

  tearDown(() async {
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

  testWidgets('nach Dunkel bei 21 → Topografie: Kamera an der Grenze, '
      'Fotos einzeln', (tester) async {
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
    MapController steuerung() =>
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    final dunkel = Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble();
    final topo = Kartenstil.topo.hoechsteAnzeigeStufe.toDouble();
    expect(topo, lessThan(dunkel));
    steuerung().move(const ll.LatLng(47.0, 11.002), dunkel);
    await warte(tester);
    expect(steuerung().camera.zoom, dunkel);

    await tester.tap(find.byTooltip(de.karteAnsicht));
    await warte(tester);
    await tester.tap(find.text(de.karteTopografie).last);
    await warte(tester);

    expect(steuerung().camera.zoom, lessThanOrEqualTo(topo));
    final fotomarker = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .last
        .markers;
    expect(fotomarker, hasLength(3), reason: 'einzeln, nicht wie bei Stufe 6');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

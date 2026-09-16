// Der Globus im ECHTEN Kartenbildschirm, nicht im nackten Widget.
//
// Braucht integration_test, weil die Kugel über einen Fragment-Shader
// gezeichnet wird – den gibt es in `flutter test` nicht.
//
// Geprüft wird beides: dass Scrollen zoomt, und dass die Pinzahl dabei
// gedeckelt bleibt. Ohne die Deckelung wuchs sie an einer echten
// Bibliothek (1092 verortete Fotos) von 222 auf 910, und ein Einzelbild
// brauchte am Ende 262 ms – bei vier Bildern je Sekunde wirkt der Globus
// nicht langsam, sondern kaputt.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'dart:io';
import 'dart:math';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Scrollzoom, gedeckelte Pinzahl und Zoomknöpfe', (tester) async {
    final temp = Directory.systemTemp.createTempSync('pv_kartezoom_');
    final db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    final lib = LibraryState()..db = db..paths = paths;
    // Ein paar verortete Fotos, damit Pins entstehen – die sitzen als
    // Flutter-Widgets ueber dem Globus.
    // So viele wie in der echten Bibliothek, und aehnlich verteilt:
    // der Grossteil in einer Stadt, der Rest verstreut. Genau darauf
    // kommt es an - die Pins entstehen je Rasterzelle.
    const anzahl = 1092;
    final zufall = Random(7);
    for (var i = 0; i < anzahl; i++) {
      final nah = i < anzahl * 0.8;
      final lat = nah ? 48.13 + zufall.nextDouble() * 0.2 : -60 + zufall.nextDouble() * 120;
      final lng = nah ? 11.57 + zufall.nextDouble() * 0.2 : -180 + zufall.nextDouble() * 360;
      await db.insertAsset(AssetsCompanion.insert(
        id: 'a$i', originalFileName: 'a$i.jpg', relativePath: 'originals/a$i.jpg',
        checksum: 'c$i', type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 1, 1), importedAt: DateTime.now(),
        fileSizeBytes: const Value(1),
        latitude: Value(lat), longitude: Value(lng),
      ));
    }

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: MapScreen(library: lib),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // In den Globus-Modus schalten.
    await tester.tap(find.byTooltip('Kartenansicht'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Globus').last);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final globus = find.byType(FlutterEarthGlobe);
    expect(globus, findsOneWidget);

    final mitte = tester.getCenter(globus);
    final zeiger = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(zeiger.hover(mitte));
    final vorher = tester.widget<FlutterEarthGlobe>(globus).controller.zoom;
    var meistePins = 0;
    for (var i = 0; i < 8; i++) {
      await tester.sendEventToBinding(zeiger.scroll(const Offset(0, -120)));
      await tester.pump(const Duration(milliseconds: 16));
      final c = tester.widget<FlutterEarthGlobe>(globus).controller;
      if (c.points.length > meistePins) meistePins = c.points.length;
    }
    final nachher = tester.widget<FlutterEarthGlobe>(globus).controller.zoom;
    expect(nachher, greaterThan(vorher), reason: 'Scrollen zoomt nicht');
    expect(meistePins, lessThan(400),
        reason: 'Pinzahl nicht gedeckelt – ohne Deckelung waren es 910');

    // Die Knöpfe: erst weiter weg, dann wieder näher heran.
    final raus = find.byTooltip('Weiter weg');
    final rein = find.byTooltip('Näher heran');
    expect(raus, findsOneWidget);
    expect(rein, findsOneWidget);

    await tester.tap(raus);
    await tester.pump(const Duration(milliseconds: 200));
    final nachRaus = tester.widget<FlutterEarthGlobe>(globus).controller.zoom;
    expect(nachRaus, lessThan(nachher), reason: 'Knopf „Weiter weg" wirkt nicht');

    await tester.tap(rein);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<FlutterEarthGlobe>(globus).controller.zoom,
        greaterThan(nachRaus),
        reason: 'Knopf „Näher heran" wirkt nicht');

    await db.close();
    temp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

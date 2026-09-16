import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';
import 'package:photo_vault/widgets/wisch_zoom.dart';

/// **Auch die kleine Karte muss sich zoomen lassen.**
///
/// Die grosse Karte bekam den Wischzoom, weil eine Maus ohne Rad (Magic
/// Mouse) und ein Trackpad sonst nur verschieben – siehe
/// `wisch_zoom_test.dart`. In der Info-Ansicht fehlte er, und Knöpfe gab
/// es dort auch nicht: Mit einer solchen Maus liess sich diese Karte
/// überhaupt nicht zoomen.
void main() {
  Widget karte() => const MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: MiniLocationMap(latitude: 51.9, longitude: 10.4, height: 300),
        ),
      );

  testWidgets('sie trägt beide Zoomknöpfe', (tester) async {
    await tester.pumpWidget(karte());
    await tester.pump();
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
  });

  testWidgets('der Knopf ändert die Stufe wirklich', (tester) async {
    await tester.pumpWidget(karte());
    await tester.pump();
    final steuerung =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
    final vorher = steuerung.camera.zoom;

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(steuerung.camera.zoom, greaterThan(vorher));

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(steuerung.camera.zoom, vorher);
  });

  testWidgets('sie hängt im Wischzoom – sonst zoomt keine Magic Mouse',
      (tester) async {
    await tester.pumpWidget(karte());
    await tester.pump();
    expect(find.byType(WischZoom), findsOneWidget);
  });

  testWidgets('eine Trackpad-Geste ändert die Stufe', (tester) async {
    await tester.pumpWidget(karte());
    await tester.pump();

    final mitte = tester.getCenter(find.byType(FlutterMap));
    final zeiger = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(zeiger.panZoomStart(mitte));
    await tester.pump();
    await tester.sendEventToBinding(
        zeiger.panZoomUpdate(mitte, pan: const Offset(0, -120)));
    await tester.pump();
    await tester.sendEventToBinding(zeiger.panZoomEnd());
    await tester.pump();

    // Der Beleg steht in der Kamera, nicht im Widget: `initialZoom`
    // bleibt, was es war.
    final karteWidget = tester.widget<FlutterMap>(find.byType(FlutterMap));
    final steuerung = karteWidget.mapController!;
    expect(steuerung.camera.zoom, greaterThan(karteWidget.options.initialZoom),
        reason: 'Wischen nach oben muss heranzoomen');
  });
}

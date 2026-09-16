import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/reiseroute.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/routenkarte.dart';

/// **Die Übersichtskarte liess sich nicht bedienen.**
///
/// Sie war mit Absicht unbeweglich – eine Karte, die das Mausrad
/// annimmt, verschluckt inmitten einer rollbaren Seite jeden zweiten
/// Wisch. Der Preis war, dass man in eine Reise über drei Länder nicht
/// hineinsehen konnte.
///
/// Die Auflösung sind Knöpfe: Sie kommen dem Rollen der Seite nicht in
/// die Quere. Geprüft wird deshalb beides – dass die Knöpfe wirken, und
/// dass Rad und Kneifen weiterhin **nicht** an der Karte hängen.
void main() {
  late Directory wurzel;
  late StoragePaths paths;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_route_');
    paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
  });

  tearDown(() => wurzel.deleteSync(recursive: true));

  /// Eine Strecke über rund 40 km – gross genug, dass Hineinzoomen
  /// überhaupt einen Unterschied macht.
  List<Routenpunkt> route() => [
        (breite: 50.10, laenge: 8.60, zeit: DateTime(2026, 7, 1, 9)),
        (breite: 50.25, laenge: 8.75, zeit: DateTime(2026, 7, 1, 12)),
        (breite: 50.40, laenge: 8.90, zeit: DateTime(2026, 7, 1, 15)),
      ];

  Future<void> zeige(WidgetTester tester, {double hoehe = 240}) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Routenkarte(
            route: route(),
            orte: const [],
            nachId: const {},
            paths: paths,
            beiOrt: (_) {},
            hoehe: hoehe,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  double zoom(WidgetTester tester) =>
      tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!.camera
          .zoom;

  double hoeheDerKarte(WidgetTester tester) =>
      tester.getRect(find.byType(FlutterMap)).height;

  testWidgets('die vier Knoepfe stehen da', (tester) async {
    await zeige(tester);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.fit_screen_outlined), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
  });

  testWidgets('plus zoomt hinein, minus wieder heraus', (tester) async {
    await zeige(tester);
    final anfang = zoom(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    final nachRein = zoom(tester);
    expect(nachRein, greaterThan(anfang));

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect(zoom(tester), closeTo(anfang, 0.001));
  });

  testWidgets('einpassen fuehrt zurueck auf die Strecke', (tester) async {
    await zeige(tester);
    final anfang = zoom(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
    expect(zoom(tester), greaterThan(anfang));

    await tester.tap(find.byIcon(Icons.fit_screen_outlined));
    await tester.pump();
    expect(zoom(tester), closeTo(anfang, 0.01));
  });

  testWidgets('der Vergroessern-Knopf macht die Karte hoeher und wieder klein',
      (tester) async {
    await zeige(tester, hoehe: 200);
    expect(hoeheDerKarte(tester), closeTo(200, 0.5));

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    expect(hoeheDerKarte(tester), closeTo(200 * 1.8, 0.5));

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pump();
    expect(hoeheDerKarte(tester), closeTo(200 * 2.8, 0.5));
    // Auf der letzten Stufe bietet der Knopf den Rueckweg an.
    expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_fullscreen));
    await tester.pump();
    expect(hoeheDerKarte(tester), closeTo(200, 0.5));
  });

  testWidgets('das Mausrad gehoert weiterhin der Seite, nicht der Karte',
      (tester) async {
    // Der Grund, aus dem die Karte ueberhaupt unbeweglich war. Ein
    // Zoomknopf loest das Problem nur, wenn das Rad NICHT auch zoomt.
    await zeige(tester);
    final optionen =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
    final flags = optionen.interactionOptions.flags;
    expect(InteractiveFlag.hasScrollWheelZoom(flags), isFalse);
    expect(InteractiveFlag.hasPinchZoom(flags), isFalse);
    // Ziehen dagegen muss gehen - sonst kaeme man aus einer Ecke nicht
    // mehr heraus.
    expect(InteractiveFlag.hasDrag(flags), isTrue);
  });

  testWidgets('zoomen bleibt unter der hoechsten Kachelstufe', (tester) async {
    // Ueber der letzten Stufe, fuer die es Kacheln gibt, wuerde die Karte
    // grau - der Knopf muss dort aufhoeren.
    await zeige(tester);
    final grenze =
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options.maxZoom!;
    for (var i = 0; i < 30; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
    }
    expect(zoom(tester), lessThanOrEqualTo(grenze));
  });
}

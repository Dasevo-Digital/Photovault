import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/gelaende_screen.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/gelaende.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';

/// Die Geländeansicht am Bildschirm.
///
/// Ohne Netz: Die Kacheln kommen aus einem gestellten Client. Geprüft
/// wird, was ohne Server prüfbar ist – dass aus Kacheln eine Landschaft
/// wird, dass ein Ausfall als Ausfall dasteht statt als leere Fläche,
/// und dass die Spur ankommt.
Future<Uint8List> _terrariumKachel({double meter = 500}) async {
  const kante = 256;
  final rgba = Uint8List(kante * kante * 4);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      // Eine Rampe von [meter] auf [meter]+400 nach Osten.
      final h = meter + x / kante * 400;
      final roh = (h + 32768).round();
      final i = (y * kante + x) * 4;
      rgba[i] = roh >> 8;
      rgba[i + 1] = roh & 255;
      rgba[i + 2] = 0;
      rgba[i + 3] = 255;
    }
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, kante, kante, ui.PixelFormat.rgba8888, fertig.complete);
  final bild = await fertig.future;
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

void main() {
  late Uint8List kachel;

  setUpAll(() async => kachel = await _terrariumKachel());

  Future<void> zeige(
    WidgetTester tester, {
    required http.Client netz,
    Gelaendekarte auflage = const Gelaendekarte(grund: Gelaendegrund.wanderkarte),
    List<Gelaendespurpunkt> spur = const [
      (breite: 50.61, laenge: 9.86, hoehe: 400.0, zeit: null),
      (breite: 50.62, laenge: 9.88, hoehe: 620.0, zeit: null),
      (breite: 50.63, laenge: 9.90, hoehe: 550.0, zeit: null),
    ],
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: GelaendeScreen(
          spur: spur, titel: 'Brocken', netz: netz, auflage: auflage),
    ));
    // Das Laden läuft über echte Futures – ohne runAsync kehrt es in der
    // gestellten Zeit eines Widget-Tests nie zurück.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(Gelaendeansicht).evaluate().isNotEmpty) return;
      if (find.textContaining('keine Geländehöhen').evaluate().isNotEmpty) {
        return;
      }
    }
  }

  testWidgets('aus Kacheln wird eine Landschaft', (tester) async {
    var abrufe = 0;
    await zeige(tester, netz: MockClient((anfrage) async {
      abrufe++;
      return http.Response.bytes(kachel, 200);
    }));

    expect(find.byType(Gelaendeansicht), findsOneWidget);
    expect(abrufe, greaterThan(0));
    // Höhen und Karte werden beide geholt – Berge ohne Wege sind keine
    // Auskunft.
    final ansicht =
        tester.widget<Gelaendeansicht>(find.byType(Gelaendeansicht));
    expect(ansicht.karte, isNotNull);
    expect(ansicht.netz.dreiecke, greaterThan(1000));
    // Die Spur ist dabei, in Metern.
    expect(ansicht.spur, hasLength(3));
  });

  testWidgets('ohne Höhenkacheln steht der Ausfall da, nicht eine leere Fläche',
      (tester) async {
    await zeige(tester,
        netz: MockClient((anfrage) async => http.Response('weg', 404)));
    expect(find.byType(Gelaendeansicht), findsNothing);
    expect(find.textContaining('keine Geländehöhen'), findsOneWidget);
    // Und ein Knopf, es noch einmal zu versuchen: Der häufigste Grund
    // ist eine Verbindung, die gerade nicht da war.
    expect(find.text('Noch einmal versuchen'), findsOneWidget);
  });

  testWidgets('fällt die Karte aus, bleibt die Landschaft', (tester) async {
    // Nur die Kartenkacheln scheitern. Ein Gelände ohne Karte ist
    // weniger, aber es ist nicht nichts.
    await zeige(tester, netz: MockClient((anfrage) async {
      if (anfrage.url.host.contains('opentopomap')) {
        return http.Response('weg', 500);
      }
      return http.Response.bytes(kachel, 200);
    }));
    final ansicht =
        tester.widget<Gelaendeansicht>(find.byType(Gelaendeansicht));
    expect(ansicht.karte, isNull);
    expect(ansicht.netz.dreiecke, greaterThan(1000));
  });

  testWidgets('eine einzelne fehlende Kachel nimmt die Landschaft nicht mit',
      (tester) async {
    // Fünfzehn von sechzehn Kacheln ergeben eine Landschaft mit einem
    // Loch; null Kacheln ergeben nichts.
    var erste = true;
    await zeige(tester, netz: MockClient((anfrage) async {
      if (erste && anfrage.url.host.contains('amazonaws')) {
        erste = false;
        return http.Response('weg', 404);
      }
      return http.Response.bytes(kachel, 200);
    }));
    expect(find.byType(Gelaendeansicht), findsOneWidget);
  });

  testWidgets('die Bedienung und die Quellen stehen dabei', (tester) async {
    await zeige(tester,
        netz: MockClient((anfrage) async => http.Response.bytes(kachel, 200)));
    expect(find.textContaining('Ziehen dreht und kippt'), findsOneWidget);
    // Namensnennung ist bei OpenTopoMap keine Höflichkeit, sondern die
    // Lizenz.
    expect(find.textContaining('opentopomap.org'), findsOneWidget);
    expect(find.textContaining('Tilezen'), findsOneWidget);
  });

  testWidgets('die Namensnennung nennt genau die Ebenen, die im Bild stehen',
      (tester) async {
    // Eine Lizenzauflage ist keine Zierleiste: Wer die Wegeebene
    // abschaltet, soll Waymarked Trails nicht mehr genannt sehen - und
    // wer sie einschaltet, muss ihn nennen.
    await zeige(tester,
        auflage: const Gelaendekarte(
            grund: Gelaendegrund.luftbild, wege: true, beschriftung: true),
        netz: MockClient((anfrage) async => http.Response.bytes(kachel, 200)));
    expect(find.textContaining('Esri'), findsOneWidget);
    expect(find.textContaining('waymarkedtrails'), findsOneWidget);
    expect(find.textContaining('opentopomap.org'), findsNothing);
  });

  group('Die Karte auf der Landschaft laesst sich waehlen', () {
    // Gewuenscht als „nutze eine 3D-Satellitenkarte fuer den Flug": Die
    // Landschaft war immer mit OpenTopoMap texturiert, egal was auf dem
    // Kartenbildschirm eingestellt war.

    testWidgets('der uebergebene Stil bestimmt, welche Kacheln geholt werden',
        (tester) async {
      final adressen = <String>[];
      await zeige(tester,
          auflage: const Gelaendekarte(grund: Gelaendegrund.hell),
          netz: MockClient((anfrage) async {
        adressen.add(anfrage.url.host);
        return http.Response.bytes(kachel, 200);
      }));
      expect(find.byType(Gelaendeansicht), findsOneWidget);
      // Die Hoehen kommen immer von derselben Quelle; die Karte nicht.
      expect(adressen.any((h) => h.contains('openstreetmap')), isTrue);
      expect(adressen.any((h) => h.contains('opentopomap')), isFalse,
          reason: 'bei „hell" hat OpenTopoMap nichts zu suchen');
    });

    testWidgets('ohne Angabe bleibt es bei der Wanderkarte', (tester) async {
      final adressen = <String>[];
      await zeige(tester, netz: MockClient((anfrage) async {
        adressen.add(anfrage.url.host);
        return http.Response.bytes(kachel, 200);
      }));
      expect(adressen.any((h) => h.contains('opentopomap')), isTrue);
    });

    testWidgets('umschalten holt die Karte neu, aber nicht die Hoehen',
        (tester) async {
      // Das Hoehengitter haengt am Ausschnitt und nicht am Stil - es ein
      // zweites Mal zu laden waeren Sekunden fuer nichts.
      final hoehen = <String>[];
      final karten = <String>[];
      await zeige(tester, netz: MockClient((anfrage) async {
        final h = anfrage.url.host;
        (h.contains('terrarium') || h.contains('elevation') ||
                anfrage.url.path.contains('terrarium')
            ? hoehen
            : karten)
            .add(anfrage.url.toString());
        return http.Response.bytes(kachel, 200);
      }));
      final hoehenVorher = hoehen.length;
      final kartenVorher = karten.length;
      expect(hoehenVorher, greaterThan(0));

      await tester.tap(find.byIcon(Icons.layers_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hell'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (karten.length > kartenVorher) break;
      }
      expect(karten.length, greaterThan(kartenVorher),
          reason: 'die Karte muss neu geholt werden');
      expect(hoehen.length, hoehenVorher,
          reason: 'die Hoehen aber nicht');
    });
  });
}

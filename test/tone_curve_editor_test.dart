import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/develop_color.dart';
import 'package:photo_vault/widgets/color_mixer_panel.dart';
import 'package:photo_vault/widgets/tone_curve_editor.dart';

/// Die Bedienung von Tonwertkurve und Farbmischer.
///
/// Die Mathematik dahinter ist getrennt geprüft (develop_color_test.dart);
/// hier geht es um das, was der Nutzer mit der Maus anrichten kann – und
/// vor allem darum, dass er die Kurve nicht in einen Zustand bringen kann,
/// den die Interpolation nicht mehr auswerten kann.
void main() {
  /// Baut den Editor und gibt einen Zugriff auf den jeweils letzten Stand
  /// zurück. Feste Grösse, damit sich Bildschirmkoordinaten ausrechnen
  /// lassen: Das Raster ist quadratisch, also 300×300.
  Future<({ToneCurve Function() stand, int Function() endeGezaehlt})> baueEditor(
    WidgetTester tester, {
    ToneCurve start = ToneCurve.neutral,
  }) async {
    var aktuell = start;
    var enden = 0;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) => ToneCurveEditor(
                curve: aktuell,
                histogram: null,
                onChanged: (k) => setState(() => aktuell = k),
                onChangeEnd: () => enden++,
              ),
            ),
          ),
        ),
      ),
    ));
    return (stand: () => aktuell, endeGezaehlt: () => enden);
  }

  /// Bildschirmpunkt innerhalb des 300×300-Rasters für Kurvenkoordinaten.
  Offset stelle(WidgetTester tester, double eingang, double ausgang) {
    final raster = tester.getRect(find.byKey(toneCurveRasterKey));
    return Offset(
      raster.left + eingang * raster.width,
      raster.top + (1 - ausgang) * raster.height,
    );
  }

  testWidgets('frisch ist die Kurve die Gerade', (tester) async {
    final e = await baueEditor(tester);
    expect(e.stand().istNeutral, isTrue);
    expect(find.text('Tonwertkurve'), findsOneWidget);
  });

  testWidgets('Ziehen in der Fläche legt einen Punkt an und meldet das Ende',
      (tester) async {
    final e = await baueEditor(tester);

    await tester.dragFrom(stelle(tester, 0.5, 0.5), const Offset(0, -30));
    await tester.pumpAndSettle();

    final punkte = e.stand().zusammen;
    expect(punkte, hasLength(3), reason: 'zwei Enden plus der neue Punkt');
    expect(punkte[1].input, closeTo(0.5, 0.05));
    expect(punkte[1].output, greaterThan(0.5), reason: 'nach oben gezogen');
    expect(e.endeGezaehlt(), 1, reason: 'ein nativer Render nach dem Loslassen');
  });

  testWidgets('ein Endpunkt bleibt am Rand und lässt sich nur heben',
      (tester) async {
    // Sonst hätte die Kurve einen Bereich ohne Definition – links von
    // einem nach innen gezogenen Startpunkt wüsste niemand, was gilt.
    final e = await baueEditor(tester);

    // Ein paar Pixel hinein statt genau auf die Ecke: Die untere Kante
    // gehört nicht mehr zur Trefferfläche, dort käme gar kein Zeiger an.
    // Der Fangradius greift den Endpunkt von hier aus mühelos.
    await tester.dragFrom(stelle(tester, 0.02, 0.02), const Offset(60, -45));
    await tester.pumpAndSettle();

    final erster = e.stand().zusammen.first;
    expect(erster.input, 0.0, reason: 'darf nicht nach rechts wandern');
    expect(erster.output, greaterThan(0.0), reason: 'aber anheben geht');
  });

  testWidgets('ein Punkt überholt seine Nachbarn nicht', (tester) async {
    // Eine unsortierte Punktfolge wäre für die Interpolation ein Bruch:
    // Zwei Punkte auf derselben Senkrechten ergäben eine Division durch null.
    const start = ToneCurve(zusammen: [
      CurvePoint(0, 0),
      CurvePoint(0.3, 0.3),
      CurvePoint(0.6, 0.6),
      CurvePoint(1, 1),
    ]);
    final e = await baueEditor(tester, start: start);

    // Den mittleren Punkt weit nach rechts über seinen Nachbarn hinaus.
    await tester.dragFrom(stelle(tester, 0.3, 0.3), const Offset(200, 0));
    await tester.pumpAndSettle();

    final punkte = e.stand().zusammen;
    for (var i = 1; i < punkte.length; i++) {
      expect(punkte[i].input, greaterThan(punkte[i - 1].input),
          reason: 'die Folge muss geordnet bleiben: $punkte');
    }
  });

  testWidgets('langes Drücken entfernt einen Punkt, aber kein Ende',
      (tester) async {
    const start = ToneCurve(zusammen: [
      CurvePoint(0, 0),
      CurvePoint(0.5, 0.7),
      CurvePoint(1, 1),
    ]);
    final e = await baueEditor(tester, start: start);

    await tester.longPressAt(stelle(tester, 0, 0));
    await tester.pumpAndSettle();
    expect(e.stand().zusammen, hasLength(3), reason: 'das Ende bleibt');

    await tester.longPressAt(stelle(tester, 0.5, 0.7));
    await tester.pumpAndSettle();
    expect(e.stand().zusammen, hasLength(2));
    expect(e.stand().istNeutral, isTrue);
  });

  testWidgets('der Kanalwechsel lässt die anderen Kanäle unberührt',
      (tester) async {
    final e = await baueEditor(tester);

    await tester.tap(find.text('R'));
    await tester.pumpAndSettle();
    await tester.dragFrom(stelle(tester, 0.5, 0.5), const Offset(0, -40));
    await tester.pumpAndSettle();

    expect(e.stand().rot, hasLength(3));
    expect(e.stand().gruen, hasLength(2), reason: 'Grün bleibt die Gerade');
    expect(e.stand().blau, hasLength(2));
    expect(e.stand().zusammen, hasLength(2));
  });

  testWidgets('"Kanal zurücksetzen" wirkt nur auf den sichtbaren Kanal',
      (tester) async {
    const start = ToneCurve(
      zusammen: [CurvePoint(0, 0), CurvePoint(0.4, 0.8), CurvePoint(1, 1)],
      blau: [CurvePoint(0, 0.1), CurvePoint(1, 1)],
    );
    final e = await baueEditor(tester, start: start);

    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();

    expect(e.stand().zusammen, hasLength(2));
    expect(e.stand().blau.first.output, 0.1, reason: 'Blau war nicht gemeint');
  });

  testWidgets('bei neutralem Kanal ist Zurücksetzen abgeschaltet', (tester) async {
    await baueEditor(tester);
    final knopf = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Zurücksetzen'));
    expect(knopf.onPressed, isNull);
  });

  group('Farbmischer', () {
    Future<({ColorMixer Function() stand, int Function() endeGezaehlt})> baueMischer(
      WidgetTester tester, {
      ColorMixer start = ColorMixer.neutral,
    }) async {
      var aktuell = start;
      var enden = 0;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) => ColorMixerPanel(
                  mixer: aktuell,
                  onChanged: (m) => setState(() => aktuell = m),
                  onChangeEnd: () => enden++,
                ),
              ),
            ),
          ),
        ),
      ));
      return (stand: () => aktuell, endeGezaehlt: () => enden);
    }

    testWidgets('alle acht Bänder stehen zur Wahl', (tester) async {
      await baueMischer(tester);
      expect(find.byType(Tooltip), findsNWidgets(ColorBand.values.length));
      expect(find.text('Farbton'), findsOneWidget);
      expect(find.text('Sättigung'), findsOneWidget);
      expect(find.text('Helligkeit'), findsOneWidget);
    });

    testWidgets('ein Regler ändert nur das ausgewählte Band', (tester) async {
      final e = await baueMischer(tester);

      await tester.tap(find.byTooltip('Grün'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider).at(1), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(e.stand().band(ColorBand.gruen).saettigung, greaterThan(0));
      expect(e.stand().band(ColorBand.gruen).farbton, 0);
      for (final band in ColorBand.values.where((b) => b != ColorBand.gruen)) {
        expect(e.stand().band(band).istNeutral, isTrue, reason: band.name);
      }
      expect(e.endeGezaehlt(), 1);
    });

    testWidgets('"Band zurücksetzen" räumt nur dieses eine Band', (tester) async {
      const start = ColorMixer({
        ColorBand.rot: BandAnpassung(farbton: 0.5),
        ColorBand.blau: BandAnpassung(saettigung: -0.5),
      });
      final e = await baueMischer(tester, start: start);

      // Rot ist beim Öffnen ausgewählt.
      await tester.tap(find.text('Zurücksetzen'));
      await tester.pumpAndSettle();

      expect(e.stand().band(ColorBand.rot).istNeutral, isTrue);
      expect(e.stand().band(ColorBand.blau).saettigung, -0.5);
    });

    testWidgets('bei neutralem Band ist Zurücksetzen abgeschaltet', (tester) async {
      await baueMischer(tester);
      final knopf =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Zurücksetzen'));
      expect(knopf.onPressed, isNull);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/histogram.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/histogram_view.dart';

import 'goldbilder.dart';

/// Die vier Anzeigen des Histogramm-Bedienfelds.
///
/// Eine Waveform lässt sich schlecht behaupten – man muss sie ansehen.
/// Deshalb neben den Prüfungen ein Abbild; an das echte Fenster kommt man
/// in dieser Umgebung nicht heran.
void main() {
  /// Ein Verlauf von links dunkel nach rechts hell, mit einem Farbstich,
  /// der nach rechts zunimmt – so ist in jeder der vier Ansichten etwas
  /// anderes zu sehen.
  img.Image testbild() {
    final bild = img.Image(width: 400, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 400; x++) {
        final t = x / 399;
        bild.setPixelRgb(
          x, y,
          (t * 255).round(),
          (t * 200).round(),
          (t * 120).round(),
        );
      }
    }
    return bild;
  }

  Future<void> zeige(WidgetTester tester) async {
    final bild = testbild();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: HistogramView(
              data: computeHistogram(bild),
              waveform: computeWaveform(bild),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('alle vier Ansichten bauen ohne Fehler', (tester) async {
    await zeige(tester);
    for (final name in ['Helligkeit', 'RGB', 'Waveform', 'Parade']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
    }
  });

  testWidgets('ohne Waveform-Daten bleibt der Kasten leer statt zu stürzen',
      (tester) async {
    // Der Zustand direkt nach dem Öffnen: Das Histogramm ist da, die
    // Waveform noch nicht.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
            width: 360, child: HistogramView(data: computeHistogram(testbild()))),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waveform'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Vorschau'), findsOneWidget);
  });

  testWidgets('so sieht die Waveform aus', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Waveform'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HistogramView),
      matchesGoldenFile('golden/waveform.png'),
    );
  }, skip: nurAufReferenzplattform);

  testWidgets('so sieht die Parade aus', (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Parade'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HistogramView),
      matchesGoldenFile('golden/parade.png'),
    );
  }, skip: nurAufReferenzplattform);
}

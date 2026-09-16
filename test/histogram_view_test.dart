import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/histogram.dart';
import 'package:photo_vault/widgets/histogram_view.dart';

/// Waagerechter Schwarz-nach-Weiß-Verlauf mit einem kräftigen Rotanteil –
/// belegt viele Tonwertstufen UND unterscheidet die Kanäle deutlich, damit
/// sich Helligkeits- und RGB-Darstellung messbar unterscheiden müssen.
HistogramData _sampleData() {
  final image = img.Image(width: 256, height: 32);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgb(x, y, x, (x * 0.4).round(), (x * 0.1).round());
    }
  }
  return computeHistogram(image);
}

/// Rendert [key]s Grenze und zählt gezeichnete Pixel.
Future<({int nonBlack, int colored, int total})> _measure(
  WidgetTester tester,
  GlobalKey key,
) async {
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // toImage()/toByteData() sind echte, asynchrone Engine-Aufrufe – im
  // Widget-Test läuft die Zeit sonst simuliert weiter und das Future würde
  // nie abgeschlossen (der Test hinge). runAsync() gibt ihnen echte Zeit.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }) as Uint8List;

  var nonBlack = 0;
  var colored = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
    if (r + g + b > 40) nonBlack++;
    final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
    // Deutlich farbiger (nicht grau/weiß) Pixel.
    if (maxC - minC > 50) colored++;
  }
  return (nonBlack: nonBlack, colored: colored, total: bytes.length ~/ 4);
}

Future<void> _pumpView(WidgetTester tester, GlobalKey key, HistogramData? data) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 300, child: HistogramView(data: data)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zeichnet im Helligkeitsmodus sichtbare, überwiegend graue Pixel', (tester) async {
    final key = GlobalKey();
    await _pumpView(tester, key, _sampleData());

    final result = await _measure(tester, key);

    expect(result.nonBlack, greaterThan(0), reason: 'es muss überhaupt etwas gezeichnet werden');
    // Die Luminanzfläche ist weiß – nennenswert farbige Pixel dürfen hier
    // nicht auftreten (die kämen nur aus den RGB-Kurven).
    expect(
      result.colored / result.total,
      lessThan(0.02),
      reason: 'Helligkeitsmodus zeichnet keine farbigen Kurven',
    );
  });

  testWidgets('nach Umschalten auf RGB werden farbige Kurven gezeichnet', (tester) async {
    final key = GlobalKey();
    await _pumpView(tester, key, _sampleData());

    final before = await _measure(tester, key);

    await tester.tap(find.text('RGB'));
    await tester.pumpAndSettle();

    final after = await _measure(tester, key);

    expect(
      after.colored,
      greaterThan(before.colored),
      reason: 'der RGB-Modus muss farbige Kanalkurven zeigen',
    );
    expect(after.colored / after.total, greaterThan(0.02));
  });

  testWidgets('lässt sich wieder auf Helligkeit zurückschalten', (tester) async {
    final key = GlobalKey();
    await _pumpView(tester, key, _sampleData());

    await tester.tap(find.text('RGB'));
    await tester.pumpAndSettle();
    final rgb = await _measure(tester, key);

    await tester.tap(find.text('Helligkeit'));
    await tester.pumpAndSettle();
    final luminance = await _measure(tester, key);

    expect(luminance.colored, lessThan(rgb.colored));
  });

  testWidgets('zeigt einen Hinweis statt einer leeren Fläche, solange keine Daten vorliegen', (tester) async {
    final key = GlobalKey();
    await _pumpView(tester, key, null);

    expect(find.text('Noch keine Vorschau'), findsOneWidget);
    // Die Umschalter bleiben trotzdem bedienbar sichtbar.
    expect(find.text('Helligkeit'), findsOneWidget);
    expect(find.text('RGB'), findsOneWidget);
  });

  testWidgets('behandelt ein leeres Histogramm wie fehlende Daten', (tester) async {
    final key = GlobalKey();
    await _pumpView(tester, key, HistogramData.empty());

    expect(find.text('Noch keine Vorschau'), findsOneWidget);
  });

  testWidgets('zeigt den Ladehinweis nur bei isStale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: HistogramView(data: _sampleData(), isStale: true)),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: HistogramView(data: _sampleData())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

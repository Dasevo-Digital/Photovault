// **Was die Flugleiste in jedem Bild kostet.**
//
// Der Flug baut die Ansicht in jedem Bild neu – die Uhr ruft `setState`.
// Darin steckt das Höhenprofil, und das legt seine Punkte bei jedem
// Durchgang neu an: eine Liste über JEDEN Punkt der Spur. Eine
// Tageswanderung hat viertausend davon, und dreissigmal je Sekunde
// viertausend Datensätze anzulegen ist etwas anderes als sie zu zeichnen.
//
//   PV_SPUR=/tmp/spur.csv flutter test tool/messe_flugleiste_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

void main() {
  testWidgets('Neubau der Leiste im Flug', (tester) async {
    // Die echte Spur, wenn eine da ist – sonst eine gleich lange
    // gerechnete, damit die Zahl auch ohne Bibliothek entsteht.
    final pfad = Platform.environment['PV_SPUR'];
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    final start = DateTime.utc(2026, 9, 3, 8);
    if (pfad != null) {
      final zeilen = File(pfad).readAsLinesSync();
      var i = 0;
      double? b0, l0;
      for (final z in zeilen) {
        final t = z.split(',');
        if (t.length < 3) continue;
        final b = double.tryParse(t[0]), l = double.tryParse(t[1]);
        final h = double.tryParse(t[2]);
        if (b == null || l == null) continue;
        b0 ??= b;
        l0 ??= l;
        linie.add((
          x: (l - l0) * meterJeGradLaenge(b),
          y: (b - b0) * meterJeGradBreite,
          z: (h ?? 0) * gelaendeUeberhoehung,
        ));
        werte.add((hoehe: h, zeit: start.add(Duration(seconds: i * 12))));
        i++;
      }
    } else {
      final n = int.tryParse(Platform.environment['PV_PUNKTE'] ?? '') ?? 3964;
      for (var i = 0; i <= n; i++) {
        linie.add((x: i * 4.0, y: math.sin(i / 40) * 300, z: 0));
        werte.add((
          hoehe: 300 + 200 * math.sin(i / 300),
          zeit: start.add(Duration(seconds: i * 12)),
        ));
      }
    }
    print('${linie.length} Spurpunkte');

    final flug = Gelaendeflug(linie, werte: werte);
    var fortschritt = 0.0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setzen) => Flugleiste(
            flug: flug,
            stand: flug.bei(fortschritt),
            fortschritt: fortschritt,
            laeuft: true,
            imFlug: Platform.environment['PV_OHNE'] == null,
            beimSchalten: () {},
            beimBeenden: () {},
            beimSpulen: (w) => setzen(() => fortschritt = w),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Wie ein laufender Flug: den Fortschritt bewegen und neu bauen.
    final regler = find.byType(Slider);
    expect(regler, findsOneWidget);
    const laeufe = 60;
    final uhr = Stopwatch()..start();
    for (var i = 0; i < laeufe; i++) {
      final s = tester.state<State>(find.byType(StatefulBuilder));
      // ignore: invalid_use_of_protected_member
      s.setState(() => fortschritt = i / laeufe);
      await tester.pump();
    }
    uhr.stop();
    print('Neubau der Flugleiste: '
        '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(2)} ms '
        'je Bild (Debug-Zeit)');
  });
}

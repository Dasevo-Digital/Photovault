// **Was ein ganzes Flugbild kostet – Aufbau UND Zeichnen.**
//
// `messe_gelaendemaler_test.dart` misst nur den Maler,
// `messe_flugleiste_test.dart` nur die Leiste. Hier steht die Ansicht
// zusammen, so wie sie fliegt: Die Uhr ruft in jedem Bild `setState`,
// und damit wird der ganze Baum neu gebaut – Landschaft, Foto, Leiste,
// Höhenprofil.
//
//   PV_SPUR=/tmp/spur.csv flutter test tool/messe_flugansicht_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

void main() {
  testWidgets('je Bild im Flug', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const n = 220;
    final h = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        h[y * n + x] = 400 + 220 * math.sin(x / 9.0) * math.cos(y / 7.0);
      }
    }
    final gitter = Hoehengitter(
      spalten: n, zeilen: n, hoehen: h,
      nord: 51.90, sued: 51.80, west: 10.55, ost: 10.71,
    );
    final netz = baueNetz(gitter, kante: 96, grundstufe: 15);
    print('${netz.bloecke.length} Bloecke');

    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    final start = DateTime.utc(2026, 9, 3, 8);
    final pfad = Platform.environment['PV_SPUR'];
    if (pfad != null) {
      var i = 0;
      double? b0, l0;
      for (final z in File(pfad).readAsLinesSync()) {
        final t = z.split(',');
        if (t.length < 3) continue;
        final b = double.tryParse(t[0]), l = double.tryParse(t[1]);
        final hh = double.tryParse(t[2]);
        if (b == null || l == null) continue;
        b0 ??= b;
        l0 ??= l;
        linie.add((
          x: (l - l0) * meterJeGradLaenge(b),
          y: (b - b0) * meterJeGradBreite,
          z: (hh ?? 0) * gelaendeUeberhoehung,
        ));
        werte.add((hoehe: hh, zeit: start.add(Duration(seconds: i++ * 12))));
      }
    }
    print('${linie.length} Spurpunkte');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Gelaendeansicht(netz: netz, spur: linie, spurwerte: werte),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();

    const laeufe = 60;
    final uhr = Stopwatch()..start();
    for (var i = 0; i < laeufe; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    uhr.stop();
    print('ganze Ansicht im Flug: '
        '${(uhr.elapsedMicroseconds / laeufe / 1000).toStringAsFixed(2)} ms '
        'je Bild (Debug-Zeit)');
  });
}

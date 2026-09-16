// **Was man von der Videoausgabe sieht.**
//
// Der Anlass ist ein Fehler, den keine Rechnung gefunden hätte und der
// vier Wochen lang niemandem auffiel: Der Fortschritt der Ausgabe wurde
// gerechnet, an die Flugleiste durchgereicht – und dort **nirgends
// gezeichnet**. Sichtbar war allein, dass aus dem Filmzeichen ein
// Stoppzeichen wurde. Wer eine Wanderung von sechzehn Kilometern ausgab,
// wartete also gut eine Minute vor einer Oberfläche, die schwieg, und
// hielt das für „es passiert nichts".
//
// Ein Wert, der berechnet und weitergereicht wird, ist deshalb noch
// nicht angezeigt. Diese Datei prüft das Anzeigen.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';
import 'package:photo_vault/services/platform/nativer_videoschreiber.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

void main() {
  Gelaendenetz netz() {
    const n = 16;
    final hoehen = Float32List(n * n);
    for (var i = 0; i < n * n; i++) {
      hoehen[i] = 400 + 50 * math.sin(i / 7);
    }
    return baueNetz(Hoehengitter(
      spalten: n, zeilen: n, hoehen: hoehen,
      nord: 50.63, sued: 50.60, west: 9.85, ost: 9.91,
    ));
  }

  ({List<Raumpunkt> linie, List<Flugwert> werte}) spur() {
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    final start = DateTime.utc(2026, 9, 3, 10);
    for (var i = 0; i <= 100; i++) {
      linie.add((x: -1000 + i * 20.0, y: i * 4.0, z: i * 3.0));
      werte.add((hoehe: 400 + i * 1.0, zeit: start.add(Duration(seconds: i * 12))));
    }
    return (linie: linie, werte: werte);
  }

  Widget leiste({double? fortschritt, Duration? rest}) {
    final s = spur();
    final flug = Gelaendeflug(s.linie, werte: s.werte);
    return MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Flugleiste(
          flug: flug,
          stand: null,
          fortschritt: 0,
          laeuft: false,
          imFlug: false,
          beimSchalten: () {},
          beimBeenden: () {},
          beimSpulen: (_) {},
          beimAusgeben: () {},
          gibtAus: fortschritt != null,
          ausgabeFortschritt: fortschritt,
          ausgabeRest: rest,
        ),
      ),
    );
  }

  testWidgets('ohne Ausgabe steht kein Balken da', (tester) async {
    await tester.pumpWidget(leiste());
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('waehrend der Ausgabe steht ein Balken da, und er stimmt',
      (tester) async {
    await tester.pumpWidget(leiste(fortschritt: 0.42));
    final balken = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(balken.value, closeTo(0.42, 1e-9),
        reason: 'ein Balken, der nicht mitgeht, ist eine Zierleiste');
    expect(find.textContaining('42'), findsOneWidget,
        reason: 'die Zahl gehoert daneben - ein Balken allein sagt nicht, '
            'ob es noch eine Minute oder eine Stunde dauert');
  });

  testWidgets('ist eine Restzeit da, steht sie dabei', (tester) async {
    await tester.pumpWidget(
        leiste(fortschritt: 0.5, rest: const Duration(seconds: 90)));
    // 90 Sekunden werden auf zwei Minuten gerundet - genauer, als eine
    // Schaetzung es hergibt.
    expect(find.textContaining('2'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('ohne Restzeit steht nur der Anteil, keine geratene Zahl',
      (tester) async {
    await tester.pumpWidget(leiste(fortschritt: 0.05));
    expect(find.textContaining('5'), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('der Ausgabeknopf fragt mit der Flugdauer', (tester) async {
    // Die Vorgabe im Einstellungsfenster ist die Laenge, die man gerade
    // gesehen hat. Ohne sie muesste jeder erst raten, wie lang sein Flug
    // ueberhaupt ist.
    // **Die Werkzeugsuche stellen.** Sonst liest sie den PATH dieser
    // Maschine, und das ist echte Ein-/Ausgabe: In einem Widget-Test
    // kehrt sie nie zurueck, und der Lauf haengt wortlos bis zum
    // Zeitlimit.
    DesktopImageTools.stelleWerkzeuge(const {'ffmpeg': '/bin/echo'});
    addTearDown(DesktopImageTools.vergissWerkzeuge);
    // Und den nativen Kanal stellen: Ohne Antwort von drueben wartet die
    // Abfrage auf ein Ereignis, das die gestellte Uhr eines Widget-Tests
    // nie ausloest.
    NativerVideoschreiber.vergiss();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            NativerVideoschreiber.kanal, (_) async => true);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativerVideoschreiber.kanal, null);
      NativerVideoschreiber.vergiss();
    });
    Duration? gefragt;
    final s = spur();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Gelaendeansicht(
          netz: netz(),
          spur: s.linie,
          spurwerte: s.werte,
          beimVideoZiel: (vorgabe) async {
            gefragt = vorgabe;
            return null;
          },
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.movie_outlined));
    await tester.pumpAndSettle();
    expect(gefragt, isNotNull, reason: 'der Knopf fragt gar nicht');
    expect(gefragt!.inSeconds, greaterThan(1));
    // Die Flugdauer eines 2-km-Weges bei 300 m/s, plus Einflug und
    // Abspann: die Untergrenze von zehn Sekunden, auf 12 gestreckt.
    expect(gefragt!.inSeconds, lessThan(60));
  });
}

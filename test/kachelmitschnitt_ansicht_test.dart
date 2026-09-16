import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/kachelmitschnitt_screen.dart';
import 'package:photo_vault/services/kachelmitschnitt.dart';
import 'package:photo_vault/theme/app_theme.dart';

Kachelabruf abruf(String kachel, {int? status = 200, String? fehler}) =>
    Kachelabruf(
      zeit: DateTime(2026, 8, 28, 8, 19),
      adresse: 'https://tile.openstreetmap.org/$kachel.png',
      dauer: const Duration(milliseconds: 90),
      status: status,
      fehler: fehler,
      bytes: 12000,
    );

Future<void> zeige(WidgetTester tester, Kachelmitschnitt m) async {
  // Ein hohes Fenster: Die Ansicht scrollt, und was ausserhalb liegt,
  // baut eine ListView gar nicht erst – ein `findsNothing` wäre dann
  // keine Aussage über die Ansicht, sondern über die Fenstergrösse.
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppTexte.localizationsDelegates,
    supportedLocales: AppTexte.supportedLocales,
    // Mit dem echten Thema: Die Ansicht färbt auffällige Werte über
    // [AppSemantik], und das ist eine Erweiterung des Themas.
    theme: buildDarkTheme(),
    home: KachelmitschnittScreen(mitschnitt: m),
  ));
  await tester.pump();
}

/// Die Texte in der Sprache, in der die Ansicht gerade gebaut wurde –
/// sonst hinge der Test an der Spracheinstellung der Maschine.
AppTexte texte(WidgetTester tester) =>
    AppTexte.of(tester.element(find.byType(Scaffold)));

/// Baut den Baum ab und lässt die Taktuhr auslaufen – sonst meldet
/// flutter_test einen hängenden Timer.
Future<void> raeumeAb(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('ohne Einträge steht da, dass nichts mitgeschrieben wurde',
      (tester) async {
    await zeige(tester, Kachelmitschnitt());
    final t = texte(tester);
    expect(find.text(t.mitschnittNochNichts), findsOneWidget);
    expect(find.text(t.mitschnittStarten), findsOneWidget);
    await raeumeAb(tester);
  });

  testWidgets('der Knopf schaltet den Mitschnitt an und wieder aus',
      (tester) async {
    final m = Kachelmitschnitt();
    await zeige(tester, m);

    final t = texte(tester);
    await tester.tap(find.text(t.mitschnittStarten));
    await tester.pump();
    expect(m.laeuft, isTrue);
    expect(find.text(t.mitschnittAnhalten), findsOneWidget);

    await tester.tap(find.text(t.mitschnittAnhalten));
    await tester.pump();
    expect(m.laeuft, isFalse);
    await raeumeAb(tester);
  });

  testWidgets('die beiden Verhältniszahlen stehen oben und stimmen',
      (tester) async {
    // Der gemessene Fall in klein: sechs Abrufe auf drei Kacheln, dazu
    // zwölf Verbindungen. Genau diese beiden Zahlen auseinanderzuhalten
    // ist der Zweck des Bildschirms.
    final m = Kachelmitschnitt()..starte();
    for (var i = 0; i < 3; i++) {
      m.notiere(abruf('8/134/$i'));
      m.notiere(abruf('8/134/$i'));
    }
    for (var i = 0; i < 12; i++) {
      m.verbindungGeoeffnet();
    }

    await zeige(tester, m);
    final t = texte(tester);
    expect(find.text(t.mitschnittVerbJeAbruf), findsOneWidget);
    expect(find.text(t.mitschnittAbrufeJeKachel), findsOneWidget);
    expect(find.text('2.0'), findsNWidgets(2)); // 12/6 und 6/3

    m.halteAn();
    await raeumeAb(tester);
  });

  testWidgets('Statuscodes, Fehler und die letzten Abrufe stehen darunter',
      (tester) async {
    final m = Kachelmitschnitt()..starte();
    m.notiere(abruf('8/134/85'));
    m.notiere(abruf('8/134/86', status: 404));
    m.notiere(abruf('8/134/87', status: null, fehler: 'SocketException: weg'));

    await zeige(tester, m);
    final t = texte(tester);
    expect(find.text(t.mitschnittStatusTitel), findsOneWidget);
    expect(find.text('404'), findsOneWidget);
    expect(find.text(t.mitschnittFehlerTitel), findsOneWidget);
    expect(find.text('SocketException: weg'), findsWidgets);
    // Die Liste zeigt die Kachel kurz, nicht die volle Adresse.
    expect(find.text('8/134/85'), findsOneWidget);

    m.halteAn();
    await raeumeAb(tester);
  });

  test('der Bericht trägt die Zahlen, um die es geht', () {
    final m = Kachelmitschnitt()..starte();
    m.notiere(abruf('8/134/85'));
    m.notiere(abruf('8/134/85'));
    m.verbindungGeoeffnet();
    m.verbindungGeoeffnet();
    m.verbindungGeoeffnet();
    m.verbindungGeoeffnet();

    final bericht = berichtAus(m);
    expect(bericht, contains('Abrufe: 2'));
    expect(bericht, contains('Verbindungen: 4'));
    expect(bericht, contains('Verbindungen je Abruf: 2.00'));
    expect(bericht, contains('Abrufe je Kachel: 2.00'));
    expect(bericht, contains('8/134/85'));
  });
}

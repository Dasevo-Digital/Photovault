import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gpx.dart';
import 'package:photo_vault/widgets/hoehenprofil.dart';

/// Das Höhenprofil.
///
/// Ein `CustomPaint` lässt sich nicht daraufhin prüfen, ob es „richtig
/// aussieht". Prüfbar ist, **was es meldet**: welchen Punkt es unter dem
/// Zeiger sieht, und was es der Sprachausgabe sagt – für die es sonst
/// eine leere Fläche wäre.
void main() {
  /// Ein Profil über zehn Kilometer, gleichmässig ansteigend.
  List<Profilpunkt> profil({int anzahl = 11}) => [
        for (var i = 0; i < anzahl; i++)
          (km: i.toDouble(), hoehe: 100.0 + i * 10, index: i),
      ];

  Future<int?> zeigeUndTippe(
    WidgetTester tester,
    List<Profilpunkt> punkte, {
    required double anteil,
  }) async {
    int? gemeldet;
    var gerufen = false;
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: Hoehenprofil(
            punkte: punkte,
            beschreibung: 'Höhenprofil über 10 km',
            beiStelle: (i) {
              gemeldet = i;
              gerufen = true;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Eine echte Mausbewegung und kein Tippen: `onHover` ist der Weg,
    // den ein Zeiger nimmt, und ein Loslassen meldete sofort wieder
    // `null`.
    final kasten = tester.getRect(find.byType(Hoehenprofil));
    final zeiger = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await zeiger.addPointer(location: Offset.zero);
    await zeiger.moveTo(
        Offset(kasten.left + kasten.width * anteil, kasten.center.dy));
    await tester.pump();
    expect(gerufen, isTrue, reason: 'keine Meldung bei anteil=$anteil');
    final antwort = gemeldet;
    // Den Zeiger hier abmelden und nicht im tearDown: Ein zweiter Aufruf
    // in demselben Test meldete sonst einen zweiten an, während der
    // erste noch liegt – und der Mausverfolger bricht darüber ab.
    // Abgemeldet wird nach dem Ablesen, denn das Verlassen der Fläche
    // meldet planmässig `null`.
    await zeiger.removePointer();
    await tester.pump();
    return antwort;
  }

  testWidgets('meldet den Punkt unter dem Zeiger', (tester) async {
    expect(await zeigeUndTippe(tester, profil(), anteil: 0.5), 5);
    expect(await zeigeUndTippe(tester, profil(), anteil: 0.0), 0);
    // Knapp vor dem Rand und nicht auf ihm: Der rechte Rand gehört
    // schon nicht mehr zur Fläche, dort kommt kein Zeigerereignis an.
    expect(await zeigeUndTippe(tester, profil(), anteil: 0.99), 10);
  });

  testWidgets('sucht über die Strecke, nicht über den Index',
      (tester) async {
    // **Der Unterschied, der zählt.** Wer stehen bleibt, erzeugt viele
    // Punkte an derselben Stelle. Hier liegen neun der zehn Punkte auf
    // dem ersten Kilometer, einer bei zehn.
    final rast = [
      for (var i = 0; i < 9; i++)
        (km: i * 0.1, hoehe: 100.0, index: i),
      (km: 10.0, hoehe: 200.0, index: 9),
    ];
    // Über den Index gesucht käme in der Mitte der Punkt Nummer 5
    // heraus – mitten aus der Rast. Über die Strecke gesucht steht die
    // Mitte bei fünf Kilometern, und dort ist der letzte Punkt der Rast
    // der nächstgelegene.
    expect(await zeigeUndTippe(tester, rast, anteil: 0.5), 8);
    // Weiter rechts gewinnt der ferne Punkt.
    expect(await zeigeUndTippe(tester, rast, anteil: 0.6), 9);
  });

  testWidgets('zeigt die Stelle als Text an', (tester) async {
    // Geprüft wird der Text, während der Zeiger liegt – deshalb hier
    // ohne den Helfer, der ihn am Ende abmeldet.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: Hoehenprofil(punkte: profil(), beschreibung: 'Profil'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final kasten = tester.getRect(find.byType(Hoehenprofil));
    final zeiger = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await zeiger.addPointer(location: Offset.zero);
    addTearDown(zeiger.removePointer);
    await zeiger.moveTo(kasten.center);
    await tester.pump();
    expect(find.text('5,0 km · 150 m'), findsOneWidget);
  });

  testWidgets('die Sprachausgabe bekommt eine Beschreibung',
      (tester) async {
    // Ohne sie wäre das Profil für jemanden, der es sich vorlesen lässt,
    // überhaupt nicht vorhanden.
    final griff = tester.ensureSemantics();
    await zeigeUndTippe(tester, profil(), anteil: 0.5);
    expect(
        find.bySemanticsLabel('Höhenprofil über 10 km'), findsOneWidget);
    griff.dispose();
  });

  testWidgets('ohne Punkte wird nichts gezeichnet', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Hoehenprofil(punkte: [], beschreibung: 'leer'),
      ),
    ));
    await tester.pumpAndSettle();
    // Eine leere Fläche statt eines Rahmens um nichts.
    expect(tester.getSize(find.byType(Hoehenprofil)), Size.zero);
  });
}

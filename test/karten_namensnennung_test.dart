import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Die Namensnennung der Kartenanbieter ist eine Lizenzauflage – sie muss
/// vollständig zu sehen sein, auch in der schmalsten Stelle, an der eine
/// Karte vorkommt: der 340 Punkte breiten Info-Ansicht.
///
/// Vorher lief sie dort um über 400 Punkte über und wurde abgeschnitten.
/// Aufgefallen ist das erst, als die Info-Ansicht zum ersten Mal unter
/// Test stand; am Bildschirm sieht man einen abgeschnittenen Kleinsttext
/// in einer Ecke nicht.
void main() {
  /// Die Breite der Info-Ansicht (siehe AssetInfoSheet in
  /// asset_viewer_screen.dart und face_review_screen.dart).
  const panelBreite = 340.0;

  Future<void> zeige(WidgetTester tester, double breite) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: breite,
          child: const MiniLocationMap(
            latitude: null,
            longitude: null,
            height: 200,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Zeigt die Namensnennung eines bestimmten Stils in gegebener Breite.
  ///
  /// Getrennt von [zeige], weil MiniLocationMap immer den Theme-Stil
  /// nimmt – die Auflage gilt aber fuer JEDEN Stil, und der laengste
  /// Text ist der von OpenTopoMap.
  Future<void> zeigeStil(
      WidgetTester tester, Kartenstil stil, double breite) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: Scaffold(
        body: SizedBox(
          width: breite,
          height: 200,
          child: Builder(
            builder: (context) =>
                Stack(children: [buildMapAttribution(context, stil: stil)]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('passt in die Breite der Info-Ansicht', (tester) async {
    await zeige(tester, panelBreite);
    // Ein Überlauf meldet sich als Ausnahme; tester.takeException() wäre
    // dann nicht null. Zusätzlich die Sichtprüfung, dass der Text ganz da
    // ist und nicht bloß in Teilen.
    expect(tester.takeException(), isNull);
    expect(find.text(Kartenstil.dunkel.namensnennung), findsOneWidget);
  });

  testWidgets('passt auch in eine sehr schmale Spalte', (tester) async {
    // Ein Fenster kann schmaler werden als die Info-Ansicht; die Auflage
    // gilt dann trotzdem.
    await zeige(tester, 200);
    expect(tester.takeException(), isNull);
    expect(find.text(Kartenstil.dunkel.namensnennung), findsOneWidget);
  });

  testWidgets('deckt die Karte nicht zu', (tester) async {
    await zeige(tester, panelBreite);
    final breite = tester.getSize(find.text(Kartenstil.dunkel.namensnennung)).width;
    expect(breite, lessThan(panelBreite * 2 / 3),
        reason: 'sonst liegt sie über der halben Karte');
  });

  /// Die eigentliche Auflage gilt fuer JEDEN Stil, nicht nur den dunklen.
  /// OpenTopoMap hat den mit Abstand laengsten Text - genau der Fall, in
  /// dem die Namensnennung abgeschnitten wuerde, und ausgerechnet die
  /// darf nicht unvollstaendig sein. Genau das ist hier schon einmal
  /// passiert (siehe Kopf der Datei).
  for (final stil in Kartenstil.values) {
    testWidgets('${stil.name}: Namensnennung passt in die Info-Ansicht',
        (tester) async {
      await zeigeStil(tester, stil, panelBreite);
      expect(tester.takeException(), isNull);
      expect(find.text(stil.namensnennung), findsOneWidget);
      final breite = tester.getSize(find.text(stil.namensnennung)).width;
      expect(breite, lessThanOrEqualTo(panelBreite * 2 / 3),
          reason: 'sonst liegt sie ueber der halben Karte');
    });
  }

  test('jeder Stil nennt seine Quelle ueberhaupt', () {
    // Ein leerer Text waere ein stiller Lizenzverstoss - er faellt
    // niemandem auf, weil da einfach nichts steht.
    for (final stil in Kartenstil.values) {
      expect(stil.namensnennung.trim(), isNotEmpty, reason: stil.name);
      expect(stil.kachelUrl, startsWith('https://'), reason: stil.name);
    }
  });

  test('jede Quelle nennt ihre letzte echte Stufe ausdruecklich', () {
    // Frueher stand hier, dass nur OpenTopoMap eine Angabe hat und die
    // beiden anderen sich auf die Vorgabe der Bibliothek verlassen. Das
    // war zwei Mal unguenstig: OSM antwortet ab Stufe 20 mit 400, und
    // CARTO traegt umgekehrt eine Stufe WEITER als die Vorgabe. Beides
    // an echten Abrufen nachgemessen, mitten in Berlin.
    //
    // Ohne eigene Angabe war ausserdem keine Anzeigegrenze abzuleiten -
    // und ohne die zoomt die Karte ins Nichts, siehe zoomgrenze_test.
    expect(Kartenstil.topo.hoechsteEchteStufe, 17,
        reason: 'darueber kommt eine einfarbige Kachel');
    expect(Kartenstil.hell.hoechsteEchteStufe, 19,
        reason: 'ab 20 antwortet OSM mit 400');
    expect(Kartenstil.dunkel.hoechsteEchteStufe, 19,
        reason: 'ohne Schluessel liefert OSM die Kacheln');
    setzeCartoSchluessel('probe');
    expect(Kartenstil.dunkel.hoechsteEchteStufe, 20,
        reason: 'CARTO liefert auf 20 noch gezeichnete Kacheln');
    setzeCartoSchluessel(null);
    for (final stil in Kartenstil.values) {
      expect(stil.hoechsteEchteStufe, isNotNull, reason: stil.name);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/timeline_scrubber.dart';

import 'goldbilder.dart';

/// Der Regler ist reine Oberfläche, aber eine mit Fallstricken: Er zeichnet
/// in einem [Stack] mit festen Abständen, und seine Beschriftungen sind in
/// beiden Sprachen unterschiedlich lang. Diese Prüfungen halten fest, dass
/// er in eine schmale Leiste passt, ohne überzulaufen.
Rasterzeile _foto(String id, DateTime wann) => Rasterzeile.aus(AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: id,
      fileCreatedAt: wann,
      importedAt: wann,
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 0,
    ));

/// Vier Jahre à zwölf Monate, absteigend – so viel, dass Jahreszahlen und
/// Monatspunkte dicht beieinander liegen.
({List<int> keys, Map<int, List<Rasterzeile>> groups}) _bibliothek() {
  final keys = <int>[];
  final groups = <int, List<Rasterzeile>>{};
  for (var jahr = 2026; jahr >= 2023; jahr--) {
    for (var monat = 12; monat >= 1; monat--) {
      final key = jahr * 100 + monat;
      keys.add(key);
      groups[key] = [
        for (var i = 0; i < 8; i++) _foto('$key-$i', DateTime(jahr, monat, 5)),
      ];
    }
  }
  return (keys: keys, groups: groups);
}

Future<void> _zeige(WidgetTester tester, Locale locale, double breite) async {
  final b = _bibliothek();
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppTexte.localizationsDelegates,
    supportedLocales: AppTexte.supportedLocales,
    home: Scaffold(
      body: Row(
        children: [
          const Expanded(child: SizedBox()),
          SizedBox(
            width: breite,
            height: 600,
            child: TimelineScrubber(
              orderedKeys: b.keys,
              groups: b.groups,
              controller: ScrollController(),
              gridWidth: 800,
            ),
          ),
        ],
      ),
    ),
  ));
  await tester.pump();
}


/// Eine Bibliothek wie die im Fehlerbericht: Der Schwerpunkt liegt in den
/// letzten Jahren, die alten haben je ein paar Fotos. Genau dadurch drängen
/// sich 2006 bis 2014 auf wenige Pixel.
({List<int> keys, Map<int, List<Rasterzeile>> groups}) _schieflastig() {
  final keys = <int>[];
  final groups = <int, List<Rasterzeile>>{};
  for (var jahr = 2026; jahr >= 2006; jahr--) {
    final proMonat = jahr >= 2015 ? 60 : 1;
    for (var monat = 12; monat >= 1; monat--) {
      final key = jahr * 100 + monat;
      keys.add(key);
      groups[key] = [
        for (var i = 0; i < proMonat; i++) _foto('$key-$i', DateTime(jahr, monat, 5)),
      ];
    }
  }
  return (keys: keys, groups: groups);
}

void _weitereTests() {
  group('Welche Jahre überhaupt geschrieben werden', () {
    test('was Platz hat, bleibt stehen', () {
      final gewaehlt = sichtbareBeschriftungen(
        [10, 60, 110, 160],
        von: 0,
        bis: 600,
      );
      expect(gewaehlt, [0, 1, 2, 3]);
    });

    test('was sich überlappt, fällt weg – der genau gemeldete Fehler', () {
      // Sieben Jahre auf 24 Pixel: Im Screenshot lagen dort 2014 bis 2020
      // als schwarzer Klumpen übereinander.
      final eng = [400.0, 404.0, 408.0, 412.0, 416.0, 420.0, 424.0];
      final gewaehlt = sichtbareBeschriftungen(eng, von: 0, bis: 600);
      expect(gewaehlt.length, lessThan(eng.length));
      // Und was übrig bleibt, hat wirklich Abstand.
      for (var i = 1; i < gewaehlt.length; i++) {
        expect(eng[gewaehlt[i]] - eng[gewaehlt[i - 1]], greaterThanOrEqualTo(15.0));
      }
    });

    test('die erste Zahl bleibt immer', () {
      expect(sichtbareBeschriftungen([0, 2, 4], von: 0, bis: 600).first, 0);
    });

    test('was ausserhalb der Leiste liegt, wird nicht gezeichnet', () {
      expect(sichtbareBeschriftungen([-40, 300, 900], von: 0, bis: 600), [1]);
    });

    test('die aktive Beschriftung hat Vorrang', () {
      // Sie nennt Monat UND Jahr und ist damit die genauere Angabe – eine
      // Jahreszahl darunter wäre nur Matsch. Im Screenshot stand oben
      // „2024Aug." ineinander.
      final ohne = sichtbareBeschriftungen([100, 300], von: 0, bis: 600);
      final mit = sichtbareBeschriftungen([100, 300],
          von: 0, bis: 600, gesperrt: (oben: 92, unten: 114));
      expect(ohne, [0, 1]);
      expect(mit, [1], reason: 'die 100 liegt im gesperrten Band');
    });

    test('ohne Jahre kommt nichts zurück', () {
      expect(sichtbareBeschriftungen([], von: 0, bis: 600), isEmpty);
    });
  });

  testWidgets('keine zwei Jahreszahlen überlappen sich auf dem Schirm',
      (tester) async {
    // Die Gegenprobe zum Bericht, an gerenderten Rechtecken gemessen statt
    // an der Rechnung dahinter.
    final b = _schieflastig();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(
            width: 64,
            height: 700,
            child: TimelineScrubber(
              orderedKeys: b.keys,
              groups: b.groups,
              controller: ScrollController(),
              gridWidth: 800,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();

    final rechtecke = <Rect>[];
    for (var jahr = 2006; jahr <= 2026; jahr++) {
      final treffer = find.text('$jahr');
      if (treffer.evaluate().isEmpty) continue;
      rechtecke.add(tester.getRect(treffer));
    }

    expect(rechtecke.length, greaterThan(3),
        reason: 'ein paar Jahre müssen schon dastehen');
    rechtecke.sort((a, b) => a.top.compareTo(b.top));
    for (var i = 1; i < rechtecke.length; i++) {
      expect(rechtecke[i].top, greaterThanOrEqualTo(rechtecke[i - 1].bottom - 0.5),
          reason: 'überlappende Jahreszahlen: ${rechtecke[i - 1]} und ${rechtecke[i]}');
    }
  });

  testWidgets('auch die aktive Beschriftung überlappt keine Jahreszahl',
      (tester) async {
    final b = _schieflastig();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(
            width: 64,
            height: 700,
            child: TimelineScrubber(
              orderedKeys: b.keys,
              groups: b.groups,
              controller: ScrollController(),
              gridWidth: 800,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Am Anfang steht die Ansicht ganz oben – dort sass im Bericht
    // „2024Aug." ineinander.
    final aktiv = tester.getRect(find.text('Dez. 2026'));
    for (var jahr = 2006; jahr <= 2026; jahr++) {
      final treffer = find.text('$jahr');
      if (treffer.evaluate().isEmpty) continue;
      final r = tester.getRect(treffer);
      final ueberlappt = r.top < aktiv.bottom && r.bottom > aktiv.top;
      expect(ueberlappt, isFalse, reason: '$jahr liegt unter der aktiven Beschriftung');
    }
  });
}

void main() {
  _weitereTests();

  testWidgets('die Jahreszahlen stehen da, die Monate nicht', (tester) async {
    await _zeige(tester, const Locale('de'), 64);
    // Jedes Jahr höchstens einmal beschriftet – nicht 48 Monate.
    //
    // 2026 fehlt bewusst: Die Ansicht steht oben, und dort sagt die aktive
    // Beschriftung bereits „Dez. 2026". Eine Jahreszahl darunter wäre nur
    // Matsch – genau der Fehler aus dem Bericht.
    for (final jahr in ['2025', '2024', '2023']) {
      expect(find.text(jahr), findsOneWidget, reason: '\$jahr fehlt');
    }
    expect(find.text('Dez. 2026'), findsOneWidget);
    expect(find.text('2026'), findsNothing,
        reason: 'die aktive Beschriftung nennt das Jahr schon');
  });

  testWidgets('nichts läuft über die Leiste hinaus', (tester) async {
    // Die eigentliche Gefahr: Die aktive Beschriftung ("Dez. 2026") ist
    // deutlich breiter als eine Jahreszahl. Läuft sie über, meldet Flutter
    // einen Overflow – und der zählt hier als Fehler.
    for (final locale in [const Locale('de'), const Locale('en')]) {
      await _zeige(tester, locale, 64);
      expect(tester.takeException(), isNull,
          reason: 'Überlauf in ${locale.languageCode}');
    }
  });

  testWidgets('bei sehr wenigen Monaten erscheint der Regler gar nicht',
      (tester) async {
    // Ein Schnell-Scroll-Regler über zwei Gruppen wäre nur Unruhe.
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 64,
          height: 600,
          child: TimelineScrubber(
            orderedKeys: const [202601],
            groups: {202601: [_foto('a', DateTime(2026, 1, 5))]},
            controller: ScrollController(),
            gridWidth: 800,
          ),
        ),
      ),
    ));
    expect(find.text('2026'), findsNothing);
  });

  testWidgets('so sieht die Leiste bei schieflastigem Bestand aus',
      (tester) async {
    // Dieselbe Verteilung wie im Bericht. Ein Abbild statt einer
    // Behauptung – an das echte Fenster kommt man hier nicht heran.
    final b = _schieflastig();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xFF202020),
        body: Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(
            width: 64,
            height: 700,
            child: TimelineScrubber(
              orderedKeys: b.keys,
              groups: b.groups,
              controller: ScrollController(),
              gridWidth: 800,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
    await expectLater(
      find.byType(TimelineScrubber),
      matchesGoldenFile('golden/zeitleiste.png'),
    );
  }, skip: nurAufReferenzplattform);
}

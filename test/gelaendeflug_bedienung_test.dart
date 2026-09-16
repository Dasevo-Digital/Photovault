import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/widgets/gelaende.dart';

/// **Die Bedienung des Fluges.**
///
/// Die Rechnung steht in `gelaendeflug_test.dart`; hier geht es um das,
/// was daran zu sehen und zu drücken ist. Ohne Netz und ohne Kacheln –
/// das Gelände wird von Hand gebaut, damit dieser Prüfstand nicht davon
/// abhängt, ob gerade jemand erreichbar ist.
void main() {
  /// Ein sanfter Hügel, damit es überhaupt Höhenunterschiede gibt.
  Gelaendenetz netz() {
    const n = 24;
    final hoehen = Float32List(n * n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        hoehen[y * n + x] =
            400 + 200 * math.sin(x / n * math.pi) * math.sin(y / n * math.pi);
      }
    }
    return baueNetz(Hoehengitter(
      spalten: n,
      zeilen: n,
      hoehen: hoehen,
      nord: 50.63,
      sued: 50.60,
      west: 9.85,
      ost: 9.91,
    ));
  }

  /// Eine Spur quer über den Hügel, 2 km lang, gleichmässig in 20
  /// Minuten – also 6 km/h, wie eine zügige Wanderung.
  ({List<Raumpunkt> linie, List<Flugwert> werte}) spur({bool mitZeit = true}) {
    final start = DateTime.utc(2026, 8, 30, 10);
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    for (var i = 0; i <= 100; i++) {
      linie.add((x: -1000 + i * 20.0, y: i * 4.0, z: i * 3.0));
      werte.add((
        hoehe: 400 + i * 1.0,
        zeit: mitZeit ? start.add(Duration(seconds: i * 12)) : null,
      ));
    }
    return (linie: linie, werte: werte);
  }

  Widget bildschirm({
    bool mitZeit = true,
    bool mitSpur = true,
    List<Widget> fussnoten = const [],
  }) {
    final s = spur(mitZeit: mitZeit);
    return MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: Gelaendeansicht(
          netz: netz(),
          spur: mitSpur ? s.linie : const [],
          spurwerte: mitSpur ? s.werte : const [],
          fussnoten: fussnoten,
        ),
      ),
    );
  }

  AppTexte texte(WidgetTester tester) =>
      AppTexte.of(tester.element(find.byType(Gelaendeansicht)));

  testWidgets('ohne Spur gibt es keine Flugleiste', (tester) async {
    await tester.pumpWidget(bildschirm(mitSpur: false));
    await tester.pump();
    expect(find.byType(Flugleiste), findsNothing,
        reason: 'ein Flug über nichts wäre ein Knopf, der nichts tut');
  });

  testWidgets('mit Spur steht der Startknopf da', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
    // Solange nicht geflogen wird, gibt es auch nichts zu spulen.
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('der Start bringt die Messwerte hervor', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    final t = texte(tester);
    expect(find.text(t.flugHoehe), findsNothing);

    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();

    expect(find.text(t.flugHoehe), findsOneWidget);
    expect(find.text(t.flugTempo), findsOneWidget);
    expect(find.text(t.flugSteigung), findsOneWidget);
    expect(find.text(t.flugUnterwegs), findsOneWidget);

    // Den Ticker anhalten, sonst läuft er über das Testende hinaus.
    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pump();
  });

  testWidgets('das Tempo steht in km/h und stimmt', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // 2040 m in 20 Minuten sind 6,1 km/h. Die Zahl selbst ist die Probe
    // darauf, dass nicht m/s dastehen – das wären 1,7.
    //
    // Herausgelesen statt gesucht: Das Dezimaltrennzeichen hängt an der
    // Sprache des Prüflaufs, und ein Test, der auf ein Komma besteht,
    // fällt in der englischen Fassung.
    final tempotexte = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .where((s) => s.contains('km/h'))
        .toList();
    expect(tempotexte, hasLength(1));
    final zahl = double.parse(RegExp(r'[0-9]+[.,][0-9]+')
        .firstMatch(tempotexte.single)!
        .group(0)!
        .replaceAll(',', '.'));
    expect(zahl, closeTo(6.1, 0.3), reason: 'km/h, nicht m/s');

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pump();
  });

  testWidgets('ohne Zeitstempel sagt die Leiste das, statt zu schweigen',
      (tester) async {
    await tester.pumpWidget(bildschirm(mitZeit: false));
    await tester.pump();
    final t = texte(tester);
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();

    // Ohne Zeit gibt es kein Tempo – aber die Höhe steht trotzdem da,
    // und der Grund für die Lücke ebenfalls.
    expect(find.text(t.flugTempo), findsNothing);
    expect(find.text(t.flugHoehe), findsOneWidget);
    expect(find.text(t.flugOhneZeit), findsNothing,
        reason: 'der Hinweis gilt nur, wenn gar keine Zahl übrig bleibt');

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pump();
  });

  testWidgets('anhalten und weiterfliegen', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    // **Zwei Takte, nicht einer.** Der erste bringt den Ticker in Gang,
    // erst der zweite lässt Zeit vergehen. Mit nur einem steht der Regler
    // auf null, und der Test hielte den Flug für kaputt.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final unterwegs = tester.widget<Slider>(find.byType(Slider)).value;
    expect(unterwegs, greaterThan(0));

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Slider>(find.byType(Slider)).value, unterwegs,
        reason: 'angehalten heisst angehalten');

    // Und der Knopf bietet jetzt das Weiterfliegen an, nicht den Start.
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Slider>(find.byType(Slider)).value,
        greaterThan(unterwegs));

    await tester.tap(find.byIcon(Icons.pause_circle_outline));
    await tester.pump();
  });

  testWidgets('der Regler spult und hält dabei an', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final leiste = tester.widget<Slider>(find.byType(Slider));
    leiste.onChanged!(0.8);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, closeTo(0.8, 1e-9));
    // Spulen hält an – sonst liefe der Flug unter der Hand weiter,
    // während jemand eine Stelle sucht.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Slider>(find.byType(Slider)).value, closeTo(0.8, 1e-9));
  });

  testWidgets('am Ende bietet der Knopf einen zweiten Lauf an',
      (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(1.0);
    await tester.pump();

    expect(find.byIcon(Icons.replay), findsOneWidget,
        reason: 'am Ende stehen bleiben, aber den Weg zurück anbieten');
  });

  testWidgets('„Zur Übersicht" beendet den Flug', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    final t = texte(tester);
    expect(find.text(t.flugHoehe), findsOneWidget);

    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pump();

    expect(find.text(t.flugHoehe), findsNothing);
    expect(find.byIcon(Icons.flight_takeoff), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('der Flug hinterlässt keinen laufenden Ticker', (tester) async {
    // Ein Ticker, der den Baum überlebt, lässt flutter_test mit „A Timer
    // is still pending" fallen – und zwar im nächsten Test, nicht in
    // diesem. Deshalb steht die Prüfung ausdrücklich da.
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.tap(find.byIcon(Icons.flight_takeoff));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  group('Die Fussnoten liegen ueber der Flugleiste und nicht darauf', () {
    // Gemeldet als „Erklaerung unten ueberlappt sich mit dem
    // Flugzeugsymbol": Der Bildschirm legte seine Fussnoten in einem
    // ZWEITEN Stapel mit `bottom:` ueber die Ansicht - und traf damit
    // genau den Knopf, der den Flug startet.
    const marke = Key('fussnote-links');
    List<Widget> zettel() => const [
          KeyedSubtree(key: marke, child: Text('Ziehen dreht')),
          Text('Kartendaten'),
        ];

    testWidgets('die Fussnote endet oberhalb des Startknopfs',
        (tester) async {
      await tester.pumpWidget(bildschirm(fussnoten: zettel()));
      await tester.pump();

      final fuss = tester.getRect(find.byKey(marke));
      final knopf = tester.getRect(find.byIcon(Icons.flight_takeoff));
      expect(fuss.bottom, lessThanOrEqualTo(knopf.top),
          reason: 'die Erklaerung darf den Startknopf nicht beruehren');
      expect(fuss.overlaps(knopf), isFalse);
    });

    testWidgets('auch waehrend des Fluges, wenn die Leiste hoeher wird',
        (tester) async {
      // Im Flug wachsen Messwerte und Hoehenprofil in die Leiste hinein.
      // Eine fest gewaehlte Hoehe waere hier wieder falsch.
      await tester.pumpWidget(bildschirm(fussnoten: zettel()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.flight_takeoff));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fuss = tester.getRect(find.byKey(marke));
      final leiste = tester.getRect(find.byType(Flugleiste));
      expect(fuss.bottom, lessThanOrEqualTo(leiste.top));
      expect(fuss.overlaps(leiste), isFalse);
    });

    testWidgets('ohne Spur stehen sie trotzdem am unteren Rand',
        (tester) async {
      await tester.pumpWidget(
          bildschirm(mitSpur: false, fussnoten: zettel()));
      await tester.pump();
      final fuss = tester.getRect(find.byKey(marke));
      final ganz = tester.getRect(find.byType(Gelaendeansicht));
      expect(fuss.bottom, lessThanOrEqualTo(ganz.bottom));
      expect(ganz.bottom - fuss.bottom, lessThan(40),
          reason: 'ohne Flugleiste gehoeren sie nach unten');
    });
  });
}

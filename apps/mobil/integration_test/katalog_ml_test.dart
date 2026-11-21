// ignore_for_file: avoid_print
// Nachprüfung der Handy-Einträge, die in der ersten Runde an fehlenden
// Modellen scheiterten – im iOS-Simulator
// „PV Pruefung“ gegen den Wegwerf-Server „ml“ (ONNX Runtime und Modelle,
// 127.0.0.1:18820) und den Vorschalt-Proxy pruefkatalog/tools/ml_proxy.py
// (18821, Steuerung 18822). Testbilder: pruefkatalog/fixtures-ml (macOS-
// Benutzerbilder, gemeinfreie Bilder aus docs/screenshots).
//
//   flutter test integration_test/katalog_ml_test.dart -d <Simulator> \
//     --dart-define=PV_FIXTURES_ML=<Ordner mit den Testbildern>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;

import 'katalog_hilfen.dart';

/// Die Ports des Servers „ml“ und seines Vorschalt-Proxys (Vorgabe wie in
/// der ersten Runde; für Nachprüfungen per --dart-define andere).
const _mlPort = int.fromEnvironment('PV_ML_PORT', defaultValue: 18820);
const _mlAppPort = int.fromEnvironment('PV_ML_APP_PORT', defaultValue: 18821);
const _mlSteuerPort = int.fromEnvironment(
  'PV_ML_STEUER_PORT',
  defaultValue: 18822,
);
final mlDirekt = Uri.parse('http://$hostAdresse:$_mlPort/');
final mlApp = Uri.parse('http://$hostAdresse:$_mlAppPort/');
const mlFix = String.fromEnvironment('PV_FIXTURES_ML');
const voegel = {
  'animals_eagle.jpg',
  'animals_owl.jpg',
  'animals_parrot.jpg',
  'animals_penguin.jpg',
};

Future<List<String>> mlLog() async {
  final r = await http.get(Uri.parse('http://$hostAdresse:$_mlSteuerPort/log'));
  return [
    for (final e in jsonDecode(r.body) as List)
      '${(e as Map)['methode']} ${e['pfad']} ${e['status']}',
  ];
}

Future<void> mlLogLeeren() async {
  await http.post(Uri.parse('http://$hostAdresse:18822/log/leeren'));
}

Future<Map<String, String>> ladeHoch(
  Serververbindung v,
  List<String> pfade,
) async => {for (final f in pfade) p.basename(f): await hochladenPfad(v, f)};

Future<void> befehl(
  Serververbindung v,
  String art,
  Map<String, Object?> werte,
) => v.schicke('api/v1/befehle', {'art': art, 'werte': werte});

/// Stösst die Auswertung an und wartet, bis sie 2,5 s lang ruht.
Future<void> auswerten(Serververbindung v) async {
  await v.schicke('api/v1/auswertung', const <String, Object?>{});
  DateTime? ruhig;
  final ende = DateTime.now().add(const Duration(minutes: 10));
  while (DateTime.now().isBefore(ende)) {
    final a = await v.hole('api/v1/auswertung');
    if (a['laeuft'] == true) {
      ruhig = null;
    } else {
      ruhig ??= DateTime.now();
      if (DateTime.now().difference(ruhig) >
          const Duration(milliseconds: 2500)) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw StateError('Auswertung nicht fertig');
}

Finder suchfeld() => find.descendant(
  of: find.byType(Scaffold).first,
  matching: find.byType(TextField),
);

/// Die Spalte eines Fotos in einer Duplikatgruppe.
Finder duplSpalte(String name) => find
    .ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 150),
    )
    .first;

Finder karteMit(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

/// Rollt zur Überschrift [titel], sobald die Seite sie baut (die
/// Aufnahmedaten zeigen den Abschnitt erst nach ihrer eigenen Prüfung).
Future<void> zumAbschnitt(WidgetTester tester, String titel) async {
  final ende = DateTime.now().add(const Duration(seconds: 60));
  Object? zuletzt;
  while (DateTime.now().isBefore(ende)) {
    try {
      await rolleZu(tester, find.text(titel));
      return;
    } catch (e) {
      zuletzt = e;
      await ruhe(tester, 1000);
    }
  }
  throw TestFailure('Abschnitt $titel erschien nicht: $zuletzt');
}

String? zeileMit(WidgetTester tester, String anfang) {
  for (final t in sichtbareTexte(tester)) {
    if (t.startsWith(anfang)) return t;
  }
  return null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vorbereitung', (tester) async {
    await einrichten();
    await ersteinrichtung(mlDirekt);
  });

  // ------------------------------------------------------------------

  pruefung('MOB-055 Grosses JPEG: Ansichtsbild, beim Zoomen das Original', (
    tester,
  ) async {
    final konto = await kontoAnlegen(mlDirekt, 'KML055');
    final v = await api(mlDirekt, konto);
    final ids = await ladeHoch(v, [
      '$mlFix/gross/blatt_gross.jpg',
      '$mlFix/inhalt/nature_leaf.jpg',
    ]);
    final gross = ids['blatt_gross.jpg']!;
    final a = await aufnahme(v, gross);
    print(
      'MOB-055 Server: ${a['widthPx']}×${a['heightPx']}, '
      'Vorschau ${a['previewRelativePath']}, Original ${a['relativePath']}',
    );
    expect('${a['previewRelativePath']}', contains('-ansicht'));
    await starteApp(tester, server: mlApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await ruhe(tester, 2000);
    final i = rasterIds(tester).indexOf(gross);
    await mlLogLeeren();
    await oeffneKachel(tester, i);
    await ruhe(tester, 4000);
    final vorher = await mlLog();
    await mlLogLeeren();
    final m = tester.getCenter(find.byType(PageView));
    // Doppeltipp mit echter Pause (im Simulator vergeht bei pump() keine
    // Zeit, die Geste braucht aber mindestens 40 ms zwischen den Tipps).
    await tester.tapAt(m);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await tester.tapAt(m);
    await ruhe(tester, 6000);
    var nachher = await mlLog();
    var wie = 'Doppeltipp';
    if (!nachher.any((x) => x.contains('${a['relativePath']}'))) {
      // Sonst mit zwei Fingern aufziehen.
      final a1 = await tester.startGesture(
        m - const Offset(30, 0),
        pointer: 71,
      );
      final a2 = await tester.startGesture(
        m + const Offset(30, 0),
        pointer: 72,
      );
      for (var i = 0; i < 12; i++) {
        await a1.moveBy(const Offset(-12, 0));
        await a2.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await a1.up();
      await a2.up();
      await ruhe(tester, 6000);
      nachher = await mlLog();
      wie = 'Aufziehen mit zwei Fingern';
    }
    print('MOB-055 gezoomt mit: $wie');
    print('MOB-055 beim Öffnen: $vorher');
    print('MOB-055 beim Zoomen: $nachher');
    final dateien = [
      for (final x in vorher)
        if (x.contains('/api/v1/dateien/')) x,
    ];
    expect(
      dateien.any((x) => x.contains('-ansicht.jpg')),
      isTrue,
      reason: 'beim Öffnen das Ansichtsbild',
    );
    final originalPfad = '/api/v1/dateien/${a['relativePath']}';
    expect(
      dateien.any((x) => x.contains(originalPfad)),
      isFalse,
      reason: 'beim Öffnen nicht das Original des grossen Fotos',
    );
    expect(
      nachher.where((x) => x.contains(originalPfad)).length,
      1,
      reason: 'beim Zoomen genau einmal das Original',
    );
  });

  pruefung('MOB-110 Bildinhalt mit Modell: passende Fotos vorn', (
    tester,
  ) async {
    final konto = await kontoAnlegen(mlDirekt, 'KML110');
    final v = await api(mlDirekt, konto);
    await ladeHoch(v, [
      for (final n in [
        'animals_eagle.jpg',
        'animals_owl.jpg',
        'animals_parrot.jpg',
        'animals_penguin.jpg',
        'animals_zebra.jpg',
        'flowers_sunflower.jpg',
        'flowers_poppy.jpg',
        'flowers_dahlia.jpg',
        'nature_leaf.jpg',
        'nature_earth.jpg',
        'sports_soccer.jpg',
        'sports_tennis.jpg',
      ])
        '$mlFix/inhalt/$n',
    ]);
    await auswerten(v);
    await befehl(v, 'sucheUebersetzenSetzen', {'an': true});
    await starteApp(tester, server: mlApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bereich(tester, de.navSuche);
    final hinweis = tester.widget<TextField>(suchfeld().first);
    expect(hinweis.decoration?.hintText, de.sucheHinweisInhalt);
    Future<(List<String>, bool, List<String>)> suche(String text) async {
      await schreibe(tester, suchfeld().first, text);
      final f = tester.widget<TextField>(suchfeld().first);
      f.onSubmitted?.call(text);
      var balken = false;
      for (var i = 0; i < 80 && !balken; i++) {
        await tester.pump(const Duration(milliseconds: 15));
        balken = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      }
      await warteWeg(
        tester,
        find.byType(LinearProgressIndicator),
        max: const Duration(seconds: 60),
      );
      await ruhe(tester, 1200);
      return (
        rasterNamen(tester),
        balken,
        sichtbareTexte(tester).where((t) => t.length > 25).toList(),
      );
    }

    final (vogel, balken, texte) = await suche('Vogel');
    final (hund, _, texteHund) = await suche('Hund');
    final (blume, _, _) = await suche('Blume');
    await befehl(v, 'sucheUebersetzenSetzen', {'an': false});
    final (vogelRoh, _, _) = await suche('Vogel');
    print('MOB-110 Platzhalter: ${hinweis.decoration?.hintText}');
    print(
      'MOB-110 Vogel (übersetzt): ${vogel.take(6).toList()} Balken: $balken',
    );
    print('MOB-110 Hund (übersetzt): ${hund.take(4).toList()} $texteHund');
    print('MOB-110 Blume (übersetzt): ${blume.take(5).toList()}');
    print('MOB-110 Vogel (Vorgabe, unübersetzt): ${vogelRoh.take(6).toList()}');
    expect(balken, isTrue, reason: 'Balken während der Suche');
    expect(vogel.take(4).toSet(), voegel, reason: 'Vögel vorn');
    expect(
      blume.take(3).every((n) => n.startsWith('flowers_')),
      isTrue,
      reason: 'Blumen vorn',
    );
    expect(texte, isNot(contains(de.sucheFehler)));
    expect(texte, isNot(contains(de.sucheKeinModell)));
  });

  pruefung('MOB-129 Duplikate mit Modell', (tester) async {
    final konto = await kontoAnlegen(mlDirekt, 'KML129');
    final v = await api(mlDirekt, konto);
    final ids = await ladeHoch(v, [
      for (final n in [
        'sonnenblume.jpg',
        'sonnenblume_q60.jpg',
        'eule.jpg',
        'eule_beschnitten.jpg',
      ])
        '$mlFix/dupl/$n',
      '$mlFix/inhalt/sports_tennis.jpg',
      '$mlFix/inhalt/nature_earth.jpg',
    ]);
    await befehl(v, 'favoritSetzen', {
      'ids': [ids['sonnenblume.jpg'], ids['sonnenblume_q60.jpg']],
      'favorit': true,
    });
    await auswerten(v);
    final app = await starteApp(tester, server: mlApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bibOeffnen(tester, de.bibDuplikate);
    expect(find.text('92 %'), findsOneWidget, reason: 'Vorgabe 92 %');
    await tippe(tester, find.text(de.duplSuchen), ms: 2500);
    await warte(
      tester,
      find.textContaining('Gruppen bei 92 % Ähnlichkeit'),
      max: const Duration(seconds: 60),
    );
    final hinweis1 = zeileMit(tester, '2 Gruppen bei 92 %');
    final nurVonHand = find.text(de.duplNurVonHand(2)).evaluate().length;
    print('MOB-129 erst: $hinweis1; nur von Hand: $nurVonHand');
    // In der Favoriten-Gruppe (Sonnenblume) „Behalten“ beim nicht
    // umrandeten Foto.
    await tippe(
      tester,
      find.descendant(
        of: duplSpalte('sonnenblume_q60.jpg'),
        matching: find.text(de.duplBehalten),
      ),
    );
    await warte(tester, find.text(de.duplBehaltenEine('sonnenblume_q60.jpg')));
    final frage = de.duplBehaltenEine('sonnenblume_q60.jpg');
    await tippe(tester, find.widgetWithText(FilledButton, 'OK'), ms: 2000);
    // Bei der Eulen-Gruppe „Keine Duplikate“, dann erneut suchen.
    await tippe(
      tester,
      find.descendant(
        of: karteMit('eule.jpg'),
        matching: find.text(de.duplKeineDuplikate),
      ),
      ms: 1500,
    );
    await tippe(tester, find.text(de.duplSuchen), ms: 2500);
    await warte(
      tester,
      find.textContaining(de.duplAusnahmen(1)),
      max: const Duration(seconds: 60),
    );
    final hinweis2 = zeileMit(tester, 'Keine Duplikate bei');
    final sb = await aufnahme(v, ids['sonnenblume.jpg']!);
    print(
      'MOB-129 danach: $hinweis2; sonnenblume.jpg im Papierkorb: ${sb['isTrashed']}',
    );
    // Neue Gruppen: Mohn (zwei Favoriten) und Kaktus.
    final ids2 = await ladeHoch(v, [
      for (final n in [
        'mohn.jpg',
        'mohn_q85.jpg',
        'kaktus.jpg',
        'kaktus_q85.jpg',
      ])
        '$mlFix/dupl/$n',
    ]);
    await befehl(v, 'favoritSetzen', {
      'ids': [ids2['mohn.jpg'], ids2['mohn_q85.jpg']],
      'favorit': true,
    });
    await auswerten(v);
    await app.sitzung.gleicheAb();
    await ruhe(tester, 2000);
    await tippe(tester, find.text(de.duplSuchen), ms: 2500);
    await warte(
      tester,
      find.text(de.duplAlle(1)),
      max: const Duration(seconds: 60),
    );
    final hinweis3 = zeileMit(tester, '2 Gruppen bei 92 %');
    final vonHand3 = find.text(de.duplNurVonHand(2)).evaluate().length;
    await tippe(tester, find.text(de.duplAlle(1)));
    await warte(tester, find.text(de.duplAlleFrage(1, 1)));
    await tippe(tester, find.widgetWithText(FilledButton, 'OK'), ms: 3000);
    await warte(
      tester,
      find.textContaining('1 Gruppen bei 92 %'),
      max: const Duration(seconds: 60),
    );
    final mohnBleibt =
        find.text('mohn.jpg').evaluate().isNotEmpty &&
        find.text('mohn_q85.jpg').evaluate().isNotEmpty;
    final kaktus = {
      for (final n in ['kaktus.jpg', 'kaktus_q85.jpg'])
        n: (await aufnahme(v, ids2[n]!))['isTrashed'],
    };
    print(
      'MOB-129 Sammel: $hinweis3; nur von Hand: $vonHand3; Mohn bleibt: '
      '$mohnBleibt; Kaktus im Papierkorb: $kaktus',
    );
    // Konto ohne Einbettungen.
    final leer = await kontoAnlegen(mlDirekt, 'KML129L');
    await starteApp(tester, server: mlApp, konto: leer);
    await bibOeffnen(tester, de.bibDuplikate);
    await tippe(tester, find.text(de.duplSuchen), ms: 2500);
    await warte(
      tester,
      find.text(de.duplKeineEinbettungen),
      max: const Duration(seconds: 40),
    );
    expect(hinweis1, isNotNull);
    expect(nurVonHand, 1, reason: 'Favoriten-Gruppe nur von Hand');
    expect(frage, isNotEmpty);
    expect(sb['isTrashed'], true, reason: 'das andere Foto im Papierkorb');
    expect(
      hinweis2,
      'Keine Duplikate bei 92 % Ähnlichkeit. 1 Paare sind ausgenommen.',
    );
    expect(vonHand3, 1);
    expect(mohnBleibt, isTrue);
    expect(kaktus.values.where((x) => x == true).length, 1);
  });

  pruefung('MOB-131 Alte Fotos zeitlich einordnen mit Modell', (tester) async {
    final konto = await kontoAnlegen(mlDirekt, 'KML131');
    final v = await api(mlDirekt, konto);
    final ids = await ladeHoch(v, [
      for (final n in [
        'alt_kirche.jpg',
        'alt_berge.jpg',
        'alt_fluss.jpg',
        'alt_quellen.jpg',
        'alt_mutter.jpg',
      ])
        '$mlFix/alt/$n',
      '$mlFix/ohne_datum/tennis_ohne_datum.jpg',
      '$mlFix/ohne_datum/lotus_ohne_datum.jpg',
    ]);
    await auswerten(v);
    final funde = [
      for (final f in (await v.hole('api/v1/datierung'))['funde']! as List)
        (f as Map).cast<String, Object?>(),
    ];
    await starteApp(tester, server: mlApp, konto: konto);
    await warteAufKacheln(tester, 5);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await zumAbschnitt(tester, de.datierungTitel);
    await warte(
      tester,
      find.textContaining('um 19'),
      max: const Duration(seconds: 60),
    );
    await ruhe(tester, 800);
    List<(String, String, String)> zeilen() => [
      for (final t in tester.widgetList<ListTile>(find.byType(ListTile)))
        if (t.title is Text && ((t.title as Text).data ?? '').startsWith('um '))
          (
            (t.title as Text).data!,
            (t.subtitle as Text?)?.data ?? '',
            t.trailing == null
                ? '–'
                : t.trailing is TextButton
                ? (((t.trailing as TextButton).child as Text).data ?? '')
                : ((t.trailing as Text).data ?? ''),
          ),
    ];
    final vorher = zeilen();
    print('MOB-131 Zeilen: $vorher');
    final belastbar = [
      for (final f in funde)
        if (f['belastbar'] == true) f,
    ];
    final alle = find.text(de.datierungAlle(belastbar.length));
    final hatAlle = alle.evaluate().isNotEmpty;
    // Eine Schätzung einzeln übernehmen, den Rest über den Knopf oben.
    await tippe(
      tester,
      find.widgetWithText(TextButton, de.datierungUebernehmen).first,
      ms: 2500,
    );
    final nachEinem = zeilen();
    if (belastbar.length > 1) {
      await rolleZu(tester, find.text(de.datierungAlle(belastbar.length - 1)));
      await tippe(
        tester,
        find.text(de.datierungAlle(belastbar.length - 1)),
        ms: 3000,
      );
    }
    final nachAllen = zeilen();
    print('MOB-131 nach einem: $nachEinem');
    print('MOB-131 nach allen: $nachAllen');
    final daten = <String, String>{};
    for (final f in belastbar) {
      final id = ((f['aufnahme']! as Map)['id']) as String;
      final j = await v.hole('api/v1/aufnahmen/$id/angaben');
      daten['${j['name']}'] =
          '${j['aufgenommen']} geschätzt=${j['datumGeschaetzt']} (um ${f['jahr']})';
      expect(
        '${j['aufgenommen']}'.startsWith('${f['jahr']}-07-01T12:00'),
        isTrue,
        reason: '${j['name']}: ${j['aufgenommen']}',
      );
      expect(j['datumGeschaetzt'], true);
    }
    print('MOB-131 Daten danach: $daten');
    // Konto mit Fotos ohne Datum, die nicht alt aussehen.
    final modern = await kontoAnlegen(mlDirekt, 'KML131M');
    final vm = await api(mlDirekt, modern);
    await ladeHoch(vm, [
      '$mlFix/ohne_datum/tennis_ohne_datum.jpg',
      '$mlFix/ohne_datum/lotus_ohne_datum.jpg',
    ]);
    await auswerten(vm);
    await starteApp(tester, server: mlApp, konto: modern);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await zumAbschnitt(tester, de.datierungTitel);
    await warte(
      tester,
      find.text(de.datierungKeine),
      max: const Duration(seconds: 40),
    );
    expect(vorher.length, funde.length);
    expect(ids.length, 7);
    expect(hatAlle, isTrue, reason: 'Knopf „N Schätzungen übernehmen“');
    for (final z in vorher) {
      final sicher = RegExp(r'^\d{4} bis \d{4}$').hasMatch(z.$2);
      expect(
        sicher ? z.$3 == de.datierungUebernehmen : z.$3 == '–',
        isTrue,
        reason: 'Zeile $z',
      );
      if (!sicher) expect(z.$2.startsWith('zu unsicher ('), isTrue);
    }
    expect(
      nachAllen.where((z) => z.$3 == de.datierungIstUebernommen).length,
      belastbar.length,
    );
  });

  pruefung('MOB-058 Live Photo abspielen', (tester) async {
    final konto = await kontoAnlegen(mlDirekt, 'KML058');
    final v = await api(mlDirekt, konto);
    final foto = await hochladen(
      v,
      await File('$mlFix/inhalt/animals_parrot.jpg').readAsBytes(),
      'IMG_0058.JPG',
    );
    final film = await hochladen(
      v,
      await File('$fixturesOrdner/video_hoch_3s.mov').readAsBytes(),
      'IMG_0058.MOV',
    );
    final gewoehnlich = await hochladenPfad(v, '$mlFix/inhalt/nature_leaf.jpg');
    final a = await aufnahme(v, foto);
    print(
      'MOB-058 Paar: Foto verknüpft mit ${a['linkedAssetId']} (Video $film)',
    );
    expect(a['linkedAssetId'], film);
    await starteApp(tester, server: mlApp, konto: konto);
    await warteAufKacheln(tester, 2);
    final ids = rasterIds(tester);
    // Gewöhnliches Foto: kein „LIVE“.
    await oeffneKachel(tester, ids.indexOf(gewoehnlich));
    await ruhe(tester, 1500);
    final ohne = find.text('LIVE').evaluate().length;
    await schliesse(tester);
    await oeffneKachel(tester, ids.indexOf(foto));
    await ruhe(tester, 1500);
    final mit = find.text('LIVE').evaluate().length;
    final spieler = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'VideoPlayer',
    );
    Color? marke() {
      final c = tester.widget<Container>(
        find
            .ancestor(of: find.text('LIVE'), matching: find.byType(Container))
            .first,
      );
      return (c.decoration as BoxDecoration?)?.color;
    }

    final farbeAus = marke();
    // Halten spielt, Loslassen hält an.
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    var gehalten = false;
    for (var i = 0; i < 60 && !gehalten; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      gehalten = spieler.evaluate().isNotEmpty;
    }
    final spieltBeimHalten =
        gehalten &&
        ((tester.widget(spieler) as dynamic).controller.value.isPlaying ==
            true);
    await g.up();
    await ruhe(tester, 800);
    final nachLoslassen = spieler.evaluate().isEmpty;
    // Tipp auf die Marke startet, erneut tippen stoppt.
    await tester.tap(find.text('LIVE'));
    var getippt = false;
    for (var i = 0; i < 60 && !getippt; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      getippt = spieler.evaluate().isNotEmpty;
    }
    final farbeAn = marke();
    await tester.tap(find.text('LIVE'));
    await ruhe(tester, 800);
    final gestoppt = spieler.evaluate().isEmpty;
    final farbeDanach = marke();
    print(
      'MOB-058 LIVE gewöhnlich: $ohne, Live Photo: $mit; Halten spielt: '
      '$spieltBeimHalten, Loslassen hält an: $nachLoslassen; Tipp startet: '
      '$getippt (Marke $farbeAn), erneut stoppt: $gestoppt (Marke $farbeDanach, '
      'vorher $farbeAus)',
    );
    expect(ohne, 0);
    expect(mit, 1);
    expect(spieltBeimHalten, isTrue);
    expect(nachLoslassen, isTrue);
    expect(getippt, isTrue);
    expect(farbeAn, Colors.white);
    expect(gestoppt, isTrue);
    expect(farbeDanach, isNot(Colors.white));
  });

  // Behoben in #418: Nach dem Anstossen sieht die Zeile nach, solange die
  // Auswertung läuft; nach „Jetzt sichern“ fragt die Seite den Stand der
  // Server-Sicherung nach, bis der Lauf vorbei ist.
  pruefung('MOB-155 Verwalter: Auswertung läuft, Server jetzt sichern', (
    tester,
  ) async {
    final vw = await verwalter(mlDirekt);
    var s = await vw.hole('api/v1/sicherung');
    if (s['stufe'] == 'nichtEingerichtet') {
      await vw.schicke('api/v1/sicherung/einrichten', {
        'passphrase': 'Pruef-Sicherungssatz-fuer-ML-77',
      });
    }
    for (var i = 0; i < 120; i++) {
      s = await vw.hole('api/v1/sicherung');
      if (s['laeuft'] != true && s['letzterErfolg'] != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    print('MOB-155 Sicherung vorher: ${s['stufe']} ${s['letzterErfolg']}');
    final ende0 = s['ende'];
    // Unausgewertete Fotos beim Verwalter.
    final kennung = eindeutig('ml155');
    for (var i = 0; i < 24; i++) {
      await hochladen(
        vw,
        jpeg(datum: DateTime(2023, 5, 1, 8).add(Duration(minutes: i))),
        '${kennung}_$i.jpg',
      );
    }
    await starteApp(tester, server: mlApp, konto: 'Verwalter');
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontenVerwalten));
    await warte(tester, find.text(de.verwAnstossen));
    final vorher = zeileMit(tester, 'Auswertung');
    final sicherungZeile = zeileMit(tester, 'Sicherung des Servers');
    await tippe(tester, find.text(de.verwAnstossen), ms: 400);
    final nachher = zeileMit(tester, 'Auswertung');
    final amServer = await vw.hole('api/v1/auswertung');
    await ruhe(tester, 4000);
    final spaeter = zeileMit(tester, 'Auswertung');
    final amServer2 = await vw.hole('api/v1/auswertung');
    // Zweiter Versuch (Gegenprobe): erneut anstossen, während er läuft.
    await tippe(tester, find.text(de.verwAnstossen), ms: 400);
    final nochmal = zeileMit(tester, 'Auswertung');
    print(
      'MOB-155 vorher: $vorher; nach Anstossen: $nachher (Server: '
      '${amServer['laeuft']} ${amServer['stand']}); 4 s später: $spaeter '
      '(Server: ${amServer2['laeuft']} ${amServer2['stand']}); erneut '
      'angestossen: $nochmal; Sicherungszeile: $sicherungZeile',
    );
    // „Jetzt sichern“.
    await rolleZu(tester, find.text(de.verwJetztSichern));
    await tippe(tester, find.text(de.verwJetztSichern), ms: 1500);
    var s2 = await vw.hole('api/v1/sicherung');
    for (var i = 0; i < 240; i++) {
      s2 = await vw.hole('api/v1/sicherung');
      if (s2['laeuft'] != true && s2['ende'] != ende0) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final meldungen = sichtbareTexte(
      tester,
    ).where((t) => t.length > 20).toList();
    // Die Zeile zur Sicherung des Servers steht weiter oben.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await ruhe(tester, 800);
    final sicherungOben = zeileMit(tester, 'Sicherung des Servers');
    print('MOB-155 Sicherungszeile oben: $sicherungOben');
    print(
      'MOB-155 Jetzt sichern: Server ${s2['stufe']} ende $ende0 → '
      '${s2['ende']} letzterErfolg ${s2['letzterErfolg']}; sichtbar: $meldungen',
    );
    expect(
      nachher != null && nachher.startsWith('Auswertung läuft'),
      isTrue,
      reason: 'nach dem Anstossen: $nachher (Server ${amServer['stand']})',
    );
    if (amServer2['laeuft'] == true && amServer2['stand'] != null) {
      expect(
        spaeter,
        startsWith('Auswertung läuft: '),
        reason: 'die Zeile sieht nach, während der Server rechnet',
      );
    }
    expect(s2['ende'], isNot(ende0), reason: 'Sicherung lief');
    // Der neue Zeitpunkt der Server-Sicherung steht oben.
    final neu = DateTime.tryParse('${s2['letzterErfolg']}')?.toLocal();
    if (neu != null) {
      await warte(
        tester,
        find.text(
          de.serverSicherungStand(DateFormat.yMd('de').add_Hm().format(neu)),
        ),
        max: const Duration(seconds: 15),
      );
    }
  });
}

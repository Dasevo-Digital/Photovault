// ignore_for_file: avoid_print
part of 'katalog_mob_r2_test.dart';

// ======================================================================
// Karte

Finder get _punkte =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Punkt');

List<int> _gruppen(WidgetTester tester) => [
  for (final e in _punkte.evaluate())
    ((e.widget as dynamic).gruppe as List).length,
];

void karteTests() {
  pruefung('MOB-121 MOB-122 Karte: Gruppen, Zoom, dunkel, Kacheln, offline', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K121');
    final v = await api(hauptDirekt, konto);
    final nah1 = await hochladen(
      v,
      jpeg(breitengrad: 51.900, laengengrad: 10.400),
      'nah1.jpg',
    );
    await hochladen(
      v,
      jpeg(breitengrad: 51.930, laengengrad: 10.430),
      'nah2.jpg',
    );
    final fern = await hochladen(
      v,
      jpeg(breitengrad: 40.0, laengengrad: -3.7),
      'fern.jpg',
    );
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    expect(app.sitzung.kartenUeberServer, isTrue);
    await proxyLogLeeren();
    await bibOeffnen(tester, de.navKarte);
    await ruhe(tester, 4000);
    print('MOB-121 Zoom 4: ${_gruppen(tester)}');
    expect(_gruppen(tester)..sort(), [1, 2], reason: 'nahe Fotos ein Punkt');
    final karte = MapController.of(
      tester.element(find.byType(MarkerLayer).first),
    );
    karte.move(const LatLng(51.915, 10.415), 12);
    await ruhe(tester, 2500);
    print('MOB-121 Zoom 12: ${_gruppen(tester)}');
    expect(
      _gruppen(tester).where((n) => n == 2),
      isEmpty,
      reason: 'beim Zoomen geteilt',
    );
    karte.move(const LatLng(47, 3), 4);
    await ruhe(tester, 2500);
    expect(_gruppen(tester)..sort(), [1, 2]);
    // Mehrere: Seite mit „2 Aufnahmen“; eines: Betrachter.
    final zwei = _punkte.evaluate().firstWhere(
      (e) => ((e.widget as dynamic).gruppe as List).length == 2,
    );
    await tester.tapAt(tester.getCenter(find.byWidget(zwei.widget)));
    await ruhe(tester, 1500);
    await warte(tester, find.widgetWithText(AppBar, de.karteFotos(2)));
    await schliesse(tester);
    final eins = _punkte.evaluate().firstWhere(
      (e) => ((e.widget as dynamic).gruppe as List).length == 1,
    );
    await tester.tapAt(tester.getCenter(find.byWidget(eins.widget)));
    await ruhe(tester, 1500);
    await warte(tester, tooltip(de.betrachterAngaben));
    await schliesse(tester);
    // MOB-122: Kacheln über den eigenen Server.
    final log = await proxyLog();
    final ueberServer = log
        .where((e) => '${e['pfad']}'.startsWith('/api/v1/karte/'))
        .length;
    print('MOB-122 Kachelanfragen über den eigenen Server: $ueberServer');
    // Dunkel: Kacheln mit Farbfilter, Wasserfarbe bleibt blau.
    expect(
      find.ancestor(
        of: find.byType(TileLayer),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
    await bildschirmfoto('mob121_hell.png');
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await ruhe(tester, 2500);
    final filter = find.ancestor(
      of: find.byType(TileLayer),
      matching: find.byType(ColorFiltered),
    );
    expect(filter, findsOneWidget, reason: 'dunkle Kacheln');
    await bildschirmfoto('mob121_dunkel.png');
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
    await ruhe(tester, 1000);
    // Echte Kacheln über den Server (PV_KARTEN=an): eine neue Gegend.
    await steuer('proxy/haupt/kacheln/durch');
    final vorher =
        Directory('${serverDaten('mob-haupt')}/kartenkacheln').existsSync()
        ? Directory(
            '${serverDaten('mob-haupt')}/kartenkacheln',
          ).listSync().length
        : 0;
    karte.move(const LatLng(47.4215, 10.9853), 13);
    await ruhe(tester, 8000);
    final dir = Directory('${serverDaten('mob-haupt')}/kartenkacheln');
    final nachher = dir.existsSync() ? dir.listSync().length : 0;
    print('MOB-122 Kacheln im Speicher des Servers: $vorher → $nachher');
    expect(
      nachher,
      greaterThan(vorher),
      reason: 'Server holt und hält die Kacheln',
    );
    await steuer('proxy/haupt/kacheln/selbst');
    // Ohne Server: bekannte Ausschnitte aus dem Speicher des Telefons.
    await schliesse(tester);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await proxyAus();
    await proxyLogLeeren();
    await bibOeffnen(tester, de.navKarte);
    MapController.of(
      tester.element(find.byType(MarkerLayer).first),
    ).move(const LatLng(47.4215, 10.9853), 13);
    await ruhe(tester, 5000);
    final bilder = [
      for (final r in tester.widgetList<RawImage>(
        find.descendant(
          of: find.byType(TileLayer),
          matching: find.byType(RawImage),
        ),
      ))
        if (r.image != null) r,
    ];
    print('MOB-122 offline sichtbare Kacheln: ${bilder.length}');
    expect(bilder, isNotEmpty);
    await bildschirmfoto('mob122_offline.png');
    await proxyAn();
    await schliesse(tester);
    // Älterer Server ohne Kachelfunktion: das Telefon holt sie selbst.
    await proxyRegel({
      'muster': r'^/api/v1/zustand',
      'patch': {
        'funktionen': {'karte': null},
      },
    });
    final alt = await neuStarten(tester, app);
    await warteBis(
      tester,
      () => alt.sitzung.serverfassung != null,
      grund: 'Zustand geholt',
    );
    await ruhe(tester, 1500);
    print(
      'MOB-122 älterer Server: kartenUeberServer=${alt.sitzung.kartenUeberServer}',
    );
    expect(alt.sitzung.kartenUeberServer, isFalse);
    expect(fern, isNotEmpty);
    expect(nah1, isNotEmpty);
    // Leeres Konto
    final leer = await kontoAnlegen(hauptDirekt, 'K121L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.navKarte);
    await warte(tester, find.text(de.karteLeer));
  });
}

// ======================================================================
// Bibliothek

List<SpurpunktWerte> _spur({required bool hoehen}) => [
  for (var i = 0; i < 20; i++)
    (
      breite: 47.42 + i * 0.002,
      laenge: 10.98 + i * 0.002,
      hoehe: hoehen ? 1000.0 + i * 20 - (i > 14 ? (i - 14) * 30 : 0) : null,
      zeit: DateTime.utc(2024, 7, 10, 8).add(Duration(minutes: i * 6)),
    ),
];

void bibliothekTests() {
  pruefung('MOB-124 Reisen, Aktivitäten, Spur mit und ohne Höhen', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K124');
    final v = await api(hauptDirekt, konto);
    final fotos = <String>[];
    for (var i = 0; i < 4; i++) {
      fotos.add(
        await hochladen(
          v,
          jpeg(
            datum: DateTime(2024, 7, 10, 10 + i),
            breitengrad: 47.42 + i * 0.01,
            laengengrad: 10.98 + i * 0.01,
          ),
          'tour_$i.jpg',
        ),
      );
    }
    final rid = uuid(), a1 = uuid(), a2 = uuid();
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(
        ReiseAnlegen(
          ReisenCompanion.insert(
            id: rid,
            name: 'Alpenreise',
            von: DateTime(2024, 7, 9),
            bis: DateTime(2024, 7, 12),
            angelegtAm: DateTime.now(),
          ),
          fotos,
        ),
      );
      await r.tue(
        AktivitaetAnlegen(
          AktivitaetenCompanion.insert(
            id: a1,
            name: 'Gipfeltour',
            art: 'wanderung',
            von: DateTime(2024, 7, 10, 8),
            bis: DateTime(2024, 7, 10, 16),
            angelegtAm: DateTime.now(),
            reiseId: Value(rid),
          ),
          fotos,
        ),
      );
      await r.tue(
        AktivitaetAnlegen(
          AktivitaetenCompanion.insert(
            id: a2,
            name: 'Talrunde',
            art: 'wanderung',
            von: DateTime(2024, 7, 11, 8),
            bis: DateTime(2024, 7, 11, 12),
            angelegtAm: DateTime.now(),
            reiseId: Value(rid),
          ),
          const [],
        ),
      );
      await r.tue(
        SpurAnlegen(
          id: uuid(),
          name: 'Gipfeltour.gpx',
          quelle: 'Gipfeltour.gpx',
          aktivitaetId: a1,
          laengeKm: 3.6,
          aufstieg: 280,
          abstieg: 30,
          angelegtAm: DateTime.now(),
          punkte: _spur(hoehen: true),
        ),
      );
      await r.tue(
        SpurAnlegen(
          id: uuid(),
          name: 'Talrunde.gpx',
          quelle: 'Talrunde.gpx',
          aktivitaetId: a2,
          laengeKm: 3.6,
          angelegtAm: DateTime.now(),
          punkte: _spur(hoehen: false),
        ),
      );
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 4);
    await bibOeffnen(tester, de.bibReisen);
    await warte(tester, find.text('Alpenreise'));
    await rolleZu(tester, find.text(de.aktivitaetenTitel));
    expect(find.text('Gipfeltour'), findsWidgets);
    await rolleZu(tester, find.text('Alpenreise'), schritt: -250);
    await tippe(tester, find.text('Alpenreise').first, ms: 2000);
    await warte(tester, find.text('Gipfeltour'));
    expect(find.text('Talrunde'), findsWidgets);
    final yAkt = tester.getTopLeft(find.text('Gipfeltour').first).dy;
    await warteBis(
      tester,
      () => find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'AufnahmenRaster',
            ),
            matching: kacheln(),
          )
          .evaluate()
          .isNotEmpty,
      grund: 'Aufnahmen der Reise',
    );
    // Die Aktivitätskarten stehen im Kopf des Rasters, die Aufnahmen der
    // Reise darunter (die Karten tragen selbst ein Titelbild).
    final fotoKachel = kachelVon(fotos.first);
    await warte(tester, fotoKachel);
    final yRaster = tester.getTopLeft(fotoKachel.first).dy;
    expect(yAkt, lessThan(yRaster), reason: 'Aktivitäten über den Aufnahmen');
    await tippe(tester, find.text('Gipfeltour').first, ms: 2500);
    await rolleZu(tester, find.text(de.spurTitel));
    expect(
      find.textContaining(de.spurKennzahlen('3,6', 280, 30)),
      findsOneWidget,
    );
    expect(find.text(de.spurHoehenprofil), findsOneWidget);
    expect(find.text(de.keineRoute), findsNothing, reason: 'Route aus 4 Fotos');
    final profil = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Hoehenprofil',
    );
    await tester.ensureVisible(profil);
    await ruhe(tester, 500);
    final marken0 = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .length;
    Set<String> punkte() => {
      for (final l in tester.widgetList<MarkerLayer>(find.byType(MarkerLayer)))
        for (final m in l.markers) '${m.point.latitude},${m.point.longitude}',
    };
    final p0 = punkte();
    final r = tester.getRect(profil);
    final g = await tester.startGesture(
      Offset(r.left + r.width * 0.3, r.center.dy),
    );
    await g.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await ruhe(tester, 400);
    final etikett = sichtbareTexte(
      tester,
    ).where((t) => RegExp(r'^\d+,\d km · \d+ m$').hasMatch(t)).toList();
    final ebenen = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .toList();
    final p1 = punkte().difference(p0);
    await g.moveBy(Offset(r.width * 0.3, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await ruhe(tester, 400);
    final p2 = punkte().difference(p0);
    await g.up();
    await ruhe(tester, 800);
    final p3 = punkte().difference(p0);
    print(
      'MOB-124 Etikett $etikett, Marke $p1 → $p2, Ebenen $marken0 → ${ebenen.length}',
    );
    expect(etikett, isNotEmpty);
    expect(p1, hasLength(1), reason: 'eine Marke beim Fahren');
    expect(p2, hasLength(1));
    expect(p1.single == p2.single, isFalse, reason: 'die Marke folgt');
    expect(p3, isEmpty, reason: 'nach dem Loslassen weg');
    await schliesse(tester);
    await tippe(tester, find.text('Talrunde').first, ms: 2500);
    await rolleZu(tester, find.text(de.spurTitel));
    expect(
      find.textContaining(de.spurKennzahlenOhneHoehe('3,6')),
      findsOneWidget,
    );
    expect(find.text(de.spurOhneHoehen), findsOneWidget);
    expect(find.text(de.spurHoehenprofil), findsNothing);
  });

  pruefung('MOB-126 Stammbaum und Lebensbaum', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K126');
    final v = await api(hauptDirekt, konto);
    await hochladen(v, jpeg(), 'baum.jpg');
    final pa = await person(hauptDirekt, konto, 'Person A');
    final pb = await person(hauptDirekt, konto, 'Person B');
    final kind = await person(hauptDirekt, konto, 'Kind');
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(BeziehungHinzufuegen(kind, pa, Verwandtschaft.elternteil));
      await r.tue(BeziehungHinzufuegen(kind, pb, Verwandtschaft.elternteil));
      await r.tue(BeziehungHinzufuegen(pa, pb, Verwandtschaft.partner));
    });
    teilenAbfangen();
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await bibOeffnen(tester, de.bibStammbaum);
    await ruhe(tester, 2000);
    await waehleKonto(tester, kind);
    await ruhe(tester, 1500);
    final baum = find.byType(InteractiveViewer);
    double y(String n) => tester
        .getCenter(find.descendant(of: baum, matching: find.text(n)).first)
        .dy;
    print(
      'MOB-126 Höhen: Kind ${y('Kind')}, A ${y('Person A')}, B ${y('Person B')}',
    );
    expect(y('Kind'), greaterThan(y('Person A')));
    expect(y('Kind'), greaterThan(y('Person B')));
    for (final dd
        in tester
            .widgetList(find.byWidgetPredicate((w) => w is DropdownButton))
            .skip(1)) {
      final d = dd as dynamic;
      final items = d.items as List;
      if (items.length > 1) {
        d.onChanged(items[1].value);
        await ruhe(tester, 800);
      }
    }
    double massstab() => tester
        .widget<InteractiveViewer>(baum)
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    final m0 = massstab();
    await tippe(tester, tooltip(de.baumVergroessern), ms: 800);
    final m1 = massstab();
    await tippe(tester, tooltip(de.baumVerkleinern), ms: 800);
    await tippe(tester, tooltip(de.baumVerkleinern), ms: 800);
    final m2 = massstab();
    await tippe(tester, tooltip(de.baumGanzZeigen), ms: 800);
    print('MOB-126 Massstab $m0 → $m1 → $m2 → ${massstab()}');
    expect(m1, greaterThan(m0));
    expect(m2, lessThan(m1));
    await waehleKonto(tester, kind);
    await ruhe(tester, 800);
    await tippe(
      tester,
      find.descendant(of: baum, matching: find.text('Person A')).first,
      ms: 1500,
    );
    final wert = tester
        .widget<DropdownButton<String>>(
          find.byWidgetPredicate((w) => w is DropdownButton<String>).first,
        )
        .value;
    print('MOB-126 nach dem Tipp: Mitte $wert (Person A $pa)');
    expect(wert, pa);
    await tippe(tester, find.text(de.baumLebensbaum), ms: 2500);
    for (final dd
        in tester
            .widgetList(find.byWidgetPredicate((w) => w is DropdownButton))
            .skip(1)
            .toList()) {
      final d = dd as dynamic;
      final items = d.items as List;
      if (items.length > 1) {
        d.onChanged(items[1].value);
        await ruhe(tester, 800);
      }
    }
    final sw = find.byType(Switch);
    if (sw.evaluate().isNotEmpty) await tippe(tester, sw.first);
    await tippe(tester, find.text(de.lbSpeichern), ms: 2000);
    await warteBis(
      tester,
      () => geteilt.isNotEmpty,
      max: const Duration(seconds: 40),
      grund: 'Bild geteilt',
    );
    final f = geteilt.single.single;
    print('MOB-126 geteilt: ${f.pfad} ${f.daten.length} B');
    expect(f.pfad, endsWith('.png'));
    expect(f.daten.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  pruefung('MOB-128 Rückblick mit Familientagen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K128');
    final v = await api(hauptDirekt, konto);
    final h = DateTime.now();
    await hochladen(v, jpeg(datum: DateTime(h.year, 1, 15)), 'diesjahr.jpg');
    await hochladen(
      v,
      jpeg(
        datum: DateTime(
          h.year - 2,
          h.month,
          h.day,
        ).subtract(const Duration(days: 3)),
      ),
      'frueher.jpg',
    );
    final kind = await person(hauptDirekt, konto, 'Kind');
    final g = DateTime(h.year, h.month, h.day + 3);
    await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.tue(
        LebensdatenSetzen(
          kind,
          geburt: DateTime(g.year - 10, g.month, g.day, 12),
          tod: null,
        ),
      ),
    );
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.bibRueckblick);
    await warte(tester, find.text(de.rbJahr(h.year)));
    await rolleZu(tester, find.text(de.rbFamilientage));
    await warte(
      tester,
      find.text(de.rbInTagen(3, de.rbGeburtstag('Kind', 10))),
    );
    await rolleZu(tester, find.text(de.rbLetzteTage));
    final merken = find.text(de.rbMerken);
    await rolleZu(tester, merken);
    await tippe(tester, merken.first, ms: 1500);
    await rolleZu(tester, find.text(de.rbGemerkt));
    await rolleZu(tester, find.text(de.rbVergessen));
    await tippe(tester, find.text(de.rbVergessen).first, ms: 1500);
    await ruhe(tester, 1000);
    expect(find.text(de.rbVergessen), findsNothing);
    await rolleZu(tester, find.text(de.rbJahr(h.year)), schritt: -250);
    await tippe(tester, find.text(de.rbJahr(h.year)), ms: 1500);
    await warte(tester, find.text(de.jrFotos));
    for (final s in [de.jrVideos, de.jrTage, de.jrLaender]) {
      print('MOB-128 Jahreszahl „$s“: ${find.text(s).evaluate().length}');
    }
    await tippe(tester, tooltip(de.jrVorjahr), ms: 1500);
    await warte(tester, find.text(de.jrLeer(h.year - 1)));
    await tippe(tester, tooltip(de.jrFolgejahr), ms: 1500);
    await warte(tester, find.text(de.jrFotos));
  });

  pruefung('MOB-130 Aufnahmedaten: übernehmen, Prüfsummen, ohne Server', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K130');
    final v = await api(hauptDirekt, konto);
    final bytes = [for (var i = 0; i < 3; i++) jpeg()];
    final ids = [
      await hochladen(v, bytes[0], 'IMG_20200101_100000.jpg'),
      await hochladen(v, bytes[1], 'IMG_20200202_100000.jpg'),
      await hochladen(v, bytes[2], 'IMG_20200303_100000.jpg'),
    ];
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(
        AufnahmedatenSetzen([
          for (var i = 0; i < ids.length; i++)
            (
              id: ids[i],
              zeitpunkt: DateTime(2023, 6, 1 + i, 10),
              geschaetzt: true,
            ),
        ]),
      );
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await warte(
      tester,
      find.textContaining('Bei 3 Aufnahmen nennt der Dateiname'),
      max: const Duration(seconds: 40),
    );
    expect(
      find.textContaining('die Dateien bleiben unverändert'),
      findsWidgets,
    );
    expect(find.textContaining(de.datenLautName), findsWidgets);
    final zeilen = find.byType(CheckboxListTile);
    final erste = tester.widget<CheckboxListTile>(zeilen.first);
    erste.onChanged!(false);
    await ruhe(tester, 800);
    await warte(tester, find.text(de.datenUebernehmen(2)));
    await tippe(tester, find.text(de.datenUebernehmen(2)));
    await warte(tester, find.text(de.datenFrage(2)));
    await tippe(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'OK'),
      ),
      ms: 3000,
    );
    await warte(
      tester,
      find.textContaining('Bei einer Aufnahme nennt'),
      max: const Duration(seconds: 40),
    );
    final mitDatum = [
      for (final id in ids)
        (await amServer(hauptDirekt, konto, id))?.fileCreatedAt,
    ];
    print('MOB-130 Daten am Server: $mitDatum');
    for (var i = 0; i < 3; i++) {
      expect(
        sha(await original(v, ids[i])),
        sha(bytes[i]),
        reason: 'Original $i unverändert',
      );
    }
    final p = await v.schicke('api/v1/pruefsummen', {
      'pruefsummen': [for (final b in bytes) sha(b)],
    });
    print('MOB-130 Prüfsummen am Server: $p');
    expect(((p['vorhanden'] as Map?) ?? const {}).length, 3);
    await schliesse(tester);
    await proxyAus();
    await ruhe(tester, 1000);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await warte(
      tester,
      find.text(de.datenOhneServer),
      max: const Duration(seconds: 70),
    );
    await proxyAn();
  });
}

// ======================================================================
// Entwickeln

Future<void> _entwickelnOeffnen(WidgetTester tester) async {
  await tippe(tester, tooltip(de.betrachterMehr));
  await tippe(tester, find.text(de.entwTitel).last, ms: 3000);
  await warte(
    tester,
    find.text(de.entwBelichtung),
    max: const Duration(seconds: 40),
  );
}

void entwickelnTests() {
  // Behoben in #418: Nach dem Entwickeln vergisst der Betrachter auch die
  // Bildquelle und zeigt gleich die neue Fassung.
  pruefung('MOB-134 Entwickeln: Vorschau, Vorher, Weissabgleich, Speichern', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K134');
    final v = await api(hauptDirekt, konto);
    final ids = [
      await hochladen(
        v,
        jpeg(breite: 4000, hoehe: 3000, datum: DateTime(2024, 5, 5)),
        'entw1.jpg',
      ),
      await hochladen(
        v,
        jpeg(breite: 1200, hoehe: 800, datum: DateTime(2024, 5, 4)),
        'entw2.jpg',
      ),
    ];
    final video = await hochladenDatei(v, 'video_5s.mp4');
    final korb = await hochladen(
      v,
      jpeg(datum: DateTime(2024, 5, 3)),
      'korb134.jpg',
    );
    await mitRechner(hauptDirekt, konto, (r) => r.tue(InDenPapierkorb([korb])));
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    final nachSpeichern = <String>[];
    for (final id in ids) {
      await rolleZu(tester, kachelVon(id));
      await tippe(tester, kachelVon(id), ms: 1500);
      await warte(tester, tooltip(de.betrachterAngaben));
      await _entwickelnOeffnen(tester);
      ui.Image? bild() =>
          tester.widget<RawImage>(find.byType(RawImage).first).image;
      await warteBis(tester, () => bild() != null, grund: 'Vorschau');
      final b0 = bild();
      final regler = find.byType(Slider);
      await tester.drag(regler.first, const Offset(80, 0));
      await ruhe(tester, 1500);
      final b1 = bild();
      expect(identical(b0, b1), isFalse, reason: 'Vorschau ändert sich sofort');
      final vorher = find.text(de.entwVorher);
      if (vorher.evaluate().isNotEmpty) {
        final g = await tester.startGesture(tester.getCenter(vorher));
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await ruhe(tester, 600);
        final gehalten = bild();
        await g.up();
        await ruhe(tester, 800);
        print(
          'MOB-134 Vorher: gehalten=original ${identical(gehalten, b0)}, danach ${identical(bild(), b1)}',
        );
        expect(
          identical(gehalten, b1),
          isFalse,
          reason: '„Vorher“ zeigt das Original',
        );
      }
      // Weissabgleich ausschalten, Farbtemperatur ändern.
      final wa = find.widgetWithText(SwitchListTile, de.entwAutoWeiss);
      await rolleZu(tester, wa, in_: find.byType(Scrollable).last);
      expect(tester.widget<SwitchListTile>(wa).value, isTrue);
      await tippe(tester, wa, ms: 1000);
      expect(tester.widget<SwitchListTile>(wa).value, isFalse);
      final temp = find
          .ancestor(
            of: find.text(de.entwTemperatur),
            matching: find.byType(Column),
          )
          .first;
      final tr = find.descendant(of: temp, matching: find.byType(Slider));
      final s = tester.widget<Slider>(tr.first);
      expect(s.onChanged, isNotNull, reason: 'Temperatur aktiv');
      s.onChanged!(8000);
      s.onChangeEnd?.call(8000);
      await ruhe(tester, 1500);
      // Speichern: Hinweise mitschreiben.
      final gesehen = <String>{};
      await tester.tap(find.text(de.entwSpeichern));
      final ende = DateTime.now().add(const Duration(seconds: 120));
      while (DateTime.now().isBefore(ende) &&
          find.text(de.entwGespeichert).evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
        for (final t in sichtbareTexte(tester)) {
          if (t.contains('Rechne') || t.contains('Lade hoch')) gesehen.add(t);
        }
      }
      print('MOB-134 beim Speichern: $gesehen');
      expect(find.text(de.entwGespeichert), findsWidgets);
      if (id == ids.first) {
        expect(
          gesehen.any(
            (t) => t.contains('Rechne in voller Grösse (4000 × 3000)'),
          ),
          isTrue,
        );
      }
      expect(gesehen.any((t) => t.contains('Lade hoch')), isTrue);
      await ruhe(tester, 2500);
      // Was zeigt der Betrachter jetzt?
      final q = _bildquellen(tester).map(_quelle).toList();
      print('MOB-134 Betrachter nach dem Speichern: $q');
      nachSpeichern.add(q.join(','));
      await schliesse(tester);
      final a = await aufnahme(v, id);
      print('MOB-134 am Server: ${a['developedRelativePath']}');
      expect(
        a['developedRelativePath'],
        isNotNull,
        reason: 'Web und Rechner sehen die neue Fassung',
      );
      final e = await mitRechner(
        hauptDirekt,
        konto,
        (r) => r.db.developSettingsForAsset(id),
      );
      expect(e?.temperature, closeTo(8000, 1));
      // Neu geöffnet: entwickelte Fassung.
      await tippe(tester, kachelVon(id), ms: 2000);
      await warte(tester, tooltip(de.betrachterAngaben));
      await ruhe(tester, 1500);
      final q2 = _bildquellen(tester).map(_quelle).toList();
      print('MOB-134 neu geöffnet: $q2');
      expect(q2.any((x) => x.contains('developed/')), isTrue);
      await schliesse(tester);
    }
    // Video und Papierkorb: kein „Entwickeln“.
    await tippe(tester, kachelVon(video), ms: 1500);
    await tippe(tester, tooltip(de.betrachterMehr));
    expect(find.text(de.entwTitel), findsNothing, reason: 'Video');
    await tester.tapAt(const Offset(10, 10));
    await ruhe(tester, 600);
    await schliesse(tester);
    await bibOeffnen(tester, de.bibPapierkorb);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    final mehr = tooltip(de.betrachterMehr);
    if (mehr.evaluate().isNotEmpty) {
      await tippe(tester, mehr);
      expect(find.text(de.entwTitel), findsNothing, reason: 'Papierkorb');
    }
    print('MOB-134 gleich nach dem Speichern gezeigt: $nachSpeichern');
    expect(
      nachSpeichern,
      everyElement(contains('developed/')),
      reason: 'Betrachter zeigt gleich die neue Fassung',
    );
  });

  pruefung('MOB-136 Masken und Tonkurve vom Rechner', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K136');
    final v = await api(hauptDirekt, konto);
    final maskiert = await hochladen(
      v,
      jpeg(datum: DateTime(2024, 4, 2)),
      'maske.jpg',
    );
    final kurve = await hochladen(
      v,
      jpeg(datum: DateTime(2024, 4, 1)),
      'kurve.jpg',
    );
    final tmp = File(p.join(Directory.systemTemp.path, 'r2_136.png'));
    await tmp.writeAsBytes(_pngBild(64, 48));
    await v.legeAb('api/v1/dateien/masks/$maskiert-1.png', tmp);
    final tmpj = File(p.join(Directory.systemTemp.path, 'r2_136.jpg'));
    await tmpj.writeAsBytes(jpeg(breite: 640, hoehe: 480));
    await v.legeAb('api/v1/dateien/developed/$kurve-1.jpg', tmpj);
    final kurveJson = const ToneCurve(
      zusammen: [CurvePoint(0, 0), CurvePoint(0.5, 0.65), CurvePoint(1, 1)],
    ).encode();
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(MaskeAnlegen(maskiert, 'masks/$maskiert-1.png', 'Himmel'));
      await r.tue(
        EntwicklungSpeichern(
          kurve,
          DevelopSettingsCompanion.insert(
            assetId: kurve,
            toneCurveJson: Value(kurveJson),
            updatedAt: DateTime.now(),
          ),
          'developed/$kurve-1.jpg',
        ),
      );
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    // Maske: Hinweis, Rückfrage verneinen.
    await tippe(tester, kachelVon(maskiert), ms: 1500);
    await _entwickelnOeffnen(tester);
    await warte(tester, find.textContaining(de.entwMaskenHinweis));
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await ruhe(tester, 1000);
    await tippe(tester, find.text(de.entwSpeichern), ms: 1200);
    await warte(tester, find.text(de.entwMaskenFrage));
    await tippe(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, de.abbrechen),
      ),
      ms: 1500,
    );
    expect(
      find.text(de.entwBelichtung),
      findsOneWidget,
      reason: 'Seite bleibt',
    );
    await ruhe(tester, 2000);
    expect(
      (await aufnahme(v, maskiert))['developedRelativePath'],
      isNull,
      reason: 'nicht gespeichert',
    );
    await tippe(tester, find.byType(BackButton));
    if (find.text(de.entwVerwerfen).evaluate().isNotEmpty) {
      await tippe(
        tester,
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .last,
        ms: 1500,
      );
    }
    await warteWeg(tester, find.text(de.entwBelichtung));
    await schliesse(tester);
    // Tonkurve: Hinweis, Speichern behält sie.
    await oeffneId(tester, kurve);
    await _entwickelnOeffnen(tester);
    await warte(tester, find.textContaining(de.entwVomRechner));
    await tester.drag(find.byType(Slider).first, const Offset(60, 0));
    await ruhe(tester, 1000);
    await tippe(tester, find.text(de.entwSpeichern), ms: 500);
    await warte(
      tester,
      find.text(de.entwGespeichert),
      max: const Duration(seconds: 90),
    );
    await ruhe(tester, 2500);
    final e = await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.db.developSettingsForAsset(kurve),
    );
    print('MOB-136 Tonkurve nach dem Speichern: ${e?.toneCurveJson}');
    expect(e?.toneCurveJson, kurveJson);
  });

  pruefung('MOB-140 Diashow als Video: 40 von 50, Abbrechen, MP4', (
    tester,
  ) async {
    final k = await kontoMitFotos('K140', 50);
    teilenAbfangen();
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 6);
    final d = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Diashow',
    );
    Future<void> knoepfe() async {
      await tester.tapAt(tester.getCenter(d));
      await ruhe(tester, 400);
    }

    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.diashowAbHier), ms: 1500);
    await warte(tester, d);
    await knoepfe();
    await tippe(tester, tooltip(de.diashowAlsVideo));
    await warte(tester, find.text(de.diashowVideoTitel));
    await warte(tester, find.textContaining('Die ersten 40 von 50 Fotos'));
    print(
      'MOB-140 Umfang: ${sichtbareTexte(tester).where((t) => t.contains('Fotos'))}',
    );
    await schreibeLeise(tester, feld(de.diashowVideoTitelfeld), 'Probe');
    await tippe(tester, find.text(de.diashowVideoErstellen), ms: 1500);
    await warte(tester, find.text(de.diashowVideoWirdErstellt));
    await tippe(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, de.abbrechen),
      ),
      ms: 3000,
    );
    await warteWeg(
      tester,
      find.text(de.diashowVideoWirdErstellt),
      max: const Duration(seconds: 60),
    );
    await ruhe(tester, 2000);
    expect(geteilt, isEmpty, reason: 'abgebrochen: kein Video');
    expect(find.byType(SnackBar), findsNothing, reason: 'keine Meldung');
    if (find
        .byWidgetPredicate((w) => w is AnimatedOpacity && w.opacity == 0)
        .evaluate()
        .isNotEmpty) {
      await knoepfe();
    }
    await tippe(tester, tooltip(de.diashowBeenden));
    await warteWeg(tester, d);
    await schliesse(tester);
    // Zwei Fotos ganz schreiben lassen.
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, aktion(de.diashow), ms: 1500);
    await warte(tester, d);
    await knoepfe();
    await tippe(tester, tooltip(de.diashowAlsVideo));
    await warte(tester, find.text(de.diashowVideoTitel));
    await schreibeLeise(tester, feld(de.diashowVideoTitelfeld), 'Zwei');
    await schreibeLeise(tester, feld(de.diashowVideoUntertitel), 'Probe');
    await tippe(tester, find.text(de.diashowVideoErstellen), ms: 1500);
    await warteBis(
      tester,
      () => geteilt.isNotEmpty,
      max: const Duration(minutes: 6),
      grund: 'Video geteilt',
    );
    final f = geteilt.single.single;
    print('MOB-140 geteilt: ${f.pfad} ${f.daten.length} B');
    expect(f.pfad, endsWith('.mp4'));
    // Für den Blick auf die Titelkarte auf den Mac kopieren.
    try {
      await File(f.pfad).copy('$katalog/arbeit/r2-mob/shots/mob140.mp4');
    } catch (e) {
      print('MOB-140 Kopie: $e');
    }
    final c = VideoPlayerController.file(File(f.pfad));
    await c.initialize();
    print('MOB-140 Video: ${c.value.size} ${c.value.duration}');
    expect(c.value.size, const Size(1920, 1080));
    expect(c.value.duration.inMilliseconds, inInclusiveRange(8000, 11000));
    await c.dispose();
  });
}

Uint8List _pngBild(int b, int h) {
  final bild = img.Image(width: b, height: h);
  img.fill(bild, color: img.ColorRgb8(255, 255, 255));
  return img.encodePng(bild);
}

// ======================================================================
// Konto

const _appStoreBau = bool.fromEnvironment('PV_STORE');

void kontoTests() {
  // Nur im Lauf mit --dart-define=PV_STORE=true (Bau für den App Store).
  pruefung('MOB-141 App-Store-Bau: keine Zeile „Unterstützen“', (tester) async {
    final k = await kontoMitFotos('K141S', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await kontoOeffnen(tester);
    final texte = await texteBeimRollen(tester);
    print(
      'MOB-141 App-Store-Bau: ${texte.where((t) => t.startsWith('App ') || t.contains('unterstützen'))}',
    );
    expect(texte, contains(de.kontoFassung));
    expect(texte.contains(de.kontoUnterstuetzen), isFalse);
  }, skip: !_appStoreBau);

  pruefung('MOB-141 Kontoseite: Fassung, Unterstützen öffnet den Browser', (
    tester,
  ) async {
    final k = await kontoMitFotos('K141', 1);
    await proxyRegel({
      'muster': r'^/api/v1/zustand',
      'patch': {'fassung': '3.67.8', 'commit': 'abc1234'},
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await kontoOeffnen(tester);
    expect(find.text(hostAdresse), findsOneWidget);
    expect(find.text(de.kontoKontoGeraet(k.konto, 'Telefon')), findsOneWidget);
    await warte(tester, find.text(de.kontoAbgeglichen));
    await rolleZu(tester, find.text(de.kontoFassung));
    await warte(tester, find.textContaining('App 0.19.9 (57) · Server 3.67.8'));
    print(
      'MOB-141 Fassung: ${sichtbareTexte(tester).where((t) => t.startsWith('App '))}',
    );
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const extern =
        'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.launchUrl';
    const safari =
        'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.openUrlInSafariViewController';
    final aufrufe = <String>[];
    for (final k in [extern, safari]) {
      bote.setMockMessageHandler(k, (m) async {
        aufrufe.add('$k ${const StandardMessageCodec().decodeMessage(m)}');
        return const StandardMessageCodec().encodeMessage([
          'abgefangen',
          null,
          null,
        ]);
      });
    }
    addTearDown(() {
      bote.setMockMessageHandler(extern, null);
      bote.setMockMessageHandler(safari, null);
    });
    await rolleZu(tester, find.text(de.kontoUnterstuetzen));
    await tippe(tester, find.text(de.kontoUnterstuetzen), ms: 1500);
    print('MOB-141 Aufrufe: $aufrufe');
    expect(aufrufe, hasLength(1));
    expect(aufrufe.single, startsWith(extern));
    expect(aufrufe.single, contains('ko-fi.com'));
    expect(
      aufrufe.single,
      contains('false'),
      reason: 'externer Browser, nicht in der App',
    );
  });

  pruefung('MOB-152 Entsperren, Passwort, TOTP zurücksetzen', (tester) async {
    final direkt = adresse(Port.konten);
    final server = adresse(Port.kontenProxy);
    final verw = eindeutig('VerwK');
    final b = eindeutig('KontoB');
    for (final (n, vw) in [(verw, true), (b, false)]) {
      final r = await steuer('konto/neu', {
        'server': 'konten',
        'name': n,
        'verwalter': vw,
      });
      expect(r['rc'], 0, reason: '$r');
    }
    final tv = await totpEinrichten(direkt, verw);
    final tb = await totpEinrichten(direkt, b);
    expect(tb.token, isNotEmpty);
    for (var i = 0; i < 6; i++) {
      await anmelden(direkt, b, passwort: 'falsch-falsch-$i');
    }
    await starteApp(tester, server: server, konto: verw, token: tv.token);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontenVerwalten));
    await tippe(tester, find.text(de.kontenVerwalten), ms: 1500);
    await warte(tester, find.text(de.kontenTitel));
    await warte(tester, find.text(b));
    print(
      'MOB-152 Liste: ${sichtbareTexte(tester).where((t) => t.contains('TOTP') || t.contains(b))}',
    );
    expect(find.textContaining(de.kontoGesperrt), findsWidgets);
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.kontoEntsperren), ms: 1500);
    await meldung(tester, de.kontoErledigt);
    expect(
      await anmelden(direkt, b),
      isNot(isA<AnmeldungAbgewiesen>()),
      reason: 'B kann sich wieder anmelden',
    );
    await meldungenWeg(tester);
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.kontoPasswortSetzen), ms: 1000);
    await warte(tester, find.text(de.kontoPasswortSetzenText(b)));
    final dialog = find.byType(AlertDialog);
    Finder f(String l) => find.descendant(of: dialog, matching: feld(l));
    await schreibeLeise(tester, f(de.anmeldenPasswort), '${pw}B');
    await schreibeLeise(tester, f(de.anmeldenPasswortWiederholen), '${pw}B');
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
      ms: 2000,
    );
    await meldung(tester, de.kontoErledigt);
    final rb = await Serververbindung(
      direkt,
      tb.token,
    ).anfrage('GET', 'api/v1/abgleich/stand');
    expect(rb.statusCode, 401, reason: 'Gerät von B abgemeldet');
    await meldungenWeg(tester);
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.kontoTotpZuruecksetzen), ms: 1500);
    await meldung(tester, de.kontoTotpZurueckgesetzt(b));
    final neu = await anmelden(direkt, b, passwort: '${pw}B');
    print('MOB-152 nächste Anmeldung von B: $neu');
    expect(neu, isA<AnmeldungTotpEinrichten>());
  });

  pruefung('MOB-153 MOB-154 Konto entfernen; ohne Verwalterrecht', (
    tester,
  ) async {
    final direkt = adresse(Port.verw);
    final server = adresse(Port.verwProxy);
    final vw = await verwalter(direkt);
    try {
      await vw.schicke('api/v1/sicherung/einrichten', {
        'passphrase': 'Pruef-Sicherung-123456',
      });
    } catch (e) {
      print('MOB-154 Sicherung einrichten: $e');
    }
    print('MOB-154 Server-Sicherung: ${await vw.hole('api/v1/sicherung')}');
    final a = await kontoAnlegen(direkt, 'KontoA');
    final b = await kontoAnlegen(direkt, 'KontoB');
    final vb = await api(direkt, b, geraet: 'B-Telefon');
    final bild = jpeg();
    await hochladen(vb, bild, 'b153.jpg');
    final idB = await eigeneKontoId(vb);
    // MOB-154 Gegenprobe: der Verwalter sieht die Zeilen.
    await starteApp(tester, server: server, konto: 'Verwalter');
    await kontoOeffnen(tester);
    await ruhe(tester, 3000);
    final texteV = await texteBeimRollen(tester);
    final beimVerwalter = {
      for (final t in [
        de.kontenVerwalten,
        de.verwAnstossen,
        de.verwJetztSichern,
      ])
        t: texteV.contains(t),
      'Server-Sicherung': texteV.any(
        (x) => x.contains('Sicherung des Servers'),
      ),
    };
    print('MOB-154 beim Verwalter: $beimVerwalter');
    // MOB-153: B entfernen.
    await rolleZu(tester, find.text(de.kontenVerwalten));
    await tippe(tester, find.text(de.kontenVerwalten), ms: 1500);
    await warte(tester, find.text(b));
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.entfernen), ms: 1000);
    await warte(tester, find.text(de.kontoEntfernenTitel(b)));
    expect(find.text(de.kontoEntfernenText), findsOneWidget);
    expect(de.kontoEntfernenText, contains('beiseitegelegt, nicht gelöscht'));
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(find.text(b), findsOneWidget);
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.entfernen), ms: 1000);
    await tippe(tester, find.text(de.entfernen).last, ms: 2500);
    await warteWeg(tester, find.text(b));
    final rb = await vb.anfrage('GET', 'api/v1/abgleich/stand');
    expect(rb.statusCode, 401, reason: 'Gerät von B abgemeldet');
    final bib = Directory('${serverDaten('mob-verw')}/bibliotheken');
    final beiseite = [
      for (final e in bib.listSync())
        if (p.basename(e.path).startsWith('$idB.entfernt-')) e.path,
    ];
    print('MOB-153 beiseitegelegt: $beiseite');
    expect(beiseite, hasLength(1));
    final dateien = [
      for (final f in Directory(
        '${beiseite.single}/library/originals',
      ).listSync(recursive: true))
        if (f is File) f,
    ];
    expect(dateien, hasLength(1));
    expect(
      sha(await dateien.single.readAsBytes()),
      sha(bild),
      reason: 'Original liegt unversehrt',
    );
    expect(Directory('${bib.path}/$idB').existsSync(), isFalse);
    // MOB-154: Konto A ohne Verwaltung.
    await starteApp(tester, server: server, konto: a);
    await kontoOeffnen(tester);
    await ruhe(tester, 3000);
    final texteA = await texteBeimRollen(tester);
    print('MOB-154 Kontoseite von A: $texteA');
    expect(texteA, contains(de.kontoAbmelden), reason: 'ganz durchgesehen');
    for (final t in [
      de.kontenVerwalten,
      de.verwAnstossen,
      de.verwJetztSichern,
      de.verwAuswertungRuht,
    ]) {
      expect(texteA.contains(t), isFalse, reason: t);
    }
    expect(texteA.any((x) => x.contains('Sicherung des Servers')), isFalse);
    final va = await api(direkt, a);
    for (final (m, pfad) in [
      ('GET', 'api/v1/konten'),
      ('GET', 'api/v1/sicherung'),
      ('POST', 'api/v1/sicherung/jetzt'),
    ]) {
      final r = await va.anfrage(m, pfad);
      print('MOB-154 A $m $pfad: ${r.statusCode}');
      expect(r.statusCode, 403);
    }
    expect(beimVerwalter[de.kontenVerwalten], isTrue);
    expect(
      beimVerwalter['Server-Sicherung'],
      isTrue,
      reason: 'Stand der Server-Sicherung beim Verwalter',
    );
  });
}

// ======================================================================
// Einstellungen

void einstellungenTests() {
  pruefung('MOB-157 Einstellungen: vier Schalter, Web → Handy', (tester) async {
    final k = await kontoMitFotos('K157', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await bibOeffnen(tester, de.bibEinstellungen);
    await warte(tester, find.text(de.einstHinweis));
    Future<void> schalte(String titel) async {
      final zeile = find
          .ancestor(of: find.text(titel), matching: find.byType(Row))
          .first;
      final sw = find.descendant(of: zeile, matching: find.byType(Switch));
      await meldungenWeg(tester);
      await rolleZu(tester, find.text(titel));
      await tippe(tester, sw.first);
      await meldung(tester, de.einstGespeichert);
    }

    Future<Bibliothekseinstellungen> amServer() =>
        mitRechner(hauptDirekt, k.konto, (r) => bibliothekseinstellungen(r.db));
    final vorher = await amServer();
    for (final t in [
      de.einstFormateStapeln,
      de.einstAuswerten,
      de.einstUebersetzen,
      de.einstSchuetzen,
    ]) {
      await schalte(t);
    }
    await ruhe(tester, 3000);
    final nachher = await amServer();
    print('MOB-157 vorher $vorher\nMOB-157 nachher $nachher');
    expect(nachher.formateStapeln, !vorher.formateStapeln);
    expect(nachher.auswertenNachImport, !vorher.auswertenNachImport);
    expect(nachher.sucheUebersetzen, !vorher.sucheUebersetzen);
    expect(nachher.angabenSchuetzen, !vorher.angabenSchuetzen);
    // Web: einen Schalter zurückstellen.
    await befehl(k.v, 'sucheUebersetzenSetzen', {
      'an': vorher.sucheUebersetzen,
    });
    final app = _laufendeSitzung(tester);
    await warteBis(
      tester,
      () async =>
          (await bibliothekseinstellungen(app.db)).sucheUebersetzen ==
          vorher.sucheUebersetzen,
      max: const Duration(seconds: 60),
      grund: 'Änderung aus dem Web kommt an',
    );
    await schliesse(tester);
    await bibOeffnen(tester, de.bibEinstellungen);
    await warte(tester, find.text(de.einstHinweis));
    final zeile = find
        .ancestor(
          of: find.text(de.einstUebersetzen),
          matching: find.byType(Row),
        )
        .first;
    await rolleZu(tester, find.text(de.einstUebersetzen));
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: zeile, matching: find.byType(Switch)).first,
          )
          .value,
      vorher.sucheUebersetzen,
    );
  });

  pruefung('MOB-159 Gesichtsvorschläge und Schwelle', (tester) async {
    final k = await kontoMitFotos('K159', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await bibOeffnen(tester, de.bibEinstellungen);
    final zeile = find
        .ancestor(
          of: find.text(de.einstVorschlaege),
          matching: find.byType(Row),
        )
        .first;
    await rolleZu(tester, find.text(de.einstVorschlaege));
    await tippe(
      tester,
      find.descendant(of: zeile, matching: find.byType(Switch)),
    );
    await meldung(tester, de.einstGespeichert);
    final regler = find.byType(Slider);
    final v0 = tester.widget<Slider>(regler.first);
    print('MOB-159 Vorschläge: ${v0.min}–${v0.max}, Stufen ${v0.divisions}');
    expect(v0.min, closeTo(0.6, 0.001));
    expect(v0.max, closeTo(0.9, 0.001));
    await tester.drag(regler.at(0), const Offset(400, 0));
    await ruhe(tester, 2000);
    expect(find.text(de.einstAb('90 %')), findsOneWidget);
    await meldungenWeg(tester);
    await rolleZu(tester, find.text(de.einstSchwelle));
    await tester.ensureVisible(regler.last);
    await ruhe(tester, 600);
    final s = tester.widget<Slider>(regler.last);
    expect(s.min, closeTo(0.2, 0.001));
    expect(s.max, closeTo(0.8, 0.001));
    final r = tester.getRect(regler.last);
    const rand = 24.0;
    final x = r.left + rand + (0.65 - 0.2) / 0.6 * (r.width - 2 * rand);
    final g = await tester.startGesture(Offset(x - 30, r.center.dy));
    await g.moveBy(const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(15, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await ruhe(tester, 400);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(de.einstGespeichert),
      ),
      findsNothing,
      reason: 'erst beim Loslassen',
    );
    await g.up();
    await meldung(tester, de.einstGespeichert);
    final wert = tester.widget<Slider>(regler.last).value;
    print('MOB-159 Schwelle nach dem Ziehen: $wert');
    await ruhe(tester, 3000);
    final e = await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => bibliothekseinstellungen(r.db),
    );
    print(
      'MOB-159 am Server: vorschläge ${e.vorschlaegeAb} schwelle ${e.gesichtsschwelle}',
    );
    expect(e.vorschlaegeAb, closeTo(0.9, 0.001));
    expect(e.gesichtsschwelle, closeTo(wert, 0.006));
    expect(wert, closeTo(0.65, 0.03));
    await schliesse(tester);
    await bibOeffnen(tester, de.bibEinstellungen);
    await rolleZu(tester, find.text(de.einstSchwelle));
    expect(
      find.text(wert.toStringAsFixed(2)),
      findsOneWidget,
      reason: 'Wert bleibt',
    );
    expect(find.text(de.einstAb('90 %')), findsOneWidget);
  });
}

Sitzung _laufendeSitzung(WidgetTester tester) =>
    tester.widget<PhotoVaultMobil>(find.byType(PhotoVaultMobil)).sitzung;

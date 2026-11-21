// ignore_for_file: avoid_print
part of 'katalog_mob_r2_test.dart';

// ======================================================================
// Gesichter mit dem Erkennungsmodell des Servers

Future<Map<String, String>> _portraits(
  Serververbindung v,
  List<(String, int)> wer,
) async {
  final ids = <String, String>{};
  for (final (k, n) in wer) {
    for (var i = 1; i <= n; i++) {
      final name = 'person_${k}_$i.jpg';
      ids[name] = await hochladenPfad(v, '$mlFix/gesichter/$name');
    }
  }
  return ids;
}

/// Gruppen „Ohne Namen“ am Server: je Gruppe die Gesichter (id, aufnahme).
Future<List<List<Map<String, Object?>>>> _ohneNamen(Serververbindung v) async {
  final d = await v.hole('api/v1/gesichter/ohne-namen');
  return [
    for (final g in (d['gruppen'] as List? ?? const []).cast<Map>())
      [for (final f in (g['gesichter'] as List).cast<Map>()) f.cast()],
  ];
}

List<Map<String, Object?>>? _gruppeVon(
  List<List<Map<String, Object?>>> gruppen,
  Map<String, String> namen,
  String praefix,
) {
  for (final g in gruppen) {
    final n = {for (final f in g) namen[f['aufnahme']] ?? ''};
    if (n.isNotEmpty && n.every((x) => x.startsWith(praefix))) return g;
  }
  return null;
}

void gesichterTests() {
  pruefung('MOB-076 MOB-080 Ohne Namen: Vorschlag bestätigen, im Foto zeigen', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K076');
    final v = await api(hauptDirekt, konto);
    final ids = await _portraits(v, [('a', 4), ('c', 4), ('b', 2)]);
    final namen = {for (final e in ids.entries) e.value: e.key};
    await auswerten(v);
    var gruppen = await _ohneNamen(v);
    final ga = _gruppeVon(gruppen, namen, 'person_a')!;
    print(
      'MOB-076 Gruppen: ${[for (final g in gruppen) g.map((f) => namen[f['aufnahme']]).toList()]}',
    );
    final pa = uuid();
    await befehl(v, 'personAnlegen', {'personId': pa, 'name': 'Person A'});
    final erstes = ga.firstWhere(
      (f) => namen[f['aufnahme']] == 'person_a_1.jpg',
    );
    await befehl(v, 'gesichterZuordnen', {
      'gesichtIds': [erstes['id']],
      'personId': pa,
    });
    // Für den grünen Rahmen: ein benanntes Gesicht von Hand auf a_2.
    final pb = await person(hauptDirekt, konto, 'Person B');
    await gesicht(
      v,
      ids['person_a_2.jpg']!,
      kasten: const [0.02, 0.02, 0.12, 0.12],
      personId: pb,
    );
    final db = bibliotheksDb('mob-haupt', await eigeneKontoId(v));
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bibOeffnen(tester, de.navPersonen);
    await warte(tester, find.text(de.gesichterOhneNamen));
    final kopf = sichtbareTexte(
      tester,
    ).where((t) => t.contains('Gesichter')).toList();
    print('MOB-076 Kopf und Karten: $kopf');
    await warte(tester, find.text(de.gesichterVorschlagFrage('Person A')));
    expect(find.text(de.gesichterWerIstDas), findsWidgets);
    // MOB-080 zuerst: Gruppe öffnen, „Im Foto zeigen“.
    await tippe(
      tester,
      find.text(de.gesichterVorschlagFrage('Person A')),
      ms: 1500,
    );
    await warte(tester, find.text(de.gesichterAehnliche(3)));
    expect(find.text(de.gesichterHinweis), findsOneWidget);
    expect(
      find.bySemanticsLabel(de.gesichtImFoto),
      findsWidgets,
      reason: 'Zeichen „Im Foto zeigen“ an jedem Gesicht',
    );
    expect(
      tooltip(de.gesichtImFoto),
      findsNothing,
      reason: 'Katalog nennt einen Tooltip; das Zeichen hat nur ein Label',
    );
    final knoepfe = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'ImFotoKnopf',
      ),
    );
    // Das Gesicht auf a_2 suchen (dort steht auch das benannte).
    final bilder = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'Personenbild',
      ),
    );
    final pfade = [
      for (final e in bilder.evaluate()) '${(e.widget as dynamic).relativ}',
    ];
    final aufA2 = <int>[];
    for (var i = 0; i < pfade.length; i++) {
      final z = await sql(
        db,
        'SELECT asset_id FROM faces WHERE crop_relative_path = ?',
        [pfade[i]],
      );
      if (z.isNotEmpty && z.first.first == ids['person_a_2.jpg']) aufA2.add(i);
    }
    print('MOB-080 Ausschnitte $pfade, auf a_2: $aufA2');
    await tippe(tester, knoepfe.at(aufA2.isEmpty ? 0 : aufA2.first), ms: 2500);
    final rahmen = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Rahmen',
    );
    await warteBis(
      tester,
      () => rahmen.evaluate().isNotEmpty,
      grund: 'Rahmen im ganzen Foto',
    );
    final r = [
      for (final e in rahmen.evaluate())
        '${(e.widget as dynamic).gewaehlt}/${(e.widget as dynamic).name}',
    ];
    print('MOB-080 Rahmen: $r');
    expect(r.where((x) => x.startsWith('true/')), hasLength(1));
    if (aufA2.isNotEmpty) {
      expect(r, contains('false/Person B'), reason: 'benannt mit Namen');
      expect(find.text('Person B'), findsWidgets);
    }
    await zurueck(tester);
    // MOB-076: ein Gesicht herausnehmen, „Das ist Person A“.
    if (find.text(de.gesichterAehnliche(3)).evaluate().isEmpty) {
      await tippe(
        tester,
        find.text(de.gesichterVorschlagFrage('Person A')),
        ms: 1500,
      );
    }
    final bild0 = bilder.evaluate().first.widget as dynamic;
    final heraus = '${bild0.relativ}';
    await tippe(tester, bilder.first);
    await tippe(tester, find.text(de.gesichterDasIst('Person A')), ms: 2500);
    await app.sitzung.gleicheAb();
    await Future<void>.delayed(const Duration(seconds: 2));
    final z = await sql(
      db,
      'SELECT person_id FROM faces WHERE crop_relative_path = ?',
      [heraus],
    );
    final beiA = await sql(
      db,
      'SELECT count(*) FROM faces WHERE person_id = ?',
      [pa],
    );
    print('MOB-076 herausgenommen: $z, bei Person A: $beiA');
    expect(z.single.single, isNull, reason: 'bleibt ohne Namen');
    expect(beiA.single.single, 3, reason: '1 benanntes + 2 übrige');
    // MOB-080 offline: ein nie geladenes Foto.
    gruppen = await _ohneNamen(v);
    await zurueck(tester);
    await zurueck(tester);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await bibOeffnen(tester, de.navPersonen);
    await warte(tester, find.text(de.gesichterWerIstDas));
    await proxyAus();
    await tippe(tester, find.text(de.gesichterWerIstDas).first, ms: 1500);
    await tippe(tester, knoepfe.last, ms: 3000);
    await warte(
      tester,
      find.text(de.gesichtFotoFehlt),
      max: const Duration(seconds: 40),
    );
    await proxyAn();
  });

  pruefung('MOB-078 Weitere Fotos einer Person finden', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K078');
    final v = await api(hauptDirekt, konto);
    final ids = await _portraits(v, [('a', 5), ('b', 3)]);
    final namen = {for (final e in ids.entries) e.value: e.key};
    await auswerten(v);
    final gruppen = await _ohneNamen(v);
    final ga = _gruppeVon(gruppen, namen, 'person_a')!;
    final gb = _gruppeVon(gruppen, namen, 'person_b')!;
    final pa = uuid(), pc = uuid();
    await befehl(v, 'personAnlegen', {'personId': pa, 'name': 'Person A'});
    await befehl(v, 'personAnlegen', {'personId': pc, 'name': 'Person C'});
    await befehl(v, 'gesichterZuordnen', {
      'gesichtIds': [
        ga.firstWhere((f) => namen[f['aufnahme']] == 'person_a_1.jpg')['id'],
      ],
      'personId': pa,
    });
    await befehl(v, 'gesichterZuordnen', {
      'gesichtIds': [for (final f in gb) f['id']],
      'personId': pc,
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bereich(tester, de.navBibliothek);
    await rolleZu(tester, find.text('Person A'));
    await tippe(tester, find.text('Person A').first, ms: 1500);
    await tippe(tester, tooltip(de.gesichterWeitereFinden), ms: 3000);
    await warte(
      tester,
      find.text(de.gesichterVorschlaegeFuer('Person A')),
      max: const Duration(seconds: 40),
    );
    expect(find.textContaining(de.gesichterVorschlagHinweis), findsWidgets);
    final n = ga.length - 1;
    await warte(tester, find.text(de.gesichterZuordnenAnzahl(n)));
    // Ein Gesicht abwählen.
    final kachel = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await tippe(tester, kachel.first);
    await warte(tester, find.text(de.gesichterZuordnenAnzahl(n - 1)));
    await tippe(tester, find.text(de.gesichterZuordnenAnzahl(n - 1)), ms: 300);
    await meldung(tester, de.gesichterUebernommen(n - 1));
    await warteBis(
      tester,
      () => rasterIds(tester).length == n,
      max: const Duration(seconds: 30),
      grund: 'Personenseite neu geladen',
    );
    await zurueck(tester);
    await rolleZu(tester, find.text('Person C'));
    await tippe(tester, find.text('Person C').first, ms: 1500);
    await tippe(tester, tooltip(de.gesichterWeitereFinden), ms: 3000);
    await warte(
      tester,
      find.textContaining('Kein unbenanntes Gesicht liegt über der Schwelle'),
      max: const Duration(seconds: 40),
    );
    print(
      'MOB-078 ohne Treffer: ${sichtbareTexte(tester).where((t) => t.contains('Schwelle'))}',
    );
  });
}

// ======================================================================
// Gesperrte Aufnahmen (direkt in der Wegwerf-DB gesperrt: Sperren geht am
// Rechner nur ohne Server, library_state.dart:1067 `_nurOhneServer`)

void sperreTests() {
  pruefung('MOB-083 MOB-105 MOB-109 Gesperrte Aufnahme erscheint nirgends', (
    tester,
  ) async {
    final h = DateTime.now();
    final tag = DateTime(h.year - 2, h.month, h.day, 11);
    final a = await kontoAnlegen(hauptDirekt, 'K109A');
    final va = await api(hauptDirekt, a);
    final b = await kontoAnlegen(hauptDirekt, 'K109B');
    final p0 = await hochladen(
      va,
      jpeg(
        datum: tag,
        kamera: 'Offen',
        modell: 'Offenmodell',
        breitengrad: 50.1,
        laengengrad: 8.6,
      ),
      'offen_109.jpg',
    );
    final x = await hochladen(
      va,
      jpeg(
        datum: tag.add(const Duration(minutes: 5)),
        kamera: 'Sperr',
        modell: 'Sperrmodell',
        breitengrad: 50.12,
        laengengrad: 8.62,
      ),
      'geheim_109.jpg',
    );
    final p2 = await hochladen(
      va,
      jpeg(datum: DateTime(2023, 1, 1)),
      'korb_109.jpg',
    );
    final video = await hochladenDatei(va, 'video_5s.mp4');
    final pa = await person(hauptDirekt, a, 'Person A');
    final g0 = await gesicht(va, p0, personId: pa);
    await gesicht(va, x, personId: pa);
    final album = await _albumMit(a, 'Sperralbum', [p0, x, p2, video]);
    final dbA = bibliotheksDb('mob-haupt', await eigeneKontoId(va));
    final crop = (await sql(
      dbA,
      'SELECT crop_relative_path FROM faces WHERE id = ?',
      [g0],
    )).single.single;
    await mitRechner(hauptDirekt, a, (r) async {
      await r.tue(
        OrtSetzen([x], 50.12, 8.62, land: 'Germany', stadt: 'Sperrstadt'),
      );
      await r.tue(PersonTitelbildSetzen(pa, '$crop'));
      await r.tue(InDenPapierkorb([p2]));
    });
    // Teilen der Bibliothek mit B (ganz).
    final idB = await kontoId(va, b);
    expect((await va.anfrage('PUT', 'api/v1/partner/$idB')).statusCode, 204);
    // Sperren wie der Tresor: is_locked in der Bibliothek.
    await sql(dbA, 'UPDATE assets SET is_locked = 1 WHERE id = ?', [x]);
    expect(
      (await sql(dbA, 'SELECT is_locked FROM assets WHERE id = ?', [
        x,
      ])).single.single,
      1,
    );
    final app = await starteApp(tester, server: hauptApp, konto: a);
    await warteAufKacheln(tester, 2);
    // Zeitleiste
    final zl = rasterIds(tester);
    print('MOB-109 Zeitleiste: $zl');
    expect(zl, contains(p0));
    expect(zl, isNot(contains(x)));
    expect(
      await app.sitzung.db.assetById(x),
      isNotNull,
      reason: 'in der Kopie, nur verborgen',
    );
    // Erinnerung „Vor 2 Jahren“ mit nur einer Aufnahme
    await warte(tester, find.text(de.erinnerungenVorJahren(2)));
    expect(find.text(de.erinnerungenAnzahl(1)), findsWidgets);
    expect(find.text(de.erinnerungenAnzahl(2)), findsNothing);
    // Album (MOB-083) samt Diashow
    await _albumOeffnen(tester, 'Sperralbum');
    await warte(tester, find.widgetWithText(AppBar, 'Sperralbum'));
    for (final t in [
      de.diashow,
      de.albumAlsLink,
      tt.kontenTeilen,
      de.albumOfflineSpeichern,
    ]) {
      expect(tooltip(t), findsOneWidget, reason: t);
    }
    await warteBis(
      tester,
      () => rasterIds(tester).isNotEmpty,
      grund: 'Albumraster',
    );
    final imAlbum = rasterIds(tester);
    print('MOB-083 Albumraster: $imAlbum');
    expect(imAlbum.toSet(), {p0, video});
    await tippe(tester, tooltip(de.diashow), ms: 1500);
    final d = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Diashow',
    );
    await warte(tester, d);
    final fotos = [
      for (final z in (tester.widget(d) as dynamic).fotos as List)
        z.id as String,
    ];
    print('MOB-083 Diashow: $fotos');
    expect(fotos, [p0]);
    await schliesse(tester);
    await schliesse(tester);
    // Personenseite
    await bereich(tester, de.navBibliothek);
    await rolleZu(tester, find.text('Person A'));
    await tippe(tester, find.text('Person A').first, ms: 1500);
    await warteBis(
      tester,
      () => rasterIds(tester).isNotEmpty,
      grund: 'Personenseite',
    );
    expect(rasterIds(tester), [p0]);
    final bild = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Personenbild',
    );
    final titelbilder = {
      for (final e in bild.evaluate()) '${(e.widget as dynamic).relativ}',
    };
    print('MOB-109 Titelbilder der Person: $titelbilder');
    await zurueck(tester);
    // Karte: nur ein Punkt
    await bibOeffnen(tester, de.navKarte);
    await ruhe(tester, 3000);
    final punkte = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_Punkt',
    );
    final menge = [
      for (final e in punkte.evaluate())
        ((e.widget as dynamic).gruppe as List).length,
    ];
    print('MOB-109 Kartenpunkte: $menge');
    expect(menge.fold<int>(0, (s, n) => s + n), 1);
    await schliesse(tester);
    // Orte
    await bibOeffnen(tester, de.bibOrte);
    await ruhe(tester, 2500);
    expect(find.textContaining('Sperrstadt'), findsNothing);
    await schliesse(tester);
    // Suche nach dem Ort und dem Dateinamen
    await bereich(tester, de.navSuche);
    for (final s in ['Sperrstadt', 'geheim_109']) {
      final f = find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == 'Suche',
            ),
            matching: find.byType(TextField),
          )
          .first;
      await schreibeLeise(tester, f, s);
      await absenden(tester, f);
      await ruhe(tester, 3000);
      final suchRaster = find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Suche'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'AufnahmenRaster',
        ),
      );
      final treffer = suchRaster.evaluate().isEmpty
          ? <String>[]
          : [
              for (final z
                  in ((tester.widget(suchRaster.first) as dynamic).zeilen
                      as List))
                z.id as String,
            ];
      print(
        'MOB-109 Suche „$s“: $treffer, '
        '„${de.sucheNichts}“ ${find.text(de.sucheNichts).evaluate().length}',
      );
      expect(treffer, isNot(contains(x)));
    }
    // Statistik
    await bibOeffnen(tester, de.bibStatistik);
    await warte(tester, find.text(de.statGesperrt));
    final kachel = find.ancestor(
      of: find.text(de.statGesperrt),
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Kennzahl',
      ),
    );
    final inKachel = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: kachel.first, matching: find.byType(Text)),
      ))
        t.data ?? '',
    ];
    print('MOB-109 Statistik „Gesperrter Ordner“: $inKachel');
    expect(inKachel, contains('1'));
    await schliesse(tester);
    // Der Server liefert die Datei nicht aus.
    final mini = await va.anfrage('GET', 'api/v1/aufnahmen/$x/miniatur');
    expect(mini.statusCode, isNot(200));
    // MOB-105: B sieht die Bibliothek ohne Papierkorb und Gesperrtes.
    final vb = await api(hauptDirekt, b);
    final idA = await kontoId(vb, a);
    for (final (id, soll) in [(p0, true), (x, false), (p2, false)]) {
      final r = await vb.anfrage(
        'GET',
        'api/v1/partner/von/$idA/aufnahmen/$id/miniatur',
      );
      print('MOB-105 B ruft $id: ${r.statusCode}');
      expect(r.statusCode == 200, soll, reason: id);
    }
    final zl2 = await vb.hole('api/v1/partner/von/$idA/aufnahmen');
    final sichtbar = jsonEncode(zl2);
    expect(sichtbar.contains(x), isFalse, reason: 'Liste ohne Gesperrtes');
    expect(sichtbar.contains(p2), isFalse, reason: 'Liste ohne Papierkorb');
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text(tt.partnerBibliothekVon(a)));
    expect(find.text(tt.partnerGanzeBibliothek), findsOneWidget);
    await tippe(tester, find.text(tt.partnerBibliothekVon(a)), ms: 2500);
    await tippe(tester, find.byType(PopupMenuButton<void>), ms: 800);
    final menue = [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is PopupMenuEntry),
          matching: find.byType(Text),
        ),
      ))
        t.data ?? '',
    ];
    print('MOB-105 Menü bei B: $menue');
    expect(menue, hasLength(2), reason: 'nur Zeitleiste und Verlassen');
    expect(album, isNotEmpty);
  });
}

// ======================================================================
// Alben

void albenTests() {
  pruefung('MOB-089 Offline aufheben; Auswahl nur auf diesem Gerät', (
    tester,
  ) async {
    final k = await kontoMitFotos('K089', 2);
    final album = await _albumMit(k.konto, 'Offline089', k.ids);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await _albumOeffnen(tester, 'Offline089');
    await tippe(tester, tooltip(de.albumOfflineSpeichern), ms: 200);
    await meldung(
      tester,
      de.albumOfflineFertig(2),
      max: const Duration(seconds: 90),
    );
    await warte(tester, find.textContaining('Offline auf diesem Telefon ·'));
    // Zweites Gerät desselben Kontos (eigene Kopie, eigener Gerätename).
    final ordner2 = await Directory.systemTemp.createTemp('pv_zweit_');
    final s2 = Sitzung(
      ordner: () async => Directory(p.join(ordner2.path, 'bibliothek')),
    );
    await s2.verbinde(
      server: hauptApp,
      konto: k.konto,
      geraet: 'Zweitgeraet',
      token: await holeToken(hauptDirekt, k.konto, geraet: 'Zweitgeraet'),
    );
    expect(s2.istAlbumOffline(album), isFalse, reason: 'zweites Gerät');
    expect(app.sitzung.istAlbumOffline(album), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(PhotoVaultMobil(sitzung: s2));
    await ruhe(tester, 1500);
    await _albumOeffnen(tester, 'Offline089');
    await warte(tester, tooltip(de.albumOfflineSpeichern));
    expect(find.textContaining('Offline auf diesem Telefon ·'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await s2.beende();
    await ordner2.delete(recursive: true);
    await tester.pump();
    await tester.pumpWidget(PhotoVaultMobil(sitzung: app.sitzung));
    await ruhe(tester, 1500);
    // „Leeren“ lässt die angehefteten Dateien liegen.
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoZwischenspeicherLeeren));
    await tippe(tester, find.text(de.kontoZwischenspeicherLeeren), ms: 1500);
    await zurueck(tester);
    await proxyAus();
    await _albumOeffnen(tester, 'Offline089');
    await oeffneKachel(tester, 0);
    await zoome(tester);
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
    await schliesse(tester);
    await proxyAn();
    await tippe(tester, tooltip(de.albumOfflineAufheben));
    await meldung(tester, de.albumOfflineEntfernt);
    expect(find.textContaining('Offline auf diesem Telefon ·'), findsNothing);
  });

  pruefung('MOB-104 Album automatisch mit Personen füllen', (tester) async {
    final k = await kontoMitFotos('K104', 3);
    final pa = await person(hauptDirekt, k.konto, 'Person A');
    final kind = await person(hauptDirekt, k.konto, 'Kind');
    await gesicht(k.v, k.ids[0], personId: pa, kasten: [0.1, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[0], personId: kind, kasten: [0.6, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[1], personId: pa);
    await _albumMit(k.konto, 'Regelalbum', const []);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await proxyLogLeeren();
    await _albumOeffnen(tester, 'Regelalbum');
    await ruhe(tester, 2500);
    final knopf = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Albumregelknopf',
    );
    final regel = (await proxyPfade())
        .where((x) => x.contains('/regel'))
        .toList();
    print(
      'MOB-104 Albumregelknopf: ${knopf.evaluate().length}, '
      'Tooltip da: ${tooltip(tt.automatischFuellen).evaluate().length}, '
      'Anfragen: $regel, Proxy-Status: ${[for (final e in await proxyLog())
        if ('${e['pfad']}'.contains('/regel')) e['status']]}',
    );
    await tippe(tester, tooltip(tt.automatischFuellen), ms: 1500);
    await warte(tester, find.text(tt.automatischTitel('Regelalbum')));
    await tippe(tester, find.text(tt.speichern).last, ms: 1500);
    await warte(tester, find.text(tt.regelMindestensEine));
    await tippe(tester, find.widgetWithText(CheckboxListTile, 'Person A'));
    final liste = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await rolleZu(
      tester,
      find.widgetWithText(CheckboxListTile, 'Kind'),
      in_: liste.first,
      schritt: 40,
    );
    await tippe(tester, find.widgetWithText(CheckboxListTile, 'Kind'));
    await tippe(tester, find.text(tt.regelAlle));
    await tippe(tester, find.text(tt.speichern).last, ms: 2500);
    await meldung(
      tester,
      tt.automatischDazu(1),
      max: const Duration(seconds: 30),
    );
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      max: const Duration(seconds: 30),
      grund: 'Foto mit beiden',
    );
    expect(rasterIds(tester), [k.ids[0]]);
    await meldungenWeg(tester);
    await ruhe(tester, 1500);
    await tippe(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            (w.tooltip ?? '').startsWith(tt.automatischFuellen),
      ),
      ms: 1500,
    );
    await tippe(tester, find.text(tt.automatischAus), ms: 2000);
    await meldung(tester, tt.automatischAusGemacht);
    expect(rasterIds(tester), [k.ids[0]], reason: 'was darin liegt, bleibt');
  });
}

// ======================================================================
// Freigaben

void freigabenTests() {
  pruefung('MOB-096 Gäste-Beiträge annehmen und ablehnen', (tester) async {
    final k = await kontoMitFotos('K096', 1);
    final album = await _albumMit(k.konto, 'Gaestealbum', k.ids);
    final f = await k.v.schicke('api/v1/freigaben', {
      'titel': 'Gaestealbum',
      'album': album,
      'tage': 7,
      'herunterladen': false,
      'hochladen': true,
    });
    final kennung = Uri.parse('${f['link']}').pathSegments.last;
    for (final n in ['gast1.jpg', 'gast2.jpg']) {
      final r = await http.post(
        hauptDirekt.resolve('api/v1/teilen/$kennung/beitrag?name=$n&von=Gast'),
        headers: {
          'x-pv-teilen': '1',
          'content-type': 'application/octet-stream',
        },
        body: jpeg(datum: DateTime(2025, 1, 1)),
      );
      expect(r.statusCode, lessThan(300), reason: 'Gast lädt hoch: ${r.body}');
    }
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    expect(rasterIds(tester), hasLength(1), reason: 'nicht in der Zeitleiste');
    expect(await app.sitzung.db.watchAlbumAssets(album).first, hasLength(1));
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text('Gaestealbum'));
    await warte(
      tester,
      find.textContaining(de.linkBeitraegeOffen(2)),
      max: const Duration(seconds: 40),
    );
    await tippe(tester, find.textContaining(de.linkBeitraegeOffen(2)));
    await warte(tester, find.text(de.beitraegeTitel));
    await warteBis(
      tester,
      () => find.byTooltip(de.beitraegeAnnehmen).evaluate().length == 2,
      max: const Duration(seconds: 120),
      grund: 'beide geprüft und annehmbar',
    );
    expect(find.textContaining('eigenen Prozess'), findsOneWidget);
    expect(find.textContaining(de.beitraegeVon('Gast')), findsWidgets);
    expect(find.text(de.beitraegeAlleAnnehmen), findsOneWidget);
    await tippe(tester, find.byTooltip(de.beitraegeAnnehmen).first, ms: 1500);
    await meldung(tester, de.beitraegeAngenommen(1));
    await warteBis(
      tester,
      () => find.byTooltip(de.beitraegeAnnehmen).evaluate().length == 1,
      grund: 'einer angenommen',
    );
    await tippe(tester, find.byTooltip(de.beitraegeAblehnen).first, ms: 2000);
    await warteBis(
      tester,
      () => find.byTooltip(de.beitraegeAblehnen).evaluate().isEmpty,
      grund: 'abgelehnter verschwindet',
    );
    await app.sitzung.gleicheAb();
    final imAlbum = await app.sitzung.db.watchAlbumAssets(album).first;
    print('MOB-096 im Album: ${imAlbum.map((a) => a.originalFileName)}');
    expect(imAlbum, hasLength(2));
    final offen = await k.v.hole('api/v1/beitraege');
    print('MOB-096 offen am Server: $offen');
  });

  pruefung('MOB-099 Konto B trägt bei: ohne Zugriff, Fortschritt, ohne Server', (
    tester,
  ) async {
    await inMediathek(3, praefix: 'r2_099');
    final a = await kontoMitFotos('K099A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K099B');
    final album = await _albumMit(a.konto, 'Beitragsalbum', a.ids);
    await albumTeilen(a.v, album, b, beitragen: true);
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Beitragsalbum'));
    await tippe(tester, find.text('Beitragsalbum'), ms: 2000);
    final pm = PhotoManagerAttrappe()
      ..antworten['requestPermissionExtend'] = ((_) => 2)
      ..an();
    addTearDown(pm.aus);
    await tippe(tester, tooltip(tt.geteiltHinzufuegen), ms: 800);
    await meldung(tester, de.fotosKeinZugriff);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(de.fotosEinstellungen),
      ),
      findsOneWidget,
    );
    pm.aus();
    await meldungenWeg(tester);
    for (
      var v = 0;
      v < 3 && find.text(de.fotosWaehlen).evaluate().isEmpty;
      v++
    ) {
      await tippe(tester, tooltip(tt.geteiltHinzufuegen), ms: 2500);
      await ruhe(tester, 2000);
    }
    await warte(
      tester,
      find.text(de.fotosWaehlen),
      max: const Duration(seconds: 30),
    );
    final bilder = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onTap != null,
    );
    await warteBis(
      tester,
      () => bilder.evaluate().length >= 3,
      grund: 'Mediathek',
    );
    await tippe(tester, bilder.at(0));
    await tippe(tester, bilder.at(1));
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    await proxyRegel({
      'muster': r'^/api/v1/geteilt/.+/beitrag',
      'verzoegerung': 3,
    });
    await tippe(tester, find.text(de.fotosHinzufuegen(2)), ms: 200);
    await warte(
      tester,
      find.text(tt.geteiltLaedtHoch(1, 2)),
      max: const Duration(seconds: 20),
    );
    await meldung(
      tester,
      tt.geteiltHinzugefuegt(2),
      max: const Duration(seconds: 90),
    );
    await proxyZuruecksetzen();
    final kacheln3 = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'GeteiltesAlbumSeite',
      ),
      matching: find.byType(GestureDetector),
    );
    await warteBis(
      tester,
      () => kacheln3.evaluate().length >= 3,
      max: const Duration(seconds: 30),
      grund: 'Album lädt neu',
    );
    var beigetragen = 0;
    for (var i = 0; i < 3; i++) {
      await tippe(tester, kacheln3.at(i), ms: 1500);
      if (find.text(tt.geteiltBeigetragenVon(b)).evaluate().isNotEmpty) {
        beigetragen++;
      }
      await schliesse(tester);
    }
    print(
      'MOB-099 „Beigetragen von $b“ bei $beigetragen von 3 (nur im Betrachter)',
    );
    expect(beigetragen, 2);
    // Server weg während des dritten Uploads.
    await meldungenWeg(tester);
    await tippe(tester, tooltip(tt.geteiltHinzufuegen), ms: 2500);
    await warte(
      tester,
      find.text(de.fotosWaehlen),
      max: const Duration(seconds: 30),
    );
    await warteBis(
      tester,
      () => bilder.evaluate().length >= 3,
      grund: 'Mediathek',
    );
    await tippe(tester, bilder.at(2));
    await proxyRegel({
      'muster': r'^/api/v1/geteilt/.+/beitrag',
      'abbrechen': true,
    });
    await tippe(tester, find.text(de.fotosHinzufuegen(1)), ms: 500);
    await meldung(tester, tt.geteiltOffline, max: const Duration(seconds: 60));
  });

  pruefung('MOB-106 Partnerfotos: Marke, Reihenfolge, Ausschalten', (
    tester,
  ) async {
    final a = await kontoMitFotos('K106A', 2);
    final b = await kontoMitFotos('K106B', 1, ab: DateTime(2024, 6, 20, 11));
    final idB = await kontoId(a.v, b.konto);
    expect((await a.v.anfrage('PUT', 'api/v1/partner/$idB')).statusCode, 204);
    final app = await starteApp(tester, server: hauptApp, konto: b.konto);
    await warteAufKacheln(tester, 1);
    Future<void> schalten() async {
      await bereich(tester, de.navAlben);
      await rolleZu(tester, find.text(tt.partnerBibliothekVon(a.konto)));
      await tippe(
        tester,
        find.text(tt.partnerBibliothekVon(a.konto)),
        ms: 2000,
      );
      await tippe(tester, find.byType(PopupMenuButton<void>), ms: 800);
      await tippe(tester, find.text(tt.partnerInZeitleiste), ms: 2000);
      await schliesse(tester);
      await bereich(tester, de.navZeitleiste);
      await app.sitzung.ladePartnerfotos();
    }

    await schalten();
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      max: const Duration(seconds: 30),
      grund: 'Partnerfotos',
    );
    final ids = rasterIds(tester);
    expect(ids.last, b.ids[0], reason: 'nach Datum');
    final marke = find.descendant(
      of: find.byTooltip(a.konto),
      matching: find.text('K'),
    );
    print('MOB-106 Marken „K“: ${marke.evaluate().length}');
    expect(marke, findsNWidgets(2));
    await lang(tester, kacheln().at(0));
    expect(
      find.text(de.auswahlAnzahl(1)),
      findsNothing,
      reason: 'nicht wählbar',
    );
    await tippe(tester, kacheln().at(0), ms: 1500);
    final betrachter = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'GeteilterBetrachter',
    );
    expect(betrachter, findsOneWidget);
    final seiten = (tester.widget(betrachter) as dynamic);
    try {
      print(
        'MOB-106 Betrachter zeigt ${(seiten.aufnahmen as List).length} Aufnahmen',
      );
    } catch (_) {}
    await schliesse(tester);
    await tippe(tester, tooltip(de.ansichtReihenfolge));
    await tippe(tester, find.text(de.sortName).last, ms: 1000);
    expect(rasterIds(tester), [b.ids[0]], reason: 'andere Reihenfolge: weg');
    await tippe(tester, tooltip(de.ansichtReihenfolge));
    await tippe(tester, find.text(de.sortAufnahmeNeu).last, ms: 1000);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      grund: 'wieder da',
    );
    await schalten();
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      max: const Duration(seconds: 30),
      grund: 'nach dem Ausschalten weg',
    );
    expect(rasterIds(tester), [b.ids[0]]);
  });

  // Behoben in #418: Der Nachlass zeigt den Grund des Servers
  // (teilenFehlertext), nicht seine rohe Antwort.
  pruefung('MOB-107 Nachlass: ablehnen, erneut verlangen, Frist läuft ab', (
    tester,
  ) async {
    final a = await kontoMitFotos('K107A', 2);
    final b = await kontoAnlegen(hauptDirekt, 'K107B');
    final serverDb = '${serverDaten('mob-haupt')}/server.sqlite';
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(tt.nachlass));
    await tippe(tester, find.text(tt.nachlass), ms: 1500);
    await waehleKonto(tester, await kontoId(a.v, b));
    final frist = find.byWidgetPredicate((w) => w is DropdownButton<int>);
    if (frist.evaluate().isNotEmpty) {
      tester.widget<DropdownButton<int>>(frist.first).onChanged!(7);
      await ruhe(tester, 600);
    }
    await tippe(tester, find.text(tt.nachlassBenennen), ms: 1500);
    await warte(tester, find.text(b));
    Future<void> verlangen() async {
      await starteApp(tester, server: hauptApp, konto: b);
      await kontoOeffnen(tester);
      await rolleZu(tester, find.text(tt.nachlass));
      await tippe(tester, find.text(tt.nachlass), ms: 1500);
      await warte(tester, find.text(tt.nachlassFuerMich));
      await tippe(tester, find.text(tt.nachlassVerlangen));
      await tippe(tester, find.text(tt.nachlassVerlangen).last, ms: 2000);
    }

    await verlangen();
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await warte(
      tester,
      find.textContaining('verlangt Zugang zu deiner Bibliothek'),
      max: const Duration(seconds: 30),
    );
    final banner = sichtbareTexte(
      tester,
    ).firstWhere((t) => t.contains('verlangt Zugang'));
    print('MOB-107 Hinweis bei A: $banner');
    expect(banner, contains(b));
    expect(banner, contains('Ohne Widerspruch bekommt'));
    await tippe(tester, find.text(tt.nachlassAblehnen), ms: 1500);
    await warteWeg(
      tester,
      find.textContaining('verlangt Zugang zu deiner Bibliothek'),
    );
    // Gleich wieder verlangen: was zeigt die App?
    await verlangen();
    await ruhe(tester, 1500);
    final sofort = sichtbareTexte(tester)
        .where(
          (t) =>
              t.contains('fehler') ||
              t.contains('abgelehnt') ||
              t.contains('später'),
        )
        .toList();
    print('MOB-107 sofort erneut: $sofort');
    // Die Pause nach dem Widerspruch und dann die Frist in der Wegwerf-DB
    // verstreichen lassen (Systemzeit bleibt).
    final ida = await eigeneKontoId(a.v);
    await sql(
      serverDb,
      'UPDATE nachlass SET abgelehnt = abgelehnt - 8*86400000 WHERE besitzer = ? AND abgelehnt IS NOT NULL',
      [ida],
    );
    await verlangen();
    final zeile = await sql(
      serverDb,
      'SELECT frist_tage, angefordert, abgelehnt FROM nachlass WHERE besitzer = ?',
      [ida],
    );
    print('MOB-107 Anfrage am Server: $zeile');
    expect(zeile.single[1], isNotNull, reason: 'erneut verlangt');
    await sql(
      serverDb,
      'UPDATE nachlass SET angefordert = angefordert - (frist_tage + 1)*86400000 WHERE besitzer = ?',
      [ida],
    );
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(
      tester,
      find.text(tt.partnerBibliothekVon(a.konto)),
      schritt: 200,
    );
    expect(find.text(tt.partnerGanzeBibliothek), findsOneWidget);
    await tippe(tester, find.text(tt.partnerBibliothekVon(a.konto)), ms: 2500);
    await tippe(tester, find.byType(PopupMenuButton<void>), ms: 800);
    final menue = [
      for (final t in tester.widgetList<Text>(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is PopupMenuEntry),
          matching: find.byType(Text),
        ),
      ))
        t.data ?? '',
    ];
    print('MOB-107 Menü bei B (nur ansehen): $menue');
    expect(menue, hasLength(2));
    expect(
      sofort.where((t) => t.trimLeft().startsWith('{')),
      isEmpty,
      reason: 'verständliche Meldung statt JSON',
    );
    expect(sofort, isNotEmpty, reason: 'eine Meldung steht da');
  });
}

// ======================================================================
// Suche

void sucheTests() {
  // Behoben in #418: Der Knopf neben der Filterzeile sucht wie
  // „Zurücksetzen“ im Filterblatt neu und leert ohne Suchtext alles.
  pruefung('MOB-115 Filter der Suche: alle zusammen, Videos, Zurücksetzen', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K115');
    final v = await api(hauptDirekt, konto);
    final h = DateTime.now();
    final gestern = DateTime(h.year, h.month, h.day - 1, 12);
    Uint8List foto({
      DateTime? datum,
      String modell = 'FilterModell',
      String? make = 'Filtermake',
    }) => jpeg(
      datum: datum ?? gestern,
      kamera: make,
      modell: modell,
      breite: 320,
      hoehe: 240,
    );
    final ziel = await hochladen(v, foto(), 'ziel_115.jpg');
    final nurA = await hochladen(v, foto(), 'nur_a_115.jpg');
    final andereStadt = await hochladen(v, foto(), 'stadt_115.jpg');
    final altesJahr = await hochladen(
      v,
      foto(datum: DateTime(h.year - 1, 3, 3)),
      'alt_115.jpg',
    );
    final andereKamera = await hochladen(
      v,
      foto(modell: 'Anderes'),
      'kamera_115.jpg',
    );
    final empfangen = await hochladen(v, foto(), 'IMG-20261105-WA0001.jpg');
    final keinFavorit = await hochladen(v, foto(), 'kein_fav_115.jpg');
    final imAlbum = await hochladen(v, foto(), 'album_115.jpg');
    final video = await hochladenDatei(v, 'video_5s.mp4');
    final video2 = await hochladen(
      v,
      Uint8List.fromList(
        await macDatei(p.join(fixturesOrdner, 'video_hoch_3s.mov')),
      ),
      'video2_115.mov',
    );
    final pa = await person(hauptDirekt, konto, 'Person A');
    final pb = await person(hauptDirekt, konto, 'Person B');
    final alle = [
      ziel,
      nurA,
      andereStadt,
      altesJahr,
      andereKamera,
      empfangen,
      keinFavorit,
      imAlbum,
    ];
    for (final id in alle) {
      await gesicht(v, id, personId: pa, kasten: const [0.05, 0.1, 0.3, 0.4]);
      if (id != nurA) {
        await gesicht(v, id, personId: pb, kasten: const [0.6, 0.1, 0.3, 0.4]);
      }
    }
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(
        OrtSetzen(
          [
            for (final x in alle)
              if (x != andereStadt) x,
          ],
          50.1,
          8.6,
          land: 'Germany',
          stadt: 'Musterstadt',
        ),
      );
      await r.tue(
        OrtSetzen(
          [andereStadt],
          48.5,
          11.2,
          land: 'Germany',
          stadt: 'Beispielhausen',
        ),
      );
      await r.tue(
        FavoritSetzen([
          for (final x in alle)
            if (x != keinFavorit) x,
          video,
        ], true),
      );
      final al = uuid();
      await r.tue(AlbumAnlegen(al, 'Filteralbum', DateTime.now()));
      await r.tue(AlbumFuellen(al, [imAlbum]));
      await r.tue(
        AufnahmedatenSetzen([
          (id: video, zeitpunkt: gestern, geschaetzt: false),
          (id: video2, zeitpunkt: gestern, geschaetzt: false),
        ]),
      );
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 4);
    await bereich(tester, de.navSuche);
    await tippe(tester, tooltip(de.sucheFilter), ms: 1500);
    final blatt = find.byType(BottomSheet);
    await warte(
      tester,
      find.descendant(of: blatt, matching: find.text(de.sucheFilterPersonen)),
    );
    await tippe(tester, find.widgetWithText(FilterChip, 'Person A'));
    await tippe(tester, find.widgetWithText(FilterChip, 'Person B'));
    final dd = find.descendant(
      of: blatt,
      matching: find.byWidgetPredicate((w) => w is DropdownButton),
    );
    (tester.widget(dd.at(0)) as dynamic).onChanged('Germany');
    await ruhe(tester, 600);
    (tester.widget(dd.at(1)) as dynamic).onChanged('Musterstadt');
    await ruhe(tester, 600);
    // Zeitraum: vom Ersten des Monats bis heute (Kalender des Systems).
    await tippe(
      tester,
      find.descendant(of: blatt, matching: find.text(de.sucheFilterVon)),
    );
    await tippe(
      tester,
      find
          .descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('1'),
          )
          .first,
    );
    await tippe(
      tester,
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('OK'),
      ),
      ms: 800,
    );
    await tippe(
      tester,
      find.descendant(of: blatt, matching: find.text(de.sucheFilterBis)),
    );
    await tippe(
      tester,
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('OK'),
      ),
      ms: 800,
    );
    final segment = find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('SegmentedButton'),
    );
    await rolleZu(
      tester,
      segment,
      in_: find.descendant(of: blatt, matching: find.byType(Scrollable)).first,
    );
    await tippe(
      tester,
      find.descendant(of: segment, matching: find.text(de.sucheFilterFotos)),
    );
    await rolleZu(
      tester,
      find.text(de.sucheFilterOhneAlbum),
      in_: find.descendant(of: blatt, matching: find.byType(Scrollable)).first,
    );
    final dd2 = find.descendant(
      of: blatt,
      matching: find.byWidgetPredicate((w) => w is DropdownButton),
    );
    print('MOB-115 Auswahlfelder: ${dd2.evaluate().length}');
    (tester.widget(dd2.at(2)) as dynamic).onChanged('FilterModell');
    await ruhe(tester, 400);
    (tester.widget(dd2.at(3)) as dynamic).onChanged(Aufnahmeherkunft.kamera);
    await ruhe(tester, 400);
    await tippe(
      tester,
      find.widgetWithText(SwitchListTile, de.sucheFilterFavoriten),
    );
    await tippe(
      tester,
      find.widgetWithText(SwitchListTile, de.sucheFilterOhneAlbum),
    );
    await tippe(tester, find.text(de.sucheFilterAnwenden), ms: 3000);
    await warte(tester, find.textContaining('Filter: '));
    final zeile = sichtbareTexte(
      tester,
    ).firstWhere((t) => t.startsWith('Filter: '));
    print('MOB-115 $zeile');
    for (final teil in [
      'Person A',
      'Person B',
      'Musterstadt',
      'FilterModell',
      de.bibFavoriten,
    ]) {
      expect(zeile, contains(teil));
    }
    await warteBis(
      tester,
      () => find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'AufnahmenRaster',
          )
          .evaluate()
          .isNotEmpty,
      grund: 'Treffer',
    );
    final treffer = rasterIds(tester);
    print('MOB-115 Treffer: $treffer (Ziel $ziel)');
    expect(treffer, [ziel], reason: 'nur das, was alle Filter erfüllt');
    // Nur Videos + Favoriten.
    await tippe(tester, tooltip(de.sucheFilter), ms: 1500);
    await tippe(
      tester,
      find.descendant(
        of: blatt,
        matching: find.text(de.sucheFilterZuruecksetzen),
      ),
      ms: 2000,
    );
    await ruhe(tester, 1000);
    final nachReset = sichtbareTexte(tester);
    print('MOB-115 nach Zurücksetzen: ${nachReset.take(12)}');
    expect(find.textContaining('Filter: '), findsNothing);
    expect(
      find.text(de.sucheTextOderFilter),
      findsOneWidget,
      reason: 'leert alles',
    );
    await tippe(tester, tooltip(de.sucheFilter), ms: 1500);
    await rolleZu(
      tester,
      segment,
      in_: find.descendant(of: blatt, matching: find.byType(Scrollable)).first,
    );
    await tippe(
      tester,
      find.descendant(of: segment, matching: find.text(de.sucheFilterVideos)),
    );
    await rolleZu(
      tester,
      find.text(de.sucheFilterFavoriten),
      in_: find.descendant(of: blatt, matching: find.byType(Scrollable)).first,
    );
    await tippe(
      tester,
      find.widgetWithText(SwitchListTile, de.sucheFilterFavoriten),
    );
    await tippe(tester, find.text(de.sucheFilterAnwenden), ms: 3000);
    await warteBis(
      tester,
      () => find
          .byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'AufnahmenRaster',
          )
          .evaluate()
          .isNotEmpty,
      grund: 'Treffer Videos',
    );
    expect(rasterIds(tester), [video]);
    // Der Knopf neben der Filterzeile.
    final knopf = find.descendant(
      of: find
          .ancestor(
            of: find.textContaining('Filter: '),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(IconButton),
    );
    final knopfDa = knopf.evaluate().isNotEmpty;
    if (knopfDa) {
      await tippe(tester, knopf.first, ms: 1500);
      final raster = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'AufnahmenRaster',
      );
      print(
        'MOB-115 Knopf an der Filterzeile: Filterzeile ${find.textContaining('Filter: ').evaluate().length}, '
        'Treffer danach ${raster.evaluate().isEmpty ? '-' : rasterIds(tester)}',
      );
      expect(
        find.text(de.sucheTextOderFilter),
        findsOneWidget,
        reason: '„Zurücksetzen“ an der Filterzeile leert alles',
      );
    }
    expect(knopfDa, isTrue, reason: 'Knopf an der Filterzeile');
  });
}

// ignore_for_file: avoid_print
part of 'katalog_mob_r2_test.dart';

// ======================================================================
// Sicherung der Kamerarolle

Future<void> _sichernBisFertig(WidgetTester tester, App app) async {
  final alle = await mediathekAnzahl();
  await sicherungsseite(tester);
  await schalter(tester, de.sicherungAn, true);
  await warteBis(
    tester,
    () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
    max: const Duration(minutes: 5),
    grund: 'erster Lauf',
  );
  await app.sitzung.gleicheAb();
}

/// Kennung am Server zu den Fotos des Telefons [lokal].
Future<Map<String, String>> _amServerAls(
  App app,
  List<AssetEntity> lokal,
) async {
  final d = app.sitzung.sicherung!;
  final zu = <String, String>{};
  for (final z
      in await app.sitzung.db.customSelect('SELECT id FROM assets').get()) {
    final id = z.read<String>('id');
    final g = d.gesichertAls(id);
    if (g != null) zu[g.lokal] = id;
  }
  return {
    for (final e in lokal)
      if (zu[e.id] != null) e.id: zu[e.id]!,
  };
}

Finder get _lokaleKachel => find.byWidgetPredicate(
  (w) =>
      w.runtimeType.toString() == 'Miniatur' &&
      (((w as dynamic).zeile?.id as String?)?.startsWith('lokal:') ?? false),
);

void sicherungTests() {
  // Befund: Ist die Sicherung aus, meldet die Sicherungsseite die Abmeldung
  // nicht (2× nachgestellt): apps/mobil/lib/seiten/sicherung.dart:122 baut
  // den Stand nur bei eingeschalteter Sicherung, und der Hinweis (:309-317)
  // kommt nur aus `dienst.fehler`, also erst nach einem Lauf mit 401. Mit
  // eingeschalteter Sicherung erscheint er (grün), ebenso oben in der App.
  pruefung('MOB-021 Abgemeldet: Hinweis oben und auf der Sicherungsseite', (
    tester,
  ) async {
    final befunde = <String>[];
    for (var lauf = 0; lauf < 2; lauf++) {
      final k = await kontoMitFotos('K021', 2);
      final app = await starteApp(tester, server: hauptApp, konto: k.konto);
      await warteAufKacheln(tester, 2);
      final mitSicherung = lauf == 1;
      if (mitSicherung) {
        await _sichernBisFertig(tester, app);
        await zurueck(tester);
        await zurueck(tester);
      }
      final g = (await k.v.hole('api/v1/geraete'))['geraete']! as List;
      final telefon = g.cast<Map>().firstWhere((x) => x['name'] == 'Telefon');
      expect(
        (await k.v.anfrage(
          'DELETE',
          'api/v1/geraete/${telefon['id']}',
        )).statusCode,
        lessThan(300),
      );
      await nachUntenZiehen(tester);
      app.sitzung.abgleich?.jetzt();
      await warte(
        tester,
        find.text(de.abgemeldetHinweis),
        max: const Duration(seconds: 60),
      );
      await warteAufKacheln(tester, 2);
      if (mitSicherung) await inMediathek(1, praefix: 'r2_021');
      await sicherungsseite(tester);
      await ruhe(tester, 8000);
      final da = find.text(de.abgemeldetHinweis).evaluate().isNotEmpty;
      befunde.add(
        '${mitSicherung ? 'Sicherung an' : 'Sicherung aus'}: Hinweis auf der Sicherungsseite $da',
      );
      if (mitSicherung) {
        await rolleZu(tester, find.text(de.sicherungJetzt));
        await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
        await warte(
          tester,
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(de.abgemeldetHinweis),
          ),
          max: const Duration(seconds: 30),
        );
        befunde.add('Jetzt sichern: Meldung abgemeldet');
      }
      await zurueck(tester);
      await zurueck(tester);
    }
    print('MOB-021 $befunde');
    expect(
      befunde.where((b) => b.endsWith('false')),
      isEmpty,
      reason: 'Sicherungsseite meldet die Abmeldung',
    );
  }, skip: true);

  pruefung(
    'MOB-042 MOB-185 MOB-186 Vom Telefon löschen (Systemrückfrage nachgestellt)',
    (tester) async {
      final konto = await kontoAnlegen(hauptDirekt, 'K042');
      final neu = await inMediathek(7, praefix: 'r2_042');
      final app = await starteApp(tester, server: hauptApp, konto: konto);
      await _sichernBisFertig(tester, app);
      final s = await _amServerAls(app, neu);
      expect(s, hasLength(7));
      final [p1, p2, p3, p4, a, x, c] = neu;
      final pm = PhotoManagerAttrappe()..an();
      addTearDown(pm.aus);
      // MOB-186: X am „Rechner“ in den Papierkorb.
      await mitRechner(
        hauptDirekt,
        konto,
        (r) => r.tue(InDenPapierkorb([s[x.id]!])),
      );
      await app.sitzung.gleicheAb();
      await rolleZu(tester, find.text(de.sicherungPapierkorbTelefon));
      pm.loeschenAntwort(bestaetigt: true);
      await tippe(tester, find.text(de.sicherungPapierkorbTelefon), ms: 2000);
      await warte(tester, find.text(de.sicherungFreigebenTitel(1)));
      expect(find.text(de.sicherungPapierkorbTelefonText), findsOneWidget);
      await tippe(
        tester,
        find.text(de.sicherungFreigebenLoeschen).last,
        ms: 2000,
      );
      await meldung(tester, de.vomTelefonGeloescht(1));
      expect(pm.geloescht.last, [
        x.id,
      ], reason: 'nur das Foto aus dem Papierkorb');
      await meldungenWeg(tester);
      await mitRechner(
        hauptDirekt,
        konto,
        (r) => r.tue(AusDemPapierkorb([s[x.id]!])),
      );
      await app.sitzung.gleicheAb();
      await tippe(tester, find.text(de.sicherungPapierkorbTelefon), ms: 2000);
      await warte(
        tester,
        find.textContaining(de.sicherungPapierkorbTelefonNichts),
      );
      await meldungenWeg(tester);
      // MOB-042: zwei gesicherte Fotos in der Zeitleiste in den Papierkorb.
      await zurueck(tester);
      await zurueck(tester);
      await rolleZu(tester, kachelVon(s[p1.id]!));
      await lang(tester, kachelVon(s[p1.id]!));
      await tippe(tester, kachelVon(s[p2.id]!));
      await tippe(tester, aktion(de.auswahlPapierkorb), ms: 1500);
      final haken = find.byType(CheckboxListTile);
      await warte(tester, haken);
      expect(find.text(de.loeschenAuchTelefon(2)), findsOneWidget);
      expect(find.text(de.loeschenAuchTelefonHinweisIos), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(haken).value,
        app.sitzung.sicherung!.einstellungen.vomTelefon,
      );
      expect(tester.widget<CheckboxListTile>(haken).value, isTrue);
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.betrachterPapierkorb),
        ms: 2000,
      );
      await meldung(tester, de.vomTelefonGeloescht(2));
      expect(pm.geloescht.last.toSet(), {p1.id, p2.id});
      await meldungenWeg(tester);
      // Häkchen entfernen: gemerkt.
      await rolleZu(tester, kachelVon(s[p3.id]!));
      await lang(tester, kachelVon(s[p3.id]!));
      await tippe(tester, aktion(de.auswahlPapierkorb), ms: 1500);
      await tippe(tester, haken);
      expect(tester.widget<CheckboxListTile>(haken).value, isFalse);
      final n0 = pm.geloescht.length;
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.betrachterPapierkorb),
        ms: 2000,
      );
      expect(pm.geloescht.length, n0, reason: 'nichts vom Telefon');
      expect(app.sitzung.sicherung!.einstellungen.vomTelefon, isFalse);
      await meldungenWeg(tester);
      await rolleZu(tester, kachelVon(s[p4.id]!));
      await lang(tester, kachelVon(s[p4.id]!));
      await tippe(tester, aktion(de.auswahlPapierkorb), ms: 1500);
      expect(
        tester.widget<CheckboxListTile>(haken).value,
        isFalse,
        reason: 'letzte Wahl vorbelegt',
      );
      // Ablehnen der Systemrückfrage.
      await tippe(tester, haken);
      pm.loeschenAntwort(bestaetigt: false);
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.betrachterPapierkorb),
        ms: 2000,
      );
      await meldung(tester, de.vomTelefonGeloescht(0));
      await meldungenWeg(tester);
      // MOB-185: Speicher freigeben. C am Rechner in den Papierkorb, D neu
      // und ungesichert (Server aus).
      await mitRechner(
        hauptDirekt,
        konto,
        (r) => r.tue(InDenPapierkorb([s[c.id]!])),
      );
      await app.sitzung.gleicheAb();
      await proxyAus();
      final [d] = await inMediathek(1, praefix: 'r2_185_d');
      await ruhe(tester, 5000);
      await sicherungsseite(tester);
      pm.loeschenAntwort(bestaetigt: true);
      await rolleZu(tester, find.text(de.sicherungFreigeben));
      await tester.tap(find.text(de.sicherungFreigeben));
      var sucht = false;
      for (
        var i = 0;
        i < 30 && find.byType(AlertDialog).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        sucht =
            sucht ||
            find.text(de.sicherungFreigebenSucht).evaluate().isNotEmpty;
      }
      await warte(
        tester,
        find.byType(AlertDialog),
        max: const Duration(seconds: 30),
      );
      final titel = sichtbareTexte(
        tester,
      ).firstWhere((t) => t.contains('vom Telefon löschen?'));
      print('MOB-185 „Sucht …“ gesehen: $sucht; Rückfrage: $titel');
      expect(find.text(de.sicherungFreigebenText), findsOneWidget);
      await tippe(
        tester,
        find.text(de.sicherungFreigebenLoeschen).last,
        ms: 2000,
      );
      final weg = pm.geloescht.last.toSet();
      print('MOB-185 freigegeben: ${weg.length} Fotos');
      expect(
        weg,
        containsAll([a.id, x.id]),
        reason: 'unverändert und sicher auf dem Server',
      );
      for (final e in [p1, p2, p3, p4, c, d]) {
        expect(
          weg.contains(e.id),
          isFalse,
          reason: '${e.id} bleibt (Papierkorb oder ungesichert)',
        );
      }
      await meldung(tester, de.sicherungFreigegeben(weg.length));
      await proxyAn();
      final amA = await amServer(hauptDirekt, konto, s[a.id]!);
      expect(amA?.isTrashed, isFalse, reason: 'am Server bleibt A');
      expect(sucht, isTrue, reason: '„Sucht gesicherte Aufnahmen …“');
    },
  );

  pruefung('MOB-179 Videos sichern: aus, dann wieder an', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K179');
    await PhotoManager.editor.saveVideo(
      File('$fixturesOrdner/video_5s.mp4'),
      title: 'r2_179_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await inMediathek(1, praefix: 'r2_179');
    final videos = await PhotoManager.getAssetCount(type: RequestType.video);
    final alle = await mediathekAnzahl();
    await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungVideos, false);
    await rolleZu(tester, find.text(de.sicherungAn), schritt: -250);
    await schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () async => await serverAnzahl(konto) >= alle - videos,
      max: const Duration(minutes: 5),
      grund: 'Fotos oben',
    );
    await ruhe(tester, 4000);
    expect(await serverAnzahl(konto), alle - videos, reason: 'Videos bleiben');
    await zurueck(tester);
    await zurueck(tester);
    await warte(
      tester,
      find.text(de.lokalAnzahl(videos)),
      max: const Duration(seconds: 40),
    );
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungVideos, true);
    await meldungenWeg(tester);
    // „Jetzt sichern“ oben in der Zeitleiste (die Zeile „N nur auf dem
    // Telefon“); auf der Sicherungsseite fand rolleZu den Knopf nicht.
    await zurueck(tester);
    await zurueck(tester);
    await warte(tester, find.text(de.lokalJetztSichern));
    await tippe(tester, find.text(de.lokalJetztSichern).first, ms: 300);
    final m = await meldungenBis(
      tester,
      de.jetztGesichert(videos),
      max: const Duration(minutes: 3),
    );
    final d = _laufendeSitzung(tester).sicherung!;
    print(
      'MOB-179 Meldungen: $m; fehlgeschlagen ${d.fehlgeschlagen}; '
      'abgelehnt ${d.abgelehntGruende}; letzter Lauf offen ${d.letzterLauf?.offen}',
    );
    expect(m, contains(de.jetztGesichert(videos)));
    expect(await serverAnzahl(konto), alle);
  });

  pruefung('MOB-183 MOB-189 „Jetzt sichern“: Ausgänge; neue Fotos gleich', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K183');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteBis(
      tester,
      () => app.sitzung.sicherung != null,
      grund: 'Sicherungsdienst',
    );
    // Schritt 1: Ohne Sicherung gibt es keinen Knopf „Jetzt sichern“.
    final knopfZeitleiste = find
        .text(de.lokalJetztSichern)
        .evaluate()
        .isNotEmpty;
    await sicherungsseite(tester);
    final knopfSeite = find.text(de.sicherungJetzt).evaluate().isNotEmpty;
    print(
      'MOB-183 Sicherung aus: Knopf in der Zeitleiste $knopfZeitleiste, auf der Seite $knopfSeite',
    );
    // Die Meldung selbst (über die Funktion des Knopfs).
    unawaited(jetztSichernFuer(tester, app));
    await meldung(tester, de.jetztAus);
    await tippe(
      tester,
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(de.jetztEinrichten),
      ),
      ms: 1500,
    );
    expect(
      find.text(de.sicherungAn),
      findsWidgets,
      reason: '„Einrichten“ öffnet die Sicherungsseite',
    );
    await meldungenWeg(tester);
    final alle = await mediathekAnzahl();
    await schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
      max: const Duration(minutes: 5),
      grund: 'erster Lauf',
    );
    await ruhe(tester, 3000);
    // MOB-189: drei Fotos kurz hintereinander, ohne Bedienung.
    final vorher = await serverAnzahl(konto);
    await proxyLogLeeren();
    await inMediathek(3, praefix: 'r2_189');
    final t0 = DateTime.now();
    await warteBis(
      tester,
      () async => await serverAnzahl(konto) >= vorher + 3,
      max: const Duration(seconds: 30),
      grund: 'drei neue von selbst',
    );
    final dauer = DateTime.now().difference(t0);
    final hoch = [
      for (final x in await proxyPfade())
        if (x == 'POST /api/v1/hochladen') x,
    ];
    print(
      'MOB-189 nach ${dauer.inSeconds} s auf dem Server, Uploads ${hoch.length}',
    );
    expect(hoch, hasLength(3));
    // Drei neue „Jetzt sichern“: Den Lauf von selbst lässt der Proxy an den
    // Prüfsummen scheitern (503), damit die drei bis zum Tipp offen bleiben.
    // (Mit ausgeschaltetem Server waren sie beim Tipp schon oben.)
    await proxyRegel({
      'methode': 'POST',
      'muster': r'^/api/v1/pruefsummen',
      'status': 503,
      'body': {'fehler': 'Pruefung'},
    });
    await inMediathek(3, praefix: 'r2_183');
    await ruhe(tester, 8000);
    await proxyZuruecksetzen();
    await meldungenWeg(tester);
    await ruhe(tester, 1500);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    final knopf = find.ancestor(
      of: find.text(de.sicherungJetzt),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    print(
      'MOB-183 Knopf aktiv: ${knopf.evaluate().isEmpty ? '?' : tester.widget<ButtonStyleButton>(knopf.first).onPressed != null}, '
      'Dienst läuft ${app.sitzung.sicherung!.laeuft}, ungesichert ${app.sitzung.sicherung!.ungesichert?.length}',
    );
    await tippe(tester, find.text(de.sicherungJetzt), ms: 100);
    final m3 = await meldungenBis(tester, de.jetztGesichert(3));
    print('MOB-183 Meldungen nach „Jetzt sichern“ mit 3 neuen: $m3');
    expect(m3, contains(de.jetztGesichert(3)));
    await meldungenWeg(tester);
    await rolleBis(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await meldung(
      tester,
      de.jetztAllesSicher,
      max: const Duration(seconds: 60),
    );
    await meldungenWeg(tester);
    // Eines scheitert.
    await proxyRegel({
      'methode': 'POST',
      'muster': r'^/api/v1/pruefsummen',
      'status': 503,
      'body': {'fehler': 'Pruefung'},
    });
    await inMediathek(3, praefix: 'r2_183f');
    await ruhe(tester, 8000);
    await proxyZuruecksetzen();
    await meldungenWeg(tester);
    await proxyRegel({
      'methode': 'POST',
      'muster': r'^/api/v1/hochladen$',
      'status': 500,
      'body': {'fehler': 'Pruefung'},
      'einmal': true,
    });
    await rolleBis(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await meldung(
      tester,
      de.jetztTeils(2, 1),
      max: const Duration(seconds: 90),
    );
    await tippe(
      tester,
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(de.jetztDetails),
      ),
      ms: 1500,
    );
    await rolleZu(tester, find.text(de.sicherungProbleme(1)));
    await meldungenWeg(tester);
    // Server weg, Netz da: was meldet „Jetzt sichern“?
    await proxyAus();
    await inMediathek(1, praefix: 'r2_183o');
    await ruhe(tester, 5000);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await rolleBis(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await ruhe(tester, 6000);
    final ohne = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      ))
        t.data ?? '',
    ];
    print('MOB-183 Server nicht erreichbar, ein Foto offen: $ohne');
    await proxyAn();
    expect(
      knopfZeitleiste || knopfSeite,
      isFalse,
      reason: 'wie in Runde 1: ohne Sicherung kein Knopf',
    );
  });

  pruefung('MOB-184 Nur auf dem Telefon: Zeitleiste und eigener Betrachter', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K184');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await _sichernBisFertig(tester, app);
    await zurueck(tester);
    await zurueck(tester);
    await proxyAus();
    await ruhe(tester, 1500);
    await inMediathek(2, praefix: 'r2_184');
    await warte(
      tester,
      find.text(de.lokalAnzahl(2)),
      max: const Duration(seconds: 60),
    );
    print(
      'MOB-184 Zeile: ${sichtbareTexte(tester).where((t) => t.contains('Wartet') || t.contains('nur auf dem Telefon'))}',
    );
    expect(find.text(de.lokalJetztSichern), findsWidgets);
    await warte(tester, _lokaleKachel);
    await tester.ensureVisible(_lokaleKachel.first);
    await ruhe(tester, 500);
    expect(_lokaleKachel, findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'AufnahmenRaster',
        ),
        matching: find.byIcon(Icons.cloud_off_outlined),
      ),
      findsWidgets,
      reason: 'durchgestrichene Wolke an den Kacheln',
    );
    await lang(tester, _lokaleKachel.first);
    expect(
      find.text(de.auswahlAnzahl(1)),
      findsNothing,
      reason: 'nicht wählbar',
    );
    await tippe(tester, _lokaleKachel.first, ms: 1500);
    await warte(tester, find.text(de.lokalNochNichtGesichert));
    expect(find.text(de.lokalJetztSichern), findsWidgets);
    expect(tooltip(de.lokalVomTelefonLoeschen), findsOneWidget);
    final pm = PhotoManagerAttrappe()..an();
    addTearDown(pm.aus);
    pm.loeschenAntwort(bestaetigt: true);
    await tippe(tester, tooltip(de.lokalVomTelefonLoeschen), ms: 2000);
    await meldung(tester, de.vomTelefonGeloescht(1));
    expect(pm.geloescht, hasLength(1));
    await proxyAn();
  });

  pruefung('MOB-164 iOS: Kontrollzentrum verdeckt, sperrt aber nicht', (
    tester,
  ) async {
    final k = await kontoMitFotos('K164', 1);
    await einrichten();
    await appBeenden(tester);
    final ordner = await Directory.systemTemp.createTemp('pv_mob_');
    final s =
        Sitzung(
            ordner: () async => Directory(p.join(ordner.path, 'bibliothek')),
          )
          ..appSperre = AppSperre(
            an: true,
            verfuegbar: () async => true,
            pruefe: (_) async => true,
          );
    await s.verbinde(
      server: hauptApp,
      konto: k.konto,
      geraet: 'Telefon',
      token: await holeToken(hauptDirekt, k.konto),
    );
    await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
    await ruhe(tester, 1500);
    await s.appSperre!.entsperre('Pruefung');
    await ruhe(tester, 1500);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await ruhe(tester, 800);
    final verdeckt = find.byIcon(Icons.lock_outline).evaluate().isNotEmpty;
    final gesperrt = find.text(de.appSperreEntsperren).evaluate().isNotEmpty;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await ruhe(tester, 1200);
    print(
      'MOB-164 iOS inaktiv: verdeckt $verdeckt, gesperrt $gesperrt; danach Betrachter ${tooltip(de.betrachterAngaben).evaluate().isNotEmpty}',
    );
    expect(verdeckt, isTrue);
    expect(gesperrt, isFalse);
    expect(tooltip(de.betrachterAngaben), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await s.beende();
    await ordner.delete(recursive: true);
  });
}

Future<void> jetztSichernFuer(WidgetTester tester, App app) => jetztSichern(
  tester.element(find.byType(Scaffold).last),
  app.sitzung.sicherung!,
  db: app.sitzung.db,
);

// ======================================================================
// Passkey (lang: die App wartet nach dem Schliessen des Browsers)

void passkeyTests() {
  // Befund: Schliesst man den Browser der App, ohne sich anzumelden, merkt
  // die App das nicht: url_launcher meldet das Schliessen nach dem ersten
  // Laden nicht mehr (URLLaunchSession.swift), und PasskeyAnmeldung.melde
  // wartet nur auf den Rückweg – bis die Frist von 5 Minuten abläuft
  // (packages/kern/lib/abgleich/passkey_anmeldung.dart `frist`, `ankunft`
  // .timeout). So lange dreht der Balken; erst dann steht „Die Anmeldung mit
  // Passkey wurde nicht abgeschlossen.“ (apps/mobil/lib/seiten/anmelden.dart:166-176).
  pruefung('MOB-009 Passkey: Browser ohne Anmeldung schliessen', (
    tester,
  ) async {
    final messungen = <String>[];
    for (var lauf = 0; lauf < 2; lauf++) {
      await starteApp(tester);
      await schreibe(tester, feld(de.anmeldenAdresse), hauptApp.toString());
      await tippe(tester, find.text(de.anmeldenPasskey), ms: 200);
      // Warten, bis der Browser der App die Seite geladen hat.
      await ruhe(tester, 6000);
      await bildschirmfoto('mob009_browser_$lauf.png');
      messungen.add(
        'Lauf ${lauf + 1}: vor dem Schliessen Meldung '
        '${find.text(de.anmeldenPasskeyAbgebrochen).evaluate().isNotEmpty}, '
        'sichtbar ${sichtbareTexte(tester).where((t) => t.contains('Passkey') || t.contains('geklappt'))}',
      );
      final t0 = DateTime.now();
      await closeInAppWebView();
      await ruhe(tester, 30000);
      final nach30 = find
          .text(de.anmeldenPasskeyAbgebrochen)
          .evaluate()
          .isNotEmpty;
      final balken = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      messungen.add(
        'Lauf ${lauf + 1}: nach 30 s Meldung $nach30, Balken $balken',
      );
      if (lauf == 0) {
        await warte(
          tester,
          find.text(de.anmeldenPasskeyAbgebrochen),
          max: const Duration(minutes: 6),
        );
        messungen.add(
          'Meldung nach ${DateTime.now().difference(t0).inSeconds} s',
        );
        expect(
          find.text(de.anmeldenTitel),
          findsOneWidget,
          reason: 'bleibt auf der Anmeldeseite',
        );
      }
    }
    print('MOB-009 $messungen');
    expect(
      messungen.where((m) => m.contains('nach 30 s Meldung false')),
      isEmpty,
      reason: 'Meldung bald nach dem Schliessen',
    );
  });
}

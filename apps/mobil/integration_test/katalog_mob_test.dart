// ignore_for_file: avoid_print
// Katalogprüfung der Handy-App (pruefkatalog/teile/MOB.json) im
// iOS-Simulator gegen Wegwerf-Server. Jede Prüfung trägt die Katalog-IDs
// im Namen. Laufen lassen:
//
//   flutter test integration_test/katalog_mob_test.dart -d <Simulator> \
//     --dart-define=PV_FIXTURES=<Ordner mit Videos> \
//     --dart-define=PV_FIXTURES_MOB=<Ordner mit probe.heic>
//
// Vorher: Wegwerf-Server und die Steuerung der Prüfumgebung (Ports in
// katalog_hilfen.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/serveradresse.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/groessentext.dart';
import 'package:kern/services/intelligente_alben.dart';
import 'package:kern/services/suchlauf.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'katalog_hilfen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Vorbereitung (nimmt späte Fehler ausserhalb der Prüfungen auf)',
    (tester) async {
      await einrichten();
    },
  );

  tearDown(() async {
    await proxyZuruecksetzen('haupt');
    await proxyZuruecksetzen('leer1');
    await proxyZuruecksetzen('konten');
    await proxyZuruecksetzen('verw');
  });

  // ------------------------------------------------------------------
  // Anmelden

  Future<void> anmeldeDaten(
    WidgetTester tester, {
    required String adresse,
    required String name,
    required String passwort,
  }) async {
    await schreibe(tester, feld(de.anmeldenAdresse), adresse);
    await schreibe(tester, feld(de.anmeldenName), name);
    await schreibe(tester, feld(de.anmeldenPasswort), passwort);
  }

  Future<void> tippeAnmelden(WidgetTester tester) async {
    await tippe(tester, find.widgetWithText(FilledButton, de.anmeldenAnmelden));
  }

  pruefung('MOB-001 Leere oder falsche Server-Adresse', (tester) async {
    await starteApp(tester);
    await warte(tester, find.text(de.anmeldenTitel));
    await anmeldeDaten(tester, adresse: '', name: 'KontoA', passwort: pw);
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenNichtErreichbar));
    expect(istRot(tester, de.anmeldenNichtErreichbar), isTrue);
    await schreibe(
      tester,
      feld(de.anmeldenAdresse),
      'http://$hostAdresse:${Port.frei}',
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenNichtErreichbar));
    await ruhe(tester, 1500);
    expect(find.text(de.anmeldenNichtErreichbar), findsOneWidget);
    expect(istRot(tester, de.anmeldenNichtErreichbar), isTrue);
    // Seite steht, Eingaben bleiben.
    expect(find.text(de.anmeldenTitel), findsOneWidget);
    expect(find.text('KontoA'), findsOneWidget);
    expect(find.text('http://$hostAdresse:${Port.frei}'), findsOneWidget);
    expect(ausnahmen(tester), isEmpty);
  });

  // Behoben in #418: Anmeldung.zustand() prüft Status und Inhalt, bevor es
  // die Antwort deutet; ein fremder Dienst ist ein Serverfehler.
  pruefung('MOB-002 Adresse zeigt auf keinen Photo-Vault-Server', (
    tester,
  ) async {
    // Zweimal, damit ein Befund sicher ist.
    final gezeigt = <String>[];
    for (var i = 0; i < 2; i++) {
      final app = await starteApp(tester);
      await anmeldeDaten(
        tester,
        adresse: 'http://$hostAdresse:${Port.fremd}',
        name: 'KontoA',
        passwort: pw,
      );
      await tippeAnmelden(tester);
      await warteWeg(tester, find.byType(LinearProgressIndicator));
      await ruhe(tester, 500);
      final rot = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.style?.color != null &&
              t.style!.color ==
                  Theme.of(
                    tester.element(find.byType(Scaffold).first),
                  ).colorScheme.error)
            t.data ?? '',
      ];
      gezeigt.add(rot.join(' | '));
      expect(app.sitzung.verbindung, isNull);
      expect(
        File(p.join(app.bibliothek.path, 'library.sqlite')).existsSync(),
        isFalse,
      );
    }
    print('MOB-002 gezeigt: $gezeigt');
    expect(gezeigt, everyElement(de.anmeldenKeinServer));
  });

  pruefung('MOB-003 http:// nur im eigenen Netz, sonst nur https', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K003');
    await starteApp(tester);
    await proxyLogLeeren();
    await anmeldeDaten(
      tester,
      adresse: 'http://fotos.example.org',
      name: konto,
      passwort: pw,
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenNurHttps));
    expect(istRot(tester, de.anmeldenNurHttps), isTrue);
    // Ohne Schema gilt https: die reine Regel der Seite …
    expect(serveradresseAus('fotos.example.org')!.scheme, 'https');
    // … und in der App: an einen lokalen http-Dienst ohne Schema geht keine
    // http-Anfrage (TLS scheitert), und es kommt nicht die http-Meldung.
    await schreibe(
      tester,
      feld(de.anmeldenAdresse),
      '$hostAdresse:${Port.hauptProxy}',
    );
    await tippeAnmelden(tester);
    await warteWeg(tester, find.byType(LinearProgressIndicator));
    expect(find.text(de.anmeldenNurHttps), findsNothing);
    final log = await proxyLog();
    expect(log.where((e) => '${e['pfad']}'.startsWith('/api/')), isEmpty);
    // Lokale Adresse mit http:// – die Anmeldung läuft weiter.
    await schreibe(tester, feld(de.anmeldenAdresse), hauptApp.toString());
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warte(
      tester,
      find.byType(NavigationBar),
      max: const Duration(seconds: 40),
    );
  });

  pruefung('MOB-011 Erstes Konto vom Telefon anlegen', (tester) async {
    await steuer('server/leer2/neu');
    final app = await starteApp(tester);
    await anmeldeDaten(
      tester,
      adresse: adresse(Port.leer2).toString(),
      name: 'Verwalter',
      passwort: pw,
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenErstesTitel));
    expect(find.text(de.anmeldenErstesText('Verwalter')), findsOneWidget);
    await schreibe(tester, feld(de.anmeldenPasswortWiederholen), pw);
    await tippe(tester, find.text(de.anmeldenErstesAnlegen));
    await warte(
      tester,
      find.text(de.zeitleisteLeer),
      max: const Duration(seconds: 40),
    );
    expect(app.sitzung.verbindung?.konto, 'Verwalter');
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontenVerwalten));
    expect(find.text(de.kontenVerwalten), findsOneWidget);
  });

  pruefung('MOB-012 Erstes Konto: Prüfungen und Abbrechen', (tester) async {
    await steuer('server/leer1/neu');
    await starteApp(tester);
    final leer = adresse(Port.leer1).toString();
    await anmeldeDaten(tester, adresse: leer, name: 'a', passwort: pw);
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenNameUngueltig));
    await anmeldeDaten(
      tester,
      adresse: leer,
      name: 'Verwalter',
      passwort: 'elf-Zeichen',
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenPasswortZuKurz(12)));
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenErstesTitel));
    await schreibe(tester, feld(de.anmeldenPasswortWiederholen), '${pw}x');
    await tippe(tester, find.text(de.anmeldenErstesAnlegen));
    await warte(tester, find.text(de.anmeldenPasswortUngleich));
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    await warte(tester, feld(de.anmeldenAdresse));
    expect(find.text(de.anmeldenErstesTitel), findsNothing);
    // Erneut hin: das Wiederholungsfeld ist leer.
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warte(tester, feld(de.anmeldenPasswortWiederholen));
    final w = tester.widget<TextField>(feld(de.anmeldenPasswortWiederholen));
    expect(w.controller!.text, isEmpty);
    final a = Anmeldung(adresse(Port.leer1));
    expect((await a.zustand())['einrichten'], isTrue, reason: 'kein Konto');
    a.schliesse();
  });

  pruefung('MOB-013 Erstes Konto nur aus dem Heimnetz und nur einmal', (
    tester,
  ) async {
    await steuer('server/leer1/neu');
    await starteApp(tester);
    // Fall 1: über einen Zugang, den der Server als „von aussen“ sieht
    // (Proxy setzt X-Forwarded-For mit einer öffentlichen Adresse).
    await proxyRegel({
      'muster': '^/api/v1/',
      'kopf': {'X-Forwarded-For': '203.0.113.7'},
    }, 'leer1');
    await anmeldeDaten(
      tester,
      adresse: adresse(Port.leer1Proxy).toString(),
      name: 'Verwalter',
      passwort: pw,
    );
    await tippeAnmelden(tester);
    await warteWeg(tester, find.byType(LinearProgressIndicator));
    await ruhe(tester, 500);
    // Von aussen meldet der Server kein „einrichten“; die App versucht eine
    // normale Anmeldung. Festhalten, was sie zeigt.
    final vonAussen =
        find.text(de.anmeldenErstesNurHeimnetz).evaluate().isNotEmpty
        ? 'heimnetz'
        : find.text(de.anmeldenFalsch).evaluate().isNotEmpty
        ? 'falsch'
        : find.text(de.anmeldenErstesTitel).evaluate().isNotEmpty
        ? 'erstesKonto'
        : 'anderes';
    print('MOB-013 Fall 1 zeigt: $vonAussen');
    expect(find.text(de.anmeldenErstesTitel), findsNothing);
    final z0 = Anmeldung(adresse(Port.leer1));
    expect(
      (await z0.zustand())['einrichten'],
      isTrue,
      reason: 'kein Konto von aussen',
    );
    z0.schliesse();
    await proxyZuruecksetzen('leer1');
    // Fall 2: im Heimnetz bis „Erstes Konto anlegen“, parallel legt die
    // API ein Konto an.
    await schreibe(
      tester,
      feld(de.anmeldenAdresse),
      adresse(Port.leer1).toString(),
    );
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warte(tester, feld(de.anmeldenPasswortWiederholen));
    final a = Anmeldung(adresse(Port.leer1));
    final erstes = await a.einrichten('Erster', pw, geraet: 'API');
    a.schliesse();
    expect(erstes, isA<AnmeldungFertig>());
    await schreibe(tester, feld(de.anmeldenPasswortWiederholen), pw);
    print('MOB-013 Fall 2 vor dem Tipp: ${sichtbareTexte(tester)}');
    FocusManager.instance.primaryFocus?.unfocus();
    await ruhe(tester, 600);
    await tippe(tester, find.text(de.anmeldenErstesAnlegen), ms: 100);
    print('MOB-013 Fall 2 gleich nach dem Tipp: ${sichtbareTexte(tester)}');
    await warteWeg(tester, find.byType(LinearProgressIndicator));
    await ruhe(tester, 800);
    print('MOB-013 Fall 2 zeigt: ${sichtbareTexte(tester)}');
    await warte(tester, find.text(de.anmeldenSchonEingerichtet));
    expect(feld(de.anmeldenAdresse), findsOneWidget, reason: 'zurück');
    // Nur ein Konto auf dem Server.
    final v = await api(adresse(Port.leer1), 'Erster');
    final konten = (await v.hole('api/v1/konten'))['konten']! as List;
    expect(konten, hasLength(1));
  });

  pruefung('MOB-004 Falsches Passwort', (tester) async {
    await ersteinrichtung(adresse(Port.leer2));
    final konto = await kontoAnlegen(adresse(Port.leer2), 'K004');
    final app = await starteApp(tester);
    await anmeldeDaten(
      tester,
      adresse: adresse(Port.leer2).toString(),
      name: konto,
      passwort: 'falsches-Passwort-1',
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenFalsch));
    expect(istRot(tester, de.anmeldenFalsch), isTrue);
    // Gegenprobe: unbekannter Name, dieselbe Meldung.
    await schreibe(tester, feld(de.anmeldenName), 'Gibtsnicht_004');
    await tippeAnmelden(tester);
    await ruhe(tester, 1500);
    await warte(tester, find.text(de.anmeldenFalsch));
    expect(app.sitzung.verbindung, isNull);
    expect(find.byType(NavigationBar), findsNothing);
  });

  pruefung('MOB-005 Bremse nach vielen Fehlversuchen', (tester) async {
    await ersteinrichtung(adresse(Port.leer2));
    final konto = await kontoAnlegen(adresse(Port.leer2), 'K005');
    await starteApp(tester);
    await anmeldeDaten(
      tester,
      adresse: adresse(Port.leer2).toString(),
      name: konto,
      passwort: 'falsches-Passwort-1',
    );
    var gebremst = false;
    for (var i = 0; i < 7 && !gebremst; i++) {
      await schreibe(tester, feld(de.anmeldenPasswort), 'falsches-Passwort-1');
      await tippeAnmelden(tester);
      await warteWeg(tester, find.byType(LinearProgressIndicator));
      gebremst = find
          .textContaining('Zu viele Fehlversuche')
          .evaluate()
          .isNotEmpty;
    }
    expect(gebremst, isTrue, reason: 'Meldung der Bremse');
    // Sofort mit richtigem Passwort: ebenfalls abgewiesen.
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warteWeg(tester, find.byType(LinearProgressIndicator));
    final meldung = tester
        .widgetList<Text>(find.textContaining('Zu viele Fehlversuche'))
        .first
        .data!;
    final sekunden = int.parse(
      RegExp(r'(\d+) Sekunden').firstMatch(meldung)!.group(1)!,
    );
    expect(find.byType(NavigationBar), findsNothing);
    // Nach Ablauf klappt es.
    await ruhe(tester, (sekunden + 2) * 1000);
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippeAnmelden(tester);
    await warte(
      tester,
      find.byType(NavigationBar),
      max: const Duration(seconds: 40),
    );
  });

  pruefung('MOB-006 Erfolgreiche Anmeldung lädt die Bibliothek', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K006');
    final v = await api(hauptDirekt, konto);
    await fotos(v, 3, praefix: 'k006');
    final app = await starteApp(tester);
    final geraet = tester.widget<TextField>(feld(de.anmeldenGeraet));
    expect(geraet.controller!.text, de.geraetVorgabe);
    expect(de.geraetVorgabe, 'Telefon');
    // Das Laden kurz bremsen, damit der Zwischentext sichtbar ist.
    await proxyRegel({'muster': '^/api/v1/abgleich/abzug', 'verzoegerung': 3});
    await anmeldeDaten(
      tester,
      adresse: hauptApp.toString(),
      name: konto,
      passwort: pw,
    );
    await tippeAnmelden(tester);
    await warte(tester, find.text(de.anmeldenLaedt));
    await warteAufKacheln(tester, 3);
    expect(find.text(de.navZeitleiste), findsWidgets);
    await kontoOeffnen(tester);
    expect(find.text(hostAdresse), findsOneWidget);
    expect(find.text(de.kontoKontoGeraet(konto, 'Telefon')), findsOneWidget);
    await warte(tester, find.text(de.kontoAbgeglichen));
    expect(app.sitzung.verbindung!.konto, konto);
  });

  // Behoben in #418: Ohne Wiederherstellungscodes bleibt die Seite nach dem
  // Fehler mit Meldung, „Erneut versuchen“ und „Zurück zur Anmeldung“.
  pruefung('MOB-014 Server fällt beim Laden der Bibliothek aus', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K014');
    final v = await api(hauptDirekt, konto);
    await fotos(v, 2, praefix: 'k014');
    final befunde = <String>[];
    for (var durchgang = 1; durchgang <= 2; durchgang++) {
      await starteApp(tester);
      await proxyRegel({
        'muster': '^/api/v1/abgleich/abzug',
        'abbrechen': true,
      });
      await anmeldeDaten(
        tester,
        adresse: hauptApp.toString(),
        name: konto,
        passwort: pw,
      );
      await tippeAnmelden(tester);
      await ruhe(tester, 4000);
      final fehler = ausnahmen(tester);
      final meldung = find
          .text(de.anmeldenNichtErreichbar)
          .evaluate()
          .isNotEmpty;
      final zurueck = find.text(de.anmeldenZurueck).evaluate().isNotEmpty;
      befunde.add(
        'Durchgang $durchgang: Ausnahmen $fehler, Meldung $meldung, '
        'zurück $zurueck',
      );
      await proxyZuruecksetzen();
      // Ein zweiter Versuch klappt.
      await tippe(tester, find.text(de.startfehlerErneut));
      await warteAufKacheln(tester, 2);
    }
    print('MOB-014 $befunde');
    expect(
      befunde,
      everyElement(contains('Ausnahmen [], Meldung true, zurück true')),
    );
  });

  pruefung('MOB-015 Nach Neustart ohne erneute Anmeldung, auch offline', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K015');
    final v = await api(hauptDirekt, konto);
    await fotos(v, 2, praefix: 'k015');
    var app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await proxyAus();
    app = await neuStarten(tester, app);
    await warteAufKacheln(tester, 2);
    expect(find.text(de.anmeldenTitel), findsNothing);
    await warte(
      tester,
      find.textContaining('Server nicht erreichbar'),
      max: const Duration(seconds: 60),
    );
    await proxyAn();
    app.sitzung.abgleich?.jetzt();
    await warteWeg(
      tester,
      find.textContaining('Server nicht erreichbar'),
      max: const Duration(seconds: 75),
    );
  });

  verbindungTests();
  zeitleisteTests();
  auswahlTests();
  betrachterTests();
  angabenTests();
  gesichterTests();
  albenTests();
  freigabenTests();
  sucheTests();
  bibliothekTests();
  entwickelnTests();
  kontoTests();
  einstellungenTests();
  sicherungTests();
  nachtragTests();
}

String _kennung() => uuid();

// --------------------------------------------------------------------
// Start und Verbindung

void verbindungTests() {
  pruefung('MOB-016 Vier Bereiche unten, jeder behält seinen Stand', (
    tester,
  ) async {
    final k = await kontoMitFotos('K016', 30);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    for (final n in [de.navZeitleiste, de.navSuche, de.navAlben]) {
      expect(
        find.descendant(of: find.byType(NavigationBar), matching: find.text(n)),
        findsOneWidget,
      );
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await ruhe(tester);
    await bereich(tester, de.navSuche);
    expect(find.widgetWithText(AppBar, de.navSuche), findsOneWidget);
    final suchfeld = find.descendant(
      of: find.byType(Scaffold).first,
      matching: find.byType(TextField),
    );
    await schreibe(tester, suchfeld.first, 'merktext');
    await bereich(tester, de.navAlben);
    expect(find.widgetWithText(AppBar, de.navAlben), findsOneWidget);
    await bereich(tester, de.navBibliothek);
    expect(find.widgetWithText(AppBar, de.navBibliothek), findsOneWidget);
    await bereich(tester, de.navSuche);
    expect(find.text('merktext'), findsOneWidget, reason: 'Suchtext bleibt');
    expect(
      find.descendant(
        of: tooltip(de.kontoTitel),
        matching: find.text(k.konto[0].toUpperCase()),
      ),
      findsOneWidget,
    );
    await kontoOeffnen(tester);
  });

  pruefung('MOB-018 Änderungen ohne Server warten und gehen später nach', (
    tester,
  ) async {
    final k = await kontoMitFotos('K018', 3);
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Album 1', DateTime.now()));
    });
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    final ids = rasterIds(tester);
    await proxyAus();
    await ruhe(tester, 1500);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterFavorit));
    await schliesse(tester);
    await lang(tester, kacheln().at(1));
    await tippe(tester, find.text('Album 1'));
    await meldung(tester, de.auswahlImAlbum(1, 'Album 1'));
    await warte(
      tester,
      find.text(de.offline(2)),
      max: const Duration(seconds: 60),
    );
    // Am Telefon sofort sichtbar.
    expect((await app.sitzung.db.assetById(ids[0]))!.isFavorite, isTrue);
    await kontoOeffnen(tester);
    expect(find.text(de.offline(2)), findsWidgets);
    await proxyAn();
    app.sitzung.abgleich?.jetzt();
    await warte(
      tester,
      find.text(de.kontoAbgeglichen),
      max: const Duration(seconds: 75),
    );
    await zurueck(tester);
    await warteWeg(tester, find.textContaining('Server nicht erreichbar'));
    await mitRechner(hauptDirekt, k.konto, (r) async {
      expect((await r.db.assetById(ids[0]))!.isFavorite, isTrue);
      final drin = await r.db.watchAlbumAssets(album).first;
      expect(drin.map((a) => a.id), [ids[1]]);
    });
  });

  pruefung('MOB-019 Ohne Netz: Kopie arbeitet, ungeladene Bilder melden sich', (
    tester,
  ) async {
    final k = await kontoMitFotos('K019', 4);
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Offlinealbum', DateTime.now()));
      await r.tue(AlbumFuellen(album, [k.ids[0]]));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    // Ein Foto ansehen (lädt die Ansicht), die anderen nie.
    await oeffneKachel(tester, 0);
    await ruhe(tester, 3000);
    await schliesse(tester);
    await proxyAus();
    await ruhe(tester, 1500);
    await bereich(tester, de.navAlben);
    await warte(tester, find.text('Offlinealbum'));
    await bibOeffnen(tester, de.navPersonen);
    await ruhe(tester, 800);
    await zurueck(tester);
    await bibOeffnen(tester, de.navKarte);
    await ruhe(tester, 1500);
    await zurueck(tester);
    await bereich(tester, de.navSuche);
    await tippe(tester, find.text(de.sucheText));
    final feldSuche = find.descendant(
      of: find.byType(Scaffold).first,
      matching: find.byType(TextField),
    );
    await schreibe(tester, feldSuche.first, 'k019_2');
    await absenden(tester, feldSuche.first);
    await ruhe(tester, 1500);
    expect(rasterNamen(tester), contains('k019_2.jpg'));
    await bereich(tester, de.navZeitleiste);
    await oeffneKachel(tester, 0);
    await ruhe(tester, 3000);
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
    await schliesse(tester);
    await oeffneKachel(tester, 3);
    await ruhe(tester, 6000);
    print(
      'MOB-019 nie geöffnet: Meldung '
      '${find.text(de.betrachterNichtGeladen).evaluate().isNotEmpty}',
    );
    expect(ausnahmen(tester), isEmpty);
  });

  pruefung('MOB-020 App oder Server zu alt', (tester) async {
    final k = await kontoMitFotos('K020', 2);
    var app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    final schema = app.sitzung.db.schemaVersion;
    await proxyRegel({
      'muster': '^/api/v1/abgleich/stand',
      'patch': {'schema': schema - 1},
    });
    app = await neuStarten(tester, app);
    await warte(tester, find.text(de.serverZuAlt));
    await warteAufKacheln(tester, 2);
    await kontoOeffnen(tester);
    expect(find.text(de.serverZuAlt), findsWidgets);
    await proxyZuruecksetzen();
    await proxyRegel({
      'muster': '^/api/v1/abgleich/stand',
      'patch': {'schema': schema + 1},
    });
    app = await neuStarten(tester, app);
    await warte(tester, find.text(de.appZuAlt));
    await warteAufKacheln(tester, 2);
  });

  pruefung('MOB-021 Telefon wurde anderswo abgemeldet', (tester) async {
    final k = await kontoMitFotos('K021', 2);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    // Im „Web“: das Gerät „Telefon“ abmelden.
    final g = (await k.v.hole('api/v1/geraete'))['geraete']! as List;
    final telefon = g.cast<Map>().firstWhere((x) => x['name'] == 'Telefon');
    final r = await k.v.anfrage('DELETE', 'api/v1/geraete/${telefon['id']}');
    expect(r.statusCode, lessThan(300));
    await nachUntenZiehen(tester);
    app.sitzung.abgleich?.jetzt();
    await warte(
      tester,
      find.text(de.abgemeldetHinweis),
      max: const Duration(seconds: 60),
    );
    await warteAufKacheln(tester, 2);
    // Neue Daten kommen nicht mehr.
    await hochladen(k.v, jpeg(), 'k021_neu.jpg');
    await ruhe(tester, 5000);
    expect(rasterNamen(tester), isNot(contains('k021_neu.jpg')));
    await kontoOeffnen(tester);
    await tippe(tester, find.text(de.sicherungTitel));
    await ruhe(tester, 1500);
    print(
      'MOB-021 Sicherungsseite zeigt Abmeldung: '
      '${find.text(de.abgemeldetHinweis).evaluate().isNotEmpty}',
    );
  });

  pruefung('MOB-022 Speicher des Servers knapp oder voll', (tester) async {
    final k = await kontoMitFotos('K022', 1);
    await proxyRegel({
      'muster': '^/api/v1/speicher',
      'patch': {
        'stufe': 'knapp',
        'gesamt': 100 * 1024 * 1024 * 1024,
        'frei': 3 * 1024 * 1024 * 1024,
      },
    });
    var app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warte(tester, find.text(de.speicherKnapp('3.00 GB')));
    await kontoOeffnen(tester);
    final zeile = find.text(
      de.speicherStand(
        groessentext(3 * 1024 * 1024 * 1024),
        groessentext(100 * 1024 * 1024 * 1024),
      ),
    );
    await warte(tester, zeile);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(of: zeile, matching: find.byType(ListTile)),
        matching: find.byIcon(Icons.storage_outlined),
      ),
    );
    final ctx = tester.element(zeile);
    expect(icon.color, Theme.of(ctx).colorScheme.error, reason: 'rot');
    await proxyZuruecksetzen();
    await proxyRegel({
      'muster': '^/api/v1/speicher',
      'patch': {'stufe': 'voll', 'frei': 0},
    });
    app = await neuStarten(tester, app);
    await warte(tester, find.text(de.speicherVoll));
  });

  pruefung('MOB-023 Stand der Server-Sicherung nur für Verwalter', (
    tester,
  ) async {
    final verw = await kontoAnlegen(hauptDirekt, 'V023', alsVerwalter: true);
    final konto = await kontoAnlegen(hauptDirekt, 'K023');
    // Ohne PV_SICHERUNG meldet der Server „aus“: dann keine Zeile.
    var app = await starteApp(tester, server: hauptApp, konto: verw);
    await kontoOeffnen(tester);
    await ruhe(tester, 2500);
    print(
      'MOB-023 Server ohne Sicherung (stufe aus): Zeile '
      '${find.textContaining('Sicherung des Servers').evaluate().isNotEmpty}',
    );
    await proxyRegel({
      'muster': '^/api/v1/sicherung',
      'patch': {'stufe': 'nichtEingerichtet'},
    });
    app = await neuStarten(tester, app);
    await kontoOeffnen(tester);
    await warte(tester, find.text(de.serverSicherungOffen));
    await proxyZuruecksetzen();
    await proxyRegel({
      'muster': '^/api/v1/sicherung',
      'patch': {'stufe': 'fehler', 'fehler': 'Ziel fehlt'},
    });
    app = await neuStarten(tester, app);
    await warte(tester, find.text(de.serverSicherungWarnung));
    await kontoOeffnen(tester);
    final z = find.text(de.serverSicherungWarnung);
    await warte(tester, z);
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(of: z.last, matching: find.byType(ListTile)),
        matching: find.byIcon(Icons.backup_outlined),
      ),
    );
    expect(icon.color, Theme.of(tester.element(z.last)).colorScheme.error);
    await proxyZuruecksetzen();
    await proxyRegel({
      'muster': '^/api/v1/sicherung',
      'patch': {'stufe': 'ok', 'letzterErfolg': '2026-11-16T03:00:00Z'},
    });
    app = await neuStarten(tester, app);
    await kontoOeffnen(tester);
    await warte(tester, find.textContaining('Sicherung des Servers: zuletzt'));
    await proxyZuruecksetzen();
    // Konto ohne Verwalterrecht sieht nichts davon – auch bei Warnung.
    await proxyRegel({
      'muster': '^/api/v1/sicherung',
      'patch': {'stufe': 'fehler'},
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await ruhe(tester, 3000);
    expect(find.text(de.serverSicherungWarnung), findsNothing);
    await kontoOeffnen(tester);
    await ruhe(tester, 2000);
    expect(find.textContaining('Sicherung des Servers'), findsNothing);
  });

  pruefung('MOB-024 MOB-025 Konflikt: Punkt, Karte und Entscheidung', (
    tester,
  ) async {
    final k = await kontoMitFotos('K024', 2);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    final id = rasterIds(tester).first;
    await proxyAus();
    await ruhe(tester, 1000);
    // Am Telefon die Beschreibung ändern (ohne Server).
    await app.sitzung.db.fuehreAus(BeschreibungSetzen([id], 'vom Telefon'));
    // Am „Rechner“ dieselbe Beschreibung anders.
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(BeschreibungSetzen([id], 'vom Rechner'));
    });
    await proxyAn();
    app.sitzung.abgleich?.jetzt();
    // MOB-025: Meldung unten mit „Ansehen“.
    await warte(
      tester,
      find.text(de.syncNichtUebernommen(1)),
      max: const Duration(seconds: 60),
    );
    expect(find.text(de.syncAnsehen), findsOneWidget);
    // Punkt am Reiter „Bibliothek“.
    final punkt = tester.widget<Badge>(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(Badge),
      ),
    );
    expect(punkt.isLabelVisible, isTrue);
    await tippe(tester, find.text(de.syncAnsehen));
    await warte(tester, find.text(st.titel));
    await zurueck(tester);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.syncUebersicht));
    expect(
      find.text('0 / 1'),
      findsOneWidget,
      reason: 'wartend / zu entscheiden',
    );
    await zurueck(tester);
    await bereich(tester, de.navBibliothek);
    await warte(tester, find.text(de.syncZuEntscheiden(1)));
    await tippe(tester, find.text(de.syncZuEntscheiden(1)));
    await warte(tester, find.textContaining(st.konflikt));
    await tippe(tester, find.textContaining(st.konflikt));
    await ruhe(tester, 2500);
    final werte = sichtbareTexte(tester);
    print('MOB-024 Fallseite: $werte');
    expect(werte.join(' '), contains('vom Rechner'), reason: 'Serverwert');
    expect(werte.join(' '), contains('vom Telefon'), reason: 'eigener Wert');
    await tippe(tester, find.text(st.behalten));
    await tippe(tester, find.text(st.bestaetigen));
    await ruhe(tester, 2000);
    await warteBis(
      tester,
      () => (app.sitzung.abgleichszustand?.faelle ?? 1) == 0,
      grund: 'Fall entschieden',
    );
    expect((await app.sitzung.db.assetById(id))!.description, 'vom Rechner');
    expect(
      (await amServer(hauptDirekt, k.konto, id))!.description,
      'vom Rechner',
    );
  });
}

// --------------------------------------------------------------------
// Zeitleiste

void zeitleisteTests() {
  pruefung('MOB-027 Leere Zeitleiste', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K027');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warte(tester, find.text(de.zeitleisteLeer));
    await proxyLogLeeren();
    await nachUntenZiehen(tester);
    await ruhe(tester, 1500);
    final log = await proxyLog();
    expect(
      log.any((e) => '${e['pfad']}'.contains('abgleich/aenderungen')),
      isTrue,
      reason: 'Ziehen gleicht ab',
    );
    expect(app.sitzung.abgleichszustand?.erreichbar, isTrue);
  });

  pruefung('MOB-028 Neue Aufnahmen erscheinen von selbst und per Ziehen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K028', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await hochladen(k.v, jpeg(datum: DateTime(2026, 11, 1)), 'k028_neu1.jpg');
    await warteBis(
      tester,
      () => rasterNamen(tester).contains('k028_neu1.jpg'),
      max: const Duration(seconds: 45),
      grund: 'erstes neues Foto von selbst',
    );
    expect(rasterNamen(tester).first, 'k028_neu1.jpg', reason: 'oben');
    await hochladen(k.v, jpeg(datum: DateTime(2026, 11, 2)), 'k028_neu2.jpg');
    await nachUntenZiehen(tester);
    await warteBis(
      tester,
      () => rasterNamen(tester).contains('k028_neu2.jpg'),
      max: const Duration(seconds: 20),
      grund: 'zweites nach dem Ziehen',
    );
    await warteWeg(tester, find.byType(RefreshProgressIndicator));
  });

  pruefung('MOB-029 Zwei Finger ändern die Spaltenzahl (2 bis 6)', (
    tester,
  ) async {
    final k = await kontoMitFotos('K029', 24);
    var app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    expect(app.sitzung.rasterspalten, 4);
    Future<void> kneife(double von, double bis) async {
      final mitte = tester.getCenter(find.byType(Scrollable).first);
      final a = await tester.startGesture(mitte - Offset(von, 0), pointer: 7);
      final b = await tester.startGesture(mitte + Offset(von, 0), pointer: 8);
      for (var i = 1; i <= 10; i++) {
        final d = von + (bis - von) * i / 10;
        await a.moveTo(mitte - Offset(d, 0));
        await b.moveTo(mitte + Offset(d, 0));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await a.up();
      await b.up();
      await ruhe(tester, 500);
    }

    final gesehen = <int>{app.sitzung.rasterspalten};
    for (var i = 0; i < 6; i++) {
      await kneife(40, 160);
      gesehen.add(app.sitzung.rasterspalten);
    }
    final weit = app.sitzung.rasterspalten;
    for (var i = 0; i < 8; i++) {
      await kneife(160, 30);
      gesehen.add(app.sitzung.rasterspalten);
    }
    final eng = app.sitzung.rasterspalten;
    print('MOB-029 Spalten gesehen: $gesehen, weit $weit, eng $eng');
    expect(weit, 2);
    expect(eng, 6);
    app = await neuStarten(tester, app);
    expect(app.sitzung.rasterspalten, 6, reason: 'nach dem Neustart');
  });

  pruefung('MOB-030 Reihenfolge wählen; Gliederung nur nach Datum', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K030');
    final v = await api(hauptDirekt, konto);
    await hochladen(v, jpeg(datum: DateTime(2023, 5, 1)), 'b_mitte.jpg');
    await hochladen(v, jpeg(datum: DateTime(2021, 5, 1)), 'c_alt.jpg');
    await hochladen(
      v,
      jpeg(datum: DateTime(2025, 5, 1), breite: 1600, hoehe: 1200),
      'a_neu.jpg',
    );
    var app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    expect(rasterNamen(tester), ['a_neu.jpg', 'b_mitte.jpg', 'c_alt.jpg']);
    Future<void> waehle(String text) async {
      await tippe(tester, tooltip(de.ansichtReihenfolge));
      await tippe(tester, find.text(text).last);
      await ruhe(tester, 800);
    }

    await waehle(de.sortAufnahmeAlt);
    expect(rasterNamen(tester), ['c_alt.jpg', 'b_mitte.jpg', 'a_neu.jpg']);
    await waehle(de.sortImportNeu);
    expect(rasterNamen(tester).first, 'a_neu.jpg');
    expect(tooltip(de.ansichtNurMonate), findsNothing, reason: 'ohne Datum');
    await waehle(de.sortName);
    expect(rasterNamen(tester), ['a_neu.jpg', 'b_mitte.jpg', 'c_alt.jpg']);
    await waehle(de.sortGroesse);
    expect(rasterNamen(tester).first, 'a_neu.jpg');
    // Die aktuelle Wahl ist abgehakt.
    await tippe(tester, tooltip(de.ansichtReihenfolge));
    final haken = tester.widget<CheckedPopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text(de.sortGroesse).last,
        matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
      ),
    );
    expect(haken.checked, isTrue);
    await tester.tapAt(const Offset(5, 5));
    await ruhe(tester);
    await waehle(de.sortBewertung);
    app = await neuStarten(tester, app);
    await warteAufKacheln(tester, 3);
    expect(app.sitzung.sortierung.name, 'bewertung', reason: 'gemerkt');
    await waehle(de.sortAufnahmeNeu);
    expect(tooltip(de.ansichtNurMonate), findsOneWidget);
  });

  pruefung('MOB-031 Form und Grösse der Kacheln', (tester) async {
    final k = await kontoMitFotos('K031', 6);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    final formVorher = app.sitzung.form;
    await tippe(tester, tooltip(de.ansichtReihen));
    expect(app.sitzung.form, isNot(formVorher));
    await tippe(tester, tooltip(de.ansichtQuadrate));
    expect(app.sitzung.form, formVorher);
    await tippe(tester, tooltip(de.ansichtNurMonate));
    expect(app.sitzung.nurMonate, isTrue);
    await tippe(tester, tooltip(de.ansichtNachTagen));
    expect(app.sitzung.nurMonate, isFalse);
    for (var i = 0; i < 5 && app.sitzung.rasterspalten < 6; i++) {
      await tippe(tester, tooltip(de.ansichtKleiner));
    }
    expect(app.sitzung.rasterspalten, 6);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(de.ansichtKleiner),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'bei 6 ausgegraut',
    );
    for (var i = 0; i < 5 && app.sitzung.rasterspalten > 2; i++) {
      await tippe(tester, tooltip(de.ansichtGroesser));
    }
    expect(app.sitzung.rasterspalten, 2);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(de.ansichtGroesser),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
      reason: 'bei 2 ausgegraut',
    );
  });

  pruefung('MOB-032 Liste mit Spalten und Gliederung', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K032');
    final v = await api(hauptDirekt, konto);
    await hochladen(
      v,
      jpeg(datum: DateTime(2024, 3, 1), kamera: 'Zeta', modell: 'Z1'),
      'z.jpg',
    );
    await hochladen(
      v,
      jpeg(datum: DateTime(2024, 4, 1), kamera: 'Alpha', modell: 'A1'),
      'a.jpg',
    );
    await hochladen(v, jpeg(datum: DateTime(2024, 5, 1)), 'ohne.jpg');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await tippe(tester, tooltip(de.ansichtListe));
    expect(app.sitzung.alsListe, isTrue);
    await ruhe(tester, 1500);
    for (final g in [de.gruppeMonat, de.gruppeTag, de.gruppeKeine]) {
      await tippe(tester, tooltip(de.ansichtGliederung));
      await tippe(tester, find.text(g).last);
    }
    await tippe(tester, tooltip(de.ansichtGliederung));
    await tippe(tester, find.text(de.gruppeKamera).last);
    await ruhe(tester, 2000);
    final namen = rasterNamen(tester);
    print('MOB-032 nach Kamera: $namen');
    expect(namen.last, 'ohne.jpg', reason: 'ohne Kamera am Ende');
    expect(namen.indexOf('a.jpg'), lessThan(namen.indexOf('z.jpg')));
    expect(find.text(de.listeOhneKamera), findsWidgets);
    // Spalten: alle bis auf eine abwählen, die letzte bleibt.
    await tippe(tester, tooltip(de.listeSpalten));
    final kaesten = find.byType(CheckboxListTile);
    await warte(tester, kaesten);
    for (var runde = 0; runde < 15; runde++) {
      final an = [
        for (final e in kaesten.evaluate())
          if ((e.widget as CheckboxListTile).value == true) e,
      ];
      if (an.length <= 1) break;
      await tester.tap(find.byWidget(an.first.widget));
      await ruhe(tester, 300);
    }
    final rest = [
      for (final e in kaesten.evaluate())
        if ((e.widget as CheckboxListTile).value == true) e.widget,
    ];
    expect(rest, hasLength(1));
    await tester.tap(find.byWidget(rest.single));
    await ruhe(tester, 300);
    expect(
      kaesten.evaluate().where(
        (e) => (e.widget as CheckboxListTile).value == true,
      ),
      hasLength(1),
      reason: 'die letzte lässt sich nicht abwählen',
    );
    await tester.tapAt(const Offset(5, 5));
    await ruhe(tester);
    if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      await schliesse(tester);
    }
    await lang(tester, kacheln().first);
    await warte(tester, find.text(de.auswahlAnzahl(1)));
  });

  pruefung('MOB-034 Jahre und Kalender', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K034');
    final v = await api(hauptDirekt, konto);
    await hochladen(v, jpeg(datum: DateTime(2022, 7, 3)), 'j2022.jpg');
    await hochladen(v, jpeg(datum: DateTime(2024, 2, 9)), 'j2024.jpg');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await tippe(tester, tooltip(de.ansichtJahre));
    await warte(tester, find.widgetWithText(AppBar, de.ansichtJahre));
    await warte(tester, find.textContaining('2022'));
    expect(find.textContaining('2024'), findsWidgets);
    await tippe(tester, find.textContaining('2024').first);
    await warte(tester, find.text('Februar'));
    await tippe(tester, find.text('Februar'));
    await warteBis(
      tester,
      () => rasterNamen(tester).contains('j2024.jpg'),
      grund: 'Aufnahmen des Monats',
    );
    expect(rasterNamen(tester), ['j2024.jpg']);
    await schliesse(tester);
    await schliesse(tester);
    await schliesse(tester);
    await bibOeffnen(tester, de.bibKalender);
    await warte(tester, find.textContaining('2022'));
    // Leer: anderes Konto ohne Fotos.
    final leer = await kontoAnlegen(hauptDirekt, 'K034L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.bibKalender);
    await warte(tester, find.text(de.kalLeer));
  });

  pruefung('MOB-035 Erinnerungen über der Zeitleiste', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K035');
    final v = await api(hauptDirekt, konto);
    final h = DateTime.now();
    await hochladen(
      v,
      jpeg(datum: DateTime(h.year - 1, h.month, h.day, 10)),
      'vor1.jpg',
    );
    await hochladen(
      v,
      jpeg(datum: DateTime(h.year - 3, h.month, h.day, 10)),
      'vor3.jpg',
    );
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await warte(tester, find.text(de.erinnerungenTitel));
    expect(find.text(de.erinnerungenVorJahren(1)), findsOneWidget);
    expect(find.text(de.erinnerungenVorJahren(3)), findsOneWidget);
    expect(find.text(de.erinnerungenAnzahl(1)), findsWidgets);
    await tippe(tester, find.text(de.erinnerungenVorJahren(1)), ms: 1500);
    await warte(tester, tooltip(de.betrachterAngaben));
  });
}

// --------------------------------------------------------------------
// Auswahl

Finder _aktion(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'Auswahlleiste',
  ),
  matching: find.text(text),
);

void auswahlTests() {
  pruefung('MOB-037 Auswählen: lange drücken, ziehen, tippen, aufheben', (
    tester,
  ) async {
    final k = await kontoMitFotos('K037', 40);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 8);
    await lang(tester, kacheln().at(0));
    await warte(tester, find.text(de.auswahlAnzahl(1)));
    // Häkchen an der gewählten Kachel.
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    await tippe(tester, tooltip(de.auswahlAufheben));
    await warteWeg(tester, find.text(de.auswahlAnzahl(1)));
    // Lang drücken und ziehen.
    final start = tester.getCenter(kacheln().at(0));
    final ziel = tester.getCenter(kacheln().at(5));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(start, ziel, i / 10)!);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await ruhe(tester, 300);
    final mitte = RegExp(r'^(\d+) ausgewählt$');
    int anzahl() {
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final m = mitte.firstMatch(t.data ?? '');
        if (m != null) return int.parse(m.group(1)!);
      }
      return 0;
    }

    final nachZiehen = anzahl();
    expect(nachZiehen, greaterThanOrEqualTo(6));
    // Bis an den unteren Rand: das Raster rollt weiter.
    final rand = Offset(
      ziel.dx,
      tester.view.physicalSize.height / tester.view.devicePixelRatio - 170,
    );
    await g.moveTo(rand);
    await ruhe(tester, 2500);
    await g.up();
    await ruhe(tester, 500);
    final amRand = anzahl();
    print('MOB-037 Ziehen: $nachZiehen, am Rand: $amRand');
    expect(amRand, greaterThan(nachZiehen));
    // Tippen fügt hinzu bzw. nimmt heraus.
    await tippe(tester, kacheln().at(0));
    expect(anzahl(), amRand - 1);
    await tippe(tester, kacheln().at(0));
    expect(anzahl(), amRand);
    await tippe(tester, tooltip(de.auswahlAufheben));
    await warteBis(tester, () => anzahl() == 0, grund: 'Blatt weg');
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'Auswahlleiste',
      ),
      findsNothing,
    );
  });

  pruefung('MOB-039 Favorit für eine Auswahl', (tester) async {
    final k = await kontoMitFotos('K039', 3);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(FavoritSetzen([k.ids[0]], true));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    for (var i = 0; i < 3; i++) {
      i == 0
          ? await lang(tester, kacheln().at(0))
          : await tippe(tester, kacheln().at(i));
    }
    await tippe(tester, _aktion(de.auswahlFavorit));
    await warteWeg(tester, find.text(de.auswahlAnzahl(3)));
    await ruhe(tester, 3000);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      for (final id in k.ids) {
        expect((await r.db.assetById(id))!.isFavorite, isTrue);
      }
    });
    await bibOeffnen(tester, de.bibFavoriten);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      grund: '3 Favoriten',
    );
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    for (var i = 0; i < 3; i++) {
      i == 0
          ? await lang(tester, kacheln().at(0))
          : await tippe(tester, kacheln().at(i));
    }
    await tippe(tester, _aktion(de.auswahlFavorit));
    await ruhe(tester, 3000);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      for (final id in k.ids) {
        expect((await r.db.assetById(id))!.isFavorite, isFalse);
      }
    });
    await bibOeffnen(tester, de.bibFavoriten);
    await warte(tester, find.text(de.bibFavoritenLeer));
  });

  pruefung('MOB-040 Auswahl in Album legen, neues Album anlegen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K040', 4);
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Album 1', DateTime.now()));
    });
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, find.text('Album 1'));
    await meldung(tester, de.auswahlImAlbum(2, 'Album 1'));
    await ruhe(tester, 4500);
    await lang(tester, kacheln().at(2));
    await tippe(tester, _aktion(de.auswahlAlbumNeu));
    await warte(tester, find.widgetWithText(AlertDialog, de.auswahlAlbumNeu));
    await tippe(tester, find.text(de.auswahlAlbumAnlegen));
    expect(
      find.widgetWithText(AlertDialog, de.auswahlAlbumNeu),
      findsOneWidget,
      reason: 'leerer Name: Dialog bleibt',
    );
    await schreibe(tester, feld(de.auswahlAlbumName), 'Album 2');
    await tippe(tester, find.text(de.auswahlAlbumAnlegen));
    await meldung(tester, de.auswahlImAlbum(1, 'Album 2'));
    await ruhe(tester, 4500);
    await lang(tester, kacheln().at(3));
    await tippe(tester, _aktion(de.auswahlAlbumNeu));
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    await ruhe(tester, 2000);
    final alben = await app.sitzung.db.alleAlben();
    expect(alben.map((a) => a.name).toSet(), {'Album 1', 'Album 2'});
    await mitRechner(hauptDirekt, k.konto, (r) async {
      final a = await r.db.alleAlben();
      expect(a.map((x) => x.name).toSet(), {'Album 1', 'Album 2'});
      expect((await r.db.watchAlbumAssets(album).first).length, 2);
    });
    await bereich(tester, de.navAlben);
    await warte(tester, find.text('Album 2'));
  });

  pruefung('MOB-041 Auswahl in den Papierkorb, mit Abbrechen', (tester) async {
    final k = await kontoMitFotos('K041', 3);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    final ids = rasterIds(tester).take(2).toList();
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlPapierkorb));
    await warte(tester, find.text(de.auswahlPapierkorbTitel(2)));
    expect(find.text(de.auswahlPapierkorbText), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(rasterIds(tester).length, 3);
    await tippe(tester, _aktion(de.auswahlPapierkorb));
    await tippe(tester, find.text(de.betrachterPapierkorb).last);
    await warteBis(tester, () => rasterIds(tester).length == 1, grund: '2 weg');
    await ruhe(tester, 3000);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      for (final id in ids) {
        final a = await r.db.assetById(id);
        expect(a, isNotNull, reason: 'nicht endgültig gelöscht');
        expect(a!.isTrashed, isTrue);
      }
    });
    await bibOeffnen(tester, de.bibPapierkorb);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 2,
      grund: 'im Papierkorb',
    );
  });

  // Behoben in #418: „Rückgängig“ stellt nur die geänderten Aufnahmen
  // zurück, und die Meldung vergeht von selbst.
  pruefung('MOB-043 Archivieren und Rückgängig', (tester) async {
    final k = await kontoMitFotos('K043', 4);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    final ids = rasterIds(tester);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlArchiv));
    await meldung(tester, de.auswahlArchiviert(2));
    await tippe(tester, find.text(de.variantenRueckgaengig));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 4,
      grund: 'zurück',
    );
    await meldungenWeg(tester);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlArchiv));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 2,
      grund: 'archiviert',
    );
    // Ohne Tipp vergeht die Meldung mit „Rückgängig“ von selbst.
    await ruhe(tester, 6000);
    expect(find.text(de.auswahlArchiviert(2)), findsNothing);
    await meldungenWeg(tester);
    await bibOeffnen(tester, de.bibArchiv);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 2,
      grund: 'im Archiv',
    );
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlArchiv));
    await meldung(tester, de.auswahlAusArchiv(2));
    await meldungenWeg(tester);
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 4,
      grund: 'wieder da',
    );
    // Gemischte Auswahl (Hinweis auswahl.dart:87): eine archiviert, eine
    // nicht, im Album gewählt, archivieren, Rückgängig.
    final album = _kennung();
    await app.sitzung.db.fuehreAus(
      AlbumAnlegen(album, 'Gemischt', DateTime.now()),
    );
    await app.sitzung.db.fuehreAus(AlbumFuellen(album, [ids[2], ids[3]]));
    await app.sitzung.db.fuehreAus(ArchivSetzen([ids[2]], true));
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Gemischt'));
    await warteBis(tester, () => rasterIds(tester).length == 2, grund: 'Album');
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlArchiv));
    await meldung(tester, de.auswahlArchiviert(2));
    await tippe(tester, find.text(de.variantenRueckgaengig));
    await ruhe(tester, 1500);
    final vorher = (await app.sitzung.db.assetById(ids[2]))!.isArchived;
    print(
      'MOB-043 gemischt: vorher archivierte nach Rückgängig archiviert=$vorher',
    );
    expect(
      vorher,
      isTrue,
      reason: 'Rückgängig stellt den Stand vor dem Archivieren her',
    );
    expect((await app.sitzung.db.assetById(ids[3]))!.isArchived, isFalse);
  });

  pruefung('MOB-044 Ort für mehrere Aufnahmen setzen', (tester) async {
    final k = await kontoMitFotos('K044', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlOrt));
    await warte(tester, find.text(de.ortFuerAufnahmen(2)));
    final f = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await schreibe(tester, f, 'G');
    await ruhe(tester, 1500);
    expect(find.text(de.ortKeinTreffer), findsNothing);
    expect(find.text(de.ortKeinVerzeichnis), findsNothing);
    await schreibe(tester, f, 'Goslar');
    await ruhe(tester, 2500);
    final ohneVerzeichnis = find
        .text(de.ortKeinVerzeichnis)
        .evaluate()
        .isNotEmpty;
    print('MOB-044 ohne Ortsverzeichnis am Server: $ohneVerzeichnis');
    expect(ohneVerzeichnis, isTrue);
    await proxyAus();
    await schreibe(tester, f, 'Paris');
    await warte(tester, find.text(de.ortKeineVerbindung));
  });

  pruefung('MOB-045 „Aufs Telefon“ speichert Originale', (tester) async {
    final k = await kontoMitFotos('K045', 1);
    await hochladenDatei(k.v, 'video_5s.mp4');
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlHerunterladen));
    await meldung(
      tester,
      de.auswahlGespeichert(2),
      max: const Duration(seconds: 60),
    );
  });

  pruefung('MOB-046 MOB-047 Teilen: Original oder JPEG, JPEG ohne Ort', (
    tester,
  ) async {
    teilenAbfangen();
    final konto = await kontoAnlegen(hauptDirekt, 'K046');
    final v = await api(hauptDirekt, konto);
    final bytes = jpeg(
      breite: 3000,
      hoehe: 2000,
      datum: DateTime(2024, 8, 1, 9, 30),
      kamera: 'Pruefkamera',
      modell: 'PK1',
      breitengrad: 51.9,
      laengengrad: 10.4,
    );
    await hochladen(v, bytes, 'mitort.jpg');
    await hochladenDatei(v, 'video_5s.mp4');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    final namen = rasterNamen(tester);
    final foto = namen.indexOf('mitort.jpg');
    final video = 1 - foto;
    // Nur das Foto.
    await lang(tester, kacheln().at(foto));
    await tippe(tester, _aktion(de.auswahlTeilen));
    for (final z in [
      de.teilenOriginal,
      de.teilenOriginalHinweis,
      de.jpegVolleGroesse,
      de.jpegKante(4096),
      de.jpegKante(2048),
      de.jpegKante(1024),
    ]) {
      expect(find.text(z), findsOneWidget, reason: z);
    }
    expect(find.textContaining(de.teilenOhneVideos), findsNothing);
    await schliesse(tester);
    await tippe(tester, kacheln().at(video));
    await tippe(tester, _aktion(de.auswahlTeilen));
    expect(find.textContaining(de.teilenOhneVideos), findsOneWidget);
    await schliesse(tester);
    await tippe(tester, kacheln().at(foto));
    await tippe(tester, _aktion(de.auswahlTeilen));
    final jpegZeile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text(de.jpegKante(1024)),
        matching: find.byType(ListTile),
      ),
    );
    expect(jpegZeile.enabled, isFalse, reason: 'nur Video: JPEG grau');
    await schliesse(tester);
    await tippe(tester, tooltip(de.auswahlAufheben));
    // JPEG 2048 (MOB-047).
    await lang(tester, kacheln().at(foto));
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.jpegKante(2048)), ms: 100);
    print(
      'MOB-046 Meldung „wird als JPEG geholt“ gesehen: '
      '${find.text(de.teilenWandelt).evaluate().isNotEmpty}',
    );
    await warteBis(
      tester,
      () => geteilt.isNotEmpty,
      max: const Duration(seconds: 60),
      grund: 'geteilt',
    );
    final datei = geteilt.last.single;
    expect(datei.pfad.toLowerCase(), endsWith('.jpg'));
    final bild = img.decodeJpg(datei.daten)!;
    expect(math.max(bild.width, bild.height), 2048);
    final exif = img.decodeJpgExif(datei.daten)!;
    print(
      'MOB-047 JPEG exif: image ${exif.imageIfd.keys.toList()} exif ${exif.exifIfd.keys.toList()} gps ${exif.gpsIfd.keys.toList()}',
    );
    expect(exif.gpsIfd.isEmpty, isTrue, reason: 'kein Ort');
    expect(exif.imageIfd['Make']?.toString(), contains('Pruefkamera'));
    expect(
      exif.exifIfd['DateTimeOriginal']?.toString() ??
          exif.imageIfd['DateTime']?.toString(),
      contains('2024:08:01'),
    );
    // Original: unverändert mit GPS.
    await ruhe(tester, 1000);
    await lang(tester, kacheln().at(foto));
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.teilenOriginal));
    await warteBis(
      tester,
      () => geteilt.length >= 2,
      max: const Duration(seconds: 60),
      grund: 'Original geteilt',
    );
    final o = geteilt.last.single;
    expect(sha(o.daten), sha(bytes), reason: 'Original byte-gleich');
    expect(img.decodeJpgExif(o.daten)!.gpsIfd.isEmpty, isFalse);
  });

  pruefung('MOB-048 Teilen ohne Server', (tester) async {
    teilenAbfangen();
    final k = await kontoMitFotos('K048', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    // Kachel 0: Original einmal laden (teilen), Kachel 1 nie.
    await lang(tester, kacheln().at(0));
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.teilenOriginal));
    await warteBis(tester, () => geteilt.length == 1, grund: 'online geteilt');
    await proxyAus();
    await ruhe(tester, 1500);
    await lang(tester, kacheln().at(1));
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.teilenOriginal));
    await meldung(
      tester,
      de.betrachterNichtGeladen,
      max: const Duration(seconds: 60),
    );
    expect(
      find.text(de.auswahlAnzahl(1)),
      findsOneWidget,
      reason: 'Auswahl bleibt',
    );
    await ruhe(tester, 4500);
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.jpegVolleGroesse));
    await meldung(
      tester,
      de.betrachterNichtGeladen,
      max: const Duration(seconds: 60),
    );
    await ruhe(tester, 4500);
    await tippe(tester, tooltip(de.auswahlAufheben));
    await lang(tester, kacheln().at(0));
    await tippe(tester, _aktion(de.auswahlTeilen));
    await tippe(tester, find.text(de.teilenOriginal));
    await warteBis(tester, () => geteilt.length == 2, grund: 'offline geteilt');
  });

  pruefung('MOB-050 Als Varianten stapeln', (tester) async {
    final k = await kontoMitFotos('K050', 5);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 5);
    Future<void> dreiWaehlen() async {
      await lang(tester, kacheln().at(0));
      await tippe(tester, kacheln().at(1));
      await tippe(tester, kacheln().at(2));
    }

    await dreiWaehlen();
    await tippe(tester, _aktion(de.variantenBilden));
    await warte(tester, find.text(de.variantenHauptWaehlen));
    expect(find.text(de.variantenHauptText), findsOneWidget);
    await tippe(tester, find.text(de.speichern));
    await meldung(tester, de.variantenGebildet(3));
    await tippe(tester, find.text(de.variantenRueckgaengig));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 5,
      grund: 'aufgelöst',
    );
    await meldungenWeg(tester);
    await dreiWaehlen();
    await tippe(tester, _aktion(de.variantenBilden));
    await tippe(tester, find.text(de.speichern));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      grund: 'nur Hauptversion',
    );
    await meldungenWeg(tester);
    // Mit schon Gestapeltem.
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, kacheln().at(2));
    await tippe(tester, _aktion(de.variantenBilden));
    await meldung(tester, de.variantenSchonGestapelt);
  });

  pruefung('MOB-052 Collage aus 2 bis 9 Fotos', (tester) async {
    final k = await kontoMitFotos('K052', 10);
    await hochladenDatei(k.v, 'video_5s.mp4');
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 11);
    final namen = rasterNamen(tester);
    final video = namen.indexOf('video_5s.mp4');
    final fotoIdx = [
      for (var i = 0; i < namen.length; i++)
        if (i != video) i,
    ];
    Finder collage() => _aktion(tt.collage);
    await lang(tester, kacheln().at(fotoIdx[0]));
    expect(collage(), findsNothing, reason: 'ein Foto');
    await tippe(tester, tooltip(de.auswahlAufheben));
    // Zehn Fotos: der ganze Tag (Tipp auf den Tageskopf).
    await tippe(tester, find.text('Donnerstag, 20. Juni'));
    await ruhe(tester);
    expect(find.text(de.auswahlAnzahl(10)), findsOneWidget);
    expect(collage(), findsNothing, reason: 'zehn Fotos');
    await tippe(tester, tooltip(de.auswahlAufheben));
    await lang(tester, kacheln().at(fotoIdx[0]));
    await tippe(tester, kacheln().at(fotoIdx[1]));
    await tippe(tester, kacheln().at(video));
    expect(collage(), findsNothing, reason: 'mit Video');
    await tippe(tester, kacheln().at(video));
    await tippe(tester, kacheln().at(fotoIdx[2]));
    expect(collage(), findsOneWidget, reason: 'drei Fotos');
    await tippe(tester, collage());
    await warte(tester, find.text(tt.collageVorlage));
    await tippe(tester, find.text(tt.speichern).last, ms: 3000);
    await warte(
      tester,
      find.text(tt.collageGespeichert),
      max: const Duration(seconds: 60),
    );
    await warteBis(
      tester,
      () => rasterIds(tester).length == 12,
      max: const Duration(seconds: 40),
      grund: 'Collage in der Zeitleiste',
    );
    await proxyAus();
    await ruhe(tester, 1500);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, kacheln().at(2));
    print(
      'MOB-052 Collage ohne Server sichtbar: ${collage().evaluate().isNotEmpty}',
    );
  });
}

// --------------------------------------------------------------------
// Betrachter

void betrachterTests() {
  pruefung('MOB-053 Öffnen, blättern, Leiste ein- und ausblenden', (
    tester,
  ) async {
    final k = await kontoMitFotos(
      'K053',
      3,
      ab: DateTime(2026, 9, 12, 10),
      abstand: const Duration(days: 1),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await oeffneKachel(tester, 0);
    expect(find.text('12.09.2026'), findsOneWidget);
    for (final t in [
      de.betrachterFavorit,
      de.betrachterTeilen,
      de.betrachterAngaben,
      de.betrachterMehr,
      de.betrachterPapierkorb,
    ]) {
      expect(tooltip(t), findsOneWidget, reason: t);
    }
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await ruhe(tester, 1200);
    expect(find.text('11.09.2026'), findsOneWidget, reason: 'nächstes Foto');
    await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
    await ruhe(tester, 1200);
    expect(find.text('12.09.2026'), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await ruhe(tester, 800);
    expect(tooltip(de.betrachterAngaben), findsNothing, reason: 'ausgeblendet');
    await tester.tapAt(tester.getCenter(find.byType(PageView)));
    await ruhe(tester, 800);
    expect(tooltip(de.betrachterAngaben), findsOneWidget);
  });

  pruefung('MOB-054 Nach unten wischen schliesst, nach oben zeigt Angaben', (
    tester,
  ) async {
    final k = await kontoMitFotos('K054', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    final mitte = tester.getCenter(find.byType(PageView));
    await tester.dragFrom(mitte, const Offset(0, 60));
    await ruhe(tester, 800);
    expect(
      tooltip(de.betrachterAngaben),
      findsOneWidget,
      reason: 'federt zurück',
    );
    await tester.dragFrom(mitte, const Offset(0, 500));
    await ruhe(tester, 1200);
    expect(find.byType(PageView), findsNothing, reason: 'geschlossen');
    await oeffneKachel(tester, 0);
    await tester.dragFrom(mitte, const Offset(0, -300));
    await ruhe(tester, 1500);
    await warte(tester, find.text(de.angabenTitel));
  });

  pruefung('MOB-055 Zoomen lädt die volle Auflösung', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K055');
    final v = await api(hauptDirekt, konto);
    final heic = await hochladenPfad(v, '$fixturesMob/probe.heic');
    final jpg = await hochladen(
      v,
      jpeg(breite: 4000, hoehe: 3000, datum: DateTime(2020, 1, 1)),
      'gross.jpg',
    );
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    Future<(List<String>, List<String>)> zoome(String id) async {
      final i = rasterIds(tester).indexOf(id);
      await proxyLogLeeren();
      await oeffneKachel(tester, i);
      await ruhe(tester, 3000);
      final vorher = [for (final e in await proxyLog()) '${e['pfad']}'];
      await proxyLogLeeren();
      final m = tester.getCenter(find.byType(PageView));
      await tester.tapAt(m);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(m);
      await ruhe(tester, 6000);
      final nachher = [for (final e in await proxyLog()) '${e['pfad']}'];
      await schliesse(tester);
      return (vorher, nachher);
    }

    final (jv, jn) = await zoome(jpg);
    print('MOB-055 JPEG beim Öffnen: $jv; beim Zoomen: $jn');
    expect(
      [...jv, ...jn].any((x) => x.contains('/api/v1/dateien/originals/')),
      isTrue,
      reason: 'das Original (volle Auflösung) wird geholt',
    );
    final (hv, hn) = await zoome(heic);
    print('MOB-055 HEIC beim Öffnen: $hv; beim Zoomen: $hn');
    expect(
      hn.any((x) => x.contains('/api/v1/aufnahmen/$heic/voll')),
      isTrue,
      reason: 'HEIC: gewandeltes JPEG in voller Grösse erst beim Zoomen',
    );
  });

  pruefung('MOB-056 Favorit und Papierkorb im Betrachter', (tester) async {
    final k = await kontoMitFotos('K056', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    final id = rasterIds(tester).first;
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterFavorit));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.favorite),
      ),
      findsOneWidget,
    );
    await ruhe(tester, 2500);
    expect((await amServer(hauptDirekt, k.konto, id))!.isFavorite, isTrue);
    await tippe(tester, tooltip(de.betrachterFavorit));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.favorite_border),
      ),
      findsOneWidget,
    );
    await ruhe(tester, 2500);
    expect((await amServer(hauptDirekt, k.konto, id))!.isFavorite, isFalse);
    await tippe(tester, tooltip(de.betrachterPapierkorb));
    await warte(tester, find.text(de.betrachterPapierkorbTitel));
    expect(find.text(de.betrachterPapierkorbText), findsOneWidget);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(tooltip(de.betrachterAngaben), findsOneWidget);
    await tippe(tester, tooltip(de.betrachterPapierkorb));
    await tippe(tester, find.text(de.betrachterPapierkorb).last);
    await warteWeg(tester, find.byType(PageView));
    await ruhe(tester, 2500);
    expect((await amServer(hauptDirekt, k.konto, id))!.isTrashed, isTrue);
  });

  pruefung('MOB-057 Betrachter im Papierkorb: nur zurückholen', (tester) async {
    final k = await kontoMitFotos('K057', 2);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(InDenPapierkorb([k.ids[0]])),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await bibOeffnen(tester, de.bibPapierkorb);
    await warteBis(
      tester,
      () => kacheln().evaluate().isNotEmpty,
      grund: 'Papierkorb',
    );
    await oeffneKachel(tester, 0);
    expect(tooltip(de.betrachterFavorit), findsNothing);
    expect(tooltip(de.betrachterPapierkorb), findsNothing);
    expect(tooltip(de.auswahlZurueckholen), findsOneWidget);
    await tippe(tester, tooltip(de.betrachterMehr));
    expect(find.text(de.betrachterGesichtAufziehen), findsNothing);
    expect(find.text(de.entwTitel), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await ruhe(tester);
    await tippe(tester, tooltip(de.auswahlZurueckholen));
    await warteWeg(tester, find.byType(PageView));
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await warteBis(
      tester,
      () => rasterIds(tester).contains(k.ids[0]),
      grund: 'zurück',
    );
  });

  pruefung('MOB-058 Live Photo: LIVE nur beim Live Photo', (tester) async {
    final k = await kontoMitFotos('K058', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await ruhe(tester, 1500);
    expect(find.text('LIVE'), findsNothing);
  });

  pruefung('MOB-059 Video abspielen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K059');
    final v = await api(hauptDirekt, konto);
    await hochladenDatei(v, 'video_5s.mp4');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await proxyLogLeeren();
    await oeffneKachel(tester, 0);
    final spieler = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'VideoPlayer',
    );
    await warte(tester, spieler, max: const Duration(seconds: 30));
    dynamic c() => (tester.widget(spieler) as dynamic).controller;
    await warteBis(tester, () => c().value.isPlaying == true, grund: 'spielt');
    final log = await proxyLog();
    print('MOB-059 Anfragen: ${[for (final e in log) e['pfad']]}');
    await tester.tapAt(tester.getCenter(spieler));
    await ruhe(tester, 800);
    final angehalten = c().value.isPlaying == false;
    await tester.tapAt(tester.getCenter(spieler));
    await ruhe(tester, 800);
    final weiter = c().value.isPlaying == true;
    print('MOB-059 Tipp hält an: $angehalten, Tipp spielt weiter: $weiter');
    expect(angehalten && weiter, isTrue);
    final balken = find.byType(Slider).evaluate().isNotEmpty
        ? find.byType(Slider)
        : find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'VideoProgressIndicator',
          );
    if (balken.evaluate().isNotEmpty) {
      final r = tester.getRect(balken.first);
      await tester.tapAt(Offset(r.left + r.width * 0.8, r.center.dy));
      await ruhe(tester, 1200);
      final pos = c().value.position as Duration;
      print('MOB-059 nach Sprung: $pos');
      expect(pos.inMilliseconds, greaterThan(2500));
    } else {
      fail('kein Fortschrittsbalken gefunden');
    }
  });

  pruefung('MOB-062 Diashow ab hier', (tester) async {
    final k = await kontoMitFotos('K062', 4, abstand: const Duration(days: 1));
    await hochladenDatei(k.v, 'video_5s.mp4');
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 5,
      grund: '5 Aufnahmen',
    );
    final namen = rasterNamen(tester);
    final erstesFoto = namen.indexWhere((n) => n.endsWith('.jpg'));
    await oeffneKachel(tester, erstesFoto);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.diashowAbHier), ms: 1500);
    await warte(
      tester,
      find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Diashow'),
    );
    await ruhe(tester, 9000);
    await tester.tapAt(tester.getCenter(find.byType(Scaffold).last));
    await ruhe(tester, 500);
    final zaehler = [
      for (final t in tester.widgetList<Text>(find.textContaining(' / ')))
        t.data ?? '',
    ];
    print('MOB-062 Zähler: $zaehler');
    await tippe(tester, tooltip(de.diashowBeenden), ms: 1500);
    await warte(tester, tooltip(de.betrachterAngaben));
    expect(
      find.text('20.06.2024'),
      findsNothing,
      reason: 'nicht mehr das erste Foto',
    );
    await schliesse(tester);
    final video = namen.indexOf('video_5s.mp4');
    await oeffneKachel(tester, video);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.diashowAbHier), ms: 1500);
    await tester.tapAt(tester.getCenter(find.byType(Scaffold).last));
    await ruhe(tester, 500);
    expect(find.textContaining('1 / '), findsOneWidget);
  });
}

// --------------------------------------------------------------------
// Angaben

Future<void> _angaben(WidgetTester tester) async {
  await tippe(tester, tooltip(de.betrachterAngaben), ms: 1200);
  await warte(tester, find.text(de.angabenTitel));
}

void angabenTests() {
  pruefung('MOB-063 Zeilen der Angaben', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K063');
    final v = await api(hauptDirekt, konto);
    final id = await hochladen(
      v,
      jpeg(
        datum: DateTime(2023, 4, 5, 6, 7),
        kamera: 'Pruefkamera',
        modell: 'PK2',
        breitengrad: 48.1,
        laengengrad: 11.5,
      ),
      'angaben.jpg',
    );
    final album = _kennung();
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Angabenalbum', DateTime.now()));
      await r.tue(AlbumFuellen(album, [id]));
      await r.tue(SchlagwortAnheften([id], 'Testwort'));
      await r.tue(BeschreibungSetzen([id], 'Eine Beschreibung'));
      await r.tue(BewertungSetzen([id], 3));
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    for (final t in [
      'angaben.jpg',
      'Testwort',
      'Angabenalbum',
      de.angabenStandortBekannt,
    ]) {
      await rolleZu(
        tester,
        find.textContaining(t),
        in_: find.byType(Scrollable).last,
      );
      expect(find.textContaining(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('Pruefkamera'), findsWidgets);
    expect(find.text('Eine Beschreibung'), findsOneWidget);
    await rolleZu(
      tester,
      find.textContaining('Importiert'),
      in_: find.byType(Scrollable).last,
    );
    await tippe(tester, find.text('Angabenalbum'));
    await warte(tester, find.widgetWithText(AppBar, 'Angabenalbum'));
  });

  pruefung('MOB-064 Beschreibung ändern', (tester) async {
    final k = await kontoMitFotos('K064', 2);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(
        BildbeschreibungSetzen(
          k.ids[1],
          'Ein Testbild mit Flächen',
          deutsch: true,
        ),
      );
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    final f = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == de.angabenBeschreibung,
    );
    await rolleZu(tester, f, in_: find.byType(Scrollable).last);
    await schreibe(tester, f, 'Neue Beschreibung');
    await tippe(tester, find.text(de.angabenSpeichern));
    await warte(tester, find.text(de.angabenGespeichert));
    await schreibe(tester, f, 'Neue Beschreibung!');
    await warte(tester, find.text(de.angabenSpeichern));
    await ruhe(tester, 2000);
    expect(
      (await amServer(hauptDirekt, k.konto, k.ids[0]))!.description,
      'Neue Beschreibung',
    );
    await schliesse(tester);
    await schliesse(tester);
    await oeffneKachel(tester, 1);
    await _angaben(tester);
    await rolleZu(
      tester,
      find.textContaining('Automatisch:'),
      in_: find.byType(Scrollable).last,
    );
    expect(
      find.text(de.angabenAutomatisch('Ein Testbild mit Flächen')),
      findsOneWidget,
    );
  });

  pruefung('MOB-066 Ort in den Angaben setzen, ändern, entfernen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K066', 2);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(
        OrtSetzen([k.ids[1]], 52.5, 13.4, land: 'DE', stadt: 'Teststadt'),
      );
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    await rolleZu(
      tester,
      find.text(de.ortKeiner),
      in_: find.byType(Scrollable).last,
    );
    expect(find.text(de.ortSetzen), findsOneWidget);
    await schliesse(tester);
    await schliesse(tester);
    await oeffneKachel(tester, 1);
    await _angaben(tester);
    await rolleZu(
      tester,
      find.text(de.ortAendern),
      in_: find.byType(Scrollable).last,
    );
    await tippe(tester, find.text(de.ortAendern));
    await tippe(tester, find.text(de.ortEntfernen));
    await warte(tester, find.text(de.ortKeiner));
    await ruhe(tester, 2000);
    final a = await amServer(hauptDirekt, k.konto, k.ids[1]);
    expect(a!.latitude, isNull);
  });

  pruefung('MOB-067 Schlagwort umbenennen', (tester) async {
    final k = await kontoMitFotos('K067', 2);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(SchlagwortAnheften([k.ids[0], k.ids[1]], 'Testwort'));
      await r.tue(SchlagwortAnheften([k.ids[1]], 'Anderes'));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    final knopf = find.byTooltip(de.angabenSchlagwortUmbenennen);
    await rolleZu(tester, knopf, in_: find.byType(Scrollable).last);
    await tippe(tester, knopf.first);
    await schreibe(tester, feld(de.angabenSchlagwortUmbenennenFeld), 'Anderes');
    await tippe(tester, find.text(de.angabenUmbenennen));
    await meldung(tester, de.angabenSchlagwortVorhanden('Anderes'));
    await ruhe(tester, 4500);
    await tippe(tester, knopf.first);
    await schreibe(tester, feld(de.angabenSchlagwortUmbenennenFeld), 'Neuwort');
    await tippe(tester, find.text(de.angabenUmbenennen));
    await ruhe(tester, 2500);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      final namen = (await r.db.customSelect('SELECT name FROM tags').get())
          .map((z) => z.read<String>('name'))
          .toSet();
      expect(namen, contains('Neuwort'));
      expect(namen, isNot(contains('Testwort')));
    });
  });

  pruefung('MOB-068 Datum aus dem Dateinamen übernehmen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K068');
    final v = await api(hauptDirekt, konto);
    final bytes = jpeg();
    final id = await hochladen(v, bytes, 'IMG_20200101_120000.jpg');
    // Der Server nimmt beim Import das Datum aus dem Namen. Ein abweichendes,
    // nur geschätztes Datum (wie aus der Bildbetrachtung) setzt der Rechner.
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(
        AufnahmedatenSetzen([
          (id: id, zeitpunkt: DateTime(2023, 6, 6, 6, 6), geschaetzt: true),
        ]),
      );
    });
    final vorher = sha(await original(v, id));
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    await warte(tester, find.textContaining('Der Dateiname nennt'));
    await tippe(tester, find.text(de.angabenUebernehmen));
    await ruhe(tester, 2500);
    final a = (await app.sitzung.db.assetById(id))!;
    expect(a.fileCreatedAt.toLocal().year, 2020);
    expect(sha(await original(v, id)), vorher, reason: 'Original byte-gleich');
    await schliesse(tester);
    await schliesse(tester);
    // Offline: kein Vorschlag (zweites solches Foto).
    final id2 = await hochladen(v, jpeg(), 'IMG_20190202_101010.jpg');
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(
        AufnahmedatenSetzen([
          (id: id2, zeitpunkt: DateTime(2023, 1, 1), geschaetzt: true),
        ]),
      );
    });
    await warteBis(
      tester,
      () => rasterIds(tester).contains(id2),
      max: const Duration(seconds: 40),
      grund: 'zweites Foto',
    );
    await proxyAus();
    await ruhe(tester, 1500);
    await oeffneKachel(tester, rasterIds(tester).indexOf(id2));
    await _angaben(tester);
    await ruhe(tester, 2500);
    expect(find.textContaining('Der Dateiname nennt'), findsNothing);
  });

  pruefung('MOB-070 Serie in den Angaben', (tester) async {
    final k = await kontoMitFotos('K070', 5);
    final serie = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(SerieBilden(serie, k.ids, k.ids[2]));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    final zeile = find.text(de.angabenSerie(5));
    await rolleZu(tester, zeile, in_: find.byType(Scrollable).last);
    await tippe(tester, zeile);
    await warte(tester, find.text(de.angabenSerieTitel(5)));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 5,
      grund: '5 Bilder',
    );
    expect(rasterIds(tester).first, k.ids[2], reason: 'Titelbild zuerst');
    await oeffneKachel(tester, 4);
  });
}

// --------------------------------------------------------------------
// Gesichter und Personen

Finder _rahmen() => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'Gesichtsebene',
  ),
  matching: find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onTap != null,
  ),
);

Future<void> _gesichterZeigen(WidgetTester tester) async {
  await tippe(tester, tooltip(de.betrachterMehr));
  await tippe(tester, find.text(de.betrachterGesichterZeigen), ms: 1500);
}

void gesichterTests() {
  pruefung('MOB-071 Gesichtsrahmen zeigen und Gesicht benennen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K071', 1);
    await gesicht(k.v, k.ids[0], kasten: [0.1, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[0], kasten: [0.55, 0.15, 0.3, 0.4]);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await _gesichterZeigen(tester);
    await warteBis(
      tester,
      () => _rahmen().evaluate().length == 2,
      grund: '2 Rahmen',
    );
    await tester.tap(_rahmen().first);
    await ruhe(tester, 800);
    await warte(tester, feld(de.gesichterName));
    await schreibe(tester, feld(de.gesichterName), 'Person A');
    await tippe(tester, find.text(de.gesichterBenennen), ms: 1500);
    await warte(tester, find.text('Person A'));
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterGesichterAus), ms: 800);
    expect(_rahmen(), findsNothing);
    await schliesse(tester);
    await bibOeffnen(tester, de.navPersonen);
    await warte(tester, find.text('Person A'));
    await ruhe(tester, 2000);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      final p = await r.db.customSelect('SELECT name FROM people').get();
      expect(p.map((z) => z.read<String>('name')), contains('Person A'));
    });
  });

  pruefung('MOB-072 Gesicht von Hand aufziehen', (tester) async {
    final k = await kontoMitFotos('K072', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterGesichtAufziehen));
    await warte(tester, find.text(de.betrachterAufziehenHinweis));
    // „Abbrechen“ in der Leiste unten beendet den Modus.
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(find.text(de.betrachterAufziehenHinweis), findsNothing);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterGesichtAufziehen));
    await warte(tester, find.text(de.betrachterAufziehenHinweis));
    final m = tester.getCenter(find.byType(PageView));
    // Blättern gesperrt.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1500);
    await ruhe(tester, 800);
    expect(find.text(de.betrachterAufziehenHinweis), findsOneWidget);
    // Zu klein.
    // Erst über die Ziehschwelle, dann fast zurück: ein winziger Rahmen.
    final g = await tester.startGesture(m);
    await g.moveBy(const Offset(30, 30));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveTo(m + const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 50));
    await g.up();
    await ruhe(tester, 800);
    await meldung(tester, de.betrachterRahmenZuKlein);
    // Gross genug.
    await tester.dragFrom(m - const Offset(60, 60), const Offset(120, 140));
    await ruhe(tester, 1500);
    await warte(tester, feld(de.gesichterName));
    await schreibe(tester, feld(de.gesichterName), 'Person B');
    await tippe(tester, find.text(de.gesichterBenennen), ms: 1500);
    // Ohne Server.
    await proxyAus();
    await ruhe(tester, 1000);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterGesichtAufziehen));
    await tester.dragFrom(m - const Offset(80, 40), const Offset(120, 140));
    await meldung(
      tester,
      de.betrachterGesichtFehler,
      max: const Duration(seconds: 60),
    );
    if (find.widgetWithText(TextButton, de.abbrechen).evaluate().isNotEmpty) {
      await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    }
    expect(find.text(de.betrachterAufziehenHinweis), findsNothing);
  });

  pruefung('MOB-074 Foto von der Gesichtersuche ausnehmen', (tester) async {
    final k = await kontoMitFotos('K074', 1);
    await gesicht(k.v, k.ids[0]);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await _gesichterZeigen(tester);
    await warteBis(
      tester,
      () => _rahmen().evaluate().isNotEmpty,
      grund: 'Rahmen',
    );
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterNichtMehrDurchsuchen));
    await meldung(tester, de.betrachterNichtMehrDurchsuchtHinweis);
    expect(_rahmen(), findsOneWidget, reason: 'Rahmen bleiben');
    await ruhe(tester, 4500);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.betrachterWiederDurchsuchen));
    await meldung(tester, de.betrachterWiederDurchsuchtHinweis);
    expect(_rahmen(), findsOneWidget);
  });

  pruefung(
    'MOB-075 Benennen-Dialog: leer, vorhandene Person, beiseite, lösen, löschen',
    (tester) async {
      final k = await kontoMitFotos('K075', 1);
      final pa = await person(hauptDirekt, k.konto, 'Person A');
      await gesicht(k.v, k.ids[0], kasten: [0.05, 0.1, 0.25, 0.3]);
      await gesicht(k.v, k.ids[0], kasten: [0.4, 0.1, 0.25, 0.3]);
      await gesicht(k.v, k.ids[0], kasten: [0.7, 0.5, 0.25, 0.3], personId: pa);
      final app = await starteApp(tester, server: hauptApp, konto: k.konto);
      await warteAufKacheln(tester, 1);
      await oeffneKachel(tester, 0);
      await _gesichterZeigen(tester);
      await warteBis(
        tester,
        () => _rahmen().evaluate().length == 3,
        grund: '3 Rahmen',
      );
      Future<void> rahmenBei(double x, double y) async {
        // Den Rahmen nehmen, dessen Mitte [x,y] (Anteil) am nächsten liegt.
        final ebene = tester.getRect(
          find
              .byWidgetPredicate(
                (w) => w.runtimeType.toString() == 'Gesichtsebene',
              )
              .first,
        );
        final ziel = Offset(
          ebene.left + ebene.width * x,
          ebene.top + ebene.height * y,
        );
        final r = _rahmen().evaluate().toList()
          ..sort(
            (
              a,
              b,
            ) => ((tester.getCenter(find.byWidget(a.widget)) - ziel).distance)
                .compareTo(
                  (tester.getCenter(find.byWidget(b.widget)) - ziel).distance,
                ),
          );
        await tester.tap(find.byWidget(r.first.widget));
        await ruhe(tester, 800);
        await warte(tester, feld(de.gesichterName));
      }

      await rahmenBei(0.17, 0.25);
      await schreibe(tester, feld(de.gesichterName), '');
      await tippe(tester, find.text(de.gesichterBenennen));
      await warte(tester, find.text(de.gesichterNameFehlt));
      await schreibe(tester, feld(de.gesichterName), 'person a');
      await tippe(tester, find.text(de.gesichterBenennen), ms: 1500);
      await ruhe(tester, 1500);
      final personen = await app.sitzung.db
          .customSelect('SELECT id, name FROM people')
          .get();
      expect(personen, hasLength(1), reason: 'keine neue Person');
      await rahmenBei(0.52, 0.25);
      await tippe(tester, find.text(de.gesichterBeiseite), ms: 1500);
      await rahmenBei(0.82, 0.65);
      await tippe(tester, find.text(de.gesichterLoesen), ms: 1500);
      await rahmenBei(0.82, 0.65);
      await tippe(tester, find.text(de.gesichterRahmenLoeschen));
      await warte(tester, find.text(de.gesichterRahmenLoeschenFrage));
      await tippe(tester, find.text(de.gesichterRahmenLoeschen).last, ms: 1500);
      await ruhe(tester, 2500);
      final faces = await app.sitzung.db
          .customSelect(
            'SELECT person_id, is_ignored FROM faces WHERE asset_id = ?',
            variables: [Variable(k.ids[0])],
          )
          .get();
      print('MOB-075 Gesichter: ${faces.map((z) => z.data).toList()}');
      expect(faces, hasLength(2), reason: 'ein Rahmen gelöscht');
      expect(
        faces.where((z) => z.data['person_id'] == pa),
        hasLength(1),
        reason: '„person a“ ging an Person A',
      );
      expect(faces.where((z) => z.data['is_ignored'] == 1), hasLength(1));
    },
  );

  pruefung('MOB-079 Zwei Personen zusammenführen', (tester) async {
    final k = await kontoMitFotos('K079', 2);
    final pa = await person(hauptDirekt, k.konto, 'Person A');
    final pb = await person(hauptDirekt, k.konto, 'Person B');
    await gesicht(k.v, k.ids[0], personId: pa);
    await gesicht(k.v, k.ids[1], personId: pb);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.navPersonen);
    await tippe(tester, find.text('Person A'));
    await tippe(tester, tooltip(de.personZusammenfuehren));
    await warte(tester, find.text(de.personZusammenfuehrenTitel('Person A')));
    await tippe(tester, find.text('Person B').last);
    await warte(
      tester,
      find.text(de.personZusammenfuehrenFrage('Person B', 'Person A')),
    );
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    await ruhe(tester, 1000);
    await tippe(tester, tooltip(de.personZusammenfuehren));
    await tippe(tester, find.text('Person B').last);
    await tippe(tester, find.text(de.personZusammenfuehren).last, ms: 2500);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      final p = await r.db.customSelect('SELECT id FROM people').get();
      expect(p.map((z) => z.read<String>('id')), [pa]);
      final f = await r.db
          .customSelect("SELECT asset_id FROM faces WHERE person_id = '$pa'")
          .get();
      expect(f, hasLength(2));
    });
  });

  pruefung('MOB-081 Personenstreifen und Personenseite', (tester) async {
    final k = await kontoMitFotos('K081', 4);
    final pb = await person(hauptDirekt, k.konto, 'Person B');
    final pa = await person(hauptDirekt, k.konto, 'Person A');
    final kind = await person(hauptDirekt, k.konto, 'Kind');
    await gesicht(k.v, k.ids[0], personId: pb);
    await gesicht(k.v, k.ids[1], personId: pa);
    await gesicht(k.v, k.ids[2], personId: kind);
    await gesicht(k.v, k.ids[3], personId: kind);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(InDenPapierkorb([k.ids[3]])),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await bereich(tester, de.navBibliothek);
    await warte(tester, find.text('Kind'));
    final xa = tester.getTopLeft(find.text('Person A').first).dx;
    final xb = tester.getTopLeft(find.text('Person B').first).dx;
    final xk = tester.getTopLeft(find.text('Kind').first).dx;
    expect(
      xk < xa && xa < xb,
      isTrue,
      reason: 'alphabetisch: Kind, Person A, Person B',
    );
    await tippe(tester, find.text(de.bibAlle));
    await warte(tester, find.widgetWithText(AppBar, de.navPersonen));
    await schliesse(tester);
    await tippe(tester, find.text('Kind').first);
    await warteBis(
      tester,
      () => rasterIds(tester).isNotEmpty,
      grund: 'Personenseite',
    );
    expect(rasterIds(tester), [k.ids[2]], reason: 'ohne Papierkorb');
    final leer = await kontoAnlegen(hauptDirekt, 'K081L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bereich(tester, de.navBibliothek);
    await warte(tester, find.text(de.personenLeer));
    // Behoben in #418: Das Telefon benennt selbst (MOB-071).
    expect(de.personenLeer, contains(de.gesichterOhneNamen));
  });

  pruefung('MOB-080 Gesicht im ganzen Foto zeigen', (tester) async {
    final k = await kontoMitFotos('K080', 2);
    final pa = await person(hauptDirekt, k.konto, 'Person A');
    await gesicht(k.v, k.ids[0], kasten: [0.1, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[0], kasten: [0.6, 0.1, 0.3, 0.4], personId: pa);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.navPersonen);
    await warte(tester, find.text(de.gesichterOhneNamen));
    final zeigen = tooltip(de.gesichtImFoto);
    await rolleZu(tester, zeigen);
    await tippe(tester, zeigen.first, ms: 2500);
    await warte(tester, find.text('Person A'));
  });
}

// --------------------------------------------------------------------
// Alben

void albenTests() {
  pruefung('MOB-082 Albenliste mit Abschnitten', (tester) async {
    final a = await kontoAnlegen(hauptDirekt, 'K082A');
    final b = await kontoMitFotos('K082B', 1);
    await starteApp(tester, server: hauptApp, konto: a);
    await bereich(tester, de.navAlben);
    await warte(tester, find.text(de.albenLeer));
    final va = await api(hauptDirekt, a);
    final ids = await fotos(va, 2, praefix: 'k082');
    await mitRechner(hauptDirekt, a, (r) async {
      final x = _kennung();
      await r.tue(AlbumAnlegen(x, 'Erstes', DateTime.now()));
      await r.tue(AlbumFuellen(x, [ids[0]]));
      await r.tue(AlbumAnlegen(_kennung(), 'Zweites', DateTime.now()));
    });
    final geteilt = _kennung();
    await mitRechner(hauptDirekt, b.konto, (r) async {
      await r.tue(AlbumAnlegen(geteilt, 'Von B', DateTime.now()));
      await r.tue(AlbumFuellen(geteilt, b.ids));
    });
    await albumTeilen(b.v, geteilt, a);
    final app = await starteApp(tester, server: hauptApp, konto: a);
    await bereich(tester, de.navAlben);
    await warte(tester, find.text('Erstes'));
    expect(find.text('Zweites'), findsOneWidget);
    await app.sitzung.db.fuehreAus(
      SucheMerken(
        _kennung(),
        'Gemerkt',
        alsGespeicherteSuche(const Suchfilter(), text: 'k082'),
      ),
    );
    await bereich(tester, de.navAlben);
    await warte(tester, find.text(de.albenIntelligent));
    await rolleZu(tester, find.text(tt.geteiltMitMir));
    await warte(tester, find.text('Von B'));
    await proxyAus();
    await neuStarten(tester, app);
    await bereich(tester, de.navAlben);
    await ruhe(tester, 4000);
    expect(find.text('Erstes'), findsOneWidget);
    expect(find.text(tt.geteiltMitMir), findsNothing);
  });

  pruefung('MOB-083 Albumseite und Diashow des Albums', (tester) async {
    final k = await kontoMitFotos('K083', 3);
    final v = await hochladenDatei(k.v, 'video_5s.mp4');
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Albumseite', DateTime.now()));
      await r.tue(AlbumFuellen(album, [...k.ids, v]));
      await r.tue(InDenPapierkorb([k.ids[2]]));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Albumseite'));
    await warte(tester, find.widgetWithText(AppBar, 'Albumseite'));
    for (final t in [
      de.diashow,
      de.albumAlsLink,
      tt.kontenTeilen,
      de.albumOfflineSpeichern,
    ]) {
      expect(tooltip(t), findsOneWidget, reason: t);
    }
    await warteBis(tester, () => rasterIds(tester).isNotEmpty, grund: 'Raster');
    final ids = rasterIds(tester);
    print('MOB-083 Albumraster: $ids');
    expect(ids, isNot(contains(k.ids[2])), reason: 'nicht aus dem Papierkorb');
    await tippe(tester, tooltip(de.diashow), ms: 1500);
    final d = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Diashow',
    );
    await warte(tester, d);
    final fotos = (tester.widget(d) as dynamic).fotos as List;
    expect(fotos.map((z) => z.id), isNot(contains(v)), reason: 'nur Fotos');
    expect(fotos.length, 2);
  });

  pruefung('MOB-084 Intelligentes Album merken, öffnen, löschen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K084', 3);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(SchlagwortAnheften([k.ids[0], k.ids[1]], 'Testwort'));
    });
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await bereich(tester, de.navSuche);
    await tippe(tester, find.text(de.sucheText));
    final f = find.descendant(
      of: find.byType(Scaffold).first,
      matching: find.byType(TextField),
    );
    await schreibe(tester, f.first, 'Testwort');
    await absenden(tester, f.first);
    await ruhe(tester, 1500);
    await tippe(tester, find.text(de.sucheAlsAlbum));
    await schreibe(tester, feld(de.albenName), 'Testalbum');
    await tippe(tester, find.text(de.albenMerken));
    await meldung(tester, de.sucheAlsAlbumGemerkt('Testalbum'));
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Testalbum'));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 2,
      grund: '2 Treffer',
    );
    await schliesse(tester);
    final neu = await hochladen(k.v, jpeg(), 'k084_neu.jpg');
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(SchlagwortAnheften([neu], 'Testwort')),
    );
    await ruhe(tester, 5000);
    await tippe(tester, find.text('Testalbum'));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      max: const Duration(seconds: 40),
      grund: 'auch das neue',
    );
    await tippe(tester, tooltip(de.albenLoeschen));
    await warte(tester, find.text(de.albenIntelligentLoeschen('Testalbum')));
    await tippe(tester, find.text(de.albenLoeschen).last, ms: 1500);
    expect(find.text('Testalbum'), findsNothing);
    await ruhe(tester, 2000);
    await mitRechner(hauptDirekt, k.konto, (r) async {
      expect(
        await r.db.customSelect('SELECT id FROM saved_searches').get(),
        isEmpty,
      );
      expect(
        await r.db.assetById(k.ids[0]),
        isNotNull,
        reason: 'Fotos bleiben',
      );
    });
  });

  pruefung(
    'MOB-085 Intelligentes Album nach Bildinhalt ohne Modell oder Netz',
    (tester) async {
      final k = await kontoMitFotos('K085', 2);
      await mitRechner(
        hauptDirekt,
        k.konto,
        (r) => r.tue(SchlagwortAnheften([k.ids[0]], 'Hund')),
      );
      final app = await starteApp(tester, server: hauptApp, konto: k.konto);
      await warteAufKacheln(tester, 2);
      await app.sitzung.db.fuehreAus(
        SucheMerken(
          _kennung(),
          'Inhaltsalbum',
          alsGespeicherteSuche(
            const Suchfilter(),
            text: 'Hund',
            art: Suchart.inhalt,
          ),
        ),
      );
      await bereich(tester, de.navAlben);
      await tippe(tester, find.text('Inhaltsalbum'));
      await warte(tester, find.text(de.sucheKeinModell));
      // Behoben in #418: ohne Modell die Treffer der Textsuche.
      await warteBis(
        tester,
        () => rasterIds(tester).isNotEmpty,
        grund: 'Textreffer',
      );
      expect(rasterIds(tester), [k.ids[0]]);
      await schliesse(tester);
      await proxyAus();
      await ruhe(tester, 1000);
      await tippe(tester, find.text('Inhaltsalbum'));
      await warte(
        tester,
        find.text(de.sucheFehler),
        max: const Duration(seconds: 60),
      );
      expect(ausnahmen(tester), isEmpty);
    },
  );

  pruefung('MOB-086 MOB-089 Album offline behalten und aufheben', (
    tester,
  ) async {
    final k = await kontoMitFotos('K086', 2);
    final heic = await hochladenPfad(k.v, '$fixturesMob/probe.heic');
    final vid = await hochladenDatei(k.v, 'video_5s.mp4');
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Offline', DateTime.now()));
      await r.tue(AlbumFuellen(album, [...k.ids, heic, vid]));
    });
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Offline'));
    await tippe(tester, tooltip(de.albumOfflineSpeichern), ms: 200);
    await meldung(
      tester,
      de.albumOfflineFertig(4),
      max: const Duration(seconds: 90),
    );
    await warte(tester, find.textContaining('Offline auf diesem Telefon ·'));
    await proxyAus();
    await ruhe(tester, 1500);
    // Alle öffnen und zoomen.
    for (var i = 0; i < 4; i++) {
      await oeffneKachel(tester, i);
      final m = tester.getCenter(find.byType(PageView));
      await tester.tapAt(m);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(m);
      await ruhe(tester, 2500);
      expect(
        find.text(de.betrachterNichtGeladen),
        findsNothing,
        reason: 'Kachel $i',
      );
      await schliesse(tester);
    }
    // MOB-089: „Leeren“ lässt angeheftete Dateien liegen.
    await proxyAn();
    await schliesse(tester);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoZwischenspeicherLeeren));
    await tippe(tester, find.text(de.kontoZwischenspeicherLeeren), ms: 1500);
    await zurueck(tester);
    await proxyAus();
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Offline'));
    await oeffneKachel(tester, 0);
    await ruhe(tester, 2500);
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
    await schliesse(tester);
    await proxyAn();
    await tippe(tester, tooltip(de.albumOfflineAufheben));
    await meldung(tester, de.albumOfflineEntfernt);
    expect(find.textContaining('Offline auf diesem Telefon ·'), findsNothing);
    // Zweites Gerät desselben Kontos sieht es nicht als angeheftet.
    expect(app.sitzung.istAlbumOffline(album), isFalse);
  });

  pruefung('MOB-087 Offline behalten bricht ab und setzt fort', (tester) async {
    final k = await kontoMitFotos('K087', 6);
    final album = _kennung();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Abbruch', DateTime.now()));
      await r.tue(AlbumFuellen(album, k.ids));
    });
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 6);
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Abbruch'));
    // Originale bremsen, dann mitten im Laden den Server weg.
    await proxyRegel({'muster': '^/api/v1/dateien/', 'verzoegerung': 2});
    await tippe(tester, tooltip(de.albumOfflineSpeichern), ms: 200);
    await ruhe(tester, 3000);
    await proxyAus();
    await meldung(
      tester,
      de.albumOfflineFehler,
      max: const Duration(seconds: 90),
    );
    expect(
      tooltip(de.albumOfflineAufheben),
      findsOneWidget,
      reason: 'bleibt angeheftet',
    );
    await proxyZuruecksetzen();
    await app.sitzung.pflegeOfflineUndZwischenspeicher();
    await ruhe(tester, 3000);
    final fehlt = await app.sitzung.offlineAlben!.holeAlbum(
      app.sitzung.db,
      app.sitzung.paths,
      album,
    );
    print('MOB-087 nach Fortsetzen offline: $fehlt');
    expect(fehlt, 6);
  });
}

// --------------------------------------------------------------------
// Freigaben und Links

Future<String> _albumMit(String konto, String name, List<String> ids) async {
  final a = _kennung();
  await mitRechner(hauptDirekt, konto, (r) async {
    await r.tue(AlbumAnlegen(a, name, DateTime.now()));
    if (ids.isNotEmpty) await r.tue(AlbumFuellen(a, ids));
  });
  return a;
}

Future<void> _albumOeffnen(WidgetTester tester, String name) async {
  await bereich(tester, de.navAlben);
  await rolleZu(tester, find.text(name));
  await tippe(tester, find.text(name).first, ms: 1200);
}

void freigabenTests() {
  pruefung('MOB-090 Album oder Auswahl als Link teilen', (tester) async {
    teilenAbfangen();
    final k = await kontoMitFotos('K090', 4);
    await _albumMit(k.konto, 'Album 1', k.ids.take(2).toList());
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    await _albumOeffnen(tester, 'Album 1');
    await tippe(tester, tooltip(de.albumAlsLink));
    await warte(tester, find.text(de.linkTitel));
    expect(
      tester.widget<TextField>(feld(de.linkFeldTitel)).controller!.text,
      'Album 1',
    );
    expect(find.text(de.linkTage(7)), findsOneWidget);
    expect(feld(de.linkPasswort), findsOneWidget);
    final herunter = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, de.linkHerunterladen),
    );
    expect(herunter.value, isFalse);
    expect(find.text(de.linkOhneMetadaten), findsOneWidget);
    expect(find.text(de.linkGaesteHochladen), findsOneWidget);
    await tippe(tester, find.text(de.linkErstellen), ms: 1500);
    await warte(tester, find.text(de.linkWerHatSieht));
    await tippe(tester, find.text(de.linkKopieren));
    await meldung(tester, de.linkKopiert);
    final kopiert = (await Clipboard.getData('text/plain'))?.text ?? '';
    expect(kopiert, contains('/'));
    await tippe(tester, find.text(de.linkTeilen));
    await warteBis(
      tester,
      () => geteilteTexte.isNotEmpty,
      grund: 'Link geteilt',
    );
    expect(geteilteTexte.last, kopiert);
    await schliesse(tester);
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await lang(tester, kacheln().at(2));
    await tippe(tester, kacheln().at(3));
    await tippe(tester, _aktion(de.auswahlLink));
    await warte(tester, find.text(de.linkTitel));
    expect(
      tester.widget<TextField>(feld(de.linkFeldTitel)).controller!.text,
      de.linkAnzahl(2),
    );
    expect(find.text(de.linkGaesteHochladen), findsNothing);
  });

  // Behoben in #418: Auch bei abgerissener Verbindung steht „Ohne
  // Verbindung zum Server gibt es keinen Link.“, nie die rohe Ausnahme.
  pruefung('MOB-091 Link: Titel, Passwortlänge, ohne Server', (tester) async {
    final k = await kontoMitFotos('K091', 1);
    await _albumMit(k.konto, 'Linkalbum', k.ids);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await _albumOeffnen(tester, 'Linkalbum');
    await tippe(tester, tooltip(de.albumAlsLink));
    await schreibe(tester, feld(de.linkFeldTitel), '');
    await tippe(tester, find.text(de.linkErstellen));
    await warte(tester, find.text(de.linkTitelFehlt));
    await schreibe(tester, feld(de.linkFeldTitel), 'Titel');
    await schreibe(tester, feld(de.linkPasswort), 'abc');
    await tippe(tester, find.text(de.linkErstellen));
    await warte(tester, find.text(de.linkPasswortKurz));
    await schreibe(tester, feld(de.linkPasswort), '');
    await proxyAus();
    await tippe(tester, find.text(de.linkErstellen));
    await warteWeg(
      tester,
      find.byType(LinearProgressIndicator),
      max: const Duration(seconds: 70),
    );
    await ruhe(tester, 1500);
    final texte = sichtbareTexte(tester);
    print(
      'MOB-091 ohne Server zeigt: ${texte.where((t) => !t.startsWith('http')).toList()}',
    );
    expect(find.text(de.linkWerHatSieht), findsNothing, reason: 'kein Link');
    expect(find.text(de.linkOhneServer), findsOneWidget);
    final freigaben =
        (await k.v.hole('api/v1/freigaben'))['freigaben'] as List?;
    expect(freigaben ?? const [], isEmpty);
  });

  // Behoben in #418: nurImHeimnetz nimmt die Bereiche aus dem Kern
  // (imEigenenNetz), wie ohneTlsErlaubt – samt dem der VPNs.
  pruefung('MOB-094 Hinweis: Link nur im Heimnetz erreichbar', (tester) async {
    final k = await kontoMitFotos('K094', 1);
    await _albumMit(k.konto, 'Heimnetz', k.ids);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await _albumOeffnen(tester, 'Heimnetz');
    await tippe(tester, tooltip(de.albumAlsLink));
    await tippe(tester, find.text(de.linkErstellen), ms: 1500);
    await warte(tester, find.text(de.linkNurHeimnetz));
    expect(istRot(tester, de.linkNurHeimnetz), isTrue);
    await schliesse(tester);
    // Gegenprobe VPN-Bereich 100.64/10 (Hinweis freigaben.dart:254):
    // der Server liefert einen Link mit einer solchen Adresse.
    final vpnAdresse = 'http://${[100, 100, 20, 30].join('.')}:18851';
    await proxyRegel({
      'muster': '^/api/v1/freigaben',
      'methode': 'POST',
      'patch': {'link': '$vpnAdresse/s/probe'},
    });
    await tippe(tester, tooltip(de.albumAlsLink));
    await tippe(tester, find.text(de.linkErstellen), ms: 1500);
    await warte(tester, find.text(de.linkWerHatSieht));
    final vpn = find.text(de.linkNurHeimnetz).evaluate().isNotEmpty;
    print(
      'MOB-094 100.64/10 als Heimnetz erkannt: $vpn; ohneTlsErlaubt: '
      '${ohneTlsErlaubt(Uri.parse(vpnAdresse))}',
    );
    expect(vpn, isTrue);
  });

  pruefung('MOB-095 Geteilte Links verwalten und löschen', (tester) async {
    final k = await kontoMitFotos('K095', 2);
    final leer = await kontoAnlegen(hauptDirekt, 'K095L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.linkNochNichts));
    final mitPw = await k.v.schicke('api/v1/freigaben', {
      'titel': 'Mit Passwort',
      'ids': k.ids,
      'tage': 7,
      'passwort': 'geheim1',
      'herunterladen': false,
    });
    await k.v.schicke('api/v1/freigaben', {
      'titel': 'Ohne Ende',
      'ids': [k.ids[0]],
      'herunterladen': false,
    });
    final link = Uri.parse('${mitPw['link']}');
    final kennung = link.pathSegments.last;
    // Ein Aufruf durch den Gast.
    final r = await http.post(
      hauptDirekt.resolve('api/v1/teilen/$kennung/passwort'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'passwort': 'geheim1'}),
    );
    final keks = (r.headers['set-cookie'] ?? '').split(';').first;
    final g = await http.get(
      hauptDirekt.resolve('api/v1/teilen/$kennung'),
      headers: {if (keks.isNotEmpty) 'cookie': keks},
    );
    print(
      'MOB-095 Gastaufruf: Passwort ${r.statusCode}, Seite ${g.statusCode}',
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text('Mit Passwort'));
    final zeile = find.ancestor(
      of: find.text('Mit Passwort'),
      matching: find.byType(ListTile),
    );
    final unter = [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: zeile, matching: find.byType(Text)),
      ))
        t.data ?? '',
    ].join(' | ');
    print('MOB-095 Zeile: $unter');
    expect(unter, contains(de.linkAnzahl(2)));
    expect(unter, contains(de.linkMitPasswort));
    expect(unter, contains('bis '));
    await rolleZu(tester, find.text('Ohne Ende'));
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Ohne Ende'),
          matching: find.byType(ListTile),
        ),
        matching: find.textContaining(de.linkUnbegrenzt),
      ),
      findsOneWidget,
    );
    await tippe(
      tester,
      find.descendant(
        of: zeile,
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    expect(find.text(de.linkKopieren), findsOneWidget);
    expect(find.text(de.linkTeilen), findsOneWidget);
    await tippe(tester, find.text(de.linkLoeschen));
    await warte(tester, find.text(de.linkLoeschenFrage('Mit Passwort')));
    await tippe(tester, find.text(de.linkLoeschen).last, ms: 1500);
    await warteWeg(tester, find.text('Mit Passwort'));
    final nach = await http.get(hauptDirekt.resolve('api/v1/teilen/$kennung'));
    expect(nach.statusCode, anyOf(404, 410), reason: 'der Gast sieht nichts');
  });

  pruefung('MOB-096 Gäste-Beiträge über Album-Link annehmen und ablehnen', (
    tester,
  ) async {
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
    expect(rasterNamen(tester), isNot(contains('gast1.jpg')));
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
      () =>
          find.byTooltip(de.beitraegeAnnehmen).evaluate().length +
              find.byTooltip(de.beitraegeEntfernen).evaluate().length +
              find.byTooltip(de.beitraegeAblehnen).evaluate().length ==
          2,
      max: const Duration(seconds: 60),
      grund: 'beide Beiträge gelistet',
    );
    await ruhe(tester, 5000);
    final pruefung0 = sichtbareTexte(
      tester,
    ).where((t) => t.contains('von Gast')).toList();
    print('MOB-096 Beiträge: $pruefung0');
    expect(find.textContaining('eigenen Prozess'), findsOneWidget);
    expect(find.textContaining(de.beitraegeVon('Gast')), findsWidgets);
    final annehmbar = find.byTooltip(de.beitraegeAnnehmen).evaluate().length;
    print('MOB-096 annehmbar (geprüft): $annehmbar');
    if (annehmbar == 2) {
      expect(find.text(de.beitraegeAlleAnnehmen), findsOneWidget);
      await tippe(tester, find.byTooltip(de.beitraegeAnnehmen).first, ms: 1500);
      await meldung(tester, de.beitraegeAngenommen(1));
      await tippe(tester, find.byTooltip(de.beitraegeAblehnen).first, ms: 1500);
      await ruhe(tester, 3000);
      await app.sitzung.gleicheAb();
      final imAlbum = await app.sitzung.db.watchAlbumAssets(album).first;
      expect(imAlbum.length, 2);
    } else {
      // Ohne isolierte Prüfung am Server: nur entfernen möglich.
      await tippe(
        tester,
        find.byTooltip(de.beitraegeEntfernen).first,
        ms: 2000,
      );
      await warteBis(
        tester,
        () => find.byTooltip(de.beitraegeEntfernen).evaluate().length == 1,
        grund: 'einer entfernt',
      );
      final imAlbum = await app.sitzung.db.watchAlbumAssets(album).first;
      expect(imAlbum.length, 1, reason: 'nichts ungeprüft im Album');
      fail(
        'Annehmen nicht prüfbar: der Server meldet „Isolierte Prüfung nicht verfügbar“',
      );
    }
  });

  pruefung('MOB-097 Album mit Konten teilen', (tester) async {
    final a = await kontoMitFotos('K097A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K097B');
    await _albumMit(a.konto, 'Teilalbum', a.ids);
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await warteAufKacheln(tester, 1);
    await _albumOeffnen(tester, 'Teilalbum');
    await tippe(tester, tooltip(tt.kontenTeilen), ms: 1500);
    await warte(tester, find.text(tt.kontenTeilenTitel('Teilalbum')));
    expect(find.text(tt.kontenTeilenHinweis), findsOneWidget);
    // Konto B im Auswahlfeld wählen (es gibt mehrere Konten).
    // Konto B im Auswahlfeld wählen (lange Liste: Wert direkt setzen).
    await waehleKonto(tester, await kontoId(a.v, b));
    await tippe(tester, find.text(tt.kontenTeilenKnopf), ms: 1500);
    await warte(tester, find.text(b));
    expect(find.text(tt.kontenAnsehen), findsWidgets);
    final recht = find.byWidgetPredicate((w) => w is DropdownButton<bool>);
    await tippe(tester, recht.first);
    await tippe(tester, find.text(tt.kontenBeitragen).last, ms: 1500);
    final t =
        (await a.v.hole(
              'api/v1/alben/${Uri.encodeComponent((await app0(a.konto, 'Teilalbum')))}/teilungen',
            ))['teilungen']
            as List;
    expect(t.cast<Map>().single['beitragen'], isTrue);
    // Server mit nur einem Konto.
    final erster = adresse(Port.leer1);
    final v1 = await api(erster, 'Erster');
    final x = _kennung();
    final r = await Rechner.verbinde(v1);
    await r.tue(AlbumAnlegen(x, 'Allein', DateTime.now()));
    await r.schliesse();
    await starteApp(tester, server: erster, konto: 'Erster');
    await _albumOeffnen(tester, 'Allein');
    await tippe(tester, tooltip(tt.kontenTeilen), ms: 1500);
    await warte(tester, find.text(tt.kontenKeineAnderen));
  });

  pruefung('MOB-098 Konto B sieht „Geteilt mit mir“, nur ansehen', (
    tester,
  ) async {
    final a = await kontoMitFotos('K098A', 2);
    final b = await kontoAnlegen(hauptDirekt, 'K098B');
    final album = await _albumMit(a.konto, 'Ansehalbum', a.ids);
    await albumTeilen(a.v, album, b);
    await starteApp(tester, server: hauptApp, konto: b);
    await warte(tester, find.text(de.zeitleisteLeer));
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text(tt.geteiltMitMir));
    await warte(tester, find.text('Ansehalbum'));
    expect(find.text(tt.geteiltVon(a.konto)), findsOneWidget);
    await tippe(tester, find.text('Ansehalbum'), ms: 1500);
    await warte(tester, find.text(tt.geteiltAlbumVon(a.konto)));
    expect(tooltip(tt.geteiltHinzufuegen), findsNothing);
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    expect(
      find.text(de.zeitleisteLeer),
      findsOneWidget,
      reason: 'nicht in der eigenen Zeitleiste',
    );
  });

  pruefung('MOB-099 Konto B trägt Fotos aus der Mediathek bei', (tester) async {
    final a = await kontoMitFotos('K099A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K099B');
    final album = await _albumMit(a.konto, 'Beitragsalbum', a.ids);
    await albumTeilen(a.v, album, b, beitragen: true);
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Beitragsalbum'));
    await tippe(tester, find.text('Beitragsalbum'), ms: 1500);
    await tippe(tester, tooltip(tt.geteiltHinzufuegen), ms: 2500);
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
    await tippe(tester, bilder.at(1));
    await tippe(tester, bilder.at(2));
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    await tippe(tester, find.text(de.fotosHinzufuegen(2)), ms: 200);
    await meldung(
      tester,
      tt.geteiltHinzugefuegt(2),
      max: const Duration(seconds: 90),
    );
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
      grund: 'Album lädt neu (3 Aufnahmen)',
    );
    var beigetragen = false;
    for (var i = 0; i < 3 && !beigetragen; i++) {
      await tippe(tester, kacheln3.at(i), ms: 1500);
      beigetragen = find
          .text(tt.geteiltBeigetragenVon(b))
          .evaluate()
          .isNotEmpty;
      await schliesse(tester);
    }
    expect(beigetragen, isTrue, reason: '„Beigetragen von …“');
  });

  pruefung('MOB-100 Konto B blendet ein geteiltes Album aus', (tester) async {
    final a = await kontoMitFotos('K100A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K100B');
    final album = await _albumMit(a.konto, 'Ausblendalbum', a.ids);
    final zweites = await _albumMit(a.konto, 'Endealbum', a.ids);
    await albumTeilen(a.v, album, b);
    await albumTeilen(a.v, zweites, b);
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Ausblendalbum'));
    await tippe(tester, find.text('Ausblendalbum'), ms: 1500);
    await tippe(tester, find.byType(PopupMenuButton<void>));
    await tippe(tester, find.text(tt.geteiltVerlassen));
    await warte(
      tester,
      find.text(tt.geteiltVerlassenFrage('Ausblendalbum', a.konto)),
    );
    await tippe(tester, find.text(tt.geteiltVerlassen).last, ms: 2000);
    await bereich(tester, de.navAlben);
    await ruhe(tester, 2000);
    expect(find.text('Ausblendalbum'), findsNothing);
    final bei =
        (await a.v.hole(
              'api/v1/alben/${Uri.encodeComponent(album)}/teilungen',
            ))['teilungen']
            as List;
    print('MOB-100 Teilungen bei A nach Ausblenden: $bei');
    expect(await amServer(hauptDirekt, a.konto, a.ids[0]), isNotNull);
    // Zweiter Fall: A beendet die Teilung, B hat das Album offen.
    await rolleZu(tester, find.text('Endealbum'));
    await tippe(tester, find.text('Endealbum'), ms: 1500);
    final id = await kontoId(a.v, b);
    await a.v.anfrage(
      'DELETE',
      'api/v1/alben/${Uri.encodeComponent(zweites)}/teilungen/$id',
    );
    await nachUntenZiehen(tester);
    await warte(
      tester,
      find.text(tt.geteiltNichtMehr),
      max: const Duration(seconds: 30),
    );
  });

  pruefung('MOB-101 Konto B entfernt nur den eigenen Beitrag', (tester) async {
    final a = await kontoMitFotos('K101A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K101B');
    final album = await _albumMit(a.konto, 'Entfernalbum', a.ids);
    await albumTeilen(a.v, album, b, beitragen: true);
    final vb = await api(hauptDirekt, b);
    final ordner = await Directory.systemTemp.createTemp('pv_b_');
    final datei = File(p.join(ordner.path, 'vonb.jpg'))
      ..writeAsBytesSync(jpeg());
    await vb.schickeDatei(
      'api/v1/geteilt/${Uri.encodeComponent(await geteiltId(vb, 'Entfernalbum'))}/beitrag',
      datei,
      parameter: {'name': 'vonb.jpg'},
    );
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Entfernalbum'));
    await tippe(tester, find.text('Entfernalbum'), ms: 2000);
    final kacheln2 = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'GeteiltesAlbumSeite',
      ),
      matching: find.byType(GestureDetector),
    );
    await warteBis(
      tester,
      () => kacheln2.evaluate().length >= 2,
      grund: '2 Kacheln',
    );
    var eigenes = false;
    for (var i = 0; i < 2 && !eigenes; i++) {
      await tippe(tester, kacheln2.at(i), ms: 1500);
      if (find.text(tt.geteiltBeigetragenVon(b)).evaluate().isNotEmpty) {
        eigenes = true;
        expect(tooltip(tt.geteiltEntfernen), findsOneWidget);
      } else {
        expect(
          tooltip(tt.geteiltEntfernen),
          findsNothing,
          reason: 'Foto von A',
        );
        await schliesse(tester);
      }
    }
    expect(eigenes, isTrue);
    await tippe(tester, tooltip(tt.geteiltEntfernen));
    await warte(tester, find.textContaining('Deinen Beitrag'));
    await tippe(tester, find.text(tt.geteiltEntfernen).last);
    await meldung(tester, tt.geteiltEntfernt);
  });

  pruefung('MOB-102 MOB-103 Neue Beiträge, Kommentare und „Gefällt mir“', (
    tester,
  ) async {
    final a = await kontoMitFotos('K102A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K102B');
    final album = await _albumMit(a.konto, 'Kommentaralbum', a.ids);
    await _albumMit(a.konto, 'Ungeteilt', a.ids);
    await albumTeilen(a.v, album, b, beitragen: true);
    final vb = await api(hauptDirekt, b);
    final ordner = await Directory.systemTemp.createTemp('pv_b_');
    final datei = File(p.join(ordner.path, 'neuvonb.jpg'))
      ..writeAsBytesSync(jpeg());
    await vb.schickeDatei(
      'api/v1/geteilt/${Uri.encodeComponent(await geteiltId(vb, 'Kommentaralbum'))}/beitrag',
      datei,
      parameter: {'name': 'neuvonb.jpg'},
    );
    // B kommentiert.
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Kommentaralbum'));
    await tippe(tester, find.text('Kommentaralbum'), ms: 1500);
    await tippe(tester, tooltip(tt.kommentare), ms: 1500);
    await warte(tester, find.text(tt.kommentareHinweis));
    final f = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == tt.kommentarSchreiben,
    );
    await schreibe(tester, f, 'Schönes Album');
    await tippe(tester, tooltip(tt.kommentarSenden), ms: 1500);
    await warte(tester, find.text('Schönes Album'));
    await schliesse(tester);
    // „Gefällt mir“ im Betrachter.
    final kacheln2 = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'GeteiltesAlbumSeite',
      ),
      matching: find.byType(GestureDetector),
    );
    await tippe(tester, kacheln2.first, ms: 1500);
    await tippe(tester, find.bySemanticsLabel(tt.gefaelltMir), ms: 1500);
    await schliesse(tester);
    // A: neue Beiträge, Kommentar, Gefällt.
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await bereich(tester, de.navAlben);
    await warte(
      tester,
      find.text(tt.neueBeitraegeTitel),
      max: const Duration(seconds: 30),
    );
    expect(
      find.text(tt.neueBeitraegeAlbum('Kommentaralbum', 1)),
      findsOneWidget,
    );
    expect(find.text(tt.neueBeitraegeVon(b)), findsOneWidget);
    await tippe(
      tester,
      find.text(tt.neueBeitraegeAlbum('Kommentaralbum', 1)),
      ms: 1500,
    );
    await warte(tester, find.widgetWithText(AppBar, 'Kommentaralbum'));
    await tippe(tester, tooltip(tt.kommentare), ms: 1500);
    await warte(tester, find.text('Schönes Album'));
    await schliesse(tester);
    await schliesse(tester);
    await ruhe(tester, 1500);
    await bereich(tester, de.navZeitleiste);
    await bereich(tester, de.navAlben);
    await ruhe(tester, 2500);
    expect(find.text(tt.neueBeitraegeTitel), findsNothing, reason: 'gesehen');
    await tippe(tester, find.text('Ungeteilt'), ms: 1500);
    expect(tooltip(tt.kommentare), findsNothing);
    // B entfernt den Kommentar.
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text('Kommentaralbum'));
    await tippe(tester, find.text('Kommentaralbum'), ms: 1500);
    await tippe(tester, tooltip(tt.kommentare), ms: 1500);
    await tippe(tester, tooltip(tt.kommentarEntfernen));
    await warte(tester, find.text(tt.kommentarEntfernenFrage));
    await tippe(tester, find.text(tt.entfernen).last, ms: 1500);
    await warteWeg(tester, find.text('Schönes Album'));
  });

  pruefung('MOB-105 Bibliothek teilen, auf Personen einschränken', (
    tester,
  ) async {
    final a = await kontoMitFotos('K105A', 3);
    final b = await kontoAnlegen(hauptDirekt, 'K105B');
    final pa = await person(hauptDirekt, a.konto, 'Person A');
    await gesicht(a.v, a.ids[0], personId: pa);
    await mitRechner(
      hauptDirekt,
      a.konto,
      (r) => r.tue(InDenPapierkorb([a.ids[2]])),
    );
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(tt.bibliothekTeilen));
    await tippe(tester, find.text(tt.bibliothekTeilen), ms: 1500);
    await waehleKonto(tester, await kontoId(a.v, b));
    await tippe(tester, find.text(tt.kontenTeilenKnopf), ms: 1500);
    await warte(tester, find.text(b));
    // B sieht die ganze Bibliothek, ohne Papierkorb.
    final vb = await api(hauptDirekt, b);
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text(tt.partnerBibliothekVon(a.konto)));
    expect(find.text(tt.partnerGanzeBibliothek), findsOneWidget);
    await tippe(tester, find.text(tt.partnerBibliothekVon(a.konto)), ms: 2500);
    final kacheln2 = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString().contains('Partner'),
      ),
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onTap != null,
      ),
    );
    await ruhe(tester, 2000);
    print('MOB-105 Kacheln bei B: ${kacheln2.evaluate().length}');
    // Einschränken auf Person A.
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(tt.bibliothekTeilen));
    await tippe(tester, find.text(tt.bibliothekTeilen), ms: 1500);
    await tippe(tester, tooltip(tt.partnerEinschraenken), ms: 1500);
    await tippe(tester, find.text('Person A').last);
    await tippe(tester, find.text(tt.speichern).last, ms: 1500);
    await starteApp(tester, server: hauptApp, konto: b);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text(tt.partnerBibliothekVon(a.konto)));
    await warte(tester, find.text(tt.partnerEingeschraenkt));
    final idA = await kontoId(vb, a.konto);
    final r1 = await vb.anfrage(
      'GET',
      'api/v1/partner/von/$idA/aufnahmen/${a.ids[1]}/miniatur',
    );
    final r0 = await vb.anfrage(
      'GET',
      'api/v1/partner/von/$idA/aufnahmen/${a.ids[0]}/miniatur',
    );
    final r2 = await vb.anfrage(
      'GET',
      'api/v1/partner/von/$idA/aufnahmen/${a.ids[2]}/miniatur',
    );
    print(
      'MOB-105 direkter Abruf: mit Person ${r0.statusCode}, ohne ${r1.statusCode}, Papierkorb ${r2.statusCode}',
    );
    expect(r0.statusCode, 200);
    expect(r1.statusCode, isNot(200));
    expect(r2.statusCode, isNot(200));
  });

  pruefung('MOB-107 Nachlasskontakt benennen, Zugang verlangen, ablehnen', (
    tester,
  ) async {
    final a = await kontoMitFotos('K107A', 1);
    final b = await kontoAnlegen(hauptDirekt, 'K107B');
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(tt.nachlass));
    await tippe(tester, find.text(tt.nachlass), ms: 1500);
    await waehleKonto(tester, await kontoId(a.v, b));
    await tippe(tester, find.text(tt.nachlassBenennen), ms: 1500);
    await warte(tester, find.text(b));
    await starteApp(tester, server: hauptApp, konto: b);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(tt.nachlass));
    await tippe(tester, find.text(tt.nachlass), ms: 1500);
    await warte(tester, find.text(tt.nachlassFuerMich));
    await tippe(tester, find.text(tt.nachlassVerlangen));
    await tippe(tester, find.text(tt.nachlassVerlangen).last, ms: 1500);
    await starteApp(tester, server: hauptApp, konto: a.konto);
    await warte(
      tester,
      find.textContaining('verlangt Zugang zu deiner Bibliothek'),
      max: const Duration(seconds: 30),
    );
    await tippe(tester, find.text(tt.nachlassAblehnen), ms: 1500);
    await warteWeg(
      tester,
      find.textContaining('verlangt Zugang zu deiner Bibliothek'),
    );
  });

  pruefung('MOB-108 Ohne Teilung sieht Konto B nichts von Konto A', (
    tester,
  ) async {
    final a = await kontoMitFotos('K108A', 2);
    await _albumMit(a.konto, 'Geheimalbum', a.ids);
    await mitRechner(
      hauptDirekt,
      a.konto,
      (r) => r.tue(SchlagwortAnheften(a.ids, 'Geheimwort')),
    );
    final b = await kontoAnlegen(hauptDirekt, 'K108B');
    await starteApp(tester, server: hauptApp, konto: b);
    await warte(tester, find.text(de.zeitleisteLeer));
    await bereich(tester, de.navSuche);
    await tippe(tester, find.text(de.sucheText));
    final f = find.descendant(
      of: find.byType(Scaffold).first,
      matching: find.byType(TextField),
    );
    await schreibe(tester, f.first, 'Geheimwort');
    await absenden(tester, f.first);
    await ruhe(tester, 1500);
    expect(find.text(de.sucheNichts), findsOneWidget);
    await bereich(tester, de.navAlben);
    await ruhe(tester, 2000);
    expect(find.text('Geheimalbum'), findsNothing);
    expect(find.text(tt.geteiltMitMir), findsNothing);
    final vb = await api(hauptDirekt, b);
    final r = await vb.anfrage('GET', 'api/v1/aufnahmen/${a.ids[0]}/original');
    final m = await vb.anfrage('GET', 'api/v1/aufnahmen/${a.ids[0]}/miniatur');
    print(
      'MOB-108 direkter Abruf durch B: original ${r.statusCode}, miniatur ${m.statusCode}',
    );
    expect(r.statusCode, isNot(200));
    expect(m.statusCode, isNot(200));
  });
}

/// Die Kennung eines Albums von [konto] nach Namen (über ein zweites
/// Gerät).
Future<String> app0(String konto, String name) => mitRechner(
  hauptDirekt,
  konto,
  (r) async => (await r.db.alleAlben()).firstWhere((a) => a.name == name).id,
);

// --------------------------------------------------------------------
// Suche

Finder _suchfeld() => find.descendant(
  of: find.byType(Scaffold).first,
  matching: find.byType(TextField),
);

Future<void> _suche(
  WidgetTester tester,
  String text, {
  bool inhalt = false,
}) async {
  await bereich(tester, de.navSuche);
  await tippe(tester, find.text(inhalt ? de.sucheInhalt : de.sucheText));
  await schreibe(tester, _suchfeld().first, text);
  await absenden(tester, _suchfeld().first);
  await ruhe(tester, 1500);
  await warteWeg(
    tester,
    find.byType(LinearProgressIndicator),
    max: const Duration(seconds: 60),
  );
}

void sucheTests() {
  // Behoben in #418: Ohne Netz sagt „Bildinhalt“, dass die Bildsuche den
  // Server braucht, und zeigt die Treffer der Textsuche.
  pruefung('MOB-111 MOB-113 Bildinhalt ohne Modell und ohne Netz', (
    tester,
  ) async {
    final k = await kontoMitFotos('K111', 2);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(SchlagwortAnheften([k.ids[0]], 'Hund')),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bereich(tester, de.navSuche);
    final w = tester.widget<TextField>(_suchfeld().first);
    expect(
      w.decoration?.hintText,
      de.sucheHinweisInhalt,
      reason: 'Bildinhalt ist Vorgabe',
    );
    await _suche(tester, 'Hund', inhalt: true);
    await warte(tester, find.text(de.sucheKeinModell));
    expect(rasterIds(tester), [k.ids[0]], reason: 'Textreffer');
    // MOB-113: ohne Netz.
    await proxyAus();
    await ruhe(tester, 1000);
    await _suche(tester, 'Hund', inhalt: true);
    await warte(tester, find.text(de.sucheInhaltOhneServer));
    expect(rasterIds(tester), [k.ids[0]], reason: 'Textreffer ohne Netz');
    final ohne = sichtbareTexte(tester);
    print(
      'MOB-113 Bildinhalt ohne Netz: ${ohne.where((t) => t.length > 10).toList()}',
    );
    final treffer = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'AufnahmenRaster',
    );
    print(
      'MOB-113 Treffer ohne Netz: ${treffer.evaluate().isNotEmpty ? rasterIds(tester) : []}',
    );
    await tippe(tester, find.text(de.sucheText), ms: 1500);
    await absenden(tester, _suchfeld().first);
    await ruhe(tester, 1500);
    expect(rasterIds(tester), [k.ids[0]], reason: 'nach Umschalten Textreffer');
    expect(find.text(de.sucheFehler), findsNothing);
    expect(ohne, isNot(contains(de.sucheFehler)));
  });

  pruefung('MOB-112 Textsuche ohne Netz', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K112');
    final v = await api(hauptDirekt, konto);
    final ids = [
      await hochladen(v, jpeg(), 'schlagwort.jpg'),
      await hochladen(v, jpeg(), 'ort.jpg'),
      await hochladen(v, jpeg(), 'person.jpg'),
      await hochladen(v, jpeg(), 'beschreibung.jpg'),
      await hochladen(v, jpeg(), 'Dateiname_Zebra.jpg'),
    ];
    final pa = await person(hauptDirekt, konto, 'Person A');
    await gesicht(v, ids[2], personId: pa);
    await mitRechner(hauptDirekt, konto, (r) async {
      await r.tue(SchlagwortAnheften([ids[0]], 'Leuchtturm'));
      await r.tue(
        OrtSetzen([ids[1]], 53.5, 8.1, land: 'DE', stadt: 'Musterhafen'),
      );
      await r.tue(BeschreibungSetzen([ids[3]], 'Ein Abend am Wasserfall'));
    });
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 5);
    await proxyAus();
    await ruhe(tester, 1000);
    await bereich(tester, de.navSuche);
    await tippe(tester, find.text(de.sucheText));
    expect(
      tester.widget<TextField>(_suchfeld().first).decoration?.hintText,
      de.sucheHinweisText,
    );
    for (final (wort, id) in [
      ('Leuchtturm', ids[0]),
      ('Musterhafen', ids[1]),
      ('Person A', ids[2]),
      ('Wasserfall', ids[3]),
      ('Zebra', ids[4]),
    ]) {
      await _suche(tester, wort);
      expect(rasterIds(tester), contains(id), reason: wort);
    }
  });

  pruefung('MOB-114 Leere Suche und keine Treffer', (tester) async {
    final k = await kontoMitFotos('K114', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await _suche(tester, '');
    await warte(tester, find.text(de.sucheTextOderFilter));
    await _suche(tester, 'Quatschwortxyz');
    await warte(tester, find.text(de.sucheNichts));
    expect(find.text(de.sucheAlsAlbum), findsOneWidget);
  });

  pruefung('MOB-115 Filter der Suche', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K115');
    final v = await api(hauptDirekt, konto);
    final f1 = await hochladen(
      v,
      jpeg(datum: DateTime(2022, 3, 3), kamera: 'Filterkamera'),
      'f1.jpg',
    );
    final f2 = await hochladen(v, jpeg(datum: DateTime(2023, 3, 3)), 'f2.jpg');
    await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.tue(FavoritSetzen([f1], true)),
    );
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await bereich(tester, de.navSuche);
    await tippe(tester, tooltip(de.sucheFilter), ms: 1200);
    await rolleZu(
      tester,
      find.text(de.sucheFilterFavoriten),
      in_: find.byType(Scrollable).last,
    );
    await tippe(tester, find.text(de.sucheFilterFavoriten));
    await rolleZu(
      tester,
      find.text(de.sucheFilterAnwenden),
      in_: find.byType(Scrollable).last,
    );
    await tippe(tester, find.text(de.sucheFilterAnwenden), ms: 1500);
    await warte(tester, find.textContaining('Filter: '));
    expect(find.textContaining(de.bibFavoriten), findsWidgets);
    expect(rasterIds(tester), [f1], reason: 'Filter allein genügen');
    expect(rasterIds(tester), isNot(contains(f2)));
    await tippe(tester, tooltip(de.sucheFilter), ms: 1200);
    await rolleZu(
      tester,
      find.text(de.sucheFilterZuruecksetzen),
      in_: find.byType(Scrollable).last,
    );
    await tippe(tester, find.text(de.sucheFilterZuruecksetzen), ms: 1200);
    if (find.text(de.sucheFilterAnwenden).evaluate().isNotEmpty) {
      await tippe(tester, find.text(de.sucheFilterAnwenden), ms: 1200);
    }
    expect(find.textContaining('Filter: '), findsNothing);
  });
}

// --------------------------------------------------------------------
// Bibliothek

void bibliothekTests() {
  pruefung('MOB-117 Aufbau der Bibliothek und Favoriten', (tester) async {
    final k = await kontoMitFotos('K117', 2);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(FavoritSetzen([k.ids[1]], true)),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bereich(tester, de.navBibliothek);
    for (final t in [
      de.navPersonen,
      de.bibEntdecken,
      de.bibFavoriten,
      de.navKarte,
      de.bibOrte,
      de.bibReisen,
      de.bibStammbaum,
      de.bibStatistik,
      de.bibRueckblick,
      de.bibKalender,
      de.bibVerwalten,
      de.kammerTitel,
      de.bibDuplikate,
      de.bibAufnahmedaten,
      de.bibArchiv,
      de.bibPapierkorb,
      de.bibEinstellungen,
    ]) {
      await rolleZu(tester, find.textContaining(t));
      expect(find.textContaining(t), findsWidgets, reason: t);
    }
    await bibOeffnen(tester, de.bibFavoriten);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      grund: 'Favorit',
    );
    final leer = await kontoAnlegen(hauptDirekt, 'K117L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.bibFavoriten);
    await warte(tester, find.text(de.bibFavoritenLeer));
  });

  pruefung('MOB-118 Papierkorb: zurückholen, endgültig löschen, leeren', (
    tester,
  ) async {
    final k = await kontoMitFotos('K118', 4);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(InDenPapierkorb(k.ids.take(3).toList())),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await bibOeffnen(tester, de.bibPapierkorb);
    await warte(tester, find.text(de.bibPapierkorbHinweis));
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      grund: '3 im Papierkorb',
    );
    await lang(tester, kacheln().at(0));
    for (final t in [
      de.auswahlTeilen,
      de.auswahlZurueckholen,
      de.bibEndgueltig,
    ]) {
      expect(_aktion(t), findsOneWidget, reason: t);
    }
    expect(_aktion(de.auswahlFavorit), findsNothing);
    final zurueck = rasterIds(tester).first;
    await tippe(tester, _aktion(de.auswahlZurueckholen), ms: 1500);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 2,
      grund: 'zurückgeholt',
    );
    await lang(tester, kacheln().at(0));
    final weg = rasterIds(tester).first;
    await tippe(tester, _aktion(de.bibEndgueltig));
    await warte(tester, find.text(de.bibEndgueltigTitel(1)));
    expect(find.text(de.bibEndgueltigText), findsOneWidget);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    await tippe(tester, _aktion(de.bibEndgueltig));
    await tippe(tester, find.text(de.bibEndgueltig).last, ms: 2500);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      grund: 'endgültig weg',
    );
    expect(
      await amServer(hauptDirekt, k.konto, weg),
      isNull,
      reason: 'am Server weg',
    );
    await tippe(tester, find.text(de.bibPapierkorbLeeren));
    await tippe(tester, find.text(de.bibEndgueltig).last, ms: 2500);
    await warte(tester, find.text(de.bibPapierkorbLeer));
    expect((await amServer(hauptDirekt, k.konto, zurueck))!.isTrashed, isFalse);
  });

  pruefung('MOB-119 Endgültig löschen: Server zu alt oder nicht erreichbar', (
    tester,
  ) async {
    final k = await kontoMitFotos('K119', 2);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(InDenPapierkorb([k.ids[0]])),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await bibOeffnen(tester, de.bibPapierkorb);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      grund: 'Papierkorb',
    );
    await proxyAus();
    await ruhe(tester, 1000);
    await lang(tester, kacheln().at(0));
    await tippe(tester, _aktion(de.bibEndgueltig));
    await tippe(tester, find.text(de.bibEndgueltig).last);
    await meldung(
      tester,
      de.bibEndgueltigFehler,
      max: const Duration(seconds: 70),
    );
    await proxyAn();
    await proxyRegel({
      'muster': '^/api/v1/papierkorb/leeren',
      'status': 404,
      'body': {'fehler': 'unbekannt'},
    });
    await ruhe(tester, 4500);
    await tippe(tester, _aktion(de.bibEndgueltig));
    await tippe(tester, find.text(de.bibEndgueltig).last);
    await meldung(tester, de.bibEndgueltigServerZuAlt);
    expect(rasterIds(tester), [k.ids[0]], reason: 'bleibt im Papierkorb');
  });

  pruefung('MOB-120 Archiv', (tester) async {
    final k = await kontoMitFotos('K120', 2);
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(ArchivSetzen([k.ids[0]], true)),
    );
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    expect(rasterIds(tester), [k.ids[1]]);
    await bibOeffnen(tester, de.bibArchiv);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 1,
      grund: 'im Archiv',
    );
    expect(rasterIds(tester), [k.ids[0]]);
    final leer = await kontoAnlegen(hauptDirekt, 'K120L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.bibArchiv);
    await warte(tester, find.text(de.bibArchivLeer));
  });

  pruefung('MOB-121 MOB-122 Karte; Kacheln über den eigenen Server', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K121');
    final v = await api(hauptDirekt, konto);
    await hochladen(
      v,
      jpeg(breitengrad: 51.90, laengengrad: 10.40),
      'nah1.jpg',
    );
    await hochladen(
      v,
      jpeg(breitengrad: 51.901, laengengrad: 10.401),
      'nah2.jpg',
    );
    await hochladen(v, jpeg(breitengrad: 40.0, laengengrad: -3.7), 'fern.jpg');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await proxyLogLeeren();
    await bibOeffnen(tester, de.navKarte);
    await ruhe(tester, 5000);
    final log = await proxyLog();
    final kacheln3 = log
        .where((e) => '${e['pfad']}'.startsWith('/api/v1/karte/'))
        .length;
    print('MOB-122 Kachelanfragen über den eigenen Server: $kacheln3');
    expect(kacheln3, greaterThan(0));
    expect(ausnahmen(tester), isEmpty);
    final leer = await kontoAnlegen(hauptDirekt, 'K121L');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.navKarte);
    await warte(tester, find.text(de.karteLeer));
  });

  pruefung('MOB-124 MOB-126 Reisen, Stammbaum: leere Zustände', (tester) async {
    final leer = await kontoAnlegen(hauptDirekt, 'K124');
    await starteApp(tester, server: hauptApp, konto: leer);
    await bibOeffnen(tester, de.bibReisen);
    await warte(tester, find.text(de.reisenLeer));
    await rolleZu(tester, find.text(de.aktivitaetenLeer));
    await schliesse(tester);
    await bibOeffnen(tester, de.bibStammbaum);
    await warte(tester, find.text(de.baumKeinePersonen));
  });

  pruefung('MOB-128 Rückblick', (tester) async {
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
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.bibRueckblick);
    await warte(tester, find.text(de.rbJahr(h.year)));
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
    await tippe(tester, tooltip(de.jrVorjahr), ms: 1500);
    await warte(tester, find.text(de.jrLeer(h.year - 1)));
    await tippe(tester, tooltip(de.jrFolgejahr), ms: 1500);
    await warte(tester, find.text(de.jrFotos));
  });

  pruefung('MOB-129 MOB-131 Duplikate und Datierung ohne Modell', (
    tester,
  ) async {
    final k = await kontoMitFotos('K129', 2);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await bibOeffnen(tester, de.bibDuplikate);
    await tippe(tester, find.text(de.duplSuchen), ms: 2500);
    await warte(
      tester,
      find.text(de.duplKeineEinbettungen),
      max: const Duration(seconds: 40),
    );
    expect(de.duplAusnahmen(1), '1 Paare sind ausgenommen.');
    await schliesse(tester);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await rolleZu(tester, find.text(de.datierungTitel));
    await warte(
      tester,
      find.text(de.datierungOhneModell),
      max: const Duration(seconds: 40),
    );
  });

  pruefung('MOB-130 Aufnahmedaten nach Dateinamen prüfen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K130');
    final v = await api(hauptDirekt, konto);
    final ids = [
      await hochladen(v, jpeg(), 'IMG_20200101_100000.jpg'),
      await hochladen(v, jpeg(), 'IMG_20200202_100000.jpg'),
      await hochladen(v, jpeg(), 'IMG_20200303_100000.jpg'),
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
    final vorher = [for (final id in ids) sha(await original(v, id))];
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    if (find.text(de.datenPruefen).evaluate().isNotEmpty) {
      await tippe(tester, find.text(de.datenPruefen), ms: 3000);
    }
    await warte(
      tester,
      find.textContaining('Bei 3 Aufnahmen nennt der Dateiname'),
      max: const Duration(seconds: 40),
    );
    expect(find.textContaining(de.datenLautName), findsWidgets);
    // Vorgewählt sind alle drei; eines abwählen.
    final kaesten = find.byType(Checkbox);
    await tippe(tester, kaesten.at(0));
    await tippe(tester, find.text(de.datenUebernehmen(2)));
    await warte(tester, find.text(de.datenFrage(2)));
    await tippe(tester, find.text(de.datenUebernehmen(2)).last, ms: 3000);
    await warte(
      tester,
      find.textContaining('Bei einer Aufnahme nennt'),
      max: const Duration(seconds: 40),
    );
    for (var i = 0; i < 3; i++) {
      expect(sha(await original(v, ids[i])), vorher[i], reason: 'Original $i');
    }
    await schliesse(tester);
    await proxyAus();
    await ruhe(tester, 1000);
    await bibOeffnen(tester, de.bibAufnahmedaten);
    await warte(
      tester,
      find.text(de.datenOhneServer),
      max: const Duration(seconds: 70),
    );
  });

  pruefung('MOB-132 Fotokammer sichten, freigeben, verwerfen', (tester) async {
    final k = await kontoMitFotos('K132', 5);
    await k.v.schicke('api/v1/kammer/aufnehmen', {'ids': k.ids});
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await bereich(tester, de.navBibliothek);
    await rolleZu(tester, find.textContaining(de.kammerTitel));
    await warte(
      tester,
      find.text('${de.kammerTitel} (5)'),
      max: const Duration(seconds: 30),
    );
    await tippe(tester, find.text('${de.kammerTitel} (5)'), ms: 2000);
    final kacheln4 = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'FotokammerSeite',
      ),
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onLongPress != null,
      ),
    );
    await warteBis(
      tester,
      () => kacheln4.evaluate().length == 5,
      grund: '5 in der Kammer',
    );
    await tippe(tester, kacheln4.at(0), ms: 1500);
    await tippe(tester, tooltip('3'));
    await tippe(tester, tooltip(de.kammerAblehnen), ms: 1200);
    print(
      'MOB-132 Zähler nach Sternen und Ablehnen: ${sichtbareTexte(tester).where((t) => t.contains(' / 5')).toList()}',
    );
    expect(find.text('1 / 5'), findsNothing, reason: 'blättert weiter');
    await schliesse(tester);
    await lang(tester, kacheln4.at(2));
    await tippe(tester, find.text(de.kammerVerwerfen));
    await warte(tester, find.text(de.kammerVerwerfenTitel(1)));
    expect(find.text(de.kammerVerwerfenText), findsOneWidget);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    await tippe(tester, kacheln4.at(2));
    await lang(tester, kacheln4.at(3));
    await tippe(tester, find.text(de.kammerFreigeben), ms: 2000);
    await meldung(tester, de.kammerFreigegeben(1));
    await tippe(tester, tooltip(de.kammerAbschliessen));
    await warte(tester, find.text(de.kammerAbschliessenText(1, 3)));
    await tippe(tester, find.text(de.kammerAbschliessen).last, ms: 3000);
    await warte(
      tester,
      find.text(de.kammerLeer),
      max: const Duration(seconds: 40),
    );
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await warteBis(
      tester,
      () => rasterIds(tester).length == 4,
      max: const Duration(seconds: 40),
      grund: '4 in der Zeitleiste',
    );
  });
}

// --------------------------------------------------------------------
// Entwickeln und Diashow

void entwickelnTests() {
  pruefung('MOB-134 MOB-135 MOB-137 Entwickeln, Speichern, Original bleibt', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K134');
    final v = await api(hauptDirekt, konto);
    final bytes = jpeg(breite: 1200, hoehe: 800, datum: DateTime(2024, 5, 5));
    final id = await hochladen(v, bytes, 'entwickeln.jpg');
    final vorher = sha(await original(v, id));
    expect(vorher, sha(bytes));
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.entwTitel), ms: 3000);
    await warte(tester, find.text(de.entwBelichtung));
    final regler = find.byType(Slider);
    await tester.drag(regler.first, const Offset(60, 0));
    await ruhe(tester, 800);
    // Zurück mit Änderung: Rückfrage.
    await tippe(tester, find.byType(BackButton));
    await warte(tester, find.text(de.entwVerwerfen));
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen).last);
    expect(
      find.text(de.entwBelichtung),
      findsOneWidget,
      reason: 'Seite bleibt',
    );
    await tippe(tester, find.text(de.entwZuruecksetzen));
    await tester.drag(regler.at(1), const Offset(50, 0));
    await ruhe(tester, 800);
    final vorherKnopf = find.text(de.entwVorher);
    if (vorherKnopf.evaluate().isNotEmpty) {
      final g = await tester.startGesture(tester.getCenter(vorherKnopf));
      await ruhe(tester, 800);
      await g.up();
    }
    await tippe(tester, find.text(de.entwSpeichern), ms: 500);
    await warte(
      tester,
      find.text(de.entwGespeichert),
      max: const Duration(seconds: 90),
    );
    await ruhe(tester, 2000);
    // MOB-137: weitere Änderungen.
    await app.sitzung.db.fuehreAus(BeschreibungSetzen([id], 'neu'));
    await app.sitzung.db.fuehreAus(BewertungSetzen([id], 4));
    await app.sitzung.db.fuehreAus(
      OrtSetzen([id], 50.1, 8.6, land: 'DE', stadt: 'Prüfort'),
    );
    await ruhe(tester, 3000);
    expect(sha(await original(v, id)), vorher, reason: 'Original byte-gleich');
    final a = await amServer(hauptDirekt, konto, id);
    print('MOB-134 nach Speichern am Server: ${a?.description} ${a?.rating}');
    // MOB-135: Entwicklung entfernen.
    await schliesse(tester);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.entwTitel), ms: 3000);
    await tippe(tester, find.text(de.entwEntfernen));
    await warte(tester, find.text(de.entwEntfernenFrage));
    await tippe(
      tester,
      find.widgetWithText(FilledButton, de.entwEntfernen).evaluate().isNotEmpty
          ? find.widgetWithText(FilledButton, de.entwEntfernen)
          : find.text(de.entwEntfernen).last,
      ms: 2000,
    );
    await ruhe(tester, 2000);
    expect(sha(await original(v, id)), vorher);
  });

  pruefung('MOB-136 Entwickeln: HEIC rechnet aus der Vorschau', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K136');
    final v = await api(hauptDirekt, konto);
    await hochladenPfad(v, '$fixturesMob/probe.heic');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.entwTitel), ms: 3000);
    await warte(
      tester,
      find.text(de.entwVorschauQuelle),
      max: const Duration(seconds: 40),
    );
  });

  pruefung('MOB-138 MOB-139 Diashow aus Auswahl, nur Videos', (tester) async {
    final k = await kontoMitFotos('K138', 5);
    await hochladenDatei(k.v, 'video_5s.mp4');
    await hochladenPfad(k.v, '$fixturesOrdner/video_hoch_3s.mov');
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 7);
    final namen = rasterNamen(tester);
    final videos = [
      for (var i = 0; i < namen.length; i++)
        if (!namen[i].endsWith('.jpg')) i,
    ];
    final bilder = [
      for (var i = 0; i < namen.length; i++)
        if (namen[i].endsWith('.jpg')) i,
    ];
    await lang(tester, kacheln().at(videos[0]));
    await tippe(tester, kacheln().at(videos[1]));
    await tippe(tester, _aktion(de.diashow));
    await meldung(tester, de.diashowKeineFotos);
    await tippe(tester, tooltip(de.auswahlAufheben));
    await lang(tester, kacheln().at(bilder[0]));
    for (final i in [...bilder.skip(1), videos[0]]) {
      await tippe(tester, kacheln().at(i), ms: 200);
    }
    await tippe(tester, _aktion(de.diashow), ms: 1500);
    final d = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Diashow',
    );
    await warte(tester, d);
    expect(
      ((tester.widget(d) as dynamic).fotos as List).length,
      5,
      reason: 'Video fehlt',
    );
    await ruhe(tester, 5000);
    await tester.tapAt(tester.getCenter(d));
    await ruhe(tester, 500);
    for (final t in [de.diashowVorige, de.diashowNaechste, de.diashowBeenden]) {
      expect(tooltip(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining(' / 5'), findsOneWidget);
    await tippe(tester, tooltip(de.diashowAnhalten));
    expect(tooltip(de.diashowWeiter), findsOneWidget);
    await tippe(tester, tooltip(de.diashowNaechste));
    await tippe(tester, tooltip(de.diashowVorige));
    await tippe(tester, tooltip(de.diashowWeiter));
    await ruhe(tester, 5000);
    final knopfOpazitaet = tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: tooltip(de.diashowBeenden),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    expect(knopfOpazitaet, 0, reason: 'Knöpfe nach 4 s weg');
    await tester.tapAt(tester.getCenter(d));
    await ruhe(tester, 400);
    expect(
      tooltip(de.diashowAlsVideo),
      findsOneWidget,
      reason: 'iOS: Als Video speichern',
    );
    await tippe(tester, tooltip(de.diashowAlsVideo));
    await warte(tester, find.text(de.diashowVideoTitel));
    expect(
      find.text(de.diashowVideoUmfang(5, 20)).evaluate().isNotEmpty ||
          find.textContaining('5 Fotos').evaluate().isNotEmpty,
      isTrue,
    );
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    double opazitaet() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: tooltip(de.diashowBeenden),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;
    if (opazitaet() == 0) {
      await tester.tapAt(tester.getCenter(d));
      await ruhe(tester, 400);
    }
    await tippe(tester, tooltip(de.diashowBeenden));
    await warteWeg(tester, d);
  });
}

// --------------------------------------------------------------------
// Konto

void kontoTests() {
  pruefung('MOB-141 Kontoseite: Verbindung, Fassung, Unterstützen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K141', 1);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await kontoOeffnen(tester);
    expect(find.text(hostAdresse), findsOneWidget);
    expect(find.text(de.kontoKontoGeraet(k.konto, 'Telefon')), findsOneWidget);
    await warte(tester, find.text(de.kontoAbgeglichen));
    await rolleZu(tester, find.text(de.kontoFassung));
    await warte(tester, find.textContaining('App 0.19.9 (57) · Server '));
    print(
      'MOB-141 Fassung: ${sichtbareTexte(tester).where((t) => t.startsWith('App ')).toList()}, '
      'serverfassung ${app.sitzung.serverfassung}',
    );
    await rolleZu(tester, find.text(de.kontoUnterstuetzen));
    expect(find.text(de.kontoUnterstuetzen), findsOneWidget);
  });

  pruefung('MOB-142 Abmelden löscht die Kopie, Server bleibt', (tester) async {
    final k = await kontoMitFotos('K142', 2);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await oeffneKachel(tester, 0);
    await ruhe(tester, 2500);
    await schliesse(tester);
    final token = app.sitzung.verbindung!.token;
    final bilder = app.bibliothek
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .length;
    expect(bilder, greaterThan(0), reason: 'vorher Bilder im App-Ordner');
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await warte(tester, find.text(de.kontoAbmeldenTitel));
    expect(find.text(de.kontoAbmeldenText), findsOneWidget);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(find.widgetWithText(AppBar, de.kontoTitel), findsOneWidget);
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(
      tester,
      find.widgetWithText(FilledButton, de.kontoAbmelden),
      ms: 2500,
    );
    await warte(tester, find.text(de.anmeldenTitel));
    expect(
      app.bibliothek.existsSync(),
      isFalse,
      reason: 'Kopie samt Bildern weg',
    );
    final r = await Serververbindung(
      hauptDirekt,
      token,
    ).anfrage('GET', 'api/v1/abgleich/stand');
    expect(r.statusCode, 401, reason: 'Token gilt nicht mehr');
    final g = (await k.v.hole('api/v1/geraete'))['geraete']! as List;
    expect(g.cast<Map>().where((x) => x['name'] == 'Telefon'), isEmpty);
    expect(
      await amServer(hauptDirekt, k.konto, k.ids[0]),
      isNotNull,
      reason: 'am Server bleibt alles',
    );
  });

  pruefung('MOB-143 Abmelden ohne Netz und mit wartenden Änderungen', (
    tester,
  ) async {
    final k = await kontoMitFotos('K143', 1);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await proxyAus();
    await ruhe(tester, 1000);
    await app.sitzung.db.fuehreAus(FavoritSetzen([k.ids[0]], true));
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(
      tester,
      find.widgetWithText(FilledButton, de.kontoAbmelden),
      ms: 2500,
    );
    await warte(
      tester,
      find.text(de.anmeldenTitel),
      max: const Duration(seconds: 90),
    );
    expect(app.bibliothek.existsSync(), isFalse);
    await proxyAn();
    final g = (await k.v.hole('api/v1/geraete'))['geraete']! as List;
    expect(g.cast<Map>().where((x) => x['name'] == 'Telefon'), hasLength(1));
    expect(
      (await amServer(hauptDirekt, k.konto, k.ids[0]))!.isFavorite,
      isFalse,
    );
  });

  pruefung('MOB-144 Zwischenspeicher: Grenze und Leeren', (tester) async {
    final k = await kontoMitFotos('K144', 4);
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 4);
    await oeffneKachel(tester, 0);
    await ruhe(tester, 2000);
    await schliesse(tester);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoZwischenspeicher));
    await warte(tester, find.textContaining('von 2.00 GB'));
    await tippe(tester, find.text(de.kontoZwischenspeicher));
    await warte(tester, find.text(de.kontoZwischenspeicherGrenze));
    for (final t in [
      '512.0 MB',
      '1.00 GB',
      '2.00 GB',
      '5.00 GB',
      de.kontoZwischenspeicherOhneGrenze,
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tippe(tester, find.text('512.0 MB'), ms: 1500);
    expect(app.sitzung.zwischenspeicherGrenzeMb, 512);
    await warte(tester, find.textContaining('von 512.0 MB'));
    final vorher = await app.sitzung.zwischenspeicher.groesse();
    await tippe(tester, find.text(de.kontoZwischenspeicherLeeren), ms: 1500);
    final nachher = await app.sitzung.zwischenspeicher.groesse();
    print('MOB-144 belegt vor/nach Leeren: $vorher / $nachher');
    expect(nachher, lessThanOrEqualTo(vorher));
    await tippe(tester, find.text(de.kontoZwischenspeicher));
    await tippe(
      tester,
      find.text(de.kontoZwischenspeicherOhneGrenze),
      ms: 1500,
    );
    await warte(tester, find.textContaining(', ohne Grenze –'));
  });

  pruefung('MOB-145 Geräte des Kontos ansehen und abmelden', (tester) async {
    final k = await kontoMitFotos('K145', 1);
    final tablet = await holeToken(hauptDirekt, k.konto, geraet: 'Tablet');
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.eigenGeraete));
    await warte(tester, find.text('Telefon ${de.eigenDiesesTelefon}'));
    expect(find.text('Tablet'), findsOneWidget);
    expect(find.textContaining('zuletzt '), findsWidgets);
    final tabletZeile = find.ancestor(
      of: find.text('Tablet'),
      matching: find.byType(ListTile),
    );
    await tippe(
      tester,
      find.descendant(
        of: tabletZeile,
        matching: find.text(de.eigenGeraetAbmelden),
      ),
    );
    await warte(tester, find.text(de.eigenGeraetAbmeldenFrage('Tablet')));
    await tippe(tester, find.text(de.eigenGeraetAbmelden).last, ms: 2000);
    await warteWeg(tester, find.text('Tablet'));
    final r = await Serververbindung(
      hauptDirekt,
      tablet,
    ).anfrage('GET', 'api/v1/abgleich/stand');
    expect(r.statusCode, 401);
    final eigen = find.ancestor(
      of: find.text('Telefon ${de.eigenDiesesTelefon}'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: eigen, matching: find.text(de.kontoAbmelden)),
      findsOneWidget,
    );
  });

  pruefung('MOB-007 MOB-146 MOB-147 TOTP: Anmeldung, Passwort, neue Codes', (
    tester,
  ) async {
    final server = adresse(Port.kontenProxy);
    final t1 = eindeutig('KontoT');
    await steuer('konto/konten', {'name': t1});
    final e = await totpEinrichten(adresse(Port.konten), t1);
    // Ein neuer Code erst im nächsten Zeitfenster.
    String frisch() => totp(e.geheimnis);
    Future<void> naechstesFenster() async {
      final s = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 30;
      await ruhe(tester, (31 - s) * 1000);
    }

    await starteApp(tester);
    Future<void> bisZumCode() async {
      await schreibe(tester, feld(de.anmeldenAdresse), server.toString());
      await schreibe(tester, feld(de.anmeldenName), t1);
      await schreibe(tester, feld(de.anmeldenPasswort), pw);
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.anmeldenAnmelden),
      );
      await warte(tester, find.text(de.anmeldenCodeHinweis));
    }

    await bisZumCode();
    final codefeld = find.byType(TextField);
    final falsch = frisch() == '000000' ? '111111' : '000000';
    await schreibe(tester, codefeld.first, falsch);
    await tippe(tester, find.text(de.anmeldenBestaetigen));
    await warte(tester, find.text(de.anmeldenFalsch));
    await naechstesFenster();
    await schreibe(tester, codefeld.first, frisch());
    await tippe(tester, find.text(de.anmeldenBestaetigen));
    await warte(
      tester,
      find.byType(NavigationBar),
      max: const Duration(seconds: 40),
    );
    // MOB-147: neue Wiederherstellungscodes.
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.eigenCodesUebrig(e.codes.length)));
    await tippe(
      tester,
      find.text(de.eigenCodesUebrig(e.codes.length)),
      ms: 1200,
    );
    await schreibe(tester, feld(de.eigenTotpCode), falsch);
    await tippe(tester, find.text(de.eigenCodesNeu), ms: 2000);
    final fehlerSicht = sichtbareTexte(tester);
    print('MOB-147 falscher Code: $fehlerSicht');
    await naechstesFenster();
    await schreibe(tester, feld(de.eigenTotpCode), frisch());
    await tippe(tester, find.text(de.eigenCodesNeu), ms: 2000);
    await warte(
      tester,
      find.textContaining('die bisherigen gelten nicht mehr'),
    );
    await tippe(tester, find.text(de.kopieren));
    await meldung(tester, de.eigenCodesKopiert);
    final neueCodes = (await Clipboard.getData('text/plain'))?.text ?? '';
    expect(neueCodes.trim(), isNotEmpty);
    await schliesse(tester);
    // MOB-146: Passwort ändern mit TOTP, anderes Gerät abmelden.
    final neue = neueCodes
        .split(RegExp(r'\s+'))
        .where((c) => c.isNotEmpty)
        .toList();
    // Ein alter Code gilt nicht mehr (MOB-147) …
    final alt0 = Anmeldung(adresse(Port.konten));
    final s0 = await alt0.anmelden(t1, pw, geraet: 'Alt');
    final alt = s0 is AnmeldungCode
        ? await alt0.bestaetige(s0.vorgang, e.codes.first)
        : s0;
    alt0.schliesse();
    print('MOB-147 alter Code nach Neuerzeugen: $alt');
    expect(alt, isA<AnmeldungAbgewiesen>(), reason: 'alter Code abgewiesen');
    // … das zweite Gerät meldet sich mit einem neuen an.
    final zweites = await holeTokenTotp(
      adresse(Port.konten),
      t1,
      e.geheimnis,
      neue[1],
    );
    await rolleZu(tester, find.text(de.eigenPasswortAendern));
    await tippe(tester, find.text(de.eigenPasswortAendern), ms: 1200);
    expect(feld(de.eigenTotpCode), findsOneWidget);
    await schreibe(tester, feld(de.eigenPasswortAlt), pw);
    await schreibe(tester, feld(de.eigenPasswortNeu), '${pw}neu');
    await schreibe(tester, feld(de.eigenPasswortNochmal), '${pw}anders');
    await tippe(tester, find.text(de.eigenAendern));
    await warte(tester, find.text(de.eigenPasswortUngleich));
    await schreibe(tester, feld(de.eigenPasswortAlt), 'falsches-Passwort-9');
    await schreibe(tester, feld(de.eigenPasswortNochmal), '${pw}neu');
    await naechstesFenster();
    await schreibe(tester, feld(de.eigenTotpCode), frisch());
    await tippe(tester, find.text(de.eigenAendern), ms: 2000);
    print(
      'MOB-146 falsches altes Passwort: ${sichtbareTexte(tester).where((t) => t.length > 8).toList()}',
    );
    expect(find.text(de.eigenPasswortGeaendert), findsNothing);
    await schreibe(tester, feld(de.eigenPasswortAlt), pw);
    await naechstesFenster();
    await schreibe(tester, feld(de.eigenTotpCode), frisch());
    final andere = find.widgetWithText(
      CheckboxListTile,
      de.eigenAndereAbmelden,
    );
    if (tester.widget<CheckboxListTile>(andere).value != true) {
      await tippe(tester, andere);
    }
    await tippe(tester, find.text(de.eigenAendern), ms: 2500);
    await warte(tester, find.text(de.eigenPasswortGeaendert));
    expect(
      tester.widget<TextField>(feld(de.eigenPasswortAlt)).controller!.text,
      isEmpty,
    );
    final r = await Serververbindung(
      adresse(Port.konten),
      zweites,
    ).anfrage('GET', 'api/v1/abgleich/stand');
    expect(r.statusCode, 401, reason: 'zweites Gerät abgemeldet');
    await schliesse(tester);
    // MOB-007: abmelden, mit Wiederherstellungscode anmelden, Code zweimal.
    final codes = neue;
    await rolleZu(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(
      tester,
      find.widgetWithText(FilledButton, de.kontoAbmelden),
      ms: 2500,
    );
    await warte(tester, find.text(de.anmeldenTitel));
    Future<void> mitCode(String c) async {
      await schreibe(tester, feld(de.anmeldenAdresse), server.toString());
      await schreibe(tester, feld(de.anmeldenName), t1);
      await schreibe(tester, feld(de.anmeldenPasswort), '${pw}neu');
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.anmeldenAnmelden),
      );
      await warte(tester, find.text(de.anmeldenCodeHinweis));
      await schreibe(tester, find.byType(TextField).first, c);
      await tippe(tester, find.text(de.anmeldenBestaetigen));
    }

    await mitCode(codes.first);
    await warte(
      tester,
      find.byType(NavigationBar),
      max: const Duration(seconds: 40),
    );
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(
      tester,
      find.widgetWithText(FilledButton, de.kontoAbmelden),
      ms: 2500,
    );
    await warte(tester, find.text(de.anmeldenTitel));
    await mitCode(codes.first);
    await warte(tester, find.text(de.anmeldenFalsch));
    // Alter Code (vor dem Neuerzeugen) wird abgewiesen (MOB-147).
    await tippe(tester, find.text(de.anmeldenBestaetigen));
    await schreibe(tester, find.byType(TextField).first, e.codes.last);
    await tippe(tester, find.text(de.anmeldenBestaetigen));
    await ruhe(tester, 2000);
    print(
      'MOB-147 alter Code: ${sichtbareTexte(tester).where((t) => t.length > 8).toList()}',
    );
  });

  pruefung('MOB-008 Erzwungene TOTP-Einrichtung und einmalige Codes', (
    tester,
  ) async {
    final t2 = eindeutig('KontoT');
    await steuer('konto/konten', {'name': t2});
    await starteApp(tester);
    await schreibe(
      tester,
      feld(de.anmeldenAdresse),
      adresse(Port.kontenProxy).toString(),
    );
    await schreibe(tester, feld(de.anmeldenName), t2);
    await schreibe(tester, feld(de.anmeldenPasswort), pw);
    await tippe(tester, find.widgetWithText(FilledButton, de.anmeldenAnmelden));
    await warte(tester, find.text(de.anmeldenTotpTitel));
    final geheim = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(
      RegExp(r'^([A-Z2-7]{4} )+[A-Z2-7]{1,4}$').hasMatch(geheim),
      isTrue,
      reason: 'Vierergruppen: $geheim',
    );
    // Nicht antippen: iOS öffnet otpauth:// in der Passwörter-App, die App
    // ginge in den Hintergrund (im Lauf 3 beobachtet).
    expect(find.text(de.anmeldenTotpOeffnen), findsOneWidget);
    await tippe(tester, find.text(de.kopieren));
    final kopiert = (await Clipboard.getData('text/plain'))!.text!;
    expect(kopiert, geheim.replaceAll(' ', ''));
    await schreibe(tester, find.byType(TextField).first, totp(kopiert));
    await tippe(tester, find.text(de.anmeldenBestaetigen));
    await warte(tester, find.text(de.anmeldenCodesTitel));
    expect(find.text(de.anmeldenCodesText), findsOneWidget);
    expect(
      de.anmeldenCodesText,
      contains('sie werden nicht noch einmal gezeigt.'),
    );
    await tippe(tester, find.text(de.kopieren));
    final codes = (await Clipboard.getData('text/plain'))!.text!;
    expect(codes.split('\n').length, 10);
    await tippe(tester, find.text(de.weiter));
    await warte(
      tester,
      find.byType(NavigationBar),
      max: const Duration(seconds: 40),
    );
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.eigenCodesUebrig(10)));
    expect(find.textContaining(codes.split('\n').first), findsNothing);
  });

  pruefung('MOB-150 MOB-151 MOB-152 MOB-153 MOB-154 Konten verwalten', (
    tester,
  ) async {
    final server = adresse(Port.verwProxy);
    final direkt = adresse(Port.verw);
    final a = await kontoAnlegen(direkt, 'KontoA');
    final b = await kontoAnlegen(direkt, 'KontoB');
    final vb = await api(direkt, b);
    await hochladen(vb, jpeg(), 'b.jpg');
    // Konto A mit TOTP (auf diesem Server frei, also selbst einrichten).
    // Konto B nach Fehlversuchen sperren.
    for (var i = 0; i < 5; i++) {
      await anmelden(direkt, b, passwort: 'falsch-falsch-$i');
    }
    await starteApp(tester, server: server, konto: 'Verwalter');
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontenVerwalten));
    await tippe(tester, find.text(de.kontenVerwalten), ms: 1500);
    await warte(tester, find.text(de.kontenTitel));
    await warte(tester, find.text('Verwalter · ${de.kontoDu}'));
    expect(find.textContaining(de.kontoGesperrt), findsOneWidget);
    await tippe(tester, find.text('Verwalter · ${de.kontoDu}'));
    expect(
      find.text(de.kontoPasswortSetzen),
      findsNothing,
      reason: 'eigenes Konto reagiert nicht',
    );
    await tippe(tester, find.text(a));
    expect(find.text(de.kontoPasswortSetzen), findsOneWidget);
    expect(find.text(de.entfernen), findsOneWidget);
    await schliesse(tester);
    await tippe(tester, find.text(b));
    expect(find.text(de.kontoEntsperren), findsOneWidget);
    await tippe(tester, find.text(de.kontoEntsperren), ms: 1500);
    await meldung(tester, de.kontoErledigt);
    expect(
      await anmelden(direkt, b),
      isA<AnmeldungFertig>(),
      reason: 'wieder anmeldbar',
    );
    // MOB-151: Konto anlegen.
    await tippe(tester, find.text(de.kontoAnlegen), ms: 1000);
    final dialog = find.byType(AlertDialog);
    Finder f(String l) => find.descendant(of: dialog, matching: feld(l));
    await schreibe(tester, f(de.anmeldenName), 'a');
    await schreibe(tester, f(de.anmeldenPasswort), pw);
    await schreibe(tester, f(de.anmeldenPasswortWiederholen), pw);
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
    );
    await warte(tester, find.text(de.anmeldenNameUngueltig));
    final c = eindeutig('KontoC');
    await schreibe(tester, f(de.anmeldenName), c);
    await schreibe(tester, f(de.anmeldenPasswort), 'kurz');
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
    );
    await warte(tester, find.text(de.anmeldenPasswortZuKurz(12)));
    await schreibe(tester, f(de.anmeldenPasswort), pw);
    await schreibe(tester, f(de.anmeldenPasswortWiederholen), '${pw}x');
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
    );
    await warte(tester, find.text(de.anmeldenPasswortUngleich));
    await schreibe(tester, f(de.anmeldenPasswortWiederholen), pw);
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
      ms: 2000,
    );
    await meldung(tester, de.kontoErledigt);
    await warte(tester, find.text(c));
    final vc = await api(direkt, c);
    final kc = await vc.anfrage('GET', 'api/v1/konten');
    expect(kc.statusCode, 403, reason: 'Konto C ohne Verwaltung');
    // MOB-152: Passwort neu setzen und TOTP zurücksetzen bei Konto B.
    final tokB = await holeToken(direkt, b, geraet: 'B-Telefon');
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.kontoPasswortSetzen), ms: 1000);
    await warte(tester, find.text(de.kontoPasswortSetzenText(b)));
    await schreibe(tester, f(de.anmeldenPasswort), '${pw}B');
    await schreibe(tester, f(de.anmeldenPasswortWiederholen), '${pw}B');
    await tippe(
      tester,
      find.descendant(of: dialog, matching: find.text(de.speichern)),
      ms: 2000,
    );
    await meldung(tester, de.kontoErledigt);
    final rb = await Serververbindung(
      direkt,
      tokB,
    ).anfrage('GET', 'api/v1/abgleich/stand');
    expect(rb.statusCode, 401, reason: 'Geräte von B abgemeldet');
    await ruhe(tester, 4500);
    await tippe(tester, find.text(a));
    if (find.text(de.kontoTotpZuruecksetzen).evaluate().isNotEmpty) {
      await tippe(tester, find.text(de.kontoTotpZuruecksetzen), ms: 1500);
      await meldung(tester, de.kontoTotpZurueckgesetzt(a));
    } else {
      print('MOB-152 Konto A ohne TOTP: keine Zeile „TOTP zurücksetzen“');
      await schliesse(tester);
    }
    await ruhe(tester, 4500);
    // MOB-153: Konto B entfernen.
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.entfernen), ms: 1000);
    await warte(tester, find.text(de.kontoEntfernenTitel(b)));
    expect(find.text(de.kontoEntfernenText), findsOneWidget);
    await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
    expect(find.text(b), findsOneWidget);
    await tippe(tester, find.text(b));
    await tippe(tester, find.text(de.entfernen), ms: 1000);
    await tippe(tester, find.text(de.entfernen).last, ms: 2000);
    await warteWeg(tester, find.text(b));
    final ab = await anmelden(direkt, b, passwort: '${pw}B');
    expect(ab, isA<AnmeldungAbgewiesen>());
    // MOB-154: Konto A sieht keine Verwaltung.
    await starteApp(tester, server: server, konto: a);
    await kontoOeffnen(tester);
    await ruhe(tester, 2500);
    await rolleZu(tester, find.text(de.kontoAbmelden));
    expect(find.text(de.kontenVerwalten), findsNothing);
    expect(find.text(de.verwAnstossen), findsNothing);
    expect(find.text(de.verwJetztSichern), findsNothing);
    final va = await api(direkt, a);
    expect((await va.anfrage('GET', 'api/v1/konten')).statusCode, 403);
  });

  pruefung('MOB-155 Verwalter: Auswertung anstossen', (tester) async {
    await starteApp(
      tester,
      server: adresse(Port.verwProxy),
      konto: 'Verwalter',
    );
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontenVerwalten));
    await warte(tester, find.text(de.verwAnstossen));
    expect(find.text(de.verwAuswertungRuht), findsOneWidget);
    await tippe(tester, find.text(de.verwAnstossen), ms: 2500);
    print(
      'MOB-155 nach Anstossen: ${sichtbareTexte(tester).where((t) => t.startsWith('Auswertung')).toList()}',
    );
    expect(
      find.text(de.verwJetztSichern),
      findsNothing,
      reason: 'ohne eingerichtete Sicherung',
    );
  });
}

// --------------------------------------------------------------------
// Einstellungen

void einstellungenTests() {
  pruefung('MOB-156 Sprache der App', (tester) async {
    final k = await kontoMitFotos('K156', 1);
    var app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await bibOeffnen(tester, de.bibEinstellungen);
    await tippe(tester, find.text('English'), ms: 1500);
    await warte(
      tester,
      find.text('Library settings').evaluate().isNotEmpty
          ? find.text('Library settings')
          : find.textContaining('Language'),
    );
    app = await neuStarten(tester, app);
    await warte(tester, find.text('Photos'));
    expect(app.sitzung.sprache, 'en');
    await bereich(tester, 'Library');
    await rolleZu(tester, find.text('Settings'));
    await tippe(tester, find.text('Settings'));
    await tippe(tester, find.text('Automatic'), ms: 1500);
    await warte(tester, find.text(de.einstTitel));
  });

  pruefung('MOB-157 Einstellungen der Bibliothek gelten für alle Geräte', (
    tester,
  ) async {
    final k = await kontoMitFotos('K157', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await bibOeffnen(tester, de.bibEinstellungen);
    await warte(tester, find.text(de.einstHinweis));
    Future<void> schalte(String titel) async {
      final zeile = find
          .ancestor(of: find.text(titel), matching: find.byType(Row))
          .first;
      final sw = find.descendant(of: zeile, matching: find.byType(Switch));
      await rolleZu(tester, find.text(titel));
      await tippe(tester, sw.first);
      await meldung(tester, de.einstGespeichert);
      await ruhe(tester, 4200);
    }

    await schalte(de.einstFormateStapeln);
    await schalte(de.einstUebersetzen);
    await ruhe(tester, 2000);
    final e = await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => bibliothekseinstellungen(r.db),
    );
    print(
      'MOB-157 am Server: stapeln ${e.formateStapeln} übersetzen ${e.sucheUebersetzen}',
    );
    expect(e.formateStapeln, isTrue);
  });

  // Behoben in #418: Die Frist geht auch, wenn das Feld den Fokus verliert
  // oder die Seite ohne Bestätigen geschlossen wird.
  pruefung('MOB-158 Papierkorb automatisch leeren: Frist', (tester) async {
    final k = await kontoMitFotos('K158', 1);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await bibOeffnen(tester, de.bibEinstellungen);
    final zeile = find
        .ancestor(of: find.text(de.einstPapierkorb), matching: find.byType(Row))
        .first;
    await tippe(
      tester,
      find.descendant(of: zeile, matching: find.byType(Switch)),
    );
    await meldung(tester, de.einstGespeichert);
    expect(find.text(de.einstPapierkorbText), findsOneWidget);
    final tage = find
        .ancestor(of: find.text(de.einstNach), matching: find.byType(Row))
        .first;
    final feldTage = find.descendant(
      of: tage,
      matching: find.byType(TextField),
    );
    Future<int> amServer0() async => (await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => bibliothekseinstellungen(r.db),
    )).papierkorbTage;
    await schreibe(tester, feldTage, '7');
    await absenden(tester, feldTage);
    await ruhe(tester, 3000);
    expect(await amServer0(), 7);
    await schreibe(tester, feldTage, '0');
    await absenden(tester, feldTage);
    await ruhe(tester, 3000);
    expect(await amServer0(), 1);
    await schreibe(tester, feldTage, '9999');
    await absenden(tester, feldTage);
    await ruhe(tester, 3000);
    expect(await amServer0(), 3650);
    await schreibe(tester, feldTage, '14');
    await schliesse(tester);
    await ruhe(tester, 3000);
    final nach = await amServer0();
    print('MOB-158 „14“ ohne Bestätigen, am Server: $nach');
    expect(nach, 14);
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
    await tester.drag(regler.at(0), const Offset(400, 0));
    await ruhe(tester, 2000);
    expect(
      find.text(de.einstAb('90 %')).evaluate().isNotEmpty ||
          find.textContaining('90').evaluate().isNotEmpty,
      isTrue,
    );
    await rolleZu(tester, find.text(de.einstSchwelle));
    final s = tester.widget<Slider>(regler.last);
    print('MOB-159 Schwelle min ${s.min} max ${s.max} wert ${s.value}');
    expect(s.min, closeTo(0.2, 0.001));
    expect(s.max, closeTo(0.8, 0.001));
    await tester.ensureVisible(regler.last);
    await ruhe(tester, 400);
    await tester.drag(regler.last, const Offset(60, 0));
    await ruhe(tester, 3000);
    print(
      'MOB-159 Schwelle nach dem Ziehen: ${tester.widget<Slider>(regler.last).value}',
    );
    final e = await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => bibliothekseinstellungen(r.db),
    );
    print(
      'MOB-159 am Server: vorschläge ${e.vorschlaegeAb} schwelle ${e.gesichtsschwelle}',
    );
    expect(e.vorschlaegeAb, closeTo(0.9, 0.001));
  });
}

// --------------------------------------------------------------------
// Sicherung der Kamerarolle (Mediathek des Simulators)

var _mediathekNr = 0;

/// Legt [n] neue Testfotos in die Mediathek des Simulators.
Future<List<AssetEntity>> _inMediathek(int n, {String praefix = 'pv'}) async {
  final l = <AssetEntity>[];
  for (var i = 0; i < n; i++) {
    _mediathekNr++;
    l.add(
      await PhotoManager.editor.saveImage(
        jpeg(breite: 400, hoehe: 300, farbe: 0x203040 + _mediathekNr * 977),
        filename:
            '${praefix}_${DateTime.now().millisecondsSinceEpoch}_$_mediathekNr.jpg',
        creationDate: DateTime(2025, 3, 1).add(Duration(minutes: _mediathekNr)),
      ),
    );
  }
  return l;
}

Future<int> _mediathekAnzahl() => PhotoManager.getAssetCount();

Future<int> _serverAnzahl(String konto) => mitRechner(
  hauptDirekt,
  konto,
  (r) async =>
      (await r.db
              .customSelect(
                'SELECT count(*) AS n FROM assets WHERE is_trashed = 0',
              )
              .getSingle())
          .read<int>('n'),
);

Future<void> _sicherungsseite(WidgetTester tester) async {
  await kontoOeffnen(tester);
  await rolleZu(tester, find.text(de.sicherungTitel));
  await tippe(tester, find.text(de.sicherungTitel), ms: 1200);
  await warte(tester, find.text(de.sicherungAn));
}

Future<void> _schalter(WidgetTester tester, String titel, bool an) async {
  final z = find.widgetWithText(SwitchListTile, titel);
  await rolleZu(tester, z);
  if (tester.widget<SwitchListTile>(z).value != an) {
    await tippe(tester, z, ms: 1200);
  }
}

void sicherungTests() {
  pruefung(
    'MOB-170 MOB-196 Sicherung einschalten; anderes Konto beginnt von vorn',
    (tester) async {
      await PhotoManager.requestPermissionExtend();
      await _inMediathek(2);
      final n = await _mediathekAnzahl();
      final a = await kontoAnlegen(hauptDirekt, 'K170A');
      await starteApp(tester, server: hauptApp, konto: a);
      await _sicherungsseite(tester);
      for (final (t, an) in [
        (de.sicherungVideos, true),
        (de.sicherungNurWlan, true),
        (de.sicherungNurBeimLaden, false),
      ]) {
        final z = find.widgetWithText(SwitchListTile, t);
        await rolleZu(tester, z);
        expect(tester.widget<SwitchListTile>(z).value, an, reason: t);
      }
      expect(find.text(de.sicherungAlleFotos), findsOneWidget);
      await rolleZu(tester, find.text(de.sicherungAn), schritt: -250);
      await _schalter(tester, de.sicherungAn, true);
      var fortschritt = false;
      await warteBis(
        tester,
        () {
          if (find.textContaining('Lädt ').evaluate().isNotEmpty) {
            fortschritt = true;
          }
          return find.text(de.sicherungStand(n, n)).evaluate().isNotEmpty;
        },
        max: const Duration(minutes: 4),
        grund: '$n von $n gesichert',
      );
      print('MOB-170 Fortschritt „Lädt …“ gesehen: $fortschritt; Mediathek $n');
      expect(find.textContaining('Zuletzt: '), findsOneWidget);
      await zurueck(tester);
      await rolleZu(tester, find.text(de.sicherungTitel));
      expect(find.text(de.sicherungStand(n, n)), findsOneWidget);
      expect(await _serverAnzahl(a), n);
      // MOB-196: abmelden, mit Konto B anmelden.
      final b = await kontoAnlegen(hauptDirekt, 'K196B');
      await starteApp(tester, server: hauptApp, konto: b);
      await _sicherungsseite(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, de.sicherungAn),
            )
            .value,
        isFalse,
      );
      print(
        'MOB-196 Seite bei Konto B (aus): '
        '${sichtbareTexte(tester).where((t) => t.contains('gesichert')).toList()}',
      );
      await _schalter(tester, de.sicherungAn, true);
      await warteBis(
        tester,
        () => find.text(de.sicherungStand(n, n)).evaluate().isNotEmpty,
        max: const Duration(minutes: 4),
        grund: 'Konto B gesichert',
      );
      expect(await _serverAnzahl(b), n);
      expect(await _serverAnzahl(a), n, reason: 'bei A ändert sich nichts');
    },
  );

  pruefung('MOB-179 Videos sichern ausschalten', (tester) async {
    await PhotoManager.requestPermissionExtend();
    final konto = await kontoAnlegen(hauptDirekt, 'K179');
    await PhotoManager.editor.saveVideo(
      File('$fixturesOrdner/video_5s.mp4'),
      title: 'pv_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    await _inMediathek(1);
    final videos = await PhotoManager.getAssetCount(type: RequestType.video);
    final alle = await _mediathekAnzahl();
    await starteApp(tester, server: hauptApp, konto: konto);
    await _sicherungsseite(tester);
    await _schalter(tester, de.sicherungVideos, false);
    await rolleZu(tester, find.text(de.sicherungAn), schritt: -250);
    await _schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () async => await _serverAnzahl(konto) >= alle - videos,
      max: const Duration(minutes: 4),
      grund: 'Fotos oben',
    );
    await ruhe(tester, 3000);
    expect(await _serverAnzahl(konto), alle - videos, reason: 'Videos bleiben');
    await zurueck(tester);
    await zurueck(tester);
    await warte(
      tester,
      find.text(de.lokalAnzahl(videos)),
      max: const Duration(seconds: 40),
    );
    await _sicherungsseite(tester);
    await _schalter(tester, de.sicherungVideos, true);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt));
    await warteBis(
      tester,
      () async => await _serverAnzahl(konto) == alle,
      max: const Duration(minutes: 4),
      grund: 'Video folgt',
    );
  });

  pruefung('MOB-180 Nur gewählte Alben sichern', (tester) async {
    await PhotoManager.requestPermissionExtend();
    final konto = await kontoAnlegen(hauptDirekt, 'K180');
    final album = await PhotoManager.editor.darwin.createAlbum(
      'Urlaubstest${DateTime.now().millisecondsSinceEpoch % 100000}',
    );
    expect(album, isNotNull);
    final drei = await _inMediathek(3, praefix: 'urlaub');
    for (final a in drei) {
      await PhotoManager.editor.copyAssetToPath(asset: a, pathEntity: album!);
    }
    final alle = await _mediathekAnzahl();
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await _sicherungsseite(tester);
    await rolleZu(tester, find.text(de.sicherungAlben));
    await tippe(tester, find.text(de.sicherungAlben), ms: 1500);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, de.sicherungAlleFotos),
          )
          .value,
      isTrue,
    );
    await rolleZu(tester, find.text(album!.name));
    await tippe(tester, find.text(album.name), ms: 800);
    await zurueck(tester);
    await warte(tester, find.text(de.sicherungAlbenAnzahl(1)));
    await rolleZu(tester, find.text(de.sicherungAn), schritt: -250);
    await _schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () async => await _serverAnzahl(konto) >= 3,
      max: const Duration(minutes: 3),
      grund: '3 Fotos des Albums',
    );
    await ruhe(tester, 4000);
    expect(await _serverAnzahl(konto), 3, reason: 'nur das Album');
    await zurueck(tester);
    await zurueck(tester);
    await ruhe(tester, 3000);
    final zeile = sichtbareTexte(
      tester,
    ).where((t) => t.contains('nur auf dem Telefon')).toList();
    print(
      'MOB-180 Zeitleiste zählt: $zeile (Mediathek $alle, Album 3); ungesichert ${app.sitzung.sicherung?.ungesichert?.length}',
    );
    // Abhaken des letzten Albums: wieder alle Fotos.
    await _sicherungsseite(tester);
    await rolleZu(tester, find.text(de.sicherungAlben));
    await tippe(tester, find.text(de.sicherungAlben), ms: 1500);
    await rolleZu(tester, find.text(album.name));
    await tippe(tester, find.text(album.name), ms: 800);
    // Mit jedem Lauf kommt ein Album dazu: „Alle Fotos“ steht dann oben
    // ausserhalb des Bildes.
    await rolleZu(
      tester,
      find.widgetWithText(CheckboxListTile, de.sicherungAlleFotos),
      schritt: -250,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, de.sicherungAlleFotos),
          )
          .value,
      isTrue,
    );
    await zurueck(tester);
    await warte(tester, find.text(de.sicherungAlleFotos));
    // „Jetzt sichern“ steht über den Alben.
    await rolleZu(tester, find.text(de.sicherungJetzt), schritt: -250);
    await tippe(tester, find.text(de.sicherungJetzt));
    // Gezählt wird am Telefon: Die Testbilder früherer Läufe sind gleich,
    // und der Server nimmt jedes nur einmal – seine Zahl erreicht die der
    // Mediathek dann nie.
    await warteBis(
      tester,
      () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
      max: const Duration(minutes: 4),
      grund: 'übrige gesichert',
    );
    expect(
      zeile,
      isEmpty,
      reason: 'nur Fotos der Auswahl zählen als ungesichert',
    );
  });

  pruefung(
    'MOB-183 MOB-189 „Jetzt sichern“ sagt, wie es ausging; neue Fotos gleich',
    (tester) async {
      await PhotoManager.requestPermissionExtend();
      final konto = await kontoAnlegen(hauptDirekt, 'K183');
      await starteApp(tester, server: hauptApp, konto: konto);
      await _sicherungsseite(tester);
      await rolleZu(tester, find.text(de.sicherungJetzt));
      await tippe(tester, find.text(de.sicherungJetzt));
      await meldung(tester, de.jetztAus);
      expect(find.text(de.jetztEinrichten), findsOneWidget);
      await meldungenWeg(tester);
      await _schalter(tester, de.sicherungAn, true);
      final alle = await _mediathekAnzahl();
      await warteBis(
        tester,
        () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
        max: const Duration(minutes: 4),
        grund: 'erster Lauf',
      );
      // MOB-189: drei neue Fotos bei offener App.
      final vorher = await _serverAnzahl(konto);
      await _inMediathek(3, praefix: 'neu');
      final t0 = DateTime.now();
      await warteBis(
        tester,
        () async => await _serverAnzahl(konto) >= vorher + 3,
        max: const Duration(seconds: 60),
        grund: 'neue Fotos von selbst',
      );
      print(
        'MOB-189 neue Fotos nach ${DateTime.now().difference(t0).inSeconds} s auf dem Server',
      );
      await ruhe(tester, 2000);
      await rolleZu(tester, find.text(de.sicherungJetzt));
      await tippe(tester, find.text(de.sicherungJetzt));
      await meldung(
        tester,
        de.jetztAllesSicher,
        max: const Duration(seconds: 60),
      );
      // Ohne Netz.
      await meldungenWeg(tester);
      await proxyAus();
      await _inMediathek(1, praefix: 'offline');
      await ruhe(tester, 3000);
      if (find.text(de.sicherungJetzt).evaluate().isNotEmpty &&
          tester
                  .widget<FilledButton>(
                    find.ancestor(
                      of: find.text(de.sicherungJetzt),
                      matching: find.byWidgetPredicate(
                        (w) => w is FilledButton,
                      ),
                    ),
                  )
                  .onPressed !=
              null) {
        await rolleZu(tester, find.text(de.sicherungJetzt));
        await tippe(tester, find.text(de.sicherungJetzt));
        await ruhe(tester, 3000);
      }
      print(
        'MOB-183 ohne Netz: ${sichtbareTexte(tester).where((t) => t.contains('Wartet') || t.contains('abgebrochen')).toList()}',
      );
    },
  );

  pruefung(
    'MOB-042 MOB-061 MOB-185 MOB-186 Gesicherte Fotos: Löschen-Häkchen, offline, freigeben',
    (tester) async {
      await PhotoManager.requestPermissionExtend();
      final konto = await kontoAnlegen(hauptDirekt, 'K042');
      await _inMediathek(2, praefix: 'gesichert');
      final alle = await _mediathekAnzahl();
      final app = await starteApp(tester, server: hauptApp, konto: konto);
      await _sicherungsseite(tester);
      await _schalter(tester, de.sicherungAn, true);
      await warteBis(
        tester,
        () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
        max: const Duration(minutes: 4),
        grund: 'gesichert',
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, de.sicherungVomTelefon),
            )
            .value,
        isTrue,
      );
      // MOB-185: Speicher freigeben (bis zur Systemrückfrage).
      await rolleZu(tester, find.text(de.sicherungFreigeben));
      await tippe(tester, find.text(de.sicherungFreigeben), ms: 200);
      print(
        'MOB-185 „Sucht gesicherte Aufnahmen …“ gesehen: '
        '${find.text(de.sicherungFreigebenSucht).evaluate().isNotEmpty}',
      );
      await warteBis(
        tester,
        () =>
            find.text(de.sicherungFreigebenText).evaluate().isNotEmpty ||
            find.text(de.sicherungFreigebenNichts).evaluate().isNotEmpty,
        max: const Duration(seconds: 60),
        grund: 'Rückfrage',
      );
      print(
        'MOB-185 Rückfrage: ${sichtbareTexte(tester).where((t) => t.contains('löschen?') || t.contains('Nichts')).toList()}',
      );
      if (find.widgetWithText(TextButton, de.abbrechen).evaluate().isNotEmpty) {
        await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
      }
      // MOB-186: Gelöschtes auch vom Telefon (ein Foto am Rechner in den
      // Papierkorb).
      final ids =
          (await app.sitzung.db.customSelect('SELECT id FROM assets').get())
              .map((r) => r.read<String>('id'))
              .toList();
      await mitRechner(
        hauptDirekt,
        konto,
        (r) => r.tue(InDenPapierkorb([ids.first])),
      );
      await app.sitzung.gleicheAb();
      await ruhe(tester, 2000);
      await rolleZu(tester, find.text(de.sicherungPapierkorbTelefon));
      await tippe(tester, find.text(de.sicherungPapierkorbTelefon), ms: 1500);
      await warteBis(
        tester,
        () =>
            find
                .text(de.sicherungPapierkorbTelefonText)
                .evaluate()
                .isNotEmpty ||
            find
                .text(de.sicherungPapierkorbTelefonNichts)
                .evaluate()
                .isNotEmpty,
        max: const Duration(seconds: 60),
        grund: 'Rückfrage Papierkorb',
      );
      expect(find.text(de.sicherungFreigebenTitel(1)), findsOneWidget);
      await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
      await zurueck(tester);
      await zurueck(tester);
      // MOB-042: Papierkorb mit Häkchen „auch vom Telefon“.
      await warteBis(
        tester,
        () => kacheln().evaluate().length >= 2,
        grund: 'Kacheln',
      );
      await lang(tester, kacheln().at(0));
      await tippe(tester, kacheln().at(1));
      await tippe(tester, _aktion(de.auswahlPapierkorb));
      await warte(tester, find.byType(CheckboxListTile));
      final haken = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(haken.value, isTrue, reason: 'laut Einstellung vorbelegt');
      final hakenText = sichtbareTexte(
        tester,
      ).where((t) => t.contains('Fotomediathek dieses Telefons')).toList();
      print('MOB-042 Häkchen: $hakenText');
      expect(hakenText, isNotEmpty);
      expect(find.text(de.loeschenAuchTelefonHinweisIos), findsOneWidget);
      await tippe(tester, find.byType(CheckboxListTile));
      await tippe(tester, find.text(de.betrachterPapierkorb).last, ms: 2000);
      await ruhe(tester, 2000);
      await lang(tester, kacheln().at(0));
      await tippe(tester, _aktion(de.auswahlPapierkorb));
      if (find.byType(CheckboxListTile).evaluate().isNotEmpty) {
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          isFalse,
          reason: 'letzte Wahl gemerkt',
        );
      }
      await tippe(tester, find.widgetWithText(TextButton, de.abbrechen));
      await tippe(tester, tooltip(de.auswahlAufheben));
      // MOB-061: gesichertes Foto offline in voller Auflösung.
      await proxyAus();
      await ruhe(tester, 1000);
      await oeffneKachel(tester, 0);
      await ruhe(tester, 3000);
      expect(find.text(de.betrachterNichtGeladen), findsNothing);
    },
  );

  pruefung('MOB-175 Am Server endgültig Gelöschtes kommt nicht wieder', (
    tester,
  ) async {
    await PhotoManager.requestPermissionExtend();
    final konto = await kontoAnlegen(hauptDirekt, 'K175');
    final alle = await _mediathekAnzahl();
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await _sicherungsseite(tester);
    await _schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
      max: const Duration(minutes: 4),
      grund: 'gesichert',
    );
    final id =
        (await app.sitzung.db
                .customSelect('SELECT id FROM assets LIMIT 1')
                .getSingle())
            .read<String>('id');
    final v = await api(hauptDirekt, konto);
    await mitRechner(hauptDirekt, konto, (r) => r.tue(InDenPapierkorb([id])));
    await v.schicke('api/v1/papierkorb/leeren', {
      'ids': [id],
    });
    final nach = await _serverAnzahl(konto);
    await ruhe(tester, 2000);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt));
    await ruhe(tester, 8000);
    expect(
      await _serverAnzahl(konto),
      nach,
      reason: 'nicht erneut hochgeladen',
    );
  });
}

// --------------------------------------------------------------------
// Nachträge

void nachtragTests() {
  pruefung('MOB-009 Passkey-Anmeldung: älterer Server ohne Passkeys', (
    tester,
  ) async {
    await proxyRegel({
      'muster': '^/api/v1/zustand',
      'patch': {
        'anmeldung': {'passkeys': false},
      },
    });
    await starteApp(tester);
    await schreibe(tester, feld(de.anmeldenAdresse), hauptApp.toString());
    await tippe(tester, find.text(de.anmeldenPasskey), ms: 1500);
    await warte(tester, find.text(de.anmeldenPasskeyUnbekannt));
    expect(find.text(de.anmeldenTitel), findsOneWidget);
  });

  pruefung('MOB-104 Album automatisch mit Personen füllen', (tester) async {
    final k = await kontoMitFotos('K104', 3);
    final pa = await person(hauptDirekt, k.konto, 'Person A');
    final kind = await person(hauptDirekt, k.konto, 'Kind');
    await gesicht(k.v, k.ids[0], personId: pa, kasten: [0.1, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[0], personId: kind, kasten: [0.6, 0.1, 0.3, 0.4]);
    await gesicht(k.v, k.ids[1], personId: pa);
    final regelalbum = await _albumMit(k.konto, 'Regelalbum', const []);
    try {
      print(
        'MOB-104 Regel am Server: ${await k.v.hole('api/v1/alben/$regelalbum/regel')}',
      );
    } catch (e) {
      print('MOB-104 Regel am Server: $e');
    }
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await _albumOeffnen(tester, 'Regelalbum');
    await tippe(tester, tooltip(tt.automatischFuellen), ms: 1500);
    await warte(tester, find.text(tt.automatischTitel('Regelalbum')));
    await tippe(tester, find.text(tt.speichern).last, ms: 1500);
    await warte(tester, find.text(tt.regelMindestensEine));
    await tippe(tester, find.widgetWithText(CheckboxListTile, 'Person A'));
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
    await ruhe(tester, 4500);
    await tippe(tester, tooltip(tt.automatischFuellen), ms: 1500);
    await tippe(tester, find.text(tt.automatischAus), ms: 2000);
    await meldung(tester, tt.automatischAusGemacht);
  });

  pruefung('MOB-106 Partnerfotos in der eigenen Zeitleiste', (tester) async {
    final a = await kontoMitFotos('K106A', 2);
    final b = await kontoMitFotos('K106B', 1, ab: DateTime(2024, 6, 20, 11));
    final idB = await kontoId(a.v, b.konto);
    final r = await a.v.anfrage('PUT', 'api/v1/partner/$idB');
    expect(r.statusCode, 204);
    final app = await starteApp(tester, server: hauptApp, konto: b.konto);
    await warteAufKacheln(tester, 1);
    await bereich(tester, de.navAlben);
    await rolleZu(tester, find.text(tt.partnerBibliothekVon(a.konto)));
    await tippe(tester, find.text(tt.partnerBibliothekVon(a.konto)), ms: 2000);
    await tippe(tester, find.byType(PopupMenuButton<void>), ms: 800);
    await tippe(tester, find.text(tt.partnerInZeitleiste), ms: 2000);
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await app.sitzung.ladePartnerfotos();
    await warteBis(
      tester,
      () => rasterIds(tester).length == 3,
      max: const Duration(seconds: 30),
      grund: 'Partnerfotos dazwischen',
    );
    final ids = rasterIds(tester);
    print('MOB-106 Raster: $ids (B: ${b.ids[0]})');
    // A’s Fotos (12:00, 11:59) sind neuer als B’s (11:00): nach Datum vorn.
    expect(ids.last, b.ids[0], reason: 'nach Datum einsortiert');
    // Partnerkachel nicht wählbar.
    const i = 0;
    await lang(tester, kacheln().at(i));
    expect(
      find.text(de.auswahlAnzahl(1)),
      findsNothing,
      reason: 'nicht wählbar',
    );
    await tippe(tester, kacheln().at(i), ms: 1500);
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'GeteilterBetrachter',
      ),
      findsOneWidget,
    );
    await schliesse(tester);
    await tippe(tester, tooltip(de.ansichtReihenfolge));
    await tippe(tester, find.text(de.sortName).last, ms: 1000);
    expect(rasterIds(tester), [b.ids[0]], reason: 'andere Reihenfolge: weg');
  });

  pruefung('MOB-184 Nur auf dem Telefon: Zeitleiste und eigener Betrachter', (
    tester,
  ) async {
    await PhotoManager.requestPermissionExtend();
    final konto = await kontoAnlegen(hauptDirekt, 'K184');
    final alle = await _mediathekAnzahl();
    await starteApp(tester, server: hauptApp, konto: konto);
    await _sicherungsseite(tester);
    await _schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
      max: const Duration(minutes: 4),
      grund: 'gesichert',
    );
    await zurueck(tester);
    await zurueck(tester);
    await proxyAus();
    await ruhe(tester, 1500);
    await _inMediathek(2, praefix: 'nurtelefon');
    await warte(
      tester,
      find.text(de.lokalAnzahl(2)),
      max: const Duration(seconds: 60),
    );
    print(
      'MOB-184 Zeile: ${sichtbareTexte(tester).where((t) => t.contains('Wartet') || t.contains('nur auf dem Telefon')).toList()}',
    );
    expect(find.text(de.lokalJetztSichern), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsWidgets);
    final raster =
        tester
                .widgetList(
                  find.byWidgetPredicate(
                    (w) => w.runtimeType.toString() == 'AufnahmenRaster',
                  ),
                )
                .last
            as dynamic;
    final lokaleIds = (raster.lokal as Map).keys.toSet();
    final lokal = rasterIds(tester).indexWhere(lokaleIds.contains);
    expect(lokal, greaterThanOrEqualTo(0));
    // Die Kachel über ihre Marke (durchgestrichene Wolke) im Raster finden –
    // die Kachelreihenfolge enthält auch Erinnerungen.
    final marke = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'AufnahmenRaster',
      ),
      matching: find.byIcon(Icons.cloud_off_outlined),
    );
    final kachel = find
        .ancestor(
          of: marke.last,
          matching: kacheln().evaluate().isEmpty
              ? find.byType(Stack)
              : find.byType(Stack),
        )
        .first;
    await lang(tester, kachel);
    expect(
      find.text(de.auswahlAnzahl(1)),
      findsNothing,
      reason: 'nicht wählbar',
    );
    await tippe(tester, kachel, ms: 1500);
    await warte(tester, find.text(de.lokalNochNichtGesichert));
    expect(find.text(de.lokalJetztSichern), findsWidgets);
    expect(tooltip(de.lokalVomTelefonLoeschen), findsOneWidget);
  });
}

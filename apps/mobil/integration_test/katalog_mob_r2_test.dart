// ignore_for_file: avoid_print
// Zweite Prüfrunde der Handy-App (pruefkatalog/teile/MOB.json): die
// Einträge, die in der ersten Runde an fehlenden Daten am Wegwerf-Server
// hingen (Personen, Gesichter mit Modell, Ortsverzeichnis, HEIC mit
// heif-dec, Reisen mit Spur, gesperrte Aufnahmen …). Im iOS-Simulator
// „PV Pruefung“ gegen die Wegwerf-Server der Runde (übersetztes Bündel aus
// diesem Worktree, siehe pruefkatalog/arbeit/r2-mob/wegwerf_r2.sh) und die
// Steuerung pruefkatalog/arbeit/r2-mob/mob_steuer_r2.py:
//
//   „haupt“ 18850 (Proxy 18851): Modelle, PV_SELBST_RECHNEN=alles,
//            PV_KARTEN=an, erfundenes Ortsverzeichnis (PV_GEODATEN)
//   „konten“ 18856 (Proxy 18860): TOTP Pflicht
//   „verw“   18857 (Proxy 18861): PV_SICHERUNG (Server-Sicherung)
//   „leer1“  18853 (Proxy 18854): frisch, ohne Konto
//
//   flutter test integration_test/katalog_mob_r2_test.dart -d <Simulator> \
//     --dart-define=PV_KATALOG=<Ordner des Prüfkatalogs> \
//     --dart-define=PV_FIXTURES=<pruefkatalog/fixtures> \
//     --dart-define=PV_FIXTURES_R2=<pruefkatalog/arbeit/r2-mob/fixtures> \
//     --dart-define=PV_FIXTURES_ML=<pruefkatalog/fixtures-ml>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:kern/services/develop_color.dart' show CurvePoint, ToneCurve;
import 'package:kern/services/search_filters.dart' show Aufnahmeherkunft;
import 'package:kern/services/stammbaum.dart' show Verwandtschaft;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:photo_vault_mobil/app_sperre.dart';
import 'package:photo_vault_mobil/main.dart' show PhotoVaultMobil;
import 'package:photo_vault_mobil/seiten/sicherung.dart' show jetztSichern;
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'katalog_hilfen.dart';
import 'katalog_r2_hilfen.dart';

part 'r2_teil_b.dart';
part 'r2_teil_c.dart';
part 'r2_teil_d.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vorbereitung', (tester) async {
    await einrichten();
    await ersteinrichtung(hauptDirekt);
    await ersteinrichtung(adresse(Port.verw));
    // Den Zugriff auf die Fotos erteilt vorher simctl (die Systemabfrage
    // ist nicht bedienbar; ein Erteilen während des Laufs beendet die App).
    await PhotoManager.requestPermissionExtend();
  });

  tearDown(() async {
    for (final n in ['haupt', 'leer1', 'konten', 'verw']) {
      await proxyZuruecksetzen(n);
    }
  });

  betrachterTests();
  gesichterTests();
  sperreTests();
  albenTests();
  freigabenTests();
  sucheTests();
  karteTests();
  bibliothekTests();
  kontoTests();
  einstellungenTests();
  sicherungTests();
  entwickelnTests();
  // Mit Texteingabe in Blättern: spät, damit ein Fehler der Tastatur im
  // Simulator nicht die übrigen Prüfungen mitreisst.
  angabenTests();
  anmeldenTests();
  // Lang (über fünf Minuten): zuletzt.
  passkeyTests();
}

String _kennung() => uuid();

Future<String> _albumMit(
  String konto,
  String name,
  List<String> ids, {
  Uri? server,
}) async {
  final a = _kennung();
  await mitRechner(server ?? hauptDirekt, konto, (r) async {
    await r.tue(AlbumAnlegen(a, name, DateTime.now()));
    if (ids.isNotEmpty) await r.tue(AlbumFuellen(a, ids));
  });
  return a;
}

Future<void> _albumOeffnen(WidgetTester tester, String name) async {
  await bereich(tester, de.navAlben);
  await rolleZu(tester, find.text(name));
  await tippe(tester, find.text(name).first, ms: 1500);
}

Future<void> _angaben(WidgetTester tester) async {
  await tippe(tester, tooltip(de.betrachterAngaben), ms: 1500);
}

/// Die Bildquellen, die der Betrachter gerade zeigt.
List<ImageProvider> _bildquellen(WidgetTester tester) => [
  for (final i in tester.widgetList<Image>(
    find.descendant(of: find.byType(PageView), matching: find.byType(Image)),
  ))
    i.image,
];

String _quelle(ImageProvider q) {
  final innen = q is ResizeImage ? q.imageProvider : q;
  final d = innen as dynamic;
  String extra = '';
  try {
    extra = ' relativ=${d.relativ}';
  } catch (_) {}
  try {
    extra += ' original=${d.isOriginal}';
  } catch (_) {}
  return '${innen.runtimeType}$extra';
}

// ======================================================================
// Anmelden

void anmeldenTests() {
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

  // Behoben in #463: Von aussen verrät der Server nicht, ob er schon
  // eingerichtet ist (kein `einrichten` im Zustand, POST /api/v1/einrichten
  // immer 403). Die App bietet „Neuer Server? Erstes Konto anlegen“ deshalb
  // immer an; der Versuch endet mit dem Satz, dass das erste Konto nur aus
  // dem Heimnetz geht.
  pruefung('MOB-013 Erstes Konto von aussen (zweimal)', (tester) async {
    final gezeigt = <String>[];
    for (var i = 0; i < 2; i++) {
      await steuer('server/leer1/neu');
      await starteApp(tester);
      await proxyRegel({
        'muster': '^/api/v1/',
        'kopf': {'X-Forwarded-For': '203.0.113.${7 + i}'},
      }, 'leer1');
      await anmeldeDaten(
        tester,
        adresse: adresse(Port.leer1Proxy).toString(),
        name: 'Verwalter',
        passwort: pw,
      );
      await tippe(
        tester,
        find.widgetWithText(TextButton, de.anmeldenNeuerServer),
      );
      await warte(tester, feld(de.anmeldenPasswortWiederholen));
      expect(
        find.text(de.anmeldenErstesTextOffen('Verwalter')),
        findsOneWidget,
      );
      await schreibe(tester, feld(de.anmeldenPasswortWiederholen), pw);
      FocusManager.instance.primaryFocus?.unfocus();
      await ruhe(tester, 400);
      await tippe(tester, find.text(de.anmeldenErstesAnlegen));
      await warteWeg(tester, find.byType(LinearProgressIndicator));
      await ruhe(tester, 800);
      gezeigt.add(
        find.text(de.anmeldenErstesNurHeimnetz).evaluate().isNotEmpty
            ? 'heimnetz'
            : find.text(de.anmeldenFalsch).evaluate().isNotEmpty
            ? 'falsch'
            : sichtbareTexte(tester).join(' | '),
      );
      final z = Anmeldung(adresse(Port.leer1));
      expect((await z.zustand())['einrichten'], isTrue, reason: 'kein Konto');
      z.schliesse();
      await proxyZuruecksetzen('leer1');
    }
    print('MOB-013 von aussen gezeigt: $gezeigt');
    expect(gezeigt, everyElement('heimnetz'));
  });
}

// ======================================================================
// Betrachter

void betrachterTests() {
  pruefung('MOB-054 Vergrössert verschiebt das Wischen das Bild', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K054');
    final v = await api(hauptDirekt, konto);
    await hochladen(v, jpeg(breite: 300, hoehe: 1500), 'hoch_054.jpg');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await oeffneKachel(tester, 0);
    await ruhe(tester, 2500);
    Rect bild() => tester.getRect(
      find
          .descendant(of: find.byType(PageView), matching: find.byType(Image))
          .first,
    );
    final vorher = bild();
    await zoome(tester);
    final gezoomt = bild();
    print('MOB-054 Bild vorher $vorher, gezoomt $gezoomt');
    var groesser = gezoomt.width > vorher.width * 1.3;
    if (!groesser) {
      await zoome(tester, aufziehen: true);
      groesser = bild().width > vorher.width * 1.3;
    }
    expect(groesser, isTrue, reason: 'vergrössert');
    final vorZug = bild();
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await ruhe(tester, 1500);
    final nachZug = bild();
    print('MOB-054 vor dem Zug $vorZug, danach $nachZug');
    expect(find.byType(PageView), findsOneWidget, reason: 'bleibt offen');
    expect(tooltip(de.betrachterAngaben), findsOneWidget);
    expect(
      nachZug.top,
      greaterThan(vorZug.top + 40),
      reason: 'das Bild ist verschoben',
    );
    expect(find.text(de.angabenTitel), findsNothing);
  });

  pruefung('MOB-055 MOB-136 HEIC: Vorschau, Zoom in Originalgrösse', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K055');
    final v = await api(hauptDirekt, konto);
    final id = await hochladenPfad(v, '$r2Fix/gross.heic', name: 'gross.heic');
    Map<String, Object?> a = {};
    for (var i = 0; i < 60; i++) {
      a = await aufnahme(v, id);
      if (a['previewRelativePath'] != null) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print(
      'MOB-055 HEIC am Server: ${a['widthPx']}×${a['heightPx']}, '
      'Miniatur ${a['thumbnailRelativePath']}, Vorschau ${a['previewRelativePath']}',
    );
    expect(a['previewRelativePath'], isNotNull, reason: 'heif-dec wandelt');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await proxyLogLeeren();
    await oeffneKachel(tester, 0);
    await ruhe(tester, 4000);
    final beimOeffnen = await proxyPfade();
    print('MOB-055 beim Öffnen: $beimOeffnen');
    expect(
      beimOeffnen.any((x) => x.contains('/api/v1/aufnahmen/$id/voll')),
      isFalse,
      reason: 'beim Öffnen nur die Vorschau',
    );
    expect(
      beimOeffnen.any((x) => x.contains('/api/v1/dateien/previews/')),
      isTrue,
      reason: 'Vorschau vom Server',
    );
    await proxyLogLeeren();
    await zoome(tester);
    await ruhe(tester, 8000);
    var beimZoomen = await proxyPfade();
    if (!beimZoomen.any((x) => x.contains('/voll'))) {
      await zoome(tester, aufziehen: true);
      await ruhe(tester, 8000);
      beimZoomen = await proxyPfade();
    }
    print('MOB-055 beim Zoomen: $beimZoomen');
    expect(
      beimZoomen.where((x) => x.contains('/api/v1/aufnahmen/$id/voll')),
      isNotEmpty,
      reason: 'gewandeltes JPEG in Originalgrösse',
    );
    // Die gewandelte Datei hat die Originalgrösse.
    final r = await v.anfrage('GET', 'api/v1/aufnahmen/$id/voll');
    final voll = await ui.instantiateImageCodec(r.bodyBytes);
    final b = (await voll.getNextFrame()).image;
    print('MOB-055 /voll: ${r.headers['content-type']} ${b.width}×${b.height}');
    expect((b.width, b.height), (5000, 3750));
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
    // MOB-136: Entwickeln rechnet beim HEIC aus der Vorschau.
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.entwTitel).last, ms: 3000);
    await warte(
      tester,
      find.textContaining(de.entwVorschauQuelle),
      max: const Duration(seconds: 30),
    );
    expect(find.textContaining('liess sich nicht laden'), findsNothing);
  });

  pruefung('MOB-060 Schweres Video: leichte Fassung; defektes Video', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K060');
    final v = await api(hauptDirekt, konto);
    final schwer = await hochladenPfad(v, '$r2Fix/schwer.mp4');
    final kaputt = await hochladenPfad(v, '$r2Fix/kaputt.mp4');
    final a = await aufnahme(v, schwer);
    print(
      'MOB-060 schwer: ${a['fileSizeBytes']} B, ${a['durationSeconds']} s, '
      'Datum ${a['fileCreatedAt']}',
    );
    print('MOB-060 kaputt: ${await aufnahme(v, kaputt)}');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    final ids = rasterIds(tester);
    await proxyLogLeeren();
    await oeffneKachel(tester, ids.indexOf(schwer));
    // Das Original läuft an; dann bremst der Proxy jede weitere Anfrage auf
    // das Original (wie ein langsames Netz), bis der Spieler steht.
    await warteBis(
      tester,
      () => find.byType(VideoPlayer).evaluate().isNotEmpty,
      max: const Duration(seconds: 60),
      grund: 'Spieler',
    );
    await ruhe(tester, 2500);
    await proxyRegel({
      'muster': r'^/api/v1/dateien/originals/',
      'verzoegerung': 25,
    });
    final t0 = DateTime.now();
    await warte(
      tester,
      find.text(de.betrachterWirdUmgewandelt),
      max: const Duration(seconds: 90),
    );
    final hinweisNach = DateTime.now().difference(t0);
    VideoPlayerController ctl() =>
        tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller;
    final stelle = ctl().value.position;
    print('MOB-060 Hinweis nach ${hinweisNach.inSeconds} s, Stelle $stelle');
    await warteBis(
      tester,
      () => ctl().dataSource.contains('abspielbar'),
      max: const Duration(minutes: 4),
      grund: 'leichte Fassung',
    );
    await ruhe(tester, 3000);
    print(
      'MOB-060 leichte Fassung ${ctl().dataSource} ab ${ctl().value.position}',
    );
    expect(
      ctl().value.position,
      greaterThanOrEqualTo(stelle - const Duration(seconds: 1)),
      reason: 'an derselben Stelle weiter',
    );
    await proxyZuruecksetzen();
    await schliesse(tester);
    // Defekt: Meldung statt schwarzer Fläche.
    await oeffneKachel(tester, rasterIds(tester).indexOf(kaputt));
    await warte(
      tester,
      find.text(de.betrachterNichtGeladen),
      max: const Duration(seconds: 120),
    );
    await schliesse(tester);
    // Ohne leichte Fassung (der Server kann keine erzeugen): Das Original
    // bleibt.
    await proxyRegel({
      'muster': r'/abspielbar',
      'status': 422,
      'body': {'fehler': 'nicht umwandelbar'},
    });
    await oeffneKachel(tester, rasterIds(tester).indexOf(schwer));
    await warteBis(
      tester,
      () => find.byType(VideoPlayer).evaluate().isNotEmpty,
      max: const Duration(seconds: 60),
      grund: 'Spieler',
    );
    await ruhe(tester, 2500);
    await proxyRegel({
      'muster': r'^/api/v1/dateien/originals/',
      'verzoegerung': 12,
    });
    // Der Server sagt gleich beim Öffnen, dass es keine leichte Fassung
    // gibt: Das Original bleibt, ein Hinweis darf kurz kommen und gehen.
    final hinweise = <bool>[];
    for (var i = 0; i < 30; i++) {
      await ruhe(tester, 1000);
      hinweise.add(
        find.text(de.betrachterWirdUmgewandelt).evaluate().isNotEmpty,
      );
    }
    print('MOB-060 Hinweis ohne leichte Fassung (je Sekunde): $hinweise');
    await proxyZuruecksetzen();
    await ruhe(tester, 3000);
    print(
      'MOB-060 ohne leichte Fassung: ${ctl().dataSource} bei ${ctl().value.position}, '
      'Fehler ${find.text(de.betrachterNichtGeladen).evaluate().length}',
    );
    expect(ctl().dataSource.contains('abspielbar'), isFalse);
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
  });

  pruefung('MOB-061 Gesichertes Foto vom Telefon, auch offline', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K061');
    final neu = await inMediathek(2, praefix: 'r2_061');
    final alle = await mediathekAnzahl();
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungAn, true);
    await warteBis(
      tester,
      () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
      max: const Duration(minutes: 5),
      grund: 'gesichert',
    );
    await app.sitzung.gleicheAb();
    final d = app.sitzung.sicherung!;
    final server = <String, String>{};
    for (final z
        in await app.sitzung.db.customSelect('SELECT id FROM assets').get()) {
      final id = z.read<String>('id');
      final g = d.gesichertAls(id);
      if (g != null) server[g.lokal] = id;
    }
    final s1 = server[neu[0].id]!, s2 = server[neu[1].id]!;
    // Das zweite am Server entwickeln (wie der Rechner).
    final v = await api(hauptDirekt, konto);
    final tmp = File(p.join(Directory.systemTemp.path, 'entw_061.jpg'));
    await tmp.writeAsBytes(jpeg(breite: 400, hoehe: 300, farbe: 0xff0000));
    await v.legeAb('api/v1/dateien/developed/$s2-1.jpg', tmp);
    await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.tue(
        EntwicklungSpeichern(
          s2,
          DevelopSettingsCompanion.insert(
            assetId: s2,
            exposure: const Value(1.0),
            updatedAt: DateTime.now(),
          ),
          'developed/$s2-1.jpg',
        ),
      ),
    );
    await warteBis(tester, () async {
      await app.sitzung.gleicheAb();
      return (await app.sitzung.db.assetById(s2))?.developedRelativePath !=
          null;
    }, grund: 'entwickelt angekommen');
    await zurueck(tester);
    await zurueck(tester);
    await bereich(tester, de.navZeitleiste);
    await proxyAus();
    await ruhe(tester, 1000);
    await rolleZu(tester, kachelVon(s1));
    await tippe(tester, kachelVon(s1), ms: 1500);
    await warte(tester, tooltip(de.betrachterAngaben));
    await ruhe(tester, 1500);
    final q1 = _bildquellen(tester).map(_quelle).toList();
    await zoome(tester);
    if (_bildquellen(tester).length < 2) await zoome(tester, aufziehen: true);
    await ruhe(tester, 2000);
    final q1z = _bildquellen(tester).map(_quelle).toList();
    print('MOB-061 Foto 1 offline: $q1, gezoomt $q1z');
    expect(q1.any((x) => x.startsWith('AssetEntityImageProvider')), isTrue);
    expect(q1z.any((x) => x.contains('original=true')), isTrue);
    expect(find.text(de.betrachterNichtGeladen), findsNothing);
    await schliesse(tester);
    await proxyAn();
    await ruhe(tester, 1500);
    await rolleZu(tester, kachelVon(s2));
    await tippe(tester, kachelVon(s2), ms: 1500);
    await warte(tester, tooltip(de.betrachterAngaben));
    await ruhe(tester, 2500);
    final q2 = _bildquellen(tester).map(_quelle).toList();
    print('MOB-061 Foto 2 (entwickelt): $q2');
    expect(q2.any((x) => x.contains('relativ=developed/')), isTrue);
    expect(q2.any((x) => x.startsWith('AssetEntityImageProvider')), isFalse);
  });
}

// ======================================================================
// Angaben

void angabenTests() {
  pruefung('MOB-044 MOB-066 Ort über das Ortsverzeichnis, geerbter Ort', (
    tester,
  ) async {
    final k = await kontoMitFotos('K044', 3);
    // Ein Foto mit geerbtem Ort (wie „Ort vom Nachbarfoto übernehmen“).
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(OrtsvorschlagUebernehmen([k.ids[2]], 48.5, 11.2)),
    );
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    final ids = rasterIds(tester);
    final i0 = ids.indexOf(k.ids[0]), i1 = ids.indexOf(k.ids[1]);
    await lang(tester, kacheln().at(i0));
    await tippe(tester, kacheln().at(i1));
    await tippe(tester, aktion(de.auswahlOrt), ms: 1200);
    await warte(tester, find.text(de.ortFuerAufnahmen(2)));
    final suchfeld = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await schreibeLeise(tester, suchfeld, 'M');
    await ruhe(tester, 1500);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );
    for (final m in [
      de.ortKeinTreffer,
      de.ortKeineVerbindung,
      de.ortKeinVerzeichnis,
    ]) {
      expect(find.text(m), findsNothing, reason: 'ein Zeichen: keine Meldung');
    }
    await schreibeLeise(tester, suchfeld, 'Musterstadt');
    await warte(tester, find.widgetWithText(ListTile, 'Musterstadt'));
    await tippe(tester, find.widgetWithText(ListTile, 'Musterstadt'), ms: 1500);
    await warteWeg(tester, find.text(de.ortFuerAufnahmen(2)));
    await app.sitzung.gleicheAb();
    for (final id in [k.ids[0]]) {
      final s0 = await amServer(hauptDirekt, k.konto, k.ids[1]);
      expect(s0?.locationCity, 'Musterstadt', reason: 'zweites Foto');
      final s = await amServer(hauptDirekt, k.konto, id);
      expect(s?.locationCity, 'Musterstadt', reason: id);
      final aufheben = tooltip(de.auswahlAufheben);
      if (aufheben.evaluate().isNotEmpty) await tippe(tester, aufheben);
      print(
        'MOB-044 Raster ${rasterIds(tester)}, Kacheln ${kacheln().evaluate().length}, sichtbar ${sichtbareTexte(tester).take(12)}',
      );
      await oeffneKachel(tester, rasterIds(tester).indexOf(id));
      await _angaben(tester);
      await warte(tester, find.textContaining('Musterstadt'));
      await schliesse(tester);
      await schliesse(tester);
    }
    // Unsinn und ohne Server.
    await lang(tester, kacheln().at(rasterIds(tester).indexOf(k.ids[0])));
    await tippe(tester, kacheln().at(rasterIds(tester).indexOf(k.ids[1])));
    await tippe(tester, aktion(de.auswahlOrt), ms: 1200);
    await schreibeLeise(tester, suchfeld, 'Xqzwvy');
    await warte(tester, find.text(de.ortKeinTreffer));
    await proxyAus();
    await schreibeLeise(tester, suchfeld, 'Musterst');
    await warte(tester, find.text(de.ortKeineVerbindung));
    await proxyAn();
    await tastaturWeg(tester);
    await schliesse(tester);
    await meldungenWeg(tester);
    // MOB-066: geerbter Ort; dann ein Foto ohne Ort über das Verzeichnis.
    final g = rasterIds(tester).indexOf(k.ids[2]);
    if (find.text(de.auswahlAnzahl(2)).evaluate().isNotEmpty) {
      await zurueck(tester);
    }
    await tippe(tester, kacheln().at(g), ms: 1200);
    await _angaben(tester);
    await warte(tester, find.textContaining(de.angabenGeerbt));
    await tippe(tester, find.text(de.ortAendern), ms: 1200);
    await tippe(tester, find.text(de.ortEntfernen), ms: 1500);
    await warte(tester, find.text(de.ortKeiner));
    expect(find.text(de.ortSetzen), findsWidgets);
    await tippe(tester, find.widgetWithText(TextButton, de.ortSetzen));
    expect(find.text(de.ortEntfernen), findsNothing, reason: 'ohne Ort');
    final feld2 = find.descendant(
      of: find.byType(BottomSheet).last,
      matching: find.byType(TextField),
    );
    await schreibeLeise(tester, feld2, 'Beispielhausen');
    await warte(tester, find.widgetWithText(ListTile, 'Beispielhausen'));
    await tippe(tester, find.widgetWithText(ListTile, 'Beispielhausen'));
    await warte(tester, find.textContaining('Beispielhausen'));
    expect(find.text(de.ortAendern), findsOneWidget);
    expect(find.textContaining(de.angabenGeerbt), findsNothing);
    final s = await amServer(hauptDirekt, k.konto, k.ids[2]);
    print(
      'MOB-066 am Server: ${s?.locationCity} ${s?.latitude} ${s?.ortGeerbt}',
    );
    expect(s?.locationCity, 'Beispielhausen');
    expect(s?.ortGeerbt, isFalse);
  });

  pruefung('MOB-045 Aufs Telefon: ohne Zugriff, Originalnamen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K045');
    final v = await api(hauptDirekt, konto);
    final stamm = 'r2_045_${DateTime.now().millisecondsSinceEpoch}';
    await hochladen(v, jpeg(datum: DateTime(2024, 3, 3)), '$stamm.jpg');
    await hochladen(
      v,
      Uint8List.fromList(
        await macDatei(p.join(fixturesOrdner, 'video_5s.mp4')),
      ),
      '$stamm.mp4',
    );
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 2);
    final pm = PhotoManagerAttrappe()
      ..antworten['requestPermissionExtend'] =
          ((_) => 2) // verweigert
      ..an();
    addTearDown(pm.aus);
    await lang(tester, kacheln().at(0));
    await tippe(tester, kacheln().at(1));
    await tippe(tester, aktion(de.auswahlHerunterladen), ms: 300);
    await meldung(tester, de.auswahlKeinZugriff);
    pm.aus();
    await meldungenWeg(tester);
    await proxyRegel({
      'muster': r'^/api/v1/dateien/originals/',
      'verzoegerung': 2,
    });
    if (find.text(de.auswahlAnzahl(2)).evaluate().isEmpty) {
      await lang(tester, kacheln().at(0));
      await tippe(tester, kacheln().at(1));
    }
    await tippe(tester, aktion(de.auswahlHerunterladen), ms: 200);
    await meldung(tester, de.auswahlLaedt);
    await meldung(
      tester,
      de.auswahlGespeichert(2),
      max: const Duration(seconds: 90),
    );
    // In der Mediathek mit dem Originalnamen.
    final pfade = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.common,
    );
    final n = await pfade.first.assetCountAsync;
    final titel = <String>[];
    for (final e in await pfade.first.getAssetListRange(start: 0, end: n)) {
      titel.add(await e.titleAsync);
    }
    print(
      'MOB-045 Namen in der Mediathek (Auszug): ${titel.where((t) => t.startsWith('r2_045'))}',
    );
    expect(titel, containsAll(['$stamm.jpg', '$stamm.mp4']));
  });

  pruefung('MOB-063 Angaben: Person, erkannter Text, Transkript', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K063');
    final v = await api(hauptDirekt, konto);
    final schild = await hochladenPfad(v, '$r2Fix/schild.jpg');
    final video = await hochladenPfad(
      v,
      p.join(fixturesOrdner, 'r2mob_sprache.mp4'),
    );
    final foto = await hochladen(
      v,
      jpeg(
        datum: DateTime(2023, 8, 1, 10),
        kamera: 'Pruefkamera',
        modell: 'PK-1',
        breitengrad: -40,
        laengengrad: 170,
      ),
      'r2_063.jpg',
    );
    final pid = await person(hauptDirekt, konto, 'Testperson');
    await gesicht(v, foto, personId: pid);
    final album = await _albumMit(konto, 'Angabenalbum', [foto]);
    await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.tue(
        AufnahmedatenSetzen([
          (id: foto, zeitpunkt: DateTime(2010, 5, 5, 12), geschaetzt: true),
        ]),
      ),
    );
    await auswerten(v);
    final as = await aufnahme(v, schild), av = await aufnahme(v, video);
    print('MOB-063 OCR: ${as['ocrText']} | Transkript: ${av['transkript']}');
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 3);
    // Foto: Datum geschätzt, Person, Album.
    await tippe(tester, kachelVon(foto), ms: 1200);
    await _angaben(tester);
    await warte(tester, find.textContaining(de.angabenDatumGeschaetzt));
    expect(find.textContaining('Pruefkamera'), findsWidgets);
    expect(find.text(de.angabenStandortBekannt), findsOneWidget);
    await rolleZu(tester, find.widgetWithText(ActionChip, 'Testperson'));
    await tippe(
      tester,
      find.widgetWithText(ActionChip, 'Testperson'),
      ms: 2000,
    );
    await warte(tester, find.widgetWithText(AppBar, 'Testperson'));
    await zurueck(tester);
    await rolleZu(tester, find.textContaining('Angabenalbum'));
    expect(album, isNotEmpty);
    await schliesse(tester);
    await schliesse(tester);
    // Schild: erkannter Text.
    await tippe(tester, kachelVon(schild), ms: 1200);
    await _angaben(tester);
    await rolleZu(tester, find.text(de.angabenText));
    await tippe(tester, find.text(de.angabenText));
    await warte(tester, find.textContaining('BAHNHOF'));
    await schliesse(tester);
    await schliesse(tester);
    // Video: Transkript.
    await tippe(tester, kachelVon(video), ms: 1500);
    await _angaben(tester);
    await rolleZu(tester, find.text(de.angabenTranskript));
    await tippe(tester, find.text(de.angabenTranskript));
    await warte(tester, find.textContaining('Spracherkennung'));
  });

  pruefung('MOB-069 Formate eines Stapels einzeln teilen', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'K069');
    final v = await api(hauptDirekt, konto);
    await mitRechner(
      hauptDirekt,
      konto,
      (r) => r.tue(const FormateStapelnSetzen(true)),
    );
    final d = DateTime(2024, 9, 9, 9, 9, 9);
    final jpg = jpeg(datum: d, farbe: 0x112233);
    final dng = jpeg(datum: d, farbe: 0x445566, breite: 800, hoehe: 600);
    final ij = await hochladen(v, jpg, 'IMG_0069.jpg');
    final id = await hochladen(v, dng, 'IMG_0069.dng');
    AssetData? a;
    for (var i = 0; i < 40; i++) {
      a = await amServer(hauptDirekt, konto, ij);
      if (a?.stackId != null) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print('MOB-069 Stapel: ${a?.stackId} Titelbild ${a?.isStackCover}');
    expect(a?.stackId, isNotNull);
    teilenAbfangen();
    await starteApp(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    expect(rasterIds(tester), hasLength(1), reason: 'nur eine Fassung');
    await oeffneKachel(tester, 0);
    await _angaben(tester);
    await rolleZu(tester, find.text(de.angabenFormate));
    final chipDng = tooltip(de.angabenFassungTeilen('IMG_0069.dng'));
    expect(chipDng, findsOneWidget);
    expect(tooltip(de.angabenFassungTeilen('IMG_0069.jpg')), findsOneWidget);
    await proxyRegel({
      'muster': r'^/api/v1/dateien/originals/.*\.dng',
      'verzoegerung': 2,
    });
    await tippe(tester, chipDng, ms: 200);
    await meldung(tester, de.betrachterLaedtOriginal);
    await warteBis(tester, () => geteilt.isNotEmpty, grund: 'geteilt');
    final f = geteilt.single.single;
    print('MOB-069 geteilt: ${f.pfad} (${f.daten.length} B)');
    expect(sha(f.daten), sha(dng));
    expect(id, isNotEmpty);
  });
}

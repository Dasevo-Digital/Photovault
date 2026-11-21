// ignore_for_file: avoid_print
// Katalogprüfung der Handy-App, Teil Android (pruefkatalog/teile/MOB.json,
// Einträge mit selbsttest „android“) im eigenen Emulator photovault_test
// gegen Wegwerf-Server auf dem Mac (Adresse des Rechners im Emulator).
// Geräte-PIN, Netz und Akku stellt die Prüfung über adb am eigenen
// Emulator (emulator-5574) ein, den die Steuerung der Prüfumgebung
// anspricht.
//
//   flutter test integration_test/katalog_mob_android_test.dart \
//     -d emulator-5574 --dart-define=PV_HOST=<Adresse des Rechners im Emulator>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_vault_mobil/app_sperre.dart';
import 'package:photo_vault_mobil/main.dart' show PhotoVaultMobil;
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'katalog_hilfen.dart';

const _paket = 'de.dasevo.photovault.test';
const _pin = '1234';

Future<String> adb(List<String> args) async {
  // Beim Umschalten des WLANs reisst die Verbindung zum Mac kurz ab.
  for (var versuch = 0; ; versuch++) {
    try {
      final r = await steuer('adb', {'args': args});
      return '${r['aus'] ?? ''}${r['fehler'] ?? ''}';
    } catch (e) {
      if (versuch >= 5) rethrow;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

Future<void> pinSetzen() => adb(['shell', 'locksettings', 'set-pin', _pin]);
Future<void> pinEntfernen() =>
    adb(['shell', 'locksettings', 'clear', '--old', _pin]);

/// Gibt die PIN in die Systemabfrage ein.
Future<void> pinEingeben(WidgetTester tester) async {
  await ruhe(tester, 1500);
  await adb(['shell', 'input', 'text', _pin]);
  await adb(['shell', 'input', 'keyevent', '66']);
  await ruhe(tester, 1500);
}

/// Bricht die Systemabfrage ab (Zurück-Taste).
Future<void> abfrageAbbrechen(WidgetTester tester) async {
  await ruhe(tester, 1500);
  await adb(['shell', 'input', 'keyevent', '4']);
  await ruhe(tester, 1500);
}

/// App in den Hintergrund und nach [dauer] wieder nach vorn.
Future<void> hinterUndVor(WidgetTester tester, Duration dauer) async {
  // Android friert Apps im Hintergrund ein; zurückholen muss sie der Mac.
  await steuer('adb/spaeter', {
    'args': [
      'shell',
      'am',
      'start',
      '-n',
      '$_paket/de.dasevo.photovault.MainActivity',
    ],
    'nach': dauer.inMilliseconds / 1000,
  });
  await adb(['shell', 'input', 'keyevent', '3']);
  // Im Hintergrund zeichnet die App nicht: nicht pumpen, nur warten.
  await Future<void>.delayed(dauer + const Duration(seconds: 2));
  await ruhe(tester, 2000);
}

/// Startet die App wie `main()` – mit App-Sperre.
Future<(Sitzung, Directory)> starteMitSperre(
  WidgetTester tester, {
  required Uri server,
  required String konto,
}) async {
  await einrichten();
  await appBeenden(tester);
  final ordner = await Directory.systemTemp.createTemp('pv_mob_');
  final bib = Directory(p.join(ordner.path, 'bibliothek'));
  // Jede Prüfung beginnt ohne App-Sperre (Einstellung dieser Test-App).
  final einstellung = File(
    p.join((await getApplicationSupportDirectory()).path, 'app_sperre.json'),
  );
  if (await einstellung.exists()) await einstellung.delete();
  final s = Sitzung(ordner: () async => bib)
    ..appSperre = await AppSperre.lade();
  final zurueck = SperrZurueck(s.appSperre!);
  WidgetsBinding.instance.addObserver(zurueck);
  addTearDown(() => WidgetsBinding.instance.removeObserver(zurueck));
  final t = await holeToken(server, konto, geraet: 'Telefon');
  await s.verbinde(server: server, konto: konto, geraet: 'Telefon', token: t);
  await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
  await ruhe(tester, 800);
  return (s, ordner);
}

Finder _sperrSchalter() => find.descendant(
  of: find
      .ancestor(of: find.text(de.appSperreTitel), matching: find.byType(Row))
      .first,
  matching: find.byType(Switch),
);

Future<void> _einstellungen(WidgetTester tester) async {
  await bibOeffnen(tester, de.bibEinstellungen);
  await warte(tester, find.text(de.appSperreTitel));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vorbereitung (nimmt späte Fehler auf)', (tester) async {
    await einrichten();
    await pinEntfernen();
    await adb([
      'shell',
      'pm',
      'grant',
      _paket,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    // MOB-171 nimmt den Zugriff selbst weg („Nie fragen“) und gibt ihn
    // zurück; die übrigen Prüfungen brauchen ihn.
    for (final r in [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
    ]) {
      await adb(['shell', 'pm', 'grant', _paket, r]);
    }
  });

  tearDown(() async {
    await proxyZuruecksetzen();
  });

  // Behoben in #418: Zurück in der App liest der Sicherungsdienst den
  // Zugriff auch bei ausgeschalteter Sicherung neu (zurueckInDerApp).
  // Ist der Zugriff beim Start erteilt, beendet Android die App beim
  // Entziehen: Dann vor dem Lauf per adb entziehen und MOB-171 allein
  // laufen lassen (ohne „Vorbereitung“, die ihn erteilt).
  pruefung('MOB-171 Kein Zugriff auf die Fotos', (tester) async {
    await pinEntfernen();
    for (final r in [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
      'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
    ]) {
      await adb(['shell', 'pm', 'revoke', _paket, r]);
      await adb([
        'shell',
        'pm',
        'set-permission-flags',
        _paket,
        r,
        'user-fixed',
      ]);
    }
    final konto = await kontoAnlegen(hauptDirekt, 'A171');
    await starteApp(tester, server: hauptApp, konto: konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.sicherungTitel));
    await tippe(tester, find.text(de.sicherungTitel), ms: 1200);
    final schalter = find.widgetWithText(SwitchListTile, de.sicherungAn);
    await tippe(tester, schalter, ms: 3000);
    expect(tester.widget<SwitchListTile>(schalter).value, isFalse);
    await warte(tester, find.text(de.sicherungKeinZugriff));
    expect(find.text(de.sicherungKeinZugriffHinweis), findsOneWidget);
    expect(find.text(de.sicherungEinstellungenOeffnen), findsOneWidget);
    // In den Einstellungen erlauben (hier per adb), zurück zur App.
    for (final r in [
      'android.permission.READ_MEDIA_IMAGES',
      'android.permission.READ_MEDIA_VIDEO',
    ]) {
      await adb([
        'shell',
        'pm',
        'clear-permission-flags',
        _paket,
        r,
        'user-fixed',
      ]);
      await adb(['shell', 'pm', 'grant', _paket, r]);
    }
    await hinterUndVor(tester, const Duration(seconds: 2));
    await ruhe(tester, 10000);
    final bleibt = find.text(de.sicherungKeinZugriff).evaluate().isNotEmpty;
    print('MOB-171 Zeile „Kein Zugriff“ nach dem Erlauben noch da: $bleibt');
    await tippe(tester, schalter, ms: 3000);
    expect(tester.widget<SwitchListTile>(schalter).value, isTrue);
    expect(find.text(de.sicherungKeinZugriff), findsNothing);
    expect(bleibt, isFalse, reason: 'Zeile verschwindet ohne Neustart');
  });

  pruefung('MOB-160 MOB-163 App-Sperre einschalten und abschalten', (
    tester,
  ) async {
    final k = await kontoMitFotos('A160', 2);
    final (s, _) = await starteMitSperre(
      tester,
      server: hauptApp,
      konto: k.konto,
    );
    await warteAufKacheln(tester, 2);
    await _einstellungen(tester);
    // Ohne PIN.
    await tippe(tester, _sperrSchalter(), ms: 1500);
    await meldung(tester, de.appSperreNichtVerfuegbar);
    expect(tester.widget<Switch>(_sperrSchalter()).value, isFalse);
    // Mit PIN, Abbruch.
    await pinSetzen();
    await ruhe(tester, 4500);
    await tippe(tester, _sperrSchalter(), ms: 300);
    await abfrageAbbrechen(tester);
    expect(tester.widget<Switch>(_sperrSchalter()).value, isFalse);
    // Mit PIN, eingegeben.
    await tippe(tester, _sperrSchalter(), ms: 300);
    await pinEingeben(tester);
    await warteBis(
      tester,
      () => tester.widget<Switch>(_sperrSchalter()).value,
      grund: 'an',
    );
    for (final t in [
      de.appSperreSofort,
      de.appSperreMinuten(1),
      de.appSperreMinuten(5),
      de.appSperreMinuten(15),
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(s.appSperre!.an, isTrue);
    // MOB-163: Abschalten nur mit Bestätigung.
    await tippe(tester, _sperrSchalter(), ms: 300);
    await abfrageAbbrechen(tester);
    expect(tester.widget<Switch>(_sperrSchalter()).value, isTrue);
    await tippe(tester, _sperrSchalter(), ms: 300);
    await pinEingeben(tester);
    await warteBis(
      tester,
      () => !tester.widget<Switch>(_sperrSchalter()).value,
      grund: 'aus',
    );
    expect(find.text(de.appSperreMinuten(5)), findsNothing);
  });

  pruefung('MOB-161 MOB-164 MOB-166 Gesperrter Start, Umschalter, Zurück', (
    tester,
  ) async {
    final k = await kontoMitFotos('A161', 2);
    final album = uuid();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Geheimes Album', DateTime.now()));
      await r.tue(AlbumFuellen(album, k.ids));
    });
    await pinSetzen();
    await starteMitSperre(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 2);
    await _einstellungen(tester);
    await tippe(tester, _sperrSchalter(), ms: 300);
    await pinEingeben(tester);
    await warteBis(
      tester,
      () => tester.widget<Switch>(_sperrSchalter()).value,
      grund: 'an',
    );
    // MOB-164: FLAG_SECURE gesetzt (Umschalter leer, kein Bildschirmfoto).
    final fenster = await adb(['shell', 'dumpsys', 'window', 'windows']);
    final sicher = RegExp(r'SECURE').hasMatch(fenster);
    print('MOB-164 FLAG_SECURE im Fenster: $sicher');
    expect(sicher, isTrue);
    // Drei Seiten tief: Album → Foto → Angaben.
    await schliesse(tester);
    await bereich(tester, de.navAlben);
    await tippe(tester, find.text('Geheimes Album'), ms: 1200);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterAngaben), ms: 1200);
    // MOB-161/166: verlassen, zurück; Abfrage abbrechen.
    await hinterUndVor(tester, const Duration(seconds: 3));
    await abfrageAbbrechen(tester);
    await warte(tester, find.text(de.appSperreGesperrt));
    expect(find.text(de.appSperreEntsperren), findsOneWidget);
    await ruhe(tester, 3000);
    expect(
      find.text(de.appSperreGesperrt),
      findsOneWidget,
      reason: 'keine Schleife',
    );
    for (var i = 0; i < 3; i++) {
      await adb(['shell', 'input', 'keyevent', '4']);
      await ruhe(tester, 800);
    }
    expect(
      find.text(de.appSperreGesperrt),
      findsOneWidget,
      reason: 'Zurück schliesst nichts',
    );
    await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
    await pinEingeben(tester);
    await warteWeg(tester, find.text(de.appSperreGesperrt));
    expect(
      find.text(de.angabenTitel),
      findsOneWidget,
      reason: 'dieselbe Seite wie vorher',
    );
    // Sperre wieder aus (für die nächsten Prüfungen).
    await schliesse(tester);
  });

  pruefung('MOB-162 Frist der Sperre', (tester) async {
    final k = await kontoMitFotos('A162', 1);
    await pinSetzen();
    final (s, _) = await starteMitSperre(
      tester,
      server: hauptApp,
      konto: k.konto,
    );
    await warteAufKacheln(tester, 1);
    await _einstellungen(tester);
    if (!tester.widget<Switch>(_sperrSchalter()).value) {
      await tippe(tester, _sperrSchalter(), ms: 300);
      await pinEingeben(tester);
    }
    // Längere Frist verlangt die PIN.
    await tippe(tester, find.text(de.appSperreMinuten(5)), ms: 300);
    await pinEingeben(tester);
    expect(s.appSperre!.frist, const Duration(minutes: 5));
    // Kürzere nicht.
    await tippe(tester, find.text(de.appSperreMinuten(1)), ms: 1500);
    expect(s.appSperre!.frist, const Duration(minutes: 1));
    await hinterUndVor(tester, const Duration(seconds: 30));
    expect(
      find.text(de.appSperreGesperrt),
      findsNothing,
      reason: 'nach 30 s frei',
    );
    await hinterUndVor(tester, const Duration(minutes: 2));
    await warte(
      tester,
      find.text(de.appSperreGesperrt),
      max: const Duration(seconds: 10),
    );
    await abfrageAbbrechen(tester);
    await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
    await pinEingeben(tester);
  });

  pruefung('MOB-168 Kein Aussperren ohne Gerätecode', (tester) async {
    final k = await kontoMitFotos('A168', 1);
    await pinSetzen();
    final (s, _) = await starteMitSperre(
      tester,
      server: hauptApp,
      konto: k.konto,
    );
    await warteAufKacheln(tester, 1);
    await _einstellungen(tester);
    if (!tester.widget<Switch>(_sperrSchalter()).value) {
      await tippe(tester, _sperrSchalter(), ms: 300);
      await pinEingeben(tester);
    }
    expect(s.appSperre!.an, isTrue);
    await steuer('adb/spaeter', {
      'args': [
        'shell',
        'am',
        'start',
        '-n',
        '$_paket/de.dasevo.photovault.MainActivity',
      ],
      'nach': 6,
    });
    await adb(['shell', 'input', 'keyevent', '3']);
    await pinEntfernen();
    await Future<void>.delayed(const Duration(seconds: 8));
    await ruhe(tester, 4000);
    expect(
      find.text(de.appSperreGesperrt),
      findsNothing,
      reason: 'sperrt nicht aus',
    );
    expect(s.appSperre!.an, isFalse, reason: 'Sperre schaltet sich ab');
    expect(tester.widget<Switch>(_sperrSchalter()).value, isFalse);
  });

  pruefung('MOB-167 Video hält beim Sperren an', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A167');
    final v = await api(hauptDirekt, konto);
    await hochladenDatei(v, 'video_5s.mp4');
    await pinSetzen();
    await starteMitSperre(tester, server: hauptApp, konto: konto);
    await warteAufKacheln(tester, 1);
    await _einstellungen(tester);
    if (!tester.widget<Switch>(_sperrSchalter()).value) {
      await tippe(tester, _sperrSchalter(), ms: 300);
      await pinEingeben(tester);
    }
    await tippe(tester, find.text(de.appSperreSofort), ms: 1000);
    await schliesse(tester);
    await bereich(tester, de.navZeitleiste);
    await oeffneKachel(tester, 0);
    final spieler = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'VideoPlayer',
    );
    await warte(tester, spieler, max: const Duration(seconds: 30));
    dynamic c() => (tester.widget(spieler) as dynamic).controller;
    await warteBis(tester, () => c().value.isPlaying == true, grund: 'spielt');
    await hinterUndVor(tester, const Duration(seconds: 2));
    await abfrageAbbrechen(tester);
    await warte(tester, find.text(de.appSperreGesperrt));
    expect(c().value.isPlaying, isFalse, reason: 'kein Ton hinter der Sperre');
    await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
    await pinEingeben(tester);
    await ruhe(tester, 1500);
    expect(c().value.isPlaying, isFalse, reason: 'erst nach Tipp weiter');
  });

  pruefung('MOB-177 Nur im WLAN; einmal mobil sichern', (tester) async {
    await PhotoManager.requestPermissionExtend();
    final konto = await kontoAnlegen(hauptDirekt, 'A177');
    await PhotoManager.editor.saveImage(
      jpeg(breite: 300, hoehe: 200),
      filename: 'a177_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await adb(['shell', 'svc', 'wifi', 'disable']);
    await ruhe(tester, 4000);
    try {
      await starteApp(tester, server: hauptApp, konto: konto);
      await kontoOeffnen(tester);
      await rolleZu(tester, find.text(de.sicherungTitel));
      await tippe(tester, find.text(de.sicherungTitel), ms: 1200);
      await tippe(
        tester,
        find.widgetWithText(SwitchListTile, de.sicherungAn),
        ms: 3000,
      );
      await warte(
        tester,
        find.textContaining(de.sicherungWartetWlan),
        max: const Duration(seconds: 30),
      );
      await rolleZu(tester, find.text(de.sicherungJetzt));
      await tippe(tester, find.text(de.sicherungJetzt));
      await meldung(tester, de.jetztWartetWlan);
      await tippe(tester, find.text(de.jetztMobil), ms: 1500);
      final alle = await PhotoManager.getAssetCount();
      await warteBis(
        tester,
        () => find.text(de.sicherungStand(alle, alle)).evaluate().isNotEmpty,
        max: const Duration(minutes: 3),
        grund: 'ein Lauf über Mobilfunk',
      );
      await PhotoManager.editor.saveImage(
        jpeg(breite: 300, hoehe: 200),
        filename: 'a177n_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ruhe(tester, 15000);
      await warte(
        tester,
        find.textContaining(de.sicherungWartetWlan),
        max: const Duration(seconds: 30),
      );
    } finally {
      await adb(['shell', 'svc', 'wifi', 'enable']);
    }
  });

  pruefung('MOB-192 Sofort im Hintergrund und Akku-Ausnahme', (tester) async {
    await PhotoManager.requestPermissionExtend();
    await adb(['shell', 'dumpsys', 'deviceidle', 'whitelist', '-$_paket']);
    final konto = await kontoAnlegen(hauptDirekt, 'A192');
    await starteApp(tester, server: hauptApp, konto: konto);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.sicherungTitel));
    await tippe(tester, find.text(de.sicherungTitel), ms: 1200);
    await tippe(
      tester,
      find.widgetWithText(SwitchListTile, de.sicherungAn),
      ms: 3000,
    );
    await rolleZu(tester, find.text(de.sicherungSofort));
    await warte(tester, find.text(de.sicherungSofortAndroidGedrosselt));
    expect(find.text(de.sicherungSofortAkku), findsOneWidget);
    // „Nicht zurückhalten“ erlauben (hier per adb wie im Systemdialog).
    await adb(['shell', 'dumpsys', 'deviceidle', 'whitelist', '+$_paket']);
    await hinterUndVor(tester, const Duration(seconds: 2));
    await warte(
      tester,
      find.text(de.sicherungSofortAndroid),
      max: const Duration(seconds: 20),
    );
    expect(find.text(de.sicherungSofortAkku), findsNothing);
  });

  pruefung('MOB-088 Neues in angehefteten Alben nur im WLAN', (tester) async {
    final k = await kontoMitFotos('A088', 1);
    final album = uuid();
    await mitRechner(hauptDirekt, k.konto, (r) async {
      await r.tue(AlbumAnlegen(album, 'Angeheftet', DateTime.now()));
      await r.tue(AlbumFuellen(album, k.ids));
    });
    final app = await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 1);
    await app.sitzung.setzeAlbumOffline(album, true);
    final neu = await hochladen(
      k.v,
      jpeg(breite: 800, hoehe: 600),
      'a088_neu.jpg',
    );
    await mitRechner(
      hauptDirekt,
      k.konto,
      (r) => r.tue(AlbumFuellen(album, [neu])),
    );
    await app.sitzung.gleicheAb();
    await ruhe(tester, 2000);
    await adb(['shell', 'svc', 'wifi', 'disable']);
    await ruhe(tester, 4000);
    try {
      expect(await app.sitzung.imWlan(), isFalse);
      await proxyLogLeeren();
      await app.sitzung.pflegeOfflineUndZwischenspeicher();
      final ohne = (await proxyLog())
          .where((e) => '${e['pfad']}'.contains('/originals/'))
          .length;
      print('MOB-088 Originale über Mobilfunk geholt: $ohne');
      expect(ohne, 0);
    } finally {
      await adb(['shell', 'svc', 'wifi', 'enable']);
    }
    await warteBis(
      tester,
      () => app.sitzung.imWlan(),
      max: const Duration(seconds: 60),
      grund: 'WLAN wieder da',
    );
    await ruhe(tester, 3000);
    await proxyLogLeeren();
    await app.sitzung.pflegeOfflineUndZwischenspeicher();
    final mit = (await proxyLog())
        .where((e) => '${e['pfad']}'.contains('/originals/'))
        .length;
    print('MOB-088 Originale im WLAN geholt: $mit');
    expect(mit, greaterThan(0));
  });
}

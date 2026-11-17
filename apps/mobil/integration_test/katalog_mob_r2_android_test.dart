// ignore_for_file: avoid_print
// Zweite Prüfrunde der Handy-App, Teil Android (pruefkatalog/teile/MOB.json):
// Hintergrundaufgaben, Netz, Laden, Vordergrunddienst und die echten
// Rückfragen des Systems im eigenen Emulator photovault_test
// (emulator-5574) gegen die Wegwerf-Server der Runde (Proxy „haupt2“).
// adb läuft über die Steuerung pruefkatalog/arbeit/r2-mob/mob_steuer_r2.py.
//
//   adb -s emulator-5574 uninstall de.dasevo.photovault.test   (frisch)
//   flutter test integration_test/katalog_mob_r2_android_test.dart \
//     -d emulator-5574 --dart-define=PV_HOST=<Adresse des Rechners im Emulator> \
//     --dart-define=PV_PROXY_NAME=haupt2 --dart-define=PV_PROXY_PORT=18862
//
// Hintergrundläufe lesen die Kopie im Standardordner der App
// (Sitzung.vorgabeOrdner); die Prüfungen dafür verbinden sich deshalb dort
// und melden sich am Ende ab.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_vault_mobil/app_sperre.dart';
import 'package:photo_vault_mobil/main.dart' show PhotoVaultMobil;
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:workmanager/workmanager.dart';

import 'katalog_hilfen.dart';
import 'katalog_r2_hilfen.dart';

const _paket = 'de.dasevo.photovault.test';
const _pin = '1234';
const _fix = '$katalog/arbeit/r2-mob/fixtures/android';

Future<String> adb(List<String> args) async {
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

Future<void> spaeter(List<String> args, double sekunden) =>
    steuer('adb/spaeter', {'args': args, 'nach': sekunden});

Future<void> pinSetzen() => adb(['shell', 'locksettings', 'set-pin', _pin]);
Future<void> pinEntfernen() =>
    adb(['shell', 'locksettings', 'clear', '--old', _pin]);

Future<void> pinEingeben(WidgetTester tester) async {
  await ruhe(tester, 1500);
  await adb(['shell', 'input', 'text', _pin]);
  await adb(['shell', 'input', 'keyevent', '66']);
  await ruhe(tester, 1500);
}

/// Schaltet den Sperrschalter um und bestätigt die Systemabfrage mit der
/// PIN – mit bis zu drei Versuchen, falls die Abfrage spät erscheint.
Future<void> sperreUmschalten(
  WidgetTester tester,
  Finder schalter,
  bool ziel,
) async {
  for (var versuch = 0; versuch < 3; versuch++) {
    if (tester.widget<Switch>(schalter).value == ziel) return;
    await tippe(tester, schalter, ms: 300);
    for (var i = 0; i < 6; i++) {
      await ruhe(tester, 1500);
      final k = await knoten();
      final pinFeld = k.any(
        (x) =>
            x.id.contains('lockPassword') ||
            x.id.contains('password_entry') ||
            x.text.toLowerCase().contains('pin'),
      );
      if (pinFeld) break;
    }
    await adb(['shell', 'input', 'text', _pin]);
    await adb(['shell', 'input', 'keyevent', '66']);
    await ruhe(tester, 3000);
    if (tester.widget<Switch>(schalter).value == ziel) return;
    print(
      'Sperrschalter nach Versuch ${versuch + 1}: ${[for (final x in await knoten())
        if (x.text != '|') x.text].take(15)}',
    );
  }
}

final _start = [
  'shell',
  'am',
  'start',
  '-n',
  '$_paket/de.dasevo.photovault.MainActivity',
];

/// Ein Foto vom Mac in die Galerie legen (eigene Prüfsumme je Datei).
Future<String> fotoInGalerie(
  String name, {
  String ordner = 'DCIM/Camera',
}) async {
  final ziel = '/sdcard/$ordner/${DateTime.now().millisecondsSinceEpoch}_$name';
  await adb(['push', '$_fix/$name', ziel]);
  await scanne(ziel);
  return ziel;
}

Future<void> scanne(String pfad) => adb([
  'shell',
  'am',
  'broadcast',
  '-a',
  'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
  '-d',
  'file://$pfad',
]);

/// Knoten der aktuellen Oberfläche (uiautomator), mit Text und Mitte.
Future<List<({String text, String id, int x, int y})>> knoten() async {
  await adb(['shell', 'uiautomator', 'dump', '/sdcard/r2_ui.xml']);
  final xml = await adb(['shell', 'cat', '/sdcard/r2_ui.xml']);
  final l = <({String text, String id, int x, int y})>[];
  for (final m in RegExp(r'<node [^>]*>').allMatches(xml)) {
    final n = m.group(0)!;
    String a(String k) => RegExp('$k="([^"]*)"').firstMatch(n)?.group(1) ?? '';
    final b = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]').firstMatch(a('bounds'));
    if (b == null) continue;
    final x1 = int.parse(b.group(1)!), y1 = int.parse(b.group(2)!);
    final x2 = int.parse(b.group(3)!), y2 = int.parse(b.group(4)!);
    l.add((
      text: '${a('text')}|${a('content-desc')}',
      id: a('resource-id'),
      x: (x1 + x2) ~/ 2,
      y: (y1 + y2) ~/ 2,
    ));
  }
  return l;
}

/// Tippt im System (Rückfrage, Wähler) auf den ersten Knoten mit [text].
Future<bool> systemTipp(List<String> texte) async {
  for (var versuch = 0; versuch < 8; versuch++) {
    final k = await knoten();
    for (final t in texte) {
      final n = k
          .where(
            (x) => x.text.toLowerCase().split('|').contains(t.toLowerCase()),
          )
          .firstOrNull;
      if (n != null) {
        await adb(['shell', 'input', 'tap', '${n.x}', '${n.y}']);
        return true;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  print(
    'Systemknopf $texte nicht gefunden: ${[for (final x in await knoten())
      if (x.text != '|') x.text]}',
  );
  return false;
}

/// Die App mit der Kopie im Standardordner (wie nach der echten Anmeldung),
/// damit auch die Hintergrundaufgaben sie finden.
Future<Sitzung> starteStandard(
  WidgetTester tester,
  String konto, {
  bool sperre = false,
}) async {
  await einrichten();
  await appBeenden(tester);
  final ordner = await Sitzung.vorgabeOrdner();
  if (await ordner.exists()) await ordner.delete(recursive: true);
  final einstellung = File(
    p.join((await getApplicationSupportDirectory()).path, 'app_sperre.json'),
  );
  if (await einstellung.exists()) await einstellung.delete();
  final s = Sitzung();
  if (sperre) {
    s.appSperre = await AppSperre.lade();
    final zurueck = SperrZurueck(s.appSperre!);
    WidgetsBinding.instance.addObserver(zurueck);
    addTearDown(() => WidgetsBinding.instance.removeObserver(zurueck));
  }
  final t = await holeToken(hauptDirekt, konto, geraet: 'Telefon');
  await s.verbinde(server: hauptApp, konto: konto, geraet: 'Telefon', token: t);
  await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
  await ruhe(tester, 1000);
  return s;
}

Future<void> abmeldenUndWeg(WidgetTester tester, Sitzung s) async {
  try {
    await s.abmelden();
  } catch (e) {
    print('abmelden: $e');
  }
  await tester.pumpWidget(const SizedBox());
  await ruhe(tester, 500);
}

Future<void> sicherungEin(
  WidgetTester tester,
  Sitzung s, {
  bool nurWlan = true,
  bool nurBeimLaden = false,
}) async {
  final d = s.sicherung!;
  await d.setze(
    d.einstellungen.mit(nurWlan: nurWlan, nurBeimLaden: nurBeimLaden),
  );
  await sicherungsseite(tester);
  await schalter(tester, de.sicherungAn, true);
}

Future<void> warteLaufEnde(
  WidgetTester tester,
  Sitzung s,
  DateTime ab, {
  Duration max = const Duration(minutes: 5),
}) => warteBis(
  tester,
  () {
    final d = s.sicherung!;
    final l = d.letzterLauf;
    return !d.laeuft && l != null && l.ende.isAfter(ab);
  },
  max: max,
  grund: 'Lauf zu Ende',
);

/// Die Jobs des JobSchedulers für diese App (SystemJobService), als
/// Argumente für `cmd jobscheduler run`: Namensraum und Kennung.
Future<List<List<String>>> jobIds() async {
  final aus = await adb(['shell', 'dumpsys', 'jobscheduler', _paket]);
  final jobs = <String, List<String>>{};
  for (final m in RegExp(
    r'JOB (?:([\w.]+):)?u0a\d+/(\d+): [0-9a-f]+ @[^\s]*@de\.dasevo\.photovault\.test/androidx\.work',
  ).allMatches(aus)) {
    final ns = m.group(1);
    jobs['${ns ?? ''}/${m.group(2)}'] = [
      if (ns != null) ...['-n', ns],
      m.group(2)!,
    ];
  }
  return jobs.values.toList();
}

List<String> jobLauf(List<String> job, {String art = '-f'}) => [
  'shell',
  'cmd',
  'jobscheduler',
  'run',
  art,
  ...job.sublist(0, job.length - 1),
  _paket,
  job.last,
];

Future<int> anzahlHochladen(DateTime ab) async => [
  for (final e in await proxyLog())
    if (e['methode'] == 'POST' &&
        e['pfad'] == '/api/v1/hochladen' &&
        (e['zeit'] as num) * 1000 >= ab.millisecondsSinceEpoch)
      e,
].length;

/// Stand einer WorkManager-Aufgabe (mit Frist: die Abfrage hing einmal).
Future<Object?> _arbeit(String name) async {
  try {
    return (await Workmanager()
            .getWorkInfo(name)
            .timeout(const Duration(seconds: 8)))
        ?.state;
  } catch (e) {
    return 'unbekannt ($e)';
  }
}

Finder _sperrSchalter() => find.descendant(
  of: find
      .ancestor(of: find.text(de.appSperreTitel), matching: find.byType(Row))
      .first,
  matching: find.byType(Switch),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Vorbereitung', (tester) async {
    await einrichten();
    await pinEntfernen();
    await adb([
      'shell',
      'pm',
      'grant',
      _paket,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    await adb(['shell', 'svc', 'wifi', 'enable']);
    await adb(['shell', 'svc', 'data', 'enable']);
    await adb(['shell', 'dumpsys', 'battery', 'reset']);
  });

  tearDown(() async {
    await proxyZuruecksetzen();
    await adb(['shell', 'svc', 'wifi', 'enable']);
    await adb(['shell', 'svc', 'data', 'enable']);
  });

  // Zuerst, solange die App nur den Teilzugriff hat (frisch installiert).
  pruefung('MOB-172 Nur ausgewählte Fotos freigegeben', (tester) async {
    await adb([
      'shell',
      'pm',
      'grant',
      _paket,
      'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
    ]);
    final konto = await kontoAnlegen(hauptDirekt, 'A172');
    for (var i = 0; i < 3; i++) {
      await PhotoManager.editor.saveImage(
        jpeg(breite: 300, hoehe: 200),
        filename: 'a172_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
      );
    }
    await fotoInGalerie('r2a_1.jpg');
    await fotoInGalerie('r2a_2.jpg');
    final sichtbar = await PhotoManager.getAssetCount();
    print('MOB-172 sichtbar für die App: $sichtbar');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    // Einschalten fragt das System nach dem Zugriff: „Fotos auswählen“,
    // im Wähler nichts dazunehmen, bestätigen (bleibt beim Teilzugriff).
    final z = find.widgetWithText(SwitchListTile, de.sicherungAn);
    await tester.tap(z);
    await Future<void>.delayed(const Duration(seconds: 3));
    final ablauf = <String>[];
    Future<void> waehle(int n) async {
      // n == 0: bei der bisherigen Auswahl bleiben.
      if (n == 0) {
        if (await systemTipp([
          'Keine weiteren auswählen',
          "Don't select more",
        ])) {
          ablauf.add('bei der Auswahl geblieben');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }
      if (await systemTipp([
        'Eingeschränkten Zugriff zulassen',
        'Fotos und Videos auswählen',
        'Allow limited access',
        'Select photos and videos',
      ])) {
        ablauf.add('Auswahl geöffnet');
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      final k = await knoten();
      final bilder = [
        for (final x in k)
          if (x.text.contains('Photo taken') ||
              x.text.contains('Foto aufgenommen') ||
              x.text.contains('Foto vom'))
            x,
      ];
      ablauf.add(
        '${bilder.length} Bilder im Wähler: ${bilder.map((b) => b.text).take(8)}; '
        'Texte ${[for (final x in k)
          if (x.text != '|') x.text].take(25)}',
      );
      var gewaehlt = 0;
      for (final b in bilder) {
        if (gewaehlt == n) break;
        final t = b.text.toLowerCase();
        final schonGewaehlt =
            (t.contains('ausgewählt') && !t.contains('nicht ausgewählt')) ||
            (t.contains('selected') && !t.contains('not selected'));
        if (schonGewaehlt) continue;
        await adb(['shell', 'input', 'tap', '${b.x}', '${b.y}']);
        gewaehlt++;
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (await systemTipp([
        'Zulassen',
        'Fertig',
        'Allow',
        'Done',
        'Hinzufügen',
        'Add',
      ])) {
        ablauf.add('bestätigt ($gewaehlt)');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    await waehle(0);
    await ruhe(tester, 2000);
    await warte(
      tester,
      find.text(de.sicherungTeilweise),
      max: const Duration(seconds: 30),
    );
    expect(find.textContaining(de.sicherungTeilweiseHinweis), findsOneWidget);
    await warteLaufEnde(
      tester,
      app.sitzung,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final vorher = await serverAnzahl(konto);
    print('MOB-172 am Server: $vorher (sichtbar $sichtbar)');
    expect(vorher, sichtbar, reason: 'nur, was die App sehen darf');
    await tester.tap(find.text(de.sicherungAuswahlAendern));
    await Future<void>.delayed(const Duration(seconds: 3));
    await waehle(2);
    print('MOB-172 Ablauf: $ablauf');
    await ruhe(tester, 3000);
    await warteBis(
      tester,
      () async => await serverAnzahl(konto) >= vorher + 2,
      max: const Duration(minutes: 2),
      grund: 'die zwei weiteren gehen hoch',
    );
  });

  pruefung('MOB-164 Android: Bildschirmfoto und Umschalter mit und ohne Sperre', (
    tester,
  ) async {
    await adb([
      'shell',
      'pm',
      'grant',
      _paket,
      'android.permission.READ_MEDIA_IMAGES',
    ]);
    await adb([
      'shell',
      'pm',
      'grant',
      _paket,
      'android.permission.READ_MEDIA_VIDEO',
    ]);
    final k = await kontoMitFotos('A164', 2);
    await pinSetzen();
    await Future<void>.delayed(const Duration(seconds: 5));
    try {
      final s = await starteStandard(tester, k.konto, sperre: true);
      await warteAufKacheln(tester, 2);
      await bibOeffnen(tester, de.bibEinstellungen);
      await warte(tester, find.text(de.appSperreTitel));
      await sperreUmschalten(tester, _sperrSchalter(), true);
      await warteBis(
        tester,
        () => tester.widget<Switch>(_sperrSchalter()).value,
        grund: 'an',
      );
      await schliesse(tester);
      await bereich(tester, de.navZeitleiste);
      await warteAufKacheln(tester, 2);
      await oeffneKachel(tester, 0);
      Future<({bool sicher, int fotos})> pruefe(String name) async {
        final w = await adb(['shell', 'dumpsys', 'window', 'windows']);
        final block =
            RegExp(
              'Window\\{[^}]*$_paket/de\\.dasevo\\.photovault\\.MainActivity\\}[\\s\\S]*?(?=\\n  Window #|\\Z)',
            ).firstMatch(w)?.group(0) ??
            '';
        final fl = RegExp(r'fl=([^\n]*)').firstMatch(block)?.group(1) ?? '';
        final vorher = (await adb([
          'shell',
          'ls',
          '/sdcard/Pictures/Screenshots',
        ])).split('\n').where((x) => x.endsWith('.png')).length;
        await adb(['shell', 'input', 'keyevent', '120']);
        await ruhe(tester, 2500);
        final nachher = (await adb([
          'shell',
          'ls',
          '/sdcard/Pictures/Screenshots',
        ])).split('\n').where((x) => x.endsWith('.png')).length;
        await adb(['shell', 'input', 'keyevent', '187']);
        await Future<void>.delayed(const Duration(seconds: 2));
        await steuer('adb/shot', {'name': name});
        await adb(['shell', 'input', 'keyevent', '4']);
        await spaeter(_start, 1);
        await Future<void>.delayed(const Duration(seconds: 3));
        await ruhe(tester, 1500);
        print(
          'MOB-164 $name: Fenster fl=$fl; Bildschirmfotos $vorher → $nachher',
        );
        return (sicher: fl.contains('SECURE'), fotos: nachher - vorher);
      }

      final mit = await pruefe('mob164_umschalter_mit_sperre.png');
      // Zurück in die App: ggf. entsperren.
      if (find.text(de.appSperreEntsperren).evaluate().isNotEmpty) {
        await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
        await pinEingeben(tester);
      }
      await appBeenden(tester);
      await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
      await ruhe(tester, 1500);
      if (find.text(de.appSperreEntsperren).evaluate().isNotEmpty) {
        await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
        await pinEingeben(tester);
      }
      await bibOeffnen(tester, de.bibEinstellungen);
      await sperreUmschalten(tester, _sperrSchalter(), false);
      await warteBis(
        tester,
        () => !tester.widget<Switch>(_sperrSchalter()).value,
        grund: 'aus',
      );
      await schliesse(tester);
      final ohne = await pruefe('mob164_umschalter_ohne_sperre.png');
      expect(mit.sicher, isTrue, reason: 'FLAG_SECURE mit Sperre');
      expect(mit.fotos, 0, reason: 'kein Bildschirmfoto mit Sperre');
      expect(ohne.sicher, isFalse);
      expect(ohne.fotos, 1, reason: 'ohne Sperre geht das Bildschirmfoto');
      await abmeldenUndWeg(tester, s);
    } finally {
      await pinEntfernen();
    }
  });

  pruefung('MOB-190 Vordergrunddienst beim Verlassen der App', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A190');
    await fotoInGalerie('r2a_gross.mp4', ordner: 'Movies');
    final s = await starteStandard(tester, konto);
    await proxyRegel({
      'methode': 'PATCH',
      'muster': '^/api/v1/hochladen/',
      'verzoegerung': 6,
    }, proxyName);
    await sicherungEin(tester, s);
    await warteBis(
      tester,
      () =>
          s.sicherung!.laeuft &&
          (s.sicherung!.fortschritt?.datei ?? '').isNotEmpty,
      max: const Duration(minutes: 3),
      grund: 'Upload läuft',
    );
    final t0 = DateTime.now();
    await adb(['logcat', '-c']);
    await spaeter(_start, 560);
    await adb(['shell', 'input', 'keyevent', '3']);
    final befunde = <String>[];
    var gesehen = false;
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      final n = await adb(['shell', 'dumpsys', 'notification', '--noredact']);
      final unsere = RegExp(
        'pkg=$_paket[\\s\\S]*?(?=NotificationRecord|\\Z)',
      ).allMatches(n).map((m) => m.group(0)!).toList();
      final titel = unsere.any(
        (b) => b.contains(de.sicherungBenachrichtigungTitel),
      );
      final kanal = unsere.any((b) => b.contains('channel=sicherung'));
      final dienst = (await adb([
        'shell',
        'dumpsys',
        'activity',
        'services',
        _paket,
      ])).contains('isForeground=true');
      if (titel || i % 6 == 0) {
        befunde.add(
          '${DateTime.now().difference(t0).inSeconds}s: Benachrichtigung $titel Kanal $kanal Vordergrund $dienst',
        );
      }
      if (i == 0) {
        befunde.add(
          'Übergabe gleich nach dem Verlassen: ${await _arbeit('de.dasevo.photovault.sicherung.weiter')}',
        );
      }
      if (titel) gesehen = true;
      if (gesehen && !titel) break;
    }
    final log = await adb(['logcat', '-d', '-t', '400']);
    final absturz = RegExp(
      r'ForegroundServiceDidNotStartInTime|startForeground[^\n]*|FATAL EXCEPTION[^\n]*',
    ).allMatches(log).map((m) => m.group(0)).take(5).toList();
    print('MOB-190 $befunde\nMOB-190 Protokoll: $absturz');
    await adb(_start);
    await ruhe(tester, 3000);
    final l = s.sicherung!.letzterLauf;
    final weiter = await _arbeit('de.dasevo.photovault.sicherung.weiter');
    print(
      'MOB-190 letzter Lauf ${l?.ende} offen ${l?.offen}; Übergabe $weiter; am Server ${await serverAnzahl(konto)}',
    );
    expect(
      gesehen,
      isTrue,
      reason: 'Benachrichtigung „Photo Vault sichert Fotos“',
    );
    await abmeldenUndWeg(tester, s);
  });

  pruefung('MOB-191 MOB-181 Hintergrundaufgabe: periodisch, nur beim Laden', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A191');
    final s = await starteStandard(tester, konto);
    await sicherungEin(tester, s);
    await warteLaufEnde(
      tester,
      s,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await PhotoManager.stopChangeNotify();
    await Workmanager().cancelByUniqueName(
      'de.dasevo.photovault.sicherung.waechter',
    );
    await Workmanager().cancelByUniqueName(
      'de.dasevo.photovault.sicherung.sofort',
    );
    final jobs = await jobIds();
    print('MOB-191 Jobs: $jobs');
    Future<int> imHintergrund(
      List<List<String>> befehle, {
      double dauer = 60,
    }) async {
      final vorher = await serverAnzahl(konto);
      var t = 4.0;
      for (final b in befehle) {
        await spaeter(b, t);
        t += 8;
      }
      await spaeter(_start, dauer);
      await adb(['shell', 'input', 'keyevent', '3']);
      await Future<void>.delayed(Duration(seconds: dauer.round() + 4));
      await ruhe(tester, 2000);
      return await serverAnzahl(konto) - vorher;
    }

    final ziel =
        '/sdcard/DCIM/Camera/${DateTime.now().millisecondsSinceEpoch}_r2a_3.jpg';
    final scan = [
      'shell',
      'am',
      'broadcast',
      '-a',
      'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
      '-d',
      'file://$ziel',
    ];
    final lauf = [for (final j in jobs) jobLauf(j)];
    final neu1 = await imHintergrund([
      ['push', '$_fix/r2a_3.jpg', ziel],
      scan,
      ...lauf,
    ]);
    print('MOB-191 periodisch, App geschlossen: +$neu1');
    // Nur im WLAN, nur Mobilfunk: nichts.
    await adb(['shell', 'svc', 'wifi', 'disable']);
    await Future<void>.delayed(const Duration(seconds: 4));
    final ziel2 =
        '/sdcard/DCIM/Camera/${DateTime.now().millisecondsSinceEpoch}_r2a_4.jpg';
    final neu2 = await imHintergrund([
      ['push', '$_fix/r2a_4.jpg', ziel2],
      [
        'shell',
        'am',
        'broadcast',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        'file://$ziel2',
      ],
      ...lauf,
    ]);
    print('MOB-191 nur Mobilfunk, „Nur im WLAN“: +$neu2');
    await adb(['shell', 'svc', 'wifi', 'enable']);
    await Future<void>.delayed(const Duration(seconds: 6));
    // MOB-181: nur beim Laden.
    await ruhe(tester, 1500);
    // Den Schalter „Im Hintergrund nur beim Laden“ wie die Seite setzen
    // (dienst.setze plant die Aufgaben mit der Ladebedingung neu).
    final d = s.sicherung!;
    await d.setze(d.einstellungen.mit(nurBeimLaden: true));
    await ruhe(tester, 2000);
    await adb(['shell', 'dumpsys', 'battery', 'unplug']);
    await adb(['shell', 'dumpsys', 'battery', 'set', 'status', '3']);
    final jobs2 = await jobIds();
    final ziel3 =
        '/sdcard/DCIM/Camera/${DateTime.now().millisecondsSinceEpoch}_r2a_5.jpg';
    final lauf2 = [for (final j in jobs2) jobLauf(j, art: '-s')];
    final neu3 = await imHintergrund([
      ['push', '$_fix/r2a_5.jpg', ziel3],
      [
        'shell',
        'am',
        'broadcast',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        'file://$ziel3',
      ],
      ...lauf2,
    ]);
    final bedingungen = await adb(['shell', 'dumpsys', 'jobscheduler', _paket]);
    final laden = RegExp(
      r'Unsatisfied constraints:[^\n]*',
    ).allMatches(bedingungen).map((m) => m.group(0)).toSet();
    print('MOB-181 ohne Laden: +$neu3; $laden');
    await adb(['shell', 'dumpsys', 'battery', 'set', 'ac', '1']);
    await adb(['shell', 'dumpsys', 'battery', 'set', 'status', '2']);
    final neu4 = await imHintergrund([...lauf2], dauer: 50);
    print('MOB-181 mit Laden: +$neu4');
    // App offen, ohne Kabel: „Jetzt sichern“ sichert trotzdem.
    await adb(['shell', 'dumpsys', 'battery', 'unplug']);
    await adb(['shell', 'dumpsys', 'battery', 'set', 'status', '3']);
    await PhotoManager.editor.saveImage(
      jpeg(breite: 300, hoehe: 200),
      filename: 'a181_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await meldungenWeg(tester);
    final vorOffen = await serverAnzahl(konto);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await warteBis(
      tester,
      () async => await serverAnzahl(konto) > vorOffen,
      max: const Duration(minutes: 2),
      grund: 'offen ohne Kabel',
    );
    await adb(['shell', 'dumpsys', 'battery', 'reset']);
    await abmeldenUndWeg(tester, s);
    expect(
      neu1,
      greaterThanOrEqualTo(1),
      reason: 'MOB-191 periodisch ohne offene App',
    );
    expect(neu2, 0, reason: 'MOB-191 „Nur im WLAN“ ohne WLAN: nichts');
    expect(neu3, 0, reason: 'MOB-181 ohne Laden: nichts');
    expect(neu4, greaterThanOrEqualTo(1), reason: 'MOB-181 mit Laden');
  });

  pruefung('MOB-169 Sicherung läuft trotz App-Sperre', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A169');
    await pinSetzen();
    await Future<void>.delayed(const Duration(seconds: 5));
    try {
      final s = await starteStandard(tester, konto, sperre: true);
      await sicherungEin(tester, s);
      await warteLaufEnde(
        tester,
        s,
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await zurueck(tester);
      await zurueck(tester);
      await bibOeffnen(tester, de.bibEinstellungen);
      await sperreUmschalten(tester, _sperrSchalter(), true);
      await warteBis(
        tester,
        () => tester.widget<Switch>(_sperrSchalter()).value,
        grund: 'Sperre an',
      );
      final vorher = await serverAnzahl(konto);
      final ziel =
          '/sdcard/DCIM/Camera/${DateTime.now().millisecondsSinceEpoch}_r2a_6.jpg';
      await spaeter(['push', '$_fix/r2a_6.jpg', ziel], 8);
      await spaeter([
        'shell',
        'am',
        'broadcast',
        '-a',
        'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
        '-d',
        'file://$ziel',
      ], 12);
      await spaeter(_start, 100);
      final weg = DateTime.now();
      await adb(['shell', 'input', 'keyevent', '3']);
      await Future<void>.delayed(const Duration(seconds: 104));
      await ruhe(tester, 2000);
      final zurueckZeit = DateTime.now();
      final gesperrt = find.text(de.appSperreGesperrt).evaluate().isNotEmpty;
      final nachher = await serverAnzahl(konto);
      final hoch = [
        for (final e in await proxyLog())
          if (e['methode'] == 'POST' &&
              e['pfad'] == '/api/v1/hochladen' &&
              (e['zeit'] as num) * 1000 > weg.millisecondsSinceEpoch)
            e['zeit'],
      ];
      print(
        'MOB-169 gesperrt beim Zurückkommen $gesperrt; Server $vorher → $nachher; Uploads $hoch (zurück ${zurueckZeit.millisecondsSinceEpoch / 1000})',
      );
      expect(nachher, vorher + 1, reason: 'ohne Entsperren auf den Server');
      expect(gesperrt, isTrue, reason: 'die App blieb gesperrt');
      if (gesperrt) {
        await tippe(tester, find.text(de.appSperreEntsperren), ms: 300);
        await pinEingeben(tester);
      }
      await abmeldenUndWeg(tester, s);
    } finally {
      await pinEntfernen();
    }
  });

  pruefung('MOB-195 Nach dem Abmelden keine Uploads mehr', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A195');
    final s = await starteStandard(tester, konto);
    await sicherungEin(tester, s);
    await warteLaufEnde(
      tester,
      s,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final jobs = await jobIds();
    final namen = [
      'de.dasevo.photovault.sicherung',
      'de.dasevo.photovault.sicherung.weiter',
      'de.dasevo.photovault.sicherung.waechter',
      'de.dasevo.photovault.sicherung.sofort',
    ];
    final vorher = {for (final n in namen) n: await _arbeit(n)};
    print('MOB-195 vorher: Jobs $jobs, Aufgaben $vorher');
    await zurueck(tester);
    await zurueck(tester);
    await kontoOeffnen(tester);
    await rolleZu(tester, find.text(de.kontoAbmeldenHinweis));
    await tippe(tester, find.text(de.kontoAbmeldenHinweis));
    await warte(tester, find.text(de.kontoAbmeldenTitel));
    await tippe(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
      ms: 3000,
    );
    await warte(
      tester,
      find.text(de.anmeldenTitel),
      max: const Duration(seconds: 30),
    );
    final nachher = {for (final n in namen) n: await _arbeit(n)};
    final jobs2 = await jobIds();
    print('MOB-195 nachher: Jobs $jobs2, Aufgaben $nachher');
    final t0 = DateTime.now();
    await proxyLogLeeren();
    await fotoInGalerie('r2a_7.jpg');
    for (final j in jobs) {
      print('MOB-195 alter Job $j: ${await adb(jobLauf(j))}');
    }
    await ruhe(tester, 30000);
    final anfragen = [
      for (final x in await proxyPfade())
        if (x.contains('/pruefsummen') || x.contains('/hochladen')) x,
    ];
    print('MOB-195 Anfragen nach dem Abmelden: $anfragen');
    expect(anfragen, isEmpty);
    expect(await anzahlHochladen(t0), 0);
    expect(jobs2, isEmpty, reason: 'eingeplante Aufgaben gestrichen');
    await tester.pumpWidget(const SizedBox());
  });

  pruefung('MOB-175 Endgültig gelöscht kommt nicht wieder; bearbeitet schon', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A175');
    final pfad = await fotoInGalerie('r2a_8.jpg');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungAn, true);
    await warteLaufEnde(
      tester,
      app.sitzung,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final ids = await mitRechner(
      hauptDirekt,
      konto,
      (r) async => [
        for (final z
            in await r.db
                .customSelect(
                  "SELECT id FROM assets WHERE original_file_name LIKE '%r2a_8.jpg'",
                )
                .get())
          z.read<String>('id'),
      ],
    );
    expect(ids, hasLength(1));
    // Im „Web“ in den Papierkorb und den Papierkorb leeren.
    await mitRechner(hauptDirekt, konto, (r) => r.tue(InDenPapierkorb(ids)));
    final v = await api(hauptDirekt, konto);
    await v.schicke('api/v1/papierkorb/leeren', {'alle': true});
    final vorher = await serverAnzahl(konto);
    await meldungenWeg(tester);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await ruhe(tester, 8000);
    final nachJetzt = await serverAnzahl(konto);
    // Am Telefon bearbeiten: dieselbe Datei mit neuem Inhalt.
    final vorBearb = await adb([
      'shell',
      'content',
      'query',
      '--uri',
      'content://media/external/images/media',
      '--projection',
      '_id:date_modified',
      '--where',
      "_data='$pfad'",
    ]);
    await adb(['push', '$_fix/r2a_9.jpg', pfad]);
    await Future<void>.delayed(const Duration(seconds: 2));
    await scanne(pfad);
    await Future<void>.delayed(const Duration(seconds: 2));
    final nachBearb = await adb([
      'shell',
      'content',
      'query',
      '--uri',
      'content://media/external/images/media',
      '--projection',
      '_id:date_modified',
      '--where',
      "_data='$pfad'",
    ]);
    print('MOB-175 MediaStore vorher $vorBearb nachher $nachBearb');
    await meldungenWeg(tester);
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await warteBis(
      tester,
      () async => await serverAnzahl(konto) > nachJetzt,
      max: const Duration(minutes: 2),
      grund: 'bearbeitet: geht wieder hoch',
    );
    print(
      'MOB-175 Server: $vorher → nach „Jetzt sichern“ $nachJetzt → nach Bearbeiten ${await serverAnzahl(konto)}',
    );
    expect(
      nachJetzt,
      vorher,
      reason: 'endgültig Gelöschtes kommt nicht wieder',
    );
  });

  pruefung(
    'MOB-177 MOB-183 MOB-184 WLAN, Mobilfunk, kein Netz; nur auf dem Telefon',
    (tester) async {
      final konto = await kontoAnlegen(hauptDirekt, 'A177');
      final app = await starteApp(tester, server: hauptApp, konto: konto);
      await sicherungsseite(tester);
      await schalter(tester, de.sicherungAn, true);
      await warteLaufEnde(
        tester,
        app.sitzung,
        DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final d = app.sitzung.sicherung!;
      await adb(['shell', 'svc', 'wifi', 'disable']);
      await ruhe(tester, 5000);
      await PhotoManager.editor.saveImage(
        jpeg(breite: 300, hoehe: 200),
        filename: 'a177_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ruhe(tester, 5000);
      await warte(
        tester,
        find.textContaining(de.sicherungWartetWlan),
        max: const Duration(seconds: 40),
      );
      var laeufe = 0;
      var vorher = d.laeuft;
      void zaehle() {
        if (d.laeuft && !vorher) laeufe++;
        vorher = d.laeuft;
      }

      d.addListener(zaehle);
      await meldungenWeg(tester);
      await rolleZu(tester, find.text(de.sicherungJetzt));
      await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
      await meldung(tester, de.jetztWartetWlan);
      final t0 = DateTime.now();
      await tippe(tester, find.text(de.jetztMobil), ms: 1500);
      await warteLaufEnde(
        tester,
        app.sitzung,
        t0,
        max: const Duration(minutes: 3),
      );
      print(
        'MOB-177 nach „Mobil sichern“: offen ${d.letzterLauf?.offen}, Läufe $laeufe',
      );
      expect(d.letzterLauf!.offen, 0);
      final hoch1 = await anzahlHochladen(t0);
      // Neues Foto: wartet wieder.
      final t1 = DateTime.now();
      await PhotoManager.editor.saveImage(
        jpeg(breite: 300, hoehe: 200),
        filename: 'a177n_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ruhe(tester, 30000);
      final hoch2 = await anzahlHochladen(t1);
      print(
        'MOB-177 Uploads: über Mobilfunk $hoch1, danach $hoch2; Läufe $laeufe; wartet ${d.wartet}',
      );
      expect(hoch1, 1);
      expect(laeufe, 1, reason: 'genau ein Lauf über Mobilfunk');
      expect(hoch2, 0, reason: 'das neue Foto wartet wieder auf WLAN');
      d.removeListener(zaehle);
      // MOB-184: Kopfzeile der Zeitleiste mit „Wartet auf WLAN“; echtes
      // Löschen vom Telefon über die Rückfrage des Systems.
      await zurueck(tester);
      await zurueck(tester);
      await PhotoManager.editor.saveImage(
        jpeg(breite: 300, hoehe: 200),
        filename: 'a184_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ruhe(tester, 10000);
      final ohneZiehen = find.text(de.lokalAnzahl(2)).evaluate().isNotEmpty;
      print('MOB-184 Zeile ohne Ziehen nach 10 s: $ohneZiehen');
      // Ziehen an der Zeitleiste selbst (RefreshIndicator).
      await tester.fling(
        find
            .descendant(
              of: find.byType(RefreshIndicator).first,
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 400),
        1200,
      );
      await ruhe(tester, 2500);
      await warte(
        tester,
        find.text(de.lokalAnzahl(2)),
        max: const Duration(seconds: 40),
      );
      final kopf = sichtbareTexte(tester)
          .where(
            (t) => t.contains('Wartet') || t.contains('nur auf dem Telefon'),
          )
          .toList();
      print('MOB-184 Kopfzeile: $kopf');
      expect(find.textContaining(de.sicherungWartetWlan), findsWidgets);
      final lokal = find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString() == 'Miniatur' &&
            (((w as dynamic).zeile?.id as String?)?.startsWith('lokal:') ??
                false),
      );
      await rolleZu(tester, lokal);
      await tippe(tester, lokal.first, ms: 1500);
      await warte(tester, find.text(de.lokalNochNichtGesichert));
      final vorZahl = await PhotoManager.getAssetCount();
      await tippe(tester, tooltip(de.lokalVomTelefonLoeschen), ms: 2500);
      final bestaetigt = await systemTipp([
        'Allow',
        'Zulassen',
        'Delete',
        'Löschen',
      ]);
      await meldung(
        tester,
        de.vomTelefonGeloescht(1),
        max: const Duration(seconds: 30),
      );
      print(
        'MOB-184 Systemrückfrage bestätigt $bestaetigt; Galerie $vorZahl → ${await PhotoManager.getAssetCount()}',
      );
      expect(await PhotoManager.getAssetCount(), vorZahl - 1);
      // MOB-183: ganz ohne Netz, „Nur im WLAN“ aus.
      await adb(['shell', 'svc', 'data', 'disable']);
      await d.setze(d.einstellungen.mit(nurWlan: false));
      await ruhe(tester, 4000);
      await sicherungsseite(tester);
      await meldungenWeg(tester);
      await rolleZu(tester, find.text(de.sicherungJetzt));
      await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
      await meldung(
        tester,
        de.sicherungWartetNetz,
        max: const Duration(seconds: 30),
      );
    },
  );

  pruefung('MOB-178 WLAN weg mitten im Upload', (tester) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A178');
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungAn, true);
    await warteLaufEnde(
      tester,
      app.sitzung,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final d = app.sitzung.sicherung!;
    await proxyRegel({
      'methode': 'PATCH',
      'muster': '^/api/v1/hochladen/',
      'verzoegerung': 8,
    }, proxyName);
    await proxyLogLeeren();
    await fotoInGalerie('r2a_gross2.mp4', ordner: 'Movies');
    await meldungenWeg(tester);
    await rolleZu(tester, find.text(de.sicherungJetzt));
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await warteBis(
      tester,
      () => d.laeuft && (d.fortschritt?.datei ?? '').isNotEmpty,
      max: const Duration(minutes: 2),
      grund: 'grosses Video läuft',
    );
    await warteBis(
      tester,
      () async => (await proxyPfade()).any((x) => x.startsWith('PATCH')),
      max: const Duration(seconds: 60),
      grund: 'erstes Stück',
    );
    final t0 = DateTime.now();
    await adb(['shell', 'svc', 'wifi', 'disable']);
    await warteBis(
      tester,
      () => !d.laeuft,
      max: const Duration(seconds: 60),
      grund: 'Upload hört auf',
    );
    final stop = DateTime.now().difference(t0);
    await ruhe(tester, 30000);
    final log = await proxyLog();
    final spaet = [
      for (final e in log)
        if ((e['zeit'] as num) * 1000 > t0.millisecondsSinceEpoch + 20000)
          '${e['methode']} ${e['pfad']}',
    ];
    print(
      'MOB-178 Stopp nach ${stop.inSeconds} s; wartet ${d.wartet}; Anfragen nach 20 s: $spaet',
    );
    final posts = log
        .where(
          (e) => e['methode'] == 'POST' && e['pfad'] == '/api/v1/hochladen',
        )
        .length;
    await adb(['shell', 'svc', 'wifi', 'enable']);
    await ruhe(tester, 8000);
    final t1 = DateTime.now();
    await meldungenWeg(tester);
    await tippe(tester, find.text(de.sicherungJetzt), ms: 300);
    await proxyZuruecksetzen();
    await warteLaufEnde(
      tester,
      app.sitzung,
      t1,
      max: const Duration(minutes: 4),
    );
    final danach = [
      for (final e in await proxyLog())
        if ((e['zeit'] as num) * 1000 > t1.millisecondsSinceEpoch &&
            '${e['pfad']}'.startsWith('/api/v1/hochladen'))
          '${e['methode']} ${e['pfad']}',
    ];
    print('MOB-178 nach dem WLAN: $danach (POST vorher $posts)');
    expect(
      stop.inSeconds,
      lessThanOrEqualTo(25),
      reason: 'hört spätestens nach etwa 15 s auf',
    );
    expect(d.wartet, isNotNull);
    expect(
      spaet.where((x) => x.contains('/hochladen')),
      isEmpty,
      reason: 'über Mobilfunk geht nichts weiter',
    );
    expect(
      danach.first,
      startsWith('HEAD /api/v1/hochladen/'),
      reason: 'setzt an derselben Stelle fort',
    );
    expect(
      danach.where((x) => x == 'POST /api/v1/hochladen'),
      isEmpty,
      reason: 'kein neuer Upload',
    );
  });

  pruefung('MOB-140 Android: kein „Als Video speichern“ in der Diashow', (
    tester,
  ) async {
    final k = await kontoMitFotos('A140', 3);
    await starteApp(tester, server: hauptApp, konto: k.konto);
    await warteAufKacheln(tester, 3);
    await oeffneKachel(tester, 0);
    await tippe(tester, tooltip(de.betrachterMehr));
    await tippe(tester, find.text(de.diashowAbHier), ms: 1500);
    final d = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'Diashow',
    );
    await warte(tester, d);
    await tester.tapAt(tester.getCenter(d));
    await ruhe(tester, 500);
    expect(tooltip(de.diashowBeenden), findsOneWidget);
    expect(tooltip(de.diashowAlsVideo), findsNothing);
  });

  pruefung('MOB-185 MOB-186 Android: echte Rückfrage beim Löschen', (
    tester,
  ) async {
    final konto = await kontoAnlegen(hauptDirekt, 'A185');
    final pfade = <String, String>{};
    for (final n in ['r2a_10.jpg', 'r2a_11.jpg', 'r2a_12.jpg', 'r2a_1.jpg']) {
      pfade[n] = await fotoInGalerie(n, ordner: 'Pictures');
    }
    final app = await starteApp(tester, server: hauptApp, konto: konto);
    await sicherungsseite(tester);
    await schalter(tester, de.sicherungAn, true);
    await warteLaufEnde(
      tester,
      app.sitzung,
      DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await app.sitzung.gleicheAb();
    Future<String> idVon(String n) async => (await mitRechner(
      hauptDirekt,
      konto,
      (r) async => [
        for (final z
            in await r.db
                .customSelect(
                  "SELECT id FROM assets WHERE original_file_name LIKE '%$n'",
                )
                .get())
          z.read<String>('id'),
      ],
    )).single;
    final a = await idVon('r2a_10.jpg'),
        b = await idVon('r2a_11.jpg'),
        c = await idVon('r2a_12.jpg'),
        x = await idVon('r2a_1.jpg');
    // MOB-186: X am Rechner in den Papierkorb.
    await mitRechner(hauptDirekt, konto, (r) => r.tue(InDenPapierkorb([x])));
    await app.sitzung.gleicheAb();
    await rolleBis(tester, find.text(de.sicherungPapierkorbTelefon));
    await tippe(tester, find.text(de.sicherungPapierkorbTelefon), ms: 2000);
    await warte(tester, find.text(de.sicherungFreigebenTitel(1)));
    expect(find.text(de.sicherungPapierkorbTelefonText), findsOneWidget);
    await tippe(
      tester,
      find.text(de.sicherungFreigebenLoeschen).last,
      ms: 2500,
    );
    await systemTipp(['Allow', 'Zulassen', 'Delete', 'Löschen']);
    await meldung(
      tester,
      de.vomTelefonGeloescht(1),
      max: const Duration(seconds: 30),
    );
    await meldungenWeg(tester);
    await tippe(tester, find.text(de.sicherungPapierkorbTelefon), ms: 2500);
    await warte(
      tester,
      find.textContaining(de.sicherungPapierkorbTelefonNichts),
    );
    final weg = await adb(['shell', 'ls', pfade['r2a_1.jpg']!]);
    print('MOB-186 X in der Galerie: $weg');
    await meldungenWeg(tester);
    // MOB-185: B bearbeitet, C im Papierkorb am Server, D neu und ungesichert.
    await mitRechner(hauptDirekt, konto, (r) => r.tue(InDenPapierkorb([c])));
    await app.sitzung.gleicheAb();
    await proxyAus();
    await adb(['push', '$_fix/r2a_2.jpg', pfade['r2a_11.jpg']!]);
    await scanne(pfade['r2a_11.jpg']!);
    final pfadD = await fotoInGalerie('r2a_3.jpg', ordner: 'Pictures');
    await ruhe(tester, 5000);
    await rolleBis(tester, find.text(de.sicherungFreigeben));
    await tester.tap(find.text(de.sicherungFreigeben));
    var sucht = false;
    for (
      var i = 0;
      i < 40 && find.byType(AlertDialog).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      sucht =
          sucht || find.text(de.sicherungFreigebenSucht).evaluate().isNotEmpty;
    }
    await warte(
      tester,
      find.byType(AlertDialog),
      max: const Duration(seconds: 30),
    );
    final titel = sichtbareTexte(
      tester,
    ).firstWhere((t) => t.contains('vom Telefon löschen?'));
    print('MOB-185 Sucht: $sucht; $titel');
    expect(find.text(de.sicherungFreigebenText), findsOneWidget);
    await tippe(
      tester,
      find.text(de.sicherungFreigebenLoeschen).last,
      ms: 2500,
    );
    await systemTipp(['Allow', 'Zulassen', 'Delete', 'Löschen']);
    await ruhe(tester, 3000);
    final bleiben = {
      for (final e in pfade.entries)
        e.key: (await adb(['shell', 'ls', e.value])).contains('No such')
            ? 'weg'
            : 'da',
      'D': (await adb(['shell', 'ls', pfadD])).contains('No such')
          ? 'weg'
          : 'da',
    };
    print(
      'MOB-185 Galerie danach: $bleiben (A=r2a_10, B=r2a_11 bearbeitet, C=r2a_12 Papierkorb)',
    );
    expect(bleiben['r2a_10.jpg'], 'weg');
    expect(bleiben['r2a_11.jpg'], 'da');
    expect(bleiben['r2a_12.jpg'], 'da');
    expect(bleiben['D'], 'da');
    await meldungenWeg(tester);
    await rolleBis(tester, find.text(de.sicherungFreigeben));
    await tester.tap(find.text(de.sicherungFreigeben));
    await ruhe(tester, 4000);
    final nichts = sichtbareTexte(
      tester,
    ).where((t) => t.contains('Nichts freizugeben')).toList();
    print('MOB-185 erneut: $nichts');
    await proxyAn();
    final amA = await amServer(hauptDirekt, konto, a);
    expect(amA?.isTrashed, isFalse, reason: 'am Server bleibt A');
    expect(b, isNotEmpty);
    expect(sucht, isTrue);
    expect(
      nichts,
      isNotEmpty,
      reason:
          '„Nichts freizugeben“ (die eigenen Testfotos früherer Prüfungen ausgenommen)',
    );
  });
}

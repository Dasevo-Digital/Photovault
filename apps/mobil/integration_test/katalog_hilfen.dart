// ignore_for_file: avoid_print
// Gemeinsame Hilfen für die Katalogprüfung der Handy-App (MOB).
//
// Jede Prüfung startet denselben Widgetbaum wie `main.dart`
// (`PhotoVaultMobil`), aber mit einer eigenen Kopie der Bibliothek in einem
// frischen Temp-Ordner. Gesprochen wird nur mit Wegwerf-Servern des
// Prüfkatalogs auf dem Mac (Simulator: 127.0.0.1, Emulator: seine
// Adresse für den Rechner, über PV_HOST).
// Vor den Servern sitzt ein Vorschalt-Proxy (pruefkatalog/tools/
// mob_steuer.py), über den eine Prüfung den Server „ausschalten“ oder
// einzelne Antworten nachstellen kann.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:abgleich_ui/l10n/sync_texte.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
// Rational ist nicht öffentlich ausgeführt, die GPS-Grade brauchen es.
// ignore: implementation_imports
import 'package:image/src/util/rational.dart' show Rational;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/main.dart' show PhotoVaultMobil;
import 'package:photo_vault_mobil/sicherung/hintergrund.dart';
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:teilen_ui/l10n/teilen_texte.dart';
import 'package:workmanager/workmanager.dart';
import 'package:zierbild/zierschrift.dart';

/// Die deutschen Texte der App.
final AppTexte de = lookupAppTexte(const Locale('de'));

/// Die deutschen Texte des Teilen-Pakets (Links, geteilte Alben …).
final TeilenTexte tt = lookupTeilenTexte(const Locale('de'));

/// Die deutschen Texte der Abgleichsübersicht (Konflikte).
final SyncTexte st = lookupSyncTexte(const Locale('de'));

/// Wo der Mac zu erreichen ist: im Simulator 127.0.0.1, im Emulator die
/// Adresse, unter der er den Rechner erreicht (per PV_HOST).
const hostAdresse = String.fromEnvironment(
  'PV_HOST',
  defaultValue: '127.0.0.1',
);

/// Ordner mit Testdateien (Videos) – nur im Simulator lesbar.
const fixturesOrdner = String.fromEnvironment('PV_FIXTURES');

/// Passwort aller Wegwerf-Konten (mindestens 12 Zeichen).
const pw = 'Pruef-Passwort-123';

/// Die Ports der Prüfumgebung (siehe mob_steuer.py).
abstract final class Port {
  static const haupt = 18850;
  static const hauptProxy = 18851;
  static const steuer = 18852;
  static const leer1 = 18853;
  static const leer1Proxy = 18854;
  static const leer2 = 18855;
  static const konten = 18856;
  static const verw = 18857;
  static const fremd = 18858;
  static const frei = 18859;
  static const kontenProxy = 18860;
  static const verwProxy = 18861;
}

Uri adresse(int port) => Uri.parse('http://$hostAdresse:$port/');

/// Welcher Vorschalt-Proxy vor „haupt“ (iOS und Android getrennt, damit
/// parallele Läufe sich nicht stören).
const proxyName = String.fromEnvironment(
  'PV_PROXY_NAME',
  defaultValue: 'haupt',
);
const proxyPort = int.fromEnvironment(
  'PV_PROXY_PORT',
  defaultValue: Port.hauptProxy,
);

/// Server „haupt“, wie die App ihn sieht (über den Proxy).
final hauptApp = adresse(proxyPort);

/// Derselbe Server direkt – für Vorbereitung und Gegenproben.
final hauptDirekt = adresse(Port.haupt);

var _eingerichtet = false;

/// Was `main()` vor `runApp` erledigt – einmal je Prozess.
Future<void> einrichten() async {
  if (_eingerichtet) return;
  _eingerichtet = true;
  protokollZiel = debugPrint;
  await Workmanager().initialize(sicherungImHintergrund);
  zierschriftenLizenzenAnmelden();
}

// --------------------------------------------------------------------------
// Warten und Bedienen

/// Pumpt, bis [f] etwas findet (höchstens [max]).
Future<void> warte(
  WidgetTester tester,
  Finder f, {
  Duration max = const Duration(seconds: 25),
  String? grund,
}) async {
  final ende = DateTime.now().add(max);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (f.evaluate().isNotEmpty) return;
  }
  final sichtbar = sichtbareTexte(tester).take(40).join(' | ');
  throw TestFailure(
    'Nicht erschienen nach ${max.inSeconds} s: $f'
    '${grund == null ? '' : ' ($grund)'}\nSichtbar: $sichtbar',
  );
}

/// Pumpt, bis [f] nichts mehr findet.
Future<void> warteWeg(
  WidgetTester tester,
  Finder f, {
  Duration max = const Duration(seconds: 25),
}) async {
  final ende = DateTime.now().add(max);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (f.evaluate().isEmpty) return;
  }
  throw TestFailure('Nicht verschwunden nach ${max.inSeconds} s: $f');
}

/// Pumpt, bis [bedingung] gilt.
Future<void> warteBis(
  WidgetTester tester,
  FutureOr<bool> Function() bedingung, {
  Duration max = const Duration(seconds: 25),
  String grund = 'Bedingung',
}) async {
  final ende = DateTime.now().add(max);
  while (DateTime.now().isBefore(ende)) {
    if (await bedingung()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  final sichtbar = sichtbareTexte(tester).take(40).join(' | ');
  throw TestFailure(
    '$grund trat nicht ein (${max.inSeconds} s)\nSichtbar: $sichtbar',
  );
}

/// Lässt einige Bilder laufen (ohne pumpAndSettle, das bei Kreiseln nie
/// endet).
Future<void> ruhe(WidgetTester tester, [int ms = 600]) async {
  final ende = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Tippt [f] an (vorher sichtbar gerollt) und lässt die Oberfläche
/// nachziehen.
Future<void> tippe(WidgetTester tester, Finder f, {int ms = 500}) async {
  await warte(tester, f);
  // Im Simulator erscheint die echte Tastatur; solange sie ein- oder
  // ausfährt, verschiebt sich die Seite und ein Tipp ginge daneben.
  if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
    FocusManager.instance.primaryFocus?.unfocus();
    await ruhe(tester, 700);
  }
  final ziel = f.first;
  try {
    await tester.ensureVisible(ziel);
  } catch (_) {
    // Nicht in einer rollbaren Fläche.
  }
  await tester.pump();
  await tester.tap(ziel, warnIfMissed: false);
  await ruhe(tester, ms);
}

/// Rollt in der ersten (oder [in_]) rollbaren Fläche, bis [f] sichtbar ist.
Future<void> rolleZu(
  WidgetTester tester,
  Finder f, {
  Finder? in_,
  double schritt = 250,
}) async {
  if (f.evaluate().isNotEmpty) {
    await tester.ensureVisible(f.first);
    await ruhe(tester, 200);
    return;
  }
  await tester.scrollUntilVisible(
    f,
    schritt,
    // Die sichtbare rollbare Fläche (IndexedStack baut auch die anderen
    // Bereiche).
    scrollable: in_ ?? _sichtbareRollflaeche(tester),
    maxScrolls: 80,
  );
  await ruhe(tester, 200);
}

Finder text(String s) => find.text(s);
Finder textEnthaelt(String s) => find.textContaining(s);
Finder tooltip(String s) => find.byTooltip(s);

/// Das Textfeld mit der Beschriftung [label].
Finder feld(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> schreibe(WidgetTester tester, Finder f, String inhalt) async {
  await warte(tester, f);
  try {
    await tester.ensureVisible(f.first);
  } catch (_) {}
  await tester.enterText(f.first, inhalt);
  await tester.pump();
}

/// Die rote Fehlerzeile der Anmeldeseite o. Ä.: ein Text in der
/// Fehlerfarbe.
bool istRot(WidgetTester tester, String s) {
  final w = tester.widget<Text>(find.text(s).first);
  final ctx = tester.element(find.text(s).first);
  return w.style?.color == Theme.of(ctx).colorScheme.error;
}

/// Ob ein Fehler in Flutter (Ausnahme beim Bauen u. Ä.) aufgetreten ist.
/// Holt alle gesammelten Ausnahmen ab.
List<Object> ausnahmen(WidgetTester tester) {
  final l = <Object>[];
  while (true) {
    final e = tester.takeException();
    if (e == null) break;
    l.add(e);
  }
  return l;
}

// --------------------------------------------------------------------------
// Steuerung (Proxy, adb)

Future<Map<String, Object?>> steuer(
  String pfad, [
  Map<String, Object?>? inhalt,
]) async {
  final r = await http.post(
    Uri.parse('http://$hostAdresse:${Port.steuer}/$pfad'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(inhalt ?? const {}),
  );
  return (jsonDecode(r.body) as Map).cast<String, Object?>();
}

Future<void> proxyAus([String name = proxyName]) => steuer('proxy/$name/aus');
Future<void> proxyAn([String name = proxyName]) => steuer('proxy/$name/an');
Future<void> proxyZuruecksetzen([String name = proxyName]) =>
    steuer('proxy/$name/zuruecksetzen');
Future<void> proxyRegel(Map<String, Object?> regel, [String name = 'haupt']) =>
    steuer('proxy/$name/regel', regel);
Future<void> proxyLogLeeren([String name = proxyName]) =>
    steuer('proxy/$name/log/leeren');
Future<List<Map<String, Object?>>> proxyLog([String name = proxyName]) async =>
    [
      for (final e in (await steuer('proxy/$name/log'))['log']! as List)
        (e as Map).cast<String, Object?>(),
    ];

// --------------------------------------------------------------------------
// Konten und Server

var _zaehler = 0;

/// Ein eindeutiger Kontoname (2 bis 40 Zeichen, erlaubte Zeichen).
String eindeutig(String praefix) {
  _zaehler++;
  final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return '${praefix}_${t.substring(t.length - 5)}$_zaehler';
}

Future<Anmeldeschritt> anmelden(
  Uri server,
  String name, {
  String passwort = pw,
  String geraet = 'Probe',
}) async {
  final a = Anmeldung(server);
  try {
    return await a.anmelden(name, passwort, geraet: geraet);
  } finally {
    a.schliesse();
  }
}

/// Meldet [name] an und gibt das Token zurück (ohne TOTP).
Future<String> holeToken(
  Uri server,
  String name, {
  String passwort = pw,
  String geraet = 'Probe',
}) async {
  final s = await anmelden(server, name, passwort: passwort, geraet: geraet);
  if (s is! AnmeldungFertig) {
    throw StateError('Anmeldung von $name: $s');
  }
  return s.token;
}

Future<Serververbindung> api(
  Uri server,
  String name, {
  String passwort = pw,
  String geraet = 'Probe',
}) async => Serververbindung(
  server,
  await holeToken(server, name, passwort: passwort, geraet: geraet),
);

final _verwalter = <String, Serververbindung>{};

/// Die Verbindung des Verwalters von [server] (direkt, ohne Proxy).
Future<Serververbindung> verwalter(Uri server) async =>
    _verwalter[server.toString()] ??= await api(
      server,
      'Verwalter',
      geraet: 'Pruefung',
    );

/// Legt über den Verwalter ein neues Konto an und gibt seinen Namen
/// zurück.
Future<String> kontoAnlegen(
  Uri server,
  String praefix, {
  bool alsVerwalter = false,
}) async {
  final name = eindeutig(praefix);
  await Kontenverwaltung(
    await verwalter(server),
  ).legeAn(name, pw, verwalter: alsVerwalter);
  return name;
}

/// TOTP (RFC 6238, SHA-1, 6 Ziffern, 30 s) aus einem Base32-Geheimnis.
String totp(String geheimnis, {DateTime? zeit, int versatz = 0}) {
  const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final bits = StringBuffer();
  for (final c in geheimnis.toUpperCase().replaceAll('=', '').split('')) {
    final v = abc.indexOf(c);
    if (v < 0) continue;
    bits.write(v.toRadixString(2).padLeft(5, '0'));
  }
  final s = bits.toString();
  final schluessel = Uint8List(s.length ~/ 8);
  for (var i = 0; i < schluessel.length; i++) {
    schluessel[i] = int.parse(s.substring(i * 8, i * 8 + 8), radix: 2);
  }
  final t =
      (zeit ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 ~/ 30 + versatz;
  final zaehler = ByteData(8)..setUint64(0, t);
  final h = Hmac(sha1, schluessel).convert(zaehler.buffer.asUint8List()).bytes;
  final o = h.last & 0x0f;
  final code =
      ((h[o] & 0x7f) << 24 |
          (h[o + 1] & 0xff) << 16 |
          (h[o + 2] & 0xff) << 8 |
          (h[o + 3] & 0xff)) %
      1000000;
  return code.toString().padLeft(6, '0');
}

/// Richtet TOTP für [name] ein (erste Anmeldung auf einem Server mit
/// Pflicht) und gibt Geheimnis, Codes und Token zurück.
Future<({String geheimnis, List<String> codes, String token})> totpEinrichten(
  Uri server,
  String name,
) async {
  final a = Anmeldung(server);
  try {
    final s = await a.anmelden(name, pw, geraet: 'Einrichtung');
    if (s is! AnmeldungTotpEinrichten) {
      throw StateError('Erwartet: TOTP einrichten, war $s');
    }
    final f = await a.bestaetige(s.vorgang, totp(s.geheimnis));
    if (f is! AnmeldungFertig) throw StateError('TOTP-Bestätigung: $f');
    return (
      geheimnis: s.geheimnis,
      codes: f.wiederherstellungscodes ?? const <String>[],
      token: f.token,
    );
  } finally {
    a.schliesse();
  }
}

// --------------------------------------------------------------------------
// Testbilder

final _zufall = math.Random(42);

/// Ein JPEG mit wählbaren Angaben.
Uint8List jpeg({
  int breite = 640,
  int hoehe = 480,
  DateTime? datum,
  String? kamera,
  String? modell,
  double? breitengrad,
  double? laengengrad,
  int? farbe,
}) {
  final bild = img.Image(width: breite, height: hoehe);
  final f = farbe ?? _zufall.nextInt(0xffffff);
  img.fill(
    bild,
    color: img.ColorRgb8((f >> 16) & 0xff, (f >> 8) & 0xff, f & 0xff),
  );
  for (var i = 0; i < 5; i++) {
    final x = _zufall.nextInt(breite);
    final y = _zufall.nextInt(hoehe);
    img.fillRect(
      bild,
      x1: x,
      y1: y,
      x2: math.min(breite - 1, x + 20 + _zufall.nextInt(breite ~/ 3)),
      y2: math.min(hoehe - 1, y + 20 + _zufall.nextInt(hoehe ~/ 3)),
      color: img.ColorRgb8(
        _zufall.nextInt(256),
        _zufall.nextInt(256),
        _zufall.nextInt(256),
      ),
    );
  }
  if (datum != null) {
    String z(int v, int s) => v.toString().padLeft(s, '0');
    final t =
        '${z(datum.year, 4)}:${z(datum.month, 2)}:${z(datum.day, 2)} '
        '${z(datum.hour, 2)}:${z(datum.minute, 2)}:${z(datum.second, 2)}';
    bild.exif.exifIfd['DateTimeOriginal'] = t;
    bild.exif.imageIfd['DateTime'] = t;
  }
  if (kamera != null) bild.exif.imageIfd['Make'] = kamera;
  if (modell != null) bild.exif.imageIfd['Model'] = modell;
  if (breitengrad != null && laengengrad != null) {
    img.IfdValueRational grad(double wert) {
      final w = wert.abs();
      final g = w.floor();
      final m = ((w - g) * 60).floor();
      final s = ((w - g - m / 60) * 3600 * 1000).round();
      return img.IfdValueRational.list([
        Rational(g, 1),
        Rational(m, 1),
        Rational(s, 1000),
      ]);
    }

    final gps = bild.exif.gpsIfd;
    gps[0x0001] = img.IfdValueAscii(breitengrad < 0 ? 'S' : 'N');
    gps[0x0002] = grad(breitengrad);
    gps[0x0003] = img.IfdValueAscii(laengengrad < 0 ? 'W' : 'E');
    gps[0x0004] = grad(laengengrad);
  }
  return img.encodeJpg(bild, quality: 88);
}

/// Lädt [daten] als [name] über [v] hoch (wie ein anderes Gerät) und gibt
/// die Kennung der Aufnahme zurück.
Future<String> hochladen(
  Serververbindung v,
  Uint8List daten,
  String name,
) async {
  final ordner = await Directory.systemTemp.createTemp('pv_hoch_');
  try {
    final f = File(p.join(ordner.path, name));
    await f.writeAsBytes(daten);
    final kopf = await TusHochladen(
      v,
    ).lade(f, 'api/v1/hochladen', {'filename': name});
    final id = kopf['pv-aufnahme'];
    if (id == null) throw StateError('Hochladen ohne Aufnahme: $kopf');
    return id;
  } finally {
    await ordner.delete(recursive: true);
  }
}

/// Lädt eine Datei aus dem Fixtures-Ordner hoch (nur im Simulator).
Future<String> hochladenDatei(Serververbindung v, String fixture) async {
  if (Platform.isAndroid) {
    // Im Emulator liegen die Dateien des Macs nicht; die Steuerung reicht
    // sie durch.
    final r = await http.get(
      Uri.parse('http://$hostAdresse:${Port.steuer}/fixture/$fixture'),
    );
    if (r.statusCode != 200) {
      throw StateError('Fixture $fixture: ${r.statusCode}');
    }
    return hochladen(v, r.bodyBytes, fixture);
  }
  final f = File(p.join(fixturesOrdner, fixture));
  return hochladen(v, await f.readAsBytes(), fixture);
}

/// Mehrere Fotos auf einmal: Namen `<praefix>_<i>.jpg`, Datum absteigend
/// ab [ab] (je ein Tag früher).
Future<List<String>> fotos(
  Serververbindung v,
  int anzahl, {
  String praefix = 'foto',
  DateTime? ab,
  Duration abstand = const Duration(minutes: 1),
}) async {
  final start = ab ?? DateTime(2024, 6, 20, 12);
  return [
    for (var i = 0; i < anzahl; i++)
      await hochladen(
        v,
        jpeg(datum: start.subtract(abstand * i), breite: 320, hoehe: 240),
        '${praefix}_$i.jpg',
      ),
  ];
}

/// Eine Aufnahme, wie der Server sie über die API zeigt.
Future<Map<String, Object?>> aufnahme(Serververbindung v, String id) =>
    v.hole('api/v1/aufnahmen/$id');

/// Ein zweites Gerät desselben Kontos, das Befehle schickt – wie der
/// Rechner oder die Weboberfläche.
class Rechner {
  Rechner._(this.db, this.abgleich, this._ordner);

  final AppDatabase db;
  final Abgleich abgleich;
  final Directory _ordner;

  static Future<Rechner> verbinde(Serververbindung v) async {
    final ordner = await Directory.systemTemp.createTemp('pv_rechner_');
    await Abgleich.holeAbzug(v, File(p.join(ordner.path, 'library.sqlite')));
    final db = await AppDatabase.open(ordner);
    final a = Abgleich(db, v);
    await a.richteEin();
    return Rechner._(db, a, ordner);
  }

  /// Holt den neuesten Stand des Servers.
  Future<void> empfange() => abgleich.empfange();

  /// Führt [befehl] aus und schickt ihn zum Server.
  Future<T> tue<T>(Befehl<T> befehl) async {
    await abgleich.empfange();
    final e = await db.fuehreAus(befehl);
    await abgleich.sende();
    return e;
  }

  Future<void> schliesse() async {
    await abgleich.beende();
    await db.close();
    try {
      await _ordner.delete(recursive: true);
    } catch (_) {}
  }
}

// --------------------------------------------------------------------------
// Die App

class App {
  App(this.sitzung, this.ordner);
  final Sitzung sitzung;
  final Directory ordner;

  Directory get bibliothek => Directory(p.join(ordner.path, 'bibliothek'));
}

App? _laufend;

/// Räumt die zuletzt gestartete App ab.
Future<void> appBeenden(WidgetTester tester) async {
  final a = _laufend;
  _laufend = null;
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  if (a == null) return;
  try {
    await a.sitzung.beende().timeout(const Duration(seconds: 20));
  } catch (e) {
    print('beende: $e');
  }
  try {
    await a.ordner.delete(recursive: true);
  } catch (_) {}
}

/// Startet die App wie `main()` mit einer frischen Kopie.
///
/// Mit [konto] meldet sie sich (ohne Oberfläche) bei [server] an und holt
/// die Bibliothek; ohne steht die Anmeldeseite da.
Future<App> starteApp(
  WidgetTester tester, {
  Uri? server,
  String? konto,
  String passwort = pw,
  String geraet = 'Telefon',
  String? token,
}) async {
  await einrichten();
  await appBeenden(tester);
  final ordner = await Directory.systemTemp.createTemp('pv_mob_');
  final bib = Directory(p.join(ordner.path, 'bibliothek'));
  final s = Sitzung(ordner: () async => bib);
  if (konto != null) {
    final t =
        token ??
        await holeToken(server!, konto, passwort: passwort, geraet: geraet);
    await s.verbinde(server: server!, konto: konto, geraet: geraet, token: t);
  } else {
    await s.starte();
  }
  final app = _laufend = App(s, ordner);
  await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
  await ruhe(tester, 400);
  return app;
}

/// Startet die App auf einer schon vorhandenen Kopie neu (wie nach dem
/// Beenden der App): neue Sitzung, gleicher Ordner.
Future<App> neuStarten(WidgetTester tester, App alt) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await alt.sitzung.beende();
  final bib = alt.bibliothek;
  final s = Sitzung(ordner: () async => bib);
  await s.starte();
  final app = _laufend = App(s, alt.ordner);
  await tester.pumpWidget(PhotoVaultMobil(sitzung: s));
  await ruhe(tester, 400);
  return app;
}

/// Wartet, bis die App die Zeitleiste zeigt und [anzahl] Kacheln da sind.
Future<void> warteAufKacheln(
  WidgetTester tester,
  int anzahl, {
  Duration max = const Duration(seconds: 40),
}) async {
  await warteBis(
    tester,
    () => kacheln().evaluate().length >= anzahl,
    max: max,
    grund: '$anzahl Kacheln',
  );
}

/// Kacheln des Rasters (Miniaturen).
Finder kacheln() => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == 'Miniatur',
  skipOffstage: true,
);

/// Wechselt unten zum Bereich [name] („Fotos“, „Suche“, „Alben“,
/// „Bibliothek“).
Future<void> bereich(WidgetTester tester, String name) async {
  await tippe(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(name)),
  );
}

/// Öffnet die Kontoseite über den Kreis oben rechts.
Future<void> kontoOeffnen(WidgetTester tester) async {
  await tippe(tester, tooltip(de.kontoTitel));
  await warte(tester, find.widgetWithText(AppBar, de.kontoTitel));
}

/// Zurück (Pfeil oben links bzw. Navigator.pop).
Future<void> zurueck(WidgetTester tester) async {
  // Nie die Startseite selbst wegnehmen: maybePop lässt die letzte Seite.
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  await nav.maybePop();
  await ruhe(tester, 800);
}

/// Zieht die erste rollbare Fläche nach unten (Abgleich auslösen).
Future<void> nachUntenZiehen(WidgetTester tester) async {
  await tester.fling(find.byType(Scrollable).first, const Offset(0, 400), 1200);
  await ruhe(tester, 1500);
}

// --------------------------------------------------------------------------
// System-Teilen abfangen

/// Was die App an das System-Teilen gegeben hat: je Aufruf die Dateien
/// (Name und Inhalt, beim Aufruf gelesen).
final geteilt = <List<({String pfad, Uint8List daten})>>[];
final geteilteTexte = <String>[];

/// Fängt das System-Teilen ab (share_plus), damit kein Blatt die Prüfung
/// blockiert. Die Dateien werden beim Aufruf gelesen.
void teilenAbfangen() {
  geteilt.clear();
  geteilteTexte.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          final a = (call.arguments as Map).cast<String, Object?>();
          final dateien = <({String pfad, Uint8List daten})>[];
          for (final pfad in (a['paths'] as List? ?? const [])) {
            final f = File(pfad as String);
            dateien.add((
              pfad: pfad,
              daten: await f.exists() ? await f.readAsBytes() : Uint8List(0),
            ));
          }
          geteilt.add(dateien);
          if (a['text'] case final String t) geteilteTexte.add(t);
          if (a['uri'] case final String u) geteilteTexte.add(u);
          return 'dev.fluttercommunity.plus/share/success';
        },
      );
}

// --------------------------------------------------------------------------
// Weitere Hilfen

/// Wie der Server eine Aufnahme sieht – über ein frisches „zweites Gerät“
/// (holt den Abzug neu).
Future<AssetData?> amServer(Uri server, String konto, String id) async {
  final r = await Rechner.verbinde(await api(server, konto));
  try {
    return await r.db.assetById(id);
  } finally {
    await r.schliesse();
  }
}

/// Führt [arbeit] mit einem frischen zweiten Gerät von [konto] aus.
Future<T> mitRechner<T>(
  Uri server,
  String konto,
  Future<T> Function(Rechner r) arbeit,
) async {
  final r = await Rechner.verbinde(await api(server, konto));
  try {
    return await arbeit(r);
  } finally {
    await r.schliesse();
  }
}

/// Öffnet in der Bibliothek die Kachel [name].
Future<void> bibOeffnen(WidgetTester tester, String name) async {
  await bereich(tester, de.navBibliothek);
  final f = find.text(name);
  await rolleZu(tester, f);
  // „Personen“ steht zweimal (Abschnitt und Kachel): die Kachel nehmen.
  await tippe(tester, f.last);
}

/// Langes Drücken.
Future<void> lang(WidgetTester tester, Finder f) async {
  await warte(tester, f);
  try {
    await tester.ensureVisible(f.first);
    await tester.pump();
  } catch (_) {}
  await tester.longPress(f.first, warnIfMissed: false);
  await ruhe(tester, 600);
}

/// Die Zeilen des (obersten sichtbaren) Rasters.
List<String> rasterNamen(WidgetTester tester) {
  final r = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'AufnahmenRaster',
  );
  final w = tester.widgetList(r).last as dynamic;
  return [for (final z in (w.zeilen as List)) z.originalFileName as String];
}

List<String> rasterIds(WidgetTester tester) {
  final r = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'AufnahmenRaster',
  );
  final w = tester.widgetList(r).last as dynamic;
  return [for (final z in (w.zeilen as List)) z.id as String];
}

/// Ein neues Konto auf „haupt“ mit [anzahl] Fotos; gibt Name, Verbindung
/// und Kennungen (neueste zuerst) zurück.
Future<({String konto, Serververbindung v, List<String> ids})> kontoMitFotos(
  String praefix,
  int anzahl, {
  DateTime? ab,
  Duration abstand = const Duration(minutes: 1),
}) async {
  final konto = await kontoAnlegen(hauptDirekt, praefix);
  final v = await api(hauptDirekt, konto);
  final ids = await fotos(
    v,
    anzahl,
    praefix: praefix.toLowerCase(),
    ab: ab,
    abstand: abstand,
  );
  return (konto: konto, v: v, ids: ids);
}

/// Öffnet die Kachel [i] der Zeitleiste im Betrachter.
Future<void> oeffneKachel(WidgetTester tester, int i) async {
  await tippe(tester, kacheln().at(i), ms: 1200);
  await warte(tester, tooltip(de.betrachterAngaben));
}

/// Schliesst den Betrachter bzw. die oberste Seite.
Future<void> schliesse(WidgetTester tester) async {
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  await nav.maybePop();
  await ruhe(tester, 800);
}

/// Wartet auf eine Meldung unten (SnackBar) mit [s].
Future<void> meldung(WidgetTester tester, String s, {Duration? max}) => warte(
  tester,
  find.descendant(of: find.byType(SnackBar), matching: find.text(s)),
  max: max ?? const Duration(seconds: 25),
);

/// Legt auf einem frischen Server das erste Konto „Verwalter“ an, falls es
/// noch keines gibt.
Future<void> ersteinrichtung(Uri server) async {
  final a = Anmeldung(server);
  try {
    if ((await a.zustand())['einrichten'] == true) {
      await a.einrichten('Verwalter', pw, geraet: 'Pruefung');
    }
  } finally {
    a.schliesse();
  }
  _verwalter.remove(server.toString());
}

/// Eigene Testdateien der MOB-Prüfung (HEIC u. a.), auf dem Mac erzeugt.
const fixturesMob = String.fromEnvironment('PV_FIXTURES_MOB');

/// Lädt eine Datei vom Mac hoch (nur im Simulator), unter [name].
Future<String> hochladenPfad(
  Serververbindung v,
  String pfad, {
  String? name,
}) async =>
    hochladen(v, await File(pfad).readAsBytes(), name ?? p.basename(pfad));

/// Das Original einer Aufnahme vom Server.
Future<Uint8List> original(Serververbindung v, String id) async {
  final r = await v.anfrage('GET', 'api/v1/aufnahmen/$id/original');
  if (r.statusCode != 200) {
    throw StateError('Original $id: ${r.statusCode}');
  }
  return r.bodyBytes;
}

String sha(List<int> daten) => sha256.convert(daten).toString();

/// Die Kennung des Kontos [name], wie [v] sie unter „andere Konten“ sieht.
Future<String> kontoId(Serververbindung v, String name) async {
  final k = (await v.hole('api/v1/konten/andere'))['konten']! as List;
  for (final x in k.cast<Map>()) {
    if (x['name'] == name) return '${x['id']}';
  }
  throw StateError('Konto $name nicht unter andere');
}

/// Teilt das Album [albumId] von [v] mit [konto].
Future<void> albumTeilen(
  Serververbindung v,
  String albumId,
  String konto, {
  bool beitragen = false,
}) async {
  final id = await kontoId(v, konto);
  final r = await v.anfrage(
    'PUT',
    'api/v1/alben/${Uri.encodeComponent(albumId)}/teilungen/${Uri.encodeComponent(id)}',
    kopf: {'content-type': 'application/json'},
    inhalt: utf8.encode('{"beitragen":$beitragen}'),
  );
  if (r.statusCode != 200) {
    throw StateError('Teilen: ${r.statusCode} ${r.body}');
  }
}

/// Ein Gesicht von Hand (wie „Gesicht aufziehen“), optional mit Person.
Future<String> gesicht(
  Serververbindung v,
  String aufnahme, {
  List<double> kasten = const [0.3, 0.2, 0.3, 0.4],
  String? personId,
}) async {
  final d = await v.schicke('api/v1/aufnahmen/$aufnahme/gesichter', {
    'kasten': kasten,
    'personId': ?personId,
  });
  return '${(d['gesicht']! as Map)['id']}';
}

/// Legt eine Person an (über ein zweites Gerät) und gibt ihre Kennung
/// zurück.
Future<String> person(Uri server, String konto, String name) async {
  final id = uuid();
  await mitRechner(server, konto, (r) => r.tue(PersonAnlegen(id, name)));
  return id;
}

/// Eine zufällige UUID (Version 4).
String uuid() {
  final z = math.Random();
  String h(int n) =>
      [for (var i = 0; i < n; i++) z.nextInt(16).toRadixString(16)].join();
  return '${h(8)}-${h(4)}-4${h(3)}-8${h(3)}-${h(12)}';
}

/// Alle sichtbaren Texte (für Befunde im Protokoll).
List<String> sichtbareTexte(WidgetTester tester) => [
  for (final t in tester.widgetList<RichText>(find.byType(RichText)))
    if (t.text.toPlainText().trim().isNotEmpty) t.text.toPlainText(),
  for (final t in tester.widgetList<EditableText>(find.byType(EditableText)))
    if (t.controller.text.trim().isNotEmpty) t.controller.text,
];

/// Meldet [name] mit TOTP an (Code aus [geheimnis] oder [ersatz], wenn der
/// aktuelle Code schon verbraucht sein könnte) und gibt das Token zurück.
Future<String> holeTokenTotp(
  Uri server,
  String name,
  String geheimnis,
  String ersatz, {
  String passwort = pw,
  String geraet = 'Zweitgeraet',
}) async {
  final a = Anmeldung(server);
  try {
    final s = await a.anmelden(name, passwort, geraet: geraet);
    if (s is! AnmeldungCode) throw StateError('Erwartet Code: $s');
    final f = await a.bestaetige(s.vorgang, ersatz);
    if (f is! AnmeldungFertig) throw StateError('TOTP: $f');
    return f.token;
  } finally {
    a.schliesse();
  }
}

/// Fehler, die nur sagen, dass der Server gerade nicht antwortet – im Test
/// mit ausgeschaltetem Server erwartet. Die App lässt solche Fehler beim
/// Nachladen von Dateien unbehandelt auflaufen (Dateibeschaffung.hole); im
/// Betrieb landen sie nur im Protokoll, im Test brächen sie die Prüfung ab.
bool harmloserNetzfehler(Object e) =>
    e is KeineVerbindung ||
    e is SocketException ||
    e is HandshakeException ||
    e is http.ClientException ||
    e is TimeoutException ||
    (e is Serverfehler && (e.status >= 500 || e.status == 404));

var ignorierteNetzfehler = 0;

/// Wie [testWidgets], aber Netzfehler beim Nachladen (siehe
/// [harmloserNetzfehler]) werden protokolliert statt die Prüfung
/// abzubrechen. Alle anderen Fehler gelten weiter.
void pruefung(
  String name,
  Future<void> Function(WidgetTester tester) body, {
  bool skip = false,
}) {
  testWidgets(name, (tester) async {
    final vorher = FlutterError.onError;
    FlutterError.onError = (d) {
      if (harmloserNetzfehler(d.exception)) {
        ignorierteNetzfehler++;
        print('[$name] Netzfehler ignoriert: ${d.exception}');
        return;
      }
      vorher?.call(d);
    };
    Object? fehler;
    StackTrace? spur;
    final fertig = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await body(tester);
        } catch (e, s) {
          fehler = e;
          spur = s;
        }
        // Offene Bilder und Anfragen in derselben Zone auslaufen lassen.
        try {
          await appBeenden(tester);
        } catch (e) {
          print('[$name] beim Beenden: $e');
        }
        if (!fertig.isCompleted) fertig.complete();
      },
      (e, s) {
        if (harmloserNetzfehler(e)) {
          ignorierteNetzfehler++;
          print('[$name] Netzfehler ignoriert: $e');
          return;
        }
        fehler ??= e;
        spur ??= s;
        if (!fertig.isCompleted) fertig.complete();
      },
    );
    await fertig.future;
    FlutterError.onError = vorher;
    if (fehler != null) Error.throwWithStackTrace(fehler!, spur!);
  }, skip: skip);
}

/// Nimmt alle Meldungen unten weg (Meldungen mit Aktion bleiben sonst
/// stehen und halten die nächsten zurück).
Future<void> meldungenWeg(WidgetTester tester) async {
  for (final s in tester.stateList<ScaffoldMessengerState>(
    find.byType(ScaffoldMessenger),
  )) {
    s.clearSnackBars();
  }
  await ruhe(tester, 500);
}

/// Wählt im (ersten) Auswahlfeld für Konten den Eintrag [wert] – wie ein
/// Tipp auf den Eintrag im Menü, das bei vielen Konten zu lang wird.
Future<void> waehleKonto(WidgetTester tester, String wert) async {
  final f = find.byWidgetPredicate((w) => w is DropdownButton<String>);
  await warte(tester, f);
  final dd = tester.widget<DropdownButton<String>>(f.first);
  expect(
    dd.items!.map((e) => e.value),
    contains(wert),
    reason: 'Konto steht in der Auswahl',
  );
  dd.onChanged!(wert);
  await ruhe(tester, 600);
}

/// Die Kennung, unter der [v] (der Empfänger) ein mit ihm geteiltes Album
/// sieht – passend zur Albumkennung des Besitzers oder zum Namen.
Future<String> geteiltId(Serververbindung v, String albumOderName) async {
  final d = (await v.hole('api/v1/geteilt'))['alben'] as List? ?? const [];
  for (final x in d.cast<Map>()) {
    if ('${x['id']}' == albumOderName ||
        '${x['album']}' == albumOderName ||
        '${x['name']}' == albumOderName ||
        '${x['id']}'.endsWith(albumOderName)) {
      return '${x['id']}';
    }
  }
  throw StateError('Geteiltes Album $albumOderName nicht gefunden: $d');
}

/// Schickt das Feld [f] ab, wie die Eingabetaste der Tastatur
/// (onSubmitted).
Future<void> absenden(WidgetTester tester, Finder f) async {
  final w = tester.widget<TextField>(f.first);
  w.onSubmitted?.call(w.controller?.text ?? '');
  await ruhe(tester, 600);
}

Finder _sichtbareRollflaeche(WidgetTester tester) {
  final treffbar = find.byType(Scrollable).hitTestable();
  if (treffbar.evaluate().isNotEmpty) return treffbar.first;
  // Sonst die letzte senkrechte (oberste Seite).
  final senkrecht = find.byWidgetPredicate(
    (w) =>
        w is Scrollable &&
        (w.axisDirection == AxisDirection.down ||
            w.axisDirection == AxisDirection.up),
  );
  return senkrecht.last;
}

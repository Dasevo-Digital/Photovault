// ignore_for_file: avoid_print
// Katalog-Prüfungen „Orte, Karte, Reisen“ (ORT-…), Ende-zu-Ende in der
// echten macOS-App mit Wegwerf-Bibliothek.
//
// Läuft nur über die Warteschlange des Prüfkatalogs:
//   tools/e2e_queue.sh ort integration_test/katalog_ort_test.dart
//
// **Das Netz ist in jeder Prüfung für die App gesperrt** (über
// [HttpOverrides]): Kartenkacheln, Luftbilder, Gelände und CARTO gehen so
// nie an fremde Server. Geprüft werden Marker, Zahlen, Listen und
// Navigation, nicht die Kacheln. Nur der GeoNames-Download (ORT-055) und
// das einmalige Füllen des Zwischenspeichers dafür öffnen es kurz.
//
// Orte sind ausschliesslich Koordinaten bekannter Stadtzentren.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_earth_globe/flutter_earth_globe.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gelaende/gelaende_screen.dart';
import 'package:gelaende/l10n/gelaende_texte.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/eigenkarte.dart';
import 'package:kern/services/gelaendeebenen.dart';
import 'package:kern/services/geo_data_catalog.dart';
import 'package:kern/services/kartenstil.dart';
import 'package:kern/services/laenderkatalog.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/aktivitaeten_screen.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/aufnahmen_waehlen_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/screens/gpx_verortung_screen.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/screens/ortsansicht_screen.dart';
import 'package:photo_vault/screens/ortsvorschlaege_screen.dart';
import 'package:photo_vault/screens/reise_detail_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/screens/weltkarte_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/eigene_karte_einstellung.dart';
import 'package:photo_vault/widgets/mini_location_map.dart'
    show Kachelschicht, MiniLocationMap;
import 'package:provider/provider.dart';

import 'katalog_kit.dart';

// ---------------------------------------------------------------------------
// Orte (Stadtzentren, öffentlich bekannt)
// ---------------------------------------------------------------------------

typedef Ort = (double, double);

const Ort hamburg = (53.5511, 9.9937);
const Ort muenchen = (48.1374, 11.5755);
const Ort nuernberg = (49.4521, 11.0767);
const Ort berlin = (52.5200, 13.4050);
const Ort bremen = (53.0793, 8.8017);
const Ort hannover = (52.3759, 9.7320);
const Ort leipzig = (51.3397, 12.3731);
const Ort wien = (48.2082, 16.3738);
const Ort rom = (41.9028, 12.4964);
const Ort paris = (48.8566, 2.3522);
const Ort madrid = (40.4168, -3.7038);
const Ort meer = (40.0, -40.0);

final gt = lookupGelaendeTexte(const Locale('de'));

/// Ein Foto mit Ort und Datum.
File fotoBei(
  String name,
  Ort ort,
  DateTime datum, {
  double dBreite = 0,
  double dLaenge = 0,
}) => testfoto(
  name,
  datum: datum,
  breitengrad: ort.$1 + dBreite,
  laengengrad: ort.$2 + dLaenge,
);

String titelDatum(DateTime d) => '${d.day}.${d.month}.${d.year}';

// ---------------------------------------------------------------------------
// Netz
// ---------------------------------------------------------------------------

/// Sperrt das Netz für alles, was über `dart:io` geht (Dio, package:http,
/// Bildlader). Wer einen Client anlegt, solange [offen] falsch ist, kann
/// nie verbinden; jeder Versuch steht in [versuche].
class Netzsperre extends HttpOverrides {
  bool offen = false;
  final versuche = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (offen) return client;
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      versuche.add(uri);
      return Future<ConnectionTask<Socket>>.error(
        const SocketException('Netz in der Katalogprüfung gesperrt'),
      );
    };
    return client;
  }
}

final netz = Netzsperre();

/// Startet die App (über das Kit) und sperrt vorher das Netz.
Future<void> starte(
  WidgetTester tester, {
  Size groesse = const Size(1400, 900),
  bool geodaten = false,
}) async {
  netz.offen = false;
  netz.versuche.clear();
  HttpOverrides.global = netz;
  addTearDown(() => HttpOverrides.global = null);
  // Der Meldungsdienst ist ein Einzelstück und überlebt die Prüfungen.
  melde.alleSchliessen();
  melde.verlaufLeeren();
  await startApp(tester, groesse: groesse);
  if (geodaten) await geonamesBereitstellen(tester);
}

// ---------------------------------------------------------------------------
// GeoNames
// ---------------------------------------------------------------------------

const _geoDateien = [
  GeoDataCatalog.citiesFileName,
  GeoDataCatalog.admin1FileName,
  GeoDataCatalog.countryFileName,
];

/// Zwischenspeicher im Temp des Prüfplatzes – damit der Datensatz (11 MB
/// gepackt) nicht in jeder Prüfung neu aus dem Netz kommt.
Directory get geoZwischenspeicher =>
    Directory(p.join(Directory.systemTemp.path, 'pv_katalog_ort_geonames'));

bool get geoZwischenspeicherVoll => _geoDateien.every(
  (n) => File(p.join(geoZwischenspeicher.path, n)).existsSync(),
);

void geoInZwischenspeicher() {
  final svc = bibliothek.geoDataDownloadService;
  geoZwischenspeicher.createSync(recursive: true);
  for (final n in _geoDateien) {
    File(
      p.join(svc.geoDataDir, n),
    ).copySync(p.join(geoZwischenspeicher.path, n));
  }
}

/// Vorbedingung „GeoNames-Datensatz geladen“: aus dem Zwischenspeicher
/// (sonst einmal aus dem Netz) in den Datenordner der Prüfung legen und
/// neu einlesen lassen – wie nach einem Download in den Einstellungen.
Future<void> geonamesBereitstellen(WidgetTester tester) async {
  await tester.runAsync(() async {
    final svc = bibliothek.geoDataDownloadService;
    if (!geoZwischenspeicherVoll) {
      netz.offen = true;
      try {
        await svc.download().drain<void>();
      } finally {
        netz.offen = false;
      }
      geoInZwischenspeicher();
    } else {
      Directory(svc.geoDataDir).createSync(recursive: true);
      for (final n in _geoDateien) {
        File(
          p.join(geoZwischenspeicher.path, n),
        ).copySync(p.join(svc.geoDataDir, n));
      }
    }
    await bibliothek.reloadGeoData();
  });
  await settle(tester);
  expect(bibliothek.geoDataAvailable, isTrue);
}

ReverseGeocoder get geo => bibliothek.geocoder!;

// ---------------------------------------------------------------------------
// Datenbank
// ---------------------------------------------------------------------------

Future<List<AssetData>> alle(WidgetTester tester) async => (await tester
    .runAsync(() => bibliothek.db.select(bibliothek.db.assets).get()))!;

Future<AssetData> aufnahme(WidgetTester tester, String name) async =>
    (await alle(tester)).firstWhere((a) => a.originalFileName == name);

Future<void> sql(
  WidgetTester tester,
  String anweisung, [
  List<Object?> werte = const [],
]) async {
  await tester.runAsync(() => bibliothek.db.customStatement(anweisung, werte));
}

Future<T> db<T>(WidgetTester tester, Future<T> Function() f) async =>
    (await tester.runAsync(f)) as T;

Future<void> inPapierkorb(WidgetTester tester, String id) =>
    db(tester, () => bibliothek.db.fuehreAus(InDenPapierkorb([id])));

Future<void> sperren(WidgetTester tester, AssetData a) async {
  await tester.runAsync(() async {
    if (!bibliothek.vaultUnlockedThisSession) {
      await bibliothek.setupVaultPin('2468');
    }
    await bibliothek.lockAsset(a);
  });
  await settle(tester);
}

/// Neustart der App mit derselben Wegwerf-Bibliothek. Die Umlenkung des
/// Datenordners aus [startApp] bleibt bestehen; geprüft wird, dass die
/// Bibliothek danach am selben Ort im Temp-Ordner liegt.
Future<void> neuStart(WidgetTester tester) async {
  final wurzel = bibliothek.paths.root.path;
  // Wie beim Beenden: Hintergrundarbeit anhalten, dann schliessen.
  final alt = bibliothek;
  if (alt.analyseLaeuft) alt.brichHintergrundanalyseAb();
  for (final lauf in alt.offeneAufgaben.toList()) {
    alt.brichAufgabeAb(lauf.schluessel);
  }
  final ende = DateTime.now().add(const Duration(seconds: 30));
  while (alt.etwasLaeuft && DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await alt.vorDemBeenden();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const PhotoVaultApp());
  await waitFor(
    tester,
    find.byType(HomeShell),
    timeout: const Duration(seconds: 90),
  );
  bibliothek = Provider.of<LibraryState>(
    tester.element(find.byType(HomeShell)),
    listen: false,
  );
  final neu = bibliothek.paths.root.path;
  if (neu != wurzel || !neu.startsWith(anker.path)) {
    throw StateError('Nach dem Neustart eine andere Bibliothek: $neu');
  }
  await settle(tester);
}

// ---------------------------------------------------------------------------
// Bedienung allgemein
// ---------------------------------------------------------------------------

/// Wechselt in einen Hauptbereich – über einen anderen, damit offene
/// Unterseiten des Bereichs geschlossen und der Bildschirm neu aufgebaut
/// wird (ein Wunsch auf den schon gezeigten Bereich ändert nichts).
Future<void> bereich(WidgetTester tester, int b) async {
  await openSection(
    tester,
    b == Hauptbereich.zeitleiste ? Hauptbereich.alben : Hauptbereich.zeitleiste,
  );
  await openSection(tester, b);
  await settle(tester);
}

Finder typ(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

Finder kachel(String id) =>
    find.byWidgetPredicate((w) => w is AssetThumbnailTile && w.asset.id == id);

Finder textIn(Finder bereich, String text) =>
    find.descendant(of: bereich, matching: find.text(text));

Finder textEnthaeltIn(Finder bereich, String text) =>
    find.descendant(of: bereich, matching: find.textContaining(text));

Finder knopf(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool knopfAktiv(WidgetTester tester, Finder f) =>
    tester.widget<ButtonStyleButton>(f.first).onPressed != null;

Finder get dialogFeld => find.byType(AlertDialog);

/// Wie `tap` aus dem Kit, nur dass vorher die Meldungen oben rechts
/// geschlossen werden – sie liegen sonst über Knöpfen und Feldern, und der
/// Klick landet auf der Meldung. Geprüft werden Meldungen über [meldung],
/// das auch den Verlauf ansieht.
Future<void> klick(WidgetTester tester, Finder f) async {
  await meldungenWeg(tester);
  await tap(tester, f);
}

/// Schliesst die Meldungen und wartet, bis auch ihre Ausblendung vorbei
/// ist – solange sie noch stehen, fangen sie Klicks ab.
Future<void> meldungenWeg(WidgetTester tester) async {
  melde.alleSchliessen();
  // Ungelesene lassen oben rechts eine Glocke stehen, die Klicks abfängt
  // und beim Treffer den Verlauf aufklappt.
  melde.verlaufGelesen();
  await tester.pump();
  await waitGone(
    tester,
    typ('_Meldungskarte'),
    timeout: const Duration(seconds: 5),
  );
}

Future<void> eingeben(WidgetTester tester, Finder f, String text) async {
  await meldungenWeg(tester);
  await enter(tester, f, text);
  // Gelegentlich kommt die Eingabe nicht im Feld an (die Tastaturverbindung
  // hängt noch am vorigen Feld). Dann wie beim Tippen: Text setzen und
  // onChanged melden.
  final feld = tester.widget(f.first);
  if (feld is TextField &&
      feld.controller != null &&
      feld.controller!.text != text) {
    print('Eingabe nachgereicht: „$text“');
    feld.controller!.text = text;
    feld.onChanged?.call(text);
    await settle(tester);
  }
}

/// Wartet, bis die Meldung [text] erschienen ist – auf dem Bildschirm oder
/// im Verlauf der Meldungen. Erfolgsmeldungen stehen nur vier Sekunden;
/// `tap` wartet nach dem Klick bis zu fünf, solange sich etwas bewegt.
Future<void> meldung(WidgetTester tester, String text) async {
  final seit = DateTime.now().subtract(const Duration(seconds: 15));
  final ende = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(ende)) {
    if (melde.verlauf.any(
      (m) => m.text.contains(text) && m.zeit.isAfter(seit),
    )) {
      return;
    }
    if (find.textContaining(text).evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    'Meldung nicht erschienen: $text\nVerlauf: '
    '${melde.verlauf.take(5).map((m) => m.text).toList()}',
  );
}

/// Schliesst alle Meldungen (oben rechts), bevor sie Knöpfe verdecken.
Future<void> stille(WidgetTester tester) async {
  await meldungenWeg(tester);
}

/// Zurück über den Pfeil der obersten Seite.
Future<void> zurueck(WidgetTester tester) async {
  final pfeil = find.byType(BackButton);
  if (pfeil.evaluate().isNotEmpty) {
    await tester.tap(pfeil.last);
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  }
  await settle(tester);
}

String textVon(WidgetTester tester, Finder f) {
  final w = tester.widget<Text>(f.first);
  return w.data ?? w.textSpan?.toPlainText() ?? '';
}

/// Mausbewegung, damit ein Tooltip erscheint.
Future<void> zeigeMit(WidgetTester tester, Finder f) async {
  final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await maus.addPointer(location: Offset.zero);
  addTearDown(maus.removePointer);
  await maus.moveTo(tester.getCenter(f.first));
  await tester.pump(const Duration(milliseconds: 1200));
  await settle(tester);
}

/// Wählt im Material-Datumsdialog über die Texteingabe ein Datum.
Future<void> datumImDialog(WidgetTester tester, DateTime d) async {
  await waitFor(tester, find.byType(DatePickerDialog));
  final ml = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  final umschalter = find.byTooltip(ml.inputDateModeButtonLabel);
  if (umschalter.evaluate().isNotEmpty) await klick(tester, umschalter);
  final feld = find.descendant(
    of: find.byType(DatePickerDialog),
    matching: find.byType(TextField),
  );
  await waitFor(tester, feld);
  await tester.enterText(feld.first, ml.formatCompactDate(d));
  await settle(tester);
  await klick(tester, find.text(ml.okButtonLabel));
  await waitGone(tester, find.byType(DatePickerDialog));
}

// ---------------------------------------------------------------------------
// Vollansicht und Info
// ---------------------------------------------------------------------------

Finder get vollansicht => find.byType(AssetViewerScreen);
Finder get infoBereich => find.byType(AssetInfoSheet);
Finder get infoKarte =>
    find.descendant(of: infoBereich, matching: find.byType(MiniLocationMap));
Finder get infoKarteFlutter =>
    find.descendant(of: infoKarte, matching: find.byType(FlutterMap));

AssetViewerScreen viewer(WidgetTester tester) =>
    tester.widget<AssetViewerScreen>(vollansicht);

String viewerTitel(WidgetTester tester) => textVon(
  tester,
  find.descendant(
    of: find.descendant(of: vollansicht, matching: find.byType(AppBar)),
    matching: find.byType(Text),
  ),
);

Future<void> oeffneInZeitleiste(WidgetTester tester, String id) async {
  await bereich(tester, Hauptbereich.zeitleiste);
  await settle(tester);
  await klick(tester, kachel(id));
  await waitFor(tester, vollansicht);
}

Future<void> info(WidgetTester tester) async {
  if (infoBereich.evaluate().isEmpty) {
    await klick(tester, find.byTooltip(de.viewerInfo));
  }
  await waitFor(tester, infoBereich);
}

Future<void> viewerZu(WidgetTester tester) async {
  for (var i = 0; i < 2 && vollansicht.evaluate().isNotEmpty; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
  }
  // Steht der Fokus noch in einem Textfeld der Info, kommt Escape nicht
  // bei der Vollansicht an – dann über den Pfeil oben links.
  if (vollansicht.evaluate().isNotEmpty) {
    final pfeil = find.descendant(
      of: vollansicht,
      matching: find.byWidgetPredicate(
        (w) => w is BackButton || w is CloseButton,
      ),
    );
    if (pfeil.evaluate().isNotEmpty) {
      await tap(tester, pfeil.first);
    } else {
      await tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .maybePop();
      await settle(tester);
    }
  }
  await waitGone(tester, vollansicht);
}

Future<void> pfeil(WidgetTester tester, LogicalKeyboardKey taste) async {
  await tester.sendKeyEvent(taste);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

// ---------------------------------------------------------------------------
// Karten
// ---------------------------------------------------------------------------

Finder get fotomarker => typ('_MapThumbMarker');
Finder get globusPins => typ('_GlobePin');
Finder get rauten => typ('_GlobusEreignis');

/// Wartet auf Pins oder Rauten des Globus.
///
/// Im Test erscheinen sie nach dem Öffnen des Globus nicht von selbst,
/// sondern erst nach der ersten Bedienung (siehe Prüfung „ORT-018 Pins
/// erscheinen …“). Damit die übrigen Prüfungen trotzdem laufen, folgt
/// dann ein Zoomschritt hin und zurück – wie ein Mensch, der den Globus
/// kurz anfasst.
Future<bool> globusLabelsAbwarten(WidgetTester tester, Finder f) async {
  final ende = DateTime.now().add(const Duration(seconds: 6));
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return true;
  }
  print('Globus: ohne Bedienung keine Pins');
  await klick(tester, find.byTooltip(de.karteHineinzoomen));
  await klick(tester, find.byTooltip(de.karteHerauszoomen));
  await waitFor(tester, f, timeout: const Duration(seconds: 20));
  return false;
}

/// Klickt mit der Maus auf einen Pin des Globus und meldet, ob der Klick
/// den Pin überhaupt trifft (Trefferprüfung an seiner Mitte).
/// Ob der letzte [tippeAufPin] den Pin wirklich getroffen hat.
var pinGetroffen = true;

/// Klickt mit der Maus auf einen Pin des Globus. Trifft der Klick ihn
/// nicht (im Test lagen die Pins ausserhalb der Trefferfläche des Globus),
/// wird sein Klickziel direkt ausgelöst – damit wenigstens der Sprung in
/// die flache Karte geprüft wird – und [pinGetroffen] steht auf falsch.
Future<void> tippeAufPin(WidgetTester tester, Finder pin) async {
  final mitte = tester.getCenter(pin.first);
  final ziel = tester.renderObject(pin.first);
  final treffer = tester.hitTestOnBinding(mitte);
  pinGetroffen = treffer.path.any((e) => identical(e.target, ziel));
  final globus = find.byType(FlutterEarthGlobe);
  print(
    'Pin bei $mitte (Globusmitte ${tester.getCenter(globus)}, '
    'Globus ${tester.getRect(globus)}), getroffen: $pinGetroffen',
  );
  if (pinGetroffen) {
    await tester.tapAt(mitte, kind: PointerDeviceKind.mouse);
  } else {
    tester
        .widget<GestureDetector>(
          find
              .ancestor(of: pin.first, matching: find.byType(GestureDetector))
              .first,
        )
        .onTap!();
  }
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}

MapController steuerung(WidgetTester tester, [Finder? karte]) => tester
    .widget<FlutterMap>((karte ?? find.byType(FlutterMap)).first)
    .mapController!;

int _zahlIn(Element e) {
  final texte = find
      .descendant(
        of: find.byElementPredicate((x) => identical(x, e)),
        matching: find.byType(Text),
      )
      .evaluate();
  if (texte.isEmpty) return 1;
  return int.parse((texte.first.widget as Text).data!.trim());
}

/// Die gebauten Marker einer Art, mit Zahl und Ort.
List<({int anzahl, ll.LatLng ort, Offset mitte})> marker(
  WidgetTester tester, [
  Finder? art,
]) {
  final karte = find.byType(FlutterMap);
  final hatKarte = karte.evaluate().isNotEmpty;
  final oben = hatKarte ? tester.getTopLeft(karte.first) : Offset.zero;
  final kamera = hatKarte ? steuerung(tester).camera : null;
  return [
    for (final e in (art ?? fotomarker).evaluate())
      () {
        final mitte = tester.getCenter(
          find.byElementPredicate((x) => identical(x, e)),
        );
        return (
          anzahl: _zahlIn(e),
          ort: kamera == null
              ? const ll.LatLng(0, 0)
              : kamera.screenOffsetToLatLng(mitte - oben),
          mitte: mitte,
        );
      }(),
  ];
}

int summe(WidgetTester tester, [Finder? art]) =>
    marker(tester, art).fold(0, (s, m) => s + m.anzahl);

/// Marker in der Nähe von [ort] (Grad).
List<int> markerBei(WidgetTester tester, Ort ort, {double radius = 0.2}) => [
  for (final m in marker(tester))
    if ((m.ort.latitude - ort.$1).abs() < radius &&
        (m.ort.longitude - ort.$2).abs() < radius)
      m.anzahl,
];

Future<void> schwenke(
  WidgetTester tester,
  Ort ort, {
  double? zoom,
  Finder? karte,
}) async {
  final c = steuerung(tester, karte);
  c.move(ll.LatLng(ort.$1, ort.$2), zoom ?? c.camera.zoom);
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}

/// Ein echter Klick auf die Karte an der Stelle [ort].
Future<void> tippeAufKarte(
  WidgetTester tester,
  Ort ort, {
  Finder? karte,
}) async {
  final f = (karte ?? find.byType(FlutterMap)).first;
  await tester.ensureVisible(f);
  await settle(tester);
  final c = steuerung(tester, f);
  final versatz = c.camera.latLngToScreenOffset(ll.LatLng(ort.$1, ort.$2));
  await tester.tapAt(tester.getTopLeft(f) + versatz);
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}

/// Schwenkt die Karte auf [ort] (Zoom 12) und klickt genau dort hin.
Future<void> setzeOrtPerKlick(
  WidgetTester tester,
  Ort ort, {
  required Finder karte,
}) async {
  await tester.ensureVisible(karte.first);
  await settle(tester);
  await schwenke(tester, ort, zoom: 12, karte: karte);
  await tippeAufKarte(tester, ort, karte: karte);
}

double zoomVon(WidgetTester tester) => steuerung(tester).camera.zoom;

Future<void> naeher(WidgetTester tester) =>
    klick(tester, find.byTooltip(de.karteHineinzoomen));
Future<void> weiterWeg(WidgetTester tester) =>
    klick(tester, find.byTooltip(de.karteHerauszoomen));

bool zoomknopfAktiv(WidgetTester tester, String hinweis) =>
    tester
        .widget<InkResponse>(
          find
              .descendant(
                of: find.byTooltip(hinweis),
                matching: find.byType(InkResponse),
              )
              .first,
        )
        .onTap !=
    null;

Future<void> karteOeffnen(WidgetTester tester) async {
  await bereich(tester, Hauptbereich.karte);
  await waitFor(tester, find.byType(MapScreen));
  await settle(tester);
}

Future<void> kartenansicht(WidgetTester tester, String eintrag) async {
  await stille(tester);
  await klick(tester, find.byTooltip(de.karteAnsicht));
  await klick(tester, find.text(eintrag).last);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Finder kartenmenueEintrag(String name) => find.ancestor(
  of: find.text(name),
  matching: find.byType(PopupMenuItem<Kartenansicht>),
);

Finder ansichtSymbol(IconData symbol) => find.descendant(
  of: find.byTooltip(de.karteAnsicht),
  matching: find.byIcon(symbol),
);

Kartenstil? stilDerKarte(WidgetTester tester) =>
    tester.widget<Kachelschicht>(find.byType(Kachelschicht).first).stil;

TileLayer kachelLage(WidgetTester tester) =>
    tester.widget<TileLayer>(find.byType(TileLayer).first);

// ---------------------------------------------------------------------------
// Einstellungen, Werkzeuge, Aufgaben
// ---------------------------------------------------------------------------

Finder get einstellungsliste => find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> sichtbarIn(WidgetTester tester, Finder f, Finder liste) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 250, scrollable: liste, maxScrolls: 80);
  }
  await tester.ensureVisible(f.first);
  await settle(tester);
}

Future<void> einstellungsgruppe(WidgetTester tester, String titel) async {
  await bereich(tester, Hauptbereich.einstellungen);
  await waitFor(tester, find.byType(SettingsScreen));
  final kopf = find.descendant(
    of: find.byType(ExpansionTile),
    matching: find.text(titel),
  );
  await sichtbarIn(tester, kopf, einstellungsliste);
  await klick(tester, kopf);
  await settle(tester);
}

Future<void> zeigeEinstellung(WidgetTester tester, Finder f) =>
    sichtbarIn(tester, f, einstellungsliste);

Finder get aufgabenliste => find
    .descendant(
      of: find.byType(BackgroundTasksScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> aufgabenOeffnen(WidgetTester tester) async {
  await bereich(tester, Hauptbereich.werkzeuge);
  await waitFor(tester, find.byType(ToolsScreen));
  await klick(
    tester,
    find
        .descendant(
          of: find.byType(ToolsScreen),
          matching: find.text(de.aufgTitel),
        )
        .first,
  );
  await waitFor(tester, find.byType(BackgroundTasksScreen));
}

Finder aufgabenkarte(String titel) =>
    find.ancestor(of: find.text(titel), matching: typ('_Aufgabenrahmen'));

Finder aufgabenText(String titel, String text) =>
    find.descendant(of: aufgabenkarte(titel), matching: find.text(text));

Future<void> aufgabeStarten(
  WidgetTester tester,
  String titel,
  String modus,
) async {
  await sichtbarIn(tester, find.text(titel), aufgabenliste);
  final schliessen = aufgabenText(titel, de.allgSchliessen);
  if (schliessen.evaluate().isNotEmpty) await klick(tester, schliessen);
  await klick(tester, aufgabenText(titel, modus));
}

Future<void> aufgabeFertig(WidgetTester tester, String titel) => waitFor(
  tester,
  aufgabenText(titel, de.allgSchliessen),
  timeout: const Duration(seconds: 120),
);

bool aufgabenknopfAktiv(WidgetTester tester, String titel, String modus) =>
    tester
        .widget<InkWell>(
          find
              .ancestor(
                of: aufgabenText(titel, modus),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap !=
    null;

// ---------------------------------------------------------------------------
// Länderliste
// ---------------------------------------------------------------------------

Future<void> laenderSuchen(WidgetTester tester, String text) async {
  await eingeben(tester, field(de.laenderSuchen), text);
  await settle(tester);
}

Finder landzeile(String name) => find.ancestor(
  of: find.descendant(
    of: find.byType(LaenderlisteScreen),
    matching: find.text(name),
  ),
  matching: find.byType(ListTile),
);

String unterzeile(WidgetTester tester, Finder zeile) {
  final unter = tester.widget<ListTile>(zeile.first).subtitle;
  return unter is Text ? (unter.data ?? '') : '';
}

String landname(String iso) => geo.laenderkatalog.nachIso(iso)!.anzeige('de');

// ---------------------------------------------------------------------------
// Reisen
// ---------------------------------------------------------------------------

Finder reisekachel(String name) =>
    find.byWidgetPredicate((w) => w is Reisekachel && w.reise.name == name);

Finder aktivitaetskachel(String name) => find.byWidgetPredicate(
  (w) => w is Aktivitaetskachel && w.aktivitaet.name == name,
);

Future<void> kachelbefehl(
  WidgetTester tester,
  Finder kachel,
  String text,
) async {
  await stille(tester);
  await klick(
    tester,
    find.descendant(
      of: kachel,
      matching: find.byWidgetPredicate((w) => w is PopupMenuButton),
    ),
  );
  await klick(tester, find.text(text).last);
}

Future<String> reiseAnlegen(
  WidgetTester tester,
  String name,
  DateTime von,
  DateTime bis,
  List<String> ids,
) async {
  final id = 'reise-$name';
  await db(
    tester,
    () => bibliothek.db.fuehreAus(
      ReiseAnlegen(
        ReisenCompanion.insert(
          id: id,
          name: name,
          von: von,
          bis: bis,
          angelegtAm: DateTime.now(),
        ),
        ids,
      ),
    ),
  );
  return id;
}

Future<String> aktivitaetAnlegen(
  WidgetTester tester,
  String name,
  DateTime von,
  DateTime bis,
  List<String> ids, {
  String? reiseId,
}) async {
  final id = 'aktivitaet-$name';
  await db(
    tester,
    () => bibliothek.db.fuehreAus(
      AktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: id,
          name: name,
          art: 'wanderung',
          von: von,
          bis: bis,
          reiseId: Value(reiseId),
          angelegtAm: DateTime.now(),
        ),
        ids,
      ),
    ),
  );
  return id;
}

Future<void> reisenOeffnen(WidgetTester tester) async {
  await bereich(tester, Hauptbereich.reisen);
  await waitFor(tester, find.byType(ReisenScreen));
  await waitGone(
    tester,
    find.text(de.reisenSuchtNoch),
    timeout: const Duration(seconds: 60),
  );
  await settle(tester);
}

Future<void> aktivitaetenOeffnen(WidgetTester tester) async {
  await reisenOeffnen(tester);
  await klick(tester, find.byTooltip(de.aktivitaetenOeffnen));
  await waitFor(tester, find.byType(AktivitaetenScreen));
  await waitGone(
    tester,
    find.text(de.aktivitaetenSuchtNoch),
    timeout: const Duration(seconds: 60),
  );
  await settle(tester);
}

// ---------------------------------------------------------------------------
// GPX
// ---------------------------------------------------------------------------

/// Der nachgestellte Dateidialog, der zusätzlich festhält, welche Endungen
/// verlangt wurden.
class MerkenderDialog extends KatalogDateidialog {
  FileType? typ;
  List<String>? endungen;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    typ = type;
    endungen = allowedExtensions;
    return super.pickFile(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      onFileLoading: onFileLoading,
      compressionQuality: compressionQuality,
      androidOptions: androidOptions,
      darwinOptions: darwinOptions,
      windowsOptions: windowsOptions,
      linuxOptions: linuxOptions,
      webOptions: webOptions,
    );
  }
}

Future<void> gpxOeffnen(WidgetTester tester) async {
  await bereich(tester, Hauptbereich.werkzeuge);
  await waitFor(tester, find.byType(ToolsScreen));
  final eintrag = find.text(de.werkzGpxTitel);
  await sichtbarIn(
    tester,
    eintrag,
    find
        .descendant(
          of: find.byType(ToolsScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await klick(tester, eintrag);
  await waitFor(tester, find.byType(GpxVerortungScreen));
}

Future<void> gpxWaehlen(WidgetTester tester, File datei) async {
  dialog.dateien = [datei];
  await klick(tester, find.text(de.gpxDateiWaehlen));
  await tester.pump(const Duration(milliseconds: 500));
  await settle(tester);
}

/// Die 2024-07-10 08–11 Uhr UTC aufgezeichnete Spur – zur Ortszeit. Ihre
/// Punkte liegen eine Stunde auseinander; über Lücken von mehr als 30
/// Minuten rechnet die Verortung nicht (gpx.dart:278), verortbar ist also
/// nur, was genau auf einem Punkt oder bis 5 Minuten vor dem ersten bzw.
/// nach dem letzten liegt.
DateTime spurzeit(int stunde, int minute) =>
    DateTime.utc(2024, 7, 10, stunde, minute).toLocal();

// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Leere Bibliothek
  // =========================================================================

  testWidgets(
    'ORT-001 ORT-047 ORT-059 ORT-028 Leere Bibliothek: Karte, Vorladen, '
    'Auflösen ohne Datensatz, Netzhinweis',
    (tester) async {
      await starte(tester);

      // ORT-001
      await karteOeffnen(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(de.karteTitel),
        ),
        findsWidgets,
      );
      expect(find.text(de.karteKeineOrteLang), findsOneWidget);
      expect(find.byTooltip(de.karteHineinzoomen), findsNothing);
      expect(find.byTooltip(de.karteHerauszoomen), findsNothing);
      expect(find.byTooltip(de.karteAusschnittListe), findsNothing);

      // ORT-047
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      // ORT-028: der Netzhinweis steht oben, mit Weltkugel.
      final hinweis = find.text(de.einstKartenNetzHinweis);
      await zeigeEinstellung(tester, hinweis);
      expect(hinweis, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: hinweis, matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.public_outlined),
        ),
        findsOneWidget,
      );
      expect(de.einstKartenNetzHinweis, contains('OpenStreetMap, OpenTopoMap'));
      expect(de.einstKartenNetzHinweis, contains('Esri'));
      expect(de.einstKartenNetzHinweis, contains('AWS'));
      expect(de.einstKartenNetzHinweis, contains('Ortsverzeichnis'));
      print(
        'ORT-028 Hinweis nennt Waymarked: '
        '${de.einstKartenNetzHinweis.contains('Waymarked')}, Overpass: '
        '${de.einstKartenNetzHinweis.contains('Overpass')}, CARTO: '
        '${de.einstKartenNetzHinweis.contains('CARTO')}',
      );

      final vorladen = find.text(de.einstVorladenTitel);
      await zeigeEinstellung(tester, vorladen);
      await klick(tester, vorladen);
      await meldung(tester, de.einstVorladenKeineOrte);
      expect(dialogFeld, findsNothing);

      // ORT-059
      await aufgabenOeffnen(tester);
      await sichtbarIn(
        tester,
        find.text(de.werkzOrteAufloesenTitel),
        aufgabenliste,
      );
      expect(
        aufgabenText(
          de.werkzOrteAufloesenTitel,
          de.aufgModellNoetig(de.aufgGeoDatensatz, de.aufgWoStandortdaten),
        ),
        findsOneWidget,
      );
      expect(
        aufgabenknopfAktiv(tester, de.werkzOrteAufloesenTitel, de.aufgFehlende),
        isFalse,
      );
      await finish(tester);
    },
  );

  // =========================================================================
  // Flache Karte
  // =========================================================================

  testWidgets(
    'ORT-002 ORT-003 ORT-004 ORT-009 ORT-005 Karte: Marker, Gruppen, Zoom, '
    'Vollansicht, Neuladen',
    (tester) async {
      await starte(tester);
      final fotos = [
        fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
        fotoBei('a2.jpg', hamburg, DateTime(2024, 3, 2, 10), dBreite: 0.002),
        fotoBei('a3.jpg', hamburg, DateTime(2024, 3, 3, 10), dBreite: 0.004),
        fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
        fotoBei('b2.jpg', muenchen, DateTime(2024, 4, 11, 10), dLaenge: 0.002),
        fotoBei('c1.jpg', berlin, DateTime(2024, 5, 20, 10)),
      ];
      await importiereDirekt(tester, fotos);
      final verortet = (await alle(
        tester,
      )).where((a) => a.latitude != null).toList();
      expect(verortet, hasLength(6));

      // ORT-002
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      final kamera = steuerung(tester).camera;
      final mitteB =
          verortet.map((a) => a.latitude!).reduce((a, b) => a + b) / 6;
      final mitteL =
          verortet.map((a) => a.longitude!).reduce((a, b) => a + b) / 6;
      expect(kamera.zoom, closeTo(6, 0.01));
      expect(kamera.center.latitude, closeTo(mitteB, 0.01));
      expect(kamera.center.longitude, closeTo(mitteL, 0.01));
      final m = marker(tester);
      expect(m, hasLength(3), reason: 'je Ort ein Marker');
      expect(m.map((x) => x.anzahl).toList()..sort(), [1, 2, 3]);
      expect(summe(tester), 6);
      // Ohne verortete Ereignisse fehlt der Schalter (ORT-015).
      expect(find.byTooltip(de.karteEreignisseAusblenden), findsNothing);

      // ORT-004: Der Zahlenmarker von Ort A öffnet genau dessen Fotos.
      final a = m.firstWhere((x) => x.anzahl == 3);
      await tester.tapAt(a.mitte);
      await settle(tester);
      await waitFor(tester, vollansicht);
      final gruppe = viewer(tester).assets.map((x) => x.originalFileName);
      expect(gruppe.toSet(), {'a1.jpg', 'a2.jpg', 'a3.jpg'});
      final datenA = {
        titelDatum(DateTime(2024, 3, 1)),
        titelDatum(DateTime(2024, 3, 2)),
        titelDatum(DateTime(2024, 3, 3)),
      };
      final gesehen = <String>{viewerTitel(tester)};
      for (var i = 0; i < 4; i++) {
        await pfeil(tester, LogicalKeyboardKey.arrowRight);
        gesehen.add(viewerTitel(tester));
      }
      for (var i = 0; i < 4; i++) {
        await pfeil(tester, LogicalKeyboardKey.arrowLeft);
        gesehen.add(viewerTitel(tester));
      }
      expect(gesehen, datenA, reason: 'nur Fotos von Ort A');
      await viewerZu(tester);

      // ORT-003 / ORT-009: auf Ort A schwenken, mit den Knöpfen zoomen.
      await schwenke(tester, (hamburg.$1 + 0.002, hamburg.$2), zoom: 6);
      expect(markerBei(tester, hamburg), [3]);
      var z = zoomVon(tester);
      var geteilt = false;
      for (var i = 0; i < 14 && !geteilt; i++) {
        await naeher(tester);
        expect(zoomVon(tester), closeTo(z + 1, 0.01), reason: 'ein Schritt');
        z = zoomVon(tester);
        final bei = markerBei(tester, hamburg);
        expect(bei.fold(0, (s, x) => s + x), 3, reason: 'kein Foto fehlt');
        geteilt = bei.length > 1;
      }
      expect(geteilt, isTrue, reason: 'Gruppe teilt sich beim Hineinzoomen');
      final tiefsterZoom = zoomVon(tester);
      var zusammen = false;
      for (var i = 0; i < 14 && !zusammen; i++) {
        await weiterWeg(tester);
        expect(zoomVon(tester), closeTo(z - 1, 0.01));
        z = zoomVon(tester);
        final bei = markerBei(tester, hamburg);
        expect(bei.fold(0, (s, x) => s + x), 3);
        zusammen = bei.length == 1;
      }
      expect(zusammen, isTrue, reason: 'Gruppe fasst sich wieder zusammen');
      print('ORT-003 geteilt ab Zoom $tiefsterZoom');

      // ORT-009: Wischen und Kneifen auf dem Trackpad.
      await schwenke(tester, hamburg, zoom: 10);
      final c = steuerung(tester);
      final mitte0 = c.camera.center;
      final pos = tester.getCenter(find.byType(FlutterMap));
      final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await g.panZoomStart(pos);
      await g.panZoomUpdate(pos, pan: const Offset(0, -100));
      await g.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(c.camera.zoom, closeTo(11, 0.05), reason: 'hoch wischt heran');
      expect(c.camera.center.latitude, closeTo(mitte0.latitude, 1e-4));
      expect(c.camera.center.longitude, closeTo(mitte0.longitude, 1e-4));
      await g.panZoomStart(pos);
      await g.panZoomUpdate(pos, pan: const Offset(0, 100));
      await g.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(c.camera.zoom, closeTo(10, 0.05), reason: 'runter wischt weg');
      await g.panZoomStart(pos);
      for (final s in [1.2, 1.5, 2.0]) {
        await g.panZoomUpdate(pos, scale: s);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.panZoomEnd();
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(c.camera.zoom, greaterThan(10.5), reason: 'Kneifen zoomt');

      // ORT-005: Einzelmarker → Info → Ort entfernen → Karte lädt neu.
      await schwenke(tester, berlin, zoom: 8);
      final einzel = marker(tester)
          .where((x) => x.anzahl == 1)
          .where((x) => (x.ort.latitude - berlin.$1).abs() < 0.2);
      expect(einzel, hasLength(1));
      await tester.tapAt(einzel.first.mitte);
      await settle(tester);
      await waitFor(tester, vollansicht);
      expect(viewer(tester).assets.single.originalFileName, 'c1.jpg');
      await info(tester);
      await klick(tester, find.byTooltip(de.infoOrtEntfernen));
      await eventually(
        tester,
        () async =>
            (await bibliothek.db.assetById(
              viewer(tester).assets.single.id,
            ))?.latitude ==
            null,
      );
      await viewerZu(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(markerBei(tester, berlin, radius: 1), isEmpty);
      await schwenke(tester, (50.8, 11.5), zoom: 5);
      expect(summe(tester), 5);
      await finish(tester);
    },
  );

  testWidgets('ORT-006 ORT-007 Kartenansicht wählen und über Neustart merken', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);

    // ORT-006
    await stille(tester);
    await klick(tester, find.byTooltip(de.karteAnsicht));
    expect(find.byType(PopupMenuItem<Kartenansicht>), findsNWidgets(4));
    for (final n in [
      de.karteHell,
      de.karteDunkel,
      de.karteTopografie,
      de.karteGlobus,
    ]) {
      expect(kartenmenueEintrag(n), findsOneWidget);
    }
    expect(
      find.descendant(
        of: kartenmenueEintrag(de.karteDunkel),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(ansichtSymbol(Icons.dark_mode_outlined), findsOneWidget);
    expect(stilDerKarte(tester), Kartenstil.dunkel);

    for (final (name, symbol, stil) in [
      (de.karteHell, Icons.light_mode_outlined, Kartenstil.hell),
      (de.karteTopografie, Icons.terrain_outlined, Kartenstil.topo),
      (de.karteDunkel, Icons.dark_mode_outlined, Kartenstil.dunkel),
    ]) {
      await kartenansicht(tester, name);
      expect(ansichtSymbol(symbol), findsOneWidget, reason: name);
      expect(stilDerKarte(tester), stil, reason: name);
      await klick(tester, find.byTooltip(de.karteAnsicht));
      expect(
        find.descendant(
          of: kartenmenueEintrag(name),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
        reason: 'Haken bei $name',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
    }

    // ORT-007
    await kartenansicht(tester, de.karteTopografie);
    await bereich(tester, Hauptbereich.zeitleiste);
    await neuStart(tester);
    bibliothek.zeigeBereich(Hauptbereich.karte);
    // Der erste gebaute Kartenstil muss schon Topografie sein.
    final ende = DateTime.now().add(const Duration(seconds: 20));
    Kartenstil? ersterStil;
    while (DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(Kachelschicht).evaluate().isNotEmpty) {
        ersterStil = stilDerKarte(tester);
        break;
      }
    }
    expect(ersterStil, Kartenstil.topo, reason: 'ohne Umweg über Dunkel');
    expect(ansichtSymbol(Icons.terrain_outlined), findsOneWidget);
    await klick(tester, find.byTooltip(de.karteAnsicht));
    expect(
      find.descendant(
        of: kartenmenueEintrag(de.karteTopografie),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await finish(tester);
  });

  // Behoben in #413: Beim Stilwechsel zieht die Karte die Kamera selbst an die
  // Stilgrenze und gruppiert nach dem Zoom der Kamera statt fest nach Stufe 6.
  testWidgets('ORT-008 Zoomgrenze je Stil und Gruppierung nach dem Wechsel', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('l1.jpg', leipzig, DateTime(2024, 3, 1, 10), dLaenge: -0.0002),
      fotoBei('l2.jpg', leipzig, DateTime(2024, 3, 2, 10)),
      fotoBei('l3.jpg', leipzig, DateTime(2024, 3, 3, 10), dLaenge: 0.0002),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteDunkel);
    await schwenke(tester, leipzig, zoom: 15);
    var vorher = zoomVon(tester);
    for (var i = 0; i < 12; i++) {
      await naeher(tester);
      if (zoomVon(tester) == vorher) break;
      vorher = zoomVon(tester);
    }
    final dunkelMax = Kartenstil.dunkel.hoechsteAnzeigeStufe.toDouble();
    expect(zoomVon(tester), closeTo(dunkelMax, 0.01));
    expect(markerBei(tester, leipzig, radius: 0.01), hasLength(3));

    await kartenansicht(tester, de.karteTopografie);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final topoMax = Kartenstil.topo.hoechsteAnzeigeStufe.toDouble();
    final nachWechsel = zoomVon(tester);
    final gruppen = markerBei(tester, leipzig, radius: 0.01);
    print('ORT-008 nach Wechsel: Zoom $nachWechsel, Marker $gruppen');
    // Weiter hineinwischen.
    final pos = tester.getCenter(find.byType(FlutterMap));
    final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
    await g.panZoomStart(pos);
    await g.panZoomUpdate(pos, pan: const Offset(0, -600));
    await g.panZoomEnd();
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    final nachWischen = zoomVon(tester);
    print('ORT-008 nach Wischen: Zoom $nachWischen');
    // Erwartet: die Karte steht nach dem Wechsel nicht über der Grenze von
    // Topografie, die Marker passen zur Zoomstufe (dort drei einzelne),
    // und Wischen bleibt an der Grenze.
    final befunde = [
      if (nachWechsel > topoMax + 0.01)
        'Zoom nach Wechsel $nachWechsel > $topoMax',
      if (gruppen.length != 3)
        'Marker nach Wechsel $gruppen statt drei einzelner',
      if (nachWischen > topoMax + 0.01)
        'Zoom nach Wischen $nachWischen > $topoMax',
    ];
    expect(befunde, isEmpty);
    await finish(tester);
  });

  testWidgets('ORT-011 ORT-012 ORT-013 Liste „Fotos im Ausschnitt“', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('a2.jpg', hamburg, DateTime(2024, 3, 5, 10), dBreite: 0.003),
      fotoBei('a3.jpg', hamburg, DateTime(2024, 3, 3, 10), dLaenge: 0.003),
      fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
      fotoBei('b2.jpg', muenchen, DateTime(2024, 4, 11, 10), dLaenge: 0.002),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    final liste = typ('_Ausschnittliste');
    final knopf = find.byTooltip(de.karteAusschnittListe);
    await klick(tester, knopf);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(liste, findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(of: knopf, matching: find.byType(IconButton)).first,
          )
          .isSelected,
      isTrue,
    );
    expect(textIn(liste, de.karteImAusschnitt(5)), findsOneWidget);

    // Auf Ort A schwenken und stillhalten.
    await schwenke(tester, hamburg, zoom: 12);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(textIn(liste, de.karteImAusschnitt(3)), findsOneWidget);
    final kacheln = find.descendant(
      of: liste,
      matching: find.byType(AssetThumbnailTile),
    );
    expect(kacheln, findsNWidgets(3));
    final zeiten = [
      for (final e in kacheln.evaluate())
        (e.widget as AssetThumbnailTile).asset.fileCreatedAt,
    ];
    expect(
      zeiten,
      [...zeiten]..sort((a, b) => b.compareTo(a)),
      reason: 'jüngstes zuerst',
    );
    expect(tester.getSize(liste).width, closeTo(340, 0.5));

    // ORT-013: ein Foto der Liste öffnen und blättern.
    final ids = [
      for (final e in kacheln.evaluate())
        (e.widget as AssetThumbnailTile).asset.id,
    ];
    await tester.tap(kacheln.at(1));
    await settle(tester);
    await waitFor(tester, vollansicht);
    expect(viewer(tester).assets.map((a) => a.id).toList(), ids);
    expect(viewer(tester).initialIndex, 1);
    final erlaubt = {for (final t in zeiten) titelDatum(t)};
    final gesehen = <String>{viewerTitel(tester)};
    for (var i = 0; i < 3; i++) {
      await pfeil(tester, LogicalKeyboardKey.arrowRight);
      gesehen.add(viewerTitel(tester));
    }
    await pfeil(tester, LogicalKeyboardKey.arrowLeft);
    gesehen.add(viewerTitel(tester));
    expect(gesehen.difference(erlaubt), isEmpty);
    await viewerZu(tester);

    // ORT-012: Ausschnitt ohne Fotos.
    await schwenke(tester, meer, zoom: 7);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(textIn(liste, de.karteImAusschnitt(0)), findsOneWidget);
    expect(textIn(liste, de.karteAusschnittLeer), findsOneWidget);

    // Schmales Fenster: Liste darunter.
    var breite = 2000.0;
    for (final w in [1000.0, 900.0, 820.0]) {
      await tester.binding.setSurfaceSize(Size(w, 900));
      await settle(tester);
      breite = tester.getSize(find.byType(MapScreen)).width;
      if (breite < 900) break;
    }
    if (breite < 900) {
      final kartenOben = tester.getTopLeft(find.byType(FlutterMap)).dy;
      expect(tester.getTopLeft(liste).dy, greaterThan(kartenOben + 100));
      expect(tester.getSize(liste).width, greaterThan(breite * 0.9));
    } else {
      print('ORT-011 Kartenfläche bei 1000 Punkten noch $breite breit');
    }
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await settle(tester);
    await klick(tester, knopf);
    expect(liste, findsNothing);
    await finish(tester);
  });

  testWidgets('ORT-016 Gesperrte und gelöschte Fotos fehlen auf der Karte', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('frei.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('gesperrt.jpg', rom, DateTime(2024, 3, 2, 10)),
      fotoBei('geloescht.jpg', wien, DateTime(2024, 3, 3, 10)),
    ]);
    await sperren(tester, await aufnahme(tester, 'gesperrt.jpg'));
    await inPapierkorb(tester, (await aufnahme(tester, 'geloescht.jpg')).id);

    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    expect(summe(tester), 1);
    await klick(tester, find.byTooltip(de.karteAusschnittListe));
    final liste = typ('_Ausschnittliste');
    for (final ort in [rom, wien]) {
      await schwenke(tester, ort, zoom: 10);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(fotomarker, findsNothing, reason: '$ort');
      expect(textIn(liste, de.karteImAusschnitt(0)), findsOneWidget);
    }
    await schwenke(tester, (48.0, 12.0), zoom: 4);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(textIn(liste, de.karteImAusschnitt(1)), findsOneWidget);

    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, globusPins);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(summe(tester, globusPins), 1);
    final mitOrt = await db(tester, () => bibliothek.db.assetsWithLocation());
    expect(mitOrt.map((a) => a.originalFileName), ['frei.jpg']);
    await finish(tester);
  });

  testWidgets('ORT-015 Lebensereignisse auf Karte und Globus', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    await tester.runAsync(() async {
      await bibliothek.db
          .into(bibliothek.db.people)
          .insert(PeopleCompanion.insert(id: 'person-a', name: 'Person A'));
      await bibliothek.db
          .into(bibliothek.db.lebensereignisse)
          .insert(
            LebensereignisseCompanion.insert(
              id: 'ereignis-1',
              personId: 'person-a',
              art: 'umzug',
              ort: const Value('Bremen'),
              ortBreite: Value(bremen.$1),
              ortLaenge: Value(bremen.$2),
            ),
          );
    });
    await karteOeffnen(tester);
    await waitFor(tester, rauten);
    expect(rauten, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(of: rauten, matching: find.byType(Tooltip)).first,
    );
    expect(tooltip.message, 'Person A · Bremen');
    await zeigeMit(tester, rauten);
    expect(find.text('Person A · Bremen'), findsWidgets);
    // Fotomarker liegen über den Rauten: die Ereignisschicht kommt zuerst.
    final schichten = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .children
        .whereType<MarkerLayer>()
        .toList();
    expect(schichten, hasLength(2));
    expect(
      schichten.first.markers.first.child,
      isA<Tooltip>(),
      reason: 'Ereignisse unten',
    );

    await klick(tester, find.byTooltip(de.karteEreignisseAusblenden));
    expect(rauten, findsNothing);
    expect(find.byTooltip(de.karteEreignisseEinblenden), findsOneWidget);
    await klick(tester, find.byTooltip(de.karteEreignisseEinblenden));
    expect(rauten, findsOneWidget);

    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, rauten);
    await klick(tester, find.byTooltip(de.karteEreignisseAusblenden));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(rauten, findsNothing);
    await klick(tester, find.byTooltip(de.karteEreignisseEinblenden));
    await waitFor(tester, rauten);
    await finish(tester);
  });

  testWidgets('ORT-017 Karte aus dem Rückblick öffnen', (tester) async {
    await starte(tester);
    // Ohne verortete Fotos fehlt der Abschnitt „Orte“.
    await importiereDirekt(tester, [
      testfoto('ohne.jpg', datum: DateTime(2024, 2, 1, 10)),
    ]);
    await bereich(tester, Hauptbereich.rueckblick);
    await waitFor(tester, find.byType(ExploreScreen));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(typ('_OrteAbschnitt'), findsOneWidget);
    expect(
      textIn(typ('_OrteAbschnitt'), de.erkundenOrte),
      findsNothing,
      reason: 'ohne verortete Fotos kein Abschnitt',
    );
    await finish(tester);

    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    await bereich(tester, Hauptbereich.rueckblick);
    await waitFor(tester, find.byType(ExploreScreen));
    final abschnitt = typ('_OrteAbschnitt');
    final rueckblick = find
        .descendant(
          of: find.byType(ExploreScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    final alleAnzeigen = textIn(abschnitt, de.allgAlleAnzeigen);
    await sichtbarIn(tester, alleAnzeigen, rueckblick);
    await klick(tester, alleAnzeigen);
    await waitFor(tester, find.byType(MapScreen));
    expect(fotomarker, findsWidgets);
    await zurueck(tester);
    await waitGone(tester, find.byType(MapScreen));
    final vorschau = find.descendant(
      of: typ('_LocationsPreview'),
      matching: find.byType(InkWell),
    );
    await sichtbarIn(tester, vorschau, rueckblick);
    await klick(tester, vorschau);
    await waitFor(tester, find.byType(MapScreen));
    await finish(tester);
  });

  // =========================================================================
  // Globus
  // =========================================================================

  testWidgets('ORT-018 ORT-019 ORT-020 ORT-022 ORT-023 Globus: Pins, Sprung, '
      'Zoomhinweis ohne Netz, Grenzen, Wechsel', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('a2.jpg', hamburg, DateTime(2024, 3, 2, 10), dBreite: 0.002),
      fotoBei('a3.jpg', hamburg, DateTime(2024, 3, 3, 10), dBreite: 0.004),
      fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
      fotoBei('b2.jpg', muenchen, DateTime(2024, 4, 11, 10), dLaenge: 0.002),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteHell);

    // ORT-018
    await kartenansicht(tester, de.karteGlobus);
    await waitFor(tester, find.byType(FlutterEarthGlobe));
    await globusLabelsAbwarten(tester, globusPins);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    expect(summe(tester, globusPins), 5);
    expect(marker(tester, globusPins).map((x) => x.anzahl).toList()..sort(), [
      2,
      3,
    ]);
    expect(find.text(de.karteTexturNachweis), findsOneWidget);
    expect(find.byTooltip(de.karteHineinzoomen), findsOneWidget);
    expect(find.byTooltip(de.karteAusschnittListe), findsNothing);
    expect(ansichtSymbol(Icons.public), findsOneWidget);

    // ORT-020 (Netz gesperrt) und ORT-022: von der kleinsten Stufe bis 6.
    expect(zoomknopfAktiv(tester, de.karteHerauszoomen), isTrue);
    await weiterWeg(tester);
    final weiterAmMinimum = zoomknopfAktiv(tester, de.karteHerauszoomen);
    for (var stufe = 0; stufe <= 6; stufe++) {
      await naeher(tester);
      expect(
        find.text(de.karteGlobusZoomHinweis),
        stufe >= 3 ? findsOneWidget : findsNothing,
        reason: 'Stufe $stufe',
      );
      if (stufe == 3) {
        await weiterWeg(tester);
        expect(find.text(de.karteGlobusZoomHinweis), findsNothing);
        await naeher(tester);
        expect(find.text(de.karteGlobusZoomHinweis), findsOneWidget);
      }
    }
    final naeherAnStufe6 = zoomknopfAktiv(tester, de.karteHineinzoomen);
    // Über die Grenze hinaus passiert nichts, kein Sprung.
    await naeher(tester);
    expect(find.text(de.karteGlobusZoomHinweis), findsOneWidget);
    expect(find.byType(FlutterEarthGlobe), findsOneWidget);
    print(
      'ORT-022 aktiv an der kleinsten Stufe: $weiterAmMinimum, '
      'an Stufe 6: $naeherAnStufe6',
    );
    expect(find.text(de.karteGlobusLuftbildHinweis), findsNothing);

    // ORT-023: Stufe 4, Dunkel, wieder Globus.
    await weiterWeg(tester);
    await weiterWeg(tester);
    await kartenansicht(tester, de.karteDunkel);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, globusPins);
    expect(find.text(de.karteGlobusZoomHinweis), findsNothing);
    for (var i = 0; i < 2; i++) {
      await naeher(tester);
    }
    expect(find.text(de.karteGlobusZoomHinweis), findsNothing);
    await naeher(tester);
    expect(
      find.text(de.karteGlobusZoomHinweis),
      findsOneWidget,
      reason: 'wieder bei Stufe 0 begonnen',
    );
    await bereich(tester, Hauptbereich.zeitleiste);
    await karteOeffnen(tester);
    await waitFor(tester, find.byType(FlutterEarthGlobe));
    await globusLabelsAbwarten(tester, globusPins);
    expect(find.text(de.karteGlobusZoomHinweis), findsNothing);

    // ORT-019: Pin springt in die zuletzt benutzte flache Karte (Dunkel).
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final pinA = find.ancestor(
      of: find.descendant(of: globusPins, matching: find.text('3')),
      matching: globusPins,
    );
    await tippeAufPin(tester, pinA);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await waitFor(tester, find.byType(FlutterMap));
    expect(ansichtSymbol(Icons.dark_mode_outlined), findsOneWidget);
    final k = steuerung(tester).camera;
    expect(k.zoom, closeTo(16, 0.01));
    expect(k.center.latitude, closeTo(hamburg.$1 + 0.002, 0.003));
    expect(k.center.longitude, closeTo(hamburg.$2, 0.003));
    await waitFor(tester, fotomarker);
    await tester.tap(fotomarker.first);
    await settle(tester);
    await waitFor(tester, vollansicht);
    expect(
      viewer(tester).assets.first.originalFileName,
      startsWith('a'),
      reason: 'Marker öffnet das Foto',
    );
    await viewerZu(tester);
    await finish(tester);
  });

  // Behoben in #413: Der Pin-Sprung bewegt die schon benutzte flache Karte
  // über den Steuerer (Zoom 16, an der Stilgrenze geklemmt), statt sich auf
  // initialCenter/initialZoom zu verlassen.
  testWidgets('ORT-019 Pin springt nach „Hell“ in die helle Karte', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('a2.jpg', hamburg, DateTime(2024, 3, 2, 10), dBreite: 0.002),
      fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteHell);
    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, globusPins);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final pinA = find.ancestor(
      of: find.descendant(of: globusPins, matching: find.text('2')),
      matching: globusPins,
    );
    await tippeAufPin(tester, pinA);
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    await waitFor(tester, find.byType(FlutterMap));
    expect(ansichtSymbol(Icons.light_mode_outlined), findsOneWidget);
    expect(stilDerKarte(tester), Kartenstil.hell);
    expect(zoomVon(tester), closeTo(16, 0.01));
    await finish(tester);
  });

  // Behoben in #413: _onGlobeZoomChanged baut auch neu, wenn die Stufe eine
  // Zoomgrenze erreicht oder verlässt; die Knöpfe werden dort grau.
  testWidgets('ORT-022 Zoomknöpfe des Globus werden an den Grenzen grau', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, globusPins);
    final befunde = <String>[];
    await weiterWeg(tester);
    if (zoomknopfAktiv(tester, de.karteHerauszoomen)) {
      befunde.add('„Weiter weg“ an der kleinsten Stufe aktiv');
    }
    for (var i = 0; i < 7; i++) {
      await naeher(tester);
    }
    if (zoomknopfAktiv(tester, de.karteHineinzoomen)) {
      befunde.add('„Näher heran“ an Stufe 6 aktiv');
    }
    print('ORT-022 $befunde');
    expect(befunde, isEmpty);
    await finish(tester);
  });

  // Behoben in #413: RotatingGlobe rechnet die Punktpositionen jetzt vor dem
  // Aufbau der Beschriftungen aus (third_party/flutter_earth_globe,
  // ANPASSUNGEN.md Punkt 4).
  testWidgets('ORT-018 Pins erscheinen beim Öffnen ohne Bedienung', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('b1.jpg', muenchen, DateTime(2024, 4, 10, 10)),
    ]);
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    await kartenansicht(tester, de.karteGlobus);
    await waitFor(tester, find.byType(FlutterEarthGlobe));
    final ende = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(ende) && globusPins.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final ohneBedienung = globusPins.evaluate().length;
    await klick(tester, find.byTooltip(de.karteHineinzoomen));
    await klick(tester, find.byTooltip(de.karteHerauszoomen));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final nachZoom = globusPins.evaluate().length;
    // Auf den Schwerpunkt gedreht? Dann liegen beide Pins nahe der Mitte.
    final mitteGlobus = tester.getCenter(find.byType(FlutterEarthGlobe));
    final abstaende = [
      for (final m in marker(tester, globusPins))
        (m.mitte - mitteGlobus).distance.round(),
    ];
    print('ORT-018 Abstand der Pins zur Globusmitte: $abstaende');
    print(
      'ORT-018 Pins ohne Bedienung: $ohneBedienung, nach Zoomschritt: $nachZoom',
    );
    expect(
      ohneBedienung,
      2,
      reason: 'Pins stehen erst nach der ersten Bedienung',
    );
    await finish(tester);
  });

  testWidgets('ORT-024 Globus mit rund 1000 verorteten Fotos', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('stadt.jpg', leipzig, DateTime(2024, 3, 1, 10)),
    ]);
    final basis = await aufnahme(tester, 'stadt.jpg');
    final zufall = math.Random(7);
    await tester.runAsync(
      () => bibliothek.db.batch((b) {
        b.insertAll(bibliothek.db.assets, [
          for (var i = 1; i < 1000; i++)
            basis.copyWith(
              id: 'stadt-$i',
              checksum: '${basis.checksum}-$i',
              originalFileName: 'stadt-$i.jpg',
              latitude: Value(leipzig.$1 + (zufall.nextDouble() - 0.5) * 0.1),
              longitude: Value(leipzig.$2 + (zufall.nextDouble() - 0.5) * 0.1),
            ),
        ]);
      }),
    );
    final mitOrt = await db(tester, () => bibliothek.db.assetsWithLocation());
    expect(mitOrt, hasLength(1000));
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker, timeout: const Duration(seconds: 30));
    await kartenansicht(tester, de.karteGlobus);
    await globusLabelsAbwarten(tester, globusPins);
    final zahlen = <int, int>{};
    final dauer = <int, int>{};
    for (var stufe = 1; stufe <= 6; stufe++) {
      final uhr = Stopwatch()..start();
      await naeher(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      dauer[stufe] = uhr.elapsedMilliseconds;
      zahlen[stufe] = globusPins.evaluate().length;
      expect(summe(tester, globusPins), lessThanOrEqualTo(1000));
    }
    print('ORT-024 Pins je Stufe: $zahlen, ms je Schritt: $dauer');
    for (var stufe = 4; stufe <= 6; stufe++) {
      expect(zahlen[stufe]!, lessThanOrEqualTo(zahlen[3]!), reason: '$stufe');
    }
    // Drehen auf Stufe 6.
    final globus = find.byType(FlutterEarthGlobe);
    await tester.drag(globus, const Offset(-200, 50));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(globusPins.evaluate().length, lessThanOrEqualTo(zahlen[3]!));
    await finish(tester);
  });

  // =========================================================================
  // Karteneinstellungen
  // =========================================================================

  testWidgets(
    'ORT-029 ORT-030 ORT-031 CARTO-Schlüssel und doppelte Auflösung',
    (tester) async {
      await starte(tester);
      await importiereDirekt(tester, [
        fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      ]);
      const schluessel = 'pruefschluessel-0815';
      final feld = field(de.einstCartoFeld);
      final speichern = find.descendant(
        of: find.ancestor(of: feld, matching: find.byType(Row)).first,
        matching: find.widgetWithText(FilledButton, de.allgSpeichern),
      );

      // ORT-029
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, feld);
      await eingeben(tester, feld, schluessel);
      await klick(tester, speichern);
      await meldung(tester, de.einstCartoGespeichert);
      expect(find.text(de.einstCartoAktiv), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text(de.einstCartoAktiv),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        await db(tester, () => bibliothek.db.cartoSchluesselWert()),
        schluessel,
      );
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      await kartenansicht(tester, de.karteDunkel);
      expect(kachelLage(tester).urlTemplate, contains('cartocdn'));
      expect(kachelLage(tester).urlTemplate, contains(schluessel));
      expect(kachelLage(tester).tileBuilder, isNull, reason: 'kein Umfärben');
      expect(find.text('© OpenStreetMap contributors © CARTO'), findsOneWidget);
      await neuStart(tester);
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, feld);
      await eventually(
        tester,
        () async =>
            tester.widget<TextField>(feld).controller!.text == schluessel,
        was: 'Schlüssel nach dem Neustart wieder im Feld',
      );
      expect(
        tester.widget<TextField>(feld).controller!.text,
        schluessel,
        reason: 'Schlüssel nach dem Neustart wieder im Feld',
      );

      // ORT-030
      await eingeben(tester, feld, '   ');
      await klick(tester, speichern);
      await meldung(tester, de.einstCartoEntfernt);
      expect(find.text(de.einstCartoOhne), findsOneWidget);
      expect(
        await db(tester, () => bibliothek.db.cartoSchluesselWert()),
        isNull,
      );
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      expect(kachelLage(tester).urlTemplate, contains('openstreetmap.org'));
      expect(kachelLage(tester).tileBuilder, isNotNull, reason: 'umgefärbt');

      // ORT-031
      final dicht =
          MediaQuery.devicePixelRatioOf(
            tester.element(find.byType(MapScreen)),
          ) >
          1.0;
      print('ORT-031 Punktdichte > 1: $dicht');
      expect(
        kachelLage(tester).resolvedRetinaMode != RetinaMode.disabled,
        dicht,
      );
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      final schalter = find.widgetWithText(
        SwitchListTile,
        de.einstKarteScharfTitel,
      );
      await zeigeEinstellung(tester, schalter);
      expect(tester.widget<SwitchListTile>(schalter).value, isTrue);
      await klick(tester, schalter);
      expect(tester.widget<SwitchListTile>(schalter).value, isFalse);
      expect(
        await db(tester, () => bibliothek.db.karteHochaufloesendWert()),
        isFalse,
      );
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      expect(kachelLage(tester).resolvedRetinaMode, RetinaMode.disabled);
      await neuStart(tester);
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, schalter);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(tester.widget<SwitchListTile>(schalter).value, isFalse);
      await finish(tester);
    },
  );

  testWidgets('ORT-033 ORT-035 Standardkarte und Vorlage ohne Schlüssel', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    Finder zeile(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ListTile));

    // ORT-033
    await einstellungsgruppe(tester, de.einstAbschnittKarte);
    await zeigeEinstellung(tester, zeile(de.karteTopografie));
    await stille(tester);
    await klick(
      tester,
      find.descendant(
        of: zeile(de.karteTopografie).first,
        matching: find.text(de.einstKartenquellenAlsStandard),
      ),
    );
    await meldung(
      tester,
      de.einstKartenquellenStandardGesetzt(de.karteTopografie),
    );
    expect(
      textIn(zeile(de.karteTopografie).first, de.einstKartenquellenStandard),
      findsOneWidget,
    );
    expect(
      textIn(zeile(de.karteTopografie).first, de.einstKartenquellenAlsStandard),
      findsNothing,
    );
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    expect(stilDerKarte(tester), Kartenstil.topo);
    expect(ansichtSymbol(Icons.terrain_outlined), findsOneWidget);

    // ORT-035
    final vorlage = kartenvorlagen.firstWhere((v) => v.sofortNutzbar);
    await einstellungsgruppe(tester, de.einstAbschnittKarte);
    await zeigeEinstellung(tester, zeile(vorlage.name));
    await stille(tester);
    await klick(
      tester,
      find.descendant(
        of: zeile(vorlage.name).first,
        matching: find.text(de.einstKartenquellenUebernehmen),
      ),
    );
    await waitFor(tester, find.text(de.einstEigeneKarteWarnungTitel));
    for (final t in [
      de.einstEigeneKarteWarnungUebermittlung,
      de.einstEigeneKarteWarnungOffline,
      de.einstEigeneKarteWarnungBedingungen,
    ]) {
      expect(textIn(dialogFeld, t), findsOneWidget);
    }
    await klick(tester, find.text(de.einstEigeneKarteWarnungAnnehmen));
    await meldung(tester, de.einstKartenquellenUebernommen(vorlage.name));
    expect(
      textIn(zeile(vorlage.name).first, de.einstKartenquellenStandard),
      findsOneWidget,
    );
    await karteOeffnen(tester);
    await waitFor(tester, fotomarker);
    expect(stilDerKarte(tester), Kartenstil.eigene);
    expect(ansichtSymbol(Icons.travel_explore_outlined), findsOneWidget);
    await klick(tester, find.byTooltip(de.karteAnsicht));
    expect(kartenmenueEintrag(vorlage.name), findsOneWidget);
    expect(find.byType(PopupMenuItem<Kartenansicht>), findsNWidgets(5));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await finish(tester);
  });

  Finder eigeneKarte() => find.byType(EigeneKarteEinstellung);
  Finder vorlagenKnopf() => find.ancestor(
    of: find.text(de.einstEigeneKarteVorlage),
    matching: find.byWidgetPredicate((w) => w is OutlinedButton),
  );
  Finder formularSpeichern() => find.descendant(
    of: eigeneKarte(),
    matching: find.widgetWithText(FilledButton, de.allgSpeichern),
  );
  String feldtext(WidgetTester tester, String beschriftung) =>
      tester.widget<TextField>(field(beschriftung)).controller!.text;
  String? feldfehler(WidgetTester tester, String beschriftung) =>
      tester.widget<TextField>(field(beschriftung)).decoration!.errorText;
  Future<void> vorlageWaehlen(WidgetTester tester, Kartenvorlage v) async {
    await zeigeEinstellung(tester, vorlagenKnopf());
    await stille(tester);
    await klick(tester, vorlagenKnopf());
    await klick(tester, find.text(v.name).last);
  }

  testWidgets(
    'ORT-038 ORT-039 ORT-040 ORT-041 ORT-045 Formular „Eigene Kartenquelle“',
    (tester) async {
      await starte(tester);
      await einstellungsgruppe(tester, de.einstAbschnittKarte);

      // ORT-038: Menü mit allen Vorlagen, Wahl füllt nur die Felder.
      await zeigeEinstellung(tester, vorlagenKnopf());
      await stille(tester);
      await klick(tester, vorlagenKnopf());
      for (final v in kartenvorlagen) {
        final eintrag = find.ancestor(
          of: find.text(v.name).last,
          matching: find.byType(ListTile),
        );
        expect(eintrag, findsWidgets, reason: v.name);
        expect(
          textIn(
            eintrag.first,
            v.gemessen
                ? de.einstEigeneKarteVorlageGemessen('${v.stufe}')
                : de.einstEigeneKarteVorlageLautAnbieter('${v.stufe}'),
          ),
          findsOneWidget,
          reason: v.name,
        );
      }
      final ohne = kartenvorlagen.firstWhere((v) => v.sofortNutzbar);
      await klick(tester, find.text(ohne.name).last);
      expect(feldtext(tester, de.einstEigeneKarteName), ohne.name);
      expect(feldtext(tester, de.einstEigeneKarteAdresse), ohne.url);
      expect(feldtext(tester, de.einstEigeneKarteNennung), ohne.nennung);
      expect(feldtext(tester, de.einstEigeneKarteStufe), '${ohne.stufe}');
      expect(await db(tester, () => bibliothek.db.eigeneKarteWert()), isNull);

      // ORT-039: stehengebliebene Schlüsselmarke.
      final mitSchluessel = kartenvorlagen.firstWhere(
        (v) => v.brauchtSchluessel && !v.sitzungNoetig,
      );
      await vorlageWaehlen(tester, mitSchluessel);
      expect(
        feldtext(tester, de.einstEigeneKarteAdresse),
        contains(schluesselMarke),
      );
      await stille(tester);
      await klick(tester, formularSpeichern());
      await meldung(tester, de.einstEigeneKarteFehlerSchluessel);
      expect(
        feldfehler(tester, de.einstEigeneKarteAdresse),
        de.einstEigeneKarteFehlerSchluessel,
      );
      expect(find.text(de.einstEigeneKarteWarnungTitel), findsNothing);
      expect(await db(tester, () => bibliothek.db.eigeneKarteWert()), isNull);

      // ORT-040: Prüfung der Kacheladresse.
      final adresse = field(de.einstEigeneKarteAdresse);
      for (final (eingabe, fehler, unterDemFeld) in [
        ('', de.einstEigeneKarteFehlerLeer, false),
        ('kacheln.test/{z}/{x}/{y}.png', de.einstEigeneKarteFehlerHttp, true),
        (
          'https://kacheln.test/karte.png',
          de.einstEigeneKarteFehlerPlatzhalter('{z}, {x}, {y}'),
          true,
        ),
        (
          'https://kacheln.test/{z}/{x}/{y}/{foo}.png',
          de.einstEigeneKarteFehlerUnbekannt('{z}, {x}, {y}, {s}, {r}'),
          true,
        ),
      ]) {
        await eingeben(tester, adresse, eingabe);
        print(
          'ORT-040 Feld: „${feldtext(tester, de.einstEigeneKarteAdresse)}“, '
          'Fehler: ${feldfehler(tester, de.einstEigeneKarteAdresse)}',
        );
        expect(
          feldfehler(tester, de.einstEigeneKarteAdresse),
          unterDemFeld ? fehler : isNull,
          reason: 'beim Tippen: $eingabe',
        );
        await stille(tester);
        await klick(tester, formularSpeichern());
        await meldung(tester, fehler);
        expect(find.text(de.einstEigeneKarteWarnungTitel), findsNothing);
      }
      expect(await db(tester, () => bibliothek.db.eigeneKarteWert()), isNull);

      // ORT-041: Namensnennung ist Pflicht.
      await eingeben(tester, adresse, 'https://kacheln.test/{z}/{x}/{y}.png');
      expect(feldfehler(tester, de.einstEigeneKarteAdresse), isNull);
      await eingeben(tester, field(de.einstEigeneKarteNennung), '');
      await stille(tester);
      await klick(tester, formularSpeichern());
      await meldung(tester, de.einstEigeneKarteFehlerNennung);
      expect(find.text(de.einstEigeneKarteWarnungTitel), findsNothing);
      expect(await db(tester, () => bibliothek.db.eigeneKarteWert()), isNull);

      // ORT-045: Google ohne Schlüssel.
      final google = kartenvorlagen.firstWhere((v) => v.sitzungNoetig);
      await vorlageWaehlen(tester, google);
      expect(find.text(de.einstEigeneKarteSitzungText), findsOneWidget);
      final sitzung = find.text(de.einstEigeneKarteSitzung);
      await zeigeEinstellung(tester, sitzung);
      netz.versuche.clear();
      await stille(tester);
      await klick(tester, sitzung);
      await meldung(tester, de.einstEigeneKarteSitzungOhneSchluessel);
      expect(
        netz.versuche.where((u) => u.host.contains('google')),
        isEmpty,
        reason: 'keine Anfrage an Google',
      );
      await finish(tester);
    },
  );

  // Behoben in #413: Der Knopf ist bedienbar und öffnet das Vorlagenmenü
  // selbst (showButtonMenu über den Schlüssel des PopupMenuButton).
  testWidgets('ORT-038 Knopf „Vorlage übernehmen“ sieht bedienbar aus', (
    tester,
  ) async {
    await starte(tester);
    await einstellungsgruppe(tester, de.einstAbschnittKarte);
    await zeigeEinstellung(tester, vorlagenKnopf());
    expect(
      tester.widget<OutlinedButton>(vorlagenKnopf().first).enabled,
      isTrue,
      reason: 'Knopf ist mit onPressed: null gebaut und wirkt ausgegraut',
    );
    await finish(tester);
  });

  testWidgets(
    'ORT-042 ORT-044 Eigene Kartenquelle speichern, benutzen, entfernen',
    (tester) async {
      await starte(tester);
      await importiereDirekt(tester, [
        fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      ]);
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, field(de.einstEigeneKarteName));
      await eingeben(tester, field(de.einstEigeneKarteName), 'Testkarte');
      await eingeben(
        tester,
        field(de.einstEigeneKarteAdresse),
        'https://kacheln.test/{z}/{x}/{y}.png',
      );
      await eingeben(tester, field(de.einstEigeneKarteNennung), '© Testkarte');
      await eingeben(tester, field(de.einstEigeneKarteStufe), '18');
      await stille(tester);
      await klick(tester, formularSpeichern());
      await waitFor(tester, find.text(de.einstEigeneKarteWarnungTitel));
      await klick(tester, find.text(de.einstEigeneKarteWarnungAnnehmen));
      await meldung(tester, de.einstEigeneKarteGespeichert);
      expect(find.text(de.einstEigeneKarteAktiv('Testkarte')), findsOneWidget);
      expect(find.text(de.einstEigeneKarteEntfernen), findsOneWidget);
      final gespeichert = await db(
        tester,
        () => bibliothek.db.eigeneKarteWert(),
      );
      expect(gespeichert?.name, 'Testkarte');
      expect(gespeichert?.stufe, 18);

      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      await kartenansicht(tester, 'Testkarte');
      expect(stilDerKarte(tester), Kartenstil.eigene);
      expect(find.text('© Testkarte'), findsOneWidget);
      await schwenke(tester, hamburg, zoom: 15);
      var vorher = zoomVon(tester);
      for (var i = 0; i < 10; i++) {
        await naeher(tester);
        if (zoomVon(tester) == vorher) break;
        vorher = zoomVon(tester);
      }
      expect(zoomVon(tester), closeTo(20, 0.01), reason: '18 + 2 Stufen');

      await neuStart(tester);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      expect(stilDerKarte(tester), Kartenstil.eigene);
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, field(de.einstEigeneKarteName));
      expect(feldtext(tester, de.einstEigeneKarteName), 'Testkarte');
      expect(feldtext(tester, de.einstEigeneKarteStufe), '18');
      expect(find.text(de.einstEigeneKarteAktiv('Testkarte')), findsOneWidget);

      // ORT-044
      final entfernen = find.text(de.einstEigeneKarteEntfernen);
      await zeigeEinstellung(tester, entfernen);
      await stille(tester);
      await klick(tester, entfernen);
      await meldung(tester, de.einstEigeneKarteEntfernt);
      expect(feldtext(tester, de.einstEigeneKarteName), isEmpty);
      expect(feldtext(tester, de.einstEigeneKarteAdresse), isEmpty);
      expect(feldtext(tester, de.einstEigeneKarteNennung), isEmpty);
      expect(find.text(de.einstEigeneKarteOhne), findsOneWidget);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      expect(stilDerKarte(tester), Kartenstil.dunkel);
      expect(ansichtSymbol(Icons.dark_mode_outlined), findsOneWidget);
      await klick(tester, find.byTooltip(de.karteAnsicht));
      expect(kartenmenueEintrag('Testkarte'), findsNothing);
      expect(find.byType(PopupMenuItem<Kartenansicht>), findsNWidgets(4));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);

      // Hinweis zu ORT-042: leerer Name.
      await einstellungsgruppe(tester, de.einstAbschnittKarte);
      await zeigeEinstellung(tester, field(de.einstEigeneKarteName));
      await eingeben(tester, field(de.einstEigeneKarteName), '');
      await eingeben(
        tester,
        field(de.einstEigeneKarteAdresse),
        'https://kacheln.test/{z}/{x}/{y}.png',
      );
      await eingeben(tester, field(de.einstEigeneKarteNennung), '© Testkarte');
      await stille(tester);
      await klick(tester, formularSpeichern());
      await klick(tester, find.text(de.einstEigeneKarteWarnungAnnehmen));
      await meldung(tester, de.einstEigeneKarteGespeichert);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      await klick(tester, find.byTooltip(de.karteAnsicht));
      final eintraege = find.byType(PopupMenuItem<Kartenansicht>);
      expect(eintraege, findsNWidgets(5));
      final namen = [
        for (final e in eintraege.evaluate())
          find
              .descendant(
                of: find.byElementPredicate((x) => identical(x, e)),
                matching: find.byType(Text),
              )
              .evaluate()
              .map((t) => (t.widget as Text).data ?? '')
              .join(),
      ];
      print('ORT-042 Menü mit leerem Namen: $namen');
      expect(namen, contains(de.karteEigene));
      expect(namen.where((n) => n.trim().isEmpty), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      await finish(tester);
    },
  );

  testWidgets('ORT-048 Vorladen-Dialog nennt Umfang und bricht ab', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('b.jpg', rom, DateTime(2024, 3, 2, 10)),
    ]);
    await einstellungsgruppe(tester, de.einstAbschnittKarte);
    final vorladen = find.text(de.einstVorladenTitel);
    await zeigeEinstellung(tester, vorladen);
    await klick(tester, vorladen);
    await waitFor(tester, dialogFeld);
    final inhalt = find.descendant(
      of: dialogFeld,
      matching: find.textContaining('Gebiete,'),
    );
    expect(inhalt, findsOneWidget);
    final satz = textVon(tester, inhalt);
    print('ORT-048 $satz');
    expect(satz, startsWith('2 Gebiete,'));
    expect(satz, contains('Kacheln, rund'));
    expect(satz, contains('MB'));
    await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
    expect(dialogFeld, findsNothing);
    expect(find.text(de.einstVorladenText), findsOneWidget);
    await finish(tester);
  });

  // =========================================================================
  // Standortdaten (GeoNames)
  // =========================================================================

  Future<void> standortdatenOeffnen(WidgetTester tester) async {
    await einstellungsgruppe(tester, de.einstAbschnittStandortdaten);
    await zeigeEinstellung(tester, find.text(de.einstGeoTitel));
  }

  Finder geoZeile() => find.ancestor(
    of: find.text(de.einstGeoTitel),
    matching: find.byType(ListTile),
  );

  testWidgets('ORT-055 GeoNames-Datensatz herunterladen', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('ohne.jpg', datum: DateTime(2024, 2, 1, 10)),
    ]);
    await standortdatenOeffnen(tester);
    final herunterladen = find.descendant(
      of: geoZeile(),
      matching: find.text(de.allgHerunterladen),
    );
    expect(herunterladen, findsOneWidget);
    netz.offen = true;
    await tester.tap(herunterladen);
    await tester.pump();
    await waitFor(tester, find.text(de.einstGeoLaedt));
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.textContaining('%'), findsWidgets);
    // Wegwischen und daneben tippen: das Blatt bleibt.
    await tester.drag(
      find.text(de.einstGeoLaedt),
      const Offset(0, 300),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    final nochDa1 = find.text(de.einstGeoLaedt).evaluate().isNotEmpty;
    // Daneben tippen – in die abgedunkelte Arbeitsfläche, nicht in die
    // Seitenleiste (dort liegt die Sperrfläche des Blatts nicht).
    await tester.tapAt(
      tester.getTopLeft(find.byType(SettingsScreen)) + const Offset(60, 60),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final nochDa2 = find.text(de.einstGeoLaedt).evaluate().isNotEmpty;
    final fertig = bibliothek.geoDataDownloadService.isInstalled;
    print('ORT-055 Blatt nach Wischen: $nochDa1, nach Tippen: $nochDa2');
    if (!fertig) {
      expect(nochDa1, isTrue, reason: 'Blatt lässt sich nicht wegwischen');
      expect(nochDa2, isTrue);
    }
    await waitGone(
      tester,
      find.text(de.einstGeoLaedt),
      timeout: const Duration(minutes: 4),
    );
    netz.offen = false;
    await eventually(tester, () async => bibliothek.geoDataAvailable);
    await settle(tester);
    expect(
      find.descendant(
        of: geoZeile(),
        matching: find.byTooltip(de.einstGeoLoeschen),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: geoZeile(),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    await tester.runAsync(() async => geoInZwischenspeicher());

    await bereich(tester, Hauptbereich.orte);
    await waitFor(tester, find.byType(LaenderlisteScreen));
    await waitFor(tester, find.textContaining(' Länder · '));
    final ohne = await aufnahme(tester, 'ohne.jpg');
    await oeffneInZeitleiste(tester, ohne.id);
    await info(tester);
    await eingeben(tester, field(de.infoOrtSuchen), 'Ham');
    expect(
      find.descendant(
        of: infoBereich,
        matching: find.byIcon(Icons.place_outlined),
      ),
      findsWidgets,
    );
    await viewerZu(tester);
    await finish(tester);
  });

  testWidgets('ORT-056 GeoNames-Download ohne Netz', (tester) async {
    await starte(tester);
    final vorher = DateTime.now();
    await standortdatenOeffnen(tester);
    await klick(
      tester,
      find.descendant(
        of: geoZeile(),
        matching: find.text(de.allgHerunterladen),
      ),
    );
    await waitGone(
      tester,
      find.text(de.einstGeoLaedt),
      timeout: const Duration(seconds: 60),
    );
    await settle(tester);
    expect(
      melde.verlauf.any(
        (m) => m.art == Meldungsart.fehler && !m.zeit.isBefore(vorher),
      ),
      isTrue,
      reason: 'eine Fehlermeldung',
    );
    expect(
      find.descendant(
        of: geoZeile(),
        matching: find.text(de.allgHerunterladen),
      ),
      findsOneWidget,
    );
    expect(bibliothek.geoDataAvailable, isFalse);
    expect(bibliothek.geoDataDownloadService.isInstalled, isFalse);
    final ordner = Directory(bibliothek.geoDataDownloadService.geoDataDir);
    expect(
      ordner.parent.listSync().where(
        (e) => p.basename(e.path).startsWith('geodata.download-'),
      ),
      isEmpty,
      reason: 'kein halber Satz',
    );
    expect(netz.versuche, isNotEmpty);
    await finish(tester);
  });

  testWidgets('ORT-057 GeoNames-Datensatz löschen', (tester) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    final a = await aufnahme(tester, 'a.jpg');
    expect(a.locationCity, isNotNull);
    await standortdatenOeffnen(tester);
    await klick(
      tester,
      find.descendant(
        of: geoZeile(),
        matching: find.byTooltip(de.einstGeoLoeschen),
      ),
    );
    await eventually(tester, () async => !bibliothek.geoDataAvailable);
    await settle(tester);
    expect(bibliothek.geoDataDownloadService.isInstalled, isFalse);
    expect(
      find.descendant(
        of: geoZeile(),
        matching: find.text(de.allgHerunterladen),
      ),
      findsOneWidget,
    );
    await bereich(tester, Hauptbereich.orte);
    await waitFor(tester, find.text(de.laenderOhneGeodaten));
    expect((await aufnahme(tester, 'a.jpg')).locationCity, a.locationCity);
    await oeffneInZeitleiste(tester, a.id);
    await info(tester);
    expect(textIn(infoBereich, a.locationCity!), findsWidgets);
    await viewerZu(tester);
    await finish(tester);
  });

  testWidgets('ORT-058 Ortsnamen werden offline aufgelöst', (tester) async {
    await starte(tester);
    // Erst importieren, dann den Datensatz laden: Koordinate ohne Namen.
    await importiereDirekt(tester, [
      fotoBei('a.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('b.jpg', muenchen, DateTime(2024, 3, 2, 10)),
    ]);
    expect((await aufnahme(tester, 'a.jpg')).locationCity, isNull);
    await geonamesBereitstellen(tester);
    netz.versuche.clear();
    await aufgabenOeffnen(tester);
    await aufgabeStarten(tester, de.werkzOrteAufloesenTitel, de.aufgFehlende);
    await eventually(
      tester,
      () async => (await bibliothek.db.select(bibliothek.db.assets).get())
          .every((a) => a.locationCity != null),
      timeout: const Duration(seconds: 60),
    );
    await aufgabeFertig(tester, de.werkzOrteAufloesenTitel);
    expect(netz.versuche, isEmpty, reason: 'keine Anfrage ins Netz');
    final a = await aufnahme(tester, 'a.jpg');
    expect(a.locationCountry, isNotNull);
    expect(a.locationState, isNotNull);
    // Ein zweiter Lauf hat nichts mehr zu tun.
    await aufgabeStarten(tester, de.werkzOrteAufloesenTitel, de.aufgFehlende);
    await waitFor(tester, find.textContaining(de.werkzAlleAufgeloest));
    await oeffneInZeitleiste(tester, a.id);
    await info(tester);
    expect(textIn(infoBereich, a.locationCity!), findsWidgets);
    await viewerZu(tester);
    await finish(tester);
  });

  testWidgets('ORT-060 Orte aus Dateien nachträglich einlesen', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      fotoBei('gps1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('gps2.jpg', muenchen, DateTime(2024, 3, 2, 10)),
      testfoto('ohne.jpg', datum: DateTime(2024, 3, 3, 10)),
    ]);
    // Wie in einer älteren Bibliothek: GPS in der Datei, kein Ort im Eintrag.
    await sql(
      tester,
      'UPDATE assets SET latitude = NULL, longitude = NULL, '
      'location_country = NULL, location_state = NULL, location_city = NULL, '
      'gps_geprueft = 0',
    );
    final originale = {
      for (final a in await alle(tester))
        a.originalFileName: bibliothek.paths
            .absolute(a.relativePath)
            .readAsBytesSync(),
    };
    await aufgabenOeffnen(tester);
    await aufgabeStarten(tester, de.aufgOrteTitel, de.aufgFehlende);
    await aufgabeFertig(tester, de.aufgOrteTitel);
    final g1 = await aufnahme(tester, 'gps1.jpg');
    final g2 = await aufnahme(tester, 'gps2.jpg');
    final o = await aufnahme(tester, 'ohne.jpg');
    expect(g1.latitude, closeTo(hamburg.$1, 0.001));
    expect(g2.longitude, closeTo(muenchen.$2, 0.001));
    expect(o.latitude, isNull, reason: 'nicht 0/0');
    expect(o.longitude, isNull);
    expect(
      await db(tester, () => bibliothek.db.countLocationBackfill()),
      0,
      reason: 'zweiter Lauf hat nichts zu tun',
    );
    await aufgabeStarten(tester, de.aufgOrteTitel, de.aufgFehlende);
    await waitFor(tester, find.textContaining(de.werkzAlleHabenOrt));
    expect(
      await db(tester, () => bibliothek.db.countLocationBackfill(alle: true)),
      1,
      reason: '„Alle“ sieht das schon geprüfte Foto wieder',
    );
    await aufgabeStarten(tester, de.aufgOrteTitel, de.aufgModusAlle);
    await aufgabeFertig(tester, de.aufgOrteTitel);
    expect((await aufnahme(tester, 'ohne.jpg')).latitude, isNull);
    for (final a in await alle(tester)) {
      expect(
        bibliothek.paths.absolute(a.relativePath).readAsBytesSync(),
        originale[a.originalFileName],
        reason: 'Original ${a.originalFileName} unverändert',
      );
    }
    await finish(tester);
  });

  // =========================================================================
  // Ort setzen
  // =========================================================================

  testWidgets(
    'ORT-061 ORT-062 ORT-063 ORT-069 Ort per Karte setzen, ändern, entfernen; '
    'Original bleibt unverändert',
    (tester) async {
      await starte(tester, geodaten: true);
      await importiereDirekt(tester, [
        testfoto('ohne.jpg', datum: DateTime(2024, 3, 1, 10)),
        fotoBei('mit.jpg', hamburg, DateTime(2024, 3, 2, 10)),
      ]);
      final ohne = await aufnahme(tester, 'ohne.jpg');
      var mit = await aufnahme(tester, 'mit.jpg');
      final original = bibliothek.paths.absolute(mit.relativePath);
      final bytesVorher = original.readAsBytesSync();
      final zeitVorher = original.lastModifiedSync();
      final exifVorher = img.decodeJpgExif(bytesVorher)!;

      // ORT-061
      await oeffneInZeitleiste(tester, ohne.id);
      await info(tester);
      expect(textIn(infoKarte, de.karteTippenFuerOrt), findsOneWidget);
      await setzeOrtPerKlick(tester, paris, karte: infoKarteFlutter);
      await eventually(
        tester,
        () async =>
            (await bibliothek.db.assetById(ohne.id))?.locationCity != null,
      );
      await settle(tester);
      final gesetzt = (await bibliothek.db.assetById(ohne.id))!;
      expect(gesetzt.latitude, closeTo(paris.$1, 0.01));
      expect(
        find.descendant(
          of: infoKarte,
          matching: find.byIcon(Icons.location_pin),
        ),
        findsOneWidget,
      );
      expect(textIn(infoBereich, gesetzt.locationCity!), findsWidgets);
      expect(textEnthaeltIn(infoBereich, gesetzt.locationState!), findsWidgets);
      await viewerZu(tester);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      await schwenke(tester, paris, zoom: 10);
      expect(markerBei(tester, paris), [1]);

      // ORT-062
      await oeffneInZeitleiste(tester, mit.id);
      await info(tester);
      final stadtVorher = mit.locationCity!;
      expect(textIn(infoBereich, stadtVorher), findsWidgets);
      await setzeOrtPerKlick(tester, rom, karte: infoKarteFlutter);
      await eventually(
        tester,
        () async =>
            ((await bibliothek.db.assetById(mit.id))?.latitude ?? 0) < 45,
      );
      await settle(tester);
      mit = (await bibliothek.db.assetById(mit.id))!;
      expect(mit.latitude, closeTo(rom.$1, 0.01));
      expect(mit.locationCity, isNot(stadtVorher));
      expect(textIn(infoBereich, mit.locationCity!), findsWidgets);
      expect(
        tester.widget<MiniLocationMap>(infoKarte).latitude,
        closeTo(rom.$1, 0.01),
      );
      await viewerZu(tester);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      await schwenke(tester, rom, zoom: 10);
      expect(markerBei(tester, rom), [1]);
      await schwenke(tester, hamburg, zoom: 10);
      expect(markerBei(tester, hamburg), isEmpty);

      // ORT-063
      await oeffneInZeitleiste(tester, mit.id);
      await info(tester);
      await klick(tester, find.byTooltip(de.infoOrtEntfernen));
      await settle(tester);
      expect(find.byTooltip(de.infoOrtEntfernen), findsNothing);
      expect(textIn(infoKarte, de.karteTippenFuerOrt), findsOneWidget);
      mit = (await bibliothek.db.assetById(mit.id))!;
      expect(mit.latitude, isNull);
      expect(mit.locationCity, isNull);
      expect(mit.locationCountry, isNull);
      await viewerZu(tester);
      await karteOeffnen(tester);
      await waitFor(tester, fotomarker);
      expect(summe(tester), 1, reason: 'nur noch das Foto in Paris');
      await bereich(tester, Hauptbereich.orte);
      await waitFor(tester, find.byType(LaenderlisteScreen));
      await laenderSuchen(tester, landname('IT'));
      expect(
        unterzeile(tester, landzeile(landname('IT'))),
        isNot(contains('Aufnahme')),
      );

      // ORT-069: ändern, entfernen, per „Ort suchen“ neu setzen.
      await oeffneInZeitleiste(tester, mit.id);
      await info(tester);
      await setzeOrtPerKlick(tester, wien, karte: infoKarteFlutter);
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(mit.id))?.latitude != null,
      );
      await klick(tester, find.byTooltip(de.infoOrtEntfernen));
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(mit.id))?.latitude == null,
      );
      await eingeben(tester, field(de.infoOrtSuchen), 'Berlin');
      await klick(
        tester,
        find.descendant(
          of: infoBereich,
          matching: find.byTooltip(de.infoOrtSuchen),
        ),
      );
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(mit.id))?.latitude != null,
      );
      mit = (await bibliothek.db.assetById(mit.id))!;
      expect(mit.latitude, closeTo(berlin.$1, 0.3));
      await viewerZu(tester);
      final bytesNachher = original.readAsBytesSync();
      expect(bytesNachher, bytesVorher, reason: 'Prüfsumme unverändert');
      expect(original.lastModifiedSync(), zeitVorher);
      final exifNachher = img.decodeJpgExif(bytesNachher)!;
      expect(
        exifNachher.gpsIfd[0x0002].toString(),
        exifVorher.gpsIfd[0x0002].toString(),
      );
      expect(
        exifNachher.gpsIfd[0x0004].toString(),
        exifVorher.gpsIfd[0x0004].toString(),
      );
      await finish(tester);
    },
  );

  testWidgets('ORT-064 Ort setzen ohne Ortsverzeichnis, später auflösen', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('ohne.jpg', datum: DateTime(2024, 3, 1, 10)),
    ]);
    final ohne = await aufnahme(tester, 'ohne.jpg');
    await oeffneInZeitleiste(tester, ohne.id);
    await info(tester);
    await setzeOrtPerKlick(tester, hamburg, karte: infoKarteFlutter);
    await eventually(
      tester,
      () async => (await bibliothek.db.assetById(ohne.id))?.latitude != null,
    );
    await settle(tester);
    expect(textIn(infoBereich, de.infoStandortBekannt), findsOneWidget);
    expect(textIn(infoBereich, de.infoOrtNichtAufgeloest), findsOneWidget);
    expect((await bibliothek.db.assetById(ohne.id))!.locationCity, isNull);
    await viewerZu(tester);

    await geonamesBereitstellen(tester);
    await aufgabenOeffnen(tester);
    await aufgabeStarten(tester, de.werkzOrteAufloesenTitel, de.aufgFehlende);
    await eventually(
      tester,
      () async =>
          (await bibliothek.db.assetById(ohne.id))?.locationCity != null,
      timeout: const Duration(seconds: 60),
    );
    final stadt = (await bibliothek.db.assetById(ohne.id))!.locationCity!;
    await oeffneInZeitleiste(tester, ohne.id);
    await info(tester);
    expect(textIn(infoBereich, stadt), findsWidgets);
    await viewerZu(tester);
    await finish(tester);
  });

  // Behoben in #413: Der Wegweiser nennt Werkzeuge → Aufgaben und die
  // Aufgabe „Land/Bundesland/Stadt auflösen“; dort steht sie auch.
  testWidgets('ORT-064 Wegweiser „Werkzeuge → Orte“ führt zum Auflösen', (
    tester,
  ) async {
    await starte(tester);
    expect(
      de.infoOrtNichtAufgeloest,
      contains('${de.navWerkzeuge} → ${de.aufgTitel}'),
    );
    expect(de.infoOrtNichtAufgeloest, contains(de.werkzOrteAufloesenTitel));
    await aufgabenOeffnen(tester);
    await sichtbarIn(
      tester,
      find.text(de.werkzOrteAufloesenTitel),
      aufgabenliste,
    );
    expect(
      find.descendant(
        of: find.byType(BackgroundTasksScreen),
        matching: find.text(de.werkzOrteAufloesenTitel),
      ),
      findsOneWidget,
      reason: 'unter Werkzeuge → Aufgaben steht das Auflösen',
    );
    await finish(tester);
  });

  testWidgets('ORT-065 Ortsvorschläge beim Tippen', (tester) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('mit.jpg', hamburg, DateTime(2024, 3, 2, 10)),
    ]);
    final mit = await aufnahme(tester, 'mit.jpg');
    await oeffneInZeitleiste(tester, mit.id);
    await info(tester);
    final vorschlaege = find.descendant(
      of: infoBereich,
      matching: find.byIcon(Icons.place_outlined),
    );
    await eingeben(tester, field(de.infoOrtSuchen), 'B');
    expect(vorschlaege, findsNothing, reason: 'ein Buchstabe ist zu wenig');
    await eingeben(tester, field(de.infoOrtSuchen), 'Br');
    expect(vorschlaege, findsWidgets, reason: 'ab zwei Buchstaben');
    final zuBr = [
      for (final e
          in find
              .ancestor(of: vorschlaege, matching: find.byType(ListTile))
              .evaluate())
        ((e.widget as ListTile).title as Text).data,
    ];
    print('ORT-065 Vorschläge zu „Br“: $zuBr');
    // Mehrdeutiger Name: Unter gleichnamigen Orten entscheidet die Nähe.
    await eingeben(tester, field(de.infoOrtSuchen), 'Neustadt');
    final treffer = geo.vorschlaege(
      'Neustadt',
      naheBreite: mit.latitude,
      naheLaenge: mit.longitude,
    );
    final zeilen = find.ancestor(
      of: vorschlaege,
      matching: find.byType(ListTile),
    );
    expect(zeilen.evaluate().length, treffer.length);
    double abstand(OrtsTreffer t) => ReverseGeocoder.haversineKm(
      t.breite,
      t.laenge,
      mit.latitude!,
      mit.longitude!,
    );
    final naechster = treffer.reduce(
      (a, b) => abstand(a) <= abstand(b) ? a : b,
    );
    final erste = tester.widget<ListTile>(zeilen.first);
    expect((erste.title as Text).data, naechster.name, reason: 'Nächster oben');
    expect((erste.subtitle as Text?)?.data, naechster.herkunft);
    if (naechster.einwohner > 0) expect(erste.trailing, isNotNull);
    await klick(tester, zeilen.first);
    await meldung(
      tester,
      de.infoOrtGesetzt(
        naechster.herkunft.isEmpty
            ? naechster.name
            : '${naechster.name}, ${naechster.herkunft}',
      ),
    );
    expect(
      tester.widget<TextField>(field(de.infoOrtSuchen)).controller!.text,
      isEmpty,
    );
    expect(vorschlaege, findsNothing);
    final neu = (await bibliothek.db.assetById(mit.id))!;
    expect(neu.latitude, closeTo(naechster.breite, 1e-6));
    expect(
      tester.widget<MiniLocationMap>(infoKarte).latitude,
      closeTo(naechster.breite, 1e-6),
    );
    expect(textIn(infoBereich, neu.locationCity!), findsWidgets);
    await viewerZu(tester);
    await finish(tester);
  });

  testWidgets('ORT-070 ORT-071 Ort für mehrere Fotos setzen und entfernen', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      testfoto('o1.jpg', datum: DateTime(2024, 3, 1, 10)),
      testfoto('o2.jpg', datum: DateTime(2024, 3, 2, 10)),
      testfoto('o3.jpg', datum: DateTime(2024, 3, 3, 10)),
      fotoBei('v1.jpg', hamburg, DateTime(2024, 3, 4, 10)),
    ]);
    await sql(
      tester,
      "UPDATE assets SET description = 'Beschreibung ' || original_file_name",
    );
    final vorher = {for (final a in await alle(tester)) a.id: a};
    final ids = vorher.keys.toList();

    Future<void> auswaehlen() async {
      await bereich(tester, Hauptbereich.zeitleiste);
      await settle(tester);
      await tester.longPress(kachel(ids.first));
      await settle(tester);
      for (final id in ids.skip(1)) {
        await klick(tester, kachel(id));
      }
      await klick(tester, find.byTooltip(de.auswMetadaten));
      await waitFor(tester, find.text(de.auswMetadatenTitel(4)));
    }

    final dialogKarte = find.descendant(
      of: dialogFeld,
      matching: find.byType(FlutterMap),
    );

    // ORT-070
    await auswaehlen();
    expect(textIn(dialogFeld, de.auswOrtHinweis), findsOneWidget);
    await setzeOrtPerKlick(tester, wien, karte: dialogKarte);
    await klick(tester, textIn(dialogFeld, de.allgSpeichern));
    await eventually(
      tester,
      () async => (await bibliothek.db.select(bibliothek.db.assets).get())
          .every((a) => a.locationCity != null && a.latitude! < 49),
      timeout: const Duration(seconds: 30),
    );
    final nach = await alle(tester);
    final staedte = nach.map((a) => a.locationCity).toSet();
    expect(staedte, hasLength(1));
    for (final a in nach) {
      expect(a.latitude, closeTo(wien.$1, 0.01));
      expect(a.description, vorher[a.id]!.description);
      expect(a.fileCreatedAt, vorher[a.id]!.fileCreatedAt);
    }

    // ORT-071: nichts antippen → Speichern; Abbrechen; dann entfernen.
    await auswaehlen();
    await klick(tester, textIn(dialogFeld, de.allgSpeichern));
    await settle(tester);
    for (final a in await alle(tester)) {
      expect(a.latitude, closeTo(wien.$1, 0.01), reason: 'unverändert');
    }
    await auswaehlen();
    await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
    await settle(tester);
    for (final a in await alle(tester)) {
      expect(a.latitude, closeTo(wien.$1, 0.01), reason: 'Abbrechen');
    }
    await auswaehlen();
    final haken = find.widgetWithText(CheckboxListTile, de.auswOrtEntfernen);
    await klick(tester, haken);
    expect(tester.widget<CheckboxListTile>(haken).value, isTrue);
    await setzeOrtPerKlick(tester, rom, karte: dialogKarte);
    expect(
      tester.widget<CheckboxListTile>(haken).value,
      isFalse,
      reason: 'Klick auf die Karte nimmt den Haken weg',
    );
    await klick(tester, haken);
    expect(tester.widget<CheckboxListTile>(haken).value, isTrue);
    await klick(tester, textIn(dialogFeld, de.allgSpeichern));
    await eventually(
      tester,
      () async => (await bibliothek.db.select(bibliothek.db.assets).get())
          .every((a) => a.latitude == null),
    );
    await finish(tester);
  });

  // =========================================================================
  // Orte von Nachbarn
  // =========================================================================

  List<File> nachbarnTag(String praefix, DateTime tag, Ort ort) => [
    fotoBei('${praefix}_v1.jpg', ort, tag.add(const Duration(hours: 10))),
    testfoto(
      '${praefix}_o1.jpg',
      datum: tag.add(const Duration(hours: 10, minutes: 30)),
    ),
    testfoto('${praefix}_o2.jpg', datum: tag.add(const Duration(hours: 11))),
    testfoto(
      '${praefix}_o3.jpg',
      datum: tag.add(const Duration(hours: 11, minutes: 30)),
    ),
    fotoBei(
      '${praefix}_v2.jpg',
      ort,
      tag.add(const Duration(hours: 12)),
      dBreite: 0.001,
    ),
  ];

  Future<void> nachbarnOeffnen(WidgetTester tester) async {
    await bereich(tester, Hauptbereich.werkzeuge);
    await waitFor(tester, find.byType(ToolsScreen));
    final eintrag = find.text(de.ortVorschlagWerkzTitel);
    await sichtbarIn(
      tester,
      eintrag,
      find
          .descendant(
            of: find.byType(ToolsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await klick(tester, eintrag);
    await waitFor(tester, find.byType(OrtsvorschlaegeScreen));
    await waitGone(
      tester,
      find.descendant(
        of: find.byType(OrtsvorschlaegeScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
  }

  testWidgets(
    'ORT-072 ORT-074 ORT-077 ORT-079 Orte von Nachbarn ansehen, übernehmen, '
    'von Hand ersetzen',
    (tester) async {
      await starte(tester, geodaten: true);
      final tag = DateTime(2024, 5, 4);
      await importiereDirekt(tester, nachbarnTag('t', tag, hamburg));

      // ORT-072
      await bereich(tester, Hauptbereich.werkzeuge);
      await waitFor(tester, find.byType(ToolsScreen));
      final eintrag = find.ancestor(
        of: find.text(de.ortVorschlagWerkzTitel),
        matching: find.byType(ListTile),
      );
      await sichtbarIn(
        tester,
        eintrag,
        find
            .descendant(
              of: find.byType(ToolsScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await waitFor(
        tester,
        find.descendant(of: eintrag, matching: find.byType(Badge)),
      );
      expect(
        find.descendant(
          of: eintrag,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                RegExp(r'^Alle \d+ übernehmen$').hasMatch(w.data ?? ''),
          ),
        ),
        findsOneWidget,
      );
      await nachbarnOeffnen(tester);
      expect(find.text(de.ortVorschlagErklaerung), findsOneWidget);
      expect(
        find.textContaining(
          '${DateFormat.yMMMMd('de').format(tag)} · ${de.ortVorschlagAnzahl(3)}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('2 verortete Nachbarn, höchstens'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(OrtsvorschlaegeScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
        findsNWidgets(3),
      );
      expect(find.text(de.allgVerwerfen), findsOneWidget);
      expect(find.text(de.allgUebernehmen), findsOneWidget);
      expect(
        find.text(de.ortVorschlagAlleUebernehmen(1)),
        findsNothing,
        reason: 'bei nur einem Bündel kein „Alle übernehmen“',
      );
      await zurueck(tester);

      // ORT-079
      await bereich(tester, Hauptbereich.werkzeuge);
      await klick(
        tester,
        find.descendant(
          of: find.byType(ToolsScreen),
          matching: find.text(de.gesundheitTitel),
        ),
      );
      await waitFor(tester, find.byType(LibraryHealthScreen));
      await waitGone(
        tester,
        find.descendant(
          of: find.byType(LibraryHealthScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        timeout: const Duration(seconds: 60),
      );
      await sichtbarIn(
        tester,
        find.text(de.gesundheitOrteTitel),
        find
            .descendant(
              of: find.byType(LibraryHealthScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final karte = find
          .ancestor(
            of: find.text(de.gesundheitOrteTitel),
            matching: typ('_StatusCard'),
          )
          .first;
      expect(textIn(karte, de.gesundheitOrteOffen(3)), findsOneWidget);
      await klick(tester, textIn(karte, de.gesundheitOrteAnsehen));
      await waitFor(tester, find.byType(OrtsvorschlaegeScreen));
      await waitFor(tester, find.text(de.allgUebernehmen));

      // ORT-074
      await klick(tester, find.text(de.allgUebernehmen));
      await waitFor(tester, find.text(de.ortVorschlagKeine));
      final geerbt = (await alle(
        tester,
      )).where((a) => a.originalFileName.contains('_o')).toList();
      expect(geerbt, hasLength(3));
      for (final a in geerbt) {
        expect(a.latitude, closeTo(hamburg.$1, 0.01));
        expect(a.ortGeerbt, isTrue);
        expect(a.locationCity, isNotNull);
      }
      final o2 = geerbt.firstWhere((a) => a.originalFileName == 't_o2.jpg');
      await oeffneInZeitleiste(tester, o2.id);
      await info(tester);
      expect(textIn(infoBereich, de.infoOrtGeerbt), findsOneWidget);
      expect(
        find.descendant(
          of: infoBereich,
          matching: find.byIcon(Icons.share_location_outlined),
        ),
        findsOneWidget,
      );

      // ORT-077
      await setzeOrtPerKlick(tester, bremen, karte: infoKarteFlutter);
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(o2.id))?.ortGeerbt == false,
      );
      await settle(tester);
      expect(textIn(infoBereich, de.infoOrtGeerbt), findsNothing);
      await viewerZu(tester);
      await finish(tester);
    },
  );

  testWidgets('ORT-073 Kein Vorschlag bei uneinigen oder fernen Nachbarn', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    final tag = DateTime(2024, 5, 4);
    await importiereDirekt(tester, [
      fotoBei('v1.jpg', hamburg, tag.add(const Duration(hours: 10))),
      testfoto('o1.jpg', datum: tag.add(const Duration(hours: 11))),
      fotoBei('v2.jpg', berlin, tag.add(const Duration(hours: 12))),
      testfoto('allein.jpg', datum: DateTime(2024, 6, 20, 15)),
    ]);
    await nachbarnOeffnen(tester);
    expect(find.text(de.ortVorschlagKeine), findsOneWidget);
    await finish(tester);
  });

  testWidgets('ORT-075 Verworfenes Bündel bleibt verworfen', (tester) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(
      tester,
      nachbarnTag('t', DateTime(2024, 5, 4), hamburg),
    );
    await nachbarnOeffnen(tester);
    await klick(tester, find.text(de.allgVerwerfen));
    await waitFor(tester, find.text(de.ortVorschlagKeine));
    await zurueck(tester);
    await nachbarnOeffnen(tester);
    expect(find.text(de.ortVorschlagKeine), findsOneWidget);
    await neuStart(tester);
    await nachbarnOeffnen(tester);
    expect(find.text(de.ortVorschlagKeine), findsOneWidget);
    for (final a in await alle(tester)) {
      if (a.originalFileName.contains('_o')) expect(a.latitude, isNull);
    }
    await finish(tester);
  });

  Finder alleUebernehmen(int n) => find.text(de.ortVorschlagAlleUebernehmen(n));

  testWidgets('ORT-076 Alle Vorschläge übernehmen mit Rückfrage', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      ...nachbarnTag('t', DateTime(2024, 5, 4), hamburg),
      ...nachbarnTag('u', DateTime(2024, 6, 8), muenchen),
    ]);
    await nachbarnOeffnen(tester);
    await klick(tester, alleUebernehmen(2));
    await waitFor(tester, find.text(de.ortVorschlagAlleFrageTitel));
    expect(textIn(dialogFeld, de.ortVorschlagAlleFrage(2, 6)), findsOneWidget);
    await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
    for (final a in await alle(tester)) {
      if (a.originalFileName.contains('_o')) expect(a.latitude, isNull);
    }
    expect(alleUebernehmen(2), findsOneWidget);
    await klick(tester, alleUebernehmen(2));
    await waitFor(tester, dialogFeld);
    await tester.tap(
      find.descendant(of: dialogFeld, matching: find.byType(FilledButton)),
    );
    await tester.pump();
    await waitFor(tester, find.text(de.ortVorschlagKeine));
    for (final a in await alle(tester)) {
      if (a.originalFileName.contains('_o')) {
        expect(a.latitude, isNotNull, reason: a.originalFileName);
        expect(a.ortGeerbt, isTrue);
      }
    }
    await finish(tester);
  });

  // Behoben in #413: Die Rückfrage gibt confirmDialog die Beschriftung
  // „Übernehmen“ mit.
  testWidgets('ORT-076 Bestätigungsknopf heisst nicht „Löschen“', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      ...nachbarnTag('t', DateTime(2024, 5, 4), hamburg),
      ...nachbarnTag('u', DateTime(2024, 6, 8), muenchen),
    ]);
    await nachbarnOeffnen(tester);
    await klick(tester, alleUebernehmen(2));
    await waitFor(tester, dialogFeld);
    final ja = tester.widget<Text>(
      find.descendant(
        of: find.descendant(
          of: dialogFeld,
          matching: find.byType(FilledButton),
        ),
        matching: find.byType(Text),
      ),
    );
    expect(
      ja.data,
      isNot(de.allgLoeschen),
      reason: 'Übernehmen wird mit einem roten „Löschen“-Knopf bestätigt',
    );
    await finish(tester);
  });

  // =========================================================================
  // GPX
  // =========================================================================

  testWidgets(
    'ORT-080 ORT-085 ORT-087 GPX: Bildschirm, falsche Dateien, schon verortet',
    (tester) async {
      await starte(tester);
      await importiereDirekt(tester, [
        fotoBei('verortet.jpg', muenchen, spurzeit(9, 30)),
      ]);
      final merkend = MerkenderDialog();
      FilePickerPlatform.instance = merkend;
      addTearDown(() => FilePickerPlatform.instance = dialog);

      // ORT-080
      await gpxOeffnen(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(de.gpxTitel),
        ),
        findsOneWidget,
      );
      expect(find.text(de.gpxErklaerung), findsOneWidget);
      merkend.dateien = [];
      await klick(tester, find.text(de.gpxDateiWaehlen));
      expect(merkend.typ, FileType.custom);
      expect(merkend.endungen, ['gpx']);
      expect(find.textContaining(' Punkte · '), findsNothing);
      expect(find.text(de.gpxFehlerKeinGpx), findsNothing);

      // ORT-085
      final anders = File(p.join(eingang.path, 'anders.gpx'))
        ..writeAsStringSync(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<kml xmlns="http://www.opengis.net/kml/2.2"><Document/></kml>',
        );
      final leer = File(p.join(eingang.path, 'leer.gpx'))
        ..writeAsStringSync(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<gpx version="1.1" creator="pruefung" '
          'xmlns="http://www.topografix.com/GPX/1/1">'
          '<trk><name>leer</name><trkseg></trkseg></trk></gpx>',
        );
      final fehlerfarbe = Theme.of(
        tester.element(find.byType(GpxVerortungScreen)),
      ).colorScheme.error;
      merkend.dateien = [anders];
      await klick(tester, find.text(de.gpxDateiWaehlen));
      await waitFor(tester, find.text(de.gpxFehlerKeinGpx));
      expect(
        tester.widget<Text>(find.text(de.gpxFehlerKeinGpx)).style?.color,
        fehlerfarbe,
      );
      expect(knopfAktiv(tester, knopf(de.gpxDateiWaehlen)), isTrue);
      merkend.dateien = [leer];
      await klick(tester, find.text(de.gpxDateiWaehlen));
      await waitFor(tester, find.text(de.gpxFehlerLeer));
      expect(
        tester.widget<Text>(find.text(de.gpxFehlerLeer)).style?.color,
        fehlerfarbe,
      );
      expect(knopfAktiv(tester, knopf(de.gpxDateiWaehlen)), isTrue);

      // ORT-087
      merkend.dateien = [fixture('strecke.gpx')];
      await klick(tester, find.text(de.gpxDateiWaehlen));
      await waitFor(tester, find.text(de.gpxKeineKandidaten));
      expect(find.text(de.gpxVerorten), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'ORT-083 ORT-088 GPX verortet nur Fotos ohne Ort, nicht gesperrte oder '
    'gelöschte',
    (tester) async {
      await starte(tester, geodaten: true);
      await importiereDirekt(tester, [
        testfoto('o1.jpg', datum: spurzeit(7, 57)),
        testfoto('o2.jpg', datum: spurzeit(9, 0)),
        testfoto('o3.jpg', datum: spurzeit(11, 4)),
        fotoBei('verortet.jpg', muenchen, spurzeit(9, 30)),
        testfoto('gesperrt.jpg', datum: spurzeit(10, 0)),
        testfoto('geloescht.jpg', datum: spurzeit(8, 0)),
      ]);
      final gesperrt = await aufnahme(tester, 'gesperrt.jpg');
      final geloescht = await aufnahme(tester, 'geloescht.jpg');
      await sperren(tester, gesperrt);
      await inPapierkorb(tester, geloescht.id);

      await gpxOeffnen(tester);
      await gpxWaehlen(tester, fixture('strecke.gpx'));
      await waitFor(tester, find.textContaining('4 Punkte · '));
      final trefferText = [
        for (final e in find.textContaining(' einen Ort.').evaluate())
          (e.widget as Text).data,
      ];
      print('ORT-088 Trefferzeile: $trefferText');
      expect(find.text(de.gpxTreffer(3)), findsOneWidget, reason: 'ORT-088');
      await klick(tester, find.text(de.gpxVerorten));
      await meldung(tester, de.gpxFertig(3));
      await waitFor(tester, find.text(de.gpxKeineKandidaten));
      for (final n in ['o1.jpg', 'o2.jpg', 'o3.jpg']) {
        final a = await aufnahme(tester, n);
        expect(a.latitude, inInclusiveRange(47.41, 47.44), reason: n);
        expect(a.longitude, inInclusiveRange(10.98, 11.01), reason: n);
        expect(a.locationCity, isNotNull, reason: n);
      }
      final verortet = await aufnahme(tester, 'verortet.jpg');
      expect(verortet.latitude, closeTo(muenchen.$1, 0.001));

      // ORT-088: zurückholen, weiterhin ohne Ort.
      await tester.runAsync(() async {
        await bibliothek.unlockAsset(
          (await bibliothek.db.assetById(gesperrt.id))!,
        );
        await bibliothek.db.fuehreAus(AusDemPapierkorb([geloescht.id]));
      });
      final g = (await bibliothek.db.assetById(gesperrt.id))!;
      final l = (await bibliothek.db.assetById(geloescht.id))!;
      expect(g.isLocked, isFalse);
      expect(l.isTrashed, isFalse);
      expect(g.latitude, isNull);
      expect(l.latitude, isNull);
      await finish(tester);
    },
  );

  // =========================================================================
  // Länderliste und Ortsansicht
  // =========================================================================

  /// Ein Land mit zwei bis fünf Regionen, deren jede einen Ort im Datensatz
  /// hat – für „alle Regionen belegt“.
  ({String iso, List<Ort> orte}) landMitWenigenRegionen() {
    for (final l in geo.laenderkatalog.laender) {
      if (l.iso == 'DE' || l.regionen < 2 || l.regionen > 5) continue;
      final regionen = geo.regionenVon(l.iso);
      if (regionen.length != l.regionen) continue;
      final orte = <Ort>[];
      for (final r in regionen) {
        final punkt = geo.regionspunkt(r.schluessel);
        if (punkt == null) break;
        orte.add((punkt.breite, punkt.laenge));
      }
      if (orte.length == regionen.length) return (iso: l.iso, orte: orte);
    }
    throw StateError('Kein passendes Land im Datensatz');
  }

  Future<void> laenderlisteOeffnen(WidgetTester tester) async {
    await bereich(tester, Hauptbereich.orte);
    await waitFor(tester, find.byType(LaenderlisteScreen));
    await waitFor(tester, find.textContaining(' Länder · '));
  }

  testWidgets(
    'ORT-089 ORT-093 ORT-094 Länderliste: Kopf, Besuchsgrad, Handmarke',
    (tester) async {
      await starte(tester, geodaten: true);
      final landA = landMitWenigenRegionen();
      await importiereDirekt(tester, [
        for (final (i, o) in landA.orte.indexed)
          fotoBei('a$i.jpg', o, DateTime(2024, 3, 1 + i, 10)),
        fotoBei('de1.jpg', hamburg, DateTime(2024, 4, 1, 10)),
      ]);
      final gesamt = geo.laenderkatalog.laender.length;
      final nRegionen = landA.orte.length;
      final deRegionen = geo.regionenVon('DE').length;
      print('ORT-093 Land A: ${landA.iso} mit $nRegionen Regionen');

      // ORT-089
      await laenderlisteOeffnen(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(de.laenderTitel),
        ),
        findsWidgets,
      );
      expect(find.text(de.laenderKopf(gesamt, 2, 1)), findsOneWidget);
      for (final t in [
        de.laenderBesucht,
        de.laenderVollstaendig,
        de.laenderTeilweise,
        de.laenderVerbleibend,
        de.laenderLegende,
      ]) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text(de.fortschrittHinweis(gesamt)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      await laenderSuchen(tester, landname('IS'));
      expect(
        landzeile(landname('IS')),
        findsOneWidget,
        reason: 'auch unbesuchte',
      );
      expect(
        find.descendant(
          of: landzeile(landname('IS')),
          matching: find.byTooltip(de.laenderNichtBesucht),
        ),
        findsOneWidget,
      );

      // ORT-093
      await laenderSuchen(tester, landname(landA.iso));
      final zeileA = landzeile(landname(landA.iso));
      expect(
        find.descendant(
          of: zeileA,
          matching: find.byTooltip(de.laenderVollstaendig),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: zeileA,
          matching: find.byTooltip(de.laenderAusFotos),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: zeileA,
          matching: find.byTooltip(de.laenderRegionen(nRegionen, nRegionen)),
        ),
        findsOneWidget,
      );
      expect(textIn(zeileA, '$nRegionen/$nRegionen'), findsOneWidget);
      final eintragA = geo.laenderkatalog.nachIso(landA.iso)!;
      final unterA = unterzeile(tester, zeileA);
      expect(unterA, contains(de.laenderAufnahmen(nRegionen)));
      if (eintragA.hauptstadt != null) {
        expect(unterA, contains(eintragA.hauptstadt!));
      }
      await laenderSuchen(tester, landname('DE'));
      final zeileDe = landzeile(landname('DE'));
      expect(
        find.descendant(
          of: zeileDe,
          matching: find.byTooltip(de.laenderTeilweise),
        ),
        findsOneWidget,
      );
      expect(textIn(zeileDe, '1/$deRegionen'), findsOneWidget);
      expect(
        find.descendant(
          of: zeileDe,
          matching: find.byTooltip(de.laenderRegionen(1, deRegionen)),
        ),
        findsOneWidget,
      );
      final ohneRegionen = geo.laenderkatalog.laender.firstWhere(
        (l) => l.regionen == 0,
      );
      await laenderSuchen(tester, ohneRegionen.anzeige('de'));
      expect(
        unterzeile(tester, landzeile(ohneRegionen.anzeige('de'))),
        contains(de.laenderOhneRegionen),
      );

      // ORT-094
      await laenderSuchen(tester, landname('IS'));
      await meldungenWeg(tester);
      final zeileIsland = landzeile(landname('IS')).first;
      final druck = await tester.startGesture(
        tester.getCenter(zeileIsland),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 900));
      await druck.up();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      if (find.text(de.laenderHinweisMarke).evaluate().isEmpty) {
        final treffer = tester.hitTestOnBinding(tester.getCenter(zeileIsland));
        print(
          'ORT-094 langer Druck ohne Blatt; Ziele: '
          '${treffer.path.take(6).map((e) => e.target.runtimeType).toList()}',
        );
        tester.widget<ListTile>(zeileIsland).onLongPress!();
        await tester.pump(const Duration(milliseconds: 500));
        await settle(tester);
      }
      await waitFor(
        tester,
        find.text(de.laenderHinweisMarke),
        timeout: const Duration(seconds: 5),
      );
      expect(
        find.ancestor(
          of: find.text(de.laenderHinweisMarke),
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
      );
      await klick(tester, find.text(de.laenderMarkeBesucht));
      await settle(tester);
      final zeileIs = landzeile(landname('IS'));
      expect(
        find.descendant(
          of: zeileIs,
          matching: find.byTooltip(de.laenderNurVonHand),
        ),
        findsOneWidget,
      );
      expect(unterzeile(tester, zeileIs), contains(de.laenderVonHand));
      final kopfNachMarke = find.textContaining(' Länder · 3 besucht · ');
      expect(
        kopfNachMarke,
        findsOneWidget,
        reason: 'zählt im Kopf als besucht',
      );
      print('ORT-094 Kopf: ${textVon(tester, kopfNachMarke)}');
      await klick(tester, zeileIs);
      await waitFor(tester, find.byType(OrtsansichtScreen));
      expect(
        find.descendant(
          of: find.byType(OrtsansichtScreen),
          matching: find.text(landname('IS')),
        ),
        findsWidgets,
      );
      await finish(tester);
    },
  );

  // Behoben in #413: besuchteOrte zählt dieselbe Menge wie die Karte (_mitOrt,
  // nur Haupteinträge); die Videohälfte eines Live Photos zählt nicht mehr
  // mit.
  testWidgets('ORT-093 Live Photo zählt in der Länderliste einmal', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    final foto = fotoBei('IMG_0001.jpg', hamburg, DateTime(2024, 3, 1, 10));
    final video = fixture('video_hoch_3s.mov')
      ..renameSync(p.join(eingang.path, 'IMG_0001.mov'));
    await importiereDirekt(tester, [
      foto,
      File(p.join(eingang.path, 'IMG_0001.mov')),
    ]);
    var bild = await aufnahme(tester, 'IMG_0001.jpg');
    var film = await aufnahme(tester, 'IMG_0001.mov');
    if (bild.linkedAssetId != film.id) {
      await tester.runAsync(() => bibliothek.db.linkAssets(bild.id, film.id));
    }
    // Wie bei einem iPhone: auch die Videohälfte trägt den Ort.
    await sql(
      tester,
      'UPDATE assets SET latitude = ?, longitude = ?, location_country = ?, '
      'location_state = ?, location_city = ? WHERE id = ?',
      [
        bild.latitude,
        bild.longitude,
        bild.locationCountry,
        bild.locationState,
        bild.locationCity,
        film.id,
      ],
    );
    bild = await aufnahme(tester, 'IMG_0001.jpg');
    film = await aufnahme(tester, 'IMG_0001.mov');
    expect(bild.linkedAssetId, film.id);
    expect(
      await db(tester, () => bibliothek.db.assetsWithLocation()),
      hasLength(1),
      reason: 'auf der Karte ein Eintrag',
    );
    expect(video.path, isNotEmpty);
    await laenderlisteOeffnen(tester);
    await laenderSuchen(tester, landname('DE'));
    final unter = unterzeile(tester, landzeile(landname('DE')));
    print('ORT-093 Live Photo: $unter');
    expect(unter, contains(de.laenderAufnahmen(1)));
    await finish(tester);
  });

  testWidgets('ORT-098 Gesperrte und gelöschte Fotos zählen nicht als Besuch', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('frei.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('gesperrt.jpg', paris, DateTime(2024, 3, 2, 10)),
      fotoBei('geloescht.jpg', madrid, DateTime(2024, 3, 3, 10)),
    ]);
    await sperren(tester, await aufnahme(tester, 'gesperrt.jpg'));
    await inPapierkorb(tester, (await aufnahme(tester, 'geloescht.jpg')).id);
    final gesamt = geo.laenderkatalog.laender.length;
    await laenderlisteOeffnen(tester);
    expect(find.text(de.laenderKopf(gesamt, 1, 1)), findsOneWidget);
    for (final iso in ['FR', 'ES']) {
      await laenderSuchen(tester, landname(iso));
      final zeile = landzeile(landname(iso));
      await waitFor(tester, zeile);
      final hinweise = [
        for (final e
            in find
                .descendant(of: zeile, matching: find.byType(Tooltip))
                .evaluate())
          (e.widget as Tooltip).message,
      ];
      print('ORT-098 $iso: ${unterzeile(tester, zeile)} · $hinweise');
      expect(hinweise, contains(de.laenderNichtBesucht), reason: iso);
      expect(unterzeile(tester, zeile), isNot(contains('Aufnahme')));
      await klick(tester, zeile);
      await waitFor(tester, find.byType(OrtsansichtScreen));
      await waitGone(
        tester,
        find.descendant(
          of: find.byType(OrtsansichtScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(OrtsansichtScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
        findsNothing,
        reason: 'keine Fotos in $iso',
      );
      await zurueck(tester);
      await waitGone(tester, find.byType(OrtsansichtScreen));
    }
    await finish(tester);
  });

  Future<void> deutschlandOeffnen(WidgetTester tester) async {
    await laenderlisteOeffnen(tester);
    await laenderSuchen(tester, landname('DE'));
    await klick(tester, landzeile(landname('DE')));
    await waitFor(tester, find.byType(OrtsansichtScreen));
    await waitGone(
      tester,
      find.descendant(
        of: find.byType(OrtsansichtScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
  }

  Finder ortsansicht() => find.byType(OrtsansichtScreen);

  testWidgets('ORT-099 ORT-100 ORT-103 Ortsansicht: Land, Region, Ort, Foto', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('h1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('h2.jpg', hamburg, DateTime(2024, 3, 2, 10), dBreite: 0.001),
      fotoBei('m1.jpg', muenchen, DateTime(2024, 3, 3, 10)),
      fotoBei('m2.jpg', muenchen, DateTime(2024, 3, 4, 10), dBreite: 0.001),
      fotoBei('n1.jpg', nuernberg, DateTime(2024, 3, 5, 10)),
    ]);
    final m1 = await aufnahme(tester, 'm1.jpg');
    final h1 = await aufnahme(tester, 'h1.jpg');
    final n1 = await aufnahme(tester, 'n1.jpg');
    expect(n1.locationState, m1.locationState, reason: 'beide in Bayern');
    final deRegionen = geo.regionenVon('DE').length;
    final hauptstadt = geo.laenderkatalog.nachIso('DE')!.hauptstadt!;

    // ORT-099
    await deutschlandOeffnen(tester);
    expect(textIn(ortsansicht(), '🇩🇪'), findsOneWidget);
    expect(
      textIn(ortsansicht(), '$hauptstadt · ${de.laenderAufnahmen(5)}'),
      findsOneWidget,
    );
    expect(textIn(ortsansicht(), '2/$deRegionen'), findsOneWidget);
    expect(
      find.descendant(
        of: ortsansicht(),
        matching: find.widgetWithText(ChoiceChip, de.laenderBesucht),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: ortsansicht(),
        matching: find.widgetWithText(ChoiceChip, de.laenderGeplant),
      ),
      findsOneWidget,
    );
    expect(
      textIn(ortsansicht(), de.ortRegionen(2, deRegionen)),
      findsOneWidget,
    );
    final zeilen = find.descendant(
      of: ortsansicht(),
      matching: typ('_Unterortzeile'),
    );
    final erste = [
      for (final e in zeilen.evaluate().take(2))
        ((find
                    .descendant(
                      of: find.byElementPredicate((x) => identical(x, e)),
                      matching: find.byType(Text),
                    )
                    .evaluate()
                    .first
                    .widget)
                as Text)
            .data,
    ];
    expect(erste, [
      m1.locationState,
      h1.locationState,
    ], reason: 'besuchte zuerst');
    final liste = find
        .descendant(of: ortsansicht(), matching: find.byType(Scrollable))
        .first;
    await sichtbarIn(tester, textIn(ortsansicht(), de.ortFotos(5)), liste);
    expect(textIn(ortsansicht(), de.ortFotos(5)), findsOneWidget);
    await tester.drag(liste, const Offset(0, 3000));
    await settle(tester);

    // ORT-100
    await klick(tester, textIn(ortsansicht(), m1.locationState!));
    await waitFor(tester, find.byType(OrtsansichtScreen));
    await waitGone(
      tester,
      find.descendant(
        of: ortsansicht(),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(m1.locationState!),
      ),
      findsWidgets,
    );
    expect(textEnthaeltIn(ortsansicht(), 'Orte · 2 von '), findsOneWidget);
    final liste2 = find
        .descendant(of: ortsansicht(), matching: find.byType(Scrollable))
        .first;
    await sichtbarIn(tester, textIn(ortsansicht(), de.ortFotos(3)), liste2);
    expect(textIn(ortsansicht(), de.ortFotos(3)), findsOneWidget);
    await tester.drag(liste2, const Offset(0, 3000));
    await settle(tester);
    final orte = [
      for (final e
          in find
              .descendant(of: ortsansicht(), matching: typ('_Unterortzeile'))
              .evaluate()
              .take(4))
        ((find
                    .descendant(
                      of: find.byElementPredicate((x) => identical(x, e)),
                      matching: find.byType(Text),
                    )
                    .evaluate()
                    .first
                    .widget)
                as Text)
            .data,
    ];
    print(
      'ORT-100 erste Orte der Region: $orte, Fotos in ${m1.locationCity}, '
      '${n1.locationCity}',
    );
    await sichtbarIn(tester, textIn(ortsansicht(), m1.locationCity!), liste2);
    await klick(tester, textIn(ortsansicht(), m1.locationCity!));
    await waitGone(
      tester,
      find.descendant(
        of: ortsansicht(),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    await waitFor(tester, textIn(ortsansicht(), de.ortFotos(2)));
    expect(textEnthaeltIn(ortsansicht(), 'Orte · '), findsNothing);
    expect(textEnthaeltIn(ortsansicht(), 'Regionen · '), findsNothing);

    // ORT-103
    final fotos = find.descendant(
      of: ortsansicht(),
      matching: find.byType(AssetThumbnailTile),
    );
    expect(fotos, findsNWidgets(2));
    await klick(tester, fotos);
    await waitFor(tester, vollansicht);
    expect(viewer(tester).assets.map((a) => a.originalFileName).toSet(), {
      'm1.jpg',
      'm2.jpg',
    });
    final erlaubt = {
      titelDatum(DateTime(2024, 3, 3)),
      titelDatum(DateTime(2024, 3, 4)),
    };
    final gesehen = <String>{viewerTitel(tester)};
    await pfeil(tester, LogicalKeyboardKey.arrowRight);
    gesehen.add(viewerTitel(tester));
    await pfeil(tester, LogicalKeyboardKey.arrowRight);
    gesehen.add(viewerTitel(tester));
    expect(gesehen, erlaubt);
    await klick(tester, find.byTooltip(de.viewerInPapierkorb));
    await waitFor(tester, dialogFeld);
    await klick(
      tester,
      find.descendant(of: dialogFeld, matching: find.byType(FilledButton)),
    );
    await waitGone(tester, vollansicht);
    await waitFor(tester, textIn(ortsansicht(), de.ortFotos(1)));
    expect(fotos, findsOneWidget);
    await finish(tester);
  });

  // Hinweis zu ORT-101 (automatisch, nicht e2e): Im Kopf der Ortsansicht steht
  // „von Hand“ auch, wenn Fotos das Land belegen (ortsansicht_screen.dart:309,
  // `stand.marke == Markenart.besucht` statt „nur von Hand“). Zwei Läufe.
  testWidgets('ORT-101 Kopf der Ortsansicht: „von Hand“ trotz Fotos', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('h1.jpg', hamburg, DateTime(2024, 3, 1, 10)),
    ]);
    await deutschlandOeffnen(tester);
    await klick(
      tester,
      find.descendant(
        of: ortsansicht(),
        matching: find.widgetWithText(ChoiceChip, de.laenderBesucht),
      ),
    );
    await settle(tester);
    await tester.drag(
      find
          .descendant(of: ortsansicht(), matching: find.byType(Scrollable))
          .first,
      const Offset(0, 3000),
    );
    await settle(tester);
    final kopf = find.descendant(
      of: typ('_Kopf'),
      matching: find.textContaining(de.laenderAufnahmen(1)),
    );
    await waitFor(tester, kopf);
    final zeile = textVon(tester, kopf);
    print('ORT-101 Kopfzeile: $zeile');
    expect(zeile, isNot(contains(de.laenderVonHand)));
    await finish(tester);
  }, skip: true);

  // =========================================================================
  // Weltkarte
  // =========================================================================

  Future<void> weltkarteOeffnen(WidgetTester tester) async {
    await reisenOeffnen(tester);
    await klick(tester, find.byTooltip(de.weltkarteOeffnen));
    await waitFor(tester, find.byType(WeltkarteScreen));
    await waitFor(
      tester,
      find.byType(PolygonLayer),
      timeout: const Duration(seconds: 30),
    );
    await settle(tester);
  }

  testWidgets('ORT-105 ORT-114 Weltkarte öffnen, Legende', (tester) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('h.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      fotoBei('r.jpg', rom, DateTime(2024, 3, 2, 10)),
    ]);
    await weltkarteOeffnen(tester);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.weltkarteTitel),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons,
      isNotEmpty,
      reason: 'belegte Länder und Regionen ausgefüllt',
    );
    final marken = typ('_Marke');
    expect(marken.evaluate().length, greaterThanOrEqualTo(4));
    final leiste = typ('_Markierleiste');
    expect(textIn(leiste, de.weltkarteKlickMarkiert), findsOneWidget);
    for (final t in [
      de.weltkarteLaender,
      de.weltkarteRegionen,
      de.weltkarteOrte,
    ]) {
      expect(textIn(leiste, t), findsOneWidget);
    }
    expect(
      find.descendant(
        of: leiste,
        matching: find.widgetWithText(FilterChip, de.laenderGeplant),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip(de.karteHineinzoomen), findsOneWidget);
    expect(find.byTooltip(de.karteHerauszoomen), findsOneWidget);

    // ORT-114
    await klick(tester, find.byTooltip(de.weltkarteLegende));
    await waitFor(tester, dialogFeld);
    for (final t in [
      de.weltkarteLegende,
      de.weltkarteLegendeFotos,
      de.weltkarteLegendeHand,
      de.weltkarteLegendeGeplant,
      de.weltkarteOhneUmriss,
    ]) {
      expect(textIn(dialogFeld, t), findsOneWidget, reason: t);
    }
    final ml = MaterialLocalizations.of(tester.element(dialogFeld));
    await klick(tester, textIn(dialogFeld, ml.closeButtonLabel));
    expect(dialogFeld, findsNothing);
    await finish(tester);
  });

  // Befund ORT-112: Auf der Stufe „Orte“ passen die Schlüssel nicht
  // zusammen (weltkarte_screen.dart:210/231 „ISO|Ort“ gegen Z. 433
  // „Land|Region|Ort“, Vergleich Z. 322–341). Zwei Läufe.
  testWidgets(
    'ORT-112 Weltkarte: Ort markieren und mit zweitem Klick entfernen',
    (tester) async {
      await starte(tester, geodaten: true);
      await importiereDirekt(tester, [
        fotoBei('h.jpg', hamburg, DateTime(2024, 3, 1, 10)),
      ]);
      await weltkarteOeffnen(tester);
      // Die Punkte ausblenden, damit der Klick die Fläche trifft.
      for (final ebene in [
        de.weltkarteLaender,
        de.weltkarteRegionen,
        de.weltkarteOrte,
      ]) {
        await klick(tester, find.byTooltip(de.weltkarteEbenen));
        await klick(
          tester,
          find.descendant(
            of: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
            matching: find.text(ebene),
          ),
        );
      }
      expect(typ('_Marke'), findsNothing);
      await klick(tester, textIn(typ('_Markierleiste'), de.weltkarteOrte));

      Future<List<OrtsmarkenData>> ortsmarken() async => [
        for (final m in await db(tester, () => bibliothek.db.alleOrtsmarken()))
          if (m.art == 'ort') m,
      ];

      final befunde = <String>[];

      // Ein Ort mit Fotos bekommt keinen Haken von Hand.
      final h = await aufnahme(tester, 'h.jpg');
      await schwenke(tester, (h.latitude!, h.longitude!), zoom: 10);
      await stille(tester);
      await tippeAufKarte(tester, (h.latitude!, h.longitude!));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final belegtMeldung = melde.verlauf.isEmpty
          ? ''
          : melde.verlauf.first.text;
      print('ORT-112 Klick auf Ort mit Fotos: $belegtMeldung');
      if (belegtMeldung != de.weltkarteSchonBelegt(h.locationCity!)) {
        befunde.add('Ort mit Fotos: „$belegtMeldung“');
      }
      if ((await ortsmarken()).isNotEmpty) {
        befunde.add('Ort mit Fotos bekam eine Handmarke');
        for (final m in await ortsmarken()) {
          await db(
            tester,
            () =>
                bibliothek.db.fuehreAus(OrtsmarkeLoeschen('ort', m.schluessel)),
          );
        }
      }

      // Erster Klick markiert einen Ort ohne Fotos.
      await schwenke(tester, wien, zoom: 10);
      await stille(tester);
      await tippeAufKarte(tester, wien);
      await eventually(
        tester,
        () async => (await bibliothek.db.alleOrtsmarken()).isNotEmpty,
      );
      final marken = await ortsmarken();
      expect(marken, hasLength(1));
      final name = marken.single.name;
      await meldung(tester, de.weltkarteMarkeGesetzt(name));
      await stille(tester);

      // Zweiter Klick genau dorthin nimmt die Marke weg.
      await tippeAufKarte(tester, wien);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final zweite = melde.verlauf.isEmpty ? '' : melde.verlauf.first.text;
      final nachZweitem = await ortsmarken();
      print(
        'ORT-112 nach zweitem Klick: Marken ${nachZweitem.length}, Meldung $zweite',
      );
      if (nachZweitem.isNotEmpty ||
          zweite != de.weltkarteMarkeWeggenommen(name)) {
        befunde.add(
          'zweiter Klick: ${nachZweitem.length} Marke(n), Meldung „$zweite“',
        );
      }
      expect(befunde, isEmpty);
      await finish(tester);
    },
    skip: true,
  );

  // =========================================================================
  // Reisen
  // =========================================================================

  Finder vorschlagskarte(String text) =>
      find.ancestor(of: find.textContaining(text), matching: find.byType(Card));

  testWidgets(
    'ORT-117 ORT-118 ORT-126 Reise erkannt, bestätigt, benannt; Kopfzeile',
    (tester) async {
      await starte(tester, geodaten: true);
      await importiereDirekt(tester, [
        for (var i = 0; i < 10; i++)
          fotoBei(
            'heim$i.jpg',
            hamburg,
            DateTime(2024, 1 + i ~/ 2, 3 + i * 2, 12),
            dBreite: 0.001 * i,
          ),
        for (var i = 0; i < 7; i++)
          fotoBei(
            'rom$i.jpg',
            rom,
            DateTime(2024, 6, 10 + i, 12),
            dLaenge: 0.001 * i,
          ),
        for (var i = 0; i < 6; i++)
          fotoBei(
            'berlin$i.jpg',
            berlin,
            DateTime(2024, 7, 20, 9 + i),
            dBreite: 0.001 * i,
          ),
        for (var i = 0; i < 6; i++)
          fotoBei(
            'wien$i.jpg',
            wien,
            DateTime(2024, 9, 7, 10).add(Duration(hours: 6 * i)),
            dLaenge: 0.001 * i,
          ),
      ]);
      await bereich(tester, Hauptbereich.reisen);
      await waitFor(tester, find.byType(ReisenScreen));
      await waitGone(
        tester,
        find.text(de.reisenSuchtNoch),
        timeout: const Duration(seconds: 60),
      );
      await settle(tester);

      // ORT-117
      expect(find.text(de.reisenVorschlaege), findsOneWidget);
      final ja = find.widgetWithText(FilledButton, de.reisenIstEineReise);
      expect(
        ja,
        findsNWidgets(2),
        reason: 'Rom-Woche und Wien, kein Tagesausflug',
      );
      final datum = DateFormat.yMMMd('de');
      final romZeile =
          '${de.reisenSpanne(datum.format(DateTime(2024, 6, 10)), datum.format(DateTime(2024, 6, 16)))}'
          ' · ${de.reisenNaechte(6)} · ${de.reisenAufnahmen(7)}';
      expect(find.text(romZeile), findsOneWidget);
      final romKarte = vorschlagskarte(de.reisenNaechte(6)).first;
      expect(textIn(romKarte, de.reisenKeineReise), findsOneWidget);
      expect(
        find.textContaining(datum.format(DateTime(2024, 7, 20))),
        findsNothing,
      );

      // ORT-118
      await klick(tester, find.descendant(of: romKarte, matching: ja));
      await waitFor(tester, find.text(de.reisenBenennen));
      final namensfeld = find.descendant(
        of: dialogFeld,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(namensfeld).controller!.text, isNotEmpty);
      await eingeben(tester, namensfeld, 'Rom-Woche');
      await klick(tester, textIn(dialogFeld, de.allgUebernehmen));
      await waitFor(tester, reisekachel('Rom-Woche'));
      expect(find.text(de.reisenBestaetigte), findsOneWidget);
      expect(
        textIn(reisekachel('Rom-Woche'), de.reisenNaechte(6)),
        findsOneWidget,
      );
      expect(textIn(reisekachel('Rom-Woche'), '2024'), findsOneWidget);
      expect(ja, findsOneWidget, reason: 'der Rom-Vorschlag ist weg');
      final reisen = await db(tester, () => bibliothek.db.alleReisen());
      expect(reisen.single.name, 'Rom-Woche');
      expect(
        await db(
          tester,
          () => bibliothek.db.zuordnungenDerReise(reisen.single.id),
        ),
        hasLength(7),
      );

      final wienKarte = vorschlagskarte(de.reisenNaechte(1)).first;
      await klick(tester, find.descendant(of: wienKarte, matching: ja));
      await waitFor(tester, find.text(de.reisenBenennen));
      await eingeben(
        tester,
        find.descendant(of: dialogFeld, matching: find.byType(TextField)),
        '',
      );
      await klick(tester, textIn(dialogFeld, de.allgUebernehmen));
      await settle(tester);
      expect(await db(tester, () => bibliothek.db.alleReisen()), hasLength(1));
      await klick(
        tester,
        find.descendant(
          of: vorschlagskarte(de.reisenNaechte(1)).first,
          matching: ja,
        ),
      );
      await waitFor(tester, find.text(de.reisenBenennen));
      await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
      await settle(tester);
      expect(await db(tester, () => bibliothek.db.alleReisen()), hasLength(1));
      expect(ja, findsOneWidget);

      // ORT-126
      expect(find.textContaining(de.reisenAnzahl(1)), findsWidgets);
      expect(find.textContaining(de.reisenAufnahmen(7)), findsWidgets);
      for (final t in [
        de.reisenSelbstAnlegen,
        de.weltkarteOeffnen,
        de.laenderTitel,
        de.aktivitaetenOeffnen,
        de.reisenAktualisieren,
      ]) {
        expect(find.byTooltip(t), findsOneWidget, reason: t);
      }
      await tester.tap(find.byTooltip(de.reisenAktualisieren));
      var suchtGesehen = false;
      var knopfAus = false;
      for (var i = 0; i < 10 && !suchtGesehen; i++) {
        await tester.pump();
        suchtGesehen = find.text(de.reisenSuchtNoch).evaluate().isNotEmpty;
        knopfAus =
            tester
                .widget<IconButton>(
                  find
                      .ancestor(
                        of: find.byTooltip(de.reisenAktualisieren),
                        matching: find.byType(IconButton),
                      )
                      .first,
                )
                .onPressed ==
            null;
      }
      // Bei wenigen Fotos ist die Suche oft schon nach einem Bild fertig.
      print(
        'ORT-126 während der Suche: Text $suchtGesehen, Knopf aus $knopfAus',
      );
      if (suchtGesehen) expect(knopfAus, isTrue);
      await waitGone(
        tester,
        find.text(de.reisenSuchtNoch),
        timeout: const Duration(seconds: 60),
      );
      await finish(tester);
    },
  );

  DateTime tagVor(int n, [int stunde = 10, int minute = 0]) {
    final d = DateTime.now().subtract(Duration(days: n));
    return DateTime(d.year, d.month, d.day, stunde, minute);
  }

  Finder datumsknoepfe() => find.descendant(
    of: dialogFeld,
    matching: find.byWidgetPredicate((w) => w is OutlinedButton),
  );

  testWidgets('ORT-120 Reise von Hand anlegen', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('d1.jpg', datum: tagVor(6)),
      testfoto('d2.jpg', datum: tagVor(5)),
      testfoto('d3.jpg', datum: tagVor(4)),
      testfoto('d3spaet.jpg', datum: tagVor(4, 23, 30)),
      testfoto('davor.jpg', datum: tagVor(9)),
      testfoto('danach.jpg', datum: tagVor(2)),
    ]);
    await reisenOeffnen(tester);
    await klick(tester, find.byTooltip(de.reisenSelbstAnlegen));
    await waitFor(tester, dialogFeld);
    final uebernehmen = find.descendant(
      of: dialogFeld,
      matching: knopf(de.allgUebernehmen),
    );
    expect(knopfAktiv(tester, uebernehmen), isFalse, reason: 'ohne Namen');
    await waitFor(tester, textIn(dialogFeld, de.zeitraumFotos(0)));
    await eingeben(tester, field(de.zeitraumName), 'Kurzreise');
    expect(knopfAktiv(tester, uebernehmen), isTrue);
    final format = DateFormat.yMMMMd('de');
    await klick(tester, datumsknoepfe().at(0));
    await datumImDialog(tester, tagVor(4));
    await klick(tester, datumsknoepfe().at(1));
    await datumImDialog(tester, tagVor(6));
    // Das Ende vor dem Anfang: der Anfang wandert mit.
    expect(
      textIn(datumsknoepfe().at(0), format.format(tagVor(6))),
      findsOneWidget,
    );
    expect(
      textIn(datumsknoepfe().at(1), format.format(tagVor(6))),
      findsOneWidget,
    );
    await klick(tester, datumsknoepfe().at(1));
    await datumImDialog(tester, tagVor(4));
    await waitFor(tester, textIn(dialogFeld, de.zeitraumFotos(4)));
    await klick(tester, uebernehmen);
    await meldung(tester, de.reisenSelbstAngelegt('Kurzreise'));
    await waitFor(tester, reisekachel('Kurzreise'));
    final reise = (await db(tester, () => bibliothek.db.alleReisen())).single;
    final ids = await db(
      tester,
      () => bibliothek.db.zuordnungenDerReise(reise.id),
    );
    final namen = {
      for (final a in await alle(tester))
        if (ids.contains(a.id)) a.originalFileName,
    };
    expect(namen, {'d1.jpg', 'd2.jpg', 'd3.jpg', 'd3spaet.jpg'});
    await stille(tester);
    await klick(tester, reisekachel('Kurzreise'));
    await waitFor(tester, find.byType(ReiseDetailScreen));
    await waitFor(tester, find.textContaining(de.reisenAufnahmen(4)));
    await finish(tester);
  });

  testWidgets('ORT-121 ORT-123 ORT-124 Reise umbenennen, allein, entfernen', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('r1.jpg', datum: DateTime(2024, 4, 1, 10)),
      testfoto('r2.jpg', datum: DateTime(2024, 4, 2, 10)),
      testfoto('r3.jpg', datum: DateTime(2024, 4, 3, 10)),
    ]);
    final ids = [for (final a in await alle(tester)) a.id];
    final reiseId = await reiseAnlegen(
      tester,
      'Osterreise',
      DateTime(2024, 4, 1),
      DateTime(2024, 4, 3),
      ids,
    );
    await db(
      tester,
      () => bibliothek.db.fuehreAus(
        ReisetagnotizSetzen(reiseId, DateTime(2024, 4, 2), 'Notiz zum Tag'),
      ),
    );
    await aktivitaetAnlegen(
      tester,
      'Ostergang',
      DateTime(2024, 4, 2, 9),
      DateTime(2024, 4, 2, 12),
      [ids[1]],
      reiseId: reiseId,
    );
    await reisenOeffnen(tester);

    // ORT-123
    await kachelbefehl(
      tester,
      reisekachel('Osterreise'),
      de.reisenZusammenfuehren,
    );
    await meldung(tester, de.reisenZusammenfuehrenAllein);
    expect(dialogFeld, findsNothing);

    // ORT-121
    await kachelbefehl(tester, reisekachel('Osterreise'), de.reisenUmbenennen);
    await waitFor(tester, dialogFeld);
    final feld = find.descendant(
      of: dialogFeld,
      matching: find.byType(TextField),
    );
    await eingeben(tester, feld, 'Ostern 2024');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await waitFor(tester, reisekachel('Ostern 2024'));
    await kachelbefehl(tester, reisekachel('Ostern 2024'), de.reisenUmbenennen);
    await waitFor(tester, dialogFeld);
    await eingeben(tester, feld, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(
      reisekachel('Ostern 2024'),
      findsOneWidget,
      reason: 'leer bleibt alt',
    );

    // ORT-124
    await kachelbefehl(tester, reisekachel('Ostern 2024'), de.reisenLoeschen);
    await waitFor(
      tester,
      textIn(dialogFeld, de.reisenLoeschenFrage('Ostern 2024')),
    );
    await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
    expect(reisekachel('Ostern 2024'), findsOneWidget);
    await kachelbefehl(tester, reisekachel('Ostern 2024'), de.reisenLoeschen);
    await waitFor(tester, dialogFeld);
    await klick(tester, textIn(dialogFeld, de.allgEntfernen));
    await waitGone(tester, reisekachel('Ostern 2024'));
    expect(await db(tester, () => bibliothek.db.alleReisen()), isEmpty);
    expect(
      await db(
        tester,
        () => bibliothek.db.select(bibliothek.db.reisetagnotizen).get(),
      ),
      isEmpty,
    );
    final nachher = await alle(tester);
    expect(nachher, hasLength(3));
    expect(
      nachher.where((a) => a.isTrashed),
      isEmpty,
      reason: 'nichts im Papierkorb',
    );
    final akt = await db(tester, () => bibliothek.db.alleAktivitaeten());
    expect(akt.single.name, 'Ostergang');
    expect(akt.single.reiseId, isNull);
    await bereich(tester, Hauptbereich.zeitleiste);
    await settle(tester);
    for (final id in ids) {
      expect(kachel(id), findsOneWidget);
    }
    await aktivitaetenOeffnen(tester);
    expect(find.text(de.aktivitaetenOhneReise), findsOneWidget);
    expect(aktivitaetskachel('Ostergang'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('ORT-122 Reisen zusammenführen', (tester) async {
    await starte(tester);
    await importiereDirekt(tester, [
      // Mit Ort: Eine Reise mit Spur, aber ohne verortetes Foto bringt die
      // Routenkarte zum Absturz (eigene Prüfung unten).
      fotoBei('r1a.jpg', hamburg, DateTime(2024, 4, 1, 10)),
      fotoBei('r1b.jpg', bremen, DateTime(2024, 4, 2, 10)),
      fotoBei('beide.jpg', bremen, DateTime(2024, 4, 3, 10), dBreite: 0.001),
      fotoBei('r2a.jpg', muenchen, DateTime(2024, 4, 5, 10)),
      fotoBei('r2b.jpg', nuernberg, DateTime(2024, 4, 6, 10)),
    ]);
    final id = {for (final a in await alle(tester)) a.originalFileName: a.id};
    final r1 = await reiseAnlegen(
      tester,
      'R1',
      DateTime(2024, 4, 1),
      DateTime(2024, 4, 3),
      [id['r1a.jpg']!, id['r1b.jpg']!, id['beide.jpg']!],
    );
    final r2 = await reiseAnlegen(
      tester,
      'R2',
      DateTime(2024, 4, 3),
      DateTime(2024, 4, 6),
      [id['beide.jpg']!, id['r2a.jpg']!, id['r2b.jpg']!],
    );
    await tester.runAsync(() async {
      await bibliothek.db.fuehreAus(
        ReisetagnotizSetzen(r1, DateTime(2024, 4, 5), 'Notiz R1'),
      );
      await bibliothek.db.fuehreAus(
        ReisetagnotizSetzen(r2, DateTime(2024, 4, 5), 'Notiz R2'),
      );
      await bibliothek.db.fuehreAus(
        ReisetagnotizSetzen(r2, DateTime(2024, 4, 6), 'Nur R2'),
      );
    });
    await aktivitaetAnlegen(
      tester,
      'Gang R2',
      DateTime(2024, 4, 5, 9),
      DateTime(2024, 4, 5, 12),
      [id['r2a.jpg']!],
      reiseId: r2,
    );
    // Die GPX-Spur über die Oberfläche an R2.
    await reisenOeffnen(tester);
    await klick(tester, reisekachel('R2'));
    await waitFor(tester, find.byTooltip(de.spurHinzufuegen));
    dialog.dateien = [fixture('strecke.gpx')];
    await klick(tester, find.byTooltip(de.spurHinzufuegen));
    await eventually(
      tester,
      () async => (await bibliothek.db.spurenDerReise(r2)).isNotEmpty,
    );
    await zurueck(tester);
    await waitFor(tester, reisekachel('R1'));

    await kachelbefehl(tester, reisekachel('R1'), de.reisenZusammenfuehren);
    await waitFor(tester, find.text(de.reisenZusammenfuehrenTitel('R1')));
    final los = find.descendant(
      of: dialogFeld,
      matching: find.widgetWithText(FilledButton, de.reisenZusammenfuehren),
    );
    expect(knopfAktiv(tester, los), isFalse, reason: 'erst nach einer Auswahl');
    await klick(tester, find.widgetWithText(CheckboxListTile, 'R2'));
    expect(knopfAktiv(tester, los), isTrue);
    await klick(tester, los);
    await meldung(tester, de.reisenZusammengefuehrt('R1', 1));
    await waitGone(tester, reisekachel('R2'));
    final reisen = await db(tester, () => bibliothek.db.alleReisen());
    expect(reisen.map((r) => r.name), ['R1']);
    final ziel = reisen.single;
    expect(ziel.von.isAfter(DateTime(2024, 4, 1, 23)), isFalse);
    expect(
      ziel.bis.isBefore(DateTime(2024, 4, 6)),
      isFalse,
      reason: 'Zeitraum wächst',
    );
    final zuordnung = await db(
      tester,
      () => bibliothek.db.zuordnungenDerReise(r1),
    );
    expect(zuordnung, id.values.toSet(), reason: 'alle fünf, „beide“ einmal');
    final akt = await db(tester, () => bibliothek.db.alleAktivitaeten());
    expect(akt.single.reiseId, r1);
    expect(
      await db(tester, () => bibliothek.db.spurenDerReise(r1)),
      hasLength(1),
    );
    final notizen = await db(
      tester,
      () => bibliothek.db.reisetagnotizenFuer(r1),
    );
    print('ORT-122 Tagesnotizen: $notizen');
    expect(notizen.values, containsAll(['Notiz R1', 'Nur R2']));
    expect(notizen.values, isNot(contains('Notiz R2')));
    await finish(tester);
  });

  testWidgets('ORT-128 ORT-129 Reisedetail: Route, Orte, Tageskapitel', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    await importiereDirekt(tester, [
      fotoBei('t1a.jpg', hamburg, DateTime(2024, 8, 1, 10)),
      fotoBei('t1b.jpg', hamburg, DateTime(2024, 8, 1, 11), dBreite: 0.001),
      fotoBei('t2a.jpg', bremen, DateTime(2024, 8, 2, 10)),
      fotoBei('t2b.jpg', bremen, DateTime(2024, 8, 2, 11), dBreite: 0.001),
      fotoBei('t3a.jpg', hannover, DateTime(2024, 8, 3, 10)),
      testfoto('x1.jpg', datum: DateTime(2024, 8, 10, 10)),
      testfoto('x2.jpg', datum: DateTime(2024, 8, 11, 10)),
    ]);
    final alleA = await alle(tester);
    final tour = [
      for (final a in alleA)
        if (a.originalFileName.startsWith('t')) a,
    ];
    final ohneOrt = [
      for (final a in alleA)
        if (a.originalFileName.startsWith('x')) a.id,
    ];
    final tourId = await reiseAnlegen(
      tester,
      'Nordtour',
      DateTime(2024, 8, 1),
      DateTime(2024, 8, 3),
      [for (final a in tour) a.id],
    );
    await aktivitaetAnlegen(
      tester,
      'Hafenrundgang',
      DateTime(2024, 8, 1, 9),
      DateTime(2024, 8, 1, 12),
      [tour.first.id],
      reiseId: tourId,
    );
    await reiseAnlegen(
      tester,
      'Ohne Ort',
      DateTime(2024, 8, 10),
      DateTime(2024, 8, 11),
      ohneOrt,
    );
    final staedte = {for (final a in tour) a.locationCity!};
    expect(staedte, hasLength(3));

    await reisenOeffnen(tester);
    await klick(tester, reisekachel('Nordtour'));
    await waitFor(tester, find.byType(ReiseDetailScreen));
    await waitFor(tester, find.text(de.reisenRoute));
    final detail = find.byType(ReiseDetailScreen);
    expect(
      find.descendant(of: detail, matching: find.byType(ActionChip)),
      findsOneWidget,
    );
    expect(textEnthaeltIn(detail, de.reisenNaechte(2)), findsOneWidget);
    expect(textEnthaeltIn(detail, de.reisenAufnahmen(5)), findsWidgets);
    expect(typ('Routenkarte'), findsOneWidget);
    expect(textIn(detail, de.reisenOrte), findsOneWidget);
    for (final s in staedte) {
      expect(find.widgetWithText(Chip, s), findsOneWidget, reason: s);
    }
    expect(textIn(detail, de.aktivitaetenInDieserReise), findsOneWidget);
    expect(textIn(detail, 'Hafenrundgang'), findsOneWidget);
    final format = DateFormat.yMMMMEEEEd('de');
    final liste = find
        .descendant(of: detail, matching: find.byType(Scrollable))
        .first;
    tour.sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
    for (final a in tour) {
      final kopf = '${format.format(a.fileCreatedAt)} · ${a.locationCity}';
      await sichtbarIn(tester, find.text(kopf), liste);
      expect(find.text(kopf), findsOneWidget);
    }
    await tester.drag(liste, const Offset(0, 3000));
    await settle(tester);
    final ortsbilder = typ('_Ortsbild');
    expect(ortsbilder, findsNWidgets(3));
    await klick(tester, ortsbilder.first);
    await waitFor(tester, vollansicht);
    final gezeigt = viewer(tester).assets;
    expect(gezeigt.map((a) => a.locationCity).toSet(), hasLength(1));
    await viewerZu(tester);
    await zurueck(tester);

    // ORT-129
    await waitFor(tester, reisekachel('Ohne Ort'));
    await stille(tester);
    await klick(tester, reisekachel('Ohne Ort'));
    await waitFor(tester, find.byType(ReiseDetailScreen));
    await waitFor(tester, find.text(de.reisenKeineRoute));
    expect(find.text(de.reisenRoute), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'ORT-135 ORT-137 ORT-140 Reisedetail: Fotos herausnehmen, hinzufügen, '
    'Reise entfernen',
    (tester) async {
      await starte(tester);
      await importiereDirekt(tester, [
        testfoto('r1.jpg', datum: DateTime(2024, 3, 1, 10)),
        testfoto('r2.jpg', datum: DateTime(2024, 3, 1, 12)),
        testfoto('r3.jpg', datum: DateTime(2024, 3, 2, 10)),
        testfoto('r4.jpg', datum: DateTime(2024, 3, 3, 10)),
        testfoto('frei.jpg', datum: DateTime(2024, 3, 2, 15)),
        testfoto('aussen.jpg', datum: DateTime(2024, 2, 20, 10)),
      ]);
      final id = {for (final a in await alle(tester)) a.originalFileName: a.id};
      final reiseId = await reiseAnlegen(
        tester,
        'Märzreise',
        DateTime(2024, 3, 1),
        DateTime(2024, 3, 3),
        [id['r1.jpg']!, id['r2.jpg']!, id['r3.jpg']!, id['r4.jpg']!],
      );
      await reiseAnlegen(
        tester,
        'Leer',
        DateTime(2001, 5, 1),
        DateTime(2001, 5, 3),
        [],
      );
      Future<void> detailOeffnen(String name) async {
        await reisenOeffnen(tester);
        await stille(tester);
        await klick(tester, reisekachel(name));
        await waitFor(tester, find.byType(ReiseDetailScreen));
        await waitFor(tester, find.byTooltip(de.aufnahmenHinzufuegen));
      }

      // ORT-135
      await detailOeffnen('Märzreise');
      await meldungenWeg(tester);
      await tester.longPress(
        kachel(id['r1.jpg']!),
        kind: PointerDeviceKind.mouse,
      );
      await settle(tester);
      await klick(tester, find.text(de.auswAuswaehlen));
      final leiste = typ('ZuordnungAuswahlleiste');
      await waitFor(tester, textIn(leiste, de.auswAnzahl(1)));
      await klick(tester, kachel(id['r2.jpg']!));
      expect(
        vollansicht,
        findsNothing,
        reason: 'Antippen wählt statt zu öffnen',
      );
      expect(textIn(leiste, de.auswAnzahl(2)), findsOneWidget);
      await klick(tester, textIn(leiste, de.aufnahmenAusReiseEntfernen));
      await meldung(tester, de.aufnahmenEntferntReise(2));
      await waitFor(tester, find.textContaining(de.reisenAufnahmen(2)));
      expect(
        await db(tester, () => bibliothek.db.zuordnungenDerReise(reiseId)),
        {id['r3.jpg'], id['r4.jpg']},
      );
      final nachher = await alle(tester);
      expect(nachher, hasLength(6));
      expect(nachher.where((a) => a.isTrashed), isEmpty);
      // Zweiter Durchgang: Auswahl aufheben lässt alles stehen.
      await meldungenWeg(tester);
      await tester.ensureVisible(kachel(id['r3.jpg']!));
      await settle(tester);
      await tester.longPress(
        kachel(id['r3.jpg']!),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      if (find.text(de.auswAuswaehlen).evaluate().isEmpty) {
        final r = tester.getRect(kachel(id['r3.jpg']!));
        final treffer = tester.hitTestOnBinding(r.center);
        print(
          'ORT-135 zweiter langer Druck ohne Menü; Kachel $r, Ziele: '
          '${treffer.path.take(6).map((e) => e.target.runtimeType).toList()}',
        );
        tester.widget<AssetThumbnailTile>(kachel(id['r3.jpg']!)).onLongPress!();
        await tester.pump(const Duration(milliseconds: 500));
        await settle(tester);
      }
      await klick(tester, find.text(de.auswAuswaehlen));
      await waitFor(tester, leiste);
      await klick(
        tester,
        find.descendant(of: leiste, matching: find.byTooltip(de.auswAufheben)),
      );
      expect(leiste, findsNothing);
      expect(
        await db(tester, () => bibliothek.db.zuordnungenDerReise(reiseId)),
        hasLength(2),
      );
      await bereich(tester, Hauptbereich.zeitleiste);
      await settle(tester);
      expect(
        kachel(id['r1.jpg']!),
        findsOneWidget,
        reason: 'bleibt in der Zeitleiste',
      );

      // ORT-137
      await detailOeffnen('Märzreise');
      await klick(tester, find.byTooltip(de.aufnahmenHinzufuegen));
      await waitFor(tester, find.byType(AufnahmenWaehlenScreen));
      final wahl = find.byType(AufnahmenWaehlenScreen);
      await waitFor(
        tester,
        find.descendant(of: wahl, matching: find.byType(AssetThumbnailTile)),
      );
      expect(textIn(wahl, de.aufnahmenWahlGewaehlt(2)), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find
                  .descendant(of: wahl, matching: find.byType(ChoiceChip))
                  .first,
            )
            .selected,
        isTrue,
        reason: 'Zeitraum vorgewählt',
      );
      expect(
        tester.widget<AssetThumbnailTile>(kachel(id['r3.jpg']!)).selected,
        isTrue,
        reason: 'Vorhandene sind vorgewählt',
      );
      await klick(
        tester,
        find.widgetWithText(ChoiceChip, de.aufnahmenWahlAlle),
      );
      await klick(tester, kachel(id['aussen.jpg']!));
      expect(textIn(wahl, de.aufnahmenWahlGewaehlt(3)), findsOneWidget);
      await klick(
        tester,
        find.descendant(of: wahl, matching: find.byType(ChoiceChip)).first,
      );
      expect(
        textEnthaeltIn(wahl, de.aufnahmenWahlAusserhalb(1)),
        findsOneWidget,
      );
      await klick(tester, kachel(id['frei.jpg']!));
      await klick(tester, find.text(de.allgFertig));
      await meldung(tester, de.aufnahmenWahlGeaendert(2, 0));
      await stille(tester);
      expect(
        await db(tester, () => bibliothek.db.zuordnungenDerReise(reiseId)),
        hasLength(4),
      );
      await klick(tester, find.byTooltip(de.aufnahmenHinzufuegen));
      await waitFor(tester, find.byType(AufnahmenWaehlenScreen));
      await klick(tester, find.text(de.allgFertig));
      await meldung(tester, de.aufnahmenWahlUnveraendert);
      await zurueck(tester);
      await detailOeffnen('Leer');
      await klick(tester, find.byTooltip(de.aufnahmenHinzufuegen));
      await waitFor(tester, find.text(de.aufnahmenWahlLeer));
      await zurueck(tester);
      await zurueck(tester);

      // ORT-140
      await detailOeffnen('Märzreise');
      await klick(tester, find.byTooltip(de.reisenLoeschen));
      await waitFor(tester, dialogFeld);
      await klick(tester, textIn(dialogFeld, de.allgEntfernen));
      await waitGone(tester, find.byType(ReiseDetailScreen));
      await waitGone(tester, reisekachel('Märzreise'));
      expect(await alle(tester), hasLength(6));
      await finish(tester);
    },
  );

  // =========================================================================
  // Aktivitäten
  // =========================================================================

  testWidgets('ORT-142 Aktivität wird erkannt und vorgeschlagen', (
    tester,
  ) async {
    await starte(tester, geodaten: true);
    const start = (47.4920, 11.0955);
    const schritt = 1.3333 / 111.195;
    await importiereDirekt(tester, [
      for (var i = 0; i < 12; i++)
        fotoBei(
          'heim$i.jpg',
          hamburg,
          DateTime(2024, 1 + i ~/ 2, 2 + i * 2, 12),
          dBreite: 0.0005 * i,
        ),
      for (var i = 0; i < 7; i++)
        fotoBei('weg$i.jpg', (
          start.$1 + schritt * i,
          start.$2,
        ), DateTime(2024, 8, 15, 9).add(Duration(minutes: 30 * i))),
      for (var i = 0; i < 4; i++)
        fotoBei(
          'kurz$i.jpg',
          muenchen,
          DateTime(2024, 8, 20, 14, 10 * i),
          dBreite: 0.0003 * i,
        ),
      for (var i = 0; i < 5; i++)
        fotoBei(
          'garten$i.jpg',
          hamburg,
          DateTime(2024, 8, 25, 14).add(Duration(minutes: 45 * i)),
          dLaenge: 0.0004 * i,
        ),
    ]);
    await aktivitaetenOeffnen(tester);
    expect(find.text(de.aktivitaetenVorschlaege), findsOneWidget);
    final ja = find.widgetWithText(FilledButton, de.aktivitaetenIstEine);
    expect(ja, findsOneWidget, reason: 'nur die Wanderung');
    final karte = find.ancestor(of: ja, matching: find.byType(Card)).first;
    final zeile = textEnthaeltIn(karte, '8,0 km');
    expect(zeile, findsOneWidget);
    final text = textVon(tester, zeile);
    print('ORT-142 $text');
    expect(text, startsWith(de.aktArtWanderung));
    expect(
      text,
      contains(DateFormat.yMMMd('de').format(DateTime(2024, 8, 15))),
    );
    expect(text, contains(de.aktivitaetenAufnahmen(7)));
    expect(textIn(karte, de.aktivitaetenKeine), findsOneWidget);
    final bilder = find.descendant(
      of: karte,
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, bilder);
    expect(bilder, findsNWidgets(5));
    expect(textIn(karte, de.aktivitaetenWeitere(2)), findsOneWidget);
    await klick(tester, bilder.first);
    await waitFor(tester, vollansicht);
    await viewerZu(tester);
    await finish(tester);
  });

  testWidgets('ORT-145 ORT-147 Aktivität von Hand anlegen und löschen', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('d1.jpg', datum: DateTime(2024, 5, 10, 9)),
      testfoto('d2.jpg', datum: DateTime(2024, 5, 10, 12)),
      testfoto('d3.jpg', datum: DateTime(2024, 5, 10, 18)),
      testfoto('e1.jpg', datum: DateTime(2024, 6, 1, 10)),
      testfoto('e2.jpg', datum: DateTime(2024, 6, 1, 11)),
    ]);
    final id = {for (final a in await alle(tester)) a.originalFileName: a.id};
    final reiseId = await reiseAnlegen(
      tester,
      'Maireise',
      DateTime(2024, 5, 9),
      DateTime(2024, 5, 11),
      [id['d1.jpg']!, id['d2.jpg']!, id['d3.jpg']!],
    );
    await aktivitaetenOeffnen(tester);
    Future<void> anlegen(String name, DateTime tag) async {
      await stille(tester);
      await klick(tester, find.byTooltip(de.aktivitaetenSelbstAnlegen));
      await waitFor(tester, dialogFeld);
      expect(
        textIn(dialogFeld, de.aktArtWanderung),
        findsOneWidget,
        reason: 'Vorgabe',
      );
      await eingeben(tester, field(de.zeitraumName), name);
      await klick(tester, datumsknoepfe().at(0));
      await datumImDialog(tester, tag);
      await klick(tester, datumsknoepfe().at(1));
      await datumImDialog(tester, tag);
      await klick(
        tester,
        find.descendant(of: dialogFeld, matching: knopf(de.allgUebernehmen)),
      );
      await meldung(tester, de.aktivitaetenSelbstAngelegt(name));
      await waitFor(tester, aktivitaetskachel(name));
    }

    // ORT-145
    await anlegen('Stadtgang', DateTime(2024, 5, 10));
    expect(
      find.text(de.aktivitaetenBestaetigte),
      findsOneWidget,
      reason: 'Auf Reisen',
    );
    var akt = await db(tester, () => bibliothek.db.alleAktivitaeten());
    final stadtgang = akt.firstWhere((a) => a.name == 'Stadtgang');
    expect(stadtgang.reiseId, reiseId);
    final zuStadt = await db(
      tester,
      () => bibliothek.db.select(bibliothek.db.aktivitaetAufnahmen).get(),
    );
    expect(
      {
        for (final z in zuStadt)
          if (z.aktivitaetId == stadtgang.id) z.assetId,
      },
      {id['d1.jpg'], id['d2.jpg'], id['d3.jpg']},
    );
    await anlegen('Ausflug', DateTime(2024, 6, 1));
    expect(
      find.text(de.aktivitaetenOhneReise),
      findsOneWidget,
      reason: 'Für sich',
    );
    akt = await db(tester, () => bibliothek.db.alleAktivitaeten());
    expect(akt.firstWhere((a) => a.name == 'Ausflug').reiseId, isNull);

    // ORT-147
    await kachelbefehl(
      tester,
      aktivitaetskachel('Ausflug'),
      de.aktivitaetenLoeschen,
    );
    await waitFor(
      tester,
      textIn(dialogFeld, de.aktivitaetenLoeschenFrage('Ausflug')),
    );
    await klick(tester, textIn(dialogFeld, de.allgEntfernen));
    await waitGone(tester, aktivitaetskachel('Ausflug'));
    akt = await db(tester, () => bibliothek.db.alleAktivitaeten());
    expect(akt.map((a) => a.name), ['Stadtgang']);
    final nachher = await alle(tester);
    expect(nachher, hasLength(5));
    expect(
      nachher.where((a) => a.isTrashed),
      isEmpty,
      reason: 'nichts im Papierkorb',
    );
    await finish(tester);
  });

  // =========================================================================
  // Kalender
  // =========================================================================

  testWidgets(
    'ORT-154 ORT-158 ORT-159 Kalender: Jahre, Löschen, ohne Gesperrte',
    (tester) async {
      await starte(tester);
      await bereich(tester, Hauptbereich.kalender);
      await waitFor(tester, find.text(de.kalenderLeer));
      await importiereDirekt(tester, [
        testfoto('j22.jpg', datum: DateTime(2022, 7, 1, 10)),
        testfoto('j23.jpg', datum: DateTime(2023, 7, 1, 10)),
        for (final tag in [3, 4, 5])
          for (final h in [10, 15])
            testfoto('juni$tag-$h.jpg', datum: DateTime(2024, 6, tag, h)),
        testfoto('gesperrt19.jpg', datum: DateTime(2019, 5, 1, 10)),
        testfoto('geloescht18.jpg', datum: DateTime(2018, 5, 1, 10)),
      ]);
      await sperren(tester, await aufnahme(tester, 'gesperrt19.jpg'));
      await inPapierkorb(
        tester,
        (await aufnahme(tester, 'geloescht18.jpg')).id,
      );
      await bereich(tester, Hauptbereich.zeitleiste);
      await bereich(tester, Hauptbereich.kalender);
      final kalender = find.byType(CalendarScreen);
      await waitFor(tester, textIn(kalender, '2024'));

      // ORT-154 / ORT-159
      final lagen = [
        for (final j in ['2024', '2023', '2022'])
          tester.getTopLeft(textIn(kalender, j)),
      ];
      for (var i = 1; i < lagen.length; i++) {
        final davor = lagen[i - 1];
        final jetzt = lagen[i];
        expect(
          jetzt.dy > davor.dy + 1 ||
              (jetzt.dy - davor.dy).abs() <= 1 && jetzt.dx > davor.dx,
          isTrue,
          reason: 'jüngstes zuerst',
        );
      }
      expect(textIn(kalender, de.kalenderAnzahlFotos(6)), findsOneWidget);
      expect(textIn(kalender, de.kalenderAnzahlFotos(1)), findsNWidgets(2));
      expect(textIn(kalender, '2019'), findsNothing);
      expect(textIn(kalender, '2018'), findsNothing);

      // ORT-158
      await klick(tester, textIn(kalender, '2024'));
      final juni = DateFormat.MMMM('de').format(DateTime(2024, 6));
      await klick(tester, find.text(juni));
      final id = {for (final a in await alle(tester)) a.originalFileName: a.id};
      await waitFor(tester, kachel(id['juni5-10.jpg']!));
      await tester.longPress(kachel(id['juni5-10.jpg']!));
      await settle(tester);
      await klick(
        tester,
        find.text(DateFormat.yMMMMEEEEd('de').format(DateTime(2024, 6, 3))),
      );
      await waitFor(tester, find.text(de.auswAnzahl(3)));
      await klick(tester, find.byTooltip(de.allgLoeschen));
      await waitFor(tester, textIn(dialogFeld, de.loeschenTitel(3)));
      expect(textIn(dialogFeld, de.loeschenHinweis(3)), findsOneWidget);
      await klick(tester, textIn(dialogFeld, de.allgAbbrechen));
      expect((await alle(tester)).where((a) => a.isTrashed), hasLength(1));
      await klick(tester, find.byTooltip(de.allgLoeschen));
      await waitFor(tester, dialogFeld);
      await klick(
        tester,
        find.descendant(of: dialogFeld, matching: find.byType(FilledButton)),
      );
      await settle(tester);
      final weg = {
        for (final a in await alle(tester))
          if (a.isTrashed) a.originalFileName,
      };
      expect(weg, {
        'geloescht18.jpg',
        'juni3-10.jpg',
        'juni3-15.jpg',
        'juni5-10.jpg',
      });
      await zurueck(tester);
      await waitFor(tester, find.text(de.kalenderAnzahlFotos(3)));
      await zurueck(tester);
      await waitFor(tester, textIn(kalender, de.kalenderAnzahlFotos(3)));
      await bereich(tester, Hauptbereich.papierkorb);
      await waitFor(tester, find.byType(TrashScreen));
      final raster = tester.widget<GridView>(
        find.descendant(
          of: find.byType(TrashScreen),
          matching: find.byType(GridView),
        ),
      );
      expect(
        (raster.childrenDelegate as SliverChildBuilderDelegate).childCount,
        4,
        reason: 'drei aus dem Juni und das von 2018 im Papierkorb',
      );
      await finish(tester);
    },
  );

  // =========================================================================
  // Gelände (ohne Netz: nur Menüs und Merken)
  // =========================================================================

  testWidgets('ORT-164 ORT-175 Gelände: Karte, Ebenen und Flugstil merken', (
    tester,
  ) async {
    await starte(tester);
    // Mit verorteten Fotos: Ohne sie scheitert die Routenkarte an der
    // leeren Fotostrecke (siehe „ORT-122 Reise mit Spur …“).
    await importiereDirekt(tester, [
      fotoBei('a1.jpg', (47.4250, 10.9900), DateTime(2024, 7, 10, 10)),
      fotoBei('a2.jpg', (47.4300, 10.9950), DateTime(2024, 7, 10, 11)),
      fotoBei('b1.jpg', (47.4250, 10.9900), DateTime(2024, 7, 11, 10)),
      fotoBei('b2.jpg', (47.4300, 10.9950), DateTime(2024, 7, 11, 11)),
    ]);
    final id = {for (final a in await alle(tester)) a.originalFileName: a.id};
    await aktivitaetAnlegen(
      tester,
      'Tour A',
      DateTime(2024, 7, 10, 8),
      DateTime(2024, 7, 10, 12),
      [id['a1.jpg']!, id['a2.jpg']!],
    );
    await aktivitaetAnlegen(
      tester,
      'Tour B',
      DateTime(2024, 7, 11, 8),
      DateTime(2024, 7, 11, 12),
      [id['b1.jpg']!, id['b2.jpg']!],
    );

    Future<void> gelaendeOeffnen(String name) async {
      await aktivitaetenOeffnen(tester);
      await stille(tester);
      await klick(tester, aktivitaetskachel(name));
      await waitFor(tester, find.byTooltip(de.aktivitaetenLoeschen));
      if (find.byTooltip(de.gelaendeOeffnen).evaluate().isEmpty) {
        dialog.dateien = [fixture('strecke.gpx')];
        await klick(tester, find.byTooltip(de.spurHinzufuegen));
        await waitFor(tester, find.byTooltip(de.gelaendeOeffnen));
      }
      await klick(tester, find.byTooltip(de.gelaendeOeffnen));
      await waitFor(tester, find.byType(GelaendeScreen));
      await waitFor(
        tester,
        find.text(gt.gelaendeNichts),
        timeout: const Duration(seconds: 60),
      );
    }

    Future<void> gelaendeZu() async {
      await zurueck(tester);
      await waitGone(tester, find.byType(GelaendeScreen));
    }

    Color? symbolfarbe(String eintrag) => tester
        .widget<Icon>(
          find
              .descendant(
                of: find
                    .ancestor(
                      of: find.text(eintrag).last,
                      matching: find.byType(Row),
                    )
                    .first,
                matching: find.byType(Icon),
              )
              .first,
        )
        .color;

    Finder kastenBei(String eintrag, IconData symbol) => find.descendant(
      of: find
          .ancestor(of: find.text(eintrag).last, matching: find.byType(Row))
          .first,
      matching: find.byIcon(symbol),
    );

    // ORT-164
    await gelaendeOeffnen('Tour A');
    final primaer = Theme.of(
      tester.element(find.byType(GelaendeScreen)),
    ).colorScheme.primary;
    await klick(tester, find.byTooltip(gt.gelaendeKarte));
    for (final t in [
      gt.karteLuftbild,
      gt.karteTopografie,
      gt.karteHell,
      gt.karteDunkel,
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    final vorgabe = [
      for (final t in [
        gt.karteLuftbild,
        gt.karteTopografie,
        gt.karteHell,
        gt.karteDunkel,
      ])
        if (symbolfarbe(t) == primaer) t,
    ];
    print('ORT-164 Grund ab Werk: $vorgabe');
    expect(vorgabe, hasLength(1), reason: 'genau ein Grund markiert');
    await klick(tester, find.text(gt.karteHell).last);
    await eventually(
      tester,
      () async =>
          (await bibliothek.db.gelaendeKarteWert()).grund == Gelaendegrund.hell,
    );
    await klick(tester, find.byTooltip(gt.gelaendeKarte));
    expect(symbolfarbe(gt.karteHell), primaer);
    final wegeVorher = kastenBei(
      gt.gelaendeEbeneWege,
      Icons.check_box_outlined,
    ).evaluate().isNotEmpty;
    print('ORT-164 Wanderwege ab Werk: $wegeVorher');
    final wegeSymbol = wegeVorher
        ? Icons.check_box_outline_blank
        : Icons.check_box_outlined;
    await klick(tester, find.text(gt.gelaendeEbeneWege).last);
    await eventually(
      tester,
      () async => (await bibliothek.db.gelaendeKarteWert()).wege != wegeVorher,
    );
    await klick(tester, find.byTooltip(gt.gelaendeKarte));
    expect(kastenBei(gt.gelaendeEbeneWege, wegeSymbol), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await gelaendeZu();
    // Eine eigene Quelle steht zusätzlich im Menü.
    const karte = Eigenkarte(
      name: 'Testkarte',
      url: 'https://kacheln.test/{z}/{x}/{y}.png',
      nennung: '© Testkarte',
      stufe: 18,
      zugestimmt: true,
    );
    await db(tester, () => bibliothek.db.setzeEigeneKarteWert(karte));
    await settle(tester);
    await zurueck(tester);
    await gelaendeOeffnen('Tour A');
    await klick(tester, find.byTooltip(gt.gelaendeKarte));
    expect(symbolfarbe(gt.karteHell), primaer, reason: 'gemerkt');
    expect(kastenBei(gt.gelaendeEbeneWege, wegeSymbol), findsOneWidget);
    expect(find.text('Testkarte'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);

    // ORT-175
    expect(
      find.descendant(
        of: find.byTooltip(gt.flugStil),
        matching: find.byIcon(Icons.flight_outlined),
      ),
      findsOneWidget,
    );
    await klick(tester, find.byTooltip(gt.flugStil));
    await klick(tester, find.text(gt.flugStilNahDran).last);
    expect(
      find.descendant(
        of: find.byTooltip(gt.flugStil),
        matching: find.byIcon(Icons.directions_walk),
      ),
      findsOneWidget,
    );
    await waitFor(
      tester,
      find.text(gt.gelaendeNichts),
      timeout: const Duration(seconds: 60),
    );
    await gelaendeZu();
    await zurueck(tester);
    await gelaendeOeffnen('Tour B');
    expect(
      find.descendant(
        of: find.byTooltip(gt.flugStil),
        matching: find.byIcon(Icons.directions_walk),
      ),
      findsOneWidget,
      reason: 'in derselben Sitzung „Nah dran“',
    );
    // Aufräumen: der Stil hängt am Prozess, nicht an der Bibliothek.
    await klick(tester, find.byTooltip(gt.flugStil));
    await klick(tester, find.text(gt.flugStilUeberblick).last);
    await waitFor(
      tester,
      find.text(gt.gelaendeNichts),
      timeout: const Duration(seconds: 60),
    );
    await gelaendeZu();
    await finish(tester);
  });

  // Prüfungen, deren Fehler ausserhalb des Tests auflaufen können,
  // stehen am Ende.
  // Befund beim Vorbereiten von ORT-122: Eine Reise mit GPX-Spur, aber
  // ohne verortetes Foto. Routenkarte legt dann eine Linie aus null Punkten
  // an (lib/widgets/routenkarte.dart:180–186), flutter_map scheitert an
  // LatLngBounds aus einer leeren Liste.
  // Befund ORT-122: Routenkarte legt eine Linie aus null Punkten an und
  // scheitert an LatLngBounds (routenkarte.dart:180–186). Drei Läufe
  // (Reise und Aktivität).
  testWidgets('ORT-122 Reise mit Spur, aber ohne verortete Fotos', (
    tester,
  ) async {
    await starte(tester);
    await importiereDirekt(tester, [
      testfoto('r2a.jpg', datum: DateTime(2024, 7, 10, 10)),
      testfoto('r2b.jpg', datum: DateTime(2024, 7, 10, 11)),
    ]);
    await reiseAnlegen(
      tester,
      'R2',
      DateTime(2024, 7, 10),
      DateTime(2024, 7, 10),
      [for (final a in await alle(tester)) a.id],
    );
    await reisenOeffnen(tester);
    await klick(tester, reisekachel('R2'));
    await waitFor(tester, find.byTooltip(de.spurHinzufuegen));
    dialog.dateien = [fixture('strecke.gpx')];
    await klick(tester, find.byTooltip(de.spurHinzufuegen));
    await eventually(
      tester,
      () async => (await bibliothek.db.spurenDerReise('reise-R2')).isNotEmpty,
    );
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    final fehler = tester.takeException();
    final hatKarte = typ('Routenkarte').evaluate().isNotEmpty;
    // Aufräumen, damit der Fehler nicht bei jedem Bild erneut kommt.
    await zurueck(tester);
    await settle(tester);
    while (tester.takeException() != null) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    print('ORT-122 Routenkarte mit Spur ohne Fotoort: $fehler');
    expect(fehler, isNull, reason: 'Routenkarte mit leerer Fotostrecke');
    expect(hatKarte, isTrue);
    await finish(tester);
  }, skip: true);

  // Behoben in #413: liesGpxDatei macht aus dem Lesefehler einen GpxFehler
  // (unlesbar); die Verortung meldet ihn und gibt Kreisel und Knopf frei.
  testWidgets('ORT-086 Unlesbare Datei mit Endung .gpx', (tester) async {
    await starte(tester);
    await gpxOeffnen(tester);
    final kaputt = File(
      p.join(eingang.path, 'kaputt.gpx'),
    )..writeAsBytesSync([0xFF, 0xFE, 0xC3, 0x28, 0xA0, 0xA1, 0x80, 0x00, 0xFF]);
    await gpxWaehlen(tester, kaputt);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(
      find.descendant(
        of: find.byType(GpxVerortungScreen),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'Kreisel verschwindet',
    );
    expect(knopfAktiv(tester, knopf(de.gpxDateiWaehlen)), isTrue);
    await finish(tester);
  });
}

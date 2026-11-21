// ignore_for_file: avoid_print, invalid_use_of_visible_for_testing_member
// Zweite Prüfrunde, Prüfer r2-gru: Einträge aus GRU, IMP und ANS, die in
// der ersten Runde teilweise blieben, weil dem Prüfstand etwas fehlte –
// Karte ohne Netz, echte Modelle, echte Gesichter, Neustart, ein echter
// Wechseldatenträger, Sprache im Video, HEIC, ein GeoNames-Datensatz.
//
// Diese Datei enthält die Prüfungen ohne Server und die Hilfen, die die
// übrigen Dateien der Runde mitnutzen (`import 'katalog_r2_gru_test.dart'
// hide main;`):
//   katalog_r2_gru_neustart_test.dart  GRU-184 Teil 2 (neuer Prozess)
//   katalog_r2_gru_server_test.dart    mit dem Wegwerf-Server
//   katalog_r2_gru_menge_test.dart     3000 Fotos
//
// **Karte.** Die Kacheln kommen hier aus einem Anbieter im Prüfstand
// ([LeereKacheln] über `kachelAnbieterFuerTest`), nicht aus dem Netz. So
// öffnet sich die Karte wie sonst, ohne dass OpenStreetMap gefragt wird.
//
// **Wechseldatenträger (IMP-100).** Ein Disk-Image, das
// `pruefkatalog/arbeit/r2-gru/r2gru_steuerung.py` auf 127.0.0.1:18874
// einsteckt und auswirft: Die App im Sandkasten darf /Volumes nur lesen
// und kein hdiutil starten.
//
// Laufen lassen nur über die Warteschlange des Prüfkatalogs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart'
    show TileProvider, TileCoordinates, TileLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/umzug.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/search_filters.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/album_detail_screen.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/screens/fotokammer_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/locked_folder_screen.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/screens/person_detail_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/screens/statistics_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/groessentext.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/mini_location_map.dart'
    show kachelAnbieterFuerTest;
import 'package:photo_vault/widgets/search_options_sheet.dart';
import 'package:photo_vault/widgets/seitenleiste.dart';
import 'package:photo_vault/widgets/video_playback.dart' show VideoSurface;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'katalog_kit.dart';

// --- Allgemeine Hilfen ---------------------------------------------------------

/// Was gerade geschieht – für das Lebenszeichen im Protokoll.
var schritt = '';

/// Höchstdauer je Prüfung.
const frist = Timeout(Duration(minutes: 15));

/// Lebenszeichen alle 30 s im Protokoll (Schritt und Bildtakt) – für jede
/// Datei der Runde einmal aus `main` gerufen.
void lebenszeichen() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Timer? uhr;
  var bilder = 0;
  setUpAll(() {
    SchedulerBinding.instance.addPersistentFrameCallback((_) => bilder++);
    var zuletzt = -1;
    uhr = Timer.periodic(const Duration(seconds: 30), (_) {
      print(
        'LEBENSZEICHEN ${DateTime.now().toIso8601String().substring(11, 19)} '
        'Bilder ${bilder - (zuletzt < 0 ? bilder : zuletzt)} seit 30 s, '
        'Schritt: $schritt',
      );
      zuletzt = bilder;
    });
  });
  tearDownAll(() => uhr?.cancel());
}

Finder _typ(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

/// Die Zeile der Seitenleiste mit dem Text [text].
Finder zeile(String text) =>
    find.ancestor(of: find.text(text), matching: _typ('_Zeile'));

/// Klick auf den linken Teil (das Symbol) eines Leisteneintrags.
Future<void> tippeLinks(WidgetTester tester, Finder bereich) async {
  await waitFor(tester, bereich);
  final ink = find.descendant(
    of: bereich.first,
    matching: find.byType(InkWell),
  );
  await tester.ensureVisible(ink.first);
  await tester.pump();
  final r = tester.getRect(ink.first);
  await tester.tapAt(Offset(r.left + 24, r.center.dy));
}

/// Klick auf einen Eintrag der Seitenleiste.
Future<void> leiste(WidgetTester tester, String text) async {
  schritt = 'leiste $text';
  await tippeLinks(tester, zeile(text));
  await settle(tester, max: const Duration(seconds: 3));
}

/// Wie [leiste], ohne auf Ruhe zu warten.
Future<void> leisteSchnell(WidgetTester tester, String text) async {
  await tippeLinks(tester, zeile(text));
  await tester.pump(const Duration(milliseconds: 50));
}

int gewaehlt(WidgetTester tester) =>
    tester.widget<Seitenleiste>(find.byType(Seitenleiste)).gewaehlt;

/// Tippt auf [f] und wartet nur kurz.
Future<void> tippe(WidgetTester tester, Finder f) async {
  schritt = 'tippe $f'.split('\n').first;
  await waitFor(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await settle(tester, max: const Duration(seconds: 2));
}

/// Zurück: der Zurück-Pfeil der obersten Seite, sonst die Seite schliessen.
Future<void> zurueck(WidgetTester tester) async {
  final pfeil = find.byType(BackButton);
  if (pfeil.evaluate().isNotEmpty) {
    await tester.tap(pfeil.last);
  } else {
    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
  }
  await settle(tester, max: const Duration(seconds: 3));
}

/// Alle offenen Seiten schliessen.
Future<void> alleZurueck(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final b = find.byType(BackButton);
    if (b.evaluate().isEmpty) return;
    await tester.tap(b.last);
    await settle(tester, max: const Duration(seconds: 2));
  }
}

/// Fenstergrösse für Layout UND MediaQuery.
Future<void> fenster(WidgetTester tester, Size groesse) async {
  tester.view.physicalSize = groesse * tester.view.devicePixelRatio;
  await tester.binding.setSurfaceSize(groesse);
  await tester.pump();
}

/// startApp aus dem Kit, vorher die MediaQuery-Grösse passend zur Fläche.
Future<LibraryState> starte(
  WidgetTester tester, {
  Size groesse = const Size(1400, 900),
  Object modelle = false,
}) async {
  schritt = 'startApp';
  // Keine Kachel aus dem Netz: Auch die kleine Karte im Info-Blatt holte
  // sonst Kacheln bei OpenStreetMap.
  if (kachelAnbieterFuerTest == null) kachelnOhneNetz();
  tester.view.physicalSize = groesse * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  return startApp(tester, groesse: groesse, modelle: modelle);
}

/// Übergeht Assertions des Flutter-Rahmens selbst (Semantikbaum,
/// RawTooltip am globalen Zeigerweg), alles andere geht an den Prüfrahmen.
void filtereSemantik() {
  final vorher = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exception.toString();
    final stapel = details.stack?.toString() ?? '';
    if (text.contains('package:flutter/src/semantics/semantics.dart') ||
        text.contains("'!child.attached'") ||
        text.contains("'node.built'")) {
      return;
    }
    if (stapel.contains('raw_tooltip.dart') &&
        (text.contains('SingleTickerProviderStateMixin') ||
            text.contains("Looking up a deactivated widget's ancestor"))) {
      return;
    }
    vorher?.call(details);
  };
}

/// Hält Analyse und Aufgaben an und wartet, bis nichts mehr läuft.
Future<void> halteAn(WidgetTester tester, LibraryState b) async {
  try {
    if (b.analyseLaeuft) b.brichHintergrundanalyseAb();
    for (final lauf in b.offeneAufgaben.toList()) {
      b.brichAufgabeAb(lauf.schluessel);
    }
    final ende = DateTime.now().add(const Duration(seconds: 30));
    while (b.etwasLaeuft && DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  } catch (e) {
    print('halteAn: $e');
  }
}

/// Beendet die App (Arbeit anhalten, Oberfläche abbauen, Datenbank zu)
/// und startet sie mit derselben Umlenkung des Kits neu. [dazwischen]
/// läuft, solange nichts geöffnet ist.
Future<void> neustart(
  WidgetTester tester, {
  FutureOr<void> Function()? dazwischen,
}) async {
  final alt = bibliothek;
  schritt = 'neustart: anhalten';
  await halteAn(tester, alt);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 500));
  try {
    await alt.vorDemBeenden();
  } catch (e) {
    print('neustart: vorDemBeenden: $e');
  }
  if (dazwischen != null) await dazwischen();
  schritt = 'neustart: aufbauen';
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
  if (!bibliothek.paths.root.path.startsWith(anker.path)) {
    throw StateError(
      'Bibliothek liegt nicht im Temp-Ordner: ${bibliothek.paths.root.path}',
    );
  }
  await settle(tester);
}

/// Ende einer Prüfung: Arbeit anhalten, Oberfläche abbauen, dann finish.
Future<void> ende(WidgetTester tester) async {
  schritt = 'ende';
  await halteAn(tester, bibliothek);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 500));
  await finish(tester);
}

/// Datenbankarbeit in echter Zeit.
Future<T> mitDb<T>(WidgetTester tester, Future<T> Function() arbeit) async =>
    (await tester.runAsync(arbeit)) as T;

Future<List<AssetData>> aufnahmen(WidgetTester tester) =>
    mitDb(tester, () => bibliothek.db.select(bibliothek.db.assets).get());

Future<AssetData> aufnahme(WidgetTester tester, String name) async =>
    (await aufnahmen(tester)).firstWhere((a) => a.originalFileName == name);

Future<void> befehl(WidgetTester tester, Befehl<Object?> b) async {
  await mitDb(tester, () => bibliothek.db.fuehreAus(b));
  await settle(tester, max: const Duration(seconds: 2));
}

/// [importiereDirekt] mit Schrittmarke.
Future<List<String>> importiere(WidgetTester tester, List<File> dateien) {
  schritt = 'import ${dateien.length}';
  return importiereDirekt(tester, dateien);
}

/// Pumpt [dauer] lang in echter Zeit.
Future<void> warte(WidgetTester tester, Duration dauer) async {
  final ende = DateTime.now().add(dauer);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String sha(File f) => sha256.convert(f.readAsBytesSync()).toString();

int ordnergroesse(Directory d) {
  var n = 0;
  if (!d.existsSync()) return 0;
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is File) n += e.lengthSync();
  }
  return n;
}

/// Erzeugt [n] kleine Testfotos.
List<File> fotos(
  int n, {
  String stamm = 'f',
  int breite = 160,
  int hoehe = 120,
  bool mitOrt = false,
}) => [
  for (var i = 0; i < n; i++)
    testfoto(
      '$stamm${i.toString().padLeft(4, '0')}.jpg',
      datum: DateTime(2024, 5, 1, 10).add(Duration(minutes: i)),
      breitengrad: mitOrt ? 47.0 + i * 0.001 : null,
      laengengrad: mitOrt ? 11.0 + i * 0.001 : null,
      breite: breite,
      hoehe: hoehe,
    ),
];

/// [n] Fotos: eines erzeugt, die übrigen als Kopien mit angehängten
/// Bytes (andere Prüfsumme, dasselbe Bild). [ordner] statt des Eingangs.
List<File> grosseFotos(
  int n, {
  String stamm = 'g',
  int breite = 3000,
  int hoehe = 2000,
  bool mitOrt = false,
  Directory? ordner,
  Uint8List? basisBytes,
}) {
  final ziel = ordner ?? eingang;
  final bytes =
      basisBytes ??
      testfoto(
        '${stamm}_basis.jpg',
        datum: DateTime(2024, 5, 1, 10, 7),
        breite: breite,
        hoehe: hoehe,
        breitengrad: mitOrt ? 47.1 : null,
        laengengrad: mitOrt ? 11.1 : null,
      ).readAsBytesSync();
  final kennung = utf8.encode('pv-kopie-');
  return [
    for (var i = 0; i < n; i++)
      File(p.join(ziel.path, '$stamm${i.toString().padLeft(4, '0')}.jpg'))
        ..writeAsBytesSync(
          Uint8List(bytes.length + kennung.length + 6)
            ..setAll(0, bytes)
            ..setAll(bytes.length, kennung)
            ..setAll(
              bytes.length + kennung.length,
              utf8.encode(i.toString().padLeft(6, '0')),
            ),
        ),
  ];
}

/// Ein Knopf (Filled/Outlined/Text) mit dem Text [text].
Finder knopf(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

Finder knopfIn(Finder bereich, String text) => find.ancestor(
  of: find.descendant(of: bereich, matching: find.text(text)),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// ⌘ + [taste].
Future<void> mitMeta(WidgetTester tester, LogicalKeyboardKey taste) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(taste);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await settle(tester, max: const Duration(seconds: 2));
}

/// Die Rasterkachel der Aufnahme [id].
Finder kachel(String id) =>
    find.byWidgetPredicate((w) => w is AssetThumbnailTile && w.asset.id == id);

/// Wie viele Kacheln das Raster des Papierkorbs zeigt (0 ohne Raster).
int papierkorbKacheln(WidgetTester tester) {
  final g = find.descendant(
    of: find.byType(TrashScreen),
    matching: find.byType(GridView),
  );
  if (g.evaluate().isEmpty) return 0;
  return tester
          .widget<GridView>(g.first)
          .childrenDelegate
          .estimatedChildCount ??
      0;
}

/// Die Rasterkachel mit dem Dateinamen [name].
Finder kachelName(String name) => find.byWidgetPredicate(
  (w) => w is AssetThumbnailTile && w.asset.originalFileName == name,
);

/// Scrollt im ersten Scrollbereich von [bildschirm], bis [ziel] da ist.
Future<void> sichtbar(WidgetTester tester, Finder ziel, Type bildschirm) async {
  await waitFor(tester, find.byType(bildschirm));
  final bereich = find
      .descendant(
        of: find.byType(bildschirm),
        matching: find.byType(Scrollable),
      )
      .first;
  if (ziel.evaluate().isEmpty) {
    tester.state<ScrollableState>(bereich).position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    ziel,
    250,
    scrollable: bereich,
    maxScrolls: 80,
  );
  await settle(tester, max: const Duration(seconds: 2));
}

/// Öffnet ein Foto aus der Zeitleiste im Vollbild.
Future<void> oeffneFoto(WidgetTester tester, String id) async {
  await alleZurueck(tester);
  await openSection(tester, Hauptbereich.zeitleiste);
  try {
    await waitFor(tester, kachel(id), timeout: const Duration(seconds: 5));
  } on TimeoutException {
    await sichtbar(tester, kachel(id), TimelineScreen);
  }
  await tippe(tester, kachel(id));
  await waitFor(tester, find.byType(AssetViewerScreen));
  await settle(tester, max: const Duration(seconds: 2));
}

/// Die Einstellungen öffnen und die Gruppe [titel] aufklappen.
Future<void> einstellungsgruppe(WidgetTester tester, String titel) async {
  await alleZurueck(tester);
  await openSection(tester, Hauptbereich.einstellungen);
  final t = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, t, SettingsScreen);
  await tippe(tester, t.first);
}

/// Die Aufgabenübersicht öffnen: Werkzeuge → Aufgaben.
Future<void> aufgabenOeffnen(WidgetTester tester) async {
  await alleZurueck(tester);
  await openSection(tester, Hauptbereich.werkzeuge);
  final ziel = find.descendant(
    of: find.byType(ToolsScreen),
    matching: find.text(de.aufgTitel),
  );
  await sichtbar(tester, ziel, ToolsScreen);
  await tippe(tester, ziel);
  await waitFor(tester, find.byType(BackgroundTasksScreen));
}

/// Die Karte einer Aufgabe mit dem Titel [titel] (dorthin gescrollt).
Future<Finder> aufgabe(WidgetTester tester, String titel) async {
  final t = find.descendant(
    of: find.byType(BackgroundTasksScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, t, BackgroundTasksScreen);
  await Scrollable.ensureVisible(tester.element(t.first), alignment: 0.4);
  await tester.pump(const Duration(milliseconds: 200));
  return find.ancestor(of: t.first, matching: find.byType(Card)).first;
}

/// Tippt in der Karte [k] auf die Aktion [beschriftung].
Future<void> aktion(WidgetTester tester, Finder k, String beschriftung) async {
  final f = find.descendant(of: k, matching: find.text(beschriftung));
  await waitFor(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Der Wert neben [beschriftung] in einer Zahlenreihe der Karte [k].
String? zahl(WidgetTester tester, Finder k, String beschriftung) {
  final b = find.descendant(of: k, matching: find.text(beschriftung));
  if (b.evaluate().isEmpty) return null;
  final reihe = find.ancestor(of: b.first, matching: find.byType(Row)).first;
  final texte = tester
      .widgetList<Text>(find.descendant(of: reihe, matching: find.byType(Text)))
      .toList();
  return texte.last.data;
}

/// Die Dateinamen der Modelle [eintraege] – für `startApp(modelle: …)`.
List<String> dateienVon(List<ModelCatalogEntry> eintraege) => [
  for (final e in eintraege)
    for (final f in e.files) f.fileName,
];

/// Wartet, bis keine Analyse und keine Aufgabe mehr läuft.
Future<void> warteRuhe(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  var ruhig = 0;
  await eventually(
    tester,
    () async {
      final still =
          !bibliothek.analyseLaeuft &&
          !bibliothek.analyseZurueckgestellt &&
          bibliothek.offeneAufgaben.isEmpty;
      ruhig = still ? ruhig + 1 : 0;
      return ruhig >= 4;
    },
    timeout: timeout,
    was: 'Ruhe nach der Auswertung',
  );
}

/// Führt [ausloesen] aus, wartet, bis die Hintergrundanalyse begonnen hat,
/// und dann auf ihr Ende.
Future<T> mitAnalyse<T>(
  WidgetTester tester,
  Future<T> Function() ausloesen, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  var begonnen = false;
  final b = bibliothek;
  void hoere() {
    if (b.analyseLaeuft) begonnen = true;
  }

  b.addListener(hoere);
  b.fortschritt.addListener(hoere);
  try {
    final ergebnis = await ausloesen();
    await eventually(
      tester,
      () async => begonnen || b.analyseLaeuft,
      timeout: const Duration(minutes: 2),
      was: 'Analyse beginnt',
    );
    await warteRuhe(tester, timeout: timeout);
    return ergebnis;
  } finally {
    b.removeListener(hoere);
    b.fortschritt.removeListener(hoere);
  }
}

/// Eine Datei aus `pruefkatalog/fixtures-ml` (Gesichter, HEIC, Inhalte),
/// in den Eingang kopiert – nur lesend aus /Volumes.
File mlFixture(String relativ, {String? name}) {
  final quelle = File(
    p.join(p.dirname(fixturesOrdner), 'fixtures-ml', relativ),
  );
  if (!quelle.existsSync()) throw StateError('ML-Fixture fehlt: $quelle');
  return quelle.copySync(p.join(eingang.path, name ?? p.basename(relativ)));
}

/// Die Gesichter der Aufnahme [id].
Future<List<FaceData>> gesichterVon(WidgetTester tester, String id) => mitDb(
  tester,
  () => (bibliothek.db.select(
    bibliothek.db.faces,
  )..where((t) => t.assetId.equals(id))).get(),
);

/// Kachelanbieter des Prüfstands: ein graues Bild je Kachel, ohne Netz.
class LeereKacheln extends TileProvider {
  LeereKacheln();

  static final Uint8List _png = () {
    final bild = img.Image(width: 256, height: 256);
    img.fill(bild, color: img.ColorRgb8(205, 210, 215));
    return Uint8List.fromList(img.encodePng(bild));
  }();

  var abgerufen = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    abgerufen++;
    return MemoryImage(_png);
  }
}

/// Setzt [LeereKacheln] als Kachelanbieter der Karte (bis zum Ende der
/// Prüfung).
LeereKacheln kachelnOhneNetz() {
  final k = LeereKacheln();
  kachelAnbieterFuerTest = k;
  addTearDown(() => kachelAnbieterFuerTest = null);
  return k;
}

// --- Steuerung des Wechseldatenträgers (IMP-100) -----------------------------

const steuerAdresse = 'http://127.0.0.1:18874';
const wechselOrdner = '/Volumes/PVR2GRU/DCIM';

Future<Map<String, dynamic>> steuer(
  String methode,
  String pfad, {
  List<int>? inhalt,
}) async {
  final c = HttpClient();
  try {
    final r = await c.openUrl(methode, Uri.parse('$steuerAdresse$pfad'));
    if (inhalt != null) {
      r.contentLength = inhalt.length;
      r.add(inhalt);
    } else {
      r.contentLength = 0;
    }
    final a = await r.close();
    final text = await a.transform(utf8.decoder).join();
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (a.statusCode != 200) throw StateError('Steuerung $pfad: $text');
    return j;
  } finally {
    c.close(force: true);
  }
}

// --- Wegwerf-Server -------------------------------------------------------------

const kennwort = 'pruefpasswort-123';
final _verwalterToken = <String, String>{};
var _kontoNummer = 0;

/// Meldet [konto] an [server] an (TOTP ist am Wegwerf-Server frei).
Future<String> anmelden(Uri server, String konto, String geraet) async {
  final a = Anmeldung(server);
  try {
    final s = await a.anmelden(konto, kennwort, geraet: geraet);
    if (s is! AnmeldungFertig) throw StateError('Anmeldung: $s');
    return s.token;
  } finally {
    a.schliesse();
  }
}

/// Ein neues, leeres Konto am [server]: Das erste Konto (Verwalter) legt
/// die Einrichtung an, jedes weitere der Verwalter – ein Umzug geht nur in
/// eine leere Bibliothek, und mehrere Prüfungen teilen sich den Server.
Future<({String konto, String token})> neuesKonto(
  Uri server, {
  String geraet = 'Rechner A',
  bool nurVerwalter = false,
}) async {
  var admin = _verwalterToken['$server'];
  if (admin == null) {
    final a = Anmeldung(server);
    try {
      Anmeldeschritt s;
      try {
        s = await a.einrichten('verwalter', kennwort, geraet: 'Verwaltung');
      } on Serverfehler {
        s = await a.anmelden('verwalter', kennwort, geraet: 'Verwaltung');
      }
      admin = (s as AnmeldungFertig).token;
    } finally {
      a.schliesse();
    }
    _verwalterToken['$server'] = admin;
  }
  // Ein älterer Server ohne Kontenverwaltung: das erste Konto selbst.
  if (nurVerwalter) return (konto: 'verwalter', token: admin);
  final name =
      'konto-${++_kontoNummer}-${DateTime.now().millisecondsSinceEpoch % 1000000}';
  final v = Serververbindung(server, admin);
  try {
    await Kontenverwaltung(v).legeAn(name, kennwort);
  } finally {
    v.schliesse();
  }
  return (konto: name, token: await anmelden(server, name, geraet));
}

/// Was die App unter „Mit Server verbinden“ → „Diese Bibliothek auf den
/// Server ziehen“ tut: neues Konto, Umzug, Verbindungsdatei, Neustart.
/// [adresseInDatei] steht in der Verbindungsdatei (etwa eine
/// [Durchreiche]); der Umzug geht direkt an [server].
Future<({String konto, String token})> verbinde(
  WidgetTester tester,
  Uri server, {
  Uri? adresseInDatei,
  String geraet = 'Rechner A',
  Future<void> Function(Serververbindung v)? vorNeustart,
  bool nurVerwalter = false,
}) async {
  schritt = 'verbinde $server';
  late ({String konto, String token}) k;
  await tester.runAsync(() async {
    k = await neuesKonto(server, geraet: geraet, nurVerwalter: nurVerwalter);
    final v = Serververbindung(server, k.token);
    try {
      await for (final _ in Umzug(
        v,
        bibliothek.db,
        bibliothek.paths.root,
      ).laufe()) {}
      if (vorNeustart != null) await vorNeustart(v);
    } finally {
      v.schliesse();
    }
    await Verbindungsdatei(
      server: adresseInDatei ?? server,
      konto: k.konto,
      geraet: geraet,
      token: k.token,
    ).schreibe(await LibraryLocation.currentRoot());
  });
  await neustart(tester);
  expect(bibliothek.verbunden, isTrue);
  await eventually(
    tester,
    () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    timeout: const Duration(seconds: 90),
    was: 'Server erreichbar',
  );
  return k;
}

/// Eine Durchreiche zum Wegwerf-Server, die sich anhalten lässt – für
/// die App sieht das aus wie ein gestoppter und wieder gestarteter Server
/// (Verbindungen brechen ab, neue werden abgewiesen). Der Server selbst
/// läuft mit seinen Daten weiter. [fehlendePfade] beantwortet sie mit 404.
class Durchreiche {
  Durchreiche(this.ziel, {this.port = 18870});
  final Uri ziel;
  int port;
  HttpServer? _server;
  final _client = HttpClient()..autoUncompress = false;
  final fehlendePfade = <String>{};

  String get adresse => 'http://127.0.0.1:$port';

  Future<void> starte() async {
    for (var i = 0; ; i++) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        break;
      } on SocketException {
        if (i > 40) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    port = _server!.port;
    _server!.listen((a) => unawaited(_reiche(a)));
  }

  Future<void> halteAn() async {
    await _server?.close(force: true);
    _server = null;
  }

  static const _ohne = {
    'host',
    'content-length',
    'transfer-encoding',
    'connection',
    'keep-alive',
  };

  Future<void> _reiche(HttpRequest anfrage) async {
    try {
      if (fehlendePfade.any((f) => anfrage.uri.path.endsWith(f))) {
        anfrage.response.statusCode = 404;
        await anfrage.response.close();
        return;
      }
      final r = await _client.openUrl(
        anfrage.method,
        ziel.replace(
          path: anfrage.uri.path,
          query: anfrage.uri.hasQuery ? anfrage.uri.query : null,
        ),
      );
      r.followRedirects = false;
      anfrage.headers.forEach((name, werte) {
        if (!_ohne.contains(name)) r.headers.set(name, werte);
      });
      if (anfrage.contentLength >= 0) r.contentLength = anfrage.contentLength;
      await r.addStream(anfrage);
      final a = await r.close();
      final antwort = anfrage.response..statusCode = a.statusCode;
      antwort.headers.clear();
      a.headers.forEach((name, werte) {
        if (_ohne.contains(name)) return;
        antwort.headers.set(name, werte);
      });
      final ohneInhalt =
          anfrage.method == 'HEAD' ||
          a.statusCode == HttpStatus.noContent ||
          a.statusCode == HttpStatus.notModified;
      if (a.contentLength >= 0) {
        antwort.contentLength = a.contentLength;
      } else if (ohneInhalt) {
        antwort.contentLength = 0;
      } else {
        antwort.headers.chunkedTransferEncoding = true;
      }
      await antwort.addStream(a);
      await antwort.close();
    } catch (e) {
      try {
        anfrage.response.statusCode = 502;
        await anfrage.response.close();
      } catch (_) {}
    }
  }
}

/// Führt [body] in einer eigenen Zone aus und sammelt Fehler, die dort
/// niemand fängt (statt die Prüfung sofort scheitern zu lassen) – so
/// lässt sich nachsehen, ob die App Fehler unbehandelt liegen lässt.
/// [beiFehler] darf einen Fehler übernehmen (true = nicht sammeln).
Future<List<String>> mitFehlerfang(
  Future<void> Function() body, {
  bool Function(Object e, StackTrace s)? beiFehler,
}) async {
  final unbehandelt = <String>[];
  final fertig = Completer<void>();
  runZonedGuarded(
    () async {
      try {
        await body();
        if (!fertig.isCompleted) fertig.complete();
      } catch (e, s) {
        if (!fertig.isCompleted) fertig.completeError(e, s);
      }
    },
    (e, s) {
      if (beiFehler?.call(e, s) ?? false) return;
      final zeile = '$e\n${s.toString().split('\n').take(12).join('\n')}';
      print('UNBEHANDELT: $zeile');
      unbehandelt.add(zeile);
    },
  );
  await fertig.future;
  return unbehandelt;
}

/// Ein kleiner GeoNames-Datensatz im Format von geonames.org, mit
/// erfundenen Orten in zwei Ländern, im Datenordner der Prüfung.
void geoDatensatz() {
  final d = Directory(p.join(anker.path, 'geodata'))
    ..createSync(recursive: true);
  String stadt(int id, String name, double b, double l, String cc, String a1) =>
      '$id\t$name\t$name\t\t$b\t$l\tP\tPPL\t$cc\t\t$a1\t\t\t\t5000\t\t100\t'
      'Europe/Paris\t2024-01-01';
  File(p.join(d.path, 'cities1000.txt')).writeAsStringSync(
    '${[stadt(9100001, 'Nordstadt', 48.0, 2.0, 'FR', '01'), stadt(9100002, 'Nordheim', 48.6, 2.6, 'FR', '01'), stadt(9100003, 'Suedstadt', 44.0, 5.0, 'FR', '02'), stadt(9100004, 'Oststadt', 43.0, 12.0, 'IT', '01'), stadt(9100005, 'Weststadt', 41.0, 14.0, 'IT', '02')].join('\n')}\n',
  );
  File(p.join(d.path, 'admin1CodesASCII.txt')).writeAsStringSync(
    'FR.01\tRegion Nord\tRegion Nord\t9200001\n'
    'FR.02\tRegion Sued\tRegion Sued\t9200002\n'
    'IT.01\tRegione Est\tRegione Est\t9200003\n'
    'IT.02\tRegione Ovest\tRegione Ovest\t9200004\n',
  );
  File(p.join(d.path, 'countryInfo.txt')).writeAsStringSync(
    '# Kopfzeile\n'
    'FR\tFRA\t250\tFR\tFrance\tParis\t547030\t64768389\tEU\t.fr\tEUR\tEuro'
    '\t33\t\t\tfr-FR\t3017382\t\t\n'
    'IT\tITA\t380\tIT\tItaly\tRom\t301230\t60431283\tEU\t.it\tEUR\tEuro'
    '\t39\t\t\tit-IT\t3175395\t\t\n',
  );
}

/// Ein Durchgang von ANS-108. Prüft alles Erwartete; die beiden Punkte
/// des Befunds kommen als (Stadt nach der Landeswahl offen, Hinweis ohne
/// aufgelöste Orte) zurück.
Future<(bool, bool)> _ans108(WidgetTester tester) async {
  await starte(tester);
  await neustart(tester, dazwischen: geoDatensatz);
  expect(bibliothek.geoDataAvailable, isTrue);
  await importiere(tester, [
    testfoto('n1.jpg', breitengrad: 48.01, laengengrad: 2.01),
    testfoto('n2.jpg', breitengrad: 48.61, laengengrad: 2.61),
    testfoto('s1.jpg', breitengrad: 44.01, laengengrad: 5.01),
    testfoto('o1.jpg', breitengrad: 43.01, laengengrad: 12.01),
    testfoto('w1.jpg', breitengrad: 41.01, laengengrad: 14.01),
  ]);
  Future<bool> alleAufgeloest() async =>
      (await bibliothek.db.select(bibliothek.db.assets).get()).every(
        (a) => a.locationCity != null,
      );
  // „Land/Bundesland/Stadt auflösen“ über die Aufgabe (falls der Import
  // sie nicht schon aufgelöst hat).
  if (!(await mitDb(tester, alleAufgeloest))) {
    await aufgabenOeffnen(tester);
    final k = await aufgabe(tester, de.werkzOrteAufloesenTitel);
    await aktion(tester, k, de.aufgFehlende);
    await eventually(
      tester,
      () async =>
          (bibliothek.lauf('ortsnamen')?.beendet ?? false) ||
          await alleAufgeloest(),
      timeout: const Duration(minutes: 2),
      was: 'Orte aufgelöst',
    );
    await alleZurueck(tester);
  } else {
    print('ANS-108: schon beim Import aufgelöst');
  }
  final aufgeloest = {
    for (final a in await aufnahmen(tester))
      a.originalFileName:
          '${a.locationCountry}/${a.locationState}/${a.locationCity}',
  };
  print('ANS-108: aufgelöst $aufgeloest');
  expect(aufgeloest['n1.jpg'], 'France/Region Nord/Nordstadt');
  expect(aufgeloest['w1.jpg'], 'Italy/Regione Ovest/Weststadt');
  await openSection(tester, Hauptbereich.suche);
  final blatt = find.byType(SearchOptionsSheet);
  Finder scroller() =>
      find.descendant(of: blatt, matching: find.byType(Scrollable)).first;
  Finder auswahl(String beschriftung) => find.descendant(
    of: blatt,
    matching: find.byWidgetPredicate(
      (w) =>
          w is DropdownButtonFormField<String?> &&
          w.decoration.labelText == beschriftung,
    ),
  );
  Future<void> hin(String beschriftung) => tester.scrollUntilVisible(
    auswahl(beschriftung),
    200,
    scrollable: scroller(),
    maxScrolls: 60,
  );
  Future<List<String>> liste(String beschriftung) async {
    await hin(beschriftung);
    await tippe(tester, auswahl(beschriftung));
    final menue = find.byWidgetPredicate(
      (w) => w.runtimeType.toString().startsWith('_DropdownMenu'),
    );
    final eintraege = [
      for (final e
          in find.descendant(of: menue, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data ?? '',
    ];
    await tippe(tester, find.text(de.allgAlle).last);
    return eintraege;
  }

  Future<void> waehleIn(String beschriftung, String wert) async {
    await hin(beschriftung);
    await tippe(tester, auswahl(beschriftung));
    await tippe(tester, find.text(wert).last);
  }

  bool offen(String beschriftung) =>
      tester
          .widget<DropdownButtonFormField<String?>>(auswahl(beschriftung))
          .onChanged !=
      null;

  await tippe(tester, find.byTooltip(de.sucheOptionen).first);
  await waitFor(tester, blatt);
  await hin(de.suchoptLand);
  expect(
    find.descendant(of: blatt, matching: find.text(de.suchoptGeoFehlt)),
    findsNothing,
    reason: 'aufgelöste Orte: kein Hinweis',
  );
  expect(await liste(de.suchoptLand), [de.allgAlle, 'Frankreich', 'Italien']);
  await waehleIn(de.suchoptLand, 'Frankreich');
  expect(await liste(de.suchoptBundesland), [
    de.allgAlle,
    'Region Nord',
    'Region Sued',
  ]);
  final stadtNachLand = offen(de.suchoptStadt);
  final staedteNachLand = stadtNachLand
      ? await liste(de.suchoptStadt)
      : const <String>[];
  print('ANS-108: Städte nach der Landeswahl $staedteNachLand');
  if (stadtNachLand) {
    expect(staedteNachLand, [
      de.allgAlle,
      'Nordheim',
      'Nordstadt',
      'Suedstadt',
    ]);
  }
  await waehleIn(de.suchoptBundesland, 'Region Nord');
  expect(await liste(de.suchoptStadt), [de.allgAlle, 'Nordheim', 'Nordstadt']);
  await waehleIn(de.suchoptStadt, 'Nordstadt');
  await tippe(
    tester,
    find.descendant(
      of: blatt,
      matching: find.widgetWithText(FilledButton, de.suchoptSuchen),
    ),
  );
  await waitGone(tester, blatt);
  await settle(tester);
  final treffer = [
    for (final e
        in find
            .descendant(
              of: find.byType(SearchScreen),
              matching: find.byType(AssetThumbnailTile),
            )
            .evaluate())
      (e.widget as AssetThumbnailTile).asset.originalFileName,
  ];
  expect(treffer, ['n1.jpg'], reason: 'nur Fotos der Stadt');

  // Zweite Bibliothek ohne aufgelöste Orte (Datensatz vorhanden, das Foto
  // ohne Ort im Datensatz).
  await ende(tester);
  await starte(tester);
  await neustart(tester, dazwischen: geoDatensatz);
  await importiere(tester, [testfoto('x.jpg')]);
  await openSection(tester, Hauptbereich.suche);
  await tippe(tester, find.byTooltip(de.sucheOptionen).first);
  await waitFor(tester, blatt);
  await hin(de.suchoptLand);
  final hinweisDa = find
      .descendant(of: blatt, matching: find.text(de.suchoptGeoFehlt))
      .evaluate()
      .isNotEmpty;
  final laender = await liste(de.suchoptLand);
  print(
    'ANS-108: ohne aufgelöste Orte Hinweis $hinweisDa, Länder $laender, '
    'Datensatz ${bibliothek.geoDataAvailable}',
  );
  expect(laender, [de.allgAlle], reason: 'keine aufgelösten Orte');
  await ende(tester);
  return (stadtNachLand, hinweisDa);
}

// --- Prüfungen ------------------------------------------------------------------

void main() {
  lebenszeichen();

  testWidgets(
    'GRU-039 GRU-058 GRU-049 Karte über Leiste, ⌘6 und Blatt (Kacheln ohne Netz)',
    (tester) async {
      filtereSemantik();
      final kacheln = kachelnOhneNetz();
      await starte(tester);
      final ids = await importiere(tester, fotos(3, mitOrt: true));
      await befehl(tester, AlbumAnlegen('alb1', 'Urlaub', DateTime(2024)));
      await befehl(tester, AlbumFuellen('alb1', ids));

      // GRU-039: alle 18 Einträge, Bereich und Hervorhebung.
      SearchScreen? suche() {
        final s = find.byType(SearchScreen);
        return s.evaluate().isEmpty ? null : tester.widget<SearchScreen>(s);
      }

      final ziele = <(String, bool Function())>[
        (de.navFotos, () => find.byType(TimelineScreen).evaluate().isNotEmpty),
        (de.navSuche, () => suche() != null && suche()!.startFilter == null),
        (de.navAlben, () => find.byType(AlbumsScreen).evaluate().isNotEmpty),
        (de.navFavoriten, () => suche()?.startFilter?.favoritesOnly == true),
        (de.navPersonen, () => find.byType(PeopleScreen).evaluate().isNotEmpty),
        (de.navKarte, () => find.byType(MapScreen).evaluate().isNotEmpty),
        (
          de.navOrte,
          () => find.byType(LaenderlisteScreen).evaluate().isNotEmpty,
        ),
        (de.navReisen, () => find.byType(ReisenScreen).evaluate().isNotEmpty),
        (
          de.navStammbaum,
          () => find.byType(StammbaumScreen).evaluate().isNotEmpty,
        ),
        (
          de.navStatistik,
          () => find.byType(StatisticsScreen).evaluate().isNotEmpty,
        ),
        (
          de.navRueckblick,
          () => find.byType(ExploreScreen).evaluate().isNotEmpty,
        ),
        (
          de.navKalender,
          () => find.byType(CalendarScreen).evaluate().isNotEmpty,
        ),
        (
          de.navFotokammer,
          () => find.byType(FotokammerScreen).evaluate().isNotEmpty,
        ),
        (
          de.navDuplikate,
          () => find.byType(DuplicatesScreen).evaluate().isNotEmpty,
        ),
        (de.navArchiv, () => suche()?.startFilter?.nurArchiv == true),
        (
          de.navPapierkorb,
          () => find.byType(TrashScreen).evaluate().isNotEmpty,
        ),
        (de.navWerkzeuge, () => find.byType(ToolsScreen).evaluate().isNotEmpty),
        (
          de.navEinstellungen,
          () => find.byType(SettingsScreen).evaluate().isNotEmpty,
        ),
      ];
      expect(ziele, hasLength(18));
      for (var i = 0; i < ziele.length; i++) {
        await leiste(tester, ziele[i].$1);
        if (i == Hauptbereich.karte) {
          await waitFor(tester, find.byType(MapScreen));
          await settle(tester);
        }
        expect(gewaehlt(tester), i, reason: ziele[i].$1);
        expect(ziele[i].$2(), isTrue, reason: 'Bereich ${ziele[i].$1}');
        expect(tester.takeException(), isNull);
      }
      print('GRU-039: Karte zeigte ${kacheln.abgerufen} Kacheln (ohne Netz)');
      expect(kacheln.abgerufen, greaterThan(0), reason: 'Karte gezeichnet');
      // Suche und Favoriten teilen keinen Zustand.
      await leiste(tester, de.navSuche);
      final suchfeld = find
          .descendant(
            of: find.byType(SearchScreen),
            matching: find.byType(TextField),
          )
          .first;
      await enter(tester, suchfeld, 'Strand');
      await leiste(tester, de.navFavoriten);
      expect(
        tester
            .widgetList<TextField>(
              find.descendant(
                of: find.byType(SearchScreen),
                matching: find.byType(TextField),
              ),
            )
            .any((f) => f.controller?.text == 'Strand'),
        isFalse,
      );

      // GRU-058: ⌘1 bis ⌘9, auch ⌘6 (Karte).
      final ziffern = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      for (var i = 0; i < ziffern.length; i++) {
        await mitMeta(tester, ziffern[i]);
        if (i == Hauptbereich.karte) {
          await waitFor(tester, find.byType(MapScreen));
        }
        expect(gewaehlt(tester), i, reason: '⌘${i + 1}');
        expect(ziele[i].$2(), isTrue, reason: '⌘${i + 1}: ${ziele[i].$1}');
      }

      // GRU-049: schmales Fenster, Blatt „Bibliothek“ → „Karte“.
      await mitMeta(tester, LogicalKeyboardKey.digit1);
      await fenster(tester, const Size(680, 900));
      await settle(tester);
      final leisteUnten = find.byType(NavigationBar);
      await waitFor(tester, leisteUnten);
      await tippe(
        tester,
        find.descendant(of: leisteUnten, matching: find.text(de.navBibliothek)),
      );
      final blatt = find.byType(BottomSheet);
      await waitFor(tester, blatt);
      for (final t in [
        de.befehlspaletteTitel,
        de.befehlspaletteHinweis,
        de.navGruppeEntdecken,
        de.navGruppeVerwalten,
      ]) {
        expect(
          find.descendant(of: blatt, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      final farben = <Object?>{
        for (final e
            in find
                .descendant(of: blatt, matching: _typ('Farbsymbol'))
                .evaluate())
          (e.widget as dynamic).farbe,
      };
      print('GRU-049: ${farben.length} verschiedene Farben der Symbole');
      expect(farben.length, greaterThan(4), reason: 'farbige Symbole');
      await tippe(
        tester,
        find.descendant(of: blatt, matching: find.text(de.navKarte)),
      );
      await waitGone(tester, blatt);
      await waitFor(tester, find.byType(MapScreen));
      expect(tester.widget<NavigationBar>(leisteUnten).selectedIndex, 3);
      await tippe(
        tester,
        find.descendant(of: leisteUnten, matching: find.text(de.navBibliothek)),
      );
      await waitFor(tester, blatt);
      await tippe(
        tester,
        find.descendant(of: blatt, matching: find.text(de.befehlspaletteTitel)),
      );
      final palettenFeld = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == de.befehlspaletteHinweis,
      );
      await waitFor(tester, palettenFeld);
      await tippe(tester, find.byType(BackButton));
      await waitGone(tester, palettenFeld);
      await fenster(tester, const Size(1400, 900));
      await ende(tester);
    },
    timeout: frist,
  );

  testWidgets('GRU-120 Videos beim Schweben: stumm, ausgeschaltet Standbild', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, [fixture('video_5s.mp4')]);
    final k = find.byType(AssetThumbnailTile);
    await waitFor(tester, k);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(location: const Offset(1300, 850));
    addTearDown(maus.removePointer);
    await tester.pump();
    Future<({bool spielt, double? lautstaerke})> schweben() async {
      await maus.moveTo(const Offset(1300, 850));
      await tester.pump(const Duration(milliseconds: 500));
      await maus.moveTo(tester.getCenter(k.first));
      final ende = DateTime.now().add(const Duration(seconds: 8));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 100));
        final v = find.byType(VideoSurface);
        if (v.evaluate().isNotEmpty) {
          final c = tester.widget<VideoSurface>(v.first).controller;
          if (c.isPlaying) {
            return (
              spielt: true,
              lautstaerke: c.videoController.player.state.volume,
            );
          }
        }
      }
      return (spielt: false, lautstaerke: null);
    }

    final an = await schweben();
    print('GRU-120: eingeschaltet $an');
    expect(an.spielt, isTrue, reason: 'eingeschaltet spielt es');
    expect(an.lautstaerke, 0, reason: 'stumm');
    await maus.moveTo(const Offset(1300, 850));
    await tester.pump(const Duration(milliseconds: 300));
    await einstellungsgruppe(tester, de.einstAbschnittErscheinungsbild);
    await tippe(
      tester,
      find.ancestor(
        of: find.text(de.einstSchwebeVorschauTitel),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(
      (await bibliothek.db.select(bibliothek.db.appSettings).getSingle())
          .schwebeVorschau,
      isFalse,
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, k);
    final aus = await schweben();
    expect(aus.spielt, isFalse, reason: 'ausgeschaltet Standbild');
    expect(find.byType(VideoSurface), findsNothing);
    await ende(tester);
  }, timeout: frist);

  testWidgets('GRU-056 Band der KI-Restaurierung mit echtem Modell', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester, modelle: dateienVon([ModelCatalog.neuralRestore]));
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    final ids = await importiere(tester, [
      // Zwei 512er Kacheln nebeneinander und eine kleine: Grössere Bilder
      // liessen die App bei der Restaurierung über die 12 GB des Wächters
      // wachsen (so auch SIC-083 in der ersten Runde).
      testfoto('rest1.jpg', breite: 900, hoehe: 360),
      testfoto('rest2.jpg', breite: 240, hoehe: 180),
    ]);
    expect(bibliothek.restoreQueue.restoreHalter?.installiert, isTrue);
    await mitDb(tester, () async {
      for (final id in ids) {
        await bibliothek.restoreQueue.enqueue(id);
      }
    });
    // Nur wartende (die Restaurierung wartet auf eine ruhige Phase).
    await waitFor(
      tester,
      find.text(de.restaurierungWartend(2)),
      timeout: const Duration(seconds: 20),
    );
    final muster = de.restaurProzentMitWarteschlange(4711, 1).split('4711');
    final prozent = RegExp(
      '^${RegExp.escape(muster[0])}(\\d+)${RegExp.escape(muster[1])}\$',
    );
    var vorbereitet = false;
    String? bandText;
    final laeuftBand = find.byWidgetPredicate(
      (w) => w is Text && prozent.hasMatch(w.data ?? ''),
    );
    final ende0 = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(ende0) && bandText == null) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(de.restaurierungWirdVorbereitet).evaluate().isNotEmpty) {
        vorbereitet = true;
      }
      if (laeuftBand.evaluate().isNotEmpty) {
        bandText = tester.widget<Text>(laeuftBand.first).data;
      }
    }
    print('GRU-056: vorbereitet $vorbereitet, Band „$bandText“');
    expect(bandText, isNotNull, reason: '„läuft – n %, 1 in Warteschlange“');
    // Klick aufs Band öffnet die Warteschlange neben der Leiste.
    await tippe(tester, laeuftBand);
    await waitFor(tester, find.byType(RestoreQueueScreen));
    expect(find.text(de.restaurTitel), findsWidgets);
    expect(find.byType(Seitenleiste), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(RestoreQueueScreen)).dx,
      greaterThanOrEqualTo(Seitenleiste.schmal - 1),
    );
    await zurueck(tester);
    // Ohne Aufträge verschwindet das Band.
    await eventually(
      tester,
      () async {
        final jobs = await bibliothek.db
            .select(bibliothek.db.restoreJobs)
            .get();
        return jobs.every((j) => j.status == 'done' || j.status == 'failed');
      },
      timeout: const Duration(minutes: 8),
      was: 'beide Restaurierungen fertig',
    );
    final jobs = await mitDb(
      tester,
      () => bibliothek.db.select(bibliothek.db.restoreJobs).get(),
    );
    print(
      'GRU-056: ${[for (final j in jobs) '${j.status} ${j.errorMessage}']}',
    );
    expect(jobs.every((j) => j.status == 'done'), isTrue);
    await waitGone(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == de.restaurierungWirdVorbereitet ||
                prozent.hasMatch(w.data ?? '') ||
                (w.data ?? '').contains(de.restaurierungWartend(1)) ||
                (w.data ?? '').contains(de.restaurierungWartend(2))),
      ),
      timeout: const Duration(seconds: 30),
    );
    await ende(tester);
  }, timeout: frist);

  testWidgets(
    'GRU-095 IMP-193 Echte Gesichter: Speicherbedarf, gesperrt aus allen Ansichten',
    (tester) async {
      filtereSemantik();
      final kacheln = kachelnOhneNetz();
      await starte(
        tester,
        modelle: dateienVon([
          ModelCatalog.faceDetection,
          ModelCatalog.faceRecognition,
        ]),
      );
      expect(bibliothek.faceDetectionAvailable, isTrue);
      final portraits = [
        mlFixture('gesichter/person_a_1.jpg'),
        mlFixture('gesichter/person_a_2.jpg'),
        mlFixture('gesichter/person_a_3.jpg'),
        mlFixture('heic/sonnenblume.heic'),
      ];
      await mitAnalyse(tester, () => importiere(tester, portraits));
      final a1 = await aufnahme(tester, 'person_a_1.jpg');
      final a2 = await aufnahme(tester, 'person_a_2.jpg');
      final a3 = await aufnahme(tester, 'person_a_3.jpg');
      final ids = [a1.id, a2.id, a3.id];
      final gesichter = <String>[];
      for (final id in ids) {
        final g = await gesichterVon(tester, id);
        print('Gesichter in $id: ${g.length}');
        gesichter.addAll(g.map((x) => x.id));
      }
      expect(gesichter, isNotEmpty, reason: 'echte Gesichter erkannt');
      final faces = Directory(p.join(bibliothek.paths.root.path, 'faces'));
      expect(ordnergroesse(faces), greaterThan(0), reason: 'Ausschnitte');

      // GRU-095: Speicherbedarf aufgeschlüsselt. Die Gruppe von Hand
      // aufklappen und gleich hinsehen: zuerst „wird berechnet …“.
      // Damit das Zählen nicht schneller ist als ein Blick: 6000 kleine
      // Dateien in einem eigenen Ordner der Originale.
      final ballast = Directory(
        p.join(bibliothek.paths.root.path, 'originals', '1999', 'ballast'),
      )..createSync(recursive: true);
      for (var i = 0; i < 6000; i++) {
        File(p.join(ballast.path, 'b$i.bin')).writeAsStringSync('$i');
      }
      await alleZurueck(tester);
      bibliothek.zeigeBereich(Hauptbereich.einstellungen);
      await tester.pump(const Duration(milliseconds: 50));
      final gruppe = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.text(de.einstSpeicherortTitel),
      );
      await waitFor(tester, find.byType(SettingsScreen));
      if (gruppe.hitTestable().evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          gruppe,
          300,
          scrollable: find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 40,
        );
      }
      await tester.tap(gruppe.first);
      var berechnet = false;
      final bedarf = find.text(de.einstSpeicherbedarf);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        berechnet |= find.text(de.einstWirdBerechnet).evaluate().isNotEmpty;
        if (berechnet) break;
      }
      print('GRU-095: „wird berechnet …“ gesehen: $berechnet');
      expect(berechnet, isTrue, reason: 'erst „wird berechnet …“');
      await waitFor(tester, bedarf);
      await waitGone(tester, find.text(de.einstWirdBerechnet));
      await sichtbar(tester, bedarf, SettingsScreen);
      await tippe(tester, bedarf);
      final wurzel = bibliothek.paths.root;
      final erwartet = <String, int>{
        de.belegung_originals: ordnergroesse(
          Directory(p.join(wurzel.path, 'originals')),
        ),
        de.belegung_previews: ordnergroesse(
          Directory(p.join(wurzel.path, 'previews')),
        ),
        de.belegung_thumbnails: ordnergroesse(
          Directory(p.join(wurzel.path, 'thumbnails')),
        ),
        de.belegung_faces: ordnergroesse(faces),
      };
      print('GRU-095: erwartet $erwartet');
      final rechts = <double>[];
      for (final e in erwartet.entries) {
        final zeileF = find.ancestor(
          of: find.text(e.key),
          matching: find.byType(Row),
        );
        if (e.value == 0) {
          expect(find.text(e.key), findsNothing, reason: 'leer: ${e.key}');
          continue;
        }
        await waitFor(tester, zeileF);
        final groesse = find.descendant(
          of: zeileF.first,
          matching: find.text(groessentext(e.value)),
        );
        expect(groesse, findsOneWidget, reason: '${e.key} ${e.value}');
        rechts.add(tester.getTopRight(groesse).dx);
      }
      expect(find.text(de.belegung_faces), findsOneWidget);
      expect(find.text(de.belegung_datenbank), findsOneWidget);
      rechts.add(
        tester
            .getTopRight(
              find
                  .descendant(
                    of: find
                        .ancestor(
                          of: find.text(de.belegung_datenbank),
                          matching: find.byType(Row),
                        )
                        .first,
                    matching: find.byType(Text),
                  )
                  .last,
            )
            .dx,
      );
      print('GRU-095: rechte Kanten der Grössen $rechts');
      expect(
        rechts.reduce(math.max) - rechts.reduce(math.min),
        lessThan(1.5),
        reason: 'rechtsbündig',
      );
      int summe() {
        var n = ordnergroesse(wurzel);
        for (final s in ['', '-wal', '-shm']) {
          final f = File(p.join(anker.path, 'library.sqlite$s'));
          if (f.existsSync()) n += f.lengthSync();
        }
        return n;
      }

      var summeOk = false;
      for (var i = 0; i < 6 && !summeOk; i++) {
        summeOk = find.text(groessentext(summe())).evaluate().isNotEmpty;
        if (!summeOk) await tester.pump(const Duration(milliseconds: 500));
      }
      expect(summeOk, isTrue, reason: 'Summe = library/ + library.sqlite');

      // IMP-193: Foto mit Gesicht sperren.
      await mitDb(tester, () async {
        await bibliothek.setupVaultPin('24682468');
        await bibliothek.db.fuehreAus(const PersonAnlegen('pa', 'Person A'));
        await bibliothek.db.fuehreAus(GesichterZuordnen(gesichter, 'pa'));
        await bibliothek.db.fuehreAus(
          AlbumAnlegen('alb', 'Album A', DateTime(2024)),
        );
        await bibliothek.db.fuehreAus(AlbumFuellen('alb', [a1.id]));
        await bibliothek.db.customStatement(
          'UPDATE assets SET latitude = 47.2, longitude = 11.2 WHERE id = ?',
          [a1.id],
        );
      });
      final vorher = await mitDb(
        tester,
        () => bibliothek.db.watchAssetsForPerson('pa').first,
      );
      expect(vorher.map((a) => a.id), contains(a1.id));
      await oeffneFoto(tester, a1.id);
      await tippe(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(a1.id))!.isLocked,
        was: 'gesperrt',
      );
      await waitGone(tester, find.byType(AssetViewerScreen));
      // Zeitleiste
      await openSection(tester, Hauptbereich.zeitleiste);
      await settle(tester);
      await waitFor(tester, kachel(ids[1]));
      expect(kachel(a1.id), findsNothing, reason: 'Zeitleiste');
      // Suche
      final treffer = await mitDb(
        tester,
        () => bibliothek.db.searchAssets(
          const SearchFilters(
            textMode: SearchTextMode.filename,
            query: 'person_a_1',
          ),
        ),
      );
      expect(treffer, isEmpty, reason: 'Suche');
      // Album
      await openSection(tester, Hauptbereich.alben);
      await tippe(tester, find.text('Album A').first);
      await waitFor(tester, find.byType(AlbumDetailScreen));
      await settle(tester);
      expect(kachel(a1.id), findsNothing, reason: 'Album');
      await alleZurueck(tester);
      // Personen
      await openSection(tester, Hauptbereich.personen);
      await tippe(
        tester,
        find
            .descendant(
              of: find.byType(PeopleScreen),
              matching: find.text('Person A'),
            )
            .first,
      );
      await waitFor(tester, find.byType(PersonDetailScreen));
      await waitFor(tester, kachel(ids[1]));
      final inPerson = [
        for (final e
            in find
                .descendant(
                  of: find.byType(PersonDetailScreen),
                  matching: find.byType(AssetThumbnailTile),
                )
                .evaluate())
          (e.widget as AssetThumbnailTile).asset.id,
      ];
      print('IMP-193: Person A zeigt $inPerson');
      expect(inPerson, isNot(contains(a1.id)), reason: 'Personen');
      expect(inPerson, containsAll([ids[1], ids[2]]));
      await alleZurueck(tester);
      // Karte
      final mitOrt = await mitDb(
        tester,
        () => bibliothek.db.assetsWithLocation(),
      );
      expect(mitOrt.map((a) => a.id), isNot(contains(a1.id)), reason: 'Karte');
      await openSection(tester, Hauptbereich.karte);
      await waitFor(tester, find.byType(MapScreen));
      await settle(tester);
      expect(tester.takeException(), isNull);
      print('IMP-193: Karte mit ${kacheln.abgerufen} Kacheln');
      // Gesperrter Ordner
      await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
      await tippe(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.byType(LockedFolderScreen));
      // Unter „Fotos“ genau dieses eine Foto (die Kacheln dort tragen den
      // Knopf „Aus dem gesperrten Ordner entfernen“).
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.byTooltip(de.gesperrtEntfernen),
        ),
      );
      expect(
        find
            .descendant(
              of: find.byType(LockedFolderScreen),
              matching: find.byTooltip(de.gesperrtEntfernen),
            )
            .evaluate()
            .length,
        1,
      );
      expect(
        await mitDb(
          tester,
          () async => (await bibliothek.db.select(bibliothek.db.assets).get())
              .where((x) => x.isLocked && !x.isTrashed)
              .map((x) => x.id)
              .toList(),
        ),
        [a1.id],
      );
      await alleZurueck(tester);
      // Original verschlüsselt
      final gesperrt = (await mitDb(
        tester,
        () => bibliothek.db.assetById(a1.id),
      ))!;
      final roh = bibliothek.paths
          .absolute(gesperrt.relativePath)
          .readAsBytesSync();
      expect(roh.take(3).toList(), [0x50, 0x56, 0x45], reason: 'PVE');
      img.Image? alsBild;
      try {
        alsBild = img.decodeImage(roh);
      } catch (_) {}
      expect(alsBild, isNull, reason: 'nicht als Bild lesbar');
      await ende(tester);
    },
    timeout: frist,
  );

  testWidgets('GRU-162 Gesichter und CLIP nacheinander, Orte läuft mit', (
    tester,
  ) async {
    filtereSemantik();
    await starte(
      tester,
      modelle: dateienVon([
        ModelCatalog.faceDetection,
        ModelCatalog.faceRecognition,
        ModelCatalog.clip,
      ]),
    );
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    const n = 40;
    await importiere(
      tester,
      grosseFotos(n, stamm: 'k', breite: 1600, hoehe: 1200, mitOrt: true),
    );
    expect(bibliothek.maxGleichzeitig, 1);
    expect(bibliothek.faceDetectionAvailable, isTrue);
    expect(bibliothek.clipAvailable, isTrue);
    await bibliothek.db.customStatement(
      'UPDATE assets SET latitude = NULL, longitude = NULL, gps_geprueft = 0',
    );
    await aufgabenOeffnen(tester);
    final g = await aufgabe(tester, de.werkzGesichterScannenTitel);
    await aktion(tester, g, de.aufgModusAlle);
    await tester.pump(const Duration(milliseconds: 200));
    final lg = bibliothek.lauf('gesichter')!;
    final e = await aufgabe(tester, de.aufgEmbeddingsTitel);
    await aktion(tester, e, de.aufgModusAlle);
    await tester.pump(const Duration(milliseconds: 200));
    final le = bibliothek.lauf('embeddings')!;
    print(
      'GRU-162: Gesichter läuft ${lg.laeuft} (${lg.erledigt}/${lg.gesamt}), '
      'CLIP wartet ${le.wartet}',
    );
    expect(lg.laeuft, isTrue, reason: 'Gesichter läuft noch');
    expect(le.wartet, isTrue, reason: 'CLIP wartet');
    expect(zahl(tester, e, de.aufgWartend), '1');
    // Gegenprobe: Orte (ohne Modell) läuft sofort mit.
    final o = await aufgabe(tester, de.aufgOrteTitel);
    await aktion(tester, o, de.aufgModusAlle);
    await tester.pump(const Duration(milliseconds: 200));
    final lo = bibliothek.lauf('orte');
    print('GRU-162: Orte läuft ${lo?.laeuft}, beendet ${lo?.beendet}');
    expect(lo != null && (lo.laeuft || lo.beendet), isTrue);
    expect(le.wartet || lg.beendet, isTrue, reason: 'CLIP wartet weiter');
    // CLIP startet von selbst, sobald Gesichter fertig ist.
    await eventually(
      tester,
      () async => lg.beendet,
      timeout: const Duration(minutes: 6),
      was: 'Gesichter fertig',
    );
    await eventually(
      tester,
      () async => le.gestartet,
      timeout: const Duration(seconds: 60),
      was: 'CLIP startet von selbst',
    );
    await eventually(
      tester,
      () async => le.beendet,
      timeout: const Duration(minutes: 6),
      was: 'CLIP fertig',
    );
    final mitEinbettung = await mitDb(
      tester,
      () => bibliothek.db
          .customSelect('SELECT count(*) AS n FROM image_embeddings')
          .getSingle(),
    );
    final gescannt = (await aufnahmen(
      tester,
    )).where((a) => a.facesScanned).length;
    print(
      'GRU-162: Einbettungen ${mitEinbettung.read<int>('n')}, '
      'gescannt $gescannt, Gesichter-Lauf ${lg.erfolgreich}, '
      'CLIP-Lauf ${le.erfolgreich}',
    );
    expect(mitEinbettung.read<int>('n'), n);
    expect(gescannt, n);
    expect(lg.erfolgreich && le.erfolgreich, isTrue);
    await ende(tester);
  }, timeout: frist);

  testWidgets('IMP-189 IMP-190 Papierkorb-Ablauf beim echten Neustart', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    await importiere(tester, [
      testfoto('alt100.jpg'),
      testfoto('alt8.jpg'),
      testfoto('neu1.jpg'),
      testfoto('gesperrt8.jpg'),
    ]);
    final a100 = await aufnahme(tester, 'alt100.jpg');
    final a8 = await aufnahme(tester, 'alt8.jpg');
    final n1 = await aufnahme(tester, 'neu1.jpg');
    final g8 = await aufnahme(tester, 'gesperrt8.jpg');
    File datei(AssetData a) => bibliothek.paths.absolute(a.relativePath);

    // IMP-190: Ablauf aus, Foto seit 100 Tagen im Papierkorb; Neustart,
    // dann einige Minuten warten.
    await befehl(tester, InDenPapierkorb([a100.id], zeit: vorTagen(100)));
    expect(
      (await mitDb(
            tester,
            () => bibliothek.db.trashSettingsRow(),
          ))?.autoDeleteEnabled ??
          false,
      isFalse,
    );
    await neustart(tester);
    schritt = 'IMP-190 warten';
    await warte(tester, const Duration(minutes: 3));
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a100.id)))?.isTrashed,
      isTrue,
      reason: 'ohne aktiven Ablauf bleibt es',
    );
    expect(datei(a100).existsSync(), isTrue);

    // IMP-189: 7 Tage; 8 Tage alt, 1 Tag alt, gesperrt 8 Tage alt.
    await mitDb(tester, () async {
      await bibliothek.db.fuehreAus(
        const PapierkorbFristSetzen(an: true, tage: 7),
      );
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([a8.id], zeit: vorTagen(8)),
      );
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([n1.id], zeit: vorTagen(1)),
      );
      await bibliothek.setupVaultPin('24682468');
      await bibliothek.lockAsset(g8);
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([g8.id], zeit: vorTagen(8)),
      );
    });
    final g8vorher = (await mitDb(
      tester,
      () => bibliothek.db.assetById(g8.id),
    ))!;
    expect(g8vorher.isLocked && g8vorher.isTrashed, isTrue);
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a8.id)))?.isTrashed,
      isTrue,
      reason: 'vor dem Neustart noch da',
    );
    final start = DateTime.now();
    await neustart(tester);
    await eventually(
      tester,
      () async => await bibliothek.db.assetById(a8.id) == null,
      timeout: const Duration(seconds: 60),
      was: '8 Tage altes beim Start gelöscht',
    );
    for (final x in [a100, a8, g8vorher]) {
      expect(
        await mitDb(tester, () => bibliothek.db.assetById(x.id)),
        isNull,
        reason: '${x.originalFileName} endgültig gelöscht',
      );
      expect(datei(x).existsSync(), isFalse, reason: x.originalFileName);
    }
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(n1.id)))?.isTrashed,
      isTrue,
      reason: '1 Tag alt bleibt',
    );
    final lauf = (await mitDb(
      tester,
      () => bibliothek.db.trashSettingsRow(),
    ))!.lastPurgeAt;
    print('IMP-189: Start $start, letzter Lauf $lauf');
    expect(lauf, isNotNull);
    expect(lauf!.isBefore(start.subtract(const Duration(seconds: 1))), isFalse);
    // Papierkorb und gesperrter Papierkorb ansehen.
    await openSection(tester, Hauptbereich.papierkorb);
    await waitFor(tester, find.byType(TrashScreen));
    await eventually(
      tester,
      () async => papierkorbKacheln(tester) == 1,
      was: 'eine Kachel im Papierkorb',
    );
    await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
    await tippe(tester, find.text(de.einstGesperrtOeffnen));
    if (find.text(de.pinEingebenTitel).evaluate().isNotEmpty) {
      await enter(tester, find.byType(TextField).last, '24682468');
      await tippe(tester, knopf('OK'));
    }
    await waitFor(tester, find.byType(LockedFolderScreen));
    await tippe(
      tester,
      find
          .descendant(
            of: find.byType(LockedFolderScreen),
            matching: find.text(de.gesperrtTabPapierkorb),
          )
          .hitTestable(),
    );
    await waitFor(tester, find.text(de.gesperrtPapierkorbLeer));
    await alleZurueck(tester);
    await einstellungsgruppe(tester, de.einstAbschnittPapierkorb);
    await waitFor(tester, find.text(de.einstLetzterLauf));
    final ctx = tester.element(find.byType(SettingsScreen));
    final sprache = Localizations.localeOf(ctx).toString();
    final zeit =
        '${DateFormat.yMd(sprache).format(lauf)} – '
        '${DateFormat.Hm(sprache).format(lauf)}';
    expect(find.text(zeit), findsOneWidget, reason: '„Letzter Lauf“ $zeit');
    await ende(tester);
  }, timeout: frist);

  testWidgets('IMP-100 Überwachter Ordner auf ausgeworfenem Datenträger', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    // Der Datenträger: ein Disk-Image (siehe Kopf der Datei).
    final z = await tester.runAsync(() => steuer('POST', '/einstecken'));
    expect(z!['eingesteckt'], isTrue, reason: 'Steuerung $steuerAdresse');
    addTearDown(() async {
      try {
        await steuer('POST', '/auswerfen');
      } catch (_) {}
    });
    await tester.runAsync(() async {
      await steuer('POST', '/leeren');
      for (final n in ['w1.jpg', 'w2.jpg']) {
        await steuer(
          'PUT',
          '/datei/$n',
          inhalt: testfoto(n, datum: DateTime(2020, 6, 1)).readAsBytesSync(),
        );
      }
    });
    melde.verlaufLeeren();
    await einstellungsgruppe(tester, de.einstUeberwachtTitel);
    dialog.ordner = wechselOrdner;
    await tippe(tester, find.text(de.einstUeberwachtWaehlen));
    await eventually(
      tester,
      () async =>
          melde.verlauf.any((m) => m.text == de.einstUeberwachtUebernommen(2)),
      was: 'zwei Fotos vom Datenträger übernommen',
    );
    expect(await aufnahmen(tester), hasLength(2));
    final vorher = {for (final a in await aufnahmen(tester)) a.id};

    // Auswerfen.
    melde.verlaufLeeren();
    final aus = await tester.runAsync(() => steuer('POST', '/auswerfen'));
    print('IMP-100: ausgeworfen $aus');
    expect(aus!['eingesteckt'], isFalse);
    expect(Directory(wechselOrdner).existsSync(), isFalse);
    // Fünf Minuten warten (der Ordner wird alle fünf Minuten angesehen).
    schritt = 'IMP-100 fünf Minuten';
    await warte(tester, const Duration(minutes: 5, seconds: 30));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect({for (final a in await aufnahmen(tester)) a.id}, vorher);
    print('IMP-100: Meldungen nach 5 min: ${melde.verlauf.map((m) => m.text)}');
    expect(
      melde.verlauf.where((m) => m.art == Meldungsart.fehler),
      isEmpty,
      reason: 'keine Fehlermeldung',
    );
    // App neu starten, solange er fehlt.
    await neustart(tester);
    await warte(tester, const Duration(seconds: 10));
    expect(find.byType(HomeShell), findsOneWidget);
    expect({for (final a in await aufnahmen(tester)) a.id}, vorher);
    expect(
      melde.verlauf.where((m) => m.art == Meldungsart.fehler),
      isEmpty,
      reason: 'keine Fehlermeldung nach dem Neustart',
    );
    // Wieder eingesteckt, ein neues Foto darauf: geht weiter.
    await tester.runAsync(() async {
      await steuer('POST', '/einstecken');
      await steuer(
        'PUT',
        '/datei/w3.jpg',
        inhalt: testfoto(
          'w3.jpg',
          datum: DateTime(2020, 6, 3),
        ).readAsBytesSync(),
      );
    });
    await neustart(tester);
    await eventually(
      tester,
      () async => (await bibliothek.db.select(bibliothek.db.assets).get()).any(
        (a) => a.originalFileName == 'w3.jpg',
      ),
      timeout: const Duration(seconds: 60),
      was: 'w3.jpg nach dem Wiedereinstecken',
    );
    expect(await aufnahmen(tester), hasLength(3));
    await tester.runAsync(() => steuer('POST', '/auswerfen'));
    await ende(tester);
  }, timeout: frist);

  testWidgets('ANS-101 Gesprochenes in Videos mit echter Spracherkennung', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester, modelle: dateienVon([ModelCatalog.spracherkennung]));
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    expect(bibliothek.spracherkennungAvailable, isTrue);
    await importiere(tester, [
      fixture('r2gru_sprache.mp4'),
      testfoto('still.jpg'),
    ]);
    // Durchgang: „Gesprochenes in Videos“ → „Alle“.
    await aufgabenOeffnen(tester);
    final k = await aufgabe(tester, de.aufgTranskripteTitel);
    await aktion(tester, k, de.aufgModusAlle);
    await eventually(
      tester,
      () async => bibliothek.lauf('transkripte')?.beendet ?? false,
      timeout: const Duration(minutes: 6),
      was: 'Spracherkennung fertig',
    );
    final v = await aufnahme(tester, 'r2gru_sprache.mp4');
    print('ANS-101: Transkript [${v.transkriptSprache}] ${v.transkript}');
    expect(v.transkript?.toLowerCase(), contains('geburtstag'));
    await alleZurueck(tester);
    await openSection(tester, Hauptbereich.suche);
    final blatt = find.byType(SearchOptionsSheet);
    await tippe(tester, find.byTooltip(de.sucheOptionen).first);
    await waitFor(tester, blatt);
    final typ = find.descendant(
      of: blatt,
      matching: find.text(de.suchoptTypTranskript),
    );
    await waitFor(tester, typ);
    await tester.ensureVisible(typ.first);
    await tippe(tester, typ.first);
    expect(
      find.descendant(
        of: blatt,
        matching: find.text(de.suchoptTranskriptFehlt),
      ),
      findsNothing,
    );
    final feld = find.descendant(
      of: blatt,
      matching: find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == de.suchoptHintTranskript,
      ),
    );
    await enter(tester, feld, 'Geburtstag');
    await tippe(
      tester,
      find.descendant(
        of: blatt,
        matching: find.widgetWithText(FilledButton, de.suchoptSuchen),
      ),
    );
    await waitGone(tester, blatt);
    await waitFor(tester, kachelName('r2gru_sprache.mp4'));
    final treffer = [
      for (final e
          in find
              .descendant(
                of: find.byType(SearchScreen),
                matching: find.byType(AssetThumbnailTile),
              )
              .evaluate())
        (e.widget as AssetThumbnailTile).asset.originalFileName,
    ];
    expect(treffer, ['r2gru_sprache.mp4']);
    // Ohne Modell: der Hinweis unter dem Feld.
    await ende(tester);
    await starte(tester);
    await openSection(tester, Hauptbereich.suche);
    await tippe(tester, find.byTooltip(de.sucheOptionen).first);
    await waitFor(tester, blatt);
    final typ2 = find.descendant(
      of: blatt,
      matching: find.text(de.suchoptTypTranskript),
    );
    await waitFor(tester, typ2);
    await tester.ensureVisible(typ2.first);
    await tippe(tester, typ2.first);
    await waitFor(
      tester,
      find.descendant(
        of: blatt,
        matching: find.text(de.suchoptTranskriptFehlt),
      ),
    );
    await ende(tester);
  }, timeout: frist);

  testWidgets('ANS-107 Dateiformat mit HEIC, JPG, PNG und zwei RAW', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    final png = File(p.join(eingang.path, 'grafik.png'))
      ..writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 48)));
    await importiere(tester, [
      testfoto('bild1.jpg', datum: DateTime(2025, 4, 1)),
      testfoto('bild2.jpg', datum: DateTime(2025, 4, 2)),
      mlFixture('heic/sonnenblume.heic'),
      mlFixture('heic/zebra.heic'),
      png,
      // Die RAW-Proben liegen nicht im Git (test/fixtures/samples des
      // Hauptordners); Kopien unter pruefkatalog/fixtures/r2gru.
      for (final n in ['canon_eos_r10.cr3', 'sony_ilce6300.arw'])
        File(
          p.join(fixturesOrdner, 'r2gru', n),
        ).copySync(p.join(eingang.path, n)),
    ]);
    final alle = await aufnahmen(tester);
    print('ANS-107: ${[for (final a in alle) a.originalFileName]}');
    expect(alle, hasLength(7));
    await openSection(tester, Hauptbereich.suche);
    final blatt = find.byType(SearchOptionsSheet);
    Finder scroller() =>
        find.descendant(of: blatt, matching: find.byType(Scrollable)).first;
    Future<void> oeffnen() async {
      await tippe(tester, find.byTooltip(de.sucheOptionen).first);
      await waitFor(tester, blatt);
      await settle(tester);
    }

    Future<List<String?>> formate() async {
      final titel = find.descendant(
        of: blatt,
        matching: find.text(de.suchoptDateiformat),
      );
      await tester.scrollUntilVisible(
        titel,
        200,
        scrollable: scroller(),
        maxScrolls: 60,
      );
      final chips = find.descendant(
        of: find.ancestor(of: titel, matching: find.byType(Column)).first,
        matching: find.byType(FilterChip),
      );
      await tester.ensureVisible(chips.first);
      await tester.pump();
      return [
        for (final e in chips.evaluate())
          ((e.widget as FilterChip).label as Text).data,
      ];
    }

    Future<void> chip(String text) async {
      final f = find.descendant(
        of: blatt,
        matching: find.widgetWithText(FilterChip, text),
      );
      await tester.ensureVisible(f.first);
      await tester.pump();
      await tester.tap(f.first);
      await settle(tester, max: const Duration(seconds: 2));
    }

    Future<void> suchen() async {
      await tippe(
        tester,
        find.descendant(
          of: blatt,
          matching: find.widgetWithText(FilledButton, de.suchoptSuchen),
        ),
      );
      await waitGone(tester, blatt);
      await settle(tester);
    }

    List<String> treffer() => [
      for (final e
          in find
              .descendant(
                of: find.byType(SearchScreen),
                matching: find.byType(AssetThumbnailTile),
              )
              .evaluate())
        (e.widget as AssetThumbnailTile).asset.originalFileName,
    ]..sort();

    await oeffnen();
    final chips = await formate();
    print('ANS-107: Formate $chips');
    expect(chips.toSet(), {
      de.suchoptNurRaw,
      'JPG',
      'HEIC',
      'PNG',
      'CR3',
      'ARW',
    }, reason: 'nur vorhandene Formate');
    await chip('JPG');
    await chip('HEIC');
    await suchen();
    expect(treffer(), [
      'bild1.jpg',
      'bild2.jpg',
      'sonnenblume.heic',
      'zebra.heic',
    ], reason: 'JPG oder HEIC');
    await oeffnen();
    await tippe(tester, find.text(de.suchoptAllesLeeren));
    await formate();
    await chip(de.suchoptNurRaw);
    final nachRaw = {
      for (final e
          in find
              .descendant(of: blatt, matching: find.byType(FilterChip))
              .evaluate())
        if ((e.widget as FilterChip).selected)
          ((e.widget as FilterChip).label as Text).data,
    };
    print('ANS-107: nach „Nur RAW“ gewählt $nachRaw');
    expect(nachRaw, containsAll(['CR3', 'ARW']));
    expect(nachRaw.intersection({'JPG', 'HEIC', 'PNG'}), isEmpty);
    await suchen();
    expect(treffer(), ['canon_eos_r10.cr3', 'sony_ilce6300.arw']);
    await tippe(tester, find.byTooltip(de.sucheSpeichernTitel));
    await enter(tester, field(de.allgName), 'Nur Rohdaten');
    await tippe(tester, find.text(de.allgSpeichern));
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.suche);
    await tippe(tester, find.widgetWithText(InputChip, 'Nur Rohdaten'));
    await settle(tester);
    expect(treffer(), ['canon_eos_r10.cr3', 'sony_ilce6300.arw']);
    // Zweite Bibliothek nur mit JPG.
    await ende(tester);
    await starte(tester);
    await importiere(tester, [testfoto('nur.jpg')]);
    await openSection(tester, Hauptbereich.suche);
    await oeffnen();
    final chips2 = await formate();
    print('ANS-107: zweite Bibliothek $chips2');
    expect(chips2, isNot(contains(de.suchoptNurRaw)));
    expect(chips2, ['JPG']);
    await ende(tester);
  }, timeout: frist);

  // Behoben in #410: Die Stadt ist schon nach der Landeswahl wählbar (Städte
  // des Landes), und der Hinweis „Noch keine Orte aufgelöst“ hängt an den
  // aufgelösten Orten statt am geladenen Datensatz.
  testWidgets(
    'ANS-108 Ortsfilter mit GeoNames-Datensatz, aufgelöst über die Aufgabe',
    (tester) async {
      filtereSemantik();
      final befunde = <String>[];
      for (var durchgang = 1; durchgang <= 2; durchgang++) {
        final (stadtNachLand, hinweisOhneOrte) = await _ans108(tester);
        print(
          'ANS-108 Durchgang $durchgang: Stadt nach Landeswahl offen '
          '$stadtNachLand, Hinweis ohne aufgelöste Orte $hinweisOhneOrte',
        );
        if (!stadtNachLand) befunde.add('$durchgang: Stadt gesperrt');
        if (!hinweisOhneOrte) befunde.add('$durchgang: kein Hinweis');
      }
      expect(befunde, isEmpty);
    },
    timeout: frist,
  );

  testWidgets(
    'GRU-184 Teil 1: Meldungen im Verlauf, Bibliothek bleibt liegen',
    (tester) async {
      filtereSemantik();
      await starte(tester);
      await importiere(tester, [testfoto('gru184.jpg')]);
      melde.verlaufLeeren();
      // Eine Meldung der App (Werkzeuge → Sichten ohne unbewertete Fotos
      // sind es nicht: das Foto ist unbewertet) und eine zweite.
      melde.hinweis('Probehinweis vor dem Neustart');
      melde.erfolg('Probemeldung vor dem Neustart');
      await tester.pump(const Duration(seconds: 7));
      await settle(tester);
      final glocke = find.byTooltip(de.meldungenGlocke);
      await waitFor(tester, glocke);
      expect(
        find.descendant(of: glocke, matching: find.text('2')),
        findsOneWidget,
      );
      expect(melde.verlauf, hasLength(2));
      // Beenden wie die App: Arbeit anhalten, Datenbank zu. Die Bibliothek
      // bleibt für den zweiten Prozess liegen (im Temp-Ordner des
      // Testplatzes, Teil 2 räumt sie weg).
      await halteAn(tester, bibliothek);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      await bibliothek.vorDemBeenden();
      final ablage = Directory(
        p.join(Directory.systemTemp.path, 'pv_r2gru_neustart'),
      );
      if (ablage.existsSync()) ablage.deleteSync(recursive: true);
      ablage.createSync(recursive: true);
      for (final s in ['', '-wal', '-shm']) {
        final f = File(p.join(anker.path, 'library.sqlite$s'));
        if (f.existsSync()) f.copySync(p.join(ablage.path, 'library.sqlite$s'));
      }
      await Process.run('/bin/cp', [
        '-R',
        bibliothek.paths.root.path,
        p.join(ablage.path, 'library'),
      ]);
      File(
        p.join(ablage.path, 'marke.json'),
      ).writeAsStringSync(jsonEncode({'aufnahmen': 1, 'meldungen': 2}));
      print('GRU-184 Teil 1: Bibliothek abgelegt unter ${ablage.path}');
      await finish(tester);
    },
    timeout: frist,
  );
}

/// Für die übrigen Dateien der Runde.
const uuid = Uuid();

// ignore_for_file: avoid_print
// **Gemeinsame Hilfen für die Katalog-Prüfungen**
// (integration_test/katalog_*_test.dart).
//
// Jede Prüfung startet die echte App – denselben Widgetbaum wie
// `main.dart` – aber mit einer frischen Wegwerf-Bibliothek in einem
// Temp-Ordner. Der Datenordner wird über
// [LibraryLocation.nutzeFuerTests] umgelenkt, **bevor** irgendetwas ihn
// erfragt: So bestimmt die App ihn nie selbst, und weder die
// Produktiv-App noch der Testbau „Photo Vault (Test)“ samt ihrer
// Bibliotheken werden berührt.
//
// Laufen lassen nur über die Warteschlange des Prüfkatalogs (eigene
// Plätze mit eigener Kennung `de.dasevo.photovault.e2e<n>`), nie direkt
// mit `flutter test -d macos` im Hauptordner.
//
// Was die Warteschlange über `--dart-define` hereingibt:
//   PV_KATALOG_FIXTURES  Ordner mit vorbereiteten Testdateien (Videos …)
//   PV_KATALOG_REPO      Wurzel des Repos (für test/fixtures)
//   PV_KATALOG_SERVER    Adresse eines frischen Wegwerf-Servers, falls
//                        der Lauf einen braucht
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Rational ist nicht öffentlich ausgeführt, die GPS-Grade brauchen es.
// ignore: implementation_imports
import 'package:image/src/util/rational.dart' show Rational;
import 'package:intl/date_symbol_data_local.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/bildwerkzeuge.dart' show Bildwerkzeuge;
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/services/bilddekodierung.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/native_image_converter.dart'
    show AppBildwerkzeuge;
import 'package:photo_vault/services/platform/folder_access_desktop.dart';
import 'package:photo_vault/services/serversperre.dart';
import 'package:photo_vault/services/tokenablage.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/zierbaum_farben.dart'
    show zierschriftenLizenzenAnmelden;
import 'package:photo_vault/widgets/mini_location_map.dart'
    show kartenSpeicherEinrichten;
import 'package:provider/provider.dart';

import '../test/hilfen/dateidialog.dart' show NachgestellteDatei;

export 'package:photo_vault/screens/home_shell.dart' show Hauptbereich;

/// Die deutschen Texte der App, z. B. `de.importierenTooltip`.
final AppTexte de = lookupAppTexte(const Locale('de'));

/// Die englischen Texte, für Prüfungen der zweiten Sprache.
final AppTexte en = lookupAppTexte(const Locale('en'));

const fixturesOrdner = String.fromEnvironment('PV_KATALOG_FIXTURES');
const repoOrdner = String.fromEnvironment('PV_KATALOG_REPO');
const serverAdresse = String.fromEnvironment('PV_KATALOG_SERVER');
const modellOrdner = String.fromEnvironment('PV_KATALOG_MODELLE');

/// Die Bibliothek der laufenden Prüfung.
late LibraryState bibliothek;

/// Der Datenordner der laufenden Prüfung (Temp-Ordner, wird am Ende
/// gelöscht).
late Directory anker;

/// Der nachgestellte Dateidialog. Vor dem Antippen festlegen, was er
/// zurückgibt: [KatalogDateidialog.dateien], [KatalogDateidialog.ordner],
/// [KatalogDateidialog.speichernUnter].
final dialog = KatalogDateidialog();

var _vorbereitet = false;

/// Was `main()` vor `runApp` erledigt – einmal je Prozess.
Future<void> _vorbereiten() async {
  if (_vorbereitet) return;
  _vorbereitet = true;
  protokollZiel = debugPrint;
  Bildwerkzeuge.standard = const AppBildwerkzeuge();
  MediaKit.ensureInitialized();
  await initializeDateFormatting();
  kartenSpeicherEinrichten();
  bildspeicherEinrichten();
  zierschriftenLizenzenAnmelden();
  richteServersperreEin();
  FilePickerPlatform.instance = dialog;
  _taktgeberStarten();
}

/// Treibt ein Bild an, wenn das System keines liefert.
///
/// Liegt das Fenster eines Testplatzes ganz unter einem anderen (mehrere
/// Plätze laufen gleichzeitig), liefert macOS keine Bildtakte mehr, und
/// `tester.pump` wartet ewig auf das nächste Bild – der Lauf hängt mit
/// 0 % Rechenzeit. Steht ein Bild an und kam seit 400 ms keines, wird es
/// hier von Hand ausgelöst; es ist dasselbe Bild, das der Bildtakt sonst
/// ausgelöst hätte.
void _taktgeberStarten() {
  final b = WidgetsBinding.instance;
  final seitBild = Stopwatch()..start();
  var rohzeit = Duration.zero;
  b.addPersistentFrameCallback((_) {
    rohzeit = b.currentSystemFrameTimeStamp;
    seitBild
      ..reset()
      ..start();
  });
  Timer.periodic(const Duration(milliseconds: 250), (_) {
    // Meldet macOS das Fenster als verborgen, schaltet Flutter die Bilder
    // ab (framesEnabled falsch); dann bleibt scheduleFrame wirkungslos und
    // hasScheduledFrame falsch, während tester.pump weiter auf ein Bild
    // wartet. In diesem Fall trotzdem takten.
    if (!b.hasScheduledFrame && b.framesEnabled) return;
    if (b.schedulerPhase != SchedulerPhase.idle) return;
    if (seitBild.elapsed < const Duration(milliseconds: 400)) return;
    try {
      b.handleBeginFrame(rohzeit + seitBild.elapsed);
      b.handleDrawFrame();
    } catch (e) {
      print('Taktgeber: $e');
    }
  });
}

/// Übergeht Zusicherungen aus dem Rahmenwerk selbst bis zum Ende der
/// Prüfung – nicht aus der App:
///
/// - zum Semantikbaum (`'!child.attached'`, `'node.built'`). Die kommen
///   nur, wenn auf dem Rechner eine Bedienungshilfe die Semantik
///   einschaltet, dann aber bei jedem Bild.
/// - von einem abgebauten `RawTooltip`, der noch am globalen Zeigerweg
///   hängt und beim nächsten Klick einen zweiten Ticker anlegt
///   (raw_tooltip.dart).
void semantikZusicherungenUebergehen() {
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
  addTearDown(() => FlutterError.onError = vorher);
}

/// Startet die App mit einer frischen Bibliothek.
///
/// [fotos] werden ohne Oberfläche importiert (schnell, für
/// Vorbedingungen). Wer den Import selbst prüft, nimmt [importiereUeberUi].
/// [sprache]: 'de' (Vorgabe), 'en' oder 'system'.
/// [modelle]: verlinkt die vorab geladenen KI-Modelle (Ordner der
/// Warteschlange, siehe tools/modelle_holen.py) in den Modellordner der
/// Prüfung, bevor die App startet – `true` für alle, oder eine Liste von
/// Dateinamen (z. B. `['face_detection_yunet.onnx']`).
Future<LibraryState> startApp(
  WidgetTester tester, {
  List<File> fotos = const [],
  String sprache = 'de',
  Size groesse = const Size(1400, 900),
  Object modelle = false,
}) async {
  await _vorbereiten();
  await _beende();
  anker = Directory.systemTemp.createTempSync('pv_katalog_');
  // ZUERST: Der Datenordner zeigt in den Temp-Ordner, bevor die App ihn
  // erfragen kann.
  LibraryLocation.nutzeFuerTests(
    anker: anker,
    zugriff: const DesktopFolderAccess(),
  );
  Verbindungsdatei.tokenablage = AppTokenablage(
    Directory(p.join(anker.path, 'tokens')),
  );
  if (modelle != false) {
    verlinkeModelle(modelle is List ? modelle.cast() : null);
  }
  dialog.zuruecksetzen();
  // Scheitert die Prüfung, bevor sie finish ruft, räumt das hier auf.
  addTearDown(_beende);
  await tester.binding.setSurfaceSize(groesse);
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
  _offen = true;
  if (!bibliothek.paths.root.path.startsWith(anker.path)) {
    throw StateError(
      'Bibliothek liegt nicht im Temp-Ordner: ${bibliothek.paths.root.path}',
    );
  }
  await bibliothek.db.setSprache(sprache);
  await settle(tester);
  if (fotos.isNotEmpty) await importiereDirekt(tester, fotos);
  return bibliothek;
}

/// Verlinkt vorab geladene Modelldateien in `<anker>/models` (nur
/// lesend; die Dateien liegen ausserhalb des Sandkastens unter /Volumes).
/// [nur]: bestimmte Dateinamen, sonst alle.
void verlinkeModelle([List<String>? nur]) {
  if (modellOrdner.isEmpty) {
    throw StateError('PV_KATALOG_MODELLE fehlt (nur über die Warteschlange)');
  }
  final ziel = Directory(p.join(anker.path, 'models'))
    ..createSync(recursive: true);
  for (final f in Directory(modellOrdner).listSync().whereType<File>()) {
    final name = p.basename(f.path);
    if (name.endsWith('.teil')) continue;
    if (nur != null && !nur.contains(name)) continue;
    final link = Link(p.join(ziel.path, name));
    if (!link.existsSync()) link.createSync(f.path);
  }
}

/// Beendet die Prüfung: Datenbank schliessen, Widgetbaum leeren,
/// Temp-Ordner löschen.
Future<void> finish(WidgetTester tester) async {
  await _beende();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 200));
  try {
    anker.deleteSync(recursive: true);
  } catch (_) {}
}

/// Ob die Bibliothek der laufenden Prüfung noch offen ist.
var _offen = false;

/// Hält die Hintergrundarbeit an und schliesst die Bibliothek – auch,
/// wenn eine Prüfung mittendrin scheitert (über addTearDown aus
/// [startApp]). Sonst liefe die Arbeit der alten Bibliothek in die
/// nächste Prüfung hinein: Abfragen auf die geschlossene Datenbank, die
/// dem nächsten Test angelastet werden, und Modelle, die nie freikommen.
Future<void> _beende() async {
  if (!_offen) return;
  _offen = false;
  final b = bibliothek;
  try {
    if (b.analyseLaeuft) b.brichHintergrundanalyseAb();
    for (final lauf in b.offeneAufgaben.toList()) {
      b.brichAufgabeAb(lauf.schluessel);
    }
    final ende = DateTime.now().add(const Duration(seconds: 30));
    while (b.etwasLaeuft && DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (b.etwasLaeuft) print('finish: Hintergrundarbeit läuft noch');
    await b.vorDemBeenden();
  } catch (e) {
    print('finish: $e');
  }
}

/// Importiert ohne Oberfläche und wartet, bis alles da ist.
Future<List<String>> importiereDirekt(
  WidgetTester tester,
  List<File> dateien,
) async {
  final ids = <String>[];
  await tester.runAsync(() async {
    await for (final f in bibliothek.importFiles([
      for (final d in dateien) d.path,
    ])) {
      if (f.assetId case final id?) ids.add(id);
    }
  });
  await settle(tester);
  return ids;
}

/// Importiert über den Knopf „Importieren“ und den nachgestellten
/// Dateidialog (einzelne Dateien), bestätigt den Importplan und wartet
/// auf das Ende.
Future<void> importiereUeberUi(WidgetTester tester, List<File> dateien) async {
  dialog.dateien = dateien;
  // Der Knopf in der Leiste trägt den Text als Tooltip; die leere
  // Zeitleiste zeigt ihn als Beschriftung.
  final knopf = find.byTooltip(de.importierenTooltip);
  await tap(tester, _findet(knopf) ? knopf : find.text(de.importierenTooltip));
  await tap(tester, find.text(de.importEinzelneDateien));
  // Importplan „Import prüfen“: warten, bis die Prüfung durch ist und der
  // Startknopf frei wird.
  await waitFor(
    tester,
    find.text(de.importPlanTitel),
    timeout: const Duration(seconds: 30),
  );
  final starten = find.ancestor(
    of: find.text(de.importPlanStarten(dateien.length)),
    matching: find.byType(FilledButton),
  );
  await waitFor(tester, starten, timeout: const Duration(seconds: 60));
  final ende = DateTime.now().add(const Duration(seconds: 60));
  while (tester.widget<FilledButton>(starten).onPressed == null) {
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException('Importplan gibt den Start nicht frei');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.tap(starten);
  await settle(tester);
  await eventually(tester, () async {
    final n = await bibliothek.db.select(bibliothek.db.assets).get();
    return n.length >= dateien.length;
  }, timeout: const Duration(seconds: 120));
  await settle(tester);
}

// --- Testdateien ------------------------------------------------------------

var _zaehler = 0;

/// Ordner für erzeugte Testdateien (im Temp-Ordner der Prüfung).
Directory get eingang =>
    Directory(p.join(anker.path, 'eingang'))..createSync(recursive: true);

/// Erzeugt ein JPEG mit Aufnahmedatum, Kamera und Ort in den EXIF-Daten.
///
/// Jedes Bild ist anders (Farbe und Muster aus einem Zähler), damit die
/// Prüfsummen verschieden sind und der Import keine Dubletten sieht.
/// [gleichWie] macht eine exakte Kopie eines früheren Bildes (Dublette).
File testfoto(
  String name, {
  DateTime? datum,
  double? breitengrad,
  double? laengengrad,
  String? kamera,
  String? modell,
  int breite = 800,
  int hoehe = 600,
  int? muster,
  String? beschreibung,
}) {
  final n = muster ?? ++_zaehler;
  final zufall = math.Random(n);
  final bild = img.Image(width: breite, height: hoehe);
  img.fill(
    bild,
    color: img.ColorRgb8(
      40 + zufall.nextInt(180),
      40 + zufall.nextInt(180),
      40 + zufall.nextInt(180),
    ),
  );
  for (var i = 0; i < 6; i++) {
    final x = zufall.nextInt(breite);
    final y = zufall.nextInt(hoehe);
    img.fillRect(
      bild,
      x1: x,
      y1: y,
      x2: math.min(breite - 1, x + 40 + zufall.nextInt(breite ~/ 3)),
      y2: math.min(hoehe - 1, y + 40 + zufall.nextInt(hoehe ~/ 3)),
      color: img.ColorRgb8(
        zufall.nextInt(256),
        zufall.nextInt(256),
        zufall.nextInt(256),
      ),
    );
  }
  if (datum != null) {
    String z(int v, int s) => v.toString().padLeft(s, '0');
    final text =
        '${z(datum.year, 4)}:${z(datum.month, 2)}:${z(datum.day, 2)} '
        '${z(datum.hour, 2)}:${z(datum.minute, 2)}:${z(datum.second, 2)}';
    bild.exif.exifIfd['DateTimeOriginal'] = text;
    bild.exif.imageIfd['DateTime'] = text;
  }
  if (kamera != null) bild.exif.imageIfd['Make'] = kamera;
  if (modell != null) bild.exif.imageIfd['Model'] = modell;
  if (beschreibung != null) {
    bild.exif.imageIfd['ImageDescription'] = beschreibung;
  }
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
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(bild, quality: 90));
  return datei;
}

/// Eine vorbereitete Datei aus dem Fixtures-Ordner der Warteschlange
/// (z. B. `video_5s.mp4`), in den Eingang kopiert.
File fixture(String name) {
  final quelle = File(p.join(fixturesOrdner, name));
  if (!quelle.existsSync()) {
    throw StateError('Fixture fehlt: ${quelle.path}');
  }
  return quelle.copySync(p.join(eingang.path, name));
}

/// Eine Datei aus `test/fixtures` des Repos, in den Eingang kopiert.
File repoFixture(String relativ) {
  final quelle = File(p.join(repoOrdner, 'test', 'fixtures', relativ));
  if (!quelle.existsSync()) {
    throw StateError('Repo-Fixture fehlt: ${quelle.path}');
  }
  return quelle.copySync(p.join(eingang.path, p.basename(relativ)));
}

// --- Bedienung --------------------------------------------------------------

/// Pumpt, bis nichts mehr ansteht – mit Obergrenze, denn Ladekreise und
/// Videos drehen endlos.
Future<void> settle(
  WidgetTester tester, {
  Duration max = const Duration(seconds: 5),
}) async {
  final ende = DateTime.now().add(max);
  do {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) break;
  } while (DateTime.now().isBefore(ende));
}

/// Ob [finder] etwas findet – auch für `.first`/`.last`, die bei leerem
/// Ergebnis werfen statt leer zu sein.
bool _findet(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Wartet, bis [finder] etwas findet.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (_findet(finder)) return;
  }
  throw TimeoutException(
    'Nicht gefunden: $finder\nAuf dem Bildschirm: ${onScreen(tester)}',
  );
}

/// Wartet, bis [finder] nichts mehr findet.
Future<void> waitGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!_findet(finder)) return;
  }
  throw TimeoutException(
    'Verschwindet nicht: $finder\nAuf dem Bildschirm: ${onScreen(tester)}',
  );
}

/// Wartet, bis [bedingung] wahr ist (echte Zeit, z. B. für Datenbank oder
/// Dateien).
Future<void> eventually(
  WidgetTester tester,
  Future<bool> Function() bedingung, {
  Duration timeout = const Duration(seconds: 30),
  String? was,
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    final ok = await tester.runAsync(bedingung) ?? false;
    if (ok) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    'Bedingung nicht erfüllt${was == null ? '' : ': $was'}\n'
    'Auf dem Bildschirm: ${onScreen(tester)}',
  );
}

/// Tippt auf [finder] (das erste Treffer-Widget) und wartet kurz.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}

/// Tippt auf den Text [text].
Future<void> tapText(WidgetTester tester, String text) =>
    tap(tester, find.text(text));

/// Schreibt [text] in [finder] (ein Textfeld).
Future<void> enter(WidgetTester tester, Finder finder, String text) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.enterText(finder.first, text);
  await settle(tester);
}

/// Das Textfeld mit der Beschriftung oder dem Hinweis [beschriftung].
Finder field(String beschriftung) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      (w.decoration?.labelText == beschriftung ||
          w.decoration?.hintText == beschriftung),
);

/// Scrollt, bis [finder] sichtbar ist (im ersten scrollbaren Bereich, der
/// ihn enthält).
Future<void> scrollTo(WidgetTester tester, Finder finder, {Finder? in_}) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: in_ ?? find.byType(Scrollable).first,
    maxScrolls: 100,
  );
  await settle(tester);
}

/// Öffnet einen Hauptbereich (siehe [Hauptbereich]), wie über die
/// Seitenleiste.
Future<void> openSection(WidgetTester tester, int bereich) async {
  bibliothek.zeigeBereich(bereich);
  await settle(tester);
}

/// Taste drücken, z. B. [LogicalKeyboardKey.escape].
Future<void> key(WidgetTester tester, LogicalKeyboardKey taste) async {
  await tester.sendKeyEvent(taste);
  await settle(tester);
}

/// Zurück (oberste Seite des inneren Navigators schliessen).
Future<void> back(WidgetTester tester) async {
  final zurueck = find.byTooltip(
    const DefaultMaterialLocalizations().backButtonTooltip,
  );
  if (zurueck.evaluate().isNotEmpty) {
    await tap(tester, zurueck.last);
  } else {
    await key(tester, LogicalKeyboardKey.escape);
  }
}

/// Alle Texte auf dem Bildschirm – für Fehlermeldungen.
String onScreen(WidgetTester tester) {
  final texte = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText();
    if (s != null && s.trim().isNotEmpty) texte.add(s.trim());
  }
  for (final e in find.byType(RichText).evaluate()) {
    final s = (e.widget as RichText).text.toPlainText();
    if (s.trim().isNotEmpty && !texte.contains(s.trim())) texte.add(s.trim());
  }
  return texte.take(80).join(' | ');
}

/// Wartet, bis eine Meldung (Snackbar/Hinweis) mit [text] erscheint.
Future<void> erwarteMeldung(WidgetTester tester, String text) =>
    waitFor(tester, find.textContaining(text));

/// Datum relativ zu heute.
DateTime vorTagen(int tage) => DateTime.now().subtract(Duration(days: tage));

// --- Dateidialog ------------------------------------------------------------

/// Der Dateidialog, nachgestellt (siehe test/hilfen/dateidialog.dart).
class KatalogDateidialog extends FilePickerPlatform {
  /// Was „Dateien wählen“ zurückgibt (leer = abgebrochen).
  List<File> dateien = [];

  /// Was „Ordner wählen“ zurückgibt (`null` = abgebrochen).
  String? ordner;

  /// Wohin „Speichern unter“ schreibt (`null` = abgebrochen).
  String? speichernUnter;

  /// Welche Wege gerufen wurden, mit Titel.
  final gerufen = <String>[];

  void zuruecksetzen() {
    dateien = [];
    ordner = null;
    speichernUnter = null;
    gerufen.clear();
  }

  @override
  Future<List<PlatformFile>> pickFiles({
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
  }) async {
    gerufen.add('pickFiles ${dialogTitle ?? ''}');
    return [for (final d in dateien) NachgestellteDatei(d)];
  }

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
  }) async {
    gerufen.add('pickFile ${dialogTitle ?? ''}');
    return dateien.isEmpty ? null : NachgestellteDatei(dateien.first);
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    gerufen.add('getDirectoryPath ${dialogTitle ?? ''}');
    return ordner;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    gerufen.add('saveFile $fileName');
    final ziel = speichernUnter;
    if (ziel == null) return null;
    final datei = File(
      p.extension(ziel).isEmpty ? p.join(ziel, fileName) : ziel,
    );
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(bytes);
    return datei.uri;
  }
}

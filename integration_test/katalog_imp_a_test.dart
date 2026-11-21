// Katalog-Prüfungen IMP-001 bis IMP-113: Import (Einstieg, Prüfung vor dem
// Import, Ablauf und Bilanz, Formate, Live/Motion Photos, Formatstapel,
// Dubletten, Aufnahmedatum, Kameravorgaben, XMP-Beilage, mit Server),
// Überwachter Ordner und XMP-Sidecars einlesen – in der echten macOS-App
// mit Wegwerf-Bibliothek.
//
// Laufen lassen nur über die Warteschlange des Prüfkatalogs:
//   …/pruefkatalog/tools/e2e_queue.sh imp-a integration_test/katalog_imp_a_test.dart
// Die Prüfungen mit Server tragen „MitServer“ im Namen und laufen getrennt:
//   PV_E2E_SERVER=1 PV_E2E_ARGS='--plain-name MitServer' …/e2e_queue.sh imp-a …
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:media_kit_video/media_kit_video.dart' show Video;
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/import_plan_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/screens/xmp_import_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart' show themeModeToString;
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/live_photo_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';

import 'katalog_kit.dart';

// ---------------------------------------------------------------------------
// Hilfen nur für diese Datei
// ---------------------------------------------------------------------------

/// Ein Unterordner im Temp-Ordner der Prüfung.
Directory quellordner(String name) =>
    Directory(p.join(anker.path, 'quellen', name))..createSync(recursive: true);

/// Verschiebt [datei] nach [ordner].
File nach(File datei, Directory ordner, [String? name]) =>
    datei.renameSync(p.join(ordner.path, name ?? p.basename(datei.path)));

String pruefsumme(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Setzt die Änderungszeit zurück (der überwachte Ordner nimmt beim ersten
/// Hinsehen nur, was älter als zwei Minuten ist).
File altern(File f, [Duration um = const Duration(hours: 1)]) {
  f.setLastModifiedSync(DateTime.now().subtract(um));
  return f;
}

Future<T> hintergrund<T>(WidgetTester tester, Future<T> Function() f) async =>
    (await tester.runAsync(f)) as T;

Future<List<AssetData>> _alle() =>
    bibliothek.db.select(bibliothek.db.assets).get();

Future<List<AssetData>> aufnahmen(WidgetTester tester) =>
    hintergrund(tester, _alle);

Future<AssetData> aufnahme(WidgetTester tester, String name) async =>
    (await aufnahmen(tester)).singleWhere((a) => a.originalFileName == name);

Future<List<String>> albenVon(WidgetTester tester, String id) =>
    hintergrund(tester, () async {
      final zeilen = await (bibliothek.db.select(
        bibliothek.db.albumAssets,
      )..where((t) => t.assetId.equals(id))).get();
      final namen = <String>[];
      for (final z in zeilen) {
        final a = await (bibliothek.db.select(
          bibliothek.db.albums,
        )..where((t) => t.id.equals(z.albumId))).getSingleOrNull();
        if (a != null) namen.add(a.name);
      }
      return namen;
    });

Future<List<String>> tagsVon(WidgetTester tester, String id) =>
    hintergrund(tester, () async {
      return [for (final t in await bibliothek.db.tagsForAsset(id)) t.name];
    });

Future<void> befehl(WidgetTester tester, Befehl<Object?> b) =>
    hintergrund(tester, () async {
      await bibliothek.db.fuehreAus(b);
    });

/// Wartet, bis einer der [finder] etwas findet, und gibt dessen Stelle.
Future<int> warteAufEines(
  WidgetTester tester,
  List<Finder> finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < finder.length; i++) {
      if (finder[i].evaluate().isNotEmpty) return i;
    }
  }
  throw TimeoutException(
    'Keines gefunden: $finder\nAuf dem Bildschirm: ${onScreen(tester)}',
  );
}

/// Pumpt [dauer] lang in echter Zeit.
Future<void> warte(WidgetTester tester, Duration dauer) async {
  final ende = DateTime.now().add(dauer);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

// --- Testdateien -------------------------------------------------------------

var _eigene = 0;

/// Ein JPEG mit frei gesetzten EXIF-Texten – auch solchen, die [testfoto]
/// nicht schreiben kann („0000:00:00 00:00:00“, Zeitzone).
File eigenesFoto(
  String name, {
  String? aufnahme,
  String? versatz,
  String? kamera,
  String? modell,
  int breite = 320,
  int hoehe = 240,
}) {
  final n = ++_eigene;
  final bild = img.Image(width: breite, height: hoehe);
  img.fill(
    bild,
    color: img.ColorRgb8(20 + (n * 37) % 200, 60 + (n * 53) % 180, 140),
  );
  img.fillRect(
    bild,
    x1: 5 + n % 50,
    y1: 5,
    x2: breite ~/ 2,
    y2: hoehe ~/ 2,
    color: img.ColorRgb8((n * 91) % 255, 30, 200),
  );
  if (aufnahme != null) {
    bild.exif.exifIfd['DateTimeOriginal'] = aufnahme;
    bild.exif.imageIfd['DateTime'] = aufnahme;
  }
  if (versatz != null) bild.exif.exifIfd[0x9011] = img.IfdValueAscii(versatz);
  if (kamera != null) bild.exif.imageIfd['Make'] = kamera;
  if (modell != null) bild.exif.imageIfd['Model'] = modell;
  return File(p.join(eingang.path, name))
    ..writeAsBytesSync(img.encodeJpg(bild, quality: 85));
}

/// Ein PNG ohne Angaben.
File pngFoto(String name) {
  final bild = img.Image(width: 64, height: 48);
  img.fill(bild, color: img.ColorRgb8(10, 200, 90));
  return File(p.join(eingang.path, name))
    ..writeAsBytesSync(img.encodePng(bild));
}

/// Eine Datei aus den Bytes am Ende dieser Datei.
File ausBase64(String name, String daten) =>
    File(p.join(eingang.path, name))..writeAsBytesSync(base64Decode(daten));

/// Ein XMP-Paket wie von Lightroom/darktable.
String xmpPaket({
  int? bewertung,
  String? farbe,
  String? beschreibung,
  List<String> tags = const [],
  double? breite,
  double? laenge,
  List<({String name, double x, double y, double w, double h})> regionen =
      const [],
}) {
  String gps(double wert, String plus, String minus) {
    final w = wert.abs();
    final grad = w.floor();
    final minuten = (w - grad) * 60;
    return '$grad,${minuten.toStringAsFixed(4)}${wert < 0 ? minus : plus}';
  }

  final attribute = [
    'xmlns:xmp="http://ns.adobe.com/xap/1.0/"',
    'xmlns:dc="http://purl.org/dc/elements/1.1/"',
    'xmlns:exif="http://ns.adobe.com/exif/1.0/"',
    'xmlns:mwg-rs="http://www.metadataworkinggroup.com/schemas/regions/"',
    'xmlns:stArea="http://ns.adobe.com/xmp/sType/Area#"',
    if (bewertung != null) 'xmp:Rating="$bewertung"',
    if (farbe != null) 'xmp:Label="$farbe"',
    if (breite != null) 'exif:GPSLatitude="${gps(breite, 'N', 'S')}"',
    if (laenge != null) 'exif:GPSLongitude="${gps(laenge, 'E', 'W')}"',
  ].join(' ');
  final kinder = StringBuffer();
  if (beschreibung != null) {
    kinder.write(
      '<dc:description><rdf:Alt><rdf:li xml:lang="x-default">'
      '$beschreibung</rdf:li></rdf:Alt></dc:description>',
    );
  }
  if (tags.isNotEmpty) {
    kinder.write('<dc:subject><rdf:Bag>');
    for (final t in tags) {
      kinder.write('<rdf:li>$t</rdf:li>');
    }
    kinder.write('</rdf:Bag></dc:subject>');
  }
  if (regionen.isNotEmpty) {
    kinder.write('<mwg-rs:Regions rdf:parseType="Resource">');
    kinder.write('<mwg-rs:RegionList><rdf:Bag>');
    for (final r in regionen) {
      kinder.write(
        '<rdf:li rdf:parseType="Resource">'
        '<mwg-rs:Area stArea:x="${r.x}" stArea:y="${r.y}" '
        'stArea:w="${r.w}" stArea:h="${r.h}" stArea:unit="normalized"/>'
        '<mwg-rs:Name>${r.name}</mwg-rs:Name>'
        '<mwg-rs:Type>Face</mwg-rs:Type></rdf:li>',
      );
    }
    kinder.write('</rdf:Bag></mwg-rs:RegionList></mwg-rs:Regions>');
  }
  return '<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>'
      '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
      '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description rdf:about="" $attribute>$kinder</rdf:Description>'
      '</rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
}

/// Setzt ein APP1-Segment mit [xmp] hinter die APPn-Segmente des JPEG.
Uint8List mitXmpSegment(Uint8List jpeg, String xmp) {
  var pos = 2;
  while (pos + 4 < jpeg.length &&
      jpeg[pos] == 0xFF &&
      jpeg[pos + 1] >= 0xE0 &&
      jpeg[pos + 1] <= 0xEF) {
    pos += 2 + ((jpeg[pos + 2] << 8) | jpeg[pos + 3]);
  }
  final nutz = [
    ...ascii.encode('http://ns.adobe.com/xap/1.0/'),
    0,
    ...utf8.encode(xmp),
  ];
  final laenge = nutz.length + 2;
  return Uint8List.fromList([
    ...jpeg.sublist(0, pos),
    0xFF,
    0xE1,
    laenge >> 8,
    laenge & 0xFF,
    ...nutz,
    ...jpeg.sublist(pos),
  ]);
}

// --- Import über die Oberfläche --------------------------------------------

/// Der Knopf „Importieren“ unten in der Seitenleiste – das Symbol, denn
/// die eingeklappte Leiste zeigt nur das, und die Mitte der ganzen Zeile
/// liegt dann schon über dem Inhalt.
Finder get leistenImport => find.descendant(
  of: find.ancestor(
    of: find.text(de.navImportieren),
    matching: find.byType(InkWell),
  ),
  matching: find.byIcon(Icons.add_photo_alternate_outlined),
);

Future<void> oeffneImportdialog(WidgetTester tester) async {
  await tap(tester, leistenImport.first);
  await waitFor(tester, find.text(de.importWasTitel));
}

/// Schliesst den Dialog „Was möchtest du importieren?“ mit einem Klick
/// daneben.
Future<void> schliesseDialog(WidgetTester tester) async {
  await tester.tapAt(const Offset(8, 8));
  await settle(tester);
  await waitGone(tester, find.text(de.importWasTitel));
}

final _pruefFortschritt = RegExp(r'^\d+ von \d+ Dateien geprüft$');

Future<void> warteAufPlan(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  await waitFor(
    tester,
    find.text(de.importPlanTitel),
    timeout: const Duration(seconds: 60),
  );
  await waitGone(
    tester,
    find.textContaining(_pruefFortschritt),
    timeout: timeout,
  );
  await settle(tester);
}

Future<void> planMitDateien(
  WidgetTester tester,
  List<File> dateien, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  dialog.dateien = dateien;
  await oeffneImportdialog(tester);
  await tap(tester, find.text(de.importEinzelneDateien));
  await warteAufPlan(tester, timeout: timeout);
}

Future<void> planMitOrdner(
  WidgetTester tester,
  Directory ordner, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  dialog.ordner = ordner.path;
  await oeffneImportdialog(tester);
  await tap(tester, find.text(de.importGanzerOrdner));
  await warteAufPlan(tester, timeout: timeout);
}

typedef Planzeile = ({String text, bool gewaehlt, bool waehlbar});

/// Die Zeilen von „Import prüfen“: Dateiname → Status und Haken.
Map<String, Planzeile> planzeilen(WidgetTester tester) => {
  for (final e
      in find
          .descendant(
            of: find.byType(ImportPlanScreen),
            matching: find.byType(CheckboxListTile),
          )
          .evaluate())
    ((e.widget as CheckboxListTile).title! as Text).data!: (
      text: ((e.widget as CheckboxListTile).subtitle! as Text).data!,
      gewaehlt: (e.widget as CheckboxListTile).value ?? false,
      waehlbar: (e.widget as CheckboxListTile).onChanged != null,
    ),
};

String status(Planzeile z) => z.text.split('\n').first;

Finder startknopf(int n) => find.ancestor(
  of: find.text(de.importPlanStarten(n)),
  matching: find.byType(FilledButton),
);

bool frei(WidgetTester tester, Finder knopf) =>
    tester.widget<FilledButton>(knopf).onPressed != null;

Future<void> starteKnopf(WidgetTester tester, Finder knopf) async {
  await waitFor(tester, knopf);
  final ende = DateTime.now().add(const Duration(seconds: 30));
  while (!frei(tester, knopf)) {
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException('Startknopf bleibt gesperrt: ${onScreen(tester)}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(knopf);
  await tester.pump();
}

Future<void> starte(WidgetTester tester, int n) =>
    starteKnopf(tester, startknopf(n));

Future<void> planAbbrechen(WidgetTester tester) async {
  await tap(
    tester,
    find.descendant(
      of: find.byType(ImportPlanScreen),
      matching: find.widgetWithText(TextButton, de.allgAbbrechen),
    ),
  );
  await waitGone(tester, find.byType(ImportPlanScreen));
}

Future<void> warteAufAbschluss(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 3),
}) => waitFor(tester, find.text(de.importAbgeschlossen), timeout: timeout);

/// Die Zeilen „N × Grund“ unter „Warum?“.
List<String> warumZeilen(WidgetTester tester) => [
  for (final e in find.textContaining(RegExp(r'^\d+ × ')).evaluate())
    (e.widget as Text).data ?? '',
];

Future<void> schliesseBlatt(WidgetTester tester) async {
  await tap(tester, find.widgetWithText(OutlinedButton, de.allgFertig));
  await waitGone(tester, find.text(de.importAbgeschlossen));
  await settle(tester);
}

Future<void> importiereUeberPlan(
  WidgetTester tester,
  List<File> dateien, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  await planMitDateien(tester, dateien, timeout: timeout);
  await starte(tester, dateien.length);
  await warteAufAbschluss(tester, timeout: timeout);
  await schliesseBlatt(tester);
}

// --- Zeitleiste, Vollbild, Info ----------------------------------------------

Finder kachel(String id) =>
    find.byWidgetPredicate((w) => w is AssetThumbnailTile && w.asset.id == id);

/// Rollt die Zeitleiste, bis die Kachel [id] gebaut ist (das Raster baut
/// nur, was in der Nähe des Sichtbaren liegt).
Future<void> rolleZuKachel(WidgetTester tester, String id) async {
  final ziel = kachel(id);
  final ende = DateTime.now().add(const Duration(seconds: 40));
  var schritt = 0;
  while (ziel.evaluate().isEmpty) {
    if (DateTime.now().isAfter(ende)) break;
    ScrollPosition? beste;
    for (final e
        in find
            .descendant(
              of: find.byType(TimelineScreen),
              matching: find.byType(Scrollable),
            )
            .evaluate()) {
      final pos = (e as StatefulElement).state as ScrollableState;
      final p = pos.position;
      if (p.axis != Axis.vertical || !p.hasContentDimensions) continue;
      if (beste == null || p.maxScrollExtent > beste.maxScrollExtent) {
        beste = p;
      }
    }
    if (beste != null) {
      // Erst ganz nach oben, dann in Schritten nach unten.
      final ziel = schritt == 0
          ? beste.minScrollExtent
          : (beste.pixels + beste.viewportDimension * 0.7).clamp(
              beste.minScrollExtent,
              beste.maxScrollExtent,
            );
      beste.jumpTo(ziel);
      schritt = beste.pixels >= beste.maxScrollExtent ? 0 : schritt + 1;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> sieheKachel(WidgetTester tester, String id) async {
  await rolleZuKachel(tester, id);
  await waitFor(tester, kachel(id), timeout: const Duration(seconds: 30));
}

Future<void> oeffneFoto(WidgetTester tester, String id) async {
  await rolleZuKachel(tester, id);
  await waitFor(tester, kachel(id), timeout: const Duration(seconds: 30));
  await tap(tester, kachel(id).first);
  await waitFor(tester, find.byType(AssetViewerScreen));
  await settle(tester);
}

Future<void> zeigeInfo(WidgetTester tester) async {
  if (find.text(de.infoDetails).evaluate().isEmpty) {
    await tap(
      tester,
      find.descendant(
        of: find.byType(AssetViewerScreen),
        matching: find.byTooltip(de.viewerInfo),
      ),
    );
  }
  await waitFor(tester, find.text(de.infoDetails));
  await settle(tester);
}

Future<void> schliesseFoto(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AssetViewerScreen))).pop();
  await waitGone(tester, find.byType(AssetViewerScreen));
  await settle(tester);
}

/// Ob sich [bild] dekodieren lässt.
Future<bool> laesstSichLaden(WidgetTester tester, ImageProvider bild) async =>
    (await tester.runAsync(() async {
      final fertig = Completer<bool>();
      final strom = bild.resolve(ImageConfiguration.empty);
      final hoerer = ImageStreamListener(
        (info, _) {
          if (!fertig.isCompleted) fertig.complete(info.image.width > 0);
        },
        onError: (e, _) {
          debugPrint('Bild nicht ladbar: $e');
          if (!fertig.isCompleted) fertig.complete(false);
        },
      );
      strom.addListener(hoerer);
      final ok = await fertig.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      strom.removeListener(hoerer);
      return ok;
    })) ??
    false;

/// Das Vollbild ist da und lässt sich dekodieren.
Future<void> erwarteVollbild(WidgetTester tester, String was) async {
  await waitFor(
    tester,
    find.byType(PhotoView),
    timeout: const Duration(seconds: 30),
  );
  final pv = tester.widget<PhotoView>(find.byType(PhotoView).first);
  expect(
    await laesstSichLaden(tester, pv.imageProvider!),
    isTrue,
    reason: 'Vollbild von $was lässt sich nicht dekodieren',
  );
}

bool vorschauOk(AssetData a) {
  final rel = a.thumbnailRelativePath;
  if (rel == null) return false;
  final f = bibliothek.paths.absolute(rel);
  return f.existsSync() && img.decodeImage(f.readAsBytesSync()) != null;
}

// --- Einstellungen -----------------------------------------------------------

/// Was in einer geöffneten Gruppe steht – daran erkennt
/// [oeffneEinstellungsgruppe], ob sie schon offen ist.
Finder _gruppeninhalt(String titel) {
  if (titel == de.einstAbschnittErscheinungsbild) return stapelSchalter;
  if (titel == de.serverTitel) return find.text(de.serverVerbinden);
  if (titel == de.einstUeberwachtTitel) {
    return find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data == de.einstUeberwachtKeiner ||
              w.data == de.einstUeberwachtAktiv),
    );
  }
  throw ArgumentError(titel);
}

Future<void> oeffneEinstellungsgruppe(WidgetTester tester, String titel) async {
  await openSection(tester, Hauptbereich.einstellungen);
  final inhalt = _gruppeninhalt(titel);
  if (inhalt.evaluate().isEmpty) {
    await tap(
      tester,
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text(titel),
      ),
    );
  }
  await waitFor(tester, inhalt);
  await settle(tester);
}

Finder get stapelSchalter =>
    find.widgetWithText(SwitchListTile, de.einstFormateStapelnTitel);

Future<void> oeffneWerkzeug(WidgetTester tester, String titel) async {
  await openSection(tester, Hauptbereich.werkzeuge);
  await waitFor(tester, find.byType(ToolsScreen));
  await scrollTo(
    tester,
    find.text(titel),
    in_: find
        .descendant(
          of: find.byType(ToolsScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tap(tester, find.text(titel));
}

Future<void> zurueck(WidgetTester tester) async {
  await tap(tester, find.byType(BackButton).last);
  await settle(tester);
}

/// Startet die App neu – wie Beenden und wieder Öffnen. Der Datenordner
/// bleibt im Temp-Ordner dieser Prüfung (von [startApp] umgelenkt).
Future<void> neustart(
  WidgetTester tester, {
  Future<void> Function()? dazwischen,
}) async {
  try {
    await bibliothek.vorDemBeenden();
  } catch (e) {
    debugPrint('neustart: $e');
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
  if (dazwischen != null) await dazwischen();
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

// --- Wegwerf-Server ----------------------------------------------------------

/// Eine Durchreiche zum Wegwerf-Server der Warteschlange. Sie lässt sich
/// anhalten („Server nicht erreichbar“) und kann sich als ältere
/// Serverfassung ausgeben (`importplan` < 2). Sonst reicht sie alles
/// unverändert durch.
class Durchreiche {
  Durchreiche(this.ziel);
  final Uri ziel;
  HttpServer? _server;
  int port = 0;
  bool alterServer = false;
  final _client = HttpClient()..autoUncompress = false;

  String get adresse => 'http://127.0.0.1:$port';

  Future<void> starte() async {
    for (var i = 0; ; i++) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        break;
      } on SocketException {
        if (i > 20) rethrow;
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
      final umschreiben =
          alterServer &&
          anfrage.uri.path.endsWith('/api/v1/zustand') &&
          a.statusCode == 200;
      a.headers.forEach((name, werte) {
        if (_ohne.contains(name)) return;
        if (umschreiben && name == 'content-encoding') return;
        antwort.headers.set(name, werte);
      });
      if (umschreiben) {
        var bytes = await a.fold<List<int>>([], (b, s) => b..addAll(s));
        if (a.headers.value('content-encoding') == 'gzip') {
          bytes = gzip.decode(bytes);
        }
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        (json['funktionen'] as Map<String, dynamic>)['importplan'] = 1;
        final neu = utf8.encode(jsonEncode(json));
        antwort.contentLength = neu.length;
        antwort.add(neu);
      } else {
        // Nach headers.clear() ist weder Länge noch „chunked“ gesetzt; ohne
        // eines davon wüsste die App nie, wo die Antwort endet.
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
      }
      await antwort.close();
    } catch (e) {
      try {
        anfrage.response.statusCode = 502;
        await anfrage.response.close();
      } catch (_) {}
    }
  }
}

const _konto = 'kontoa';
const _kennwort = 'Wegwerf-Kennwort-42';

/// Verbindet die App über die Oberfläche mit dem Wegwerf-Server (beim
/// ersten Mal legt sie das erste Konto an, danach meldet sie sich an),
/// öffnet die Bibliothek des Servers und startet neu.
Future<void> verbinde(WidgetTester tester, Durchreiche d) async {
  await oeffneEinstellungsgruppe(tester, de.serverTitel);
  await tap(tester, find.text(de.serverVerbinden));
  await enter(tester, field(de.serverAdresse), d.adresse);
  await enter(tester, field(de.serverName), _konto);
  await enter(tester, field(de.serverPasswort), _kennwort);
  await enter(tester, field(de.serverGeraet), 'Testplatz');
  await tap(tester, find.widgetWithText(FilledButton, de.serverAnmelden));
  final weiter = [
    field(de.serverPasswortWiederholen),
    find.text(de.serverCodesTitel),
    find.text(de.serverServerBib),
    find.text(de.serverTotpTitel),
  ];
  var schritt = await warteAufEines(tester, weiter);
  if (schritt == 0) {
    await enter(tester, field(de.serverPasswortWiederholen), _kennwort);
    await tap(
      tester,
      find.widgetWithText(FilledButton, de.serverErstesAnlegen),
    );
    schritt = await warteAufEines(tester, weiter.sublist(1));
    schritt++;
  }
  if (schritt == 3) fail('Server verlangt TOTP: ${onScreen(tester)}');
  if (schritt == 1) await tap(tester, find.text(de.serverWeiter));
  await tap(tester, find.text(de.serverServerBib));
  await waitFor(
    tester,
    find.text(de.einstNeustartTitel),
    timeout: const Duration(seconds: 90),
  );
  await neustart(tester);
  expect(bibliothek.verbunden, isTrue);
}

/// Schaltet „Erst in die Fotokammer“ aus, falls es vom letzten Import her
/// noch an ist (der Schalter merkt sich seinen Stand).
Future<void> kammerAus(WidgetTester tester) async {
  final s = find.widgetWithText(SwitchListTile, de.importKammerSchalter);
  if (s.evaluate().isNotEmpty && tester.widget<SwitchListTile>(s).value) {
    await tap(tester, s);
  }
}

Future<String?> serverPruefsumme(String id) async {
  final r = await bibliothek.abgleich!.verbindung.anfrage(
    'GET',
    'api/v1/aufnahmen/$id/original',
  );
  if (r.statusCode != 200) return null;
  return sha256.convert(r.bodyBytes).toString();
}

String _tag(DateTime d) => DateFormat.yMMMd('de').format(d);

/// Tippt auf [finder] und wartet, bis die Meldung [text] kommt. Geprüft am
/// Verlauf des Meldungsdienstes: Eine Meldung steht nur vier Sekunden, und
/// das Warten nach einem Tippen (settle) kann länger dauern.
Future<void> tippeMitMeldung(
  WidgetTester tester,
  Finder finder,
  String text, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  final start = DateTime.now().subtract(const Duration(milliseconds: 1));
  await tester.tap(finder.first);
  final ende = DateTime.now().add(timeout);
  while (!melde.verlauf.any((m) => m.text == text && m.zeit.isAfter(start))) {
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException(
        'Meldung „$text“ kam nicht. Zuletzt: '
        '${melde.verlauf.take(5).map((m) => m.text).toList()}\n'
        'Auf dem Bildschirm: ${onScreen(tester)}',
      );
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester);
}

/// testWidgets mit einer Abschirmung: Die Restaurierungs-Warteschlange der
/// App stellt bei jedem Start und jeder Eingabe eine Uhr (20 s,
/// RestoreQueueService.idleDelay), die [LibraryState.vorDemBeenden] nicht
/// anhält. Läuft sie nach [finish] ab, fragt sie die schon geschlossene
/// Datenbank („connection was closed“), und der Testrahmen schreibt den
/// Fehler der längst fertigen Prüfung zu. Nur genau dieser Fehler wird hier
/// ausgeblendet; alles andere schlägt wie gewohnt fehl.
void pruefung(
  String name,
  Future<void> Function(WidgetTester tester) body, {
  bool? skip,
  Timeout? timeout,
}) {
  testWidgets(
    name,
    (tester) async {
      final fertig = Completer<void>();
      runZonedGuarded(
        () async {
          try {
            await body(tester);
            if (!fertig.isCompleted) fertig.complete();
          } catch (e, s) {
            if (!fertig.isCompleted) fertig.completeError(e, s);
          }
        },
        (e, s) {
          if ('$e'.contains('connection was closed')) {
            debugPrint('Ausgeblendet (Datenbank schon geschlossen): $e');
            return;
          }
          if (!fertig.isCompleted) {
            fertig.completeError(e, s);
          } else {
            debugPrint('NACH_TEST_FEHLER $name: $e\n$s');
          }
        },
      );
      await fertig.future;
    },
    skip: skip,
    timeout: timeout,
  );
}

// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // === Import – Einstieg und Auswahl =======================================

  pruefung('IMP-001 IMP-002 IMP-005 IMP-010 Importdialog, leere Zeitleiste, '
      'Abbruch, Kamera ohne Datenträger', (tester) async {
    await startApp(tester);
    // IMP-002: Knopf im leeren Zustand der Zeitleiste.
    await waitFor(tester, find.text(de.timelineLeer));
    await tap(tester, find.text(de.importierenTooltip));
    await waitFor(tester, find.text(de.importWasTitel));
    await schliesseDialog(tester);

    // IMP-001: Knopf „Importieren“ in der Seitenleiste.
    await oeffneImportdialog(tester);
    expect(find.text(de.importEinzelneDateien), findsOneWidget);
    expect(find.text(de.importGanzerOrdner), findsOneWidget);
    expect(find.text(de.importVonKamera), findsOneWidget);

    // IMP-005: Systemdialog abgebrochen (gibt nichts zurück).
    dialog.dateien = [];
    await tap(tester, find.text(de.importEinzelneDateien));
    await settle(tester, max: const Duration(seconds: 2));
    expect(
      dialog.gerufen.where((g) => g.startsWith('pickFiles')),
      hasLength(1),
    );
    expect(find.text(de.importPlanTitel), findsNothing);
    expect(find.text(de.importLaeuft), findsNothing);
    expect(await aufnahmen(tester), isEmpty);

    // IMP-010: Von Kamera/SD-Karte ohne Datenträger.
    await oeffneImportdialog(tester);
    await tap(tester, find.text(de.importVonKamera));
    await waitFor(tester, find.text(de.kameraImportTitel));
    await waitFor(
      tester,
      find.text(de.kameraKeinDatentraeger),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(de.kameraWechselmedienRecht), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, de.allgAbbrechen));
    await waitGone(tester, find.text(de.kameraImportTitel));
    expect(find.text(de.importPlanTitel), findsNothing);
    expect(await aufnahmen(tester), isEmpty);

    // IMP-001: schmales Fenster – runder Knopf.
    // Die Breite liest die App aus MediaQuery – also die Ansicht verkleinern.
    final dpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(600 * dpr, 900 * dpr);
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await settle(tester);
    await tap(tester, find.byTooltip(de.importierenTooltip));
    await waitFor(tester, find.text(de.importWasTitel));
    expect(find.text(de.importGanzerOrdner), findsOneWidget);
    await schliesseDialog(tester);
    tester.view.resetPhysicalSize();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await settle(tester);
    await finish(tester);
  });

  pruefung('IMP-003 IMP-031 IMP-035 IMP-036 IMP-037 IMP-090 Einzelne Dateien, '
      'Bilanz, Jetzt sichten, Original unverändert, Ablage', (tester) async {
    await startApp(tester);
    final a = testfoto('a.jpg', datum: DateTime(2024, 5, 1, 10));
    final b = testfoto('b.JPG', datum: DateTime(2023, 8, 15, 14, 30));
    final c = testfoto('c.jpg', datum: DateTime(2022, 1, 2, 9));
    final vorher = {
      for (final f in [a, b, c]) f.path: pruefsumme(f),
    };

    await planMitDateien(tester, [a, b, c]);
    // IMP-090: ohne Server kein Schalter „Erst in die Fotokammer“.
    expect(find.text(de.importKammerSchalter), findsNothing);
    final zeilen = planzeilen(tester);
    expect(zeilen.keys.toSet(), {'a.jpg', 'b.JPG', 'c.jpg'});
    for (final z in zeilen.values) {
      expect(status(z), de.importPlanNeu);
      expect(z.gewaehlt, isTrue);
    }
    await starte(tester, 3);
    await warteAufAbschluss(tester);

    // IMP-031: keine Bilanzzeile, nur 3 / 3 und die Knöpfe.
    expect(find.textContaining('3 / 3'), findsOneWidget);
    expect(find.textContaining('übersprungen'), findsNothing);
    expect(find.textContaining('nicht herein'), findsNothing);
    expect(find.text(de.importJetztSichten), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, de.allgFertig), findsOneWidget);

    // IMP-036 / IMP-037: Quelle unverändert, Kopie gleich, Ablage.
    final alle = await aufnahmen(tester);
    expect(alle, hasLength(3));
    for (final f in [a, b, c]) {
      expect(f.existsSync(), isTrue);
      expect(pruefsumme(f), vorher[f.path]);
      final x = alle.singleWhere(
        (x) => x.originalFileName == p.basename(f.path),
      );
      expect(
        pruefsumme(bibliothek.paths.absolute(x.relativePath)),
        vorher[f.path],
      );
    }
    final bx = alle.singleWhere((x) => x.originalFileName == 'b.JPG');
    expect(bx.relativePath, 'originals/2023/08/${bx.id}.jpg');
    expect(bibliothek.paths.absolute(bx.relativePath).existsSync(), isTrue);

    // IMP-035: Jetzt sichten – genau die drei neuen im Sichtungsmodus.
    await tap(tester, find.text(de.importJetztSichten));
    await waitFor(tester, find.byType(AssetViewerScreen));
    final viewer = tester.widget<AssetViewerScreen>(
      find.byType(AssetViewerScreen),
    );
    expect(viewer.cullingMode, isTrue);
    expect(
      viewer.assets.map((x) => x.id).toSet(),
      alle.map((x) => x.id).toSet(),
    );
    await schliesseFoto(tester);

    // IMP-003: in der Zeitleiste unter dem Aufnahmedatum.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitGone(tester, find.text(de.timelineLeer));
    for (final x in alle) {
      await sieheKachel(tester, x.id);
      expect(
        tester
            .widget<AssetThumbnailTile>(kachel(x.id).first)
            .asset
            .fileCreatedAt,
        x.fileCreatedAt,
      );
    }
    for (final d in [DateTime(2024, 5), DateTime(2023, 8), DateTime(2022, 1)]) {
      expect(find.text(DateFormat.yMMMM('de').format(d)), findsWidgets);
    }
    await finish(tester);
  });

  pruefung('IMP-006 Ganzen Ordner samt Unterordnern importieren', (
    tester,
  ) async {
    await startApp(tester);
    final o = quellordner('urlaub');
    final u = Directory(p.join(o.path, 'tag2'))..createSync();
    nach(testfoto('o1.jpg', datum: DateTime(2021, 6, 1)), o);
    nach(testfoto('o2.jpg', datum: DateTime(2021, 6, 2)), o);
    nach(testfoto('u1.jpg', datum: DateTime(2021, 6, 3)), u);
    await planMitOrdner(tester, o);
    final z = planzeilen(tester);
    expect(z.keys.toSet(), {'o1.jpg', 'o2.jpg', 'u1.jpg'});
    expect(z.values.map(status).toSet(), {de.importPlanNeu});
    await starte(tester, 3);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);
    final alle = await aufnahmen(tester);
    expect(alle, hasLength(3));
    for (final x in alle) {
      await sieheKachel(tester, x.id);
    }
    await finish(tester);
  });

  pruefung('IMP-008 IMP-009 IMP-055 Leerer Ordner, fremde Dateien, '
      'nicht unterstütztes Format', (tester) async {
    await startApp(tester);
    // IMP-009 zuerst (damit kein Hinweis von IMP-008 mehr steht).
    final fremd = quellordner('fremd');
    File(p.join(fremd.path, 'a.txt')).writeAsStringSync('a');
    File(p.join(fremd.path, 'b.txt')).writeAsStringSync('b');
    File(p.join(fremd.path, 'c.xmp')).writeAsStringSync(xmpPaket(bewertung: 3));
    await planMitOrdner(tester, fremd);
    final z = planzeilen(tester);
    expect(z.keys.toSet(), {'a.txt', 'b.txt', 'c.xmp'});
    for (final e in z.values) {
      expect(status(e), de.importPlanFormat);
      expect(e.gewaehlt, isFalse);
      expect(e.waehlbar, isFalse);
    }
    expect(startknopf(0), findsOneWidget);
    expect(frei(tester, startknopf(0)), isFalse);
    // Hinweis aus import_progress_sheet.dart:69 kommt hier nicht.
    expect(find.text(de.importNichtsImOrdner), findsNothing);
    await planAbbrechen(tester);

    // IMP-055: notiz.txt neben einem Foto.
    final gemischt = quellordner('gemischt');
    File(p.join(gemischt.path, 'notiz.txt')).writeAsStringSync('Notiz');
    nach(testfoto('foto.jpg', datum: DateTime(2020, 4, 4)), gemischt);
    await planMitOrdner(tester, gemischt);
    final g = planzeilen(tester);
    expect(status(g['notiz.txt']!), de.importPlanFormat);
    expect(g['notiz.txt']!.gewaehlt, isFalse);
    expect(status(g['foto.jpg']!), de.importPlanNeu);
    await starte(tester, 1);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);
    expect((await aufnahmen(tester)).map((a) => a.originalFileName), [
      'foto.jpg',
    ]);

    // IMP-008: Ordner nur mit versteckten Dateien.
    final leer = quellordner('leer');
    File(p.join(leer.path, '.DS_Store')).writeAsStringSync('x');
    dialog.ordner = leer.path;
    await oeffneImportdialog(tester);
    await tippeMitMeldung(
      tester,
      find.text(de.importGanzerOrdner),
      de.importNichtsImOrdner,
    );
    expect(find.text(de.importPlanTitel), findsNothing);
    await finish(tester);
  });

  // === Import – Prüfung vor dem Import =====================================

  pruefung('IMP-014 Prüffenster zeigt Fortschritt und Bilanz', (tester) async {
    await startApp(tester);
    final schonDa = testfoto('schon_da.jpg', datum: DateTime(2019, 1, 1));
    await importiereDirekt(tester, [schonDa]);
    final o = quellordner('mix');
    for (var i = 0; i < 5; i++) {
      nach(testfoto('n$i.jpg', datum: DateTime(2021, 3, i + 1)), o);
    }
    schonDa.copySync(p.join(o.path, 'kopie.jpg'));
    File(p.join(o.path, 'notiz.txt')).writeAsStringSync('Notiz');

    dialog.ordner = o.path;
    await oeffneImportdialog(tester);
    await tester.tap(find.text(de.importGanzerOrdner));
    var sahZaehler = false, sahBalken = false;
    final ende = DateTime.now().add(const Duration(seconds: 60));
    final zeilenFinder = find.descendant(
      of: find.byType(ImportPlanScreen),
      matching: find.byType(CheckboxListTile),
    );
    while (zeilenFinder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende)) fail('Prüfung endet nicht');
      await tester.pump(const Duration(milliseconds: 16));
      if (find
          .textContaining(RegExp(r'^\d+ von 7 Dateien geprüft$'))
          .evaluate()
          .isNotEmpty) {
        sahZaehler = true;
        if (find
            .descendant(
              of: find.byType(ImportPlanScreen),
              matching: find.byType(LinearProgressIndicator),
            )
            .evaluate()
            .isNotEmpty) {
          sahBalken = true;
        }
      }
    }
    await settle(tester);
    expect(sahZaehler, isTrue, reason: '„x von 7 Dateien geprüft“');
    expect(sahBalken, isTrue, reason: 'Fortschrittsbalken');
    expect(find.textContaining('5 ausgewählt · '), findsOneWidget);
    expect(
      find.textContaining(' · 1 Dubletten · 1 nicht übernehmbar'),
      findsOneWidget,
    );
    final z = planzeilen(tester);
    for (var i = 0; i < 5; i++) {
      expect(status(z['n$i.jpg']!), de.importPlanNeu);
    }
    expect(status(z['kopie.jpg']!), de.importPlanVorhanden);
    expect(status(z['notiz.txt']!), de.importPlanFormat);
    await planAbbrechen(tester);
    await finish(tester);
  });

  pruefung(
    'IMP-016 IMP-068 IMP-070 Dubletten in der Auswahl und in der Bibliothek',
    (tester) async {
      await startApp(tester);
      final x = testfoto('x.jpg', muster: 777, datum: DateTime(2022, 2, 2));
      final y = testfoto('y.jpg', muster: 777, datum: DateTime(2022, 2, 2));
      expect(pruefsumme(x), pruefsumme(y));

      // IMP-016
      await planMitDateien(tester, [x, y]);
      final z = planzeilen(tester);
      final neu = z.values.where((e) => status(e) == de.importPlanNeu).toList();
      final doppelt = z.values
          .where((e) => status(e) == de.importPlanDoppelt)
          .toList();
      expect(neu, hasLength(1));
      expect(neu.single.gewaehlt, isTrue);
      expect(doppelt, hasLength(1));
      expect(doppelt.single.waehlbar, isFalse);
      expect(doppelt.single.gewaehlt, isFalse);
      await starte(tester, 1);
      await warteAufAbschluss(tester);
      await schliesseBlatt(tester);
      expect(await aufnahmen(tester), hasLength(1));

      // IMP-068: byte-gleiche Kopie unter anderem Namen.
      final kopie = x.copySync(p.join(eingang.path, 'b.jpg'));
      await planMitDateien(tester, [kopie]);
      expect(status(planzeilen(tester)['b.jpg']!), de.importPlanVorhanden);
      expect(frei(tester, startknopf(0)), isFalse);
      await planAbbrechen(tester);
      expect(await aufnahmen(tester), hasLength(1));

      // IMP-070: Ordner mit 3 schon importierten und 1 neuen Foto.
      final p1 = testfoto('p1.jpg', datum: DateTime(2022, 3, 3));
      final p2 = testfoto('p2.jpg', datum: DateTime(2022, 4, 4));
      await importiereDirekt(tester, [p1, p2]);
      final o = quellordner('wieder');
      for (final f in [x, p1, p2]) {
        f.copySync(p.join(o.path, p.basename(f.path)));
      }
      final spaet = nach(testfoto('neu.jpg', datum: DateTime(2022, 5, 5)), o);
      await planMitOrdner(tester, o);
      expect(
        find.textContaining(
          RegExp(r'^1 ausgewählt · .* · 3 Dubletten · 0 nicht übernehmbar$'),
        ),
        findsOneWidget,
      );
      // Dieselbe Datei kommt inzwischen auf anderem Weg herein (wie über
      // den überwachten Ordner): beim Import eine Dublette.
      await importiereDirekt(tester, [spaet]);
      await starte(tester, 1);
      await warteAufAbschluss(tester);
      expect(find.textContaining(de.importBilanzDuplikate(1)), findsOneWidget);
      await schliesseBlatt(tester);
      expect(await aufnahmen(tester), hasLength(4));
      await finish(tester);
    },
  );

  pruefung(
    'IMP-017 IMP-034 Nicht lesbare Datei, gescheiterte erneut versuchen',
    (tester) async {
      await startApp(tester);
      final o = quellordner('rechte');
      final gesperrt = nach(
        testfoto('gesperrt.jpg', datum: DateTime(2020, 1, 1)),
        o,
      );
      final lesbar = nach(
        testfoto('lesbar.jpg', datum: DateTime(2020, 1, 2)),
        o,
      );
      Future<void> chmod(String modus, File f) async {
        final r = await hintergrund(
          tester,
          () => Process.run('/bin/chmod', [modus, f.path]),
        );
        expect(r.exitCode, 0, reason: 'chmod: ${r.stderr}');
      }

      // IMP-017
      await chmod('000', gesperrt);
      await planMitOrdner(tester, o);
      final z = planzeilen(tester);
      expect(status(z['gesperrt.jpg']!), de.importPlanFehler);
      expect(z['gesperrt.jpg']!.waehlbar, isFalse);
      expect(z['gesperrt.jpg']!.gewaehlt, isFalse);
      expect(status(z['lesbar.jpg']!), de.importPlanNeu);
      expect(find.textContaining(' · 1 nicht übernehmbar'), findsOneWidget);
      await planAbbrechen(tester);

      // IMP-034: Leserecht zur Prüfung da, beim Import weg, dann wieder da.
      await chmod('644', gesperrt);
      await planMitDateien(tester, [gesperrt, lesbar]);
      await chmod('000', gesperrt);
      await starte(tester, 2);
      await warteAufAbschluss(tester);
      expect(find.textContaining(de.importBilanzFehler(1)), findsOneWidget);
      await chmod('644', gesperrt);
      await tap(tester, find.text(de.importErneutVersuchen(1)));
      await waitGone(
        tester,
        find.text(de.importErneutVersuchen(1)),
        timeout: const Duration(seconds: 60),
      );
      await warteAufAbschluss(tester);
      expect(find.textContaining('nicht herein'), findsNothing);
      await schliesseBlatt(tester);
      expect((await aufnahmen(tester)).map((a) => a.originalFileName).toSet(), {
        'gesperrt.jpg',
        'lesbar.jpg',
      });
      await finish(tester);
    },
  );

  pruefung('IMP-018 IMP-019 Auswahl ändern, abgewählte Datei bleibt draussen', (
    tester,
  ) async {
    await startApp(tester);
    final o = quellordner('drei');
    for (final n in ['a', 'b', 'c']) {
      nach(testfoto('$n.jpg', datum: DateTime(2021, 1, 1)), o);
    }
    await planMitOrdner(tester, o);
    expect(frei(tester, startknopf(3)), isTrue);
    await tap(tester, find.widgetWithText(CheckboxListTile, 'c.jpg'));
    expect(find.text(de.importPlanStarten(2)), findsOneWidget);
    expect(find.textContaining('2 ausgewählt · '), findsOneWidget);
    await tap(tester, find.widgetWithText(CheckboxListTile, 'a.jpg'));
    await tap(tester, find.widgetWithText(CheckboxListTile, 'b.jpg'));
    expect(find.text(de.importPlanStarten(0)), findsOneWidget);
    expect(frei(tester, startknopf(0)), isFalse);
    // IMP-019: nur a.jpg wieder an.
    await tap(tester, find.widgetWithText(CheckboxListTile, 'a.jpg'));
    await starte(tester, 1);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);
    expect((await aufnahmen(tester)).map((a) => a.originalFileName), ['a.jpg']);
    await finish(tester);
  });

  pruefung('IMP-020 Prüfung abbrechen ohne Schreibwirkung', (tester) async {
    await startApp(tester);
    final vorab = testfoto('vorab.jpg', datum: DateTime(2018, 8, 8));
    final ids = await importiereDirekt(tester, [vorab]);
    await befehl(tester, AlbumAnlegen('album-a', 'Album A', DateTime.now()));
    await befehl(tester, AlbumFuellen('album-a', ids));
    await befehl(tester, SchlagwortAnheften(ids, 'Tag A'));
    await befehl(tester, FavoritSetzen(ids, true));

    Future<Map<String, Object>> stand() => hintergrund(tester, () async {
      final db = bibliothek.db;
      Set<String> dateien(Directory d) => d.existsSync()
          ? {
              for (final e in d.listSync(recursive: true))
                if (e is File)
                  p.relative(e.path, from: bibliothek.paths.root.path),
            }
          : <String>{};
      return {
        'aufnahmen': (await db.select(db.assets).get()).length,
        'alben': (await db.select(db.albums).get()).length,
        'albuminhalt': (await db.select(db.albumAssets).get()).length,
        'tags': (await db.select(db.tags).get()).length,
        'tagzuordnung': (await db.select(db.assetTags).get()).length,
        'favoriten': (await db.select(db.assets).get())
            .where((a) => a.isFavorite)
            .length,
        'dateien': {
          ...dateien(bibliothek.paths.originalsDir),
          ...dateien(bibliothek.paths.thumbnailsDir),
          ...dateien(bibliothek.paths.previewsDir),
        }.join('|'),
      };
    });

    final vorher = await stand();
    final o = quellordner('viele');
    for (var i = 0; i < 500; i++) {
      nach(
        testfoto('v$i.jpg', breite: 64, hoehe: 48, datum: DateTime(2017, 1, 1)),
        o,
      );
    }
    dialog.ordner = o.path;
    await oeffneImportdialog(tester);
    await tester.tap(find.text(de.importGanzerOrdner));
    await waitFor(
      tester,
      find.textContaining(RegExp(r'^[1-9]\d* von 500 Dateien geprüft$')),
      timeout: const Duration(seconds: 60),
    );
    expect(
      find.descendant(
        of: find.byType(ImportPlanScreen),
        matching: find.byType(CheckboxListTile),
      ),
      findsNothing,
      reason: 'Prüfung lief beim Abbrechen noch',
    );
    await planAbbrechen(tester);
    await warte(tester, const Duration(seconds: 3));
    expect(await stand(), vorher);
    await finish(tester);
  });

  pruefung('IMP-021 IMP-071 IMP-072 IMP-073 IMP-074 IMP-075 Aufnahmedatum und '
      'Datumsherkunft', (tester) async {
    await startApp(tester);
    final mai = testfoto('mai.jpg', datum: DateTime(2024, 5, 1, 10));
    final ohne = testfoto('ohne.jpg')
      ..setLastModifiedSync(DateTime(2021, 3, 4, 5, 6, 7));
    final name = testfoto('24-11-13 10-48-28.jpg');
    final nurTag = testfoto('IMG-20241113-WA0001.jpg');
    final null0 = eigenesFoto('nulluhr.jpg', aufnahme: '0000:00:00 00:00:00')
      ..setLastModifiedSync(DateTime(2020, 2, 3, 4, 5, 6));
    final januar = testfoto('januar.jpg', datum: DateTime(2022, 1, 2, 9));
    final zone = eigenesFoto(
      'zone.jpg',
      aufnahme: '2023:06:10 15:30:00',
      versatz: '+02:00',
    );
    final alleDateien = [mai, ohne, name, nurTag, null0, januar, zone];

    // IMP-021: Datum in der Prüfung.
    await planMitDateien(tester, alleDateien);
    final z = planzeilen(tester);
    expect(z['mai.jpg']!.text, contains('1.5.2024'));
    expect(z['mai.jpg']!.text, isNot(contains(de.importPlanDatumGeschaetzt)));
    expect(
      z['ohne.jpg']!.text,
      contains('4.3.2021 · ${de.importPlanDatumGeschaetzt}'),
    );
    await starte(tester, alleDateien.length);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);

    final a = {for (final x in await aufnahmen(tester)) x.originalFileName: x};
    // IMP-071
    expect(a['januar.jpg']!.fileCreatedAt, DateTime(2022, 1, 2, 9));
    expect(a['januar.jpg']!.datumGeschaetzt, isFalse);
    // IMP-073
    expect(a['ohne.jpg']!.fileCreatedAt, DateTime(2021, 3, 4, 5, 6, 7));
    expect(a['ohne.jpg']!.datumGeschaetzt, isTrue);
    // IMP-072
    expect(
      a['24-11-13 10-48-28.jpg']!.fileCreatedAt,
      DateTime(2024, 11, 13, 10, 48, 28),
    );
    expect(a['24-11-13 10-48-28.jpg']!.datumGeschaetzt, isFalse);
    final t = a['IMG-20241113-WA0001.jpg']!;
    expect(
      (t.fileCreatedAt.year, t.fileCreatedAt.month, t.fileCreatedAt.day),
      (2024, 11, 13),
    );
    expect(t.datumGeschaetzt, isTrue);
    // IMP-074
    final n = a['nulluhr.jpg']!;
    expect(n.fileCreatedAt, DateTime(2020, 2, 3, 4, 5, 6));
    expect(n.datumGeschaetzt, isTrue);
    expect(n.relativePath, startsWith('originals/2020/02/'));
    final ordner = bibliothek.paths.originalsDir
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();
    expect(
      ordner.where((o) => o.startsWith('00') || o.startsWith('-')),
      isEmpty,
    );
    // IMP-075
    expect(a['zone.jpg']!.zeitversatzMinuten, 120);

    // Info-Blatt
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffneFoto(tester, a['januar.jpg']!.id);
    await zeigeInfo(tester);
    expect(find.text(_tag(DateTime(2022, 1, 2))), findsWidgets);
    expect(find.textContaining('09:00:00'), findsOneWidget);
    expect(find.text(de.infoDatumGeschaetzt), findsNothing);
    await schliesseFoto(tester);

    await oeffneFoto(tester, a['ohne.jpg']!.id);
    await zeigeInfo(tester);
    expect(find.text(_tag(DateTime(2021, 3, 4))), findsWidgets);
    expect(find.text(de.infoDatumGeschaetzt), findsOneWidget);
    await schliesseFoto(tester);

    await oeffneFoto(tester, a['24-11-13 10-48-28.jpg']!.id);
    await zeigeInfo(tester);
    expect(find.text(_tag(DateTime(2024, 11, 13))), findsWidgets);
    expect(find.textContaining('10:48:28'), findsOneWidget);
    expect(find.text(de.infoDatumGeschaetzt), findsNothing);
    await schliesseFoto(tester);

    await oeffneFoto(tester, a['nulluhr.jpg']!.id);
    await zeigeInfo(tester);
    expect(find.text(de.infoDatumGeschaetzt), findsOneWidget);
    await schliesseFoto(tester);

    await oeffneFoto(tester, a['zone.jpg']!.id);
    await zeigeInfo(tester);
    final zeile = DateFormat.E(
      'de',
    ).addPattern(', ').add_Hms().format(DateTime(2023, 6, 10, 15, 30));
    expect(find.text('$zeile · UTC+2'), findsOneWidget);
    await schliesseFoto(tester);
    await finish(tester);
  });

  // Befund (zweimal reproduziert): Ein echtes EXIF-Datum vor 1990 (etwa bei
  // Scans) wird verworfen – packages/kern/lib/services/exif_camera.dart:112
  // (`if (jahr < 1990) return null;`). Das Foto bekommt den Dateizeitstempel
  // und gilt als „Datum geschätzt“.
  pruefung('IMP-074 Befund: EXIF-Datum von 1985 bleibt erhalten', (
    tester,
  ) async {
    await startApp(tester);
    final scan = eigenesFoto('scan1985.jpg', aufnahme: '1985:06:01 12:00:00');
    await importiereUeberPlan(tester, [scan]);
    final a = await aufnahme(tester, 'scan1985.jpg');
    expect(a.fileCreatedAt, DateTime(1985, 6, 1, 12));
    expect(a.datumGeschaetzt, isFalse);
    await finish(tester);
  });

  pruefung('IMP-022 IMP-024 IMP-025 Regeltreffer in der Vorschau, '
      'Regel mit gelöschtem Album', (tester) async {
    await startApp(tester);
    await befehl(tester, AlbumAnlegen('album-a', 'Album A', DateTime.now()));
    await befehl(
      tester,
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: 'r1',
          name: 'Regel JPG',
          triggerType: 'dateiendung',
          aiTagTerm: const Value('jpg'),
          targetAlbumId: const Value('album-a'),
          autoFavorite: const Value(true),
        ),
      ),
    );
    await befehl(
      tester,
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: 'r2',
          name: 'Regel KI',
          triggerType: 'aiTag',
          aiTagTerm: const Value('hund'),
        ),
      ),
    );
    final jpg = testfoto('regel.jpg', datum: DateTime(2021, 7, 7));
    final png = pngFoto('regel.png');
    await planMitDateien(tester, [jpg, png]);
    final z = planzeilen(tester);
    expect(z['regel.jpg']!.text, contains(de.importPlanAlben('Album A')));
    expect(z['regel.jpg']!.text, contains(de.importPlanFavorit));
    expect(z['regel.jpg']!.text, contains(de.importPlanTreffer('Regel JPG')));
    expect(z['regel.png']!.text, isNot(contains('Alben:')));
    expect(z['regel.png']!.text, isNot(contains(de.importPlanFavorit)));
    expect(z['regel.png']!.text, isNot(contains('Passende Regeln')));
    // IMP-025
    expect(find.text(de.importPlanSpaeter(1)), findsOneWidget);
    await starte(tester, 2);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);
    final j = await aufnahme(tester, 'regel.jpg');
    final pn = await aufnahme(tester, 'regel.png');
    expect(await albenVon(tester, j.id), ['Album A']);
    expect(j.isFavorite, isTrue);
    expect(await albenVon(tester, pn.id), isEmpty);
    expect(pn.isFavorite, isFalse);

    // IMP-024: Zielalbum gelöscht (die Oberfläche bietet für gewöhnliche
    // Alben kein Löschen an, darum direkt in der Datenbank).
    await hintergrund(tester, () async {
      final db = bibliothek.db;
      await (db.delete(
        db.albumAssets,
      )..where((t) => t.albumId.equals('album-a'))).go();
      await (db.delete(db.albums)..where((t) => t.id.equals('album-a'))).go();
    });
    final jpg2 = testfoto('regel2.jpg', datum: DateTime(2021, 7, 8));
    await planMitDateien(tester, [jpg2]);
    final z2 = planzeilen(tester)['regel2.jpg']!;
    expect(z2.text, contains(de.importPlanUngueltigeZiele));
    expect(z2.waehlbar, isFalse);
    expect(z2.gewaehlt, isFalse);
    await planAbbrechen(tester);

    // Hinweis: dasselbe bei einem Kamera-Preset mit gelöschtem Album.
    await befehl(tester, const RegelLoeschen('r1'));
    await befehl(tester, AlbumAnlegen('album-b', 'Album B', DateTime.now()));
    await befehl(
      tester,
      KameravorgabeSpeichern(
        CameraPresetsCompanion.insert(
          id: 'k1',
          cameraMake: 'Testkamera',
          cameraModel: 'T1',
          targetAlbumId: const Value('album-b'),
        ),
      ),
    );
    await hintergrund(tester, () async {
      final db = bibliothek.db;
      await (db.delete(db.albums)..where((t) => t.id.equals('album-b'))).go();
    });
    final k = testfoto('kamera.jpg', kamera: 'Testkamera', modell: 'T1');
    final anders = testfoto('anders.jpg', kamera: 'Andere', modell: 'X');
    await planMitDateien(tester, [k, anders]);
    final z3 = planzeilen(tester);
    expect(z3['kamera.jpg']!.text, contains(de.importPlanUngueltigeZiele));
    expect(z3['kamera.jpg']!.waehlbar, isFalse);
    expect(z3['anders.jpg']!.waehlbar, isTrue);
    await planAbbrechen(tester);
    await finish(tester);
  });

  pruefung('IMP-026 Regeln bearbeiten aus der Prüfung', (tester) async {
    await startApp(tester);
    final jpg = testfoto('ziel.jpg', datum: DateTime(2021, 9, 9));
    await planMitDateien(tester, [jpg]);
    expect(planzeilen(tester)['ziel.jpg']!.text, isNot(contains('Alben:')));
    await tap(tester, find.text(de.importPlanRegeln));
    await waitFor(tester, find.byType(AutomationRulesScreen));
    await tap(tester, find.byTooltip(de.regelNeu));
    await enter(tester, field(de.regelNameFeld), 'Endung jpg');
    await tap(
      tester,
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>),
    );
    await tap(tester, find.text(de.regelAusloeserDateiendung).last);
    await enter(tester, field(de.regelDateiendungWert), 'jpg');
    await enter(tester, field(de.presetNeuesAlbum), 'Album A');
    await tap(tester, find.widgetWithText(FilledButton, de.allgSpeichern));
    await waitFor(tester, find.textContaining('Endung jpg'));
    await zurueck(tester);
    await waitGone(tester, find.byType(AutomationRulesScreen));
    await warteAufPlan(tester);
    await eventually(tester, () async {
      final z = planzeilen(tester)['ziel.jpg'];
      return z != null &&
          z.text.contains(de.importPlanAlben('Album A')) &&
          z.text.contains(de.importPlanTreffer('Endung jpg'));
    });
    await planAbbrechen(tester);
    await finish(tester);
  });

  pruefung('IMP-032 Bilanz mit Fehlern und „erneut versuchen“', (tester) async {
    await startApp(tester);
    final n = testfoto('n.jpg', datum: DateTime(2020, 10, 1));
    final d = testfoto('d.jpg', datum: DateTime(2020, 10, 2));
    await planMitDateien(tester, [n, d]);
    d.deleteSync();
    await starte(tester, 2);
    await warteAufAbschluss(tester);
    expect(
      find.textContaining(
        '${de.importBilanzNeu(1)} · ${de.importBilanzFehler(1)}',
      ),
      findsOneWidget,
    );
    expect(find.text(de.importErneutVersuchen(1)), findsOneWidget);
    await schliesseBlatt(tester);
    expect((await aufnahmen(tester)).map((a) => a.originalFileName), ['n.jpg']);
    await finish(tester);
  });

  pruefung(
    'IMP-028 IMP-033 Datei ändert sich nach der Prüfung, „Warum?“ fasst zusammen',
    (tester) async {
      await startApp(tester);
      // IMP-028
      final a = testfoto('a.jpg', datum: DateTime(2020, 11, 1));
      await planMitDateien(tester, [a]);
      a.writeAsBytesSync([1, 2, 3], mode: FileMode.append);
      await starte(tester, 1);
      await warteAufAbschluss(tester);
      expect(find.textContaining(de.importBilanzFehler(1)), findsOneWidget);
      final originale = bibliothek.paths.originalsDir.existsSync()
          ? bibliothek.paths.originalsDir
                .listSync(recursive: true)
                .whereType<File>()
                .toList()
          : <File>[];
      expect(originale, isEmpty, reason: 'Teil-Kopie im Bibliotheksordner');
      expect(await aufnahmen(tester), isEmpty);
      await tap(tester, find.text(de.importFehlerWarum));
      expect(find.textContaining(RegExp(r'^1 × .+$')), findsOneWidget);
      expect(find.text('a.jpg'), findsOneWidget);
      debugPrint('IMP-028 Grund: ${warumZeilen(tester)}');
      await schliesseBlatt(tester);

      // IMP-033: acht Dateien mit demselben Grund.
      final acht = [
        for (var i = 1; i <= 8; i++)
          testfoto('c$i.jpg', datum: DateTime(2020, 12, i)),
      ];
      await planMitDateien(tester, acht);
      for (final f in acht) {
        f.writeAsBytesSync([9], mode: FileMode.append);
      }
      await starte(tester, 8);
      await warteAufAbschluss(tester);
      await tap(tester, find.text(de.importFehlerWarum));
      expect(find.textContaining(RegExp(r'^\d+ × ')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^8 × .+$')), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'^(c\d\.jpg, ){5}c\d\.jpg …$')),
        findsOneWidget,
      );
      debugPrint('IMP-033 Gründe: ${warumZeilen(tester)}');
      await schliesseBlatt(tester);
      await finish(tester);
    },
  );

  // Behoben in #409: ImportResult trägt die Ausnahme selbst (grund), und
  // importFehlertext übersetzt Kennungen auch als Text.
  pruefung('IMP-028 Befund: „Warum?“ nennt den Grund als Satz', (tester) async {
    await startApp(tester);
    final a = testfoto('a.jpg', datum: DateTime(2020, 11, 1));
    await planMitDateien(tester, [a]);
    a.writeAsBytesSync([1, 2, 3], mode: FileMode.append);
    await starte(tester, 1);
    await warteAufAbschluss(tester);
    await tap(tester, find.text(de.importFehlerWarum));
    debugPrint('IMP-028 Befund: ${warumZeilen(tester)}');
    expect(find.text('1 × ${de.importFehlerQuelleGeaendert}'), findsOneWidget);
    await schliesseBlatt(tester);
    await finish(tester);
  });

  // === Import – Ablauf und Bilanz ==========================================

  pruefung(
    'IMP-029 IMP-030 Fortschritt während des Imports, Blatt bleibt offen',
    (tester) async {
      await startApp(tester);
      final o = quellordner('fuenfzig');
      for (var i = 0; i < 50; i++) {
        nach(
          testfoto(
            'f${i.toString().padLeft(2, '0')}.jpg',
            datum: DateTime(2019, 5, 1, 8, i),
          ),
          o,
        );
      }
      await planMitOrdner(tester, o);
      await starte(tester, 50);
      final zeile = RegExp(r'^(\d+) / 50 — f\d\d\.jpg$');
      final werte = <int>{};
      var sahLauf = false, abbrechenImBlatt = false, versucht = false;
      final ende = DateTime.now().add(const Duration(minutes: 3));
      while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
        if (DateTime.now().isAfter(ende)) fail('Import endet nicht');
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text(de.importLaeuft).evaluate().isNotEmpty) {
          sahLauf = true;
          if (find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.text(de.allgAbbrechen),
              )
              .evaluate()
              .isNotEmpty) {
            abbrechenImBlatt = true;
          }
          if (!versucht) {
            versucht = true;
            // Neben das Blatt klicken und es nach unten ziehen.
            await tester.tapAt(const Offset(700, 40));
            await tester.pump(const Duration(milliseconds: 300));
            await tester.dragFrom(
              tester.getCenter(find.byType(BottomSheet)),
              const Offset(0, 500),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byType(BottomSheet), findsOneWidget);
          }
        }
        for (final e in find.byType(Text).evaluate()) {
          final m = zeile.firstMatch((e.widget as Text).data ?? '');
          if (m != null) werte.add(int.parse(m[1]!));
        }
      }
      expect(sahLauf, isTrue, reason: '„Importiere Fotos & Videos …“');
      expect(
        werte.where((w) => w > 0 && w < 50),
        isNotEmpty,
        reason: 'Zähler n / 50',
      );
      expect(find.textContaining(RegExp(r'^50 / 50')), findsOneWidget);
      expect(abbrechenImBlatt, isFalse);
      // Auch nach dem Ende schliesst nur „Fertig“.
      await tester.tapAt(const Offset(700, 40));
      await settle(tester);
      expect(find.text(de.importAbgeschlossen), findsOneWidget);
      await schliesseBlatt(tester);
      expect(await aufnahmen(tester), hasLength(50));
      await finish(tester);
    },
  );

  pruefung('IMP-039 Grosse Menge (verkleinert: 300 Fotos)', (tester) async {
    await startApp(tester);
    final o = quellordner('menge');
    for (var i = 0; i < 300; i++) {
      nach(
        testfoto(
          'm$i.jpg',
          breite: 96,
          hoehe: 72,
          datum: DateTime(2016, 1, 1, 0, i % 60),
        ),
        o,
      );
    }
    final zaehler = <String>{};
    dialog.ordner = o.path;
    await oeffneImportdialog(tester);
    await tester.tap(find.text(de.importGanzerOrdner));
    final zeilenFinder = find.descendant(
      of: find.byType(ImportPlanScreen),
      matching: find.byType(CheckboxListTile),
    );
    var ende = DateTime.now().add(const Duration(minutes: 3));
    while (zeilenFinder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende)) fail('Prüfung endet nicht');
      await tester.pump(const Duration(milliseconds: 50));
      for (final e in find.textContaining(_pruefFortschritt).evaluate()) {
        zaehler.add((e.widget as Text).data!);
      }
    }
    expect(zaehler, isNotEmpty, reason: 'Prüfung zählt sichtbar');
    await starte(tester, 300);
    final importZaehler = <String>{};
    ende = DateTime.now().add(const Duration(minutes: 8));
    while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende)) fail('Import endet nicht');
      await tester.pump(const Duration(milliseconds: 100));
      for (final e in find.textContaining(RegExp(r'^\d+ / 300')).evaluate()) {
        importZaehler.add(((e.widget as Text).data!).split(' — ').first);
      }
    }
    expect(
      importZaehler.length,
      greaterThan(5),
      reason: 'Import zählt sichtbar',
    );
    await schliesseBlatt(tester);
    final alle = await aufnahmen(tester);
    expect(alle, hasLength(300));
    expect(alle.map((a) => a.checksum).toSet(), hasLength(300));
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 15)));

  // === Import – Formate ====================================================

  pruefung('IMP-041 IMP-042 IMP-045 IMP-046 IMP-051 WebP, HEIC, AVIF, '
      'JPEG XL, Videos', (tester) async {
    await startApp(tester);
    final webp = ausBase64('probe.webp', _webpProbe);
    final heic = repoFixture('werkzeuge/probe.heic');
    final avif = repoFixture('werkzeuge/probe.avif');
    final jxl = repoFixture('jxl/kasten_exif_64x48.jxl');
    final mp4 = repoFixture('werkzeuge/probe.mp4');
    final mts = ausBase64('probe.mts', _mtsProbe);
    final mpg = ausBase64('probe.mpg', _mpgProbe);
    await importiereUeberPlan(tester, [webp, heic, avif, jxl, mp4, mts, mpg]);
    final a = {for (final x in await aufnahmen(tester)) x.originalFileName: x};
    expect(a.keys.toSet(), {
      'probe.webp',
      'probe.heic',
      'probe.avif',
      'kasten_exif_64x48.jxl',
      'probe.mp4',
      'probe.mts',
      'probe.mpg',
    });
    // IMP-041
    final w = a['probe.webp']!;
    expect((w.type, w.widthPx, w.heightPx), ('IMAGE', 120, 80));
    expect(vorschauOk(w), isTrue, reason: 'Miniatur WebP');
    // IMP-042
    final h = a['probe.heic']!;
    expect(h.type, 'IMAGE');
    expect(h.relativePath, endsWith('.heic'));
    expect(vorschauOk(h), isTrue, reason: 'Miniatur HEIC');
    expect(h.previewRelativePath, isNotNull);
    // IMP-045
    expect(vorschauOk(a['probe.avif']!), isTrue, reason: 'Miniatur AVIF');
    // IMP-046
    final j = a['kasten_exif_64x48.jxl']!;
    expect(j.fileCreatedAt, DateTime(2019, 7, 14, 16, 20, 5));
    expect(j.datumGeschaetzt, isFalse);
    expect((j.cameraMake, j.cameraModel), ('Testkamera', 'Modell X'));
    // IMP-051
    for (final v in ['probe.mp4', 'probe.mts', 'probe.mpg']) {
      expect(a[v]!.type, 'VIDEO', reason: v);
    }
    expect(a['probe.mp4']!.durationSeconds, greaterThan(0));
    expect(vorschauOk(a['probe.mp4']!), isTrue, reason: 'Vorschaubild MP4');
    final dauern = {
      for (final v in ['probe.mts', 'probe.mpg']) v: a[v]!.durationSeconds,
    };
    debugPrint('IMP-051 Dauer MTS/MPG: $dauern');

    await openSection(tester, Hauptbereich.zeitleiste);
    for (final n in ['probe.webp', 'probe.heic', 'probe.avif']) {
      await oeffneFoto(tester, a[n]!.id);
      await erwarteVollbild(tester, n);
      await schliesseFoto(tester);
    }
    await oeffneFoto(tester, j.id);
    await erwarteVollbild(tester, 'JPEG XL');
    await zeigeInfo(tester);
    expect(find.text(_tag(DateTime(2019, 7, 14))), findsWidgets);
    expect(find.textContaining('Modell X'), findsWidgets);
    await schliesseFoto(tester);

    await oeffneFoto(tester, a['probe.mp4']!.id);
    await waitFor(
      tester,
      find.byType(Video),
      timeout: const Duration(seconds: 30),
    );
    await eventually(tester, () async {
      final v = tester.widget<Video>(find.byType(Video).first);
      return v.controller.player.state.position > Duration.zero;
    }, was: 'MP4 spielt ab');
    await schliesseFoto(tester);
    // Dauer der Camcorder-Formate (der Katalog verlangt sie für alle).
    expect(
      dauern.values.every((d) => d != null && d > 0),
      isTrue,
      reason: 'Dauer MTS/MPG: $dauern',
    );
    await finish(tester);
  });

  pruefung('IMP-048 RAW: CR3, DNG, ARW', (tester) async {
    await startApp(tester);
    final cr3 = repoFixture('samples/canon_eos_r10.cr3');
    final dng = repoFixture('samples/iphone_6s_plus.dng');
    final arw = repoFixture('samples/sony_ilce6300.arw');
    await importiereUeberPlan(tester, [
      cr3,
      dng,
      arw,
    ], timeout: const Duration(minutes: 6));
    final a = {for (final x in await aufnahmen(tester)) x.originalFileName: x};
    final angaben = <String, String>{};
    for (final x in a.values) {
      angaben[x.originalFileName] =
          '${x.widthPx}x${x.heightPx} ${x.fileCreatedAt} geschätzt=${x.datumGeschaetzt} '
          '${x.cameraMake}/${x.cameraModel} Objektiv=${x.lensModel}';
    }
    debugPrint('IMP-048: $angaben');
    final c = a['canon_eos_r10.cr3']!;
    expect(c.cameraModel, 'Canon EOS R10');
    expect(c.lensModel, 'EF50mm f/1.8 STM');
    expect(c.fileCreatedAt, DateTime(2022, 8, 19, 19, 19, 28));
    await openSection(tester, Hauptbereich.zeitleiste);
    for (final x in a.values) {
      expect(x.type, 'IMAGE');
      expect(
        x.widthPx,
        greaterThan(1500),
        reason: '${x.originalFileName}: $angaben',
      );
      expect(
        x.heightPx,
        greaterThan(1000),
        reason: '${x.originalFileName}: $angaben',
      );
      expect(x.datumGeschaetzt, isFalse, reason: x.originalFileName);
      expect(x.cameraModel, isNotNull, reason: x.originalFileName);
      expect(vorschauOk(x), isTrue, reason: 'Miniatur ${x.originalFileName}');
      await oeffneFoto(tester, x.id);
      await erwarteVollbild(tester, x.originalFileName);
      await zeigeInfo(tester);
      expect(find.text(_tag(x.fileCreatedAt)), findsWidgets);
      expect(find.textContaining(x.cameraModel!), findsWidgets);
      if (x.lensModel != null) {
        expect(find.textContaining(x.lensModel!), findsWidgets);
      }
      await schliesseFoto(tester);
    }
    for (final x in a.values) {
      expect(x.lensModel, isNotNull, reason: 'Objektiv ${x.originalFileName}');
    }
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 15)));

  // === Import – Live Photos und Motion Photos ==============================

  pruefung('IMP-057 Live Photo aus HEIC und MOV', (tester) async {
    await startApp(tester);
    final heic = nach(
      repoFixture('werkzeuge/probe.heic'),
      eingang,
      'IMG_0001.HEIC',
    );
    final mov = nach(fixture('video_hoch_3s.mov'), eingang, 'IMG_0001.MOV');
    heic.setLastModifiedSync(DateTime(2024, 7, 1, 12, 0, 0));
    mov.setLastModifiedSync(DateTime(2024, 7, 1, 12, 0, 3));
    await importiereUeberPlan(tester, [heic, mov]);
    final foto = await aufnahme(tester, 'IMG_0001.HEIC');
    final video = await aufnahme(tester, 'IMG_0001.MOV');
    expect(video.type, 'VIDEO');
    expect(foto.linkedAssetId, video.id);
    await openSection(tester, Hauptbereich.zeitleiste);
    await sieheKachel(tester, foto.id);
    expect(kachel(video.id), findsNothing);
    expect(find.byType(AssetThumbnailTile), findsOneWidget);
    await oeffneFoto(tester, foto.id);
    await waitFor(
      tester,
      find.byType(LivePhotoView),
      timeout: const Duration(seconds: 30),
    );
    await schliesseFoto(tester);
    await finish(tester);
  });

  pruefung('IMP-059 Motion Photo von Google/Samsung', (tester) async {
    await startApp(tester);
    final mp4 = File(p.join(fixturesOrdner, 'video_5s.mp4')).readAsBytesSync();
    final quelle = testfoto(
      'PXL_20250712_101500123.MP.jpg',
      datum: DateTime(2025, 7, 12, 10, 15),
      breitengrad: 47.1,
      laengengrad: 10.9,
    );
    final xmp =
        '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
        'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about="" '
        'xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" '
        'GCamera:MicroVideo="1" GCamera:MicroVideoVersion="1" '
        'GCamera:MicroVideoOffset="${mp4.length}" '
        'GCamera:MicroVideoPresentationTimestampUs="0"/>'
        '</rdf:RDF></x:xmpmeta>';
    quelle.writeAsBytesSync([
      ...mitXmpSegment(quelle.readAsBytesSync(), xmp),
      ...mp4,
    ]);
    final vorher = pruefsumme(quelle);
    await importiereUeberPlan(tester, [quelle]);
    await eventually(
      tester,
      () async => (await _alle()).length == 2,
      was: 'Video abgetrennt',
    );
    final alle = await aufnahmen(tester);
    final foto = alle.singleWhere((a) => a.type == 'IMAGE');
    final video = alle.singleWhere((a) => a.type == 'VIDEO');
    expect(foto.linkedAssetId, video.id);
    expect(video.fileCreatedAt, foto.fileCreatedAt);
    expect(pruefsumme(bibliothek.paths.absolute(foto.relativePath)), vorher);
    expect(
      bibliothek.paths.absolute(video.relativePath).readAsBytesSync(),
      mp4,
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await sieheKachel(tester, foto.id);
    expect(find.byType(AssetThumbnailTile), findsOneWidget);
    expect(foto.latitude, closeTo(47.1, 0.001));
    expect(video.latitude, closeTo(47.1, 0.001), reason: 'Ort des Videos');
    expect(video.longitude, closeTo(10.9, 0.001), reason: 'Ort des Videos');
    await finish(tester);
  });

  // === Import – Formatstapel ===============================================

  pruefung('IMP-061 IMP-066 Formatstapel: Schalter aus, an, wieder aus', (
    tester,
  ) async {
    await startApp(tester);
    await oeffneEinstellungsgruppe(tester, de.einstAbschnittErscheinungsbild);
    await waitFor(tester, stapelSchalter);
    expect(tester.widget<SwitchListTile>(stapelSchalter).value, isFalse);

    final dng = nach(
      repoFixture('samples/iphone_6s_plus.dng'),
      eingang,
      'IMG_0100.DNG',
    );
    final angaben = await hintergrund(
      tester,
      () => bibliothek.importService.untersucheDatei(dng.path),
    );
    final jpg = testfoto(
      'IMG_0100.JPG',
      datum: angaben.datum,
      kamera: angaben.kamera,
      modell: angaben.modell,
    );
    // Eine von Hand gebildete Variante, die das Ausschalten überstehen muss.
    final m1 = testfoto('hand1.jpg', datum: DateTime(2015, 1, 1, 10));
    final m2 = testfoto('hand2.jpg', datum: DateTime(2015, 1, 1, 11));
    final hand = await importiereDirekt(tester, [m1, m2]);
    await befehl(tester, VariantenBilden('hand', hand, hand.first));

    await importiereUeberPlan(tester, [dng, jpg]);
    final d = await aufnahme(tester, 'IMG_0100.DNG');
    final j = await aufnahme(tester, 'IMG_0100.JPG');
    await openSection(tester, Hauptbereich.zeitleiste);
    // IMP-061: einzeln.
    await sieheKachel(tester, d.id);
    await sieheKachel(tester, j.id);

    // An: stapelt.
    await oeffneEinstellungsgruppe(tester, de.einstAbschnittErscheinungsbild);
    await tap(tester, stapelSchalter);
    await eventually(tester, () async {
      final x = await bibliothek.db.assetById(d.id);
      return x?.stackId != null;
    }, was: 'Stapel gebildet');
    await openSection(tester, Hauptbereich.zeitleiste);
    await sieheKachel(tester, j.id);
    await waitGone(tester, kachel(d.id));

    // IMP-066: aus – wieder einzeln, nichts gelöscht, Hand-Variante bleibt.
    await oeffneEinstellungsgruppe(tester, de.einstAbschnittErscheinungsbild);
    await tap(tester, stapelSchalter);
    await eventually(tester, () async {
      final x = await bibliothek.db.assetById(d.id);
      return x?.stackId == null;
    }, was: 'Stapel aufgelöst');
    await openSection(tester, Hauptbereich.zeitleiste);
    await sieheKachel(tester, d.id);
    await sieheKachel(tester, j.id);
    for (final x in [
      await aufnahme(tester, 'IMG_0100.DNG'),
      await aufnahme(tester, 'IMG_0100.JPG'),
    ]) {
      expect(x.isTrashed, isFalse);
      expect(bibliothek.paths.absolute(x.relativePath).existsSync(), isTrue);
    }
    final h1 = await aufnahme(tester, 'hand1.jpg');
    final h2 = await aufnahme(tester, 'hand2.jpg');
    expect(h1.stackId, isNotNull);
    expect(h2.stackId, h1.stackId);
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 12)));

  pruefung('IMP-062 RAW+JPEG wird gestapelt', (tester) async {
    await startApp(tester);
    await oeffneEinstellungsgruppe(tester, de.einstAbschnittErscheinungsbild);
    await tap(tester, stapelSchalter);
    await eventually(tester, () async => await bibliothek.db.formateStapeln());

    final cr3 = nach(
      repoFixture('samples/canon_eos_r10.cr3'),
      eingang,
      'IMG_1144.CR3',
    );
    final angaben = await hintergrund(
      tester,
      () => bibliothek.importService.untersucheDatei(cr3.path),
    );
    final jpg = testfoto(
      'IMG_1144.JPG',
      datum: angaben.datum,
      kamera: angaben.kamera,
      modell: angaben.modell,
    );
    await importiereUeberPlan(tester, [
      cr3,
      jpg,
    ], timeout: const Duration(minutes: 5));
    await eventually(tester, () async {
      final r = await bibliothek.db.select(bibliothek.db.assets).get();
      final c = r.singleWhere((a) => a.originalFileName == 'IMG_1144.CR3');
      final j = r.singleWhere((a) => a.originalFileName == 'IMG_1144.JPG');
      return c.stackId != null && c.stackId == j.stackId && j.isStackCover;
    }, was: 'gestapelt, JPEG oben');
    final c = await aufnahme(tester, 'IMG_1144.CR3');
    final j = await aufnahme(tester, 'IMG_1144.JPG');
    await openSection(tester, Hauptbereich.zeitleiste);
    await sieheKachel(tester, j.id);
    expect(kachel(c.id), findsNothing);
    await oeffneFoto(tester, j.id);
    await zeigeInfo(tester);
    expect(find.text(de.infoVarianten(2)), findsOneWidget);
    expect(
      find.textContaining('nur das Titelbild ist in der Übersicht sichtbar'),
      findsOneWidget,
    );
    expect(find.textContaining('Formate: '), findsOneWidget);
    final chips = find.byWidgetPredicate(
      (w) =>
          w is ActionChip &&
          w.label is Text &&
          ((w.label as Text).data ?? '').contains(' · '),
    );
    expect(chips, findsNWidgets(2));
    await schliesseFoto(tester);
    for (final x in [c, j]) {
      expect(x.isTrashed, isFalse);
      expect(bibliothek.paths.absolute(x.relativePath).existsSync(), isTrue);
    }
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 12)));

  // === Kamera-Presets ======================================================

  pruefung(
    'IMP-023 IMP-076 IMP-077 IMP-078 IMP-079 IMP-080 IMP-081 Kamera-Presets',
    (tester) async {
      await startApp(tester);
      final dummy = await importiereDirekt(tester, [testfoto('dummy.jpg')]);
      await befehl(tester, SchlagwortAnheften(dummy, 'Tag A'));
      await befehl(tester, AlbumAnlegen('album-a', 'Album A', DateTime.now()));

      await oeffneWerkzeug(tester, de.werkzPresetsTitel);
      await waitFor(tester, find.text(de.presetTitel));
      await tap(tester, find.byTooltip(de.presetNeu));
      await waitFor(tester, find.text(de.presetNeuTitel));
      // IMP-077
      await enter(tester, field(de.presetHersteller), 'Testkamera');
      await tap(tester, find.widgetWithText(FilledButton, de.allgSpeichern));
      expect(find.text(de.presetHerstellerModellNoetig), findsOneWidget);
      expect(find.text(de.presetNeuTitel), findsOneWidget);
      expect(
        await hintergrund(
          tester,
          () => bibliothek.db.select(bibliothek.db.cameraPresets).get(),
        ),
        isEmpty,
      );
      // IMP-076
      await enter(tester, field(de.presetModell), 'T1');
      await tap(
        tester,
        find.byWidgetPredicate((w) => w is DropdownButtonFormField<AlbumData?>),
      );
      await tap(tester, find.text('Album A').last);
      await tap(
        tester,
        find.widgetWithText(SwitchListTile, de.presetFavorisieren),
      );
      await tap(
        tester,
        find
            .byWidgetPredicate((w) => w is InkWell && w.child is InputDecorator)
            .last,
      );
      await tap(tester, find.widgetWithText(CheckboxListTile, 'Tag A'));
      await tap(tester, find.widgetWithText(FilledButton, de.allgUebernehmen));
      await tap(tester, find.widgetWithText(FilledButton, de.allgSpeichern));
      await waitGone(tester, find.text(de.presetNeuTitel));
      await waitFor(tester, find.text('Testkamera T1'));
      expect(
        find.textContaining('Album: Album A · Automatisch favorisieren'),
        findsOneWidget,
      );
      // IMP-079: Preset mit neuem Album.
      await tap(tester, find.byTooltip(de.presetNeu));
      await enter(tester, field(de.presetHersteller), 'Canon');
      await enter(tester, field(de.presetModell), 'EOS R5');
      await enter(tester, field(de.presetNeuesAlbum), 'Album B');
      await tap(tester, find.widgetWithText(FilledButton, de.allgSpeichern));
      await waitFor(tester, find.text('Canon EOS R5'));
      expect(find.textContaining('Album: Album B'), findsOneWidget);
      final alben = await hintergrund(
        tester,
        () => bibliothek.db.select(bibliothek.db.albums).get(),
      );
      expect(alben.map((a) => a.name), contains('Album B'));
      await zurueck(tester);

      // IMP-023 / IMP-078 / IMP-081
      final t1 = testfoto('kamera_t1.jpg', kamera: 'Testkamera', modell: 'T1');
      final andere = testfoto('andere.jpg', kamera: 'Andere', modell: 'X');
      final canon = testfoto(
        'canon_gross.jpg',
        kamera: 'CANON',
        modell: 'EOS R5',
      );
      await planMitDateien(tester, [t1, andere, canon]);
      final z = planzeilen(tester);
      expect(z['kamera_t1.jpg']!.text, contains(de.importPlanAlben('Album A')));
      expect(z['kamera_t1.jpg']!.text, contains(de.importPlanTags('Tag A')));
      expect(z['kamera_t1.jpg']!.text, contains(de.importPlanFavorit));
      for (final n in ['andere.jpg', 'canon_gross.jpg']) {
        expect(z[n]!.text, isNot(contains('Alben:')), reason: n);
        expect(z[n]!.text, isNot(contains(de.importPlanFavorit)), reason: n);
      }
      await starte(tester, 3);
      await warteAufAbschluss(tester);
      await schliesseBlatt(tester);
      final k = await aufnahme(tester, 'kamera_t1.jpg');
      final an = await aufnahme(tester, 'andere.jpg');
      final ca = await aufnahme(tester, 'canon_gross.jpg');
      expect(await albenVon(tester, k.id), ['Album A']);
      expect(k.isFavorite, isTrue);
      expect(await tagsVon(tester, k.id), ['Tag A']);
      expect(await albenVon(tester, an.id), isEmpty);
      expect(an.isFavorite, isFalse);
      expect(await albenVon(tester, ca.id), isEmpty, reason: 'IMP-081');
      await openSection(tester, Hauptbereich.favoriten);
      await sieheKachel(tester, k.id);
      expect(kachel(an.id), findsNothing);

      // IMP-080: Preset löschen.
      await oeffneWerkzeug(tester, de.werkzPresetsTitel);
      await waitFor(tester, find.text('Testkamera T1'));
      await tap(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Testkamera T1'),
          matching: find.byTooltip(de.allgLoeschen),
        ),
      );
      await waitFor(tester, find.text(de.presetLoeschenTitel));
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await waitGone(tester, find.text('Testkamera T1'));
      await zurueck(tester);
      final k2 = await aufnahme(tester, 'kamera_t1.jpg');
      expect(await albenVon(tester, k2.id), ['Album A']);
      expect(k2.isFavorite, isTrue);
      final neu = testfoto(
        'kamera_t1_neu.jpg',
        kamera: 'Testkamera',
        modell: 'T1',
      );
      await importiereUeberPlan(tester, [neu]);
      final n = await aufnahme(tester, 'kamera_t1_neu.jpg');
      expect(await albenVon(tester, n.id), isEmpty);
      expect(n.isFavorite, isFalse);
      expect(await tagsVon(tester, n.id), isEmpty);
      await finish(tester);
    },
  );

  // === XMP-Beilage beim Import =============================================

  pruefung('IMP-082 IMP-083 XMP-Beilage beim Import, Ort aus der Kamera', (
    tester,
  ) async {
    await startApp(tester);
    final o = quellordner('beilage');
    nach(testfoto('foto.jpg', datum: DateTime(2021, 8, 1)), o);
    File(p.join(o.path, 'foto.xmp')).writeAsStringSync(
      xmpPaket(
        bewertung: 4,
        farbe: 'Red',
        beschreibung: 'Am See',
        tags: ['Tag A'],
        breite: 47.5,
        laenge: 11.25,
      ),
    );
    nach(
      testfoto(
        'mitort.jpg',
        datum: DateTime(2021, 8, 2),
        breitengrad: 48.1,
        laengengrad: 11.5,
      ),
      o,
    );
    File(
      p.join(o.path, 'mitort.xmp'),
    ).writeAsStringSync(xmpPaket(tags: ['Tag C'], breite: 40.0, laenge: -3.7));
    await planMitOrdner(tester, o);
    final z = planzeilen(tester);
    debugPrint(
      'IMP-082 Beilagen in der Prüfung: ${z['foto.xmp']?.text} / ${z['mitort.xmp']?.text}',
    );
    // Behoben in #409: Die Beilagen stehen als Beilage ihres Fotos da,
    // nicht als „Format wird nicht unterstützt“.
    expect(status(z['foto.xmp']!), de.importPlanBeilage('foto.jpg'));
    expect(status(z['mitort.xmp']!), de.importPlanBeilage('mitort.jpg'));
    await starte(tester, 2);
    await warteAufAbschluss(tester);
    await schliesseBlatt(tester);
    final f = await aufnahme(tester, 'foto.jpg');
    expect(f.rating, 4);
    expect(f.colorLabel, 'red');
    expect(f.description, 'Am See');
    expect(await tagsVon(tester, f.id), contains('Tag A'));
    expect(f.latitude, closeTo(47.5, 0.001));
    expect(f.longitude, closeTo(11.25, 0.001));
    // IMP-083
    final m = await aufnahme(tester, 'mitort.jpg');
    expect(m.latitude, closeTo(48.1, 0.001));
    expect(m.longitude, closeTo(11.5, 0.001));
    expect(await tagsVon(tester, m.id), contains('Tag C'));

    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffneFoto(tester, f.id);
    await zeigeInfo(tester);
    expect(find.textContaining('Am See'), findsWidgets);
    expect(find.text('Tag A'), findsWidgets);
    await schliesseFoto(tester);
    await finish(tester);
  });

  // === Überwachter Ordner ==================================================

  pruefung(
    'IMP-091 IMP-092 IMP-093 IMP-098 IMP-100 IMP-101 Überwachter Ordner',
    (tester) async {
      await startApp(tester);
      // IMP-091
      await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
      await waitFor(tester, find.text(de.einstUeberwachtKeiner));
      expect(find.text(de.einstUeberwachtErklaerung), findsOneWidget);
      expect(find.text(de.einstUeberwachtWaehlen), findsOneWidget);

      // IMP-093: leerer Ordner.
      final leer = quellordner('leer_ueberwacht');
      dialog.ordner = leer.path;
      await tippeMitMeldung(
        tester,
        find.text(de.einstUeberwachtWaehlen),
        de.einstUeberwachtNichtsNeues,
      );

      // IMP-092: Ordner mit zwei älteren Fotos.
      final w = quellordner('ueberwacht');
      altern(nach(testfoto('w1.jpg', datum: DateTime(2020, 6, 1)), w));
      altern(nach(testfoto('w2.jpg', datum: DateTime(2020, 6, 2)), w));
      dialog.ordner = w.path;
      await tippeMitMeldung(
        tester,
        find.text(de.einstUeberwachtAndererWaehlen),
        de.einstUeberwachtUebernommen(2),
      );
      await waitFor(tester, find.text(w.path));
      expect(find.text(de.einstUeberwachtAktiv), findsOneWidget);
      expect(find.text(de.einstUeberwachtAndererWaehlen), findsOneWidget);
      expect(find.text(de.einstUeberwachtBeenden), findsOneWidget);
      expect(await aufnahmen(tester), hasLength(2));

      // IMP-098: App beendet, neues Foto hineingelegt, App gestartet.
      await neustart(
        tester,
        dazwischen: () async {
          altern(nach(testfoto('w3.jpg', datum: DateTime(2020, 6, 3)), w));
        },
      );
      await eventually(
        tester,
        () async => (await _alle()).any((a) => a.originalFileName == 'w3.jpg'),
        was: 'w3.jpg beim Start übernommen',
      );
      final w3 = await aufnahme(tester, 'w3.jpg');
      await openSection(tester, Hauptbereich.zeitleiste);
      await sieheKachel(tester, w3.id);

      // IMP-100: Ordner verschwindet (wie ein ausgeworfener Datenträger).
      final weg = '${w.path}_weg';
      await neustart(tester, dazwischen: () async => w.renameSync(weg));
      await warte(tester, const Duration(seconds: 5));
      expect(find.byType(HomeShell), findsOneWidget);
      expect(await aufnahmen(tester), hasLength(3));
      // Wieder eingesteckt: geht weiter.
      await neustart(
        tester,
        dazwischen: () async {
          Directory(weg).renameSync(w.path);
          altern(nach(testfoto('w4.jpg', datum: DateTime(2020, 6, 4)), w));
        },
      );
      await eventually(
        tester,
        () async => (await _alle()).any((a) => a.originalFileName == 'w4.jpg'),
        was: 'w4.jpg nach dem Wiedereinstecken',
      );

      // IMP-101: Überwachung beenden.
      await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
      await tap(tester, find.text(de.einstUeberwachtBeenden));
      await waitFor(tester, find.text(de.einstUeberwachtKeiner));
      await neustart(
        tester,
        dazwischen: () async {
          altern(nach(testfoto('w5.jpg', datum: DateTime(2020, 6, 5)), w));
        },
      );
      await warte(tester, const Duration(seconds: 10));
      expect(
        (await aufnahmen(tester)).map((a) => a.originalFileName),
        isNot(contains('w5.jpg')),
      );
      await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
      await waitFor(tester, find.text(de.einstUeberwachtKeiner));
      await finish(tester);
    },
  );

  pruefung('IMP-096 Überwachter Ordner: neue Datei im Fünf-Minuten-Takt', (
    tester,
  ) async {
    final beginn = DateTime.now();
    await startApp(tester);
    final w = quellordner('takt');
    await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
    dialog.ordner = w.path;
    await tippeMitMeldung(
      tester,
      find.text(de.einstUeberwachtWaehlen),
      de.einstUeberwachtNichtsNeues,
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    // Hineinkopiert mit der Zeit der Aufnahme (älter als zwei Minuten).
    altern(nach(testfoto('takt.jpg', datum: DateTime(2020, 7, 1)), w));
    await eventually(
      tester,
      () async => (await _alle()).any((a) => a.originalFileName == 'takt.jpg'),
      timeout: const Duration(minutes: 6),
      was: 'takt.jpg ohne Klick übernommen',
    );
    debugPrint('IMP-096: nach ${DateTime.now().difference(beginn)} übernommen');
    final t = await aufnahme(tester, 'takt.jpg');
    await sieheKachel(tester, t.id);
    await finish(tester);
  }, timeout: const Timeout(Duration(minutes: 12)));

  // === XMP-Sidecars einlesen ===============================================

  pruefung(
    'IMP-104 IMP-105 IMP-106 IMP-107 IMP-110 XMP-Sidecars einlesen: keine, '
    'Abweichungen, einzeln und alle übernehmen, eingebettet',
    (tester) async {
      await startApp(tester);
      await hintergrund(
        tester,
        () => bibliothek.db.setThemeMode(themeModeToString(ThemeMode.light)),
      );
      await importiereDirekt(tester, [testfoto('ohne.jpg')]);
      // IMP-104
      await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
      await waitFor(tester, find.text(de.xmpKeineSidecars));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await zurueck(tester);

      // Vorbereitung 105–107, 110
      final stern = (await importiereDirekt(tester, [
        testfoto('stern.jpg'),
      ])).single;
      await befehl(tester, BewertungSetzen([stern], 2));
      await befehl(tester, SchlagwortAnheften([stern], 'Tag A'));
      final s = await aufnahme(tester, 'stern.jpg');
      final original = bibliothek.paths.absolute(s.relativePath);
      final vorher = pruefsumme(original);
      bibliothek.paths
          .absolute(bibliothek.paths.xmpSidecarPath(s.relativePath))
          .writeAsStringSync(
            xmpPaket(
              bewertung: 5,
              tags: ['Tag A', 'Tag B'],
              beschreibung: 'Neu beschrieben',
            ),
          );
      final emb = testfoto('eingebettet.jpg');
      emb.writeAsBytesSync(
        mitXmpSegment(emb.readAsBytesSync(), xmpPaket(bewertung: 3)),
      );
      await importiereDirekt(tester, [emb]);

      await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
      final bewertung = '${de.xmpFeldBewertung}: "2" → "5"';
      await waitFor(tester, find.text(bewertung));
      // IMP-105
      expect(
        find.text('${de.xmpFeldNeueTags}: "Tag A" → "Tag B"'),
        findsOneWidget,
      );
      // IMP-110
      expect(find.text('${de.xmpFeldBewertung}: "0" → "3"'), findsOneWidget);
      // IMP-106
      await tap(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text(bewertung),
            matching: find.byType(ListTile),
          ),
          matching: find.widgetWithText(TextButton, de.allgUebernehmen),
        ),
      );
      await waitGone(tester, find.text(bewertung));
      expect((await aufnahme(tester, 'stern.jpg')).rating, 5);
      expect(pruefsumme(original), vorher);

      // IMP-107: Lesbarkeit des fest weissen Texts im hellen Erscheinungsbild.
      final knopfText = tester.widget<Text>(
        find.descendant(
          of: find.byType(XmpImportScreen),
          matching: find.text(de.xmpAlleUebernehmen),
        ),
      );
      final kontext = tester.element(find.byType(XmpImportScreen));
      final thema = Theme.of(kontext);
      final leiste = tester.widget<AppBar>(
        find.descendant(
          of: find.byType(XmpImportScreen),
          matching: find.byType(AppBar),
        ),
      );
      final grund =
          leiste.backgroundColor ??
          thema.appBarTheme.backgroundColor ??
          thema.colorScheme.surface;
      final vorne = knopfText.style?.color ?? thema.colorScheme.primary;
      final l1 = vorne.computeLuminance(), l2 = grund.computeLuminance();
      final kontrast = (l1 > l2
          ? (l1 + 0.05) / (l2 + 0.05)
          : (l2 + 0.05) / (l1 + 0.05));
      debugPrint(
        'IMP-107 Kontrast „Alle übernehmen“: ${kontrast.toStringAsFixed(2)} '
        '(Text $vorne auf $grund, hell=${thema.brightness == Brightness.light})',
      );
      await tap(tester, find.text(de.xmpAlleUebernehmen));
      await waitGone(
        tester,
        find.widgetWithText(TextButton, de.allgUebernehmen),
      );
      await tap(tester, find.byTooltip(de.xmpErneutEinlesen));
      await waitFor(tester, find.text(de.xmpKeineAbweichungen(2)));
      final s2 = await aufnahme(tester, 'stern.jpg');
      expect(s2.description, 'Neu beschrieben');
      expect(await tagsVon(tester, s2.id), containsAll(['Tag A', 'Tag B']));
      expect((await aufnahme(tester, 'eingebettet.jpg')).rating, 3);
      expect(pruefsumme(original), vorher);
      await finish(tester);
    },
  );

  // Behoben in #409: „Alle übernehmen“ nimmt die Farbe des Themas statt
  // fest weiss.
  pruefung(
    'IMP-107 Befund: „Alle übernehmen“ im hellen Erscheinungsbild lesbar',
    (tester) async {
      await startApp(tester);
      await hintergrund(
        tester,
        () => bibliothek.db.setThemeMode(themeModeToString(ThemeMode.light)),
      );
      final id = (await importiereDirekt(tester, [testfoto('k.jpg')])).single;
      final a = await aufnahme(tester, 'k.jpg');
      bibliothek.paths
          .absolute(bibliothek.paths.xmpSidecarPath(a.relativePath))
          .writeAsStringSync(xmpPaket(bewertung: 4));
      expect(id, a.id);
      await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
      await waitFor(tester, find.text(de.xmpAlleUebernehmen));
      final knopfText = tester.widget<Text>(
        find.descendant(
          of: find.byType(XmpImportScreen),
          matching: find.text(de.xmpAlleUebernehmen),
        ),
      );
      final thema = Theme.of(tester.element(find.byType(XmpImportScreen)));
      final leiste = tester.widget<AppBar>(
        find.descendant(
          of: find.byType(XmpImportScreen),
          matching: find.byType(AppBar),
        ),
      );
      final grund =
          leiste.backgroundColor ??
          thema.appBarTheme.backgroundColor ??
          thema.colorScheme.surface;
      final vorne = knopfText.style?.color ?? thema.colorScheme.primary;
      final l1 = vorne.computeLuminance(), l2 = grund.computeLuminance();
      final kontrast = (l1 > l2
          ? (l1 + 0.05) / (l2 + 0.05)
          : (l2 + 0.05) / (l1 + 0.05));
      expect(kontrast, greaterThanOrEqualTo(3.0), reason: 'Kontrast $kontrast');
      await finish(tester);
    },
  );

  pruefung('IMP-108 Abgelehntes Foto kommt in den Papierkorb', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('abgelehnt.jpg')]);
    final a = await aufnahme(tester, 'abgelehnt.jpg');
    bibliothek.paths
        .absolute(bibliothek.paths.xmpSidecarPath(a.relativePath))
        .writeAsStringSync(xmpPaket(bewertung: -1));
    await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
    await waitFor(tester, find.text(de.xmpFeldAbgelehnt));
    await tap(tester, find.widgetWithText(TextButton, de.allgUebernehmen));
    await waitGone(tester, find.text(de.xmpFeldAbgelehnt));
    expect((await aufnahme(tester, 'abgelehnt.jpg')).isTrashed, isTrue);
    await zurueck(tester);
    await openSection(tester, Hauptbereich.papierkorb);
    await waitFor(tester, find.byType(TrashScreen));
    final kachelImKorb = find
        .descendant(
          of: find.descendant(
            of: find.byType(TrashScreen),
            matching: find.byType(GridView),
          ),
          matching: find.byType(Stack),
        )
        .first;
    await waitFor(tester, kachelImKorb);
    await tester.longPress(kachelImKorb);
    await settle(tester);
    await tap(tester, find.byTooltip(de.einstWiederherstellen));
    await eventually(tester, () async {
      final x = await bibliothek.db.assetById(a.id);
      return x != null && !x.isTrashed;
    }, was: 'wiederhergestellt');
    await finish(tester);
  });

  pruefung('IMP-109 Namen für erkannte Gesichter', (tester) async {
    await startApp(tester);
    final id = (await importiereDirekt(tester, [
      testfoto('gruppe.jpg'),
    ])).single;
    await befehl(tester, const PersonAnlegen('pa', 'person a'));
    await befehl(tester, const PersonAnlegen('pb', 'Person B'));
    await hintergrund(tester, () async {
      final db = bibliothek.db;
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'f1',
              assetId: id,
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.3,
            ),
          );
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'f2',
              assetId: id,
              personId: const Value('pb'),
              boxX: 0.6,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.3,
            ),
          );
    });
    final a = await aufnahme(tester, 'gruppe.jpg');
    bibliothek.paths
        .absolute(bibliothek.paths.xmpSidecarPath(a.relativePath))
        .writeAsStringSync(
          xmpPaket(
            regionen: [
              (name: 'Person A', x: 0.2, y: 0.25, w: 0.2, h: 0.3),
              (name: 'Person C', x: 0.7, y: 0.25, w: 0.2, h: 0.3),
            ],
          ),
        );
    await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
    final zeile =
        '${de.xmpFeldGesichter}: ${de.xmpGesichterOhneNamen(1)} → "Person A"';
    await waitFor(tester, find.text(zeile));
    await tap(
      tester,
      find.descendant(
        of: find.ancestor(
          of: find.text(zeile),
          matching: find.byType(ListTile),
        ),
        matching: find.widgetWithText(TextButton, de.allgUebernehmen),
      ),
    );
    await waitGone(tester, find.text(zeile));
    final gesichter = await hintergrund(
      tester,
      () => bibliothek.db.facesForAsset(id),
    );
    expect(gesichter.singleWhere((g) => g.id == 'f1').personId, 'pa');
    expect(gesichter.singleWhere((g) => g.id == 'f2').personId, 'pb');
    final personen = await hintergrund(
      tester,
      () => bibliothek.db.allePersonen(),
    );
    expect(personen, hasLength(2));
    await finish(tester);
  });

  pruefung('IMP-111 Aus Ordner einlesen (ohne Server)', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('foto.jpg')]);
    final o = quellordner('beilagen');
    File(p.join(o.path, 'foto.xmp')).writeAsStringSync(xmpPaket(bewertung: 4));
    await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
    await waitFor(tester, find.text(de.xmpKeineSidecars));
    dialog.ordner = o.path;
    await tap(tester, find.byTooltip(de.xmpOrdnerWaehlen));
    await waitFor(tester, find.text('${de.xmpFeldBewertung}: "0" → "4"'));
    expect(find.text('foto.jpg'), findsOneWidget);
    await finish(tester);
  });

  pruefung('IMP-113 Gesperrte und gelöschte Fotos werden übergangen', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('gesperrt.jpg'),
      testfoto('geloescht.jpg'),
      testfoto('normal.jpg'),
    ]);
    for (final n in ['gesperrt.jpg', 'geloescht.jpg', 'normal.jpg']) {
      final a = await aufnahme(tester, n);
      bibliothek.paths
          .absolute(bibliothek.paths.xmpSidecarPath(a.relativePath))
          .writeAsStringSync(xmpPaket(bewertung: 5));
    }
    final g = await aufnahme(tester, 'gesperrt.jpg');
    final l = await aufnahme(tester, 'geloescht.jpg');
    await hintergrund(tester, () async {
      final db = bibliothek.db;
      await (db.update(db.assets)..where((t) => t.id.equals(g.id))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
    });
    await befehl(tester, InDenPapierkorb([l.id]));
    await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
    await waitFor(tester, find.text('normal.jpg'));
    expect(find.text('gesperrt.jpg'), findsNothing);
    expect(find.text('geloescht.jpg'), findsNothing);
    expect(find.widgetWithText(TextButton, de.allgUebernehmen), findsOneWidget);
    await finish(tester);
  });

  // === Import – mit Server (PV_E2E_SERVER=1) ================================

  pruefung('IMP-085 IMP-089 IMP-111 MitServer: Import lädt hoch, Fotokammer, '
      'XMP aus Ordner', (tester) async {
    await startApp(tester);
    final d = Durchreiche(Uri.parse(serverAdresse));
    await d.starte();
    await verbinde(tester, d);
    // IMP-085
    final a = testfoto('srv_a.jpg', datum: DateTime(2023, 3, 1, 9));
    final b = testfoto('srv_b.jpg', datum: DateTime(2023, 3, 2, 9));
    final quellen = {'srv_a.jpg': pruefsumme(a), 'srv_b.jpg': pruefsumme(b)};
    await planMitDateien(tester, [a, b]);
    await kammerAus(tester);
    await starte(tester, 2);
    await warteAufAbschluss(tester);
    expect(find.textContaining('2 / 2'), findsOneWidget);
    expect(find.textContaining('nicht herein'), findsNothing);
    await schliesseBlatt(tester);
    await eventually(
      tester,
      () async {
        final namen = (await _alle()).map((x) => x.originalFileName).toSet();
        return namen.containsAll(quellen.keys);
      },
      timeout: const Duration(seconds: 60),
      was: 'über den Abgleich da',
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    for (final n in quellen.keys) {
      final x = await aufnahme(tester, n);
      await sieheKachel(tester, x.id);
      expect(
        await hintergrund(tester, () => serverPruefsumme(x.id)),
        quellen[n],
      );
    }

    // IMP-089: Erst in die Fotokammer.
    final k = testfoto('srv_kammer.jpg', datum: DateTime(2023, 3, 3, 9));
    await planMitDateien(tester, [k]);
    final schalter = find.widgetWithText(
      SwitchListTile,
      de.importKammerSchalter,
    );
    await waitFor(tester, schalter);
    if (!tester.widget<SwitchListTile>(schalter).value) {
      await tap(tester, schalter);
    }
    final knopf = find.ancestor(
      of: find.text(de.importPlanStartenKammer(1)),
      matching: find.byType(FilledButton),
    );
    await starteKnopf(tester, knopf);
    await warteAufAbschluss(tester);
    expect(find.textContaining(de.importBilanzKammer(1)), findsOneWidget);
    expect(find.text(de.importZurKammer), findsOneWidget);
    await schliesseBlatt(tester);
    await warte(tester, const Duration(seconds: 8));
    final sichtbar = (await aufnahmen(
      tester,
    )).where((x) => x.originalFileName == 'srv_kammer.jpg');
    for (final x in sichtbar) {
      expect(kachel(x.id), findsNothing);
    }

    // IMP-111: Beilagen aus einem Ordner (verbundene Bibliothek).
    final o = quellordner('xmp_server');
    File(p.join(o.path, 'srv_a.xmp')).writeAsStringSync(xmpPaket(bewertung: 4));
    await oeffneWerkzeug(tester, de.werkzXmpLesenTitel);
    await waitFor(tester, find.byTooltip(de.xmpOrdnerWaehlen));
    await settle(tester);
    dialog.ordner = o.path;
    await tap(tester, find.byTooltip(de.xmpOrdnerWaehlen));
    await waitFor(tester, find.text('${de.xmpFeldBewertung}: "0" → "4"'));
    expect(find.text('srv_a.jpg'), findsOneWidget);
    await zurueck(tester);
    // Die Durchreiche bleibt offen: Was die App nach finish noch
    // holt, soll nicht als Fehler auf diese Prüfung fallen.
    await finish(tester);
  }, skip: serverAdresse.isEmpty);

  pruefung(
    'IMP-086 IMP-087 MitServer: ältere Serverfassung, Server nicht erreichbar',
    (tester) async {
      await startApp(tester);
      final d = Durchreiche(Uri.parse(serverAdresse));
      await d.starte();
      await verbinde(tester, d);
      // IMP-086
      d.alterServer = true;
      final alt = testfoto('srv_alt.jpg', datum: DateTime(2023, 4, 1));
      await planMitDateien(tester, [alt]);
      await kammerAus(tester);
      expect(find.text(de.importPlanServerAlt), findsOneWidget);
      expect(frei(tester, startknopf(1)), isFalse);
      await planAbbrechen(tester);
      d.alterServer = false;

      // IMP-087
      final fs = [
        for (var i = 1; i <= 3; i++)
          testfoto('srv_weg$i.jpg', datum: DateTime(2023, 4, 1 + i)),
      ];
      await planMitDateien(tester, fs);
      await kammerAus(tester);
      await d.halteAn();
      final t0 = DateTime.now();
      await starte(tester, 3);
      var sahWarnung = false;
      final ende = DateTime.now().add(const Duration(minutes: 4));
      while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
        if (DateTime.now().isAfter(ende)) fail('Import endet nicht');
        await tester.pump(const Duration(milliseconds: 100));
        if (find.text(de.importPlanGeaendert).evaluate().isNotEmpty) {
          sahWarnung = true;
        }
      }
      final dauer = DateTime.now().difference(t0);
      await settle(tester);
      if (find.text(de.importPlanGeaendert).evaluate().isNotEmpty) {
        sahWarnung = true;
      }
      debugPrint('IMP-087: Dauer $dauer, Warnung „geändert“: $sahWarnung');
      expect(dauer, lessThan(const Duration(seconds: 90)));
      expect(find.textContaining(de.importBilanzFehler(3)), findsOneWidget);
      await tap(tester, find.text(de.importFehlerWarum));
      expect(
        find.text('3 × ${de.importFehlerKeineVerbindung}'),
        findsOneWidget,
      );
      await d.starte();
      await warte(tester, const Duration(seconds: 3));
      await tap(tester, find.text(de.importErneutVersuchen(3)));
      await waitGone(
        tester,
        find.text(de.importErneutVersuchen(3)),
        timeout: const Duration(seconds: 90),
      );
      await warteAufAbschluss(tester, timeout: const Duration(minutes: 3));
      expect(find.textContaining('nicht herein'), findsNothing);
      await schliesseBlatt(tester);
      await eventually(
        tester,
        () async {
          final namen = (await _alle()).map((x) => x.originalFileName).toSet();
          return namen.containsAll([
            'srv_weg1.jpg',
            'srv_weg2.jpg',
            'srv_weg3.jpg',
          ]);
        },
        timeout: const Duration(seconds: 90),
        was: 'nach Neustart hereingeholt',
      );
      // Die Durchreiche bleibt offen: Was die App nach finish noch
      // holt, soll nicht als Fehler auf diese Prüfung fallen.
      await finish(tester);
    },
    skip: serverAdresse.isEmpty,
    timeout: const Timeout(Duration(minutes: 12)),
  );

  // Behoben in #409: Der Abbruch meldet den Grund über importFehlertext,
  // und „pv_import_server_zu_alt“ wird zum Satz.
  pruefung('IMP-087 Befund MitServer: Abbruch nennt den richtigen Grund', (
    tester,
  ) async {
    await startApp(tester);
    final d = Durchreiche(Uri.parse(serverAdresse));
    await d.starte();
    await verbinde(tester, d);
    // Server nach der Prüfung weg.
    final f = testfoto('srv_grund1.jpg', datum: DateTime(2023, 5, 1));
    await planMitDateien(tester, [f]);
    await kammerAus(tester);
    await d.halteAn();
    await starte(tester, 1);
    var sahWarnung = false;
    final ende = DateTime.now().add(const Duration(minutes: 3));
    while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende)) fail('Import endet nicht');
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(de.importPlanGeaendert).evaluate().isNotEmpty) {
        sahWarnung = true;
      }
    }
    await schliesseBlatt(tester);
    await d.starte();
    // Server wird nach der Prüfung „älter“.
    final g = testfoto('srv_grund2.jpg', datum: DateTime(2023, 5, 2));
    await planMitDateien(tester, [g]);
    await kammerAus(tester);
    d.alterServer = true;
    await starte(tester, 1);
    var sahWarnung2 = false;
    final ende2 = DateTime.now().add(const Duration(minutes: 3));
    while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende2)) fail('Import endet nicht');
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(de.importPlanGeaendert).evaluate().isNotEmpty) {
        sahWarnung2 = true;
      }
    }
    await tap(tester, find.text(de.importFehlerWarum));
    final roh = find
        .textContaining('pv_import_server_zu_alt')
        .evaluate()
        .isNotEmpty;
    debugPrint(
      'IMP-087 Befund: Warnung weg=$sahWarnung alt=$sahWarnung2 roh=$roh',
    );
    expect(sahWarnung, isFalse, reason: 'Server weg, Meldung sagt „geändert“');
    expect(
      sahWarnung2,
      isFalse,
      reason: 'Server zu alt, Meldung sagt „geändert“',
    );
    expect(roh, isFalse, reason: 'Grund als Kennung statt als Satz');
    // Die Durchreiche bleibt offen: Was die App nach finish noch
    // holt, soll nicht als Fehler auf diese Prüfung fallen.
    await finish(tester);
  }, skip: serverAdresse.isEmpty);

  pruefung('IMP-103 MitServer: Überwachter Ordner lädt beim Einrichten hoch', (
    tester,
  ) async {
    await startApp(tester);
    final d = Durchreiche(Uri.parse(serverAdresse));
    await d.starte();
    await verbinde(tester, d);
    final w = quellordner('srv_ueberwacht');
    altern(nach(testfoto('srv_w1.jpg', datum: DateTime(2023, 6, 1)), w));
    altern(nach(testfoto('srv_w2.jpg', datum: DateTime(2023, 6, 2)), w));
    await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
    dialog.ordner = w.path;
    await tippeMitMeldung(
      tester,
      find.text(de.einstUeberwachtWaehlen),
      de.einstUeberwachtUebernommen(2),
    );
    expect(find.text(de.einstUeberwachtAktiv), findsOneWidget);
    await eventually(
      tester,
      () async {
        final namen = (await _alle()).map((x) => x.originalFileName).toSet();
        return namen.containsAll(['srv_w1.jpg', 'srv_w2.jpg']);
      },
      timeout: const Duration(seconds: 60),
      was: 'über den Abgleich da',
    );
    for (final n in ['srv_w1.jpg', 'srv_w2.jpg']) {
      final x = await aufnahme(tester, n);
      expect(
        await hintergrund(tester, () => serverPruefsumme(x.id)),
        isNotNull,
      );
    }
    // Die Durchreiche bleibt offen: Was die App nach finish noch
    // holt, soll nicht als Fehler auf diese Prüfung fallen.
    await finish(tester);
  }, skip: serverAdresse.isEmpty);

  // Behoben in #409: Der Fünf-Minuten-Takt des überwachten Ordners läuft auch
  // verbunden (LibraryState.richteOrdnertaktEin).
  pruefung(
    'IMP-103 Befund MitServer: später gelegtes Foto kommt im Takt',
    (tester) async {
      await startApp(tester);
      final d = Durchreiche(Uri.parse(serverAdresse));
      await d.starte();
      await verbinde(tester, d);
      final start = DateTime.now();
      final w = quellordner('srv_takt');
      await oeffneEinstellungsgruppe(tester, de.einstUeberwachtTitel);
      dialog.ordner = w.path;
      await tippeMitMeldung(
        tester,
        find.text(de.einstUeberwachtWaehlen),
        de.einstUeberwachtNichtsNeues,
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      altern(nach(testfoto('srv_takt.jpg', datum: DateTime(2023, 7, 1)), w));
      final bis = start.add(const Duration(minutes: 5, seconds: 40));
      var da = false;
      while (DateTime.now().isBefore(bis) && !da) {
        await warte(tester, const Duration(seconds: 5));
        da = (await aufnahmen(
          tester,
        )).any((a) => a.originalFileName == 'srv_takt.jpg');
      }
      debugPrint(
        'IMP-103 Befund: nach ${DateTime.now().difference(start)} da=$da',
      );
      expect(da, isTrue, reason: 'mit Server kein Fünf-Minuten-Takt');
      // Die Durchreiche bleibt offen: Was die App nach finish noch
      // holt, soll nicht als Fehler auf diese Prüfung fallen.
      await finish(tester);
    },
    skip: serverAdresse.isEmpty,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

// ---------------------------------------------------------------------------
// Kleine Probedateien, mit ffmpeg/cwebp erzeugt (Testbild, keine Fotos).
// ---------------------------------------------------------------------------

const _webpProbe =
    'UklGRmQFAABXRUJQVlA4IFgFAABwHwCdASp4AFAAPrVOoEqnJCMhpNVfSOAWiWwAyrIm/kH43dp9nHqn5GfkB0y2/fg/nzCoepvwJ+q/Jz/Je/b1L/jr/a+4d/fv6/6//Qp5iv1u9Vf+7/8b/S+5b/VeoB/Of8N6SXsq+gv/AP876Xv7UfCz+4vo4ZqJ2WUQn9mluGM1xY+fd/o/ar7m8zfqvfsr7Cn7KoDrNsVQW6ezW6eY2K5waWoTHeLb/UDxzZevVvR1+dt1K2DIKfPvjqK64u1MLFmXeKBWIFgSV/jl9KfHuLvOG4P0vmv/9zDLe4SjOFiYP9uq4zQMMTwWla16WcNWj8VrrWhYke3hQMjGk+LpNaTsQAD+9arLlZQUL1GLB6vYs6UxFUZ7Uvgr/DtzxGkac+kTSkrW/DtyP5YY9lhDFA6axu99vGOMJWxMWYaly/lmLBIEl8gKO1n1G7s9vzJVG4mK/SCrBbn5z+ekghewHiMsfRE93VaJMCCr8feJWlZXWsdyL8gh99nf/1Tff/VGf+qPYV6+VAG8364l94tJxrAasRi5QrnjQBa0Ylo1ee5svV/nZ87Pnqg9HWkSUMHcdgGmHLZip0hc0zzLRo1gRxPw/9/nm19/2cT3o+j7jn+aCljsZWXABw6shaxrBJEcT0xtAsyyzjSHkstkNuPEdnpNbxNEDRuxu9Gryg7hlJnSbZA8IPDfoemBMQrUx03492RHM/QMb5jXDae3alczRAOJZrIOMtOnKXZ7jiJ/dAzCyLT5Kxc7Ae8nWA+3Cb78lKPgyesIzxDYBMNnRRknlka7pzfQAJu5SyrgdAgI2RO9Fkq8wz6WlfJ3SRf2eHbOhnLHF8yXPGgms6VKFJbtGyxCZ5LNw9NBXAvWaUZEAdwSq5khqyrKkkJNcBuXkY6vaVOdHMDIguX8D5vfkO/Hc7DPqJQaa3aqtofqfe2jPnam2d1PKj772OVc9373I137XD5Zwz3ysg+f/8N2utN/QpVaKtDwX9eH81XgeBv4M2uPLGGz2FZ4g+LKxHe3/UGfoRNvLhDm3jqn4+WkohsnS24rDldf8xt96XIXKsy8CZsXyGk/XnNUorF84bkqU4FAsSYG9sNHktTRz/zGMUvFoYFbpqBNJ5SZbsUErlX9PfsIbaXD5XkI5ZygX23nJ+73j5+II0/qofyYWEXv2zqnkVe8Pntv3f/GkmQt0WdLx9oXG5j5K5XlyUu0vQXPceW+0js8nwXv8vEgyhehhdW8PdN+dnsET/3evn0j621GJbtaVSzsuGUCDdeav+lHwFefTi1Z3yxdO0XHONVyutvoaZE47Qe/apbkPfdQNnVezQ+PCTj3B/oFO1VG86WUxV9j5OwjHqsKv3EMcckt/KMY+/l8Zn+PixeyMr4uCpAWzcQJU76B/o8/hHrywSLiqZZOeuvNtdnO18HU5bO+4jGT+k7eb7+FoNIhNDF480Taam18AhgJpydt6n3AZG+cPH4xjQ+HOnXhMcWIQwLCRLv99/nbCCjtzXG40uEB8SAxspfiyEsQiTH5/kkefXE5suJtz4OXNFg2QvGg8FgOta9lmqv6JUsWezj/oVIb+bpdEca+AlaJDN5UNHF8rE/WMQIXex7bd/jDa5vytpqjqG1XCGozjBrNP/Zcw/wOS4C/RhAOHmH/CKZWLqIfjUzzIh/kk/M4odJUEaeFiS31ZXhp3zEx9HxPphXr9M+1uQwN7F3tqIIYPVcDGBPdRiWTrfCZ+49C6ue9ZdbjvqLXa9Qrr7zlqkjtiRVbxYG9/8c++A6zybHJuPDssuyvU+DxbeWSBxmh2ZDoPlP3Pqn9EJlrs8SXKnchAAA=';

const _mtsProbe =
    'R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAQAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABAAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAMC1QAAB7DH4A//////////////////////////////////////////////////8AAAHgAACAwAoxAAf1rREAB9hhAAABswQAMCL//+AAAAABtRSKAAEAAAAAAbgACABAAAABAAAP//gAAAG1j//zQYAAAAEBE/lFKUv3C825SlIi5SlIi5SlIiAAAAECE/lFKUv3C825SlIi5SlIi5SlIiAAAAEDE/lFKUv3C825SlIi5SlIi5SlIiBHQQAxfQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAJEvkRAAf1rQAAAQAAV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADJ9EAAAibJ+AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAkwRREACRL5AAABAACX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AAEQAAsA0AAcEAAAAB8AAqsQSy//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HUAARAAKwEgABwQAA4QDwAALhAPAAnosj0f///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dBADN9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAlNkREACTBFAAABAADX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EANH0QAACYWH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEACWrdEQAJTZEAAAEAARf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA1fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAJiCkRAAlq3QAAAQABV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdAABIAALANAAHBAAAAAfAAKrEEsv//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R1AAEgACsBIAAcEAAOEA8AAC4QDwAJ6LI9H///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQQA2fRAAAKb+fgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAJpXURAAmIKQAAAQABl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADd9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAnCwREACaV1AAABAAHX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAOH0QAAC1pH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEACeANEQAJwsEAAAEAAhf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQAATAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABMAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAOX0A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEACf1ZEQAJ4A0AAAEAAlf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA6fRAAAMRKfgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQALGqURAAn9WQAAAQACl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADt9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAs38REACxqlAAABAALX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AREQBC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAUAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABQAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAPC1QAADS8H4A//////////////////////////////////////////////////8AAAHgAACAwAoxAAtVPREACzfxAAABswQAMCL//+AAAAABtRSKAAEAAAAAAbgACAYAAAABAAAP//gAAAG1j//zQYAAAAEBE/lFKUv3C825SlIi5SlIi5SlIiAAAAECE/lFKUv3C825SlIi5SlIi5SlIiAAAAEDE/lFKUv3C825SlIi5SlIi5SlIiBHQQA9fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQALcokRAAtVPQAAAQAAV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBAD59EAAA4ZZ+AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAuP1REAC3KJAAABAACX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AAFQAAsA0AAcEAAAAB8AAqsQSy//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HUAAVAAKwEgABwQAA4QDwAALhAPAAnosj0f///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dBAD99AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAAutIREAC4/VAAABAADX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAMH0QAADwPH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAC8ptEQALrSEAAAEAARf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQAxfQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAL57kRAAvKbQAAAQABV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdAABYAALANAAHBAAAAAfAAKrEEsv//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R1AAFgACsBIAAcEAAOEA8AAC4QDwAJ6LI9H///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQQAyfRAAAP7ifgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQANBQURAAvnuQAAAQABl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADN9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA0iUREADQUFAAABAAHX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EANH0QAAENiH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEADT+dEQANIlEAAAEAAhf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQAAXAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABcAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EANX0A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEADVzpEQANP50AAAEAAlf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA2fRAAARwufgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQANejURAA1c6QAAAQACl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADd9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA2XgREADXo1AAABAALX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AREgBC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAYAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABgAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAOC1QAAEq1H4A//////////////////////////////////////////////////8AAAHgAACAwAoxAA20zREADZeBAAABswQAMCL//+AAAAABtRSKAAEAAAAAAbgACCAAAAABAAAP//gAAAG1j//zQYAAAAEBE/lFKUv3C825SlIi5SlIi5SlIiAAAAECE/lFKUv3C825SlIi5SlIi5SlIiAAAAEDE/lFKUv3C825SlIi5SlIi5SlIiBHQQA5fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAN0hkRAA20zQAAAQAAV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADp9EAABOXp+AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA3vZREADdIZAAABAACX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AAGQAAsA0AAcEAAAAB8AAqsQSy//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HUAAZAAKwEgABwQAA4QDwAALhAPAAnosj0f///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dBADt9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA8MsREADe9lAAABAADX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAPH0QAAFIIH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEADyn9EQAPDLEAAAEAARf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA9fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAPR0kRAA8p/QAAAQABV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdAABoAALANAAHBAAAAAfAAKrEEsv//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R1AAGgACsBIAAcEAAOEA8AAC4QDwAJ6LI9H///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQQA+fRAAAVbGfgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAPZJURAA9HSQAAAQABl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBAD99AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA+B4READ2SVAAABAAHX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAMH0QAAFlbH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAD58tEQAPgeEAAAEAAhf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQAAbAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABsAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAMX0A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAD7x5EQAPny0AAAEAAlf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQAyfRAAAXQSfgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQAP2cURAA+8eQAAAQACl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADN9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxAA/3EREAD9nFAAABAALX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AREwBC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQAAcAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQABwAArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EANC1QAAGCuH4A//////////////////////////////////////////////////8AAAHgAACAwAoxABEUXREAD/cRAAABswQAMCL//+AAAAABtRSKAAEAAAAAAbgACCYAAAABAAAP//gAAAG1j//zQYAAAAEBE/lFKUv3C825SlIi5SlIi5SlIiAAAAECE/lFKUv3C825SlIi5SlIi5SlIiAAAAEDE/lFKUv3C825SlIi5SlIi5SlIiBHQQA1fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQARMakRABEUXQAAAQAAV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADZ9EAABkV5+AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxABFO9REAETGpAAABAACX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0AAHQAAsA0AAcEAAAAB8AAqsQSy//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HUAAdAAKwEgABwQAA4QDwAALhAPAAnosj0f///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dBADd9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxABFsQREAEU71AAABAADX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAOH0QAAGgBH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAEYmNEQARbEEAAAEAARf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA5fQD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQARptkRABGJjQAAAQABV//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdAAB4AALANAAHBAAAAAfAAKrEEsv//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R1AAHgACsBIAAcEAAOEA8AAC4QDwAJ6LI9H///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////9HQQA6fRAAAa6qfgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQARxCURABGm2QAAAQABl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBADt9AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxABHhcREAEcQlAAABAAHX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRwR0EAPH0QAAG9UH4A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAEf69EQAR4XEAAAEAAhf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQAAfAACwDQABwQAAAAHwACqxBLL//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////0dQAB8AArASAAHBAADhAPAAAuEA8ACeiyPR////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////R0EAPX0A/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////wAAAeAAAIDACjEAExwJEQAR/r0AAAEAAlf/+4AAAAG1gR/zQYAAAAEBEnRwAAABAhJ0cAAAAQMSdHBHQQA+fRAAAcv2fgD/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////AAAB4AAAgMAKMQATOVURABMcCQAAAQACl//7gAAAAbWBH/NBgAAAAQESdHAAAAECEnRwAAABAxJ0cEdBAD99AP////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AAAHgAACAwAoxABNWoREAEzlVAAABAALX//uAAAABtYEf80GAAAABARJ0cAAAAQISdHAAAAEDEnRw';

const _mpgProbe =
    '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////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////';

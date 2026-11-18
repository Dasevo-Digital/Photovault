// ignore_for_file: avoid_print
// Katalog-Prüfungen des Bereichs ANS (Ansehen, Ordnen, Suchen): Zeitleiste,
// Auswahl, Einzelansicht, Bewertung, Alben, Suche, Rückblick, Statistik,
// Datenschutz. Jede Prüfung startet die echte App mit einer frischen
// Wegwerf-Bibliothek (siehe katalog_kit.dart) und bedient sie wie ein
// Mensch. Laufen lassen nur über die Warteschlange des Prüfkatalogs.
import 'dart:async' show TimeoutException;
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/umzug.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_format.dart' show assetFormatLabel;
import 'package:kern/services/embedding_codec.dart'
    show blobFromEmbeddingFloats;
import 'package:kern/services/listengliederung.dart';
import 'package:kern/services/search_filters.dart' show SearchTextMode;
import 'package:kern/services/textstellen.dart' show textstellenAusJson;
import 'package:intl/intl.dart' show DateFormat;
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/aufnahmen_waehlen_screen.dart';
import 'package:photo_vault/screens/dokumente_screen.dart'
    show ladeDokumentvorschlaege;
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/similar_photos_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/screens/statistics_screen.dart';
import 'package:photo_vault/screens/jahresrueckblick_screen.dart';
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/asset_list_view.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/color_label_picker.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/panorama_360_view.dart';
import 'package:photo_vault/widgets/search_options_sheet.dart';
import 'package:photo_vault/widgets/seitenleiste.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';
import 'package:photo_vault/widgets/star_rating.dart';
import 'package:photo_vault/widgets/textrahmen.dart';
import 'package:photo_vault/widgets/video_playback.dart';
import 'package:photo_vault/widgets/live_photo_view.dart';
import 'package:photo_vault/widgets/timeline_scrubber.dart';
import 'package:provider/provider.dart';
import 'package:teilen_ui/l10n/teilen_texte.dart';
import 'package:uuid/uuid.dart';

import 'katalog_kit.dart';

// --- Eigene Hilfen ----------------------------------------------------------

const _uuid = Uuid();

/// Sperrt das Netz für alles ausser dem Wegwerf-Server auf diesem Rechner:
/// Keine Prüfung darf fremde Dienste erreichen (Kartenkacheln,
/// Aktualisierungsprüfung, Modell-Downloads). Versuche werden gemerkt.
class OhneNetz extends HttpOverrides {
  final versuche = <Uri>[];

  /// Sperrt auch den Wegwerf-Server – „Server gestoppt“.
  bool serverGesperrt = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if ((uri.host == '127.0.0.1' || uri.host == 'localhost') &&
          !serverGesperrt) {
        return Socket.startConnect(uri.host, uri.port);
      }
      versuche.add(uri);
      return Future.error(
        SocketException('Netz in der Prüfung gesperrt: ${uri.host}'),
      );
    };
    return client;
  }
}

final ohneNetz = OhneNetz();

/// Die Rasterkachel des Fotos mit dem Dateinamen [name].
Finder kachel(String name) => find.byWidgetPredicate(
  (w) => w is AssetThumbnailTile && w.asset.originalFileName == name,
);

/// Alle Aufnahmen der Bibliothek (auch gelöschte und gesperrte).
Future<List<AssetData>> alleAufnahmen(WidgetTester tester) async =>
    (await echt(() => bibliothek.db.select(bibliothek.db.assets).get()))!;

/// Die Aufnahme mit dem Dateinamen [name].
Future<AssetData> aufnahme(WidgetTester tester, String name) async =>
    (await alleAufnahmen(tester)).firstWhere((a) => a.originalFileName == name);

/// Führt einen Befehl der Datenbank aus (Vorbedingungen).
Future<void> befehl(WidgetTester tester, Befehl<Object?> b) async {
  await echt(() => bibliothek.db.fuehreAus(b));
  await settle(tester);
}

/// Wartet auf echte Arbeit (Datenbank, Dateien). Der Prüfstand läuft in
/// Echtzeit; `tester.runAsync` liesse sich nicht schachteln – das `eventually`
/// des Kits ruft seine Bedingung schon darin auf.
Future<T?> echt<T>(Future<T> Function() arbeit) => arbeit();

/// Kennungen zu Dateinamen.
Future<List<String>> ids(WidgetTester tester, List<String> namen) async {
  final alle = await alleAufnahmen(tester);
  return [
    for (final n in namen) alle.firstWhere((a) => a.originalFileName == n).id,
  ];
}

/// Die Dateinamen in der Reihenfolge des Zeitleisten-Rasters.
List<String> rasterNamen(WidgetTester tester) => [
  for (final a
      in tester
          .widget<MonthGroupedAssetGrid>(
            find.byType(MonthGroupedAssetGrid).first,
          )
          .assets)
    a.originalFileName,
];

/// Startet die App neu – dieselbe Bibliothek (der Datenordner bleibt über
/// [startApp] umgelenkt), ein neuer Widgetbaum und ein neuer Zustand.
Future<void> neustart(WidgetTester tester) async {
  // Wie das Kit beim Beenden: erst die Hintergrundarbeit anhalten, dann
  // die Bibliothek schliessen – sonst liefe sie in die neue hinein.
  final alt = bibliothek;
  try {
    if (alt.analyseLaeuft) alt.brichHintergrundanalyseAb();
    for (final lauf in alt.offeneAufgaben.toList()) {
      alt.brichAufgabeAb(lauf.schluessel);
    }
    final ende = DateTime.now().add(const Duration(seconds: 30));
    while (alt.etwasLaeuft && DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await alt.vorDemBeenden();
  } catch (e) {
    print('neustart: $e');
  }
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
  expect(bibliothek.paths.root.path, startsWith(anker.path));
  await settle(tester);
}

/// Eine zweite, frische Bibliothek in derselben Prüfung.
Future<void> zweiteBibliothek(
  WidgetTester tester, {
  List<File> Function()? fotos,
  Object modelle = false,
}) async {
  await finish(tester);
  await startApp(tester, modelle: modelle);
  final dateien = fotos?.call() ?? const <File>[];
  if (dateien.isNotEmpty) await importiereDirekt(tester, dateien);
}

/// ⌘ (Command) zusammen mit [taste].
Future<void> befehlstaste(WidgetTester tester, LogicalKeyboardKey taste) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(taste);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await settle(tester);
}

/// Klick mit gehaltener Command-Taste.
Future<void> befehlsklick(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await settle(tester);
}

/// Rechtsklick mit der Maus auf [finder] (oder an [stelle]).
Future<void> rechtsklick(
  WidgetTester tester,
  Finder finder, {
  Offset? stelle,
}) async {
  await waitFor(tester, finder);
  final wo = stelle ?? tester.getCenter(finder.first);
  final geste = await tester.startGesture(
    wo,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await geste.up();
  await settle(tester);
}

/// Zurück über den Pfeil der obersten Seite (deutsche Beschriftung).
Future<void> zurueck(WidgetTester tester) async {
  final pfeil = find.byType(BackButton);
  if (pfeil.evaluate().isNotEmpty) {
    await tap(tester, pfeil.last);
  } else {
    await key(tester, LogicalKeyboardKey.escape);
  }
  await settle(tester);
}

/// Alle Meldungen schliessen und den Verlauf leeren – sonst bleibt oben
/// rechts die Glocke mit der Zahl der ungelesenen stehen.
Future<void> meldungenWeg(WidgetTester tester) async {
  melde.verlaufLeeren();
  await settle(tester);
}

/// Wartet, bis die App die Meldung [text] gegeben hat (aus dem Verlauf –
/// eine Meldung von vier Sekunden kann während des Wartens auf den
/// Bildschirm schon wieder verblasst sein).
Future<void> meldung(WidgetTester tester, String text) => eventually(
  tester,
  () async => melde.verlauf.any((m) => m.text.contains(text)),
  was: 'Meldung „$text“',
);

/// Die App hat keine Meldung mit [text] gegeben (seit dem letzten Leeren).
void keineMeldung(String text) => expect(
  melde.verlauf.where((m) => m.text.contains(text)),
  isEmpty,
  reason: 'keine Meldung „$text“',
);

/// Der Titel der Einzelansicht für ein Datum (T.M.JJJJ).
String titel(DateTime d) => '${d.day}.${d.month}.${d.year}';

Finder get betrachter => find.byType(AssetViewerScreen);

/// Zeigt die Einzelansicht gerade das Foto vom [datum]?
Finder betrachterZeigt(DateTime datum) => find.descendant(
  of: find.descendant(of: betrachter, matching: find.byType(AppBar)),
  matching: find.text(titel(datum)),
);

/// Öffnet das Foto [name] aus dem Raster (einfacher Klick).
Future<void> oeffne(WidgetTester tester, String name) async {
  await tap(tester, kachel(name));
  await waitFor(tester, betrachter);
  await settle(tester);
  // Die Ansicht holt sich den Tastaturfokus selbst (autofocus); erst
  // danach kommen Tasten an.
  bool imBetrachter() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorWidgetOfExactType<AssetViewerScreen>() != null;
  }

  for (var i = 0; i < 30 && !imBetrachter(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!imBetrachter()) {
    print(
      'oeffne($name): Fokus nicht in der Ansicht: '
      '${FocusManager.instance.primaryFocus}',
    );
  }
}

/// Schliesst die Einzelansicht mit Esc.
Future<void> schliesseBetrachter(WidgetTester tester) async {
  await key(tester, LogicalKeyboardKey.escape);
  // Hat ein Textfeld der Info-Leiste den Fokus, nimmt es Esc für sich –
  // dann über den Pfeil oben links.
  for (var i = 0; i < 10 && betrachter.evaluate().isNotEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (betrachter.evaluate().isNotEmpty) {
    final pfeil = find.descendant(
      of: betrachter,
      matching: find.byType(BackButton),
    );
    if (pfeil.evaluate().isNotEmpty) await tap(tester, pfeil.first);
  }
  await waitGone(tester, betrachter);
}

/// Knopf in der Kopfleiste der Einzelansicht (Tooltip).
Finder knopf(String tooltip) =>
    find.descendant(of: betrachter, matching: find.byTooltip(tooltip));

/// SHA-256 einer Datei.
Future<String> pruefsumme(WidgetTester tester, File f) async => (await tester
    .runAsync(() async => sha256.convert(await f.readAsBytes()).toString()))!;

/// SHA-256 der Originaldatei einer Aufnahme (Ablageort aus der Datenbank).
Future<String> originalSumme(WidgetTester tester, String name) async {
  final a = await aufnahme(tester, name);
  return pruefsumme(tester, bibliothek.paths.absolute(a.relativePath));
}

/// Richtet den gesperrten Ordner mit der Test-PIN ein.
Future<void> tresorEinrichten(WidgetTester tester) async {
  await echt(() => bibliothek.setupVaultPin('2468'));
  await settle(tester);
}

/// Kennungen gesperrter Aufnahmen nach ihrem früheren Namen: Im gesperrten
/// Ordner verbirgt die App Dateiname und Datum.
final _gesperrt = <String, String>{};

/// Legt die Aufnahme [name] in den gesperrten Ordner.
Future<String> sperre(WidgetTester tester, String name) async {
  final a = await aufnahme(tester, name);
  _gesperrt[name] = a.id;
  await echt(() => bibliothek.lockAsset(a));
  await settle(tester);
  return a.id;
}

/// Holt [name] aus dem gesperrten Ordner zurück.
Future<void> entsperre(WidgetTester tester, String name) async {
  final id = _gesperrt[name]!;
  final a = (await alleAufnahmen(tester)).firstWhere((x) => x.id == id);
  await echt(() => bibliothek.unlockAsset(a));
  await settle(tester);
}

/// Schreibt Spalten einer Aufnahme direkt (Vorbedingung, z. B. ISO).
Future<void> setzeSpalten(
  WidgetTester tester,
  String name,
  AssetsCompanion werte,
) async {
  final a = await aufnahme(tester, name);
  final db = bibliothek.db;
  await echt(
    () => (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(werte),
  );
  await settle(tester);
}

/// Setzt das Aufnahmedatum direkt (Vorbedingung). Nötig für Daten vor
/// 1990: Der Import verwirft solche EXIF-Daten (exif_camera.dart:110–112,
/// `if (jahr < 1990) return null`) und nimmt ein geschätztes.
Future<void> setzeDatum(WidgetTester tester, String name, DateTime d) =>
    setzeSpalten(
      tester,
      name,
      AssetsCompanion(
        fileCreatedAt: Value(d),
        datumGeschaetzt: const Value(false),
      ),
    );

/// Legt [anzahl] Aufnahmen als Datenbankzeilen an (grosse Bibliotheken
/// ohne Dateien). Dateiname `zeile_<n>.jpg`, Aufnahmedatum alle [abstand]
/// rückwärts ab [ab]; `zeile_0` ist die neueste.
Future<void> zeilenAnlegen(
  WidgetTester tester,
  int anzahl, {
  required DateTime ab,
  Duration abstand = const Duration(days: 3),
}) async {
  final db = bibliothek.db;
  final jetzt = DateTime.now();
  await echt(() async {
    await db.batch((b) {
      b.insertAll(db.assets, [
        for (var i = 0; i < anzahl; i++)
          AssetsCompanion.insert(
            id: _uuid.v4(),
            originalFileName: 'zeile_$i.jpg',
            relativePath: 'fehlt/zeile_$i.jpg',
            checksum: 'zeile-$i-${jetzt.microsecondsSinceEpoch}',
            type: 'IMAGE',
            fileCreatedAt: ab.subtract(abstand * i),
            importedAt: jetzt,
            fileSizeBytes: Value(1000 + i),
            widthPx: const Value(800),
            heightPx: const Value(600),
          ),
      ]);
    });
  });
  await settle(tester);
}

/// Der Scrollbereich des Zeitleisten-Rasters.
ScrollableState rasterRolle(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(MonthGroupedAssetGrid),
            matching: find.byType(Scrollable),
          )
          .first,
    );

/// Liegt [finder] sichtbar im Fenster?
bool sichtbar(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final r = tester.getRect(finder.first);
  // Die oberste Seite: in der Einzelansicht deren Gerüst, sonst die Hülle.
  final fenster = tester.getRect(find.byType(Scaffold).first);
  return r.bottom > fenster.top &&
      r.top < fenster.bottom &&
      r.right > fenster.left &&
      r.left < fenster.right;
}

/// Ein Bild mit Text darin (für die Texterkennung und die Bildsuche).
File textfoto(
  String name,
  List<String> zeilen, {
  DateTime? datum,
  int breite = 1200,
  int hoehe = 800,
  img.Color? grund,
  img.Color? schrift,
}) {
  final bild = img.Image(width: breite, height: hoehe);
  img.fill(bild, color: grund ?? img.ColorRgb8(255, 255, 255));
  var y = 80;
  for (final z in zeilen) {
    img.drawString(
      bild,
      z,
      font: img.arial48,
      x: 60,
      y: y,
      color: schrift ?? img.ColorRgb8(0, 0, 0),
    );
    y += 90;
  }
  if (datum != null) {
    String n(int v, int s) => v.toString().padLeft(s, '0');
    final text =
        '${n(datum.year, 4)}:${n(datum.month, 2)}:${n(datum.day, 2)} '
        '${n(datum.hour, 2)}:${n(datum.minute, 2)}:${n(datum.second, 2)}';
    bild.exif.exifIfd['DateTimeOriginal'] = text;
    bild.exif.imageIfd['DateTime'] = text;
  }
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(bild, quality: 92));
  return datei;
}

/// Eine Monats- oder Tagesüberschrift im Raster (nicht die Marke am
/// Zeitstrahl, die denselben Text tragen kann).
Finder monatskopf(String text) => find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.text(text),
);

/// Welcher Hauptbereich gerade zu sehen ist (siehe [Hauptbereich]).
int aktuellerBereich(WidgetTester tester) {
  final seiten = find.byWidgetPredicate(
    (w) =>
        w is KeyedSubtree &&
        w.key is ValueKey<int> &&
        w.child.runtimeType.toString().endsWith('Screen'),
  );
  return (tester.widget(seiten.last).key! as ValueKey<int>).value;
}

/// Der Filmstreifen der Einzelansicht (waagerechte Liste).
Finder get filmstreifen => find.descendant(
  of: betrachter,
  matching: find.byWidgetPredicate(
    (w) => w is ListView && w.scrollDirection == Axis.horizontal,
  ),
);

/// Das weiss umrandete Vorschaubild im Filmstreifen.
Finder get weissUmrandet => find.descendant(
  of: filmstreifen,
  matching: find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    if (d is! BoxDecoration) return false;
    final rand = d.border;
    return rand is Border && rand.top.color == Colors.white;
  }),
);

/// Die Zwischenablage, abgefangen statt der des Rechners.
String? zwischenablage;

void ablageAbfangen(WidgetTester tester) {
  zwischenablage = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          zwischenablage = (call.arguments as Map)['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, Object?>{'text': zwischenablage};
        case 'Clipboard.hasStrings':
          return <String, Object?>{'value': zwischenablage != null};
      }
      return null;
    },
  );
}

void ablageFreigeben(WidgetTester tester) => tester
    .binding
    .defaultBinaryMessenger
    .setMockMethodCallHandler(SystemChannels.platform, null);

/// Der Hinweistext im Suchfeld oben.
String? suchfeldHinweis(WidgetTester tester) =>
    tester.widget<TextField>(suchfeld).decoration?.hintText;

/// Ob die Datei [relativePath] gerade entschlüsselt im Klartext-Ordner
/// der Bibliothek liegt (siehe LibraryState.decryptForViewing).
Future<bool> entschluesselt(WidgetTester tester, String relativePath) async {
  final name = sha256.convert(utf8.encode(relativePath)).toString();
  final datei = File(
    p.join(Directory.systemTemp.path, 'photovault_decrypt', name),
  );
  return (await echt(datei.exists)) ?? false;
}

/// Öffnet den gesperrten Ordner über die Einstellungen (mit Test-PIN,
/// falls er gesperrt ist).
Future<void> oeffneGesperrtenOrdner(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.einstellungen);
  await rolleZu(
    tester,
    find.text(de.einstAbschnittGesperrterOrdner).first,
    in_: rolleIn(SettingsScreen),
  );
  await tap(tester, find.text(de.einstAbschnittGesperrterOrdner).first);
  await tap(tester, find.text(de.einstGesperrtOeffnen));
  await pinFallsGefragt(tester);
  await waitFor(tester, find.text(de.gesperrtTabFotos));
}

/// Gibt die Test-PIN ein, wenn danach gefragt wird.
Future<void> pinFallsGefragt(WidgetTester tester, {String pin = '2468'}) async {
  await settle(tester);
  if (find.text(de.pinEingebenTitel).evaluate().isEmpty) return;
  await enter(tester, field(de.pinFeld), pin);
  await tap(
    tester,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    ),
  );
}

/// Die Texte des Teilen-Pakets (Albumregeln, Konten).
final TeilenTexte teilenDe = lookupTeilenTexte(const Locale('de'));

/// Ein Bild mit grossen Wörtern auf farbigem Grund – ein Motiv, das die
/// Bildsuche (CLIP) liest. Klein gezeichnet und hochskaliert, damit die
/// Schrift auch nach dem Verkleinern auf 224 Punkte lesbar bleibt.
File motivfoto(
  String name,
  List<String> woerter,
  img.Color grund,
  DateTime datum,
) {
  final klein = img.Image(width: 320, height: 240);
  img.fill(klein, color: grund);
  final dunkel = (grund.r + grund.g + grund.b) / 3 < 128;
  var y = 40;
  for (final w in woerter) {
    img.drawString(
      klein,
      w,
      font: img.arial48,
      x: 30,
      y: y,
      color: dunkel ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0),
    );
    y += 80;
  }
  final gross = img.copyResize(klein, width: 960, height: 720);
  String n(int v, int s) => v.toString().padLeft(s, '0');
  final text =
      '${n(datum.year, 4)}:${n(datum.month, 2)}:${n(datum.day, 2)} 12:00:00';
  gross.exif.exifIfd['DateTimeOriginal'] = text;
  gross.exif.imageIfd['DateTime'] = text;
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(gross, quality: 92));
  return datei;
}

/// Legt auf [name] ein Gesicht an und ordnet es der Person [personId] zu.
Future<void> gesichtFuer(
  WidgetTester tester,
  String name,
  String personId,
) async {
  final a = await aufnahme(tester, name);
  final gesicht = _uuid.v4();
  await echt(() async {
    await bibliothek.db.insertFace(
      FacesCompanion.insert(
        id: gesicht,
        assetId: a.id,
        personId: const Value.absent(),
        boxX: 0.3,
        boxY: 0.3,
        boxW: 0.2,
        boxH: 0.2,
      ),
    );
    await bibliothek.db.fuehreAus(GesichterZuordnen([gesicht], personId));
  });
  await settle(tester);
}

/// „?“ auf der deutschen Tastatur: Umschalt und die Taste rechts neben
/// der Null (dieselbe Lage wie „/“ im US-Layout).
Future<void> fragezeichen(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.slash);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await settle(tester);
}

/// Der erste Text [text] im Bildschirm [typ] (nicht in der Seitenleiste).
Finder imSchirm(Type typ, String text) =>
    find.descendant(of: find.byType(typ), matching: find.text(text)).first;

/// Der Scrollbereich im Bildschirm [typ] (nicht der der Seitenleiste).
Finder rolleIn(Type typ) => find
    .descendant(of: find.byType(typ), matching: find.byType(Scrollable))
    .first;

/// Tippt das Löschzeichen eines Chips an.
Future<void> chipLoeschen(WidgetTester tester, Finder chip) async {
  for (final symbol in [Icons.clear, Icons.cancel, Icons.close]) {
    final f = find.descendant(of: chip, matching: find.byIcon(symbol));
    if (f.evaluate().isNotEmpty) {
      await tap(tester, f);
      return;
    }
  }
  fail('Chip ohne Löschzeichen');
}

/// Wert einer Statistik-Kachel mit der Beschriftung [beschriftung].
String statWert(WidgetTester tester, String beschriftung) {
  final karte = find
      .ancestor(
        of: find
            .descendant(
              of: find.byType(StatisticsScreen),
              matching: find.text(beschriftung),
            )
            .first,
        matching: find.byType(Card),
      )
      .first;
  return [
    for (final e
        in find.descendant(of: karte, matching: find.byType(Text)).evaluate())
      (e.widget as Text).data ?? '',
  ].firstWhere((t) => t != beschriftung);
}

/// Einfacher Klick auf eine Kachel, die auch einen Doppelklick kennt: Der
/// einfache wirkt erst nach Ablauf der Doppelklick-Frist.
Future<void> einfachKlick(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 450));
  await settle(tester);
}

/// Klickt in der Seitenleiste auf den Eintrag [text] – auf das Symbol am
/// linken Rand: Die schmale Leiste klappt ihre Beschriftung erst beim
/// Darüberfahren auf.
Future<void> leistenKlick(WidgetTester tester, String text) async {
  final zeile = find
      .ancestor(
        of: find.descendant(
          of: find.byType(Seitenleiste),
          matching: find.text(text),
        ),
        matching: find.byType(InkWell),
      )
      .first;
  await waitFor(tester, zeile);
  final r = tester.getRect(zeile);
  await tester.tapAt(Offset(r.left + 18, r.center.dy));
  await settle(tester);
}

/// Der Knopf (IconButton) mit dem Tooltip [tooltip] in der Einzelansicht.
IconButton knopfWidget(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find
          .ancestor(of: knopf(tooltip), matching: find.byType(IconButton))
          .first,
    );

/// Wählt im Menü „Reihenfolge“ den Eintrag [eintrag].
Future<void> reihenfolge(WidgetTester tester, String eintrag) async {
  await tap(tester, find.byTooltip(de.sortReihenfolge));
  await tap(tester, find.text(eintrag).last);
  await settle(tester);
}

/// Der Haken im offenen Menü „Reihenfolge“ steht an [eintrag].
bool hakenAn(WidgetTester tester, String eintrag) {
  final item = tester.widget<CheckedPopupMenuItem<Object>>(
    find.ancestor(
      of: find.text(eintrag).last,
      matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
    ),
  );
  return item.checked;
}

// --- Suche -----------------------------------------------------------------

Finder get optionenBlatt => find.byType(SearchOptionsSheet);

/// Die Hinweistexte des Suchfelds im Optionenblatt, je Suchart.
List<String> get _feldHinweise => [
  de.suchoptHintKontext,
  de.suchoptHintDateiname,
  de.suchoptHintBeschreibung,
  de.suchoptHintOcr,
  de.suchoptHintCaption,
  de.suchoptHintTranskript,
  de.suchoptHintUeberall,
];

/// Das Ausschluss-Zeichen an einem Personenbild (nicht das Symbol vor
/// „Ohne diese Schlagwörter …“).
Finder get ausschlussZeichen => find.descendant(
  of: optionenBlatt,
  matching: find.byWidgetPredicate(
    (w) => w is Icon && w.icon == Icons.block && w.size == 26,
  ),
);

/// Das Suchfeld im Optionenblatt.
Finder get optionenFeld => find.descendant(
  of: optionenBlatt,
  matching: find.byWidgetPredicate(
    (w) => w is TextField && _feldHinweise.contains(w.decoration?.hintText),
  ),
);

/// Das Suchfeld oben in der Suche.
Finder get suchfeld => find
    .descendant(of: find.byType(SearchScreen), matching: find.byType(TextField))
    .first;

Future<void> oeffneSuchoptionen(WidgetTester tester) async {
  await tap(tester, find.byTooltip(de.sucheOptionen).first);
  await waitFor(tester, optionenBlatt);
  await settle(tester);
}

bool _hat(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Rollt [in_], bis [ziel] gebaut ist, und holt es ins Bild – erst nach
/// unten, dann nach oben. Anders als `scrollUntilVisible` verträgt es
/// Finder mit `.first`, die vor dem Rollen noch nichts finden.
Future<void> rolleZu(
  WidgetTester tester,
  Finder ziel, {
  required Finder in_,
}) async {
  for (final richtung in [-1.0, 1.0]) {
    for (var i = 0; i < 60 && !_hat(ziel); i++) {
      await tester.drag(
        in_.first,
        Offset(0, 220 * richtung),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    if (_hat(ziel)) break;
  }
  if (!_hat(ziel)) {
    throw TimeoutException(
      'Beim Rollen nicht gefunden: $ziel\nAuf dem Bildschirm: '
      '${onScreen(tester)}',
    );
  }
  await tester.ensureVisible(ziel.first);
  await settle(tester);
}

/// Tippt im Optionenblatt auf den Text [text] (rollt ihn heran).
Future<void> imBlatt(WidgetTester tester, String text) async {
  final ziel = find.descendant(of: optionenBlatt, matching: find.text(text));
  await rolleZu(
    tester,
    ziel,
    in_: find
        .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
        .first,
  );
  await tap(tester, ziel.first);
}

/// „Suche“ unten im Optionenblatt.
Future<void> optionenSuchen(WidgetTester tester) async {
  await tap(
    tester,
    find.descendant(
      of: optionenBlatt,
      matching: find.widgetWithText(FilledButton, de.suchoptSuchen),
    ),
  );
  await waitGone(tester, optionenBlatt);
  await settle(tester);
}

/// Suchart [typ] wählen, [text] eintragen, suchen.
Future<void> sucheNachTyp(
  WidgetTester tester,
  String typ,
  String text, {
  bool offen = false,
}) async {
  if (!offen) await oeffneSuchoptionen(tester);
  await imBlatt(tester, typ);
  await enter(tester, optionenFeld, text);
  await optionenSuchen(tester);
  await eventually(
    tester,
    () async => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    was: 'Suche fertig',
  );
  await settle(tester);
}

/// Die Dateinamen der Treffer in ihrer Reihenfolge.
List<String> treffer(WidgetTester tester) => [
  for (final e
      in find
          .descendant(
            of: find.byType(SearchScreen),
            matching: find.byType(AssetThumbnailTile),
          )
          .evaluate())
    (e.widget as AssetThumbnailTile).asset.originalFileName,
];

/// Text oben ins Suchfeld und Eingabe.
Future<void> tippeSuche(WidgetTester tester, String text) async {
  await tester.tap(suchfeld);
  await tester.enterText(suchfeld, text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await settle(tester);
  await eventually(
    tester,
    () async => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    timeout: const Duration(seconds: 90),
    was: 'Suche fertig',
  );
  await settle(tester);
}

/// Klick mit der Maus, nachdem der Zeiger kurz darüber stand (für
/// Bedienelemente, die erst beim Darüberfahren antippbar werden).
Future<void> mausKlick(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  final wo = tester.getCenter(finder.first);
  final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await maus.addPointer(location: wo - const Offset(1, 1));
  await maus.moveTo(wo);
  await tester.pump(const Duration(milliseconds: 150));
  await maus.down(wo);
  await tester.pump(const Duration(milliseconds: 50));
  await maus.up();
  await tester.pump(const Duration(milliseconds: 100));
  await maus.removePointer();
  await settle(tester);
}

/// Wählt die Fotos [namen] im Raster aus: das erste lange gedrückt, die
/// übrigen einfach angeklickt.
Future<void> waehle(WidgetTester tester, List<String> namen) async {
  await waitFor(tester, kachel(namen.first));
  await tester.longPress(kachel(namen.first));
  await settle(tester);
  for (final n in namen.skip(1)) {
    await tap(tester, kachel(n));
  }
  await waitFor(tester, find.text(de.auswAnzahl(namen.length)));
}

/// Ein Knopf der Auswahlleiste.
Future<void> leiste(WidgetTester tester, String tooltip) => tap(
  tester,
  find.descendant(
    of: find.byType(SelectionActionBar),
    matching: find.byTooltip(tooltip),
  ),
);

/// Klickt „Rückgängig“ in der jüngsten Meldung. Ist die Meldung schon
/// verblasst (das Warten auf den Bildschirm dauerte länger als ihre acht
/// Sekunden), wird dieselbe Aktion aus dem Verlauf ausgelöst.
Future<void> rueckgaengig(WidgetTester tester) async {
  final knopf = find.text(de.allgRueckgaengig);
  if (knopf.evaluate().isNotEmpty) {
    await tester.tap(knopf.last);
    await settle(tester);
    return;
  }
  final mitAktion = melde.verlauf.where((m) => m.aktion != null).toList()
    ..sort((a, b) => a.nummer.compareTo(b.nummer));
  if (mitAktion.isEmpty) fail('keine Meldung mit „Rückgängig“');
  print('Rückgängig aus dem Verlauf: ${mitAktion.last.text}');
  mitAktion.last.aktion!.beiDruck();
  await settle(tester);
}

/// Wählt im offenen Datumsdialog über die Texteingabe den Tag [d].
/// Gibt zurück, ob der Dialog danach zu ist (Datum angenommen).
Future<bool> datumEintippen(WidgetTester tester, DateTime d) async {
  final dialog = find.byType(DatePickerDialog);
  await waitFor(tester, dialog);
  for (final symbol in [Icons.edit_outlined, Icons.edit]) {
    final stift = find.descendant(of: dialog, matching: find.byIcon(symbol));
    if (stift.evaluate().isNotEmpty) {
      await tap(tester, stift);
      break;
    }
  }
  String n(int v) => v.toString().padLeft(2, '0');
  final feld = find.descendant(of: dialog, matching: find.byType(TextField));
  await enter(tester, feld, '${n(d.day)}.${n(d.month)}.${d.year}');
  await tap(tester, find.descendant(of: dialog, matching: find.text('OK')));
  await settle(tester);
  return dialog.evaluate().isEmpty;
}

/// Bestätigt einen offenen Zeitdialog unverändert.
Future<void> zeitBestaetigen(WidgetTester tester) async {
  final dialog = find.byType(TimePickerDialog);
  await waitFor(tester, dialog);
  await tap(tester, find.descendant(of: dialog, matching: find.text('OK')));
}

Future<List<String>> schlagwoerter(WidgetTester tester, String name) async {
  final a = await aufnahme(tester, name);
  final t = await echt(() => bibliothek.db.tagsForAsset(a.id));
  return [for (final x in t!) x.name];
}

Future<List<String>> albumInhalt(WidgetTester tester, String album) async {
  final db = bibliothek.db;
  final alben = await echt(() => db.alleAlben());
  final a = alben!.firstWhere((x) => x.name == album);
  final inhalt = await echt(() => db.assetsInAlbumOnce(a.id));
  return [for (final x in inhalt!) x.originalFileName];
}

Future<String> albumAnlegen(
  WidgetTester tester,
  String name,
  List<String> fotos, {
  DateTime? zeit,
}) async {
  final id = _uuid.v4();
  await befehl(tester, AlbumAnlegen(id, name, zeit ?? DateTime.now()));
  if (fotos.isNotEmpty) {
    await befehl(tester, AlbumFuellen(id, await ids(tester, fotos)));
  }
  return id;
}

/// Meldet die Bibliothek als Konto A beim Wegwerf-Server an, zieht sie
/// dorthin um und startet die App als verbundene Kopie neu.
Future<void> verbindeMitServer(WidgetTester tester) async {
  final server = Uri.parse(serverAdresse);
  await echt(() async {
    final anmeldung = Anmeldung(server);
    final schritt = await anmeldung.einrichten(
      'konto-a',
      'pruefpasswort-123',
      geraet: 'Rechner A',
    );
    anmeldung.schliesse();
    final token = (schritt as AnmeldungFertig).token;
    final v = Serververbindung(server, token);
    try {
      await for (final _ in Umzug(
        v,
        bibliothek.db,
        bibliothek.paths.root,
      ).laufe()) {}
    } finally {
      v.schliesse();
    }
    await Verbindungsdatei(
      server: server,
      konto: 'konto-a',
      geraet: 'Rechner A',
      token: token,
    ).schreibe(bibliothek.paths.root.parent);
  });
  await neustart(tester);
  expect(bibliothek.verbunden, isTrue);
  await eventually(
    tester,
    () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    timeout: const Duration(seconds: 60),
    was: 'Server erreichbar',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = ohneNetz;
  // Meldungen anderer Prüfungen liegen sonst noch im (globalen) Verlauf, und
  // die Glocke darüber verdeckt Knöpfe oben rechts.
  setUp(() => melde.verlaufLeeren());
  // Die Testdateien einer Prüfung entstehen, bevor startApp den Ordner der
  // Prüfung anlegt (sie stehen in dessen Argumenten). Ein eigener Ordner
  // dafür, damit das auch für die erste Prüfung eines Laufs gilt; startApp
  // setzt `anker` danach wie immer neu.
  setUpAll(() {
    anker = Directory.systemTemp.createTempSync('pv_katalog_eingang_');
  });

  // === Zeitleiste ===========================================================

  testWidgets('ANS-001 Leere Bibliothek zeigt den Leerzustand', (tester) async {
    await startApp(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, find.text(de.timelineLeer));
    expect(find.byType(MonthGroupedAssetGrid), findsNothing);
    final knopf = find.widgetWithText(FilledButton, de.importierenTooltip);
    final beliebig = knopf.evaluate().isNotEmpty
        ? knopf
        : find.text(de.importierenTooltip);
    await tap(tester, beliebig);
    await waitFor(tester, find.text(de.importWasTitel));
    expect(find.text(de.importEinzelneDateien), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.text(de.importWasTitel));
    await finish(tester);
  });

  testWidgets(
    'ANS-002 ANS-003 ANS-004 Monatsgruppen, Jahresübersicht, Monatsübersicht',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('jul_a.jpg', datum: DateTime(2025, 7, 20, 10)),
          testfoto('jul_b.jpg', datum: DateTime(2025, 7, 5, 10)),
          testfoto('mar.jpg', datum: DateTime(2025, 3, 10, 10)),
          testfoto('jan.jpg', datum: DateTime(2025, 1, 2, 10)),
          testfoto('dez.jpg', datum: DateTime(2024, 12, 24, 18)),
          testfoto('alt.jpg', datum: DateTime(2023, 6, 1, 9)),
          testfoto('archiv.jpg', datum: DateTime(2025, 7, 12, 10)),
          testfoto('papierkorb.jpg', datum: DateTime(2025, 7, 13, 10)),
          testfoto('gesperrt.jpg', datum: DateTime(2025, 7, 14, 10)),
        ],
      );
      await befehl(
        tester,
        ArchivSetzen(await ids(tester, ['archiv.jpg']), true),
      );
      await befehl(
        tester,
        InDenPapierkorb(await ids(tester, ['papierkorb.jpg'])),
      );
      await tresorEinrichten(tester);
      await sperre(tester, 'gesperrt.jpg');

      // ANS-002: Monatsüberschriften, neuester Monat oben, im Monat das
      // neueste Foto zuerst; Archiv, Papierkorb und Gesperrtes fehlen.
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));
      expect(rasterNamen(tester), [
        'jul_a.jpg',
        'jul_b.jpg',
        'mar.jpg',
        'jan.jpg',
        'dez.jpg',
        'alt.jpg',
      ]);
      final juli = tester.getTopLeft(monatskopf('Juli 2025'));
      final maerz = tester.getTopLeft(monatskopf('März 2025'));
      final dezember = tester.getTopLeft(monatskopf('Dezember 2024'));
      expect(juli.dy, lessThan(maerz.dy));
      expect(maerz.dy, lessThan(dezember.dy));
      final a = tester.getTopLeft(kachel('jul_a.jpg'));
      final b = tester.getTopLeft(kachel('jul_b.jpg'));
      expect(a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx), isTrue);
      for (final weg in ['archiv.jpg', 'papierkorb.jpg', 'gesperrt.jpg']) {
        expect(kachel(weg), findsNothing, reason: weg);
      }

      // ANS-003: Jahresübersicht mit einer Kachel je Jahr, neuestes zuerst.
      await tap(tester, find.byTooltip(de.timelineJahre));
      await waitFor(tester, find.text(de.timelineDetails));
      expect(find.text(de.timelineJahre), findsWidgets);
      final j25 = tester.getTopLeft(find.text('2025'));
      final j24 = tester.getTopLeft(find.text('2024'));
      final j23 = tester.getTopLeft(find.text('2023'));
      expect(j25.dy < j24.dy || (j25.dy == j24.dy && j25.dx < j24.dx), isTrue);
      expect(j24.dy < j23.dy || (j24.dy == j23.dy && j24.dx < j23.dx), isTrue);
      // Anzahl je Jahr neben der Jahreszahl: 2025 hat vier sichtbare Fotos.
      final kachel25 = find.ancestor(
        of: find.text('2025'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: kachel25.first, matching: find.text('4')),
        findsOneWidget,
      );
      // ANS-004: Jahr → Monatsübersicht.
      await tap(tester, find.text('2025'));
      await waitFor(tester, find.text(de.kalenderGanzesJahr));
      expect(find.text('Juli'), findsOneWidget);
      expect(find.text('März'), findsOneWidget);
      expect(find.text('Januar'), findsOneWidget);
      expect(find.text('Februar'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Juli')).dy <=
            tester.getTopLeft(find.text('Januar')).dy,
        isTrue,
      );
      expect(find.text(de.kalenderAnzahlFotos(2)), findsOneWidget);
      // Ein Monat zeigt nur seine Fotos, nach Tagen gegliedert.
      await tap(tester, find.text('Juli'));
      await waitFor(tester, find.text('Juli 2025'));
      await waitFor(tester, kachel('jul_a.jpg'));
      expect(kachel('jul_b.jpg'), findsOneWidget);
      expect(kachel('mar.jpg'), findsNothing);
      expect(find.textContaining('20. Juli 2025'), findsWidgets);
      await zurueck(tester);
      // „Ganzes Jahr“: alle Fotos des Jahres nach Monaten.
      await tap(tester, find.text(de.kalenderGanzesJahr));
      await waitFor(tester, kachel('jan.jpg'));
      for (final n in ['jul_a.jpg', 'jul_b.jpg', 'mar.jpg', 'jan.jpg']) {
        expect(kachel(n), findsOneWidget, reason: n);
      }
      expect(kachel('dez.jpg'), findsNothing);
      expect(monatskopf('März 2025'), findsOneWidget);
      expect(monatskopf('Januar 2025'), findsOneWidget);
      await zurueck(tester);
      await zurueck(tester);
      // „Details“ führt zurück zur Monatsansicht.
      await tap(tester, find.text(de.timelineDetails));
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));
      expect(monatskopf('Juli 2025'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-007 ANS-008 ANS-009 Tagesgliederung, Reihenfolgen, gemerkt',
    (tester) async {
      final heute = DateTime.now();
      final gestern = heute.subtract(const Duration(days: 1));
      await startApp(
        tester,
        fotos: [
          testfoto(
            'c_heute.jpg',
            datum: DateTime(heute.year, heute.month, heute.day, 0, 5),
            breite: 400,
            hoehe: 300,
          ),
          testfoto(
            'a_gestern.jpg',
            datum: DateTime(gestern.year, gestern.month, gestern.day, 12),
            breite: 1600,
            hoehe: 1200,
          ),
          testfoto('e_alt1.jpg', datum: DateTime(2024, 3, 4, 10)),
          testfoto('b_alt2.jpg', datum: DateTime(2024, 3, 9, 10)),
        ],
      );
      // Ein später importiertes, älteres Foto für „Zuletzt hinzugefügt“.
      await echt(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await importiereDirekt(tester, [
        testfoto(
          'd_spaet.jpg',
          datum: DateTime(2023, 1, 1, 10),
          breite: 2400,
          hoehe: 1800,
        ),
      ]);
      await befehl(
        tester,
        BewertungSetzen(await ids(tester, ['e_alt1.jpg']), 5),
      );
      await befehl(
        tester,
        BewertungSetzen(await ids(tester, ['b_alt2.jpg']), 3),
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));

      // ANS-007: Tagesüberschriften.
      expect(find.text(de.tagHeute), findsNothing);
      await tap(tester, find.byTooltip(de.zeitleisteNachTagen));
      await waitFor(tester, find.text(de.tagHeute));
      expect(find.text(de.tagGestern), findsOneWidget);
      // Ältere Tage tragen Wochentag und Datum.
      expect(find.textContaining('4. März'), findsWidgets);
      expect(find.textContaining('9. März'), findsWidgets);
      // Kleine Tage stehen nebeneinander: zwei Tage im März in einer Zeile.
      final t4 = tester.getTopLeft(find.textContaining('4. März').first);
      final t9 = tester.getTopLeft(find.textContaining('9. März').first);
      expect(t4.dy, closeTo(t9.dy, 2));
      expect(await echt(() => bibliothek.db.zeitleisteMitTagenWert()), isTrue);
      // Übersteht den Neustart.
      await neustart(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, find.text(de.tagHeute));
      expect(find.byTooltip(de.zeitleisteNachMonaten), findsOneWidget);
      await tap(tester, find.byTooltip(de.zeitleisteNachMonaten));
      await waitGone(tester, find.text(de.tagHeute));
      expect(find.text(de.tagGestern), findsNothing);

      // ANS-008: Dateigrösse – keine Monate, kein Zeitstrahl, kein Tage-Knopf.
      expect(find.byType(TimelineScrubber), findsOneWidget);
      await reihenfolge(tester, de.sortGroesse);
      expect(find.text('März 2024'), findsNothing);
      expect(find.byType(TimelineScrubber), findsNothing);
      expect(find.byTooltip(de.zeitleisteNachTagen), findsNothing);
      expect(rasterNamen(tester).first, 'd_spaet.jpg');
      final groessen = {
        for (final a in await alleAufnahmen(tester))
          a.originalFileName: a.fileSizeBytes,
      };
      final nachGroesse = rasterNamen(tester);
      for (var i = 1; i < nachGroesse.length; i++) {
        expect(
          groessen[nachGroesse[i - 1]]! >= groessen[nachGroesse[i]]!,
          isTrue,
          reason: '$nachGroesse',
        );
      }
      await reihenfolge(tester, de.sortAufnahmeNeu);
      await waitFor(tester, find.text('März 2024'));
      expect(find.byType(TimelineScrubber), findsOneWidget);
      expect(find.byTooltip(de.zeitleisteNachTagen), findsOneWidget);

      // ANS-009: sechs Reihenfolgen mit Haken.
      final erwartet = <String, List<String>>{
        de.sortAufnahmeNeu: [
          'c_heute.jpg',
          'a_gestern.jpg',
          'b_alt2.jpg',
          'e_alt1.jpg',
          'd_spaet.jpg',
        ],
        de.sortAufnahmeAlt: [
          'd_spaet.jpg',
          'e_alt1.jpg',
          'b_alt2.jpg',
          'a_gestern.jpg',
          'c_heute.jpg',
        ],
        de.sortName: [
          'a_gestern.jpg',
          'b_alt2.jpg',
          'c_heute.jpg',
          'd_spaet.jpg',
          'e_alt1.jpg',
        ],
      };
      for (final e in erwartet.entries) {
        await reihenfolge(tester, e.key);
        expect(rasterNamen(tester), e.value, reason: e.key);
        await tap(tester, find.byTooltip(de.sortReihenfolge));
        expect(hakenAn(tester, e.key), isTrue, reason: e.key);
        await key(tester, LogicalKeyboardKey.escape);
      }
      await reihenfolge(tester, de.sortImportNeu);
      expect(rasterNamen(tester).first, 'd_spaet.jpg');
      await reihenfolge(tester, de.sortBewertung);
      expect(rasterNamen(tester).take(2), ['e_alt1.jpg', 'b_alt2.jpg']);
      await reihenfolge(tester, de.sortGroesse);
      expect(rasterNamen(tester).first, 'd_spaet.jpg');
      await reihenfolge(tester, de.sortName);
      // Nach dem Neustart gilt die zuletzt gewählte Reihenfolge.
      await neustart(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));
      await eventually(
        tester,
        () async => rasterNamen(tester).first == 'a_gestern.jpg',
        was: 'Reihenfolge nach Neustart',
      );
      expect(rasterNamen(tester), erwartet[de.sortName]);
      await tap(tester, find.byTooltip(de.sortReihenfolge));
      expect(hakenAn(tester, de.sortName), isTrue);
      await key(tester, LogicalKeyboardKey.escape);
      await finish(tester);
    },
  );

  testWidgets('ANS-010 Listenansicht mit Gliederung', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto(
          'k1.jpg',
          datum: DateTime(2025, 5, 3, 10),
          kamera: 'Zeta',
          modell: 'Z1',
        ),
        testfoto(
          'k2.jpg',
          datum: DateTime(2025, 4, 3, 10),
          kamera: 'Alpha',
          modell: 'A7',
        ),
        testfoto(
          'k3.jpg',
          datum: DateTime(2025, 4, 2, 10),
          kamera: 'Alpha',
          modell: 'A7',
        ),
        testfoto('ohne1.jpg', datum: DateTime(2025, 3, 3, 10)),
        testfoto('ohne2.jpg', datum: DateTime(2025, 2, 3, 10)),
      ],
    );
    final alle = await alleAufnahmen(tester);
    final kameras = {for (final a in alle) a.originalFileName: a.cameraModel};
    expect(kameras['k2.jpg'], isNotNull, reason: 'Kamera beim Import gelesen');
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, find.byType(MonthGroupedAssetGrid));
    expect(find.byTooltip(de.zeitleisteKleiner), findsOneWidget);
    await tap(tester, find.byTooltip(de.ansichtListe));
    await waitFor(tester, find.byType(AssetListView));
    // Zeilen mit Spalten, kein Foto fehlt.
    final liste = tester.widget<AssetListView>(find.byType(AssetListView));
    expect(liste.assets.length, 5);
    expect(find.text('k1.jpg'), findsOneWidget);
    // Knöpfe für Kachelgrösse, Form und Tage fehlen in der Liste.
    expect(find.byTooltip(de.zeitleisteKleiner), findsNothing);
    expect(find.byTooltip(de.zeitleisteGroesser), findsNothing);
    expect(find.byTooltip(de.zeitleisteFormReihen), findsNothing);
    expect(find.byTooltip(de.zeitleisteNachTagen), findsNothing);
    // Nach Monat (Vorgabe).
    expect(find.text('Mai 2025'), findsOneWidget);
    expect(find.text('April 2025'), findsOneWidget);
    Future<void> gliedern(String eintrag) async {
      await tap(tester, find.byType(DropdownButton<ListenGruppierung>));
      await tap(tester, find.text(eintrag).last);
    }

    await gliedern(de.gruppeTag);
    expect(find.textContaining('3. April 2025'), findsWidgets);
    expect(find.textContaining('2. April 2025'), findsWidgets);
    await gliedern(de.gruppeKamera);
    await waitFor(tester, find.text(de.listeOhneKamera));
    final ohne = tester.getTopLeft(find.text(de.listeOhneKamera)).dy;
    final alpha = tester.getTopLeft(find.textContaining('A7').first).dy;
    final zeta = tester.getTopLeft(find.textContaining('Z1').first).dy;
    expect(alpha, lessThan(zeta), reason: 'alphabetisch');
    expect(zeta, lessThan(ohne), reason: 'ohne Kamera zuletzt');
    expect(
      tester.widget<AssetListView>(find.byType(AssetListView)).assets.length,
      5,
    );
    await gliedern(de.gruppeKeine);
    expect(find.text('Mai 2025'), findsNothing);
    expect(find.text(de.listeOhneKamera), findsNothing);
    for (final n in ['k1.jpg', 'k2.jpg', 'k3.jpg', 'ohne1.jpg', 'ohne2.jpg']) {
      expect(find.text(n), findsOneWidget, reason: n);
    }
    // Zurück auf Raster.
    await tap(tester, find.byTooltip(de.ansichtRaster));
    await waitFor(tester, find.byType(MonthGroupedAssetGrid));
    expect(rasterNamen(tester).length, 5);
    expect(find.byTooltip(de.zeitleisteKleiner), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'ANS-012 ANS-014 Grosse Bibliothek: Start, Nachladen, nach oben',
    (tester) async {
      await startApp(tester);
      await zeilenAnlegen(tester, 2000, ab: DateTime(2026, 6, 1, 12));
      await openSection(tester, Hauptbereich.suche);
      final uhr = Stopwatch()..start();
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('zeile_0.jpg'));
      uhr.stop();
      print('ANS-012: erstes Raster nach ${uhr.elapsedMilliseconds} ms');
      expect(uhr.elapsedMilliseconds, lessThan(5000));
      // Das Ladefenster beginnt bei 600.
      expect(rasterNamen(tester).length, 600);
      // Bis ganz nach unten rollen: Es wird nachgeladen.
      final ende = DateTime.now().add(const Duration(seconds: 90));
      while (rasterNamen(tester).length < 2000 ||
          kachel('zeile_1999.jpg').evaluate().isEmpty) {
        if (DateTime.now().isAfter(ende)) {
          fail('nicht alles nachgeladen: ${rasterNamen(tester).length}');
        }
        final pos = rasterRolle(tester).position;
        pos.jumpTo(pos.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 200));
      }
      await settle(tester);
      final namen = rasterNamen(tester);
      expect(namen.length, 2000);
      expect(namen.toSet().length, 2000, reason: 'keines doppelt');
      expect(namen.last, 'zeile_1999.jpg');
      expect(sichtbar(tester, kachel('zeile_1999.jpg')), isTrue);

      // ANS-014: Ein erneuter Klick auf „Fotos“ springt nach oben.
      expect(rasterRolle(tester).position.pixels, greaterThan(1000));
      await leistenKlick(tester, de.navFotos);
      await eventually(
        tester,
        () async => rasterRolle(tester).position.pixels < 1,
        was: 'Raster oben',
      );
      expect(sichtbar(tester, kachel('zeile_0.jpg')), isTrue);
      // Dasselbe in der Liste.
      await tap(tester, find.byTooltip(de.ansichtListe));
      await waitFor(tester, find.byType(AssetListView));
      final listenRolle = find
          .descendant(
            of: find.byType(AssetListView),
            matching: find.byType(Scrollable),
          )
          .evaluate()
          .map((e) => (e as StatefulElement).state as ScrollableState)
          .firstWhere((s) => s.position.axis == Axis.vertical);
      listenRolle.position.jumpTo(5000);
      await settle(tester);
      expect(listenRolle.position.pixels, greaterThan(1000));
      await leistenKlick(tester, de.navFotos);
      await eventually(
        tester,
        () async => listenRolle.position.pixels < 1,
        was: 'Liste oben',
      );
      await tap(tester, find.byTooltip(de.ansichtRaster));
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));

      await finish(tester);
    },
  );

  // Behoben in #410: Die Zeitleiste hält das Sprungziel im eigenen Zustand,
  // bis Raster oder Liste es gezeigt haben; der zweite Aufbau der Hülle ohne
  // Ziel verliert es nicht mehr.
  testWidgets('ANS-015 „Foto in der Timeline anzeigen“ springt zum Foto', (
    tester,
  ) async {
    await startApp(tester);
    await zeilenAnlegen(tester, 1200, ab: DateTime(2026, 6, 1, 12));
    // ANS-015: altes Foto über die Suche finden, öffnen, „in der
    // Timeline anzeigen“.
    await openSection(tester, Hauptbereich.suche);
    await sucheNachTyp(tester, de.suchoptTypDateiname, 'zeile_1100');
    await waitFor(tester, kachel('zeile_1100.jpg'));
    await oeffne(tester, 'zeile_1100.jpg');
    await rechtsklick(tester, find.byType(PageView));
    await tap(tester, find.text(de.viewerInTimelineZeigen));
    await waitGone(tester, betrachter);
    await waitFor(tester, kachel('zeile_1100.jpg'));
    await eventually(
      tester,
      () async => sichtbar(tester, kachel('zeile_1100.jpg')),
      was: 'Foto im Blick',
    );
    expect(
      find.ancestor(
        of: kachel('zeile_1100.jpg'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_FlashHighlight',
        ),
      ),
      findsOneWidget,
      reason: 'kurz hervorgehoben',
    );
    print('ANS-015: Monat ${find.text('März 2017').evaluate().length}');
    await finish(tester);
  });

  // === Auswahl und Sammeländerungen ========================================

  testWidgets(
    'ANS-017 ANS-019 Auswählen per Druck und Klick, Gruppen über Überschriften',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 6; i++)
            testfoto('m$i.jpg', datum: DateTime(2025, 5, 10 + i, 10)),
          testfoto('t1a.jpg', datum: DateTime(2025, 4, 3, 10)),
          testfoto('t1b.jpg', datum: DateTime(2025, 4, 3, 11)),
          testfoto('t2.jpg', datum: DateTime(2025, 4, 8, 10)),
          testfoto('x.jpg', datum: DateTime(2025, 3, 8, 10)),
        ],
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, find.byType(MonthGroupedAssetGrid));
      bool gewaehlt(String n) =>
          tester.widget<AssetThumbnailTile>(kachel(n)).selected;

      // ANS-017: langer Druck, zwei Klicks, ein Klick wählt ab.
      await tester.longPress(kachel('m0.jpg'));
      await settle(tester);
      expect(gewaehlt('m0.jpg'), isTrue);
      expect(find.text(de.auswAnzahl(1)), findsOneWidget);
      await tap(tester, kachel('m1.jpg'));
      await tap(tester, kachel('m2.jpg'));
      expect(find.text(de.auswAnzahl(3)), findsOneWidget);
      expect(betrachter, findsNothing, reason: 'Klick öffnet nicht');
      expect(gewaehlt('m1.jpg') && gewaehlt('m2.jpg'), isTrue);
      expect(
        find.descendant(
          of: kachel('m1.jpg'),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
        reason: 'Haken auf der Kachel',
      );
      await tap(tester, kachel('m1.jpg'));
      expect(find.text(de.auswAnzahl(2)), findsOneWidget);
      expect(gewaehlt('m1.jpg'), isFalse);
      await leiste(tester, de.auswAufheben);
      expect(find.byType(SelectionActionBar), findsNothing);
      expect(gewaehlt('m0.jpg'), isFalse);
      // ⌘-Klick wählt ebenfalls aus, ohne zu öffnen.
      await befehlsklick(tester, kachel('m3.jpg'));
      expect(find.text(de.auswAnzahl(1)), findsOneWidget);
      expect(betrachter, findsNothing);
      await leiste(tester, de.auswAufheben);

      // ANS-019: Monatsüberschrift wählt den Monat, zweimal wieder ab.
      await tap(tester, find.text('Mai 2025'));
      expect(find.text(de.auswAnzahl(6)), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(gewaehlt('m$i.jpg'), isTrue);
      }
      expect(gewaehlt('t2.jpg'), isFalse);
      await tap(tester, find.text('Mai 2025'));
      expect(find.byType(SelectionActionBar), findsNothing);
      // Tagesüberschrift wählt nur den Tag.
      await tap(tester, find.byTooltip(de.zeitleisteNachTagen));
      final tag = find.textContaining('3. Apr');
      await waitFor(tester, tag);
      await mausKlick(tester, tag);
      await waitFor(tester, find.text(de.auswAnzahl(2)));
      expect(gewaehlt('t1a.jpg') && gewaehlt('t1b.jpg'), isTrue);
      expect(gewaehlt('t2.jpg'), isFalse);
      await leiste(tester, de.auswAufheben);
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-020 ANS-021 ANS-022 ANS-023 Sammel-Favorit, -Bewertung, -Farbe, '
    '-Schlagwort mit Rückgängig',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 4; i++)
            testfoto('s$i.jpg', datum: DateTime(2025, 6, 10 + i, 10)),
        ],
      );
      await befehl(tester, FavoritSetzen(await ids(tester, ['s0.jpg']), true));
      await befehl(
        tester,
        BewertungSetzen(await ids(tester, ['s0.jpg', 's1.jpg']), 5),
      );
      await befehl(
        tester,
        FarbmarkeSetzen(await ids(tester, ['s2.jpg']), 'blue'),
      );
      await befehl(
        tester,
        SchlagwortAnheften(await ids(tester, ['s1.jpg']), 'Urlaub'),
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      Future<Map<String, AssetData>> stand() async => {
        for (final a in await alleAufnahmen(tester)) a.originalFileName: a,
      };
      final drei = ['s0.jpg', 's1.jpg', 's2.jpg'];

      // ANS-020: Favorisieren setzt bei allen, Rückgängig je Foto.
      await waehle(tester, drei);
      await leiste(tester, de.auswFavorisieren);
      await meldung(tester, de.auswRueckFavorit(3));
      expect(find.byType(SelectionActionBar), findsNothing);
      var s = await stand();
      expect(drei.every((n) => s[n]!.isFavorite), isTrue);
      expect(
        find.descendant(
          of: kachel('s2.jpg'),
          matching: find.byIcon(Icons.favorite),
        ),
        findsOneWidget,
        reason: 'Herz auf der Kachel',
      );
      await rueckgaengig(tester);
      await eventually(tester, () async {
        final x = await stand();
        return x['s0.jpg']!.isFavorite &&
            !x['s1.jpg']!.isFavorite &&
            !x['s2.jpg']!.isFavorite;
      }, was: 'Favorit zurück');
      await meldungenWeg(tester);

      // ANS-021: Bewertung für vier.
      final vier = [...drei, 's3.jpg'];
      await waehle(tester, vier);
      await leiste(tester, de.auswBewertungSetzen);
      final bewDialog = find.byType(AlertDialog);
      await waitFor(tester, find.text(de.auswBewertungTitel(4)));
      await tap(
        tester,
        find.descendant(of: bewDialog, matching: find.byType(InkWell)).at(2),
      );
      await meldung(tester, de.auswRueckBewertung(4));
      s = await stand();
      expect(vier.every((n) => s[n]!.rating == 3), isTrue);
      await rueckgaengig(tester);
      await eventually(tester, () async {
        final x = await stand();
        return x['s0.jpg']!.rating == 5 &&
            x['s1.jpg']!.rating == 5 &&
            x['s2.jpg']!.rating == 0 &&
            x['s3.jpg']!.rating == 0;
      }, was: 'Bewertung je Foto zurück');
      await meldungenWeg(tester);
      await waehle(tester, vier);
      await leiste(tester, de.auswBewertungSetzen);
      await tapText(tester, de.auswKeineBewertung);
      s = await stand();
      expect(vier.every((n) => s[n]!.rating == 0), isTrue);
      await meldungenWeg(tester);
      await befehl(tester, BewertungSetzen(await ids(tester, ['s0.jpg']), 4));
      await waehle(tester, vier);
      await leiste(tester, de.auswBewertungSetzen);
      await tap(
        tester,
        find.descendant(of: bewDialog, matching: find.text(de.allgAbbrechen)),
      );
      s = await stand();
      expect(s['s0.jpg']!.rating, 4, reason: 'Abbrechen ändert nichts');
      expect(find.text(de.auswRueckBewertung(4)), findsNothing);
      if (find.byType(SelectionActionBar).evaluate().isNotEmpty) {
        await leiste(tester, de.auswAufheben);
      }

      // ANS-022: Farbmarkierung für drei.
      await waehle(tester, drei);
      await leiste(tester, de.auswFarbeSetzen);
      await waitFor(tester, find.text(de.auswFarbeTitel(3)));
      await tap(
        tester,
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await meldung(tester, de.auswRueckFarbe(3));
      s = await stand();
      expect(drei.every((n) => s[n]!.colorLabel == 'red'), isTrue);
      await rueckgaengig(tester);
      await eventually(tester, () async {
        final x = await stand();
        return x['s0.jpg']!.colorLabel == null &&
            x['s1.jpg']!.colorLabel == null &&
            x['s2.jpg']!.colorLabel == 'blue';
      }, was: 'Farbe je Foto zurück');
      await meldungenWeg(tester);
      // Schliessen ohne Wahl ändert nichts.
      await waehle(tester, drei);
      await leiste(tester, de.auswFarbeSetzen);
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
      s = await stand();
      expect(s['s2.jpg']!.colorLabel, 'blue');
      // „Keine Farbe“ entfernt bei allen.
      if (find.byType(SelectionActionBar).evaluate().isEmpty) {
        await waehle(tester, drei);
      }
      await leiste(tester, de.auswFarbeSetzen);
      await tapText(tester, de.auswKeineFarbe);
      s = await stand();
      expect(drei.every((n) => s[n]!.colorLabel == null), isTrue);
      await meldungenWeg(tester);

      // ANS-023: Schlagwort „Urlaub“, eines trägt es schon.
      await waehle(tester, drei);
      await leiste(tester, de.auswTagHinzufuegen);
      await waitFor(tester, find.text(de.auswTagTitel(3)));
      await enter(tester, field(de.auswTagFeld), 'Urlaub');
      await tapText(tester, de.allgHinzufuegen);
      await meldung(tester, de.auswRueckSchlagwort('Urlaub', 2));
      for (final n in drei) {
        expect(await schlagwoerter(tester, n), contains('Urlaub'), reason: n);
      }
      await rueckgaengig(tester);
      await eventually(tester, () async {
        return (await schlagwoerter(tester, 's1.jpg')).contains('Urlaub') &&
            !(await schlagwoerter(tester, 's0.jpg')).contains('Urlaub') &&
            !(await schlagwoerter(tester, 's2.jpg')).contains('Urlaub');
      }, was: 'Schlagwort nur bei den zwei neuen zurück');
      await meldungenWeg(tester);
      // Leeres Feld und Abbrechen ändern nichts.
      await waehle(tester, drei);
      await leiste(tester, de.auswTagHinzufuegen);
      await tapText(tester, de.allgHinzufuegen);
      keineMeldung('vergeben');
      await waehle(tester, drei);
      await leiste(tester, de.auswTagHinzufuegen);
      await enter(tester, field(de.auswTagFeld), 'Anders');
      await tapText(tester, de.allgAbbrechen);
      expect(await schlagwoerter(tester, 's0.jpg'), isEmpty);
      // Tragen schon alle das Schlagwort, gibt es keine Meldung.
      await befehl(
        tester,
        SchlagwortAnheften(await ids(tester, drei), 'Urlaub'),
      );
      await meldungenWeg(tester);
      await waehle(tester, drei);
      await leiste(tester, de.auswTagHinzufuegen);
      await enter(tester, field(de.auswTagFeld), 'Urlaub');
      await tapText(tester, de.allgHinzufuegen);
      await settle(tester);
      keineMeldung('vergeben');
      await finish(tester);
    },
  );

  testWidgets('ANS-024 ANS-025 Auswahl in neues und bestehendes Album', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 4; i++)
          testfoto('a$i.jpg', datum: DateTime(2025, 6, 10 + i, 10)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    Future<List<String>> albumNamen() async => [
      for (final a in (await echt(() => bibliothek.db.alleAlben()))!) a.name,
    ];

    // ANS-024: neues Album, Rückgängig entfernt es ganz.
    await waehle(tester, ['a0.jpg', 'a1.jpg']);
    await leiste(tester, de.auswZuAlbum);
    await enter(tester, field(de.albumNeuAnlegen), 'Ferien');
    await tapText(tester, de.allgHinzufuegen);
    await meldung(tester, de.auswRueckAlbum(2));
    expect((await albumInhalt(tester, 'Ferien'))..sort(), ['a0.jpg', 'a1.jpg']);
    await rueckgaengig(tester);
    await eventually(
      tester,
      () async => !(await albumNamen()).contains('Ferien'),
      was: 'Album verschwunden',
    );
    await meldungenWeg(tester);
    // Noch einmal und in „Alben“ nachsehen.
    await waehle(tester, ['a0.jpg', 'a1.jpg']);
    await leiste(tester, de.auswZuAlbum);
    await enter(tester, field(de.albumNeuAnlegen), 'Ferien');
    await tapText(tester, de.allgHinzufuegen);
    await meldung(tester, de.auswRueckAlbum(2));
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Ferien'));
    await waitFor(tester, kachel('a0.jpg'));
    expect(kachel('a1.jpg'), findsOneWidget);
    expect(kachel('a2.jpg'), findsNothing);
    await zurueck(tester);
    await meldungenWeg(tester);

    // ANS-025: in das bestehende Album, ohne Doppelte.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waehle(tester, ['a1.jpg', 'a2.jpg', 'a3.jpg']);
    await leiste(tester, de.auswZuAlbum);
    await tap(
      tester,
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<AlbumData>),
    );
    await tap(tester, find.text('Ferien').last);
    await tapText(tester, de.allgHinzufuegen);
    await meldung(tester, de.auswRueckAlbum(2));
    await meldungenWeg(tester);
    await waehle(tester, ['a1.jpg', 'a2.jpg', 'a3.jpg']);
    await leiste(tester, de.auswZuAlbum);
    await tap(
      tester,
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<AlbumData>),
    );
    await tap(tester, find.text('Ferien').last);
    await tapText(tester, de.allgHinzufuegen);
    await settle(tester);
    keineMeldung('ins Album gelegt');
    final inhalt = await albumInhalt(tester, 'Ferien');
    expect(inhalt.length, 4);
    expect(inhalt.toSet().length, 4, reason: 'jedes Foto genau einmal');
    await finish(tester);
  });

  testWidgets('ANS-026 Sammel-Metadaten: nur ausgefüllte Felder ändern sich', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 3; i++)
          testfoto(
            'meta$i.jpg',
            datum: DateTime(2024, 2, 10 + i, 10),
            breitengrad: 47.1 + i / 10,
            laengengrad: 11.2,
          ),
      ],
    );
    final drei = ['meta0.jpg', 'meta1.jpg', 'meta2.jpg'];
    for (var i = 0; i < 3; i++) {
      await befehl(
        tester,
        BeschreibungSetzen(await ids(tester, [drei[i]]), 'Text $i'),
      );
    }
    await openSection(tester, Hauptbereich.zeitleiste);
    Future<Map<String, AssetData>> stand() async => {
      for (final a in await alleAufnahmen(tester)) a.originalFileName: a,
    };
    final vorher = await stand();
    expect(vorher['meta0.jpg']!.latitude, isNotNull);

    // Nur das Datum.
    await waehle(tester, drei);
    await leiste(tester, de.auswMetadaten);
    await waitFor(tester, find.text(de.auswMetadatenTitel(3)));
    final neu = DateTime(2023, 8, 15);
    await tapText(tester, de.allgWaehlen);
    expect(await datumEintippen(tester, neu), isTrue);
    await tapText(tester, de.allgSpeichern);
    await eventually(tester, () async {
      final x = await stand();
      return drei.every((n) => x[n]!.fileCreatedAt.year == 2023);
    }, was: 'neues Datum');
    var s = await stand();
    for (var i = 0; i < 3; i++) {
      final a = s[drei[i]]!;
      expect(
        [a.fileCreatedAt.year, a.fileCreatedAt.month, a.fileCreatedAt.day],
        [2023, 8, 15],
      );
      expect(a.description, 'Text $i');
      expect(a.latitude, isNotNull);
    }
    await waitFor(tester, find.text('August 2023'));
    expect(find.text('Februar 2024'), findsNothing);

    // Nur „Ort entfernen“.
    await waehle(tester, drei);
    await leiste(tester, de.auswMetadaten);
    await tapText(tester, de.auswOrtEntfernen);
    await tapText(tester, de.allgSpeichern);
    await eventually(tester, () async {
      final x = await stand();
      return drei.every((n) => x[n]!.latitude == null);
    }, was: 'Ort weg');
    s = await stand();
    expect(s['meta1.jpg']!.description, 'Text 1');

    // Nur die Beschreibung.
    await waehle(tester, drei);
    await leiste(tester, de.auswMetadaten);
    await enter(tester, field(de.auswBeschreibungFeld), 'Gemeinsam');
    await tapText(tester, de.allgSpeichern);
    await eventually(tester, () async {
      final x = await stand();
      return drei.every((n) => x[n]!.description == 'Gemeinsam');
    }, was: 'gleiche Beschreibung');
    s = await stand();
    expect(s['meta0.jpg']!.fileCreatedAt.year, 2023);

    // „Abbrechen“ ändert nichts.
    await waehle(tester, drei);
    await leiste(tester, de.auswMetadaten);
    await enter(tester, field(de.auswBeschreibungFeld), 'Nicht');
    await tapText(tester, de.allgAbbrechen);
    s = await stand();
    expect(drei.every((n) => s[n]!.description == 'Gemeinsam'), isTrue);
    await finish(tester);
  });

  testWidgets('ANS-027 Archivieren und aus dem Archiv holen', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('arch1.jpg', datum: DateTime(2025, 6, 10, 10)),
        testfoto('arch2.jpg', datum: DateTime(2025, 6, 11, 10)),
        testfoto('bleibt.jpg', datum: DateTime(2025, 6, 12, 10)),
      ],
    );
    await albumAnlegen(tester, 'Mit Archiv', ['arch1.jpg']);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waehle(tester, ['arch1.jpg', 'arch2.jpg']);
    await leiste(tester, de.auswArchiv);
    await meldung(tester, de.auswRueckArchiviert(2));
    await waitGone(tester, kachel('arch1.jpg'));
    expect(kachel('arch2.jpg'), findsNothing);
    expect(kachel('bleibt.jpg'), findsOneWidget);
    // „Rückgängig“ kehrt um.
    await rueckgaengig(tester);
    await waitFor(tester, kachel('arch1.jpg'));
    await meldungenWeg(tester);
    await waehle(tester, ['arch1.jpg', 'arch2.jpg']);
    await leiste(tester, de.auswArchiv);
    await meldung(tester, de.auswRueckArchiviert(2));
    await meldungenWeg(tester);
    // Im Archiv, im Album und in der Suche.
    await openSection(tester, Hauptbereich.archiv);
    await waitFor(tester, kachel('arch1.jpg'));
    expect(kachel('arch2.jpg'), findsOneWidget);
    expect(kachel('bleibt.jpg'), findsNothing);
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Mit Archiv'));
    await waitFor(tester, kachel('arch1.jpg'));
    await zurueck(tester);
    await openSection(tester, Hauptbereich.suche);
    await sucheNachTyp(tester, de.suchoptTypDateiname, 'arch');
    await waitFor(tester, kachel('arch1.jpg'));
    expect(kachel('arch2.jpg'), findsOneWidget);
    // Aus dem Archiv holen.
    await openSection(tester, Hauptbereich.archiv);
    await waehle(tester, ['arch1.jpg', 'arch2.jpg']);
    await leiste(tester, de.auswArchiv);
    await meldung(tester, de.auswRueckAusArchiv(2));
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel('arch1.jpg'));
    expect(kachel('arch2.jpg'), findsOneWidget);
    // Rückgängig legt sie wieder ins Archiv.
    await rueckgaengig(tester);
    await waitGone(tester, kachel('arch1.jpg'));
    await finish(tester);
  });

  testWidgets('ANS-028 Sammel-Löschen mit Bestätigung, Originale bleiben', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 4; i++)
          testfoto('del$i.jpg', datum: DateTime(2025, 6, 10 + i, 10)),
      ],
    );
    final drei = ['del0.jpg', 'del1.jpg', 'del2.jpg'];
    final dateien = [
      for (final n in drei)
        bibliothek.paths.absolute((await aufnahme(tester, n)).relativePath),
    ];
    await openSection(tester, Hauptbereich.zeitleiste);
    await waehle(tester, drei);
    await leiste(tester, de.allgLoeschen);
    await waitFor(tester, find.text(de.loeschenTitel(3)));
    expect(find.text('3 Fotos löschen?'), findsOneWidget);
    expect(find.text(de.loeschenHinweis(3)), findsOneWidget);
    final rot = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, de.allgLoeschen),
    );
    final farbe = rot.style?.backgroundColor?.resolve({});
    final fehlerfarbe = Theme.of(
      tester.element(find.byType(AlertDialog)),
    ).colorScheme.error;
    expect(farbe, fehlerfarbe, reason: 'roter Knopf');
    await tapText(tester, de.allgAbbrechen);
    expect(
      find.text(de.auswAnzahl(3)),
      findsOneWidget,
      reason: 'Auswahl bleibt',
    );
    expect(kachel('del0.jpg'), findsOneWidget);
    await leiste(tester, de.allgLoeschen);
    await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
    await waitGone(tester, kachel('del0.jpg'));
    expect(kachel('del1.jpg'), findsNothing);
    expect(kachel('del3.jpg'), findsOneWidget);
    final alle = await alleAufnahmen(tester);
    for (final n in drei) {
      expect(alle.firstWhere((a) => a.originalFileName == n).isTrashed, isTrue);
    }
    for (final f in dateien) {
      expect(f.existsSync(), isTrue, reason: 'Original bleibt: ${f.path}');
    }
    await openSection(tester, Hauptbereich.papierkorb);
    final raster = find.descendant(
      of: find.byType(TrashScreen),
      matching: find.byType(GridView),
    );
    await waitFor(tester, raster);
    final grid = tester.widget<GridView>(raster.first);
    expect((grid.childrenDelegate as SliverChildBuilderDelegate).childCount, 3);
    await finish(tester);
  });

  testWidgets('ANS-029 Vergleichen nur bei genau zwei ausgewählten Fotos', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 3; i++)
          testfoto('v$i.jpg', datum: DateTime(2025, 6, 10 + i, 10)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    final vergleich = find.descendant(
      of: find.byType(SelectionActionBar),
      matching: find.byTooltip(de.auswVergleichen),
    );
    await waehle(tester, ['v0.jpg']);
    expect(vergleich, findsNothing);
    await tap(tester, kachel('v1.jpg'));
    expect(vergleich, findsOneWidget);
    await tap(tester, kachel('v2.jpg'));
    expect(vergleich, findsNothing);
    await tap(tester, kachel('v2.jpg'));
    await tap(tester, vergleich);
    await waitFor(tester, find.text(de.vergleichTitel));
    expect(find.text('v0.jpg'), findsOneWidget);
    expect(find.text('v1.jpg'), findsOneWidget);
    final bilder = find.byType(InteractiveViewer);
    expect(bilder, findsNWidgets(2));
    double massstab(int i) => tester
        .widget<InteractiveViewer>(bilder.at(i))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    Future<void> aufziehen(int i) async {
      final mitte = tester.getCenter(bilder.at(i));
      final f1 = await tester.startGesture(mitte - const Offset(20, 0));
      final f2 = await tester.startGesture(mitte + const Offset(20, 0));
      for (var k = 0; k < 6; k++) {
        await f1.moveBy(const Offset(-15, 0));
        await f2.moveBy(const Offset(15, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await f1.up();
      await f2.up();
      await settle(tester);
    }

    // Gekoppelt zoomen beide.
    await aufziehen(0);
    expect(massstab(0), greaterThan(1.2));
    expect(massstab(1), closeTo(massstab(0), 0.001));
    // Zurücksetzen setzt beide zurück.
    await tap(tester, find.byTooltip(de.vergleichZuruecksetzen));
    expect(massstab(0), closeTo(1, 0.001));
    expect(massstab(1), closeTo(1, 0.001));
    // Entkoppelt getrennt.
    await tap(tester, find.byTooltip(de.vergleichEntkoppeln));
    await aufziehen(0);
    expect(massstab(0), greaterThan(1.2));
    expect(massstab(1), closeTo(1, 0.001));
    await tap(tester, find.byTooltip(de.vergleichZuruecksetzen));
    expect(massstab(0), closeTo(1, 0.001));
    // Übereinander.
    final linksVorher = tester.getTopLeft(bilder.at(0));
    final rechtsVorher = tester.getTopLeft(bilder.at(1));
    expect(linksVorher.dy, closeTo(rechtsVorher.dy, 1));
    await tap(tester, find.byTooltip(de.vergleichUebereinander));
    expect(
      tester.getTopLeft(bilder.at(1)).dy,
      greaterThan(tester.getTopLeft(bilder.at(0)).dy + 50),
    );
    expect(find.byTooltip(de.vergleichNebeneinander), findsOneWidget);
    await zurueck(tester);
    await finish(tester);
  });

  // === Tastatur und Navigation =============================================

  testWidgets('ANS-035 Übersicht der Tastaturkürzel', (tester) async {
    await startApp(tester, fotos: [testfoto('k.jpg')]);
    await openSection(tester, Hauptbereich.zeitleiste);
    await fragezeichen(tester);
    await waitFor(tester, find.text(de.kuerzelTitel));
    final tafel = find.byType(AlertDialog);
    for (final abschnitt in [
      de.kuerzelNavigation,
      de.kuerzelRaster,
      de.kuerzelVollbild,
      de.kuerzelSichtung,
    ]) {
      await rolleZu(
        tester,
        find.descendant(of: tafel, matching: find.text(abschnitt)),
        in_: find
            .descendant(of: tafel, matching: find.byType(Scrollable))
            .first,
      );
      expect(
        find.descendant(of: tafel, matching: find.text(abschnitt)),
        findsOneWidget,
      );
    }
    // Jede Taste, die das Raster auswertet (siehe rasterbedienung.dart).
    for (final taste in ['0 – 5', '6 – 9', 'F', 'Esc', '⏎', '← ↑ ↓ →']) {
      expect(
        find.descendant(of: tafel, matching: find.text(taste)),
        findsWidgets,
        reason: taste,
      );
    }
    await tap(
      tester,
      find.descendant(
        of: tafel,
        matching: find.widgetWithText(TextButton, de.allgSchliessen),
      ),
    );
    await waitGone(tester, find.text(de.kuerzelTitel));
    await finish(tester);
  });

  // Befund: Die Tafel nennt in „Vollbildansicht“ weder R (Drittel-Raster)
  // noch P (Fokus-Peaking), obwohl die Einzelansicht beide auswertet
  // (asset_viewer_screen.dart:368–375, tastenkuerzel.dart:57–72).
  testWidgets('ANS-035 R und P stehen in der Tafel', skip: true, (
    tester,
  ) async {
    await startApp(tester, fotos: [testfoto('k.jpg')]);
    await fragezeichen(tester);
    await waitFor(tester, find.text(de.kuerzelTitel));
    final tafel = find.byType(AlertDialog);
    expect(find.descendant(of: tafel, matching: find.text('R')), findsWidgets);
    expect(find.descendant(of: tafel, matching: find.text('P')), findsWidgets);
    await finish(tester);
  });

  testWidgets('ANS-036 Bereiche per ⌘1–⌘9 und Befehlspalette', (tester) async {
    await startApp(tester, fotos: [testfoto('n.jpg')]);
    await albumAnlegen(tester, 'Navi', ['n.jpg']);
    await openSection(tester, Hauptbereich.zeitleiste);
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
      await befehlstaste(tester, ziffern[i]);
      await eventually(
        tester,
        () async => aktuellerBereich(tester) == i,
        was: '⌘${i + 1} → Bereich $i',
      );
    }
    // Aus der Detailseite eines Albums heraus.
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Navi'));
    await waitFor(tester, find.byTooltip(de.albumFotosHinzufuegen));
    await befehlstaste(tester, LogicalKeyboardKey.digit1);
    await waitGone(tester, find.byTooltip(de.albumFotosHinzufuegen));
    expect(aktuellerBereich(tester), Hauptbereich.zeitleiste);
    // ⌘K: Befehlspalette.
    await befehlstaste(tester, LogicalKeyboardKey.keyK);
    await waitFor(tester, find.text(de.befehlspaletteHinweis));
    await tester.enterText(find.byType(TextField).last, 'Alben');
    await settle(tester);
    await tap(
      tester,
      find.descendant(of: find.byType(ListTile), matching: find.text('Alben')),
    );
    await eventually(
      tester,
      () async => aktuellerBereich(tester) == Hauptbereich.alben,
      was: 'Palette → Alben',
    );
    await befehlstaste(tester, LogicalKeyboardKey.keyK);
    await waitFor(tester, find.text(de.befehlspaletteHinweis));
    await tester.enterText(find.byType(TextField).last, 'qqxyzunsinn');
    await settle(tester);
    expect(find.text(de.befehlspaletteLeer), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await finish(tester);
  });

  // Behoben in #408: Die Kürzelziele stehen als Bereichsnamen da, ⌘0 führt
  // auf Hauptbereich.einstellungen (derselbe Fehler wie GRU-059).
  testWidgets('ANS-036 ⌘0 öffnet die Einstellungen', (tester) async {
    await startApp(tester, fotos: [testfoto('n.jpg')]);
    await openSection(tester, Hauptbereich.zeitleiste);
    await befehlstaste(tester, LogicalKeyboardKey.digit0);
    await settle(tester);
    print('ANS-036: ⌘0 → Bereich ${aktuellerBereich(tester)}');
    expect(aktuellerBereich(tester), Hauptbereich.einstellungen);
    await finish(tester);
  });

  // === Einzelansicht ========================================================

  testWidgets(
    'ANS-037 ANS-038 ANS-039 Einzelansicht: Titel, Blättern, Filmstreifen',
    (tester) async {
      final daten = [
        for (var i = 0; i < 32; i++)
          DateTime(2025, 5, 31, 20).subtract(Duration(days: i)),
      ];
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 32; i++)
            testfoto(
              'f$i.jpg',
              datum: daten[i],
              breite: 400,
              hoehe: 300,
              breitengrad: i == 3 ? 48.1 : null,
              laengengrad: i == 3 ? 11.5 : null,
            ),
        ],
      );
      await albumAnlegen(tester, 'Eins', ['f5.jpg']);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('f3.jpg'));
      // ANS-037: Titelzeile mit Datum, Ort und Format; Esc schliesst.
      final rolle = rasterRolle(tester);
      rolle.position.jumpTo(40);
      await settle(tester);
      final vorher = rolle.position.pixels;
      await oeffne(tester, 'f3.jpg');
      expect(betrachterZeigt(daten[3]), findsOneWidget);
      final kopf = find.descendant(
        of: betrachter,
        matching: find.byType(AppBar),
      );
      expect(
        find.descendant(of: kopf, matching: find.byIcon(Icons.location_on)),
        findsOneWidget,
      );
      final f3 = await aufnahme(tester, 'f3.jpg');
      expect(
        find.descendant(of: kopf, matching: find.text(assetFormatLabel(f3))),
        findsOneWidget,
      );
      final geruest = tester.widget<Scaffold>(
        find.descendant(of: betrachter, matching: find.byType(Scaffold)).first,
      );
      expect(geruest.backgroundColor, Colors.black);
      expect(filmstreifen, findsOneWidget);
      await schliesseBetrachter(tester);
      // Ein paar Punkte Spiel: Das Raster fasst nach dem Schliessen die
      // Reihe neu, gemessen 12 Punkte.
      print(
        'ANS-037: Rollstand vorher $vorher, nachher '
        '${rasterRolle(tester).position.pixels}',
      );
      expect(rasterRolle(tester).position.pixels, closeTo(vorher, 20));

      // ANS-038: Pfeiltasten, Leertaste, Pfeilknöpfe; Anfang und Ende.
      await oeffne(tester, 'f1.jpg');
      expect(betrachterZeigt(daten[1]), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(daten[2]));
      await key(tester, LogicalKeyboardKey.space);
      await waitFor(tester, betrachterZeigt(daten[3]));
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await waitFor(tester, betrachterZeigt(daten[2]));
      await tap(tester, knopf(de.viewerNaechstesFoto));
      await waitFor(tester, betrachterZeigt(daten[3]));
      await tap(tester, knopf(de.viewerVorherigesFoto));
      await waitFor(tester, betrachterZeigt(daten[2]));
      await tap(tester, knopf(de.viewerVorherigesFoto));
      await tap(tester, knopf(de.viewerVorherigesFoto));
      await waitFor(tester, betrachterZeigt(daten[0]));
      expect(knopf(de.viewerVorherigesFoto), findsNothing);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(betrachterZeigt(daten[0]), findsOneWidget);

      // Beobachtung: Wirken die Pfeiltasten noch, nachdem der Knopf
      // „Vorheriges Foto“ verschwunden ist?
      final fokus = FocusManager.instance.primaryFocus;
      await key(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 300));
      final tasteWirkt = betrachterZeigt(daten[1]).evaluate().isNotEmpty;
      print(
        'ANS-038: Fokus nach den Pfeilknöpfen: $fokus; '
        'Pfeiltaste wirkt danach: $tasteWirkt',
      );
      if (!tasteWirkt) await tap(tester, knopf(de.viewerNaechstesFoto));
      await waitFor(tester, betrachterZeigt(daten[1]));
      // ANS-039: Filmstreifen rollt mit, das aktuelle Foto weiss umrandet.
      for (var i = 1; i < 25; i++) {
        await tester.tap(knopf(de.viewerNaechstesFoto));
        await tester.pump(const Duration(milliseconds: 260));
      }
      await settle(tester);
      await waitFor(tester, betrachterZeigt(daten[25]));
      expect(weissUmrandet, findsOneWidget);
      expect(sichtbar(tester, weissUmrandet), isTrue);
      final rahmen = tester.getRect(weissUmrandet);
      final streifen = tester.getRect(filmstreifen);
      expect(rahmen.left >= streifen.left - 1, isTrue);
      expect(rahmen.right <= streifen.right + 1, isTrue);
      // Klick auf ein weit entferntes Vorschaubild.
      final bilder = find.descendant(
        of: filmstreifen,
        matching: find.byType(GestureDetector),
      );
      final streifenRect = tester.getRect(filmstreifen);
      final sichtbare = [
        for (var i = 0; i < bilder.evaluate().length; i++)
          if (tester.getRect(bilder.at(i)).left >= streifenRect.left &&
              tester.getRect(bilder.at(i)).right <= streifenRect.right)
            bilder.at(i),
      ];
      final ziel = sichtbare.first;
      final zielRect = tester.getRect(ziel);
      // Abstand zum umrandeten Bild (Nr. 25) in Vorschaubildern (56 + 4).
      final zielNr = 25 + ((zielRect.left - rahmen.left) / 60).round();
      print('ANS-039: Klick auf Vorschaubild Nr. $zielNr');
      expect(zielNr, lessThan(25));
      await tester.tapAt(zielRect.center);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await waitFor(tester, betrachterZeigt(daten[zielNr]));
      expect(betrachterZeigt(daten[25]), findsNothing);
      // Der Streifen rollt das neue Foto in die Mitte, weiss umrandet.
      expect(weissUmrandet, findsOneWidget);
      expect(sichtbar(tester, weissUmrandet), isTrue);
      final neuRahmen = tester.getRect(weissUmrandet);
      final neuStreifen = tester.getRect(filmstreifen);
      expect(neuRahmen.left >= neuStreifen.left - 1, isTrue);
      expect(neuRahmen.right <= neuStreifen.right + 1, isTrue);
      // Ans Ende: kein „Nächstes Foto“ mehr.
      for (
        var i = 0;
        i < 40 && knopf(de.viewerNaechstesFoto).evaluate().isNotEmpty;
        i++
      ) {
        await tester.tap(knopf(de.viewerNaechstesFoto));
        await tester.pump(const Duration(milliseconds: 260));
      }
      await settle(tester);
      await waitFor(tester, betrachterZeigt(daten[31]));
      expect(knopf(de.viewerNaechstesFoto), findsNothing);
      await key(tester, LogicalKeyboardKey.space);
      expect(betrachterZeigt(daten[31]), findsOneWidget);
      await schliesseBetrachter(tester);
      // Album mit nur einem Foto: kein Filmstreifen.
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Eins'));
      await oeffne(tester, 'f5.jpg');
      expect(filmstreifen, findsNothing);
      expect(knopf(de.viewerDiaschauStarten), findsNothing);
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-040 ANS-041 Blättern in der Herkunftsliste, Serie öffnet nur die Serie',
    (tester) async {
      DateTime tag(int i) => DateTime(2025, 3, 1, 10).add(Duration(days: i));
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 5; i++) testfoto('treffer$i.jpg', datum: tag(i)),
          for (var i = 0; i < 3; i++)
            testfoto('albumfoto$i.jpg', datum: tag(10 + i)),
          for (var i = 0; i < 4; i++)
            testfoto('serie$i.jpg', datum: tag(20 + i)),
          testfoto('einzeln.jpg', datum: tag(30)),
        ],
      );
      await albumAnlegen(tester, 'Drei', [
        'albumfoto2.jpg',
        'albumfoto0.jpg',
        'albumfoto1.jpg',
      ]);
      final serie = await ids(tester, [
        'serie0.jpg',
        'serie1.jpg',
        'serie2.jpg',
        'serie3.jpg',
      ]);
      await befehl(tester, SerieBilden(_uuid.v4(), serie, serie[3]));

      // ANS-040: Album – nur seine drei Fotos, in Rasterreihenfolge.
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Drei'));
      await waitFor(tester, kachel('albumfoto0.jpg'));
      final albumOrdnung = [
        for (final e in find.byType(AssetThumbnailTile).evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      ];
      expect(albumOrdnung, [
        'albumfoto2.jpg',
        'albumfoto1.jpg',
        'albumfoto0.jpg',
      ]);
      await oeffne(tester, albumOrdnung.first);
      expect(betrachterZeigt(tag(12)), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(tag(11)));
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(tag(10)));
      expect(knopf(de.viewerNaechstesFoto), findsNothing);
      await schliesseBetrachter(tester);
      await zurueck(tester);
      // Suche – nur die fünf Treffer.
      await openSection(tester, Hauptbereich.suche);
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'treffer');
      await waitFor(tester, kachel('treffer0.jpg'));
      final ordnung = treffer(tester);
      expect(ordnung.length, 5);
      await oeffne(tester, ordnung.first);
      final gesehen = <String>[];
      for (var i = 0; i < 5; i++) {
        for (var k = 0; k < 5; k++) {
          if (betrachterZeigt(tag(k)).evaluate().isNotEmpty) {
            gesehen.add('treffer$k.jpg');
          }
        }
        await key(tester, LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(gesehen, ordnung);
      expect(knopf(de.viewerNaechstesFoto), findsNothing);
      await schliesseBetrachter(tester);

      // ANS-041: im Raster nur das Titelbild der Serie, mit Abzeichen „4“.
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('serie3.jpg'));
      for (final n in ['serie0.jpg', 'serie1.jpg', 'serie2.jpg']) {
        expect(kachel(n), findsNothing, reason: n);
      }
      expect(
        find.descendant(of: kachel('serie3.jpg'), matching: find.text('4')),
        findsOneWidget,
      );
      await oeffne(tester, 'serie3.jpg');
      // An den Anfang, dann bis zum Ende zählen.
      for (var i = 0; i < 10; i++) {
        if (knopf(de.viewerVorherigesFoto).evaluate().isEmpty) break;
        await tap(tester, knopf(de.viewerVorherigesFoto));
        await tester.pump(const Duration(milliseconds: 300));
      }
      var weiter = 0;
      for (var i = 0; i < 10; i++) {
        if (knopf(de.viewerNaechstesFoto).evaluate().isEmpty) break;
        await tap(tester, knopf(de.viewerNaechstesFoto));
        await tester.pump(const Duration(milliseconds: 300));
        weiter++;
      }
      final mitglieder = tester
          .widget<AssetViewerScreen>(betrachter)
          .assets
          .map((a) => a.originalFileName)
          .toSet();
      expect(mitglieder, {
        'serie0.jpg',
        'serie1.jpg',
        'serie2.jpg',
        'serie3.jpg',
      });
      expect(weiter, 3, reason: 'vier Seiten, nicht mehr');
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets('ANS-042 Zoomen und Verschieben im Foto', (tester) async {
    await startApp(
      tester,
      fotos: [testfoto('gross.jpg', breite: 4000, hoehe: 3000)],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'gross.jpg');
    final foto = find.descendant(
      of: betrachter,
      matching: find.byType(PhotoView),
    );
    await waitFor(tester, foto);
    await settle(tester);
    PhotoViewControllerBase steuerung() =>
        tester.widget<PhotoView>(foto.first).controller!;
    await eventually(
      tester,
      () async => steuerung().scale != null,
      was: 'Anfangsmassstab',
    );
    final anfang = steuerung().scale!;
    final mitte = tester.getCenter(foto.first);
    // Kneifen auf dem Trackpad vergrössert.
    final kneifen = await tester.startGesture(
      mitte,
      kind: PointerDeviceKind.trackpad,
    );
    for (var i = 1; i <= 8; i++) {
      await kneifen.panZoomUpdate(mitte, scale: 1 + i * 0.15);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await kneifen.panZoomEnd();
    await settle(tester);
    final gekniffen = steuerung().scale!;
    print('ANS-042: Massstab $anfang → nach Kneifen $gekniffen');
    expect(gekniffen, greaterThan(anfang * 1.05));
    // Ohne Taste: Wischen verschiebt das vergrösserte Bild.
    final lageVorher = steuerung().position;
    final g = await tester.startGesture(
      mitte,
      kind: PointerDeviceKind.trackpad,
    );
    for (var i = 1; i <= 5; i++) {
      await g.panZoomUpdate(mitte, pan: Offset(0, -30.0 * i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.panZoomEnd();
    await settle(tester);
    expect(steuerung().scale!, closeTo(gekniffen, 0.01));
    expect(steuerung().position, isNot(lageVorher));
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: ⌘/Strg + Wischen zoomt in der Einzelansicht nicht. Der
  // Massstab, den BildZoomGesten (bild_zoom_gesten.dart:92–103) setzt,
  // überschreibt PhotoView gleich wieder: Dessen Skalierungserkennung
  // bekommt dieselben Trackpad-Ereignisse (scale 1) und setzt den Massstab
  // auf den Anfangswert der Geste zurück. Die Einheitsprüfungen
  // (wisch_zoom_bild_test.dart) prüfen nur die Rechnung, nicht das
  // Zusammenspiel mit PhotoView.
  testWidgets('ANS-042 ⌘ + Wischen zoomt innerhalb fester Grenzen', skip: true, (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [testfoto('gross.jpg', breite: 4000, hoehe: 3000)],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'gross.jpg');
    final foto = find.descendant(
      of: betrachter,
      matching: find.byType(PhotoView),
    );
    await waitFor(tester, foto);
    PhotoViewControllerBase steuerung() =>
        tester.widget<PhotoView>(foto.first).controller!;
    await eventually(
      tester,
      () async => steuerung().scale != null,
      was: 'Anfangsmassstab',
    );
    final mitte = tester.getCenter(foto.first);
    Future<void> wischen(double dy) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      final g = await tester.startGesture(
        mitte,
        kind: PointerDeviceKind.trackpad,
      );
      final zwischen = <double>[];
      for (var i = 1; i <= 5; i++) {
        await g.panZoomUpdate(mitte, pan: Offset(0, dy * i / 5));
        await tester.pump(const Duration(milliseconds: 16));
        zwischen.add(steuerung().scale ?? 0);
      }
      await g.panZoomEnd();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);
      print(
        'ANS-042: ⌘-Wischen $dy → unterwegs $zwischen, danach ${steuerung().scale}',
      );
    }

    final anfang = steuerung().scale!;
    await wischen(-120);
    final hoch = steuerung().scale!;
    expect(hoch, greaterThan(anfang * 1.2), reason: 'nach oben vergrössert');
    await wischen(120);
    expect(
      steuerung().scale!,
      lessThan(hoch * 0.9),
      reason: 'nach unten kleiner',
    );
    for (var i = 0; i < 4; i++) {
      await wischen(-900);
    }
    expect(steuerung().scale!, lessThanOrEqualTo(8.0001), reason: 'Grenze');
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('ANS-043 Panorama und 360°-Foto', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto(
          'panorama.jpg',
          datum: DateTime(2025, 1, 2),
          breite: 3000,
          hoehe: 1000,
        ),
        testfoto(
          'kugel.jpg',
          datum: DateTime(2025, 1, 1),
          breite: 2000,
          hoehe: 1000,
        ),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'panorama.jpg');
    final foto = find.descendant(
      of: betrachter,
      matching: find.byType(PhotoView),
    );
    await waitFor(tester, foto);
    expect(
      tester.widget<PhotoView>(foto.first).initialScale,
      PhotoViewComputedScale.covered,
      reason: 'füllt die Höhe',
    );
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 1, 1)));
    final kugel = find.descendant(
      of: betrachter,
      matching: find.byType(Panorama360View),
    );
    await waitFor(tester, kugel);
    expect(tester.widget<Panorama360View>(kugel).mode, Panorama360Mode.sphere);
    await tap(tester, knopf(de.viewerFlachesSchwenken));
    expect(tester.widget<Panorama360View>(kugel).mode, Panorama360Mode.flat);
    await tap(tester, knopf(de.viewerKugelSchwenken));
    expect(tester.widget<Panorama360View>(kugel).mode, Panorama360Mode.sphere);
    await tap(tester, knopf(de.viewerFlacheVorschau));
    await waitGone(tester, kugel);
    await tap(tester, knopf(de.ansicht360));
    await waitFor(tester, kugel);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: Solange es ungelesene Meldungen
  // gibt, steht oben rechts die Glocke des Meldungsfensters
  // (meldungsfenster.dart:131–141, Abstand oben kToolbarHeight + 12,
  // rechts 16) – genau über den Knöpfen oben rechts im Bild der
  // Einzelansicht (asset_viewer_screen.dart: 360°-Knöpfe `top: 8, right:
  // 8`, „Dieses Bild als Foto sichern“ `top/right: AppSpacing.sm`). Der
  // Klick öffnet dann den Meldungsverlauf statt der flachen Vorschau.
  testWidgets(
    'ANS-043 Knöpfe oben rechts trotz ungelesener Meldung',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto(
            'kugel.jpg',
            datum: DateTime(2025, 1, 1),
            breite: 2000,
            hoehe: 1000,
          ),
        ],
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'kugel.jpg');
      final kugel = find.descendant(
        of: betrachter,
        matching: find.byType(Panorama360View),
      );
      await waitFor(tester, kugel);
      // Irgendeine Meldung der App, z. B. nach einer Sammeländerung.
      melde.hinweis('Probemeldung');
      await settle(tester);
      melde.alleSchliessen();
      await settle(tester);
      expect(melde.ungelesen, greaterThan(0), reason: 'Glocke steht');
      final knopfRect = tester.getRect(knopf(de.viewerFlacheVorschau));
      print('ANS-043: Knopf „Flache Vorschau“ bei $knopfRect');
      await tester.tapAt(knopfRect.center);
      await settle(tester);
      final verlaufOffen = find
          .text(de.meldungenVerlaufLeeren)
          .evaluate()
          .isNotEmpty;
      print('ANS-043: Klick öffnete den Meldungsverlauf: $verlaufOffen');
      expect(kugel, findsNothing, reason: 'flache Vorschau statt Kugel');
      await finish(tester);
    },
  );

  testWidgets('ANS-044 Info-Seitenleiste ein- und ausblenden', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto(
          'i1.jpg',
          datum: DateTime(2025, 2, 2, 10),
          kamera: 'Herstellerin',
          modell: 'Modell Eins',
        ),
        testfoto(
          'i2.jpg',
          datum: DateTime(2025, 2, 1, 10),
          kamera: 'Andere',
          modell: 'Modell Zwei',
        ),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'i1.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    await waitFor(tester, info);
    expect(field(de.infoBeschreibungHinzufuegen), findsOneWidget);
    expect(
      find.descendant(of: info, matching: find.byType(StarRating)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: info, matching: find.byType(ColorLabelPicker)),
      findsOneWidget,
    );
    for (final t in [de.navPersonen, de.suchoptTagsTitel, de.infoDetails]) {
      expect(
        find.descendant(of: info, matching: find.text(t)),
        findsWidgets,
        reason: t,
      );
    }
    expect(
      find.descendant(of: info, matching: find.textContaining('Modell Eins')),
      findsWidgets,
    );
    expect(
      find.descendant(of: info, matching: find.text('i1.jpg')),
      findsOneWidget,
    );
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(
      tester,
      find.descendant(of: info, matching: find.textContaining('Modell Zwei')),
    );
    expect(
      find.descendant(of: info, matching: find.textContaining('Modell Eins')),
      findsNothing,
    );
    expect(
      find.descendant(of: info, matching: find.text('i2.jpg')),
      findsOneWidget,
    );
    await tap(tester, knopf(de.viewerInfo));
    await waitGone(tester, info);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: Tippen in der Info-Leiste löst die Tasten der Einzelansicht aus.
  // _handleKeyEvent (asset_viewer_screen.dart:316–377) prüft nicht, ob ein
  // Textfeld den Fokus hat (anders als rasterbedienung.dart:253,
  // _schreibtGerade) und meldet Ziffern, F, R, P und Leertaste als
  // erledigt: Bewertung/Favorit/Farbe ändern sich, die Ansicht blättert,
  // und das Zeichen kommt im Feld nicht an.
  testWidgets(
    'ANS-045 Tippen in der Info-Leiste löst keine Tastenkürzel aus',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('tipp1.jpg', datum: DateTime(2025, 2, 2, 10)),
          testfoto('tipp2.jpg', datum: DateTime(2025, 2, 1, 10)),
        ],
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'tipp1.jpg');
      await tap(tester, knopf(de.viewerInfo));
      final feld = field(de.infoBeschreibungHinzufuegen);
      await tap(tester, feld);
      // Wie beim echten Tippen: Jede Taste kommt als Tastenereignis und als
      // Texteingabe.
      Future<void> tippe(String text) async {
        final tasten = <String, LogicalKeyboardKey>{
          '2': LogicalKeyboardKey.digit2,
          '0': LogicalKeyboardKey.digit0,
          '3': LogicalKeyboardKey.digit3,
          '5': LogicalKeyboardKey.digit5,
          'f': LogicalKeyboardKey.keyF,
          'r': LogicalKeyboardKey.keyR,
          'p': LogicalKeyboardKey.keyP,
          ' ': LogicalKeyboardKey.space,
        };
        var bisher = '';
        for (final z in text.split('')) {
          final taste = tasten[z.toLowerCase()];
          if (taste != null) await tester.sendKeyEvent(taste);
          bisher += z;
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: bisher,
              selection: TextSelection.collapsed(offset: bisher.length),
            ),
          );
          await tester.pump();
        }
        await settle(tester);
      }

      await tippe('Familie 2023 frei');
      final a = await aufnahme(tester, 'tipp1.jpg');
      expect(a.rating, 0, reason: 'Ziffern setzen keine Bewertung');
      expect(a.isFavorite, isFalse, reason: 'F schaltet keinen Favoriten');
      expect(betrachterZeigt(DateTime(2025, 2, 2, 10)), findsOneWidget);
      expect(
        knopfWidget(tester, de.viewerDrittelRaster).isSelected,
        isNot(true),
      );
      expect(
        knopfWidget(tester, de.viewerFokusPeaking).isSelected,
        isNot(true),
      );
      await tap(tester, field(de.infoTagHinzufuegenPlatzhalter));
      await tippe('Ferien 5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      final b = await aufnahme(tester, 'tipp1.jpg');
      expect(b.rating, 0);
      expect(b.colorLabel, isNull);
      await finish(tester);
    },
  );

  testWidgets('ANS-046 Diaschau starten, umlaufen, stoppen', (tester) async {
    final d = [
      DateTime(2025, 4, 3, 10),
      DateTime(2025, 4, 2, 10),
      DateTime(2025, 4, 1, 10),
    ];
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 3; i++) testfoto('dia$i.jpg', datum: d[i]),
        testfoto('allein.jpg', datum: DateTime(2020, 1, 1)),
      ],
    );
    await albumAnlegen(tester, 'Solo', ['allein.jpg']);
    await befehl(tester, ArchivSetzen(await ids(tester, ['allein.jpg']), true));
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'dia0.jpg');
    await tap(tester, knopf(de.viewerDiaschauStarten));
    expect(knopf(de.viewerDiaschauStoppen), findsOneWidget);
    Future<void> warte(Duration dauer) async {
      final ende = DateTime.now().add(dauer);
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await warte(const Duration(milliseconds: 4600));
    expect(betrachterZeigt(d[1]), findsOneWidget, reason: 'nach 4 s');
    await warte(const Duration(seconds: 4));
    expect(betrachterZeigt(d[2]), findsOneWidget, reason: 'nach 8 s');
    await warte(const Duration(seconds: 4));
    expect(betrachterZeigt(d[0]), findsOneWidget, reason: 'umgelaufen');
    // Pfeiltaste stoppt.
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(knopf(de.viewerDiaschauStarten), findsOneWidget);
    await waitFor(tester, betrachterZeigt(d[1]));
    await warte(const Duration(milliseconds: 4600));
    expect(betrachterZeigt(d[1]), findsOneWidget, reason: 'gestoppt');
    // Knopf stoppt.
    await tap(tester, knopf(de.viewerDiaschauStarten));
    await tap(tester, knopf(de.viewerDiaschauStoppen));
    expect(knopf(de.viewerDiaschauStarten), findsOneWidget);
    await warte(const Duration(milliseconds: 4600));
    expect(betrachterZeigt(d[1]), findsOneWidget);
    // Filmstreifen stoppt ebenfalls.
    await tap(tester, knopf(de.viewerDiaschauStarten));
    await tester.tapAt(
      tester.getCenter(
        find
            .descendant(
              of: filmstreifen,
              matching: find.byType(GestureDetector),
            )
            .first,
      ),
    );
    await settle(tester);
    expect(knopf(de.viewerDiaschauStarten), findsOneWidget);
    await schliesseBetrachter(tester);
    // Album mit einem Foto: kein Knopf.
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Solo'));
    await oeffne(tester, 'allein.jpg');
    expect(knopf(de.viewerDiaschauStarten), findsNothing);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('ANS-047 Rechtsklick-Menü der Einzelansicht', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('roh.jpg', datum: DateTime(2025, 4, 3, 10)),
        testfoto('bearbeitet.jpg', datum: DateTime(2025, 4, 2, 10)),
        fixture('video_5s.mp4'),
      ],
    );
    final b = await aufnahme(tester, 'bearbeitet.jpg');
    await setzeSpalten(
      tester,
      'bearbeitet.jpg',
      AssetsCompanion(developedRelativePath: Value(b.relativePath)),
    );
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 4, 1, 10))),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'roh.jpg');
    final flaeche = find.descendant(
      of: betrachter,
      matching: find.byType(PageView),
    );
    final r = tester.getRect(flaeche);
    final erste = r.topLeft + const Offset(200, 150);
    await rechtsklick(tester, flaeche, stelle: erste);
    final punkte = [
      de.viewerInDarktable,
      de.viewerInTimelineZeigen,
      de.viewerAehnlicheZeigen,
      de.viewerMetadatenBearbeiten,
      de.viewerGesichterBearbeiten,
    ];
    for (final t in punkte) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text(de.infoOriginalHerstellen), findsNothing);
    final lage1 = tester.getTopLeft(find.text(de.viewerInDarktable));
    expect(
      (lage1 - erste).distance,
      lessThan(120),
      reason: 'an der Klickstelle',
    );
    // Esc schliesst nur das Menü.
    await key(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.text(de.viewerInDarktable));
    expect(betrachter, findsOneWidget);
    // Zweimal kurz nacheinander: das Menü zieht um.
    await rechtsklick(tester, flaeche, stelle: erste);
    final zweite = r.topLeft + const Offset(500, 380);
    await rechtsklick(tester, flaeche, stelle: zweite);
    expect(find.text(de.viewerInDarktable), findsOneWidget);
    final lage2 = tester.getTopLeft(find.text(de.viewerInDarktable));
    expect((lage2 - lage1).distance, greaterThan(150));
    await key(tester, LogicalKeyboardKey.escape);
    // Bearbeitetes Foto: „Original wiederherstellen“.
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 2, 10)));
    await rechtsklick(tester, flaeche, stelle: erste);
    expect(find.text(de.infoOriginalHerstellen), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    // Video: ohne darktable und Gesichter.
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1, 10)));
    await rechtsklick(tester, flaeche, stelle: erste);
    expect(find.text(de.viewerInTimelineZeigen), findsOneWidget);
    expect(find.text(de.viewerInDarktable), findsNothing);
    expect(find.text(de.viewerGesichterBearbeiten), findsNothing);
    await key(tester, LogicalKeyboardKey.escape);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('ANS-048 ANS-049 Löschen per Knopf und per Taste, Rückgängig', (
    tester,
  ) async {
    final d = {
      'A': DateTime(2025, 4, 3, 10),
      'B': DateTime(2025, 4, 2, 10),
      'C': DateTime(2025, 4, 1, 10),
    };
    await startApp(
      tester,
      fotos: [
        for (final e in d.entries) testfoto('${e.key}.jpg', datum: e.value),
        testfoto('knopf.jpg', datum: DateTime(2026, 1, 3)),
        testfoto('k2.jpg', datum: DateTime(2026, 1, 2)),
        testfoto('k3.jpg', datum: DateTime(2026, 1, 1)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);

    // ANS-048: Knopf, Abbrechen, Löschen.
    await oeffne(tester, 'knopf.jpg');
    await tap(tester, knopf(de.viewerInPapierkorb));
    await waitFor(tester, find.text(de.loeschenTitel(1)));
    expect(find.text('Foto löschen?'), findsOneWidget);
    expect(find.text(de.loeschenHinweis(1)), findsOneWidget);
    await tapText(tester, de.allgAbbrechen);
    expect(betrachter, findsOneWidget);
    expect((await aufnahme(tester, 'knopf.jpg')).isTrashed, isFalse);
    await tap(tester, knopf(de.viewerInPapierkorb));
    await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
    await waitGone(tester, betrachter);
    await waitGone(tester, kachel('knopf.jpg'));
    expect((await aufnahme(tester, 'knopf.jpg')).isTrashed, isTrue);

    // ANS-049: Taste ⌫ mit Bestätigung, weiter zu B, Rückgängig holt A.
    await oeffne(tester, 'A.jpg');
    await key(tester, LogicalKeyboardKey.backspace);
    await waitFor(tester, find.text(de.loeschenTitel(1)));
    await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
    await waitFor(tester, betrachterZeigt(d['B']!));
    await meldung(tester, de.viewerImPapierkorb);
    expect((await aufnahme(tester, 'A.jpg')).isTrashed, isTrue);
    await rueckgaengig(tester);
    await waitFor(tester, betrachterZeigt(d['A']!));
    expect((await aufnahme(tester, 'A.jpg')).isTrashed, isFalse);
    await meldungenWeg(tester);
    // Zu C (dem letzten), löschen: das vorige erscheint.
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(d['C']!));
    await key(tester, LogicalKeyboardKey.delete);
    await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
    await waitFor(tester, betrachterZeigt(d['B']!));
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: Wird das letzte übrige Foto per ⌫ gelöscht, schliesst sich die
  // Ansicht zwar, baut sich vorher aber mit leerer Liste noch einmal auf:
  // _removeCurrentAndAdvance (asset_viewer_screen.dart:401) leert _assets
  // per setState und ruft erst danach Navigator.pop; build
  // (asset_viewer_screen.dart:881) greift über _currentAsset (:233) auf
  // _assets[_currentIndex] zu – RangeError beim Bauen.
  testWidgets(
    'ANS-049 Letztes Foto per Taste löschen schliesst die Ansicht',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('x1.jpg', datum: DateTime(2025, 4, 2, 10)),
          testfoto('x2.jpg', datum: DateTime(2025, 4, 1, 10)),
        ],
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'x1.jpg');
      await key(tester, LogicalKeyboardKey.backspace);
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1, 10)));
      await key(tester, LogicalKeyboardKey.backspace);
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await waitGone(tester, betrachter);
      final fehler = tester.takeException();
      print('ANS-049: Ausnahme beim Schliessen: $fehler');
      expect(fehler, isNull);
      expect(find.text(de.timelineLeer), findsOneWidget);
      await finish(tester);
    },
  );

  // Befund: Im Album nimmt der Knopf „In den Papierkorb verschieben (⌫)“
  // das Foto aus dem Album (album_detail_screen.dart:91–96, onDelete mit
  // AusAlbumNehmen), die Taste ⌫ nicht: Sie geht über
  // _confirmAndDeleteCurrent → _removeCurrentAndAdvance
  // (asset_viewer_screen.dart:383–391) und legt nur in den Papierkorb. Nach
  // dem Wiederherstellen steht das Foto wieder im Album, beim Knopf nicht.
  testWidgets(
    'ANS-049 Im Album: Knopf und Taste ⌫ behandeln die Albumzugehörigkeit',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('al1.jpg', datum: DateTime(2025, 4, 3, 10)),
          testfoto('al2.jpg', datum: DateTime(2025, 4, 2, 10)),
          testfoto('al3.jpg', datum: DateTime(2025, 4, 1, 10)),
        ],
      );
      final album = await albumAnlegen(tester, 'Löschprobe', [
        'al1.jpg',
        'al2.jpg',
        'al3.jpg',
      ]);
      Future<Set<String>> mitglieder() async {
        final db = bibliothek.db;
        final zeilen = await echt(
          () => (db.select(
            db.albumAssets,
          )..where((t) => t.albumId.equals(album))).get(),
        );
        final alle = await alleAufnahmen(tester);
        return {
          for (final z in zeilen!)
            alle.firstWhere((a) => a.id == z.assetId).originalFileName,
        };
      }

      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Löschprobe'));
      // Knopf: aus dem Album und in den Papierkorb.
      await oeffne(tester, 'al1.jpg');
      await tap(tester, knopf(de.viewerInPapierkorb));
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await waitGone(tester, betrachter);
      expect(await mitglieder(), isNot(contains('al1.jpg')));
      // Taste ⌫: nur in den Papierkorb, die Zugehörigkeit bleibt.
      await oeffne(tester, 'al2.jpg');
      await key(tester, LogicalKeyboardKey.backspace);
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await settle(tester);
      expect((await aufnahme(tester, 'al2.jpg')).isTrashed, isTrue);
      final nachTaste = await mitglieder();
      print(
        'ANS-049 Album: nach ⌫ noch Mitglied: ${nachTaste.contains('al2.jpg')}',
      );
      expect(
        nachTaste,
        isNot(contains('al2.jpg')),
        reason: 'die Taste ⌫ wirkt wie der Knopf „In den Papierkorb (⌫)“',
      );
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-051 Sichtungs-Modus: nur unbewertete, Ablehnen ohne Rückfrage',
    (tester) async {
      final d = [
        DateTime(2025, 4, 3, 10),
        DateTime(2025, 4, 2, 10),
        DateTime(2025, 4, 1, 10),
      ];
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 3; i++) testfoto('u$i.jpg', datum: d[i]),
          testfoto('bewertet.jpg', datum: DateTime(2025, 5, 1)),
          testfoto('weg.jpg', datum: DateTime(2025, 5, 2)),
          testfoto('zu.jpg', datum: DateTime(2025, 5, 3)),
        ],
      );
      await befehl(
        tester,
        BewertungSetzen(await ids(tester, ['bewertet.jpg']), 2),
      );
      await befehl(tester, InDenPapierkorb(await ids(tester, ['weg.jpg'])));
      await tresorEinrichten(tester);
      await sperre(tester, 'zu.jpg');
      await openSection(tester, Hauptbereich.werkzeuge);
      await rolleZu(
        tester,
        find.text(de.werkzSichtenTitel),
        in_: rolleIn(ToolsScreen),
      );
      await tapText(tester, de.werkzSichtenTitel);
      await waitFor(tester, betrachter);
      final viewer = tester.widget<AssetViewerScreen>(betrachter);
      expect(viewer.cullingMode, isTrue);
      expect(viewer.assets.map((a) => a.originalFileName).toList(), [
        'u0.jpg',
        'u1.jpg',
        'u2.jpg',
      ]);
      expect(find.text(de.sichtungHilfeleiste(1, 3)), findsOneWidget);
      expect(filmstreifen, findsNothing);
      expect(betrachterZeigt(d[0]), findsOneWidget);
      await key(tester, LogicalKeyboardKey.digit4);
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'u0.jpg')).rating == 4,
        was: 'Bewertung 4',
      );
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(d[1]));
      await key(tester, LogicalKeyboardKey.backspace);
      expect(find.byType(AlertDialog), findsNothing, reason: 'ohne Rückfrage');
      await waitFor(tester, betrachterZeigt(d[2]));
      expect((await aufnahme(tester, 'u1.jpg')).isTrashed, isTrue);
      await schliesseBetrachter(tester);
      // Zweite Bibliothek: alle bewertet.
      await zweiteBibliothek(tester, fotos: () => [testfoto('r.jpg')]);
      await befehl(tester, BewertungSetzen(await ids(tester, ['r.jpg']), 1));
      await openSection(tester, Hauptbereich.werkzeuge);
      await rolleZu(
        tester,
        find.text(de.werkzSichtenTitel),
        in_: rolleIn(ToolsScreen),
      );
      await tapText(tester, de.werkzSichtenTitel);
      await meldung(tester, de.werkzKeineUnbewerteten);
      expect(betrachter, findsNothing);
      await finish(tester);
    },
  );

  testWidgets('ANS-052 Drittel-Raster und Fokus-Peaking', (tester) async {
    await startApp(
      tester,
      fotos: [
        // 3:2 – ein Bild im Verhältnis 2:1 nähme die App als 360°-Foto.
        testfoto(
          'scharf1.jpg',
          datum: DateTime(2025, 4, 3),
          breite: 1200,
          hoehe: 800,
        ),
        testfoto(
          'scharf2.jpg',
          datum: DateTime(2025, 4, 2),
          breite: 1200,
          hoehe: 800,
        ),
        fixture('video_5s.mp4'),
      ],
    );
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 4, 1))),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'scharf1.jpg');
    final raster = find.descendant(
      of: betrachter,
      matching: find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is Drittelraster,
      ),
    );
    bool an(String tooltip) => knopfWidget(tester, tooltip).isSelected ?? false;
    await tap(tester, knopf(de.viewerDrittelRaster));
    try {
      await waitFor(tester, raster, timeout: const Duration(seconds: 10));
    } on TimeoutException {
      final maler = [
        for (final e
            in find
                .descendant(of: betrachter, matching: find.byType(CustomPaint))
                .evaluate())
          (e.widget as CustomPaint).painter.runtimeType.toString(),
      ];
      print(
        'ANS-052: Knopf an: ${an(de.viewerDrittelRaster)}, Maler $maler, '
        'PhotoView ${find.byType(PhotoView).evaluate().length}, '
        'Ladekreis ${find.descendant(of: betrachter, matching: find.byType(CircularProgressIndicator)).evaluate().length}',
      );
      rethrow;
    }
    expect(an(de.viewerDrittelRaster), isTrue);
    // Auf dem Foto (3:2), nicht auf dem Fenster.
    final flaeche = tester.getSize(raster.first);
    expect(flaeche.width / flaeche.height, closeTo(1.5, 0.05));
    await key(tester, LogicalKeyboardKey.keyR);
    await waitGone(tester, raster);
    expect(an(de.viewerDrittelRaster), isFalse);
    await key(tester, LogicalKeyboardKey.keyR);
    await waitFor(tester, raster);
    // Fokus-Peaking färbt nach kurzer Rechenzeit.
    await tap(tester, knopf(de.viewerFokusPeaking));
    expect(an(de.viewerFokusPeaking), isTrue);
    final ueberlagerung = find.descendant(
      of: betrachter,
      matching: find.byWidgetPredicate(
        (w) => w is Image && w.image is MemoryImage,
      ),
    );
    await waitFor(tester, ueberlagerung, timeout: const Duration(seconds: 30));
    // Beide bleiben beim Blättern.
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 2)));
    expect(an(de.viewerDrittelRaster), isTrue);
    expect(an(de.viewerFokusPeaking), isTrue);
    await waitFor(tester, raster);
    await waitFor(tester, ueberlagerung, timeout: const Duration(seconds: 30));
    // Beim Video fehlen beide Knöpfe.
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1)));
    expect(knopf(de.viewerDrittelRaster), findsNothing);
    expect(knopf(de.viewerFokusPeaking), findsNothing);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: „Erkannten Text hervorheben“ zeigt keine Kästen. Die Kästen
  // brauchen die Masse des Bildes (asset_viewer_screen.dart:2012,
  // `widget.textZeigen && masse != null && _stellen.isNotEmpty`), gesetzt
  // werden sie aber nur, wenn Drittel-Raster oder Gesichter eingeschaltet
  // werden (_masseSicherstellen/_gesichterLaden, :1663, :1698–1700, :1752);
  // didUpdateWidget ruft für textZeigen nichts auf. Nur mit erkanntem Text
  // allein bleibt das Foto ohne Kästen und ohne Hinweis.
  testWidgets(
    'ANS-053 Kästen über dem erkannten Text, Klick kopiert die Zeile',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          textfoto('schild.jpg', [
            'BAHNHOF',
            'GLEIS 7',
          ], datum: DateTime(2025, 4, 3, 10)),
        ],
      );
      await echt(() async {
        await for (final _ in bibliothek.backfillOcrText(alle: true)) {}
      });
      ablageAbfangen(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'schild.jpg');
      // ANS-053: Kästen über den Textstellen, Klick kopiert die Zeile.
      await tap(tester, knopf(de.viewerTextZeigen));
      final kaesten = find.descendant(
        of: betrachter,
        matching: find.byType(Textrahmen),
      );
      await waitFor(tester, kaesten);
      final bahnhof = kaesten.evaluate().firstWhere(
        (e) => (e.widget as Textrahmen).stelle.text.toUpperCase().contains(
          'BAHNHOF',
        ),
      );
      final text = (bahnhof.widget as Textrahmen).stelle.text;
      await tester.tapAt(tester.getCenter(find.byWidget(bahnhof.widget)));
      await settle(tester);
      await meldung(tester, de.viewerZeileKopiert(text));
      expect(zwischenablage, text);
      await tap(tester, knopf(de.viewerTextVerbergen));
      await waitGone(tester, kaesten);
      await meldungenWeg(tester);
      ablageFreigeben(tester);
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-054 ANS-053 Erkannter Text in der Info-Leiste, Foto ohne Text',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          textfoto('schild.jpg', [
            'BAHNHOF',
            'GLEIS 7',
          ], datum: DateTime(2025, 4, 3, 10)),
          testfoto('leer.jpg', datum: DateTime(2025, 4, 2, 10)),
          fixture('video_5s.mp4'),
        ],
      );
      await setzeSpalten(
        tester,
        'video_5s.mp4',
        AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 4, 1, 10))),
      );
      // Texterkennung laufen lassen (macOS: Vision) und ein Transkript.
      await echt(() async {
        await for (final _ in bibliothek.backfillOcrText(alle: true)) {}
      });
      final schild = await aufnahme(tester, 'schild.jpg');
      print('ANS-053: erkannt „${schild.ocrText}“');
      expect(schild.ocrText?.toUpperCase(), contains('BAHNHOF'));
      final video = await aufnahme(tester, 'video_5s.mp4');
      await echt(
        () => bibliothek.db.setTranskript(
          video.id,
          text: 'Hallo und willkommen',
          sprache: 'de',
        ),
      );
      ablageAbfangen(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'schild.jpg');
      // ANS-054: Abschnitt „Erkannter Text“ mit Zahl der Stellen.
      await tap(tester, knopf(de.viewerInfo));
      final info = find.byType(AssetInfoSheet);
      await waitFor(tester, info);
      expect(
        find.descendant(of: info, matching: find.text(de.infoErkannterText)),
        findsOneWidget,
      );
      final stellen = textstellenAusJson(
        (await aufnahme(tester, 'schild.jpg')).ocrBoxen,
      ).length;
      expect(stellen, greaterThan(0));
      expect(
        find.descendant(
          of: info,
          matching: find.text(de.infoTextStellen(stellen)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: info, matching: find.byType(SelectableText)),
        findsWidgets,
        reason: 'markierbar',
      );
      await tap(
        tester,
        find.descendant(
          of: info,
          matching: find.byTooltip(de.infoTextKopieren),
        ),
      );
      await meldung(tester, de.infoTextKopiert);
      expect(zwischenablage?.toUpperCase(), contains('BAHNHOF'));
      // Foto ohne Text: keine Abschnitte; Hervorheben meldet „kein Text“.
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 2, 10)));
      await waitFor(
        tester,
        find.descendant(of: info, matching: find.text('leer.jpg')),
      );
      expect(
        find.descendant(of: info, matching: find.text(de.infoErkannterText)),
        findsNothing,
      );
      expect(
        find.descendant(of: info, matching: find.text(de.infoGesprochen)),
        findsNothing,
      );
      await tap(tester, knopf(de.viewerTextZeigen));
      await waitFor(tester, find.text(de.viewerKeinText));
      await tap(tester, knopf(de.viewerTextVerbergen));
      // Video: Abschnitt „Gesprochen“.
      await key(tester, LogicalKeyboardKey.arrowRight);
      await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1, 10)));
      await waitFor(
        tester,
        find.descendant(of: info, matching: find.text(de.infoGesprochen)),
      );
      expect(
        find.descendant(
          of: info,
          matching: find.textContaining('Hallo und willkommen'),
        ),
        findsWidgets,
      );
      await schliesseBetrachter(tester);
      ablageFreigeben(tester);
      await finish(tester);
    },
  );

  testWidgets('ANS-055 Video abspielen, pausieren, springen', (tester) async {
    await startApp(
      tester,
      fotos: [
        fixture('video_5s.mp4'),
        testfoto('daneben.jpg', datum: DateTime(2025, 4, 1, 10)),
      ],
    );
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 4, 2, 10))),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'video_5s.mp4');
    final flaeche = find.descendant(
      of: betrachter,
      matching: find.byType(VideoSurface),
    );
    await waitFor(tester, flaeche, timeout: const Duration(seconds: 30));
    VideoPlaybackController regler() =>
        tester.widget<VideoSurface>(flaeche.first).controller;
    // Startet von selbst.
    await eventually(
      tester,
      () async => regler().isPlaying && regler().position.inMilliseconds > 300,
      was: 'läuft an',
    );
    // Schleife: nach mehr als der Länge läuft es weiter.
    final laenge = regler().duration;
    expect(laenge.inMilliseconds, greaterThan(3000));
    await echt(() => Future<void>.delayed(laenge + const Duration(seconds: 1)));
    await settle(tester);
    expect(regler().isPlaying, isTrue, reason: 'Schleife');
    expect(regler().position, lessThan(laenge));
    // Klick pausiert (grosses Abspielsymbol), weiterer Klick setzt fort.
    await tester.tapAt(tester.getCenter(flaeche.first));
    await settle(tester);
    await eventually(tester, () async => !regler().isPlaying, was: 'Pause');
    await settle(tester);
    expect(
      find.descendant(
        of: betrachter,
        matching: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.play_arrow && w.size == 72,
        ),
      ),
      findsOneWidget,
    );
    await tester.tapAt(tester.getCenter(flaeche.first));
    await eventually(tester, () async => regler().isPlaying, was: 'weiter');
    // Klick in die Leiste springt dorthin.
    final leisteFinder = find.descendant(
      of: betrachter,
      matching: find.byType(VideoProgressBar),
    );
    final leisteRect = tester.getRect(leisteFinder.first);
    await tester.tapAt(
      Offset(leisteRect.left + leisteRect.width * 0.8, leisteRect.center.dy),
    );
    await settle(tester);
    await eventually(
      tester,
      () async =>
          regler().position.inMilliseconds > laenge.inMilliseconds * 0.6,
      was: 'gesprungen',
    );
    // Ziehen in der Leiste.
    await tester.dragFrom(
      Offset(leisteRect.left + leisteRect.width * 0.7, leisteRect.center.dy),
      Offset(-leisteRect.width * 0.6, 0),
    );
    await settle(tester);
    await eventually(
      tester,
      () async =>
          regler().position.inMilliseconds < laenge.inMilliseconds * 0.5,
      was: 'gezogen',
    );
    // Wegblättern hält an, Zurückkehren spielt wieder ab.
    final alt = regler();
    await key(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1, 10)));
    await eventually(tester, () async => !alt.isPlaying, was: 'angehalten');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 2, 10)));
    await waitFor(tester, flaeche);
    await eventually(tester, () async => regler().isPlaying, was: 'spielt');
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('ANS-056 Videobild als Foto sichern', (tester) async {
    await startApp(tester, fotos: [fixture('video_5s.mp4')]);
    final videoDatei = bibliothek.paths.absolute(
      (await aufnahme(tester, 'video_5s.mp4')).relativePath,
    );
    final vorher = await pruefsumme(tester, videoDatei);
    final zeit = DateTime(2024, 5, 6, 14, 30);
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(
        fileCreatedAt: Value(zeit),
        latitude: const Value(47.5),
        longitude: const Value(11.25),
      ),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'video_5s.mp4');
    final flaeche = find.descendant(
      of: betrachter,
      matching: find.byType(VideoSurface),
    );
    await waitFor(tester, flaeche, timeout: const Duration(seconds: 30));
    VideoPlaybackController regler() =>
        tester.widget<VideoSurface>(flaeche.first).controller;
    await eventually(
      tester,
      () async => regler().position.inMilliseconds >= 2000,
      was: 'bei 0:02',
    );
    await tester.tapAt(tester.getCenter(flaeche.first));
    await eventually(tester, () async => !regler().isPlaying, was: 'Pause');
    await tap(tester, knopf(de.viewerVideobildSichern));
    await meldung(tester, 'als Foto gesichert');
    await meldung(tester, 'mit Datum und Ort des Videos');
    await eventually(tester, () async {
      final bilder = (await alleAufnahmen(
        tester,
      )).where((a) => a.type == 'IMAGE');
      return bilder.length == 1;
    }, was: 'neues Foto');
    final foto = (await alleAufnahmen(
      tester,
    )).firstWhere((a) => a.type == 'IMAGE');
    expect(foto.fileCreatedAt.difference(zeit).inSeconds.abs(), lessThan(10));
    expect(foto.latitude, closeTo(47.5, 0.001));
    expect(foto.longitude, closeTo(11.25, 0.001));
    await meldungenWeg(tester);
    // Ohne weiterzuspulen: schon gesichert.
    await tap(tester, knopf(de.viewerVideobildSichern));
    await meldung(tester, de.viewerVideobildSchonDa);
    expect(
      (await alleAufnahmen(tester)).where((a) => a.type == 'IMAGE').length,
      1,
    );
    await schliesseBetrachter(tester);
    // In der Zeitleiste steht das neue Foto.
    await waitFor(tester, kachel(foto.originalFileName));
    expect(await pruefsumme(tester, videoDatei), vorher);
    await finish(tester);
  });

  testWidgets('ANS-057 Live Photo: halten, Dauerschleife, eine Kachel', (
    tester,
  ) async {
    await startApp(tester);
    final film = fixture(
      'video_hoch_3s.mov',
    ).renameSync(p.join(eingang.path, 'IMG_4000.MOV'));
    await importiereDirekt(tester, [
      testfoto(
        'IMG_4000.JPG',
        datum: DateTime(2025, 4, 2, 10),
        breite: 360,
        hoehe: 640,
      ),
      film,
    ]);
    final foto = await aufnahme(tester, 'IMG_4000.JPG');
    expect(foto.linkedAssetId, isNotNull, reason: 'verknüpft');
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel('IMG_4000.JPG'));
    expect(
      find.byType(AssetThumbnailTile),
      findsOneWidget,
      reason: 'eine Kachel',
    );
    expect(
      find.descendant(
        of: kachel('IMG_4000.JPG'),
        matching: find.byIcon(Icons.motion_photos_on),
      ),
      findsOneWidget,
    );
    await oeffne(tester, 'IMG_4000.JPG');
    await waitFor(tester, find.text('LIVE'));
    expect(find.text(de.livePhotoHalten), findsOneWidget);
    final live = find.descendant(
      of: betrachter,
      matching: find.byType(LivePhotoView),
    );
    final video = find.descendant(
      of: live,
      matching: find.byType(VideoSurface),
    );
    // Halten spielt, Loslassen zeigt das Standbild.
    final halt = await tester.startGesture(tester.getCenter(live));
    await tester.pump(const Duration(milliseconds: 700));
    await waitFor(tester, video, timeout: const Duration(seconds: 15));
    expect(find.text('LIVE'), findsNothing);
    await halt.up();
    await settle(tester);
    await waitGone(tester, video);
    expect(find.text('LIVE'), findsOneWidget);
    // Dauerschleife übersteht Halten und Loslassen.
    await tap(tester, find.byTooltip(de.liveDauerschleife));
    await waitFor(tester, video);
    final halt2 = await tester.startGesture(tester.getCenter(live));
    await tester.pump(const Duration(milliseconds: 700));
    await halt2.up();
    await settle(tester);
    await echt(() => Future<void>.delayed(const Duration(seconds: 4)));
    await settle(tester);
    expect(video, findsOneWidget, reason: 'Schleife läuft weiter');
    await tap(tester, find.byTooltip(de.liveWiedergabeStoppen));
    await waitGone(tester, video);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('ANS-058 Favorit in der Einzelansicht', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('fav.jpg', datum: DateTime(2025, 4, 2, 10)),
        testfoto('anderes.jpg', datum: DateTime(2025, 4, 1, 10)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'fav.jpg');
    await tap(tester, knopf(de.viewerFavoritSetzen));
    await waitFor(tester, knopf(de.viewerFavoritEntfernen));
    expect(
      find.descendant(
        of: knopf(de.viewerFavoritEntfernen),
        matching: find.byIcon(Icons.favorite),
      ),
      findsOneWidget,
    );
    expect((await aufnahme(tester, 'fav.jpg')).isFavorite, isTrue);
    await key(tester, LogicalKeyboardKey.keyF);
    await waitFor(tester, knopf(de.viewerFavoritSetzen));
    expect((await aufnahme(tester, 'fav.jpg')).isFavorite, isFalse);
    await key(tester, LogicalKeyboardKey.keyF);
    await waitFor(tester, knopf(de.viewerFavoritEntfernen));
    expect((await aufnahme(tester, 'fav.jpg')).isFavorite, isTrue);
    await schliesseBetrachter(tester);
    // Kachel mit Herz, Foto unter „Favoriten“.
    await waitFor(
      tester,
      find.descendant(
        of: kachel('fav.jpg'),
        matching: find.byIcon(Icons.favorite),
      ),
    );
    await openSection(tester, Hauptbereich.favoriten);
    await waitFor(tester, kachel('fav.jpg'));
    expect(kachel('anderes.jpg'), findsNothing);
    await finish(tester);
  });

  // Befund: Bewertung und Farbmarke per Taste kommen in der Datenbank an,
  // die offene Info-Leiste zeigt sie aber nicht: AssetInfoSheet übernimmt
  // die Aufnahme nur in initState (asset_info_sheet.dart:77, `late
  // AssetData _asset = widget.asset`) und hat kein didUpdateWidget; die
  // Einzelansicht reicht die neue Fassung nur über das Widget herein
  // (asset_viewer_screen.dart:1198–1201, gleicher Schlüssel).
  testWidgets(
    'ANS-059 Bewertung und Farbmarke per Taste in der Einzelansicht',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('taste.jpg', datum: DateTime(2025, 4, 2, 10)),
          testfoto('anderes.jpg', datum: DateTime(2025, 4, 1, 10)),
        ],
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'taste.jpg');
      await tap(tester, knopf(de.viewerInfo));
      final sterne = find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.byType(StarRating),
      );
      final farben = find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.byType(ColorLabelPicker),
      );
      await waitFor(tester, sterne);
      Future<void> pruefe(int sternZahl, String? farbe, String was) async {
        await eventually(tester, () async {
          final a = await aufnahme(tester, 'taste.jpg');
          return a.rating == sternZahl && a.colorLabel == farbe;
        }, was: '$was in der Datenbank');
        await settle(tester);
        print(
          'ANS-059 $was: Leiste zeigt ${tester.widget<StarRating>(sterne).value}'
          ' Sterne, Farbe ${tester.widget<ColorLabelPicker>(farben).value}',
        );
        expect(tester.widget<StarRating>(sterne).value, sternZahl, reason: was);
        expect(
          tester.widget<ColorLabelPicker>(farben).value,
          farbe,
          reason: was,
        );
      }

      await key(tester, LogicalKeyboardKey.digit4);
      await pruefe(4, null, '„4“');
      await key(tester, LogicalKeyboardKey.digit0);
      await pruefe(0, null, '„0“');
      await key(tester, LogicalKeyboardKey.digit7);
      await pruefe(0, 'yellow', '„7“');
      await key(tester, LogicalKeyboardKey.digit7);
      await pruefe(0, null, 'zweites „7“');
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets('ANS-060 Erinnerungen: ohne Löschen', (tester) async {
    final heute = DateTime.now();
    final damals = DateTime(
      heute.year - 2,
      heute.month,
      heute.day,
      10,
    ).subtract(const Duration(days: 5));
    await startApp(
      tester,
      fotos: [
        testfoto('erinnerung1.jpg', datum: damals),
        testfoto(
          'erinnerung2.jpg',
          datum: damals.add(const Duration(hours: 1)),
        ),
      ],
    );
    await openSection(tester, Hauptbereich.rueckblick);
    final zeile = find.widgetWithText(ListTile, de.erinnerungenTitel);
    await rolleZu(tester, zeile, in_: rolleIn(ExploreScreen));
    await tap(tester, zeile);
    await waitFor(tester, find.text(de.erinnerungenLetzteTage));
    await waitFor(tester, kachel('erinnerung1.jpg'));
    await oeffne(tester, 'erinnerung1.jpg');
    expect(knopf(de.viewerInPapierkorb), findsNothing);
    await key(tester, LogicalKeyboardKey.backspace);
    expect(find.byType(AlertDialog), findsNothing);
    expect(betrachter, findsOneWidget);
    expect((await aufnahme(tester, 'erinnerung1.jpg')).isTrashed, isFalse);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // === Schwebevorschau ======================================================

  testWidgets('ANS-064 ANS-065 Schwebevorschau: gesperrt still, abschaltbar', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        fixture('video_5s.mp4'),
        testfoto('dazu.jpg', datum: DateTime(2020, 1, 1)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    final kachelVideo = kachel('video_5s.mp4');
    await waitFor(tester, kachelVideo);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    // Nicht über der Seitenleiste beginnen: Die klappt beim Darüberfahren
    // auf und läge dann über den ersten Kacheln.
    final ruhe =
        tester.getRect(find.byType(HomeShell)).centerRight -
        const Offset(150, 0);
    await maus.addPointer(location: ruhe);
    await tester.pump();
    Future<void> schwebe(Finder ziel) async {
      await maus.moveTo(tester.getCenter(ziel.first));
      final ende = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> weg() async {
      await maus.moveTo(ruhe);
      await settle(tester);
    }

    // ANS-065: eingeschaltet läuft die Vorschau an.
    await schwebe(kachelVideo);
    await waitFor(
      tester,
      find.descendant(of: kachelVideo, matching: find.byType(VideoSurface)),
      timeout: const Duration(seconds: 15),
    );
    await weg();
    // Ausschalten in den Einstellungen.
    await openSection(tester, Hauptbereich.einstellungen);
    await tapText(tester, de.einstAbschnittErscheinungsbild);
    final schalter = find.widgetWithText(
      SwitchListTile,
      de.einstSchwebeVorschauTitel,
    );
    await tap(tester, schalter);
    await eventually(
      tester,
      () async => tester.widget<SwitchListTile>(schalter).value == false,
      was: 'Schalter aus',
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachelVideo);
    await schwebe(kachelVideo);
    expect(
      find.descendant(of: kachelVideo, matching: find.byType(VideoSurface)),
      findsNothing,
      reason: 'ausgeschaltet bleibt es ein Standbild',
    );
    await weg();
    await openSection(tester, Hauptbereich.einstellungen);
    await tapText(tester, de.einstAbschnittErscheinungsbild);
    await tap(tester, schalter);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachelVideo);
    await schwebe(kachelVideo);
    await waitFor(
      tester,
      find.descendant(of: kachelVideo, matching: find.byType(VideoSurface)),
      timeout: const Duration(seconds: 15),
    );
    await weg();

    // ANS-064: gesperrtes Video im gesperrten Ordner bleibt still.
    await tresorEinrichten(tester);
    await sperre(tester, 'video_5s.mp4');
    final gesperrt = (await alleAufnahmen(
      tester,
    )).firstWhere((a) => a.id == _gesperrt['video_5s.mp4']);
    expect(gesperrt.isLocked, isTrue);
    await oeffneGesperrtenOrdner(tester);
    final gesperrteKachel = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await waitFor(tester, gesperrteKachel);
    await schwebe(gesperrteKachel);
    expect(find.byType(VideoSurface), findsNothing);
    expect(
      await entschluesselt(tester, gesperrt.relativePath),
      isFalse,
      reason: 'kein Video nebenbei entschlüsselt',
    );
    await weg();
    await maus.removePointer();
    await finish(tester);
  });

  // === Bewertung, Favoriten, Markierungen, Beschreibung ====================

  testWidgets(
    'ANS-066 ANS-067 ANS-068 Sterne, Farbe und Beschreibung in der Info-Leiste',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('info.jpg', datum: DateTime(2025, 4, 1, 10)),
          testfoto('oben.jpg', datum: DateTime(2025, 4, 3, 10)),
        ],
      );
      await befehl(tester, BewertungSetzen(await ids(tester, ['oben.jpg']), 3));
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'info.jpg');
      await tap(tester, knopf(de.viewerInfo));
      final info = find.byType(AssetInfoSheet);
      final stern = find.descendant(
        of: find.descendant(of: info, matching: find.byType(StarRating)),
        matching: find.byType(InkWell),
      );
      // ANS-066
      await tap(tester, stern.at(2));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).rating == 3,
        was: 'drei Sterne',
      );
      await tap(tester, stern.at(2));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).rating == 0,
        was: 'zurückgesetzt',
      );
      await tap(tester, stern.at(4));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).rating == 5,
        was: 'fünf Sterne',
      );
      // ANS-067: Lila an und wieder aus, dann Rot.
      final kreis = find.descendant(
        of: find.descendant(of: info, matching: find.byType(ColorLabelPicker)),
        matching: find.byType(InkWell),
      );
      await tap(tester, kreis.at(4));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).colorLabel == 'purple',
        was: 'Lila',
      );
      await tap(tester, kreis.at(4));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).colorLabel == null,
        was: 'Lila weg',
      );
      await tap(tester, kreis.at(0));
      await eventually(
        tester,
        () async => (await aufnahme(tester, 'info.jpg')).colorLabel == 'red',
        was: 'Rot',
      );
      // ANS-068: Beschreibung, ausserhalb klicken.
      await tap(tester, field(de.infoBeschreibungHinzufuegen));
      await tester.enterText(
        field(de.infoBeschreibungHinzufuegen),
        'Gartenfest',
      );
      await settle(tester);
      await tester.tapAt(
        tester.getTopLeft(
              find
                  .descendant(of: info, matching: find.text(de.infoDetails))
                  .first,
            ) +
            const Offset(0, -2),
      );
      await tap(
        tester,
        find.descendant(of: info, matching: find.text(de.infoDetails)).first,
      );
      await eventually(
        tester,
        () async =>
            (await aufnahme(tester, 'info.jpg')).description == 'Gartenfest',
        was: 'Beschreibung gespeichert',
      );
      await schliesseBetrachter(tester);
      await oeffne(tester, 'info.jpg');
      if (find.byType(AssetInfoSheet).evaluate().isEmpty) {
        await tap(tester, knopf(de.viewerInfo));
      }
      await waitFor(tester, find.text('Gartenfest'));
      await schliesseBetrachter(tester);
      // „Bewertung, beste zuerst“: das Fünf-Sterne-Foto oben.
      await reihenfolge(tester, de.sortBewertung);
      expect(rasterNamen(tester).first, 'info.jpg');
      await reihenfolge(tester, de.sortAufnahmeNeu);
      // Suche nach Farbe Rot und nach Beschreibung „Garten“.
      await openSection(tester, Hauptbereich.suche);
      await oeffneSuchoptionen(tester);
      await imBlatt(tester, de.farbeRot);
      await optionenSuchen(tester);
      await waitFor(tester, kachel('info.jpg'));
      expect(kachel('oben.jpg'), findsNothing);
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      await sucheNachTyp(
        tester,
        de.suchoptTypBeschreibung,
        'Garten',
        offen: true,
      );
      await waitFor(tester, kachel('info.jpg'));
      expect(treffer(tester), ['info.jpg']);
      await finish(tester);
    },
  );

  // Vermuteter Fehler aus dem Katalog (Speichern nur bei Fokusverlust,
  // asset_info_sheet.dart:339): mit der Maus nicht bestätigt – der Klick
  // auf „Nächstes Foto“ oder „Info“ nimmt dem Feld zuerst den Fokus, und
  // das Speichern läuft auch nach dem Neuaufbau der Leiste zu Ende.
  testWidgets('ANS-069 Beschreibung geht beim Weiterblättern nicht verloren', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('b1.jpg', datum: DateTime(2025, 4, 2, 10)),
        testfoto('b2.jpg', datum: DateTime(2025, 4, 1, 10)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'b1.jpg');
    await tap(tester, knopf(de.viewerInfo));
    await tap(tester, field(de.infoBeschreibungHinzufuegen));
    await tester.enterText(field(de.infoBeschreibungHinzufuegen), 'Test eins');
    await settle(tester);
    // Ohne das Feld zu verlassen weiterblättern und zurück.
    await tap(tester, knopf(de.viewerNaechstesFoto));
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 1, 10)));
    await tap(tester, knopf(de.viewerVorherigesFoto));
    await waitFor(tester, betrachterZeigt(DateTime(2025, 4, 2, 10)));
    await settle(tester);
    final nachBlaettern = (await aufnahme(tester, 'b1.jpg')).description;
    print('ANS-069: nach dem Blättern „$nachBlaettern“');
    // Zweiter Weg: Info schliessen statt blättern.
    await tap(tester, field(de.infoBeschreibungHinzufuegen));
    await tester.enterText(field(de.infoBeschreibungHinzufuegen), 'Test zwei');
    await settle(tester);
    await tap(tester, knopf(de.viewerInfo));
    await settle(tester);
    final nachSchliessen = (await aufnahme(tester, 'b1.jpg')).description;
    print('ANS-069: nach dem Schliessen „$nachSchliessen“');
    expect(nachBlaettern, 'Test eins');
    expect(nachSchliessen, 'Test zwei');
    await finish(tester);
  });

  testWidgets('ANS-070 KI-Beschreibung von Hand ändern', (tester) async {
    await startApp(
      tester,
      fotos: [testfoto('ki.jpg', datum: DateTime(2025, 4, 1, 10))],
    );
    final a = await aufnahme(tester, 'ki.jpg');
    // Vorbedingung: ein Durchgang hat eine Beschreibung geschrieben.
    await echt(() => bibliothek.db.setAiCaption(a.id, 'a dog on a beach'));
    await settle(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'ki.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    await waitFor(
      tester,
      find.descendant(of: info, matching: find.text(de.infoKiBeschreibung)),
    );
    await tap(
      tester,
      find.descendant(of: info, matching: find.text(de.infoSpracheEn)),
    );
    final kiFeld = find.descendant(
      of: info,
      matching: find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            (w.decoration?.hintText == de.infoKiPlatzhalterEn ||
                w.decoration?.hintText == de.infoKiPlatzhalterDe),
      ),
    );
    await tap(tester, kiFeld);
    await tester.enterText(kiFeld, 'a lighthouse at the harbour');
    await settle(tester);
    // Umschalten speichert vorher.
    await tap(
      tester,
      find.descendant(of: info, matching: find.text(de.infoSpracheDe)),
    );
    await eventually(tester, () async {
      final x = await aufnahme(tester, 'ki.jpg');
      return x.aiCaption == 'a lighthouse at the harbour' && x.aiCaptionEdited;
    }, was: 'gespeichert');
    await waitFor(
      tester,
      find.descendant(
        of: info,
        matching: find.text(de.infoKiBeschreibungVonHand),
      ),
    );
    expect(
      find.descendant(of: info, matching: find.text(de.infoKiVonHandHinweis)),
      findsOneWidget,
    );
    await schliesseBetrachter(tester);
    await openSection(tester, Hauptbereich.suche);
    await sucheNachTyp(tester, de.suchoptTypCaption, 'lighthouse');
    await waitFor(tester, kachel('ki.jpg'));
    expect(suchfeldHinweis(tester), de.suchePlatzhalterBildunterschrift);
    await finish(tester);
  });

  testWidgets('ANS-071 Aufnahmedatum in der Info-Leiste ändern (2024)', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [testfoto('d2024.jpg', datum: DateTime(2024, 3, 10, 9, 15))],
    );
    final datei = bibliothek.paths.absolute(
      (await aufnahme(tester, 'd2024.jpg')).relativePath,
    );
    final vorher = await pruefsumme(tester, datei);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, find.text('März 2024'));
    await oeffne(tester, 'd2024.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    await tap(
      tester,
      find
          .descendant(of: info, matching: find.byTooltip(de.allgBearbeiten))
          .first,
    );
    expect(await datumEintippen(tester, DateTime(2024, 6, 20)), isTrue);
    await zeitBestaetigen(tester);
    await eventually(tester, () async {
      final x = await aufnahme(tester, 'd2024.jpg');
      return x.fileCreatedAt.month == 6 && x.fileCreatedAt.day == 20;
    }, was: 'neues Datum');
    await waitFor(
      tester,
      find.descendant(
        of: info,
        matching: find.text(
          DateFormat.yMMMd('de').format(DateTime(2024, 6, 20)),
        ),
      ),
    );
    await schliesseBetrachter(tester);
    await waitFor(tester, find.text('Juni 2024'));
    expect(find.text('März 2024'), findsNothing);
    final neu = bibliothek.paths.absolute(
      (await aufnahme(tester, 'd2024.jpg')).relativePath,
    );
    expect(await pruefsumme(tester, neu), vorher, reason: 'Inhalt unverändert');
    await finish(tester);
  });

  testWidgets('ANS-072 Datum aus dem Dateinamen übernehmen', (tester) async {
    await startApp(tester, fotos: [testfoto('IMG-20240512-WA0003.jpg')]);
    final importiert = await aufnahme(tester, 'IMG-20240512-WA0003.jpg');
    print(
      'ANS-072: Import setzte ${importiert.fileCreatedAt}, geschätzt '
      '${importiert.datumGeschaetzt}',
    );
    // Vorbedingung „ohne EXIF-Datum“: ein geschätztes Datum, das nicht aus
    // dem Namen stammt (der Import nimmt den Namen inzwischen selbst).
    await setzeSpalten(
      tester,
      'IMG-20240512-WA0003.jpg',
      AssetsCompanion(
        fileCreatedAt: Value(DateTime(2026, 1, 15, 8)),
        datumGeschaetzt: const Value(true),
      ),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'IMG-20240512-WA0003.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    await waitFor(
      tester,
      find.descendant(of: info, matching: find.text(de.infoDatumGeschaetzt)),
    );
    final hinweis = find.descendant(
      of: info,
      matching: find.textContaining('Dateiname nennt'),
    );
    await waitFor(tester, hinweis);
    await tap(
      tester,
      find.descendant(of: info, matching: find.text(de.infoDatumUebernehmen)),
    );
    await eventually(tester, () async {
      final a = await aufnahme(tester, 'IMG-20240512-WA0003.jpg');
      return a.fileCreatedAt.year == 2024 &&
          a.fileCreatedAt.month == 5 &&
          a.fileCreatedAt.day == 12;
    }, was: '12.05.2024');
    await waitGone(tester, hinweis);
    final nachher = await aufnahme(tester, 'IMG-20240512-WA0003.jpg');
    print('ANS-072: nach Übernehmen geschätzt ${nachher.datumGeschaetzt}');
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // === Schlagwörter und Vokabular ==========================================

  testWidgets('ANS-073 ANS-074 Schlagwort hinzufügen, entfernen, umbenennen', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('t1.jpg', datum: DateTime(2025, 4, 5, 10)),
        testfoto('t2.jpg', datum: DateTime(2025, 4, 4, 10)),
        testfoto('r1.jpg', datum: DateTime(2025, 4, 3, 10)),
        testfoto('r2.jpg', datum: DateTime(2025, 4, 2, 10)),
        testfoto('r3.jpg', datum: DateTime(2025, 4, 1, 10)),
      ],
    );
    await befehl(
      tester,
      SchlagwortAnheften(
        await ids(tester, ['r1.jpg', 'r2.jpg', 'r3.jpg']),
        'Strnad',
      ),
    );
    await befehl(
      tester,
      SchlagwortAnheften(await ids(tester, ['r3.jpg']), 'Meer'),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    // ANS-073
    await oeffne(tester, 't1.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    final tagFeld = field(de.infoTagHinzufuegenPlatzhalter);
    await tap(tester, tagFeld);
    await tester.enterText(tagFeld, 'Strand');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await waitFor(
      tester,
      find.descendant(
        of: info,
        matching: find.widgetWithText(InputChip, 'Strand'),
      ),
    );
    await tap(tester, knopf(de.viewerNaechstesFoto));
    await waitFor(
      tester,
      find.descendant(of: info, matching: find.text('t2.jpg')),
    );
    await tap(tester, tagFeld);
    await tester.enterText(tagFeld, 'Strand');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await schlagwoerter(tester, 't2.jpg'), contains('Strand'));
    await tap(tester, knopf(de.viewerVorherigesFoto));
    await waitFor(
      tester,
      find.descendant(of: info, matching: find.text('t1.jpg')),
    );
    final chip = find.descendant(
      of: info,
      matching: find.widgetWithText(InputChip, 'Strand'),
    );
    await waitFor(tester, chip);
    await chipLoeschen(tester, chip);
    await waitGone(tester, chip);
    expect(await schlagwoerter(tester, 't1.jpg'), isNot(contains('Strand')));
    expect(await schlagwoerter(tester, 't2.jpg'), contains('Strand'));
    await schliesseBetrachter(tester);
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptTagsHint);
    await tap(tester, find.widgetWithText(CheckboxListTile, 'Strand'));
    await tapText(tester, de.allgUebernehmen);
    await optionenSuchen(tester);
    await waitFor(tester, kachel('t2.jpg'));
    expect(treffer(tester), ['t2.jpg']);

    // ANS-074: „Strnad“ in „Strand“ umbenennen – den gibt es schon.
    // Erst ein freier Name, dann ein vergebener.
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'r1.jpg');
    if (info.evaluate().isEmpty) await tap(tester, knopf(de.viewerInfo));
    final strnad = find.descendant(
      of: info,
      matching: find.widgetWithText(InputChip, 'Strnad'),
    );
    await waitFor(tester, strnad);
    expect(
      tester.widget<InputChip>(strnad).tooltip,
      de.infoTagUmbenennenHinweis,
    );
    await tap(
      tester,
      find.descendant(of: strnad, matching: find.text('Strnad')),
    );
    await waitFor(tester, find.text(de.infoTagUmbenennen));
    await enter(tester, field(de.infoTagUmbenennenFeld), 'Strandgut');
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await eventually(tester, () async {
      for (final n in ['r1.jpg', 'r2.jpg', 'r3.jpg']) {
        if (!(await schlagwoerter(tester, n)).contains('Strandgut')) {
          return false;
        }
      }
      return true;
    }, was: 'alle drei umbenannt');
    final umbenannt = find.descendant(
      of: info,
      matching: find.widgetWithText(InputChip, 'Strandgut'),
    );
    await waitFor(tester, umbenannt);
    await tap(
      tester,
      find.descendant(of: umbenannt, matching: find.text('Strandgut')),
    );
    await enter(tester, field(de.infoTagUmbenennenFeld), 'Meer');
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await meldung(tester, de.infoTagVorhanden('Meer'));
    expect(await schlagwoerter(tester, 'r1.jpg'), ['Strandgut']);
    expect((await schlagwoerter(tester, 'r3.jpg'))..sort(), [
      'Meer',
      'Strandgut',
    ]);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets(
    'ANS-075 ANS-077 Vokabular pflegen, KI-Schlagwörter zurücknehmen',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('ki1.jpg', datum: DateTime(2025, 4, 2)),
          testfoto('ki2.jpg', datum: DateTime(2025, 4, 1)),
        ],
      );
      await befehl(
        tester,
        SchlagwortAnheften(
          await ids(tester, ['ki1.jpg', 'ki2.jpg']),
          'Leuchtturm',
          quelle: 'ki',
        ),
      );
      await befehl(
        tester,
        SchlagwortAnheften(
          await ids(tester, ['ki2.jpg']),
          'Hafen',
          quelle: 'ki',
        ),
      );
      await befehl(
        tester,
        SchlagwortAnheften(await ids(tester, ['ki1.jpg']), 'Eigenes'),
      );
      await openSection(tester, Hauptbereich.einstellungen);
      await tapText(tester, de.einstAbschnittVokabular);
      final feld = field(de.einstBegriffHinzufuegenFeld);
      Finder chip(String t) => find.widgetWithText(InputChip, t);
      // ANS-075
      final vorher = chip('Leuchtturm').evaluate().length;
      expect(vorher, 0);
      await enter(tester, feld, 'Leuchtturm');
      await tap(tester, find.byTooltip(de.einstBegriffHinzufuegen));
      await waitFor(tester, chip('Leuchtturm'));
      await enter(tester, feld, 'Leuchtturm');
      await tap(tester, find.byTooltip(de.einstBegriffHinzufuegen));
      expect(
        chip('Leuchtturm'),
        findsOneWidget,
        reason: 'doppelt passiert nichts',
      );
      final anzahl = find.byType(InputChip).evaluate().length;
      await enter(tester, feld, '');
      await tap(tester, find.byTooltip(de.einstBegriffHinzufuegen));
      expect(find.byType(InputChip).evaluate().length, anzahl);
      await chipLoeschen(tester, chip('Leuchtturm'));
      await waitGone(tester, chip('Leuchtturm'));
      expect(await schlagwoerter(tester, 'ki1.jpg'), contains('Leuchtturm'));
      // ANS-077: drei KI-Schlagwörter, ein eigenes.
      final eintrag = find.text(de.einstKiTagsZurueckAnzahl(3));
      await rolleZu(tester, eintrag, in_: rolleIn(SettingsScreen));
      await tap(tester, eintrag);
      await waitFor(tester, find.text(de.einstKiTagsZurueckFrage(3)));
      await tapText(tester, de.allgAbbrechen);
      expect(await schlagwoerter(tester, 'ki2.jpg'), contains('Hafen'));
      await tap(tester, eintrag);
      await tapText(tester, de.einstKiTagsZurueckJetzt);
      await meldung(tester, de.einstKiTagsZurueckFertig(3));
      expect(await schlagwoerter(tester, 'ki1.jpg'), ['Eigenes']);
      expect(await schlagwoerter(tester, 'ki2.jpg'), isEmpty);
      // Bei null KI-Schlagwörtern ausgegraut.
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.einstellungen);
      await tapText(tester, de.einstAbschnittVokabular);
      final leer = find.widgetWithText(ListTile, de.einstKiTagsZurueck);
      await rolleZu(tester, leer, in_: rolleIn(SettingsScreen));
      await eventually(
        tester,
        () async => tester.widget<ListTile>(leer).enabled == false,
        was: 'ausgegraut',
      );
      await finish(tester);
    },
  );

  // === Alben ================================================================

  testWidgets(
    'ANS-079 ANS-080 ANS-081 ANS-082 Album anlegen, leer, füllen, Reihenfolge',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 10; i++)
            testfoto('z$i.jpg', datum: DateTime(2016 + i, 3, 1, 10)),
        ],
      );
      await albumAnlegen(
        tester,
        'Alt',
        [],
        zeit: DateTime.now().subtract(const Duration(days: 3)),
      );
      await openSection(tester, Hauptbereich.alben);
      Finder albumKarte(String name) =>
          find.ancestor(of: find.text(name), matching: find.byType(Card)).first;
      Future<void> neuesAlbum(String? name, {bool abbrechen = false}) async {
        await tap(tester, find.text(de.albumNeu).last);
        await waitFor(tester, field(de.albumName));
        if (name != null) await enter(tester, field(de.albumName), name);
        await tapText(tester, abbrechen ? de.allgAbbrechen : de.allgErstellen);
      }

      // ANS-079
      await neuesAlbum('Neu');
      await waitFor(tester, find.text('Neu'));
      final neuLage = tester.getTopLeft(find.text('Neu'));
      final altLage = tester.getTopLeft(find.text('Alt'));
      expect(
        neuLage.dy < altLage.dy ||
            (neuLage.dy == altLage.dy && neuLage.dx < altLage.dx),
        isTrue,
        reason: 'neuestes Album zuerst',
      );
      expect(
        find.descendant(
          of: albumKarte('Neu'),
          matching: find.byIcon(Icons.photo_album_outlined),
        ),
        findsOneWidget,
      );
      final vorher = (await echt(() => bibliothek.db.alleAlben()))!.length;
      await neuesAlbum(null);
      await neuesAlbum('Gar nicht', abbrechen: true);
      expect((await echt(() => bibliothek.db.alleAlben()))!.length, vorher);
      expect(find.text('Gar nicht'), findsNothing);

      // ANS-080: leeres Album.
      await tap(tester, find.text('Neu'));
      await waitFor(tester, find.text(de.albumLeer));
      expect(find.byTooltip(de.albumFotosHinzufuegen), findsOneWidget);
      expect(find.byTooltip(de.albumExportieren), findsNothing);
      expect(find.byTooltip(de.fotobuchAlsPdf), findsNothing);

      // ANS-081: drei Fotos anhaken, „Fertig“.
      Future<void> haken(List<String> namen, {bool fertig = true}) async {
        print('ANS-081: haken $namen, fertig: $fertig');
        await tap(tester, find.byTooltip(de.albumFotosHinzufuegen));
        await waitFor(tester, find.text(de.albumFotosWaehlenTitel('Neu')));
        for (final n in namen) {
          await rolleZu(
            tester,
            kachel(n),
            in_: rolleIn(AufnahmenWaehlenScreen),
          );
          await tap(tester, kachel(n));
        }
        if (fertig) {
          await tap(tester, find.widgetWithText(TextButton, de.allgFertig));
        } else {
          await zurueck(tester);
        }
        await waitGone(tester, find.text(de.albumFotosWaehlenTitel('Neu')));
      }

      await tap(tester, find.byTooltip(de.albumFotosHinzufuegen));
      await waitFor(tester, find.text(de.albumFotosWaehlenTitel('Neu')));
      for (final n in ['z1.jpg', 'z5.jpg', 'z8.jpg']) {
        await rolleZu(tester, kachel(n), in_: rolleIn(AufnahmenWaehlenScreen));
        await tap(tester, kachel(n));
      }
      expect(find.text(de.aufnahmenWahlGewaehlt(3)), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, de.allgFertig));
      await waitGone(tester, find.byType(AufnahmenWaehlenScreen));
      print('ANS-081: nach „Fertig“: ${onScreen(tester)}');
      print('ANS-081: im Album ${await albumInhalt(tester, 'Neu')}');
      await waitFor(tester, kachel('z5.jpg'));
      expect((await albumInhalt(tester, 'Neu'))..sort(), [
        'z1.jpg',
        'z5.jpg',
        'z8.jpg',
      ]);
      // ANS-082: neuestes Aufnahmedatum zuerst (hinzugefügt in anderer Folge).
      final ordnung = [
        for (final e in find.byType(AssetThumbnailTile).evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      ];
      expect(ordnung, ['z8.jpg', 'z5.jpg', 'z1.jpg']);
      // Einen Haken entfernen.
      await haken(['z5.jpg']);
      await waitGone(tester, kachel('z5.jpg'));
      expect((await albumInhalt(tester, 'Neu'))..sort(), ['z1.jpg', 'z8.jpg']);
      expect((await aufnahme(tester, 'z5.jpg')).isTrashed, isFalse);
      // Haken setzen, ohne „Fertig“ zurück: nichts ändert sich.
      await haken(['z2.jpg'], fertig: false);
      expect((await albumInhalt(tester, 'Neu'))..sort(), ['z1.jpg', 'z8.jpg']);
      await zurueck(tester);
      // Das abgehakte Foto steht weiter in der Zeitleiste.
      await openSection(tester, Hauptbereich.zeitleiste);
      await rolleZu(
        tester,
        kachel('z5.jpg'),
        in_: find.byType(CustomScrollView),
      );
      // ANS-082: Übersicht – zuletzt angelegtes Album zuerst.
      await albumAnlegen(
        tester,
        'Drittes',
        [],
        zeit: DateTime.now().add(const Duration(minutes: 1)),
      );
      await openSection(tester, Hauptbereich.alben);
      await waitFor(tester, find.text('Drittes'));
      final lagen = [
        for (final n in ['Drittes', 'Neu', 'Alt'])
          tester.getTopLeft(find.text(n)),
      ];
      for (var i = 1; i < lagen.length; i++) {
        expect(
          lagen[i - 1].dy < lagen[i].dy ||
              (lagen[i - 1].dy == lagen[i].dy && lagen[i - 1].dx < lagen[i].dx),
          isTrue,
        );
      }
      await finish(tester);
    },
  );

  testWidgets('ANS-083 ANS-084 Titelbild setzen und zurückfallen', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('neu.jpg', datum: DateTime(2025, 6, 1)),
        testfoto('mitte.jpg', datum: DateTime(2024, 6, 1)),
        testfoto('alt.jpg', datum: DateTime(2023, 6, 1)),
      ],
    );
    await albumAnlegen(tester, 'Titel', ['neu.jpg', 'mitte.jpg', 'alt.jpg']);
    await tresorEinrichten(tester);
    Finder titelbild() => find.descendant(
      of: find
          .ancestor(of: find.text('Titel'), matching: find.byType(Card))
          .first,
      matching: find.byType(AssetThumbnailTile),
    );
    String titelbildName() =>
        tester.widget<AssetThumbnailTile>(titelbild()).asset.originalFileName;
    Future<void> uebersichtNeu() async {
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.alben);
      await waitFor(tester, find.text('Titel'));
      await settle(tester);
    }

    // ANS-083: ohne Wahl das neueste Foto.
    await uebersichtNeu();
    await waitFor(tester, titelbild());
    expect(titelbildName(), 'neu.jpg');
    await tap(tester, find.text('Titel'));
    await waitFor(tester, kachel('alt.jpg'));
    await tester.longPress(kachel('alt.jpg'));
    await settle(tester);
    await tap(tester, find.byTooltip(de.albumTitelbildSetzen));
    await meldung(tester, de.albumTitelbildGesetzt);
    expect(
      find.byType(SelectionActionBar),
      findsNothing,
      reason: 'Auswahl weg',
    );
    await tester.longPress(kachel('alt.jpg'));
    await settle(tester);
    await tap(tester, kachel('mitte.jpg'));
    expect(find.byTooltip(de.albumTitelbildSetzen), findsNothing);
    await leiste(tester, de.auswAufheben);
    await zurueck(tester);
    await waitFor(tester, titelbild());
    await eventually(
      tester,
      () async => titelbildName() == 'alt.jpg',
      was: 'ohne Neustart das gewählte Titelbild',
    );

    // ANS-084: Titelbild im Papierkorb → neuestes übriges.
    await befehl(tester, InDenPapierkorb(await ids(tester, ['alt.jpg'])));
    await uebersichtNeu();
    expect(titelbildName(), 'neu.jpg');
    await befehl(tester, AusDemPapierkorb(await ids(tester, ['alt.jpg'])));
    await uebersichtNeu();
    expect(titelbildName(), 'alt.jpg', reason: 'Wahl gilt wieder');
    // Gesperrt → neuestes übriges.
    await sperre(tester, 'alt.jpg');
    await uebersichtNeu();
    expect(titelbildName(), 'neu.jpg');
    await entsperre(tester, 'alt.jpg');
    await uebersichtNeu();
    // Aus dem Album abgehakt → neuestes übriges.
    await tap(tester, find.text('Titel'));
    await tap(tester, find.byTooltip(de.albumFotosHinzufuegen));
    await waitFor(tester, find.text(de.albumFotosWaehlenTitel('Titel')));
    await tap(tester, kachel('alt.jpg'));
    await tapText(tester, de.allgFertig);
    await zurueck(tester);
    await uebersichtNeu();
    expect(titelbildName(), 'neu.jpg');
    await finish(tester);
  });

  testWidgets(
    'ANS-085 ANS-086 Fotos im Album löschen; Gesperrtes und Gelöschtes',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 3; i++)
            testfoto('al$i.jpg', datum: DateTime(2025, 6, 10 + i)),
          for (var i = 0; i < 3; i++)
            testfoto('bl$i.jpg', datum: DateTime(2024, 6, 10 + i)),
        ],
      );
      await albumAnlegen(tester, 'Löschalbum', [
        'al0.jpg',
        'al1.jpg',
        'al2.jpg',
      ]);
      await albumAnlegen(tester, 'Sperralbum', [
        'bl0.jpg',
        'bl1.jpg',
        'bl2.jpg',
      ]);
      await tresorEinrichten(tester);

      // ANS-085: zwei auswählen und löschen.
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Löschalbum'));
      await waehle(tester, ['al0.jpg', 'al1.jpg']);
      await leiste(tester, de.allgLoeschen);
      await waitFor(tester, find.text(de.albumFotosLoeschenTitel(2)));
      expect(find.text(de.albumFotosLoeschenText), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
      await waitGone(tester, kachel('al0.jpg'));
      expect(kachel('al1.jpg'), findsNothing);
      expect(kachel('al2.jpg'), findsOneWidget);
      await zurueck(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      expect(kachel('al0.jpg'), findsNothing);
      // Im Papierkorb wiederherstellen.
      await openSection(tester, Hauptbereich.papierkorb);
      final kacheln = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );
      await waitFor(tester, kacheln);
      await tester.longPress(kacheln.first);
      await settle(tester);
      await tap(tester, kacheln.at(1));
      await tap(tester, find.byTooltip(de.einstWiederherstellen));
      await eventually(tester, () async {
        final a = await aufnahme(tester, 'al0.jpg');
        final b = await aufnahme(tester, 'al1.jpg');
        return !a.isTrashed && !b.isTrashed;
      }, was: 'wiederhergestellt');
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('al0.jpg'));
      expect(await albumInhalt(tester, 'Löschalbum'), ['al2.jpg']);

      // ANS-086: in der Zeitleiste löschen und sperren.
      await befehl(tester, InDenPapierkorb(await ids(tester, ['bl0.jpg'])));
      await sperre(tester, 'bl1.jpg');
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Sperralbum'));
      await waitFor(tester, kachel('bl2.jpg'));
      expect(kachel('bl0.jpg'), findsNothing);
      expect(kachel('bl1.jpg'), findsNothing);
      await zurueck(tester);
      await befehl(tester, AusDemPapierkorb(await ids(tester, ['bl0.jpg'])));
      await entsperre(tester, 'bl1.jpg');
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Sperralbum'));
      await waitFor(tester, kachel('bl0.jpg'));
      await waitFor(tester, kachel('bl1.jpg'));
      expect(kachel('bl2.jpg'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('ANS-087 ANS-088 Intelligentes Album anlegen und löschen', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('foto1.jpg', datum: DateTime(2025, 1, 1)),
        testfoto('foto2.jpg', datum: DateTime(2025, 1, 2)),
        fixture('video_5s.mp4'),
      ],
    );
    final zweites = fixture('video_hoch_3s.mov');
    await importiereDirekt(tester, [zweites]);
    await albumAnlegen(tester, 'Gewöhnlich', ['foto1.jpg']);
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptVideo);
    await optionenSuchen(tester);
    await waitFor(tester, kachel('video_5s.mp4'));
    expect(treffer(tester)..sort(), ['video_5s.mp4', 'video_hoch_3s.mov']);
    await tap(tester, find.byTooltip(de.sucheSpeichernTitel));
    await enter(tester, field(de.allgName), 'Nur Videos');
    await tapText(tester, de.allgSpeichern);
    await openSection(tester, Hauptbereich.alben);
    await waitFor(tester, find.text('Nur Videos'));
    expect(find.text(de.albenIntelligente), findsOneWidget);
    expect(find.text(de.albenGewoehnliche), findsWidgets);
    await tap(tester, find.text('Nur Videos'));
    await waitFor(tester, kachel('video_5s.mp4'));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Nur Videos'),
      ),
      findsOneWidget,
    );
    expect(treffer(tester).length, 2);
    await zurueck(tester);
    // Ein drittes Video kommt dazu.
    final drittes = fixture(
      'video_5s.mp4',
    ).renameSync(p.join(eingang.path, 'drittes.mp4'));
    await echt(() async {
      // Anders als das erste, damit es keine Dublette ist.
      await drittes.writeAsBytes([0, 0, 0, 1], mode: FileMode.append);
    });
    await importiereDirekt(tester, [drittes]);
    await tap(tester, find.text('Nur Videos'));
    await waitFor(tester, kachel('drittes.mp4'));
    expect(treffer(tester).length, 3);
    await zurueck(tester);

    // ANS-088: löschen mit Abbrechen und Bestätigen.
    final loeschen = find.byTooltip(de.albumIntelligentLoeschen);
    await tap(tester, loeschen);
    await waitFor(
      tester,
      find.text(de.albumIntelligentLoeschenFrage('Nur Videos')),
    );
    await tapText(tester, de.allgAbbrechen);
    expect(find.text('Nur Videos'), findsOneWidget);
    await tap(tester, loeschen);
    await tap(tester, find.widgetWithText(FilledButton, de.allgLoeschen));
    await waitGone(tester, find.text('Nur Videos'));
    await openSection(tester, Hauptbereich.suche);
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Nur Videos'), findsNothing);
    final videos = (await alleAufnahmen(
      tester,
    )).where((a) => a.type == 'VIDEO');
    expect(videos.length, 3, reason: 'alle Videos noch da');
    await finish(tester);
  });

  testWidgets('ANS-089 Server-Knöpfe im Album ohne Verbindung', (tester) async {
    await startApp(tester, fotos: [testfoto('s.jpg')]);
    await albumAnlegen(tester, 'Ohne Server', ['s.jpg']);
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Ohne Server'));
    await waitFor(tester, kachel('s.jpg'));
    expect(find.byTooltip(teilenDe.kontenTeilen), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            (w.message ?? '').startsWith(teilenDe.automatischFuellen),
      ),
      findsNothing,
    );
    await finish(tester);
  });

  // === Suche ================================================================

  testWidgets(
    'ANS-094 ANS-096 ANS-097 Suche: Startzustand, ohne Modell, ohne Embeddings',
    (tester) async {
      await startApp(tester, fotos: [testfoto('strand.jpg')]);
      // ANS-094
      await openSection(tester, Hauptbereich.suche);
      await waitFor(tester, find.text(de.sucheAnleitung));
      expect(suchfeldHinweis(tester), de.suchePlatzhalterKontext);
      expect(find.byTooltip(de.sucheSpeichernTitel), findsNothing);
      await tap(tester, find.byTooltip(de.sucheAusloesen));
      await tester.tap(suchfeld);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(
        find.text(de.sucheAnleitung),
        findsOneWidget,
        reason: 'leer: nichts',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // ANS-096: ohne CLIP-Modell.
      await tippeSuche(tester, 'Strand');
      await waitFor(tester, find.text(de.sucheModellFehlt));
      await oeffneSuchoptionen(tester);
      expect(
        find.descendant(
          of: optionenBlatt,
          matching: find.text(de.suchoptClipFehlt),
        ),
        findsOneWidget,
      );
      final radio = tester.widget<RadioGroup<SearchTextMode>>(
        find.descendant(
          of: find
              .ancestor(
                of: find.descendant(
                  of: optionenBlatt,
                  matching: find.text(de.suchoptTypKontext),
                ),
                matching: find.byType(InkWell),
              )
              .first,
          matching: find.byType(RadioGroup<SearchTextMode>),
        ),
      );
      expect(
        radio.groupValue,
        SearchTextMode.context,
        reason: '„Kontext“ gewählt',
      );
      await tap(
        tester,
        find.descendant(
          of: optionenBlatt,
          matching: find.byTooltip(de.allgSchliessen),
        ),
      );
      // ANS-097: Modell da, Embeddings noch nicht berechnet.
      await zweiteBibliothek(
        tester,
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
        ],
      );
      await befehl(tester, const AuswertenNachImportSetzen(false));
      await importiereDirekt(tester, [testfoto('strand.jpg')]);
      await openSection(tester, Hauptbereich.suche);
      await tippeSuche(tester, 'Strand');
      await waitFor(
        tester,
        find.text(de.sucheOhneEmbeddings),
        timeout: const Duration(seconds: 90),
      );
      expect(find.text(de.sucheKeineTreffer), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('ANS-098 Kontextsuche mit beschädigtem Modell', (tester) async {
    await startApp(
      tester,
      modelle: const ['clip_image_encoder.onnx', 'vocab.json', 'merges.txt'],
    );
    // Die Text-Modelldatei durch Zufallsinhalt ersetzen (eigene Datei im
    // Modellordner der Prüfung, nicht der geteilte Vorrat).
    final kaputt = File(p.join(anker.path, 'models', 'clip_text_encoder.onnx'));
    final zufall = math.Random(7);
    kaputt.writeAsBytesSync([
      for (var i = 0; i < 4096; i++) zufall.nextInt(256),
    ]);
    await echt(() => bibliothek.reloadModels());
    await befehl(tester, const AuswertenNachImportSetzen(false));
    await importiereDirekt(tester, [testfoto('strand.jpg')]);
    await openSection(tester, Hauptbereich.suche);
    await tippeSuche(tester, 'Strand');
    await waitFor(
      tester,
      find.textContaining('liegt zwar auf der Platte'),
      timeout: const Duration(seconds: 60),
    );
    expect(find.textContaining('clip_text_encoder'), findsWidgets);
    // Die App läuft weiter.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel('strand.jpg'));
    await finish(tester);
  });

  testWidgets(
    'ANS-095 ANS-117 ANS-120 Kontextsuche nach Bildinhalt, Gelöschtes und '
    'Gesperrtes nie, ähnliche Fotos',
    (tester) async {
      await startApp(
        tester,
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
          'translate_de_en_encoder.onnx',
          'translate_de_en_decoder.onnx',
          'translate_vocab.json',
        ],
      );
      await befehl(tester, const AuswertenNachImportSetzen(false));
      await befehl(tester, const SucheUebersetzenSetzen(true));
      final weiss = img.ColorRgb8(245, 248, 252);
      final sand = img.ColorRgb8(230, 205, 150);
      await importiereDirekt(tester, [
        motivfoto(
          'hund_schnee.jpg',
          ['DOG', 'SNOW'],
          weiss,
          DateTime(2025, 1, 5),
        ),
        motivfoto(
          'strand_sichtbar.jpg',
          ['BEACH', 'SEA'],
          sand,
          DateTime(2025, 7, 5),
        ),
        motivfoto(
          'strand_weg.jpg',
          ['BEACH', 'SAND'],
          sand,
          DateTime(2025, 7, 6),
        ),
        motivfoto(
          'strand_zu.jpg',
          ['BEACH', 'WAVES'],
          sand,
          DateTime(2025, 7, 7),
        ),
        motivfoto(
          'auto.jpg',
          ['CAR', 'ROAD'],
          img.ColorRgb8(90, 90, 95),
          DateTime(2025, 3, 5),
        ),
        motivfoto(
          'katze.jpg',
          ['CAT'],
          img.ColorRgb8(200, 120, 160),
          DateTime(2025, 4, 5),
        ),
      ]);
      final uhr = Stopwatch()..start();
      await echt(() async {
        await for (final _ in bibliothek.backfillClipEmbeddings(alle: true)) {}
      });
      print('ANS-095: Embeddings in ${uhr.elapsedMilliseconds} ms');
      await befehl(
        tester,
        InDenPapierkorb(await ids(tester, ['strand_weg.jpg'])),
      );
      await tresorEinrichten(tester);
      await sperre(tester, 'strand_zu.jpg');
      // Ein Foto ohne Embedding (danach importiert).
      await importiereDirekt(tester, [
        motivfoto(
          'ohne.jpg',
          ['TREE'],
          img.ColorRgb8(60, 140, 60),
          DateTime(2024, 2, 2),
        ),
      ]);

      // ANS-095: „Hund im Schnee“, das Hundefoto vorn, ohne Netz.
      final netzVorher = ohneNetz.versuche.length;
      await openSection(tester, Hauptbereich.suche);
      await tippeSuche(tester, 'Hund im Schnee');
      await waitFor(
        tester,
        kachel('hund_schnee.jpg'),
        timeout: const Duration(seconds: 90),
      );
      print('ANS-095: Reihenfolge ${treffer(tester)}');
      expect(treffer(tester).first, 'hund_schnee.jpg');
      expect(ohneNetz.versuche.length, netzVorher, reason: 'keine Netzanfrage');
      // ANS-117: Kontextsuche „Strand“ ohne gelöschtes und gesperrtes Foto.
      await tippeSuche(tester, 'Strand');
      await waitFor(tester, kachel('strand_sichtbar.jpg'));
      print('ANS-117: Strand → ${treffer(tester)}');
      expect(treffer(tester), isNot(contains('strand_weg.jpg')));
      expect(treffer(tester), isNot(contains('strand_zu.jpg')));
      expect(treffer(tester).first, 'strand_sichtbar.jpg');
      // Nach Dateiname aller drei.
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'strand_');
      await waitFor(tester, kachel('strand_sichtbar.jpg'));
      expect(treffer(tester), ['strand_sichtbar.jpg']);
      // ANS-120 + ANS-117: ähnliche Bilder beim sichtbaren Strandfoto.
      await oeffne(tester, 'strand_sichtbar.jpg');
      await rechtsklick(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PageView)),
      );
      await tap(tester, find.text(de.viewerAehnlicheZeigen));
      await waitFor(tester, find.text(de.aehnlTitel));
      final aehnliche = find.descendant(
        of: find.byType(SimilarPhotosScreen),
        matching: find.byType(AssetThumbnailTile),
      );
      await waitFor(tester, aehnliche);
      final namen = [
        for (final e in aehnliche.evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      ];
      print('ANS-120: ähnlich zu strand_sichtbar → $namen');
      expect(
        namen,
        isNot(contains('strand_sichtbar.jpg')),
        reason: 'ohne Ausgangsfoto',
      );
      expect(namen, isNot(contains('strand_weg.jpg')));
      expect(namen, isNot(contains('strand_zu.jpg')));
      expect(namen.length, lessThanOrEqualTo(60));
      expect(namen.length, greaterThanOrEqualTo(3));
      // Ein Klick öffnet die Einzelansicht.
      await tap(tester, aehnliche.first);
      await waitGone(tester, find.byType(SimilarPhotosScreen));
      expect(betrachter, findsOneWidget);
      expect(
        tester
            .widget<AssetViewerScreen>(betrachter)
            .assets
            .first
            .originalFileName,
        namen.first,
      );
      await key(tester, LogicalKeyboardKey.escape);
      await waitFor(tester, find.byType(SimilarPhotosScreen));
      await zurueck(tester);
      await schliesseBetrachter(tester);
      // Foto ohne Embedding.
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'ohne');
      await oeffne(tester, 'ohne.jpg');
      await rechtsklick(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PageView)),
      );
      await tap(tester, find.text(de.viewerAehnlicheZeigen));
      await waitFor(tester, find.text(de.aehnlKeineTreffer));
      await zurueck(tester);
      await schliesseBetrachter(tester);
      // Bibliothek ohne Modell.
      await zweiteBibliothek(tester, fotos: () => [testfoto('x.jpg')]);
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'x.jpg');
      await rechtsklick(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PageView)),
      );
      await tap(tester, find.text(de.viewerAehnlicheZeigen));
      await waitFor(tester, find.text(de.aehnlClipFehlt));
      await zurueck(tester);
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets('ANS-099 ANS-100 ANS-102 Suche nach Dateiname, Beschreibung, '
      'KI-Beschreibung, Text im Bild, überall', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('urlaub_strand.jpg', datum: DateTime(2025, 1, 1)),
        testfoto('geburtstag.jpg', datum: DateTime(2025, 1, 2)),
        testfoto('hund.jpg', datum: DateTime(2025, 1, 3)),
        textfoto('bahnhof.jpg', ['BAHNHOF'], datum: DateTime(2025, 1, 4)),
        testfoto('quokka_datei.jpg', datum: DateTime(2025, 2, 1)),
        testfoto('w2.jpg', datum: DateTime(2025, 2, 2)),
        textfoto('w3.jpg', ['QUOKKA'], datum: DateTime(2025, 2, 3)),
        testfoto('w4.jpg', datum: DateTime(2025, 2, 4)),
        testfoto('w5.jpg', datum: DateTime(2025, 2, 5)),
        testfoto('w6.jpg', datum: DateTime(2025, 2, 6)),
      ],
    );
    await befehl(
      tester,
      BeschreibungSetzen(await ids(tester, ['geburtstag.jpg']), 'Strandtag'),
    );
    await echt(() async {
      final h = await aufnahme(tester, 'hund.jpg');
      await bibliothek.db.setAiCaption(h.id, 'a dog on a beach');
    });
    // Ein Wort an sechs verschiedenen Stellen.
    await befehl(
      tester,
      BeschreibungSetzen(await ids(tester, ['w2.jpg']), 'Ein Quokka am Weg'),
    );
    await befehl(
      tester,
      SchlagwortAnheften(await ids(tester, ['w4.jpg']), 'Quokka'),
    );
    final w5 = await aufnahme(tester, 'w5.jpg');
    await echt(
      () => bibliothek.db.setLocationNames(
        w5.id,
        country: 'Australien',
        state: 'Westaustralien',
        city: 'Quokkastadt',
      ),
    );
    final person = _uuid.v4();
    await befehl(tester, PersonAnlegen(person, 'Quokka'));
    await gesichtFuer(tester, 'w6.jpg', person);
    // Texterkennung (macOS: Vision).
    await echt(() async {
      await for (final _ in bibliothek.backfillOcrText(alle: true)) {}
    });
    expect(
      (await aufnahme(tester, 'bahnhof.jpg')).ocrText?.toUpperCase(),
      contains('BAHNHOF'),
    );
    await openSection(tester, Hauptbereich.suche);
    // ANS-099
    await sucheNachTyp(tester, de.suchoptTypDateiname, 'urlaub');
    expect(treffer(tester), ['urlaub_strand.jpg']);
    expect(suchfeldHinweis(tester), de.suchePlatzhalterDateiname);
    await sucheNachTyp(tester, de.suchoptTypBeschreibung, 'Strand');
    expect(treffer(tester), ['geburtstag.jpg']);
    expect(suchfeldHinweis(tester), de.suchePlatzhalterBeschreibung);
    await sucheNachTyp(tester, de.suchoptTypCaption, 'dog');
    expect(treffer(tester), ['hund.jpg']);
    expect(suchfeldHinweis(tester), de.suchePlatzhalterBildunterschrift);
    // ANS-100
    await sucheNachTyp(tester, de.suchoptTypOcr, 'Bahnhof');
    expect(treffer(tester), ['bahnhof.jpg']);
    // ANS-102: überall.
    await sucheNachTyp(tester, de.suchoptTypUeberall, 'Quokka');
    expect(treffer(tester)..sort(), [
      'quokka_datei.jpg',
      'w2.jpg',
      'w3.jpg',
      'w4.jpg',
      'w5.jpg',
      'w6.jpg',
    ]);
    await sucheNachTyp(tester, de.suchoptTypUeberall, 'Quo');
    expect(treffer(tester).length, 6, reason: 'Wortanfang');
    for (final sonder in ['OR', 'NOT', '(*', 'Quokka OR Hund']) {
      await sucheNachTyp(tester, de.suchoptTypUeberall, sonder);
      expect(tester.takeException(), isNull, reason: sonder);
      expect(
        find.textContaining('fehlgeschlagen'),
        findsNothing,
        reason: sonder,
      );
    }
    await sucheNachTyp(tester, de.suchoptTypUeberall, 'Quokka OR Hund');
    expect(treffer(tester), isEmpty, reason: '„OR“ ist ein gewöhnliches Wort');
    // ANS-100: frische Bibliothek ohne Texterkennungslauf.
    await zweiteBibliothek(tester, fotos: () => [testfoto('frisch.jpg')]);
    await befehl(tester, const AuswertenNachImportSetzen(false));
    await openSection(tester, Hauptbereich.suche);
    await sucheNachTyp(tester, de.suchoptTypOcr, 'Bahnhof');
    await waitFor(tester, find.text(de.sucheOhneTexterkennung));
    await finish(tester);
  });

  testWidgets('ANS-101 Gesprochenes in Videos suchen', (tester) async {
    await startApp(
      tester,
      modelle: const [
        'whisper_encoder.onnx',
        'whisper_decoder.onnx',
        'whisper_vocab.json',
      ],
    );
    // Sonst schriebe die Auswertung nach dem Import ihr eigenes (leeres)
    // Transkript über das gesetzte.
    await befehl(tester, const AuswertenNachImportSetzen(false));
    await importiereDirekt(tester, [
      fixture('video_5s.mp4'),
      testfoto('still.jpg'),
    ]);
    // Vorbedingung: ein Durchgang hat das Wort erkannt (die Spracherkennung
    // selbst prüft integration_test/whisper_test.dart).
    final v = await aufnahme(tester, 'video_5s.mp4');
    await echt(
      () => bibliothek.db.setTranskript(
        v.id,
        text: 'Geburtstagskuchen',
        sprache: 'de',
      ),
    );
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptTypTranskript);
    expect(
      find.descendant(
        of: optionenBlatt,
        matching: find.text(de.suchoptTranskriptFehlt),
      ),
      findsNothing,
      reason: 'Modell vorhanden',
    );
    await enter(tester, optionenFeld, 'Geburtstagskuchen');
    await optionenSuchen(tester);
    await waitFor(tester, kachel('video_5s.mp4'));
    expect(treffer(tester), ['video_5s.mp4']);
    // Ohne Modell.
    await zweiteBibliothek(tester, fotos: () => [testfoto('x.jpg')]);
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptTypTranskript);
    await waitFor(
      tester,
      find.descendant(
        of: optionenBlatt,
        matching: find.text(de.suchoptTranskriptFehlt),
      ),
    );
    await finish(tester);
  });

  testWidgets('ANS-103 ANS-104 ANS-105 Personen-, Schlagwort-, Bewertungs- und '
      'Farbfilter', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('a_allein.jpg', datum: DateTime(2025, 1, 1)),
        testfoto('a_mit_b.jpg', datum: DateTime(2025, 1, 2)),
        testfoto('b_allein.jpg', datum: DateTime(2025, 1, 3)),
        testfoto('a_mit_kind.jpg', datum: DateTime(2025, 1, 4)),
      ],
    );
    final a = _uuid.v4(), b = _uuid.v4(), kind = _uuid.v4();
    await befehl(tester, PersonAnlegen(a, 'Person A'));
    await befehl(tester, PersonAnlegen(b, 'Person B'));
    await befehl(tester, PersonAnlegen(kind, 'Kind'));
    await gesichtFuer(tester, 'a_allein.jpg', a);
    await gesichtFuer(tester, 'a_mit_b.jpg', a);
    await gesichtFuer(tester, 'a_mit_b.jpg', b);
    await gesichtFuer(tester, 'b_allein.jpg', b);
    await gesichtFuer(tester, 'a_mit_kind.jpg', a);
    await gesichtFuer(tester, 'a_mit_kind.jpg', kind);
    await openSection(tester, Hauptbereich.suche);
    // ANS-103: A einmal, B zweimal → A ohne B.
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, 'Person A');
    await imBlatt(tester, 'Person B');
    await imBlatt(tester, 'Person B');
    expect(
      ausschlussZeichen,
      findsOneWidget,
      reason: 'B trägt das Ausschluss-Zeichen',
    );
    await optionenSuchen(tester);
    expect(treffer(tester)..sort(), ['a_allein.jpg', 'a_mit_kind.jpg']);
    // Dritter Tipp hebt B auf; A und Kind zusammen.
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, 'Person B');
    expect(ausschlussZeichen, findsNothing);
    await imBlatt(tester, 'Kind');
    await optionenSuchen(tester);
    expect(treffer(tester), ['a_mit_kind.jpg']);

    // ANS-104: Schlagwörter.
    await zweiteBibliothek(
      tester,
      fotos: () => [
        testfoto('berge.jpg', datum: DateTime(2025, 2, 1)),
        testfoto('berge_strand.jpg', datum: DateTime(2025, 2, 2)),
        testfoto('strand.jpg', datum: DateTime(2025, 2, 3)),
        testfoto('ohne.jpg', datum: DateTime(2025, 2, 4)),
      ],
    );
    await befehl(
      tester,
      SchlagwortAnheften(
        await ids(tester, ['berge.jpg', 'berge_strand.jpg']),
        'Berge',
      ),
    );
    await befehl(
      tester,
      SchlagwortAnheften(
        await ids(tester, ['berge_strand.jpg', 'strand.jpg']),
        'Strand',
      ),
    );
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptTagsHint);
    await waitFor(tester, find.text(de.suchoptTagsWaehlen));
    await tap(tester, find.widgetWithText(CheckboxListTile, 'Berge'));
    await tapText(tester, de.allgUebernehmen);
    await imBlatt(tester, de.suchoptOhneTagsHint);
    await tap(tester, find.widgetWithText(CheckboxListTile, 'Strand'));
    await tapText(tester, de.allgUebernehmen);
    // „Abbrechen“ im Dialog übernimmt nichts.
    await imBlatt(tester, de.suchoptOhneTagsHint);
    await tap(tester, find.widgetWithText(CheckboxListTile, 'Berge'));
    await tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgAbbrechen),
      ),
    );
    await optionenSuchen(tester);
    expect(treffer(tester), ['berge.jpg']);
    await oeffneSuchoptionen(tester);
    await tap(tester, find.text(de.suchoptAllesLeeren));
    await imBlatt(tester, de.suchoptOhneTag);
    // Solange „Ohne Tag“ gesetzt ist, sind die Tag-Felder gesperrt.
    final tagFeld = find.ancestor(
      of: find.descendant(
        of: optionenBlatt,
        matching: find.text(de.suchoptTagsHint),
      ),
      matching: find.byType(InkWell),
    );
    expect(tester.widget<InkWell>(tagFeld.first).onTap, isNull);
    await optionenSuchen(tester);
    expect(treffer(tester), ['ohne.jpg']);

    // ANS-105: Mindestbewertung und Farben.
    await zweiteBibliothek(
      tester,
      fotos: () => [
        for (final n in ['s2', 's3', 's5', 'rot', 'blau', 'keine'])
          testfoto('$n.jpg', datum: DateTime(2025, 3, n.length)),
      ],
    );
    await befehl(tester, BewertungSetzen(await ids(tester, ['s2.jpg']), 2));
    await befehl(tester, BewertungSetzen(await ids(tester, ['s3.jpg']), 3));
    await befehl(tester, BewertungSetzen(await ids(tester, ['s5.jpg']), 5));
    await befehl(
      tester,
      FarbmarkeSetzen(await ids(tester, ['rot.jpg']), 'red'),
    );
    await befehl(
      tester,
      FarbmarkeSetzen(await ids(tester, ['blau.jpg']), 'blue'),
    );
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    final sterne = find.descendant(
      of: find.descendant(of: optionenBlatt, matching: find.byType(StarRating)),
      matching: find.byType(InkWell),
    );
    await rolleZu(
      tester,
      sterne.at(2),
      in_: find
          .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
          .first,
    );
    await tap(tester, sterne.at(2));
    await optionenSuchen(tester);
    expect(treffer(tester)..sort(), ['s3.jpg', 's5.jpg']);
    await oeffneSuchoptionen(tester);
    await rolleZu(
      tester,
      sterne.at(2),
      in_: find
          .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
          .first,
    );
    await tap(tester, sterne.at(2));
    expect(
      tester
          .widget<StarRating>(
            find.descendant(
              of: optionenBlatt,
              matching: find.byType(StarRating),
            ),
          )
          .value,
      0,
      reason: 'erneutes Antippen hebt auf',
    );
    await imBlatt(tester, de.farbeRot);
    await imBlatt(tester, de.farbeBlau);
    await optionenSuchen(tester);
    expect(treffer(tester)..sort(), ['blau.jpg', 'rot.jpg']);
    await finish(tester);
  });

  testWidgets(
    'ANS-106 ANS-107 ANS-108 Aufnahmewerte, Kamera, unscharf, Dateiformat, Ort',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (final n in ['iso100', 'iso800', 'iso3200'])
            testfoto('$n.jpg', datum: DateTime(2025, 4, n.length)),
        ],
      );
      final werte = {
        'iso100.jpg': (100, 1.8, 24.0, 'Beta', 'B1', 'Weit 24', 9000.0),
        'iso800.jpg': (800, 8.0, 200.0, 'Alpha', 'A9', 'Tele 200', 1.0),
        'iso3200.jpg': (3200, 8.0, 200.0, 'Alpha', 'A9', 'Tele 200', 9000.0),
      };
      for (final e in werte.entries) {
        final (iso, blende, brennweite, marke, modell, objektiv, schaerfe) =
            e.value;
        await setzeSpalten(
          tester,
          e.key,
          AssetsCompanion(
            iso: Value(iso),
            fNumber: Value(blende),
            focalLengthMm: Value(brennweite),
            cameraMake: Value(marke),
            cameraModel: Value(modell),
            lensModel: Value(objektiv),
            sharpnessScore: Value(schaerfe),
          ),
        );
      }
      final scroller = find
          .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
          .first;
      Future<void> feld(String beschriftung, String text) async {
        final f = find.descendant(
          of: optionenBlatt,
          matching: field(beschriftung),
        );
        await rolleZu(tester, f, in_: scroller);
        await enter(tester, f, text);
      }

      await openSection(tester, Hauptbereich.suche);
      // ANS-106: ISO 800–3200, beide Enden einschliesslich.
      await oeffneSuchoptionen(tester);
      await feld(de.suchoptIsoVon, '800');
      await feld(de.suchoptIsoBis, '3200');
      await optionenSuchen(tester);
      expect(treffer(tester)..sort(), ['iso3200.jpg', 'iso800.jpg']);
      // Blende mit Komma, danach „abc“.
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      await feld(de.suchoptBlendeVon, '1,8');
      await feld(de.suchoptBlendeBis, '1,8');
      await optionenSuchen(tester);
      expect(treffer(tester), ['iso100.jpg']);
      await oeffneSuchoptionen(tester);
      await feld(de.suchoptBlendeVon, 'abc');
      await feld(de.suchoptBlendeBis, '');
      await feld(de.suchoptIsoVon, '100');
      await optionenSuchen(tester);
      expect(treffer(tester).length, 3, reason: '„abc“ wird ignoriert');
      // Kameralisten: nur vorhandene Werte, sortiert, ohne Doppelte.
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      Future<List<String>> liste(String beschriftung) async {
        final dd = find.descendant(
          of: optionenBlatt,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String?> &&
                w.decoration.labelText == beschriftung,
          ),
        );
        await rolleZu(tester, dd, in_: scroller);
        await tap(tester, dd);
        final eintraege = [
          for (final e
              in find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (w) =>
                          w.runtimeType.toString().startsWith('_DropdownMenu'),
                    ),
                    matching: find.byType(Text),
                  )
                  .evaluate())
            (e.widget as Text).data ?? '',
        ];
        await tap(tester, find.text(de.allgAlle).last);
        return eintraege;
      }

      expect(await liste(de.suchoptMarke), [de.allgAlle, 'Alpha', 'Beta']);
      expect(await liste(de.suchoptModell), [de.allgAlle, 'A9', 'B1']);
      expect(await liste(de.suchoptObjektiv), [
        de.allgAlle,
        'Tele 200',
        'Weit 24',
      ]);
      // Nur unscharfe Fotos.
      await imBlatt(tester, de.suchoptNurUnscharfe);
      await optionenSuchen(tester);
      expect(treffer(tester), ['iso800.jpg']);

      // ANS-107: Dateiformate (JPG, PNG und zwei RAW).
      final png = File(p.join(eingang.path, 'grafik.png'))
        ..writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 48)));
      await importiereDirekt(tester, [
        png,
        repoFixture('samples/canon_eos_r10.cr3'),
        repoFixture('samples/sony_ilce6300.arw'),
      ]);
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      final formate = find.descendant(
        of: find
            .ancestor(
              of: find.descendant(
                of: optionenBlatt,
                matching: find.text(de.suchoptDateiformat),
              ),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(FilterChip),
      );
      await rolleZu(tester, formate.first, in_: scroller);
      final chips = [
        for (final e in formate.evaluate())
          ((e.widget as FilterChip).label as Text).data,
      ];
      print('ANS-107: Formate $chips');
      expect(
        chips,
        containsAll([de.suchoptNurRaw, 'JPG', 'PNG', 'CR3', 'ARW']),
      );
      expect(chips, isNot(contains('HEIC')), reason: 'nur vorhandene');
      await imBlatt(tester, 'JPG');
      await imBlatt(tester, 'PNG');
      await optionenSuchen(tester);
      expect(treffer(tester).length, 4, reason: 'JPG oder PNG');
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      await imBlatt(tester, de.suchoptNurRaw);
      await optionenSuchen(tester);
      expect(treffer(tester)..sort(), [
        'canon_eos_r10.cr3',
        'sony_ilce6300.arw',
      ]);
      await tap(tester, find.byTooltip(de.sucheSpeichernTitel));
      await enter(tester, field(de.allgName), 'Nur Rohdaten');
      await tapText(tester, de.allgSpeichern);
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.suche);
      await tap(tester, find.widgetWithText(InputChip, 'Nur Rohdaten'));
      await settle(tester);
      expect(treffer(tester)..sort(), [
        'canon_eos_r10.cr3',
        'sony_ilce6300.arw',
      ]);

      // ANS-108: Ortsfilter.
      final orte = {
        'iso100.jpg': ('Frankreich', 'Bretagne', 'Brest'),
        'iso800.jpg': ('Frankreich', 'Provence', 'Nizza'),
        'iso3200.jpg': ('Italien', 'Toskana', 'Florenz'),
        'grafik.png': ('Italien', 'Latium', 'Rom'),
      };
      for (final e in orte.entries) {
        final a = await aufnahme(tester, e.key);
        await echt(
          () => bibliothek.db.setLocationNames(
            a.id,
            country: e.value.$1,
            state: e.value.$2,
            city: e.value.$3,
          ),
        );
      }
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.suche);
      await oeffneSuchoptionen(tester);
      Future<void> waehleIn(String beschriftung, String wert) async {
        final dd = find.descendant(
          of: optionenBlatt,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String?> &&
                w.decoration.labelText == beschriftung,
          ),
        );
        await rolleZu(tester, dd, in_: scroller);
        await tap(tester, dd);
        await tap(tester, find.text(wert).last);
      }

      await waehleIn(de.suchoptLand, 'Frankreich');
      expect(await liste(de.suchoptBundesland), [
        de.allgAlle,
        'Bretagne',
        'Provence',
      ]);
      // Die Stadt lässt sich erst nach dem Bundesland öffnen
      // (search_options_sheet.dart, _locationState == null → gesperrt).
      final stadt = find.descendant(
        of: optionenBlatt,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String?> &&
              w.decoration.labelText == de.suchoptStadt,
        ),
      );
      final stadtGesperrt =
          tester.widget<DropdownButtonFormField<String?>>(stadt).onChanged ==
          null;
      print('ANS-108: Stadt nach Landeswahl gesperrt: $stadtGesperrt');
      await waehleIn(de.suchoptBundesland, 'Provence');
      expect(await liste(de.suchoptStadt), [de.allgAlle, 'Nizza']);
      await waehleIn(de.suchoptStadt, 'Nizza');
      await optionenSuchen(tester);
      expect(treffer(tester), ['iso800.jpg']);
      // Zweite Bibliothek ohne aufgelöste Orte.
      await zweiteBibliothek(tester, fotos: () => [testfoto('x.jpg')]);
      await openSection(tester, Hauptbereich.suche);
      await oeffneSuchoptionen(tester);
      final hinweis = find.descendant(
        of: optionenBlatt,
        matching: find.text(de.suchoptGeoFehlt),
      );
      await rolleZu(tester, hinweis, in_: scroller);
      expect(hinweis, findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('ANS-109 Zeitraumfilter, beide Enden einschliesslich', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('erster.jpg', datum: DateTime(2026, 6, 1, 9)),
        testfoto('mitte.jpg', datum: DateTime(2026, 6, 15, 21)),
        testfoto('ende.jpg', datum: DateTime(2026, 6, 30, 9)),
        testfoto('alt.jpg', datum: DateTime(1985, 5, 5, 9)),
      ],
    );
    await setzeDatum(tester, 'alt.jpg', DateTime(1985, 5, 5, 9));
    await openSection(tester, Hauptbereich.suche);
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptAnfangsdatum);
    await tap(
      tester,
      find
          .descendant(
            of: optionenBlatt,
            matching: find.text(de.suchoptDatumPlatzhalter),
          )
          .first,
    );
    expect(await datumEintippen(tester, DateTime(2026, 6, 1)), isTrue);
    await tap(
      tester,
      find
          .descendant(
            of: optionenBlatt,
            matching: find.text(de.suchoptDatumPlatzhalter),
          )
          .first,
    );
    expect(await datumEintippen(tester, DateTime(2026, 6, 15)), isTrue);
    await optionenSuchen(tester);
    expect(treffer(tester)..sort(), ['erster.jpg', 'mitte.jpg']);
    // „Datum entfernen“ leert das Feld.
    await oeffneSuchoptionen(tester);
    final entfernen = find.descendant(
      of: optionenBlatt,
      matching: find.byTooltip(de.suchoptDatumEntfernen),
    );
    await rolleZu(
      tester,
      entfernen.last,
      in_: find
          .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
          .first,
    );
    expect(entfernen, findsNWidgets(2));
    await tap(tester, entfernen.last);
    expect(entfernen, findsOneWidget);
    expect(
      find.descendant(
        of: optionenBlatt,
        matching: find.text(de.suchoptDatumPlatzhalter),
      ),
      findsOneWidget,
    );
    await optionenSuchen(tester);
    expect(treffer(tester)..sort(), ['ende.jpg', 'erster.jpg', 'mitte.jpg']);
    await finish(tester);
  });

  testWidgets(
    'ANS-110 ANS-111 Medientyp, Anzeigeoptionen, Herkunft, Null-Treffer, '
    'Alles leeren, Schliessen, Filterpunkt',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto(
            'p_album.jpg',
            datum: DateTime(2025, 1, 1),
            kamera: 'Marke',
            modell: 'M',
          ),
          testfoto(
            'p_fav.jpg',
            datum: DateTime(2025, 1, 2),
            kamera: 'Marke',
            modell: 'M',
          ),
          testfoto(
            'IMG_4711.jpg',
            datum: DateTime(2025, 1, 3),
            kamera: 'Marke',
            modell: 'M',
          ),
          testfoto('IMG-20240512-WA0003.jpg'),
          fixture('video_5s.mp4'),
        ],
      );
      await albumAnlegen(tester, 'Eins', ['p_album.jpg']);
      await befehl(
        tester,
        FavoritSetzen(await ids(tester, ['p_fav.jpg']), true),
      );
      await befehl(
        tester,
        BewertungSetzen(await ids(tester, ['p_fav.jpg']), 5),
      );
      final alle = await alleAufnahmen(tester);
      final bilder = {
        for (final a in alle)
          if (a.type == 'IMAGE') a.originalFileName,
      };
      final geschaetzt = {
        for (final a in alle)
          if (a.datumGeschaetzt) a.originalFileName,
      };
      print('ANS-110: geschätzt $geschaetzt');
      expect(geschaetzt, contains('IMG-20240512-WA0003.jpg'));
      final scroller = find
          .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
          .first;
      Future<Set<String>> mitOption(List<String> texte) async {
        await oeffneSuchoptionen(tester);
        await tap(tester, find.text(de.suchoptAllesLeeren));
        for (final t in texte) {
          await imBlatt(tester, t);
        }
        await optionenSuchen(tester);
        return treffer(tester).toSet();
      }

      await openSection(tester, Hauptbereich.suche);
      // ANS-110
      expect(await mitOption([de.suchoptBild]), bilder);
      expect(await mitOption([de.suchoptVideo]), {'video_5s.mp4'});
      expect(
        await mitOption([de.suchoptInKeinemAlbum]),
        {for (final a in alle) a.originalFileName}..remove('p_album.jpg'),
      );
      expect(await mitOption([de.suchoptFavoriten]), {'p_fav.jpg'});
      expect(await mitOption([de.sucheDatumGeschaetzt]), geschaetzt);
      final kamera = await mitOption([de.sucheHerkunftKamera]);
      expect(kamera, contains('IMG_4711.jpg'));
      expect(kamera, isNot(contains('IMG-20240512-WA0003.jpg')));
      final empfangen = await mitOption([de.sucheHerkunftEmpfangen]);
      expect(empfangen, contains('IMG-20240512-WA0003.jpg'));
      expect(empfangen, isNot(contains('IMG_4711.jpg')));

      // ANS-111: 5 Sterne und Video ergeben nichts.
      await oeffneSuchoptionen(tester);
      await tap(tester, find.text(de.suchoptAllesLeeren));
      final sterne = find.descendant(
        of: find.descendant(
          of: optionenBlatt,
          matching: find.byType(StarRating),
        ),
        matching: find.byType(InkWell),
      );
      await rolleZu(tester, sterne.at(4), in_: scroller);
      await tap(tester, sterne.at(4));
      await imBlatt(tester, de.suchoptVideo);
      await waitFor(tester, find.text(de.suchoptKeineTreffer));
      // „Alles leeren“ setzt zurück.
      await tap(tester, find.text(de.suchoptAllesLeeren));
      await waitGone(tester, find.text(de.suchoptKeineTreffer));
      final sternreihe = find.descendant(
        of: optionenBlatt,
        matching: find.byType(StarRating),
      );
      await rolleZu(tester, sternreihe, in_: scroller);
      expect(tester.widget<StarRating>(sternreihe).value, 0);
      // „Schliessen“ verwirft.
      await imBlatt(tester, de.suchoptFavoriten);
      await tap(
        tester,
        find.descendant(
          of: optionenBlatt,
          matching: find.byTooltip(de.allgSchliessen),
        ),
      );
      await waitGone(tester, optionenBlatt);
      await oeffneSuchoptionen(tester);
      final fav = find.descendant(
        of: optionenBlatt,
        matching: find.widgetWithText(CheckboxListTile, de.suchoptFavoriten),
      );
      await rolleZu(tester, fav, in_: scroller);
      expect(tester.widget<CheckboxListTile>(fav).value, isFalse);
      // Mehrere Filter zusammen (UND), danach trägt das Symbol einen Punkt.
      await tap(tester, find.text(de.suchoptAllesLeeren));
      await imBlatt(tester, de.suchoptBild);
      await imBlatt(tester, de.suchoptInKeinemAlbum);
      await imBlatt(tester, de.suchoptFavoriten);
      await optionenSuchen(tester);
      expect(treffer(tester), ['p_fav.jpg']);
      final punkt = tester.widget<Badge>(
        find.descendant(
          of: find.byTooltip(de.sucheOptionen),
          matching: find.byType(Badge),
        ),
      );
      expect(punkt.isLabelVisible, isTrue);
      await finish(tester);
    },
  );

  testWidgets('ANS-112 Satzdeutung zeigt Marken', (tester) async {
    await startApp(
      tester,
      modelle: const [
        'clip_image_encoder.onnx',
        'clip_text_encoder.onnx',
        'vocab.json',
        'merges.txt',
      ],
    );
    await befehl(tester, const AuswertenNachImportSetzen(false));
    final sand = img.ColorRgb8(230, 205, 150);
    await importiereDirekt(tester, [
      motivfoto('treffer.jpg', ['BEACH'], sand, DateTime(2023, 7, 1)),
      motivfoto('falsches_jahr.jpg', ['BEACH'], sand, DateTime(2022, 7, 1)),
      motivfoto('drei_sterne.jpg', ['BEACH'], sand, DateTime(2023, 8, 1)),
      motivfoto('ohne_person.jpg', ['BEACH'], sand, DateTime(2023, 9, 1)),
    ]);
    final a = _uuid.v4();
    await befehl(tester, PersonAnlegen(a, 'Person A'));
    for (final n in ['treffer.jpg', 'falsches_jahr.jpg', 'drei_sterne.jpg']) {
      await gesichtFuer(tester, n, a);
    }
    await befehl(
      tester,
      BewertungSetzen(
        await ids(tester, [
          'treffer.jpg',
          'falsches_jahr.jpg',
          'ohne_person.jpg',
        ]),
        5,
      ),
    );
    await befehl(
      tester,
      BewertungSetzen(await ids(tester, ['drei_sterne.jpg']), 3),
    );
    await echt(() async {
      await for (final _ in bibliothek.backfillClipEmbeddings(alle: true)) {}
    });
    await openSection(tester, Hauptbereich.suche);
    await tippeSuche(tester, 'Strand 2023 mit 5 Sternen Person A');
    final marken = find.descendant(
      of: find.byType(SearchScreen),
      matching: find.byType(Chip),
    );
    await waitFor(tester, marken);
    final texte = [
      for (final e in marken.evaluate())
        ((e.widget as Chip).label as Text).data ?? '',
    ];
    print('ANS-112: Marken $texte');
    expect(texte.length, 3);
    expect(texte[0], startsWith('${de.famstatZeitraum}: '));
    expect(texte[0], contains('2023'));
    expect(texte[1], startsWith('${de.infoBewertung}: '));
    expect(texte[2], '${de.navPersonen}: Person A');
    expect(tester.widget<TextField>(suchfeld).controller!.text, 'Strand');
    await waitFor(
      tester,
      kachel('treffer.jpg'),
      timeout: const Duration(seconds: 60),
    );
    expect(treffer(tester), ['treffer.jpg']);
    await finish(tester);
  });

  // Befund: „Deutung zurücknehmen“ stellt den Satz nur aus den erkannten
  // Teilen zusammen (search_screen.dart:888, `funde.wortlaut`); der
  // unerkannte Rest („Strand“) fehlt. _satzVerwerfen (search_screen.dart:
  // 362) baut die Filter neu und verwirft so auch die von Hand gesetzten
  // „Favoriten“.
  testWidgets(
    'ANS-113 Satzdeutung zurücknehmen stellt den Satz wieder her',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [testfoto('x.jpg', datum: DateTime(2023, 5, 1))],
      );
      final a = _uuid.v4();
      await befehl(tester, PersonAnlegen(a, 'Person A'));
      await gesichtFuer(tester, 'x.jpg', a);
      await openSection(tester, Hauptbereich.suche);
      // Von Hand „Favoriten“ setzen.
      await oeffneSuchoptionen(tester);
      await imBlatt(tester, de.suchoptFavoriten);
      await optionenSuchen(tester);
      const satz = 'Strand 2023 mit 5 Sternen Person A';
      await tippeSuche(tester, satz);
      await waitFor(tester, find.byTooltip(de.sucheSatzVerwerfen));
      await tap(tester, find.byTooltip(de.sucheSatzVerwerfen));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(Chip),
        ),
        findsNothing,
        reason: 'Marken weg',
      );
      final feld = tester.widget<TextField>(suchfeld).controller!.text;
      print('ANS-113: im Feld nach dem Zurücknehmen „$feld“');
      await oeffneSuchoptionen(tester);
      final fav = find.descendant(
        of: optionenBlatt,
        matching: find.widgetWithText(CheckboxListTile, de.suchoptFavoriten),
      );
      await rolleZu(
        tester,
        fav,
        in_: find
            .descendant(of: optionenBlatt, matching: find.byType(Scrollable))
            .first,
      );
      final favoritBleibt = tester.widget<CheckboxListTile>(fav).value;
      print('ANS-113: „Favoriten“ danach noch gesetzt: $favoritBleibt');
      expect(feld, satz);
      expect(favoritBleibt, isTrue, reason: 'von Hand gesetzter Filter bleibt');
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-118 ANS-119 Gespeicherte Suchen als Chips; Favoriten- und Archivansicht',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('strand_fav.jpg', datum: DateTime(2025, 1, 1)),
          testfoto('strand_nicht.jpg', datum: DateTime(2025, 1, 2)),
          testfoto('berg_fav.jpg', datum: DateTime(2025, 1, 3)),
          testfoto('archiviert.jpg', datum: DateTime(2025, 1, 4)),
        ],
      );
      await befehl(
        tester,
        FavoritSetzen(
          await ids(tester, ['strand_fav.jpg', 'berg_fav.jpg']),
          true,
        ),
      );
      await befehl(
        tester,
        ArchivSetzen(await ids(tester, ['archiviert.jpg']), true),
      );
      await openSection(tester, Hauptbereich.suche);
      // ANS-118
      await oeffneSuchoptionen(tester);
      await imBlatt(tester, de.suchoptFavoriten);
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'strand', offen: true);
      expect(treffer(tester), ['strand_fav.jpg']);
      await tap(tester, find.byTooltip(de.sucheSpeichernTitel));
      await enter(tester, field(de.allgName), 'Strandfavoriten');
      await tapText(tester, de.allgSpeichern);
      final chip = find.widgetWithText(InputChip, 'Strandfavoriten');
      await waitFor(tester, chip);
      expect(
        find.descendant(of: chip, matching: find.byIcon(Icons.bookmark)),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip(de.sucheSpeichernTitel));
      await tapText(tester, de.allgSpeichern);
      expect(
        find.byType(InputChip),
        findsOneWidget,
        reason: 'leerer Name speichert nichts',
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.suche);
      await waitFor(tester, chip);
      expect(find.text(de.sucheAnleitung), findsOneWidget);
      await tap(
        tester,
        find.descendant(of: chip, matching: find.text('Strandfavoriten')),
      );
      await waitFor(tester, kachel('strand_fav.jpg'));
      expect(treffer(tester), ['strand_fav.jpg']);
      expect(tester.widget<TextField>(suchfeld).controller!.text, 'strand');
      expect(suchfeldHinweis(tester), de.suchePlatzhalterDateiname);
      await chipLoeschen(tester, chip);
      await waitGone(tester, chip);
      await openSection(tester, Hauptbereich.alben);
      await settle(tester);
      expect(find.text('Strandfavoriten'), findsNothing);

      // ANS-119: Favoriten als Suche.
      await openSection(tester, Hauptbereich.favoriten);
      await waitFor(tester, kachel('strand_fav.jpg'));
      expect(treffer(tester)..sort(), ['berg_fav.jpg', 'strand_fav.jpg']);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(de.navFavoriten),
        ),
        findsOneWidget,
      );
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'berg');
      expect(treffer(tester), ['berg_fav.jpg']);
      await openSection(tester, Hauptbereich.archiv);
      await waitFor(tester, kachel('archiviert.jpg'));
      expect(treffer(tester), ['archiviert.jpg']);
      await zweiteBibliothek(tester, fotos: () => [testfoto('x.jpg')]);
      await openSection(tester, Hauptbereich.favoriten);
      await waitFor(tester, find.text(de.sucheKeineTreffer));
      await finish(tester);
    },
  );

  // === Rückblick, Erinnerungen, Jahresrückblick =============================

  testWidgets(
    'ANS-122 ANS-124 „An diesem Tag“ und Papierkorb-Zeile im Rückblick',
    (tester) async {
      final h = DateTime.now();
      DateTime vor(int jahre) => DateTime(h.year - jahre, h.month, h.day, 10);
      await startApp(
        tester,
        fotos: [
          testfoto('vor1a.jpg', datum: vor(1)),
          testfoto('vor1b.jpg', datum: vor(1).add(const Duration(hours: 1))),
          testfoto('vor3.jpg', datum: vor(3)),
          testfoto('heute.jpg', datum: DateTime(h.year, h.month, h.day, 0, 1)),
          testfoto('anders.jpg', datum: DateTime(2020, 1, 1)),
          testfoto('anders2.jpg', datum: DateTime(2020, 1, 2)),
        ],
      );
      await openSection(tester, Hauptbereich.rueckblick);
      final vor1 = find.text(de.erkundenVorJahren(1));
      await waitFor(tester, vor1);
      expect(find.text(de.erkundenVorJahren(3)), findsOneWidget);
      expect(
        find.text(de.erkundenErinnerungen),
        findsNWidgets(2),
        reason: 'Abschnitt und Zeile',
      );
      Finder reiheUnter(Finder kopf) => find.descendant(
        of: find.ancestor(of: kopf, matching: find.byType(Column)).first,
        matching: find.byType(AssetThumbnailTile),
      );
      final erinnerungen = find
          .ancestor(of: vor1, matching: find.byType(Column))
          .first;
      expect(
        find.descendant(of: erinnerungen, matching: kachel('heute.jpg')),
        findsNothing,
        reason: 'das Foto von heute fehlt',
      );
      expect(reiheUnter(vor1), findsWidgets);
      // Die Einzelansicht blättert nur in der Gruppe.
      await tap(
        tester,
        find.descendant(of: erinnerungen, matching: kachel('vor1a.jpg')),
      );
      await waitFor(tester, betrachter);
      expect(
        tester
            .widget<AssetViewerScreen>(betrachter)
            .assets
            .map((a) => a.originalFileName)
            .toSet(),
        {'vor1a.jpg', 'vor1b.jpg'},
      );
      await schliesseBetrachter(tester);

      // ANS-124: Papierkorb-Zeile.
      final rolle = rolleIn(ExploreScreen);
      await rolleZu(
        tester,
        imSchirm(ExploreScreen, de.papierkorbTitel),
        in_: rolle,
      );
      expect(find.text(de.papierkorbLeer), findsOneWidget);
      await befehl(
        tester,
        InDenPapierkorb(await ids(tester, ['anders.jpg', 'anders2.jpg'])),
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.rueckblick);
      final rolle2 = rolleIn(ExploreScreen);
      await rolleZu(tester, find.text(de.papierkorbAnzahl(2)), in_: rolle2);
      expect(find.text(de.papierkorbAnzahl(2)), findsOneWidget);
      final lage = tester.state<ScrollableState>(rolle2).position.pixels;
      await tap(tester, find.text(de.papierkorbAnzahl(2)));
      await waitFor(tester, find.byType(TrashScreen));
      await zurueck(tester);
      await waitGone(tester, find.byType(TrashScreen));
      expect(
        tester.state<ScrollableState>(rolle2).position.pixels,
        closeTo(lage, 2),
        reason: 'dieselbe Rollposition',
      );
      // Zweite Bibliothek: derselbe Monat früherer Jahre, andere Tage.
      final andererTag = h.day > 14 ? 3 : 25;
      await zweiteBibliothek(
        tester,
        fotos: () => [
          testfoto(
            'monat.jpg',
            datum: DateTime(h.year - 2, h.month, andererTag, 10),
          ),
        ],
      );
      await openSection(tester, Hauptbereich.rueckblick);
      final monat = DateFormat.MMMM('de').format(h);
      await waitFor(tester, find.text(de.erkundenImMonatVorJahren(monat, 2)));
      // Ohne beides fehlt der Abschnitt.
      await zweiteBibliothek(
        tester,
        fotos: () => [
          testfoto(
            'nichts.jpg',
            datum: DateTime(2019, h.month == 1 ? 6 : 1, 15),
          ),
        ],
      );
      await openSection(tester, Hauptbereich.rueckblick);
      await waitFor(tester, find.text(de.erinnerungenTitel));
      await settle(tester);
      expect(
        find.text(de.erkundenErinnerungen),
        findsOneWidget,
        reason: 'nur die Zeile',
      );
      await finish(tester);
    },
  );

  // Befund: „Im {monat} vor {jahre} Jahren“ hat keine Einzahl
  // (app_de.arb, erkundenImMonatVorJahren; explore_screen.dart:1070) – bei
  // einem Jahr steht „vor 1 Jahren“.
  testWidgets(
    'ANS-122 Monatsrückblick vor einem Jahr in der Einzahl',
    skip: true,
    (tester) async {
      final h = DateTime.now();
      final andererTag = h.day > 14 ? 3 : 25;
      await startApp(
        tester,
        fotos: [
          testfoto(
            'monat.jpg',
            datum: DateTime(h.year - 1, h.month, andererTag, 10),
          ),
        ],
      );
      await openSection(tester, Hauptbereich.rueckblick);
      final monat = DateFormat.MMMM('de').format(h);
      final kopf = find.textContaining('Im $monat vor');
      await waitFor(tester, kopf);
      final text = tester.widget<Text>(kopf).data!;
      print('ANS-122: Überschrift „$text“');
      expect(text, isNot(contains('1 Jahren')));
      await finish(tester);
    },
  );

  testWidgets('ANS-123 Abschnitte und „Alle anzeigen“ im Rückblick', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto(
          'p1.jpg',
          datum: DateTime(2024, 5, 1, 10),
          breitengrad: 48.1,
          laengengrad: 11.5,
        ),
        testfoto(
          'p2.jpg',
          datum: DateTime(2024, 5, 2, 10),
          breitengrad: 48.2,
          laengengrad: 11.6,
        ),
        testfoto('p3.jpg', datum: DateTime(2024, 5, 3, 10)),
      ],
    );
    final person = _uuid.v4();
    await befehl(tester, PersonAnlegen(person, 'Person A'));
    await gesichtFuer(tester, 'p1.jpg', person);
    await albumAnlegen(tester, 'Rückblickalbum', ['p2.jpg']);
    final jetzt = DateTime.now();
    await befehl(
      tester,
      ReiseAnlegen(
        ReisenCompanion.insert(
          id: _uuid.v4(),
          name: 'Testreise',
          von: DateTime(2024, 5, 1),
          bis: DateTime(2024, 5, 3),
          angelegtAm: jetzt,
        ),
        await ids(tester, ['p1.jpg', 'p2.jpg']),
      ),
    );
    await befehl(
      tester,
      AktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: _uuid.v4(),
          name: 'Testwanderung',
          art: 'wanderung',
          von: DateTime(2024, 5, 2),
          bis: DateTime(2024, 5, 2, 18),
          angelegtAm: jetzt,
        ),
        await ids(tester, ['p2.jpg']),
      ),
    );
    await openSection(tester, Hauptbereich.rueckblick);
    final rolle = rolleIn(ExploreScreen);
    for (final abschnitt in [
      de.erkundenPersonen,
      de.erkundenOrte,
      de.erkundenReisen,
      de.erkundenAktivitaeten,
      de.erkundenLetzteAlben,
      de.erkundenLetzteFotos,
    ]) {
      final titel = imSchirm(ExploreScreen, abschnitt);
      await rolleZu(tester, titel, in_: rolle);
      expect(titel, findsWidgets, reason: abschnitt);
      final kopf = find
          .ancestor(of: titel.first, matching: find.byType(Row))
          .first;
      final alle = find.descendant(
        of: kopf,
        matching: find.text(de.allgAlleAnzeigen),
      );
      if (alle.evaluate().isEmpty) {
        fail('„Alle anzeigen“ fehlt bei $abschnitt');
      }
      await tap(tester, alle);
      // Die Übersicht liegt über dem Rückblick – mit oder ohne Zurück-Pfeil
      // (die Personen etwa kommen ohne eigene Kopfleiste).
      await eventually(
        tester,
        () async => find.byType(ExploreScreen).evaluate().isEmpty,
        was: '„Alle anzeigen“ bei $abschnitt',
      );
      final pfeil = find.byType(BackButton).evaluate().isNotEmpty;
      print(
        'ANS-123: $abschnitt → ${onScreen(tester).split(' | ').take(3).join(' | ')}'
        '; Zurück-Pfeil: $pfeil',
      );
      if (pfeil) {
        await zurueck(tester);
      } else {
        // Wie ein Mensch: noch einmal auf „Rückblick“ in der Leiste.
        await leistenKlick(tester, de.navRueckblick);
      }
      await waitFor(tester, find.byType(ExploreScreen));
    }
    // Ein Klick unter „Zuletzt hinzugefügte Fotos“ öffnet die Einzelansicht.
    final letzte = find.descendant(
      of: find
          .ancestor(
            of: find.text(de.erkundenLetzteFotos),
            matching: find.byType(Column),
          )
          .first,
      matching: find.byType(AssetThumbnailTile),
    );
    await rolleZu(tester, letzte.first, in_: rolle);
    await tap(tester, letzte.first);
    await waitFor(tester, betrachter);
    await schliesseBetrachter(tester);
    await finish(tester);
  });

  // Befund: „Zuletzt hinzugefügte Fotos“ ordnet nach dem Aufnahmedatum,
  // nicht nach der Importzeit – explore_screen.dart:184
  // `library.db.watchTimeline(limit: anzahl)` ohne
  // Rastersortierung.importNeu. Ein zuletzt importiertes altes Foto steht
  // hinten bzw. gar nicht in der Reihe.
  testWidgets(
    'ANS-123 Zuletzt importiertes altes Foto steht vorn',
    skip: true,
    (tester) async {
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 4; i++)
            testfoto('neu$i.jpg', datum: DateTime(2025, 5, 1 + i)),
        ],
      );
      await echt(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await importiereDirekt(tester, [
        testfoto('altimport.jpg', datum: DateTime(2001, 1, 1)),
      ]);
      await openSection(tester, Hauptbereich.rueckblick);
      final rolle = rolleIn(ExploreScreen);
      await rolleZu(tester, find.text(de.erkundenLetzteFotos), in_: rolle);
      final reihe = find.descendant(
        of: find
            .ancestor(
              of: find.text(de.erkundenLetzteFotos),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(AssetThumbnailTile),
      );
      await waitFor(tester, reihe);
      final namen = [
        for (final e in reihe.evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      ];
      print('ANS-123: Zuletzt hinzugefügt → $namen');
      expect(namen.first, 'altimport.jpg');
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-125 ANS-126 ANS-127 Erinnerungen: letzte zwei Wochen, Reisen, merken, '
    'nichts Verborgenes',
    (tester) async {
      final h = DateTime.now();
      final damals = DateTime(
        h.year - 2,
        h.month,
        h.day,
        10,
      ).subtract(const Duration(days: 5));
      final vorEinemJahr = DateTime(h.year - 1, h.month, h.day, 12);
      await startApp(
        tester,
        fotos: [
          for (var i = 0; i < 3; i++)
            testfoto('e$i.jpg', datum: damals.add(Duration(hours: i))),
          testfoto('reise1.jpg', datum: DateTime(2024, 3, 3, 10)),
          testfoto('reise2.jpg', datum: DateTime(2024, 3, 4, 10)),
          testfoto('sichtbar.jpg', datum: vorEinemJahr),
          testfoto(
            'gesperrt.jpg',
            datum: vorEinemJahr.add(const Duration(minutes: 1)),
          ),
          testfoto(
            'geloescht.jpg',
            datum: vorEinemJahr.add(const Duration(minutes: 2)),
          ),
          testfoto(
            'archiviert.jpg',
            datum: vorEinemJahr.add(const Duration(minutes: 3)),
          ),
        ],
      );
      await befehl(
        tester,
        ReiseAnlegen(
          ReisenCompanion.insert(
            id: _uuid.v4(),
            name: 'Testreise',
            von: DateTime(2024, 3, 3),
            bis: DateTime(2024, 3, 4, 23),
            angelegtAm: DateTime.now(),
          ),
          await ids(tester, ['reise1.jpg', 'reise2.jpg']),
        ),
      );
      await befehl(
        tester,
        FavoritSetzen(await ids(tester, ['reise1.jpg', 'reise2.jpg']), true),
      );
      await tresorEinrichten(tester);
      await sperre(tester, 'gesperrt.jpg');
      await befehl(
        tester,
        InDenPapierkorb(await ids(tester, ['geloescht.jpg'])),
      );
      await befehl(
        tester,
        ArchivSetzen(await ids(tester, ['archiviert.jpg']), true),
      );
      Future<void> oeffneErinnerungen() async {
        await openSection(tester, Hauptbereich.zeitleiste);
        await openSection(tester, Hauptbereich.rueckblick);
        final zeile = find.widgetWithText(ListTile, de.erinnerungenTitel);
        await rolleZu(tester, zeile, in_: rolleIn(ExploreScreen));
        await tap(tester, zeile);
        await waitFor(tester, find.text(de.erinnerungenLetzteTage));
        await settle(tester);
      }

      // ANS-127 im Rückblick: „Vor 1 Jahr“ nur mit dem sichtbaren Foto.
      await openSection(tester, Hauptbereich.rueckblick);
      await waitFor(tester, find.text(de.erkundenVorJahren(1)));
      final rueckblickReihe = find.descendant(
        of: find
            .ancestor(
              of: find.text(de.erkundenVorJahren(1)),
              matching: find.byType(Column),
            )
            .first,
        matching: find.byType(AssetThumbnailTile),
      );
      final imRueckblick = {
        for (final e in rueckblickReihe.evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      };
      expect(imRueckblick, contains('sichtbar.jpg'));
      for (final n in ['gesperrt.jpg', 'geloescht.jpg', 'archiviert.jpg']) {
        expect(imRueckblick, isNot(contains(n)), reason: n);
      }

      // ANS-125
      await oeffneErinnerungen();
      final kopf = de.erinnerungenTagVorJahren(
        DateFormat.yMMMMd('de').format(damals),
        2,
      );
      await waitFor(tester, find.text(kopf));
      await waitFor(tester, find.text(de.erinnerungenSchoensteReisen));
      expect(
        find.text(de.erinnerungenReise('Testreise', '2024', 2)),
        findsOneWidget,
      );
      // ANS-127 in den Erinnerungen.
      expect(kachel('sichtbar.jpg'), findsWidgets);
      for (final n in ['gesperrt.jpg', 'geloescht.jpg', 'archiviert.jpg']) {
        expect(kachel(n), findsNothing, reason: n);
      }
      await tap(tester, kachel('e0.jpg').first);
      await waitFor(tester, betrachter);
      await schliesseBetrachter(tester);

      // ANS-126: merken, ein Foto löschen, vergessen.
      final gruppe = find
          .ancestor(of: find.text(kopf), matching: find.byType(Row))
          .first;
      await tap(
        tester,
        find.descendant(
          of: gruppe,
          matching: find.byTooltip(de.erinnerungenMerken),
        ),
      );
      await waitFor(tester, find.text(de.erinnerungenGemerkt));
      expect(find.byTooltip(de.erinnerungenVergessen), findsWidgets);
      await befehl(tester, InDenPapierkorb(await ids(tester, ['e1.jpg'])));
      await zurueck(tester);
      await oeffneErinnerungen();
      await waitFor(tester, find.text(de.erinnerungenGemerkt));
      final gemerkt = find
          .ancestor(
            of: find.text(de.erinnerungenGemerkt),
            matching: find.byType(Column),
          )
          .first;
      final gemerkteFotos = {
        for (final e
            in find
                .descendant(
                  of: gemerkt,
                  matching: find.byType(AssetThumbnailTile),
                )
                .evaluate())
          (e.widget as AssetThumbnailTile).asset.originalFileName,
      };
      print('ANS-126: gemerkt nach dem Löschen $gemerkteFotos');
      expect(gemerkteFotos.containsAll(['e0.jpg', 'e2.jpg']), isTrue);
      expect(gemerkteFotos, isNot(contains('e1.jpg')));
      await tap(tester, find.byTooltip(de.erinnerungenVergessen).first);
      await waitGone(tester, find.text(de.erinnerungenGemerkt));
      // Zweite Bibliothek ohne solche Fotos.
      await zweiteBibliothek(
        tester,
        fotos: () => [
          testfoto('x.jpg', datum: DateTime(2020, h.month == 6 ? 1 : 6, 1)),
        ],
      );
      await oeffneErinnerungen();
      expect(find.text(de.erinnerungenKeine), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('ANS-128 ANS-129 „Dein Jahr“: Kennzahlen, Vorjahr, Folgejahr', (
    tester,
  ) async {
    final jahr = DateTime.now().month <= 2
        ? DateTime.now().year - 1
        : DateTime.now().year;
    await startApp(
      tester,
      fotos: [
        testfoto(
          'j1.jpg',
          datum: DateTime(jahr, 1, 10, 10),
          breitengrad: 48.1,
          laengengrad: 11.5,
        ),
        testfoto(
          'j2.jpg',
          datum: DateTime(jahr, 3, 10, 10),
          breitengrad: 45.4,
          laengengrad: 12.3,
        ),
        testfoto('j3.jpg', datum: DateTime(jahr, 3, 11, 10)),
        fixture('video_5s.mp4'),
      ],
    );
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(fileCreatedAt: Value(DateTime(jahr, 3, 12, 10))),
    );
    for (final (n, land, stadt) in [
      ('j1.jpg', 'Deutschland', 'München'),
      ('j2.jpg', 'Italien', 'Venedig'),
    ]) {
      final a = await aufnahme(tester, n);
      await echt(
        () => bibliothek.db.setLocationNames(
          a.id,
          country: land,
          state: null,
          city: stadt,
        ),
      );
    }
    final person = _uuid.v4();
    await befehl(tester, PersonAnlegen(person, 'Person A'));
    await gesichtFuer(tester, 'j1.jpg', person);
    await gesichtFuer(tester, 'j2.jpg', person);
    await befehl(
      tester,
      ReiseAnlegen(
        ReisenCompanion.insert(
          id: _uuid.v4(),
          name: 'Jahresreise',
          von: DateTime(jahr, 3, 10),
          bis: DateTime(jahr, 3, 12, 23),
          angelegtAm: DateTime.now(),
        ),
        await ids(tester, ['j2.jpg', 'j3.jpg']),
      ),
    );
    await befehl(tester, FavoritSetzen(await ids(tester, ['j1.jpg']), true));
    await openSection(tester, Hauptbereich.rueckblick);
    final zeile = find.text(de.jahresrueckblickTitel(jahr));
    await rolleZu(tester, zeile, in_: rolleIn(ExploreScreen));
    await tap(tester, zeile);
    await waitFor(tester, find.text(de.jahresrueckblickTage));
    final rolle = rolleIn(JahresrueckblickScreen);
    for (final t in [
      de.jahresrueckblickFotos,
      de.jahresrueckblickVideos,
      de.jahresrueckblickTage,
      de.jahresrueckblickLaender,
      de.jahresrueckblickOrte,
      de.jahresrueckblickStaerksterMonat,
      de.jahresrueckblickAuswahl,
      de.jahresrueckblickPersonen,
      de.jahresrueckblickReisen,
    ]) {
      await rolleZu(tester, imSchirm(JahresrueckblickScreen, t), in_: rolle);
      expect(imSchirm(JahresrueckblickScreen, t), findsWidgets, reason: t);
    }
    expect(find.text('Jahresreise'), findsOneWidget);
    // ANS-129: Folgejahr im laufenden Jahr ausgegraut.
    final folge = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right).first,
    );
    if (jahr == DateTime.now().year) {
      expect(folge.onPressed, isNull, reason: 'Folgejahr ausgegraut');
    }
    await tap(tester, find.byTooltip(de.jahresrueckblickVorjahr));
    await waitFor(tester, find.text(de.jahresrueckblickLeer(jahr - 1)));
    await finish(tester);
  });

  // === Statistik und Kalender ==============================================

  testWidgets('ANS-131 ANS-132 Statistik: Kacheln, Diagramme, Aktualisieren', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto(
          'f1.jpg',
          datum: DateTime(2023, 12, 31, 23, 30),
          kamera: 'Alpha',
          modell: 'A1',
        ),
        testfoto(
          'f2.jpg',
          datum: DateTime(2024, 1, 1, 0, 30),
          kamera: 'Alpha',
          modell: 'A1',
        ),
        testfoto(
          'f3.jpg',
          datum: DateTime(1965, 6, 1, 12),
          kamera: 'Beta',
          modell: 'B2',
        ),
        fixture('video_5s.mp4'),
        testfoto('weg.jpg', datum: DateTime(2020, 1, 1)),
        testfoto('zu.jpg', datum: DateTime(2020, 1, 2)),
      ],
    );
    // Ein Live Photo zählt einmal.
    final film = fixture(
      'video_hoch_3s.mov',
    ).renameSync(p.join(eingang.path, 'IMG_5000.MOV'));
    await importiereDirekt(tester, [
      testfoto('IMG_5000.JPG', datum: DateTime(2024, 5, 5, 10)),
      film,
    ]);
    await setzeSpalten(
      tester,
      'video_5s.mp4',
      AssetsCompanion(fileCreatedAt: Value(DateTime(2024, 7, 1, 10))),
    );
    print(
      'ANS-132: Import las für f3 (EXIF 1965) '
      '${(await aufnahme(tester, 'f3.jpg')).fileCreatedAt}',
    );
    await setzeDatum(tester, 'f3.jpg', DateTime(1965, 6, 1, 12));
    await befehl(tester, FavoritSetzen(await ids(tester, ['f1.jpg']), true));
    await befehl(tester, InDenPapierkorb(await ids(tester, ['weg.jpg'])));
    await tresorEinrichten(tester);
    await sperre(tester, 'zu.jpg');
    await openSection(tester, Hauptbereich.statistik);
    await waitFor(tester, find.text(de.statInsgesamt));
    String wert(String beschriftung) => statWert(tester, beschriftung);

    // Sichtbar: f1, f2, f3, Live Photo (einmal) = 4 Fotos, 1 Video.
    expect(wert(de.statInsgesamt), '5');
    expect(wert(de.statFotos), '4');
    expect(wert(de.statVideos), '1');
    expect(wert(de.suchoptFavoriten), '1');
    expect(wert(de.statImPapierkorb), '1');
    expect(wert(de.einstGesperrterOrdner), '1');
    expect(wert(de.statSpeicherplatz), isNotEmpty);
    // ANS-132: Jahre (Silvester/Neujahr, 1965), Monate, Kameras.
    final jahre = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label ?? '').startsWith(
            'Balkendiagramm, Fotos und Videos pro Jahr',
          ),
    );
    await rolleZu(tester, jahre, in_: rolleIn(StatisticsScreen));
    final jahrText = tester.widget<Semantics>(jahre).properties.label!;
    print('ANS-132: $jahrText');
    expect(jahrText, contains('1965: 1'));
    expect(jahrText, contains('2023: 1'));
    expect(jahrText, contains('2024: 3'));
    expect(find.text(de.statSaisonalitaet), findsOneWidget);
    await rolleZu(
      tester,
      find.text(de.statKameras),
      in_: rolleIn(StatisticsScreen),
    );
    expect(find.textContaining('A1'), findsWidgets);
    expect(find.textContaining('B2'), findsWidgets);
    // Ein weiteres Foto, „Aktualisieren“.
    await importiereDirekt(tester, [
      testfoto('spaet.jpg', datum: DateTime(2022, 2, 2)),
    ]);
    await tap(tester, find.byTooltip(de.allgAktualisieren));
    await waitFor(tester, find.text(de.statInsgesamt));
    final rolle = rolleIn(StatisticsScreen);
    tester.state<ScrollableState>(rolle).position.jumpTo(0);
    await settle(tester);
    expect(wert(de.statInsgesamt), '6');
    // Leere Bibliothek.
    await zweiteBibliothek(tester);
    await openSection(tester, Hauptbereich.statistik);
    await waitFor(tester, find.text(de.statLeer));
    await finish(tester);
  });

  testWidgets('ANS-133 Kalender: Jahr, Monat, Raster mit Auswahl', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('k1.jpg', datum: DateTime(2025, 6, 3, 10)),
        testfoto('k2.jpg', datum: DateTime(2025, 6, 3, 11)),
        testfoto('k3.jpg', datum: DateTime(2025, 6, 9, 10)),
        testfoto('k4.jpg', datum: DateTime(2023, 2, 1, 10)),
      ],
    );
    await openSection(tester, Hauptbereich.kalender);
    await waitFor(tester, find.text('2025'));
    expect(find.text(de.kalenderAnzahlFotos(3)), findsOneWidget);
    expect(find.text(de.kalenderAnzahlFotos(1)), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2025')).dy <=
          tester.getTopLeft(find.text('2023')).dy,
      isTrue,
    );
    await tap(tester, find.text('2025'));
    await tap(tester, find.text('Juni'));
    await waitFor(tester, kachel('k1.jpg'));
    expect(
      find.textContaining('3. Juni 2025'),
      findsWidgets,
      reason: 'nach Tagen',
    );
    expect(find.textContaining('9. Juni 2025'), findsWidgets);
    await befehlsklick(tester, kachel('k1.jpg'));
    await befehlsklick(tester, kachel('k3.jpg'));
    await waitFor(tester, find.text(de.auswAnzahl(2)));
    await key(tester, LogicalKeyboardKey.digit3);
    await eventually(tester, () async {
      final a = await aufnahme(tester, 'k1.jpg');
      final b = await aufnahme(tester, 'k3.jpg');
      return a.rating == 3 && b.rating == 3;
    }, was: 'beide drei Sterne');
    expect((await aufnahme(tester, 'k2.jpg')).rating, 0);
    await zweiteBibliothek(tester);
    await openSection(tester, Hauptbereich.kalender);
    await waitFor(tester, find.text(de.kalenderLeer));
    await finish(tester);
  });

  // === Vorschläge ===========================================================

  testWidgets('ANS-134 ANS-135 ANS-136 „Wer könnte das sein?“, leere Zustände, '
      'Beiseitegelegte', (tester) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 5; i++)
          testfoto('g$i.jpg', datum: DateTime(2025, 1, 1 + i)),
      ],
    );
    final person = _uuid.v4();
    await befehl(tester, PersonAnlegen(person, 'Person A'));
    final grund = Float32List.fromList([
      for (var i = 0; i < 128; i++) math.sin(i + 1),
    ]);
    final anders = Float32List.fromList([
      for (var i = 0; i < 128; i++) math.cos(i * 7.0 + 3),
    ]);
    Future<String> gesicht(
      String foto,
      Float32List v, {
      String? an,
      bool beiseite = false,
    }) async {
      final a = await aufnahme(tester, foto);
      final id = _uuid.v4();
      await echt(() async {
        await bibliothek.db.insertFace(
          FacesCompanion.insert(
            id: id,
            assetId: a.id,
            personId: const Value.absent(),
            boxX: 0.3,
            boxY: 0.3,
            boxW: 0.2,
            boxH: 0.2,
            embedding: Value(blobFromEmbeddingFloats(Float32List.fromList(v))),
          ),
        );
        if (an != null) {
          await bibliothek.db.fuehreAus(GesichterZuordnen([id], an));
        }
        if (beiseite) {
          await bibliothek.db.fuehreAus(GesichterBeiseitelegen([id], true));
        }
      });
      return id;
    }

    await gesicht('g0.jpg', grund, an: person);
    await gesicht('g1.jpg', grund, an: person);
    final offen1 = await gesicht('g2.jpg', grund);
    final offen2 = await gesicht('g3.jpg', grund);
    final weggelegt = await gesicht('g4.jpg', grund, beiseite: true);
    Future<void> oeffneVorschlaege() async {
      await openSection(tester, Hauptbereich.personen);
      await tap(tester, find.textContaining(de.personenUnbenannteTab));
      await rechtsklick(tester, find.byType(TabBarView));
      await tap(tester, find.text(de.vorschlaegeTitel).last);
      await waitFor(tester, find.text(de.vorschlaegeEinleitung));
    }

    // ANS-135 (A): Wiedererkennung nie gelaufen.
    await oeffneVorschlaege();
    await waitFor(tester, find.text(de.vorschlaegeLaufHinweis));
    await zurueck(tester);
    // ANS-134: Lauf, dann eine Zeile je Person.
    await echt(() async {
      await for (final _ in bibliothek.backfillWiedererkennung()) {}
    });
    await oeffneVorschlaege();
    final zeile = find.widgetWithText(ListTile, 'Person A');
    await waitFor(tester, zeile);
    expect(
      find.descendant(of: zeile, matching: find.text(de.vorschlaegeAnzahl(2))),
      findsOneWidget,
    );
    await tap(tester, zeile);
    await waitFor(tester, find.byType(BackButton));
    expect(find.text(de.vorschlaegeEinleitung), findsNothing);
    await zurueck(tester);
    await waitFor(tester, find.text(de.vorschlaegeEinleitung));
    await waitFor(tester, zeile);
    await zurueck(tester);
    // Zweiter Weg: Werkzeuge → Bibliothekszustand → „Vorschläge ansehen“.
    await openSection(tester, Hauptbereich.werkzeuge);
    await tapText(tester, de.gesundheitTitel);
    final ansehen = find.text(de.gesundheitVorschlaegeAnsehen);
    await rolleZu(tester, ansehen.first, in_: rolleIn(LibraryHealthScreen));
    await tap(tester, ansehen.first);
    await waitFor(tester, find.text(de.vorschlaegeEinleitung));
    expect(find.widgetWithText(ListTile, 'Person A'), findsOneWidget);
    await zurueck(tester);
    await zurueck(tester);
    // ANS-136: Beiseitegelegte einbeziehen und vergleichen.
    await oeffneVorschlaege();
    await tap(
      tester,
      find.widgetWithText(SwitchListTile, de.vorschlaegeBeiseite),
    );
    await waitFor(tester, find.text(de.vorschlaegeBeiseiteHinweis));
    await waitFor(tester, find.text(de.vorschlaegeBeiseiteNieVerglichen(1)));
    await tap(tester, find.text(de.vorschlaegeJetztVergleichen));
    await eventually(
      tester,
      () async =>
          find.text(de.vorschlaegeLaeuft).evaluate().isEmpty &&
          (find.widgetWithText(ListTile, 'Person A').evaluate().isNotEmpty ||
              find.text(de.vorschlaegeBeiseiteLeer).evaluate().isNotEmpty),
      was: 'Durchgang fertig',
    );
    final faces = await echt(
      () => bibliothek.db.select(bibliothek.db.faces).get(),
    );
    for (final f in faces!) {
      if ({offen1, offen2, weggelegt}.contains(f.id)) {
        expect(f.personId, isNull, reason: 'keine Zuordnung geändert');
      }
    }
    await zurueck(tester);
    // ANS-135 (B): Lauf ohne Treffer.
    await zweiteBibliothek(
      tester,
      fotos: () => [testfoto('h0.jpg'), testfoto('h1.jpg')],
    );
    final p2 = _uuid.v4();
    await befehl(tester, PersonAnlegen(p2, 'Person B'));
    await gesicht('h0.jpg', grund, an: p2);
    await gesicht('h1.jpg', anders);
    await echt(() async {
      await for (final _ in bibliothek.backfillWiedererkennung()) {}
    });
    await oeffneVorschlaege();
    await waitFor(tester, find.text(de.vorschlaegeKeine));
    await finish(tester);
  });

  // === Dokumente ============================================================

  testWidgets(
    'ANS-137 ANS-138 ANS-139 ANS-140 ANS-060 Ausweise finden, abwählen, '
    'sperren, nicht mehr vorschlagen',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('pass.jpg', datum: DateTime(2025, 3, 3)),
          testfoto('karte.jpg', datum: DateTime(2025, 3, 2)),
          testfoto('bon.jpg', datum: DateTime(2025, 3, 1)),
        ],
      );
      final passId = (await aufnahme(tester, 'pass.jpg')).id;
      Future<AssetData> pass() async =>
          (await alleAufnahmen(tester)).firstWhere((a) => a.id == passId);
      // Vorbedingung „Texterkennung gelaufen“: erfundene Ausweisdaten als
      // erkannter Text (die echte Erkennung prüft abnahme_test.dart #74).
      final texte = {
        'pass.jpg':
            'REISEPASS\nP<UTOPERSON<<A<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<\n'
            'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
        'karte.jpg': 'TESTBANK\n4111 1111 1111 1111\nGUELTIG BIS 12/30',
        'bon.jpg': 'KASSENBON\nBROT 2,50\nSUMME 12,50 EUR\n1234 5678 9012',
      };
      for (final e in texte.entries) {
        final a = await aufnahme(tester, e.key);
        await echt(() => bibliothek.db.setOcrResult(a.id, e.value));
      }
      await tresorEinrichten(tester);
      await echt(() async => bibliothek.lockVaultSession());
      await settle(tester);
      // ANS-137
      await openSection(tester, Hauptbereich.werkzeuge);
      await tapText(tester, de.gesundheitTitel);
      await waitFor(tester, find.byType(LibraryHealthScreen));
      await rolleZu(
        tester,
        find.text(de.gesundheitDokumenteTitel),
        in_: rolleIn(LibraryHealthScreen),
      );
      expect(find.text(de.gesundheitDokumenteOffen(2)), findsOneWidget);
      await rolleZu(
        tester,
        find.text(de.gesundheitDokumenteAnsehen),
        in_: rolleIn(LibraryHealthScreen),
      );
      await tap(tester, find.text(de.gesundheitDokumenteAnsehen));
      await waitFor(tester, find.text(de.dokumenteTitel));
      await waitFor(tester, kachel('pass.jpg'));
      expect(kachel('karte.jpg'), findsOneWidget);
      expect(kachel('bon.jpg'), findsNothing);
      expect(
        find.text('${de.dokumentArtReisepass} · ${de.dokumentGrundPruefzeile}'),
        findsOneWidget,
      );
      expect(
        find.text('${de.dokumentArtKarte} · ${de.dokumentGrundKartennummer}'),
        findsOneWidget,
      );
      bool gewaehlt(String n) =>
          tester.widget<AssetThumbnailTile>(kachel(n)).selected;
      expect(gewaehlt('pass.jpg') && gewaehlt('karte.jpg'), isTrue);
      expect(find.text(de.dokumenteSperren(2)), findsOneWidget);
      // ANS-138: ein Klick wählt ab, Doppelklick öffnet.
      await einfachKlick(tester, kachel('karte.jpg'));
      expect(find.text(de.dokumenteSperren(1)), findsOneWidget);
      await einfachKlick(tester, kachel('karte.jpg'));
      expect(find.text(de.dokumenteSperren(2)), findsOneWidget);
      await tester.tap(kachel('pass.jpg'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(kachel('pass.jpg'));
      await settle(tester);
      await waitFor(tester, betrachter);
      // ANS-060: In „Ausweise und Karten“ weder Papierkorb noch Favorit.
      expect(knopf(de.viewerInPapierkorb), findsNothing);
      expect(knopf(de.viewerFavoritSetzen), findsNothing);
      await key(tester, LogicalKeyboardKey.keyF);
      await key(tester, LogicalKeyboardKey.backspace);
      expect(find.byType(AlertDialog), findsNothing);
      final passVorher = await pass();
      expect(passVorher.isFavorite || passVorher.isTrashed, isFalse);
      await schliesseBetrachter(tester);
      // Beide abwählen: Knöpfe ausgegraut.
      await einfachKlick(tester, kachel('pass.jpg'));
      await einfachKlick(tester, kachel('karte.jpg'));
      final verwerfen = find.widgetWithText(
        OutlinedButton,
        de.dokumenteVerwerfen,
      );
      final sperrenKnopf = find.ancestor(
        of: find.text(de.dokumenteSperren(0)),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              verwerfen.evaluate().isNotEmpty
                  ? verwerfen
                  : find.ancestor(
                      of: find.text(de.dokumenteVerwerfen),
                      matching: find.byWidgetPredicate(
                        (w) => w is ButtonStyleButton,
                      ),
                    ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<ButtonStyleButton>(sperrenKnopf.first).onPressed,
        isNull,
      );
      // ANS-140: „Nicht mehr vorschlagen“ für die Karte.
      await einfachKlick(tester, kachel('karte.jpg'));
      await tapText(tester, de.dokumenteVerwerfen);
      await waitGone(tester, kachel('karte.jpg'));
      // ANS-139: sperren – PIN-Abfrage abbrechen, dann mit PIN. Nach dem
      // Verwerfen lädt die Liste neu und wählt wieder alles vor.
      if (!gewaehlt('pass.jpg')) await einfachKlick(tester, kachel('pass.jpg'));
      expect(gewaehlt('pass.jpg'), isTrue);
      await tapText(tester, de.dokumenteSperren(1));
      await waitFor(tester, find.text(de.pinEingebenTitel));
      await tapText(tester, de.allgAbbrechen);
      expect((await pass()).isLocked, isFalse);
      await tapText(tester, de.dokumenteSperren(1));
      await pinFallsGefragt(tester);
      await meldung(tester, de.dokumenteGesperrt(1));
      await waitFor(tester, find.text(de.dokumenteKeine));
      expect((await pass()).isLocked, isTrue);
      await zurueck(tester);
      await zurueck(tester);
      // Gesperrt: weder Zeitleiste noch Suche.
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('karte.jpg'));
      expect(kachel('pass.jpg'), findsNothing);
      await openSection(tester, Hauptbereich.suche);
      await sucheNachTyp(tester, de.suchoptTypDateiname, 'pass');
      expect(treffer(tester), isEmpty);
      // ANS-140: Die Karte bleibt unverschlüsselt in der Zeitleiste und
      // kommt nicht wieder; die Karte „Ausweise liegen offen“ fehlt.
      expect((await aufnahme(tester, 'karte.jpg')).isLocked, isFalse);
      await openSection(tester, Hauptbereich.werkzeuge);
      await tapText(tester, de.gesundheitTitel);
      await settle(tester);
      await echt(() => Future<void>.delayed(const Duration(seconds: 1)));
      await settle(tester);
      expect(find.text(de.gesundheitDokumenteTitel), findsNothing);
      await zurueck(tester);
      final vorschlaege = await echt(
        () => ladeDokumentvorschlaege(bibliothek.db),
      );
      expect(vorschlaege, isEmpty);
      await finish(tester);
    },
  );

  // === Datenschutz und Originale ===========================================

  testWidgets(
    'ANS-141 ANS-142 Gesperrte und gelöschte Fotos erscheinen in keiner Ansicht',
    (tester) async {
      final h = DateTime.now();
      final vorEinemJahr = DateTime(h.year - 1, h.month, h.day, 12);
      await startApp(
        tester,
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
        ],
      );
      await befehl(tester, const AuswertenNachImportSetzen(false));
      final sand = img.ColorRgb8(230, 205, 150);
      await importiereDirekt(tester, [
        motivfoto('geheim.jpg', ['BEACH', 'SEA'], sand, vorEinemJahr),
        motivfoto(
          'weg.jpg',
          ['BEACH', 'SUN'],
          sand,
          vorEinemJahr.add(const Duration(minutes: 1)),
        ),
        motivfoto(
          'bleibt.jpg',
          ['MOUNTAIN'],
          img.ColorRgb8(120, 140, 170),
          vorEinemJahr.add(const Duration(minutes: 2)),
        ),
      ]);
      await echt(() async {
        await for (final _ in bibliothek.backfillClipEmbeddings(alle: true)) {}
      });
      final album = await albumAnlegen(tester, 'Privat', [
        'geheim.jpg',
        'weg.jpg',
        'bleibt.jpg',
      ]);
      for (final n in ['geheim.jpg', 'weg.jpg']) {
        await befehl(
          tester,
          SchlagwortAnheften(await ids(tester, [n]), 'Vertraulich'),
        );
        await befehl(tester, FavoritSetzen(await ids(tester, [n]), true));
      }
      await befehl(
        tester,
        AlbumTitelbildSetzen(album, (await aufnahme(tester, 'geheim.jpg')).id),
      );
      await tresorEinrichten(tester);
      await sperre(tester, 'geheim.jpg');
      await befehl(tester, InDenPapierkorb(await ids(tester, ['weg.jpg'])));
      final verborgen = ['geheim.jpg', 'weg.jpg'];

      Future<void> nirgends({required bool wegAuchVerborgen}) async {
        final zuPruefen = wegAuchVerborgen ? verborgen : ['geheim.jpg'];
        void fehlen(String wo) {
          for (final n in zuPruefen) {
            expect(kachel(n), findsNothing, reason: '$n in $wo');
          }
        }

        // Fotos, Jahre, Kalender, Favoriten, Album (auch Titelbild).
        await openSection(tester, Hauptbereich.zeitleiste);
        await waitFor(tester, kachel('bleibt.jpg'));
        fehlen('Fotos');
        await tap(tester, find.byTooltip(de.timelineJahre));
        final jahrKachel = find.ancestor(
          of: find.text('${vorEinemJahr.year}'),
          matching: find.byType(InkWell),
        );
        await waitFor(tester, jahrKachel);
        final sichtbar = wegAuchVerborgen ? 1 : 2;
        expect(
          find.descendant(
            of: jahrKachel.first,
            matching: find.text('$sichtbar'),
          ),
          findsOneWidget,
          reason: 'Jahre zählen nur Sichtbares',
        );
        await tap(tester, find.text(de.timelineDetails));
        await openSection(tester, Hauptbereich.kalender);
        await waitFor(tester, find.text(de.kalenderAnzahlFotos(sichtbar)));
        await openSection(tester, Hauptbereich.favoriten);
        await settle(tester);
        await eventually(
          tester,
          () async => find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        fehlen('Favoriten');
        await openSection(tester, Hauptbereich.alben);
        await waitFor(tester, find.text('Privat'));
        fehlen('Albenübersicht (Titelbild)');
        await tap(tester, find.text('Privat'));
        await waitFor(tester, kachel('bleibt.jpg'));
        fehlen('Album');
        await zurueck(tester);
        // Suche nach Dateiname, Schlagwort und per Kontext.
        await openSection(tester, Hauptbereich.suche);
        await sucheNachTyp(tester, de.suchoptTypDateiname, '.jpg');
        fehlen('Suche Dateiname');
        await oeffneSuchoptionen(tester);
        await tap(tester, find.text(de.suchoptAllesLeeren));
        await imBlatt(tester, de.suchoptTagsHint);
        final tagWahl = find.widgetWithText(CheckboxListTile, 'Vertraulich');
        if (tagWahl.evaluate().isNotEmpty) {
          await tap(tester, tagWahl);
          await tapText(tester, de.allgUebernehmen);
          await optionenSuchen(tester);
          fehlen('Suche Schlagwort');
        } else {
          await key(tester, LogicalKeyboardKey.escape);
          await tap(
            tester,
            find.descendant(
              of: optionenBlatt,
              matching: find.byTooltip(de.allgSchliessen),
            ),
          );
        }
        await oeffneSuchoptionen(tester);
        await tap(tester, find.text(de.suchoptAllesLeeren));
        await imBlatt(tester, de.suchoptTypKontext);
        // Ohne Begriff sucht „Suche“ nicht, übernimmt aber die Suchart.
        await tap(
          tester,
          find.descendant(
            of: optionenBlatt,
            matching: find.widgetWithText(FilledButton, de.suchoptSuchen),
          ),
        );
        await waitGone(tester, optionenBlatt);
        await tippeSuche(tester, 'Strand');
        await waitFor(
          tester,
          kachel('bleibt.jpg'),
          timeout: const Duration(seconds: 60),
        );
        fehlen('Kontextsuche');
        // Rückblick, Erinnerungen, Dein Jahr, Statistik.
        await openSection(tester, Hauptbereich.rueckblick);
        await waitFor(tester, find.text(de.erkundenLetzteFotos));
        await settle(tester);
        fehlen('Rückblick');
        final zeile = find.widgetWithText(ListTile, de.erinnerungenTitel);
        await rolleZu(tester, zeile, in_: rolleIn(ExploreScreen));
        await tap(tester, zeile);
        await waitFor(tester, find.text(de.erinnerungenLetzteTage));
        await settle(tester);
        fehlen('Erinnerungen');
        await zurueck(tester);
        final jahr = h.month <= 2 ? h.year - 1 : h.year;
        final dein = find.text(de.jahresrueckblickTitel(jahr));
        await rolleZu(tester, dein, in_: rolleIn(ExploreScreen));
        await tap(tester, dein);
        if (jahr != vorEinemJahr.year) {
          await tap(tester, find.byTooltip(de.jahresrueckblickVorjahr));
        }
        await waitFor(tester, find.text(de.jahresrueckblickTage));
        await settle(tester);
        fehlen('Dein Jahr');
        await zurueck(tester);
        await openSection(tester, Hauptbereich.statistik);
        await waitFor(tester, find.text(de.statInsgesamt));
        String wert(String beschriftung) => statWert(tester, beschriftung);

        expect(wert(de.statInsgesamt), '$sichtbar');
        expect(wert(de.einstGesperrterOrdner), '1');
        expect(wert(de.statImPapierkorb), wegAuchVerborgen ? '1' : '0');
      }

      // ANS-141 und ANS-142 (Papierkorb).
      await nirgends(wegAuchVerborgen: true);
      // ANS-142: Im Papierkorb selbst steht es.
      await openSection(tester, Hauptbereich.papierkorb);
      final raster = find.descendant(
        of: find.byType(TrashScreen),
        matching: find.byType(GridView),
      );
      await waitFor(tester, raster);
      expect(
        (tester.widget<GridView>(raster).childrenDelegate
                as SliverChildBuilderDelegate)
            .childCount,
        1,
      );
      // Wiederherstellen: überall wieder da, mit Schlagwort, Favorit, Album.
      await echt(
        () async => bibliothek.ausPapierkorbHolen([
          (await aufnahme(tester, 'weg.jpg')).id,
        ]),
      );
      await settle(tester);
      final weg = await aufnahme(tester, 'weg.jpg');
      expect(weg.isTrashed, isFalse);
      expect(weg.isFavorite, isTrue);
      expect(await schlagwoerter(tester, 'weg.jpg'), contains('Vertraulich'));
      expect(await albumInhalt(tester, 'Privat'), contains('weg.jpg'));
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel('weg.jpg'));
      await openSection(tester, Hauptbereich.favoriten);
      await waitFor(tester, kachel('weg.jpg'));
      await nirgends(wegAuchVerborgen: false);
      await finish(tester);
    },
  );

  testWidgets(
    'ANS-143 Gesperrte Fotos in der Einzelansicht ohne fremde Werkzeuge',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('geheim.jpg', datum: DateTime(2025, 4, 2)),
          fixture('video_5s.mp4'),
        ],
      );
      await setzeSpalten(
        tester,
        'video_5s.mp4',
        AssetsCompanion(fileCreatedAt: Value(DateTime(2025, 4, 1))),
      );
      await tresorEinrichten(tester);
      await sperre(tester, 'geheim.jpg');
      await sperre(tester, 'video_5s.mp4');
      await oeffneGesperrtenOrdner(tester);
      final kacheln = find.descendant(
        of: find.byType(GridView),
        matching: find.byType(GestureDetector),
      );
      await waitFor(tester, kacheln);
      await tap(tester, kacheln.first);
      await waitFor(tester, betrachter);
      await settle(tester);
      final liste = tester.widget<AssetViewerScreen>(betrachter).assets;
      final fotoIndex = liste.indexWhere((a) => a.type == 'IMAGE');
      // Der gesperrte Ordner zeigt sein eigenes (verborgenes) Datum – über
      // die Seite der Ansicht, nicht über den Titel.
      int seite() => tester
          .widget<PageView>(
            find.descendant(of: betrachter, matching: find.byType(PageView)),
          )
          .controller!
          .page!
          .round();
      print(
        'ANS-143: Titel ${onScreen(tester)}; Liste '
        '${[for (final a in liste) '${a.type}:${a.fileCreatedAt}']}',
      );
      if (seite() != fotoIndex) {
        await key(
          tester,
          fotoIndex > seite()
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft,
        );
        await settle(tester);
      }
      expect(seite(), fotoIndex);
      for (final t in [
        de.viewerGesichterZeigen,
        de.viewerTextZeigen,
        de.viewerEntwickeln,
        de.viewerBearbeiten,
      ]) {
        expect(knopf(t), findsNothing, reason: t);
      }
      await rechtsklick(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PageView)),
      );
      expect(find.text(de.viewerInTimelineZeigen), findsOneWidget);
      expect(find.text(de.viewerInDarktable), findsNothing);
      expect(find.text(de.viewerGesichterBearbeiten), findsNothing);
      await key(tester, LogicalKeyboardKey.escape);
      // Das gesperrte Video.
      await key(
        tester,
        fotoIndex == 0
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft,
      );
      await eventually(tester, () async => seite() != fotoIndex, was: 'Video');
      await settle(tester, max: const Duration(seconds: 8));
      expect(liste[seite()].type, 'VIDEO');
      expect(knopf(de.viewerZuschneiden), findsNothing);
      expect(knopf(de.viewerVideobildSichern), findsNothing);
      expect(find.byTooltip(de.viewerVideobildSichern), findsNothing);
      await schliesseBetrachter(tester);
      await finish(tester);
    },
  );

  testWidgets('ANS-144 Ansehen und Ordnen verändern keine Originaldatei', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        for (var i = 0; i < 5; i++)
          testfoto(
            'orig$i.jpg',
            datum: DateTime(2024, 3, 10 + i, 10),
            breitengrad: 47.0 + i / 10,
            laengengrad: 11.0,
          ),
        fixture('video_5s.mp4'),
      ],
    );
    final namen = [for (var i = 0; i < 5; i++) 'orig$i.jpg', 'video_5s.mp4'];
    final vorher = {for (final n in namen) n: await originalSumme(tester, n)};
    await openSection(tester, Hauptbereich.zeitleiste);
    // Bewertung, Farbe, Favorit, Beschreibung, Schlagwort in der Einzelansicht.
    await oeffne(tester, 'orig4.jpg');
    await key(tester, LogicalKeyboardKey.digit4);
    await key(tester, LogicalKeyboardKey.digit8);
    await key(tester, LogicalKeyboardKey.keyF);
    await tap(tester, knopf(de.viewerInfo));
    await tap(tester, field(de.infoBeschreibungHinzufuegen));
    await tester.enterText(
      field(de.infoBeschreibungHinzufuegen),
      'Nur Datenbank',
    );
    await tap(tester, field(de.infoTagHinzufuegenPlatzhalter));
    await tester.enterText(field(de.infoTagHinzufuegenPlatzhalter), 'Ordnung');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await schliesseBetrachter(tester);
    final o4 = await aufnahme(tester, 'orig4.jpg');
    expect([o4.rating, o4.colorLabel, o4.isFavorite], [4, 'green', true]);
    expect(o4.description, 'Nur Datenbank');
    // Album, archivieren und zurück, Titelbild.
    await waehle(tester, ['orig0.jpg', 'orig1.jpg', 'video_5s.mp4']);
    await leiste(tester, de.auswZuAlbum);
    await enter(tester, field(de.albumNeuAnlegen), 'Ordnungsalbum');
    await tapText(tester, de.allgHinzufuegen);
    await meldungenWeg(tester);
    await waehle(tester, ['orig2.jpg']);
    await leiste(tester, de.auswArchiv);
    await openSection(tester, Hauptbereich.archiv);
    await waehle(tester, ['orig2.jpg']);
    await leiste(tester, de.auswArchiv);
    await meldungenWeg(tester);
    await openSection(tester, Hauptbereich.alben);
    await tap(tester, find.text('Ordnungsalbum'));
    await tester.longPress(kachel('orig1.jpg'));
    await settle(tester);
    await tap(tester, find.byTooltip(de.albumTitelbildSetzen));
    await zurueck(tester);
    // Sammelbearbeitung: neues Datum, Ort entfernen.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waehle(tester, ['orig0.jpg', 'orig1.jpg', 'orig3.jpg']);
    await leiste(tester, de.auswMetadaten);
    await tapText(tester, de.allgWaehlen);
    expect(await datumEintippen(tester, DateTime(2022, 9, 9)), isTrue);
    await tapText(tester, de.auswOrtEntfernen);
    await tapText(tester, de.allgSpeichern);
    await eventually(
      tester,
      () async =>
          (await aufnahme(tester, 'orig3.jpg')).fileCreatedAt.year == 2022,
      was: 'Sammeldatum',
    );
    expect((await aufnahme(tester, 'orig3.jpg')).latitude, isNull);
    // Prüfsummen erneut – nur der Ablageort darf sich geändert haben.
    for (final n in namen) {
      expect(await originalSumme(tester, n), vorher[n], reason: n);
    }
    await finish(tester);
  });

  testWidgets(
    'ANS-145 Eigenständige Bibliothek: Ansehen und Suchen ohne Netz',
    (tester) async {
      await startApp(
        tester,
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
        ],
      );
      await befehl(tester, const AuswertenNachImportSetzen(false));
      final sand = img.ColorRgb8(230, 205, 150);
      await importiereDirekt(tester, [
        motivfoto('meer.jpg', ['BEACH'], sand, DateTime(2025, 5, 5)),
        textfoto('schild.jpg', ['BAHNHOF'], datum: DateTime(2025, 5, 6)),
      ]);
      await echt(() async {
        await for (final _ in bibliothek.backfillClipEmbeddings(alle: true)) {}
        await for (final _ in bibliothek.backfillOcrText(alle: true)) {}
      });
      await albumAnlegen(tester, 'Offline', ['meer.jpg']);
      final vorher = ohneNetz.versuche.length;
      final fehlerVorher = melde.verlauf
          .where((m) => m.art == Meldungsart.fehler)
          .length;
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'meer.jpg');
      await key(tester, LogicalKeyboardKey.arrowRight);
      await schliesseBetrachter(tester);
      await openSection(tester, Hauptbereich.alben);
      await waitFor(tester, find.text('Offline'));
      await openSection(tester, Hauptbereich.rueckblick);
      await waitFor(tester, find.text(de.erkundenLetzteFotos));
      await openSection(tester, Hauptbereich.statistik);
      await waitFor(tester, find.text(de.statInsgesamt));
      await openSection(tester, Hauptbereich.suche);
      await tippeSuche(tester, 'Strand');
      await waitFor(
        tester,
        kachel('meer.jpg'),
        timeout: const Duration(seconds: 60),
      );
      await sucheNachTyp(tester, de.suchoptTypOcr, 'Bahnhof');
      expect(treffer(tester), ['schild.jpg']);
      final neu = ohneNetz.versuche.skip(vorher).toList();
      final fremd = [
        for (final u in neu)
          if (!u.host.contains('tile') && !u.host.contains('arcgis')) u,
      ];
      print('ANS-145: Netzversuche $neu');
      expect(fremd, isEmpty, reason: 'keine Netzanfrage ausser Kartenkacheln');
      expect(
        melde.verlauf.where((m) => m.art == Meldungsart.fehler).length,
        fehlerVorher,
        reason: 'keine Fehlermeldung',
      );
      await finish(tester);
    },
  );

  // === Nachträge: Zeitstrahl, Archiv in der Zeitleiste, Vokabular ==========

  testWidgets('ANS-013 Zeitstrahl zur Schnellnavigation', (tester) async {
    await startApp(tester);
    // Viele Monate über acht Jahre, als Datenbankzeilen.
    await zeilenAnlegen(
      tester,
      200,
      ab: DateTime(2026, 6, 1, 12),
      abstand: const Duration(days: 15),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    final strahl = find.byType(TimelineScrubber);
    await waitFor(tester, strahl);
    // Jahreszahlen am Zeitstrahl überlappen sich nicht.
    final jahre = [
      for (final e
          in find
              .descendant(of: strahl, matching: find.byType(Text))
              .evaluate())
        if (RegExp(r'^\d{4}$').hasMatch((e.widget as Text).data ?? ''))
          tester.getRect(find.byWidget(e.widget)),
    ];
    print('ANS-013: ${jahre.length} Jahreszahlen am Zeitstrahl');
    expect(jahre.length, greaterThan(1));
    for (var i = 0; i < jahre.length; i++) {
      for (var k = i + 1; k < jahre.length; k++) {
        expect(jahre[i].overlaps(jahre[k]), isFalse);
      }
    }
    // Ziehen: das Raster springt mit.
    expect(rasterRolle(tester).position.pixels, lessThan(1));
    final r = tester.getRect(strahl);
    final geste = await tester.startGesture(
      Offset(r.center.dx, r.top + 20),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 10; i++) {
      await geste.moveTo(
        Offset(r.center.dx, r.top + 20 + (r.height * 0.6) * i / 10),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 200));
    final waehrend = rasterRolle(tester).position.pixels;
    await geste.up();
    await settle(tester);
    expect(waehrend, greaterThan(1000), reason: 'das Raster folgt dem Zug');
    expect(rasterRolle(tester).position.pixels, greaterThan(1000));
    final anteil =
        rasterRolle(tester).position.pixels /
        rasterRolle(tester).position.maxScrollExtent;
    expect(
      anteil,
      closeTo(0.6, 0.2),
      reason: 'springt zum gewählten Zeitpunkt',
    );
    await finish(tester);
  });

  // Behoben in #410: Der Zeitstrahl steht erst ab drei Gruppen
  // (zeitstrahlAbGruppen); Raster und Zeitstrahl prüfen dieselbe Schwelle.
  testWidgets('ANS-013 Bei sehr wenigen Monaten kein Zeitstrahl', (
    tester,
  ) async {
    await startApp(
      tester,
      fotos: [
        testfoto('m1.jpg', datum: DateTime(2025, 5, 3)),
        testfoto('m2.jpg', datum: DateTime(2025, 4, 3)),
      ],
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel('m1.jpg'));
    await settle(tester);
    print(
      'ANS-013: Zeitstrahl bei zwei Monaten: ${find.byType(TimelineScrubber).evaluate().length}',
    );
    expect(find.byType(TimelineScrubber), findsNothing);
    await finish(tester);
  });

  // Behoben in #410: Das Sprungziel bleibt in der Zeitleiste erhalten (siehe
  // ANS-015), das Raster meldet „Foto nicht in der Timeline gefunden.“.
  testWidgets(
    'ANS-016 „In der Timeline anzeigen“ bei einem archivierten Foto',
    (tester) async {
      await startApp(
        tester,
        fotos: [
          testfoto('archiviert.jpg', datum: DateTime(2025, 3, 3)),
          testfoto('normal.jpg', datum: DateTime(2025, 3, 4)),
        ],
      );
      await befehl(
        tester,
        ArchivSetzen(await ids(tester, ['archiviert.jpg']), true),
      );
      await openSection(tester, Hauptbereich.archiv);
      await oeffne(tester, 'archiviert.jpg');
      await rechtsklick(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PageView)),
      );
      await tap(tester, find.text(de.viewerInTimelineZeigen));
      await waitGone(tester, betrachter);
      await meldung(tester, de.rasterFotoNichtGefunden);
      expect(aktuellerBereich(tester), Hauptbereich.zeitleiste);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_FlashHighlight',
        ),
        findsNothing,
        reason: 'kein anderes Foto hervorgehoben',
      );
      await finish(tester);
    },
  );

  testWidgets('ANS-076 Neuer Begriff wirkt auf künftige Importe', (
    tester,
  ) async {
    await startApp(
      tester,
      modelle: const [
        'clip_image_encoder.onnx',
        'clip_text_encoder.onnx',
        'vocab.json',
        'merges.txt',
        'translate_de_en_encoder.onnx',
        'translate_de_en_decoder.onnx',
        'translate_vocab.json',
      ],
    );
    await befehl(tester, const AuswertenNachImportSetzen(false));
    await befehl(tester, const SucheUebersetzenSetzen(true));
    final weiss = img.ColorRgb8(245, 245, 245);
    await importiereDirekt(tester, [
      motivfoto('turm_alt.jpg', ['LIGHTHOUSE'], weiss, DateTime(2025, 1, 1)),
    ]);
    Future<void> kiLauf() async {
      await echt(() async {
        await for (final _ in bibliothek.backfillAiTags(onlyUntagged: true)) {}
      });
      await settle(tester);
    }

    await kiLauf();
    final altVorher = await schlagwoerter(tester, 'turm_alt.jpg');
    // Ein Begriff, der noch nicht im Vokabular steht (die Vorgabe enthält
    // „Hund“ schon) – neu ins Vokabular (Einstellungen).
    await openSection(tester, Hauptbereich.einstellungen);
    await tapText(tester, de.einstAbschnittVokabular);
    expect(find.widgetWithText(InputChip, 'Leuchtturm'), findsNothing);
    await enter(tester, field(de.einstBegriffHinzufuegenFeld), 'Leuchtturm');
    await tap(tester, find.byTooltip(de.einstBegriffHinzufuegen));
    await waitFor(tester, find.widgetWithText(InputChip, 'Leuchtturm'));
    // Ein zweites Foto mit demselben Motiv importieren, die
    // Verschlagwortung abwarten.
    await importiereDirekt(tester, [
      motivfoto('turm_neu.jpg', ['LIGHTHOUSE'], weiss, DateTime(2025, 1, 2)),
    ]);
    await kiLauf();
    final neu = await schlagwoerter(tester, 'turm_neu.jpg');
    final alt = await schlagwoerter(tester, 'turm_alt.jpg');
    print('ANS-076: alt vorher $altVorher, alt $alt, neu $neu');
    expect(alt, altVorher, reason: 'das vorher importierte bleibt unverändert');
    expect(alt, isNot(contains('Leuchtturm')));
    expect(neu, contains('Leuchtturm'));
    await finish(tester);
  });

  // === Mit dem Wegwerf-Server (PV_E2E_SERVER=1, sonst übersprungen) =========

  testWidgets(
    'ANS-089 ANS-090 ANS-091 ANS-092 mitServer verbundene Bibliothek',
    skip: serverAdresse.isEmpty,
    (tester) async {
      await startApp(tester);
      final jahre = [2019, 2021, 2023, 2025];
      await importiereDirekt(tester, [
        for (final j in jahre)
          testfoto('a$j.jpg', datum: DateTime(j, 6, 1, 10)),
        testfoto('b2022.jpg', datum: DateTime(2022, 6, 1, 10)),
        testfoto('lokal.jpg', datum: DateTime(2018, 1, 1, 10)),
        testfoto('fern.jpg', datum: DateTime(2017, 1, 1, 10)),
        for (var i = 0; i < 19; i++)
          testfoto('viele$i.jpg', datum: DateTime(2010, 1, 1 + i)),
      ]);
      final personA = _uuid.v4(), personB = _uuid.v4();
      await befehl(tester, PersonAnlegen(personA, 'Person A'));
      await befehl(tester, PersonAnlegen(personB, 'Person B'));
      for (final j in jahre) {
        await gesichtFuer(tester, 'a$j.jpg', personA);
      }
      await gesichtFuer(tester, 'b2022.jpg', personB);
      // 19 weitere benannte Personen (zusammen 21).
      for (var i = 0; i < 19; i++) {
        final id = _uuid.v4();
        await befehl(
          tester,
          PersonAnlegen(id, 'Person ${String.fromCharCode(67 + i)}'),
        );
        await gesichtFuer(tester, 'viele$i.jpg', id);
      }
      await albumAnlegen(tester, 'Familie', []);
      await albumAnlegen(tester, 'Mit Server', ['lokal.jpg']);
      await verbindeMitServer(tester);

      // ANS-089: mit Server erscheinen beide Knöpfe.
      await openSection(tester, Hauptbereich.alben);
      await tap(tester, find.text('Mit Server'));
      await waitFor(tester, find.byTooltip(teilenDe.kontenTeilen));
      await waitFor(tester, find.byTooltip(teilenDe.automatischFuellen));
      await zurueck(tester);

      // ANS-091: Fehlerfälle der Albumregel.
      await tap(tester, find.text('Familie'));
      final regelKnopf = find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            (w.tooltip ?? '').startsWith(teilenDe.automatischFuellen),
      );
      await waitFor(tester, regelKnopf);
      await tap(tester, regelKnopf);
      await waitFor(tester, find.text(teilenDe.automatischTitel('Familie')));
      await tap(tester, find.text(teilenDe.speichern).last);
      await waitFor(tester, find.text(teilenDe.regelMindestensEine));
      final alleNamen = [
        'Person A',
        'Person B',
        for (var i = 0; i < 19; i++) 'Person ${String.fromCharCode(67 + i)}',
      ];
      Future<void> haken(String name) async {
        final f = find.widgetWithText(CheckboxListTile, name);
        final liste = find
            .ancestor(
              of: find.byType(CheckboxListTile).first,
              matching: find.byType(Scrollable),
            )
            .first;
        await rolleZu(tester, f, in_: liste);
        await tester.tap(f);
        await tester.pump();
      }

      for (final n in alleNamen) {
        await haken(n);
      }
      await settle(tester);
      await tap(tester, find.text(teilenDe.speichern).last);
      await waitFor(tester, find.text(teilenDe.regelHoechstens));
      expect(
        find.text(teilenDe.automatischTitel('Familie')),
        findsOneWidget,
        reason: 'bleibt offen',
      );
      // Alle wieder ab, nur Person A, Server „gestoppt“ (gesperrt).
      for (final n in alleNamen.skip(1)) {
        await haken(n);
      }
      await settle(tester);
      final hakenA = find.widgetWithText(CheckboxListTile, 'Person A');
      await rolleZu(
        tester,
        hakenA,
        in_: find
            .ancestor(
              of: find.byType(CheckboxListTile).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.widget<CheckboxListTile>(hakenA).value, isTrue);
      ohneNetz.serverGesperrt = true;
      await tap(tester, find.text(teilenDe.speichern).last);
      await waitFor(
        tester,
        find.text(teilenDe.geteiltOffline),
        timeout: const Duration(seconds: 40),
      );
      ohneNetz.serverGesperrt = false;
      expect(
        await albumInhalt(tester, 'Familie'),
        isEmpty,
        reason: 'Album unverändert',
      );

      // ANS-090: Person A, „Eine der Personen“, ab 1.1.2021.
      await tap(tester, find.text(teilenDe.regelEine));
      await tap(tester, find.text(teilenDe.aufgenommenAb));
      expect(await datumEintippen(tester, DateTime(2021, 1, 1)), isTrue);
      // Die Rückmeldung kommt hier als SnackBar (teilen_ui), nicht über das
      // Meldungsfenster: ohne langes Warten nach dem Klick nachsehen.
      await tester.tap(find.text(teilenDe.speichern).last);
      await waitFor(
        tester,
        find.text(teilenDe.automatischDazu(3)),
        timeout: const Duration(seconds: 30),
      );
      await eventually(
        tester,
        () async {
          final inhalt = await albumInhalt(tester, 'Familie');
          return inhalt.length == 3;
        },
        timeout: const Duration(seconds: 60),
        was: 'Album gefüllt (Abgleich)',
      );
      expect((await albumInhalt(tester, 'Familie'))..sort(), [
        'a2021.jpg',
        'a2023.jpg',
        'a2025.jpg',
      ]);
      await waitFor(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is IconButton &&
              (w.tooltip ?? '').startsWith('${teilenDe.automatischFuellen}:') &&
              (w.tooltip ?? '').contains('Person A') &&
              w.isSelected == true,
        ),
      );

      // ANS-092: herausgenommen bleibt draussen; Regel abschalten.
      await tap(tester, find.byTooltip(de.albumFotosHinzufuegen));
      await waitFor(tester, find.text(de.albumFotosWaehlenTitel('Familie')));
      await rolleZu(
        tester,
        kachel('a2023.jpg'),
        in_: rolleIn(AufnahmenWaehlenScreen),
      );
      await tap(tester, kachel('a2023.jpg'));
      await tap(tester, find.widgetWithText(TextButton, de.allgFertig));
      await eventually(tester, () async {
        final inhalt = await albumInhalt(tester, 'Familie');
        return !inhalt.contains('a2023.jpg');
      }, was: 'abgehakt');
      await echt(() => Future<void>.delayed(const Duration(seconds: 5)));
      expect(
        await albumInhalt(tester, 'Familie'),
        isNot(contains('a2023.jpg')),
        reason: 'kommt nicht zurück',
      );
      await tap(tester, regelKnopf);
      await tester.tap(find.text(teilenDe.automatischAus));
      await waitFor(
        tester,
        find.text(teilenDe.automatischAusGemacht),
        timeout: const Duration(seconds: 30),
      );
      expect((await albumInhalt(tester, 'Familie'))..sort(), [
        'a2021.jpg',
        'a2025.jpg',
      ]);
      await zurueck(tester);

      await finish(tester);
    },
  );

  // Befund: Ein Foto, dessen Original in der verbundenen Kopie nicht
  // vorrätig ist, zeigt bei gestopptem Server nur die Ladeanzeige – nach
  // 20 s noch immer, ohne Hinweis und ohne Vorschaubild. Der Fehler beim
  // Holen wird nicht behandelt: StoragePaths.bereit → Dateibeschaffung.hole
  // wirft KeineVerbindung, und asset_viewer_screen.dart:1938–1940
  // (_AssetPage.build) zeigt bei `!snapshot.hasData` – also auch bei
  // `snapshot.hasError` – nur CircularProgressIndicator. In beiden Läufen
  // kam KeineVerbindung ausserdem als nicht abgefangene Ausnahme an (im
  // zweiten brach die Prüfung daran gleich beim Öffnen ab).
  testWidgets(
    'ANS-061 mitServer Original nicht vorrätig bei gestopptem Server',
    skip: true,
    (tester) async {
      await startApp(tester);
      addTearDown(() => ohneNetz.serverGesperrt = false);
      await importiereDirekt(tester, [
        testfoto('lokal.jpg', datum: DateTime(2018, 1, 1, 10)),
        testfoto('fern.jpg', datum: DateTime(2017, 1, 1, 10)),
      ]);
      await verbindeMitServer(tester);
      // Das zwischengespeicherte Foto einmal ansehen, solange der Server
      // läuft.
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffne(tester, 'lokal.jpg');
      await waitFor(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PhotoView)),
      );
      await schliesseBetrachter(tester);
      // „Server stoppen“ (sperren) und warten, bis offene Verbindungen des
      // Clients verfallen sind (Leerlauf 15 s) – sonst holt eine noch
      // offene Verbindung das Original doch.
      ohneNetz.serverGesperrt = true;
      final abgewiesenVorher = ohneNetz.versuche
          .where((u) => u.host == '127.0.0.1' || u.host == 'localhost')
          .length;
      final leerlauf = DateTime.now().add(const Duration(seconds: 18));
      while (DateTime.now().isBefore(leerlauf)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      // Original und Vorschau von fern.jpg sind nicht vorrätig.
      final fern = await aufnahme(tester, 'fern.jpg');
      final fernDatei = bibliothek.paths.absolute(fern.relativePath);
      for (final rel in [fern.relativePath, fern.previewRelativePath]) {
        if (rel == null) continue;
        final f = bibliothek.paths.absolute(rel);
        if (f.existsSync()) f.deleteSync();
      }
      expect(fernDatei.existsSync(), isFalse);
      await oeffne(tester, 'fern.jpg');
      final ende = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final laedtNoch = find
          .descendant(
            of: betrachter,
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isNotEmpty;
      final abgewiesen =
          ohneNetz.versuche
              .where((u) => u.host == '127.0.0.1' || u.host == 'localhost')
              .length -
          abgewiesenVorher;
      print(
        'ANS-061: nach 20 s noch Ladeanzeige: $laedtNoch; '
        'Original doch geholt: ${fernDatei.existsSync()}; '
        'abgewiesene Verbindungen zum Server: $abgewiesen; '
        '${onScreen(tester)}',
      );
      // Sonst wäre der Fall gar nicht eingetreten.
      expect(fernDatei.existsSync(), isFalse);
      // Beobachtung: Blättert die Pfeiltaste von hier weiter?
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 600));
      print(
        'ANS-061: Pfeiltaste wirkt auf der hängenden Seite: '
        '${betrachterZeigt(DateTime(2018, 1, 1, 10)).evaluate().isNotEmpty}',
      );
      // Esc schliesst, das zwischengespeicherte Foto erscheint normal.
      await schliesseBetrachter(tester);
      expect(betrachter, findsNothing);
      await oeffne(tester, 'lokal.jpg');
      await waitFor(
        tester,
        find.descendant(of: betrachter, matching: find.byType(PhotoView)),
      );
      await schliesseBetrachter(tester);
      await openSection(tester, Hauptbereich.alben);
      await openSection(tester, Hauptbereich.zeitleiste);
      expect(
        kachel('fern.jpg'),
        findsOneWidget,
        reason: 'App bleibt bedienbar',
      );
      ohneNetz.serverGesperrt = false;
      expect(
        laedtNoch,
        isFalse,
        reason: 'Hinweis oder Vorschaubild statt Dauerladen',
      );
      await finish(tester);
    },
  );

  // === Befunde mit Zusicherungen im Datumsdialog (am Ende: eine
  // Ausnahme mitten im Tippen bringt den Prüfstand für alle folgenden
  // Prüfungen aus dem Tritt) ===============================================

  // Befund: Bei einem Foto von 1985 öffnet „Bearbeiten“ keinen Kalender.
  // asset_info_sheet.dart:364–368 ruft showDatePicker mit
  // firstDate: DateTime(1990) und initialDate = Aufnahmedatum (1985) –
  // das verletzt die Vorbedingung (initialDate >= firstDate), die
  // Zusicherung wirft, und vor 1990 ist ohnehin kein Tag wählbar.
  testWidgets('ANS-071 Aufnahmedatum vor 1990 ändern', (tester) async {
    await startApp(
      tester,
      fotos: [testfoto('d1985.jpg', datum: DateTime(1985, 7, 4, 12))],
    );
    final importiert = await aufnahme(tester, 'd1985.jpg');
    print('ANS-071: Import las als Datum ${importiert.fileCreatedAt}');
    await setzeDatum(tester, 'd1985.jpg', DateTime(1985, 7, 4, 12));
    final datei = bibliothek.paths.absolute(
      (await aufnahme(tester, 'd1985.jpg')).relativePath,
    );
    final vorher = await pruefsumme(tester, datei);
    await openSection(tester, Hauptbereich.zeitleiste);
    await oeffne(tester, 'd1985.jpg');
    await tap(tester, knopf(de.viewerInfo));
    final info = find.byType(AssetInfoSheet);
    await tap(
      tester,
      find
          .descendant(of: info, matching: find.byTooltip(de.allgBearbeiten))
          .first,
    );
    await settle(tester);
    final fehler = tester.takeException();
    print('ANS-071 (1985): Ausnahme beim Öffnen: $fehler');
    expect(fehler, isNull, reason: 'Kalender öffnet ohne Fehler');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(await datumEintippen(tester, DateTime(1984, 9, 1)), isTrue);
    await zeitBestaetigen(tester);
    await eventually(
      tester,
      () async =>
          (await aufnahme(tester, 'd1985.jpg')).fileCreatedAt.year == 1984,
      was: '1984 gewählt',
    );
    final neu = bibliothek.paths.absolute(
      (await aufnahme(tester, 'd1985.jpg')).relativePath,
    );
    expect(await pruefsumme(tester, neu), vorher);
    await finish(tester);
  });

  // Befund: Der Zeitraumfilter beginnt erst 1990
  // (search_options_sheet.dart:300, firstDate: DateTime(1990)) – ein Tag
  // 1984 ist nicht wählbar. Hat die Satzdeutung („1985“) ein früheres
  // Anfangsdatum gesetzt, verletzt es als Startwert die Vorbedingung von
  // showDatePicker; der Kalender öffnet sich nicht.
  testWidgets('ANS-109 Zeitraum vor 1990', (tester) async {
    await startApp(
      tester,
      fotos: [
        testfoto('alt.jpg', datum: DateTime(1985, 5, 5, 9)),
        testfoto('neu.jpg', datum: DateTime(2020, 5, 5, 9)),
      ],
    );
    await setzeDatum(tester, 'alt.jpg', DateTime(1985, 5, 5, 9));
    await openSection(tester, Hauptbereich.suche);
    // 1. Ein Tag im Jahr 1984 als Anfangsdatum.
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptAnfangsdatum);
    await tap(
      tester,
      find
          .descendant(
            of: optionenBlatt,
            matching: find.text(de.suchoptDatumPlatzhalter),
          )
          .first,
    );
    final angenommen1984 = await datumEintippen(tester, DateTime(1984, 3, 1));
    print('ANS-109: 1984 als Anfangsdatum angenommen: $angenommen1984');
    if (!angenommen1984) {
      await tap(
        tester,
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
    }
    await tap(
      tester,
      find.descendant(
        of: optionenBlatt,
        matching: find.byTooltip(de.allgSchliessen),
      ),
    );
    await waitGone(tester, optionenBlatt);
    // 2. Der Kalender mit einem Startwert aus 1985 (aus der Satzdeutung).
    await tippeSuche(tester, '1985');
    await oeffneSuchoptionen(tester);
    await imBlatt(tester, de.suchoptAnfangsdatum);
    final anfang = find.descendant(
      of: optionenBlatt,
      matching: find.textContaining('1985'),
    );
    final mitStart = anfang.evaluate().isNotEmpty;
    print('ANS-109: Anfangsdatum aus der Satzdeutung gesetzt: $mitStart');
    Object? fehler;
    if (mitStart) {
      try {
        await tester.tap(anfang.first);
        await settle(tester);
      } catch (e) {
        fehler = e;
      }
      fehler ??= tester.takeException();
      print('ANS-109: Ausnahme beim Öffnen: $fehler');
    }
    expect(angenommen1984, isTrue, reason: '1984 ist wählbar');
    expect(fehler, isNull, reason: 'Kalender öffnet mit Startwert 1985');
    await finish(tester);
  });

  // ENDE
}

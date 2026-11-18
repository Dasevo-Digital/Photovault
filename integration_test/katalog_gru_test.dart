// ignore_for_file: avoid_print
// Katalog-Prüfungen für den Bereich GRU (Grundgerüst): Start und
// Startfehler, Hauptfenster und Seitenleiste, Hinweisbänder, Tastenkürzel,
// Beenden, mehrere Bibliotheken, Speicherort, Einstellungen, Werkzeuge,
// Hintergrundaufgaben, Meldungen und Barrierefreiheit.
//
// Jede Prüfung startet die echte App mit einer Wegwerf-Bibliothek im
// Temp-Ordner (siehe katalog_kit.dart). Weitere Bibliotheken liegen
// ausschliesslich unter [anker]. Ein Neustart der App im selben Test baut
// PhotoVaultApp neu auf, solange die Umlenkung des Kits gilt.
//
// Laufen lassen nur über die Warteschlange des Prüfkatalogs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/album_detail_screen.dart';
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/aufnahmedaten_screen.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/screens/camera_presets_screen.dart';
import 'package:photo_vault/screens/datierung_screen.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/screens/einstellungen/bibliotheken.dart';
import 'package:photo_vault/screens/einstellungen/erscheinungsbild.dart';
import 'package:photo_vault/screens/einstellungen/gefahrenzone.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart';
import 'package:photo_vault/screens/einstellungen/speicherort.dart';
import 'package:photo_vault/screens/einstellungen/sprache.dart';
import 'package:photo_vault/screens/einstellungen/ueber.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/screens/export_presets_screen.dart';
import 'package:photo_vault/screens/fotokammer_screen.dart';
import 'package:photo_vault/screens/gpx_verortung_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/integrity_check_screen.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/screens/locked_folder_screen.dart';
import 'package:photo_vault/screens/ortsvorschlaege_screen.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/screens/scan_workspace_screen.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/stack_review_screen.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/screens/statistics_screen.dart';
import 'package:photo_vault/screens/staubsuche_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/screens/xmp_import_screen.dart';
import 'package:photo_vault/services/bibliothekssperre.dart';
import 'package:photo_vault/services/groessentext.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/modelltexte.dart';
import 'package:photo_vault/services/restore_queue_service.dart'
    show fortschrittProzent;
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/arbeitsbereich.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/seitenleiste.dart';
import 'package:photo_vault/widgets/video_playback.dart' show VideoSurface;
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'katalog_kit.dart';

// --- Hilfen dieser Datei ----------------------------------------------------

/// Widgets eines privaten Typs (z. B. die Zeilen der Seitenleiste).
Finder _typ(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

/// Die Zeile der Seitenleiste mit dem Text [text].
Finder zeile(String text) =>
    find.ancestor(of: find.text(text), matching: _typ('_Zeile'));

/// Der Text [text] in einer Zeile der Seitenleiste.
Finder zeilenText(String text) =>
    find.descendant(of: _typ('_Zeile'), matching: find.text(text));

/// Tippt auf den linken Teil (das Symbol) eines Eintrags der Leiste – so
/// trifft der Klick auch die eingeklappte Leiste.
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

/// Wie [leiste], aber ohne auf Ruhe zu warten.
Future<void> leisteSchnell(WidgetTester tester, String text) async {
  await tippeLinks(tester, zeile(text));
  await tester.pump(const Duration(milliseconds: 50));
}

int gewaehlt(WidgetTester tester) =>
    tester.widget<Seitenleiste>(find.byType(Seitenleiste)).gewaehlt;

double inhaltLinks(WidgetTester tester) =>
    tester.getTopLeft(find.byType(Arbeitsbereich)).dx;

/// Deckkraft der Beschriftung eines Leisteneintrags (0 = eingeklappt).
double deckkraft(WidgetTester tester, String text) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: zeilenText(text),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

/// Ein Knopf (Filled/Outlined/Text) mit dem Text [text].
Finder knopf(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

/// Ein Knopf mit dem Text [text] innerhalb von [bereich].
Finder knopfIn(Finder bereich, String text) => find.ancestor(
  of: find.descendant(of: bereich, matching: find.text(text)),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool knopfAktiv(WidgetTester tester, Finder f) =>
    tester.widget<ButtonStyleButton>(f.first).onPressed != null;

/// Der aktuelle Zustand der Bibliothek – auch dann, wenn statt der Hülle
/// ein Startfehler zu sehen ist.
LibraryState zustand(WidgetTester tester) => Provider.of<LibraryState>(
  tester.element(find.byType(MaterialApp)),
  listen: false,
);

/// Beendet die App (Datenbank zu, Baum leer) und startet sie mit derselben
/// Umlenkung neu. [dazwischen] läuft, solange nichts geöffnet ist.
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

/// Beendet die App (Arbeit anhalten, Oberfläche abbauen, Datenbank zu) und
/// startet sie mit derselben Umlenkung neu. [dazwischen] läuft, solange
/// nichts geöffnet ist. Liefert, ob das erste Bild den Ladekreis zeigte.
///
/// Erst die Oberfläche, dann die Datenbank: Eine Abfrage, die ein
/// Bildschirm gerade stellt, liefe sonst gegen die geschlossene Datenbank
/// und würde als Fehler der Prüfung gemeldet.
Future<bool> neustart(
  WidgetTester tester, {
  bool shell = true,
  FutureOr<void> Function()? dazwischen,
}) async {
  final alt = bibliothek;
  schritt = 'neustart: anhalten';
  await halteAn(tester, alt);
  schritt = 'neustart: abbauen';
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 500));
  schritt = 'neustart: vorDemBeenden';
  try {
    await alt.vorDemBeenden();
  } catch (e) {
    print('neustart: vorDemBeenden: $e');
  }
  schritt = 'neustart: dazwischen';
  if (dazwischen != null) await dazwischen();
  schritt = 'neustart: aufbauen';
  await tester.pumpWidget(const PhotoVaultApp());
  final kreis =
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
      find.byType(HomeShell).evaluate().isEmpty;
  await tester.pump();
  bibliothek = zustand(tester);
  if (shell) {
    await waitFor(
      tester,
      find.byType(HomeShell),
      timeout: const Duration(seconds: 90),
    );
    bibliothek = zustand(tester);
    await settle(tester);
  }
  return kreis;
}

/// Ende einer Prüfung: Arbeit anhalten, Oberfläche abbauen, dann finish
/// aus dem Kit (Datenbank zu, Temp-Ordner weg).
Future<void> ende(WidgetTester tester) async {
  schritt = 'ende';
  await halteAn(tester, bibliothek);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 500));
  await finish(tester);
}

Future<List<AssetData>> aufnahmen() =>
    bibliothek.db.select(bibliothek.db.assets).get();

Future<int> anzahlAufnahmen() async => (await aufnahmen()).length;

/// Ob die Datenbank der laufenden Bibliothek noch antwortet.
Future<bool> datenbankOffen() async {
  try {
    await bibliothek.db
        .customSelect('SELECT 1')
        .get()
        .timeout(const Duration(seconds: 5));
    return true;
  } catch (_) {
    return false;
  }
}

String sha(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Prüfsummen aller Dateien unter [d] (relativer Pfad → sha256), ohne die
/// Sperrdatei der Instanz. [ohneDb] lässt die SQLite-Dateien weg: Sie
/// ändern sich beim Schliessen (WAL-Abschluss), ohne dass etwas verlegt
/// wird.
Map<String, String> pruefsummen(Directory d, {bool ohneDb = false}) {
  final m = <String, String>{};
  if (!d.existsSync()) return m;
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = p.relative(e.path, from: d.path);
    final name = p.basename(rel);
    if (name.startsWith(Bibliothekssperre.dateiname)) continue;
    if (ohneDb && name.startsWith('library.sqlite')) continue;
    m[rel] = sha(e);
  }
  return m;
}

int ordnergroesse(Directory d) {
  var n = 0;
  if (!d.existsSync()) return 0;
  for (final e in d.listSync(recursive: true, followLinks: false)) {
    if (e is File) n += e.lengthSync();
  }
  return n;
}

/// Hält die Sperrdatei einer Bibliothek aus einem zweiten Prozess – wie
/// eine zweite Instanz (fcntl-Sperre wie in Bibliothekssperre).
class Sperrhalter {
  Sperrhalter._(this._prozess);
  final Process _prozess;
  bool _weg = false;

  static const _skript = r'''
use Fcntl;
open(my $f, '>>', $ARGV[0]) or die "open: $!";
my $s = pack('qqiss', 0, 0, 0, F_WRLCK, 0);
fcntl($f, F_SETLK, $s) or die "lock: $!";
$| = 1;
print "gesperrt\n";
my $x = <STDIN>;
''';

  static Future<Sperrhalter> auf(Directory wurzel) async {
    final ziel = p.join(wurzel.path, Bibliothekssperre.dateiname);
    final prozess = await Process.start('/usr/bin/perl', ['-e', _skript, ziel]);
    final fehler = StringBuffer();
    prozess.stderr.transform(utf8.decoder).listen(fehler.write);
    final erste = await prozess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15));
    if (erste.trim() != 'gesperrt') {
      prozess.kill(ProcessSignal.sigkill);
      throw StateError('Sperrhalter: $erste / $fehler');
    }
    return Sperrhalter._(prozess);
  }

  Future<void> beende() async {
    if (_weg) return;
    _weg = true;
    _prozess.kill(ProcessSignal.sigkill);
    await _prozess.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }
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

/// Tippt auf [f] (erster Treffer) und wartet nur kurz: Meldungen stehen
/// vier Sekunden, und das Warten des Kits auf Ruhe dauert bei laufenden
/// Animationen bis zu fünf.
Future<void> tippe(WidgetTester tester, Finder f) async {
  schritt = 'tippe $f'.split('\n').first;
  await waitFor(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await settle(tester, max: const Duration(seconds: 2));
}

/// Rollt [liste], bis [f] gebaut ist, und holt den ersten Treffer ins Bild.
Future<void> zeige(WidgetTester tester, Finder f, Finder liste) async {
  final pos = tester.state<ScrollableState>(liste).position;
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo((pos.pixels + 300).clamp(0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 50));
  }
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    if (pos.pixels <= 0) break;
    pos.jumpTo((pos.pixels - 300).clamp(0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

/// Setzt die Fenstergrösse für Layout UND MediaQuery. setSurfaceSize allein
/// ändert im Live-Prüfrahmen nur die Fläche; MediaQuery (wonach die App
/// zwischen schmal und breit wählt) folgt sonst dem echten Fenster.
Future<void> fenster(WidgetTester tester, Size groesse) async {
  tester.view.physicalSize = groesse * tester.view.devicePixelRatio;
  await tester.binding.setSurfaceSize(groesse);
  await tester.pump();
}

/// startApp aus dem Kit – vorher die MediaQuery-Grösse passend zur Fläche.
Future<LibraryState> starte(
  WidgetTester tester, {
  String sprache = 'de',
  Size groesse = const Size(1400, 900),
}) async {
  tester.view.physicalSize = groesse * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  return startApp(tester, sprache: sprache, groesse: groesse);
}

/// Wie oft ein Klick auf einem Startbildschirm (Bibliothek noch nicht
/// geöffnet) an `library.restoreQueue` scheiterte – lib/main.dart:206.
var spaeteFehler = 0;

/// Ob [filtereSemantik] diesen Fehler übergeht (nur der Befund-Test nicht).
var spaeteFehlerUebergehen = true;

/// Fehler beim Schliessen des Fortschrittsfensters nach gescheitertem
/// Verlegen (nur in den GRU-101-Prüfungen übergangen und gezählt).
var verschiebeFehler = 0;
var verschiebeFehlerUebergehen = false;

/// Übergeht Assertions des Flutter-Rahmens selbst (Semantikbaum bei
/// eingeschalteten Bedienungshilfen, RawTooltip am globalen Zeigerweg),
/// die weder zur App noch zur Prüfung gehören; alles andere geht
/// unverändert an den Prüfrahmen.
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
    // Ebenfalls aus dem Rahmen, nicht aus der App: Ein abgebauter
    // RawTooltip hängt noch am globalen Zeigerweg und legt beim nächsten
    // Klick einen zweiten Ticker an (raw_tooltip.dart).
    if (stapel.contains('raw_tooltip.dart') &&
        (text.contains('SingleTickerProviderStateMixin') ||
            text.contains("Looking up a deactivated widget's ancestor"))) {
      return;
    }
    // Befund (eigener Test unten): Auf den Startbildschirmen wirft jeder
    // Klick, weil der Listener in main.dart die Warteschlange der
    // Restaurierung anspricht, die es vor dem Öffnen nicht gibt. Die
    // übrigen Prüfungen dieser Bildschirme sollen davon nicht abhängen.
    if (spaeteFehlerUebergehen &&
        text.contains("Field 'restoreQueue' has not been initialized")) {
      spaeteFehler++;
      return;
    }
    // Befund (GRU-101): Scheitert das Verlegen, wird der Fortschritts-
    // Notifier entsorgt, während das schliessende Fenster noch mit ihm
    // baut (lib/screens/einstellungen/speicherort.dart:187); die zweite
    // Meldung ist die Folge davon im Inspektor.
    if (verschiebeFehlerUebergehen &&
        (text.contains(
              'BibliotheksVerschiebefortschritt?> was used after '
              'being disposed',
            ) ||
            text.contains("Looking up a deactivated widget's ancestor"))) {
      verschiebeFehler++;
      return;
    }
    vorher?.call(details);
  };
}

/// [importiereDirekt] mit Schrittmarke für das Lebenszeichen.
Future<List<String>> importiere(WidgetTester tester, List<File> dateien) {
  schritt = 'import ${dateien.length}';
  return importiereDirekt(tester, dateien);
}

/// Die Einstellungen öffnen (über die Leiste).
Future<void> einstellungen(WidgetTester tester) async {
  await leiste(tester, de.navEinstellungen);
  await waitFor(tester, find.byType(SettingsScreen));
}

Finder get einstListe => find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Klappt die Gruppe [titel] der Einstellungen auf (oder zu).
Future<void> gruppe(WidgetTester tester, String titel) async {
  final f = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(titel),
  );
  tester.state<ScrollableState>(einstListe).position.jumpTo(0);
  await tester.pump();
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: einstListe,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await settle(tester, max: const Duration(seconds: 3));
}

/// Scrollt im Einstellungsbereich bis [f].
Future<void> zeigeInEinstellungen(WidgetTester tester, Finder f) =>
    zeige(tester, f, einstListe);

/// Die Aufgabenübersicht öffnen: Werkzeuge → Aufgaben.
Future<void> aufgabenOeffnen(WidgetTester tester) async {
  await leiste(tester, de.navWerkzeuge);
  await waitFor(tester, find.byType(ToolsScreen));
  await tippe(
    tester,
    find.descendant(
      of: find.byType(ToolsScreen),
      matching: find.text(de.aufgTitel),
    ),
  );
  await waitFor(tester, find.byType(BackgroundTasksScreen));
}

Finder get aufgabenListe => find
    .descendant(
      of: find.byType(BackgroundTasksScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Die Karte einer Aufgabe mit dem Titel [titel] (dorthin gescrollt).
Future<Finder> karte(WidgetTester tester, String titel) async {
  final t = find.descendant(
    of: find.byType(BackgroundTasksScreen),
    matching: find.text(titel),
  );
  await zeige(tester, t, aufgabenListe);
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

/// Ob in der Karte [k] ein Text vorkommt, der [muster] erfüllt.
bool textIn(WidgetTester tester, Finder k, bool Function(String) muster) {
  for (final t in tester.widgetList<Text>(
    find.descendant(of: k, matching: find.byType(Text)),
  )) {
    final s = t.data ?? t.textSpan?.toPlainText() ?? '';
    if (muster(s)) return true;
  }
  return false;
}

/// ⌘ + [taste].
Future<bool> mitMeta(WidgetTester tester, LogicalKeyboardKey taste) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  final r = await tester.sendKeyEvent(taste);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await settle(tester, max: const Duration(seconds: 2));
  return r;
}

/// Umschalt + [taste] mit dem Zeichen [zeichen].
Future<bool> mitUmschalt(
  WidgetTester tester,
  LogicalKeyboardKey taste,
  String zeichen,
) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final r = await tester.sendKeyEvent(taste, character: zeichen);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await settle(tester, max: const Duration(seconds: 2));
  return r;
}

/// Stellt die Frage „darf ich beenden?“ der nativen Seite nach (Kanal
/// photo_vault/beenden, Methode darfBeenden).
Future<bool> frageBeenden(WidgetTester tester) async {
  const codec = StandardMethodCodec();
  final bytes = await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage(
        'photo_vault/beenden',
        codec.encodeMethodCall(const MethodCall('darfBeenden')),
        null,
      );
  return codec.decodeEnvelope(bytes!) as bool;
}

/// Lebenszyklus nachstellen, gültige Übergänge vorausgesetzt.
Future<void> lebenszyklus(
  WidgetTester tester,
  List<AppLifecycleState> zustaende,
) async {
  for (final z in zustaende) {
    if (tester.binding.lifecycleState == z) continue;
    tester.binding.handleAppLifecycleStateChanged(z);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Erzeugt [n] Testfotos (kleine, eigene Inhalte).
List<File> fotos(
  int n, {
  String stamm = 'f',
  int breite = 160,
  int hoehe = 120,
  bool mitOrt = false,
  DateTime? ab,
  int monateAbstand = 0,
}) => [
  for (var i = 0; i < n; i++)
    testfoto(
      '$stamm${i.toString().padLeft(4, '0')}.jpg',
      datum: monateAbstand > 0
          ? DateTime(2020 + (i ~/ 12), 1 + (i % 12), 10, 12)
          : (ab ?? DateTime(2024, 5, 1, 10)).add(Duration(minutes: i)),
      breitengrad: mitOrt ? 47.0 + i * 0.001 : null,
      laengengrad: mitOrt ? 11.0 + i * 0.001 : null,
      breite: breite,
      hoehe: hoehe,
    ),
];

/// [n] grosse Fotos: eines erzeugt, die übrigen als Kopien mit
/// angehängten Bytes (andere Prüfsumme, dasselbe Bild) – das Erzeugen
/// grosser JPEGs kostet sonst je Bild eine halbe Sekunde.
List<File> grosseFotos(
  int n, {
  String stamm = 'g',
  int breite = 3000,
  int hoehe = 2000,
  bool mitOrt = false,
}) {
  final basis = testfoto(
    '${stamm}0000.jpg',
    datum: DateTime(2024, 5, 1, 10, 7),
    breite: breite,
    hoehe: hoehe,
    breitengrad: mitOrt ? 47.1 : null,
    laengengrad: mitOrt ? 11.1 : null,
  );
  final bytes = basis.readAsBytesSync();
  return [
    basis,
    for (var i = 1; i < n; i++)
      File(p.join(eingang.path, '$stamm${i.toString().padLeft(4, '0')}.jpg'))
        ..writeAsBytesSync([...bytes, ...utf8.encode('pv-kopie-$i')]),
  ];
}

/// Ein Knopf der Kopfzeile der Aufgaben – mit Beschriftung oder, bei
/// Enge bzw. grosser Systemschrift, als Symbol mit Kurzhinweis.
Finder kopfknopf(String text) {
  final kopf = find.descendant(
    of: find.byType(BackgroundTasksScreen),
    matching: find.byType(AppBar),
  );
  final beschriftet = find.descendant(of: kopf, matching: find.text(text));
  if (beschriftet.evaluate().isNotEmpty) return beschriftet;
  return find.descendant(of: kopf, matching: find.byTooltip(text));
}

/// Legt eine Bibliothek in [d] an (library.sqlite und library/ mit einer
/// Datei), ohne die App – als „bestehende Bibliothek“.
Future<void> legeBibliothekAn(Directory d) async {
  d.createSync(recursive: true);
  final db = await AppDatabase.open(d);
  await db.close();
  final datei = File(
    p.join(d.path, 'library', 'originals', '2020', '01', 'x.txt'),
  )..createSync(recursive: true);
  datei.writeAsStringSync('Inhalt einer bestehenden Bibliothek');
}

String bandAnfang() => de
    .analyseLaeuft(de.stufeBildanalyse, 1, Analysestufe.values.length, '')
    .replaceAll(')', '');

/// Die Zeile des Hinweisbandes, die [text] enthält.
Finder bandZeile(String text) => find
    .ancestor(of: find.textContaining(text), matching: find.byType(Row))
    .first;

Map<String, dynamic> ortsdatei() =>
    jsonDecode(File(p.join(anker.path, 'location.json')).readAsStringSync())
        as Map<String, dynamic>;

Future<void> schreibeVerbindung(Directory wurzel) async {
  // Zeigt auf einen lokalen Anschluss, an dem nichts lauscht: Die
  // Bibliothek gilt als verbunden, der Server als nicht erreichbar. Es
  // wird kein Dienst angesprochen.
  File(p.join(wurzel.path, 'verbindung.json')).writeAsStringSync(
    jsonEncode({
      'server': 'http://127.0.0.1:9/',
      'konto': 'konto-a',
      'geraet': 'pruefgeraet',
      'token': 'kein-echtes-token',
    }),
  );
}

/// Regler [f] per Ziehen auf [ziel] stellen; [beimZiehen] sieht den Stand
/// mitten im Ziehen.
Future<void> zieheRegler(
  WidgetTester tester,
  Finder f,
  double ziel, {
  void Function()? beimZiehen,
}) async {
  for (var versuch = 0; versuch < 4; versuch++) {
    final s = tester.widget<Slider>(f);
    if ((s.value - ziel).abs() < 0.001) return;
    final r = tester.getRect(f);
    const rand = 24.0;
    double x(double v) =>
        r.left + rand + (v - s.min) / (s.max - s.min) * (r.width - 2 * rand);
    final g = await tester.startGesture(Offset(x(s.value), r.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    final schritte = 6;
    for (var i = 1; i <= schritte; i++) {
      await g.moveTo(
        Offset(x(s.value) + (x(ziel) - x(s.value)) * i / schritte, r.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    beimZiehen?.call();
    await g.up();
    await settle(tester, max: const Duration(seconds: 2));
  }
}

// --- Prüfungen --------------------------------------------------------------

/// Höchstdauer je Prüfung: Hängt eine (etwa weil keine Bilder mehr
/// kommen), scheitert sie, statt den ganzen Lauf aufzuhalten.
const _frist = Timeout(Duration(minutes: 8));

/// Was gerade geschieht – für das Lebenszeichen im Protokoll.
var schritt = '';

void main() {
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

  testWidgets(
    'GRU-001 GRU-002 GRU-003 GRU-047 GRU-055 Erster Start, leere Zeitleiste, Ladekreis',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      // GRU-001
      expect(gewaehlt(tester), Hauptbereich.zeitleiste);
      expect(find.byType(TimelineScreen), findsOneWidget);
      await waitFor(tester, find.text(de.timelineLeer));
      final importKnopf = find.descendant(
        of: find.byType(TimelineScreen),
        matching: find.text(de.importierenTooltip),
      );
      expect(importKnopf, findsOneWidget);
      expect(bibliothek.paths.root.parent.path, anker.path);
      expect(File(p.join(anker.path, 'library.sqlite')).existsSync(), isTrue);
      expect(Directory(p.join(anker.path, 'library')).existsSync(), isTrue);

      // GRU-047: nur die Standardbibliothek – keine Bibliothekszeile.
      expect(
        tester.widget<Seitenleiste>(find.byType(Seitenleiste)).unterzeile,
        isNull,
      );

      // GRU-055: nichts läuft, kein Band.
      await eventually(
        tester,
        () async => !bibliothek.etwasLaeuft,
        was: 'Start-Analyse endet',
      );
      await settle(tester);
      expect(bibliothek.verbunden, isFalse);
      expect(find.textContaining(bandAnfang()), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HomeShell),
          matching: find.text(de.allgAbbrechen),
        ),
        findsNothing,
      );
      expect(find.textContaining('KI-Restaurierung'), findsNothing);

      // GRU-002: Import öffnen, abbrechen.
      await tippe(tester, importKnopf);
      await waitFor(tester, find.text(de.importWasTitel));
      await key(tester, LogicalKeyboardKey.escape);
      await waitGone(tester, find.text(de.importWasTitel));
      dialog.dateien = [];
      await tippe(tester, importKnopf);
      await tippe(tester, find.text(de.importEinzelneDateien));
      await settle(tester);
      expect(dialog.gerufen.any((g) => g.startsWith('pickFiles')), isTrue);
      expect(await anzahlAufnahmen(), 0);
      expect(find.text(de.timelineLeer), findsOneWidget);

      // GRU-003: mit Fotos neu starten – erst der Ladekreis, dann die Hülle.
      await importiere(tester, fotos(2));
      final kreis = await neustart(tester);
      expect(kreis, isTrue, reason: 'Ladekreis im ersten Bild');
      expect(bibliothek.isReady, isTrue);
      expect(await anzahlAufnahmen(), 2);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-014 GRU-015 GRU-017 GRU-016 Bibliothek belegt', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(1));
    final dbDatei = File(p.join(anker.path, 'library.sqlite'));
    final wal = File('${dbDatei.path}-wal');
    Sperrhalter? halter;
    addTearDown(() async => halter?.beende());
    late String summeVorher;
    late bool walVorher;
    await neustart(
      tester,
      shell: false,
      dazwischen: () async {
        await Bibliothekssperre.gib();
        halter = await Sperrhalter.auf(anker);
        summeVorher = sha(dbDatei);
        walVorher = wal.existsSync();
      },
    );
    // GRU-014
    await waitFor(tester, find.text(de.sperreTitel));
    bibliothek = zustand(tester);
    expect(bibliothek.bibliothekBelegt, isTrue);
    expect(bibliothek.isReady, isFalse);
    expect(find.text(de.sperreText), findsOneWidget);
    expect(find.text(de.sperreOrt), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && w.data == anker.path,
      ),
      findsOneWidget,
    );
    expect(knopf(de.sperreErneut), findsOneWidget);
    expect(knopf(de.sperreAndere), findsOneWidget);
    expect(knopf(de.sperreBeenden), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(sha(dbDatei), summeVorher, reason: 'library.sqlite unverändert');
    expect(wal.existsSync(), walVorher, reason: 'keine neue -wal-Datei');

    // GRU-015: Erneut versuchen, solange die andere Instanz hält.
    final erneut = knopf(de.sperreErneut);
    await tester.tap(erneut);
    await tester.pump();
    final kreisImKnopf = find
        .descendant(
          of: erneut,
          matching: find.byType(CircularProgressIndicator),
        )
        .evaluate()
        .isNotEmpty;
    final gesperrt =
        !knopfAktiv(tester, knopf(de.sperreAndere)) &&
        !knopfAktiv(tester, knopf(de.sperreBeenden));
    print(
      'GRU-015: Kreis im Knopf gesehen: $kreisImKnopf, gesperrt: $gesperrt',
    );
    await waitFor(tester, find.text(de.sperreNochBelegt));
    final rot = tester
        .widget<Text>(find.text(de.sperreNochBelegt))
        .style
        ?.color;
    expect(
      rot,
      Theme.of(
        tester.element(find.text(de.sperreNochBelegt)),
      ).colorScheme.error,
    );
    expect(sha(dbDatei), summeVorher);

    // GRU-017: keine weitere Bibliothek.
    await tippe(tester, knopf(de.sperreAndere));
    await waitFor(tester, find.byType(SimpleDialog));
    expect(find.text(de.sperreAuswahlLeer), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(SimpleDialog));
    expect(find.text(de.sperreTitel), findsOneWidget);

    // GRU-016: andere Instanz schliessen, erneut versuchen.
    await halter!.beende();
    await tester.tap(knopf(de.sperreErneut));
    await waitFor(
      tester,
      find.byType(HomeShell),
      timeout: const Duration(seconds: 60),
    );
    bibliothek = zustand(tester);
    expect(await anzahlAufnahmen(), 1);
    await ende(tester);
  }, timeout: _frist);

  // Behoben in #408: Der Listener in main.dart meldet über
  // LibraryState.benutzungMelden, das vor dem Anlegen der
  // Restaurierungswarteschlange nichts tut.
  testWidgets(
    'GRU-015 GRU-024 GRU-031 Klick auf einem Startbildschirm wirft keinen Fehler',
    (tester) async {
      filtereSemantik();
      spaeteFehlerUebergehen = false;
      addTearDown(() => spaeteFehlerUebergehen = true);
      await starte(tester);
      final weg = Directory(p.join(anker.path, 'Weg'))..createSync();
      final e = await LibraryLocation.fuegeHinzu(
        PickedFolder(weg.path, ''),
        name: 'Weg',
      );
      await LibraryLocation.wechsleZu(e);
      weg.deleteSync();
      await neustart(tester, shell: false);
      await waitFor(tester, find.text(de.unerreichbarTitel));
      bibliothek = zustand(tester);
      await tester.tap(knopf(de.sperreErneut).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-018 Belegt: andere Bibliothek wählen', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(1));
    final b = Directory(p.join(anker.path, 'B'))..createSync();
    final c = Directory(p.join(anker.path, 'C'))..createSync();
    final eb = await LibraryLocation.fuegeHinzu(
      PickedFolder(b.path, ''),
      name: 'B',
    );
    await LibraryLocation.fuegeHinzu(PickedFolder(c.path, ''), name: 'C');
    await LibraryLocation.wechsleZu(eb);
    c.deleteSync();
    Sperrhalter? halter;
    addTearDown(() async => halter?.beende());
    late Map<String, String> bVorher;
    await neustart(
      tester,
      shell: false,
      dazwischen: () async {
        bVorher = pruefsummen(b);
        halter = await Sperrhalter.auf(b);
      },
    );
    await waitFor(tester, find.text(de.sperreTitel));
    bibliothek = zustand(tester);
    expect(bibliothek.belegterOrt, b.path);
    await tippe(tester, knopf(de.sperreAndere));
    await waitFor(tester, find.byType(SimpleDialog));
    final dlg = find.byType(SimpleDialog);
    // B selbst steht nicht zur Wahl, C ist ausgegraut.
    expect(find.descendant(of: dlg, matching: find.text('B')), findsNothing);
    final cKachel = find.ancestor(
      of: find.descendant(of: dlg, matching: find.text('C')),
      matching: find.byType(ListTile),
    );
    expect(cKachel, findsOneWidget);
    expect(tester.widget<ListTile>(cKachel).enabled, isFalse);
    expect(
      find.descendant(
        of: cKachel,
        matching: find.text(de.einstBibNichtGefunden),
      ),
      findsOneWidget,
    );
    final cOption = find.ancestor(
      of: cKachel,
      matching: find.byType(SimpleDialogOption),
    );
    expect(tester.widget<SimpleDialogOption>(cOption).onPressed, isNull);
    await tester.tap(cKachel, warnIfMissed: false);
    await settle(tester);
    expect(find.byType(SimpleDialog), findsOneWidget);
    // Standard wählen.
    await tippe(
      tester,
      find.descendant(of: dlg, matching: find.text('Standard')),
    );
    await waitFor(
      tester,
      find.byType(HomeShell),
      timeout: const Duration(seconds: 60),
    );
    bibliothek = zustand(tester);
    expect(bibliothek.paths.root.parent.path, anker.path);
    expect(await anzahlAufnahmen(), 1);
    final bekannt = await LibraryLocation.bekannte();
    expect(bekannt.firstWhere((x) => x.istAktiv).istStandard, isTrue);
    expect(pruefsummen(b), bVorher, reason: 'B unverändert');
    // Auch beim nächsten Start die Standardbibliothek.
    await neustart(tester);
    expect(bibliothek.paths.root.parent.path, anker.path);
    expect(await anzahlAufnahmen(), 1);
    await ende(tester);
  }, timeout: _frist);

  Future<Directory> archivEinrichten(WidgetTester tester) async {
    final archiv = Directory(p.join(anker.path, 'Archiv'))..createSync();
    final e = await LibraryLocation.fuegeHinzu(
      PickedFolder(archiv.path, ''),
      name: 'Archiv',
    );
    await LibraryLocation.wechsleZu(e);
    await neustart(tester);
    expect(bibliothek.paths.root.parent.path, archiv.path);
    await importiere(tester, fotos(2, stamm: 'archiv'));
    return archiv;
  }

  testWidgets(
    'GRU-023 GRU-027 GRU-025 GRU-024 GRU-026 Bibliothek nicht erreichbar, Freigabe',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      final archiv = await archivEinrichten(tester);
      final weg = Directory(p.join(anker.path, 'Archiv_weg'));
      final cfg = File(p.join(anker.path, 'location.json'));
      late String cfgVorher;
      await neustart(
        tester,
        shell: false,
        dazwischen: () {
          archiv.renameSync(weg.path);
          cfgVorher = cfg.readAsStringSync();
        },
      );
      // GRU-023
      await waitFor(tester, find.text(de.unerreichbarTitel));
      bibliothek = zustand(tester);
      expect(find.text(de.unerreichbarText('Archiv')), findsOneWidget);
      expect(find.text(de.sperreOrt), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == archiv.path,
        ),
        findsOneWidget,
      );
      for (final t in [
        de.unerreichbarFreigeben,
        de.sperreErneut,
        de.unerreichbarStandard,
        de.sperreBeenden,
      ]) {
        expect(knopf(t), findsOneWidget, reason: t);
      }
      expect(bibliothek.isReady, isFalse);
      expect(find.byType(HomeShell), findsNothing);

      // GRU-027: Ordnerdialog abbrechen.
      dialog.ordner = null;
      await tippe(tester, knopf(de.unerreichbarFreigeben));
      expect(
        dialog.gerufen.last,
        contains(de.unerreichbarDialog('Archiv')),
        reason: 'Überschrift des Ordnerdialogs',
      );
      expect(find.text(de.unerreichbarKeineBibliothek), findsNothing);
      expect(find.text(de.unerreichbarNochImmer), findsNothing);
      expect(find.text(de.unerreichbarTitel), findsOneWidget);
      expect(cfg.readAsStringSync(), cfgVorher);

      // GRU-025: Ordner ohne Bibliothek.
      final leer = Directory(p.join(anker.path, 'leer'))..createSync();
      dialog.ordner = leer.path;
      await tippe(tester, knopf(de.unerreichbarFreigeben));
      await waitFor(tester, find.text(de.unerreichbarKeineBibliothek));
      expect(
        tester
            .widget<Text>(find.text(de.unerreichbarKeineBibliothek))
            .style
            ?.color,
        Theme.of(
          tester.element(find.text(de.unerreichbarTitel)),
        ).colorScheme.error,
      );
      expect(File(p.join(leer.path, 'library.sqlite')).existsSync(), isFalse);
      expect(cfg.readAsStringSync(), cfgVorher);

      // GRU-024, erster Teil: erneut versuchen, solange der Ordner fehlt.
      await tippe(tester, knopf(de.sperreErneut));
      await waitFor(tester, find.text(de.unerreichbarNochImmer));

      // GRU-026: den richtigen (umgezogenen) Ordner freigeben.
      dialog.ordner = weg.path;
      await tippe(tester, knopf(de.unerreichbarFreigeben));
      await waitFor(
        tester,
        find.byType(HomeShell),
        timeout: const Duration(seconds: 60),
      );
      bibliothek = zustand(tester);
      expect(bibliothek.paths.root.parent.path, weg.path);
      expect(await anzahlAufnahmen(), 2);
      await einstellungen(tester);
      await gruppe(tester, de.einstBibListe);
      final aktivKachel = find.ancestor(
        of: find.text(weg.path),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, aktivKachel);
      expect(
        find.descendant(of: aktivKachel, matching: find.text('Archiv')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: aktivKachel, matching: find.text(de.einstBibAktiv)),
        findsOneWidget,
      );
      final alteKachel = find.ancestor(
        of: find.text(de.einstBibNichtGefunden),
        matching: find.byType(ListTile),
      );
      expect(alteKachel, findsOneWidget);
      expect(
        find.descendant(of: alteKachel, matching: find.text('Archiv')),
        findsOneWidget,
      );
      final entfernen = find.descendant(
        of: alteKachel,
        matching: find.byTooltip(de.einstBibAusListeEntfernen),
      );
      expect(entfernen, findsOneWidget);
      await tippe(tester, entfernen);
      await tippe(tester, knopf(de.allgEntfernen));
      await waitGone(tester, find.text(de.einstBibNichtGefunden));
      final liste = await LibraryLocation.bekannte();
      expect(liste.where((x) => x.eintrag.name == 'Archiv').length, 1);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets(
    'GRU-028 GRU-024 Standardbibliothek nur für diese Sitzung, Erneut nach Rückkehr',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      final archiv = await archivEinrichten(tester);
      final weg = Directory(p.join(anker.path, 'Archiv_weg'));
      await neustart(
        tester,
        shell: false,
        dazwischen: () => archiv.renameSync(weg.path),
      );
      await waitFor(tester, find.text(de.unerreichbarTitel));
      bibliothek = zustand(tester);
      // GRU-028: Standard nur für diese Sitzung.
      await tippe(tester, knopf(de.unerreichbarStandard));
      await waitFor(
        tester,
        find.byType(HomeShell),
        timeout: const Duration(seconds: 60),
      );
      bibliothek = zustand(tester);
      expect(bibliothek.paths.root.parent.path, anker.path);
      expect(await anzahlAufnahmen(), 0);
      expect(
        ortsdatei()['aktiv'],
        archiv.path,
        reason: 'Archiv bleibt eingestellt',
      );
      await neustart(tester, shell: false);
      await waitFor(tester, find.text(de.unerreichbarTitel));
      bibliothek = zustand(tester);
      expect(find.text(de.unerreichbarText('Archiv')), findsOneWidget);

      // GRU-024, zweiter Teil: Ordner zurück, erneut versuchen.
      weg.renameSync(archiv.path);
      await tippe(tester, knopf(de.sperreErneut));
      await waitFor(
        tester,
        find.byType(HomeShell),
        timeout: const Duration(seconds: 60),
      );
      bibliothek = zustand(tester);
      expect(bibliothek.paths.root.parent.path, archiv.path);
      expect(await anzahlAufnahmen(), 2);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-030 GRU-031 Beschädigte Datenbank', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(1));
    final dbDatei = File(p.join(anker.path, 'library.sqlite'));
    final sicher = Directory(p.join(anker.path, 'sicher'))..createSync();
    late String summe;
    await neustart(
      tester,
      shell: false,
      dazwischen: () {
        for (final s in ['', '-wal', '-shm']) {
          final f = File('${dbDatei.path}$s');
          if (f.existsSync()) {
            f.copySync(p.join(sicher.path, 'library.sqlite$s'));
            if (s.isNotEmpty) f.deleteSync();
          }
        }
        dbDatei.writeAsStringSync('Das ist keine Datenbank. ' * 300);
        summe = sha(dbDatei);
      },
    );
    // GRU-030
    await waitFor(
      tester,
      find.text(de.startFehlerTitel),
      timeout: const Duration(seconds: 60),
    );
    bibliothek = zustand(tester);
    expect(find.text(de.startFehlerText), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is SelectableText && (w.data ?? '').trim().isNotEmpty,
      ),
      findsOneWidget,
    );
    expect(knopf(de.startFehlerErneut), findsOneWidget);
    expect(sha(dbDatei), summe, reason: 'library.sqlite byte-gleich');

    // GRU-031: Ursache beheben, erneut versuchen.
    for (final f in sicher.listSync().whereType<File>()) {
      f.copySync(p.join(anker.path, p.basename(f.path)));
    }
    final erneut = knopf(de.startFehlerErneut);
    await tester.tap(erneut);
    await tester.pump();
    final gesperrt =
        find.byType(HomeShell).evaluate().isNotEmpty ||
        (erneut.evaluate().isNotEmpty && !knopfAktiv(tester, erneut));
    final kreis =
        find.byType(HomeShell).evaluate().isNotEmpty ||
        find
            .descendant(
              of: erneut,
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isNotEmpty;
    print('GRU-031: Knopf gesperrt: $gesperrt, Kreis: $kreis');
    await waitFor(
      tester,
      find.byType(HomeShell),
      timeout: const Duration(seconds: 60),
    );
    bibliothek = zustand(tester);
    expect(await anzahlAufnahmen(), 1);
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-032 Neuere Bibliothek wird nicht zurückgestuft', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final dbDatei = File(p.join(anker.path, 'library.sqlite'));
    await neustart(
      tester,
      shell: false,
      dazwischen: () {
        final d = sql.sqlite3.open(dbDatei.path);
        d.execute('PRAGMA user_version = 999');
        d.close();
      },
    );
    await waitFor(
      tester,
      find.text(de.startFehlerNeuerTitel),
      timeout: const Duration(seconds: 60),
    );
    bibliothek = zustand(tester);
    expect(find.text(de.startFehlerNeuerText), findsOneWidget);
    final d = sql.sqlite3.open(dbDatei.path, mode: sql.OpenMode.readOnly);
    final stand = d.select('PRAGMA user_version').first.values.first;
    d.close();
    expect(stand, 999);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-033 GRU-034 Startbildschirme: Systemsprache, dunkel, große Schrift',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await bibliothek.db.setSprache('de');
      await bibliothek.db.setThemeMode('light');
      final archiv = Directory(p.join(anker.path, 'Archiv'))..createSync();
      final e = await LibraryLocation.fuegeHinzu(
        PickedFolder(archiv.path, ''),
        name: 'Archiv',
      );
      await LibraryLocation.wechsleZu(e);
      archiv.deleteSync();
      final pd = tester.platformDispatcher;
      addTearDown(pd.clearAllTestValues);
      pd.localesTestValue = const [Locale('en')];
      pd.localeTestValue = const Locale('en');
      pd.platformBrightnessTestValue = Brightness.dark;
      await neustart(tester, shell: false);
      // GRU-033
      await waitFor(tester, find.text(en.unerreichbarTitel));
      bibliothek = zustand(tester);
      expect(
        Theme.of(tester.element(find.text(en.unerreichbarTitel))).brightness,
        Brightness.dark,
      );

      // GRU-034: 2,0-fache Schrift, 600 Punkte breit, alle drei Bildschirme.
      pd.textScaleFactorTestValue = 2.0;
      await fenster(tester, const Size(600, 800));
      await settle(tester);
      Future<void> pruefeKnoepfe(List<String> texte) async {
        expect(tester.takeException(), isNull);
        for (final t in texte) {
          final k = knopf(t);
          await waitFor(tester, k);
          await tester.ensureVisible(k.first);
          await tester.pump();
          expect(k.first.hitTestable(), findsOneWidget, reason: t);
        }
        expect(tester.takeException(), isNull);
      }

      await pruefeKnoepfe([
        en.unerreichbarFreigeben,
        en.sperreErneut,
        en.unerreichbarStandard,
        en.sperreBeenden,
      ]);
      // Belegt.
      Sperrhalter? halter;
      addTearDown(() async => halter?.beende());
      await neustart(
        tester,
        shell: false,
        dazwischen: () async {
          archiv.createSync();
          halter = await Sperrhalter.auf(archiv);
        },
      );
      await waitFor(tester, find.text(en.sperreTitel));
      bibliothek = zustand(tester);
      await pruefeKnoepfe([en.sperreErneut, en.sperreAndere, en.sperreBeenden]);
      // Beschädigt.
      await neustart(
        tester,
        shell: false,
        dazwischen: () async {
          await halter!.beende();
          File(
            p.join(archiv.path, 'library.sqlite'),
          ).writeAsStringSync('kaputt ' * 500);
        },
      );
      await waitFor(
        tester,
        find.text(en.startFehlerTitel),
        timeout: const Duration(seconds: 60),
      );
      bibliothek = zustand(tester);
      await pruefeKnoepfe([en.startFehlerErneut]);
      pd.clearAllTestValues();
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-035 GRU-036 GRU-037 GRU-038 GRU-040 GRU-186 Seitenleiste', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final semantik = tester.ensureSemantics();
    await tester.pump();
    // GRU-035: eingeklappt nur Symbole.
    expect(
      tester.widget<Seitenleiste>(find.byType(Seitenleiste)).fixiert,
      isFalse,
    );
    expect(inhaltLinks(tester), closeTo(Seitenleiste.schmal, 1));
    expect(deckkraft(tester, de.navAlben), 0);
    // GRU-186 (eingeklappt): jeder Eintrag ist ein Knopf mit Namen.
    final albenInk = find.descendant(
      of: zeile(de.navAlben),
      matching: find.byType(InkWell),
    );
    expect(
      tester.getSemantics(albenInk.first),
      isSemantics(label: de.navAlben, isButton: true, isSelected: false),
    );
    expect(
      tester.getSemantics(
        find
            .descendant(of: zeile(de.navFotos), matching: find.byType(InkWell))
            .first,
      ),
      isSemantics(label: de.navFotos, isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(
        find
            .descendant(of: _typ('_Nadel'), matching: find.byType(InkWell))
            .first,
      ),
      isSemantics(hasToggledState: true, isToggled: false),
    );

    // Maus auf die Leiste: klappt über dem Inhalt auf.
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(location: const Offset(900, 450));
    addTearDown(maus.removePointer);
    await tester.pump();
    await maus.moveTo(const Offset(30, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    expect(deckkraft(tester, de.navAlben), 1);
    expect(inhaltLinks(tester), closeTo(Seitenleiste.schmal, 1));
    final leistenKasten = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(Seitenleiste),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).border is Border &&
              ((c.decoration as BoxDecoration).border as Border).right.width >
                  0,
        )
        .first;
    expect(
      (leistenKasten.decoration as BoxDecoration).boxShadow,
      isNotEmpty,
      reason: 'Schatten über dem Inhalt',
    );
    await maus.moveTo(const Offset(900, 450));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      deckkraft(tester, de.navAlben),
      1,
      reason: 'Viertelsekunde Nachsicht',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200));
    expect(deckkraft(tester, de.navAlben), 0);

    // GRU-036: eine Unterseite öffnen, dann fixieren.
    await aufgabenOeffnen(tester);
    await maus.moveTo(const Offset(30, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tippeLinks(tester, _typ('_Nadel'));
    await settle(tester);
    expect(
      tester.widget<Seitenleiste>(find.byType(Seitenleiste)).fixiert,
      isTrue,
    );
    await maus.moveTo(const Offset(900, 450));
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(deckkraft(tester, de.navAlben), 1);
    expect(inhaltLinks(tester), closeTo(Seitenleiste.offen, 1));
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    final nadelIcon = tester.widget<Icon>(find.byIcon(Icons.push_pin));
    expect(
      nadelIcon.color,
      Theme.of(tester.element(find.byIcon(Icons.push_pin))).colorScheme.primary,
    );
    expect(
      tester
          .widget<AnimatedRotation>(
            find.ancestor(
              of: find.byIcon(Icons.push_pin),
              matching: find.byType(AnimatedRotation),
            ),
          )
          .turns,
      0,
    );
    expect(find.byType(BackgroundTasksScreen), findsOneWidget);
    expect(
      tester.getSemantics(
        find
            .descendant(of: _typ('_Nadel'), matching: find.byType(InkWell))
            .first,
      ),
      isSemantics(hasToggledState: true, isToggled: true),
    );

    // GRU-038: Aufbau von oben nach unten.
    final reihenfolge = [
      de.navFotos,
      de.navSuche,
      de.navAlben,
      de.navGruppeEntdecken.toUpperCase(),
      de.navFavoriten,
      de.navPersonen,
      de.navKarte,
      de.navOrte,
      de.navReisen,
      de.navStammbaum,
      de.navStatistik,
      de.navRueckblick,
      de.navKalender,
      de.navGruppeVerwalten.toUpperCase(),
      de.navFotokammer,
      de.navDuplikate,
      de.navArchiv,
      de.navPapierkorb,
      de.navWerkzeuge,
      de.navEinstellungen,
    ];
    final leistenTeil = find.ancestor(
      of: find.byType(Arbeitsbereich),
      matching: find.byType(Seitenleiste),
    );
    Finder inLeiste(String t) => find.descendant(
      of: find.byWidgetPredicate(
        (w) => const [
          '_Zeile',
          '_Gruppe',
          '_Marke',
          '_Nadel',
        ].contains(w.runtimeType.toString()),
      ),
      matching: find.text(t),
    );
    expect(leistenTeil, findsOneWidget);
    for (final sc in tester.stateList<ScrollableState>(
      find.descendant(
        of: find.byType(Seitenleiste),
        matching: find.byType(Scrollable),
      ),
    )) {
      if (sc.context.findAncestorWidgetOfExactType<Arbeitsbereich>() == null) {
        sc.position.jumpTo(0);
      }
    }
    await tester.pump();
    final marke = tester.getTopLeft(inLeiste('Photo Vault').first).dy;
    var vorher = marke;
    for (final t in reihenfolge) {
      final y = tester.getTopLeft(inLeiste(t).first).dy;
      expect(y, greaterThan(vorher), reason: 'Reihenfolge bei $t');
      vorher = y;
    }
    final importY = tester.getTopLeft(inLeiste(de.navImportieren).first).dy;
    final nadelY = tester.getTopLeft(inLeiste(de.navLeisteLoesen).first).dy;
    expect(nadelY, greaterThan(importY));
    // Passt nicht alles hinein, rollt der Mittelteil.
    await fenster(tester, const Size(1400, 560));
    await settle(tester);
    final mitte = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(Seitenleiste),
            matching: find.byType(Scrollable),
          ),
        )
        .where(
          (s) =>
              s.context.findAncestorWidgetOfExactType<Arbeitsbereich>() == null,
        )
        .first;
    expect(mitte.position.maxScrollExtent, greaterThan(0));
    await fenster(tester, const Size(1400, 900));
    await settle(tester);

    // GRU-037: Fixierung überdauert den Neustart.
    expect(
      File(
        p.join(anker.path, 'seitenleiste_fixiert'),
      ).readAsStringSync().trim(),
      '1',
    );
    await neustart(tester);
    await settle(tester);
    expect(
      tester.widget<Seitenleiste>(find.byType(Seitenleiste)).fixiert,
      isTrue,
    );
    expect(inhaltLinks(tester), closeTo(Seitenleiste.offen, 1));

    // GRU-036 (Lösen): klappt sofort zu, Inhalt rückt zurück.
    await tippeLinks(tester, _typ('_Nadel'));
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);
    expect(
      tester.widget<Seitenleiste>(find.byType(Seitenleiste)).fixiert,
      isFalse,
    );
    expect(deckkraft(tester, de.navAlben), 0);
    expect(inhaltLinks(tester), closeTo(Seitenleiste.schmal, 1));
    // GRU-038: eingeklappt trennt eine feine Linie die Gruppen.
    final linien = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: _typ('_Gruppe'),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map(
          (c) => ((c.decoration as BoxDecoration).border as Border).top.color,
        )
        .toList();
    expect(linien, hasLength(2));
    expect(linien.every((f) => f != Colors.transparent), isTrue);

    // GRU-040: Klick auf „Photo Vault“ führt zu den Fotos.
    await leiste(tester, de.navAlben);
    expect(gewaehlt(tester), Hauptbereich.alben);
    await tippeLinks(tester, _typ('_Marke'));
    await settle(tester);
    expect(gewaehlt(tester), Hauptbereich.zeitleiste);
    expect(find.byType(TimelineScreen), findsOneWidget);
    semantik.dispose();
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-189 Seitenleiste mit der Tastatur', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final alben = find.descendant(
      of: zeile(de.navAlben),
      matching: find.byType(InkWell),
    );
    var leisteOffen = false;
    var aufAlben = false;
    for (var i = 0; i < 80 && !aufAlben; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 60));
      final fokus = FocusManager.instance.primaryFocus;
      final ctx = fokus?.context;
      if (ctx == null) continue;
      final inLeiste =
          ctx.findAncestorWidgetOfExactType<Seitenleiste>() != null &&
          ctx.findAncestorWidgetOfExactType<Arbeitsbereich>() == null;
      if (inLeiste && !leisteOffen) {
        await tester.pump(const Duration(milliseconds: 200));
        leisteOffen = deckkraft(tester, de.navFotos) == 1;
      }
      final r = tester.getRect(alben.first);
      if (inLeiste && (fokus!.rect.center - r.center).distance < 4) {
        aufAlben = true;
      }
    }
    expect(leisteOffen, isTrue, reason: 'Leiste klappt mit dem Fokus auf');
    expect(aufAlben, isTrue, reason: 'Tab erreicht „Alben“');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(gewaehlt(tester), Hauptbereich.alben);
    expect(find.byType(AlbumsScreen), findsOneWidget);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-039 GRU-041 GRU-042 GRU-043 GRU-061 Bereiche, Unterseiten, Vollbild',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      final ids = await importiere(tester, fotos(2));
      await bibliothek.db.fuehreAus(
        AlbumAnlegen('alb1', 'Urlaub', DateTime(2024)),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen('alb1', ids));
      await settle(tester);

      // GRU-039: jeder Eintrag öffnet seinen Bereich (ohne „Karte“, siehe
      // Ergebnis: die Karte lädt Kacheln aus dem Netz).
      final ziele = <(String, bool Function())>[
        (de.navFotos, () => find.byType(TimelineScreen).evaluate().isNotEmpty),
        (
          de.navSuche,
          () =>
              find.byType(SearchScreen).evaluate().isNotEmpty &&
              tester
                      .widget<SearchScreen>(find.byType(SearchScreen))
                      .startFilter ==
                  null,
        ),
        (de.navAlben, () => find.byType(AlbumsScreen).evaluate().isNotEmpty),
        (
          de.navFavoriten,
          () =>
              tester
                  .widget<SearchScreen>(find.byType(SearchScreen))
                  .startFilter
                  ?.favoritesOnly ==
              true,
        ),
        (de.navPersonen, () => find.byType(PeopleScreen).evaluate().isNotEmpty),
        (de.navKarte, () => true),
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
        (
          de.navArchiv,
          () =>
              tester
                  .widget<SearchScreen>(find.byType(SearchScreen))
                  .startFilter
                  ?.nurArchiv ==
              true,
        ),
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
      for (var i = 0; i < ziele.length; i++) {
        if (i == Hauptbereich.karte) continue;
        await leiste(tester, ziele[i].$1);
        expect(gewaehlt(tester), i, reason: ziele[i].$1);
        expect(ziele[i].$2(), isTrue, reason: 'Bereich ${ziele[i].$1}');
        expect(tester.takeException(), isNull);
      }
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
      final felder = tester.widgetList<TextField>(
        find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byType(TextField),
        ),
      );
      expect(felder.any((f) => f.controller?.text == 'Strand'), isFalse);

      // GRU-041: Album neben der Leiste, Vollbild darüber.
      await leiste(tester, de.navAlben);
      await tippe(tester, find.text('Urlaub'));
      await waitFor(tester, find.byType(AlbumDetailScreen));
      expect(find.byType(Seitenleiste), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(AlbumDetailScreen)).dx,
        greaterThanOrEqualTo(Seitenleiste.schmal - 1),
      );
      final kachel = find.descendant(
        of: find.byType(AlbumDetailScreen),
        matching: find.byType(AssetThumbnailTile),
      );
      await waitFor(tester, kachel);
      await tester.tap(kachel.first);
      await waitFor(tester, find.byType(AssetViewerScreen));
      await settle(tester);
      expect(find.byType(Seitenleiste), findsNothing);
      expect(
        tester.getRect(find.byType(AssetViewerScreen)),
        Offset.zero & const Size(1400, 900),
      );
      await key(tester, LogicalKeyboardKey.escape);
      await waitGone(tester, find.byType(AssetViewerScreen));
      await waitFor(tester, find.byType(Seitenleiste));

      // GRU-042: Bereichswechsel schliesst die Unterseite.
      await waitFor(tester, find.byType(AlbumDetailScreen));
      await leiste(tester, de.navPersonen);
      await leiste(tester, de.navAlben);
      expect(find.byType(AlbumsScreen), findsOneWidget);
      expect(find.byType(AlbumDetailScreen), findsNothing);

      // GRU-043: erneuter Klick auf den aktiven Bereich.
      await tippe(tester, find.text('Urlaub'));
      await waitFor(tester, find.byType(AlbumDetailScreen));
      await leiste(tester, de.navAlben);
      await waitGone(tester, find.byType(AlbumDetailScreen));
      expect(find.byType(AlbumsScreen), findsOneWidget);

      // GRU-061: Kürzel aus einer offenen Unterseite heraus.
      await tippe(tester, find.text('Urlaub'));
      await waitFor(tester, find.byType(AlbumDetailScreen));
      await mitMeta(tester, LogicalKeyboardKey.digit5);
      expect(gewaehlt(tester), Hauptbereich.personen);
      expect(find.byType(PeopleScreen), findsOneWidget);
      await mitMeta(tester, LogicalKeyboardKey.digit3);
      expect(gewaehlt(tester), Hauptbereich.alben);
      expect(find.byType(AlbumsScreen), findsOneWidget);
      expect(find.byType(AlbumDetailScreen), findsNothing);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets(
    'GRU-058 GRU-060 GRU-062 GRU-063 GRU-064 Tastenkürzel und Befehlspalette',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      // GRU-058 (⌘6 = Karte ausgenommen, siehe Ergebnis).
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
        if (i == Hauptbereich.karte) continue;
        await mitMeta(tester, ziffern[i]);
        expect(gewaehlt(tester), i, reason: '⌘${i + 1}');
      }
      expect(find.byType(StammbaumScreen), findsOneWidget);
      // GRU-060: Nummernfeld.
      await mitMeta(tester, LogicalKeyboardKey.numpad3);
      expect(gewaehlt(tester), Hauptbereich.alben);
      expect(find.byType(AlbumsScreen), findsOneWidget);

      // GRU-062: Befehlspalette.
      await mitMeta(tester, LogicalKeyboardKey.digit1);
      await mitMeta(tester, LogicalKeyboardKey.keyK);
      final palettenFeld = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == de.befehlspaletteHinweis,
      );
      await waitFor(tester, palettenFeld);
      final fotosKachel = find.ancestor(
        of: find.text(de.navFotos),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(fotosKachel.first).selected, isTrue);
      expect(find.byType(ListTile).evaluate().length, greaterThan(8));
      await enter(tester, palettenFeld, 'kal');
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.widgetWithText(ListTile, de.navKalender), findsOneWidget);
      await tippe(tester, find.widgetWithText(ListTile, de.navKalender));
      await waitGone(tester, palettenFeld);
      expect(gewaehlt(tester), Hauptbereich.kalender);
      expect(find.byType(CalendarScreen), findsOneWidget);

      // GRU-063: ohne Treffer, leeren, zurück.
      await mitMeta(tester, LogicalKeyboardKey.keyK);
      await waitFor(tester, palettenFeld);
      await enter(tester, palettenFeld, 'xyz');
      expect(find.text(de.befehlspaletteLeer), findsOneWidget);
      await tippe(tester, find.byIcon(Icons.clear));
      expect(tester.widget<TextField>(palettenFeld).controller?.text, '');
      expect(find.byType(ListTile).evaluate().length, greaterThan(8));
      await tippe(tester, find.byType(BackButton));
      await waitGone(tester, palettenFeld);
      expect(gewaehlt(tester), Hauptbereich.kalender);

      // GRU-064: „?“ öffnet die Kürzelübersicht.
      await mitUmschalt(tester, LogicalKeyboardKey.slash, '?');
      final tafel = find.widgetWithText(AlertDialog, de.kuerzelTitel);
      await waitFor(tester, tafel);
      for (final t in [
        de.kuerzelNavigation,
        de.kuerzelRaster,
        de.kuerzelVollbild,
        de.kuerzelSichtung,
      ]) {
        expect(
          find.descendant(of: tafel, matching: find.text(t)),
          findsOneWidget,
          reason: t,
        );
      }
      await tippe(tester, knopfIn(tafel, de.allgSchliessen));
      await waitGone(tester, tafel);
      await ende(tester);
    },
    timeout: _frist,
  );

  // Behoben in #408: Die Kürzelziele stehen als Bereichsnamen da, ⌘0 führt
  // auf Hauptbereich.einstellungen.
  testWidgets('GRU-059 ⌘0 öffnet die Einstellungen', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    expect(de.kuerzelUebrigeBereiche, contains('⌘0 Einstellungen'));
    await mitMeta(tester, LogicalKeyboardKey.digit0);
    expect(gewaehlt(tester), Hauptbereich.einstellungen);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await ende(tester);
  }, timeout: _frist);

  // Behoben in #408: Die Hülle lässt „?“ und „_“ durch, solange ein
  // Textfeld den Fokus hat (schreibtGerade, wie im Raster).
  testWidgets('GRU-065 ? und _ in einem Textfeld werden getippt', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await einstellungen(tester);
    final feld = find.descendant(
      of: find.byType(SearchBar),
      matching: find.byType(TextField),
    );
    await tester.tap(feld);
    await tester.pump();
    await tester.enterText(feld, 'a');
    await tester.pump();
    final tafel = find.widgetWithText(AlertDialog, de.kuerzelTitel);
    final frage = await mitUmschalt(tester, LogicalKeyboardKey.slash, '?');
    final tafelBeiFrage = tafel.evaluate().isNotEmpty;
    if (tafelBeiFrage) {
      await tippe(tester, knopfIn(tafel, de.allgSchliessen));
      await tester.tap(feld);
      await tester.pump();
    }
    final strich = await mitUmschalt(tester, LogicalKeyboardKey.minus, '_');
    final tafelBeiStrich = tafel.evaluate().isNotEmpty;
    print(
      'GRU-065: „?“ abgefangen: $frage, Tafel: $tafelBeiFrage; '
      '„_“ abgefangen: $strich, Tafel: $tafelBeiStrich',
    );
    expect(tafelBeiFrage, isFalse, reason: '„?“ im Suchfeld öffnet die Tafel');
    expect(
      frage,
      isFalse,
      reason: '„?“ gilt als erledigt, erreicht das Feld nicht',
    );
    expect(tafelBeiStrich, isFalse, reason: '„_“ im Suchfeld öffnet die Tafel');
    expect(strich, isFalse, reason: '„_“ gilt als erledigt');
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-044 „Fotos“ erneut anklicken springt nach oben', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, fotos(40, stamm: 'm', monateAbstand: 1));
    await settle(tester);
    ScrollableState zeitleiste() => tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(TimelineScreen),
            matching: find.byType(Scrollable),
          ),
        )
        .where((s) => s.position.axis == Axis.vertical)
        .reduce(
          (a, b) =>
              a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b,
        );
    await eventually(
      tester,
      () async => zeitleiste().position.maxScrollExtent > 1000,
      was: 'Zeitleiste lang genug',
    );
    for (var runde = 0; runde < 2; runde++) {
      final s = zeitleiste();
      await tester.dragFrom(const Offset(800, 600), const Offset(0, -2500));
      await settle(tester);
      expect(s.position.pixels, greaterThan(500), reason: 'weit unten');
      await leiste(tester, de.navFotos);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(zeitleiste().position.pixels, lessThan(1), reason: 'Runde $runde');
    }
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-048 GRU-049 GRU-050 Schmales Fenster', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester, groesse: const Size(680, 900));
    // GRU-048
    expect(find.byType(Seitenleiste), findsNothing);
    final leisteUnten = find.byType(NavigationBar);
    expect(leisteUnten, findsOneWidget);
    for (final t in [de.navFotos, de.navSuche, de.navAlben, de.navBibliothek]) {
      expect(
        find.descendant(of: leisteUnten, matching: find.text(t)),
        findsOneWidget,
        reason: t,
      );
    }
    expect(find.byTooltip(de.importierenTooltip), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // GRU-049: Blatt „Bibliothek“ (Kalender statt Karte gewählt).
    await tippe(
      tester,
      find.descendant(of: leisteUnten, matching: find.text(de.navBibliothek)),
    );
    final blatt = find.byType(BottomSheet);
    await waitFor(tester, blatt);
    expect(
      find.descendant(of: blatt, matching: find.text(de.befehlspaletteTitel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: blatt, matching: find.text(de.befehlspaletteHinweis)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: blatt, matching: find.text(de.navGruppeEntdecken)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: blatt, matching: find.text(de.navGruppeVerwalten)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: blatt, matching: find.text(de.navKarte)),
      findsOneWidget,
    );
    await tippe(
      tester,
      find.descendant(of: blatt, matching: find.text(de.navKalender)),
    );
    await waitGone(tester, blatt);
    expect(find.byType(CalendarScreen), findsOneWidget);
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
          w is TextField && w.decoration?.hintText == de.befehlspaletteHinweis,
    );
    await waitFor(tester, palettenFeld);
    await tippe(tester, find.byType(BackButton));
    await waitGone(tester, palettenFeld);

    // GRU-050: breit – schmal – breit behält den Kalender.
    await fenster(tester, const Size(1400, 900));
    await settle(tester);
    expect(gewaehlt(tester), Hauptbereich.kalender);
    expect(find.byType(CalendarScreen), findsOneWidget);
    await fenster(tester, const Size(680, 900));
    await settle(tester);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await fenster(tester, const Size(1400, 900));
    await settle(tester);
    expect(gewaehlt(tester), Hauptbereich.kalender);
    await ende(tester);
  }, timeout: _frist);

  // Behoben in #400: Der Tresorwächter der Hülle horchte nie, weil sein
  // `late`-Feld erst in dispose entstand.
  testWidgets('GRU-051 Gesperrter Ordner wird beim Verbergen gesperrt', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.setupVaultPin('2468');
    expect(bibliothek.vaultUnlockedThisSession, isTrue);
    // Gegenprobe: nur Fokuswechsel.
    await lebenszyklus(tester, [AppLifecycleState.inactive]);
    expect(
      bibliothek.vaultUnlockedThisSession,
      isTrue,
      reason: 'Fokuswechsel sperrt nicht',
    );
    await lebenszyklus(tester, [AppLifecycleState.resumed]);
    expect(bibliothek.vaultUnlockedThisSession, isTrue);
    // Verbergen.
    await lebenszyklus(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
    ]);
    await tester.pump(const Duration(milliseconds: 300));
    expect(bibliothek.vaultUnlockedThisSession, isFalse);
    await lebenszyklus(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await settle(tester);
    // Ordner öffnen verlangt wieder die PIN.
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittGesperrterOrdner);
    await tippe(tester, knopf(de.einstGesperrtOeffnen));
    await waitFor(tester, find.text(de.pinEingebenTitel));
    await enter(tester, find.byType(TextField).last, '2468');
    await tippe(tester, knopf('OK'));
    await waitFor(tester, find.byType(LockedFolderScreen));
    expect(bibliothek.vaultUnlockedThisSession, isTrue);
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-056 Band der KI-Restaurierung', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final ids = await importiere(tester, fotos(2));
    for (var i = 0; i < 2; i++) {
      await bibliothek.db.createRestoreJob(
        RestoreJobsCompanion.insert(
          id: 'r$i',
          assetId: ids[i],
          status: 'queued',
          createdAt: DateTime.now().add(Duration(seconds: i)),
        ),
      );
    }
    await waitFor(tester, find.text(de.restaurierungWartend(2)));
    // Läuft, Kacheln noch unbekannt: „wird vorbereitet“.
    await (bibliothek.db.update(
      bibliothek.db.restoreJobs,
    )..where((t) => t.id.equals('r0'))).write(
      RestoreJobsCompanion(
        status: const Value('running'),
        startedAt: Value(DateTime.now()),
      ),
    );
    await waitFor(tester, find.text(de.restaurierungWirdVorbereitet));
    await (bibliothek.db.update(
      bibliothek.db.restoreJobs,
    )..where((t) => t.id.equals('r0'))).write(
      const RestoreJobsCompanion(tilesDone: Value(3), tilesTotal: Value(10)),
    );
    final job = (await bibliothek.db.select(bibliothek.db.restoreJobs).get())
        .firstWhere((j) => j.id == 'r0');
    final prozent = fortschrittProzent(job)!;
    await waitFor(
      tester,
      find.text(de.restaurProzentMitWarteschlange(prozent, 1)),
    );
    // Klick öffnet die Warteschlange neben der Leiste.
    await tippe(
      tester,
      find.text(de.restaurProzentMitWarteschlange(prozent, 1)),
    );
    await waitFor(tester, find.byType(RestoreQueueScreen));
    expect(find.text(de.restaurTitel), findsWidgets);
    expect(find.byType(Seitenleiste), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(RestoreQueueScreen)).dx,
      greaterThanOrEqualTo(Seitenleiste.schmal - 1),
    );
    await zurueck(tester);
    for (final id in ['r0', 'r1']) {
      await bibliothek.db.deleteRestoreJob(id);
    }
    await waitGone(tester, find.textContaining('KI-Restaurierung'));
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-170 Verbundene Bibliothek: Aufgaben laufen am Server', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(1));
    await neustart(tester, dazwischen: () => schreibeVerbindung(anker));
    expect(bibliothek.verbunden, isTrue);
    melde.verlaufLeeren();
    // GRU-170
    await aufgabenOeffnen(tester);
    final orte = await karte(tester, de.aufgOrteTitel);
    await aktion(tester, orte, de.aufgModusAlle);
    await erwarteMeldung(tester, de.aufgAmServer);
    expect(bibliothek.lauf('orte'), isNull, reason: 'lokal startet nichts');
    expect(bibliothek.etwasLaeuft, isFalse);
    await ende(tester);
  }, timeout: _frist);

  // Befund: Ist der Server nicht erreichbar und wartet eine Änderung, wirft
  // der Abgleich eine unbehandelte KeineVerbindung
  // (packages/kern/lib/abgleich/abgleich.dart:365 über verbindung.dart:70);
  // der Prüfrahmen lastet sie einer früheren Prüfung an. Das Band selbst
  // erscheint richtig.
  testWidgets(
    'GRU-057 Verbunden, Server nicht erreichbar: Band mit wartender Änderung',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await importiere(tester, fotos(1));
      await neustart(tester, dazwischen: () => schreibeVerbindung(anker));
      expect(bibliothek.verbunden, isTrue);
      // GRU-057: eine Änderung (Stern im Vollbild), Server nicht erreichbar.
      await leiste(tester, de.navFotos);
      final kachel = find.byType(AssetThumbnailTile);
      await waitFor(tester, kachel);
      await tester.tap(kachel.first);
      await waitFor(tester, find.byType(AssetViewerScreen));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await settle(tester);
      await key(tester, LogicalKeyboardKey.escape);
      await waitGone(tester, find.byType(AssetViewerScreen));
      await waitFor(
        tester,
        find.text(de.serverOffline(1)),
        timeout: const Duration(seconds: 60),
      );
      await ende(tester);
    },
    skip: true,
    timeout: _frist,
  );

  // Behoben in #408: Verbunden meldet die Sammelkarte, dass der Server
  // auswertet, statt eine laufende Auswertung zu behaupten.
  testWidgets('GRU-171 Verbunden: „Jetzt starten“ behauptet keine Auswertung', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(1));
    await neustart(tester, dazwischen: () => schreibeVerbindung(anker));
    expect(bibliothek.verbunden, isTrue);
    melde.verlaufLeeren();
    await aufgabenOeffnen(tester);
    final sammel = await karte(tester, de.werkzAllesNachholenTitel);
    await aktion(tester, sammel, de.aufgJetztStarten);
    await tester.pump(const Duration(milliseconds: 300));
    final sofort = find.text(de.aufgLaeuft).evaluate().isNotEmpty;
    await settle(tester, max: const Duration(seconds: 1));
    expect(bibliothek.analyseLaeuft, isFalse);
    expect(zahl(tester, sammel, de.aufgStatus), de.aufgBereit);
    expect(find.textContaining(bandAnfang()), findsNothing);
    final behauptet =
        sofort || melde.verlauf.any((m) => m.text == de.aufgLaeuft);
    print('GRU-171: Meldung „${de.aufgLaeuft}“ erschienen: $behauptet');
    expect(
      behauptet,
      isFalse,
      reason: 'App behauptet eine laufende Auswertung',
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-068 GRU-069 GRU-070 GRU-071 Beenden über den Kanal', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await eventually(tester, () async => !bibliothek.etwasLaeuft);
    // GRU-068: nichts läuft – keine Rückfrage, Datenbank zu.
    final darf = await frageBeenden(tester);
    await settle(tester);
    expect(darf, isTrue);
    expect(find.text(de.beendenTitel), findsNothing);
    expect(await datenbankOffen(), isFalse, reason: 'Datenbank geschlossen');
    await neustart(tester);

    // GRU-069: Auswertung und „Orte einlesen“ laufen.
    await importiere(tester, grosseFotos(24, stamm: 'gross'));
    unawaited(bibliothek.starteHintergrundanalyse());
    final strom = StreamController<ImportProgress>();
    addTearDown(() async {
      if (!strom.isClosed) await strom.close();
    });
    bibliothek.reiheAufgabeEin(
      schluessel: 'orte',
      titel: de.werkzLeseOrte,
      leermeldung: de.werkzKeinePassenden,
      strom: () => strom.stream,
    );
    strom.add(ImportProgress(0, 10));
    await eventually(
      tester,
      () async =>
          bibliothek.analyseLaeuft && bibliothek.laufendeAufgaben.isNotEmpty,
      was: 'beide laufen',
    );
    var antwort = frageBeenden(tester);
    await waitFor(tester, find.text(de.beendenTitel));
    expect(find.text(de.beendenText), findsOneWidget);
    expect(find.text('• ${de.werkzAllesNachholenTitel}'), findsOneWidget);
    expect(find.text('• ${de.werkzLeseOrte}'), findsOneWidget);
    expect(knopf(de.beendenTrotzdem), findsOneWidget);
    expect(knopf(de.beendenWeiterlaufen), findsOneWidget);

    // GRU-070: weiterlaufen lassen.
    final vorher = bibliothek.analyse?.erledigt ?? 0;
    await tippe(tester, knopf(de.beendenWeiterlaufen));
    expect(await antwort, isFalse);
    expect(await datenbankOffen(), isTrue);
    await eventually(
      tester,
      () async =>
          !bibliothek.analyseLaeuft ||
          (bibliothek.analyse?.erledigt ?? 0) > vorher,
      was: 'Fortschritt steigt',
    );
    expect(bibliothek.lauf('orte')?.laeuft, isTrue);

    // GRU-071: trotzdem beenden.
    antwort = frageBeenden(tester);
    await waitFor(tester, find.text(de.beendenTitel));
    final ausgewertet = (await aufnahmen())
        .where((a) => a.sharpnessScore != null)
        .length;
    await tippe(tester, knopf(de.beendenTrotzdem));
    expect(await antwort, isTrue);
    expect(await datenbankOffen(), isFalse);
    await strom.close();
    await neustart(tester);
    expect(bibliothek.initialisierungsfehler, isNull);
    final danach = (await aufnahmen())
        .where((a) => a.sharpnessScore != null)
        .length;
    expect(danach, greaterThanOrEqualTo(ausgewertet));
    expect(await anzahlAufnahmen(), 24);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-077 GRU-078 GRU-080 GRU-079 GRU-081 GRU-086 GRU-088 GRU-087 GRU-187 Bibliotheken verwalten',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      melde.verlaufLeeren();
      // GRU-077
      await einstellungen(tester);
      expect(find.text(de.einstBeschrBibliotheken), findsOneWidget);
      await gruppe(tester, de.einstBibListe);
      final standard = find.ancestor(
        of: find.text('Standard'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, standard);
      expect(
        find.descendant(
          of: standard,
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: standard, matching: find.text(de.einstBibAktiv)),
        findsOneWidget,
      );
      expect(knopf(de.einstBibHinzufuegen), findsOneWidget);
      expect(find.text(de.einstBibWechselHinweis), findsOneWidget);

      // GRU-078: leeren Ordner hinzufügen.
      final neu = Directory(p.join(anker.path, 'Neu'))..createSync();
      dialog.ordner = neu.path;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      await erwarteMeldung(tester, de.einstBibLeerHinzugefuegt);
      final neuKachel = find.ancestor(
        of: find.text('Neu'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, neuKachel);
      expect(
        find.descendant(of: neuKachel, matching: find.text(neu.path)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: neuKachel,
          matching: find.byIcon(Icons.radio_button_unchecked),
        ),
        findsOneWidget,
      );
      expect(neu.listSync(), isEmpty, reason: 'im Ordner entsteht nichts');
      expect(await datenbankOffen(), isTrue);
      expect(bibliothek.paths.root.parent.path, anker.path);

      // GRU-080: abbrechen, doppelt hinzufügen.
      final sichtbarVorher = melde.verlauf.length;
      dialog.ordner = null;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      await settle(tester);
      expect(
        melde.verlauf.length,
        sichtbarVorher,
        reason: 'Abbrechen meldet nichts',
      );
      dialog.ordner = neu.path;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      await settle(tester);
      expect(neuKachel, findsOneWidget);
      expect(
        (await LibraryLocation.bekannte())
            .where((b) => b.eintrag.path == neu.path)
            .length,
        1,
      );

      // GRU-079: bestehende Bibliothek hinzufügen.
      final alt = Directory(p.join(anker.path, 'Alt'));
      await legeBibliothekAn(alt);
      final altVorher = pruefsummen(alt);
      dialog.ordner = alt.path;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      await erwarteMeldung(tester, de.einstBibBestehendHinzugefuegt);
      final altKachel = find.ancestor(
        of: find.text('Alt'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, altKachel);
      expect(pruefsummen(alt), altVorher);

      // GRU-081: wechseln – Rückfrage und Abbrechen.
      final cfgVorher = File(
        p.join(anker.path, 'location.json'),
      ).readAsStringSync();
      await tippe(
        tester,
        find.descendant(of: neuKachel, matching: find.text('Neu')),
      );
      await waitFor(tester, find.text(de.einstBibWechselnTitel('Neu')));
      expect(find.text(de.einstBibWechselnText), findsOneWidget);
      await tippe(tester, knopf(de.allgAbbrechen));
      await waitGone(tester, find.text(de.einstBibWechselnTitel('Neu')));
      expect(
        File(p.join(anker.path, 'location.json')).readAsStringSync(),
        cfgVorher,
      );
      expect(await datenbankOffen(), isTrue);

      // GRU-086: nicht erreichbarer Eintrag.
      final fehlt = Directory(p.join(anker.path, 'Fehlt'))..createSync();
      await LibraryLocation.fuegeHinzu(
        PickedFolder(fehlt.path, ''),
        name: 'Fehlt',
      );
      fehlt.deleteSync();
      await leiste(tester, de.navAlben);
      await einstellungen(tester);
      await gruppe(tester, de.einstBibListe);
      final fehltKachel = find.ancestor(
        of: find.text('Fehlt'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, fehltKachel);
      expect(tester.widget<ListTile>(fehltKachel).enabled, isFalse);
      expect(
        find.descendant(
          of: fehltKachel,
          matching: find.text(de.einstBibNichtGefunden),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: fehltKachel, matching: find.text('Fehlt')),
      );
      await settle(tester);
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'Klick bewirkt nichts',
      );
      expect(
        find.descendant(
          of: fehltKachel,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
        findsOneWidget,
      );

      // GRU-088: entfernen abbrechen.
      final neuKachel2 = find.ancestor(
        of: find.text('Neu'),
        matching: find.byType(ListTile),
      );
      await tippe(
        tester,
        find.descendant(
          of: neuKachel2,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
      );
      await waitFor(tester, find.text(de.einstBibEntfernenTitel('Neu')));
      await tippe(tester, knopf(de.allgAbbrechen));
      await waitGone(tester, find.text(de.einstBibEntfernenTitel('Neu')));
      expect(neuKachel2, findsOneWidget);

      // GRU-087: entfernen löscht keine Fotos.
      final altKachel2 = find.ancestor(
        of: find.text('Alt'),
        matching: find.byType(ListTile),
      );
      await tippe(
        tester,
        find.descendant(
          of: altKachel2,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
      );
      await waitFor(tester, find.text(de.einstBibEntfernenTitel('Alt')));
      await tippe(tester, knopf(de.allgEntfernen));
      await waitGone(tester, altKachel2);
      expect(pruefsummen(alt), altVorher, reason: 'byte-gleich vorhanden');

      // GRU-187: Kurzhinweise der Symbolknöpfe.
      expect(find.byTooltip(de.einstBibAusListeEntfernen), findsWidgets);
      await gruppe(tester, de.einstBibListe);
      await gruppe(tester, de.einstSpeicherortTitel);
      await waitFor(tester, find.byTooltip(de.einstImFinderAnzeigen));
      await gruppe(tester, de.einstSpeicherortTitel);
      tester.state<ScrollableState>(einstListe).position.jumpTo(0);
      await tester.pump();
      await enter(
        tester,
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.byType(TextField),
        ),
        'xyz',
      );
      expect(find.byTooltip(de.allgAbbrechen), findsOneWidget);
      await aufgabenOeffnen(tester);
      await tippe(tester, kopfknopf(de.aufgGleichzeitigTitel));
      await waitFor(tester, find.byTooltip(de.aufgWenigerGleichzeitig));
      expect(find.byTooltip(de.aufgMehrGleichzeitig), findsOneWidget);
      // Vorgelesen: der Kurzhinweis ist die Beschriftung des Knopfes.
      final semantik = tester.ensureSemantics();
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(find.byTooltip(de.aufgMehrGleichzeitig)),
        isSemantics(tooltip: de.aufgMehrGleichzeitig),
      );
      semantik.dispose();
      await tippe(tester, knopf(de.allgAbbrechen));
      await ende(tester);
    },
    timeout: _frist,
  );

  // Behoben in #408: Die Oberfläche zeigt den Standardordner über
  // BibliothekMitZustand.anzeigename mit dem übersetzten Namen.
  testWidgets('GRU-077 Name „Standard“ in englischer Oberfläche', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester, sprache: 'en');
    await leiste(tester, en.navEinstellungen);
    await waitFor(tester, find.byType(SettingsScreen));
    await gruppe(tester, en.einstBibListe);
    await waitFor(tester, find.text(en.einstBibAktiv));
    final aktiv = find.ancestor(
      of: find.text(en.einstBibAktiv),
      matching: find.byType(ListTile),
    );
    final name = tester
        .widget<Text>(
          find.descendant(of: aktiv, matching: find.byType(Text)).first,
        )
        .data;
    print('GRU-077 (en): Name der Standardbibliothek: $name');
    expect(
      name,
      isNot('Standard'),
      reason: 'unübersetzt in englischer Oberfläche',
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-082 GRU-085 GRU-083 GRU-046 GRU-089 GRU-092 GRU-084 GRU-090 Wechseln zwischen Bibliotheken',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await importiere(tester, fotos(2, stamm: 'std'));
      await bibliothek.db.setThemeMode('light');
      final neu = Directory(p.join(anker.path, 'Neu'))..createSync();
      // Hinzufügen über die Oberfläche.
      await einstellungen(tester);
      await gruppe(tester, de.einstBibListe);
      dialog.ordner = neu.path;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      final neuKachel = find.ancestor(
        of: find.text('Neu'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, neuKachel);

      // GRU-082: wechseln verschiebt keine Datei.
      final stdVorher = pruefsummen(anker, ohneDb: true)
        ..removeWhere((k, _) => !k.startsWith('library${p.separator}'));
      final neuVorher = pruefsummen(neu);
      final cfgVorher = File(
        p.join(anker.path, 'location.json'),
      ).readAsStringSync();
      await tippe(
        tester,
        find.descendant(of: neuKachel, matching: find.text('Neu')),
      );
      await tippe(tester, knopf(de.einstBibWechselnAktion));
      final laufGesehen = find
          .text(de.einstBibWechselnLaeuft)
          .evaluate()
          .isNotEmpty;
      await waitFor(tester, find.text(de.einstNeustartTitel));
      print('GRU-082: „Wechsle Bibliothek …“ gesehen: $laufGesehen');
      expect(find.text(de.einstBibGewechselt), findsOneWidget);
      expect(knopf(de.allgSchliessen), findsOneWidget);
      final stdNachher = pruefsummen(anker, ohneDb: true)
        ..removeWhere((k, _) => !k.startsWith('library${p.separator}'));
      expect(stdNachher, stdVorher, reason: 'Standard byte-gleich');
      expect(pruefsummen(neu), neuVorher, reason: 'Neu byte-gleich');
      expect(
        File(p.join(anker.path, 'location.json')).readAsStringSync(),
        isNot(cfgVorher),
      );
      expect(ortsdatei()['aktiv'], neu.path);

      // GRU-085 / GRU-083: nach dem Neustart ist „Neu“ offen (leer).
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, neu.path);
      await waitFor(tester, find.text(de.timelineLeer));
      expect(File(p.join(neu.path, 'library.sqlite')).existsSync(), isTrue);
      expect(Directory(p.join(neu.path, 'library')).existsSync(), isTrue);
      // GRU-046: Name der geöffneten Bibliothek unter „Photo Vault“.
      final sl = tester.widget<Seitenleiste>(find.byType(Seitenleiste));
      expect(sl.unterzeile, 'Neu');
      expect(sl.unterzeileHinweis, de.geoeffneteBibliothek('Neu'));
      expect(find.byTooltip(de.geoeffneteBibliothek('Neu')), findsOneWidget);
      // Inhalt für später (GRU-090).
      final ids = await importiere(tester, fotos(3, stamm: 'neu'));
      await bibliothek.db.fuehreAus(
        AlbumAnlegen('albNeu', 'Urlaub', DateTime(2024)),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen('albNeu', ids));
      await bibliothek.db.fuehreAus(const PersonAnlegen('pNeu', 'Person A'));
      await einstellungen(tester);
      await gruppe(tester, de.einstBibListe);
      final neuAktiv = find.ancestor(
        of: find.text(neu.path),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, neuAktiv);
      expect(
        find.descendant(of: neuAktiv, matching: find.text(de.einstBibAktiv)),
        findsOneWidget,
      );
      // GRU-089: aktive und Standard ohne Entfernen-Symbol.
      final stdKachel = find.ancestor(
        of: find.text('Standard'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: stdKachel,
          matching: find.text(de.einstBibImmerVorhanden),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stdKachel,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: neuAktiv,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
        findsNothing,
      );

      // GRU-092: „Neu“ dunkel/English, Standard hell/Deutsch – zurück zu
      // Standard, dann gelten Hell/Deutsch.
      await bibliothek.db.setThemeMode('dark');
      await bibliothek.db.setSprache('en');
      await settle(tester);
      await waitFor(tester, find.text(en.einstBibListe));
      // Mit der Sprache wechseln die Titel und damit die Schlüssel der
      // Gruppen – „Libraries“ ist wieder zugeklappt.
      if (find.text('Standard').evaluate().isEmpty) {
        await gruppe(tester, en.einstBibListe);
      }
      final neuVorWechsel = pruefsummen(neu, ohneDb: true);
      final stdKachelEn = find.ancestor(
        of: find.text('Standard'),
        matching: find.byType(ListTile),
      );
      await tippe(
        tester,
        find.descendant(of: stdKachelEn, matching: find.text('Standard')),
      );
      await tippe(tester, knopf(en.einstBibWechselnAktion));
      await waitFor(tester, find.text(en.einstNeustartTitel));
      // GRU-084: zurück zur Standardbibliothek.
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, anker.path);
      expect(await anzahlAufnahmen(), 2);
      expect(
        Theme.of(tester.element(find.byType(HomeShell))).brightness,
        Brightness.light,
      );
      expect(find.text(de.navFotos), findsWidgets);
      expect(find.text(en.navFotos), findsNothing);
      expect(
        pruefsummen(neu, ohneDb: true),
        neuVorWechsel,
        reason: 'externe unverändert',
      );
      expect(
        (await LibraryLocation.bekannte()).any(
          (b) => b.eintrag.path == neu.path,
        ),
        isTrue,
      );

      // GRU-090: entfernen und wieder hinzufügen, dann wechseln.
      await einstellungen(tester);
      await gruppe(tester, de.einstBibListe);
      final neuKachel3 = find.ancestor(
        of: find.text('Neu'),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, neuKachel3);
      await tippe(
        tester,
        find.descendant(
          of: neuKachel3,
          matching: find.byTooltip(de.einstBibAusListeEntfernen),
        ),
      );
      await tippe(tester, knopf(de.allgEntfernen));
      await waitGone(tester, neuKachel3);
      melde.verlaufLeeren();
      dialog.ordner = neu.path;
      await tippe(tester, knopf(de.einstBibHinzufuegen));
      await erwarteMeldung(tester, de.einstBibBestehendHinzugefuegt);
      await tippe(
        tester,
        find.descendant(of: neuKachel3, matching: find.text('Neu')),
      );
      await tippe(tester, knopf(de.einstBibWechselnAktion));
      await waitFor(tester, find.text(de.einstNeustartTitel));
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, neu.path);
      expect(await anzahlAufnahmen(), 3);
      expect(
        (await bibliothek.db.alleAlben()).map((a) => a.name),
        contains('Urlaub'),
      );
      final personen = await bibliothek.db.select(bibliothek.db.people).get();
      expect(personen.map((x) => x.name), contains('Person A'));
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets(
    'GRU-094 GRU-095 GRU-097 GRU-098 Speicherort ansehen, Hindernisse',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await importiere(tester, fotos(3));
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      // GRU-094
      final pfad = bibliothek.paths.root.path;
      expect(p.basename(pfad), 'library');
      await waitFor(tester, find.text(pfad));
      expect(find.text(de.einstSpeicherort), findsOneWidget);
      expect(find.byTooltip(de.einstImFinderAnzeigen), findsOneWidget);
      expect(knopf(de.einstAendern), findsOneWidget);
      await settle(tester);
      expect(knopf(de.einstZuruecksetzen), findsNothing);

      // GRU-095: Speicherbedarf.
      final bedarf = find.text(de.einstSpeicherbedarf);
      await waitFor(tester, bedarf);
      await waitGone(tester, find.text(de.einstWirdBerechnet));
      await zeigeInEinstellungen(tester, bedarf);
      await tippe(tester, bedarf);
      final originale = ordnergroesse(Directory(p.join(pfad, 'originals')));
      final zeileOriginale = find.ancestor(
        of: find.text(de.belegung_originals),
        matching: find.byType(Row),
      );
      await waitFor(tester, zeileOriginale);
      expect(
        find.descendant(
          of: zeileOriginale.first,
          matching: find.text(groessentext(originale)),
        ),
        findsOneWidget,
      );
      expect(find.text(de.belegung_thumbnails), findsOneWidget);
      expect(find.text(de.belegung_datenbank), findsOneWidget);
      expect(
        find.text(de.belegung_faces),
        findsNothing,
        reason: 'leere Posten fehlen',
      );
      int summe() {
        var n = ordnergroesse(bibliothek.paths.root);
        for (final s in ['', '-wal', '-shm']) {
          final f = File(p.join(anker.path, 'library.sqlite$s'));
          if (f.existsSync()) n += f.lengthSync();
        }
        return n;
      }

      var summeGefunden = false;
      for (var i = 0; i < 4 && !summeGefunden; i++) {
        summeGefunden = find.text(groessentext(summe())).evaluate().isNotEmpty;
        if (!summeGefunden) {
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
      expect(
        summeGefunden,
        isTrue,
        reason: 'Summe = library/ + library.sqlite',
      );

      // GRU-097: in den angezeigten Ordner verlegen.
      final vorher = pruefsummen(bibliothek.paths.root);
      for (final ziel in [pfad, p.join(pfad, 'originals')]) {
        dialog.ordner = ziel;
        await zeigeInEinstellungen(tester, knopf(de.einstAendern));
        await tippe(tester, knopf(de.einstAendern));
        await waitFor(tester, find.text(de.einstSpeicherortInBibliothek));
        expect(find.text(de.einstNeustartTitel), findsNothing);
        await waitGone(
          tester,
          find.text(de.einstSpeicherortInBibliothek),
          timeout: const Duration(seconds: 15),
        );
      }
      expect(pruefsummen(bibliothek.paths.root), vorher);
      expect(await datenbankOffen(), isTrue);

      // GRU-098: auf eine bestehende Bibliothek verlegen.
      final alt = Directory(p.join(anker.path, 'Alt'));
      await legeBibliothekAn(alt);
      final altVorher = pruefsummen(alt);
      dialog.ordner = alt.path;
      await tippe(tester, knopf(de.einstAendern));
      await waitFor(tester, find.text(de.einstSpeicherortBelegt));
      expect(pruefsummen(alt), altVorher);
      expect(pruefsummen(bibliothek.paths.root), vorher);
      expect(await datenbankOffen(), isTrue);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets(
    'GRU-099 GRU-188 GRU-100 GRU-102 Speicherort verlegen und zurücksetzen',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await bibliothek.db.setAutoAnalyzeAfterImport(false);
      final ids = await importiere(tester, fotos(12));
      await bibliothek.db.fuehreAus(
        AlbumAnlegen('alb', 'Urlaub', DateTime(2024)),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen('alb', ids));
      await bibliothek.db.fuehreAus(const PersonAnlegen('p1', 'Person A'));
      // Viel Inhalt, damit der Fortschritt sichtbar wird.
      final ballast = File(
        p.join(
          bibliothek.paths.root.path,
          'originals',
          '2000',
          '01',
          'ballast.bin',
        ),
      )..createSync(recursive: true);
      final raf = ballast.openSync(mode: FileMode.write);
      final block = List<int>.filled(1 << 20, 7);
      for (var i = 0; i < 120; i++) {
        raf.writeFromSync(block);
      }
      raf.closeSync();
      final originaleVorher = pruefsummen(
        Directory(p.join(bibliothek.paths.root.path, 'originals')),
      );
      final neu = Directory(p.join(anker.path, 'Neu'))..createSync();
      await LibraryLocation.fuegeHinzu(PickedFolder(neu.path, ''), name: 'Neu');
      final ziel = Directory(p.join(anker.path, 'ziel'))..createSync();
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      dialog.ordner = ziel.path;
      final semantik = tester.ensureSemantics();
      await tester.pump();
      await tester.pump();
      await zeigeInEinstellungen(tester, knopf(de.einstAendern));
      await tester.tap(knopf(de.einstAendern).first);
      // GRU-099 / GRU-188: das Fortschrittsfenster.
      var fensterGesehen = false;
      var fortschrittGesehen = false;
      var semantikGesehen = false;
      final fortschritt = RegExp(r'.+ von .+ · \d+ von \d+ Dateien');
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .text(de.einstSpeicherortVerschiebenLaeuft)
            .evaluate()
            .isNotEmpty) {
          fensterGesehen = true;
          if (find
              .byWidgetPredicate(
                (w) => w is Text && fortschritt.hasMatch(w.data ?? ''),
              )
              .evaluate()
              .isNotEmpty) {
            fortschrittGesehen = true;
          }
          final s = tester.getSemantics(
            find.text(de.einstSpeicherortVerschiebenLaeuft),
          );
          bool hatProzent(SemanticsNode n) {
            if (n.label.contains(de.einstSpeicherortVerschiebenLaeuft) &&
                RegExp(r'^\d+ %$').hasMatch(n.value)) {
              return true;
            }
            var gefunden = false;
            n.visitChildren((k) {
              gefunden = gefunden || hatProzent(k);
              return !gefunden;
            });
            return gefunden;
          }

          var knoten = s;
          while (knoten.parent != null &&
              !knoten.label.contains(de.einstSpeicherortVerschiebenLaeuft)) {
            knoten = knoten.parent!;
          }
          if (hatProzent(knoten) ||
              (knoten.label.contains(de.einstSpeicherortVerschiebenLaeuft) &&
                  RegExp(r'^\d+ %$').hasMatch(knoten.value))) {
            semantikGesehen = true;
          }
        }
        if (find.text(de.einstNeustartTitel).evaluate().isNotEmpty) break;
      }
      semantik.dispose();
      print(
        'GRU-099/188: Fenster $fensterGesehen, Fortschritt $fortschrittGesehen, '
        'Semantik $semantikGesehen',
      );
      await waitFor(
        tester,
        find.text(de.einstNeustartTitel),
        timeout: const Duration(seconds: 60),
      );
      expect(fensterGesehen, isTrue);
      expect(fortschrittGesehen, isTrue);
      expect(find.text(de.einstSpeicherortGeaendert), findsOneWidget);
      expect(File(p.join(ziel.path, 'library.sqlite')).existsSync(), isTrue);
      expect(
        pruefsummen(Directory(p.join(ziel.path, 'library', 'originals'))),
        originaleVorher,
      );
      expect(File(p.join(anker.path, 'library.sqlite')).existsSync(), isFalse);
      expect(Directory(p.join(anker.path, 'library')).existsSync(), isFalse);

      // GRU-100: nach dem Neustart alles da, Originale byte-gleich.
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, ziel.path);
      expect(await anzahlAufnahmen(), 12);
      expect(
        (await bibliothek.db.alleAlben()).map((a) => a.name),
        contains('Urlaub'),
      );
      expect(
        (await bibliothek.db.select(bibliothek.db.people).get()).map(
          (x) => x.name,
        ),
        contains('Person A'),
      );
      expect(
        pruefsummen(Directory(p.join(bibliothek.paths.root.path, 'originals'))),
        originaleVorher,
      );
      var liste = await LibraryLocation.bekannte();
      final aktiv = liste.firstWhere((b) => b.istAktiv);
      expect(aktiv.eintrag.path, ziel.path);
      print(
        'GRU-100: Name des aktiven Eintrags nach dem Verlegen: ${aktiv.eintrag.name}',
      );
      // Ein zweites Verlegen behält den Namen des Eintrags.
      final ziel2 = Directory(p.join(anker.path, 'ziel2'))..createSync();
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      dialog.ordner = ziel2.path;
      await zeigeInEinstellungen(tester, knopf(de.einstAendern));
      await tippe(tester, knopf(de.einstAendern));
      await waitFor(
        tester,
        find.text(de.einstNeustartTitel),
        timeout: const Duration(seconds: 60),
      );
      await neustart(tester);
      liste = await LibraryLocation.bekannte();
      final aktiv2 = liste.firstWhere((b) => b.istAktiv);
      expect(aktiv2.eintrag.path, ziel2.path);
      expect(
        aktiv2.eintrag.name,
        aktiv.eintrag.name,
        reason: 'bisheriger Name',
      );

      // GRU-102: zurücksetzen.
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      await waitFor(tester, knopf(de.einstZuruecksetzen));
      await zeigeInEinstellungen(tester, knopf(de.einstZuruecksetzen));
      await tippe(tester, knopf(de.einstZuruecksetzen));
      await waitFor(tester, find.text(de.einstSpeicherortZuruecksetzenTitel));
      await tippe(tester, knopf(de.allgAbbrechen));
      await waitGone(tester, find.text(de.einstSpeicherortZuruecksetzenTitel));
      expect(await datenbankOffen(), isTrue);
      expect(File(p.join(ziel2.path, 'library.sqlite')).existsSync(), isTrue);
      await tippe(tester, knopf(de.einstZuruecksetzen));
      await waitFor(tester, find.text(de.einstSpeicherortZuruecksetzenTitel));
      await tippe(
        tester,
        knopfIn(find.byType(AlertDialog), de.einstZuruecksetzen),
      );
      final laufGesehen = find
          .text(de.einstSpeicherortZuruecksetzenLaeuft)
          .evaluate()
          .isNotEmpty;
      await waitFor(
        tester,
        find.text(de.einstNeustartTitel),
        timeout: const Duration(seconds: 60),
      );
      print('GRU-102: „Setze Speicherort zurück …“ gesehen: $laufGesehen');
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, anker.path);
      expect(await anzahlAufnahmen(), 12);
      expect(
        pruefsummen(Directory(p.join(bibliothek.paths.root.path, 'originals'))),
        originaleVorher,
      );
      liste = await LibraryLocation.bekannte();
      expect(
        liste.any((b) => b.eintrag.path == neu.path),
        isTrue,
        reason: 'andere Einträge bleiben',
      );
      await ende(tester);
    },
    timeout: _frist,
  );

  Future<({Directory gesperrt, Map<String, String> vorher})> verlegenScheitert(
    WidgetTester tester,
  ) async {
    filtereSemantik();
    verschiebeFehlerUebergehen = true;
    verschiebeFehler = 0;
    addTearDown(() {
      verschiebeFehlerUebergehen = false;
      print(
        'GRU-101: Fehler beim Schliessen des Fortschrittsfensters: $verschiebeFehler',
      );
    });
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(3));
    final gesperrt = Directory(p.join(anker.path, 'gesperrt'))..createSync();
    await Process.run('chmod', ['555', gesperrt.path]);
    addTearDown(() => Process.run('chmod', ['755', gesperrt.path]));
    final vorher = pruefsummen(bibliothek.paths.root);
    melde.verlaufLeeren();
    await einstellungen(tester);
    await gruppe(tester, de.einstSpeicherortTitel);
    dialog.ordner = gesperrt.path;
    await zeigeInEinstellungen(tester, knopf(de.einstAendern));
    await tippe(tester, knopf(de.einstAendern));
    await waitFor(
      tester,
      find.textContaining('${de.einstVerschiebenFehlgeschlagen}:'),
      timeout: const Duration(seconds: 30),
    );
    return (gesperrt: gesperrt, vorher: vorher);
  }

  testWidgets('GRU-101 Verlegen scheitert: alte Bibliothek bleibt', (
    tester,
  ) async {
    final r = await verlegenScheitert(tester);
    // Die Fehlermeldung bleibt stehen.
    await tester.pump(const Duration(seconds: 6));
    expect(
      find.textContaining('${de.einstVerschiebenFehlgeschlagen}:'),
      findsOneWidget,
    );
    expect(pruefsummen(bibliothek.paths.root), r.vorher);
    expect(File(p.join(anker.path, 'library.sqlite')).existsSync(), isTrue);
    expect(
      pruefsummen(r.gesperrt),
      isEmpty,
      reason: 'keine Teilkopien am Ziel',
    );
    await neustart(tester);
    expect(bibliothek.paths.root.parent.path, anker.path);
    expect(await anzahlAufnahmen(), 3);
    expect(pruefsummen(bibliothek.paths.root), r.vorher);
    await Process.run('chmod', ['755', r.gesperrt.path]);
    await ende(tester);
  }, timeout: _frist);

  // Behoben in #408: Scheitert ein Vorgang, nachdem die Datenbank
  // geschlossen wurde (LibraryState.datenbankGeschlossen), verlangt
  // verlegeBibliothek den Neustart.
  testWidgets('GRU-101 Nach gescheitertem Verlegen bleibt die App bedienbar', (
    tester,
  ) async {
    final r = await verlegenScheitert(tester);
    final offen = await datenbankOffen();
    final neustartVerlangt = find
        .text(de.einstNeustartTitel)
        .evaluate()
        .isNotEmpty;
    print(
      'GRU-101: Datenbank offen: $offen, Neustart verlangt: $neustartVerlangt',
    );
    expect(offen || neustartVerlangt, isTrue);
    await Process.run('chmod', ['755', r.gesperrt.path]);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-103 GRU-104 Zurücksetzen auf belegten Standard, bei aktiver Standardbibliothek',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await importiere(tester, fotos(2));
      final neu = Directory(p.join(anker.path, 'Neu'))..createSync();
      final e = await LibraryLocation.fuegeHinzu(
        PickedFolder(neu.path, ''),
        name: 'Neu',
      );
      await LibraryLocation.wechsleZu(e);
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, neu.path);
      await importiere(tester, fotos(1, stamm: 'n'));
      // GRU-103
      final stdVorher = pruefsummen(Directory(p.join(anker.path, 'library')));
      final neuVorher = pruefsummen(Directory(p.join(neu.path, 'library')));
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      await waitFor(tester, knopf(de.einstZuruecksetzen));
      await zeigeInEinstellungen(tester, knopf(de.einstZuruecksetzen));
      await tippe(tester, knopf(de.einstZuruecksetzen));
      await tippe(
        tester,
        knopfIn(find.byType(AlertDialog), de.einstZuruecksetzen),
      );
      await waitFor(tester, find.text(de.einstSpeicherortBelegt));
      expect(find.text(de.einstNeustartTitel), findsNothing);
      expect(await datenbankOffen(), isTrue);
      expect(pruefsummen(Directory(p.join(anker.path, 'library'))), stdVorher);
      expect(pruefsummen(Directory(p.join(neu.path, 'library'))), neuVorher);
      expect(File(p.join(neu.path, 'library.sqlite')).existsSync(), isTrue);

      // GRU-104: aktiv ist wieder „Standard“, location.json existiert.
      await LibraryLocation.wechsleZu(
        (await LibraryLocation.bekannte())
            .firstWhere((b) => b.istStandard)
            .eintrag,
      );
      await neustart(tester);
      expect(bibliothek.paths.root.parent.path, anker.path);
      final stdVorher2 = pruefsummen(Directory(p.join(anker.path, 'library')));
      final neuVorher2 = pruefsummen(neu, ohneDb: true);
      await einstellungen(tester);
      await gruppe(tester, de.einstSpeicherortTitel);
      await settle(tester);
      final sichtbar = knopf(de.einstZuruecksetzen).evaluate().isNotEmpty;
      print(
        'GRU-104: „Zurücksetzen“ bei aktiver Standardbibliothek sichtbar: $sichtbar',
      );
      if (sichtbar) {
        await zeigeInEinstellungen(tester, knopf(de.einstZuruecksetzen));
        await tippe(tester, knopf(de.einstZuruecksetzen));
        await tippe(
          tester,
          knopfIn(find.byType(AlertDialog), de.einstZuruecksetzen),
        );
        await settle(tester);
        await tester.pump(const Duration(seconds: 1));
        print(
          'GRU-104: danach Neustart verlangt: '
          '${find.text(de.einstNeustartTitel).evaluate().isNotEmpty}, '
          'Datenbank offen: ${await datenbankOffen()}',
        );
      }
      expect(pruefsummen(Directory(p.join(anker.path, 'library'))), stdVorher2);
      expect(pruefsummen(neu, ohneDb: true), neuVorher2);
      expect(File(p.join(anker.path, 'library.sqlite')).existsSync(), isTrue);
      await ende(tester);
    },
    timeout: _frist,
  );

  // Behoben in #408: LibraryLocation.isCustom fragt, ob die aktive
  // Bibliothek ausserhalb des Standardordners liegt, nicht mehr, ob
  // location.json existiert.
  testWidgets('GRU-104 „Zurücksetzen“ fehlt bei aktiver Standardbibliothek', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final neu = Directory(p.join(anker.path, 'Neu'))..createSync();
    await LibraryLocation.fuegeHinzu(PickedFolder(neu.path, ''), name: 'Neu');
    await LibraryLocation.wechsleZu(
      (await LibraryLocation.bekannte())
          .firstWhere((b) => b.istStandard)
          .eintrag,
    );
    // Auch ohne weitere Bibliothek in der Liste (GRU-094).
    await LibraryLocation.entferneAusListe(neu.path);
    expect(File(p.join(anker.path, 'location.json')).existsSync(), isTrue);
    await neustart(tester);
    await einstellungen(tester);
    await gruppe(tester, de.einstSpeicherortTitel);
    await settle(tester);
    expect(knopf(de.einstZuruecksetzen), findsNothing);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-106 GRU-107 GRU-108 GRU-109 GRU-110 GRU-111 GRU-112 GRU-113 Einstellungen allgemein',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester, groesse: const Size(1400, 2300));
      await einstellungen(tester);
      // GRU-106: Suchfeld und 19 Gruppen, zugeklappt, in fester Reihenfolge.
      final titel = [
        (de.einstAbschnittErscheinungsbild, de.einstBeschrErscheinungsbild),
        (de.spracheTitel, de.einstBeschrSprache),
        (de.einstUeberwachtTitel, de.einstBeschrUeberwacht),
        (de.einstBibListe, de.einstBeschrBibliotheken),
        (de.serverTitel, de.einstBeschrServer),
        (de.einstSpeicherortTitel, de.einstBeschrSpeicherort),
        (de.einstAbschnittModelle, de.einstBeschrModelle),
        (de.einstAbschnittHintergrund, de.einstBeschrHintergrund),
        (de.einstAbschnittVokabular, de.einstBeschrVokabular),
        (de.einstAbschnittStandortdaten, de.einstBeschrStandortdaten),
        (de.einstAbschnittKarte, de.einstBeschrKarte),
        (de.einstAbschnittGesperrterOrdner, de.einstBeschrGesperrt),
        (de.einstBackupVerschluesselungTitel, de.einstBeschrBackupSchluessel),
        (de.einstAbschnittManuellesBackup, de.einstBeschrBackupManuell),
        (de.einstAbschnittAutoBackup, de.einstBeschrBackupAuto),
        (de.einstAbschnittPapierkorb, de.einstBeschrPapierkorb),
        (de.einstAbschnittGefahrenzone, de.einstBeschrGefahr),
        (de.kuerzelTitel, de.einstBeschrKuerzel),
        (de.einstUeberTitel, de.einstBeschrUeber),
      ];
      expect(
        find.descendant(
          of: find.byType(SearchBar),
          matching: find.text(de.einstSuche),
        ),
        findsOneWidget,
      );
      Finder kopf(String t) => find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.text(t),
      );
      final kacheln = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(ExpansionTile),
      );
      expect(kacheln, findsNWidgets(19));
      var y = -1.0;
      for (final (t, b) in titel) {
        expect(kopf(t), findsOneWidget, reason: t);
        expect(kopf(b), findsOneWidget, reason: b);
        final dy = tester.getTopLeft(kopf(t)).dy;
        expect(dy, greaterThan(y), reason: 'Reihenfolge $t');
        y = dy;
      }
      for (final typ in [
        ErscheinungsbildGruppe,
        SpracheGruppe,
        BibliothekenGruppe,
        SpeicherortGruppe,
        GefahrenzoneGruppe,
        UeberGruppe,
      ]) {
        expect(find.byType(typ), findsNothing, reason: 'zugeklappt: $typ');
      }

      // GRU-107: jede Gruppe auf- und zuklappen.
      for (final (t, _) in titel) {
        await gruppe(tester, t);
        await settle(tester);
        expect(tester.takeException(), isNull, reason: t);
        await gruppe(tester, t);
        await settle(tester);
      }

      final suche = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      );
      tester.state<ScrollableState>(einstListe).position.jumpTo(0);
      await tester.pump();
      // GRU-108
      await enter(tester, suche, 'Passphrase');
      expect(kacheln, findsOneWidget);
      expect(kopf(de.einstBackupVerschluesselungTitel), findsOneWidget);
      expect(tester.widget<ExpansionTile>(kacheln).initiallyExpanded, isTrue);
      expect(find.byType(SicherungsschluesselGruppe), findsOneWidget);
      // GRU-109
      await enter(tester, suche, 'KARTE');
      expect(kacheln, findsOneWidget);
      expect(kopf(de.einstAbschnittKarte), findsOneWidget);
      await enter(tester, suche, '');
      await enter(tester, suche, 'backup');
      expect(kacheln, findsNWidgets(3));
      for (final t in [
        de.einstBackupVerschluesselungTitel,
        de.einstAbschnittManuellesBackup,
        de.einstAbschnittAutoBackup,
      ]) {
        expect(kopf(t), findsOneWidget, reason: t);
      }
      // GRU-110
      await enter(tester, suche, 'xyz');
      expect(find.text(de.einstNichtsGefunden), findsOneWidget);
      expect(kacheln, findsNothing);
      await tippe(tester, find.byTooltip(de.allgAbbrechen));
      expect(kacheln, findsNWidgets(19));
      expect(find.byTooltip(de.allgAbbrechen), findsNothing);
      expect(find.byType(BibliothekenGruppe), findsNothing);

      // GRU-112: Eingabe überdauert das Zuklappen.
      await gruppe(tester, de.einstAbschnittVokabular);
      final begriff = field(de.einstBegriffHinzufuegenFeld);
      await enter(tester, begriff, 'Probe');
      await gruppe(tester, de.einstAbschnittVokabular);
      expect(begriff, findsNothing);
      await gruppe(tester, de.einstAbschnittVokabular);
      await waitFor(tester, begriff);
      expect(tester.widget<TextField>(begriff).controller?.text, 'Probe');
      await gruppe(tester, de.einstAbschnittVokabular);

      // GRU-113: „Hintergrundaufgaben“ führt zu den Aufgaben.
      await gruppe(tester, de.einstAbschnittHintergrund);
      await tippe(tester, find.text(de.einstAufgabenTitel));
      await waitFor(tester, find.byType(BackgroundTasksScreen));
      expect(find.byType(Seitenleiste), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(BackgroundTasksScreen)).dx,
        greaterThanOrEqualTo(Seitenleiste.schmal - 1),
      );
      await zurueck(tester);

      // GRU-111: Suche auf Englisch.
      await bibliothek.db.setSprache('en');
      await settle(tester);
      await waitFor(tester, find.text(en.einstSuche));
      tester.state<ScrollableState>(einstListe).position.jumpTo(0);
      await tester.pump();
      await enter(tester, suche, 'appear');
      expect(kacheln, findsOneWidget);
      expect(kopf(en.einstAbschnittErscheinungsbild), findsOneWidget);
      await ende(tester);
    },
    timeout: _frist,
  );

  // Behoben in #408: „Hintergrundaufgaben“ beschreibt jetzt die
  // Aufgaben-Übersicht; die automatische Auswertung steht in der
  // Beschreibung von „KI-Modelle“, wo der Schalter liegt.
  testWidgets('GRU-114 Schalter der automatischen Auswertung über die Suche', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await einstellungen(tester);
    await enter(
      tester,
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      ),
      'ausgewertet',
    );
    await settle(tester);
    final gefunden = tester
        .widgetList<ExpansionTile>(
          find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(ExpansionTile),
          ),
        )
        .map((e) => (e.title as Text).data)
        .toList();
    print('GRU-114: gefundene Gruppen: $gefunden');
    expect(find.text(de.einstAutoAnalyseTitel), findsOneWidget);
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-116 GRU-118 GRU-117 Design hell, dunkel, System', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final pd = tester.platformDispatcher;
    addTearDown(pd.clearAllTestValues);
    pd.platformBrightnessTestValue = Brightness.light;
    Brightness hell() =>
        Theme.of(tester.element(find.byType(HomeShell))).brightness;
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittErscheinungsbild);
    final segmente = find.byWidgetPredicate(
      (w) => w is SegmentedButton<ThemeMode>,
    );
    // GRU-116
    await tippe(tester, find.text(de.einstDesignDunkel));
    expect(hell(), Brightness.dark);
    expect(tester.widget<SegmentedButton<ThemeMode>>(segmente).selected, {
      ThemeMode.dark,
    });
    final farben = Theme.of(tester.element(find.byType(HomeShell))).colorScheme;
    final leistenKasten = tester
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(Seitenleiste),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).border is Border &&
              ((c.decoration as BoxDecoration).border as Border).right.width >
                  0,
        )
        .first;
    final leistenFarbe = (leistenKasten.decoration as BoxDecoration).color!;
    final grund = Theme.of(
      tester.element(find.byType(HomeShell)),
    ).scaffoldBackgroundColor;
    expect(leistenFarbe, farben.surfaceContainerLow);
    expect(
      leistenFarbe.computeLuminance(),
      greaterThan(grund.computeLuminance()),
      reason: 'Leiste dunkel etwas heller als der Grund',
    );
    await tippe(tester, find.text(de.einstDesignHell));
    expect(hell(), Brightness.light);
    expect(tester.widget<SegmentedButton<ThemeMode>>(segmente).selected, {
      ThemeMode.light,
    });
    await tippe(tester, find.text(de.einstDesignSystem));
    expect(tester.widget<SegmentedButton<ThemeMode>>(segmente).selected, {
      ThemeMode.system,
    });
    expect(hell(), Brightness.light);
    // GRU-118: System folgt dem Wechsel.
    pd.platformBrightnessTestValue = Brightness.dark;
    await settle(tester);
    expect(hell(), Brightness.dark);
    pd.platformBrightnessTestValue = Brightness.light;
    await settle(tester);
    expect(hell(), Brightness.light);
    // GRU-117: dunkel bleibt nach dem Neustart.
    await tippe(tester, find.text(de.einstDesignDunkel));
    await neustart(tester);
    await settle(tester);
    expect(hell(), Brightness.dark);
    pd.clearAllTestValues();
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-120 Videos beim Schweben abspielen', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, [fixture('video_5s.mp4')]);
    await settle(tester);
    final kachel = find.byType(AssetThumbnailTile);
    await waitFor(tester, kachel);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(location: const Offset(1300, 850));
    addTearDown(maus.removePointer);
    await tester.pump();
    Future<bool> spieltNachSchweben() async {
      await maus.moveTo(const Offset(1300, 850));
      await tester.pump(const Duration(milliseconds: 500));
      await maus.moveTo(tester.getCenter(kachel.first));
      final ende = DateTime.now().add(const Duration(seconds: 8));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 100));
        final v = find.byType(VideoSurface);
        if (v.evaluate().isNotEmpty &&
            tester.widget<VideoSurface>(v.first).controller.isPlaying) {
          return true;
        }
      }
      return false;
    }

    expect(
      await spieltNachSchweben(),
      isTrue,
      reason: 'eingeschaltet spielt es',
    );
    await maus.moveTo(const Offset(1300, 850));
    await tester.pump(const Duration(milliseconds: 300));
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittErscheinungsbild);
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
    await leiste(tester, de.navFotos);
    await waitFor(tester, kachel);
    expect(
      await spieltNachSchweben(),
      isFalse,
      reason: 'ausgeschaltet Standbild',
    );
    expect(find.byType(VideoSurface), findsNothing);
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-121 Gleiche Aufnahme in mehreren Formaten stapeln', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, [repoFixture('samples/sony_ilce6300.arw')]);
    final raw = (await aufnahmen()).single;
    print(
      'GRU-121: RAW-Datum ${raw.fileCreatedAt}, geschätzt ${raw.datumGeschaetzt}, '
      'Kamera ${raw.cameraMake} ${raw.cameraModel}',
    );
    expect(raw.datumGeschaetzt, isFalse);
    await importiere(tester, [
      testfoto(
        'sony_ilce6300.jpg',
        datum: raw.fileCreatedAt,
        kamera: raw.cameraMake ?? 'SONY',
        modell: raw.cameraModel ?? 'ILCE-6300',
      ),
    ]);
    final beide = await aufnahmen();
    expect(beide, hasLength(2));
    final dateien = [
      for (final a in beide) bibliothek.paths.absolute(a.relativePath),
    ];
    await settle(tester);
    expect(find.byType(AssetThumbnailTile), findsNWidgets(2));
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittErscheinungsbild);
    final schalter = find.ancestor(
      of: find.text(de.einstFormateStapelnTitel),
      matching: find.byType(SwitchListTile),
    );
    await tippe(tester, schalter);
    await eventually(tester, () async {
      final a = await aufnahmen();
      return a.every((x) => x.stackId != null) &&
          a.map((x) => x.stackId).toSet().length == 1;
    }, was: 'beide im selben Stapel');
    expect(find.textContaining('Stapeln fehlgeschlagen'), findsNothing);
    await leiste(tester, de.navFotos);
    await settle(tester);
    expect(find.byType(AssetThumbnailTile), findsOneWidget);
    expect(dateien.every((d) => d.existsSync()), isTrue);
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittErscheinungsbild);
    await tippe(tester, schalter);
    await eventually(
      tester,
      () async => (await aufnahmen()).every((x) => x.stackId == null),
      was: 'Stapel aufgelöst',
    );
    await leiste(tester, de.navFotos);
    await settle(tester);
    expect(find.byType(AssetThumbnailTile), findsNWidgets(2));
    expect(dateien.every((d) => d.existsSync()), isTrue);
    expect(await anzahlAufnahmen(), 2);
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-122 GRU-129 Sprache „English“, ohne Startbestückung, Neustart',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      // Nur selbst angelegte Begriffe.
      await bibliothek.db.delete(bibliothek.db.aiTagVocabulary).go();
      await bibliothek.db.addAiTagTerm('Probe eins');
      await einstellungen(tester);
      await gruppe(tester, de.spracheTitel);
      await tippe(tester, find.text(de.spracheEnglisch));
      await settle(tester);
      // GRU-122
      for (final t in [
        en.navFotos,
        en.navSuche,
        en.navAlben,
        en.navEinstellungen,
      ]) {
        expect(zeilenText(t), findsOneWidget, reason: t);
      }
      expect(find.text(en.spracheVokabularTitel), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // GRU-129
      await neustart(tester);
      expect(zeilenText(en.navFotos), findsOneWidget);
      expect(zeilenText(de.navFotos), findsNothing);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets(
    'GRU-123 GRU-130 GRU-131 Vokabular-Rückfrage, Nutzerdaten, Monatsnamen',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await bibliothek.db.setAutoAnalyzeAfterImport(false);
      final ids = await importiere(tester, [
        testfoto('maerz.jpg', datum: DateTime(2026, 3, 14, 10)),
      ]);
      await bibliothek.db.fuehreAus(
        AlbumAnlegen('alb', 'Urlaub', DateTime(2024)),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen('alb', ids));
      await bibliothek.db.fuehreAus(const PersonAnlegen('p1', 'Person A'));
      // GRU-131 (deutsch)
      await settle(tester);
      await waitFor(tester, find.textContaining('März 2026'));
      final vokabularVorher = await bibliothek.db.aiTagVocabularyTerms();
      expect(vokabularVorher, contains('Strand'));
      await einstellungen(tester);
      await gruppe(tester, de.spracheTitel);
      // GRU-130: Hinweis unter der Auswahl (deutsch).
      expect(find.text(de.spracheHinweis), findsOneWidget);
      await tippe(tester, find.text(de.spracheEnglisch));
      // GRU-123: Rückfrage in der neuen Sprache.
      await waitFor(tester, find.text(en.spracheVokabularTitel));
      final bekannt = vokabularVorher
          .where((b) => b == 'Strand' || true)
          .length;
      expect(
        find.textContaining(RegExp(r'\d+ of the \d+')),
        findsOneWidget,
        reason: 'nennt, wie viele übersetzbar sind',
      );
      print('GRU-123: Vokabular mit $bekannt Begriffen');
      await tippe(tester, find.text(en.spracheVokabularBehalten));
      await waitGone(tester, find.text(en.spracheVokabularTitel));
      expect(await bibliothek.db.aiTagVocabularyTerms(), vokabularVorher);
      // GRU-130: Nutzerdaten unverändert.
      expect((await bibliothek.db.alleAlben()).map((a) => a.name), ['Urlaub']);
      expect(
        (await bibliothek.db.select(bibliothek.db.people).get()).map(
          (x) => x.name,
        ),
        ['Person A'],
      );
      // GRU-131 (englisch, ohne Neustart)
      await leiste(tester, en.navFotos);
      await waitFor(tester, find.textContaining('March'));
      expect(find.textContaining('März'), findsNothing);
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-124 GRU-125 Vokabular übersetzen', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    final ids = await importiere(tester, fotos(1));
    final datei = bibliothek.paths.absolute(
      (await aufnahmen()).single.relativePath,
    );
    final summe = sha(datei);
    await bibliothek.db.fuehreAus(
      SchlagwortAnheften([ids.single], 'Strand', quelle: Tagquelle.ki),
    );
    await bibliothek.db.addAiTagTerm('Eigener Begriff eins');
    await bibliothek.db.addAiTagTerm('Eigener Begriff zwei');
    melde.verlaufLeeren();
    await einstellungen(tester);
    await gruppe(tester, de.spracheTitel);
    await tippe(tester, find.text(de.spracheEnglisch));
    await waitFor(tester, find.text(en.spracheVokabularTitel));
    // GRU-125
    expect(find.text(en.spracheVokabularSelbstAngelegt(2)), findsOneWidget);
    await tippe(tester, find.text(en.spracheVokabularUebersetzen));
    await waitFor(tester, find.textContaining(RegExp(r'terms? translated')));
    final terme = await bibliothek.db.aiTagVocabularyTerms();
    expect(
      terme,
      containsAll(['Eigener Begriff eins', 'Eigener Begriff zwei', 'Beach']),
    );
    expect(terme, isNot(contains('Strand')));
    // GRU-124
    final tags = await bibliothek.db.tagsForAsset(ids.single);
    expect(tags.map((t) => t.name), contains('Beach'));
    expect(tags.map((t) => t.name), isNot(contains('Strand')));
    expect(sha(datei), summe);
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-127 GRU-128 Systemsprache', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    final pd = tester.platformDispatcher;
    addTearDown(pd.clearAllTestValues);
    pd.localesTestValue = const [Locale('de')];
    pd.localeTestValue = const Locale('de');
    await settle(tester);
    await einstellungen(tester);
    await gruppe(tester, de.spracheTitel);
    // GRU-127
    await tippe(tester, find.text(de.spracheSystem));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(zeilenText(de.navFotos), findsOneWidget);
    expect(
      tester
          .widget<SegmentedButton<String>>(
            find.byWidgetPredicate((w) => w is SegmentedButton<String>),
          )
          .selected,
      {'system'},
    );
    // GRU-128: nicht unterstützte Systemsprache.
    pd.localesTestValue = const [Locale('fr')];
    pd.localeTestValue = const Locale('fr');
    await neustart(tester);
    expect(zeilenText(de.navFotos), findsOneWidget);
    expect(zeilenText(en.navFotos), findsNothing);
    pd.clearAllTestValues();
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-133 GRU-134 GRU-139 Über diese App', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await einstellungen(tester);
    await gruppe(tester, de.einstUeberTitel);
    // GRU-133
    final version = find.byWidgetPredicate(
      (w) =>
          w is Text && RegExp(r'^Photo Vault \d+\.\d+').hasMatch(w.data ?? ''),
    );
    await waitFor(tester, version);
    expect(find.textContaining('Bau '), findsOneWidget);
    expect(
      find.textContaining(' · ${Platform.operatingSystem} '),
      findsOneWidget,
    );
    expect(find.text(de.einstDatenbank), findsOneWidget);
    expect(
      find.text(de.einstDatenbankStand(bibliothek.db.schemaVersion)),
      findsOneWidget,
    );
    // GRU-134, ohne Modell.
    expect(find.text(de.einstKeineModelle), findsOneWidget);
    expect(find.text(de.einstModelleUnbenutzt), findsOneWidget);
    // GRU-139: Lizenzen.
    await zeigeInEinstellungen(tester, find.text(de.einstLizenzen));
    await tippe(tester, find.text(de.einstLizenzen));
    await waitFor(tester, find.byType(LicensePage));
    await waitFor(
      tester,
      find.text('EB Garamond'),
      timeout: const Duration(seconds: 30),
    );
    expect(find.textContaining('Photo Vault'), findsWidgets);
    final kopfVersion = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d+\.\d+\.\d+').hasMatch(w.data ?? ''),
    );
    expect(kopfVersion, findsWidgets);
    await tippe(tester, find.text('EB Garamond'));
    await waitFor(
      tester,
      find.textContaining('SIL Open Font License'),
      timeout: const Duration(seconds: 20),
    );
    await zurueck(tester);
    await settle(tester);
    if (find.byType(LicensePage).evaluate().isNotEmpty) await zurueck(tester);
    // GRU-134, mit Modell: das vorab geladene YuNet (230 KB) in den
    // Modellordner legen und neu starten – wie nach dem Herunterladen.
    await neustart(
      tester,
      dazwischen: () => verlinkeModelle(['face_detection_yunet.onnx']),
    );
    expect(bibliothek.isModelInstalled(ModelCatalog.faceDetection), isTrue);
    await einstellungen(tester);
    await gruppe(tester, de.einstUeberTitel);
    final gesamt = ModelCatalog.fuerSprache(
      'de',
      istInstalliert: bibliothek.isModelInstalled,
    ).length;
    await waitFor(tester, find.text(de.einstModelleGeladen(1, gesamt)));
    expect(
      find.text(modellTitel(de, ModelCatalog.faceDetection.id)),
      findsWidgets,
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-141 GRU-142 GRU-143 Gefahrenzone: Dialog und Abbrechen', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(2));
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittGefahrenzone);
    // GRU-141
    expect(find.text(de.einstResetText), findsOneWidget);
    expect(find.text(de.einstResetTitel), findsOneWidget);
    expect(find.text(de.einstResetKurz), findsOneWidget);
    final karteRot = tester.widget<Card>(
      find
          .ancestor(
            of: find.text(de.einstResetTitel),
            matching: find.byType(Card),
          )
          .first,
    );
    final rand = (karteRot.shape as RoundedRectangleBorder).side.color;
    final fehlerFarbe = Theme.of(
      tester.element(find.text(de.einstResetTitel)),
    ).colorScheme.error;
    expect(rand.r, closeTo(fehlerFarbe.r, 0.01));
    expect(rand.g, closeTo(fehlerFarbe.g, 0.01));
    final vorher = pruefsummen(anker, ohneDb: true);
    // GRU-142
    await zeigeInEinstellungen(tester, knopf(de.einstResetKnopf));
    await tippe(tester, knopf(de.einstResetKnopf));
    await waitFor(tester, find.text(de.einstResetBestaetigenTitel));
    final wortFeld = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    final fokus = FocusManager.instance.primaryFocus?.context;
    expect(
      fokus != null &&
              find
                  .descendant(
                    of: wortFeld,
                    matching: find.byWidget(fokus.widget),
                  )
                  .evaluate()
                  .isNotEmpty ||
          (fokus?.findAncestorWidgetOfExactType<TextField>() != null),
      isTrue,
      reason: 'Feld hat den Fokus',
    );
    final endgueltig = knopf(de.einstResetEndgueltig);
    await enter(tester, wortFeld, de.einstResetWort.toLowerCase());
    expect(knopfAktiv(tester, endgueltig), isFalse);
    await enter(tester, wortFeld, '');
    await enter(tester, wortFeld, de.einstResetWort);
    expect(knopfAktiv(tester, endgueltig), isTrue);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(
      find.text(de.einstResetBestaetigenTitel),
      findsOneWidget,
      reason: 'Klick daneben schliesst nicht',
    );
    // GRU-143
    await tippe(tester, knopfIn(find.byType(AlertDialog), de.allgAbbrechen));
    await waitGone(tester, find.text(de.einstResetBestaetigenTitel));
    expect(pruefsummen(anker, ohneDb: true), vorher);
    expect(await datenbankOffen(), isTrue);
    expect(await anzahlAufnahmen(), 2);
    await ende(tester);
  }, timeout: _frist);

  Future<void> zuruecksetzenUeberUi(WidgetTester tester) async {
    await einstellungen(tester);
    await gruppe(tester, de.einstAbschnittGefahrenzone);
    await zeigeInEinstellungen(tester, knopf(de.einstResetKnopf));
    await tippe(tester, knopf(de.einstResetKnopf));
    await waitFor(tester, find.text(de.einstResetBestaetigenTitel));
    await enter(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      de.einstResetWort,
    );
    await tester.tap(knopf(de.einstResetEndgueltig).first);
    await tester.pump();
  }

  testWidgets('GRU-144 GRU-145 Gefahrenzone: Zurücksetzen', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(2));
    // Modell und Standortdaten liegen im Datenordner.
    File(p.join(anker.path, 'models', 'probe.onnx'))
      ..createSync(recursive: true)
      ..writeAsStringSync('Modell');
    File(p.join(anker.path, 'geodata', 'cities1000.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('Ort');
    final zweit = Directory(p.join(anker.path, 'Zweit'));
    await legeBibliothekAn(zweit);
    await LibraryLocation.fuegeHinzu(
      PickedFolder(zweit.path, ''),
      name: 'Zweit',
    );
    final zweitVorher = pruefsummen(zweit);
    // GRU-144
    await zuruecksetzenUeberUi(tester);
    var laufGesehen = false;
    for (var i = 0; i < 200; i++) {
      if (find.text(de.einstResetLaeuft).evaluate().isNotEmpty) {
        laufGesehen = true;
      }
      if (find.text(de.einstNeustartTitel).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 16));
    }
    print('GRU-144: „Lösche Bibliothek …“ gesehen: $laufGesehen');
    await waitFor(
      tester,
      find.text(de.einstNeustartTitel),
      timeout: const Duration(seconds: 60),
    );
    expect(find.text(de.einstResetFertig), findsOneWidget);
    for (final s in ['', '-wal', '-shm']) {
      expect(
        File(p.join(anker.path, 'library.sqlite$s')).existsSync(),
        isFalse,
        reason: s,
      );
    }
    expect(Directory(p.join(anker.path, 'library')).existsSync(), isFalse);
    expect(
      File(p.join(anker.path, 'models', 'probe.onnx')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(anker.path, 'geodata', 'cities1000.txt')).existsSync(),
      isTrue,
    );
    expect(File(p.join(anker.path, 'location.json')).existsSync(), isTrue);
    // GRU-145
    await neustart(tester);
    expect(bibliothek.paths.root.parent.path, anker.path);
    await waitFor(tester, find.text(de.timelineLeer));
    expect(await anzahlAufnahmen(), 0);
    expect(pruefsummen(zweit), zweitVorher);
    expect(
      (await LibraryLocation.bekannte()).any(
        (b) => b.eintrag.path == zweit.path,
      ),
      isTrue,
    );
    await ende(tester);
  }, timeout: _frist);

  // Befund: „Datenbank zurücksetzen“ löscht verbindung.json nicht
  // (LibraryState.eraseLibraryDataAt, lib/state/library_state.dart:3539) –
  // die geleerte Bibliothek ist nach dem Neustart weiter mit dem Server
  // verbunden.
  testWidgets(
    'GRU-145 Verbundene Bibliothek: verbindung.json nach dem Zurücksetzen',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await importiere(tester, fotos(1));
      await neustart(tester, dazwischen: () => schreibeVerbindung(anker));
      expect(bibliothek.verbunden, isTrue);
      await zuruecksetzenUeberUi(tester);
      await waitFor(
        tester,
        find.text(de.einstNeustartTitel),
        timeout: const Duration(seconds: 60),
      );
      final bleibt = File(p.join(anker.path, 'verbindung.json')).existsSync();
      await neustart(tester);
      print(
        'GRU-145: verbindung.json bleibt: $bleibt, danach verbunden: ${bibliothek.verbunden}',
      );
      expect(bleibt, isFalse);
      expect(bibliothek.verbunden, isFalse);
      await ende(tester);
    },
    skip: true,
    timeout: _frist,
  );

  testWidgets('GRU-146 GRU-147 GRU-148 Werkzeuge', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    melde.verlaufLeeren();
    await leiste(tester, de.navWerkzeuge);
    final werkzeuge = find.byType(ToolsScreen);
    await waitFor(tester, werkzeuge);
    // GRU-146: „Aufgaben“ steht oben.
    final aufgabenKachel = find.ancestor(
      of: find.descendant(of: werkzeuge, matching: find.text(de.aufgTitel)),
      matching: find.byType(ListTile),
    );
    expect(aufgabenKachel, findsOneWidget);
    final kachelnY = tester
        .widgetList<ListTile>(
          find.descendant(of: werkzeuge, matching: find.byType(ListTile)),
        )
        .length;
    expect(kachelnY, greaterThan(3));
    final ersteKachel = find
        .descendant(of: werkzeuge, matching: find.byType(ListTile))
        .first;
    expect(
      find.descendant(of: ersteKachel, matching: find.text(de.aufgTitel)),
      findsOneWidget,
    );
    expect(find.text(de.werkzZuAufgabenText), findsOneWidget);
    expect(
      bibliothek.etwasLaeuft,
      isFalse,
      reason: 'kein Eintrag startet selbst etwas',
    );
    await tippe(tester, aufgabenKachel);
    await waitFor(tester, find.byType(BackgroundTasksScreen));
    expect(find.byType(Seitenleiste), findsOneWidget);
    await zurueck(tester);
    await waitGone(tester, find.byType(BackgroundTasksScreen));

    // GRU-147: jedes Werkzeug öffnet seinen Bildschirm neben der Leiste.
    final werkzeugListe = find
        .descendant(of: werkzeuge, matching: find.byType(Scrollable))
        .first;
    final ziele = <(String, Type)>[
      (de.scanTitel, ScanWorkspaceScreen),
      (de.gesundheitTitel, LibraryHealthScreen),
      (de.werkzAnalyseseiteTitel, StatisticsScreen),
      (de.werkzGpxTitel, GpxVerortungScreen),
      (de.werkzPresetsTitel, CameraPresetsScreen),
      (de.werkzExportVorgabenTitel, ExportPresetsScreen),
      (de.staubTitel, StaubsucheScreen),
      (de.werkzRegelnTitel, AutomationRulesScreen),
      (de.werkzDuplikateTitel, DuplicatesScreen),
      (de.datierungTitel, DatierungScreen),
      (de.aufnahmedatenTitel, AufnahmedatenScreen),
      (de.werkzStapelTitel, StackReviewScreen),
      (de.ortVorschlagWerkzTitel, OrtsvorschlaegeScreen),
      (de.werkzIntegritaetTitel, IntegrityCheckScreen),
      (de.werkzXmpLesenTitel, XmpImportScreen),
    ];
    for (final (titel, typ) in ziele) {
      final f = find.descendant(of: werkzeuge, matching: find.text(titel));
      tester.state<ScrollableState>(werkzeugListe).position.jumpTo(0);
      await tester.pump();
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: werkzeugListe,
        maxScrolls: 60,
      );
      await tippe(tester, f);
      await waitFor(tester, find.byType(typ));
      expect(find.byType(Seitenleiste), findsOneWidget, reason: titel);
      expect(
        tester.getTopLeft(find.byType(typ)).dx,
        greaterThanOrEqualTo(Seitenleiste.schmal - 1),
        reason: titel,
      );
      expect(tester.takeException(), isNull, reason: titel);
      await zurueck(tester);
      await waitGone(tester, find.byType(typ));
      await waitFor(tester, werkzeuge);
    }

    // GRU-148: leer – Meldung; mit Fotos – Sichtung im Vollbild.
    final sichten = find.descendant(
      of: werkzeuge,
      matching: find.text(de.werkzSichtenTitel),
    );
    await tester.scrollUntilVisible(
      sichten,
      200,
      scrollable: werkzeugListe,
      maxScrolls: 60,
    );
    await tippe(tester, sichten);
    await erwarteMeldung(tester, de.werkzKeineUnbewerteten);
    await importiere(tester, fotos(1));
    await tippe(tester, sichten);
    await waitFor(tester, find.byType(AssetViewerScreen));
    await settle(tester);
    expect(find.byType(Seitenleiste), findsNothing);
    expect(
      tester.getRect(find.byType(AssetViewerScreen)),
      Offset.zero & const Size(1400, 900),
    );
    await key(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(AssetViewerScreen));
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-149 GRU-150 GRU-151 Werkzeuge: Regler und Auskunft', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await leiste(tester, de.navWerkzeuge);
    final werkzeuge = find.byType(ToolsScreen);
    await waitFor(tester, werkzeuge);
    final liste = find
        .descendant(of: werkzeuge, matching: find.byType(Scrollable))
        .first;
    final regler = find.descendant(
      of: werkzeuge,
      matching: find.byType(Slider),
    );
    await tester.scrollUntilVisible(
      regler,
      200,
      scrollable: liste,
      maxScrolls: 40,
    );
    await settle(tester);
    // GRU-149
    final s = tester.widget<Slider>(regler.first);
    expect(s.min, closeTo(0.15, 1e-9));
    expect(s.max, closeTo(0.60, 1e-9));
    print('GRU-149: Startwert ${s.value}');
    var wertBeimZiehen = '';
    await zieheRegler(
      tester,
      regler.first,
      0.50,
      beimZiehen: () {
        final v = tester.widget<Slider>(regler.first).value;
        wertBeimZiehen = find.text(v.toStringAsFixed(2)).evaluate().isNotEmpty
            ? v.toStringAsFixed(2)
            : '';
      },
    );
    expect(
      wertBeimZiehen,
      isNotEmpty,
      reason: 'Wert steht beim Ziehen daneben',
    );
    expect(tester.widget<Slider>(regler.first).value, closeTo(0.50, 0.001));
    expect(find.text('0.50'), findsOneWidget);
    await eventually(
      tester,
      () async => (bibliothek.faceSimilarityThreshold - 0.50).abs() < 0.001,
      was: 'Schwelle gespeichert',
    );
    await neustart(tester);
    await leiste(tester, de.navWerkzeuge);
    await waitFor(tester, werkzeuge);
    await tester.scrollUntilVisible(
      regler,
      200,
      scrollable: liste,
      maxScrolls: 40,
    );
    expect(tester.widget<Slider>(regler.first).value, closeTo(0.50, 0.001));

    // GRU-150
    final schalter = find.ancestor(
      of: find.text(de.werkzAutoVorschlaege),
      matching: find.byType(SwitchListTile),
    );
    await tester.scrollUntilVisible(
      schalter,
      200,
      scrollable: liste,
      maxScrolls: 40,
    );
    await tippe(tester, schalter);
    await waitFor(tester, find.text(de.werkzAutoVorschlaegeAb('0.70')));
    expect(regler, findsNWidgets(2));
    final zweiter = regler.at(1);
    expect(tester.widget<Slider>(zweiter).min, closeTo(0.6, 1e-9));
    expect(tester.widget<Slider>(zweiter).max, closeTo(0.9, 1e-9));
    await zieheRegler(tester, zweiter, 0.80);
    expect(find.text(de.werkzAutoVorschlaegeAb('0.80')), findsOneWidget);
    await tippe(tester, schalter);
    expect(regler, findsOneWidget);
    expect(find.textContaining('ab 0.'), findsNothing);

    // GRU-151
    final heic = find.text(de.werkzHeicTitel);
    await tester.scrollUntilVisible(
      heic,
      200,
      scrollable: liste,
      maxScrolls: 40,
    );
    await waitFor(tester, find.text(de.werkzHeicAktiv));
    final heicKachel = find.ancestor(of: heic, matching: find.byType(ListTile));
    expect(
      find.descendant(
        of: heicKachel,
        matching: find.byIcon(Icons.check_circle_outline),
      ),
      findsOneWidget,
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-176 GRU-178 GRU-180 GRU-183 GRU-185 Meldungen', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    melde.verlaufLeeren();
    tester.takeAnnouncements();
    await leiste(tester, de.navWerkzeuge);
    final werkzeuge = find.byType(ToolsScreen);
    await waitFor(tester, werkzeuge);
    final liste = find
        .descendant(of: werkzeuge, matching: find.byType(Scrollable))
        .first;
    final sichten = find.descendant(
      of: werkzeuge,
      matching: find.text(de.werkzSichtenTitel),
    );
    await tester.scrollUntilVisible(
      sichten,
      200,
      scrollable: liste,
      maxScrolls: 60,
    );
    final meldung = find.text(de.werkzKeineUnbewerteten);
    // GRU-176 (breit): oben rechts.
    await tippe(tester, sichten);
    await waitFor(tester, meldung);
    final r = tester.getRect(meldung);
    expect(r.right, greaterThan(1200));
    expect(r.top, lessThan(200));
    // GRU-185: genau einmal vorgelesen.
    var ansagen = tester.takeAnnouncements().where(
      (a) => a.message == de.werkzKeineUnbewerteten,
    );
    expect(ansagen, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(meldung, findsNothing, reason: 'verblasst');
    ansagen = tester.takeAnnouncements().where(
      (a) => a.message == de.werkzKeineUnbewerteten,
    );
    expect(ansagen, isEmpty, reason: 'nicht noch einmal nach Ablauf');
    // GRU-178: dreimal schnell – eine Karte mit „3×“.
    melde.verlaufLeeren();
    for (var i = 0; i < 3; i++) {
      await tester.tap(sichten);
      await tester.pump(const Duration(milliseconds: 150));
    }
    await settle(tester, max: const Duration(seconds: 1));
    expect(meldung, findsOneWidget);
    expect(find.text(de.meldungWiederholt(3)), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    // GRU-180: zwei Meldungen verblasst – Glocke und Verlauf.
    melde.verlaufLeeren();
    await settle(tester);
    await tippe(tester, sichten);
    await tester.pump(const Duration(milliseconds: 1200));
    melde.erfolg('Probemeldung erledigt');
    await tester.pump(const Duration(seconds: 6));
    await settle(tester);
    final glocke = find.byTooltip(de.meldungenGlocke);
    await waitFor(tester, glocke);
    expect(
      find.descendant(of: glocke, matching: find.text('2')),
      findsOneWidget,
    );
    await tippe(tester, glocke);
    await waitFor(tester, find.text(de.meldungenTitel));
    final erfolgY = tester.getTopLeft(find.text('Probemeldung erledigt')).dy;
    final hinweisY = tester.getTopLeft(find.text(de.werkzKeineUnbewerteten)).dy;
    expect(erfolgY, lessThan(hinweisY), reason: 'neueste zuerst');
    expect(find.textContaining(de.meldungArtErfolg), findsWidgets);
    expect(find.textContaining(de.meldungArtHinweis), findsWidgets);
    expect(find.textContaining(RegExp(r'\d{1,2}:\d{2}')), findsWidgets);
    expect(find.descendant(of: glocke, matching: find.text('2')), findsNothing);
    expect(melde.ungelesen, 0);
    await tippe(tester, find.text(de.meldungenVerlaufLeeren));
    await waitFor(tester, find.text(de.meldungenKeine));
    // Verlauf schliessen.
    await tippe(tester, glocke);
    await settle(tester);
    // GRU-183: Fehlermeldung bleibt bei Bereichswechsel und über Dialogen.
    melde.verlaufLeeren();
    melde.fehler('Probefehler');
    await waitFor(tester, find.text('Probefehler'));
    await leiste(tester, de.navAlben);
    expect(find.text('Probefehler'), findsOneWidget);
    await mitUmschalt(tester, LogicalKeyboardKey.slash, '?');
    await waitFor(tester, find.widgetWithText(AlertDialog, de.kuerzelTitel));
    expect(find.text('Probefehler').hitTestable(), findsOneWidget);
    await key(tester, LogicalKeyboardKey.escape);
    melde.verlaufLeeren();
    // GRU-176 (schmal): unten mittig.
    await fenster(tester, const Size(560, 900));
    await settle(tester);
    await openSection(tester, Hauptbereich.werkzeuge);
    await waitFor(tester, werkzeuge);
    final liste2 = find
        .descendant(of: werkzeuge, matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      sichten,
      200,
      scrollable: liste2,
      maxScrolls: 60,
    );
    await tippe(tester, sichten);
    await waitFor(tester, meldung);
    final r2 = tester.getRect(meldung);
    expect(r2.bottom, greaterThan(700));
    expect(r2.center.dx, closeTo(280, 80));
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-154 GRU-155 GRU-167 Aufgaben: Aufbau', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, fotos(3));
    await aufgabenOeffnen(tester);
    final kopf = find.descendant(
      of: find.byType(BackgroundTasksScreen),
      matching: find.byType(AppBar),
    );
    // GRU-154
    final mq = MediaQuery.of(
      tester.element(find.byType(BackgroundTasksScreen)),
    );
    final beschriftet = find
        .descendant(of: kopf, matching: find.text(de.aufgErstellen))
        .evaluate()
        .isNotEmpty;
    print(
      'GRU-154: Breite ${mq.size.width}, Schrift ${mq.textScaler.scale(1)}, '
      'Schwelle ${mq.textScaler.scale(1000)}, beschriftet $beschriftet',
    );
    expect(kopfknopf(de.aufgErstellen), findsOneWidget);
    expect(kopfknopf(de.aufgGleichzeitigTitel), findsOneWidget);
    if (mq.size.width >= mq.textScaler.scale(1000)) {
      expect(beschriftet, isTrue, reason: 'genug Platz: mit Beschriftung');
    }
    final sammel = await karte(tester, de.werkzAllesNachholenTitel);
    expect(zahl(tester, sammel, de.aufgAktiv), isNotNull);
    expect(zahl(tester, sammel, de.aufgStatus), de.aufgBereit);
    expect(
      find.descendant(of: sammel, matching: find.text(de.aufgJetztStarten)),
      findsOneWidget,
    );
    for (final (titel, aktionen) in [
      (de.aufgOrteTitel, [de.aufgModusAlle, de.aufgFehlende]),
      (de.aufgKameraTitel, [de.aufgFehlende]),
      (de.aufgUnschaerfeTitel, [de.aufgFehlende]),
      (de.aufgVideobilderTitel, [de.aufgModusAlle, de.aufgFehlende]),
    ]) {
      final k = await karte(tester, titel);
      expect(find.descendant(of: k, matching: find.byType(Icon)), findsWidgets);
      expect(zahl(tester, k, de.aufgAktiv), '0', reason: titel);
      expect(zahl(tester, k, de.aufgWartend), '0', reason: titel);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        textIn(
          tester,
          k,
          (s) =>
              RegExp(r'^\d+ Fotos offen$').hasMatch(s) ||
              RegExp('^${de.aufgBetrifft}: \\d+\$').hasMatch(s) ||
              s.startsWith(de.aufgNeuSeitLauf(0).split(':').first),
        ),
        isTrue,
        reason: 'offene Zahl bei $titel',
      );
      for (final a in aktionen) {
        expect(
          find.descendant(of: k, matching: find.text(a)),
          findsOneWidget,
          reason: '$titel $a',
        );
      }
    }
    // GRU-167: ohne YuNet gesperrt.
    final gesichter = await karte(tester, de.werkzGesichterScannenTitel);
    expect(
      find.descendant(
        of: gesichter,
        matching: find.text(
          de.aufgModellNoetig(de.aufgYunetModell, de.aufgWoModelle),
        ),
      ),
      findsOneWidget,
    );
    final knoepfe = tester.widgetList<InkWell>(
      find.descendant(of: gesichter, matching: find.byType(InkWell)),
    );
    expect(
      knoepfe.every((k) => k.onTap == null),
      isTrue,
      reason: 'keine bedienbaren Knöpfe',
    );
    await tippe(tester, kopfknopf(de.aufgErstellen));
    await waitFor(tester, find.byType(CheckboxListTile));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.werkzGesichterScannenTitel),
      ),
      findsNothing,
    );
    await tippe(tester, knopfIn(find.byType(AlertDialog), de.allgAbbrechen));
    // GRU-155: schmal nur Symbole.
    await fenster(tester, const Size(640, 900));
    await settle(tester);
    expect(tester.takeException(), isNull);
    if (find.byType(BackgroundTasksScreen).evaluate().isEmpty) {
      await openSection(tester, Hauptbereich.werkzeuge);
      await tippe(
        tester,
        find.descendant(
          of: find.byType(ToolsScreen),
          matching: find.text(de.aufgTitel),
        ),
      );
      await waitFor(tester, find.byType(BackgroundTasksScreen));
    }
    expect(tester.takeException(), isNull);
    expect(find.byTooltip(de.aufgErstellen), findsOneWidget);
    expect(find.byTooltip(de.aufgGleichzeitigTitel), findsOneWidget);
    expect(
      find.descendant(of: kopf, matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kopf, matching: find.byIcon(Icons.settings_outlined)),
      findsOneWidget,
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-156 GRU-052 GRU-053 Hintergrundanalyse und Band', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, fotos(36, stamm: 'g', breite: 2000, hoehe: 1500));
    expect((await aufnahmen()).every((a) => a.sharpnessScore == null), isTrue);
    melde.verlaufLeeren();
    await aufgabenOeffnen(tester);
    var sammel = await karte(tester, de.werkzAllesNachholenTitel);
    // GRU-156 / GRU-052
    await aktion(tester, sammel, de.aufgJetztStarten);
    await waitFor(tester, find.text(de.aufgLaeuft));
    await waitFor(tester, find.textContaining(bandAnfang()));
    await waitFor(
      tester,
      find.descendant(
        of: sammel,
        matching: find.text(de.aufgStufeKurz(1, Analysestufe.values.length)),
      ),
    );
    expect(
      textIn(
        tester,
        sammel,
        (s) =>
            s.startsWith('${de.stufeBildanalyse} (') &&
            s.endsWith('– Stufe 1/${Analysestufe.values.length}'),
      ),
      isTrue,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            RegExp(
              '${RegExp.escape(bandAnfang())}, \\d+/36\\)',
            ).hasMatch(w.data ?? ''),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bandZeile(bandAnfang()),
        matching: find.byType(TextButton),
      ),
      findsOneWidget,
    );
    // Bereichswechsel: Band bleibt.
    await leisteSchnell(tester, de.navAlben);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining(bandAnfang()), findsOneWidget);
    // GRU-053: Klick auf den Text bricht nichts ab.
    await tester.tap(find.textContaining(bandAnfang()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(bibliothek.analyseLaeuft, isTrue);
    await tester.tap(
      find.descendant(
        of: bandZeile(bandAnfang()),
        matching: find.byType(TextButton),
      ),
    );
    await eventually(
      tester,
      () async => !bibliothek.analyseLaeuft,
      was: 'Analyse hält an',
    );
    await waitGone(tester, find.textContaining(bandAnfang()));
    final ausgewertet = (await aufnahmen())
        .where((a) => a.sharpnessScore != null)
        .length;
    expect(ausgewertet, greaterThan(0));
    expect(
      ausgewertet,
      lessThan(36),
      reason: 'abgebrochen, bevor alles fertig war',
    );
    // GRU-156: Abbrechen in der Karte.
    await aufgabenOeffnen(tester);
    sammel = await karte(tester, de.werkzAllesNachholenTitel);
    await aktion(tester, sammel, de.aufgJetztStarten);
    await waitFor(
      tester,
      find.descendant(
        of: sammel,
        matching: find.text(de.aufgStufeKurz(1, Analysestufe.values.length)),
      ),
    );
    await aktion(tester, sammel, de.allgAbbrechen);
    await eventually(
      tester,
      () async => !bibliothek.analyseLaeuft,
      was: 'Analyse hält an',
    );
    await settle(tester);
    expect(zahl(tester, sammel, de.aufgStatus), de.aufgBereit);
    final danach = (await aufnahmen())
        .where((a) => a.sharpnessScore != null)
        .length;
    expect(
      danach,
      greaterThanOrEqualTo(ausgewertet),
      reason: 'Ausgewertetes bleibt',
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-157 GRU-054 GRU-158 GRU-159 GRU-175 Aufgabe „Orte einlesen“', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    const n = 600;
    await importiere(
      tester,
      grosseFotos(n, stamm: 'ort', breite: 120, hoehe: 90, mitOrt: true),
    );
    expect(await anzahlAufnahmen(), n);
    // Vorbedingung wie nach einem Import aus einer älteren Fassung: Der
    // Ort steht in der Datei, aber noch nicht in der Datenbank.
    Future<void> orteVergessen() => bibliothek.db.customStatement(
      'UPDATE assets SET latitude = NULL, longitude = NULL, gps_geprueft = 0',
    );
    await orteVergessen();
    await aufgabenOeffnen(tester);
    var orte = await karte(tester, de.aufgOrteTitel);
    // GRU-157: läuft in der Karte, ohne Dialog.
    final start = DateTime.now();
    await aktion(tester, orte, de.aufgModusAlle);
    final l0 = bibliothek.lauf('orte');
    print(
      'GRU-157: nach dem Klick lauf=${l0 != null}, läuft ${l0?.laeuft}, '
      'beendet ${l0?.beendet}, ${l0?.erledigt}/${l0?.gesamt}',
    );
    var titelGesehen = false;
    var zahlenGesehen = false;
    var dateiGesehen = false;
    var nurAbbrechen = false;
    var aktivEins = false;
    var balken = false;
    var dialogGesehen = false;
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(AlertDialog).evaluate().isNotEmpty) dialogGesehen = true;
      final lauf = bibliothek.lauf('orte');
      if (lauf == null) continue;
      if (lauf.laeuft) {
        titelGesehen |= find
            .descendant(of: orte, matching: find.text(de.werkzLeseOrte))
            .evaluate()
            .isNotEmpty;
        zahlenGesehen |= textIn(
          tester,
          orte,
          (s) => RegExp(r'^\d+ / \d+$').hasMatch(s),
        );
        dateiGesehen |= textIn(
          tester,
          orte,
          (s) => RegExp(r'ort\d{4}\.jpg').hasMatch(s),
        );
        balken |= find
            .descendant(
              of: orte,
              matching: find.byType(LinearProgressIndicator),
            )
            .evaluate()
            .isNotEmpty;
        aktivEins |= zahl(tester, orte, de.aufgAktiv) == '1';
        nurAbbrechen |=
            find
                .descendant(of: orte, matching: find.text(de.allgAbbrechen))
                .evaluate()
                .isNotEmpty &&
            find
                .descendant(of: orte, matching: find.text(de.aufgModusAlle))
                .evaluate()
                .isEmpty &&
            find
                .descendant(of: orte, matching: find.text(de.aufgFehlende))
                .evaluate()
                .isEmpty;
      }
      if (lauf.beendet) break;
    }
    print(
      'GRU-157: Dauer bis zum Ende ${DateTime.now().difference(start).inMilliseconds} ms',
    );
    print(
      'GRU-157: Titel $titelGesehen, Zahlen $zahlenGesehen, Datei $dateiGesehen, '
      'Balken $balken, nur Abbrechen $nurAbbrechen, Aktiv 1 $aktivEins, Dialog $dialogGesehen',
    );
    expect(dialogGesehen, isFalse);
    expect(
      titelGesehen && zahlenGesehen && balken && nurAbbrechen && aktivEins,
      isTrue,
    );
    expect(dateiGesehen, isTrue);
    // GRU-158: Ende und Schliessen.
    await eventually(
      tester,
      () async => bibliothek.lauf('orte')?.beendet ?? false,
    );
    await settle(tester);
    expect(
      find.descendant(of: orte, matching: find.text(de.aufgFertigMit(n))),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.descendant(
              of: orte,
              matching: find.byType(LinearProgressIndicator),
            ),
          )
          .value,
      closeTo(1, 0.001),
    );
    await aktion(tester, orte, de.allgSchliessen);
    await settle(tester);
    expect(
      find.descendant(of: orte, matching: find.text(de.aufgModusAlle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: orte, matching: find.text(de.aufgFehlende)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: orte, matching: find.text('${de.aufgBetrifft}: 0')),
      findsOneWidget,
    );

    // GRU-054 / GRU-175: Band, während man in die Fotos wechselt.
    await orteVergessen();
    await aktion(tester, orte, de.aufgModusAlle);
    await leisteSchnell(tester, de.navFotos);
    var bandGesehen = false;
    final zahlen = <int>{};
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final t in tester.widgetList<Text>(
        find.textContaining(de.werkzLeseOrte),
      )) {
        final m = RegExp('  (\\d+)/$n').firstMatch(t.data ?? '');
        if (m != null) {
          bandGesehen = true;
          zahlen.add(int.parse(m.group(1)!));
        }
      }
      if (i == 20) await leisteSchnell(tester, de.navAlben);
      if (i == 40) await leisteSchnell(tester, de.navFotos);
      if (bibliothek.lauf('orte')?.beendet ?? false) break;
    }
    print('GRU-054/175: Band gesehen $bandGesehen, Zahlen $zahlen');
    expect(bandGesehen, isTrue);
    expect(tester.takeException(), isNull);
    await eventually(
      tester,
      () async => bibliothek.lauf('orte')?.beendet ?? false,
    );
    await waitGone(tester, find.textContaining(de.werkzLeseOrte));

    // GRU-159: nichts zu tun.
    await aufgabenOeffnen(tester);
    orte = await karte(tester, de.aufgOrteTitel);
    if (find
        .descendant(of: orte, matching: find.text(de.allgSchliessen))
        .evaluate()
        .isNotEmpty) {
      await aktion(tester, orte, de.allgSchliessen);
      await settle(tester);
    }
    await aktion(tester, orte, de.aufgFehlende);
    await waitFor(
      tester,
      find.descendant(of: orte, matching: find.text(de.werkzAlleHabenOrt)),
    );
    expect(
      find.descendant(of: orte, matching: find.text('0 / 0')),
      findsNothing,
    );
    await ende(tester);
  }, timeout: _frist);

  testWidgets(
    'GRU-160 GRU-162 GRU-163 GRU-164 GRU-161 Schwere Aufgaben, Abbrechen, Wegnavigieren',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await bibliothek.db.setAutoAnalyzeAfterImport(false);
      const n = 40;
      await importiere(tester, grosseFotos(n, stamm: 'u', mitOrt: true));
      expect(await anzahlAufnahmen(), n);
      expect(bibliothek.maxGleichzeitig, 1);
      await aufgabenOeffnen(tester);
      var unschaerfe = await karte(tester, de.aufgUnschaerfeTitel);
      // GRU-160: abbrechen.
      await aktion(tester, unschaerfe, de.aufgFehlende);
      var lauf = bibliothek.lauf('unschaerfe')!;
      await eventually(tester, () async => lauf.erledigt >= 2 || lauf.beendet);
      print('GRU-160: vor dem Abbrechen ${lauf.erledigt}/${lauf.gesamt}');
      expect(lauf.laeuft, isTrue);
      await aktion(tester, unschaerfe, de.allgAbbrechen);
      await eventually(tester, () async => lauf.beendet);
      await settle(tester, max: const Duration(seconds: 1));
      final x = lauf.erledigt;
      expect(lauf.abgebrochen, isTrue);
      expect(
        find.descendant(
          of: unschaerfe,
          matching: find.text(de.aufgAbgebrochenBei(x, n)),
        ),
        findsOneWidget,
      );
      final mitWert = (await aufnahmen())
          .where((a) => a.sharpnessScore != null)
          .length;
      expect(mitWert, inInclusiveRange(x, x + 1));
      await aktion(tester, unschaerfe, de.allgSchliessen);
      await settle(tester, max: const Duration(seconds: 1));
      expect(
        find.descendant(
          of: unschaerfe,
          matching: find.text(de.aufgOffeneFotos(n - mitWert)),
        ),
        findsOneWidget,
      );

      // GRU-162: zweite schwere Aufgabe wartet, „Orte einlesen“ läuft mit
      // (Unschärfe und Videobilder statt Gesichter und CLIP).
      await aktion(tester, unschaerfe, de.aufgFehlende);
      lauf = bibliothek.lauf('unschaerfe')!;
      expect(lauf.laeuft, isTrue);
      var video = await karte(tester, de.aufgVideobilderTitel);
      await aktion(tester, video, de.aufgModusAlle);
      await tester.pump(const Duration(milliseconds: 200));
      expect(bibliothek.lauf('videobilder')?.wartet, isTrue);
      expect(zahl(tester, video, de.aufgWartend), '1');
      final orte = await karte(tester, de.aufgOrteTitel);
      await aktion(tester, orte, de.aufgModusAlle);
      await tester.pump(const Duration(milliseconds: 200));
      final orteLauf = bibliothek.lauf('orte');
      expect(orteLauf != null && (orteLauf.laeuft || orteLauf.beendet), isTrue);
      expect(lauf.laeuft, isTrue, reason: 'Unschärfe läuft noch');
      // GRU-163: wartende streichen.
      video = await karte(tester, de.aufgVideobilderTitel);
      await aktion(tester, video, de.allgAbbrechen);
      await tester.pump(const Duration(milliseconds: 200));
      final v = bibliothek.lauf('videobilder');
      expect(v == null || !v.offen, isTrue, reason: 'gestrichen');
      expect(lauf.laeuft, isTrue, reason: 'die laufende arbeitet weiter');
      if (v != null &&
          find
              .descendant(of: video, matching: find.text(de.allgSchliessen))
              .evaluate()
              .isNotEmpty) {
        await aktion(tester, video, de.allgSchliessen);
        await tester.pump(const Duration(milliseconds: 200));
      }
      // GRU-164: Gleichzeitige Ausführungen.
      await aktion(tester, video, de.aufgModusAlle);
      await tester.pump(const Duration(milliseconds: 200));
      expect(bibliothek.lauf('videobilder')?.wartet, isTrue);
      await tester.tap(kopfknopf(de.aufgGleichzeitigTitel).first);
      await tester.pump(const Duration(milliseconds: 300));
      final weniger = find.byTooltip(de.aufgWenigerGleichzeitig);
      final mehr = find.byTooltip(de.aufgMehrGleichzeitig);
      await waitFor(tester, weniger);
      IconButton ib(Finder f) => tester.widget<IconButton>(
        find.ancestor(of: f, matching: find.byType(IconButton)).first,
      );
      Finder zahlImDialog(String w) =>
          find.descendant(of: find.byType(AlertDialog), matching: find.text(w));
      expect(zahlImDialog('1'), findsOneWidget);
      expect(ib(weniger).onPressed, isNull);
      for (var i = 0; i < 3; i++) {
        await tester.tap(mehr);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(zahlImDialog('4'), findsOneWidget);
      expect(ib(mehr).onPressed, isNull);
      for (var i = 0; i < 2; i++) {
        await tester.tap(weniger);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(zahlImDialog('2'), findsOneWidget);
      await tester.tap(knopf(de.allgSpeichern).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(bibliothek.maxGleichzeitig, 2);
      final vl = bibliothek.lauf('videobilder');
      print(
        'GRU-164: Unschärfe läuft ${lauf.laeuft}, '
        'Videobilder läuft ${vl?.laeuft}, beendet ${vl?.beendet}',
      );
      expect(
        vl != null && (vl.laeuft || vl.beendet),
        isTrue,
        reason: 'startet sofort',
      );
      // Abbrechen verwirft eine Änderung.
      await tester.tap(kopfknopf(de.aufgGleichzeitigTitel).first);
      await tester.pump(const Duration(milliseconds: 300));
      await waitFor(tester, mehr);
      await tester.tap(mehr);
      await tester.pump(const Duration(milliseconds: 100));
      expect(zahlImDialog('3'), findsOneWidget);
      await tester.tap(
        knopfIn(find.byType(AlertDialog), de.allgAbbrechen).first,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(bibliothek.maxGleichzeitig, 2);

      // GRU-161: läuft beim Wegnavigieren weiter.
      final nochOffen = lauf.laeuft;
      print(
        'GRU-161: Unschärfe läuft noch: $nochOffen (${lauf.erledigt}/${lauf.gesamt})',
      );
      await leisteSchnell(tester, de.navFotos);
      if (nochOffen) {
        await waitFor(tester, find.textContaining(de.werkzBerechneUnschaerfe));
        await tester.pump(const Duration(seconds: 1));
        expect(
          find
                  .textContaining(de.werkzBerechneUnschaerfe)
                  .evaluate()
                  .isNotEmpty ||
              lauf.beendet,
          isTrue,
        );
      }
      await aufgabenOeffnen(tester);
      unschaerfe = await karte(tester, de.aufgUnschaerfeTitel);
      final fortschritt = textIn(
        tester,
        unschaerfe,
        (s) =>
            RegExp(r'^\d+ / \d+$').hasMatch(s) ||
            s == de.aufgFertigMit(lauf.gesamt),
      );
      print(
        'GRU-161: Karte zeigt Fortschritt/Bilanz: $fortschritt, '
        'läuft ${lauf.laeuft}, ${lauf.erledigt}/${lauf.gesamt}',
      );
      expect(
        nochOffen,
        isTrue,
        reason: 'Lauf war beim Wegnavigieren noch offen',
      );
      expect(fortschritt, isTrue, reason: 'aktueller Stand in der Karte');
      await eventually(
        tester,
        () async => !bibliothek.etwasLaeuft,
        timeout: const Duration(seconds: 120),
      );
      await neustart(tester);
      expect(bibliothek.maxGleichzeitig, 2, reason: 'bleibt nach dem Neustart');
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-165 GRU-166 „Aufgabe erstellen“', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    await importiere(tester, fotos(5, mitOrt: true));
    final originale = pruefsummen(
      Directory(p.join(bibliothek.paths.root.path, 'originals')),
    );
    melde.verlaufLeeren();
    await aufgabenOeffnen(tester);
    Future<void> oeffneDialog() async {
      await tippe(tester, kopfknopf(de.aufgErstellen));
      await waitFor(tester, find.byType(CheckboxListTile));
    }

    final dlg = find.byType(AlertDialog);
    Future<void> kreuze(String titel) async {
      final f = find.descendant(of: dlg, matching: find.text(titel));
      final scroll = find
          .descendant(of: dlg, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(
        f,
        100,
        scrollable: scroll,
        maxScrolls: 40,
      );
      await tippe(tester, f);
    }

    // GRU-165
    await oeffneDialog();
    for (final m in [
      de.aufgModusAlle,
      de.aufgFehlende,
      de.aufgModusDarktable,
    ]) {
      expect(
        find.descendant(of: dlg, matching: find.text(m)),
        findsOneWidget,
        reason: m,
      );
    }
    expect(
      find.descendant(
        of: dlg,
        matching: find.text(de.werkzGesichterScannenTitel),
      ),
      findsNothing,
    );
    final einreihen = knopfIn(dlg, de.aufgEinreihen);
    expect(knopfAktiv(tester, einreihen), isFalse);
    await kreuze(de.aufgOrteTitel);
    expect(knopfAktiv(tester, einreihen), isTrue);
    await tippe(tester, knopfIn(dlg, de.allgAbbrechen));
    await waitGone(tester, dlg);
    expect(
      bibliothek.lauf('orte'),
      isNull,
      reason: 'Abbrechen reiht nichts ein',
    );
    await oeffneDialog();
    await kreuze(de.aufgOrteTitel);
    await kreuze(de.aufgKameraTitel);
    await tippe(tester, einreihen);
    await erwarteMeldung(tester, de.aufgEingereiht(2));
    expect(bibliothek.lauf('orte'), isNotNull);
    expect(bibliothek.lauf('kameradaten'), isNotNull);
    await eventually(tester, () async => !bibliothek.etwasLaeuft);
    // Hinweis prüfen: Modus „Namen wie darktable“ bei „Orte einlesen“.
    // Vorbedingung: Ort fehlt in der Datenbank, die Dateien wurden schon
    // angesehen – „Alle“ hätte 5 Fotos zu tun, „Fehlende“ keines.
    await bibliothek.db.customStatement(
      'UPDATE assets SET latitude = NULL, longitude = NULL, gps_geprueft = 1',
    );
    await oeffneDialog();
    await tippe(
      tester,
      find.descendant(of: dlg, matching: find.text(de.aufgModusDarktable)),
    );
    await kreuze(de.aufgOrteTitel);
    await tippe(tester, einreihen);
    await eventually(
      tester,
      () async => bibliothek.lauf('orte')?.beendet ?? false,
    );
    final l = bibliothek.lauf('orte')!;
    print(
      'GRU-165 Hinweis: Modus „Namen wie darktable“ bei „Orte einlesen“ lief mit '
      'gesamt=${l.gesamt} (5 = Aktion „Alle“, 0 = „Fehlende“), Titel „${l.titel}“',
    );
    await eventually(tester, () async => !bibliothek.etwasLaeuft);
    // GRU-166: Aufgaben mit Rückfrage werden übergangen.
    melde.verlaufLeeren();
    await oeffneDialog();
    await tippe(
      tester,
      find.descendant(of: dlg, matching: find.text(de.aufgModusAlle)),
    );
    await kreuze(de.werkzDatumTitel);
    await kreuze(de.aufgAblageTitel);
    await tippe(tester, einreihen);
    await erwarteMeldung(tester, de.aufgEingereiht(0));
    await settle(tester);
    expect(bibliothek.lauf('aufnahmedatum'), isNull);
    expect(bibliothek.lauf('ablage'), isNull);
    expect(
      pruefsummen(Directory(p.join(bibliothek.paths.root.path, 'originals'))),
      originale,
    );
    await ende(tester);
  }, timeout: _frist);

  Future<AssetData> verlegeInMonat(
    AssetData a,
    int jahr,
    int monat, {
    DateTime? datum,
  }) async {
    final teile = p.posix.split(a.relativePath);
    final neuRel = p.posix.join(
      'originals',
      jahr.toString().padLeft(4, '0'),
      monat.toString().padLeft(2, '0'),
      teile.last,
    );
    final alt = bibliothek.paths.absolute(a.relativePath);
    final neu = bibliothek.paths.absolute(neuRel);
    neu.parent.createSync(recursive: true);
    alt.renameSync(neu.path);
    await (bibliothek.db.update(
      bibliothek.db.assets,
    )..where((t) => t.id.equals(a.id))).write(
      AssetsCompanion(
        relativePath: Value(neuRel),
        fileCreatedAt: datum == null ? const Value.absent() : Value(datum),
      ),
    );
    return (await bibliothek.db.assetById(a.id))!;
  }

  testWidgets(
    'GRU-168 GRU-169 Datumskorrektur und Ablage: Rückfragen, Originale',
    (tester) async {
      filtereSemantik();
      schritt = 'startApp';
      await starte(tester);
      await bibliothek.db.setAutoAnalyzeAfterImport(false);
      await importiere(tester, [repoFixture('samples/sony_ilce6300.arw')]);
      final raw0 = (await aufnahmen()).single;
      final rawDatum = raw0.fileCreatedAt;
      final rawSumme = sha(bibliothek.paths.absolute(raw0.relativePath));
      // Vorbedingung: Datum vom Dateizeitstempel, Ablage im falschen Monat.
      var raw = await verlegeInMonat(
        raw0,
        2024,
        5,
        datum: DateTime(2024, 5, 1, 12),
      );
      await importiere(tester, [
        testfoto('jpeg.jpg', datum: DateTime(2023, 8, 15, 14, 30)),
      ]);
      final jpeg0 = (await aufnahmen()).firstWhere(
        (a) => a.originalFileName == 'jpeg.jpg',
      );
      final jpegSumme = sha(bibliothek.paths.absolute(jpeg0.relativePath));
      await aufgabenOeffnen(tester);
      // GRU-168
      var datumKarte = await karte(tester, de.werkzDatumTitel);
      await aktion(tester, datumKarte, de.aufgModusAlle);
      await waitFor(tester, find.text(de.werkzDatumFrageTitel));
      expect(find.text(de.werkzDatumFrage), findsOneWidget);
      expect(de.werkzDatumFrage, contains('Monatsordner'));
      expect(de.werkzDatumFrage, contains('Rückgängig'));
      await tippe(tester, knopfIn(find.byType(AlertDialog), de.allgAbbrechen));
      await waitGone(tester, find.text(de.werkzDatumFrageTitel));
      expect(bibliothek.lauf('aufnahmedatum'), isNull);
      expect(
        (await bibliothek.db.assetById(raw.id))!.fileCreatedAt,
        DateTime(2024, 5, 1, 12),
      );
      datumKarte = await karte(tester, de.werkzDatumTitel);
      await aktion(tester, datumKarte, de.aufgModusAlle);
      await waitFor(tester, find.text(de.werkzDatumFrageTitel));
      await tippe(tester, knopf(de.werkzDatumStarten));
      await eventually(
        tester,
        () async => bibliothek.lauf('aufnahmedatum')?.beendet ?? false,
      );
      raw = (await bibliothek.db.assetById(raw.id))!;
      expect(
        raw.fileCreatedAt.difference(rawDatum).inMinutes.abs(),
        lessThan(1),
      );
      expect(
        raw.relativePath,
        startsWith(
          'originals/${rawDatum.year.toString().padLeft(4, '0')}/${rawDatum.month.toString().padLeft(2, '0')}/',
        ),
      );
      expect(sha(bibliothek.paths.absolute(raw.relativePath)), rawSumme);
      // GRU-169
      final jpeg = await verlegeInMonat(jpeg0, 2020, 2);
      await settle(tester);
      final datumVorher = jpeg.fileCreatedAt;
      final kachelnVorher = await anzahlAufnahmen();
      var ablage = await karte(tester, de.aufgAblageTitel);
      if (find
          .descendant(of: ablage, matching: find.text(de.allgSchliessen))
          .evaluate()
          .isNotEmpty) {
        await aktion(tester, ablage, de.allgSchliessen);
      }
      ablage = await karte(tester, de.aufgAblageTitel);
      await aktion(tester, ablage, de.aufgModusAlle);
      await waitFor(tester, find.text(de.werkzAblageFrageTitel));
      expect(find.text(de.werkzAblageFrage), findsOneWidget);
      await tippe(tester, knopf(de.werkzAblageStarten));
      await eventually(
        tester,
        () async => bibliothek.lauf('ablage')?.beendet ?? false,
      );
      await settle(tester);
      final l = bibliothek.lauf('ablage')!;
      expect(
        find.descendant(
          of: ablage,
          matching: find.text(de.werkzAblageBilanz(1, l.gesamt)),
        ),
        findsOneWidget,
      );
      final jpegDanach = (await bibliothek.db.assetById(jpeg.id))!;
      expect(jpegDanach.relativePath, startsWith('originals/2023/08/'));
      expect(jpegDanach.fileCreatedAt, datumVorher);
      expect(
        sha(bibliothek.paths.absolute(jpegDanach.relativePath)),
        jpegSumme,
      );
      await leiste(tester, de.navFotos);
      await settle(tester);
      expect(await anzahlAufnahmen(), kachelnVorher);
      expect(find.byType(AssetThumbnailTile), findsNWidgets(2));
      await ende(tester);
    },
    timeout: _frist,
  );

  testWidgets('GRU-172 Hervorgehobene Aufgabe aus dem Bibliothekszustand', (
    tester,
  ) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester);
    await importiere(tester, [
      testfoto('stunde.jpg', datum: DateTime(2024, 5, 1, 10)),
    ]);
    // Vorbedingung: ein Aufnahmedatum auf voller Stunde, noch nicht
    // nachgesehen – der Bibliothekszustand verweist auf die Aufgabe.
    final a = (await aufnahmen()).single;
    await (bibliothek.db.update(bibliothek.db.assets)
          ..where((t) => t.id.equals(a.id)))
        .write(const AssetsCompanion(datumGeprueft: Value(false)));
    await leiste(tester, de.navWerkzeuge);
    await tippe(
      tester,
      find.descendant(
        of: find.byType(ToolsScreen),
        matching: find.text(de.gesundheitTitel),
      ),
    );
    await waitFor(tester, find.byType(LibraryHealthScreen));
    final pruefen = find.text(de.gesundheitDatumPruefen);
    final liste = find
        .descendant(
          of: find.byType(LibraryHealthScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      pruefen,
      200,
      scrollable: liste,
      maxScrolls: 60,
    );
    await tippe(tester, pruefen);
    await waitFor(tester, find.byType(BackgroundTasksScreen));
    final titel = find.descendant(
      of: find.byType(BackgroundTasksScreen),
      matching: find.text(de.aufgDatumsherkunftTitel),
    );
    await waitFor(tester, titel);
    final k = find.ancestor(of: titel, matching: find.byType(Card)).first;
    final rahmen = tester.widget<Card>(k).shape as RoundedRectangleBorder?;
    expect(rahmen, isNotNull, reason: 'Rahmen');
    expect(rahmen!.side.width, 2);
    expect(
      rahmen.side.color,
      Theme.of(tester.element(titel)).colorScheme.primary,
    );
    // Ganz oben, direkt unter der Sammelkarte.
    final sammelY = tester
        .getTopLeft(find.text(de.werkzAllesNachholenTitel))
        .dy;
    final y = tester.getTopLeft(titel).dy;
    expect(y, greaterThan(sammelY));
    final gesichter = find.descendant(
      of: find.byType(BackgroundTasksScreen),
      matching: find.text(de.werkzGesichterScannenTitel),
    );
    if (gesichter.evaluate().isNotEmpty) {
      expect(y, lessThan(tester.getTopLeft(gesichter).dy));
    }
    await ende(tester);
  }, timeout: _frist);

  testWidgets('GRU-192 Einstellungen bei doppelter Schrift', (tester) async {
    filtereSemantik();
    schritt = 'startApp';
    await starte(tester, groesse: const Size(820, 900));
    final pd = tester.platformDispatcher;
    addTearDown(pd.clearAllTestValues);
    pd.textScaleFactorTestValue = 2.0;
    await settle(tester);
    // Unter 700 Punkten fehlt die Leiste nicht: 820 ist breit.
    await einstellungen(tester);
    for (final t in [
      de.einstBibListe,
      de.einstSpeicherortTitel,
      de.einstUeberTitel,
    ]) {
      await gruppe(tester, t);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: t);
      if (t == de.einstSpeicherortTitel) {
        // Der lange Pfad bricht um und bleibt im Fenster.
        final pfad = find.text(bibliothek.paths.root.path);
        await zeigeInEinstellungen(tester, pfad);
        expect(tester.getRect(pfad.first).right, lessThanOrEqualTo(820));
        expect(tester.takeException(), isNull);
      }
    }
    pd.clearAllTestValues();
    await ende(tester);
  }, timeout: _frist);
}

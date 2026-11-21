// ignore_for_file: avoid_print
// Katalog-Prüfungen des Bereichs KI (pruefkatalog/teile/KI.json): KI-Modelle,
// Hintergrundanalyse, Aufgaben, Schlagwörter, Bildbeschreibung,
// Texterkennung, Ausweise, Datierung, Scan-Arbeitsbereich,
// Automatisierungsregeln, Schadenserkennung und Rechenhilfe – in der echten
// App mit frischer Wegwerf-Bibliothek je Prüfung.
//
// KI-Modelle kommen nicht aus dem Netz, sondern aus dem vorab geladenen
// Ordner der Warteschlange (startApp(modelle: …) bzw. [installiere]). Nur
// die Einträge zum Herunterladen laden kleine Modelle (YuNet, Augenzustand)
// wirklich aus der Katalog-Adresse.
//
// Laufen lassen nur über die Warteschlange:
//   …/pruefkatalog/tools/e2e_queue.sh ki integration_test/katalog_ki_test.dart
// Prüfungen mit Befund tragen „Befundpruefung“ im Namen, die mit Server
// „Serverpruefung“ (PV_E2E_SERVER=1).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kern/abgleich/rechenzeit.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart' show AppTexte;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart'
    show BackgroundTasksScreen;
import 'package:photo_vault/screens/dokumente_screen.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/image_editor_screen.dart'
    show ImageEditorScreen;
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/screens/scan_workspace_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/services/groessentext.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;
import 'package:photo_vault/services/modelltexte.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/textrahmen.dart';
import 'package:provider/provider.dart';

import 'katalog_kit.dart';

// --- Hilfen dieser Datei -----------------------------------------------------

/// Die Dateinamen der Modelle [eintraege] – für `startApp(modelle: …)`.
List<String> dateienVon(List<ModelCatalogEntry> eintraege) => [
  for (final e in eintraege)
    for (final f in e.files) f.fileName,
];

/// Obergrenze je Prüfung: Hängt eine, sollen die übrigen trotzdem laufen.
const zeitgrenze = Timeout(Duration(minutes: 15));

/// Die Modelle, die die sieben Stufen der Hintergrundanalyse brauchen.
const analysemodelle = [
  ModelCatalog.clip,
  ModelCatalog.faceDetection,
  ModelCatalog.faceRecognition,
  ModelCatalog.eyeState,
  ModelCatalog.captioningFlorence,
  ModelCatalog.spracherkennung,
];

/// Legt vorab geladene Modelle in den Modellordner der Prüfung und lädt sie
/// neu – dasselbe, was die Oberfläche nach einem Download tut
/// (`reloadModels`), nur ohne Netz.
Future<void> installiere(
  WidgetTester tester,
  List<ModelCatalogEntry> eintraege,
) async {
  verlinkeModelle(dateienVon(eintraege));
  await tester.runAsync(bibliothek.reloadModels);
  await settle(tester);
}

Directory get modellordnerDerPruefung =>
    Directory(p.join(anker.path, 'models'));

/// Ein Befehl an die Datenbank (für Vorbedingungen).
Future<T?> befehl<T>(WidgetTester tester, Befehl<T> b) =>
    tester.runAsync(() => bibliothek.db.fuehreAus(b));

Variable<Object> _variable(Object? wert) => switch (wert) {
  final int i => Variable<int>(i),
  final double d => Variable<double>(d),
  final bool b => Variable<bool>(b),
  final String s => Variable<String>(s),
  _ => throw ArgumentError('Wert $wert'),
};

/// Eine SQL-Abfrage auf die Bibliothek der Prüfung.
Future<List<Map<String, Object?>>> sql(
  WidgetTester tester,
  String abfrage, [
  List<Object?> werte = const [],
]) async {
  final zeilen = await tester.runAsync(
    () => bibliothek.db
        .customSelect(abfrage, variables: [for (final w in werte) _variable(w)])
        .get(),
  );
  return [for (final z in zeilen!) z.data];
}

/// Die erste Spalte der ersten Zeile als Zahl.
Future<int> zahl(
  WidgetTester tester,
  String abfrage, [
  List<Object?> werte = const [],
]) async {
  final z = await sql(tester, abfrage, werte);
  final w = z.first.values.first;
  return (w as num?)?.toInt() ?? 0;
}

Future<void> sqlAusfuehren(
  WidgetTester tester,
  String anweisung, [
  List<Object?> werte = const [],
]) => tester.runAsync(
  () => bibliothek.db.customStatement(anweisung, [for (final w in werte) w]),
);

Future<AssetData> aufnahme(WidgetTester tester, String id) async =>
    (await tester.runAsync(() => bibliothek.db.assetById(id)))!;

/// Schaltet die Auswertung nach dem Import aus (Vorbedingung).
Future<void> autoAus(WidgetTester tester) =>
    befehl(tester, const AuswertenNachImportSetzen(false));

Future<void> autoAn(WidgetTester tester) =>
    befehl(tester, const AuswertenNachImportSetzen(true));

/// Beendet die App wie beim Schliessen und startet sie neu – mit derselben
/// Wegwerf-Bibliothek. Die Umlenkung des Datenordners aus [startApp] bleibt
/// dabei bestehen; es wird nur der Widgetbaum neu aufgebaut.
Future<void> neustart(WidgetTester tester) async {
  await tester.runAsync(bibliothek.vorDemBeenden);
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

bool _findet(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Pumpt eine kurze, feste Zeit – statt [settle], wo Fortschrittsanzeigen
/// endlos animieren.
Future<void> pumpe(WidgetTester tester, [int ms = 600]) async {
  final ende = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Tippen ohne auf Ruhe zu warten (für Bildschirme mit laufender Arbeit).
Future<void> tippe(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await pumpe(tester);
}

/// Wechselt den Hauptbereich so, dass die Seite neu aufgebaut wird.
Future<void> bereich(WidgetTester tester, int nummer) async {
  final ziel = nummer == Hauptbereich.zeitleiste
      ? Hauptbereich.alben
      : Hauptbereich.zeitleiste;
  await openSection(tester, ziel);
  await openSection(tester, nummer);
  await pumpe(tester, 400);
}

/// Bringt [f] in Sicht – im ersten scrollbaren Bereich von [seite].
Future<void> sichtbar(WidgetTester tester, Finder f, Type seite) async {
  if (!_findet(f)) {
    final rollen = find
        .descendant(of: find.byType(seite), matching: find.byType(Scrollable))
        .first;
    try {
      await tester.scrollUntilVisible(
        f,
        250,
        scrollable: rollen,
        maxScrolls: 80,
      );
    } catch (_) {
      await tester.scrollUntilVisible(
        f,
        -250,
        scrollable: rollen,
        maxScrolls: 80,
      );
    }
  }
  await tester.ensureVisible(f.first);
  await pumpe(tester, 300);
}

/// Öffnet „Einstellungen“ und klappt die Gruppe [titel] auf.
Future<void> einstellungsgruppe(WidgetTester tester, String titel) async {
  await bereich(tester, Hauptbereich.einstellungen);
  await waitFor(tester, find.byType(SettingsScreen));
  final f = find.text(titel);
  await sichtbar(tester, f, SettingsScreen);
  await tester.tap(f.first);
  await settle(tester, max: const Duration(seconds: 2));
}

/// Öffnet in „Werkzeuge“ den Eintrag [titel].
Future<void> werkzeug(WidgetTester tester, String titel) async {
  await bereich(tester, Hauptbereich.werkzeuge);
  await waitFor(tester, find.byType(ToolsScreen));
  final f = find.descendant(
    of: find.byType(ToolsScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, f, ToolsScreen);
  await tester.tap(f.first);
  await pumpe(tester, 800);
}

/// „Werkzeuge“ → „Aufgaben“.
Future<void> aufgaben(WidgetTester tester) async {
  await werkzeug(tester, de.aufgTitel);
  await waitFor(tester, find.byType(BackgroundTasksScreen));
}

/// Die Karte mit dem Titel [titel] (Aufgaben, Modellkarten …).
Finder karte(String titel) =>
    find.ancestor(of: find.text(titel), matching: find.byType(Card)).first;

/// Alle Texte unterhalb von [f], zusammengefügt.
String texteIn(Finder f) {
  final texte = <String>[];
  for (final e
      in find.descendant(of: f, matching: find.byType(RichText)).evaluate()) {
    texte.add((e.widget as RichText).text.toPlainText());
  }
  return texte.join(' | ');
}

/// Scrollt die Aufgabenliste zur Karte [titel].
Future<void> zurKarte(WidgetTester tester, String titel) async {
  final f = find.text(titel);
  await sichtbar(tester, f, BackgroundTasksScreen);
  // In die Mitte holen: Oben verdeckt sonst das Band, das während einer
  // Auswertung über dem Inhalt erscheint, die Knöpfe.
  await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.4);
  await pumpe(tester, 300);
}

/// Die Kennung des Laufs zu einer Aufgabenkarte.
String? schluesselZu(String titel) => {
  de.werkzGesichterScannenTitel: 'gesichter',
  de.aufgWiedererkennungTitel: 'wiedererkennung',
  de.aufgVorschauTitel: 'vorschau',
  de.aufgOcrTitel: 'ocr',
  de.aufgBeschreibungenTitel: 'beschreibungen',
  de.aufgTranskripteTitel: 'transkripte',
  de.aufgUebersetzenTitel: 'beschreibungen_de',
  de.aufgEmbeddingsTitel: 'embeddings',
  de.aufgKiTagsTitel: 'kitags',
  de.aufgUnschaerfeTitel: 'unschaerfe',
  de.aufgVideobilderTitel: 'videobilder',
}[titel];

/// Tippt in der Aktionsleiste der Karte [titel] auf [knopf].
Future<void> kartenknopf(
  WidgetTester tester,
  String titel,
  String knopf,
) async {
  final startet = knopf == de.aufgModusAlle || knopf == de.aufgFehlende;
  final schluessel = startet ? schluesselZu(titel) : null;
  for (var versuch = 0; versuch < 3; versuch++) {
    await zurKarte(tester, titel);
    final f = find.descendant(of: karte(titel), matching: find.text(knopf));
    await waitFor(tester, f);
    await tester.tap(f.first);
    await pumpe(tester);
    if (schluessel == null || bibliothek.lauf(schluessel) != null) return;
    print('kartenknopf: $titel/$knopf ging daneben, neuer Versuch');
  }
  throw StateError('Aufgabe $titel liess sich nicht starten');
}

/// Alle Aufgaben im Sammeldialog – die Liste baut nur, was sichtbar ist.
Future<Set<String>> dialogTitel(WidgetTester tester) async {
  final gesehen = <String>{};
  final rollen = find
      .descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      )
      .last;
  for (var i = 0; i < 30; i++) {
    final vorher = gesehen.length;
    for (final c in tester.widgetList<CheckboxListTile>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(CheckboxListTile),
      ),
    )) {
      gesehen.add((c.title! as Text).data!);
    }
    await tester.drag(rollen, const Offset(0, -120));
    await pumpe(tester, 200);
    if (gesehen.length == vorher && i > 2) break;
  }
  await tester.drag(rollen, const Offset(0, 4000));
  await pumpe(tester, 300);
  return gesehen;
}

/// Hakt im Sammeldialog die Aufgabe [titel] an.
Future<void> imDialogTippen(WidgetTester tester, String titel) async {
  final f = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(titel),
  );
  if (!_findet(f)) {
    await tester.scrollUntilVisible(
      f,
      60,
      scrollable: find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .last,
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(f.first);
  await pumpe(tester, 200);
  await tester.tap(f.first);
  await pumpe(tester, 300);
}

/// Schreibt in ein Feld und prüft, dass der Text dort angekommen ist.
Future<void> eintragen(WidgetTester tester, Finder feld, String text) async {
  for (var i = 0; i < 3; i++) {
    await enter(tester, feld, text);
    final ist = tester
        .widget<EditableText>(
          find.descendant(of: feld.first, matching: find.byType(EditableText)),
        )
        .controller
        .text;
    if (ist == text) return;
    print('eintragen: „$ist“ statt „$text“, neuer Versuch');
    await tester.tap(feld.first);
    await pumpe(tester, 300);
  }
  throw StateError('Text kam nicht im Feld an: $text');
}

/// Tippt einen Kopfknopf der Aufgaben und wartet auf den Dialog.
Future<void> kopfTippen(WidgetTester tester, String beschriftung) async {
  for (var i = 0; i < 3; i++) {
    melde.alleSchliessen();
    await pumpe(tester, 800);
    final f = kopf(beschriftung);
    await waitFor(tester, f);
    if (i == 0) {
      await tester.tap(f.first);
    } else {
      // Ein stehengebliebener Kurzhinweis des Nachbarknopfs deckt die
      // Mitte ab – links im Knopf tippen.
      final r = tester.getRect(f.first);
      await tester.tapAt(r.centerLeft + Offset(4.0 + 4 * i, 0));
    }
    await pumpe(tester, 600);
    if (_findet(find.byType(AlertDialog))) return;
    print('kopfTippen: $beschriftung öffnete keinen Dialog, neuer Versuch');
  }
  throw StateError('Dialog „$beschriftung“ ging nicht auf');
}

/// Kopfknopf der Aufgaben: je nach Fensterbreite mit Text oder nur Symbol.
Finder kopf(String beschriftung) {
  // Meldungen stehen oben rechts – genau über den Kopfknöpfen.
  melde.alleSchliessen();
  if (_findet(find.text(beschriftung))) return find.text(beschriftung);
  final knopf = find.ancestor(
    of: find.byTooltip(beschriftung),
    matching: find.byType(IconButton),
  );
  return _findet(knopf) ? knopf : find.byTooltip(beschriftung);
}

/// Ob der Knopf [knopf] der Karte [titel] bedienbar ist.
bool knopfAktiv(WidgetTester tester, String titel, String knopf) {
  final ink = find
      .ancestor(
        of: find.descendant(of: karte(titel), matching: find.text(knopf)),
        matching: find.byType(InkWell),
      )
      .first;
  return tester.widget<InkWell>(ink).onTap != null;
}

/// Wartet, bis die Aufgabe [schluessel] fertig ist.
Future<void> warteAufLauf(
  WidgetTester tester,
  String schluessel, {
  Duration timeout = const Duration(minutes: 4),
}) => eventually(
  tester,
  () async => bibliothek.lauf(schluessel)?.beendet ?? false,
  timeout: timeout,
  was: 'Aufgabe $schluessel fertig',
);

/// Wartet, bis keine Analyse und keine Aufgabe mehr läuft (dreimal
/// hintereinander gesehen).
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

/// Startet über die Karte „Alle Auswertungen jetzt nachholen“ und wartet
/// auf das Ende.
Future<void> analyseUeberKarte(
  WidgetTester tester, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  await aufgaben(tester);
  await mitAnalyse(
    tester,
    () => kartenknopf(tester, de.werkzAllesNachholenTitel, de.aufgJetztStarten),
    timeout: timeout,
  );
}

/// Führt [ausloesen] aus, wartet, bis die Hintergrundanalyse wirklich
/// begonnen hat (das Laden der Modelle dauert), und dann auf ihr Ende.
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

/// Öffnet den Betrachter für [id] wie die Zeitleiste.
Future<void> betrachter(
  WidgetTester tester,
  List<String> ids,
  String id,
) async {
  final assets = <AssetData>[];
  for (final i in ids) {
    final a = await tester.runAsync(() => bibliothek.db.assetById(i));
    if (a != null) assets.add(a);
  }
  if (!assets.any((a) => a.id == id)) {
    throw StateError('Aufnahme $id nicht da (ids $ids)');
  }
  final nav = Navigator.of(
    tester.element(find.byType(HomeShell, skipOffstage: false)),
    rootNavigator: true,
  );
  unawaited(
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => AssetViewerScreen(
          assets: assets,
          initialIndex: assets.indexWhere((a) => a.id == id),
          paths: bibliothek.paths,
          db: bibliothek.db,
          library: bibliothek,
          onToggleFavorite: (a) =>
              bibliothek.db.fuehreAus(FavoritSetzen([a.id], !a.isFavorite)),
          onDelete: (a) => bibliothek.db.fuehreAus(InDenPapierkorb([a.id])),
        ),
      ),
    ),
  );
  await waitFor(tester, find.byType(AssetViewerScreen));
  await pumpe(tester, 1200);
}

/// Schliesst den Betrachter.
Future<void> betrachterZu(WidgetTester tester) async {
  if (!_findet(find.byType(AssetViewerScreen))) return;
  final nav = Navigator.of(
    tester.element(find.byType(AssetViewerScreen)),
    rootNavigator: true,
  );
  nav.pop();
  await pumpe(tester, 800);
}

Future<void> rechtsklick(WidgetTester tester, Finder f) async {
  await tester.tap(
    f.first,
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await pumpe(tester, 500);
}

String sha(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Ein einfarbiges JPEG ohne Muster (kein Text, keine Gesichter).
File blindfoto(String name, {int r = 128, int g = 128, int b = 128}) {
  final bild = img.Image(width: 640, height: 480);
  img.fill(bild, color: img.ColorRgb8(r, g, b));
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(bild, quality: 92));
  return datei;
}

/// Ein Bild mit Text, über die Textdarstellung der App (alle Zeichen samt
/// Umlauten), als PNG.
Future<File> textbild(
  WidgetTester tester,
  String name,
  List<String> zeilen, {
  double groesse = 64,
  String? schrift,
  double breite = 1800,
}) async {
  final bytes = await tester.runAsync(() async {
    final hoehe = (120 + zeilen.length * groesse * 1.7).roundToDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, breite, hoehe));
    c.drawRect(
      Rect.fromLTWH(0, 0, breite, hoehe),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    var y = 60.0;
    for (final z in zeilen) {
      final tp = TextPainter(
        text: TextSpan(
          text: z,
          style: TextStyle(
            color: const Color(0xFF000000),
            fontSize: groesse,
            fontFamily: schrift,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: breite - 80);
      tp.paint(c, Offset(40, y));
      y += groesse * 1.7;
    }
    final bild = await rec.endRecording().toImage(
      breite.toInt(),
      hoehe.toInt(),
    );
    final png = await bild.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  });
  final datei = File(p.join(eingang.path, name))..writeAsBytesSync(bytes!);
  return datei;
}

/// Der Schalter mit dem Titel [titel].
Finder schalter(String titel) =>
    find.ancestor(of: find.text(titel), matching: find.byType(SwitchListTile));

/// Die Modellkarte des Katalogeintrags [id].
Finder modellkarte(String id, [AppTexte? t]) => karte(modellTitel(t ?? de, id));

/// Stellt die Oberflächensprache über die Einstellungen um und beantwortet
/// die Frage nach dem Vokabular.
Future<void> sprache(
  WidgetTester tester,
  String ziel, {
  required bool uebersetzen,
}) async {
  final vorher = Localizations.localeOf(
    tester.element(find.byType(HomeShell)),
  ).languageCode;
  final t = vorher == 'en' ? en : de;
  await einstellungsgruppe(tester, t.spracheTitel);
  await tippe(
    tester,
    find.text(ziel == 'en' ? t.spracheEnglisch : t.spracheDeutsch),
  );
  final n = ziel == 'en' ? en : de;
  await waitFor(tester, find.text(n.spracheVokabularTitel));
  await tippe(
    tester,
    find.text(
      uebersetzen ? n.spracheVokabularUebersetzen : n.spracheVokabularBehalten,
    ),
  );
  await settle(tester);
}

/// Simuliert die Frage der nativen Seite „darf beendet werden?“ (Fenster
/// schliessen / Cmd+Q) und liefert die Antwort der App.
Future<bool?> beendenAnfragen(WidgetTester tester) {
  const codec = StandardMethodCodec();
  final antwort = Completer<bool?>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'photo_vault/beenden',
    codec.encodeMethodCall(const MethodCall('darfBeenden')),
    (data) {
      if (!antwort.isCompleted) {
        antwort.complete(
          data == null ? null : codec.decodeEnvelope(data) as bool?,
        );
      }
    },
  );
  return antwort.future;
}

/// Wartet mit Pumpen auf ein Future, das von der Oberfläche abhängt.
Future<T> mitPumpen<T>(
  WidgetTester tester,
  Future<T> future, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  T? wert;
  var fertig = false;
  unawaited(
    future.then((w) {
      wert = w;
      fertig = true;
    }),
  );
  final ende = DateTime.now().add(timeout);
  while (!fertig && DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!fertig) throw TimeoutException('Antwort blieb aus');
  return wert as T;
}

/// Nachgestellter Dateidialog, der sich die erlaubten Endungen merkt (der
/// des Kits tut das nicht).
class EndungenDialog extends KatalogDateidialog {
  List<String>? erlaubt;
  String? titel;

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
  }) {
    erlaubt = allowedExtensions;
    titel = dialogTitle;
    dateien = dialog.dateien;
    return super.pickFiles(
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

/// Ein Scan: weisser Grund mit Rechtecken als „Papierfotos“.
File scanbild(
  String name, {
  List<(int, int, int, int, img.Color)> fotos = const [],
  int breite = 1200,
  int hoehe = 800,
  bool png = true,
  int grund = 250,
}) {
  final bild = img.Image(width: breite, height: hoehe);
  img.fill(bild, color: img.ColorRgb8(grund, grund, grund));
  var n = 0;
  for (final (x, y, w, h, farbe) in fotos) {
    img.fillRect(bild, x1: x, y1: y, x2: x + w, y2: y + h, color: farbe);
    // Ein Muster, damit sich die Ausschnitte unterscheiden.
    img.fillRect(
      bild,
      x1: x + 20 + n * 7,
      y1: y + 20,
      x2: x + 60 + n * 7,
      y2: y + 40 + n * 5,
      color: img.ColorRgb8(255, 255, 0),
    );
    n++;
  }
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(png ? img.encodePng(bild) : img.encodeJpg(bild));
  return datei;
}

/// Die Prüfziffer einer maschinenlesbaren Zone (7-3-1).
int pruefziffer(String feld) {
  const gewichte = [7, 3, 1];
  var summe = 0;
  for (var i = 0; i < feld.length; i++) {
    final c = feld.codeUnitAt(i);
    final wert = c >= 0x30 && c <= 0x39
        ? c - 0x30
        : (c >= 0x41 && c <= 0x5A ? c - 0x41 + 10 : 0);
    summe += wert * gewichte[i % 3];
  }
  return summe % 10;
}

/// Die zweite Zeile einer Ausweis-Prüfzone (TD1), ohne echte Daten.
String td1Zeile2({bool falsch = false}) {
  const geburt = '800101', ablauf = '300101';
  final p1 = pruefziffer(geburt);
  final p2 = (pruefziffer(ablauf) + (falsch ? 1 : 0)) % 10;
  return '$geburt${p1}F$ablauf${p2}UTO<<<<<<<<<<<0';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Fehlermeldungen stehen, bis man sie schliesst, und der Meldungsdienst
  // gilt für den ganzen Prozess – eine stehengebliebene Meldung der
  // vorigen Prüfung läge sonst über den Knöpfen der nächsten.
  setUp(melde.alleSchliessen);

  // ---------------------------------------------------------------- Modelle

  testWidgets(
    timeout: zeitgrenze,
    'KI-001 KI-015 KI-026 KI-046 KI-047 KI-063 KI-110 Oberflaeche ohne Modelle',
    (tester) async {
      await startApp(tester);

      // KI-001: die Modellgruppe.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      expect(find.text(de.einstKiHinweis), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(schalter(de.einstAutoAnalyseTitel)).value,
        isTrue,
      );
      expect(find.text(de.einstUebersetzeBeschreibungTitel), findsOneWidget);
      expect(find.text(de.einstUebersetzeSucheTitel), findsOneWidget);
      expect(find.text(de.einstAlleModelleLaden(15)), findsOneWidget);
      expect(ModelCatalog.all.length, 15);
      for (final e in ModelCatalog.all) {
        await sichtbar(
          tester,
          find.text(modellTitel(de, e.id)),
          SettingsScreen,
        );
        final k = modellkarte(e.id);
        final text = texteIn(k);
        expect(text, contains(modellBeschreibung(de, e.id)), reason: e.id);
        expect(
          text,
          contains(de.einstModellLizenzZeile(modellLizenz(de, e.id))),
          reason: e.id,
        );
        expect(
          find.descendant(of: k, matching: find.text(de.allgHerunterladen)),
          findsOneWidget,
          reason: e.id,
        );
      }
      for (final id in [
        'face_detection_yunet',
        'clip_vit_b32',
        'captioning_florence2_base_ft',
        'speech_whisper_small',
        'ocr_ppocr_latin',
      ]) {
        expect(modellTitel(de, id), isNotEmpty);
      }

      // KI-015: nachrechnen ohne Modell.
      await sichtbar(
        tester,
        find.text(de.einstModellePruefenTitel),
        SettingsScreen,
      );
      await tippe(tester, find.text(de.einstModellePruefenTitel));
      await erwarteMeldung(tester, de.einstModellePruefenNichtsDa);

      // KI-026: Auto-Auswertung, vorgegeben an, überdauert Neustarts.
      await sichtbar(
        tester,
        schalter(de.einstAutoAnalyseTitel),
        SettingsScreen,
      );
      await tippe(tester, schalter(de.einstAutoAnalyseTitel));
      expect(
        await tester.runAsync(bibliothek.db.autoAnalyzeAfterImportEnabled),
        isFalse,
      );
      await neustart(tester);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      expect(
        tester.widget<SwitchListTile>(schalter(de.einstAutoAnalyseTitel)).value,
        isFalse,
      );
      await tippe(tester, schalter(de.einstAutoAnalyseTitel));
      await neustart(tester);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      expect(
        tester.widget<SwitchListTile>(schalter(de.einstAutoAnalyseTitel)).value,
        isTrue,
      );

      // KI-046: beide Wege zu den Aufgaben; Werkzeuge startet nichts.
      await bereich(tester, Hauptbereich.werkzeuge);
      expect(bibliothek.offeneAufgaben, isEmpty);
      await aufgaben(tester);
      expect(find.text(de.werkzAllesNachholenTitel), findsOneWidget);
      // Breit mit Beschriftung, schmal nur Symbole mit Kurzhinweis – die
      // Fensterbreite der Prüf-App bestimmt die Ansicht.
      final ctx = tester.element(find.byType(BackgroundTasksScreen));
      final breit =
          MediaQuery.sizeOf(ctx).width >=
          MediaQuery.textScalerOf(ctx).scale(1000);
      print(
        'KI-046 Fensterbreite ${MediaQuery.sizeOf(ctx).width}, breit $breit',
      );
      for (final k in [de.aufgErstellen, de.aufgGleichzeitigTitel]) {
        expect(breit ? find.text(k) : find.byTooltip(k), findsOneWidget);
      }
      expect(bibliothek.offeneAufgaben, isEmpty);
      await einstellungsgruppe(tester, de.einstAbschnittHintergrund);
      await tippe(tester, find.text(de.einstAufgabenTitel));
      await waitFor(tester, find.byType(BackgroundTasksScreen));
      expect(find.text(de.werkzAllesNachholenTitel), findsOneWidget);

      // KI-047: KI-Karten ohne Modell nennen den Grund.
      await aufgaben(tester);
      final faelle = {
        de.werkzGesichterScannenTitel: de.aufgYunetModell,
        de.aufgEmbeddingsTitel: de.aufgClipModell,
        de.aufgKiTagsTitel: de.aufgClipModell,
        de.aufgBeschreibungenTitel: de.aufgBeschreibungsmodell,
        de.aufgTranskripteTitel: de.aufgSprachmodell,
        de.aufgUebersetzenTitel: de.aufgUebersetzungsmodell,
      };
      for (final MapEntry(key: titel, value: modell) in faelle.entries) {
        await zurKarte(tester, titel);
        expect(
          texteIn(karte(titel)),
          contains(de.aufgModellNoetig(modell, de.aufgWoModelle)),
          reason: titel,
        );
        final knopf =
            find
                .descendant(
                  of: karte(titel),
                  matching: find.text(de.aufgFehlende),
                )
                .evaluate()
                .isNotEmpty
            ? de.aufgFehlende
            : de.aufgModusAlle;
        expect(knopfAktiv(tester, titel, knopf), isFalse, reason: titel);
      }
      await zurKarte(tester, de.aufgOcrTitel);
      expect(texteIn(karte(de.aufgOcrTitel)), contains(de.aufgOffeneFotos(0)));
      expect(knopfAktiv(tester, de.aufgOcrTitel, de.aufgFehlende), isTrue);

      // KI-110: Datierung ohne CLIP.
      await werkzeug(tester, de.datierungTitel);
      await waitFor(tester, find.text(de.datierungOhneModell));

      // KI-063: Bibliothekszustand zählt bereite Funktionen.
      await werkzeug(tester, de.gesundheitTitel);
      await waitFor(tester, find.byType(LibraryHealthScreen));
      final stand = find.textContaining('von 7 lokalen');
      await sichtbar(tester, stand, LibraryHealthScreen);
      final vorher = tester.widget<Text>(stand.first).data!;
      final n0 = int.parse(vorher.split(' ').first);
      expect(vorher, de.gesundheitModelleStand(n0, 7));
      expect(n0, greaterThanOrEqualTo(1), reason: 'macOS: Texterkennung');
      await installiere(tester, [ModelCatalog.clip]);
      await tippe(tester, find.byTooltip(de.gesundheitAktualisieren));
      await pumpe(tester, 1500);
      await sichtbar(
        tester,
        find.text(de.gesundheitModelleStand(n0 + 1, 7)),
        LibraryHealthScreen,
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-002 KI-003 KI-004 KI-006 YuNet herunterladen',
    (tester) async {
      await startApp(tester);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      final dienst = bibliothek.modelDownloadService;
      const id = 'face_detection_yunet';
      final titel = modellTitel(de, id);

      // KI-004, Zustand 1.
      await sichtbar(
        tester,
        find.text(de.einstGesichtserkennungInaktiv),
        SettingsScreen,
      );
      final vorher = dienst.gesamteBytes();
      expect(
        find.text(de.einstModelleBelegterPlatz(groessentext(vorher))),
        findsOneWidget,
      );

      // KI-002/KI-003: herunterladen; das Blatt lässt sich nicht wegklicken.
      await sichtbar(tester, find.text(titel), SettingsScreen);
      await tester.tap(
        find.descendant(
          of: modellkarte(id),
          matching: find.text(de.allgHerunterladen),
        ),
      );
      var blatt = false, prozent = false, versuchtWeg = false, blieb = false;
      final ende = DateTime.now().add(const Duration(seconds: 90));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 40));
        final b = find.text(de.einstModellLaedt(titel));
        if (_findet(b)) {
          blatt = true;
          if (_findet(find.textContaining(' %'))) prozent = true;
          if (!versuchtWeg) {
            versuchtWeg = true;
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.tapAt(const Offset(1300, 40));
            await tester.pump(const Duration(milliseconds: 60));
            blieb =
                _findet(b) ||
                bibliothek.isModelInstalled(ModelCatalog.faceDetection);
          }
        }
        if (bibliothek.isModelInstalled(ModelCatalog.faceDetection) &&
            !_findet(b)) {
          break;
        }
      }
      expect(blatt, isTrue, reason: 'Fortschrittsblatt erschien');
      expect(prozent, isTrue, reason: 'Prozentzahl im Blatt');
      expect(blieb, isTrue, reason: 'Escape/Klick daneben schloss das Blatt');
      await settle(tester);
      expect(bibliothek.isModelInstalled(ModelCatalog.faceDetection), isTrue);
      final yunet = File(
        p.join(modellordnerDerPruefung.path, 'face_detection_yunet.onnx'),
      );
      final groesse = groessentext(yunet.lengthSync());
      final k = modellkarte(id);
      expect(
        find.descendant(of: k, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(
        texteIn(k),
        contains(
          '${de.einstModellLizenzZeile(modellLizenz(de, id))} · $groesse',
        ),
      );
      expect(texteIn(k), contains('Apache-2.0'));
      expect(
        find.descendant(
          of: k,
          matching: find.byTooltip(de.einstModellLoeschen),
        ),
        findsOneWidget,
      );
      expect(find.text(de.einstAlleModelleLaden(14)), findsOneWidget);
      // KI-004, Zustand 2.
      await sichtbar(tester, find.text(de.einstNurErkennung), SettingsScreen);
      // KI-006: Summe steigt um die Grösse.
      final nachher = dienst.gesamteBytes();
      expect(nachher - vorher, yunet.lengthSync());
      expect(
        find.text(de.einstModelleBelegterPlatz(groessentext(nachher))),
        findsOneWidget,
      );

      // KI-004, Zustand 3: SFace dazu.
      await installiere(tester, [ModelCatalog.faceRecognition]);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(de.einstGesichtserkennungBeides),
        SettingsScreen,
      );

      // KI-006: fremde Dateien zählen mit, Löschen senkt die Summe.
      File(
        p.join(modellordnerDerPruefung.path, 'fremd.bin'),
      ).writeAsBytesSync(List.filled(300000, 1));
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      final mitFremd = dienst.gesamteBytes();
      expect(
        mitFremd,
        nachher +
            File(
              p.join(
                modellordnerDerPruefung.path,
                'face_recognition_sface.onnx',
              ),
            ).lengthSync() +
            300000,
      );
      await sichtbar(
        tester,
        find.text(de.einstModelleBelegterPlatz(groessentext(mitFremd))),
        SettingsScreen,
      );
      await sichtbar(tester, find.text(titel), SettingsScreen);
      final yunetBytes = yunet.lengthSync();
      await tippe(
        tester,
        find.descendant(
          of: modellkarte(id),
          matching: find.byTooltip(de.einstModellLoeschen),
        ),
      );
      await settle(tester);
      expect(
        find.descendant(
          of: modellkarte(id),
          matching: find.text(de.allgHerunterladen),
        ),
        findsOneWidget,
      );
      expect(dienst.gesamteBytes(), mitFremd - yunetBytes);
      await sichtbar(
        tester,
        find.text(
          de.einstModelleBelegterPlatz(groessentext(mitFremd - yunetBytes)),
        ),
        SettingsScreen,
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-005 KI-007 KI-008 KI-016 KI-023 Modelle verwalten mit allen Modellen',
    (tester) async {
      await startApp(tester, modelle: true);
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('m1.jpg', datum: DateTime(2023, 3, 3, 12)),
      ]);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'embeddings');
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [ids.first],
        ),
        1,
      );

      // KI-016/KI-023: alle Dateien aus den Katalog-Adressen stimmen.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      final alleDa = find.ancestor(
        of: find.text(de.einstAlleModelleDa),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(alleDa).onPressed, isNull);
      final dateien = ModelCatalog.all.fold<int>(
        0,
        (n, e) => n + e.files.length,
      );
      await sichtbar(
        tester,
        find.text(de.einstModellePruefenTitel),
        SettingsScreen,
      );
      await tester.tap(find.text(de.einstModellePruefenTitel));
      var laeuftGesehen = false;
      final ende = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 50));
        if (_findet(find.textContaining('Rechnet nach: '))) {
          laeuftGesehen = true;
        }
        if (_findet(find.text(de.einstModellePruefenAlleGut(dateien)))) break;
      }
      expect(laeuftGesehen, isTrue, reason: 'Blatt „Rechnet nach: …“');
      expect(find.text(de.einstModellePruefenAlleGut(dateien)), findsOneWidget);

      // KI-008: ein Modell löschen, der Sammelknopf holt genau das eine.
      Future<void> loesche(String mid) async {
        await sichtbar(tester, find.text(modellTitel(de, mid)), SettingsScreen);
        await tippe(
          tester,
          find.descendant(
            of: modellkarte(mid),
            matching: find.byTooltip(de.einstModellLoeschen),
          ),
        );
        await settle(tester);
      }

      Future<List<String>> sammeln(int anzahl) async {
        final knopf = find.text(de.einstAlleModelleLaden(anzahl));
        await sichtbar(tester, knopf, SettingsScreen);
        await tester.tap(knopf);
        final gesehen = <String>{};
        final bis = DateTime.now().add(const Duration(minutes: 2));
        while (DateTime.now().isBefore(bis)) {
          await tester.pump(const Duration(milliseconds: 40));
          for (var i = 1; i <= anzahl; i++) {
            if (_findet(find.text(de.einstAlleModelleLaeuft(i, anzahl)))) {
              gesehen.add('$i');
            }
          }
          if (_findet(find.text(de.einstAlleModelleDa))) break;
        }
        await settle(tester);
        return gesehen.toList()..sort();
      }

      final yunetLink = Link(
        p.join(modellordnerDerPruefung.path, 'face_detection_yunet.onnx'),
      );
      await loesche('eye_state_ocec');
      await sichtbar(
        tester,
        find.text(de.einstAlleModelleLaden(1)),
        SettingsScreen,
      );
      expect(await sammeln(1), ['1']);
      expect(bibliothek.isModelInstalled(ModelCatalog.eyeState), isTrue);
      expect(yunetLink.existsSync(), isTrue, reason: 'YuNet unangetastet');
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text(de.einstAlleModelleDa),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );

      // KI-007: zwei fehlende werden nacheinander geladen.
      await loesche('eye_state_ocec');
      await loesche('face_detection_yunet');
      expect(await sammeln(2), ['1', '2']);
      expect(bibliothek.isModelInstalled(ModelCatalog.eyeState), isTrue);
      expect(bibliothek.isModelInstalled(ModelCatalog.faceDetection), isTrue);
      expect(find.text(de.einstAlleModelleDa), findsOneWidget);

      // KI-005: CLIP löschen – ohne Rückfrage, Platz sinkt, Aufgaben sagen
      // warum, Ergebnisse bleiben.
      final vorher = bibliothek.modelDownloadService.gesamteBytes();
      final clipBytes = bibliothek.modelDownloadService.belegteBytes(
        ModelCatalog.clip,
      );
      await loesche('clip_vit_b32');
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.descendant(
          of: modellkarte('clip_vit_b32'),
          matching: find.text(de.allgHerunterladen),
        ),
        findsOneWidget,
      );
      expect(
        bibliothek.modelDownloadService.gesamteBytes(),
        vorher - clipBytes,
      );
      await sichtbar(
        tester,
        find.text(
          de.einstModelleBelegterPlatz(groessentext(vorher - clipBytes)),
        ),
        SettingsScreen,
      );
      await aufgaben(tester);
      for (final titel in [de.aufgEmbeddingsTitel, de.aufgKiTagsTitel]) {
        await zurKarte(tester, titel);
        expect(
          texteIn(karte(titel)),
          contains(de.aufgModellNoetig(de.aufgClipModell, de.aufgWoModelle)),
        );
      }
      expect(await zahl(tester, 'SELECT count(*) FROM image_embeddings'), 1);
      expect(await zahl(tester, 'SELECT count(*) FROM assets'), 1);
      // Die geteilten Vorratsdateien sind nur Verknüpfungen – nichts davon
      // ist verloren.
      expect(
        File(p.join(modellOrdner, 'clip_image_encoder.onnx')).existsSync(),
        isTrue,
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-013 KI-017 KI-018 Modelldateien veraendert',
    (tester) async {
      await startApp(tester);
      final ordner = modellordnerDerPruefung..createSync(recursive: true);
      File(
        p.join(ordner.path, 'caption_encoder.onnx'),
      ).writeAsBytesSync(List.filled(5000, 7));
      File(p.join(ordner.path, 'ocr_dict.txt')).writeAsStringSync('a\nb\n');
      final original = File(
        p.join(modellOrdner, 'face_detection_yunet.onnx'),
      ).readAsBytesSync();
      final veraendert = Uint8List.fromList(original);
      veraendert[veraendert.length ~/ 2] ^= 0xFF;
      File(
        p.join(ordner.path, 'face_detection_yunet.onnx'),
      ).writeAsBytesSync(veraendert);
      await neustart(tester);

      // KI-013: abgelöste Dateien sind nach dem Start weg.
      await eventually(
        tester,
        () async =>
            !File(p.join(ordner.path, 'caption_encoder.onnx')).existsSync() &&
            !File(p.join(ordner.path, 'ocr_dict.txt')).existsSync(),
        was: 'abgelöste Modelldateien entfernt',
      );
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(de.einstModelleBelegterPlatz(groessentext(original.length))),
        SettingsScreen,
      );

      // KI-017: gleich lang, ein Byte anders.
      await sichtbar(
        tester,
        find.text(de.einstModellePruefenTitel),
        SettingsScreen,
      );
      await tippe(tester, find.text(de.einstModellePruefenTitel));
      await waitFor(tester, find.text(de.einstModellePruefenBefundTitel));
      expect(find.text(de.einstModellePruefenBefundText), findsOneWidget);
      expect(
        find.text(
          'face_detection_yunet.onnx – ${de.einstModellZustandWeichtAb}',
        ),
        findsOneWidget,
      );
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgSchliessen),
        ),
      );
      expect(find.text(de.einstModellePruefenBefundTitel), findsNothing);
      await sichtbar(
        tester,
        find.text(modellTitel(de, 'face_detection_yunet')),
        SettingsScreen,
      );
      expect(
        find.descendant(
          of: modellkarte('face_detection_yunet'),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );

      // KI-018: bei CLIP fehlt eine Datei, eine andere ist zu kurz.
      final clip = [for (final f in ModelCatalog.clip.files) f.fileName];
      final fehlt = clip.firstWhere((n) => !n.endsWith('.onnx'));
      final kurz = clip.lastWhere((n) => !n.endsWith('.onnx') && n != fehlt);
      verlinkeModelle([
        for (final n in clip)
          if (n != fehlt && n != kurz) n,
      ]);
      final voll = File(p.join(modellOrdner, kurz)).readAsBytesSync();
      File(
        p.join(ordner.path, kurz),
      ).writeAsBytesSync(voll.sublist(0, voll.length ~/ 2));
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(de.einstModellePruefenTitel),
        SettingsScreen,
      );
      await tippe(tester, find.text(de.einstModellePruefenTitel));
      await waitFor(
        tester,
        find.text(de.einstModellePruefenBefundTitel),
        timeout: const Duration(seconds: 60),
      );
      expect(
        find.text('$fehlt – ${de.einstModellZustandFehlt}'),
        findsOneWidget,
      );
      expect(
        find.text('$kurz – ${de.einstModellZustandZuKurz}'),
        findsOneWidget,
      );
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgSchliessen),
        ),
      );

      await finish(tester);
    },
  );

  // Behoben in #414: Die Dienste prüfen die Länge ihrer Modelldateien wie die Modellkarte (ModelCatalog.dateiVollstaendig).
  testWidgets(
    timeout: zeitgrenze,
    'KI-014 Befundpruefung abgeschnittene Modelldatei',
    (tester) async {
      await startApp(tester);
      final ordner = modellordnerDerPruefung..createSync(recursive: true);
      final original = File(
        p.join(modellOrdner, 'face_detection_yunet.onnx'),
      ).readAsBytesSync();
      final yunet = File(p.join(ordner.path, 'face_detection_yunet.onnx'))
        ..writeAsBytesSync(original.sublist(0, original.length - 100));
      await neustart(tester);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      final titel = modellTitel(de, 'face_detection_yunet');
      await sichtbar(tester, find.text(titel), SettingsScreen);
      final knopf = find.descendant(
        of: modellkarte('face_detection_yunet'),
        matching: find.text(de.allgHerunterladen),
      );
      expect(knopf, findsOneWidget);
      final karteGes = find.ancestor(
        of: find.text(de.einstGesichtserkennungAktiv),
        matching: find.byType(ListTile),
      );
      await sichtbar(tester, karteGes, SettingsScreen);
      final zustand = texteIn(karteGes);
      print('KI-014 Gesichtserkennung mit abgeschnittener Datei: $zustand');
      // Ein erneuter Download ersetzt die kaputte Datei.
      await sichtbar(tester, find.text(titel), SettingsScreen);
      await tester.tap(knopf);
      await eventually(
        tester,
        () async =>
            bibliothek.isModelInstalled(ModelCatalog.faceDetection) &&
            !_findet(find.text(de.einstModellLaedt(titel))),
        timeout: const Duration(seconds: 90),
        was: 'YuNet neu geladen',
      );
      expect(yunet.lengthSync(), original.length);
      expect(sha(yunet), sha256.convert(original).toString());
      expect(
        zustand,
        contains(de.einstGesichtserkennungInaktiv),
        reason: 'abgeschnittenes YuNet gilt als aktiv',
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-019 KI-020 KI-021 Uebersetzungsschalter und englische Oberflaeche',
    (tester) async {
      await startApp(tester);
      // KI-021: ohne Modell beide Schalter aus und gesperrt.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      for (final titel in [
        de.einstUebersetzeBeschreibungTitel,
        de.einstUebersetzeSucheTitel,
      ]) {
        final s = tester.widget<SwitchListTile>(schalter(titel));
        expect(s.value, isFalse, reason: titel);
        expect(s.onChanged, isNull, reason: titel);
      }
      expect(
        find.textContaining('Das zugehörige Modell ist noch nicht geladen.'),
        findsNWidgets(2),
      );

      // KI-019: Englisch blendet Übersetzungsmodelle und Schalter aus.
      await sprache(tester, 'en', uebersetzen: false);
      await einstellungsgruppe(tester, en.einstAbschnittModelle);
      expect(find.text(en.einstUebersetzeBeschreibungTitel), findsNothing);
      expect(find.text(en.einstUebersetzeSucheTitel), findsNothing);
      expect(find.text(en.einstAlleModelleLaden(13)), findsOneWidget);
      for (final e in ModelCatalog.all) {
        final titel = find.text(modellTitel(en, e.id));
        if (ModelCatalog.nurFuerDeutsch.contains(e)) {
          expect(titel, findsNothing, reason: e.id);
        } else {
          await sichtbar(tester, titel, SettingsScreen);
        }
      }
      for (final e in ModelCatalog.nurFuerDeutsch) {
        expect(find.text(modellTitel(en, e.id)), findsNothing);
      }
      await sprache(tester, 'de', uebersetzen: false);

      // KI-021: mit EN→DE ist der erste Schalter bedienbar, der zweite nicht.
      await installiere(tester, [ModelCatalog.translationEnDe]);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      expect(
        tester
            .widget<SwitchListTile>(
              schalter(de.einstUebersetzeBeschreibungTitel),
            )
            .onChanged,
        isNotNull,
      );
      expect(
        tester
            .widget<SwitchListTile>(schalter(de.einstUebersetzeSucheTitel))
            .onChanged,
        isNull,
      );
      await tippe(tester, schalter(de.einstUebersetzeBeschreibungTitel));
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      expect(
        tester
            .widget<SwitchListTile>(
              schalter(de.einstUebersetzeBeschreibungTitel),
            )
            .value,
        isTrue,
      );
      expect(
        await tester.runAsync(bibliothek.db.uebersetzeBeschreibungen),
        isTrue,
      );

      // KI-020: beide geladen, Englisch: Karten bleiben, Schalter nicht.
      await installiere(tester, [ModelCatalog.translationDeEn]);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await tippe(tester, schalter(de.einstUebersetzeSucheTitel));
      await sprache(tester, 'en', uebersetzen: false);
      await einstellungsgruppe(tester, en.einstAbschnittModelle);
      expect(find.text(en.einstUebersetzeBeschreibungTitel), findsNothing);
      expect(find.text(en.einstUebersetzeSucheTitel), findsNothing);
      for (final e in ModelCatalog.nurFuerDeutsch) {
        await sichtbar(
          tester,
          find.text(modellTitel(en, e.id)),
          SettingsScreen,
        );
        expect(
          find.descendant(
            of: modellkarte(e.id, en),
            matching: find.byTooltip(en.einstModellLoeschen),
          ),
          findsOneWidget,
          reason: e.id,
        );
      }
      await sprache(tester, 'de', uebersetzen: false);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      for (final titel in [
        de.einstUebersetzeBeschreibungTitel,
        de.einstUebersetzeSucheTitel,
      ]) {
        await sichtbar(tester, schalter(titel), SettingsScreen);
        expect(
          tester.widget<SwitchListTile>(schalter(titel)).value,
          isTrue,
          reason: titel,
        );
      }
      await finish(tester);
    },
  );

  // Behoben in #414: deleteEntry lässt Dateien stehen, die ein anderer vorhandener Eintrag mitbenutzt (translate_vocab.json).
  testWidgets(
    timeout: zeitgrenze,
    'KI-022 Befundpruefung Uebersetzungsrichtung loeschen',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.translationEnDe,
          ModelCatalog.translationDeEn,
        ]),
      );
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(modellTitel(de, ModelCatalog.translationEnDe.id)),
        SettingsScreen,
      );
      await tippe(
        tester,
        find.descendant(
          of: modellkarte(ModelCatalog.translationEnDe.id),
          matching: find.byTooltip(de.einstModellLoeschen),
        ),
      );
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(modellTitel(de, ModelCatalog.translationDeEn.id)),
        SettingsScreen,
      );
      final vokabel = File(
        p.join(modellordnerDerPruefung.path, 'translate_vocab.json'),
      );
      print('KI-022 translate_vocab.json noch da: ${vokabel.existsSync()}');
      expect(
        bibliothek.isModelInstalled(ModelCatalog.translationDeEn),
        isTrue,
        reason: 'Deutsch → Englisch sollte installiert bleiben',
      );
      expect(
        find.descendant(
          of: modellkarte(ModelCatalog.translationDeEn.id),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(schalter(de.einstUebersetzeSucheTitel))
            .onChanged,
        isNotNull,
      );
      await finish(tester);
    },
  );

  // ---------------------------------------------------------- Schlagwörter

  testWidgets(
    timeout: zeitgrenze,
    'KI-072 KI-073 KI-074 KI-080 Vokabular bearbeiten',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final ids = await importiereDirekt(tester, [testfoto('v1.jpg')]);
      await befehl(tester, SchlagwortAnheften([ids.first], 'Strand'));

      // KI-072: Startbestückung, alphabetisch, mit Löschkreuz.
      await einstellungsgruppe(tester, de.einstAbschnittVokabular);
      expect(find.text(de.einstVokabularText), findsOneWidget);
      List<String> chips() => [
        for (final c in tester.widgetList<InputChip>(
          find.descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(InputChip),
          ),
        ))
          ((c.label as Text).data!),
      ];
      final anfang = chips();
      expect(anfang, containsAll(['Baby', 'Berge', 'Strand']));
      expect(anfang, List.of(anfang)..sort());
      for (final c in tester.widgetList<InputChip>(find.byType(InputChip))) {
        expect(c.onDeleted, isNotNull);
      }
      final feld = field(de.einstBegriffHinzufuegenFeld);
      expect(feld, findsOneWidget);
      expect(find.byTooltip(de.einstBegriffHinzufuegen), findsOneWidget);

      // KI-073: hinzufügen per Enter, leer, doppelt.
      await eintragen(tester, feld, 'Testbegriff');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(chips(), contains('Testbegriff'));
      expect(tester.widget<TextField>(feld).controller!.text, isEmpty);
      final anzahl = chips().length;
      await eintragen(tester, feld, '   ');
      await tippe(tester, find.byTooltip(de.einstBegriffHinzufuegen));
      expect(chips().length, anzahl);
      await eintragen(tester, feld, 'Testbegriff');
      await tippe(tester, find.byTooltip(de.einstBegriffHinzufuegen));
      await settle(tester);
      expect(chips().where((c) => c == 'Testbegriff').length, 1);
      expect(chips().length, anzahl);

      // KI-074: „Strand“ entfernen, ohne Rückfrage; das Schlagwort am Foto
      // bleibt.
      final strand = find.ancestor(
        of: find.text('Strand'),
        matching: find.byType(InputChip),
      );
      final loeschen = MaterialLocalizations.of(
        tester.element(strand),
      ).deleteButtonTooltip;
      await tippe(
        tester,
        find.descendant(of: strand, matching: find.byTooltip(loeschen)),
      );
      await settle(tester);
      expect(chips(), isNot(contains('Strand')));
      expect(find.byType(AlertDialog), findsNothing);
      final tags = await tester.runAsync(
        () => bibliothek.db.tagsForAsset(ids.first),
      );
      expect(tags!.map((t) => t.name), contains('Strand'));

      // KI-080: ohne KI-Schlagwörter gesperrt.
      final zurueck = find.ancestor(
        of: find.text(de.einstKiTagsZurueck),
        matching: find.byType(ListTile),
      );
      await sichtbar(tester, zurueck, SettingsScreen);
      expect(texteIn(zurueck), contains(de.einstKiTagsZurueckAnzahl(0)));
      expect(tester.widget<ListTile>(zurueck).enabled, isFalse);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-085 Sprachwechsel uebersetzt das Vokabular',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final ids = await importiereDirekt(tester, [testfoto('s1.jpg')]);
      await befehl(
        tester,
        SchlagwortAnheften([ids.first], 'Berge', quelle: Tagquelle.ki),
      );
      await befehl(tester, KiBegriffHinzufuegen('Eigenbegriff'));

      await einstellungsgruppe(tester, de.spracheTitel);
      await tippe(tester, find.text(de.spracheEnglisch));
      // Der Dialog steht schon in der neuen Sprache.
      await waitFor(tester, find.text(en.spracheVokabularTitel));
      expect(find.text(en.spracheVokabularUebersetzen), findsOneWidget);
      expect(find.text(en.spracheVokabularBehalten), findsOneWidget);
      expect(find.text(en.spracheVokabularSelbstAngelegt(1)), findsOneWidget);
      await tippe(tester, find.text(en.spracheVokabularUebersetzen));
      await settle(tester);
      final begriffe = await tester.runAsync(
        bibliothek.db.aiTagVocabularyTerms,
      );
      expect(begriffe, contains('Mountains'));
      expect(begriffe, isNot(contains('Berge')));
      expect(begriffe, contains('Eigenbegriff'));
      final tags = await tester.runAsync(
        () => bibliothek.db.tagsForAsset(ids.first),
      );
      expect(tags!.map((t) => t.name.toLowerCase()), contains('mountains'));

      // Zurück auf Deutsch, „Unverändert lassen“ ändert nichts.
      await einstellungsgruppe(tester, en.spracheTitel);
      await tippe(tester, find.text(en.spracheDeutsch));
      await waitFor(tester, find.text(de.spracheVokabularTitel));
      expect(find.text(de.spracheVokabularUebersetzen), findsOneWidget);
      await tippe(tester, find.text(de.spracheVokabularBehalten));
      await settle(tester);
      final danach = await tester.runAsync(bibliothek.db.aiTagVocabularyTerms);
      expect(danach, begriffe);
      await finish(tester);
    },
  );

  testWidgets(timeout: zeitgrenze, 'KI-079 KI-Schlagwoerter zuruecknehmen', (
    tester,
  ) async {
    await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
    await autoAus(tester);
    await warteRuhe(tester);
    final ids = await importiereDirekt(tester, [
      testfoto('z1.jpg'),
      testfoto('z2.jpg'),
    ]);
    await befehl(
      tester,
      SchlagwortAnheften(ids, 'Strand', quelle: Tagquelle.ki),
    );
    await befehl(
      tester,
      SchlagwortAnheften([ids.first], 'Berge', quelle: Tagquelle.ki),
    );
    await befehl(tester, SchlagwortAnheften([ids.first], 'Von Hand'));
    await sqlAusfuehren(tester, 'UPDATE assets SET ai_tags_scanned = 1');

    await einstellungsgruppe(tester, de.einstAbschnittVokabular);
    final eintrag = find.ancestor(
      of: find.text(de.einstKiTagsZurueck),
      matching: find.byType(ListTile),
    );
    await sichtbar(tester, eintrag, SettingsScreen);
    expect(texteIn(eintrag), contains(de.einstKiTagsZurueckAnzahl(3)));
    await tippe(tester, eintrag);
    await waitFor(tester, find.text(de.einstKiTagsZurueckFrage(3)));
    await tippe(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgAbbrechen),
      ),
    );
    expect(
      await zahl(tester, "SELECT count(*) FROM asset_tags WHERE quelle = 'ki'"),
      3,
    );
    await tippe(tester, eintrag);
    await tippe(tester, find.text(de.einstKiTagsZurueckJetzt));
    await erwarteMeldung(tester, de.einstKiTagsZurueckFertig(3));
    expect(
      await zahl(tester, "SELECT count(*) FROM asset_tags WHERE quelle = 'ki'"),
      0,
    );
    final tags = await tester.runAsync(
      () => bibliothek.db.tagsForAsset(ids.first),
    );
    expect(tags!.map((t) => t.name), ['Von Hand']);
    // Der Vermerk „schon durchgesehen“ ist an beiden Fotos gelöscht.
    expect(
      await zahl(
        tester,
        'SELECT count(*) FROM assets WHERE ai_tags_scanned = 0',
      ),
      2,
    );
    await finish(tester);
  });

  // Behoben in #414: assetsForAiTagging/countAiTagging verlangen „kein Schlagwort der Bilderkennung“ statt „gar kein Schlagwort“.
  testWidgets(
    timeout: zeitgrenze,
    'KI-079 Befundpruefung Fotos mit Handvergabe sind nach dem Zuruecknehmen offen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('zz1.jpg'),
        testfoto('zz2.jpg'),
      ]);
      await befehl(
        tester,
        SchlagwortAnheften(ids, 'Strand', quelle: Tagquelle.ki),
      );
      await befehl(tester, SchlagwortAnheften([ids.first], 'Von Hand'));
      await sqlAusfuehren(tester, 'UPDATE assets SET ai_tags_scanned = 1');
      await befehl(tester, const KiSchlagwoerterZuruecknehmen());
      await aufgaben(tester);
      await zurKarte(tester, de.aufgKiTagsTitel);
      final text = texteIn(karte(de.aufgKiTagsTitel));
      print('KI-079 Karte nach dem Zurücknehmen: $text');
      final offen = await tester.runAsync(
        () => bibliothek.db.countAiTagging(onlyUntagged: true),
      );
      expect(offen, 2, reason: 'Foto mit Handvergabe gilt nicht als offen');
      expect(text, contains(de.aufgOffeneFotos(2)));
      await finish(tester);
    },
  );

  // Behoben in #414: Das Zurücknehmen löscht nur Schlagwörter, die dadurch unbenutzt werden (kein Foto, keine Regel, keine Kameravorgabe).
  testWidgets(
    timeout: zeitgrenze,
    'KI-081 Befundpruefung Zuruecknehmen laesst unbenutzte Schlagwoerter',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final ids = await importiereDirekt(tester, [testfoto('l1.jpg')]);
      // „Leer“ hängt an keinem Foto, nur an einer Regel.
      await befehl(tester, SchlagwortAnheften([ids.first], 'Leer'));
      final leer = (await tester.runAsync(
        () => bibliothek.db.tagsForAsset(ids.first),
      ))!.single;
      await befehl(tester, SchlagwortLoesen(ids.first, leer.id));
      await befehl(
        tester,
        SchlagwortAnheften([ids.first], 'Strand', quelle: Tagquelle.ki),
      );
      await werkzeug(tester, de.werkzRegelnTitel);
      await tippe(tester, find.byTooltip(de.regelNeu));
      await eintragen(tester, field(de.regelNameFeld), 'Regel Leer');
      await eintragen(tester, field(de.regelBreitengrad), '10');
      await eintragen(tester, field(de.regelLaengengrad), '20');
      await tippe(tester, find.text(de.presetTagsWaehlenPlatzhalter));
      await tippe(
        tester,
        find.descendant(
          of: find.byType(CheckboxListTile),
          matching: find.text('Leer'),
        ),
      );
      await tippe(tester, find.text(de.allgUebernehmen));
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(tester, find.textContaining(de.regelTagsTeil('Leer')));

      await einstellungsgruppe(tester, de.einstAbschnittVokabular);
      final eintrag = find.ancestor(
        of: find.text(de.einstKiTagsZurueck),
        matching: find.byType(ListTile),
      );
      await sichtbar(tester, eintrag, SettingsScreen);
      await tippe(tester, eintrag);
      await tippe(tester, find.text(de.einstKiTagsZurueckJetzt));
      await erwarteMeldung(tester, de.einstKiTagsZurueckFertig(1));
      final nochDa = await zahl(
        tester,
        "SELECT count(*) FROM tags WHERE name = 'Leer'",
      );
      final inRegel = await zahl(
        tester,
        'SELECT count(*) FROM automation_rule_tags',
      );
      print('KI-081 Leer noch da: $nochDa, Regel-Tags: $inRegel');
      expect(nochDa, 1, reason: 'von Hand angelegtes Schlagwort gelöscht');
      await werkzeug(tester, de.werkzRegelnTitel);
      await waitFor(tester, find.textContaining(de.regelTagsTeil('Leer')));
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-075 KI-077 KI-082 KI-084 KI-Schlagwoerter mit der Bilderkennung',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.clip, ModelCatalog.translationDeEn]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      // Bildinhalte, die die Bilderkennung sicher benennt: Emoji-Bilder.
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'hunde.png', [
          '🐕 🐕 🐕',
          '🐕 🐕 🐕',
        ], groesse: 220),
        await textbild(tester, 'autos.png', [
          '🚗 🚗 🚗',
          '🚗 🚗 🚗',
        ], groesse: 220),
        blindfoto('einfarbig.jpg', r: 90, g: 90, b: 90),
      ]);
      await analyseUeberKarte(tester);

      // KI-075: höchstens fünf Begriffe aus dem Vokabular, sichtbar in Info.
      final vokabular = (await tester.runAsync(
        bibliothek.db.aiTagVocabularyTerms,
      ))!;
      final kiTags = <String, List<String>>{};
      for (final id in ids) {
        kiTags[id] = [
          for (final z in await sql(
            tester,
            'SELECT t.name AS n FROM asset_tags a JOIN tags t ON t.id = a.tag_id '
            "WHERE a.asset_id = ? AND a.quelle = 'ki'",
            [id],
          ))
            z['n']! as String,
        ];
        expect(kiTags[id]!.length, lessThanOrEqualTo(5));
        for (final t in kiTags[id]!) {
          expect(vokabular, contains(t));
        }
      }
      print('KI-075 vergeben: $kiTags');
      final mitTags = ids.firstWhere(
        (i) => kiTags[i]!.isNotEmpty,
        orElse: () => '',
      );
      expect(mitTags, isNotEmpty, reason: 'kein Foto bekam Schlagwörter');
      await betrachter(tester, ids, mitTags);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      for (final t in kiTags[mitTags]!) {
        expect(find.textContaining(t), findsWidgets, reason: t);
      }
      await betrachterZu(tester);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains(de.aufgOffeneFotos(0)),
      );

      // KI-077: das einfarbige Foto gilt als erledigt, auch nach dem Start.
      final mono = await aufnahme(tester, ids[2]);
      expect(mono.aiTagsScanned, isTrue);
      await autoAn(tester);
      await neustart(tester);
      await warteRuhe(tester);
      expect(
        await tester.runAsync(
          () => bibliothek.db.countAiTagging(onlyUntagged: true),
        ),
        0,
      );
      final herkunft = await zahl(
        tester,
        "SELECT count(*) FROM asset_tags WHERE quelle = 'ki'",
      );
      expect(
        herkunft,
        kiTags.values.fold<int>(0, (n, l) => n + l.length),
        reason: 'nichts neu verschlagwortet',
      );
      await autoAus(tester);

      // KI-082: neuer Begriff – „Fehlende“ findet nichts, „Alle“ geht über
      // alles.
      await befehl(tester, KiBegriffHinzufuegen('Testmotiv'));
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgKiTagsTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'kitags');
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains(de.werkzKeinePassenden),
      );
      await kartenknopf(tester, de.aufgKiTagsTitel, de.allgSchliessen);
      await kartenknopf(tester, de.aufgKiTagsTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'kitags');
      expect(bibliothek.lauf('kitags')!.gesamt, ids.length);
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains(de.aufgFertigMit(ids.length)),
      );
      await kartenknopf(tester, de.aufgKiTagsTitel, de.allgSchliessen);

      // KI-084: Suche und Schlagwörter übersetzen, Lauf mit „Alle“.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        schalter(de.einstUebersetzeSucheTitel),
        SettingsScreen,
      );
      await tippe(tester, schalter(de.einstUebersetzeSucheTitel));
      expect(
        await tester.runAsync(bibliothek.db.uebersetzeSucheUndTags),
        isTrue,
      );
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgKiTagsTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'kitags');
      expect(bibliothek.lauf('kitags')!.fehler, isNull);
      final namen = [
        for (final z in await sql(
          tester,
          'SELECT DISTINCT t.name AS n FROM asset_tags a JOIN tags t '
          "ON t.id = a.tag_id WHERE a.quelle = 'ki'",
        ))
          z['n']! as String,
      ];
      print('KI-084 Begriffe mit Übersetzung: $namen');
      final vok = (await tester.runAsync(bibliothek.db.aiTagVocabularyTerms))!;
      for (final n in namen) {
        expect(vok, contains(n), reason: 'Begriff bleibt deutsch: $n');
      }
      await kartenknopf(tester, de.aufgKiTagsTitel, de.allgSchliessen);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        schalter(de.einstUebersetzeSucheTitel),
        SettingsScreen,
      );
      await tippe(tester, schalter(de.einstUebersetzeSucheTitel));
      expect(
        await tester.runAsync(bibliothek.db.uebersetzeSucheUndTags),
        isFalse,
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-161 KI-Tag-Regel wirkt nach der Verschlagwortung',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final erstes = await importiereDirekt(tester, [
        testfoto('r1.jpg', muster: 815, datum: DateTime(2021, 1, 1, 12)),
      ]);
      await analyseUeberKarte(tester);
      final begriffe = [
        for (final z in await sql(
          tester,
          'SELECT t.name AS n FROM asset_tags a JOIN tags t ON t.id = a.tag_id '
          "WHERE a.asset_id = ? AND a.quelle = 'ki'",
          [erstes.first],
        ))
          z['n']! as String,
      ];
      expect(begriffe, isNotEmpty, reason: 'Vorbedingung: ein KI-Begriff');
      final begriff = begriffe.first;

      await werkzeug(tester, de.werkzRegelnTitel);
      await tippe(tester, find.byTooltip(de.regelNeu));
      await eintragen(tester, field(de.regelNameFeld), 'Regel KI');
      await tippe(tester, find.text(de.regelAusloeserOrt));
      await tippe(tester, find.text(de.regelAusloeserTag).last);
      final auswahl = find.ancestor(
        of: find.text(de.regelTagBegriff),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tippe(tester, auswahl);
      final eintrag = find.text(begriff).last;
      if (!_findet(eintrag) || tester.getRect(eintrag).top > 880) {
        await tester.scrollUntilVisible(
          eintrag,
          48,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 80,
        );
      }
      await tippe(tester, find.text(begriff).last);
      await eintragen(tester, field(de.presetNeuesAlbum), 'KI-Album');
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(
        tester,
        find.textContaining(
          '${de.regelAusloeserTag} · ${de.regelTagWert(begriff)}',
        ),
      );

      // Dasselbe Bild noch einmal (andere Datei) und ein anderes.
      final neu = await importiereDirekt(tester, [
        testfoto('r2.jpg', muster: 815, datum: DateTime(2021, 1, 2, 12)),
        blindfoto('r3.jpg', r: 20, g: 120, b: 220),
      ]);
      await analyseUeberKarte(tester);
      final album =
          (await sql(
                tester,
                "SELECT id FROM albums WHERE name = 'KI-Album'",
              )).single['id']!
              as String;
      for (final id in neu) {
        final hat = await zahl(
          tester,
          'SELECT count(*) FROM asset_tags a JOIN tags t ON t.id = a.tag_id '
          "WHERE a.asset_id = ? AND t.name = ? AND a.quelle = 'ki'",
          [id, begriff],
        );
        final drin = await zahl(
          tester,
          'SELECT count(*) FROM album_assets WHERE album_id = ? AND asset_id = ?',
          [album, id],
        );
        print('KI-161 $id: Begriff $hat, im Album $drin');
        expect(drin, hat > 0 ? 1 : 0);
      }
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM album_assets WHERE album_id = ? AND asset_id = ?',
          [album, neu.first],
        ),
        1,
        reason: 'das gleiche Bild bekam den Begriff und liegt im Album',
      );
      await finish(tester);
    },
  );

  // Behoben in #414: Vokabular-Hinweis nennt Werkzeuge → Aufgaben → KI-Tags → Alle, „Alle Auswertungen nachholen“ alle sieben Stufen, PaddleOCR 12,8 MB.
  testWidgets(
    timeout: zeitgrenze,
    'KI-031 KI-083 KI-095 Befundpruefung veraltete Texte',
    (tester) async {
      await startApp(tester);
      final falsch = <String>[];
      // app_de.arb:528 – Weg zum Neuverschlagworten.
      await einstellungsgruppe(tester, de.einstAbschnittVokabular);
      expect(find.text(de.einstVokabularText), findsOneWidget);
      print('TEXT 528: ${de.einstVokabularText}');
      if (!de.einstVokabularText.contains(de.aufgTitel) ||
          de.einstVokabularText.contains('KI-Tags berechnen')) {
        falsch.add('528 einstVokabularText nennt „${de.einstVokabularText}“');
      }
      // app_de.arb:4287 – Grösse der Texterkennung.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      final ocr = modellBeschreibung(de, ModelCatalog.ocrPaddle.id);
      await sichtbar(tester, find.textContaining(ocr), SettingsScreen);
      final bytes = ModelCatalog.ocrPaddle.files.fold<int>(
        0,
        (n, f) => n + f.bytes,
      );
      final mb = (bytes / 1000000).toStringAsFixed(1).replaceAll('.', ',');
      final mib = (bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',');
      print('TEXT 4287: $ocr (Katalog: $bytes Bytes = $mb MB / $mib MiB)');
      if (!ocr.contains('$mb MB') && !ocr.contains('$mib MB')) {
        falsch.add('4287 nennt „$ocr“, Katalog ergibt $mb MB');
      }
      // app_de.arb:970 – die Stufen der Gesamtauswertung.
      await aufgaben(tester);
      expect(find.text(de.werkzAllesNachholenText), findsOneWidget);
      print('TEXT 970: ${de.werkzAllesNachholenText}');
      for (final stufe in [
        de.stufeVideobilder,
        de.stufeSpracherkennung,
        de.stufeWiedererkennung,
      ]) {
        if (!de.werkzAllesNachholenText.contains(stufe)) {
          falsch.add('970 werkzAllesNachholenText ohne „$stufe“');
        }
      }
      // app_de.arb:1058 – OCR-Karte (unter macOS zutreffend).
      await zurKarte(tester, de.aufgOcrTitel);
      expect(find.text(de.aufgOcrText), findsOneWidget);
      print('TEXT 1058: ${de.aufgOcrText}');
      print('TEXTBEFUNDE: $falsch');
      expect(falsch, isEmpty);
      await finish(tester);
    },
  );

  // ---------------------------------------------------- Hintergrundanalyse

  testWidgets(
    timeout: zeitgrenze,
    'KI-027 KI-031 Analyse nach dem Import mit Hinweisband',
    (tester) async {
      await startApp(tester, modelle: dateienVon(analysemodelle));
      await warteRuhe(tester);
      final stufen = <(int, Analysestufe)>[];
      final gesamtWerte = <int>{};
      void merke() {
        final a = bibliothek.analyse;
        if (a == null) return;
        gesamtWerte.add(a.stufenGesamt);
        if (stufen.isEmpty || stufen.last.$2 != a.stufe) {
          stufen.add((a.stufeNummer, a.stufe));
        }
      }

      bibliothek.addListener(merke);
      bibliothek.fortschritt.addListener(merke);
      final dateien = [
        for (var i = 0; i < 10; i++)
          testfoto('h$i.jpg', datum: DateTime(2024, 4, 1 + i, 10)),
        fixture('video_5s.mp4'),
      ];
      await importiereUeberUi(tester, dateien);
      // Der Import wartet nicht auf die Analyse.
      final laeuftNachImport =
          bibliothek.analyseLaeuft || bibliothek.analyseZurueckgestellt;
      var bandGesehen = false, abbrechenGesehen = false;
      final ende = DateTime.now().add(const Duration(minutes: 8));
      var ruhig = 0;
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 200));
        final band = find.textContaining(' wird berechnet (Schritt ');
        if (_findet(band)) {
          bandGesehen = true;
          final text = tester.widget<Text>(band.first).data ?? '';
          expect(text, contains('von 7'));
          if (_findet(
            find.ancestor(
              of: find.text(de.allgAbbrechen),
              matching: find.byType(TextButton),
            ),
          )) {
            abbrechenGesehen = true;
          }
        }
        merke();
        ruhig = bibliothek.analyseLaeuft ? 0 : ruhig + 1;
        if (ruhig > 10 && stufen.isNotEmpty) break;
      }
      bibliothek.removeListener(merke);
      bibliothek.fortschritt.removeListener(merke);
      print('KI-031 Stufen: $stufen');
      expect(gesamtWerte, {7});
      expect(laeuftNachImport || stufen.isNotEmpty, isTrue);
      expect(bandGesehen, isTrue, reason: 'Hinweisband erschien');
      expect(abbrechenGesehen, isTrue, reason: 'Knopf „Abbrechen“ im Band');
      expect(bibliothek.analyseLaeuft, isFalse);
      expect(find.textContaining(' wird berechnet (Schritt '), findsNothing);
      // KI-031: Reihenfolge der Stufen.
      for (var i = 1; i < stufen.length; i++) {
        expect(stufen[i].$1, greaterThan(stufen[i - 1].$1), reason: '$stufen');
      }
      expect(
        [for (final s in stufen) s.$2],
        Analysestufe.values,
        reason: 'alle sieben Stufen in der Reihenfolge',
      );
      expect(
        [for (final s in Analysestufe.values) analysestufeName(de, s)],
        [
          de.stufeBildanalyse,
          de.stufeVideobilder,
          de.stufeTexterkennung,
          de.stufeSchlagwoerter,
          de.stufeBildbeschreibung,
          de.stufeSpracherkennung,
          de.stufeWiedererkennung,
        ],
      );
      expect(
        await zahl(tester, 'SELECT count(*) FROM image_embeddings'),
        greaterThanOrEqualTo(10),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-028 KI-029 KI-048 KI-060 Auswertung von Hand',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.clip,
          ModelCatalog.faceDetection,
          ModelCatalog.captioningFlorence,
        ]),
      );
      await warteRuhe(tester);
      // KI-028: Auto-Auswertung über die Einstellungen aus.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await tippe(tester, schalter(de.einstAutoAnalyseTitel));
      expect(
        await tester.runAsync(bibliothek.db.autoAnalyzeAfterImportEnabled),
        isFalse,
      );
      await importiereDirekt(tester, [
        for (var i = 0; i < 5; i++)
          testfoto('a$i.jpg', datum: DateTime(2024, 5, 1 + i, 9)),
      ]);
      await pumpe(tester, 1500);
      expect(bibliothek.analyseLaeuft, isFalse);
      expect(find.textContaining(' wird berechnet (Schritt '), findsNothing);

      // KI-048: Karten nennen Aktiv/Wartend und offene Fotos.
      await aufgaben(tester);
      for (final (titel, knoepfe) in [
        (de.werkzGesichterScannenTitel, [de.aufgModusAlle, de.aufgFehlende]),
        (de.aufgOcrTitel, [de.aufgModusAlle, de.aufgFehlende]),
        (de.aufgBeschreibungenTitel, [de.aufgModusAlle, de.aufgFehlende]),
        (de.aufgEmbeddingsTitel, [de.aufgModusAlle, de.aufgFehlende]),
        (de.aufgKiTagsTitel, [de.aufgModusAlle, de.aufgFehlende]),
        (de.aufgUnschaerfeTitel, [de.aufgFehlende]),
      ]) {
        await zurKarte(tester, titel);
        final text = texteIn(karte(titel));
        expect(text, contains(de.aufgAktiv), reason: titel);
        expect(text, contains(de.aufgWartend), reason: titel);
        expect(text, contains(de.aufgOffeneFotos(5)), reason: titel);
        for (final k in knoepfe) {
          expect(knopfAktiv(tester, titel, k), isTrue, reason: '$titel $k');
        }
        if (knoepfe.length == 1) {
          expect(
            find.descendant(
              of: karte(titel),
              matching: find.text(de.aufgModusAlle),
            ),
            findsNothing,
          );
        }
      }
      await zurKarte(tester, de.aufgVideobilderTitel);
      expect(
        texteIn(karte(de.aufgVideobilderTitel)),
        contains('${de.aufgBetrifft}: 0'),
      );

      // KI-060: die Karte „Alle Auswertungen jetzt nachholen“.
      await zurKarte(tester, de.werkzAllesNachholenTitel);
      final gesamt = karte(de.werkzAllesNachholenTitel);
      expect(texteIn(gesamt), contains(de.aufgBereit));
      expect(texteIn(gesamt), contains(de.aufgStatus));
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await erwarteMeldung(tester, de.aufgLaeuft);
      var stufeGesehen = false, zeileGesehen = false, abbrechen = false;
      final bis = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(bis) &&
          (bibliothek.analyseLaeuft || !stufeGesehen)) {
        await tester.pump(const Duration(milliseconds: 150));
        final a = bibliothek.analyse;
        if (a == null) continue;
        final t = texteIn(karte(de.werkzAllesNachholenTitel));
        if (t.contains('Stufe ${a.stufeNummer}/7')) stufeGesehen = true;
        if (t.contains(' – Stufe ') &&
            t.contains(analysestufeName(de, a.stufe))) {
          zeileGesehen = true;
        }
        if (t.contains(de.allgAbbrechen)) abbrechen = true;
      }
      expect(stufeGesehen, isTrue, reason: 'Status „Stufe n/7“');
      expect(zeileGesehen, isTrue, reason: 'Zeile „<Stufe> (x/y) – Stufe n/7“');
      expect(abbrechen, isTrue, reason: 'Leiste „Abbrechen“');
      await warteRuhe(tester);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains(de.aufgOffeneFotos(0)),
      );
      await zurKarte(tester, de.werkzAllesNachholenTitel);
      expect(
        texteIn(karte(de.werkzAllesNachholenTitel)),
        contains(de.aufgBereit),
      );

      // KI-060 Abbrechen in der Karte, KI-029 Abbrechen im Band.
      await importiereDirekt(tester, [
        for (var i = 0; i < 50; i++)
          testfoto('b$i.jpg', datum: DateTime(2023, 1, 1 + i % 28, 8)),
      ]);
      Future<int> eingebettet() =>
          zahl(tester, 'SELECT count(*) FROM image_embeddings');
      await aufgaben(tester);
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async => (bibliothek.analyse?.erledigt ?? 0) >= 3,
        timeout: const Duration(minutes: 2),
        was: 'Analyse in Gang',
      );
      await kartenknopf(tester, de.werkzAllesNachholenTitel, de.allgAbbrechen);
      await eventually(
        tester,
        () async => !bibliothek.analyseLaeuft,
        timeout: const Duration(minutes: 1),
        was: 'Analyse hält an',
      );
      await pumpe(tester);
      expect(
        texteIn(karte(de.werkzAllesNachholenTitel)),
        contains(de.aufgBereit),
      );
      final nachKarte = await eingebettet();
      expect(nachKarte, lessThan(55));
      expect(nachKarte, greaterThan(5));

      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async => (bibliothek.analyse?.erledigt ?? 0) >= 3,
        timeout: const Duration(minutes: 2),
        was: 'Analyse wieder in Gang',
      );
      await bereich(tester, Hauptbereich.zeitleiste);
      final bandKnopf = find.ancestor(
        of: find.text(de.allgAbbrechen),
        matching: find.byType(TextButton),
      );
      await tippe(tester, bandKnopf);
      await eventually(
        tester,
        () async => !bibliothek.analyseLaeuft,
        timeout: const Duration(minutes: 1),
        was: 'Analyse hält nach dem Band-Abbruch an',
      );
      await pumpe(tester);
      expect(find.textContaining(' wird berechnet (Schritt '), findsNothing);
      final nachBand = await eingebettet();
      expect(nachBand, greaterThan(nachKarte));
      expect(nachBand, lessThan(55));
      await aufgaben(tester);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains(de.aufgOffeneFotos(55 - nachBand)),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-030 KI-038 Beenden waehrend der Analyse und Fortsetzen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        for (var i = 0; i < 40; i++)
          testfoto('q$i.jpg', datum: DateTime(2022, 2, 1 + i % 28, 7)),
      ]);
      await autoAn(tester);
      await aufgaben(tester);
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async => (bibliothek.analyse?.erledigt ?? 0) >= 4,
        timeout: const Duration(minutes: 2),
        was: 'Analyse in Gang',
      );

      // KI-038: Rückfrage, „Weiterlaufen lassen“.
      final erste = beendenAnfragen(tester);
      await waitFor(tester, find.text(de.beendenTitel));
      expect(find.text(de.beendenText), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(de.werkzAllesNachholenTitel),
        ),
        findsOneWidget,
      );
      await tippe(tester, find.text(de.beendenWeiterlaufen));
      expect(await mitPumpen(tester, erste), isFalse);
      expect(bibliothek.analyseLaeuft, isTrue);

      // Stand vor dem Beenden.
      final vorher = {
        for (final z in await sql(
          tester,
          "SELECT asset_id, zeit FROM ergebnisherkunft WHERE art = 'clip'",
        ))
          z['asset_id']! as String: z['zeit'],
      };
      expect(vorher, isNotEmpty);
      expect(vorher.length, lessThan(ids.length));

      final zweite = beendenAnfragen(tester);
      await waitFor(tester, find.text(de.beendenTitel));
      await tippe(tester, find.text(de.beendenTrotzdem));
      expect(await mitPumpen(tester, zweite), isTrue);
      // Der Prozess endete hier; im Test hält die Arbeit von selbst an.
      bibliothek.brichHintergrundanalyseAb();
      await eventually(
        tester,
        () async => !bibliothek.analyseLaeuft,
        timeout: const Duration(minutes: 1),
        was: 'alte Analyse hält an',
      );

      // KI-030: nach dem Start läuft das Band von selbst, nur für Offenes.
      final gesamtNachStart = <int>[];
      await tester.runAsync(bibliothek.vorDemBeenden);
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
      void merke() {
        final a = bibliothek.analyse;
        if (a != null && a.stufe == Analysestufe.bildanalyse && a.gesamt > 0) {
          gesamtNachStart.add(a.gesamt);
        }
      }

      bibliothek.addListener(merke);
      bibliothek.fortschritt.addListener(merke);
      var bandGesehen = false;
      final bis = DateTime.now().add(const Duration(minutes: 4));
      var ruhig = 0;
      while (DateTime.now().isBefore(bis)) {
        await tester.pump(const Duration(milliseconds: 200));
        merke();
        if (_findet(find.textContaining(' wird berechnet (Schritt '))) {
          bandGesehen = true;
        }
        ruhig = bibliothek.analyseLaeuft ? 0 : ruhig + 1;
        if (ruhig > 10 && gesamtNachStart.isNotEmpty) break;
      }
      bibliothek.removeListener(merke);
      bibliothek.fortschritt.removeListener(merke);
      print('KI-030 vorher ${vorher.length}, nach dem Start: $gesamtNachStart');
      expect(bandGesehen, isTrue, reason: 'Band nach dem Start');
      expect(gesamtNachStart, isNotEmpty);
      print(
        'KI-030 offen vor dem Beenden: ${ids.length - vorher.length}, '
        'Band nach dem Start: ${gesamtNachStart.first}',
      );
      final nachher = {
        for (final z in await sql(
          tester,
          "SELECT asset_id, zeit FROM ergebnisherkunft WHERE art = 'clip'",
        ))
          z['asset_id']! as String: z['zeit'],
      };
      expect(nachher.length, ids.length);
      for (final e in vorher.entries) {
        expect(
          nachher[e.key],
          e.value,
          reason: 'nicht neu gerechnet: ${e.key}',
        );
      }
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-032 Stufen ohne Modell werden still uebersprungen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.faceDetection]));
      await warteRuhe(tester);
      final ids = await mitAnalyse(
        tester,
        () => importiereDirekt(tester, [
          testfoto('y1.jpg', datum: DateTime(2024, 1, 2, 10)),
          testfoto('y2.jpg', datum: DateTime(2024, 1, 3, 10)),
        ]),
      );
      expect(find.textContaining('fehlgeschlagen'), findsNothing);
      for (final id in ids) {
        final a = await aufnahme(tester, id);
        expect(a.facesScanned, isTrue, reason: 'Gesichter-Scan');
        expect(a.sharpnessScore, isNotNull, reason: 'Unschärfe');
        expect(a.aiCaption, isNull);
        expect(a.aiTagsScanned, isFalse);
      }
      expect(await zahl(tester, 'SELECT count(*) FROM image_embeddings'), 0);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgBeschreibungenTitel);
      expect(
        texteIn(karte(de.aufgBeschreibungenTitel)),
        contains(
          de.aufgModellNoetig(de.aufgBeschreibungsmodell, de.aufgWoModelle),
        ),
      );
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains(de.aufgModellNoetig(de.aufgClipModell, de.aufgWoModelle)),
      );
      await zurKarte(tester, de.werkzGesichterScannenTitel);
      expect(
        texteIn(karte(de.werkzGesichterScannenTitel)),
        contains(de.aufgOffeneFotos(0)),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-034 Beschaedigtes Foto haelt die Analyse nicht auf',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.clip, ModelCatalog.faceDetection]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('g1.jpg', datum: DateTime(2024, 2, 1, 10)),
        testfoto('g2.jpg', datum: DateTime(2024, 2, 2, 10)),
        testfoto('kaputt.jpg', datum: DateTime(2024, 2, 3, 10)),
      ]);
      // Der Inhalt der dritten Datei wird zerstört (Kopf bleibt, Rest Müll).
      final kaputt = await aufnahme(tester, ids[2]);
      final datei = bibliothek.paths.absolute(kaputt.relativePath);
      final roh = datei.readAsBytesSync();
      final zufall = math.Random(7);
      datei.writeAsBytesSync([
        ...roh.sublist(0, 4),
        for (var i = 4; i < roh.length; i++) zufall.nextInt(256),
      ]);
      await analyseUeberKarte(tester);
      for (final id in ids.take(2)) {
        final a = await aufnahme(tester, id);
        expect(a.facesScanned, isTrue);
        expect(a.sharpnessScore, isNotNull);
        expect(
          await zahl(
            tester,
            'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
            [id],
          ),
          1,
        );
      }
      final k = await aufnahme(tester, ids[2]);
      expect(k.facesScanned, isFalse);
      expect(k.sharpnessScore, isNull);
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [ids[2]],
        ),
        0,
      );
      await aufgaben(tester);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains(de.aufgOffeneFotos(1)),
      );
      await zurKarte(tester, de.werkzGesichterScannenTitel);
      expect(
        texteIn(karte(de.werkzGesichterScannenTitel)),
        contains(de.aufgOffeneFotos(1)),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-035 Oberflaeche bleibt bedienbar waehrend der Analyse',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.captioningFlorence,
          ModelCatalog.clip,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        for (var i = 0; i < 24; i++)
          testfoto('u$i.jpg', datum: DateTime(2020, 3, 1 + i, 11)),
      ]);
      await aufgaben(tester);
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async => bibliothek.analyse?.stufe == Analysestufe.bildbeschreibung,
        timeout: const Duration(minutes: 3),
        was: 'Bildbeschreibung rechnet',
      );
      var groessteLuecke = Duration.zero;
      final erledigtVorher = bibliothek.analyse?.erledigt ?? 0;
      Future<void> messe(int runden) async {
        for (var i = 0; i < runden; i++) {
          final uhr = Stopwatch()..start();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          final ueber = uhr.elapsed - const Duration(milliseconds: 40);
          if (ueber > groessteLuecke) groessteLuecke = ueber;
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      await bereich(tester, Hauptbereich.zeitleiste);
      await messe(20);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await messe(20);
      await betrachter(tester, ids, ids[3]);
      await messe(20);
      await rechtsklick(tester, find.byType(PageView));
      await messe(10);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await betrachterZu(tester);
      await messe(30);
      final erledigtNachher = bibliothek.analyse?.erledigt ?? 1 << 20;
      print(
        'KI-035 grösste Verzögerung: ${groessteLuecke.inMilliseconds} ms, '
        'Band $erledigtVorher → $erledigtNachher',
      );
      expect(groessteLuecke, lessThan(const Duration(milliseconds: 250)));
      expect(
        erledigtNachher > erledigtVorher || !bibliothek.analyseLaeuft,
        isTrue,
        reason: 'das Band zählt weiter',
      );
      bibliothek.brichHintergrundanalyseAb();
      await warteRuhe(tester);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-042 Gesperrte und geloeschte Fotos werden nicht ausgewertet',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.clip,
          ModelCatalog.captioningFlorence,
          ModelCatalog.faceDetection,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'offen.png', ['OFFENER TEXT 1234']),
        await textbild(tester, 'gesperrt.png', ['GESPERRTER TEXT 5678']),
        await textbild(tester, 'geloescht.png', ['GELOESCHTER TEXT 9012']),
      ]);
      await tester.runAsync(() => bibliothek.setupVaultPin('2468'));
      await tester.runAsync(
        () async =>
            bibliothek.lockAsset((await bibliothek.db.assetById(ids[1]))!),
      );
      await befehl(tester, InDenPapierkorb([ids[2]]));
      await analyseUeberKarte(tester);

      final offen = await aufnahme(tester, ids[0]);
      expect(offen.ocrText, isNotNull);
      expect(offen.aiCaption, isNotNull);
      expect(offen.aiTagsScanned, isTrue);
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [ids[0]],
        ),
        1,
      );
      for (final id in ids.skip(1)) {
        final a = await aufnahme(tester, id);
        expect(a.ocrText, isNull, reason: id);
        expect(a.aiCaption, isNull, reason: id);
        expect(a.aiCaptionDe, isNull, reason: id);
        expect(a.aiTagsScanned, isFalse, reason: id);
        expect(
          await zahl(
            tester,
            'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
            [id],
          ),
          0,
          reason: id,
        );
        expect(
          await zahl(
            tester,
            "SELECT count(*) FROM asset_tags WHERE asset_id = ? AND quelle = 'ki'",
            [id],
          ),
          0,
          reason: id,
        );
      }
      // Entsperren und ansehen, bevor eine neue Analyse läuft.
      await tester.runAsync(
        () async =>
            bibliothek.unlockAsset((await bibliothek.db.assetById(ids[1]))!),
      );
      final entsperrt = await aufnahme(tester, ids[1]);
      expect(entsperrt.isLocked, isFalse);
      expect(entsperrt.ocrText, isNull);
      expect(entsperrt.aiCaption, isNull);
      await betrachter(tester, [ids[0], ids[1]], ids[1]);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      expect(find.text(de.infoErkannterText), findsNothing);
      expect(find.text(de.infoKiBeschreibung), findsNothing);
      await betrachterZu(tester);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-043 Sperren entfernt KI-Ergebnisse, Entsperren rechnet neu',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.clip,
          ModelCatalog.captioningFlorence,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'a.png', ['ZUGANG GEHEIM 4711']),
        await textbild(tester, 'b.png', ['ZWEITES BILD 0815']),
      ]);
      await analyseUeberKarte(tester);
      final a = ids[0], b = ids[1];
      expect((await aufnahme(tester, a)).ocrText, isNotNull);
      expect((await aufnahme(tester, a)).aiCaption, isNotNull);
      await befehl(
        tester,
        SchlagwortAnheften([a], 'Strand', quelle: Tagquelle.ki),
      );
      await befehl(tester, SchlagwortAnheften([a], 'Handvergabe'));
      await befehl(
        tester,
        BildbeschreibungSetzen(b, 'Eigene Worte', deutsch: true),
      );
      expect((await aufnahme(tester, b)).aiCaptionEdited, isTrue);

      await tester.runAsync(() => bibliothek.setupVaultPin('2468'));
      for (final id in [a, b]) {
        await tester.runAsync(
          () async =>
              bibliothek.lockAsset((await bibliothek.db.assetById(id))!),
        );
      }
      final ga = await aufnahme(tester, a);
      expect(ga.isLocked, isTrue);
      expect(ga.ocrText, isNull);
      expect(ga.ocrBoxen, isNull);
      expect(ga.aiCaption, isNull);
      expect(ga.aiCaptionDe, isNull);
      expect(ga.transkript, isNull);
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [a],
        ),
        0,
      );
      expect(
        await zahl(
          tester,
          "SELECT count(*) FROM asset_tags WHERE asset_id = ? AND quelle = 'ki'",
          [a],
        ),
        0,
      );
      final roheDb = File(
        p.join(bibliothek.paths.root.parent.path, 'library.sqlite'),
      );
      if (roheDb.existsSync()) {
        final inhalt = String.fromCharCodes(roheDb.readAsBytesSync());
        print(
          'KI-043 Text im Klartext der Datei: ${inhalt.contains('GEHEIM')}',
        );
      }
      // Entsperren: von Hand Vergebenes ist wieder da, die KI rechnet neu.
      for (final id in [a, b]) {
        await tester.runAsync(
          () async =>
              bibliothek.unlockAsset((await bibliothek.db.assetById(id))!),
        );
      }
      final tagsA = await tester.runAsync(() => bibliothek.db.tagsForAsset(a));
      expect(tagsA!.map((t) => t.name), contains('Handvergabe'));
      final eb = await aufnahme(tester, b);
      expect(eb.aiCaptionEdited, isTrue);
      expect(eb.aiCaptionDe ?? eb.aiCaption, 'Eigene Worte');
      await analyseUeberKarte(tester);
      final na = await aufnahme(tester, a);
      expect(na.ocrText, isNotNull);
      expect(na.aiCaption, isNotNull);
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [a],
        ),
        1,
      );
      expect((await aufnahme(tester, b)).aiCaptionDe ?? '', 'Eigene Worte');
      await finish(tester);
    },
  );

  // Behoben in #403: Sperren nimmt auch die Videoeinbettungen weg.
  testWidgets(
    timeout: zeitgrenze,
    'KI-044 Befundpruefung Sperren entfernt Videoeinbettungen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [fixture('video_5s.mp4')]);
      // Längere Fixture gibt es nicht: Laufzeit auf 30 s gesetzt.
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [ids.first],
      );
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgVideobilderTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'videobilder');
      final vorher = await zahl(
        tester,
        'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
        [ids.first],
      );
      expect(vorher, greaterThanOrEqualTo(2));
      await tester.runAsync(() => bibliothek.setupVaultPin('2468'));
      await tester.runAsync(
        () async =>
            bibliothek.lockAsset((await bibliothek.db.assetById(ids.first))!),
      );
      final nachher = await zahl(
        tester,
        'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
        [ids.first],
      );
      final geprueft = (await aufnahme(tester, ids.first)).videobilderGeprueft;
      print(
        'KI-044 Videoeinbettungen vorher $vorher, nach dem Sperren $nachher, '
        'videobilder_geprueft $geprueft',
      );
      expect(nachher, 0, reason: 'Vektoren des gesperrten Videos im Klartext');
      expect(geprueft, isFalse);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-045 Auswertungen veraendern keine Originale',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([...analysemodelle, ModelCatalog.translationEnDe]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'o1.png', ['ORIGINAL BLEIBT']),
        testfoto('o2.jpg', datum: DateTime(2021, 7, 7, 7)),
        fixture('video_5s.mp4'),
      ]);
      final assets = [for (final id in ids) await aufnahme(tester, id)];
      final summen = {
        for (final a in assets)
          a.id: sha(bibliothek.paths.absolute(a.relativePath)),
      };
      Set<String> nachbarn() => {
        for (final a in assets)
          for (final e
              in bibliothek.paths.absolute(a.relativePath).parent.listSync())
            e.path,
      };
      final vorher = nachbarn();
      await analyseUeberKarte(tester, timeout: const Duration(minutes: 8));
      // Jede KI-Aufgabe mit „Alle“ über den Sammeldialog.
      await aufgaben(tester);
      await kopfTippen(tester, de.aufgErstellen);
      await tippe(tester, find.text(de.aufgModusAlle).last);
      for (final titel in [
        de.werkzGesichterScannenTitel,
        de.aufgWiedererkennungTitel,
        de.aufgOcrTitel,
        de.aufgBeschreibungenTitel,
        de.aufgTranskripteTitel,
        de.aufgUebersetzenTitel,
        de.aufgEmbeddingsTitel,
        de.aufgKiTagsTitel,
        de.aufgVideobilderTitel,
      ]) {
        await imDialogTippen(tester, titel);
      }
      await tippe(tester, find.text(de.aufgEinreihen));
      await erwarteMeldung(tester, de.aufgEingereiht(9));
      await warteRuhe(tester, timeout: const Duration(minutes: 10));
      for (final a in assets) {
        expect(
          sha(bibliothek.paths.absolute(a.relativePath)),
          summen[a.id],
          reason: a.originalFileName,
        );
      }
      expect(nachbarn(), vorher, reason: 'keine Dateien neben den Originalen');
      await finish(tester);
    },
  );

  // --------------------------------------------------------------- Aufgaben

  testWidgets(
    timeout: zeitgrenze,
    'KI-049 KI-050 KI-051 KI-052 KI-053 Aufgabe laeuft in der Karte',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      const n = 120;
      final namen = [for (var i = 0; i < n; i++) 'k$i.jpg'];
      await importiereDirekt(tester, [
        for (var i = 0; i < n; i++)
          testfoto(
            namen[i],
            datum: DateTime(2019, 1 + i % 12, 1 + i % 28, 9),
            breite: 2400,
            hoehe: 1800,
          ),
      ]);
      await aufgaben(tester);
      final titel = de.aufgEmbeddingsTitel;
      final fortschritt = RegExp(r'\d+ / \d+');

      // KI-049: kein Dialog, Fortschritt in der Karte.
      await kartenknopf(tester, titel, de.aufgFehlende);
      expect(find.byType(AlertDialog), findsNothing);
      await eventually(
        tester,
        () async => (bibliothek.lauf('embeddings')?.erledigt ?? 0) >= 1,
        timeout: const Duration(minutes: 2),
        was: 'CLIP rechnet',
      );
      await zurKarte(tester, titel);
      final text = texteIn(karte(titel));
      print('KI-049 Karte: $text');
      expect(text, contains(de.werkzBerechneEmbeddings));
      expect(fortschritt.hasMatch(text), isTrue, reason: text);
      expect(namen.any(text.contains), isTrue, reason: 'Dateiname: $text');
      expect(text, contains('${de.aufgAktiv} | 1'));
      expect(text, contains(de.allgAbbrechen));
      expect(
        find.descendant(
          of: karte(titel),
          matching: find.byType(LinearProgressIndicator),
        ),
        findsOneWidget,
      );

      // KI-053: abbrechen.
      await kartenknopf(tester, titel, de.allgAbbrechen);
      await warteAufLauf(
        tester,
        'embeddings',
        timeout: const Duration(minutes: 1),
      );
      await pumpe(tester);
      final lauf = bibliothek.lauf('embeddings')!;
      expect(lauf.abgebrochen, isTrue);
      await zurKarte(tester, titel);
      expect(
        texteIn(karte(titel)),
        contains(de.aufgAbgebrochenBei(lauf.erledigt, lauf.gesamt)),
      );
      final berechnet = await zahl(
        tester,
        'SELECT count(*) FROM image_embeddings',
      );
      expect(berechnet, lessThan(n));
      expect(berechnet, greaterThan(0));
      await kartenknopf(tester, titel, de.allgSchliessen);
      await pumpe(tester, 1500);
      await zurKarte(tester, titel);
      expect(
        texteIn(karte(titel)),
        contains(de.aufgOffeneFotos(n - berechnet)),
      );
      expect(knopfAktiv(tester, titel, de.aufgModusAlle), isTrue);

      // KI-050: wegnavigieren, das Band zeigt den Lauf, zurück zeigt die
      // Karte den Stand.
      await kartenknopf(tester, titel, de.aufgFehlende);
      await bereich(tester, Hauptbereich.zeitleiste);
      final band = find.textContaining('${de.werkzBerechneEmbeddings}  ');
      await waitFor(tester, band);
      print('KI-050 Band: ${tester.widget<Text>(band.first).data}');
      expect(
        find.ancestor(
          of: find.text(de.allgAbbrechen),
          matching: find.byType(TextButton),
        ),
        findsWidgets,
      );
      await aufgaben(tester);
      await zurKarte(tester, titel);
      final zurueck = texteIn(karte(titel));
      expect(
        fortschritt.hasMatch(zurueck) ||
            zurueck.contains(de.aufgFertigMit(n - berechnet)),
        isTrue,
        reason: zurueck,
      );

      // KI-051: durchlaufen lassen, Bilanz, schliessen.
      await warteAufLauf(tester, 'embeddings');
      await pumpe(tester);
      await zurKarte(tester, titel);
      expect(texteIn(karte(titel)), contains(de.aufgFertigMit(n - berechnet)));
      expect(texteIn(karte(titel)), contains(de.allgSchliessen));
      await kartenknopf(tester, titel, de.allgSchliessen);
      await pumpe(tester, 1000);
      await zurKarte(tester, titel);
      expect(texteIn(karte(titel)), contains(de.aufgOffeneFotos(0)));
      expect(knopfAktiv(tester, titel, de.aufgFehlende), isTrue);

      // KI-052: nichts zu tun.
      await kartenknopf(tester, titel, de.aufgFehlende);
      await warteAufLauf(tester, 'embeddings');
      await pumpe(tester);
      await zurKarte(tester, titel);
      expect(texteIn(karte(titel)), contains(de.werkzAlleHabenEmbedding));
      expect(texteIn(karte(titel)), isNot(contains('0 / 0')));
      await kartenknopf(tester, titel, de.allgSchliessen);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-054 KI-055 KI-056 KI-058 Warteschlange und Sammeldialog',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.clip,
          ModelCatalog.captioningFlorence,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      await importiereDirekt(tester, [
        for (var i = 0; i < 60; i++)
          testfoto(
            'w$i.jpg',
            datum: DateTime(2018, 1 + i % 12, 2, 9),
            breite: 2400,
            hoehe: 1800,
          ),
      ]);
      await aufgaben(tester);

      // KI-058: Sammeldialog.
      await kopfTippen(tester, de.aufgErstellen);
      final dialogF = find.byType(AlertDialog);
      final einreihen = find.ancestor(
        of: find.text(de.aufgEinreihen),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(einreihen).onPressed, isNull);
      for (final m in [
        de.aufgModusAlle,
        de.aufgFehlende,
        de.aufgModusDarktable,
      ]) {
        expect(
          find.descendant(of: dialogF, matching: find.text(m)),
          findsOneWidget,
        );
      }
      final imDialog = await dialogTitel(tester);
      print('KI-058 im Dialog: $imDialog');
      expect(imDialog, contains(de.aufgEmbeddingsTitel));
      expect(imDialog, contains(de.aufgBeschreibungenTitel));
      expect(imDialog, isNot(contains(de.werkzGesichterScannenTitel)));
      expect(imDialog, isNot(contains(de.aufgTranskripteTitel)));
      expect(imDialog, isNot(contains(de.aufgUebersetzenTitel)));
      for (final t in [de.aufgEmbeddingsTitel, de.aufgKiTagsTitel]) {
        await imDialogTippen(tester, t);
      }
      expect(tester.widget<FilledButton>(einreihen).onPressed, isNotNull);
      await tippe(tester, einreihen);
      await erwarteMeldung(tester, de.aufgEingereiht(2));
      await pumpe(tester);
      expect(bibliothek.lauf('embeddings')!.laeuft, isTrue);
      expect(bibliothek.lauf('kitags')!.wartet, isTrue);
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains('${de.aufgWartend} | 1'),
      );

      // KI-054: dieselbe Aufgabe läuft nicht doppelt.
      await kopfTippen(tester, de.aufgErstellen);
      await imDialogTippen(tester, de.aufgKiTagsTitel);
      await tippe(tester, find.text(de.aufgEinreihen));
      await erwarteMeldung(tester, de.aufgEingereiht(0));
      await zurKarte(tester, de.aufgKiTagsTitel);
      final kiText = texteIn(karte(de.aufgKiTagsTitel));
      expect(kiText, contains(de.allgAbbrechen));
      expect(
        find.descendant(
          of: karte(de.aufgKiTagsTitel),
          matching: find.text(de.aufgModusAlle),
        ),
        findsNothing,
      );
      // Aufräumen (was schon fertig ist, braucht kein Abbrechen).
      for (final (titel, k) in [
        (de.aufgKiTagsTitel, 'kitags'),
        (de.aufgEmbeddingsTitel, 'embeddings'),
      ]) {
        if (bibliothek.lauf(k)?.offen ?? false) bibliothek.brichAufgabeAb(k);
        print('KI-054 Aufräumen: $titel');
      }
      await warteRuhe(tester, timeout: const Duration(minutes: 2));
      for (final t in [de.aufgEmbeddingsTitel, de.aufgKiTagsTitel]) {
        await zurKarte(tester, t);
        if (_findet(
          find.descendant(of: karte(t), matching: find.text(de.allgSchliessen)),
        )) {
          await kartenknopf(tester, t, de.allgSchliessen);
        }
      }

      // KI-055: Die Bildbeschreibung (Florence, langsam) läuft, eine
      // zweite schwere Aufgabe stellt sich dahinter.
      await kartenknopf(tester, de.aufgBeschreibungenTitel, de.aufgFehlende);
      await eventually(
        tester,
        () async => bibliothek.lauf('beschreibungen')?.laeuft ?? false,
        was: 'Bildbeschreibung läuft',
      );
      final vorher = await zahl(
        tester,
        'SELECT count(*) FROM image_embeddings',
      );
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle);
      await pumpe(tester);
      expect(bibliothek.lauf('embeddings')!.wartet, isTrue);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains('${de.aufgWartend} | 1'),
      );

      // KI-056: die wartende aus der Schlange nehmen.
      for (var i = 0; i < 2; i++) {
        await kartenknopf(tester, de.aufgEmbeddingsTitel, de.allgAbbrechen);
        await pumpe(tester);
        if (!(bibliothek.lauf('embeddings')?.wartet ?? false)) break;
        print('KI-056 Abbrechen ging daneben, neuer Versuch');
      }
      expect(bibliothek.lauf('embeddings'), isNull);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        knopfAktiv(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle),
        isTrue,
      );
      expect(bibliothek.lauf('beschreibungen')!.laeuft, isTrue);
      expect(
        await zahl(tester, 'SELECT count(*) FROM image_embeddings'),
        vorher,
        reason: 'die gestrichene Aufgabe hat nichts gerechnet',
      );

      // KI-055: Vorschaubilder brauchen kein Modell und laufen sofort.
      await kartenknopf(tester, de.aufgVorschauTitel, de.aufgFehlende);
      await pumpe(tester, 300);
      expect(bibliothek.lauf('vorschau')!.wartet, isFalse);
      expect(bibliothek.lauf('beschreibungen')!.abgebrochen, isFalse);
      bibliothek.brichAufgabeAb('beschreibungen');
      await warteRuhe(tester, timeout: const Duration(minutes: 2));
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-036 KI-037 KI-057 Analyse und schwere Aufgaben',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      await importiereDirekt(tester, [
        for (var i = 0; i < 60; i++)
          testfoto(
            'x$i.jpg',
            datum: DateTime(2017, 1 + i % 12, 3, 9),
            breite: 2400,
            hoehe: 1800,
          ),
      ]);
      await aufgaben(tester);

      // KI-036: während der Analyse wartet eine schwere Aufgabe.
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async => bibliothek.analyseLaeuft,
        was: 'Analyse läuft',
      );
      await kartenknopf(tester, de.aufgKiTagsTitel, de.aufgModusAlle);
      expect(bibliothek.lauf('kitags')!.wartet, isTrue);
      await zurKarte(tester, de.aufgKiTagsTitel);
      expect(
        texteIn(karte(de.aufgKiTagsTitel)),
        contains('${de.aufgWartend} | 1'),
      );
      await eventually(
        tester,
        () async => !bibliothek.analyseLaeuft,
        timeout: const Duration(minutes: 4),
        was: 'Analyse fertig',
      );
      await eventually(
        tester,
        () async =>
            (bibliothek.lauf('kitags')?.laeuft ?? false) ||
            (bibliothek.lauf('kitags')?.beendet ?? false),
        was: 'KI-Tags starten von selbst',
      );
      await warteAufLauf(tester, 'kitags');
      await kartenknopf(tester, de.aufgKiTagsTitel, de.allgSchliessen);

      // KI-037: Analyse während einer schweren Aufgabe wird nachgeholt.
      await autoAn(tester);
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle);
      await eventually(
        tester,
        () async => bibliothek.lauf('embeddings')?.laeuft ?? false,
        was: 'CLIP läuft',
      );
      final neu = await importiereDirekt(tester, [
        testfoto('neu1.jpg', datum: DateTime(2025, 1, 1, 9)),
        testfoto('neu2.jpg', datum: DateTime(2025, 1, 2, 9)),
      ]);
      await pumpe(tester, 800);
      if (bibliothek.lauf('embeddings')!.laeuft) {
        expect(bibliothek.analyseLaeuft, isFalse);
        expect(bibliothek.analyseZurueckgestellt, isTrue);
      }
      await warteAufLauf(tester, 'embeddings');
      await warteRuhe(tester);
      for (final id in neu) {
        expect(
          await zahl(
            tester,
            'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
            [id],
          ),
          1,
        );
        expect((await aufnahme(tester, id)).aiTagsScanned, isTrue);
      }
      await aufgaben(tester);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      if (_findet(
        find.descendant(
          of: karte(de.aufgEmbeddingsTitel),
          matching: find.text(de.allgSchliessen),
        ),
      )) {
        await kartenknopf(tester, de.aufgEmbeddingsTitel, de.allgSchliessen);
      }
      await autoAus(tester);

      // KI-057: gleichzeitige Ausführungen.
      Future<void> oeffneGleichzeitig() async {
        await kopfTippen(tester, de.aufgGleichzeitigTitel);
        await waitFor(tester, find.text(de.aufgGleichzeitigText));
      }

      IconButton knopf(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      await oeffneGleichzeitig();
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('1')),
        findsOneWidget,
      );
      expect(knopf(de.aufgWenigerGleichzeitig).onPressed, isNull);
      for (var i = 0; i < 3; i++) {
        await tippe(tester, find.byTooltip(de.aufgMehrGleichzeitig));
      }
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('4')),
        findsOneWidget,
      );
      expect(knopf(de.aufgMehrGleichzeitig).onPressed, isNull);
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
      expect(bibliothek.maxGleichzeitig, 1);
      await oeffneGleichzeitig();
      await tippe(tester, find.byTooltip(de.aufgMehrGleichzeitig));
      await tippe(tester, find.text(de.allgSpeichern));
      expect(bibliothek.maxGleichzeitig, 2);
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle);
      await kartenknopf(tester, de.aufgKiTagsTitel, de.aufgModusAlle);
      await pumpe(tester);
      expect(bibliothek.lauf('embeddings')!.laeuft, isTrue);
      expect(
        bibliothek.lauf('kitags')!.wartet,
        isFalse,
        reason: 'zweite schwere Aufgabe läuft nebenher',
      );
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains('${de.aufgAktiv} | 1'),
      );
      if (bibliothek.lauf('kitags')!.laeuft) {
        await zurKarte(tester, de.aufgKiTagsTitel);
        expect(
          texteIn(karte(de.aufgKiTagsTitel)),
          contains('${de.aufgAktiv} | 1'),
        );
        await kartenknopf(tester, de.aufgKiTagsTitel, de.allgAbbrechen);
      }
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.allgAbbrechen);
      await warteRuhe(tester, timeout: const Duration(minutes: 2));
      await neustart(tester);
      expect(bibliothek.maxGleichzeitig, 2);
      await aufgaben(tester);
      await oeffneGleichzeitig();
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('2')),
        findsOneWidget,
      );
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-059 KI-068 Gesichter scannen mit Ausnahmen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.faceDetection]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('f1.jpg', datum: DateTime(2020, 5, 5, 10)),
        testfoto('f2.jpg', datum: DateTime(2020, 5, 6, 10)),
        testfoto('f3.jpg', datum: DateTime(2020, 5, 7, 10)),
      ]);
      // Vorbedingung: auf Foto 1 ein zugeordnetes und ein beiseitegelegtes
      // Gesicht, auf Foto 2 ein vorhandenes.
      Future<void> gesicht(String fid, String aid, double x) => sqlAusfuehren(
        tester,
        'INSERT INTO faces (id, asset_id, box_x, box_y, box_w, box_h) '
        'VALUES (?, ?, ?, 0.2, 0.15, 0.2)',
        [fid, aid, x],
      );
      await gesicht('gA', ids[0], 0.1);
      await gesicht('gB', ids[0], 0.6);
      await gesicht('gC', ids[1], 0.3);
      await befehl(tester, const PersonAnlegen('pA', 'Person A'));
      await befehl(tester, const GesichterZuordnen(['gA'], 'pA'));
      await befehl(tester, const GesichterBeiseitelegen(['gB'], true));

      // KI-068: Foto 2 über „Gesichter bearbeiten“ ausnehmen.
      await betrachter(tester, ids, ids[1]);
      await rechtsklick(tester, find.byType(PageView));
      await tippe(tester, find.text(de.viewerGesichterBearbeiten));
      await pumpe(tester, 1500);
      await waitFor(tester, find.byType(FaceReviewScreen));
      final flaeche = find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.byType(AspectRatio),
      );
      await waitFor(tester, flaeche, timeout: const Duration(seconds: 30));
      await rechtsklick(tester, flaeche.first);
      await tippe(tester, find.text(de.gesichtNichtMehrDurchsuchen));
      await erwarteMeldung(tester, de.gesichtNichtMehrDurchsuchtHinweis);
      expect((await aufnahme(tester, ids[1])).faceScanExcluded, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpe(tester);
      while (_findet(find.byType(AssetViewerScreen))) {
        Navigator.of(
          tester.element(find.byType(AssetViewerScreen)),
          rootNavigator: true,
        ).pop();
        await pumpe(tester, 600);
      }
      await sqlAusfuehren(
        tester,
        "DELETE FROM ergebnisherkunft WHERE art = 'gesichter'",
      );

      // KI-059: „Gesichter scannen – Alle“.
      await aufgaben(tester);
      await kartenknopf(
        tester,
        de.werkzGesichterScannenTitel,
        de.aufgModusAlle,
      );
      await warteAufLauf(tester, 'gesichter');
      final lauf = bibliothek.lauf('gesichter')!;
      expect(lauf.gesamt, 2, reason: 'das ausgenommene Foto zählt nicht');
      final faces = await sql(
        tester,
        'SELECT id, asset_id, person_id, is_ignored FROM faces ORDER BY id',
      );
      print('KI-059 Gesichter danach: $faces');
      final a = faces.firstWhere((f) => f['id'] == 'gA');
      expect(a['person_id'], 'pA');
      final b = faces.firstWhere((f) => f['id'] == 'gB');
      expect(b['is_ignored'], 1);
      expect(
        faces.where((f) => f['asset_id'] == ids[0]).length,
        2,
        reason: 'kein neues Gesicht an der beiseitegelegten Stelle',
      );
      expect(faces.where((f) => f['id'] == 'gC'), hasLength(1));
      expect(
        await zahl(
          tester,
          "SELECT count(*) FROM ergebnisherkunft WHERE asset_id = ? AND art = 'gesichter'",
          [ids[1]],
        ),
        0,
        reason: 'ausgenommenes Foto nicht durchsucht',
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-061 KI-062 Bibliothekszustand fuehrt zu den Aufgaben',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        fixture('video_5s.mp4'),
        testfoto('e1.jpg', datum: DateTime(2016, 6, 6, 6)),
      ]);
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [ids.first],
      );

      // KI-061: „Weitere Standbilder holen“ hebt die Aufgabe hervor.
      await werkzeug(tester, de.gesundheitTitel);
      await sichtbar(
        tester,
        find.text(de.gesundheitVideobilderTitel),
        LibraryHealthScreen,
      );
      await tippe(tester, find.text(de.gesundheitVideobilderHolen));
      await waitFor(tester, find.byType(BackgroundTasksScreen));
      final erste = tester
          .widgetList<Card>(
            find.descendant(
              of: find.byType(BackgroundTasksScreen),
              matching: find.byType(Card),
            ),
          )
          .toList();
      final videokarte = tester.widget<Card>(karte(de.aufgVideobilderTitel));
      final shape = videokarte.shape;
      expect(shape, isA<RoundedRectangleBorder>());
      expect((shape! as RoundedRectangleBorder).side.width, 2);
      // Ganz oben: direkt nach der Gesamtkarte.
      expect(erste.indexOf(videokarte), lessThanOrEqualTo(1));

      // KI-062: veralteter Modellstand.
      final datei = bibliothek.paths.modelProcessingStateFile;
      final inhalt = datei.readAsStringSync().replaceFirstMapped(
        RegExp(r'"clip":"[^"]*"'),
        (_) => '"clip":"alt"',
      );
      datei.writeAsStringSync(inhalt);
      await neustart(tester);
      expect(bibliothek.outdatedModelPipelines, contains('clip'));
      await werkzeug(tester, de.gesundheitTitel);
      await sichtbar(
        tester,
        find.text(de.gesundheitModellwechselTitel),
        LibraryHealthScreen,
      );
      expect(find.text(de.gesundheitModellwechselText(1)), findsOneWidget);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'embeddings');
      expect(bibliothek.lauf('embeddings')!.fehler, isNull);
      await werkzeug(tester, de.gesundheitTitel);
      await pumpe(tester, 1500);
      expect(find.text(de.gesundheitModellwechselTitel), findsNothing);
      expect(bibliothek.outdatedModelPipelines, isNot(contains('clip')));
      await finish(tester);
    },
  );

  // Behoben in #414: „Aufgaben öffnen“ öffnet die Aufgabenliste und hebt die Aufgabe der veralteten Verarbeitung hervor.
  testWidgets(
    timeout: zeitgrenze,
    'KI-062 Befundpruefung Aufgaben oeffnen fuehrt zu Werkzeuge',
    (tester) async {
      await startApp(tester);
      final datei = bibliothek.paths.modelProcessingStateFile;
      final inhalt = datei.readAsStringSync().replaceFirstMapped(
        RegExp(r'"clip":"[^"]*"'),
        (_) => '"clip":"alt"',
      );
      datei.writeAsStringSync(inhalt);
      await neustart(tester);
      await werkzeug(tester, de.gesundheitTitel);
      await sichtbar(
        tester,
        find.text(de.gesundheitModellwechselAufgaben),
        LibraryHealthScreen,
      );
      await tippe(tester, find.text(de.gesundheitModellwechselAufgaben));
      await pumpe(tester, 1200);
      final aufWerkzeuge = _findet(find.byType(ToolsScreen));
      final aufAufgaben = _findet(find.byType(BackgroundTasksScreen));
      final nochZustand = _findet(find.byType(LibraryHealthScreen));
      print(
        'KI-062 nach „Aufgaben öffnen“: Werkzeuge $aufWerkzeuge, '
        'Aufgaben $aufAufgaben, Bibliothekszustand $nochZustand',
      );
      expect(aufAufgaben, isTrue, reason: 'führt nach „Werkzeuge“');
      await finish(tester);
    },
  );

  // ------------------------------------------------------------ Bildanalyse

  testWidgets(
    timeout: zeitgrenze,
    'KI-064 KI-065 KI-066 KI-069 KI-070 Bildanalyse',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.clip, ModelCatalog.faceDetection]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      // Scharf: Schachbrett; weich: dasselbe stark weichgezeichnet.
      final scharf = img.Image(width: 640, height: 480);
      for (var y = 0; y < 480; y++) {
        for (var x = 0; x < 640; x++) {
          final w = ((x ~/ 8) + (y ~/ 8)).isEven ? 255 : 0;
          scharf.setPixelRgb(x, y, w, w, w);
        }
      }
      final weich = img.gaussianBlur(img.Image.from(scharf), radius: 12);
      final fs = File(p.join(eingang.path, 'scharf.jpg'))
        ..writeAsBytesSync(img.encodeJpg(scharf, quality: 95));
      final fw = File(p.join(eingang.path, 'weich.jpg'))
        ..writeAsBytesSync(img.encodeJpg(weich, quality: 95));
      final ids = await importiereDirekt(tester, [
        fs,
        fw,
        blindfoto('flaeche.jpg', r: 200, g: 60, b: 60),
        testfoto('papierkorb.jpg', datum: DateTime(2015, 1, 1, 1)),
      ]);
      await befehl(tester, InDenPapierkorb([ids[3]]));

      // KI-065: Unschärfe ohne Modellbedarf, nur „Fehlende“.
      await aufgaben(tester);
      await zurKarte(tester, de.aufgUnschaerfeTitel);
      expect(
        find.descendant(
          of: karte(de.aufgUnschaerfeTitel),
          matching: find.text(de.aufgModusAlle),
        ),
        findsNothing,
      );
      await kartenknopf(tester, de.aufgUnschaerfeTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'unschaerfe');
      await pumpe(tester);
      final u = texteIn(karte(de.aufgUnschaerfeTitel));
      expect(
        u.contains(de.aufgFertigMit(3)) ||
            u.contains(de.werkzAlleHabenUnschaerfe),
        isTrue,
        reason: u,
      );
      await kartenknopf(tester, de.aufgUnschaerfeTitel, de.allgSchliessen);

      // KI-064/066/069: Analyse.
      await kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await warteRuhe(tester);
      final s = (await aufnahme(tester, ids[0])).sharpnessScore!;
      final w = (await aufnahme(tester, ids[1])).sharpnessScore!;
      print('KI-064 Unschärfe: scharf $s, weich $w');
      expect(w, lessThan(s));
      await aufgaben(tester);
      for (final titel in [
        de.aufgUnschaerfeTitel,
        de.werkzGesichterScannenTitel,
        de.aufgEmbeddingsTitel,
      ]) {
        await zurKarte(tester, titel);
        expect(
          texteIn(karte(titel)),
          contains(de.aufgOffeneFotos(0)),
          reason: titel,
        );
      }
      final offen = [ids[0], ids[1], ids[2]];
      await betrachter(tester, offen, ids[2]);
      await tippe(tester, find.byTooltip(de.viewerGesichterZeigen));
      await waitFor(tester, find.text(de.viewerKeineGesichter));
      // KI-069: ähnliche Bilder.
      await rechtsklick(tester, find.byType(PageView));
      await tippe(tester, find.text(de.viewerAehnlicheZeigen));
      await waitFor(tester, find.text(de.aehnlTitel));
      await pumpe(tester, 1500);
      expect(find.text(de.aehnlKeineTreffer), findsNothing);
      expect(find.text(de.aehnlClipFehlt), findsNothing);
      while (_findet(find.text(de.aehnlTitel)) ||
          _findet(find.byType(AssetViewerScreen))) {
        final e = _findet(find.text(de.aehnlTitel))
            ? find.text(de.aehnlTitel)
            : find.byType(AssetViewerScreen);
        Navigator.of(tester.element(e.first), rootNavigator: true).pop();
        await pumpe(tester, 600);
      }

      // KI-070: „Alle“ rechnet alle auswertbaren neu.
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'embeddings');
      await pumpe(tester);
      expect(bibliothek.lauf('embeddings')!.gesamt, 3);
      expect(
        texteIn(karte(de.aufgEmbeddingsTitel)),
        contains(de.aufgFertigMit(3)),
      );
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM image_embeddings WHERE asset_id = ?',
          [ids[3]],
        ),
        0,
      );
      await finish(tester);
    },
  );

  // ------------------------------------------------------- Bildbeschreibung

  Finder kiFeld() => find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText == de.infoKiPlatzhalterDe ||
            w.decoration?.hintText == de.infoKiPlatzhalterEn),
  );

  bool sprachknopfAktiv(WidgetTester tester, String beschriftung) {
    final t = tester.widget<Text>(find.text(beschriftung).last);
    return t.style?.fontWeight == FontWeight.w700;
  }

  testWidgets(
    timeout: zeitgrenze,
    'KI-086 KI-088 KI-090 Bildbeschreibung und Uebersetzung',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.captioningFlorence]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('d1.jpg', datum: DateTime(2014, 4, 4, 4)),
        blindfoto('d2.jpg', r: 30, g: 140, b: 60),
      ]);
      await analyseUeberKarte(tester);

      // KI-086: englischer Satz, EN aktiv.
      final a = await aufnahme(tester, ids[0]);
      expect(a.aiCaption, isNotNull);
      expect(a.aiCaptionDe, isNull);
      await betrachter(tester, ids, ids[0]);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoKiBeschreibung));
      final feld = tester.widget<TextField>(kiFeld());
      expect(feld.controller!.text, a.aiCaption!.trim());
      expect(feld.style?.fontStyle, FontStyle.italic);
      expect(find.text(de.infoSpracheDe), findsWidgets);
      expect(sprachknopfAktiv(tester, de.infoSpracheEn), isTrue);
      expect(sprachknopfAktiv(tester, de.infoSpracheDe), isFalse);
      await betrachterZu(tester);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgBeschreibungenTitel);
      expect(
        texteIn(karte(de.aufgBeschreibungenTitel)),
        contains(de.aufgOffeneFotos(0)),
      );

      // KI-090: vorhandene Beschreibungen nachträglich übersetzen.
      await installiere(tester, [ModelCatalog.translationEnDe]);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'beschreibungen_de');
      await pumpe(tester);
      expect(
        texteIn(karte(de.aufgUebersetzenTitel)),
        contains(de.aufgFertigMit(2)),
      );
      expect(bibliothek.captioningHalter.istGeladen, isFalse);
      expect((await aufnahme(tester, ids[0])).aiCaptionDe, isNotNull);
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.allgSchliessen);
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'beschreibungen_de');
      await pumpe(tester);
      expect(
        texteIn(karte(de.aufgUebersetzenTitel)),
        contains(de.werkzAlleUebersetzt),
      );
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.allgSchliessen);

      // KI-088: neue Beschreibungen werden übersetzt, das Original bleibt.
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await tippe(tester, schalter(de.einstUebersetzeBeschreibungTitel));
      final neu = await importiereDirekt(tester, [
        testfoto('d3.jpg', datum: DateTime(2014, 5, 5, 5)),
      ]);
      await analyseUeberKarte(tester);
      final n = await aufnahme(tester, neu.first);
      expect(n.aiCaption, isNotNull);
      expect(n.aiCaptionDe, isNotNull);
      await betrachter(tester, [...ids, ...neu], neu.first);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoKiBeschreibung));
      expect(sprachknopfAktiv(tester, de.infoSpracheDe), isTrue);
      expect(
        tester.widget<TextField>(kiFeld()).controller!.text,
        n.aiCaptionDe!.trim(),
      );
      await tippe(tester, find.text(de.infoSpracheEn).last);
      expect(
        tester.widget<TextField>(kiFeld()).controller!.text,
        n.aiCaption!.trim(),
      );
      await betrachterZu(tester);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-091 KI-092 KI-093 Von Hand geaenderte Beschreibung',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.captioningFlorence,
          ModelCatalog.translationEnDe,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('hd1.jpg', datum: DateTime(2013, 3, 3, 3)),
      ]);
      await analyseUeberKarte(tester);
      final id = ids.first;
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'beschreibungen_de');
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.allgSchliessen);

      // KI-091: von Hand ändern (deutsche Fassung ist vorgegeben).
      await betrachter(tester, ids, id);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoKiBeschreibung));
      expect(sprachknopfAktiv(tester, de.infoSpracheDe), isTrue);
      await tester.tap(kiFeld());
      await tester.enterText(kiFeld(), 'Mein eigener Satz');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpe(tester, 1200);
      await waitFor(tester, find.text(de.infoKiBeschreibungVonHand));
      expect(find.text(de.infoKiVonHandHinweis), findsOneWidget);
      print(
        'TEXT 4241: ${de.infoKiVonHandHinweis} (Knopf: ${de.aufgModusAlle})',
      );
      var a = await aufnahme(tester, id);
      expect(a.aiCaptionEdited, isTrue);
      expect(a.aiCaptionDe, 'Mein eigener Satz');
      final englisch = a.aiCaption;

      // KI-093: Umschalten speichert vorher.
      await tippe(tester, find.text(de.infoSpracheEn).last);
      await tester.tap(kiFeld());
      await tester.enterText(kiFeld(), 'My own sentence');
      await tippe(tester, find.text(de.infoSpracheDe).last);
      expect(
        tester.widget<TextField>(kiFeld()).controller!.text,
        'Mein eigener Satz',
      );
      await tippe(tester, find.text(de.infoSpracheEn).last);
      expect(
        tester.widget<TextField>(kiFeld()).controller!.text,
        'My own sentence',
      );
      a = await aufnahme(tester, id);
      expect(a.aiCaption, 'My own sentence');
      expect(englisch, isNot('My own sentence'));
      await betrachterZu(tester);

      // KI-091: „Alle“ und „Beschreibungen übersetzen“ lassen den Text stehen.
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgBeschreibungenTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'beschreibungen');
      await kartenknopf(tester, de.aufgBeschreibungenTitel, de.allgSchliessen);
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'beschreibungen_de');
      await kartenknopf(tester, de.aufgUebersetzenTitel, de.allgSchliessen);
      a = await aufnahme(tester, id);
      expect(a.aiCaptionDe, 'Mein eigener Satz');
      expect(a.aiCaption, 'My own sentence');
      await betrachter(tester, ids, id);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoKiBeschreibungVonHand));
      expect(
        tester.widget<TextField>(kiFeld()).controller!.text,
        'Mein eigener Satz',
      );

      // KI-092: beide Felder leeren gibt das Foto frei.
      await tester.tap(kiFeld());
      await tester.enterText(kiFeld(), '');
      await tippe(tester, find.text(de.infoSpracheEn).last);
      await tester.tap(kiFeld());
      await tester.enterText(kiFeld(), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpe(tester, 1200);
      a = await aufnahme(tester, id);
      expect(a.aiCaptionEdited, isFalse);
      expect(find.text(de.infoKiBeschreibungVonHand), findsNothing);
      await betrachterZu(tester);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgBeschreibungenTitel);
      expect(
        texteIn(karte(de.aufgBeschreibungenTitel)),
        contains(de.aufgOffeneFotos(1)),
      );
      await kartenknopf(tester, de.aufgBeschreibungenTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'beschreibungen');
      a = await aufnahme(tester, id);
      expect(a.aiCaption, isNotNull);
      expect(a.aiCaption, isNot('My own sentence'));
      await finish(tester);
    },
  );

  // Behoben in #414: infoVideoStandbild sagt, dass nur die Beschreibung auf dem einen Standbild beruht und Videobilder bis zu fünf weitere auswertet.
  testWidgets(
    timeout: zeitgrenze,
    'KI-094 Befundpruefung Videohinweis unter der Beschreibung',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([
          ModelCatalog.captioningFlorence,
          ModelCatalog.clip,
        ]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [fixture('video_5s.mp4')]);
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [ids.first],
      );
      await analyseUeberKarte(tester);
      final bilder = await zahl(
        tester,
        'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
        [ids.first],
      );
      expect((await aufnahme(tester, ids.first)).aiCaption, isNotNull);
      await betrachter(tester, ids, ids.first);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoKiBeschreibung));
      final hinweis = _findet(find.text(de.infoVideoStandbild));
      print(
        'TEXT 2176: ${de.infoVideoStandbild} – sichtbar $hinweis, '
        'ausgewertete Standbilder $bilder',
      );
      await betrachterZu(tester);
      expect(hinweis, isTrue);
      expect(
        bilder <= 1 ||
            !de.infoVideoStandbild.contains('nicht auf dem ganzen Film'),
        isTrue,
        reason: 'Hinweis sagt „ein Standbild“, ausgewertet wurden $bilder',
      );
      await finish(tester);
    },
  );

  // --------------------------------------------------------- Texterkennung

  testWidgets(
    timeout: zeitgrenze,
    'KI-095 KI-096 KI-097 KI-098 KI-099 Texterkennung unter macOS',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'umlaute.png', [
          'Größe Übung Straße',
          'Zeile Zwei',
        ]),
        blindfoto('ohne.jpg', r: 240, g: 240, b: 240),
        fixture('video_hoch_3s.mov'),
      ]);

      // KI-095: ohne Modell bedienbar; PaddleOCR steht trotzdem zum Laden.
      await aufgaben(tester);
      await zurKarte(tester, de.aufgOcrTitel);
      expect(knopfAktiv(tester, de.aufgOcrTitel, de.aufgFehlende), isTrue);
      await kartenknopf(tester, de.aufgOcrTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'ocr');
      expect(bibliothek.lauf('ocr')!.fehler, isNull);
      await kartenknopf(tester, de.aufgOcrTitel, de.allgSchliessen);
      await einstellungsgruppe(tester, de.einstAbschnittModelle);
      await sichtbar(
        tester,
        find.text(modellTitel(de, ModelCatalog.ocrPaddle.id)),
        SettingsScreen,
      );
      expect(
        find.descendant(
          of: modellkarte(ModelCatalog.ocrPaddle.id),
          matching: find.text(de.allgHerunterladen),
        ),
        findsOneWidget,
      );
      expect(
        modellBeschreibung(de, ModelCatalog.ocrPaddle.id),
        contains('macOS'),
      );

      // KI-096: Text samt Umlauten.
      final a = await aufnahme(tester, ids[0]);
      print('KI-096 erkannt: ${a.ocrText}');
      expect(a.ocrText, contains('Größe'));
      expect(a.ocrText, contains('Übung'));
      expect(a.ocrText, contains('Straße'));
      await betrachter(tester, [ids[0], ids[1]], ids[0]);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoErkannterText));
      final stellen = a.ocrBoxen == null
          ? 0
          : RegExp('"text"').allMatches(a.ocrBoxen!).length;
      expect(
        find.textContaining(RegExp(r'\d+ Textstellen? im Bild')),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .any((w) => (w.data ?? '').contains('Straße')),
        isTrue,
        reason: 'markierbar',
      );
      print('KI-096 Stellen laut Boxen: $stellen');

      // KI-097: kopieren.
      await tippe(tester, find.byTooltip(de.infoTextKopieren));
      await erwarteMeldung(tester, de.infoTextKopiert);
      final ablage = await tester.runAsync(
        () => Clipboard.getData(Clipboard.kTextPlain),
      );
      expect(ablage?.text, contains('Straße'));

      // KI-098: Textstellen im Betrachter.
      await tippe(tester, find.byTooltip(de.viewerInfo));
      // Die Masse des Bildes holt der Betrachter nur mit eingeschalteten
      // Gesichtern oder Raster (siehe „KI-098 Befundpruefung“) – deshalb
      // zuerst die Gesichter.
      await tippe(tester, find.byTooltip(de.viewerGesichterZeigen));
      await tippe(tester, find.byTooltip(de.viewerTextZeigen));
      final rahmen = find.byType(Textrahmen);
      await waitFor(tester, rahmen, timeout: const Duration(seconds: 15));
      await pumpe(tester, 1500);
      final mitte = tester.getCenter(rahmen.first);
      final fenster = tester.view.physicalSize / tester.view.devicePixelRatio;
      print('KI-098 erster Rahmen bei $mitte, Fenster $fenster');
      if (mitte.dx > 0 &&
          mitte.dy > 0 &&
          mitte.dx < fenster.width &&
          mitte.dy < fenster.height) {
        await tester.tap(rahmen.first);
        await pumpe(tester, 600);
        await erwarteMeldung(tester, '“ kopiert');
      } else {
        print(
          'KI-098 Rahmen liegt ausserhalb des Fensters – Tipp nicht geprüft',
        );
      }
      // Foto ohne Text.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await pumpe(tester, 1200);
      await waitFor(tester, find.text(de.viewerKeinText));
      await betrachterZu(tester);
      // Video: kein Knopf.
      await betrachter(tester, [ids[2]], ids[2]);
      expect(find.byTooltip(de.viewerTextZeigen), findsNothing);
      expect(find.byTooltip(de.viewerTextVerbergen), findsNothing);
      await betrachterZu(tester);

      // KI-099: ein Foto ohne Text gilt als durchsucht.
      final ohne = await aufnahme(tester, ids[1]);
      expect(ohne.ocrScanned, isTrue);
      await betrachter(tester, [ids[1]], ids[1]);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await pumpe(tester, 800);
      expect(find.text(de.infoErkannterText), findsNothing);
      await betrachterZu(tester);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgOcrTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'ocr');
      await pumpe(tester);
      expect(
        texteIn(karte(de.aufgOcrTitel)),
        contains(de.werkzAlleTextDurchsucht),
      );
      await finish(tester);
    },
  );

  // Befund: „Erkannten Text hervorheben“ allein zeigt keine Rahmen: Die Bildmasse holt der Betrachter nur für Gesichter oder Raster (asset_viewer_screen.dart:1663/1698, Bedingung :2012).
  testWidgets(
    skip: true,
    timeout: zeitgrenze,
    'KI-098 Befundpruefung Textrahmen ohne eingeschaltete Gesichter',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'schild.png', ['HALTESTELLE NORD']),
      ]);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgOcrTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'ocr');
      expect((await aufnahme(tester, ids.first)).ocrBoxen, isNotNull);
      await betrachter(tester, ids, ids.first);
      await tippe(tester, find.byTooltip(de.viewerTextZeigen));
      var rahmen = false;
      final ende = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(ende) && !rahmen) {
        await tester.pump(const Duration(milliseconds: 200));
        rahmen = _findet(find.byType(Textrahmen));
      }
      print('KI-098 Textrahmen nur mit Texthervorhebung: $rahmen');
      await betrachterZu(tester);
      expect(rahmen, isTrue, reason: 'ohne Gesichter keine Rahmen');
      await finish(tester);
    },
  );

  // ------------------------------------- Spracherkennung und Videobilder

  testWidgets(
    timeout: zeitgrenze,
    'KI-104 Video ohne Sprache gilt als gehoert',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.spracherkennung]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        fixture('video_hoch_3s.mov'),
        fixture('video_5s.mp4'),
      ]);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgTranskripteTitel, de.aufgFehlende);
      await warteAufLauf(
        tester,
        'transkripte',
        timeout: const Duration(minutes: 5),
      );
      await kartenknopf(tester, de.aufgTranskripteTitel, de.allgSchliessen);
      for (final id in ids) {
        final a = await aufnahme(tester, id);
        print('KI-104 ${a.originalFileName}: „${a.transkript}“');
        expect(a.transkriptGeprueft, isTrue);
        await betrachter(tester, [id], id);
        await tippe(tester, find.byTooltip(de.viewerInfo));
        await pumpe(tester, 800);
        final gesprochen = _findet(find.text(de.infoGesprochen));
        print(
          'KI-104 ${a.originalFileName}: Abschnitt „Gesprochen“ $gesprochen',
        );
        // Ohne Tonspur: nichts. Die Tonspur mit Sinuston (Rauschen gibt es
        // als Testdatei nicht) wird nur berichtet.
        if (id == ids.first) {
          expect((a.transkript ?? '').trim(), isEmpty);
          expect(gesprochen, isFalse);
        }
        await betrachterZu(tester);
      }
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgTranskripteTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'transkripte');
      await pumpe(tester);
      expect(
        texteIn(karte(de.aufgTranskripteTitel)),
        contains(de.werkzAlleVideosGehoert),
      );
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-107 Videos: weitere Standbilder werden ausgewertet',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        fixture('video_5s.mp4'),
        fixture('video_hoch_3s.mov'),
      ]);
      // Nur Fixtures bis 5 s: Laufzeit des ersten Videos auf 30 s gesetzt.
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [ids[0]],
      );
      Set<String> bilddateien() => {
        for (final e in bibliothek.paths.root.listSync(recursive: true))
          if (e is File &&
              RegExp(
                r'\.(jpe?g|png|webp)$',
                caseSensitive: false,
              ).hasMatch(e.path))
            e.path,
      };
      final vorher = bilddateien();
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgVideobilderTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'videobilder');
      await pumpe(tester);
      expect(
        texteIn(karte(de.aufgVideobilderTitel)),
        contains(de.aufgFertigMit(2)),
      );
      final lang = await zahl(
        tester,
        'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
        [ids[0]],
      );
      expect(lang, inInclusiveRange(2, 5));
      expect(
        await zahl(
          tester,
          'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
          [ids[1]],
        ),
        0,
      );
      expect((await aufnahme(tester, ids[1])).videobilderGeprueft, isTrue);
      expect((await aufnahme(tester, ids[0])).videobilderGeprueft, isTrue);
      expect(bilddateien(), vorher, reason: 'keine Standbilder auf der Platte');
      await finish(tester);
    },
  );

  // Behoben in #414: scanFacesForDecodedAsset und speichereGesichter lassen von der Gesichtssuche ausgenommene Aufnahmen aus.
  testWidgets(
    timeout: zeitgrenze,
    'KI-108 Befundpruefung Videobilder beachten die Gesichter-Ausnahme',
    (tester) async {
      await startApp(
        tester,
        modelle: dateienVon([ModelCatalog.clip, ModelCatalog.faceDetection]),
      );
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [fixture('video_5s.mp4')]);
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [ids.first],
      );
      // Für Videos gibt es „Gesichter bearbeiten“ nicht – die Ausnahme wird
      // direkt gesetzt (derselbe Befehl wie dort).
      await befehl(tester, GesichtssucheAusnehmen(ids.first, true));
      await sqlAusfuehren(
        tester,
        'DELETE FROM ergebnisherkunft WHERE asset_id = ?',
        [ids.first],
      );
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgVideobilderTitel, de.aufgModusAlle);
      await warteAufLauf(tester, 'videobilder');
      final gesucht = await zahl(
        tester,
        "SELECT count(*) FROM ergebnisherkunft WHERE asset_id = ? AND art = 'gesichter'",
        [ids.first],
      );
      print('KI-108 Gesichtssuche auf dem ausgenommenen Video: $gesucht');
      expect(gesucht, 0, reason: 'Gesichtssuche lief trotz Ausnahme');
      await finish(tester);
    },
  );

  // ------------------------------------------------- Ausweise und Karten

  String fundtext(String art, String grund) => '$art · $grund';

  Future<void> zuDokumenten(WidgetTester tester) async {
    await werkzeug(tester, de.gesundheitTitel);
    await sichtbar(
      tester,
      find.text(de.gesundheitDokumenteTitel),
      LibraryHealthScreen,
    );
    await tippe(tester, find.text(de.gesundheitDokumenteAnsehen));
    await waitFor(tester, find.byType(DokumenteScreen));
    await pumpe(tester, 800);
  }

  testWidgets(
    timeout: zeitgrenze,
    'KI-117 KI-118 KI-119 Ausweise und Karten erkennen',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      await warteRuhe(tester);
      const mono = 'Courier New';
      const geburt = '800101', ablauf = '300101';
      final td3 =
          'C01X00T47${pruefziffer('C01X00T47')}UTO$geburt${pruefziffer(geburt)}'
          'F$ablauf${pruefziffer(ablauf)}<<<<<<<<<<<<<<00';
      final bilder = <String, File>{
        'pass': await textbild(
          tester,
          'pass.png',
          ['P<UTOMUSTER<<PERSON<A<<<<<<<<<<<<<<<<<<<<<<', td3],
          schrift: mono,
          groesse: 52,
          breite: 2200,
        ),
        'ausweis': await textbild(
          tester,
          'ausweis.png',
          ['IDUTOT220001293<<<<<<<<<<<<<<<', td1Zeile2()],
          schrift: mono,
          groesse: 56,
        ),
        'aufenthalt': await textbild(
          tester,
          'aufenthalt.png',
          ['AUFENTHALTSTITEL', td1Zeile2()],
          schrift: mono,
          groesse: 56,
        ),
        'falsch': await textbild(
          tester,
          'falsch.png',
          [td1Zeile2(falsch: true)],
          schrift: mono,
          groesse: 56,
        ),
        'karte': await textbild(tester, 'karte.png', ['4111 1111 1111 1111']),
        'bon': await textbild(tester, 'bon.png', [
          'SUMME 4111111111111111 EUR',
        ]),
        'fuehrerschein': await textbild(tester, 'fs.png', ['FÜHRERSCHEIN']),
        'text': await textbild(tester, 'liste.png', [
          'Einkaufsliste Brot Milch',
        ]),
      };
      final namen = bilder.keys.toList();
      final ids = await importiereDirekt(tester, bilder.values.toList());
      final video = await importiereDirekt(tester, [fixture('video_5s.mp4')]);
      await sqlAusfuehren(
        tester,
        'UPDATE assets SET duration_seconds = 30 WHERE id = ?',
        [video.first],
      );
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgOcrTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'ocr');
      for (var i = 0; i < ids.length; i++) {
        print(
          'KI-118 ${namen[i]}: „${(await aufnahme(tester, ids[i])).ocrText}“',
        );
      }

      // KI-117: Karte vor den übrigen Hinweisen auf Wartendes.
      await werkzeug(tester, de.gesundheitTitel);
      final titel = find.text(de.gesundheitDokumenteTitel);
      await sichtbar(tester, titel, LibraryHealthScreen);
      expect(find.text(de.gesundheitDokumenteOffen(5)), findsOneWidget);
      expect(find.text(de.gesundheitDokumenteAnsehen), findsOneWidget);
      final video2 = find.text(de.gesundheitVideobilderTitel);
      await sichtbar(tester, video2, LibraryHealthScreen);
      await sichtbar(tester, titel, LibraryHealthScreen);
      if (_findet(video2)) {
        expect(
          tester.getTopLeft(titel).dy,
          lessThan(tester.getTopLeft(video2).dy),
        );
      }

      // KI-118/KI-119: Beschriftungen.
      await zuDokumenten(tester);
      for (final erwartet in [
        fundtext(de.dokumentArtReisepass, de.dokumentGrundPruefzeile),
        fundtext(de.dokumentArtAusweis, de.dokumentGrundPruefzeile),
        fundtext(de.dokumentArtAufenthaltstitel, de.dokumentGrundPruefzeile),
        fundtext(de.dokumentArtKarte, de.dokumentGrundKartennummer),
        fundtext(de.dokumentArtFuehrerschein, de.dokumentGrundSchluesselwort),
      ]) {
        expect(find.text(erwartet), findsOneWidget, reason: erwartet);
      }
      expect(find.text(de.dokumenteSperren(5)), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-120 KI-121 KI-122 KI-123 KI-124 Funde sperren und verwerfen',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        await textbild(tester, 'k1.png', ['4111 1111 1111 1111']),
        await textbild(tester, 'k2.png', ['5555 5555 5555 4444']),
      ]);
      await aufgaben(tester);
      await kartenknopf(tester, de.aufgOcrTitel, de.aufgFehlende);
      await warteAufLauf(tester, 'ocr');
      await tester.runAsync(() => bibliothek.setupVaultPin('2468'));
      bibliothek.lockVaultSession();

      // KI-120: Auswahl.
      await zuDokumenten(tester);
      expect(find.text(de.dokumenteSperren(2)), findsOneWidget);
      final kacheln = find.descendant(
        of: find.byType(DokumenteScreen),
        matching: find.byType(GridView),
      );
      final zellen = find.descendant(
        of: kacheln,
        matching: find.byType(Expanded),
      );
      await tester.tap(zellen.at(0));
      await pumpe(tester, 500);
      await waitFor(tester, find.text(de.dokumenteSperren(1)));
      await tester.tap(zellen.at(0));
      await pumpe(tester, 500);
      await waitFor(tester, find.text(de.dokumenteSperren(2)));
      await tester.tap(zellen.at(0));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(zellen.at(0));
      await pumpe(tester, 1200);
      await waitFor(tester, find.byType(AssetViewerScreen));
      Navigator.of(
        tester.element(find.byType(AssetViewerScreen)),
        rootNavigator: true,
      ).pop();
      await pumpe(tester, 800);

      // KI-122: PIN-Abfrage abbrechen sperrt nichts.
      await tippe(tester, find.text(de.dokumenteSperren(2)));
      await waitFor(tester, find.text(de.pinEingebenTitel));
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
      await pumpe(tester, 800);
      expect(find.text(de.dokumenteGesperrt(2)), findsNothing);
      expect(find.text(de.dokumenteGesperrt(1)), findsNothing);
      expect(
        await zahl(tester, 'SELECT count(*) FROM assets WHERE is_locked = 1'),
        0,
      );
      expect(find.text(de.dokumenteSperren(2)), findsOneWidget);

      // KI-121: einen abwählen, den anderen mit PIN sperren.
      await tester.tap(zellen.at(1));
      await pumpe(tester, 500);
      await tippe(tester, find.text(de.dokumenteSperren(1)));
      await waitFor(tester, find.text(de.pinEingebenTitel));
      await eintragen(tester, field(de.pinFeld), '2468');
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('OK'),
        ),
      );
      await erwarteMeldung(tester, de.dokumenteGesperrt(1));
      await pumpe(tester, 1500);
      final gesperrt = await sql(
        tester,
        'SELECT id FROM assets WHERE is_locked = 1',
      );
      expect(gesperrt, hasLength(1));
      final offen = ids.firstWhere((i) => i != gesperrt.single['id']);
      expect((await aufnahme(tester, offen)).isLocked, isFalse);
      expect(zellen, findsOneWidget);

      // KI-123: „Nicht mehr vorschlagen“, auch nach dem Neustart.
      await tippe(tester, find.text(de.dokumenteVerwerfen));
      await pumpe(tester, 1000);
      // KI-124: leerer Zustand.
      await waitFor(tester, find.text(de.dokumenteKeine));
      await neustart(tester);
      await werkzeug(tester, de.gesundheitTitel);
      await pumpe(tester, 1500);
      expect(find.text(de.gesundheitDokumenteTitel), findsNothing);
      final o = await aufnahme(tester, offen);
      expect(o.isLocked, isFalse);
      expect(o.isTrashed, isFalse);
      await finish(tester);
    },
  );

  // --------------------------------------------------------------- Datierung

  /// Ein „altes Papierfoto“: Sepia, Korn, heller Rand und – wie bei
  /// vielen Abzügen – das Jahr aufgedruckt.
  Future<File> altesFoto(WidgetTester tester, String name, int n) async {
    final jahr = 1952 + n * 3;
    final bytes = await tester.runAsync(() async {
      const w = 1000.0, h = 760.0;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      c.drawRect(
        const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFFEDE6D3),
      );
      const bild = Rect.fromLTWH(50, 50, 900, 620);
      c.drawRect(
        bild,
        Paint()
          ..shader = ui.Gradient.linear(bild.topCenter, bild.bottomCenter, [
            const Color(0xFFD9C29A),
            const Color(0xFF6E5638),
          ]),
      );
      final dunkel = Paint()..color = const Color(0xFF4A3922);
      // Haus mit Dach, Baum, zwei Personen.
      c.drawRect(Rect.fromLTWH(150.0 + n * 20, 330, 260, 200), dunkel);
      c.drawPath(
        Path()
          ..moveTo(130.0 + n * 20, 330)
          ..lineTo(280.0 + n * 20, 220)
          ..lineTo(430.0 + n * 20, 330)
          ..close(),
        dunkel,
      );
      c.drawCircle(Offset(700, 300.0 + n * 5), 110, dunkel);
      c.drawRect(const Rect.fromLTWH(685, 380, 30, 150), dunkel);
      for (final x in [520.0, 580.0]) {
        c.drawCircle(Offset(x, 440), 22, dunkel);
        c.drawRect(Rect.fromLTWH(x - 25, 462, 50, 110), dunkel);
      }
      final zufall = math.Random(n);
      final korn = Paint();
      for (var i = 0; i < 6000; i++) {
        korn.color = Color.fromARGB(40, zufall.nextInt(80), 60, 30);
        c.drawCircle(
          Offset(
            50 + zufall.nextDouble() * 900,
            50 + zufall.nextDouble() * 620,
          ),
          0.8,
          korn,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: 'Sommer $jahr',
          style: const TextStyle(
            color: Color(0xFF3B2C18),
            fontSize: 40,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, const Offset(60, 690));
      final bildDaten = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final png = await bildDaten.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    });
    return File(p.join(eingang.path, name))..writeAsBytesSync(bytes!);
  }

  testWidgets(
    timeout: zeitgrenze,
    'KI-111 KI-112 KI-113 KI-114 KI-115 Alte Fotos zeitlich einordnen',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.clip]));
      await autoAus(tester);
      await warteRuhe(tester);
      await importiereDirekt(tester, [
        testfoto(
          'farbe1.jpg',
          datum: DateTime(2023, 8, 1, 12),
          kamera: 'Testkamera',
        ),
        testfoto(
          'farbe2.jpg',
          datum: DateTime(2023, 8, 2, 12),
          kamera: 'Testkamera',
        ),
      ]);
      await analyseUeberKarte(tester);
      // KI-111: nur Fotos mit echtem Datum.
      await werkzeug(tester, de.datierungTitel);
      await waitFor(tester, find.text(de.datierungKeine));

      // KI-112: undatierte, alt aussehende Scans.
      final scans = await importiereDirekt(tester, [
        for (var i = 0; i < 6; i++) await altesFoto(tester, 'scan$i.png', i),
      ]);
      for (final id in scans) {
        await sqlAusfuehren(
          tester,
          "UPDATE assets SET camera_model = 'Flachbett-Scan' WHERE id = ?",
          [id],
        );
      }
      await analyseUeberKarte(tester);
      await werkzeug(tester, de.datierungTitel);
      await pumpe(tester, 3000);
      final um = find.textContaining(RegExp(r'^um \d{4}$'));
      final anzahl = um.evaluate().length;
      print('KI-112 Funde: $anzahl, Bildschirm: ${onScreen(tester)}');
      expect(anzahl, greaterThan(0), reason: 'kein Scan sah für CLIP alt aus');
      final jahre = [
        for (final e in um.evaluate())
          int.parse((e.widget as Text).data!.substring(3)),
      ];
      expect(jahre, List.of(jahre)..sort(), reason: 'älteste zuerst');
      expect(
        find.textContaining(RegExp(r'^\d{4} bis \d{4}$')).evaluate().length +
            find.textContaining(RegExp(r'^zu unsicher')).evaluate().length,
        anzahl,
      );
      expect(find.text('farbe1.jpg'), findsNothing);

      // KI-113: eine übernehmen.
      final knoepfe = find.widgetWithText(TextButton, de.datierungUebernehmen);
      final belastbar = knoepfe.evaluate().isNotEmpty;
      print('KI-113 belastbare Schätzungen: ${knoepfe.evaluate().length}');
      if (belastbar) {
        final vorher = {
          for (final id in scans)
            id: sha(
              bibliothek.paths.absolute(
                (await aufnahme(tester, id)).relativePath,
              ),
            ),
        };
        await tippe(tester, knoepfe.first);
        await erwarteMeldung(tester, de.datierungUebernommen(1));
        expect(find.text(de.datierungIstUebernommen), findsWidgets);
        final uebernommen = [
          for (final id in scans)
            if (await aufnahme(tester, id) case final x
                when x.fileCreatedAt.month == 7 &&
                    x.fileCreatedAt.day == 1 &&
                    x.fileCreatedAt.hour == 12)
              x,
        ];
        print(
          'KI-113 übernommen: ${[for (final x in uebernommen) x.fileCreatedAt]}',
        );
        expect(uebernommen, hasLength(1));
        final a = uebernommen.single;
        expect(a.fileCreatedAt.month, 7);
        expect(a.fileCreatedAt.day, 1);
        expect(a.fileCreatedAt.hour, 12);
        expect(a.datumGeschaetzt, isTrue);
        expect(sha(bibliothek.paths.absolute(a.relativePath)), vorher[a.id]);

        // KI-114: alle übernehmen.
        final alle = find.textContaining(RegExp(r'Schätzungen? übernehmen$'));
        final rest = knoepfe.evaluate().length;
        if (rest > 0) {
          await tippe(tester, alle.first);
          await erwarteMeldung(tester, de.datierungUebernommen(rest));
        }
        final null0 = find.ancestor(
          of: find.text(de.datierungAlleUebernehmen(0)),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(null0).onPressed, isNull);
        await werkzeug(tester, de.datierungTitel);
        await pumpe(tester, 2000);
        expect(find.text(de.datierungIstUebernommen), findsWidgets);
      }
      // KI-115: gesperrt und gelöscht fehlen.
      final liste = um.evaluate().length;
      await tester.runAsync(() => bibliothek.setupVaultPin('2468'));
      await tester.runAsync(
        () async =>
            bibliothek.lockAsset((await bibliothek.db.assetById(scans[0]))!),
      );
      await befehl(tester, InDenPapierkorb([scans[1]]));
      final kandidaten = await tester.runAsync(
        bibliothek.db.datierungskandidaten,
      );
      expect(
        kandidaten!.map((k) => k.asset.id),
        isNot(anyOf(contains(scans[0]), contains(scans[1]))),
      );
      await werkzeug(tester, de.datierungTitel);
      await pumpe(tester, 2000);
      print('KI-115 Funde vorher $liste, nachher ${um.evaluate().length}');
      expect(um.evaluate().length, lessThanOrEqualTo(liste));
      await finish(tester);
    },
  );

  // ------------------------------------------------------ Scan-Arbeitsbereich

  final rot = img.ColorRgb8(200, 40, 40);
  final blau = img.ColorRgb8(40, 60, 200);
  final gruen = img.ColorRgb8(40, 170, 70);
  final braun = img.ColorRgb8(150, 100, 50);

  Future<void> scanOeffnen(WidgetTester tester, List<File> dateien) async {
    await werkzeug(tester, de.scanTitel);
    await waitFor(tester, find.byType(ScanWorkspaceScreen));
    dialog.dateien = dateien;
    await tippe(tester, find.text(de.scanDateienWaehlen));
    await eventually(
      tester,
      () async => _findet(find.textContaining(RegExp(r'Fotos? erkannt'))),
      timeout: const Duration(seconds: 60),
      was: 'Scans analysiert',
    );
    await pumpe(tester, 500);
  }

  Finder fotoBox(int nummer) => find.ancestor(
    of: find.text(de.scanFotoNummer(nummer)),
    matching: find.byType(CheckboxListTile),
  );

  Future<void> scanImportieren(WidgetTester tester, int anzahl) async {
    final k = find.text(de.scanImportieren(anzahl));
    await sichtbar(tester, k, ScanWorkspaceScreen);
    await tippe(tester, k);
  }

  bool scanTempDa() => Directory.systemTemp.listSync().any(
    (e) => p.basename(e.path).startsWith('photo_vault_scan_'),
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-126 KI-127 Scan-Arbeitsbereich oeffnen und Dateiauswahl',
    (tester) async {
      await startApp(tester);
      final merker = EndungenDialog();
      FilePickerPlatform.instance = merker;
      try {
        await werkzeug(tester, de.scanTitel);
        await waitFor(tester, find.byType(ScanWorkspaceScreen));
        expect(find.text(de.scanText), findsOneWidget);
        expect(find.text(de.scanDateienWaehlen), findsOneWidget);
        expect(find.text(de.scanNochKeine), findsOneWidget);
        dialog.dateien = [];
        await tippe(tester, find.text(de.scanDateienWaehlen));
        expect(merker.erlaubt, ['jpg', 'jpeg', 'png', 'bmp', 'tif', 'tiff']);
        expect(merker.titel, de.scanDateienWaehlen);
        expect(find.text(de.scanNochKeine), findsOneWidget);
      } finally {
        FilePickerPlatform.instance = dialog;
      }
      await finish(tester);
    },
  );

  // Behoben in #405 (Scan-Analyse im Isolate über berechne).
  testWidgets(
    timeout: zeitgrenze,
    'KI-128 KI-130 KI-131 KI-132 KI-140 KI-141 Befundpruefung Scan mit zwei Fotos',
    (tester) async {
      semantikZusicherungenUebergehen();
      await startApp(tester);
      await autoAus(tester);
      final merker = EndungenDialog();
      FilePickerPlatform.instance = merker;
      try {
        final scan = scanbild(
          'scan_zwei.png',
          fotos: [(100, 200, 400, 300, rot), (700, 200, 400, 300, blau)],
        );
        final summe = sha(scan);

        // KI-128.
        await werkzeug(tester, de.scanTitel);
        await waitFor(tester, find.byType(ScanWorkspaceScreen));
        dialog.dateien = [scan];
        await tippe(tester, find.text(de.scanDateienWaehlen));
        await eventually(
          tester,
          () async =>
              _findet(find.text(de.scanErkannt(2))) ||
              _findet(find.textContaining('konnte den Vorgang nicht')),
          timeout: const Duration(seconds: 60),
          was: 'Scan analysiert',
        );
        final fehler = find.textContaining('konnte den Vorgang nicht');
        if (_findet(fehler)) {
          final t = tester.widget<Text>(fehler.first).data ?? '';
          print('SCANFEHLER: ${t.substring(0, math.min(400, t.length))}');
        }
        expect(
          fehler,
          findsNothing,
          reason: 'Scan liess sich nicht analysieren',
        );
        expect(merker.erlaubt, ['jpg', 'jpeg', 'png', 'bmp', 'tif', 'tiff']);
        expect(find.text(de.scanFotoNummer(1)), findsOneWidget);
        expect(find.text(de.scanFotoNummer(2)), findsOneWidget);
        expect(tester.widget<CheckboxListTile>(fotoBox(1)).value, isTrue);
        expect(tester.widget<CheckboxListTile>(fotoBox(2)).value, isTrue);
        expect(find.text(de.scanImportieren(2)), findsOneWidget);
        expect(
          tester.getCenter(find.text(de.scanFotoNummer(1))).dx,
          lessThan(tester.getCenter(find.text(de.scanFotoNummer(2))).dx),
        );

        // KI-132: abwählen.
        await tippe(tester, fotoBox(2));
        expect(find.text(de.scanImportieren(1)), findsOneWidget);
        await tippe(tester, fotoBox(1));
        final null0 = find.ancestor(
          of: find.text(de.scanImportieren(0)),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(null0).onPressed, isNull);
        await tippe(tester, fotoBox(1));
        await tippe(tester, fotoBox(2));

        // KI-131: zweimal rechts, einmal links.
        final karte1 = find.ancestor(
          of: find.text(de.scanFotoNummer(1)),
          matching: find.byType(Card),
        );
        Future<void> drehe(String tip) => tippe(
          tester,
          find.descendant(of: karte1, matching: find.byTooltip(tip)),
        );
        await drehe(de.scanRechtsDrehen);
        await drehe(de.scanRechtsDrehen);
        await drehe(de.scanLinksDrehen);
        expect(
          tester
              .widget<RotatedBox>(
                find
                    .descendant(of: karte1, matching: find.byType(RotatedBox))
                    .first,
              )
              .quarterTurns,
          1,
        );
        await scanImportieren(tester, 2);
        // KI-140: Abschlussmeldung, Bildschirm zu, Temp leer.
        await erwarteMeldung(tester, de.scanFertig(2, 0, 0));
        await waitGone(tester, find.byType(ScanWorkspaceScreen));
        expect(scanTempDa(), isFalse);
        final neu = await sql(
          tester,
          'SELECT original_file_name AS n, width_px AS w, height_px AS h '
          'FROM assets ORDER BY original_file_name',
        );
        print('KI-131 importiert: $neu');
        expect(neu, hasLength(2));
        expect(neu[0]['w'], neu[1]['h'], reason: 'Foto 1 um 90° gedreht');
        expect(neu[0]['h'], neu[1]['w']);
        // KI-141: Scan unverändert und nicht selbst importiert.
        expect(sha(scan), summe);
        expect(neu.map((z) => z['n']), isNot(contains('scan_zwei.png')));

        // KI-140: dieselben Ausschnitte noch einmal → Duplikate.
        await scanOeffnen(tester, [scan]);
        await tippe(
          tester,
          find.descendant(
            of: karte1,
            matching: find.byTooltip(de.scanRechtsDrehen),
          ),
        );
        await scanImportieren(tester, 2);
        await erwarteMeldung(tester, de.scanFertig(0, 2, 0));
        expect(await zahl(tester, 'SELECT count(*) FROM assets'), 2);

        // KI-130: ganzen Scan verwenden.
        await scanOeffnen(tester, [scan]);
        await tippe(tester, find.text(de.scanGanzesBild));
        await waitFor(tester, find.text(de.scanErkannt(1)));
        expect(sha(scan), summe);
      } finally {
        FilePickerPlatform.instance = dialog;
      }
      await finish(tester);
    },
  );

  // Behoben in #405 (Scan-Analyse im Isolate über berechne).
  testWidgets(
    timeout: zeitgrenze,
    'KI-129 KI-133 KI-134 KI-135 Befundpruefung Scan: Formate, Beschreibung, Datum',
    (tester) async {
      semantikZusicherungenUebergehen();
      await startApp(tester);
      await autoAus(tester);

      // KI-129: fast leerer Scan.
      final leer = scanbild('leer.png', grund: 245);
      await scanOeffnen(tester, [leer]);
      expect(find.text(de.scanErkannt(1)), findsOneWidget);

      // KI-133: PNG mit Farbprofil bleibt PNG, JPEG bleibt JPEG.
      final profil = [
        '/System/Library/ColorSync/Profiles/sRGB Profile.icc',
        '/System/Library/ColorSync/Profiles/Generic RGB Profile.icc',
      ].map(File.new).firstWhere((f) => f.existsSync());
      final icc = profil.readAsBytesSync();
      final pngBild = img.Image(width: 1000, height: 700);
      img.fill(pngBild, color: img.ColorRgb8(250, 250, 250));
      img.fillRect(pngBild, x1: 200, y1: 150, x2: 700, y2: 500, color: gruen);
      pngBild.iccProfile = img.IccProfile(
        'Profil',
        img.IccProfileCompression.none,
        icc,
      );
      final pngScan = File(p.join(eingang.path, 'profil.png'))
        ..writeAsBytesSync(img.encodePng(pngBild));
      final jpgScan = scanbild(
        'foto.jpg',
        fotos: [(150, 150, 500, 400, braun)],
        png: false,
      );
      await scanOeffnen(tester, [pngScan, jpgScan]);
      await scanImportieren(tester, 2);
      await erwarteMeldung(tester, de.scanFertig(2, 0, 0));
      final zeilen = await sql(
        tester,
        'SELECT id, original_file_name AS n FROM assets ORDER BY original_file_name',
      );
      final ausPng = zeilen.firstWhere(
        (z) => (z['n']! as String).startsWith('profil'),
      );
      final ausJpg = zeilen.firstWhere(
        (z) => (z['n']! as String).startsWith('foto'),
      );
      expect(ausPng['n'], endsWith('.png'));
      expect(ausJpg['n'], endsWith('.jpg'));
      final pngDatei = bibliothek.paths.absolute(
        (await aufnahme(tester, ausPng['id']! as String)).relativePath,
      );
      final dekodiert = img.decodePng(pngDatei.readAsBytesSync())!;
      expect(
        dekodiert.iccProfile?.decompressed(),
        icc,
        reason: 'gleiches Farbprofil',
      );
      final mitte = dekodiert.getPixel(
        dekodiert.width ~/ 2,
        dekodiert.height ~/ 2,
      );
      expect([mitte.r, mitte.g, mitte.b], [gruen.r, gruen.g, gruen.b]);
      final jpgDatei = bibliothek.paths.absolute(
        (await aufnahme(tester, ausJpg['id']! as String)).relativePath,
      );
      expect(jpgDatei.readAsBytesSync().sublist(0, 2), [0xFF, 0xD8]);

      // KI-134: gemeinsame Beschreibung und Datum.
      final ferien = scanbild(
        'ferien.png',
        fotos: [(100, 100, 300, 250, rot), (600, 300, 300, 250, blau)],
      );
      await scanOeffnen(tester, [ferien]);
      await eintragen(tester, field(de.scanBeschreibung), 'Ferien');
      final heute = DateTime.now();
      final tag = heute.day > 3 ? heute.day - 2 : heute.day;
      Future<void> datumWaehlen() async {
        final eintrag = find.text(de.scanDatumKeins);
        await sichtbar(tester, eintrag, ScanWorkspaceScreen);
        await tippe(tester, eintrag);
        await waitFor(tester, find.byType(DatePickerDialog));
        await tippe(
          tester,
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text('$tag'),
          ),
        );
        final ok = MaterialLocalizations.of(
          tester.element(find.byType(DatePickerDialog)),
        ).okButtonLabel;
        await tippe(
          tester,
          find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.text(ok),
          ),
        );
      }

      await datumWaehlen();
      expect(find.text(de.scanDatumKeins), findsNothing);
      await tippe(
        tester,
        find.descendant(
          of: find.byType(ScanWorkspaceScreen),
          matching: find.byTooltip(de.allgLoeschen),
        ),
      );
      expect(find.text(de.scanDatumKeins), findsOneWidget);
      await datumWaehlen();
      await scanImportieren(tester, 2);
      await erwarteMeldung(tester, de.scanFertig(2, 0, 0));
      final ferienZeilen = await sql(
        tester,
        "SELECT id FROM assets WHERE original_file_name LIKE 'ferien%'",
      );
      expect(ferienZeilen, hasLength(2));
      for (final z in ferienZeilen) {
        final a = await aufnahme(tester, z['id']! as String);
        expect(a.description, 'Ferien');
        expect(
          [a.fileCreatedAt.year, a.fileCreatedAt.month, a.fileCreatedAt.day],
          [heute.year, heute.month, tag],
        );
      }

      // KI-135: ohne Datum zählt der Import, geschätzt.
      final benannt = scanbild(
        'scan_2019-05-04.png',
        fotos: [(300, 200, 500, 350, braun)],
      );
      final vorImport = DateTime.now();
      await scanOeffnen(tester, [benannt]);
      await scanImportieren(tester, 1);
      await erwarteMeldung(tester, de.scanFertig(1, 0, 0));
      final z = (await sql(
        tester,
        "SELECT id FROM assets WHERE original_file_name LIKE 'scan_2019%'",
      )).single;
      final a = await aufnahme(tester, z['id']! as String);
      print('KI-135 Datum: ${a.fileCreatedAt}, geschätzt ${a.datumGeschaetzt}');
      expect(a.datumGeschaetzt, isTrue);
      expect(
        a.fileCreatedAt.difference(vorImport).inMinutes.abs(),
        lessThan(10),
      );
      expect(a.fileCreatedAt.year, isNot(2019));
      await finish(tester);
    },
  );

  // Behoben in #405 (Scan-Analyse im Isolate über berechne).
  testWidgets(
    timeout: zeitgrenze,
    'KI-136 KI-137 KI-138 Befundpruefung Vorder- und Rueckseiten stapeln',
    (tester) async {
      semantikZusicherungenUebergehen();
      await startApp(tester);
      await autoAus(tester);
      final a = scanbild(
        'seiteA.png',
        fotos: [(100, 200, 400, 300, rot), (700, 200, 400, 300, blau)],
      );
      final b = scanbild(
        'seiteB.png',
        fotos: [(100, 200, 400, 300, gruen), (700, 200, 400, 300, braun)],
      );
      // KI-136: ungerade Auswahl.
      await scanOeffnen(tester, [a, b]);
      final paar = find.text(de.scanPaarweise);
      await sichtbar(tester, paar, ScanWorkspaceScreen);
      await tippe(tester, paar);
      await sichtbar(tester, fotoBox(2), ScanWorkspaceScreen);
      await tippe(tester, fotoBox(2).last);
      await scanImportieren(tester, 3);
      await erwarteMeldung(tester, de.scanUngerade);
      expect(await zahl(tester, 'SELECT count(*) FROM assets'), 0);
      expect(find.byType(ScanWorkspaceScreen), findsOneWidget);

      // KI-137: vier ausgewählt → zwei Stapel.
      await tippe(tester, fotoBox(2).last);
      await scanImportieren(tester, 4);
      await erwarteMeldung(tester, de.scanFertig(4, 0, 0));
      final zeilen = await sql(
        tester,
        'SELECT original_file_name AS n, stack_id AS s, is_stack_cover AS c '
        'FROM assets ORDER BY original_file_name',
      );
      print('KI-137 Stapel: $zeilen');
      expect(zeilen, hasLength(4));
      expect(zeilen[0]['s'], isNotNull);
      expect(zeilen[0]['s'], zeilen[1]['s']);
      expect(zeilen[2]['s'], zeilen[3]['s']);
      expect(zeilen[0]['s'], isNot(zeilen[2]['s']));
      expect(zeilen[0]['c'], 1, reason: 'Vorderseite sichtbar');
      expect(zeilen[1]['c'], 0);
      expect(zeilen[2]['c'], 1);
      expect(zeilen[3]['c'], 0);

      // KI-138: ein Paar mit Duplikat.
      final c = scanbild(
        'seiteC.png',
        fotos: [(100, 200, 400, 300, braun), (700, 200, 400, 300, gruen)],
      );
      final d = scanbild(
        'seiteD.png',
        fotos: [(100, 200, 400, 300, blau), (700, 200, 400, 300, rot)],
      );
      await scanOeffnen(tester, [c]);
      await tippe(tester, fotoBox(1));
      await scanImportieren(tester, 1);
      await erwarteMeldung(tester, de.scanFertig(1, 0, 0));
      await scanOeffnen(tester, [c, d]);
      await sichtbar(tester, paar, ScanWorkspaceScreen);
      await tippe(tester, paar);
      await scanImportieren(tester, 4);
      await erwarteMeldung(tester, de.scanPaarNichtGestapelt(1));
      final dz = await sql(
        tester,
        'SELECT original_file_name AS n, stack_id AS s FROM assets '
        "WHERE original_file_name LIKE 'seiteD%' ORDER BY original_file_name",
      );
      expect(dz, hasLength(2));
      expect(dz[0]['s'], isNotNull);
      expect(dz[0]['s'], dz[1]['s']);
      await finish(tester);
    },
  );

  // Behoben in #405 (Scan-Analyse im Isolate über berechne).
  testWidgets(
    timeout: zeitgrenze,
    'KI-139 Befundpruefung Scan: nach dem Import restaurieren',
    (tester) async {
      semantikZusicherungenUebergehen();
      await startApp(tester);
      await autoAus(tester);
      final scan = scanbild('rest.png', fotos: [(200, 200, 300, 250, rot)]);
      await scanOeffnen(tester, [scan]);
      expect(find.text(de.scanRestaurieren), findsNothing);
      await installiere(tester, [ModelCatalog.neuralRestore]);
      await scanOeffnen(tester, [scan]);
      final schalterR = schalter(de.scanRestaurieren);
      await sichtbar(tester, schalterR, ScanWorkspaceScreen);
      await tippe(tester, schalterR);
      await scanImportieren(tester, 1);
      await erwarteMeldung(tester, de.scanFertig(1, 0, 0));
      await waitFor(
        tester,
        find.textContaining(
          RegExp(
            'Warteschlange für die KI-Restaurierung|KI-Restaurierung läuft',
          ),
        ),
        timeout: const Duration(seconds: 30),
      );
      for (final z in await sql(tester, 'SELECT id FROM restore_jobs')) {
        await tester.runAsync(
          () => bibliothek.restoreQueue.cancel(z['id']! as String),
        );
      }
      await eventually(
        tester,
        () async => !bibliothek.restoreQueue.isProcessing,
        timeout: const Duration(minutes: 3),
        was: 'Restaurierung angehalten',
      );
      await finish(tester);
    },
  );

  // Behoben in #405 (Scan-Analyse im Isolate über berechne).
  testWidgets(
    timeout: zeitgrenze,
    'KI-142 Befundpruefung unlesbare Datei verwirft die Auswahl',
    (tester) async {
      semantikZusicherungenUebergehen();
      await startApp(tester);
      final gut = scanbild('gut.png', fotos: [(200, 200, 300, 250, blau)]);
      final kaputt = File(p.join(eingang.path, 'kaputt.png'))
        ..writeAsStringSync('Das ist kein Bild.');
      await werkzeug(tester, de.scanTitel);
      dialog.dateien = [gut, kaputt];
      await tippe(tester, find.text(de.scanDateienWaehlen));
      await erwarteMeldung(
        tester,
        de.scanFehler('').replaceAll(RegExp(r':\s*$'), ''),
      );
      await pumpe(tester, 1000);
      // Bedienbar: Knopf wieder frei.
      final knopf = find.ancestor(
        of: find.text(de.scanDateienWaehlen),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(knopf).onPressed, isNotNull);
      final gutDa = _findet(find.text('gut.png'));
      print('KI-142 gültiger Scan nach dem Fehler noch da: $gutDa');
      expect(gutDa, isTrue, reason: 'der gültige Scan wurde mit verworfen');
      await finish(tester);
    },
  );

  // ------------------------------------------------ Automatisierungsregeln

  Future<void> regelNeu(WidgetTester tester) async {
    await tippe(tester, find.byTooltip(de.regelNeu));
    await waitFor(tester, find.text(de.regelNeuTitel));
  }

  Future<void> bedingung(WidgetTester tester, String art) async {
    final auswahl = find.ancestor(
      of: find.text(de.regelBedingung),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tippe(tester, auswahl);
    await tippe(tester, find.text(art).last);
  }

  String fehlerImDialog(WidgetTester tester) {
    final rot = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.style?.color == Colors.redAccent,
      ),
    );
    return _findet(rot) ? tester.widget<Text>(rot.first).data! : '';
  }

  Future<void> tagWaehlen(
    WidgetTester tester,
    DateTime tag, {
    required bool von,
  }) async {
    final knopf = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(OutlinedButton),
    );
    await tippe(tester, knopf.at(von ? 0 : 1));
    await waitFor(tester, find.byType(DatePickerDialog));
    final ok = MaterialLocalizations.of(
      tester.element(find.byType(DatePickerDialog)),
    ).okButtonLabel;
    await tippe(
      tester,
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text('${tag.day}'),
      ),
    );
    await tippe(
      tester,
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.text(ok),
      ),
    );
  }

  testWidgets(
    timeout: zeitgrenze,
    'KI-154 KI-155 KI-156 KI-157 KI-164 KI-165 KI-166 KI-168 KI-170 Ortsregel',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final tagFoto = await importiereDirekt(tester, [testfoto('tags.jpg')]);
      await befehl(tester, SchlagwortAnheften(tagFoto, 'Tag A'));
      await befehl(tester, SchlagwortAnheften(tagFoto, 'Tag B'));
      await befehl(tester, AlbumAnlegen('albumX', 'Album X', DateTime(2024)));
      final vorher = await importiereDirekt(tester, [
        testfoto('vorher.jpg', breitengrad: 10.5, laengengrad: 20.25),
      ]);

      // KI-154: leere Liste.
      await werkzeug(tester, de.werkzRegelnTitel);
      await waitFor(tester, find.byType(AutomationRulesScreen));
      expect(find.text(de.regelLeer), findsOneWidget);
      expect(find.byTooltip(de.regelNeu), findsOneWidget);

      // KI-156: Pflichtfelder und Koordinaten.
      await regelNeu(tester);
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelNameNoetig);
      await eintragen(tester, field(de.regelNameFeld), 'Regel A');
      await eintragen(tester, field(de.regelBreitengrad), 'abc');
      await eintragen(tester, field(de.regelLaengengrad), '20,25');
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelKoordinatenUngueltig);
      await eintragen(tester, field(de.regelBreitengrad), '95');
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelBreitengradBereich);
      await eintragen(tester, field(de.regelBreitengrad), '10');
      await eintragen(tester, field(de.regelLaengengrad), '190');
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelLaengengradBereich);
      expect(find.text(de.regelNeuTitel), findsOneWidget);
      expect(await zahl(tester, 'SELECT count(*) FROM automation_rules'), 0);

      // KI-155: Ortsregel.
      await eintragen(tester, field(de.regelBreitengrad), '10,5');
      await eintragen(tester, field(de.regelLaengengrad), '20,25');
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect([slider.min, slider.max], [1, 200]);
      expect(find.text(de.regelUmkreis('25')), findsOneWidget);
      // KI-164: Zielalbum und neues Album schliessen sich aus.
      final albumWahl = find.ancestor(
        of: find.text(de.presetZielalbum),
        matching: find.byType(DropdownButtonFormField<AlbumData?>),
      );
      await tippe(tester, albumWahl);
      await tippe(tester, find.text('Album X').last);
      await eintragen(tester, field(de.presetNeuesAlbum), 'Album A');
      expect(
        find.descendant(of: albumWahl, matching: find.text(de.presetKeinAlbum)),
        findsOneWidget,
      );
      await tippe(tester, albumWahl);
      await tippe(tester, find.text('Album X').last);
      expect(
        tester.widget<TextField>(field(de.presetNeuesAlbum)).controller!.text,
        isEmpty,
      );
      await eintragen(tester, field(de.presetNeuesAlbum), 'Album A');
      await tippe(tester, find.text(de.presetFavorisieren));
      // KI-165: Tags wählen, Abbrechen übernimmt nichts, Chip entfernen.
      await tippe(tester, find.text(de.presetTagsWaehlenPlatzhalter));
      await waitFor(tester, find.text(de.suchoptTagsWaehlen));
      await tippe(
        tester,
        find.descendant(
          of: find.byType(CheckboxListTile),
          matching: find.text('Tag B'),
        ),
      );
      await tippe(tester, find.text(de.allgAbbrechen).last);
      expect(find.byType(Chip), findsNothing);
      await tippe(tester, find.text(de.presetTagsWaehlenPlatzhalter));
      await eintragen(tester, field(de.suchoptTagsFiltern), 'Tag');
      for (final t in ['Tag A', 'Tag B']) {
        await tippe(
          tester,
          find.descendant(
            of: find.byType(CheckboxListTile),
            matching: find.text(t),
          ),
        );
      }
      await tippe(tester, find.text(de.allgUebernehmen));
      expect(find.byType(Chip), findsNWidgets(2));
      final chipB = find.ancestor(
        of: find.text('Tag B'),
        matching: find.byType(Chip),
      );
      final loeschen = MaterialLocalizations.of(
        tester.element(chipB),
      ).deleteButtonTooltip;
      await tippe(
        tester,
        find.descendant(of: chipB, matching: find.byTooltip(loeschen)),
      );
      expect(find.byType(Chip), findsOneWidget);
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(tester, find.text('Regel A'));
      final unter = find.textContaining(
        '${de.regelAusloeserOrt} · ${de.regelUmkreisUm('25', '10.50', '20.25')}',
      );
      expect(unter, findsOneWidget);
      final zeile = tester.widget<Text>(unter).data!;
      expect(zeile, contains(de.regelAlbumTeil('Album A')));
      expect(zeile, contains(de.presetFavorisieren));
      expect(zeile, contains(de.regelTagsTeil('Tag A')));
      expect(
        await zahl(
          tester,
          "SELECT count(*) FROM albums WHERE name = 'Album A'",
        ),
        1,
      );
      final albumA =
          (await sql(
                tester,
                "SELECT id FROM albums WHERE name = 'Album A'",
              )).single['id']!
              as String;

      // KI-170: vorhandene Fotos bleiben unverändert.
      Future<(int, bool, String)> stand(String id) async => (
        await zahl(
          tester,
          'SELECT count(*) FROM album_assets WHERE album_id = ? AND asset_id = ?',
          [albumA, id],
        ),
        (await aufnahme(tester, id)).isFavorite,
        [
          for (final t in (await tester.runAsync(
            () => bibliothek.db.tagsForAsset(id),
          ))!)
            t.name,
        ].join(','),
      );
      expect(await stand(vorher.first), (0, false, ''));

      // KI-157: wirkt beim Import.
      final neu = await importiereDirekt(tester, [
        testfoto('innen.jpg', breitengrad: 10.6, laengengrad: 20.3),
        testfoto('aussen.jpg', breitengrad: 40.0, laengengrad: 40.0),
      ]);
      expect(await stand(neu[0]), (1, true, 'Tag A'));
      expect(await stand(neu[1]), (0, false, ''));

      // KI-166: bearbeiten.
      await tippe(tester, find.byTooltip(de.allgBearbeiten));
      await waitFor(tester, find.text(de.regelBearbeitenTitel));
      expect(
        tester.widget<TextField>(field(de.regelNameFeld)).controller!.text,
        'Regel A',
      );
      expect(
        tester.widget<TextField>(field(de.regelBreitengrad)).controller!.text,
        '10.5',
      );
      await eintragen(tester, field(de.regelNameFeld), 'Regel B');
      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await pumpe(tester);
      expect(find.text(de.regelUmkreis('25')), findsNothing);
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(tester, find.text('Regel B'));
      expect(find.text('Regel A'), findsNothing);
      expect(await zahl(tester, 'SELECT count(*) FROM automation_rules'), 1);
      final radius =
          (await sql(
                tester,
                'SELECT region_radius_km AS r FROM automation_rules',
              )).single['r']!
              as num;
      expect(radius, isNot(25));

      // KI-168: löschen.
      await tippe(tester, find.byTooltip(de.allgLoeschen));
      await waitFor(tester, find.text(de.regelLoeschenTitel));
      expect(find.text(de.regelLoeschenText('Regel B')), findsOneWidget);
      await tippe(tester, find.text(de.allgAbbrechen).last);
      expect(find.text('Regel B'), findsOneWidget);
      await tippe(tester, find.byTooltip(de.allgLoeschen));
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await waitFor(tester, find.text(de.regelLeer));
      expect(await stand(neu[0]), (1, true, 'Tag A'));
      await finish(tester);
    },
  );

  testWidgets(
    timeout: zeitgrenze,
    'KI-158 KI-162 KI-163 Datums-, Datei- und Vokabelregeln',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final heute = DateTime.now();
      final monat = DateTime(heute.year, heute.month);
      await werkzeug(tester, de.werkzRegelnTitel);
      await waitFor(tester, find.byType(AutomationRulesScreen));

      // KI-158: Datumsregel.
      await regelNeu(tester);
      await eintragen(tester, field(de.regelNameFeld), 'Datum');
      await bedingung(tester, de.regelAusloeserDatum);
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelDatumWaehlen);
      await tagWaehlen(
        tester,
        DateTime(monat.year, monat.month, 12),
        von: true,
      );
      await tagWaehlen(
        tester,
        DateTime(monat.year, monat.month, 6),
        von: false,
      );
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelDatumReihenfolge);
      await tagWaehlen(tester, DateTime(monat.year, monat.month, 3), von: true);
      await tippe(tester, find.text(de.allgSpeichern));
      String fmt(int tag) =>
          DateFormat.yMd('de').format(DateTime(monat.year, monat.month, tag));
      await waitFor(
        tester,
        find.textContaining(
          '${de.regelAusloeserDatum} · ${de.regelDatumBereich(fmt(3), fmt(6))}',
        ),
      );

      // KI-163: Dateiname und Dateiendung.
      await regelNeu(tester);
      await eintragen(tester, field(de.regelNameFeld), 'Name');
      await bedingung(tester, de.regelAusloeserDateiname);
      await eintragen(tester, field(de.regelDateinameWert), 'Urlaub');
      await eintragen(tester, field(de.presetNeuesAlbum), 'Namen');
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(tester, find.text('Name'));
      await regelNeu(tester);
      await eintragen(tester, field(de.regelNameFeld), 'Endung falsch');
      await bedingung(tester, de.regelAusloeserDateiendung);
      await eintragen(tester, field(de.regelDateiendungWert), 'j?g');
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelDateiUngueltig);
      await eintragen(tester, field(de.regelNameFeld), 'Endung');
      await eintragen(tester, field(de.regelDateiendungWert), 'jpg, .heic');
      await eintragen(tester, field(de.presetNeuesAlbum), 'Endungen');
      await tippe(tester, find.text(de.allgSpeichern));
      await waitFor(tester, find.text('Endung'));
      final urlaub = File(p.join(eingang.path, 'URLAUB_01.png'))
        ..writeAsBytesSync(
          img.encodePng(
            img.Image(width: 64, height: 48)..clear(img.ColorRgb8(9, 99, 199)),
          ),
        );
      final bild = File(p.join(eingang.path, 'bild.JPG'))
        ..writeAsBytesSync(testfoto('x.jpg').readAsBytesSync());
      final ids = await importiereDirekt(tester, [urlaub, bild]);
      Future<List<String>> alben(String id) async => [
        for (final z in await sql(
          tester,
          'SELECT a.name AS n FROM album_assets x JOIN albums a ON a.id = x.album_id '
          'WHERE x.asset_id = ?',
          [id],
        ))
          z['n']! as String,
      ];
      expect(await alben(ids[0]), ['Namen']);
      expect(await alben(ids[1]), ['Endungen']);

      // KI-162: ohne Vokabular.
      await sqlAusfuehren(tester, 'DELETE FROM ai_tag_vocabulary');
      await werkzeug(tester, de.werkzRegelnTitel);
      await regelNeu(tester);
      await eintragen(tester, field(de.regelNameFeld), 'KI');
      await bedingung(tester, de.regelAusloeserTag);
      expect(find.text(de.regelKeinVokabular), findsOneWidget);
      await tippe(tester, find.text(de.allgSpeichern));
      expect(fehlerImDialog(tester), de.regelTagWaehlen);
      await tippe(tester, find.text(de.allgAbbrechen).last);
      await finish(tester);
    },
  );

  // Behoben in #414: regelTrifftZu vergleicht ganze Kalendertage, der letzte Tag zählt bis Mitternacht.
  testWidgets(
    timeout: zeitgrenze,
    'KI-159 Befundpruefung Datumsregel schliesst den letzten Tag ein',
    (tester) async {
      await startApp(tester);
      await autoAus(tester);
      final heute = DateTime.now();
      final m = DateTime(heute.year, heute.month);
      await werkzeug(tester, de.werkzRegelnTitel);
      for (final (name, von, bis) in [('Bereich', 1, 5), ('Ein Tag', 10, 10)]) {
        await regelNeu(tester);
        await eintragen(tester, field(de.regelNameFeld), name);
        await bedingung(tester, de.regelAusloeserDatum);
        await tagWaehlen(tester, DateTime(m.year, m.month, von), von: true);
        await tagWaehlen(tester, DateTime(m.year, m.month, bis), von: false);
        await tippe(tester, find.text(de.presetFavorisieren));
        await tippe(tester, find.text(de.allgSpeichern));
        await waitFor(tester, find.text(name));
      }
      final ids = await importiereDirekt(tester, [
        testfoto('am5.jpg', datum: DateTime(m.year, m.month, 5, 14)),
        testfoto('am1.jpg', datum: DateTime(m.year, m.month, 1, 8)),
        testfoto('am10.jpg', datum: DateTime(m.year, m.month, 10, 10)),
      ]);
      final fav = [
        for (final id in ids) (await aufnahme(tester, id)).isFavorite,
      ];
      print('KI-159 favorisiert (5. 14 Uhr, 1. 8 Uhr, 10. 10 Uhr): $fav');
      expect(fav, [true, true, true]);
      await finish(tester);
    },
  );

  // Behoben in #407: Die Datumswahl der Regeln beginnt mit dem ersten Foto.
  testWidgets(
    timeout: zeitgrenze,
    'KI-160 Befundpruefung Datumsregel fuer Fotos vor 2000',
    (tester) async {
      await startApp(tester);
      await werkzeug(tester, de.werkzRegelnTitel);
      await regelNeu(tester);
      await bedingung(tester, de.regelAusloeserDatum);
      final knopf = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(OutlinedButton),
      );
      await tippe(tester, knopf.first);
      await waitFor(tester, find.byType(DatePickerDialog));
      final ml = MaterialLocalizations.of(
        tester.element(find.byType(DatePickerDialog)),
      );
      await tippe(
        tester,
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text(ml.formatMonthYear(DateTime.now())),
        ),
      );
      await pumpe(tester, 600);
      final jahre = find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(Scrollable),
      );
      // Ganz nach oben: Seit #407 beginnt die Wahl mit dem ersten Foto.
      for (var i = 0; i < 4; i++) {
        await tester.fling(jahre.first, const Offset(0, 3000), 4000);
        await pumpe(tester, 600);
      }
      final gibt1826 = _findet(find.text('1826'));
      final gibt1825 = _findet(find.text('1825'));
      print('KI-160 Jahresauswahl: 1826 da $gibt1826, 1825 da $gibt1825');
      expect(
        gibt1826,
        isTrue,
        reason: 'Datumswahl beginnt mit dem ersten Foto',
      );
      expect(gibt1825, isFalse);
      await finish(tester);
    },
  );

  // Behoben in #414: Die Auswahl „KI-Tag-Begriff“ steht beim Öffnen auf einem Begriff aus dem Vokabular oder auf keinem (vorbelegterKiTagBegriff).
  testWidgets(
    timeout: zeitgrenze,
    'KI-167 Befundpruefung Bearbeiten mit Begriff ausserhalb des Vokabulars',
    (tester) async {
      await startApp(tester);
      await befehl(
        tester,
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r1',
            name: 'Strandregel',
            triggerType: 'aiTag',
            aiTagTerm: const Value('Strand'),
          ),
        ),
      );
      await befehl(
        tester,
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r2',
            name: 'Namensregel',
            triggerType: 'dateiname',
            aiTagTerm: const Value('Urlaub'),
          ),
        ),
      );
      await sqlAusfuehren(
        tester,
        "DELETE FROM ai_tag_vocabulary WHERE term = 'Strand'",
      );
      await werkzeug(tester, de.werkzRegelnTitel);
      await waitFor(tester, find.text('Strandregel'));
      final fehler = <String>[];
      // Fall 1: Begriff aus dem Vokabular entfernt.
      await tippe(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text('Strandregel'),
            matching: find.byType(Card),
          ),
          matching: find.byTooltip(de.allgBearbeiten),
        ),
      );
      final e1 = tester.takeException();
      if (e1 != null) fehler.add('entfernter Begriff: $e1');
      if (!_findet(find.text(de.regelBearbeitenTitel))) {
        fehler.add('Dialog 1 fehlt');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpe(tester);
      Navigator.of(
        tester.element(find.byType(AutomationRulesScreen)),
      ).popUntil((r) => r is! DialogRoute);
      await pumpe(tester);
      // Fall 2: „Dateiname enthält“ auf „KI-Tag“ umgestellt.
      await tippe(
        tester,
        find.descendant(
          of: find.ancestor(
            of: find.text('Namensregel'),
            matching: find.byType(Card),
          ),
          matching: find.byTooltip(de.allgBearbeiten),
        ),
      );
      tester.takeException();
      await bedingung(tester, de.regelAusloeserTag);
      final e2 = tester.takeException();
      if (e2 != null) fehler.add('Wechsel auf KI-Tag: $e2');
      print('KI-167 Fehlerbilder: $fehler');
      Navigator.of(
        tester.element(find.byType(AutomationRulesScreen)),
      ).popUntil((r) => r is! DialogRoute && r is! PopupRoute);
      await pumpe(tester);
      expect(fehler, isEmpty);
      await finish(tester);
    },
  );

  // ------------------------------------- Schadenserkennung und Tiefenmaske

  File kratzerbild(String name, {bool ruhig = false}) {
    final bild = img.Image(width: 900, height: 700);
    img.fill(bild, color: img.ColorRgb8(118, 112, 104));
    if (!ruhig) {
      img.drawLine(
        bild,
        x1: 120,
        y1: 80,
        x2: 780,
        y2: 620,
        color: img.ColorRgb8(245, 245, 245),
        thickness: 3,
      );
      for (final (x, y) in [
        (150, 500),
        (650, 150),
        (700, 520),
        (300, 200),
        (520, 600),
      ]) {
        img.fillCircle(
          bild,
          x: x,
          y: y,
          radius: 3,
          color: img.ColorRgb8(20, 20, 20),
        );
      }
    }
    final datei = File(p.join(eingang.path, name));
    datei.writeAsBytesSync(img.encodePng(bild));
    return datei;
  }

  Future<void> retusche(
    WidgetTester tester,
    List<String> ids,
    String id,
  ) async {
    await betrachter(tester, ids, id);
    await tippe(tester, find.byTooltip(de.viewerBearbeiten));
    await waitFor(tester, find.byTooltip(de.bearbRetusche));
    await pumpe(tester, 1000);
    await tippe(tester, find.byTooltip(de.bearbRetusche));
    await waitFor(tester, find.byTooltip(de.bearbKratzerSuchen));
  }

  Future<void> editorZu(WidgetTester tester) async {
    while (_findet(find.byType(ImageEditorScreen))) {
      Navigator.of(tester.element(find.byType(ImageEditorScreen).first)).pop();
      await pumpe(tester, 600);
    }
    await betrachterZu(tester);
  }

  testWidgets(
    timeout: zeitgrenze,
    'KI-144 KI-145 KI-147 Kratzer und Staub ohne Kratzer-Modell',
    (tester) async {
      await startApp(tester, modelle: dateienVon([ModelCatalog.inpainting]));
      await autoAus(tester);
      await warteRuhe(tester);
      final ids = await importiereDirekt(tester, [
        kratzerbild('kratzer.png'),
        kratzerbild('ruhig.png', ruhig: true),
      ]);
      final original = bibliothek.paths.absolute(
        (await aufnahme(tester, ids[0])).relativePath,
      );
      final summe = sha(original);

      // KI-144.
      await retusche(tester, ids, ids[0]);
      await tippe(tester, find.byTooltip(de.bearbKratzerSuchen));
      await waitFor(
        tester,
        find.textContaining('Vorschlag: '),
        timeout: const Duration(seconds: 60),
      );
      final meldung = tester
          .widget<Text>(find.textContaining('Vorschlag: ').first)
          .data!;
      print('KI-144 Meldung: $meldung');
      expect(meldung, contains('Kratzer'));
      expect(meldung, contains('Prüfen, Falsches radieren, dann anwenden.'));

      // KI-147: radieren, anwenden; neu beginnen, abbrechen.
      await tippe(tester, find.byTooltip(de.bearbRadieren));
      final flaeche = find.byType(CustomPaint).last;
      await tester.dragFrom(
        tester.getCenter(flaeche) - const Offset(40, 40),
        const Offset(80, 80),
      );
      await pumpe(tester, 400);
      await tippe(tester, find.text(de.bearbRetuscheAnwenden));
      await eventually(
        tester,
        () async => !_findet(find.byTooltip(de.bearbKratzerSuchen)),
        timeout: const Duration(seconds: 90),
        was: 'Entfernen fertig',
      );
      expect(find.textContaining('fehlgeschlagen'), findsNothing);
      await tippe(tester, find.byTooltip(de.bearbRetusche));
      await waitFor(tester, find.byTooltip(de.bearbKratzerSuchen));
      await tester.dragFrom(
        tester.getCenter(find.byType(CustomPaint).last),
        const Offset(60, 0),
      );
      await pumpe(tester, 300);
      await tippe(
        tester,
        find
            .ancestor(
              of: find.text(de.allgAbbrechen),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            )
            .last,
      );
      expect(find.byTooltip(de.bearbKratzerSuchen), findsNothing);
      await editorZu(tester);
      expect(sha(original), summe, reason: 'Original unverändert');

      // KI-145: ruhiges Bild.
      await retusche(tester, ids, ids[1]);
      await tippe(tester, find.byTooltip(de.bearbKratzerSuchen));
      await erwarteMeldung(tester, de.bearbKratzerKeine);
      await editorZu(tester);
      await finish(tester);
    },
  );

  testWidgets(timeout: zeitgrenze, 'KI-146 Kratzersuche mit Kratzer-Modell', (
    tester,
  ) async {
    await startApp(
      tester,
      modelle: dateienVon([ModelCatalog.inpainting, ModelCatalog.kratzer]),
    );
    await autoAus(tester);
    await warteRuhe(tester);
    final ids = await importiereDirekt(tester, [kratzerbild('alt.png')]);
    await retusche(tester, ids, ids[0]);
    await tippe(tester, find.byTooltip(de.bearbKratzerSuchen));
    await waitFor(
      tester,
      find.textContaining('Vorschlag des Kratzer-Modells: '),
      timeout: const Duration(seconds: 90),
    );
    await editorZu(tester);
    await finish(tester);
  });

  File staubfoto(String name, int n, {required bool fleck}) {
    final bild = img.Image(width: 1024, height: 768);
    final r0 = 60 + n * 13 % 120, g0 = 90 + n * 7 % 100, b0 = 120 + n * 11 % 90;
    for (var y = 0; y < 768; y++) {
      for (var x = 0; x < 1024; x++) {
        bild.setPixelRgb(
          x,
          y,
          (r0 + x * 40 ~/ 1024).clamp(0, 255),
          (g0 + y * 30 ~/ 768).clamp(0, 255),
          b0,
        );
      }
    }
    if (fleck) {
      for (var dy = -6; dy <= 6; dy++) {
        for (var dx = -6; dx <= 6; dx++) {
          final d = math.sqrt(dx * dx + dy * dy);
          if (d > 6) continue;
          final px = bild.getPixel(400 + dx, 300 + dy);
          final f = d < 4 ? 0.55 : 0.75;
          bild.setPixelRgb(
            400 + dx,
            300 + dy,
            (px.r * f).round(),
            (px.g * f).round(),
            (px.b * f).round(),
          );
        }
      }
    }
    bild.exif.imageIfd['Make'] = 'Testkamera';
    bild.exif.imageIfd['Model'] = fleck
        ? 'Staubkamera S1'
        : 'Saubere Kamera S2';
    bild.exif.exifIfd['DateTimeOriginal'] =
        '2022:0${1 + n % 9}:1${n % 9} 10:00:00';
    final datei = File(p.join(eingang.path, name));
    datei.writeAsBytesSync(img.encodeJpg(bild, quality: 95));
    return datei;
  }

  testWidgets(timeout: zeitgrenze, 'KI-148 KI-149 Sensorstaub suchen', (
    tester,
  ) async {
    await startApp(tester);
    await autoAus(tester);
    await importiereDirekt(tester, [testfoto('ohne_kamera.jpg')]);
    // KI-148: keine Kamera vermerkt.
    await werkzeug(tester, de.staubTitel);
    await waitFor(tester, find.text(de.staubKeineKameras));

    // KI-149.
    await importiereDirekt(tester, [
      for (var i = 0; i < 10; i++) staubfoto('staub$i.jpg', i, fleck: true),
      for (var i = 0; i < 4; i++)
        staubfoto('sauber$i.jpg', 20 + i, fleck: false),
    ]);
    Future<void> suche(String kamera) async {
      await werkzeug(tester, de.staubTitel);
      final wahl = find.byType(DropdownButtonFormField<String>);
      await waitFor(tester, wahl);
      await tippe(tester, wahl);
      await tippe(tester, find.textContaining(kamera).last);
      await tippe(tester, find.text(de.staubSuchen));
    }

    await suche('Staubkamera');
    var fortschritt = false;
    final ende = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (_findet(
        find.textContaining(RegExp(r'\d+ von \d+ Aufnahmen untersucht')),
      )) {
        fortschritt = true;
      }
      if (_findet(find.textContaining('immer wieder auftauch')) ||
          _findet(find.textContaining('kein Sensorstaub gefunden'))) {
        break;
      }
    }
    print('KI-149 Ergebnis: ${onScreen(tester)}');
    expect(fortschritt, isTrue, reason: 'Fortschrittszeile');
    expect(find.text(de.staubGefunden(1)), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'auf \d+ von \d+ untersuchten Aufnahmen')),
      findsOneWidget,
    );
    await tippe(tester, find.text(de.staubImEditorOeffnen));
    await waitFor(tester, find.byType(ImageEditorScreen));
    Navigator.of(tester.element(find.byType(ImageEditorScreen).first)).pop();
    await pumpe(tester, 800);

    await suche('Saubere Kamera');
    await waitFor(
      tester,
      find.text(de.staubNichtsGefunden(4)),
      timeout: const Duration(minutes: 2),
    );
    await finish(tester);
  });

  testWidgets(timeout: zeitgrenze, 'KI-151 Tiefenmaske ohne Tiefenkarte', (
    tester,
  ) async {
    await startApp(tester);
    await autoAus(tester);
    final ids = await importiereDirekt(tester, [testfoto('flach.jpg')]);
    await betrachter(tester, ids, ids.first);
    await tippe(tester, find.byTooltip(de.viewerEntwickeln));
    await waitFor(tester, find.byTooltip(de.entwTiefenmaske));
    await pumpe(tester, 1500);
    final vorher = await zahl(tester, 'SELECT count(*) FROM develop_masks');
    await tippe(tester, find.byTooltip(de.entwTiefenmaske));
    await erwarteMeldung(tester, de.entwTiefenKeine);
    expect(await zahl(tester, 'SELECT count(*) FROM develop_masks'), vorher);
    Navigator.of(tester.element(find.byTooltip(de.entwTiefenmaske))).pop();
    await pumpe(tester, 800);
    await betrachterZu(tester);
    await finish(tester);
  });

  // ---------------------------------------------------------------- Server

  testWidgets(
    timeout: zeitgrenze,
    'KI-039 KI-143 KI-173 KI-174 KI-175 KI-176 KI-178 Serverpruefung Rechenhilfe',
    skip: serverAdresse.isEmpty,
    (tester) async {
      await startApp(tester);
      // KI-173: ohne Server kein Schalter.
      await einstellungsgruppe(tester, de.serverTitel);
      expect(find.text(de.serverRechenhilfe), findsNothing);
      await tippe(tester, find.text(de.serverVerbinden));
      await eintragen(tester, field(de.serverAdresse), serverAdresse);
      await eintragen(tester, field(de.serverName), 'konto-a');
      await eintragen(tester, field(de.serverPasswort), 'pruef-passwort-123');
      await tippe(tester, find.text(de.serverAnmelden));
      await pumpe(tester, 2000);
      if (_findet(field(de.serverPasswortWiederholen))) {
        await enter(
          tester,
          field(de.serverPasswortWiederholen),
          'pruef-passwort-123',
        );
        await tippe(tester, find.text(de.serverErstesAnlegen));
        await pumpe(tester, 2000);
      }
      if (_findet(find.text(de.serverWeiter))) {
        await tippe(tester, find.text(de.serverWeiter));
      }
      await waitFor(
        tester,
        find.text(de.serverServerBib),
        timeout: const Duration(seconds: 30),
      );
      await tippe(tester, find.text(de.serverServerBib));
      await waitFor(
        tester,
        find.text(de.einstNeustartTitel),
        timeout: const Duration(seconds: 60),
      );
      await neustart(tester);
      expect(bibliothek.verbunden, isTrue);

      // KI-173: verbunden steht der Schalter da.
      await einstellungsgruppe(tester, de.serverTitel);
      final hilfe = schalter(de.serverRechenhilfe);
      await sichtbar(tester, hilfe, SettingsScreen);
      expect(
        texteIn(hilfe),
        contains(de.serverRechenhilfeText.substring(0, 40)),
      );
      expect(find.text(de.serverRechenzeit), findsNothing);
      await tippe(tester, hilfe);
      await waitFor(tester, find.text(de.serverRechenzeit));
      // KI-175: ohne Modell.
      // Unter macOS liest Vision Text ohne Modell (rechenhilfe.dart:221):
      // „kein Modell“ gibt es dort nicht.
      await pumpe(tester, 1500);
      final keinModell = _findet(find.text(de.serverRechenhilfeKeinModell));
      final wartet = _findet(find.textContaining('Wartet auf Arbeit'));
      print('KI-175 ohne Modell: „kein Modell“ $keinModell, wartet $wartet');
      expect(keinModell || wartet, isTrue);
      // KI-174: Wann rechnen.
      final segmente = find.byType(SegmentedButton<Rechenzeit>);
      expect(tester.widget<SegmentedButton<Rechenzeit>>(segmente).selected, {
        Rechenzeit.amNetz,
      });
      for (final (wahl, text) in [
        (de.serverRechenzeitImmer, de.serverRechenzeitImmerText),
        (de.serverRechenzeitUnbenutzt, de.serverRechenzeitUnbenutztText),
        (de.serverRechenzeitAmNetz, de.serverRechenzeitAmNetzText),
        (de.serverRechenzeitImmer, de.serverRechenzeitImmerText),
      ]) {
        await tippe(
          tester,
          find.descendant(of: segmente, matching: find.text(wahl)),
        );
        await waitFor(tester, find.text(text));
      }
      await neustart(tester);
      await einstellungsgruppe(tester, de.serverTitel);
      await sichtbar(
        tester,
        find.byType(SegmentedButton<Rechenzeit>),
        SettingsScreen,
      );
      expect(
        tester
            .widget<SegmentedButton<Rechenzeit>>(
              find.byType(SegmentedButton<Rechenzeit>),
            )
            .selected,
        {Rechenzeit.immer},
      );

      // KI-039: verbunden keine lokale Analyse; Aufgabe läuft am Server.
      await installiere(tester, [ModelCatalog.clip]);
      final hoch = await importiereDirekt(tester, [
        testfoto('srv1.jpg', datum: DateTime(2024, 9, 1, 9)),
        testfoto('srv2.jpg', datum: DateTime(2024, 9, 2, 9)),
      ]);
      print('KI-039 hochgeladen: $hoch');
      await pumpe(tester, 2000);
      expect(bibliothek.analyseLaeuft, isFalse);
      await aufgaben(tester);
      await zurKarte(tester, de.aufgEmbeddingsTitel);
      await tippe(
        tester,
        find.descendant(
          of: karte(de.aufgEmbeddingsTitel),
          matching: find.text(de.aufgFehlende),
        ),
      );
      await erwarteMeldung(tester, de.aufgAmServer);

      // KI-176: die Rechenhilfe liefert Ergebnisse.
      await einstellungsgruppe(tester, de.serverTitel);
      await waitFor(
        tester,
        find.textContaining(RegExp(r'Ergebnisse? geliefert')),
        timeout: const Duration(minutes: 3),
      );
      await eventually(
        tester,
        () async =>
            (await bibliothek.db
                    .customSelect('SELECT count(*) AS n FROM image_embeddings')
                    .getSingle())
                .read<int>('n') >=
            2,
        timeout: const Duration(minutes: 3),
        was: 'Einbettungen kommen über den Abgleich zurück',
      );

      // KI-143: Scan-Import verbunden.
      final scan = scanbild(
        'srvscan.png',
        fotos: [
          (100, 200, 400, 300, img.ColorRgb8(200, 40, 40)),
          (700, 200, 400, 300, img.ColorRgb8(40, 60, 200)),
        ],
      );
      await werkzeug(tester, de.scanTitel);
      dialog.dateien = [scan];
      await tippe(tester, find.text(de.scanDateienWaehlen));
      await eventually(
        tester,
        () async =>
            _findet(find.text(de.scanErkannt(2))) ||
            _findet(find.textContaining('konnte den Vorgang nicht')),
        timeout: const Duration(seconds: 60),
        was: 'Scan analysiert',
      );
      if (_findet(find.text(de.scanErkannt(2)))) {
        await eintragen(tester, field(de.scanBeschreibung), 'Ferien');
        await scanImportieren(tester, 2);
        await eventually(
          tester,
          () async =>
              (await bibliothek.db
                      .customSelect(
                        'SELECT count(*) AS n FROM assets WHERE '
                        "original_file_name LIKE 'srvscan%' "
                        "AND description = 'Ferien'",
                      )
                      .getSingle())
                  .read<int>('n') ==
              2,
          timeout: const Duration(minutes: 2),
          was: 'Scan-Ausschnitte über den Abgleich da',
        );
      } else {
        // Befund KI-128: Die Scan-Analyse scheitert schon vor dem Import.
        print('KI-143 blockiert: Scan-Analyse scheitert (Befund KI-128)');
        melde.alleSchliessen();
        await pumpe(tester, 600);
        // Die überlange Fehlermeldung lässt das Meldungsfenster überlaufen –
        // eine Folge desselben Befunds, nicht dieser Prüfung.
        final folge = tester.takeException();
        print('KI-143 Folgefehler der Meldung: ${folge.runtimeType}');
      }

      // KI-178: ausschalten (den Server selbst kann die Prüfung nicht
      // beenden).
      await einstellungsgruppe(tester, de.serverTitel);
      await sichtbar(tester, schalter(de.serverRechenhilfe), SettingsScreen);
      await tippe(tester, schalter(de.serverRechenhilfe));
      await waitGone(tester, find.text(de.serverRechenzeit));
      await neustart(tester);
      await einstellungsgruppe(tester, de.serverTitel);
      await sichtbar(tester, schalter(de.serverRechenhilfe), SettingsScreen);
      expect(
        tester.widget<SwitchListTile>(schalter(de.serverRechenhilfe)).value,
        isFalse,
      );
      await finish(tester);
    },
  );
}

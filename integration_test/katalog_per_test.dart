// ignore_for_file: avoid_print
// Prüfkatalog, Bereich PER (Personen, Gesichter, Stammbaum, Familie):
// Ende-zu-Ende in der echten macOS-App mit Wegwerf-Bibliothek.
//
// **Wie die Gesichter entstehen.** Das Repo enthält keine Fotos mit
// echten Gesichtern. Gesichter, Personen und Verwandtschaften werden
// deshalb als Vorbedingung direkt in der Datenbank der Prüfbibliothek
// angelegt, wie es die Unittests unter test/ tun, und danach wird die
// Oberfläche bedient. Die Einbettungen sind handgemachte Vektoren mit
// 128 Stellen; so stehen die Ähnlichkeiten fest. YuNet und SFace werden
// nur dort aus dem Vorrat der Warteschlange verlinkt, wo der Lauf der
// Gesichtssuche selbst geprüft wird.
//
// Personen heissen „Person A“, „Person B“, „Kind“ …; Orte sind
// Koordinaten oder ausgedachte Namen („Prüfstadt“).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart' show lesbarerPfad;
import 'package:kern/services/embedding_codec.dart';
import 'package:kern/services/stammbaum.dart' show Verwandtschaft;
import 'package:kern/services/verwandtschaftsgrad.dart' show Geschlecht;
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/face_cluster_review_screen.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/screens/familienfotos_screen.dart';
import 'package:photo_vault/screens/familienorte_screen.dart';
import 'package:photo_vault/screens/familienstatistik_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/lebenslauf_screen.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/screens/person_detail_screen.dart';
import 'package:photo_vault/screens/person_suggestions_screen.dart';
import 'package:photo_vault/screens/soziogramm_screen.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/vorschlaege_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/hintergrundlauf.dart' show abweisungstext;
import 'package:photo_vault/theme/app_theme.dart' show DunkleFlaeche;
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/faecher_ansicht.dart';
import 'package:photo_vault/widgets/familien_zeitleiste.dart';
import 'package:photo_vault/widgets/familientage_abschnitt.dart';
import 'package:photo_vault/widgets/gesichtsrahmen.dart';
import 'package:photo_vault/widgets/lebensbaum_ansicht.dart';
import 'package:photo_vault/widgets/profilbild.dart';
import 'package:photo_vault/widgets/sanduhr_ansicht.dart';
import 'package:photo_vault/widgets/zierbaum_ansicht.dart';

import 'katalog_kit.dart';

// ---------------------------------------------------------------------------
// Vorbereitung
// ---------------------------------------------------------------------------

const _testPin = '4711';
const _gesichtsmodelle = [
  'face_detection_yunet.onnx',
  'face_recognition_sface.onnx',
];

var _nr = 0;
String _neueKennung(String vorsilbe) => '$vorsilbe${++_nr}';

/// Startet die App über das Kit und schaltet die automatische Auswertung
/// nach dem Import ab: Sie würde sonst parallel zu den angelegten
/// Gesichtern Vorschläge rechnen und Zahlen verschieben.
Future<void> start(WidgetTester tester, {Object modelle = false}) async {
  await startApp(tester, modelle: modelle);
  melde.verlaufLeeren();
  await tester.runAsync(() => bibliothek.db.setAutoAnalyzeAfterImport(false));
  await eventually(
    tester,
    () async => !bibliothek.analyseLaeuft,
    timeout: const Duration(seconds: 60),
    was: 'Startanalyse beendet',
  );
}

/// Datenbank- oder Dateiarbeit in echter Zeit.
Future<T> dbx<T>(WidgetTester tester, Future<T> Function() arbeit) async {
  late T ergebnis;
  await tester.runAsync(() async {
    ergebnis = await arbeit();
  });
  return ergebnis;
}

/// Importiert ohne Oberfläche; Ergebnis nach Dateiname.
Future<Map<String, AssetData>> fotos(
  WidgetTester tester,
  List<File> dateien,
) async {
  await importiereDirekt(tester, dateien);
  final alle = await dbx(
    tester,
    () => bibliothek.db.select(bibliothek.db.assets).get(),
  );
  return {for (final a in alle) a.originalFileName: a};
}

/// [n] Testfotos `<praefix>1.jpg` …, je einen Tag auseinander.
List<File> bilder(
  String praefix,
  int n, {
  int jahr = 2023,
  double? breite,
  double? laenge,
  int kante = 800,
}) => [
  for (var i = 1; i <= n; i++)
    testfoto(
      '$praefix$i.jpg',
      datum: DateTime(jahr, 1, 1, 10).add(Duration(days: i)),
      breitengrad: breite,
      laengengrad: laenge,
      breite: kante,
      hoehe: kante * 3 ~/ 4,
    ),
];

final _ausschnitte = <int, Uint8List>{};
Uint8List _ausschnitt(int n) => _ausschnitte.putIfAbsent(n % 12, () {
  final b = img.Image(width: 32, height: 32);
  img.fill(
    b,
    color: img.ColorRgb8(
      40 + (n * 37) % 200,
      60 + (n * 53) % 180,
      80 + (n * 71) % 160,
    ),
  );
  return Uint8List.fromList(img.encodeJpg(b));
});

/// Legt ein erkanntes Gesicht mit eigener Ausschnittdatei an.
Future<String> gesicht(
  String assetId, {
  String? person,
  bool ignoriert = false,
  Float32List? vektor,
  double x = 0.1,
  double y = 0.1,
  double w = 0.2,
  double h = 0.25,
  String? ausschnitt,
}) async {
  final id = _neueKennung('g');
  final rel = ausschnitt ?? bibliothek.paths.faceRelativePath(id);
  final datei = bibliothek.paths.absolute(rel);
  if (!datei.existsSync()) {
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(_ausschnitt(_nr));
  }
  await bibliothek.db.insertFace(
    FacesCompanion.insert(
      id: id,
      assetId: assetId,
      boxX: x,
      boxY: y,
      boxW: w,
      boxH: h,
      cropRelativePath: Value(rel),
      personId: Value(person),
      isIgnored: Value(ignoriert),
      embedding: Value(vektor == null ? null : blobFromEmbeddingFloats(vektor)),
    ),
  );
  if (person != null) {
    await bibliothek.db.setPersonCoverIfUnset(person, rel);
  }
  return id;
}

/// Eine Zeile für [vieleGesichter] (gemeinsamer Ausschnitt).
FacesCompanion gesichtszeile(
  String assetId,
  String ausschnitt, {
  String? person,
  bool ignoriert = false,
  Float32List? vektor,
  String? id,
}) => FacesCompanion.insert(
  id: id ?? _neueKennung('m'),
  assetId: assetId,
  boxX: 0.1,
  boxY: 0.1,
  boxW: 0.2,
  boxH: 0.2,
  cropRelativePath: Value(ausschnitt),
  personId: Value(person),
  isIgnored: Value(ignoriert),
  embedding: Value(vektor == null ? null : blobFromEmbeddingFloats(vektor)),
);

Future<void> vieleGesichter(List<FacesCompanion> zeilen) =>
    bibliothek.db.batch((b) => b.insertAll(bibliothek.db.faces, zeilen));

/// Eine Ausschnittdatei, die sich viele Gesichter teilen.
String gemeinsamerAusschnitt(String name) {
  final rel = 'faces/$name.jpg';
  final f = bibliothek.paths.absolute(rel);
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(_ausschnitt(name.length));
  return rel;
}

Future<String> person(
  String name, {
  DateTime? geburt,
  DateTime? tod,
  Geschlecht? geschlecht,
}) async {
  final id = _neueKennung('p');
  await bibliothek.db.fuehreAus(PersonAnlegen(id, name));
  if (geburt != null || tod != null) {
    await bibliothek.db.fuehreAus(
      LebensdatenSetzen(id, geburt: geburt, tod: tod),
    );
  }
  if (geschlecht != null) {
    await bibliothek.db.fuehreAus(GeschlechtSetzen(id, geschlecht));
  }
  return id;
}

/// [elternteil] ist ein Elternteil von [kind].
Future<void> verwandt(
  String kind,
  String elternteil, [
  Verwandtschaft art = Verwandtschaft.elternteil,
]) async {
  final fehler = await bibliothek.db.fuehreAus(
    BeziehungHinzufuegen(kind, elternteil, art),
  );
  if (fehler != null) throw StateError('Beziehung: $fehler');
}

Future<void> partner(String a, String b) =>
    verwandt(a, b, Verwandtschaft.partner);

Future<String> ereignis(
  String personId,
  String art, {
  DateTime? datum,
  String? ort,
  String? notiz,
  double? breite,
  double? laenge,
}) async {
  final id = _neueKennung('e');
  await bibliothek.db.fuehreAus(
    EreignisHinzufuegen((
      id: id,
      personId: personId,
      art: art,
      datum: datum,
      ort: ort,
      notiz: notiz,
    )),
  );
  if (breite != null && laenge != null) {
    await bibliothek.db.fuehreAus(
      EreignisortSetzen(id, breite: breite, laenge: laenge),
    );
  }
  return id;
}

Future<FaceData> gesichtZeile(WidgetTester tester, String id) => dbx(
  tester,
  () => (bibliothek.db.select(
    bibliothek.db.faces,
  )..where((t) => t.id.equals(id))).getSingle(),
);

Future<List<FaceData>> alleGesichter(WidgetTester tester) =>
    dbx(tester, () => bibliothek.db.select(bibliothek.db.faces).get());

Future<PersonData?> personZeile(WidgetTester tester, String id) => dbx(
  tester,
  () => (bibliothek.db.select(
    bibliothek.db.people,
  )..where((t) => t.id.equals(id))).getSingleOrNull(),
);

Future<List<PersonData>> allePersonen(WidgetTester tester) =>
    dbx(tester, () => bibliothek.db.select(bibliothek.db.people).get());

Future<PersonData> personNamens(WidgetTester tester, String name) async =>
    (await allePersonen(tester)).firstWhere((p) => p.name == name);

Future<AssetData> assetZeile(WidgetTester tester, String id) => dbx(
  tester,
  () => (bibliothek.db.select(
    bibliothek.db.assets,
  )..where((t) => t.id.equals(id))).getSingle(),
);

Future<List<FaceMatchFeedbackData>> rueckmeldungen(WidgetTester tester) => dbx(
  tester,
  () => bibliothek.db.select(bibliothek.db.faceMatchFeedback).get(),
);

/// Die Originaldatei eines Fotos, für den Vergleich vorher/nachher.
Future<List<int>> originalBytes(WidgetTester tester, AssetData a) =>
    dbx(tester, () => bibliothek.paths.absolute(a.relativePath).readAsBytes());

/// Ein Einheitsvektor aus den gewichteten Richtungen [teile].
Float32List vek(Map<int, double> teile) {
  final v = Float32List(128);
  teile.forEach((i, w) => v[i] = w);
  var n = 0.0;
  for (final x in v) {
    n += x * x;
  }
  n = math.sqrt(n);
  for (var i = 0; i < v.length; i++) {
    v[i] = v[i] / n;
  }
  return v;
}

Float32List richtung(int i) => vek({i: 1});

/// Das Ortsverzeichnis als kleiner, ausgedachter Auszug (statt des
/// GeoNames-Downloads): ein Ort „Prüfstadt“ bei 47,25 / 9,75.
Future<void> ortsverzeichnisEinrichten(WidgetTester tester) async {
  await tester.runAsync(() async {
    final d = bibliothek.geoDataDownloadService;
    d.citiesFile.parent.createSync(recursive: true);
    d.citiesFile.writeAsStringSync(
      '900001\tPrüfstadt\tPruefstadt\t\t47.25\t9.75\tP\tPPL\tXT\t\t01\t\t\t\t12000\t\t400\tEurope/Berlin\t2024\n',
    );
    d.admin1File.writeAsStringSync('XT.01\tPrüfland\tPruefland\t1\n');
    d.countryFile.writeAsStringSync(
      'XT\tXTT\t999\tXT\tTestland\tPrüfstadt\t1000\t1000\tEU\t.xt\tEUR\tEuro\t99\t\t\tde-DE\t900002\t\t\n',
    );
    await bibliothek.reloadGeoData();
  });
}

// ---------------------------------------------------------------------------
// Bedienung
// ---------------------------------------------------------------------------

Future<void> warte(WidgetTester tester, int ms) async {
  final ende = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

bool sichtbar(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Einfacher Klick auf ein Ziel, das auch einen Doppelklick kennt: Der
/// einfache Klick kommt erst nach der Doppelklick-Frist an.
///
/// Ohne `ensureVisible`: Das schiebt jeden umgebenden Scrollbereich, auch
/// den waagerechten der TabBarView – und wechselt damit unbemerkt den
/// Reiter (bei Kacheln in der rechten Hälfte auf „Ignoriert“).
Future<void> tippe(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  await tester.tap(f.first);
  await warte(tester, 450);
}

/// Wie `tap` aus dem Kit, aber ohne `ensureVisible` (siehe [tippe]).
Future<void> klick(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  await tester.tap(f.first);
  await settle(tester);
}

/// Langer Druck mit echter Wartezeit (der Erkenner braucht 500 ms).
Future<void> langDruecken(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  final geste = await tester.startGesture(tester.getCenter(f.first));
  await warte(tester, 900);
  await geste.up();
  await warte(tester, 500);
}

Future<void> doppelklick(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  final stelle = tester.getCenter(f.first);
  await tester.tapAt(stelle);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(stelle);
  await warte(tester, 500);
}

Future<void> rechtsklickBei(WidgetTester tester, Offset stelle) async {
  final maus = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await maus.addPointer(location: stelle);
  await maus.down(stelle);
  await tester.pump(const Duration(milliseconds: 30));
  await maus.up();
  await maus.removePointer();
  await warte(tester, 400);
}

Future<void> rechtsklick(
  WidgetTester tester,
  Finder f, {
  Offset versatz = Offset.zero,
}) async {
  await waitFor(tester, f);
  await rechtsklickBei(tester, tester.getCenter(f.first) + versatz);
}

/// Schliesst ein offenes Kontextmenü der Gesichter-Ansicht mit einem Klick
/// in die leere Titelleiste. Escape bei offenem MenuAnchor löste im
/// Testlauf eine Kette von Rahmenwerk-Zusicherungen aus
/// („_HighlightModeManager … deactivated widget“).
/// Duldet Rahmenwerk-Fehlermeldungen, die [muster] enthalten (bekannter
/// Folgefehler eines Befunds), und gibt den Weg zurück.
void Function() kennFehlerDulden(Object muster) {
  final liste = muster is List<String> ? muster : [muster as String];
  final vorher = FlutterError.onError;
  FlutterError.onError = (d) {
    final text = d.exceptionAsString();
    if (liste.any(text.contains)) {
      print('geduldet: ${text.split('\n').first}');
      return;
    }
    vorher?.call(d);
  };
  void zurueck() => FlutterError.onError = vorher;
  addTearDown(zurueck);
  return zurueck;
}

/// Schliesst einen nach „Automatisch gruppieren“ stehen gebliebenen
/// Fortschrittsdialog über seinen Knopf „Abbrechen“ (Befund PER-044).
Future<void> haengendenDialogSchliessen(WidgetTester tester) async {
  await warte(tester, 800);
  final abbrechen = imDialog(find.text(de.allgAbbrechen));
  if (sichtbar(abbrechen)) {
    print('hängender Fortschrittsdialog wird geschlossen');
    await klick(tester, abbrechen);
    await waitGone(tester, find.byType(AlertDialog));
  }
}

/// Rahmenwerk-Zusicherungen beim Aufbau des Semantikbaums.
///
/// Auf dem Prüfrechner ist die Semantik eingeschaltet (Bedienungshilfen
/// anderer Werkzeuge). Ändern Aktionen aus dem Kontextmenü eines
/// Gesichtsrahmens die Rahmen, meldet `flushSemantics` dann Dutzende
/// Zusicherungen – ohne Bezug zum geprüften Ergebnis, im Bericht als
/// Beobachtung festgehalten.
const _semantikZusicherungen = [
  "'!child.attached': is not true",
  "'node.built': is not true",
  "'_owner == null': is not true",
  "'node.parent?._dirty != true': is not true",
];

Future<void> menueZu(WidgetTester tester) async {
  final leiste = find.descendant(
    of: find.byType(FaceReviewScreen),
    matching: find.byType(AppBar),
  );
  await tester.tapAt(tester.getCenter(leiste.first));
  await warte(tester, 400);
}

/// Eine Taste – in der Gesichter-Ansicht vorher mit Fokus auf ihr.
///
/// Ihr `Focus(autofocus: true)` bekommt den Fokus nicht immer, wenn vorher
/// eine andere Ansicht offen war (in der Prüfung gelegentlich nach der
/// Rückkehr aus der Vollbildansicht); ein Mensch klickte dann ins Fenster.
Future<void> taste(WidgetTester tester, LogicalKeyboardKey k) async {
  final ansicht = find.descendant(
    of: find.byType(FaceReviewScreen),
    matching: find.byType(Scaffold),
  );
  if (sichtbar(ansicht) &&
      !sichtbar(find.byType(AlertDialog)) &&
      !sichtbar(find.byType(MenuItemButton))) {
    Focus.of(tester.element(ansicht.first)).requestFocus();
    await tester.pump();
  }
  await key(tester, k);
}

Future<void> zurueck(WidgetTester tester) async {
  final k = find.byType(BackButton);
  if (k.evaluate().isNotEmpty) {
    await tester.tap(k.last);
  } else {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  }
  await warte(tester, 500);
}

Finder reiter(String beschriftung) => find.descendant(
  of: find.byType(Tab),
  matching: find.textContaining(beschriftung),
);

Finder reiterText(String text) =>
    find.descendant(of: find.byType(Tab), matching: find.text(text));

Finder imDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Finder kachel(String faceId) => find.byWidgetPredicate(
  (w) =>
      w is LocalImageTile && p.basenameWithoutExtension(w.file.path) == faceId,
);

Finder get kacheln => find.byType(LocalImageTile);

List<String> kachelReihe(WidgetTester tester) => [
  for (final k in tester.widgetList<LocalImageTile>(kacheln))
    p.basenameWithoutExtension(k.file.path),
];

Finder rahmen(String faceId) => find.byWidgetPredicate(
  (w) => w is Gesichtsrahmen && w.gesicht.id == faceId,
);

/// Der Knopf (FilledButton, OutlinedButton … auch mit Symbol) mit [text].
Finder knopf(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool knopfAktiv(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(knopf(text).first).enabled;

IconButton symbolknopf(WidgetTester tester, String tooltip) =>
    tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );

Finder dialogZeile(String name) =>
    imDialog(find.widgetWithText(ListTile, name));

Meldung? meldung(String text) {
  for (final m in melde.verlauf) {
    if (m.text == text) return m;
  }
  return null;
}

Future<Meldung> erwarteText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    final m = meldung(text);
    if (m != null) return m;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure(
    'Meldung fehlt: „$text“\nVerlauf: '
    '${melde.verlauf.map((m) => m.text).join(' | ')}\n'
    'Auf dem Bildschirm: ${onScreen(tester)}',
  );
}

Future<void> rueckgaengig(WidgetTester tester) async {
  await klick(tester, find.text(de.allgRueckgaengig).last);
  await warte(tester, 600);
}

Future<void> personenOeffnen(WidgetTester tester, {String? reiterName}) async {
  await openSection(tester, Hauptbereich.alben);
  await openSection(tester, Hauptbereich.personen);
  await waitFor(tester, find.byType(PeopleScreen));
  await warte(tester, 500);
  if (reiterName != null) {
    await klick(tester, reiter(reiterName));
    await warte(tester, 400);
  }
}

/// Wählt Gesichter im Raster aus (Klick je Kachel).
Future<void> waehle(WidgetTester tester, List<String> faceIds) async {
  for (final id in faceIds) {
    await tippe(tester, kachel(id));
  }
}

bool ausgewaehlt(WidgetTester tester, String faceId) =>
    tester.widget<LocalImageTile>(kachel(faceId)).selected;

/// Öffnet über den runden Knopf einer Kachel das ganze Foto.
Future<void> imFotoZeigen(WidgetTester tester, String faceId) async {
  final rahmenDerKachel = find
      .ancestor(of: kachel(faceId), matching: find.byType(Stack))
      .first;
  await klick(
    tester,
    find.descendant(
      of: rahmenDerKachel,
      matching: find.byTooltip(de.gesichtImFoto),
    ),
  );
  await waitFor(tester, find.byType(FaceReviewScreen));
  await warte(tester, 600);
}

/// Ordnet die Auswahl über den Dialog einer neuen Person zu.
Future<void> neuePersonImDialog(WidgetTester tester, String name) async {
  await waitFor(tester, find.byType(AlertDialog));
  await enter(tester, imDialog(field(de.personSuchenOderAnlegen)), name);
  await klick(tester, imDialog(find.text(de.personAnlegenAktion(name))));
  await warte(tester, 600);
}

/// Wählt im Dialog eine bestehende Person und bestätigt.
Future<void> bestehendePersonImDialog(WidgetTester tester, String name) async {
  await waitFor(tester, find.byType(AlertDialog));
  await klick(tester, dialogZeile(name));
  await klick(tester, imDialog(find.text(de.personZuordnenAktion)));
  await warte(tester, 600);
}

Future<void> stammbaumOeffnen(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.alben);
  await openSection(tester, Hauptbereich.stammbaum);
  await waitFor(tester, find.byType(StammbaumScreen));
  await warte(tester, 600);
}

/// Rückt [name] über „Andere Person in die Mitte“ in die Mitte.
Future<void> mitte(WidgetTester tester, String name) async {
  await klick(tester, find.byTooltip(de.stammbaumAndereWaehlen));
  await enter(tester, imDialog(field(de.personSuchenOderAnlegen)), name);
  await klick(
    tester,
    imDialog(find.widgetWithText(FilledButton, de.personZuordnenAktion)),
  );
  await waitFor(tester, find.text(de.stammbaumTitelVon(name)));
  await warte(tester, 400);
}

/// Ein Eintrag aus dem Menü „Mehr“ des Stammbaums.
Future<void> stammbaumMehr(WidgetTester tester, String eintrag) async {
  melde.alleSchliessen();
  await klick(
    tester,
    find.descendant(
      of: find.byType(StammbaumScreen),
      matching: find.byTooltip(de.allgMehr),
    ),
  );
  await klick(tester, find.text(eintrag).last);
  await warte(tester, 500);
}

Finder werkzeugListe() => find
    .descendant(of: find.byType(ToolsScreen), matching: find.byType(Scrollable))
    .first;

Finder schild(String name) => find.descendant(
  of: find.byType(ZierbaumAnsicht),
  matching: find.text(name),
);

/// Öffnet das Menü eines Schildes im Baum per Rechtsklick.
Future<void> schildMenue(WidgetTester tester, String name) async {
  await rechtsklick(tester, schild(name));
  await waitFor(tester, find.text(de.stammbaumLebensdaten));
}

/// Gibt im offenen Datumsdialog ein Datum über die Texteingabe ein.
Future<void> datumEingeben(WidgetTester tester, DateTime datum) async {
  await waitFor(tester, find.byType(DatePickerDialog));
  final ml = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await klick(tester, find.byTooltip(ml.inputDateModeButtonLabel));
  final feld = find.descendant(
    of: find.byType(DatePickerDialog),
    matching: find.byType(TextField),
  );
  await enter(tester, feld, ml.formatCompactDate(datum));
  await klick(tester, find.text(ml.okButtonLabel));
  await warte(tester, 300);
}

/// Liest eine GEDCOM-Datei über „Mehr“ → „GEDCOM einlesen …“ ein.
Future<void> gedcomEinlesen(WidgetTester tester, String inhalt) async {
  final datei = File(p.join(eingang.path, 'familie_${++_nr}.ged'))
    ..writeAsStringSync(inhalt);
  dialog.dateien = [datei];
  await stammbaumMehr(tester, de.stammbaumGedcomImport);
  await waitFor(
    tester,
    find.text(de.gedcomImportTitel),
    timeout: const Duration(seconds: 60),
  );
  await klick(tester, find.text(de.gedcomImportUebernehmen));
  await waitFor(
    tester,
    find.text(de.gedcomBerichtTitel),
    timeout: const Duration(seconds: 120),
  );
  await klick(tester, imDialog(find.text(de.allgSchliessen)));
  await warte(tester, 500);
}

String gedcom(List<String> zeilen) => [
  '0 HEAD',
  '1 CHAR UTF-8',
  '1 GEDC',
  '2 VERS 5.5.1',
  ...zeilen,
  '0 TRLR',
].join('\r\n');

/// Startet in „Werkzeuge → Aufgaben“ eine Aufgabe über ihren Knopf.
Future<void> aufgabeStarten(
  WidgetTester tester,
  String titel,
  String modus,
) async {
  await openSection(tester, Hauptbereich.alben);
  await openSection(tester, Hauptbereich.werkzeuge);
  await tap(tester, find.text(de.aufgTitel).first);
  await waitFor(tester, find.byType(BackgroundTasksScreen));
  final karte = find.ancestor(
    of: find.text(titel),
    matching: find.byType(Card),
  );
  await scrollTo(
    tester,
    find.text(titel),
    in_: find
        .descendant(
          of: find.byType(BackgroundTasksScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  // Ein beendeter früherer Lauf steht noch in der Karte; erst schliessen.
  final schliessen = find.descendant(
    of: karte.first,
    matching: find.text(de.allgSchliessen),
  );
  if (sichtbar(schliessen)) {
    await tap(tester, schliessen);
    await warte(tester, 400);
  }
  await tap(
    tester,
    find.descendant(of: karte.first, matching: find.text(modus)),
  );
}

Future<void> warteAufLauf(WidgetTester tester, String schluessel) async {
  await eventually(
    tester,
    () async => !(bibliothek.lauf(schluessel)?.offen ?? false),
    timeout: const Duration(seconds: 180),
    was: 'Lauf $schluessel beendet',
  );
  await warte(tester, 300);
}

/// Speicherdialog, der genau an den gewählten Pfad schreibt – wie der
/// echte Dialog, der eine leere Platzhalterdatei hinterlässt.
class _GenauerSpeicherdialog extends KatalogDateidialog {
  String? ziel;
  bool platzhalter = true;
  final namen = <String>[];

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
    namen.add(fileName);
    final z = ziel;
    if (z == null) return null;
    if (platzhalter) {
      try {
        File(z).writeAsBytesSync(bytes);
      } on FileSystemException {
        // Wie der echte Dialog: das Ziel bleibt gewählt.
      }
    }
    return File(z).uri;
  }
}

_GenauerSpeicherdialog _genauerDialog() {
  final d = _GenauerSpeicherdialog();
  FilePickerPlatform.instance = d;
  addTearDown(() => FilePickerPlatform.instance = dialog);
  return d;
}

/// Protokolliert, ob irgendwo ein HTTP-Client entsteht.
class _Netzprotokoll extends HttpOverrides {
  final clients = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients.add(StackTrace.current.toString().split('\n').take(6).join(' / '));
    return super.createHttpClient(context);
  }
}

bool _istRaute(Widget w) => w.runtimeType.toString() == '_Ereignismarke';
bool _istOrtsmarke(Widget w) => w.runtimeType.toString() == '_Ortsmarke';

/// Ein `testWidgets`, dessen Rumpf in einer eigenen Fehlerzone läuft.
///
/// **Warum.** Die Restaurierungs-Warteschlange stellt bei jedem Zeiger-
/// ereignis (lib/main.dart:206) eine Uhr auf 20 Sekunden Leerlauf und
/// fragt danach die Datenbank. Läuft die Uhr erst nach `finish()` ab, ist
/// die Datenbank geschlossen, und drift meldet „connection was closed“ –
/// als Fehler der längst beendeten Prüfung. Genau dieser eine Fehler wird
/// hier verschluckt; jeder andere scheitert die Prüfung wie gewohnt.
void pruefung(
  String name,
  Future<void> Function(WidgetTester tester) rumpf, {
  bool skip = false,
}) => testWidgets(name, (tester) {
  final fertig = Completer<void>();
  Object? fremd;
  StackTrace? fremdStapel;
  runZonedGuarded(
    () async {
      try {
        await rumpf(tester);
      } catch (fehler, stapel) {
        if (!fertig.isCompleted) fertig.completeError(fehler, stapel);
        return;
      }
      if (fertig.isCompleted) return;
      // Ein verirrter Fehler während der Prüfung lässt sie scheitern –
      // aber erst, wenn ihr Rumpf durch ist, damit nichts in die nächste
      // Prüfung hineinpumpt.
      if (fremd != null) {
        fertig.completeError(fremd!, fremdStapel);
      } else {
        fertig.complete();
      }
    },
    (fehler, stapel) {
      final text = '$fehler';
      if (text.contains('connection was closed') ||
          text.contains('after closing')) {
        print('nach finish() verschluckt: ${text.split('\n').first}');
        return;
      }
      print('Fehler in der Prüfung: ${text.split('\n').first}');
      fremd ??= fehler;
      fremdStapel ??= stapel;
    },
  );
  return fertig.future;
}, skip: skip);

// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Personen – Übersicht
  // =========================================================================

  pruefung('PER-001 PER-002 PER-003 PER-035 Reiter, leere Zustände, Kacheln', (
    tester,
  ) async {
    await start(tester);
    await personenOeffnen(tester);
    // PER-002: leerer Reiter „Personen“, ohne Zahl.
    await waitFor(tester, find.text(de.personenLeer));
    expect(reiterText(de.personenTab), findsOneWidget);
    expect(reiterText(de.personenUnbenannteTab), findsOneWidget);
    expect(reiterText(de.personenIgnoriertTab), findsOneWidget);
    // PER-035: leerer Reiter „Ignoriert“.
    await klick(tester, reiter(de.personenIgnoriertTab));
    await waitFor(tester, find.text(de.personenIgnoriertLeer));

    final f = await fotos(tester, bilder('ue', 9));
    final ids = [for (var i = 1; i <= 9; i++) f['ue$i.jpg']!.id];
    late String a;
    await tester.runAsync(() async {
      a = await person('Person A');
      await person('Person B');
      await gesicht(ids[0], person: a);
      for (var i = 1; i <= 5; i++) {
        await gesicht(ids[i]);
      }
      for (var i = 6; i <= 8; i++) {
        await gesicht(ids[i], ignoriert: true);
      }
    });
    // PER-001
    await personenOeffnen(tester);
    await waitFor(tester, reiterText(de.tabMitZahl(de.personenTab, 2)));
    expect(
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 5)),
      findsOneWidget,
    );
    expect(
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 3)),
      findsOneWidget,
    );

    // PER-003: Kachel mit Profilbild bzw. Platzhalter, Name, Hinweis.
    const langerName =
        'Person C mit einem ungewöhnlich langen Namen, der nicht in die Kachel passt';
    await tester.runAsync(() => person(langerName));
    await personenOeffnen(tester);
    await waitFor(tester, find.text('Person A'));
    Profilbild bildVon(String name) => tester.widget<Profilbild>(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(name), matching: find.byType(InkWell))
                .first,
            matching: find.byType(Profilbild),
          )
          .first,
    );
    expect(bildVon('Person A').datei, isNotNull);
    expect(bildVon('Person B').datei, isNull, reason: 'Platzhalter');
    expect(find.text(de.personenLangeDruecken), findsNWidgets(3));
    final lang = tester.widget<Text>(find.text(langerName));
    expect(lang.maxLines, 1);
    expect(lang.overflow, TextOverflow.ellipsis);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(langerName))
          .didExceedMaxLines,
      isTrue,
      reason: 'der lange Name wird gekürzt',
    );
    await finish(tester);
  });

  pruefung('PER-004 PER-058 PER-068 PER-091 Personenansicht und Blättern', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, [...bilder('pa', 5), ...bilder('pb', 1)]);
    late String a;
    await tester.runAsync(() async {
      a = await person('Person A');
      final b = await person('Person B');
      for (var i = 1; i <= 5; i++) {
        await gesicht(f['pa$i.jpg']!.id, person: a);
      }
      // Ein Foto mit zwei Gesichtern von Person A.
      await gesicht(f['pa4.jpg']!.id, person: a, x: 0.6);
      await gesicht(f['pb1.jpg']!.id, person: b);
    });
    await personenOeffnen(tester);
    // PER-004
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Person A')),
      findsOneWidget,
    );
    // PER-058
    await waitFor(tester, find.text(de.personDoppelklickHinweis));
    expect(find.text(de.personProfilbildAendern), findsOneWidget);
    expect(find.text(de.personWeitereFotosSuchen), findsOneWidget);
    expect(
      tester
          .widget<Profilbild>(
            find
                .descendant(
                  of: find.byType(PersonDetailScreen),
                  matching: find.byType(Profilbild),
                )
                .first,
          )
          .datei,
      isNotNull,
    );
    final detailKacheln = find.descendant(
      of: find.byType(PersonDetailScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    expect(
      detailKacheln,
      findsNWidgets(5),
      reason: 'Foto mit 2 Gesichtern einmal',
    );
    expect(
      [
        for (final k in tester.widgetList<AssetThumbnailTile>(detailKacheln))
          k.asset.id,
      ],
      [for (var i = 5; i >= 1; i--) f['pa$i.jpg']!.id],
      reason: 'neueste zuerst',
    );
    // Es gibt keinen Weg zum Umbenennen oder Löschen (Hinweis PER-058).
    expect(find.byTooltip('Umbenennen'), findsNothing);

    // PER-068: einfacher Klick → Vollbild mit allen Fotos der Person.
    await tippe(tester, detailKacheln.at(1));
    await waitFor(tester, find.byType(AssetViewerScreen));
    final viewer = tester.widget<AssetViewerScreen>(
      find.byType(AssetViewerScreen),
    );
    expect(viewer.assets.length, 5);
    expect(viewer.initialIndex, 1);
    await zurueck(tester);
    await waitGone(tester, find.byType(AssetViewerScreen));
    // Doppelklick → Gesichter-Ansicht mit Rahmen.
    await doppelklick(tester, detailKacheln.at(0));
    await waitFor(tester, find.byType(FaceReviewScreen));
    await waitFor(tester, find.byType(Gesichtsrahmen));

    // PER-091: Titel, Position, Pfeile.
    expect(find.text(de.gesichtPosition(1, 5)), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.text('pa5.jpg'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip(de.gesichtVoriges), findsOneWidget);
    expect(find.byTooltip(de.gesichtNaechstes), findsOneWidget);
    expect(symbolknopf(tester, de.gesichtVoriges).onPressed, isNull);
    await taste(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, find.text(de.gesichtPosition(2, 5)));
    for (var i = 0; i < 3; i++) {
      await klick(tester, find.byTooltip(de.gesichtNaechstes));
    }
    await waitFor(tester, find.text(de.gesichtPosition(5, 5)));
    expect(symbolknopf(tester, de.gesichtNaechstes).onPressed, isNull);
    await taste(tester, LogicalKeyboardKey.arrowRight);
    expect(
      find.text(de.gesichtPosition(5, 5)),
      findsOneWidget,
      reason: 'kein Sprung zum Anfang',
    );
    await zurueck(tester);
    await waitGone(tester, find.byType(FaceReviewScreen));
    // Bei nur einem Foto fehlen die Pfeile.
    await personenOeffnen(tester);
    await klick(tester, find.text('Person B'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await doppelklick(
      tester,
      find.descendant(
        of: find.byType(PersonDetailScreen),
        matching: find.byType(AssetThumbnailTile),
      ),
    );
    await waitFor(tester, find.byType(FaceReviewScreen));
    expect(find.byTooltip(de.gesichtVoriges), findsNothing);
    expect(find.byTooltip(de.gesichtNaechstes), findsNothing);
    await finish(tester);
  });

  pruefung('PER-005 PER-196 PER-198 Wer mit wem', (tester) async {
    await start(tester);
    final f = await fotos(tester, [
      testfoto('s1.jpg', datum: DateTime(2022, 3, 1)),
      testfoto('s2.jpg', datum: DateTime(2024, 3, 1)),
      testfoto('s3.jpg', datum: DateTime(2023, 3, 1)),
    ]);
    late String a, b;
    await tester.runAsync(() async {
      a = await person('Person A');
      b = await person('Person B');
      await gesicht(f['s1.jpg']!.id, person: a);
      await gesicht(f['s1.jpg']!.id, person: b, x: 0.6);
      await gesicht(f['s2.jpg']!.id, person: a);
      await gesicht(f['s3.jpg']!.id, person: a);
    });
    // PER-005, PER-196: nur ein gemeinsames Foto → leer.
    await personenOeffnen(tester);
    await klick(tester, find.byTooltip(de.soziogrammTitel));
    await waitFor(tester, find.byType(SoziogrammScreen));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.soziogrammTitel),
      ),
      findsOneWidget,
    );
    await waitFor(tester, find.text(de.soziogrammLeer));
    await zurueck(tester);
    // PER-198: zweites gemeinsames Foto.
    await tester.runAsync(() => gesicht(f['s2.jpg']!.id, person: b, x: 0.6));
    await personenOeffnen(tester);
    await klick(tester, find.byTooltip(de.soziogrammTitel));
    await waitFor(tester, find.textContaining(' & '));
    final verbindung = tester.widget<Text>(find.textContaining(' & ').first);
    expect(verbindung.data, contains('Person A'));
    expect(verbindung.data, contains('Person B'));
    expect(find.text(de.soziogrammGemeinsam(2)), findsWidgets);
    await klick(tester, find.textContaining(' & ').first);
    await waitFor(tester, find.byType(AssetViewerScreen));
    final viewer = tester.widget<AssetViewerScreen>(
      find.byType(AssetViewerScreen),
    );
    expect(
      [for (final x in viewer.assets) x.id],
      [f['s2.jpg']!.id, f['s1.jpg']!.id],
      reason: 'genau die gemeinsamen, neueste zuerst',
    );
    await finish(tester);
  });

  pruefung('PER-006 Personen im Info-Bereich eines Fotos', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('in', 2));
    await tester.runAsync(() async {
      final a = await person('Person A');
      await gesicht(f['in1.jpg']!.id, person: a);
      await gesicht(f['in1.jpg']!.id, person: a, x: 0.6);
      await gesicht(f['in2.jpg']!.id, person: a);
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    final kachelnDetail = find.descendant(
      of: find.byType(PersonDetailScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, kachelnDetail);
    // in1 ist älter → zweite Kachel.
    await tippe(tester, kachelnDetail.at(1));
    await waitFor(tester, find.byType(AssetViewerScreen));
    await klick(tester, find.byTooltip(de.viewerInfo).last);
    await waitFor(tester, find.byType(AssetInfoSheet));
    final imInfo = find.descendant(
      of: find.byType(AssetInfoSheet),
      matching: find.text('Person A'),
    );
    await waitFor(tester, imInfo);
    await scrollTo(
      tester,
      imInfo,
      in_: find
          .descendant(
            of: find.byType(AssetInfoSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(imInfo, findsOneWidget, reason: 'zwei Gesichter, ein Eintrag');
    await klick(tester, imInfo);
    await waitFor(tester, find.byType(PersonDetailScreen));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Person A')),
      findsWidgets,
    );
    await finish(tester);
  });

  pruefung('PER-007 Person über „+“ im Info-Bereich zuordnen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('pl', 1));
    final foto = f['pl1.jpg']!.id;
    late String g1, g2;
    await tester.runAsync(() async {
      g1 = await gesicht(foto, x: 0.1);
      g2 = await gesicht(foto, x: 0.6);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, g1);
    await klick(tester, find.byTooltip(de.viewerInfo));
    await waitFor(tester, find.byType(AssetInfoSheet));
    // Ohne benanntes Gesicht (Teil von PER-006).
    await waitFor(tester, find.text(de.infoNiemandZugeordnet));
    final plus = find.descendant(
      of: find.byType(AssetInfoSheet),
      matching: find.byTooltip(de.personZuordnenTitel),
    );
    await scrollTo(
      tester,
      plus,
      in_: find
          .descendant(
            of: find.byType(AssetInfoSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await klick(tester, plus);
    await neuePersonImDialog(tester, 'Person A');
    final a = await personNamens(tester, 'Person A');
    final nachher = [
      await gesichtZeile(tester, g1),
      await gesichtZeile(tester, g2),
    ];
    expect(
      nachher.where((x) => x.personId == a.id).length,
      1,
      reason: 'genau ein Gesicht – das erste, ohne Rückfrage',
    );
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.text('Person A'),
      ),
    );
    // Das zweite unbenannte Gesicht folgt beim nächsten „+“.
    await klick(tester, plus);
    await bestehendePersonImDialog(tester, 'Person A');
    expect((await gesichtZeile(tester, g2)).personId, a.id);
    expect((await gesichtZeile(tester, g1)).personId, a.id);
    // Ohne unbenanntes Gesicht: Hinweis.
    await klick(tester, plus);
    await erwarteText(tester, de.infoKeineUnbenannten);
    expect(find.byType(AlertDialog), findsNothing);
    await finish(tester);
  });

  // =========================================================================
  // Gesichtssuche (YuNet/SFace aus dem Vorrat)
  // =========================================================================

  /// Startet die Gesichtssuche aus dem leeren Reiter (30 grosse Fotos,
  /// damit der Lauf einige Sekunden dauert) und prüft den Sofortzustand.
  Future<void> sucheAusLeeremReiter(WidgetTester tester) async {
    await start(tester, modelle: _gesichtsmodelle);
    expect(bibliothek.faceDetectionAvailable, isTrue);
    await fotos(tester, bilder('gs', 30, kante: 2000));
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, find.text(de.personenNochNichtDurchsucht(30)));
    await klick(tester, find.text(de.personenJetztSuchen));
    // Sofort: Text ohne Knopf, in den Aufgaben „Scanne neue Fotos …“.
    expect(find.text(de.personenSucheLaeuft), findsOneWidget);
    expect(find.text(de.personenJetztSuchen), findsNothing);
    final lauf = bibliothek.lauf('gesichter');
    expect(lauf, isNotNull);
    expect(lauf!.titel, de.werkzScanneNeue);
  }

  pruefung('PER-011 Gesichtssuche läuft schon', (tester) async {
    await sucheAusLeeremReiter(tester);
    // Ein zweiter Start über denselben Weg wie „Fehlende“ in den Aufgaben
    // (background_tasks_screen.dart reiheEin → reiheAufgabeEin).
    final abweisung = bibliothek.reiheAufgabeEin(
      schluessel: 'gesichter',
      titel: de.werkzScanneNeue,
      leermeldung: de.werkzKeinePassenden,
      rechenintensiv: true,
      strom: () => bibliothek.rescanFaces(onlyNewPhotos: true),
    );
    expect(abweisung, isNotNull, reason: 'kein zweiter Durchgang');
    expect(abweisungstext(de, abweisung!), de.aufgLaeuftSchon);
    await warteAufLauf(tester, 'gesichter');
    expect(
      await dbx(tester, () => bibliothek.db.countFaceScan(onlyNew: true)),
      0,
    );
    await finish(tester);
  });

  // Behoben in #412: Der Reiter liest Stand und Raster neu, sobald die
  // Gesichtssuche durch ist.
  pruefung('PER-010 Gesichtssuche aus dem leeren Reiter', (tester) async {
    await sucheAusLeeremReiter(tester);
    await warteAufLauf(tester, 'gesichter');
    expect(
      await dbx(tester, () => bibliothek.db.countFaceScan(onlyNew: true)),
      0,
      reason: 'alle 30 Fotos durchsucht',
    );
    await warte(tester, 800);
    expect(
      find.text(de.personenNochNichtDurchsucht(30)),
      findsNothing,
      reason: 'Stand nach dem Lauf veraltet',
    );
    expect(find.text(de.personenKeineUnbenannten), findsOneWidget);
    await finish(tester);
  });

  pruefung('PER-034 PER-096 Erneuter Scan: Ignorierte bleiben, Ausnahmen', (
    tester,
  ) async {
    await start(tester, modelle: _gesichtsmodelle);
    final f = await fotos(tester, bilder('rs', 3));
    late String u1, u2, u3;
    await tester.runAsync(() async {
      u1 = await gesicht(f['rs1.jpg']!.id);
      u2 = await gesicht(f['rs2.jpg']!.id);
      u3 = await gesicht(f['rs3.jpg']!.id);
    });
    // PER-096: Foto rs2 ausnehmen.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, u2);
    final flaeche = find.descendant(
      of: find.byType(FaceReviewScreen),
      matching: find.byType(AspectRatio),
    );
    final r = tester.getRect(flaeche.first);
    await rechtsklickBei(tester, Offset(r.center.dx, r.bottom - 20));
    await klick(tester, find.text(de.gesichtNichtMehrDurchsuchen));
    await erwarteText(tester, de.gesichtNichtMehrDurchsuchtHinweis);
    expect(
      (await assetZeile(tester, f['rs2.jpg']!.id)).faceScanExcluded,
      isTrue,
    );
    await taste(tester, LogicalKeyboardKey.escape);
    // PER-034: u1 über „Alle unbenannten Erkennungen löschen“ löschen,
    // danach ein anderes Gesicht ignorieren.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, kacheln);
    await klick(tester, find.text(de.personenAlleErkennungenLoeschen));
    await klick(tester, imDialog(find.text(de.allgLoeschen)));
    await erwarteText(tester, de.personenErkennungenGeloeschtMeldung(3));
    late String ig;
    await tester.runAsync(() async {
      // Neu erkannt und gleich beiseitegelegt; dazu wieder je ein
      // unbenanntes auf dem ausgenommenen und einem normalen Foto.
      ig = await gesicht(f['rs1.jpg']!.id, ignoriert: true, x: 0.5);
      u2 = await gesicht(f['rs2.jpg']!.id);
      u3 = await gesicht(f['rs3.jpg']!.id);
    });
    await aufgabeStarten(
      tester,
      de.werkzGesichterScannenTitel,
      de.aufgModusAlle,
    );
    await warteAufLauf(tester, 'gesichter');
    final nachher = {for (final g in await alleGesichter(tester)) g.id: g};
    expect(nachher[ig]?.isIgnored, isTrue, reason: 'ignoriertes bleibt');
    expect(nachher.containsKey(u1), isFalse);
    // Das ausgenommene Foto fiel aus dem Lauf: sein Rahmen steht noch.
    expect(nachher.containsKey(u2), isTrue, reason: 'ausgenommen');
    expect(
      nachher.containsKey(u3),
      isFalse,
      reason: 'durchsucht: der unbenannte Eintrag wurde ersetzt',
    );
    // PER-096: zurücknehmen.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, u2);
    final r2 = tester.getRect(flaeche.first);
    await rechtsklickBei(tester, Offset(r2.center.dx, r2.bottom - 20));
    await klick(tester, find.text(de.gesichtWiederDurchsuchen));
    await erwarteText(tester, de.gesichtWiederDurchsuchtHinweis);
    expect(
      (await assetZeile(tester, f['rs2.jpg']!.id)).faceScanExcluded,
      isFalse,
    );
    await finish(tester);
  });

  // =========================================================================
  // Unbenannte Gesichter – Auswahl und Zuordnen
  // =========================================================================

  pruefung('PER-013 PER-014 PER-023 PER-024 Auswahl, Hinweis, Ignorieren', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('au', 6));
    final g = <String>[];
    await tester.runAsync(() async {
      for (var i = 1; i <= 6; i++) {
        g.add(await gesicht(f['au$i.jpg']!.id));
      }
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kacheln);
    // PER-014
    expect(find.text(de.personenSchwellenHinweis), findsOneWidget);
    expect(find.text(de.personenAutomatischGruppieren), findsOneWidget);
    // PER-013
    expect(find.text(de.personenDoppelklickHinweis), findsNothing);
    await waehle(tester, [g[0], g[1]]);
    expect(ausgewaehlt(tester, g[0]), isTrue);
    expect(ausgewaehlt(tester, g[1]), isTrue);
    expect(find.text(de.personenDoppelklickHinweis), findsOneWidget);
    expect(find.text(de.personenAehnlicheAuswaehlen), findsOneWidget);
    expect(find.byTooltip(de.personenIgnorierenTooltip), findsOneWidget);
    expect(find.text(de.personenZuordnenKnopf(2)), findsOneWidget);
    await tippe(tester, kachel(g[0]));
    expect(ausgewaehlt(tester, g[0]), isFalse);
    expect(find.text(de.personenZuordnenKnopf(1)), findsOneWidget);
    await tippe(tester, kachel(g[1]));
    expect(find.text(de.personenDoppelklickHinweis), findsNothing);
    expect(find.byTooltip(de.personenIgnorierenTooltip), findsNothing);

    // PER-023
    final vorher = kachelReihe(tester);
    melde.verlaufLeeren();
    await waehle(tester, [g[2], g[3]]);
    await klick(tester, find.byTooltip(de.personenIgnorierenTooltip));
    expect(find.byType(AlertDialog), findsNothing, reason: 'ohne Rückfrage');
    await waitGone(tester, kachel(g[2]));
    expect(kacheln, findsNWidgets(4));
    final m = await erwarteText(tester, de.personenIgnoriertMeldung(2));
    expect(m.aktion?.beschriftung, de.allgRueckgaengig);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 2)),
    );
    expect(
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 4)),
      findsOneWidget,
    );
    // PER-024
    await rueckgaengig(tester);
    await waitFor(tester, kachel(g[2]));
    expect(kachelReihe(tester), vorher, reason: 'wieder an ihrer Stelle');
    await waitFor(tester, reiterText(de.personenIgnoriertTab));
    expect((await gesichtZeile(tester, g[2])).isIgnored, isFalse);
    await finish(tester);
  });

  pruefung('PER-015 PER-016 PER-017 PER-018 Ähnliche mit auswählen', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('ae', 7));
    String id(int i) => f['ae$i.jpg']!.id;
    late String ohne, allein, a1, b1, a2, a3;
    await tester.runAsync(() async {
      ohne = await gesicht(id(1));
      allein = await gesicht(id(2), vektor: richtung(9));
      a1 = await gesicht(id(3), vektor: richtung(1));
      b1 = await gesicht(id(4), vektor: richtung(5));
      a2 = await gesicht(id(5), vektor: vek({1: 0.95, 2: 0.31}));
      a3 = await gesicht(id(6), vektor: vek({1: 0.9, 3: 0.43}));
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kacheln);
    // PER-018
    await waehle(tester, [ohne]);
    await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
    await erwarteText(tester, de.personenModellFehlt);
    await tippe(tester, kachel(ohne));
    // PER-017
    await waehle(tester, [allein]);
    await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
    await erwarteText(
      tester,
      de.personenKeineAehnlichen(
        bibliothek.faceSimilarityThreshold.toStringAsFixed(2),
      ),
    );
    expect(find.text(de.personenZuordnenKnopf(1)), findsOneWidget);
    await tippe(tester, kachel(allein));
    // PER-015
    await waehle(tester, [a1]);
    await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
    await waitFor(tester, find.text(de.personenAehnlicheAbwaehlen));
    expect(ausgewaehlt(tester, a2), isTrue);
    expect(ausgewaehlt(tester, a3), isTrue);
    expect(ausgewaehlt(tester, b1), isFalse);
    expect(find.byIcon(Icons.auto_awesome), findsNWidgets(2));
    expect(find.text(de.personenZuordnenKnopf(3)), findsOneWidget);
    // PER-016
    await tippe(tester, kachel(b1));
    expect(find.text(de.personenZuordnenKnopf(4)), findsOneWidget);
    await klick(tester, find.text(de.personenAehnlicheAbwaehlen));
    await warte(tester, 300);
    expect(ausgewaehlt(tester, a2), isFalse);
    expect(ausgewaehlt(tester, a3), isFalse);
    expect(ausgewaehlt(tester, a1), isTrue);
    expect(ausgewaehlt(tester, b1), isTrue);
    expect(find.text(de.personenZuordnenKnopf(2)), findsOneWidget);
    await finish(tester);
  });

  pruefung('PER-019 PER-020 PER-021 Zuordnen und Rückgängig', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('zo', 6));
    final g = <String>[];
    await tester.runAsync(() async {
      for (var i = 1; i <= 6; i++) {
        g.add(await gesicht(f['zo$i.jpg']!.id));
      }
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 6)),
    );
    // PER-019
    melde.verlaufLeeren();
    await waehle(tester, [g[0], g[1]]);
    await klick(tester, find.text(de.personenZuordnenKnopf(2)));
    await waitFor(tester, imDialog(find.text(de.personenZuordnen(2))));
    await neuePersonImDialog(tester, 'Person A');
    await waitGone(tester, kachel(g[0]));
    expect(kacheln, findsNWidgets(4));
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 4)),
    );
    expect(reiterText(de.tabMitZahl(de.personenTab, 1)), findsOneWidget);
    final m = await erwarteText(
      tester,
      de.personenZugeordnetMeldung(2, 'Person A'),
    );
    expect(m.aktion?.beschriftung, de.allgRueckgaengig);
    var a = await personNamens(tester, 'Person A');
    expect([
      bibliothek.paths.faceRelativePath(g[0]),
      bibliothek.paths.faceRelativePath(g[1]),
    ], contains(a.coverFaceCropPath));
    // PER-020: bestehende Person, Profilbild bleibt.
    final titelbild = a.coverFaceCropPath;
    await waehle(tester, [g[2]]);
    await klick(tester, find.text(de.personenZuordnenKnopf(1)));
    await waitFor(tester, find.byType(AlertDialog));
    await klick(tester, dialogZeile('Person A'));
    expect(imDialog(find.byIcon(Icons.check)), findsOneWidget);
    await klick(tester, imDialog(find.text(de.personZuordnenAktion)));
    await waitGone(tester, kachel(g[2]));
    expect((await gesichtZeile(tester, g[2])).personId, a.id);
    a = await personNamens(tester, 'Person A');
    expect(a.coverFaceCropPath, titelbild);
    // PER-021: neue Person B und Rückgängig.
    melde.verlaufLeeren();
    await waehle(tester, [g[3], g[4]]);
    await klick(tester, find.text(de.personenZuordnenKnopf(2)));
    await neuePersonImDialog(tester, 'Person B');
    await erwarteText(tester, de.personenZugeordnetMeldung(2, 'Person B'));
    await waitFor(tester, reiterText(de.tabMitZahl(de.personenTab, 2)));
    await rueckgaengig(tester);
    await waitFor(tester, kachel(g[3]));
    await waitFor(tester, reiterText(de.tabMitZahl(de.personenTab, 1)));
    expect(
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 3)),
      findsOneWidget,
    );
    expect(
      (await allePersonen(tester)).where((x) => x.name == 'Person B'),
      isEmpty,
    );
    expect((await gesichtZeile(tester, g[3])).personId, isNull);
    expect((await gesichtZeile(tester, g[4])).personId, isNull);
    // Das Foto von PER-020 steht in der Personenansicht von Person A.
    await klick(tester, reiter(de.personenTab));
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (w) => w is AssetThumbnailTile && w.asset.id == f['zo3.jpg']!.id,
      ),
    );
    await finish(tester);
  });

  pruefung(
    'PER-022 PER-066 Rückgängig bei bestehender Person, gelernte Schwelle',
    (tester) async {
      await start(tester);
      final f = await fotos(tester, bilder('ls', 5));
      String id(int i) => f['ls$i.jpg']!.id;
      late String a, u1, u2, u3, u4;
      await tester.runAsync(() async {
        a = await person('Person A');
        await gesicht(id(1), person: a, vektor: richtung(1));
        u1 = await gesicht(id(2), vektor: richtung(1));
        u2 = await gesicht(id(3), vektor: vek({1: 1, 2: 0.1}));
        u3 = await gesicht(id(4), vektor: vek({1: 1, 3: 0.15}));
        u4 = await gesicht(id(5), vektor: vek({1: 0.5, 4: 0.866}));
      });
      final vorher = (await personZeile(tester, a))!;
      await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      // PER-022
      melde.verlaufLeeren();
      await waehle(tester, [u1]);
      await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
      await waitFor(tester, find.text(de.personenZuordnenKnopf(4)));
      await klick(tester, find.text(de.personenZuordnenKnopf(4)));
      await bestehendePersonImDialog(tester, 'Person A');
      await erwarteText(tester, de.personenZugeordnetMeldung(4, 'Person A'));
      expect(await rueckmeldungen(tester), isNotEmpty);
      await rueckgaengig(tester);
      await waitFor(tester, kachel(u1));
      for (final u in [u1, u2, u3, u4]) {
        expect((await gesichtZeile(tester, u)).personId, isNull);
      }
      final danach = (await personZeile(tester, a))!;
      expect(danach.coverFaceCropPath, vorher.coverFaceCropPath);
      expect(danach.similarityThreshold, vorher.similarityThreshold);
      expect(await rueckmeldungen(tester), isEmpty);
      // PER-066: drei Entscheidungen (zwei bestätigt, eine abgewählt).
      await waehle(tester, [u1]);
      await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
      await waitFor(tester, find.text(de.personenZuordnenKnopf(4)));
      await tippe(tester, kachel(u4));
      await klick(tester, find.text(de.personenZuordnenKnopf(3)));
      await bestehendePersonImDialog(tester, 'Person A');
      await waitGone(tester, kachel(u1));
      await klick(tester, reiter(de.personenTab));
      await klick(tester, find.text('Person A'));
      await waitFor(tester, find.byType(PersonDetailScreen));
      final zeile = find.textContaining('Wiedererkennung:');
      await waitFor(tester, zeile);
      final text = tester.widget<Text>(zeile).data!;
      expect(text, contains('2 Bestätigungen'));
      expect(text, contains('einer Korrektur'));
      expect(text, contains('angepasst auf'));
      expect((await personZeile(tester, a))!.similarityThreshold, isNotNull);
      await klick(tester, find.text(de.personVerwerfen));
      await erwarteText(tester, de.personGelerntesVerworfen);
      await waitGone(tester, zeile);
      expect((await personZeile(tester, a))!.similarityThreshold, isNull);
      await finish(tester);
    },
  );

  pruefung('PER-025 Gesicht im Foto zeigen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('iz', 3));
    late String gA, gB, gC, gD;
    await tester.runAsync(() async {
      gA = await gesicht(f['iz1.jpg']!.id, x: 0.1);
      gB = await gesicht(f['iz1.jpg']!.id, x: 0.6);
      gC = await gesicht(f['iz2.jpg']!.id);
      gD = await gesicht(f['iz3.jpg']!.id);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kachel(gD));
    // Die erwartete Reihe: die Fotos der Kacheln in Rasterfolge, jedes
    // einmal (das Raster selbst ist nicht nach Einfügen geordnet).
    final fotoVon = {
      gA: 'iz1.jpg',
      gB: 'iz1.jpg',
      gC: 'iz2.jpg',
      gD: 'iz3.jpg',
    };
    final reihe = <String>[];
    for (final g in kachelReihe(tester)) {
      if (!reihe.contains(fotoVon[g])) reihe.add(fotoVon[g]!);
    }
    print('PER-025 Reihe nach Raster: $reihe');
    expect(reihe, hasLength(3), reason: 'Gruppenfoto einmal');
    Finder titel(String datei) => find.descendant(
      of: find.byType(FaceReviewScreen),
      matching: find.text(datei),
    );
    await imFotoZeigen(tester, gC);
    final start2 = reihe.indexOf('iz2.jpg');
    await waitFor(tester, find.text(de.gesichtPosition(start2 + 1, 3)));
    expect(titel('iz2.jpg'), findsOneWidget);
    final hervor = tester
        .widgetList<Gesichtsrahmen>(find.byType(Gesichtsrahmen))
        .where((r) => r.hervorgehoben)
        .toList();
    expect(hervor.map((r) => r.gesicht.id), [gC]);
    // An den Anfang, dann mit Pfeil rechts durch die ganze Reihe.
    for (var i = 0; i < start2; i++) {
      await taste(tester, LogicalKeyboardKey.arrowLeft);
    }
    for (var i = 0; i < 3; i++) {
      await waitFor(tester, find.text(de.gesichtPosition(i + 1, 3)));
      expect(
        titel(reihe[i]),
        findsOneWidget,
        reason: 'Reihenfolge des Rasters',
      );
      if (reihe[i] == 'iz1.jpg') {
        // Das Gruppenfoto: zwei Rahmen auf einer Position.
        await waitFor(tester, rahmen(gB));
        expect(find.byType(Gesichtsrahmen), findsNWidgets(2));
      }
      if (i < 2) await taste(tester, LogicalKeyboardKey.arrowRight);
    }
    await taste(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(FaceReviewScreen));
    // Alternativ: Doppelklick auf die Kachel.
    await doppelklick(tester, kachel(gD));
    await waitFor(tester, find.byType(FaceReviewScreen));
    await waitFor(
      tester,
      find.text(de.gesichtPosition(reihe.indexOf('iz3.jpg') + 1, 3)),
    );
    await finish(tester);
  });

  pruefung('PER-026 Große Menge unbenannter Gesichter', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('gm', 10));
    final assets = [for (var i = 1; i <= 10; i++) f['gm$i.jpg']!.id];
    await tester.runAsync(() async {
      final gleich = gemeinsamerAusschnitt('gleich');
      final rest = gemeinsamerAusschnitt('rest');
      // Alle mit derselben Einbettung: „Ähnliche mit auswählen“ nimmt so
      // das ganze geladene Raster auf einmal.
      await vieleGesichter([
        for (var i = 0; i < 1000; i++)
          gesichtszeile(
            assets[i % 10],
            i.isEven ? gleich : rest,
            vektor: richtung(1),
          ),
      ]);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 1000)),
    );
    int rasterZahl() =>
        (tester
                    .widget<GridView>(
                      find.descendant(
                        of: find.byType(TabBarView),
                        matching: find.byType(GridView),
                      ),
                    )
                    .childrenDelegate
                as SliverChildBuilderDelegate)
            .childCount!;
    expect(rasterZahl(), 200);
    // Viele auf einmal: ein Gesicht wählen, die gleichen dazu, ignorieren.
    await tippe(tester, kacheln.first);
    await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
    await waitFor(tester, find.text(de.personenAehnlicheAbwaehlen));
    final knopfText = tester
        .widget<Text>(find.textContaining(RegExp(r'^\d+ zuordnen$')))
        .data!;
    final gewaehlt = int.parse(knopfText.split(' ').first);
    print('PER-026: $gewaehlt Gesichter auf einmal gewählt');
    expect(200 - gewaehlt, lessThan(40), reason: 'Raster fällt unter 40');
    await klick(tester, find.byTooltip(de.personenIgnorierenTooltip));
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 1000 - gewaehlt)),
    );
    await warte(tester, 1000);
    expect(rasterZahl(), 200, reason: 'füllt sich wieder auf');
    await finish(tester);
  });

  // =========================================================================
  // Massenaktionen
  // =========================================================================

  pruefung('PER-027 PER-028 PER-029 PER-030 Kontextmenü, alle ignorieren', (
    tester,
  ) async {
    await start(tester);
    // PER-028: leerer Reiter.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, find.byType(TabBarView));
    await waitFor(tester, find.text(de.personenAlleIgnorieren));
    expect(find.text(de.vorschlaegeTitel), findsOneWidget);
    expect(find.text(de.vorschlaegeAnzahl(0)), findsOneWidget);
    expect(find.text(de.personenAlleIgnorierenHinweis(0)), findsOneWidget);
    expect(find.text(de.personenAlleErkennungenLoeschen), findsOneWidget);
    expect(
      find.text(de.personenAlleErkennungenLoeschenHinweis),
      findsOneWidget,
    );
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find
                .ancestor(
                  of: find.text(de.personenAlleIgnorieren),
                  matching: find.byType(PopupMenuItem<String>),
                )
                .first,
          )
          .enabled,
      isFalse,
    );
    await taste(tester, LogicalKeyboardKey.escape);
    // Auch im Reiter „Ignoriert“.
    await klick(tester, reiter(de.personenIgnoriertTab));
    await rechtsklick(tester, find.byType(TabBarView));
    await waitFor(tester, find.text(de.personenAlleErkennungenLoeschen));
    await taste(tester, LogicalKeyboardKey.escape);

    final f = await fotos(tester, bilder('mi', 5));
    final assets = [for (var i = 1; i <= 5; i++) f['mi$i.jpg']!.id];
    late List<String> vorherIgnoriert;
    await tester.runAsync(() async {
      final a = await person('Person A');
      final teil = gemeinsamerAusschnitt('viele');
      await vieleGesichter([
        for (var i = 0; i < 250; i++) gesichtszeile(assets[i % 5], teil),
      ]);
      for (var i = 0; i < 3; i++) {
        await gesicht(assets[i], person: a, x: 0.6);
      }
      vorherIgnoriert = [
        await gesicht(assets[3], ignoriert: true, x: 0.6),
        await gesicht(assets[4], ignoriert: true, x: 0.6),
      ];
    });
    // PER-027, PER-029
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kacheln);
    melde.verlaufLeeren();
    await rechtsklick(tester, kacheln);
    await waitFor(tester, find.text(de.personenAlleIgnorierenHinweis(250)));
    await klick(tester, find.text(de.personenAlleIgnorieren));
    final m = await erwarteText(tester, de.personenAlleIgnoriertMeldung(250));
    expect(m.aktion?.beschriftung, de.allgRueckgaengig);
    expect(await dbx(tester, () => bibliothek.db.unassignedFacesCount()), 0);
    expect(await dbx(tester, () => bibliothek.db.ignoredFacesCount()), 252);
    final benannt = (await alleGesichter(
      tester,
    )).where((x) => x.personId != null).toList();
    expect(benannt.length, 3);
    expect(benannt.every((x) => !x.isIgnored), isTrue);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 252)),
    );
    expect(reiterText(de.personenUnbenannteTab), findsOneWidget);
    // PER-030
    await rueckgaengig(tester);
    await eventually(
      tester,
      () async => await bibliothek.db.unassignedFacesCount() == 250,
    );
    expect(await dbx(tester, () => bibliothek.db.ignoredFacesCount()), 2);
    for (final id in vorherIgnoriert) {
      expect((await gesichtZeile(tester, id)).isIgnored, isTrue);
    }
    await finish(tester);
  });

  pruefung('PER-032 Alle Erkennungen löschen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('el', 3));
    final assets = [for (var i = 1; i <= 3; i++) f['el$i.jpg']!];
    final vorher = [for (final a in assets) await originalBytes(tester, a)];
    final weg = <String>[];
    final bleibt = <String>[];
    await tester.runAsync(() async {
      final a = await person('Person A');
      for (var i = 0; i < 3; i++) {
        weg.add(await gesicht(assets[i].id));
      }
      weg.add(await gesicht(assets[0].id, ignoriert: true, x: 0.5));
      weg.add(await gesicht(assets[1].id, ignoriert: true, x: 0.5));
      bleibt.add(await gesicht(assets[0].id, person: a, x: 0.75));
      bleibt.add(await gesicht(assets[2].id, person: a, x: 0.75));
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, kacheln);
    await klick(tester, find.text(de.personenAlleErkennungenLoeschen));
    await waitFor(tester, find.text(de.personenErkennungenLoeschenTitel));
    await klick(tester, imDialog(find.text(de.allgLoeschen)));
    await erwarteText(tester, de.personenErkennungenGeloeschtMeldung(5));
    final rest = await alleGesichter(tester);
    expect(rest.map((x) => x.id).toSet(), bleibt.toSet());
    await tester.runAsync(() async {
      for (final id in weg) {
        expect(
          bibliothek.paths
              .absolute(bibliothek.paths.faceRelativePath(id))
              .existsSync(),
          isFalse,
          reason: 'Ausschnitt $id gelöscht',
        );
      }
      for (final id in bleibt) {
        expect(
          bibliothek.paths
              .absolute(bibliothek.paths.faceRelativePath(id))
              .existsSync(),
          isTrue,
        );
      }
    });
    for (var i = 0; i < 3; i++) {
      final jetzt = await assetZeile(tester, assets[i].id);
      expect(jetzt.isTrashed, isFalse);
      expect(await originalBytes(tester, jetzt), vorher[i]);
    }
    await finish(tester);
  });

  // =========================================================================
  // Ignorierte Gesichter
  // =========================================================================

  pruefung('PER-036 PER-037 Ignoriert: Hinweise, Deckel, zurückholen', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('ig', 3));
    final assets = [for (var i = 1; i <= 3; i++) f['ig$i.jpg']!.id];
    final eigene = <String>[];
    await tester.runAsync(() async {
      for (final a in assets) {
        eigene.add(await gesicht(a, ignoriert: true));
      }
    });
    await personenOeffnen(tester, reiterName: de.personenIgnoriertTab);
    await waitFor(tester, find.text(de.personenIgnoriertHinweis));
    final abgeblendet = tester.widget<Opacity>(
      find.ancestor(of: kacheln.first, matching: find.byType(Opacity)).first,
    );
    expect(abgeblendet.opacity, closeTo(0.55, 0.01));
    // PER-036: 300 ignorierte.
    await tester.runAsync(() async {
      final teil = gemeinsamerAusschnitt('ignoriert');
      await vieleGesichter([
        for (var i = 0; i < 297; i++)
          gesichtszeile(assets[i % 3], teil, ignoriert: true),
      ]);
    });
    await personenOeffnen(tester, reiterName: de.personenIgnoriertTab);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 300)),
    );
    expect(
      find.text(de.personenIgnoriertTeilHinweis(200, 300)),
      findsOneWidget,
    );
    expect(
      (tester
                  .widget<GridView>(
                    find.descendant(
                      of: find.byType(TabBarView),
                      matching: find.byType(GridView),
                    ),
                  )
                  .childrenDelegate
              as SliverChildBuilderDelegate)
          .childCount,
      200,
    );
    // PER-037: zwei zurückholen.
    final zwei = kachelReihe(tester).take(2).toList();
    for (var i = 0; i < 2; i++) {
      await tippe(tester, kacheln.at(i));
    }
    await klick(tester, find.text(de.personenZurueckholenKnopf(2)));
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 298)),
    );
    expect(
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 2)),
      findsOneWidget,
    );
    expect(await dbx(tester, () => bibliothek.db.unassignedFacesCount()), 2);
    print('PER-037 zurückgeholt: $zwei');
    await finish(tester);
  });

  // =========================================================================
  // Automatisch gruppieren
  // =========================================================================

  pruefung('PER-039 Gruppieren mit zu wenigen Gesichtern', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('ag', 3));
    await tester.runAsync(() async {
      await gesicht(f['ag1.jpg']!.id, vektor: richtung(40));
      await gesicht(f['ag2.jpg']!.id);
      await gesicht(f['ag3.jpg']!.id);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await erwarteText(tester, de.personenZuWenigeFuerClustering);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(PeopleScreen), findsOneWidget);
    await finish(tester);
  });

  // Behoben in #406: Der Fortschrittsdialog wird auf seinem eigenen
  // (Wurzel-)Navigator geschlossen.
  pruefung('PER-043 Gruppieren ohne ähnliche Gruppen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('kg', 4));
    await tester.runAsync(() async {
      for (var i = 1; i <= 4; i++) {
        await gesicht(f['kg$i.jpg']!.id, vektor: richtung(40 + i));
      }
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await erwarteText(tester, de.personenKeineGruppen);
    await warte(tester, 1500);
    final dialogOffen = sichtbar(find.byType(AlertDialog));
    final seiteDa = sichtbar(find.byType(PeopleScreen));
    print('PER-043: Dialog offen $dialogOffen, Personen-Seite da $seiteDa');
    // Was vom Arbeitsbereich übrig ist: ein anderer Bereich?
    await openSection(tester, Hauptbereich.alben);
    await warte(tester, 800);
    print(
      'PER-043: danach Bereich Alben sichtbar: '
      '${sichtbar(find.byType(AlbumsScreen))}',
    );
    expect(dialogOffen, isFalse, reason: 'Fortschrittsdialog schliesst');
    expect(seiteDa, isTrue, reason: 'Personen-Seite bleibt');
    await finish(tester);
  });

  // Behoben in #406 (Fortschrittsdialog auf dem Wurzel-Navigator).
  pruefung('PER-044 Ansicht „Vorschläge prüfen“', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('ag', 8));
    final assets = [for (var i = 1; i <= 8; i++) f['ag$i.jpg']!.id];
    // PER-044: Person A und drei Gruppen.
    late String a;
    final g1 = <String>[], g2 = <String>[], g3 = <String>[];
    await tester.runAsync(() async {
      a = await person('Person A');
      await gesicht(assets[4], person: a, vektor: richtung(10), x: 0.7);
      await gesicht(assets[5], person: a, vektor: richtung(10), x: 0.7);
      for (var i = 0; i < 8; i++) {
        g1.add(
          await gesicht(
            assets[i % 8],
            vektor: vek({10: 1, 60 + i: 0.05}),
            y: 0.5,
          ),
        );
      }
      for (var i = 0; i < 3; i++) {
        g2.add(await gesicht(assets[i], vektor: richtung(11), y: 0.7));
      }
      for (var i = 0; i < 4; i++) {
        g3.add(await gesicht(assets[i + 3], vektor: richtung(12), y: 0.7));
      }
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await waitFor(
      tester,
      find.byType(FaceClusterReviewScreen),
      timeout: const Duration(seconds: 60),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.clusterTitel),
      ),
      findsOneWidget,
    );
    Finder karte(String text) =>
        find.ancestor(of: find.text(text), matching: find.byType(Card)).first;
    final karteG1 = karte(de.clusterGesichterAnzahl(8));
    await waitFor(tester, karteG1);
    expect(
      find.descendant(of: karteG1, matching: find.text('+2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: karteG1,
        matching: find.text(de.clusterAehnlichZu('Person A')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: karteG1,
        matching: find.byTooltip(de.clusterIgnorierenTooltip),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: karteG1,
        matching: find.text(de.clusterUeberspringen),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FaceClusterReviewScreen),
        matching: find.byType(Card),
      ),
      findsNWidgets(3),
    );
    await warte(tester, 1500);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'der Fortschrittsdialog schliesst sich',
    );
    print('PER-044 a=$a g1=${g1.length} g2=${g2.length} g3=${g3.length}');
    await finish(tester);
  });

  // Wie PER-044, aber der hängende Fortschrittsdialog wird – wie es ein
  // Mensch täte – mit „Abbrechen“ weggeklickt; seine Folgefehler im
  // Debug-Bau („ValueNotifier<_ClusterStand> was used after being
  // disposed“) gehören zu PER-043/PER-044 und werden hier geduldet.
  pruefung(
    'PER-045 PER-047 PER-048 PER-049 Vorschläge prüfen nach dem Dialog',
    (tester) async {
      final fehlerZurueck = kennFehlerDulden('_ClusterStand');
      await start(tester);
      final f = await fotos(tester, bilder('ag', 8));
      final assets = [for (var i = 1; i <= 8; i++) f['ag$i.jpg']!.id];
      // PER-044: Person A und drei Gruppen.
      late String a;
      final g1 = <String>[], g2 = <String>[], g3 = <String>[];
      await tester.runAsync(() async {
        a = await person('Person A');
        await gesicht(assets[4], person: a, vektor: richtung(10), x: 0.7);
        await gesicht(assets[5], person: a, vektor: richtung(10), x: 0.7);
        for (var i = 0; i < 8; i++) {
          g1.add(
            await gesicht(
              assets[i % 8],
              vektor: vek({10: 1, 60 + i: 0.05}),
              y: 0.5,
            ),
          );
        }
        for (var i = 0; i < 3; i++) {
          g2.add(await gesicht(assets[i], vektor: richtung(11), y: 0.7));
        }
        for (var i = 0; i < 4; i++) {
          g3.add(await gesicht(assets[i + 3], vektor: richtung(12), y: 0.7));
        }
      });
      await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      await klick(tester, find.text(de.personenAutomatischGruppieren));
      await waitFor(
        tester,
        find.byType(FaceClusterReviewScreen),
        timeout: const Duration(seconds: 60),
      );
      await haengendenDialogSchliessen(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(de.clusterTitel),
        ),
        findsOneWidget,
      );
      Finder karte(String text) =>
          find.ancestor(of: find.text(text), matching: find.byType(Card)).first;
      final karteG1 = karte(de.clusterGesichterAnzahl(8));
      await waitFor(tester, karteG1);
      expect(
        find.descendant(of: karteG1, matching: find.text('+2')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: karteG1,
          matching: find.text(de.clusterAehnlichZu('Person A')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: karteG1,
          matching: find.byTooltip(de.clusterIgnorierenTooltip),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: karteG1,
          matching: find.text(de.clusterUeberspringen),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(FaceClusterReviewScreen),
          matching: find.byType(Card),
        ),
        findsNWidgets(3),
      );
      // PER-045
      await klick(
        tester,
        find.descendant(
          of: karteG1,
          matching: find.text(de.personZuordnenAktion),
        ),
      );
      await waitFor(tester, imDialog(find.text(de.personVorschlag)));
      final erste = tester
          .widgetList<ListTile>(imDialog(find.byType(ListTile)))
          .first;
      expect((erste.title as Text).data, 'Person A');
      expect(imDialog(find.byIcon(Icons.check)), findsOneWidget);
      await klick(
        tester,
        imDialog(find.widgetWithText(FilledButton, de.personZuordnenAktion)),
      );
      await waitGone(tester, find.text(de.clusterGesichterAnzahl(8)));
      for (final id in g1) {
        expect((await gesichtZeile(tester, id)).personId, a);
      }
      final lernenVorher = (await rueckmeldungen(tester)).length;
      // PER-047
      await klick(
        tester,
        find.descendant(
          of: karte(de.clusterGesichterAnzahl(3)),
          matching: find.text(de.clusterUeberspringen),
        ),
      );
      await waitGone(tester, find.text(de.clusterGesichterAnzahl(3)));
      for (final id in g2) {
        final z = await gesichtZeile(tester, id);
        expect(z.personId, isNull);
        expect(z.isIgnored, isFalse);
      }
      expect((await rueckmeldungen(tester)).length, lernenVorher);
      // PER-048
      await klick(
        tester,
        find.descendant(
          of: karte(de.clusterGesichterAnzahl(4)),
          matching: find.byTooltip(de.clusterIgnorierenTooltip),
        ),
      );
      // PER-049
      await waitFor(tester, find.text(de.clusterFertig));
      for (final id in g3) {
        expect((await gesichtZeile(tester, id)).isIgnored, isTrue);
      }
      // Kein Zurück: Nach dem Befund PER-043/PER-044 ist die Seite unter
      // „Vorschläge prüfen“ weg, und der Arbeitsbereich zeigt keinen
      // Bereich mehr an. PER-046 läuft deshalb in einer eigenen Prüfung.
      fehlerZurueck();
      await finish(tester);
    },
  );

  // Wie oben mit weggeklicktem Fortschrittsdialog (Befund PER-044).
  pruefung('PER-046 Gruppe einer anderen Person zuordnen', (tester) async {
    final fehlerZurueck = kennFehlerDulden('_ClusterStand');
    await start(tester);
    final f = await fotos(tester, bilder('ga', 5));
    late String a;
    final g5 = <String>[];
    await tester.runAsync(() async {
      a = await person('Person A');
      await gesicht(f['ga1.jpg']!.id, person: a, vektor: richtung(10));
      await gesicht(f['ga2.jpg']!.id, person: a, vektor: richtung(10));
      for (var i = 0; i < 3; i++) {
        g5.add(
          await gesicht(
            f['ga${i + 3}.jpg']!.id,
            vektor: vek({10: 1, 80 + i: 0.05}),
          ),
        );
      }
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await waitFor(
      tester,
      find.byType(FaceClusterReviewScreen),
      timeout: const Duration(seconds: 60),
    );
    await haengendenDialogSchliessen(tester);
    final mitVorschlag = find
        .ancestor(
          of: find.text(de.clusterAehnlichZu('Person A')),
          matching: find.byType(Card),
        )
        .first;
    await waitFor(tester, mitVorschlag);
    await klick(
      tester,
      find.descendant(
        of: mitVorschlag,
        matching: find.text(de.personZuordnenAktion),
      ),
    );
    await waitFor(tester, imDialog(find.byIcon(Icons.check)));
    await klick(tester, dialogZeile('Person A'));
    expect(imDialog(find.byIcon(Icons.check)), findsNothing);
    await neuePersonImDialog(tester, 'Person B');
    final b = await personNamens(tester, 'Person B');
    for (final id in g5) {
      expect((await gesichtZeile(tester, id)).personId, b.id);
    }
    final fuerA = (await rueckmeldungen(
      tester,
    )).where((r) => r.personId == a).toList();
    expect(fuerA, hasLength(1), reason: 'ein Eintrag je Gruppe');
    expect(fuerA.single.accepted, isFalse);
    fehlerZurueck();
    await finish(tester);
  });

  pruefung('PER-040 PER-041 PER-042 Fortschritt, Abbrechen, Warnung', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('fd', 10));
    final assets = [for (var i = 1; i <= 10; i++) f['fd$i.jpg']!.id];
    await tester.runAsync(() async {
      final teil = gemeinsamerAusschnitt('fortschritt');
      final r = math.Random(7);
      await vieleGesichter([
        for (var i = 0; i < 8001; i++)
          gesichtszeile(
            assets[i % 10],
            teil,
            vektor: vek({
              for (var k = 0; k < 6; k++) r.nextInt(128): r.nextDouble() + 0.1,
            }),
          ),
      ]);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kacheln);
    // PER-042
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await waitFor(
      tester,
      find.text(de.personenDauertTitel),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(de.personenDauertText(8001)), findsOneWidget);
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await warte(tester, 800);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await klick(tester, find.text(de.personenAutomatischGruppieren));
    await waitFor(
      tester,
      find.text(de.personenDauertTitel),
      timeout: const Duration(seconds: 30),
    );
    await klick(tester, imDialog(find.text(de.allgStarten)));
    // PER-040
    await waitFor(tester, imDialog(find.byType(LinearProgressIndicator)));
    await waitFor(tester, find.text(de.clusterPhaseVergleichen));
    final werte = <int>[];
    final ende = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 100));
      for (final t in tester.widgetList<Text>(imDialog(find.byType(Text)))) {
        final m = RegExp(r'^(\d+) %$').firstMatch(t.data ?? '');
        if (m != null) werte.add(int.parse(m.group(1)!));
      }
    }
    print('PER-040 Prozentwerte: ${werte.toSet().toList()}');
    expect(werte, isNotEmpty);
    for (var i = 1; i < werte.length; i++) {
      expect(werte[i], greaterThanOrEqualTo(werte[i - 1]));
    }
    await taste(tester, LogicalKeyboardKey.escape);
    expect(
      find.text(de.clusterPhaseVergleichen),
      findsOneWidget,
      reason: 'Escape schliesst den Dialog nicht',
    );
    // PER-041
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.byType(AlertDialog));
    await warte(tester, 3000);
    expect(find.byType(FaceClusterReviewScreen), findsNothing);
    expect(await dbx(tester, () => bibliothek.db.unassignedFacesCount()), 8001);
    await finish(tester);
  });

  // =========================================================================
  // Dialog Person zuordnen
  // =========================================================================

  pruefung('PER-054 PER-055 PER-056 Dialog Person zuordnen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('dz', 2));
    late String x, y, z;
    await tester.runAsync(() async {
      x = await gesicht(f['dz1.jpg']!.id, x: 0.1);
      z = await gesicht(f['dz2.jpg']!.id);
    });
    // PER-055: ohne Personen.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waehle(tester, [z]);
    await klick(tester, find.text(de.personenZuordnenKnopf(1)));
    await waitFor(tester, imDialog(find.text(de.personNochKeine)));
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await tester.runAsync(() async {
      final a = await person('Person A');
      await person('Person B');
      y = await gesicht(f['dz1.jpg']!.id, person: a, x: 0.6);
    });
    // PER-054
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waehle(tester, [z]);
    await klick(tester, find.text(de.personenZuordnenKnopf(1)));
    await waitFor(tester, find.byType(AlertDialog));
    expect(knopfAktiv(tester, de.personZuordnenAktion), isFalse);
    await klick(tester, dialogZeile('Person A'));
    expect(imDialog(find.byIcon(Icons.check)), findsOneWidget);
    expect(knopfAktiv(tester, de.personZuordnenAktion), isTrue);
    await klick(tester, dialogZeile('Person A'));
    expect(imDialog(find.byIcon(Icons.check)), findsNothing);
    final feld = imDialog(field(de.personSuchenOderAnlegen));
    await enter(tester, feld, 'Xyz');
    // PER-055: kein Treffer.
    expect(imDialog(find.text(de.personKeinTreffer('Xyz'))), findsOneWidget);
    await klick(tester, imDialog(find.byTooltip(de.allgLeeren)));
    expect(tester.widget<TextField>(feld).controller!.text, isEmpty);
    expect(knopfAktiv(tester, de.personZuordnenAktion), isFalse);
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.byType(AlertDialog));
    expect((await gesichtZeile(tester, z)).personId, isNull);
    // PER-056
    await tippe(tester, kachel(z));
    await imFotoZeigen(tester, x);
    await klick(tester, rahmen(x));
    await waitFor(tester, imDialog(find.text(de.gesichtBenennen)));
    expect(imDialog(find.text(de.allgAbbrechen)), findsOneWidget);
    await klick(tester, imDialog(find.text(de.gesichtIgnorieren)));
    await waitFor(
      tester,
      find.descendant(of: rahmen(x), matching: find.text(de.gesichtIgnoriert)),
    );
    expect((await gesichtZeile(tester, x)).isIgnored, isTrue);
    await klick(tester, rahmen(y));
    await waitFor(tester, imDialog(find.text(de.gesichtUmbenennen)));
    expect(imDialog(find.text(de.gesichtIgnorieren)), findsNothing);
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await finish(tester);
  });

  pruefung('PER-057 Viele Personen im Dialog', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('vp', 1));
    late String g;
    await tester.runAsync(() async {
      for (var i = 1; i <= 80; i++) {
        await person('Person ${i.toString().padLeft(2, '0')}');
      }
      g = await gesicht(f['vp1.jpg']!.id);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waehle(tester, [g]);
    await klick(tester, find.text(de.personenZuordnenKnopf(1)));
    await waitFor(tester, dialogZeile('Person 01'));
    final liste = find
        .descendant(
          of: imDialog(find.byType(ListView)),
          matching: find.byType(Scrollable),
        )
        .first;
    final stand = tester.state<ScrollableState>(liste);
    final vorher = stand.position.pixels;
    final sicht = stand.position.viewportDimension;
    final maus = TestPointer(1, PointerDeviceKind.mouse);
    final mitte = tester.getCenter(liste);
    await tester.sendEventToBinding(maus.hover(mitte));
    await tester.sendEventToBinding(maus.scroll(const Offset(0, 600)));
    await warte(tester, 600);
    final nachher = stand.position.pixels;
    print('PER-057 Radschritt: $vorher → $nachher (Sicht $sicht)');
    expect(nachher, greaterThan(vorher), reason: 'die Liste rollt in sich');
    expect(
      nachher - vorher,
      lessThan(sicht),
      reason: 'keine Zeile übersprungen',
    );
    final dialogRect = tester.getRect(find.byType(AlertDialog));
    for (final t in [de.allgAbbrechen]) {
      final r = tester.getRect(imDialog(find.text(t)));
      expect(dialogRect.contains(r.center), isTrue, reason: '$t sichtbar');
    }
    await finish(tester);
  });

  // =========================================================================
  // Personenansicht
  // =========================================================================

  pruefung('PER-059 PER-061 PER-065 PER-127 Grenzfälle der Personenansicht', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('gr', 2));
    late String a, b;
    await tester.runAsync(() async {
      a = await person('Person A');
      b = await person('Person B');
      await verwandt(b, a);
      await gesicht(f['gr1.jpg']!.id, person: a, vektor: richtung(1));
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    // PER-127, PER-059
    await schildMenue(tester, 'Person B');
    await klick(tester, find.text(de.stammbaumFotosZeigen));
    await waitFor(tester, find.byType(PersonDetailScreen));
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Person B')),
      findsOneWidget,
    );
    await waitFor(tester, find.text(de.personKeineFotos));
    // PER-061
    await klick(tester, find.text(de.personProfilbildAendern));
    await erwarteText(tester, de.personKeineGesichter);
    expect(find.byType(AlertDialog), findsNothing);
    // PER-065 (a)
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await erwarteText(tester, de.vorschlagKeineEmbeddings);
    // Während die Personenansicht offen ist, ändert sich etwas.
    await tester.runAsync(
      () => bibliothek.db.fuehreAus(
        LebensdatenSetzen(b, geburt: DateTime(1977, 4, 5), tod: null),
      ),
    );
    await zurueck(tester);
    await waitFor(tester, find.byType(ZierbaumAnsicht));
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(ZierbaumAnsicht),
        matching: find.textContaining('1977'),
      ),
    );
    // PER-065 (b): keine unbenannten Gesichter.
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await erwarteText(tester, de.vorschlagKeineKandidaten);
    // PER-065 (c): nur unähnliche.
    await tester.runAsync(
      () => gesicht(f['gr2.jpg']!.id, vektor: richtung(50)),
    );
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await erwarteText(
      tester,
      de.vorschlagNichtsGefunden(
        bibliothek.faceSimilarityThreshold.toStringAsFixed(2),
      ),
    );
    expect(find.byType(PersonSuggestionsScreen), findsNothing);
    await finish(tester);
  });

  pruefung('PER-060 PER-062 PER-064 Profilbild und Vorschläge', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('pv', 9));
    String id(int i) => f['pv$i.jpg']!.id;
    late String a, v4;
    final benannt = <String>[];
    final vorschlaege = <String>[];
    await tester.runAsync(() async {
      a = await person('Person A');
      for (var i = 1; i <= 3; i++) {
        benannt.add(await gesicht(id(i), person: a, vektor: richtung(1)));
      }
      vorschlaege.add(await gesicht(id(4), vektor: vek({1: 1, 2: 0.1})));
      vorschlaege.add(await gesicht(id(5), vektor: vek({1: 1, 3: 0.15})));
      vorschlaege.add(await gesicht(id(6), vektor: vek({1: 1, 4: 0.2})));
      v4 = await gesicht(id(7), vektor: vek({1: 0.6, 5: 0.8}));
      vorschlaege.add(v4);
      await gesicht(id(8), vektor: richtung(30));
      await gesicht(id(9), vektor: richtung(31));
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    // PER-060
    final titelVorher = (await personZeile(tester, a))!.coverFaceCropPath;
    await klick(tester, find.text(de.personProfilbildAendern));
    await waitFor(tester, imDialog(find.text(de.personProfilbildWaehlen)));
    final wahl = find.descendant(
      of: imDialog(find.byType(GridView)),
      matching: find.byType(InkWell),
    );
    expect(wahl, findsNWidgets(3));
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    expect((await personZeile(tester, a))!.coverFaceCropPath, titelVorher);
    // Einen Ausschnitt wählen, der nicht schon das Profilbild ist (die
    // Reihenfolge im Dialog ist nicht festgelegt).
    String? titelNeu = titelVorher;
    for (var i = 0; i < 3 && titelNeu == titelVorher; i++) {
      await klick(tester, find.text(de.personProfilbildAendern));
      await waitFor(tester, wahl);
      await klick(tester, wahl.at(i));
      await waitGone(tester, find.byType(AlertDialog));
      titelNeu = (await personZeile(tester, a))!.coverFaceCropPath;
    }
    expect(titelNeu, isNot(titelVorher));
    expect([
      for (final g in benannt) bibliothek.paths.faceRelativePath(g),
    ], contains(titelNeu));
    await warte(tester, 500);
    expect(
      tester
          .widget<Profilbild>(
            find
                .descendant(
                  of: find.byType(PersonDetailScreen),
                  matching: find.byType(Profilbild),
                )
                .first,
          )
          .datei
          ?.path,
      bibliothek.paths.absolute(titelNeu!).path,
    );
    // PER-062
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await waitFor(tester, find.byType(PersonSuggestionsScreen));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.vorschlagTitel('Person A')),
      ),
      findsOneWidget,
    );
    expect(kacheln, findsNWidgets(4));
    for (final v in vorschlaege) {
      expect(ausgewaehlt(tester, v), isTrue);
    }
    expect(
      find.textContaining(RegExp(r'^[01]\.\d\d$')),
      findsNWidgets(4),
      reason: 'Ähnlichkeit an jeder Kachel',
    );
    expect(find.text(de.vorschlagUebernehmen(4)), findsOneWidget);
    // PER-064
    await klick(tester, find.text(de.vorschlagKeineWaehlen));
    expect(find.text(de.vorschlagUebernehmen(0)), findsOneWidget);
    await klick(tester, find.text(de.vorschlagAlleWaehlen));
    expect(find.text(de.vorschlagUebernehmen(4)), findsOneWidget);
    await klick(tester, find.text(de.vorschlagKeineWaehlen));
    await klick(tester, find.text(de.vorschlagUebernehmen(0)));
    await erwarteText(tester, de.vorschlagUebernommenMeldung(0));
    expect(await rueckmeldungen(tester), hasLength(4));
    // Das Gelernte: alle vier abgelehnt.
    expect(
      (await rueckmeldungen(tester)).where((r) => !r.accepted),
      hasLength(4),
    );
    await finish(tester);
  });

  // Behoben in #412: „Weitere Fotos suchen“ lässt Gesichter aus, die für
  // diese Person abgelehnt wurden (packages/kern, abgelehnteGesichterFuer),
  // und rechnet mit der Person, wie sie jetzt ist – in derselben Ansicht wie
  // nach erneutem Öffnen.
  pruefung('PER-063 Vorschläge teilweise übernehmen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('vt', 7));
    String id(int i) => f['vt$i.jpg']!.id;
    late String a, v4;
    final vorschlaege = <String>[];
    await tester.runAsync(() async {
      a = await person('Person A');
      for (var i = 1; i <= 3; i++) {
        await gesicht(id(i), person: a, vektor: richtung(1));
      }
      vorschlaege.add(await gesicht(id(4), vektor: vek({1: 1, 2: 0.1})));
      vorschlaege.add(await gesicht(id(5), vektor: vek({1: 1, 3: 0.15})));
      vorschlaege.add(await gesicht(id(6), vektor: vek({1: 1, 4: 0.2})));
      v4 = await gesicht(id(7), vektor: vek({1: 0.6, 5: 0.8}));
      vorschlaege.add(v4);
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await waitFor(tester, find.byType(PersonSuggestionsScreen));
    await tippe(tester, kachel(v4));
    await klick(tester, find.text(de.vorschlagUebernehmen(3)));
    await erwarteText(tester, de.vorschlagUebernommenMeldung(3));
    for (final v in vorschlaege) {
      final z = await gesichtZeile(tester, v);
      expect(z.personId, v == v4 ? isNull : a);
    }
    final gelernt = await rueckmeldungen(tester);
    expect(
      gelernt.where((r) => r.faceId == v4 && !r.accepted),
      hasLength(1),
      reason: 'zählt als Korrektur',
    );
    final schwelle = (await personZeile(tester, a))!.similarityThreshold;
    print('PER-063 gelernte Schwelle: $schwelle');
    // Gleich noch einmal suchen, in derselben Ansicht.
    melde.verlaufLeeren();
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await warte(tester, 1500);
    final gleicheAnsicht = sichtbar(kachel(v4));
    if (sichtbar(find.byType(PersonSuggestionsScreen))) await zurueck(tester);
    // Zum Vergleich: frisch geöffnete Ansicht.
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await klick(tester, find.text(de.personWeitereFotosSuchen));
    await warte(tester, 1500);
    final frischeAnsicht = sichtbar(kachel(v4));
    print(
      'PER-063 abgewähltes Gesicht erneut vorgeschlagen – dieselbe Ansicht: '
      '$gleicheAnsicht, frisch geöffnet: $frischeAnsicht',
    );
    expect(gleicheAnsicht, isFalse, reason: 'wird nicht wieder vorgeschlagen');
    expect(frischeAnsicht, isFalse);
    await finish(tester);
  });

  // =========================================================================
  // Wiedererkennung und Vorschläge
  // =========================================================================

  pruefung('PER-070 PER-071 PER-072 PER-073 Wer könnte das sein?', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('wk', 7));
    String id(int i) => f['wk$i.jpg']!.id;
    late String a, i1, i2;
    await tester.runAsync(() async {
      a = await person('Person A');
      await gesicht(id(1), person: a, vektor: richtung(1));
      await gesicht(id(2), person: a, vektor: richtung(1));
      await gesicht(id(3), vektor: richtung(20));
      i1 = await gesicht(id(4), ignoriert: true, vektor: richtung(1));
      i2 = await gesicht(id(5), ignoriert: true, vektor: vek({1: 1, 2: 0.2}));
    });
    // PER-071 (noch nie verglichen)
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, kacheln);
    await klick(tester, find.text(de.vorschlaegeTitel).last);
    await waitFor(tester, find.byType(VorschlaegeScreen));
    // PER-070 (Aufbau)
    expect(find.text(de.vorschlaegeEinleitung), findsOneWidget);
    expect(find.text(de.vorschlaegeBeiseite), findsOneWidget);
    await waitFor(tester, find.text(de.vorschlaegeLaufHinweis));
    await zurueck(tester);
    await tester.runAsync(() async {
      await for (final _ in bibliothek.backfillWiedererkennung()) {}
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, kacheln);
    await klick(tester, find.text(de.vorschlaegeTitel).last);
    await waitFor(tester, find.text(de.vorschlaegeKeine));
    // PER-072
    await klick(tester, find.text(de.vorschlaegeBeiseite));
    await waitFor(tester, find.text(de.vorschlaegeBeiseiteHinweis));
    await waitFor(tester, find.text(de.vorschlaegeBeiseiteNieVerglichen(2)));
    await klick(tester, find.text(de.vorschlaegeJetztVergleichen));
    await waitFor(
      tester,
      find.text(de.vorschlaegeAnzahl(2)),
      timeout: const Duration(seconds: 60),
    );
    expect(find.text('Person A'), findsOneWidget);
    expect((await gesichtZeile(tester, i1)).isIgnored, isTrue);
    expect((await gesichtZeile(tester, i2)).isIgnored, isTrue);
    await zurueck(tester);
    // PER-070: gespeicherte Vorschläge für Person A.
    final s = <String>[];
    await tester.runAsync(() async {
      s.add(await gesicht(id(6), vektor: richtung(1)));
      s.add(await gesicht(id(7), vektor: vek({1: 0.8, 2: 0.6})));
      s.add(await gesicht(id(6), vektor: vek({1: 0.6, 3: 0.8}), x: 0.6));
      await for (final _ in bibliothek.backfillWiedererkennung()) {}
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await rechtsklick(tester, kacheln);
    await klick(tester, find.text(de.vorschlaegeTitel).last);
    await waitFor(tester, find.text(de.vorschlaegeAnzahl(3)));
    expect(de.vorschlaegeEinleitung, contains('Sie sehen'));
    // PER-073
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonSuggestionsScreen));
    await tippe(tester, kachel(s[2]));
    await klick(tester, find.text(de.vorschlagUebernehmen(2)));
    await waitFor(tester, find.byType(VorschlaegeScreen));
    await waitFor(tester, find.text(de.vorschlaegeKeine));
    expect((await gesichtZeile(tester, s[0])).personId, a);
    expect((await gesichtZeile(tester, s[1])).personId, a);
    final abgelehnt = await gesichtZeile(tester, s[2]);
    expect(abgelehnt.personId, isNull);
    expect(abgelehnt.vorschlagPersonId, isNull);
    await tester.runAsync(() async {
      await for (final _ in bibliothek.backfillWiedererkennung()) {}
    });
    expect((await gesichtZeile(tester, s[2])).vorschlagPersonId, isNull);
    await finish(tester);
  });

  pruefung('PER-074 PER-075 Werkzeuge: Schwelle und sichere Vorschläge', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('ws', 8));
    String id(int i) => f['ws$i.jpg']!.id;
    late String a, ref, h1, h2, sicher, unsicher;
    await tester.runAsync(() async {
      a = await person('Person A');
      await gesicht(id(1), person: a, vektor: richtung(1));
      await gesicht(id(2), person: a, vektor: richtung(1));
      ref = await gesicht(id(3), vektor: richtung(40));
      h1 = await gesicht(id(4), vektor: vek({40: 0.9, 41: 0.436}));
      h2 = await gesicht(id(5), vektor: vek({40: 0.42, 42: 0.907}));
    });
    Future<int> mitAusgewaehlt() async {
      await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      await waehle(tester, [ref]);
      await klick(tester, find.text(de.personenAehnlicheAuswaehlen));
      await warte(tester, 400);
      final n = [h1, h2].where((x) => ausgewaehlt(tester, x)).length;
      return n;
    }

    expect(await mitAusgewaehlt(), 2);
    // PER-075
    await openSection(tester, Hauptbereich.werkzeuge);
    await scrollTo(
      tester,
      find.text(de.werkzAbschnittGesichtserkennung),
      in_: werkzeugListe(),
    );
    final reglerFinder = find.byWidgetPredicate(
      (w) => w is Slider && w.min == 0.15 && w.max == 0.6,
    );
    final regler = tester.widget<Slider>(reglerFinder);
    expect(regler.min, 0.15);
    expect(regler.max, 0.6);
    expect(find.text('0.36'), findsOneWidget);
    final rect = tester.getRect(reglerFinder);
    Future<double> tippeBei(double anteil) async {
      await tester.tapAt(
        Offset(rect.left + rect.width * anteil, rect.center.dy),
      );
      await warte(tester, 300);
      return bibliothek.faceSimilarityThreshold;
    }

    final w1 = await tippeBei(0.25);
    final w2 = await tippeBei(0.85);
    final anteil = 0.25 + (0.5 - w1) / (w2 - w1) * 0.6;
    await tippeBei(anteil);
    for (
      var i = 0;
      i < 3 && (bibliothek.faceSimilarityThreshold - 0.5).abs() > 0.001;
      i++
    ) {
      final schritt = bibliothek.faceSimilarityThreshold < 0.5 ? 0.012 : -0.012;
      await tippeBei(anteil + schritt * (i + 1));
    }
    expect(bibliothek.faceSimilarityThreshold, closeTo(0.5, 0.001));
    expect(
      await dbx(tester, () => bibliothek.db.faceSimilarityThresholdWert()),
      closeTo(0.5, 0.001),
      reason: 'gespeichert – der Start liest diesen Wert',
    );
    await openSection(tester, Hauptbereich.alben);
    await openSection(tester, Hauptbereich.werkzeuge);
    await scrollTo(
      tester,
      find.text(de.werkzAbschnittGesichtserkennung),
      in_: werkzeugListe(),
    );
    expect(find.text('0.50'), findsOneWidget);
    expect(await mitAusgewaehlt(), 1, reason: 'höhere Schwelle, weniger');
    // PER-074
    await openSection(tester, Hauptbereich.alben);
    await openSection(tester, Hauptbereich.werkzeuge);
    await scrollTo(
      tester,
      find.text(de.werkzAutoVorschlaege),
      in_: werkzeugListe(),
    );
    await klick(tester, find.text(de.werkzAutoVorschlaege));
    await waitFor(tester, find.text(de.werkzAutoVorschlaegeAb('0.70')));
    expect(
      await dbx(tester, () => bibliothek.db.vorschlaegeAutomatischAbWert()),
      closeTo(0.7, 0.001),
    );
    // Allgemeine Schwelle zurück auf die Vorgabe, damit Person A mit ihr
    // vergleicht.
    await tester.runAsync(() => bibliothek.setFaceSimilarityThreshold(0.363));
    await tester.runAsync(() async {
      sicher = await gesicht(id(6), vektor: vek({1: 0.8, 2: 0.6}));
      unsicher = await gesicht(id(7), vektor: vek({1: 0.5, 2: -0.866}));
    });
    await aufgabeStarten(tester, de.aufgWiedererkennungTitel, de.aufgFehlende);
    await warteAufLauf(tester, 'wiedererkennung');
    final s = await gesichtZeile(tester, sicher);
    expect(s.personId, a, reason: 'ab 0.70 ohne Rückfrage zugeordnet');
    expect(s.automatischZugeordnet, isTrue);
    final u = await gesichtZeile(tester, unsicher);
    expect(u.personId, isNull);
    expect(u.vorschlagPersonId, a, reason: 'unsicher bleibt Vorschlag');
    // Ausgeschaltet wird nichts mehr von selbst zugeordnet.
    await openSection(tester, Hauptbereich.alben);
    await openSection(tester, Hauptbereich.werkzeuge);
    await scrollTo(
      tester,
      find.text(de.werkzAutoVorschlaege),
      in_: werkzeugListe(),
    );
    await klick(tester, find.text(de.werkzAutoVorschlaege));
    await waitGone(tester, find.text(de.werkzAutoVorschlaegeAb('0.70')));
    late String spaeter;
    await tester.runAsync(() async {
      spaeter = await gesicht(id(8), vektor: vek({1: 0.9, 6: 0.436}));
    });
    await aufgabeStarten(tester, de.aufgWiedererkennungTitel, de.aufgFehlende);
    await warteAufLauf(tester, 'wiedererkennung');
    final sp = await gesichtZeile(tester, spaeter);
    expect(sp.personId, isNull);
    expect(sp.vorschlagPersonId, a);
    await finish(tester);
  });

  // =========================================================================
  // Gesichter im Foto bearbeiten
  // =========================================================================

  pruefung(
    'PER-076 PER-077 PER-078 PER-079 PER-081 PER-083 PER-084 Gesichter im Foto',
    (tester) async {
      print('Semantik an: ${tester.binding.semanticsEnabled}');
      final semantikZurueck = kennFehlerDulden(_semantikZusicherungen);
      await start(tester);
      final f = await fotos(tester, bilder('gf', 1));
      final foto = f['gf1.jpg']!;
      final original = await originalBytes(tester, foto);
      late String a, nA, u1, u2, ig;
      await tester.runAsync(() async {
        a = await person('Person A');
        nA = await gesicht(foto.id, person: a, x: 0.03, vektor: richtung(1));
        u1 = await gesicht(foto.id, x: 0.27);
        u2 = await gesicht(foto.id, x: 0.51);
        ig = await gesicht(foto.id, x: 0.75, ignoriert: true);
      });
      await personenOeffnen(tester);
      await klick(tester, find.text('Person A'));
      await waitFor(tester, find.byType(PersonDetailScreen));
      await doppelklick(
        tester,
        find.descendant(
          of: find.byType(PersonDetailScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
      );
      await waitFor(tester, rahmen(ig));
      Color farbe(String id) {
        final c = tester
            .widgetList<Container>(
              find.descendant(of: rahmen(id), matching: find.byType(Container)),
            )
            .firstWhere(
              (c) =>
                  c.decoration is BoxDecoration &&
                  (c.decoration! as BoxDecoration).border != null,
            );
        return ((c.decoration! as BoxDecoration).border! as Border).top.color;
      }

      Finder beschriftung(String id, String text) =>
          find.descendant(of: rahmen(id), matching: find.text(text));
      // PER-076
      expect(farbe(nA), Colors.greenAccent);
      expect(beschriftung(nA, 'Person A'), findsOneWidget);
      expect(farbe(u1), Colors.orangeAccent);
      expect(beschriftung(u1, de.gesichtUnbenannt), findsOneWidget);
      expect(farbe(ig), DunkleFlaeche.inaktiv);
      expect(beschriftung(ig, de.gesichtIgnoriert), findsOneWidget);
      // PER-079
      await klick(tester, rahmen(ig));
      await erwarteText(tester, de.gesichtZurueckgeholt);
      expect(find.byType(AlertDialog), findsNothing);
      await waitFor(tester, beschriftung(ig, de.gesichtUnbenannt));
      expect(farbe(ig), Colors.orangeAccent);
      // PER-077
      await klick(tester, rahmen(u1));
      await waitFor(tester, imDialog(find.text(de.gesichtBenennen)));
      expect(imDialog(find.text(de.allgAbbrechen)), findsOneWidget);
      expect(imDialog(find.text(de.gesichtIgnorieren)), findsOneWidget);
      await neuePersonImDialog(tester, 'Person B');
      await waitFor(tester, beschriftung(u1, 'Person B'));
      expect(farbe(u1), Colors.greenAccent);
      final b = await personNamens(tester, 'Person B');
      expect((await gesichtZeile(tester, u1)).personId, b.id);
      // PER-078
      await klick(tester, rahmen(nA));
      await waitFor(tester, imDialog(find.text(de.gesichtUmbenennen)));
      expect(imDialog(find.text(de.personAktuell('Person A'))), findsOneWidget);
      expect(imDialog(find.text(de.gesichtIgnorieren)), findsNothing);
      expect(imDialog(find.text(de.personVorschlag)), findsNothing);
      await bestehendePersonImDialog(tester, 'Person B');
      await waitFor(tester, beschriftung(nA, 'Person B'));
      final beiA = (await alleGesichter(tester)).where((x) => x.personId == a);
      expect(beiA, isEmpty, reason: 'Foto nicht mehr bei Person A');
      // PER-081
      await rechtsklick(tester, rahmen(u1));
      await klick(tester, find.text(de.gesichtZuordnungLoesen));
      await waitFor(tester, beschriftung(u1, de.gesichtUnbenannt));
      expect((await gesichtZeile(tester, u1)).personId, isNull);
      await rechtsklick(tester, rahmen(u2));
      await waitFor(tester, find.text(de.gesichtErkennungLoeschen));
      expect(find.text(de.gesichtZuordnungLoesen), findsNothing);
      await menueZu(tester);
      // PER-084
      final flaeche = tester.getRect(
        find
            .descendant(
              of: find.byType(FaceReviewScreen),
              matching: find.byType(AspectRatio),
            )
            .first,
      );
      final leer = Offset(flaeche.center.dx, flaeche.bottom - 15);
      await rechtsklickBei(tester, leer);
      await klick(tester, find.text(de.gesichtAlleUnbenanntenIgnorieren(3)));
      await waitFor(tester, beschriftung(u2, de.gesichtIgnoriert));
      expect(beschriftung(u1, de.gesichtIgnoriert), findsOneWidget);
      expect(beschriftung(ig, de.gesichtIgnoriert), findsOneWidget);
      expect(beschriftung(nA, 'Person B'), findsOneWidget);
      await rechtsklickBei(tester, leer);
      final keine = find.ancestor(
        of: find.text(de.gesichtAlleUnbenanntenIgnorieren(0)),
        matching: find.byType(MenuItemButton),
      );
      await waitFor(tester, keine);
      expect(tester.widget<MenuItemButton>(keine.first).onPressed, isNull);
      await menueZu(tester);
      // PER-083
      final crop = bibliothek.paths.absolute(
        bibliothek.paths.faceRelativePath(nA),
      );
      expect(await dbx(tester, () => crop.exists()), isTrue);
      await rechtsklick(tester, rahmen(nA));
      await klick(tester, find.text(de.gesichtErkennungLoeschen));
      await waitGone(tester, rahmen(nA));
      expect(find.byType(AlertDialog), findsNothing);
      expect(await dbx(tester, () => crop.exists()), isFalse);
      expect(await originalBytes(tester, foto), original);
      await finish(tester);
      semantikZurueck();
    },
  );

  pruefung('PER-087 PER-088 PER-107 Gesicht von Hand, Originale bleiben', (
    tester,
  ) async {
    print('Semantik an: ${tester.binding.semanticsEnabled}');
    final semantikZurueck = kennFehlerDulden(_semantikZusicherungen);
    await start(tester);
    final f = await fotos(tester, bilder('hd', 2));
    final m1 = f['hd1.jpg']!;
    final m2 = f['hd2.jpg']!;
    final vorher = [
      await originalBytes(tester, m1),
      await originalBytes(tester, m2),
    ];
    late String a, um, ub;
    await tester.runAsync(() async {
      a = await person('Person A');
      um = await gesicht(m1.id, x: 0.05, y: 0.05, w: 0.15, h: 0.2);
      ub = await gesicht(m1.id, x: 0.75, y: 0.05, w: 0.15, h: 0.2);
      await gesicht(m2.id);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, um);
    final position = find.textContaining(RegExp(r'^\d von 2$'));
    await waitFor(tester, position);
    final stelleVorher = tester.widget<Text>(position).data!;
    Rect flaeche() => tester.getRect(
      find
          .descendant(
            of: find.byType(FaceReviewScreen),
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    // PER-088
    await klick(tester, find.byTooltip(de.gesichtManuellHinzufuegen));
    await waitFor(tester, find.text(de.gesichtRechteckHinweis));
    final r = flaeche();
    await tester.tapAt(r.center);
    await warte(tester, 400);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'Klick legt nichts an',
    );
    final kurz = await tester.startGesture(
      r.center,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 4; i++) {
      await kurz.moveBy(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await kurz.up();
    await kurz.removePointer();
    await warte(tester, 400);
    expect(
      find.byType(AlertDialog),
      findsNothing,
      reason: 'Strich < 10 Punkte',
    );
    await taste(tester, LogicalKeyboardKey.arrowRight);
    expect(
      find.text(stelleVorher),
      findsOneWidget,
      reason: 'Pfeil blättert im Modus nicht',
    );
    await taste(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.text(de.gesichtRechteckHinweis));
    expect(find.byType(FaceReviewScreen), findsOneWidget);
    await taste(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(FaceReviewScreen));
    // PER-087
    await imFotoZeigen(tester, um);
    await klick(tester, find.byTooltip(de.gesichtManuellHinzufuegen));
    await waitFor(tester, find.text(de.gesichtRechteckHinweis));
    final r2 = flaeche();
    final anfang = Offset(r2.left + r2.width * 0.4, r2.top + r2.height * 0.4);
    final zug = await tester.startGesture(
      anfang,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 10; i++) {
      await zug.moveBy(const Offset(12, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final tuerkis = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          ((w.decoration! as BoxDecoration).border as Border?)?.top.color ==
              Colors.cyanAccent,
    );
    expect(tuerkis, findsOneWidget, reason: 'türkises Rechteck beim Ziehen');
    await zug.up();
    await zug.removePointer();
    await waitFor(tester, imDialog(find.text(de.gesichtNeuBenennen)));
    await bestehendePersonImDialog(tester, 'Person A');
    await waitGone(tester, find.text(de.gesichtRechteckHinweis));
    final neu = (await alleGesichter(
      tester,
    )).where((x) => x.personId == a && x.assetId == m1.id);
    expect(neu, hasLength(1));
    final hand = neu.single;
    expect(hand.cropRelativePath, isNotNull);
    expect(
      await dbx(
        tester,
        () => bibliothek.paths.absolute(hand.cropRelativePath!).exists(),
      ),
      isTrue,
    );
    expect(
      (await personZeile(tester, a))!.coverFaceCropPath,
      hand.cropRelativePath,
    );
    await waitFor(
      tester,
      find.descendant(of: rahmen(hand.id), matching: find.text('Person A')),
    );
    // PER-107: zuordnen, ignorieren, Erkennung löschen – Original gleich.
    await klick(tester, rahmen(um));
    await bestehendePersonImDialog(tester, 'Person A');
    await rechtsklick(tester, rahmen(ub));
    await klick(tester, find.text(de.gesichtIgnorieren));
    await warte(tester, 500);
    await rechtsklick(tester, rahmen(hand.id));
    await klick(tester, find.text(de.gesichtErkennungLoeschen));
    await waitGone(tester, rahmen(hand.id));
    expect((await gesichtZeile(tester, um)).personId, a);
    expect((await gesichtZeile(tester, ub)).isIgnored, isTrue);
    expect(await originalBytes(tester, m1), vorher[0]);
    expect(await originalBytes(tester, m2), vorher[1]);
    await finish(tester);
    semantikZurueck();
  });

  pruefung('PER-090 Manuelles Gesicht, Original nicht hier, Server weg', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('sv', 1));
    final foto = f['sv1.jpg']!;
    late String u;
    await tester.runAsync(() async {
      u = await gesicht(foto.id);
    });
    final anzeige = bibliothek.paths.absolute(lesbarerPfad(foto));
    final beiseite = File('${anzeige.path}.beiseite');
    // Nachgestellt: Das Original liegt nicht hier, und das Holen vom
    // Server scheitert (wie bei einem gestoppten Server).
    await tester.runAsync(() async => anzeige.renameSync(beiseite.path));
    bibliothek.paths.beschaffe = (rel) async =>
        throw const SocketException('Server nicht erreichbar');
    addTearDown(() => bibliothek.paths.beschaffe = null);
    final vorher = (await alleGesichter(tester)).length;
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, u);
    await klick(tester, find.byTooltip(de.gesichtManuellHinzufuegen));
    final r = tester.getRect(
      find
          .descendant(
            of: find.byType(FaceReviewScreen),
            matching: find.byType(AspectRatio),
          )
          .first,
    );
    final zug = await tester.startGesture(
      Offset(r.left + r.width * 0.5, r.top + r.height * 0.5),
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 0; i < 8; i++) {
      await zug.moveBy(const Offset(12, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await zug.up();
    await zug.removePointer();
    await neuePersonImDialog(tester, 'Person B');
    await erwarteText(tester, de.entwOriginalNichtDa);
    expect((await alleGesichter(tester)).length, vorher);
    expect(
      (await allePersonen(tester)).where((x) => x.name == 'Person B'),
      isEmpty,
      reason: 'keine leere Person B',
    );
    bibliothek.paths.beschaffe = null;
    await tester.runAsync(() async => beiseite.renameSync(anzeige.path));
    await finish(tester);
  });

  pruefung('PER-093 PER-097 Sperren aus der Gesichter-Ansicht', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('gs', 4));
    String id(int i) => f['gs$i.jpg']!.id;
    await tester.runAsync(() async {
      final a = await person('Person A');
      for (var i = 1; i <= 3; i++) {
        await gesicht(id(i), person: a);
      }
      await bibliothek.setupVaultPin(_testPin);
      bibliothek.lockVaultSession();
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    final detailKacheln = find.descendant(
      of: find.byType(PersonDetailScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, detailKacheln);
    expect(detailKacheln, findsNWidgets(3));
    // PER-093: das mittlere (gs2) sperren.
    await doppelklick(tester, detailKacheln.at(1));
    await waitFor(tester, find.text(de.gesichtPosition(2, 3)));
    await klick(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
    await waitFor(tester, imDialog(field(de.pinFeld)));
    await enter(tester, imDialog(field(de.pinFeld)), _testPin);
    await klick(tester, imDialog(find.text('OK')));
    await erwarteText(
      tester,
      de.gesichtInGesperrtemOrdner,
      timeout: const Duration(seconds: 30),
    );
    await waitFor(tester, find.text(de.gesichtPosition(2, 2)));
    expect(
      find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.text('gs1.jpg'),
      ),
      findsOneWidget,
      reason: 'das nächste wird gezeigt',
    );
    expect((await assetZeile(tester, id(2))).isLocked, isTrue);
    // Weiter sperren bis zum letzten: dann schliesst die Ansicht.
    melde.verlaufLeeren();
    await klick(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
    await erwarteText(
      tester,
      de.gesichtInGesperrtemOrdner,
      timeout: const Duration(seconds: 30),
    );
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.text('gs3.jpg'),
      ),
    );
    melde.verlaufLeeren();
    await klick(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
    await erwarteText(
      tester,
      de.gesichtInGesperrtemOrdner,
      timeout: const Duration(seconds: 30),
    );
    await waitGone(tester, find.byType(FaceReviewScreen));
    await waitFor(tester, find.text(de.personKeineFotos));
    // PER-097: eine Reihe mit einem gesperrten Foto. In der Oberfläche
    // führt kein Weg dorthin (alle Quellen lassen Gesperrtes weg), die
    // Ansicht wird deshalb mit einer solchen Reihe geöffnet.
    final offen = await assetZeile(tester, id(4));
    final gesperrt = await assetZeile(tester, id(2));
    expect(gesperrt.isLocked, isTrue);
    unawaited(
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              FaceReviewScreen(library: bibliothek, assets: [offen, gesperrt]),
        ),
      ),
    );
    await waitFor(tester, find.text(de.gesichtPosition(1, 2)));
    await taste(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, find.text(de.gesichtGesperrt));
    expect(find.byType(Gesichtsrahmen), findsNothing);
    for (final t in [
      de.gesichtRahmenAusblenden,
      de.gesichtManuellHinzufuegen,
      de.viewerFavoritSetzen,
      de.viewerInGesperrtenOrdner,
      de.viewerInfo,
      de.gesichtFotoLoeschen,
    ]) {
      expect(find.byTooltip(t), findsNothing, reason: t);
    }
    expect(symbolknopf(tester, de.gesichtVoriges).onPressed, isNotNull);
    await klick(tester, find.byTooltip(de.gesichtVoriges));
    await waitFor(tester, find.text(de.gesichtPosition(1, 2)));
    expect(find.text(de.gesichtGesperrt), findsNothing);
    await finish(tester);
  });

  pruefung('PER-098 Gesichter bearbeiten aus der Vollbildansicht', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, [
      ...bilder('vb', 2),
      fixture('video_5s.mp4'),
    ]);
    final video = f['video_5s.mp4']!;
    await tester.runAsync(() async {
      final a = await person('Person A');
      await gesicht(f['vb1.jpg']!.id, person: a);
      await gesicht(f['vb2.jpg']!.id, person: a);
      await gesicht(video.id, person: a);
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    Finder kachelVon(String assetId) => find.byWidgetPredicate(
      (w) => w is AssetThumbnailTile && w.asset.id == assetId,
    );
    await waitFor(tester, kachelVon(f['vb1.jpg']!.id));
    final reihe = [
      for (final k in tester.widgetList<AssetThumbnailTile>(
        find.descendant(
          of: find.byType(PersonDetailScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
      ))
        k.asset.id,
    ];
    final stelle = reihe.indexOf(f['vb1.jpg']!.id);
    await tippe(tester, kachelVon(f['vb1.jpg']!.id));
    await waitFor(tester, find.byType(AssetViewerScreen));
    await warte(tester, 800);
    await rechtsklick(tester, find.byType(PageView));
    await klick(tester, find.text(de.viewerGesichterBearbeiten));
    await waitFor(tester, find.byType(FaceReviewScreen));
    await waitFor(
      tester,
      find.text(de.gesichtPosition(stelle + 1, reihe.length)),
    );
    expect(
      find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.text('vb1.jpg'),
      ),
      findsOneWidget,
    );
    await taste(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(FaceReviewScreen));
    await zurueck(tester);
    await waitGone(tester, find.byType(AssetViewerScreen));
    // Beim Video fehlt der Eintrag.
    await tippe(tester, kachelVon(video.id));
    await waitFor(tester, find.byType(AssetViewerScreen));
    await warte(tester, 1500);
    await rechtsklick(tester, find.byType(PageView));
    await waitFor(tester, find.text(de.viewerAehnlicheZeigen));
    expect(find.text(de.viewerGesichterBearbeiten), findsNothing);
    await finish(tester);
  });

  // =========================================================================
  // Personen zusammenführen
  // =========================================================================

  pruefung('PER-099 PER-100 PER-102 Zusammenführen', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('zf', 4));
    String id(int i) => f['zf$i.jpg']!.id;
    late String a;
    await tester.runAsync(() async {
      a = await person('Person A');
      await gesicht(id(1), person: a);
    });
    // PER-102: nur eine Person.
    await personenOeffnen(tester);
    await langDruecken(tester, find.text('Person A'));
    await warte(tester, 600);
    expect(find.byType(SimpleDialog), findsNothing);
    late String b, kind, gb1, gb2;
    await tester.runAsync(() async {
      b = await person('Person B');
      kind = await person('Kind');
      gb1 = await gesicht(id(2), person: b);
      gb2 = await gesicht(id(3), person: b);
      await gesicht(id(4), person: a);
      await verwandt(kind, b);
      await partner(a, b);
    });
    // PER-099
    await personenOeffnen(tester);
    await waitFor(tester, reiterText(de.tabMitZahl(de.personenTab, 3)));
    await langDruecken(tester, find.text('Person B'));
    print(
      'PER-099: erster langer Druck öffnet: '
      '${sichtbar(find.text(de.personenZusammenfuehrenMit('Person B')))}',
    );
    await waitFor(tester, find.text(de.personenZusammenfuehrenMit('Person B')));
    final optionen = find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.byType(SimpleDialogOption),
    );
    expect(optionen, findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Kind'),
      ),
      findsOneWidget,
    );
    await klick(
      tester,
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Person A'),
      ),
    );
    await waitFor(tester, find.text(de.personenZusammenfuehrenTitel));
    expect(
      find.text(de.personenZusammenfuehrenText('Person B', 'Person A')),
      findsOneWidget,
    );
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    expect(await personZeile(tester, b), isNotNull);
    expect((await gesichtZeile(tester, gb1)).personId, b);
    // PER-100 – erst, wenn die Rückfrage ganz verschwunden ist; ihre
    // Barriere fängt sonst den Druck ab.
    await waitGone(tester, find.byType(AlertDialog));
    await warte(tester, 500);
    await langDruecken(tester, find.text('Person B'));
    final gleichWieder = sichtbar(
      find.text(de.personenZusammenfuehrenMit('Person B')),
    );
    print('PER-100: zweiter langer Druck ohne Neuladen öffnet: $gleichWieder');
    if (!gleichWieder) {
      await personenOeffnen(tester);
      await langDruecken(tester, find.text('Person B'));
      print(
        'PER-100: nach erneutem Öffnen: '
        '${sichtbar(find.text(de.personenZusammenfuehrenMit('Person B')))}',
      );
    }
    await waitFor(tester, find.text(de.personenZusammenfuehrenMit('Person B')));
    await klick(
      tester,
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Person A'),
      ),
    );
    await klick(
      tester,
      imDialog(find.widgetWithText(FilledButton, de.personenZusammenfuehren)),
    );
    await waitGone(tester, find.text('Person B'));
    await waitFor(tester, reiterText(de.tabMitZahl(de.personenTab, 2)));
    expect(await personZeile(tester, b), isNull);
    expect((await gesichtZeile(tester, gb1)).personId, a);
    expect((await gesichtZeile(tester, gb2)).personId, a);
    final kanten = await dbx(
      tester,
      () => bibliothek.db.select(bibliothek.db.personBeziehungen).get(),
    );
    expect(
      kanten.where((k) => k.personId == kind && k.andereId == a),
      hasLength(1),
      reason: 'die Verwandtschaft hängt jetzt an Person A',
    );
    expect(kanten.where((k) => k.personId == k.andereId), isEmpty);
    expect(kanten.where((k) => k.personId == b || k.andereId == b), isEmpty);
    await finish(tester);
  });

  // Behoben in #412: mergePeople überträgt auch Lebensdaten, Geschlecht und
  // den Lebenslauf der aufgelösten Person.
  pruefung('PER-101 Lebensdaten und Lebenslauf beim Zusammenführen', (
    tester,
  ) async {
    // Mit übertragenem Geburtsdatum blendet der Lebensdaten-Dialog seine
    // Feldbeschriftung ein. Der Taktgeber des Prüfstands löst dabei
    // gelegentlich ein Bild vor dem letzten aus (`elapsedInSeconds >= 0.0`
    // in AnimationController._tick) – eine Frage des Prüfstands, nicht der
    // App (wie in katalog_r2_sic_test.dart).
    kennFehlerDulden('elapsedInSeconds >= 0.0');
    await start(tester);
    late String a, b;
    await tester.runAsync(() async {
      a = await person('Person A');
      b = await person(
        'Person B',
        geburt: DateTime(1950, 6, 7),
        geschlecht: Geschlecht.weiblich,
      );
      await ereignis(b, 'hochzeit', datum: DateTime(1975, 8, 9));
      // Damit Person A im Baum ein Schild mit Menü hat.
      await verwandt(await person('Kind'), a);
    });
    await personenOeffnen(tester);
    await waitFor(tester, find.text('Person B'));
    await langDruecken(tester, find.text('Person B'));
    await klick(
      tester,
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Person A'),
      ),
    );
    await klick(
      tester,
      imDialog(find.widgetWithText(FilledButton, de.personenZusammenfuehren)),
    );
    await waitGone(tester, find.text('Person B'));
    final verwaist = await dbx(
      tester,
      () => (bibliothek.db.select(
        bibliothek.db.lebensereignisse,
      )..where((t) => t.personId.equals(b))).get(),
    );
    print(
      'PER-101: verwaiste Lebensereignisse von Person B: ${verwaist.length}',
    );
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await waitFor(tester, find.text(de.stammbaumAngaben));
    final geburtSichtbar = sichtbar(imDialog(find.text('7.6.1950')));
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebenslauf));
    await waitFor(tester, find.byType(LebenslaufScreen));
    await warte(tester, 500);
    final hochzeitSichtbar = sichtbar(find.text(de.lebenslaufHochzeit));
    final nachher = (await personZeile(tester, a))!;
    print(
      'PER-101: Geburt im Dialog $geburtSichtbar, Hochzeit $hochzeitSichtbar, '
      'geburtsdatum ${nachher.geburtsdatum}, geschlecht ${nachher.geschlecht}',
    );
    expect(nachher.geburtsdatum, DateTime(1950, 6, 7));
    expect(geburtSichtbar, isTrue);
    expect(hochzeitSichtbar, isTrue);
    expect(verwaist, isEmpty);
    await finish(tester);
  });

  // =========================================================================
  // Datenschutz
  // =========================================================================

  pruefung('PER-103 Gesperrte und gelöschte Fotos im Gesichterraster', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('ds', 4));
    String id(int i) => f['ds$i.jpg']!.id;
    late String sichtbarId;
    await tester.runAsync(() async {
      await gesicht(id(1));
      await gesicht(id(2), ignoriert: true);
      await gesicht(id(3));
      sichtbarId = await gesicht(id(4));
      await bibliothek.setupVaultPin(_testPin);
      await bibliothek.lockAsset(f['ds1.jpg']!);
      await bibliothek.lockAsset(f['ds2.jpg']!);
      await bibliothek.db.fuehreAus(InDenPapierkorb([id(3)]));
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(tester, kachel(sichtbarId));
    expect(kacheln, findsOneWidget);
    expect(
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 1)),
      findsOneWidget,
    );
    expect(reiterText(de.personenIgnoriertTab), findsOneWidget);
    await klick(tester, reiter(de.personenIgnoriertTab));
    await waitFor(tester, find.text(de.personenIgnoriertLeer));
    // Herausholen.
    await tester.runAsync(() async {
      for (final i in [1, 2]) {
        final a = await (bibliothek.db.select(
          bibliothek.db.assets,
        )..where((t) => t.id.equals(id(i)))).getSingle();
        await bibliothek.unlockAsset(a);
      }
      await bibliothek.db.fuehreAus(AusDemPapierkorb([id(3)]));
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waitFor(
      tester,
      reiterText(de.tabMitZahl(de.personenUnbenannteTab, 3)),
    );
    expect(kacheln, findsNWidgets(3));
    expect(
      reiterText(de.tabMitZahl(de.personenIgnoriertTab, 1)),
      findsOneWidget,
    );
    await finish(tester);
  });

  pruefung('PER-104 PER-105 Profilbild und Personenansicht ohne Gesperrtes', (
    tester,
  ) async {
    await start(tester);
    final f = await fotos(tester, bilder('sp', 5));
    String id(int i) => f['sp$i.jpg']!.id;
    late String a, b, gA1, gA2, q;
    await tester.runAsync(() async {
      a = await person('Person A');
      b = await person('Person B');
      gA1 = await gesicht(id(1), person: a, vektor: richtung(1));
      gA2 = await gesicht(id(2), person: a, vektor: richtung(1));
      await gesicht(id(3), person: b, vektor: richtung(9));
      q = await gesicht(id(4), vektor: vek({1: 1, 2: 0.1}));
      await bibliothek.setupVaultPin(_testPin);
    });
    expect(
      (await personZeile(tester, a))!.coverFaceCropPath,
      bibliothek.paths.faceRelativePath(gA1),
    );
    // PER-104: Foto des Profilbilds sperren.
    await tester.runAsync(() => bibliothek.lockAsset(f['sp1.jpg']!));
    expect(
      (await personZeile(tester, a))!.coverFaceCropPath,
      bibliothek.paths.faceRelativePath(gA2),
    );
    await personenOeffnen(tester);
    Profilbild bildVon(String name) => tester.widget<Profilbild>(
      find
          .descendant(
            of: find
                .ancestor(of: find.text(name), matching: find.byType(InkWell))
                .first,
            matching: find.byType(Profilbild),
          )
          .first,
    );
    await waitFor(tester, find.text('Person A'));
    expect(
      bildVon('Person A').datei?.path,
      bibliothek.paths.absolute(bibliothek.paths.faceRelativePath(gA2)).path,
    );
    // Ohne Ersatz: Platzhalter.
    await tester.runAsync(() => bibliothek.lockAsset(f['sp3.jpg']!));
    await personenOeffnen(tester);
    await waitFor(tester, find.text('Person B'));
    expect(bildVon('Person B').datei, isNull);
    // PER-105 und Profilbild-Dialog
    await klick(tester, find.text('Person A'));
    final detailKacheln = find.descendant(
      of: find.byType(PersonDetailScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, detailKacheln);
    expect(detailKacheln, findsOneWidget, reason: 'das gesperrte fehlt');
    await klick(tester, find.text(de.personProfilbildAendern));
    await waitFor(tester, imDialog(find.text(de.personProfilbildWaehlen)));
    expect(
      find.descendant(
        of: imDialog(find.byType(GridView)),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    // PER-105: nach dem Herausholen wieder da.
    await tester.runAsync(() async {
      final x = await (bibliothek.db.select(
        bibliothek.db.assets,
      )..where((t) => t.id.equals(id(1)))).getSingle();
      await bibliothek.unlockAsset(x);
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, detailKacheln);
    await warte(tester, 500);
    expect(detailKacheln, findsNWidgets(2), reason: 'wieder da');
    print('PER-104 q=$q');
    await finish(tester);
  });

  // Behoben in #403: Der Abdruck des Vorrats zählt gesperrte Fotos nicht
  // mehr mit, Sperren verwirft ihn also.
  pruefung('PER-106 Kein Namensvorschlag aus gesperrten Fotos', (tester) async {
    await start(tester);
    final f = await fotos(tester, bilder('ns', 3));
    late String q;
    await tester.runAsync(() async {
      final a = await person('Person A');
      await gesicht(f['ns1.jpg']!.id, person: a, vektor: richtung(1));
      await gesicht(f['ns2.jpg']!.id, person: a, vektor: richtung(1));
      q = await gesicht(f['ns3.jpg']!.id, vektor: vek({1: 1, 2: 0.1}));
      await bibliothek.setupVaultPin(_testPin);
    });
    // Gegenprobe: Solange nichts gesperrt ist, wird Person A vorgeschlagen.
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, q);
    await klick(tester, rahmen(q));
    await waitFor(tester, imDialog(find.text(de.personVorschlag)));
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await taste(tester, LogicalKeyboardKey.escape);
    // Alle Fotos von Person A in den gesperrten Ordner.
    await tester.runAsync(() async {
      await bibliothek.lockAsset(f['ns1.jpg']!);
      await bibliothek.lockAsset(f['ns2.jpg']!);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await imFotoZeigen(tester, q);
    await klick(tester, rahmen(q));
    await waitFor(tester, imDialog(find.text(de.gesichtBenennen)));
    final vorschlag = sichtbar(imDialog(find.text(de.personVorschlag)));
    print('PER-106: Vorschlag trotz gesperrter Fotos: $vorschlag');
    expect(vorschlag, isFalse);
    await finish(tester);
  });

  pruefung('PER-108 Gesichtserkennung ohne Netz', (tester) async {
    await start(tester, modelle: _gesichtsmodelle);
    final f = await fotos(tester, bilder('nz', 4));
    final protokoll = _Netzprotokoll();
    HttpOverrides.global = protokoll;
    addTearDown(() => HttpOverrides.global = null);
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await klick(tester, find.text(de.personenJetztSuchen));
    await warteAufLauf(tester, 'gesichter');
    expect(bibliothek.lauf('gesichter')?.erfolgreich ?? true, isTrue);
    late String g1, g2;
    await tester.runAsync(() async {
      g1 = await gesicht(f['nz1.jpg']!.id);
      g2 = await gesicht(f['nz2.jpg']!.id);
    });
    await personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
    await waehle(tester, [g1, g2]);
    await klick(tester, find.text(de.personenZuordnenKnopf(2)));
    await neuePersonImDialog(tester, 'Person A');
    final a = await personNamens(tester, 'Person A');
    expect((await gesichtZeile(tester, g1)).personId, a.id);
    print('PER-108 HTTP-Clients: ${protokoll.clients}');
    expect(protokoll.clients, isEmpty, reason: 'keine Netzwerkanfrage');
    await finish(tester);
  });

  // =========================================================================
  // Stammbaum
  // =========================================================================

  // Behoben in #412: Der Knopf „Andere Person in die Mitte“ steht auch im
  // leeren Stammbaum, auf den sein Text verweist.
  pruefung('PER-109 Stammbaum ohne Personen', (tester) async {
    await start(tester);
    await stammbaumOeffnen(tester);
    await waitFor(tester, find.text(de.stammbaumKeinePersonen));
    expect(
      find.byTooltip(de.stammbaumAndereWaehlen),
      findsOneWidget,
      reason: 'der Text verweist auf diesen Knopf',
    );
    await klick(tester, find.byTooltip(de.stammbaumAndereWaehlen));
    await neuePersonImDialog(tester, 'Person A');
    await waitFor(tester, find.text(de.stammbaumTitelVon('Person A')));
    await finish(tester);
  });

  pruefung('PER-111 Andere Person in die Mitte', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      await person('Person A');
      await person('Person B');
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await klick(tester, find.byTooltip(de.stammbaumAndereWaehlen));
    await waitFor(tester, imDialog(find.text(de.stammbaumAndereWaehlen)));
    await klick(tester, dialogZeile('Person B'));
    await klick(tester, imDialog(find.text(de.personZuordnenAktion)));
    await waitFor(tester, find.text(de.stammbaumTitelVon('Person B')));
    await klick(tester, find.byTooltip(de.stammbaumAndereWaehlen));
    await neuePersonImDialog(tester, 'Kind');
    await waitFor(tester, find.text(de.stammbaumTitelVon('Kind')));
    expect((await allePersonen(tester)).map((p) => p.name), contains('Kind'));
    await finish(tester);
  });

  pruefung(
    'PER-115 PER-116 PER-117 PER-118 PER-119 PER-120 PER-122 PER-123 Beziehungen',
    (tester) async {
      await start(tester);
      late String a, b;
      await tester.runAsync(() async {
        a = await person('Person A');
        b = await person('Person B');
      });
      await stammbaumOeffnen(tester);
      await mitte(tester, 'Person A');
      Future<List<PersonBeziehungenData>> kanten() => dbx(
        tester,
        () => bibliothek.db.select(bibliothek.db.personBeziehungen).get(),
      );
      // PER-115
      await klick(tester, find.byTooltip(de.stammbaumElternteilHinzufuegen));
      await waitFor(tester, find.text(de.stammbaumLeiblich));
      expect(find.text(de.stammbaumAdoptiv), findsOneWidget);
      expect(find.text(de.stammbaumPflege), findsOneWidget);
      await klick(tester, find.text(de.stammbaumLeiblich));
      await waitFor(
        tester,
        imDialog(find.text(de.stammbaumElternteilHinzufuegen)),
      );
      expect(dialogZeile('Person A'), findsNothing, reason: 'die Mitte fehlt');
      await neuePersonImDialog(tester, 'Person C');
      await waitFor(tester, schild('Person C'));
      expect(
        find.descendant(
          of: find.byType(ZierbaumAnsicht),
          matching: find.text('Elternteil'),
        ),
        findsOneWidget,
      );
      // PER-116
      await klick(tester, find.byTooltip(de.stammbaumPartnerHinzufuegen));
      await bestehendePersonImDialog(tester, 'Person B');
      await waitFor(tester, schild('Person B'));
      expect(
        (await kanten()).where((k) => k.art == Verwandtschaft.partner.name),
        hasLength(1),
      );
      // PER-117
      await klick(tester, find.byTooltip(de.stammbaumKindHinzufuegen));
      await klick(tester, find.text(de.stammbaumLeiblich));
      await neuePersonImDialog(tester, 'Kind');
      await waitFor(tester, schild('Kind'));
      final kind = await personNamens(tester, 'Kind');
      expect(
        (await kanten()).where((k) => k.personId == kind.id && k.andereId == a),
        hasLength(1),
      );
      // PER-118
      await klick(tester, find.byTooltip(de.stammbaumElternteilHinzufuegen));
      await klick(tester, find.text(de.stammbaumAdoptiv));
      await neuePersonImDialog(tester, 'Person D');
      await waitFor(tester, schild('Person D'));
      expect(
        find.descendant(
          of: find.byType(ZierbaumAnsicht),
          matching: find.text('Adoptivelternteil'),
        ),
        findsOneWidget,
      );
      // PER-120
      melde.verlaufLeeren();
      final vorher = (await kanten()).length;
      await klick(tester, find.byTooltip(de.stammbaumPartnerHinzufuegen));
      await bestehendePersonImDialog(tester, 'Person B');
      await erwarteText(tester, de.stammbaumFehlerVorhanden);
      expect((await kanten()).length, vorher);
      // PER-122
      await schildMenue(tester, 'Person C');
      for (final t in [
        de.stammbaumInDieMitte,
        de.stammbaumLebensdaten,
        de.stammbaumLebenslauf,
        de.stammbaumFotosZeigen,
        de.stammbaumVerbindungsart,
        de.stammbaumVerbindungEntfernen,
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      await taste(tester, LogicalKeyboardKey.escape);
      expect(find.byTooltip(de.stammbaumMenue), findsWidgets);
      await schildMenue(tester, 'Person A');
      expect(find.text(de.stammbaumInDieMitte), findsNothing);
      await taste(tester, LogicalKeyboardKey.escape);
      // PER-123
      await schildMenue(tester, 'Person C');
      await klick(tester, find.text(de.stammbaumVerbindungEntfernen));
      await waitFor(
        tester,
        find.text(de.stammbaumVerbindungEntfernenFrage('Person C', 'Person A')),
      );
      await klick(tester, imDialog(find.text(de.allgAbbrechen)));
      expect(schild('Person C'), findsOneWidget);
      await schildMenue(tester, 'Person C');
      await klick(tester, find.text(de.stammbaumVerbindungEntfernen));
      await klick(tester, imDialog(find.text(de.allgEntfernen)));
      await waitGone(tester, schild('Person C'));
      await schildMenue(tester, 'Person D');
      await klick(tester, find.text(de.stammbaumVerbindungEntfernen));
      await klick(tester, imDialog(find.text(de.allgEntfernen)));
      await waitGone(tester, schild('Person D'));
      final namen = (await allePersonen(tester)).map((p) => p.name).toSet();
      expect(namen, containsAll(['Person C', 'Person D']));
      // PER-119
      melde.verlaufLeeren();
      await schildMenue(tester, 'Kind');
      await klick(tester, find.text(de.stammbaumInDieMitte));
      await waitFor(tester, find.text(de.stammbaumTitelVon('Kind')));
      final vorKreis = (await kanten()).length;
      await klick(tester, find.byTooltip(de.stammbaumKindHinzufuegen));
      await klick(tester, find.text(de.stammbaumLeiblich));
      await bestehendePersonImDialog(tester, 'Person A');
      await erwarteText(tester, de.stammbaumFehlerKreis);
      expect((await kanten()).length, vorKreis);
      print('PER-115..123 Person B: $b');
      await finish(tester);
    },
  );

  pruefung('PER-133 PER-134 PER-137 Lebensdaten', (tester) async {
    await start(tester);
    late String a;
    await tester.runAsync(() async {
      a = await person('Person A');
      await verwandt(a, await person('Person B'));
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    // PER-133
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await waitFor(tester, find.text(de.stammbaumAngaben));
    expect(imDialog(find.text(de.stammbaumGeschlecht)), findsOneWidget);
    expect(imDialog(find.text(de.stammbaumGeboren)), findsOneWidget);
    expect(imDialog(find.text(de.stammbaumGestorben)), findsOneWidget);
    expect(imDialog(find.text(de.stammbaumUnbekannt)), findsNWidgets(2));
    expect(imDialog(find.text(de.stammbaumNurJahrHinweis)), findsOneWidget);
    await klick(tester, imDialog(find.byType(DropdownButton<Geschlecht?>)));
    for (final g in [
      de.stammbaumGeschlechtOffen,
      de.stammbaumGeschlechtWeiblich,
      de.stammbaumGeschlechtMaennlich,
      de.stammbaumGeschlechtDivers,
    ]) {
      expect(find.text(g), findsWidgets, reason: g);
    }
    await klick(tester, find.text(de.stammbaumGeschlechtWeiblich).last);
    await klick(tester, imDialog(find.text(de.stammbaumUnbekannt)).first);
    await datumEingeben(tester, DateTime(1986, 11, 15));
    expect(imDialog(find.text('15.11.1986')), findsOneWidget);
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(ZierbaumAnsicht),
        matching: find.textContaining('1986'),
      ),
    );
    var p1 = (await personZeile(tester, a))!;
    expect(p1.geburtsdatum, DateTime(1986, 11, 15));
    expect(p1.geschlecht, isNotNull);
    // PER-134
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await waitFor(tester, imDialog(find.text('15.11.1986')));
    await klick(tester, imDialog(find.byTooltip(de.allgEntfernen)).first);
    expect(imDialog(find.text(de.stammbaumUnbekannt)), findsNWidgets(2));
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await warte(tester, 500);
    p1 = (await personZeile(tester, a))!;
    expect(p1.geburtsdatum, isNull);
    final geschlechtVorher = p1.geschlecht;
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await klick(tester, imDialog(find.byType(DropdownButton<Geschlecht?>)));
    await klick(tester, find.text(de.stammbaumGeschlechtDivers).last);
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await warte(tester, 300);
    expect((await personZeile(tester, a))!.geschlecht, geschlechtVorher);
    // PER-137: Gestorben vor Geboren – der Dialog speichert es.
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await waitFor(tester, find.text(de.stammbaumAngaben));
    await klick(tester, imDialog(find.text(de.stammbaumUnbekannt)).first);
    await datumEingeben(tester, DateTime(2000, 1, 1));
    await klick(tester, imDialog(find.text(de.stammbaumUnbekannt)).first);
    await datumEingeben(tester, DateTime(1990, 1, 1));
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await warte(tester, 500);
    p1 = (await personZeile(tester, a))!;
    expect(p1.geburtsdatum, DateTime(2000));
    expect(p1.sterbedatum, DateTime(1990));
    await stammbaumMehr(tester, de.stammbaumFamilienstatistik);
    await waitFor(tester, find.byType(FamilienstatistikScreen));
    final negativ = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'(^|\s)[-−]\s?\d').hasMatch(w.data ?? ''),
    );
    expect(negativ, findsNothing, reason: 'kein negatives Lebensalter');
    await finish(tester);
  });

  // Befund: showDatePicker mit firstDate 1800 bei einem Datum vor 1800
  // (lib/screens/stammbaum_screen.dart:3014–3019).
  pruefung('PER-136 Lebensdaten vor 1800', (tester) async {
    await start(tester);
    await stammbaumOeffnen(tester);
    await gedcomEinlesen(
      tester,
      gedcom([
        '0 @I1@ INDI',
        '1 NAME Person /A/',
        '1 SEX F',
        '1 BIRT',
        '2 DATE 1750',
        '1 FAMC @F1@',
        '0 @I2@ INDI',
        '1 NAME Person /B/',
        '1 SEX M',
        '1 FAMS @F1@',
        '0 @F1@ FAM',
        '1 HUSB @I2@',
        '1 CHIL @I1@',
      ]),
    );
    final a = await personNamens(tester, 'Person A');
    expect(a.geburtsdatum?.year, 1750);
    await mitte(tester, 'Person A');
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await waitFor(tester, imDialog(find.text('1.1.1750')));
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await warte(tester, 500);
    expect((await personZeile(tester, a.id))!.geburtsdatum?.year, 1750);
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebensdaten));
    await klick(tester, imDialog(find.text('1.1.1750')));
    await warte(tester, 800);
    final fehler = tester.takeException();
    print('PER-136 Ausnahme beim Datumsdialog: $fehler');
    expect(fehler, isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await finish(tester);
  });

  pruefung('PER-139 PER-147 PER-155 PER-158 Ansichten', (tester) async {
    await start(tester);
    late String a;
    await tester.runAsync(() async {
      a = await person('Person A', geburt: DateTime(1960));
      final b = await person('Person B', geburt: DateTime(1930));
      final c = await person('Person C', geburt: DateTime(1932));
      final d = await person('Person D', geburt: DateTime(1962));
      final e = await person('Person E', geburt: DateTime(1990));
      final k = await person('Kind', geburt: DateTime(1992));
      for (final x in [a, d]) {
        await verwandt(x, b);
        await verwandt(x, c);
      }
      await partner(b, c);
      await verwandt(e, d);
      await verwandt(k, a);
      // Viele Nachkommen für den Platzmangel im Lebensbaum: 12 Kinder mit
      // je 14 Kindern von Person E.
      final ids = <String>[];
      for (var i = 0; i < 12; i++) {
        ids.add(await person('Nachkomme $i'));
      }
      for (final kid in ids) {
        await verwandt(kid, e);
      }
      for (var i = 0; i < 12; i++) {
        for (var j = 0; j < 14; j++) {
          final en = await person('Enkel $i-$j');
          await verwandt(en, ids[i]);
        }
      }
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    Finder segment(String text) => find.descendant(
      of: find.byWidgetPredicate((w) => w is SegmentedButton),
      matching: find.text(text),
    );
    // PER-139
    final ansichten = <String, Finder>{
      de.stammbaumAnsichtFaecher: find.byType(FaecherAnsicht),
      de.stammbaumAnsichtSanduhr: find.byType(SanduhrAnsicht),
      de.stammbaumAnsichtNachfahren: find.text('Kind'),
      de.stammbaumAnsichtListe: find.textContaining('verwandt'),
      de.stammbaumAnsichtZeitleiste: find.byType(FamilienZeitleiste),
      de.stammbaumAnsichtLebensbaum: find.byType(LebensbaumAnsicht),
      de.stammbaumAnsichtBaum: find.byType(ZierbaumAnsicht),
    };
    for (final e in ansichten.entries) {
      await klick(tester, segment(e.key));
      await waitFor(tester, e.value);
    }
    await tester.binding.setSurfaceSize(const Size(480, 900));
    await warte(tester, 800);
    expect(tester.takeException(), isNull, reason: 'kein Überlauf');
    final leiste = find.ancestor(
      of: find.byWidgetPredicate((w) => w is SegmentedButton),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.widget<SingleChildScrollView>(leiste.first).scrollDirection,
      Axis.horizontal,
    );
    final hoehen = {
      for (final t in ansichten.keys) tester.getSize(segment(t)).height.round(),
    };
    expect(hoehen, hasLength(1), reason: 'keine umbrochenen Beschriftungen');
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await warte(tester, 500);
    // PER-147
    await klick(tester, segment(de.stammbaumAnsichtSanduhr));
    Finder inSanduhr(String n) => find.descendant(
      of: find.byType(SanduhrAnsicht),
      matching: find.text(n),
    );
    await waitFor(tester, inSanduhr('Person B'));
    expect(inSanduhr('Person C'), findsOneWidget);
    expect(inSanduhr('Kind'), findsOneWidget);
    expect(inSanduhr('Person D'), findsOneWidget);
    expect(inSanduhr('Person E'), findsOneWidget);
    await klick(
      tester,
      find.widgetWithText(FilterChip, de.stammbaumSeitenlinien),
    );
    await waitGone(tester, inSanduhr('Person D'));
    expect(inSanduhr('Person E'), findsNothing);
    expect(inSanduhr('Person B'), findsOneWidget);
    await klick(
      tester,
      find.widgetWithText(FilterChip, de.stammbaumSeitenlinien),
    );
    await waitFor(tester, inSanduhr('Person D'));
    // PER-155
    await klick(tester, segment(de.stammbaumAnsichtLebensbaum));
    await waitFor(tester, find.byTooltip(de.lebensbaumPortraitsAus));
    await klick(tester, find.byTooltip(de.lebensbaumPortraitsAus));
    await waitFor(tester, find.byTooltip(de.lebensbaumPortraitsAn));
    await klick(tester, find.byTooltip(de.lebensbaumPortraitsAn));
    await waitFor(tester, find.byTooltip(de.lebensbaumPortraitsAus));
    // PER-158
    final d = _genauerDialog();
    final ordner = Directory(p.join(anker.path, 'ausgabe'))..createSync();
    d.ziel = p.join(ordner.path, 'lebensbaum.pdf');
    melde.verlaufLeeren();
    await klick(tester, find.byTooltip(de.lebensbaumDrucken));
    await erwarteText(
      tester,
      de.stammbaumTafelFertig,
      timeout: const Duration(seconds: 60),
    );
    expect(d.namen, contains('stammbaum-lebensbaum.pdf'));
    final pdf = File(d.ziel!).readAsBytesSync();
    expect(latin1.decode(pdf.take(5).toList()), '%PDF-');
    // Platzmangel: Nachkommen von Person E.
    await mitte(tester, 'Person E');
    await klick(
      tester,
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is SegmentedButton<dynamic> || w is SegmentedButton,
        ),
        matching: find.text(de.lebensbaumNachkommen),
      ),
    );
    await waitFor(
      tester,
      find.textContaining('weitere Personen haben im Bild keinen Platz mehr'),
    );
    // Ohne Vorfahren ist das Drucker-Symbol ausgegraut.
    await mitte(tester, 'Person B');
    await klick(
      tester,
      find
          .descendant(
            of: find.byWidgetPredicate((w) => w is SegmentedButton),
            matching: find.text(de.lebensbaumVorfahren),
          )
          .last,
    );
    await warte(tester, 500);
    expect(symbolknopf(tester, de.lebensbaumDrucken).onPressed, isNull);
    print('PER-139 a=$a');
    await finish(tester);
  });

  // Behoben in #412: Die Zeitleiste rückt über denselben Weg wie die
  // anderen Ansichten; der Zurück-Pfeil führt zur vorigen Mitte.
  pruefung('PER-151 Zeitleiste und Zurück-Pfeil', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      final a = await person('Person A', geburt: DateTime(1960));
      final b = await person('Person B', geburt: DateTime(1935));
      await verwandt(a, b);
    });
    await personenOeffnen(tester);
    await klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await klick(
      tester,
      find.descendant(
        of: find.byType(PersonDetailScreen),
        matching: find.byTooltip(de.stammbaumTitel),
      ),
    );
    await waitFor(tester, find.text(de.stammbaumTitelVon('Person A')));
    await klick(
      tester,
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SegmentedButton),
        matching: find.text(de.stammbaumAnsichtZeitleiste),
      ),
    );
    await waitFor(tester, find.byType(FamilienZeitleiste));
    await klick(
      tester,
      find.descendant(
        of: find.byType(FamilienZeitleiste),
        matching: find.text('Person B'),
      ),
    );
    await waitFor(tester, find.text(de.stammbaumTitelVon('Person B')));
    await zurueck(tester);
    expect(
      find.byType(StammbaumScreen),
      findsOneWidget,
      reason: 'bleibt im Stammbaum',
    );
    expect(find.text(de.stammbaumTitelVon('Person A')), findsOneWidget);
    await finish(tester);
  });

  pruefung('PER-143 Baum: zu viele Haushalte', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      final a = await person('Person A');
      final b = await person('Person B');
      final c = await person('Person C');
      final g = await person('Person G');
      await verwandt(a, b);
      await verwandt(a, c);
      await partner(b, c);
      await verwandt(b, g);
      for (var i = 0; i < 45; i++) {
        final o = await person('Onkel $i');
        final pa = await person('Partner $i');
        await verwandt(o, g);
        await partner(o, pa);
      }
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await klick(tester, find.byKey(const ValueKey('baumKreis')));
    await klick(tester, find.text(de.stammbaumKreisCousinsZweitenGrades).last);
    await waitFor(
      tester,
      find.textContaining(
        RegExp(
          r'weitere Haushalte passen nicht ins Bild|weiterer Haushalt passt nicht ins Bild',
        ),
      ),
    );
    await finish(tester);
  });

  pruefung('PER-156 PER-157 PER-159 PER-162 Ausgaben', (tester) async {
    await start(tester);
    // Ohne Personen ist „Als GEDCOM ausgeben …“ ausgegraut.
    await stammbaumOeffnen(tester);
    await klick(
      tester,
      find.descendant(
        of: find.byType(StammbaumScreen),
        matching: find.byTooltip(de.allgMehr),
      ),
    );
    final gedcomEintrag = find.ancestor(
      of: find.text(de.stammbaumGedcomExport),
      matching: find.byType(PopupMenuItem<String>),
    );
    await waitFor(tester, gedcomEintrag);
    expect(
      tester.widget<PopupMenuItem<String>>(gedcomEintrag.first).enabled,
      isFalse,
    );
    await taste(tester, LogicalKeyboardKey.escape);
    await tester.runAsync(() async {
      final a = await person(
        'Person A',
        geburt: DateTime(1960, 2, 3),
        geschlecht: Geschlecht.weiblich,
      );
      final b = await person(
        'Person B',
        geburt: DateTime(1930, 4, 5),
        tod: DateTime(2001, 6, 7),
        geschlecht: Geschlecht.maennlich,
      );
      final k = await person('Kind', geburt: DateTime(1990, 8, 9));
      await verwandt(a, b);
      await verwandt(k, a);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    final d = _genauerDialog();
    final ordner = Directory(p.join(anker.path, 'ausgabe'))..createSync();
    // PER-156: Name ohne Endung.
    d.ziel = p.join(ordner.path, 'tafel');
    melde.verlaufLeeren();
    await stammbaumMehr(tester, de.stammbaumTafelDrucken);
    await erwarteText(
      tester,
      de.stammbaumTafelFertig,
      timeout: const Duration(seconds: 60),
    );
    expect(d.namen.last, 'stammbaum-tafel.pdf');
    final tafel = File(p.join(ordner.path, 'tafel.pdf'));
    expect(tafel.existsSync(), isTrue);
    expect(File(p.join(ordner.path, 'tafel')).existsSync(), isFalse);
    final inhalt = latin1.decode(tafel.readAsBytesSync());
    expect(inhalt, startsWith('%PDF-'));
    final seiten = RegExp(r'/Type\s*/Page[^s]').allMatches(inhalt).length;
    final box = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)',
    ).firstMatch(inhalt);
    print('PER-156 Seiten: $seiten, MediaBox: ${box?.group(0)}');
    // Stehen die Seitenobjekte unkomprimiert in der Datei, werden sie
    // geprüft; in Objektströmen sind sie ohne PDF-Leser nicht lesbar.
    if (seiten > 0) {
      expect(seiten, 1);
      expect(box, isNotNull);
      final bw = double.parse(box!.group(1)!);
      final bh = double.parse(box.group(2)!);
      expect(bw, closeTo(1190.55, 2), reason: 'A3 quer');
      expect(bh, closeTo(841.89, 2));
    }
    // PER-157
    d.ziel = p.join(ordner.path, 'zierbaum.pdf');
    melde.verlaufLeeren();
    await stammbaumMehr(tester, de.stammbaumZierbaumDrucken);
    await erwarteText(
      tester,
      de.stammbaumTafelFertig,
      timeout: const Duration(seconds: 60),
    );
    expect(d.namen.last, 'stammbaum-zierbaum.pdf');
    expect(
      latin1.decode(File(d.ziel!).readAsBytesSync().take(5).toList()),
      '%PDF-',
    );
    // PER-159: abbrechen.
    d.ziel = null;
    melde.verlaufLeeren();
    final dateienVorher = ordner.listSync().length;
    await stammbaumMehr(tester, de.stammbaumTafelDrucken);
    await warte(tester, 1500);
    expect(melde.verlauf, isEmpty, reason: 'keine Meldung');
    expect(ordner.listSync().length, dateienVorher);
    // PER-162
    d.ziel = p.join(ordner.path, 'familie.ged');
    await stammbaumMehr(tester, de.stammbaumGedcomExport);
    await erwarteText(tester, de.stammbaumGedcomFertig(3));
    expect(d.namen.last, 'stammbaum.ged');
    final roh = File(d.ziel!).readAsBytesSync();
    final text = utf8.decode(roh);
    expect(text, startsWith('0 HEAD'));
    expect(text.trimRight(), endsWith('0 TRLR'));
    expect(text, contains('\r\n'));
    expect(RegExp(r'^1 NAME ', multiLine: true).allMatches(text), hasLength(3));
    expect(text, contains('1 SEX F'));
    expect(text, contains('1 SEX M'));
    expect(text, contains('1 BIRT'));
    expect(text, contains('1 DEAT'));
    expect(text, contains('FAM'));
    await finish(tester);
  });

  // Behoben in #412: GEDCOM, Tafel, Zierbaum und Lebensbaum fangen einen
  // Schreibfehler ab und melden ihn verständlich.
  pruefung('PER-160 Ziel nicht beschreibbar', (tester) async {
    await start(tester);
    await tester.runAsync(() => person('Person A'));
    await stammbaumOeffnen(tester);
    final d = _genauerDialog();
    d.platzhalter = false;
    // Ein „Ordner“, der eine Datei ist: Schreiben darunter scheitert.
    final keinOrdner = File(p.join(anker.path, 'keinordner'))
      ..writeAsStringSync('x');
    d.ziel = p.join(keinOrdner.path, 'familie.ged');
    melde.verlaufLeeren();
    await stammbaumMehr(tester, de.stammbaumGedcomExport);
    await warte(tester, 1500);
    final ausnahme = tester.takeException();
    print(
      'PER-160 Ausnahme: $ausnahme; Meldungen: ${melde.verlauf.map((m) => '${m.art}: ${m.text}').toList()}',
    );
    expect(ausnahme, isNull, reason: 'die App fängt den Schreibfehler ab');
    expect(
      melde.verlauf.where((m) => m.art == Meldungsart.fehler),
      isNotEmpty,
      reason: 'verständliche Fehlermeldung',
    );
    await finish(tester);
  });

  pruefung('PER-168 Große GEDCOM-Datei', (tester) async {
    await start(tester);
    await stammbaumOeffnen(tester);
    final zeilen = <String>[];
    for (var f = 0; f < 1000; f++) {
      final m = 'I${f * 3 + 1}', w = 'I${f * 3 + 2}', k = 'I${f * 3 + 3}';
      zeilen
        ..addAll([
          '0 @$m@ INDI',
          '1 NAME Person /M$f/',
          '1 SEX M',
          '1 FAMS @F$f@',
        ])
        ..addAll([
          '0 @$w@ INDI',
          '1 NAME Person /W$f/',
          '1 SEX F',
          '1 FAMS @F$f@',
        ])
        ..addAll([
          '0 @$k@ INDI',
          '1 NAME Kind /K$f/',
          '1 BIRT',
          '2 DATE ${1900 + f % 100}',
          '1 FAMC @F$f@',
        ])
        ..addAll(['0 @F$f@ FAM', '1 HUSB @$m@', '1 WIFE @$w@', '1 CHIL @$k@']);
    }
    final uhr = Stopwatch()..start();
    final datei = File(p.join(eingang.path, 'gross.ged'))
      ..writeAsStringSync(gedcom(zeilen));
    dialog.dateien = [datei];
    await stammbaumMehr(tester, de.stammbaumGedcomImport);
    await waitFor(
      tester,
      find.text(de.gedcomImportTitel),
      timeout: const Duration(seconds: 60),
    );
    await klick(tester, find.text(de.gedcomImportUebernehmen));
    await waitFor(
      tester,
      find.text(de.gedcomImportFertig(3000)),
      timeout: const Duration(seconds: 180),
    );
    uhr.stop();
    print('PER-168 Einlesen von 3000 Personen: ${uhr.elapsedMilliseconds} ms');
    expect(uhr.elapsed, lessThan(const Duration(seconds: 120)));
    await klick(tester, imDialog(find.text(de.allgSchliessen)));
    await warte(tester, 500);
    expect((await allePersonen(tester)).length, 3000);
    // Die App bleibt bedienbar.
    await klick(
      tester,
      find.descendant(
        of: find.byWidgetPredicate((w) => w is SegmentedButton),
        matching: find.text(de.stammbaumAnsichtListe),
      ),
    );
    await waitFor(tester, find.textContaining('verwandt'));
    await finish(tester);
  });

  pruefung('PER-169 PER-170 PER-171 PER-173 PER-174 Lebenslauf und Orte', (
    tester,
  ) async {
    await start(tester);
    // PER-170 … PER-174 ohne Ortsverzeichnis.
    await tester.runAsync(() async {
      final a = await person('Person A', geburt: DateTime(1950, 1, 2));
      await verwandt(await person('Kind'), a);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Kind');
    // PER-170
    await schildMenue(tester, 'Kind');
    await klick(tester, find.text(de.stammbaumLebenslauf));
    await waitFor(tester, find.text(de.lebenslaufVon('Kind')));
    expect(find.text(de.lebenslaufLeer), findsOneWidget);
    await zurueck(tester);
    // PER-171
    await mitte(tester, 'Person A');
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebenslauf));
    await waitFor(tester, find.byType(LebenslaufScreen));
    await klick(tester, find.byTooltip(de.lebenslaufHinzufuegen));
    await waitFor(tester, imDialog(find.text(de.lebenslaufHinzufuegen)));
    await klick(tester, imDialog(find.text(de.allgAbbrechen)));
    await warte(tester, 300);
    expect(
      find.text(de.lebenslaufUmzug),
      findsNothing,
      reason: 'Abbrechen legt nichts an',
    );
    await klick(tester, find.byTooltip(de.lebenslaufHinzufuegen));
    await klick(
      tester,
      imDialog(find.byWidgetPredicate((w) => w is DropdownButton)).first,
    );
    await warte(tester, 300);
    for (final art in [
      de.lebenslaufHochzeit,
      de.lebenslaufUmzug,
      de.lebenslaufBeruf,
      de.lebenslaufAusbildung,
      de.lebenslaufSonstiges,
    ]) {
      expect(find.text(art), findsWidgets, reason: art);
    }
    await klick(tester, find.text(de.lebenslaufUmzug).last);
    await klick(tester, imDialog(find.text(de.lebenslaufOhneDatum)));
    await datumEingeben(tester, DateTime(2001, 3, 15));
    await enter(tester, imDialog(field(de.lebenslaufOrt)), 'Prüfstadt');
    await enter(tester, imDialog(field(de.lebenslaufNotiz)), 'Notiz eins');
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await waitFor(tester, find.text(de.lebenslaufUmzug));
    expect(find.text('Prüfstadt · Notiz eins'), findsOneWidget);
    expect(find.text('15.3.2001'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    // PER-174: Ort setzen und entfernen (ohne Ortsverzeichnis).
    await klick(tester, find.byTooltip(de.lebenslaufOrtAufKarte));
    await waitFor(tester, imDialog(find.text(de.lebenslaufOrtOhneVerzeichnis)));
    await tester.tap(imDialog(find.byType(FlutterMap)));
    await waitGone(
      tester,
      find.byType(AlertDialog),
      timeout: const Duration(seconds: 10),
    );
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(LebenslaufScreen),
        matching: find.byIcon(Icons.place),
      ),
    );
    await klick(tester, find.byTooltip(de.lebenslaufOrtAufKarte));
    await klick(tester, imDialog(find.text(de.lebenslaufOrtEntfernen)));
    await waitFor(tester, find.byIcon(Icons.wrong_location_outlined));
    expect(
      find.text('Prüfstadt · Notiz eins'),
      findsOneWidget,
      reason: 'Name bleibt',
    );
    // PER-173
    final geburtZeile = find.ancestor(
      of: find.text(de.lebenslaufGeburt),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: geburtZeile,
        matching: find.byTooltip(de.allgLoeschen),
      ),
      findsNothing,
    );
    await klick(tester, find.byTooltip(de.allgLoeschen));
    await waitGone(tester, find.text(de.lebenslaufUmzug));
    await zurueck(tester);
    // PER-169: Ortsverzeichnis, GEDCOM mit Geburts- und Sterbeort.
    await ortsverzeichnisEinrichten(tester);
    expect(bibliothek.geoDataAvailable, isTrue);
    await gedcomEinlesen(
      tester,
      gedcom([
        '0 @I1@ INDI',
        '1 NAME Person /F/',
        '1 SEX F',
        '1 BIRT',
        '2 DATE 1 JAN 1950',
        '2 PLAC Prüfstadt',
        '1 DEAT',
        '2 DATE 2 FEB 2010',
        '2 PLAC Nirgendwohausen',
      ]),
    );
    final pf = await personNamens(tester, 'Person F');
    final ereignisse = await dbx(
      tester,
      () => (bibliothek.db.select(
        bibliothek.db.lebensereignisse,
      )..where((t) => t.personId.equals(pf.id))).get(),
    );
    final bekannt = ereignisse.firstWhere((e) => e.ort == 'Prüfstadt');
    final unbekannt = ereignisse.firstWhere((e) => e.ort == 'Nirgendwohausen');
    expect(bekannt.ortBreite, closeTo(47.25, 0.01));
    expect(unbekannt.ortBreite, isNull, reason: 'bleibt als Text');
    final foto = await fotos(tester, [
      testfoto(
        'lo1.jpg',
        datum: DateTime(2020),
        breitengrad: 47.3,
        laengengrad: 9.8,
      ),
    ]);
    await tester.runAsync(() => gesicht(foto['lo1.jpg']!.id, person: pf.id));
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person F');
    await stammbaumMehr(tester, de.stammbaumFamilienorte);
    await waitFor(tester, find.byType(FamilienorteScreen));
    await waitFor(tester, find.text('${de.orteEreignisse} (1)'));
    expect(find.byTooltip('Person F · Prüfstadt'), findsOneWidget);
    await finish(tester);
  });

  // Behoben in #412: Ein neuer Lebenslauf-Ort wird gleich beim Anlegen
  // verortet (LibraryState.verorteEreignis).
  pruefung('PER-175 Neuer Ort wird sofort verortet', (tester) async {
    await start(tester);
    await ortsverzeichnisEinrichten(tester);
    await tester.runAsync(
      () async => verwandt(await person('Person A'), await person('Person B')),
    );
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await schildMenue(tester, 'Person A');
    await klick(tester, find.text(de.stammbaumLebenslauf));
    await klick(tester, find.byTooltip(de.lebenslaufHinzufuegen));
    await klick(
      tester,
      imDialog(find.byWidgetPredicate((w) => w is DropdownButton)).first,
    );
    await klick(tester, find.text(de.lebenslaufUmzug).last);
    await enter(tester, imDialog(field(de.lebenslaufOrt)), 'Prüfstadt');
    await klick(tester, imDialog(find.text(de.allgSpeichern)));
    await waitFor(tester, find.text(de.lebenslaufUmzug));
    await warte(tester, 1500);
    await klick(tester, find.byTooltip(de.lebenslaufOrtAufKarte));
    await waitFor(tester, find.byType(AlertDialog));
    final text = sichtbar(imDialog(find.text(de.lebenslaufOrtUnbekannt)))
        ? 'unbekannt'
        : sichtbar(imDialog(find.text(de.lebenslaufOrtErkannt)))
        ? 'erkannt'
        : '?';
    print('PER-175 Dialog: $text');
    expect(imDialog(find.text(de.lebenslaufOrtErkannt)), findsOneWidget);
    await finish(tester);
  });

  // =========================================================================
  // Fotos und Orte der Familie
  // =========================================================================

  pruefung('PER-177 PER-178 PER-179 PER-180 Fotos der Familie', (tester) async {
    await start(tester);
    late String a, k, b, c;
    await tester.runAsync(() async {
      a = await person('Person A');
      k = await person('Kind');
      b = await person('Person B');
      c = await person('Person C');
      await verwandt(k, a);
      await partner(a, c);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    // PER-178
    await stammbaumMehr(tester, de.stammbaumFamilienfotos);
    await erwarteText(tester, de.stammbaumKeineFamilienfotos);
    expect(find.byType(FamilienfotosScreen), findsNothing);
    final f = await fotos(tester, [
      testfoto('ff1.jpg', datum: DateTime(2020, 1, 1)),
      testfoto('ff2.jpg', datum: DateTime(2021, 1, 1)),
      testfoto('ff3.jpg', datum: DateTime(2022, 1, 1)),
      testfoto('ff4.jpg', datum: DateTime(2023, 1, 1)),
      testfoto('ff5.jpg', datum: DateTime(2024, 1, 1)),
      testfoto('ff6.jpg', datum: DateTime(2019, 1, 1)),
      testfoto('ff7.jpg', datum: DateTime(2018, 1, 1)),
    ]);
    String id(int i) => f['ff$i.jpg']!.id;
    await tester.runAsync(() async {
      await gesicht(id(1), person: a);
      await gesicht(id(2), person: k);
      await gesicht(id(3), person: a);
      await gesicht(id(3), person: k, x: 0.6);
      await gesicht(id(4), person: b);
      await gesicht(id(5), person: c);
      await gesicht(id(6), person: k);
      await gesicht(id(7), person: k);
    });
    // PER-177
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await stammbaumMehr(tester, de.stammbaumFamilienfotos);
    await waitFor(tester, find.byType(FamilienfotosScreen));
    expect(find.text(de.stammbaumFamilienfotosVon('Person A')), findsOneWidget);
    List<String> reihe() => [
      for (final t in tester.widgetList<AssetThumbnailTile>(
        find.descendant(
          of: find.byType(FamilienfotosScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
      ))
        t.asset.id,
    ];
    await waitFor(tester, find.byType(AssetThumbnailTile));
    expect(reihe(), [id(5), id(3), id(2), id(1), id(6), id(7)]);
    await zurueck(tester);
    // PER-179
    await tester.runAsync(() async {
      await bibliothek.setupVaultPin(_testPin);
      await bibliothek.lockAsset(f['ff6.jpg']!);
      await bibliothek.db.fuehreAus(InDenPapierkorb([id(7)]));
    });
    await stammbaumMehr(tester, de.stammbaumFamilienfotos);
    await waitFor(tester, find.byType(FamilienfotosScreen));
    await waitFor(tester, find.byType(AssetThumbnailTile));
    expect(reihe(), [id(5), id(3), id(2), id(1)]);
    // PER-180
    await klick(tester, find.byType(AssetThumbnailTile).at(1));
    await waitFor(tester, find.byType(AssetViewerScreen));
    final viewer = tester.widget<AssetViewerScreen>(
      find.byType(AssetViewerScreen),
    );
    expect([for (final x in viewer.assets) x.id], [id(5), id(3), id(2), id(1)]);
    await klick(tester, find.byTooltip(de.viewerInPapierkorb));
    await klick(tester, imDialog(find.text(de.allgLoeschen)));
    await waitGone(tester, find.byType(AssetViewerScreen));
    expect((await assetZeile(tester, id(3))).isTrashed, isTrue);
    await finish(tester);
  });

  pruefung('PER-181 PER-182 PER-183 PER-185 Orte der Familie', (tester) async {
    await start(tester);
    late String a, b, k;
    await tester.runAsync(() async {
      a = await person('Person A');
      b = await person('Person B');
      k = await person('Kind');
      await verwandt(a, b);
      await verwandt(k, a);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    // PER-185
    await stammbaumMehr(tester, de.stammbaumFamilienorte);
    await erwarteText(tester, de.stammbaumKeineFamilienorte);
    expect(find.byType(FamilienorteScreen), findsNothing);
    final f = await fotos(tester, [
      testfoto(
        'or1.jpg',
        datum: DateTime(2020),
        breitengrad: 47.0,
        laengengrad: 9.0,
      ),
      testfoto(
        'or2.jpg',
        datum: DateTime(2021),
        breitengrad: 47.0,
        laengengrad: 9.0,
      ),
      testfoto(
        'or3.jpg',
        datum: DateTime(2022),
        breitengrad: 51.5,
        laengengrad: 12.5,
      ),
      testfoto(
        'or4.jpg',
        datum: DateTime(2023),
        breitengrad: 45.0,
        laengengrad: 7.0,
      ),
    ]);
    await tester.runAsync(() async {
      await gesicht(f['or1.jpg']!.id, person: a);
      await gesicht(f['or2.jpg']!.id, person: a);
      await gesicht(f['or3.jpg']!.id, person: b);
      await gesicht(f['or4.jpg']!.id, person: k);
      await ereignis(a, 'umzug', ort: 'Prüfstadt', breite: 48.5, laenge: 10.5);
    });
    // PER-181
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await stammbaumMehr(tester, de.stammbaumFamilienorte);
    await waitFor(tester, find.byType(FamilienorteScreen));
    expect(find.text(de.stammbaumFamilienorteVon('Person A')), findsOneWidget);
    expect(find.text('${de.orteIch} (2)'), findsOneWidget);
    expect(find.text('${de.orteVorfahren} (1)'), findsOneWidget);
    expect(find.text('${de.orteNachkommen} (1)'), findsOneWidget);
    expect(find.textContaining(de.orteSeitenlinie), findsNothing);
    expect(find.textContaining(de.orteAngeheiratet), findsNothing);
    final marken = find.byWidgetPredicate(_istOrtsmarke);
    await waitFor(tester, marken);
    expect(marken, findsNWidgets(3));
    // PER-183
    expect(find.text('${de.orteEreignisse} (1)'), findsOneWidget);
    final raute = find.byWidgetPredicate(_istRaute);
    expect(raute, findsOneWidget);
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(location: Offset.zero);
    await maus.moveTo(tester.getCenter(raute));
    await warte(tester, 1500);
    expect(find.text('Person A · Prüfstadt'), findsOneWidget);
    await maus.moveTo(Offset.zero);
    await maus.removePointer();
    await warte(tester, 500);
    await klick(tester, find.text('${de.orteEreignisse} (1)'));
    expect(raute, findsNothing);
    // PER-181: Marke mit Zahl öffnet ihre Fotos.
    await klick(tester, find.descendant(of: marken, matching: find.text('2')));
    await waitFor(tester, find.byType(AssetViewerScreen));
    expect(
      tester
          .widget<AssetViewerScreen>(find.byType(AssetViewerScreen))
          .assets
          .length,
      2,
    );
    await zurueck(tester);
    await waitGone(tester, find.byType(AssetViewerScreen));
    // PER-182
    await klick(tester, find.text('${de.orteVorfahren} (1)'));
    await warte(tester, 300);
    expect(marken, findsNWidgets(2));
    await klick(tester, find.text('${de.orteIch} (2)'));
    await klick(tester, find.text('${de.orteNachkommen} (1)'));
    await waitFor(tester, find.text(de.orteNichtsGewaehlt));
    await finish(tester);
  });

  // Behoben in #412: „Orte der Familie“ zeigt die Karte auch, wenn nur
  // Ereignisse einen Ort haben.
  pruefung('PER-184 Orte der Familie nur mit Ereignissen', (tester) async {
    await start(tester);
    await tester.runAsync(() async {
      final a = await person('Person A');
      await ereignis(a, 'umzug', ort: 'Prüfstadt', breite: 47.25, laenge: 9.75);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await stammbaumMehr(tester, de.stammbaumFamilienorte);
    await waitFor(tester, find.byType(FamilienorteScreen));
    await warte(tester, 800);
    final keineGruppe = sichtbar(find.text(de.orteNichtsGewaehlt));
    print('PER-184 „Keine Gruppe ausgewählt.“ sichtbar: $keineGruppe');
    expect(find.byWidgetPredicate(_istRaute), findsOneWidget);
    expect(find.text(de.orteNichtsGewaehlt), findsNothing);
    await finish(tester);
  });

  pruefung(
    'PER-187 Familienauswertungen ohne gesperrte, gelöschte, ignorierte',
    (tester) async {
      await start(tester);
      final f = await fotos(tester, [
        testfoto(
          'fa1.jpg',
          datum: DateTime(2020),
          breitengrad: 47.0,
          laengengrad: 9.0,
        ),
        testfoto(
          'fa2.jpg',
          datum: DateTime(2021),
          breitengrad: 48.0,
          laengengrad: 10.0,
        ),
        testfoto(
          'fa3.jpg',
          datum: DateTime(2022),
          breitengrad: 46.0,
          laengengrad: 8.0,
        ),
        testfoto(
          'fa4.jpg',
          datum: DateTime(2023),
          breitengrad: 46.5,
          laengengrad: 8.5,
        ),
      ]);
      String id(int i) => f['fa$i.jpg']!.id;
      await tester.runAsync(() async {
        final a = await person('Person A');
        final b = await person('Person B');
        await verwandt(a, b);
        for (final i in [1, 2]) {
          await gesicht(id(i), person: a);
          await gesicht(id(i), person: b, x: 0.6);
        }
        for (final i in [3, 4]) {
          await gesicht(id(i), person: a);
          await gesicht(id(i), x: 0.6, ignoriert: true, vektor: richtung(3));
        }
        await bibliothek.setupVaultPin(_testPin);
        await bibliothek.lockAsset(f['fa1.jpg']!);
        await bibliothek.db.fuehreAus(InDenPapierkorb([id(2)]));
      });
      await stammbaumOeffnen(tester);
      await mitte(tester, 'Person A');
      await stammbaumMehr(tester, de.stammbaumFamilienorte);
      await waitFor(tester, find.byType(FamilienorteScreen));
      expect(find.text('${de.orteIch} (2)'), findsOneWidget);
      expect(find.textContaining(de.orteVorfahren), findsNothing);
      await zurueck(tester);
      await stammbaumMehr(tester, de.stammbaumFamilienstatistik);
      await waitFor(tester, find.byType(FamilienstatistikScreen));
      final aufnahmen = find.ancestor(
        of: find.text(de.famstatAufnahmenGesamt),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(of: aufnahmen.first, matching: find.text('2')),
        findsOneWidget,
        reason: 'nur die zwei offenen Fotos',
      );
      await zurueck(tester);
      await personenOeffnen(tester);
      await klick(tester, find.byTooltip(de.soziogrammTitel));
      await waitFor(tester, find.text(de.soziogrammLeer));
      await finish(tester);
    },
  );

  pruefung('PER-188 PER-189 Familienstatistik', (tester) async {
    await start(tester);
    final f = await fotos(tester, [
      for (var j = 2019; j <= 2024; j++)
        testfoto('st$j.jpg', datum: DateTime(j, 5, 1)),
    ]);
    await tester.runAsync(() async {
      final a = await person('Person A', geburt: DateTime(1960));
      final k = await person('Kind', geburt: DateTime(1990));
      final b = await person('Person B', geburt: DateTime(1930));
      await verwandt(a, b);
      await verwandt(k, a);
      for (var j = 2019; j <= 2024; j++) {
        await gesicht(f['st$j.jpg']!.id, person: a);
      }
      // Ein Familienfoto mit beiden zählt einmal.
      await gesicht(f['st2024.jpg']!.id, person: k, x: 0.6);
    });
    await stammbaumOeffnen(tester);
    await mitte(tester, 'Person A');
    await stammbaumMehr(tester, de.stammbaumFamilienstatistik);
    await waitFor(tester, find.byType(FamilienstatistikScreen));
    // PER-188
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.stammbaumFamilienstatistik),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Person A')),
      findsOneWidget,
    );
    await waitFor(tester, find.text(de.famstatAufFotos));
    final oben = tester.getTopLeft(find.text(de.famstatAufFotos)).dy;
    // Die Liste baut faul: Steht die zweite Überschrift noch nicht da,
    // liegt sie weiter unten.
    if (sichtbar(find.text(de.famstatAusLebensdaten))) {
      expect(
        tester.getTopLeft(find.text(de.famstatAusLebensdaten)).dy,
        greaterThan(oben),
      );
    }
    // PER-189
    expect(find.text(de.famstatAufnahmenGesamt), findsOneWidget);
    expect(find.text(de.famstatImBild), findsWidgets);
    expect(find.text(de.famstatZeitraum), findsOneWidget);
    expect(find.text(de.famstatVonBis('2019', '2024')), findsOneWidget);
    expect(find.text(de.famstatInJahren(6)), findsOneWidget);
    final aufnahmen = find.ancestor(
      of: find.text(de.famstatAufnahmenGesamt),
      matching: find.byType(Column),
    );
    expect(
      find.descendant(of: aufnahmen.first, matching: find.text('6')),
      findsOneWidget,
      reason: 'Familienfoto einmal',
    );
    expect(find.text(de.famstatOhneBild(1)), findsOneWidget);
    expect(find.text(de.famstatAufnahmenJeJahr), findsOneWidget);
    await finish(tester);
  });

  pruefung('PER-202 Familientage: Geburtstagsfotos zuerst', (tester) async {
    await start(tester);
    final heute = DateTime.now();
    final f = await fotos(tester, [
      for (var i = 0; i < 4; i++)
        testfoto(
          'gb23_$i.jpg',
          datum: DateTime(2023, heute.month, heute.day, 10 + i),
        ),
      testfoto('gb22.jpg', datum: DateTime(2022, heute.month, heute.day, 12)),
      testfoto('gb21.jpg', datum: DateTime(2021, heute.month, heute.day, 12)),
      testfoto(
        'so25.jpg',
        datum: DateTime(heute.year - 1, heute.month == 1 ? 6 : 1, 5),
      ),
      testfoto(
        'so24.jpg',
        datum: DateTime(heute.year - 2, heute.month == 3 ? 7 : 3, 9),
      ),
    ]);
    await tester.runAsync(() async {
      final a = await person(
        'Person A',
        geburt: DateTime(1990, heute.month, heute.day),
      );
      for (final x in f.values) {
        await gesicht(x.id, person: a);
      }
      await bibliothek.setupVaultPin(_testPin);
      await bibliothek.lockAsset(f['gb21.jpg']!);
    });
    await openSection(tester, Hauptbereich.alben);
    await openSection(tester, Hauptbereich.rueckblick);
    final abschnitt = find.byType(FamilientageAbschnitt);
    await waitFor(tester, abschnitt, timeout: const Duration(seconds: 30));
    final kachelnTage = find.descendant(
      of: abschnitt,
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, kachelnTage);
    final namenNachId = {for (final x in f.values) x.id: x.originalFileName};
    final reihe = [
      for (final t in tester.widgetList<AssetThumbnailTile>(kachelnTage))
        namenNachId[t.asset.id] ?? t.asset.id,
    ];
    print('PER-202 Reihe: $reihe');
    expect(reihe, isNot(contains('gb21.jpg')), reason: 'gesperrt');
    expect(reihe.take(4).every((n) => n.startsWith('gb')), isTrue);
    expect(reihe.where((n) => n.startsWith('gb23')), hasLength(3));
    expect(reihe.indexOf('gb22.jpg'), lessThan(4));
    // Neuere Fotos ohne Geburtstag folgen nicht: Gibt es Geburtstagsfotos,
    // zeigt der Abschnitt nur diese (rueckblickseite.dart:113–115).
    expect(reihe, hasLength(4));
    await finish(tester);
  });
}

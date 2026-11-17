// ignore_for_file: avoid_print
// Zusätzliche Hilfen der zweiten Prüfrunde (r2-mob) für die Handy-App.
// Gemeinsam mit katalog_hilfen.dart; die Steuerung ist
// pruefkatalog/arbeit/r2-mob/mob_steuer_r2.py (gleiche Ports wie in der
// ersten Runde, dazu simctl, SQL auf den Wegwerf-Datenbanken und Konten
// mit TOTP-Einrichtung).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'katalog_hilfen.dart';

/// Der Ordner des Prüfkatalogs auf dem Mac (im Simulator lesbar), über
/// `--dart-define=PV_KATALOG=<Ordner>`.
const katalog = String.fromEnvironment('PV_KATALOG');

/// Eigene Testdateien der zweiten Runde (Videos, HEIC, Schild).
const r2Fix = String.fromEnvironment(
  'PV_FIXTURES_R2',
  defaultValue: '$katalog/arbeit/r2-mob/fixtures',
);

/// Testbilder mit echtem Inhalt (Porträts, Tiere …).
const mlFix = String.fromEnvironment(
  'PV_FIXTURES_ML',
  defaultValue: '$katalog/fixtures-ml',
);

/// Der Datenordner eines Wegwerf-Servers.
String serverDaten(String name) => '$katalog/server-daten/$name/daten';

/// Die Bibliothek eines Kontos auf dem Wegwerf-Server [name].
String bibliotheksDb(String name, String kontoId) =>
    '${serverDaten(name)}/bibliotheken/$kontoId/library.sqlite';

/// SQL auf einer Datenbank eines eigenen Wegwerf-Servers (über die
/// Steuerung auf dem Mac).
Future<List<List<Object?>>> sql(
  String db,
  String befehl, [
  List<Object?> args = const [],
]) async {
  final r = await steuer('sql', {'db': db, 'sql': befehl, 'args': args});
  if (r['zeilen'] == null) throw StateError('SQL: $r');
  return [for (final z in r['zeilen']! as List) (z as List).cast<Object?>()];
}

/// `xcrun simctl <args>` für den eigenen Simulator.
Future<Map<String, Object?>> simctl(List<String> args) =>
    steuer('simctl', {'args': args});

/// Ein Bildschirmfoto des Simulators nach `arbeit/r2-mob/shots/<name>`.
Future<void> bildschirmfoto(String name) => simctl(['io', name]);

/// Die Kennung des Kontos von [v].
Future<String> eigeneKontoId(Serververbindung v) async =>
    '${(await v.hole('api/v1/konto'))['id']}';

/// Stösst die Auswertung an und wartet, bis sie 2,5 s lang ruht.
Future<void> auswerten(Serververbindung v, {Duration? max}) async {
  await v.schicke('api/v1/auswertung', const <String, Object?>{});
  DateTime? ruhig;
  final ende = DateTime.now().add(max ?? const Duration(minutes: 12));
  while (DateTime.now().isBefore(ende)) {
    final a = await v.hole('api/v1/auswertung');
    if (a['laeuft'] == true) {
      ruhig = null;
    } else {
      ruhig ??= DateTime.now();
      if (DateTime.now().difference(ruhig) >
          const Duration(milliseconds: 2500)) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  throw StateError('Auswertung nicht fertig');
}

/// Ein Befehl wie aus der Weboberfläche.
Future<void> befehl(
  Serververbindung v,
  String art,
  Map<String, Object?> werte,
) => v.schicke('api/v1/befehle', {'art': art, 'werte': werte});

// --------------------------------------------------------------------------
// photo_manager teilweise nachstellen

const _pmKanal = 'com.fluttercandies/photo_manager';
const _codec = StandardMethodCodec();

/// Ersetzt einzelne Methoden von photo_manager (z. B. die Systemrückfrage
/// beim Löschen); alle anderen gehen an die echte Mediathek.
class PhotoManagerAttrappe {
  PhotoManagerAttrappe();

  /// Methode → Antwort (ein Wert oder eine Funktion der Argumente).
  final antworten = <String, Object? Function(Object? args)>{};
  final aufrufe = <MethodCall>[];

  void an() {
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    bote.setMockMessageHandler(_pmKanal, (m) async {
      final c = _codec.decodeMethodCall(m);
      final f = antworten[c.method];
      if (f != null) {
        aufrufe.add(c);
        return _codec.encodeSuccessEnvelope(f(c.arguments));
      }
      return bote.delegate.send(_pmKanal, m);
    });
  }

  void aus() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(_pmKanal, null);
  }

  /// Die Systemrückfrage beim Löschen: bestätigt (alle ids) oder abgelehnt.
  void loeschenAntwort({required bool bestaetigt}) {
    antworten['deleteWithIds'] = (a) => bestaetigt
        ? ((a! as Map)['ids'] as List).cast<String>()
        : const <String>[];
  }

  List<List<String>> get geloescht => [
    for (final c in aufrufe)
      if (c.method == 'deleteWithIds')
        ((c.arguments! as Map)['ids'] as List).cast<String>(),
  ];
}

// --------------------------------------------------------------------------
// Mediathek und Sicherung

var _nr = 0;

/// Legt [n] neue Testfotos in die Mediathek des Simulators (heutiges
/// Datum, damit sie oben in der Zeitleiste stehen).
Future<List<AssetEntity>> inMediathek(
  int n, {
  String praefix = 'r2',
  DateTime? datum,
}) async {
  final l = <AssetEntity>[];
  for (var i = 0; i < n; i++) {
    _nr++;
    l.add(
      await PhotoManager.editor.saveImage(
        jpeg(
          breite: 400,
          hoehe: 300,
          farbe: 0x405060 + _nr * 7919 + DateTime.now().millisecond,
        ),
        filename:
            '${praefix}_${DateTime.now().millisecondsSinceEpoch}_$_nr.jpg',
        creationDate: datum ?? DateTime.now().subtract(Duration(minutes: _nr)),
      ),
    );
  }
  return l;
}

Future<int> mediathekAnzahl() => PhotoManager.getAssetCount();

/// Wie viele Aufnahmen (ohne Papierkorb) [konto] auf [server] hat.
Future<int> serverAnzahl(String konto, {Uri? server}) => mitRechner(
  server ?? hauptDirekt,
  konto,
  (r) async =>
      (await r.db
              .customSelect(
                'SELECT count(*) AS n FROM assets WHERE is_trashed = 0',
              )
              .getSingle())
          .read<int>('n'),
);

Future<void> sicherungsseite(WidgetTester tester) async {
  await kontoOeffnen(tester);
  await rolleZu(tester, find.text(de.sicherungTitel));
  await tippe(tester, find.text(de.sicherungTitel), ms: 1200);
  await warte(tester, find.text(de.sicherungAn));
}

Future<void> schalter(WidgetTester tester, String titel, bool an) async {
  final z = find.widgetWithText(SwitchListTile, titel);
  await rolleZu(tester, z);
  if (tester.widget<SwitchListTile>(z).value != an) {
    await tippe(tester, z, ms: 1200);
  }
}

Finder aktion(String text) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'Auswahlleiste',
  ),
  matching: find.text(text),
);

/// Die Kachel der Aufnahme [id] im Raster.
Finder kachelVon(String id) => find.byWidgetPredicate(
  (w) =>
      w.runtimeType.toString() == 'Miniatur' &&
      ((w as dynamic).zeile?.id as String?) == id,
);

/// Doppeltipp mit echter Pause, sonst Aufziehen mit zwei Fingern.
Future<void> zoome(WidgetTester tester, {bool aufziehen = false}) async {
  final m = tester.getCenter(find.byType(PageView));
  if (!aufziehen) {
    await tester.tapAt(m);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await tester.tapAt(m);
    await ruhe(tester, 2500);
    return;
  }
  final a1 = await tester.startGesture(m - const Offset(30, 0), pointer: 71);
  final a2 = await tester.startGesture(m + const Offset(30, 0), pointer: 72);
  for (var i = 0; i < 12; i++) {
    await a1.moveBy(const Offset(-12, 0));
    await a2.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await a1.up();
  await a2.up();
  await ruhe(tester, 2500);
}

/// Wartet, bis die Proxy-Liste eine Anfrage mit [teil] enthält.
Future<List<String>> proxyPfade([String name = proxyName]) async => [
  for (final e in await proxyLog(name)) '${e['methode']} ${e['pfad']}',
];

/// Datei als Bytes vom Mac (im Simulator lesbar).
Future<List<int>> macDatei(String pfad) => File(pfad).readAsBytes();

String basis(String pfad) => p.basename(pfad);

/// Zeit, die wirklich vergeht (pumpend).
Future<void> warteEcht(WidgetTester tester, Duration d) =>
    ruhe(tester, d.inMilliseconds);

/// Fährt die Tastatur ein und wartet, bis die Seite wieder steht (ein Blatt
/// mit offener Tastatur zu schliessen bringt im Simulator negative
/// viewInsets).
Future<void> tastaturWeg(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await ruhe(tester, 1200);
}

/// Setzt den Text eines Felds ohne die Bildschirmtastatur (die im
/// Simulator beim Schliessen eines Blatts negative viewInsets meldet und
/// den Widgetbaum für alle folgenden Prüfungen beschädigt).
Future<void> schreibeLeise(WidgetTester tester, Finder f, String text) async {
  await warte(tester, f);
  FocusManager.instance.primaryFocus?.unfocus();
  await ruhe(tester, 900);
  final feld = tester.widget<TextField>(f.first);
  final e = tester.widget<EditableText>(
    find.descendant(of: f.first, matching: find.byType(EditableText)),
  );
  e.controller.text = text;
  feld.onChanged?.call(text);
  await ruhe(tester, 400);
}

/// Rollt die sichtbare Liste von oben bis unten durch und sammelt dabei alle
/// Texte (eine ListView baut nur, was gerade zu sehen ist).
Future<Set<String>> texteBeimRollen(WidgetTester tester) async {
  final gesehen = <String>{...sichtbareTexte(tester)};
  final f = find.byType(Scrollable).hitTestable();
  if (f.evaluate().isEmpty) return gesehen;
  final s = tester.state<ScrollableState>(f.first);
  s.position.jumpTo(0);
  await ruhe(tester, 400);
  for (var i = 0; i < 40; i++) {
    gesehen.addAll(sichtbareTexte(tester));
    final p = s.position;
    if (p.pixels >= p.maxScrollExtent) break;
    p.jumpTo((p.pixels + 250).clamp(0, p.maxScrollExtent));
    await ruhe(tester, 300);
  }
  gesehen.addAll(sichtbareTexte(tester));
  return gesehen;
}

/// Sammelt die Texte aller Meldungen unten, bis [bis] erscheint oder [max]
/// vergeht.
Future<List<String>> meldungenBis(
  WidgetTester tester,
  String bis, {
  Duration max = const Duration(seconds: 90),
}) async {
  final gesehen = <String>[];
  final ende = DateTime.now().add(max);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 150));
    for (final t in tester.widgetList<Text>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
    )) {
      final s = t.data ?? '';
      if (s.isNotEmpty && (gesehen.isEmpty || gesehen.last != s)) {
        gesehen.add(s);
      }
    }
    if (gesehen.contains(bis)) break;
  }
  return gesehen;
}

/// Öffnet die Aufnahme [id] im Betrachter (hebt eine Auswahl vorher auf).
Future<void> oeffneId(WidgetTester tester, String id) async {
  for (var versuch = 0; versuch < 3; versuch++) {
    final aufheben = tooltip(de.auswahlAufheben);
    if (aufheben.evaluate().isNotEmpty) await tippe(tester, aufheben);
    await warte(tester, kachelVon(id));
    await tester.ensureVisible(kachelVon(id));
    await ruhe(tester, 400);
    await tippe(tester, kachelVon(id), ms: 1500);
    final ende = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(ende)) {
      if (tooltip(de.betrachterAngaben).evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 150));
    }
  }
  await warte(tester, tooltip(de.betrachterAngaben));
}

/// Rollt die sichtbare Liste in Schritten, bis [f] gebaut ist, und holt es
/// dann ins Bild (rolleZu fand in langen Seiten manchmal keine Fläche).
Future<void> rolleBis(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final s = tester.state<ScrollableState>(
      find.byType(Scrollable).hitTestable().first,
    );
    s.position.jumpTo(0);
    await ruhe(tester, 300);
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      final p = s.position;
      if (p.pixels >= p.maxScrollExtent) break;
      p.jumpTo((p.pixels + 200).clamp(0, p.maxScrollExtent));
      await ruhe(tester, 250);
    }
  }
  await warte(tester, f);
  await tester.ensureVisible(f.first);
  await ruhe(tester, 400);
}

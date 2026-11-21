// ignore_for_file: avoid_print
// Katalog-Prüfungen SIC-001 bis SIC-093 (Sicherung, Wiederherstellung,
// KI-Restaurierung-Warteschlange, zweite Bibliothek) in der echten
// macOS-App. Läuft nur über die Warteschlange des Prüfkatalogs.
//
// Sicherungsziele und Quellordner liegen unter `anker` (Temp-Ordner der
// Prüfung). Der Ordnerdialog von Hand kommt über `dialog.ordner`; die
// Ordnerwahl mit Merkmal (automatisches Backup, zweite Bibliothek) geht
// unter macOS über den Kanal `photo_vault/library_location` und wird hier
// mit [Ordnerkanal] nachgestellt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/screens/einstellungen/backup_stand.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/screens/second_library_compare_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/groessentext.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:provider/provider.dart';

import 'katalog_kit.dart';

const _p1 = 'erste-passphrase-1';
const _p2 = 'zweite-passphrase-2';

// --- Ordner und Dateien -------------------------------------------------------

/// Ein Ordner unter dem Temp-Ordner der Prüfung (neben der Bibliothek).
Directory ordner(String name) =>
    Directory(p.join(anker.path, 'pruef', name))..createSync(recursive: true);

String _sha(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Was in [d] liegt: relativer Pfad → Grösse, Prüfsumme, Änderungszeit.
Map<String, String> inhaltVon(Directory d) => {
  for (final f in d.listSync(recursive: true).whereType<File>())
    p.relative(f.path, from: d.path):
        '${f.lengthSync()}|${_sha(f)}|'
        '${f.lastModifiedSync().millisecondsSinceEpoch}',
};

void kopiere(Directory von, Directory nach) {
  for (final e in von.listSync(recursive: true)) {
    final ziel = p.join(nach.path, p.relative(e.path, from: von.path));
    if (e is Directory) {
      Directory(ziel).createSync(recursive: true);
    } else if (e is File) {
      Directory(p.dirname(ziel)).createSync(recursive: true);
      e.copySync(ziel);
    }
  }
}

/// Dreht ein Byte in der Mitte von [f] um.
void beschaedige(File f) {
  final raf = f.openSync(mode: FileMode.append);
  final mitte = raf.lengthSync() ~/ 2;
  raf.setPositionSync(mitte);
  final b = raf.readByteSync();
  raf.setPositionSync(mitte);
  raf.writeByteSync(b ^ 0xff);
  raf.closeSync();
}

/// Ein JPEG mit [mib] MiB angehängter Füllung hinter dem Bildende – gross
/// genug für Mengengrenze und Prüfbudget, trotzdem ein lesbares Foto.
File grossesFoto(String name, int mib, {required DateTime datum}) {
  final f = testfoto(name, datum: datum, breite: 400, hoehe: 300);
  final raf = f.openSync(mode: FileMode.append);
  final block = Uint8List(1 << 20);
  for (var i = 0; i < mib; i++) {
    block[i % block.length] = i & 0xff;
    raf.writeFromSync(block);
  }
  raf.closeSync();
  return f;
}

/// Ein Foto mit klar erkennbarem Inhalt (für den CLIP-Vergleich).
File musterfoto(
  String name,
  String art, {
  DateTime? datum,
  int breite = 640,
  int hoehe = 480,
}) {
  final bild = img.Image(width: breite, height: hoehe);
  final zufall = math.Random(name.hashCode);
  switch (art) {
    case 'schach':
      final k = breite ~/ 8;
      for (var y = 0; y < hoehe; y += k) {
        for (var x = 0; x < breite; x += k) {
          final weiss = ((x ~/ k) + (y ~/ k)).isEven;
          img.fillRect(
            bild,
            x1: x,
            y1: y,
            x2: x + k - 1,
            y2: y + k - 1,
            color: weiss
                ? img.ColorRgb8(250, 250, 250)
                : img.ColorRgb8(0, 0, 0),
          );
        }
      }
    case 'kreis':
      img.fill(bild, color: img.ColorRgb8(255, 255, 255));
      img.fillCircle(
        bild,
        x: breite ~/ 2,
        y: hoehe ~/ 2,
        radius: hoehe ~/ 3,
        color: img.ColorRgb8(220, 20, 20),
      );
    case 'kreis_variante':
      img.fill(bild, color: img.ColorRgb8(255, 250, 225));
      img.fillCircle(
        bild,
        x: (breite * 0.6).round(),
        y: (hoehe * 0.55).round(),
        radius: (hoehe / 3.6).round(),
        color: img.ColorRgb8(200, 30, 30),
      );
    case 'rauschen':
      for (var y = 0; y < hoehe; y++) {
        for (var x = 0; x < breite; x++) {
          final g = zufall.nextInt(256);
          bild.setPixelRgb(x, y, g, g, g);
        }
      }
    case 'streifen':
      const farben = [
        [230, 0, 0],
        [255, 140, 0],
        [255, 230, 0],
        [0, 170, 0],
        [0, 90, 255],
        [90, 0, 160],
      ];
      final b = breite ~/ farben.length + 1;
      for (var i = 0; i < farben.length; i++) {
        img.fillRect(
          bild,
          x1: i * b,
          y1: 0,
          x2: math.min(breite - 1, (i + 1) * b),
          y2: hoehe - 1,
          color: img.ColorRgb8(farben[i][0], farben[i][1], farben[i][2]),
        );
      }
    case 'text':
      img.fill(bild, color: img.ColorRgb8(255, 255, 255));
      for (var z = 0; z < 14; z++) {
        img.drawString(
          bild,
          'LOREM IPSUM DOLOR SIT AMET $z',
          font: img.arial24,
          x: 20,
          y: 15 + z * 32,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    case 'landschaft':
      for (var y = 0; y < hoehe; y++) {
        final himmel = y < hoehe * 0.6;
        final c = himmel
            ? img.ColorRgb8(70 + y ~/ 4, 140 + y ~/ 6, 255)
            : img.ColorRgb8(40, 150 - (y - hoehe * 0.6).round() ~/ 3, 40);
        img.drawLine(bild, x1: 0, y1: y, x2: breite - 1, y2: y, color: c);
      }
      img.fillCircle(
        bild,
        x: (breite * 0.75).round(),
        y: (hoehe * 0.2).round(),
        radius: hoehe ~/ 10,
        color: img.ColorRgb8(255, 230, 40),
      );
    default:
      throw ArgumentError(art);
  }
  if (datum != null) {
    String z(int v, int s) => v.toString().padLeft(s, '0');
    final text =
        '${z(datum.year, 4)}:${z(datum.month, 2)}:${z(datum.day, 2)} '
        '${z(datum.hour, 2)}:${z(datum.minute, 2)}:${z(datum.second, 2)}';
    bild.exif.exifIfd['DateTimeOriginal'] = text;
    bild.exif.imageIfd['DateTime'] = text;
  }
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(bild, quality: 92));
  return datei;
}

// --- Bibliothek ---------------------------------------------------------------

Future<List<AssetData>> aufnahmen(WidgetTester tester) async {
  final alle = await tester.runAsync(
    () => bibliothek.db.select(bibliothek.db.assets).get(),
  );
  return [
    for (final a in alle!)
      if (!a.isTrashed) a,
  ]..sort((a, b) => a.originalFileName.compareTo(b.originalFileName));
}

Future<int> zahl(WidgetTester tester, String tabelle) async {
  final z = await tester.runAsync(
    () => bibliothek.db
        .customSelect('SELECT count(*) AS n FROM $tabelle')
        .getSingle(),
  );
  return z!.read<int>('n');
}

/// Löscht [weg] endgültig (Papierkorb, dann leeren).
Future<void> endgueltigWeg(WidgetTester tester, List<AssetData> weg) async {
  await tester.runAsync(() async {
    await bibliothek.db.fuehreAus(InDenPapierkorb([for (final a in weg) a.id]));
    await bibliothek.endgueltigLoeschen(weg);
  });
  await settle(tester);
}

/// Macht die Bibliothek leer: Aufnahmen, Personen, Gesichter, Reisen,
/// Alben – wie eine frisch angelegte.
Future<void> leeren(WidgetTester tester) async {
  await tester.runAsync(() async {
    final db = bibliothek.db;
    for (final t in [
      'faces',
      'people',
      'reise_aufnahmen',
      'reisen',
      'album_assets',
      'albums',
    ]) {
      await db.customStatement('DELETE FROM $t');
    }
  });
  final alle = await aufnahmen(tester);
  if (alle.isNotEmpty) await endgueltigWeg(tester, alle);
  expect(await aufnahmen(tester), isEmpty);
}

/// Neustart der App mit derselben Bibliothek: Datenbank schliessen, Baum
/// leeren, App neu aufbauen. Die Umlenkung aus [startApp] bleibt dabei
/// bestehen – der Datenordner ist weiter der Temp-Ordner der Prüfung.
Future<void> neustart(WidgetTester tester) async {
  await hintergrundAnhalten(tester);
  await bibliothek.vorDemBeenden();
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
  if (!bibliothek.paths.root.path.startsWith(anker.path)) {
    throw StateError(
      'Bibliothek liegt nicht im Temp-Ordner: ${bibliothek.paths.root.path}',
    );
  }
  await settle(tester);
}

// --- Start und Ende -----------------------------------------------------------

/// [startApp] aus dem Kit, danach den Meldungsverlauf leeren (der
/// Meldungsdienst ist ein Einzelstück und überdauert die Prüfungen).
Future<void> starteApp(
  WidgetTester tester, {
  String sprache = 'de',
  Object modelle = false,
}) async {
  await startApp(tester, sprache: sprache, modelle: modelle);
  melde.verlaufLeeren();
}

Future<void> fertig(WidgetTester tester) async {
  await settle(tester);
  await finish(tester);
}

/// Hält die Hintergrundarbeit an, bevor die Bibliothek geschlossen wird
/// (wie das Kit in finish).
Future<void> hintergrundAnhalten(WidgetTester tester) async {
  if (bibliothek.analyseLaeuft) bibliothek.brichHintergrundanalyseAb();
  await eventually(
    tester,
    () async => !bibliothek.etwasLaeuft,
    timeout: const Duration(seconds: 30),
  );
  await settle(tester);
}

// --- Ordnerwahl mit Merkmal (macOS-Kanal) -------------------------------------

/// Stellt den nativen Ordnerdialog mit Merkmal nach (siehe
/// SecurityScopedBookmark). Das Merkmal trägt den Pfad, damit ein Neustart
/// es wieder auflösen kann.
class Ordnerkanal {
  Ordnerkanal(WidgetTester tester) {
    final bote = tester.binding.defaultBinaryMessenger;
    bote.setMockMethodCallHandler(_kanal, _antwort);
    addTearDown(() => bote.setMockMethodCallHandler(_kanal, null));
  }

  static const _kanal = MethodChannel('photo_vault/library_location');

  /// Was der Dialog zurückgibt (`null` = abgebrochen).
  String? ordner;
  final gerufen = <String>[];

  Future<Object?> _antwort(MethodCall call) async {
    gerufen.add(call.method);
    switch (call.method) {
      case 'pickFolderAndCreateBookmark':
        final o = ordner;
        return o == null ? null : {'path': o, 'bookmark': 'pv-test:$o'};
      case 'resolveBookmark':
        final m = (call.arguments as Map)['bookmark'] as String;
        return m.startsWith('pv-test:') ? m.substring(8) : null;
    }
    throw MissingPluginException();
  }
}

// --- Oberfläche ---------------------------------------------------------------

Finder imDialog(Finder f) =>
    find.descendant(of: find.byType(AlertDialog), matching: f);

Finder textPasst(RegExp re) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && re.hasMatch(w.data!),
);

/// Ein übersetzter Satz mit Platzhaltern als regulärer Ausdruck: [satz]
/// wird mit `\u0001` als Platzhalter erzeugt, jeder Platzhalter passt auf
/// beliebigen Text.
RegExp satzMuster(String satz) => RegExp(
  '^${satz.split('\u0001').map(RegExp.escape).join('.+?')}\$',
  dotAll: true,
);

/// Scrollt [ziel] in [liste] ins Bild (auch nach oben).
Future<void> zeigeIn(WidgetTester tester, Finder ziel, Finder liste) async {
  if (ziel.evaluate().isEmpty) {
    tester.state<ScrollableState>(liste).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      ziel,
      250,
      scrollable: liste,
      maxScrolls: 200,
    );
  }
  await tester.ensureVisible(ziel.first);
  await settle(tester);
}

Future<void> einstellungen(WidgetTester tester) async {
  if (find.byType(SettingsScreen).evaluate().isNotEmpty) return;
  await openSection(tester, Hauptbereich.einstellungen);
  await waitFor(tester, find.byType(SettingsScreen));
}

/// Schliesst die Einstellungen und öffnet sie neu (frischer Stand).
Future<void> einstellungenNeu(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.zeitleiste);
  await waitGone(tester, find.byType(SettingsScreen));
  await einstellungen(tester);
}

Finder get _einstellungsliste => find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Klappt die Gruppe [titel] auf, falls ihr Inhalt [inhalt] noch fehlt.
///
/// Erst den Kopf ins Bild holen: Die Liste baut nur, was zu sehen ist. Eine
/// aufgeklappte Gruppe weit oben ist dann gar nicht gebaut – ein Tippen auf
/// ihren Kopf klappte sie wieder zu.
/// Welche Gruppe hinter einem von [gruppe] gelieferten Finder steckt – damit
/// [tippeIn] sie wieder ins Bild holen kann. Die Liste baut weggescrollte
/// Gruppen ab, und ob eine Gruppe danach wieder offen erscheint, ist nicht
/// verlässlich.
final _gruppen = <Finder, (String, Type)>{};

Future<Finder> gruppe(WidgetTester tester, String titel, Type inhalt) async {
  await einstellungen(tester);
  final kasten = find.byType(inhalt);
  _gruppen[kasten] = (titel, inhalt);
  final kopf = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(titel),
  );
  await zeigeIn(tester, kopf, _einstellungsliste);
  if (kasten.evaluate().isEmpty) {
    await tester.tap(kopf.first);
    await settle(tester);
    await waitFor(tester, kasten);
  }
  return kasten;
}

Future<Finder> schluesselGruppe(WidgetTester tester, [AppTexte? t]) => gruppe(
  tester,
  (t ?? de).einstBackupVerschluesselungTitel,
  SicherungsschluesselGruppe,
);
Future<Finder> handGruppe(WidgetTester tester, [AppTexte? t]) => gruppe(
  tester,
  (t ?? de).einstAbschnittManuellesBackup,
  SicherungVonHandGruppe,
);
Future<Finder> autoGruppe(WidgetTester tester, [AppTexte? t]) => gruppe(
  tester,
  (t ?? de).einstAbschnittAutoBackup,
  AutomatischeSicherungGruppe,
);

/// Tippt [f] an, ohne danach zu warten, bis nichts mehr ansteht: Ein
/// Fortschrittsfenster dreht seinen Balken endlos, [settle] liefe also,
/// bis der Lauf vorbei ist, und man sähe nur noch das Ende.
Future<void> starte(WidgetTester tester, Finder f) async {
  await waitFor(tester, f);
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> tippeIn(WidgetTester tester, Finder bereich, String text) async {
  final ziel = find.descendant(of: bereich, matching: find.text(text));
  final g = _gruppen[bereich];
  if (ziel.evaluate().isEmpty && g != null) {
    await gruppe(tester, g.$1, g.$2);
  }
  await starte(tester, ziel);
}

/// Der Knopf (FilledButton, OutlinedButton …) um den Text [text].
ButtonStyleButton knopf(WidgetTester tester, Finder bereich, String text) =>
    tester.widget<ButtonStyleButton>(
      find
          .ancestor(
            of: find.descendant(of: bereich, matching: find.text(text)),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .first,
    );

Finder dropdownBei(Finder bereich, String titel) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(of: bereich, matching: find.text(titel)),
        matching: find.byType(ListTile),
      )
      .first,
  matching: find.byType(DropdownButton<int>),
);

Future<void> passphraseEingeben(
  WidgetTester tester,
  String text, [
  AppTexte? t,
]) async {
  final s = t ?? de;
  await waitFor(tester, find.text(s.einstBackupPassphraseEingeben));
  await enter(tester, field(s.passphraseFeld), text);
  await starte(tester, imDialog(find.text('OK')));
  final ende = DateTime.now().add(const Duration(seconds: 60));
  while (find.text(s.einstBackupPassphraseEingeben).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException('Passphrase-Dialog bleibt offen');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> passphraseFestlegen(WidgetTester tester, String text) async {
  await waitFor(tester, find.text(de.passphraseFestlegenTitel));
  await enter(tester, field(de.passphraseNeuFeld), text);
  await enter(tester, field(de.passphraseWiederholen), text);
  await tap(tester, imDialog(find.text(de.allgFestlegen)));
  await waitGone(
    tester,
    find.text(de.passphraseFestlegenTitel),
    timeout: const Duration(seconds: 60),
  );
}

/// Was ein Fortschrittsfenster gezeigt hat.
class Lauf {
  Lauf(
    this.gesehen,
    this.ende, {
    required this.erfolg,
    required this.fehler,
    required this.balken,
    required this.abbrechen,
  });

  /// Alle Zeilen, die während des Laufs dastanden, in ihrer Reihenfolge.
  final List<String> gesehen;

  /// Die letzte Zeile.
  final String ende;

  /// Grüner Haken bzw. rotes Fehlersymbol am Ende.
  final bool erfolg, fehler;

  /// Ob während des Laufs ein Balken bzw. ein Abbrechen-Knopf zu sehen war.
  final bool balken, abbrechen;

  @override
  String toString() =>
      'Lauf(erfolg: $erfolg, fehler: $fehler, balken: $balken, '
      'abbrechen: $abbrechen, ende: „$ende“, '
      'gesehen: ${gesehen.length > 12 ? [...gesehen.take(6), '…', ...gesehen.skip(gesehen.length - 6)] : gesehen})';
}

Finder fenster(String titel) =>
    find.ancestor(of: find.text(titel), matching: find.byType(AlertDialog));

/// Wartet, bis das Fortschrittsfenster [titel] fertig ist, und sammelt
/// dabei alles, was darin stand.
Future<Lauf> laufAbwarten(
  WidgetTester tester,
  String titel, {
  AppTexte? t,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final s = t ?? de;
  final f = fenster(titel);
  final bis = DateTime.now().add(const Duration(seconds: 90));
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(bis)) {
      throw TimeoutException(
        'Fenster „$titel“ erscheint nicht\nAuf dem Bildschirm: ${onScreen(tester)}',
      );
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  final schliessen = find.descendant(
    of: f,
    matching: find.text(s.allgSchliessen),
  );
  final gesehen = <String>[];
  var balken = false, abbrechen = false;
  List<String> zeilen() => [
    for (final e
        in find.descendant(of: f, matching: find.byType(Text)).evaluate())
      if ((e.widget as Text).data case final d?)
        if (d != titel && d != s.allgSchliessen) d,
  ];
  final ende = DateTime.now().add(timeout);
  while (true) {
    for (final z in zeilen()) {
      if (!gesehen.contains(z)) gesehen.add(z);
    }
    if (find
        .descendant(of: f, matching: find.byType(LinearProgressIndicator))
        .evaluate()
        .isNotEmpty) {
      balken = true;
    }
    if (find
        .descendant(of: f, matching: find.text(s.allgAbbrechen))
        .evaluate()
        .isNotEmpty) {
      abbrechen = true;
    }
    if (schliessen.evaluate().isNotEmpty) break;
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException('Lauf „$titel“ endet nicht: $gesehen');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  final letzte = zeilen();
  final lauf = Lauf(
    gesehen,
    letzte.isEmpty ? '' : letzte.last,
    erfolg: find
        .descendant(of: f, matching: find.byIcon(Icons.check_circle))
        .evaluate()
        .isNotEmpty,
    fehler: find
        .descendant(of: f, matching: find.byIcon(Icons.error_outline))
        .evaluate()
        .isNotEmpty,
    balken: balken,
    abbrechen: abbrechen,
  );
  print('Lauf „$titel“: $lauf');
  return lauf;
}

Future<void> schliesseLauf(
  WidgetTester tester,
  String titel, [
  AppTexte? t,
]) async {
  await tap(
    tester,
    find.descendant(
      of: fenster(titel),
      matching: find.text((t ?? de).allgSchliessen),
    ),
  );
  await waitGone(tester, fenster(titel));
}

/// Schliesst die oberste Seite: über den Zurück- oder Schliessen-Knopf der
/// Leiste, sonst wie die Zurück-Taste des Systems (maybePop, mit allen
/// Rückfragen der Seite).
Future<void> seiteZurueck(WidgetTester tester) async {
  for (final knopf in [find.byType(BackButton), find.byType(CloseButton)]) {
    if (knopf.evaluate().isNotEmpty) {
      await tester.tap(knopf.last);
      await settle(tester);
      return;
    }
  }
  await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
  await settle(tester);
}

String heute() => DateFormat.yMd('de').format(DateTime.now());
String datumZeit(DateTime d) =>
    '${DateFormat.yMd('de').format(d)} – ${DateFormat.Hm('de').format(d)}';

bool gemeldet(String text, [Meldungsart? art]) =>
    melde.verlauf.any((m) => m.text == text && (art == null || m.art == art));

Future<void> sprache(WidgetTester tester, String code) async {
  await tester.runAsync(() => bibliothek.db.setSprache(code));
  await settle(tester);
}

Future<void> chmod(String modus, String pfad) async {
  final r = await Process.run('/bin/chmod', [modus, pfad]);
  if (r.exitCode != 0) throw StateError('chmod: ${r.stderr}');
}

double kosinus(Float32List a, Float32List b) {
  var s = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return s / (math.sqrt(na) * math.sqrt(nb));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Passphrase und Einstellungen ohne Lauf
  // =========================================================================
  testWidgets('SIC-001 SIC-003 SIC-004 SIC-008 SIC-012 SIC-013 SIC-030 SIC-031 '
      'SIC-032 SIC-053 Passphrase einrichten, Hinweise, Ziel und Intervall', (
    tester,
  ) async {
    await starteApp(tester);
    await importiereDirekt(tester, [
      testfoto('a.jpg', datum: DateTime(2023, 3, 1, 10)),
      testfoto('b.jpg', datum: DateTime(2023, 3, 2, 10)),
    ]);
    final kanal = Ordnerkanal(tester);
    melde.verlaufLeeren();

    // SIC-004, SIC-003, SIC-001
    final schluessel = await schluesselGruppe(tester);
    expect(
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstPassphraseEinrichten),
      ),
      findsOneWidget,
    );
    await tippeIn(tester, schluessel, de.allgEinrichten);
    await waitFor(tester, find.text(de.passphraseFestlegenTitel));
    expect(find.text(de.passphraseWarnung), findsOneWidget);
    expect(
      de.passphraseWarnung,
      startsWith(
        'Wichtig: Backups werden echt verschlüsselt (AES-256). Ohne diese '
        'Passphrase gibt es KEINE Möglichkeit, sie wiederherzustellen',
      ),
    );

    await enter(tester, field(de.passphraseNeuFeld), 'abcdefghij');
    await enter(tester, field(de.passphraseWiederholen), 'abcdefghik');
    await tap(tester, imDialog(find.text(de.allgFestlegen)));
    await waitFor(tester, find.text(de.passphraseUngleich));
    final fehler = find.text(de.passphraseUngleich);
    expect(
      tester.widget<Text>(fehler).style?.color,
      Theme.of(tester.element(fehler)).colorScheme.error,
    );
    expect(find.text(de.passphraseFestlegenTitel), findsOneWidget);
    expect(await tester.runAsync(() => bibliothek.db.hasBackupKey()), isFalse);

    await enter(tester, field(de.passphraseNeuFeld), _p1);
    await enter(tester, field(de.passphraseWiederholen), _p1);
    await tap(tester, imDialog(find.text(de.allgFestlegen)));
    await waitGone(
      tester,
      find.text(de.passphraseFestlegenTitel),
      timeout: const Duration(seconds: 60),
    );
    await waitFor(
      tester,
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupEntsperrt),
      ),
    );
    for (final text in [
      de.einstBackupPassphrase,
      de.einstBackupAendern,
      de.allgEntfernen,
    ]) {
      expect(
        find.descendant(of: schluessel, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    expect(await tester.runAsync(() => bibliothek.db.hasBackupKey()), isTrue);
    expect(bibliothek.backupKeyAvailableThisSession, isTrue);

    // SIC-008
    await tippeIn(tester, schluessel, de.allgEntfernen);
    await waitFor(tester, find.text(de.einstBackupEntschluesselnTitel));
    expect(find.text(de.einstBackupEntschluesselnText), findsOneWidget);
    expect(
      de.einstBackupEntschluesselnText,
      contains('Bereits bestehende verschlüsselte Backups am Zielort bleiben'),
    );
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.einstBackupEntschluesselnTitel));
    expect(await tester.runAsync(() => bibliothek.db.hasBackupKey()), isTrue);
    expect(
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupEntsperrt),
      ),
      findsOneWidget,
    );

    // SIC-012
    final hand = await handGruppe(tester);
    expect(
      find.descendant(
        of: hand,
        matching: find.text(de.einstBackupManuellHinweis),
      ),
      findsOneWidget,
    );
    expect(
      de.einstBackupManuellHinweis,
      startsWith(
        'Eine Sicherung mit Passphrase nimmt zusätzlich einen '
        'verschlüsselten Schnappschuss der Datenbank mit',
      ),
    );
    expect(
      de.einstBackupManuellHinweis,
      contains('Ohne Passphrase enthält die Sicherung nur die Originale'),
    );

    // SIC-013
    dialog.ordner = null;
    dialog.gerufen.clear();
    await tippeIn(tester, hand, de.einstJetztSichern);
    await settle(tester, max: const Duration(seconds: 2));
    expect(
      dialog.gerufen.where((g) => g.startsWith('getDirectoryPath')),
      hasLength(1),
    );
    expect(find.text(de.einstBackupSichertLaeuft), findsNothing);
    expect(
      find.descendant(
        of: hand,
        matching: find.text(de.einstBackupNieGesichert),
      ),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(() => bibliothek.db.lastBackupRecord()),
      isNull,
    );

    // SIC-030
    final auto = await autoGruppe(tester);
    final schalter = find.descendant(
      of: auto,
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(schalter).onChanged, isNull);
    expect(
      find.descendant(of: auto, matching: find.text(de.einstBackupZuerstZiel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: auto, matching: find.text(de.einstBackupKeinOrdner)),
      findsOneWidget,
    );
    expect(knopf(tester, auto, de.einstJetztSynchronisieren).enabled, isFalse);

    // SIC-031, SIC-053
    final ziel = ordner('ziel_auto');
    kanal.ordner = ziel.path;
    await tippeIn(tester, auto, de.einstWaehlen);
    await waitFor(
      tester,
      find.descendant(of: auto, matching: find.text(ziel.path)),
    );
    expect(kanal.gerufen, contains('pickFolderAndCreateBookmark'));
    expect(
      find.descendant(of: auto, matching: find.text(ziel.path)),
      findsNWidgets(2),
    );
    await waitFor(
      tester,
      find.descendant(of: auto, matching: find.text(de.backupProbeNochNie)),
    );
    expect(tester.widget<SwitchListTile>(schalter).onChanged, isNotNull);
    await tap(tester, schalter);
    await eventually(
      tester,
      () async =>
          (await bibliothek.db.backupSettingsRow())?.autoBackupEnabled == true,
    );
    await einstellungenNeu(tester);
    final auto2 = await autoGruppe(tester);
    await waitFor(
      tester,
      find.descendant(
        of: auto2,
        matching: find.byWidgetPredicate((w) => w is SwitchListTile && w.value),
      ),
    );
    expect(
      find.descendant(of: auto2, matching: find.text(ziel.path)),
      findsNWidgets(2),
    );

    // SIC-032
    final intervall = dropdownBei(auto2, de.einstIntervall);
    expect(tester.widget<DropdownButton<int>>(intervall).value, 24);
    expect(
      find.descendant(of: intervall, matching: find.text(de.einstTaeglich)),
      findsOneWidget,
    );
    for (final (text, stunden) in [
      (de.einstStuendlich, 1),
      (de.einstIntervallSechsStunden, 6),
      (de.einstTaeglich, 24),
      (de.einstWoechentlich, 168),
    ]) {
      await tap(tester, intervall);
      await tap(tester, find.text(text).last);
      await eventually(
        tester,
        () async =>
            (await bibliothek.db.backupSettingsRow())
                ?.autoBackupIntervalHours ==
            stunden,
        was: 'Intervall $stunden',
      );
      await waitFor(
        tester,
        find.descendant(of: intervall, matching: find.text(text)),
      );
      expect(tester.widget<DropdownButton<int>>(intervall).value, stunden);
    }
    await fertig(tester);
  });

  // =========================================================================
  // Gesperrte Passphrase nach Neustart
  // =========================================================================
  testWidgets('SIC-078 SIC-044 SIC-048 SIC-005 SIC-006 SIC-022 SIC-079 SIC-035 '
      'Nach Neustart gesperrt: Meldung, Hinweise, Entsperren', (tester) async {
    await starteApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 3; i++)
        testfoto('n$i.jpg', datum: DateTime(2022, 5, i + 1, 9)),
    ]);
    final zAuto = ordner('ziel_auto');
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: zAuto.path,
        intervalHours: 24,
      );
    });
    // Ein erster vollständiger Lauf über die Oberfläche.
    var auto = await autoGruppe(tester);
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    final erster = await laufAbwarten(tester, de.einstBackupLaeuft);
    expect(erster.erfolg, isTrue, reason: '$erster');
    await schliesseLauf(tester, de.einstBackupLaeuft);

    // Fällig machen und neu starten.
    await tester.runAsync(
      () => bibliothek.db.setLastAutoBackupAt(
        DateTime.now().subtract(const Duration(days: 3, hours: 1)),
      ),
    );
    melde.verlaufLeeren();
    await neustart(tester);
    expect(bibliothek.backupKeyAvailableThisSession, isFalse);

    // SIC-078
    final warnung = de.backupWartetPassphrase(3);
    await waitFor(
      tester,
      find.text(warnung),
      timeout: const Duration(seconds: 30),
    );
    expect(
      find.widgetWithText(TextButton, de.backupPassphraseEingeben),
      findsOneWidget,
    );
    expect(gemeldet(warnung, Meldungsart.warnung), isTrue);
    // Der nächste Takt des Zeitgebers meldet nicht noch einmal.
    await tester.runAsync(() => bibliothek.runAutoBackupIfDue());
    await settle(tester);
    expect(melde.verlauf.where((m) => m.text == warnung), hasLength(1));

    // SIC-044
    auto = await autoGruppe(tester);
    final hinweis = find.descendant(
      of: auto,
      matching: find.text(de.einstBackupPassphraseGesperrt),
    );
    await waitFor(tester, hinweis);
    expect(
      tester.widget<Text>(hinweis).style?.color,
      tester.element(hinweis).semantik.warnung,
    );

    // SIC-048
    final stand = find.descendant(
      of: auto,
      matching: find.byType(BackupStandAnzeige),
    );
    await waitFor(
      tester,
      find.descendant(
        of: stand,
        matching: textPasst(satzMuster(de.backupStandVom('\u0001'))),
      ),
    );
    expect(
      find.descendant(
        of: stand,
        matching: find.textContaining('Alles gesichert: 3 Dateien'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stand,
        matching: find.widgetWithText(TextButton, de.serverKontoEntsperren),
      ),
      findsOneWidget,
    );

    // SIC-005 (Status gesperrt)
    final schluessel = await schluesselGruppe(tester);
    expect(
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupGesperrt),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: schluessel,
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );

    // SIC-006
    await tippeIn(tester, schluessel, de.einstBackupAendern);
    await passphraseEingeben(tester, 'falsche-passphrase');
    await waitFor(tester, find.text(de.passphraseFalsch));
    expect(gemeldet(de.passphraseFalsch, Meldungsart.warnung), isTrue);
    expect(find.text(de.passphraseFestlegenTitel), findsNothing);
    expect(bibliothek.backupKeyAvailableThisSession, isFalse);
    expect(
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupGesperrt),
      ),
      findsOneWidget,
    );

    // SIC-022
    final hand = await handGruppe(tester);
    await tippeIn(tester, hand, de.einstBackupVerschluesseln);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.descendant(of: hand, matching: find.byType(CheckboxListTile)),
          )
          .value,
      isTrue,
    );
    final zHand = ordner('ziel_hand');
    dialog.ordner = zHand.path;
    dialog.gerufen.clear();
    await tippeIn(tester, hand, de.einstJetztSichern);
    await waitFor(tester, find.text(de.einstBackupPassphraseEingeben));
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.einstBackupPassphraseEingeben));
    await settle(tester, max: const Duration(seconds: 2));
    expect(
      dialog.gerufen.where((g) => g.startsWith('getDirectoryPath')),
      isEmpty,
    );
    expect(find.text(de.einstBackupSichertLaeuft), findsNothing);
    expect(zHand.listSync(recursive: true), isEmpty);

    // SIC-005 (Entsperren über „Ändern“)
    await tippeIn(tester, schluessel, de.einstBackupAendern);
    await passphraseEingeben(tester, _p1);
    await waitFor(tester, find.text(de.passphraseFestlegenTitel));
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.passphraseFestlegenTitel));
    expect(bibliothek.backupKeyAvailableThisSession, isTrue);
    var statusEntsperrt = true;
    try {
      await waitFor(
        tester,
        find.descendant(
          of: schluessel,
          matching: find.text(de.einstBackupEntsperrt),
        ),
        timeout: const Duration(seconds: 5),
      );
    } on TimeoutException {
      statusEntsperrt = false;
    }
    print(
      'SIC-005: Status nach Entsperren über Ändern: '
      '${statusEntsperrt ? 'entsperrt' : 'weiter gesperrt angezeigt'}',
    );

    // SIC-079: fällig machen, neu starten, aus der Meldung entsperren.
    await tester.runAsync(
      () => bibliothek.db.setLastAutoBackupAt(
        DateTime.now().subtract(const Duration(days: 3, hours: 1)),
      ),
    );
    melde.verlaufLeeren();
    await neustart(tester);
    await waitFor(
      tester,
      find.text(warnung),
      timeout: const Duration(seconds: 30),
    );
    final vorher = (await tester.runAsync(
      () => bibliothek.db.backupSettingsRow(),
    ))!.lastAutoBackupAt!;
    await tap(
      tester,
      find.widgetWithText(TextButton, de.backupPassphraseEingeben),
    );
    await passphraseEingeben(tester, _p1);
    await waitFor(
      tester,
      find.text(de.backupErledigt),
      timeout: const Duration(seconds: 120),
    );
    expect(gemeldet(de.backupErledigt, Meldungsart.erfolg), isTrue);
    expect(find.text(de.einstBackupLaeuft), findsNothing);
    final nachher = (await tester.runAsync(
      () => bibliothek.db.backupSettingsRow(),
    ))!.lastAutoBackupAt!;
    expect(nachher.isAfter(vorher), isTrue);

    // SIC-035: Neustart (nicht fällig), „Jetzt synchronisieren“ fragt.
    await neustart(tester);
    expect(bibliothek.backupKeyAvailableThisSession, isFalse);
    auto = await autoGruppe(tester);
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    await passphraseEingeben(tester, _p1);
    final lauf = await laufAbwarten(tester, de.einstBackupLaeuft);
    expect(lauf.erfolg, isTrue, reason: '$lauf');
    await schliesseLauf(tester, de.einstBackupLaeuft);
    final letzter = (await tester.runAsync(
      () => bibliothek.db.backupSettingsRow(),
    ))!.lastAutoBackupAt!;
    expect(DateTime.now().difference(letzter).inMinutes, lessThan(5));
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(AutomatischeSicherungGruppe),
        matching: find.text(datumZeit(letzter)),
      ),
    );
    await fertig(tester);
  });

  // Behoben in #415: Jedes Entsperren der Einstellungen geht über
  // _schluesselBereit und lädt den Stand des Schlüssels neu.
  testWidgets('SIC-005 Befund: Status wechselt nach Entsperren über Ändern', (
    tester,
  ) async {
    await starteApp(tester);
    await importiereDirekt(tester, [testfoto('s.jpg')]);
    await tester.runAsync(() => bibliothek.setupBackupPassphrase(_p1));
    await neustart(tester);
    final schluessel = await schluesselGruppe(tester);
    expect(
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupGesperrt),
      ),
      findsOneWidget,
    );
    await tippeIn(tester, schluessel, de.einstBackupAendern);
    await passphraseEingeben(tester, _p1);
    await waitFor(tester, find.text(de.passphraseFestlegenTitel));
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.passphraseFestlegenTitel));
    expect(bibliothek.backupKeyAvailableThisSession, isTrue);
    await waitFor(
      tester,
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstBackupEntsperrt),
      ),
      timeout: const Duration(seconds: 5),
    );
    await fertig(tester);
  });

  // =========================================================================
  // Sicherung von Hand ohne Passphrase, prüfen, zurückholen
  // =========================================================================
  testWidgets('SIC-010 SIC-058 SIC-059 SIC-061 SIC-071 SIC-070 SIC-062 SIC-077 '
      'SIC-066 Sicherung von Hand ohne Passphrase, prüfen, zurückholen', (
    tester,
  ) async {
    await starteApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 5; i++)
        testfoto(
          'foto_$i.jpg',
          datum: DateTime(2022, 4, i + 1, 10),
          breitengrad: 47.1 + i / 10,
          laengengrad: 11.1 + i / 10,
        ),
    ]);
    melde.verlaufLeeren();
    final vorher = await aufnahmen(tester);
    expect(vorher, hasLength(5));
    final pruefsummen = {for (final a in vorher) a.checksum};
    await tester.runAsync(() async {
      final db = bibliothek.db;
      await db.setRating(vorher[0].id, 5);
      await db.setRating(vorher[1].id, 3);
      await db.setFavorite(vorher[2].id, true);
      await db.setColorLabel(vorher[3].id, 'red');
      await db.createAlbum(
        AlbumsCompanion.insert(
          id: 'album-a',
          name: 'Album A',
          createdAt: DateTime(2024),
        ),
      );
      await db.addAssetsToAlbum('album-a', [vorher[0].id, vorher[4].id]);
    });

    // SIC-010
    final z = ordner('z');
    var hand = await handGruppe(tester);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.descendant(of: hand, matching: find.byType(CheckboxListTile)),
          )
          .value,
      isFalse,
    );
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstJetztSichern);
    final sicherung = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
    expect(sicherung.erfolg, isTrue, reason: '$sicherung');
    await schliesseLauf(tester, de.einstBackupSichertLaeuft);
    final wurzel = Directory(p.join(z.path, 'PhotoVault-Backup'));
    final originale = Directory(
      p.join(wurzel.path, 'originals'),
    ).listSync(recursive: true).whereType<File>().toList();
    final bilder = originale.where((f) => !f.path.endsWith('.xmp')).toList();
    final beilagen = originale.where((f) => f.path.endsWith('.xmp')).toList();
    expect(bilder, hasLength(5));
    expect(beilagen, hasLength(5));
    for (final b in bilder) {
      expect(
        p.relative(b.path, from: wurzel.path),
        matches(RegExp(r'^originals/\d{4}/\d{2}/[^/]+\.jpg$')),
      );
    }
    final meta =
        jsonDecode(
              File(p.join(wurzel.path, 'metadata.json')).readAsStringSync(),
            )
            as Map;
    expect((meta['assets'] as List), hasLength(5));
    expect(File(p.join(wurzel.path, 'vault.key')).existsSync(), isFalse);
    await waitFor(
      tester,
      find.descendant(
        of: hand,
        matching: find.text(de.einstBackupZusammenfassung(heute(), 5, z.path)),
      ),
    );

    // SIC-058
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    final pruefung = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
    expect(pruefung.erfolg, isTrue);
    expect(pruefung.ende, de.einstBackupPruefungErfolgreich(5));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    expect(
      gemeldet(de.einstBackupPruefungErfolgreich(5), Meldungsart.erfolg),
      isTrue,
    );

    // SIC-059
    final zk = ordner('z_kaputt');
    kopiere(z, zk);
    beschaedige(
      File(p.join(zk.path, p.relative(bilder.first.path, from: z.path))),
    );
    dialog.ordner = zk.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    final kaputt = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
    expect(kaputt.ende, de.einstBackupPruefungFehler(4, 0, 1));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    expect(
      gemeldet(de.einstBackupPruefungFehler(4, 0, 1), Meldungsart.warnung),
      isTrue,
    );

    // SIC-061
    final leer = ordner('leer');
    dialog.ordner = leer.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    final ohne = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
    expect(ohne.fehler, isTrue);
    expect(ohne.ende, startsWith(de.fortschrittFehlgeschlagen('')));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    expect(leer.listSync(recursive: true), isEmpty);
    print('SIC-061 (de): ${ohne.ende}');

    // SIC-071
    final zf = ordner('z_fehlt');
    kopiere(z, zf);
    File(
      p.join(zf.path, p.relative(bilder.last.path, from: z.path)),
    ).deleteSync();
    dialog.ordner = zf.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    final unvollstaendig = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(unvollstaendig.fehler, isTrue);
    expect(
      unvollstaendig.ende,
      de.fortschrittFehlgeschlagen(de.backupRestoreUnvollstaendig(0, 4, 1, 0)),
    );
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
    expect(await aufnahmen(tester), hasLength(5));

    // SIC-070
    await endgueltigWeg(tester, [vorher[1], vorher[3]]);
    expect(await aufnahmen(tester), hasLength(3));
    hand = await handGruppe(tester);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    final teil = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(teil.erfolg, isTrue, reason: '$teil');
    expect(teil.ende, de.backupRestoreZusammenfassung(2, 3));
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
    final nachTeil = await aufnahmen(tester);
    expect(nachTeil, hasLength(5));
    expect({for (final a in nachTeil) a.checksum}, pruefsummen);

    // SIC-062
    await leeren(tester);
    hand = await handGruppe(tester);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    final ganz = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(ganz.erfolg, isTrue, reason: '$ganz');
    expect(ganz.ende, de.backupRestoreZusammenfassung(5, 0));
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
    final zurueck = await aufnahmen(tester);
    expect(zurueck, hasLength(5));
    expect({for (final a in zurueck) a.checksum}, pruefsummen);
    AssetData von(String name) =>
        zurueck.singleWhere((a) => a.originalFileName == name);
    expect(von('foto_0.jpg').rating, 5);
    expect(von('foto_1.jpg').rating, 3);
    expect(von('foto_2.jpg').isFavorite, isTrue);
    expect(von('foto_3.jpg').colorLabel, 'red');
    for (var i = 0; i < 5; i++) {
      expect(von('foto_$i.jpg').latitude, closeTo(47.1 + i / 10, 0.001));
      expect(von('foto_$i.jpg').longitude, closeTo(11.1 + i / 10, 0.001));
    }
    final alben = await tester.runAsync(
      () => bibliothek.db.select(bibliothek.db.albums).get(),
    );
    final albumA = alben!.singleWhere((a) => a.name == 'Album A');
    final imAlbum = await tester.runAsync(
      () => bibliothek.db.assetsInAlbumOnce(albumA.id),
    );
    expect(
      {for (final a in imAlbum!) a.originalFileName},
      {'foto_0.jpg', 'foto_4.jpg'},
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    expect(find.text(de.timelineLeer), findsNothing);

    // SIC-077: Ordner mit beiden Sicherungsarten.
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.runAutoBackupNow(z.path).drain<void>();
    });
    expect(
      Directory(p.join(z.path, 'PhotoVault-AutoBackup')).existsSync(),
      isTrue,
    );
    hand = await handGruppe(tester);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    await waitFor(
      tester,
      fenster(de.einstBackupWiederherstellenLaeuft),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(de.einstBackupPassphraseEingeben), findsNothing);
    expect(find.text(de.einstBackupWiederherstellungspunktTitel), findsNothing);
    final beide = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(beide.ende, de.backupRestoreZusammenfassung(0, 5));
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);

    // … die automatische nur, wenn man ihren Ordner selbst wählt; dann
    // fragt sie nach der Passphrase. SIC-066: Abbrechen startet nichts.
    dialog.ordner = p.join(z.path, 'PhotoVault-AutoBackup');
    await tippeIn(tester, hand, de.einstWiederherstellen);
    await waitFor(tester, find.text(de.einstBackupPassphraseEingeben));
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.einstBackupPassphraseEingeben));
    await settle(tester, max: const Duration(seconds: 2));
    expect(fenster(de.einstBackupWiederherstellenLaeuft), findsNothing);
    expect(find.text(de.einstBackupWiederherstellungspunktTitel), findsNothing);
    expect(await aufnahmen(tester), hasLength(5));
    await fertig(tester);
  });

  // Behoben in #415: Der Prüfdienst wirft BackupManifestFehler, fehlertext
  // übersetzt ihn.
  testWidgets(
    'SIC-061 Befund: Fehler der Backup-Prüfung in der englischen Oberfläche',
    (tester) async {
      await starteApp(tester, sprache: 'en');
      final leer = ordner('leer');
      final ohneFotos = ordner('ohne_fotos');
      final kaputt = ordner('kaputt');
      File(p.join(kaputt.path, 'metadata.json')).writeAsStringSync('[]');
      final hand = await handGruppe(tester, en);
      dialog.ordner = ohneFotos.path;
      await tippeIn(tester, hand, en.einstJetztSichern);
      await laufAbwarten(tester, en.einstBackupSichertLaeuft, t: en);
      await schliesseLauf(tester, en.einstBackupSichertLaeuft, en);
      final texte = <String>[];
      for (final o in [leer, ohneFotos, kaputt]) {
        dialog.ordner = o.path;
        await tippeIn(tester, hand, en.einstBackupPruefen);
        final lauf = await laufAbwarten(
          tester,
          en.einstBackupPruefungLaeuft,
          t: en,
        );
        expect(lauf.fehler, isTrue);
        texte.add(lauf.ende);
        await schliesseLauf(tester, en.einstBackupPruefungLaeuft, en);
      }
      print('SIC-061 (en): $texte');
      for (final t in texte) {
        expect(t, isNot(contains('FormatException')));
        expect(t, isNot(contains('fehlt im Backup')));
        expect(t, isNot(contains('Das Backup enthält')));
        expect(t, isNot(contains('hat kein gültiges Format')));
      }
      await fertig(tester);
    },
  );

  // =========================================================================
  // Verschlüsselte Sicherung von Hand
  // =========================================================================
  testWidgets('SIC-011 SIC-060 SIC-055 SIC-056 SIC-065 SIC-007 SIC-009 SIC-064 '
      'SIC-063 Verschlüsselte Sicherung von Hand und zurückholen', (
    tester,
  ) async {
    const namen = [
      'urlaub.jpg',
      'strand.jpg',
      'berge.jpg',
      'seeufer.jpg',
      'wald.jpg',
    ];
    await starteApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < namen.length; i++)
        testfoto(
          namen[i],
          datum: DateTime(2021, 7, i + 1, 12),
          breite: 2400,
          hoehe: 1600,
        ),
    ]);
    melde.verlaufLeeren();
    final vorher = await aufnahmen(tester);
    AssetData von(List<AssetData> l, String n) =>
        l.singleWhere((a) => a.originalFileName == n);
    await tester.runAsync(() async {
      final db = bibliothek.db;
      await db.createPerson(PeopleCompanion.insert(id: 'pa', name: 'Person A'));
      await db.createPerson(PeopleCompanion.insert(id: 'pb', name: 'Person B'));
      var n = 0;
      for (final name in namen) {
        await db.insertFace(
          FacesCompanion.insert(
            id: 'gesicht_${n++}',
            assetId: von(vorher, name).id,
            boxX: 0.3,
            boxY: 0.25,
            boxW: 0.25,
            boxH: 0.3,
            personId: Value(n.isOdd ? 'pa' : 'pb'),
            cropRelativePath: Value('faces/gesicht_$n.jpg'),
          ),
        );
      }
      await db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'reise-a',
          name: 'Reise A',
          von: DateTime(2021, 7, 1),
          bis: DateTime(2021, 7, 6),
          angelegtAm: DateTime(2021, 8, 1),
        ),
        [for (final n in namen.take(3)) von(vorher, n).id],
      );
      await bibliothek.setupBackupPassphrase(_p1);
    });

    // SIC-011
    final z = ordner('z');
    var hand = await handGruppe(tester);
    await tippeIn(tester, hand, de.einstBackupVerschluesseln);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstJetztSichern);
    final sicherung = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
    expect(sicherung.erfolg, isTrue, reason: '$sicherung');
    await schliesseLauf(tester, de.einstBackupSichertLaeuft);
    final wurzel = Directory(p.join(z.path, 'PhotoVault-Backup'));
    final daten = Directory(p.join(wurzel.path, 'data'));
    expect(File(p.join(wurzel.path, 'vault.key')).existsSync(), isTrue);
    final datenDateien = daten.listSync();
    expect(datenDateien, hasLength(5));
    for (final d in datenDateien) {
      expect(d, isA<File>());
      expect(p.basename(d.path), isNot(contains('.')));
    }
    final alles = wurzel.listSync(recursive: true);
    for (final e in alles) {
      final rel = p.relative(e.path, from: wurzel.path);
      expect(rel, isNot(endsWith('.xmp')));
      expect(rel, isNot(endsWith('.jpg')));
      expect(rel, isNot(matches(RegExp(r'(^|/)\d{4}(/|$)'))));
      if (e is File) {
        final inhalt = latin1.decode(e.readAsBytesSync());
        for (final n in [
          ...namen.map((n) => n.split('.').first),
          'SQLite format 3',
          'Person A',
          'Reise A',
        ]) {
          expect(inhalt.contains(n), isFalse, reason: '„$n“ in $rel');
        }
      }
    }
    expect(Directory(p.join(wurzel.path, 'originals')).listSync(), isEmpty);
    final zustand = inhaltVon(z);

    // SIC-060
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    await waitFor(tester, find.text(de.einstBackupPassphraseEingeben));
    await tap(tester, imDialog(find.text(de.allgAbbrechen)));
    await waitGone(tester, find.text(de.einstBackupPassphraseEingeben));
    await settle(tester, max: const Duration(seconds: 2));
    expect(fenster(de.einstBackupPruefungLaeuft), findsNothing);
    await tippeIn(tester, hand, de.einstBackupPruefen);
    await passphraseEingeben(tester, _p1);
    final pruefung = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
    expect(pruefung.ende, de.einstBackupPruefungErfolgreich(5));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    expect(inhaltVon(z), zustand);

    // SIC-055
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.backupProbeStarten);
    await passphraseEingeben(tester, _p1);
    final probe = await laufAbwarten(tester, de.backupProbeTitel);
    expect(
      probe.ende,
      contains(' von 5 Originalen probeweise wiederhergestellt'),
    );
    expect(probe.ende, contains(de.backupProbeMitDatenbank));
    expect(
      probe.ende,
      contains('Die aktive Bibliothek wurde nicht verändert.'),
    );
    await schliesseLauf(tester, de.backupProbeTitel);
    expect(
      melde.verlauf.any(
        (m) =>
            m.art == Meldungsart.erfolg &&
            m.text.contains('Originalen probeweise wiederhergestellt') &&
            m.text.contains('Die aktive Bibliothek wurde nicht verändert.'),
      ),
      isTrue,
    );
    expect(await aufnahmen(tester), hasLength(5));

    // SIC-056
    final zk = ordner('z_kaputt');
    kopiere(z, zk);
    beschaedige(
      File(p.join(zk.path, 'PhotoVault-Backup', 'library.sqlite.enc')),
    );
    dialog.ordner = zk.path;
    await tippeIn(tester, hand, de.backupProbeStarten);
    await passphraseEingeben(tester, _p1);
    final kaputt = await laufAbwarten(tester, de.backupProbeTitel);
    expect(
      kaputt.ende,
      contains(
        ': Die Wiederherstellungsprobe war nicht erfolgreich. '
        'Sicherungsdateien, Passphrase und verfügbaren Platz prüfen.',
      ),
    );
    await schliesseLauf(tester, de.backupProbeTitel);
    expect(
      melde.verlauf.any(
        (m) =>
            m.art == Meldungsart.warnung &&
            m.text.contains(
              'Die Wiederherstellungsprobe war nicht erfolgreich',
            ),
      ),
      isTrue,
    );

    // SIC-065
    final summenVorher = {for (final a in await aufnahmen(tester)) a.checksum};
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    await passphraseEingeben(tester, 'falsch-falsch-falsch');
    final falsch = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(falsch.fehler, isTrue);
    expect(falsch.ende, startsWith(de.fortschrittFehlgeschlagen('')));
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
    print('SIC-065: ${falsch.ende}');
    final nachFalsch = await aufnahmen(tester);
    expect(nachFalsch, hasLength(5));
    expect({for (final a in nachFalsch) a.checksum}, summenVorher);

    // SIC-007
    final schluessel = await schluesselGruppe(tester);
    final keyVorher = File(p.join(wurzel.path, 'vault.key')).readAsStringSync();
    final datenVorher = inhaltVon(daten);
    final seit = DateTime.now();
    await tippeIn(tester, schluessel, de.einstBackupAendern);
    await passphraseFestlegen(tester, _p2);
    await settle(tester, max: const Duration(seconds: 2));
    final erfolgNachAendern = melde.verlauf.any(
      (m) => m.art == Meldungsart.erfolg && m.zeit.isAfter(seit),
    );
    print('SIC-007: Erfolgsmeldung nach Ändern: $erfolgNachAendern');
    // Bis zum nächsten Lauf trägt Z die alte Hülle.
    hand = await handGruppe(tester);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    await passphraseEingeben(tester, _p1);
    final alteHuelle = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
    expect(alteHuelle.ende, de.einstBackupPruefungErfolgreich(5));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    // Erneut nach Z sichern (Haken steht noch).
    expect(
      tester
          .widget<CheckboxListTile>(
            find.descendant(of: hand, matching: find.byType(CheckboxListTile)),
          )
          .value,
      isTrue,
    );
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstJetztSichern);
    final zweite = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
    expect(zweite.erfolg, isTrue, reason: '$zweite');
    await schliesseLauf(tester, de.einstBackupSichertLaeuft);
    expect(
      File(p.join(wurzel.path, 'vault.key')).readAsStringSync(),
      isNot(keyVorher),
    );
    expect(inhaltVon(daten), datenVorher);
    for (final (pass, gut) in [(_p2, true), (_p1, false)]) {
      dialog.ordner = z.path;
      await tippeIn(tester, hand, de.einstBackupPruefen);
      await passphraseEingeben(tester, pass);
      final lauf = await laufAbwarten(tester, de.einstBackupPruefungLaeuft);
      if (gut) {
        expect(lauf.ende, de.einstBackupPruefungErfolgreich(5));
      } else {
        expect(lauf.fehler, isTrue, reason: '$lauf');
        print('SIC-007: Prüfung mit alter Passphrase: ${lauf.ende}');
      }
      await schliesseLauf(tester, de.einstBackupPruefungLaeuft);
    }

    // SIC-009
    final zustand2 = inhaltVon(z);
    await tippeIn(tester, schluessel, de.allgEntfernen);
    await waitFor(tester, find.text(de.einstBackupEntschluesselnTitel));
    await tap(tester, imDialog(find.text(de.allgEntfernen)));
    await waitFor(
      tester,
      find.descendant(
        of: schluessel,
        matching: find.text(de.einstPassphraseEinrichten),
      ),
    );
    expect(await tester.runAsync(() => bibliothek.db.hasBackupKey()), isFalse);
    expect(inhaltVon(z), zustand2);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstBackupPruefen);
    await passphraseEingeben(tester, _p2);
    final nachEntfernen = await laufAbwarten(
      tester,
      de.einstBackupPruefungLaeuft,
    );
    expect(nachEntfernen.ende, de.einstBackupPruefungErfolgreich(5));
    await schliesseLauf(tester, de.einstBackupPruefungLaeuft);

    // SIC-064, SIC-063: leere Bibliothek ohne Backup-Passphrase, nur mit
    // der Passphrase zurückholen.
    await leeren(tester);
    expect(await zahl(tester, 'people'), 0);
    expect(await zahl(tester, 'reisen'), 0);
    expect(await tester.runAsync(() => bibliothek.db.hasBackupKey()), isFalse);
    dialog.ordner = z.path;
    await tippeIn(tester, hand, de.einstWiederherstellen);
    await passphraseEingeben(tester, _p2);
    final zurueck = await laufAbwarten(
      tester,
      de.einstBackupWiederherstellenLaeuft,
    );
    expect(zurueck.erfolg, isTrue, reason: '$zurueck');
    expect(zurueck.ende, de.backupRestoreZusammenfassung(5, 0));
    await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
    expect(
      zurueck.gesehen.any((t) => t.startsWith(de.backupAusschnitteNeu)),
      isTrue,
      reason: '${zurueck.gesehen}',
    );
    final uebernommen = satzMuster(
      de.backupUebernommen(1).replaceFirst('1', '\u0001'),
    );
    print(
      'SIC-063: Zeile „Einträge … übernommen“ gesehen: '
      '${zurueck.gesehen.any(uebernommen.hasMatch)}',
    );
    final neu = await aufnahmen(tester);
    expect(neu, hasLength(5));
    final personen = await tester.runAsync(
      () => bibliothek.db.select(bibliothek.db.people).get(),
    );
    expect({for (final x in personen!) x.name}, {'Person A', 'Person B'});
    final gesichter = await tester.runAsync(
      () => bibliothek.db.select(bibliothek.db.faces).get(),
    );
    expect(gesichter, hasLength(5));
    for (final g in gesichter!) {
      expect(neu.any((a) => a.id == g.assetId), isTrue);
      expect(g.cropRelativePath, isNotNull);
      expect(
        bibliothek.paths.absolute(g.cropRelativePath!).existsSync(),
        isTrue,
      );
    }
    expect(
      gesichter
          .where((g) => g.assetId == von(neu, 'urlaub.jpg').id)
          .single
          .personId,
      'pa',
    );
    expect(await zahl(tester, 'reisen'), 1);
    expect(await zahl(tester, 'reise_aufnahmen'), 3);
    await fertig(tester);
  });

  // Befund: Die Zeile „N Einträge aus dem Datenbank-Schnappschuss
  // übernommen …“ erscheint nie. Der Dienst schickt die Zahl nur im letzten
  // Ereignis mit (packages/kern/lib/services/backup_restore.dart:199), und
  // dort prüft _wiederherstellZeile zuerst das abgeschlossene Ergebnis
  // (lib/screens/einstellungen/sicherung.dart:457) und zeigt die
  // Zusammenfassung.
  testWidgets(
    'SIC-063 Befund: Zeile „Einträge aus dem Datenbank-Schnappschuss übernommen“',
    skip: true,
    (tester) async {
      await starteApp(tester);
      await importiereDirekt(tester, [testfoto('p1.jpg'), testfoto('p2.jpg')]);
      final z = ordner('z');
      await tester.runAsync(() async {
        await bibliothek.db.createPerson(
          PeopleCompanion.insert(id: 'pa', name: 'Person A'),
        );
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.runManualBackup(z.path, encrypt: true).drain<void>();
      });
      await leeren(tester);
      final hand = await handGruppe(tester);
      dialog.ordner = z.path;
      await tippeIn(tester, hand, de.einstWiederherstellen);
      await passphraseEingeben(tester, _p1);
      final lauf = await laufAbwarten(
        tester,
        de.einstBackupWiederherstellenLaeuft,
      );
      expect(lauf.erfolg, isTrue);
      expect(await zahl(tester, 'people'), 1);
      final uebernommen = satzMuster(
        de.backupUebernommen(1).replaceFirst('1', '\u0001'),
      );
      expect(
        lauf.gesehen.any(uebernommen.hasMatch),
        isTrue,
        reason: '${lauf.gesehen}',
      );
      await fertig(tester);
    },
  );

  // Behoben in #415: Eine falsche Passphrase kommt als PassphraseFalsch
  // an und erscheint als „Falsche Passphrase.“.
  testWidgets(
    'SIC-065 Befund: falsche Passphrase beim Wiederherstellen, lesbare Meldung',
    (tester) async {
      await starteApp(tester);
      await importiereDirekt(tester, [testfoto('w.jpg')]);
      final z = ordner('z');
      await tester.runAsync(() async {
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.runManualBackup(z.path, encrypt: true).drain<void>();
      });
      final hand = await handGruppe(tester);
      dialog.ordner = z.path;
      await tippeIn(tester, hand, de.einstWiederherstellen);
      await passphraseEingeben(tester, 'falsch-falsch-falsch');
      final lauf = await laufAbwarten(
        tester,
        de.einstBackupWiederherstellenLaeuft,
      );
      expect(lauf.fehler, isTrue);
      expect(lauf.ende, isNot(contains('SecretBox')));
      expect(lauf.ende, isNot(contains('Error')));
      expect(lauf.ende, isNot(contains('Exception')));
      await fertig(tester);
    },
  );

  // =========================================================================
  // Fortschritt, Probe, Wiederherstellungspunkte
  // =========================================================================
  testWidgets(
    'SIC-024 SIC-025 SIC-036 SIC-052 SIC-054 SIC-038 SIC-067 Fortschritt, '
    'Probe und Wiederherstellungspunkte',
    (tester) async {
      await starteApp(tester);
      await importiereDirekt(tester, [
        for (var i = 0; i < 20; i++)
          testfoto(
            'bild_${i.toString().padLeft(2, '0')}.jpg',
            datum: DateTime(2020, 1, 1, 12).add(Duration(days: i)),
            breite: 1600,
            hoehe: 1200,
          ),
      ]);
      final zAuto = ordner('ziel_auto');
      final alle = await aufnahmen(tester);
      await tester.runAsync(() async {
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.db.setAutoBackupConfig(
          enabled: true,
          destination: zAuto.path,
        );
        await bibliothek.db.createPerson(
          PeopleCompanion.insert(id: 'p-a', name: 'Person A'),
        );
      });

      // SIC-024
      final hand = await handGruppe(tester);
      dialog.ordner = ordner('ziel_hand').path;
      await tippeIn(tester, hand, de.einstJetztSichern);
      final vonHand = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
      expect(vonHand.balken, isTrue);
      expect(vonHand.abbrechen, isFalse);
      expect(vonHand.erfolg, isTrue);
      expect(
        vonHand.gesehen.any(RegExp(r'^\d+ / 20 — bild_\d\d\.jpg$').hasMatch),
        isTrue,
        reason: '${vonHand.gesehen}',
      );
      await schliesseLauf(tester, de.einstBackupSichertLaeuft);

      // SIC-025
      var auto = await autoGruppe(tester);
      await tippeIn(tester, auto, de.einstJetztSynchronisieren);
      final erster = await laufAbwarten(tester, de.einstBackupLaeuft);
      expect(erster.erfolg, isTrue, reason: '$erster');
      final menge = satzMuster(
        '\u0001 / 20\u0001\n'
        '${de.backupLaufMenge('\u0001', '\u0001', '\u0001')}',
      );
      expect(
        erster.gesehen.any(menge.hasMatch),
        isTrue,
        reason: '${erster.gesehen}',
      );
      expect(
        erster.gesehen.any(
          RegExp(
            r'^\d+ / 20 — bild_\d\d\.jpg\n.+ von .+ gesichert, .+ ausstehend$',
          ).hasMatch,
        ),
        isTrue,
      );
      await schliesseLauf(tester, de.einstBackupLaeuft);

      // SIC-052, SIC-054
      auto = await autoGruppe(tester);
      final probeZeile = RegExp(
        r'^\d{1,2}\.\d{1,2}\.\d{4} – \d{2}:\d{2}: \d+ von 20 Originalen '
        r'probeweise wiederhergestellt; Datenbank geprüft\. Die aktive '
        r'Bibliothek wurde nicht verändert\.\n'
        '${RegExp.escape(de.backupProbePassphraseOffen)}\$',
      );
      await waitFor(
        tester,
        find.descendant(of: auto, matching: textPasst(probeZeile)),
      );

      // SIC-036
      await tippeIn(tester, auto, de.einstJetztSynchronisieren);
      final nochmal = await laufAbwarten(tester, de.einstBackupLaeuft);
      expect(nochmal.erfolg, isTrue, reason: '$nochmal');
      expect(
        nochmal.ende == de.einstBackupKeineNeuen ||
            nochmal.ende.contains('Originalen probeweise wiederhergestellt'),
        isTrue,
        reason: nochmal.ende,
      );
      print(
        'SIC-036: „Keine neuen Dateien“ gesehen: '
        '${nochmal.gesehen.contains(de.einstBackupKeineNeuen)}',
      );
      await schliesseLauf(tester, de.einstBackupLaeuft);

      // SIC-038: insgesamt neun Läufe, je mit einer kleinen Änderung.
      for (var lauf = 3; lauf <= 9; lauf++) {
        await tester.runAsync(() async {
          await bibliothek.db.setFavorite(alle[lauf].id, true);
          if (lauf == 9) {
            // Für SIC-067: Der jüngste Stand kennt „Person A“ nicht mehr.
            await bibliothek.db.customStatement(
              "DELETE FROM people WHERE id = 'p-a'",
            );
            await bibliothek.db.createPerson(
              PeopleCompanion.insert(id: 'p-b', name: 'Person B'),
            );
          }
        });
        auto = await autoGruppe(tester);
        await tippeIn(tester, auto, de.einstJetztSynchronisieren);
        final l = await laufAbwarten(tester, de.einstBackupLaeuft);
        expect(l.erfolg, isTrue, reason: 'Lauf $lauf: $l');
        await schliesseLauf(tester, de.einstBackupLaeuft);
      }
      final autoWurzel = Directory(p.join(zAuto.path, 'PhotoVault-AutoBackup'));
      final generationen = Directory(p.join(autoWurzel.path, 'generations'))
          .listSync()
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList();
      print('SIC-038: ${generationen.length} Generationen');
      expect(generationen.length, lessThanOrEqualTo(7));
      expect(generationen.length, 7);
      expect(
        Directory(p.join(autoWurzel.path, 'data')).listSync().whereType<File>(),
        hasLength(20),
      );

      // SIC-067
      expect(await zahl(tester, 'people'), 1);
      dialog.ordner = zAuto.path;
      await tippeIn(tester, hand, de.einstWiederherstellen);
      await passphraseEingeben(tester, _p1);
      await waitFor(
        tester,
        find.text(de.einstBackupWiederherstellungspunktTitel),
      );
      expect(find.text(de.einstBackupAktuellerStand), findsOneWidget);
      final punkte = textPasst(
        satzMuster(de.einstBackupGenerationZeit('\u0001')),
      );
      // Das Blatt zeigt nicht alle sieben auf einmal; die übrigen liegen
      // beim Scrollen darunter. Gesammelt wird beim Scrollen bis ans Ende,
      // gewählt der unterste (älteste) Punkt.
      final gesehenePunkte = <String>{};
      void sammle() {
        for (final e in punkte.evaluate()) {
          gesehenePunkte.add((e.widget as Text).data!);
        }
      }

      sammle();
      expect(punkte, findsWidgets);
      final blatt = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 6; i++) {
        await tester.drag(blatt, const Offset(0, -150));
        await settle(tester);
        sammle();
      }
      print(
        'SIC-067: ${gesehenePunkte.length} Punkte im Blatt: $gesehenePunkte',
      );
      await starte(tester, punkte.last);
      final w = await laufAbwarten(
        tester,
        de.einstBackupWiederherstellenLaeuft,
      );
      expect(w.erfolg, isTrue, reason: '$w');
      expect(w.ende, de.backupRestoreZusammenfassung(0, 20));
      await schliesseLauf(tester, de.einstBackupWiederherstellenLaeuft);
      final personen = await tester.runAsync(
        () => bibliothek.db.select(bibliothek.db.people).get(),
      );
      expect({for (final x in personen!) x.name}, {'Person A', 'Person B'});
      await fertig(tester);
    },
  );

  // =========================================================================
  // Menge je Lauf und Prüfbudget (grosse Dateien)
  // =========================================================================
  testWidgets('SIC-057 SIC-033 SIC-034 SIC-046 Menge je Lauf und Prüfbudget', (
    tester,
  ) async {
    await starteApp(tester);
    melde.verlaufLeeren();
    // Zwei Originale über 128 MB, zusammen über 500 MB, die neuesten.
    await importiereDirekt(tester, [
      grossesFoto('gross_1.jpg', 265, datum: DateTime(2024, 6, 2, 10)),
      grossesFoto('gross_2.jpg', 265, datum: DateTime(2024, 6, 1, 10)),
    ]);
    expect(await aufnahmen(tester), hasLength(2));

    // SIC-057: Sicherung nur mit Originalen über dem Prüfbudget.
    final zGross = ordner('z_gross');
    var hand = await handGruppe(tester);
    dialog.ordner = zGross.path;
    await tippeIn(tester, hand, de.einstJetztSichern);
    final gross = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
    print('SIC-057 Sicherung: ${gross.ende}');
    await schliesseLauf(tester, de.einstBackupSichertLaeuft);
    dialog.ordner = zGross.path;
    await tippeIn(tester, hand, de.backupProbeStarten);
    final probe = await laufAbwarten(tester, de.backupProbeTitel);
    expect(probe.ende, matches(satzMuster(de.backupProbeZuGross('\u0001'))));
    await schliesseLauf(tester, de.backupProbeTitel);
    expect(
      melde.verlauf.any(
        (m) =>
            m.art == Meldungsart.warnung &&
            m.text.contains(
              'Kein Original passt in das Prüfbudget von 128 MB.',
            ),
      ),
      isTrue,
    );

    // Beobachtung zum Befund „SIC-057 Zusatz“: das automatische Backup, wenn
    // kein Original ins Prüfbudget passt (eigenes Ziel).
    final zNurGross = ordner('ziel_nur_gross');
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: zNurGross.path,
      );
    });
    await einstellungenNeu(tester);
    final autoNurGross = await autoGruppe(tester);
    await tippeIn(tester, autoNurGross, de.einstJetztSynchronisieren);
    final nurGross = await laufAbwarten(
      tester,
      de.einstBackupLaeuft,
      timeout: const Duration(minutes: 10),
    );
    await schliesseLauf(tester, de.einstBackupLaeuft);
    print(
      'SIC-057 automatisch: fehler=${nurGross.fehler}, ende=„${nurGross.ende}“, '
      'letzter Lauf=${(await tester.runAsync(() => bibliothek.db.backupSettingsRow()))?.lastAutoBackupAt}',
    );

    // Drei kleine, ältere Fotos dazu.
    final klein = [
      for (var i = 0; i < 3; i++)
        testfoto('klein_$i.jpg', datum: DateTime(2020, 1, i + 1, 10)),
    ];
    await importiereDirekt(tester, klein);
    final alle = await aufnahmen(tester);
    expect(alle, hasLength(5));
    final kleinBytes = alle
        .where((a) => a.originalFileName.startsWith('klein_'))
        .fold<int>(0, (s, a) => s + a.fileSizeBytes);

    // SIC-033
    final zAuto = ordner('ziel_auto');
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: zAuto.path,
      );
    });
    await einstellungenNeu(tester);
    var auto = await autoGruppe(tester);
    final menge = dropdownBei(auto, de.einstMengeJeLauf);
    await tap(tester, menge);
    await tap(tester, find.text('500 MB').last);
    await eventually(
      tester,
      () async =>
          (await bibliothek.db.backupSettingsRow())?.autoBackupMaxMbPerRun ==
          500,
    );
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    final begrenzt = await laufAbwarten(
      tester,
      de.einstBackupLaeuft,
      timeout: const Duration(minutes: 10),
    );
    expect(begrenzt.erfolg, isTrue, reason: '$begrenzt');
    expect(begrenzt.ende, de.backupGrenzeErreicht(3, groessentext(kleinBytes)));
    await schliesseLauf(tester, de.einstBackupLaeuft);
    final datenAuto = Directory(
      p.join(zAuto.path, 'PhotoVault-AutoBackup', 'data'),
    );
    expect(datenAuto.listSync(), hasLength(2));

    // SIC-046
    auto = await autoGruppe(tester);
    final stand = find.descendant(
      of: auto,
      matching: find.byType(BackupStandAnzeige),
    );
    await waitFor(
      tester,
      find.descendant(
        of: stand,
        matching: find.textContaining('Gesichert: 2 von 5 Dateien ('),
      ),
    );
    expect(
      find.descendant(
        of: stand,
        matching: find.text(de.backupStandOffen(3, groessentext(kleinBytes))),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stand, matching: find.text(de.backupStandHinweis)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stand,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsOneWidget,
    );
    final neuZaehlen = find.descendant(
      of: stand,
      matching: find.byTooltip(de.backupStandNeuZaehlen),
    );
    await tester.tap(neuZaehlen);
    var zaehltGesehen = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find
          .descendant(of: stand, matching: find.text(de.backupStandZaehlt))
          .evaluate()
          .isNotEmpty) {
        zaehltGesehen = true;
      }
    }
    print(
      'SIC-046: „Wird gezählt …“ nach „Neu zählen“ gesehen: $zaehltGesehen',
    );
    expect(
      find.descendant(
        of: stand,
        matching: find.textContaining('Gesichert: 2 von 5 Dateien ('),
      ),
      findsOneWidget,
    );

    // SIC-034: Die Grenze gilt auch von Hand – sie steht aber nur beim
    // automatischen Backup.
    hand = await handGruppe(tester);
    expect(
      find.descendant(of: hand, matching: find.text(de.einstMengeJeLauf)),
      findsNothing,
    );
    expect(
      find.descendant(of: auto, matching: find.text(de.einstMengeJeLauf)),
      findsOneWidget,
    );
    final zHand = ordner('ziel_hand');
    dialog.ordner = zHand.path;
    await tippeIn(tester, hand, de.einstJetztSichern);
    final vonHand = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
    expect(vonHand.ende, de.backupGrenzeErreicht(3, groessentext(kleinBytes)));
    await schliesseLauf(tester, de.einstBackupSichertLaeuft);
    await waitFor(
      tester,
      find.descendant(
        of: hand,
        matching: find.text(
          de.einstBackupZusammenfassung(heute(), 2, zHand.path),
        ),
      ),
    );

    // SIC-033: Der zweite Lauf holt den Rest nach.
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    final rest = await laufAbwarten(
      tester,
      de.einstBackupLaeuft,
      timeout: const Duration(minutes: 10),
    );
    expect(rest.erfolg, isTrue, reason: '$rest');
    expect(
      rest.ende,
      contains('von 5 Originalen probeweise wiederhergestellt'),
    );
    await schliesseLauf(tester, de.einstBackupLaeuft);
    expect(datenAuto.listSync(), hasLength(5));
    await fertig(tester);
  });

  // Befund (Zusatz zu SIC-057): Passt kein Original ins Prüfbudget von
  // 128 MB, gilt die Probe als gescheitert
  // (packages/kern/lib/services/backup_probe.dart:159), und das automatische
  // Backup wirft danach (lib/services/backup_koordinator.dart:160-168): Das
  // Fenster zeigt „Fehlgeschlagen: Bad state: pv_probe_stichprobe_zu_gross“,
  // „Letzter Lauf“ bleibt leer. Eine Bibliothek nur aus grossen Videos käme
  // so nie zu einem gelungenen automatischen Backup. Siehe auch die Ausgabe
  // „SIC-057 automatisch“ im Test „SIC-057 SIC-033 …“.
  testWidgets(
    'SIC-057 Zusatz: automatisches Backup, wenn kein Original ins Prüfbudget passt',
    skip: true,
    (tester) async {
      await starteApp(tester);
      await importiereDirekt(tester, [
        grossesFoto('video_gross.jpg', 140, datum: DateTime(2024, 5, 1, 10)),
      ]);
      final z = ordner('ziel_auto');
      await tester.runAsync(() async {
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.db.setAutoBackupConfig(
          enabled: true,
          destination: z.path,
        );
      });
      final auto = await autoGruppe(tester);
      await tippeIn(tester, auto, de.einstJetztSynchronisieren);
      final lauf = await laufAbwarten(tester, de.einstBackupLaeuft);
      await schliesseLauf(tester, de.einstBackupLaeuft);
      final letzter = (await tester.runAsync(
        () => bibliothek.db.backupSettingsRow(),
      ))!.lastAutoBackupAt;
      print('SIC-057 Zusatz: $lauf, letzter Lauf: $letzter');
      expect(lauf.fehler, isFalse, reason: lauf.ende);
      expect(letzter, isNotNull);
      await fertig(tester);
    },
  );

  // Befund: Nach „Neu zählen“ bleibt der alte Stand stehen; „Wird gezählt …“
  // zeigt die Anzeige nur, solange noch gar kein Stand da ist
  // (lib/screens/einstellungen/backup_stand.dart:112-121).
  testWidgets(
    'SIC-046 Befund: „Neu zählen“ zeigt „Wird gezählt …“',
    skip: true,
    (tester) async {
      await starteApp(tester);
      await importiereDirekt(tester, [
        for (var i = 0; i < 4; i++) testfoto('z$i.jpg'),
      ]);
      final zAuto = ordner('ziel_auto');
      await tester.runAsync(() async {
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.db.setAutoBackupConfig(
          enabled: true,
          destination: zAuto.path,
        );
        await bibliothek.runAutoBackupNow(zAuto.path).drain<void>();
      });
      final auto = await autoGruppe(tester);
      final stand = find.descendant(
        of: auto,
        matching: find.byType(BackupStandAnzeige),
      );
      await waitFor(
        tester,
        find.descendant(
          of: stand,
          matching: find.textContaining('Alles gesichert'),
        ),
      );
      await tester.tap(
        find.descendant(
          of: stand,
          matching: find.byTooltip(de.backupStandNeuZaehlen),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(of: stand, matching: find.text(de.backupStandZaehlt)),
        findsOneWidget,
      );
      await fertig(tester);
    },
  );

  // =========================================================================
  // Zielordner, Zeitgeber, Meldungen
  // =========================================================================
  testWidgets('SIC-042 SIC-039 SIC-043 SIC-081 SIC-080 Zielordner mit Merkmal, '
      'Zeitgeber, gesperrtes Ziel, fehlendes Original', (tester) async {
    await starteApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 3; i++)
        testfoto('m$i.jpg', datum: DateTime(2021, 2, i + 1, 9)),
    ]);
    final kanal = Ordnerkanal(tester);
    await tester.runAsync(() => bibliothek.setupBackupPassphrase(_p1));

    // SIC-042
    final z = ordner('ziel_merkmal');
    kanal.ordner = z.path;
    var auto = await autoGruppe(tester);
    await tippeIn(tester, auto, de.einstWaehlen);
    await waitFor(
      tester,
      find.descendant(of: auto, matching: find.text(z.path)),
    );
    final merkmale = File(p.join(anker.path, 'sicherungsziel.json'));
    print('SIC-042: Merkmal-Datei vorhanden: ${merkmale.existsSync()}');
    await neustart(tester);
    kanal.gerufen.clear();
    auto = await autoGruppe(tester);
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    await passphraseEingeben(tester, _p1);
    final nachNeustart = await laufAbwarten(tester, de.einstBackupLaeuft);
    expect(nachNeustart.erfolg, isTrue, reason: '$nachNeustart');
    expect(nachNeustart.ende, isNot(contains('Operation not permitted')));
    await schliesseLauf(tester, de.einstBackupLaeuft);
    expect(kanal.gerufen, contains('resolveBookmark'));
    expect(
      Directory(p.join(z.path, 'PhotoVault-AutoBackup', 'data')).listSync(),
      hasLength(3),
    );

    // SIC-039: Takt des Zeitgebers (derselbe Aufruf wie alle 30 Minuten).
    final vorZweiStunden = DateTime.now().subtract(const Duration(hours: 2));
    await tester.runAsync(() async {
      await bibliothek.db.setAutoBackupConfig(enabled: true, intervalHours: 1);
      await bibliothek.db.setLastAutoBackupAt(vorZweiStunden);
      await bibliothek.runAutoBackupIfDue();
    });
    final takt = (await tester.runAsync(
      () => bibliothek.db.backupSettingsRow(),
    ))!.lastAutoBackupAt!;
    expect(
      takt.isAfter(vorZweiStunden.add(const Duration(minutes: 90))),
      isTrue,
    );
    await einstellungenNeu(tester);
    auto = await autoGruppe(tester);
    await waitFor(
      tester,
      find.descendant(of: auto, matching: find.text(datumZeit(takt))),
    );

    // SIC-043
    final gesperrt = ordner('ziel_gesperrt');
    await chmod('555', gesperrt.path);
    addTearDown(() async {
      try {
        await chmod('755', gesperrt.path);
      } catch (_) {}
    });
    await tester.runAsync(
      () => bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: gesperrt.path,
      ),
    );
    await einstellungenNeu(tester);
    auto = await autoGruppe(tester);
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    final zu = await laufAbwarten(tester, de.einstBackupLaeuft);
    expect(zu.fehler, isTrue);
    expect(zu.ende, de.fortschrittFehlgeschlagen(de.backupZielGesperrt));
    await schliesseLauf(tester, de.einstBackupLaeuft);

    // SIC-081
    await tester.runAsync(
      () => bibliothek.db.setLastAutoBackupAt(vorZweiStunden),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitGone(tester, find.byType(SettingsScreen));
    melde.verlaufLeeren();
    await tester.runAsync(() => bibliothek.runAutoBackupIfDue());
    await waitFor(tester, find.text(de.backupZielGesperrt));
    expect(gemeldet(de.backupZielGesperrt, Meldungsart.warnung), isTrue);
    await tap(tester, find.widgetWithText(TextButton, de.backupZurEinstellung));
    await waitFor(tester, find.byType(SettingsScreen));
    await chmod('755', gesperrt.path);

    // SIC-080
    final frisch = ordner('ziel_frisch');
    final eins = (await aufnahmen(tester)).first;
    bibliothek.paths.absolute(eins.relativePath).deleteSync();
    await tester.runAsync(() async {
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: frisch.path,
      );
      await bibliothek.db.setLastAutoBackupAt(vorZweiStunden);
    });
    melde.verlaufLeeren();
    await tester.runAsync(() => bibliothek.runAutoBackupIfDue());
    await waitFor(tester, find.text(de.backupDateienFehlen(1)));
    expect(gemeldet(de.backupDateienFehlen(1), Meldungsart.warnung), isTrue);
    await fertig(tester);
  });

  // =========================================================================
  // Zwei Läufe gleichzeitig
  // =========================================================================
  // Behoben in #415: ProgressDialog übersetzt Fehler ohne eigenes
  // fehlerText über die gemeinsame Übersetzung fehlertext.
  testWidgets('SIC-041 Zwei Läufe gleichzeitig', (tester) async {
    await starteApp(tester);
    await importiereDirekt(tester, [
      grossesFoto('gross.jpg', 80, datum: DateTime(2024, 1, 1, 10)),
      testfoto('klein.jpg', datum: DateTime(2020, 1, 1, 10)),
    ]);
    final z = ordner('ziel_auto');
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: z.path,
      );
    });
    final auto = await autoGruppe(tester);
    // Der Zeitgeber stösst einen Lauf an …
    final hintergrund = bibliothek.runAutoBackupIfDue();
    await tester.pump(const Duration(milliseconds: 200));
    // … und währenddessen „Jetzt synchronisieren“.
    await tippeIn(tester, auto, de.einstJetztSynchronisieren);
    final lauf = await laufAbwarten(tester, de.einstBackupLaeuft);
    await schliesseLauf(tester, de.einstBackupLaeuft);
    await tester.runAsync(() => hintergrund);
    final generationen =
        Directory(p.join(z.path, 'PhotoVault-AutoBackup', 'generations'))
            .listSync()
            .whereType<Directory>()
            .where((d) => !p.basename(d.path).startsWith('.'));
    expect(lauf.fehler, isTrue, reason: '$lauf');
    expect(generationen, hasLength(1));
    print('SIC-041: ${lauf.ende}');
    expect(lauf.ende, de.fortschrittFehlgeschlagen(de.backupLaeuftBereits));
    await fertig(tester);
  });

  // =========================================================================
  // Verbundene Bibliothek (Wegwerf-Server der Warteschlange)
  // =========================================================================
  testWidgets(
    'SIC-029 SIC-045 Sicherung in einer mit dem Server verbundenen Bibliothek',
    skip: serverAdresse.isEmpty,
    (tester) async {
      await starteApp(tester);
      melde.verlaufLeeren();
      final adresse = Uri.parse(
        serverAdresse.endsWith('/') ? serverAdresse : '$serverAdresse/',
      );
      const konto = 'konto-a';
      const passwort = 'ein langes passwort fuer die pruefung';
      final fotos = [
        testfoto('strand.jpg', datum: DateTime(2023, 7, 1, 12)),
        testfoto('wiese.jpg', datum: DateTime(2023, 7, 2, 12)),
      ];
      late String tokenRechner;
      await tester.runAsync(() async {
        // Ein anderes Gerät legt das Konto an und lädt zwei Fotos hoch.
        final a = Anmeldung(adresse);
        final telefon = await a.einrichten(konto, passwort, geraet: 'Telefon');
        a.schliesse();
        final anders = Serververbindung(
          adresse,
          (telefon as AnmeldungFertig).token,
        );
        for (final f in fotos) {
          await TusHochladen(
            anders,
          ).lade(f, 'api/v1/hochladen', {'filename': p.basename(f.path)});
        }
        anders.schliesse();
        final b = Anmeldung(adresse);
        final rechner = await b.anmelden(konto, passwort, geraet: 'Rechner');
        b.schliesse();
        tokenRechner = (rechner as AnmeldungFertig).token;
      });

      // Diese Bibliothek wird zur verbundenen Kopie: Abzug des Servers und
      // Verbindungsdatei in den Datenordner, dann neu starten (wie nach
      // „Server verbinden“, nur ohne das Beenden der App).
      final wurzel = bibliothek.paths.root.parent;
      expect(wurzel.path, startsWith(anker.path));
      await hintergrundAnhalten(tester);
      await bibliothek.vorDemBeenden();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        for (final endung in ['', '-wal', '-shm']) {
          final f = File(p.join(wurzel.path, 'library.sqlite$endung'));
          if (f.existsSync()) f.deleteSync();
        }
        final v = Serververbindung(adresse, tokenRechner);
        await Abgleich.holeAbzug(
          v,
          File(p.join(wurzel.path, 'library.sqlite')),
        );
        v.schliesse();
        await Verbindungsdatei(
          server: adresse,
          konto: konto,
          geraet: 'Rechner',
          token: tokenRechner,
        ).schreibe(wurzel);
      });
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
      expect(bibliothek.verbunden, isTrue);
      final alle = await aufnahmen(tester);
      expect(
        {for (final a in alle) a.originalFileName},
        {'strand.jpg', 'wiese.jpg'},
      );
      // Originale nur teilweise da: eines gibt es hier sicher nicht.
      for (final a in alle) {
        final f = bibliothek.paths.absolute(a.relativePath);
        if (a.originalFileName == 'strand.jpg' && f.existsSync()) {
          f.deleteSync();
        }
      }
      expect(
        bibliothek.paths
            .absolute(
              alle
                  .singleWhere((a) => a.originalFileName == 'strand.jpg')
                  .relativePath,
            )
            .existsSync(),
        isFalse,
      );

      // SIC-029
      final zHand = ordner('ziel_hand');
      final hand = await handGruppe(tester);
      dialog.ordner = zHand.path;
      await tippeIn(tester, hand, de.einstJetztSichern);
      final vonHand = await laufAbwarten(tester, de.einstBackupSichertLaeuft);
      expect(vonHand.erfolg, isTrue, reason: '$vonHand');
      expect(vonHand.gesehen.any((t) => t.contains(de.nurOhneServer)), isFalse);
      await schliesseLauf(tester, de.einstBackupSichertLaeuft);
      expect(gemeldet(de.nurOhneServer), isFalse);
      final kopiert =
          Directory(p.join(zHand.path, 'PhotoVault-Backup', 'originals'))
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => !f.path.endsWith('.xmp'));
      expect(kopiert, hasLength(2));

      // SIC-045
      final zAuto = ordner('ziel_auto');
      await tester.runAsync(() async {
        await bibliothek.setupBackupPassphrase(_p1);
        await bibliothek.db.setAutoBackupConfig(
          enabled: true,
          destination: zAuto.path,
        );
      });
      await einstellungenNeu(tester);
      final auto = await autoGruppe(tester);
      await tippeIn(tester, auto, de.einstJetztSynchronisieren);
      final lauf = await laufAbwarten(tester, de.einstBackupLaeuft);
      expect(lauf.erfolg, isTrue, reason: '$lauf');
      await schliesseLauf(tester, de.einstBackupLaeuft);
      expect(
        Directory(
          p.join(zAuto.path, 'PhotoVault-AutoBackup', 'data'),
        ).listSync(),
        hasLength(2),
      );
      for (final a in await aufnahmen(tester)) {
        expect(a.autoBackedUp, isFalse, reason: a.originalFileName);
        expect(a.backedUp, isFalse, reason: a.originalFileName);
      }
      await fertig(tester);
    },
  );

  // =========================================================================
  // Zweite Bibliothek vergleichen
  // =========================================================================
  // Über den Eintrag „Duplikate“ der Seitenleiste – derselbe Bildschirm wie
  // Werkzeuge → „Duplikate & ähnliche Fotos suchen“. Der Weg über die
  // Werkzeuge (Scrollen in ihrer Liste) löste im Testbau wiederholt
  // Semantik-Assertions des Frameworks aus („!child.attached“).
  Future<void> zweiteBibliothekOeffnen(
    WidgetTester tester, [
    AppTexte? t,
  ]) async {
    final s = t ?? de;
    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(tester, find.byType(DuplicatesScreen));
    await tap(tester, find.text(s.duplZweiteBibliothek));
    await waitFor(tester, find.byType(SecondLibraryCompareScreen));
  }

  // Befund: Der Grund steht als fester deutscher Satz im Dienst
  // (lib/services/second_library_scan_service.dart:84) und erscheint so
  // auch in der englischen Oberfläche („Comparison failed: Kein
  // PhotoVault-Ordner: library.sqlite fehlt unter …“). Nachgestellt im
  // Test „SIC-088 SIC-091 SIC-093 SIC-092 …“ (Ausgabe „SIC-092 (en)“).
  testWidgets(
    'SIC-092 Befund: Grund „library.sqlite fehlt“ in der englischen Oberfläche',
    skip: true,
    (tester) async {
      await starteApp(
        tester,
        sprache: 'en',
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
        ],
      );
      final kanal = Ordnerkanal(tester);
      expect(bibliothek.clipAvailable, isTrue);
      await zweiteBibliothekOeffnen(tester, en);
      kanal.ordner = ordner('leer').path;
      await tap(tester, find.text(en.zweitOrdnerKnopf));
      final fehler = textPasst(
        satzMuster(en.zweitVergleichFehlgeschlagen('\u0001')),
      );
      await waitFor(tester, fehler);
      expect(tester.widget<Text>(fehler).data, isNot(contains('fehlt unter')));
      await fertig(tester);
    },
  );

  testWidgets('SIC-087 Zweite Bibliothek ohne CLIP-Modell', (tester) async {
    await starteApp(tester);
    await importiereDirekt(tester, [testfoto('c.jpg')]);
    final kanal = Ordnerkanal(tester);
    kanal.ordner = ordner('zweite').path;
    melde.verlaufLeeren();
    expect(bibliothek.clipAvailable, isFalse);
    await zweiteBibliothekOeffnen(tester);
    await tap(tester, find.text(de.zweitOrdnerKnopf));
    await waitFor(tester, find.text(de.allgClipNoetigKurz));
    expect(gemeldet(de.allgClipNoetigKurz, Meldungsart.warnung), isTrue);
    expect(kanal.gerufen, isNot(contains('pickFolderAndCreateBookmark')));
    expect(find.text(de.zweitErklaerung), findsOneWidget);
    await fertig(tester);
  });

  testWidgets(
    'SIC-088 SIC-091 SIC-093 SIC-092 Zweite Bibliothek vergleichen mit CLIP',
    (tester) async {
      await starteApp(
        tester,
        modelle: const [
          'clip_image_encoder.onnx',
          'clip_text_encoder.onnx',
          'vocab.json',
          'merges.txt',
        ],
      );
      final kanal = Ordnerkanal(tester);
      expect(bibliothek.clipAvailable, isTrue);

      Future<void> analysiert() async {
        unawaited(bibliothek.starteHintergrundanalyse());
        await eventually(
          tester,
          () async {
            final e = await bibliothek.db.allEmbeddings();
            final a = (await bibliothek.db.select(bibliothek.db.assets).get())
                .where((x) => !x.isTrashed);
            return a.every((x) => e.containsKey(x.id));
          },
          timeout: const Duration(minutes: 5),
          was: 'CLIP-Einbettungen',
        );
        await eventually(
          tester,
          () async => !bibliothek.analyseLaeuft,
          timeout: const Duration(minutes: 5),
        );
      }

      final wurzel = bibliothek.paths.root.parent;
      Future<Directory> abzug(String name) async {
        final d = ordner(name);
        await tester.runAsync(
          () => bibliothek.db.customStatement('VACUUM INTO ?', [
            p.join(d.path, 'library.sqlite'),
          ]),
        );
        kopiere(
          bibliothek.paths.thumbnailsDir,
          Directory(p.join(d.path, 'library', 'thumbnails')),
        );
        return d;
      }

      // Bibliothek „ohne gemeinsame Fotos“: X1–X3.
      await importiereDirekt(tester, [
        musterfoto('x_schach.jpg', 'schach', datum: DateTime(2019, 1, 1, 10)),
        musterfoto(
          'x_rauschen.jpg',
          'rauschen',
          datum: DateTime(2019, 1, 2, 10),
        ),
        musterfoto(
          'x_streifen.jpg',
          'streifen',
          datum: DateTime(2019, 1, 3, 10),
        ),
      ]);
      await analysiert();
      final ohneGemeinsame = await abzug('ohne_gemeinsame');
      // Zweite Bibliothek: dazu S1 und eine Variante von S2.
      await importiereDirekt(tester, [
        testfoto('gleich_1.jpg', datum: DateTime(2019, 2, 1, 10)),
        musterfoto(
          'gleich_2b.jpg',
          'kreis_variante',
          datum: DateTime(2019, 2, 2, 10),
        ),
      ]);
      await analysiert();
      final zweite = await abzug('zweite');
      final fremd = await tester.runAsync(() => bibliothek.db.allEmbeddings());
      final fremdeAufnahmen = await aufnahmen(tester);
      // Eigene Bibliothek: S1, S2, O1–O3.
      await endgueltigWeg(tester, [
        for (final a in fremdeAufnahmen)
          if (a.originalFileName != 'gleich_1.jpg') a,
      ]);
      await importiereDirekt(tester, [
        musterfoto('gleich_2.jpg', 'kreis', datum: DateTime(2019, 3, 1, 10)),
        musterfoto('o_text.jpg', 'text', datum: DateTime(2019, 3, 2, 10)),
        musterfoto(
          'o_landschaft.jpg',
          'landschaft',
          datum: DateTime(2019, 3, 3, 10),
        ),
      ]);
      await analysiert();
      final eigen = await tester.runAsync(() => bibliothek.db.allEmbeddings());
      final eigeneAufnahmen = await aufnahmen(tester);
      String name(String id, List<AssetData> l) =>
          l.firstWhere((a) => a.id == id).originalFileName;
      for (final e in eigen!.entries) {
        for (final f in fremd!.entries) {
          print(
            'Kosinus ${name(e.key, eigeneAufnahmen)} ~ '
            '${name(f.key, fremdeAufnahmen)}: ${kosinus(e.value, f.value).toStringAsFixed(3)}',
          );
        }
      }
      final dbVorher = _sha(File(p.join(zweite.path, 'library.sqlite')));
      expect(wurzel.path, startsWith(anker.path));

      await zweiteBibliothekOeffnen(tester);

      // SIC-092: Ordner ohne Bibliothek.
      final leer = ordner('leer');
      kanal.ordner = leer.path;
      await tap(tester, find.text(de.zweitOrdnerKnopf));
      final fehler = textPasst(
        satzMuster(de.zweitVergleichFehlgeschlagen('\u0001')),
      );
      await waitFor(tester, fehler);
      final fehlerText = tester.widget<Text>(fehler).data!;
      print('SIC-092 (de): $fehlerText');
      expect(fehlerText, contains('library.sqlite'));
      expect(find.text(de.allgErneutVersuchen), findsOneWidget);

      // SIC-088: „Erneut versuchen“ mit der zweiten Bibliothek.
      kanal.ordner = zweite.path;
      await tap(tester, find.text(de.allgErneutVersuchen));
      final treffer = find.text(de.zweitTreffer(2));
      await waitFor(tester, treffer, timeout: const Duration(seconds: 60));
      expect(
        textPasst(satzMuster(de.zweitAehnlichProzent('\u0001'))),
        findsNWidgets(2),
      );
      expect(find.text(de.zweitBibliothek), findsNWidgets(2));
      expect(find.text('gleich_1.jpg'), findsOneWidget);
      expect(find.text('gleich_2b.jpg'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SecondLibraryCompareScreen),
          matching: find.byType(AssetThumbnailTile),
        ),
        findsNWidgets(2),
      );
      expect(_sha(File(p.join(zweite.path, 'library.sqlite'))), dbVorher);

      // SIC-091: Schwelle auf 0.99, ohne neues Laden.
      expect(find.text(de.zweitSchwelleHinweis), findsOneWidget);
      expect(find.text('0.92'), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      // Beim Laden ersetzt der Ladekreis die ganze Liste samt Regler.
      var ladekreis = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byType(Slider).evaluate().isEmpty) ladekreis = true;
      }
      await settle(tester);
      expect(find.text('0.99'), findsOneWidget);
      expect(ladekreis, isFalse);
      final s2 = eigeneAufnahmen.singleWhere(
        (a) => a.originalFileName == 'gleich_2.jpg',
      );
      final s2b = fremdeAufnahmen.singleWhere(
        (a) => a.originalFileName == 'gleich_2b.jpg',
      );
      final aehnlich = kosinus(eigen[s2.id]!, fremd![s2b.id]!);
      print('SIC-091: Kosinus S2 ~ S2b = $aehnlich');
      expect(
        find.text(de.zweitTreffer(aehnlich >= 0.99 ? 2 : 1)),
        findsOneWidget,
      );

      // SIC-093: keine Treffer, dann „Anderer Ordner“.
      kanal.ordner = ohneGemeinsame.path;
      await tap(tester, find.text(de.zweitAndererOrdner));
      await waitFor(
        tester,
        find.text(de.zweitKeineTreffer),
        timeout: const Duration(seconds: 60),
      );
      final gerufen = kanal.gerufen
          .where((m) => m == 'pickFolderAndCreateBookmark')
          .length;
      kanal.ordner = null;
      await tap(tester, find.text(de.zweitAndererOrdner));
      expect(
        kanal.gerufen.where((m) => m == 'pickFolderAndCreateBookmark').length,
        gerufen + 1,
      );
      expect(find.text(de.zweitKeineTreffer), findsOneWidget);

      // SIC-092 in der englischen Oberfläche (Befund: fester deutscher
      // Satz, lib/services/second_library_scan_service.dart:84).
      await sprache(tester, 'en');
      kanal.ordner = leer.path;
      await tap(tester, find.text(en.zweitAndererOrdner));
      final fehlerEn = textPasst(
        satzMuster(en.zweitVergleichFehlgeschlagen('\u0001')),
      );
      await waitFor(tester, fehlerEn);
      print('SIC-092 (en): ${tester.widget<Text>(fehlerEn).data}');
      await fertig(tester);
    },
  );

  // =========================================================================
  // KI-Restaurierung – Warteschlange
  // =========================================================================
  testWidgets(
    'SIC-083 SIC-084 SIC-085 SIC-082 KI-Restaurierung: Band, Abbrechen, '
    'Entfernen, leere Liste',
    (tester) async {
      await starteApp(tester, modelle: const ['real_esrgan_x4.onnx']);
      await importiereDirekt(tester, [
        testfoto(
          'gross_a.jpg',
          datum: DateTime(2024, 3, 2, 10),
          // Zwei Kacheln nebeneinander (512er Kacheln): Nach der ersten
          // hält der Auftrag beim Antippen des Bands an und lässt sich
          // abbrechen. Bei 1600×1200 und bei 800×560 wuchs die App während
          // der Restaurierung über 12 GB und wurde vom Wächter der
          // Warteschlange beendet.
          breite: 900,
          hoehe: 360,
        ),
        testfoto(
          'klein_b.jpg',
          datum: DateTime(2024, 3, 1, 10),
          breite: 240,
          hoehe: 180,
        ),
      ]);
      melde.verlaufLeeren();
      final band = find.textContaining(
        'in der Warteschlange für die KI-Restaurierung',
      );
      expect(band, findsNothing);
      expect(find.text(de.restaurierungWirdVorbereitet), findsNothing);
      expect(bibliothek.restoreQueue.restoreHalter?.installiert, isTrue);
      final vorher = await aufnahmen(tester);
      AssetData von(List<AssetData> l, String n) =>
          l.singleWhere((x) => x.originalFileName == n);
      final summeA = _sha(
        bibliothek.paths.absolute(von(vorher, 'gross_a.jpg').relativePath),
      );
      final summeB = _sha(
        bibliothek.paths.absolute(von(vorher, 'klein_b.jpg').relativePath),
      );

      Future<void> einreihen(String name) async {
        await openSection(tester, Hauptbereich.zeitleiste);
        final kachel = find.byWidgetPredicate(
          (w) => w is AssetThumbnailTile && w.asset.id == von(vorher, name).id,
        );
        await tap(tester, kachel);
        await tap(tester, find.byTooltip(de.viewerEntwickeln));
        await waitFor(tester, find.byType(DevelopScreen));
        await tap(tester, find.byTooltip(de.entwRestaurierungAnwenden));
        await waitFor(tester, find.text(de.modellEsrganTitel));
        await tap(tester, imDialog(find.text(de.allgStarten)));
        await eventually(
          tester,
          () async =>
              gemeldet(de.entwRestaurierungEingereiht, Meldungsart.erfolg),
          was: 'Meldung „eingereiht“',
        );
        await seiteZurueck(tester);
        await settle(tester);
        await waitGone(tester, find.byType(DevelopScreen));
        await seiteZurueck(tester);
        await settle(tester);
        await waitGone(tester, find.byTooltip(de.viewerEntwickeln));
      }

      await einreihen('gross_a.jpg');
      await einreihen('klein_b.jpg');

      // SIC-083
      await waitFor(tester, find.text(de.restaurierungWartend(2)));
      final laeuft = textPasst(
        satzMuster(
          de
              .restaurProzentMitWarteschlange(1234, 1)
              .replaceFirst('1234', '\u0001'),
        ),
      );
      await waitFor(tester, laeuft, timeout: const Duration(minutes: 3));

      // SIC-084: den laufenden Auftrag abbrechen.
      await tap(tester, laeuft);
      await waitFor(tester, find.byType(RestoreQueueScreen));
      Finder zeile(String name) => find.ancestor(
        of: find.descendant(
          of: find.byType(RestoreQueueScreen),
          matching: find.text(name),
        ),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, zeile('gross_a.jpg'));
      melde.verlaufLeeren();
      await settle(tester);
      await tap(
        tester,
        find.descendant(
          of: zeile('gross_a.jpg'),
          matching: find.byTooltip(de.allgAbbrechen),
        ),
      );
      await waitFor(
        tester,
        find.descendant(
          of: zeile('gross_a.jpg'),
          matching: find.text(de.restaurAbgebrochen),
        ),
        timeout: const Duration(minutes: 2),
      );
      final a = (await aufnahmen(
        tester,
      )).singleWhere((x) => x.originalFileName == 'gross_a.jpg');
      expect(a.restoredRelativePath, isNull);
      expect(_sha(bibliothek.paths.absolute(a.relativePath)), summeA);

      // B läuft nach der Ruhepause durch.
      await waitFor(
        tester,
        find.descendant(
          of: zeile('klein_b.jpg'),
          matching: find.text(de.allgFertig),
        ),
        timeout: const Duration(minutes: 4),
      );
      final b = (await aufnahmen(
        tester,
      )).singleWhere((x) => x.originalFileName == 'klein_b.jpg');
      expect(b.restoredRelativePath, isNotNull);

      // SIC-085. Vorher die Meldungen weg: Ihre Karte (oben rechts) lag
      // über dem Knopf der ersten Zeile.
      melde.verlaufLeeren();
      await settle(tester);
      await tap(
        tester,
        find.descendant(
          of: zeile('klein_b.jpg'),
          matching: find.byTooltip(de.restaurAusListe),
        ),
      );
      await waitGone(tester, zeile('klein_b.jpg'));
      final b2 = (await aufnahmen(
        tester,
      )).singleWhere((x) => x.originalFileName == 'klein_b.jpg');
      expect(b2.restoredRelativePath, b.restoredRelativePath);
      expect(
        bibliothek.paths.absolute(b2.restoredRelativePath!).existsSync(),
        isTrue,
      );
      expect(_sha(bibliothek.paths.absolute(b2.relativePath)), summeB);
      await tap(
        tester,
        find.descendant(
          of: zeile('gross_a.jpg'),
          matching: find.byTooltip(de.restaurAusListe),
        ),
      );
      await waitGone(tester, zeile('gross_a.jpg'));

      // SIC-082
      await waitFor(tester, find.text(de.restaurLeer));
      expect(find.text(de.restaurTitel), findsOneWidget);
      expect(band, findsNothing);
      expect(laeuft, findsNothing);
      await fertig(tester);
    },
  );
}

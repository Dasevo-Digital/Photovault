import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Erzeugt die Bildschirmfotos für die README.
///
/// **Kein Test, sondern ein Werkzeug** – deshalb unter `tool/` und nicht
/// unter `test/`; die normale Suite führt es nicht mit aus. Aufruf:
///
/// ```
/// flutter test tool/bildschirmfotos_test.dart
/// ```
///
/// Warum gerendert und nicht am Fenster abfotografiert: An das echte
/// Fenster kommt man in dieser Umgebung nicht zuverlässig heran (siehe
/// den Kommentar im Golden-Test des Stammbaums). Gezeichnet wird dabei
/// derselbe Widgetbaum mit demselben Thema – das Bild zeigt also die
/// App, nur aufgenommen durch die Testbühne statt durch den
/// Fensterserver. Damit die Schrift lesbar ist statt als Platzhalter zu
/// erscheinen, wird eine echte Systemschrift geladen.
///
/// **Auf diesen Bildern ist kein einziges Foto zu sehen** – die
/// Stammbaum-Ansichten kommen ohne aus, und die Familie ist frei
/// erfunden. Damit ist die Regel aus docs/screenshots/README.md nicht
/// nur eingehalten, sondern gegenstandslos.
const _breite = 1600.0;
const _hoehe = 1200.0;

/// Wohin die fertigen Bilder gehen – in den öffentlichen Spiegel, denn
/// nur dort liegen sie (siehe sync_public.py).
const _ziel = '../photo_vault_public/docs/screenshots';

/// Lädt eine echte Systemschrift, damit im Bild Buchstaben stehen und
/// nicht die Platzhalterbalken der Testbühne.
///
/// **In `runAsync`**, sonst kommt es nie zurück: Innerhalb von
/// `testWidgets` läuft die Zeit gefälscht, und eine echte Datei- oder
/// Bildoperation wartet dort auf eine Zusage, die niemand einlöst.
/// Derselbe Stolperstein wie seinerzeit bei `Picture.toImage()` in der
/// PDF-Tafel.
Future<void> _ladeSchrift(WidgetTester tester) async {
  Future<void> nimm(String familie, List<String> pfade) async {
    final lader = FontLoader(familie);
    var gefunden = false;
    for (final pfad in pfade) {
      final datei = File(pfad);
      if (!datei.existsSync()) continue;
      final bytes = await datei.readAsBytes();
      lader.addFont(Future.value(ByteData.view(bytes.buffer)));
      gefunden = true;
    }
    if (gefunden) await lader.load();
  }

  await tester.runAsync(() async {
    await nimm('Beschriftung', [
      '/System/Library/Fonts/Supplemental/Arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
    ]);
    // Ohne die Symbolschrift stehen an jeder Knopfstelle leere Kästchen –
    // das Bild sähe kaputt aus, obwohl die App in Ordnung ist. Sie liegt
    // im Flutter-Zwischenspeicher, nicht im System, und wo der liegt,
    // hängt an der Installation. Deshalb vom Testprogramm aus nach oben
    // gesucht statt einen Pfad zu behaupten.
    // Die mitgelieferten Zierschriften. Ohne sie stehen die Namen im
    // Zierbaum als schwarze Kaestchen da: Die Schilder setzen ihre
    // Schrift ausdruecklich auf 'Zierschrift', und was ein Widget
    // ausdruecklich verlangt, holt die Testbuehne nicht aus dem Thema
    // nach. Die Kopfzeile blieb dabei lesbar, weil sie die Schrift des
    // Themas nimmt - das Bild sah also nur zur Haelfte kaputt aus.
    await nimm('Zierschrift', ['assets/fonts/EBGaramond-Variable.ttf']);
    await nimm('Zierschrift Gross', ['assets/fonts/GreatVibes-Regular.ttf']);

    final symbolschrift = _sucheSymbolschrift();
    await nimm('MaterialIcons', [if (symbolschrift != null) symbolschrift]);
  });
}

/// Sucht `MaterialIcons-Regular.otf` im Flutter-Zwischenspeicher, vom
/// laufenden Testprogramm aus aufwärts.
String? _sucheSymbolschrift() {
  var ordner = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final kandidat = File(p.join(
        ordner.path, 'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf'));
    if (kandidat.existsSync()) return kandidat.path;
    final oben = ordner.parent;
    if (oben.path == ordner.path) break;
    ordner = oben;
  }
  return null;
}

Future<void> _schreibe(WidgetTester tester, Finder was, String name) async {
  final grenze =
      tester.firstElement(was).renderObject! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final bild = await grenze.toImage(pixelRatio: 1.0);
    final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
    bild.dispose();
    final datei = File(p.join(_ziel, name));
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(daten!.buffer.asUint8List());
    // ignore: avoid_print
    print('geschrieben: ${datei.path} (${daten.lengthInBytes ~/ 1024} KB)');
  });
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_bildschirmfotos');
    db = AppDatabase(NativeDatabase.memory());
    // Der Prüfer sieht nur den Ordner, nicht den Zweck: Diese Datei ist
    // ein Werkzeug, kein Auslieferungscode, und braucht denselben
    // Wegwerf-Speicherort wie ein Test.
    // ignore: invalid_use_of_visible_for_testing_member
    final paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    // Eine frei erfundene Familie über vier Generationen – so gewählt,
    // dass alle Eigenheiten der Ansicht sichtbar werden: zwei Elternteile
    // je Zweig, Geschwister, Partner, Kinder, ein Adoptivelternteil und
    // eine Seitenlinie mit Nichte.
    for (final (id, name, jahr, tot, g) in <(String, String, int, int?, String?)>[
      ('urgross1', 'Wilhelm Hauser', 1878, 1951, 'm'),
      ('urgross2', 'Therese Hauser', 1881, 1962, 'w'),
      ('opa', 'Friedrich Hauser', 1907, 1984, 'm'),
      ('oma', 'Elisabeth Hauser', 1911, 1996, 'w'),
      ('opa2', 'Karl Brandt', 1905, 1978, 'm'),
      ('oma2', 'Johanna Brandt', 1913, 2001, 'w'),
      ('vater', 'Ernst Hauser', 1938, 2019, 'm'),
      ('mutter', 'Margarete Hauser', 1941, null, 'w'),
      ('ziehmutter', 'Hedwig Vogt', 1936, 2011, 'w'),
      ('ich', 'Anna Hauser', 1968, null, 'w'),
      ('bruder', 'Thomas Hauser', 1971, null, 'm'),
      ('gatte', 'Peter Reimann', 1965, null, 'm'),
      ('schwaegerin', 'Ruth Hauser', 1974, null, 'w'),
      ('kind1', 'Lena Reimann', 1996, null, 'w'),
      ('kind2', 'Jonas Reimann', 1999, null, 'm'),
      ('nichte', 'Sophie Hauser', 2001, null, 'w'),
      ('enkel', 'Mia Reimann', 2022, null, 'w'),
    ]) {
      await db.createPerson(PeopleCompanion.insert(
        id: id,
        name: name,
        geburtsdatum: Value(DateTime(jahr)),
        sterbedatum: Value(tot == null ? null : DateTime(tot)),
        geschlecht: Value(g),
      ));
    }

    Future<void> eltern(String kind, String e, [Verwandtschaft art = Verwandtschaft.elternteil]) =>
        db.fuegeBeziehungHinzu(kind, e, art);

    await eltern('opa', 'urgross1');
    await eltern('opa', 'urgross2');
    await eltern('vater', 'opa');
    await eltern('vater', 'oma');
    await eltern('mutter', 'opa2');
    await eltern('mutter', 'oma2');
    await eltern('ich', 'vater');
    await eltern('ich', 'mutter');
    await eltern('bruder', 'vater');
    await eltern('bruder', 'mutter');
    // Eine Adoptivmutter – im Bild gestrichelt, in der Liste eigens benannt.
    await eltern('ich', 'ziehmutter', Verwandtschaft.adoptivelternteil);
    await eltern('kind1', 'ich');
    await eltern('kind1', 'gatte');
    await eltern('kind2', 'ich');
    await eltern('kind2', 'gatte');
    await eltern('nichte', 'bruder');
    await eltern('nichte', 'schwaegerin');
    await eltern('enkel', 'kind1');
    await db.fuegeBeziehungHinzu('ich', 'gatte', Verwandtschaft.partner);
    await db.fuegeBeziehungHinzu('vater', 'mutter', Verwandtschaft.partner);
    await db.fuegeBeziehungHinzu('bruder', 'schwaegerin', Verwandtschaft.partner);
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester, {Size groesse = const Size(_breite, _hoehe)}) async {
    await _ladeSchrift(tester);
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final thema = buildDarkTheme();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: thema.copyWith(
        textTheme: thema.textTheme.apply(fontFamily: 'Beschriftung'),
        primaryTextTheme: thema.primaryTextTheme.apply(fontFamily: 'Beschriftung'),
      ),
      home: RepaintBoundary(
        child: StammbaumScreen(library: library, startPersonId: 'ich'),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> waehleSicht(WidgetTester tester, String beschriftung) async {
    await tester.tap(find.text(beschriftung));
    await tester.pumpAndSettle();
  }

  testWidgets('Stammbaum – Baum', (tester) async {
    // Flacher als die übrigen: Der Ausschnitt um eine Person ist breit
    // und niedrig, in einem 4:3-Fenster bliebe oben und unten viel Leere.
    await zeige(tester, groesse: const Size(_breite, 820));
    await _schreibe(tester, find.byType(RepaintBoundary).first, 'stammbaum.png');
  });

  // Vom Fächer gibt es bewusst KEINE Aufnahme. Er beschriftet seine Ringe
  // mit einem TextPainter, und dessen Schrift kommt weder aus dem Thema
  // noch aus einem FontLoader – in der Testbühne bleiben dort
  // Platzhalterbalken stehen. Ein Bild, das die App kaputt aussehen
  // lässt, obwohl sie es nicht ist, wäre schlechter als keines.
  // (Geprüft: Ein Überschreiben der Familien „FlutterTest", „Roboto" und
  // „Ahem" ändert nichts – ein TextStyle ohne Familienangabe greift auf
  // die Schrift der Bühne zurück.)

  testWidgets('Stammbaum – Sanduhr', (tester) async {
    await zeige(tester, groesse: const Size(_breite, 1050));
    await waehleSicht(tester, 'Sanduhr');
    await _schreibe(tester, find.byType(RepaintBoundary).first, 'stammbaum-sanduhr.png');
  });

  testWidgets('Stammbaum – Verwandte', (tester) async {
    await zeige(tester);
    await waehleSicht(tester, 'Verwandte');
    await _schreibe(tester, find.byType(RepaintBoundary).first, 'stammbaum-verwandte.png');
  });
}

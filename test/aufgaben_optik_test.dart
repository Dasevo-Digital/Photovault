import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/florence_captioning_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/eye_state_service.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/ocr_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

import 'goldbilder.dart';

/// Die Aufgabenübersicht nach dem Umbau: Inhalt links, Aktionsleiste rechts
/// über die volle Kartenhöhe.
///
/// Die Anordnung hat eine Sollbruchstelle, die man im Code nicht sieht: Die
/// Leiste ist fest 112 Punkte breit, die Beschreibungen umbrechen frei, und
/// die Kartenhöhe kommt aus IntrinsicHeight. In einem schmalen Fenster ist
/// ein Überlauf die naheliegende Folge – und Überläufe fallen im Betrieb
/// nur als roter Balken auf, den niemand meldet.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  ModellHalter<T> halter<T>(String name, {required bool installiert}) => ModellHalter<T>(
        name: name,
        installiert: installiert,
        laden: () async => throw StateError('im Test wird nichts geladen'),
        entsorgen: (_) async {},
      );

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_aufgaben_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths)
      // Gemischt: So sind beide Zustände der Leiste im Bild – bedienbar und
      // abgeschaltet, weil ein Modell fehlt.
      ..faceEngineHalter = halter<FaceEngineService>('Gesichter', installiert: true)
      ..eyeStateHalter = halter<EyeStateService>('Augen', installiert: false)
      ..clipBildHalter = halter<ClipService>('CLIP-Bild', installiert: false)
      ..clipTextHalter = halter<ClipService>('CLIP-Text', installiert: false)
      ..captioningHalter = halter<FlorenceCaptioningService>('Bildbeschreibung', installiert: false)
      // Ausdrücklich gesetzt: Ohne das hinge die Karte an
      // Platform.isMacOS und der Test prüfte je nach Rechner etwas
      // anderes.
      ..ocrHalter = halter<OcrService>('OCR', installiert: true);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester, Size groesse) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      // Das echte Thema der App, nicht ein zusammengestelltes: Die Karten
      // greifen über context.semantik auf eine Theme-Erweiterung zu, die
      // sonst fehlt – und die Farbrollen sollen genau die geprüften sein.
      theme: buildDarkTheme(),
      home: BackgroundTasksScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('die Karten bauen ohne Überlauf – auch im schmalen Fenster', (tester) async {
    // 640 Punkte ist die kleinste Breite, in der das Hauptfenster noch
    // sinnvoll bedienbar ist.
    await zeige(tester, const Size(640, 900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Karten bauen ohne Überlauf – im breiten Fenster', (tester) async {
    await zeige(tester, const Size(1600, 1000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('jede Karte hat Symbol, Zahlenpaar und Aktionsleiste', (tester) async {
    await zeige(tester, const Size(1000, 900));

    // Die Zahlenzeile: „Aktiv" steht auf jeder sichtbaren Karte, deren
    // Modell vorhanden ist.
    expect(find.text('Aktiv'), findsWidgets);
    expect(find.text('Wartend'), findsWidgets);

    // Und die Leiste sitzt rechts vom Inhalt, nicht darunter.
    final ersteLeiste = find.byIcon(Icons.image_search).first;
    final leisteMitte = tester.getCenter(ersteLeiste);
    final karteMitte = tester.getCenter(find.byType(Card).first);
    expect(leisteMitte.dx, greaterThan(karteMitte.dx),
        reason: 'die Aktionsleiste gehört an den rechten Rand der Karte');
  });

  testWidgets('jede Karte nennt die Zahl der offenen Fotos', (tester) async {
    // Die dritte Zeile, die es vorher nicht gab: „Aktiv" und „Wartend"
    // zählen seit der Warteschlange Aufgaben, nicht Fotos. Ohne diese
    // Zeile wäre die nützlichste Zahl der Seite verschwunden.
    for (var i = 0; i < 3; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'o$i',
            originalFileName: 'o$i.jpg',
            relativePath: 'originals/o$i.jpg',
            checksum: 'o$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));
    }
    await zeige(tester, const Size(1400, 2600));
    expect(find.text('3 Fotos offen'), findsWidgets);
  });

  testWidgets('„offen" steht nur da, wo die Zahl auch auf null gehen kann',
      (tester) async {
    // Der Fund der 17. Prüfrunde. Drei Karten zählten Kandidaten und
    // nannten es „offen": Orte einlesen zeigte 5838, Kameradaten 842,
    // Live-Photo-Paare 6804 – und nach einem vollständig geglückten
    // Durchgang stand dort fast dieselbe Zahl. Von 60 Fotos ohne Ort
    // trugen sieben überhaupt GPS in der Datei. Eine Karte, die nach
    // getaner Arbeit aussieht wie vorher, sieht aus wie kaputt.
    //
    // „Betrifft: n" verspricht nichts, was nicht eintritt.
    await zeige(tester, const Size(1400, 2600));
    final texte = AppTexte.of(tester.element(find.byType(Scaffold).first));
    const kandidaten = {'orte', 'kameradaten', 'livephotos', 'aufnahmedatum',
        'entwickelt', 'xmp'};
    for (final aufgabe in aufgabenliste(texte, library)) {
      if (!kandidaten.contains(aufgabe.schluessel)) continue;
      expect(aufgabe.offenLabel, texte.aufgBetrifft,
          reason: 'Die Aufgabe "${aufgabe.schluessel}" zählt Fotos, die sie '
              'ansieht – nicht Fotos, die danach fertig sind.');
    }
  });

  testWidgets('die Kopfzeile passt auch ins schmale Fenster', (tester) async {
    // Bei 640 Punkten lief sie über: zwei Knöpfe mit langer Beschriftung
    // neben dem Titel. Dort bleiben nur die Symbole – der Text steht im
    // Kurzhinweis und damit auch für die Sprachausgabe bereit.
    await zeige(tester, const Size(640, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('Aufgabe erstellen'), findsNothing);
    expect(find.byTooltip('Aufgabe erstellen'), findsOneWidget);

    await zeige(tester, const Size(1400, 900));
    expect(find.text('Aufgabe erstellen'), findsOneWidget);
  });

  testWidgets('was sich neu rechnen lässt, bietet auch „Alle" an',
      (tester) async {
    // Gemeldeter Fehler: Die Karte „CLIP-Embeddings" hatte nur „Starten".
    // Das rechnet ausschliesslich fehlende Fotos – nach der Umstellung
    // der Bildvorverarbeitung also fast nichts, und es sah trotzdem nach
    // getaner Arbeit aus. Bei den Bildbeschreibungen war der zweite Knopf
    // längst da; genau diese Ungleichheit fiel niemandem auf.
    await zeige(tester, const Size(1400, 2400));

    for (final titel in ['CLIP-Embeddings', 'Bildbeschreibungen', 'KI-Tags']) {
      final karte = find.ancestor(
        of: find.text(titel),
        matching: find.byType(Card),
      );
      expect(karte, findsOneWidget, reason: 'Karte „$titel" fehlt');
      expect(
        find.descendant(of: karte, matching: find.text('Alle')),
        findsOneWidget,
        reason: 'Karte „$titel" bietet kein Neurechnen aller Fotos an',
      );
    }
  });

  testWidgets('eine Aufgabe ohne Modell zeigt den Grund statt der Zahlen', (tester) async {
    // Hoch genug, dass die Liste alle Karten baut – find greift nur auf
    // Gebautes zu, und die CLIP-Karten liegen weit unten.
    await zeige(tester, const Size(1000, 2600));
    // CLIP fehlt (siehe setUp) – die betroffenen Karten nennen das Modell.
    expect(find.textContaining('CLIP-Modell'), findsWidgets);
  });

  testWidgets('die Zahlenfelder tragen die echten Werte', (tester) async {
    // Drei Fotos, die noch keine Texterkennung hatten. „Aktiv" und
    // „Wartend" stehen auf 0 – es läuft ja nichts –, und die Zahl der
    // offenen Fotos steht in der Zeile darunter.
    for (var i = 0; i < 3; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a$i',
            originalFileName: 'a$i.jpg',
            relativePath: 'originals/a$i.jpg',
            checksum: 'c$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));
    }
    await zeige(tester, const Size(1000, 2600));

    final ocrKarte = find.ancestor(
      of: find.text('Text erkennen (OCR)'),
      matching: find.byType(Card),
    );
    expect(ocrKarte, findsOneWidget, reason: 'die Karte muss gebaut sein');
    expect(find.descendant(of: ocrKarte, matching: find.text('0')), findsNWidgets(2),
        reason: 'Aktiv und Wartend zählen Aufgaben – hier läuft keine');
    expect(find.descendant(of: ocrKarte, matching: find.text('3 Fotos offen')),
        findsOneWidget);
  });

  testWidgets('so sieht die Karte aus', (tester) async {
    // Ein Abbild statt einer Behauptung. Klickautomatisierung ist in dieser
    // Umgebung unzuverlässig, an das echte Fenster kommt man nicht heran –
    // das gerenderte Bild ist die einzige Möglichkeit, die Anordnung
    // tatsächlich anzusehen statt sie aus dem Quelltext zu erschliessen.
    // Die Schrift ist im Test ein Platzhalter; es geht um Kästen, nicht um
    // Buchstaben.
    await zeige(tester, const Size(900, 640));
    await expectLater(
      find.byType(BackgroundTasksScreen),
      matchesGoldenFile('golden/aufgaben.png'),
    );
  }, skip: nurAufReferenzplattform);
}

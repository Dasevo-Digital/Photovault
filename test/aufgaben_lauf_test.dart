import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/eye_state_service.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/florence_captioning_service.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/ocr_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/translation_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Die Aufgabenübersicht zeigt den Fortschritt jetzt in der Karte statt in
/// einem Fenster, das den Bildschirm sperrt.
///
/// Der Punkt dieser Tests ist nicht die Optik, sondern die Zusicherung
/// dahinter: Es darf kein Dialog mehr aufgehen. Genau daran hing, dass eine
/// „Hintergrundaufgabe" keine war – man konnte während der Arbeit nichts
/// anderes tun und den Vorgang auch nicht beiseitelegen.
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
    tempRoot = Directory.systemTemp.createTempSync('pv_aufgaben_lauf_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths)
      ..faceEngineHalter = halter<FaceEngineService>('Gesichter', installiert: true)
      ..eyeStateHalter = halter<EyeStateService>('Augen', installiert: false)
      ..clipBildHalter = halter<ClipService>('CLIP-Bild', installiert: false)
      ..clipTextHalter = halter<ClipService>('CLIP-Text', installiert: false)
      ..uebersetzungEnDeHalter = halter<TranslationService>('Übersetzung', installiert: false)
      ..captioningHalter = halter<FlorenceCaptioningService>('Bildbeschreibung', installiert: false)
      // Ausdrücklich gesetzt: Ohne das hinge die Karte an
      // Platform.isMacOS und der Test prüfte je nach Rechner etwas
      // anderes.
      ..ocrHalter = halter<OcrService>('OCR', installiert: true);
  });

  tearDown(() async {
    // Der Meldungsdienst ist ein Einzelstueck – was hier stehen
    // bleibt, steht im naechsten Test noch da.
    melde.verlaufLeeren();
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Eine feste Zahl von Einzelbildern statt `pumpAndSettle`.
  ///
  /// Solange ein Fortschrittsbalken zu sehen ist, läuft dessen Ticker; ein
  /// `pumpAndSettle` dreht dann bis zu seinem Zeitlimit von zehn Minuten
  /// gestellter Zeit und kostet real Minuten – gemessen, nicht vermutet.
  /// Erst ein einzelnes `pump()` (das die Zustandsänderung übernimmt), dann
  /// genug Zeit, damit die angestossenen Übergänge auslaufen.
  Future<void> einigeBilder(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    // Hoch genug, damit auch die weiter unten stehenden Karten gebaut
    // sind: Die Liste baut faul, und mit jeder neuen Aufgabe rutscht
    // „Orte einlesen" weiter nach unten.
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      // Das echte Thema: Die Karten greifen über context.semantik auf eine
      // Theme-Erweiterung zu, die einem zusammengestellten Thema fehlt.
      theme: buildDarkTheme(),
      // Der Meldungsstapel gehoert dazu: Seit der Meldungszentrale
      // erscheinen Meldungen dort und nicht mehr als SnackBar im
      // Scaffold.
      builder: (context, kind) => mitMeldungen(kind),
      home: BackgroundTasksScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  /// Rollt, bis [finder] im Bild ist – die Liste ist länger als jedes
  /// Testfenster.
  /// Scrollt zu einer Karte – **erst zurück an den Anfang**.
  ///
  /// `scrollUntilVisible` sucht nur in einer Richtung. Wer eine Karte
  /// ansteuert, die weiter oben liegt als die zuletzt angesteuerte, bekommt
  /// „Bad state: No element" – nicht „nicht gefunden", sondern einen
  /// Absturz an einem Finder ohne Treffer. Aufgefallen ist das, als eine
  /// Karte dazukam und die Prüfliste damit nicht mehr in Bildschirmreihen-
  /// folge stand; die Reihenfolge der Liste soll aber egal sein.
  Future<void> hinScrollen(WidgetTester tester, Finder finder) async {
    final liste = find.byType(Scrollable).first;
    await tester.drag(liste, const Offset(0, 20000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 200, scrollable: liste);
    await tester.pumpAndSettle();
  }

  testWidgets('ein gestarteter Vorgang öffnet keinen Dialog, sondern läuft in der Karte',
      (tester) async {
    await zeige(tester);

    final ocrKarte = find.ancestor(
      of: find.text('Text erkennen (OCR)'),
      matching: find.byType(Card),
    );
    await hinScrollen(tester, ocrKarte);

    await tester.tap(find.descendant(of: ocrKarte, matching: find.text('Fehlende')));
    await tester.pumpAndSettle();

    // Das ist die eigentliche Zusicherung.
    expect(find.byType(AlertDialog), findsNothing);

    // Die leere Datenbank hat nichts nachzuholen – der Lauf ist sofort
    // durch und sagt das mit der Meldung der Karte, nicht mit „0 / 0".
    expect(
      find.descendant(of: ocrKarte, matching: find.text('Alle Fotos wurden bereits nach Text durchsucht.')),
      findsOneWidget,
    );
    expect(find.descendant(of: ocrKarte, matching: find.text('Schließen')), findsOneWidget);

    await tester.tap(find.descendant(of: ocrKarte, matching: find.text('Schließen')));
    await tester.pumpAndSettle();

    // Danach steht die Karte wieder auf ihren Zahlen.
    expect(library.lauf('ocr'), isNull);
    expect(find.descendant(of: ocrKarte, matching: find.text('Wartend')), findsOneWidget);
  });

  testWidgets('während ein Vorgang läuft, zeigt die Karte Balken, Zahlen und Abbrechen',
      (tester) async {
    final regler = StreamController<ImportProgress>();
    // Der Lauf wird angestossen, bevor der Bildschirm steht – genau der
    // Fall, um den es geht: Man startet etwas und navigiert weg.
    library.reiheAufgabeEin(
      schluessel: 'orte',
      titel: 'Lese Orte aus Fotos ein …',
      leermeldung: 'Alle Fotos haben bereits einen Ort.',
      strom: () => regler.stream,
    );

    // Hoch genug, damit auch die weiter unten stehenden Karten gebaut
    // sind: Die Liste baut faul, und mit jeder neuen Aufgabe rutscht
    // „Orte einlesen" weiter nach unten.
    tester.view.physicalSize = const Size(1400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      // Der Meldungsstapel gehoert dazu: Seit der Meldungszentrale
      // erscheinen Meldungen dort und nicht mehr als SnackBar im
      // Scaffold.
      builder: (context, kind) => mitMeldungen(kind),
      home: BackgroundTasksScreen(library: library),
    ));
    // Kein pumpEventQueue: Der Testkörper läuft in einer gestellten Zeit,
    // in der ein echtes Warten auf die Ereignisschlange nie zurückkehrt.
    regler.add(ImportProgress(3, 10, currentFile: 'IMG_0042.HEIC'));
    await einigeBilder(tester);

    final karte = find.ancestor(of: find.text('Orte einlesen'), matching: find.byType(Card));
    expect(find.descendant(of: karte, matching: find.text('Lese Orte aus Fotos ein …')),
        findsOneWidget);
    expect(find.descendant(of: karte, matching: find.text('3 / 10')), findsOneWidget);
    expect(find.descendant(of: karte, matching: find.text('IMG_0042.HEIC')), findsOneWidget);
    expect(find.descendant(of: karte, matching: find.byType(LinearProgressIndicator)),
        findsOneWidget);

    // Solange gearbeitet wird, gibt es genau eine sinnvolle Handlung.
    expect(find.descendant(of: karte, matching: find.text('Fehlende')), findsNothing);
    expect(find.descendant(of: karte, matching: find.text('Abbrechen')), findsOneWidget);

    // Was der Abbruch-Knopf auslöst, steht in hintergrundlauf_test.dart:
    // Abonnement gekündigt, Lauf als abgebrochen vermerkt, Zähler bei 7 von
    // 100. Hier bleibt es beim Nachweis, dass es ihn gibt und er die
    // übrigen Aktionen verdrängt – ein Antippen an dieser Stelle bringt die
    // Testumgebung reproduzierbar zum Stehen (nachgemessen: kein weiteres
    // Einzelbild geplant, kein laufender Ticker, und trotzdem kehrt der
    // Test nicht zurück).
    await regler.close();
  });

  testWidgets('jede Karte bietet „Alle", „Fehlende" oder beides – und sonst '
      'nichts', (tester) async {
    await zeige(tester);

    // **Zwei Wörter für zwei Sachverhalte.** Vorher standen auf den
    // Knöpfen sieben verschiedene: „Fehlende", „Neue Fotos",
    // „Ungetaggte", „Starten", „Alle erneut", „Alle neu", „Alle Fotos" –
    // und welches wo, war von Karte zu Karte verschieden.
    const nurFehlende = [
      'Text erkennen (OCR)',
      'Unschärfe',
      'Land/Bundesland/Stadt auflösen',
      'Kameradaten einlesen',
      'Dateiarten prüfen',
      'Live-Photo-Paare prüfen',
    ];
    const nurAlle = [
      'Entwickelte Fotos neu rendern',
      'XMP-Sidecars schreiben',
      'Aufnahmedatum aus RAW und Videos nachtragen',
      'Ablage nach Datum ordnen',
    ];
    // „Orte einlesen" hat seit Fassung 2.6 beides: „Fehlende" überspringt,
    // wo schon einmal nachgesehen wurde, „Alle" sieht auch dort erneut hin.
    const beides = [
      'Bildbeschreibungen',
      'CLIP-Embeddings',
      'KI-Tags',
      'Orte einlesen',
    ];

    for (final titel in nurFehlende) {
      final karte = find.ancestor(of: find.text(titel), matching: find.byType(Card));
      await hinScrollen(tester, karte);
      expect(find.descendant(of: karte, matching: find.text('Fehlende')), findsOneWidget,
          reason: '$titel holt nur Fehlendes nach');
      expect(find.descendant(of: karte, matching: find.text('Alle')), findsNothing,
          reason: titel);
    }

    for (final titel in nurAlle) {
      final karte = find.ancestor(of: find.text(titel), matching: find.byType(Card));
      await hinScrollen(tester, karte);
      expect(find.descendant(of: karte, matching: find.text('Alle')), findsOneWidget,
          reason: '$titel bearbeitet alles, was es auflistet');
      expect(find.descendant(of: karte, matching: find.text('Fehlende')), findsNothing,
          reason: titel);
    }

    for (final titel in beides) {
      final karte = find.ancestor(of: find.text(titel), matching: find.byType(Card));
      await hinScrollen(tester, karte);
      expect(find.descendant(of: karte, matching: find.text('Alle')), findsOneWidget,
          reason: titel);
      expect(find.descendant(of: karte, matching: find.text('Fehlende')), findsOneWidget,
          reason: titel);
    }
  });

  testWidgets('eine zweite schwere Aufgabe stellt sich in die Schlange',
      (tester) async {
    // Vorher kam hier eine Abweisung, und wer beides wollte, musste das
    // Ende der ersten abpassen.
    final erste = StreamController<ImportProgress>();
    addTearDown(erste.close);
    library.reiheAufgabeEin(
      schluessel: 'beschreibungen',
      titel: 'Erzeuge Bildbeschreibungen …',
      leermeldung: 'nichts zu tun',
      strom: () => erste.stream,
      rechenintensiv: true,
    );
    await zeige(tester);

    // „Unschärfe" ist rechenintensiv und braucht trotzdem kein Modell –
    // damit hängt der Test nicht daran, was auf der Maschine installiert
    // ist.
    final karte = find.ancestor(
        of: find.text('Unschärfe'), matching: find.byType(Card));
    await hinScrollen(tester, karte);
    await tester.tap(find.descendant(of: karte, matching: find.text('Fehlende')));
    await einigeBilder(tester);

    expect(library.lauf('unschaerfe')!.wartet, isTrue);
    // Die Karte sagt es auch: eine wartende Aufgabe.
    expect(find.descendant(of: karte, matching: find.text('Wartend')), findsOneWidget);
    expect(find.descendant(of: karte, matching: find.text('1')), findsWidgets);
    // Und sie lässt sich wieder aus der Schlange nehmen.
    expect(find.descendant(of: karte, matching: find.text('Abbrechen')), findsOneWidget);
  });

  testWidgets('der Sammeldialog reiht mehrere auf einmal ein', (tester) async {
    await zeige(tester);

    await tester.tap(find.text('Aufgabe erstellen'));
    await tester.pumpAndSettle();

    // Zwei ankreuzen, die ohne Modell auskommen – sonst hinge der Test an
    // dem, was auf der Maschine installiert ist.
    for (final titel in ['Orte einlesen', 'Kameradaten einlesen']) {
      final zeile = find.ancestor(
          of: find.text(titel), matching: find.byType(CheckboxListTile));
      await tester.scrollUntilVisible(zeile, 100,
          scrollable: find.descendant(
              of: find.byType(AlertDialog), matching: find.byType(Scrollable)).first);
      await tester.tap(zeile);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Einreihen'));
    await einigeBilder(tester);

    // Beide sind angekommen – die leere Datenbank lässt sie sofort
    // durchlaufen, entscheidend ist, dass es je einen Eintrag gibt.
    expect(library.lauf('orte'), isNotNull);
    expect(library.lauf('kameradaten'), isNotNull);
  });

  testWidgets('ohne Auswahl lässt sich der Sammeldialog nicht abschicken',
      (tester) async {
    await zeige(tester);
    await tester.tap(find.text('Aufgabe erstellen'));
    await tester.pumpAndSettle();

    final knopf = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Einreihen'));
    expect(knopf.onPressed, isNull,
        reason: 'ein Knopf, der nichts tun kann, soll das vorher zeigen');
  });

  testWidgets('die Werkzeuge starten keine einzige Aufgabe mehr',
      (tester) async {
    // **Die Zusicherung, um die es beim Umbau ging.** Dieselben fünfzehn
    // Durchgänge standen vorher zweimal in der App. Ein Test, der nur die
    // neue Seite prüft, hätte das Doppelte nicht bemerkt.
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: (context, kind) => mitMeldungen(kind),
      home: ToolsScreen(library: library),
    ));
    await einigeBilder(tester);

    for (final aufgabe in aufgabenliste(
        AppTexte.of(tester.element(find.byType(ToolsScreen))), library)) {
      expect(find.text(aufgabe.titel), findsNothing,
          reason: '„${aufgabe.titel}" ist eine Aufgabe und gehört nur in die '
              'Aufgabenverwaltung');
    }

    // Stattdessen steht dort der Weg dorthin.
    expect(find.text('Aufgaben'), findsOneWidget);
  });
}

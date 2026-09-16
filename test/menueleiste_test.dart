import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Menüleiste bleibt stehen.**
///
/// Bis hierher verschwand sie, sobald man irgendetwas öffnete: Ein
/// `Navigator.push` sucht sich den nächstgelegenen Navigator, und das war
/// der des ganzen Fensters – der geöffnete Unterbildschirm legte sich über
/// alles. Seit die Fläche neben der Leiste einen eigenen Navigator hat
/// (`Arbeitsbereich`), steht die Leiste; nur wer sie ausdrücklich umgeht
/// (`rootNavigator: true`), bekommt das ganze Fenster. Genau diese beiden
/// Hälften stehen hier gegenüber – die zweite ist die Gegenprobe zur ersten.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_menue_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Abgezählte Bilder statt eines Ausschwingens: Die Zeitleiste dreht
  /// einen Ladekreis, solange sie auf die Datenbank wartet – eine endlose
  /// Bewegung, an der `pumpAndSettle` in die Zeitüberschreitung liefe,
  /// statt zurückzukehren.
  ///
  /// Drei Bilder, und das mittlere grosszügig: Wie lange ein Übergang
  /// dauert, hängt an der Plattform – unter macOS läuft der Cupertino-
  /// Übergang, und der ist länger als die 300 ms des Material-Übergangs.
  /// Eine Sekunde deckt beide. Und erst wenn der Übergang durch ist, wird
  /// die obenauf liegende Seite als deckend gemeldet – **das Bild danach**
  /// stellt die darunter beiseite. Ohne dieses dritte Bild fände der Test
  /// die verdeckte Leiste noch.
  Future<void> ruhe(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> huelle(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: HomeShell(library: library),
    ));
    await tester.pump();
  }

  /// Baut den Baum ab und lässt den Aufräum-Timer von drift auslaufen –
  /// dasselbe Vorgehen wie in `papierkorb_bedienung_test.dart`.
  ///
  /// Ohne das meldet flutter_test „A Timer is still pending even after the
  /// widget tree was disposed": Die Abmeldung eines `watch`-Stroms läuft
  /// über einen Timer mit Dauer null, und der entsteht ERST beim Abbau des
  /// Baums, den der erste Durchlauf auslöst.
  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Öffnet etwas so, wie es eine Seite tut: über ihren eigenen Kontext.
  Future<void> oeffne(WidgetTester tester,
      {required bool ganzesFenster}) async {
    final kontext = tester.element(find.byType(TimelineScreen));
    unawaited(Navigator.of(kontext, rootNavigator: ganzesFenster).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unterseite')),
      ),
    ));
    await ruhe(tester);
  }

  testWidgets('was eine Seite oeffnet, laesst die Leiste stehen',
      (tester) async {
    await huelle(tester);
    expect(find.byType(NavigationRail), findsOneWidget);

    await oeffne(tester, ganzesFenster: false);

    expect(find.text('Unterseite'), findsOneWidget,
        reason: 'Die Unterseite ist da.');
    expect(find.byType(NavigationRail), findsOneWidget,
        reason: 'Und die Leiste steht daneben, statt verdeckt zu sein.');
    await abbauen(tester);
  });

  testWidgets('die Gegenprobe: Vollbild verdeckt die Leiste sehr wohl',
      (tester) async {
    await huelle(tester);
    await oeffne(tester, ganzesFenster: true);

    expect(find.text('Unterseite'), findsOneWidget);
    // `findsNothing` heisst hier „nicht mehr zu sehen": Die Hülle bleibt
    // unter der Vollbildseite im Baum, aber beiseitegestellt, und danach
    // sucht ein Finder von sich aus nicht.
    expect(find.byType(NavigationRail), findsNothing,
        reason: 'Wer das ganze Fenster verlangt, bekommt es – der 3D-Flug '
            'und die Vollbildansicht gehen genau diesen Weg.');
    await abbauen(tester);
  });

  testWidgets('ein Wechsel des Bereichs schliesst die offene Seite',
      (tester) async {
    await huelle(tester);
    await oeffne(tester, ganzesFenster: false);

    // Über das Symbol, nicht über die Beschriftung: Die Leiste zeigt den
    // Namen nur beim ausgewählten Eintrag (labelType: selected).
    await tester.tap(find.byIcon(Icons.photo_album_outlined));
    await ruhe(tester);

    expect(find.text('Unterseite'), findsNothing,
        reason: 'Sonst zeigte die Leiste einen Bereich an, den niemand sieht.');
    expect(find.byType(AlbumsScreen), findsOneWidget);
    await abbauen(tester);
  });

  testWidgets('dasselbe Ziel noch einmal fuehrt zurueck zur Uebersicht',
      (tester) async {
    await huelle(tester);
    await oeffne(tester, ganzesFenster: false);

    // Die Zeitleiste ist der Bereich, in dem wir schon stehen – ihr Symbol
    // ist deshalb das ausgefüllte.
    await tester.tap(find.byIcon(Icons.photo));
    await ruhe(tester);

    expect(find.text('Unterseite'), findsNothing,
        reason: 'Vorher war das eine tote Taste.');
    expect(find.byType(TimelineScreen), findsOneWidget);
    await abbauen(tester);
  });

  testWidgets('schmale Fenster zeigen vier Hauptziele und ein Mehr-Menü',
      (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await huelle(tester);

    expect(find.byType(NavigationRail), findsNothing);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));

    await tester.tap(find.byIcon(Icons.more_horiz));
    await ruhe(tester);
    expect(find.byIcon(Icons.build_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.manage_search_outlined), findsOneWidget);
    await abbauen(tester);
  });

  /// **Ein Bildschirm tief im Bereich kann die Leiste nicht selbst
  /// umschalten** – sie liegt über ihm. Der Gesundheitsbildschirm meldet
  /// offene Gesichter und will den Weg zu den Personen anbieten, ohne den
  /// Gruppierlauf ein zweites Mal zu bauen. Dafür gibt es
  /// [LibraryState.zeigeBereich]; hier steht, dass die Hülle darauf hört.
  testWidgets('ein Bereichswunsch von unten schaltet die Leiste um',
      (tester) async {
    await huelle(tester);
    await oeffne(tester, ganzesFenster: false);
    expect(find.text('Unterseite'), findsOneWidget);

    // Alben als Ziel und nicht Personen: Der Personen-Bildschirm liest
    // beim Aufbau Gesichtsausschnitte von der Platte, und echte
    // Ein-/Ausgabe haengt unter der gestellten Testuhr wortlos (siehe
    // papierkorb_bedienung_test). Geprueft wird der Kanal, nicht sein Ziel.
    library.zeigeBereich(Hauptbereich.alben);
    // Zweimal: Anders als ein Tippen wirkt der Wunsch erst am ENDE des
    // ersten Bildes (er wird im Aufbau des Bereichs gelesen und per
    // Rückruf nach dem Bild eingelöst). Der Übergang der abzuräumenden
    // Seite beginnt damit ein Bild später als sonst.
    await ruhe(tester);
    await ruhe(tester);

    expect(find.byType(AlbumsScreen), findsOneWidget);
    expect(find.text('Unterseite'), findsNothing,
        reason: 'Der Wechsel raeumt den Bereich auf wie ein Tippen auch.');
    await abbauen(tester);
  });

  testWidgets('der Wunsch gilt genau einmal', (tester) async {
    await huelle(tester);
    library.zeigeBereich(Hauptbereich.kalender);
    await ruhe(tester);
    await ruhe(tester);

    // Zurueck auf die Zeitleiste tippen – der verbrauchte Wunsch darf nicht
    // noch einmal greifen und einen wieder wegschieben.
    await tester.tap(find.byIcon(Icons.photo_outlined));
    await ruhe(tester);

    expect(find.byType(TimelineScreen), findsOneWidget);
    await abbauen(tester);
  });
}

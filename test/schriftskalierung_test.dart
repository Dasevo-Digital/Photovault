import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

import 'package:photo_vault/screens/aktivitaeten_screen.dart';
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/bibliothek_belegt_screen.dart';
import 'package:photo_vault/screens/calendar_screen.dart';
import 'package:photo_vault/screens/camera_presets_screen.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/screens/export_presets_screen.dart';
import 'package:photo_vault/screens/integrity_check_screen.dart';
import 'package:photo_vault/screens/laenderliste_screen.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/screens/reisen_screen.dart';
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/stack_review_screen.dart';
import 'package:photo_vault/screens/statistics_screen.dart';
import 'package:photo_vault/screens/staubsuche_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/screens/xmp_import_screen.dart';

/// **Was passiert bei grosser Systemschrift?**
///
/// In der 18. Prüfrunde lief jedes Schild des Zierbaums ab dem
/// 1,21-fachen über. Repariert und geprüft wurde damals der Zierbaum;
/// der Rest der App nicht – vor der 23. Prüfrunde setzte genau **ein**
/// Test im ganzen Projekt überhaupt einen [TextScaler].
///
/// Dieser hier fährt jeden Bildschirm ab, der mit nichts weiter als der
/// Bibliothek auskommt, und zwar bei 1,0 / 1,3 / 1,6 und in zwei
/// Fensterbreiten. Ein Überlauf fällt im Betrieb nur als schwarzgelber
/// Balken auf, den niemand meldet – und in der ausgelieferten Fassung
/// ist selbst der weg: Dort wird stillschweigend abgeschnitten.
///
/// Gefunden hat er dreierlei, und alle drei waren derselbe Fehler –
/// eine Länge, die in Punkten festgeschrieben war, obwohl sie an der
/// Schriftgrösse hängt:
///
///   * die Kopfzeile der Hintergrundaufgaben, 180 Punkte,
///   * die Überschrift eines Streifens der Übersicht, 193 Punkte,
///   * die Personenkacheln derselben Übersicht, 1 Punkt.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_skal_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
    await _fuellen(db);
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  final bildschirme = <String, Widget Function(LibraryState)>{
    'Aktivitaeten': (l) => AktivitaetenScreen(library: l),
    'Alben': (l) => AlbumsScreen(library: l),
    'Automatik': (l) => AutomationRulesScreen(library: l),
    'Hintergrundaufgaben': (l) => BackgroundTasksScreen(library: l),
    'BibliothekBelegt': (l) => BibliothekBelegtScreen(library: l),
    'Kalender': (l) => CalendarScreen(library: l),
    'Kameravorgaben': (l) => CameraPresetsScreen(library: l),
    'Duplikate': (l) => DuplicatesScreen(library: l),
    'Erkunden': (l) => ExploreScreen(library: l),
    'Ausfuhrvorgaben': (l) => ExportPresetsScreen(library: l),
    'Integritaet': (l) => IntegrityCheckScreen(library: l),
    'Laenderliste': (l) => LaenderlisteScreen(library: l),
    'Personen': (l) => PeopleScreen(library: l),
    'Reisen': (l) => ReisenScreen(library: l),
    'Restaurierung': (l) => RestoreQueueScreen(library: l),
    'Suche': (l) => SearchScreen(library: l),
    'Serien': (l) => StackReviewScreen(library: l),
    'Statistik': (l) => StatisticsScreen(library: l),
    'Staubsuche': (l) => StaubsucheScreen(library: l),
    'Werkzeuge': (l) => ToolsScreen(library: l),
    'Papierkorb': (l) => TrashScreen(library: l),
    'XMP': (l) => XmpImportScreen(library: l),
  };

  // 600 px trifft ausdrücklich die kompakte Navigation (<700), die zuvor in
  // keinem Skalierungstest vorkam. 2,0 bildet die große Systemschrift ab.
  for (final breite in [600.0, 820.0, 1100.0]) {
    for (final skalierung in [1.0, 1.6, 2.0]) {
      for (final eintrag in bildschirme.entries) {
        testWidgets('${eintrag.key} bei ${skalierung}x auf ${breite.round()}',
            (tester) async {
          tester.view.physicalSize = Size(breite, 900);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppTexte.localizationsDelegates,
            supportedLocales: AppTexte.supportedLocales,
            theme: buildDarkTheme(),
            builder: (context, kind) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(skalierung)),
              child: kind!,
            ),
            // Der Rahmen, in dem jeder dieser Bildschirme im Betrieb
            // steht – manche bringen ihr eigenes Gerüst mit, andere
            // nicht, und ohne eines fehlt ihnen die Material-Fläche.
            home: Scaffold(body: eintrag.value(library)),
          ));
          // Kein `pumpAndSettle`: Mehrere dieser Bildschirme zeigen
          // beim Laden einen Kreisel, und der wird nie fertig.
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 40));
          }
          final fehler = tester.takeException();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          expect(fehler, isNull,
              reason: '${eintrag.key} bei $skalierung auf $breite');
        });
      }
    }
  }
}

/// So viel Inhalt, dass die Bildschirme etwas zu zeigen haben – mit
/// absichtlich langen Namen, denn eine kurze Beschriftung läuft nie über.
Future<void> _fuellen(AppDatabase db) async {
  for (var i = 0; i < 12; i++) {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a$i',
          originalFileName: 'DSC_0000$i.jpg',
          relativePath: 'originals/a$i.jpg',
          checksum: 'c$i',
          type: i == 11 ? 'VIDEO' : 'IMAGE',
          fileCreatedAt: DateTime(2026, 1 + i % 12, 1 + i),
          importedAt: DateTime(2026),
          fileSizeBytes: Value(1000 + i),
          cameraMake: const Value('Panasonic'),
          cameraModel: const Value('Lumix DC-G9 Mark II'),
          latitude: Value(52.3 + i / 100),
          longitude: Value(9.7 + i / 100),
          locationCity: const Value('Braunschweig'),
          locationCountry: const Value('Deutschland'),
          isTrashed: Value(i == 10),
        ));
  }
  for (var i = 0; i < 4; i++) {
    await db.into(db.people).insert(PeopleCompanion.insert(
        id: 'p$i', name: 'Marie-Christine Oberhauser-Schmitt $i'));
    await db.into(db.albums).insert(AlbumsCompanion.insert(
        id: 'al$i',
        name: 'Sommerurlaub Norwegen und Schweden $i',
        createdAt: DateTime(2026)));
  }
}

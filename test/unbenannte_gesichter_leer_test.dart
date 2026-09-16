import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **„Nach dem Import keine unbekannten Gesichter."**
///
/// Der Tab sagte darauf: „Keine unbenannten Gesichter (mehr). Neue
/// erscheinen hier automatisch, sobald du weitere Fotos importierst" –
/// und versprach damit genau das, was gerade nicht eingetreten war.
/// Dieselbe falsche Auskunft wie „Keine Treffer" bei einer Suche in
/// einem leeren Verzeichnis: Der Satz stimmt nur, wenn ueberhaupt
/// gesucht wurde.
///
/// Drei Faelle sind zu unterscheiden, und der leere Tab muss sagen,
/// welcher gilt: kein Gesichtsmodell, noch nicht durchsucht, oder
/// wirklich nichts gefunden.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  ModellHalter<T> halter<T>(String name, {required bool installiert}) => ModellHalter<T>(
        name: name,
        installiert: installiert,
        laden: () async => throw StateError('im Test wird nichts geladen'),
        entsorgen: (_) async {},
      );

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_gesichter_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, {bool durchsucht = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
            facesScanned: Value(durchsucht),
          ));

  /// Feste Takte mit echten Pausen dazwischen: Der Bildschirm holt seinen
  /// Stand aus der Datenbank, und die antwortet nicht innerhalb der Uhr
  /// eines Widget-Tests.
  Future<void> takte(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(body: PeopleScreen(library: library)),
    ));
    await takte(tester);
    // Auf den Tab "Unbenannte" wechseln - ueber den Reiter selbst, nicht
    // ueber seine Beschriftung: Der Personen-Tab daneben nennt ihn im
    // Text ebenfalls.
    await tester.tapAt(tester.getCenter(
        find.ancestor(of: find.textContaining('Unbenannte'), matching: find.byType(Tab))));
    await takte(tester);
  }

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('ohne Modell sagt der Tab, dass keines da ist', (tester) async {
    await tester.runAsync(() async {
      await aufnahme('a1');
      await zeige(tester);

      expect(find.textContaining('Ohne ein Modell für die Gesichtserkennung'), findsOneWidget);
      // Ein Knopf "Jetzt suchen" waere hier ein Knopf, der nichts kann.
      expect(find.text('Jetzt nach Gesichtern suchen'), findsNothing);
      await abbauen(tester);
    });
  });

  testWidgets('mit Modell, aber ungesuchten Fotos: die Zahl und der Knopf', (tester) async {
    await tester.runAsync(() async {
      library.faceEngineHalter = halter<FaceEngineService>('Gesichter', installiert: true);
      await aufnahme('a1');
      await aufnahme('a2');
      await aufnahme('a3', durchsucht: true);
      await zeige(tester);

      // Zwei von dreien sind offen - und genau das steht da, statt eines
      // Versprechens, das schon gebrochen ist.
      expect(find.textContaining('2 Aufnahmen sind noch nicht nach Gesichtern'), findsOneWidget);
      expect(find.text('Jetzt nach Gesichtern suchen'), findsOneWidget);

      // Und der Knopf reiht wirklich einen Lauf ein - unter demselben
      // Schluessel wie die Aufgabenliste, damit nicht zwei Durchgaenge
      // dieselbe Liste abarbeiten.
      expect(library.lauf('gesichter'), isNull);
      await tester.tapAt(tester.getCenter(find.text('Jetzt nach Gesichtern suchen')));
      await takte(tester);
      // Der Lauf steht danach in der Liste - unter demselben Schluessel
      // wie in der Aufgabenuebersicht. Ob er schon fertig ist, haengt am
      // Modell (im Test wird keines geladen) und ist hier nicht die
      // Frage; die Frage ist, ob der Knopf ueberhaupt etwas anstoesst.
      expect(library.lauf('gesichter'), isNotNull);

      library.brichAufgabeAb('gesichter');
      await takte(tester);
      await abbauen(tester);
    });
  });

  testWidgets('alles durchsucht und nichts gefunden: der alte Satz', (tester) async {
    await tester.runAsync(() async {
      library.faceEngineHalter = halter<FaceEngineService>('Gesichter', installiert: true);
      await aufnahme('a1', durchsucht: true);
      await zeige(tester);

      expect(find.textContaining('Keine unbenannten Gesichter'), findsOneWidget);
      expect(find.text('Jetzt nach Gesichtern suchen'), findsNothing);
      await abbauen(tester);
    });
  });
}

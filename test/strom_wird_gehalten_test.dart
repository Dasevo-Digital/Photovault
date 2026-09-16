import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Bildschirme halten ihren Datenstrom fest.**
///
/// `db.watchTimeline(limit: 600)` gibt bei jedem Aufruf ein neues
/// Stream-Objekt zurück. Stand der Aufruf direkt im `stream:` eines
/// StreamBuilder, sah dieser bei jedem Neubau einen anderen Strom, kündigte
/// das Abo und schloss ein neues – und ein neues Abo führt die Abfrage von
/// vorn aus, auch wenn nebenan noch eines auf genau dieselbe offen ist.
///
/// An der gewachsenen Bibliothek (7341 Aufnahmen) je Neubau gemessen:
///
/// ```
/// watchTimeline(600)           5,1 ms   (Startfenster)
/// watchTimeline(3000)         12,9 ms
/// watchTimeline() ohne Grenze 35,9 ms   (nach dem Scrollen)
/// watchTrash()                 3,0 ms
/// ```
///
/// Neubauten löst in der Zeitleiste **jeder Pfeiltastendruck** aus
/// (`Rasterbedienung` setzt `aktiveKachel` per `setState`) und jeder Klick
/// in der Mehrfachauswahl. Eine gedrückt gehaltene Taste sind rund dreissig
/// Neubauten je Sekunde.
///
/// Geprüft wird deshalb nicht die Rechnung, sondern die **Verdrahtung**:
/// Bekommt der StreamBuilder nach einem Neubau wirklich dasselbe
/// Stream-Objekt? Ein Prüfstand auf [Stromhalter] allein sähe nicht, ob der
/// Bildschirm ihn auch benutzt.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_strom_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aufnahme(String id, DateTime wann) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: wann,
          ));

  /// Baut den Baum ab und lässt den Aufräum-Timer von drift auslaufen –
  /// siehe papierkorb_bedienung_test.dart, dieselbe Falle.
  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget rahmen(Widget kind) => MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        locale: const Locale('de'),
        home: kind,
      );

  /// Alle Ströme, die gerade im Baum an einem StreamBuilder hängen.
  ///
  /// Die Zeitleiste holt seit dem schmalen Zeilentyp [Rasterzeile] statt
  /// `AssetData` – die Frage bleibt dieselbe: Ist es bei einem Neuaufbau
  /// noch derselbe Strom?
  List<Stream<List<T>>> stroeme<T>(WidgetTester tester) => tester
      .widgetList<StreamBuilder<List<T>>>(
          find.byType(StreamBuilder<List<T>>))
      .map((w) => w.stream!)
      .toList();

  testWidgets('die Zeitleiste behaelt ihren Strom ueber Neubauten', (tester) async {
    for (var i = 0; i < 3; i++) {
      await aufnahme('a$i', DateTime(2026, 5, 1 + i));
    }
    await tester.pumpWidget(rahmen(Scaffold(body: TimelineScreen(library: library))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final vorher = stroeme<Rasterzeile>(tester);
    expect(vorher, hasLength(1));

    // Der Neubau, um den es geht: ein Pfeiltastendruck. [Rasterbedienung]
    // setzt dabei `aktiveKachel` per `setState`.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(identical(stroeme<Rasterzeile>(tester).single, vorher.single), isTrue,
        reason: 'sonst fragt jeder Tastendruck die Datenbank erneut');
    await abbauen(tester);
  });

  testWidgets('waechst das Ladefenster, wird sehr wohl neu gefragt', (tester) async {
    // Die Gegenprobe. Ein Halter, der stur festhält, zeigte nach dem
    // Scrollen für immer die ersten 600 Fotos – und das wäre schlimmer als
    // die Abfragen, die er spart.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await db.batch((b) => b.insertAll(db.assets, [
          for (var i = 0; i < 700; i++)
            AssetsCompanion.insert(
              id: 'f$i',
              originalFileName: 'f$i.jpg',
              relativePath: 'originals/f$i.jpg',
              checksum: 'pruef-f$i',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026).add(Duration(hours: i)),
              importedAt: DateTime(2026),
            ),
        ]));
    await tester.pumpWidget(rahmen(Scaffold(body: TimelineScreen(library: library))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final vorher = stroeme<Rasterzeile>(tester).single;
    // Ans Ende des geladenen Ausschnitts – genau das, was das Fenster
    // wachsen lässt (siehe onScrollNearEnd).
    final lage = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    lage.jumpTo(lage.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(identical(stroeme<Rasterzeile>(tester).single, vorher), isFalse,
        reason: 'ein groesseres Fenster ist eine andere Abfrage');
    await abbauen(tester);
  });

  testWidgets('der Papierkorb fragt nicht zweimal dasselbe', (tester) async {
    // Zwei Leser – die Liste und die Belegungszahl in der Titelleiste.
    // Vorher standen dort zwei getrennte `watchTrash()`-Aufrufe: dieselbe
    // Abfrage, zweimal ausgeführt, und bei jedem Neubau erneut.
    await aufnahme('weg', DateTime(2026, 5, 1));
    await db.moveToTrash(['weg']);
    await tester.pumpWidget(rahmen(TrashScreen(library: library)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final gefunden = stroeme<AssetData>(tester);
    expect(gefunden.length, greaterThanOrEqualTo(2),
        reason: 'Liste und Belegungszahl lesen beide');
    expect(gefunden.toSet(), hasLength(1),
        reason: 'aber aus demselben Strom');
    await abbauen(tester);
  });
}

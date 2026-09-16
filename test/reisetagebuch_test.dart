import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/reise_detail_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **„Ohne Reisetagebuch erwartete ich schriftliche Notizen für jeden
/// Tag."**
///
/// Die Kapitel nach Tagen gab es – ein Tagebuch besteht aber nicht aus
/// Bildern allein. Es fehlte genau das, was ein Tagebuch ausmacht: der
/// Satz, den nur der Reisende schreiben kann. Die Notiz an der Reise
/// gab es schon, sie gilt aber für die ganze Reise; „am dritten Tag hat
/// es geschüttet" gehört an den dritten Tag.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_tagebuch_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    melde.verlaufLeeren();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Zwei Reisetage mit je zwei Aufnahmen – ohne den zweiten Tag liesse
  /// sich nicht prüfen, dass eine Notiz nur an IHREM Tag steht.
  Future<ReisenData> anlegen() async {
    final ids = <String>[];
    for (final (i, wann) in [
      DateTime(2026, 6, 14, 9),
      DateTime(2026, 6, 14, 11),
      DateTime(2026, 6, 15, 10),
      DateTime(2026, 6, 15, 16),
    ].indexed) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'r$i',
            originalFileName: 'r$i.jpg',
            relativePath: 'originals/r$i.jpg',
            checksum: 'pruef-r$i',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: DateTime(2026),
            latitude: const Value(41.9),
            longitude: const Value(12.5),
            locationCity: const Value('Roma'),
          ));
      ids.add('r$i');
    }
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'reise1',
        name: 'Rom',
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 15, 16),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ids,
    );
    return (await db.alleReisen()).single;
  }

  Future<void> zeige(WidgetTester tester, ReisenData reise) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: ReiseDetailScreen(library: library, reise: reise),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> schreibe(WidgetTester tester, int tag, String text) async {
    await tester.tap(find
        .byTooltip('Notiz zu diesem Tag schreiben')
        .at(tag));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, text);
    await tester.tap(find.widgetWithText(FilledButton, 'Übernehmen'));
    await tester.pumpAndSettle();
  }

  test('leerer Text loescht die Notiz, statt eine leere anzulegen', () async {
    await anlegen();
    final tag = DateTime(2026, 6, 14);
    await db.setzeReisetagnotiz('reise1', tag, 'Regen den ganzen Tag');
    expect(await db.reisetagnotizenFuer('reise1'), {tag: 'Regen den ganzen Tag'});
    await db.setzeReisetagnotiz('reise1', tag, '   ');
    expect(await db.reisetagnotizenFuer('reise1'), isEmpty);
  });

  test('die Uhrzeit faellt weg - der Tag ist der Schluessel', () async {
    await anlegen();
    await db.setzeReisetagnotiz('reise1', DateTime(2026, 6, 14, 17, 42), 'Abends');
    expect(await db.reisetagnotizenFuer('reise1'),
        {DateTime(2026, 6, 14): 'Abends'});
  });

  test('mit der Reise verschwinden auch ihre Tagesnotizen', () async {
    await anlegen();
    await db.setzeReisetagnotiz('reise1', DateTime(2026, 6, 14), 'Regen');
    await db.reiseLoeschen('reise1');
    // Sonst gehoerten sie stillschweigend zur naechsten Reise mit
    // derselben Kennung.
    expect(await db.reisetagnotizenFuer('reise1'), isEmpty);
  });

  testWidgets('jeder Tag traegt einen Stift, auch der leere', (tester) async {
    await zeige(tester, await anlegen());
    // Zwei Tage, zwei Stifte - und keiner davon erscheint erst, wenn es
    // schon etwas gibt.
    expect(find.byTooltip('Notiz zu diesem Tag schreiben'), findsNWidgets(2));
    expect(find.byTooltip('Notiz zu diesem Tag ändern'), findsNothing);
  });

  testWidgets('die geschriebene Notiz steht unter ihrer Ueberschrift',
      (tester) async {
    await zeige(tester, await anlegen());
    await schreibe(tester, 0, 'Ankunft im Regen, Kolosseum geschlossen.');

    expect(find.text('Ankunft im Regen, Kolosseum geschlossen.'),
        findsOneWidget);
    // Nur an ihrem Tag: der andere bleibt leer.
    expect(find.byTooltip('Notiz zu diesem Tag ändern'), findsOneWidget);
    expect(find.byTooltip('Notiz zu diesem Tag schreiben'), findsOneWidget);

    // Und sie steht wirklich in der Datenbank, nicht nur im Bild - an
    // dem Tag, dessen Stift gedrueckt wurde (die Kapitel laufen
    // aufsteigend, der erste ist der 14.).
    expect(await db.reisetagnotizenFuer('reise1'),
        {DateTime(2026, 6, 14): 'Ankunft im Regen, Kolosseum geschlossen.'});
  });
}

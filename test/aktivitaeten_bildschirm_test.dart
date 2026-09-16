import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/aktivitaeten_screen.dart';
import 'package:photo_vault/services/aktivitaeten.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Der Weg vom Vorschlag zur eingetragenen Aktivität.
///
/// Die Rechnung steht in aktivitaeten_test.dart; hier geht es um das,
/// was erst am Bildschirm sichtbar wird – dass aus einer Häufung ein
/// Vorschlag mit Knöpfen wird, dass „Nein" ihn dauerhaft loswird, und
/// dass eine bestätigte Wanderung in der richtigen der beiden Listen
/// landet.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_akt_');
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

  /// Eine Aufnahme [minuten] nach 9 Uhr, [kmOst] östlich von Hannover.
  Future<void> aufnahme(String id, int minuten, double kmOst,
          {DateTime? tag, String? stadt}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: (tag ?? DateTime(2026, 6, 14, 9))
                .add(Duration(minutes: minuten)),
            importedAt: DateTime(2026),
            latitude: const Value(52.37),
            longitude: Value(9.73 + kmOst / 68.0),
            locationCity: Value(stadt),
          ));

  /// Acht Bilder über dreieinhalb Stunden und rund zehn Kilometer – eine
  /// Wanderung, wie die Erkennung sie sucht.
  Future<void> wanderung({DateTime? tag, String stadt = 'Goslar'}) async {
    for (var i = 0; i < 8; i++) {
      await aufnahme('w$i', i * 30, i * 1.5, tag: tag, stadt: stadt);
    }
    // Ein Zuhause, damit die Erkennung einen Bezugspunkt hat: viele Tage
    // an derselben Stelle schlagen eine einzelne Häufung.
    for (var i = 0; i < 40; i++) {
      await aufnahme('h$i', 0, 0,
          tag: DateTime(2026, 1, 1, 12).add(Duration(days: i)));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: (context, kind) => mitMeldungen(kind),
      home: AktivitaetenScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('aus einer Häufung wird ein Vorschlag mit Zahlen',
      (tester) async {
    await wanderung();
    await zeige(tester);

    expect(find.text('Vorschläge'), findsOneWidget);
    expect(find.text('Goslar'), findsOneWidget);
    // Art, Datum, Dauer, Strecke und Zahl der Bilder in einer Zeile –
    // und das Komma gehört zur Sprache.
    expect(find.textContaining('Wanderung'), findsWidgets);
    expect(find.textContaining('3 h 30 min'), findsOneWidget);
    expect(find.textContaining('10,5 km'), findsOneWidget);
    expect(find.textContaining('8 Fotos'), findsOneWidget);
  });

  testWidgets('eine bestätigte Reise wird nicht noch einmal als Aktivität '
      'vorgeschlagen', (tester) async {
    await wanderung();
    // Dieselben acht Bilder als bestätigte Reise. Vorher bot der
    // Bildschirm sie trotzdem als Aktivität an – bei der echten Reise
    // „Mazār-e Sharīf – ISAF" stammten zwei von vier Vorschlägen aus
    // ihren Aufnahmen, einer davon zu 28 von 28.
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harzwoche',
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 13),
        angelegtAm: DateTime(2026, 6, 15),
      ),
      [for (var i = 0; i < 8; i++) 'w$i'],
    );
    await zeige(tester);

    expect(find.text('Vorschläge'), findsNothing,
        reason: 'was in einer Reise steht, ist schon zugeordnet');
    expect(find.text('Goslar'), findsNothing);
  });

  testWidgets('ohne die Reise steht der Vorschlag sehr wohl da',
      (tester) async {
    // Die Gegenprobe zum Test darüber: Sonst prüfte er nur, dass der
    // Bildschirm überhaupt nichts anzeigt.
    await wanderung();
    await zeige(tester);
    expect(find.text('Vorschläge'), findsOneWidget);
  });

  testWidgets('bestätigen legt sie an – für sich, ohne Reise',
      (tester) async {
    await wanderung();
    await zeige(tester);

    await tester.tap(find.text('War eine Unternehmung'));
    await tester.pumpAndSettle();
    // Der vorgeschlagene Name steht schon im Feld.
    expect(find.widgetWithText(TextField, 'Goslar'), findsOneWidget);
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final k = (await db.alleAktivitaeten()).single;
    expect(k.name, 'Goslar');
    expect(Aktivitaetsart.aus(k.art), Aktivitaetsart.wanderung);
    expect(k.reiseId, isNull);
    expect((await db.aufnahmenDerAktivitaet(k.id)), hasLength(8));

    // Und sie steht unter „Für sich", nicht unter „Auf Reisen".
    expect(find.text('Für sich'), findsOneWidget);
    expect(find.text('Auf Reisen'), findsNothing);
    // Der Vorschlag ist verbraucht – seine Bilder sind vergeben.
    expect(find.text('Vorschläge'), findsNothing);
  });

  testWidgets('eine Wanderung im Urlaub steht unter „Auf Reisen"',
      (tester) async {
    // **Angelegt wird sie im Reisebildschirm**, nicht hier: Aus einer
    // bestätigten Reise entstehen keine Vorschläge mehr (siehe oben).
    // Was dieser Test bewacht, ist die Anzeige – dass eine Aktivität mit
    // Reise in der anderen der beiden Listen landet und ihre Reise nennt.
    await wanderung();
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'r1',
        name: 'Harz',
        von: DateTime(2026, 6, 13),
        bis: DateTime(2026, 6, 16),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7'],
    );
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Goslar',
        art: Aktivitaetsart.wanderung.kennung,
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 12, 30),
        reiseId: const Value('r1'),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7'],
    );
    await zeige(tester);

    expect(find.text('Auf Reisen'), findsOneWidget);
    expect(find.textContaining('Gehört zu: Harz'), findsOneWidget);
  });

  testWidgets('„Nein" macht den Vorschlag dauerhaft los', (tester) async {
    await wanderung();
    await zeige(tester);

    await tester.tap(find.text('War keine'));
    await tester.pumpAndSettle();
    expect(find.text('Vorschläge'), findsNothing);
    expect(await db.verworfeneAktivitaetsvorschlaege(), {'w0'});

    // Auch nach dem nächsten Durchlauf – ein Vorschlag, den man dreimal
    // wegwischen muss, ist eine Belästigung.
    await zeige(tester);
    expect(find.text('Vorschläge'), findsNothing);
  });

  testWidgets('ohne Aufnahmen steht da, was fehlt', (tester) async {
    await zeige(tester);
    expect(find.textContaining('Noch keine Aktivität'), findsOneWidget);
    // Und der Hinweis auf den fehlenden Geo-Datensatz, denn ohne ihn
    // wäre „noch keine Aktivität" nur die halbe Auskunft.
    expect(find.textContaining('GeoNames-Datensatz'), findsWidgets);
  });
}

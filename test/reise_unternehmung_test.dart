import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/reise_detail_screen.dart';
import 'package:photo_vault/services/aktivitaeten.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// **Eine Unternehmung aus der Reise heraus anlegen.**
///
/// Der Weg, der gefehlt hat: Aktivitäten entstanden nur im
/// Aktivitätenbildschirm und fanden ihre Reise über den Kalender. Seit
/// eine bestätigte Reise keine Vorschläge mehr erzeugt – sie bot
/// dieselben Fotos ein zweites Mal an –, muss es dort gehen, wo man die
/// Reise vor sich hat.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_reiseunt_');
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

  /// Eine Reise über drei Tage, mit einer Aufnahme je Tag.
  Future<ReisenData> anlegen() async {
    for (var i = 0; i < 3; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'r$i',
            originalFileName: 'r$i.jpg',
            relativePath: 'originals/r$i.jpg',
            checksum: 'pruef-r$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14 + i, 10),
            importedAt: DateTime(2026),
            latitude: const Value(41.9),
            longitude: const Value(12.5),
            locationCity: const Value('Roma'),
          ));
    }
    await db.reiseAnlegen(
      ReisenCompanion.insert(
        id: 'reise1',
        name: 'Rom',
        von: DateTime(2026, 6, 14, 10),
        bis: DateTime(2026, 6, 16, 10),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['r0', 'r1', 'r2'],
    );
    return (await db.alleReisen()).single;
  }

  Future<void> zeige(WidgetTester tester, ReisenData reise) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: (context, kind) => mitMeldungen(kind),
      home: ReiseDetailScreen(library: library, reise: reise),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ohne Unternehmung steht da, dass es sie gibt', (tester) async {
    // Vorher erschien der Abschnitt erst, wenn schon eine existierte –
    // wer keine hatte, erfuhr nie, dass es sie gibt.
    await zeige(tester, await anlegen());
    expect(find.text('Unternehmungen'), findsOneWidget);
    expect(find.textContaining('Noch keine'), findsOneWidget);
  });

  testWidgets('die ganze Reise wird zur Unternehmung', (tester) async {
    await zeige(tester, await anlegen());

    await tester.tap(find.byTooltip('Unternehmung anlegen'));
    await tester.pumpAndSettle();

    // **Vorbelegt mit der ganzen Reise**: Wer nichts ändert, bekommt
    // genau sie. Name und Zeitraum stehen schon da.
    expect(find.widgetWithText(TextField, 'Rom'), findsOneWidget);
    expect(find.textContaining('3'), findsWidgets);

    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    final k = (await db.alleAktivitaeten()).single;
    expect(k.name, 'Rom');
    expect(k.reiseId, 'reise1', reason: 'sie gehört zu dieser Reise');
    expect(k.von, DateTime(2026, 6, 14, 10));
    expect(k.bis, DateTime(2026, 6, 16, 10));
    expect(await db.aufnahmenDerAktivitaet(k.id), hasLength(3),
        reason: 'alle drei Aufnahmen der Reise');

    // Und sie steht danach im Bildschirm.
    expect(find.textContaining('Noch keine'), findsNothing);
  });

  testWidgets('ein engerer Zeitraum ergibt ein Kapitel daraus',
      (tester) async {
    final reise = await anlegen();
    // Denselben Weg, aber nur der erste Tag – die Aufnahmen der beiden
    // anderen Tage dürfen nicht mitkommen.
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Kolosseum',
        art: Aktivitaetsart.besichtigung.kennung,
        von: DateTime(2026, 6, 14, 9),
        bis: DateTime(2026, 6, 14, 18),
        reiseId: const Value('reise1'),
        angelegtAm: DateTime(2026, 7, 1),
      ),
      ['r0'],
    );
    await zeige(tester, reise);
    expect(find.text('Kolosseum'), findsOneWidget);
    expect(find.textContaining('Noch keine'), findsNothing);
  });
}

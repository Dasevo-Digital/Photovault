import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/services/hochskalieren.dart';
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Hochskalieren läuft in der Warteschlange der Restaurierung (#500) – und
/// heisst dort auch so: im Band über der App und in der Liste der Aufträge.
void main() {
  final de = AppTexteDe();
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  RestoreJobData auftrag(
    String id,
    String status, {
    int fertig = 0,
    int gesamt = 0,
  }) => RestoreJobData(
    id: id,
    assetId: 'a',
    status: status,
    tilesDone: fertig,
    tilesTotal: gesamt,
    createdAt: DateTime(2026, 11, 27),
  );

  group('das Band', () {
    test('ein laufendes Hochskalieren sagt Faktor und Stand', () {
      final text = restaurierungsbandText(de, [
        auftrag(hochskalierAuftragsId(4), 'running', fertig: 21, gesamt: 50),
      ]);
      expect(
        text,
        de.hochskalierenBand(
          de.hochskalierenAuftrag(4),
          de.restaurZeileLaeuft(42),
        ),
      );
    });

    test('warten nur Hochskalier-Aufträge, heisst es so', () {
      expect(
        restaurierungsbandText(de, [
          auftrag(hochskalierAuftragsId(2), 'queued'),
        ]),
        de.hochskalierenWartend(1),
      );
      expect(
        restaurierungsbandText(de, [
          auftrag(hochskalierAuftragsId(2), 'queued'),
          auftrag('restaurierung', 'queued'),
        ]),
        de.restaurierungWartend(2),
      );
    });

    test('Gegenprobe: eine Restaurierung bleibt eine Restaurierung', () {
      expect(
        restaurierungsbandText(de, [
          auftrag('restaurierung', 'running', fertig: 21, gesamt: 50),
        ]),
        de.restaurProzentLaeuft(42),
      );
      expect(
        restaurierungsbandText(de, [auftrag('fertig', 'done')]),
        isNull,
        reason: 'ohne offene Aufträge kein Band',
      );
    });
  });

  testWidgets('die Liste nennt Faktor und Grund', (tester) async {
    final library = LibraryState()..db = db;
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'foto.jpg',
            relativePath: 'originals/foto.jpg',
            checksum: 'a',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024),
            importedAt: DateTime(2024),
          ),
        );
    final hoch = hochskalierAuftragsId(2);
    for (final id in [hoch, 'restaurierung']) {
      await db.createRestoreJob(
        RestoreJobsCompanion.insert(
          id: id,
          assetId: 'a',
          status: 'queued',
          createdAt: DateTime(2026),
        ),
      );
    }
    await db.markRestoreJobStatus(
      hoch,
      'failed',
      errorMessage: RestaurierungsGrund.zuGross.name,
    );
    await db.markRestoreJobStatus('restaurierung', 'done');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: RestoreQueueScreen(library: library),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    expect(
      find.text(de.hochskalierenAuftragName('foto.jpg', 2)),
      findsOneWidget,
    );
    expect(
      find.text(
        de.restaurFehlgeschlagen(
          de.restaurGrundZuGross(
            hochskalierMaxKante,
            hochskalierMaxPixel ~/ 1000000,
          ),
        ),
      ),
      findsOneWidget,
    );
    // Die Restaurierung daneben behält ihren blossen Dateinamen.
    expect(find.text('foto.jpg'), findsOneWidget);
    // Der gescheiterte Auftrag lässt sich noch einmal anstossen, der fertige
    // nicht.
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

    // Abbauen und den Aufräum-Timer von drift auslaufen lassen (wie in
    // strom_wird_gehalten_test.dart).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  });
}

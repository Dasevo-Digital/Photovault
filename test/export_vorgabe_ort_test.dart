import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/export_presets_screen.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Schalter „Ort mitgeben“ in den Exportvorgaben (#468): sichtbar beim
/// Rendern, gespeichert in der Vorgabe und in ihrer Zusammenfassung
/// genannt – die steht auch im Exportdialog.
void main() {
  final de = AppTexteDe();
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_vorgabe_ort_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('beim Rendern lässt sich der Ort mitgeben', (tester) async {
    // Kein `pumpAndSettle`: Die Liste zeigt beim Laden einen Kreisel.
    Future<void> weiter() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: ExportPresetsScreen(library: library),
      ),
    );
    await weiter();

    await tester.tap(find.byTooltip(de.exportVorgabeNeu));
    await weiter();
    await tester.enterText(
      find.widgetWithText(TextField, de.exportVorgabeName),
      'Mit Ort',
    );

    final schalter = find.widgetWithText(SwitchListTile, de.exportVorgabeOrt);
    // Neu aus, wie es für gerenderte Vorgaben bisher galt.
    expect(tester.widget<SwitchListTile>(schalter).value, isFalse);
    // Ohne Rendern ohne Bedeutung: Die Kopie behält ihren Ort.
    await tester.tap(
      find.widgetWithText(SwitchListTile, de.exportVorgabeNachJpeg),
    );
    await weiter();
    expect(schalter, findsNothing);
    await tester.tap(
      find.widgetWithText(SwitchListTile, de.exportVorgabeNachJpeg),
    );
    await weiter();
    await tester.ensureVisible(schalter);
    await tester.tap(schalter);
    await weiter();
    expect(tester.widget<SwitchListTile>(schalter).value, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, de.allgSpeichern));
    await weiter();

    final gespeichert = await db.alleExportPresets();
    expect(gespeichert.single.ortMitgeben, isTrue);
    expect(vorgabeZusammenfassung(de, gespeichert.single), contains('mit Ort'));
    expect(find.textContaining(de.exportVorgabeMitOrt), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

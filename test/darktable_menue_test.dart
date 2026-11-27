import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/bearbeitungsprogramme.dart';
import 'package:photo_vault/services/darktable_bruecke.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// **„Ergebnis aus darktable übernehmen“ fehlte gleich nach dem Öffnen**
/// (BEA-152).
///
/// Das Rechtsklick-Menü fragt beim Aufbau, ob eine Arbeitskopie bereitliegt.
/// Nach „In darktable bearbeiten“ baute die Vollbildansicht aber nicht neu
/// auf; der Punkt erschien erst, wenn sie aus anderem Grund neu gezeichnet
/// wurde.
///
/// Seit #499 steht darktable im Untermenü „Bearbeiten in“; der Punkt zum
/// Übernehmen bleibt im Menü selbst.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late DarktableBruecke bruecke;
  late Bearbeitungsprogramme programme;
  late AssetData foto;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_darktable_menue_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    // Ein eigener Ordner statt des üblichen im Heimverzeichnis, und ein
    // Start, der nichts startet.
    bruecke = DarktableBruecke(
      Directory(p.join(wurzel.path, 'darktable')),
      starte: (_) async => true,
    );
    // Keine Erkennung auf dem Prüfrechner, keine Einstellung im echten
    // Datenordner: darktable steht auch ohne Fund im Menü.
    programme = Bearbeitungsprogramme(
      basis: Directory(p.join(wurzel.path, 'arbeit')),
      einstellungen: () async => File(p.join(wurzel.path, 'programme.json')),
      erkenne: () async => const {},
      zeigeOrdner: (_) async => true,
    );
    final original = pfade.absolute('originals/a.jpg');
    await original.parent.create(recursive: true);
    await original.writeAsBytes(img.encodeJpg(img.Image(width: 8, height: 8)));
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'a.jpg',
            relativePath: 'originals/a.jpg',
            checksum: 'pruef-a',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14),
            importedAt: DateTime(2026),
          ),
        );
    foto = (await db.assetById('a'))!;
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> menueOeffnen(WidgetTester tester) async {
    await tester.tap(find.byType(PageView), buttons: kSecondaryMouseButton);
    await warte(tester);
  }

  testWidgets('nach dem Öffnen steht „Ergebnis übernehmen“ im Menü', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: [foto],
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: bibliothek,
            darktable: bruecke,
            programme: programme,
          ),
        ),
      ),
    );
    await warte(tester);

    await menueOeffnen(tester);
    expect(find.text('Bearbeiten in'), findsOneWidget);
    expect(find.text('Ergebnis aus darktable übernehmen'), findsNothing);
    await tester.tap(find.text('Bearbeiten in'));
    await warte(tester);
    await tester.tap(find.text('darktable'));
    await warte(tester);
    expect(bruecke.offen('a'), isTrue, reason: 'die Arbeitskopie liegt da');

    await menueOeffnen(tester);
    expect(find.text('Ergebnis aus darktable übernehmen'), findsOneWidget);
  });
}

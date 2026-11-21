import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// **Verbunden, Server weg, Original nie geholt.**
///
/// Das Holen wirft [KeineVerbindung]. Die Seite zeigte bei einem Fehler
/// genau wie beim Warten nur die Ladeanzeige – für immer, ohne Hinweis
/// und ohne das Vorschaubild, das längst da ist.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  final de = AppTexteDe();

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_original_fehlt_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    // Wie eine verbundene Kopie ohne Server – mit der echten
    // Beschaffung, damit auch ein unbehandelter Fehler beim Aufräumen
    // auffällt.
    Dateibeschaffung(
      pfade,
      Serververbindung(
        Uri.parse('http://127.0.0.1:9/'),
        'pruef',
        client: MockClient((_) async => throw http.ClientException('fort')),
      ),
    ).binde();
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade);
    final vorschau = pfade.absolute('thumbnails/fern.jpg');
    vorschau.parent.createSync(recursive: true);
    vorschau.writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xD9]);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'fern',
            originalFileName: 'fern.jpg',
            relativePath: 'originals/fern.jpg',
            checksum: 'pruef-fern',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2017),
            importedAt: DateTime(2017),
            thumbnailRelativePath: const Value('thumbnails/fern.jpg'),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('Hinweis und Vorschaubild statt Dauerladen', (tester) async {
    final foto = (await tester.runAsync(() => db.assetById('fern')))!;
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
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(de.viewerOriginalNichtDa), findsOneWidget);
    expect(find.byType(Image), findsWidgets, reason: 'das Vorschaubild');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

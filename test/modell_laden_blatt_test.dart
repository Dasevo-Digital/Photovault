import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/model_download_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/state/library_state.dart';

/// Ein Download, dessen Fortschritt der Test selbst schickt.
class _Downloads extends ModelDownloadService {
  _Downloads(super.modelsDir);
  final lauf = StreamController<ModelDownloadProgress>();

  @override
  Stream<ModelDownloadProgress> download(ModelCatalogEntry entry) =>
      lauf.stream;
}

class _Bibliothek extends LibraryState {
  var neuGeladen = 0;

  @override
  Future<void> reloadModels() async => neuGeladen++;
}

/// Das Blatt mit dem Ladefortschritt liegt im Navigator des
/// Arbeitsbereichs, und jeder Klick in die Seitenleiste räumt ihn ab
/// (`popUntil(isFirst)`). Danach warf das nächste `setState` auf dem
/// entsorgten Blatt mitten in die Ladeschleife: Die Datei kam zwar an,
/// aber die Modelle wurden nie neu eingelesen, und als Fehler stand
/// „setState() called after dispose()“ da.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late _Bibliothek library;
  late _Downloads downloads;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const ablage = MethodChannel('plugins.flutter.io/path_provider');
    bote.setMockMethodCallHandler(
      ablage,
      (_) async => Directory.systemTemp.path,
    );
    addTearDown(() => bote.setMockMethodCallHandler(ablage, null));
    const kanal = MethodChannel('dev.fluttercommunity.plus/package_info');
    bote.setMockMethodCallHandler(
      kanal,
      (_) async => <String, String>{
        'appName': 'Photo Vault',
        'packageName': 'com.example.photoVault',
        'version': '3.7.0',
        'buildNumber': '1',
      },
    );
    addTearDown(() => bote.setMockMethodCallHandler(kanal, null));

    wurzel = Directory.systemTemp.createTempSync('pv_modellblatt_');
    db = AppDatabase(NativeDatabase.memory());
    downloads = _Downloads(
      (Directory(
        p.join(wurzel.path, 'models'),
      )..createSync(recursive: true)).path,
    );
    library = _Bibliothek()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      )
      ..modelDownloadService = downloads;
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('ein Klick in die Seitenleiste bricht das Laden nicht ab', (
    tester,
  ) async {
    await tester.runAsync(() async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(body: SettingsScreen(library: library)),
        ),
      );
      Future<void> takte() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await takte();
      await tester.enterText(find.byType(SearchBar), 'KI-Modelle');
      await takte();
      final de = AppTexte.of(tester.element(find.byType(SettingsScreen)));
      await tester.tap(find.text(de.allgHerunterladen).first);
      await takte();
      expect(find.byType(BottomSheet), findsOneWidget);

      // Was die Seitenleiste mit dem Navigator des Arbeitsbereichs tut.
      Navigator.of(
        tester.element(find.byType(SettingsScreen)),
      ).popUntil((route) => route.isFirst);
      await takte();
      expect(find.byType(BottomSheet), findsNothing);

      downloads.lauf.add(ModelDownloadProgress('modell.onnx', 50, 100));
      await takte();
      downloads.lauf.add(ModelDownloadProgress('modell.onnx', 100, 100));
      await downloads.lauf.close();
      await takte();

      expect(library.neuGeladen, 1, reason: 'das geladene Modell zählt');
      expect(find.textContaining('setState'), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

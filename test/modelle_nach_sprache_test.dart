import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **„Die Einstellungen waren immer präsent, egal welche Sprache
/// eingestellt war."**
///
/// Gemeint waren die beiden OPUS-MT-Modellkarten. Die zwei *Schalter*
/// darüber verschwinden bei englischer Oberfläche längst – gemessen und
/// bestätigt; die zwei *Modelle* darunter standen weiter da und boten
/// 200 MB zum Herunterladen an, die auf Englisch nichts bewirken: Das
/// eine übersetzt Bildbeschreibungen ins Deutsche, das andere deutsche
/// Suchbegriffe ins Englische.
///
/// Der Sonderfall, der die Regel erst brauchbar macht: Was schon auf der
/// Platte liegt, bleibt sichtbar. Ein verstecktes Modell ist ein Modell,
/// das niemand mehr löschen kann.
void main() {
  bool nichts(ModelCatalogEntry e) => false;
  bool alles(ModelCatalogEntry e) => true;

  test('auf Deutsch steht der ganze Katalog da', () {
    final liste = ModelCatalog.fuerSprache('de', istInstalliert: nichts);
    expect(liste, ModelCatalog.all);
  });

  test('auf Englisch fallen genau die zwei Uebersetzungsmodelle weg', () {
    final liste = ModelCatalog.fuerSprache('en', istInstalliert: nichts);
    expect(liste.length, ModelCatalog.all.length - 2);
    expect(liste.contains(ModelCatalog.translationEnDe), isFalse);
    expect(liste.contains(ModelCatalog.translationDeEn), isFalse);
    // Und sonst nichts: Die uebrigen neun bleiben unangetastet.
    for (final e in ModelCatalog.all) {
      if (ModelCatalog.nurFuerDeutsch.contains(e)) continue;
      expect(liste.contains(e), isTrue, reason: e.id);
    }
  });

  test('was schon geladen ist, bleibt auch auf Englisch sichtbar', () {
    final liste = ModelCatalog.fuerSprache('en',
        istInstalliert: (e) => e == ModelCatalog.translationEnDe);
    // Sonst laegen 100 MB in der Bibliothek, die niemand mehr loswird.
    expect(liste.contains(ModelCatalog.translationEnDe), isTrue);
    expect(liste.contains(ModelCatalog.translationDeEn), isFalse);
  });

  test('alles installiert heisst: alles sichtbar', () {
    expect(ModelCatalog.fuerSprache('en', istInstalliert: alles),
        ModelCatalog.all);
  });

  group('und der Bildschirm benutzt die Regel auch', () {
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUpAll(() async => initializeDateFormatting());

    /// Der Bildschirm fragt ganz unten nach Version und Baunummer. Ohne
    /// Antwort wirft der Plattformkanal mitten in den Lauf hinein –
    /// sichtbar erst unter `runAsync`, weil erst dort die Zusagen wirklich
    /// zu Ende laufen.
    setUp(() {
      // Und die Bibliotheksliste fragt nach dem Datenordner.
      const ablage = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              ablage, (_) async => Directory.systemTemp.path);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ablage, null));

      const kanal = MethodChannel('dev.fluttercommunity.plus/package_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, (_) async => <String, String>{
                'appName': 'Photo Vault',
                'packageName': 'com.example.photoVault',
                'version': '3.7.0',
                'buildNumber': '1',
              });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kanal, null));
    });

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_modellsprache_');
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryState()
        ..db = db
        ..paths =
            await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')))
        ..modelDownloadService = ModelDownloadService(
            (Directory(p.join(wurzel.path, 'models'))
                  ..createSync(recursive: true))
                .path);
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    /// Geprüft wird nicht die Regel – die steht oben –, sondern die
    /// **Verdrahtung**: Fragt der Bildschirm sie überhaupt?
    Future<List<String>> titel(WidgetTester tester, String sprache) async {
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(sprache),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: SettingsScreen(library: library)),
      ));
      Future<void> takte() async {
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      await takte();
      // Ueber die Suche in den Einstellungen: Die Liste ist faul, und die
      // Modellgruppe steht so weit unten, dass sie ungebaut bliebe.
      await tester.enterText(find.byType(SearchBar),
          sprache == 'de' ? 'KI-Modelle' : 'AI models');
      await takte();

      final gefunden = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          if ((w.data ?? '').contains('OPUS-MT')) w.data!,
      ];
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      return gefunden;
    }

    testWidgets('auf Deutsch stehen beide OPUS-MT-Karten da', (tester) async {
      await tester.runAsync(() async {
        expect(await titel(tester, 'de'), hasLength(2));
      });
    });

    testWidgets('auf Englisch steht keine da', (tester) async {
      await tester.runAsync(() async {
        expect(await titel(tester, 'en'), isEmpty);
      });
    });
  });
}

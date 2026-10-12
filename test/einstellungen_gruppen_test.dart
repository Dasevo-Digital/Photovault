import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:kern/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/mini_location_map.dart'
    show setzeCartoSchluessel, setzeKarteHochaufloesend;
import 'package:photo_vault/widgets/tastenkuerzel.dart';

/// **Jede Gruppe der Einstellungen, einmal geöffnet und einmal bedient.**
///
/// Angelegt vor dem Aufteilen von settings_screen.dart in eigene
/// Gruppen-Dateien (#41): Die Datei hatte gut 3.400 Zeilen und einen
/// einzigen Test, der zwei Modellkarten zählte. Diese Tests halten fest,
/// was jede Gruppe zeigt und was ihre Bedienelemente in die Datenbank
/// schreiben – und zwei Eigenschaften, die ein Umbau leicht verliert:
///
/// * **Was man eingibt, überdauert das Zuklappen.** Der Inhalt einer
///   Gruppe wird beim Zuklappen verworfen; ihr Zustand liegt deshalb beim
///   Bildschirm. Ein Häkchen oder ein halb getippter Schlüssel darf beim
///   Wiederaufklappen nicht weg sein.
/// * **Der Sprachwechsel fragt nach dem Vokabular**, obwohl die App dabei
///   jede Gruppe neu baut (ihre Titel ändern sich). Die Rückfrage läuft im
///   Kontext des Bildschirms, nicht der Gruppe.
///
/// Die App wird wie in main.dart gebaut: Die Sprache kommt aus der
/// Datenbank, ein Wechsel baut also wirklich alles in der neuen Sprache.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  final de = lookupAppTexte(const Locale('de'));
  final en = lookupAppTexte(const Locale('en'));

  setUpAll(() async => initializeDateFormatting());

  setUp(() {
    const ablage = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ablage, (_) async => wurzel.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ablage, null),
    );
    const paket = MethodChannel('dev.fluttercommunity.plus/package_info');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          paket,
          (_) async => <String, String>{
            'appName': 'Photo Vault',
            'packageName': 'de.dasevo.photovault',
            'version': '3.7.0',
            'buildNumber': '1',
          },
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(paket, null),
    );
  });

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_einstellungen_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'bibliothek')),
      )
      ..modelDownloadService = ModelDownloadService(
        (Directory(
          p.join(wurzel.path, 'models'),
        )..createSync(recursive: true)).path,
      );
  });

  tearDown(() async {
    // Zwei Einstellungen wirken über globale Schalter auf jede Karte.
    setzeCartoSchluessel('');
    setzeKarteHochaufloesend(true);
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> takte(WidgetTester tester, [int runden = 8]) async {
    for (var i = 0; i < runden; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      StreamBuilder<AppSettingsData?>(
        stream: db.watchAppSettings(),
        builder: (context, einstellungen) => MaterialApp(
          locale:
              localeFromString(einstellungen.data?.sprache) ??
              const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: Scaffold(body: SettingsScreen(library: library)),
        ),
      ),
    );
    await takte(tester);
  }

  /// Öffnet Gruppen über die Suche – die Liste ist faul, und weiter unten
  /// stehende Gruppen wären sonst gar nicht gebaut. Bei einem Treffer
  /// erscheint eine Gruppe aufgeklappt.
  Future<void> suche(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(SearchBar), text);
    await takte(tester);
  }

  /// [finder] innerhalb der Gruppe mit dem Titel [titel].
  Finder inGruppe(String titel, Finder finder) => find.descendant(
    of: find
        .ancestor(of: find.text(titel), matching: find.byType(ExpansionTile))
        .first,
    matching: finder,
  );

  /// Der Kopf der Gruppe [titel] – der Titel steht nach einer Suche auch
  /// im Suchfeld.
  Finder kopf(String titel) => find
      .descendant(of: find.byType(ExpansionTile), matching: find.text(titel))
      .first;

  Future<void> raeumeAb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('Erscheinungsbild: Design und Schwebe-Vorschau', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittErscheinungsbild);
      await tester.tap(find.text(de.einstDesignHell));
      await takte(tester);
      expect(
        themeModeFromString((await db.watchAppSettings().first)?.themeMode),
        ThemeMode.light,
      );
      await tester.tap(find.text(de.einstSchwebeVorschauTitel));
      await takte(tester);
      expect((await db.watchAppSettings().first)?.schwebeVorschau, isFalse);
      await raeumeAb(tester);
    });
  });

  testWidgets('Sprache: der Wechsel fragt nach dem Vokabular, in der neuen '
      'Sprache', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.spracheTitel);
      await tester.tap(find.text(de.spracheEnglisch));
      await takte(tester, 12);
      expect(await db.spracheWert(), 'en');
      // Die Gruppen sind jetzt englisch beschriftet und damit neu gebaut;
      // die Rückfrage kommt trotzdem.
      expect(find.text(en.spracheVokabularTitel), findsOneWidget);
      await tester.tap(find.text(en.spracheVokabularBehalten));
      await takte(tester);
      expect(find.text(en.spracheVokabularTitel), findsNothing);
      await raeumeAb(tester);
    });
  });

  testWidgets('Überwachter Ordner: noch keiner', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstUeberwachtTitel);
      expect(find.text(de.einstUeberwachtKeiner), findsOneWidget);
      expect(find.text(de.einstUeberwachtWaehlen), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Bibliotheken: die aktive steht in der Liste', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstBibListe);
      expect(
        inGruppe(de.einstBibListe, find.text(de.einstBibHinzufuegen)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Speicherort: Pfad und berechnete Belegung', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstSpeicherortTitel);
      expect(find.text(library.paths.root.path), findsOneWidget);
      expect(find.text(de.einstSpeicherbedarf), findsOneWidget);
      expect(find.text(de.einstWirdBerechnet), findsNothing);
      await raeumeAb(tester);
    });
  });

  testWidgets('Modelle: Autoanalyse-Schalter und jede Modellkarte', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittModelle);
      for (final e in ModelCatalog.fuerSprache(
        'de',
        istInstalliert: (_) => false,
      )) {
        expect(find.text(modellTitel(de, e.id)), findsOneWidget, reason: e.id);
      }
      expect(await db.autoAnalyzeAfterImportEnabled(), isTrue);
      await tester.tap(find.text(de.einstAutoAnalyseTitel));
      await takte(tester);
      expect(await db.autoAnalyzeAfterImportEnabled(), isFalse);
      // Und der Schalter zeigt es auch.
      final schalter = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(de.einstAutoAnalyseTitel),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(schalter.value, isFalse);
      await raeumeAb(tester);
    });
  });

  testWidgets('Hintergrund: der Weg zu den Aufgaben', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittHintergrund);
      expect(find.text(de.einstAufgabenTitel), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Vokabular: ein Begriff kommt hinzu', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittVokabular);
      expect(find.text(de.einstKiTagsZurueck), findsOneWidget);
      await tester.enterText(
        inGruppe(de.einstAbschnittVokabular, find.byType(TextField)),
        'Probebegriff',
      );
      await tester.tap(find.byTooltip(de.einstBegriffHinzufuegen));
      await takte(tester);
      expect(await db.aiTagVocabularyTerms(), contains('Probebegriff'));
      expect(find.widgetWithText(InputChip, 'Probebegriff'), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Standortdaten: zum Herunterladen angeboten', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittStandortdaten);
      expect(find.text(de.einstGeoTitel), findsOneWidget);
      expect(
        inGruppe(
          de.einstAbschnittStandortdaten,
          find.text(de.allgHerunterladen),
        ),
        findsOneWidget,
      );
      await raeumeAb(tester);
    });
  });

  testWidgets('Karte: Schlüssel speichern, doppelte Auflösung schalten', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittKarte);
      expect(find.text(de.einstCartoOhne), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, de.einstCartoFeld),
        'probeschluessel',
      );
      // Zwei Knöpfe „Speichern" in der Gruppe – gemeint ist der neben dem
      // CARTO-Feld, nicht der der eigenen Kartenquelle.
      await tester.tap(
        find.descendant(
          of: find
              .ancestor(
                of: find.widgetWithText(TextField, de.einstCartoFeld),
                matching: find.byType(Row),
              )
              .first,
          matching: find.widgetWithText(FilledButton, de.allgSpeichern),
        ),
      );
      await takte(tester);
      expect(await db.cartoSchluesselWert(), 'probeschluessel');
      expect(find.text(de.einstCartoAktiv), findsOneWidget);

      expect(await db.karteHochaufloesendWert(), isTrue);
      await tester.tap(find.text(de.einstKarteScharfTitel));
      await takte(tester);
      expect(await db.karteHochaufloesendWert(), isFalse);
      await raeumeAb(tester);
    });
  });

  testWidgets('Karte: ein halb getippter Schlüssel überdauert das Zuklappen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittKarte);
      await tester.enterText(
        find.widgetWithText(TextField, de.einstCartoFeld),
        'halb',
      );
      await takte(tester);
      await tester.tap(kopf(de.einstAbschnittKarte));
      await takte(tester);
      expect(find.widgetWithText(TextField, de.einstCartoFeld), findsNothing);
      await tester.tap(kopf(de.einstAbschnittKarte));
      await takte(tester);
      final feld = tester.widget<TextField>(
        find.widgetWithText(TextField, de.einstCartoFeld),
      );
      expect(feld.controller!.text, 'halb');
      await raeumeAb(tester);
    });
  });

  testWidgets('Gesperrter Ordner: ohne PIN wird eingerichtet', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittGesperrterOrdner);
      expect(find.text(de.einstPinEinrichten), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Sicherungsschlüssel: ohne Passphrase wird eingerichtet', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstBackupVerschluesselungTitel);
      expect(find.text(de.einstPassphraseEinrichten), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Sicherung von Hand: das Häkchen überdauert das Zuklappen', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittManuellesBackup);
      expect(find.text(de.einstBackupNieGesichert), findsOneWidget);
      Finder haekchen() => find.ancestor(
        of: find.text(de.einstBackupVerschluesseln),
        matching: find.byType(CheckboxListTile),
      );
      expect(tester.widget<CheckboxListTile>(haekchen()).value, isFalse);
      await tester.tap(haekchen());
      await takte(tester);
      expect(tester.widget<CheckboxListTile>(haekchen()).value, isTrue);

      await tester.tap(kopf(de.einstAbschnittManuellesBackup));
      await takte(tester);
      expect(haekchen(), findsNothing);
      await tester.tap(kopf(de.einstAbschnittManuellesBackup));
      await takte(tester);
      expect(tester.widget<CheckboxListTile>(haekchen()).value, isTrue);
      await raeumeAb(tester);
    });
  });

  testWidgets('Automatische Sicherung: ohne Ziel nicht einschaltbar', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittAutoBackup);
      expect(find.text(de.einstBackupKeinOrdner), findsOneWidget);
      final schalter = tester.widget<SwitchListTile>(
        inGruppe(de.einstAbschnittAutoBackup, find.byType(SwitchListTile)),
      );
      expect(schalter.onChanged, isNull);
      await raeumeAb(tester);
    });
  });

  testWidgets('Papierkorb: die automatische Leerung lässt sich einschalten', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittPapierkorb);
      expect(find.text(de.papierkorbLeer), findsOneWidget);
      expect(
        (await db.trashSettingsRow())?.autoDeleteEnabled ?? false,
        isFalse,
      );
      await tester.tap(
        inGruppe(de.einstAbschnittPapierkorb, find.byType(SwitchListTile)),
      );
      await takte(tester);
      expect((await db.trashSettingsRow())?.autoDeleteEnabled, isTrue);
      final schalter = tester.widget<SwitchListTile>(
        inGruppe(de.einstAbschnittPapierkorb, find.byType(SwitchListTile)),
      );
      expect(schalter.value, isTrue);
      await raeumeAb(tester);
    });
  });

  testWidgets('Gefahrenzone: der Knopf steht da', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstAbschnittGefahrenzone);
      expect(find.text(de.einstResetTitel), findsOneWidget);
      expect(find.text(de.einstResetKnopf), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Tastenkürzel: die Tafel', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.kuerzelTitel);
      expect(find.byType(Tastenkuerzeltafel), findsOneWidget);
      await raeumeAb(tester);
    });
  });

  testWidgets('Über: Fassung und Datenbankstand', (tester) async {
    await tester.runAsync(() async {
      await zeige(tester);
      await suche(tester, de.einstUeberTitel);
      expect(find.text('Photo Vault 3.7.0'), findsOneWidget);
      expect(
        find.text(de.einstDatenbankStand(db.schemaVersion)),
        findsOneWidget,
      );
      expect(find.text(de.einstNachAktualisierungSuchen), findsOneWidget);
      await raeumeAb(tester);
    });
  });
}

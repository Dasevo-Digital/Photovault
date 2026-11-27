import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/export_presets_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/wasserzeichen_editor.dart';

/// Das Wasserzeichen im Editor der Exportvorgaben (#497).
void main() {
  final de = AppTexteDe();
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_vorgabe_zeichen_');
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

  Widget app(Widget kind) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppTexte.localizationsDelegates,
    supportedLocales: AppTexte.supportedLocales,
    home: kind,
  );

  testWidgets('ein Text-Wasserzeichen anlegen; ohne Rendern gesperrt', (
    tester,
  ) async {
    // Kein `pumpAndSettle`: Die Liste zeigt beim Laden einen Kreisel.
    Future<void> weiter() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ExportPresetsScreen(library: library)));
    await weiter();

    await tester.tap(find.byTooltip(de.exportVorgabeNeu));
    await weiter();
    await tester.enterText(
      find.widgetWithText(TextField, de.exportVorgabeName),
      'Fotoclub',
    );

    final schalter = find.byKey(const ValueKey('wasserzeichenSchalter'));
    SwitchListTile kachel() => tester.widget<SwitchListTile>(schalter);
    expect(kachel().value, isFalse, reason: 'neu ohne Zeichen');
    expect(kachel().onChanged, isNotNull);

    // Ohne „Nach JPEG rendern“: gesperrt, mit Begründung.
    await tester.tap(
      find.widgetWithText(SwitchListTile, de.exportVorgabeNachJpeg),
    );
    await weiter();
    expect(kachel().onChanged, isNull);
    expect(find.text(de.wasserzeichenNurGerendert), findsOneWidget);
    await tester.tap(
      find.widgetWithText(SwitchListTile, de.exportVorgabeNachJpeg),
    );
    await weiter();

    await tester.ensureVisible(schalter);
    await tester.tap(schalter);
    await weiter();
    expect(find.byType(WasserzeichenEditor), findsOneWidget);

    // Ohne Text lässt es sich nicht speichern.
    final speichern = find.widgetWithText(FilledButton, de.allgSpeichern);
    await tester.tap(speichern);
    await weiter();
    expect(find.text(de.wasserzeichenFehlt), findsOneWidget);
    expect(await db.alleExportPresets(), isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, de.wasserzeichenText),
      '© 2026 Fotoclub',
    );
    final obenLinks = find.byKey(const ValueKey('wasserzeichenLage_obenLinks'));
    await tester.ensureVisible(obenLinks);
    await tester.tap(obenLinks);
    await weiter();
    await tester.tap(speichern);
    await weiter();

    final gespeichert = (await db.alleExportPresets()).single;
    final w = Wasserzeichen.ausKodiert(gespeichert.wasserzeichen)!;
    expect(w.art, Wasserzeichenart.text);
    expect(w.text, '© 2026 Fotoclub');
    expect(w.lage, Wasserzeichenlage.obenLinks);
    expect(w.bild, isNull);
    // Die Zusammenfassung in der Liste (und im Exportdialog) nennt es.
    await weiter();
    expect(
      find.textContaining(de.exportVorgabeMitWasserzeichen),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('ausgeschaltet wird das Zeichen nicht gespeichert', (
    tester,
  ) async {
    Future<void> weiter() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    await db.upsertExportPreset(
      ExportPresetsCompanion.insert(
        name: 'Web',
        nachJpeg: const Value(true),
        wasserzeichen: Value(const Wasserzeichen(text: '© alt').kodiert()),
        erstelltAm: DateTime(2026),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ExportPresetsScreen(library: library)));
    await weiter();
    await tester.tap(find.byTooltip(de.allgBearbeiten));
    await weiter();

    final schalter = find.byKey(const ValueKey('wasserzeichenSchalter'));
    expect(tester.widget<SwitchListTile>(schalter).value, isTrue);
    expect(find.widgetWithText(TextField, '© alt'), findsOneWidget);
    await tester.ensureVisible(schalter);
    await tester.tap(schalter);
    await weiter();
    await tester.tap(find.widgetWithText(FilledButton, de.allgSpeichern));
    await weiter();
    final gespeichert = (await db.alleExportPresets()).single;
    expect(gespeichert.wasserzeichen, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('ein Logo wählen: PNG ja, anderes nein', (tester) async {
    final logo = Uint8List.fromList(
      img.encodePng(
        img.Image(width: 40, height: 20, numChannels: 4)
          ..clear(img.ColorRgba8(255, 0, 0, 200)),
      ),
    );
    var datei = logo;
    Wasserzeichen? zuletzt;
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        Scaffold(
          body: SingleChildScrollView(
            child: WasserzeichenEditor(
              wert: const Wasserzeichen(),
              beiAenderung: (w) => zuletzt = w,
              logoWaehlen: (_) async => datei,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text(de.wasserzeichenArtLogo));
    await tester.pumpAndSettle();
    expect(zuletzt?.art, Wasserzeichenart.bild);
    expect(find.text(de.wasserzeichenLogoHinweis), findsOneWidget);

    // Das Vorbereiten läuft in einem Isolate – echte Zeit statt der
    // gestellten Uhr des Tests.
    Future<void> waehle() async {
      await tester.tap(find.text(de.wasserzeichenLogoWaehlen));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    await waehle();
    expect(zuletzt?.bild, logo);
    expect(zuletzt!.vollstaendig, isTrue);

    // Ein JPEG trägt keine Transparenz: abgelehnt, das Logo bleibt.
    datei = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    await waehle();
    expect(find.text(de.wasserzeichenLogoUngueltig), findsOneWidget);
    expect(zuletzt?.bild, logo);

    // Lage, Grösse, Deckkraft und Rand gehen mit.
    await tester.tap(find.byKey(const ValueKey('wasserzeichenLage_mitte')));
    await tester.pumpAndSettle();
    expect(zuletzt?.lage, Wasserzeichenlage.mitte);
    final regler = find.byType(Slider);
    expect(regler, findsNWidgets(3));
    await tester.drag(regler.at(1), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(zuletzt?.deckkraft, Wasserzeichen.deckkraftMin);
    expect(find.text(de.wasserzeichenDeckkraft(10)), findsOneWidget);
  });
}

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/xmp_import_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// „Alle übernehmen“ stand fest weiss in der Kopfleiste – im hellen
/// Erscheinungsbild weiss auf fast weiss (IMP-107).
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_xmp_knopf_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'k.jpg',
            relativePath: 'originals/k.jpg',
            checksum: 'c',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024),
            importedAt: DateTime(2024),
            rating: const Value(0),
          ),
        );
    final beilage = library.paths.absolute(
      library.paths.xmpSidecarPath('originals/k.jpg'),
    );
    beilage.parent.createSync(recursive: true);
    beilage.writeAsStringSync(
      '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
      'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description rdf:about="" '
      'xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>'
      '</rdf:RDF></x:xmpmeta>',
    );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  double kontrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  for (final (name, thema) in [
    ('hell', buildLightTheme()),
    ('dunkel', buildDarkTheme()),
  ]) {
    testWidgets('„Alle übernehmen“ ist $name lesbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: thema,
          home: XmpImportScreen(library: library),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byType(TextButton).evaluate().isNotEmpty) break;
        }
      });
      final de = AppTexte.of(tester.element(find.byType(XmpImportScreen)));
      final schrift = tester.widget<RichText>(
        find.descendant(
          of: find.widgetWithText(TextButton, de.xmpAlleUebernehmen),
          matching: find.byType(RichText),
        ),
      );
      // Die Fläche der Kopfleiste: ihr erstes Material, nicht das des
      // Knopfs (das ist durchsichtig).
      final leiste = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      final vorne = schrift.text.style!.color!;
      expect(
        kontrast(vorne, leiste),
        greaterThanOrEqualTo(3.0),
        reason: 'Schrift $vorne auf $leiste',
      );
    });
  }
}

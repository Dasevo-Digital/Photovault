import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/stack_review_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';

class _SerienBibliothek extends LibraryState {
  List<List<AssetData>> gruppen = [];

  @override
  bool get clipAvailable => true;

  @override
  Future<List<List<AssetData>>> serienvorschlaegeGecacht() async => gruppen;
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late _SerienBibliothek library;
  late List<AssetData> vorher;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_serien_dialog_');
    db = AppDatabase(NativeDatabase.memory());
    library = _SerienBibliothek()
      ..db = db
      ..paths = await StoragePaths.forTesting(temp);
    for (var gruppe = 0; gruppe < 2; gruppe++) {
      for (var i = 0; i < 3; i++) {
        final id = 'serie${gruppe}_$i';
        final pfad = 'originals/$id.jpg';
        final datei = File('${temp.path}/$pfad');
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes([gruppe, i, 17, 23]);
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: pfad,
                checksum: 'inhalt-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, 1, 1),
                importedAt: DateTime(2026, 1, 1),
              ),
            );
      }
    }
    vorher = await db.select(db.assets).get();
    library.gruppen = [
      for (var g = 0; g < 2; g++)
        vorher.where((a) => a.id.startsWith('serie${g}_')).toList(),
    ];
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
    library.dispose();
  });

  Future<void> oeffne(WidgetTester tester, Locale sprache) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: sprache,
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: StackReviewScreen(library: library),
      ),
    );
    await tester.pumpAndSettle();
    final label = sprache.languageCode == 'de'
        ? 'Alle 2 übernehmen'
        : 'Accept all 2';
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  for (final sprache in [const Locale('de'), const Locale('en')]) {
    final de = sprache.languageCode == 'de';
    final bestaetigen = de ? 'Übernehmen' : 'Apply';
    testWidgets(
      'Serien ${sprache.languageCode}: Abbrechen ändert keine Fotos',
      (tester) async {
        await oeffne(tester, sprache);
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(of: dialog, matching: find.text(bestaetigen)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(de ? 'Löschen' : 'Delete'),
          ),
          findsNothing,
        );
        await tester.tap(find.text(de ? 'Abbrechen' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(await db.select(db.assets).get(), vorher);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Serien ${sprache.languageCode}: Übernehmen erhält Originale', (
      tester,
    ) async {
      await oeffne(tester, sprache);
      final button = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, bestaetigen),
      );
      expect(button, findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      final farben = Theme.of(tester.element(button)).colorScheme;
      expect(material.color, farben.primary);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final nachher = await db.select(db.assets).get();
      expect(nachher, hasLength(6));
      expect(nachher.map((a) => a.stackId).toSet(), hasLength(2));
      expect(nachher.every((a) => a.stackId != null && !a.isTrashed), isTrue);
      expect(nachher.where((a) => a.isStackCover), hasLength(2));
      for (final a in vorher) {
        final neu = nachher.singleWhere((b) => b.id == a.id);
        expect(neu.relativePath, a.relativePath);
        expect(neu.checksum, a.checksum);
        final gruppe = a.id.startsWith('serie0_') ? 0 : 1;
        final index = int.parse(a.id.split('_').last);
        expect(File('${temp.path}/${a.relativePath}').readAsBytesSync(), [
          gruppe,
          index,
          17,
          23,
        ]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Echtes Löschen behält Beschriftung und Warnfarbe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmDialog(context, 'Entfernen?', 'Eine Datei'),
            child: const Text('Öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Löschen');
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );
    expect(material.color, Theme.of(tester.element(button)).colorScheme.error);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
  });
}

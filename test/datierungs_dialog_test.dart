import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/datierungs_dialog.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:kern/db/database.dart';
import 'package:drift/native.dart';

void main() {
  testWidgets(
    'Datierung in schmalem Fenster und mit großer Schrift speicherbar',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'a',
          originalFileName: 'a.jpg',
          relativePath: 'a.jpg',
          checksum: 'a',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2026),
        ),
      );
      final a = (await db.assetById('a'))!;
      AufnahmeDatierung? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.7)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await frageDatierung(context, a);
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '1985');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(result!.genauigkeit, Datierungsgenauigkeit.jahr);
      expect(result!.von, DateTime.utc(1985));
      expect(tester.takeException(), isNull);
    },
  );
}

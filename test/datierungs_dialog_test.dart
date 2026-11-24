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

  // ANS-151 (#491): In der Prüfrunde kam nach dem abgelehnten „85“ und dem
  // Wechsel auf „Monat“ die Eingabe „1985-13“ nicht im Feld an, und
  // „Speichern“ legte den vom Wechsel gesetzten Monat ab. Hier dieselbe
  // Folge ohne den Prüfstand, an dem in der Runde Animationen hingen.
  testWidgets('abgelehnte Eingaben bleiben abgelehnt, auch nach dem Wechsel '
      'der Genauigkeit (ANS-151)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'a',
        originalFileName: 'a.jpg',
        relativePath: 'a.jpg',
        checksum: 'a',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2024, 3, 9),
        importedAt: DateTime(2026),
      ),
    );
    final a = (await db.assetById('a'))!;
    var geschlossen = false;
    AufnahmeDatierung? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await frageDatierung(context, a);
                geschlossen = true;
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    final feld = find.byType(TextField).first;
    final ungueltig = find.text(
      'Bitte einen gültigen Kalenderbereich eingeben.',
    );

    Future<void> genauigkeit(String name) async {
      await tester.tap(
        find.byType(DropdownButtonFormField<Datierungsgenauigkeit>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    String feldtext() => tester.widget<TextField>(feld).controller!.text;

    await tester.enterText(feld, '85');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(ungueltig, findsOneWidget);

    await genauigkeit('Monat');
    expect(feldtext(), '2024-03', reason: 'der bisherige Monat');
    await tester.enterText(feld, '1985-13');
    expect(feldtext(), '1985-13');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(geschlossen, isFalse);
    expect(ungueltig, findsOneWidget);

    await genauigkeit('Tag');
    await tester.enterText(feld, '1985-02-30');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(geschlossen, isFalse);

    await genauigkeit('Zeitraum');
    await tester.enterText(feld, '1985-06-10');
    await tester.enterText(find.byType(TextField).at(1), '1985-06-01');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(geschlossen, isFalse);
    expect(ungueltig, findsOneWidget);

    // Und danach nimmt er eine gültige Angabe an.
    await genauigkeit('Monat');
    await tester.enterText(feld, '1985-06');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(geschlossen, isTrue);
    expect(result!.genauigkeit, Datierungsgenauigkeit.monat);
    expect(result!.von, DateTime.utc(1985, 6));
  });
}

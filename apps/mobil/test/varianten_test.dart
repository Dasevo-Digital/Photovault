import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/varianten.dart';
import 'package:photo_vault_mobil/sitzung.dart';

/// Varianten auf dem Telefon wie am Rechner (#219): bilden mit gewählter
/// Hauptversion, Hauptversion wechseln, wieder einzeln zeigen.
void main() {
  late AppDatabase db;
  late Sitzung sitzung;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sitzung = Sitzung()..db = db;
    for (final (id, name) in [
      ('roh', 'IMG_0001.DNG'),
      ('jpg', 'IMG_0001.JPG'),
      ('bearb', 'IMG_0001 bearbeitet.jpg'),
    ]) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: name,
          relativePath: 'originals/$id',
          checksum: id,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 5, 1, 12),
          importedAt: DateTime(2026, 5, 2),
        ),
      );
    }
  });
  tearDown(() => db.close());

  Future<(BuildContext, AppTexte)> zeige(WidgetTester tester) async {
    late BuildContext innen;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              innen = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return (innen, AppTexte.of(innen));
  }

  Future<List<Rasterzeile>> zeilen(List<String> ids) async => [
    for (final a in await db.assetsByIds(ids)) Rasterzeile.aus(a),
  ];

  testWidgets('bilden mit gewählter Hauptversion', (tester) async {
    final (innen, t) = await zeige(tester);
    final auswahl = await zeilen(['roh', 'jpg', 'bearb']);
    final fertig = variantenBilden(innen, sitzung, auswahl);
    await tester.pumpAndSettle();
    expect(find.text(t.variantenHauptWaehlen), findsOneWidget);
    await tester.tap(find.text('IMG_0001 bearbeitet.jpg'));
    await tester.pump();
    await tester.tap(find.text(t.speichern));
    await tester.pumpAndSettle();
    expect(await fertig, isTrue);

    final alle = await db.assetsByIds(['roh', 'jpg', 'bearb']);
    final stapel = alle.map((a) => a.stackId).toSet();
    expect(stapel, hasLength(1));
    expect(istVariantenstapel(stapel.single), isTrue);
    expect(
      alle.singleWhere((a) => a.isStackCover).id,
      'bearb',
      reason: 'die gewählte Fassung ist die Hauptversion',
    );
    expect(find.text(t.variantenGebildet(3)), findsOneWidget);
  });

  testWidgets('schon Gestapeltes wird abgewiesen', (tester) async {
    await db.createStack('serie-1', ['roh', 'jpg'], 'roh');
    final (innen, t) = await zeige(tester);
    final fertig = variantenBilden(
      innen,
      sitzung,
      await zeilen(['jpg', 'bearb']),
    );
    await tester.pumpAndSettle();
    expect(await fertig, isFalse);
    expect(find.text(t.variantenSchonGestapelt), findsOneWidget);
    expect(find.text(t.variantenHauptWaehlen), findsNothing);
    expect((await db.assetById('bearb'))!.stackId, isNull);
  });

  testWidgets('Hauptversion wechseln und einzeln zeigen', (tester) async {
    const stapel = 'variante:v1';
    await db.createStack(stapel, ['roh', 'jpg', 'bearb'], 'roh');
    final (innen, t) = await zeige(tester);

    final gewechselt = hauptversionWechseln(
      innen,
      sitzung,
      stapel,
      await db.assetsByIds(['roh', 'jpg', 'bearb']),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('IMG_0001.JPG'));
    await tester.pump();
    await tester.tap(find.text(t.speichern));
    await tester.pumpAndSettle();
    expect(await gewechselt, isTrue);
    expect((await db.assetById('jpg'))!.isStackCover, isTrue);
    expect((await db.assetById('roh'))!.isStackCover, isFalse);

    final einzeln = variantenAufloesen(innen, sitzung, stapel, 3);
    await tester.pumpAndSettle();
    expect(find.text(t.variantenEinzelnFrage(3)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, t.variantenEinzeln));
    await tester.pumpAndSettle();
    expect(await einzeln, isTrue);
    for (final a in await db.assetsByIds(['roh', 'jpg', 'bearb'])) {
      expect(a.stackId, isNull);
    }
  });
}

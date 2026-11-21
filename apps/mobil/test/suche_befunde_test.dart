// Suche und intelligente Alben: behobene Befunde aus dem Prüfkatalog der
// Handy-App (MOB, Issue #418): je Befund ein Test, der ohne die Korrektur
// scheitert.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/alben.dart';
import 'package:photo_vault_mobil/seiten/raster.dart';
import 'package:photo_vault_mobil/seiten/suche.dart';
import 'package:photo_vault_mobil/sitzung.dart';

Widget _app(Widget inhalt) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppTexte.localizationsDelegates,
  supportedLocales: AppTexte.supportedLocales,
  home: Scaffold(body: inhalt),
);

/// Eine Kopie mit den Aufnahmen [ids] (Dateiname `<id>.jpg`) und einem
/// Server, der so antwortet wie [server].
Future<(Sitzung, AppDatabase)> _sitzung(
  WidgetTester tester,
  List<String> ids,
  Future<http.Response> Function(http.Request) server,
) async {
  final ordner = Directory.systemTemp.createTempSync('pv_suche_befund_');
  addTearDown(() => ordner.deleteSync(recursive: true));
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  for (final id in ids) {
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: 'pruef-$id',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2025),
        importedAt: DateTime(2026),
      ),
    );
  }
  final pfade = (await tester.runAsync(() => StoragePaths.forTesting(ordner)))!;
  final verbindung = Serververbindung(
    Uri.parse('https://fotos.example/'),
    't',
    client: MockClient(server),
  );
  return (
    Sitzung()
      ..db = db
      ..paths = pfade
      ..abgleich = Abgleich(db, verbindung),
    db,
  );
}

Future<void> _ruhe(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}

List<String> _raster(WidgetTester tester) => [
  for (final z
      in tester.widget<AufnahmenRaster>(find.byType(AufnahmenRaster)).zeilen)
    z.id,
];

Future<void> _abbauen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('MOB-085 intelligentes Album nach Bildinhalt ohne Modell: '
      'Hinweis und die Treffer der Textsuche', (tester) async {
    final (sitzung, db) = await _sitzung(tester, [
      'hund',
      'katze',
    ], (_) async => http.Response('{"fehler": "kein Modell"}', 404));
    await tester.runAsync(
      () => db.fuehreAus(
        const SucheMerken(
          'g1',
          'Hunde',
          SearchFilters(query: 'hund', textMode: SearchTextMode.context),
        ),
      ),
    );
    final suche = (await tester.runAsync(db.gespeicherteSuchen))!.single;
    await tester.pumpWidget(
      _app(IntelligentesAlbumSeite(sitzung: sitzung, suche: suche)),
    );
    await _ruhe(tester);
    final t = AppTexte.of(tester.element(find.byType(AufnahmenRaster)));
    expect(find.text(t.sucheKeinModell), findsOneWidget);
    expect(_raster(tester), ['hund']);
    await _abbauen(tester);
  });

  testWidgets('MOB-113 Bildinhalt ohne Netz: Hinweis statt „hat nicht '
      'geklappt“, Treffer aus der Kopie', (tester) async {
    final (sitzung, _) = await _sitzung(tester, [
      'hund',
      'katze',
    ], (_) async => throw http.ClientException('Verbindung abgelehnt'));
    await tester.pumpWidget(_app(Suche(sitzung: sitzung)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Suche)));
    await tester.enterText(find.byType(TextField), 'hund');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _ruhe(tester);
    expect(find.text(t.sucheFehler), findsNothing);
    expect(find.text(t.sucheInhaltOhneServer), findsOneWidget);
    expect(_raster(tester), ['hund']);

    await tester.tap(find.text(t.sucheText));
    await _ruhe(tester);
    expect(_raster(tester), ['hund'], reason: 'Text sucht in der Kopie');
    await _abbauen(tester);
  });

  testWidgets('MOB-115 „Zurücksetzen“ neben der Filterzeile leert ohne '
      'Suchtext auch die Treffer', (tester) async {
    final (sitzung, db) = await _sitzung(tester, [
      's1',
      's2',
    ], (_) async => http.Response('{}', 404));
    await tester.runAsync(
      () => db.fuehreAus(const FavoritSetzen(['s2'], true)),
    );
    await tester.pumpWidget(_app(Suche(sitzung: sitzung)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Suche)));
    await tester.tap(find.byTooltip(t.sucheFilter));
    await _ruhe(tester);
    await tester.tap(find.text(t.sucheFilterFavoriten));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.sucheFilterAnwenden));
    await _ruhe(tester);
    expect(_raster(tester), ['s2']);

    await tester.tap(find.byTooltip(t.sucheFilterZuruecksetzen));
    await _ruhe(tester);
    expect(find.textContaining('Filter:'), findsNothing);
    expect(_raster(tester), isEmpty);
    expect(find.text(t.sucheTextOderFilter), findsOneWidget);
    await _abbauen(tester);
  });
}

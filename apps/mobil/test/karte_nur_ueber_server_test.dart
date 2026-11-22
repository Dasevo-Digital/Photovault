import 'dart:io';

import 'package:abgleich_ui/l10n/sync_texte.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap, TileLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:gelaende/texte.dart' show GelaendeTexte;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/karte.dart';
import 'package:photo_vault_mobil/seiten/landschaft.dart';
import 'package:photo_vault_mobil/seiten/reisen.dart';
import 'package:photo_vault_mobil/sitzung.dart';

/// Liefert der Server keine Kacheln, holt das Telefon sie nicht selbst
/// (#469) – und jede Karte sagt das, statt leer und kaputt auszusehen.
void main() {
  Future<(_Sitzung, AppDatabase)> sitzungMitOrt(WidgetTester tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_karte_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'a1',
        originalFileName: 'a1.jpg',
        relativePath: 'originals/a1.jpg',
        checksum: 'pruef-a1',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 8, 30, 9),
        importedAt: DateTime(2026),
        latitude: const Value(51.83),
        longitude: const Value(10.64),
      ),
    );
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    return (
      _Sitzung()
        ..db = db
        ..paths = pfade,
      db,
    );
  }

  Widget app(Widget seite) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: const [
      ...AppTexte.localizationsDelegates,
      SyncTexte.delegate,
      GelaendeTexte.delegate,
    ],
    supportedLocales: AppTexte.supportedLocales,
    home: Scaffold(body: seite),
  );

  testWidgets('Karte: Hinweis, solange der Server keine Kacheln liefert, '
      'danach neu geladen', (tester) async {
    final (sitzung, _) = await sitzungMitOrt(tester);
    await tester.pumpWidget(app(Karte(sitzung: sitzung)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    final t = AppTexte.of(tester.element(find.byType(Karte)));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text(t.karteNurUeberServer), findsOneWidget);
    final vorher = tester.state(find.byType(TileLayer));

    sitzung.meldeKarten(true);
    await tester.pump();
    expect(find.text(t.karteNurUeberServer), findsNothing);
    expect(
      identical(tester.state(find.byType(TileLayer)), vorher),
      isFalse,
      reason: 'die abgewiesenen Kacheln werden gleich neu geholt',
    );

    // Bleibt der Server fähig, baut nicht jede Meldung der Sitzung die
    // Schicht neu.
    final danach = tester.state(find.byType(TileLayer));
    sitzung.meldeKarten(true);
    await tester.pump();
    expect(identical(tester.state(find.byType(TileLayer)), danach), isTrue);
  });

  testWidgets('Reisen und Gelände: derselbe Hinweis auf der Karte der '
      'Aktivität, ein eigener in der Landschaft', (tester) async {
    final (sitzung, db) = await sitzungMitOrt(tester);
    await tester.runAsync(() async {
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'runde',
          name: 'Ilsetal',
          art: 'wanderung',
          von: DateTime(2026, 8, 30, 9),
          bis: DateTime(2026, 8, 30, 14),
          angelegtAm: DateTime(2026, 9, 1),
        ),
        ['a1'],
      );
      await db.fuehreAus(
        SpurAnlegen(
          id: 'spur',
          name: 'Ilsetal.gpx',
          quelle: 'Ilsetal.gpx',
          aktivitaetId: 'runde',
          laengeKm: 3.2,
          aufstieg: 180,
          abstieg: 175,
          angelegtAm: DateTime(2026, 9, 1),
          punkte: [
            for (var i = 0; i < 20; i++)
              (
                breite: 51.83 + i * 0.001,
                laenge: 10.64 + i * 0.0012,
                hoehe: 300.0 + (i < 10 ? i : 20 - i) * 18,
                zeit: DateTime.utc(2026, 8, 30, 7, i * 3),
              ),
          ],
        ),
      );
    });
    await tester.pumpWidget(
      app(AktivitaetSeite(sitzung: sitzung, aktivitaetId: 'runde')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(AktivitaetSeite)));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text(t.karteNurUeberServer), findsOneWidget);

    // Die Höhendaten reicht der Server nicht weiter: Die Landschaft sagt
    // es auch dann, wenn er Kartenkacheln liefert.
    sitzung.meldeKarten(true);
    await tester.pump();
    expect(find.text(t.karteNurUeberServer), findsNothing);
    expect(landschaftUeberServer(sitzung), isFalse);
    await tester.ensureVisible(find.text(t.gelaendeOeffnen));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.gelaendeOeffnen));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.gelaendeNurUeberServer), findsOneWidget);
  });
}

class _Sitzung extends Sitzung {
  void meldeKarten(bool ja) {
    kartenUeberServer = ja;
    notifyListeners();
  }
}

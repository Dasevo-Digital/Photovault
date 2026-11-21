// Zeitleiste: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/zeitleiste.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  testWidgets('MOB-021 abgemeldet: Ziehen an der Zeitleiste wirft keinen '
      'ungefangenen Fehler', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_zeitleiste_bef_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'z1',
        originalFileName: 'z1.jpg',
        relativePath: 'originals/z1.jpg',
        checksum: 'pruef-z1',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2025, 6, 2, 12),
        importedAt: DateTime(2026),
      ),
    );
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    // Der Server kennt das Gerät nicht mehr.
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient(
        (_) async => http.Response('{"fehler":"nicht angemeldet"}', 401),
      ),
    );
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade
      ..abgleich = Abgleich(db, verbindung);
    await tester.runAsync(sitzung.abgleich!.richteEin);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: Zeitleiste(sitzung: sitzung)),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    // Das, was „nach unten ziehen“ auslöst.
    final ziehen = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh;
    Object? fehler;
    await tester.runAsync(() async {
      try {
        await ziehen();
      } catch (f) {
        fehler = f;
      }
    });
    expect(fehler, isNull, reason: '$fehler');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

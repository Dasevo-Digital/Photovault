@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/video_trim_screen.dart';

import 'schnitt_probevideo.dart';

/// Die Vorschau beim Zuschneiden am echten Abspieler: Die Logik prüft
/// test/schnittsteuerung_test.dart, ob libmpv wirklich springt und am Ende
/// des Bereichs hält, nur dieser Test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('spielt genau den gewählten Bereich und hält an dessen Ende', (
    tester,
  ) async {
    MediaKit.ensureInitialized();
    final wurzel = await Directory.systemTemp.createTemp('pv_schnitt_');
    addTearDown(() => wurzel.delete(recursive: true));
    final paths = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'l')),
    );
    final video = paths.absolute('originals/v.mp4');
    await video.parent.create(recursive: true);
    await video.writeAsBytes(base64.decode(schnittProbevideo));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'v',
            originalFileName: 'v.mp4',
            relativePath: 'originals/v.mp4',
            checksum: 'p',
            type: 'VIDEO',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ),
        );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: VideoTrimScreen(
          asset: (await db.assetById('v'))!,
          db: db,
          paths: paths,
        ),
      ),
    );

    Future<bool> warteAuf(Finder f, Duration frist) async {
      final ende = DateTime.now().add(frist);
      while (DateTime.now().isBefore(ende)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (f.evaluate().isNotEmpty) return true;
      }
      return false;
    }

    expect(
      await warteAuf(find.byType(RangeSlider), const Duration(seconds: 15)),
      isTrue,
      reason: 'das Video öffnet sich',
    );
    expect(find.textContaining('Länge 00:12'), findsOneWidget);

    // Bereich 7 bis 9 s: Ohne funktionierenden Sprung liefe die Wiedergabe von
    // vorn und bräuchte neun Sekunden bis zum Ende des Bereichs.
    final griff = tester.widget<RangeSlider>(find.byType(RangeSlider));
    griff.onChanged!(const RangeValues(7, 12));
    await tester.pump();
    griff.onChanged!(const RangeValues(7, 9));
    await tester.pump();
    expect(find.textContaining('Länge 00:02'), findsOneWidget);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final beginn = DateTime.now();
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(
      await warteAuf(find.byIcon(Icons.pause), const Duration(seconds: 3)),
      isTrue,
      reason: 'die Vorschau läuft',
    );
    expect(
      await warteAuf(find.byIcon(Icons.play_arrow), const Duration(seconds: 6)),
      isTrue,
      reason: 'sie hält am Ende des Bereichs',
    );
    final dauer = DateTime.now().difference(beginn);
    // ignore: avoid_print
    print('Vorschau lief ${dauer.inMilliseconds} ms');
    expect(dauer.inMilliseconds, greaterThan(1500));
    expect(dauer.inMilliseconds, lessThan(4000));

    // Der nächste Druck beginnt wieder vorn, also noch einmal zwei Sekunden.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final zweiter = DateTime.now();
    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(
      await warteAuf(find.byIcon(Icons.pause), const Duration(seconds: 3)),
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.pause));
    expect(
      await warteAuf(find.byIcon(Icons.play_arrow), const Duration(seconds: 3)),
      isTrue,
      reason: 'von Hand anhalten geht auch',
    );
    expect(
      DateTime.now().difference(zweiter).inMilliseconds,
      lessThan(1500),
      reason: 'angehalten, nicht bis zum Ende gelaufen',
    );
    await tester.pumpWidget(const SizedBox());
  });
}

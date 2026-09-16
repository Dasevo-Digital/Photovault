@TestOn('linux || windows')
library;

// ignore_for_file: avoid_print
// **Die Schwebe-Vorschau, mit einem echten Abspieler.**
//
// Der Unittest (test/schwebevorschau_test.dart) stellt die Vorschau nach
// und prüft das Verhalten der Kachel: wann sie startet, wann sie
// aufhört. Was er nicht prüfen kann, ist der Teil dazwischen – dass aus
// „die Maus steht" wirklich ein laufendes Video wird. Dazu gehört ein
// echtes libmpv, und das entscheidet sich erst im laufenden Prozess.
//
// Hier steht die eine Frage, die dabei offen war: Die Bildfläche kommt
// erst in den Baum, NACHDEM `open()` durchgelaufen ist – vorher weiss
// niemand, ob die Datei überhaupt taugt. Der Videotest nebenan hält
// ausdrücklich fest, dass `open()` ohne Bildfläche im Baum auf ein
// erstes Bild warten kann, das nie kommt. Ob das auch hier zutrifft,
// beantwortet nur ein Lauf.
//
// **Nicht unter macOS**, aus demselben Grund wie nebenan: Die
// Testfassung läuft dort im Sandkasten und sieht die Vorlage im
// Projektordner nicht.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/schwebevorschau.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/schwebevorschau.dart';
import 'package:photo_vault/widgets/video_playback.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  /// Dieselbe Vorlage wie im Videotest: 320x240, drei Sekunden, kein Ton.
  final probe =
      File(p.join('test', 'fixtures', 'werkzeuge', 'probe.mp4')).absolute;

  testWidgets('aus „die Maus steht" wird ein laufendes Video', (tester) async {
    expect(probe.existsSync(), isTrue, reason: 'Vorlage fehlt: ${probe.path}');

    final wurzel = Directory.systemTemp.createTempSync('pv_schwebe_echt_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    // ignore: invalid_use_of_visible_for_testing_member
    final paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
    final ziel = paths.absolute('o/probe.mp4');
    await ziel.parent.create(recursive: true);
    await probe.copy(ziel.path);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final video = AssetsCompanion.insert(
      id: 'v1',
      originalFileName: 'probe.mp4',
      relativePath: 'o/probe.mp4',
      checksum: 'c1',
      type: 'VIDEO',
      fileCreatedAt: DateTime(2026, 3, 12),
      importedAt: DateTime(2026, 3, 12),
      durationSeconds: const Value(3),
    );
    await db.into(db.assets).insert(video);
    final asset = (await db.assetById('v1'))!;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Scaffold(
        body: SchwebevorschauBereich(
          db: db,
          paths: paths,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: AssetThumbnailTile(
                  asset: Rasterzeile.aus(asset), paths: paths, onTap: () {}),
            ),
          ),
        ),
      ),
    ));

    final geste = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await geste.addPointer(location: Offset.zero);
    addTearDown(geste.removePointer);
    await tester.pump();
    await geste.moveTo(tester.getCenter(find.byType(AssetThumbnailTile)));
    await tester.pump();

    // Erst die Wartezeit abwarten, dann echte Zeit vergehen lassen:
    // Öffnen und Abspielen kommen aus libmpv, nicht aus Flutters Uhr.
    await tester.pump(schwebeVerzoegerung);
    // Wie lange es vom Ablauf der Wartezeit bis zum Bild dauert. Die Zahl
    // gehört zum Gefühl der Sache: Kommt das Bild erst nach einer
    // Sekunde, ist die Maus meistens schon weiter.
    final uhr = Stopwatch()..start();
    for (var i = 0; i < 40 && find.byType(VideoSurface).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    uhr.stop();
    print('vom Ablauf der Wartezeit bis zum Bild: ${uhr.elapsedMilliseconds} ms');

    expect(find.byType(VideoSurface), findsOneWidget,
        reason: 'die Maus stand, aber es kam kein Bild – genau der Zustand, '
            'in dem open() auf ein erstes Bild wartet, das nie kommt');
    print('Bildfläche steht');

    // Und es läuft wirklich, statt bloss dazustehen.
    final regler = tester
        .widget<VideoSurface>(find.byType(VideoSurface))
        .controller;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)));
    print('Position: ${regler.position.inMilliseconds} ms, '
        'Dauer: ${regler.duration.inMilliseconds} ms');
    expect(regler.isPlaying, isTrue);
    expect(regler.position.inMilliseconds, greaterThan(100),
        reason: 'das Bild stand, aber es lief nichts');

    // Der Zeiger zieht weiter: Das Bild verschwindet, der Abspieler wird
    // abgeräumt. Ohne das bliebe für jede überstrichene Kachel ein
    // mpv-Prozess offen.
    await geste.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(find.byType(VideoSurface), findsNothing);
  });
}

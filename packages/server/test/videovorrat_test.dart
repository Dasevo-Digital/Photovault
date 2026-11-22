import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/src/videofassung.dart';
import 'package:test/test.dart';

/// Die leichte Fassung schwerer Videos entsteht schon nach dem Import
/// (#394) – nach den angefragten, nie vor ihnen.
void main() {
  late Directory ordner;
  late File protokoll;
  late File ffmpeg;
  late File original;
  late Directory speicher;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_vorrat_');
    protokoll = File('${ordner.path}/aufrufe.txt');
    // Ein ffmpeg, das nur festhält, was es schreibt, und es anlegt.
    ffmpeg = File('${ordner.path}/ffmpeg')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'for a; do letztes="\$a"; done\n'
        'sleep 0.2\n'
        'echo "\$(basename "\$letztes" .mp4.teil)" >> "${protokoll.path}"\n'
        'printf x > "\$letztes"\n',
      );
    await Process.run('chmod', ['+x', ffmpeg.path]);
    original = File('${ordner.path}/clip.mov')..writeAsBytesSync([1, 2, 3]);
    await original.setLastModified(DateTime(2026));
    speicher = Directory('${ordner.path}/abspielbar');
  });
  tearDown(() => ordner.delete(recursive: true));

  Videofassungen fassungen({int grenze = 1 << 30}) => Videofassungen(
    ffmpeg: ffmpeg.path,
    ffprobe: '${ordner.path}/kein-ffprobe',
    grenze: grenze,
  );

  test('vorgemerkt entsteht die Fassung ohne Abruf', () async {
    final f = fassungen();
    f.vormerken(speicher, 'v1', original);
    await f.vorratAbgearbeitet;
    expect(Videofassungen.ziel(speicher, 'v1').existsSync(), isTrue);
    expect(await f.bereit(speicher, 'v1', original), isNotNull);
  }, skip: Platform.isWindows ? 'ohne sh' : false);

  test('eine angefragte Fassung geht vor', () async {
    final f = fassungen();
    final angefragt = f.erzeuge(speicher, 'angefragt', original);
    f.vormerken(speicher, 'vorrat', original);
    await angefragt;
    await f.vorratAbgearbeitet;
    expect(protokoll.readAsLinesSync(), [
      'angefragt.s${Videofassungen.stand}',
      'vorrat.s${Videofassungen.stand}',
    ]);
  }, skip: Platform.isWindows ? 'ohne sh' : false);

  test(
    'der Vorrat belegt höchstens die Hälfte des Zwischenspeichers',
    () async {
      final f = fassungen(grenze: 100);
      speicher.createSync(recursive: true);
      File('${speicher.path}/alt.s2.mp4').writeAsBytesSync(List.filled(60, 0));
      f.vormerken(speicher, 'v2', original);
      await f.vorratAbgearbeitet;
      expect(Videofassungen.ziel(speicher, 'v2').existsSync(), isFalse);
      expect(protokoll.existsSync(), isFalse);
    },
    skip: Platform.isWindows ? 'ohne sh' : false,
  );

  test(
    'Abrufe über Links stellen höchstens zwei Umwandlungen vor die Besitzer',
    () async {
      // Die Reihe gehört allen Konten. Ein Besucher, der jedes Video eines
      // grossen geteilten Albums abrief, stellte jedes davon vor die
      // Videos, die ein Besitzer gerade ansehen wollte.
      final f = fassungen();
      for (var i = 0; i < 5; i++) {
        expect(
          await f.bereit(speicher, 'gast$i', original, gast: true),
          isNull,
        );
      }
      await f.erzeuge(speicher, 'eigen', original);
      final s = Videofassungen.stand;
      expect(protokoll.readAsLinesSync(), [
        'gast0.s$s',
        'gast1.s$s',
        'eigen.s$s',
      ]);
      // Ist wieder ein Platz frei, kommt der nächste Abruf dran.
      expect(await f.bereit(speicher, 'gast2', original, gast: true), isNull);
      await f.erzeuge(speicher, 'gast2', original);
      expect(
        await f.bereit(speicher, 'gast2', original, gast: true),
        isNotNull,
      );
    },
    skip: Platform.isWindows ? 'ohne sh' : false,
  );

  group('was einen Vorrat lohnt', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());
    final jetzt = DateTime(2026, 11, 15);

    Future<AssetData> aufnahme(
      String id, {
      String typ = 'VIDEO',
      int bytes = 154338552,
      double? sekunden = 22.7,
      DateTime? am,
      bool gesperrt = false,
    }) async {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.mov',
          relativePath: 'originals/$id.mov',
          checksum: 'pruef-$id',
          type: typ,
          fileCreatedAt: am ?? DateTime(2026, 11, 14),
          importedAt: DateTime(2026, 11, 14),
          fileSizeBytes: Value(bytes),
          durationSeconds: Value(sekunden),
          isLocked: Value(gesperrt),
        ),
      );
      return (await db.assetById(id))!;
    }

    test('frisch und schwer: ja', () async {
      expect(
        Videofassungen.lohntVorrat(await aufnahme('iphone'), jetzt: jetzt),
        isTrue,
      );
    });

    test('leicht, alt, gesperrt, ohne Dauer oder ein Bild: nein', () async {
      for (final a in [
        await aufnahme('leicht', bytes: 6000000, sekunden: 8),
        await aufnahme('alt', am: DateTime(2020)),
        await aufnahme('gesperrt', gesperrt: true),
        await aufnahme('ohne_dauer', sekunden: null),
        await aufnahme('bild', typ: 'IMAGE'),
      ]) {
        expect(
          Videofassungen.lohntVorrat(a, jetzt: jetzt),
          isFalse,
          reason: a.id,
        );
      }
    });
  });
}

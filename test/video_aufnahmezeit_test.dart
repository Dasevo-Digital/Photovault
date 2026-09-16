import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// **Videos bekommen ihren Aufnahmezeitpunkt.**
///
/// Der Fund an der echten Bibliothek: 440 Videos, davon **309 mit einem
/// Zeitpunkt in der Datei** – und **kein einziges** mit dem richtigen in
/// der Datenbank. 196 lagen um mehr als einen Tag daneben, das älteste um
/// zwölf Jahre. Ursache war nicht ein falscher Leser, sondern gar keiner:
/// `package:exif` liest MOV und MP4 nicht, und der Import fiel auf
/// `lastModified()` zurück – also auf den Zeitpunkt des letzten Kopierens.
///
/// Was dieser Prüfstand sichert, ist die **Kette**: Der Leser (der hat
/// seinen eigenen, siehe `video_metadaten_test.dart`) muss auch
/// tatsächlich gefragt werden, sein Ergebnis muss in der Zeile landen, und
/// die Datei muss im Ordner des Aufnahmemonats liegen und nicht in dem des
/// Imports.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService imp;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_videozeit_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    imp = ImportService(db, pfade);
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  List<int> u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  Uint8List kasten(String art, List<int> inhalt) {
    final b = BytesBuilder()
      ..add(u32(8 + inhalt.length))
      ..add(art.codeUnits)
      ..add(inhalt);
    return b.toBytes();
  }

  List<int> appleListe(Map<String, String> paare) {
    final namen = paare.keys.toList();
    return [
      ...kasten('meta', [
        ...kasten('keys', [
          0,
          0,
          0,
          0,
          ...u32(namen.length),
          for (final n in namen) ...[
            ...u32(8 + n.codeUnits.length),
            ...'mdta'.codeUnits,
            ...n.codeUnits,
          ],
        ]),
        ...kasten('ilst', [
          for (var i = 0; i < namen.length; i++)
            ...() {
              final data = kasten('data', [
                ...u32(1),
                ...u32(0),
                ...paare[namen[i]]!.codeUnits,
              ]);
              return [...u32(8 + data.length), ...u32(i + 1), ...data];
            }(),
        ]),
      ]),
    ];
  }

  /// Ein Video, dessen `moov` – wie im Regelfall – hinter den Rohdaten
  /// steht.
  Uint8List videobytes({
    int? mvhdSekunden,
    Map<String, String> apple = const {},
  }) {
    final sek = mvhdSekunden ?? 0;
    return (BytesBuilder()
          ..add(kasten('ftyp', 'qt  '.codeUnits))
          ..add(kasten('mdat', List.filled(2000, 7)))
          ..add(kasten('moov', [
            ...kasten('mvhd', [
              0,
              0,
              0,
              0,
              ...u32(sek),
              ...u32(sek),
              ...u32(1000),
              ...u32(5000),
            ]),
            if (apple.isNotEmpty) ...appleListe(apple),
          ])))
        .toBytes();
  }

  int seit1904(DateTime utc) => utc.difference(DateTime.utc(1904)).inSeconds;

  Future<AssetData> importiere(String name, Uint8List inhalt,
      {DateTime? dateizeit}) async {
    final rein = Directory(p.join(temp.path, 'rein'))
      ..createSync(recursive: true);
    final datei = File(p.join(rein.path, name))..writeAsBytesSync(inhalt);
    if (dateizeit != null) datei.setLastModifiedSync(dateizeit);
    final erg = await imp.importFile(datei.path);
    expect(erg.outcome, ImportOutcome.imported, reason: 'Import misslang');
    return (await db.assetById(erg.assetId!))!;
  }

  test('Apples Aufnahmezeit schlägt den Zeitstempel der Datei', () async {
    final asset = await importiere(
      'a.mov',
      videobytes(
        mvhdSekunden: seit1904(DateTime.utc(2025, 9, 20, 9, 50, 21)),
        apple: {
          'com.apple.quicktime.creationdate': '2025-09-20T11:50:21+0200',
        },
      ),
      dateizeit: DateTime(2026, 8, 30, 7),
    );
    expect(asset.fileCreatedAt.toUtc(), DateTime.utc(2025, 9, 20, 9, 50, 21));
  });

  test('ohne Apple-Eintrag gilt mvhd', () async {
    final asset = await importiere(
      'b.mp4',
      videobytes(mvhdSekunden: seit1904(DateTime.utc(2013, 6, 2, 16, 40, 17))),
      dateizeit: DateTime(2026, 8, 30, 7),
    );
    expect(asset.fileCreatedAt, DateTime(2013, 6, 2, 16, 40, 17));
  });

  test('das Video landet im Ordner seines Aufnahmemonats', () async {
    // Der eigentliche Schaden des alten Verhaltens: Nicht nur die Zeile
    // war falsch, das Video lag auch im Ordner des Importmonats.
    final asset = await importiere(
      'c.mp4',
      videobytes(mvhdSekunden: seit1904(DateTime.utc(2013, 6, 2, 16, 40, 17))),
      dateizeit: DateTime(2026, 8, 30, 7),
    );
    expect(asset.relativePath, contains(p.join('2013', '06')));
    expect(File(pfade.absolute(asset.relativePath).path).existsSync(), isTrue);
  });

  test('ohne jede Zeitangabe bleibt der Zeitstempel der Datei', () async {
    // Der Rückfall ist nicht falsch, er ist nur der letzte Ausweg.
    final wann = DateTime(2024, 3, 4, 5, 6, 7);
    final asset = await importiere('d.mp4', videobytes(), dateizeit: wann);
    expect(asset.fileCreatedAt, wann);
  });

  test('Hersteller und Gerät kommen mit', () async {
    final asset = await importiere(
      'e.mov',
      videobytes(mvhdSekunden: seit1904(DateTime.utc(2025, 1, 2, 3)), apple: {
        'com.apple.quicktime.make': 'Apple',
        'com.apple.quicktime.model': 'iPhone 13 Pro',
      }),
    );
    expect(asset.cameraMake, 'Apple');
    expect(asset.cameraModel, 'iPhone 13 Pro');
  });

  group('der Nachtrag holt nach, was schon in der Bibliothek liegt', () {
    test('Videos stehen jetzt auf der Kandidatenliste', () async {
      // Vor der Änderung fragte die Abfrage nach `type = 'IMAGE'` und einer
      // RAW-Endung – ein Video kam dort nie vor, und deshalb blieben die
      // 440 für immer falsch datiert, egal wie oft jemand die Aufgabe
      // startete.
      await importiere('f.mp4', videobytes(), dateizeit: DateTime(2026, 8));
      final kandidaten = await db.assetsFuerDatumskorrektur();
      expect(kandidaten.map((a) => a.originalFileName), contains('f.mp4'));
      expect(await db.countDatumskorrektur(), kandidaten.length);
    });

    test('gewöhnliche JPEG bleiben aussen vor', () async {
      // Dort kam das Datum immer aus den EXIF-Daten oder es gab keines –
      // erneutes Lesen brächte nichts und kostete einen Durchlauf über die
      // ganze Bibliothek.
      final rein = Directory(p.join(temp.path, 'rein'))
        ..createSync(recursive: true);
      final jpg = File(p.join(rein.path, 'g.jpg'))
        ..writeAsBytesSync(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
      await imp.importFile(jpg.path);
      final namen =
          (await db.assetsFuerDatumskorrektur()).map((a) => a.originalFileName);
      expect(namen, isNot(contains('g.jpg')));
    });

    test('der Papierkorb bleibt unangetastet', () async {
      final asset = await importiere('h.mp4', videobytes());
      await db.moveToTrash([asset.id]);
      final namen =
          (await db.assetsFuerDatumskorrektur()).map((a) => a.originalFileName);
      expect(namen, isNot(contains('h.mp4')));
    });
  });

  test('die Kameradaten-Aufgabe sieht Videos an', () async {
    // Sie fragte nach `type = 'IMAGE'`; 275 Videos mit Hersteller und
    // Gerät in der Datei blieben damit unerreichbar, während der Lauf 842
    // Fotos las, von denen keines eine Kameraangabe hat.
    final asset = await importiere('i.mp4', videobytes());
    expect(asset.cameraMake, isNull);
    final kandidaten = await db.assetsForCameraMetadataBackfill();
    expect(kandidaten.map((a) => a.id), contains(asset.id));
    expect(await db.countCameraMetadataBackfill(), kandidaten.length);
  });
}

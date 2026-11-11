import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/nachbearbeitung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/beilagenangaben.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Dieselbe Aufnahme in mehreren Dateiformaten als ein Stapel (#361).
void main() {
  late Directory temp;
  late AppDatabase db;
  late Nachbearbeitung nb;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_formatstapel_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'lib')),
    );
    nb = Nachbearbeitung(
      db: db,
      paths: paths,
      importe: () => ImportService(db, paths),
      auswertungen: Auswertungen(db: db, paths: paths, modelle: Modelle()),
    );
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  final zeit = DateTime(2024, 6, 1, 12, 30, 15);

  Future<void> lege(
    String id,
    String name, {
    DateTime? am,
    bool geschaetzt = false,
    String? kamera,
    int breite = 4032,
    int hoehe = 3024,
    bool favorit = false,
    int sterne = 0,
    String? beschreibung,
    String? entwickelt,
    bool papierkorb = false,
    bool gesperrt = false,
    String typ = 'IMAGE',
    String? verknuepft,
  }) => db.insertAsset(
    AssetsCompanion.insert(
      id: id,
      originalFileName: name,
      relativePath: 'originals/$id',
      checksum: id,
      type: typ,
      fileCreatedAt: am ?? zeit,
      importedAt: zeit,
      dateiformat: Value(p.extension(name).substring(1).toLowerCase()),
      datumGeschaetzt: Value(geschaetzt),
      cameraModel: Value(kamera),
      widthPx: Value(breite),
      heightPx: Value(hoehe),
      isFavorite: Value(favorit),
      rating: Value(sterne),
      description: Value(beschreibung),
      developedRelativePath: Value(entwickelt),
      isTrashed: Value(papierkorb),
      isLocked: Value(gesperrt),
      linkedAssetId: Value(verknuepft),
    ),
  );

  Future<Set<String>> sichtbar() async => {
    for (final z
        in await db
            .customSelect('SELECT id FROM assets WHERE $rasterSichtbar')
            .get())
      z.read<String>('id'),
  };

  Future<AssetData> zeile(String id) async => (await db.assetById(id))!;

  group('was zusammengehört', () {
    test('HEIC und JPG: ein Eintrag, das HEIC liegt oben', () async {
      await lege('j', 'IMG_0001.JPG');
      await lege(
        'h',
        'IMG_0001.HEIC',
        am: zeit.add(const Duration(seconds: 1)),
      );
      expect(await db.stapleFormate(), 1);
      expect(await sichtbar(), {'h'});
      final oben = await zeile('h');
      expect(istVariantenstapel(oben.stackId), isTrue);
      expect(istFormatstapel(oben.stackId), isTrue);
      expect(oben.stackSize, 2);
      expect((await zeile('j')).stackId, oben.stackId);
    });

    test(
      'Gross- und Kleinschreibung und jpeg/jpg spielen keine Rolle',
      () async {
        await lege('a', 'img_0002.heif');
        await lege('b', 'IMG_0002.jpeg');
        expect(await db.stapleFormate(), 1);
      },
    );

    test('RAW und JPG: das fertige Bild liegt oben', () async {
      await lege('r', 'DSC_1.NEF', breite: 6048, hoehe: 4024);
      await lege('j', 'DSC_1.JPG', breite: 6000, hoehe: 4000);
      await db.stapleFormate();
      expect(await sichtbar(), {'j'});
    });

    test('ein entwickeltes RAW liegt oben', () async {
      await lege('r', 'DSC_2.CR3', entwickelt: 'developed/r.jpg');
      await lege('j', 'DSC_2.JPG');
      await db.stapleFormate();
      expect(await sichtbar(), {'r'});
    });

    test('benannte Gesichter bleiben sichtbar', () async {
      await lege('h', 'IMG_3.HEIC');
      await lege('j', 'IMG_3.JPG');
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'f',
              assetId: 'j',
              personId: const Value('p'),
              boxX: 0,
              boxY: 0,
              boxW: 0.1,
              boxH: 0.1,
            ),
          );
      await db.stapleFormate();
      expect(await sichtbar(), {'j'});
    });

    test('drei Formate sind ein Stapel', () async {
      await lege('h', 'IMG_4.HEIC');
      await lege('j', 'IMG_4.JPG');
      await lege('d', 'IMG_4.DNG');
      expect(await db.stapleFormate(), 1);
      expect((await zeile('h')).stackSize, 3);
    });
  });

  group('was getrennt bleibt', () {
    test('gleicher Name, aber Jahre auseinander', () async {
      await lege('a', 'IMG_1712.HEIC');
      await lege('b', 'IMG_1712.JPG', am: DateTime(2013, 6, 1));
      expect(await db.stapleFormate(), 0);
    });

    test('drei Sekunden liegen zu weit auseinander', () async {
      await lege('a', 'IMG_5.HEIC');
      await lege('b', 'IMG_5.JPG', am: zeit.add(const Duration(seconds: 3)));
      expect(await db.stapleFormate(), 0);
    });

    test('dasselbe Format ist kein Formatpaar', () async {
      await lege('a', 'IMG_6.JPG');
      await lege('b', 'IMG_6.jpeg');
      expect(await db.stapleFormate(), 0);
    });

    test('ein geschätztes Datum beweist nichts', () async {
      await lege('a', 'IMG_7.HEIC');
      await lege('b', 'IMG_7.JPG', geschaetzt: true);
      expect(await db.stapleFormate(), 0);
    });

    test('zwei verschiedene Kameras', () async {
      await lege('a', 'DSC_8.NEF', kamera: 'Z 6');
      await lege('b', 'DSC_8.JPG', kamera: 'X100V');
      expect(await db.stapleFormate(), 0);
    });

    test('anderer Name, Papierkorb, Gesperrtes, Video', () async {
      await lege('a', 'IMG_9.HEIC');
      await lege('b', 'IMG_90.JPG');
      await lege('c', 'IMG_9.JPG', papierkorb: true);
      await lege('d', 'IMG_9.PNG', gesperrt: true);
      await lege('e', 'IMG_9.MOV', typ: 'VIDEO');
      expect(await db.stapleFormate(), 0);
    });

    test('neben einer Serie entsteht kein Formatstapel', () async {
      await lege('a', 'IMG_10.HEIC');
      await lege('b', 'IMG_10.JPG', favorit: true);
      await lege('c', 'IMG_11.HEIC');
      await db.fuehreAus(const SerieBilden('s', ['a', 'c'], 'a'));
      expect(await db.stapleFormate(), 0);
      expect((await zeile('a')).stackId, 's');
      expect((await zeile('b')).stackId, isNull);
    });

    test('Serienbilder mit verschiedenen Nummern', () async {
      // Dieselbe Sekunde, dieselbe Kamera, zwei Formate – aber IMG_1390
      // und IMG_1392 sind zwei Bilder einer Serie, kein Formatpaar.
      await lege('j', 'IMG_1390.jpg', kamera: 'Canon EOS R10');
      await lege('r', 'IMG_1392-510ad155.CR3', kamera: 'Canon EOS R10');
      expect(await db.stapleFormate(), 0);
    });
  });

  group('Zusätze am Namen (#365)', () {
    test('der Stamm', () {
      expect(formatstamm('IMG_0531-1bd0b0c6.jpg'), 'img_0531');
      expect(formatstamm('IMG_0531-04446957.CR3'), 'img_0531');
      expect(formatstamm('IMG_1144 (2).CR3'), 'img_1144');
      expect(formatstamm('IMG_1144 2.CR3'), 'img_1144');
      expect(formatstamm('IMG_1027+1.JPG'), 'img_1027');
      expect(formatstamm('IMG_0361+1-88c523ca.jpg'), 'img_0361');
      expect(formatstamm('IMG_0124-hdr-7a983870.jpg'), 'img_0124-hdr');
      // Was kein Zusatz ist, bleibt.
      expect(formatstamm('IMG_1026-Verbessert.dng'), 'img_1026-verbessert');
      expect(
        formatstamm('23-05-09 18-31-31 1702.MOV'),
        '23-05-09 18-31-31 1702',
      );
      expect(formatstamm('DSC_1.NEF'), 'dsc_1');
      expect(formatstamm('-1bd0b0c6.jpg'), '-1bd0b0c6');
    });

    test('RAW und JPEG mit Hexzusatz sind ein Stapel', () async {
      await lege('r', 'IMG_0531.CR3', kamera: 'Canon EOS R10');
      await lege('j', 'IMG_0531-1bd0b0c6.jpg', kamera: 'Canon EOS R10');
      expect(await db.stapleFormate(), 1);
      expect(await sichtbar(), {'j'});
    });

    test('eine Nummer in Klammern trennt nicht', () async {
      await lege('j', 'IMG_1144.jpg');
      await lege('r', 'IMG_1144 (2).CR3');
      expect(await db.stapleFormate(), 1);
      expect(await sichtbar(), {'j'});
    });

    test('beim Import findet die neue Datei ihr Gegenstück', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await lege('r', 'IMG_0532.CR3');
      await nb.neueAufnahme('r');
      await lege('j', 'IMG_0532-d8566b0d.jpg');
      await nb.neueAufnahme('j');
      expect(await sichtbar(), {'j'});
      // Und umgekehrt: erst die Datei mit Zusatz.
      await lege('j2', 'IMG_0533-922be27a.jpg');
      await nb.neueAufnahme('j2');
      await lege('r2', 'IMG_0533.CR3');
      await nb.neueAufnahme('r2');
      expect(await sichtbar(), {'j', 'j2'});
    });

    test('verschiedene Nummern sind zwei Aufnahmen (#367)', () async {
      // Eine RAW+JPEG-Serie, umbenannt: alles in derselben Sekunde.
      for (final n in [1, 2]) {
        await lege('r$n', 'Hochzeit $n.CR3', kamera: 'Canon EOS R10');
        await lege('j$n', 'Hochzeit $n.JPG', kamera: 'Canon EOS R10');
      }
      await lege('x', 'Foto 1.jpg', kamera: 'X');
      await lege('y', 'Foto 2.heic', kamera: 'X');
      expect(await db.stapleFormate(), 2);
      expect(await sichtbar(), {'j1', 'j2', 'x', 'y'});
      expect((await zeile('r1')).stackId, (await zeile('j1')).stackId);
      expect((await zeile('r2')).stackId, (await zeile('j2')).stackId);
    });

    test('dieselbe Nummer passt, auch anders geschrieben', () async {
      await lege('r', 'IMG_1144 (2).CR3');
      await lege('j', 'IMG_1144 2.jpg');
      await lege('h', 'IMG_0361+1-88c523ca.jpg');
      await lege('d', 'IMG_0361+1.DNG');
      expect(await db.stapleFormate(), 2);
      expect(await sichtbar(), {'j', 'h'});
    });

    test('der Import greift nicht auf einen längeren Namen über', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await lege('a', 'IMG_05310.CR3');
      await lege('b', 'IMG_0531.jpg');
      await nb.neueAufnahme('b');
      expect(await sichtbar(), {'a', 'b'});
    });
  });

  group('ein Format liegt schon in einem Stapel (#365)', () {
    Future<void> serie() async {
      await lege('a', 'IMG_1096.CR3', kamera: 'Canon EOS R10');
      await lege(
        'c',
        'IMG_1097.CR3',
        kamera: 'Canon EOS R10',
        am: zeit.add(const Duration(seconds: 1)),
      );
      await db.fuehreAus(const SerieBilden('s', ['a', 'c'], 'a'));
    }

    test('das freie Format kommt verdeckt in die Serie', () async {
      await serie();
      await lege('b', 'IMG_1096.jpg', kamera: 'Canon EOS R10');
      expect(await db.stapleFormate(), 1);
      expect(await sichtbar(), {'a'});
      expect((await zeile('b')).stackId, 's');
      expect((await zeile('a')).isStackCover, isTrue);
      expect((await zeile('a')).stackSize, 3);
      // Ein zweiter Lauf ändert nichts.
      expect(await db.stapleFormate(), 0);
    });

    test('auch in Varianten', () async {
      await lege('d', 'IMG_7325.DNG', kamera: 'iPhone 17 Pro');
      await lege('j', 'IMG_7325.jpeg', kamera: 'iPhone 17 Pro');
      await lege('e', 'IMG_7325_bearbeitet.jpg', kamera: 'iPhone 17 Pro');
      await db.fuehreAus(const VariantenBilden('v', ['j', 'e'], 'e'));
      expect(await db.stapleFormate(), 1);
      expect(await sichtbar(), {'e'});
      expect((await zeile('d')).stackId, 'variante:v');
    });

    test('wer Angaben trägt, bleibt daneben sichtbar', () async {
      await serie();
      await lege('b', 'IMG_1096.jpg', kamera: 'Canon EOS R10', sterne: 3);
      expect(await db.stapleFormate(), 0);
      expect((await zeile('b')).stackId, isNull);
      expect((await zeile('b')).rating, 3);
    });

    test('ein Live Photo bleibt daneben sichtbar (#368)', () async {
      await serie();
      await lege('v', 'IMG_1096.MOV', typ: 'VIDEO', verknuepft: 'b');
      await lege(
        'b',
        'IMG_1096.HEIC',
        kamera: 'Canon EOS R10',
        verknuepft: 'v',
      );
      expect(await db.stapleFormate(), 0);
      expect((await zeile('b')).stackId, isNull);
      expect(await sichtbar(), {'a', 'b'});
    });

    test('beim Import kommt das JPEG zu seinem RAW in der Serie', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await serie();
      await lege('b', 'IMG_1096-1bd0b0c6.jpg', kamera: 'Canon EOS R10');
      await nb.neueAufnahme('b');
      expect((await zeile('b')).stackId, 's');
      expect(await sichtbar(), {'a'});
      expect((await zeile('a')).stackSize, 3);
    });

    test('benannte Gesichter halten nicht ab', () async {
      await serie();
      await lege('b', 'IMG_1096.jpg', kamera: 'Canon EOS R10');
      await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              id: 'f',
              assetId: 'b',
              personId: const Value('p'),
              boxX: 0,
              boxY: 0,
              boxW: 0.1,
              boxH: 0.1,
            ),
          );
      expect(await db.stapleFormate(), 1);
      expect((await zeile('b')).stackId, 's');
      // Die Seite der Person zeigt es weiter.
      expect((await db.watchAssetsForPerson('p').first).map((a) => a.id), [
        'b',
      ]);
    });

    test('Ausschalten holt es wieder heraus, die Serie bleibt', () async {
      await serie();
      await lege('b', 'IMG_1096.jpg', kamera: 'Canon EOS R10');
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await sichtbar(), {'a'});
      await db.fuehreAus(const FormateStapelnSetzen(false));
      expect(await sichtbar(), {'a', 'b'});
      final a = await zeile('a');
      expect(a.stackId, 's');
      expect(a.stackSize, 2);
      expect((await zeile('c')).stackId, 's');
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await sichtbar(), {'a'});
    });

    test('nach dem Auflösen der Serie bleibt die Marke folgenlos', () async {
      await serie();
      await lege('b', 'IMG_1096.jpg', kamera: 'Canon EOS R10');
      await db.stapleFormate();
      await db.fuehreAus(const SerieAufloesen('s'));
      await db.fuehreAus(const VariantenBilden('w', ['b', 'c'], 'c'));
      await db.fuehreAus(const FormateStapelnSetzen(false));
      // b liegt jetzt von Hand in den Varianten w – das bleibt so.
      expect((await zeile('b')).stackId, 'variante:w');
    });
  });

  test('ein zweiter Lauf ändert nichts', () async {
    await lege('h', 'IMG_12.HEIC');
    await lege('j', 'IMG_12.JPG');
    await db.stapleFormate();
    final vorher = (await zeile('h')).stackId;
    expect(await db.stapleFormate(), 0);
    expect((await zeile('h')).stackId, vorher);
  });

  test('wer Angaben trägt, bleibt oben', () async {
    await lege('h', 'IMG_13.HEIC');
    await lege(
      'j',
      'IMG_13.JPG',
      favorit: true,
      sterne: 4,
      beschreibung: 'Unten',
    );
    await db
        .into(db.albums)
        .insert(AlbumsCompanion.insert(id: 'alb', name: 'A', createdAt: zeit));
    await db.addAssetsToAlbum('alb', ['j']);
    await db.stapleFormate();
    expect(await sichtbar(), {'j'});
  });

  Future<Set<String>> imAlbum(String album) async => {
    for (final z in await (db.select(
      db.albumAssets,
    )..where((t) => t.albumId.equals(album))).get())
      z.assetId,
  };

  Future<void> album(String id, List<String> mit) async {
    await db
        .into(db.albums)
        .insert(AlbumsCompanion.insert(id: id, name: id, createdAt: zeit));
    await db.addAssetsToAlbum(id, mit);
  }

  test('Angaben ziehen um, statt kopiert zu werden', () async {
    await lege('h', 'IMG_31.HEIC', beschreibung: 'Oben');
    await lege('j', 'IMG_31.JPG', sterne: 4, beschreibung: 'Unten');
    await lege('d', 'IMG_31.DNG', favorit: true);
    await album('alb', ['j']);
    // Alle drei tragen etwas; die Regeln entscheiden: HEIC vor JPG vor RAW.
    await db.stapleFormate();
    expect(await sichtbar(), {'h'});
    final oben = await zeile('h');
    expect(oben.isFavorite, isTrue);
    expect(oben.rating, 4);
    expect(oben.description, 'Oben');
    expect(await imAlbum('alb'), {'h'});
    final j = await zeile('j');
    expect(j.rating, 0);
    expect(j.description, 'Unten', reason: 'nicht übernommen, also nicht weg');
    expect((await zeile('d')).isFavorite, isFalse);
  });

  test(
    'aus und wieder an: dieselbe Hauptversion, nichts kommt zurück',
    () async {
      await lege('h', 'IMG_32.HEIC');
      await lege('j', 'IMG_32.JPG');
      await album('a1', ['j']);
      await album('a2', ['h']);
      await db.fuehreAus(const FormateStapelnSetzen(true));
      final stapel = (await zeile('h')).stackId!;
      await db.fuehreAus(VariantenHauptbildSetzen(stapel, 'j'));
      expect(await sichtbar(), {'j'});
      expect(await imAlbum('a2'), {'j'}, reason: 'zieht mit der Hauptversion');
      await db.nimmAusAlbum('a1', ['j']);
      await db.fuehreAus(const FormateStapelnSetzen(false));
      expect(await sichtbar(), {'h', 'j'});
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await sichtbar(), {'j'});
      expect(await imAlbum('a1'), isEmpty);
      expect(await imAlbum('a2'), {'j'});
    },
  );

  test('sichtbareFassung führt zum Titelbild jedes Stapels', () async {
    await lege('a', 'A.JPG');
    await lege('b', 'B.JPG');
    await lege('c', 'C.JPG');
    await db.fuehreAus(const SerieBilden('s', ['a', 'b'], 'a'));
    expect(await db.sichtbareFassung('b'), 'a');
    expect(await db.sichtbareFassung('a'), 'a');
    expect(await db.sichtbareFassung('c'), 'c');
  });

  test('verdeckte Fassungen werden nicht ausgewertet', () async {
    await lege('h', 'IMG_33.HEIC');
    await lege('j', 'IMG_33.JPG');
    final vorher = await db.countOcrBackfill();
    await db.stapleFormate();
    expect(await db.countOcrBackfill(), vorher - 1);
  });

  test('eine neue Fassung kommt dazu, die Hauptversion bleibt', () async {
    await lege('h', 'IMG_14.HEIC');
    await lege('j', 'IMG_14.JPG');
    await db.stapleFormate();
    await db.fuehreAus(
      VariantenHauptbildSetzen((await zeile('h')).stackId!, 'j'),
    );
    final kennung = (await zeile('h')).stackId;
    await lege('d', 'IMG_14.DNG');
    expect(await db.stapleFormate(), 1);
    expect(await sichtbar(), {'j'});
    expect((await zeile('j')).stackSize, 3);
    expect((await zeile('d')).stackId, kennung);
    expect((await zeile('h')).stackId, kennung);
  });

  group('der Schalter', () {
    test('an stapelt, aus zeigt wieder einzeln', () async {
      await lege('h', 'IMG_15.HEIC');
      await lege('j', 'IMG_15.JPG');
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await db.formateStapeln(), isTrue);
      expect(await sichtbar(), {'h'});
      await db.fuehreAus(const FormateStapelnSetzen(false));
      expect(await db.formateStapeln(), isFalse);
      expect(await sichtbar(), {'h', 'j'});
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await sichtbar(), {'h'});
    });

    test('aus lässt von Hand gebildete Varianten stehen', () async {
      await lege('a', 'A.JPG');
      await lege('b', 'B.JPG');
      await db.fuehreAus(const VariantenBilden('v', ['a', 'b'], 'a'));
      await db.fuehreAus(const FormateStapelnSetzen(false));
      expect((await zeile('b')).stackId, 'variante:v');
    });

    test('von Hand Aufgelöstes kommt nicht wieder', () async {
      await lege('h', 'IMG_16.HEIC');
      await lege('j', 'IMG_16.JPG');
      await db.stapleFormate();
      await db.fuehreAus(VariantenAufloesen((await zeile('h')).stackId!));
      expect(await sichtbar(), {'h', 'j'});
      expect(await db.stapleFormate(), 0);
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await sichtbar(), {'h', 'j'});
    });

    test('verbunden schaltet das Gerät nur um', () async {
      await lege('h', 'IMG_17.HEIC');
      await lege('j', 'IMG_17.JPG');
      db.umleitung = <T>(b) => b.anwenden(db);
      addTearDown(() => db.umleitung = null);
      await db.fuehreAus(const FormateStapelnSetzen(true));
      expect(await db.formateStapeln(), isTrue);
      expect(await sichtbar(), {'h', 'j'});
    });
  });

  group('beim Import', () {
    test('ohne Schalter bleibt alles einzeln', () async {
      await lege('h', 'IMG_18.HEIC');
      await lege('j', 'IMG_18.JPG');
      await nb.neueAufnahme('j');
      expect(await sichtbar(), {'h', 'j'});
    });

    test('mit Schalter stapelt die zweite Datei das Paar', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await lege('h', 'IMG_19.HEIC');
      await nb.neueAufnahme('h');
      expect(await sichtbar(), {'h'});
      await lege('j', 'IMG_19.JPG');
      await nb.neueAufnahme('j');
      expect(await sichtbar(), {'h'});
      expect((await zeile('h')).stackSize, 2);
    });

    test('die Beilage eines verdeckten RAWs landet auf der obersten', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await lege('j', 'DSC_20.JPG');
      await lege('r', 'DSC_20.NEF');
      await nb.neueAufnahme('r');
      expect(await sichtbar(), {'j'});
      await const Beilagenangaben(sterne: 3).wendeAn(db, 'r');
      expect((await zeile('j')).rating, 3);
    });

    test('die Beilage ergänzt die Hauptversion, ersetzt sie nicht', () async {
      await db.fuehreAus(const FormateStapelnSetzen(true));
      await lege('j', 'DSC_21.JPG', sterne: 4, beschreibung: 'Am See');
      await lege('r', 'DSC_21.NEF');
      await nb.neueAufnahme('r');
      await const Beilagenangaben(
        sterne: 2,
        beschreibung: 'aus darktable',
      ).wendeAn(db, 'r');
      final oben = await zeile('j');
      expect(oben.rating, 4);
      expect(oben.description, 'Am See');
    });
  });
}

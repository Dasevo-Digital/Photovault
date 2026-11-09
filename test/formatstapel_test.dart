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

    test('eine Serie bleibt, wie sie ist', () async {
      await lege('a', 'IMG_10.HEIC');
      await lege('b', 'IMG_10.JPG');
      await lege('c', 'IMG_11.HEIC');
      await db.fuehreAus(const SerieBilden('s', ['a', 'c'], 'a'));
      expect(await db.stapleFormate(), 0);
      expect((await zeile('a')).stackId, 's');
      expect((await zeile('b')).stackId, isNull);
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

  test('was nur die verdeckte Fassung trägt, rückt nach oben', () async {
    await lege('h', 'IMG_13.HEIC', beschreibung: 'Oben');
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
    expect(await sichtbar(), {'h'});
    final oben = await zeile('h');
    expect(oben.isFavorite, isTrue);
    expect(oben.rating, 4);
    expect(oben.description, 'Oben');
    final imAlbum = await (db.select(
      db.albumAssets,
    )..where((t) => t.albumId.equals('alb'))).get();
    expect({for (final z in imAlbum) z.assetId}, {'h', 'j'});
  });

  test('eine neue Fassung kommt dazu, die Hauptversion bleibt', () async {
    await lege('h', 'IMG_14.HEIC');
    await lege('j', 'IMG_14.JPG');
    await db.stapleFormate();
    await db.fuehreAus(
      VariantenHauptbildSetzen((await zeile('h')).stackId!, 'j'),
    );
    await lege('d', 'IMG_14.DNG');
    expect(await db.stapleFormate(), 1);
    expect(await sichtbar(), {'j'});
    expect((await zeile('j')).stackSize, 3);
    expect((await zeile('d')).stackId, (await zeile('h')).stackId);
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
  });
}

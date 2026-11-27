import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/collage.dart' show mitAufnahmezeit;
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/zusammenfuegen/ablage.dart';
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/zusammenfuegen_dienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/zusammenfuegen_dialog.dart';

import 'hilfen/synthetische_bilder.dart';

/// Das Ergebnis eines Zusammenfügens (#498) wird eine neue Aufnahme und
/// liegt vorn in einem Variantenstapel mit seinen Quellen – geprüft an
/// einer Bibliothek im Speicher.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_zusammenfuegen_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    importe = ImportService(db, pfade);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Uint8List jpeg(int farbe, DateTime zeit) {
    final b = img.Image(width: 64, height: 48);
    img.fill(b, color: img.ColorRgb8(farbe, 120, 200 - farbe));
    return mitAufnahmezeit(img.encodeJpg(b, quality: 90), zeit);
  }

  Future<AssetData> aufnahme(String name, DateTime zeit, int farbe) async {
    final quelle = File(p.join(temp.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(jpeg(farbe, zeit));
    final r = await importe.importFile(quelle.path);
    expect(r.outcome, ImportOutcome.imported);
    return (await db.assetById(r.assetId!))!;
  }

  Future<String?> einlesen(Uint8List bytes, String name) async {
    final datei = File(p.join(temp.path, 'ergebnis', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    final r = await importe.importFile(datei.path);
    return r.outcome == ImportOutcome.imported ? r.assetId : null;
  }

  test('das Ergebnis liegt vorn im Stapel, mit Zeit der mittleren Quelle, '
      'dem bekannten Ort und dem Album des bisherigen Fotos', () async {
    final a = await aufnahme('IMG_0001.JPG', DateTime(2024, 6, 1, 10), 10);
    final b = await aufnahme(
      'IMG_0002.JPG',
      DateTime(2024, 6, 1, 10, 0, 2),
      60,
    );
    final c = await aufnahme(
      'IMG_0003.JPG',
      DateTime(2024, 6, 1, 10, 0, 4),
      110,
    );
    // Nur die letzte Quelle kennt ihren Ort, und nur aus der Datenbank.
    await db.fuehreAus(OrtSetzen([c.id], 47.5, 8.7));
    await db.fuehreAus(AlbumAnlegen('album', 'Urlaub', DateTime(2024)));
    await db.fuehreAus(AlbumFuellen('album', [b.id]));
    final quellen = await db.assetsByIds([c.id, a.id, b.id]);

    final id = await legeZusammengefuegtesAb(
      db: db,
      quellen: quellen,
      jpeg: jpeg(200, DateTime(2030)),
      art: Fuegeart.hdr,
      einlesen: einlesen,
    );

    final ergebnis = (await db.assetById(id))!;
    expect(ergebnis.originalFileName, 'IMG_0002-HDR.jpg');
    expect(ergebnis.fileCreatedAt, b.fileCreatedAt);
    expect(ergebnis.latitude, closeTo(47.5, 1e-4));
    expect(ergebnis.longitude, closeTo(8.7, 1e-4));
    expect(istVariantenstapel(ergebnis.stackId), isTrue);
    expect(ergebnis.isStackCover, isTrue);
    expect(ergebnis.stackSize, 4);
    for (final q in await db.assetsByIds([a.id, b.id, c.id])) {
      expect(q.stackId, ergebnis.stackId, reason: q.originalFileName);
      expect(q.isStackCover, isFalse, reason: q.originalFileName);
    }
    // Das Album zieht mit dem sichtbaren Foto um (#363).
    expect(await db.imAlbum('album', [id]), contains(id));
  });

  test('Gegenprobe: liegt eine Quelle schon in Varianten, kommt der ganze '
      'Stapel mit und behält seine Kennung', () async {
    final a = await aufnahme('a.jpg', DateTime(2024, 6, 2, 9), 20);
    final x = await aufnahme('x.jpg', DateTime(2024, 6, 2, 9, 0, 1), 40);
    final b = await aufnahme('b.jpg', DateTime(2024, 6, 2, 9, 0, 3), 80);
    await db.fuehreAus(VariantenBilden('v1', [a.id, x.id], a.id));
    final quellen = await db.assetsByIds([a.id, b.id]);

    final id = await legeZusammengefuegtesAb(
      db: db,
      quellen: quellen,
      jpeg: jpeg(150, DateTime(2030)),
      art: Fuegeart.panorama,
      einlesen: einlesen,
    );

    final ergebnis = (await db.assetById(id))!;
    expect(ergebnis.stackId, variantenstapelId('v1'));
    expect(ergebnis.isStackCover, isTrue);
    expect(ergebnis.stackSize, 4);
    expect(ergebnis.originalFileName, 'a-Panorama.jpg');
    final mitglieder = await db.assetsInStack(variantenstapelId('v1'));
    expect({for (final m in mitglieder) m.id}, {id, a.id, x.id, b.id});
    expect(mitglieder.where((m) => m.isStackCover), hasLength(1));
  });

  test('genau dieses Bild gibt es schon: kein Stapel, ein Fehler', () async {
    final a = await aufnahme('a.jpg', DateTime(2024, 6, 3), 30);
    final b = await aufnahme('b.jpg', DateTime(2024, 6, 3, 0, 0, 1), 90);
    await expectLater(
      legeZusammengefuegtesAb(
        db: db,
        quellen: [a, b],
        jpeg: jpeg(1, DateTime(2030)),
        art: Fuegeart.hdr,
        einlesen: (_, _) async => null,
      ),
      throwsStateError,
    );
    expect((await db.assetById(a.id))!.stackId, isNull);
  });

  test('Quellen: nur Fotos, nicht gesperrt, nicht im Papierkorb – nach '
      'Aufnahmezeit', () async {
    Future<void> zeile(
      String id,
      String typ,
      DateTime zeit, {
      bool gesperrt = false,
      bool papierkorb = false,
    }) => db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'o/$id.jpg',
            checksum: 'pruef-$id',
            type: typ,
            fileCreatedAt: zeit,
            importedAt: zeit,
            isLocked: Value(gesperrt),
            isTrashed: Value(papierkorb),
          ),
        );
    await zeile('spaet', 'IMAGE', DateTime(2024, 1, 2));
    await zeile('frueh', 'IMAGE', DateTime(2024, 1, 1));
    await zeile('film', 'VIDEO', DateTime(2024, 1, 1));
    await zeile('geheim', 'IMAGE', DateTime(2024, 1, 1), gesperrt: true);
    await zeile('weg', 'IMAGE', DateTime(2024, 1, 1), papierkorb: true);

    final r = await zusammenfuegbare(db, [
      'spaet',
      'film',
      'geheim',
      'frueh',
      'weg',
    ]);
    expect([for (final q in r.quellen) q.id], ['frueh', 'spaet']);
    expect(r.ausgelassen, 3);
    expect(leitquelle(r.quellen).id, 'frueh');
  });

  test('Fehlertexte nennen den Grund und die betroffene Quelle', () async {
    final t = lookupAppTexte(const Locale('de'));
    final a = await aufnahme('Sonne.jpg', DateTime(2024), 5);
    expect(
      zusammenfuegeFehlertext(
        t,
        const Zusammenfuegefehler(Fuegegrund.keineUeberlappung),
        [a],
        Fuegeart.panorama,
      ),
      t.zusfFehlerUeberlappung,
    );
    expect(
      zusammenfuegeFehlertext(
        t,
        const Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: 0),
        [a],
        Fuegeart.hdr,
      ),
      contains('Sonne.jpg'),
    );
    expect(
      zusammenfuegeFehlertext(t, StateError('kaputt'), [a], Fuegeart.hdr),
      contains('kaputt'),
    );
  });

  test('ganzer Lauf am Rechner: Quellen aus der Bibliothek, Rechnen im '
      'Isolat, Ablage über den Import', () async {
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = importe;
    await db.setAutoAnalyzeAfterImport(false);
    final quellen = <AssetData>[];
    for (final (i, ev, dx) in [(0, -1.5, 3.0), (1, 0.0, 0.0), (2, 1.5, -2.0)]) {
      final bild = belichtungsaufnahme(240, 180, ev, dx: dx);
      final datei = File(p.join(temp.path, 'eingang', 'reihe_$i.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          mitAufnahmezeit(bild.alsJpeg(), DateTime(2024, 7, 1, 12, 0, i)),
        );
      final r = await importe.importFile(datei.path);
      quellen.add((await db.assetById(r.assetId!))!);
    }
    Fuegeausgang? ausgang;
    final stand = await zusammenfuegenLauf(
      library,
      quellen: quellen,
      art: Fuegeart.hdr,
      fertig: (a) => ausgang = a,
    ).toList();
    expect(stand.last.done, 100);
    expect(
      stand.map((s) => s.done),
      orderedEquals([...stand.map((s) => s.done)]..sort()),
    );
    final id = ausgang!.assetId;
    expect(ausgang!.verwendet, 3);
    final ergebnis = (await db.assetById(id))!;
    expect(ergebnis.isStackCover, isTrue);
    expect(ergebnis.stackSize, 4);
    expect(ergebnis.originalFileName, 'reihe_1-HDR.jpg');
    expect(ergebnis.widthPx, inInclusiveRange(230, 240));
    // Der Arbeitsordner ist geräumt.
    expect(
      Directory.systemTemp.listSync().whereType<Directory>().where(
        (d) =>
            p.basename(d.path).startsWith('pv_fuegen_') &&
            d.existsSync() &&
            d.listSync().any((e) => p.basename(e.path) == 'ergebnis.jpg'),
      ),
      isEmpty,
    );
  });
}

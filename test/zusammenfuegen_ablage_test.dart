import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/collage.dart' show mitAufnahmezeit;
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/tresorreihe.dart';
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

  Future<Fuegeablage?> ablegen(
    List<AssetData> quellen,
    Uint8List bytes, {
    Fuegeart art = Fuegeart.hdr,
    bool Function()? abgebrochen,
  }) => legeZusammengefuegtesAb(
    db: db,
    paths: pfade,
    importe: importe,
    quellen: quellen,
    jpeg: bytes,
    art: art,
    abgebrochen: abgebrochen,
  );

  Future<int> anzahlAufnahmen() async =>
      (await db.select(db.assets).get()).length;

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

    final ablage = (await ablegen(quellen, jpeg(200, DateTime(2030))))!;
    final id = ablage.id;
    expect(ablage.neu, isTrue);

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

    final id = (await ablegen(
      quellen,
      jpeg(150, DateTime(2030)),
      art: Fuegeart.panorama,
    ))!.id;

    final ergebnis = (await db.assetById(id))!;
    expect(ergebnis.stackId, variantenstapelId('v1'));
    expect(ergebnis.isStackCover, isTrue);
    expect(ergebnis.stackSize, 4);
    expect(ergebnis.originalFileName, 'a-Panorama.jpg');
    final mitglieder = await db.assetsInStack(variantenstapelId('v1'));
    expect({for (final m in mitglieder) m.id}, {id, a.id, x.id, b.id});
    expect(mitglieder.where((m) => m.isStackCover), hasLength(1));
  });

  group('Alben, Favorit und Sterne aller sichtbaren Quellen (#498)', () {
    test('kommen auf das Ergebnis, auch von einer Quelle, die nicht die '
        'Leitquelle ist', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 4, 9), 20);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 4, 9, 0, 1), 40);
      final c = await aufnahme('c.jpg', DateTime(2024, 6, 4, 9, 0, 2), 80);
      // b ist die Leitquelle; Album, Favorit und Sterne trägt nur a, ein
      // zweites Album nur der Titel eines Stapels um c.
      final x = await aufnahme('x.jpg', DateTime(2024, 6, 4, 9, 0, 3), 90);
      await db.fuehreAus(VariantenBilden('v', [c.id, x.id], x.id));
      await db.fuehreAus(AlbumAnlegen('reise', 'Reise', DateTime(2024)));
      await db.fuehreAus(AlbumAnlegen('beste', 'Beste', DateTime(2024)));
      await db.fuehreAus(AlbumFuellen('reise', [a.id]));
      await db.fuehreAus(AlbumFuellen('beste', [x.id]));
      await db.fuehreAus(FavoritSetzen([a.id], true));
      await db.fuehreAus(BewertungSetzen([a.id], 4));
      await db.fuehreAus(BewertungSetzen([x.id], 2));
      final quellen = await db.assetsByIds([a.id, b.id, c.id]);
      expect(leitquelle(quellen).id, b.id);

      final id = (await ablegen(quellen, jpeg(7, DateTime(2030))))!.id;

      final e = (await db.assetById(id))!;
      expect(e.isStackCover, isTrue);
      expect(e.stackSize, 5);
      expect(e.isFavorite, isTrue);
      expect(e.rating, 4, reason: 'das Maximum der Sterne');
      expect(await db.imAlbum('reise', [id]), contains(id));
      expect(await db.imAlbum('beste', [id]), contains(id));
      // Die Albumseiten zeigen das Ergebnis, nicht die verdeckten Quellen.
      expect([for (final x in await db.albumAufnahmen('reise')) x.id], [id]);
      expect([for (final x in await db.albumAufnahmen('beste')) x.id], [id]);
    });

    test('Gegenprobe: Ohne Angaben an den Quellen bleibt das Ergebnis ohne '
        'Album, Favorit und Sterne', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 5, 9), 20);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 5, 9, 0, 1), 40);
      final id = (await ablegen([a, b], jpeg(8, DateTime(2030))))!.id;
      final e = (await db.assetById(id))!;
      expect(e.isFavorite, isFalse);
      expect(e.rating, 0);
      expect(
        await (db.select(
          db.albumAssets,
        )..where((t) => t.assetId.equals(id))).get(),
        isEmpty,
      );
    });
  });

  group('Gibt es genau dieses Bild schon (#498)', () {
    test('wird das vorhandene eingeordnet statt eines Fehlers – auch '
        'zweimal hintereinander', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 3), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 3, 0, 0, 1), 90);
      final bild = jpeg(1, DateTime(2030));
      // Ein halber Erfolg: Das Bild ist eingelesen, aber nicht gestapelt.
      final bytes = mitAngabenDerQuellen(bild, [a, b]);
      final datei = File(p.join(temp.path, 'halb', 'a-HDR.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
      final halb = (await importe.importFile(datei.path)).assetId!;
      final vorher = await anzahlAufnahmen();

      final erst = (await ablegen([a, b], bild))!;
      expect(erst.id, halb);
      expect(erst.neu, isFalse);
      final zweit = (await ablegen([a, b], bild))!;
      expect(zweit.id, halb);
      expect(await anzahlAufnahmen(), vorher);
      final e = (await db.assetById(halb))!;
      expect(e.isStackCover, isTrue);
      expect(e.stackSize, 3, reason: 'nicht doppelt gezählt');
      expect((await db.assetById(a.id))!.stackId, e.stackId);
    });

    test('liegt es im Papierkorb, wird es zurückgeholt; im gesperrten '
        'Ordner scheitert es mit eigenem Grund', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 6), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 6, 0, 0, 1), 90);
      final bild = jpeg(2, DateTime(2030));
      final erst = (await ablegen([a, b], bild))!;
      // Aus dem Stapel gelöst und weggeworfen.
      await db.fuehreAus(
        VariantenAufloesen((await db.assetById(erst.id))!.stackId!),
      );
      await db.fuehreAus(InDenPapierkorb([erst.id]));
      final quellen = await db.assetsByIds([a.id, b.id]);

      final zurueck = (await ablegen(quellen, bild))!;
      expect(zurueck.id, erst.id);
      expect(zurueck.zurueckgeholt, isTrue);
      final e = (await db.assetById(erst.id))!;
      expect(e.isTrashed, isFalse);
      expect(e.isStackCover, isTrue);

      await (db.update(db.assets)..where((t) => t.id.equals(erst.id))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      await expectLater(
        ablegen(quellen, bild),
        throwsA(
          isA<Zusammenfuegefehler>().having(
            (f) => f.grund,
            'grund',
            Fuegegrund.ergebnisGesperrt,
          ),
        ),
      );
    });
  });

  group('Gesperrt oder weggeworfen, während gerechnet wurde (#498)', () {
    test('ein inzwischen gesperrtes Foto: nichts abgelegt, eigener Grund – '
        'auch wenn das Sperren in der Tresorreihe noch läuft', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 7), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 7, 0, 0, 1), 90);
      final vorher = await anzahlAufnahmen();
      // Ein Sperren, das gerade läuft: Es steht vor dem Ablegen in der
      // Reihe und setzt das Foto erst nach einer Weile auf gesperrt.
      final sperren = inTresorreihe(pfade, () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await (db.update(db.assets)..where((t) => t.id.equals(b.id))).write(
          const AssetsCompanion(isLocked: Value(true)),
        );
      });
      await expectLater(
        ablegen([a, b], jpeg(3, DateTime(2030))),
        throwsA(
          isA<Zusammenfuegefehler>()
              .having((f) => f.grund, 'grund', Fuegegrund.quelleGesperrt)
              .having((f) => f.quelle, 'quelle', 1),
        ),
      );
      await sperren;
      expect(await anzahlAufnahmen(), vorher);
      expect((await db.assetById(a.id))!.stackId, isNull);
    });

    test('im Papierkorb oder gelöscht: ebenso; Gegenprobe offen', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 8), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 8, 0, 0, 1), 90);
      await db.fuehreAus(InDenPapierkorb([a.id]));
      await expectLater(
        ablegen([a, b], jpeg(4, DateTime(2030))),
        throwsA(
          isA<Zusammenfuegefehler>()
              .having((f) => f.grund, 'grund', Fuegegrund.quelleWeg)
              .having((f) => f.quelle, 'quelle', 0),
        ),
      );
      await db.fuehreAus(AusDemPapierkorb([a.id]));
      expect(await ablegen([a, b], jpeg(4, DateTime(2030))), isNotNull);
    });

    test('abgebrochen, während das Ablegen in der Reihe wartete: nichts '
        'abgelegt', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 9), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 9, 0, 0, 1), 90);
      final vorher = await anzahlAufnahmen();
      expect(
        await ablegen([a, b], jpeg(5, DateTime(2030)), abgebrochen: () => true),
        isNull,
      );
      expect(await anzahlAufnahmen(), vorher);
    });
  });

  test('Angaben: Kalenderdatierung, Schätzung, Zeitzone, Ortsnamen und '
      'keine Gesichtssuche (#498)', () async {
    final a = await aufnahme('a.jpg', DateTime(1985, 7, 1, 12), 30);
    final b = await aufnahme('b.jpg', DateTime(1985, 7, 1, 12, 0, 1), 90);
    final c = await aufnahme('c.jpg', DateTime(1985, 7, 1, 12, 0, 2), 150);
    // Die Leitquelle b ist nur aufs Jahr datiert, ihre Zeit geschätzt, und
    // sie kennt ihre Zone; den Ort samt Namen kennt nur c.
    await db.fuehreAus(DatierungSetzen([b.id], AufnahmeDatierung.jahr(1985)));
    await (db.update(db.assets)..where((t) => t.id.equals(b.id))).write(
      const AssetsCompanion(zeitversatzMinuten: Value(120)),
    );
    await db.fuehreAus(
      OrtSetzen(
        [c.id],
        47.37,
        8.54,
        land: 'Schweiz',
        region: 'Zürich',
        stadt: 'Zürich',
      ),
    );
    final quellen = await db.assetsByIds([a.id, b.id, c.id]);
    final leit = quellen.firstWhere((q) => q.id == b.id);

    final id = (await ablegen(quellen, jpeg(6, DateTime(2030))))!.id;

    final e = (await db.assetById(id))!;
    expect(e.fileCreatedAt, leit.fileCreatedAt, reason: 'nicht der Tag heute');
    expect(e.datumVon, leit.datumVon);
    expect(e.datumBis, leit.datumBis);
    expect(e.datumGenauigkeit, leit.datumGenauigkeit);
    expect(e.datumGeschaetzt, isTrue);
    expect(e.latitude, closeTo(47.37, 1e-4));
    expect(e.locationCountry, 'Schweiz');
    expect(e.locationCity, 'Zürich');
    expect(e.faceScanExcluded, isTrue);

    // Gegenprobe Zeitzone: ohne Kalenderdatierung steht die Zeit im EXIF,
    // und mit ihr der Versatz.
    final d = await aufnahme('d.jpg', DateTime(2024, 3, 1, 8), 40);
    final f = await aufnahme('f.jpg', DateTime(2024, 3, 1, 8, 0, 1), 140);
    await (db.update(db.assets)..where((t) => t.id.equals(d.id))).write(
      const AssetsCompanion(zeitversatzMinuten: Value(-270)),
    );
    final mitZone = (await ablegen(
      await db.assetsByIds([d.id, f.id]),
      jpeg(9, DateTime(2030)),
    ))!.id;
    expect((await db.assetById(mitZone))!.zeitversatzMinuten, -270);
    expect((await db.assetById(mitZone))!.fileCreatedAt, d.fileCreatedAt);
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

  test('Fehlertexte nennen den Grund und die betroffene Quelle – für jeden '
      'Grund in beiden Sprachen, ohne Kennung oder „Bad state“', () async {
    final a = await aufnahme('Sonne.jpg', DateTime(2024), 5);
    for (final sprache in ['de', 'en']) {
      final t = lookupAppTexte(Locale(sprache));
      for (final grund in Fuegegrund.values) {
        final text = zusammenfuegeFehlertext(
          t,
          Zusammenfuegefehler(grund, quelle: 0, ursache: StateError('x')),
          [a],
          Fuegeart.hdr,
        );
        expect(text, isNot(contains('pv_')), reason: '$sprache $grund');
        expect(text, isNot(contains('Bad state')), reason: '$sprache $grund');
        expect(text, isNot(contains(grund.name)), reason: '$sprache $grund');
      }
    }
    final t = lookupAppTexte(const Locale('de'));
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
      zusammenfuegeFehlertext(
        t,
        const Zusammenfuegefehler(Fuegegrund.quelleGesperrt, quelle: 0),
        [a],
        Fuegeart.hdr,
      ),
      t.zusfFehlerQuelleGesperrt('Sonne.jpg'),
    );
    // Eine bekannte Kennung vom Import kommt als Satz, eine fremde als Text.
    expect(
      zusammenfuegeFehlertext(
        t,
        const Zusammenfuegefehler(
          Fuegegrund.einlesen,
          ursache: 'pv_import_quelle_geaendert',
        ),
        [a],
        Fuegeart.hdr,
      ),
      t.zusfFehlerEinlesen(t.importFehlerQuelleGeaendert),
    );
    expect(
      zusammenfuegeFehlertext(t, StateError('kaputt'), [a], Fuegeart.hdr),
      t.zusfFehlerAllgemein('kaputt'),
    );
  });

  group('ganzer Lauf am Rechner', () {
    late LibraryState library;
    late List<AssetData> quellen;

    setUp(() async {
      library = LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = importe;
      await db.setAutoAnalyzeAfterImport(false);
      quellen = <AssetData>[];
      for (final (i, ev, dx) in [
        (0, -1.5, 3.0),
        (1, 0.0, 0.0),
        (2, 1.5, -2.0),
      ]) {
        final bild = belichtungsaufnahme(240, 180, ev, dx: dx);
        final datei = File(p.join(temp.path, 'eingang', 'reihe_$i.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(
            mitAufnahmezeit(bild.alsJpeg(), DateTime(2024, 7, 1, 12, 0, i)),
          );
        final r = await importe.importFile(datei.path);
        quellen.add((await db.assetById(r.assetId!))!);
      }
    });

    test('Quellen aus der Bibliothek, Rechnen im Isolat, Ablage über den '
        'Import', () async {
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
      expect(ergebnis.faceScanExcluded, isTrue);
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

      // Ein zweiter Lauf mit denselben Quellen trifft auf genau dieses
      // Bild und meldet es, statt zu scheitern.
      Fuegeausgang? zweiter;
      await zusammenfuegenLauf(
        library,
        quellen: await db.assetsByIds([for (final q in quellen) q.id]),
        art: Fuegeart.hdr,
        fertig: (a) => zweiter = a,
      ).drain<void>();
      expect(zweiter!.assetId, id);
    });

    test('Abbrechen nach der letzten Meldung des Isolats legt nichts ab '
        '(#498)', () async {
      final vorher = await anzahlAufnahmen();
      // Die Tresorreihe ist belegt: Das Ablegen wartet dort, und gekündigt
      // wird, nachdem das Bild fertig gerechnet ist.
      final frei = Completer<void>();
      final belegt = inTresorreihe(pfade, () => frei.future);
      Fuegeausgang? ausgang;
      final letzte = Completer<void>();
      final abo =
          zusammenfuegenLauf(
            library,
            quellen: quellen,
            art: Fuegeart.hdr,
            fertig: (a) => ausgang = a,
          ).listen((s) {
            if (s.done == 95 && !letzte.isCompleted) letzte.complete();
          });
      await letzte.future;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final gekuendigt = abo.cancel();
      frei.complete();
      await belegt;
      await gekuendigt;
      expect(ausgang, isNull);
      expect(await anzahlAufnahmen(), vorher);
      for (final q in await db.assetsByIds([for (final q in quellen) q.id])) {
        expect(q.stackId, isNull);
      }
    });
  });

  group('verbunden', () {
    test('frisch abgeglichen vor dem Hochladen, mit Prüfsumme; eine Dublette '
        'wird eingeordnet', () async {
      final a = await aufnahme('a.jpg', DateTime(2024, 6, 10), 30);
      final b = await aufnahme('b.jpg', DateTime(2024, 6, 10, 0, 0, 1), 90);
      final angaben = <Map<String, String>>[];
      var abgeholt = 0;
      // Der „Server“ importiert in dieselbe Bibliothek; das Abholen ist
      // dann nichts weiter.
      Future<Map<String, String>> hochladen(
        File datei,
        Map<String, String> m,
      ) async {
        angaben.add(m);
        expect(sha256.convert(datei.readAsBytesSync()).toString(), m['sha256']);
        final r = await importe.importFile(datei.path);
        return {'pv-ausgang': r.outcome.name, 'pv-aufnahme': ?r.assetId};
      }

      final bild = jpeg(10, DateTime(2030));
      Future<Fuegeablage?> amServer(List<AssetData> q) =>
          legeZusammengefuegtesAmServerAb(
            db: db,
            quellen: q,
            jpeg: bild,
            art: Fuegeart.hdr,
            hochladen: hochladen,
            abholen: () async => abgeholt++,
          );
      final erst = (await amServer([a, b]))!;
      expect(abgeholt, 2, reason: 'vor dem Hochladen und danach');
      expect(
        angaben.single['geaendert'],
        '${a.fileCreatedAt.millisecondsSinceEpoch}',
      );
      expect((await db.assetById(erst.id))!.isStackCover, isTrue);
      final zweit = (await amServer(await db.assetsByIds([a.id, b.id])))!;
      expect(zweit.id, erst.id);
      expect(zweit.neu, isFalse);
    });

    test(
      'ist eine Quelle nach dem Abgleich gesperrt, geht nichts hinauf',
      () async {
        final a = await aufnahme('a.jpg', DateTime(2024, 6, 11), 30);
        final b = await aufnahme('b.jpg', DateTime(2024, 6, 11, 0, 0, 1), 90);
        var hochgeladen = false;
        await expectLater(
          legeZusammengefuegtesAmServerAb(
            db: db,
            quellen: [a, b],
            jpeg: jpeg(11, DateTime(2030)),
            art: Fuegeart.hdr,
            hochladen: (_, _) async {
              hochgeladen = true;
              return const {'pv-ausgang': 'imported'};
            },
            // Das Abholen bringt die Sperre von einem anderen Gerät mit.
            abholen: () =>
                (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(
                  const AssetsCompanion(isLocked: Value(true)),
                ),
          ),
          throwsA(
            isA<Zusammenfuegefehler>().having(
              (f) => f.grund,
              'grund',
              Fuegegrund.quelleGesperrt,
            ),
          ),
        );
        expect(hochgeladen, isFalse);
      },
    );
  });
}

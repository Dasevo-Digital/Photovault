import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/jpeg_angaben.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/restore_queue_screen.dart';
import 'package:photo_vault/services/entwicklung_ablegen.dart';
import 'package:photo_vault/services/hochskalieren.dart';
import 'package:photo_vault/services/hochskalieren_ablegen.dart';
import 'package:photo_vault/services/restore_queue_service.dart';
import 'package:photo_vault/services/restore_service.dart';

/// Das Ergebnis des Hochskalierens wird eine eigene Aufnahme im
/// Variantenstapel des Originals (#500) – mit dessen Angaben, mit dem
/// Original als Hauptbild, auch über einen Server. Dazu der Weg durch die
/// Warteschlange der Restaurierung mit einem Ersatzmodell, das einfach
/// vergrössert.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_hochskalieren_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    importe = ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  var nummer = 0;
  Future<AssetData> foto({
    String name = 'urlaub.jpg',
    int breite = 40,
    int hoehe = 30,
  }) async {
    final bild = img.Image(width: breite, height: hoehe);
    // Jedes Foto anders, sonst wären es Dubletten.
    img.fill(bild, color: img.ColorRgb8(20 + nummer++ * 10, 90, 40));
    final ordner = await Directory(
      p.join(temp.path, 'quelle', '$nummer'),
    ).create(recursive: true);
    final f = File(p.join(ordner.path, name))
      ..writeAsBytesSync(img.encodeJpg(bild));
    final r = await importe.importFile(f.path);
    return (await db.assetById(r.assetId!))!;
  }

  Uint8List vergroessert(AssetData asset, int faktor) {
    final bild = img.decodeJpg(
      paths.absolute(asset.relativePath).readAsBytesSync(),
    )!;
    return img.encodeJpg(
      img.copyResize(
        bild,
        width: bild.width * faktor,
        height: bild.height * faktor,
      ),
    );
  }

  Future<String?> lege(
    AssetData original,
    Uint8List jpeg,
    int faktor, {
    bool Function()? abgebrochen,
    Future<void> Function(String id)? nachbearbeiten,
  }) => legeHochskaliertAb(
    db: db,
    paths: paths,
    importe: importe,
    ablage: Hochskalierablage(
      originalId: original.id,
      jpeg: jpeg,
      faktor: faktor,
      abgebrochen: abgebrochen,
    ),
    nachbearbeiten: nachbearbeiten,
  );

  Future<int> anzahlAufnahmen() async =>
      (await db.select(db.assets).get()).length;

  group('als Variante ablegen', () {
    test(
      'ohne Stapel: neue Aufnahme, Original bleibt Hauptbild, Angaben mit',
      () async {
        final original = await foto();
        final zeit = DateTime(2019, 7, 14, 16, 30);
        await db.fuehreAus(
          AufnahmedatenSetzen([
            (id: original.id, zeitpunkt: zeit, geschaetzt: false),
          ]),
        );
        await db.fuehreAus(
          OrtSetzen(
            [original.id],
            43.7,
            7.26,
            land: 'Frankreich',
            region: 'PACA',
            stadt: 'Nizza',
          ),
        );
        await db.fuehreAus(
          BeschreibungSetzen([original.id], 'Am Strand mit Oma'),
        );
        await db.fuehreAus(SchlagwortAnheften([original.id], 'Sommer'));
        await db.fuehreAus(
          SchlagwortAnheften([original.id], 'strand', quelle: Tagquelle.ki),
        );
        await db.fuehreAus(BewertungSetzen([original.id], 4));
        await db.fuehreAus(FarbmarkeSetzen([original.id], 'rot'));
        await db.fuehreAus(FavoritSetzen([original.id], true));
        await (db.update(
          db.assets,
        )..where((t) => t.id.equals(original.id))).write(
          const AssetsCompanion(
            zeitversatzMinuten: Value(120),
            cameraMake: Value('Canon'),
            cameraModel: Value('EOS R10'),
          ),
        );
        final stand = (await db.assetById(original.id))!;

        // Wie die Warteschlange: die Angaben ins JPEG, dann ablegen.
        final datei = mitHochskalierangaben(vergroessert(original, 4), stand);
        final id = await lege(original, datei, 4);

        final neu = (await db.assetById(id!))!;
        final vorher = (await db.assetById(original.id))!;
        expect(neu.originalFileName, 'urlaub (4×).jpg');
        expect((neu.widthPx, neu.heightPx), (160, 120));
        expect(neu.fileCreatedAt.isAtSameMomentAs(zeit), isTrue);
        expect((neu.latitude, neu.longitude), (43.7, 7.26));
        expect(neu.locationCity, 'Nizza');
        expect(neu.description, 'Am Strand mit Oma');
        expect(neu.rating, 4);
        expect(neu.colorLabel, 'rot');
        expect(neu.isFavorite, isTrue);
        expect(neu.faceScanExcluded, isTrue);
        // Der Zeitzonenversatz kommt nur über die Datei (es gibt keinen
        // Befehl dafür), ebenso stehen Zeit und Ort in ihr.
        expect(neu.zeitversatzMinuten, 120);
        final exif = img.decodeJpgExif(
          paths.absolute(neu.relativePath).readAsBytesSync(),
        )!;
        expect(
          exif.exifIfd['DateTimeOriginal']?.toString(),
          '2019:07:14 16:30:00',
        );
        expect(exif.exifIfd['OffsetTimeOriginal']?.toString(), '+02:00');
        expect(exif.gpsIfd['GPSLatitudeRef']?.toString(), 'N');
        // Ohne Kamera: Eine Kameravorgabe entwickelte das schon entwickelte
        // Bild sonst ein zweites Mal.
        expect(exif.imageIfd.make, isNull);
        expect(neu.cameraMake, isNull);
        final schlagwoerter = [
          for (final t in await db.tagsForAsset(neu.id)) t.name,
        ];
        expect(schlagwoerter, contains('Sommer'));
        expect(
          schlagwoerter,
          isNot(contains('strand')),
          reason: 'die Bilderkennung vergibt ihre eigenen',
        );

        expect(istVariantenstapel(vorher.stackId), isTrue);
        expect(neu.stackId, vorher.stackId);
        expect(vorher.isStackCover, isTrue);
        expect(vorher.stackSize, 2);
        expect(neu.isStackCover, isFalse);
      },
    );

    test('im Variantenstapel: kommt dazu, das Titelbild bleibt', () async {
      final titel = await foto(name: 'titel.jpg');
      final original = await foto(name: 'zweite.jpg');
      await db.fuehreAus(
        VariantenBilden('v1', [titel.id, original.id], titel.id),
      );

      final id = await lege(
        (await db.assetById(original.id))!,
        vergroessert(original, 2),
        2,
      );

      final mitglieder = await db.assetsInStack(variantenstapelId('v1'));
      expect({for (final m in mitglieder) m.id}, {titel.id, original.id, id});
      final oben = mitglieder.singleWhere((m) => m.isStackCover);
      expect(oben.id, titel.id);
      expect(oben.stackSize, 3);
    });

    test('in einer Serie: bleibt eine Serie', () async {
      final a = await foto(name: 'a.jpg');
      final b = await foto(name: 'b.jpg');
      await db.fuehreAus(SerieBilden('serie-1', [a.id, b.id], a.id));

      final id = await lege((await db.assetById(a.id))!, vergroessert(a, 2), 2);

      final neu = (await db.assetById(id!))!;
      expect(neu.stackId, 'serie-1');
      expect((await db.assetById(a.id))!.stackSize, 3);
    });

    test(
      'im Formatstapel: wird ein gewöhnlicher Variantenstapel mit allen',
      () async {
        // RAW und JPEG derselben Aufnahme (#361), das RAW vorn.
        final raw = await foto(name: 'IMG_0001.jpg');
        final jpg = await foto(name: 'IMG_0001b.jpg');
        await db.fuehreAus(
          VariantenBilden('format-abc', [raw.id, jpg.id], raw.id),
        );
        final stapel = (await db.assetById(jpg.id))!.stackId;
        expect(istFormatstapel(stapel), isTrue);

        final id = await lege(
          (await db.assetById(jpg.id))!,
          vergroessert(jpg, 2),
          2,
        );

        final neu = (await db.assetById(id!))!;
        expect(istVariantenstapel(neu.stackId), isTrue);
        expect(
          istFormatstapel(neu.stackId),
          isFalse,
          reason: 'die Vergrösserung ist kein weiteres Format',
        );
        final mitglieder = await db.assetsInStack(neu.stackId!);
        expect({for (final m in mitglieder) m.id}, {raw.id, jpg.id, id});
        expect(mitglieder.singleWhere((m) => m.isStackCover).id, raw.id);
        expect(await db.assetsInStack(stapel!), isEmpty);
      },
    );

    test('beim Beenden abgebrochen: nichts angelegt', () async {
      final original = await foto();
      final zahl = await anzahlAufnahmen();
      await expectLater(
        lege(original, vergroessert(original, 2), 2, abgebrochen: () => true),
        throwsA(isA<AblageAbgebrochen>()),
      );
      expect(await anzahlAufnahmen(), zahl);
    });

    test('scheitert die Nachbearbeitung, gilt das Ablegen trotzdem', () async {
      final original = await foto();
      final id = await lege(
        original,
        vergroessert(original, 2),
        2,
        nachbearbeiten: (_) async => throw StateError('Regeln kaputt'),
      );
      expect(id, isNotNull);
      expect((await db.assetById(id!))!.stackId, isNotNull);
    });

    test(
      'ein fertiger Auftrag öffnet das Ergebnis, nicht das Original',
      () async {
        final original = await foto(name: 'oma.jpg');
        final id = await lege(original, vergroessert(original, 3), 3);
        RestoreJobData auftrag(String kennung) => RestoreJobData(
          id: kennung,
          assetId: original.id,
          status: 'done',
          tilesDone: 1,
          tilesTotal: 1,
          createdAt: DateTime(2026),
        );
        expect(
          (await ergebnisDesAuftrags(
            db,
            auftrag(hochskalierAuftragsId(3)),
          ))!.id,
          id,
        );
        // Ein anderer Faktor und eine Restaurierung: das Original.
        expect(
          (await ergebnisDesAuftrags(
            db,
            auftrag(hochskalierAuftragsId(2)),
          ))!.id,
          original.id,
        );
        expect(
          (await ergebnisDesAuftrags(db, auftrag('restaurierung')))!.id,
          original.id,
        );
      },
    );

    test('liegt dieselbe Datei im Papierkorb, kommt sie zurück', () async {
      final original = await foto();
      final jpeg = vergroessert(original, 2);
      final erst = await lege(original, jpeg, 2);
      await db.fuehreAus(InDenPapierkorb([erst!]));

      final zweit = await lege(original, jpeg, 2);

      expect(zweit, erst);
      expect((await db.assetById(erst))!.isTrashed, isFalse);
    });

    test('der Zeitzonenversatz steht im EXIF, nur wo er gewollt ist', () async {
      final original = (await foto()).copyWith(
        zeitversatzMinuten: const Value(-270),
      );
      final jpeg = img.encodeJpg(img.Image(width: 4, height: 4));
      String? versatz(Uint8List b) =>
          img.decodeJpgExif(b)?.exifIfd['OffsetTimeOriginal']?.toString();

      expect(versatz(mitHochskalierangaben(jpeg, original)), '-04:30');
      // Export und Fotobuch bleiben, wie sie waren.
      expect(versatz(mitAufnahmeangaben(jpeg, original)), isNull);
      expect(
        versatz(
          mitHochskalierangaben(
            jpeg,
            original.copyWith(zeitversatzMinuten: const Value(null)),
          ),
        ),
        isNull,
      );
    });

    test('zweimal dasselbe Ergebnis: eine Aufnahme, Stapel bleibt', () async {
      final original = await foto();
      final jpeg = vergroessert(original, 3);
      final erst = await lege(original, jpeg, 3);
      final zahl = await anzahlAufnahmen();

      final zweit = await lege(original, jpeg, 3);

      expect(zweit, erst);
      expect(await anzahlAufnahmen(), zahl);
      expect((await db.assetById(original.id))!.stackSize, 2);
    });

    test('gesperrt oder im Papierkorb: nichts wird angelegt', () async {
      final original = await foto();
      final jpeg = vergroessert(original, 2);
      final zahl = await anzahlAufnahmen();

      await db.setAssetsLocked([original.id], true);
      await expectLater(
        lege(original, jpeg, 2),
        throwsA(
          isA<AufnahmeNichtAblegbar>().having(
            (e) => e.gesperrt,
            'gesperrt',
            isTrue,
          ),
        ),
      );
      await db.setAssetsLocked([original.id], false);
      await db.moveToTrash([original.id]);
      await expectLater(
        lege(original, jpeg, 2),
        throwsA(isA<AufnahmeNichtAblegbar>()),
      );

      expect(await anzahlAufnahmen(), zahl);
      expect((await db.assetById(original.id))!.stackId, isNull);
    });
  });

  group('mit Server', () {
    test('die Datei geht hoch, die Befehle ordnen ein', () async {
      final original = await foto();
      final jpeg = vergroessert(original, 2);
      Map<String, String>? gesendet;
      var abgeholt = 0;

      final id = await legeHochskaliertAmServerAb(
        db: db,
        ablage: Hochskalierablage(
          originalId: original.id,
          jpeg: jpeg,
          faktor: 2,
        ),
        // Der „Server“ importiert in dieselbe Datenbank – so, als hätte
        // der Abgleich die neue Aufnahme schon in die Kopie gebracht.
        hochladen: (datei, angaben, {fortsetzen, angelegt, abbrechen}) async {
          gesendet = angaben;
          final r = await importe.importFile(datei.path);
          return {'pv-ausgang': 'imported', 'pv-aufnahme': r.assetId!};
        },
        abholen: () async => abgeholt++,
      );

      expect(gesendet?['filename'], 'urlaub (2×).jpg');
      expect(
        gesendet?['geaendert'],
        '${original.fileCreatedAt.millisecondsSinceEpoch}',
      );
      expect(gesendet?['abgeleitetVon'], original.id);
      expect(gesendet?['sha256'], sha256.convert(jpeg).toString());
      // Vorher, damit eine Sperre von anderswo ankommt, und nachher, um die
      // neue Aufnahme zu holen.
      expect(abgeholt, 2);
      final neu = (await db.assetById(id!))!;
      expect(neu.stackId, (await db.assetById(original.id))!.stackId);
      expect(neu.stackId, isNotNull);
    });

    test('lehnt der Server ab, wird nichts eingeordnet', () async {
      final original = await foto();
      await expectLater(
        legeHochskaliertAmServerAb(
          db: db,
          ablage: Hochskalierablage(
            originalId: original.id,
            jpeg: vergroessert(original, 2),
            faktor: 2,
          ),
          hochladen: (_, _, {fortsetzen, angelegt, abbrechen}) async => {
            'pv-ausgang': 'failed',
            'pv-fehler': Uri.encodeComponent('pv_speicher_voll'),
          },
          abholen: () async {},
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('pv_speicher_voll'),
          ),
        ),
      );
      expect((await db.assetById(original.id))!.stackId, isNull);
    });
  });

  group('mit Server: Sperre von anderswo und Gesichter (#430, #500)', () {
    /// Der „Server“ importiert in dieselbe Datenbank; [nachImport] läuft
    /// gleich danach, als hätte er schon weitergerechnet.
    Hochladen server({
      FutureOr<void> Function(String id)? nachImport,
      Map<String, String>? antwort,
      void Function()? vorher,
    }) => (datei, angaben, {fortsetzen, angelegt, abbrechen}) async {
      vorher?.call();
      if (antwort != null) return antwort;
      final r = await importe.importFile(datei.path);
      nachImport?.call(r.assetId!);
      return {'pv-ausgang': 'imported', 'pv-aufnahme': r.assetId!};
    };

    Future<String?> amServer(
      AssetData original,
      Hochladen hochladen, {
      Future<void> Function()? abholen,
    }) => legeHochskaliertAmServerAb(
      db: db,
      ablage: Hochskalierablage(
        originalId: original.id,
        jpeg: vergroessert(original, 2),
        faktor: 2,
      ),
      hochladen: hochladen,
      abholen: abholen ?? () async {},
      paths: paths,
    );

    test(
      'vor dem Hochladen frisch abgeholt: gesperrt, nichts geht hoch',
      () async {
        final original = await foto();
        var hochgeladen = 0;
        await expectLater(
          amServer(
            original,
            server(vorher: () => hochgeladen++),
            // Das Abholen bringt die Sperre eines anderen Geräts.
            abholen: () => db.setAssetsLocked([original.id], true),
          ),
          throwsA(
            isA<AufnahmeNichtAblegbar>().having((e) => e.gesperrt, 'g', isTrue),
          ),
        );
        expect(hochgeladen, 0);
      },
    );

    test(
      'während des Hochladens gesperrt: die Kopie geht in den Papierkorb',
      () async {
        final original = await foto();
        var abgeholt = 0;
        String? neu;
        await expectLater(
          amServer(
            original,
            server(nachImport: (id) => neu = id),
            abholen: () async {
              if (++abgeholt == 2) {
                await db.setAssetsLocked([original.id], true);
              }
            },
          ),
          throwsA(isA<AufnahmeNichtAblegbar>()),
        );
        final kopie = (await db.assetById(neu!))!;
        expect(kopie.isTrashed, isTrue, reason: 'keine offene Klartextkopie');
        expect(kopie.stackId, isNull);
      },
    );

    test(
      'meldet der Server das Original gesperrt, ist nichts abgelegt',
      () async {
        final original = await foto();
        await expectLater(
          amServer(
            original,
            server(
              antwort: {
                'pv-ausgang': 'failed',
                'pv-fehler': 'pv_original_gesperrt',
              },
            ),
          ),
          throwsA(
            isA<AufnahmeNichtAblegbar>().having((e) => e.gesperrt, 'g', isTrue),
          ),
        );
      },
    );

    test('scheitert das Einordnen, geht die Kopie in den Papierkorb', () async {
      final original = await foto();
      void beobachter(Befehl<Object?> b, Object? _) {
        if (b is VariantenBilden) throw StateError('Stapel kaputt');
      }

      db.befehlsbeobachter.add(beobachter);
      addTearDown(() => db.befehlsbeobachter.remove(beobachter));
      String? neu;
      await expectLater(
        amServer(original, server(nachImport: (id) => neu = id)),
        throwsStateError,
      );
      expect((await db.assetById(neu!))!.isTrashed, isTrue);
    });

    test(
      'die Gesichtssuche ist der erste Befehl, schon Erkanntes geht weg',
      () async {
        final original = await foto();
        await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
        final ablauf = <String>[];
        void beobachter(Befehl<Object?> b, Object? _) => ablauf.add(b.art);
        db.befehlsbeobachter.add(beobachter);
        addTearDown(() => db.befehlsbeobachter.remove(beobachter));
        Future<void> gesicht(
          String id,
          String asset, {
          String? person,
          bool automatisch = false,
        }) => db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                id: id,
                assetId: asset,
                personId: Value(person),
                boxX: 0.1,
                boxY: 0.1,
                boxW: 0.3,
                boxH: 0.3,
                automatischZugeordnet: Value(automatisch),
              ),
            );

        final id = await amServer(
          original,
          // Der Server war schneller und hat schon Gesichter gefunden.
          server(
            nachImport: (neu) async {
              ablauf.add('hochgeladen');
              await gesicht('unbenannt', neu);
              await gesicht('vermutet', neu, person: 'p1', automatisch: true);
              await gesicht('von-hand', neu, person: 'p1');
            },
          ),
          abholen: () async => ablauf.add('abholen'),
        );

        final nachHochladen = ablauf.sublist(ablauf.indexOf('hochgeladen') + 1);
        expect(nachHochladen.first, 'gesichtssucheAusnehmen');
        expect(
          nachHochladen.indexOf('gesichtssucheAusnehmen'),
          lessThan(nachHochladen.indexOf('abholen')),
        );
        expect((await db.assetById(id!))!.faceScanExcluded, isTrue);
        expect(
          [for (final f in await db.facesForAsset(id)) f.id],
          ['von-hand'],
        );
      },
    );
  });

  group('in der Warteschlange', () {
    late _Modell modell;
    late _Warteschlange queue;

    setUp(() {
      modell = _Modell();
      queue = _Warteschlange(db, paths)
        ..restoreHalter = ModellHalter<RestoreService>(
          name: 'Ersatzmodell',
          installiert: true,
          laden: () async => modell,
          entsorgen: (_) async {},
        )
        ..hochskaliertAblegen = (ablage) => legeHochskaliertAb(
          db: db,
          paths: paths,
          importe: importe,
          ablage: ablage,
        );
    });

    Future<RestoreJobData> auftrag(String id) async {
      for (var i = 0; i < 500 && queue.isProcessing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return (await db.watchRestoreJobs().first).singleWhere((j) => j.id == id);
    }

    test('rechnet 3× und legt die Variante ab', () async {
      final original = await foto();
      queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();

      final id = await queue.hochskalieren(original.id, 3);

      final job = await auftrag(id);
      expect(job.status, 'done', reason: '${job.errorMessage}');
      expect(modell.faktoren, [3]);
      final mitglieder = await db.assetsInStack(
        (await db.assetById(original.id))!.stackId!,
      );
      final neu = mitglieder.singleWhere((m) => m.id != original.id);
      expect((neu.widthPx, neu.heightPx), (120, 90));
    });

    test(
      'derselbe Faktor nur einmal, eine Restaurierung daneben schon',
      () async {
        final original = await foto();
        queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
        modell.halten = true;

        final erst = await queue.hochskalieren(original.id, 2);
        await modell.begonnen.future;
        final nochmal = await queue.hochskalieren(original.id, 2);
        final anders = await queue.hochskalieren(original.id, 4);
        final restaurierung = await queue.enqueue(original.id);

        expect(nochmal, erst);
        expect({erst, anders, restaurierung}, hasLength(3));
        expect(hochskalierfaktor(anders), 4);
        expect(hochskalierfaktor(restaurierung), isNull);

        // Aufräumen: Die wartenden gehen sofort, der laufende bricht ab.
        await queue.cancel(anders);
        await queue.cancel(restaurierung);
        await queue.cancel(erst);
        expect((await auftrag(erst)).status, 'cancelled');
      },
    );

    test('ein Video wird nicht hochskaliert', () async {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: 'video',
              originalFileName: 'film.mov',
              relativePath: 'originals/film.mov',
              checksum: 'film',
              type: 'VIDEO',
              fileCreatedAt: DateTime(2024),
              importedAt: DateTime(2024),
              widthPx: const Value(1920),
              heightPx: const Value(1080),
            ),
          );

      final job = await auftrag(await queue.hochskalieren('video', 2));

      expect(job.status, 'failed');
      expect(job.errorMessage, RestaurierungsGrund.keinFoto.name);
      expect(modell.faktoren, isEmpty);
    });

    test('ist die Vorlage zu gross geworden, wird nicht gerechnet', () async {
      final original = await foto();
      // Seit dem Einreihen breiter entwickelt: 2× gäbe 18000 px.
      queue.vorlage = img.encodeJpg(img.Image(width: 9000, height: 8));

      final job = await auftrag(await queue.hochskalieren(original.id, 2));

      expect(job.status, 'failed');
      expect(job.errorMessage, RestaurierungsGrund.zuGross.name);
      expect(modell.faktoren, isEmpty);
    });

    File aufgehoben(String auftrag) =>
        File(p.join(paths.root.path, 'auftragsergebnisse', '$auftrag.jpg'));

    Future<void> restauriert(AssetData original, img.Image bild) async {
      const pfad = 'restored/entrauscht.jpg';
      paths.absolute(pfad)
        ..createSync(recursive: true)
        ..writeAsBytesSync(img.encodeJpg(bild));
      await db.fuehreAus(RestaurierungSpeichern(original.id, pfad));
    }

    test('ein KI-Entrauschen in Originalgrösse ist die Vorlage', () async {
      final original = await foto();
      final entrauscht = img.Image(width: 40, height: 30);
      img.fill(entrauscht, color: img.ColorRgb8(1, 2, 3));
      await restauriert(original, entrauscht);
      queue.vorlage = img.encodeJpg(img.Image(width: 40, height: 30));

      final id = await queue.hochskalieren(original.id, 2);

      expect((await auftrag(id)).status, 'done');
      expect(
        modell.eingaben.single,
        paths.absolute('restored/entrauscht.jpg').readAsBytesSync(),
        reason: 'sonst wäre das verrauschte Bild vergrössert worden',
      );
      final plan = await queue.hochskalierplan(
        (await db.assetById(original.id))!,
      );
      expect(plan.quelle, Hochskalierquelle.restaurierung);
      expect((plan.breite, plan.hoehe), (40, 30));
    });

    test('eine schon vergrösserte Restaurierung wird übergangen', () async {
      final original = await foto();
      await restauriert(original, img.Image(width: 160, height: 120));
      queue.vorlage = img.encodeJpg(img.Image(width: 40, height: 30));

      final id = await queue.hochskalieren(original.id, 2);

      expect((await auftrag(id)).status, 'done');
      expect(modell.eingaben.single, queue.vorlage);
      final plan = await queue.hochskalierplan(
        (await db.assetById(original.id))!,
      );
      expect(plan.quelle, Hochskalierquelle.entwicklung);
      expect(plan.restaurierungUebergangen, isTrue);
    });

    test('der Dialog rechnet mit dem gespeicherten Zuschnitt', () async {
      final original = await foto();
      await db
          .into(db.developSettings)
          .insert(
            DevelopSettingsCompanion.insert(
              assetId: original.id,
              updatedAt: DateTime(2026),
              cropJson: Value(
                Bildzuschnitt(breite: 0.5, hoehe: 0.5, drehungen: 1).json,
              ),
            ),
          );
      final plan = await queue.hochskalierplan(original);
      // 40 × 30, halbiert und eine Vierteldrehung.
      expect((plan.breite, plan.hoehe), (15, 20));
      expect(plan.quelle, Hochskalierquelle.entwicklung);
      expect(plan.restaurierungUebergangen, isFalse);
    });

    test('scheitert das Ablegen, bleibt das Ergebnis – ein zweiter Versuch '
        'rechnet nicht noch einmal und setzt das Hochladen fort', () async {
      final original = await foto();
      queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
      final echt = queue.hochskaliertAblegen!;
      final orte = <String?>[];
      var versuch = 0;
      queue.hochskaliertAblegen = (ablage) async {
        orte.add(ablage.hochladeort);
        if (++versuch == 1) {
          ablage.hochladeortMerken!('api/v1/hochladen/abc');
          throw StateError('Leitung weg');
        }
        return echt(ablage);
      };

      final id = await queue.hochskalieren(original.id, 2);
      final erst = await auftrag(id);
      expect(erst.status, 'failed');
      expect(erst.errorMessage, contains('Leitung weg'));
      expect(aufgehoben(id).existsSync(), isTrue);

      await queue.wiederholen(id);
      final zweit = await auftrag(id);

      expect(zweit.status, 'done', reason: '${zweit.errorMessage}');
      expect(modell.faktoren, [2], reason: 'nur einmal gerechnet');
      expect(orte, [null, 'api/v1/hochladen/abc']);
      expect(aufgehoben(id).existsSync(), isFalse);
    });

    test('beim Beenden mitten im Ablegen: der Auftrag bleibt offen und legt '
        'nach dem Neustart ab, ohne zu rechnen', () async {
      final original = await foto();
      queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
      final begonnen = Completer<void>();
      queue.hochskaliertAblegen = (ablage) async {
        begonnen.complete();
        // Wie das Hochladen: vor jedem Stück nach dem Abbruch fragen.
        while (true) {
          ablage.pruefeAbbruch();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      };

      final id = await queue.hochskalieren(original.id, 4);
      await begonnen.future;
      final uhr = Stopwatch()..start();
      await queue.beende();
      expect(
        uhr.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'das Ablegen hört auf, statt die Frist auszuschöpfen',
      );
      expect((await auftrag(id)).status, 'running');
      expect(aufgehoben(id).existsSync(), isTrue);

      // Der nächste Start.
      await db.resetStuckRunningRestoreJobs();
      final neuesModell = _Modell();
      final danach = _Warteschlange(db, paths)
        ..restoreHalter = ModellHalter<RestoreService>(
          name: 'Ersatzmodell',
          installiert: true,
          laden: () async => neuesModell,
          entsorgen: (_) async {},
        )
        ..hochskaliertAblegen = (ablage) => legeHochskaliertAb(
          db: db,
          paths: paths,
          importe: importe,
          ablage: ablage,
        );
      await danach.resume();
      for (var i = 0; i < 500 && danach.isProcessing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final job = (await db.watchRestoreJobs().first).singleWhere(
        (j) => j.id == id,
      );
      expect(job.status, 'done', reason: '${job.errorMessage}');
      expect(neuesModell.faktoren, isEmpty);
      final stapel = (await db.assetById(original.id))!.stackId!;
      final neu = (await db.assetsInStack(
        stapel,
      )).singleWhere((m) => m.id != original.id);
      expect((neu.widthPx, neu.heightPx), (160, 120));
      expect(aufgehoben(id).existsSync(), isFalse);
    });

    test(
      'während des Rechnens gesperrt: auch das aufgehobene Ergebnis geht',
      () async {
        final original = await foto();
        queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
        final weiter = Completer<void>();
        modell.warten = weiter;

        final id = await queue.hochskalieren(original.id, 2);
        await modell.begonnen.future;
        await db.setAssetsLocked([original.id], true);
        weiter.complete();
        final job = await auftrag(id);

        expect(job.status, 'failed');
        expect(job.errorMessage, RestaurierungsGrund.gesperrt.name);
        expect(aufgehoben(id).existsSync(), isFalse);
      },
    );

    test('beim Sperren verschwinden aufgehobene Ergebnisse', () async {
      final original = await foto();
      queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
      queue.hochskaliertAblegen = (_) async => throw StateError('weg');
      final id = await queue.hochskalieren(original.id, 2);
      expect((await auftrag(id)).status, 'failed');
      expect(aufgehoben(id).existsSync(), isTrue);

      await queue.verwirfErgebnisseFuer([original.id]);

      expect(aufgehoben(id).existsSync(), isFalse);
    });

    test('aus der Liste genommen: das Ergebnis geht mit', () async {
      final original = await foto();
      queue.vorlage = paths.absolute(original.relativePath).readAsBytesSync();
      queue.hochskaliertAblegen = (_) async => throw StateError('weg');
      final id = await queue.hochskalieren(original.id, 2);
      await auftrag(id);

      await queue.entferne(id);

      expect(aufgehoben(id).existsSync(), isFalse);
      expect(await db.watchRestoreJobs().first, isEmpty);
    });

    test(
      'beim Start wird aufgeräumt, was kein offener Auftrag braucht',
      () async {
        final original = await foto();
        Future<void> auftragMit(String id, String status) async {
          await db.createRestoreJob(
            RestoreJobsCompanion.insert(
              id: id,
              assetId: original.id,
              status: status,
              createdAt: DateTime(2026),
            ),
          );
          aufgehoben(id)
            ..createSync(recursive: true)
            ..writeAsBytesSync(img.encodeJpg(img.Image(width: 2, height: 2)));
        }

        await auftragMit('gescheitert', 'failed');
        await auftragMit('fertig', 'done');
        aufgehoben('verwaist')
          ..createSync(recursive: true)
          ..writeAsBytesSync([1, 2, 3]);

        await queue.resumeWhenIdle();
        for (var i = 0; i < 200 && aufgehoben('verwaist').existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await queue.beende();

        expect(aufgehoben('gescheitert').existsSync(), isTrue);
        expect(aufgehoben('fertig').existsSync(), isFalse);
        expect(aufgehoben('verwaist').existsSync(), isFalse);
      },
    );

    test('ein Faktor, den diese Fassung nicht kennt, läuft nicht als '
        'Restaurierung', () async {
      final original = await foto();
      await restauriert(original, img.Image(width: 160, height: 120));
      const fremd = 'hochskalieren-8x-6f1c0c1e-2b3a-4d5e-8f90-123456789abc';
      await db.createRestoreJob(
        RestoreJobsCompanion.insert(
          id: fremd,
          assetId: original.id,
          status: 'queued',
          createdAt: DateTime(2026),
        ),
      );

      await queue.resume();
      final job = await auftrag(fremd);

      expect(job.status, 'failed');
      expect(job.errorMessage, RestaurierungsGrund.unbekannteArt.name);
      expect(modell.faktoren, isEmpty);
      expect(
        (await db.assetById(original.id))!.restoredRelativePath,
        'restored/entrauscht.jpg',
        reason: 'die vorhandene Restaurierung bleibt',
      );
      expect(istHochskalierauftrag(fremd), isTrue);
      expect(hochskalierfaktor(fremd), isNull);
    });

    test('ohne Modell lässt sich nichts einreihen', () async {
      final original = await foto();
      queue.restoreHalter = ModellHalter<RestoreService>(
        name: 'fehlt',
        installiert: false,
        laden: () async => modell,
        entsorgen: (_) async {},
      );
      await expectLater(
        queue.hochskalieren(original.id, 2),
        throwsA(isA<RestaurierungNichtVerfuegbar>()),
      );
      expect(await db.watchRestoreJobs().first, isEmpty);
    });
  });
}

/// Die Warteschlange mit einer festen Vorlage statt des nativen
/// Entwickelns, das es im Prüfstand nicht gibt.
class _Warteschlange extends RestoreQueueService {
  _Warteschlange(super.db, super.paths);

  Uint8List? vorlage;

  @override
  Future<Uint8List?> entwickeltesJpeg(AssetData asset) async => vorlage;
}

/// Ein „Modell“, das einfach vergrössert – ohne ONNX.
class _Modell implements RestoreService {
  final faktoren = <int>[];
  final begonnen = Completer<void>();

  /// Was das „Netz“ als Vorlage bekam.
  final eingaben = <Uint8List>[];

  /// Hält den Lauf an, bis er abgebrochen wird.
  bool halten = false;

  /// Hält den Lauf an, bis dies erfüllt ist – dann rechnet er.
  Completer<void>? warten;

  @override
  Restaurierungslauf starteHochskalieren(
    Uint8List quelle, {
    required int faktor,
    int quality = 92,
    void Function(int done, int total)? onProgress,
  }) {
    faktoren.add(faktor);
    eingaben.add(quelle);
    if (!begonnen.isCompleted) begonnen.complete();
    final lauf = _Lauf();
    Uint8List rechne() {
      final bild = img.decodeJpg(quelle)!;
      onProgress?.call(1, 1);
      return img.encodeJpg(
        img.copyResize(
          bild,
          width: bild.width * faktor,
          height: bild.height * faktor,
        ),
      );
    }

    final w = warten;
    if (w != null) {
      unawaited(
        w.future.then((_) {
          if (!lauf.fertig.isCompleted) lauf.fertig.complete(rechne());
        }),
      );
    } else if (!halten) {
      lauf.fertig.complete(rechne());
    }
    return lauf;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Lauf implements Restaurierungslauf {
  final fertig = Completer<Uint8List?>();

  @override
  Future<Uint8List?> get ergebnis => fertig.future;

  @override
  void abbrechen() {
    if (!fertig.isCompleted) fertig.complete(null);
  }

  @override
  void fortsetzen() {}

  @override
  void pausieren() {}
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
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

  Future<String?> lege(AssetData original, Uint8List jpeg, int faktor) =>
      legeHochskaliertAb(
        db: db,
        paths: paths,
        importe: importe,
        originalId: original.id,
        jpeg: jpeg,
        faktor: faktor,
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

        final id = await lege(original, vergroessert(original, 4), 4);

        final neu = (await db.assetById(id!))!;
        final vorher = (await db.assetById(original.id))!;
        expect(neu.originalFileName, 'urlaub (4×).jpg');
        expect((neu.widthPx, neu.heightPx), (160, 120));
        expect(neu.fileCreatedAt.isAtSameMomentAs(zeit), isTrue);
        expect((neu.latitude, neu.longitude), (43.7, 7.26));
        expect(neu.locationCity, 'Nizza');
        expect(neu.description, 'Am Strand mit Oma');
        expect(neu.rating, 4);
        expect(neu.faceScanExcluded, isTrue);
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
        originalId: original.id,
        jpeg: jpeg,
        faktor: 2,
        // Der „Server“ importiert in dieselbe Datenbank – so, als hätte
        // der Abgleich die neue Aufnahme schon in die Kopie gebracht.
        hochladen: (datei, angaben) async {
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
      expect(abgeholt, 1);
      final neu = (await db.assetById(id!))!;
      expect(neu.stackId, (await db.assetById(original.id))!.stackId);
      expect(neu.stackId, isNotNull);
    });

    test('lehnt der Server ab, wird nichts eingeordnet', () async {
      final original = await foto();
      await expectLater(
        legeHochskaliertAmServerAb(
          db: db,
          originalId: original.id,
          jpeg: vergroessert(original, 2),
          faktor: 2,
          hochladen: (_, _) async => {
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
        ..hochskaliertAblegen = (originalId, jpeg, faktor) =>
            legeHochskaliertAb(
              db: db,
              paths: paths,
              importe: importe,
              originalId: originalId,
              jpeg: jpeg,
              faktor: faktor,
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

  /// Hält den Lauf an, bis er abgebrochen wird.
  bool halten = false;

  @override
  Restaurierungslauf starteHochskalieren(
    Uint8List quelle, {
    required int faktor,
    int quality = 92,
    void Function(int done, int total)? onProgress,
  }) {
    faktoren.add(faktor);
    if (!begonnen.isCompleted) begonnen.complete();
    final lauf = _Lauf();
    if (!halten) {
      final bild = img.decodeJpg(quelle)!;
      onProgress?.call(1, 1);
      lauf.fertig.complete(
        img.encodeJpg(
          img.copyResize(
            bild,
            width: bild.width * faktor,
            height: bild.height * faktor,
          ),
        ),
      );
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

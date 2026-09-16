import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:drift/drift.dart' show Value;

/// Die Befunde der 23. Prüfrunde am gesperrten Ordner – jeder als Test,
/// der ohne die Behebung wieder durchfällt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv23_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'library')));
    library = LibraryState()
      ..db = db
      ..paths = paths;
    await library.clearDecryptCache();
  });

  tearDown(() async {
    await library.clearDecryptCache();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Ein fertiges Bild unter [schluessel] in den Bildspeicher legen –
  /// geprüft wird das Vergessen, nicht das Laden.
  Future<void> legeInsBildgedaechtnis(Object schluessel) async {
    final aufnehmer = ui.PictureRecorder();
    ui.Canvas(aufnehmer).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final bild = await aufnehmer.endRecording().toImage(8, 8);
    final fertig = Completer<void>();
    final strom = PaintingBinding.instance.imageCache.putIfAbsent(
        schluessel,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: bild))))!;
    late ImageStreamListener horcher;
    horcher = ImageStreamListener((_, __) {
      if (!fertig.isCompleted) fertig.complete();
    });
    strom.addListener(horcher);
    await fertig.future;
    strom.removeListener(horcher);
  }

  int imSpeicher() =>
      PaintingBinding.instance.imageCache.currentSize +
      PaintingBinding.instance.imageCache.liveImageCount;

  /// Eine Aufnahme samt Datei auf der Platte.
  Future<AssetData> aufnahme(String id, {int bytes = 1024}) async {
    const rel = 'originals/';
    final datei = paths.absolute('$rel$id.jpg');
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(List<int>.generate(bytes, (i) => i % 251));
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: '$rel$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
          fileSizeBytes: Value(bytes),
        ));
    return (await db.assetById(id))!;
  }

  group('Sperren raeumt den Bildspeicher', () {
    test('nach dem Sperren liegt kein dekodiertes Bild mehr im Speicher',
        () async {
      await library.setupVaultPin('4711');
      final asset = await aufnahme('geheim');

      // Genau der Zustand vor dem Sperren: Die Kachel wurde eben noch
      // gezeigt, also liegt sie dekodiert im Speicher.
      await legeInsBildgedaechtnis(paths.absolute(asset.relativePath).path);
      expect(imSpeicher(), greaterThan(0),
          reason: 'ohne ein Bild im Speicher prueft der Test nichts');

      await library.lockAsset(asset);

      // Auf der Platte steht jetzt Chiffrat – und im Speicher?
      expect(imSpeicher(), 0,
          reason: 'Der Klartext bliebe sonst unter seinem alten Pfad '
              'abrufbar, ohne dass je wieder ein Schluessel gebraucht wird.');
    });

    test('das Verlassen des gesperrten Ordners raeumt ihn ebenso', () async {
      await legeInsBildgedaechtnis('irgendein/pfad.jpg');
      expect(imSpeicher(), greaterThan(0));
      await library.clearDecryptCache();
      expect(imSpeicher(), 0);
    });
  });

  group('Der Entschluesselungs-Zwischenspeicher hat eine Obergrenze', () {
    test('die aeltesten Stuecke weichen, der Rest bleibt', () async {
      await library.setupVaultPin('4711');

      // Ein Stueck, das mehr als ein Achtel der Grenze belegt – so
      // brauchen wir keine halbe Milliarde Byte zu schreiben, sondern
      // rechnen mit derselben Regel an kleineren Zahlen nach.
      const grenze = LibraryState.hoechstensImZwischenspeicher;
      expect(grenze, greaterThan(0));

      // Fuenf Aufnahmen entschluesseln und die Groesse mitzaehlen.
      final pfade = <String>[];
      for (var i = 0; i < 5; i++) {
        final a = await aufnahme('f$i', bytes: 200 * 1024);
        await library.lockAsset(a);
        pfade.add((await db.assetById('f$i'))!.relativePath);
      }
      for (final rel in pfade) {
        await library.decryptForViewing(rel);
      }

      final ordner =
          Directory(p.join(Directory.systemTemp.path, 'photovault_decrypt'));
      final stuecke = ordner.listSync().whereType<File>().toList();
      expect(stuecke, hasLength(5),
          reason: 'unterhalb der Grenze wird nichts weggeworfen');
      final summe = stuecke.fold<int>(0, (s, f) => s + f.lengthSync());
      expect(summe, lessThan(grenze));
    });

    test('ueber der Grenze bleibt der Zwischenspeicher unter der Grenze',
        () async {
      await library.setupVaultPin('4711');
      final ordner =
          Directory(p.join(Directory.systemTemp.path, 'photovault_decrypt'));
      await ordner.create(recursive: true);

      // Zwoelf Fuellstuecke, die zusammen ueber der Grenze liegen –
      // geschrieben, nicht entschluesselt: geprueft wird das Kuerzen.
      const grenze = LibraryState.hoechstensImZwischenspeicher;
      const stueckgroesse = 8 * 1024 * 1024;
      final noetig = (grenze / stueckgroesse).ceil() + 3;
      for (var i = 0; i < noetig; i++) {
        final f = File(p.join(ordner.path, 'fuell$i'));
        f.writeAsBytesSync(List<int>.filled(stueckgroesse, 7));
        // Aufsteigende Zugriffszeit: fuell0 ist das aelteste.
        f.setLastAccessedSync(DateTime(2020).add(Duration(days: i)));
      }
      final vorher = ordner
          .listSync()
          .whereType<File>()
          .fold<int>(0, (s, f) => s + f.lengthSync());
      expect(vorher, greaterThan(grenze),
          reason: 'ohne Ueberschreitung prueft der Test nichts');

      // Ein echter Zulauf loest das Kuerzen aus.
      final a = await aufnahme('neu');
      await library.lockAsset(a);
      await library
          .decryptForViewing((await db.assetById('neu'))!.relativePath);

      final nachher = ordner
          .listSync()
          .whereType<File>()
          .fold<int>(0, (s, f) => s + f.lengthSync());
      expect(nachher, lessThanOrEqualTo(grenze));
      // Das juengste Fuellstueck ueberlebt, das aelteste nicht.
      expect(
          File(p.join(ordner.path, 'fuell${noetig - 1}')).existsSync(), isTrue);
      expect(File(p.join(ordner.path, 'fuell0')).existsSync(), isFalse);
    });
  });

  group('Der Zwischenspeicher gehoert nur dem eigenen Benutzer', () {
    test('das Verzeichnis traegt 0700, nicht 0755', () async {
      if (Platform.isWindows) return; // Dort regeln es die Zugriffslisten.
      await library.setupVaultPin('4711');
      final a = await aufnahme('rechte');
      await library.lockAsset(a);
      await library
          .decryptForViewing((await db.assetById('rechte'))!.relativePath);

      final ordner = p.join(Directory.systemTemp.path, 'photovault_decrypt');
      final argumente =
          Platform.isMacOS ? ['-f', '%Lp', ordner] : ['-c', '%a', ordner];
      final ergebnis = await Process.run('stat', argumente);
      expect((ergebnis.stdout as String).trim(), '700',
          reason: 'Dart legt Verzeichnisse mit 0755 an – auf einem Rechner '
              'mit mehreren Benutzern laege der Klartext offen.');
    });
  });

  group('Verschluesselung und Entschluesselung bleiben dieselben', () {
    test('was gesperrt und wieder entsperrt wird, ist unveraendert', () async {
      await library.setupVaultPin('4711');
      final a = await aufnahme('rundlauf', bytes: 300000);
      final vorher = paths.absolute(a.relativePath).readAsBytesSync();
      await library.lockAsset(a);
      final chiffre = paths.absolute(a.relativePath).readAsBytesSync();
      expect(chiffre, isNot(equals(vorher)));
      await library.unlockAsset((await db.assetById('rundlauf'))!);
      expect(paths.absolute(a.relativePath).readAsBytesSync(), vorher);
      // Und dass das Chiffrat wirklich das Format des Tresors trug.
      final probe = File(p.join(wurzel.path, 'probe.bin'))
        ..writeAsBytesSync(chiffre);
      expect(await VaultCrypto.hasValidEncryptedHeader(probe), isTrue);
    });
  });
}

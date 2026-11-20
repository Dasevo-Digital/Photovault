import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/arbeitsvorschauen.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late Directory temp;
  late StoragePaths paths;
  late AppDatabase db;
  late ImportService importe;
  late AssetData a;
  late Arbeitsvorschauen dienst;
  late List<String> renderQuellen;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_arbeitsvorschau_test_');
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    db = AppDatabase(NativeDatabase.memory());
    importe = ImportService(db, paths);
    final jpeg = img.encodeJpg(
      img.Image(width: 400, height: 300)..clear(img.ColorRgb8(80, 100, 120)),
    );
    final f = await File(p.join(temp.path, 'foto.jpg')).writeAsBytes(jpeg);
    final r = await importe.importFile(f.path);
    a = (await db.assetById(r.assetId!))!;
    renderQuellen = [];
    dienst = Arbeitsvorschauen(
      db,
      paths,
      renderer: (f, w, m, k) async {
        renderQuellen.add(f.path);
        var bild = img.decodeJpg(await f.readAsBytes())!;
        if (k == 2048) bild = img.copyResize(bild, width: 40);
        return schneideEntwicklung(
          Uint8List.fromList(img.encodeJpg(bild)),
          w.zuschnitt,
        );
      },
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  DevelopSettingsData werte(double ev) => DevelopSettingsData(
    assetId: a.id,
    exposure: ev,
    temperature: null,
    tint: null,
    contrast: 0,
    shadows: 0,
    highlights: 0,
    sharpness: 0,
    noiseReduction: 0,
    lensCorrectionEnabled: true,
    clarity: 0,
    vignette: 0,
    lutPath: null,
    lutStrength: 1,
    toneCurveJson: null,
    colorMixerJson: null,
    updatedAt: DateTime.now(),
  );
  Future<void> entwurf(double ev) async {
    final arbeit = await dienst.oeffne(a.id);
    try {
      await arbeit.db
          .into(arbeit.db.developSettings)
          .insertOnConflictUpdate(werte(ev));
    } finally {
      await arbeit.schliesse();
    }
    await dienst.merkeEntwurf(a.id);
  }

  test(
    'ohne erreichbares Original bearbeiten und später tatsächlich am Original rendern',
    () async {
      await dienst.vorbereiten(a);
      final original = paths.absolute(a.relativePath);
      final vorher = await original.readAsBytes();
      final weg = await original.rename(p.join(temp.path, 'abgezogen.jpg'));
      await entwurf(1);
      expect(await db.developSettingsForAsset(a.id), isNull);
      expect((await dienst.liste()).single.entwurf, isTrue);
      await expectLater(
        dienst.anwenden(a.id, 'Offline'),
        throwsA(isA<FileSystemException>()),
      );
      await weg.rename(original.path);
      await dienst.anwenden(a.id, 'Offline');
      final aktuell = (await db.assetById(a.id))!;
      final bild = img.decodeJpg(
        await paths.absolute(aktuell.developedRelativePath!).readAsBytes(),
      )!;
      expect(
        bild.width,
        400,
        reason: 'die 40-Pixel-Arbeitsvorschau ist keine endgültige Ausgabe',
      );
      expect(renderQuellen.last, original.path);
      expect(await original.readAsBytes(), vorher);
      expect((await db.developSettingsForAsset(a.id))!.exposure, 1);
    },
  );

  test(
    'konkurrierende Entwicklung bleibt erhalten; Entwurf nur ausdrücklich als neue Variante',
    () async {
      await dienst.vorbereiten(a);
      await entwurf(1);
      await db.into(db.developSettings).insert(werte(-1));
      await expectLater(
        dienst.anwenden(a.id, 'Offline'),
        throwsA(isA<OfflineKonflikt>()),
      );
      expect((await db.developSettingsForAsset(a.id))!.exposure, -1);
      expect(await db.variantenFuer(a.id), isEmpty);
      expect((await dienst.liste()).single.entwurf, isTrue);
      await dienst.anwenden(a.id, 'Offline', nurNeueVariante: true);
      expect((await db.developSettingsForAsset(a.id))!.exposure, -1);
      expect((await db.variantenFuer(a.id)).single.name, 'Offline');
    },
  );

  test(
    'geänderte Originalbytes werden auch bei zurückgesetztem Zeitstempel abgewiesen',
    () async {
      await dienst.vorbereiten(a);
      await entwurf(1);
      final f = paths.absolute(a.relativePath);
      final zeit = (await f.stat()).modified;
      final bytes = await f.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await f.writeAsBytes(bytes);
      await f.setLastModified(zeit);
      await expectLater(
        dienst.anwenden(a.id, 'Offline', nurNeueVariante: true),
        throwsA(
          isA<OfflineKonflikt>().having(
            (e) => e.originalGeaendert,
            'Original verändert',
            isTrue,
          ),
        ),
      );
      expect(await db.variantenFuer(a.id), isEmpty);
      expect((await dienst.liste()).single.entwurf, isTrue);
    },
  );

  test(
    'beschädigte Arbeitsvorschau wird nicht geöffnet und ein Entwurf nicht ersetzt',
    () async {
      await dienst.vorbereiten(a);
      await entwurf(1);
      await dienst.vorbereiten(a);
      final arbeits = await dienst.oeffne(a.id);
      expect((await arbeits.db.developSettingsForAsset(a.id))!.exposure, 1);
      final file = arbeits.paths.absolute('originals/basis.jpg');
      await arbeits.schliesse();
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(dienst.oeffne(a.id), throwsFormatException);
      expect(paths.offeneArbeitsvorschauen, isEmpty);
    },
  );

  test('Vorbereitungsgrenze zählt den Arbeitskatalog mit', () async {
    final original = await paths.absolute(a.relativePath).readAsBytes();
    final knapp = Arbeitsvorschauen(
      db,
      paths,
      hoechstensBytes: original.length + 128,
      renderer: (f, w, m, k) => f.readAsBytes(),
    );
    await expectLater(knapp.vorbereiten(a), throwsFormatException);
    expect(await dienst.liste(), isEmpty);
    expect(await paths.absolute(a.relativePath).readAsBytes(), original);
  });

  test('Speichergrenze lässt Original und Katalog unverändert', () async {
    final begrenzt = Arbeitsvorschauen(
      db,
      paths,
      hoechstensBytes: 1,
      renderer: (f, w, m, k) => f.readAsBytes(),
    );
    await expectLater(begrenzt.vorbereiten(a), throwsFormatException);
    expect(await dienst.liste(), isEmpty);
    expect(
      (await db.assetById(a.id))!.checksum,
      sha256
          .convert(await paths.absolute(a.relativePath).readAsBytes())
          .toString(),
    );
  });

  test(
    'offene Arbeitsbibliothek verhindert Löschen und Sperren; geschlossen wird vollständig geschützt',
    () async {
      await dienst.vorbereiten(a);
      await entwurf(1);
      final arbeit = await dienst.oeffne(a.id);
      await expectLater(dienst.entfernen(a.id), throwsStateError);
      final library = LibraryState()
        ..db = db
        ..paths = paths
        ..importService = importe
        ..backupService = BackupService(db, paths)
        ..klartextOrdnerFuerTests = Directory(p.join(temp.path, 'klartext'));
      await library.setupVaultPin('1234');
      await expectLater(library.lockAsset(a), throwsStateError);
      expect((await db.assetById(a.id))!.isLocked, isFalse);
      await arbeit.schliesse();
      final json = File(
        p.join(paths.root.path, 'arbeitsvorschauen', a.id, 'stand.json'),
      );
      await library.lockAsset(a);
      expect(await VaultCrypto.hasValidEncryptedHeader(json), isTrue);
      expect(await dienst.liste(), isEmpty);
      await library.unlockAsset((await db.assetById(a.id))!);
      final wieder = await dienst.oeffne(a.id);
      expect((await wieder.db.developSettingsForAsset(a.id))!.exposure, 1);
      await wieder.schliesse();
    },
  );
}

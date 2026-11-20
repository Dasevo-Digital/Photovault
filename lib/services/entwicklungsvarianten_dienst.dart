import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:kern/db/database.dart';
import 'package:kern/services/entwicklungsvariante.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:uuid/uuid.dart';

class EntwicklungsvariantenDienst {
  const EntwicklungsvariantenDienst(this.db, this.paths);
  final AppDatabase db;
  final StoragePaths paths;

  Future<String> speichern({
    required AssetData asset,
    required String name,
    required DevelopSettingsData einstellungen,
    required List<DevelopMaskData> masken,
    required Uint8List jpeg,
    StoragePaths? quellPaths,
    String? aktivierenBeiStand,
  }) async {
    if (asset.isLocked ||
        asset.isTrashed ||
        name.trim().isEmpty ||
        name.trim().length > 80 ||
        masken.length > 100 ||
        jpeg.length > 32 * 1024 * 1024) {
      throw const FormatException('pv_variante_format');
    }
    final id = const Uuid().v4();
    final geschrieben = <String>[];
    final dateien = <String, String>{};
    Future<String> einfrieren(
      String alt,
      String ordner,
      String endung,
      int limit,
    ) async {
      final f = await (quellPaths ?? paths).bereit(alt);
      if (await f.length() > limit) {
        throw const FormatException('pv_variante_dateiumfang');
      }
      final hash = (await sha256.bind(f.openRead()).first).toString();
      // Ein Tresorwechsel darf niemals die Datei einer anderen Aufnahme
      // verschlüsseln, auch wenn beide Masken oder Farbtabellen gleich sind.
      final eigentuemer = sha256
          .convert(utf8.encode(asset.id))
          .toString()
          .substring(0, 16);
      final neu = '$ordner/var-$eigentuemer-$hash.$endung';
      final ziel = paths.absolute(neu);
      if (!await ziel.exists()) {
        final teil = File('${ziel.path}.$id.part');
        try {
          await ziel.parent.create(recursive: true);
          await f.copy(teil.path);
          if ((await sha256.bind(teil.openRead()).first).toString() != hash) {
            throw const FormatException('pv_variante_datei_geaendert');
          }
          await teil.rename(ziel.path);
          geschrieben.add(neu);
        } finally {
          if (await teil.exists()) await teil.delete();
        }
      }
      if ((await sha256.bind(ziel.openRead()).first).toString() != hash) {
        throw const FormatException('pv_variante_datei_geaendert');
      }
      dateien[neu] = hash;
      return neu;
    }

    try {
      final eingefroren = <DevelopMaskData>[];
      final random = Random.secure();
      for (final m in masken) {
        if (m.assetId != asset.id) {
          throw const FormatException('pv_variante_maske');
        }
        final pfad = await einfrieren(
          m.maskRelativePath,
          'masks',
          'png',
          16 * 1024 * 1024,
        );
        final kennung =
            random.nextInt(1 << 26) * (1 << 26) + random.nextInt(1 << 26);
        eingefroren.add(m.copyWith(id: kennung, maskRelativePath: pfad));
      }
      final lut = einstellungen.lutPath == null
          ? null
          : await einfrieren(
              einstellungen.lutPath!,
              'luts',
              'cube',
              4 * 1024 * 1024,
            );
      final vorschau = 'developed/var-$id.jpg';
      final bild = paths.absolute(vorschau);
      await bild.parent.create(recursive: true);
      await bild.writeAsBytes(jpeg, flush: true);
      geschrieben.add(vorschau);
      dateien[vorschau] = sha256.convert(jpeg).toString();
      final stand = Entwicklungsstand(
        asset.checksum,
        einstellungen.copyWith(assetId: asset.id, lutPath: Value(lut)),
        eingefroren,
        dateien,
      );
      Entwicklungsstand.decode(stand.encode());
      for (final pfad in dateien.keys) {
        await paths.abgelegt(pfad);
      }
      await db.fuehreAus(
        EntwicklungsvarianteSpeichern(
          DevelopVariantData(
            id: id,
            assetId: asset.id,
            name: name.trim(),
            stateJson: stand.encode(),
            previewRelativePath: vorschau,
            updatedAt: DateTime.now(),
          ),
          aktivierenBeiStand: aktivierenBeiStand,
        ),
      );
      return id;
    } catch (_) {
      for (final pfad in geschrieben) {
        if (!await db.varianteVerwendetDatei(pfad)) {
          final f = paths.absolute(pfad);
          if (await f.exists()) await f.delete();
        }
      }
      rethrow;
    }
  }

  Future<void> aktivieren(
    DevelopVariantData variante, {
    String? erwarteterStand,
  }) async {
    final stand = Entwicklungsstand.decode(variante.stateJson);
    for (final e in stand.dateien.entries) {
      final f = await paths.bereit(e.key);
      if ((await sha256.bind(f.openRead()).first).toString() != e.value) {
        throw const FormatException('pv_variante_datei_geaendert');
      }
    }
    await db.fuehreAus(
      EntwicklungsvarianteAktivieren(
        variante.assetId,
        variante.id,
        erwarteterStand: erwarteterStand,
      ),
    );
  }

  Future<void> umbenennen(DevelopVariantData variante, String name) =>
      db.fuehreAus(
        EntwicklungsvarianteSpeichern(
          variante.copyWith(name: name, updatedAt: DateTime.now()),
        ),
      );

  /// Dateien bleiben zunächst liegen: ein aktives Ergebnis, eine andere
  /// Variante oder ein laufender Sicherungsabzug kann sie noch benötigen.
  Future<void> entfernen(DevelopVariantData variante) => db.fuehreAus(
    EntwicklungsvarianteEntfernen(variante.assetId, variante.id),
  );
}

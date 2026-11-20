import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'entwicklungsvariante.dart';
import 'storage_paths.dart';
import 'vault_crypto.dart';
import 'backup_dateinamen.dart';

class VariantenSicherungsstand {
  const VariantenSicherungsstand({
    this.geschriebenBytes = 0,
    this.offen = 0,
    this.offenBytes = 0,
  });
  final int geschriebenBytes, offen, offenBytes;
}

/// Unveränderliche Variantendateien liegen nach Inhalt adressiert neben
/// den Originalen. Ältere Generationen benutzen dieselben Objekte weiter.
class VariantenSicherung {
  static Future<VariantenSicherungsstand> ausSchnappschuss(
    File snapshot,
    StoragePaths paths,
    Directory ziel,
    SecretKey key, {
    int maxBytes = 0,
  }) async {
    final quelle = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
    final dateien = <String, String>{};
    try {
      if (quelle
          .select("SELECT 1 FROM sqlite_master WHERE name='develop_variants'")
          .isEmpty) {
        return const VariantenSicherungsstand();
      }
      var anzahl = 0;
      for (final row in quelle.select(
        'SELECT state_json FROM develop_variants LIMIT 200001',
      )) {
        if (++anzahl > 200000) {
          throw const FormatException('pv_varianten_sicherung_umfang');
        }
        _ergaenze(
          dateien,
          Entwicklungsstand.decode(row['state_json'] as String).dateien,
        );
      }
    } finally {
      quelle.close();
    }
    return _sichereDateien(dateien, paths, ziel, key, maxBytes);
  }

  static Future<VariantenSicherungsstand> ohneSchnappschuss(
    AppDatabase db,
    StoragePaths paths,
    Directory ziel, {
    int maxBytes = 0,
  }) async {
    final index = File(p.join(ziel.path, 'variantenstand.jsonl'));
    final teil = File('${index.path}.${const Uuid().v4()}.part');
    final dateien = <String, String>{};
    RandomAccessFile? aus;
    var zeilen = 0;
    try {
      for (var offset = 0; ; offset += 100) {
        final werte =
            await (db.select(db.developVariants)
                  ..orderBy([(t) => OrderingTerm.asc(t.id)])
                  ..limit(100, offset: offset))
                .get();
        for (final v in werte) {
          final a = await db.assetById(v.assetId);
          if (a == null || a.isLocked || a.isTrashed) continue;
          if (++zeilen > 200000) {
            throw const FormatException('pv_varianten_sicherung_umfang');
          }
          final stand = Entwicklungsstand.decode(v.stateJson);
          _ergaenze(dateien, stand.dateien);
          aus ??= await teil.open(mode: FileMode.write);
          await aus.writeString(
            '${jsonEncode({'fassung': 1, 'sha256': a.checksum, 'variante': v.toJson()})}\n',
          );
        }
        if (werte.length < 100) break;
      }
      if (aus != null) {
        await aus.flush();
        await aus.close();
        aus = null;
      }
      final stand = await _sichereDateien(dateien, paths, ziel, null, maxBytes);
      if (await teil.exists()) {
        await teil.rename(index.path);
      } else if (await index.exists()) {
        await index.writeAsString('', flush: true);
      }
      return stand;
    } finally {
      await aus?.close();
      if (await teil.exists()) await teil.delete();
    }
  }

  static void _ergaenze(Map<String, String> ziel, Map<String, String> neu) {
    for (final e in neu.entries) {
      if (ziel.containsKey(e.key) && ziel[e.key] != e.value) {
        throw const FormatException('pv_variante_datei_geaendert');
      }
      ziel[e.key] = e.value;
    }
    if (ziel.length > 200000) {
      throw const FormatException('pv_varianten_sicherung_umfang');
    }
  }

  static Future<String> _name(String hash, SecretKey? key) async =>
      key == null ? hash : VerschluesselteNamen.fuerPruefsumme(hash, key);
  static Future<void> _pruefe(File f, String hash, SecretKey? key) async {
    if (await FileSystemEntity.type(f.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await f.length() > 66 * 1024 * 1024) {
      throw const FormatException('pv_variante_dateiumfang');
    }
    if (key != null) {
      await VaultCrypto.pruefeDatei(f, key, erwartetePruefsumme: hash);
    } else if ((await sha256.bind(f.openRead()).first).toString() != hash) {
      throw const FormatException('pv_variante_datei_geaendert');
    }
  }

  static Future<VariantenSicherungsstand> _sichereDateien(
    Map<String, String> dateien,
    StoragePaths paths,
    Directory ziel,
    SecretKey? key,
    int maxBytes,
  ) async {
    var geschrieben = 0, offen = 0, offenBytes = 0;
    final geprueft = <String>{};
    for (final e in dateien.entries) {
      if (!geprueft.add(e.value)) continue;
      final target = File(
        p.join(ziel.path, 'varianten', await _name(e.value, key)),
      );
      await _pruefeEltern(ziel, target);
      if (await target.exists()) {
        try {
          await _pruefe(target, e.value, key);
          continue;
        } on Object {
          /* Eine beschädigte Kopie wird ersetzt. */
        }
      }
      final quelle = await paths.bereit(e.key);
      final bytes = await quelle.length();
      if (bytes > 64 * 1024 * 1024) {
        throw const FormatException('pv_variante_dateiumfang');
      }
      if (maxBytes > 0 && geschrieben >= maxBytes) {
        offen++;
        offenBytes += bytes;
        continue;
      }
      await target.parent.create(recursive: true);
      final teil = File('${target.path}.${const Uuid().v4()}.part');
      try {
        if (key != null) {
          await VaultCrypto.encryptFile(quelle, teil, key);
        } else {
          await quelle.copy(teil.path);
        }
        await _pruefe(teil, e.value, key);
        await teil.rename(target.path);
        geschrieben += bytes;
      } finally {
        if (await teil.exists()) await teil.delete();
      }
    }
    return VariantenSicherungsstand(
      geschriebenBytes: geschrieben,
      offen: offen,
      offenBytes: offenBytes,
    );
  }

  static Future<void> stelleWiederHer(
    AppDatabase db,
    StoragePaths paths,
    Directory wurzel,
    SecretKey? key, {
    File? schnappschuss,
    bool ausSnapshot = true,
    Set<String>? auswahl,
  }) async {
    final uebernommen = <String>{};
    if (ausSnapshot) {
      if (schnappschuss == null) {
        throw const FormatException('pv_variante_schnappschuss');
      }
      final quelle = sqlite3.open(schnappschuss.path, mode: OpenMode.readOnly);
      try {
        if (quelle
            .select("SELECT 1 FROM sqlite_master WHERE name='develop_variants'")
            .isEmpty) {
          return;
        }
        for (final r in quelle.select(
          'SELECT v.id, v.state_json, a.checksum FROM develop_variants v JOIN assets a ON a.id=v.asset_id WHERE a.is_locked=0 LIMIT 200001',
        )) {
          if (uebernommen.length >= 200000) {
            throw const FormatException('pv_varianten_sicherung_umfang');
          }
          final hash = r['checksum'] as String;
          if (auswahl != null && !auswahl.contains(hash)) continue;
          final a =
              await (db.select(db.assets)..where(
                    (t) => t.checksum.equals(hash) & t.isLocked.equals(false),
                  ))
                  .getSingleOrNull();
          if (a == null) continue;
          final v =
              await (db.select(db.developVariants)..where(
                    (t) =>
                        t.id.equals(r['id'] as String) & t.assetId.equals(a.id),
                  ))
                  .getSingleOrNull();
          if (v == null) continue;
          if (v.stateJson != r['state_json']) {
            throw const FormatException(
              'pv_variante_wiederherstellungskonflikt',
            );
          }
          uebernommen.add(v.id);
        }
      } finally {
        quelle.close();
      }
    }
    if (!ausSnapshot) {
      final index = File(p.join(wurzel.path, 'variantenstand.jsonl'));
      if (!await index.exists()) return;
      await _pruefeEltern(wurzel, index);
      if (await FileSystemEntity.type(index.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const FormatException('pv_variante_pfad');
      }
      if (await index.length() > 256 * 1024 * 1024) {
        throw const FormatException('pv_varianten_sicherung_umfang');
      }
      var n = 0;
      await for (final text
          in index
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (++n > 200000 || text.length > 2 * 1024 * 1024) {
          throw const FormatException('pv_varianten_sicherung_umfang');
        }
        final j = jsonDecode(text) as Map;
        if (j['fassung'] != 1) {
          throw const FormatException('pv_variante_format');
        }
        final hash = j['sha256'] as String;
        if (auswahl != null && !auswahl.contains(hash)) continue;
        final a =
            await (db.select(db.assets)..where(
                  (t) => t.checksum.equals(hash) & t.isLocked.equals(false),
                ))
                .getSingleOrNull();
        if (a == null) continue;
        final v = DevelopVariantData.fromJson(
          (j['variante'] as Map).cast<String, dynamic>(),
        ).copyWith(assetId: a.id);
        await db.fuehreAus(EntwicklungsvarianteSpeichern(v));
        uebernommen.add(v.id);
      }
    }
    final dateien = <String, String>{};
    for (var offset = 0; ; offset += 100) {
      final werte =
          await (db.select(db.developVariants)
                ..orderBy([(t) => OrderingTerm.asc(t.id)])
                ..limit(100, offset: offset))
              .get();
      for (final v in werte) {
        if (!uebernommen.contains(v.id)) continue;
        final a = await db.assetById(v.assetId);
        if (a == null ||
            a.isLocked ||
            (auswahl != null && !auswahl.contains(a.checksum))) {
          continue;
        }
        _ergaenze(dateien, Entwicklungsstand.decode(v.stateJson).dateien);
      }
      if (werte.length < 100) break;
    }
    for (final e in dateien.entries) {
      final ziel = paths.absolute(e.key);
      await _pruefeEltern(paths.root, ziel);
      if (await ziel.exists()) {
        await _pruefe(ziel, e.value, null);
        continue;
      }
      final quelle = File(
        p.join(wurzel.path, 'varianten', await _name(e.value, key)),
      );
      await _pruefeEltern(wurzel, quelle);
      if (await FileSystemEntity.type(quelle.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await quelle.length() > 66 * 1024 * 1024) {
        throw const FormatException('pv_variante_pfad');
      }
      final teil = File('${ziel.path}.${const Uuid().v4()}.part');
      await ziel.parent.create(recursive: true);
      final basis = await paths.root.resolveSymbolicLinks();
      if (!p.isWithin(basis, await ziel.parent.resolveSymbolicLinks())) {
        throw const FormatException('pv_variante_pfad');
      }
      try {
        if (key != null) {
          await VaultCrypto.decryptFile(quelle, teil, key);
        } else {
          await quelle.copy(teil.path);
        }
        await _pruefe(teil, e.value, null);
        await teil.rename(ziel.path);
      } finally {
        if (await teil.exists()) await teil.delete();
      }
    }
  }

  static Future<void> _pruefeEltern(Directory wurzel, File datei) async {
    final basis = await wurzel.resolveSymbolicLinks();
    var eltern = datei.parent;
    while (!await eltern.exists()) {
      if (p.equals(eltern.path, eltern.parent.path)) {
        throw const FormatException('pv_variante_pfad');
      }
      eltern = eltern.parent;
    }
    final real = await eltern.resolveSymbolicLinks();
    if (!p.equals(basis, real) && !p.isWithin(basis, real)) {
      throw const FormatException('pv_variante_pfad');
    }
  }
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'platform/folder_access.dart';
import 'speicherkarte.dart';
import 'importquittungen.dart' show Kopienbefund;
import 'platform/speicherlaufwerk.dart';

enum SpeicherschutzGrund {
  ziel,
  datentraeger,
  bestaetigung,
  konflikt,
  kopieFehlt,
  referenzen,
}

class SpeicherschutzFehler implements Exception {
  const SpeicherschutzFehler(this.grund);
  final SpeicherschutzGrund grund;
}

class Freigabekandidat {
  const Freigabekandidat._(
    this.id,
    this.relativ,
    this.hash,
    this.bytes,
    this.originalkopie,
  );
  final String id, relativ, hash, originalkopie;
  final int bytes;
}

class Speicherschutzplan {
  const Speicherschutzplan._(
    this.originalort,
    this.sicherungsort,
    this.sicherung,
    this.kandidaten,
    this.geprueft,
    this.am,
    this.laufwerke,
  );
  final PickedFolder originalort, sicherungsort;
  final BackupAuswahl sicherung;
  final List<Freigabekandidat> kandidaten;
  final int geprueft;
  final DateTime am;
  final List<String> laufwerke;
  int get bytes => kandidaten.fold(0, (s, k) => s + k.bytes);
}

/// Vor dem Entfernen bleibt die Aufnahme über einen dauerhaften externen
/// Originalverweis erreichbar. Eine zweite unabhängig bestätigte Kopie ist
/// zusätzlich erforderlich; ein alter Prüfmerker genügt nicht.
class Speicherschutz {
  Speicherschutz(
    this.db,
    this.paths, {
    FolderAccess? zugriff,
    Future<Speicherlaufwerk?> Function(String)? laufwerk,
    Future<void> Function(File)? entfernen,
    required this.nachweise,
  }) : zugriff = zugriff ?? FolderAccess.forCurrentPlatform(),
       laufwerk = laufwerk ?? Laufwerksauskunft.fuer,
       entfernen =
           entfernen ??
           ((f) async {
             await f.delete();
           });
  final AppDatabase db;
  final SpeicherkarteDienst nachweise;
  final StoragePaths paths;
  final FolderAccess zugriff;
  final Future<Speicherlaufwerk?> Function(String) laufwerk;
  final Future<void> Function(File) entfernen;

  Future<String> _ziel(PickedFolder ort) async {
    final pfad = ort.token.isEmpty
        ? ort.path
        : await zugriff.resolveRoot(path: ort.path, token: ort.token);
    if (pfad == null || !await Directory(pfad).exists()) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.ziel);
    }
    final real = await Directory(pfad).resolveSymbolicLinks();
    final root = await paths.root.resolveSymbolicLinks();
    if (p.equals(real, root) ||
        p.isWithin(root, real) ||
        p.isWithin(real, root)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.ziel);
    }
    return real;
  }

  Future<List<String>> _laufwerke(String original, String sicherung) async {
    final root = await paths.root.resolveSymbolicLinks();
    final ids = <String>[];
    for (final pfad in [root, original, sicherung]) {
      final info = await laufwerk(pfad);
      if (info == null || info.id.isEmpty) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.datentraeger);
      }
      ids.add(info.id);
    }
    if (ids.toSet().length != 3) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.datentraeger);
    }
    return ids;
  }

  Future<String> _hash(File f, bool Function()? abgebrochen) async =>
      (await sha256
              .bind(
                f
                    .openRead()
                    .map((teil) {
                      if (abgebrochen?.call() == true) {
                        throw const SpeicherschutzFehler(
                          SpeicherschutzGrund.konflikt,
                        );
                      }
                      return teil;
                    })
                    .timeout(const Duration(seconds: 30)),
              )
              .first)
          .toString();

  Future<List<AssetData>> _aufnahmen() async {
    if (paths.beschaffe != null || paths.referenzen == null) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.referenzen);
    }
    final aus = <AssetData>[];
    var cursor = '';
    while (true) {
      final teil =
          await (db.select(db.assets)
                ..where(
                  (a) =>
                      a.isLocked.equals(false) &
                      a.isTrashed.equals(false) &
                      a.id.isBiggerThanValue(cursor),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.id)])
                ..limit(500))
              .get();
      aus.addAll(teil.where((a) => !paths.istReferenziert(a.relativePath)));
      if (aus.length > 200000) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
      }
      if (teil.length < 500) break;
      cursor = teil.last.id;
    }
    return aus;
  }

  Future<File> _quelle(AssetData a) async {
    final f = paths.absolute(a.relativePath);
    if (await FileSystemEntity.type(f.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(
          await paths.root.resolveSymbolicLinks(),
          await f.resolveSymbolicLinks(),
        )) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
    return f;
  }

  String _dateiname(AssetData a) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(a.checksum)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
    final ext = p.extension(a.originalFileName).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(ext)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
    return '${a.checksum}$ext';
  }

  Future<void> _pruefeKopie(String root, File kopie) async {
    if (await FileSystemEntity.type(kopie.path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(root, await kopie.resolveSymbolicLinks())) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
  }

  Future<void> pruefeSicherungsziel(PickedFolder ziel) async {
    final root = await _ziel(ziel);
    final hier = await laufwerk(await paths.root.resolveSymbolicLinks());
    final dort = await laufwerk(root);
    if (hier == null || dort == null || hier.id == dort.id) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.datentraeger);
    }
  }

  Future<int> originalkopienAnlegen(
    PickedFolder ziel, {
    bool Function()? abgebrochen,
    void Function(int, int)? fortschritt,
  }) async {
    final root = await _ziel(ziel);
    final hier = await laufwerk(await paths.root.resolveSymbolicLinks());
    final dort = await laufwerk(root);
    if (hier == null || dort == null || hier.id == dort.id) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.datentraeger);
    }
    final alle = await _aufnahmen();
    var fertig = 0;
    for (final a in alle) {
      if (abgebrochen?.call() == true) break;
      final quelle = await _quelle(a);
      if (await _hash(quelle, abgebrochen) != a.checksum) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
      }
      final datei = File(p.join(root, _dateiname(a)));
      if (await FileSystemEntity.type(datei.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        await _pruefeKopie(root, datei);
        if (await _hash(datei, abgebrochen) != a.checksum) {
          throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
        }
      } else {
        final teil = File(p.join(root, '.${const Uuid().v4()}.part'));
        try {
          await quelle.copy(teil.path);
          if (await _hash(teil, abgebrochen) != a.checksum) {
            throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
          }
          if (await FileSystemEntity.type(datei.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            await _pruefeKopie(root, datei);
            if (await _hash(datei, abgebrochen) != a.checksum) {
              throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
            }
          } else {
            await teil.rename(datei.path);
          }
        } finally {
          if (await teil.exists()) await teil.delete();
        }
      }
      fertig++;
      fortschritt?.call(fertig, alle.length);
    }
    return fertig;
  }

  Future<Speicherschutzplan> pruefe(
    PickedFolder originalort,
    PickedFolder sicherungsort,
    BackupAuswahl sicherung, {
    required bool unabhaengigkeitBestaetigt,
    bool Function()? abgebrochen,
    void Function(int, int)? fortschritt,
  }) async {
    if (!unabhaengigkeitBestaetigt) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.bestaetigung);
    }
    final a = await _ziel(originalort), b = await _ziel(sicherungsort);
    if (!p.equals(sicherung.wurzel, b)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.ziel);
    }
    final ids = await _laufwerke(a, b);
    final alle = await _aufnahmen(), aus = <Freigabekandidat>[];
    final pruefsummen = alle.map((a) => a.checksum).toSet();
    final nachweis = await nachweise.pruefe(
      sicherung,
      sicherungsort,
      pruefsummen,
      abgebrochen: abgebrochen,
      fortschritt: (n, _) =>
          fortschritt?.call(n, pruefsummen.length + alle.length),
    );
    if (!nachweis.vollstaendig) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
    var fertig = 0;
    for (final foto in alle) {
      if (abgebrochen?.call() == true) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
      }
      final quelle = await _quelle(foto);
      final kopie = File(p.join(a, _dateiname(foto)));
      if (await kopie.exists()) await _pruefeKopie(a, kopie);
      if (await kopie.exists() &&
          await _hash(kopie, abgebrochen) == foto.checksum &&
          await _hash(quelle, abgebrochen) == foto.checksum &&
          nachweis.befunde[foto.checksum] == Kopienbefund.bestaetigt) {
        final real = await kopie.resolveSymbolicLinks();
        if (!p.isWithin(a, real) ||
            await FileSystemEntity.type(kopie.path, followLinks: false) !=
                FileSystemEntityType.file) {
          throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
        }
        aus.add(
          Freigabekandidat._(
            foto.id,
            foto.relativePath,
            foto.checksum,
            await quelle.length(),
            real,
          ),
        );
      }
      fertig++;
      fortschritt?.call(
        fertig + pruefsummen.length,
        alle.length + pruefsummen.length,
      );
    }
    return Speicherschutzplan._(
      originalort,
      sicherungsort,
      sicherung,
      List.unmodifiable(aus),
      fertig,
      DateTime.now(),
      ids,
    );
  }

  Future<({int dateien, int bytes})> freigeben(
    Speicherschutzplan plan, {
    required bool bestaetigt,
    bool Function()? abgebrochen,
    void Function(int, int)? fortschritt,
  }) async {
    if (!bestaetigt) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.bestaetigung);
    }
    final a = await _ziel(plan.originalort),
        b = await _ziel(plan.sicherungsort);
    if (!p.equals(plan.sicherung.wurzel, b)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.ziel);
    }
    final ids = await _laufwerke(a, b);
    if (ids.join('|') != plan.laufwerke.join('|') ||
        DateTime.now().difference(plan.am) > const Duration(minutes: 30)) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
    }
    final refs = paths.referenzen;
    if (paths.beschaffe != null || refs == null) {
      throw const SpeicherschutzFehler(SpeicherschutzGrund.referenzen);
    }
    var dateien = 0, bytes = 0, erledigt = 0;
    final ordner = await refs.ordnerHinzufuegen(Directory(a));
    await refs.merkeZugriff(ordner, plan.originalort.token);
    for (final k in plan.kandidaten) {
      if (abgebrochen?.call() == true) break;
      final frisch = await db.assetById(k.id);
      if (frisch == null ||
          frisch.isLocked ||
          frisch.isTrashed ||
          frisch.relativePath != k.relativ ||
          frisch.checksum != k.hash) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
      }
      final quelle = await _quelle(frisch), kopie = File(k.originalkopie);
      if (!p.isWithin(a, await kopie.resolveSymbolicLinks()) ||
          await _hash(kopie, abgebrochen) != k.hash ||
          !await plan.sicherung.pruefeOriginal(k.hash) ||
          await _hash(quelle, abgebrochen) != k.hash) {
        throw const SpeicherschutzFehler(SpeicherschutzGrund.kopieFehlt);
      }
      final verweis = await refs.aufnehmen(ordner, kopie);
      var umgestellt = false;
      try {
        if (refs.dateien[verweis]!.sha256 != k.hash) {
          throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
        }
        await db.transaction(() async {
          final f = await db.assetById(k.id);
          if (f == null ||
              f.isLocked ||
              f.isTrashed ||
              f.relativePath != k.relativ ||
              f.checksum != k.hash) {
            throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
          }
          await (db.update(db.assets)..where((t) => t.id.equals(k.id))).write(
            AssetsCompanion(relativePath: Value(verweis)),
          );
        });
        umgestellt = true;
        if (await _hash(quelle, abgebrochen) != k.hash) {
          throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
        }
        if ((await _laufwerke(a, b)).join('|') != plan.laufwerke.join('|') ||
            (await db.assetById(k.id))?.relativePath != verweis) {
          throw const SpeicherschutzFehler(SpeicherschutzGrund.konflikt);
        }
        await entfernen(quelle);
        dateien++;
        bytes += k.bytes;
      } on Object {
        if (umgestellt && await quelle.exists()) {
          await db.transaction(() async {
            final f = await db.assetById(k.id);
            if (f?.relativePath == verweis && f?.checksum == k.hash) {
              await (db.update(db.assets)..where((t) => t.id.equals(k.id)))
                  .write(AssetsCompanion(relativePath: Value(k.relativ)));
            }
          });
        }
        final nochVerwendet =
            await (db.select(db.assets)
                  ..where((t) => t.relativePath.equals(verweis))
                  ..limit(1))
                .get();
        if (nochVerwendet.isEmpty) await refs.entfernen(verweis);
        rethrow;
      }
      erledigt++;
      fortschritt?.call(erledigt, plan.kandidaten.length);
    }
    await refs.speichern();
    return (dateien: dateien, bytes: bytes);
  }
}

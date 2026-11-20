import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

import 'entwicklungsvarianten_dienst.dart';
import 'native_image_converter.dart';

typedef ArbeitsRenderer =
    Future<Uint8List?> Function(
      File quelle,
      DevelopAdjustments werte,
      List<MaskAdjustmentLayer> masken,
      int kante,
    );

class OfflineKonflikt implements Exception {
  const OfflineKonflikt({this.originalGeaendert = false});
  final bool originalGeaendert;
}

class ArbeitsvorschauInfo {
  const ArbeitsvorschauInfo(this.asset, this.entwurf, this.am);
  final AssetData asset;
  final bool entwurf;
  final DateTime am;
}

class Arbeitsbibliothek {
  Arbeitsbibliothek(this.db, this.paths, this.asset, this._schliessen);
  final AppDatabase db;
  final StoragePaths paths;
  final AssetData asset;
  final Future<void> Function() _schliessen;
  Future<void> schliesse() => _schliessen();
}

/// Eine eigene kleine Arbeitsbibliothek hält Entwürfe von aktiven
/// Fotodaten getrennt. Erst das bestätigte Anwenden rendert am Original.
class Arbeitsvorschauen {
  Arbeitsvorschauen(
    this.db,
    this.paths, {
    ArbeitsRenderer? renderer,
    this.hoechstensBytes = 2 * 1024 * 1024 * 1024,
  }) : _renderer =
           renderer ??
           ((f, w, m, k) => NativeImageConverter.developImage(
             f,
             adjustments: w,
             masks: m,
             maxDimension: k,
             quality: .92,
           ));
  final AppDatabase db;
  final StoragePaths paths;
  final ArbeitsRenderer _renderer;
  final int hoechstensBytes;
  Directory get _wurzel =>
      paths.absolute('arbeitsvorschauen/platzhalter').parent;
  Directory _ordner(String id) {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(id)) {
      throw const FormatException('pv_arbeitsvorschau_kennung');
    }
    return Directory(p.join(_wurzel.path, id));
  }

  Future<void> _pruefeOrdner(Directory ordner) async {
    final basis = await paths.root.resolveSymbolicLinks();
    final real = await ordner.resolveSymbolicLinks();
    if (!p.isWithin(basis, real) ||
        await FileSystemEntity.type(ordner.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await FileSystemEntity.type(_wurzel.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw const FormatException('pv_arbeitsvorschau_pfad');
    }
  }

  Future<Map<String, dynamic>> _stand(String id) async {
    final o = _ordner(id);
    await _pruefeOrdner(o);
    final f = File(p.join(o.path, 'stand.json'));
    if (await f.length() > 256 * 1024) {
      throw const FormatException('pv_arbeitsvorschau_umfang');
    }
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    if (j['fassung'] != 1 || j['id'] != id) {
      throw const FormatException('pv_arbeitsvorschau_format');
    }
    return j;
  }

  Future<void> _merke(String id, Map<String, dynamic> j) async {
    final f = File(p.join(_ordner(id).path, 'stand.json'));
    final teil = File('${f.path}.part');
    try {
      await teil.writeAsString(jsonEncode(j), flush: true);
      await teil.rename(f.path);
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }

  Future<int> _verbrauch() async {
    if (!await _wurzel.exists()) return 0;
    await _pruefeOrdner(_wurzel);
    var bytes = 0, n = 0;
    await for (final e in _wurzel.list(recursive: true, followLinks: false)) {
      if (++n > 200000) {
        throw const FormatException('pv_arbeitsvorschau_umfang');
      }
      if (e is File) bytes += await e.length();
    }
    return bytes;
  }

  Future<void> vorbereiten(AssetData asset) async {
    final frisch = await db.assetById(asset.id);
    if (frisch == null ||
        frisch.isLocked ||
        frisch.isTrashed ||
        frisch.type != 'IMAGE') {
      throw const FormatException('pv_arbeitsvorschau_aufnahme');
    }
    final ziel = _ordner(asset.id);
    if (await ziel.exists()) {
      await _stand(asset.id);
      // Ein bestehender Entwurf wird niemals durch erneutes Vorbereiten ersetzt.
      return;
    }
    final original = await paths.bereit(frisch.relativePath);
    if ((await sha256.bind(original.openRead()).first).toString() !=
        frisch.checksum) {
      throw const OfflineKonflikt(originalGeaendert: true);
    }
    final basis = await db.entwicklungsBasis(frisch.id);
    final einstellungen = await db.developSettingsForAsset(frisch.id);
    final masken = await db.masksForAsset(frisch.id);
    final jpeg = await _renderer(
      original,
      DevelopAdjustments.neutral,
      const [],
      2048,
    );
    if (jpeg == null || jpeg.length > 32 * 1024 * 1024) {
      throw const FormatException('pv_arbeitsvorschau_bild');
    }
    final vorhandeneBytes = await _verbrauch();
    if (vorhandeneBytes + jpeg.length > hoechstensBytes) {
      throw const FormatException('pv_arbeitsvorschau_umfang');
    }
    await _wurzel.create(recursive: true);
    await _pruefeOrdner(_wurzel);
    final temp = await _wurzel.createTemp('.vorbereiten-');
    AppDatabase? arbeitsDb;
    try {
      final arbeitsPaths = await StoragePaths.oeffne(
        Directory(p.join(temp.path, 'library')),
      );
      await arbeitsPaths
          .absolute('originals/basis.jpg')
          .writeAsBytes(jpeg, flush: true);
      final dateien = <String, String>{};
      var neuBytes = jpeg.length;
      for (final pfad in {
        if (einstellungen?.lutPath != null) einstellungen!.lutPath!,
        for (final m in masken) m.maskRelativePath,
      }) {
        final f = await paths.bereit(pfad);
        final laenge = await f.length();
        if (laenge > 16 * 1024 * 1024 ||
            vorhandeneBytes + neuBytes + laenge > hoechstensBytes) {
          throw const FormatException('pv_arbeitsvorschau_umfang');
        }
        final hash = (await sha256.bind(f.openRead()).first).toString();
        final dest = arbeitsPaths.absolute(pfad);
        await dest.parent.create(recursive: true);
        await f.copy(dest.path);
        if ((await sha256.bind(dest.openRead()).first).toString() != hash) {
          throw const OfflineKonflikt();
        }
        dateien[pfad] = hash;
        neuBytes += laenge;
      }
      arbeitsDb = await AppDatabase.open(temp);
      final arbeit = frisch.copyWith(
        relativePath: 'originals/basis.jpg',
        checksum: sha256.convert(jpeg).toString(),
        fileSizeBytes: jpeg.length,
        dateiformat: const Value('jpg'),
        thumbnailRelativePath: const Value(null),
        previewRelativePath: const Value(null),
        developedRelativePath: const Value(null),
        restoredRelativePath: const Value(null),
        trimmedRelativePath: const Value(null),
      );
      await arbeitsDb.into(arbeitsDb.assets).insert(arbeit);
      if (einstellungen != null) {
        await arbeitsDb.into(arbeitsDb.developSettings).insert(einstellungen);
      }
      for (final m in masken) {
        await arbeitsDb.into(arbeitsDb.developMasks).insert(m);
      }
      await arbeitsDb.close();
      arbeitsDb = null;
      if (await db.entwicklungsBasis(frisch.id) != basis ||
          (await sha256.bind(original.openRead()).first).toString() !=
              frisch.checksum) {
        throw const OfflineKonflikt();
      }
      final j = {
        'fassung': 1,
        'id': frisch.id,
        'original': frisch.checksum,
        'basis': basis,
        'dateien': dateien,
        'vorschau': sha256.convert(jpeg).toString(),
        'am': DateTime.now().toUtc().toIso8601String(),
        'entwurf': false,
      };
      await File(
        p.join(temp.path, 'stand.json'),
      ).writeAsString(jsonEncode(j), flush: true);
      // Auch Katalog, Journal und Beilagen belegen Platz, nicht nur das JPEG.
      if (await _verbrauch() > hoechstensBytes) {
        throw const FormatException('pv_arbeitsvorschau_umfang');
      }
      await temp.rename(ziel.path);
    } finally {
      await arbeitsDb?.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<List<ArbeitsvorschauInfo>> liste() async {
    if (!await _wurzel.exists()) return const [];
    final ids = <String>[];
    await for (final e in _wurzel.list(followLinks: false)) {
      if (e is Directory &&
          RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(p.basename(e.path))) {
        ids.add(p.basename(e.path));
      }
      if (ids.length > 5000) {
        throw const FormatException('pv_arbeitsvorschau_umfang');
      }
    }
    final aus = <ArbeitsvorschauInfo>[];
    for (final a in await db.assetsByIds(ids)) {
      if (a.isLocked || a.isTrashed) continue;
      final s = await _stand(a.id);
      aus.add(
        ArbeitsvorschauInfo(
          a,
          s['entwurf'] == true,
          DateTime.parse(s['am'] as String),
        ),
      );
    }
    return aus;
  }

  Future<Arbeitsbibliothek> oeffne(String id) async {
    final original = await db.assetById(id);
    if (original == null ||
        original.isLocked ||
        original.isTrashed ||
        paths.offeneArbeitsvorschauen.contains(id)) {
      throw const FormatException('pv_arbeitsvorschau_aufnahme');
    }
    final s = await _stand(id);
    final o = _ordner(id);
    final arbeitsPaths = await StoragePaths.oeffne(
      Directory(p.join(o.path, 'library')),
    );
    final basis = arbeitsPaths.absolute('originals/basis.jpg');
    if ((await sha256.bind(basis.openRead()).first).toString() !=
        s['vorschau']) {
      throw const FormatException('pv_arbeitsvorschau_bild');
    }
    paths.offeneArbeitsvorschauen.add(id);
    AppDatabase? arbeitsDb;
    try {
      arbeitsDb = await AppDatabase.open(o);
      final a = await arbeitsDb.assetById(id);
      if (a == null) throw const FormatException('pv_arbeitsvorschau_aufnahme');
      final katalog = arbeitsDb;
      return Arbeitsbibliothek(katalog, arbeitsPaths, a, () async {
        await katalog.close();
        paths.offeneArbeitsvorschauen.remove(id);
      });
    } catch (_) {
      await arbeitsDb?.close();
      paths.offeneArbeitsvorschauen.remove(id);
      rethrow;
    }
  }

  Future<void> merkeEntwurf(String id) async {
    final j = await _stand(id);
    j['entwurf'] = true;
    await _merke(id, j);
  }

  Future<bool> _dateienGleich(Map<String, dynamic> s) async {
    for (final e in (s['dateien'] as Map).cast<String, String>().entries) {
      try {
        if ((await sha256.bind((await paths.bereit(e.key)).openRead()).first)
                .toString() !=
            e.value) {
          return false;
        }
      } on Object {
        return false;
      }
    }
    return true;
  }

  Future<String> anwenden(
    String id,
    String name, {
    bool nurNeueVariante = false,
  }) async {
    final s = await _stand(id);
    final a = await db.assetById(id);
    if (a == null || a.isLocked || a.isTrashed) {
      throw const FormatException('pv_arbeitsvorschau_aufnahme');
    }
    final original = await paths.bereit(a.relativePath);
    if (a.checksum != s['original'] ||
        (await sha256.bind(original.openRead()).first).toString() !=
            s['original']) {
      throw const OfflineKonflikt(originalGeaendert: true);
    }
    final basis = s['basis'] as String;
    if (!nurNeueVariante &&
        (await db.entwicklungsBasis(id) != basis || !await _dateienGleich(s))) {
      throw const OfflineKonflikt();
    }
    final arbeit = await oeffne(id);
    try {
      final d = await arbeit.db.developSettingsForAsset(id);
      if (d == null) throw const FormatException('pv_arbeitsvorschau_entwurf');
      final masken = await arbeit.db.masksForAsset(id);
      final werte = reglerAusEinstellungen(
        d,
        lut: await ladeFarbtabelle(arbeit.paths, d.lutPath),
      );
      final bytes = await _renderer(original, werte, [
        for (final m in masken)
          MaskAdjustmentLayer(
            maskFilePath: arbeit.paths.absolute(m.maskRelativePath).path,
            adjustments: DevelopAdjustments(
              exposure: m.exposure,
              temperature: m.temperature,
              tint: m.tint,
              contrast: m.contrast,
              shadows: m.shadows,
              highlights: m.highlights,
              sharpness: m.sharpness,
              noiseReduction: m.noiseReduction,
            ),
          ),
      ], 4096);
      if (bytes == null) throw const FormatException('pv_arbeitsvorschau_bild');
      if ((await sha256.bind(original.openRead()).first).toString() !=
          s['original']) {
        throw const OfflineKonflikt(originalGeaendert: true);
      }
      final dienst = EntwicklungsvariantenDienst(db, paths);
      if (!nurNeueVariante && !await _dateienGleich(s)) {
        throw const OfflineKonflikt();
      }
      final String variante;
      try {
        variante = await dienst.speichern(
          asset: a,
          name: name,
          einstellungen: d.copyWith(assetId: id),
          masken: masken,
          jpeg: bytes,
          quellPaths: arbeit.paths,
          aktivierenBeiStand: nurNeueVariante ? null : basis,
        );
      } on StateError catch (e) {
        if (e.message == 'pv_offline_konflikt') throw const OfflineKonflikt();
        rethrow;
      }
      s['angewandt'] = DateTime.now().toUtc().toIso8601String();
      s['entwurf'] = false;
      await _merke(id, s);
      return variante;
    } finally {
      await arbeit.schliesse();
    }
  }

  Future<void> entfernen(String id) async {
    if (paths.offeneArbeitsvorschauen.contains(id)) {
      throw StateError('pv_arbeitsvorschau_offen');
    }
    final o = _ordner(id);
    if (!await o.exists()) return;
    await _pruefeOrdner(o);
    await o.delete(recursive: true);
  }
}

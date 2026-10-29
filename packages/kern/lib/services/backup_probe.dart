part of 'backup_service.dart';

/// Der Nachweis gehört zum Sicherungsziel. Er enthält weder Dateinamen
/// noch Prüfsummen einzelner Fotos oder Schlüsselmaterial.
class BackupProbeErgebnis {
  const BackupProbeErgebnis({
    required this.am,
    required this.erfolgreich,
    required this.originale,
    required this.gesamt,
    required this.datenbank,
    this.letzterErfolg,
    this.fehler,
    this.position = 0,
    this.passphraseGeprueft,
  });

  final DateTime am;
  final bool erfolgreich;
  final int originale;
  final int gesamt;
  final bool datenbank;
  final DateTime? letzterErfolg;
  final String? fehler;
  final int position;
  final bool? passphraseGeprueft;

  Map<String, Object?> alsJson() => {
    'format': 1,
    'am': am.toUtc().toIso8601String(),
    'erfolgreich': erfolgreich,
    'originale': originale,
    'gesamt': gesamt,
    'datenbank': datenbank,
    'letzterErfolg': letzterErfolg?.toUtc().toIso8601String(),
    'fehler': fehler,
    'position': position,
    'passphraseGeprueft': passphraseGeprueft,
  };

  static BackupProbeErgebnis ausJson(Map<String, dynamic> j) {
    if (j['format'] != 1) throw const FormatException('pv_probe_format');
    return BackupProbeErgebnis(
      am: DateTime.parse(j['am'] as String),
      erfolgreich: j['erfolgreich'] as bool,
      originale: j['originale'] as int,
      gesamt: j['gesamt'] as int,
      datenbank: j['datenbank'] as bool,
      letzterErfolg: DateTime.tryParse('${j['letzterErfolg']}'),
      fehler: j['fehler'] as String?,
      position: j['position'] as int? ?? 0,
      passphraseGeprueft: j['passphraseGeprueft'] as bool?,
    );
  }
}

class _ProbeDatenbank extends AppDatabase {
  _ProbeDatenbank(super.executor);
}

extension BackupWiederherstellungsprobe on BackupService {
  static const probeDateiname = 'wiederherstellungsprobe.json';

  Future<BackupProbeErgebnis?> letzteProbe(String wurzel) async {
    try {
      return BackupProbeErgebnis.ausJson(
        jsonDecode(await File(p.join(wurzel, probeDateiname)).readAsString())
            as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  /// Stellt eine rotierende Stichprobe über denselben Wiederherstellungsweg
  /// wie die Oberfläche wieder her. Die Produktivdatenbank und deren Pfade
  /// werden dabei nie verwendet. Ein Erfolg bestätigt nur diese Stichprobe.
  Future<BackupProbeErgebnis> pruefeWiederherstellung(
    String wurzel, {
    SecretKey? schluessel,
    String? passphrase,
    int anzahl = 3,
    int maxBytes = 128 * 1024 * 1024,
    Directory? zwischenlager,
  }) async {
    if (anzahl < 1 || maxBytes < 1) throw ArgumentError('pv_probe_grenze');
    final vorher = await letzteProbe(wurzel);
    final am = DateTime.now();
    final temp = await (zwischenlager ?? Directory.systemTemp).createTemp(
      'pv_wiederherstellungsprobe_',
    );
    AppDatabase? probeDb;
    var datenbank = false, erledigt = 0, gesamt = 0;
    var position = vorher?.position ?? 0;
    String? fehler;
    bool? passphraseGeprueft;
    try {
      if (!Platform.isWindows) {
        final r = await Process.run('chmod', ['700', temp.path]);
        if (r.exitCode != 0) throw const FileSystemException('pv_probe_rechte');
      }
      final root = Directory(wurzel);
      final echt = await root.resolveSymbolicLinks();
      Future<File> sicher(String relativ) async {
        final f = File(p.join(wurzel, relativ));
        if (p.isAbsolute(relativ) ||
            !p.isWithin(wurzel, p.normalize(f.path)) ||
            !p.isWithin(echt, await f.resolveSymbolicLinks())) {
          throw const FormatException('pv_probe_pfad');
        }
        return f;
      }

      final keyFile = File(p.join(wurzel, 'vault.key'));
      if (schluessel != null || await keyFile.exists()) {
        passphraseGeprueft = false;
        final datei = await sicher('vault.key');
        if (await datei.length() > 16384) {
          throw const FormatException('pv_probe_schluessel');
        }
        final e = jsonDecode(await datei.readAsString()) as Map;
        final salt = base64Decode(e['kdfSalt'] as String);
        final nonce = base64Decode(e['nonce'] as String);
        final wrapped = base64Decode(e['wrapped'] as String);
        if (salt.length != 16 || nonce.length != 12 || wrapped.length != 48) {
          throw const FormatException('pv_probe_schluessel');
        }
        if (schluessel == null) {
          if (passphrase == null) throw const BackupBrauchtPassphrase();
          schluessel = await VaultCrypto.unwrapMasterKey(
            passphrase,
            kdfSalt: salt,
            nonce: nonce,
            wrapped: wrapped,
          );
          passphraseGeprueft = true;
        }
      }
      final meta = await sicher('metadata.json');
      if (await meta.length() > 64 * 1024 * 1024) {
        throw const FormatException('pv_probe_manifest_zu_gross');
      }
      final klar = File(p.join(temp.path, 'metadata.json'));
      if (schluessel == null) {
        await meta.copy(klar.path);
      } else {
        await VaultCrypto.decryptFile(meta, klar, schluessel);
      }
      final manifest = jsonDecode(await klar.readAsString()) as Map;
      final fotos = (manifest['assets'] as List).cast<Map>();
      // Das Manifest muss vollständig lesbar sein, auch außerhalb der
      // Stichprobe. Ungültige Einträge dürfen nicht still verschwinden.
      final gesehen = <String>{};
      for (final foto in fotos) {
        final hash = foto['checksum'];
        if (hash is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
            !gesehen.add(hash) ||
            foto['originalFileName'] is! String ||
            (foto['tags'] != null &&
                (foto['tags'] is! List ||
                    !(foto['tags'] as List).every((t) => t is String)))) {
          throw const FormatException('pv_probe_manifest');
        }
      }
      gesamt = fotos.length;
      final snapshot = File(p.join(wurzel, 'library.sqlite.enc'));
      if (await snapshot.exists()) {
        final quelle = await sicher('library.sqlite.enc');
        if (schluessel == null) {
          throw const FormatException('pv_probe_schluessel');
        }
        if (await quelle.length() > 512 * 1024 * 1024) {
          throw const FormatException('pv_probe_datenbank_zu_gross');
        }
        final dbDatei = File(p.join(temp.path, 'schnappschuss.sqlite'));
        await VaultCrypto.decryptFile(quelle, dbDatei, schluessel);
        final db = sqlite3.open(dbDatei.path, mode: OpenMode.readOnly);
        try {
          if (db.select('PRAGMA integrity_check').single.values.single !=
                  'ok' ||
              db.select('PRAGMA foreign_key_check').isNotEmpty ||
              (db.select('PRAGMA user_version').single.values.single as int) >
                  _db.schemaVersion) {
            throw const FormatException('pv_probe_datenbank');
          }
          datenbank = true;
        } finally {
          db.close();
        }
      }
      final auswahl = <String>{};
      final start = position;
      var bytes = 0;
      for (var i = 0; i < fotos.length && auswahl.length < anzahl; i++) {
        final index = (start + i) % fotos.length;
        final foto = fotos[index];
        final hash = foto['checksum'] as String;
        final relativ = schluessel == null
            ? foto['backupRelativePath'] as String
            : p.join(
                VerschluesselteNamen.ordner,
                await VerschluesselteNamen.fuerPruefsumme(hash, schluessel),
              );
        final datei = await sicher(relativ);
        final groesse = await datei.length();
        if (bytes + groesse > maxBytes) continue;
        bytes += groesse;
        auswahl.add(hash);
        position = (index + 1) % fotos.length;
      }
      if (fotos.isNotEmpty && auswahl.isEmpty) {
        throw const FormatException('pv_probe_stichprobe_zu_gross');
      }
      final library = Directory(p.join(temp.path, 'bibliothek'));
      await library.create();
      probeDb = _ProbeDatenbank(
        NativeDatabase(File(p.join(library.path, 'library.sqlite'))),
      );
      final pfade = await StoragePaths.oeffne(
        Directory(p.join(library.path, 'library')),
      );
      final dienst = BackupService(probeDb, pfade);
      await dienst
          .restoreFromBackup(
            wurzel,
            ImportService(probeDb, pfade),
            entschluesselungsschluessel: schluessel,
            auswahlPruefsummen: auswahl,
            streng: true,
            zwischenlager: temp,
          )
          .drain<void>();
      final wiederhergestellt = await probeDb.select(probeDb.assets).get();
      if (wiederhergestellt.length != auswahl.length) {
        throw const FormatException('pv_probe_anzahl');
      }
      for (final foto in fotos.where((f) => auswahl.contains(f['checksum']))) {
        final a = wiederhergestellt.singleWhere(
          (a) => a.checksum == foto['checksum'],
        );
        final tags = (await probeDb.tagsForAsset(
          a.id,
        )).map((t) => t.name).toSet();
        final erwartet = (foto['tags'] as List? ?? const [])
            .cast<String>()
            .toSet();
        final bytesHash =
            (await sha256.bind(pfade.absolute(a.relativePath).openRead()).first)
                .toString();
        if (bytesHash != foto['checksum'] ||
            a.originalFileName !=
                p.basename(foto['originalFileName'] as String) ||
            (a.description ?? '') != (foto['description'] ?? '') ||
            a.isFavorite != (foto['isFavorite'] ?? false) ||
            a.rating != (foto['rating'] ?? 0) ||
            (foto['fileCreatedAt'] is String &&
                !a.fileCreatedAt.isAtSameMomentAs(
                  DateTime.parse(foto['fileCreatedAt'] as String),
                )) ||
            (foto['datumGeschaetzt'] is bool &&
                a.datumGeschaetzt != foto['datumGeschaetzt']) ||
            (foto.containsKey('colorLabel') &&
                a.colorLabel != foto['colorLabel']) ||
            (foto.containsKey('latitude') &&
                a.latitude != (foto['latitude'] as num?)?.toDouble()) ||
            (foto.containsKey('longitude') &&
                a.longitude != (foto['longitude'] as num?)?.toDouble()) ||
            (foto.containsKey('locationCity') &&
                a.locationCity != foto['locationCity']) ||
            (foto.containsKey('locationState') &&
                a.locationState != foto['locationState']) ||
            (foto.containsKey('locationCountry') &&
                a.locationCountry != foto['locationCountry']) ||
            tags.length != erwartet.length ||
            !tags.containsAll(erwartet)) {
          throw const FormatException('pv_probe_metadaten');
        }
        if (foto['kiTags'] case final List ki) {
          final ist = (await probeDb.kiTagNamesByAssetId())[a.id] ?? <String>{};
          if (ist.length != ki.length || !ist.containsAll(ki.cast<String>())) {
            throw const FormatException('pv_probe_tagherkunft');
          }
        }
        erledigt++;
      }
      final alben = (manifest['albums'] as List? ?? const []).cast<Map>();
      for (final album in alben) {
        final enthalten = (album['assetChecksums'] as List)
            .cast<String>()
            .toSet()
            .intersection(auswahl);
        if (enthalten.isEmpty) continue;
        final gefunden = await probeDb.select(probeDb.albums).get();
        var passt = false;
        for (final a in gefunden.where((a) => a.name == album['name'])) {
          final ist = (await probeDb.assetsInAlbumOnce(
            a.id,
          )).map((a) => a.checksum).toSet();
          if (ist.length == enthalten.length && ist.containsAll(enthalten)) {
            passt = true;
          }
        }
        if (!passt) throw const FormatException('pv_probe_alben');
      }
    } on Object catch (e) {
      fehler = e is FormatException && e.message.startsWith('pv_probe_')
          ? e.message
          : 'pv_probe_unlesbar';
    } finally {
      try {
        await probeDb?.close();
        await temp.delete(recursive: true);
      } on Object {
        fehler = 'pv_probe_aufraeumen';
      }
    }
    final ergebnis = BackupProbeErgebnis(
      am: am,
      erfolgreich: fehler == null,
      originale: erledigt,
      gesamt: gesamt,
      datenbank: datenbank,
      letzterErfolg: fehler == null ? am : vorher?.letzterErfolg,
      fehler: fehler,
      position: position,
      passphraseGeprueft: passphraseGeprueft,
    );
    final ziel = File(p.join(wurzel, probeDateiname));
    final teil = File('${ziel.path}.${const Uuid().v4()}.neu');
    try {
      await teil.writeAsString(jsonEncode(ergebnis.alsJson()), flush: true);
      await teil.rename(ziel.path);
    } finally {
      if (await teil.exists()) await teil.delete();
    }
    return ergebnis;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'blur_detection.dart';
import 'face_engine_service.dart';
import 'import_service.dart';
import 'storage_paths.dart';
import 'vault_crypto.dart';
import 'xmp_writer.dart';

import 'package:image/image.dart' as img;

/// Geworfen, wenn ein verschlüsseltes Backup ohne Passphrase geöffnet werden
/// soll – der Aufrufer zeigt seinen eigenen, übersetzten Hinweis.
class BackupBrauchtPassphrase implements Exception {
  const BackupBrauchtPassphrase();
}


class BackupProgress {
  final int done;
  final int total;
  final String? currentFile;

  /// Wie viele Dateien beim nächsten Lauf folgen, weil die Mengenbegrenzung
  /// gegriffen hat – sonst null.
  ///
  /// Als Zahl statt als fertigem Satz: Der Dienst kennt keine
  /// Oberflächensprache, und der Satz stünde sonst in `currentFile`, wo
  /// eigentlich ein Dateiname erwartet wird.
  final int? grenzeOffen;

  /// Wie viele Dateien in diesem Lauf nicht gesichert werden konnten –
  /// sonst null.
  ///
  /// Auch das eine Zahl statt eines Satzes, aus demselben Grund wie
  /// [grenzeOffen]. Sie muss sichtbar werden: Eine Sicherung, die einzelne
  /// Dateien auslässt, darf nicht wie eine vollständige aussehen.
  final int? fehlgeschlagen;

  /// Wie viele Zeilen aus dem Datenbank-Schnappschuss übernommen wurden –
  /// Personen, Gesichter, Verwandtschaften, Reisen, Aktivitäten und alles
  /// Weitere, was in keiner Datei-Beilage steht. `null`, wenn die Sicherung
  /// keinen Schnappschuss enthielt (eine von Hand angestossene tut das
  /// nicht) oder er sich nicht lesen liess.
  final int? uebernommeneZeilen;

  /// Wahr, solange die Wiederherstellung die Gesichtsausschnitte neu
  /// zeichnet. Das ist eine eigene Stufe mit eigener Zählung – ohne diesen
  /// Hinweis sähe es aus, als finge der Lauf von vorne an.
  final bool ausschnitteNeu;

  BackupProgress(this.done, this.total,
      {this.currentFile,
      this.grenzeOffen,
      this.fehlgeschlagen,
      this.uebernommeneZeilen,
      this.ausschnitteNeu = false});
}

/// Kopiert die Bibliothek manuell in einen vom Nutzer gewählten Ordner.
/// Das ist bewusst kein automatischer Cloud-Upload: der Nutzer wählt selbst
/// einen Ordner (z.B. den lokalen Dropbox- oder Google-Drive-Sync-Ordner),
/// und der jeweilige Desktop-Client kümmert sich um die eigentliche
/// Cloud-Synchronisierung.
///
/// Optional (siehe [encryptionKey]) wird das Backup mit AES-256-GCM
/// verschlüsselt – derselbe Mechanismus wie beim gesperrten Ordner
/// (VaultCrypto), aber mit einem eigenen, von der Backup-Passphrase
/// abgeleiteten Master-Key (siehe LibraryState). Der verpackte Schlüssel
/// wird zusätzlich als `vault.key`-Datei INS Backup selbst geschrieben,
/// damit sich ein verschlüsseltes Backup auch auf einem komplett anderen
/// Rechner allein mit der Passphrase wiederherstellen lässt.
class BackupService {
  BackupService(this._db, this._paths, {Directory? zwischenlager})
      : _festesZwischenlager = zwischenlager;

  final AppDatabase _db;
  final StoragePaths _paths;

  /// Ein vorgegebenes Zwischenlager statt eines frisch angelegten im
  /// System-Temp. **Nur für Tests**: Anders liesse sich der Fall „das
  /// Zwischenlager taugt nicht" nicht nachstellen, ohne ein Dateisystem
  /// mit fester Grösse anzulegen. Wird nicht aufgeräumt – wer es
  /// vorgibt, räumt es auch weg.
  final Directory? _festesZwischenlager;
  final _uuid = const Uuid();

  static const _backupFolderName = 'PhotoVault-Backup';

  /// Ab welcher Grösse das Zwischenlager im System-Temp nachweislich nicht
  /// mehr reicht – `null`, solange nichts daran gescheitert ist.
  ///
  /// Selbst geeicht statt vorher ausgerechnet: Dart kennt keinen
  /// portablen Weg, den freien Platz eines Dateisystems zu erfragen, und
  /// ihn über FFI je Plattform zu holen wäre viel Maschinerie für eine
  /// Zahl, die sich hier von selbst ergibt. Die erste zu grosse Datei
  /// bezahlt einen vergeblichen Schreibversuch, alle weiteren nicht mehr.
  int? _zwischenlagerGrenze;

  /// Der geeichte Wert – nur für Tests. Er unterscheidet zwei Fälle, die
  /// sich von aussen sonst nicht auseinanderhalten lassen: „das
  /// Zwischenlager taugt nicht" (Wert gesetzt) und „das Ziel taugt nicht"
  /// (Wert bleibt `null`).
  @visibleForTesting
  int? get zwischenlagerGrenze => _zwischenlagerGrenze;

  /// Schreibt eine Datei über eine Zwischenablage und legt sie erst
  /// fertig ins Ziel.
  ///
  /// **Warum überhaupt eine Zwischendatei.** Cloud-Clients beginnen sonst,
  /// halbfertige Dateien hochzuladen. Das Umbenennen am Ende ist innerhalb
  /// desselben Dateisystems atomar – der Client sieht die Datei entweder
  /// gar nicht oder vollständig.
  ///
  /// **Warum zwei mögliche Orte.** Bevorzugt wird das System-Temp: Es
  /// liegt ausserhalb des Sync-Ordners, der Client sieht die Zwischendatei
  /// also nie. Unter Flatpak ist `/tmp` aber ein **tmpfs von 789 MiB**
  /// (nachgemessen am 25.08.2026), und in einer echten Bibliothek liegen
  /// Videos bis 9,1 GB. Für die passt das Zwischenlager nicht – und weil
  /// tmpfs im Arbeitsspeicher liegt, kostete der Versuch obendrein RAM.
  /// Dann wird neben dem Ziel geschrieben: dasselbe Dateisystem, also
  /// weiterhin ein atomares Umbenennen, keine Grössengrenze und ein
  /// Schreibvorgang weniger. Der Preis ist, dass ein Sync-Client die
  /// `.pv-teil`-Datei kurz sieht.
  ///
  /// [quellGroesse] dient nur der Eichung von [_zwischenlagerGrenze].
  Future<void> _ueberZwischendatei({
    required Directory zwischenlager,
    required File ziel,
    required int quellGroesse,
    required Future<void> Function(File zwischen) schreibe,
  }) async {
    final vermutlichZuGross = _zwischenlagerGrenze != null &&
        quellGroesse >= _zwischenlagerGrenze!;

    if (!vermutlichZuGross) {
      final zwischen = File(p.join(zwischenlager.path, 'teil'));
      var imLager = false;
      try {
        await schreibe(zwischen);
        imLager = true;
      } on FileSystemException catch (e) {
        // Kein Platz (oder sonst ein Problem) im Zwischenlager. Merken,
        // damit die nächste grosse Datei den Umweg gar nicht erst geht.
        _zwischenlagerGrenze = quellGroesse;
        debugPrint('Zwischenlager fasst $quellGroesse Bytes nicht ($e) – '
            'ab jetzt wird neben dem Ziel geschrieben');
        await _wegwerfen(zwischen);
      }
      if (imLager) {
        // Ab hier ist das Zwischenlager aus dem Spiel. Scheitert das
        // Ablegen, liegt es am Ziel – und dann hilft es nicht, es dort
        // noch einmal zu versuchen. Diese Unterscheidung ist nicht
        // theoretisch: Ohne sie eichte ein unschreibbares Ziel die
        // Grenze des Zwischenlagers und nahm dem restlichen Lauf die
        // Eigenschaft, für die es überhaupt da ist.
        try {
          await _verschiebe(zwischen, ziel);
        } catch (_) {
          await _wegwerfen(zwischen);
          rethrow;
        }
        return;
      }
    }

    final daneben = File('${ziel.path}.pv-teil');
    try {
      await schreibe(daneben);
      await _verschiebe(daneben, ziel);
    } catch (_) {
      await _wegwerfen(daneben);
      rethrow;
    }
  }

  /// Löscht eine Zwischendatei, ohne den eigentlichen Fehler zu verdecken.
  Future<void> _wegwerfen(File datei) async {
    try {
      if (await datei.exists()) await datei.delete();
    } catch (_) {
      // Ein liegengebliebener Rest ist ärgerlich, aber kein Grund, den
      // Lauf abzubrechen – und schon gar keiner, den echten Fehler zu
      // überschreiben.
    }
  }

  /// Führt ein inkrementelles Backup durch: nur Originaldateien, die noch
  /// nicht als gesichert markiert sind, werden kopiert. Die Metadaten
  /// (Favoriten, Beschreibung, Tags, Alben) werden bei jedem Lauf komplett
  /// neu als `metadata.json` exportiert, damit der Cloud-Ordner immer den
  /// aktuellen Stand widerspiegelt.
  /// [maxBytesPerRun] begrenzt, wie viel je Lauf ins Ziel geschrieben wird
  /// (0 oder negativ = unbegrenzt). Gedacht für Cloud-Sync-Ordner: Ohne
  /// Grenze landen bei der ersten Sicherung zigtausend Dateien auf einmal
  /// im Sync-Ordner und der Upload läuft tagelang. Was nicht mehr
  /// hineinpasst, bleibt unmarkiert und kommt beim nächsten Lauf dran.
  Stream<BackupProgress> performBackup(
    String destinationRootPath, {
    SecretKey? encryptionKey,
    int maxBytesPerRun = 0,
  }) async* {
    final backupRoot = Directory(p.join(destinationRootPath, _backupFolderName));
    final originalsOut = Directory(p.join(backupRoot.path, 'originals'));
    await originalsOut.create(recursive: true);

    // Bei einer verschlüsselten Sicherung von Hand kommt der Schnappschuss
    // der Datenbank mit – genau wie bei der automatischen. Ohne ihn brächte
    // eine Wiederherstellung die Fotos zurück und liesse die Namen an den
    // Gesichtern, den Stammbaum, Reisen und Aktivitäten liegen (Befund der
    // 19. Prüfrunde).
    //
    // **Nur verschlüsselt.** Eine Klartext-Datenbank neben den Fotos wäre
    // dasselbe Leck, das die 16. Prüfrunde bei `metadata.json` geschlossen
    // hat, nur grösser: Sie beschriebe jede Aufnahme, auch die im
    // gesperrten Ordner. Wer eine Sicherung von Hand ohne Passphrase
    // anlegt, bekommt deshalb weiterhin Fotos plus Beilagen – und der
    // Einstellungstext sagt das inzwischen auch.
    if (encryptionKey != null) {
      await _writeEncryptedDatabaseSnapshot(backupRoot, encryptionKey);
    }

    // Zwischenlager – warum und was passiert, wenn es nicht reicht: siehe
    // [_ueberZwischendatei]. Geht es verloren (Neustart), entsteht kein
    // Schaden: Markiert wird erst nach erfolgreicher Ablage im Ziel.
    final staging = _festesZwischenlager ??
        await Directory.systemTemp.createTemp('pv_backup_stage_');

    final pending = await _db.assetsNotBackedUp();
    var done = 0;
    var totalBytes = 0;
    var geschriebeneBytes = 0;
    var abgebrochenWegenLimit = false;
    final backedUpIds = <String>[];
    var fehlgeschlagen = 0;

    // XMP-Sidecars nur für unverschlüsselte Backups: bei einem verschlüsselten
    // Backup (encryptionKey != null) würde eine im Klartext danebenliegende
    // .xmp-Datei genau die Vertraulichkeit unterlaufen, die der Nutzer mit der
    // Backup-Passphrase gerade herstellen wollte.
    final tagsByAssetId = encryptionKey == null ? await _db.allTagNamesByAssetId() : null;
    // Aus demselben Grund: Ein Name neben einem verschlüsselten Foto sagt
    // mehr aus als das Foto selbst.
    final gesichterByAssetId =
        encryptionKey == null ? await _db.alleGesichtsregionen() : null;

    yield BackupProgress(0, pending.length);

    try {
      for (final asset in pending) {
        if (maxBytesPerRun > 0 && geschriebeneBytes >= maxBytesPerRun) {
          abgebrochenWegenLimit = true;
          break;
        }

        final source = _paths.absolute(asset.relativePath);
        // Je Datei abgesichert: Vorher stand die ganze Schleife in einem
        // try/finally ohne catch – eine einzige Datei, die sich nicht
        // schreiben liess, brach den kompletten Lauf ab, und alles
        // dahinter wurde nie gesichert. Genau das passierte unter Flatpak
        // beim ersten Video über 789 MB.
        try {
          if (await source.exists()) {
            // Verschlüsselt: flach unter data/ mit abgeleitetem Namen, damit
            // weder Aufnahmezeitraum noch Dateiformat sichtbar bleiben.
            // Unverschlüsselt: weiterhin die lesbare Ordnerstruktur, damit
            // sich so ein Backup auch ohne die App durchsehen lässt.
            final target = encryptionKey != null
                ? File(p.join(backupRoot.path, VerschluesselteNamen.ordner,
                    await VerschluesselteNamen.fuerPruefsumme(asset.checksum, encryptionKey)))
                : File(p.join(originalsOut.path,
                    asset.relativePath.replaceFirst('originals${Platform.pathSeparator}', '')));
            await target.parent.create(recursive: true);

            final quellGroesse = await source.length();
            await _ueberZwischendatei(
              zwischenlager: staging,
              ziel: target,
              quellGroesse: quellGroesse,
              schreibe: (zwischen) async {
                if (encryptionKey != null) {
                  await VaultCrypto.encryptFile(source, zwischen, encryptionKey);
                } else {
                  await source.copy(zwischen.path);
                }
              },
            );

            if (encryptionKey == null) {
              final xmp = buildXmpPacket(
                asset,
                tagsByAssetId![asset.id] ?? const [],
                gesichter: gesichterByAssetId![asset.id] ?? const [],
              );
              await File(_paths.xmpSidecarPath(target.path)).writeAsString(xmp);
            }

            totalBytes += quellGroesse;
            geschriebeneBytes += await target.length();
          }
          backedUpIds.add(asset.id);
        } catch (e) {
          // Nicht markieren – die Datei kommt beim nächsten Lauf wieder
          // dran. Gezählt wird sie trotzdem, sonst sähe ein Lauf mit
          // Ausfällen aus wie ein vollständiger.
          fehlgeschlagen++;
          debugPrint('Sicherung von ${asset.originalFileName} '
              'fehlgeschlagen: $e');
        }
        done++;
        yield BackupProgress(done, pending.length, currentFile: asset.originalFileName);
      }
    } finally {
      // Reste immer wegräumen, auch bei Fehlern – aber nur das selbst
      // angelegte Lager. Ein vorgegebenes gehört dem Aufrufer.
      if (_festesZwischenlager == null) {
        try {
          await staging.delete(recursive: true);
        } catch (e) {
          // Kein Grund, die Sicherung scheitern zu lassen - aber es muss
          // gesagt werden: Im Zwischenlager liegen die Dateien im
          // KLARTEXT. Bleibt es stehen, bleibt der Klartext liegen, und
          // ein stiller Fehlschlag hiesse, dass niemand davon erfaehrt.
          debugPrint('Zwischenlager ${staging.path} nicht geloescht: $e - '
              'es enthaelt unverschluesselte Dateien.');
        }
      }
    }

    if (backedUpIds.isNotEmpty) {
      await _db.markBackedUp(backedUpIds);
    }

    await _writeMetadataExport(backupRoot, encryptionKey: encryptionKey);
    if (encryptionKey != null) {
      await _writeKeyEnvelope(backupRoot);
    }

    await _db.insertBackupRecord(BackupRecordsCompanion.insert(
      id: _uuid.v4(),
      performedAt: DateTime.now(),
      destinationPath: destinationRootPath,
      // Nur die tatsächlich gesicherten Dateien zählen, nicht die geplanten –
      // sonst behauptet der Bericht bei einem begrenzten Lauf mehr, als er
      // geschafft hat.
      fileCount: backedUpIds.length,
      totalBytes: totalBytes,
    ));

    // Abschließende Meldung macht sichtbar, dass noch etwas aussteht –
    // sonst wirkt ein begrenzter Lauf wie ein vollständiges Backup.
    if (abgebrochenWegenLimit) {
      yield BackupProgress(
        done,
        pending.length,
        grenzeOffen: pending.length - done,
      );
    }
    // Nach der Mengenmeldung, damit sie das letzte Wort hat: Ausgelassene
    // Dateien sind die wichtigere Nachricht.
    if (fehlgeschlagen > 0) {
      yield BackupProgress(done, pending.length, fehlgeschlagen: fehlgeschlagen);
    }
  }

  /// Verschiebt [von] nach [nach].
  ///
  /// `rename` ist innerhalb desselben Dateisystems atomar – der Cloud-Client
  /// sieht die Datei dann entweder gar nicht oder vollständig, nie halb
  /// geschrieben. Über Dateisystemgrenzen hinweg (Zwischenspeicher im
  /// System-Temp, Ziel auf einem anderen Volume) schlägt `rename` fehl;
  /// dann wird kopiert und die Zwischendatei gelöscht.
  Future<void> _verschiebe(File von, File nach) async {
    try {
      await von.rename(nach.path);
    } on FileSystemException {
      await von.copy(nach.path);
      await von.delete();
    }
  }

  /// Schreibt `metadata.json` — die Beschreibung dessen, **was gesichert
  /// wurde**.
  ///
  /// **Gesperrte Fotos stehen nicht darin, und das war ein Befund.** Ihre
  /// Dateien werden seit jeher ausgelassen ([AppDatabase.assetsNotBackedUp]
  /// schliesst `isLocked` aus), ihre Metadaten aber nicht: Dateiname,
  /// Beschreibung und Schlagwörter landeten im Klartext in einer Datei,
  /// die typischerweise in einem Dropbox- oder Drive-Ordner liegt. An
  /// einem nachgebauten Fall abgelesen — die Datei blieb zurück, der
  /// Name stand da:
  ///
  /// ```
  /// originals/  -> nur strand.jpg
  /// metadata.json -> "Scheidungsurkunde_Anna.jpg",
  ///                  "Termin beim Anwalt am 3.9.", ["Scheidung"]
  /// ```
  ///
  /// Damit war genau das preisgegeben, wovor der gesperrte Ordner
  /// schützen soll. Dieselbe Überlegung stand schon bei den
  /// XMP-Beilagen daneben (siehe [performBackup]) — sie galt nur hier
  /// nicht.
  ///
  /// **Was eine frühere Sicherung enthält, ändert sich dadurch nicht.**
  /// Wer ein Foto sperrt, nachdem es gesichert wurde, findet es weiter im
  /// Sicherungsziel: Dort wird nie gelöscht, und das ist Absicht.
  Future<void> _writeMetadataExport(Directory backupRoot, {SecretKey? encryptionKey}) async {
    final allAssets = await _db.assetsFuerMetadatenexport();
    final albums = await _db.select(_db.albums).get();
    // Eine einzige Abfrage für alle Tags statt einer pro Foto (N+1-Problem
    // bei großen Bibliotheken – Backups sollen schnell bleiben).
    final tagsByAssetId = await _db.allTagNamesByAssetId();
    // Getrennt mitgeführt, damit eine Rücksicherung die Herkunft nicht
    // einebnet – siehe [AppDatabase.kiTagNamesByAssetId].
    final kiTagsByAssetId = await _db.kiTagNamesByAssetId();

    final assetsJson = <Map<String, dynamic>>[];
    for (final a in allAssets) {
      assetsJson.add({
        'checksum': a.checksum,
        'originalFileName': a.originalFileName,
        // Die Wiederherstellung braucht diesen Pfad nicht, die
        // Sicherungsprüfung aber schon: Nur so kann sie eine vorhandene,
        // aber veränderte Datei klar von einer fehlenden unterscheiden,
        // ohne den ganzen Zielordner nach jedem möglichen Hash absuchen zu
        // müssen. Bei verschlüsselten Backups liegt das Feld selbst wieder
        // in der verschlüsselten metadata.json.
        'backupRelativePath': a.relativePath,
        'isFavorite': a.isFavorite,
        'description': a.description,
        'fileCreatedAt': a.fileCreatedAt.toIso8601String(),
        // Sterne und Farbmarke sind Handarbeit und standen bis hierher
        // nicht in der Sicherung — die Anleitung nannte „Bewertungen"
        // trotzdem. Wer nach einem Plattenschaden zurückspielte, fand
        // jeden Stern gelöscht.
        'rating': a.rating,
        'colorLabel': a.colorLabel,
        // Der Ort ebenso: Seit Fassung 2.1.0 lässt er sich von Hand über
        // den Namen eintragen, und für eingescannte Bilder ist das die
        // einzige Quelle. Aus der Datei zurückzurechnen geht dort nicht.
        'latitude': a.latitude,
        'longitude': a.longitude,
        'locationCity': a.locationCity,
        'locationState': a.locationState,
        'locationCountry': a.locationCountry,
        'tags': tagsByAssetId[a.id] ?? const <String>[],
        // Zusätzlich und nicht anstelle von 'tags': Eine ältere Fassung,
        // die dieses Feld nicht kennt, liest die Sicherung weiterhin – sie
        // bekommt dann alles als Handvergabe, also den sicheren Fall.
        'kiTags': (kiTagsByAssetId[a.id] ?? const <String>{}).toList(),
      });
    }

    final albumsJson = <Map<String, dynamic>>[];
    for (final album in albums) {
      final albumAssets = await _db.assetsInAlbumOnce(album.id);
      albumsJson.add({
        'name': album.name,
        'assetChecksums': albumAssets.map((a) => a.checksum).toList(),
      });
    }

    final export = {
      'exportedAt': DateTime.now().toIso8601String(),
      'assets': assetsJson,
      'albums': albumsJson,
    };

    final file = File(p.join(backupRoot.path, 'metadata.json'));
    final jsonBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(export));

    if (encryptionKey == null) {
      await file.writeAsBytes(jsonBytes);
      return;
    }
    // Die Klartext-Zwischendatei liegt im privaten Temp-Ordner der App
    // (unter macOS im Sandbox-Container), NICHT im Sicherungsziel.
    //
    // Vorher stand sie neben der verschlüsselten Datei. Das Ziel ist aber
    // gerade der Ort, an dem nichts Lesbares landen soll – oft ein
    // USB-Stick oder eine Netzfreigabe. Dort enthielte die Datei für einen
    // Moment sämtliche Dateinamen, Beschreibungen, Schlagwörter und
    // Koordinaten im Klartext, und auf Flash-Speicher überlebt Gelöschtes
    // sein Löschen. Stürzte das Programm zwischen Schreiben und Löschen ab,
    // bliebe sie sogar dauerhaft liegen.
    final tempDir = await Directory.systemTemp.createTemp('pv_backup_meta_');
    final plainTemp = File(p.join(tempDir.path, 'metadata.json'));
    await plainTemp.writeAsBytes(jsonBytes);
    try {
      await VaultCrypto.encryptFile(plainTemp, file, encryptionKey);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  /// Schreibt den verpackten Backup-Master-Key als kleine, PIN/Passphrase-
  /// geschützte Datei INS Backup selbst (nicht nur lokal in der
  /// App-Datenbank) – nur dadurch lässt sich ein verschlüsseltes Backup auf
  /// einem komplett anderen Rechner allein mit der Passphrase entschlüsseln.
  Future<void> _writeKeyEnvelope(Directory backupRoot) async {
    final row = await _db.backupSettingsRow();
    final kdfSalt = row?.kdfSalt;
    final nonce = row?.wrappedMasterKeyNonce;
    final wrapped = row?.wrappedMasterKey;
    if (kdfSalt == null || nonce == null || wrapped == null) return;
    final envelope = {
      'kdfSalt': base64Encode(kdfSalt),
      'nonce': base64Encode(nonce),
      'wrapped': base64Encode(wrapped),
    };
    final file = File(p.join(backupRoot.path, 'vault.key'));
    await file.writeAsString(jsonEncode(envelope));
  }

  /// Stellt eine Bibliothek aus einem zuvor erstellten Backup-Ordner wieder
  /// her: importiert alle gefundenen Originaldateien (Duplikate werden über
  /// die Prüfsumme automatisch übersprungen) und wendet anschließend, sofern
  /// vorhanden, `metadata.json` an (Favoriten, Beschreibung, Tags, Alben).
  /// Personen/Gesichter werden bewusst NICHT wiederhergestellt, da Immichs
  /// bzw. dieser Apps Gesichts-Crops nicht Teil des Backups sind.
  ///
  /// Ist das Backup verschlüsselt (erkennbar an einer `vault.key`-Datei im
  /// Backup-Ordner), wird [passphrase] benötigt – der Schlüssel dafür kommt
  /// ausschließlich aus dieser Datei, nicht aus der lokalen App-Datenbank,
  /// damit die Wiederherstellung auch auf einem fremden Rechner funktioniert.
  Stream<BackupProgress> restoreFromBackup(
    String backupRootPath,
    ImportService importService, {
    String? passphrase,
  }) async* {
    final keyFile = File(p.join(backupRootPath, 'vault.key'));
    SecretKey? decryptionKey;
    if (await keyFile.exists()) {
      if (passphrase == null) {
        throw const BackupBrauchtPassphrase();
      }
      final envelope = jsonDecode(await keyFile.readAsString()) as Map<String, dynamic>;
      decryptionKey = await VaultCrypto.unwrapMasterKey(
        passphrase,
        kdfSalt: base64Decode(envelope['kdfSalt'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        wrapped: base64Decode(envelope['wrapped'] as String),
      );
    }

    // Metadaten früh einlesen: Beim neuen, namenlosen Format sind sie die
    // EINZIGE Quelle dafür, welche Dateien es gibt und welche Endung sie
    // hatten – aus dem Ordner selbst lässt sich das nicht mehr ablesen.
    final metadataFile = File(p.join(backupRootPath, 'metadata.json'));
    List<Map<String, dynamic>> metaAssets = const [];
    File? entschluesselteMetadaten;
    File? entschluesselterSchnappschuss;
    // Ab hier kann eine entschlüsselte Klartext-Kopie der Metadaten im
    // Temp-Verzeichnis liegen (Dateinamen, GPS, Tags, Beschreibungen aller
    // gesicherten Fotos). Sie MUSS in jedem Fall wieder verschwinden –
    // auch wenn eine einzelne Datei defekt ist und die Schleife wirft, und
    // vor allem, wenn der Aufrufer den Stream vorzeitig abbestellt (Nutzer
    // bricht die Wiederherstellung ab). Dart führt das `finally` eines
    // async*-Generators auch bei Abbruch am `yield` aus – deshalb umschließt
    // es hier den GESAMTEN weiteren Ablauf und nicht nur das Anwenden der
    // Metadaten am Ende (Audit-Fund).
    try {
      if (await metadataFile.exists()) {
        File zuLesen = metadataFile;
        if (decryptionKey != null) {
          entschluesselteMetadaten = File(
              p.join(Directory.systemTemp.path, 'photovault_restore_${_uuid.v4()}.json'));
          await VaultCrypto.decryptFile(metadataFile, entschluesselteMetadaten, decryptionKey);
          zuLesen = entschluesselteMetadaten;
        }
        try {
          final inhalt = jsonDecode(await zuLesen.readAsString()) as Map<String, dynamic>;
          metaAssets = (inhalt['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        } catch (e) {
          // Beschädigte Metadaten dürfen den Restore NICHT abbrechen: Beim
          // alten Format werden die Dateien ohnehin über ihre Endung
          // gefunden, die Fotos kommen also trotzdem zurück (nur ohne
          // Favoriten/Tags). Beim neuen, namenlosen Format sind sie die
          // einzige Quelle – dann bleibt die Liste eben leer, statt zu
          // scheitern.
          debugPrint('metadata.json unlesbar, Restore läuft ohne Metadaten weiter: $e');
        }
      }

      // Was wiederhergestellt werden soll: Pfad plus die Endung, die die Datei
      // im Original hatte (beim neuen Format steckt sie nicht mehr im Namen).
      final files = <({String pfad, String endung})>[];

      final datenOrdner = Directory(p.join(backupRootPath, VerschluesselteNamen.ordner));
      final originalsIn = Directory(p.join(backupRootPath, 'originals'));

      if (await datenOrdner.exists() && decryptionKey != null) {
        // Neues Format: flach und namenlos. Die Zuordnung entsteht durch
        // Nachrechnen des Namens aus der Prüfsumme – ohne Schlüssel ist das
        // nicht möglich, genau das ist der Zweck.
        for (final eintrag in metaAssets) {
          final pruefsumme = eintrag['checksum'] as String?;
          if (pruefsumme == null) continue;
          final name = await VerschluesselteNamen.fuerPruefsumme(pruefsumme, decryptionKey);
          final datei = File(p.join(datenOrdner.path, name));
          if (await datei.exists()) {
            files.add((
              pfad: datei.path,
              endung: p.extension((eintrag['originalFileName'] as String?) ?? '.jpg'),
            ));
          }
        }
      } else if (await originalsIn.exists()) {
        // Altes Format: nach Endung durchsuchen. Bei verschlüsselten Backups
        // sind die Bytes zwar Chiffretext, die Endung im Pfad blieb aber die
        // des Originals.
        await for (final entity in originalsIn.list(recursive: true, followLinks: false)) {
          if (entity is File && importService.isSupported(entity.path)) {
            files.add((pfad: entity.path, endung: p.extension(entity.path)));
          }
        }
      } else {
        // Fallback: falls direkt der "originals"-Ordner selbst ausgewählt wurde.
        for (final f in await importService.collectSupportedFilesInFolder(backupRootPath)) {
          files.add((pfad: f, endung: p.extension(f)));
        }
      }

      var done = 0;
      yield BackupProgress(0, files.length);
      for (final eintrag in files) {
        final filePath = eintrag.pfad;
        if (decryptionKey == null) {
          await importService.importFile(filePath);
        } else {
          // In eine temporäre Datei mit derselben Endung entschlüsseln (für
          // Bild-/Videotyp-Erkennung beim Import), dann importieren und die
          // Zwischenkopie sofort wieder löschen. Der ursprüngliche Dateiname
          // ist ohnehin nur die Asset-UUID (siehe StoragePaths) – der echte,
          // von Menschen lesbare Name kommt gleich aus metadata.json über den
          // Prüfsummen-Abgleich zurück, unabhängig vom Namen dieser
          // Zwischenkopie.
          final tempFile = File(p.join(
            Directory.systemTemp.path,
            'photovault_restore_${_uuid.v4()}${eintrag.endung}',
          ));
          try {
            await VaultCrypto.decryptFile(File(filePath), tempFile, decryptionKey);
            await importService.importFile(tempFile.path);
          } finally {
            if (await tempFile.exists()) await tempFile.delete();
          }
        }
        done++;
        yield BackupProgress(done, files.length, currentFile: p.basename(filePath));
      }

      // Metadaten anwenden – die Datei wurde oben bereits (ggf. entschlüsselt)
      // eingelesen, deshalb hier keine zweite Entschlüsselung.
      if (await metadataFile.exists()) {
        await _applyMetadataExport(entschluesselteMetadaten ?? metadataFile);
      }

      // Und zuletzt alles, was in keiner Beilage steht: Namen an
      // Gesichtern, Stammbaum, Reisen, Aktivitäten, Spuren, gespeicherte
      // Suchen. Die automatische Sicherung legt dafür seit jeher einen
      // verschlüsselten Schnappschuss der Datenbank ab – bis zur
      // 19. Prüfrunde las ihn nur der Prüfstand.
      final schnappschuss = File(p.join(backupRootPath, 'library.sqlite.enc'));
      if (decryptionKey != null && await schnappschuss.exists()) {
        // Dieselbe Sorgfalt wie bei den Metadaten oben: Ab hier liegt eine
        // vollständige Klartext-Datenbank im Temp-Verzeichnis, und die muss
        // in jedem Fall wieder verschwinden – auch bei einem Abbruch.
        entschluesselterSchnappschuss = File(p.join(Directory.systemTemp.path,
            'photovault_restore_${_uuid.v4()}.sqlite'));
        try {
          await VaultCrypto.decryptFile(
              schnappschuss, entschluesselterSchnappschuss, decryptionKey);
          final zeilen =
              await uebernimmAusSchnappschuss(entschluesselterSchnappschuss);
          yield BackupProgress(files.length, files.length,
              uebernommeneZeilen: zeilen);
          // Die Ausschnitte zu den zurückgekommenen Gesichtern neu
          // zeichnen – sonst stünden alle Namen da und kein Bild dazu.
          yield* _zeichneAusschnitteNach();
        } catch (e) {
          // Ein unlesbarer Schnappschuss darf die Wiederherstellung nicht
          // entwerten – die Fotos und ihre Beilagen sind zu diesem
          // Zeitpunkt längst zurück.
          debugPrint('Schnappschuss nicht übernommen: $e');
        }
      }
    } finally {
      if (entschluesselteMetadaten != null && await entschluesselteMetadaten.exists()) {
        await entschluesselteMetadaten.delete();
      }
      if (entschluesselterSchnappschuss != null &&
          await entschluesselterSchnappschuss.exists()) {
        await entschluesselterSchnappschuss.delete();
      }
    }
  }

  /// Die Tabellen, die aus dem Datenbank-Schnappschuss übernommen werden –
  /// in dieser Reihenfolge, weil spätere auf frühere zeigen.
  ///
  /// **Warum es diese Liste überhaupt gibt.** `metadata.json` trägt, was
  /// sich als Datei-Beilage weitergeben lässt: Beschreibung, Sterne,
  /// Farbmarke, Ort, Schlagwörter, Alben. Alles andere – die Namen an den
  /// Gesichtern, der Stammbaum, Reisen, Aktivitäten, Spuren, gespeicherte
  /// Suchen – steht nur in der Datenbank. Die automatische Sicherung legt
  /// von der längst einen verschlüsselten Schnappschuss ab und beschreibt
  /// ihn in ihrer eigenen Doku als das, „aus dem sich bei Datenverlust
  /// alles außer den Rohdateien wiederherstellen lässt". Gelesen hat ihn
  /// bis zur 19. Prüfrunde **nichts** – der einzige Wiederherstellungsweg
  /// der App wertete ausschliesslich `metadata.json` aus. Gemessen an einer
  /// gewachsenen Bibliothek hiess das: 39 Personen und 2045 benannte
  /// Gesichter, 20 Verwandtschaften, 2 Reisen mit 423 Zuordnungen und 15
  /// Aktivitäten mit 485 Zuordnungen kamen nicht zurück.
  ///
  /// **Was bewusst fehlt.** Alles, was auf eine Datei zeigt, die in der
  /// Sicherung gar nicht liegt (Objektmasken, Videozuschnitte), und alles,
  /// was der Zielbibliothek gehört und nicht der gesicherten
  /// (`backup_settings` mit ihrem Schlüssel, `privacy_settings`,
  /// `restore_jobs`, `backup_records`). Die Einbettungen bleiben ebenfalls
  /// draussen: Sie sind der grösste Posten und rechnen sich von selbst neu.
  static const uebernommeneTabellen = <String>[
    'people',
    'faces',
    'face_match_feedback',
    'person_beziehungen',
    'lebensereignisse',
    'reisen',
    'reise_aufnahmen',
    'verworfene_reisen',
    'aktivitaeten',
    'aktivitaet_aufnahmen',
    'verworfene_aktivitaeten',
    'ortsmarken',
    'spuren',
    'spurpunkte',
    'saved_searches',
    'duplikat_ausnahmen',
    'camera_presets',
    'camera_preset_tags',
    'automation_rules',
    'automation_rule_tags',
    'develop_presets',
    'export_presets',
    'develop_settings',
    'develop_history',
    'ai_tag_vocabulary',
  ];

  /// Übernimmt aus dem entschlüsselten Schnappschuss alles, was
  /// `metadata.json` nicht trägt.
  ///
  /// **Zugeordnet wird über die Prüfsumme**, nicht über die Kennung: Der
  /// Restore importiert jede Datei neu und vergibt dabei neue Kennungen.
  /// Eine Zeile, deren Aufnahme in der Zielbibliothek fehlt (weil die Datei
  /// nicht in der Sicherung lag oder nicht lesbar war), wird ausgelassen
  /// statt auf eine fremde Aufnahme gelegt.
  ///
  /// **Die Spalten kommen aus dem Schema**, nicht aus einer zweiten Liste:
  /// Eine ältere Sicherung kennt weniger Spalten als die laufende Fassung,
  /// und eine von Hand gepflegte Aufzählung wäre die naheliegendste Art,
  /// dass eine neue Spalte still verlorengeht.
  @visibleForTesting
  Future<int> uebernimmAusSchnappschuss(File schnappschuss) async {
    final quelle = sqlite3.open(schnappschuss.path, mode: OpenMode.readOnly);
    try {
      final zielSpalten = <String, Set<String>>{};
      for (final tabelle in _db.allTables) {
        zielSpalten[tabelle.actualTableName] = {
          for (final s in tabelle.$columns) s.name,
        };
      }

      // Prüfsumme -> Kennung in dieser Bibliothek.
      final nachPruefsumme = <String, String>{
        for (final a in await _db.select(_db.assets).get()) a.checksum: a.id,
      };
      // Kennung im Schnappschuss -> Kennung hier.
      final assetZuordnung = <String, String>{};
      for (final z in quelle.select('SELECT id, checksum FROM assets')) {
        final neu = nachPruefsumme[z['checksum'] as String?];
        if (neu != null) assetZuordnung[z['id'] as String] = neu;
      }

      var uebernommen = 0;
      // **Eine Klammer um alles**, und das ist keine Feinheit: Ohne sie
      // ist jede der Zehntausenden Zeilen eine eigene Transaktion mit
      // eigenem fsync. An dieser Bibliothek gemessen (24.187 Zeilen):
      // 10,1 s ohne, 0,6 s mit. Die Absicherung je Zeile bleibt - SQLite
      // nimmt eine gescheiterte Anweisung für sich zurück, die Klammer
      // steht danach unverändert offen.
      await _db.transaction(() async {
      for (final tabelle in uebernommeneTabellen) {
        final erlaubt = zielSpalten[tabelle];
        if (erlaubt == null) continue;
        final vorhanden = quelle.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
            [tabelle]);
        if (vorhanden.isEmpty) continue;

        // Nur Spalten, die es hier UND dort gibt – eine ältere Sicherung
        // hat weniger, eine neuere könnte mehr haben.
        final spalten = [
          for (final z in quelle.select('PRAGMA table_info("$tabelle")'))
            if (erlaubt.contains(z['name'] as String)) z['name'] as String,
        ];
        if (spalten.isEmpty) continue;
        final hatAssetId = spalten.contains('asset_id');

        final liste = spalten.map((s) => '"$s"').join(', ');
        final platzhalter = List.filled(spalten.length, '?').join(', ');
        final befehl =
            'INSERT OR IGNORE INTO "$tabelle" ($liste) VALUES ($platzhalter)';

        for (final zeile in quelle.select('SELECT * FROM "$tabelle"')) {
          final werte = <Object?>[];
          var ueberspringen = false;
          for (final spalte in spalten) {
            var wert = zeile[spalte];
            if (spalte == 'asset_id' && hatAssetId) {
              wert = assetZuordnung[wert];
              if (wert == null) {
                ueberspringen = true;
                break;
              }
            }
            werte.add(wert);
          }
          if (ueberspringen) continue;
          try {
            await _db.customInsert(befehl,
                variables: [for (final w in werte) Variable(w)]);
            uebernommen++;
          } catch (e) {
            // Je Zeile abgesichert – eine Zeile, die hier nicht hineinpasst
            // (ein Fremdschlüssel auf eine ausgelassene Aufnahme etwa), darf
            // die Wiederherstellung nicht abbrechen.
            debugPrint('Zeile aus $tabelle nicht übernommen: $e');
          }
        }
      }
      // Und die Marke „schon nach Gesichtern durchsucht" mit.
      //
      // Ohne sie liefe die Hintergrundanalyse über genau die Aufnahmen, für
      // die gerade Gesichter zurückgekommen sind, fände dieselben Köpfe
      // erneut und legte sie ein zweites Mal an – diesmal ohne Namen. Die
      // Marke steht im Schnappschuss und wird deshalb von dort genommen,
      // nicht geraten: Eine Aufnahme, die dort nie durchsucht wurde, soll
      // auch hier noch durchsucht werden.
      // `markFacesScanned` nimmt eine Liste - hier stand sie je Aufnahme
      // einzeln da, also achttausend Anweisungen für eine einzige.
      final durchsucht = [
        for (final z in quelle.select(
            'SELECT id, faces_scanned FROM assets WHERE faces_scanned = 1'))
          if (assetZuordnung[z['id'] as String] case final neueId?) neueId,
      ];
      if (durchsucht.isNotEmpty) await _db.markFacesScanned(durchsucht);
      });

      return uebernommen;
    } finally {
      quelle.close();
    }
  }

  /// Zeichnet die Gesichtsausschnitte neu, die mit dem Schnappschuss
  /// zurückkamen.
  ///
  /// **Warum sie nicht in der Sicherung liegen.** Gesichert werden die
  /// Originale, nichts Abgeleitetes – Miniaturen, Vorschauen und
  /// Ausschnitte entstehen beim Import neu. Der Ausschnitt aber ist das,
  /// was man in der Personenübersicht *sieht*: Ohne ihn kämen zwar alle
  /// Namen zurück, die Übersicht wäre aber eine Wand aus leeren Kacheln.
  ///
  /// **Kein Modell nötig.** Der Kasten steht in der wiederhergestellten
  /// Zeile; [FaceEngineService.cropFaceImage] ist eine reine Bildoperation.
  /// Es wird also nicht neu erkannt (das ergäbe andere Gesichter und damit
  /// Doppelungen), sondern nur nachgezeichnet.
  ///
  /// Ein Foto wird höchstens einmal dekodiert, auch wenn mehrere Gesichter
  /// darauf sind.
  Stream<BackupProgress> _zeichneAusschnitteNach() async* {
    // Gefragt wird die Platte, nicht die Spalte: `cropRelativePath` steht
    // auch bei den zurückgespielten Zeilen da, nur die Datei dahinter fehlt.
    final nachAsset = <String, List<FaceData>>{};
    for (final g in await _db.select(_db.faces).get()) {
      final pfad = g.cropRelativePath;
      if (pfad == null) continue;
      if (await _paths.absolute(pfad).exists()) continue;
      nachAsset.putIfAbsent(g.assetId, () => []).add(g);
    }
    if (nachAsset.isEmpty) return;

    var done = 0;
    yield BackupProgress(0, nachAsset.length, ausschnitteNeu: true);
    for (final eintrag in nachAsset.entries) {
      try {
        final asset = await _db.assetById(eintrag.key);
        if (asset != null) {
          final datei = _paths
              .absolute(asset.previewRelativePath ?? asset.relativePath);
          if (await datei.exists()) {
            final bild = await compute(_dekodiere, await datei.readAsBytes());
            if (bild != null) {
              for (final gesicht in eintrag.value) {
                final ausschnitt = FaceEngineService.cropFaceImage(
                    bild,
                    DetectedFace(gesicht.boxX, gesicht.boxY, gesicht.boxW,
                        gesicht.boxH, 1.0));
                final ziel = _paths.faceRelativePath(gesicht.id);
                await FaceEngineService.saveFaceCrop(
                    ausschnitt, _paths.absolute(ziel));
                await _db.setzeGesichtsausschnitt(gesicht.id, ziel,
                    schaerfe: gesichtsschaerfe(ausschnitt));
              }
            }
          }
        }
      } catch (e) {
        // Je Foto abgesichert: Eine Datei, die sich nicht lesen lässt, darf
        // die übrigen Ausschnitte nicht mitnehmen.
        debugPrint('Gesichtsausschnitte für ${eintrag.key} nicht erneuert: $e');
      }
      done++;
      yield BackupProgress(done, nachAsset.length, ausschnitteNeu: true);
    }
  }

  /// Wendet den Inhalt einer `metadata.json` an. Läuft pro Asset-/Album-
  /// Eintrag in einem eigenen Try/Catch: ein einzelner unerwarteter/defekter
  /// Eintrag (z.B. aus einem von Hand bearbeiteten oder von einer älteren
  /// App-Version stammenden Backup) bricht damit nicht den gesamten Restore
  /// ab, sondern wird übersprungen.
  Future<void> _applyMetadataExport(File metadataFile) async {
    final Map<String, dynamic> content;
    try {
      content = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('metadata.json konnte nicht gelesen werden, überspringe Metadaten-Import: $e');
      return;
    }

    final assetsJson = (content['assets'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    final byChecksum = <String, String>{}; // checksum -> assetId in dieser DB
    for (final row in await _db.select(_db.assets).get()) {
      byChecksum[row.checksum] = row.id;
    }

    // Auch hier eine Klammer: je Eintrag bis zu sieben Anweisungen und
    // je Schlagwort zwei weitere. An 1000 Aufnahmen gemessen: 4,1 s
    // ohne, 0,4 s mit.
    await _db.transaction(() async {
    for (final entry in assetsJson) {
      try {
        final checksum = entry['checksum'] as String?;
        final assetId = checksum != null ? byChecksum[checksum] : null;
        if (assetId == null) continue;
        // Der Reimport aus dem Backup-Ordner kennt nur den Pfad
        // originals/{yyyy}/{mm}/{assetId}.ext und übernimmt dessen Basename
        // (also die Asset-UUID) als originalFileName – hier den echten,
        // von Menschen lesbaren Namen aus metadata.json wiederherstellen.
        // p.basename() schützt vor einer präparierten metadata.json (z.B.
        // aus einem fremden/geteilten Backup-Ordner), die einen Namen mit
        // Pfad-Traversal ("../../...") enthält – der wiederhergestellte Name
        // wird später beim Exportieren 1:1 als Ziel-Dateiname verwendet
        // (siehe ExportService).
        final originalFileName = entry['originalFileName'] as String?;
        if (originalFileName != null && originalFileName.isNotEmpty) {
          await _db.setOriginalFileName(assetId, p.basename(originalFileName));
        }
        if (entry['isFavorite'] == true) {
          await _db.setFavorite(assetId, true);
        }
        if (entry['description'] is String && (entry['description'] as String).isNotEmpty) {
          await _db.setDescription(assetId, entry['description'] as String);
        }
        // Fehlen die Felder (Sicherung vor Fassung 2.3.0), bleibt es beim
        // Vorgabewert - eine ältere Sicherung setzt also keine Null
        // über etwas, das im Ziel schon steht.
        if (entry['rating'] is int && entry['rating'] as int > 0) {
          await _db.setRating(assetId, entry['rating'] as int);
        }
        if (entry['colorLabel'] is String) {
          await _db.setColorLabel(assetId, entry['colorLabel'] as String);
        }
        // Beides zusammen oder gar nicht: Eine Koordinate ohne die andere
        // ist kein Ort, sondern eine halbe Zahl.
        if (entry['latitude'] is num && entry['longitude'] is num) {
          await _db.setLocation(assetId, (entry['latitude'] as num).toDouble(),
              (entry['longitude'] as num).toDouble());
        }
        if (entry['locationCity'] is String) {
          await _db.setLocationNames(
            assetId,
            country: entry['locationCountry'] as String?,
            state: entry['locationState'] as String?,
            city: entry['locationCity'] as String,
          );
        }
        // Fehlt 'kiTags' (Sicherung vor Fassung 56), bleibt die Menge
        // leer und alles kommt als Handvergabe zurück: Lieber ein
        // Schlagwort zu viel behalten als eines zu Unrecht löschbar
        // machen.
        final kiTags = {
          for (final t in (entry['kiTags'] as List<dynamic>? ?? []))
            if (t is String) t,
        };
        for (final tag in (entry['tags'] as List<dynamic>? ?? [])) {
          await _db.tagAsset(assetId, tag as String,
              quelle: kiTags.contains(tag) ? Tagquelle.ki : Tagquelle.hand);
        }
      } catch (e) {
        debugPrint('Metadaten-Eintrag konnte nicht angewendet werden, überspringe: $e');
      }
    }
    });

    final albumsJson = (content['albums'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    for (final albumEntry in albumsJson) {
      try {
        final name = albumEntry['name'] as String? ?? 'Wiederhergestelltes Album';
        final checksums = (albumEntry['assetChecksums'] as List<dynamic>? ?? []).cast<String>();
        final assetIds = checksums.map((c) => byChecksum[c]).whereType<String>().toList();
        if (assetIds.isEmpty) continue;
        final albumId = const Uuid().v4();
        await _db.createAlbum(AlbumsCompanion.insert(id: albumId, name: name, createdAt: DateTime.now()));
        await _db.addAssetsToAlbum(albumId, assetIds);
      } catch (e) {
        debugPrint('Album-Eintrag konnte nicht wiederhergestellt werden, überspringe: $e');
      }
    }
  }

  // -----------------------------------------------------------------------
  // Automatisches Backup
  // -----------------------------------------------------------------------

  static const _autoBackupFolderName = 'PhotoVault-AutoBackup';

  /// Automatisches, verschlüsseltes Backup – läuft nur, während die App
  /// offen ist (kein Hintergrunddienst, siehe LibraryState.runAutoBackupIfDue).
  /// Anders als [performBackup] sichert es zusätzlich einen konsistenten
  /// Schnappschuss der kompletten Datenbank (nicht nur eine Teilmenge der
  /// Felder in metadata.json) – das automatische Backup soll eine
  /// vollständige, eigenständige Kopie des Bibliothek-Zustands sein
  /// ("Source of Truth"), aus der sich bei Datenverlust alles außer den
  /// Rohdateien selbst wiederherstellen lässt (Gesichter, Personen, Orte,
  /// Tags, Alben, Favoriten, gesperrt-Status – alles, was in der Datenbank
  /// steht).
  ///
  /// WICHTIG: löscht am Zielort NIE etwas. Ein automatisches Backup, das
  /// lokale Löschungen nachvollzieht, wäre kein verlässliches Sicherheitsnetz
  /// mehr (eine versehentliche oder böswillige lokale Löschung würde sonst
  /// das Backup mitreißen). Dateien werden nur ergänzt, der DB-Schnappschuss
  /// nur ersetzt (er beschreibt ohnehin immer den kompletten aktuellen
  /// Zustand, nicht nur eine Differenz).
  /// [maxBytesPerRun] siehe [performBackup] – hier besonders wichtig, weil
  /// das automatische Backup typischerweise auf einen Cloud-Sync-Ordner
  /// zeigt und ungefragt im Hintergrund läuft.
  Stream<BackupProgress> performAutoBackup(
    String destinationRootPath,
    SecretKey encryptionKey, {
    int maxBytesPerRun = 0,
  }) async* {
    final backupRoot = Directory(p.join(destinationRootPath, _autoBackupFolderName));
    final originalsOut = Directory(p.join(backupRoot.path, 'originals'));
    await originalsOut.create(recursive: true);

    await _writeEncryptedDatabaseSnapshot(backupRoot, encryptionKey);
    await _writeKeyEnvelope(backupRoot);

    final staging = _festesZwischenlager ??
        await Directory.systemTemp.createTemp('pv_autobackup_stage_');
    final pending = await _db.assetsNotAutoBackedUp();
    var done = 0;
    var geschriebeneBytes = 0;
    var abgebrochenWegenLimit = false;
    final autoBackedUpIds = <String>[];
    var fehlgeschlagen = 0;
    yield BackupProgress(0, pending.length);

    try {
      for (final asset in pending) {
        if (maxBytesPerRun > 0 && geschriebeneBytes >= maxBytesPerRun) {
          abgebrochenWegenLimit = true;
          break;
        }
        final source = _paths.absolute(asset.relativePath);
        // Je Datei abgesichert – hier wiegt es schwerer als beim manuellen
        // Lauf: Dieser läuft ungefragt im Hintergrund, ein Abbruch fiele
        // also niemandem auf.
        try {
          if (await source.exists()) {
            // Automatische Backups sind immer verschlüsselt – daher stets die
            // flache, namenlose Ablage (siehe VerschluesselteNamen).
            final target = File(p.join(backupRoot.path, VerschluesselteNamen.ordner,
                await VerschluesselteNamen.fuerPruefsumme(asset.checksum, encryptionKey)));
            await target.parent.create(recursive: true);
            await _ueberZwischendatei(
              zwischenlager: staging,
              ziel: target,
              quellGroesse: await source.length(),
              schreibe: (zwischen) =>
                  VaultCrypto.encryptFile(source, zwischen, encryptionKey),
            );
            geschriebeneBytes += await target.length();
          }
          autoBackedUpIds.add(asset.id);
        } catch (e) {
          fehlgeschlagen++;
          debugPrint('Automatische Sicherung von ${asset.originalFileName} '
              'fehlgeschlagen: $e');
        }
        done++;
        yield BackupProgress(done, pending.length, currentFile: asset.originalFileName);
      }
    } finally {
      if (_festesZwischenlager == null) {
        try {
          await staging.delete(recursive: true);
        } catch (e) {
          // Kein Grund, die Sicherung scheitern zu lassen - aber es muss
          // gesagt werden: Im Zwischenlager liegen die Dateien im
          // KLARTEXT. Bleibt es stehen, bleibt der Klartext liegen, und
          // ein stiller Fehlschlag hiesse, dass niemand davon erfaehrt.
          debugPrint('Zwischenlager ${staging.path} nicht geloescht: $e - '
              'es enthaelt unverschluesselte Dateien.');
        }
      }
    }

    if (autoBackedUpIds.isNotEmpty) {
      await _db.markAutoBackedUp(autoBackedUpIds);
    }

    if (abgebrochenWegenLimit) {
      yield BackupProgress(done, pending.length,
          grenzeOffen: pending.length - done);
    }
    if (fehlgeschlagen > 0) {
      yield BackupProgress(done, pending.length, fehlgeschlagen: fehlgeschlagen);
    }
  }

  /// Erzeugt über SQLites `VACUUM INTO` einen konsistenten Schnappschuss der
  /// laufenden Datenbank (funktioniert korrekt auch während die App
  /// gleichzeitig weiterschreibt, anders als ein simples Kopieren der
  /// `.sqlite`-Datei, das einen halbgeschriebenen Zustand einfangen könnte)
  /// und verschlüsselt ihn anschließend.
  Future<void> _writeEncryptedDatabaseSnapshot(Directory backupRoot, SecretKey encryptionKey) async {
    final snapshotPath = p.join(
      Directory.systemTemp.path,
      'photovault_db_snapshot_${_uuid.v4()}.sqlite',
    );
    final snapshotFile = File(snapshotPath);
    try {
      await _db.customStatement('VACUUM INTO ?', [snapshotPath]);
      entferneGesperrteAus(snapshotPath);
      final target = File(p.join(backupRoot.path, 'library.sqlite.enc'));
      await VaultCrypto.encryptFile(snapshotFile, target, encryptionKey);
    } finally {
      if (await snapshotFile.exists()) await snapshotFile.delete();
    }
  }
}

/// Ableitung der Dateinamen für verschlüsselte Backups.
///
/// Bei einem verschlüsselten Backup sollen die Dateien im Zielordner nichts
/// über den Inhalt verraten. Bisher blieb trotz verschlüsselter Bytes
/// sichtbar: der Aufnahmezeitraum (Ordner nach Jahr/Monat), das Dateiformat
/// (Endung) und über die Prüfsumme im Namen sogar, OB eine bestimmte,
/// anderweitig bekannte Datei enthalten ist.
///
/// Deshalb liegen verschlüsselte Backups flach unter `data/` mit einem
/// Namen, der sich nur MIT dem Schlüssel berechnen lässt: HMAC-SHA256 über
/// die Prüfsumme des Fotos. Deterministisch, damit ein erneuter Lauf
/// dieselbe Datei überschreibt statt eine zweite anzulegen.
class VerschluesselteNamen {
  VerschluesselteNamen._();

  /// Unterordner für die verschlüsselten Dateien.
  static const ordner = 'data';

  static Future<String> fuerPruefsumme(String pruefsumme, SecretKey schluessel) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(pruefsumme),
      secretKey: schluessel,
    );
    return mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Streicht alle gesperrten Aufnahmen aus einem Datenbank-Schnappschuss.
///
/// **Warum das sein muss.** Die 16. Prüfrunde fand, dass `metadata.json`
/// auch die Aufnahmen im gesperrten Ordner beschrieb – Dateinamen,
/// Beschreibungen, Schlagwörter im Klartext, in einer Datei, die
/// typischerweise in einem Cloud-Ordner liegt. Behoben wurde das dort.
/// Zwanzig Zeilen weiter schreibt dieselbe Sicherung einen Schnappschuss
/// der **kompletten** Datenbank, und in dem standen dieselben Zeilen
/// weiterhin: Dateiname, Ort, Beschreibung, Schlagwörter und über die
/// Gesichter sogar die Namen der abgebildeten Personen. Verschlüsselt zwar
/// – aber mit der Sicherungs-Passphrase, nicht mit dem PIN. Der
/// Einstellungstext sagt zum gesperrten Ordner ausdrücklich, er blende die
/// Fotos „überall sonst (Timeline, Suche, Alben, Personen, Karte, Backup)"
/// aus.
///
/// **Aus dem Schema abgeleitet, nicht abgeschrieben.** Welche Tabellen an
/// einer Aufnahme hängen, steht in `PRAGMA table_info` – jede Tabelle mit
/// einer Spalte `asset_id`. Eine Liste von Hand wäre die naheliegendste
/// Art, dass eine später hinzugekommene Tabelle vergessen wird; genau
/// diese Form hatte der Fund, der hier steht.
void entferneGesperrteAus(String schnappschussPfad) {
  final db = sqlite3.open(schnappschussPfad);
  try {
    final gesperrte = db
        .select('SELECT id FROM assets WHERE is_locked = 1')
        .map((z) => z['id'] as String)
        .toList();
    if (gesperrte.isEmpty) return;
    final platzhalter = List.filled(gesperrte.length, '?').join(',');
    for (final tabelle in _tabellenMitAssetId(db)) {
      db.execute(
          'DELETE FROM "$tabelle" WHERE asset_id IN ($platzhalter)', gesperrte);
    }
    db.execute('DELETE FROM assets WHERE is_locked = 1');
    // Ohne das bliebe der gelöschte Inhalt in den freigewordenen Seiten der
    // Datei stehen – lesbar für jeden, der die entschlüsselte Datei mit
    // einem Hexeditor öffnet, statt sie als Datenbank zu befragen.
    db.execute('VACUUM');
  } finally {
    db.close();
  }
}

List<String> _tabellenMitAssetId(Database db) {
  final namen = db
      .select("SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'")
      .map((z) => z['name'] as String);
  return [
    for (final name in namen)
      if (db
          .select('PRAGMA table_info("$name")')
          .any((z) => z['name'] == 'asset_id'))
        name,
  ];
}

/// Reine Top-Level-Funktion für `compute()` – wie `decodeImageBytes` in
/// library_state.dart.
img.Image? _dekodiere(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/native.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../protokoll.dart';
import 'import_service.dart';
import 'storage_paths.dart';
import 'vault_crypto.dart';
import 'xmp_writer.dart';

import 'backup_modelle.dart';
import 'backup_manifest.dart';
import 'backup_schnappschuss.dart';
import 'backup_restore.dart';
import 'backup_dateinamen.dart';
export 'backup_dateinamen.dart';
export 'backup_modelle.dart';
export 'backup_manifest.dart' show RestorePlan, RestoreDatei;

part 'backup_probe.dart';

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

  /// Wie viele Dateien der letzte automatische Lauf tatsächlich geschrieben
  /// hat – nur die, die im Ziel noch fehlten.
  int letzterLaufNeu = 0;

  /// Was im Ziel schon liegt, wird übersprungen (siehe [performBackup]).
  ///
  /// Nicht leer genügt: Geschrieben wird über eine Zwischendatei, die erst
  /// fertig unter diesem Namen ankommt (siehe [_ueberZwischendatei]).
  static Future<bool> _liegtImZiel(File ziel) async =>
      await ziel.exists() && await ziel.length() > 0;

  /// Ob [ziel] in einer **unverschlüsselten** Sicherung noch [asset] trägt –
  /// nicht nur, ob dort etwas liegt (#251).
  ///
  /// Verschlüsselt heisst jede Datei nach ihrer Prüfsumme, und eine neue
  /// Fassung bekommt von selbst einen neuen Namen. Unverschlüsselt liegt
  /// sie unter dem Pfad der Aufnahme. Ein im Editor gedrehtes JPEG behält
  /// diesen Pfad – und wurde nie neu kopiert: Im Ziel blieb die alte Datei,
  /// die Beilage nannte die neue Prüfsumme, die Wiederherstellungsprobe
  /// scheiterte, und eine Wiederherstellung brachte das Foto gar nicht
  /// zurück.
  ///
  /// Veraltet ist die Datei im Ziel, wenn die vorige Beilage für diesen
  /// Pfad eine andere Prüfsumme nannte ([frueher]) oder wenn ihre Grösse
  /// nicht zur Aufnahme passt. Die Grösse fängt die Sicherungen, die schon
  /// falsch stehen: Deren Beilage nennt bereits die neue Prüfsumme. Gemessen
  /// wird an der Datei der Bibliothek, falls sie hier liegt – verbunden
  /// fehlt sie oft, und sie zu holen hiesse, jede Aufnahme herunterzuladen;
  /// dann gilt die Grösse aus der Datenbank.
  Future<bool> _stimmtImZiel(
    AssetData asset,
    File ziel,
    Map<String, String> frueher,
  ) async {
    if (!await _liegtImZiel(ziel)) return false;
    final genannt = frueher[asset.relativePath];
    if (genannt != null && genannt != asset.checksum) return false;
    final hier = _paths.absolute(asset.relativePath);
    final groesse = await hier.exists()
        ? await hier.length()
        : asset.fileSizeBytes;
    return groesse <= 0 || await ziel.length() == groesse;
  }

  /// Was die vorige Beilage einer unverschlüsselten Sicherung je Pfad als
  /// Prüfsumme nannte; leer ohne lesbare Beilage.
  static Future<Map<String, String>> _fruehereAblage(
    Directory backupRoot,
  ) async {
    final f = File(p.join(backupRoot.path, 'metadata.json'));
    try {
      if (!await f.exists()) return const {};
      final m = BackupManifest.ausText(await f.readAsString());
      return {for (final a in m.aufnahmen) ?a.ablage: a.pruefsumme};
    } on Object {
      return const {};
    }
  }

  /// Legt eine veraltete Datei im unverschlüsselten Ziel beiseite, bevor
  /// die neue Fassung sie ersetzt – falls die Bibliothek ihren Inhalt nicht
  /// mehr hat.
  ///
  /// Wer mit einer Fassung vor 3.49.7 ein JPEG gedreht hat, hat das
  /// Original nur noch hier: Der Editor ersetzte es am Ort (#248), und die
  /// Sicherung schrieb danach nie neu. Ein stilles Überschreiben nähme ihm
  /// die letzte Kopie. Liegen dieselben Bytes dagegen als eigene Aufnahme
  /// vor (seit 3.49.7 bleibt das Original als Variante), wird nur ersetzt.
  /// Der neue Name trägt den Anfang der Prüfsumme; eine Wiederherstellung
  /// nach der Beilage übergeht die Datei, durchsehen lässt sie sich wie
  /// jede andere.
  Future<void> _bewahreVeraltete(File ziel) async {
    if (!await ziel.exists()) return;
    final summe = (await sha256.bind(ziel.openRead()).first).toString();
    if (await _db.checksumExists(summe)) return;
    final beiseite = File(
      '${p.withoutExtension(ziel.path)}.vorher-${summe.substring(0, 12)}'
      '${p.extension(ziel.path)}',
    );
    if (await beiseite.exists()) return;
    await ziel.rename(beiseite.path);
    protokoll(
      'Sicherung: ${p.basename(ziel.path)} beiseitegelegt als '
      '${p.basename(beiseite.path)}',
    );
  }

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
    final vermutlichZuGross =
        _zwischenlagerGrenze != null && quellGroesse >= _zwischenlagerGrenze!;

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
        protokoll(
          'Zwischenlager fasst $quellGroesse Bytes nicht ($e) – '
          'ab jetzt wird neben dem Ziel geschrieben',
        );
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

  /// Führt ein inkrementelles Backup durch: nur Originaldateien, die im
  /// Ziel noch fehlen, werden kopiert. Die Metadaten
  /// (Favoriten, Beschreibung, Tags, Alben) werden bei jedem Lauf komplett
  /// neu als `metadata.json` exportiert, damit der Cloud-Ordner immer den
  /// aktuellen Stand widerspiegelt.
  ///
  /// **Das Ziel entscheidet, nicht [Assets.backedUp]** (#242). Die
  /// Markierung sagt nur, dass eine Aufnahme irgendwann irgendwohin
  /// gesichert wurde. Solange sie die Auswahl traf, bekam ein zweiter
  /// Ordner – ein zweiter Stick, ein neues Cloud-Ziel, ein geleerter
  /// Ordner – kein einziges älteres Original, nur die `metadata.json`, die
  /// sie alle aufzählte. Nachgestellt: vier Fotos nach A, danach nach B
  /// gesichert, in B lag keines.
  ///
  /// [maxBytesPerRun] begrenzt, wie viel je Lauf ins Ziel geschrieben wird
  /// (0 oder negativ = unbegrenzt). Gedacht für Cloud-Sync-Ordner: Ohne
  /// Grenze landen bei der ersten Sicherung zigtausend Dateien auf einmal
  /// im Sync-Ordner und der Upload läuft tagelang. Was nicht mehr
  /// hineinpasst, fehlt weiter im Ziel und kommt beim nächsten Lauf dran.
  ///
  /// [markieren] setzt [Assets.backedUp] für die Anzeige. Nicht im
  /// verbundenen Rechner, dessen Kopie diese Spalte nicht schreiben darf
  /// (#206).
  Stream<BackupProgress> performBackup(
    String destinationRootPath, {
    SecretKey? encryptionKey,
    int maxBytesPerRun = 0,
    bool markieren = true,
  }) async* {
    final backupRoot = Directory(
      p.join(destinationRootPath, _backupFolderName),
    );
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
    BackupManifest? manifest;
    if (encryptionKey != null) {
      manifest = await _writeEncryptedDatabaseSnapshot(
        backupRoot,
        encryptionKey,
      );
    }

    // Zwischenlager – warum und was passiert, wenn es nicht reicht: siehe
    // [_ueberZwischendatei]. Geht es verloren (Neustart), entsteht kein
    // Schaden: Markiert wird erst nach erfolgreicher Ablage im Ziel.
    final staging =
        _festesZwischenlager ??
        await Directory.systemTemp.createTemp('pv_backup_stage_');

    final pending = await _db.assetsFuerSicherung();
    // Vor dem Lauf gelesen: Am Ende wird die Beilage neu geschrieben.
    final frueher = encryptionKey == null
        ? await _fruehereAblage(backupRoot)
        : const <String, String>{};
    // Verschlüsselt: flach unter data/ mit abgeleitetem Namen, damit
    // weder Aufnahmezeitraum noch Dateiformat sichtbar bleiben.
    // Unverschlüsselt: weiterhin die lesbare Ordnerstruktur, damit
    // sich so ein Backup auch ohne die App durchsehen lässt.
    Future<File> zielVon(AssetData asset) async => encryptionKey != null
        ? File(
            p.join(
              backupRoot.path,
              VerschluesselteNamen.ordner,
              await VerschluesselteNamen.fuerPruefsumme(
                asset.checksum,
                encryptionKey,
              ),
            ),
          )
        : File(
            p.join(
              originalsOut.path,
              asset.relativePath.replaceFirst(
                'originals${Platform.pathSeparator}',
                '',
              ),
            ),
          );
    Future<bool> aktuell(AssetData asset, File ziel) => encryptionKey == null
        ? _stimmtImZiel(asset, ziel, frueher)
        : _liegtImZiel(ziel);
    var done = 0;
    var totalBytes = 0;
    var geschriebeneBytes = 0;
    var abgebrochenWegenLimit = false;
    final backedUpIds = <String>[];
    var neu = 0;
    var fehlgeschlagen = 0;

    // XMP-Sidecars nur für unverschlüsselte Backups: bei einem verschlüsselten
    // Backup (encryptionKey != null) würde eine im Klartext danebenliegende
    // .xmp-Datei genau die Vertraulichkeit unterlaufen, die der Nutzer mit der
    // Backup-Passphrase gerade herstellen wollte.
    final tagsByAssetId = encryptionKey == null
        ? await _db.allTagNamesByAssetId()
        : null;
    // Aus demselben Grund: Ein Name neben einem verschlüsselten Foto sagt
    // mehr aus als das Foto selbst.
    final gesichterByAssetId = encryptionKey == null
        ? await _db.alleGesichtsregionen()
        : null;

    yield BackupProgress(0, pending.length);

    try {
      for (final asset in pending) {
        if (maxBytesPerRun > 0 && geschriebeneBytes >= maxBytesPerRun) {
          abgebrochenWegenLimit = true;
          break;
        }

        // Je Datei abgesichert: Vorher stand die ganze Schleife in einem
        // try/finally ohne catch – eine einzige Datei, die sich nicht
        // schreiben liess, brach den kompletten Lauf ab, und alles
        // dahinter wurde nie gesichert. Genau das passierte unter Flatpak
        // beim ersten Video über 789 MB.
        try {
          final target = await zielVon(asset);
          final schonDa = await aktuell(asset, target);
          // Erst nach der Frage ans Ziel geholt: In einer verbundenen Kopie
          // lädt [StoragePaths.bereit] ein fehlendes Original vom Server –
          // für jede Aufnahme, die schon gesichert ist, wäre das ein
          // Download für nichts.
          final source = schonDa
              ? null
              : await _paths.bereit(asset.relativePath);
          if (!schonDa && (source == null || !await source.exists())) {
            throw FileSystemException(
              'pv_backup_quelle_fehlt',
              asset.relativePath,
            );
          }
          if (source != null) {
            await target.parent.create(recursive: true);
            if (encryptionKey == null) await _bewahreVeraltete(target);

            final quellGroesse = await source.length();
            await _ueberZwischendatei(
              zwischenlager: staging,
              ziel: target,
              quellGroesse: quellGroesse,
              schreibe: (zwischen) async {
                if (encryptionKey != null) {
                  await VaultCrypto.encryptFile(
                    source,
                    zwischen,
                    encryptionKey,
                  );
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
            neu++;
          }
          // Nur, was noch nicht markiert ist: Die Liste geht als eine
          // einzige Anweisung hinaus, und jetzt kommt jeder Lauf an allen
          // Aufnahmen vorbei.
          if (!asset.backedUp) backedUpIds.add(asset.id);
        } catch (e) {
          // Fehlt weiter im Ziel und kommt beim nächsten Lauf wieder
          // dran. Gezählt wird sie trotzdem, sonst sähe ein Lauf mit
          // Ausfällen aus wie ein vollständiger.
          fehlgeschlagen++;
          protokoll(
            'Sicherung von ${asset.originalFileName} '
            'fehlgeschlagen: $e',
          );
        }
        done++;
        yield BackupProgress(
          done,
          pending.length,
          currentFile: asset.originalFileName,
        );
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
          protokoll(
            'Zwischenlager ${staging.path} nicht geloescht: $e - '
            'es enthaelt unverschluesselte Dateien.',
          );
        }
      }
    }

    final offen = abgebrochenWegenLimit
        ? await _fehlenImZiel(
            pending.skip(done),
            (a) async => aktuell(a, await zielVon(a)),
          )
        : 0;
    if (offen == 0) abgebrochenWegenLimit = false;

    if (backedUpIds.isNotEmpty && markieren) {
      await _db.markBackedUp(backedUpIds);
    }

    await _writeMetadataExport(
      backupRoot,
      encryptionKey: encryptionKey,
      stand: manifest,
      liegtImZiel: (asset) async => _liegtImZiel(await zielVon(asset)),
    );
    if (encryptionKey != null) {
      await _writeKeyEnvelope(backupRoot);
    }

    await _db.insertBackupRecord(
      BackupRecordsCompanion.insert(
        id: _uuid.v4(),
        performedAt: DateTime.now(),
        destinationPath: destinationRootPath,
        // Nur die tatsächlich gesicherten Dateien zählen, nicht die geplanten –
        // sonst behauptet der Bericht bei einem begrenzten Lauf mehr, als er
        // geschafft hat.
        fileCount: neu,
        totalBytes: totalBytes,
      ),
    );

    // Abschließende Meldung macht sichtbar, dass noch etwas aussteht –
    // sonst wirkt ein begrenzter Lauf wie ein vollständiges Backup.
    // Eine begrenzte oder unvollständige Sicherung ist noch keine
    // vollständig wiederherstellbare Generation.
    if (!abgebrochenWegenLimit && fehlgeschlagen == 0) {
      final probe = await pruefeWiederherstellung(
        backupRoot.path,
        schluessel: encryptionKey,
      );
      yield BackupProgress(
        done,
        pending.length,
        wiederherstellungsprobe: probe,
      );
    }

    if (abgebrochenWegenLimit) {
      yield BackupProgress(done, pending.length, grenzeOffen: offen);
    }
    // Nach der Mengenmeldung, damit sie das letzte Wort hat: Ausgelassene
    // Dateien sind die wichtigere Nachricht.
    if (fehlgeschlagen > 0) {
      yield BackupProgress(
        done,
        pending.length,
        fehlgeschlagen: fehlgeschlagen,
      );
    }
  }

  /// Wie viele von [rest] nach erreichter Portionsgrenze im Ziel fehlen.
  ///
  /// Seit jeder Lauf an allen Aufnahmen vorbeikommt (#242), wäre der
  /// blosse Rest der Liste zu viel: Darin stehen auch die, die längst im
  /// Ziel liegen. Fehlt keine mehr, ist der Lauf vollständig – die Probe
  /// und die Generation stehen ihm dann zu.
  static Future<int> _fehlenImZiel(
    Iterable<AssetData> rest,
    Future<bool> Function(AssetData) istDa,
  ) async {
    var fehlen = 0;
    for (final asset in rest) {
      if (!await istDa(asset)) fehlen++;
    }
    return fehlen;
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
  ///
  /// **Papierkorb-Einträge nur mit ihrer Datei** ([liegtImZiel]). Sie
  /// stehen darin, weil ihre Dateien aus früheren Läufen im Ziel liegen –
  /// gesichert werden sie aber nicht mehr. Kam ein Foto vor dem ersten
  /// Lauf in den Papierkorb (oder ist das Ziel neu, #242), zählte die
  /// Beilage eine Datei auf, die nie ankam, und die
  /// Wiederherstellungsprobe scheiterte daran bei jedem Lauf.
  Future<void> _writeMetadataExport(
    Directory backupRoot, {
    SecretKey? encryptionKey,
    BackupManifest? stand,
    Future<bool> Function(AssetData asset)? liegtImZiel,
  }) async {
    if (stand != null) {
      await BackupSchnappschussSpeicher().schreibeManifest(
        stand,
        File(p.join(backupRoot.path, 'metadata.json')),
        schluessel: encryptionKey,
      );
      return;
    }
    final allAssets = [
      for (final a in await _db.assetsFuerMetadatenexport())
        if (!a.isTrashed || liegtImZiel == null || await liegtImZiel(a)) a,
    ];
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
        'fileCreatedAt': a.fileCreatedAt.toUtc().toIso8601String(),
        'datumGeschaetzt': a.datumGeschaetzt,
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
        ...handarbeitAnDerAufnahme(
          stackId: a.stackId,
          isStackCover: a.isStackCover,
          aiCaptionEdited: a.aiCaptionEdited,
          aiCaption: a.aiCaption,
          aiCaptionDe: a.aiCaptionDe,
          faceScanExcluded: a.faceScanExcluded,
        ),
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

    await BackupSchnappschussSpeicher().schreibeManifest(
      BackupManifest.ausText(jsonEncode(export), streng: true),
      File(p.join(backupRoot.path, 'metadata.json')),
      schluessel: encryptionKey,
    );
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

  Stream<BackupProgress> restoreFromBackup(
    String wurzel,
    ImportService importe, {
    String? passphrase,
    String? generationSnapshotPath,
    SecretKey? entschluesselungsschluessel,
    Set<String>? auswahlPruefsummen,
    bool streng = false,
    Directory? zwischenlager,
  }) => BackupWiederhersteller(_db, _paths).restoreFromBackup(
    wurzel,
    importe,
    passphrase: passphrase,
    generationSnapshotPath: generationSnapshotPath,
    entschluesselungsschluessel: entschluesselungsschluessel,
    auswahlPruefsummen: auswahlPruefsummen,
    streng: streng,
    zwischenlager: zwischenlager,
  );

  static const uebernommeneTabellen =
      BackupWiederhersteller.uebernommeneTabellen;
  Future<int> uebernimmAusSchnappschuss(File datei, {bool streng = false}) =>
      BackupWiederhersteller(
        _db,
        _paths,
      ).uebernimmAusSchnappschuss(datei, streng: streng);

  // -----------------------------------------------------------------------
  // Automatisches Backup
  // -----------------------------------------------------------------------

  static const autoBackupFolderName = 'PhotoVault-AutoBackup';

  /// Liest die vollständigen, intakten Wiederherstellungspunkte eines
  /// automatischen Backups. Unvollständige Ordner (etwa nach einem Abbruch)
  /// werden nicht angeboten und können daher nicht versehentlich gewählt
  /// werden.
  Future<List<BackupGeneration>> autoBackupGenerations(String wurzel) =>
      BackupSchnappschussSpeicher().generationen(wurzel);

  /// Sieben Generationen decken bei täglichem Standardintervall eine Woche
  /// ab, ohne die (potenziell große) Datenbank auf Dauer unbeschränkt zu
  /// vervielfachen. Die Originale selbst liegen weiterhin genau einmal im
  /// inhaltsadressierten verschlüsselten Datenspeicher.
  @visibleForTesting
  static const autoBackupGenerationsToKeep = 7;

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
  /// das Backup mitreißen). Dateien werden nur ergänzt. Neben dem aktuellen
  /// Datenbank-Schnappschuss bleiben die sieben jüngsten verschlüsselten
  /// Generationen erhalten; aufgeräumt werden ausschließlich ältere,
  /// von Photo Vault selbst markierte Schnappschuss-Verzeichnisse.
  /// [maxBytesPerRun] siehe [performBackup] – hier besonders wichtig, weil
  /// das automatische Backup typischerweise auf einen Cloud-Sync-Ordner
  /// zeigt und ungefragt im Hintergrund läuft.
  ///
  /// Was noch fehlt, entscheidet das Ziel selbst, nicht die Markierung
  /// [Assets.autoBackedUp]: Liegt die verschlüsselte Datei dort schon (ihr
  /// Name folgt fest aus der Prüfsumme), wird sie übersprungen. Ein neues,
  /// leeres Ziel füllt sich so von selbst. Bis #242 galt das nur für den
  /// Server und einen verbundenen Rechner (#206); jeder andere Rechner
  /// schrieb nach einem Zielwechsel nur noch Datenbank und Metadaten, und
  /// die Wiederherstellungsprobe scheiterte daran bei jedem Lauf.
  ///
  /// [markieren] setzt die Markierung für die Anzeige. Nicht am Server und
  /// nicht im verbundenen Rechner: Sie wird mit den Geräten abgeglichen und
  /// beschreibt die Sicherung eines Rechners, nicht die des Servers.
  Stream<BackupProgress> performAutoBackup(
    String destinationRootPath,
    SecretKey encryptionKey, {
    int maxBytesPerRun = 0,
    bool markieren = true,
  }) async* {
    final backupRoot = Directory(
      p.join(destinationRootPath, autoBackupFolderName),
    );
    final originalsOut = Directory(p.join(backupRoot.path, 'originals'));
    await originalsOut.create(recursive: true);

    final manifest = await _writeEncryptedDatabaseSnapshot(
      backupRoot,
      encryptionKey,
    );
    await _writeKeyEnvelope(backupRoot);

    final staging =
        _festesZwischenlager ??
        await Directory.systemTemp.createTemp('pv_autobackup_stage_');
    final pending = await _db.assetsFuerSicherung();
    // Automatische Backups sind immer verschlüsselt – daher stets die
    // flache, namenlose Ablage (siehe VerschluesselteNamen).
    Future<File> zielVon(AssetData asset) async => File(
      p.join(
        backupRoot.path,
        VerschluesselteNamen.ordner,
        await VerschluesselteNamen.fuerPruefsumme(
          asset.checksum,
          encryptionKey,
        ),
      ),
    );
    var done = 0;
    var geschriebeneBytes = 0;
    var abgebrochenWegenLimit = false;
    final autoBackedUpIds = <String>[];
    var fehlgeschlagen = 0;
    var neu = 0;
    yield BackupProgress(0, pending.length);

    try {
      for (final asset in pending) {
        if (maxBytesPerRun > 0 && geschriebeneBytes >= maxBytesPerRun) {
          abgebrochenWegenLimit = true;
          break;
        }
        // Je Datei abgesichert – hier wiegt es schwerer als beim manuellen
        // Lauf: Dieser läuft ungefragt im Hintergrund, ein Abbruch fiele
        // also niemandem auf.
        try {
          final target = await zielVon(asset);
          final schonDa = await _liegtImZiel(target);
          // Wie in [performBackup]: erst fragen, dann (verbunden) holen.
          final source = schonDa
              ? null
              : await _paths.bereit(asset.relativePath);
          if (!schonDa && (source == null || !await source.exists())) {
            throw FileSystemException(
              'pv_backup_quelle_fehlt',
              asset.relativePath,
            );
          }
          if (source != null) {
            await target.parent.create(recursive: true);
            await _ueberZwischendatei(
              zwischenlager: staging,
              ziel: target,
              quellGroesse: await source.length(),
              schreibe: (zwischen) =>
                  VaultCrypto.encryptFile(source, zwischen, encryptionKey),
            );
            geschriebeneBytes += await target.length();
            neu++;
          }
          // Wie in [performBackup]: nur, was noch nicht markiert ist.
          if (!asset.autoBackedUp) autoBackedUpIds.add(asset.id);
        } catch (e) {
          fehlgeschlagen++;
          protokoll(
            'Automatische Sicherung von ${asset.originalFileName} '
            'fehlgeschlagen: $e',
          );
        }
        done++;
        yield BackupProgress(
          done,
          pending.length,
          currentFile: asset.originalFileName,
        );
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
          protokoll(
            'Zwischenlager ${staging.path} nicht geloescht: $e - '
            'es enthaelt unverschluesselte Dateien.',
          );
        }
      }
    }

    final offen = abgebrochenWegenLimit
        ? await _fehlenImZiel(
            pending.skip(done),
            (a) async => _liegtImZiel(await zielVon(a)),
          )
        : 0;
    if (offen == 0) abgebrochenWegenLimit = false;

    if (autoBackedUpIds.isNotEmpty && markieren) {
      await _db.markAutoBackedUp(autoBackedUpIds);
    }
    letzterLaufNeu = neu;
    // Verschlüsselt, wie bei der Sicherung von Hand: Ohne diese Liste fand
    // die Wiederherstellung die namenlosen Dateien nicht – eine
    // automatische Sicherung brachte Namen und Stammbaum zurück, aber kein
    // einziges Foto.
    await _writeMetadataExport(
      backupRoot,
      encryptionKey: encryptionKey,
      stand: manifest,
    );

    if (!abgebrochenWegenLimit && fehlgeschlagen == 0) {
      final probe = await pruefeWiederherstellung(
        backupRoot.path,
        schluessel: encryptionKey,
      );
      if (probe.erfolgreich) await _archiveAutoBackupGeneration(backupRoot);
      yield BackupProgress(
        done,
        pending.length,
        wiederherstellungsprobe: probe,
      );
    }

    if (abgebrochenWegenLimit) {
      yield BackupProgress(done, pending.length, grenzeOffen: offen);
    }
    if (fehlgeschlagen > 0) {
      yield BackupProgress(
        done,
        pending.length,
        fehlgeschlagen: fehlgeschlagen,
      );
    }
  }

  /// Erzeugt über SQLites `VACUUM INTO` einen konsistenten Schnappschuss der
  /// laufenden Datenbank (funktioniert korrekt auch während die App
  /// gleichzeitig weiterschreibt, anders als ein simples Kopieren der
  /// `.sqlite`-Datei, das einen halbgeschriebenen Zustand einfangen könnte)
  /// und verschlüsselt ihn anschließend.
  Future<BackupManifest> _writeEncryptedDatabaseSnapshot(
    Directory backupRoot,
    SecretKey encryptionKey,
  ) async {
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
      return BackupSchnappschussSpeicher().manifestAusDatei(snapshotFile);
    } finally {
      if (await snapshotFile.exists()) await snapshotFile.delete();
    }
  }

  /// Bewahrt den gerade geschriebenen, vollständigen Datenbankstand als
  /// Generation auf. Die verschlüsselten Originale werden nicht dupliziert:
  /// sie ändern sich nie und liegen bereits im gemeinsamen `data/`-Ordner.
  /// Eine Generation besteht daher nur aus dem Datenbank-Schnappschuss und
  /// verweist logisch auf diesen gemeinsamen, inhaltsadressierten Bestand.
  Future<void> _archiveAutoBackupGeneration(Directory root) =>
      BackupSchnappschussSpeicher().archiviere(
        root.path,
        behalten: autoBackupGenerationsToKeep,
      );
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
        'DELETE FROM "$tabelle" WHERE asset_id IN ($platzhalter)',
        gesperrte,
      );
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
      .select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      )
      .map((z) => z['name'] as String);
  return [
    for (final name in namen)
      if (db
          .select('PRAGMA table_info("$name")')
          .any((z) => z['name'] == 'asset_id'))
        name,
  ];
}

/// Reine Top-Level-Funktion für `berechne()` – wie `decodeImageBytes` in
/// library_state.dart.

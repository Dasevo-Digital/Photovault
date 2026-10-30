import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';
import '../berechne.dart';
import '../db/database.dart';
import '../protokoll.dart';
import 'aufnahmedatum.dart';
import 'backup_manifest.dart';
import 'backup_modelle.dart';
import 'backup_restore_plan.dart';
import 'backup_schnappschuss.dart';
import 'blur_detection.dart';
import 'face_engine_service.dart';
import 'import_service.dart';
import 'storage_paths.dart';
import 'vault_crypto.dart';

class BackupWiederhersteller {
  BackupWiederhersteller(this._db, this._paths);
  final AppDatabase _db;
  final StoragePaths _paths;
  final _uuid = const Uuid();
  final _probleme = <RestoreProblem>[];
  void _problem(String code, Object fehler) {
    _probleme.add(RestoreProblem(code));
    protokoll('$code: $fehler');
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
    String wurzel,
    ImportService importe, {
    String? passphrase,
    String? generationSnapshotPath,
    SecretKey? entschluesselungsschluessel,
    Set<String>? auswahlPruefsummen,
    bool streng = false,
    Directory? zwischenlager,
  }) async* {
    final temp = await (zwischenlager ?? Directory.systemTemp).createTemp(
      'pv_restore_',
    );
    try {
      final plan =
          await RestorePlaner(
            schemaVersion: _db.schemaVersion,
            meldeProblem: _problem,
          ).erstelle(
            wurzel,
            importe,
            temp,
            passphrase: passphrase,
            generation: generationSnapshotPath,
            schluessel: entschluesselungsschluessel,
            auswahl: auswahlPruefsummen,
            streng: streng,
          );
      _probleme.addAll(plan.manifest.probleme);
      var done = 0, importiert = 0, vorhanden = 0, fehlend = 0, gescheitert = 0;
      RestoreErgebnis bilanz(bool abgeschlossen) => RestoreErgebnis(
        geplant: plan.dateien.length,
        importiert: importiert,
        vorhanden: vorhanden,
        fehlend: fehlend,
        gescheitert: gescheitert,
        abgeschlossen: abgeschlossen,
        probleme: _probleme,
      );
      yield BackupProgress(
        0,
        plan.dateien.length,
        wiederherstellung: bilanz(false),
      );
      for (final datei in plan.dateien) {
        try {
          if (!await datei.quelle.exists()) {
            fehlend++;
            if (streng) throw const FormatException('pv_probe_original_fehlt');
          } else {
            var quelle = datei.quelle;
            if (plan.schluessel case final key?) {
              quelle = File(p.join(temp.path, '${_uuid.v4()}${datei.endung}'));
              await VaultCrypto.decryptFile(datei.quelle, quelle, key);
            }
            try {
              final r = await importe.importFile(
                quelle.path,
                erwartetePruefsumme: datei.pruefsumme,
              );
              switch (r.outcome) {
                case ImportOutcome.imported:
                  importiert++;
                case ImportOutcome.duplicateSkipped:
                  vorhanden++;
                case ImportOutcome.failed:
                  gescheitert++;
                  if (streng) throw const FormatException('pv_probe_import');
              }
            } finally {
              if (quelle.path != datei.quelle.path && await quelle.exists()) {
                await quelle.delete();
              }
            }
          }
        } on Object catch (e) {
          if (streng) rethrow;
          gescheitert++;
          protokoll('pv_restore_datei: $e');
        }
        done++;
        yield BackupProgress(
          done,
          plan.dateien.length,
          currentFile: p.basename(datei.quelle.path),
          fehlgeschlagen: fehlend + gescheitert,
          wiederherstellung: bilanz(false),
        );
      }
      await _applyMetadataExport(plan.manifest, streng: streng);
      int? zeilen;
      if (plan.schnappschuss case final snapshot?) {
        try {
          zeilen = await uebernimmAusSchnappschuss(snapshot, streng: streng);
          yield* _zeichneAusschnitteNach();
        } on Object catch (e) {
          if (streng) rethrow;
          _problem('pv_restore_schnappschuss', e);
        }
      }
      try {
        await _verknuepfeLivePhotos([
          ...plan.manifest.livePaare,
          if (plan.schnappschuss case final snapshot?)
            ...BackupSchnappschussSpeicher().livePaareAusDatei(snapshot),
        ]);
      } on Object catch (e) {
        if (streng) rethrow;
        _problem('pv_restore_live_photos', e);
      }
      final ergebnis = bilanz(true);
      yield BackupProgress(
        done,
        plan.dateien.length,
        uebernommeneZeilen: zeilen,
        fehlgeschlagen: ergebnis.fehler,
        wiederherstellung: ergebnis,
      );
    } finally {
      await temp.delete(recursive: true);
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
  Future<int> uebernimmAusSchnappschuss(
    File schnappschuss, {
    bool streng = false,
  }) async {
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

      final quellSpalten = {
        for (final z in quelle.select('PRAGMA table_info(assets)')) z['name'],
      };
      if (quellSpalten.contains('file_created_at')) {
        for (final z in quelle.select('SELECT * FROM assets')) {
          final id = assetZuordnung[z['id']];
          if (id == null ||
              z['file_created_at'] is! int ||
              z['is_locked'] == 1) {
            continue;
          }
          final asset = (await _db.assetById(id))!;
          if (asset.isLocked) continue;
          // Je Aufnahme abgesichert wie in [_applyMetadataExport] (#243):
          // Hier lief der Fehler eines einzigen Umbenennens (Original
          // fehlt, Ziel belegt, keine Rechte) bis aus der Methode hinaus,
          // und mit ihm blieben Personen, Gesichter, Stammbaum und Reisen
          // aus – übrig blieb nur „pv_restore_schnappschuss“.
          try {
            await AufnahmedatumDienst(_db, _paths).setze(
              asset,
              DateTime.fromMillisecondsSinceEpoch(
                (z['file_created_at'] as int) * 1000,
              ),
              geschaetzt:
                  quellSpalten.contains('datum_geschaetzt') &&
                  z['datum_geschaetzt'] == 1,
              streng: true,
            );
          } catch (e) {
            if (streng) rethrow;
            _problem('pv_restore_aufnahmedatum', e);
          }
        }
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
            [tabelle],
          );
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
              await _db.customInsert(
                befehl,
                variables: [for (final w in werte) Variable(w)],
              );
              uebernommen++;
            } catch (e) {
              if (streng) rethrow;
              // Je Zeile abgesichert – eine Zeile, die hier nicht hineinpasst
              // (ein Fremdschlüssel auf eine ausgelassene Aufnahme etwa), darf
              // die Wiederherstellung nicht abbrechen.
              _problem('pv_restore_zeile', e);
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
            'SELECT id, faces_scanned FROM assets WHERE faces_scanned = 1',
          ))
            ?assetZuordnung[z['id'] as String],
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
          final datei = _paths.absolute(
            asset.previewRelativePath ?? asset.relativePath,
          );
          if (await datei.exists()) {
            final bild = await berechne(_dekodiere, await datei.readAsBytes());
            if (bild != null) {
              for (final gesicht in eintrag.value) {
                final ausschnitt = FaceEngineService.cropFaceImage(
                  bild,
                  DetectedFace(
                    gesicht.boxX,
                    gesicht.boxY,
                    gesicht.boxW,
                    gesicht.boxH,
                    1.0,
                  ),
                );
                final ziel = _paths.faceRelativePath(gesicht.id);
                await FaceEngineService.saveFaceCrop(
                  ausschnitt,
                  _paths.absolute(ziel),
                );
                await _db.setzeGesichtsausschnitt(
                  gesicht.id,
                  ziel,
                  schaerfe: gesichtsschaerfe(ausschnitt),
                );
              }
            }
          }
        }
      } catch (e) {
        // Je Foto abgesichert: Eine Datei, die sich nicht lesen lässt, darf
        // die übrigen Ausschnitte nicht mitnehmen.
        _problem('pv_restore_ausschnitt', e);
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
  /// Verknüpft die Paare der Live Photos wieder (#255).
  ///
  /// Die Wiederherstellung importiert jede Datei für sich, ohne die
  /// Nachbearbeitung des Imports. Bis 3.49.8 war danach kein Live Photo
  /// mehr verknüpft: Jede Videohälfte stand als eigenes Video in der
  /// Zeitleiste. Die Paare kommen als Prüfsummen aus der Beilage oder dem
  /// Schnappschuss; verknüpft wird nur, was hier noch frei ist.
  Future<int> _verknuepfeLivePhotos(Iterable<(String, String)> paare) async {
    final nachPruefsumme = <String, AssetData>{
      for (final a in await _db.select(_db.assets).get()) a.checksum: a,
    };
    final vergeben = <String>{
      for (final a in nachPruefsumme.values)
        if (a.linkedAssetId != null) a.id,
    };
    var n = 0;
    for (final (x, y) in paare) {
      final a = nachPruefsumme[x], b = nachPruefsumme[y];
      if (a == null || b == null || a.id == b.id) continue;
      if (vergeben.contains(a.id) || vergeben.contains(b.id)) continue;
      await _db.linkAssets(a.id, b.id);
      vergeben.addAll([a.id, b.id]);
      n++;
    }
    return n;
  }

  Future<void> _applyMetadataExport(
    BackupManifest manifest, {
    bool streng = false,
  }) async {
    final content = manifest.alsJson();
    final assetsJson = manifest.aufnahmen.map((a) => a.werte);

    final byChecksum = <String, String>{}; // checksum -> assetId in dieser DB
    for (final row in await _db.select(_db.assets).get()) {
      byChecksum[row.checksum] = row.id;
    }

    // Dateiumzüge haben eigene kurze Transaktionen. Eine spätere fehlerhafte
    // Metadatenzeile darf nicht nur die Datenbank zurückrollen und bereits
    // verschobene Originale am falschen Pfad zurücklassen.
    final fehlgeschlagen = <String>{};
    for (final entry in assetsJson) {
      final assetId = byChecksum[entry['checksum']];
      if (assetId == null) continue;
      final asset = (await _db.assetById(assetId))!;
      if (asset.isLocked) {
        _problem('pv_restore_gesperrt', StateError('pv_restore_gesperrt'));
        fehlgeschlagen.add(assetId);
        continue;
      }
      try {
        if (entry['fileCreatedAt'] case final String text) {
          await AufnahmedatumDienst(_db, _paths).setze(
            asset,
            DateTime.parse(text),
            geschaetzt: entry['datumGeschaetzt'] as bool? ?? false,
            streng: true,
          );
        }
      } catch (e) {
        if (streng) rethrow;
        fehlgeschlagen.add(assetId);
        _problem('pv_restore_aufnahmedatum', e);
      }
    }
    // Die verbleibende reine Datenbankarbeit bleibt gebündelt.
    final stapelMitglieder = <String, List<(String, bool)>>{};
    await _db.transaction(() async {
      for (final entry in assetsJson) {
        try {
          final assetId = byChecksum[entry['checksum']];
          if (assetId == null || fehlgeschlagen.contains(assetId)) continue;
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
            await _db.fuehreAus(
              DateinameSetzen(assetId, p.basename(originalFileName)),
            );
          }
          if (entry['isFavorite'] == true) {
            await _db.fuehreAus(FavoritSetzen([assetId], true));
          }
          if (entry['description'] is String &&
              (entry['description'] as String).isNotEmpty) {
            await _db.fuehreAus(
              BeschreibungSetzen([assetId], entry['description'] as String),
            );
          }
          // Fehlen die Felder (Sicherung vor Fassung 2.3.0), bleibt es beim
          // Vorgabewert - eine ältere Sicherung setzt also keine Null
          // über etwas, das im Ziel schon steht.
          if (entry['rating'] is int && entry['rating'] as int > 0) {
            await _db.fuehreAus(
              BewertungSetzen([assetId], entry['rating'] as int),
            );
          }
          if (entry['colorLabel'] is String) {
            await _db.fuehreAus(
              FarbmarkeSetzen([assetId], entry['colorLabel'] as String),
            );
          }
          // Explizit leere Koordinaten sind ebenfalls gesicherte Handarbeit:
          // Sonst käme beim Reimport der zuvor entfernte EXIF-Ort zurück.
          if (entry.containsKey('latitude') && entry.containsKey('longitude')) {
            final lat = entry['latitude'], lon = entry['longitude'];
            if (!((lat == null && lon == null) || (lat is num && lon is num))) {
              throw const FormatException('pv_restore_koordinaten');
            }
            await _db.fuehreAus(
              OrtSetzen(
                [assetId],
                (lat as num?)?.toDouble(),
                (lon as num?)?.toDouble(),
              ),
            );
          }
          if ([
            'locationCountry',
            'locationState',
            'locationCity',
          ].any(entry.containsKey)) {
            await _db.setLocationNames(
              assetId,
              country: entry['locationCountry'] as String?,
              state: entry['locationState'] as String?,
              city: entry['locationCity'] as String?,
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
            await _db.fuehreAus(
              SchlagwortAnheften(
                [assetId],
                tag as String,
                quelle: kiTags.contains(tag) ? Tagquelle.ki : Tagquelle.hand,
              ),
            );
          }
          // Handarbeit an der Aufnahme selbst (#244, siehe
          // [handarbeitAnDerAufnahme]). Die Beschreibung als Handvergabe:
          // So schreibt die Bilderkennung sie nicht neu.
          if (entry['faceScanExcluded'] == true) {
            await _db.fuehreAus(GesichtssucheAusnehmen(assetId, true));
          }
          if (entry['aiCaptionEdited'] == true) {
            for (final (schluessel, deutsch) in const [
              ('aiCaption', false),
              ('aiCaptionDe', true),
            ]) {
              if (entry[schluessel] case final String text
                  when text.trim().isNotEmpty) {
                await _db.fuehreAus(
                  BildbeschreibungSetzen(assetId, text, deutsch: deutsch),
                );
              }
            }
          }
          if (entry['stackId'] case final String stapel) {
            (stapelMitglieder[stapel] ??= []).add((
              assetId,
              entry['isStackCover'] == true,
            ));
          }
        } catch (e) {
          if (streng) rethrow;
          _problem('pv_restore_metadaten', e);
        }
      }
      // Stapel erst, wenn alle Mitglieder da sind.
      for (final MapEntry(key: stapel, value: mitglieder)
          in stapelMitglieder.entries) {
        try {
          await _stapleWiederAuf(stapel, mitglieder);
        } catch (e) {
          if (streng) rethrow;
          _problem('pv_restore_stapel', e);
        }
      }
    });

    final albumsJson = (content['albums'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    for (final albumEntry in albumsJson) {
      try {
        final name =
            albumEntry['name'] as String? ?? 'Wiederhergestelltes Album';
        final checksums = (albumEntry['assetChecksums'] as List<dynamic>? ?? [])
            .cast<String>();
        final assetIds = checksums
            .map((c) => byChecksum[c])
            .whereType<String>()
            .toList();
        if (assetIds.isEmpty) continue;
        final albumId = const Uuid().v4();
        await _db.fuehreAus(AlbumAnlegen(albumId, name, DateTime.now()));
        await _db.fuehreAus(AlbumFuellen(albumId, assetIds));
      } catch (e) {
        if (streng) rethrow;
        _problem('pv_restore_album', e);
      }
    }
  }

  /// Bildet einen gesicherten Stapel aus [mitglieder] (Kennung hier, ob
  /// Titelbild) neu – als Serie oder als Variantenstapel, je nach Kennung.
  ///
  /// Was im Ziel schon gestapelt ist, bleibt, wie es ist: Wer dieselbe
  /// Bibliothek zurückspielt, hat den Stapel noch, und eine Aufnahme kann
  /// nur in einem liegen. Bleibt weniger als ein Paar übrig (etwa weil
  /// Dateien fehlten), ist es kein Stapel.
  Future<void> _stapleWiederAuf(
    String stapel,
    List<(String, bool)> mitglieder,
  ) async {
    final schonDa = await (_db.select(
      _db.assets,
    )..where((t) => t.stackId.equals(stapel))).get();
    if (schonDa.isNotEmpty) return;
    final frei = [
      for (final m in mitglieder)
        if ((await _db.assetById(m.$1))?.stackId == null) m,
    ];
    if (frei.length < 2) return;
    final ids = [for (final m in frei) m.$1];
    final titel = frei.firstWhere((m) => m.$2, orElse: () => frei.first).$1;
    await _db.fuehreAus(
      istVariantenstapel(stapel)
          ? VariantenBilden(
              stapel.substring(variantenstapelPraefix.length),
              ids,
              titel,
            )
          : SerieBilden(stapel, ids, titel),
    );
  }
}

img.Image? _dekodiere(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
}

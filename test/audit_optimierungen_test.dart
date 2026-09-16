import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Sichert die Befunde eines Audits ab, damit sie nicht zurückkehren:
/// keine entschlüsselten Metadaten im Temp-Verzeichnis, keine gesperrten
/// Fotos in den Analysestufen.
void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('pv_audit_'));
  tearDown(() => tempRoot.deleteSync(recursive: true));

  Future<LibraryState> bibliothek(String name) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, name)));
    return LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);
  }

  /// Entschlüsselte Metadaten landen unter `photovault_restore_*.json` im
  /// System-Temp – dort darf nach einem Restore nichts liegen bleiben.
  List<File> uebrigeMetadatenDateien() => Directory.systemTemp
      .listSync()
      .whereType<File>()
      .where((f) =>
          p.basename(f.path).startsWith('photovault_restore_') &&
          f.path.endsWith('.json'))
      .toList();

  /// Wartet kurz ab, bis keine NEUEN Metadatendateien mehr liegen bleiben.
  ///
  /// Das System-Temp gehört allen: Die Testdateien laufen parallel, und ein
  /// anderer Backup-Test kann währenddessen seine eigene, kurzlebige
  /// `photovault_restore_*.json` dort liegen haben. Ein einzelner Blick
  /// erwischt die und meldet fälschlich ein Leck. Ein echtes Leck dagegen
  /// bleibt beliebig lange liegen und überlebt dieses Zeitfenster mühelos.
  Future<List<File>> neueRestePruefen(Set<String> vorher) async {
    var reste = <File>[];
    for (var versuch = 0; versuch < 20; versuch++) {
      reste = uebrigeMetadatenDateien().where((f) => !vorher.contains(f.path)).toList();
      if (reste.isEmpty) return reste;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return reste;
  }

  group('Wiederherstellung hinterlässt keine Klartext-Metadaten', () {
    test('auch dann nicht, wenn sie vorzeitig abgebrochen wird', () async {
      final quelle = await bibliothek('quelle');
      final quellImport = ImportService(quelle.db, quelle.paths);
      final incoming = Directory(p.join(tempRoot.path, 'incoming'))..createSync();
      for (var i = 0; i < 6; i++) {
        final f = File(p.join(incoming.path, 'foto_$i.jpg'))
          ..writeAsBytesSync(List.filled(256, i));
        await quellImport.importFile(f.path);
      }

      await quelle.setupBackupPassphrase('geheim-123');
      final ziel = Directory(p.join(tempRoot.path, 'ziel'))..createSync();
      await quelle.runManualBackup(ziel.path, encrypt: true).drain<void>();

      final vorher = uebrigeMetadatenDateien().map((f) => f.path).toSet();

      // Restore starten und nach dem ersten Fortschritt abbrechen – genau
      // das, was passiert, wenn der Nutzer die Wiederherstellung abbricht.
      final neu = await bibliothek('ziel_lib');
      final neuImport = ImportService(neu.db, neu.paths);
      final stream = neu.backupService.restoreFromBackup(
          p.join(ziel.path, 'PhotoVault-Backup'), neuImport,
          passphrase: 'geheim-123');

      final sub = stream.listen(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      // Der finally-Block des Generators läuft asynchron zum cancel().
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final neueReste = await neueRestePruefen(vorher);
      addTearDown(() {
        for (final f in neueReste) {
          if (f.existsSync()) f.deleteSync();
        }
      });
      expect(neueReste, isEmpty,
          reason: 'ein Abbruch darf die entschlüsselten Metadaten nicht '
              'im Temp-Verzeichnis zurücklassen');
    });

    test('und auch nicht nach einem vollständigen Durchlauf', () async {
      final quelle = await bibliothek('quelle2');
      final quellImport = ImportService(quelle.db, quelle.paths);
      final incoming = Directory(p.join(tempRoot.path, 'incoming2'))..createSync();
      final f = File(p.join(incoming.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
      await quellImport.importFile(f.path);

      await quelle.setupBackupPassphrase('geheim-123');
      final ziel = Directory(p.join(tempRoot.path, 'ziel2'))..createSync();
      await quelle.runManualBackup(ziel.path, encrypt: true).drain<void>();

      final vorher = uebrigeMetadatenDateien().map((f) => f.path).toSet();

      final neu = await bibliothek('ziel_lib2');
      final neuImport = ImportService(neu.db, neu.paths);
      await neu.backupService
          .restoreFromBackup(p.join(ziel.path, 'PhotoVault-Backup'), neuImport,
              passphrase: 'geheim-123')
          .drain<void>();

      final neueReste = await neueRestePruefen(vorher);
      addTearDown(() {
        for (final r in neueReste) {
          if (r.existsSync()) r.deleteSync();
        }
      });
      expect(neueReste, isEmpty);
      expect(await neu.db.select(neu.db.assets).get(), hasLength(1),
          reason: 'die Wiederherstellung selbst muss weiterhin funktionieren');
    });
  });

  test('keine Analysestufe fasst gesperrte Fotos an', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib3')));
    final imp = ImportService(db, paths);
    final inc = Directory(p.join(tempRoot.path, 'in3'))..createSync();

    final offen = await imp.importFile(
        (File(p.join(inc.path, 'offen.jpg'))..writeAsBytesSync(List.filled(64, 1))).path);
    final geheim = await imp.importFile(
        (File(p.join(inc.path, 'geheim.jpg'))..writeAsBytesSync(List.filled(64, 2))).path);
    await db.setAssetsLocked([geheim.assetId!], true);

    final stufen = <String, List<AssetData>>{
      'Texterkennung': await db.assetsForOcrBackfill(),
      'Bildbeschreibung': await db.assetsForCaptionBackfill(),
      'Unschärfe': await db.assetsForBlurBackfill(),
      'Bildsuche': await db.assetsForEmbeddingBackfill(),
      'Gesichter': await db.assetsForFaceScan(onlyNew: true),
      'Schlagwörter': await db.assetsForAiTagging(onlyUntagged: true),
    };

    for (final stufe in stufen.entries) {
      expect(stufe.value.map((a) => a.id), isNot(contains(geheim.assetId)),
          reason: '${stufe.key} darf gesperrte Fotos nicht verarbeiten');
    }
    // Gegenprobe: das ungesperrte Foto muss weiterhin verarbeitet werden,
    // sonst prüfte der Test nur eine leere Menge.
    expect(stufen['Texterkennung']!.map((a) => a.id), contains(offen.assetId));
    expect(stufen['Unschärfe']!.map((a) => a.id), contains(offen.assetId));
    expect(stufen['Bildsuche']!.map((a) => a.id), contains(offen.assetId));
  });

  test('Sperren entfernt die aus dem Bildinhalt abgeleiteten Daten', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib4')));
    final imp = ImportService(db, paths);
    final inc = Directory(p.join(tempRoot.path, 'in4'))..createSync();
    final r = await imp.importFile(
        (File(p.join(inc.path, 'dokument.jpg'))..writeAsBytesSync(List.filled(64, 3))).path);
    final id = r.assetId!;

    // Zustand, wie ihn die Analyse eines noch offenen Fotos hinterlässt.
    // MIT deutscher Fassung: Die Übersetzung ist ein eigener Durchgang,
    // und ein Test, der sie nicht anlegt, kann sie auch nicht vermissen.
    // Genau daran ist die Lücke bis zur 17. Prüfrunde vorbeigelaufen.
    await db.setOcrResult(id, 'Kontonummer DE12 3456 7890');
    await db.setAiCaption(id, 'a scanned bank statement');
    await db.setAiCaptionDe(id, 'ein abfotografierter Kontoauszug');
    await db.saveEmbedding(id, Float32List.fromList(List.filled(512, 0.1)));
    await db.setSharpnessScore(id, 42.0);

    await db.clearDerivedContentData([id]);

    final danach = (await db.select(db.assets).get()).single;
    expect(danach.ocrText, isNull, reason: 'erkannter Text ist Bildinhalt');
    expect(danach.ocrBoxen, isNull,
        reason: 'die Stellen stehen im Klartext neben dem Text');
    expect(danach.aiCaption, isNull, reason: 'die Bildunterschrift ebenso');
    expect(danach.aiCaptionDe, isNull,
        reason: 'derselbe Satz auf Deutsch ist derselbe Bildinhalt');
    expect(await db.embeddingForAsset(id), isNull,
        reason: 'das Embedding beschreibt den Bildinhalt');
    // Damit nach dem Entsperren neu berechnet wird.
    expect(danach.ocrScanned, isFalse);
    expect(danach.aiCaptionScanned, isFalse);
    // Die Schärfe verrät nichts über den Inhalt und wird gebraucht.
    expect(danach.sharpnessScore, 42.0);
  });

  test('kein Feld des Bildinhalts bleibt übersehen zurück', () async {
    // Die Lücke der 17. Prüfrunde war nicht, dass jemand ai_caption_de für
    // harmlos hielt – sie war, dass niemand sie bemerkte, als die Spalte
    // dazukam. Dieser Test zählt die Spalten auf, statt sie einzeln zu
    // nennen: Eine neue Spalte, die nach Bildinhalt klingt, fällt hier
    // auf, auch wenn niemand an diese Stelle denkt.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final spalten = db.assets.$columns.map((c) => c.name).toSet();
    const behandelt = {
      'ocr_text', 'ocr_boxen', 'ocr_scanned',
      'ai_caption', 'ai_caption_de', 'ai_caption_scanned',
      'ai_caption_edited', 'ai_tags_scanned',
    };
    const bewusstNicht = {'sharpness_score'};
    final ausInhalt = spalten.where((n) =>
        n.startsWith('ocr_') || n.startsWith('ai_') || n == 'sharpness_score');
    expect(ausInhalt, isNotEmpty, reason: 'sonst prüfte der Test nichts');
    for (final name in ausInhalt) {
      expect(behandelt.contains(name) || bewusstNicht.contains(name), isTrue,
          reason: 'Die Spalte "$name" leitet sich aus dem Bildinhalt ab. '
              'Entweder gehört sie in clearDerivedContentData, oder es steht '
              'dort, warum nicht.');
    }
  });

  test('eine von Hand geschriebene Bildunterschrift überlebt das Sperren',
      () async {
    // Sie wurde vorher gelöscht, und zwar unwiederbringlich: Das Merkmal
    // ai_caption_edited blieb stehen, und der Nachhol-Durchgang schliesst
    // genau damit aus, was von Hand geschrieben wurde.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib5')));
    final imp = ImportService(db, paths);
    final inc = Directory(p.join(tempRoot.path, 'in5'))..createSync();
    final r = await imp.importFile(
        (File(p.join(inc.path, 'urlaub.jpg'))..writeAsBytesSync(List.filled(64, 5))).path);
    final id = r.assetId!;

    await db.setAiCaptionVonHand(id, 'Omas achtzigster Geburtstag', deutsch: true);
    await db.clearDerivedContentData([id]);

    final danach = (await db.select(db.assets).get()).single;
    expect(danach.aiCaptionDe, 'Omas achtzigster Geburtstag',
        reason: 'die eigenen Worte folgen derselben Regel wie description');
    expect(danach.aiCaptionEdited, isTrue);
  });

  group('gemeinsamer Bildanalyse-Durchlauf', () {
    /// Ein echt dekodierbares JPEG – die kombinierte Stufe dekodiert
    /// tatsächlich, ein Byte-Dummy würde den Test wirkungslos machen.
    /// [kachel] variiert das Muster, damit zwei Aufrufe nicht dieselbe
    /// Prüfsumme ergeben und als Dublette abgewiesen werden.
    File echtesFoto(String pfad, {int kachel = 4}) {
      final bild = img.Image(width: 64, height: 48);
      for (var y = 0; y < 48; y++) {
        for (var x = 0; x < 64; x++) {
          final hell = (x ~/ kachel + y ~/ kachel) % 2 == 0;
          bild.setPixelRgb(x, y, hell ? 255 : 0, hell ? 255 : 0, hell ? 255 : 0);
        }
      }
      return File(pfad)..writeAsBytesSync(img.encodeJpg(bild));
    }

    test('wählt genau die Fotos, denen noch etwas fehlt', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib5')));
      final imp = ImportService(db, paths);
      final inc = Directory(p.join(tempRoot.path, 'in5'))..createSync();

      final offen = await imp.importFile(echtesFoto(p.join(inc.path, 'offen.jpg')).path);
      final fertig =
          await imp.importFile(echtesFoto(p.join(inc.path, 'fertig.jpg'), kachel: 8).path);
      expect(offen.assetId, isNotNull);
      expect(fertig.assetId, isNotNull, reason: 'die beiden Fotos dürfen keine Dubletten sein');

      // "fertig" hat alle drei Auswertungen schon.
      await db.setSharpnessScore(fertig.assetId!, 10.0);
      await db.markFacesScanned([fertig.assetId!]);
      await db.saveEmbedding(fertig.assetId!, Float32List.fromList(List.filled(512, 0.1)));

      final kandidaten = await db.assetsForCombinedImageAnalysis();
      final ids = kandidaten.map((k) => k.asset.id).toList();

      expect(ids, contains(offen.assetId));
      expect(ids, isNot(contains(fertig.assetId)),
          reason: 'ein vollständig ausgewertetes Foto darf nicht erneut dekodiert werden');

      final k = kandidaten.singleWhere((k) => k.asset.id == offen.assetId);
      expect(k.hatEmbedding, isFalse);
      expect(k.asset.sharpnessScore, isNull);
      expect(k.asset.facesScanned, isFalse);
    });

    test('rechnet die Unschärfe und übersteht fehlende Modelle', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib6')));
      final lib = LibraryState()
        ..db = db
        ..paths = paths
        ..backupService = BackupService(db, paths);
      final imp = ImportService(db, paths);
      final inc = Directory(p.join(tempRoot.path, 'in6'))..createSync();
      final r = await imp.importFile(echtesFoto(p.join(inc.path, 'muster.jpg')).path);

      // Ohne installierte Modelle und ohne native Plattformkanäle: Die
      // Texterkennung wirft hier (MissingPluginException). Die Analyse muss
      // trotzdem durchlaufen und die modellfreie Unschärfe berechnen – genau
      // das ging vorher verloren, weil ein Fehler die ganze Kette abbrach.
      await lib.starteHintergrundanalyse();

      final danach = (await db.select(db.assets).get()).single;
      expect(danach.sharpnessScore, isNotNull,
          reason: 'die Unschärfe braucht kein Modell und muss berechnet werden');
      expect(danach.id, r.assetId);
      expect(lib.analyse, isNull, reason: 'der Lauf muss sauber beendet sein');
    });
  });
}

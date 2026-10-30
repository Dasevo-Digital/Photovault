import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Was [speichereBearbeitung] getan hat.
typedef Bearbeitungsergebnis = ({
  /// Die Aufnahme, die jetzt das bisherige Original trägt – `null`, wenn es
  /// als Dublette einer anderen Aufnahme ohnehin in der Bibliothek liegt.
  String? original,

  /// Die neuen Miniatur-Angaben der bearbeiteten Aufnahme.
  ThumbnailResult vorschau,
});

/// Speichert, was der Editor (Zuschneiden, Drehen, Retusche …) aus einer
/// Aufnahme gemacht hat, **ohne das Original zu verlieren** (#248).
///
/// **Bis 3.49.6** ersetzte die bearbeitete Fassung das Original: ein JPEG
/// am Ort, alles andere (HEIC, RAW, PSD …) als neue `.jpg`, und das alte
/// Original wurde endgültig gelöscht. Weil der Editor bei diesen Formaten
/// und bei Dateien über 32 MB nur die Vorschau mit höchstens 2048 Pixeln
/// gelesen hatte, wurde aus einem 48-MP-DNG nach einmal Drehen ein JPEG
/// mit 3 MP – ohne Weg zurück.
///
/// **Jetzt** trägt die Aufnahme danach die bearbeitete Fassung, mit allem,
/// was an ihr hängt (Alben, Schlagwörter, Personen, Sterne). Das bisherige
/// Original wird eine eigene Aufnahme und liegt als Variante im selben
/// Stapel – wie ein RAW neben seinem JPEG. Liegt die Aufnahme schon in
/// einem Stapel, kommt es dorthin dazu. Von der Gesichtssuche ist es
/// ausgenommen, sonst stünden dieselben Gesichter zweimal da.
///
/// **Reihenfolge.** Die neue Datei entsteht neben dem Ziel, das alte
/// Original wird nur verschoben, und erst der Eintrag in der Datenbank
/// macht den Tausch gültig. Scheitert irgendein Schritt bis zum Import des
/// alten Originals, wird alles zurückgedreht: Datei und Eintrag stehen
/// wieder wie vorher. In einer mit dem Server verbundenen Kopie lehnt die
/// Datenbank den Eintrag ab (`pv_nur_ueber_server`, #250) – auch dann ist
/// nichts verloren.
Future<Bearbeitungsergebnis> speichereBearbeitung({
  required AppDatabase db,
  required StoragePaths paths,
  required AssetData asset,
  required Uint8List jpeg,
  ImportService? importe,
}) async {
  final import = importe ?? ImportService(db, paths);
  final pruefsumme = sha256.convert(jpeg).toString();
  final altRelativ = asset.relativePath;
  final neuRelativ = paths.originalRelativePath(
    asset.fileCreatedAt,
    asset.id,
    '.jpg',
  );
  final altDatei = paths.absolute(altRelativ);
  final neuDatei = paths.absolute(neuRelativ);
  final teil = File('${neuDatei.path}.pv-neu');
  final arbeit = Directory(
    p.join(paths.root.path, '.bearbeitung', const Uuid().v4()),
  );
  // Unter dem Namen, den die Aufnahme trägt, und mit der Endung der Datei,
  // wie sie in der Bibliothek liegt: Der Import nimmt beides aus dem Pfad.
  final stamm = p.basenameWithoutExtension(
    asset.originalFileName.replaceAll(RegExp(r'[/\\]'), '_'),
  );
  final geparkt = File(
    p.join(
      arbeit.path,
      '${stamm.isEmpty ? asset.id : stamm}${p.extension(altRelativ)}',
    ),
  );

  var verschoben = false, getauscht = false, eingetragen = false;
  Future<void> zurueck() async {
    if (eingetragen) {
      await (db.update(db.assets)..where((t) => t.id.equals(asset.id))).write(
        AssetsCompanion(
          relativePath: Value(altRelativ),
          checksum: Value(asset.checksum),
          fileSizeBytes: Value(asset.fileSizeBytes),
          previewRelativePath: Value(asset.previewRelativePath),
          developedRelativePath: Value(asset.developedRelativePath),
        ),
      );
    }
    if (getauscht && await neuDatei.exists()) await neuDatei.delete();
    if (verschoben && await geparkt.exists()) {
      await altDatei.parent.create(recursive: true);
      await geparkt.rename(altDatei.path);
    }
    if (await teil.exists()) await teil.delete();
  }

  // Erster Teil: bis das alte Original als eigene Aufnahme in der
  // Bibliothek liegt. Scheitert hier etwas, steht danach alles wie vorher.
  final ImportResult r;
  try {
    await neuDatei.parent.create(recursive: true);
    await teil.writeAsBytes(jpeg, flush: true);
    await arbeit.create(recursive: true);
    await altDatei.rename(geparkt.path);
    verschoben = true;
    await teil.rename(neuDatei.path);
    getauscht = true;
    // Setzt auch Vorschau und entwickeltes Bild zurück: Beide zeigten das
    // alte Bild. Die Einstellungen der Entwicklung bleiben; nur ihr
    // Ergebnis wird neu gerechnet.
    await db.setEditedAssetFile(
      asset.id,
      relativePath: neuRelativ,
      checksum: pruefsumme,
      fileSizeBytes: jpeg.length,
    );
    eingetragen = true;
    // Kopiert, nicht verschoben: Bis hierher liegt das alte Original nur
    // im Arbeitsordner.
    r = await import.importFile(geparkt.path);
    if (r.outcome == ImportOutcome.failed) {
      throw StateError('pv_bearbeitung_original: ${r.error}');
    }
  } catch (_) {
    await zurueck();
    if (await arbeit.exists()) await arbeit.delete(recursive: true);
    rethrow;
  }

  // Zweiter Teil: Der Tausch ist gültig, das alte Original gesichert. Was
  // jetzt noch scheitert, ordnet nur ein oder rechnet Miniaturen; die
  // Gegenstelle gibt es ab hier nicht mehr.
  await arbeit.delete(recursive: true);
  // Eine Dublette: Dieselben Bytes liegen schon als andere Aufnahme da.
  final original = r.outcome == ImportOutcome.imported ? r.assetId : null;
  if (original != null) {
    await db.fuehreAus(DateinameSetzen(original, asset.originalFileName));
    await db.fuehreAus(GesichtssucheAusnehmen(original, true));
    final stapel = asset.stackId;
    if (stapel == null) {
      await db.fuehreAus(
        VariantenBilden(const Uuid().v4(), [asset.id, original], asset.id),
      );
    } else {
      final mitglieder = await db.assetsInStack(stapel);
      final titel = mitglieder
          .firstWhere((m) => m.isStackCover, orElse: () => asset)
          .id;
      final ids = [for (final m in mitglieder) m.id, original];
      await db.fuehreAus(
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
  for (final abgeleitet in [
    asset.previewRelativePath,
    asset.developedRelativePath,
  ]) {
    if (abgeleitet != null) await paths.deletePermanently(abgeleitet);
  }
  final vorschau = await import.generateThumbnailAndPreview(
    neuDatei,
    asset.id,
    '.jpg',
    alreadyReadBytes: jpeg,
  );
  await db.updateThumbnailInfo(
    asset.id,
    thumbnailRelativePath: vorschau.thumbnailRelativePath,
    widthPx: vorschau.width,
    heightPx: vorschau.height,
  );
  return (original: original, vorschau: vorschau);
}

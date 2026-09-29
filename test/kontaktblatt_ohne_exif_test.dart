// **Das Kontaktblatt trug die Koordinaten mit, die niemand darauf sieht.**
//
// Sichtbar stehen darauf nur laufende Nummer und Aufnahmedatum. Die
// Bilder gehen aber durch `decodeImage` → `encodeJpg`, und package:image
// schreibt die EXIF-Blöcke wieder hinaus. Aus einem erzeugten Blatt
// liess sich das JPEG herausschneiden; darin standen Kamera, Modell und
// GPS 52°22'12.78" N / 9°44'8.17" E.
//
// Kein Randfall: An einer gewachsenen Bibliothek tragen 892 von 8144
// Vorschaubildern GPS und 5538 eine Kameraangabe – und ein Kontaktblatt
// ist zum Ausdrucken und Weitergeben da.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/contact_sheet_service.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Schneidet das erste eingebettete JPEG aus dem PDF.
///
/// Bilder liegen als `DCTDecode`-Strom unverändert im PDF, also zwischen
/// den JPEG-Marken – deshalb genügt das Suchen der Marken und es braucht
/// keinen PDF-Leser.
Uint8List? _bildAusPdf(Uint8List pdf) {
  final start = _finde(pdf, [0xFF, 0xD8, 0xFF], 0);
  if (start < 0) return null;
  final ende = _finde(pdf, [0xFF, 0xD9], start);
  if (ende < 0) return null;
  return Uint8List.sublistView(pdf, start, ende + 2);
}

int _finde(Uint8List haufen, List<int> muster, int ab) {
  for (var i = ab; i <= haufen.length - muster.length; i++) {
    var passt = true;
    for (var k = 0; k < muster.length; k++) {
      if (haufen[i + k] != muster[k]) {
        passt = false;
        break;
      }
    }
    if (passt) return i;
  }
  return -1;
}

AssetData _aufnahme(String rel, int groesse, List<int> inhalt) => AssetData(
      id: 'kb1',
      originalFileName: 'Urlaub-Privat.jpg',
      relativePath: rel,
      checksum: sha256.convert(inhalt).toString(),
      type: 'IMAGE',
      fileCreatedAt: DateTime(2026, 5, 4),
      importedAt: DateTime(2026),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      fileSizeBytes: groesse,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      rating: 0,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
    );

void main() {
  test('kein EXIF, keine Koordinaten, keine Kamera im Kontaktblatt',
      () async {
    final temp = Directory.systemTemp.createTempSync('pv_kb_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));

    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(20, 120, 200));
    bild.exif.imageIfd['Make'] = 'GEHEIME_KAMERA';
    bild.exif.imageIfd['Model'] = 'GEHEIMES_MODELL';
    bild.exif.gpsIfd.gpsLatitude = 52.370216;
    bild.exif.gpsIfd.gpsLongitude = 9.735603;
    final jpeg = img.encodeJpg(bild);
    // Die Quelle MUSS die Angaben tragen, sonst prüft der Test nichts.
    expect(img.decodeImage(jpeg)!.exif.imageIfd['Make'].toString(),
        contains('GEHEIME_KAMERA'));
    expect(img.decodeImage(jpeg)!.exif.gpsIfd.gpsLatitude, isNotNull);

    const rel = 'originals/2026/urlaub.jpg';
    await paths.absolute(rel).parent.create(recursive: true);
    await paths.absolute(rel).writeAsBytes(jpeg);

    // Ohne Vorschaubild greift das Blatt auf das Original zurück – der
    // Weg mit den meisten Beipackzetteln.
    final ergebnis = await ContactSheetService(paths, ExportService(paths))
        .create([_aufnahme(rel, jpeg.length, jpeg)]);
    expect(ergebnis.included, 1);

    final ausgeschnitten = _bildAusPdf(ergebnis.bytes);
    expect(ausgeschnitten, isNotNull,
        reason: 'ohne eingebettetes Bild prüft der Test nichts');
    final wieder = img.decodeImage(ausgeschnitten!)!;
    expect(wieder.hasExif ? wieder.exif.isEmpty : true, isTrue,
        reason: 'das Bild im PDF darf keinen EXIF-Anhang mehr tragen');
    expect(wieder.exif.gpsIfd.gpsLatitude, isNull);
    expect(wieder.exif.gpsIfd.gpsLongitude, isNull);

    // Und dasselbe noch einmal roh über das ganze PDF: Auch der Rest des
    // Dokuments darf die Angaben nirgends tragen.
    final text = String.fromCharCodes(ergebnis.bytes);
    expect(text, isNot(contains('GEHEIME_KAMERA')));
    expect(text, isNot(contains('GEHEIMES_MODELL')));
    expect(text, isNot(contains('Urlaub-Privat')));
  });
}

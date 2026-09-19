import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../db/database.dart';
import 'export_service.dart';
import 'storage_paths.dart';

/// Baut ein schlichtes, druckbares Kontaktblatt aus einer Auswahl.
///
/// Es nutzt vorhandene JPEG-Vorschaubilder; bei fehlender Vorschau wird die
/// Originaldatei nur dann verwendet, wenn sie sich lokal als Bild dekodieren
/// lässt. Videos und nicht dekodierbare Formate erscheinen damit nicht als
/// irreführende leere Kachel und werden in [ContactSheetResult.skipped]
/// ausgewiesen.
class ContactSheetService {
  const ContactSheetService(this._paths, this._exporter);

  final StoragePaths _paths;
  final ExportService _exporter;

  Future<ContactSheetResult> create(List<AssetData> assets) async {
    final document = pw.Document();
    final tiles = <pw.Widget>[];
    var skipped = 0;
    for (var index = 0; index < assets.length; index++) {
      final asset = assets[index];
      final image = await _loadImage(asset);
      if (image == null) {
        skipped++;
        continue;
      }
      tiles.add(pw.Container(
        width: 170,
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(children: [
          pw.SizedBox(
            height: 112,
            child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
          pw.SizedBox(height: 3),
          // Nur Nummer und Datum: Die PDF-Standardschrift kann keine Namen
          // mit jedem Unicode-Zeichen setzen, und ein Kontaktblatt braucht
          // keine privaten Dateinamen preiszugeben.
          pw.Text('${index + 1}  ${_date(asset.fileCreatedAt)}',
              style: const pw.TextStyle(fontSize: 8)),
        ]),
      ));
    }
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => tiles,
    ));
    return ContactSheetResult(
      bytes: await document.save(),
      included: tiles.length,
      skipped: skipped,
    );
  }

  Future<pw.MemoryImage?> _loadImage(AssetData asset) async {
    final thumbnail = _paths.absolute(_paths.thumbnailRelativePath(asset.id));
    if (await thumbnail.exists()) {
      final fromThumbnail = await _decode(thumbnail.readAsBytes());
      if (fromThumbnail != null) return fromThumbnail;
    }
    try {
      return await _decode(
          (await _exporter.resolveSourceFile(asset)).readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<pw.MemoryImage?> _decode(Future<Uint8List> bytesFuture) async {
    try {
      final bytes = await bytesFuture;
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return pw.MemoryImage(Uint8List.fromList(img.encodeJpg(decoded)));
      }
    } catch (_) {
      // Ein nicht lesbares Bild wird durch den nächsten Kandidaten ersetzt.
    }
    return null;
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class ContactSheetResult {
  const ContactSheetResult({
    required this.bytes,
    required this.included,
    required this.skipped,
  });

  final Uint8List bytes;
  final int included;
  final int skipped;
}

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Lässt den Nutzer wählen, wohin eine Datei geschrieben wird, und gibt den
/// Pfad zurück – `null` heißt abgebrochen.
///
/// **Warum nicht einfach `FilePicker.saveFile`.** Seit file_picker 12
/// schreibt `saveFile` die übergebenen Bytes selbst an den gewählten Ort.
/// Die App kennt den Inhalt beim Fragen aber oft noch nicht: Ein Video
/// schreibt ffmpeg erst danach, ein PDF entsteht erst nach der Wahl. Also
/// wird mit leeren Bytes gefragt, und die App überschreibt die leere Datei.
///
/// [mitEndung] ist die Endungsregel der aufrufenden Stelle. Manche
/// Dateiwähler geben die Endung nicht mit; ohne sie erkennt etwa ffmpeg das
/// Format nicht. Ändert die Regel den Pfad, bliebe die leere Datei unter dem
/// alten Namen liegen – sie wird hier entfernt.
Future<String?> waehleSpeicherort({
  required String dialogTitel,
  required String dateiname,
  required String Function(String pfad) mitEndung,
}) async {
  final ort = await FilePicker.saveFile(
    dialogTitle: dialogTitel,
    fileName: dateiname,
    bytes: Uint8List(0),
  );
  if (ort == null || ort.scheme != 'file') return null;
  final gewaehlt = ort.toFilePath();
  final ziel = mitEndung(gewaehlt);
  if (ziel != gewaehlt) {
    final platzhalter = File(gewaehlt);
    try {
      if (platzhalter.existsSync() && platzhalter.lengthSync() == 0) {
        platzhalter.deleteSync();
      }
    } on FileSystemException {
      // Liegen bleibt dann eine leere Datei; das Schreiben geht trotzdem.
    }
  }
  return ziel;
}

/// Hängt [endung] (ohne Punkt) an, wenn [pfad] nicht schon darauf endet.
String mitDateiendung(String pfad, String endung) =>
    pfad.toLowerCase().endsWith('.${endung.toLowerCase()}')
    ? pfad
    : '$pfad.$endung';

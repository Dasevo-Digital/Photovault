import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/speicherort.dart';

/// Ein Speichern-Dialog, der sich verhält wie die echten seit file_picker
/// 12: Er schreibt die übergebenen Bytes an den gewählten Ort.
class _SchreibenderDialog extends FilePickerPlatform {
  _SchreibenderDialog(this.antwort);

  /// Was der Nutzer gewählt hätte – `null` heißt abgebrochen.
  final String? antwort;
  Uint8List? geschrieben;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final a = antwort;
    if (a == null) return null;
    geschrieben = bytes;
    File(a).writeAsBytesSync(bytes);
    return Uri.file(a);
  }
}

void main() {
  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_speicherort_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  Future<String?> waehle(String? antwort) {
    FilePickerPlatform.instance = _SchreibenderDialog(antwort);
    return waehleSpeicherort(
      dialogTitel: 'Speichern',
      dateiname: 'film.mp4',
      mitEndung: (pfad) => mitDateiendung(pfad, 'mp4'),
    );
  }

  test('gefragt wird mit leeren Bytes, die App schreibt danach', () async {
    final dialog = _SchreibenderDialog(p.join(ordner.path, 'film.mp4'));
    FilePickerPlatform.instance = dialog;
    await waehleSpeicherort(
      dialogTitel: 'Speichern',
      dateiname: 'film.mp4',
      mitEndung: (pfad) => mitDateiendung(pfad, 'mp4'),
    );
    expect(dialog.geschrieben, isEmpty);
  });

  test('mit Endung: Pfad und Platzhalter bleiben', () async {
    final ziel = p.join(ordner.path, 'film.mp4');
    expect(await waehle(ziel), ziel);
    expect(File(ziel).existsSync(), isTrue);
  });

  test('ohne Endung: angehängt, der leere Platzhalter verschwindet', () async {
    final gewaehlt = p.join(ordner.path, 'film');
    expect(await waehle(gewaehlt), '$gewaehlt.mp4');
    expect(
      File(gewaehlt).existsSync(),
      isFalse,
      reason: 'sonst bliebe eine leere Datei ohne Endung liegen',
    );
  });

  test('eine Datei mit Inhalt unter dem alten Namen bleibt', () async {
    // Der Dialog hat sie geleert – aber nur, wenn sie seine war. Hat
    // jemand dazwischen etwas hineingeschrieben, gehört sie nicht uns.
    final gewaehlt = p.join(ordner.path, 'film');
    FilePickerPlatform.instance = _SchreibenderDialog(gewaehlt);
    final ziel = await waehleSpeicherort(
      dialogTitel: 'Speichern',
      dateiname: 'film.mp4',
      mitEndung: (pfad) {
        File(pfad).writeAsStringSync('fremd');
        return mitDateiendung(pfad, 'mp4');
      },
    );
    expect(ziel, '$gewaehlt.mp4');
    expect(File(gewaehlt).readAsStringSync(), 'fremd');
  });

  test('abgebrochen ist null', () async {
    expect(await waehle(null), isNull);
  });

  test('mitDateiendung hängt nur an, was fehlt', () {
    expect(mitDateiendung('/a/film.MP4', 'mp4'), '/a/film.MP4');
    expect(mitDateiendung('/a/film', 'mp4'), '/a/film.mp4');
    expect(mitDateiendung('/a/film.mov', 'mp4'), '/a/film.mov.mp4');
  });
}

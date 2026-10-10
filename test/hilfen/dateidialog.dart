import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Der Dateidialog, nachgestellt.
///
/// Der Dialog ist ein Fenster des Betriebssystems und in einem Test nicht
/// zu öffnen. Nachgestellt wird die **Schnittstelle** des Pakets und nicht
/// sein Kanal zum Betriebssystem: In einem Test wird kein
/// Erweiterungspaket angemeldet, und ein nachgestellter Kanal käme nie zum
/// Zuge. Seit file_picker 12 ist das `FilePickerPlatform.instance`; `extends`
/// übergibt den Sicherheitsschlüssel der Basisklasse von selbst.
///
/// Was der Dialog zurückgibt, ist eine echte Datei auf der Platte, und
/// alles danach läuft unverändert.
class NachgestellterDateidialog extends FilePickerPlatform {
  NachgestellterDateidialog(this.datei);

  /// Was der Dialog zurückgibt – `null` heißt „abgebrochen".
  File? datei;

  /// Welche Wege durch diesen Dialog gegangen wurden.
  final gerufen = <String>[];

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    gerufen.add('pickFile');
    final d = datei;
    return d == null ? null : NachgestellteDatei(d);
  }

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
    gerufen.add('saveFile');
    return null;
  }
}

/// Eine echte Datei, wie sie der Dialog zurückgäbe.
final class NachgestellteDatei extends PlatformFile {
  NachgestellteDatei(this.datei);

  final File datei;

  @override
  String get name => p.basename(datei.path);

  @override
  Uri get uri => datei.uri;

  /// Braucht keiner der Wege, die die Tests gehen; `cross_file` ist keine
  /// eigene Abhängigkeit dieses Pakets.
  @override
  get xFile => throw UnsupportedError('xFile im Test nicht nachgestellt');

  @override
  int? lengthSync() => datei.lengthSync();

  @override
  Future<int?> length() => datei.length();

  @override
  Future<Uint8List> readAsBytes() => datei.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      datei.openRead().map(Uint8List.fromList);
}

import 'dart:io';

import 'package:path/path.dart' as p;

/// Wie der Server läuft.
///
/// Alles kommt aus Umgebungsvariablen, damit Docker, systemd und ein Aufruf
/// von Hand dieselben Schalter haben und kein Schalter nur in einer der drei
/// Welten existiert.
///
/// | Variable         | Vorgabe               |                                    |
/// |------------------|-----------------------|------------------------------------|
/// | `PV_DATEN`       | `./daten`             | Bibliotheken, Uploads, Zugang      |
/// | `PV_ADRESSE`     | `127.0.0.1`           | worauf gehört wird                 |
/// | `PV_PORT`        | `8790`                |                                    |
/// | `PV_MODELLE`     | `<PV_DATEN>/modelle`  | die KI-Modelle                     |
/// | `PV_ONNXRUNTIME` | im Bündel `lib/`      | `libonnxruntime.so` für die Modelle |
/// | `PV_GEODATEN`    | `<PV_DATEN>/geodaten` | GeoNames für Ortsnamen             |
///
/// Ohne `PV_ONNXRUNTIME` rechnet kein Modell: Der Server nimmt Fotos an und
/// zeigt sie, wertet aber nichts aus, was ein Modell braucht. Ohne die drei
/// GeoNames-Dateien bleiben die Ortsnamen leer, die Koordinaten nicht.
///
/// **Die Vorgabe ist nur der eigene Rechner.** Wer von aussen erreichbar
/// sein will, sagt es ausdrücklich (im Docker-Bild `0.0.0.0` hinter dem
/// Reverse Proxy) – ein Server mit allen Familienfotos soll nicht aus
/// Versehen im Netz stehen.
class Einstellungen {
  Einstellungen({
    required this.daten,
    this.adresse = '127.0.0.1',
    this.port = 8790,
    Directory? modelle,
    this.onnxRuntime,
    Directory? geodaten,
  }) : modelle = modelle ?? Directory(p.join(daten.path, 'modelle')),
       geodaten = geodaten ?? Directory(p.join(daten.path, 'geodaten'));

  factory Einstellungen.ausUmgebung([Map<String, String>? umgebung]) {
    final u = umgebung ?? Platform.environment;
    final daten = Directory(p.absolute(u['PV_DATEN'] ?? 'daten'));
    final port = int.tryParse(u['PV_PORT'] ?? '');
    return Einstellungen(
      daten: daten,
      adresse: u['PV_ADRESSE'] ?? '127.0.0.1',
      port: port ?? 8790,
      modelle: u['PV_MODELLE'] == null
          ? null
          : Directory(p.absolute(u['PV_MODELLE']!)),
      onnxRuntime: u['PV_ONNXRUNTIME'] == null
          ? onnxImBuendel()
          : File(p.absolute(u['PV_ONNXRUNTIME']!)),
      geodaten: u['PV_GEODATEN'] == null
          ? null
          : Directory(p.absolute(u['PV_GEODATEN']!)),
    );
  }

  /// Die ONNX Runtime, die im Bündel neben dem Programm liegt
  /// (`bin/photo_vault_server` und `lib/libonnxruntime.so.*`) – so findet
  /// der Server sie ohne Einstellung, im Docker-Bild wie unter systemd.
  /// Bei `dart run` liegt dort keine.
  static File? onnxImBuendel([String? programm]) {
    final lib = Directory(
      p.join(p.dirname(programm ?? Platform.resolvedExecutable), '..', 'lib'),
    );
    if (!lib.existsSync()) return null;
    final da = [
      for (final f in lib.listSync().whereType<File>())
        if (p.basename(f.path).startsWith('libonnxruntime.so')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return da.isEmpty ? null : File(p.normalize(da.last.path));
  }

  final Directory daten;
  final String adresse;
  final int port;
  final Directory modelle;
  final File? onnxRuntime;
  final Directory geodaten;

  /// Eine Bibliothek je Konto; bis es Konten gibt (Stufe 6), eine.
  Directory get bibliotheken => Directory(p.join(daten.path, 'bibliotheken'));

  /// Uploads, die noch nicht vollständig sind.
  Directory get eingang => Directory(p.join(daten.path, 'eingang'));

  File get zugangsdatei => File(p.join(daten.path, 'zugang.txt'));
}

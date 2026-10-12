import 'dart:io';

import 'package:path/path.dart' as p;

/// Wie der Server läuft.
///
/// Alles kommt aus Umgebungsvariablen, damit Docker, systemd und ein Aufruf
/// von Hand dieselben Schalter haben und kein Schalter nur in einer der drei
/// Welten existiert.
///
/// | Variable     | Vorgabe              |                                     |
/// |--------------|----------------------|-------------------------------------|
/// | `PV_DATEN`   | `./daten`            | Bibliotheken, Uploads, Zugang       |
/// | `PV_ADRESSE` | `127.0.0.1`          | worauf gehört wird                  |
/// | `PV_PORT`    | `8790`               |                                     |
/// | `PV_MODELLE` | `<PV_DATEN>/modelle` | die KI-Modelle                      |
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
  }) : modelle = modelle ?? Directory(p.join(daten.path, 'modelle'));

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
    );
  }

  final Directory daten;
  final String adresse;
  final int port;
  final Directory modelle;

  /// Eine Bibliothek je Konto; bis es Konten gibt (Stufe 6), eine.
  Directory get bibliotheken => Directory(p.join(daten.path, 'bibliotheken'));

  /// Uploads, die noch nicht vollständig sind.
  Directory get eingang => Directory(p.join(daten.path, 'eingang'));

  File get zugangsdatei => File(p.join(daten.path, 'zugang.txt'));
}

import 'dart:io';

import '../services/storage_paths.dart';

/// Was eine verbundene Bibliothek nach Bedarf vom Server holt – Vorschauen
/// und Originale – sammelt sich an und wird nie von selbst weniger (Issue
/// #131). Hier wird es gemessen, begrenzt und geleert. Miniaturen und
/// Gesichter sind der Vorrat fürs Blättern ohne Netz und bleiben.
class Zwischenspeicher {
  const Zwischenspeicher(this.paths);

  final StoragePaths paths;

  /// Die Vorgabe, wenn niemand eine Grenze gesetzt hat.
  static const vorgabeMb = 2048;

  List<Directory> get _ordner => [paths.previewsDir, paths.originalsDir];

  Future<List<File>> _dateien() async => [
    for (final o in _ordner)
      if (await o.exists())
        await for (final e in o.list(recursive: true, followLinks: false))
          if (e is File) e,
  ];

  /// Wie viele Bytes Vorschauen und Originale gerade belegen.
  Future<int> groesse() async {
    var summe = 0;
    for (final f in await _dateien()) {
      try {
        summe += await f.length();
      } on FileSystemException {
        // Zwischen Auflisten und Messen gelöscht.
      }
    }
    return summe;
  }

  /// Hält den Speicher unter [hoechstens] Bytes: Was am längsten nicht
  /// gebraucht wurde (siehe [StoragePaths.bereit], das die Zeit beim
  /// Zugriff setzt), fliegt zuerst – bis nur noch vier Fünftel belegt
  /// sind, damit nicht jeder nächste Abruf wieder aufräumt. Gibt zurück,
  /// wie viele Bytes frei wurden.
  Future<int> begrenze(int hoechstens) async {
    final dateien = <(File, int, DateTime)>[];
    var summe = 0;
    for (final f in await _dateien()) {
      try {
        final s = await f.stat();
        dateien.add((f, s.size, s.modified));
        summe += s.size;
      } on FileSystemException {
        // s. o.
      }
    }
    if (summe <= hoechstens) return 0;
    dateien.sort((a, b) => a.$3.compareTo(b.$3));
    final ziel = hoechstens * 4 ~/ 5;
    var frei = 0;
    for (final (f, bytes, _) in dateien) {
      if (summe - frei <= ziel) break;
      try {
        await f.delete();
        frei += bytes;
      } on FileSystemException {
        // Gerade in Gebrauch oder schon weg – dann eben beim nächsten Mal.
      }
    }
    return frei;
  }

  /// Löscht alle Vorschauen und Originale; was jemand wieder öffnet, kommt
  /// erneut vom Server. Gibt zurück, wie viele Bytes frei wurden.
  Future<int> leere() => begrenze(0);
}

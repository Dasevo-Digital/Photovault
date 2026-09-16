import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'library_location.dart';

/// Kapselt sämtliche Pfade der lokalen Bibliothek. Layout (Wurzelverzeichnis
/// standardmäßig im App-Support-Ordner, siehe [LibraryLocation] – kann in
/// den Einstellungen auf einen beliebigen anderen Ordner verlegt werden):
///
/// `Speicherort/`
///   library/
///     originals/{yyyy}/{mm}/{assetId}.{ext}
///     thumbnails/{assetId}.jpg
///     previews/{assetId}.jpg          (nur für HEIC/DNG & Co.: von Flutter
///                                       nicht direkt darstellbare Formate)
///     developed/{assetId}.jpg        (nur mit Entwicklungs-Anpassungen, siehe DevelopScreen)
///     restored/{assetId}.jpg         (nur mit KI-Restaurierung, siehe RestoreQueueService)
///     trimmed/{assetId}.mp4          (nur mit Video-Zuschnitt, siehe VideoTrimScreen)
///     masks/{maskId}.png             (KI-Objektmasken, siehe MaskEditor)
///     luts/{name}.cube               (importierte Farbtabellen)
///     faces/{faceId}.jpg
///     trash/{assetId}.{ext}          (physisch verschoben bis "Papierkorb leeren")
///   library.sqlite
class StoragePaths {
  StoragePaths._(this.root);

  final Directory root;

  static StoragePaths? _instance;

  static Future<StoragePaths> instance() async {
    if (_instance != null) return _instance!;
    final libraryRoot = await LibraryLocation.currentRoot();
    final root = Directory(p.join(libraryRoot.path, 'library'));
    _instance = await _createAt(root);
    return _instance!;
  }

  /// Erzeugt eine eigenständige [StoragePaths]-Instanz unter einem
  /// beliebigen Wurzelverzeichnis, ohne das `path_provider`-Plugin (das
  /// echte Platform-Channels braucht) zu berühren und ohne das
  /// App-weite Singleton zu setzen. Nur für Tests gedacht, damit
  /// ImportService/BackupService dort mit einem temporären Verzeichnis
  /// statt dem echten App-Support-Ordner arbeiten können.
  @visibleForTesting
  static Future<StoragePaths> forTesting(Directory root) => _createAt(root);

  static Future<StoragePaths> _createAt(Directory root) async {
    for (final sub in [
      'originals',
      'thumbnails',
      'previews',
      'developed',
      'restored',
      'trimmed',
      'masks',
      'faces',
      'vault_metadata',
      'luts',
      'trash',
    ]) {
      await Directory(p.join(root.path, sub)).create(recursive: true);
    }
    return StoragePaths._(root);
  }

  Directory get originalsDir => Directory(p.join(root.path, 'originals'));
  Directory get thumbnailsDir => Directory(p.join(root.path, 'thumbnails'));
  Directory get previewsDir => Directory(p.join(root.path, 'previews'));
  Directory get developedDir => Directory(p.join(root.path, 'developed'));
  Directory get restoredDir => Directory(p.join(root.path, 'restored'));
  Directory get trimmedDir => Directory(p.join(root.path, 'trimmed'));

  /// Importierte Farbtabellen (`.cube`).
  ///
  /// Sie werden in die Bibliothek kopiert statt nur verwiesen: Eine
  /// Entwicklung, die auf eine Datei im Download-Ordner zeigt, sähe nach
  /// dem nächsten Aufräumen anders aus – und ein Backup enthielte den Look
  /// nicht.
  Directory get lutsDir => Directory(p.join(root.path, 'luts'));

  String lutRelativePath(String dateiname) => p.join('luts', dateiname);

  Directory get masksDir => Directory(p.join(root.path, 'masks'));
  Directory get facesDir => Directory(p.join(root.path, 'faces'));
  Directory get vaultMetadataDir =>
      Directory(p.join(root.path, 'vault_metadata'));
  Directory get trashDir => Directory(p.join(root.path, 'trash'));

  String originalRelativePath(
      DateTime fileCreatedAt, String assetId, String extension) {
    final yyyy = fileCreatedAt.year.toString().padLeft(4, '0');
    final mm = fileCreatedAt.month.toString().padLeft(2, '0');
    return p.join('originals', yyyy, mm, '$assetId$extension');
  }

  String thumbnailRelativePath(String assetId) =>
      p.join('thumbnails', '$assetId.jpg');

  /// Nur für Formate relevant, die Flutter nicht direkt rendern kann
  /// (HEIC/HEIF, DNG & Co.) – eine größere, konvertierte JPEG-Version für
  /// die Vollbildansicht (Thumbnails bleiben separat und kleiner).
  String previewRelativePath(String assetId) =>
      p.join('previews', '$assetId.jpg');

  /// Gerendertes Ergebnis der nicht-destruktiven Entwicklung (siehe
  /// DevelopScreen) – separat von [previewRelativePath], damit sich beide
  /// unabhängig regenerieren lassen (die reine Vorschau z.B. beim
  /// HEIC/RAW-Import, das entwickelte Bild nur bei geänderten Reglern).
  String developedRelativePath(String assetId) =>
      p.join('developed', '$assetId.jpg');

  /// Ergebnis einer KI-Restaurierung (siehe RestoreQueueService,
  /// RestoreJobs) – separat von [developedRelativePath], da beide
  /// unabhängig voneinander existieren können (Restaurierung nimmt das
  /// bereits entwickelte Ergebnis als Eingabe, falls vorhanden).
  String restoredRelativePath(String assetId) =>
      p.join('restored', '$assetId.jpg');

  /// Ergebnis des nicht-destruktiven Video-Zuschnitts (siehe
  /// VideoTrimScreen) – separat von [originalRelativePath], die
  /// Originaldatei wird nie angetastet.
  String trimmedRelativePath(String assetId) =>
      p.join('trimmed', '$assetId.mp4');

  String faceRelativePath(String faceId) => p.join('faces', '$faceId.jpg');
  String vaultMetadataRelativePath(String assetId) =>
      p.join('vault_metadata', '$assetId.pvm');

  /// Grauwert-Alphamaske einer KI-Objektmaske (siehe MaskEditor,
  /// SegmentationService.maskToOriginalResolution). Nimmt bewusst eine vom
  /// Aufrufer erzeugte UUID statt der Auto-Increment-`id` der DevelopMasks-
  /// Zeile entgegen – die ist erst NACH dem Einfügen der Zeile bekannt, der
  /// Dateiname muss aber schon vorher feststehen, um die Datei zu schreiben.
  String maskRelativePath(String maskFileId) =>
      p.join('masks', '$maskFileId.png');

  /// XMP-Sidecar-Pfad zu einer beliebigen bereits vorhandenen Datei (siehe
  /// xmp_writer.dart) – ein Sidecar muss denselben Basisnamen wie die
  /// tatsächlich auf der Platte liegende Datei tragen, damit Lightroom/
  /// darktable/digiKam ihn beim Ordner-Scan zuordnen. Nimmt bewusst
  /// [filePath] statt einer Asset-ID entgegen und tauscht nur die Endung
  /// aus – funktioniert dadurch gleichermaßen für relative Pfade innerhalb
  /// der Bibliothek (`{assetId}`-basiert) UND für absolute Export-/Backup-
  /// Zielpfade (`originalFileName`-basiert, siehe
  /// ExportService._uniqueDestinationPath), ohne eigene Fallunterscheidung.
  String xmpSidecarPath(String filePath) => p.setExtension(filePath, '.xmp');

  /// Löst einen in der Datenbank gespeicherten Bibliothekspfad auf.
  ///
  /// Datenbankwerte sind auch dann keine vertrauenswürdigen Dateipfade, wenn
  /// die Oberfläche selbst nur von uns erzeugte Werte schreibt: Eine alte,
  /// beschädigte oder von außen eingespielte `library.sqlite` kann absolute
  /// Pfade oder `..`-Segmente enthalten. Ohne diese Grenze würden insbesondere
  /// [deletePermanently] und die Papierkorb-Automatik außerhalb der Bibliothek
  /// lesen oder löschen.
  File absolute(String relativePath) {
    if (relativePath.isEmpty || p.isAbsolute(relativePath)) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Kein relativer Bibliothekspfad');
    }
    final basis = p.normalize(p.absolute(root.path));
    final ziel = p.normalize(p.absolute(p.join(basis, relativePath)));
    if (!p.isWithin(basis, ziel)) {
      throw ArgumentError.value(
          relativePath, 'relativePath', 'Path leaves the library root');
    }
    return File(ziel);
  }

  /// Verschiebt eine Originaldatei physisch in den Papierkorb-Ordner (wird
  /// beim "Papierkorb leeren" endgültig gelöscht). Gibt den neuen relativen
  /// Pfad zurück.
  Future<String> moveToPhysicalTrash(String currentRelativePath) async {
    final source = absolute(currentRelativePath);
    final target = File(p.join(trashDir.path, p.basename(currentRelativePath)));
    if (await source.exists()) {
      await source.rename(target.path);
    }
    return p.join('trash', p.basename(currentRelativePath));
  }

  Future<void> deletePermanently(String relativePath) async {
    final file = absolute(relativePath);
    if (await file.exists()) await file.delete();
  }

  /// Gesamtgröße aller Originaldateien in Bytes.
  Future<int> totalOriginalsSizeBytes() async {
    var total = 0;
    if (!await originalsDir.exists()) return 0;
    await for (final entity
        in originalsDir.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Die Unterordner, die die Bibliothek anlegt – in der Reihenfolge, in
  /// der sie in der Aufstellung stehen sollen.
  static const List<String> belegungsordner = [
    'originals',
    'previews',
    'thumbnails',
    'developed',
    'restored',
    'trimmed',
    'masks',
    'faces',
    'vault_metadata',
    'luts',
    'trash',
  ];

  /// Was die Bibliothek belegt – nach Teilen aufgeschlüsselt.
  ///
  /// **Warum es das braucht.** Die Anzeige in den Einstellungen zählte
  /// allein `originals/`. Aus dem Erstlauf-Bericht: „Es werden nur
  /// Originale ausgewiesen, Vorschauen und DB-Größe nicht. Speicherbedarf
  /// wird mit 1,57 GB angezeigt, real im Finder 1,75 GB." Die fehlenden
  /// 180 MB sind Vorschauen, Miniaturen, Gesichtsausschnitte und die
  /// Datenbank – alles Dinge, die die App selbst anlegt und die deshalb
  /// gerade interessant sind.
  ///
  /// `library.sqlite` liegt **neben** der Bibliothek, nicht darin, und
  /// wird deshalb eigens gesucht – samt ihrer WAL- und SHM-Nebendateien,
  /// die zusammen durchaus ein paar hundert Megabyte ausmachen können.
  Future<Bibliotheksbelegung> belegung() async {
    final teile = <String, int>{};
    var sonstiges = 0;
    if (await root.exists()) {
      await for (final eintrag
          in root.list(recursive: true, followLinks: false)) {
        if (eintrag is! File) continue;
        final laenge = await eintrag.length();
        final rest = p.relative(eintrag.path, from: root.path);
        final erster = p.split(rest).first;
        if (belegungsordner.contains(erster)) {
          teile[erster] = (teile[erster] ?? 0) + laenge;
        } else {
          // Alles, was nicht in einen der bekannten Ordner gehört: eine
          // vergessene Datei, ein Rest aus einer früheren Fassung. Sie
          // unter den Tisch fallen zu lassen hiesse, die Summe wieder zu
          // klein zu machen – und genau das war der Fehler.
          sonstiges += laenge;
        }
      }
    }
    var datenbank = 0;
    final neben = root.parent;
    for (final endung in ['', '-wal', '-shm']) {
      final datei = File(p.join(neben.path, 'library.sqlite$endung'));
      if (await datei.exists()) datenbank += await datei.length();
    }
    return Bibliotheksbelegung(
        teile: teile, sonstiges: sonstiges, datenbank: datenbank);
  }

  /// Entfernt ausschließlich abgebrochene Schreibreste, die kein gültiger
  /// Bibliotheksbestand sein können. Frische Dateien bleiben unangetastet,
  /// damit eine parallel laufende Einfuhr oder Verschlüsselung nicht gestört
  /// wird.
  Future<({int dateien, int bytes})> bereinigeSchreibreste({
    Duration mindestalter = const Duration(hours: 24),
  }) async {
    var dateien = 0;
    var bytes = 0;
    final grenze = DateTime.now().subtract(mindestalter);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !(entity.path.endsWith('.part') ||
              entity.path.endsWith('.vaulttmp'))) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (!stat.modified.isBefore(grenze)) continue;
        bytes += stat.size;
        await entity.delete();
        dateien++;
      } on FileSystemException {
        // Zwischen Prüfung und Löschen bereits verschwunden.
      }
    }
    return (dateien: dateien, bytes: bytes);
  }
}

/// Was die Bibliothek belegt, nach Teilen getrennt – siehe
/// [StoragePaths.belegung].
class Bibliotheksbelegung {
  const Bibliotheksbelegung({
    required this.teile,
    required this.sonstiges,
    required this.datenbank,
  });

  /// Bytes je Unterordner, Schlüssel wie der Ordnername.
  final Map<String, int> teile;

  /// Was in keinen der bekannten Ordner fiel.
  final int sonstiges;

  /// `library.sqlite` samt WAL/SHM.
  final int datenbank;

  int get gesamt =>
      datenbank + sonstiges + teile.values.fold<int>(0, (a, b) => a + b);

  /// Die Posten in der Reihenfolge der Aufstellung, ohne die leeren.
  ///
  /// Leere Posten wegzulassen ist kein Verstecken: Eine Zeile „Masken 0
  /// B" sagt nichts, und zehn davon machen die drei, auf die es ankommt,
  /// unauffindbar.
  List<({String name, int bytes})> get posten => [
        for (final ordner in StoragePaths.belegungsordner)
          if ((teile[ordner] ?? 0) > 0) (name: ordner, bytes: teile[ordner]!),
        if (datenbank > 0) (name: 'datenbank', bytes: datenbank),
        if (sonstiges > 0) (name: 'sonstiges', bytes: sonstiges),
      ];
}

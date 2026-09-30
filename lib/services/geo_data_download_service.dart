import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'geo_data_catalog.dart';

/// Warum der Standortdaten-Download gescheitert ist – siehe
/// [ModellDownloadFehler] für die Begründung, warum hier kein fertiger Satz
/// steht.
class GeoDownloadFehler implements Exception {
  final String datei;
  final String? ursache;

  /// true, wenn das Entpacken fehlschlug (nicht der Download selbst).
  final bool beimEntpacken;

  /// Gesetzt, wenn die Datei die erlaubte Groesse ueberschritten hat.
  final int? groessengrenze;

  const GeoDownloadFehler.uebertragung(this.datei, this.ursache)
      : beimEntpacken = false,
        groessengrenze = null;
  const GeoDownloadFehler.entpacken(this.datei, this.ursache)
      : beimEntpacken = true,
        groessengrenze = null;
  const GeoDownloadFehler.nichtImZip(this.datei)
      : ursache = null,
        beimEntpacken = true,
        groessengrenze = null;

  /// **Die Grenze als Zahl, nicht als fertiger Satz.** Vorher stand hier
  /// ein deutscher Satz, der ueber `ursache` unveraendert in die
  /// Oberflaeche lief – auch in die englische. Wer den Text setzt, ist
  /// der Bildschirm; dieser Dienst trägt nur die Zahl.
  const GeoDownloadFehler.zuGross(this.datei, this.groessengrenze)
      : ursache = null,
        beimEntpacken = false;
}

class GeoDataDownloadProgress {
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  GeoDataDownloadProgress(this.fileName, this.receivedBytes, this.totalBytes);

  double get fraction => totalBytes <= 0 ? 0 : receivedBytes / totalBytes;
}

/// Lädt den GeoNames-Datensatz (siehe [GeoDataCatalog]) in einen lokalen
/// Ordner herunter und entpackt die Städteliste – danach steht
/// [ReverseGeocoder] komplett offline zur Verfügung. Bewusst analog zu
/// ModelDownloadService aufgebaut (gleiches Download-/Fortschritts-Muster),
/// aber eine eigenständige, kleinere Klasse: anders als bei den KI-Modellen
/// gibt es keine Prüfsummen-Verifikation (siehe GeoDataCatalog) und ein
/// Entpack-Schritt kommt hinzu.
class GeoDataDownloadService {
  GeoDataDownloadService(this.geoDataDir, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: false,
              validateStatus: (status) => status == 200,
            ));

  final String geoDataDir;
  final Dio _dio;

  bool get isInstalled =>
      File(p.join(geoDataDir, GeoDataCatalog.citiesFileName)).existsSync() &&
      File(p.join(geoDataDir, GeoDataCatalog.admin1FileName)).existsSync() &&
      File(p.join(geoDataDir, GeoDataCatalog.countryFileName)).existsSync();

  File get citiesFile =>
      File(p.join(geoDataDir, GeoDataCatalog.citiesFileName));
  File get admin1File =>
      File(p.join(geoDataDir, GeoDataCatalog.admin1FileName));
  File get countryFile =>
      File(p.join(geoDataDir, GeoDataCatalog.countryFileName));

  Stream<GeoDataDownloadProgress> download() {
    late StreamController<GeoDataDownloadProgress> controller;
    controller = StreamController<GeoDataDownloadProgress>(onListen: () async {
      // Als Geschwister anlegen, nicht IN `geoDataDir`: Nur so können wir
      // den geprüften Satz danach per Verzeichniswechsel aktivieren. Ein
      // teilweises Ersetzen einzelner Dateien ließe bei vollem Datenträger
      // oder einem I/O-Fehler eine gemischte Ortsdatenbank zurück.
      final staging = Directory(
          '$geoDataDir.download-${DateTime.now().microsecondsSinceEpoch}');
      await Directory(geoDataDir).parent.create(recursive: true);
      await staging.create(recursive: true);
      try {
        for (final file in GeoDataCatalog.files) {
          final tmpPath = p.join(staging.path, file.fileName);
          final cancel = CancelToken();
          await _dio.download(
            file.url,
            tmpPath,
            cancelToken: cancel,
            onReceiveProgress: (received, total) {
              if (received > file.maxBytes || total > file.maxBytes) {
                cancel.cancel('download too large');
                return;
              }
              controller
                  .add(GeoDataDownloadProgress(file.fileName, received, total));
            },
          );
          final downloaded = await File(tmpPath).length();
          if (downloaded <= 0 || downloaded > file.maxBytes) {
            throw GeoDownloadFehler.zuGross(file.fileName, file.maxBytes);
          }
        }

        try {
          await _extractCitiesZip(staging.path);
        } catch (e) {
          controller.addError(GeoDownloadFehler.entpacken(
              GeoDataCatalog.citiesZipFileName, '$e'));
          await controller.close();
          return;
        }

        // Erst wenn ALLE Dateien da und entpackbar sind, ersetzt der neue
        // Satz den alten. Ein Netzabbruch lässt so den bisherigen Offline-
        // Geocoder vollständig nutzbar.
        for (final name in [
          GeoDataCatalog.citiesFileName,
          GeoDataCatalog.admin1FileName,
          GeoDataCatalog.countryFileName,
        ]) {
          final source = File(p.join(staging.path, name));
          if (!await source.exists() || await source.length() == 0) {
            throw GeoDownloadFehler.nichtImZip(name);
          }
        }
        await _aktiviereStagingAtomar(staging);
        await controller.close();
      } catch (e) {
        controller.addError(e is GeoDownloadFehler
            ? e
            : GeoDownloadFehler.uebertragung('Standortdaten', '$e'));
        await controller.close();
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    });
    return controller.stream;
  }

  /// Aktiviert den kompletten, bereits validierten Satz mit zwei Umbenennungen
  /// im selben Elternordner. Scheitert die zweite, wird der bisherige Satz
  /// zurückbenannt. Dadurch sieht der Offline-Geocoder nie eine Mischung aus
  /// alten und neuen Dateien.
  Future<void> _aktiviereStagingAtomar(Directory staging) async {
    final active = Directory(geoDataDir);
    final previous = Directory(
        '$geoDataDir.previous-${DateTime.now().microsecondsSinceEpoch}');
    final hadActive = await active.exists();
    var oldParked = false;
    try {
      if (hadActive) {
        await active.rename(previous.path);
        oldParked = true;
      }
      await staging.rename(active.path);
    } catch (_) {
      if (oldParked && !await active.exists() && await previous.exists()) {
        await previous.rename(active.path);
      }
      rethrow;
    }
    if (await previous.exists()) {
      try {
        await previous.delete(recursive: true);
      } catch (_) {
        // Der neue Satz ist bereits aktiv. Eine liegengebliebene, private
        // Rückfallkopie ist sicherer als einen erfolgreichen Download als
        // Fehler zu melden.
      }
    }
  }

  /// Entpackt `cities1000.txt` aus dem heruntergeladenen Zip und löscht das
  /// Zip anschließend wieder – nur die entpackte Textdatei wird dauerhaft
  /// gebraucht.
  Future<void> _extractCitiesZip(String directory) async {
    final zipFile = File(p.join(directory, GeoDataCatalog.citiesZipFileName));
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.files.firstWhere(
      (f) => f.isFile && p.basename(f.name) == GeoDataCatalog.citiesFileName,
      orElse: () => throw const GeoDownloadFehler.nichtImZip(
          GeoDataCatalog.citiesFileName),
    );
    // `archive` entpackt in den Speicher. Die begrenzte ZIP-Datei und diese
    // zusätzliche Obergrenze verhindern daher auch eine Zip-Bombe.
    if (entry.size > 64 * 1024 * 1024) {
      throw const GeoDownloadFehler.zuGross(
          GeoDataCatalog.citiesFileName, 64 * 1024 * 1024);
    }
    final targetFile = File(p.join(directory, GeoDataCatalog.citiesFileName));
    await targetFile.writeAsBytes(entry.content as List<int>);
    await zipFile.delete();
  }

  Future<void> deleteAll() async {
    for (final f in [citiesFile, admin1File, countryFile]) {
      if (await f.exists()) await f.delete();
    }
  }
}

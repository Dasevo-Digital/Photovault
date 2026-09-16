import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import 'model_catalog.dart';

/// Warum ein Modell-Download gescheitert ist.
///
/// Kein fertiger Satz: Dieser Dienst kennt keine Oberflächensprache. Die
/// Teile (Dateiname, Prüfsummen) reicht er mit, den Satz baut der
/// Einstellungs-Bildschirm.
class ModellDownloadFehler implements Exception {
  final String datei;

  /// Gesetzt, wenn die Prüfsumme nicht stimmte – dann ist der Download
  /// bewusst verworfen worden.
  final String? erhalten;
  final String? erwartet;

  /// Gesetzt, wenn die Übertragung selbst fehlschlug.
  final String? ursache;

  const ModellDownloadFehler.pruefsumme(this.datei, this.erhalten, this.erwartet)
      : ursache = null;
  const ModellDownloadFehler.uebertragung(this.datei, this.ursache)
      : erhalten = null,
        erwartet = null;
}


class ModelDownloadProgress {
  final String fileName;
  final int receivedBytes;
  final int totalBytes;
  ModelDownloadProgress(this.fileName, this.receivedBytes, this.totalBytes);

  double get fraction => totalBytes <= 0 ? 0 : receivedBytes / totalBytes;
}

/// Lädt die Dateien eines [ModelCatalogEntry] in den lokalen Modell-Ordner
/// herunter. Bewusst ein simpler, direkter HTTP-Download ohne
/// Cloud-Zwischendienst – die App spricht dabei ausschließlich mit den in
/// [ModelCatalog] hinterlegten, öffentlichen Open-Source-Quellen
/// (GitHub/HuggingFace), nie mit einem eigenen Server.
/// Zustand einer einzelnen Modelldatei bei der Nachprüfung.
///
/// Sprachfrei wie [Gradart] und die übrigen Aufzählungen der Dienste: Der
/// Satz dazu entsteht in der Oberfläche, nicht hier.
enum Modellzustand {
  /// Prüfsumme stimmt – die Datei ist die, die der Katalog nennt.
  stimmt,

  /// Gar nicht da.
  fehlt,

  /// Falsche Länge. Fast immer ein abgebrochener Download, manchmal eine
  /// veraltete Fassung aus einem früheren Katalog.
  zuKurz,

  /// Richtige Länge, falscher Inhalt. Der einzige Zustand, den allein das
  /// Nachrechnen findet – und der Grund, warum es ihn gibt.
  weichtAb,
}

class Modellbefund {
  final String dateiname;
  final Modellzustand zustand;
  const Modellbefund(this.dateiname, this.zustand);

  bool get inOrdnung => zustand == Modellzustand.stimmt;
}

class ModelDownloadService {
  /// [datenGrenze] misst die Pause ZWISCHEN zwei Datenstücken, nicht die
  /// Gesamtdauer – eine 350-MB-Datei darf also beliebig lange laufen, solange
  /// sie überhaupt läuft. Beide Grenzen sind einstellbar, damit ein Test nicht
  /// eine Minute auf eine absichtlich abgebrochene Verbindung warten muss.
  ModelDownloadService(
    this.modelsDir, {
    Duration verbindungsGrenze = const Duration(seconds: 30),
    Duration datenGrenze = const Duration(seconds: 60),
  }) : _dio = Dio(BaseOptions(
          connectTimeout: verbindungsGrenze,
          receiveTimeout: datenGrenze,
        ));

  final String modelsDir;
  final Dio _dio;

  /// Wie oft eine einzelne Datei erneut versucht wird, bevor der Eintrag
  /// als gescheitert gilt.
  static const _versuche = 3;

  /// Gilt der Eintrag als einsatzbereit?
  ///
  /// Bis zur 21. Prüfrunde lautete die ganze Frage „liegt die Datei da?".
  /// Das war an zwei Stellen zu wenig:
  ///
  /// * Eine **abgeschnittene** Datei – abgebrochener Download, volle
  ///   Platte – galt als installiert, und der Fehler kam erst beim Laden
  ///   des Modells heraus.
  /// * Eine im Katalog **geänderte Fassung** erreichte niemanden, der das
  ///   Modell schon hatte. Beim Wechsel von CLIP auf fp16 wäre die alte
  ///   Datei stillschweigend liegengeblieben, für immer und ohne Hinweis.
  ///
  /// Die Länge beantwortet beides für den Preis eines `stat`. Was sie
  /// nicht beantwortet – ob jemand die Datei gegen eine gleich grosse
  /// getauscht hat –, beantwortet [pruefe].
  bool isEntryInstalled(ModelCatalogEntry entry) =>
      entry.files.every((f) => _laengePasst(f));

  bool _laengePasst(ModelFile f) {
    final datei = File(p.join(modelsDir, f.fileName));
    if (!datei.existsSync()) return false;
    return datei.lengthSync() == f.bytes;
  }

  /// Lädt alle Dateien eines Katalog-Eintrags herunter und meldet dabei
  /// laufend den Byte-Fortschritt der jeweils aktiven Datei.
  Stream<ModelDownloadProgress> download(ModelCatalogEntry entry) {
    late StreamController<ModelDownloadProgress> controller;
    controller = StreamController<ModelDownloadProgress>(onListen: () async {
      for (final file in entry.files) {
        final targetPath = p.join(modelsDir, file.fileName);
        final tmpPath = '$targetPath.part';
        final erwartet = file.sha256.toLowerCase();

        Object? letzterFehler;
        String? letzteFalscheSumme;

        // Mehrere Anläufe, und zwar dort weiter, wo der vorige aufhörte.
        // Vorher verwarf ein einziger Abbruch alles Geladene: Bei
        // clip_image_encoder.onnx sind das 352 MB, die komplett noch einmal
        // durch die Leitung mussten. Die Prüfsumme unten bleibt die
        // Garantie – geht beim Fortsetzen irgendetwas schief, fällt es
        // dort auf und der Versuch beginnt von vorn.
        for (var versuch = 1; versuch <= _versuche; versuch++) {
          // Ein Zug statt zweier: `exists()` und danach `length()` sind zwei
          // Blicke auf die Platte, und dazwischen kann die Datei weg sein.
          // Genau daran ist der erste Lauf dieses Tests gescheitert.
          var schonDa = 0;
          try {
            schonDa = await File(tmpPath).length();
          } on FileSystemException {
            schonDa = 0;
          }
          try {
            await _dio.download(
              file.url,
              tmpPath,
              // Ohne das wäre der Fortschritt nach jedem Abbruch weg – und
              // damit der ganze Sinn dieser Schleife.
              deleteOnError: false,
              fileAccessMode:
                  schonDa > 0 ? FileAccessMode.append : FileAccessMode.write,
              options: Options(
                headers: schonDa > 0 ? {'range': 'bytes=$schonDa-'} : null,
                // Beim Fortsetzen wird 206 VERLANGT. Ein Server, der Range
                // nicht kann, antwortet mit 200 und dem ganzen Inhalt – der
                // würde an die halbe Datei angehängt und ergäbe Unsinn.
                // Lieber hier scheitern und unten von vorn anfangen.
                validateStatus: (s) =>
                    s != null && (schonDa > 0 ? s == 206 : s == 200),
              ),
              onReceiveProgress: (received, total) {
                controller.add(ModelDownloadProgress(
                  file.fileName,
                  schonDa + received,
                  total > 0 ? schonDa + total : total,
                ));
              },
            );

            final tatsaechlich = await _sha256OfFile(File(tmpPath));
            if (tatsaechlich == erwartet) {
              await File(tmpPath).rename(targetPath);
              letzterFehler = null;
              letzteFalscheSumme = null;
              break;
            }

            // Falsche Prüfsumme: Der Rumpf ist unbrauchbar, ein weiterer
            // Anlauf darf nicht darauf aufsetzen.
            letzteFalscheSumme = tatsaechlich;
            letzterFehler = null;
            if (await File(tmpPath).exists()) await File(tmpPath).delete();
          } catch (e) {
            letzterFehler = e;
            letzteFalscheSumme = null;
            // Wurde das Fortsetzen abgelehnt, ist die halbe Datei wertlos;
            // bei einem gewöhnlichen Abbruch bleibt sie als Vorschuss für
            // den nächsten Anlauf liegen.
            final abgelehnt = e is DioException &&
                e.response != null &&
                e.response!.statusCode != 206 &&
                schonDa > 0;
            if (abgelehnt && await File(tmpPath).exists()) {
              await File(tmpPath).delete();
            }
          }
        }

        if (letzteFalscheSumme != null) {
          controller.addError(ModellDownloadFehler.pruefsumme(
              file.fileName, letzteFalscheSumme, erwartet));
          await controller.close();
          return;
        }
        if (letzterFehler != null) {
          final rest = File(tmpPath);
          if (await rest.exists()) await rest.delete();
          controller.addError(ModellDownloadFehler.uebertragung(
              file.fileName, '$letzterFehler'));
          await controller.close();
          return;
        }
      }
      await controller.close();
    });
    return controller.stream;
  }

  /// Berechnet die SHA-256-Prüfsumme streamend (statt die Datei komplett in
  /// den Speicher zu laden – die CLIP-ONNX-Dateien sind mehrere hundert MB
  /// groß).
  Future<String> _sha256OfFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Was bei der Prüfung einer einzelnen Modelldatei herauskam.
  ///
  /// [fehlt] und [zuKurz] fallen schon [isEntryInstalled] auf; sie stehen
  /// hier trotzdem, damit ein Bericht nicht schweigt, wo etwas fehlt.
  /// [weichtAb] ist der Fall, für den es diese Prüfung gibt: Die Datei hat
  /// die richtige Länge und den falschen Inhalt.
  Future<List<Modellbefund>> pruefe(ModelCatalogEntry entry) async {
    final befunde = <Modellbefund>[];
    for (final f in entry.files) {
      final datei = File(p.join(modelsDir, f.fileName));
      if (!datei.existsSync()) {
        befunde.add(Modellbefund(f.fileName, Modellzustand.fehlt));
        continue;
      }
      if (await datei.length() != f.bytes) {
        befunde.add(Modellbefund(f.fileName, Modellzustand.zuKurz));
        continue;
      }
      final tatsaechlich = await _sha256OfFile(datei);
      befunde.add(Modellbefund(
          f.fileName,
          tatsaechlich == f.sha256.toLowerCase()
              ? Modellzustand.stimmt
              : Modellzustand.weichtAb));
    }
    return befunde;
  }

  /// Alle installierten Einträge nachrechnen.
  ///
  /// Nicht installierte bleiben aussen vor – „fehlt" ist kein Befund,
  /// wenn niemand das Modell haben wollte. Gemessen kostet der Durchgang
  /// über alle Modelle rund 2,6 Sekunden (CLIP allein 1,12 s für 606 MB);
  /// deshalb hängt er an einem Knopf und nicht am Programmstart.
  Future<List<Modellbefund>> pruefeAlleInstallierten(
      List<ModelCatalogEntry> eintraege,
      {void Function(String dateiname)? fortschritt}) async {
    final befunde = <Modellbefund>[];
    for (final eintrag in eintraege) {
      // Nicht `isEntryInstalled`: Das ist gerade die Prüfung, die hier
      // schärfer wiederholt wird – eine zu kurze Datei soll im Bericht
      // stehen und nicht dazu führen, dass der Eintrag übersprungen wird.
      final irgendwasDa = eintrag.files
          .any((f) => File(p.join(modelsDir, f.fileName)).existsSync());
      if (!irgendwasDa) continue;
      for (final f in eintrag.files) {
        fortschritt?.call(f.fileName);
      }
      befunde.addAll(await pruefe(eintrag));
    }
    return befunde;
  }

  Future<void> deleteEntry(ModelCatalogEntry entry) async {
    for (final name in [
      ...entry.files.map((f) => f.fileName),
      // Selbst erzeugte Dateien gehören mit weg. Wer etwas anlegt, muss
      // aufräumen, sonst tut es niemand – siehe [raeumeAbgeloesteModelle].
      ...entry.abgeleiteteDateien,
    ]) {
      final f = File(p.join(modelsDir, name));
      if (await f.exists()) await f.delete();
    }
  }

  /// Wie viel Platz die Dateien eines Eintrags tatsächlich belegen.
  /// Fehlende Dateien zählen als 0, ein nicht installierter Eintrag ergibt
  /// also 0.
  ///
  /// Bewusst synchron und ohne Zwischenspeicher: Es sind eine Handvoll
  /// `stat`-Aufrufe, und die Oberfläche prüft an derselben Stelle ohnehin
  /// schon synchron auf Vorhandensein (siehe [isEntryInstalled]).
  int belegteBytes(ModelCatalogEntry entry) {
    var summe = 0;
    for (final name in [
      ...entry.files.map((f) => f.fileName),
      ...entry.abgeleiteteDateien,
    ]) {
      final datei = File(p.join(modelsDir, name));
      if (datei.existsSync()) summe += datei.lengthSync();
    }
    return summe;
  }

  /// Gesamter Platzbedarf des Modellordners – auch Dateien, die zu keinem
  /// Katalog-Eintrag (mehr) gehören. Der Ordner wächst schnell auf über ein
  /// Gigabyte, ohne dass die App das bisher irgendwo auswies.
  int gesamteBytes() {
    final dir = Directory(modelsDir);
    if (!dir.existsSync()) return 0;
    var summe = 0;
    for (final e in dir.listSync()) {
      if (e is File) summe += e.lengthSync();
    }
    return summe;
  }

  /// Entfernt liegengebliebene `.part`-Dateien abgebrochener Downloads.
  ///
  /// Der Fehlerpfad des Downloads räumt selbst auf; wird die App aber
  /// mitten im Herunterladen beendet oder stürzt ab, bleibt die halbe
  /// Datei zurück – bis zu 335 MB, ohne dass irgendwo etwas darauf
  /// hinweist. Wiederaufnehmen lässt sie sich ohnehin nicht (der Download
  /// beginnt jedes Mal von vorn), sie ist also reiner Ballast
  /// (Audit-Fund).
  ///
  /// Nur beim Programmstart aufrufen: Während ein Download läuft, wäre
  /// genau diese Datei in Benutzung.
  Future<int> raeumeAbgebrocheneDownloads() async {
    final dir = Directory(modelsDir);
    if (!await dir.exists()) return 0;
    var entfernt = 0;
    await for (final eintrag in dir.list()) {
      if (eintrag is File && eintrag.path.endsWith('.part')) {
        try {
          await eintrag.delete();
          entfernt++;
        } catch (e) {
          debugPrint('Rest eines Downloads liess sich nicht entfernen: $e');
        }
      }
    }
    return entfernt;
  }

  /// Dateien des abgelösten Beschreibungsmodells (ViT-GPT2), das seit
  /// Version 1.4 durch Florence-2 ersetzt ist.
  ///
  /// Sie stehen in keinem Katalogeintrag mehr und liessen sich deshalb
  /// auch nicht mehr über die Modellverwaltung löschen – 246 MB, die
  /// niemand je wieder anfasst. Dasselbe Muster wie bei den verwaisten
  /// Gesichtsausschnitten der achten Prüfrunde: Wer etwas ablöst, muss
  /// aufräumen, sonst tut es niemand.
  ///
  /// Nur beim Programmstart aufrufen, aus demselben Grund wie oben.
  Future<int> raeumeAbgeloesteModelle() async {
    const abgeloest = [
      'caption_encoder.onnx',
      'caption_decoder.onnx',
      'caption_vocab.json',
      // Die Zeichentabelle des alten Lesemodells (latin_PP-OCRv3). Seit
      // dem Wechsel auf v5 steht die Tabelle in `ocr_rec.yml`, und diese
      // Datei gehört zu keinem Eintrag mehr – klein, aber sie würde sonst
      // für immer liegenbleiben und beim Lesen des Ordners verwirren.
      'ocr_dict.txt',
    ];
    var bytes = 0;
    for (final name in abgeloest) {
      final f = File('$modelsDir/$name');
      try {
        if (await f.exists()) {
          bytes += await f.length();
          await f.delete();
        }
      } catch (e) {
        debugPrint('Abgelöste Modelldatei $name liess sich nicht entfernen: $e');
      }
    }
    return bytes;
  }
}

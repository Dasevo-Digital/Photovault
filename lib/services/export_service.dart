import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import '../db/database.dart';
import '../state/library_state.dart';
import 'export_naming.dart';
import 'native_image_converter.dart';
import 'storage_paths.dart';
import 'textstellen.dart';
import '../l10n/app_localizations.dart';
import 'xmp_regionen.dart';
import 'xmp_writer.dart';

/// Größe und Format, in denen exportiert wird.
///
/// [Exportgroesse.original] kopiert die Datei unverändert – der bisherige
/// und weiterhin voreingestellte Fall, und der einzige, der RAW, Videos und
/// alle übrigen Formate unangetastet lässt. Die übrigen Stufen rendern nach
/// JPEG mit begrenzter langer Kante, für Versand und Hochladen.
///
/// Bewusst eine feste, kurze Liste statt frei benannter Voreinstellungen:
/// Die drei Grössen decken die üblichen Fälle ab, und eine Verwaltung
/// eigener Voreinstellungen wäre ein eigenes Stück Oberfläche.
enum Exportgroesse {
  original(null),
  gross(4096),
  web(2048),
  email(1024);

  const Exportgroesse(this.maxKante);
  final int? maxKante;
}

/// Die Beschriftung einer Ausgabegrösse in der Oberflächensprache.
///
/// Wie beim Modellkatalog steht sie nicht im Enum selbst: Enum-Werte sind
/// `const`, ein übersetzter Text braucht den Kontext. Und zwei Fassungen
/// desselben Textes – eine hier, eine in den Sprachdateien – laufen
/// verlässlich auseinander.
String exportgroesseBezeichnung(AppTexte t, Exportgroesse g) => switch (g) {
      Exportgroesse.original => t.exportOriginal,
      Exportgroesse.gross => t.exportGross,
      Exportgroesse.web => t.exportWeb,
      Exportgroesse.email => t.exportEmail,
    };

/// Alles, was ein Export-Lauf über die Ausgabe wissen muss.
///
/// Steht zwischen den beiden Wegen, auf denen ein Export ausgelöst werden
/// kann: der schnellen Auswahl einer der vier festen [Exportgroesse]n und
/// einer gespeicherten Voreinstellung aus der Datenbank. Der Dienst kennt
/// nur noch dieses eine Gebilde – sonst müsste jede neue Einstellung an
/// zwei Stellen durchgereicht werden.
class Exportvorgabe {
  /// Nach JPEG rendern statt die Datei zu kopieren.
  ///
  /// Ohne das bleibt die Datei Bit für Bit, wie sie ist – der einzige Weg,
  /// der RAW, Videos und alles Übrige unangetastet lässt.
  final bool nachJpeg;

  /// Längere Bildkante in Pixeln, `null` = nicht begrenzen. Ohne
  /// [nachJpeg] ohne Bedeutung.
  final int? maxKante;

  final double qualitaet;

  /// Siehe `export_naming.dart`. Der Vorgabewert übernimmt den bisherigen
  /// Dateinamen unverändert.
  final String namensmuster;

  /// Die `.xmp`-Beistelldatei mitschreiben.
  final bool xmpDaneben;

  /// Entfernt eingebettete Metadaten durch Neurendern und unterdrückt die
  /// XMP-Beilage. [gesichterVerdecken] nutzt die lokal gespeicherten
  /// Gesichtsrechtecke; es findet kein Upload und keine neue Analyse statt.
  final bool metadatenEntfernen;
  final bool gesichterVerdecken;

  const Exportvorgabe({
    this.nachJpeg = false,
    this.maxKante,
    this.qualitaet = 0.9,
    this.namensmuster = '{name}',
    this.xmpDaneben = true,
    this.metadatenEntfernen = false,
    this.gesichterVerdecken = false,
  });

  /// Die Entsprechung einer der vier festen Grössen – damit der schnelle
  /// Weg und der Voreinstellungs-Weg denselben Code durchlaufen.
  factory Exportvorgabe.ausGroesse(Exportgroesse g) => Exportvorgabe(
        nachJpeg: g.maxKante != null,
        maxKante: g.maxKante,
      );

  factory Exportvorgabe.datenschutz() => const Exportvorgabe(
        nachJpeg: true,
        maxKante: 2048,
        qualitaet: 0.9,
        xmpDaneben: false,
        metadatenEntfernen: true,
        gesichterVerdecken: true,
      );

  factory Exportvorgabe.ausPreset(ExportPresetData p) => Exportvorgabe(
        nachJpeg: p.nachJpeg,
        maxKante: p.maxKante,
        qualitaet: p.qualitaet,
        namensmuster: p.namensmuster,
        xmpDaneben: p.xmpDaneben,
      );
}

/// Eine Aufnahme, deren Metadaten sich nicht entfernen lassen.
///
/// Der Datenschutzexport streift die Metadaten ab, indem er das Bild **neu
/// rendert**. Was sich nicht rendern lässt – jedes Video, und jedes Bild,
/// dessen Umwandlung scheitert –, kann diesen Weg nicht gehen.
///
/// Vorher wurde in diesem Fall die Originaldatei kopiert. Bei einer
/// Grössenvorgabe ist das freundlich: „nichts auslassen, nur weil eine
/// Vorgabe nicht anwendbar ist". Bei einer **Zusage** kehrt sich derselbe
/// Satz um – aus „nichts auslassen" wird „alles preisgeben, was wir nicht
/// verarbeiten können". Ein Video trägt Ort, Gerät und Zeit im Behälter;
/// der Export hiess „ohne EXIF, GPS oder XMP" und lieferte alles davon aus.
///
/// Deshalb: auslassen und benennen, statt durchreichen und schweigen.
class DatenschutzNichtMoeglich implements Exception {
  const DatenschutzNichtMoeglich(this.dateiname);

  /// Der Name, unter dem der Nutzer die Aufnahme wiedererkennt.
  final String dateiname;

  // Wie die uebrigen Ausnahmen im Haus: Klassenname und Felder, kein Satz.
  // Ein Satz waere hier doppelt falsch - er sieht fuer
  // `keine_festen_texte_test` wie Oberflaechentext aus, und angezeigt wird
  // ohnehin `datenschutzAusgelassen`, nicht diese Zeile.
  @override
  String toString() => 'DatenschutzNichtMoeglich($dateiname)';
}

/// Exportiert Original-Dateien aus der verwalteten Bibliothek zurück in
/// einen normalen Ordner – z.B. um ein Foto extern weiterzubearbeiten oder zu
/// teilen. Bewusst von [BackupService] getrennt: ein Backup sichert die
/// GESAMTE Bibliothek (inkl. Metadaten-Export, Delta-Abgleich), ein Export
/// legt gezielt einzelne Original-Dateien an einem frei gewählten Ort ab.
class ExportService {
  const ExportService(this._paths, {LibraryState? library})
      : _library = library;

  final StoragePaths _paths;
  final LibraryState? _library;

  /// Liefert die tatsächliche Quelldatei eines Assets – gesperrte
  /// (verschlüsselte) Assets werden dafür einmalig über
  /// [LibraryState.decryptForViewing] entschlüsselt (dafür muss [library]
  /// beim Erzeugen übergeben worden sein und der gesperrte Ordner für diese
  /// Sitzung bereits entsperrt sein). Gemeinsam genutzt von [exportAsset]
  /// (Kopie in einen Ordner) und dem nativen Teilen-Dialog in
  /// AssetViewerScreen (Kopie an eine andere App wie Mail/AirDrop).
  Future<File> resolveSourceFile(AssetData asset) async {
    return asset.isLocked && _library != null
        ? await _library.decryptForViewing(asset.relativePath)
        : _paths.absolute(asset.relativePath);
  }

  /// Exportiert die Originaldatei eines Assets in [destinationDir] und gibt
  /// den verwendeten Dateinamen zurück (bei einer Namenskollision am
  /// Zielort mit angehängter Nummerierung). Legt zusätzlich eine
  /// `.xmp`-Sidecar-Datei mit den Metadaten daneben (siehe xmp_writer.dart)
  /// – anders als beim Bulk-Export/Backup werden hier bewusst AUCH gesperrte
  /// Assets mit einbezogen: der Nutzer hat das Entschlüsseln/Exportieren an
  /// dieser Stelle bereits aktiv angestoßen (siehe [resolveSourceFile]).
  ///
  /// Mit [groesse] ungleich [Exportgroesse.original] wird das Foto nach JPEG
  /// gerendert. Videos und alles, was sich nicht konvertieren lässt, werden
  /// dabei unverändert kopiert statt übersprungen – ein Export soll nichts
  /// auslassen, nur weil eine Grössenvorgabe darauf nicht anwendbar ist.
  /// [nummer] ist die laufende Nummer innerhalb des Export-Laufs (ab 1) und
  /// wird nur gebraucht, wenn das Namensmuster `{nr}` enthält.
  Future<String> exportAsset(
    AssetData asset,
    String destinationDir, {
    Exportgroesse groesse = Exportgroesse.original,
    Exportvorgabe? vorgabe,
    int nummer = 1,
  }) async {
    final v = vorgabe ?? Exportvorgabe.ausGroesse(groesse);
    final sourceFile = await resolveSourceFile(asset);

    // `maxDimension: null` heisst für den nativen Wandler „nicht
    // begrenzen" – so lässt sich auch in voller Auflösung nach JPEG
    // rendern, was mit der alten Aufzählung nicht ging.
    Uint8List? gerendert;
    if ((v.nachJpeg || v.metadatenEntfernen) && asset.type == 'IMAGE') {
      gerendert = await NativeImageConverter.convertToJpegBytes(
        sourceFile,
        maxDimension: v.maxKante,
        quality: v.qualitaet,
      );
      if (gerendert != null && v.gesichterVerdecken && _library != null) {
        final faces = await _library.db.facesForAsset(asset.id);
        final plateBoxes = kennzeichenBoxen(asset.ocrBoxen);
        final boxes = <(double, double, double, double)>[
          for (final face in faces)
            (face.boxX, face.boxY, face.boxW, face.boxH),
          ...plateBoxes,
        ];
        if (boxes.isNotEmpty) {
          gerendert = await compute(
            verdeckeGesichter,
            (bytes: gerendert, boxen: boxes),
          );
        }
      }
    }

    // **Der Riegel vor dem Kopieren.** Ab hier gilt: Wurde nichts
    // gerendert, wird die Originaldatei kopiert. Genau das darf der
    // Datenschutzexport nicht – siehe [DatenschutzNichtMoeglich]. Der
    // Abbruch steht VOR dem Anlegen der Zieldatei, damit am Zielort keine
    // halbe Kopie zurückbleibt, die aussieht wie ein Ergebnis.
    if (v.metadatenEntfernen && gerendert == null) {
      throw DatenschutzNichtMoeglich(asset.originalFileName);
    }

    // Die Endung richtet sich danach, was WIRKLICH geschrieben wird: Ist
    // das Rendern fehlgeschlagen (oder war es ein Video), wird kopiert –
    // dann darf dort auch kein `.jpg` stehen.
    final endung =
        gerendert != null ? '.jpg' : p.extension(asset.originalFileName);
    final zielName = dateiname(
      v.namensmuster,
      asset,
      nummer: nummer,
      endung: endung,
    );
    final targetPath = _uniqueDestinationPath(destinationDir, zielName);
    if (gerendert != null) {
      await File(targetPath).writeAsBytes(gerendert);
    } else {
      await sourceFile.copy(targetPath);
    }

    if (v.xmpDaneben && !v.metadatenEntfernen) {
      final tagNames = _library != null
          ? (await _library.db.tagsForAsset(asset.id))
              .map((t) => t.name)
              .toList()
          : const <String>[];
      // Die benannten Gesichter gehen mit: Genau dafür exportiert man mit
      // Beipackzettel – damit das Zielprogramm die Namen übernimmt, statt
      // sie ein zweites Mal von Hand zu vergeben.
      final gesichter = _library != null
          ? await _library.db.gesichtsregionenVon(asset.id)
          : const <Gesichtsregion>[];
      final xmp = buildXmpPacket(asset, tagNames, gesichter: gesichter);
      await File(_paths.xmpSidecarPath(targetPath)).writeAsString(xmp);
    }

    return p.basename(targetPath);
  }

  /// Hängt bei einer bereits vorhandenen Datei gleichen Namens am Zielort
  /// "(1)", "(2)", … an den Dateinamen an, statt die vorhandene Datei
  /// stillschweigend zu überschreiben.
  ///
  /// [fileName] wird zusätzlich über `p.basename()` geführt – reine
  /// Verteidigung in der Tiefe: der Name stammt aus [AssetData.originalFileName],
  /// das schon beim Import bzw. beim Backup-Restore auf den Basisnamen
  /// reduziert wird, aber ein Export-Ziel sollte auch bei einer künftigen
  /// Änderung dieser Invariante nie außerhalb von [dir] landen können.
  String _uniqueDestinationPath(String dir, String fileName) {
    final safeName = p.basename(fileName);
    var candidate = p.join(dir, safeName);
    if (!File(candidate).existsSync()) return candidate;
    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    var i = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$stem ($i)$ext');
      i++;
    }
    return candidate;
  }
}

/// Rechtecke von Textzeilen, die Form und Inhalt eines europäischen
/// Kennzeichens haben. Das ist bewusst konservativ: mindestens ein Buchstabe
/// und eine Ziffer, höchstens zwölf sichtbare Zeichen und ein deutlich
/// breiteres als hohes Rechteck. Die Erkennung bleibt vollständig lokal und
/// nutzt die bereits gespeicherten OCR-Stellen.
List<(double, double, double, double)> kennzeichenBoxen(String? ocrBoxen) {
  const plateUmlauts = '\u00c4\u00d6\u00dc';
  final ergebnis = <(double, double, double, double)>[];
  for (final stelle in textstellenAusJson(ocrBoxen)) {
    final kompakt = stelle.text
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9$plateUmlauts]'), '');
    final hatBuchstabe = RegExp('[A-Z$plateUmlauts]').hasMatch(kompakt);
    final hatZahl = RegExp(r'[0-9]').hasMatch(kompakt);
    final breitGenug = stelle.hoehe > 0 && stelle.breite / stelle.hoehe >= 2;
    if (kompakt.length >= 4 &&
        kompakt.length <= 12 &&
        hatBuchstabe &&
        hatZahl &&
        breitGenug) {
      ergebnis.add((stelle.links, stelle.oben, stelle.breite, stelle.hoehe));
    }
  }
  return ergebnis;
}

/// Verwischt bekannte Gesichtsbereiche in einem bereits nach JPEG
/// gerenderten Export. Die Rechtecke sind normiert und bleiben daher auch
/// nach einer Größenänderung gültig.
Uint8List verdeckeGesichter(
    ({Uint8List bytes, List<(double, double, double, double)> boxen}) args) {
  final image = img.decodeImage(args.bytes);
  if (image == null) return args.bytes;
  for (final (bx, by, bw, bh) in args.boxen) {
    final marginX = bw * .12;
    final marginY = bh * .12;
    final x = ((bx - marginX) * image.width).floor().clamp(0, image.width - 1);
    final y =
        ((by - marginY) * image.height).floor().clamp(0, image.height - 1);
    final right =
        ((bx + bw + marginX) * image.width).ceil().clamp(x + 1, image.width);
    final bottom =
        ((by + bh + marginY) * image.height).ceil().clamp(y + 1, image.height);
    final crop =
        img.copyCrop(image, x: x, y: y, width: right - x, height: bottom - y);
    img.gaussianBlur(crop, radius: (crop.width ~/ 10).clamp(8, 40));
    img.compositeImage(image, crop, dstX: x, dstY: y);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

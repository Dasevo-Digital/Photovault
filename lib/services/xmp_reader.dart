import 'dart:io';

import 'dart:convert';
import 'dart:typed_data';

import 'package:kern/services/beilagenangaben.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:kern/services/xmp_regionen.dart';

/// Aus einem XMP-Paket ausgelesene Felder – Gegenstück zu
/// [buildXmpPacket] in xmp_writer.dart. Alle Felder optional, da ein
/// Paket (insbesondere eines, das nicht von dieser App selbst stammt,
/// z.B. aus Lightroom) nicht jedes Feld enthalten muss.
///
/// Gesichts-Regionen sind seit dem Schreiben von MWG-RS dabei. Vorher stand
/// hier, es gebe „nichts Verlässliches zum Zurücklesen" – was stimmte,
/// solange die Gegenseite nichts schrieb, und genau deshalb nie von selbst
/// aufhörte zu stimmen.
class XmpFields {
  /// 0 bis 5. Andere Werte werden nicht übernommen.
  final int? rating;

  /// In darktable oder Lightroom abgelehnt (`xmp:Rating` = -1).
  final bool abgelehnt;
  final String? colorLabel;
  final String? description;
  final List<String>? tags;
  final double? latitude;
  final double? longitude;

  /// Benannte Gesichter aus dem `mwg-rs:Regions`-Block. Leer, wenn das Paket
  /// keine enthält.
  final List<Gesichtsregion> gesichter;

  const XmpFields({
    this.rating,
    this.abgelehnt = false,
    this.colorLabel,
    this.description,
    this.tags,
    this.latitude,
    this.longitude,
    this.gesichter = const [],
  });

  bool get isEmpty =>
      rating == null &&
      !abgelehnt &&
      colorLabel == null &&
      description == null &&
      tags == null &&
      latitude == null &&
      longitude == null &&
      gesichter.isEmpty;

  /// Was davon beim Import mitkommt. 0 Sterne heisst „nicht bewertet“.
  Beilagenangaben get alsBeilage => Beilagenangaben(
    sterne: rating != null && rating! > 0 ? rating : null,
    abgelehnt: abgelehnt,
    farbe: colorLabel,
    beschreibung: description,
    schlagwoerter: tags ?? const [],
    breite: latitude,
    laenge: longitude,
  );
}

/// Die Beilage neben der Datei [pfad], unter dem Namen von Photo Vault und
/// Lightroom oder dem von darktable; `null`, wenn keine lesbare da ist.
Beilagenangaben? beilageNeben(String pfad) {
  try {
    final datei = neuesteXmpBeilage([
      File(p.setExtension(pfad, '.xmp')),
      File('$pfad.xmp'),
    ]);
    final angaben = datei == null ? null : parseXmpFile(datei)?.alsBeilage;
    return angaben == null || angaben.alsMap().isEmpty ? null : angaben;
  } on FileSystemException {
    return null;
  }
}

/// Ordnet [beilagen] aus einem frei gewählten Ordner den [fotos] nach Namen
/// zu (Kennung → Datei), ohne Rücksicht auf Gross- und Kleinschreibung.
///
/// Für verbundene Bibliotheken: Die Originale liegen dort am Server, neben
/// ihnen lässt sich also nichts finden (#346). Tragen zwei Fotos denselben
/// Namen (Kameras zählen nach 9999 von vorn), bleibt ihre Beilage unbenutzt:
/// Lieber nichts übernehmen als die Sterne des falschen Fotos. Aus demselben
/// Grund bleibt ein Foto ohne Beilage, wenn zwei Unterordner je eine für
/// seinen Namen haben. Im selben Ordner gilt wie sonst die neueste.
Map<String, File> ordneBeilagenZu(
  Iterable<File> beilagen,
  Iterable<({String id, String name})> fotos,
) {
  final jeName = <String, List<String>>{};
  for (final f in fotos) {
    final name = f.name.toLowerCase();
    jeName.putIfAbsent(name, () => []).add(f.id);
    final ohne = p.withoutExtension(name);
    if (ohne != name) jeName.putIfAbsent(ohne, () => []).add(f.id);
  }
  final kandidaten = <String, List<File>>{};
  for (final b in beilagen) {
    final name = p.withoutExtension(p.basename(b.path)).toLowerCase();
    final treffer = jeName[name];
    if (treffer != null && treffer.length == 1) {
      kandidaten.putIfAbsent(treffer.single, () => []).add(b);
    }
  }
  return {
    for (final e in kandidaten.entries)
      if (e.value.map((f) => f.parent.path).toSet().length == 1)
        e.key: e.value.length == 1
            ? e.value.single
            : neuesteXmpBeilage(e.value) ?? e.value.first,
  };
}

/// Liest [file] als XMP-Sidecar ein. Gibt `null` zurück, wenn die Datei
/// fehlt oder kein gültiges XML/keine `rdf:Description` enthält.
XmpFields? parseXmpFile(File file) {
  if (!file.existsSync()) return null;
  return parseXmpContent(file.readAsStringSync());
}

/// Von [kandidaten] die vorhandene Datei, bei mehreren die zuletzt
/// geänderte: Beide Beilagen können liegen, wenn darktable neben einer von
/// hier geschriebenen eine eigene anlegt (#343).
File? neuesteXmpBeilage(Iterable<File> kandidaten) {
  File? beste;
  DateTime? zeit;
  for (final f in kandidaten) {
    if (!f.existsSync()) continue;
    final t = f.lastModifiedSync();
    if (zeit == null || t.isAfter(zeit)) {
      beste = f;
      zeit = t;
    }
  }
  return beste;
}

/// Reine Parsing-Funktion ohne Dateizugriff (Muster: [buildXmpPacket]) –
/// gut isoliert testbar. Sammelt Attribute/Elemente über ALLE
/// `rdf:Description`-Blöcke hinweg (nicht nur den ersten): reale, z.B. aus
/// Lightroom stammende XMP-Dateien verteilen Namensräume häufig auf
/// mehrere Description-Blöcke statt (wie xmp_writer.dart) alles in einen
/// einzigen zu schreiben.
XmpFields? parseXmpContent(String xmlContent) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlContent);
  } catch (_) {
    return null;
  }

  final descriptions = doc.findAllElements('rdf:Description').toList();
  if (descriptions.isEmpty) return null;

  String? findAttribute(String name) {
    for (final d in descriptions) {
      final value = d.getAttribute(name);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  XmlElement? findChild(String name) {
    for (final d in descriptions) {
      final match = d.findElements(name).firstOrNull;
      if (match != null) return match;
    }
    return null;
  }

  final ratingRaw = findAttribute('xmp:Rating');
  final bewertung = ratingRaw != null ? int.tryParse(ratingRaw) : null;
  // -1 heisst „abgelehnt“ und ist keine Bewertung (#344).
  final rating = bewertung != null && bewertung >= 0 && bewertung <= 5
      ? bewertung
      : null;

  final labelRaw = findAttribute('xmp:Label');
  final colorLabel = labelRaw != null ? _internalColorLabel(labelRaw) : null;

  final latRaw = findAttribute('exif:GPSLatitude');
  final lngRaw = findAttribute('exif:GPSLongitude');
  final latitude = latRaw != null
      ? _parseXmpGps(latRaw, isLatitude: true)
      : null;
  final longitude = lngRaw != null
      ? _parseXmpGps(lngRaw, isLatitude: false)
      : null;

  String? description;
  final descriptionElement = findChild('dc:description');
  if (descriptionElement != null) {
    final li = descriptionElement.findAllElements('rdf:li').firstOrNull;
    final text = li?.innerText.trim();
    if (text != null && text.isNotEmpty) description = text;
  }

  List<String>? tags;
  final subjectElement = findChild('dc:subject');
  if (subjectElement != null) {
    final items = subjectElement
        .findAllElements('rdf:li')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty && !_darktableEigene(doc).contains(t))
        .toList();
    if (items.isNotEmpty) tags = items;
  }

  final fields = XmpFields(
    rating: rating,
    abgelehnt: bewertung == -1,
    colorLabel: colorLabel,
    description: description,
    tags: tags,
    latitude: latitude,
    longitude: longitude,
    gesichter: _regionen(doc),
  );
  return fields.isEmpty ? null : fields;
}

/// Was darktable sich selbst anheftet (`darktable|format|cr3`,
/// `darktable|exported`) und flach auch in `dc:subject` wiederholt. Das sind
/// keine Schlagwörter des Menschen, der sortiert hat (#346).
Set<String> _darktableEigene(XmlDocument doc) {
  final eigene = <String>{};
  for (final e in doc.findAllElements('lr:hierarchicalSubject')) {
    for (final li in e.findAllElements('rdf:li')) {
      final teile = li.innerText.trim().split('|');
      if (teile.first == 'darktable') eigene.addAll(teile);
    }
  }
  return eigene;
}

/// Die benannten Gesichter aus dem `mwg-rs:Regions`-Block.
///
/// Gesucht wird über den ganzen Baum und nicht unterhalb eines bestimmten
/// `rdf:Description`: Wo der Block hängt, unterscheidet sich je nach
/// schreibendem Programm, und `rdf:parseType="Resource"` erlaubt beide
/// Schreibweisen.
///
/// Übersprungen wird jede Region ohne Namen (die sagt nichts, was die eigene
/// Erkennung nicht selbst fände) und jede, die nicht `Face` ist – MWG kennt
/// im selben Block auch Haustiere und Sachbezeichnungen.
List<Gesichtsregion> _regionen(XmlDocument doc) {
  final gefunden = <Gesichtsregion>[];
  for (final li in doc.findAllElements('rdf:li')) {
    final flaeche = li.findElements('mwg-rs:Area').firstOrNull;
    if (flaeche == null) continue;

    final art = li.findElements('mwg-rs:Type').firstOrNull?.innerText.trim();
    if (art != null && art.isNotEmpty && art.toLowerCase() != 'face') continue;

    final name = li.findElements('mwg-rs:Name').firstOrNull?.innerText.trim();
    if (name == null || name.isEmpty) continue;

    final x = double.tryParse(flaeche.getAttribute('stArea:x') ?? '');
    final y = double.tryParse(flaeche.getAttribute('stArea:y') ?? '');
    final w = double.tryParse(flaeche.getAttribute('stArea:w') ?? '');
    final h = double.tryParse(flaeche.getAttribute('stArea:h') ?? '');
    if (x == null || y == null || w == null || h == null) continue;
    if (w <= 0 || h <= 0) continue;

    gefunden.add(
      Gesichtsregion.ausMitte(
        name: name,
        mitteX: x,
        mitteY: y,
        breite: w,
        hoehe: h,
      ),
    );
  }
  return gefunden;
}

/// Wie viele Bytes vom Dateianfang nach einem eingebetteten XMP-Paket
/// durchsucht werden.
///
/// Ein Megabyte. Bei JPEG steht das APP1-Segment mit dem Paket unmittelbar
/// hinter dem Dateikopf, bei TIFF-Ableitungen (DNG, CR3) zeigt die IFD0 zu
/// Beginn darauf, und HEIC legt seine Metadaten ebenfalls nach vorn. Eine
/// 40-MB-RAW-Datei ganz einzulesen, nur um die ersten Kilobyte zu
/// durchsuchen, wäre bei 8000 Aufnahmen der teuerste Teil des ganzen Laufs.
///
/// Der Preis steht hier, damit er nicht verschwiegen wird: Ein Paket, das
/// weiter hinten steht, wird nicht gefunden. Für diesen Fall gibt es
/// weiterhin den Beipackzettel daneben.
const int xmpSuchtiefe = 1024 * 1024;

/// Liest das in [file] eingebettete XMP-Paket, falls eines vorhanden ist.
///
/// **Warum überhaupt.** Der Leser kannte bis hierher nur Beipackzettel.
/// Alles, was mit eingebettetem XMP und ohne `.xmp` daneben aus Lightroom,
/// digiKam oder einer Kamera kommt, kam damit ohne Schlagwörter, ohne
/// Bewertung und ohne Gesichtsnamen an – und man sah es der Datei nicht an.
///
/// Gesucht wird nach der Zeichenkette `<x:xmpmeta` bis `</x:xmpmeta>`. Das
/// ist bewusst kein Formatparser: Ein solcher müsste JPEG, HEIF, TIFF, CR3
/// und PNG einzeln beherrschen, und das XMP-Paket ist in allen dieser
/// Formate genau diese Zeichenfolge im Klartext. Der Zusatz „Extended XMP"
/// (Adobe verteilt sehr grosse Pakete über mehrere Segmente) bleibt
/// unberücksichtigt – dort steht typischerweise ein Vorschaubild, keine
/// Bewertung.
XmpFields? parseEingebettetesXmp(File file) {
  final roh = eingebettetesXmpPaket(file);
  return roh == null ? null : parseXmpContent(roh);
}

/// Das rohe Paket aus [file], oder `null`. Getrennt von
/// [parseEingebettetesXmp], damit sich das Suchen ohne Parsen prüfen lässt.
String? eingebettetesXmpPaket(File file) {
  if (!file.existsSync()) return null;
  final RandomAccessFile griff;
  try {
    griff = file.openSync();
  } on FileSystemException {
    return null;
  }
  try {
    final laenge = griff.lengthSync();
    final zuLesen = laenge < xmpSuchtiefe ? laenge : xmpSuchtiefe;
    if (zuLesen <= 0) return null;
    final bytes = griff.readSync(zuLesen);
    return xmpAusBytes(bytes);
  } on FileSystemException {
    return null;
  } finally {
    griff.closeSync();
  }
}

/// Sucht das Paket in bereits gelesenen Bytes. Reine Funktion.
///
/// Latin-1 und nicht UTF-8 zum Suchen: Ringsum stehen beliebige Bildbytes,
/// die als UTF-8 ungültig sind und das Dekodieren zum Werfen brächten. Für
/// die reine Suche nach ASCII-Marken genügt eine Zuordnung Byte für Byte;
/// der gefundene Ausschnitt wird danach als UTF-8 gelesen, denn XMP ist
/// laut Norm UTF-8.
String? xmpAusBytes(Uint8List bytes) {
  const anfangsmarken = ['<x:xmpmeta', '<?xpacket begin'];
  final text = latin1.decode(bytes, allowInvalid: true);
  for (final marke in anfangsmarken) {
    final start = text.indexOf(marke);
    if (start < 0) continue;
    final ende = text.indexOf('</x:xmpmeta>', start);
    if (ende < 0) continue;
    final schnitt = bytes.sublist(start, ende + '</x:xmpmeta>'.length);
    try {
      return utf8.decode(schnitt);
    } on FormatException {
      return latin1.decode(schnitt);
    }
  }
  return null;
}

/// Umkehrung von `_xmpLabelName` in xmp_writer.dart. `null` bei einem
/// unbekannten Label-Namen (z.B. eine in Lightroom frei vergebene
/// zusätzliche Farbe, die photo_vaults feste 5er-Palette nicht kennt) statt
/// eines rätselhaften internen Werts.
String? _internalColorLabel(String xmpLabel) => switch (xmpLabel) {
  'Red' => 'red',
  'Yellow' => 'yellow',
  'Green' => 'green',
  'Blue' => 'blue',
  'Purple' => 'purple',
  _ => null,
};

/// Umkehrung von `_toXmpGps` in xmp_writer.dart (Format
/// `"Grad,Minuten.mmmmmmR"`, R = Himmelsrichtung N/S/E/W). Gibt `null` bei
/// nicht parsbaren Werten zurück, statt zu werfen – ein einzelnes
/// kaputtes GPS-Feld soll nicht den ganzen Sidecar unbrauchbar machen.
double? _parseXmpGps(String value, {required bool isLatitude}) {
  final match = RegExp(
    r'^(\d+),(\d+(?:\.\d+)?)([NSEW])$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final degrees = double.tryParse(match.group(1)!);
  final minutes = double.tryParse(match.group(2)!);
  final ref = match.group(3)!;
  if (degrees == null || minutes == null) return null;
  final expectedRefs = isLatitude ? const {'N', 'S'} : const {'E', 'W'};
  if (!expectedRefs.contains(ref)) return null;
  final decimal = degrees + minutes / 60;
  return (ref == 'S' || ref == 'W') ? -decimal : decimal;
}

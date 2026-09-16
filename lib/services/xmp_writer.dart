import 'package:xml/xml.dart';

import '../db/database.dart';
import 'xmp_regionen.dart';

/// Baut ein minimales, valides XMP-Sidecar-Paket für ein Asset – Struktur/
/// Namensräume wie sie Lightroom/darktable/digiKam erzeugen und lesen
/// (einfache Werte als Attribute auf `rdf:Description`, `dc:description`
/// als Sprachalternative, `dc:subject` als Tag-Liste). Reine Funktion ohne
/// Dateizugriff – der Aufrufer schreibt die zurückgegebene Zeichenkette
/// selbst weg (siehe LibraryState.writeXmpSidecars, ExportService,
/// BackupService). Nutzt bewusst nur literale, bereits qualifizierte
/// Element-/Attributnamen (`'rdf:RDF'`, `'xmlns:rdf'`) statt
/// [XmlBuilder]s Präfix-Auflösung – XMP-Struktur ist fest vorgegeben, eine
/// eigene Namensraum-Verwaltung wäre hier nur unnötige Komplexität.
/// [gesichter] sind die benannten Gesichter dieses Fotos. Sie werden als
/// MWG-RS-Regionen geschrieben – das Format, in dem Lightroom, digiKam und
/// PhotoPrism Namen zu Bildstellen austauschen. Ohne sie blieb die
/// aufwendigste Handarbeit der Bibliothek in ihr gefangen.
///
/// Unbenannte Gesichter gehören NICHT hinein: Eine Region ohne Namen sagt
/// dem Zielprogramm nur „hier ist irgendein Kopf", und das findet dessen
/// eigene Erkennung selbst.
String buildXmpPacket(
  AssetData asset,
  List<String> tagNames, {
  List<Gesichtsregion> gesichter = const [],
}) {
  final builder = XmlBuilder();
  builder.processing('xpacket', 'begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"');
  builder.element(
    'x:xmpmeta',
    attributes: {'xmlns:x': 'adobe:ns:meta/'},
    nest: () {
      builder.element(
        'rdf:RDF',
        attributes: {'xmlns:rdf': 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'},
        nest: () {
          builder.element(
            'rdf:Description',
            attributes: {
              'rdf:about': '',
              'xmlns:dc': 'http://purl.org/dc/elements/1.1/',
              'xmlns:xmp': 'http://ns.adobe.com/xap/1.0/',
              'xmlns:exif': 'http://ns.adobe.com/exif/1.0/',
              'xmlns:tiff': 'http://ns.adobe.com/tiff/1.0/',
              'xmlns:aux': 'http://ns.adobe.com/exif/1.0/aux/',
              if (gesichter.isNotEmpty) ...{
                'xmlns:mwg-rs': 'http://www.metadataworkinggroup.com/schemas/regions/',
                'xmlns:stArea': 'http://ns.adobe.com/xmp/sType/Area#',
                'xmlns:stDim': 'http://ns.adobe.com/xap/1.0/sType/Dimensions#',
              },
              if (asset.rating > 0) 'xmp:Rating': '${asset.rating}',
              if (asset.colorLabel != null) 'xmp:Label': _xmpLabelName(asset.colorLabel!),
              if (asset.cameraMake != null) 'tiff:Make': asset.cameraMake!,
              if (asset.cameraModel != null) 'tiff:Model': asset.cameraModel!,
              if (asset.lensModel != null) 'aux:Lens': asset.lensModel!,
              if (asset.focalLengthMm != null) 'exif:FocalLength': _toRational(asset.focalLengthMm!),
              if (asset.fNumber != null) 'exif:FNumber': _toRational(asset.fNumber!),
              if (asset.iso != null) 'exif:ISOSpeedRatings': '${asset.iso}',
              if (asset.exposureTimeSeconds != null)
                'exif:ExposureTime': _toRational(asset.exposureTimeSeconds!),
              if (asset.latitude != null) 'exif:GPSLatitude': _toXmpGps(asset.latitude!, isLatitude: true),
              if (asset.longitude != null) 'exif:GPSLongitude': _toXmpGps(asset.longitude!, isLatitude: false),
            },
            nest: () {
              final description = asset.description;
              if (description != null && description.isNotEmpty) {
                builder.element(
                  'dc:description',
                  nest: () => builder.element(
                    'rdf:Alt',
                    nest: () => builder.element(
                      'rdf:li',
                      attributes: {'xml:lang': 'x-default'},
                      nest: description,
                    ),
                  ),
                );
              }
              if (tagNames.isNotEmpty) {
                builder.element(
                  'dc:subject',
                  nest: () => builder.element(
                    'rdf:Bag',
                    nest: () {
                      for (final tag in tagNames) {
                        builder.element('rdf:li', nest: tag);
                      }
                    },
                  ),
                );
              }
              if (gesichter.isNotEmpty) _regionen(builder, asset, gesichter);
            },
          );
        },
      );
    },
  );
  builder.processing('xpacket', 'end="w"');
  return builder.buildDocument().toXmlString(pretty: true);
}

/// Der `mwg-rs:Regions`-Block mit einer Region je benanntem Gesicht.
///
/// `AppliedToDimensions` nennt die Bildmasse, auf die sich die Anteile
/// beziehen. Bei `unit="normalized"` ändert das rechnerisch nichts, aber
/// mehrere Leser (darunter digiKam) überspringen einen Regions-Block ohne
/// diese Angabe – deshalb steht sie da, sobald die Masse bekannt sind.
///
/// `stArea:x`/`stArea:y` sind die **Mitte** der Region, nicht ihre linke
/// obere Ecke. Siehe [Gesichtsregion].
void _regionen(XmlBuilder builder, AssetData asset, List<Gesichtsregion> gesichter) {
  builder.element(
    'mwg-rs:Regions',
    attributes: {'rdf:parseType': 'Resource'},
    nest: () {
      final w = asset.widthPx, h = asset.heightPx;
      if (w != null && h != null && w > 0 && h > 0) {
        builder.element('mwg-rs:AppliedToDimensions', attributes: {
          'rdf:parseType': 'Resource',
          'stDim:w': '$w',
          'stDim:h': '$h',
          'stDim:unit': 'pixel',
        });
      }
      builder.element(
        'mwg-rs:RegionList',
        nest: () => builder.element(
          'rdf:Bag',
          nest: () {
            for (final g in gesichter) {
              builder.element(
                'rdf:li',
                attributes: {'rdf:parseType': 'Resource'},
                nest: () {
                  builder.element('mwg-rs:Name', nest: g.name);
                  builder.element('mwg-rs:Type', nest: 'Face');
                  builder.element('mwg-rs:Area', attributes: {
                    'rdf:parseType': 'Resource',
                    'stArea:x': _anteil(g.mitteX),
                    'stArea:y': _anteil(g.mitteY),
                    'stArea:w': _anteil(g.breite),
                    'stArea:h': _anteil(g.hoehe),
                    'stArea:unit': 'normalized',
                  });
                },
              );
            }
          },
        ),
      );
    },
  );
}

/// Sechs Nachkommastellen – mehr, als jede Gesichtserkennung hergibt, und
/// wenig genug, dass die Datei lesbar bleibt.
String _anteil(double wert) => wert.clamp(0.0, 1.0).toStringAsFixed(6);

/// Lightroom-Konvention: englischer, großgeschriebener Name statt des
/// intern verwendeten Schlüssels (siehe `colorLabelSwatches` in
/// color_label_picker.dart).
String _xmpLabelName(String colorLabel) => switch (colorLabel) {
      'red' => 'Red',
      'yellow' => 'Yellow',
      'green' => 'Green',
      'blue' => 'Blue',
      'purple' => 'Purple',
      _ => colorLabel,
    };

/// XMPs EXIF-Schema erwartet rationale Zahlen als `"Zähler/Nenner"`-Strings
/// (z.B. `"50/1"`, `"18/10"`), keine Dezimalzahlen – [precision] bestimmt
/// den Nenner vor dem Kürzen (1000 reicht für alle hier vorkommenden Werte
/// mit ausreichender Genauigkeit, ohne krumme große Zahlen zu erzeugen).
String _toRational(double value, {int precision = 1000}) {
  final numerator = (value * precision).round();
  final divisor = _gcd(numerator.abs(), precision);
  if (divisor == 0) return '0/1';
  return '${numerator ~/ divisor}/${precision ~/ divisor}';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// XMPs EXIF-Schema erwartet GPS-Koordinaten im `"Grad,Minuten.mmmmmmR"`-
/// Format (R = Himmelsrichtung N/S/E/W), nicht als einfache Dezimalgrad –
/// dasselbe Format, das z.B. Lightroom-erzeugte XMPs verwenden.
String _toXmpGps(double value, {required bool isLatitude}) {
  final ref = isLatitude ? (value >= 0 ? 'N' : 'S') : (value >= 0 ? 'E' : 'W');
  final absValue = value.abs();
  final degrees = absValue.floor();
  final minutes = (absValue - degrees) * 60;
  return '$degrees,${minutes.toStringAsFixed(6)}$ref';
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/exif_camera.dart';
import 'package:photo_vault/services/xmp_writer.dart';
import 'package:xml/xml.dart';

/// Prüft [buildXmpPacket]: valides XML, korrektes Feld-Mapping (siehe
/// Doc-Kommentar in xmp_writer.dart), und dass Sonderzeichen in Freitext
/// (Beschreibung, Tags) korrekt escaped statt das XML zu brechen.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<AssetData> insertAsset(String id) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/2026/08/$id.jpg',
          checksum: 'checksum_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 8, 12),
          importedAt: DateTime(2026, 8, 12),
        ));
    return (await db.assetById(id))!;
  }

  test('erzeugt valides, parsbares XML', () async {
    final asset = await insertAsset('a');
    final xmp = buildXmpPacket(asset, const []);

    expect(() => XmlDocument.parse(xmp), returnsNormally);
  });

  test('mappt Bewertung, Farbmarkierung, Beschreibung und Tags korrekt', () async {
    final asset0 = await insertAsset('a');
    await db.setRating(asset0.id, 4);
    await db.setColorLabel(asset0.id, 'red');
    await db.setDescription(asset0.id, 'Sonnenuntergang am Strand');
    final asset = (await db.assetById(asset0.id))!;

    final xmp = buildXmpPacket(asset, const ['Urlaub', 'Strand']);
    final doc = XmlDocument.parse(xmp);
    final description = doc.findAllElements('rdf:Description').single;

    expect(description.getAttribute('xmp:Rating'), '4');
    expect(description.getAttribute('xmp:Label'), 'Red');

    final descText = doc.findAllElements('rdf:li').first.innerText;
    expect(descText, 'Sonnenuntergang am Strand');

    final tags = doc
        .findAllElements('dc:subject')
        .single
        .findAllElements('rdf:li')
        .map((e) => e.innerText)
        .toList();
    expect(tags, ['Urlaub', 'Strand']);
  });

  test('lässt Bewertung/Farbmarkierung/Beschreibung/Tags weg, wenn nicht gesetzt', () async {
    final asset = await insertAsset('a');

    final xmp = buildXmpPacket(asset, const []);
    final doc = XmlDocument.parse(xmp);
    final description = doc.findAllElements('rdf:Description').single;

    expect(description.getAttribute('xmp:Rating'), isNull);
    expect(description.getAttribute('xmp:Label'), isNull);
    expect(doc.findAllElements('dc:description'), isEmpty);
    expect(doc.findAllElements('dc:subject'), isEmpty);
  });

  test('mappt Kamera-/Aufnahme-Metadaten als rationale Zahlen', () async {
    final asset0 = await insertAsset('a');
    await db.setCameraMetadata(
      asset0.id,
      const CameraInfo(
        make: 'Canon',
        model: 'EOS R10',
        lensModel: 'RF 50mm f/1.8 STM',
        focalLengthMm: 50,
        fNumber: 1.8,
        iso: 200,
        exposureTimeSeconds: 0.5,
      ),
    );
    final asset = (await db.assetById(asset0.id))!;

    final xmp = buildXmpPacket(asset, const []);
    final doc = XmlDocument.parse(xmp);
    final description = doc.findAllElements('rdf:Description').single;

    expect(description.getAttribute('tiff:Make'), 'Canon');
    expect(description.getAttribute('tiff:Model'), 'EOS R10');
    expect(description.getAttribute('aux:Lens'), 'RF 50mm f/1.8 STM');
    expect(description.getAttribute('exif:FocalLength'), '50/1');
    expect(description.getAttribute('exif:FNumber'), '9/5');
    expect(description.getAttribute('exif:ISOSpeedRatings'), '200');
    expect(description.getAttribute('exif:ExposureTime'), '1/2');
  });

  test('mappt GPS-Koordinaten im Grad-Minuten-Format mit Himmelsrichtung', () async {
    final asset0 = await insertAsset('a');
    await db.setLocation(asset0.id, 48.85, 2.35); // Paris, Nordhalbkugel/Ost
    final asset = (await db.assetById(asset0.id))!;

    final xmp = buildXmpPacket(asset, const []);
    final doc = XmlDocument.parse(xmp);
    final description = doc.findAllElements('rdf:Description').single;

    expect(description.getAttribute('exif:GPSLatitude'), endsWith('N'));
    expect(description.getAttribute('exif:GPSLongitude'), endsWith('E'));
  });

  test('escaped Sonderzeichen in Beschreibung/Tags statt das XML zu brechen', () async {
    final asset0 = await insertAsset('a');
    await db.setDescription(asset0.id, 'Katze & Hund <süß>');
    final asset = (await db.assetById(asset0.id))!;

    final xmp = buildXmpPacket(asset, const ['Tag & <Test>']);

    expect(() => XmlDocument.parse(xmp), returnsNormally);
    final doc = XmlDocument.parse(xmp);
    expect(doc.findAllElements('rdf:li').first.innerText, 'Katze & Hund <süß>');
  });
}

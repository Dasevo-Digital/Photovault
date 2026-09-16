import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/xmp_reader.dart';
import 'package:photo_vault/services/xmp_writer.dart';

AssetData _buildAsset({
  int rating = 0,
  String? colorLabel,
  String? description,
  double? latitude,
  double? longitude,
}) {
  return AssetData(
    id: 'a1',
    originalFileName: 'IMG_0001.jpg',
    relativePath: 'originals/2025/03/a1.jpg',
    checksum: 'chk1',
    type: 'IMAGE',
    fileCreatedAt: DateTime(2025, 3, 12),
    importedAt: DateTime(2025, 3, 12),
    isFavorite: false,
    isTrashed: false,
    isLocked: false,
    faceScanExcluded: false,
    gpsGeprueft: false,
    datumGeschaetzt: false,
    datumGeprueft: false,
    ortGeerbt: false,
    videobilderGeprueft: false,
    fileSizeBytes: 100,
    backedUp: false,
    autoBackedUp: false,
    facesScanned: false,
    rating: rating,
    colorLabel: colorLabel,
    description: description,
    latitude: latitude,
    longitude: longitude,
    ocrScanned: false,
    aiCaptionScanned: false,
    aiCaptionEdited: false,
    aiTagsScanned: false,
    isStackCover: false,
  );
}

void main() {
  group('Roundtrip: buildXmpPacket -> parseXmpContent', () {
    test('Bewertung, Farbmarkierung, Beschreibung, Tags, GPS bleiben erhalten', () {
      final asset = _buildAsset(
        rating: 4,
        colorLabel: 'green',
        description: 'Sonnenuntergang am Strand',
        latitude: 52.500171,
        longitude: -13.409877,
      );
      final xml = buildXmpPacket(asset, ['Urlaub', 'Strand']);

      final fields = parseXmpContent(xml);

      expect(fields, isNotNull);
      expect(fields!.rating, 4);
      expect(fields.colorLabel, 'green');
      expect(fields.description, 'Sonnenuntergang am Strand');
      expect(fields.tags, unorderedEquals(['Urlaub', 'Strand']));
      expect(fields.latitude, closeTo(52.500171, 0.0001));
      expect(fields.longitude, closeTo(-13.409877, 0.0001));
    });

    test('leeres Asset ohne gesetzte Felder ergibt null (nichts zu übernehmen)', () {
      final asset = _buildAsset();
      final xml = buildXmpPacket(asset, []);

      final fields = parseXmpContent(xml);

      expect(fields, isNull);
    });

    test('negative GPS-Koordinaten (Süd/West) bleiben im Vorzeichen erhalten', () {
      final asset = _buildAsset(latitude: -33.868, longitude: 151.209);
      final xml = buildXmpPacket(asset, []);

      final fields = parseXmpContent(xml);

      expect(fields!.latitude, closeTo(-33.868, 0.0001));
      expect(fields.longitude, closeTo(151.209, 0.0001));
    });
  });

  group('parseXmpContent gegen handgeschriebene, Lightroom-artige Dateien', () {
    test('mehrere rdf:Description-Blöcke werden zusammengeführt', () {
      const xml = '''
<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:xmp="http://ns.adobe.com/xap/1.0/"
        xmp:Rating="5"
        xmp:Label="Blue"/>
    <rdf:Description rdf:about=""
        xmlns:dc="http://purl.org/dc/elements/1.1/">
      <dc:subject>
        <rdf:Bag>
          <rdf:li>Familie</rdf:li>
          <rdf:li>Geburtstag</rdf:li>
        </rdf:Bag>
      </dc:subject>
      <dc:description>
        <rdf:Alt>
          <rdf:li xml:lang="x-default">Geburtstagsfeier im Garten</rdf:li>
        </rdf:Alt>
      </dc:description>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>
''';

      final fields = parseXmpContent(xml);

      expect(fields, isNotNull);
      expect(fields!.rating, 5);
      expect(fields.colorLabel, 'blue');
      expect(fields.tags, unorderedEquals(['Familie', 'Geburtstag']));
      expect(fields.description, 'Geburtstagsfeier im Garten');
    });

    test('unbekanntes Label wird als null statt Rateversuch übernommen', () {
      const xml = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Label="Türkis"/>
  </rdf:RDF>
</x:xmpmeta>
''';

      final fields = parseXmpContent(xml);

      expect(fields, isNull); // einzig gesetztes Feld ist unbekannt -> effektiv leer
    });

    test('kaputtes/kein XML ergibt null statt eines Fehlers', () {
      expect(parseXmpContent('das ist kein XML {{{'), isNull);
      expect(parseXmpContent(''), isNull);
      expect(parseXmpContent('<x:xmpmeta></x:xmpmeta>'), isNull);
    });
  });
}

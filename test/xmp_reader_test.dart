import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
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
    transkriptGeprueft: false,
    isStackCover: false,
  );
}

String _mitBewertung(String wert) =>
    '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
    'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
    '<rdf:Description xmlns:xmp="http://ns.adobe.com/xap/1.0/" '
    'xmp:Rating="$wert"/></rdf:RDF></x:xmpmeta>';

void main() {
  group('Bewertung aus fremden Programmen (#344)', () {
    test('-1 heisst abgelehnt und ist keine Bewertung', () {
      final f = parseXmpContent(_mitBewertung('-1'))!;
      expect(f.abgelehnt, isTrue);
      expect(f.rating, isNull);
    });

    test('0 bis 5 gelten', () {
      for (final w in [0, 1, 5]) {
        final f = parseXmpContent(_mitBewertung('$w'))!;
        expect(f.rating, w);
        expect(f.abgelehnt, isFalse);
      }
    });

    test('alles andere fällt weg', () {
      expect(parseXmpContent(_mitBewertung('6')), isNull);
      expect(parseXmpContent(_mitBewertung('-2')), isNull);
      expect(parseXmpContent(_mitBewertung('gut')), isNull);
    });
  });

  group('Beilagen beim Import und aus einem Ordner (#346)', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('pv_beilage_'));
    tearDown(() => ordner.deleteSync(recursive: true));

    test('findet beide Namen und liest das Urteil', () {
      File('${ordner.path}/a.CR3.xmp').writeAsStringSync(_mitBewertung('4'));
      expect(beilageNeben('${ordner.path}/a.CR3')?.sterne, 4);
      File('${ordner.path}/b.xmp').writeAsStringSync(_mitBewertung('-1'));
      expect(beilageNeben('${ordner.path}/b.CR3')?.abgelehnt, isTrue);
    });

    test('ohne Beilage oder mit 0 Sternen nichts', () {
      expect(beilageNeben('${ordner.path}/nix.CR3'), isNull);
      File('${ordner.path}/n.xmp').writeAsStringSync(_mitBewertung('0'));
      expect(beilageNeben('${ordner.path}/n.CR3'), isNull);
    });

    test('kaputte Beilage stört den Import nicht', () {
      File('${ordner.path}/k.xmp').writeAsStringSync('<kein xml');
      expect(beilageNeben('${ordner.path}/k.CR3'), isNull);
    });

    test('ordnet nach dem Namen zu, in beiden Schreibweisen', () {
      final z = ordneBeilagenZu(
        [File('/x/IMG_1.CR3.xmp'), File('/x/img_2.xmp')],
        [(id: 'a', name: 'IMG_1.CR3'), (id: 'b', name: 'IMG_2.JPG')],
      );
      expect(z['a']?.path, '/x/IMG_1.CR3.xmp');
      expect(z['b']?.path, '/x/img_2.xmp');
    });

    test('zwei Fotos mit gleichem Namen bleiben ohne Beilage', () {
      final z = ordneBeilagenZu(
        [File('/x/IMG_1.CR3.xmp')],
        [(id: 'a', name: 'IMG_1.CR3'), (id: 'b', name: 'IMG_1.CR3')],
      );
      expect(z, isEmpty);
    });
  });

  test('Schlagwörter, die darktable sich selbst gibt, fallen weg (#346)', () {
    const xmp = '''
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF
 xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"
 xmlns:lr="http://ns.adobe.com/lightroom/1.0/">
<dc:subject><rdf:Bag><rdf:li>Fluss</rdf:li><rdf:li>darktable</rdf:li>
<rdf:li>format</rdf:li><rdf:li>cr3</rdf:li></rdf:Bag></dc:subject>
<lr:hierarchicalSubject><rdf:Bag><rdf:li>Orte|Fluss</rdf:li>
<rdf:li>darktable|format|cr3</rdf:li></rdf:Bag></lr:hierarchicalSubject>
</rdf:Description></rdf:RDF></x:xmpmeta>''';
    expect(parseXmpContent(xmp)!.tags, ['Fluss']);
  });

  group('Beilage unter zwei Namen (#343)', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('pv_xmp_'));
    tearDown(() => ordner.deleteSync(recursive: true));

    File datei(String name, DateTime zeit) {
      final f = File('${ordner.path}/$name')..writeAsStringSync('x');
      f.setLastModifiedSync(zeit);
      return f;
    }

    test('nimmt die vorhandene', () {
      final dt = datei('a.CR3.xmp', DateTime(2026));
      expect(
        neuesteXmpBeilage([File('${ordner.path}/a.xmp'), dt])?.path,
        dt.path,
      );
    });

    test('von zweien die zuletzt geänderte', () {
      final eigene = datei('a.xmp', DateTime(2026, 3));
      final dt = datei('a.CR3.xmp', DateTime(2026, 5));
      expect(neuesteXmpBeilage([eigene, dt])?.path, dt.path);
      dt.setLastModifiedSync(DateTime(2026, 1));
      expect(neuesteXmpBeilage([eigene, dt])?.path, eigene.path);
    });

    test('ohne Datei nichts', () {
      expect(neuesteXmpBeilage([File('${ordner.path}/nix.xmp')]), isNull);
    });
  });

  group('Roundtrip: buildXmpPacket -> parseXmpContent', () {
    test(
      'Bewertung, Farbmarkierung, Beschreibung, Tags, GPS bleiben erhalten',
      () {
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
      },
    );

    test(
      'leeres Asset ohne gesetzte Felder ergibt null (nichts zu übernehmen)',
      () {
        final asset = _buildAsset();
        final xml = buildXmpPacket(asset, []);

        final fields = parseXmpContent(xml);

        expect(fields, isNull);
      },
    );

    test(
      'negative GPS-Koordinaten (Süd/West) bleiben im Vorzeichen erhalten',
      () {
        final asset = _buildAsset(latitude: -33.868, longitude: 151.209);
        final xml = buildXmpPacket(asset, []);

        final fields = parseXmpContent(xml);

        expect(fields!.latitude, closeTo(-33.868, 0.0001));
        expect(fields.longitude, closeTo(151.209, 0.0001));
      },
    );
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

      expect(
        fields,
        isNull,
      ); // einzig gesetztes Feld ist unbekannt -> effektiv leer
    });

    test('kaputtes/kein XML ergibt null statt eines Fehlers', () {
      expect(parseXmpContent('das ist kein XML {{{'), isNull);
      expect(parseXmpContent(''), isNull);
      expect(parseXmpContent('<x:xmpmeta></x:xmpmeta>'), isNull);
    });
  });
}

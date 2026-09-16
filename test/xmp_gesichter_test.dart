import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/xmp_reader.dart';
import 'package:photo_vault/services/xmp_regionen.dart';
import 'package:photo_vault/services/xmp_writer.dart';

/// In dieser Bibliothek stehen 17.867 erkannte Gesichter, 39 davon benannt.
/// Diese Handarbeit konnte das Programm weder verlassen noch erreichen: Der
/// Schreiber schrieb keine MWG-RS-Regionen, und der Leser begründete sein
/// Fehlen damit, dass es „nichts Verlässliches zum Zurücklesen" gebe – ein
/// Zustand, der sich selbst erhält.
///
/// Der Rundlauf ist deshalb die wichtigste Prüfung hier. Er hat schon beim
/// GEDCOM-Export ein fehlendes Feld aufgedeckt, das beim Lesen des Quelltexts
/// niemandem aufgefallen war.

AssetData _foto({int? breite, int? hoehe}) => AssetData(
      id: 'a',
      relativePath: 'originals/a.jpg',
      originalFileName: 'a.jpg',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: 'a',
      fileCreatedAt: DateTime(2026, 8, 1),
      importedAt: DateTime(2026, 8, 1),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 0,
      widthPx: breite,
      heightPx: hoehe,
    );

void main() {
  group('Rundlauf', () {
    test('geschriebene Regionen kommen unverändert zurück', () {
      final vorher = [
        const Gesichtsregion(name: 'Anna', links: 0.10, oben: 0.20, breite: 0.15, hoehe: 0.20),
        const Gesichtsregion(name: 'Bernd', links: 0.60, oben: 0.25, breite: 0.12, hoehe: 0.18),
      ];
      final paket = buildXmpPacket(_foto(breite: 4000, hoehe: 3000), const [], gesichter: vorher);
      final zurueck = parseXmpContent(paket)!.gesichter;

      expect(zurueck.length, 2);
      for (var i = 0; i < 2; i++) {
        expect(zurueck[i].name, vorher[i].name);
        expect(zurueck[i].links, closeTo(vorher[i].links, 1e-5), reason: vorher[i].name);
        expect(zurueck[i].oben, closeTo(vorher[i].oben, 1e-5), reason: vorher[i].name);
        expect(zurueck[i].breite, closeTo(vorher[i].breite, 1e-5), reason: vorher[i].name);
        expect(zurueck[i].hoehe, closeTo(vorher[i].hoehe, 1e-5), reason: vorher[i].name);
      }
    });

    test('geschrieben wird die MITTE, nicht die linke obere Ecke', () {
      // Die eine Verwechslung, die nicht auffällt: Der Kasten sässe um eine
      // halbe Gesichtsbreite verschoben und sähe in einem Gruppenbild
      // trotzdem plausibel aus. Deshalb steht die Zahl hier ausgeschrieben.
      final paket = buildXmpPacket(_foto(), const [], gesichter: [
        const Gesichtsregion(name: 'Anna', links: 0.10, oben: 0.20, breite: 0.20, hoehe: 0.40),
      ]);
      expect(paket, contains('stArea:x="0.200000"'));
      expect(paket, contains('stArea:y="0.400000"'));
      expect(paket, contains('stArea:w="0.200000"'));
      expect(paket, contains('stArea:h="0.400000"'));
    });

    test('ohne Gesichter steht kein Regions-Block und kein Namensraum da', () {
      final paket = buildXmpPacket(_foto(), const ['Urlaub']);
      expect(paket.contains('mwg-rs'), isFalse);
      expect(parseXmpContent(paket)!.gesichter, isEmpty);
    });

    test('die Bildmasse stehen dabei, sobald sie bekannt sind', () {
      final mit = buildXmpPacket(_foto(breite: 4000, hoehe: 3000), const [],
          gesichter: [const Gesichtsregion(name: 'A', links: 0, oben: 0, breite: 0.1, hoehe: 0.1)]);
      expect(mit, contains('stDim:w="4000"'));
      expect(mit, contains('stDim:h="3000"'));

      final ohne = buildXmpPacket(_foto(), const [],
          gesichter: [const Gesichtsregion(name: 'A', links: 0, oben: 0, breite: 0.1, hoehe: 0.1)]);
      expect(ohne.contains('AppliedToDimensions'), isFalse);
    });

    test('Tags und Regionen stehen nebeneinander, ohne sich zu stören', () {
      final paket = buildXmpPacket(
        _foto(),
        const ['Urlaub', 'Strand'],
        gesichter: [const Gesichtsregion(name: 'Anna', links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.2)],
      );
      final felder = parseXmpContent(paket)!;
      expect(felder.tags, ['Urlaub', 'Strand']);
      expect(felder.gesichter.single.name, 'Anna');
    });
  });

  group('Fremde Pakete lesen', () {
    /// Ein Ausschnitt in Lightroom-Schreibweise: Regionen in einem eigenen
    /// Description-Block, Namensräume verteilt.
    String fremd(String regionen) => '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>
  <rdf:Description rdf:about=""
    xmlns:mwg-rs="http://www.metadataworkinggroup.com/schemas/regions/"
    xmlns:stArea="http://ns.adobe.com/xmp/sType/Area#">
   <mwg-rs:Regions rdf:parseType="Resource">
    <mwg-rs:RegionList>
     <rdf:Bag>
$regionen
     </rdf:Bag>
    </mwg-rs:RegionList>
   </mwg-rs:Regions>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

    String region(String name, {String typ = 'Face', String x = '0.5', String y = '0.5'}) => '''
      <rdf:li rdf:parseType="Resource">
       <mwg-rs:Name>$name</mwg-rs:Name>
       <mwg-rs:Type>$typ</mwg-rs:Type>
       <mwg-rs:Area stArea:x="$x" stArea:y="$y" stArea:w="0.2" stArea:h="0.2" stArea:unit="normalized"/>
      </rdf:li>''';

    test('liest Regionen aus einem verteilten Paket samt Bewertung', () {
      final felder = parseXmpContent(fremd(region('Anna')))!;
      expect(felder.rating, 4);
      expect(felder.gesichter.single.name, 'Anna');
      expect(felder.gesichter.single.links, closeTo(0.4, 1e-6));
      expect(felder.gesichter.single.oben, closeTo(0.4, 1e-6));
    });

    test('überspringt, was kein Gesicht ist', () {
      final felder = parseXmpContent(fremd(
        '${region('Anna')}\n${region('Rex', typ: 'Pet', x: '0.2')}',
      ))!;
      expect([for (final g in felder.gesichter) g.name], ['Anna']);
    });

    test('überspringt Regionen ohne Namen', () {
      const ohneNamen = '''
      <rdf:li rdf:parseType="Resource">
       <mwg-rs:Type>Face</mwg-rs:Type>
       <mwg-rs:Area stArea:x="0.5" stArea:y="0.5" stArea:w="0.2" stArea:h="0.2"/>
      </rdf:li>''';
      expect(parseXmpContent(fremd('${region('Anna')}\n$ohneNamen'))!.gesichter.length, 1);
    });

    test('eine Region am Bildrand wird beschnitten statt negativ', () {
      final felder = parseXmpContent(fremd(region('Rand', x: '0.02', y: '0.02')))!;
      expect(felder.gesichter.single.links, 0.0);
      expect(felder.gesichter.single.oben, 0.0);
    });
  });

  group('Eingebettetes XMP', () {
    late Directory tempRoot;
    setUp(() => tempRoot = Directory.systemTemp.createTempSync('pv_xmp_'));
    tearDown(() => tempRoot.deleteSync(recursive: true));

    Uint8List mitPaket(String paket, {int vorlauf = 32, int nachlauf = 32}) {
      final b = BytesBuilder();
      b.add(List.filled(vorlauf, 0xFF));
      b.add(utf8.encode(paket));
      b.add(List.filled(nachlauf, 0x00));
      return b.toBytes();
    }

    test('findet das Paket zwischen Bildbytes', () {
      final paket = buildXmpPacket(_foto(), const ['Strand']);
      final gefunden = xmpAusBytes(mitPaket(paket));
      expect(gefunden, isNotNull);
      expect(parseXmpContent(gefunden!)!.tags, ['Strand']);
    });

    test('ungültige Bytes ringsum bringen das Suchen nicht zum Werfen', () {
      // Latin-1 statt UTF-8 zum Suchen, genau dafür: Rohe Bildbytes sind als
      // UTF-8 ungültig, und ein Decoder darüber würfe.
      final b = BytesBuilder();
      b.add([0xC3, 0x28, 0xA0, 0xA1, 0xFF, 0xFE]);
      b.add(utf8.encode(buildXmpPacket(_foto(), const ['Umlaute äöü'])));
      b.add([0x80, 0x81, 0xFF]);
      final gefunden = xmpAusBytes(b.toBytes());
      expect(parseXmpContent(gefunden!)!.tags, ['Umlaute äöü']);
    });

    test('ohne Paket kommt null zurück, nicht ein halber Fund', () {
      expect(xmpAusBytes(Uint8List.fromList(List.filled(500, 0x42))), isNull);
      // Anfang ohne Ende ist kein Paket.
      expect(xmpAusBytes(Uint8List.fromList(utf8.encode('<x:xmpmeta abgeschnitten'))), isNull);
    });

    test('liest aus einer echten Datei und hält die Suchtiefe ein', () {
      final paket = buildXmpPacket(_foto(), const ['Vorne']);
      final datei = File('${tempRoot.path}/vorne.jpg')..writeAsBytesSync(mitPaket(paket));
      expect(parseEingebettetesXmp(datei)!.tags, ['Vorne']);

      // Dasselbe Paket jenseits der Suchtiefe: bewusst nicht gefunden.
      final weitHinten = File('${tempRoot.path}/hinten.jpg')
        ..writeAsBytesSync(mitPaket(paket, vorlauf: xmpSuchtiefe + 1024));
      expect(parseEingebettetesXmp(weitHinten), isNull);
    });

    test('eine fehlende Datei ergibt null', () {
      expect(parseEingebettetesXmp(File('${tempRoot.path}/gibtesnicht.jpg')), isNull);
    });
  });

  group('Regionen den Gesichtern zuordnen', () {
    test('trifft den überlappenden Kasten', () {
      final paare = regionenZuordnen(
        [const Gesichtsregion(name: 'Anna', links: 0.10, oben: 0.10, breite: 0.20, hoehe: 0.20)],
        [
          (links: 0.60, oben: 0.60, breite: 0.20, hoehe: 0.20),
          (links: 0.12, oben: 0.12, breite: 0.20, hoehe: 0.20),
        ],
      );
      expect(paare.single.$1, 1);
      expect(paare.single.$2.name, 'Anna');
    });

    test('zwei Köpfe nebeneinander bekommen jeder den eigenen Namen', () {
      // Der Fall, für den die Sortierung nach Überdeckung da ist: Der Reihe
      // nach abgearbeitet bekäme die erste Region den falschen Kopf.
      final paare = regionenZuordnen(
        [
          const Gesichtsregion(name: 'Links', links: 0.10, oben: 0.30, breite: 0.20, hoehe: 0.20),
          const Gesichtsregion(name: 'Rechts', links: 0.50, oben: 0.30, breite: 0.20, hoehe: 0.20),
        ],
        [
          (links: 0.52, oben: 0.31, breite: 0.20, hoehe: 0.20),
          (links: 0.11, oben: 0.32, breite: 0.20, hoehe: 0.20),
        ],
      );
      final nachKasten = {for (final (k, r) in paare) k: r.name};
      expect(nachKasten, {0: 'Rechts', 1: 'Links'});
    });

    test('zu geringe Überdeckung bleibt unvergeben', () {
      final paare = regionenZuordnen(
        [const Gesichtsregion(name: 'Anna', links: 0.0, oben: 0.0, breite: 0.10, hoehe: 0.10)],
        [(links: 0.80, oben: 0.80, breite: 0.10, hoehe: 0.10)],
      );
      expect(paare, isEmpty);
    });

    test('jeder Kasten wird höchstens einmal vergeben', () {
      final paare = regionenZuordnen(
        [
          const Gesichtsregion(name: 'A', links: 0.10, oben: 0.10, breite: 0.20, hoehe: 0.20),
          const Gesichtsregion(name: 'B', links: 0.11, oben: 0.11, breite: 0.20, hoehe: 0.20),
        ],
        [(links: 0.10, oben: 0.10, breite: 0.20, hoehe: 0.20)],
      );
      expect(paare.length, 1);
      expect(paare.single.$2.name, 'A', reason: 'die stärkere Überdeckung gewinnt');
    });

    test('dieselbe Eingabe ergibt immer dieselbe Zuordnung', () {
      List<String> lauf() => [
            for (final (k, r) in regionenZuordnen(
              [
                const Gesichtsregion(name: 'A', links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.2),
                const Gesichtsregion(name: 'B', links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.2),
              ],
              [
                (links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.2),
                (links: 0.1, oben: 0.1, breite: 0.2, hoehe: 0.2),
              ],
            ))
              '$k:${r.name}',
          ];
      expect(lauf(), lauf());
    });
  });

  group('Was in den Beipackzettel kommt', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> legeGesicht(String id, {String? personId, bool ignoriert = false}) =>
        db.into(db.faces).insert(FacesCompanion.insert(
              id: id,
              assetId: 'a',
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              personId: Value(personId),
              isIgnored: Value(ignoriert),
            ));

    setUp(() async {
      await db.insertAsset(AssetsCompanion.insert(
        id: 'a',
        relativePath: 'originals/a.jpg',
        originalFileName: 'a.jpg',
        type: 'IMAGE',
        fileSizeBytes: const Value(10),
        checksum: 'a',
        fileCreatedAt: DateTime(2026, 8, 1),
        importedAt: DateTime(2026, 8, 1),
      ));
      await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    });

    test('nur benannte, nicht beiseitegelegte Gesichter', () async {
      await legeGesicht('f1', personId: 'p1');
      await legeGesicht('f2');
      await legeGesicht('f3', personId: 'p1', ignoriert: true);

      final einzeln = await db.gesichtsregionenVon('a');
      expect(einzeln.length, 1);
      expect(einzeln.single.name, 'Anna');

      final alle = await db.alleGesichtsregionen();
      expect(alle['a']!.length, 1);
      expect(alle['a']!.single.name, 'Anna');
    });

    test('ohne benannte Gesichter kommt eine leere Liste, kein Fehler', () async {
      await legeGesicht('f2');
      expect(await db.gesichtsregionenVon('a'), isEmpty);
      expect(await db.alleGesichtsregionen(), isEmpty);
    });
  });
}

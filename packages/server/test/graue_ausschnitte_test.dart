import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/gesichtsausschnitte.dart';
import 'package:kern/services/jpeg_ohne_angaben.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Am Server (#459): Der Nachlauf zeichnet die grau abgelegten
/// Gesichtsausschnitte farbig neu, unter neuem Namen und so, dass die
/// Geräte es über den Abgleich erfahren. Und ein gelöschtes Gesicht nimmt
/// seinen neu gezeichneten Ausschnitt mit.
void main() {
  late Directory ordner;
  late Bibliothek b;

  final kasten = DetectedFace(0.3, 0.3, 0.3, 0.3, 1);

  img.Image buntesFoto() {
    final bild = img.Image(width: 400, height: 300);
    for (final punkt in bild) {
      punkt
        ..r = 180 + (punkt.x % 60)
        ..g = 120 + (punkt.y % 40)
        ..b = 80 + ((punkt.x + punkt.y) % 30);
    }
    return bild;
  }

  /// Ein Foto mit einem Gesicht, dessen Ausschnitt grau abgelegt ist – so,
  /// wie es die Erkennung seit #104 tat.
  Future<void> fotoMitGrauemGesicht(String id, String gesicht) async {
    b.pfade.absolute('originals/$id.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(buntesFoto()));
    await b.db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: 'c_$id',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026, 10, 20),
        importedAt: DateTime(2026, 10, 20),
      ),
    );
    final pfad = b.pfade.faceRelativePath(gesicht);
    b.pfade.absolute(pfad)
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        jpegOhneAngaben(
          img.grayscale(FaceEngineService.cropFaceImage(buntesFoto(), kasten)),
          quality: 85,
        ),
      );
    await b.db.insertFace(
      FacesCompanion.insert(
        id: gesicht,
        assetId: id,
        boxX: kasten.x,
        boxY: kasten.y,
        boxW: kasten.width,
        boxH: kasten.height,
        cropRelativePath: Value(pfad),
      ),
    );
  }

  Future<String?> ausschnitt(String gesicht) async => (await (b.db.select(
    b.db.faces,
  )..where((f) => f.id.equals(gesicht))).getSingleOrNull())?.cropRelativePath;

  /// Die letzte Änderung an dieser Zeile, die der Server für die Geräte
  /// mitgeschrieben hat.
  Future<int> zuletzt(String tabelle, String id) async =>
      (await b.db
              .customSelect(
                'SELECT max(seq) AS n FROM pv_aenderungen '
                'WHERE tabelle = ? AND schluessel = ?',
                variables: [
                  Variable<String>(tabelle),
                  Variable<String>(jsonEncode([id])),
                ],
              )
              .getSingle())
          .readNullable<int>('n') ??
      0;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_graue_ausschnitte_');
    b = await Bibliothek.oeffne(ordner);
  });

  tearDown(() async {
    await b.schliesse();
    await ordner.delete(recursive: true);
  });

  test(
    'der Nachlauf zeichnet sie neu, und die Geräte erfahren davon',
    () async {
      await fotoMitGrauemGesicht('a1', 'g1');
      await b.db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
      await b.db.assignFacesToPerson(['g1'], 'p1');
      await b.db.setPersonCover('p1', 'faces/g1.jpg');
      final gesichtVorher = await zuletzt('faces', 'g1');
      final personVorher = await zuletzt('people', 'p1');

      final dienst = Auswertungsdienst(b);
      await dienst.jetzt();
      await dienst.beende();

      expect(await b.db.aufgabeFertigAm(nachlaufFarbigeAusschnitte), isNotNull);
      expect(await ausschnitt('g1'), 'faces/g1-2.jpg');
      final neu = img.decodeJpg(
        b.pfade.absolute('faces/g1-2.jpg').readAsBytesSync(),
      )!;
      expect(istGrau(neu), isFalse);
      expect(b.pfade.absolute('faces/g1.jpg').existsSync(), isFalse);
      final person = await (b.db.select(
        b.db.people,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(person.coverFaceCropPath, 'faces/g1-2.jpg');
      // Mitgeschrieben für die Geräte: Gesicht und Person.
      expect(await zuletzt('faces', 'g1'), greaterThan(gesichtVorher));
      expect(await zuletzt('people', 'p1'), greaterThan(personVorher));
    },
  );

  test('ein gelöschtes Gesicht nimmt seinen neuen Ausschnitt mit', () async {
    await fotoMitGrauemGesicht('a1', 'g1');
    await fotoMitGrauemGesicht('a2', 'g2');
    await erneuereGraueAusschnitte(b.db, b.pfade);
    expect(await ausschnitt('g1'), 'faces/g1-2.jpg');
    expect(await ausschnitt('g2'), 'faces/g2-2.jpg');

    // Wie es ein Gerät schickt: nur der Befehl.
    await b.db.fuehreAus(const GesichtLoeschen('g1'));
    await b.db.fuehreAus(const GesichterLoeschen(['g2']));
    for (var i = 0; i < 50; i++) {
      if (!b.pfade.absolute('faces/g1-2.jpg').existsSync() &&
          !b.pfade.absolute('faces/g2-2.jpg').existsSync()) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(b.pfade.absolute('faces/g1-2.jpg').existsSync(), isFalse);
    expect(b.pfade.absolute('faces/g2-2.jpg').existsSync(), isFalse);
  });
}

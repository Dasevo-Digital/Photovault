import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/gesichtsausschnitte.dart';
import 'package:kern/services/jpeg_ohne_angaben.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/hintergrundlauf.dart';
import 'package:photo_vault/state/library_state.dart';

/// #459: Von #104 an legte die Gesichtserkennung jeden Ausschnitt grau ab
/// (computeBlurScore färbte ihn in place). Der Nachlauf zeichnet die grauen
/// aus dem Foto neu – farbig, unter neuem Namen, mit dem Profilbild – und
/// lässt farbige, gesperrte und nicht greifbare in Ruhe.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;

  final kasten = DetectedFace(0.3, 0.3, 0.3, 0.3, 1);

  /// Ein buntes Foto: Hauttöne, damit ein Ausschnitt eindeutig farbig ist.
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

  Future<void> aufnahme(
    String id, {
    img.Image? foto,
    bool original = true,
    String typ = 'IMAGE',
    bool gesperrt = false,
    bool papierkorb = false,
  }) async {
    final relativ = 'originals/2026/10/$id.jpg';
    if (original) {
      paths.absolute(relativ)
        ..createSync(recursive: true)
        ..writeAsBytesSync(img.encodeJpg(foto ?? buntesFoto()));
    }
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: relativ,
            checksum: 'c_$id',
            type: typ,
            fileCreatedAt: DateTime(2026, 10, 20),
            importedAt: DateTime(2026, 10, 20),
            isLocked: Value(gesperrt),
            isTrashed: Value(papierkorb),
          ),
        );
  }

  /// Ein Gesicht mit einem Ausschnitt unter `faces/<id>.jpg` – grau, wie
  /// ihn die Erkennung seit #104 ablegte, oder farbig.
  Future<String> gesicht(
    String id,
    String aufnahmeId, {
    required bool grau,
    img.Image? foto,
    List<int>? inhalt,
  }) async {
    var ausschnitt = FaceEngineService.cropFaceImage(
      foto ?? buntesFoto(),
      kasten,
    );
    if (grau) ausschnitt = img.grayscale(ausschnitt);
    final pfad = paths.faceRelativePath(id);
    paths.absolute(pfad)
      ..createSync(recursive: true)
      ..writeAsBytesSync(inhalt ?? jpegOhneAngaben(ausschnitt, quality: 85));
    await db.insertFace(
      FacesCompanion.insert(
        id: id,
        assetId: aufnahmeId,
        boxX: kasten.x,
        boxY: kasten.y,
        boxW: kasten.width,
        boxH: kasten.height,
        cropRelativePath: Value(pfad),
      ),
    );
    return pfad;
  }

  Future<FaceData> zeile(String id) =>
      (db.select(db.faces)..where((f) => f.id.equals(id))).getSingle();

  img.Image lies(String relativ) =>
      img.decodeImage(paths.absolute(relativ).readAsBytesSync())!;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_graue_ausschnitte_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  test('istGrau unterscheidet einen grauen von einem farbigen Ausschnitt', () {
    final bunt = FaceEngineService.cropFaceImage(buntesFoto(), kasten);
    final grau = img.grayscale(img.Image.from(bunt));
    // So, wie sie auf der Platte liegen: als JPEG.
    img.Image rund(img.Image b) =>
        img.decodeJpg(jpegOhneAngaben(b, quality: 85))!;
    expect(istGrau(rund(grau)), isTrue);
    expect(istGrau(rund(bunt)), isFalse);
  });

  test('ein grauer Ausschnitt wird farbig neu gezeichnet, ein farbiger '
      'bleibt', () async {
    await aufnahme('a1');
    final grauerPfad = await gesicht('g1', 'a1', grau: true);
    final farbigerPfad = await gesicht('f1', 'a1', grau: false);
    final farbigVorher = paths.absolute(farbigerPfad).readAsBytesSync();
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await db.assignFacesToPerson(['g1'], 'p1');
    await db.setPersonCover('p1', grauerPfad);

    final r = await erneuereGraueAusschnitte(db, paths);
    expect(r.neu, 1);
    expect(r.offen, 0);
    expect(r.weiter, isNull);

    // Unter neuem Namen: Verbundene Geräte halten den alten vor.
    final g1 = await zeile('g1');
    expect(g1.cropRelativePath, 'faces/g1-2.jpg');
    expect(istGrau(lies(g1.cropRelativePath!)), isFalse);
    expect(lies(g1.cropRelativePath!).width, 160);
    expect(paths.absolute(grauerPfad).existsSync(), isFalse);
    expect(g1.schaerfe, isNotNull);
    // Das Profilbild zieht mit.
    final person = await (db.select(
      db.people,
    )..where((t) => t.id.equals('p1'))).getSingle();
    expect(person.coverFaceCropPath, 'faces/g1-2.jpg');

    // Der farbige bleibt, wie er ist – Name und Datei.
    expect((await zeile('f1')).cropRelativePath, farbigerPfad);
    expect(paths.absolute(farbigerPfad).readAsBytesSync(), farbigVorher);

    // Ein zweiter Lauf hat nichts mehr zu tun.
    final noch = await erneuereGraueAusschnitte(db, paths);
    expect(noch.neu, 0);
    expect((await zeile('g1')).cropRelativePath, 'faces/g1-2.jpg');
  });

  test('gesperrt, im Papierkorb, ohne Original: wartet und kommt später '
      'dran', () async {
    // Gesperrt: Der Ausschnitt ist Chiffrat und wird nicht gelesen.
    await aufnahme('geheim', gesperrt: true);
    final chiffrat = List<int>.generate(512, (i) => (i * 37) % 256);
    await gesicht('gg', 'geheim', grau: true, inhalt: chiffrat);
    await aufnahme('weg', papierkorb: true);
    await gesicht('gw', 'weg', grau: true);
    await aufnahme('fehlt', original: false);
    await gesicht('gf', 'fehlt', grau: true);

    final r = await erneuereGraueAusschnitte(db, paths);
    expect(r.neu, 0);
    expect(r.offen, 3);
    expect(await offeneAusschnitte(paths), {'gg', 'gw', 'gf'});
    expect(
      paths.absolute('faces/gg.jpg').readAsBytesSync(),
      chiffrat,
      reason: 'ein gesperrtes Foto wird nicht angefasst',
    );
    for (final id in ['gg', 'gw', 'gf']) {
      expect((await zeile(id)).cropRelativePath, 'faces/$id.jpg');
    }

    // Entsperrt (der Ausschnitt wieder Klartext), zurückgeholt, das
    // Original wieder da: Der nächste Lauf nimmt sich nur diese vor.
    await (db.update(db.assets)..where((t) => t.id.equals('geheim'))).write(
      const AssetsCompanion(isLocked: Value(false)),
    );
    paths
        .absolute('faces/gg.jpg')
        .writeAsBytesSync(
          jpegOhneAngaben(
            img.grayscale(
              FaceEngineService.cropFaceImage(buntesFoto(), kasten),
            ),
            quality: 85,
          ),
        );
    await (db.update(db.assets)..where((t) => t.id.equals('weg'))).write(
      const AssetsCompanion(isTrashed: Value(false)),
    );
    paths
        .absolute('originals/2026/10/fehlt.jpg')
        .writeAsBytesSync(img.encodeJpg(buntesFoto()));

    final spaeter = await erneuereGraueAusschnitte(
      db,
      paths,
      nur: await offeneAusschnitte(paths),
    );
    expect(spaeter.neu, 3);
    expect(spaeter.offen, 0);
    expect(await offeneAusschnitte(paths), isEmpty);
    for (final id in ['gg', 'gw', 'gf']) {
      final pfad = (await zeile(id)).cropRelativePath!;
      expect(pfad, 'faces/$id-2.jpg');
      expect(istGrau(lies(pfad)), isFalse);
    }
  });

  test('ein schwarzweisses Foto behält seinen grauen Ausschnitt', () async {
    final schwarzweiss = img.grayscale(buntesFoto());
    await aufnahme('sw', foto: schwarzweiss);
    await gesicht('gs', 'sw', grau: true, foto: schwarzweiss);

    final r = await erneuereGraueAusschnitte(db, paths);
    expect(r.neu, 0);
    expect(r.offen, 0);
    expect((await zeile('gs')).cropRelativePath, 'faces/gs.jpg');
    expect(paths.absolute('faces/gs.jpg').existsSync(), isTrue);
  });

  test('ein Gesicht aus einem Video bleibt – sein Standbild steht '
      'nirgends', () async {
    await aufnahme('v1', typ: 'VIDEO');
    await gesicht('gv', 'v1', grau: true);

    final r = await erneuereGraueAusschnitte(db, paths);
    expect(r.neu, 0);
    expect(r.offen, 0);
    expect((await zeile('gv')).cropRelativePath, 'faces/gv.jpg');
  });

  test('in Etappen: jede macht dort weiter, wo die vorige aufhörte', () async {
    for (final id in ['a1', 'a2', 'a3']) {
      await aufnahme(id);
      await gesicht('g_$id', id, grau: true);
    }
    final erste = await erneuereGraueAusschnitte(
      db,
      paths,
      frist: Duration.zero,
    );
    expect(erste.neu, 1);
    expect(erste.weiter, 'a1');
    final zweite = await erneuereGraueAusschnitte(
      db,
      paths,
      ab: erste.weiter,
      frist: Duration.zero,
    );
    expect(zweite.neu, 1);
    expect(zweite.weiter, 'a2');
    final dritte = await erneuereGraueAusschnitte(db, paths, ab: zweite.weiter);
    expect(dritte.neu, 1);
    expect(dritte.weiter, isNull);
    for (final id in ['a1', 'a2', 'a3']) {
      expect((await zeile('g_$id')).cropRelativePath, 'faces/g_$id-2.jpg');
    }
  });

  test('abgebrochen: nichts verloren, ein neuer Lauf macht den Rest', () async {
    for (final id in ['a1', 'a2']) {
      await aufnahme(id);
      await gesicht('g_$id', id, grau: true);
    }
    var gefragt = 0;
    final r = await erneuereGraueAusschnitte(
      db,
      paths,
      abbrechen: () => ++gefragt > 1,
    );
    expect(r.neu, 1);
    expect(r.weiter, isNotNull);
    final rest = await erneuereGraueAusschnitte(db, paths);
    expect(rest.neu, 1);
    expect(rest.weiter, isNull);
  });

  group('am Rechner als Aufgabe', () {
    Hintergrundlauf starte(LibraryState zustand) {
      zustand.reiheAufgabeEin(
        schluessel: nachlaufFarbigeAusschnitte,
        titel: '-',
        leermeldung: '-',
        strom: zustand.erneuereGraueAusschnitteLauf,
      );
      return zustand.lauf(nachlaufFarbigeAusschnitte)!;
    }

    test('ein ganzer Lauf zählt und ist danach erledigt', () async {
      await aufnahme('a1');
      await gesicht('g1', 'a1', grau: true);
      await gesicht('f1', 'a1', grau: false);
      final zustand = LibraryState()
        ..db = db
        ..paths = paths;
      final lauf = starte(zustand);
      await lauf.abschluss;
      await pumpEventQueue();
      expect(lauf.erfolgreich, isTrue);
      expect(lauf.getan, 1);
      expect([lauf.erledigt, lauf.gesamt], [2, 2]);
      expect(await db.aufgabeFertigAm(nachlaufFarbigeAusschnitte), isNotNull);
      expect((await zeile('g1')).cropRelativePath, 'faces/g1-2.jpg');
    });

    test('abgebrochen ist er nicht erledigt und läuft beim nächsten Start '
        'wieder', () async {
      for (final id in ['a1', 'a2', 'a3']) {
        await aufnahme(id);
        await gesicht('g_$id', id, grau: true);
      }
      final zustand = LibraryState()
        ..db = db
        ..paths = paths;
      final lauf = starte(zustand);
      zustand.brichAufgabeAb(nachlaufFarbigeAusschnitte);
      await lauf.abschluss;
      await pumpEventQueue();
      expect(lauf.abgebrochen, isTrue);
      expect(lauf.erfolgreich, isFalse);
      expect(await db.aufgabeFertigAm(nachlaufFarbigeAusschnitte), isNull);
    });
  });
}

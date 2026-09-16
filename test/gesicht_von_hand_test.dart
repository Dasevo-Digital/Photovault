import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/gesicht_von_hand.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Ein von Hand aufgezogenes Gesicht anlegen.**
///
/// Der Weg gehört jetzt zwei Bildschirmen – der Gesichts-Bearbeitung und der
/// Vollbildansicht, die seit Punkt 11 dasselbe kann. Geprüft wird deshalb der
/// gemeinsame Weg und nicht einer der beiden Aufrufer.
///
/// Drei Dinge entstehen dabei, und sie gehören zusammen: der Ausschnitt auf
/// der Platte, die Zeile in der Datenbank und – falls die Person noch keins
/// hat – ihr Profilbild. Eine Fassung, die einen Schritt vergisst, hinterlässt
/// eine verwaiste Datei oder eine Person ohne Bild, und beides fällt erst
/// Monate später auf (siehe die 17.643 verwaisten Ausschnitte der achten
/// Prüfrunde).
void main() {
  late Directory ordner;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;
  late File foto;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_gesicht_hand_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(ordner.path, 'library')));
    library = LibraryState()
      ..db = db
      ..paths = paths;

    // Ein echtes Bild, kein Platzhalter: Der Ausschnitt wird wirklich
    // geschnitten und gespeichert, und ein nicht dekodierbares Bild nähme
    // genau den Zweig, den dieser Prüfstand nicht meint.
    foto = File(p.join(ordner.path, 'foto.jpg'));
    final bild = img.Image(width: 400, height: 300);
    img.fill(bild, color: img.ColorRgb8(120, 140, 160));
    foto.writeAsBytesSync(img.encodeJpg(bild));

    await db.insertAsset(AssetsCompanion.insert(
      id: 'a1',
      relativePath: 'originals/a1.jpg',
      originalFileName: 'a1.jpg',
      type: 'IMAGE',
      checksum: 'c1',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isTrashed: const Value(false),
    ));
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
  });

  tearDown(() async {
    await db.close();
    ordner.deleteSync(recursive: true);
  });

  test('legt Zeile, Ausschnitt und Profilbild an', () async {
    final id = await gesichtVonHandAnlegen(
      library: library,
      assetId: 'a1',
      bilddatei: foto,
      kasten: const Rect.fromLTWH(0.25, 0.2, 0.3, 0.4),
      personId: 'p1',
    );

    expect(id, isNotNull);
    final gesichter = await db.facesForAsset('a1');
    expect(gesichter, hasLength(1));
    final g = gesichter.single;
    expect(g.personId, 'p1');
    expect(g.boxX, closeTo(0.25, 1e-6));
    expect(g.boxW, closeTo(0.3, 1e-6));

    // Der Ausschnitt liegt wirklich da – nicht nur sein Pfad in der Zeile.
    expect(g.cropRelativePath, isNotNull);
    expect(paths.absolute(g.cropRelativePath!).existsSync(), isTrue);

    final person = await (db.select(db.people)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(person.coverFaceCropPath, g.cropRelativePath,
        reason: 'die erste Zuordnung gibt der Person ihr Bild');
  });

  test('ein vorhandenes Profilbild wird nicht überschrieben', () async {
    await gesichtVonHandAnlegen(
      library: library,
      assetId: 'a1',
      bilddatei: foto,
      kasten: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
      personId: 'p1',
    );
    final erstes = (await (db.select(db.people)..where((t) => t.id.equals('p1')))
            .getSingle())
        .coverFaceCropPath;

    await gesichtVonHandAnlegen(
      library: library,
      assetId: 'a1',
      bilddatei: foto,
      kasten: const Rect.fromLTWH(0.5, 0.5, 0.2, 0.2),
      personId: 'p1',
    );
    final zweites = (await (db.select(db.people)..where((t) => t.id.equals('p1')))
            .getSingle())
        .coverFaceCropPath;

    expect(zweites, erstes,
        reason: 'sonst wechselte das Profilbild bei jedem nachgetragenen '
            'Gesicht, auch wenn das erste besser war');
    expect(await db.facesForAsset('a1'), hasLength(2));
  });

  test('ohne Modell entsteht das Gesicht trotzdem, nur ohne Einbettung',
      () async {
    // Der wichtige Zweig: Der Ausschnitt liegt zu diesem Zeitpunkt bereits
    // auf der Platte. Bräche das Anlegen hier ab, bliebe eine Datei ohne
    // die Zeile zurück, die sie erklärt.
    //
    // Gemeldet wird dabei NICHTS, und das ist richtig: `ModellHalter.mit`
    // gibt `null` zurück, wenn das Modell gar nicht installiert ist. Das
    // ist kein Fehlschlag dieser Handlung, sondern ein Zustand des
    // Rechners – eine Meldung dafür wäre eine, die nichts nützt.
    Object? gemeldet;
    final id = await gesichtVonHandAnlegen(
      library: library,
      assetId: 'a1',
      bilddatei: foto,
      kasten: const Rect.fromLTWH(0.25, 0.2, 0.3, 0.4),
      personId: 'p1',
      beiEinbettungsfehler: (e) => gemeldet = e,
    );

    expect(id, isNotNull, reason: 'das Gesicht muss trotzdem entstehen');
    final g = (await db.facesForAsset('a1')).single;
    expect(g.embedding, isNull);
    expect(gemeldet, isNull);
  });

  test('ein unlesbares Bild legt gar nichts an', () async {
    // Die Gegenprobe zum Zweig oben: Hier darf NICHTS entstehen, auch keine
    // Datei – es gibt nichts zu schneiden.
    final kaputt = File(p.join(ordner.path, 'kaputt.jpg'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final id = await gesichtVonHandAnlegen(
      library: library,
      assetId: 'a1',
      bilddatei: kaputt,
      kasten: const Rect.fromLTWH(0.25, 0.2, 0.3, 0.4),
      personId: 'p1',
    );
    expect(id, isNull);
    expect(await db.facesForAsset('a1'), isEmpty);
    expect(paths.facesDir.listSync(), isEmpty);
  });

  group('Wie gross ein Rahmen sein muss', () {
    test('ein Tipp ist kein Rahmen', () {
      expect(rahmenGrossGenug(const Rect.fromLTWH(0.5, 0.5, 0, 0)), isFalse);
      expect(
          rahmenGrossGenug(const Rect.fromLTWH(0.5, 0.5, 0.004, 0.004)), isFalse);
    });

    test('ein deutlich gezogener Rahmen genügt', () {
      expect(rahmenGrossGenug(const Rect.fromLTWH(0.1, 0.1, 0.05, 0.05)), isTrue);
      // Genau auf der Grenze wird nichts zugesichert: Rect speichert die
      // Kanten, und 0,11 minus 0,1 sind 0,009999999999999995. Für „Zug oder
      // Tipp?" ist das ohne Belang – aber es hier zu behaupten wäre eine
      // Genauigkeit, die es nicht gibt.
    });

    test('ein flacher Strich zählt nicht', () {
      // Beide Kanten müssen reichen. Ein waagerechter Wisch über das halbe
      // Bild ergäbe sonst einen „Rahmen" ohne Höhe.
      expect(rahmenGrossGenug(const Rect.fromLTWH(0.1, 0.1, 0.5, 0.002)), isFalse);
      expect(rahmenGrossGenug(const Rect.fromLTWH(0.1, 0.1, 0.002, 0.5)), isFalse);
    });
  });

  /// **Der Zug und der Rahmen müssen dieselbe Rechnung sein.**
  ///
  /// [Gesichtsrahmen] setzt einen Kasten mit `boxX * flaeche.width`;
  /// [kastenAusZug] geht denselben Weg zurück. Liefen die beiden
  /// auseinander, läge ein frisch gezogener Rahmen neben dem Gesicht, um
  /// das er gezogen wurde – und man suchte den Fehler in der Erkennung.
  group('Vom Zug zum Kasten', () {
    const flaeche = Size(800, 600);

    test('was hingezogen wurde, kommt dort wieder heraus', () {
      final kasten = kastenAusZug(
          const Offset(200, 150), const Offset(400, 450), flaeche);
      expect(kasten.left, closeTo(0.25, 1e-9));
      expect(kasten.top, closeTo(0.25, 1e-9));
      expect(kasten.right, closeTo(0.5, 1e-9));
      expect(kasten.bottom, closeTo(0.75, 1e-9));
    });

    test('der Rundlauf über die Darstellung trifft sich selbst', () {
      // Genau die Rechnung, die Gesichtsrahmen macht – nur andersherum.
      const box = Rect.fromLTWH(0.3, 0.4, 0.2, 0.1);
      final links = box.left * flaeche.width;
      final oben = box.top * flaeche.height;
      final zurueck = kastenAusZug(
        Offset(links, oben),
        Offset(links + box.width * flaeche.width,
            oben + box.height * flaeche.height),
        flaeche,
      );
      expect(zurueck.left, closeTo(box.left, 1e-9));
      expect(zurueck.top, closeTo(box.top, 1e-9));
      expect(zurueck.width, closeTo(box.width, 1e-9));
      expect(zurueck.height, closeTo(box.height, 1e-9));
    });

    test('die Richtung des Zuges ist egal', () {
      final hin = kastenAusZug(
          const Offset(200, 150), const Offset(400, 450), flaeche);
      final zurueck = kastenAusZug(
          const Offset(400, 450), const Offset(200, 150), flaeche);
      expect(zurueck, hin,
          reason: 'von rechts unten nach links oben ist derselbe Kasten');
    });

    test('was über den Rand geht, wird abgeschnitten', () {
      final kasten = kastenAusZug(
          const Offset(-120, -90), const Offset(1600, 1200), flaeche);
      expect(kasten, const Rect.fromLTRB(0, 0, 1, 1),
          reason: 'ein Anteil über 1 stünde in der Datenbank und läge '
              'in jeder Ansicht ausserhalb des Bildes');
    });

    test('ohne Fläche gibt es keinen Kasten statt einer Division durch null',
        () {
      expect(kastenAusZug(Offset.zero, const Offset(10, 10), Size.zero),
          Rect.zero);
    });
  });
}

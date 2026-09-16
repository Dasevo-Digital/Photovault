import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/personenvorschlag.dart';

/// **Die Erkennung war da – gefragt hat sie niemand.**
///
/// `personenvorschlag()` rechnet seit langem, wer auf einem Gesicht zu
/// sehen sein koennte. Aufgerufen wurde sie an drei Stellen, und alle
/// drei setzen voraus, dass jemand ein Gesicht **anschaut**. Nach einem
/// Import lagen die neuen Gesichter deshalb da. An der echten Bibliothek
/// endete das so: 2473 Gesichter zugeordnet, 14.065 von Hand
/// beiseitegelegt – die Warteschlange war nicht abgearbeitet, sondern
/// weggeraeumt. 960 der Weggelegten liegen ueber der Schwelle einer
/// inzwischen benannten Person.
///
/// Geprueft wird hier, was der neue Lauf schreibt und was die Zahlen
/// darauf melden – vor allem die Grenzen: Beiseitegelegtes bleibt
/// draussen, solange niemand ausdruecklich danach fragt.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Uint8List vektor(List<double> werte) =>
      blobFromEmbeddingFloats(Float32List.fromList(werte));

  Future<void> foto(String id, {bool papierkorb = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 5, 1),
            importedAt: DateTime(2026, 5, 1),
            isTrashed: Value(papierkorb),
          ));

  Future<void> gesicht(
    String id, {
    required String assetId,
    String? personId,
    List<double>? einbettung,
    bool beiseite = false,
    String? vorschlag,
    double? wert,
    DateTime? geprueft,
  }) =>
      db.into(db.faces).insert(FacesCompanion.insert(
            id: id,
            assetId: assetId,
            boxX: 0,
            boxY: 0,
            boxW: 1,
            boxH: 1,
            personId: Value(personId),
            embedding:
                Value(einbettung == null ? null : vektor(einbettung)),
            isIgnored: Value(beiseite),
            vorschlagPersonId: Value(vorschlag),
            vorschlagWert: Value(wert),
            vorschlagGeprueftAm: Value(geprueft),
          ));

  Future<String> person(String name) async {
    final id = 'p_$name';
    await db
        .into(db.people)
        .insert(PeopleCompanion.insert(id: id, name: name));
    return id;
  }

  group('was der Lauf ansieht', () {
    test('geprueft ist geprueft – der zweite Lauf faengt nicht von vorn an',
        () async {
      await foto('a');
      await gesicht('offen', assetId: 'a', einbettung: [1, 0]);
      await gesicht('schon', assetId: 'a', einbettung: [1, 0],
          geprueft: DateTime(2026, 5, 2));

      expect(
          [for (final g in await db.gesichterFuerWiedererkennung()) g.id],
          ['offen']);
      // Und mit „alle" sind beide wieder dabei – der Weg, nachdem neue
      // Personen benannt wurden.
      expect((await db.gesichterFuerWiedererkennung(alle: true)).length, 2);
    });

    test('beiseitegelegte bleiben draussen, bis jemand danach fragt',
        () async {
      await foto('a');
      await gesicht('weg', assetId: 'a', einbettung: [1, 0], beiseite: true);

      expect(await db.countWiedererkennungOffen(), 0);
      expect(await db.countWiedererkennungOffen(beiseite: true), 1);
    });

    test('ohne Einbettung und im Papierkorb ist nichts zu vergleichen',
        () async {
      await foto('a');
      await foto('weg', papierkorb: true);
      await gesicht('ohne', assetId: 'a');
      await gesicht('imMuell', assetId: 'weg', einbettung: [1, 0]);

      expect(await db.countWiedererkennungOffen(), 0);
    });
  });

  group('was der Lauf schreibt', () {
    test('die Marke wird auch dann gesetzt, wenn nichts gefunden wurde',
        () async {
      await foto('a');
      await gesicht('fremd', assetId: 'a', einbettung: [0, 1]);

      await db.merkeVorschlaege([
        (faceId: 'fremd', personId: null, wert: null),
      ]);

      final g = await (db.select(db.faces)
            ..where((t) => t.id.equals('fremd')))
          .getSingle();
      expect(g.vorschlagPersonId, isNull);
      expect(g.vorschlagGeprueftAm, isNotNull);
      // Und damit ist er aus dem naechsten Lauf heraus – sonst begaenne
      // jeder Lauf wieder bei allen.
      expect(await db.countWiedererkennungOffen(), 0);
    });
  });

  group('was die Zahlen melden', () {
    test('gezaehlt wird, was auf eine Entscheidung wartet', () async {
      final anna = await person('Anna');
      await foto('a');
      await gesicht('warte', assetId: 'a', einbettung: [1, 0],
          vorschlag: anna, wert: 0.8, geprueft: DateTime(2026, 5, 2));
      await gesicht('nichts', assetId: 'a', einbettung: [0, 1],
          geprueft: DateTime(2026, 5, 2));
      await gesicht('weggelegt', assetId: 'a', einbettung: [1, 0],
          beiseite: true,
          vorschlag: anna,
          wert: 0.9,
          geprueft: DateTime(2026, 5, 2));

      expect(await db.countVorschlaege(), 1);
      expect(await db.countVorschlaege(beiseite: true), 1);

      final jePerson = await db.vorschlaegeJePerson();
      expect(jePerson.single.person.name, 'Anna');
      expect(jePerson.single.anzahl, 1);
    });

    test('je Person absteigend nach Aehnlichkeit – das Sicherste zuerst',
        () async {
      final anna = await person('Anna');
      await foto('a');
      await gesicht('mittel', assetId: 'a', einbettung: [1, 0],
          vorschlag: anna, wert: 0.7);
      await gesicht('sicher', assetId: 'a', einbettung: [1, 0],
          vorschlag: anna, wert: 0.9);

      final liste = await db.vorschlaegeFuerPerson(anna);
      expect([for (final v in liste) v.gesicht.id], ['sicher', 'mittel']);
      expect(liste.first.aehnlichkeit, 0.9);
    });
  });

  group('die stille Luecke', () {
    test('beiseitegelegt und nie verglichen wird eigens gezaehlt', () async {
      await foto('a');
      await gesicht('weg1', assetId: 'a', einbettung: [1, 0], beiseite: true);
      await gesicht('weg2', assetId: 'a', einbettung: [1, 0], beiseite: true);
      // Schon angesehen: kein offener Posten mehr.
      await gesicht('weg3', assetId: 'a', einbettung: [1, 0],
          beiseite: true, geprueft: DateTime(2026, 5, 2));
      // Nicht beiseite: gehoert in die andere Zahl.
      await gesicht('offen', assetId: 'a', einbettung: [1, 0]);

      expect(await db.countBeiseiteNieVerglichen(), 2);
      // Und die Zahl, an der die Karte haengt, meldet davon nichts – das
      // ist der Grund, warum es die zweite ueberhaupt gibt.
      expect(await db.countVorschlaege(), 0);
      expect(await db.countVorschlaege(beiseite: true), 0);
    });

    test('nach dem Durchgang ist die Zahl weg, auch ohne Treffer', () async {
      await foto('a');
      await gesicht('weg', assetId: 'a', einbettung: [1, 0], beiseite: true);
      expect(await db.countBeiseiteNieVerglichen(), 1);

      await db.merkeVorschlaege([
        (faceId: 'weg', personId: null, wert: null),
      ]);

      expect(await db.countBeiseiteNieVerglichen(), 0);
    });
  });

  group('was nach der Entscheidung passiert', () {
    test('ein angenommener Vorschlag verschwindet aus der Schlange',
        () async {
      final anna = await person('Anna');
      await foto('a');
      await gesicht('ja', assetId: 'a', einbettung: [1, 0],
          vorschlag: anna, wert: 0.9);

      await db.assignFacesToPerson(['ja'], anna);

      final g = await (db.select(db.faces)..where((t) => t.id.equals('ja')))
          .getSingle();
      expect(g.personId, anna);
      expect(g.vorschlagPersonId, isNull);
      expect(await db.countVorschlaege(), 0);
    });

    test('ein abgelehnter auch – aber die Marke bleibt stehen', () async {
      final anna = await person('Anna');
      await foto('a');
      await gesicht('nein', assetId: 'a', einbettung: [1, 0],
          vorschlag: anna, wert: 0.9, geprueft: DateTime(2026, 5, 2));

      await db.verwirfVorschlaege(['nein']);

      final g = await (db.select(db.faces)..where((t) => t.id.equals('nein')))
          .getSingle();
      expect(g.vorschlagPersonId, isNull);
      expect(g.vorschlagGeprueftAm, isNotNull,
          reason: 'sonst stuende dieselbe Frage sofort wieder da');
      expect(await db.countVorschlaege(), 0);
      expect(await db.countWiedererkennungOffen(), 0);
    });
  });

  group('die Rechnung selbst', () {
    test('der Kern einer Person zieht ein aehnliches Gesicht an', () async {
      final anna = await person('Anna');
      await foto('a');
      await gesicht('anna1', assetId: 'a',
          personId: anna, einbettung: [1, 0, 0]);
      await gesicht('anna2', assetId: 'a',
          personId: anna, einbettung: [0.9, 0.1, 0]);

      final roh = await db.einbettungenZugeordneterGesichter();
      final kerne = personenkerne([
        for (final e in roh)
          (personId: e.personId, vektor: floatsFromEmbeddingBlob(e.vektor)),
      ]);
      expect(kerne.single.personId, anna);

      final nah = besterTreffer(
        Float32List.fromList([0.95, 0.05, 0]),
        kerne,
        schwelleFuer: (_) => 0.55,
      );
      expect(nah?.personId, anna);

      final fremd = besterTreffer(
        Float32List.fromList([0, 0, 1]),
        kerne,
        schwelleFuer: (_) => 0.55,
      );
      expect(fremd, isNull, reason: 'lieber nichts sagen als raten');
    });
  });
}

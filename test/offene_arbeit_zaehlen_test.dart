import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Zwei Zahlen für den Gesundheitsbildschirm – und beide müssen stimmen.**
///
/// An der gewachsenen Bibliothek warteten 408 erbbare Orte und 1658
/// unzugeordnete Gesichter. Die Werkzeuge dafür gibt es längst; was fehlte,
/// war die Auskunft, dass etwas wartet.
///
/// Eine Zahl, die mehr verspricht als die Liste dahinter zeigt, ist dabei
/// schlimmer als keine. Deshalb zählt [AppDatabase.countOrtsvorschlagskandidaten]
/// nicht „alles ohne Ort" (das wären an jener Bibliothek 5143), sondern nur
/// das, was der Ortsvorschlag auch anbieten kann.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(
    String id,
    DateTime wann, {
    double? breite,
    bool geloescht = false,
    bool gesperrt = false,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'c_$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: DateTime(2026),
            latitude: Value(breite),
            longitude: Value(breite == null ? null : 9.7),
            isTrashed: Value(geloescht),
            isLocked: Value(gesperrt),
          ));

  Future<void> gesicht(String id, String assetId,
          {String? person, bool beiseite = false}) =>
      db.into(db.faces).insert(FacesCompanion.insert(
            id: id,
            assetId: assetId,
            boxX: 0.1,
            boxY: 0.1,
            boxW: 0.2,
            boxH: 0.2,
            personId: Value(person),
            isIgnored: Value(beiseite),
          ));

  group('Ortsvorschlagskandidaten', () {
    test('zählt nur, was einen verorteten Nachbarn im Fenster hat', () async {
      final t = DateTime(2026, 5, 1, 12);
      await aufnahme('verortet', t, breite: 52.4);
      await aufnahme('knapp_davor', t.subtract(const Duration(minutes: 90)));
      await aufnahme('knapp_danach', t.add(const Duration(minutes: 90)));
      await aufnahme('weit_weg', t.add(const Duration(hours: 9)));

      expect(await db.countOrtsvorschlagskandidaten(), 2,
          reason: 'Nur die beiden innerhalb von zwei Stunden.');
    });

    test('die Fenstergrenze zählt in beide Richtungen', () async {
      final t = DateTime(2026, 5, 1, 12);
      await aufnahme('verortet', t, breite: 52.4);
      await aufnahme('genau_auf_der_grenze', t.add(const Duration(hours: 2)));
      await aufnahme('eine_sekunde_zu_spaet',
          t.add(const Duration(hours: 2, seconds: 1)));

      expect(await db.countOrtsvorschlagskandidaten(), 1);
      expect(
          await db.countOrtsvorschlagskandidaten(
              fensterSekunden: 3 * 60 * 60),
          2,
          reason: 'Ein weiteres Fenster nimmt beide mit.');
    });

    test('ohne ein einziges verortetes Foto gibt es nichts zu erben',
        () async {
      await aufnahme('a', DateTime(2026, 5, 1, 12));
      await aufnahme('b', DateTime(2026, 5, 1, 13));

      expect(await db.countOrtsvorschlagskandidaten(), 0);
    });

    test('gelöschte Aufnahmen zählen weder als Kandidat noch als Nachbar',
        () async {
      final t = DateTime(2026, 5, 1, 12);
      await aufnahme('verortet_aber_geloescht', t,
          breite: 52.4, geloescht: true);
      await aufnahme('ohne_ort', t.add(const Duration(minutes: 10)));

      expect(await db.countOrtsvorschlagskandidaten(), 0,
          reason: 'Der einzige Nachbar liegt im Papierkorb.');
    });
  });

  group('offene Gesichter', () {
    test('zählt nur die, die wirklich noch jemandem gehören könnten',
        () async {
      await aufnahme('foto', DateTime(2026, 5, 1));
      await aufnahme('muell', DateTime(2026, 5, 1), geloescht: true);
      await aufnahme('tresor', DateTime(2026, 5, 1), gesperrt: true);
      await db.into(db.people).insert(
          PeopleCompanion.insert(id: 'p1', name: 'Jemand'));

      await gesicht('offen1', 'foto');
      await gesicht('offen2', 'foto');
      await gesicht('zugeordnet', 'foto', person: 'p1');
      await gesicht('beiseite', 'foto', beiseite: true);
      await gesicht('im_muell', 'muell');
      await gesicht('im_tresor', 'tresor');

      expect(await db.countOffeneGesichter(), 2);
    });

    test('ohne Gesichter ist die Antwort null, nicht ein Fehler', () async {
      expect(await db.countOffeneGesichter(), 0);
    });
  });
}

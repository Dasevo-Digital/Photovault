import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Koordinaten für Lebensereignisse.
///
/// Ereignisse führen ihren Ort als **Text** und landen deshalb auf keiner
/// Karte. Schema 50 legt zwei Spalten daneben – ausdrücklich *daneben*
/// und nicht *statt*: Ein Ortsname, den der GeoNames-Auszug nicht kennt,
/// bleibt als Text stehen und ist damit nicht verloren.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> personAnlegen(String id) =>
      db.createPerson(PeopleCompanion.insert(id: id, name: 'Person $id'));

  Future<void> ereignis(String id,
      {String? ort, double? breite, double? laenge}) =>
      db.fuegeEreignisHinzu(LebensereignisseCompanion.insert(
        id: id,
        personId: 'p1',
        art: 'hochzeit',
        ort: Value(ort),
        ortBreite: Value(breite),
        ortLaenge: Value(laenge),
      ));

  setUp(() => personAnlegen('p1'));

  test('ohne Koordinate heisst: hat einen Ortsnamen, aber keinen Punkt',
      () async {
    await ereignis('e1', ort: 'Berlin');
    await ereignis('e2', ort: 'Wien', breite: 48.2, laenge: 16.37);
    await ereignis('e3');

    final offen = await db.ereignisseOhneKoordinate();
    expect(offen.map((e) => e.id), ['e1'],
        reason: 'e2 hat schon einen Punkt, e3 gar keinen Ort');
  });

  test('ein leerer Ortsname zaehlt nicht als Ort', () async {
    // Sonst liefe die Ortssuche bei jedem Start über Zeilen, in denen
    // nichts steht – und ein leerer Text ist keine Angabe.
    await ereignis('e1', ort: '');
    expect(await db.ereignisseOhneKoordinate(), isEmpty);
  });

  test('gesetzte Koordinaten kommen zurueck', () async {
    await ereignis('e1', ort: 'Berlin');
    await db.setzeEreignisort('e1', breite: 52.52, laenge: 13.41);

    final mit = await db.ereignisseMitKoordinate();
    expect(mit, hasLength(1));
    expect(mit.single.ortBreite, closeTo(52.52, 0.001));
    expect(mit.single.ortLaenge, closeTo(13.41, 0.001));
    expect(mit.single.ort, 'Berlin',
        reason: 'der aufgeschriebene Name bleibt unangetastet');
  });

  test('eine gesetzte Koordinate faellt aus dem Nachtragen heraus', () async {
    // Der Kern der Sache: Wer einen falsch geratenen Punkt von Hand
    // berichtigt, darf ihn beim naechsten Start nicht wieder ueberschrieben
    // finden.
    await ereignis('e1', ort: 'Springfield');
    expect(await db.ereignisseOhneKoordinate(), hasLength(1));

    await db.setzeEreignisort('e1', breite: 39.79, laenge: -89.64);
    expect(await db.ereignisseOhneKoordinate(), isEmpty,
        reason: 'ab jetzt gilt die Berichtigung');
  });

  test('eine Koordinate laesst sich auch wieder wegnehmen', () async {
    // „Nicht verortet" muss ein erreichbarer Zustand bleiben - sonst
    // liesse sich eine falsche Zuordnung nur durch Loeschen des ganzen
    // Ereignisses beheben.
    await ereignis('e1', ort: 'Berlin', breite: 52.52, laenge: 13.41);
    await db.setzeEreignisort('e1');

    expect(await db.ereignisseMitKoordinate(), isEmpty);
    final offen = await db.ereignisseOhneKoordinate();
    expect(offen.single.ort, 'Berlin',
        reason: 'der Name bleibt, nur der Punkt ist weg');
  });

  test('die Fassung mit den Ortsspalten ist erreicht', () async {
    // Nur „mindestens 50" und nicht die genaue Zahl: Die gilt für den
    // jeweils neuesten Schemaschritt und steht dort auch (zuletzt
    // reisen_db_test.dart). Zwei Dateien, die beide die aktuelle Fassung
    // behaupten, widersprechen einander beim nächsten Schritt.
    final fassung = await db
        .customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version'))
        .getSingle();
    expect(fassung, greaterThanOrEqualTo(50));
  });
}

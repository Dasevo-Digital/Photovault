import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Verortete Lebensereignisse für die Familienkarte.
///
/// Der Punkt allein beantwortet keine Frage — er braucht die Person, zu
/// der er gehört. Deshalb kommt der Name aus derselben Abfrage und nicht
/// aus einem zweiten Zugriff je Marker.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (final (id, name) in [('p1', 'Anna Meier'), ('p2', 'Otto Meier')]) {
      await db.createPerson(PeopleCompanion.insert(id: id, name: name));
    }
  });
  tearDown(() => db.close());

  Future<void> ereignis(String id, String person,
          {String? ort, double? breite, double? laenge}) =>
      db.fuegeEreignisHinzu(LebensereignisseCompanion.insert(
        id: id,
        personId: person,
        art: 'hochzeit',
        ort: Value(ort),
        ortBreite: Value(breite),
        ortLaenge: Value(laenge),
      ));

  test('liefert nur verortete Ereignisse, mit dem Namen der Person',
      () async {
    await ereignis('e1', 'p1', ort: 'Berlin', breite: 52.5, laenge: 13.4);
    await ereignis('e2', 'p1', ort: 'Nirgendwo');

    final treffer = await db.verorteteEreignisseFuerPersonen(['p1']);
    expect(treffer, hasLength(1), reason: 'e2 hat keine Koordinate');
    expect(treffer.single.ereignis.id, 'e1');
    expect(treffer.single.personName, 'Anna Meier');
  });

  test('nimmt nur die genannten Personen', () async {
    await ereignis('e1', 'p1', ort: 'Berlin', breite: 52.5, laenge: 13.4);
    await ereignis('e2', 'p2', ort: 'Wien', breite: 48.2, laenge: 16.4);

    final nurAnna = await db.verorteteEreignisseFuerPersonen(['p1']);
    expect(nurAnna.map((t) => t.personName), ['Anna Meier']);

    final beide = await db.verorteteEreignisseFuerPersonen(['p1', 'p2']);
    expect(beide, hasLength(2));
  });

  test('eine leere Personenliste fragt nicht die ganze Tabelle ab', () async {
    // Der Fall, der am leichtesten falsch herauskommt: `isIn([])` waere
    // eine Bedingung, die nie zutrifft - aber ohne den Kurzschluss liefe
    // trotzdem eine Abfrage ueber die ganze Tabelle.
    await ereignis('e1', 'p1', ort: 'Berlin', breite: 52.5, laenge: 13.4);
    expect(await db.verorteteEreignisseFuerPersonen([]), isEmpty);
  });

  test('mehrere Ereignisse derselben Person kommen alle mit', () async {
    // Wer dreimal umgezogen ist, hat drei Punkte - nicht einen.
    await ereignis('e1', 'p1', ort: 'Berlin', breite: 52.5, laenge: 13.4);
    await ereignis('e2', 'p1', ort: 'Wien', breite: 48.2, laenge: 16.4);
    await ereignis('e3', 'p1', ort: 'Rom', breite: 41.9, laenge: 12.5);

    final treffer = await db.verorteteEreignisseFuerPersonen(['p1']);
    expect(treffer, hasLength(3));
    expect(treffer.map((t) => t.personName).toSet(), {'Anna Meier'});
  });
}

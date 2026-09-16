import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/aktivitaeten.dart';
import 'package:photo_vault/services/reisen.dart';

/// **Reisen zusammenführen.**
///
/// Die Erkennung trennt bei mehr als zwei Tagen ohne Aufnahme. Bei einem
/// Urlaub ist das richtig; ein zweimonatiger Auslandseinsatz zerfiel
/// dadurch in vier Vorschläge (25, 63, 89 und 20 Bilder), und zwei
/// weitere Häufungen fielen unter die Mindestzahl. Zusammenführen ist
/// die Entscheidung eines Menschen – dieser Test hält fest, dass dabei
/// nichts liegenbleibt.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    for (var i = 0; i < 6; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a$i',
            originalFileName: 'a$i.jpg',
            relativePath: 'originals/a$i.jpg',
            checksum: 'p$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2013, 5, 18 + i * 10, 12),
            importedAt: DateTime(2026),
          ));
    }
  });
  tearDown(() => db.close());

  Future<void> reise(String id, String name, List<String> ids,
          {String art = 'reise'}) =>
      db.reiseAnlegen(
        ReisenCompanion.insert(
          id: id,
          name: name,
          art: Value(art),
          von: DateTime(2013, 5, 18),
          bis: DateTime(2013, 5, 20),
          notiz: Value('Notiz $id'),
          angelegtAm: DateTime(2026),
        ),
        ids,
      );

  test('die Aufnahmen kommen mit, die Quelle verschwindet', () async {
    await reise('r1', 'Einsatz', ['a0', 'a1'], art: 'unternehmung');
    await reise('r2', 'Teil zwei', ['a2', 'a3']);
    await reise('r3', 'Teil drei', ['a4', 'a5']);

    await db.reisenZusammenfuehren('r1', ['r2', 'r3']);

    final uebrig = await db.alleReisen();
    expect(uebrig.map((r) => r.id), ['r1']);
    expect(uebrig.single.name, 'Einsatz', reason: 'das Ziel behält seinen Namen');
    expect(uebrig.single.art, 'unternehmung');
    expect(uebrig.single.notiz, 'Notiz r1');
    expect((await db.aufnahmenDerReise('r1')).map((a) => a.id).toSet(),
        {'a0', 'a1', 'a2', 'a3', 'a4', 'a5'});
  });

  test('der Zeitraum wächst auf die Aufnahmen', () async {
    await reise('r1', 'Einsatz', ['a0']);
    await reise('r2', 'Teil zwei', ['a5']);
    await db.reisenZusammenfuehren('r1', ['r2']);
    final r = (await db.alleReisen()).single;
    // a0 ist der 18.05., a5 der 68. Tag danach.
    expect(r.von, DateTime(2013, 5, 18, 12));
    expect(r.bis, DateTime(2013, 5, 18, 12).add(const Duration(days: 50)));
  });

  test('Aktivitäten und Spuren hängen danach am Ziel', () async {
    await reise('r1', 'Einsatz', ['a0']);
    await reise('r2', 'Teil zwei', ['a2']);
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Ausflug',
        art: Aktivitaetsart.ausflug.kennung,
        von: DateTime(2013, 5, 28),
        bis: DateTime(2013, 5, 28, 18),
        reiseId: const Value('r2'),
        angelegtAm: DateTime(2026),
      ),
      ['a2'],
    );
    await db.spurAnlegen(
      SpurenCompanion.insert(
        id: 's1',
        name: 'tour.gpx',
        quelle: '/tmp/tour.gpx',
        reiseId: const Value('r2'),
        punktzahl: 2,
        laengeKm: 1.0,
        angelegtAm: DateTime(2026),
      ),
      const [],
    );

    await db.reisenZusammenfuehren('r1', ['r2']);

    expect((await db.alleAktivitaeten()).single.reiseId, 'r1');
    expect((await db.alleSpuren()).single.reiseId, 'r1');
  });

  test('Tagesnotizen kommen mit – die des Ziels gewinnen', () async {
    await reise('r1', 'Einsatz', ['a0']);
    await reise('r2', 'Teil zwei', ['a2']);
    await db.setzeReisetagnotiz('r1', DateTime(2013, 5, 18), 'vom Ziel');
    await db.setzeReisetagnotiz('r2', DateTime(2013, 5, 18), 'von der Quelle');
    await db.setzeReisetagnotiz('r2', DateTime(2013, 5, 28), 'nur bei der Quelle');

    await db.reisenZusammenfuehren('r1', ['r2']);

    final notizen = await db.reisetagnotizenFuer('r1');
    expect(notizen[DateTime(2013, 5, 18)], 'vom Ziel',
        reason: 'zwei Sätze zu einem Tag zusammenzukleben ergäbe einen dritten');
    expect(notizen[DateTime(2013, 5, 28)], 'nur bei der Quelle');
    expect(await db.reisetagnotizenFuer('r2'), isEmpty);
  });

  test('eine Aufnahme in beiden Reisen steht danach einmal da', () async {
    await reise('r1', 'Einsatz', ['a0', 'a1']);
    await reise('r2', 'Teil zwei', ['a1', 'a2']);
    await db.reisenZusammenfuehren('r1', ['r2']);
    final ids = (await db.aufnahmenDerReise('r1')).map((a) => a.id).toList();
    expect(ids.toSet(), {'a0', 'a1', 'a2'});
    expect(ids, hasLength(3), reason: 'keine doppelte Zeile');
  });

  test('sich selbst zusammenzuführen tut nichts', () async {
    await reise('r1', 'Einsatz', ['a0']);
    await db.reisenZusammenfuehren('r1', ['r1']);
    expect(await db.alleReisen(), hasLength(1));
    expect(await db.aufnahmenDerReise('r1'), hasLength(1));
  });

  test('eine gelöschte Reise lässt ihre Aktivität nicht ins Leere zeigen',
      () async {
    await reise('r1', 'Einsatz', ['a0']);
    await db.aktivitaetAnlegen(
      AktivitaetenCompanion.insert(
        id: 'k1',
        name: 'Ausflug',
        art: Aktivitaetsart.ausflug.kennung,
        von: DateTime(2013, 5, 18),
        bis: DateTime(2013, 5, 18, 18),
        reiseId: const Value('r1'),
        angelegtAm: DateTime(2026),
      ),
      ['a0'],
    );
    await db.reiseLoeschen('r1');
    expect((await db.alleAktivitaeten()).single.reiseId, isNull,
        reason: 'die Aktivität überlebt, ihre Reise nicht');
  });

  test('die Vorgabeart ist Reise, und Unbekanntes fällt darauf zurück', () {
    expect(Reiseart.aus('unternehmung'), Reiseart.unternehmung);
    expect(Reiseart.aus('gibtesnicht'), Reiseart.reise);
    expect(reiseartVorgabe, Reiseart.reise);
  });
}

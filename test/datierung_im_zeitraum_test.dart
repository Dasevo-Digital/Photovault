import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/erinnerungsfilter.dart';
import 'package:kern/services/rueckblickseite.dart';

/// Ein datierter Scan gehört in das Jahr seiner Datierung, nicht in das
/// seines Dateidatums (#481) – im Jahresrückblick, bei den Personen des
/// Jahres, in den Zeiträumen von Reisen und Aktivitäten und in den
/// Zeiträumen, die von Rückblicken ausgenommen sind. So ordnet ihn auch
/// die Zeitleiste ein.
void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Beide im Mai 2026 eingescannt; „scan“ ist auf 1985 datiert,
    // „juli“ auf Juli 1985.
    for (final id in ['neu', 'scan', 'juli']) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: '$id.jpg',
              checksum: id,
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026, 5, 10, 12),
              importedAt: DateTime(2026, 5, 10),
            ),
          );
    }
    await db.setzeDatierung(['scan'], AufnahmeDatierung.jahr(1985));
    await db.setzeDatierung(['juli'], AufnahmeDatierung.monat(1985, 7));
    await db.fuehreAus(const PersonAnlegen('p', 'Person'));
    await db.insertFace(
      FacesCompanion.insert(
        id: 'f',
        assetId: 'scan',
        boxX: 0,
        boxY: 0,
        boxW: .2,
        boxH: .2,
        personId: const Value('p'),
      ),
    );
  });
  tearDown(() => db.close());

  test('„Dein Jahr“ zählt den Scan im Jahr seiner Datierung', () async {
    final heuer = await jahresinhalt(db, 2026);
    expect(heuer.zahlen.fotos, 1, reason: 'nur das ungescannte Foto');
    expect(heuer.zahlen.jeMonat[4], 1);
    expect(heuer.personen, isEmpty);

    final damals = await jahresinhalt(db, 1985);
    expect(damals.zahlen.fotos, 2);
    // Nur das Jahr bekannt: in keinem Monat. Der Juli steht im Juli.
    expect(damals.zahlen.jeMonat[0], 0);
    expect(damals.zahlen.jeMonat[6], 1);
    expect(damals.zahlen.jeMonat.reduce((a, b) => a + b), 1);
    expect([for (final p in damals.personen) p.person.id], ['p']);
  });

  test('Zeiträume von Reisen und Aktivitäten folgen der Datierung', () async {
    final mai = (von: DateTime(2026, 5, 1), bis: DateTime(2026, 5, 31));
    expect(
      [for (final a in await db.aufnahmenImZeitraum(mai.von, mai.bis)) a.id],
      ['neu'],
    );
    expect(await db.zahlImZeitraum(mai.von, mai.bis), 1);
    expect(
      [for (final z in await db.rasterzeilenImZeitraum(mai.von, mai.bis)) z.id],
      ['neu'],
    );

    final juli85 = (von: DateTime(1985, 7, 1), bis: DateTime(1985, 7, 31));
    expect(
      [
        for (final a in await db.aufnahmenImZeitraum(juli85.von, juli85.bis))
          a.id,
      ],
      ['juli'],
    );
    expect(
      [
        for (final z in await db.rasterzeilenImZeitraum(
          DateTime(1985),
          DateTime(1985, 12, 31),
        ))
          z.id,
      ],
      ['scan', 'juli'],
    );
  });

  test('ausgenommene Zeiträume der Rückblicke folgen der Datierung', () async {
    await db.setzeErinnerungsfilter(
      Erinnerungsfilter(zeitraeume: [(von: '2026-05-01', bis: '2026-05-31')]),
    );
    expect((await jahresinhalt(db, 2026)).zahlen.fotos, 0);
    expect((await jahresinhalt(db, 1985)).zahlen.fotos, 2);

    await db.setzeErinnerungsfilter(
      Erinnerungsfilter(zeitraeume: [(von: '1985-01-01', bis: '1985-06-30')]),
    );
    expect((await jahresinhalt(db, 2026)).zahlen.fotos, 1);
    final damals = await jahresinhalt(db, 1985);
    expect(damals.zahlen.fotos, 1, reason: 'der Juli liegt nicht darin');
    expect(damals.personen, isEmpty);
  });
}

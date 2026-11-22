import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// Ein Befehl wirkt auf dem Gerät, das ihn vorwegnimmt, und auf dem
/// Server, der ihn über JSON bekommt, gleich – auch mit Werten, die sonst
/// jede Kopie für sich zöge.
void main() {
  Befehl<Object?> ueberJson(Befehl<Object?> b) => Befehl.ausJson(
    (jsonDecode(jsonEncode(b.alsJson())) as Map).cast<String, Object?>(),
  );

  test('Duplikate zusammenführen: Papierkorb-Aktion und -Zeitpunkt gehen '
      'mit dem Befehl', () async {
    final hier = AppDatabase(NativeDatabase.memory());
    final dort = AppDatabase(NativeDatabase.memory());
    addTearDown(hier.close);
    addTearDown(dort.close);
    for (final db in [hier, dort]) {
      for (final id in ['a1', 'a2']) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime.utc(2026, 7, 1),
                importedAt: DateTime.utc(2026, 7, 2),
              ),
            );
      }
    }
    final befehl = DuplikateZusammenfuehren(
      behaltenId: 'a1',
      duplikatIds: const ['a2'],
      // Ein Zeitpunkt vor dem Anwenden, wie bei einem Befehl, der offline
      // gewartet hat.
      zeit: DateTime.utc(2026, 11, 20, 8, 30),
    );
    await hier.fuehreAus(befehl);
    await dort.fuehreAus(ueberJson(befehl));

    final a = (await hier.assetById('a2'))!;
    final b = (await dort.assetById('a2'))!;
    expect(a.isTrashed && b.isTrashed, isTrue);
    expect(a.papierkorbAktion, isNotNull);
    expect(b.papierkorbAktion, a.papierkorbAktion);
    expect(b.trashedAt, a.trashedAt);
    expect(
      a.trashedAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 20, 8, 30)),
      isTrue,
    );

    // Ein Befehl einer älteren Fassung (ohne die Werte) wirkt weiter.
    await dort.fuehreAus(
      Befehl.ausJson({
        'art': 'duplikateZusammenfuehren',
        'werte': {
          'behaltenId': 'a2',
          'duplikatIds': ['a1'],
          'beschreibungenVerbinden': true,
        },
      }),
    );
    expect((await dort.assetById('a1'))!.papierkorbAktion, isNotNull);
  });

  // Ein Zeitpunkt ohne Zeitzone liest der Server in seiner eigenen – läuft
  // er in UTC und das Gerät in Mitteleuropa, liegt er ein bis zwei Stunden
  // daneben. Beim Rückgängig einer Zuordnung blieben so die Rückmeldungen
  // am Server stehen und kamen mit dem Abgleich zurück.
  test('Zeitpunkte reisen mit Zeitzone', () {
    final ortszeit = DateTime(2026, 11, 22, 10, 15, 30);
    final werte = <String, Object?>{
      'rueckmeldungenSeit': ZuordnungZuruecknehmen(
        gesichter: const [(id: 'g1', personId: null, ignoriert: false)],
        personId: 'p1',
        personWarNeu: false,
        titelbildVorher: null,
        rueckmeldungenSeit: ortszeit,
        allgemeineSchwelle: 0.4,
      ).werte['rueckmeldungenSeit'],
      'angelegtAm': AlbumAnlegen('al1', 'Sommer', ortszeit).werte['angelegtAm'],
    };
    for (final MapEntry(:key, :value) in werte.entries) {
      final text = value! as String;
      expect(text, endsWith('Z'), reason: key);
      expect(DateTime.parse(text).isAtSameMomentAs(ortszeit), isTrue);
    }
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/abgleichsplan.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';

/// Der Abgleich zwischen Server und verbundener App (Issue #86, Stufe 2).
void main() {
  // Zwei Datenbanken je Prüfung sind hier die Absicht.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Abgleichsplan', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<List<String>> tabellen() async => [
      for (final z
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'asset_search_fts%'",
              )
              .get())
        z.read<String>('name'),
    ];

    Future<Set<String>> spalten(String tabelle) async => {
      for (final c
          in await db.customSelect('PRAGMA table_info("$tabelle")').get())
        c.read<String>('name'),
    };

    test(
      'jede Tabelle ist eingeordnet, und der Plan nennt nur, was es gibt',
      () async {
        final alle = await tabellen();
        for (final t in Abgleichsplan.nurLokal) {
          expect(alle, contains(t), reason: 'nurLokal nennt $t');
        }
        // Eine neue Tabelle wird abgeglichen, wenn niemand etwas sagt – das
        // ist hier die Absicht. Wer eine Tabelle nur für diesen Rechner
        // anlegt, trägt sie in Abgleichsplan.nurLokal ein.
        expect(alle.where(Abgleichsplan.abgeglichen), isNotEmpty);
      },
    );

    test(
      'in geteilten Tabellen ist jede Spalte einer Seite zugeordnet',
      () async {
        for (final t in Abgleichsplan.geteilteSpalten.keys) {
          final geteilt = Abgleichsplan.geteilteSpalten[t]!;
          final lokal = Abgleichsplan.lokaleSpalten[t]!;
          expect(geteilt.intersection(lokal), isEmpty, reason: t);
          expect(
            geteilt.union(lokal),
            await spalten(t),
            reason:
                'Neue Spalte in $t: gehört sie allen (geteilteSpalten) oder '
                'nur diesem Rechner (lokaleSpalten)?',
          );
        }
      },
    );
  });

  group('Protokoll', () {
    late AppDatabase server, geraet;
    late Protokoll ps, pg;

    setUp(() async {
      server = AppDatabase(NativeDatabase.memory());
      geraet = AppDatabase(NativeDatabase.memory());
      ps = Protokoll(server);
      pg = Protokoll(geraet);
      await ps.richteEin(mitschreiben: -1);
      await pg.richteEin(mitschreiben: 0);
    });
    tearDown(() async {
      await server.close();
      await geraet.close();
    });

    Future<void> aufnahme(AppDatabase db, String id) => db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2025),
            importedAt: DateTime(2026),
          ),
        );

    /// Holt alles seit [nach] über JSON und wendet es auf dem Gerät an.
    Future<int> gleicheAb(int nach) async {
      var stand = nach;
      while (true) {
        final s = await ps.seit(stand, anzahl: 3);
        final ueberDasNetz = [
          for (final z in s.zeilen)
            Zeilenstand.ausJson(
              (jsonDecode(jsonEncode(z.alsJson())) as Map)
                  .cast<String, Object?>(),
            ),
        ];
        await geraet.transaction(() => pg.wendeAn(ueberDasNetz));
        stand = s.bis;
        if (!s.mehr) return stand;
      }
    }

    test(
      'Änderungen kommen an – samt Bytes, Löschungen und Befehlen',
      () async {
        await aufnahme(server, 'a1');
        await aufnahme(server, 'a2');
        await server.fuehreAus(const BewertungSetzen(['a1'], 4));
        await server.fuehreAus(const SchlagwortAnheften(['a1', 'a2'], 'Hafen'));
        await server.saveEmbedding(
          'a1',
          Float32List.fromList(List.generate(8, (i) => i / 8)),
        );
        final stand = await gleicheAb(0);
        expect(stand, await ps.stand());

        final a1 = (await geraet.assetsByIds(['a1'])).single;
        expect(a1.rating, 4);
        expect(
          [for (final t in await geraet.tagsForAsset('a2')) t.name],
          ['Hafen'],
        );
        final roh = await geraet
            .customSelect('SELECT vector FROM image_embeddings')
            .getSingle();
        expect(roh.read<Uint8List>('vector'), isNotEmpty);
        expect(
          await geraet
              .customSelect('SELECT count(*) AS n FROM pv_aenderungen')
              .getSingle()
              .then((z) => z.read<int>('n')),
          0,
          reason: 'was der Abgleich schreibt, schreibt das Gerät nicht mit',
        );

        await server.fuehreAus(const SchlagwortAbnehmen(['a2'], 'Hafen'));
        await server.deleteAssetRows(['a2']);
        await gleicheAb(stand);
        expect(await geraet.assetsByIds(['a2']), isEmpty);
        expect(await geraet.tagsForAsset('a2'), isEmpty);
      },
    );

    test('in geteilten Tabellen bleibt, was diesem Rechner gehört', () async {
      await geraet.setThemeMode('dark');
      await server.setThemeMode('light');
      await server.fuehreAus(const GesichtsschwelleSetzen(0.5));
      await gleicheAb(0);
      final e = await geraet.select(geraet.appSettings).getSingle();
      expect(e.themeMode, 'dark');
      expect(e.faceSimilarityThreshold, 0.5);
    });

    test('nur Lokales wandert nicht', () async {
      await server.merkeAufgabenlauf('ordnen');
      await gleicheAb(0);
      expect(await geraet.select(geraet.aufgabenlaeufe).get(), isEmpty);
    });

    test(
      'nach einer Migration, die Tabellen neu anlegt, schreibt es weiter mit',
      () async {
        // Was eine Migration tut: Tabelle weg und neu – mit ihr die Trigger.
        await server.customStatement('DROP TABLE tags');
        await server.customStatement(
          'CREATE TABLE tags (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
        );
        await ps.richteEin(mitschreiben: -1);
        final vorher = await ps.stand();
        await server.ensureTag('Leuchtturm');
        expect(await ps.stand(), greaterThan(vorher));
      },
    );

    test('auf dem Gerät schreibt nur mit, wer den Schalter setzt', () async {
      await aufnahme(geraet, 'g1');
      expect(await pg.stand(), 0);
      await geraet.customStatement('UPDATE pv_schalter SET mitschreiben = 7');
      await geraet.fuehreAus(const FavoritSetzen(['g1'], true));
      final z = await geraet
          .customSelect(
            'SELECT tabelle, schluessel, ausgang FROM pv_aenderungen',
          )
          .get();
      expect(
        {
          for (final r in z)
            '${r.read<String>('tabelle')} ${r.read<String>('schluessel')} '
                '${r.read<int>('ausgang')}',
        },
        {'assets ["g1"] 7'},
      );
    });
  });
}

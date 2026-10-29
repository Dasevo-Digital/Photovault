import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/befehlsbasis.dart';
import 'package:kern/abgleich/grenzen.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';

class _Zaehler extends QueryInterceptor {
  int lesen = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    lesen++;
    return executor.runSelect(statement, args);
  }
}

void main() {
  test(
    'große Albumauswahl liest Zeilen in Batches und rollt vollständig zurück',
    () async {
      final zaehler = _Zaehler();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(zaehler));
      addTearDown(db.close);
      final ids = [for (var i = 0; i < 8000; i++) 'foto_$i'];
      await db.batch((b) {
        b.insert(
          db.albums,
          AlbumsCompanion.insert(
            id: 'album',
            name: 'Album',
            createdAt: DateTime(2026),
          ),
        );
        b.insertAll(db.assets, [
          for (final id in ids)
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: id,
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026),
              importedAt: DateTime(2026),
            ),
        ]);
      });
      final p = Protokoll(db);
      await p.richteEin(mitschreiben: 0);
      zaehler.lesen = 0;
      final basis = await Befehlsbasis.ermittle(p, AlbumFuellen('album', ids));
      expect(basis.length, 16000);
      // Einzellesen würde hier über 24000 Abfragen benötigen.
      expect(zaehler.lesen, lessThan(300));
      expect(
        utf8.encode(jsonEncode(basis.map((b) => b.alsJson()).toList())).length,
        lessThan(Abgleichsgrenzen.befehlBytes),
      );
      expect(await db.select(db.albumAssets).get(), isEmpty);
    },
  );
  test(
    'zu großer atomarer Befehl verändert weder Foto noch Warteschlange',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'foto',
          originalFileName: 'foto.jpg',
          relativePath: 'originals/foto.jpg',
          checksum: 'hash',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
        ),
      );
      final v = Serververbindung(Uri.parse('http://localhost/'), 'synthetisch');
      addTearDown(v.schliesse);
      final a = Abgleich(db, v);
      await a.richteEin();
      addTearDown(a.beende);
      await expectLater(
        db.fuehreAus(
          BeschreibungSetzen(['foto'], 'x' * Abgleichsgrenzen.befehlBytes),
        ),
        throwsFormatException,
      );
      expect((await db.assetById('foto'))!.description, isNull);
      expect(await db.customSelect('SELECT * FROM pv_ausgang').get(), isEmpty);
    },
  );
  test(
    'Schutzzeilen zählen zur gemeinsamen Obergrenze eines atomaren Befehls',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ids = [for (var i = 0; i < 25001; i++) 'grenze_$i'];
      await db.batch((b) {
        b.insert(
          db.albums,
          AlbumsCompanion.insert(
            id: 'album',
            name: 'Album',
            createdAt: DateTime(2026),
          ),
        );
        b.insertAll(db.assets, [
          for (final id in ids)
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: id,
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026),
              importedAt: DateTime(2026),
            ),
        ]);
      });
      final p = Protokoll(db);
      await p.richteEin(mitschreiben: 0);
      await expectLater(
        Befehlsbasis.ermittle(p, AlbumFuellen('album', ids)),
        throwsFormatException,
      );
      expect(await db.select(db.albumAssets).get(), isEmpty);
    },
  );
  test(
    'mehrere große Befehle werden in vollständig gültige HTTP-Stapel aufgeteilt',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final stapel = <int>[];
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/zustand')) {
          return http.Response(
            jsonEncode({
              'funktionen': {'konfliktpruefung': 1},
            }),
            200,
          );
        }
        expect(r.url.path.endsWith('/befehle'), isTrue);
        stapel.add(r.bodyBytes.length);
        final befehle = (jsonDecode(r.body) as Map)['befehle'] as List;
        return http.Response(
          jsonEncode({
            'stand': 0,
            'ergebnisse': [
              for (final b in befehle) {'kennung': b['kennung'], 'ok': true},
            ],
          }),
          200,
        );
      });
      final v = Serververbindung(
        Uri.parse('http://localhost/'),
        'synthetisch',
        client: client,
      );
      addTearDown(v.schliesse);
      final a = Abgleich(db, v, fallschluessel: SecretKey(List.filled(32, 7)));
      await a.richteEin();
      addTearDown(a.beende);
      for (final id in ['eins', 'zwei']) {
        await a.protokoll.frei(
          () => db.insertAsset(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: id,
              type: 'IMAGE',
              fileCreatedAt: DateTime(2026),
              importedAt: DateTime(2026),
            ),
          ),
        );
        await db.fuehreAus(BeschreibungSetzen([id], 'x' * (4 * 1024 * 1024)));
      }
      await a.sende();
      expect(stapel, hasLength(2));
      expect(stapel.every((n) => n <= Abgleichsgrenzen.stapelBytes), isTrue);
      expect(
        await db
            .customSelect('SELECT * FROM pv_ausgang WHERE bestaetigt IS NULL')
            .get(),
        isEmpty,
      );
    },
  );
}

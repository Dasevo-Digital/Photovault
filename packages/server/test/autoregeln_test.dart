import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:kern/db/database.dart';
import 'package:kern/services/regel_anwenden.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Regeln vom Browser aus: anlegen über die Befehle, auf vorhandene Fotos
/// anwenden, mit Probelauf. Beim Import griffen sie schon vorher.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto erika;
  late AppDatabase db;
  late Handler api;
  late String token;

  Future<void> foto(
    String id, {
    double? breite,
    double? laenge,
    String? name,
    bool papierkorb = false,
    bool gesperrt = false,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: name ?? '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'p-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 6, 1),
          importedAt: DateTime(2026, 6, 1),
          latitude: Value(breite),
          longitude: Value(laenge),
          isTrashed: Value(papierkorb),
          isLocked: Value(gesperrt),
        ),
      );

  Future<Response> frag(String m, String pfad, [Object? j]) async => api(
    Request(
      m,
      Uri.parse('http://server/api/v1/$pfad'),
      headers: {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      },
      body: j == null ? null : jsonEncode(j),
    ),
  );

  Future<Map<String, Object?>> json(Response r) async {
    expect(r.statusCode, lessThan(300), reason: await r.readAsString());
    return {};
  }

  Future<Map<String, Object?>> liesJson(String m, String pfad) async {
    final r = await frag(m, pfad);
    final text = await r.readAsString();
    expect(r.statusCode, 200, reason: text);
    return (jsonDecode(text) as Map).cast<String, Object?>();
  }

  Future<AutomationRuleData> regel(
    String id,
    String ausloeser, {
    double? breite,
    double? laenge,
    double? km,
    String? begriff,
    String? album,
    bool favorit = false,
  }) async {
    await db.fuehreAus(
      RegelSpeichern(
        AutomationRulesCompanion.insert(
          id: id,
          name: 'Regel $id',
          triggerType: ausloeser,
          regionCenterLat: Value(breite),
          regionCenterLon: Value(laenge),
          regionRadiusKm: Value(km),
          aiTagTerm: Value(begriff),
          targetAlbumId: Value(album),
          autoFavorite: Value(favorit),
        ),
      ),
    );
    return (await db.allAutomationRules()).singleWhere((r) => r.id == id);
  }

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_autoregeln_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 9)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
    db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    // Rom und Kiel.
    await foto('rom1', breite: 41.9, laenge: 12.5);
    await foto('rom2', breite: 41.91, laenge: 12.49);
    await foto('kiel', breite: 54.3, laenge: 10.1);
    await foto('rom-weg', breite: 41.9, laenge: 12.5, papierkorb: true);
    await foto('rom-gesperrt', breite: 41.9, laenge: 12.5, gesperrt: true);
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('der Probelauf zählt und ändert nichts', () async {
    await db.fuehreAus(AlbumAnlegen('al', 'Italien', DateTime(2026)));
    await regel(
      'r',
      'location',
      breite: 41.9,
      laenge: 12.5,
      km: 30,
      album: 'al',
    );
    final d = await liesJson('POST', 'regeln/r/anwenden?probe=1');
    expect(d['treffer'], 2, reason: 'ohne Papierkorb und Gesperrtes');
    expect(await db.assetsInAlbumOnce('al'), isEmpty);
  });

  test(
    'Anwenden legt ins Album, macht zu Favoriten, vergibt Schlagwörter',
    () async {
      await db.fuehreAus(AlbumAnlegen('al', 'Italien', DateTime(2026)));
      await db.fuehreAus(const SchlagwortAnheften(['kiel'], 'Reise'));
      final tag = (await db.alleTags()).single;
      await regel(
        'r',
        'location',
        breite: 41.9,
        laenge: 12.5,
        km: 30,
        album: 'al',
        favorit: true,
      );
      await db.fuehreAus(RegelSchlagwoerterSetzen('r', [tag.id]));

      final d = await liesJson('POST', 'regeln/r/anwenden');
      expect(d['treffer'], 2);
      expect((await db.assetsInAlbumOnce('al')).map((a) => a.id).toSet(), {
        'rom1',
        'rom2',
      });
      expect((await db.assetById('rom1'))!.isFavorite, isTrue);
      expect((await db.assetById('kiel'))!.isFavorite, isFalse);
      expect((await db.allTagNamesByAssetId())['rom2'], ['Reise']);
    },
  );

  test('zweimal anwenden schadet nicht', () async {
    await db.fuehreAus(AlbumAnlegen('al', 'Italien', DateTime(2026)));
    await regel('r', 'dateiname', begriff: 'rom', album: 'al');
    await liesJson('POST', 'regeln/r/anwenden');
    await liesJson('POST', 'regeln/r/anwenden');
    expect(await db.assetsInAlbumOnce('al'), hasLength(2));
  });

  test('ein gelöschtes Album bricht die übrigen Aktionen nicht ab', () async {
    final r = await regel(
      'r',
      'dateiname',
      begriff: 'kiel',
      album: 'weg',
      favorit: true,
    );
    expect(await regelAnwenden(db, r), 1);
    expect((await db.assetById('kiel'))!.isFavorite, isTrue);
  });

  test('KI-Schlagworte zählen, von Hand vergebene nicht', () async {
    await db.fuehreAus(
      const SchlagwortAnheften(['rom1'], 'Strand', quelle: Tagquelle.ki),
    );
    await db.fuehreAus(const SchlagwortAnheften(['rom2'], 'Strand'));
    final r = await regel('r', 'aiTag', begriff: 'Strand', favorit: true);
    expect(await regelTreffer(db, r), ['rom1']);
  });

  test('eine unbekannte Regel', () async {
    expect((await frag('POST', 'regeln/nix/anwenden')).statusCode, 404);
  });

  test('anlegen über denselben Weg wie der Browser, dann lesen', () async {
    await db.fuehreAus(AlbumAnlegen('al', 'Italien', DateTime(2026)));
    await db.fuehreAus(const SchlagwortAnheften(['kiel'], 'Reise'));
    final tag = (await db.alleTags()).single;
    await json(
      await frag('POST', 'befehle', {
        'art': 'regelSpeichern',
        'werte': {
          'regel': {
            'id': 'web1',
            'name': 'Sommer',
            'trigger_type': 'dateRange',
            'region_center_lat': null,
            'region_center_lon': null,
            'region_radius_km': null,
            'ai_tag_term': null,
            'date_from': '2026-05-01T00:00:00',
            'date_to': '2026-06-30T23:59:59',
            'target_album_id': 'al',
            'auto_favorite': true,
          },
        },
      }),
    );
    await json(
      await frag('POST', 'befehle', {
        'art': 'regelSchlagwoerterSetzen',
        'werte': {
          'regelId': 'web1',
          'schlagwortIds': [tag.id],
        },
      }),
    );
    final d = await liesJson('GET', 'regeln');
    final r = (d['regeln']! as List).single as Map;
    expect(r['name'], 'Sommer');
    expect(r['ausloeser'], 'dateRange');
    expect(r['album'], 'al');
    expect(r['favorit'], isTrue);
    expect(r['schlagwoerter'], [tag.id]);
    expect(((d['alben']! as List).single as Map)['name'], 'Italien');

    final t = await liesJson('POST', 'regeln/web1/anwenden?probe=1');
    expect(t['treffer'], 3);

    await json(
      await frag('POST', 'befehle', {
        'art': 'regelLoeschen',
        'werte': {'regelId': 'web1'},
      }),
    );
    expect((await liesJson('GET', 'regeln'))['regeln'], isEmpty);
  });

  test('jede Bibliothek hat ihre eigenen Regeln', () async {
    await regel('r', 'dateiname', begriff: 'rom');
    final max = await konten.legeAn('max', 'noch ein passwort');
    token = konten.meldeAn(max.id, 'Rechner', 'y').token;
    expect((await liesJson('GET', 'regeln'))['regeln'], isEmpty);
    expect((await frag('POST', 'regeln/r/anwenden')).statusCode, 404);
  });
}

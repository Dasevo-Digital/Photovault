import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_mobil/partnerfotos.dart';
import 'package:teilen_ui/geteilte_alben.dart';

/// Fotos von Partnern in der eigenen Zeitleiste (#299).
void main() {
  http.Response json(Object? d) => http.Response(
    jsonEncode(d),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> zeile(String id, String wann) => {
    'id': id,
    'art': 'bild',
    'name': '$id.jpg',
    'aufgenommen': wann,
    'breite': 300,
    'hoehe': 200,
  };

  test(
    'nur Partner mit „in der Zeitleiste“, alle Seiten, neueste zuerst',
    () async {
      final gefragt = <String>[];
      final client = MockClient((r) async {
        gefragt.add('${r.url.path}?${r.url.query}');
        if (r.url.path == '/api/v1/partner') {
          return json({
            'meine': [],
            'mitMir': [
              {'konto': 'erika', 'name': 'Erika', 'inZeitleiste': true},
              {'konto': 'moritz', 'name': 'Moritz', 'inZeitleiste': false},
            ],
          });
        }
        if (r.url.path == '/api/v1/partner/von/erika/aufnahmen') {
          return r.url.queryParameters['nach'] == null
              ? json({
                  'aufnahmen': [zeile('b', '2024-05-01T12:00:00.000')],
                  'weiter': '1~b',
                })
              : json({
                  'aufnahmen': [zeile('a', '2024-07-01T12:00:00.000')],
                  'weiter': null,
                });
        }
        return http.Response('', 404);
      });
      final v = Serververbindung(
        Uri.parse('https://fotos.example/'),
        't',
        client: client,
      );
      final fotos = await holePartnerfotos(v);
      expect([for (final f in fotos) f.aufnahme.id], ['a', 'b']);
      expect(fotos.first.kennung, 'partner:erika:a');
      expect(fotos.first.name, 'Erika');
      expect(fotos.first.zeile.widthPx, 300);
      expect(gefragt.where((g) => g.contains('moritz')), isEmpty);
    },
  );

  test('ein Server ohne Partnerfreigabe: nichts', () async {
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await holePartnerfotos(v), isEmpty);
  });

  test('zwischen die eigenen Zeilen nach Datum gereiht', () {
    Rasterzeile eigen(String id, DateTime wann) => Rasterzeile(
      id: id,
      type: 'IMAGE',
      originalFileName: '$id.jpg',
      relativePath: 'x/$id.jpg',
      thumbnailRelativePath: null,
      fileCreatedAt: wann,
      durationSeconds: null,
      isFavorite: false,
      isStackCover: false,
      stackId: null,
      stackSize: null,
      linkedAssetId: null,
      rating: 0,
      colorLabel: null,
      widthPx: null,
      heightPx: null,
      latitude: null,
      longitude: null,
      cameraMake: null,
      isLocked: false,
    );
    final erika = GeteiltesAlbum.partner({'konto': 'erika', 'name': 'Erika'});
    final partner = [
      for (final (id, wann) in const [
        ('p2', '2024-06-01T00:00:00.000'),
        ('p1', '2024-02-01T00:00:00.000'),
      ])
        Partnerfoto.aus(erika, zeile(id, wann)),
    ];
    final m = mischeMitPartnern([
      eigen('e2', DateTime(2024, 7, 1)),
      eigen('e1', DateTime(2024, 3, 1)),
    ], partner);
    expect(
      [for (final z in m.zeilen) z.id],
      ['e2', 'partner:erika:p2', 'e1', 'partner:erika:p1'],
    );
    expect(m.partner.keys, contains('partner:erika:p1'));
  });
}

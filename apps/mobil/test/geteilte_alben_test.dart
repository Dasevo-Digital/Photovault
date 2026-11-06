import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:teilen_ui/geteilte_alben.dart';

/// Alben zwischen Konten teilen (#105) auf dem Telefon – dieselben Wege
/// wie im Browser, gegen einen gestellten Server.
void main() {
  http.Response json(Object? d, [int status = 200]) => http.Response(
    jsonEncode(d),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Widget app(Widget kind) => MaterialApp(
    locale: const Locale('de'),
    localizationsDelegates: AppTexte.localizationsDelegates,
    supportedLocales: AppTexte.supportedLocales,
    home: kind,
  );

  const album = GeteiltesAlbum(
    id: 't1',
    name: 'Urlaub',
    besitzer: 'erika',
    beitragen: true,
    anzahl: 1,
  );

  testWidgets('„Geteilt mit mir“ steht unter den Alben, mit Besitzer', (
    tester,
  ) async {
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/geteilt') {
        return json({
          'alben': [
            {
              'id': 't1',
              'name': 'Urlaub',
              'besitzer': 'erika',
              'beitragen': false,
              'anzahl': 3,
              'titelbild': 'a1',
            },
          ],
        });
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CustomScrollView(
            slivers: [
              GeteilteAlben(
                zugang: Teilungszugang(verbindung: v),
                raster: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.82,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Geteilt mit mir'), findsOneWidget);
    expect(find.text('Urlaub'), findsOneWidget);
    expect(find.text('von erika'), findsOneWidget);
  });

  testWidgets('ein Server ohne geteilte Alben: kein Abschnitt', (tester) async {
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((_) async => http.Response('', 404)),
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CustomScrollView(
            slivers: [
              GeteilteAlben(
                zugang: Teilungszugang(verbindung: v),
                raster: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Geteilt mit mir'), findsNothing);
  });

  testWidgets('beitragen: die Datei geht ins Album, danach neu geladen', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_geteilt_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final foto = File('${ordner.path}/IMG_1.HEIC')
      ..writeAsBytesSync(List.filled(64, 7));
    final eingang = <Uri>[];
    var gesendet = 0;
    var aufnahmen = <Map<String, Object?>>[
      {
        'id': 'a1',
        'art': 'bild',
        'name': 'strand.jpg',
        'aufgenommen': '2026-08-01T10:00:00Z',
      },
    ];
    final client = MockClient.streaming((r, koerper) async {
      if (r.method == 'POST' && r.url.path == '/api/v1/geteilt/t1/beitrag') {
        eingang.add(r.url);
        gesendet = (await koerper.toBytes()).length;
        aufnahmen = [
          ...aufnahmen,
          {
            'id': 'a2',
            'art': 'bild',
            'name': 'IMG_1.HEIC',
            'aufgenommen': '2026-08-02T10:00:00Z',
            'von': 'max',
            'eigene': true,
          },
        ];
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"aufnahme":"a2","ausgang":"imported"}')),
          201,
        );
      }
      if (r.url.path == '/api/v1/geteilt/t1') {
        final a = json({
          'album': {
            'id': 't1',
            'name': 'Urlaub',
            'besitzer': 'erika',
            'beitragen': true,
          },
          'aufnahmen': aufnahmen,
        });
        return http.StreamedResponse(
          Stream.value(a.bodyBytes),
          200,
          headers: a.headers,
        );
      }
      return http.StreamedResponse(const Stream.empty(), 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        GeteiltesAlbumSeite(
          album: album,
          zugang: Teilungszugang(
            verbindung: v,
            waehle: (_) async => [
              Beitragsdatei(
                name: 'IMG_1.HEIC',
                geaendert: DateTime.utc(2026, 8, 2, 10),
                datei: () async => foto,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Geteilt von erika'), findsOneWidget);
    expect(find.byType(GestureDetector), findsWidgets);

    await tester.tap(find.byTooltip('Fotos hinzufügen'));
    // Die Datei wird wirklich gelesen: echte Zeit und Testzeit im Wechsel.
    for (var i = 0; i < 30 && gesendet == 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(eingang.single.queryParameters['name'], 'IMG_1.HEIC');
    expect(
      eingang.single.queryParameters['geaendert'],
      '${DateTime.utc(2026, 8, 2, 10).millisecondsSinceEpoch}',
    );
    expect(gesendet, 64);
    expect(find.text('1 Aufnahme hinzugefügt'), findsOneWidget);
  });

  testWidgets('nur ansehen: kein Knopf zum Hinzufügen', (tester) async {
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/geteilt/t1') {
        return json({
          'album': {
            'id': 't1',
            'name': 'Urlaub',
            'besitzer': 'erika',
            'beitragen': false,
          },
          'aufnahmen': [],
        });
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        GeteiltesAlbumSeite(
          zugang: Teilungszugang(verbindung: v, waehle: (_) async => []),
          album: album,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fotos hinzufügen'), findsNothing);
    expect(find.text('Das Album ist leer.'), findsOneWidget);
  });

  testWidgets('mit Konten teilen: wählen, teilen, Recht ändern', (
    tester,
  ) async {
    final geteilt = <Map<String, Object?>>[];
    final rufe = <String>[];
    final client = MockClient((r) async {
      rufe.add('${r.method} ${r.url.path}');
      if (r.url.path == '/api/v1/konten/andere') {
        return json({
          'konten': [
            {'id': 'k-max', 'name': 'max'},
          ],
        });
      }
      if (r.url.path == '/api/v1/alben/urlaub/teilungen') {
        return json({'teilungen': geteilt});
      }
      if (r.method == 'PUT' &&
          r.url.path == '/api/v1/alben/urlaub/teilungen/k-max') {
        final b = (jsonDecode(r.body) as Map)['beitragen'] == true;
        geteilt
          ..clear()
          ..add({'id': 's1', 'konto': 'k-max', 'name': 'max', 'beitragen': b});
        return json(geteilt.single);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => mitKontenTeilen(
                context,
                v,
                albumId: 'urlaub',
                titel: 'Urlaub',
              ),
              child: const Text('teilen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('„Urlaub“ mit Konten teilen'), findsOneWidget);
    expect(find.text('Mit niemandem geteilt.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(rufe, contains('PUT /api/v1/alben/urlaub/teilungen/k-max'));
    expect(geteilt.single['beitragen'], false);
    expect(find.text('max'), findsOneWidget);
    expect(
      find.text('Auf diesem Server gibt es kein weiteres Konto.'),
      findsNothing,
    );

    // Das Recht in der Zeile umstellen.
    await tester.tap(find.text('Ansehen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beitragen').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(geteilt.single['beitragen'], true);
  });

  testWidgets('den eigenen Beitrag entfernen, nur ihn (#290)', (tester) async {
    final geloescht = <String>[];
    final client = MockClient((r) async {
      if (r.method == 'DELETE') {
        geloescht.add(r.url.path);
        return json({'papierkorb': true});
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    final aufnahmen = [
      GeteilteAufnahme(
        id: 'fremd',
        video: false,
        name: 'strand.jpg',
        aufgenommen: DateTime(2026, 8),
      ),
      GeteilteAufnahme(
        id: 'mein',
        video: false,
        name: 'see.jpg',
        aufgenommen: DateTime(2026, 8),
        von: 'max',
        eigene: true,
      ),
    ];
    bool? zurueck;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                zurueck = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => GeteilterBetrachter(
                      zugang: Teilungszugang(verbindung: v),
                      album: album,
                      aufnahmen: aufnahmen,
                      start: 0,
                    ),
                  ),
                ),
            child: const Text('auf'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aus dem Album entfernen'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Beigetragen von max'), findsOneWidget);
    await tester.tap(find.byTooltip('Aus dem Album entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(TextButton, 'Aus dem Album entfernen'),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(geloescht, ['/api/v1/geteilt/t1/aufnahmen/mein']);
    expect(zurueck, isTrue, reason: 'das Album lädt danach neu');
  });

  testWidgets('Bilder bleiben auf dem Telefon, Fremdes geht (#291)', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_geteilt_ablage_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    // Von einem Album, das nicht mehr geteilt ist.
    Directory('${ordner.path}/weg').createSync();
    final png = img.encodePng(img.Image(width: 4, height: 4));
    var bilder = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/geteilt') {
        return json({
          'alben': [
            {
              'id': 't1',
              'name': 'Urlaub',
              'besitzer': 'erika',
              'anzahl': 1,
              'titelbild': 'a1',
              'titelstand': 's9',
            },
          ],
        });
      }
      if (r.url.path.endsWith('/miniatur')) {
        bilder++;
        return http.Response.bytes(png, 200);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    Widget liste() => app(
      Scaffold(
        body: CustomScrollView(
          slivers: [
            GeteilteAlben(
              zugang: Teilungszugang(verbindung: v, ablage: ordner),
              raster: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.82,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(liste());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    final abgelegt = File('${ordner.path}/t1/a1.miniatur.s9');
    expect(abgelegt.existsSync(), isTrue);
    expect(Directory('${ordner.path}/weg').existsSync(), isFalse);
    expect(bilder, 1);

    // Ein neuer Blick: aus der Ablage, nicht vom Server.
    imageCache.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(liste());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    expect(bilder, 1);
  });

  testWidgets(
    'neue Beiträge in eigenen Alben: zeigen, öffnen, gesehen (#295)',
    (tester) async {
      final rufe = <String>[];
      var gesehen = false;
      final client = MockClient((r) async {
        rufe.add('${r.method} ${r.url.path}');
        if (r.url.path == '/api/v1/kontobeitraege') {
          return json({
            'alben': gesehen
                ? []
                : [
                    {
                      'id': 'urlaub',
                      'name': 'Urlaub',
                      'anzahl': 2,
                      'von': ['max', 'moritz'],
                    },
                  ],
          });
        }
        if (r.method == 'POST' && r.url.path.endsWith('/gesehen')) {
          gesehen = true;
          return http.Response('', 204);
        }
        return http.Response('', 404);
      });
      final v = Serververbindung(
        Uri.parse('https://fotos.example/'),
        't',
        client: client,
      );
      String? geoeffnet;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: CustomScrollView(
              slivers: [
                NeueBeitraege(
                  verbindung: v,
                  oeffne: (id, name) async => geoeffnet = id,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Neu in deinen geteilten Alben'), findsOneWidget);
      expect(find.text('„Urlaub“: 2 neue Aufnahmen'), findsOneWidget);
      expect(find.text('von max, moritz'), findsOneWidget);

      await tester.tap(find.text('„Urlaub“: 2 neue Aufnahmen'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(
        rufe,
        contains('POST /api/v1/alben/urlaub/kontobeitraege/gesehen'),
      );
      expect(geoeffnet, 'urlaub');
      expect(find.text('Neu in deinen geteilten Alben'), findsNothing);
    },
  );

  testWidgets('Partnerfreigabe: Karte, blätternde Seite, freigeben (#293)', (
    tester,
  ) async {
    final abrufe = <Uri>[];
    var freigegeben = <String>[];
    Map<String, Object?> zeile(int i) => {
      'id': 'a$i',
      'art': 'bild',
      'name': 'IMG_$i.JPG',
      'aufgenommen': '2026-08-01T10:00:00Z',
    };
    final client = MockClient((r) async {
      abrufe.add(r.url);
      switch (r.url.path) {
        case '/api/v1/geteilt':
          return json({'alben': []});
        case '/api/v1/partner':
          return json({
            'meine': [
              for (final k in freigegeben) {'konto': k, 'name': 'max'},
            ],
            'mitMir': [
              {'konto': 'k-erika', 'name': 'erika', 'anzahl': 400},
            ],
          });
        case '/api/v1/konten/andere':
          return json({
            'konten': [
              {'id': 'k-max', 'name': 'max'},
            ],
          });
        case '/api/v1/partner/von/k-erika/aufnahmen':
          final weiter = r.url.queryParameters['nach'];
          return json({
            'name': 'erika',
            'aufnahmen': [
              for (var i = 0; i < (weiter == null ? 300 : 100); i++)
                zeile(weiter == null ? i : 300 + i),
            ],
            'weiter': weiter == null ? 'seite2' : null,
          });
      }
      if (r.method == 'PUT' && r.url.path == '/api/v1/partner/k-max') {
        freigegeben = ['k-max'];
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: CustomScrollView(
            slivers: [
              GeteilteAlben(
                zugang: Teilungszugang(verbindung: v),
                raster: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.82,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bibliothek von erika'), findsOneWidget);
    expect(find.text('Ganze Bibliothek'), findsOneWidget);

    await tester.tap(find.text('Bibliothek von erika'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    // Ans Ende des Rasters: die nächste Seite kommt nach.
    await tester.drag(find.byType(GridView), const Offset(0, -20000));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final seiten = [
      for (final u in abrufe)
        if (u.path == '/api/v1/partner/von/k-erika/aufnahmen')
          u.queryParameters['nach'],
    ];
    expect(seiten, [null, 'seite2']);
  });

  testWidgets('Bibliothek teilen: ein Konto wählen und freigeben (#293)', (
    tester,
  ) async {
    final rufe = <String>[];
    var freigegeben = false;
    final client = MockClient((r) async {
      rufe.add('${r.method} ${r.url.path}');
      if (r.url.path == '/api/v1/partner') {
        return json({
          'meine': freigegeben
              ? [
                  {'konto': 'k-max', 'name': 'max'},
                ]
              : [],
          'mitMir': [],
        });
      }
      if (r.url.path == '/api/v1/konten/andere') {
        return json({
          'konten': [
            {'id': 'k-max', 'name': 'max'},
          ],
        });
      }
      if (r.method == 'PUT' && r.url.path == '/api/v1/partner/k-max') {
        freigegeben = true;
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => bibliothekTeilen(context, v),
              child: const Text('teilen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mit niemandem geteilt.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(rufe, contains('PUT /api/v1/partner/k-max'));
    expect(find.text('max'), findsOneWidget);
  });

  testWidgets('Gefällt mir und Kommentare im Betrachter (#297)', (
    tester,
  ) async {
    final anfragen = <String>[];
    var ich = false;
    final kommentare = <Map<String, Object?>>[
      {
        'id': 'k1',
        'aufnahme': 'a1',
        'name': 'erika',
        'text': 'Schöner Strand',
        'angelegt': '2026-11-01T10:00:00Z',
        'eigener': false,
        'loeschbar': false,
      },
    ];
    final client = MockClient((r) async {
      anfragen.add('${r.method} ${r.url.path}');
      if (r.url.path == '/api/v1/geteilt/t1/aktivitaet') {
        return json({
          'kommentare': kommentare,
          'gefaellt': {
            'a1': {
              'anzahl': ich ? 2 : 1,
              'ich': ich,
              'namen': ['erika', if (ich) 'max'],
            },
          },
        });
      }
      if (r.url.path == '/api/v1/geteilt/t1/gefaellt/a1') {
        ich = r.method == 'PUT';
        return http.Response('', 204);
      }
      if (r.url.path == '/api/v1/geteilt/t1/kommentare' && r.method == 'POST') {
        final k = (jsonDecode(r.body) as Map).cast<String, Object?>();
        kommentare.add({
          'id': 'k2',
          'aufnahme': k['aufnahme'],
          'name': 'max',
          'text': k['text'],
          'angelegt': '2026-11-02T10:00:00Z',
          'eigener': true,
          'loeschbar': true,
        });
        return json(kommentare.last, 201);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        GeteilterBetrachter(
          zugang: Teilungszugang(verbindung: v),
          album: album,
          aufnahmen: [
            GeteilteAufnahme(
              id: 'a1',
              video: false,
              name: 'strand.jpg',
              aufgenommen: DateTime(2026, 8),
            ),
          ],
          start: 0,
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
    expect(find.text('1'), findsWidgets, reason: 'einem gefällt es schon');

    await tester.tap(find.byIcon(Icons.thumb_up_outlined));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(anfragen, contains('PUT /api/v1/geteilt/t1/gefaellt/a1'));
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);

    // Die Kommentare zu diesem Foto, und ein neuer dazu.
    await tester.tap(find.byTooltip('Kommentare'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Schöner Strand'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Finde ich auch');
    await tester.tap(find.byTooltip('Senden'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(anfragen, contains('POST /api/v1/geteilt/t1/kommentare'));
    expect(find.text('Finde ich auch'), findsOneWidget);
    expect(kommentare.last['aufnahme'], 'a1', reason: 'zu diesem Foto');
  });

  testWidgets('beim Besitzer nur, wenn das Album geteilt ist (#297)', (
    tester,
  ) async {
    var geteilt = false;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/alben/urlaub/aktivitaet') {
        return json({'kommentare': <Object>[], 'gefaellt': <String, Object>{}});
      }
      if (r.url.path == '/api/v1/alben/urlaub/teilungen') {
        return json({
          'teilungen': [
            if (geteilt) {'id': 't1', 'konto': 'm', 'name': 'max'},
          ],
        });
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    Future<void> zeige() async {
      await tester.pumpWidget(
        app(
          Scaffold(
            appBar: AppBar(
              actions: [
                Kommentarknopf(
                  key: UniqueKey(),
                  ort: Aktivitaetsort.besitzer(v, 'urlaub'),
                  nurWennGeteilt: true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await zeige();
    expect(find.byTooltip('Kommentare'), findsNothing);
    geteilt = true;
    await zeige();
    expect(find.byTooltip('Kommentare'), findsOneWidget);
  });
  testWidgets('Automatisch füllen: Personen wählen, speichern (#298)', (
    tester,
  ) async {
    Map<String, Object?>? regel;
    Object? gesendet;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/alben/kinder/regel' && r.method == 'GET') {
        return json({'regel': regel});
      }
      if (r.url.path == '/api/v1/alben/kinder/regel' && r.method == 'PUT') {
        gesendet = jsonDecode(r.body);
        regel = {
          'personen': [
            {'id': 'anna', 'name': 'Anna'},
          ],
          'fehlend': 0,
          'alle': false,
        };
        return json({'regel': regel, 'dazu': 2});
      }
      if (r.url.path == '/api/v1/personen') {
        return json({
          'personen': [
            {'id': 'anna', 'name': 'Anna', 'anzahl': 3},
            {'id': 'ben', 'name': 'Ben', 'anzahl': 2},
            {'id': 'leer', 'name': '', 'anzahl': 9},
          ],
        });
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          appBar: AppBar(
            actions: [
              Albumregelknopf(
                verbindung: v,
                albumId: 'kinder',
                titel: 'Kinder',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Automatisch füllen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('„Kinder“ automatisch füllen'), findsOneWidget);
    // Personen ohne Namen stehen nicht zur Wahl.
    expect(find.byType(CheckboxListTile), findsNWidgets(2));

    // Ohne Person kein Speichern.
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(find.text('Wähle mindestens eine Person.'), findsOneWidget);
    expect(gesendet, isNull);

    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(gesendet, {
      'personen': ['anna'],
      'alle': false,
      'ab': null,
    });
    expect(find.text('2 Aufnahmen dazugelegt'), findsOneWidget);
    expect(find.byTooltip('Automatisch füllen: mit Anna'), findsOneWidget);
  });

  testWidgets('Bibliothek teilen: einschränken auf Personen (#299)', (
    tester,
  ) async {
    Object? gesendet;
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/partner') {
        return json({
          'meine': [
            {
              'konto': 'k-max',
              'name': 'max',
              if (gesendet != null)
                'personen': [
                  {'id': 'ben', 'name': 'Ben'},
                ],
            },
          ],
          'mitMir': [],
        });
      }
      if (r.url.path == '/api/v1/konten/andere') {
        return json({
          'konten': [
            {'id': 'k-max', 'name': 'max'},
          ],
        });
      }
      if (r.url.path == '/api/v1/personen') {
        return json({
          'personen': [
            {'id': 'anna', 'name': 'Anna', 'anzahl': 3},
            {'id': 'ben', 'name': 'Ben', 'anzahl': 2},
          ],
        });
      }
      if (r.method == 'PUT' && r.url.path == '/api/v1/partner/k-max') {
        gesendet = jsonDecode(r.body);
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => bibliothekTeilen(context, v),
              child: const Text('teilen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('teilen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Die ganze Bibliothek'), findsOneWidget);
    await tester.tap(find.byTooltip('Einschränken'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Was max sieht'), findsOneWidget);
    // Bei der Partnerfreigabe genügt immer eine Person.
    expect(find.text('Alle zusammen'), findsNothing);
    await tester.tap(find.text('Ben'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(gesendet, {
      'ab': null,
      'personen': ['ben'],
    });
    expect(find.text('mit Ben'), findsOneWidget);
  });
  testWidgets('fehlen die Personen, steht dort nicht „ganze Bibliothek“', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            const r = Regel(fehlend: 1);
            return Scaffold(
              body: Column(
                children: [
                  Text(r.leer ? 'leer' : 'eingeschränkt'),
                  Text(regelText(context, r)),
                ],
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('eingeschränkt'), findsOneWidget);
    expect(
      find.text('Eine gewählte Person gibt es nicht mehr.'),
      findsOneWidget,
    );
  });

  testWidgets('Nachlasskontakt: benennen, Zugang verlangen, ablehnen (#300)', (
    tester,
  ) async {
    final rufe = <String>[];
    var benannt = false;
    var verlangt = false;
    final client = MockClient((r) async {
      rufe.add('${r.method} ${r.url.path}');
      if (r.url.path == '/api/v1/nachlass') {
        return json({
          'kontakte': [
            if (benannt)
              {
                'konto': 'k-max',
                'name': 'max',
                'frist': 14,
                if (verlangt) 'angefordert': '2026-11-05T10:00:00Z',
                if (verlangt) 'faellig': '2026-11-19T10:00:00Z',
              },
          ],
          'fuerMich': [
            {'konto': 'k-oma', 'name': 'oma', 'frist': 30},
          ],
          'fristen': [7, 14, 30, 90],
        });
      }
      if (r.url.path == '/api/v1/konten/andere') {
        return json({
          'konten': [
            {'id': 'k-max', 'name': 'max'},
            {'id': 'k-oma', 'name': 'oma'},
          ],
        });
      }
      if (r.method == 'PUT' && r.url.path == '/api/v1/nachlass/k-max') {
        expect(jsonDecode(r.body), {'frist': 14});
        benannt = true;
        return http.Response('', 204);
      }
      if (r.method == 'POST' &&
          r.url.path == '/api/v1/nachlass/von/k-oma/anfordern') {
        return json({'konto': 'k-oma', 'name': 'oma', 'frist': 30});
      }
      if (r.method == 'POST' &&
          r.url.path == '/api/v1/nachlass/k-max/ablehnen') {
        verlangt = false;
        return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    await tester.pumpWidget(
      app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => nachlassVerwalten(context, v),
              child: const Text('nachlass'),
            ),
          ),
        ),
      ),
    );
    Future<void> warte() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('nachlass'));
    await warte();
    expect(find.text('Noch niemand benannt.'), findsOneWidget);
    // Die Frist wählen, dann benennen.
    await tester.tap(find.text('30 Tage Frist').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('14 Tage Frist').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Benennen'));
    await warte();
    expect(rufe, contains('PUT /api/v1/nachlass/k-max'));
    expect(find.widgetWithText(ListTile, '14 Tage Frist'), findsOneWidget);

    // Für Oma Zugang verlangen – erst nach der Rückfrage.
    await tester.tap(find.text('Zugang verlangen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('30 Tage lang widersprechen'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Zugang verlangen'));
    await warte();
    expect(rufe, contains('POST /api/v1/nachlass/von/k-oma/anfordern'));

    await tester.tap(find.text('Schliessen'));
    await tester.pumpAndSettle();

    // Max verlangt Zugang: Der Hinweis steht da, bis abgelehnt ist.
    verlangt = true;
    await tester.pumpWidget(
      app(Scaffold(body: NachlassHinweis(verbindung: v))),
    );
    await warte();
    expect(find.textContaining('max verlangt Zugang'), findsOneWidget);
    await tester.tap(find.text('Ablehnen'));
    await warte();
    expect(rufe, contains('POST /api/v1/nachlass/k-max/ablehnen'));
    expect(find.textContaining('max verlangt Zugang'), findsNothing);
  });
  testWidgets('Collage: Vorlage und Reihenfolge, Vorschau vom Server (#301)', (
    tester,
  ) async {
    final gesendet = <Map<String, Object?>>[];
    final bild = img.Image(width: 30, height: 30);
    img.fill(bild, color: img.ColorRgb8(200, 30, 30));
    final jpeg = img.encodeJpg(bild);
    final client = MockClient((r) async {
      if (r.url.path == '/api/v1/collage') {
        final k = (jsonDecode(r.body) as Map).cast<String, Object?>();
        gesendet.add(k);
        return k['vorschau'] == true
            ? http.Response.bytes(
                jpeg,
                200,
                headers: {'content-type': 'image/jpeg'},
              )
            : json({'aufnahme': 'neu', 'ausgang': 'imported'}, 201);
      }
      return http.Response('', 404);
    });
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: client,
    );
    var gespeichert = false;
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                gespeichert =
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => Collageseite(
                          ids: const ['a', 'b', 'c'],
                          zeichne: collageAmServer(v),
                          speichere: (w) => collageAmServerSpeichern(v, w),
                          miniatur: (_) => null,
                        ),
                      ),
                    ) ??
                    false;
              },
              child: const Text('collage'),
            ),
          ),
        ),
      ),
    );
    Future<void> warte() async {
      // Erst die Verzögerung der Seite, dann die Antwort des Servers.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('collage'));
    await warte();
    expect(gesendet.last['vorschau'], true);
    expect(gesendet.last['vorlage'], 'raster');
    expect(gesendet.last['ids'], ['a', 'b', 'c']);

    // Gross links, das zweite Foto nach vorn, schwarz.
    await tester.tap(find.byTooltip('Gross links'));
    await warte();
    expect(gesendet.last['vorlage'], 'gross_links');
    await tester.tap(find.byKey(const ValueKey('collage-b')));
    await warte();
    expect(gesendet.last['ids'], ['b', 'a', 'c']);

    await tester.tap(find.text('Speichern'));
    await warte();
    expect(gesendet.last.containsKey('vorschau'), false);
    expect(gesendet.last['vorlage'], 'gross_links');
    expect(gespeichert, true);
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto konto;
  late Handler api;
  late Map<String, String> mitSchluessel;
  const tus = {'tus-resumable': '1.0.0'};

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_server_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 7)),
      // Billig gerechnet: Hier geht es nicht um das Passwort.
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    // Ohne Ruhezeit, damit ein Test den Lauf gleich abwarten kann.
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: Duration.zero,
    );
    konto = await konten.legeAn('erika', 'ein langes passwort');
    final a = konten.meldeAn(konto.id, 'Prüfstand', 'lokal');
    mitSchluessel = {'authorization': 'Bearer ${a.token}'};
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
  });
  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Kontobereich> bereich() => bibliotheken.fuer(konto.id);

  Future<Response> frag(
    String methode,
    String pfad, {
    Map<String, String> kopf = const {},
    Object? inhalt,
    bool schluessel = true,
  }) async => api(
    Request(
      methode,
      Uri.parse('http://server$pfad'),
      headers: {if (schluessel) ...mitSchluessel, ...kopf},
      body: inhalt,
    ),
  );

  Future<Map<String, Object?>> jsonAus(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

  Uint8List jpeg(int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 90, 200 - farbe));
    return Uint8List.fromList(img.encodeJpg(bild));
  }

  String meta(Map<String, String> werte) => [
    for (final e in werte.entries)
      '${e.key} ${base64.encode(utf8.encode(e.value))}',
  ].join(',');

  /// Lädt [bytes] in zwei Stücken hoch und gibt die Antwort aufs letzte.
  Future<Response> hochladen(
    Uint8List bytes,
    String name, {
    DateTime? geaendert,
  }) async {
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': meta({
          'filename': name,
          if (geaendert != null)
            'geaendert': '${geaendert.millisecondsSinceEpoch}',
        }),
      },
    );
    expect(angelegt.statusCode, 201);
    final ort = angelegt.headers['location']!;
    final mitte = bytes.length ~/ 2;
    final erstes = await frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes.sublist(0, mitte),
    );
    expect(erstes.statusCode, 204);
    expect(erstes.headers['upload-offset'], '$mitte');
    return frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '$mitte',
      },
      inhalt: bytes.sublist(mitte),
    );
  }

  test('ohne Anmeldung nur das Lebenszeichen', () async {
    expect(
      (await frag('GET', '/api/v1/zustand', schluessel: false)).statusCode,
      200,
    );
    final start = await frag('GET', '/', schluessel: false);
    expect(start.statusCode, 200);
    expect(start.headers['content-type'], startsWith('text/html'));
    expect(await start.readAsString(), contains('Einstellungen → Server'));
    final ohne = await frag('GET', '/api/v1/aufnahmen', schluessel: false);
    expect(ohne.statusCode, 401);
    final falsch = await frag(
      'GET',
      '/api/v1/aufnahmen',
      schluessel: false,
      kopf: {'authorization': 'Bearer pv1_${'x' * 43}'},
    );
    expect(falsch.statusCode, 401);
    expect((await frag('GET', '/api/v1/aufnahmen')).statusCode, 200);
  });

  test('hochladen in Stücken, importieren, Dublette erkennen', () async {
    final bytes = jpeg(40);
    final datum = DateTime(2019, 5, 17, 14, 30);
    final r = await hochladen(bytes, 'strand.jpg', geaendert: datum);
    expect(r.statusCode, 204);
    expect(r.headers['pv-ausgang'], 'imported');
    final id = r.headers['pv-aufnahme']!;

    final seite = await jsonAus(await frag('GET', '/api/v1/aufnahmen'));
    final liste = (seite['aufnahmen']! as List).cast<Map>();
    expect(liste, hasLength(1));
    expect(liste.single['id'], id);
    expect(liste.single['name'], 'strand.jpg');
    expect(
      DateTime.parse(liste.single['aufgenommen']! as String),
      datum,
      reason: 'ohne EXIF zählt die Änderungszeit aus den Metadaten',
    );

    final nochmal = await hochladen(bytes, 'kopie.jpg');
    expect(nochmal.headers['pv-ausgang'], 'duplicateSkipped');
    expect(nochmal.headers['pv-aufnahme'], id);
  });

  test('ein Stück an falscher Stelle wird abgewiesen, Stand bleibt', () async {
    final bytes = jpeg(80);
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': meta({'filename': 'a.jpg'}),
      },
    );
    final ort = angelegt.headers['location']!;
    final falsch = await frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '10',
      },
      inhalt: bytes,
    );
    expect(falsch.statusCode, 409);
    final stand = await frag('HEAD', ort, kopf: tus);
    expect(stand.headers['upload-offset'], '0');
    expect(stand.headers['upload-length'], '${bytes.length}');
  });

  test('Dateien: Miniatur, Original im Teilabruf', () async {
    final bytes = jpeg(120);
    final id = (await hochladen(bytes, 'b.jpg')).headers['pv-aufnahme']!;
    final miniatur = await frag('GET', '/api/v1/aufnahmen/$id/miniatur');
    expect(miniatur.statusCode, 200);
    expect(miniatur.headers['content-type'], 'image/jpeg');

    final teil = await frag(
      'GET',
      '/api/v1/aufnahmen/$id/original',
      kopf: {'range': 'bytes=2-9'},
    );
    expect(teil.statusCode, 206);
    expect(teil.headers['content-range'], 'bytes 2-9/${bytes.length}');
    final gelesen = await teil.read().expand((x) => x).toList();
    expect(gelesen, bytes.sublist(2, 10));
  });

  test('ein Befehl über die Schnittstelle', () async {
    final id = (await hochladen(jpeg(160), 'c.jpg')).headers['pv-aufnahme']!;
    final r = await frag(
      'POST',
      '/api/v1/befehle',
      inhalt: jsonEncode({
        'art': 'bewertungSetzen',
        'werte': {
          'ids': [id],
          'bewertung': 4,
        },
      }),
    );
    expect(r.statusCode, 200);
    final seite = await jsonAus(await frag('GET', '/api/v1/aufnahmen'));
    expect(((seite['aufnahmen']! as List).single as Map)['bewertung'], 4);

    final kaputt = await frag(
      'POST',
      '/api/v1/befehle',
      inhalt: '{"art":"gibtEsNicht","werte":{}}',
    );
    expect(kaputt.statusCode, 400);
  });

  test('blättern über das Lesezeichen', () async {
    for (var i = 0; i < 5; i++) {
      await hochladen(
        jpeg(10 + i * 30),
        'f$i.jpg',
        geaendert: DateTime(2020, 1, 1 + i),
      );
    }
    final gesehen = <String>[];
    String? nach;
    do {
      final seite = await jsonAus(
        await frag(
          'GET',
          '/api/v1/aufnahmen?anzahl=2${nach == null ? '' : '&nach=$nach'}',
        ),
      );
      gesehen.addAll([
        for (final a in (seite['aufnahmen']! as List).cast<Map>())
          a['name']! as String,
      ]);
      nach = seite['weiter'] as String?;
    } while (nach != null);
    expect(gesehen, ['f4.jpg', 'f3.jpg', 'f2.jpg', 'f1.jpg', 'f0.jpg']);
  });

  test('nach dem Hochladen: Regeln und Live Photos wie in der App', () async {
    await (await bereich()).bibliothek.db.upsertAutomationRule(
      AutomationRulesCompanion.insert(
        id: 'regel',
        name: 'Urlaub',
        triggerType: 'dateRange',
        dateFrom: Value(DateTime(2021, 7, 1)),
        dateTo: Value(DateTime(2021, 7, 31)),
        autoFavorite: const Value(true),
      ),
    );
    final foto = (await hochladen(
      jpeg(30),
      'IMG_0007.JPG',
      geaendert: DateTime(2021, 7, 12, 9),
    )).headers['pv-aufnahme']!;
    // Die Hälfte eines Live Photos: Ob sich ein Standbild daraus ziehen
    // lässt, spielt für die Zuordnung keine Rolle, nur der Name.
    final film = await hochladen(
      Uint8List.fromList(List.generate(4096, (i) => i * 7 % 256)),
      'IMG_0007.MOV',
      geaendert: DateTime(2021, 7, 12, 9),
    );
    expect(film.headers['pv-ausgang'], 'imported');
    final filmId = film.headers['pv-aufnahme']!;

    final a = await jsonAus(await frag('GET', '/api/v1/aufnahmen/$foto'));
    expect(a['isFavorite'], isTrue, reason: 'die Regel greift beim Import');
    expect(
      a['linkedAssetId'],
      filmId,
      reason: 'Foto und Film gehören zusammen',
    );
  });

  test(
    'ausgewertet wird nach dem Hochladen – ohne Modelle die Schärfe',
    () async {
      final id = (await hochladen(jpeg(200), 'd.jpg')).headers['pv-aufnahme']!;
      await (await bereich()).auswertung.jetzt();
      final a = await jsonAus(await frag('GET', '/api/v1/aufnahmen/$id'));
      expect(
        a['sharpnessScore'],
        isNotNull,
        reason: 'die Bildanalyse braucht für die Schärfe kein Modell',
      );
      expect(a['facesScanned'], isFalse, reason: 'ohne Modell kein Vermerk');

      final stand = await jsonAus(await frag('GET', '/api/v1/auswertung'));
      expect(stand['laeuft'], isFalse);
      final angestossen = await frag('POST', '/api/v1/auswertung');
      expect(angestossen.statusCode, 202);
    },
  );

  test('Bildsuche nach Inhalt: ohne Modell eine klare Absage', () async {
    final r = await frag(
      'POST',
      '/api/v1/suche/text',
      inhalt: jsonEncode({'text': 'Strand bei Sonnenuntergang'}),
    );
    expect(r.statusCode, 404);
    final leer = await frag('POST', '/api/v1/suche/text', inhalt: '{}');
    expect(leer.statusCode, 400);
  });

  test('Prüfsummen: was schon da ist, auch im Papierkorb', () async {
    final bytes = jpeg(120);
    final r = await hochladen(bytes, 'hafen.jpg');
    final id = r.headers['pv-aufnahme']!;
    final summe = sha256.convert(bytes).toString();
    final fremd = sha256.convert(jpeg(121)).toString();

    Future<Map<String, Object?>> frage(Object? summen) async {
      final a = await frag(
        'POST',
        '/api/v1/pruefsummen',
        inhalt: jsonEncode({'pruefsummen': summen}),
      );
      expect(a.statusCode, 200);
      return ((await jsonAus(a))['vorhanden']! as Map).cast<String, Object?>();
    }

    expect(await frage([summe, fremd, 'kein-hex']), {summe: id});

    final db = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    await db.fuehreAus(InDenPapierkorb([id]));
    expect(await frage([summe]), {summe: id});

    final zuViele = await frag(
      'POST',
      '/api/v1/pruefsummen',
      inhalt: jsonEncode({'pruefsummen': List.filled(1001, fremd)}),
    );
    expect(zuViele.statusCode, 400);
  });

  test('Aufräumen verwirft nur, was nicht mehr weitergeht', () async {
    final bytes = jpeg(140);
    final angelegt = await frag(
      'POST',
      '/api/v1/hochladen',
      kopf: {
        ...tus,
        'upload-length': '${bytes.length}',
        'upload-metadata': meta({'filename': 'lang.jpg'}),
      },
    );
    final ort = angelegt.headers['location']!;
    await frag(
      'PATCH',
      ort,
      kopf: {
        ...tus,
        'content-type': 'application/offset+octet-stream',
        'upload-offset': '0',
      },
      inhalt: bytes.sublist(0, 100),
    );
    final hochladen = (await bibliotheken.fuer(konto.id)).hochladen;
    final id = ort.split('/').last;
    final alt = DateTime.now().subtract(const Duration(days: 8));
    await File('${hochladen.eingang.path}/$id.json').setLastModified(alt);

    expect(await hochladen.raeumeAuf(), 0, reason: 'der Teil wuchs gerade');
    expect(
      (await frag('HEAD', ort, kopf: tus)).headers['upload-offset'],
      '100',
    );

    await File('${hochladen.eingang.path}/$id.teil').setLastModified(alt);
    expect(await hochladen.raeumeAuf(), 1);
    expect((await frag('HEAD', ort, kopf: tus)).statusCode, 404);
  });
}

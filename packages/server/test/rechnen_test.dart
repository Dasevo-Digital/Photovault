import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/auswertung/auswertungen.dart' show Analysestufe;
import 'package:kern/auswertung/herkunft.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/textstellen.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/anmeldung_api.dart';
import 'package:photo_vault_server/src/rechnen.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Rechnen auf verbundenen Rechnern (Issue #104): Aufträge, Vergabe mit
/// Ablauf, Ergebnisse eintragen, Herkunft.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Konto konto;
  late Handler api;
  late Map<String, String> rechner;
  late Map<String, String> zweiter;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_rechnen_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 7)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    // Der Server rechnet hier nichts selbst – alles bleibt den Rechnern.
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: Duration.zero,
      selbst: const {},
    );
    konto = await konten.legeAn('erika', 'ein langes passwort');
    Map<String, String> geraet(String name) => {
      'authorization': 'Bearer ${konten.meldeAn(konto.id, name, 'x').token}',
    };
    rechner = geraet('Rechner');
    zweiter = geraet('Zweiter Rechner');
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
  });
  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<AppDatabase> db() async =>
      (await bibliotheken.fuer(konto.id)).bibliothek.db;

  Future<void> foto(
    String id, {
    String endung = 'jpg',
    String? vorschau,
  }) async => (await db())
      .into((await db()).assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.$endung',
          relativePath: 'originals/$id.$endung',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
          previewRelativePath: Value(vorschau),
        ),
      );

  Future<(int, Map<String, Object?>)> post(
    String pfad,
    Map<String, String> wer,
    Object inhalt,
  ) async {
    final r = await api(
      Request(
        'POST',
        Uri.parse('http://server/api/v1/rechnen/$pfad'),
        headers: wer,
        body: jsonEncode(inhalt),
      ),
    );
    return (
      r.statusCode,
      (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>(),
    );
  }

  Future<List<Rechenauftrag>> hole(
    Map<String, String> wer,
    List<String> arten, {
    int anzahl = 10,
  }) async {
    final (status, j) = await post('auftraege', wer, {
      'arten': arten,
      'anzahl': anzahl,
    });
    expect(status, 200);
    return [
      for (final a in j['auftraege']! as List)
        Rechenauftrag.ausJson((a as Map).cast<String, Object?>()),
    ];
  }

  Map<String, Object?> herkunft(Ergebnisart art) => {
    art.name: {
      'modell': 'modell@123',
      'geraet': 'Rechner (macOS)',
      'beschleuniger': 'CoreML',
    },
  };

  test('verteilt, aber keine Aufnahme an zwei zugleich', () async {
    await foto('a');
    await foto('b');
    // Beide haben dieselbe Zeit; welche zuerst geht, ist nicht festgelegt.
    final erste = await hole(rechner, ['texterkennung'], anzahl: 1);
    expect(erste.single.datei, 'originals/${erste.single.aufnahme}.jpg');
    final zweite = await hole(zweiter, ['texterkennung']);
    expect(
      {erste.single.aufnahme, ...zweite.map((a) => a.aufnahme)},
      {'a', 'b'},
    );
    expect(zweite, hasLength(1));
    expect(await hole(rechner, ['texterkennung']), isEmpty);
  });

  test(
    'Texterkennung vom Rechner landet in der Bibliothek, mit Herkunft',
    () async {
      await foto('a');
      final a = (await hole(rechner, ['texterkennung'])).single;
      final ergebnis = const Rechenergebnis(
        textstellen: [
          Textstelle(
            text: 'Hallo',
            links: 0.1,
            oben: 0.1,
            breite: 0.3,
            hoehe: 0.1,
          ),
        ],
      ).alsJson()..['herkunft'] = herkunft(Ergebnisart.texterkennung);

      final (fremd, _) = await post('ergebnis', zweiter, {
        'auftrag': a.id,
        'ergebnis': ergebnis,
      });
      expect(fremd, 409, reason: 'nur, wer den Auftrag hat');

      final (status, _) = await post('ergebnis', rechner, {
        'auftrag': a.id,
        'ergebnis': ergebnis,
      });
      expect(status, 200);
      final asset = (await (await db()).assetById('a'))!;
      expect(asset.ocrText, 'Hallo');
      final h = (await (await db()).herkunftVon('a')).single;
      expect(
        (h.art, h.geraet, h.beschleuniger),
        ('texterkennung', 'Rechner (macOS)', 'CoreML'),
      );

      final (zweimal, _) = await post('ergebnis', rechner, {
        'auftrag': a.id,
        'ergebnis': ergebnis,
      });
      expect(zweimal, 409, reason: 'ein Auftrag gilt einmal');
      expect(await hole(zweiter, ['texterkennung']), isEmpty);
    },
  );

  test(
    'Bildanalyse: Schärfe, Einbettung und Gesichter samt Ausschnitt',
    () async {
      await foto('a');
      final a = (await hole(rechner, ['bildanalyse'])).single;
      expect(a.teile, Bildanalyseteil.alle);
      final ausschnitt = img.encodeJpg(img.Image(width: 8, height: 8));
      final ergebnis =
          Rechenergebnis(
              schaerfe: 0.42,
              clip: Float32List.fromList(List.generate(512, (i) => i / 512)),
              gesichter: [
                Gesichtsfund(
                  x: 0.2,
                  y: 0.2,
                  breite: 0.3,
                  hoehe: 0.4,
                  schaerfe: 0.9,
                  ausschnitt: ausschnitt,
                  merkmal: Float32List.fromList(List.filled(128, 0.5)),
                  augen: 0.8,
                ),
              ],
            ).alsJson()
            ..['herkunft'] = {
              ...herkunft(Ergebnisart.clip),
              ...herkunft(Ergebnisart.gesichter),
            };
      final (status, _) = await post('ergebnis', rechner, {
        'auftrag': a.id,
        'ergebnis': ergebnis,
      });
      expect(status, 200);

      final d = await db();
      final asset = (await d.assetById('a'))!;
      expect(asset.sharpnessScore, closeTo(0.42, 1e-9));
      expect(asset.facesScanned, isTrue);
      expect((await d.allEmbeddings())['a'], hasLength(512));
      final gesicht = (await d.facesForAsset('a')).single;
      expect(gesicht.eyeOpenScore, closeTo(0.8, 1e-6));
      final pfade = (await bibliotheken.fuer(konto.id)).bibliothek.pfade;
      expect(
        pfade.absolute(gesicht.cropRelativePath!).readAsBytesSync(),
        ausschnitt,
      );
      expect(
        {for (final h in await d.herkunftVon('a')) h.art},
        {'clip', 'gesichter'},
      );
      expect(await hole(rechner, ['bildanalyse']), isEmpty, reason: 'erledigt');
    },
  );

  test('gerechnet wird aus dem Original, nicht aus dem Ansichtsbild '
      '(#333)', () async {
    await foto('j', vorschau: 'previews/j-ansicht.jpg');
    await foto('h', endung: 'heic', vorschau: 'previews/h.jpg');
    final auftraege = await hole(rechner, ['texterkennung']);
    expect(
      {for (final a in auftraege) a.aufnahme: a.datei},
      {'j': 'originals/j.jpg', 'h': 'previews/h.jpg'},
    );
  });

  test('Unsinn wird abgewiesen, ohne etwas einzutragen', () async {
    await foto('a');
    final a = (await hole(rechner, ['bildanalyse'])).single;
    final (status, j) = await post('ergebnis', rechner, {
      'auftrag': a.id,
      'ergebnis': {
        'clip': base64.encode(
          Float32List.fromList([1, 2, 3]).buffer.asUint8List(),
        ),
      },
    });
    expect(status, 400);
    expect('${j['fehler']}', contains('clip'));
    expect((await (await db()).allEmbeddings())['a'], isNull);
  });

  test('was ein Rechner nicht rechnen kann, bekommt keiner wieder', () async {
    await foto('a');
    final a = (await hole(rechner, ['texterkennung'])).single;
    await post('zurueck', rechner, {'auftrag': a.id, 'auslassen': true});
    expect(await hole(zweiter, ['texterkennung']), isEmpty);

    await foto('b');
    final b = (await hole(rechner, ['texterkennung'])).single;
    await post('zurueck', rechner, {'auftrag': b.id});
    expect((await hole(zweiter, ['texterkennung'])).map((x) => x.aufnahme), [
      'b',
    ], reason: 'ohne „auslassen“ ist sie wieder frei');
  });

  test('falsche Typen in der Anfrage sind ein 400', () async {
    await foto('a');
    for (final inhalt in [
      {'arten': 'texterkennung'},
      {
        'arten': ['texterkennung'],
        'teile': 'clip',
      },
      {
        'arten': ['texterkennung'],
        'anzahl': 'fünf',
      },
    ]) {
      final (status, _) = await post('auftraege', rechner, inhalt);
      expect(status, 400, reason: '$inhalt');
    }
  });

  test(
    'liest stückweise und vergibt auch, was hinter Vergebenem liegt',
    () async {
      // Jeder Abruf eines Rechners las bis 3.67 alle offenen Aufnahmen jeder
      // Art. Jetzt liest er Stücke; was ein anderer Rechner gerade hat,
      // liegt vorn und wird übersprungen.
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await foto(id);
      }
      final klein = const Pipeline()
          .addMiddleware(anmeldungNoetig(konten, Absender()))
          .addHandler(Rechenapi(bibliotheken, seite: 2).auftraege);
      Future<List<String>> holeKlein(Map<String, String> wer, int n) async {
        final r = await klein(
          Request(
            'POST',
            Uri.parse('http://server/api/v1/rechnen/auftraege'),
            headers: wer,
            body: jsonEncode({
              'arten': ['texterkennung'],
              'anzahl': n,
            }),
          ),
        );
        expect(r.statusCode, 200);
        final j = jsonDecode(await r.readAsString()) as Map;
        return [
          for (final a in j['auftraege'] as List) '${(a as Map)['aufnahme']}',
        ];
      }

      final erste = await holeKlein(rechner, 3);
      expect(erste, hasLength(3));
      final zweite = await holeKlein(zweiter, 5);
      expect({...erste, ...zweite}, {'a', 'b', 'c', 'd', 'e'});
      expect(zweite, hasLength(2));
      expect(await holeKlein(rechner, 5), isEmpty);
    },
  );

  test('die Kandidaten der drei Arten gibt es auch stückweise', () async {
    for (final id in ['a', 'b', 'c']) {
      await foto(id);
    }
    final d = await db();
    final alle = [
      for (final c in await d.assetsForCombinedImageAnalysis()) c.asset.id,
    ];
    expect(alle, hasLength(3));
    expect([
      for (final c in await d.assetsForCombinedImageAnalysis(
        limit: 2,
        offset: 1,
      ))
        c.asset.id,
    ], alle.sublist(1));
    final ocr = [for (final a in await d.assetsForOcrBackfill()) a.id];
    expect([
      for (final a in await d.assetsForOcrBackfill(limit: 1, offset: 2)) a.id,
    ], ocr.sublist(2));
    final text = [for (final a in await d.assetsForCaptionBackfill()) a.id];
    expect([
      for (final a in await d.assetsForCaptionBackfill(limit: 2)) a.id,
    ], text.sublist(0, 2));
  });

  group('Rechenvergabe', () {
    test('Server und Rechner nie zugleich; nach Ablauf wieder frei', () {
      var jetzt = DateTime(2026, 10, 13, 12);
      final v = Rechenvergabe(uhr: () => jetzt);
      final id = v.vergib(Rechenart.bildanalyse, 'a', 'g1')!;
      expect(v.nimm(Rechenart.bildanalyse, 'a'), isFalse);
      expect(v.vergib(Rechenart.bildanalyse, 'a', 'g2'), isNull);
      expect(
        v.nimm(Rechenart.texterkennung, 'a'),
        isTrue,
        reason: 'andere Art',
      );

      jetzt = jetzt.add(v.dauer + const Duration(seconds: 1));
      expect(v.auftrag(id, 'g1'), isNull, reason: 'abgelaufen');
      expect(v.nimm(Rechenart.bildanalyse, 'a'), isTrue);
      v.gib(Rechenart.bildanalyse, 'a');
      expect(v.vergib(Rechenart.bildanalyse, 'a', 'g2'), isNotNull);
    });

    test('geliefert bleibt geliefert bis zum nächsten Durchgang', () {
      final v = Rechenvergabe();
      final id = v.vergib(Rechenart.bildbeschreibung, 'a', 'g1')!;
      v.geliefert(id);
      expect(v.nimm(Rechenart.bildbeschreibung, 'a'), isFalse);
      v.neuerDurchgang();
      expect(v.nimm(Rechenart.bildbeschreibung, 'a'), isTrue);
    });
  });

  test('PV_KARTEN (#180)', () {
    bool karten(String? w) =>
        Einstellungen.ausUmgebung({'PV_KARTEN': ?w}).karten;
    expect(karten(null), isTrue);
    expect(karten('an'), isTrue);
    expect(karten(' AUS '), isFalse);
    // Die anderen üblichen Schreibweisen meinen dasselbe (#382).
    for (final w in ['off', 'False', '0', 'nein', 'no']) {
      expect(karten(w), isFalse, reason: w);
    }
  });

  test('PV_SELBST_RECHNEN', () {
    Set<Analysestufe> aus(String? w) =>
        Einstellungen.ausUmgebung({'PV_SELBST_RECHNEN': ?w}).selbstRechnen;
    expect(aus(null), Analysestufe.values.toSet());
    expect(aus('alles'), Analysestufe.values.toSet());
    expect(aus('nichts'), isEmpty);
    expect(aus(' schlagwoerter, wiedererkennung '), {
      Analysestufe.schlagwoerter,
      Analysestufe.wiedererkennung,
    });
    expect(() => aus('gesichter'), throwsArgumentError);
  });
}

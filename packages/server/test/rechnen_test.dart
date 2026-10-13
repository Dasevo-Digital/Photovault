import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:kern/auswertung/auswertungen.dart' show Analysestufe;
import 'package:kern/auswertung/herkunft.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/textstellen.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
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

  Future<void> foto(String id) async => (await db())
      .into((await db()).assets)
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
    final erste = await hole(rechner, ['texterkennung'], anzahl: 1);
    expect(erste.single.datei, 'originals/a.jpg');
    final zweite = await hole(zweiter, ['texterkennung']);
    expect(zweite.map((a) => a.aufnahme), ['b']);
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

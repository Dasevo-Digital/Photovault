import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/freigabe_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Gäste laden über einen Link hoch, ohne Anmeldung (#426): Platz,
/// gleichzeitige Uploads, offene Bytes und wartende Prüfungen sind
/// begrenzt – damit ein weitergereichter Link nicht die Platte füllt.

/// Der Absender steht für den Prüfstand in einem Kopf.
class _KopfAbsender extends Absender {
  @override
  String von(Request anfrage) => anfrage.headers['x-absender'] ?? '?';
}

/// Eine Prüfung, die erst endet, wenn der Prüfstand es sagt – so bleiben
/// Beiträge „in Prüfung“.
class _HaengendePruefung extends Gastpruefung {
  _HaengendePruefung()
    : super(abschottung: Future.value(const Abschottung([], ohneNetz: false)));
  final offen = <Completer<({bool ok, Map<String, Object?> befund})>>[];

  @override
  Future<({bool ok, Map<String, Object?> befund})> pruefe(
    File ein,
    Directory ziel, {
    bool video = false,
  }) {
    final c = Completer<({bool ok, Map<String, Object?> befund})>();
    offen.add(c);
    return c.future;
  }

  void alleFertig() {
    for (final c in offen) {
      if (!c.isCompleted) c.complete((ok: false, befund: {'grund': 'Ende'}));
    }
  }
}

void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late _HaengendePruefung pruefung;
  late String link;
  late int frei;
  late Speicherwaechter speicher;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_gastgrenzen_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 3)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    link = (await konten.freigaben.lege(
      konto: erika.id,
      titel: 'Feier',
      album: 'feier',
      hochladen: true,
    )).link;
    pruefung = _HaengendePruefung();
    frei = 1 << 40;
    speicher = Speicherwaechter(
      ordner,
      mindestFrei: 1000,
      messung: (_) async => Speicherstand(gesamt: 1 << 41, frei: frei),
    );
    await speicher.pruefe();
  });

  tearDown(() async {
    pruefung.alleFertig();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Freigabeapi api({
    int offeneBytes = 1 << 40,
    int jeAbsender = 100,
    int jeFreigabe = 100,
    int inPruefung = 100,
  }) => Freigabeapi(
    dienst: konten.freigaben,
    bibliotheken: bibliotheken,
    absender: _KopfAbsender(),
    video: bibliotheken.videofassungen,
    beitraege: konten.beitraege,
    pruefung: pruefung,
    speicher: speicher,
    hoechstensOffeneBytes: offeneBytes,
    gleichzeitigJeAbsender: jeAbsender,
    gleichzeitigJeFreigabe: jeFreigabe,
    hoechstensInPruefung: inPruefung,
  );

  /// Ein Upload, dessen Körper erst mit `fertig()` ankommt.
  ({Future<Response> antwort, void Function() fertig}) schicke(
    Freigabeapi f,
    String von, {
    int laenge = 1000,
  }) {
    final koerper = StreamController<List<int>>();
    final antwort = f.beitrag(
      Request(
        'POST',
        Uri.parse(
          'http://fotos.example/api/v1/teilen/$link/beitrag?name=a.jpg',
        ),
        headers: {
          'x-pv-teilen': '1',
          'content-length': '$laenge',
          'x-absender': von,
        },
        body: koerper.stream,
      ),
      link,
    );
    return (
      antwort: antwort,
      fertig: () {
        koerper.add(List.filled(laenge, 7));
        unawaited(koerper.close());
      },
    );
  }

  Future<int> ganz(Freigabeapi f, String von, {int laenge = 1000}) async {
    final s = schicke(f, von, laenge: laenge)..fertig();
    return (await s.antwort).statusCode;
  }

  Future<bool> schonDa(Future<Response> antwort) async {
    var da = false;
    unawaited(antwort.then((_) => da = true));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return da;
  }

  test('Platz: was gerade ankommt, zählt mit', () async {
    final f = api();
    frei = 1000 + 1500;
    await speicher.pruefe();
    final erster = schicke(f, 'a');
    expect(await schonDa(erster.antwort), isFalse);
    // Nach der letzten Messung wäre noch Platz – aber nicht neben dem
    // ersten, der gerade ankommt.
    expect(await ganz(f, 'b'), 507);
    erster.fertig();
    expect((await erster.antwort).statusCode, 202);
    // Geschrieben: Die nächste Messung sieht ihn, die Zusage fällt weg.
    frei = 1500;
    await speicher.pruefe();
    expect(speicher.reserviert, 0);
    expect(await ganz(f, 'b'), 507);
    frei = 5000;
    await speicher.pruefe();
    expect(await ganz(f, 'b'), 202);
  });

  test(
    'gleichzeitig: je Absender und je Link, danach 503 mit Retry-After',
    () async {
      final f = api(jeAbsender: 2, jeFreigabe: 3);
      final a1 = schicke(f, 'a'), a2 = schicke(f, 'a');
      final a3 = await ganz(f, 'a');
      expect(a3, 503);
      final b1 = schicke(f, 'b');
      expect(await schonDa(b1.antwort), isFalse);
      final c = schicke(f, 'c')..fertig();
      final antwortC = await c.antwort;
      expect(antwortC.statusCode, 503);
      expect(antwortC.headers['retry-after'], isNotNull);
      for (final s in [a1, a2, b1]) {
        s.fertig();
        expect((await s.antwort).statusCode, 202);
      }
      expect(await ganz(f, 'c'), 202);
    },
  );

  test('offene Bytes je Link sind gedeckelt', () async {
    final f = api(offeneBytes: 2500);
    expect(await ganz(f, 'a'), 202);
    expect(await ganz(f, 'b'), 202);
    final r = await ganz(f, 'c');
    expect(r, 429);
    expect(konten.beitraege.offeneBytes(konten.freigaben.fuer(link)!.id), 2000);
  });

  test('zu viele wartende Prüfungen: 503, bis geprüft ist', () async {
    final f = api(inPruefung: 2);
    expect(await ganz(f, 'a'), 202);
    expect(await ganz(f, 'b'), 202);
    final s = schicke(f, 'c')..fertig();
    final r = await s.antwort;
    expect(r.statusCode, 503);
    expect(jsonDecode(await r.readAsString()), containsPair('warten', 30));
    pruefung.alleFertig();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await ganz(f, 'c'), 202);
  });
}

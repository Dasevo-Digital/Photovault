import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/spuren_nachreichen.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Ein Client, der Anfragen an den echten Server weiterreicht – ausser
/// [eingriff] will es anders: eine kaputte Antwort, eine zurückgehaltene.
class _Weiche extends http.BaseClient {
  final _innen = http.Client();
  Future<http.StreamedResponse> Function(
    http.BaseRequest anfrage,
    Future<http.StreamedResponse> Function() weiter,
  )?
  eingriff;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final e = eingriff;
    return e == null
        ? _innen.send(request)
        : e(request, () => _innen.send(request));
  }

  @override
  void close() => _innen.close();
}

http.StreamedResponse _antwort(Object? json) => http.StreamedResponse(
  Stream.value(utf8.encode(jsonEncode(json))),
  200,
  headers: {'content-type': 'application/json'},
);

/// Die Hintergrundschleife und die direkten Aufrufe des Abgleichs gegen
/// einen echten Server (#427).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late HttpServer server;
  late Konto erika;
  final geraete = <(AppDatabase, Abgleich)>[];

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_schleife_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 1)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    server = await shelf_io.serve(
      baueApi(konten: konten, bibliotheken: bibliotheken),
      InternetAddress.loopbackIPv4,
      0,
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
  });

  tearDown(() async {
    for (final (db, a) in geraete) {
      try {
        await a.beende();
      } catch (_) {}
      a.verbindung.schliesse();
      await db.close();
    }
    geraete.clear();
    await server.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<AppDatabase> serverDb() async =>
      (await bibliotheken.fuer(erika.id)).bibliothek.db;

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

  /// Ein Gerät mit Abzug, eingerichtet, ohne Schleife; seine Anfragen
  /// laufen über [weiche].
  Future<(AppDatabase, Abgleich)> geraet(String name, _Weiche weiche) async {
    final token = konten.meldeAn(erika.id, name, 'x').token;
    final v = Serververbindung(
      Uri.parse('http://${server.address.address}:${server.port}/'),
      token,
      client: weiche,
    );
    final datei = File('${ordner.path}/$name/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    final db = AppDatabase(NativeDatabase(datei));
    final a = Abgleich(db, v);
    await a.richteEin();
    geraete.add((db, a));
    return (db, a);
  }

  Future<AssetData> holeAufnahme(AppDatabase db, String id) async =>
      (await db.assetsByIds([id])).single;

  Future<void> bis(
    FutureOr<bool> Function() ok, {
    Duration hoechstens = const Duration(seconds: 10),
  }) async {
    final ende = DateTime.now().add(hoechstens);
    while (!await ok() && DateTime.now().isBefore(ende)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('die Schleife übersteht einen Fehler, der kein Aussetzer ist, und '
      'empfängt danach weiter', () async {
    final s = await serverDb();
    await aufnahme(s, 'a1');
    final weiche = _Weiche();
    final (db, a) = await geraet('Telefon', weiche);
    // Die erste Antwort auf die Änderungen hat weder `zeilen` noch `bis`.
    var kaputt = 1;
    weiche.eingriff = (r, weiter) async {
      if (r.url.path.endsWith('/abgleich/aenderungen') && kaputt > 0) {
        kaputt--;
        return _antwort(<String, Object?>{});
      }
      return weiter();
    };
    a.starte();
    await bis(() => kaputt == 0);
    expect(kaputt, 0);

    await s.fuehreAus(const BewertungSetzen(['a1'], 4));
    await bis(() async => (await holeAufnahme(db, 'a1')).rating == 4);
    expect(
      (await holeAufnahme(db, 'a1')).rating,
      4,
      reason: 'die Schleife läuft weiter und holt die Änderung ab',
    );
    await a.beende();
  });

  group('anderes Schema beim Server', () {
    /// Lässt den Server ein Schema höher melden, sobald [an] gilt, und
    /// schreibt mit, was das Gerät sonst fragt.
    ({List<String> abgleich, void Function(bool) schalte}) hoeher(
      _Weiche weiche,
      AppDatabase db, {
      bool an = true,
    }) {
      final abgleich = <String>[];
      var hoeher = an;
      weiche.eingriff = (r, weiter) async {
        final pfad = r.url.path;
        if (pfad.endsWith('/abgleich/stand') && hoeher) {
          return _antwort({'stand': 0, 'schema': db.schemaVersion + 1});
        }
        if (pfad.contains('/abgleich/aenderungen') ||
            pfad.contains('/abgleich/zeilen') ||
            pfad.endsWith('/befehle')) {
          abgleich.add(pfad);
        }
        return weiter();
      };
      return (abgleich: abgleich, schalte: (an) => hoeher = an);
    }

    test('direkte Aufrufe ohne laufende Schleife gleichen nichts ab', () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final weiche = _Weiche();
      final (db, a) = await geraet('Telefon', weiche);
      final w = hoeher(weiche, db);

      // Ziehen zum Aktualisieren auf einem Gerät mit zu alter App.
      await s.fuehreAus(const BewertungSetzen(['a1'], 4));
      await expectLater(a.empfange(), throwsA(isA<AbgleichsschemaAnders>()));
      expect((await holeAufnahme(db, 'a1')).rating, isNot(4));
      expect(a.zustandJetzt.serverSchema, db.schemaVersion + 1);

      await db.fuehreAus(const BeschreibungSetzen(['a1'], 'hier'));
      expect(
        a.zustandJetzt.schemaAnders,
        isTrue,
        reason: 'ein neuer Befehl lässt den Hinweis stehen',
      );
      await expectLater(a.sende(), throwsA(isA<AbgleichsschemaAnders>()));
      await expectLater(a.gleicheAn(), throwsA(isA<AbgleichsschemaAnders>()));
      expect((await holeAufnahme(s, 'a1')).description, isNull);
      expect(w.abgleich, isEmpty, reason: 'weder geholt noch geschickt');
    });

    test('hat die Schleife angehalten, gleicht auch ein direkter Aufruf '
        'nichts ab', () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final weiche = _Weiche();
      final (db, a) = await geraet('Rechner', weiche);
      final w = hoeher(weiche, db);
      a.starte();
      await bis(() => a.zustandJetzt.schemaAnders);
      expect(a.zustandJetzt.schemaAnders, isTrue);

      // Am Rechner geht etwas hoch, danach holt er die neuen Aufnahmen.
      await s.fuehreAus(const BewertungSetzen(['a1'], 4));
      await expectLater(a.empfange(), throwsA(isA<AbgleichsschemaAnders>()));
      expect((await holeAufnahme(db, 'a1')).rating, isNot(4));
      expect(w.abgleich, isEmpty);
    });

    test('nach einem Aussetzer fragt die Schleife noch einmal nach dem '
        'Schema', () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final weiche = _Weiche();
      final (db, a) = await geraet('Telefon', weiche);
      final w = hoeher(weiche, db, an: false);
      final innen = weiche.eingriff!;
      a.starte();
      await bis(() => a.zustandJetzt.erreichbar);
      await s.fuehreAus(const BewertungSetzen(['a1'], 2));
      await bis(() async => (await holeAufnahme(db, 'a1')).rating == 2);
      expect((await holeAufnahme(db, 'a1')).rating, 2);

      // Der Server startet mit einer neuen Fassung neu: Die Verbindung
      // reisst einmal ab, danach meldet er ein höheres Schema.
      var abgerissen = false;
      weiche.eingriff = (r, weiter) async {
        if (!abgerissen) {
          abgerissen = true;
          w.schalte(true);
          throw http.ClientException('neu gestartet');
        }
        return innen(r, weiter);
      };
      a.jetzt();
      await bis(() => a.zustandJetzt.schemaAnders);
      expect(a.zustandJetzt.schemaAnders, isTrue);
      w.abgleich.clear();
      await s.fuehreAus(const BewertungSetzen(['a1'], 5));
      a.jetzt();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect((await holeAufnahme(db, 'a1')).rating, 2);
      expect(w.abgleich, isEmpty);
    });
  });

  group('Angleichen und ein zweites Empfangen zugleich', () {
    /// Hält die Antwort auf die erste Anfrage nach einzelnen Zeilen zurück,
    /// bis `frei` eintritt – mit dem Stand, den der Server beim Lesen hatte.
    ({Completer<void> angehalten, Completer<void> frei}) halteZeilenAn(
      _Weiche weiche,
    ) {
      final angehalten = Completer<void>(), frei = Completer<void>();
      var erstes = true;
      weiche.eingriff = (r, weiter) async {
        if (!r.url.path.endsWith('/abgleich/zeilen') || !erstes) {
          return weiter();
        }
        erstes = false;
        final antwort = await weiter();
        final koerper = await antwort.stream.toBytes();
        angehalten.complete();
        await frei.future;
        return http.StreamedResponse(
          Stream.value(koerper),
          antwort.statusCode,
          headers: antwort.headers,
        );
      };
      return (angehalten: angehalten, frei: frei);
    }

    test('ein älterer Zeilenstand landet nicht über einem neueren', () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final weiche = _Weiche();
      final (db, a) = await geraet('Telefon', weiche);
      await db.fuehreAus(const BeschreibungSetzen(['a1'], 'Hafen'));
      await a.sende();
      final halt = halteZeilenAn(weiche);

      // Die Schleife gleicht den bestätigten Befehl an und wartet auf die
      // Zeile vom Server.
      final erstes = a.empfange();
      await halt.angehalten.future;
      // Inzwischen ändert jemand die Zeile, und ein direkter Aufruf (Ziehen
      // zum Aktualisieren) holt das ab.
      await s.fuehreAus(const BeschreibungSetzen(['a1'], 'Strand'));
      final zweites = a.empfange();
      await Future.any([
        zweites,
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
      halt.frei.complete();
      await erstes;
      await zweites;
      expect((await holeAufnahme(db, 'a1')).description, 'Strand');
      expect((await holeAufnahme(s, 'a1')).description, 'Strand');
    });

    test('was ein Befehl während der Anfrage vorwegnimmt, bleibt', () async {
      final s = await serverDb();
      await aufnahme(s, 'a1');
      final weiche = _Weiche();
      final (db, a) = await geraet('Telefon', weiche);
      await db.fuehreAus(const BeschreibungSetzen(['a1'], 'Hafen'));
      await a.sende();
      final halt = halteZeilenAn(weiche);

      final lauf = a.empfange();
      await halt.angehalten.future;
      await db.fuehreAus(const BeschreibungSetzen(['a1'], 'Mole'));
      halt.frei.complete();
      await lauf;
      expect(
        (await holeAufnahme(db, 'a1')).description,
        'Mole',
        reason: 'der neue Befehl ist noch nicht gesendet',
      );
      await a.sende();
      await a.empfange();
      expect((await holeAufnahme(db, 'a1')).description, 'Mole');
      expect((await holeAufnahme(s, 'a1')).description, 'Mole');
    });
  });

  group('Spuren nachreichen', () {
    SpurAnlegen spur(String id) => SpurAnlegen(
      id: id,
      name: '$id.gpx',
      quelle: '$id.gpx',
      laengeKm: 2.4,
      aufstieg: 110,
      abstieg: 0,
      angelegtAm: DateTime.utc(2026, 8, 2),
      punkte: [
        (
          breite: 51.80,
          laenge: 10.60,
          hoehe: 300.0,
          zeit: DateTime.utc(2026, 8, 1, 9),
        ),
        (
          breite: 51.81,
          laenge: 10.62,
          hoehe: 410.0,
          zeit: DateTime.utc(2026, 8, 1, 10),
        ),
      ],
    );

    test('eine anderswo gelöschte Spur kommt nicht zurück', () async {
      final s = await serverDb();
      await s.fuehreAus(spur('weg'));
      // Der Rechner war zu, als ein anderes Gerät die Spur löschte.
      final (db, a) = await geraet('Rechner', _Weiche());
      expect((await db.alleSpuren()).map((x) => x.id), ['weg']);
      await s.fuehreAus(const SpurLoeschen('weg'));

      expect(await spurenNachreichen(a), 0);
      await a.sende();
      expect(await s.alleSpuren(), isEmpty, reason: 'nicht neu angelegt');
      expect(await db.alleSpuren(), isEmpty);
    });

    test('eine Spur mit eigenem Befehl in der Warteschlange geht nicht '
        'doppelt', () async {
      final weiche = _Weiche();
      final (db, a) = await geraet('Rechner', weiche);
      await db.fuehreAus(spur('neu'));
      expect(await spurenNachreichen(a), 0);
      expect(
        (await db
                .customSelect('SELECT count(*) AS n FROM pv_ausgang')
                .getSingle())
            .read<int>('n'),
        1,
      );
    });

    test('der Altbestand wird einmal durchgesehen', () async {
      final weiche = _Weiche();
      final (db, a) = await geraet('Rechner', weiche);
      final gefragt = <String>[];
      weiche.eingriff = (r, weiter) {
        gefragt.add(r.url.path);
        return weiter();
      };
      expect(await spurenNachreichen(a), 0);
      expect(gefragt, contains('/api/v1/spuren'));
      gefragt.clear();
      expect(await spurenNachreichen(a), 0);
      // Gemerkt in der Kopie, also auch nach einem Neustart.
      final nachStart = Abgleich(db, a.verbindung);
      await nachStart.richteEin();
      expect(await spurenNachreichen(nachStart), 0);
      expect(gefragt, isEmpty);
    });
  });
}

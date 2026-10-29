import 'package:shelf/shelf.dart';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/services/import_plan.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/fallschluessel.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

class _ClientDb extends AppDatabase {
  _ClientDb(super.executor);
}

class _Ablage implements Tokenablage {
  final werte = <String, String>{};
  @override
  Future<String?> lies(String k) async => werte[k];
  @override
  Future<bool> schreibe(String k, String v) async {
    werte[k] = v;
    return true;
  }

  @override
  Future<void> loesche(String k) async {
    werte.remove(k);
  }
}

void main() {
  late Directory temp;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Konto konto;
  late Bibliotheken bibliotheken;
  late HttpServer server;
  late AppDatabase quelle;
  late _ClientDb db;
  late Abgleich a;
  late _Ablage ablage;
  late File datei;
  late Serververbindung v;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_sync_konflikt_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 2)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    konto = await konten.legeAn('pruefkonto', 'synthetisches passwort');
    bibliotheken = Bibliotheken(
      wurzel: Directory('${temp.path}/bibliotheken'),
      eingang: Directory('${temp.path}/eingang'),
    );
    quelle = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    await quelle.insertAsset(
      AssetsCompanion.insert(
        id: 'foto',
        originalFileName: 'probe.jpg',
        relativePath: 'originals/probe.jpg',
        checksum: 'probe',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
    server = await shelf_io.serve(
      baueApi(konten: konten, bibliotheken: bibliotheken),
      '127.0.0.1',
      0,
    );
    v = Serververbindung(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      konten.meldeAn(konto.id, 'Pruefgeraet', 'x').token,
    );
    datei = File('${temp.path}/client/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    db = _ClientDb(NativeDatabase(datei));
    ablage = _Ablage();
    a = Abgleich(db, v, fallschluessel: await Fallschluessel.lade(db, ablage));
    await a.richteEin();
  });
  tearDown(() async {
    await a.beende();
    v.schliesse();
    await db.close();
    await server.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await temp.delete(recursive: true);
  });

  test(
    'abweichende gleiche Felder werden erhalten und müssen bewusst entschieden werden',
    () async {
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      expect((await db.assetById('foto'))!.rating, 3);
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await a.sende();
      await a.empfange();
      expect((await quelle.assetById('foto'))!.rating, 5);
      expect((await db.assetById('foto'))!.rating, 5);
      expect(a.zustandJetzt.faelle, 1);
      final fall = (await a.faelle()).single;
      expect(fall.grund, 'pv_sync_konflikt');
      final vergleich = await a.vergleiche(fall);
      expect(vergleich.fotonamen, ['probe.jpg']);
      await a.erneutAnwenden(vergleich);
      await a.sende();
      await a.empfange();
      expect((await quelle.assetById('foto'))!.rating, 3);
      expect(await a.faelle(), isEmpty);
    },
  );

  test(
    'unabhängige Felder und bereits gleiche Zielwerte erzeugen keinen Konflikt',
    () async {
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      await quelle.fuehreAus(
        const BeschreibungSetzen(['foto'], 'Serverbeschreibung'),
      );
      await a.sende();
      await a.empfange();
      expect(a.zustandJetzt.faelle, 0);
      expect((await quelle.assetById('foto'))!.rating, 3);
      expect(
        (await quelle.assetById('foto'))!.description,
        'Serverbeschreibung',
      );
      await db.fuehreAus(const BewertungSetzen(['foto'], 4));
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 4));
      await a.sende();
      await a.empfange();
      expect(a.zustandJetzt.faelle, 0);
    },
  );

  test(
    'ein bewusst erneut gesetzter gleicher lokaler Wert überschreibt keine neue Serverentscheidung',
    () async {
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await db.fuehreAus(const BewertungSetzen(['foto'], 0));
      await a.sende();
      await a.empfange();
      expect((await quelle.assetById('foto'))!.rating, 5);
      expect(a.zustandJetzt.faelle, 1);
    },
  );

  test(
    'Vorschau rollt zurück und legt weder zusätzliche Befehle noch doppelte Alben an',
    () async {
      await db.fuehreAus(AlbumAnlegen('album', 'Probealbum', DateTime(2026)));
      expect(await db.select(db.albums).get(), hasLength(1));
      expect(
        (await db
                .customSelect('SELECT count(*) AS n FROM pv_ausgang')
                .getSingle())
            .read<int>('n'),
        1,
      );
      await a.sende();
      await a.empfange();
      expect(await quelle.select(quelle.albums).get(), hasLength(1));
      expect(a.zustandJetzt.faelle, 0);
    },
  );

  test(
    'ein inzwischen geänderter Vergleich erfordert eine neue ausdrückliche Entscheidung',
    () async {
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await a.sende();
      await a.empfange();
      final vergleich = await a.vergleiche((await a.faelle()).single);
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 2));
      await expectLater(
        a.erneutAnwenden(vergleich),
        throwsA(isA<AbgleichsstandGeaendert>()),
      );
      expect((await quelle.assetById('foto'))!.rating, 2);
      expect(a.zustandJetzt.faelle, 1);
    },
  );

  test(
    'abgelehnte Absichten liegen dauerhaft verschlüsselt vor und überstehen eine neue Anmeldung',
    () async {
      const text = 'nur im verschluesselten Eintrag';
      await db.fuehreAus(const BeschreibungSetzen(['foto'], text));
      final offen =
          (await db.customSelect('SELECT befehl FROM pv_ausgang').getSingle())
              .read<String>('befehl');
      expect(offen, isNot(contains(text)));
      await quelle.fuehreAus(
        const BeschreibungSetzen(['foto'], 'andere Beschreibung'),
      );
      await a.sende();
      await a.empfange();
      final gespeichert =
          (await db
                  .customSelect('SELECT inhalt FROM pv_abgleichsfaelle')
                  .getSingle())
              .read<String>('inhalt');
      expect(gespeichert, isNot(contains(text)));
      await a.beende();
      v.schliesse();
      await db.close();
      db = _ClientDb(NativeDatabase(datei));
      v = Serververbindung(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        konten.meldeAn(konto.id, 'Erneute Anmeldung', 'x').token,
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      expect(a.zustandJetzt.faelle, 1);
      final fall = (await a.faelle()).single;
      expect((fall.befehl['werte'] as Map)['beschreibung'], text);
      await a.behalteServerstand(fall);
      expect(await a.faelle(), isEmpty);
      expect((await db.assetById('foto'))!.description, 'andere Beschreibung');
    },
  );

  test(
    'gesperrte und gelöschte Fotos werden nicht über eine alte Absicht verändert',
    () async {
      await db.fuehreAus(
        const BeschreibungSetzen(['foto'], 'private neue Beschreibung'),
      );
      await quelle.customStatement(
        "UPDATE assets SET is_locked = 1, description = NULL WHERE id = 'foto'",
      );
      await a.sende();
      await a.empfange();
      final vergleich = await a.vergleiche((await a.faelle()).single);
      expect(vergleich.geschuetzt, isTrue);
      expect(vergleich.fotonamen, isEmpty);
      expect(vergleich.serverwerte.every((v) => v == null), isTrue);
      await expectLater(a.erneutAnwenden(vergleich), throwsStateError);
      expect((await quelle.assetById('foto'))!.description, isNull);
    },
  );

  test(
    'verlorene Konfliktantwort wird beim Wiederholen wieder als Konflikt beantwortet',
    () async {
      await a.beende();
      final echt = http.Client();
      var verloren = false;
      final mock = MockClient((r) async {
        final kopie = http.Request(r.method, r.url)
          ..headers.addAll(r.headers)
          ..bodyBytes = r.bodyBytes;
        final antwort = await echt.send(kopie);
        final data = await antwort.stream.toBytes();
        if (!verloren && r.url.path.endsWith('/befehle')) {
          verloren = true;
          throw const SocketException('synthetische Unterbrechung');
        }
        return http.Response.bytes(
          data,
          antwort.statusCode,
          headers: antwort.headers,
        );
      });
      addTearDown(echt.close);
      v = Serververbindung(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        v.token,
        client: mock,
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await expectLater(a.sende(), throwsA(isA<KeineVerbindung>()));
      await a.sende();
      await a.empfange();
      expect(a.zustandJetzt.faelle, 1);
      expect((await quelle.assetById('foto'))!.rating, 5);
    },
  );

  test(
    'älterer Server bekommt keinen ungeschützten Befehl als stillen Ersatz',
    () async {
      await a.beende();
      var gesendet = false;
      v = Serververbindung(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        'synthetisches-token',
        client: MockClient((r) async {
          if (r.method == 'POST') gesendet = true;
          return http.Response(
            jsonEncode({'protokoll': 2}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      await a.sende();
      expect(gesendet, isFalse);
      expect(a.zustandJetzt.serverOhneKonfliktpruefung, isTrue);
      expect(a.zustandJetzt.ausstehend, 1);
    },
  );
  test(
    'bereits fehlende Albumzuordnung überschreibt keine neue Zuordnung am Server',
    () async {
      await quelle.fuehreAus(AlbumAnlegen('album', 'Album', DateTime(2026)));
      await a.empfange();
      await db.fuehreAus(const AusAlbumNehmen('album', ['foto']));
      await quelle.fuehreAus(const AlbumFuellen('album', ['foto']));
      await a.sende();
      await a.empfange();
      expect(await quelle.assetsInAlbumOnce('album'), hasLength(1));
      expect(a.zustandJetzt.faelle, 1);
    },
  );

  test(
    'unvollständige Stapelantwort bestätigt keine gespeicherte Absicht',
    () async {
      await a.beende();
      v.schliesse();
      v = Serververbindung(
        Uri.parse('http://127.0.0.1/'),
        'synthetisch',
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.method == 'GET'
                  ? {
                      'funktionen': {'konfliktpruefung': 1},
                    }
                  : {'stand': 0, 'ergebnisse': []},
            ),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      await db.fuehreAus(const BewertungSetzen(['foto'], 3));
      await expectLater(a.sende(), throwsA(isA<Serverfehler>()));
      expect((await a.faelle()).single.ausstehend, isTrue);
      expect(
        (await db.customSelect('SELECT bestaetigt FROM pv_ausgang').getSingle())
            .readNullable<int>('bestaetigt'),
        isNull,
      );
    },
  );

  test(
    'parallele Wiederholung derselben Kennung führt die Aktion genau einmal aus',
    () async {
      final befehl = {
        'kennung': 'gleichzeitig',
        ...AlbumAnlegen('album', 'Album', DateTime(2026)).alsJson(),
      };
      final ergebnisse = await Future.wait([
        for (var i = 0; i < 2; i++)
          v.schicke('api/v1/befehle', {
            'befehle': [befehl],
          }),
      ]);
      expect(
        ergebnisse.map((j) => ((j['ergebnisse'] as List).single as Map)['ok']),
        everyElement(isTrue),
      );
      expect(await quelle.select(quelle.albums).get(), hasLength(1));
      expect(
        (await quelle
                .customSelect(
                  "SELECT count(*) AS n FROM pv_erledigt WHERE kennung = 'gleichzeitig'",
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
    },
  );

  test(
    'fehlender Geräteschlüssel wird nicht durch einen neuen Schlüssel ersetzt',
    () async {
      final kennung =
          (await db
                  .customSelect('SELECT kennung FROM pv_fallschluessel')
                  .getSingle())
              .read<String>('kennung');
      ablage.werte.clear();
      await expectLater(
        Fallschluessel.lade(db, ablage),
        throwsA(isA<TokenablageFehler>()),
      );
      expect(
        (await db
                .customSelect('SELECT kennung FROM pv_fallschluessel')
                .getSingle())
            .read<String>('kennung'),
        kennung,
      );
    },
  );

  test(
    'geprüfter Upload weist geänderte Quelle oder Regelstand ohne Import ab',
    () async {
      final bib = (await bibliotheken.fuer(konto.id)).bibliothek;
      final plan = ImportPlanDienst(quelle, bib.importe);
      final datei = File('${temp.path}/upload.jpg')
        ..writeAsBytesSync([1, 4, 9, 16]);
      final stand = await plan.aktuellerRegelstand();
      var r = await TusHochladen(v).lade(datei, 'api/v1/hochladen', {
        'filename': 'upload.jpg',
        'sha256': '0' * 64,
        'regelstand': stand,
      });
      expect(r['pv-ausgang'], 'failed');
      expect(await quelle.select(quelle.assets).get(), hasLength(1));
      await quelle.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'regel',
            name: 'Neue Regel',
            triggerType: 'dateiname',
          ),
        ),
      );
      r = await TusHochladen(v).lade(datei, 'api/v1/hochladen', {
        'filename': 'upload.jpg',
        'sha256': sha256.convert(datei.readAsBytesSync()).toString(),
        'regelstand': stand,
      });
      expect(r['pv-ausgang'], 'failed');
      expect(await quelle.select(quelle.assets).get(), hasLength(1));
      r = await TusHochladen(v).lade(datei, 'api/v1/hochladen', {
        'filename': 'upload.jpg',
        'sha256': sha256.convert(datei.readAsBytesSync()).toString(),
        'regelstand': await plan.aktuellerRegelstand(),
      });
      expect(r['pv-ausgang'], 'imported');
      expect(await quelle.select(quelle.assets).get(), hasLength(2));
    },
  );

  test(
    'späte ältere Abfrage setzt den bereits neueren Bibliotheksstand nicht zurück',
    () async {
      await a.beende();
      final token = v.token;
      v.schliesse();
      final echt = http.Client();
      addTearDown(echt.close);
      final abgeholt = Completer<void>(), weiter = Completer<void>();
      var erste = true;
      v = Serververbindung(
        Uri.parse('http://127.0.0.1:${server.port}/'),
        token,
        client: MockClient((r) async {
          final kopie = http.Request(r.method, r.url)
            ..headers.addAll(r.headers)
            ..bodyBytes = r.bodyBytes;
          final antwort = await echt.send(kopie);
          final data = await antwort.stream.toBytes();
          if (erste && r.url.path.endsWith('/aenderungen')) {
            erste = false;
            abgeholt.complete();
            await weiter.future;
          }
          return http.Response.bytes(
            data,
            antwort.statusCode,
            headers: antwort.headers,
          );
        }),
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      await quelle.fuehreAus(const FavoritSetzen(['foto'], true));
      final alt = a.empfange();
      await abgeholt.future;
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await a.empfange();
      weiter.complete();
      await alt;
      expect((await db.assetById('foto'))!.rating, 5);
      expect((await db.assetById('foto'))!.isFavorite, isTrue);
    },
  );
  test(
    'alte Klartextwarteschlange wird geschützt und ohne Verlust abgearbeitet',
    () async {
      const befehl = BeschreibungSetzen(['foto'], 'Alte Offlineabsicht');
      await db.fuehreAus(befehl);
      await a.beende();
      await db.customStatement(
        "UPDATE pv_ausgang SET befehl = ?, basis = '[]'",
        [jsonEncode(befehl.alsJson())],
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      final gespeichert =
          (await db.customSelect('SELECT befehl FROM pv_ausgang').getSingle())
              .read<String>('befehl');
      expect(gespeichert, isNot(contains('Alte Offlineabsicht')));
      expect((await a.faelle()).single.lesbar, isTrue);
      await a.sende();
      await a.empfange();
      expect(
        (await quelle.assetById('foto'))!.description,
        'Alte Offlineabsicht',
      );
      expect(await a.faelle(), isEmpty);
    },
  );
  test(
    'zusammengesetzte Markierung schützt unverändert gesetzte Bewertung',
    () async {
      await db.fuehreAus(
        const MarkierungenSetzen({
          'foto': (favorit: true, bewertung: 0, farbe: null),
        }),
      );
      await quelle.fuehreAus(const BewertungSetzen(['foto'], 5));
      await a.sende();
      await a.empfange();
      final foto = (await quelle.assetById('foto'))!;
      expect(foto.rating, 5);
      expect(a.zustandJetzt.faelle, 1);
    },
  );

  test('Ortsänderung schützt das gesamte Koordinatenpaar', () async {
    await quelle.fuehreAus(const OrtSetzen(['foto'], 10, 20));
    await a.empfange();
    await db.fuehreAus(const OrtSetzen(['foto'], 10, 21));
    await quelle.fuehreAus(const OrtSetzen(['foto'], 11, 20));
    await a.sende();
    await a.empfange();
    final foto = (await quelle.assetById('foto'))!;
    expect(foto.latitude, 11);
    expect(foto.longitude, 20);
    expect(a.zustandJetzt.faelle, 1);
  });

  test(
    'neue Tagzeile bleibt nach aufgehobener Sperre erneut anwendbar',
    () async {
      await db.fuehreAus(
        const SchlagwortAnheften(['foto'], 'synthetischer-neuer-tag'),
      );
      await quelle.customStatement(
        "UPDATE assets SET is_locked = 1 WHERE id = 'foto'",
      );
      await a.sende();
      await a.empfange();
      await quelle.customStatement(
        "UPDATE assets SET is_locked = 0 WHERE id = 'foto'",
      );
      await a.empfange();
      final fall = (await a.faelle()).single;
      final vergleich = await a.vergleiche(fall);
      expect(vergleich.geschuetzt, isFalse);
      expect(vergleich.entfernt, isFalse);
      await a.erneutAnwenden(vergleich);
      await a.sende();
      await a.empfange();
      expect(
        (await quelle.tagsForAsset('foto')).map((t) => t.name),
        contains('synthetischer-neuer-tag'),
      );
      expect(await a.faelle(), isEmpty);
    },
  );
  test(
    'öffentliche Anmeldung weist übergroßen Chunked-Körper vor Authentifizierung ab',
    () async {
      var teile = 0;
      Stream<List<int>> quelle() async* {
        for (var i = 0; i < 128; i++) {
          teile++;
          yield List.filled(8192, 32);
        }
      }

      final r = await baueApi(konten: konten, bibliotheken: bibliotheken)(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v1/anmelden'),
          body: quelle(),
        ),
      );
      expect(r.statusCode, 413);
      expect(teile, lessThan(5));
    },
  );
  test(
    'alte übergroße Warteschlange bleibt als Fall erhalten und blockiert Folgebefehle nicht',
    () async {
      final alt = BeschreibungSetzen(['foto'], 'x' * (6 * 1024 * 1024 + 1));
      await a.beende();
      await db.customStatement(
        'INSERT INTO pv_ausgang (kennung,befehl,basis,angelegt) VALUES (?,?,?,?)',
        [
          'altgross',
          jsonEncode(alt.alsJson()),
          '[]',
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      a = Abgleich(
        db,
        v,
        fallschluessel: await Fallschluessel.lade(db, ablage),
      );
      await a.richteEin();
      await db.fuehreAus(const FavoritSetzen(['foto'], true));
      await a.sende();
      await a.empfange();
      expect((await quelle.assetById('foto'))!.isFavorite, isTrue);
      final fall = (await a.faelle()).single;
      expect(fall.grund, 'pv_sync_auswahl');
      expect(fall.lesbar, isTrue);
      expect(fall.befehl['art'], 'beschreibungSetzen');
    },
  );
}

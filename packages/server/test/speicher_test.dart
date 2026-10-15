import 'dart:convert';
import 'dart:io';

import 'package:kern/protokoll.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Der Speicher des Servers (Issue #123): warnen, wenn er knapp wird, und
/// keine Uploads mehr annehmen, wenn er voll ist.
void main() {
  const gb = 1000 * 1000 * 1000;

  group('df -Pk', () {
    test('Linux', () {
      final s = speicherAusDf(
        'Filesystem                         1024-blocks    Used Available Capacity Mounted on\n'
        '/dev/mapper/pve-vm--115--disk--1    205314024 5600000 189209008       3% /var/lib/x\n',
      )!;
      expect(s.gesamt, 205314024 * 1024);
      expect(s.frei, 189209008 * 1024);
    });

    test('macOS', () {
      final s = speicherAusDf(
        'Filesystem     1024-blocks      Used Available Capacity  Mounted on\n'
        '/dev/disk3s5    971350180 612345678 300000000    68%    /System/Volumes/Data\n',
      )!;
      expect(s.frei, 300000000 * 1024);
      expect(s.anteilBelegt, closeTo(0.69, 0.01));
    });

    test('Unsinn ergibt nichts', () {
      expect(speicherAusDf(''), isNull);
      expect(speicherAusDf('df: /x: No such file or directory'), isNull);
    });

    test('am echten Dateisystem', () async {
      final w = Speicherwaechter(Directory.systemTemp);
      await w.pruefe();
      expect(w.stand!.gesamt, greaterThan(0));
      expect(w.stufe, isNotNull);
    });
  });

  test('knapp nach Anteil oder nach Rest, voll unter dem Mindestplatz', () {
    final w = Speicherwaechter(Directory.systemTemp);
    Speicherstufe stufe(int gesamt, int frei) =>
        w.stufeFuer(Speicherstand(gesamt: gesamt, frei: frei));
    expect(stufe(200 * gb, 100 * gb), Speicherstufe.ausreichend);
    expect(stufe(200 * gb, 29 * gb), Speicherstufe.knapp, reason: '> 85 %');
    // Eine grosse Platte: 85 % belegt wäre noch viel, unter 10 GB nicht.
    expect(stufe(4000 * gb, 700 * gb), Speicherstufe.ausreichend);
    expect(stufe(40 * gb, 9 * gb), Speicherstufe.knapp, reason: '< 10 GB');
    expect(stufe(200 * gb, gb), Speicherstufe.voll);
  });

  test('jeder Wechsel steht im Protokoll, nicht jede Messung', () async {
    final zeilen = <String>[];
    final vorher = protokollZiel;
    protokollZiel = zeilen.add;
    addTearDown(() => protokollZiel = vorher);
    var frei = 100 * gb;
    final w = Speicherwaechter(
      Directory.systemTemp,
      messung: (_) async => Speicherstand(gesamt: 200 * gb, frei: frei),
    );
    await w.pruefe();
    await w.pruefe();
    frei = 20 * gb;
    await w.pruefe();
    frei = gb;
    await w.pruefe();
    frei = 150 * gb;
    await w.pruefe();
    expect(zeilen, [
      startsWith('Speicher: 100.0 GB frei von 200.0 GB'),
      startsWith('Speicher knapp: 20.0 GB frei'),
      allOf(startsWith('Speicher voll'), contains('Uploads werden abgewiesen')),
      startsWith('Speicher wieder ausreichend'),
    ]);
  });

  group('über die Schnittstelle', () {
    late Directory ordner;
    late Serverdatenbank sdb;
    late Bibliotheken bibliotheken;
    late Handler api;
    late Map<String, String> kopf;
    late Speicherwaechter speicher;
    var frei = 100 * gb;

    setUp(() async {
      ordner = await Directory.systemTemp.createTemp('pv_speicher_');
      sdb = Serverdatenbank.imSpeicher();
      final konten = Kontodienst(
        sdb,
        Tresorschluessel(List.filled(32, 7)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
        totpPflicht: false,
      );
      bibliotheken = Bibliotheken(
        wurzel: Directory('${ordner.path}/bibliotheken'),
        eingang: Directory('${ordner.path}/eingang'),
        ruhe: const Duration(hours: 1),
      );
      final konto = await konten.legeAn('erika', 'ein langes passwort');
      kopf = {
        'authorization':
            'Bearer ${konten.meldeAn(konto.id, 'Rechner', 'x').token}',
      };
      frei = 100 * gb;
      final w = Speicherwaechter(
        ordner,
        messung: (_) async => Speicherstand(gesamt: 200 * gb, frei: frei),
      );
      await w.pruefe();
      speicher = w;
      api = baueApi(konten: konten, bibliotheken: bibliotheken, speicher: w);
      addTearDown(() async {
        await bibliotheken.schliesseAlle();
        sdb.schliesse();
        await ordner.delete(recursive: true);
      });
    });

    Future<Response> frag(String methode, String pfad) async => api(
      Request(
        methode,
        Uri.parse('http://server/api/v1/$pfad'),
        headers: {
          ...kopf,
          'tus-resumable': '1.0.0',
          'upload-length': '10',
          'upload-metadata': 'filename ${base64.encode(utf8.encode('a.jpg'))}',
        },
      ),
    );

    test('der Stand für jedes angemeldete Gerät', () async {
      final r = await frag('GET', 'speicher');
      expect(r.statusCode, 200);
      final j = jsonDecode(await r.readAsString()) as Map;
      expect(j['stufe'], 'ausreichend');
      expect((j['gesamt'], j['frei']), (200 * gb, 100 * gb));
      expect(
        (await api(
          Request('GET', Uri.parse('http://server/api/v1/speicher')),
        )).statusCode,
        401,
        reason: 'nicht ohne Anmeldung',
      );
    });

    test('voll: Hochladen und Umzug weisen ab, sonst nichts', () async {
      expect((await frag('POST', 'hochladen')).statusCode, 201);
      frei = gb;
      await speicher.pruefe();
      final r = await frag('POST', 'hochladen');
      expect(r.statusCode, 507);
      expect(await r.readAsString(), contains('Speicher'));
      expect((await frag('PATCH', 'hochladen/x')).statusCode, 507);
      expect((await frag('POST', 'umzug/hochladen')).statusCode, 507);
      expect((await frag('GET', 'speicher')).statusCode, 200);
      expect((await frag('GET', 'bibliothek')).statusCode, 200);

      frei = 50 * gb;
      await speicher.pruefe();
      expect((await frag('POST', 'hochladen')).statusCode, 201);
    });
  });

  test('PV_SPEICHER_WARNUNG und PV_SPEICHER_MINDEST', () {
    final e = Einstellungen.ausUmgebung({
      'PV_DATEN': '/tmp/x',
      'PV_SPEICHER_WARNUNG': '90',
      'PV_SPEICHER_MINDEST': '5',
    });
    expect((e.speicherWarnung, e.speicherMindestGb), (0.9, 5));
    final vorgabe = Einstellungen.ausUmgebung({'PV_DATEN': '/tmp/x'});
    expect((vorgabe.speicherWarnung, vorgabe.speicherMindestGb), (0.85, 2));
    expect(
      () => Einstellungen.ausUmgebung({
        'PV_DATEN': '/tmp/x',
        'PV_SPEICHER_WARNUNG': '120',
      }),
      throwsArgumentError,
    );
  });
}

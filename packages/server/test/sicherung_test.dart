import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Die nächtliche Sicherung des Servers (Issue #125): verschlüsselt, nur
/// was am Ziel fehlt, nie ohne eingehängtes Ziel – und mit der App
/// wiederherstellbar.
void main() {
  const passphrase = 'eine lange passphrase';
  late Directory ordner;
  late Directory nas;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Tresorschluessel tresor;
  late Konto erika;
  late Serversicherung sicherung;
  var jetzt = DateTime(2026, 10, 15, 3, 30);

  Serversicherung neu({bool ohneZiel = false}) => Serversicherung(
    daten: Directory('${ordner.path}/daten'),
    ziel: ohneZiel ? null : nas,
    tresor: tresor,
    konten: konten,
    bibliotheken: bibliotheken,
    uhr: () => jetzt,
  );

  Future<void> foto(String name, int farbe) async {
    final f = File('${ordner.path}/quelle/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        img.encodeJpg(
          img.Image(width: 32, height: 24)
            ..clear(img.ColorRgb8(farbe, 40, 200 - farbe)),
        ),
      );
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    final r = await b.importe.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported, reason: '$name: ${r.error}');
  }

  Directory sicherungVon(Konto k) => Directory(
    '${nas.path}/${Serversicherung.ordnerFuer(k)}/PhotoVault-AutoBackup',
  );

  int verschluesselteDateien() =>
      Directory('${sicherungVon(erika).path}/data').listSync().length;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_sicherung_');
    nas = Directory('${ordner.path}/nas')..createSync();
    Directory('${ordner.path}/daten').createSync();
    sdb = Serverdatenbank.imSpeicher();
    tresor = Tresorschluessel(List.filled(32, 9));
    konten = Kontodienst(
      sdb,
      tresor,
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
    await foto('a.jpg', 10);
    await foto('b.jpg', 120);
    jetzt = DateTime(2026, 10, 15, 3, 30);
    sicherung = neu();
  });

  tearDown(() async {
    sicherung.beende();
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('ohne Ziel aus, ohne Passphrase nicht eingerichtet', () async {
    expect(await neu(ohneZiel: true).stufe(), Sicherungsstufe.aus);
    expect(await sicherung.stufe(), Sicherungsstufe.nichtEingerichtet);
    await expectLater(sicherung.einrichten('kurz'), throwsArgumentError);
    await sicherung.einrichten(passphrase);
    expect(
      File('${nas.path}/${Serversicherung.markeName}').existsSync(),
      isTrue,
    );
    await expectLater(sicherung.einrichten(passphrase), throwsStateError);
  });

  test('alles beim ersten Lauf, beim zweiten nichts noch einmal', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    var stand = await sicherung.stand();
    expect(stand['ok'], isTrue);
    expect((stand['konten']! as List).single, containsPair('neu', 2));
    expect(verschluesselteDateien(), 2);
    expect(File('${sicherungVon(erika).path}/vault.key').existsSync(), isTrue);
    expect(await sicherung.stufe(), Sicherungsstufe.ok);

    jetzt = jetzt.add(const Duration(days: 1));
    await sicherung.jetzt();
    stand = await sicherung.stand();
    expect((stand['konten']! as List).single, containsPair('neu', 0));

    // Die abgeglichene Markierung bleibt unberührt – sie gehört den Geräten.
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    expect(
      (await db.select(db.assets).get()).map((a) => a.autoBackedUp),
      everyElement(isFalse),
    );
  });

  test('ohne Kennmarke kein Byte, ein neues Ziel füllt sich wieder', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    // Das NAS ist weg: der Ordner leer, ohne Marke.
    nas.deleteSync(recursive: true);
    nas.createSync();
    await sicherung.jetzt();
    expect(nas.listSync(), isEmpty, reason: 'nichts auf die eigene Platte');
    expect(await sicherung.stufe(), Sicherungsstufe.zielFehlt);
    expect('${(await sicherung.stand())['fehler']}', contains('Kennmarke'));

    await sicherung.zielNeu();
    await sicherung.jetzt();
    expect(verschluesselteDateien(), 2);
    expect(await sicherung.stufe(), Sicherungsstufe.ok);
  });

  test('nach 36 Stunden ohne gelungenen Lauf: veraltet', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    jetzt = jetzt.add(const Duration(hours: 30));
    expect(await sicherung.stufe(), Sicherungsstufe.ok);
    jetzt = jetzt.add(const Duration(hours: 7));
    expect(await sicherung.stufe(), Sicherungsstufe.veraltet);
  });

  test('der nächste Lauf: heute um halb vier oder morgen', () {
    jetzt = DateTime(2026, 10, 15, 2);
    expect(sicherung.naechsterLauf(), DateTime(2026, 10, 15, 3, 30));
    jetzt = DateTime(2026, 10, 15, 3, 30);
    expect(sicherung.naechsterLauf(), DateTime(2026, 10, 16, 3, 30));
  });

  test(
    'mit der Passphrase lässt sie sich wie in der App zurückholen',
    () async {
      await sicherung.einrichten(passphrase);
      await sicherung.jetzt();

      final ziel = Directory('${ordner.path}/zurueck')..createSync();
      final db = await AppDatabase.open(ziel);
      addTearDown(db.close);
      final pfade = await StoragePaths.oeffne(
        Directory('${ziel.path}/library'),
      );
      await BackupService(db, pfade)
          .restoreFromBackup(
            sicherungVon(erika).path,
            ImportService(db, pfade),
            passphrase: passphrase,
          )
          .drain<void>();
      final quelle = (await bibliotheken.fuer(erika.id)).bibliothek;
      final vorher = {
        for (final a in await quelle.db.select(quelle.db.assets).get())
          a.checksum,
      };
      final nachher = {
        for (final a in await db.select(db.assets).get()) a.checksum,
      };
      expect(nachher, vorher);
      for (final a in await db.select(db.assets).get()) {
        expect(pfade.absolute(a.relativePath).existsSync(), isTrue);
      }

      await expectLater(
        BackupService(db, pfade)
            .restoreFromBackup(
              sicherungVon(erika).path,
              ImportService(db, pfade),
              passphrase: 'eine falsche passphrase',
            )
            .drain<void>(),
        throwsA(anything),
      );
    },
  );

  test('die Schnittstelle nur für Verwalter', () async {
    final max = await konten.legeAn('max', 'noch ein passwort');
    final api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      sicherung: sicherung,
    );
    Future<Response> frag(String m, String pfad, Konto k, [Object? j]) async =>
        api(
          Request(
            m,
            Uri.parse('http://server/api/v1/$pfad'),
            headers: {
              'authorization':
                  'Bearer ${konten.meldeAn(k.id, 'Rechner', 'x').token}',
            },
            body: j == null ? null : jsonEncode(j),
          ),
        );
    expect((await frag('GET', 'sicherung', max)).statusCode, 403);
    expect(
      (await frag('POST', 'sicherung/einrichten', max, {
        'passphrase': passphrase,
      })).statusCode,
      403,
    );
    final stand = await frag('GET', 'sicherung', erika);
    expect(
      (jsonDecode(await stand.readAsString()) as Map)['stufe'],
      'nichtEingerichtet',
    );
    final r = await frag('POST', 'sicherung/einrichten', erika, {
      'passphrase': passphrase,
    });
    expect(r.statusCode, 200);
    await sicherung.jetzt();
    expect(
      (await frag('POST', 'sicherung/einrichten', erika, {
        'passphrase': passphrase,
      })).statusCode,
      409,
    );
    expect((await frag('POST', 'sicherung/jetzt', erika)).statusCode, 202);
    await sicherung.jetzt();
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/umzug.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// Eine Bibliothek, die bisher nur auf einem Rechner lag, zieht auf den
/// Server (Stufe 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late HttpServer server;
  late Konto erika;
  late Serververbindung v;
  late AppDatabase rechner;
  late Directory rechnerOrdner;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_umzug_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 2)),
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
      '127.0.0.1',
      0,
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
    v = Serververbindung(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      konten.meldeAn(erika.id, 'Rechner', 'x').token,
    );

    // Die Bibliothek des Rechners: Datenbank, Originale, Miniaturen.
    rechnerOrdner = Directory('${ordner.path}/rechner/library');
    await rechnerOrdner.create(recursive: true);
    rechner = AppDatabase(
      NativeDatabase(File('${ordner.path}/rechner/library.sqlite')),
    );
    for (final id in ['a1', 'a2']) {
      await rechner
          .into(rechner.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/2025/01/$id.jpg',
              thumbnailRelativePath: Value('thumbnails/$id.jpg'),
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: DateTime(2025),
              importedAt: DateTime(2026),
            ),
          );
      await File('${rechnerOrdner.path}/originals/2025/01/$id.jpg')
          .create(recursive: true)
          .then((f) => f.writeAsBytes(utf8.encode('original $id')));
      await File('${rechnerOrdner.path}/thumbnails/$id.jpg')
          .create(recursive: true)
          .then((f) => f.writeAsBytes(utf8.encode('miniatur $id')));
    }
    await File('${rechnerOrdner.path}/.sperre').writeAsString('x');
    await rechner.fuehreAus(const BewertungSetzen(['a1'], 4));
    await rechner.fuehreAus(const PersonAnlegen('p1', 'Anna'));
    await rechner.fuehreAus(AlbumAnlegen('al1', 'Sommer', DateTime(2025, 7)));
    await rechner.fuehreAus(const AlbumFuellen('al1', ['a1', 'a2']));
  });

  tearDown(() async {
    v.schliesse();
    await rechner.close();
    await server.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('alles kommt an, und ein Gerät liest die Bibliothek danach', () async {
    final staende = await Umzug(
      v,
      rechner,
      rechnerOrdner,
      tus: TusHochladen(v, stueck: 4096),
    ).laufe().toList();
    expect(staende.last.fertig, isTrue);
    expect(staende.last.gesamt, greaterThan(0));

    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    expect((await b.db.assetsByIds(['a1'])).single.rating, 4);
    expect(await b.db.select(b.db.people).get(), hasLength(1));
    expect(
      await b.pfade.absolute('originals/2025/01/a2.jpg').readAsString(),
      'original a2',
    );
    expect(
      await b.pfade.absolute('.sperre').exists(),
      isFalse,
      reason: 'versteckte Dateien gehören nicht zur Bibliothek',
    );
    expect(
      Directory(bibliotheken.wurzel.path)
          .listSync()
          .map((e) => e.path.split('/').last)
          .any((n) => n.startsWith('${erika.id}.vor-umzug-')),
      isTrue,
      reason: 'die leere Bibliothek ist beiseitegelegt, nicht gelöscht',
    );

    // Ein Gerät verbindet sich und liest, was der Rechner hatte.
    final datei = File('${ordner.path}/telefon/library.sqlite');
    await Abgleich.holeAbzug(v, datei);
    final telefon = AppDatabase(NativeDatabase(datei));
    expect(
      {
        for (final z in await telefon.select(telefon.albumAssets).get())
          z.assetId,
      },
      {'a1', 'a2'},
    );
    await telefon.close();

    // Ein zweiter Umzug in dieselbe, jetzt volle Bibliothek: nein.
    await expectLater(
      Umzug(v, rechner, rechnerOrdner).laufe().toList(),
      throwsA(isA<Serverfehler>().having((f) => f.status, 'status', 409)),
    );
  });

  test(
    'ein unterbrochener Umzug lädt nicht noch einmal, was schon da ist',
    () async {
      await v.schicke('api/v1/umzug/beginnen', const {});
      final datei = File('${rechnerOrdner.path}/originals/2025/01/a1.jpg');
      await TusHochladen(v).lade(datei, 'api/v1/umzug/hochladen', {
        'pfad': 'originals/2025/01/a1.jpg',
        'sha256': (await sha256.bind(datei.openRead()).first).toString(),
      });
      final hochgeladen = <String>[];
      await for (final s in Umzug(v, rechner, rechnerOrdner).laufe()) {
        if (s.datei != null) hochgeladen.add(s.datei!);
      }
      expect(hochgeladen, isNot(contains('originals/2025/01/a1.jpg')));
      expect(hochgeladen, contains('originals/2025/01/a2.jpg'));
    },
  );

  test('eine Datei mit falscher Prüfsumme wird nicht angenommen', () async {
    await v.schicke('api/v1/umzug/beginnen', const {});
    final datei = File('${rechnerOrdner.path}/thumbnails/a1.jpg');
    final kopf = await TusHochladen(v).lade(datei, 'api/v1/umzug/hochladen', {
      'pfad': 'thumbnails/a1.jpg',
      'sha256': '0' * 64,
    });
    expect(kopf['pv-ausgang'], 'failed');
    final stand = await v.hole('api/v1/umzug/stand');
    expect(stand['dateien'], isEmpty);
  });
}

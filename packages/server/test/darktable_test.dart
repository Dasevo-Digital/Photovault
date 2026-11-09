import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

/// darktable-Bearbeitungen am Server rendern (#351), mit einem Ersatz für
/// `darktable-cli`: ein Skript, das seine Argumente mitschreibt und ein
/// fertiges Bild an die verlangte Stelle legt.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late HttpServer server;
  late Serververbindung v;
  late AppDatabase db;
  late File protokollDatei;
  late String id;
  const xmp = '<x:xmpmeta><darktable:history/></x:xmpmeta>';

  File ersatz(String rumpf) {
    final f = File('${ordner.path}/darktable-cli')
      ..writeAsStringSync('#!/bin/sh\n$rumpf\n');
    Process.runSync('chmod', ['+x', f.path]);
    return f;
  }

  Future<void> starte(DarktableEntwickler? d) async {
    final api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      darktable: d,
    );
    server = await shelf_io.serve(api, InternetAddress.loopbackIPv4, 0);
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    final token = konten.meldeAn(erika.id, 'Rechner', 'x').token;
    v = Serververbindung(Uri.parse('http://127.0.0.1:${server.port}/'), token);
    db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    final b = img.Image(width: 32, height: 24);
    final datei = File('${ordner.path}/foto.jpg')
      ..writeAsBytesSync(img.encodeJpg(b));
    final kopf = await TusHochladen(
      v,
    ).lade(datei, 'api/v1/hochladen', {'filename': 'foto.jpg'});
    id = kopf['pv-aufnahme']!;
  }

  Future<int> lege(String text) async => (await v.anfrage(
    'PUT',
    'api/v1/darktable/$id',
    inhalt: utf8.encode(text),
  )).statusCode;

  Future<String> warte() async {
    for (var i = 0; i < 100; i++) {
      final s = '${(await v.hole('api/v1/darktable/$id'))['stand']}';
      if (s != 'laeuft') return s;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return 'zeitueberschreitung';
  }

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_darktable_test_');
    protokollDatei = File('${ordner.path}/argumente');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 9)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    v.schliesse();
    await server.close(force: true);
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    ordner.deleteSync(recursive: true);
  });

  String gutes() {
    final bild = File('${ordner.path}/fertig.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 16, height: 12)));
    return 'echo "\$@" > ${protokollDatei.path}\ncp ${bild.path} "\$3"';
  }

  test('das Ergebnis wird die Entwicklung des Fotos', () async {
    await starte(DarktableEntwickler(finde: () async => ersatz(gutes()).path));
    expect(
      ((await v.hole('api/v1/zustand'))['funktionen'] as Map)['darktable'],
      1,
    );
    expect(await lege(xmp), 202);
    expect(await warte(), 'fertig');
    final a = (await db.assetById(id))!;
    expect(a.developedRelativePath, startsWith('developed/'));
    final args = protokollDatei.readAsStringSync();
    expect(args, contains('.xmp'));
    expect(args, contains(':memory:'));
    expect(args, contains('--core'));
    // Ohne Weiteres geht die Reihenfolge verloren: Eingabe, XMP, Ausgabe.
    final teile = args.split(' ');
    expect(teile[0], contains('originals'));
    expect(teile[1], endsWith('$id.xmp'));
    expect(teile[2], endsWith('ergebnis.jpg'));
  });

  test('eine zweite Bearbeitung ersetzt die erste', () async {
    await starte(DarktableEntwickler(finde: () async => ersatz(gutes()).path));
    await lege(xmp);
    await warte();
    final erste = (await db.assetById(id))!.developedRelativePath!;
    await lege(xmp);
    await warte();
    expect((await db.assetById(id))!.developedRelativePath, isNot(erste));
  });

  test('scheitert das Programm, bleibt das Foto, wie es war', () async {
    await starte(DarktableEntwickler(finde: () async => ersatz('exit 3').path));
    expect(await lege(xmp), 202);
    expect(await warte(), 'fehler');
    expect((await db.assetById(id))!.developedRelativePath, isNull);
  });

  test('ein hängender Lauf wird beendet', () async {
    await starte(
      DarktableEntwickler(
        finde: () async => ersatz('exec sleep 30').path,
        frist: const Duration(milliseconds: 200),
      ),
    );
    await lege(xmp);
    expect(await warte(), 'fehler');
  });

  test('ohne Programm 501, und die Apps erfahren es', () async {
    await starte(DarktableEntwickler(finde: () async => null));
    expect(await lege(xmp), 501);
    expect(
      ((await v.hole('api/v1/zustand'))['funktionen'] as Map)['darktable'],
      0,
    );
    expect((await db.assetById(id))!.developedRelativePath, isNull);
  });

  test('fehlt die Datei des Programms, heisst das Fehler', () async {
    await starte(
      DarktableEntwickler(finde: () async => '/nicht/da/darktable-cli'),
    );
    expect(await lege(xmp), 202);
    expect(await warte(), 'fehler');
  });

  test('eine XMP-Datei ohne Bearbeitung wird nicht angenommen', () async {
    await starte(DarktableEntwickler(finde: () async => ersatz(gutes()).path));
    expect(await lege('<x:xmpmeta/>'), 422);
  });

  test('ein gesperrtes Foto und ein unbekanntes gehen nicht', () async {
    await starte(DarktableEntwickler(finde: () async => ersatz(gutes()).path));
    await db.customStatement('UPDATE assets SET is_locked = 1 WHERE id = ?', [
      id,
    ]);
    expect(await lege(xmp), 404);
    final r = await v.anfrage(
      'PUT',
      'api/v1/darktable/nicht-da',
      inhalt: utf8.encode(xmp),
    );
    expect(r.statusCode, 404);
  });
}

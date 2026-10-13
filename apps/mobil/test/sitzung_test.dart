import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/sitzung.dart';

/// Das Telefon gegen einen echten Server-Prozess aus packages/server:
/// anmelden, Bibliothek holen, Bilder bei Bedarf, Änderungen in beide
/// Richtungen, Neustart ohne Anmeldung, Abmelden.
///
/// Kein Widget-Test: Hier wird über HTTP geredet und auf der Platte
/// gearbeitet, und das kommt in der angehaltenen Zeit eines Widget-Tests
/// nie zurück.
void main() {
  late Directory ordner;
  late Directory telefon;
  late Process server;
  late Uri adresse;
  late String tokenRechner;
  late Sitzung sitzung;

  Future<String> anmelden(String geraet) async {
    final a = Anmeldung(adresse);
    final s = await a.anmelden('erika', 'ein langes passwort', geraet: geraet);
    a.schliesse();
    return (s as AnmeldungFertig).token;
  }

  File jpeg(String name, int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    return File(p.join(ordner.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(bild));
  }

  Future<void> hochladen(File datei) async {
    final v = Serververbindung(adresse, tokenRechner);
    try {
      await TusHochladen(
        v,
      ).lade(datei, 'api/v1/hochladen', {'filename': p.basename(datei.path)});
    } finally {
      v.schliesse();
    }
  }

  Future<Map<String, Object?>> aufServer(String id) async {
    final v = Serververbindung(adresse, tokenRechner);
    try {
      return await v.hole('api/v1/aufnahmen/$id');
    } finally {
      v.schliesse();
    }
  }

  Future<void> bis(Future<bool> Function() bedingung, String was) async {
    for (var i = 0; i < 150; i++) {
      if (await bedingung()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Nicht eingetreten: $was');
  }

  setUpAll(() async {
    ordner = Directory.systemTemp.createTempSync('pv_mobil_');
    telefon = Directory(p.join(ordner.path, 'telefon'));
    final umgebung = {
      'PV_DATEN': p.join(ordner.path, 'server'),
      'PV_PORT': '0',
      'PV_TOTP': 'frei',
    };
    const serverOrdner = '../../packages/server';
    final anlegen = await Process.start(
      'dart',
      [
        'run',
        'bin/photo_vault_server.dart',
        'konto',
        'anlegen',
        'erika',
        '--totp-spaeter',
      ],
      workingDirectory: serverOrdner,
      environment: umgebung,
    );
    anlegen.stdin.writeln('ein langes passwort');
    await anlegen.stdin.close();
    expect(await anlegen.exitCode, 0);

    server = await Process.start(
      'dart',
      ['run', 'bin/photo_vault_server.dart'],
      workingDirectory: serverOrdner,
      environment: umgebung,
    );
    final bereit = Completer<Uri>();
    server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((z) {
          final m = RegExp(r'auf (http://127\.0\.0\.1:\d+)').firstMatch(z);
          if (m != null && !bereit.isCompleted) {
            bereit.complete(Uri.parse('${m.group(1)}/'));
          }
        });
    server.stderr.drain<void>();
    adresse = await bereit.future.timeout(const Duration(seconds: 60));
    tokenRechner = await anmelden('Rechner');
    await hochladen(jpeg('strand.jpg', 30));

    sitzung = Sitzung(ordner: () async => telefon);
  });

  tearDownAll(() async {
    await sitzung.beende();
    server.kill(ProcessSignal.sigint);
    await server.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        server.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    ordner.deleteSync(recursive: true);
  });

  test('ohne Verbindung geht es zur Anmeldung', () async {
    await sitzung.starte();
    expect(sitzung.zustand, Sitzungszustand.abgemeldet);
  });

  test('verbinden holt die Bibliothek samt Fotos vom Rechner', () async {
    await sitzung.verbinde(
      server: adresse,
      konto: 'erika',
      geraet: 'Telefon',
      token: await anmelden('Telefon'),
    );
    expect(sitzung.zustand, Sitzungszustand.bereit);
    final zeilen = await sitzung.db.alleRasterzeilen();
    expect(zeilen.map((z) => z.originalFileName), ['strand.jpg']);
    expect(
      File(p.join(telefon.path, 'verbindung.json')).statSync().modeString(),
      'rw-------',
      reason: 'das Token gehört niemand anderem',
    );
  });

  test('Bilder kommen erst, wenn man sie ansieht, und bleiben', () async {
    final z = (await sitzung.db.alleRasterzeilen()).single;
    final hier = sitzung.paths.absolute(z.thumbnailRelativePath!);
    expect(hier.existsSync(), isFalse);
    final datei = await sitzung.paths.bereit(z.thumbnailRelativePath!);
    expect(await datei.length(), greaterThan(0));
    expect(hier.existsSync(), isTrue);

    final original = await sitzung.paths.bereit(z.relativePath);
    expect(
      await original.readAsBytes(),
      File(p.join(ordner.path, 'eingang', 'strand.jpg')).readAsBytesSync(),
    );
  });

  test('ein Favorit hier landet auf dem Server', () async {
    final z = (await sitzung.db.alleRasterzeilen()).single;
    await sitzung.db.fuehreAus(FavoritSetzen([z.id], true));
    await bis(
      () async => (await aufServer(z.id))['isFavorite'] == true,
      'Favorit auf dem Server',
    );
    await bis(
      () async => (sitzung.abgleichszustand?.ausstehend ?? -1) == 0,
      'nichts mehr ausstehend',
    );
  });

  test('ein neues Foto vom Rechner erscheint von selbst', () async {
    final strom = sitzung.db.watchRasterzeilen();
    final kommt = strom.firstWhere((l) => l.length == 2);
    await hochladen(jpeg('hafen.jpg', 200));
    final zeilen = await kommt.timeout(const Duration(seconds: 15));
    expect(zeilen.map((z) => z.originalFileName), contains('hafen.jpg'));
  });

  test('ohne Modell auf dem Server sucht das Telefon im Text', () async {
    expect(await sitzung.textvektor('Strand'), isNull);
    final ids = await sitzung.db.textfundstellen('Stra');
    final treffer = await sitzung.db.searchAssets(
      const SearchFilters(),
      restrictToIds: ids,
    );
    expect(treffer.map((a) => a.originalFileName), ['strand.jpg']);
  });

  test('nach einem Neustart ist die Kopie ohne Anmeldung da', () async {
    await sitzung.beende();
    sitzung = Sitzung(ordner: () async => telefon);
    await sitzung.starte();
    expect(sitzung.zustand, Sitzungszustand.bereit);
    expect(await sitzung.db.alleRasterzeilen(), hasLength(2));
    expect(sitzung.verbindung!.geraet, 'Telefon');
  });

  test('abmelden löscht die Kopie und das Token gilt nicht mehr', () async {
    final token = sitzung.verbindung!.token;
    await sitzung.abmelden();
    expect(sitzung.zustand, Sitzungszustand.abgemeldet);
    expect(telefon.existsSync(), isFalse);

    final v = Serververbindung(adresse, token);
    try {
      await expectLater(
        v.hole('api/v1/aufnahmen'),
        throwsA(isA<Serverfehler>().having((f) => f.status, 'status', 401)),
      );
    } finally {
      v.schliesse();
    }
  });
}

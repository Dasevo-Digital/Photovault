import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:kern/abgleich/abgleich.dart';
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
}

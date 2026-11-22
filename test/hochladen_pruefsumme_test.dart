import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Verbunden ohne Importplan (überwachter Ordner, Hineinziehen): Was die
/// Kopie schon kennt, geht nicht noch einmal zum Server, und was hochgeht,
/// trägt seine Prüfsumme (#424).
void main() {
  late Directory temp;
  late AppDatabase db;
  late LibraryState lib;
  late List<http.Request> anfragen;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_hochladen_summe_');
    db = AppDatabase(NativeDatabase.memory());
    anfragen = [];
    final verbindung = Serververbindung(
      Uri.parse('http://server/'),
      'probe',
      client: MockClient((r) async {
        anfragen.add(r);
        // Kein Grund für neue Versuche: Der Test braucht nur die Anfrage.
        return http.Response('abgelehnt', 400);
      }),
    );
    lib = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'library')),
      )
      ..verbindung = Verbindungsdatei(
        server: Uri.parse('http://server/'),
        konto: 'probe',
        geraet: 'Rechner',
        token: 'probe',
      )
      ..abgleich = Abgleich(db, verbindung);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  File datei(String name, int fuellung) =>
      File(p.join(temp.path, name))
        ..writeAsBytesSync(List.filled(256, fuellung));

  Iterable<http.Request> uploads() => anfragen.where(
    (r) => r.method == 'POST' && r.url.path.endsWith('/hochladen'),
  );

  test('eine Datei, die die Kopie schon kennt, geht nicht hoch', () async {
    final f = datei('schon_da.jpg', 7);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'vorhanden',
        originalFileName: 'schon_da.jpg',
        relativePath: 'originals/schon_da.jpg',
        checksum: sha256.convert(f.readAsBytesSync()).toString(),
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );

    final stand = await lib.importFiles([f.path]).toList();

    expect(
      uploads(),
      isEmpty,
      reason: 'bisher ging jede Datei ganz zum Server, erst der verwarf sie',
    );
    expect(stand.last.duplikat, isTrue);
    expect(stand.last.gescheitert, isFalse);
  });

  test('eine neue Datei geht mit ihrer Prüfsumme hoch', () async {
    final f = datei('neu.jpg', 9);

    await lib.importFiles([f.path]).toList();

    final kopf = uploads().single.headers['upload-metadata']!;
    final angaben = {
      for (final teil in kopf.split(','))
        teil.split(' ').first: utf8.decode(base64.decode(teil.split(' ')[1])),
    };
    expect(angaben['sha256'], sha256.convert(f.readAsBytesSync()).toString());
  });
}

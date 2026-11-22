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
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Am verbundenen Rechner wird, was vom Server kommt, nicht mehr für immer
/// liegen gelassen (#432): Eine Sicherung holt Originale nur für die
/// Dauer des Schreibens, und der Zwischenspeicher bleibt unter seiner
/// Grenze wie am Handy.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late Directory server;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_zw_rechner_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    server = Directory(p.join(temp.path, 'server'))..createSync();
    // Wie Dateibeschaffung: Was fehlt, kommt vom Server und bleibt liegen.
    paths.beschaffe = (relativ) async {
      final ziel = paths.absolute(relativ);
      await ziel.parent.create(recursive: true);
      await File(p.join(server.path, relativ)).copy(ziel.path);
    };
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  /// Eine Aufnahme, deren Original am Server liegt.
  Future<String> aufnahme(String id, int fuellung) async {
    final relativ = 'originals/2026/01/$id.jpg';
    final bytes = List.filled(512, fuellung);
    File(p.join(server.path, relativ))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: relativ,
        checksum: sha256.convert(bytes).toString(),
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
    return relativ;
  }

  group('Sicherung aus der verbundenen Kopie', () {
    test('holt Originale nur für das Schreiben', () async {
      final geholt = await aufnahme('a', 1);
      final schonDa = await aufnahme('b', 2);
      await paths.bereit(schonDa);

      final lauf = await BackupService(
        db,
        paths,
      ).performBackup(p.join(temp.path, 'ziel')).toList();

      expect(lauf.last.done, 2);
      final kopien = Directory(p.join(temp.path, 'ziel'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'));
      expect(kopien, hasLength(2), reason: 'beide sind gesichert');
      expect(
        paths.absolute(geholt).existsSync(),
        isFalse,
        reason: 'bisher blieb jedes geholte Original in der Kopie liegen',
      );
      expect(
        paths.absolute(schonDa).existsSync(),
        isTrue,
        reason: 'was schon da war, bleibt',
      );
    });

    test('ebenso die automatische, verschlüsselte', () async {
      final geholt = await aufnahme('c', 3);
      final key = await VaultCrypto.createMasterKey('synthetischer-schluessel');

      await BackupService(db, paths)
          .performAutoBackup(p.join(temp.path, 'ziel'), key.masterKey)
          .drain<void>();

      expect(paths.absolute(geholt).existsSync(), isFalse);
      expect(
        Directory(p.join(temp.path, 'ziel', BackupService.autoBackupFolderName))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.contains('${p.separator}data${p.separator}')),
        isNotEmpty,
      );
    });
  });

  group('Zwischenspeicher am Rechner', () {
    late LibraryState lib;

    setUp(() {
      lib = LibraryState()
        ..db = db
        ..paths = paths
        ..abgleich = Abgleich(
          db,
          Serververbindung(
            Uri.parse('http://server/'),
            'probe',
            client: MockClient((_) async => http.Response('', 404)),
          ),
        );
    });

    Verbindungsdatei verbindung({int? mb}) => Verbindungsdatei(
      server: Uri.parse('http://server/'),
      konto: 'probe',
      geraet: 'Rechner',
      token: 'probe',
      zwischenspeicherMb: mb,
    );

    File geholt(String relativ, int mb, DateTime zuletzt) =>
        paths.absolute(relativ)
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(mb * 1024 * 1024, 1))
          ..setLastModifiedSync(zuletzt);

    test('bleibt unter seiner Grenze, das Älteste geht zuerst', () async {
      lib.verbindung = verbindung(mb: 2);
      final alt = geholt('originals/alt.jpg', 1, DateTime(2026, 1));
      final mittel = geholt('previews/mittel.jpg', 1, DateTime(2026, 2));
      final neu = geholt('originals/neu.jpg', 1, DateTime(2026, 3));

      await lib.pflegeZwischenspeicher();

      // Auf vier Fünftel der Grenze herunter: 1 von 3 MB bleibt.
      expect(alt.existsSync(), isFalse);
      expect(mittel.existsSync(), isFalse);
      expect(neu.existsSync(), isTrue, reason: 'zuletzt gebraucht');
    });

    test('ohne eigene Grenze gilt die Vorgabe des Handys', () async {
      lib.verbindung = verbindung();
      final f = geholt('originals/a.jpg', 1, DateTime(2026, 1));

      await lib.pflegeZwischenspeicher();

      expect(f.existsSync(), isTrue, reason: '1 MB liegt unter 2048 MB');
    });

    test('was im Entwickeln offen ist, bleibt', () async {
      lib.verbindung = verbindung(mb: 1);
      final relativ = await aufnahme('offen', 4);
      final offen = geholt(relativ, 1, DateTime(2025));
      final anderes = geholt('previews/x.jpg', 1, DateTime(2026));
      paths.offeneArbeitsvorschauen.add('offen');

      await lib.pflegeZwischenspeicher();

      expect(offen.existsSync(), isTrue);
      expect(anderes.existsSync(), isFalse);
    });
  });
}

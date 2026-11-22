import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/kopie_neu_laden.dart';

/// „Datenbank zurücksetzen“ in einer verbundenen Bibliothek (GRU-145):
/// Die Kopie entsteht neu aus einem Abzug des Servers, Verbindung und
/// Anmeldung bleiben, und was nur auf diesem Gerät gilt, geht nicht
/// verloren – vor allem nicht der Schlüssel des Tresors.
void main() {
  late Directory wurzel;
  late File verbindung;
  late File ablage;

  Future<void> lege(
    File datei,
    String aufnahme,
    Future<void> Function(AppDatabase db) mehr,
  ) async {
    final db = AppDatabase(NativeDatabase(datei));
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: aufnahme,
            originalFileName: '$aufnahme.jpg',
            relativePath: 'originals/$aufnahme.jpg',
            checksum: 'c_$aufnahme',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
          ),
        );
    await mehr(db);
    await db.close();
  }

  Future<T> lies<T>(Future<T> Function(AppDatabase db) was) async {
    final db = AppDatabase(
      NativeDatabase(File(p.join(wurzel.path, 'library.sqlite'))),
    );
    try {
      return await was(db);
    } finally {
      await db.close();
    }
  }

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_kopie_');
    verbindung = File(p.join(wurzel.path, 'verbindung.json'))
      ..writeAsStringSync('{"konto":"k"}');
    ablage = File(p.join(wurzel.path, 'library', 'thumbnails', 'a.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    await lege(File(p.join(wurzel.path, 'library.sqlite')), 'alt', (db) async {
      await db.saveVaultKey(
        kdfSalt: Uint8List.fromList(List.filled(16, 1)),
        nonce: Uint8List.fromList(List.filled(12, 2)),
        wrapped: Uint8List.fromList(List.filled(48, 3)),
      );
      await db.setThemeMode('dark');
      await db.setAutoBackupConfig(enabled: true, destination: '/ziel');
    });
  });

  tearDown(() => wurzel.deleteSync(recursive: true));

  Future<void> abzug(File ziel) => lege(ziel, 'vom_server', (db) async {
    // Der Abzug bringt seine eigene Zeile mit – ohne Tresorschlüssel, wie
    // beim Server, und mit der Vorgabe für die Ansicht.
    await db.setAutoAnalyzeAfterImport(false);
  });

  test(
    'die Kopie kommt neu vom Server, Verbindung und Gerätedaten bleiben',
    () async {
      var geschlossen = false;
      await ladeKopieNeu(
        wurzel,
        holeAbzug: abzug,
        vorDemTausch: () async => geschlossen = true,
      );

      expect(geschlossen, isTrue);
      final ids = await lies(
        (db) async => (await db.select(db.assets).get()).map((a) => a.id),
      );
      expect(ids, ['vom_server'], reason: 'die alte Kopie ist ersetzt');
      expect(verbindung.existsSync(), isTrue, reason: 'weiter verbunden');
      expect(ablage.existsSync(), isFalse, reason: 'Vorschauen kommen neu');
      expect(
        File(p.join(wurzel.path, 'library.sqlite.neu')).existsSync(),
        isFalse,
      );

      final tresor = await lies((db) => db.privacySettingsRow());
      expect(tresor?.wrappedMasterKey, List.filled(48, 3));
      expect(tresor?.kdfSalt, List.filled(16, 1));
      final app = await lies(
        (db) => (db.select(
          db.appSettings,
        )..where((t) => t.id.equals(0))).getSingle(),
      );
      expect(app.themeMode, 'dark', reason: 'gilt nur auf diesem Gerät');
      expect(app.autoAnalyzeAfterImport, isFalse, reason: 'kommt vom Server');
      final sicherung = await lies((db) => db.backupSettingsRow());
      expect(sicherung?.autoBackupDestination, '/ziel');
    },
  );

  test('ohne Server bleibt alles, wie es war', () async {
    var geschlossen = false;
    await expectLater(
      ladeKopieNeu(
        wurzel,
        holeAbzug: (_) async => throw const SocketException('weg'),
        vorDemTausch: () async => geschlossen = true,
      ),
      throwsA(isA<SocketException>()),
    );
    expect(geschlossen, isFalse);
    final ids = await lies(
      (db) async => (await db.select(db.assets).get()).map((a) => a.id),
    );
    expect(ids, ['alt']);
    expect(ablage.existsSync(), isTrue);
  });
}

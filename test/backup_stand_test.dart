import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/backup_stand.dart';

/// Wie viel des automatischen Backups im Ziel liegt und wie viel aussteht
/// (#303). Gezählt wird im Ziel: Die Markierung an der Aufnahme sagte nach
/// einem Zielwechsel „alles gesichert“ zu einem leeren Ordner.
void main() {
  const groesse = 64 * 1024;

  group('im Ziel gezählt', () {
    late Directory temp;
    late AppDatabase db;
    late BackupService dienst;
    late SecretKey schluessel;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pv_stand_');
      db = AppDatabase(NativeDatabase.memory());
      final pfade = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'library')),
      );
      dienst = BackupService(db, pfade);
      final w = await VaultCrypto.createMasterKey('synthetische-passphrase');
      schluessel = w.masterKey;
      await db.saveBackupKey(
        kdfSalt: w.kdfSalt,
        nonce: w.nonce,
        wrapped: w.wrapped,
      );
      final importe = ImportService(db, pfade);
      for (var i = 0; i < 4; i++) {
        final f = File(p.join(temp.path, 'bild-$i.jpg'))
          ..writeAsBytesSync(List.filled(groesse, i));
        await importe.importFile(f.path);
      }
    });
    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    Directory ordner(String name) =>
        Directory(p.join(temp.path, name))..createSync();

    String wurzel(Directory ziel) =>
        p.join(ziel.path, BackupService.autoBackupFolderName);

    test('die Grenze lässt aus: gezählt und gemerkt, mit Menge', () async {
      final a = ordner('platte');
      final verlauf = await dienst
          .performAutoBackup(a.path, schluessel, maxBytesPerRun: 1)
          .toList();

      final grenze = verlauf.lastWhere((f) => f.grenzeOffen != null);
      expect(grenze.grenzeOffen, 3);
      expect(grenze.grenzeOffenBytes, 3 * groesse);

      final s = await dienst.sicherungsstand(a.path, schluessel);
      expect(s.gesichert, 1);
      expect(s.gesichertBytes, groesse);
      expect(s.offen, 3);
      expect(s.offenBytes, 3 * groesse);
      expect(s.vollstaendig, isFalse);
      expect(s.anteil, 0.25);

      // Ohne Schlüssel bleibt, was der Lauf gesehen hat.
      final g = (await dienst.letzterStand(wurzel(a)))!;
      expect((g.gesichert, g.offen), (1, 3));
      expect((g.gesichertBytes, g.offenBytes), (groesse, 3 * groesse));
    });

    test('der Fortschritt zählt die Menge mit', () async {
      final a = ordner('platte');
      final verlauf = await dienst
          .performAutoBackup(a.path, schluessel)
          .toList();
      final mit = verlauf.where((f) => f.gesamtBytes != null).toList();
      expect(mit.first.gesichertBytes, 0);
      expect(mit.last.gesichertBytes, 4 * groesse);
      expect(mit.last.gesamtBytes, 4 * groesse);

      final s = await dienst.sicherungsstand(a.path, schluessel);
      expect(s.vollstaendig, isTrue);
      expect(s.gesamt, 4);
      expect(s.gesamtBytes, 4 * groesse);
      expect((await dienst.letzterStand(wurzel(a)))!.vollstaendig, isTrue);
    });

    test('Papierkorb und Gesperrtes zählen nicht', () async {
      final a = ordner('platte');
      await dienst.performAutoBackup(a.path, schluessel).drain<void>();
      final zeilen = await db.select(db.assets).get();
      await db.moveToTrash([zeilen[0].id]);
      await (db.update(db.assets)..where((t) => t.id.equals(zeilen[1].id)))
          .write(const AssetsCompanion(isLocked: Value(true)));
      final s = await dienst.sicherungsstand(a.path, schluessel);
      expect((s.gesichert, s.offen), (2, 0));
    });

    test(
      'ein neues Ziel ist leer, auch wenn die Markierung anderes sagt',
      () async {
        final a = ordner('alt'), b = ordner('neu');
        await dienst.performAutoBackup(a.path, schluessel).drain<void>();
        expect(await db.assetsNotAutoBackedUp(), isEmpty);

        final s = await dienst.sicherungsstand(b.path, schluessel);
        expect((s.gesichert, s.offen), (0, 4));
        expect(await dienst.letzterStand(wurzel(b)), isNull);
      },
    );

    test('ein anderer Schlüssel findet dort nichts', () async {
      final a = ordner('platte');
      await dienst.performAutoBackup(a.path, schluessel).drain<void>();
      final fremd = await VaultCrypto.createMasterKey('andere-passphrase');
      final s = await dienst.sicherungsstand(a.path, fremd.masterKey);
      expect(s.gesichert, 0);
    });

    test('eine fehlende Platte ist kein leeres Backup', () async {
      await expectLater(
        dienst.sicherungsstand(p.join(temp.path, 'abgesteckt'), schluessel),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('Anzeige', () {
    Sicherungsstand stand({int offen = 0}) => Sicherungsstand(
      am: DateTime(2026, 11, 5, 10),
      gesichert: 12300,
      gesichertBytes: 1024 * 1024 * 1024,
      offen: offen,
      offenBytes: offen == 0 ? 0 : 512 * 1024 * 1024,
    );

    Future<void> zeige(
      WidgetTester tester, {
      required bool entsperrt,
      Future<Sicherungsstand?> Function(String)? zaehle,
      Future<Sicherungsstand?> Function(String)? gemerkt,
      VoidCallback? entsperren,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: BackupStandAnzeige(
              ziel: '/ziel',
              letzterLauf: null,
              entsperrt: entsperrt,
              zaehle: zaehle ?? (_) async => null,
              gemerkt: gemerkt ?? (_) async => null,
              entsperren: entsperren,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('entsperrt: gesichert und ausstehend, mit Menge', (t) async {
      await zeige(t, entsperrt: true, zaehle: (_) async => stand(offen: 700));
      expect(find.textContaining('12.300 von 13.000 Dateien'), findsOneWidget);
      expect(find.textContaining('Ausstehend: 700 Dateien'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Neu zählen'), findsOneWidget);
    });

    testWidgets('alles da', (t) async {
      await zeige(t, entsperrt: true, zaehle: (_) async => stand());
      expect(find.textContaining('Alles gesichert: 12.300'), findsOneWidget);
      expect(find.textContaining('Ausstehend'), findsNothing);
    });

    testWidgets('gesperrt: der gemerkte Stand mit Datum', (t) async {
      var zaehlte = false;
      await zeige(
        t,
        entsperrt: false,
        zaehle: (_) async {
          zaehlte = true;
          return null;
        },
        gemerkt: (_) async => stand(offen: 1),
        entsperren: () {},
      );
      expect(zaehlte, isFalse);
      expect(find.textContaining('Ausstehend: 1 Datei ('), findsOneWidget);
      expect(find.textContaining('Stand vom'), findsOneWidget);
      expect(find.text('Entsperren'), findsOneWidget);
    });

    testWidgets('gesperrt und noch kein Lauf', (t) async {
      await zeige(t, entsperrt: false);
      expect(find.textContaining('Zum Zählen'), findsOneWidget);
    });

    testWidgets('das Ziel fehlt: kein „0 gesichert“', (t) async {
      await zeige(
        t,
        entsperrt: true,
        zaehle: (_) async => throw const FileSystemException('weg'),
      );
      expect(find.textContaining('nicht erreichbar'), findsOneWidget);
      expect(find.textContaining('Gesichert'), findsNothing);
    });
  });
}

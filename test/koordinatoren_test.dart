import 'dart:async';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_koordinator.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/services/backup_koordinator.dart';
import 'package:photo_vault/services/backup_service.dart';

class _Sicherung extends BackupService {
  _Sicherung(super.db, super.paths);
  int aufrufe = 0;
  final gestartet = Completer<void>();
  Completer<void>? freigabe;
  bool? markiert;
  int? budget;
  BackupProbeErgebnis probe = BackupProbeErgebnis(
    am: DateTime(2026),
    erfolgreich: true,
    originale: 0,
    gesamt: 0,
    datenbank: true,
  );
  @override
  Stream<BackupProgress> performAutoBackup(
    String ziel,
    SecretKey key, {
    int maxBytesPerRun = 0,
    bool markieren = true,
  }) async* {
    aufrufe++;
    markiert = markieren;
    budget = maxBytesPerRun;
    if (!gestartet.isCompleted) gestartet.complete();
    await freigabe?.future;
    yield BackupProgress(0, 0, wiederherstellungsprobe: probe);
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late _Sicherung service;
  late BackupKoordinator backup;
  late List<Backupwarnung?> warnungen;
  final jetzt = DateTime(2026, 10, 29, 12);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_koordinator_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    service = _Sicherung(db, paths);
    warnungen = [];
    backup = BackupKoordinator(
      db: db,
      backupService: service,
      istVerbunden: () => true,
      meldeWarnung: warnungen.add,
      meldeProbe: (_) {},
      oeffneZiel: (p) async => p,
      jetzt: () => jetzt,
    );
    await db.setAutoBackupConfig(
      enabled: true,
      destination: '${temp.path}/ziel',
      intervalHours: 24,
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  test(
    'Fälligkeit und fehlender Sitzungsschlüssel sind unabhängig von Widgets',
    () async {
      await db.setLastAutoBackupAt(jetzt);
      await backup.runAutoBackupIfDue();
      expect(service.aufrufe, 0);
      expect(warnungen, isEmpty);
      await db.setLastAutoBackupAt(jetzt.subtract(const Duration(days: 2)));
      await backup.runAutoBackupIfDue();
      expect(warnungen.last?.grund, Backuphindernis.passphrase);
      expect(service.aufrufe, 0);
    },
  );
  test(
    'Schlüssel lässt sich sperren und aus derselben Datenbank erneut öffnen',
    () async {
      await backup.setupBackupPassphrase('synthetische-koordinator-passphrase');
      expect(backup.backupKeyAvailableThisSession, isTrue);
      backup.sperre();
      expect(backup.backupKeyAvailableThisSession, isFalse);
      await backup.unlockBackupKeyWithPassphrase(
        'synthetische-koordinator-passphrase',
      );
      expect(backup.backupKeyAvailableThisSession, isTrue);
      await backup.removeBackupEncryption();
      expect(backup.backupKeyAvailableThisSession, isFalse);
      expect(await db.hasBackupKey(), isFalse);
    },
  );
  test(
    'Parallele Auslöser schreiben keinen zweiten automatischen Stand',
    () async {
      await backup.setupBackupPassphrase('synthetische-koordinator-passphrase');
      service.freigabe = Completer<void>();
      final erster = backup.runAutoBackupIfDue();
      await service.gestartet.future;
      await backup.runAutoBackupIfDue();
      await expectLater(
        backup.runAutoBackupNow('${temp.path}/ziel').toList(),
        throwsA(isA<BackupLaeuftBereits>()),
      );
      expect(service.aufrufe, 1);
      service.freigabe!.complete();
      await erster;
      expect((await db.backupSettingsRow())!.lastAutoBackupAt, jetzt);
    },
  );
  test(
    'Verbundene Sicherung reicht Zielprüfung und Mengenbudget weiter',
    () async {
      await db.setAutoBackupMaxMbPerRun(7);
      await backup.setupBackupPassphrase('synthetische-koordinator-passphrase');
      await backup.runAutoBackupNow('${temp.path}/ziel').drain<void>();
      expect(service.markiert, isFalse);
      expect(service.budget, 7 * 1024 * 1024);
      expect(warnungen.last, isNull);
    },
  );
  test(
    'passt kein Original ins Prüfbudget, gilt das automatische Backup als gelungen',
    () async {
      // SIC-057: Vorher scheiterte jeder Lauf mit „Bad state:
      // pv_probe_stichprobe_zu_gross“, und „Letzter Lauf“ blieb leer.
      service.probe = BackupProbeErgebnis(
        am: DateTime(2026),
        erfolgreich: false,
        originale: 0,
        gesamt: 1,
        datenbank: true,
        fehler: 'pv_probe_stichprobe_zu_gross',
      );
      await backup.setupBackupPassphrase('synthetische-koordinator-passphrase');
      await db.setLastAutoBackupAt(jetzt.subtract(const Duration(days: 2)));
      await backup.runAutoBackupIfDue();
      expect(service.aufrufe, 1);
      expect((await db.backupSettingsRow())!.lastAutoBackupAt, jetzt);
      expect(warnungen.last, isNull);

      final zeilen = await backup
          .runAutoBackupNow('${temp.path}/ziel')
          .toList();
      expect(zeilen.single.wiederherstellungsprobe?.uebersprungen, isTrue);
      expect(warnungen.last, isNull);
    },
  );
  test(
    'eine gescheiterte Probe lässt das automatische Backup scheitern',
    () async {
      service.probe = BackupProbeErgebnis(
        am: DateTime(2026),
        erfolgreich: false,
        originale: 0,
        gesamt: 1,
        datenbank: true,
        fehler: 'pv_probe_metadaten',
      );
      await backup.setupBackupPassphrase('synthetische-koordinator-passphrase');
      await db.setLastAutoBackupAt(jetzt.subtract(const Duration(days: 2)));
      await backup.runAutoBackupIfDue();
      expect(warnungen.last?.grund, Backuphindernis.fehlgeschlagen);
      expect(
        (await db.backupSettingsRow())!.lastAutoBackupAt,
        jetzt.subtract(const Duration(days: 2)),
      );
    },
  );
  test('Importkoordinator unterscheidet Import, Dublette und Fehler', () async {
    await db.fuehreAus(const AuswertenNachImportSetzen(true));
    final neu = File('${temp.path}/neu.jpg')..writeAsBytesSync([1, 2, 3]);
    final doppelt = File('${temp.path}/doppelt.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final nachlauf = <String>[];
    var analyse = 0;
    final k = ImportKoordinator(
      db: db,
      importe: ImportService(
        db,
        paths,
        bildwerkzeuge: const KeineBildwerkzeuge(),
      ),
      nachbearbeiten: (id, {regelnAnwenden = true}) async {
        nachlauf.add(id);
      },
      starteAnalyse: () async {
        analyse++;
      },
    );
    final lauf = await k.importiere([
      neu.path,
      doppelt.path,
      '${temp.path}/fehlt.jpg',
    ]).toList();
    expect(lauf[1].assetId, isNotNull);
    expect(lauf[2].duplikat, isTrue);
    expect(lauf[3].gescheitert, isTrue);
    expect(nachlauf, hasLength(1));
    expect(analyse, 1);
  });
}

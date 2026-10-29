import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/einstellungsstand.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

class _Ordnerdialog extends FilePickerPlatform {
  _Ordnerdialog(this.pfad);
  final String pfad;
  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => pfad;
}

class _BackupZaehler extends BackupService {
  _BackupZaehler(super.db, super.paths);
  var aufrufe = 0;
  String? letzterSnapshot;
  bool generationenVorhanden = true;
  RestoreErgebnis? ergebnis;
  @override
  Future<List<BackupGeneration>> autoBackupGenerations(String p) async =>
      generationenVorhanden
      ? [
          BackupGeneration(
            id: 'alt',
            createdAt: DateTime(2026),
            snapshotPath: '$p/generations/alt/library.sqlite.enc',
          ),
        ]
      : [];
  @override
  Stream<BackupProgress> restoreFromBackup(
    String root,
    ImportService imp, {
    String? passphrase,
    String? generationSnapshotPath,
    SecretKey? entschluesselungsschluessel,
    Set<String>? auswahlPruefsummen,
    bool streng = false,
    Directory? zwischenlager,
  }) async* {
    aufrufe++;
    letzterSnapshot = generationSnapshotPath;
    yield BackupProgress(1, 1, wiederherstellung: ergebnis);
  }
}

class _TestStand implements Einstellungsstand {
  _TestStand(this.library);
  @override
  final LibraryState library;
  late BuildContext context;
  @override
  BuildContext get kontext => context;
  @override
  BackupRecordData? get lastBackup => null;
  @override
  bool get encryptManualBackup => false;
  @override
  Future<void> refresh() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late _BackupZaehler backup;
  late LibraryState lib;
  late _TestStand stand;
  late FilePickerPlatform vorher;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_abbruch_probe_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    backup = _BackupZaehler(db, paths);
    lib = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = ImportService(
        db,
        paths,
        bildwerkzeuge: const KeineBildwerkzeuge(),
      )
      ..backupService = backup;
    stand = _TestStand(lib);
    vorher = FilePickerPlatform.instance;
    Directory('${temp.path}/backup/originals').createSync(recursive: true);
    FilePickerPlatform.instance = _Ordnerdialog('${temp.path}/backup');
  });
  tearDown(() async {
    FilePickerPlatform.instance = vorher;
    lib.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> oeffne(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (c) {
            stand.context = c;
            return Scaffold(
              body: SingleChildScrollView(child: SicherungVonHandGruppe(stand)),
            );
          },
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.settings_backup_restore));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Zurück aus der Generationenauswahl startet keinen Restore', (
    tester,
  ) async {
    await oeffne(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(backup.aufrufe, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Wegklicken der Generationenauswahl startet keinen Restore', (
    tester,
  ) async {
    await oeffne(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(backup.aufrufe, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Aktueller Stand ist eine ausdrückliche Auswahl', (tester) async {
    await oeffne(tester);
    final t = AppTexte.of(stand.context);
    await tester.runAsync(() async {
      await tester.tap(find.text(t.einstBackupAktuellerStand));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(backup.aufrufe, 1);
    expect(backup.letzterSnapshot, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Eine Generation reicht ihren eigenen Snapshot weiter', (
    tester,
  ) async {
    await oeffne(tester);
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.history),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(backup.aufrufe, 1);
    expect(
      backup.letzterSnapshot,
      endsWith('/generations/alt/library.sqlite.enc'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Ohne Generationen wird der aktuelle Stand direkt gewählt', (
    tester,
  ) async {
    backup.generationenVorhanden = false;
    await oeffne(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(backup.aufrufe, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Eine unvollständige Wiederherstellung zeigt einen Fehler', (
    tester,
  ) async {
    backup.generationenVorhanden = false;
    backup.ergebnis = RestoreErgebnis(
      geplant: 1,
      importiert: 0,
      vorhanden: 0,
      fehlend: 0,
      gescheitert: 1,
      abgeschlossen: true,
    );
    await oeffne(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(
      find.textContaining('Wiederherstellung unvollständig'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

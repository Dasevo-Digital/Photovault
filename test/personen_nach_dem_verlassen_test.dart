import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/state/library_state.dart';

/// Hält die erste Leseabfrage an und zählt, was danach noch gefragt wird.
class _Schleuse extends QueryInterceptor {
  final tor = Completer<void>();
  var angehalten = false;
  var zaehlen = false;
  var danach = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (zaehlen) danach++;
    if (!angehalten) {
      angehalten = true;
      await tor.future;
    }
    return executor.runSelect(statement, args);
  }
}

/// Der Personen-Reiter las seine Bestandsaufnahme als Kette von Abfragen
/// und fragte auch dann weiter, wenn er längst abgebaut war. Beim Abbau
/// einer Katalogprüfung (PER-108) traf so `countPeople` auf die schon
/// geschlossene Datenbank. Ein abgebauter Reiter soll nichts mehr fragen.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late _Schleuse schleuse;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_personen_ende_');
    schleuse = _Schleuse();
    db = AppDatabase(NativeDatabase.memory().interceptWith(schleuse));
    final paths = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'l')),
    );
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);
  });

  tearDown(() async {
    if (!schleuse.tor.isCompleted) schleuse.tor.complete();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('ein abgebauter Reiter fragt die Datenbank nicht weiter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(body: PeopleScreen(library: library)),
      ),
    );
    expect(schleuse.angehalten, isTrue, reason: 'die erste Abfrage wartet');

    await tester.pumpWidget(const SizedBox());
    // Drift räumt die Ströme des Bildschirms mit einem Nullzeitgeber ab.
    await tester.pump(const Duration(milliseconds: 1));
    schleuse.zaehlen = true;
    schleuse.tor.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 1));

    expect(schleuse.danach, 0, reason: 'Abfragen nach dem Abbau');
  });
}

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/state/library_state.dart';

/// Zählt, wie oft die Hauptansicht den Tresor sperren lässt.
class _ZaehlendeBibliothek extends LibraryState {
  int gesperrt = 0;

  @override
  Future<void> sperreTresor() async => gesperrt++;
}

/// Die Hauptansicht sperrt den Tresor, sobald das Fenster aus dem Blick
/// gerät (#400).
///
/// Der Wächter dafür war ein `late`-Feld, das erst `dispose` anlegte. Er
/// horchte darum nie, und ein verborgenes Fenster liess den gesperrten
/// Ordner offen. Die Regel selbst prüft `tresor_waechter_test.dart`; hier
/// geht es darum, dass sie in der laufenden App auch greift.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late _ZaehlendeBibliothek library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_tresor_shell_');
    db = AppDatabase(NativeDatabase.memory());
    library = _ZaehlendeBibliothek()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'lib')),
      );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  testWidgets('Verbergen des Fensters sperrt, Fokusverlust nicht', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: HomeShell(library: library),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(library.gesperrt, 0, reason: 'nur der Fokus ist weg');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(library.gesperrt, 1, reason: 'das Fenster ist verborgen');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(library.gesperrt, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

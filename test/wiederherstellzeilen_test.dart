import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Zeilen im Fenster „Wiederherstellen“.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  setUpAll(() => initializeDateFormatting());

  RestoreErgebnis ergebnis({required bool fertig}) => RestoreErgebnis(
    geplant: 2,
    importiert: 2,
    vorhanden: 0,
    fehlend: 0,
    gescheitert: 0,
    abgeschlossen: fertig,
  );

  // SIC-063: Die Übernahme aus dem Schnappschuss ist in Millisekunden
  // durch; ohne Pause stand ihre Zeile kürzer als ein Bild da.
  test(
    'die Übernahme aus dem Schnappschuss bleibt eine Weile stehen',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'pv_uebernahme_zeigen_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(
        Directory(p.join(temp.path, 'bibliothek')),
      );
      final vorher = LibraryState.uebernahmeZeigen;
      LibraryState.uebernahmeZeigen = const Duration(milliseconds: 300);
      addTearDown(() => LibraryState.uebernahmeZeigen = vorher);
      final lib = LibraryState()
        ..db = db
        ..paths = paths
        ..importService = ImportService(
          db,
          paths,
          bildwerkzeuge: const KeineBildwerkzeuge(),
        )
        ..backupService = _GestellteWiederherstellung(db, paths, [
          BackupProgress(2, 2, wiederherstellung: ergebnis(fertig: false)),
          BackupProgress(
            2,
            2,
            uebernommeneZeilen: 7,
            wiederherstellung: ergebnis(fertig: false),
          ),
          BackupProgress(
            2,
            2,
            uebernommeneZeilen: 7,
            wiederherstellung: ergebnis(fertig: true),
          ),
        ]);
      addTearDown(lib.dispose);

      final zeiten = <(BackupProgress, DateTime)>[];
      await lib
          .restoreFromBackup(temp.path)
          .forEach((e) => zeiten.add((e, DateTime.now())));

      expect(zeiten, hasLength(3));
      expect(zeiten[1].$1.uebernommeneZeilen, 7);
      expect(
        zeiten[2].$2.difference(zeiten[1].$2),
        greaterThanOrEqualTo(const Duration(milliseconds: 280)),
      );
      expect(
        zeiten[1].$2.difference(zeiten[0].$2),
        lessThan(const Duration(milliseconds: 200)),
        reason: 'nur die Zeile zur Übernahme wartet',
      );
    },
  );

  // Nebenbefund: Das Datum der Probe stand im Fortschrittsfenster der
  // Sicherung im US-Format („11/17/2026“), auch in deutscher Oberfläche.
  test('das Datum der Probe in der Sprache der Oberfläche', () {
    final probe = BackupProbeErgebnis(
      am: DateTime(2026, 11, 17, 9, 5),
      erfolgreich: true,
      originale: 3,
      gesamt: 3,
      datenbank: true,
    );
    final zeile = backupZeile(
      de,
      BackupProgress(1, 1, wiederherstellungsprobe: probe),
    );
    expect(zeile, contains('17.11.2026'));
    expect(zeile, isNot(contains('11/17/2026')));
  });
}

class _GestellteWiederherstellung extends BackupService {
  _GestellteWiederherstellung(super.db, super.paths, this.ereignisse);

  final List<BackupProgress> ereignisse;

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
  }) => Stream.fromIterable(ereignisse);
}

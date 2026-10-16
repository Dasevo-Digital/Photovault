part of '../database.dart';

/// Sicherung, ihre Verschlüsselung und die automatische Sicherung.
extension SicherungsAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Backup
  // -----------------------------------------------------------------------

  /// Gesperrte Fotos werden bewusst NIE ins (unverschlüsselte, oft in einen
  /// Cloud-Sync-Ordner zeigende) Backup aufgenommen – das würde den Zweck
  /// des gesperrten Ordners aushebeln.
  /// Die Aufnahmen, die in `metadata.json` beschrieben werden dürfen.
  ///
  /// **Dieselbe `isLocked`-Ausnahme wie bei [assetsNotBackedUp]**, und
  /// aus demselben Grund: Was nicht mitgesichert wird, soll auch nicht
  /// benannt werden. Ein Dateiname wie `Scheidungsurkunde_Anna.jpg` in
  /// einer unverschlüsselten Datei im Cloud-Ordner gibt genau das preis,
  /// wovor der gesperrte Ordner schützen soll.
  ///
  /// Papierkorb-Einträge bleiben **drin**: Ihre Dateien liegen aus
  /// früheren Läufen im Sicherungsziel, und wer sie später
  /// wiederherstellt, will seine Schlagwörter zurück.
  Future<List<AssetData>> assetsFuerMetadatenexport() =>
      (select(assets)..where((t) => t.isLocked.equals(false))).get();

  /// Welche dieser Kennungen als Aufnahmen da sind – nicht im Papierkorb.
  /// Fürs Freigeben von Speicher auf dem Telefon: Dort geht nur, was hier
  /// noch steht. In Stücken, weil SQLite die Platzhalter je Abfrage
  /// begrenzt.
  Future<Set<String>> vorhandeneAufnahmen(Iterable<String> ids) async {
    final liste = ids.toSet().toList();
    final da = <String>{};
    for (var i = 0; i < liste.length; i += 500) {
      final teil = liste.sublist(
        i,
        i + 500 > liste.length ? liste.length : i + 500,
      );
      final zeilen =
          await (selectOnly(assets)
                ..addColumns([assets.id])
                ..where(assets.id.isIn(teil) & assets.isTrashed.equals(false)))
              .get();
      for (final z in zeilen) {
        da.add(z.read(assets.id)!);
      }
    }
    return da;
  }

  Future<List<AssetData>> assetsNotBackedUp() =>
      (select(assets)..where(
            (t) =>
                t.backedUp.equals(false) &
                t.isTrashed.equals(false) &
                t.isLocked.equals(false),
          ))
          .get();

  Future<void> markBackedUp(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(backedUp: Value(true)),
      );

  Future<void> insertBackupRecord(BackupRecordsCompanion record) =>
      into(backupRecords).insert(record);

  Future<BackupRecordData?> lastBackupRecord() => (select(
    backupRecords,
  )..orderBy([(t) => OrderingTerm.desc(t.performedAt)])).getSingleOrNull();

  /// Schnelle SQLite-Eigenprüfung für die Zustandsübersicht. Anders als die
  /// vollständige Integritätsprüfung liest sie keine Mediendateien.
  Future<bool> databaseQuickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return rows.isNotEmpty &&
        rows.every((row) => row.data.values.singleOrNull == 'ok');
  }

  Future<int> countNotAutoBackedUp() => _countWhere(
    assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        assets.autoBackedUp.equals(false),
  );

  // -----------------------------------------------------------------------
  // Backup-Verschlüsselung + automatisches Backup
  // -----------------------------------------------------------------------
  //
  // Analog zum gesperrten Ordner: die eigentliche Kryptografie läuft über
  // VaultCrypto/LibraryState, hier wird nur der verpackte Backup-Master-Key
  // und die Konfiguration des automatischen Backups gespeichert.

  Future<bool> hasBackupKey() async {
    final row = await (select(
      backupSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.wrappedMasterKey != null;
  }

  Future<BackupSettingsData?> backupSettingsRow() =>
      (select(backupSettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> saveBackupKey({
    required Uint8List kdfSalt,
    required Uint8List nonce,
    required Uint8List wrapped,
  }) => into(backupSettings).insertOnConflictUpdate(
    BackupSettingsCompanion.insert(
      id: const Value(0),
      kdfSalt: Value(kdfSalt),
      wrappedMasterKeyNonce: Value(nonce),
      wrappedMasterKey: Value(wrapped),
    ),
  );

  /// Entfernt nur die lokale Einrichtung der Backup-Verschlüsselung –
  /// bereits vorhandene verschlüsselte Backups am Zielort bleiben davon
  /// unberührt (sie lassen sich weiterhin mit der Passphrase entschlüsseln,
  /// die App merkt sich nur den Schlüssel nicht mehr).
  Future<void> clearBackupKey() =>
      (update(backupSettings)..where((t) => t.id.equals(0))).write(
        const BackupSettingsCompanion(
          kdfSalt: Value(null),
          wrappedMasterKeyNonce: Value(null),
          wrappedMasterKey: Value(null),
        ),
      );

  /// [destination] und [intervalHours] werden nur geschrieben, wenn sie
  /// angegeben sind – `null` heißt "unverändert lassen", nicht "löschen".
  ///
  /// Vorher wurde das Ziel immer geschrieben: Ein Umstellen des Intervalls
  /// oder auch nur des Aktiv-Schalters übergab kein Ziel und löschte damit
  /// den zuvor gewählten Ordner, der dann erneut ausgewählt werden musste.
  /// Zum bewussten Entfernen gibt es [clearAutoBackupDestination].
  Future<void> setAutoBackupConfig({
    required bool enabled,
    String? destination,
    int? intervalHours,
  }) => into(backupSettings).insertOnConflictUpdate(
    BackupSettingsCompanion.insert(
      id: const Value(0),
      autoBackupEnabled: Value(enabled),
      autoBackupDestination: destination != null
          ? Value(destination)
          : const Value.absent(),
      autoBackupIntervalHours: intervalHours != null
          ? Value(intervalHours)
          : const Value.absent(),
    ),
  );

  Future<void> setAutoBackupMaxMbPerRun(int mb) =>
      into(backupSettings).insertOnConflictUpdate(
        BackupSettingsCompanion.insert(
          id: const Value(0),
          autoBackupMaxMbPerRun: Value(mb),
        ),
      );

  /// Entfernt das Sicherungsziel ausdrücklich (siehe [setAutoBackupConfig]).
  Future<void> clearAutoBackupDestination() =>
      (update(backupSettings)..where((t) => t.id.equals(0))).write(
        const BackupSettingsCompanion(autoBackupDestination: Value(null)),
      );

  Future<void> setLastAutoBackupAt(DateTime when) =>
      (update(backupSettings)..where((t) => t.id.equals(0))).write(
        BackupSettingsCompanion(lastAutoBackupAt: Value(when)),
      );

  /// Wie [assetsNotBackedUp], aber mit eigenem Tracking-Flag für das
  /// automatische Backup (siehe [Assets.autoBackedUp]).
  Future<List<AssetData>> assetsNotAutoBackedUp() =>
      (select(assets)..where(
            (t) =>
                t.autoBackedUp.equals(false) &
                t.isTrashed.equals(false) &
                t.isLocked.equals(false),
          ))
          .get();

  /// Alles, was eine Sicherung enthalten soll – ohne Rücksicht auf
  /// [Assets.autoBackedUp]. Für den Server, der am Ziel nachsieht, was schon
  /// da ist (siehe `BackupService.performAutoBackup`, `amZielPruefen`).
  Future<List<AssetData>> assetsFuerSicherung() => (select(
    assets,
  )..where((t) => t.isTrashed.equals(false) & t.isLocked.equals(false))).get();

  Future<void> markAutoBackedUp(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(autoBackedUp: Value(true)),
      );
}

import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'backup_service.dart';
import 'sicherungsziel.dart';
import 'vault_crypto.dart';

/// Schlüssel, Fälligkeit und Meldungen einer Sicherungssitzung gehören
/// zum selben Datenbankstand. Die Oberfläche bleibt beim Aufrufer.
class BackupKoordinator {
  BackupKoordinator({
    required this.db,
    required this.backupService,
    required this.istVerbunden,
    required this.meldeWarnung,
    required this.meldeProbe,
    Future<String> Function(String)? oeffneZiel,
    DateTime Function()? jetzt,
  }) : oeffneZiel = oeffneZiel ?? Sicherungsziel.oeffne,
       _jetzt = jetzt ?? DateTime.now;
  final AppDatabase db;
  final BackupService backupService;
  final bool Function() istVerbunden;
  bool get verbunden => istVerbunden();
  final void Function(Backupwarnung?) meldeWarnung;
  final void Function(BackupProbeErgebnis) meldeProbe;
  final Future<String> Function(String) oeffneZiel;
  final DateTime Function() _jetzt;
  void sperre() => _backupKey = null;

  SecretKey? _backupKey;
  bool _autoBackupRunning = false;
  bool get backupKeyAvailableThisSession => _backupKey != null;

  Future<void> setupBackupPassphrase(String passphrase) async {
    final wrapped = await VaultCrypto.createMasterKey(passphrase);
    await db.saveBackupKey(
      kdfSalt: wrapped.kdfSalt,
      nonce: wrapped.nonce,
      wrapped: wrapped.wrapped,
    );
    _backupKey = wrapped.masterKey;
  }

  Future<void> unlockBackupKeyWithPassphrase(String passphrase) async {
    final row = await db.backupSettingsRow();
    final kdfSalt = row?.kdfSalt;
    final nonce = row?.wrappedMasterKeyNonce;
    final wrapped = row?.wrappedMasterKey;
    if (kdfSalt == null || nonce == null || wrapped == null) {
      throw StateError('Keine Backup-Passphrase eingerichtet.');
    }
    _backupKey = await VaultCrypto.unwrapMasterKey(
      passphrase,
      kdfSalt: kdfSalt,
      nonce: nonce,
      wrapped: wrapped,
    );
  }

  Future<void> changeBackupPassphrase(String newPassphrase) async {
    final key = _backupKey;
    if (key == null) {
      throw StateError('Die Backup-Passphrase muss vorher entsperrt sein.');
    }
    final wrapped = await VaultCrypto.wrapMasterKey(key, newPassphrase);
    await db.saveBackupKey(
      kdfSalt: wrapped.kdfSalt,
      nonce: wrapped.nonce,
      wrapped: wrapped.wrapped,
    );
  }

  /// Entfernt nur die lokale Backup-Verschlüsselungs-Einrichtung – bereits
  /// bestehende verschlüsselte Backups am Zielort bleiben unangetastet
  /// (anders als beim gesperrten Ordner gibt es hier nichts "zu
  /// entschlüsseln", die Originaldateien in der Bibliothek selbst waren nie
  /// verschlüsselt).
  Future<void> removeBackupEncryption() async {
    await db.clearBackupKey();
    _backupKey = null;
  }

  /// Führt ein manuelles Backup aus – bei [encrypt] mit dem für diese
  /// Sitzung entsperrten Backup-Schlüssel (siehe [ensureBackupKeyAvailable]
  /// in pin_dialogs.dart, das der Aufrufer vorher ausgeführt haben muss).
  ///
  /// **Verbunden** (#206) sichert der Rechner die Bibliothek des Servers:
  /// Das Ziel entscheidet, was fehlt, und fehlende Originale kommen vom
  /// Server. Die Markierungen „gesichert“ stehen in `assets` und damit in
  /// einer abgeglichenen Tabelle – sie zu setzen bricht am Schutz
  /// `pv_nur_ueber_server` ab. Darum war die Sicherung hier vorher ganz
  /// gesperrt („Bad state: pv_nur_ueber_server“), und das automatische
  /// Backup lief verbunden gar nicht erst an.
  Stream<BackupProgress> runManualBackup(
    String destination, {
    required bool encrypt,
  }) async* {
    final grenze = await _backupGrenzeBytes();
    yield* backupService.performBackup(
      destination,
      encryptionKey: encrypt ? _backupKey : null,
      maxBytesPerRun: grenze,
      markieren: !verbunden,
    );
  }

  /// Portionsgrenze je Sicherungslauf in Bytes, 0 = unbegrenzt (siehe
  /// BackupSettings.autoBackupMaxMbPerRun).
  Future<int> _backupGrenzeBytes() async {
    final config = await db.backupSettingsRow();
    final mb = config?.autoBackupMaxMbPerRun ?? 0;
    return mb > 0 ? mb * 1024 * 1024 : 0;
  }

  /// Löst das automatische Backup unabhängig vom Intervall manuell aus
  /// (z.B. über den "Jetzt synchronisieren"-Button in den Einstellungen).
  /// Setzt voraus, dass die Backup-Passphrase für diese Sitzung bereits
  /// entsperrt ist.
  Stream<BackupProgress> runAutoBackupNow(String destination) async* {
    if (_autoBackupRunning) throw const BackupLaeuftBereits();
    _autoBackupRunning = true;
    try {
      final key = _backupKey;
      if (key == null) {
        throw StateError('Die Backup-Passphrase muss vorher entsperrt sein.');
      }
      // Unter macOS den Zugriff aus dem gemerkten Merkmal (#211). Nicht
      // `yield*`: Dessen Fehler gingen am `catch` vorbei.
      final ziel = await oeffneZiel(destination);
      try {
        // Verbunden: siehe [runManualBackup].
        await for (final f in backupService.performAutoBackup(
          ziel,
          key,
          maxBytesPerRun: await _backupGrenzeBytes(),
          markieren: !verbunden,
        )) {
          if (f.wiederherstellungsprobe case final probe?) {
            meldeProbe(probe);
            if (!probe.erfolgreich) {
              meldeWarnung((
                grund: Backuphindernis.fehlgeschlagen,
                letzterLauf: null,
                fehler: probe.fehler,
              ));
              throw StateError(probe.fehler ?? 'pv_probe_unlesbar');
            }
          }
          yield f;
        }
      } on FileSystemException catch (e) {
        if (Sicherungsziel.zugriffVerweigert(e)) {
          throw BackupZielGesperrt(destination);
        }
        rethrow;
      }
      await db.setLastAutoBackupAt(_jetzt());
      meldeWarnung(null);
    } finally {
      _autoBackupRunning = false;
    }
  }

  /// Prüft, ob das automatische Backup fällig ist (aktiviert, Ziel gesetzt,
  /// Intervall abgelaufen) und der Backup-Schlüssel für diese Sitzung
  /// bereits vorliegt – wenn nicht, wird NICHT nach der Passphrase gefragt
  /// (das würde unerwartet mitten in der Nutzung passieren), sondern der
  /// Lauf einfach übersprungen; die Einstellungen zeigen dann an, dass eine
  /// erneute Passphrase-Eingabe nötig ist. Läuft nur, solange die App offen
  /// ist – kein Hintergrunddienst, siehe Klassenkommentar in
  /// [BackupService.performAutoBackup].
  Future<void> runAutoBackupIfDue() async {
    if (_autoBackupRunning) return;
    _autoBackupRunning = true;
    try {
      await _wennFaellig();
    } finally {
      _autoBackupRunning = false;
    }
  }

  Future<void> _wennFaellig() async {
    final config = await db.backupSettingsRow();
    if (config == null || !config.autoBackupEnabled) return;
    final destination = config.autoBackupDestination;
    if (destination == null || destination.isEmpty) return;

    final lastRun = config.lastAutoBackupAt;
    if (lastRun != null) {
      final due = lastRun.add(Duration(hours: config.autoBackupIntervalHours));
      if (_jetzt().isBefore(due)) return;
    }

    final key = _backupKey;
    if (key == null) {
      // Passphrase muss erst wieder manuell entsperrt werden. Bis #207
      // geschah das wortlos: Das Backup blieb wochenlang aus, und nur die
      // Einstellungen hätten es gezeigt.
      meldeWarnung((
        grund: Backuphindernis.passphrase,
        letzterLauf: lastRun,
        fehler: null,
      ));
      return;
    }

    try {
      var ausfaelle = 0;
      await for (final f in backupService.performAutoBackup(
        // Unter macOS über das gemerkte Merkmal (#211).
        await oeffneZiel(destination),
        key,
        maxBytesPerRun: (config.autoBackupMaxMbPerRun > 0)
            ? config.autoBackupMaxMbPerRun * 1024 * 1024
            : 0,
        // Verbunden: siehe [runManualBackup].
        markieren: !verbunden,
      )) {
        ausfaelle = f.fehlgeschlagen ?? ausfaelle;
        if (f.wiederherstellungsprobe case final probe?) {
          meldeProbe(probe);
          if (!probe.erfolgreich) {
            throw StateError(probe.fehler ?? 'pv_probe_unlesbar');
          }
        }
      }
      await db.setLastAutoBackupAt(_jetzt());
      // Einzelne Dateien, die nicht gingen (verbunden etwa: Server kurz
      // weg), kommen beim nächsten Lauf wieder dran – gesagt wird es
      // trotzdem.
      meldeWarnung(
        ausfaelle == 0
            ? null
            : (
                grund: Backuphindernis.dateienFehlen,
                letzterLauf: _jetzt(),
                fehler: '$ausfaelle',
              ),
      );
    } catch (e) {
      protokoll('Automatisches Backup fehlgeschlagen: $e');
      meldeWarnung((
        grund: Sicherungsziel.zugriffVerweigert(e)
            ? Backuphindernis.zielGesperrt
            : Backuphindernis.fehlgeschlagen,
        letzterLauf: lastRun,
        fehler: '$e',
      ));
    }
  }
}

/// Warum das automatische Backup ausbleibt (siehe
/// [LibraryState.backupwarnung]).
enum Backuphindernis {
  /// Fällig, aber die Passphrase wurde in dieser Sitzung nicht eingegeben.
  passphrase,

  /// Gelaufen und gescheitert.
  fehlgeschlagen,

  /// Gelaufen, aber einzelne Dateien gingen nicht ([Backupwarnung.fehler]
  /// trägt ihre Zahl).
  dateienFehlen,

  /// Das Betriebssystem lässt nicht ins Ziel schreiben – unter macOS fehlt
  /// das Merkmal für den Ordner, er muss einmal neu gewählt werden (#211).
  zielGesperrt,
}

typedef Backupwarnung = ({
  Backuphindernis grund,
  DateTime? letzterLauf,
  String? fehler,
});

class BackupLaeuftBereits implements Exception {
  const BackupLaeuftBereits();
}

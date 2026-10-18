import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Was der Server über seine Nutzer weiss: Konten, angemeldete Geräte,
/// Wiederherstellungscodes, Verknüpfungen mit einem OIDC-Anbieter und die
/// Freigaben nach aussen.
///
/// Getrennt von den Bibliotheken (eine je Konto, Schema der App), weil es
/// keine Bibliothek gibt, zu der diese Daten gehören – und weil eine
/// Bibliothek sich so ohne Zugangsdaten sichern und weitergeben lässt.
///
/// SQLite ohne drift: wenige Tabellen, einfache Abfragen. Synchron, weil
/// jede Abfrage hier Mikrosekunden dauert; das Rechnen (Argon2id) liegt
/// nicht hier.
class Serverdatenbank {
  Serverdatenbank._(this.db);

  /// Öffnet `server.sqlite` in [datei] oder legt sie an und bringt das
  /// Schema auf den neuesten Stand.
  factory Serverdatenbank.oeffne(File datei) {
    datei.parent.createSync(recursive: true);
    // Nur für den Besitzer: Hier stehen die Prüfwerte der Passwörter und
    // Tokens. SQLite legt WAL und Sperrdatei mit denselben Rechten an.
    if (!datei.existsSync()) {
      datei.createSync();
      if (!Platform.isWindows) Process.runSync('chmod', ['600', datei.path]);
    }
    return Serverdatenbank._(sqlite3.open(datei.path)).._bereite();
  }

  /// Nur im Speicher – für Prüfstände.
  factory Serverdatenbank.imSpeicher() =>
      Serverdatenbank._(sqlite3.openInMemory()).._bereite();

  final Database db;

  static const schema = 2;

  void _bereite() {
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');
    // Die Verwaltung auf der Kommandozeile schreibt, während der Server
    // läuft: Wer gerade nicht darf, wartet kurz statt zu scheitern.
    db.execute('PRAGMA busy_timeout = 5000');
    final stand = db.select('PRAGMA user_version').single.columnAt(0) as int;
    if (stand > schema) {
      throw StateError(
        'server.sqlite hat Schema $stand, dieser Server kennt nur $schema – '
        'ein neuerer Server hat sie schon umgestellt.',
      );
    }
    if (stand < 1) {
      db.execute('''
        BEGIN;
        CREATE TABLE konten (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL UNIQUE COLLATE NOCASE,
          passwort TEXT,
          totp TEXT,
          totp_letzter_schritt INTEGER NOT NULL DEFAULT 0,
          verwalter INTEGER NOT NULL DEFAULT 0,
          fehlversuche INTEGER NOT NULL DEFAULT 0,
          gesperrt_bis INTEGER,
          angelegt INTEGER NOT NULL
        );
        CREATE TABLE wiederherstellung (
          konto TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
          pruefwert TEXT NOT NULL,
          PRIMARY KEY (konto, pruefwert)
        );
        CREATE TABLE geraete (
          id TEXT PRIMARY KEY,
          konto TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          pruefwert TEXT NOT NULL UNIQUE,
          angelegt INTEGER NOT NULL,
          zuletzt INTEGER NOT NULL,
          adresse TEXT
        );
        CREATE INDEX geraete_konto ON geraete(konto);
        CREATE TABLE oidc (
          aussteller TEXT NOT NULL,
          subjekt TEXT NOT NULL,
          konto TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
          angelegt INTEGER NOT NULL,
          PRIMARY KEY (aussteller, subjekt)
        );
        PRAGMA user_version = 1;
        COMMIT;
      ''');
    }
    if (stand < 2) {
      // Freigaben nach aussen (Issue #106): Der Link selbst steht nur
      // verschlüsselt da (zum erneuten Anzeigen); gesucht wird über seinen
      // SHA-256. Eine Kopie von server.sqlite allein öffnet keine Freigabe.
      db.execute('''
        BEGIN;
        CREATE TABLE freigaben (
          id TEXT PRIMARY KEY,
          konto TEXT NOT NULL REFERENCES konten(id) ON DELETE CASCADE,
          pruefwert TEXT NOT NULL UNIQUE,
          link TEXT NOT NULL,
          geheimnis TEXT NOT NULL,
          titel TEXT NOT NULL,
          album TEXT,
          aufnahmen TEXT,
          passwort TEXT,
          herunterladen INTEGER NOT NULL DEFAULT 0,
          angelegt INTEGER NOT NULL,
          ablauf INTEGER,
          aufrufe INTEGER NOT NULL DEFAULT 0,
          zuletzt INTEGER
        );
        CREATE INDEX freigaben_konto ON freigaben(konto);
        PRAGMA user_version = 2;
        COMMIT;
      ''');
    }
  }

  void schliesse() => db.close();
}

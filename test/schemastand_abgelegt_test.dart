import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';

/// **Jede Schemafassung liegt als Stand unter packages/kern/drift_schemas/.**
///
/// Aus zwei abgelegten Ständen erzeugt `dart run drift_dev make-migrations`
/// Tests, die die Migration dazwischen an einer echten Datenbank
/// nachprüfen. Das wirkt aber nur, wenn der Befehl bei jedem Schemawechsel
/// auch läuft – sonst fehlt der Stand, und der nächste Sprung bleibt
/// ungeprüft. Dieser Test fällt, sobald `schemaVersion` steigt, ohne dass
/// der neue Stand abgelegt wurde.
void main() {
  test('der aktuelle Schemastand ist abgelegt', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fassung = db.schemaVersion;
    final datei = File(
      'packages/kern/drift_schemas/default/drift_schema_v$fassung.json',
    );
    expect(
      datei.existsSync(),
      isTrue,
      reason:
          'Schema $fassung ist nicht abgelegt – '
          '`dart run drift_dev make-migrations` aufrufen',
    );
  });

  test('@DriftDatabase steht unmittelbar an der Datenbankklasse', () {
    // Eine Funktion dazwischen nimmt die Anmerkung an sich: drift findet
    // dann keine Datenbank mehr, build_runner meldet Erfolg und löscht
    // database.g.dart. So geschehen am 12.10.2026 – aufgefallen erst beim
    // nächsten Erzeugen, Tage später.
    final quelle = File(
      'packages/kern/lib/db/database.dart',
    ).readAsStringSync();
    final anmerkung = quelle.indexOf('@DriftDatabase(');
    final klasse = quelle.indexOf('class AppDatabase extends');
    expect(anmerkung, greaterThan(0));
    expect(klasse, greaterThan(anmerkung));
    final dazwischen = quelle.substring(anmerkung, klasse);
    final ende = dazwischen.lastIndexOf(')');
    expect(dazwischen.substring(ende + 1).trim(), isEmpty);
  });
}

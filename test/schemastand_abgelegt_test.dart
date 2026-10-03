import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Jede Schemafassung liegt als Stand unter drift_schemas/.**
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
    final datei =
        File('drift_schemas/default/drift_schema_v$fassung.json');
    expect(datei.existsSync(), isTrue,
        reason: 'Schema $fassung ist nicht abgelegt – '
            '`dart run drift_dev make-migrations` aufrufen');
  });
}

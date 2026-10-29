import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Eine ältere Fassung öffnet eine Bibliothek, die eine neuere schon
/// aufgestuft hat.
///
/// drift ruft dafür onUpgrade mit from > to auf und schrieb danach still
/// die kleinere Nummer zurück (nachgestellt: 95 → 94). Die nächste neuere
/// Fassung liefe dann Schritte noch einmal, die schon gelaufen sind.
void main() {
  late Directory dir;
  late File datei;
  late int aktuell;

  int nummer() {
    final roh = sqlite.sqlite3.open(datei.path, mode: sqlite.OpenMode.readOnly);
    try {
      return roh.select('PRAGMA user_version').single.values.single as int;
    } finally {
      roh.close();
    }
  }

  void setzeNummer(int n) {
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('PRAGMA user_version = $n');
    roh.close();
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photo_vault_neuer_');
    datei = File('${dir.path}/library.sqlite');
    final db = AppDatabase(NativeDatabase(datei));
    await db.customSelect('SELECT 1').get();
    aktuell = db.schemaVersion;
    await db.close();
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'eine neuere Bibliothek wird abgewiesen und behält ihre Nummer',
    () async {
      setzeNummer(aktuell + 1);

      final db = AppDatabase(NativeDatabase(datei));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<NeuereBibliothek>()
              .having((e) => e.bibliothek, 'bibliothek', aktuell + 1)
              .having((e) => e.programm, 'programm', aktuell),
        ),
      );
      await db.close();
      expect(nummer(), aktuell + 1);
    },
  );

  test(
    'AppDatabase.open weist sie gleich ab und gibt die Datei frei',
    () async {
      setzeNummer(aktuell + 1);

      Object? fehler;
      try {
        await AppDatabase.open(dir);
      } catch (e) {
        fehler = e;
      }
      // Aus dem Hintergrund-Isolat kommt sie nur als DriftRemoteException
      // mit ihrem Text an; die Oberfläche erkennt sie an der Kennung.
      expect('$fehler', contains(NeuereBibliothek.kennung));
      expect(nummer(), aktuell + 1);

      // Nichts hält die Datei noch: Zurück auf den eigenen Stand lässt sie
      // sich wieder öffnen.
      setzeNummer(aktuell);
      final db = await AppDatabase.open(dir);
      addTearDown(db.close);
      expect(nummer(), aktuell);
    },
  );

  test('eine ältere Fassung setzt die Nummer nicht mehr zurück', () async {
    final alt = _AeltereFassung(NativeDatabase(datei), aktuell - 1);
    await expectLater(
      alt.customSelect('SELECT count(*) FROM assets').get(),
      throwsA(isA<NeuereBibliothek>()),
    );
    await alt.close();
    expect(nummer(), aktuell);

    // Die eigene Fassung öffnet sie danach wie gewohnt.
    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    await db.customSelect('SELECT count(*) FROM assets').get();
    expect(nummer(), aktuell);
  });
}

class _AeltereFassung extends AppDatabase {
  _AeltereFassung(super.e, this._schema);
  final int _schema;

  @override
  int get schemaVersion => _schema;
}

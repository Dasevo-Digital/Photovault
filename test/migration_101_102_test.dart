import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/entwicklungsvariante.dart';
import 'package:kern/services/weissabgleich.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schritt 102 (#466): Die Temperatur heisst jetzt „höher ist wärmer“. Jede
/// gespeicherte Zahl wird beim Aufstufen umgerechnet, genau einmal, und das
/// Bild bleibt dasselbe (siehe weissabgleich_bild_test.dart).
void main() {
  late Directory temp;
  late File datei;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_schema102_');
    datei = File('${temp.path}/library.sqlite');
  });
  tearDown(() => temp.delete(recursive: true));

  /// Eine Bibliothek mit Temperaturen in allen Tabellen, die eine tragen –
  /// angelegt mit dem heutigen Schema und danach auf 101 zurückgestempelt,
  /// mit den Zahlen in der früheren Bedeutung.
  Future<void> legeAn({bool server = false, bool kopie = false}) async {
    final db = AppDatabase(NativeDatabase(datei));
    if (server) await Protokoll(db).richteEin(mitschreiben: -1);
    for (final id in ['a', 'b']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: id * 64,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
        ),
      );
    }
    final jetzt = DateTime(2026, 11, 22);
    await db
        .into(db.developSettings)
        .insert(
          DevelopSettingsCompanion.insert(
            assetId: 'a',
            temperature: const Value(4000),
            tint: const Value(10),
            updatedAt: jetzt,
          ),
        );
    // Automatik: bleibt leer.
    await db
        .into(db.developSettings)
        .insert(
          DevelopSettingsCompanion.insert(assetId: 'b', updatedAt: jetzt),
        );
    for (final t in [2000.0, null, 15000.0]) {
      await db
          .into(db.developHistory)
          .insert(
            DevelopHistoryCompanion.insert(
              assetId: 'a',
              exposure: 0,
              temperature: Value(t),
              contrast: 0,
              shadows: 0,
              sharpness: 0,
              noiseReduction: 0,
              lensCorrectionEnabled: true,
              createdAt: jetzt,
            ),
          );
    }
    await db.upsertDevelopPreset(
      DevelopPresetsCompanion.insert(
        name: 'Kunstlicht',
        temperature: const Value(5200),
        erstelltAm: jetzt,
      ),
    );
    await db.createDevelopMask(
      DevelopMasksCompanion.insert(
        assetId: 'a',
        maskRelativePath: 'masks/m.png',
        label: 'Himmel',
        temperature: const Value(12000),
        createdAt: jetzt,
      ),
    );
    // Ein Variantenstand der Fassung 1, wie ihn die frühere App schrieb.
    final einstellungen = (await db.developSettingsForAsset('a'))!;
    final masken = await db.masksForAsset('a');
    final stand = Entwicklungsstand('a' * 64, einstellungen, masken, {
      'masks/m.png': 'c' * 64,
    }).encode().replaceFirst('"fassung":2', '"fassung":1');
    await db
        .into(db.developVariants)
        .insert(
          DevelopVariantsCompanion.insert(
            id: 'v1',
            assetId: 'a',
            name: 'warm',
            stateJson: stand,
            previewRelativePath: 'developed/v1.jpg',
            updatedAt: jetzt,
          ),
        );
    if (kopie) {
      await db.customStatement(
        'CREATE TABLE pv_ausgang (nr INTEGER PRIMARY KEY AUTOINCREMENT, '
        'kennung TEXT NOT NULL UNIQUE, befehl TEXT NOT NULL, '
        'bestaetigt INTEGER, ok INTEGER, fehler TEXT)',
      );
    }
    await db.close();
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('PRAGMA user_version = 101');
    roh.close();
  }

  Future<List<double?>> temperaturen(AppDatabase db, String tabelle) async => [
    for (final z
        in await db
            .customSelect('SELECT temperature FROM $tabelle ORDER BY rowid')
            .get())
      (z.data['temperature'] as num?)?.toDouble(),
  ];

  Future<int> stufe(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single
          as int;

  test('rechnet jede gespeicherte Temperatur um, genau einmal', () async {
    await legeAn();
    for (var lauf = 0; lauf < 2; lauf++) {
      final db = AppDatabase(NativeDatabase(datei));
      expect(await temperaturen(db, 'develop_settings'), [10562.5, null]);
      expect(await temperaturen(db, 'develop_history'), [
        21125.0,
        null,
        42250000 / 12000,
      ]);
      expect(await temperaturen(db, 'develop_presets'), [8125.0]);
      expect(await temperaturen(db, 'develop_masks'), [42250000 / 12000]);
      expect((await db.developSettingsForAsset('a'))!.tint, 10);
      // Der Variantenstand bleibt, wie er ist, und trägt seine Fassung
      // selbst; gelesen kommt er umgerechnet heraus.
      final v = (await db.variantenFuer('a')).single;
      expect(v.stateJson, contains('"fassung":1'));
      final stand = Entwicklungsstand.decode(v.stateJson);
      expect(stand.einstellungen.temperature, 10562.5);
      expect(stand.masken.single.temperature, 42250000 / 12000);
      expect(await stufe(db), db.schemaVersion);
      await db.close();
    }
  });

  test('bricht der Schritt ab, ist nichts umgerechnet', () async {
    await legeAn();
    // Die letzte Tabelle wehrt sich: Die Umrechnung der ersten darf dann
    // auch nicht stehen bleiben, sonst rechnete der nächste Start sie ein
    // zweites Mal um.
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute(
      'CREATE TRIGGER stoerung BEFORE UPDATE ON develop_masks '
      "BEGIN SELECT RAISE(ABORT, 'gestoert'); END",
    );
    roh.close();
    final kaputt = AppDatabase(NativeDatabase(datei));
    await expectLater(kaputt.customSelect('SELECT 1').get(), throwsA(anything));
    await kaputt.close();

    final nachsehen = sqlite.sqlite3.open(datei.path);
    expect(nachsehen.select('PRAGMA user_version').single.values.single, 101);
    expect(
      nachsehen
          .select("SELECT temperature FROM develop_settings WHERE asset_id='a'")
          .single
          .values
          .single,
      4000,
    );
    nachsehen.execute('DROP TRIGGER stoerung');
    nachsehen.close();

    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    expect(await temperaturen(db, 'develop_settings'), [10562.5, null]);
    expect(await temperaturen(db, 'develop_masks'), [42250000 / 12000]);
  });

  test('der Server schreibt die umgerechneten Zeilen ins Protokoll', () async {
    await legeAn(server: true);
    final roh = sqlite.sqlite3.open(datei.path);
    roh.execute('DELETE FROM pv_aenderungen');
    roh.close();
    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    final protokolliert = {
      for (final z
          in await db
              .customSelect('SELECT DISTINCT tabelle FROM pv_aenderungen')
              .get())
        z.read<String>('tabelle'),
    };
    // Die Kopien holen sie und bekommen dieselben Zahlen, die sie beim
    // eigenen Aufstufen errechnet haben – Zeilen, keine Änderungsschritte,
    // also keine zweite Umrechnung.
    expect(
      protokolliert,
      containsAll([
        'develop_settings',
        'develop_history',
        'develop_presets',
        'develop_masks',
      ]),
    );
    expect(await temperaturen(db, 'develop_settings'), [10562.5, null]);
    // Auf dem Server gibt es keine Warteschlange und damit keine Marke.
    expect(
      await db
          .customSelect(
            "SELECT 1 FROM sqlite_master WHERE name = 'pv_weissabgleich_umkehr'",
          )
          .get(),
      isEmpty,
    );
  });

  test(
    'eine verbundene Kopie bekommt die Marke für ihre Warteschlange',
    () async {
      await legeAn(kopie: true);
      final db = AppDatabase(NativeDatabase(datei));
      addTearDown(db.close);
      expect(await temperaturen(db, 'develop_settings'), [10562.5, null]);
      expect(
        await db.customSelect('SELECT id FROM pv_weissabgleich_umkehr').get(),
        hasLength(1),
      );
    },
  );

  test('alle Werte liegen danach im Reglerbereich', () async {
    await legeAn();
    final db = AppDatabase(NativeDatabase(datei));
    addTearDown(db.close);
    for (final tabelle in Migrationsschritte.temperaturTabellen) {
      for (final t in await temperaturen(db, tabelle)) {
        if (t != null) {
          expect(t, inInclusiveRange(temperaturMin, temperaturMax));
        }
      }
    }
  });
}

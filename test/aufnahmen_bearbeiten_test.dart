import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Welche Fotos zu einer Reise oder Aktivität gehören – nachträglich
/// geändert.
///
/// **Warum das fehlte und warum es zwei Dinge sind.** Die Zuordnung
/// entstand einmal: bei der Erkennung an einer Lücke von anderthalb
/// Stunden, beim Anlegen von Hand über den Zeitraum. Beides trifft oft
/// und nicht immer – das Foto vom Vorabend gehört manchmal dazu, das aus
/// der Mittagspause manchmal nicht. Zu ändern war daran nichts.
///
/// Das zweite Ding ist der **Zeitraum**: `von`/`bis` sind aus den
/// Aufnahmen abgeleitet und trotzdem gespeichert, damit die Liste
/// sortieren kann. Wer Fotos ändert und den Zeitraum stehen lässt, hat
/// eine Reise, deren Datum keine Aufnahme mehr belegt.
void main() {
  late Directory wurzel;
  late AppDatabase db;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_zuordnung_');
    db = AppDatabase(NativeDatabase.memory());
    await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    // Sechs Aufnahmen, eine je Stunde ab 8 Uhr.
    for (var i = 0; i < 6; i++) {
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a$i',
            originalFileName: 'a$i.jpg',
            relativePath: 'originals/a$i.jpg',
            checksum: 'c$i',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14, 8 + i),
            importedAt: DateTime(2026),
          ));
    }
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> aktivitaet(List<String> ids) => db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'k1',
          name: 'Wanderung',
          art: 'wanderung',
          von: DateTime(2026, 6, 14, 9),
          bis: DateTime(2026, 6, 14, 11),
          angelegtAm: DateTime(2026),
        ),
        ids,
      );

  Future<void> reise(List<String> ids) => db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'r1',
          name: 'Rom',
          von: DateTime(2026, 6, 14, 9),
          bis: DateTime(2026, 6, 14, 11),
          angelegtAm: DateTime(2026),
        ),
        ids,
      );

  group('Aktivität', () {
    test('ein Foto dazu, eines heraus', () async {
      await aktivitaet(['a1', 'a2', 'a3']);
      await db.setzeAufnahmenDerAktivitaet('k1', {'a1', 'a2', 'a4'});
      expect([for (final a in await db.aufnahmenDerAktivitaet('k1')) a.id],
          ['a1', 'a2', 'a4']);
    });

    test('der Zeitraum wird nachgeführt', () async {
      await aktivitaet(['a1', 'a2', 'a3']);
      await db.setzeAufnahmenDerAktivitaet('k1', {'a0', 'a1'});
      final k = (await db.aktivitaet('k1'))!;
      expect(k.von, DateTime(2026, 6, 14, 8), reason: 'die neue erste');
      expect(k.bis, DateTime(2026, 6, 14, 9), reason: 'die neue letzte');
    });

    test('bleibt nichts übrig, bleibt der alte Zeitraum stehen', () async {
      // „1970" wäre eine Behauptung. Eine Aktivität ohne Bilder hat
      // keinen belegten Zeitraum – sie steht mit ihrem alten Datum in
      // der Liste, bis wieder etwas darin liegt.
      await aktivitaet(['a1', 'a2']);
      await db.setzeAufnahmenDerAktivitaet('k1', {});
      final k = (await db.aktivitaet('k1'))!;
      expect(await db.aufnahmenDerAktivitaet('k1'), isEmpty);
      expect(k.von, DateTime(2026, 6, 14, 9));
      expect(k.bis, DateTime(2026, 6, 14, 11));
    });

    test('zweimal dasselbe setzen ändert nichts', () async {
      // Der Primärschlüssel ist (Aktivität, Aufnahme) – ohne das
      // Löschen davor wäre der zweite Durchgang ein Konflikt.
      await aktivitaet(['a1', 'a2']);
      await db.setzeAufnahmenDerAktivitaet('k1', {'a1', 'a2'});
      await db.setzeAufnahmenDerAktivitaet('k1', {'a1', 'a2'});
      expect(await db.aufnahmenDerAktivitaet('k1'), hasLength(2));
    });

    test('eine andere Aktivität bleibt unberührt', () async {
      await aktivitaet(['a1', 'a2']);
      await db.aktivitaetAnlegen(
          AktivitaetenCompanion.insert(
            id: 'k2',
            name: 'Radtour',
            art: 'radtour',
            von: DateTime(2026, 6, 14, 12),
            bis: DateTime(2026, 6, 14, 13),
            angelegtAm: DateTime(2026),
          ),
          ['a4', 'a5']);
      await db.setzeAufnahmenDerAktivitaet('k1', {'a0'});
      expect([for (final a in await db.aufnahmenDerAktivitaet('k2')) a.id],
          ['a4', 'a5']);
    });
  });

  group('Reise', () {
    test('dieselbe Rechnung eine Tabelle weiter', () async {
      await reise(['a1', 'a2']);
      await db.setzeAufnahmenDerReise('r1', {'a2', 'a5'});
      expect([for (final a in await db.aufnahmenDerReise('r1')) a.id],
          ['a2', 'a5']);
      final r = (await db.reise('r1'))!;
      expect(r.von, DateTime(2026, 6, 14, 10));
      expect(r.bis, DateTime(2026, 6, 14, 13));
    });
  });
}

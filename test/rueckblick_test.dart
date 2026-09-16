import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/rueckblick.dart';

/// **Der Abschnitt verschwand an 104 Tagen im Jahr wortlos.**
///
/// „Heute vor X Jahren" trifft an der echten Bibliothek an 261 von 365
/// Tagen etwas; an 107 davon sind es hoechstens drei Aufnahmen. Am 12.
/// September 2026 – dem Tag, an dem das hier entstand – war es nichts,
/// und der Abschnitt blendete sich ohne einen Ton aus.
///
/// Und am 27. August waere er umgekippt: 1103 Aufnahmen, davon 1096 mit
/// einem Zeitstempel auf voller Stunde und 948 auf ein und derselben
/// Sekunde. Die Abwehr dagegen stand im Quelltext – sie haengt an
/// `datum_geschaetzt`, und diese Marke steht an der echten Bibliothek
/// bei 0, weil der Lauf nie gelaufen ist.
void main() {
  group('die Wahl der Frage', () {
    DateTime wann(DateTime d) => d;
    final heute = DateTime(2026, 9, 12);

    test('der Tag gewinnt, sobald er etwas hat', () {
      final r = waehleRueckblick(
        amTag: [DateTime(2013, 9, 12)],
        imMonat: [DateTime(2013, 9, 3)],
        wann: wann,
        heute: heute,
      );
      expect(r.art, Rueckblickart.tag);
      expect(r.gruppen.single.jahreHer, 13);
    });

    test('ist der Tag leer, tritt der Monat an seine Stelle', () {
      final r = waehleRueckblick(
        amTag: const <DateTime>[],
        imMonat: [DateTime(2013, 9, 3), DateTime(2024, 9, 30)],
        wann: wann,
        heute: heute,
      );
      expect(r.art, Rueckblickart.monat);
      expect([for (final g in r.gruppen) g.jahreHer], [2, 13]);
    });

    test('ist beides leer, ist das eine Auskunft und kein Zufall', () {
      final r = waehleRueckblick(
        amTag: const <DateTime>[],
        imMonat: const <DateTime>[],
        wann: wann,
        heute: heute,
      );
      expect(r.art, Rueckblickart.keiner);
      expect(r.gruppen, isEmpty);
    });

    test('das laufende Jahr ist keine Erinnerung', () {
      final r = waehleRueckblick(
        amTag: [DateTime(2026, 9, 12)],
        imMonat: const <DateTime>[],
        wann: wann,
        heute: heute,
      );
      expect(r.art, Rueckblickart.keiner);
    });
  });

  group('an der Datenbank', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    var laufend = 0;
    Future<void> foto(DateTime wann,
        {bool geschaetzt = false, bool geprueft = false}) {
      final id = 'a${laufend++}';
      return db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: DateTime(2026),
            datumGeschaetzt: Value(geschaetzt),
            datumGeprueft: Value(geprueft),
          ));
    }

    test('die volle Stunde fliegt aus den Erinnerungen – ohne den Lauf',
        () async {
      // Genau der Fall vom 27. August: erfundene Uhrzeit, aber niemand
      // hat sie je als solche markiert.
      await foto(DateTime(2006, 8, 27));
      await foto(DateTime(2006, 8, 27, 14, 32, 8));

      final treffer = await db.assetsOnThisDay(DateTime(2026, 8, 27));
      expect(treffer.length, 1);
      expect(treffer.single.fileCreatedAt.minute, 32);
    });

    test('was der Lauf bestaetigt hat, bleibt drin – auch auf voller Stunde',
        () async {
      // Der Lauf hat nachgesehen und KEIN geschaetztes Datum gefunden:
      // Dann steht in der Datei ein echtes, und die volle Stunde ist
      // Zufall. An der echten Bibliothek betrifft das 149 Aufnahmen,
      // 148 davon am 27. August.
      await foto(DateTime(2006, 8, 27), geprueft: true);
      // Ungeprueft und auf voller Stunde: der Verdacht gilt weiter.
      await foto(DateTime(2006, 8, 27));

      final treffer = await db.assetsOnThisDay(DateTime(2026, 8, 27));
      expect(treffer.length, 1);
      expect(treffer.single.datumGeprueft, isTrue);
    });

    test('der Monat bringt, was der Tag nicht hat – ohne den Tag doppelt',
        () async {
      await foto(DateTime(2013, 9, 12, 10, 5));
      await foto(DateTime(2013, 9, 3, 10, 5));
      await foto(DateTime(2013, 8, 3, 10, 5));

      final monat = await db.assetsInDiesemMonat(DateTime(2026, 9, 12));
      expect(monat.length, 1);
      expect(monat.single.fileCreatedAt.day, 3);
    });

    test('ein einzelner Jahrgang ueberschwemmt den Rueckblick nicht',
        () async {
      for (var tag = 1; tag <= 20; tag++) {
        await foto(DateTime(2013, 9, tag, 10, 5));
      }
      final monat = await db.assetsInDiesemMonat(DateTime(2026, 9, 30),
          hoechstensJeJahr: 12);
      expect(monat.length, 12);
    });
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/videostandbilder.dart';

/// **Zwei fertige Auswertungen, die nie gelaufen sind.**
///
/// An der Produktivbibliothek stand am 10.09.2026: `datum_geschaetzt` = 0,
/// `videoeinbettungen` = 0 Zeilen – bei 1097 Aufnahmen auf voller Stunde
/// und 219 Videos ab zehn Sekunden. Beide Läufe gibt es seit der 7.
/// Auflage, beide stehen in der Aufgabenliste, und beide hatte niemand
/// je angestossen. Was die Ortsvorschläge und die offenen Gesichter aus
/// derselben Lage geholt hat, war eine Karte auf dem
/// Gesundheitsbildschirm.
///
/// Geprüft wird hier das, woran eine solche Karte hängt: dass die Zahl
/// darauf **nur** zählt, was der Lauf auch ändert. Die vorhandenen Zähler
/// [AppDatabase.countDatumsherkunft] (8098) und
/// [AppDatabase.countVideobilder] (429) taugen dafür nicht.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> anlegen(
    String id, {
    required String typ,
    required DateTime wann,
    double? dauer,
    bool datumGeprueft = false,
    bool videobilderGeprueft = false,
    bool papierkorb = false,
    bool gesperrt = false,
  }) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: typ,
            fileCreatedAt: wann,
            importedAt: DateTime(2026),
            durationSeconds: Value(dauer),
            datumGeprueft: Value(datumGeprueft),
            videobilderGeprueft: Value(videobilderGeprueft),
            isTrashed: Value(papierkorb),
            isLocked: Value(gesperrt),
          ));

  group('fragwürdige Aufnahmedaten', () {
    test('nur die auf voller Stunde zählen mit', () async {
      await anlegen('voll', typ: 'IMAGE', wann: DateTime(2006, 8, 27));
      await anlegen('auchVoll', typ: 'IMAGE', wann: DateTime(2013, 7, 4, 15));
      await anlegen('minute', typ: 'IMAGE', wann: DateTime(2013, 7, 4, 15, 1));
      await anlegen('sekunde',
          typ: 'IMAGE', wann: DateTime(2013, 7, 4, 15, 0, 1));

      expect(await db.countAuffaelligeAufnahmedaten(), 2);
      // Der weite Zähler sieht alle vier an – deshalb steht er nicht auf
      // der Karte.
      expect(await db.countDatumsherkunft(), 4);
    });

    test('was schon nachgesehen wurde, wartet nicht mehr', () async {
      await anlegen('offen', typ: 'IMAGE', wann: DateTime(2006, 8, 27));
      await anlegen('erledigt',
          typ: 'IMAGE', wann: DateTime(2006, 8, 28), datumGeprueft: true);

      expect(await db.countAuffaelligeAufnahmedaten(), 1);
    });

    test('der Papierkorb zählt mit – wie beim Lauf selbst', () async {
      await anlegen('weg',
          typ: 'IMAGE', wann: DateTime(2006, 8, 27), papierkorb: true);

      expect(await db.countAuffaelligeAufnahmedaten(), 1);
      expect(
          [for (final a in await db.assetsFuerDatumsherkunft()) a.id], ['weg']);
    });
  });

  group('Videos ab dem Zweitblick', () {
    test('kurze Videos bringt der Lauf nicht weiter', () async {
      await anlegen('lang',
          typ: 'VIDEO', wann: DateTime(2020), dauer: 540.0);
      await anlegen('genauSchwelle',
          typ: 'VIDEO',
          wann: DateTime(2020),
          dauer: videoZweitblickAb.inSeconds.toDouble());
      await anlegen('kurz', typ: 'VIDEO', wann: DateTime(2020), dauer: 2.0);
      await anlegen('ohneDauer', typ: 'VIDEO', wann: DateTime(2020));

      expect(await db.countVideoZweitblick(), 2);
      // Und die Grenze ist dieselbe, die auch die Stellen bestimmt.
      expect(videostandbildstellen(2.0), isEmpty);
      expect(videostandbildstellen(videoZweitblickAb.inSeconds.toDouble()),
          isNotEmpty);
      expect(await db.countVideobilder(), 4);
    });

    test('Bilder, Erledigtes und Gesperrtes bleiben draussen', () async {
      await anlegen('bild', typ: 'IMAGE', wann: DateTime(2020), dauer: 540.0);
      await anlegen('erledigt',
          typ: 'VIDEO',
          wann: DateTime(2020),
          dauer: 540.0,
          videobilderGeprueft: true);
      await anlegen('gesperrt',
          typ: 'VIDEO', wann: DateTime(2020), dauer: 540.0, gesperrt: true);
      await anlegen('offen', typ: 'VIDEO', wann: DateTime(2020), dauer: 540.0);

      expect(await db.countVideoZweitblick(), 1);
    });
  });
}

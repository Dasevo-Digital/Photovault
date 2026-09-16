import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/services/videostandbilder.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Ein Video war ein einziges Standbild.**
///
/// Seit der 6. Vergleichsauflage werden Videos überhaupt ausgewertet: 428
/// von 429 haben eine Einbettung für die Suche, 428 Schlagwörter, 182 ein
/// erkanntes Gesicht. Alles davon stammt aus **einem** Bild, das seit dem
/// Import auf der Platte liegt.
///
/// ```
/// 429 Videos, 186 Minuten
///   unter 10 s     208   ein Bild reicht
///   ab 10 s        219   ein Bild reicht nicht
///   ab 1 min        54   laengstes: 9 min
/// ```
///
/// Bei zwei Sekunden ist das eine Bild das ganze Video. Bei neun Minuten
/// ist es eine Stichprobe von 0,2 Promille.
void main() {
  group('wie viele Standbilder', () {
    test('unter zehn Sekunden bleibt es bei dem einen', () {
      // 208 der 429 Videos. Das vorhandene Standbild liegt rund eine
      // halbe Sekunde nach dem Start – bei acht Sekunden Laufzeit zeigt
      // ein zweites nichts, was das erste nicht schon zeigte.
      for (final dauer in [0.5, 2.0, 9.9]) {
        expect(videostandbildstellen(dauer), isEmpty, reason: '$dauer s');
      }
    });

    test('ohne bekannte Laufzeit wird nichts geholt', () {
      // 33 der 429 Videos hatten beim Import keine Miniatur – bei denen
      // konnte auch die Laufzeit nicht ermittelt werden. Raten waere hier
      // teurer als schweigen.
      expect(videostandbildstellen(null), isEmpty);
      expect(videostandbildstellen(0), isEmpty);
      expect(videostandbildstellen(-1), isEmpty);
    });

    test('ab zehn Sekunden mindestens zwei, hoechstens fuenf', () {
      expect(videostandbildstellen(10), hasLength(2));
      expect(videostandbildstellen(30), hasLength(2));
      expect(videostandbildstellen(60), hasLength(3));
      expect(videostandbildstellen(100), hasLength(5));
      // Das laengste Video der Bibliothek: neun Minuten.
      expect(videostandbildstellen(540), hasLength(videoStandbilderHoechstens));
      expect(videostandbildstellen(36000), hasLength(videoStandbilderHoechstens),
          reason: 'auch zehn Stunden bekommen nicht mehr');
    });

    test('die Stellen liegen im Inneren und in aufsteigender Reihenfolge', () {
      // Der allererste Frame ist bei vielen Videos schwarz, der
      // allerletzte oft eine Bewegungsunschaerfe vom Absetzen der Kamera.
      final stellen = videostandbildstellen(120);
      expect(stellen.first, greaterThan(0));
      expect(stellen.last, lessThan(1));
      for (var i = 1; i < stellen.length; i++) {
        expect(stellen[i], greaterThan(stellen[i - 1]));
      }
      // Gleichmaessig verteilt: bei vier Bildern ein bis vier Fuenftel.
      expect(videostandbildstellen(80),
          [closeTo(0.2, 1e-9), closeTo(0.4, 1e-9), closeTo(0.6, 1e-9), closeTo(0.8, 1e-9)]);
    });

    test('keine Stelle wird doppelt geholt', () {
      for (final dauer in [10.0, 45.0, 120.0, 300.0, 540.0]) {
        final stellen = videostandbildstellen(dauer);
        expect(stellen.toSet(), hasLength(stellen.length), reason: '$dauer s');
      }
    });
  });

  group('an der Datenbank', () {
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_videobilder_');
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryState()
        ..db = db
        ..paths = await StoragePaths.forTesting(
            Directory(p.join(wurzel.path, 'lib')));
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    Future<void> anlegen(String id,
            {String typ = 'VIDEO',
            double? dauer,
            bool gesperrt = false,
            bool papierkorb = false}) =>
        db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.mov',
              relativePath: 'originals/2025/08/$id.mov',
              checksum: 'pruef-$id',
              type: typ,
              fileCreatedAt: DateTime(2025, 8, 20),
              importedAt: DateTime(2026),
              durationSeconds: Value(dauer),
              isLocked: Value(gesperrt),
              isTrashed: Value(papierkorb),
            ));

    Uint8List vektor(double x) =>
        blobFromEmbeddingFloats(Float32List.fromList([x, 0, 0, 0]));

    test('offen sind nur Videos, und nur ungeprüfte', () async {
      await anlegen('v', dauer: 30);
      await anlegen('foto', typ: 'IMAGE');
      await anlegen('geloescht', dauer: 30, papierkorb: true);
      await anlegen('gesperrt', dauer: 30, gesperrt: true);

      expect(await db.countVideobilder(), 1);
      expect([for (final a in await db.assetsFuerVideobilder()) a.id], ['v']);
    });

    test('ein zu kurzes Video gilt danach als erledigt', () async {
      // Sonst naehme sich der Nachtrag bei jedem Lauf dieselben 208
      // kurzen Videos erneut vor.
      await anlegen('kurz', dauer: 3);
      await for (final _ in library.backfillVideobilder()) {}
      expect(await db.countVideobilder(), 0);
      expect((await db.assetById('kurz'))!.videobilderGeprueft, isTrue);
    });

    test('Einbettungen werden ersetzt, nicht verdoppelt', () async {
      // Ein zweiter Lauf ueber dasselbe Video soll es ersetzen: Die
      // Stellen koennen sich mit der Laufzeit aendern.
      await anlegen('v', dauer: 60);
      await db.setzeVideoeinbettungen('v', [
        (stelle: 0.25, vector: vektor(1)),
        (stelle: 0.5, vector: vektor(0.5)),
      ]);
      expect((await db.alleVideoeinbettungen())['v'], hasLength(2));

      await db.setzeVideoeinbettungen('v', [(stelle: 0.5, vector: vektor(0.9))]);
      expect((await db.alleVideoeinbettungen())['v'], hasLength(1));
      expect((await db.assetById('v'))!.videobilderGeprueft, isTrue);
    });

    test('gesperrte und gelöschte Videos liefern keine Einbettung heraus',
        () async {
      // Was im Bildinhalt steckt, hat in der unverschluesselten
      // Datenbank nichts zu suchen – dieselbe Regel wie ueberall sonst
      // bei der Auswertung.
      await anlegen('offen', dauer: 60);
      await anlegen('gesperrt', dauer: 60, gesperrt: true);
      await db.setzeVideoeinbettungen('offen', [(stelle: 0.5, vector: vektor(1))]);
      await db.setzeVideoeinbettungen('gesperrt', [(stelle: 0.5, vector: vektor(1))]);

      expect((await db.alleVideoeinbettungen()).keys, ['offen']);
    });

    test('die Suchkandidaten tragen die Stelle im Schlüssel', () async {
      // Damit die Rangfolge jedes Standbild einzeln bewerten kann: Es
      // zaehlt das BESTE, nicht das Mittel. Ein Mittelwert ueber
      // verschiedene Szenen waere ein Vektor, der zu nichts mehr passt.
      await anlegen('v', dauer: 60);
      await db.saveEmbedding('v', Float32List.fromList([1, 0, 0, 0]));
      await db.setzeVideoeinbettungen('v', [
        (stelle: 0.25, vector: vektor(0.8)),
        (stelle: 0.75, vector: vektor(0.6)),
      ]);

      final kandidaten = await library.suchkandidaten();
      expect(kandidaten.keys.toSet(), {'v', 'v#0', 'v#1'});
      for (final k in kandidaten.keys) {
        expect(LibraryState.aufnahmeAusSuchschluessel(k), 'v');
      }
    });

    test('ohne Video-Standbilder bleibt die Kandidatenliste unverändert',
        () async {
      // Die Gegenprobe: Der neue Weg darf den alten nicht umbauen.
      await anlegen('foto', typ: 'IMAGE');
      await db.saveEmbedding('foto', Float32List.fromList([1, 0, 0, 0]));
      expect((await library.suchkandidaten()).keys, ['foto']);
    });

    test('eine Kennung mit Raute im Namen bleibt lesbar', () async {
      // Die Kennungen sind UUIDs und enthalten keine Raute – aber der
      // Rueckweg darf nicht daran haengen, dass das so bleibt.
      expect(LibraryState.aufnahmeAusSuchschluessel('a#b#2'), 'a#b');
      expect(LibraryState.aufnahmeAusSuchschluessel('a'), 'a');
    });
  });
}

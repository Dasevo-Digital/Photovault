import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';

/// **Die Videohälfte eines Live Photos ist keine eigene Aufnahme.**
///
/// Überall in der App gilt das schon (`_isPrimaryGridEntry`) – in der
/// Reise- und Aktivitätserkennung galt es nicht. Was daraus folgte, hat
/// niemand als Erkennungsfehler gelesen, sondern als „der Vorschlag kommt
/// nach dem Bestätigen wieder":
///
/// Bestätigt wurde, was die Zeitleiste zeigt – die Fotos. Die
/// MOV-Hälften blieben unzugeordnet, trugen aber dieselbe Sekunde und
/// denselben Ort und fanden sich beim nächsten Blick zu einem NEUEN
/// Vorschlag desselben Ausflugs zusammen.
///
/// An der gewachsenen Bibliothek gemessen (1933 verortete Aufnahmen, 18
/// bestätigte Aktivitäten):
///
/// ```
/// mit Videohälften    3 Vorschläge  – alle drei Schatten bestätigter Ausflüge
/// ohne Videohälften   1 Vorschlag
/// dazu die Reparatur  0 Vorschläge
/// ```
///
/// Und der Schaden davor: 19 Zuordnungen zeigten auf eine Videohälfte,
/// nur 5 der zugehörigen Fotos waren ebenfalls zugeordnet. Zwei
/// Aktivitäten bestanden aus sieben Videoschnipseln und keinem Foto.
Future<int> aktuelleFassung() async {
  final frisch = AppDatabase(NativeDatabase.memory());
  final v = await frisch
      .customSelect('PRAGMA user_version')
      .map((r) => r.read<int>('user_version'))
      .getSingle();
  await frisch.close();
  return v;
}

void main() {
  late Directory temp;
  late File datei;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_livephoto_');
    datei = File(p.join(temp.path, 'library.sqlite'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  /// Ein Live Photo: Foto und Videohälfte, beide auf dieselbe Sekunde und
  /// denselben Ort, wechselseitig verknüpft – so legt der Import sie an.
  Future<void> livePhoto(AppDatabase db, String nr,
      {required DateTime zeit, double? breite, double? laenge}) async {
    for (final (id, typ, endung) in [
      ('$nr-foto', 'IMAGE', 'JPG'),
      ('$nr-video', 'VIDEO', 'MOV'),
    ]) {
      await db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.$endung',
        originalFileName: 'IMG_$nr.$endung',
        type: typ,
        checksum: id,
        fileCreatedAt: zeit,
        importedAt: zeit,
        isTrashed: const Value(false),
        latitude: Value(breite),
        longitude: Value(laenge),
        linkedAssetId:
            Value(typ == 'IMAGE' ? '$nr-video' : '$nr-foto'),
      ));
    }
  }

  group('Die Erkennung sieht nur die Zeitleisten-Einträge', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await livePhoto(db, '01',
          zeit: DateTime(2026, 5, 1, 10), breite: 52.1, laenge: 10.5);
      await livePhoto(db, '02', zeit: DateTime(2026, 5, 1, 11));
      // Ein gewöhnliches Foto und ein eigenständiges Video – beide
      // gehören dazu und dürfen NICHT mit herausfallen.
      await db.insertAsset(AssetsCompanion.insert(
        id: 'einzeln-foto',
        relativePath: 'originals/e.jpg',
        originalFileName: 'e.jpg',
        type: 'IMAGE',
        checksum: 'e',
        fileCreatedAt: DateTime(2026, 5, 1, 12),
        importedAt: DateTime(2026, 5, 1, 12),
        isTrashed: const Value(false),
        latitude: const Value(52.2),
        longitude: const Value(10.6),
      ));
      await db.insertAsset(AssetsCompanion.insert(
        id: 'einzeln-video',
        relativePath: 'originals/v.mp4',
        originalFileName: 'v.mp4',
        type: 'VIDEO',
        checksum: 'v',
        fileCreatedAt: DateTime(2026, 5, 1, 13),
        importedAt: DateTime(2026, 5, 1, 13),
        isTrashed: const Value(false),
        latitude: const Value(52.3),
        longitude: const Value(10.7),
      ));
    });
    tearDown(() => db.close());

    test('die verortete Videohälfte fällt heraus, das Foto bleibt', () async {
      final ids = {
        for (final a in await db.aufnahmenFuerReiseerkennung()) a.id
      };
      expect(ids, contains('01-foto'));
      expect(ids, isNot(contains('01-video')),
          reason: 'sonst bildet sie hinterher einen eigenen Vorschlag');
    });

    test('ein eigenständiges Video bleibt drin', () async {
      // Die Gegenprobe: Es geht um die HÄLFTE eines Live Photos, nicht um
      // Videos. Ein Video von der Wanderung ist eine Aufnahme wie jede.
      final ids = {
        for (final a in await db.aufnahmenFuerReiseerkennung()) a.id
      };
      expect(ids, contains('einzeln-video'));
      expect(ids, contains('einzeln-foto'));
    });

    test('auch ohne Koordinate zählt nur die Zeitleisten-Hälfte', () async {
      // Diese Liste wird einer erkannten Reise zugeschlagen – eine
      // Videohälfte doppelte dort jedes Live Photo.
      final ids = {for (final a in await db.aufnahmenOhneKoordinate()) a.id};
      expect(ids, contains('02-foto'));
      expect(ids, isNot(contains('02-video')));
    });
  });

  group('Die Reparatur 64 → 65', () {
    Future<void> aufFassung64() async {
      final db = AppDatabase(NativeDatabase(datei));
      await db.customStatement('PRAGMA user_version = 64');
      await db.close();
    }

    test('eine Zuordnung auf die Videohälfte wird zum Foto', () async {
      var db = AppDatabase(NativeDatabase(datei));
      await livePhoto(db, '01',
          zeit: DateTime(2026, 5, 1, 10), breite: 52.1, laenge: 10.5);
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'a1',
          name: 'Gifhorn',
          art: 'spaziergang',
          von: DateTime(2026, 5, 1, 9),
          bis: DateTime(2026, 5, 1, 11),
          angelegtAm: DateTime(2026, 5, 1),
        ),
        const ['01-video'],
      );
      await db.close();
      await aufFassung64();

      db = AppDatabase(NativeDatabase(datei));
      final drin = await db.aufnahmenDerAktivitaet('a1');
      final fassung = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      await db.close();

      expect(fassung, await aktuelleFassung());
      expect(drin.map((a) => a.id), ['01-foto'],
          reason: 'die Aktivität bestand aus einem Videoschnipsel und '
              'keinem einzigen Foto');
    });

    test('ist das Foto schon zugeordnet, bleibt es bei einem Eintrag',
        () async {
      // Der Fall, an dem eine Reparatur ohne `INSERT OR IGNORE` jedes Live
      // Photo verdoppelt hätte.
      var db = AppDatabase(NativeDatabase(datei));
      await livePhoto(db, '01',
          zeit: DateTime(2026, 5, 1, 10), breite: 52.1, laenge: 10.5);
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'a1',
          name: 'Köln',
          art: 'spaziergang',
          von: DateTime(2026, 5, 1, 9),
          bis: DateTime(2026, 5, 1, 11),
          angelegtAm: DateTime(2026, 5, 1),
        ),
        const ['01-foto', '01-video'],
      );
      await db.close();
      await aufFassung64();

      db = AppDatabase(NativeDatabase(datei));
      final drin = await db.aufnahmenDerAktivitaet('a1');
      await db.close();
      expect(drin.map((a) => a.id), ['01-foto']);
    });

    test('eine Reise wird genauso berichtigt', () async {
      var db = AppDatabase(NativeDatabase(datei));
      await livePhoto(db, '01',
          zeit: DateTime(2026, 5, 1, 10), breite: 52.1, laenge: 10.5);
      await db.reiseAnlegen(
        ReisenCompanion.insert(
          id: 'r1',
          name: 'Harz',
          von: DateTime(2026, 5, 1),
          bis: DateTime(2026, 5, 3),
          angelegtAm: DateTime(2026, 5, 1),
        ),
        const ['01-video'],
      );
      await db.close();
      await aufFassung64();

      db = AppDatabase(NativeDatabase(datei));
      final drin = await db.aufnahmenDerReise('r1');
      await db.close();
      expect(drin.map((a) => a.id), ['01-foto']);
    });

    test('ein eigenständiges Video bleibt zugeordnet', () async {
      // Die wichtigste Gegenprobe: Die Reparatur darf nur die HÄLFTEN
      // anfassen. Ein Video, das für sich steht, gehört zur Aktivität und
      // hat kein Foto, auf das sich umbiegen liesse – es wäre sonst
      // spurlos verschwunden.
      var db = AppDatabase(NativeDatabase(datei));
      await db.insertAsset(AssetsCompanion.insert(
        id: 'v1',
        relativePath: 'originals/v.mp4',
        originalFileName: 'v.mp4',
        type: 'VIDEO',
        checksum: 'v',
        fileCreatedAt: DateTime(2026, 5, 1, 10),
        importedAt: DateTime(2026, 5, 1, 10),
        isTrashed: const Value(false),
      ));
      await db.aktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'a1',
          name: 'Wanderung',
          art: 'wanderung',
          von: DateTime(2026, 5, 1, 9),
          bis: DateTime(2026, 5, 1, 11),
          angelegtAm: DateTime(2026, 5, 1),
        ),
        const ['v1'],
      );
      await db.close();
      await aufFassung64();

      db = AppDatabase(NativeDatabase(datei));
      final drin = await db.aufnahmenDerAktivitaet('a1');
      await db.close();
      expect(drin.map((a) => a.id), ['v1']);
    });
  });
}

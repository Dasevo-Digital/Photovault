import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Ortsnachtrag an einer **echten** Bibliothek.
///
/// Läuft nur, wenn `PV_ECHTE_BIBLIOTHEK` auf einen Ordner zeigt, der eine
/// `library.sqlite` **und** den Ordner `library/` enthält – sonst hinge die
/// Suite an Dateien, die es auf keiner anderen Maschine gibt.
///
/// **Die Datenbank wird verändert, die Dateien nicht.** Deshalb muss die
/// Umgebungsvariable auf eine *Kopie* zeigen; der Test schreibt in die
/// `library.sqlite`, die er dort findet.
///
/// Der Grund für diesen Test: An gebauten Bytes lässt sich prüfen, dass
/// der Leser die drei Ablagen versteht. Ob er an 440 gewachsenen Dateien
/// dasselbe tut wie `exiftool`, lässt sich nur dort feststellen – und die
/// erste Fassung fand 213 von 246, weil sie `loci` nicht kannte und 31
/// „Videos" in Wahrheit JPEG waren.
void main() {
  final ordner = Platform.environment['PV_ECHTE_BIBLIOTHEK'];

  test('Videos bekommen ihre Orte', () async {
    if (ordner == null) {
      markTestSkipped('PV_ECHTE_BIBLIOTHEK nicht gesetzt');
      return;
    }
    final datenbank = File(p.join(ordner, 'library.sqlite'));
    expect(datenbank.existsSync(), isTrue, reason: 'library.sqlite fehlt');

    final db = AppDatabase(NativeDatabase(datenbank));
    addTearDown(db.close);
    final pfade =
        await StoragePaths.forTesting(Directory(p.join(ordner, 'library')));
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = ImportService(db, pfade);

    Future<int> mitOrt(String art) async => (await db
            .customSelect(
                "SELECT count(*) AS n FROM assets WHERE type = '$art' "
                'AND latitude IS NOT NULL')
            .getSingle())
        .read<int>('n');

    final vorherVideo = await mitOrt('VIDEO');
    final uhr = Stopwatch()..start();
    await library.backfillLocations().drain<void>();
    uhr.stop();
    final nachherVideo = await mitOrt('VIDEO');

    // ignore: avoid_print
    print('Videos mit Ort: $vorherVideo -> $nachherVideo '
        '(${uhr.elapsedMilliseconds} ms)');
    expect(nachherVideo, greaterThan(vorherVideo),
        reason: 'der Lauf muss Orte dazugewinnen');

    // Und die Dateiarten: Was in Wahrheit ein Standbild ist, muss danach
    // als Bild geführt werden.
    final vorherVideos = (await db
            .customSelect("SELECT count(*) AS n FROM assets WHERE type='VIDEO'")
            .getSingle())
        .read<int>('n');
    await library.repariereDateiarten().drain<void>();
    final nachherVideos = (await db
            .customSelect("SELECT count(*) AS n FROM assets WHERE type='VIDEO'")
            .getSingle())
        .read<int>('n');
    // ignore: avoid_print
    print('als Video geführt: $vorherVideos -> $nachherVideos');
    expect(nachherVideos, lessThan(vorherVideos));

    // Danach greift für die berichtigten Aufnahmen der gewöhnliche
    // EXIF-Weg – ein zweiter Lauf holt ihre Orte nach.
    await library.backfillLocations().drain<void>();
    final gesamtMitOrt = (await db
            .customSelect(
                'SELECT count(*) AS n FROM assets WHERE latitude IS NOT NULL')
            .getSingle())
        .read<int>('n');
    // ignore: avoid_print
    print('Aufnahmen mit Ort insgesamt: $gesamtMitOrt');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

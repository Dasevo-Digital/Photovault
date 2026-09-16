import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/screens/stack_review_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Der Vorrat an Serienvorschlägen.**
///
/// Die Rechnung kostet an der gewachsenen Bibliothek 260 ms – gemessen
/// über eine Verbindung wie in der App, mit der Datenbank auf einem
/// eigenen Isolate (7441 Einbettungen, 499 Gruppen). Gelaufen ist sie
/// **zweimal je Rundgang**: beim Öffnen des Serienbildschirms und noch
/// einmal, wenn die Werkzeugliste nach der Rückkehr ihre Zahl
/// auffrischte.
///
/// Geprüft wird deshalb nicht die Zeit – die hängt an der Maschine –,
/// sondern wie oft gerechnet wird.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_vorrat_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Zwei Gruppen zu je drei Aufnahmen, dicht beieinander in Zeit und
  /// Inhalt – genau das, was die Erkennung zusammenfasst.
  Future<void> zweiSerien() async {
    final zufall = Random(3);
    for (var g = 0; g < 2; g++) {
      final basis = Float32List(512);
      for (var i = 0; i < 512; i++) {
        basis[i] = zufall.nextDouble() - 0.5;
      }
      for (var k = 0; k < 3; k++) {
        final id = 'g${g}_$k';
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'o/$id.jpg',
              checksum: 'c$id',
              type: 'IMAGE',
              fileCreatedAt:
                  DateTime(2026, 1, 1).add(Duration(hours: g, seconds: k * 2)),
              importedAt: DateTime(2026),
              sharpnessScore: Value(k.toDouble()),
            ));
        final v = Float32List.fromList(basis);
        v[0] += k * 0.00001;
        await db.saveEmbedding(id, v);
      }
    }
  }

  test('zweimal gefragt heisst nicht zweimal gerechnet', () async {
    await zweiSerien();
    final erst = await library.serienvorschlaegeGecacht();
    final zweit = await library.serienvorschlaegeGecacht();
    expect(erst, hasLength(2));
    // Dasselbe Ergebnis, und zwar buchstaeblich dasselbe: Eine zweite
    // Rechnung ergaebe gleiche, aber neue Listen.
    expect(identical(erst, zweit), isTrue);
  });

  test('eine erledigte Gruppe ist aus dem Vorrat', () async {
    await zweiSerien();
    final vorrat = await library.serienvorschlaegeGecacht();
    library.serieErledigt(vorrat.first);
    expect(await library.serienvorschlaegeGecacht(), hasLength(1));
  });

  test('alle erledigt heisst leer, ohne neue Rechnung', () async {
    await zweiSerien();
    await library.serienvorschlaegeGecacht();
    library.serienGeleert();
    expect(await library.serienvorschlaegeGecacht(), isEmpty);
  });

  test('nach einem Import wird neu gerechnet', () async {
    // Der Fall, in dem der Vorrat wirklich veraltet: Es gibt neue
    // Einbettungen, also kann es neue Gruppen geben.
    await zweiSerien();
    expect(await library.serienvorschlaegeGecacht(), hasLength(2));
    library.serienGeleert();
    expect(await library.serienvorschlaegeGecacht(), isEmpty);

    // moveToTrash zaehlt die Einbettungsfassung hoch - damit ist der
    // Vorrat hinfaellig und die Rechnung laeuft wieder.
    await db.moveToTrash(['g0_0']);
    expect(await library.serienvorschlaegeGecacht(), isNotEmpty);
  });
  group('die Titelbild-Wahl zieht mit', () {
    /// Die Karte der Sternwahl war nach **Listenplatz** geordnet, die
    /// Liste aber schrumpft mit jeder uebernommenen Gruppe. Wer Gruppe 1
    /// uebernahm, rueckte Gruppe 2 auf Platz 1 – und bekam dort die
    /// Sternwahl der uebernommenen. Der Rumpf, der das haette richten
    /// sollen, schrieb jeden Platz auf sich selbst zurueck.
    ///
    /// Aufgerufen wird die Rechnung des Bildschirms selbst. Sie
    /// nachzubauen hiesse, einen Pruefstand zu haben, der auch dann
    /// haelt, wenn die echte Rechnung falsch ist.
    const nachEntfernen = verschobeneTitelwahl;

    test('die Wahl der nachfolgenden Gruppen bleibt bei ihnen', () {
      final vorher = {0: 2, 1: 0, 2: 1};
      expect(nachEntfernen(vorher, 0), {0: 0, 1: 1});
    });

    test('vor der entfernten aendert sich nichts', () {
      expect(nachEntfernen({0: 2, 1: 0, 2: 1}, 2), {0: 2, 1: 0});
    });

    test('die entfernte selbst faellt heraus', () {
      expect(nachEntfernen({0: 2, 1: 0, 2: 1}, 1), {0: 2, 1: 1});
    });
  });

}

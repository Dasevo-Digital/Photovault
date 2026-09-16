import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/embedding_similarity.dart';

/// Was [findBurstGroups] an einer **echten** Bibliothek findet.
///
/// Läuft nur mit `PV_ECHTE_DB` auf eine `library.sqlite`. Der Anlass: In
/// der Prüfbibliothek gibt es 0 Stapel, obwohl eine Zählung nach Zeit und
/// Kamera 107 Serien mit 606 Aufnahmen findet. Entweder ist die Erkennung
/// zu streng, oder niemand hat den Bildschirm je geöffnet – und das lässt
/// sich nur durch Nachrechnen unterscheiden.
void main() {
  final pfad = Platform.environment['PV_ECHTE_DB'];

  test('Serienerkennung an echten Einbettungen', () async {
    if (pfad == null) {
      markTestSkipped('PV_ECHTE_DB nicht gesetzt');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(pfad)));
    addTearDown(db.close);
    final zeilen = await db.customSelect(
        'SELECT e.asset_id AS id, e.vector AS v, a.file_created_at AS t, '
        'a.camera_model AS k FROM image_embeddings e '
        'JOIN assets a ON a.id = e.asset_id '
        'WHERE a.is_trashed = 0 AND a.is_locked = 0').get();
    final einbettungen = <String, Float32List>{};
    final zeiten = <String, DateTime>{};
    for (final z in zeilen) {
      einbettungen[z.read<String>('id')] =
          floatsFromEmbeddingBlob(z.read<Uint8List>('v'));
      zeiten[z.read<String>('id')] =
          DateTime.fromMillisecondsSinceEpoch(z.read<int>('t') * 1000);
    }
    // ignore: avoid_print
    print('${einbettungen.length} Einbettungen');

    for (final paar in [
      (0.92, 30),
      (0.92, 5),
      (0.88, 30),
      (0.85, 30),
      (0.80, 30),
    ]) {
      final uhr = Stopwatch()..start();
      final gruppen = findBurstGroups(BurstSearchParams(einbettungen, zeiten,
          threshold: paar.$1, maxGap: Duration(seconds: paar.$2)));
      final brauchbar =
          gruppen.where((g) => g.length >= 2 && g.length <= 20).toList();
      final gross = gruppen.where((g) => g.length > 20).length;
      // ignore: avoid_print
      print('Schwelle ${paar.$1}, Lücke ${paar.$2}s: ${gruppen.length} Gruppen, '
          'davon ${brauchbar.length} mit 2..20 '
          '(${brauchbar.fold<int>(0, (s, g) => s + g.length)} Aufnahmen), '
          '$gross zu gross, ${uhr.elapsedMilliseconds} ms');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

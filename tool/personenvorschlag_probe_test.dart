import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/embedding_codec.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/personenvorschlag.dart';

/// Was wuerde eine automatische Wiedererkennung an einer echten
/// Bibliothek finden?
///
///   PV_DB=/pfad/zur/kopie.sqlite flutter test tool/personenvorschlag_probe_test.dart
///
/// Gerechnet wird mit dem Erkennungscode der App selbst
/// ([personenkerne], [besterTreffer]) und den Schwellen aus derselben
/// Datenbank – eine Nachbildung wuerde etwas anderes messen als das,
/// was die App taete.
void main() {
  final pfad = Platform.environment['PV_DB'];

  test('Vorschlaege fuer die noch nicht zugeordneten Gesichter', () async {
    if (pfad == null) {
      // ignore: avoid_print
      print('PV_DB nicht gesetzt - uebersprungen.');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(pfad)));
    final allgemein = await db.faceSimilarityThresholdWert();
    final leute = {for (final p in await db.select(db.people).get()) p.id: p};

    final roh = await db.einbettungenZugeordneterGesichter();
    final kerne = personenkerne([
      for (final e in roh)
        if (leute.containsKey(e.personId))
          (personId: e.personId, vektor: floatsFromEmbeddingBlob(e.vektor)),
    ]);
    double schwelleFuer(String id) =>
        leute[id]?.similarityThreshold ?? allgemein;

    // ignore: avoid_print
    print('Kerne: ${kerne.length} Personen aus ${roh.length} Einbettungen, '
        'allgemeine Schwelle $allgemein');

    for (final fall in ['beiseitegelegt', 'offen']) {
      final zeilen = await db.customSelect(
        'SELECT f.id, f.embedding, f.is_ignored FROM faces f '
        'JOIN assets a ON a.id = f.asset_id '
        'WHERE f.person_id IS NULL AND f.embedding IS NOT NULL '
        '  AND f.is_ignored = ${fall == 'beiseitegelegt' ? 1 : 0} '
        '  AND a.is_trashed = 0 AND a.is_locked = 0',
      ).get();

      var treffer = 0;
      final jePerson = <String, int>{};
      final werte = <double>[];
      for (final z in zeilen) {
        final v = floatsFromEmbeddingBlob(z.read<Uint8List>('embedding'));
        var beste = 0.0;
        for (final k in kerne) {
          final s = FaceEngineService.cosineSimilarity(v, k.kern);
          if (s > beste) beste = s;
        }
        werte.add(beste);
        final t = besterTreffer(v, kerne, schwelleFuer: schwelleFuer);
        if (t != null) {
          treffer++;
          jePerson[t.personId] = (jePerson[t.personId] ?? 0) + 1;
        }
      }
      werte.sort();
      String q(double p) => werte.isEmpty
          ? '-'
          : werte[(werte.length * p).clamp(0, werte.length - 1).floor()]
              .toStringAsFixed(3);

      // ignore: avoid_print
      print('\n$fall: ${zeilen.length} Gesichter mit Einbettung');
      // ignore: avoid_print
      print('  Vorschlag ueber der Schwelle: $treffer '
          '(${zeilen.isEmpty ? 0 : (100 * treffer / zeilen.length).round()} %)');
      // ignore: avoid_print
      print('  beste Aehnlichkeit  Median ${q(0.5)}  90% ${q(0.9)}  '
          '99% ${q(0.99)}  max ${werte.isEmpty ? '-' : werte.last.toStringAsFixed(3)}');
      for (final sch in [0.363, 0.45, 0.50, 0.55, 0.60, 0.65]) {
        final n = werte.where((w) => w >= sch).length;
        // ignore: avoid_print
        print('    Schwelle ${sch.toStringAsFixed(3)}: $n '
            '(${zeilen.isEmpty ? 0 : (100 * n / zeilen.length).round()} %)');
      }
      final sortiert = jePerson.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sortiert.take(8)) {
        // ignore: avoid_print
        print('    ${leute[e.key]?.name ?? e.key}: ${e.value}');
      }
    }
    await db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}

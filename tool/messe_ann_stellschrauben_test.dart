// Laesst sich der SimHash-Vorfilter auf eine brauchbare Trefferquote
// bringen - und was kostet sie an Kandidaten?
//
// Dieselbe Rechnung wie in `EmbeddingAnnIndex`, nur mit veraenderbaren
// Konstanten. Gesucht wird ein Punkt mit hoher Trefferquote UND kleiner
// Kandidatenmenge; gibt es den nicht, ist der Vorfilter nicht zu retten.
//
//   PV_DB=<kopie> flutter test tool/messe_ann_stellschrauben_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

int _mix(int value) {
  var x = value & 0x7fffffff;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0x7fffffff;
  return (x ^ (x >> 16)) & 0x7fffffff;
}

int _signatur(Float32List v, int table, int bits, int samples) {
  var sig = 0;
  for (var bit = 0; bit < bits; bit++) {
    var sum = 0.0;
    for (var s = 0; s < samples; s++) {
      final seed = _mix(table * 0x9e3779b9 ^ bit * 0x85ebca6b ^ s);
      final wert = v[seed % v.length];
      sum += (seed & 1) == 0 ? wert : -wert;
    }
    if (sum >= 0) sig |= 1 << bit;
  }
  return sig;
}

double _kosinus(Float32List a, Float32List b) {
  var d = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    d += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return (na == 0 || nb == 0) ? 0 : d / (math.sqrt(na) * math.sqrt(nb));
}

void main() {
  test('Stellschrauben des Vorfilters', () {
    final db = sqlite3.open(
        'file:${Platform.environment['PV_DB']}?mode=ro', uri: true);
    final einbettungen = <String, Float32List>{};
    for (final z in db.select('''
        SELECT e.asset_id AS id, e.vector AS v FROM image_embeddings e
        JOIN assets a ON a.id = e.asset_id
        WHERE a.is_trashed = 0 AND a.is_locked = 0 ORDER BY e.asset_id''')) {
      final roh = z['v'] as Uint8List;
      einbettungen[z['id'] as String] = Float32List.fromList(Float32List.view(
          roh.buffer, roh.offsetInBytes, roh.lengthInBytes ~/ 4));
    }
    db.close();
    final alle = einbettungen.keys.toList();
    debugPrint('${alle.length} Vektoren\n');

    // Dieselben Abfragen fuer jede Einstellung, damit die Zahlen
    // vergleichbar bleiben.
    final zufall = math.Random(7);
    const laeufe = 20;
    const gezeigt = 60;
    final abfragen = [
      for (var i = 0; i < laeufe; i++) alle[zufall.nextInt(alle.length)]
    ];
    final sollJeAbfrage = <List<String>>[];
    for (final id in abfragen) {
      final q = einbettungen[id]!;
      final rang = einbettungen.entries
          .map((e) => MapEntry(e.key, _kosinus(q, e.value)))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      sollJeAbfrage.add(rang.take(gezeigt).map((e) => e.key).toList());
    }

    debugPrint('Tab x Bit  Nachbarbits   Kandidaten   Trefferquote top-$gezeigt');
    for (final (tabellen, bits) in [
      (8, 8),
      (16, 8),
      (32, 8),
      (16, 6),
      (32, 6),
      (64, 6),
      (32, 4),
      (64, 4),
    ]) {
      final eimer = <int, List<String>>{};
      for (final id in alle) {
        final v = einbettungen[id]!;
        for (var t = 0; t < tabellen; t++) {
          eimer
              .putIfAbsent(
                  (t << bits) | _signatur(v, t, bits, 32), () => <String>[])
              .add(id);
        }
      }
      for (final nachbarn in [true, false]) {
        var treffer = 0, soll = 0, kand = 0;
        for (var i = 0; i < abfragen.length; i++) {
          final q = einbettungen[abfragen[i]]!;
          final menge = <String>{};
          for (var t = 0; t < tabellen; t++) {
            final sig = _signatur(q, t, bits, 32);
            menge.addAll(eimer[(t << bits) | sig] ?? const []);
            if (nachbarn) {
              for (var b = 0; b < bits; b++) {
                menge.addAll(eimer[(t << bits) | (sig ^ (1 << b))] ?? const []);
              }
            }
          }
          kand += menge.length;
          treffer += sollJeAbfrage[i].where(menge.contains).length;
          soll += sollJeAbfrage[i].length;
        }
        final anteil = kand / abfragen.length / alle.length * 100;
        debugPrint('${tabellen.toString().padLeft(3)} x $bits  '
            '${(nachbarn ? "alle" : "keine").padRight(11)}  '
            '${(kand / abfragen.length).round().toString().padLeft(6)} '
            '(${anteil.toStringAsFixed(0).padLeft(3)} %)   '
            '${(treffer / soll * 100).toStringAsFixed(1)} %');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

@TestOn('mac-os')
library;

// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/ai_tagging_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:sqlite3/sqlite3.dart';

/// **Wie viele Schlagwörter vergibt welche Regel?** – an einer echten
/// Bibliothek gemessen, nicht an einem Gedankenspiel.
///
/// Läuft nur auf Zuruf und nur, wenn beide Pfade gesetzt sind:
///
/// ```
/// flutter test integration_test/ki_tag_auswahl_messung_test.dart -d macos \
///   --dart-define=PV_MESS_DB=…/library.sqlite \
///   --dart-define=PV_MESS_MODELLE=…/models
/// ```
///
/// Als Integrationstest, weil der Modellkanal einen laufenden Prozess
/// braucht – `flutter test` hat keinen.
///
/// Die Bibliothek wird **nur gelesen** (`mode: OpenMode.readOnly`); die
/// Bild-Vektoren liegen fertig in `image_embeddings` und das Modell wird
/// allein für die 55 Vokabelbegriffe gebraucht.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const dbPfad = String.fromEnvironment('PV_MESS_DB');
  const modelle = String.fromEnvironment('PV_MESS_MODELLE');

  testWidgets('alte gegen neue Auswahlregel', (tester) async {
    if (dbPfad.isEmpty || modelle.isEmpty) {
      markTestSkipped('PV_MESS_DB und PV_MESS_MODELLE nicht gesetzt');
      return;
    }
    final clip = await ClipService.load(modelle, bild: false);
    addTearDown(clip.dispose);

    final db = sqlite3.open(dbPfad, mode: OpenMode.readOnly);
    addTearDown(db.close);

    final begriffe = [
      for (final r in db.select(
          'SELECT term FROM ai_tag_vocabulary ORDER BY term'))
        r['term'] as String
    ];
    expect(begriffe, isNotEmpty, reason: 'kein Vokabular in der Bibliothek');

    final begriffsVektoren = <Float32List>[];
    for (final b in begriffe) {
      begriffsVektoren.add(await clip.embedText(await begriffFuerModell(b, null)));
    }

    double cosinus(Float32List a, Float32List b) {
      var s = 0.0;
      final n = math.min(a.length, b.length);
      for (var i = 0; i < n; i++) {
        s += a[i] * b[i];
      }
      return s;
    }

    final zeilen = db.select(
        'SELECT vector FROM image_embeddings LIMIT 1500');
    var altSumme = 0, neuSumme = 0, neuLeer = 0;
    final altVerteilung = <int, int>{};
    final neuVerteilung = <int, int>{};
    final altBegriff = <String, int>{};
    final neuBegriff = <String, int>{};

    for (final z in zeilen) {
      final roh = z['vector'] as Uint8List;
      final bild = Float32List.view(
          roh.buffer, roh.offsetInBytes, roh.lengthInBytes ~/ 4);
      final naehe = [for (final v in begriffsVektoren) cosinus(bild, v)];

      final alt = [
        for (var i = 0; i < begriffe.length; i++)
          if (naehe[i] >= 0.24) begriffe[i]
      ];
      final neu = waehleTags(begriffe, naehe);

      altSumme += alt.length;
      neuSumme += neu.length;
      if (neu.isEmpty) neuLeer++;
      altVerteilung[alt.length] = (altVerteilung[alt.length] ?? 0) + 1;
      neuVerteilung[neu.length] = (neuVerteilung[neu.length] ?? 0) + 1;
      for (final t in alt) {
        altBegriff[t] = (altBegriff[t] ?? 0) + 1;
      }
      for (final t in neu) {
        neuBegriff[t] = (neuBegriff[t] ?? 0) + 1;
      }
    }

    String top(Map<String, int> m) {
      final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      return e.take(8).map((x) => '${x.key} ${x.value}').join(', ');
    }

    print('Aufnahmen: ${zeilen.length}, Vokabular: ${begriffe.length}');
    print('alt: ${(altSumme / zeilen.length).toStringAsFixed(1)} je Foto');
    print('     ${top(altBegriff)}');
    print('neu: ${(neuSumme / zeilen.length).toStringAsFixed(1)} je Foto, '
        '$neuLeer ohne Schlagwort');
    print('     ${top(neuBegriff)}');
    print('Verteilung alt: ${(altVerteilung.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => "${e.key}:${e.value}").join(" ")}');
    print('Verteilung neu: ${(neuVerteilung.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => "${e.key}:${e.value}").join(" ")}');

    expect(neuSumme, lessThan(altSumme));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

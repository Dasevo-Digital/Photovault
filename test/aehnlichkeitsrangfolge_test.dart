import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/clip_service.dart';

void main() {
  final kandidaten = <String, Float32List>{
    'schwach': Float32List.fromList([0.1, 0]),
    'gleich_a': Float32List.fromList([0.7, 0]),
    'staerkste': Float32List.fromList([0.9, 0]),
    'gleich_b': Float32List.fromList([0.7, 0]),
  };

  test('Top-K-Heap behält nur die besten Treffer in stabiler Reihenfolge', () {
    final rang = ClipService.rankBySimilarity(
      Float32List.fromList([1, 0]),
      kandidaten,
      topK: 3,
    );

    expect(rang.map((e) => e.key), ['staerkste', 'gleich_a', 'gleich_b']);
  });

  /// Der Haufen darf nicht nur die richtigen Treffer behalten, sondern muss
  /// bei gleichem Abstand auch **immer dieselben** liefern. Zwei Fotos mit
  /// identischer Ähnlichkeit gibt es in einer echten Bibliothek reichlich
  /// (dasselbe Motiv zweimal gedrückt), und eine Trefferliste, die bei
  /// jedem Aufruf anders herum steht, sieht aus wie ein Fehler.
  test('bei gleichem Abstand gewinnt der zuerst gesehene Eintrag', () {
    for (var i = 0; i < 20; i++) {
      final rang = ClipService.rankBySimilarity(
        Float32List.fromList([1, 0]),
        kandidaten,
        topK: 2,
      );
      expect(rang.map((e) => e.key), ['staerkste', 'gleich_a']);
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/speicher_rueckgabe.dart';

/// Anlass: Eine Linux-Instanz, die knapp dreizehn Stunden gelaufen war,
/// hielt 2,4 GB – davon 1,5 GB liegengebliebener Heap der C-Bibliothek,
/// bei nur 62 MB Dart-Heap. Ein `malloc_trim(0)` gab davon 692 MB
/// zurück. Diese Tests sichern das Verhalten der Anbindung ab, nicht die
/// Wirkung – die ist eine Frage der Messung, nicht der Zusicherung.
void main() {
  test('nur dort, wo es die Funktion gibt', () {
    // glibc hat `malloc_trim`, musl nicht. Zielumgebung ist Ubuntu bzw.
    // die GNOME-Flatpak-Laufzeit, beide glibc.
    expect(SpeicherRueckgabe.moeglich, Platform.isLinux);
  });

  test('auf fremden Plattformen ein stiller Nichtstuer', () {
    if (Platform.isLinux) return;
    expect(SpeicherRueckgabe.jetzt(), isFalse);
  });

  test('wirft nie, auch bei mehrfachem Aufruf', () {
    expect(() {
      SpeicherRueckgabe.jetzt();
      SpeicherRueckgabe.jetzt();
    }, returnsNormally);
  });
}

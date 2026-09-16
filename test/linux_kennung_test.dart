import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die GTK-Kennung bestimmt, **wo die Daten liegen**: unter Linux
/// `~/.local/share/<kennung>/`, im Flatpak
/// `~/.var/app/…/data/<kennung>/`. Wird sie geändert, sucht die App an
/// einer neuen Stelle – und eine bereits benutzte Installation begrüsst
/// den Nutzer mit dem Startbildschirm, als wäre sie frisch. Die alte
/// Bibliothek liegt dann unerreichbar daneben.
///
/// Genau das ist in der zehnten Prüfrunde einmal passiert, beim Versuch,
/// die Fensterklasse an die Flatpak-Kennung anzugleichen. Die Zuordnung
/// von Fenster und Starter gehört in `StartupWMClass`, nicht hierher.
void main() {
  const erwarteteKennung = 'com.example.photo_vault';

  test('die GTK-Kennung ist unverändert – sie bestimmt den Ablageort', () {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(
      cmake,
      contains('set(APPLICATION_ID "$erwarteteKennung")'),
      reason: 'Eine Änderung verschiebt den Datenordner bestehender '
          'Installationen. Nur zusammen mit einer Umzugslogik ändern.',
    );
  });

  test('der Starter zeigt auf genau diese Fensterklasse', () {
    final desktop =
        File('packaging/flatpak/com.example.PhotoVault.desktop').readAsStringSync();
    expect(
      desktop,
      contains('StartupWMClass=$erwarteteKennung'),
      reason: 'Stimmt die Klasse nicht, ordnet die Arbeitsumgebung das '
          'Fenster keinem Starter zu: kein Symbol, kein Name in der Leiste.',
    );
  });
}

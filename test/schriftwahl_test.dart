import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Die Oberflächenschrift war fest auf `.AppleSystemUIFont` gesetzt – ein
/// Name, den nur macOS kennt. Überall sonst bekam die Oberfläche dadurch
/// still Flutters Standardschrift statt der Schrift der Arbeitsumgebung.
/// Ob die neue Wahl auch wirklich greift, misst
/// `integration_test/schrift_greift_test.dart`.
void main() {
  test('jede Plattform bekommt eine Schrift, die es dort gibt', () {
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      final familie = theme.textTheme.bodyMedium?.fontFamily;
      expect(familie, isNotNull);
      final erwartet = switch (Platform.operatingSystem) {
        'macos' => '.AppleSystemUIFont',
        'windows' => 'Segoe UI Variable',
        _ => 'Adwaita Sans',
      };
      expect(familie, erwartet,
          reason: 'jede Plattform bekommt die Schrift, die es dort gibt');
    }
  });

  test('hinter der Schrift steht ein Rückfall', () {
    final rueckfall = buildLightTheme().textTheme.bodyMedium?.fontFamilyFallback;
    expect(rueckfall, isNotNull);
    expect(rueckfall, isNotEmpty,
        reason: 'fehlt die erste Wahl, muss etwas Brauchbares folgen');
  });

  test('helles und dunkles Design schreiben gleich', () {
    expect(buildLightTheme().textTheme.bodyMedium?.fontFamily,
        buildDarkTheme().textTheme.bodyMedium?.fontFamily);
  });
}

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Prüft die Persistenz des Erscheinungsbild-Modus (setThemeMode/
/// watchAppSettings) und die String<->ThemeMode-Umwandlung.
void main() {
  test('themeModeFromString/themeModeToString sind zueinander invers', () {
    for (final mode in ThemeMode.values) {
      expect(themeModeFromString(themeModeToString(mode)), mode);
    }
    // Unbekannter/fehlender Wert fällt bewusst auf System zurück, statt zu werfen.
    expect(themeModeFromString(null), ThemeMode.system);
    expect(themeModeFromString('irgendwas'), ThemeMode.system);
  });

  test('setThemeMode speichert, watchAppSettings liefert den aktuellen Wert reaktiv', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Vor dem ersten setThemeMode existiert noch keine Zeile.
    expect(await db.watchAppSettings().first, isNull);

    await db.setThemeMode('dark');
    expect((await db.watchAppSettings().first)?.themeMode, 'dark');

    await db.setThemeMode('light');
    expect((await db.watchAppSettings().first)?.themeMode, 'light');
  });
}

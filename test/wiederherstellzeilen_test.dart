import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kern/services/backup_service.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart';

/// Die Zeilen im Fenster „Wiederherstellen“.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  setUpAll(() => initializeDateFormatting());

  RestoreErgebnis ergebnis({required bool fertig}) => RestoreErgebnis(
    geplant: 2,
    importiert: 2,
    vorhanden: 0,
    fehlend: 0,
    gescheitert: 0,
    abgeschlossen: fertig,
  );

  // SIC-063: Die Übernahme aus dem Schnappschuss ist in Millisekunden
  // durch; ohne Pause stand ihre Zeile kürzer als ein Bild da.
  test(
    'die Übernahme aus dem Schnappschuss bleibt eine Weile stehen',
    () async {
      const halten = Duration(milliseconds: 300);
      final zeiten = <(String, DateTime)>[];
      await Stream<BackupProgress>.fromIterable([
            BackupProgress(2, 2, wiederherstellung: ergebnis(fertig: false)),
            BackupProgress(
              2,
              2,
              uebernommeneZeilen: 7,
              wiederherstellung: ergebnis(fertig: false),
            ),
            BackupProgress(
              2,
              2,
              uebernommeneZeilen: 7,
              wiederherstellung: ergebnis(fertig: true),
            ),
          ])
          .transform(wiederherstellZeilen(de, halten: halten))
          .forEach((z) => zeiten.add((z, DateTime.now())));

      expect(zeiten.map((z) => z.$1), [
        '2 / 2',
        de.backupUebernommen(7),
        de.backupRestoreZusammenfassung(2, 0),
      ]);
      expect(
        zeiten[2].$2.difference(zeiten[1].$2),
        greaterThanOrEqualTo(halten - const Duration(milliseconds: 20)),
      );
    },
  );
  // Nebenbefund: Das Datum der Probe stand im Fortschrittsfenster der
  // Sicherung im US-Format („11/17/2026“), auch in deutscher Oberfläche.
  test('das Datum der Probe in der Sprache der Oberfläche', () {
    final probe = BackupProbeErgebnis(
      am: DateTime(2026, 11, 17, 9, 5),
      erfolgreich: true,
      originale: 3,
      gesamt: 3,
      datenbank: true,
    );
    final zeile = backupZeile(
      de,
      BackupProgress(1, 1, wiederherstellungsprobe: probe),
    );
    expect(zeile, contains('17.11.2026'));
    expect(zeile, isNot(contains('11/17/2026')));
  });
}

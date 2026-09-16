import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// Der Schalter entscheidet, ob die rechenintensiven Auswertungen nach
/// einem Import von selbst nachlaufen. Ein falscher Standardwert wäre
/// besonders unangenehm: aus wäre die Bibliothek stillschweigend ohne
/// Suche und ohne Personen.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('ist standardmäßig eingeschaltet, auch ohne gespeicherte Zeile', () async {
    // Frische Bibliothek: In app_settings steht noch gar nichts.
    expect(await db.autoAnalyzeAfterImportEnabled(), isTrue);
  });

  test('lässt sich ausschalten und bleibt aus', () async {
    await db.setAutoAnalyzeAfterImport(false);
    expect(await db.autoAnalyzeAfterImportEnabled(), isFalse);
  });

  test('lässt sich wieder einschalten', () async {
    await db.setAutoAnalyzeAfterImport(false);
    await db.setAutoAnalyzeAfterImport(true);
    expect(await db.autoAnalyzeAfterImportEnabled(), isTrue);
  });

  test('teilt sich die Zeile mit dem Erscheinungsbild, ohne es zu überschreiben', () async {
    // Beide schreiben auf id = 0 per insertOnConflictUpdate – ohne
    // Rücksicht aufeinander würde das eine das andere zurücksetzen.
    await db.setThemeMode('dark');
    await db.setAutoAnalyzeAfterImport(false);

    final row = await db.watchAppSettings().first;
    expect(row?.themeMode, 'dark', reason: 'Erscheinungsbild darf nicht verlorengehen');
    expect(row?.autoAnalyzeAfterImport, isFalse);

    await db.setThemeMode('light');
    expect(await db.autoAnalyzeAfterImportEnabled(), isFalse,
        reason: 'Schalter darf durch einen Theme-Wechsel nicht zurückgesetzt werden');
  });
}

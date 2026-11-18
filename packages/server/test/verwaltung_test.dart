import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Die Kommandozeile `photo_vault_server konto …`: Rückgabewerte wie bei
/// Werkzeugen üblich – 0, 64 für einen falschen Aufruf (mit Hilfe), 1 für
/// ein Konto, das es nicht gibt.
void main() {
  late Directory ordner;
  late Einstellungen e;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_verwaltung_');
    e = Einstellungen.ausUmgebung({'PV_DATEN': ordner.path, 'PV_TOTP': 'frei'});
  });
  tearDown(() => ordner.delete(recursive: true));

  test('Hilfe und falsche Aufrufe', () async {
    expect(await verwalte(['hilfe'], e), 0);
    expect(await verwalte(['konto'], e), 64);
    expect(await verwalte(['kaffee'], e), 64);
  });

  test(
    'ein unbekannter Unterbefehl ist ein falscher Aufruf, auch mit Namen',
    () async {
      // Bisher suchte er zuerst das Konto: „Ein Konto „x“ gibt es nicht.“, 1.
      expect(await verwalte(['konto', 'loeschen', 'x'], e), 64);
      expect(await verwalte(['konto', 'loeschen'], e), 64);
    },
  );

  test('ein bekannter Unterbefehl für ein Konto, das es nicht gibt', () async {
    expect(await verwalte(['konto', 'passwort', 'niemand'], e), 1);
    expect(await verwalte(['konto', 'entsperren'], e), 64);
    expect(await verwalte(['konto', 'liste'], e), 0);
  });
}

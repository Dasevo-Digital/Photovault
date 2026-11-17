import 'dart:async';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Eine Bibliothek, die sich nicht öffnen lässt, beendet den Server nicht
/// (#404).
///
/// `Bibliotheken.fuer` hängt an das Öffnen einen Aufräumer, der die
/// gescheiterte Bibliothek wieder vergisst. Als Pfeil gab der die entfernte,
/// gescheiterte Future zurück – die abgeleitete scheiterte ein zweites Mal,
/// ohne dass jemand zuhörte, und der Prozess endete mit einer unbehandelten
/// Ausnahme. Schon beim Start, weil der Server dort jede Bibliothek öffnet.
void main() {
  late Directory ordner;
  late Bibliotheken bibliotheken;
  const id = '11111111-2222-3333-4444-555555555555';

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_bibl_fehler_');
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    await Process.run('chmod', ['-R', 'u+rwx', ordner.path]);
    await ordner.delete(recursive: true);
  });

  test(
    'scheitert nur für den Aufrufer, und ein zweiter Versuch gelingt',
    () async {
      final konto = Directory('${ordner.path}/bibliotheken/$id')
        ..createSync(recursive: true);
      await Process.run('chmod', ['000', konto.path]);

      final unbehandelt = <Object>[];
      await runZonedGuarded(() async {
        await expectLater(bibliotheken.fuer(id), throwsA(anything));
        // Der Aufräumer läuft danach; scheiterte er, käme es hier an.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }, (fehler, _) => unbehandelt.add(fehler));
      expect(unbehandelt, isEmpty);

      // Vergessen, nicht festgehalten: Ist der Ordner wieder lesbar, öffnet
      // der nächste Aufruf die Bibliothek.
      await Process.run('chmod', ['755', konto.path]);
      final bereich = await bibliotheken.fuer(id);
      expect(bereich.bibliothek.ordner.path, konto.path);
    },
  );
}

// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-gru: GRU-184 Teil 2 – ein echter Neustart.
//
// Ein Neustart im selben Prozess genügt hier nicht: Der Meldungsdienst ist
// ein Einzelstück und überlebt einen nachgestellten Neustart. Diese Datei
// läuft deshalb als eigener Prozess direkt nach katalog_r2_gru_test.dart
// (dieselbe Warteschlange, derselbe Testplatz). Teil 1 hat dort Meldungen
// erzeugt und die Bibliothek im Temp-Ordner des Testplatzes abgelegt;
// hier öffnet die App genau diese Bibliothek wieder – über die Umlenkung
// des Kits in einen frischen Temp-Ordner.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/meldungsdienst.dart';

import 'katalog_kit.dart';
import 'katalog_r2_gru_test.dart' hide main;

void main() {
  lebenszeichen();

  testWidgets('GRU-184 Teil 2: nach dem Neustart keine Glocke, Verlauf leer', (
    tester,
  ) async {
    filtereSemantik();
    final ablage = Directory(
      p.join(Directory.systemTemp.path, 'pv_r2gru_neustart'),
    );
    expect(
      ablage.existsSync(),
      isTrue,
      reason: 'Teil 1 (katalog_r2_gru_test.dart) lief vorher nicht',
    );
    final marke =
        jsonDecode(File(p.join(ablage.path, 'marke.json')).readAsStringSync())
            as Map<String, dynamic>;
    await starte(tester);
    await neustart(
      tester,
      dazwischen: () async {
        for (final s in ['', '-wal', '-shm']) {
          final ziel = File(p.join(anker.path, 'library.sqlite$s'));
          if (ziel.existsSync()) ziel.deleteSync();
          final quelle = File(p.join(ablage.path, 'library.sqlite$s'));
          if (quelle.existsSync()) quelle.copySync(ziel.path);
        }
        final wurzel = Directory(p.join(anker.path, 'library'));
        if (wurzel.existsSync()) wurzel.deleteSync(recursive: true);
        final r = await Process.run('/bin/cp', [
          '-R',
          p.join(ablage.path, 'library'),
          wurzel.path,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
      },
    );
    await settle(tester);
    final alle = await aufnahmen(tester);
    print(
      'GRU-184 Teil 2: ${alle.map((a) => a.originalFileName)}, '
      'Verlauf ${melde.verlauf.map((m) => m.text)}, ungelesen ${melde.ungelesen}',
    );
    expect(alle, hasLength(marke['aufnahmen']));
    expect(alle.single.originalFileName, 'gru184.jpg', reason: 'dieselbe');
    await warte(tester, const Duration(seconds: 3));
    expect(find.byTooltip(de.meldungenGlocke), findsNothing, reason: 'Glocke');
    expect(melde.ungelesen, 0);
    expect(
      melde.verlauf.where((m) => m.text.contains('vor dem Neustart')),
      isEmpty,
      reason: 'Verlauf aus Teil 1 ist weg',
    );
    expect(melde.verlauf, isEmpty, reason: 'Verlauf leer');
    ablage.deleteSync(recursive: true);
    await ende(tester);
  }, timeout: frist);
}

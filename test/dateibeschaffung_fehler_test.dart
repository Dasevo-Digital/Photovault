import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// **Ein gescheitertes Holen hinterlässt keinen unbehandelten Fehler.**
///
/// Nach jedem Lauf räumt die Beschaffung ihren Eintrag weg – über eine
/// Zukunft, die `_laufend.remove` als Pfeil zurückgab. `remove` liefert
/// den Lauf selbst, und die Zukunft übernahm dessen Ausgang: Scheiterte
/// das Holen, scheiterte sie mit, unbeachtet. Der Fehler kam als
/// unbehandelte Ausnahme an, obwohl der Aufrufer ihn abgefangen hatte
/// (ANS-061, SIC-174). Ein solcher Fehler lässt diesen Test scheitern.
void main() {
  test('KeineVerbindung kommt nur beim Aufrufer an', () async {
    final verbindung = Serververbindung(
      Uri.parse('http://127.0.0.1:9/'),
      'pruef',
      client: MockClient((_) async => throw http.ClientException('fort')),
    );
    final wurzel = Directory.systemTemp.createTempSync('pv_beschaffung_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    final pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'l')),
    );
    Dateibeschaffung(pfade, verbindung).binde();

    await expectLater(
      pfade.bereit('originals/fern.jpg'),
      throwsA(isA<KeineVerbindung>()),
    );
    // Dem Aufräumen Zeit geben – dort entstand der zweite Fehler.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Und ein neuer Versuch geht wieder ans Netz statt an einen alten Lauf.
    await expectLater(
      pfade.bereit('originals/fern.jpg'),
      throwsA(isA<KeineVerbindung>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}

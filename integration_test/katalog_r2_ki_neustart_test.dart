// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-ki: ORT-175 „nach dem Neustart wieder
// Überblick“.
//
// Der Flugstil steht in einer statischen Variablen des Geländes
// (gelaende_screen.dart:160); ein Neustart im selben Prozess setzt ihn
// nicht zurück. Diese Datei läuft deshalb in der Warteschlange **nach**
// katalog_r2_ki_ort_test.dart, dessen letzte Prüfung „Nah dran“ gewählt
// und stehen gelassen hat (und geprüft hat, dass dabei nichts in der
// Bibliothek gespeichert wird) – als eigener Prozess, also wie die App
// nach einem echten Neustart.
//
//   …/tools/e2e_queue.sh r2-ki integration_test/katalog_r2_ki_ort_test.dart \
//     integration_test/katalog_r2_ki_neustart_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;

import 'katalog_kit.dart';
import 'katalog_r2_ki_ort_test.dart' as o;
import 'katalog_r2_ki_test.dart' as r2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  r2.netzAufAttrappe();
  setUp(melde.alleSchliessen);

  testWidgets(
    timeout: r2.lang,
    'ORT-175 Nach dem Neustart startet das Gelaende wieder im Ueberblick',
    (tester) async {
      await startApp(tester);
      await o.zweiTouren(tester);
      await o.gelaendeOeffnen(tester, 'Tour A');
      expect(o.stilSymbol(tester, Icons.flight_outlined), isTrue);
      expect(o.stilSymbol(tester, Icons.directions_walk), isFalse);
      await o.gelaendeZu(tester);
      await finish(tester);
    },
  );
}

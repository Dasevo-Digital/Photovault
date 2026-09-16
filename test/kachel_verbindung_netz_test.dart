@Tags(['netz'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/kachelmitschnitt.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Der Test, der den Fehler gefangen hätte – und ihn beim nächsten Mal
/// fängt.
///
/// Läuft auf Zuruf:
///   flutter test --tags netz --run-skipped test/kachel_verbindung_netz_test.dart
///
/// **Warum es dafür einen ECHTEN Server braucht.** Der Prüfstand in
/// kachelmitschnitt_netz_test.dart misst dieselbe Verbindungsfabrik gegen
/// einen Server auf der eigenen Maschine – und der spricht `http://`.
/// Genau daran ging der Fehler vorbei: Eine selbst gelieferte Verbindung
/// bekommt von `HttpClient` **kein** TLS aufgesetzt, und ohne TLS
/// antwortet jeder https-Server mit
/// „400 The plain HTTP request was sent to HTTPS port" und macht zu. Auf
/// der eigenen Maschine, unverschlüsselt, war davon nichts zu sehen: dort
/// lief alles grün.
///
/// Ein Test, der nur das Zählen prüft, prüft nicht das Verbinden.
void main() {
  test('echte Kacheln kommen verschlüsselt an, über wenige Verbindungen',
      () async {
    Kachelmitschnitt.instanz.starte();
    addTearDown(() {
      Kachelmitschnitt.instanz
        ..halteAn()
        ..leere();
    });

    final client = kachelNetzClient();
    // Eine Handvoll benachbarter Kacheln, nicht mehr: Die Server werden
    // gespendet.
    final antworten = await Future.wait([
      for (var x = 16; x < 24; x++)
        client.get(Uri.parse('https://tile.openstreetmap.org/5/$x/10.png')),
    ]);

    for (final a in antworten) {
      expect(a.statusCode, 200, reason: a.body);
      expect(a.bodyBytes.length, greaterThan(1000));
      // Ein PNG, keine Fehlerseite.
      expect(a.bodyBytes.take(4), [0x89, 0x50, 0x4E, 0x47]);
    }

    final bilanz = Kachelmitschnitt.instanz.bilanz;
    expect(bilanz.abrufe, 8);
    expect(bilanz.geglueckt, 8);
    // **Die eigentliche Aussage.** Acht Kacheln über höchstens
    // [kachelVerbindungen] Verbindungen: Die Verbindung wird
    // wiederverwendet. Beim kaputten Stand war es genau eine Verbindung
    // je Abruf, weil der Server nach jedem 400 zumachte.
    expect(bilanz.verbindungen, lessThanOrEqualTo(kachelVerbindungen));
    expect(bilanz.ohneDauerverbindung, 0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

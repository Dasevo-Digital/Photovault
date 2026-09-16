import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/face_clustering_service.dart';

/// Fortschritt und Abbruch der automatischen Gruppierung.
///
/// Ein Fortschrittsbalken, der nicht der geleisteten Arbeit entspricht, ist
/// schlimmer als keiner: Er behauptet, gleich fertig zu sein, und steht dann
/// minutenlang. Deshalb wird hier nicht nur geprüft, DASS gemeldet wird,
/// sondern dass die Zahlen zur Dreiecksform der Vergleiche passen.
void main() {
  /// Auf dem Einheitskreis verteilte Vektoren – so, wie SFace-Embeddings
  /// ankommen (L2-normalisiert). Die Kosinus-Ähnlichkeit ist dann der
  /// Kosinus des Winkelabstands.
  Map<String, Float32List> streuung(int anzahl) => {
        for (var i = 0; i < anzahl; i++)
          'f$i': Float32List.fromList([
            math.cos(2 * math.pi * i / anzahl),
            math.sin(2 * math.pi * i / anzahl),
          ]),
      };

  test('der Anteil läuft von knapp über 0 bis 1 und niemals rückwärts', () async {
    final gemeldet = <double>[];
    final lauf = await starteFaceClustering(
      streuung(300),
      0.9,
      beiFortschritt: gemeldet.add,
    );
    final gruppen = await lauf.ergebnis;

    expect(gruppen, isNotNull);
    expect(gemeldet, isNotEmpty);
    expect(gemeldet.first, lessThan(0.5));
    expect(gemeldet.last, closeTo(1.0, 1e-9));
    for (var i = 1; i < gemeldet.length; i++) {
      expect(gemeldet[i], greaterThanOrEqualTo(gemeldet[i - 1]),
          reason: 'ein Balken darf nicht zurückspringen');
    }
  });

  test('der Anteil zählt Paare, nicht Zeilen', () async {
    // Der eigentliche Punkt. Nach der Hälfte der äusseren Schleife sind
    // dreiviertel aller Paare erledigt – ein Balken nach Zeilen stünde dort
    // bei 50 % und liefe danach doppelt so schnell. Umgekehrt: Bei 50 %
    // gemeldetem Fortschritt darf erst rund ein Drittel der Zeilen durch
    // sein, deshalb muss der gemeldete Wert früh deutlich VOR dem
    // Zeilenanteil liegen.
    final gemeldet = <double>[];
    final lauf = await starteFaceClustering(
      streuung(400),
      0.9,
      beiFortschritt: gemeldet.add,
    );
    await lauf.ergebnis;

    // Die erste Meldung kommt nach der ersten Zeile: 399 von 79.800 Paaren
    // = 0,5 %. Nach Zeilen gerechnet wären es 0,25 %.
    expect(gemeldet.first, greaterThan(1 / 400),
        reason: 'die erste Zeile ist die teuerste, nicht die billigste');
  });

  test('ein Abbruch beendet den Lauf ohne Ergebnis', () async {
    // Der Abbruch fällt bei der ersten Fortschrittsmeldung, also
    // nachweislich mitten im Lauf. Bricht man stattdessen direkt nach dem
    // Start ab, entscheidet der Zufall, ob das Isolat nicht längst fertig
    // war – der Test prüfte dann je nach Tagesform nichts.
    FaceClusterLauf? lauf;
    var abgebrochen = false;
    lauf = await starteFaceClustering(
      streuung(3000),
      0.9,
      beiFortschritt: (_) {
        if (lauf != null && !abgebrochen) {
          abgebrochen = true;
          lauf.abbrechen();
        }
      },
    );

    expect(await lauf.ergebnis, isNull);
    expect(abgebrochen, isTrue, reason: 'der Abbruch muss mitten im Lauf erfolgt sein');
  });

  test('ohne Rückkanal rechnet die Funktion wie zuvor', () async {
    // Der Fortschritt darf am Ergebnis nichts ändern – sonst hinge die
    // Gruppierung davon ab, ob jemand zusieht.
    final daten = streuung(120);
    final ohne = clusterFaces(FaceClusterInput(daten, 0.9));

    final port = ReceivePort();
    final mit = clusterFaces(FaceClusterInput(daten, 0.9, fortschritt: port.sendPort));
    port.close();

    expect(mit.map((g) => g.toList()).toList(), ohne.map((g) => g.toList()).toList());
  });
}

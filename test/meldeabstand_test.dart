import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Der Fortschritt wird zehnmal die Sekunde gemeldet, nicht achttausendmal.**
///
/// Jede Meldung des Bibliothekszustands baut den gesamten Baum unter dem
/// `Consumer<LibraryState>` in `main.dart` neu auf – und darunter liegt
/// alles, was auf dem Bildschirm steht. Die Hintergrundanalyse meldete
/// nach **jeder einzelnen Aufnahme**: über 8000 Fotos und vier Stufen
/// 32.000 Anlässe für eine Anzeige, die kein Bildschirm öfter als
/// sechzigmal die Sekunde zeigt.
///
/// Geprüft wird die Rechnung dahinter, nicht die Analyse selbst: Die
/// bräuchte Modelle, echte Bilder und Minuten. Was hier zählt, ist, dass
/// aus vielen Anlässen wenige Meldungen werden **und der letzte Stand
/// trotzdem ankommt** – sonst bliebe die Anzeige bei „7994 von 8096"
/// stehen.
void main() {
  test('der Abstand ist kurz genug, um wie Bewegung auszusehen', () {
    // Zehnmal die Sekunde: schnell genug, dass eine Zahl läuft statt zu
    // springen, langsam genug, dass sechzig Bilder je Sekunde nicht
    // sechzig Neuaufbauten bedeuten.
    expect(LibraryState.meldeabstand, const Duration(milliseconds: 100));
    expect(LibraryState.meldeabstand.inMilliseconds, greaterThan(16),
        reason: 'kuerzer als ein Bildwechsel waere sinnlos');
    expect(LibraryState.meldeabstand.inMilliseconds, lessThan(500),
        reason: 'laenger saehe wie Stillstand aus');
  });

  group('Die Regel, nach der gemeldet wird', () {
    /// Dieselbe Rechnung wie in `starteHintergrundanalyse`: melden, wenn
    /// seit der letzten Meldung mindestens [abstand] vergangen ist.
    int meldungen(List<int> zeitpunkteMs, Duration abstand) {
      var zuletzt = 0;
      var n = 0;
      for (final t in zeitpunkteMs) {
        if (t - zuletzt >= abstand.inMilliseconds) {
          zuletzt = t;
          n++;
        }
      }
      return n + 1; // die abschliessende Meldung am Ende der Stufe
    }

    test('achttausend Aufnahmen in zwei Minuten ergeben gut tausend Meldungen',
        () {
      // 15 ms je Foto ist optimistisch schnell; je schneller die Stufe
      // läuft, desto mehr spart die Drosselung.
      final zeiten = [for (var i = 1; i <= 8000; i++) i * 15];
      expect(meldungen(zeiten, LibraryState.meldeabstand), lessThan(1300));
      expect(meldungen(zeiten, Duration.zero), 8001,
          reason: 'ohne Drosselung eine je Aufnahme');
    });

    test('eine langsame Stufe wird gar nicht gedrosselt', () {
      // Bildbeschreibung: ein paar Sekunden je Foto. Dort liegt zwischen
      // zwei Aufnahmen ohnehin mehr als der Abstand – jede meldet.
      final zeiten = [for (var i = 1; i <= 20; i++) i * 3000];
      expect(meldungen(zeiten, LibraryState.meldeabstand), 21);
    });

    test('der letzte Stand kommt immer an', () {
      // Der Fall, der ohne die abschliessende Meldung hängenbliebe: Die
      // Stufe endet kurz nach der letzten gedrosselten Meldung.
      // Fünf Aufnahmen in fünf Millisekunden: keine einzige erreicht den
      // Abstand. Ohne die abschliessende Meldung erführe niemand davon.
      final zeiten = [1, 2, 3, 4, 5];
      expect(meldungen(zeiten, LibraryState.meldeabstand), 1);
    });
  });
}

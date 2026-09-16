/// Wie viele Standbilder ein Video verdient – und an welchen Stellen.
///
/// **Der Anlass.** Seit der 6. Vergleichsauflage werden Videos überhaupt
/// ausgewertet: 428 von 429 haben eine Einbettung für die Suche, 428
/// Schlagwörter, 182 ein erkanntes Gesicht. Alles davon stammt aus
/// **einem einzigen** Standbild, das seit dem Import auf der Platte liegt.
///
/// Bei einem Live-Photo-Fetzen von zwei Sekunden ist dieses eine Bild das
/// ganze Video. Bei neun Minuten – so lang ist das längste in der echten
/// Bibliothek – ist es eine Stichprobe von 0,2 Promille. Wer den Hund im
/// Video sucht, findet ihn nur, wenn er zufällig in der ersten Sekunde
/// ins Bild lief.
///
/// ```
/// 429 Videos, 186 Minuten
///   unter 10 s     208   ein Bild reicht
///   ab 10 s        219   ein Bild reicht nicht
///   ab 1 min        54   laengstes: 9 min
/// ```
library;

/// Ab hier lohnt sich ein zweiter Blick. Darunter liegt das vorhandene
/// Standbild (rund eine halbe Sekunde nach dem Start) so nah an allem
/// anderen, dass weitere nichts Neues zeigen.
const videoZweitblickAb = Duration(seconds: 10);

/// Mehr als das wird nie geholt. Nicht aus Sparsamkeit, sondern weil der
/// Nutzen flach wird: Was ein Video zeigt, wechselt selten öfter.
const videoStandbilderHoechstens = 5;

/// Die Stellen in der Laufzeit (0 bis 1), an denen zusätzlich gegriffen
/// wird – leer, wenn das eine vorhandene Standbild genügt.
///
/// **Warum nicht gleichmässig von 0 bis 1.** Der allererste Frame ist bei
/// vielen Videos schwarz, der allerletzte oft eine Bewegungsunschärfe vom
/// Absetzen der Kamera. Die Stellen liegen deshalb bei i/(n+1) – bei drei
/// Bildern also bei einem, zwei und drei Vierteln.
///
/// Das vorhandene Standbild von rund einer halben Sekunde bleibt dabei;
/// die hier gelieferten kommen hinzu, sie ersetzen es nicht.
List<double> videostandbildstellen(double? dauerSekunden) {
  if (dauerSekunden == null || dauerSekunden <= 0) return const [];
  if (dauerSekunden < videoZweitblickAb.inSeconds) return const [];

  // Etwa alle zwanzig Sekunden ein Bild, gedeckelt. Zwei ist das Minimum,
  // sobald ueberhaupt gegriffen wird: Ein einzelnes weiteres Bild waere
  // eine zweite Stichprobe, keine Abdeckung.
  final gewuenscht = (dauerSekunden / 20).round().clamp(2, videoStandbilderHoechstens);
  return [
    for (var i = 1; i <= gewuenscht; i++) i / (gewuenscht + 1),
  ];
}

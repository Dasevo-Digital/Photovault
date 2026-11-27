/// Warum ein Zusammenfügen (#498) scheiterte – als Aufzählung, damit erst
/// die Oberfläche einen Satz daraus macht (dasselbe Muster wie
/// `RestaurierungsGrund`).
library;

/// Der Grund, aus dem kein Bild entstand.
enum Fuegegrund {
  /// Zu wenige oder zu viele Fotos für die gewählte Art.
  anzahl,

  /// Die Fotos einer Belichtungsreihe haben nicht dasselbe Seitenverhältnis
  /// – etwa eines hoch, eines quer.
  groessenUngleich,

  /// Die Fotos eines Panoramas überlappen nicht genug: Es fand sich kein
  /// Paar mit genügend übereinstimmenden Merkmalen.
  keineUeberlappung,

  /// Die Lage der Fotos zueinander liess sich nicht schlüssig bestimmen
  /// (etwa eine Drehung, die in sich nicht aufgeht).
  nichtAusrichtbar,

  /// Eine Quelle liess sich nicht lesen.
  unlesbar,
}

/// Ein Zusammenfügen ist an [grund] gescheitert. [quelle] nennt, wo es
/// darauf ankommt, die Stelle der betroffenen Quelle in der Eingabe.
class Zusammenfuegefehler implements Exception {
  const Zusammenfuegefehler(this.grund, {this.quelle});

  final Fuegegrund grund;
  final int? quelle;

  @override
  String toString() =>
      'Zusammenfuegefehler(${grund.name}${quelle == null ? '' : ', $quelle'})';
}

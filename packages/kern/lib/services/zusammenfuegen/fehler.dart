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
  /// (etwa eine Drehung, die in sich nicht aufgeht, oder eine
  /// Belichtungsreihe, die auch ausgerichtet nicht übereinander passt).
  nichtAusrichtbar,

  /// Eine Quelle liess sich nicht lesen.
  unlesbar,

  /// Eine Quelle ist so gross, dass sie sich auch verkleinert gelesen nicht
  /// sicher im Speicher halten liesse (siehe `dekodiereBild`).
  zuGross,

  /// Die Fotos sind zu klein, um sie verlässlich aneinander auszurichten.
  zuKlein,

  /// Die Fotos eines Panoramas zeigen fast denselben Ausschnitt – zwischen
  /// den Aufnahmen wurde die Kamera nicht geschwenkt.
  keinSchwenk,

  /// Eine Quelle wurde während des Zusammenfügens gesperrt. Das Ergebnis
  /// läge sonst als Klartext neben einem gesperrten Foto.
  quelleGesperrt,

  /// Eine Quelle wurde während des Zusammenfügens gelöscht oder in den
  /// Papierkorb gelegt.
  quelleWeg,

  /// Genau dieses Ergebnis gibt es schon, aber im gesperrten Ordner.
  ergebnisGesperrt,

  /// Das fertige Bild liess sich nicht in die Bibliothek bringen (Import
  /// oder Hochladen); [Zusammenfuegefehler.ursache] sagt, woran.
  einlesen,

  /// Verbunden: Der Server hat das Bild angenommen, die Kopie hier kennt
  /// es aber noch nicht. Ein zweiter Lauf findet und ordnet es ein.
  nichtAngekommen,

  /// Die Bibliothek ist mit einem Server verbunden, die Verbindung aber
  /// gerade nicht da.
  nichtVerbunden,

  /// Die Rechnung endete ohne Ergebnis – meist, weil der Speicher nicht
  /// reichte.
  ohneErgebnis,

  /// Beim Rechnen ging etwas Unerwartetes schief;
  /// [Zusammenfuegefehler.ursache] trägt den Text.
  rechenfehler,
}

/// Ein Zusammenfügen ist an [grund] gescheitert. [quelle] nennt, wo es
/// darauf ankommt, die Stelle der betroffenen Quelle in der Eingabe;
/// [ursache] bei [Fuegegrund.einlesen] und [Fuegegrund.rechenfehler], was
/// dahinter steckt.
class Zusammenfuegefehler implements Exception {
  const Zusammenfuegefehler(this.grund, {this.quelle, this.ursache});

  final Fuegegrund grund;
  final int? quelle;
  final Object? ursache;

  @override
  String toString() =>
      'Zusammenfuegefehler(${grund.name}'
      '${quelle == null ? '' : ', $quelle'}'
      '${ursache == null ? '' : ', $ursache'})';
}

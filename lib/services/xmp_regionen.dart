/// Ein benanntes Gesicht, wie es zwischen Programmen ausgetauscht wird.
///
/// **Warum es das braucht.** In dieser Bibliothek stehen 17.867 erkannte
/// Gesichter, 39 davon mit Namen – die teuerste Handarbeit, die darin steckt.
/// Sie konnte das Programm bis hierher nicht verlassen und auch nicht
/// hineinkommen: `xmp_writer.dart` schrieb keine Regionen, und
/// `xmp_reader.dart` begründete ihr Fehlen damit, dass es „nichts
/// Verlässliches zum Zurücklesen" gebe. Ein Zustand, der sich selbst erhält.
///
/// Das Format ist MWG-RS (Metadata Working Group, Regions) – das, was
/// Lightroom, digiKam und PhotoPrism schreiben und lesen.
///
/// Die Masse sind Anteile der Bildkante mit Ursprung **oben links**, genau
/// wie in der Tabelle `Faces`. MWG selbst legt den Bezugspunkt in die
/// **Mitte** der Region; umgerechnet wird an der Schnittstelle (siehe
/// [mitteX]/[ausMitte]) und nirgends sonst. Diese eine Verwechslung ist der
/// häufigste Fehler beim Lesen fremder Regionen, und sie fällt nicht auf:
/// Der Kasten sitzt dann um eine halbe Gesichtsbreite verschoben, was bei
/// einem Gruppenbild noch plausibel aussieht.
library;

class Gesichtsregion {
  final String name;

  /// Oben links plus Masse, als Anteil der Bildkante (0..1).
  final double links, oben, breite, hoehe;

  const Gesichtsregion({
    required this.name,
    required this.links,
    required this.oben,
    required this.breite,
    required this.hoehe,
  });

  /// Der Mittelpunkt, den MWG als `stArea:x`/`stArea:y` erwartet.
  double get mitteX => links + breite / 2;
  double get mitteY => oben + hoehe / 2;

  /// Der umgekehrte Weg: aus MWGs Mittelpunkt die linke obere Ecke.
  ///
  /// Beschneidet auf 0..1. Ein Gesicht am Bildrand hat in fremden Dateien
  /// durchaus eine Region, die über die Kante hinausragt; ein negativer
  /// Anteil wäre in `Faces` jedoch ein Wert, mit dem keine Anzeige rechnet.
  factory Gesichtsregion.ausMitte({
    required String name,
    required double mitteX,
    required double mitteY,
    required double breite,
    required double hoehe,
  }) {
    final b = breite.clamp(0.0, 1.0);
    final h = hoehe.clamp(0.0, 1.0);
    return Gesichtsregion(
      name: name,
      links: (mitteX - b / 2).clamp(0.0, 1.0),
      oben: (mitteY - h / 2).clamp(0.0, 1.0),
      breite: b,
      hoehe: h,
    );
  }

  double get rechts => links + breite;
  double get unten => oben + hoehe;

  /// Überdeckungsgrad zweier Rechtecke (Schnitt durch Vereinigung).
  ///
  /// Gebraucht, um eine eingelesene Region dem Gesicht zuzuordnen, das die
  /// eigene Erkennung an derselben Stelle gefunden hat. Zwei Programme
  /// zeichnen denselben Kopf nie pixelgleich ein – über die Fläche
  /// verglichen bleibt die Zuordnung trotzdem eindeutig, solange die Köpfe
  /// nicht ineinander stehen.
  static double ueberdeckung(
    ({double links, double oben, double breite, double hoehe}) a,
    ({double links, double oben, double breite, double hoehe}) b,
  ) {
    final links = a.links > b.links ? a.links : b.links;
    final oben = a.oben > b.oben ? a.oben : b.oben;
    final rechts = (a.links + a.breite) < (b.links + b.breite)
        ? (a.links + a.breite)
        : (b.links + b.breite);
    final unten = (a.oben + a.hoehe) < (b.oben + b.hoehe)
        ? (a.oben + a.hoehe)
        : (b.oben + b.hoehe);
    if (rechts <= links || unten <= oben) return 0;
    final schnitt = (rechts - links) * (unten - oben);
    final vereinigung = a.breite * a.hoehe + b.breite * b.hoehe - schnitt;
    return vereinigung <= 0 ? 0 : schnitt / vereinigung;
  }

  /// Ab welcher Überdeckung zwei Kästen als dasselbe Gesicht gelten.
  ///
  /// 0,3 und nicht 0,5: Lightroom zeichnet Gesichtsregionen deutlich weiter
  /// als YuNet (Haare und Kinn gehören dort dazu), zwei Kästen um denselben
  /// Kopf kommen dadurch leicht nur auf ein Drittel gemeinsame Fläche. Zu
  /// hoch angesetzt fände der Abgleich gar nichts, und das wäre der stille
  /// Fehlschlag – zu niedrig fände er den Nachbarn, und das fällt beim
  /// Durchsehen auf.
  static const double mindestUeberdeckung = 0.3;
}

/// Ein Kasten, wie ihn die Gesichtstabelle führt.
typedef Kasten = ({double links, double oben, double breite, double hoehe});

/// Ordnet eingelesene Regionen den vorhandenen Gesichtern zu.
///
/// Gibt Paare aus dem Index in [kaesten] und der Region zurück. Jeder Kasten
/// wird höchstens einmal vergeben, und zwar an die Region, mit der er sich am
/// stärksten überdeckt – zuerst das stärkste Paar, dann das nächststärkste.
/// Diese Reihenfolge ist der Punkt: Bei zwei nebeneinander stehenden Köpfen
/// würde eine Zuordnung „der Reihe nach" die erste Region dem falschen Kopf
/// geben, wenn sie zufällig zuerst geprüft wird.
///
/// Was unter [Gesichtsregion.mindestUeberdeckung] liegt, bleibt unvergeben.
/// Lieber eine Region, für die kein Gesicht gefunden wurde, als ein Name am
/// falschen Kopf: Das eine sieht man beim Durchsehen, das andere nicht.
///
/// Reine Funktion ohne Datenbank – deshalb Indizes statt Datensätze.
List<(int, Gesichtsregion)> regionenZuordnen(
  List<Gesichtsregion> regionen,
  List<Kasten> kaesten,
) {
  final kandidaten = <(double, int, int)>[];
  for (var r = 0; r < regionen.length; r++) {
    final region = regionen[r];
    final alsKasten = (
      links: region.links,
      oben: region.oben,
      breite: region.breite,
      hoehe: region.hoehe,
    );
    for (var k = 0; k < kaesten.length; k++) {
      final grad = Gesichtsregion.ueberdeckung(alsKasten, kaesten[k]);
      if (grad >= Gesichtsregion.mindestUeberdeckung) {
        kandidaten.add((grad, r, k));
      }
    }
  }
  // Absteigend nach Überdeckung; bei Gleichstand nach den Indizes, damit
  // dieselbe Eingabe immer dieselbe Zuordnung ergibt.
  kandidaten.sort((a, b) {
    final nachGrad = b.$1.compareTo(a.$1);
    if (nachGrad != 0) return nachGrad;
    final nachRegion = a.$2.compareTo(b.$2);
    return nachRegion != 0 ? nachRegion : a.$3.compareTo(b.$3);
  });

  final vergebeneRegionen = <int>{};
  final vergebeneKaesten = <int>{};
  final ergebnis = <(int, Gesichtsregion)>[];
  for (final (_, r, k) in kandidaten) {
    if (vergebeneRegionen.contains(r) || vergebeneKaesten.contains(k)) continue;
    vergebeneRegionen.add(r);
    vergebeneKaesten.add(k);
    ergebnis.add((k, regionen[r]));
  }
  return ergebnis;
}

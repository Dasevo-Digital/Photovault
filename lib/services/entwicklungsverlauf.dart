/// Was zwischen zwei Entwicklungsständen anders ist.
///
/// **Der Anlass.** Der Verlauf im Entwickeln-Bildschirm zeigte eine Liste
/// von Zeitpunkten – „05.03.2026, 14:30" und darunter noch einer. Was an
/// jedem davon getan wurde, stand nirgends; man musste einen Eintrag
/// laden und das Bild ansehen, um es herauszufinden. Und die Liste
/// entstand erst beim **Speichern**: Alles, was man während einer
/// Sitzung ausprobierte, war bis dahin verloren, sobald man es einmal
/// übergangen hatte.
///
/// Beides beantwortet dieselbe Rechnung: Der Unterschied zweier Stände
/// sagt, welche Werkzeuge angefasst wurden. Für die Sitzung wird er
/// zwischen zwei aufeinanderfolgenden Schritten gebildet, für die
/// gespeicherte Reihe zwischen zwei aufeinanderfolgenden Einträgen.
///
/// Ohne Oberfläche: Wie die Werkzeuge heissen, weiss erst die
/// Oberfläche – dieselbe Trennung wie beim Modellkatalog.
library;

import 'native_image_converter.dart';

/// Ein Werkzeug des Entwickeln-Bildschirms.
enum Entwicklungswerkzeug {
  belichtung,
  weissabgleich,
  temperatur,
  tint,
  kontrast,
  lichter,
  schatten,
  schaerfe,
  rauschunterdrueckung,
  klarheit,
  vignettierung,
  tonwertkurve,
  farbmischer,
  farbtabelle,
  objektivkorrektur,
}

/// Ab welchem Unterschied ein Regler als angefasst gilt.
///
/// Nicht auf exakte Gleichheit prüfen: Ein Stand, der durch die Datenbank
/// gegangen ist, trägt gerundete Zahlen, und ein Verlauf, der bei jedem
/// Eintrag „Belichtung" nennt, weil sich die zwölfte Nachkommastelle
/// unterscheidet, nennt gar nichts.
const double _schwelle = 1e-4;

bool _andersD(double a, double b) => (a - b).abs() > _schwelle;

/// Welche Werkzeuge zwischen [vorher] und [nachher] angefasst wurden.
///
/// Die Reihenfolge ist die der Aufzählung – damit dieselbe Änderung
/// zweimal dieselbe Auskunft ergibt und nicht einmal „Kontrast,
/// Belichtung" und einmal andersherum.
List<Entwicklungswerkzeug> geaenderteWerkzeuge(
  DevelopAdjustments vorher,
  DevelopAdjustments nachher,
) {
  final werkzeuge = <Entwicklungswerkzeug>[];

  void pruefe(Entwicklungswerkzeug w, bool anders) {
    if (anders) werkzeuge.add(w);
  }

  pruefe(Entwicklungswerkzeug.belichtung,
      _andersD(vorher.exposure, nachher.exposure));

  // Der Weissabgleich ist ein Schalter UND zwei Regler. `null` heisst
  // „der Kamera überlassen"; von dort auf einen Wert zu wechseln ist ein
  // anderer Vorgang als den Wert zu verschieben, und beides sollte nicht
  // denselben Namen tragen.
  final automatikVorher = vorher.temperature == null;
  final automatikNachher = nachher.temperature == null;
  pruefe(Entwicklungswerkzeug.weissabgleich, automatikVorher != automatikNachher);
  if (!automatikVorher && !automatikNachher) {
    pruefe(Entwicklungswerkzeug.temperatur,
        _andersD(vorher.temperature!, nachher.temperature!));
    pruefe(Entwicklungswerkzeug.tint,
        _andersD(vorher.tint ?? 0, nachher.tint ?? 0));
  }

  pruefe(Entwicklungswerkzeug.kontrast,
      _andersD(vorher.contrast, nachher.contrast));
  pruefe(Entwicklungswerkzeug.lichter,
      _andersD(vorher.highlights, nachher.highlights));
  pruefe(Entwicklungswerkzeug.schatten,
      _andersD(vorher.shadows, nachher.shadows));
  pruefe(Entwicklungswerkzeug.schaerfe,
      _andersD(vorher.sharpness, nachher.sharpness));
  pruefe(Entwicklungswerkzeug.rauschunterdrueckung,
      _andersD(vorher.noiseReduction, nachher.noiseReduction));
  pruefe(Entwicklungswerkzeug.klarheit,
      _andersD(vorher.clarity, nachher.clarity));
  pruefe(Entwicklungswerkzeug.vignettierung,
      _andersD(vorher.vignette, nachher.vignette));
  pruefe(Entwicklungswerkzeug.tonwertkurve,
      vorher.toneCurve != nachher.toneCurve);
  pruefe(Entwicklungswerkzeug.farbmischer,
      vorher.colorMixer != nachher.colorMixer);
  // Die Tabelle selbst wird nicht Wert für Wert verglichen – sie hat bis
  // zu 64³ Einträge. Ob eine da ist, wie sie heisst und wie stark sie
  // wirkt, sagt dasselbe.
  pruefe(
      Entwicklungswerkzeug.farbtabelle,
      (vorher.lut == null) != (nachher.lut == null) ||
          vorher.lut?.titel != nachher.lut?.titel ||
          _andersD(vorher.lutStrength, nachher.lutStrength));
  pruefe(Entwicklungswerkzeug.objektivkorrektur,
      vorher.lensCorrectionEnabled != nachher.lensCorrectionEnabled);

  return werkzeuge;
}

/// Ob sich überhaupt etwas geändert hat.
bool istAnders(DevelopAdjustments a, DevelopAdjustments b) =>
    geaenderteWerkzeuge(a, b).isNotEmpty;

/// Ein Schritt in der Sitzung: ein Stand und wann er entstand.
///
/// **Warum die Sitzung mitgeschrieben wird.** Die gespeicherte Reihe
/// entsteht erst beim Speichern – wer eine halbe Stunde probiert und
/// dabei zweimal einen Stand hatte, den er lieber behalten hätte, kam
/// nicht zurück. Ein Schritt entsteht, sobald eine Änderung sich gesetzt
/// hat, nicht bei jedem Punkt Reglerweg.
class Verlaufsschritt {
  const Verlaufsschritt({required this.wann, required this.stand});
  final DateTime wann;
  final DevelopAdjustments stand;
}

/// Wie viele Sitzungsschritte höchstens aufgehoben werden.
///
/// Genug für eine lange Sitzung, wenig genug, dass die Liste eine Liste
/// bleibt. Jeder Schritt hält nur Zahlen und zwei Kurven fest – ein Bild
/// wird nicht mitgeschrieben, sonst wären es Hunderte Megabyte.
const int maxSitzungsschritte = 60;

/// Nimmt [neu] in die Reihe auf – oder nicht.
///
/// Zurück kommt die neue Reihe. Nichts passiert, wenn der Stand dem
/// letzten gleicht: Ein Regler, der bewegt und wieder zurückgelegt wird,
/// ist kein Schritt.
List<Verlaufsschritt> mitSchritt(
  List<Verlaufsschritt> bisher,
  DevelopAdjustments neu, {
  DateTime? wann,
}) {
  if (bisher.isNotEmpty && !istAnders(bisher.last.stand, neu)) return bisher;
  final reihe = [
    ...bisher,
    Verlaufsschritt(wann: wann ?? DateTime.now(), stand: neu),
  ];
  if (reihe.length <= maxSitzungsschritte) return reihe;
  // Vorn abschneiden – aber der erste Eintrag bleibt: Er ist der Stand,
  // mit dem das Bild geöffnet wurde, und damit der einzige Weg ganz
  // zurück.
  return [reihe.first, ...reihe.skip(reihe.length - maxSitzungsschritte + 1)];
}

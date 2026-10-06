/// Die Geometrie des Lebensbaums – ohne Oberfläche.
///
/// Der Lebensbaum ist die gemalte Form der alten Stammbaumtafeln: unten
/// ein Stamm, aus dem die Generationen als Äste nach oben wachsen. Er ist
/// eine **Wahl neben** dem Zierbaum, kein Ersatz. Der Zierbaum zeigt die
/// nahe Verwandtschaft samt Angeheirateten um eine Person herum; der
/// Lebensbaum zeigt eine Linie über mehrere Generationen – und nur eine
/// Richtung auf einmal, weil ein Baum nur nach oben wachsen kann:
///
/// - **Vorfahren:** die Person am Stamm, darüber Eltern, Grosseltern und
///   so fort. Jede Gabel teilt sich in genau zwei Äste, wie im Fächer.
/// - **Nachkommen:** die Person (mit Partner) am Stamm, darüber ihre
///   Kinder, Enkel und so fort.
///
/// Gezeigt wird der Plan nicht selbst: Er ist das Vorbild, nach dem die
/// Personen auf die Schilder einer Bildvorlage verteilt werden (siehe
/// `lebensbaum_vorlage.dart`).
///
/// Ausgelagert aus demselben Grund wie die Fächertafel: Ob sich zwei
/// Schilder um ein paar Punkte überlappen, sieht man am fertigen Bild
/// nicht zuverlässig – man rechnet es nach.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'faechertafel.dart' show elternFuerTafel;
import 'stammbaum.dart';

enum Lebensbaumrichtung {
  vorfahren,
  nachkommen,

  /// Das Paar am Stamm, darüber links die Vorfahren der Person, rechts
  /// die ihres Partners – und in der ersten Reihe die Geschwister beider.
  paar,

  /// Die ganze Familie Generation für Generation, wie im Zierbaum: mit
  /// Geschwistern, Angeheirateten und deren Eltern. Ihr Plan kommt aus
  /// dem Zierbaum, nicht aus [lebensbaumplan].
  familie,
}

/// Breiter als so viel zu eins wird der Baum nicht, solange er dafür
/// in die Höhe wachsen kann (siehe [lebensbaumplan]).
const _hoechstesFormat = 1.7;

/// Die kleinste und grösste Zahl an Generationen über dem Stamm.
///
/// Nach oben begrenzt, weil sich Vorfahren verdoppeln: Sechs Generationen
/// sind 64 Plätze in der obersten Reihe, und der Baum wird breiter als
/// jede Wand. Eine einzige ist das Mindeste, sonst gäbe es keinen Ast.
const lebensbaumMinGenerationen = 1;
const lebensbaumMaxGenerationen = 6;

/// Die Masse in logischen Punkten.
///
/// Als Wertobjekt mit [mal], damit dieselbe Rechnung für den Bildschirm
/// und – dreifach vergrössert – für die Tafel zum Aufhängen gilt.
class Lebensbaummasse {
  final double schildBreite;
  final double schildHoehe;

  /// Zwischen den beiden Schildern eines Paares.
  final double paarAbstand;

  /// Zwischen zwei Nachbarn in derselben Generation.
  final double spalte;

  /// Von Generation zu Generation.
  final double stufenHoehe;

  /// Vom Schild am Stamm bis zum Boden.
  final double stamm;

  /// Links und rechts, für das Laub, das über die äussersten Schilder
  /// hinausragt.
  final double rand;

  /// Über der obersten Generation, für die Krone.
  final double kopf;

  /// Unter dem Boden, für Wurzeln und Spruchband.
  final double fuss;

  /// So schmal wird das Bild nie – sonst fände das Spruchband keinen
  /// Platz.
  final double mindestBreite;

  const Lebensbaummasse({
    this.schildBreite = 150,
    this.schildHoehe = 58,
    this.paarAbstand = 10,
    this.spalte = 22,
    this.stufenHoehe = 150,
    this.stamm = 160,
    this.rand = 130,
    this.kopf = 110,
    this.fuss = 170,
    this.mindestBreite = 760,
  });

  Lebensbaummasse mal(double f) => Lebensbaummasse(
    schildBreite: schildBreite * f,
    schildHoehe: schildHoehe * f,
    paarAbstand: paarAbstand * f,
    spalte: spalte * f,
    stufenHoehe: stufenHoehe * f,
    stamm: stamm * f,
    rand: rand * f,
    kopf: kopf * f,
    fuss: fuss * f,
    mindestBreite: mindestBreite * f,
  );
}

/// Eine Gabel des Baums: eine Person, in den Nachkommen auch ein Paar.
class Lebensknoten {
  /// Eindeutig im Plan, auch wenn eine Person zweimal vorkommt – etwa
  /// Vorfahren, die über zwei Linien abstammen.
  final String schluessel;

  /// Eine Person, oder zwei: Person und Partner nebeneinander.
  final List<String> personen;

  /// 0 am Stamm, 1 die erste Generation darüber.
  final int stufe;

  /// Der Knoten, aus dem dieser wächst. `null` am Stamm.
  final String? vorgaenger;

  /// Wie viele Astspitzen über diesem Knoten liegen, ihn selbst
  /// eingeschlossen, wenn er eine ist. Daraus wird die Dicke des Astes:
  /// Ein Ast, der viel trägt, ist dick – wie im Holz.
  final int spitzen;

  /// Je Person ein Schild.
  final List<Rect> schilder;

  const Lebensknoten({
    required this.schluessel,
    required this.personen,
    required this.stufe,
    required this.vorgaenger,
    required this.spitzen,
    required this.schilder,
  });

  /// Alle Schilder zusammen.
  Rect get rahmen => schilder.reduce((a, b) => a.expandToInclude(b));

  /// Wo der Ast von unten ankommt.
  Offset get ankunft => rahmen.bottomCenter;

  /// Wo die Äste nach oben abgehen.
  Offset get abgang => rahmen.topCenter;
}

class Lebensbaumplan {
  final List<Lebensknoten> knoten;
  final double breite;
  final double hoehe;

  /// Die Höhe des Bodens; der Stamm steht in der Mitte darauf.
  final double boden;

  /// Personen, die im Bild keinen Platz mehr hatten.
  final int verschwiegen;

  /// Wie viele Generationen über dem Stamm wirklich belegt sind.
  final int generationen;

  const Lebensbaumplan({
    required this.knoten,
    required this.breite,
    required this.hoehe,
    required this.boden,
    required this.verschwiegen,
    required this.generationen,
  });

  Lebensknoten get wurzel => knoten.first;

  /// Wo der Stamm auf dem Boden steht.
  Offset get stammFuss => Offset(wurzel.ankunft.dx, boden);

  Lebensknoten? knotenMit(String schluessel) {
    for (final k in knoten) {
      if (k.schluessel == schluessel) return k;
    }
    return null;
  }

  /// Die Person, deren Schild an [stelle] steht.
  String? personBei(Offset stelle) {
    for (final k in knoten) {
      for (var i = 0; i < k.schilder.length; i++) {
        if (k.schilder[i].contains(stelle)) return k.personen[i];
      }
    }
    return null;
  }
}

/// Der Baum als Struktur, bevor er Koordinaten bekommt.
class _Zweig {
  final String schluessel;
  final List<String> personen;
  final int stufe;
  final String? vorgaenger;
  final List<_Zweig> kinder = [];
  double breite = 0; // des ganzen Teilbaums
  double mitte = 0;

  _Zweig(this.schluessel, this.personen, this.stufe, this.vorgaenger);

  int get spitzen =>
      kinder.isEmpty ? 1 : kinder.fold(0, (s, k) => s + k.spitzen);
}

/// Baut den Plan für [wurzel].
///
/// [hoechstensSchilder] begrenzt das Bild: Nachkommen verzweigen nicht
/// regelmässig, und eine grosse Familie über sechs Generationen ergäbe
/// hunderte Schilder. Was darüber hinausgeht, wird gezählt
/// ([Lebensbaumplan.verschwiegen]) und nicht still weggelassen.
Lebensbaumplan lebensbaumplan(
  Verwandtschaftsnetz netz,
  String wurzel,
  int Function(String) ordnung, {
  required Lebensbaumrichtung richtung,
  int generationen = 4,
  Lebensbaummasse masse = const Lebensbaummasse(),
  int hoechstensSchilder = 160,
}) {
  final tiefe = generationen.clamp(
    lebensbaumMinGenerationen,
    lebensbaumMaxGenerationen,
  );
  var schilder = 0;
  var verschwiegen = 0;
  var naechsterSchluessel = 0;

  _Zweig zweig(List<String> personen, int stufe, String? vorgaenger) {
    schilder += personen.length;
    return _Zweig('${naechsterSchluessel++}', personen, stufe, vorgaenger);
  }

  final _Zweig stamm;
  switch (richtung) {
    case Lebensbaumrichtung.vorfahren:
      stamm = zweig([wurzel], 0, null);
      // Breit statt tief: Erst kommt jede Generation ganz, dann die
      // nächste. Reicht der Platz nicht, fehlt so die oberste Reihe und
      // nicht ein ganzer Ast.
      var reihe = [stamm];
      for (var stufe = 1; stufe <= tiefe && reihe.isNotEmpty; stufe++) {
        final naechste = <_Zweig>[];
        for (final z in reihe) {
          for (final elternteil in elternFuerTafel(
            netz,
            z.personen.single,
            ordnung,
          )) {
            if (elternteil == null) continue;
            if (schilder >= hoechstensSchilder) {
              verschwiegen++;
              continue;
            }
            final k = zweig([elternteil], stufe, z.schluessel);
            z.kinder.add(k);
            naechste.add(k);
          }
        }
        reihe = naechste;
      }
    case Lebensbaumrichtung.paar:
      final partner = _partnerFuer(netz, wurzel, ordnung);
      stamm = zweig([wurzel, ?partner], 0, null);
      List<String> geschwister(String id) =>
          {
              for (final e in netz.eltern(id)) ...netz.kinder(e),
            }.where((g) => g != wurzel && g != partner).toList()
            ..sort((a, b) => ordnung(a).compareTo(ordnung(b)));
      _Zweig? neu(String id, int stufe, _Zweig an) {
        if (schilder >= hoechstensSchilder) {
          verschwiegen++;
          return null;
        }
        return zweig([id], stufe, an.schluessel);
      }

      // Aussen die Geschwister, innen die Vorfahren: Die Geschwister der
      // Person links, die des Partners rechts, und die Linien beider
      // treffen sich über dem Stamm.
      final links = [for (final g in geschwister(wurzel)) ?neu(g, 1, stamm)];
      final rechts = [
        if (partner != null)
          for (final g in geschwister(partner)) ?neu(g, 1, stamm),
      ];
      var reihe = <(_Zweig, String)>[];
      final ahnen = <_Zweig>[];
      for (final id in [wurzel, ?partner]) {
        for (final elternteil in elternFuerTafel(netz, id, ordnung)) {
          if (elternteil == null || tiefe < 1) continue;
          final k = neu(elternteil, 2, stamm);
          if (k == null) continue;
          ahnen.add(k);
          reihe.add((k, elternteil));
        }
      }
      stamm.kinder.addAll([...links, ...ahnen, ...rechts]);
      for (var stufe = 3; stufe <= tiefe + 1 && reihe.isNotEmpty; stufe++) {
        final naechste = <(_Zweig, String)>[];
        for (final (z, id) in reihe) {
          for (final elternteil in elternFuerTafel(netz, id, ordnung)) {
            if (elternteil == null) continue;
            final k = neu(elternteil, stufe, z);
            if (k == null) continue;
            z.kinder.add(k);
            naechste.add((k, elternteil));
          }
        }
        reihe = naechste;
      }
    case Lebensbaumrichtung.familie:
      throw ArgumentError('Die Familie kommt aus dem Zierbaum.');
    case Lebensbaumrichtung.nachkommen:
      final gesehen = <String>{wurzel};
      List<String> paar(String id) {
        final partner = _partnerFuer(netz, id, ordnung);
        if (partner == null || !gesehen.add(partner)) return [id];
        return [id, partner];
      }

      stamm = zweig(paar(wurzel), 0, null);
      var reihe = [stamm];
      for (var stufe = 1; stufe <= tiefe && reihe.isNotEmpty; stufe++) {
        final naechste = <_Zweig>[];
        for (final z in reihe) {
          // Die Kinder beider im Paar – ein Kind, das nur beim Partner
          // eingetragen ist, gehört trotzdem an diesen Ast.
          final kinder = {
            for (final p in z.personen) ...netz.kinder(p),
          }.toList()..sort((a, b) => ordnung(a).compareTo(ordnung(b)));
          for (final kind in kinder) {
            // Ein Kreis im Bestand oder ein Kind, das über beide Eltern
            // schon einmal erreicht wurde.
            if (!gesehen.add(kind)) continue;
            if (schilder >= hoechstensSchilder) {
              verschwiegen++;
              continue;
            }
            final k = zweig(paar(kind), stufe, z.schluessel);
            z.kinder.add(k);
            naechste.add(k);
          }
        }
        reihe = naechste;
      }
  }

  // --- Breiten von oben nach unten, Lage von unten nach oben ----------
  double eigeneBreite(_Zweig z) =>
      z.personen.length * masse.schildBreite +
      (z.personen.length - 1) * masse.paarAbstand;

  void miss(_Zweig z) {
    for (final k in z.kinder) {
      miss(k);
    }
    final kinderBreite = z.kinder.isEmpty
        ? 0.0
        : z.kinder.fold<double>(0, (s, k) => s + k.breite) +
              (z.kinder.length - 1) * masse.spalte;
    z.breite = math.max(eigeneBreite(z), kinderBreite);
  }

  void lege(_Zweig z, double links) {
    z.mitte = links + z.breite / 2;
    final kinderBreite = z.kinder.isEmpty
        ? 0.0
        : z.kinder.fold<double>(0, (s, k) => s + k.breite) +
              (z.kinder.length - 1) * masse.spalte;
    var x = links + (z.breite - kinderBreite) / 2;
    for (final k in z.kinder) {
      lege(k, x);
      x += k.breite + masse.spalte;
    }
  }

  miss(stamm);
  final inhaltBreite = stamm.breite + 2 * masse.rand;
  final breite = math.max(inhaltBreite, masse.mindestBreite);
  lege(stamm, (breite - stamm.breite) / 2);

  var hoechste = 0;
  void stufen(_Zweig z) {
    hoechste = math.max(hoechste, z.stufe);
    z.kinder.forEach(stufen);
  }

  stufen(stamm);

  // **Ein breiter Baum wächst auch höher.** Mit festem Abstand wird eine
  // volle Ahnentafel über vier Generationen dreimal so breit wie hoch,
  // und ihre Äste laufen fast waagerecht – das sieht nach einem Gestell
  // aus, nicht nach einem Baum. Die Generationen rücken deshalb
  // auseinander, bis das Bild nicht breiter ist als [_hoechstesFormat]
  // zu eins, höchstens aber auf das 2,2-Fache des Abstands.
  final ohneStufen = masse.kopf + masse.schildHoehe + masse.stamm + masse.fuss;
  final stufenHoehe = hoechste == 0
      ? masse.stufenHoehe
      : ((breite / _hoechstesFormat - ohneStufen) / hoechste).clamp(
          masse.stufenHoehe,
          masse.stufenHoehe * 2.2,
        );

  // Die Mitte eines Schildes der Generation [stufe], von oben gezählt.
  double mitteY(int stufe) =>
      masse.kopf + masse.schildHoehe / 2 + (hoechste - stufe) * stufenHoehe;

  final knoten = <Lebensknoten>[];
  void sammle(_Zweig z) {
    // **Wer abstammt, steht innen.** Über dem Stamm steht ein Paar aus
    // Kind und Partner; der Partner ist angeheiratet und gehört nach
    // aussen, das Kind zum Stamm hin. Links vom Stamm also Partner, Kind –
    // rechts Kind, Partner.
    final personen =
        z.stufe > 0 && z.personen.length == 2 && z.mitte < stamm.mitte
        ? z.personen.reversed.toList()
        : z.personen;
    final y = mitteY(z.stufe);
    final gesamt = eigeneBreite(z);
    var x = z.mitte - gesamt / 2;
    final rechtecke = <Rect>[];
    for (var i = 0; i < z.personen.length; i++) {
      rechtecke.add(
        Rect.fromLTWH(
          x,
          y - masse.schildHoehe / 2,
          masse.schildBreite,
          masse.schildHoehe,
        ),
      );
      x += masse.schildBreite + masse.paarAbstand;
    }
    knoten.add(
      Lebensknoten(
        schluessel: z.schluessel,
        personen: personen,
        stufe: z.stufe,
        vorgaenger: z.vorgaenger,
        spitzen: z.spitzen,
        schilder: rechtecke,
      ),
    );
    z.kinder.forEach(sammle);
  }

  sammle(stamm);

  final boden = mitteY(0) + masse.schildHoehe / 2 + masse.stamm;
  return Lebensbaumplan(
    knoten: knoten,
    breite: breite,
    hoehe: boden + masse.fuss,
    boden: boden,
    verschwiegen: verschwiegen,
    generationen: hoechste,
  );
}

/// Der Partner, der neben [id] am Ast steht.
///
/// Bei mehreren der, mit dem die meisten Kinder eingetragen sind – auf
/// diesen Ast gehören sie. Bei Gleichstand entscheidet die Ordnung, damit
/// dasselbe Bild zweimal gleich aussieht.
String? _partnerFuer(
  Verwandtschaftsnetz netz,
  String id,
  int Function(String) ordnung,
) {
  final partner = netz.partner(id).toList()
    ..sort((a, b) => ordnung(a).compareTo(ordnung(b)));
  if (partner.isEmpty) return null;
  int gemeinsam(String p) =>
      netz.kinder(id).where((k) => netz.eltern(k).contains(p)).length;
  var bester = partner.first;
  for (final p in partner.skip(1)) {
    if (gemeinsam(p) > gemeinsam(bester)) bester = p;
  }
  return bester;
}

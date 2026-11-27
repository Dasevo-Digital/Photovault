/// Panoramen aus einem Schwenk (#498): Merkmale, Zuordnung, RANSAC,
/// Drehungen der Kamera, Zylinderprojektion, Belichtungsausgleich,
/// weicher Übergang und Zuschnitt – in reinem Dart.
///
/// **Ablauf.** Registriert wird auf verkleinerten Fassungen (gut 0,6 MP je
/// Bild): Merkmale je Bild ([findeMerkmale]), Zuordnung jedes Paars
/// ([ordneZu]), RANSAC über eine Homographie ([ransacHomographie]). Die
/// Reihenfolge der Fotos spielt keine Rolle – wer Nachbar ist, sagen die
/// Paare mit genügend passenden Merkmalen (mehr als 8 + 0,3 × Zuordnungen,
/// nach Brown und Lowe). Aus den passenden Paaren und der Brennweite folgt
/// je Bildpaar eine Drehung der Kamera (Horn), entlang des stärksten
/// Spannbaums zusammengesetzt und danach gemeinsam ausgeglichen. Die
/// Brennweite kommt aus den Aufnahmeangaben (35-mm-Äquivalent), sonst wird
/// sie so gewählt, dass die Drehungen die Paare am genauesten erklären.
/// Danach wird das Panorama aufgerichtet (die x-Achsen der Kamera liegen
/// bei einem Schwenk in einer Ebene; deren Normale ist „oben"),
/// zylindrisch abgebildet, je Bild und Farbkanal in der Verstärkung an die
/// Nachbarn angeglichen und mit linear auslaufenden Gewichten
/// überblendet. Zusammengesetzt wird in voller Auflösung, eine Quelle nach
/// der anderen.
///
/// **Grenzen.** Nur Drehungen: Wer zwischen den Aufnahmen einen Schritt
/// zur Seite macht, bekommt bei nahen Gegenständen Doppelkanten
/// (Parallaxe). Was sich bewegt, kann im Überlappungsbereich halb
/// durchsichtig erscheinen – es gibt weder Nahtsuche noch Mehrband-
/// Überblendung. Der Zylinder steht senkrecht: Ein Schwenk nach oben
/// (Hochhaus) wird nur bis etwa 68° Höhe abgebildet. Ein voller Kreis
/// (360°) wird nicht geschlossen.
///
/// **Grösse und Speicher.** Das Ergebnis hat höchstens
/// [panoramaHoechstensPixel] Bildpunkte (50 MP) und höchstens
/// [panoramaHoechstensKante] Punkte an einer Seite; ein grösseres
/// Panorama wird als Ganzes verkleinert. Im Speicher liegen dabei das
/// Ergebnis (3 Byte je Punkt), die Summe der Gewichte (4 Byte je Punkt)
/// und eine Quelle, bei 50 MP also gut 0,4 GB.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fehler.dart';
import 'matrizen.dart';
import 'merkmale.dart';
import 'raster.dart';

/// So viele Aufnahmen nimmt ein Panorama.
const panoramaMindestens = 2;
const panoramaHoechstens = 12;

/// So gross wird ein Panorama höchstens – siehe oben.
const panoramaHoechstensPixel = 50 * 1000 * 1000;
const panoramaHoechstensKante = 30000;

/// Auf so viele Bildpunkte wird jede Quelle für die Registrierung
/// verkleinert.
const _registrierPixel = 600 * 1000;

/// Was beim Zusammensetzen gewählt werden kann.
class PanoramaOptionen {
  const PanoramaOptionen({
    this.zuschneiden = true,
    this.belichtungAusgleichen = true,
    this.hoechstensPixel = panoramaHoechstensPixel,
    this.hoechstensKante = panoramaHoechstensKante,
  });

  /// Auf das grösste Rechteck zuschneiden, in dem jeder Punkt aus einer
  /// Aufnahme kommt. Ohne bleiben die Ränder schwarz.
  final bool zuschneiden;

  /// Die Helligkeit der Aufnahmen aneinander angleichen (Verstärkung je
  /// Bild und Kanal). Abschalten nur zum Vergleich.
  final bool belichtungAusgleichen;
  final int hoechstensPixel;
  final int hoechstensKante;
}

/// Das Panorama, welche Quellen darin stecken (aufsteigend), die
/// Brennweite, mit der es gerechnet wurde (bezogen auf die lange Seite),
/// und je verwendeter Quelle der Winkel ihrer Bildmitte auf dem Zylinder
/// (Bogenmass, nach dem Aufrichten).
class PanoramaErgebnis {
  const PanoramaErgebnis(
    this.bild,
    this.verwendet,
    this.brennweite,
    this.mitten,
  );

  final Farbbild bild;
  final List<int> verwendet;
  final double brennweite;
  final Map<int, double> mitten;
}

/// Eine Quelle während der Registrierung.
class _Quelle {
  _Quelle(this.breite, this.hoehe, this.klein, this.merkmale);

  /// Grösse der vollen Fassung.
  final int breite;
  final int hoehe;

  /// Die verkleinerte Fassung für Registrierung und Ausgleich.
  final Farbbild klein;
  final Merkmale merkmale;

  int get langeSeite => math.max(breite, hoehe);
  int get kleinLang => math.max(klein.breite, klein.hoehe);
  double get kleinMx => (klein.breite - 1) / 2;
  double get kleinMy => (klein.hoehe - 1) / 2;

  /// Brennweite bezogen auf die lange Seite.
  double phi = 1;

  /// Welt aus Kamera.
  Float64List drehung = einheit3();

  double get fKlein => phi * kleinLang;
}

/// Ein Bildpaar mit passenden Merkmalen: Lagen in [a] und [b] (je x, y,
/// bezogen auf die Bildmitte der kleinen Fassung).
class _Kante {
  _Kante(this.a, this.b, this.pa, this.pb, this.zuordnungen);

  final int a;
  final int b;
  final Float64List pa;
  final Float64List pb;
  final int zuordnungen;

  int get passend => pa.length ~/ 2;
}

/// Setzt [anzahl] Aufnahmen, die [lade] liefert, zu einem Panorama
/// zusammen. [brennweiten35] trägt je Quelle die Brennweite als
/// 35-mm-Äquivalent, wo sie bekannt ist. [lade] wird je Quelle zweimal
/// gerufen. [fortschritt] meldet erledigte Schritte von 2 × [anzahl] + 2.
///
/// Wirft [Zusammenfuegefehler] mit [Fuegegrund.keineUeberlappung], wenn
/// sich keine zwei Fotos verbinden lassen. Lassen sich nur einige
/// verbinden, entsteht das Panorama aus der grössten zusammenhängenden
/// Gruppe; [PanoramaErgebnis.verwendet] sagt, welche das sind.
PanoramaErgebnis fuegePanorama(
  int anzahl,
  Farbbild Function(int i) lade, {
  List<double?>? brennweiten35,
  PanoramaOptionen optionen = const PanoramaOptionen(),
  void Function(int erledigt, int gesamt)? fortschritt,
}) {
  if (anzahl < panoramaMindestens || anzahl > panoramaHoechstens) {
    throw const Zusammenfuegefehler(Fuegegrund.anzahl);
  }
  final gesamt = 2 * anzahl + 2;
  var erledigt = 0;
  void schritt() => fortschritt?.call(++erledigt, gesamt);

  // Erster Durchgang: verkleinern und Merkmale suchen.
  final quellen = <_Quelle>[];
  for (var i = 0; i < anzahl; i++) {
    final b = lade(i);
    final klein = verkleinereAuf(b, _registrierPixel);
    quellen.add(
      _Quelle(b.breite, b.hoehe, klein, findeMerkmale(Graubild.aus(klein))),
    );
    schritt();
  }

  // Jedes Paar zuordnen und mit RANSAC prüfen.
  final kanten = <_Kante>[];
  for (var i = 0; i < anzahl; i++) {
    for (var j = i + 1; j < anzahl; j++) {
      final k = _verbinde(quellen, i, j);
      if (k != null) kanten.add(k);
    }
  }
  schritt();

  // Die grösste zusammenhängende Gruppe.
  final gruppe = _groessteGruppe(anzahl, kanten);
  if (gruppe.length < 2) {
    throw const Zusammenfuegefehler(Fuegegrund.keineUeberlappung);
  }
  final inGruppe = gruppe.toSet();
  final eigene = [
    for (final k in kanten)
      if (inGruppe.contains(k.a)) k,
  ];

  // Brennweite: aus den Aufnahmeangaben, sonst geschätzt.
  final bekannt = <double>[];
  for (final i in gruppe) {
    final f35 = brennweiten35 != null && i < brennweiten35.length
        ? brennweiten35[i]
        : null;
    if (f35 != null && f35 > 0) {
      final q = quellen[i];
      final diagonale = math.sqrt(q.breite * q.breite + q.hoehe * q.hoehe);
      bekannt.add(f35 / 43.27 * diagonale / q.langeSeite);
    }
  }
  final phi = bekannt.isNotEmpty
      ? (bekannt..sort())[bekannt.length ~/ 2]
      : _schaetzeBrennweite(quellen, eigene);
  for (final q in quellen) {
    q.phi = phi;
  }

  _setzeDrehungen(quellen, gruppe, eigene);
  _richteAuf(quellen, gruppe);
  schritt();

  // Ausdehnung auf dem Zylinder, Ausgleich und Zuschnitt auf einer
  // groben Leinwand.
  final grob = _GrobeLeinwand.aus(quellen, gruppe);
  final gains = optionen.belichtungAusgleichen
      ? grob.verstaerkungen()
      : [
          for (var i = 0; i < anzahl; i++) Float64List.fromList([1, 1, 1]),
        ];
  final (t0, t1, h0, h1) = optionen.zuschneiden
      ? grob.groesstesRechteck()
      : (grob.theta0, grob.theta1, grob.hoehe0, grob.hoehe1);

  // Massstab des Ergebnisses: so fein wie die Quellen in der Bildmitte,
  // höchstens so gross wie erlaubt.
  final fVoll =
      [
        for (final i in gruppe) phi * quellen[i].langeSeite,
      ].reduce((a, b) => a + b) /
      gruppe.length;
  final b1 = (t1 - t0) * fVoll, h1v = (h1 - h0) * fVoll;
  var s = 1.0;
  s = math.min(s, math.sqrt(optionen.hoechstensPixel / (b1 * h1v)));
  s = math.min(s, optionen.hoechstensKante / b1);
  s = math.min(s, optionen.hoechstensKante / h1v);
  final fAus = fVoll * s;
  final breite = math.max(1, ((t1 - t0) * fAus).floor());
  final hoehe = math.max(1, ((h1 - h0) * fAus).floor());

  final leinwand = Farbbild.leer(breite, hoehe);
  final summe = Float32List(breite * hoehe);
  final reihe = [...gruppe]
    ..sort((a, b) => grob.mitte[a].compareTo(grob.mitte[b]));
  for (final i in reihe) {
    _zeichne(
      lade(i),
      quellen[i],
      gains[i],
      grob.bereich[i],
      leinwand,
      summe,
      t0,
      h0,
      fAus,
      s,
    );
    schritt();
  }
  // Die Quellen, die nicht in der Gruppe sind, zählen als erledigt.
  for (var i = 0; i < anzahl - gruppe.length; i++) {
    schritt();
  }
  return PanoramaErgebnis(leinwand, [...gruppe]..sort(), phi, {
    for (final i in gruppe) i: grob.mitte[i],
  });
}

/// Ordnet zwei Quellen zu und prüft mit RANSAC. `null`, wenn das Paar
/// nicht überzeugt.
_Kante? _verbinde(List<_Quelle> quellen, int i, int j) {
  final qa = quellen[i], qb = quellen[j];
  final paare = ordneZu(qa.merkmale, qb.merkmale);
  if (paare.length < 12) return null;
  final von = Float64List(paare.length * 2);
  final nach = Float64List(paare.length * 2);
  for (var k = 0; k < paare.length; k++) {
    final (x, y) = paare[k];
    von[k * 2] = qa.merkmale.punkte[x * 2] - qa.kleinMx;
    von[k * 2 + 1] = qa.merkmale.punkte[x * 2 + 1] - qa.kleinMy;
    nach[k * 2] = qb.merkmale.punkte[y * 2] - qb.kleinMx;
    nach[k * 2 + 1] = qb.merkmale.punkte[y * 2 + 1] - qb.kleinMy;
  }
  final befund = ransacHomographie(von, nach);
  if (befund == null) return null;
  final n = befund.passend.length;
  // Brown und Lowe: Ein echtes Paar erklärt einen festen Anteil seiner
  // Zuordnungen, ein zufälliges nur wenige.
  if (n < 12 || n <= 8 + 0.3 * paare.length) return null;
  final pa = Float64List(n * 2), pb = Float64List(n * 2);
  for (var k = 0; k < n; k++) {
    final m = befund.passend[k];
    pa[k * 2] = von[m * 2];
    pa[k * 2 + 1] = von[m * 2 + 1];
    pb[k * 2] = nach[m * 2];
    pb[k * 2 + 1] = nach[m * 2 + 1];
  }
  return _Kante(i, j, pa, pb, paare.length);
}

/// Die grösste zusammenhängende Gruppe von Quellen (aufsteigend). Bei
/// gleicher Grösse gewinnt die mit mehr passenden Merkmalen.
List<int> _groessteGruppe(int anzahl, List<_Kante> kanten) {
  final eltern = List<int>.generate(anzahl, (i) => i);
  int wurzel(int i) {
    while (eltern[i] != i) {
      eltern[i] = eltern[eltern[i]];
      i = eltern[i];
    }
    return i;
  }

  for (final k in kanten) {
    eltern[wurzel(k.a)] = wurzel(k.b);
  }
  final gruppen = <int, List<int>>{};
  final gewicht = <int, int>{};
  for (var i = 0; i < anzahl; i++) {
    gruppen.putIfAbsent(wurzel(i), () => []).add(i);
  }
  for (final k in kanten) {
    gewicht.update(
      wurzel(k.a),
      (v) => v + k.passend,
      ifAbsent: () => k.passend,
    );
  }
  List<int>? beste;
  var besteGewicht = -1;
  for (final MapEntry(key: w, value: g) in gruppen.entries) {
    final gw = gewicht[w] ?? 0;
    if (beste == null ||
        g.length > beste.length ||
        (g.length == beste.length && gw > besteGewicht)) {
      beste = g;
      besteGewicht = gw;
    }
  }
  return beste ?? const [];
}

/// Die Richtungen zu den Punkten [p] (x, y je Punkt, bezogen auf die
/// Bildmitte) bei der Brennweite [f], als Einheitsvektoren.
Float64List _strahlen(Float64List p, double f) {
  final n = p.length ~/ 2;
  final r = Float64List(n * 3);
  for (var k = 0; k < n; k++) {
    final x = p[k * 2], y = p[k * 2 + 1];
    final l = math.sqrt(x * x + y * y + f * f);
    r[k * 3] = x / l;
    r[k * 3 + 1] = y / l;
    r[k * 3 + 2] = f / l;
  }
  return r;
}

/// Wie gut die Drehung [r] (Kamera a → Kamera b) die Kante erklärt:
/// Abweichungen in Punkten der kleinen Fassung von b, je Paar.
Float64List _abweichungen(_Kante k, Float64List r, double fa, double fb) {
  final n = k.passend;
  final aus = Float64List(n);
  final a = _strahlen(k.pa, fa);
  for (var m = 0; m < n; m++) {
    final (x, y, z) = wende3(r, a[m * 3], a[m * 3 + 1], a[m * 3 + 2]);
    if (z <= 1e-9) {
      aus[m] = 1e6;
      continue;
    }
    final dx = fb * x / z - k.pb[m * 2], dy = fb * y / z - k.pb[m * 2 + 1];
    aus[m] = math.sqrt(dx * dx + dy * dy);
  }
  return aus;
}

/// Schätzt die Brennweite (bezogen auf die lange Seite), bei der die
/// Drehungen der einzelnen Paare deren Merkmale am besten erklären: erst
/// ein Raster von 0,3 bis 5 (Bildwinkel gut 140° bis 11°), dann ein
/// goldener Schnitt um das beste.
///
/// Warum das trägt: Unter einer reinen Drehung bildet nur die richtige
/// Brennweite die Strahlen des einen Bilds durch eine Drehung auf die des
/// anderen ab; jede andere verbiegt sie, und es bleibt ein Rest. Bei sehr
/// kleinen Drehungen ist der Rest flach – dann ist aber auch die
/// Brennweite fürs Ergebnis gleichgültig.
double _schaetzeBrennweite(List<_Quelle> quellen, List<_Kante> kanten) {
  double rest(double phi) {
    var summe = 0.0;
    var n = 0;
    for (final k in kanten) {
      final fa = phi * quellen[k.a].kleinLang;
      final fb = phi * quellen[k.b].kleinLang;
      final r = besteDrehung(_strahlen(k.pa, fa), _strahlen(k.pb, fb));
      for (final d in _abweichungen(k, r, fa, fb)) {
        summe += math.min(d * d, 25);
        n++;
      }
    }
    return n == 0 ? 0 : summe / n;
  }

  const lo = 0.3, hi = 5.0;
  const stufen = 40;
  var besteK = 0;
  var besteR = double.infinity;
  double phiK(int k) => lo * math.pow(hi / lo, k / (stufen - 1));
  for (var k = 0; k < stufen; k++) {
    final r = rest(phiK(k));
    if (r < besteR) {
      besteR = r;
      besteK = k;
    }
  }
  var a = math.log(phiK(math.max(0, besteK - 1)));
  var b = math.log(phiK(math.min(stufen - 1, besteK + 1)));
  const g = 0.6180339887498949;
  var c = b - g * (b - a), d = a + g * (b - a);
  var rc = rest(math.exp(c)), rd = rest(math.exp(d));
  for (var i = 0; i < 24; i++) {
    if (rc < rd) {
      b = d;
      d = c;
      rd = rc;
      c = b - g * (b - a);
      rc = rest(math.exp(c));
    } else {
      a = c;
      c = d;
      rc = rd;
      d = a + g * (b - a);
      rd = rest(math.exp(d));
    }
  }
  return math.exp((a + b) / 2);
}

/// Setzt die Drehung jeder Quelle der Gruppe: entlang des Spannbaums mit
/// den meisten passenden Merkmalen, dann gemeinsam nachgezogen (jede
/// Kamera abwechselnd gegen alle ihre schon gesetzten Nachbarn). Kanten,
/// die dem Baum widersprechen, fallen vorher heraus – meist zufällige
/// Treffer in wiederkehrenden Mustern.
void _setzeDrehungen(
  List<_Quelle> quellen,
  List<int> gruppe,
  List<_Kante> kanten,
) {
  final gewicht = <int, int>{};
  for (final k in kanten) {
    gewicht.update(k.a, (v) => v + k.passend, ifAbsent: () => k.passend);
    gewicht.update(k.b, (v) => v + k.passend, ifAbsent: () => k.passend);
  }
  final wurzel = gruppe.reduce(
    (a, b) => (gewicht[a] ?? 0) >= (gewicht[b] ?? 0) ? a : b,
  );
  // Prim: immer die stärkste Kante aus dem Baum hinaus.
  final gesetzt = <int>{wurzel};
  final reihe = <int>[wurzel];
  final baum = <_Kante>{};
  quellen[wurzel].drehung = einheit3();
  while (gesetzt.length < gruppe.length) {
    _Kante? beste;
    for (final k in kanten) {
      if (gesetzt.contains(k.a) == gesetzt.contains(k.b)) continue;
      if (beste == null || k.passend > beste.passend) beste = k;
    }
    if (beste == null) break;
    final vonA = gesetzt.contains(beste.a);
    final alt = vonA ? beste.a : beste.b;
    final neu = vonA ? beste.b : beste.a;
    final ra = _kantendrehung(quellen, beste); // a → b
    final rAltNeu = vonA ? ra : transponiert3(ra); // alt → neu
    // b = R_ab · a heisst R_b = R_a · R_abᵀ (Welt aus Kamera).
    quellen[neu].drehung = mal3(quellen[alt].drehung, transponiert3(rAltNeu));
    gesetzt.add(neu);
    reihe.add(neu);
    baum.add(beste);
  }
  // Widersprüchliche Kanten weglassen.
  final tragend = <_Kante>[];
  for (final k in kanten) {
    if (baum.contains(k)) {
      tragend.add(k);
      continue;
    }
    final r = _relativ(quellen, k);
    final d = _abweichungen(k, r, quellen[k.a].fKlein, quellen[k.b].fKlein)
      ..sort();
    if (d[d.length ~/ 2] < 6) tragend.add(k);
  }
  // Gemeinsam nachziehen.
  for (var runde = 0; runde < 10; runde++) {
    for (final j in reihe) {
      if (j == wurzel) continue;
      final von = <double>[], nach = <double>[];
      for (final k in tragend) {
        if (k.a != j && k.b != j) continue;
        final andere = k.a == j ? k.b : k.a;
        final eigene = k.a == j ? k.pa : k.pb;
        final fremde = k.a == j ? k.pb : k.pa;
        final se = _strahlen(eigene, quellen[j].fKlein);
        final sf = _strahlen(fremde, quellen[andere].fKlein);
        final ra = quellen[andere].drehung;
        for (var m = 0; m < se.length ~/ 3; m++) {
          von.addAll([se[m * 3], se[m * 3 + 1], se[m * 3 + 2]]);
          final (x, y, z) = wende3(ra, sf[m * 3], sf[m * 3 + 1], sf[m * 3 + 2]);
          nach.addAll([x, y, z]);
        }
      }
      if (von.length < 9) continue;
      quellen[j].drehung = besteDrehung(
        Float64List.fromList(von),
        Float64List.fromList(nach),
      );
    }
  }
  // Geht das Ganze nicht auf, ist das Ergebnis Unsinn: lieber eine
  // Meldung als ein verbogenes Bild.
  final alle = <double>[];
  for (final k in tragend) {
    alle.addAll(
      _abweichungen(
        k,
        _relativ(quellen, k),
        quellen[k.a].fKlein,
        quellen[k.b].fKlein,
      ),
    );
  }
  alle.sort();
  if (alle.isEmpty || alle[alle.length ~/ 2] > 12) {
    throw const Zusammenfuegefehler(Fuegegrund.nichtAusrichtbar);
  }
}

/// Die Drehung Kamera a → Kamera b aus den Merkmalen der Kante allein.
Float64List _kantendrehung(List<_Quelle> quellen, _Kante k) => besteDrehung(
  _strahlen(k.pa, quellen[k.a].fKlein),
  _strahlen(k.pb, quellen[k.b].fKlein),
);

/// Die Drehung Kamera a → Kamera b aus den gesetzten Drehungen.
Float64List _relativ(List<_Quelle> quellen, _Kante k) =>
    mal3(transponiert3(quellen[k.b].drehung), quellen[k.a].drehung);

/// Richtet das Panorama auf: „unten" ist die Normale der Ebene, in der
/// die x-Achsen aller Kameras liegen (bei einem waagerechten Schwenk
/// dreht sich die Kamera um diese Achse), vorn die mittlere Blickrichtung.
/// Ohne das wanderte ein leicht geneigt aufgenommener Schwenk auf dem
/// Zylinder als Welle auf und ab.
void _richteAuf(List<_Quelle> quellen, List<int> gruppe) {
  final m = Float64List(9);
  var sy0 = 0.0, sy1 = 0.0, sy2 = 0.0;
  var sz0 = 0.0, sz1 = 0.0, sz2 = 0.0;
  for (final i in gruppe) {
    final r = quellen[i].drehung;
    final x0 = r[0], x1 = r[3], x2 = r[6];
    final xs = [x0, x1, x2];
    for (var a = 0; a < 3; a++) {
      for (var b = 0; b < 3; b++) {
        m[a * 3 + b] += xs[a] * xs[b];
      }
    }
    sy0 += r[1];
    sy1 += r[4];
    sy2 += r[7];
    sz0 += r[2];
    sz1 += r[5];
    sz2 += r[8];
  }
  final e = eigenSymmetrisch(m, 3);
  final ordnung = [0, 1, 2]..sort((a, b) => e.werte[a].compareTo(e.werte[b]));
  var ux = e.vektoren[ordnung[0]];
  var uy = e.vektoren[3 + ordnung[0]];
  var uz = e.vektoren[6 + ordnung[0]];
  // Liegen alle x-Achsen fast auf einer Linie (zwei Bilder mit kleinem
  // Winkel), ist die Ebene beliebig: dann gilt das mittlere „unten".
  if (e.werte[ordnung[1]] < 1e-4 * e.werte[ordnung[2]]) {
    ux = sy0;
    uy = sy1;
    uz = sy2;
  }
  var l = math.sqrt(ux * ux + uy * uy + uz * uz);
  ux /= l;
  uy /= l;
  uz /= l;
  if (ux * sy0 + uy * sy1 + uz * sy2 < 0) {
    ux = -ux;
    uy = -uy;
    uz = -uz;
  }
  // Vorn: die mittlere Blickrichtung, waagerecht gelegt.
  final d = sz0 * ux + sz1 * uy + sz2 * uz;
  var zx = sz0 - d * ux, zy = sz1 - d * uy, zz = sz2 - d * uz;
  l = math.sqrt(zx * zx + zy * zy + zz * zz);
  if (l < 1e-9) return;
  zx /= l;
  zy /= l;
  zz /= l;
  // x = y × z (rechtshändig: x rechts, y unten, z vorn).
  final xx = uy * zz - uz * zy, xy = uz * zx - ux * zz, xz = ux * zy - uy * zx;
  final w = Float64List.fromList([xx, xy, xz, ux, uy, uz, zx, zy, zz]);
  for (final i in gruppe) {
    quellen[i].drehung = mal3(w, quellen[i].drehung);
  }
}

/// Die Leinwand in grober Auflösung: Ausdehnung jeder Quelle auf dem
/// Zylinder, die Überdeckung für den Zuschnitt und die Mittelwerte in den
/// Überlappungen für den Belichtungsausgleich.
class _GrobeLeinwand {
  _GrobeLeinwand._(
    this.quellen,
    this.gruppe,
    this.theta0,
    this.theta1,
    this.hoehe0,
    this.hoehe1,
    this.bereich,
    this.mitte,
  );

  factory _GrobeLeinwand.aus(List<_Quelle> quellen, List<int> gruppe) {
    var t0 = double.infinity, t1 = -double.infinity;
    var h0 = double.infinity, h1 = -double.infinity;
    final bereich = List<(double, double, double, double)>.filled(
      quellen.length,
      (0, 0, 0, 0),
    );
    final mitte = List<double>.filled(quellen.length, 0);
    for (final i in gruppe) {
      final q = quellen[i];
      final f = q.fKlein;
      final r = q.drehung;
      // Die Bildmitte, und der Rand in 64 Schritten je Seite.
      final (cx, _, cz) = wende3(r, 0, 0, 1);
      final tc = math.atan2(cx, cz);
      mitte[i] = tc;
      var a0 = double.infinity, a1 = -double.infinity;
      var b0 = double.infinity, b1 = -double.infinity;
      void punkt(double x, double y) {
        final (dx, dy, dz) = wende3(r, x, y, f);
        final waag = math.sqrt(dx * dx + dz * dz);
        var t = math.atan2(dx, dz) - tc;
        while (t > math.pi) {
          t -= 2 * math.pi;
        }
        while (t <= -math.pi) {
          t += 2 * math.pi;
        }
        t += tc;
        final h = (dy / math.max(waag, 1e-9)).clamp(-2.5, 2.5);
        a0 = math.min(a0, t);
        a1 = math.max(a1, t);
        b0 = math.min(b0, h);
        b1 = math.max(b1, h);
      }

      final w = q.klein.breite - 1.0, hh = q.klein.hoehe - 1.0;
      for (var k = 0; k <= 64; k++) {
        final s = k / 64;
        punkt(-w / 2 + s * w, -hh / 2);
        punkt(-w / 2 + s * w, hh / 2);
        punkt(-w / 2, -hh / 2 + s * hh);
        punkt(w / 2, -hh / 2 + s * hh);
      }
      bereich[i] = (a0, a1, b0, b1);
      t0 = math.min(t0, a0);
      t1 = math.max(t1, a1);
      h0 = math.min(h0, b0);
      h1 = math.max(h1, b1);
    }
    final l = _GrobeLeinwand._(quellen, gruppe, t0, t1, h0, h1, bereich, mitte);
    l._tasteAb();
    return l;
  }

  final List<_Quelle> quellen;
  final List<int> gruppe;
  final double theta0, theta1, hoehe0, hoehe1;

  /// Je Quelle: Winkel von–bis und Höhe von–bis auf dem Zylinder.
  final List<(double, double, double, double)> bereich;

  /// Je Quelle: der Winkel der Bildmitte.
  final List<double> mitte;

  late final double f;
  late final int breite, hoehe;

  /// Ob ein grober Punkt sicher im Bild liegt.
  late final Uint8List gedeckt;

  /// Je Paar (a · n + b): Zahl der gemeinsamen Punkte und die Summe der
  /// Farbwerte von a dort (je Kanal).
  late final Float64List anzahlPaar, summePaar;

  void _tasteAb() {
    f = math.min(1600 / (theta1 - theta0), 800 / (hoehe1 - hoehe0));
    breite = math.max(2, ((theta1 - theta0) * f).ceil());
    hoehe = math.max(2, ((hoehe1 - hoehe0) * f).ceil());
    final n = quellen.length;
    gedeckt = Uint8List(breite * hoehe);
    anzahlPaar = Float64List(n * n);
    summePaar = Float64List(n * n * 3);
    final farbe = Float64List(3 * n);
    final treffer = <int>[];
    for (var v = 0; v < hoehe; v++) {
      final h = hoehe0 + (v + 0.5) / f;
      for (var u = 0; u < breite; u++) {
        final t = theta0 + (u + 0.5) / f;
        final st = math.sin(t), ct = math.cos(t);
        treffer.clear();
        var sicher = false;
        for (final i in gruppe) {
          final q = quellen[i];
          final r = q.drehung;
          // Kamera aus Welt: Rᵀ · d.
          final cx = r[0] * st + r[3] * h + r[6] * ct;
          final cy = r[1] * st + r[4] * h + r[7] * ct;
          final cz = r[2] * st + r[5] * h + r[8] * ct;
          if (cz <= 1e-9) continue;
          final fk = q.fKlein;
          final x = fk * cx / cz + q.kleinMx, y = fk * cy / cz + q.kleinMy;
          final w = q.klein.breite, hh = q.klein.hoehe;
          if (x < 0 || y < 0 || x > w - 1 || y > hh - 1) continue;
          if (x >= 2 && y >= 2 && x <= w - 3 && y <= hh - 3) sicher = true;
          tasteAb(q.klein, x, y, farbe, i * 3);
          treffer.add(i);
        }
        if (sicher) gedeckt[v * breite + u] = 1;
        for (final a in treffer) {
          for (final b in treffer) {
            if (a == b) continue;
            anzahlPaar[a * n + b] += 1;
            for (var k = 0; k < 3; k++) {
              summePaar[(a * n + b) * 3 + k] += farbe[a * 3 + k];
            }
          }
          anzahlPaar[a * n + a] += 1;
        }
      }
    }
  }

  /// Die Verstärkung je Quelle und Farbkanal nach Brown und Lowe: In jeder
  /// Überlappung sollen beide Bilder gleich hell sein (σN = 10 Stufen),
  /// gewichtet nach der Zahl gemeinsamer Punkte.
  ///
  /// **Schwächer an eins gebunden als bei Brown und Lowe.** Dort hält
  /// σg = 0,1 jede Verstärkung nahe eins; das gleicht eine um 30 % dunklere
  /// Aufnahme im Versuch nur zur Hälfte aus, und die Stufe blieb sichtbar.
  /// Hier ist σg = 1, und danach wird so geteilt, dass die Verstärkungen
  /// im Mittel (nach Bildfläche) eins sind – das Panorama bleibt so hell
  /// wie seine Quellen im Durchschnitt.
  List<Float64List> verstaerkungen() {
    final n = quellen.length;
    final aus = List<Float64List>.generate(
      n,
      (_) => Float64List.fromList([1, 1, 1]),
    );
    final idx = gruppe;
    final m = idx.length;
    const alpha = 0.01, beta = 1.0;
    for (var k = 0; k < 3; k++) {
      final a = Float64List(m * m);
      final b = Float64List(m);
      for (var p = 0; p < m; p++) {
        final i = idx[p];
        for (var q = 0; q < m; q++) {
          final j = idx[q];
          final nij = anzahlPaar[i * n + j];
          if (nij == 0) continue;
          b[p] += beta * nij;
          a[p * m + p] += beta * nij;
          if (i == j) continue;
          final iij = summePaar[(i * n + j) * 3 + k] / nij;
          final iji = summePaar[(j * n + i) * 3 + k] / nij;
          a[p * m + p] += 2 * alpha * iij * iij * nij;
          a[p * m + q] -= 2 * alpha * iij * iji * nij;
        }
      }
      final g = loese(a, b, m);
      if (g == null) continue;
      var summe = 0.0, flaeche = 0.0;
      for (var p = 0; p < m; p++) {
        final f = anzahlPaar[idx[p] * n + idx[p]];
        summe += g[p] * f;
        flaeche += f;
      }
      final mittel = flaeche > 0 && summe > 0 ? summe / flaeche : 1.0;
      for (var p = 0; p < m; p++) {
        aus[idx[p]][k] = (g[p] / mittel).clamp(0.5, 2.0);
      }
    }
    return aus;
  }

  /// Das grösste achsparallele Rechteck, in dem jeder grobe Punkt gedeckt
  /// ist (Histogramm je Zeile, Stapelverfahren), eine grobe Zeile und
  /// Spalte nach innen gerückt. Als Winkel und Höhe; ist kein brauchbares
  /// Rechteck da, die ganze Ausdehnung.
  (double, double, double, double) groesstesRechteck() {
    final hoch = Int32List(breite);
    var besteFlaeche = 0;
    var bx0 = 0, bx1 = 0, by0 = 0, by1 = 0;
    final stapel = <int>[];
    for (var v = 0; v < hoehe; v++) {
      for (var u = 0; u < breite; u++) {
        hoch[u] = gedeckt[v * breite + u] == 1 ? hoch[u] + 1 : 0;
      }
      stapel.clear();
      for (var u = 0; u <= breite; u++) {
        final hu = u == breite ? 0 : hoch[u];
        while (stapel.isNotEmpty && hoch[stapel.last] >= hu) {
          final top = stapel.removeLast();
          final hh = hoch[top];
          final links = stapel.isEmpty ? 0 : stapel.last + 1;
          final flaeche = hh * (u - links);
          if (flaeche > besteFlaeche) {
            besteFlaeche = flaeche;
            bx0 = links;
            bx1 = u;
            by0 = v - hh + 1;
            by1 = v + 1;
          }
        }
        stapel.add(u);
      }
    }
    if (bx1 - bx0 < 6 || by1 - by0 < 6) {
      return (theta0, theta1, hoehe0, hoehe1);
    }
    return (
      theta0 + (bx0 + 1) / f,
      theta0 + (bx1 - 1) / f,
      hoehe0 + (by0 + 1) / f,
      hoehe0 + (by1 - 1) / f,
    );
  }
}

/// Zeichnet die Quelle [b] auf die Leinwand: für jeden Punkt im Bereich
/// der Quelle die Stelle im Foto (rückwärts über Zylinder und Drehung),
/// bilinear abgetastet, mit der Verstärkung [gain] und einem Gewicht, das
/// zum Bildrand linear auf null fällt, in den laufenden Mittelwert
/// gemischt.
void _zeichne(
  Farbbild b,
  _Quelle q,
  Float64List gain,
  (double, double, double, double) bereich,
  Farbbild leinwand,
  Float32List summe,
  double t0,
  double h0,
  double fAus,
  double massstab,
) {
  // Ist das Ergebnis deutlich kleiner als die Quelle, erst die Quelle
  // verkleinern – sonst flimmern feine Muster, und das Abtasten liefe über
  // 24 MP, von denen nur ein Bruchteil gebraucht wird.
  var quelle = b;
  if (massstab < 0.75) {
    quelle = verkleinere(
      b,
      math.max(2, (b.breite * massstab * 1.2).round()),
      math.max(2, (b.hoehe * massstab * 1.2).round()),
    );
  }
  final w = quelle.breite, h = quelle.hoehe;
  final f = q.phi * math.max(w, h);
  final mx = (w - 1) / 2, my = (h - 1) / 2;
  final r = q.drehung;
  final bl = leinwand.breite, hl = leinwand.hoehe;
  final (a0, a1, c0, c1) = bereich;
  final u0 = math.max(0, ((a0 - t0) * fAus).floor() - 1);
  final u1 = math.min(bl, ((a1 - t0) * fAus).ceil() + 1);
  final v0 = math.max(0, ((c0 - h0) * fAus).floor() - 1);
  final v1 = math.min(hl, ((c1 - h0) * fAus).ceil() + 1);
  if (u1 <= u0 || v1 <= v0) return;
  final sinT = Float64List(u1 - u0), cosT = Float64List(u1 - u0);
  for (var u = u0; u < u1; u++) {
    final t = t0 + (u + 0.5) / fAus;
    sinT[u - u0] = math.sin(t);
    cosT[u - u0] = math.cos(t);
  }
  final qrgb = quelle.rgb;
  final z = leinwand.rgb;
  final g0 = gain[0], g1 = gain[1], g2 = gain[2];
  final halbW = w / 2, halbH = h / 2;
  for (var v = v0; v < v1; v++) {
    final hv = h0 + (v + 0.5) / fAus;
    final ay = r[3] * hv, by = r[4] * hv, cy = r[5] * hv;
    for (var u = u0; u < u1; u++) {
      final st = sinT[u - u0], ct = cosT[u - u0];
      final cz = r[2] * st + cy + r[8] * ct;
      if (cz <= 1e-9) continue;
      final cx = r[0] * st + ay + r[6] * ct;
      final cyy = r[1] * st + by + r[7] * ct;
      final x = f * cx / cz + mx, y = f * cyy / cz + my;
      if (x < 0 || y < 0 || x > w - 1 || y > h - 1) continue;
      final x0 = x.toInt(), y0 = y.toInt();
      final x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < h ? y0 + 1 : y0;
      final fx = x - x0, fy = y - y0;
      final w00 = (1 - fx) * (1 - fy), w10 = fx * (1 - fy);
      final w01 = (1 - fx) * fy, w11 = fx * fy;
      final i00 = (y0 * w + x0) * 3, i10 = (y0 * w + x1) * 3;
      final i01 = (y1 * w + x0) * 3, i11 = (y1 * w + x1) * 3;
      final rr =
          (qrgb[i00] * w00 +
              qrgb[i10] * w10 +
              qrgb[i01] * w01 +
              qrgb[i11] * w11) *
          g0;
      final gg =
          (qrgb[i00 + 1] * w00 +
              qrgb[i10 + 1] * w10 +
              qrgb[i01 + 1] * w01 +
              qrgb[i11 + 1] * w11) *
          g1;
      final bb =
          (qrgb[i00 + 2] * w00 +
              qrgb[i10 + 2] * w10 +
              qrgb[i01 + 2] * w01 +
              qrgb[i11 + 2] * w11) *
          g2;
      final gx = math.min(x + 1, w - x) / halbW;
      final gy = math.min(y + 1, h - y) / halbH;
      final gewicht = gx * gy;
      final k = v * bl + u;
      final alt = summe[k];
      final neu = alt + gewicht;
      summe[k] = neu;
      final anteil = gewicht / neu;
      final o = k * 3;
      z[o] = _byte(z[o] + (rr - z[o]) * anteil);
      z[o + 1] = _byte(z[o + 1] + (gg - z[o + 1]) * anteil);
      z[o + 2] = _byte(z[o + 2] + (bb - z[o + 2]) * anteil);
    }
  }
}

int _byte(double v) {
  final x = (v + 0.5).floor();
  return x < 0 ? 0 : (x > 255 ? 255 : x);
}

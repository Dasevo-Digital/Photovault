/// Umrisse von Ländern und Regionen – damit ein besuchtes Gebiet auf der
/// Karte eine **Fläche** ist und nicht ein Punkt daneben.
///
/// **Warum eine eigene Datei und nicht GeoNames.** Der GeoNames-Auszug,
/// aus dem die App Orte auflöst, kennt nur Punkte. Grenzen stehen dort
/// nicht drin. Der Umriss kommt deshalb aus Natural Earth
/// (gemeinfrei, https://www.naturalearthdata.com) und wird von
/// `tool/gebiete_bauen.py` in das Format hier übersetzt.
///
/// **Der Schlüssel ist derselbe wie überall sonst:** ISO-2 für Länder,
/// der GeoNames-Regionscode („DE.02") für Regionen. Verknüpft wurde beim
/// Bauen über die GeoNames-Kennung, nicht über den Namen – Namen weichen
/// zwischen zwei Datensätzen ab, Kennungen nicht.
///
/// **Was die Umrisse nicht sind:** Sie sind auf rund zwei Kilometer
/// vereinfacht und haben keine Löcher. Berlin liegt deshalb sowohl in
/// Berlin als auch in Brandenburg. Wo sich Flächen überschneiden,
/// entscheidet die **kleinere** – so gewinnt die Enklave gegen ihren
/// Nachbarn, Lesotho gegen Südafrika und der Stadtstaat gegen das
/// Flächenland.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Ein Punkt eines Umrisses.
typedef Grenzpunkt = ({double breite, double laenge});

/// Ein Land oder eine Region als Umriss.
class Gebiet {
  /// `'land'` oder `'region'`.
  final String art;

  /// ISO-2 („DE") oder GeoNames-Regionscode („DE.02").
  final String schluessel;

  /// Ein Eintrag je Teilfläche – Inseln sind eigene Ringe.
  final List<List<Grenzpunkt>> ringe;

  Gebiet({required this.art, required this.schluessel, required this.ringe});

  /// Fläche in Quadratgrad. **Kein Flächenmaß, sondern ein Vergleichswert:**
  /// Nahe den Polen ist ein Grad Länge viel kürzer als am Äquator. Für die
  /// Frage „welches der beiden Gebiete ist das kleinere" reicht das, für
  /// eine Angabe in Quadratkilometern nicht.
  late final double vergleichsflaeche = () {
    var summe = 0.0;
    for (final ring in ringe) {
      var a = 0.0;
      for (var i = 0; i + 1 < ring.length; i++) {
        a += ring[i].laenge * ring[i + 1].breite -
            ring[i + 1].laenge * ring[i].breite;
      }
      summe += a.abs() / 2;
    }
    return summe;
  }();

  /// Liegt der Punkt in einem der Ringe? Strahlverfahren.
  bool enthaelt(double breite, double laenge) {
    for (final ring in ringe) {
      if (_imRing(ring, breite, laenge)) return true;
    }
    return false;
  }

  static bool _imRing(List<Grenzpunkt> ring, double breite, double laenge) {
    var drin = false;
    var j = ring.length - 1;
    for (var i = 0; i < ring.length; i++) {
      final bi = ring[i].breite, li = ring[i].laenge;
      final bj = ring[j].breite, lj = ring[j].laenge;
      if ((bi > breite) != (bj > breite) &&
          laenge < (lj - li) * (breite - bi) / (bj - bi) + li) {
        drin = !drin;
      }
      j = i;
    }
    return drin;
  }
}

/// Alle Umrisse, aber **erst entpackt, wenn danach gefragt wird.**
///
/// Die Datei trägt rund 3500 Gebiete mit 157.000 Punkten. Wer eine Karte
/// mit fünf besuchten Ländern öffnet, braucht davon fünf Umrisse. Beim
/// Laden wird deshalb nur nach Zeilen zerlegt; die Punkte einer Zeile
/// entstehen beim ersten Zugriff und bleiben dann liegen.
class Gebietsgrenzen {
  Gebietsgrenzen._(this._zeilen);

  /// Schlüssel („L\tDE") auf die noch unentpackte Zeile.
  final Map<String, String> _zeilen;
  final Map<String, Gebiet> _entpackt = {};

  /// Wie viele Gebiete die Datei kennt.
  int get anzahl => _zeilen.length;

  /// Aus dem gepackten Inhalt der mitgelieferten Datei.
  static Gebietsgrenzen ausGepackt(List<int> gepackt) =>
      ausText(utf8.decode(gzip.decode(gepackt)));

  static Gebietsgrenzen ausText(String text) {
    final zeilen = <String, String>{};
    for (final zeile in const LineSplitter().convert(text)) {
      if (zeile.isEmpty) continue;
      final ersterTab = zeile.indexOf('\t');
      if (ersterTab <= 0) continue;
      final zweiterTab = zeile.indexOf('\t', ersterTab + 1);
      if (zweiterTab < 0) continue;
      zeilen[zeile.substring(0, zweiterTab)] = zeile;
    }
    return Gebietsgrenzen._(zeilen);
  }

  Gebiet? _hole(String art, String schluessel) {
    final sch = '${art == 'land' ? 'L' : 'R'}\t$schluessel';
    final fertig = _entpackt[sch];
    if (fertig != null) return fertig;
    final zeile = _zeilen[sch];
    if (zeile == null) return null;
    final gebiet = Gebiet(
      art: art,
      schluessel: schluessel,
      ringe: _ringeAus(zeile.substring(zeile.indexOf('\t', 2) + 1)),
    );
    return _entpackt[sch] = gebiet;
  }

  /// Der Umriss eines Landes, oder `null`, wenn keiner vorliegt.
  ///
  /// Es fehlen siebzehn der 252 GeoNames-Länder – Winzlinge wie der
  /// Vatikan, aufgelöste Gebilde wie die Niederländischen Antillen und
  /// die französischen Übersee-Departements, die Natural Earth zu
  /// Frankreich zählt. Für die bleibt es beim Punkt auf der Karte.
  Gebiet? land(String iso) => _hole('land', iso.toUpperCase());

  /// Der Umriss einer Region („DE.02").
  Gebiet? region(String code) => _hole('region', code);

  /// Welches Land liegt unter diesem Punkt?
  ///
  /// `null` auf offener See – und zwar richtigerweise. Die Suche über die
  /// nächstgelegene Stadt würde mitten im Atlantik noch Island liefern.
  String? landBei(double breite, double laenge) =>
      _kleinstesGebiet('L', breite, laenge)?.substring(2);

  /// Welche Region liegt unter diesem Punkt?
  ///
  /// [imLand] engt auf ein Land ein und ist die Regel, nicht die
  /// Ausnahme: Das Land steht vorher schon fest, und ohne die Einengung
  /// würden alle 3253 Regionen der Welt geprüft.
  String? regionBei(double breite, double laenge, {String? imLand}) {
    final praefix = imLand == null ? null : '${imLand.toUpperCase()}.';
    return _kleinstesGebiet('R', breite, laenge, praefix)?.substring(2);
  }

  String? _kleinstesGebiet(String art, double breite, double laenge,
      [String? praefix]) {
    String? beste;
    var besteFlaeche = double.infinity;
    for (final sch in _zeilen.keys) {
      if (sch.codeUnitAt(0) != art.codeUnitAt(0)) continue;
      if (praefix != null && !sch.startsWith(praefix, 2)) continue;
      final gebiet = _hole(art == 'L' ? 'land' : 'region', sch.substring(2));
      if (gebiet == null || !gebiet.enthaelt(breite, laenge)) continue;
      if (gebiet.vergleichsflaeche < besteFlaeche) {
        besteFlaeche = gebiet.vergleichsflaeche;
        beste = sch;
      }
    }
    return beste;
  }

  /// Die Punkte einer Zeile.
  ///
  /// Format: Ringe durch `;` getrennt, Punkte durch Leerzeichen, je Punkt
  /// `Länge,Breite` als **Unterschied zum vorigen**, in Schritten von
  /// einem Zweitausendstelgrad (rund 55 Meter).
  ///
  /// Beides zusammen macht aus 2,6 Megabyte Text 1,1 Megabyte Datei:
  /// Nachbarpunkte eines Umrisses liegen dicht beieinander, ihre
  /// Differenzen sind kurze Zahlen. Die Schrittweite ist bewusst viel
  /// feiner als die Vereinfachung selbst (2,2 km) – sie soll nichts
  /// hinzufügen, nur nichts wegnehmen.
  static List<List<Grenzpunkt>> _ringeAus(String daten) {
    final ringe = <List<Grenzpunkt>>[];
    for (final teil in daten.split(';')) {
      if (teil.isEmpty) continue;
      final ring = <Grenzpunkt>[];
      var x = 0, y = 0;
      for (final paar in teil.split(' ')) {
        final komma = paar.indexOf(',');
        if (komma < 0) continue;
        x += int.parse(paar.substring(0, komma));
        y += int.parse(paar.substring(komma + 1));
        ring.add((breite: y / 2000, laenge: x / 2000));
      }
      if (ring.length >= 4) ringe.add(ring);
    }
    return ringe;
  }

  /// Mittelpunkt des grössten Rings – für eine Beschriftung oder einen
  /// Punkt, wenn die Fläche zu klein zum Antippen ist.
  static Grenzpunkt mittelpunkt(Gebiet gebiet) {
    var groesster = gebiet.ringe.first;
    var beste = -1.0;
    for (final ring in gebiet.ringe) {
      var a = 0.0;
      for (var i = 0; i + 1 < ring.length; i++) {
        a += ring[i].laenge * ring[i + 1].breite -
            ring[i + 1].laenge * ring[i].breite;
      }
      if (a.abs() > beste) {
        beste = a.abs();
        groesster = ring;
      }
    }
    var b = 0.0, l = 0.0;
    for (final p in groesster) {
      b += p.breite;
      l += p.laenge;
    }
    return (breite: b / groesster.length, laenge: l / groesster.length);
  }

  /// Wie weit ein Gebiet reicht – für „auf das Gebiet zoomen".
  static ({double sued, double west, double nord, double ost}) huelle(
      Gebiet gebiet) {
    var sued = 90.0, nord = -90.0, west = 180.0, ost = -180.0;
    for (final ring in gebiet.ringe) {
      for (final p in ring) {
        sued = math.min(sued, p.breite);
        nord = math.max(nord, p.breite);
        west = math.min(west, p.laenge);
        ost = math.max(ost, p.laenge);
      }
    }
    return (sued: sued, west: west, nord: nord, ost: ost);
  }
}

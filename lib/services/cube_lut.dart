/// Liest 3D-Farbtabellen im `.cube`-Format ein – das Austauschformat für
/// Filmsimulationen und fremde Bildlooks.
///
/// Warum das hier so wenig Code ist: [buildColorCube] in develop_color.dart
/// baut für den Farbmischer bereits einen Würfel aus Stützstellen, den
/// beide Renderpfade übernehmen – der Shader als Streifentextur, Core Image
/// als `CIColorCubeWithColorSpace`. Eine `.cube`-Datei ist genau dieselbe
/// Struktur, nur aus einer Textdatei statt aus einer Rechnung. Sie kommt
/// deshalb nicht als zusätzlicher Schritt in die Kette, sondern wird in den
/// vorhandenen Würfel **hineingerechnet**. Es entsteht keine Zeile
/// Bildmathematik in Shader oder Swift.
library;

import 'dart:typed_data';

/// Woran das Einlesen gescheitert ist.
///
/// Als Aufzählung und nicht als fertiger Satz: Welcher Text daraus wird,
/// entscheidet die Oberfläche, die weiss, in welcher Sprache sie spricht
/// (dieselbe Trennung wie bei [FaceClusterFehler]).
enum CubeFehler {
  /// Keine `LUT_3D_SIZE`-Zeile gefunden.
  keineGroesse,

  /// Eine Kantenlänge, die das Format nicht vorsieht (erlaubt sind 2..256).
  ungueltigeGroesse,

  /// Eine eindimensionale Tabelle. Sie beschreibt eine Kurve, keinen
  /// Farbraum – dafür gibt es in dieser App die Tonwertkurve.
  nurEindimensional,

  /// Zu wenige oder zu viele Datenzeilen für die angegebene Kantenlänge.
  falscheZeilenzahl,

  /// Eine Zeile, die weder Anweisung noch drei Zahlen ist.
  unlesbareZeile,
}

class CubeAusnahme implements Exception {
  final CubeFehler grund;

  /// Die Zeilennummer, an der es scheiterte – 0, wenn es die ganze Datei
  /// betrifft.
  final int zeile;

  const CubeAusnahme(this.grund, {this.zeile = 0});

  @override
  String toString() => 'CubeAusnahme($grund, Zeile $zeile)';
}

/// Eine eingelesene 3D-Farbtabelle.
class CubeLut {
  /// Kantenlänge des Würfels (üblich sind 17, 32, 33, 64).
  final int size;

  /// [size]³ RGB-Tripel, Rot läuft am schnellsten – dieselbe Reihenfolge
  /// wie in [buildColorCube] und wie `.cube` sie vorschreibt.
  final Float32List werte;

  /// Der Titel aus der Datei, falls angegeben.
  final String? titel;

  /// Der Wertebereich der **Eingabe**, den die Tabelle erwartet – fast
  /// immer 0..1.
  ///
  /// Die Angabe betrifft ausdrücklich nicht die Tabellenwerte: Die sind
  /// Ausgabefarben und bleiben, wie sie in der Datei stehen. Sie
  /// stattdessen umzurechnen wäre ein stiller Farbfehler bei jeder Datei,
  /// die einen anderen Bereich angibt.
  final List<double> domainMin;
  final List<double> domainMax;

  const CubeLut({
    required this.size,
    required this.werte,
    this.titel,
    this.domainMin = const [0, 0, 0],
    this.domainMax = const [1, 1, 1],
  });

  /// Liest die Tabelle an der Stelle [r],[g],[b] (je 0..1) ab, trilinear
  /// zwischen den acht umgebenden Stützstellen gemittelt.
  ///
  /// Ohne diese Mittelung entstünden bei einer 17er-Tabelle sichtbare
  /// Stufen in weichen Verläufen – Himmel und Haut sind genau die Stellen,
  /// an denen Filmlooks eingesetzt werden.
  List<double> abtasten(double r, double g, double b) {
    final letzter = size - 1;
    double aufIndex(double wert, int k) {
      final spanne = domainMax[k] - domainMin[k];
      final anteil = spanne == 0 ? 0.0 : (wert - domainMin[k]) / spanne;
      return anteil.clamp(0.0, 1.0) * letzter;
    }

    final rp = aufIndex(r, 0);
    final gp = aufIndex(g, 1);
    final bp = aufIndex(b, 2);

    final r0 = rp.floor(), g0 = gp.floor(), b0 = bp.floor();
    final r1 = r0 < letzter ? r0 + 1 : r0;
    final g1 = g0 < letzter ? g0 + 1 : g0;
    final b1 = b0 < letzter ? b0 + 1 : b0;
    final fr = rp - r0, fg = gp - g0, fb = bp - b0;

    List<double> stelle(int ri, int gi, int bi) {
      final i = ((bi * size + gi) * size + ri) * 3;
      return [werte[i], werte[i + 1], werte[i + 2]];
    }

    List<double> misch(List<double> a, List<double> b, double t) =>
        [for (var i = 0; i < 3; i++) a[i] + (b[i] - a[i]) * t];

    final c00 = misch(stelle(r0, g0, b0), stelle(r1, g0, b0), fr);
    final c10 = misch(stelle(r0, g1, b0), stelle(r1, g1, b0), fr);
    final c01 = misch(stelle(r0, g0, b1), stelle(r1, g0, b1), fr);
    final c11 = misch(stelle(r0, g1, b1), stelle(r1, g1, b1), fr);

    return misch(misch(c00, c10, fg), misch(c01, c11, fg), fb);
  }
}

/// Liest den Inhalt einer `.cube`-Datei.
///
/// Wirft [CubeAusnahme]. Was hier bewusst NICHT passiert: raten. Eine
/// Datei mit falscher Zeilenzahl wird abgelehnt statt aufgefüllt – ein
/// halb eingelesener Farbraum sähe aus wie ein kaputtes Foto, und niemand
/// käme auf die Datei als Ursache.
CubeLut parseCubeLut(String inhalt) {
  int? groesse;
  String? titel;
  var min = [0.0, 0.0, 0.0];
  var max = [1.0, 1.0, 1.0];
  final werte = <double>[];

  final zeilen = inhalt.split('\n');
  for (var nr = 0; nr < zeilen.length; nr++) {
    // Kommentare beginnen mit '#'; Leerzeilen sind erlaubt.
    final roh = zeilen[nr];
    final ohneKommentar = roh.contains('#') ? roh.substring(0, roh.indexOf('#')) : roh;
    final zeile = ohneKommentar.trim();
    if (zeile.isEmpty) continue;

    final teile = zeile.split(RegExp(r'\s+'));
    final wort = teile.first.toUpperCase();

    switch (wort) {
      case 'TITLE':
        titel = zeile.substring(zeile.indexOf(teile[0]) + teile[0].length).trim();
        titel = titel.replaceAll('"', '').trim();
        if (titel.isEmpty) titel = null;
      case 'LUT_3D_SIZE':
        final n = int.tryParse(teile.length > 1 ? teile[1] : '');
        if (n == null || n < 2 || n > 256) {
          throw CubeAusnahme(CubeFehler.ungueltigeGroesse, zeile: nr + 1);
        }
        groesse = n;
      case 'LUT_1D_SIZE':
        throw CubeAusnahme(CubeFehler.nurEindimensional, zeile: nr + 1);
      case 'DOMAIN_MIN':
        // Ab Feld 1: In Feld 0 steht das Schlüsselwort. Ab 0 zu lesen
        // liefert null, und die Angabe fiele still unter den Tisch.
        min = _dreiZahlen(teile, ab: 1) ?? min;
      case 'DOMAIN_MAX':
        max = _dreiZahlen(teile, ab: 1) ?? max;
      case 'LUT_3D_INPUT_RANGE':
        // Ältere Schreibweise für den Wertebereich: zwei Zahlen für alle
        // drei Kanäle.
        final a = double.tryParse(teile.length > 1 ? teile[1] : '');
        final e = double.tryParse(teile.length > 2 ? teile[2] : '');
        if (a != null && e != null) {
          min = [a, a, a];
          max = [e, e, e];
        }
      default:
        final zahlen = _dreiZahlen(teile);
        if (zahlen == null) throw CubeAusnahme(CubeFehler.unlesbareZeile, zeile: nr + 1);
        // Unverändert übernehmen: Das sind Ausgabefarben. Der Bereich aus
        // DOMAIN_MIN/MAX gilt für die Eingabe und wird beim Abtasten
        // angewandt.
        werte.addAll(zahlen);
    }
  }

  if (groesse == null) throw const CubeAusnahme(CubeFehler.keineGroesse);
  if (werte.length != groesse * groesse * groesse * 3) {
    throw const CubeAusnahme(CubeFehler.falscheZeilenzahl);
  }
  return CubeLut(
    size: groesse,
    werte: Float32List.fromList(werte),
    titel: titel,
    domainMin: min,
    domainMax: max,
  );
}

/// Drei Fliesskommazahlen ab Feld [ab] – oder `null`, wenn dort keine
/// stehen.
List<double>? _dreiZahlen(List<String> teile, {int ab = 0}) {
  if (teile.length < ab + 3) return null;
  final a = double.tryParse(teile[ab]);
  final b = double.tryParse(teile[ab + 1]);
  final c = double.tryParse(teile[ab + 2]);
  if (a == null || b == null || c == null) return null;
  return [a, b, c];
}

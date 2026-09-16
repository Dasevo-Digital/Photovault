/// **Was von der scharfen Landschaft im Speicher bleibt.**
///
/// Die Blöcke einer Tour durch das Ilsetal wären auf der feinsten Stufe
/// zusammen 320 MB – für einen Ausschnitt von knapp drei mal drei
/// Kilometern. Gehalten werden kann nur ein Bruchteil, und die Frage ist,
/// welcher.
///
/// **Nach Entfernung, nicht nach Alter.** Ein gewöhnlicher Vorrat wirft
/// das am längsten Unbenutzte weg. Hier ist das falsch: Der Flug bewegt
/// sich, und was gerade hinter der Kamera liegt, ist zwar frisch benutzt,
/// aber am wenigsten wert. Verdrängt wird deshalb, was am weitesten weg
/// ist – und bei gleicher Entfernung die feinere Fassung zuerst, weil sie
/// mehr Platz freigibt.
///
/// **Gröber ist besser als nichts.** Zu jedem Block können mehrere Stufen
/// zugleich liegen. Solange die feine lädt, wird die gröbere gezeigt;
/// ohne diese Kette bliebe die Landschaft während des Ladens
/// stellenweise leer, und Löcher fallen mehr auf als Unschärfe.
///
/// Der Inhalt ist ein Typparameter und kein Bild: So lässt sich die
/// Verdrängung mit Zahlen prüfen, ohne eine Grafikkarte zu bemühen.
library;

import 'gelaendetextur.dart';

/// Ein Eintrag im Vorrat.
class Vorratsstueck<T> {
  Vorratsstueck({
    required this.block,
    required this.stufe,
    required this.inhalt,
    required this.bytes,
  });

  final Texturblock block;
  final int stufe;
  final T inhalt;
  final int bytes;
}

/// Ein nach Grösse gedeckelter Vorrat an Blocktexturen.
class Blockvorrat<T> {
  Blockvorrat({
    required this.hoechstensBytes,
    required this.freigeben,
  });

  /// Die Obergrenze in Bytes.
  ///
  /// Gemessen wurde, was sie kauft (Zeitleiste 1600 × 1000, doppelte
  /// Punktdichte, echte Bibliothek): Bei 100 MB war der erste Bildschirm
  /// nach drei Bildschirmen verdrängt, bei 200 MB nach sieben, bei 300 MB
  /// nach elf. Für die Landschaft gilt dieselbe Art von Abwägung; die
  /// Zahl kommt von aussen, damit sie sich messen lässt, statt hier zu
  /// stehen.
  final int hoechstensBytes;

  /// Was mit einem verdrängten Inhalt zu tun ist – bei einem `ui.Image`
  /// ist das `dispose`, und ohne diesen Aufruf bliebe der Speicher der
  /// Grafikkarte belegt.
  final void Function(T inhalt) freigeben;

  final _stuecke = <String, Vorratsstueck<T>>{};
  int _belegt = 0;

  int get belegt => _belegt;
  int get anzahl => _stuecke.length;

  static String _schluessel(Texturblock b, int stufe) =>
      '${b.grundstufe}/${b.spalte}/${b.zeile}@$stufe';

  /// Genau diese Stufe, oder `null`.
  T? bei(Texturblock block, int stufe) =>
      _stuecke[_schluessel(block, stufe)]?.inhalt;

  /// Die feinste vorhandene Fassung eines Blocks, höchstens [hoechstens].
  ///
  /// Das ist der Rückfall während des Ladens: lieber die gröbere Fassung
  /// als ein Loch.
  Vorratsstueck<T>? bestes(Texturblock block, {int hoechstens = 24}) {
    Vorratsstueck<T>? gefunden;
    for (var s = hoechstens; s >= 0; s--) {
      final x = _stuecke[_schluessel(block, s)];
      if (x != null) {
        gefunden = x;
        break;
      }
    }
    return gefunden;
  }

  /// Legt eine Textur ab. Eine schon vorhandene derselben Stufe wird
  /// freigegeben und ersetzt.
  void lege(Texturblock block, int stufe, T inhalt, int bytes) {
    final k = _schluessel(block, stufe);
    final alt = _stuecke.remove(k);
    if (alt != null) {
      _belegt -= alt.bytes;
      freigeben(alt.inhalt);
    }
    _stuecke[k] = Vorratsstueck(
        block: block, stufe: stufe, inhalt: inhalt, bytes: bytes);
    _belegt += bytes;
  }

  /// Verdrängt, bis die Obergrenze wieder eingehalten ist.
  ///
  /// [entfernung] sagt, wie weit ein Block von der Kamera weg ist; was am
  /// weitesten weg ist, geht zuerst. Bei gleicher Entfernung fällt die
  /// **feinere** Fassung zuerst – sie ist die teuerste, und die gröbere
  /// darunter hält die Stelle weiter besetzt.
  ///
  /// [behalten] schützt einzelne Blöcke, egal wie weit sie weg sind: Was
  /// gerade gezeichnet wird, darf nicht unter der Hand verschwinden.
  void raeume(
    double Function(Texturblock) entfernung, {
    bool Function(Texturblock block, int stufe)? behalten,
  }) {
    if (_belegt <= hoechstensBytes) return;
    final liste = _stuecke.entries.toList()
      ..sort((a, b) {
        final d = entfernung(b.value.block).compareTo(
            entfernung(a.value.block));
        if (d != 0) return d;
        return b.value.stufe.compareTo(a.value.stufe);
      });
    for (final e in liste) {
      if (_belegt <= hoechstensBytes) break;
      if (behalten != null && behalten(e.value.block, e.value.stufe)) continue;
      _stuecke.remove(e.key);
      _belegt -= e.value.bytes;
      freigeben(e.value.inhalt);
    }
  }

  /// Gibt alles frei – beim Verlassen des Bildschirms.
  void leeren() {
    for (final x in _stuecke.values) {
      freigeben(x.inhalt);
    }
    _stuecke.clear();
    _belegt = 0;
  }
}

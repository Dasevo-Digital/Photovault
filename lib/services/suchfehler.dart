import '../l10n/app_localizations.dart';

/// Warum eine Suche nichts anzuzeigen hat.
///
/// **Ein Grund, kein Satz.** Beide Bildschirme setzten hier bisher den
/// fertig übersetzten Text – und zwar aus `initState` heraus, noch bevor
/// der Zweig zu Ende gebaut war. Flutter meldet das ausdrücklich: Wer
/// sich in `initState` auf einen vererbten Wert stützt, bekommt dessen
/// Änderungen nicht mit. Sichtbar wurde es beim Sprachwechsel — die
/// Meldung blieb in der alten Sprache stehen, weil sie nur beim Laden
/// entsteht. Der Grund dagegen ist sprachfrei und wird erst beim Zeichnen
/// zum Satz.
enum Suchfehler {
  /// Die Bilderkennung fehlt – ohne sie gibt es nichts zu vergleichen.
  clipFehlt,

  /// Etwas anderes ist schiefgegangen; [Suchfehlerstand.einzelheit] sagt was.
  gescheitert,
}

/// Der Grund samt Einzelheit.
class Suchfehlerstand {
  final Suchfehler grund;
  final String? einzelheit;
  const Suchfehlerstand(this.grund, [this.einzelheit]);

  /// Der Satz dazu, in der Sprache, die gerade gilt.
  String satz(AppTexte t) => switch (grund) {
        Suchfehler.clipFehlt => t.allgClipNoetigKurz,
        Suchfehler.gescheitert => t.allgSucheFehlgeschlagen(einzelheit ?? ''),
      };
}

/// Die Texte der Landschaft, auch ohne eingetragene Übersetzung.
library;

import 'package:flutter/widgets.dart';

import 'l10n/gelaende_texte.dart';

export 'l10n/gelaende_texte.dart';

/// Die Texte für [context].
///
/// Trägt die App [GelaendeTexte.delegate] ein, kommen sie von dort. Sonst
/// – in einem Test oder einer App, die es vergessen hat – in der Sprache
/// der Umgebung, Deutsch, wenn es die nicht gibt: Eine Landschaft ohne
/// Beschriftung ist besser als eine, die gar nicht aufgeht.
GelaendeTexte gelaendeTexte(BuildContext context) =>
    Localizations.of<GelaendeTexte>(context, GelaendeTexte) ??
    lookupGelaendeTexte(
      Localizations.maybeLocaleOf(context)?.languageCode == 'en'
          ? const Locale('en')
          : const Locale('de'),
    );

/// „12 Sekunden“, ab einer Minute „3 Minuten“ – für die Restzeit der
/// Videoausgabe.
String dauerText(GelaendeTexte t, Duration dauer) {
  final sekunden = dauer.inSeconds;
  if (sekunden < 60) {
    return t.restaurDauerSekunden(sekunden < 1 ? 1 : sekunden);
  }
  return t.restaurDauerMinuten(
    (dauer.inSeconds / 60).round().clamp(1, 1 << 30),
  );
}

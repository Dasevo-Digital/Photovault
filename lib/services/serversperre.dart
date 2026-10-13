import 'package:flutter/foundation.dart';

/// Ob [fehler] vom Sicherheitsnetz einer verbundenen Bibliothek kommt: Ein
/// Weg der App wollte an der Kopie vorbei schreiben (siehe
/// `Protokoll.richteSchutzEin` im Kern). Das ist kein Absturz, sondern
/// „geht verbunden noch nicht“.
bool istServersperre(Object fehler) =>
    '$fehler'.contains('pv_nur_ueber_server');

/// Zeigt die Meldung dazu in der Oberflächensprache; gesetzt von der
/// Oberfläche, die die Texte kennt (main.dart).
void Function()? meldeServersperre;

/// Fängt die Sperre überall ab, wo ein Fehler sonst ungefangen ankäme –
/// in Rückrufen der Oberfläche wie in Futures, auf die niemand wartet.
void richteServersperreEin() {
  final vorherFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    if (istServersperre(details.exception)) {
      meldeServersperre?.call();
      return;
    }
    vorherFlutter?.call(details);
  };
  final vorherPlattform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (fehler, spur) {
    if (istServersperre(fehler)) {
      meldeServersperre?.call();
      return true;
    }
    return vorherPlattform?.call(fehler, spur) ?? false;
  };
}

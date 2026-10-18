import 'dart:ui' show FontVariation;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Die mitgelieferte Zierschrift für die Schilder – EB Garamond.
///
/// Als Konstante und nicht als Zeichenkette an der Fundstelle: Ein
/// Schriftname im Quelltext sieht für den Wächter über feste Texte aus
/// wie ein deutscher Satz, den jemand zu übersetzen vergessen hat. Und
/// beim Umbenennen wäre eine der Fundstellen übrig geblieben.
const zierschrift = 'Zierschrift';

/// Die Schreibschrift für den Familiennamen unter dem Stamm – Great
/// Vibes. Nur dort: Bei dreizehn Punkten wäre sie nicht mehr zu lesen.
const zierschriftGross = 'Zierschrift Gross';

/// Das Gewicht auf einer **veränderlichen** Schrift.
///
/// EB Garamond kommt als eine Datei für alle Schnitte. `fontWeight`
/// allein bewegt deren `wght`-Achse nicht – Flutter würde stattdessen
/// einen künstlichen Fettdruck darüberlegen, und der sieht bei einer
/// Renaissance-Antiqua aus wie ein Druckfehler. Die Achse wird deshalb
/// ausdrücklich gesetzt.
List<FontVariation> zierGewicht(double wert) => [FontVariation('wght', wert)];

/// Trägt die Lizenzen der mitgelieferten Schriften in Flutters
/// Lizenzverzeichnis ein.
///
/// Die SIL Open Font License verlangt, dass ihr Text mitgeliefert wird.
/// Die Dateien liegen deshalb als Asset bei, und dieser Eintrag macht
/// sie über die Lizenzübersicht auch auffindbar – eine Datei im Paket,
/// die niemand sehen kann, erfüllt die Auflage dem Buchstaben nach und
/// dem Sinn nach nicht.
void zierschriftenLizenzenAnmelden() {
  LicenseRegistry.addLicense(() async* {
    for (final e in {
      'EB Garamond': 'assets/fonts/OFL-EBGaramond.txt',
      'Great Vibes': 'assets/fonts/OFL-GreatVibes.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        e.key,
      ], await rootBundle.loadString(e.value));
    }
  });
}

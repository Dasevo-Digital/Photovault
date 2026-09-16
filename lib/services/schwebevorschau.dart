/// **Wenn die Maus einen Augenblick stehen bleibt.**
///
/// Ein Video und ein Live Photo sind in einer Kachelwand nicht
/// voneinander zu unterscheiden – beide sind ein Standbild mit einem
/// kleinen Abzeichen. Was darin passiert, sieht man erst, wenn man es
/// öffnet. Bleibt die Maus einen Augenblick darauf stehen, läuft es hier
/// von selbst an.
///
/// **Warum die Entscheidung hier steht und nicht in der Kachel.** Sie ist
/// reine Rechnung: aus einem Datensatz wird eine Kennung oder nichts. So
/// lässt sie sich mit Zahlen prüfen, statt einen Zeiger über ein
/// gerendertes Raster führen zu müssen – dieselbe Trennung wie bei
/// [bildreihen] und dem Zeitstrahl.
library;

import '../db/rasterzeile.dart';

/// Wie lange die Maus stehen bleiben muss, bevor das Video anläuft.
///
/// Lang genug, dass ein Zeiger, der quer über die Wand fährt, keine Spur
/// von anlaufenden Videos hinter sich herzieht – bei 40 Kacheln in der
/// Breite wären das sonst 40 Startvorgänge in einer Sekunde.
///
/// **Und so kurz wie möglich, denn danach kommt noch etwas.** An echtem
/// Gerät gemessen (Linux, `integration_test/schwebevorschau_echt_test`):
///
/// ```
/// Abspieler erzeugen        15-30 ms
/// Datei öffnen bis Bild    300-490 ms   <- das ist libmpv
/// ```
///
/// Die Wartezeit hier und das Öffnen laufen nacheinander. Bei 450 ms
/// sah man das Video also erst nach reichlich achthundert Millisekunden
/// – da ist die Maus oft schon weiter. Bei 300 sind es rund siebenhundert.
///
/// **Drei Wege, das Öffnen zu verkürzen, wurden gemessen und verworfen:**
///
/// * Denselben Abspieler wiederverwenden, statt ihn je Vorschau neu
///   aufzubauen: 480–510 ms – nicht schneller, eher langsamer.
/// * `play: true` beim Öffnen, damit libmpv sofort dekodiert: kein
///   Unterschied.
/// * Die mpv-Stellschrauben `demuxer-lavf-probesize` (32 kB) und
///   `demuxer-lavf-analyzeduration` (0,1 s), einzeln und zusammen:
///
///   ```
///   ohne              356, 298, 482 ms
///   kleine Probe      482, 493, 462 ms
///   kurze Analyse     516, 548, 290 ms
///   beides            647, 290, 712 ms
///   ```
///
///   Keine Verbesserung, und die Streuung ist grösser als jeder
///   Unterschied. Die Zeit geht nicht in die Analyse der Datei, sondern
///   in das Dekodieren des ersten Bildes.
///
/// **Und eine Falle, die zwei Anläufe gekostet hat:**
/// `NativePlayer.setProperty` wartet standardmässig darauf, dass der
/// Abspieler fertig eingerichtet ist – der wird es aber erst beim ersten
/// `open()`. Vorher gerufen kehrt der Aufruf nie zurück, und der
/// Prüfstand hing wortlos. Der Ausweg heisst
/// `waitForInitialization: false`; erst damit kamen die Werte überhaupt
/// an, und erst damit war die Frage zu beantworten.
///
/// Gewartet wird auf die Bildmasse, und die kommen erst mit dem ersten
/// dekodierten Bild; die Dauer läge deutlich früher vor, nützt aber
/// nichts.
const Duration schwebeVerzoegerung = Duration(milliseconds: 300);

/// Welcher Datensatz das Video zu [asset] trägt – oder `null`, wenn es
/// keines gibt.
///
/// Drei Fälle:
/// * ein Video: es selbst,
/// * ein Live Photo (Standbild mit verknüpfter Hälfte): die Hälfte,
/// * alles andere: nichts.
///
/// **Der Tresor bleibt zu.** Eine gesperrte Aufnahme liegt verschlüsselt
/// auf der Platte; sie abzuspielen hiesse, sie vorher im Klartext
/// abzulegen – und das ausgerechnet nebenbei, weil ein Zeiger
/// vorbeikam. Wer ein gesperrtes Video sehen will, öffnet es (siehe
/// `LibraryState.decryptForViewing`).
String? schwebeVideoId(Rasterzeile asset) {
  if (asset.isLocked) return null;
  if (asset.type == 'VIDEO') return asset.id;
  if (asset.type == 'IMAGE' && asset.linkedAssetId != null) {
    return asset.linkedAssetId;
  }
  return null;
}

/// Ob die Schwebe-Vorschau eingeschaltet ist.
///
/// Als Wert für die ganze App und nicht je Bildschirm durchgereicht:
/// Die Einstellung steht in derselben Zeile, die `main.dart` ohnehin
/// beobachtet, und wird von dort gesetzt – genau wie der CARTO-Schlüssel
/// und die doppelte Kartenauflösung. So wirkt das Umlegen des Schalters
/// sofort und nicht erst beim nächsten Start.
bool get schwebevorschauAn => _an;
bool _an = true;

void setzeSchwebevorschau(bool an) => _an = an;

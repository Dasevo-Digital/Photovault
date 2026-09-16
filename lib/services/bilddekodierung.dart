import 'dart:io';

import 'package:flutter/widgets.dart';

/// Die Obergrenze, in der ein Foto zur Anzeige dekodiert wird.
///
/// **Warum es sie geben muss.** Eine Vorschaudatei entsteht nur für
/// Formate, die Flutter selbst nicht zeichnen kann – HEIC und RAW. In
/// einer echten Bibliothek waren das 1146 von 6930 Aufnahmen; die
/// übrigen **5784 werden im Original angezeigt**, und ein Original ist
/// so gross, wie die Kamera es gemacht hat. Die grösste dort misst
/// 20383 × 4077 Punkte. Als Bitmap im Speicher sind das **317 MB** – für
/// ein Bild, das auf einen Bildschirm von vielleicht 2000 Punkten Breite
/// gezeichnet wird.
///
/// 4096 ist keine gerechnete Grenze, sondern die, die die
/// Vollbildansicht seit jeher benutzt. Sie hier zu wiederholen wäre der
/// Fehler gewesen, den die 17. Prüfrunde gefunden hat: Drei weitere
/// Stellen zeigten dieselben Dateien ohne Deckel, weil die Zahl nur an
/// einer davon stand.
const maxDekodierKante = 4096;

/// **Was hier noch offen ist: der Bildschirm.**
///
/// Seit der Umstellung tragen Vorschau, Miniatur und Export ihren
/// Farbraum bei sich – Display P3, wo die Aufnahme mehr als sRGB hergibt.
/// Gezeichnet wird davon trotzdem in sRGB: Flutter rendert sein Fenster
/// auf allen drei Plattformen in sRGB, und daran ändert kein Profil in
/// der Datei etwas.
///
/// Der Unterschied ist damit dort behoben, wo die Datei weitergegeben
/// wird (Export, XMP-Beilage, fremde Programme), und bleibt dort offen,
/// wo sie angesehen wird. Das ist die kleinere Hälfte, aber es ist die
/// sichtbare – und sie kostet, anders als diese Umstellung, eine
/// Auseinandersetzung mit dem Fensterfarbraum aller drei Plattformen.

/// Ein Bild aus [datei], das höchstens [kante] Punkte je Seite belegt.
///
/// `fit` statt `exact`: Das Seitenverhältnis bleibt, die längere Kante
/// bestimmt. `allowUpscaling: false`, damit ein kleines Foto nicht
/// künstlich aufgeblasen wird – das kostete Speicher, ohne einen Punkt
/// mehr zu zeigen.
ImageProvider begrenztesBild(File datei, {int kante = maxDekodierKante}) =>
    ResizeImage(
      FileImage(datei),
      width: kante,
      height: kante,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );

/// Auf welche Stufen die Zielbreite eines Vorschaubildes gerundet wird.
///
/// **Warum überhaupt gerundet wird.** Ein Raster mit `maxCrossAxisExtent`
/// teilt den vorhandenen Platz gleichmässig auf – die Kachelbreite ist
/// damit eine Zahl, die sich mit **jedem** Punkt Fensterbreite ändert.
/// Aus `cacheWidth` wird so bei jedem Zwischenschritt eines Ziehens am
/// Fenster ein anderer Schlüssel im Bildspeicher: Jede sichtbare Kachel
/// wird neu dekodiert, und der Speicher füllt sich mit fast gleichen
/// Fassungen desselben Bildes.
///
/// Gemessen an einem Vorschaubild von 400 × 300 Punkten:
///
/// ```
/// ein Dekodiervorgang auf 148 Punkte      0,68 ms, 65.712 Bytes
/// Fensterbreiten 1000..1400 Punkte    ->  21 verschiedene Zielbreiten
/// dieselben, auf 32 gerundet          ->   1
/// ```
///
/// Bei fünfzig sichtbaren Kacheln sind das 21 × 50 × 0,68 ms ≈ 0,7
/// Sekunden Dekodierarbeit für ein einziges Ziehen am Fensterrand – und
/// einundzwanzig Einträge je Foto in einem Speicher, der insgesamt 100 MB
/// fasst.
const int dekodierstufe = 32;

/// Die Zielbreite in Bildpunkten für etwas, das [punkte] Punkte breit
/// angezeigt wird.
///
/// **Aufgerundet, nie abgerundet.** Eine Stufe zu klein hiesse, ein Bild
/// hochskaliert anzuzeigen – sichtbar unscharf. Der Preis der Rundung ist
/// höchstens eine Stufe zu viel an Pixeln.
int dekodierbreite(double punkte, double pixelverhaeltnis) {
  if (!punkte.isFinite || punkte <= 0) return dekodierstufe;
  final roh = punkte * pixelverhaeltnis;
  return (roh / dekodierstufe).ceil() * dekodierstufe;
}

/// Die Dekodiergrösse für ein Bild, das mit [BoxFit.cover] in eine
/// Fläche gezeichnet wird – **genau eine** der beiden Kanten.
///
/// **Warum nicht beide.** `cacheWidth` und `cacheHeight` zusammen heissen
/// für Flutter: dekodiere auf genau diese Masse. Das Seitenverhältnis
/// bleibt dabei nicht erhalten – es wird gestaucht. Gemessen an echten
/// Vorschaubildern, Kachel 160 Punkte bei doppelter Pixeldichte:
///
/// ```
/// Quelle     Ziel      dekodiert   Verhältnis
/// 400x300    320x320   320x300     1,33 -> 1,07
/// 225x400    320x320   225x320     0,56 -> 0,70
/// ```
///
/// Ein Kreis im Foto wird so zur Ellipse, und `BoxFit.cover` merkt davon
/// nichts: Es bekommt ein Bild, dessen Verhältnis schon falsch ist, und
/// füllt damit brav die Kachel. **Alle quadratischen Kacheln der App
/// haben ihre Fotos gestaucht gezeigt** – Zeitleiste, Kartenmarker,
/// Filmstreifen im Betrachter.
///
/// **Welche Kante bindet.** Bei `cover` bestimmt die Kante, an der das
/// Bild relativ am knappsten ist: Ist `kachelBreite/bildBreite` grösser
/// als `kachelHöhe/bildHöhe`, muss die Breite passen und die Höhe fällt
/// von selbst gross genug aus – sonst umgekehrt. Die andere Kante bleibt
/// offen, und damit bleibt das Verhältnis erhalten.
///
/// Sind die Masse unbekannt (2 von 8098 Aufnahmen), wird **gar nichts**
/// begrenzt. Ohne das Verhältnis lässt sich die bindende Kante nicht
/// bestimmen, und eine geratene wäre entweder unscharf oder wieder
/// verzerrt. Der Preis ist ein Vorschaubild in voller Grösse – bei 400
/// Punkten Kantenlänge höchstens 640 kB.
///
/// **Richtig ist teurer.** Eine quadratische Kachel dekodiert das
/// Vorschaubild jetzt in voller Höhe statt gestaucht; eine
/// Bildschirmfüllung der Zeitleiste stieg dadurch von 54,8 auf 68,4 MB
/// (doppelte Pixeldichte, gemessen an der echten Bibliothek). Das ist
/// keine Verschwendung, sondern das, was ein unverzerrtes Bild kostet.
({int? breite, int? hoehe}) deckendeDekodiermasse({
  required double kachelBreite,
  required double kachelHoehe,
  required int? bildBreite,
  required int? bildHoehe,
  required double pixelverhaeltnis,
}) {
  if (bildBreite == null || bildHoehe == null ||
      bildBreite <= 0 || bildHoehe <= 0) {
    return (breite: null, hoehe: null);
  }
  final breiteEndlich = kachelBreite.isFinite && kachelBreite > 0;
  final hoeheEndlich = kachelHoehe.isFinite && kachelHoehe > 0;
  if (!breiteEndlich && !hoeheEndlich) return (breite: null, hoehe: null);
  // Nur eine Kante begrenzt: Dann ist sie die bindende, ob sie es
  // rechnerisch waere oder nicht - die andere ist gar nicht bekannt.
  if (!hoeheEndlich) {
    return (breite: dekodierbreite(kachelBreite, pixelverhaeltnis), hoehe: null);
  }
  if (!breiteEndlich) {
    return (breite: null, hoehe: dekodierbreite(kachelHoehe, pixelverhaeltnis));
  }
  return kachelBreite / bildBreite >= kachelHoehe / bildHoehe
      ? (breite: dekodierbreite(kachelBreite, pixelverhaeltnis), hoehe: null)
      : (breite: null, hoehe: dekodierbreite(kachelHoehe, pixelverhaeltnis));
}

/// Die Formate, die Flutter selbst dekodiert.
///
/// Gebraucht dort, wo eine **beliebige** Datei aus der Bibliothek
/// angezeigt werden soll und nicht feststeht, ob es überhaupt ein Bild
/// ist – die Integritätsprüfung etwa hält eine verwaiste Datei in den
/// Händen und kennt nur ihren Pfad. HEIC und RAW sind nicht dabei: Dort
/// bliebe ein leeres Feld stehen, und ein leeres Feld sagt weniger als
/// kein Feld.
const flutterDekodierbareEndungen = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
];

/// Ob Flutter diese Datei nach ihrer Endung anzeigen kann.
bool flutterKannAnzeigen(String pfad) {
  final punkt = pfad.lastIndexOf('.');
  if (punkt < 0) return false;
  return flutterDekodierbareEndungen.contains(pfad.substring(punkt).toLowerCase());
}

/// Stellt den Bildspeicher auf eine Bibliothek in Bildschirmgrösse ein.
///
/// **Flutters Vorgabe war nie angefasst worden:** 1000 Bilder und 100 MB.
/// Für eine Kachelwand auf einem Bildschirm mit doppelter Pixeldichte ist
/// das ungefähr eine Bildschirmfüllung – ein 160-Punkt-Quadrat braucht
/// dort 320 Bildpunkte, und weil ein Vorschaubild nur 400 misst, wird es
/// fast in voller Grösse dekodiert. Gemessen an der echten Bibliothek
/// (7307 Aufnahmen, Fenster 1600 × 1000, doppelte Pixeldichte):
///
/// ```
/// Grenze    erstes Bild verdrängt ab Bildschirm    Arbeitsspeicher
///           Quadrate        Reihen
/// 100 MB       3               4                      544 MB
/// 200 MB       7              10                      653 MB
/// 300 MB      11              nie                     733 MB
/// ```
///
/// Drei Bildschirme sind zu wenig: So weit scrollt man in einer
/// Zeitleiste beiläufig, und der Weg zurück kostet dann eine neue
/// Dekodierung von siebzig Bildern – gemessen **210 bis 260 ms**, in
/// denen die Kacheln leer stehen.
///
/// **200 MB und nicht 300.** Die ersten hundert Megabyte kaufen vier
/// zusätzliche Bildschirme, die zweiten nur noch vier weitere – und
/// kosten dieselben hundert Megabyte. Mehr Speicher ist kein Selbstzweck.
///
/// **Warum die Bilderzahl mitwächst.** Bei einfacher Pixeldichte ist ein
/// Eintrag klein (gemessen 140 kB), und dann war die Zahl 1000 die
/// bindende Grenze – bei 144 MB, also lange vor dem Deckel. Damit
/// entschied die Zahl der Bilder statt ihrer Grösse. Jetzt entscheiden
/// die Megabyte.
///
/// **Kein Rückweg über Speicherdruck.** Auf den drei Plattformen dieser
/// App schickt die Maschine keine `didHaveMemoryPressure`-Meldung; was
/// hier steht, ist also eine feste Obergrenze und keine, die im Notfall
/// nachgibt. Deshalb eine gemessene Zahl und keine grosszügige.
void bildspeicherEinrichten() {
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 200 * 1024 * 1024
    ..maximumSize = 3000;
}

/// Vergisst alle zwischengespeicherten Bilder.
///
/// **Wozu.** Flutter merkt sich dekodierte Bilder unter einem Schlüssel
/// aus Datei und Zielgrösse. Wer ein Foto **an Ort und Stelle**
/// überschreibt – Bearbeiten speichert ein gedrehtes JPEG unter genau
/// demselben Pfad, und Vorschau und Vorschaubild werden ebenso ersetzt –,
/// ändert die Datei, nicht den Schlüssel. Danach zeigen Vollbild,
/// Zeitleiste und jede Kachel weiter das alte Bild, bis die App neu
/// startet. Gemeldet als „Vorschau nach dem Speichern nicht aktualisiert".
///
/// **Warum alles und nicht gezielt.** Ein Bild liegt unter so vielen
/// Schlüsseln im Speicher, wie es Kachelgrössen gibt, unter denen es
/// gezeichnet wurde (siehe [dekodierbreite]) – und der Speicher lässt
/// sich nicht danach durchsuchen. Alles zu verwerfen kostet einmal das
/// erneute Dekodieren der sichtbaren Kacheln; einen Schlüssel zu
/// übersehen kostet ein falsches Bild, das niemand als Fehler erkennt.
///
/// `clearLiveImages` gehört dazu: Bilder, die gerade gezeichnet werden,
/// liegen in einer zweiten Liste, die `clear` nicht anfasst – ohne sie
/// bliebe ausgerechnet das Bild stehen, auf das man sieht.
///
/// Ohne laufende Zeichenmaschine passiert nichts: Aufrufer sind seit der
/// 23. Prüfrunde auch Wege ohne Oberfläche (Sperren, Aufräumen des
/// Entschlüsselungs-Zwischenspeichers), und die laufen in reinen
/// Sachtests ohne Bindung.
void vergissAlleBilder() {
  try {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  } on FlutterError {
    // Keine Zeichenmaschine, also auch kein Bildspeicher.
  }
}

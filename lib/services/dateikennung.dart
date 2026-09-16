/// Erkennt das Bildformat an den ersten Bytes einer Datei statt an ihrem
/// Namen.
///
/// **Der Anlass steht in der Bibliothek.** Genau eine von 7.370 Aufnahmen
/// heisst `FullSizeRender - Kopie.jpg` und **ist eine HEIC-Datei**
/// (3022x3351, `sips` liest sie anstandslos). Weil die App das Format
/// bis dahin ausschliesslich an der Endung ablas, lief sie in die
/// falsche Abzweigung: keine native Umwandlung, `package:image` scheitert
/// an HEIC-Bytes, also kein Vorschaubild, keine Breite, keine Höhe – und
/// die KI-Warteschlange stolperte bei jedem Programmstart erneut über
/// dasselbe Foto.
///
/// Eine Endung ist eine Behauptung des Dateinamens. Die ersten Bytes sind
/// die Datei selbst.
///
/// **Bewusst unvollständig.** Erkannt wird, was sich an einer kurzen,
/// eindeutigen Bytefolge festmachen lässt. TIFF steht ausdrücklich
/// **nicht** dabei: `II*\0` bzw. `MM\0*` am Anfang haben auch CR2, NEF,
/// ARW, DNG und die meisten anderen Hersteller-RAWs – aus diesen vier
/// Bytes „TIFF" zu schliessen hiesse, jede RAW-Datei falsch zu benennen.
/// Wo nichts sicher ist, kommt `null` zurück, und der Aufrufer bleibt bei
/// der Endung. Ein falsches Format wäre schlimmer als gar keines.
library;

/// Wie viele Bytes vom Anfang [kennungAus] höchstens braucht.
///
/// Zwölf: vier Länge, `ftyp`, vier Marke – die ISO-BMFF-Familie
/// (HEIC/AVIF) ist der längste Fall.
const kennungBytes = 12;

/// Das Bildformat, das [kopf] behauptet – als Endung **mit** Punkt,
/// damit es sich unmittelbar gegen `heicAndRawExtensions` und Konsorten
/// prüfen lässt.
///
/// `null`, wenn die Bytes zu keiner der bekannten Signaturen passen oder
/// gar nicht erst so viele da sind.
String? kennungAus(List<int> kopf) {
  if (kopf.length < 4) return null;

  // JPEG: SOI (FFD8) plus der erste Marker – FFD8 allein käme auch am
  // Anfang mancher Rohdaten vor.
  if (kopf[0] == 0xFF && kopf[1] == 0xD8 && kopf[2] == 0xFF) return '.jpg';

  // PNG: der Signaturblock, der absichtlich so gebaut ist, dass ihn eine
  // Textübertragung zerstört.
  if (_gleich(
      kopf, 0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return '.png';
  }

  if (_text(kopf, 0, 'GIF8')) return '.gif';

  // BMP: „BM". Nur zwei Bytes und damit die schwächste Signatur hier –
  // sie steht deshalb hinter allen längeren.
  if (kopf[0] == 0x42 && kopf[1] == 0x4D) return '.bmp';

  // RIFF-Container; erst die Form dahinter macht daraus WebP.
  if (_text(kopf, 0, 'RIFF') && _text(kopf, 8, 'WEBP')) return '.webp';

  // ISO-BMFF: `ftyp` steht an Position 4, davor die Kastenlänge. Die
  // Marke dahinter entscheidet, ob es ein Bild ist und welches.
  if (_text(kopf, 4, 'ftyp')) return _bmff(_marke(kopf));

  return null;
}

/// Die vier Zeichen der Marke (`major_brand`) eines ISO-BMFF-Kastens.
String _marke(List<int> kopf) {
  if (kopf.length < 12) return '';
  return String.fromCharCodes(kopf.sublist(8, 12));
}

/// Was eine ISO-BMFF-Marke für uns bedeutet.
///
/// Derselbe Kasten trägt Fotos, Filme und Bildfolgen. `mp4`/`qt`/`isom`
/// gehören zu Videos und sind hier **nicht** aufgeführt: Diese Funktion
/// beantwortet die Frage „welches Bildformat", und ein Video ist die
/// Antwort auf eine andere Frage. `null` heisst darum auch hier: nicht
/// zuständig, bleib bei der Endung.
String? _bmff(String marke) => switch (marke) {
      // Einzelbild, Bildfolge, sowie die beiden Sammelmarken, mit denen
      // Apple seine Fotos auszeichnet.
      'heic' || 'heix' || 'heim' || 'heis' => '.heic',
      'hevc' || 'hevx' || 'hevm' || 'hevs' => '.heic',
      'mif1' || 'msf1' => '.heic',
      'avif' || 'avis' => '.avif',
      // Canons neueres RAW-Format steckt im selben Kasten wie ein Film.
      // Die Marke ist eindeutig – anders als bei den TIFF-RAWs oben lässt
      // sich CR3 also sicher an den Bytes erkennen.
      'crx ' => '.cr3',
      _ => null,
    };

bool _gleich(List<int> kopf, int ab, List<int> muster) {
  if (kopf.length < ab + muster.length) return false;
  for (var i = 0; i < muster.length; i++) {
    if (kopf[ab + i] != muster[i]) return false;
  }
  return true;
}

bool _text(List<int> kopf, int ab, String muster) =>
    _gleich(kopf, ab, muster.codeUnits);

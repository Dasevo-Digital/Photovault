import 'exif_camera.dart';

/// Aufnahmewerte einer Datei samt Aufnahmezeitpunkt.
///
/// [CameraInfo] allein reicht hier nicht: Bei Formaten, die `package:exif`
/// nicht lesen kann, fehlt auch das Datum – und das ist der teurere
/// Schaden, weil es bestimmt, wo ein Foto in der Zeitleiste und auf der
/// Platte landet.
class Aufnahmedaten {
  final CameraInfo kamera;
  final DateTime? zeitpunkt;

  const Aufnahmedaten(this.kamera, this.zeitpunkt);

  static const leer = Aufnahmedaten(CameraInfo(), null);

  bool get isEmpty => kamera.isEmpty && zeitpunkt == null;
}

/// Liest die Ausgabe von `raw-identify -v` (LibRaw).
///
/// Warum ein eigener Parser statt `package:exif`: CR3 ist ein
/// ISO-BMFF-Container wie MP4, kein TIFF – `package:exif` liefert dort
/// nachweislich NULL Tags. Unter macOS springt ImageIO ein, unter Linux
/// und Windows gibt es nur LibRaw, und dessen einziges Ausgabeformat ist
/// dieser Text.
///
/// Reine Funktion, damit sie ohne installiertes Werkzeug prüfbar ist
/// (siehe test/raw_identify_parser_test.dart).
Aufnahmedaten parseRawIdentify(String ausgabe) {
  String? feld(String name) {
    // Zeilenanfang ODER nach einem Tabulator: Die Abschnitte „EXIF:" und
    // „Makernotes:" rücken ihre Zeilen ein.
    final treffer = RegExp('^[\\t ]*${RegExp.escape(name)}:[\\t ]*(.*)\$',
            multiLine: true)
        .firstMatch(ausgabe);
    final wert = treffer?.group(1)?.trim();
    return (wert == null || wert.isEmpty) ? null : wert;
  }

  double? zahlAus(String? text) {
    if (text == null) return null;
    final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(text);
    if (m == null) return null;
    return double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  // „Camera: Canon EOS R10 ID: 0x80000465" – die Kennung hinten abschneiden.
  // Bewusst diese Zeile und nicht „Normalized Make/Model": Letztere liefert
  // „EOS R10" ohne Hersteller, ImageIO auf macOS dagegen „Canon EOS R10".
  // Zwei Plattformen, die dieselbe Kamera unterschiedlich benennen, würden
  // Kamera-Presets und die Kameraliste auseinanderlaufen lassen.
  String? modell = feld('Camera');
  if (modell != null) {
    final schnitt = modell.indexOf(RegExp(r'\s+ID:\s'));
    if (schnitt > 0) modell = modell.substring(0, schnitt).trim();
    if (modell.isEmpty) modell = null;
  }

  // „Normalized Make/Model: =Canon/EOS R10= CamMaker ID: 8"
  String? hersteller;
  final norm = RegExp(r'Normalized Make/Model:\s*=([^/]*)/').firstMatch(ausgabe);
  if (norm != null) {
    final h = norm.group(1)!.trim();
    if (h.isNotEmpty) hersteller = h;
  }

  // Objektiv: Die EXIF-Fassung zuerst. Der Abschnitt „Makernotes" führt
  // dieselbe Angabe oft mit abweichender Schreibweise („EF 50mm" gegen
  // „EF50mm"); EXIF ist das, was auch ImageIO liefert.
  final objektivEx = RegExp(r'^EXIF:$(.*?)^\S', multiLine: true, dotAll: true)
      .firstMatch(ausgabe);
  String? objektiv;
  if (objektivEx != null) {
    objektiv = RegExp(r'^[\t ]*Lens:[\t ]*(.*)$', multiLine: true)
        .firstMatch(objektivEx.group(1)!)
        ?.group(1)
        ?.trim();
  }
  objektiv ??= feld('Lens');
  if (objektiv != null && objektiv.isEmpty) objektiv = null;

  // „Shutter: 1/100.0" oder „Shutter: 2.0 sec"
  double? belichtung;
  final sh = feld('Shutter');
  if (sh != null) {
    final bruch = RegExp(r'1/(\d+(?:\.\d+)?)').firstMatch(sh);
    belichtung =
        bruch != null ? 1.0 / double.parse(bruch.group(1)!) : zahlAus(sh);
  }

  // „FocalLengthIn35mmFormat: 0 mm" heisst „nicht überliefert", nicht „0 mm".
  final kb = zahlAus(feld('FocalLengthIn35mmFormat'));

  return Aufnahmedaten(
    CameraInfo(
      make: hersteller,
      model: modell,
      lensModel: objektiv,
      focalLengthMm: zahlAus(feld('Focal length')) ?? zahlAus(feld('CurFocal')),
      fNumber: zahlAus(feld('Aperture')),
      iso: zahlAus(feld('ISO speed'))?.round(),
      exposureTimeSeconds: belichtung,
      // raw-identify gibt keine Belichtungskorrektur aus – nur eine
      // Blitzkorrektur, die etwas anderes ist. Bleibt hier leer, statt sie
      // zu verwechseln.
      exposureBiasEv: null,
      focalLength35mm: (kb == null || kb == 0) ? null : kb,
    ),
    _zeitstempel(feld('Timestamp')),
  );
}

const _monate = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};

/// „Fri Aug 19 19:19:28 2022" – das Format von `ctime`.
///
/// Von Hand statt über `DateFormat`: Die Monatsnamen stehen dort immer
/// englisch, `intl` würde sie nach der eingestellten Sprache erwarten.
DateTime? _zeitstempel(String? text) {
  if (text == null) return null;
  final m = RegExp(r'^\w{3}\s+(\w{3})\s+(\d{1,2})\s+'
          r'(\d{2}):(\d{2}):(\d{2})\s+(\d{4})$')
      .firstMatch(text.trim());
  if (m == null) return null;
  final monat = _monate[m.group(1)];
  if (monat == null) return null;
  final jahr = int.parse(m.group(6)!);
  // LibRaw setzt bei fehlendem Datum 0 ein, und `ctime` macht daraus den
  // 1.1.1970. Als Aufnahmezeitpunkt waere das schlimmer als gar keiner: Er
  // sortierte das Foto an den Anfang der Zeitleiste. RAW-Dateien stammen
  // aus Digitalkameras, die es 1990 noch nicht gab – alles darunter ist
  // kein Datum, sondern ein fehlendes.
  if (jahr < 1990) return null;
  return DateTime(jahr, monat, int.parse(m.group(2)!), int.parse(m.group(3)!),
      int.parse(m.group(4)!), int.parse(m.group(5)!));
}

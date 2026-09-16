/// Liest den Aufnahmeort aus einem Video.
///
/// **Der Anlass.** In der Prüfbibliothek liegen 440 Videos. Keines trug
/// einen Ort in der Datenbank – **43 von 60 zufällig geprüften trugen
/// einen in der Datei**. Hochgerechnet rund 315 Orte, die nie ankamen:
/// unsichtbar für Karte, Globus, Reisen, Aktivitäten und Länderzähler.
///
/// Es ist derselbe Fund wie bei den CR3-Dateien (dort 522) und dieselbe
/// Ursache: `ImportService.readGpsLocation` geht über `package:exif`, und
/// das liest weder MOV noch MP4. Beide sind ISO-BMFF – derselbe Container
/// wie CR3 –, der Kastenlauf dafür steht seither im Projekt
/// (siehe [kastenAusDatei]).
///
/// **Zwei Ablagen, beide kommen vor.** An den echten Dateien nachgesehen:
///
/// ```
/// Telefon (.mov)   moov / meta / keys + ilst
///                  Schlüssel „com.apple.quicktime.location.ISO6709"
///                  Wert     „+52.2375+010.5955+081.205/"
///
/// Drohne  (.mp4)   moov / udta / ©xyz
///                  Wert     „+52.2375+10.5738"
///
/// Kamera  (.mp4)   moov / udta / loci
///                  Zahlen, kein Text – und LÄNGE VOR BREITE
/// ```
///
/// Die ersten beiden sind ISO 6709, dasselbe Format verschieden abgelegt.
/// Der dritte ist der 3GPP-Kasten `loci` mit Festkommazahlen. Alle drei
/// kommen in derselben Bibliothek vor; wer nur den ersten liest, verliert
/// die anderen still.
library;

import 'dart:io';
import 'dart:typed_data';

import 'isobmff.dart';

/// Der Schlüssel, unter dem Apple den Ort ablegt.
const _appleOrtsschluessel = 'com.apple.quicktime.location.ISO6709';

/// Das Atom, in dem QuickTime und Android den Ort als Text ablegen.
///
/// Das erste Zeichen ist U+00A9 („©"), nicht das Wort „xyz" mit einem
/// Zeichen davor: Alle klassischen QuickTime-Anmerkungen beginnen so.
const _xyzAtom = '©xyz';

/// Breite und Länge aus einer ISO-6709-Zeichenkette.
///
/// Das Format ist ein Vorzeichen, eine Zahl, wieder ein Vorzeichen, wieder
/// eine Zahl – und danach beliebig viel Weiteres (Höhe, ein Bezugssystem
/// in Klammern, ein abschliessender Schrägstrich). Genommen werden die
/// **ersten beiden** vorzeichenbehafteten Zahlen; die dritte ist die Höhe
/// und geht hier niemanden etwas an.
///
/// `null`, wenn nichts Deutbares dasteht oder die Werte ausserhalb des
/// Möglichen liegen. Ein Ort auf 0/0 wird ebenfalls verworfen: Das ist der
/// Punkt im Atlantik, den Geräte melden, wenn sie nichts wissen.
({double breite, double laenge})? iso6709Deuten(String text) {
  final treffer = RegExp(r'([+-]\d+(?:\.\d+)?)').allMatches(text).toList();
  if (treffer.length < 2) return null;
  final breite = double.tryParse(treffer[0].group(1)!);
  final laenge = double.tryParse(treffer[1].group(1)!);
  if (breite == null || laenge == null) return null;
  if (breite.abs() > 90 || laenge.abs() > 180) return null;
  if (breite == 0 && laenge == 0) return null;
  return (breite: breite, laenge: laenge);
}

/// Der Ort aus einem bereits gelesenen `moov`-Kasten.
///
/// Rein und ohne Datei, damit sich beide Ablagen an gebauten Bytes prüfen
/// lassen, statt an einer 1,7-GB-Aufnahme.
({double breite, double laenge})? ortAusMoov(Uint8List moov) {
  return _ausAppleSchluesseln(moov) ?? _ausXyzAtom(moov) ?? _ausLoci(moov);
}

/// Apples Weg: der Ort steht als ISO-6709-Text unter einem Schlüssel in
/// `moov/meta/keys+ilst` – siehe [appleSchluesselwert] für die beiden
/// Listen und die Nummer, die sie verbindet.
({double breite, double laenge})? _ausAppleSchluesseln(Uint8List moov) {
  final wert = appleSchluesselwert(moov, _appleOrtsschluessel);
  return wert == null ? null : iso6709Deuten(wert);
}

/// Der klassische Weg: `moov/udta/©xyz` mit zwei Byte Länge, zwei Byte
/// Sprache und danach dem Text.
({double breite, double laenge})? _ausXyzAtom(Uint8List moov) {
  final text = udtaAnmerkung(moov, _xyzAtom);
  return text == null ? null : iso6709Deuten(text);
}

/// Der 3GPP-Kasten `loci` (Location Information).
///
/// Aufbau: vier Byte Fassung und Flaggen, zwei Byte Sprache, ein
/// nullterminierter Name, ein Byte Rolle, dann **Länge, Breite, Höhe** als
/// vorzeichenbehaftete 16.16-Festkommazahlen.
///
/// **Die Länge steht vor der Breite.** Wer die gewohnte Reihenfolge
/// annimmt, bekommt einen Ort, der plausibel aussieht und in einem anderen
/// Land liegt – aus 52,4 N / 10,8 O würde 10,8 N / 52,4 O, mitten im
/// Indischen Ozean. Genau deshalb steht es hier so ausdrücklich.
({double breite, double laenge})? _ausLoci(Uint8List moov) {
  final loci = sucheKasten(moov, 0, moov.length, 'loci',
      absteigenIn: const {'moov', 'udta', 'meta'});
  if (loci == null) return null;
  var p = loci.inhaltVon + 6;
  // Über den Namen hinweg bis zur abschliessenden Null.
  while (p < loci.inhaltBis && moov[p] != 0) {
    p++;
  }
  p += 2; // die Null und das Rollenbyte
  if (p + 8 > loci.inhaltBis) return null;
  final d = ByteData.sublistView(moov);
  final laenge = d.getInt32(p) / 65536.0;
  final breite = d.getInt32(p + 4) / 65536.0;
  if (breite.abs() > 90 || laenge.abs() > 180) return null;
  if (breite == 0 && laenge == 0) return null;
  return (breite: breite, laenge: laenge);
}

/// Der Aufnahmeort aus [datei], oder `null`.
///
/// Liest nur den `moov`-Kasten. Bei Videos steht der oft **hinter** den
/// Rohdaten – an einer 1,7-GB-Datei sind das trotzdem drei Sprünge und
/// vierzig Kilobyte, nicht 1,7 GB.
Future<({double breite, double laenge})?> leseVideoGps(File datei) async {
  final moov = await kastenAusDatei(datei, 'moov');
  return moov == null ? null : ortAusMoov(moov);
}

/// Aufnahmezeitpunkt und Kamera aus einem Video.
///
/// **Der Anlass.** An der echten Bibliothek nachgerechnet: von 440 Videos
/// tragen **339 einen Aufnahmezeitpunkt in der Datei** – und **kein
/// einziges** trug den richtigen in der Datenbank. Der Import kennt für
/// Videos keinen Metadatenleser und fällt auf den Zeitstempel der Datei
/// zurück (`sourceFile.lastModified()`); der ist nach jedem Kopieren,
/// Sichern und Zurückholen der Zeitpunkt dieses Vorgangs. 196 Videos lagen
/// dadurch um mehr als einen Tag daneben, das älteste um zwölf Jahre.
///
/// Es ist dieselbe Krankheit wie beim Ort (siehe [leseVideoGps]) und bei
/// CR3 – und dieselbe Ursache: `package:exif` liest nur TIFF und JPEG.
///
/// **Drei Ablagen, in dieser Reihenfolge.**
///
/// ```
/// 1  moov/meta/keys+ilst   com.apple.quicktime.creationdate
///                          „2025-09-20T11:50:21+0200"  – Ortszeit MIT Zone
/// 2  moov/udta/©day        ISO 8601, meist ebenfalls mit Zone
/// 3  moov/mvhd             Sekunden seit 1904-01-01, ohne jede Zone
/// ```
///
/// **Die Zeitzone ist der ganze Punkt.** Der `mvhd`-Kasten soll laut Norm
/// UTC tragen, und Apple hält sich daran: dasselbe Video meldete dort
/// 09:50:21 und unter `creationdate` 11:50:21+02:00. Wer `mvhd` für
/// Ortszeit hält, datiert jede Sommeraufnahme zwei Stunden zu früh – und
/// alles vor 02:00 Uhr auf den falschen Tag.
///
/// Nur hält sich längst nicht jeder daran. An 28 Videos dieser Bibliothek,
/// die eine **GPS-Zeit** tragen (die ist immer UTC und damit ein
/// unbestechlicher Schiedsrichter), lag `mvhd` **durchweg vor** der
/// GPS-Zeit: zwölfmal +2 h, neunmal +1 h, sechsmal −1 h, einmal +3 h. Also
/// Ortszeit, nicht UTC – bei Aufnahmen, die durch eine Bearbeitung
/// gegangen sind, ebenso wie bei Canon und Olympus.
///
/// Deshalb: Wo Apple seinen Schlüssel schreibt, gilt der und die Frage
/// stellt sich nicht (228 der 440). Wo nur `mvhd` dasteht, wird er als
/// **Ortszeit** gelesen – das ist die Lesart, die hier gemessen häufiger
/// zutrifft. Ein Video, das seine Zone nirgends nennt, lässt sich nicht
/// besser datieren als bis auf die Zonenverschiebung genau; wer es exakt
/// braucht, muss das Datum von Hand setzen.
library;

import 'dart:io';
import 'dart:typed_data';

import 'isobmff.dart';
import 'video_gps.dart';

/// Apples Schlüssel für den Aufnahmezeitpunkt – Ortszeit samt Zone.
const _appleZeitschluessel = 'com.apple.quicktime.creationdate';

/// Apples Schlüssel für Hersteller und Gerät.
const _appleHerstellerschluessel = 'com.apple.quicktime.make';
const _appleGeraeteschluessel = 'com.apple.quicktime.model';

/// Der Beginn der QuickTime-Zeitrechnung: 1904-01-01 00:00:00 UTC.
///
/// Nicht 1970. Ein Video von 2013 kommt sonst im Jahr 1947 heraus, und das
/// sieht plausibel genug aus, um niemandem aufzufallen.
final DateTime _quicktimeNull = DateTime.utc(1904);

/// Woher der gefundene Zeitpunkt stammt – entscheidet, wie sicher er ist.
enum Zeitherkunft {
  /// Aus einem Feld **mit** Zonenangabe. Auf die Sekunde richtig.
  mitZone,

  /// Aus `mvhd`, also ohne Zonenangabe. Auf die Zonenverschiebung genau.
  ohneZone,
}

typedef Videozeit = ({DateTime zeitpunkt, Zeitherkunft herkunft});

/// Der Aufnahmezeitpunkt aus einem bereits gelesenen `moov`-Kasten.
///
/// Rein und ohne Datei, damit sich alle drei Ablagen an gebauten Bytes
/// prüfen lassen statt an einer 1,7-GB-Aufnahme.
Videozeit? zeitAusMoov(Uint8List moov) {
  final apple = _ausZonentext(appleSchluesselwert(moov, _appleZeitschluessel));
  if (apple != null) return (zeitpunkt: apple, herkunft: Zeitherkunft.mitZone);

  final day = _ausZonentext(udtaAnmerkung(moov, '©day'));
  if (day != null) return (zeitpunkt: day, herkunft: Zeitherkunft.ohneZone);

  final mvhd = _ausMvhd(moov);
  return mvhd == null ? null : (zeitpunkt: mvhd, herkunft: Zeitherkunft.ohneZone);
}

/// Hersteller und Gerät aus einem `moov`-Kasten.
///
/// Zwei Ablagen: Apples Schlüsselliste (in dieser Bibliothek 228 von 440)
/// und die klassischen Anmerkungsatome `©mak`/`©mod` (weitere acht). Die
/// restlichen Videos tragen ihre Kameraangabe in einem
/// Hersteller-Block (Canon `CNTH`, Olympus) – der ist je Hersteller
/// verschieden und bleibt hier bewusst aussen vor.
({String? hersteller, String? geraet}) kameraAusMoov(Uint8List moov) {
  String? sauber(String? s) {
    // Nur aussen kürzen, nicht innen. Ein replaceAll(' ', '') machte aus
    // „Canon PowerShot A3350 IS“ ein „CanonPowerShotA3350IS“ – die
    // Kameraliste in den Werkzeugen zeigte dann ein zweites, unbekanntes
    // Gerät neben demselben aus den Fotos derselben Kamera.
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  return (
    hersteller: sauber(appleSchluesselwert(moov, _appleHerstellerschluessel)) ??
        sauber(udtaAnmerkung(moov, '©mak')),
    geraet: sauber(appleSchluesselwert(moov, _appleGeraeteschluessel)) ??
        sauber(udtaAnmerkung(moov, '©mod')),
  );
}

/// Ein Zeitpunkt aus einem ISO-8601-Text **mit** Zonenangabe, umgerechnet
/// in die Ortszeit dieses Rechners.
///
/// Apple schreibt `2025-09-20T11:50:21+0200` – vierstellige Zone ohne
/// Doppelpunkt, die `DateTime.parse` nicht annimmt. Ein Doppelpunkt wird
/// deshalb eingesetzt, bevor gefragt wird.
///
/// Ohne Zonenangabe wird **nichts** zurückgegeben: Der Aufrufer soll dann
/// den nächsten Weg gehen, statt eine Ortszeit zu bekommen, die vielleicht
/// UTC ist.
DateTime? _ausZonentext(String? roh) {
  if (roh == null) return null;
  // Ohne Leerzeichen: Manche Schreiber setzen eines vor die Zone.
  final text = roh.trim().replaceAll(' ', '');
  if (text.isEmpty) return null;
  final mitZone = RegExp(r'([+-])(\d{2})(\d{2})$').firstMatch(text);
  final normiert = mitZone == null
      ? text
      : '${text.substring(0, mitZone.start)}'
          '${mitZone.group(1)}${mitZone.group(2)}:${mitZone.group(3)}';
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(normiert)) return null;
  return DateTime.tryParse(normiert)?.toLocal();
}

/// Der `creation_time` aus `moov/mvhd`, gelesen als **Ortszeit**.
///
/// Der Kasten ist ein FullBox: ein Byte Fassung, drei Byte Flaggen, dann
/// die Zeit – in Fassung 0 als 32-Bit-Zahl, in Fassung 1 als 64-Bit-Zahl.
///
/// Warum als Ortszeit und nicht als UTC, obwohl die Norm UTC sagt: siehe
/// den Kopf dieser Datei. Kurz: gemessen an 28 Videos mit GPS-Zeit stand
/// dort durchweg Ortszeit.
DateTime? _ausMvhd(Uint8List moov) {
  final mvhd = sucheKasten(moov, 0, moov.length, 'mvhd',
      absteigenIn: const {'moov'}, maxTiefe: 2);
  if (mvhd == null) return null;
  final d = ByteData.sublistView(moov);
  final fassung = moov[mvhd.inhaltVon];
  final int sekunden;
  if (fassung == 1) {
    if (mvhd.inhaltVon + 12 > mvhd.inhaltBis) return null;
    sekunden = d.getUint64(mvhd.inhaltVon + 4);
  } else {
    if (mvhd.inhaltVon + 8 > mvhd.inhaltBis) return null;
    sekunden = d.getUint32(mvhd.inhaltVon + 4);
  }
  if (sekunden <= 0) return null;
  // Ohne Zone gelesen: Die Sekunden werden auf die Zeitrechnung ab 1904
  // addiert und die Wanduhr davon übernommen, nicht der Zeitpunkt.
  final wanduhr = _quicktimeNull.add(Duration(seconds: sekunden));
  final wert = DateTime(wanduhr.year, wanduhr.month, wanduhr.day, wanduhr.hour,
      wanduhr.minute, wanduhr.second);
  // Eine Kamera mit ungestellter Uhr schreibt hier die Sekunden seit dem
  // eigenen Einschalten – dieselbe Prüfung wie bei den EXIF-Daten.
  return wert.year < 1990 ? null : wert;
}

/// Der Aufnahmezeitpunkt aus [datei], oder `null`.
///
/// Liest nur den `moov`-Kasten, nicht die Datei – bei Videos steht der oft
/// **hinter** den Rohdaten, und das sind trotzdem drei Sprünge statt 1,7 GB.
Future<Videozeit?> leseVideoZeit(File datei) async {
  final moov = await kastenAusDatei(datei, 'moov');
  return moov == null ? null : zeitAusMoov(moov);
}

/// Hersteller und Gerät aus [datei] – beides kann `null` sein.
Future<({String? hersteller, String? geraet})> leseVideoKamera(
    File datei) async {
  final moov = await kastenAusDatei(datei, 'moov');
  return moov == null
      ? (hersteller: null, geraet: null)
      : kameraAusMoov(moov);
}

/// Alles, was in einem Video an Metadaten steht, aus **einem** Lesevorgang.
///
/// Der Import braucht Zeitpunkt, Kamera und Ort. Jedes für sich zu holen
/// hiesse, den `moov`-Kasten dreimal zu suchen – und der steht bei Videos
/// oft hinter den Rohdaten, also dreimal durch die Kastenkette einer
/// womöglich mehrere Gigabyte grossen Datei. Einmal reicht.
typedef Videometadaten = ({
  Videozeit? zeit,
  String? hersteller,
  String? geraet,
  ({double breite, double laenge})? ort,
});

const Videometadaten leereVideometadaten =
    (zeit: null, hersteller: null, geraet: null, ort: null);

Future<Videometadaten> leseVideoMetadaten(File datei) async {
  final moov = await kastenAusDatei(datei, 'moov');
  if (moov == null) return leereVideometadaten;
  final kamera = kameraAusMoov(moov);
  return (
    zeit: zeitAusMoov(moov),
    hersteller: kamera.hersteller,
    geraet: kamera.geraet,
    ort: ortAusMoov(moov),
  );
}

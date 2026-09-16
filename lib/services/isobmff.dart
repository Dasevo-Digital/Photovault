/// Der Kastenlauf durch einen ISO-BMFF-Container.
///
/// **Warum das hier getrennt steht.** CR3, MOV und MP4 sind derselbe
/// Container: eine Folge von Kästen, jeder mit vier Byte Länge und vier
/// Byte Art, manche mit Kindern. Der Leser dafür entstand für CR3
/// (siehe [leseCr3Gps]); als die Videos dazukamen, wäre er ein zweites Mal
/// entstanden. Zwei Fassungen desselben Laufs sind die naheliegendste Art,
/// dass eine davon eine Grenzprüfung verliert.
///
/// Die Fallen, die hier ein für alle Mal abgehandelt sind:
///
/// - **Länge 1** heisst „die echte Länge steht als 64-Bit-Zahl hinter der
///   Art"; der Kopf ist dann 16 Byte statt 8.
/// - **Länge 0** heisst „bis zum Ende" und kommt nur beim letzten Kasten vor.
/// - Eine Länge **kleiner als der eigene Kopf** liefe in eine
///   Endlosschleife, eine **über das Ende hinaus** über den Rand. Beides
///   kommt in beschädigten Dateien vor, und beides beendet den Lauf.
/// - `moov` steht bei Fotos am Anfang, bei Videos oft **hinter** `mdat`.
///   Deshalb wird die Datei nicht gelesen, sondern von Kastenkopf zu
///   Kastenkopf gesprungen: An einer 1,7-GB-Aufnahme sind das drei Sprünge
///   statt 1,7 GB.
library;

import 'dart:io';
import 'dart:typed_data';

/// Ein gefundener Kasten samt der Grenzen seines Inhalts.
typedef Kasten = ({String art, int inhaltVon, int inhaltBis});

/// Der grösste Kasten, den [kastenAusDatei] noch in den Speicher holt.
///
/// Die Schranke gilt nicht dem Normalfall – ein `moov` misst zwischen
/// wenigen Kilobyte (Foto) und wenigen Dutzend (langes Video) –, sondern
/// der beschädigten oder böswilligen Datei: Ohne sie ginge eine erfundene
/// Kastenlänge ungeprüft an `read()`.
const int isobmffLesegrenze = 64 * 1024 * 1024;

/// Die Kästen zwischen [von] und [bis] in [b], der Reihe nach.
///
/// Bricht beim ersten unstimmigen Kopf ab, statt zu werfen: Was danach
/// kommt, ist ohnehin nicht mehr zu deuten, und der Aufrufer sucht meist
/// nur nach einem bestimmten Kasten weiter vorn.
Iterable<Kasten> kaesten(Uint8List b, int von, int bis) sync* {
  final d = ByteData.sublistView(b);
  var p = von;
  while (p + 8 <= bis) {
    var groesse = d.getUint32(p);
    var kopf = 8;
    if (groesse == 1) {
      if (p + 16 > bis) return;
      groesse = d.getUint64(p + 8);
      kopf = 16;
    }
    if (groesse == 0) groesse = bis - p;
    if (groesse < kopf || p + groesse > bis) return;
    yield (
      art: String.fromCharCodes(b.sublist(p + 4, p + 8)),
      inhaltVon: p + kopf,
      inhaltBis: p + groesse,
    );
    p += groesse;
  }
}

/// Der erste Kasten der Art [art] unterhalb von [von]…[bis], beliebig tief.
///
/// [absteigenIn] entscheidet, welche Kästen als Behälter gelten – wer
/// überall hineinsteigt, läuft durch Rohdaten, die zufällig wie Köpfe
/// aussehen. [versatzIn] gibt für einen Behälter an, wie viele Bytes vor
/// seinen Kindern stehen (`meta` trägt in MP4 vier Byte Fassung und Flaggen
/// vor dem ersten Kind, in MOV nicht – siehe [kinderVon]).
Kasten? sucheKasten(
  Uint8List b,
  int von,
  int bis,
  String art, {
  required Set<String> absteigenIn,
  int tiefe = 0,
  int maxTiefe = 6,
}) {
  for (final k in kaesten(b, von, bis)) {
    if (k.art == art) return k;
    if (tiefe < maxTiefe && absteigenIn.contains(k.art)) {
      final ab = kinderVon(b, k);
      final treffer = sucheKasten(b, ab, k.inhaltBis, art,
          absteigenIn: absteigenIn, tiefe: tiefe + 1, maxTiefe: maxTiefe);
      if (treffer != null) return treffer;
    }
  }
  return null;
}

/// Wo die Kinder eines Behälters anfangen.
///
/// **Der `meta`-Stolperstein.** In MP4 ist `meta` ein „FullBox": vier Byte
/// Fassung und Flaggen stehen vor dem ersten Kind. In QuickTime (`.mov`)
/// ist es ein gewöhnlicher Behälter ohne diese vier Byte. Beide kommen in
/// dieser Bibliothek vor – die Kamera-Drohne schreibt MP4, das Telefon
/// MOV. Wer sich für eine Fassung entscheidet, liest die andere als Müll.
///
/// Entschieden wird deshalb nicht nach Dateiendung, sondern an den Bytes:
/// Steht unmittelbar hinter dem Kopf schon ein deutbarer Kasten, gibt es
/// keine Fassungsbytes.
///
/// Ein `uuid`-Kasten trägt 16 Byte Kennung vor seinem Inhalt (so findet
/// CR3 seine Canon-Verzeichnisse).
int kinderVon(Uint8List b, Kasten k) {
  if (k.art == 'uuid') return k.inhaltVon + 16;
  if (k.art != 'meta') return k.inhaltVon;
  return _istKastenkopf(b, k.inhaltVon, k.inhaltBis)
      ? k.inhaltVon
      : k.inhaltVon + 4;
}

/// Sieht das, was bei [p] steht, nach einem Kastenkopf aus?
bool _istKastenkopf(Uint8List b, int p, int bis) {
  if (p + 8 > bis) return false;
  final groesse = ByteData.sublistView(b).getUint32(p);
  if (groesse < 8 || p + groesse > bis) return false;
  // Eine Kastenart besteht aus druckbaren Zeichen; die vier Byte einer
  // Fassungsangabe sind typischerweise 0.
  for (var i = p + 4; i < p + 8; i++) {
    if (b[i] < 0x20 || b[i] > 0x7E) return false;
  }
  return true;
}

/// Der erste Kasten der Art [art] auf der **obersten** Ebene von [datei],
/// als Bytes – oder `null`, wenn es ihn nicht gibt.
///
/// Liest nicht die Datei, sondern springt von Kastenkopf zu Kastenkopf und
/// holt genau den einen gefundenen Kasten.
Future<Uint8List?> kastenAusDatei(
  File datei,
  String art, {
  int grenze = isobmffLesegrenze,
}) async {
  RandomAccessFile? griff;
  try {
    griff = await datei.open();
    final dateilaenge = await griff.length();
    var p = 0;
    while (p + 8 <= dateilaenge) {
      await griff.setPosition(p);
      final kopfBytes = await griff.read(8);
      if (kopfBytes.length < 8) return null;
      var groesse =
          ByteData.sublistView(Uint8List.fromList(kopfBytes)).getUint32(0);
      var kopf = 8;
      if (groesse == 1) {
        final weiter = await griff.read(8);
        if (weiter.length < 8) return null;
        groesse = ByteData.sublistView(Uint8List.fromList(weiter)).getUint64(0);
        kopf = 16;
      }
      if (groesse == 0) groesse = dateilaenge - p;
      if (groesse < kopf || p + groesse > dateilaenge) return null;

      if (String.fromCharCodes(kopfBytes.sublist(4, 8)) == art) {
        if (groesse > grenze) return null;
        await griff.setPosition(p);
        return Uint8List.fromList(await griff.read(groesse));
      }
      p += groesse;
    }
    return null;
  } on FileSystemException {
    // Datei weg oder nicht lesbar – das ist nicht die Frage, die hier
    // gestellt wurde. Der Aufrufer läuft ohnehin gleich darauf zu.
    return null;
  } finally {
    await griff?.close();
  }
}

/// Der Wert, den Apple unter [schluessel] in `moov/meta/keys+ilst` ablegt.
///
/// **Zwei Listen, verbunden über eine Nummer.** `keys` trägt die Namen
/// (`com.apple.quicktime.creationdate`, `…location.ISO6709`, `…make`, …),
/// `ilst` die Werte – und zwar **nicht** unter dem Namen, sondern unter
/// der Nummer, an der der Name in `keys` steht, ab 1 gezählt. Wer die
/// Werteliste für sich liest, findet Text ohne Bedeutung.
///
/// Steht hier und nicht bei den Orten, weil dieselben zwei Listen auch das
/// Aufnahmedatum und die Kamera tragen (siehe [zeitAusMoov]) – der
/// gleiche Griff, dreimal gebraucht.
String? appleSchluesselwert(Uint8List moov, String schluessel) {
  final meta = sucheKasten(moov, 0, moov.length, 'meta',
      absteigenIn: const {'moov', 'udta'});
  if (meta == null) return null;
  final ab = kinderVon(moov, meta);

  Kasten? keys, ilst;
  for (final k in kaesten(moov, ab, meta.inhaltBis)) {
    if (k.art == 'keys') keys = k;
    if (k.art == 'ilst') ilst = k;
  }
  if (keys == null || ilst == null) return null;

  final nummer = _nummerDesSchluessels(moov, keys, schluessel);
  return nummer == null ? null : _wertAusIlst(moov, ilst, nummer);
}

/// Die Nummer, unter der [gesucht] in der Namensliste steht (ab 1).
int? _nummerDesSchluessels(Uint8List b, Kasten keys, String gesucht) {
  final d = ByteData.sublistView(b);
  // `keys` ist ein FullBox: vier Byte Fassung/Flaggen, dann die Anzahl.
  var p = keys.inhaltVon + 8;
  if (p > keys.inhaltBis) return null;
  final anzahl = d.getUint32(keys.inhaltVon + 4);
  for (var i = 0; i < anzahl; i++) {
    if (p + 8 > keys.inhaltBis) return null;
    final laenge = d.getUint32(p);
    if (laenge < 8 || p + laenge > keys.inhaltBis) return null;
    // Auf die Länge folgt der Namensraum (vier Byte), dann der Name.
    final name = String.fromCharCodes(b.sublist(p + 8, p + laenge));
    if (name == gesucht) return i + 1;
    p += laenge;
  }
  return null;
}

/// Der Wert zur Nummer [nummer] aus der Werteliste.
String? _wertAusIlst(Uint8List b, Kasten ilst, int nummer) {
  final d = ByteData.sublistView(b);
  var p = ilst.inhaltVon;
  while (p + 8 <= ilst.inhaltBis) {
    final laenge = d.getUint32(p);
    if (laenge < 8 || p + laenge > ilst.inhaltBis) return null;
    if (d.getUint32(p + 4) == nummer) {
      // Im Eintrag steht ein `data`-Kasten: vier Byte Länge, „data",
      // vier Byte Art, vier Byte Sprache, dann der Text.
      for (final k in kaesten(b, p + 8, p + laenge)) {
        if (k.art != 'data') continue;
        final textVon = k.inhaltVon + 8;
        if (textVon > k.inhaltBis) return null;
        return String.fromCharCodes(b.sublist(textVon, k.inhaltBis));
      }
      return null;
    }
    p += laenge;
  }
  return null;
}

/// Der Text eines klassischen QuickTime-Anmerkungsatoms unter `moov/udta`
/// (`©day`, `©mak`, `©mod`, `©xyz`, …).
///
/// Aufbau: zwei Byte Länge, zwei Byte Sprache, dann der Text. Es gibt
/// Schreiber, die den Vorspann weglassen – deshalb wird die angegebene
/// Länge geprüft und nur benutzt, wenn sie in den Kasten passt.
String? udtaAnmerkung(Uint8List moov, String atom) {
  final k = sucheKasten(moov, 0, moov.length, atom,
      absteigenIn: const {'moov', 'udta', 'meta'});
  if (k == null) return null;
  final laenge = k.inhaltBis - k.inhaltVon;
  if (laenge >= 4) {
    final angegeben = ByteData.sublistView(moov).getUint16(k.inhaltVon);
    if (angegeben > 0 && k.inhaltVon + 4 + angegeben <= k.inhaltBis) {
      return String.fromCharCodes(
          moov.sublist(k.inhaltVon + 4, k.inhaltVon + 4 + angegeben));
    }
  }
  return laenge <= 0
      ? null
      : String.fromCharCodes(moov.sublist(k.inhaltVon, k.inhaltBis));
}

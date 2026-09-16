import 'dart:typed_data';

/// Baut CR3-Dateien fuer Tests – Kastenbaum und GPS-Verzeichnis so, wie
/// eine echte Aufnahme sie traegt.
///
/// Eigene Datei, weil zwei Prüfstände sie brauchen: der des Lesers
/// ([cr3_gps_test.dart]) und der der Verdrahtung im Import
/// ([import_service_test.dart]). Zweimal denselben Aufbau nachzubauen
/// hiesse, ihn zweimal falsch machen zu können.

/// Baut einen ISO-BMFF-Kasten: vier Byte Länge, vier Zeichen Art, Inhalt.
Uint8List kasten(String art, List<int> inhalt) {
  final b = BytesBuilder();
  b.add((ByteData(4)..setUint32(0, inhalt.length + 8)).buffer.asUint8List());
  b.add(art.codeUnits);
  b.add(inhalt);
  return b.toBytes();
}

/// Ein `uuid`-Kasten trägt 16 Byte Kennung vor seinem Inhalt.
Uint8List uuidKasten(List<int> inhalt) =>
    kasten('uuid', [...List.filled(16, 0xAA), ...inhalt]);

/// Ein GPS-Verzeichnis im TIFF-Format, so wie es in `CMT4` steht.
///
/// Die Einträge sind zwölf Byte lang; Brüche passen dort nicht hinein und
/// stehen deshalb an einem Versatz dahinter. Genau diese Indirektion ist
/// der Teil, den ein selbst ausgedachter Aufbau falsch machen würde –
/// deshalb wird sie hier nachgebaut und nicht umgangen.
Uint8List gpsVerzeichnis({
  required List<List<int>> breite, // je [Zaehler, Nenner]
  required String breiteRef,
  required List<List<int>> laenge,
  required String laengeRef,
  bool ohneLaenge = false,
}) {
  final eintraege = <Uint8List>[];
  final anzahl = ohneLaenge ? 3 : 4;
  // Kopf (8) + Anzahl (2) + Einträge (12 je) + Abschluss (4)
  final datenAb = 8 + 2 + anzahl * 12 + 4;

  Uint8List eintrag(int tag, int typ, int anzahlWerte, int wert) {
    final d = ByteData(12)
      ..setUint16(0, tag, Endian.little)
      ..setUint16(2, typ, Endian.little)
      ..setUint32(4, anzahlWerte, Endian.little)
      ..setUint32(8, wert, Endian.little);
    return d.buffer.asUint8List();
  }

  Uint8List text(int tag, String wert) {
    final d = ByteData(12)
      ..setUint16(0, tag, Endian.little)
      ..setUint16(2, 2, Endian.little)
      ..setUint32(4, 2, Endian.little);
    final b = d.buffer.asUint8List();
    b[8] = wert.codeUnitAt(0);
    b[9] = 0;
    return b;
  }

  eintraege.add(text(1, breiteRef));
  eintraege.add(eintrag(2, 5, 3, datenAb));
  if (!ohneLaenge) {
    eintraege.add(text(3, laengeRef));
    eintraege.add(eintrag(4, 5, 3, datenAb + 24));
  } else {
    eintraege.add(text(3, laengeRef));
  }

  final b = BytesBuilder();
  b.add([0x49, 0x49]); // „II" – kleine Bytereihenfolge
  b.add((ByteData(2)..setUint16(0, 42, Endian.little)).buffer.asUint8List());
  b.add((ByteData(4)..setUint32(0, 8, Endian.little)).buffer.asUint8List());
  b.add(
      (ByteData(2)..setUint16(0, anzahl, Endian.little)).buffer.asUint8List());
  for (final e in eintraege) {
    b.add(e);
  }
  b.add(List.filled(4, 0)); // kein weiteres Verzeichnis
  for (final brueche in [breite, if (!ohneLaenge) laenge]) {
    for (final bruch in brueche) {
      b.add((ByteData(8)
            ..setUint32(0, bruch[0], Endian.little)
            ..setUint32(4, bruch[1], Endian.little))
          .buffer
          .asUint8List());
    }
  }
  return b.toBytes();
}

/// Eine vollständige, wenn auch winzige CR3: `ftyp`, `moov` mit dem
/// `uuid`-Kasten und `CMT4` darin, und ein `mdat`, das nur da ist, damit
/// der Leser beweisen muss, dass er es überspringt.
Uint8List cr3Mit(Uint8List cmt4Inhalt, {int mdatBytes = 4096}) {
  final b = BytesBuilder();
  b.add(kasten(
      'ftyp', [...'crx '.codeUnits, 0, 0, 0, 1, ...'crx isom'.codeUnits]));
  b.add(kasten(
      'moov',
      uuidKasten([
        ...kasten('CMT1', List.filled(8, 0)),
        ...kasten('CMT4', cmt4Inhalt),
      ])));
  b.add(kasten('mdat', List.filled(mdatBytes, 0x7F)));
  return b.toBytes();
}

/// Braunschweig, Nordhalbkugel, östlich von Greenwich – 52°14'35,2" N,
/// 10°35'7" E. Erfundene Zahlen mit echtem Aufbau: Die Koordinaten der
/// Bibliothek, an der dieser Leser wirklich geprüft wurde, gehören nicht
/// in ein öffentliches Verzeichnis.
final beispielBreite = [
  [52, 1],
  [14, 1],
  [352, 10]
];
final beispielLaenge = [
  [10, 1],
  [35, 1],
  [70, 10]
];

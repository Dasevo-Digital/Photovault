import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/video_gps.dart';

/// **Der Ort im Video.** In der Prüfbibliothek trugen 216 von 440 Videos
/// einen Ort in der Datei und keines einen in der Datenbank.
///
/// Drei Ablagen kommen dort nebeneinander vor, und wer nur die erste liest,
/// verliert die anderen still:
///
/// ```
/// moov/meta/keys+ilst   Telefon (.mov)   ISO 6709 als Text
/// moov/udta/©xyz        Drohne  (.mp4)   ISO 6709 als Text
/// moov/udta/loci        Kamera  (.mp4)   Festkomma, LÄNGE VOR BREITE
/// ```
///
/// Geprüft wird an **gebauten** Bytes und nicht an einer echten Aufnahme:
/// Ein Video der Bibliothek wäre eine Personendatei von 1,7 GB. Der
/// Abgleich mit der Wirklichkeit lief einmalig über
/// `tool/video_gps_abgleich.dart` gegen `exiftool` – 216 von 216
/// übereinstimmend, keine falschen Treffer.
void main() {
  // ---------------------------------------------------------------- Bau

  Uint8List kasten(String art, List<int> inhalt) {
    final b = BytesBuilder();
    final kopf = ByteData(8)..setUint32(0, 8 + inhalt.length);
    b.add(kopf.buffer.asUint8List(0, 4));
    b.add(art.codeUnits);
    b.add(inhalt);
    return b.toBytes();
  }

  /// `keys`: Fassung/Flaggen, Anzahl, dann je Eintrag Länge + Namensraum
  /// + Name.
  Uint8List keysKasten(List<String> namen) {
    final b = BytesBuilder();
    b.add((ByteData(4)..setUint32(0, 0)).buffer.asUint8List());
    b.add((ByteData(4)..setUint32(0, namen.length)).buffer.asUint8List());
    for (final n in namen) {
      b.add((ByteData(4)..setUint32(0, 8 + n.length)).buffer.asUint8List());
      b.add('mdta'.codeUnits);
      b.add(n.codeUnits);
    }
    return kasten('keys', b.toBytes());
  }

  /// `ilst`: je Eintrag Länge + Schlüsselnummer, darin ein `data`-Kasten.
  Uint8List ilstKasten(Map<int, String> werte) {
    final b = BytesBuilder();
    werte.forEach((nummer, text) {
      final daten = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, 1)).buffer.asUint8List()) // Typ
        ..add((ByteData(4)..setUint32(0, 0)).buffer.asUint8List()) // Sprache
        ..add(text.codeUnits);
      final dataKasten = kasten('data', daten.toBytes());
      b.add((ByteData(4)..setUint32(0, 8 + dataKasten.length))
          .buffer
          .asUint8List());
      b.add((ByteData(4)..setUint32(0, nummer)).buffer.asUint8List());
      b.add(dataKasten);
    });
    return kasten('ilst', b.toBytes());
  }

  /// [mitFassungsbytes] bildet den Unterschied zwischen MP4 und QuickTime
  /// nach – in MP4 trägt `meta` vier Byte Fassung/Flaggen vor dem ersten
  /// Kind, in `.mov` nicht.
  Uint8List appleMoov(String ort, {bool mitFassungsbytes = false}) {
    final inneres = BytesBuilder()
      ..add(kasten('hdlr', List.filled(24, 0)))
      ..add(keysKasten([
        'com.apple.quicktime.location.accuracy.horizontal',
        'com.apple.quicktime.make',
        'com.apple.quicktime.location.ISO6709',
      ]))
      ..add(ilstKasten({1: '13.9', 2: 'Apple', 3: ort}));
    final metaInhalt = BytesBuilder();
    if (mitFassungsbytes) metaInhalt.add(const [0, 0, 0, 0]);
    metaInhalt.add(inneres.toBytes());
    return kasten('moov', [
      ...kasten('mvhd', List.filled(100, 0)),
      ...kasten('meta', metaInhalt.toBytes()),
    ]);
  }

  Uint8List xyzMoov(String ort) {
    final nutz = BytesBuilder()
      ..add((ByteData(2)..setUint16(0, ort.length)).buffer.asUint8List())
      ..add(const [0xFF, 0x7F])
      ..add(ort.codeUnits);
    return kasten('moov', [
      ...kasten('udta', kasten('©xyz', nutz.toBytes())),
    ]);
  }

  Uint8List lociMoov(double breite, double laenge, {String name = ''}) {
    final b = BytesBuilder()
      ..add(const [0, 0, 0, 0]) // Fassung/Flaggen
      ..add(const [0x55, 0xC4]) // Sprache
      ..add(name.codeUnits)
      ..add(const [0]) // Namensende
      ..add(const [0]); // Rolle
    final zahlen = ByteData(12)
      ..setInt32(0, (laenge * 65536).round())
      ..setInt32(4, (breite * 65536).round())
      ..setInt32(8, 0);
    b.add(zahlen.buffer.asUint8List());
    b.add('earth'.codeUnits);
    b.add(const [0, 0]);
    return kasten('moov', [...kasten('udta', kasten('loci', b.toBytes()))]);
  }

  // ---------------------------------------------------------------- Tests

  group('ISO 6709 deuten', () {
    test('Telefon-Schreibweise mit Höhe und Schrägstrich', () {
      final o = iso6709Deuten('+52.2375+010.5955+081.205/')!;
      expect(o.breite, closeTo(52.2375, 1e-9));
      expect(o.laenge, closeTo(10.5955, 1e-9));
    });

    test('kurze Schreibweise ohne Höhe', () {
      final o = iso6709Deuten('+52.2375+10.5738')!;
      expect(o.breite, closeTo(52.2375, 1e-9));
      expect(o.laenge, closeTo(10.5738, 1e-9));
    });

    test('Süden und Westen behalten ihr Vorzeichen', () {
      final o = iso6709Deuten('-33.8688+151.2093/')!;
      expect(o.breite, closeTo(-33.8688, 1e-9));
      final p = iso6709Deuten('+40.7128-074.0060/')!;
      expect(p.laenge, closeTo(-74.0060, 1e-9));
    });

    test('die Höhe wird nicht für die Länge gehalten', () {
      // Drei Zahlen, und nur die ersten beiden zählen.
      final o = iso6709Deuten('+52.0000+010.0000+999.000/')!;
      expect(o.laenge, closeTo(10.0, 1e-9));
    });

    test('nichts Deutbares ergibt null', () {
      expect(iso6709Deuten(''), isNull);
      expect(iso6709Deuten('irgendwas'), isNull);
      expect(iso6709Deuten('+52.0'), isNull, reason: 'nur eine Zahl');
    });

    test('unmögliche Werte werden verworfen', () {
      expect(iso6709Deuten('+95.0+010.0/'), isNull);
      expect(iso6709Deuten('+52.0+200.0/'), isNull);
    });

    test('der Nullpunkt im Atlantik gilt als „weiss nicht"', () {
      // Den melden Geräte, die keinen Empfang hatten.
      expect(iso6709Deuten('+0.0000+0.0000/'), isNull);
    });
  });

  group('Die drei Ablagen', () {
    test('Apple: keys und ilst, verbunden über die Nummer', () {
      final o = ortAusMoov(appleMoov('+52.2375+010.5955+081.205/'))!;
      expect(o.breite, closeTo(52.2375, 1e-9));
      expect(o.laenge, closeTo(10.5955, 1e-9));
    });

    test('Apple: auch wenn meta seine Fassungsbytes trägt', () {
      // MP4 gegen QuickTime. Wer sich für eine Fassung entscheidet, liest
      // die andere als Müll.
      final o = ortAusMoov(
          appleMoov('+52.2375+010.5955/', mitFassungsbytes: true))!;
      expect(o.breite, closeTo(52.2375, 1e-9));
    });

    test('Apple: die Nummer zählt, nicht die Reihenfolge im ilst', () {
      // Der Ortsschlüssel steht an dritter Stelle der Namensliste; im
      // ilst kommt er zuerst. Wer der Reihe nach zuordnet, liest die
      // Genauigkeit als Ort.
      final moov = kasten('moov', [
        ...kasten('meta', [
          ...keysKasten([
            'com.apple.quicktime.location.accuracy.horizontal',
            'com.apple.quicktime.make',
            'com.apple.quicktime.location.ISO6709',
          ]),
          ...ilstKasten({3: '+48.1372+011.5756/', 1: '13.9'}),
        ]),
      ]);
      final o = ortAusMoov(moov)!;
      expect(o.breite, closeTo(48.1372, 1e-9));
    });

    test('©xyz im udta', () {
      final o = ortAusMoov(xyzMoov('+52.2375+10.5738'))!;
      expect(o.breite, closeTo(52.2375, 1e-9));
      expect(o.laenge, closeTo(10.5738, 1e-9));
    });

    test('loci: Länge steht vor Breite', () {
      // Der teuerste Fehler dieses Kastens: vertauscht ergäbe 52,4 N /
      // 10,8 O den Punkt 10,8 N / 52,4 O im Indischen Ozean – plausibel
      // aussehend und falsch.
      final o = ortAusMoov(lociMoov(52.43199, 10.79320))!;
      expect(o.breite, closeTo(52.43199, 1e-4));
      expect(o.laenge, closeTo(10.79320, 1e-4));
    });

    test('loci mit Ortsnamen davor', () {
      final o = ortAusMoov(lociMoov(52.0, 10.0, name: 'Braunschweig'))!;
      expect(o.breite, closeTo(52.0, 1e-4));
      expect(o.laenge, closeTo(10.0, 1e-4));
    });

    test('loci: negative Werte', () {
      final o = ortAusMoov(lociMoov(-33.8688, 151.2093))!;
      expect(o.breite, closeTo(-33.8688, 1e-4));
      expect(o.laenge, closeTo(151.2093, 1e-4));
    });

    test('ein moov ohne Ort ergibt null statt einer Ausnahme', () {
      expect(ortAusMoov(kasten('moov', kasten('mvhd', List.filled(100, 0)))),
          isNull);
      expect(ortAusMoov(Uint8List(0)), isNull);
    });
  });

  group('An einer Datei', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pv_videogps_'));
    tearDown(() => temp.deleteSync(recursive: true));

    /// Baut eine Datei, in der `moov` **hinter** den Rohdaten steht – so
    /// wie es bei Videos der Regelfall ist und bei Fotos nie vorkommt.
    File datei(String name, Uint8List moov, {int mdatBytes = 5000}) {
      final f = File('${temp.path}/$name');
      final b = BytesBuilder()
        ..add(kasten('ftyp', 'qt  '.codeUnits))
        ..add(kasten('mdat', List.filled(mdatBytes, 7)))
        ..add(moov);
      f.writeAsBytesSync(b.toBytes());
      return f;
    }

    test('moov hinter mdat wird gefunden', () async {
      final o = await leseVideoGps(
          datei('a.mov', appleMoov('+52.2375+010.5955/')));
      expect(o, isNotNull);
      expect(o!.breite, closeTo(52.2375, 1e-9));
    });

    test('ein Video ohne Ort ergibt null', () async {
      final o = await leseVideoGps(
          datei('b.mov', kasten('moov', kasten('mvhd', List.filled(80, 0)))));
      expect(o, isNull);
    });

    test('eine fehlende Datei wirft nicht', () async {
      expect(await leseVideoGps(File('${temp.path}/gibtsnicht.mov')), isNull);
    });

    test('eine abgeschnittene Datei wirft nicht', () async {
      final voll = datei('c.mov', xyzMoov('+52.0+10.0'));
      final bytes = voll.readAsBytesSync();
      File('${temp.path}/halb.mov')
          .writeAsBytesSync(bytes.sublist(0, bytes.length - 20));
      expect(await leseVideoGps(File('${temp.path}/halb.mov')), isNull);
    });

    test('eine erfundene Kastenlänge läuft nicht ins Leere', () async {
      // Vier Byte Länge, die weit über das Dateiende zeigt.
      final f = File('${temp.path}/kaputt.mov');
      f.writeAsBytesSync(Uint8List.fromList([
        0xFF, 0xFF, 0xFF, 0xFF, ...'moov'.codeUnits, 1, 2, 3, 4,
      ]));
      expect(await leseVideoGps(f), isNull);
    });

    test('eine Datei ohne jeden Kasten wirft nicht', () async {
      final f = File('${temp.path}/text.mov')..writeAsStringSync('kein Video');
      expect(await leseVideoGps(f), isNull);
    });
  });
}

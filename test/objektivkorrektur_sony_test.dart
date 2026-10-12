import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/objektivkorrektur.dart';

/// Eine TIFF-Datei, wie Sony sie als ARW schreibt, auf das Nötigste
/// gekürzt: IFD0 mit einem Verweis auf das Verzeichnis der Rohdaten
/// (0x014A), dort `DistortionCorrParams` (0x7037, int16s[17]).
Uint8List sonyTiff(List<int>? stuetzwerte, {Endian ordnung = Endian.little}) {
  final b = ByteData(256);
  final ii = ordnung == Endian.little;
  b
    ..setUint8(0, ii ? 0x49 : 0x4D)
    ..setUint8(1, ii ? 0x49 : 0x4D)
    ..setUint16(2, 42, ordnung)
    ..setUint32(4, 8, ordnung);
  // IFD0 bei 8: ein Eintrag, SubIFDs → 26.
  b
    ..setUint16(8, 1, ordnung)
    ..setUint16(10, 0x014A, ordnung)
    ..setUint16(12, 4, ordnung)
    ..setUint32(14, 1, ordnung)
    ..setUint32(18, 26, ordnung)
    ..setUint32(22, 0, ordnung);
  // SubIFD bei 26: ein Eintrag, Werte bei 64.
  b
    ..setUint16(26, stuetzwerte == null ? 0 : 1, ordnung)
    ..setUint16(28, 0x7037, ordnung)
    ..setUint16(30, 8, ordnung)
    ..setUint32(32, 17, ordnung)
    ..setUint32(36, 64, ordnung)
    ..setUint32(40, 0, ordnung);
  if (stuetzwerte != null) {
    b.setInt16(64, stuetzwerte.length, ordnung);
    for (var i = 0; i < stuetzwerte.length; i++) {
      b.setInt16(66 + 2 * i, stuetzwerte[i], ordnung);
    }
  }
  return b.buffer.asUint8List();
}

void main() {
  // Werte einer echten Aufnahme (Sigma 30 mm an einer ILCE-6300).
  const sigma30 = [-7, -4, -22, -47, -97, -155, -234, -327, -453, -604, -798];

  group('lesen', () {
    test('findet die Stützstellen im Verzeichnis der Rohdaten', () {
      final v = leseSonyVerzeichnung(sonyTiff(sigma30))!;
      expect(v.faktor(0), closeTo(1 - 7 / 16384, 1e-12));
      expect(v.faktor(1), closeTo(1 - 798 / 16384, 1e-12));
      // Zwischen den Stützstellen linear: 0,05 liegt mitten zwischen der
      // ersten (0) und der zweiten (0,1).
      expect(v.faktor(0.05), closeTo(1 - 5.5 / 16384, 1e-12));
    });

    test('auch in Motorola-Reihenfolge', () {
      final v = leseSonyVerzeichnung(sonyTiff(sigma30, ordnung: Endian.big));
      expect(v?.faktor(1), closeTo(1 - 798 / 16384, 1e-12));
    });

    test('ohne Tag, mit lauter Nullen oder kaputt: nichts', () {
      expect(leseSonyVerzeichnung(sonyTiff(null)), isNull);
      expect(leseSonyVerzeichnung(sonyTiff(List.filled(11, 0))), isNull);
      expect(leseSonyVerzeichnung(Uint8List.fromList([1, 2, 3])), isNull);
      final abgeschnitten = sonyTiff(sigma30).sublist(0, 70);
      expect(leseSonyVerzeichnung(abgeschnitten), isNull);
      // Ein Verzeichnis, das auf sich selbst zeigt, darf nicht hängen.
      final schleife = ByteData.sublistView(sonyTiff(null))
        ..setUint32(28, 26, Endian.little);
      expect(leseSonyVerzeichnung(schleife.buffer.asUint8List()), isNull);
    });

    test('liest eine echte ARW', () {
      // tool/fetch_format_samples.sh; fehlt die Datei, gibt es nichts zu
      // prüfen.
      final datei = File('test/fixtures/samples/sony_ilce6300.arw');
      if (!datei.existsSync()) return;
      final v = leseSonyVerzeichnung(datei.readAsBytesSync())!;
      // exiftool: DistortionCorrParams 11 -7 -4 … -798
      expect(v.faktor(0), closeTo(1 - 7 / 16384, 1e-12));
      expect(v.faktor(1), closeTo(1 - 798 / 16384, 1e-12));
    });
  });

  group('Maßstab', () {
    // Gegen CIRAWFilter gemessen: Apple vergrößert diese Aufnahme um
    // 1,0122, damit kein leerer Rand bleibt (siehe objektivkorrektur.dart).
    test('tonnenförmig: die Mitte der kurzen Kante bindet', () {
      final v = leseSonyVerzeichnung(sonyTiff(sigma30))!;
      expect(v.massstab(1500, 1000), closeTo(1.0122, 0.0005));
      final innen = 500 / (math.sqrt(1500 * 1500 + 1000 * 1000) / 2);
      expect(v.massstab(1500, 1000), closeTo(1 / v.faktor(innen), 1e-3));
    });

    test('kissenförmig: die Ecke bindet', () {
      const kissen = [0, 14, 58, 144, 273, 431, 647, 906, 1236, 1653, 2185];
      final v = leseSonyVerzeichnung(sonyTiff(kissen))!;
      expect(v.massstab(1500, 1000), closeTo(1 / v.faktor(1), 1e-9));
    });
  });

  test('entzerren holt jeden Punkt von der berechneten Stelle', () {
    // Eine senkrechte Linie im unkorrigierten Bild. Nach dem Entzerren
    // steht sie dort, wo Maßstab · faktor(r) · Abstand wieder auf sie
    // zeigt – in der Bildmitte gerechnet, also auf der waagerechten
    // Mittellinie.
    const breite = 600, hoehe = 400;
    final roh = img.Image(width: breite, height: hoehe);
    img.fill(roh, color: img.ColorRgb8(0, 0, 0));
    // Weit aussen: Nahe der Mitte der kurzen Kante hebt der Maßstab die
    // Verzeichnung gerade auf.
    const linie = 575;
    img.fillRect(
      roh,
      x1: linie,
      y1: 0,
      x2: linie,
      y2: hoehe - 1,
      color: img.ColorRgb8(255, 255, 255),
    );
    // Kräftig tonnenförmig, damit die Linie sichtbar wandert.
    final v = leseSonyVerzeichnung(
      sonyTiff([for (var i = 0; i <= 10; i++) -20 * i * i]),
    )!;
    final ergebnis = entzerre(roh, v);

    const cx = (breite - 1) / 2, cy = (hoehe - 1) / 2;
    final halbeDiagonale = math.sqrt(cx * cx + cy * cy);
    final s = v.massstab(breite, hoehe);
    // Wo landet die Linie? Die Stelle x, für die die Quelle genau auf
    // der Linie liegt.
    var erwartet = cx;
    for (var x = cx; x < breite; x += 0.01) {
      final dx = x - cx;
      if (cx + dx * s * v.faktor(dx / halbeDiagonale) >= linie) {
        erwartet = x;
        break;
      }
    }
    var hellste = 0;
    var spalte = 0;
    for (var x = 0; x < breite; x++) {
      final w = ergebnis.getPixel(x, hoehe ~/ 2).r.toInt();
      if (w > hellste) {
        hellste = w;
        spalte = x;
      }
    }
    expect(spalte, closeTo(erwartet, 1.0));
    // Und die Linie ist tatsächlich gewandert – sonst prüfte der Test
    // nichts.
    expect((spalte - linie).abs(), greaterThan(3));
  });

  group('Stand unter Linux und Windows', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('pv_objektiv_'));
    tearDown(() => temp.deleteSync(recursive: true));

    Future<Objektivkorrekturstand> stand(String name, Uint8List daten) {
      final f = File(p.join(temp.path, name))..writeAsBytesSync(daten);
      return NativeImageConverter.objektivkorrekturOhneKanal(f);
    }

    test('Sony mit Korrekturdaten: aus der Datei', () async {
      expect(
        await stand('a.arw', sonyTiff(sigma30)),
        Objektivkorrekturstand.ausDerDatei,
      );
    });

    test('Sony ohne, andere RAW, kein RAW', () async {
      expect(
        await stand('b.arw', sonyTiff(null)),
        Objektivkorrekturstand.nichtInDatenbank,
      );
      expect(
        await stand('c.cr3', sonyTiff(sigma30)),
        Objektivkorrekturstand.nichtInDatenbank,
      );
      expect(
        await stand('d.jpg', Uint8List(4)),
        Objektivkorrekturstand.keinRaw,
      );
    });
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:farbverwaltung/farbverwaltung.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/bildzuschnitt.dart';
import 'package:kern/services/jpeg_icc.dart';
import 'package:photo_vault/services/farbverwaltung.dart';

void main() {
  late Directory temp;
  late Farbverwaltung dienst;
  late Uint8List srgb, p3, jpeg;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_farbtest_');
    dienst = Farbverwaltung(Directory('${temp.path}/profile'));
    srgb = Farbengine.standard(Standardfarbraum.srgb);
    p3 = Farbengine.standard(Standardfarbraum.displayP3);
    jpeg = Uint8List.fromList(
      img.encodeJpg(
        img.Image(width: 24, height: 16)..clear(img.ColorRgb8(180, 40, 60)),
      ),
    );
  });
  tearDown(() => temp.delete(recursive: true));
  test('native Profile, Identität und tatsächlicher Farbraumwechsel', () {
    expect(Farbengine.pruefe(srgb), IccFarbraum.rgb);
    expect(Farbengine.pruefe(p3), IccFarbraum.rgb);
    final farben = Uint8List.fromList([120, 60, 80, 30, 200, 60, 255, 0, 0]);
    final identisch = Farbengine.transformiere(
      farben,
      quelle: srgb,
      ziel: srgb,
    );
    for (var i = 0; i < farben.length; i++) {
      expect((identisch[i] - farben[i]).abs(), lessThanOrEqualTo(1));
    }
    expect(
      Farbengine.transformiere(farben, quelle: p3, ziel: srgb),
      isNot(farben),
    );
    expect(Farbengine.lizenz, contains('Permission'));
  });
  test(
    'Softproof und Gamutwarnung rechnen getrennt vom normalen Transform',
    () {
      final farben = Uint8List.fromList([
        255,
        0,
        0,
        0,
        255,
        0,
        0,
        0,
        255,
        128,
        128,
        128,
      ]);
      final normal = Farbengine.transformiere(farben, quelle: p3, ziel: p3);
      final proof = Farbengine.transformiere(
        farben,
        quelle: p3,
        ziel: p3,
        druck: srgb,
        druckvorschau: true,
      );
      final warnung = Farbengine.transformiere(
        farben,
        quelle: p3,
        ziel: p3,
        druck: srgb,
        gamutwarnung: true,
      );
      // Matrixprofile ohne Papierfarbe können verlustfrei durchgereicht werden.
      // Ein abweichender Papierweißpunkt muss im absoluten Proof sichtbar sein.
      final papier = Uint8List.fromList(srgb);
      final daten = ByteData.sublistView(papier);
      for (var i = 0; i < daten.getUint32(128); i++) {
        if (daten.getUint32(132 + i * 12) == 0x77747074) {
          final offset = daten.getUint32(136 + i * 12);
          daten.setInt32(offset + 8, (.95047 * 65536).round());
          daten.setInt32(offset + 12, 65536);
          daten.setInt32(offset + 16, (1.08883 * 65536).round());
        }
      }
      expect(
        Farbengine.transformiere(
          farben,
          quelle: p3,
          ziel: p3,
          druck: papier,
          druckvorschau: true,
          papierfarbe: true,
        ),
        isNot(normal),
      );
      expect(proof.length, normal.length);
      expect([
        for (var i = 0; i < warnung.length; i += 3) warnung.sublist(i, i + 3),
      ], contains(equals([255, 0, 255])));
      expect(Farbengine.transformiere(farben, quelle: p3, ziel: p3), normal);
      expect(
        () => Farbengine.transformiere(farben, gamutwarnung: true),
        throwsA(isA<FarbprofilFehler>()),
      );
    },
  );
  test(
    'beschädigte ICC-Köpfe und Taggrenzen werden vor dem nativen Aufruf abgelehnt',
    () {
      for (final b in [
        Uint8List(0),
        Uint8List(131),
        Uint8List.fromList(srgb)..[36] = 0,
        Uint8List.fromList(srgb)..[128] = 255,
      ]) {
        expect(() => Farbengine.pruefe(b), throwsA(isA<FarbprofilFehler>()));
      }
      expect(
        () => Farbengine.transformiere(Uint8List(2)),
        throwsA(isA<FarbprofilFehler>()),
      );
    },
  );
  test(
    'ICC-APP2-Rundlauf über 64KB, Austausch und Entfernung erhalten Bilddaten',
    () {
      final gross = Uint8List.fromList(
        List<int>.generate(150000, (i) => i % 251),
      );
      final mit = JpegIcc.schreiben(jpeg, gross);
      expect(JpegIcc.lesen(mit), gross);
      expect(JpegIcc.schreiben(mit, null), jpeg);
      expect(JpegIcc.lesen(JpegIcc.schreiben(mit, srgb)), srgb);
      expect(img.decodeJpg(JpegIcc.schreiben(jpeg, srgb))!.width, 24);
      expect(
        () => JpegIcc.lesen(Uint8List.fromList(mit)..[16] = 0),
        throwsFormatException,
      );
      expect(() => JpegIcc.lesen(mit.sublist(0, 100)), throwsFormatException);
      expect(() => JpegIcc.masse(jpeg, maxPixel: 10), throwsFormatException);
    },
  );
  test('Zuschnitt erhält ein korrekt segmentiertes ICC-Profil', () async {
    final aus = await schneideEntwicklung(
      JpegIcc.schreiben(jpeg, p3),
      Bildzuschnitt(breite: .5),
    );
    expect(JpegIcc.lesen(aus), p3);
    expect(JpegIcc.masse(aus), (breite: 12, hoehe: 16));
  });
  test(
    'Profile werden lokal kopiert und Defekte nicht still durch sRGB ersetzt',
    () async {
      final quelle = await File('${temp.path}/monitor.icc').writeAsBytes(p3);
      final w = await dienst.uebernehmen(quelle, Profilrolle.bildschirm);
      expect(w.bildschirm.length, 64);
      expect(await quelle.readAsBytes(), p3);
      final aus = await dienst.anzeige(JpegIcc.schreiben(jpeg, srgb));
      expect(JpegIcc.lesen(aus), p3);
      await File('${dienst.ordner.path}/${w.bildschirm}.icc').writeAsBytes([1]);
      await expectLater(dienst.anzeige(jpeg), throwsA(isA<FarbprofilFehler>()));
    },
  );
  test(
    'Export behält Standardbytes, explizite Profile und Datenschutz verwenden echte ICC-Ausgabe',
    () async {
      final quelle = JpegIcc.schreiben(jpeg, p3);
      expect(await dienst.exportiere(quelle), quelle);
      await dienst.speichern(
        const Farbeinstellungen(ausgabe: 'p3', druck: 'srgb'),
      );
      final normal = await dienst.exportiere(quelle);
      expect(Farbengine.pruefe(JpegIcc.lesen(normal)!), IccFarbraum.rgb);
      final privat = await dienst.exportiere(quelle, datenschutz: true);
      final drin = JpegIcc.lesen(privat)!;
      final farbe = Uint8List.fromList([100, 50, 80]);
      expect(Farbengine.transformiere(farbe, quelle: drin, ziel: srgb), farbe);
      expect(await dienst.exportiere(quelle), normal);
      final proof = await dienst.anzeige(
        quelle,
        druckvorschau: true,
        gamutwarnung: true,
      );
      expect(proof, isNot(normal));
      expect(await dienst.exportiere(quelle), normal);
    },
  );
}

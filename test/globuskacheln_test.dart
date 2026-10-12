import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_earth_globe/sphere_shader_painter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/services/globuskacheln.dart';

/// Ein Kachelspeicher, den es nicht gibt – jede Kachel kommt aus dem Netz.
class _OhneSpeicher implements MapCachingProvider {
  @override
  bool get isSupported => false;
  @override
  Future<CachedMapTile?> getTile(String url) async => null;
  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {}
}

Future<ui.Image> einfarbig(int r, int g, int b, {int kante = 4}) {
  final pixel = Uint8List(kante * kante * 4);
  for (var i = 0; i < pixel.length; i += 4) {
    pixel
      ..[i] = r
      ..[i + 1] = g
      ..[i + 2] = b
      ..[i + 3] = 255;
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixel,
    kante,
    kante,
    ui.PixelFormat.rgba8888,
    fertig.complete,
  );
  return fertig.future;
}

void main() {
  group('Kachelstufe', () {
    test('folgt Kugelgrösse, Pixeldichte und Breitengrad', () {
      // Umfang 2π·400·2 = 5027 Punkte = 19,6 Kacheln → Stufe 4.
      expect(globusKachelstufe(radius: 400, pixeldichte: 2, breitengrad: 0), 4);
      // Achtfach vergrössert (Zoomstufe 3): drei Stufen mehr.
      expect(
        globusKachelstufe(radius: 3200, pixeldichte: 2, breitengrad: 0),
        7,
      );
      // Auf 60° ist der Breitenkreis halb so lang: eine Stufe weniger.
      expect(
        globusKachelstufe(radius: 3200, pixeldichte: 2, breitengrad: 60),
        6,
      );
    });
  });

  group('Kachelfenster', () {
    test('unter Stufe 6 genügt die Grundtextur', () {
      expect(
        globusFenster(
          breitengrad: 47.4,
          laengengrad: 8.5,
          radius: 400,
          ansichtBreite: 1000,
          ansichtHoehe: 700,
          pixeldichte: 2,
        ),
        isNull,
      );
    });

    test('liegt um den Blickpunkt und deckt die Ansicht', () {
      final f = globusFenster(
        breitengrad: 47.4,
        laengengrad: 8.5,
        radius: 3200,
        ansichtBreite: 1000,
        ansichtHoehe: 700,
        pixeldichte: 2,
      )!;
      expect(f.stufe, 7);
      // Zürich auf Stufe 7: Kachel (67, 45).
      final n = 1 << f.stufe;
      final kx = (8.5 + 180) / 360 * n;
      final phi = 47.4 * math.pi / 180;
      final ky =
          (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2 * n;
      expect(kx, inInclusiveRange(f.x0 + 2, f.x0 + f.breite - 2));
      expect(ky, inInclusiveRange(f.y0 + 2, f.y0 + f.hoehe - 2));
      // Eine Kachel misst dort 2π·3200·2·cos(47,4°)/128 = 213 Punkte;
      // 2000 × 1400 Punkte sind also 10 × 7 Kacheln, dazu je zwei Rand.
      expect(f.breite, 12);
      expect(f.hoehe, 9);
    });

    test('über die Datumsgrenze und am Pol', () {
      final f = globusFenster(
        breitengrad: 0,
        laengengrad: 179.9,
        radius: 3200,
        ansichtBreite: 1000,
        ansichtHoehe: 700,
        pixeldichte: 2,
      )!;
      final n = 1 << f.stufe;
      expect(f.x0 + f.breite, greaterThan(n), reason: 'reicht über 180°');
      // Ein Blick knapp jenseits der Grenze liegt im selben Fenster.
      final dahinter = globusFenster(
        breitengrad: 0,
        laengengrad: -179.95,
        radius: 3200,
        ansichtBreite: 400,
        ansichtHoehe: 300,
        pixeldichte: 2,
      )!;
      expect(f.umfasst(dahinter), isTrue);

      expect(
        globusFenster(
          breitengrad: 86,
          laengengrad: 0,
          radius: 3200,
          ansichtBreite: 1000,
          ansichtHoehe: 700,
          pixeldichte: 2,
        ),
        isNull,
        reason: 'Web Mercator endet bei 85°',
      );
    });

    test('wird lieber gröber als zu gross', () {
      final f = globusFenster(
        breitengrad: 0,
        laengengrad: 0,
        radius: 20000,
        ansichtBreite: 3000,
        ansichtHoehe: 2000,
        pixeldichte: 2,
      )!;
      expect(f.breite, lessThanOrEqualTo(globusMosaikBreite));
      expect(f.hoehe, lessThanOrEqualTo(globusMosaikHoehe));
      expect(
        f.stufe,
        lessThan(
          globusKachelstufe(radius: 20000, pixeldichte: 2, breitengrad: 0),
        ),
      );
    });
  });

  test('das Mosaik setzt die Kacheln an ihren Platz, fehlende bleiben '
      'durchsichtig', () async {
    // Jede Kachel einfarbig, die Farbe aus ihrer Spalte; Kachel (65, 44)
    // fehlt.
    final netz = MockClient((anfrage) async {
      final teile = anfrage.url.pathSegments;
      final y = int.parse(teile[teile.length - 2]);
      final x = int.parse(teile.last);
      if (x == 65 && y == 44) return http.Response('', 404);
      final kachel = img.Image(width: 256, height: 256);
      img.fill(kachel, color: img.ColorRgb8(x * 3 % 256, 100, 50));
      return http.Response.bytes(img.encodePng(kachel), 200);
    });
    final mosaik = (await ladeMosaik(
      const Kachelfenster(7, 64, 43, 3, 2),
      netz,
      _OhneSpeicher(),
    ))!;
    expect([mosaik.width, mosaik.height], [768, 512]);
    final roh = (await mosaik.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int rot(int px, int py) => roh.getUint8((py * 768 + px) * 4);
    int alpha(int px, int py) => roh.getUint8((py * 768 + px) * 4 + 3);
    expect(rot(128, 128), 64 * 3 % 256);
    expect(rot(640, 128), 66 * 3 % 256);
    expect(alpha(384, 384), 0, reason: 'Kachel (65, 44) fehlt');
    expect(alpha(384, 128), 255);
    mosaik.dispose();
  });

  testWidgets('der Shader zeigt das Mosaik dort, wo es liegt', (tester) async {
    // Grundtextur blau, Mosaik rot um 0°/0° (Stufe 6, Kacheln 31…32).
    // Ohne Drehung zeigt die Kugelmitte auf 0°/0°.
    final (grund, mosaik, manager) = (await tester.runAsync(() async {
      final manager = SphereShaderManager();
      expect(await manager.loadShader(), isTrue);
      return (await einfarbig(0, 0, 255), await einfarbig(255, 0, 0), manager);
    }))!;
    final shader = manager.createShaderWithTextures(daySurface: grund)!;

    Future<(int, int)> farbeBei(Offset punkt, {required bool mitMosaik}) async {
      final aufnahme = ui.PictureRecorder();
      SphereShaderPainter(
        shader: shader,
        radius: 100,
        center: const Offset(120, 120),
        rotationX: 0,
        rotationZ: 0,
        lightingEnabled: false,
        detailBild: mitMosaik ? mosaik : grund,
        detailAktiv: mitMosaik,
        detailStufe: 6,
        detailX0: 31,
        detailY0: 31,
        detailBreite: 2,
        detailHoehe: 2,
      ).paint(ui.Canvas(aufnahme), const Size(240, 240));
      final bild = await tester.runAsync(
        () => aufnahme.endRecording().toImage(240, 240),
      );
      final roh = (await tester.runAsync(
        () => bild!.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final i = (punkt.dy.round() * 240 + punkt.dx.round()) * 4;
      return (roh.getUint8(i), roh.getUint8(i + 2));
    }

    // Mitte: im Mosaik.
    final mitte = await farbeBei(const Offset(120, 120), mitMosaik: true);
    expect(mitte.$1, greaterThan(200), reason: 'Mitte nicht rot: $mitte');
    // Weit aussen (rund 50° Länge): Grundtextur.
    final aussen = await farbeBei(const Offset(195, 120), mitMosaik: true);
    expect(aussen.$2, greaterThan(200), reason: 'aussen nicht blau: $aussen');
    // Ohne Mosaik überall die Grundtextur.
    final ohne = await farbeBei(const Offset(120, 120), mitMosaik: false);
    expect(ohne.$2, greaterThan(200), reason: 'ohne Mosaik nicht blau: $ohne');
  });
}

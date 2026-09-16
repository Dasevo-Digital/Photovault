import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/staubflecken.dart';

/// Sensorstaub: dunkel, rund, klein – und vor allem immer an derselben
/// Stelle. Der letzte Teil ist das Verfahren, alles davor nur die Vorstufe.
///
/// Die Schwellen stammen aus einer Messung an echten Serien: Mit einer
/// Mindesttiefe von 6 kamen bei einer EOS 60D 646 Verdachte je Aufnahme
/// heraus, mit 14 und der Prüfung auf eine ruhige Umgebung 0,7.

/// Ein gleichmässiger Himmel mit leichtem Verlauf und etwas Rauschen.
img.Image _himmel(int seed, {List<(double, double, double)> koerner = const []}) {
  final zufall = math.Random(seed);
  final b = img.Image(width: 800, height: 600);
  for (var y = 0; y < b.height; y++) {
    for (var x = 0; x < b.width; x++) {
      final grund = 210 - (y * 30 ~/ b.height) + zufall.nextInt(3);
      b.setPixelRgb(x, y, grund, grund, grund + 12);
    }
  }
  for (final (kx, ky, kr) in koerner) {
    final mx = (kx * b.width).round(), my = (ky * b.height).round();
    for (var dy = -20; dy <= 20; dy++) {
      for (var dx = -20; dx <= 20; dx++) {
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > kr * 1.8) continue;
        final x = mx + dx, y = my + dy;
        if (x < 0 || y < 0 || x >= b.width || y >= b.height) continue;
        final staerke = math.exp(-(d * d) / (kr * kr));
        final neu = (b.getPixel(x, y).r - 55 * staerke).clamp(0, 255).toInt();
        b.setPixelRgb(x, y, neu, neu, neu);
      }
    }
  }
  return b;
}

/// Unruhiges Motiv – Laub, Kies, Wellen. Genau das, was ohne die Prüfung auf
/// eine ruhige Umgebung hunderte Fehlalarme lieferte.
img.Image _unruhig(int seed) {
  final zufall = math.Random(seed);
  final b = img.Image(width: 800, height: 600);
  for (var y = 0; y < b.height; y++) {
    for (var x = 0; x < b.width; x++) {
      final wert = 90 + zufall.nextInt(120);
      b.setPixelRgb(x, y, wert, wert, wert);
    }
  }
  return b;
}

void main() {
  group('Ein einzelnes Bild', () {
    test('findet ein Korn im Himmel', () {
      final verdachte = findeStaubverdacht(_himmel(1, koerner: [(0.30, 0.22, 6.0)]));
      expect(verdachte.length, 1);
      expect(verdachte.single.x, closeTo(0.30, 0.02));
      expect(verdachte.single.y, closeTo(0.22, 0.02));
      expect(verdachte.single.tiefe, greaterThan(staubMindesttiefe));
    });

    test('findet mehrere Körner', () {
      final verdachte = findeStaubverdacht(
          _himmel(2, koerner: [(0.30, 0.22, 6.0), (0.71, 0.55, 5.0)]));
      expect(verdachte.length, 2);
    });

    test('ein sauberer Himmel ergibt nichts', () {
      expect(findeStaubverdacht(_himmel(3)), isEmpty);
    });

    test('ein unruhiges Motiv ergibt nichts', () {
      // Ohne die Prüfung auf eine ruhige Umgebung lieferte genau das
      // hunderte Verdachte je Aufnahme.
      expect(findeStaubverdacht(_unruhig(4)), isEmpty);
    });

    test('winzige Bilder werden übersprungen statt zu werfen', () {
      expect(findeStaubverdacht(img.Image(width: 10, height: 10)), isEmpty);
    });
  });

  group('Die Serie entscheidet', () {
    test('eine Stelle auf allen Aufnahmen wird bestätigt', () {
      final serie = [
        for (var i = 0; i < 8; i++)
          findeStaubverdacht(_himmel(i, koerner: [(0.30, 0.22, 6.0)])),
      ];
      final stellen = bestaetigeUeberSerie(serie);
      expect(stellen.length, 1);
      expect(stellen.single.x, closeTo(0.30, 0.02));
      expect(stellen.single.treffer, 8);
      expect(stellen.single.untersucht, 8);
      expect(stellen.single.anteil, 1.0);
    });

    test('eine Stelle auf nur einer Aufnahme wird verworfen', () {
      // Der Vogel am Himmel: einmal da, sonst nie.
      final serie = [
        for (var i = 0; i < 8; i++)
          findeStaubverdacht(_himmel(i, koerner: i == 3 ? [(0.30, 0.22, 6.0)] : const [])),
      ];
      expect(bestaetigeUeberSerie(serie), isEmpty);
    });

    test('knapp über der Schwelle reicht, knapp darunter nicht', () {
      List<List<Staubverdacht>> mitAnteil(int auf) => [
            for (var i = 0; i < 10; i++)
              findeStaubverdacht(
                  _himmel(i, koerner: i < auf ? [(0.30, 0.22, 6.0)] : const [])),
          ];
      expect(bestaetigeUeberSerie(mitAnteil(6)).length, 1, reason: '60 %');
      expect(bestaetigeUeberSerie(mitAnteil(5)), isEmpty, reason: '50 %');
    });

    test('zwei Körner im selben Bild zählen nicht doppelt', () {
      // Sonst käme eine Gruppe auf mehr Treffer als es Aufnahmen gibt.
      final serie = [
        for (var i = 0; i < 4; i++)
          findeStaubverdacht(_himmel(i, koerner: [(0.30, 0.22, 6.0), (0.32, 0.24, 5.0)])),
      ];
      for (final s in bestaetigeUeberSerie(serie)) {
        expect(s.treffer, lessThanOrEqualTo(s.untersucht));
      }
    });

    test('leichte Abweichungen gelten als dieselbe Stelle', () {
      // Zwei Programme – hier: zwei Verkleinerungen – treffen die Mitte nie
      // auf denselben Punkt.
      final serie = [
        for (var i = 0; i < 6; i++)
          [Staubverdacht(x: 0.300 + i * 0.001, y: 0.220, radius: 0.01, tiefe: 20)],
      ];
      expect(bestaetigeUeberSerie(serie).length, 1);
    });

    test('weit auseinander liegende Stellen bleiben getrennt', () {
      final serie = [
        for (var i = 0; i < 6; i++)
          [
            const Staubverdacht(x: 0.20, y: 0.20, radius: 0.01, tiefe: 20),
            const Staubverdacht(x: 0.80, y: 0.80, radius: 0.01, tiefe: 20),
          ],
      ];
      expect(bestaetigeUeberSerie(serie).length, 2);
    });

    test('eine leere Serie ergibt nichts statt einer Ausnahme', () {
      expect(bestaetigeUeberSerie(const []), isEmpty);
      expect(bestaetigeUeberSerie([const [], const []]), isEmpty);
    });
  });

  group('Die Stichprobe', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> lege(String id, DateTime wann, {String kamera = 'EOS 60D'}) =>
        db.insertAsset(AssetsCompanion.insert(
          id: id,
          relativePath: 'originals/$id.jpg',
          originalFileName: '$id.jpg',
          type: 'IMAGE',
          fileSizeBytes: const Value(10),
          checksum: id,
          fileCreatedAt: wann,
          importedAt: wann,
          cameraModel: Value(kamera),
        ));

    test('verteilt sich über den ganzen Zeitraum, statt die neuesten zu nehmen', () async {
      // Staub kommt und geht mit dem Objektivwechsel. Vierzig Aufnahmen
      // desselben Nachmittags meldeten eine Reinigung von vor drei Jahren
      // als heutigen Befund.
      for (var i = 0; i < 100; i++) {
        await lege('a$i', DateTime(2020 + i ~/ 25, 1, 1 + i % 25));
      }
      final probe = await db.aufnahmenDerKamera('EOS 60D', 10);
      expect(probe.length, 10);
      final jahre = {for (final a in probe) a.fileCreatedAt.year};
      expect(jahre.length, greaterThan(1), reason: 'sonst wäre es ein Ausschnitt');
    });

    test('weniger Aufnahmen als gefragt kommen vollständig', () async {
      await lege('a', DateTime(2020));
      await lege('b', DateTime(2021));
      expect((await db.aufnahmenDerKamera('EOS 60D', 40)).length, 2);
    });

    test('eine andere Kamera bleibt draussen', () async {
      await lege('a', DateTime(2020));
      await lege('b', DateTime(2021), kamera: 'iPhone');
      final probe = await db.aufnahmenDerKamera('EOS 60D', 40);
      expect([for (final a in probe) a.id], ['a']);
    });
  });
}

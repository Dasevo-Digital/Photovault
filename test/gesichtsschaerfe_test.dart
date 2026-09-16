import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/blur_detection.dart';

/// `computeBlurScore` misst das GANZE Bild. Ein Porträt mit unscharfem
/// Gesicht vor scharfem Laub besteht diese Prüfung mühelos – und beim
/// Sichten ist genau das die Aufnahme, die man aussortieren will.
///
/// Die Schwelle stammt aus einer Messung an 1625 echten Ausschnitten dieser
/// Bibliothek (siehe [gesichtUnscharfSchwelle]); hier wird geprüft, dass die
/// Rechnung tut, was die Messung voraussetzt.

/// Ein Bild mit feiner, kontrastreicher Struktur – „scharf".
img.Image _scharf(int kante) {
  final bild = img.Image(width: kante, height: kante);
  for (var y = 0; y < kante; y++) {
    for (var x = 0; x < kante; x++) {
      final hell = ((x ~/ 2) + (y ~/ 2)) % 2 == 0 ? 240 : 15;
      bild.setPixelRgb(x, y, hell, hell, hell);
    }
  }
  return bild;
}

/// Dasselbe Motiv, weich gezeichnet – „unscharf".
img.Image _weich(int kante) => img.gaussianBlur(_scharf(kante), radius: 4);

/// Gleichmässig dunkel – kein Kontrast, aus einem anderen Grund als
/// Unschärfe.
img.Image _dunkel(int kante) {
  final bild = img.Image(width: kante, height: kante);
  img.fill(bild, color: img.ColorRgb8(12, 12, 12));
  return bild;
}

void main() {
  group('gesichtsschaerfe', () {
    test('trennt scharf von weich deutlich', () {
      final s = gesichtsschaerfe(_scharf(160));
      final w = gesichtsschaerfe(_weich(160));
      expect(s, greaterThan(gesichtUnscharfSchwelle));
      expect(w, lessThan(gesichtUnscharfSchwelle));
      expect(s, greaterThan(w * 10), reason: 'scharf=$s weich=$w');
    });

    test('ein dunkles Gesicht fällt ebenfalls durch – und das ist gewollt', () {
      // Steht so auch in der Doku der Schwelle: Ein Gesicht, das man nicht
      // erkennt, will man in beiden Fällen nicht behalten.
      expect(gesichtsschaerfe(_dunkel(160)), lessThan(gesichtUnscharfSchwelle));
    });

    test('die Schwelle liegt zwischen den gemessenen Zehnteln', () {
      // 10 % der echten Ausschnitte liegen unter 33,7, 25 % unter 80,1.
      // Eine Schwelle ausserhalb dieses Bandes wäre entweder wirkungslos
      // oder träfe jedes vierte Gesicht.
      expect(gesichtUnscharfSchwelle, greaterThan(33.7));
      expect(gesichtUnscharfSchwelle, lessThan(80.1));
    });

    test('160er-Ausschnitte sind untereinander vergleichbar', () {
      // Alle Ausschnitte sind 160x160 (FaceEngineService.cropFaceImage), also
      // greift die Verkleinerung auf 400 Punkte in computeBlurScore nicht ein
      // – zwei gleich aussehende Gesichter bekommen denselben Wert,
      // unabhängig davon, wie gross die Person im Original war.
      expect(gesichtsschaerfe(_scharf(160)), gesichtsschaerfe(_scharf(160)));
    });

    test('winzige Bilder ergeben null statt einer Ausnahme', () {
      expect(gesichtsschaerfe(img.Image(width: 2, height: 2)), 0);
    });
  });

  group('Das schärfste Gesicht zählt', () {
    /// Dieselbe Regel wie im Betrachter: Auf einem Gruppenbild ist hinten
    /// fast immer jemand weich, und das ist kein Grund, die Aufnahme
    /// wegzuwerfen.
    bool alleUnscharf(List<double?> werte) {
      final gemessen = [for (final w in werte) if (w != null) w];
      return gemessen.isNotEmpty &&
          gemessen.reduce(math.max) < gesichtUnscharfSchwelle;
    }

    test('ein scharfes Gesicht rettet die Aufnahme', () {
      expect(alleUnscharf([5.0, 8.0, 900.0]), isFalse);
    });

    test('sind alle weich, wird gewarnt', () {
      expect(alleUnscharf([5.0, 8.0, 20.0]), isTrue);
    });

    test('ohne gemessene Gesichter wird nicht gewarnt', () {
      expect(alleUnscharf([]), isFalse);
      expect(alleUnscharf([null, null]), isFalse);
    });
  });

  group('Was der Nachlauf aufgreift', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      // Die Gesichter hängen an echten Aufnahmen: Die Liste fragt seit der
      // 19. Prüfrunde mit, ob die Aufnahme gesperrt ist, und dafür braucht
      // sie die Zeile.
      for (final (id, gesperrt) in [('a', false), ('tresor', true)]) {
        await db.insertAsset(AssetsCompanion.insert(
          id: id,
          relativePath: 'originals/\$id.jpg',
          originalFileName: '\$id.jpg',
          type: 'IMAGE',
          checksum: id,
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2024),
          isLocked: Value(gesperrt),
        ));
      }
    });
    tearDown(() => db.close());

    Future<void> lege(String id,
            {String? ausschnitt, double? schaerfe, String aufnahme = 'a'}) =>
        db.into(db.faces).insert(FacesCompanion.insert(
              id: id,
              assetId: aufnahme,
              boxX: 0.1,
              boxY: 0.1,
              boxW: 0.2,
              boxH: 0.2,
              cropRelativePath: Value(ausschnitt),
              schaerfe: Value(schaerfe),
            ));

    test('nur Gesichter ohne Wert und MIT Ausschnitt', () async {
      await lege('offen', ausschnitt: 'faces/offen.jpg');
      await lege('fertig', ausschnitt: 'faces/fertig.jpg', schaerfe: 120);
      // Ohne Ausschnitt gäbe es nichts zu messen – so ein Gesicht stünde
      // sonst bei jedem Lauf erneut in der Liste.
      await lege('ohneBild');

      expect([for (final g in await db.gesichterOhneSchaerfe()) g.id], ['offen']);
      expect(await db.countGesichterOhneSchaerfe(), 1);
    });

    test('ein Gesicht auf einer gesperrten Aufnahme bleibt draussen', () async {
      // Sein Ausschnitt liegt als Chiffrat auf der Platte. `decodeImage`
      // gibt dafür null zurück, der Wert bliebe leer – und die Aufgabe
      // fände dasselbe Gesicht bei jedem Lauf erneut. Eine
      // Hintergrundaufgabe, die dauerhaft „noch 1 offen" meldet und nie
      // fertig wird, ist schlimmer als keine.
      await lege('offen', ausschnitt: 'faces/offen.jpg');
      await lege('gesperrt',
          ausschnitt: 'faces/gesperrt.jpg', aufnahme: 'tresor');

      expect([for (final g in await db.gesichterOhneSchaerfe()) g.id], ['offen']);
      expect(await db.countGesichterOhneSchaerfe(), 1);
    });

    test('setzen entfernt es aus der Liste', () async {
      await lege('offen', ausschnitt: 'faces/offen.jpg');
      await db.setzeGesichtsschaerfe('offen', 42.5);
      expect(await db.countGesichterOhneSchaerfe(), 0);
      final gesicht = (await db.facesForAsset('a')).single;
      expect(gesicht.schaerfe, 42.5);
    });
  });
}

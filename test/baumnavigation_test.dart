import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/baumnavigation.dart';

/// Das Verschieben und Zoomen des Zierbaums – als reine Rechnung.
///
/// **Warum das überhaupt eine eigene Rechnung ist.** Der Baum hing in
/// zwei ineinandergesteckten Rollbereichen. Verschieben ging damit nur
/// über die Rollbalken oder ein Rad, Zoomen gar nicht: Ein Baum mit
/// angeheirateter Verwandtschaft ist breiter als jedes Fenster, und man
/// bekam ihn nie ganz zu sehen.
void main() {
  Offset punkt(Matrix4 blick, Offset baumstelle) =>
      baumImFenster(blick, baumstelle);

  group('zoomen', () {
    test('der Drehpunkt bleibt, wo er ist', () {
      // DIE Eigenschaft. Ohne sie wächst der Baum aus der linken oberen
      // Ecke heraus, und was man gerade ansieht, rutscht aus dem Bild.
      final vorher = Matrix4.identity();
      const drehpunkt = Offset(400, 300);
      final nachher = baumGezoomt(vorher, 2.0, drehpunkt);
      expect(punkt(nachher, drehpunkt).dx, closeTo(drehpunkt.dx, 0.001));
      expect(punkt(nachher, drehpunkt).dy, closeTo(drehpunkt.dy, 0.001));
    });

    test('alles andere rückt vom Drehpunkt weg', () {
      // Gegenprobe zur Zeile darüber: Bliebe alles stehen, wäre nichts
      // gezoomt.
      final nachher = baumGezoomt(Matrix4.identity(), 2.0, const Offset(400, 300));
      expect(punkt(nachher, const Offset(500, 300)).dx, closeTo(600, 0.001));
      expect(baumzoomAus(nachher), closeTo(2.0, 0.001));
    });

    test('an der Grenze bewegt sich nichts', () {
      // Nicht „ein bisschen weniger als gewünscht": Eine Verschiebung
      // ohne Vergrösserung sähe aus, als sei der Baum verrutscht.
      final ganzNah = baumGezoomt(Matrix4.identity(), 100, Offset.zero);
      expect(baumzoomAus(ganzNah), groessterBaumzoom);
      expect(baumGezoomt(ganzNah, 2.0, const Offset(10, 10)), same(ganzNah));

      final ganzWeit = baumGezoomt(Matrix4.identity(), 0.001, Offset.zero);
      expect(baumzoomAus(ganzWeit), kleinsterBaumzoom);
      expect(baumGezoomt(ganzWeit, 0.5, const Offset(10, 10)), same(ganzWeit));
    });

    test('Schritte bauen aufeinander auf', () {
      var blick = Matrix4.identity();
      for (var i = 0; i < 3; i++) {
        blick = baumGezoomt(blick, baumZoomschritt, const Offset(100, 100));
      }
      expect(baumzoomAus(blick), closeTo(baumZoomschritt * baumZoomschritt * baumZoomschritt, 0.001));
    });
  });

  group('einpassen', () {
    test('ein zu breiter Baum wird kleiner und steht mittig', () {
      // Der gemessene Fall: 3400 Punkte Baum in einem 1200 Punkte
      // breiten Fenster.
      final blick = baumEingepasst(const Size(3400, 900), const Size(1200, 800));
      expect(baumzoomAus(blick), closeTo(1200 / 3400, 0.001));
      // Links oben im Baum landet oben, aber senkrecht eingemittet.
      final ecke = punkt(blick, Offset.zero);
      expect(ecke.dx, closeTo(0, 0.001));
      expect(ecke.dy, closeTo((800 - 900 * 1200 / 3400) / 2, 0.001));
      // Und rechts unten liegt noch im Fenster.
      expect(punkt(blick, const Offset(3400, 900)).dx, closeTo(1200, 0.001));
    });

    test('ein kleiner Baum wird nicht aufgeblasen', () {
      // „Einpassen" heisst „ganz zeigen", nicht „ausfüllen". Aufgeblasen
      // franst die Schrift, und die Porträts werden matschig.
      final blick = baumEingepasst(const Size(400, 300), const Size(1200, 800));
      expect(baumzoomAus(blick), 1.0);
      expect(punkt(blick, const Offset(200, 150)).dx, closeTo(600, 0.001));
      expect(punkt(blick, const Offset(200, 150)).dy, closeTo(400, 0.001));
    });

    test('ein leerer Baum ergibt keine Division durch null', () {
      expect(baumEingepasst(Size.zero, const Size(1200, 800)),
          Matrix4.identity());
    });
  });

  group('der erste Blick', () {
    test('ein kleiner Baum steht als Ganzes in der Mitte', () {
      // Der Familienname steht unten am Stamm und gehört zum Bild. Wer
      // nur auf das Schild der Mitte rückte, schnitte ihn ab.
      final blick = baumErsterBlick(
        baum: const Size(600, 400),
        fenster: const Size(1000, 700),
        fokusSchild: const Rect.fromLTWH(260, 300, 80, 60),
      );
      expect(punkt(blick, const Offset(300, 200)).dx, closeTo(500, 0.001));
      expect(punkt(blick, const Offset(300, 200)).dy, closeTo(350, 0.001));
    });

    test('bei einem breiten Baum rückt die Mitte ins Bild', () {
      // Vorher begann der Ausschnitt links oben – bei irgendeinem
      // Urgrossvater. Die Person, die man aufgeschlagen hat, musste man
      // erst suchen.
      const schild = Rect.fromLTWH(2800, 500, 120, 90);
      final blick = baumErsterBlick(
        baum: const Size(3400, 900),
        fenster: const Size(1000, 700),
        fokusSchild: schild,
      );
      expect(punkt(blick, schild.center).dx, closeTo(500, 0.001));
      expect(punkt(blick, schild.center).dy, closeTo(350, 0.001));
      // Und zwar in voller Grösse – nicht eingepasst.
      expect(baumzoomAus(blick), 1.0);
    });

    test('knapp am Rand zählt als draussen', () {
      // Gegenprobe zur Regel darüber: Die Entscheidung fällt am Schild,
      // nicht an der Baumbreite. Dieser Baum ist nur wenig breiter als
      // das Fenster, sein Fokusschild liegt aber ganz aussen.
      const schild = Rect.fromLTWH(1050, 100, 100, 60);
      final blick = baumErsterBlick(
        baum: const Size(1200, 400),
        fenster: const Size(1000, 700),
        fokusSchild: schild,
      );
      expect(punkt(blick, schild.center).dx, closeTo(500, 0.001));
    });
  });

  group('zentrieren', () {
    test('die Stelle landet in der Fenstermitte', () {
      final blick = baumZentriert(const Offset(2000, 400), const Size(1200, 800), 0.5);
      expect(punkt(blick, const Offset(2000, 400)).dx, closeTo(600, 0.001));
      expect(punkt(blick, const Offset(2000, 400)).dy, closeTo(400, 0.001));
    });

    test('der Zoom bleibt, wie er war', () {
      // Beim Umsetzen der Mitte soll sich der Ausschnitt verschieben und
      // nicht zugleich die Grösse ändern – zwei Änderungen auf einmal
      // sind eine zu viel, um sie zu verfolgen.
      expect(baumzoomAus(baumZentriert(const Offset(10, 10), const Size(800, 600), 0.75)),
          closeTo(0.75, 0.001));
    });
  });
}

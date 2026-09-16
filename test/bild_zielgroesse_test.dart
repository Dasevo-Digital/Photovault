import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/develop_render.dart';

/// Auf welche Grösse das Ausgangsbild beim Entwickeln dekodiert wird.
///
/// Der Anlass war eine Messung: Um die Zielgrösse auszurechnen, wurde das
/// Bild vorher einmal vollständig dekodiert und nachgemessen. An einem
/// 24-Megapixel-JPEG kostete das 348 ms und 96 MB, für eine Angabe, die
/// in 3 ms im Dateikopf steht.
void main() {
  ui.TargetImageSize ziel(int b, int h, int max) =>
      DevelopRender.zielGroesse(breite: b, hoehe: h, maxKante: max);

  test('Querformat: die Breite wird begrenzt', () {
    final z = ziel(6000, 4000, 1600);
    expect(z.width, 1600);
    expect(z.height, isNull,
        reason: 'die Hoehe rechnet der Dekoder seitenverhaeltnistreu nach - '
            'beide anzugeben verzerrte das Bild');
  });

  test('Hochformat: die Hoehe wird begrenzt', () {
    final z = ziel(4000, 6000, 1600);
    expect(z.height, 1600);
    expect(z.width, isNull);
  });

  test('Quadrat zaehlt als Querformat, nicht als Sonderfall', () {
    // Bei gleicher Kantenlaenge ist es gleichgueltig, welche begrenzt
    // wird - solange genau EINE begrenzt wird.
    final z = ziel(3000, 3000, 1600);
    expect(z.width, 1600);
    expect(z.height, isNull);
  });

  test('kleiner als das Ziel bleibt unveraendert', () {
    // Hochrechnen brächte keine Bildinformation, kostete aber Speicher -
    // und aus einem 800er Bild wuerde ein 1600er, das nur weicher aussieht.
    final z = ziel(800, 600, 1600);
    expect(z.width, isNull);
    expect(z.height, isNull);
  });

  test('genau auf der Grenze bleibt unveraendert', () {
    // Der Randfall, der am leichtesten falsch herauskommt: `<` statt `<=`
    // liesse hier einen ueberfluessigen Skalierlauf ueber ein Bild
    // laufen, das bereits die richtige Groesse hat.
    final z = ziel(1600, 1200, 1600);
    expect(z.width, isNull);
    expect(z.height, isNull);
  });

  test('sehr schmale Bilder werden an der langen Kante gemessen', () {
    // Ein Panorama: 12000 x 800. Wuerde die kurze Kante entscheiden,
    // bliebe es bei 12000 Punkten Breite - 38 MB statt 5 MB.
    final z = ziel(12000, 800, 1600);
    expect(z.width, 1600);
    expect(z.height, isNull);
  });
}

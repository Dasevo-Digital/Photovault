/// **Die Blöcke, aus denen die scharfe Landschaft entsteht.**
///
/// Reine Rechnung – kein Netz, keine Bilder. Siehe
/// [gelaendetextur.dart] für den Grund, warum es Blöcke gibt.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendetextur.dart';

/// Der Ausschnitt der echten Wanderung durch das Ilsetal, an der auch
/// die Zahlen in der Beschreibung gemessen sind.
const _sued = 51.8286, _nord = 51.8580, _west = 10.6348, _ost = 10.6758;

void main() {
  group('Blockeinteilung', () {
    test('die Blöcke decken den Ausschnitt vollständig ab', () {
      final b = texturbloecke(
          sued: _sued, west: _west, nord: _nord, ost: _ost);
      expect(b, isNotEmpty);
      final west = b.map((x) => x.west).reduce((a, c) => a < c ? a : c);
      final ost = b.map((x) => x.ost).reduce((a, c) => a > c ? a : c);
      final nord = b.map((x) => x.nord).reduce((a, c) => a > c ? a : c);
      final sued = b.map((x) => x.sued).reduce((a, c) => a < c ? a : c);
      expect(west, lessThanOrEqualTo(_west));
      expect(ost, greaterThanOrEqualTo(_ost));
      expect(nord, greaterThanOrEqualTo(_nord));
      expect(sued, lessThanOrEqualTo(_sued));
    });

    test('und sie überlappen sich nicht', () {
      // Zwei Blöcke derselben Zeile stossen genau aneinander: Die
      // Ostkante des einen ist die Westkante des nächsten. Genau davon
      // lebt die Rechnung - überlappten sie, sähe man die Naht.
      final b = texturbloecke(
          sued: _sued, west: _west, nord: _nord, ost: _ost);
      final ersteZeile = b.where((x) => x.zeile == b.first.zeile).toList();
      expect(ersteZeile.length, greaterThan(1));
      for (var i = 1; i < ersteZeile.length; i++) {
        expect(ersteZeile[i].west, closeTo(ersteZeile[i - 1].ost, 1e-12));
      }
      final ersteSpalte = b.where((x) => x.spalte == b.first.spalte).toList();
      for (var i = 1; i < ersteSpalte.length; i++) {
        expect(ersteSpalte[i].nord, closeTo(ersteSpalte[i - 1].sued, 1e-12));
      }
    });

    test('ein Block ist auf der Grundstufe genau eine Kachel', () {
      const b = Texturblock(spalte: 34161, zeile: 21895, grundstufe: 16);
      expect(b.kachelnJeKante(16), 1);
      expect(b.kacheln(16), hasLength(1));
      expect(b.kacheln(16).single, (z: 16, x: 34161, y: 21895));
      expect(b.texturkante(16), kachelKante);
    });

    test('eine Stufe feiner sind es vier Kacheln, zwei feiner sechzehn', () {
      const b = Texturblock(spalte: 3, zeile: 5, grundstufe: 16);
      expect(b.kacheln(17), hasLength(4));
      expect(b.kacheln(18), hasLength(16));
      // Und sie liegen an der richtigen Stelle: Der Nordwestzipfel des
      // Blocks ist die Kachel (2*spalte, 2*zeile).
      expect(b.kacheln(17).first, (z: 17, x: 6, y: 10));
      expect(b.kacheln(18).first, (z: 18, x: 12, y: 20));
      expect(b.kacheln(18).last, (z: 18, x: 15, y: 23));
    });

    test('die Kacheln eines Blocks liegen wirklich in ihm drin', () {
      const b = Texturblock(spalte: 34161, zeile: 21895, grundstufe: 16);
      for (final k in b.kacheln(18)) {
        expect(kachelWesten(k.x, 18), greaterThanOrEqualTo(b.west - 1e-9));
        expect(kachelWesten(k.x + 1, 18), lessThanOrEqualTo(b.ost + 1e-9));
        expect(kachelNorden(k.y, 18), lessThanOrEqualTo(b.nord + 1e-9));
        expect(kachelNorden(k.y + 1, 18), greaterThanOrEqualTo(b.sued - 1e-9));
      }
    });

    test('was ein Block im Speicher kostet', () {
      const b = Texturblock(spalte: 0, zeile: 0, grundstufe: 16);
      expect(b.speicherBytes(16), 256 * 256 * 4);
      expect(b.speicherBytes(17), 512 * 512 * 4);
      expect(b.speicherBytes(18), 1024 * 1024 * 4);
      // Vier Megabyte bei der feinsten Stufe - die Zahl, an der die
      // Obergrenze von 18 haengt.
      expect(b.speicherBytes(18), 4 * 1024 * 1024);
    });
  });

  group('Stufenwahl nach Entfernung', () {
    // Die Kamera des Fluges: Brennweite 900 Bildpunkte, Harzer Breite.
    const brennweite = 900.0;
    const breite = 51.84;

    test('nah ist fein, fern ist grob', () {
      final nah = blockstufe(
          entfernungMeter: 200, brennweite: brennweite, breite: breite);
      final mittel = blockstufe(
          entfernungMeter: 1500, brennweite: brennweite, breite: breite);
      final fern = blockstufe(
          entfernungMeter: 9000, brennweite: brennweite, breite: breite);
      expect(nah, greaterThan(mittel));
      expect(mittel, greaterThan(fern));
      expect(nah, texturHoechsteStufe);
      // In neun Kilometern deckt ein Bildpunkt zehn Meter ab - da ist
      // selbst Stufe 14 noch feiner als noetig. Genau deshalb wird nach
      // unten nicht auf die Grundstufe geklemmt.
      expect(fern, lessThan(texturGrundstufe));
    });

    test('die gewählte Stufe ist wirklich fein genug', () {
      // Die Probe aufs Exempel: Was ein Bildpunkt in dieser Entfernung
      // abdeckt, muss mindestens so gross sein wie ein Texturpunkt -
      // sonst waere das Bild sichtbar unscharf.
      for (final d in [150.0, 400.0, 900.0, 2000.0, 5000.0]) {
        final z = blockstufe(
            entfernungMeter: d, brennweite: brennweite, breite: breite);
        final jeBildpunkt = d / brennweite;
        if (z < texturHoechsteStufe) {
          expect(kachelAufloesung(breite, z), lessThanOrEqualTo(jeBildpunkt),
              reason: 'bei $d m ist Stufe $z zu grob');
        }
        // Und nicht unnötig fein: eine Stufe gröber wäre zu grob.
        if (z > texturGrundstufe) {
          expect(kachelAufloesung(breite, z - 1),
              greaterThan(jeBildpunkt),
              reason: 'bei $d m waere Stufe ${z - 1} auch noch gut genug');
        }
      }
    });

    test('die doppelte Punktdichte fordert eine Stufe mehr', () {
      final einfach = blockstufe(
          entfernungMeter: 2000, brennweite: brennweite, breite: breite);
      final doppelt = blockstufe(
          entfernungMeter: 2000,
          brennweite: brennweite,
          breite: breite,
          schaerfe: 2);
      // Doppelt so scharf ist genau eine Kachelstufe - solange die
      // Obergrenze nicht dazwischenkommt.
      expect(doppelt, einfach + 1);
    });

    test('die Grenzen halten', () {
      expect(
          blockstufe(
              entfernungMeter: 1, brennweite: brennweite, breite: breite),
          texturHoechsteStufe);
      // Aus fuenftausend Kilometern deckt ein Bildpunkt 5,5 km ab; die
      // groebste Stufe, die dafuer noch reicht, ist 5. Die Regel gilt
      // also auch da, wo sie unsinnig weit ausserhalb liegt - sie klemmt
      // nicht auf null, weil sie nichts erfindet.
      final weit = blockstufe(
          entfernungMeter: 5000000, brennweite: brennweite, breite: breite);
      expect(weit, lessThan(texturGrundstufe));
      expect(kachelAufloesung(breite, weit),
          lessThanOrEqualTo(5000000 / brennweite));
      expect(kachelAufloesung(breite, weit - 1),
          greaterThan(5000000 / brennweite));
      // Unsinnige Angaben ergeben etwas Brauchbares statt einer Ausnahme.
      expect(
          blockstufe(
              entfernungMeter: double.nan,
              brennweite: brennweite,
              breite: breite),
          texturHoechsteStufe);
      // Ohne Brennweite gibt es keine Rechnung - dann die groebste
      // Stufe, statt einer Ausnahme oder einer erfundenen Schaerfe.
      expect(
          blockstufe(entfernungMeter: 1000, brennweite: 0, breite: breite),
          0);
    });
  });

  test('am Ilsetal: wie viele Blöcke, wie viel Speicher', () {
    final b = texturbloecke(sued: _sued, west: _west, nord: _nord, ost: _ost);
    // Acht mal zehn Kacheln der Stufe 16 - dieselbe Zahl wie in der
    // Messung, die den Umbau ausgeloest hat.
    expect(b.length, 80);
    // Alle auf der feinsten Stufe waeren 320 MB. Genau deshalb gibt es
    // den Vorrat mit Deckel und die Stufenwahl nach Entfernung.
    final alles = b.fold<int>(0, (s, x) => s + x.speicherBytes(18));
    expect(alles ~/ (1024 * 1024), 320);
  });
}

@Tags(['netz'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_vault/services/gelaende_laden.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';

/// Sonde am echten Kachelserver – die Messung, auf der diese Stufe
/// steht.
///
/// Läuft nicht in der normalen Suite (Marke `netz`), sondern auf Zuruf:
///
///   flutter test --tags netz --run-skipped test/gelaende_netz_probe_test.dart
///
/// **Warum sie überhaupt existiert:** Die Formel
/// `r · 256 + g + b/256 − 32768` ist abgeschrieben, wenn niemand sie
/// gegen ein bekanntes Gelände hält. Der Taufstein im Vogelsberg misst
/// 773 m, die Talsohlen ringsum liegen um 340 – kommt das heraus, stimmt
/// beides: Formel und Adresse.
void main() {
  test('die Kachel des Vogelsbergs ergibt seine Höhen', () async {
    final netz = http.Client();
    addTearDown(netz.close);

    // Genau die Kachel 11/1080/689 – ein Ausschnitt darin.
    final west = kachelWesten(1080, 11);
    final ost = kachelWesten(1081, 11);
    final nord = kachelNorden(689, 11);
    final sued = kachelNorden(690, 11);

    final gitter = await ladeHoehengitter(
      sued: sued + (nord - sued) * 0.01,
      west: west + (ost - west) * 0.01,
      nord: nord - (nord - sued) * 0.01,
      ost: ost - (ost - west) * 0.01,
      netz: netz,
      hoechsteStufe: 11,
      hoechstensKacheln: 1,
    );

    expect(gitter, isNotNull, reason: 'keine Kachel angekommen');
    final spanne = gitter!.spanne;
    // ignore: avoid_print
    print('Vogelsberg 11/1080/689: '
        '${spanne.tief.toStringAsFixed(1)} bis '
        '${spanne.hoch.toStringAsFixed(1)} m, '
        '${gitter.spalten}x${gitter.zeilen} Punkte');

    // Der Taufstein misst 773 m, die Talsohlen liegen um 340.
    expect(spanne.tief, closeTo(337, 30));
    expect(spanne.hoch, closeTo(800, 40));
    expect(gitter.spalten, kachelKante);
  });

  test('die Karte zum selben Ausschnitt kommt auch an', () async {
    final netz = http.Client();
    addTearDown(netz.close);
    final bild = await ladeKartenbild(
      sued: 50.55,
      west: 9.86,
      nord: 50.60,
      ost: 9.92,
      netz: netz,
      hoechsteStufe: 11,
      hoechstensKacheln: 4,
    );
    expect(bild, isNotNull);
    // ignore: avoid_print
    print('Kartenbild: ${bild!.width}x${bild.height}');
    expect(bild.width % kachelKante, 0);
    bild.dispose();
  });
}

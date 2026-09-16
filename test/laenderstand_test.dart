import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/laenderkatalog.dart';
import 'package:photo_vault/services/reisefortschritt.dart';

Landeintragung _l(String iso, String name, int regionen,
        {String erdteil = 'EU'}) =>
    (
      iso: iso,
      name: name,
      nameDe: name,
      hauptstadt: '$name-Stadt',
      kontinent: erdteil,
      regionen: regionen
    );

const _katalog = [
  (iso: 'DE', name: 'Germany', nameDe: 'Deutschland', hauptstadt: 'Berlin', kontinent: 'EU', regionen: 3),
  (iso: 'MC', name: 'Monaco', nameDe: 'Monaco', hauptstadt: 'Monaco', kontinent: 'EU', regionen: 0),
  (iso: 'PL', name: 'Poland', nameDe: 'Polen', hauptstadt: 'Warsaw', kontinent: 'EU', regionen: 2),
];

const _nachIso = {'Germany': 'DE', 'Monaco': 'MC', 'Poland': 'PL'};
const _regionscodes = {
  'DE|Hamburg': 'DE.04',
  'DE|Bavaria': 'DE.02',
  'DE|Berlin': 'DE.16',
  'PL|Masovia': 'PL.07',
};

List<Landstand> _stand({
  List<Besuchsangabe> angaben = const [],
  List<Markeneintrag> marken = const [],
}) =>
    laenderstand(
      angaben: angaben,
      katalog: _katalog,
      nachIso: _nachIso,
      regionscodes: _regionscodes,
      marken: marken,
    );

Landstand _finde(List<Landstand> alle, String iso) =>
    alle.firstWhere((l) => l.iso == iso);

void main() {
  test('ohne alles ist jedes Land „nicht besucht"', () {
    final alle = _stand();
    expect(alle.length, 3);
    expect(alle.every((l) => l.grad == Besuchsgrad.nicht), isTrue);
    expect(alle.every((l) => !l.besucht), isTrue);
  });

  test('Fotos aus zwei von drei Regionen ergeben „teilweise"', () {
    final de = _finde(
        _stand(angaben: const [
          (land: 'Germany', region: 'Hamburg', ort: 'Hamburg', anzahl: 5),
          (land: 'Germany', region: 'Bavaria', ort: 'Munich', anzahl: 9),
        ]),
        'DE');
    expect(de.aufnahmen, 14);
    expect(de.regionenBesucht, 2);
    expect(de.regionenGesamt, 3);
    expect(de.orte, 2);
    expect(de.grad, Besuchsgrad.teilweise);
  });

  test('alle Regionen belegt ergibt „vollständig"', () {
    final de = _finde(
        _stand(angaben: const [
          (land: 'Germany', region: 'Hamburg', ort: null, anzahl: 1),
          (land: 'Germany', region: 'Bavaria', ort: null, anzahl: 1),
          (land: 'Germany', region: 'Berlin', ort: null, anzahl: 1),
        ]),
        'DE');
    expect(de.grad, Besuchsgrad.vollstaendig);
  });

  test('ein Land ohne verzeichnete Regionen ist mit dem ersten Foto fertig', () {
    final mc = _finde(
        _stand(angaben: const [
          (land: 'Monaco', region: null, ort: 'Monaco', anzahl: 1),
        ]),
        'MC');
    expect(mc.regionenGesamt, 0);
    expect(mc.grad, Besuchsgrad.vollstaendig);
  });

  test('„geplant" ist kein Besuch', () {
    final pl = _finde(
        _stand(marken: const [
          (art: 'land', schluessel: 'PL', wert: Markenart.geplant),
        ]),
        'PL');
    expect(pl.marke, Markenart.geplant);
    expect(pl.besucht, isFalse);
    expect(pl.grad, Besuchsgrad.nicht);
  });

  test('eine gesetzte Landmarke „besucht" zählt ohne ein einziges Foto', () {
    final pl = _finde(
        _stand(marken: const [
          (art: 'land', schluessel: 'PL', wert: Markenart.besucht),
        ]),
        'PL');
    expect(pl.aufnahmen, 0);
    expect(pl.besucht, isTrue);
    // Ohne Regionsbeleg bleibt es „teilweise" – die Marke sagt „ich war
    // dort", nicht „ich war ueberall dort".
    expect(pl.grad, Besuchsgrad.teilweise);
  });

  test('eine Regionsmarke schiebt den Regionenfortschritt', () {
    final pl = _finde(
        _stand(marken: const [
          (art: 'region', schluessel: 'PL.07', wert: Markenart.besucht),
        ]),
        'PL');
    expect(pl.regionenBesucht, 1);
    expect(pl.grad, Besuchsgrad.teilweise);
  });

  test('Foto und Regionsmarke derselben Region zaehlen einmal', () {
    // Der Kern: Das Foto kennt „Masovia", die Marke kennt „PL.07". Ohne
    // die Uebersetzung waeren das zwei Regionen von zweien – und Polen
    // waere faelschlich vollstaendig.
    final pl = _finde(
        _stand(
          angaben: const [
            (land: 'Poland', region: 'Masovia', ort: 'Warsaw', anzahl: 3),
          ],
          marken: const [
            (art: 'region', schluessel: 'PL.07', wert: Markenart.besucht),
          ],
        ),
        'PL');
    expect(pl.regionenBesucht, 1);
    expect(pl.grad, Besuchsgrad.teilweise);
  });

  test('eine geplante Region zaehlt nicht als Beleg', () {
    final pl = _finde(
        _stand(marken: const [
          (art: 'region', schluessel: 'PL.07', wert: Markenart.geplant),
        ]),
        'PL');
    expect(pl.regionenBesucht, 0);
    expect(pl.grad, Besuchsgrad.nicht);
  });

  test('eine Ortsmarke belegt Ort und Region zugleich', () {
    final pl = _finde(
        _stand(marken: const [
          (art: 'ort', schluessel: 'Poland|Masovia|Warsaw', wert: Markenart.besucht),
        ]),
        'PL');
    expect(pl.orte, 1);
    expect(pl.regionenBesucht, 1);
  });

  test('ein unbekanntes Land faellt heraus, statt zu werfen', () {
    final alle = _stand(angaben: const [
      (land: 'Atlantis', region: null, ort: null, anzahl: 7),
    ]);
    expect(alle.every((l) => l.aufnahmen == 0), isTrue);
  });

  test('Hauptstadt und Erdteil kommen aus dem Katalog durch', () {
    final de = _finde(_stand(), 'DE');
    expect(de.hauptstadt, 'Berlin');
    expect(de.kontinent, 'EU');
    expect(_l('XX', 'Test', 1).regionen, 1);
  });

  test('eine Ortsmarke ohne Region zählt trotzdem als Ort', () {
    // 24 der 252 Länder haben keine verzeichnete Region. Ein Zerleger, der
    // solche Marken verwirft, weil er auf eine Region wartet, streicht
    // genau diese Orte aus dem Zähler – lautlos.
    final mc = _stand(marken: [
      (art: 'ort', schluessel: 'Monaco||Monte-Carlo', wert: Markenart.besucht),
    ]).firstWhere((l) => l.iso == 'MC');
    expect(mc.orte, 1);
    expect(mc.regionenBesucht, 0,
        reason: 'Monaco hat keine Region, die belegt werden könnte');
    // Und genau deshalb muss der Ort selbst reichen: Wer Monte-Carlo
    // abhakt und Monaco danach als unbesucht vorfindet, findet dafür keine
    // Erklärung.
    expect(mc.besucht, isTrue);
    expect(mc.grad, Besuchsgrad.vollstaendig);
  });
}

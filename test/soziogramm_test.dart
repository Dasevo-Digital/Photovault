import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/soziogramm.dart';

/// Das Soziogramm: wer mit wem auf Fotos ist.
void main() {
  List<({String personId, String assetId})> auf(
    Map<String, List<String>> jeFoto,
  ) => [
    for (final MapEntry(key: foto, value: personen) in jeFoto.entries)
      for (final p in personen) (personId: p, assetId: foto),
  ];

  test('gezählt werden gemeinsame Fotos, nicht Gesichter', () {
    final netz = soziogramm(
      auf({
        'f1': ['anna', 'bernd', 'bernd'],
        'f2': ['anna', 'bernd'],
        'f3': ['anna', 'clara'],
      }),
    );
    expect(netz.kanten, hasLength(1), reason: 'Anna–Clara nur einmal');
    expect(netz.kanten.single, (a: 'anna', b: 'bernd', fotos: 2));
    expect(netz.personen, {'anna': 3, 'bernd': 2});
  });

  test('nur die Personen mit den meisten Fotos', () {
    final netz = soziogramm(
      auf({
        for (var i = 0; i < 5; i++) 'a$i': ['viel', 'mittel'],
        'b1': ['wenig', 'viel'],
        'b2': ['wenig', 'viel'],
      }),
      hoechstens: 2,
    );
    expect(netz.personen.keys.toSet(), {'viel', 'mittel'});
  });

  test('die stärkste Linie zuerst', () {
    final netz = soziogramm(
      auf({
        for (var i = 0; i < 2; i++) 'x$i': ['a', 'b'],
        for (var i = 0; i < 4; i++) 'y$i': ['a', 'c'],
      }),
    );
    expect(netz.kanten.first, (a: 'a', b: 'c', fotos: 4));
  });

  test('die Anordnung ist fest, im Quadrat, und Verbundene liegen näher', () {
    final netz = soziogramm(
      auf({
        for (var i = 0; i < 8; i++) 'eng$i': ['a', 'b'],
        'lose1': ['a', 'c'],
        'lose2': ['a', 'c'],
        'fern1': ['c', 'd'],
        'fern2': ['c', 'd'],
      }),
    );
    final eins = soziogrammAnordnung(netz);
    final zwei = soziogrammAnordnung(netz);
    expect(eins, zwei);
    for (final p in eins.values) {
      expect(p.dx, inInclusiveRange(0.0, 1.0));
      expect(p.dy, inInclusiveRange(0.0, 1.0));
    }
    expect(
      (eins['a']! - eins['b']!).distance,
      lessThan((eins['b']! - eins['d']!).distance),
    );
  });

  test('ohne gemeinsame Fotos ist das Netz leer', () {
    final netz = soziogramm(
      auf({
        'f1': ['anna'],
        'f2': ['bernd'],
      }),
    );
    expect(netz.istLeer, isTrue);
    expect(soziogrammAnordnung(netz), isEmpty);
  });
}

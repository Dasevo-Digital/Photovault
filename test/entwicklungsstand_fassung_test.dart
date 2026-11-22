import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/entwicklungsvariante.dart';

/// Ein Variantenstand trägt seine Fassung selbst (#466): Fassung 1 hat die
/// Temperatur in der früheren Bedeutung und kommt beim Lesen umgerechnet
/// heraus; Fassung 2 bleibt, wie sie ist. So liest sich ein Stand aus der
/// Datenbank genauso wie einer aus einer alten Sicherung, und keiner wird
/// zweimal umgerechnet.
void main() {
  DevelopSettingsData einstellungen(double? t) => DevelopSettingsData(
    assetId: 'a',
    exposure: 0.5,
    temperature: t,
    tint: t == null ? null : 12,
    contrast: 0,
    shadows: 0,
    highlights: 0,
    sharpness: 0,
    noiseReduction: 0,
    lensCorrectionEnabled: true,
    clarity: 0,
    vignette: 0,
    lutStrength: 1,
    updatedAt: DateTime.utc(2026, 11, 22),
  );
  DevelopMaskData maske(double? t) => DevelopMaskData(
    id: 7,
    assetId: 'a',
    maskRelativePath: 'masks/m.png',
    label: 'Himmel',
    exposure: 0,
    temperature: t,
    tint: null,
    contrast: 0,
    shadows: 0,
    highlights: 0,
    sharpness: 0,
    noiseReduction: 0,
    lensCorrectionEnabled: true,
    createdAt: DateTime.utc(2026, 11, 22),
  );
  String text(
    double? t,
    double? m, {
    int fassung = Entwicklungsstand.fassung,
  }) =>
      Entwicklungsstand(
        'a' * 64,
        einstellungen(t),
        [maske(m)],
        {'masks/m.png': 'b' * 64},
      ).encode().replaceFirst(
        '"fassung":${Entwicklungsstand.fassung}',
        '"fassung":$fassung',
      );

  test('neu geschrieben ist Fassung 2', () {
    expect(Entwicklungsstand.fassung, 2);
    expect(text(4000, null), contains('"fassung":2'));
  });

  test('Fassung 1 kommt umgerechnet heraus', () {
    final s = Entwicklungsstand.decode(text(4000, 12000, fassung: 1));
    expect(s.einstellungen.temperature, 10562.5);
    expect(s.einstellungen.tint, 12);
    expect(s.einstellungen.exposure, 0.5);
    expect(s.masken.single.temperature, 42250000 / 12000);
  });

  test('Fassung 2 bleibt, und hin und zurück ändert nichts', () {
    final s = Entwicklungsstand.decode(text(4000, 12000));
    expect(s.einstellungen.temperature, 4000);
    expect(s.masken.single.temperature, 12000);
    final wieder = Entwicklungsstand.decode(s.encode());
    expect(wieder.einstellungen.temperature, 4000);
  });

  test('Automatik bleibt Automatik', () {
    final s = Entwicklungsstand.decode(text(null, null, fassung: 1));
    expect(s.einstellungen.temperature, isNull);
    expect(s.masken.single.temperature, isNull);
  });

  test('eine unbekannte Fassung wird abgelehnt', () {
    expect(
      () => Entwicklungsstand.decode(text(4000, null, fassung: 3)),
      throwsFormatException,
    );
  });
}

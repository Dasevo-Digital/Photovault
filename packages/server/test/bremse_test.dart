import 'package:photo_vault_server/src/konten/bremse.dart';
import 'package:test/test.dart';

/// Die Bremse je Adresse und je unbekanntem Namen (#426): Auch nach sehr
/// vielen Adressen zählt sie weiter, und Abgelaufenes vergisst sie.
void main() {
  var jetzt = DateTime.utc(2026, 11, 22, 12);
  setUp(() => jetzt = DateTime.utc(2026, 11, 22, 12));

  test('nach mehr als 10 000 Adressen bremst sie die nächste trotzdem', () {
    final b = Bremse(uhr: () => jetzt);
    for (var i = 0; i <= Bremse.hoechstensEintraege; i++) {
      b
        ..wartezeit('a$i')
        ..fehlschlag('a$i');
    }
    for (var i = 0; i < b.jeAdresse; i++) {
      expect(b.wartezeit('ich'), isNull);
      b.fehlschlag('ich');
    }
    expect(b.wartezeit('ich'), isNotNull);
  });

  test('abgelaufene Fehlschläge anderer Adressen machen Platz', () {
    final b = Bremse(uhr: () => jetzt);
    for (var i = 0; i < Bremse.hoechstensEintraege; i++) {
      b.fehlschlag('alt$i');
    }
    jetzt = jetzt.add(b.fenster + const Duration(minutes: 1));
    for (var i = 0; i < b.jeAdresse; i++) {
      b.fehlschlag('ich');
    }
    expect(b.wartezeit('ich'), isNotNull);
  });

  test('ein gesperrter unbekannter Name bleibt gesperrt, auch wenn sehr '
      'viele andere dazukommen', () {
    final b = Bremse(uhr: () => jetzt);
    for (var i = 0; i < Bremse.sperreAb; i++) {
      b.unbekanntFehlschlag('niemand');
    }
    expect(b.unbekanntGesperrtBis('niemand'), isNotNull);
    for (var i = 0; i < Bremse.hoechstensEintraege + 10; i++) {
      b.unbekanntFehlschlag('name$i');
    }
    expect(b.unbekanntGesperrtBis('niemand'), isNotNull);
  });
}

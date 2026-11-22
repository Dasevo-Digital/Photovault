import 'package:photo_vault_server/src/kurzablage.dart';
import 'package:test/test.dart';

/// Kurzlebige Einträge von Anfragen ohne Anmeldung (#426): gedeckelt, ohne
/// alles auf einmal zu verlieren.
void main() {
  var jetzt = DateTime.utc(2026, 11, 22, 12);
  Kurzablage<int> ablage({int insgesamt = 100, int jeAbsender = 3}) =>
      Kurzablage(
        dauer: const Duration(minutes: 5),
        insgesamt: insgesamt,
        jeAbsender: jeAbsender,
        uhr: () => jetzt,
      );
  setUp(() => jetzt = DateTime.utc(2026, 11, 22, 12));

  test('je Absender verdrängt ein neuer nur dessen ältesten', () {
    final a = ablage()..lege('fremd', 0, absender: 'b');
    for (var i = 0; i < 5; i++) {
      a.lege('k$i', i, absender: 'a');
    }
    expect(a.length, 4);
    expect(a.nimm('k0'), isNull);
    expect(a.nimm('k1'), isNull);
    expect(a.nimm('k4'), 4);
    expect(a.nimm('fremd'), 0);
  });

  test('insgesamt voll: der älteste geht, nicht alle', () {
    final a = ablage(insgesamt: 1000, jeAbsender: 5)
      ..lege('echt', 1, absender: 'ich');
    jetzt = jetzt.add(const Duration(seconds: 1));
    for (var i = 0; i < 998; i++) {
      a.lege('f$i', i, absender: 'f$i');
    }
    // Noch Platz: Auch nach 999 Einträgen ist der echte da.
    expect(a.nimm('echt'), 1);
    a.lege('echt', 1, absender: 'ich');
    for (var i = 998; i < 1500; i++) {
      a.lege('f$i', i, absender: 'f$i');
    }
    expect(a.length, 1000);
    expect(a.nimm('f1499'), 1499);
  });

  test('abgelaufen ist weg, und jeder Eintrag gilt einmal', () {
    final a = ablage()..lege('x', 1, absender: 'a');
    expect(a.nimm('x'), 1);
    expect(a.nimm('x'), isNull);
    a.lege('y', 2, absender: 'a');
    jetzt = jetzt.add(const Duration(minutes: 6));
    expect(a.nimm('y'), isNull);
    expect(a.length, 0);
  });
}

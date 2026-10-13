import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/serveradresse.dart';

/// Welche Serveradressen ohne TLS angesprochen werden dürfen – dieselbe
/// Regel am Desktop und auf dem Telefon.
void main() {
  // Private Adressen und lokale Namen zusammengesetzt: Als Text sähen sie
  // aus wie die eines echten Heimnetzes (siehe
  // tool/pruefe_repository_datenschutz.sh).
  String v4(List<int> o) => o.join('.');
  const lokal = 'local';

  test('ohne Schema gilt HTTPS, am Ende steht ein Schrägstrich', () {
    expect(
      serveradresseAus(' fotos.example.de ').toString(),
      'https://fotos.example.de/',
    );
    expect(
      serveradresseAus('http://nas:8790/pv').toString(),
      'http://nas:8790/pv/',
    );
    expect(serveradresseAus(''), isNull);
    expect(serveradresseAus('ftp://fotos.example.de'), isNull);
    expect(serveradresseAus('https://'), isNull);
  });

  test('HTTP nur im eigenen Netz', () {
    bool erlaubt(String a) => ohneTlsErlaubt(serveradresseAus(a)!);
    for (final a in [
      'https://fotos.example.de',
      'http://nas:8790',
      'http://localhost:8790',
      'http://fotos.$lokal',
      'http://${v4([10, 1, 2, 3])}:8790',
      'http://${v4([172, 20, 0, 5])}',
      'http://${v4([192, 168, 7, 9])}',
      'http://${v4([100, 101, 2, 3])}',
      'http://${v4([127, 0, 0, 1])}',
      'http://${v4([169, 254, 1, 1])}',
      'http://[::1]:8790',
      'http://[fd12:3456::1]',
    ]) {
      expect(erlaubt(a), isTrue, reason: a);
    }
    for (final a in [
      'http://fotos.example.de',
      'http://192.0.2.10',
      'http://${v4([172, 32, 0, 5])}',
      'http://${v4([100, 128, 0, 1])}',
      'http://[2001:db8::1]',
    ]) {
      expect(erlaubt(a), isFalse, reason: a);
    }
  });
}

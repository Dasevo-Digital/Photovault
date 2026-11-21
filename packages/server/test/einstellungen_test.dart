import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

/// Falsche Einstellungen halten den Start an: Der Server fängt dafür nur
/// [ArgumentError] (bin/photo_vault_server.dart, Rückgabewert 78). Was
/// eine andere Ausnahme warf, endete mit Stacktrace und 255, und was still
/// die Vorgabe nahm, lief an einer Stelle, an der niemand ihn suchte.
void main() {
  Einstellungen lies(Map<String, String> werte) => Einstellungen.ausUmgebung({
    'PV_DATEN': '/tmp/pv-einstellungen',
    ...werte,
  });

  Matcher meldet(String text) => throwsA(
    isA<ArgumentError>().having((f) => '${f.message}', 'message', text),
  );

  test('PV_BESCHLEUNIGER unbekannt: Meldung statt FormatException', () {
    expect(
      () => lies({'PV_BESCHLEUNIGER': 'rocm'}),
      meldet(
        'PV_BESCHLEUNIGER=rocm – bekannt sind cpu, openvino, cuda, coreml',
      ),
    );
    expect(() => lies({'PV_BESCHLEUNIGER': 'cuda:zwei'}), throwsArgumentError);
  });

  test('PV_PORT: nur ein Port, sonst kein Start', () {
    expect(lies({}).port, 8790);
    expect(lies({'PV_PORT': '18790'}).port, 18790);
    expect(
      () => lies({'PV_PORT': 'abc'}),
      meldet('PV_PORT: „abc“ ist keine ganze Zahl'),
    );
    // 0 heisst: einen freien Port nehmen (Prüfstände).
    expect(lies({'PV_PORT': '0'}).port, 0);
    expect(() => lies({'PV_PORT': '-1'}), throwsArgumentError);
    expect(() => lies({'PV_PORT': '70000'}), throwsArgumentError);
  });

  test('Zahlen und Adressen nennen die Variable', () {
    expect(
      () => lies({'PV_SPEICHER_MINDEST': 'viel'}),
      meldet('PV_SPEICHER_MINDEST: „viel“ ist keine ganze Zahl'),
    );
    expect(() => lies({'PV_OEFFENTLICH': 'http://[x'}), throwsArgumentError);
  });
}

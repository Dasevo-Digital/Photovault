/// Meldungen für Entwickler: was schiefging oder wie lange etwas dauerte,
/// ohne dass es in der Oberfläche erscheint.
///
/// Im Kern gibt es kein `debugPrint` – das gehört zu Flutter. Die App leitet
/// [protokollZiel] beim Start auf `debugPrint` um, ein Server auf sein
/// eigenes Protokoll; ohne Einrichtung geht die Meldung auf die Konsole.
library;

/// Wohin [protokoll] schreibt.
void Function(String meldung) protokollZiel = _aufDieKonsole;

/// Schreibt [meldung] nach [protokollZiel].
void protokoll(String meldung) => protokollZiel(meldung);

void _aufDieKonsole(String meldung) {
  // ignore: avoid_print
  print(meldung);
}

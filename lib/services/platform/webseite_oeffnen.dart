import 'dart:io';

/// Öffnet [adresse] im Standardbrowser des Betriebssystems.
///
/// **Warum kein `url_launcher`.** Für drei Prozessaufrufe eine weitere
/// Abhängigkeit samt Plugin-Registrierung auf drei Plattformen zu
/// pflegen, wäre teurer als diese Datei – und sie steht neben
/// [revealInFileManager], die seit jeher denselben Weg geht.
///
/// **Warum die Prüfung auf `http`/`https` nicht weggelassen werden darf.**
/// Was hier hineingereicht wird, landet als Argument eines
/// Systembefehls. `open` unter macOS startet auch Programme, und ein
/// `file:`- oder gar `x-apple-…`-Schema wäre dann etwas anderes als das
/// Öffnen einer Seite. Die Adressen stammen zwar aus einer
/// mitgelieferten Liste, aber genau solche Listen wachsen.
///
/// Gibt `true` zurück, wenn der Befehl abgesetzt werden konnte. `false`
/// heisst: Adresse abgelehnt, Plattform unbekannt, oder der Browser
/// liess sich nicht starten – die aufrufende Oberfläche kann dann einen
/// Hinweis zeigen, statt scheinbar wirkungslos zu bleiben.
Future<bool> oeffneWebseite(String adresse) async {
  if (!istWebadresse(adresse)) return false;
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [adresse]);
      return true;
    }
    if (Platform.isWindows) {
      // Ohne Shell und mit der Adresse als eigenem Argument – `start` in
      // einer `cmd /c`-Zeile müsste erst korrekt gequotet werden, und
      // ein `&` in einer Adresse zerlegte die Zeile.
      await Process.run('explorer', [adresse]);
      return true;
    }
    if (Platform.isLinux) {
      // Unter Flatpak reicht xdg-open aus dem Runtime den Aufruf an das
      // Portal weiter – der Browser startet also ausserhalb des
      // Sandkastens, ohne dass dafür ein Recht nötig wäre.
      final ergebnis = await Process.run('xdg-open', [adresse]);
      return ergebnis.exitCode == 0;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// Ob [adresse] eine gewöhnliche Webadresse ist – die Bedingung, unter
/// der [oeffneWebseite] sie überhaupt weiterreicht.
///
/// Getrennt herausgezogen, damit sie ohne laufendes Betriebssystem
/// geprüft werden kann.
bool istWebadresse(String adresse) {
  final ziel = Uri.tryParse(adresse.trim());
  if (ziel == null) return false;
  if (ziel.scheme != 'http' && ziel.scheme != 'https') return false;
  return ziel.host.isNotEmpty;
}

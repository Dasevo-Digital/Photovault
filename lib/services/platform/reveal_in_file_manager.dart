import 'dart:io';

/// Öffnet [path] im Dateimanager des Betriebssystems.
///
/// Bewusst hier gebündelt statt als `Platform.isMacOS`-Abfrage in der UI:
/// jede Plattform hat einen anderen Befehl, und ohne diese Trennung bliebe
/// die Schaltfläche unter Linux/Windows wirkungslos, ohne dass es auffällt.
///
/// Gibt `true` zurück, wenn der Befehl abgesetzt werden konnte. `false`
/// heißt: Plattform unbekannt oder der Dateimanager ließ sich nicht starten –
/// die aufrufende UI kann dann einen Hinweis zeigen, statt scheinbar
/// wirkungslos zu bleiben.
Future<bool> revealInFileManager(String path) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
      return true;
    }
    if (Platform.isWindows) {
      // explorer.exe liefert auch im Erfolgsfall einen Exit-Code != 0,
      // deshalb wird er hier bewusst nicht ausgewertet.
      await Process.run('explorer', [path]);
      return true;
    }
    if (Platform.isLinux) {
      // Teil der xdg-utils, auf allen gängigen Desktops vorhanden.
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    }
    return false;
  } catch (_) {
    // Befehl nicht gefunden (z.B. minimale Linux-Installation ohne
    // xdg-utils) – kein Grund, die Einstellungen abstürzen zu lassen.
    return false;
  }
}

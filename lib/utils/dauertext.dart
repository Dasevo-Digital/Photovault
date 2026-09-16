/// Eine Restzeit als Satz.
///
/// **Nicht mehr im Warteschlangen-Bildschirm zu Hause.** Er war der
/// erste, der eine Restzeit anzeigte, aber nicht der einzige geblieben:
/// Die Kopfleiste zeigt dieselbe, und seit der Videoausgabe auch die
/// Flugleiste. Ein Widget, das einen Bildschirm einbindet, um an einen
/// Satz zu kommen, hätte die Abhängigkeiten verkehrt herum gelegt.
library;

import '../l10n/app_localizations.dart';

/// Eine Dauer als Satz.
///
/// Auf ganze Minuten gerundet, sobald es mehr als eine ist: Eine
/// Restzeit von „3 Minuten 47 Sekunden" ist genauer, als die Schätzung
/// es hergibt, und sie ändert sich bei jedem Bildaufbau. Unter einer
/// Minute stehen Sekunden, weil es dann tatsächlich gleich vorbei ist.
String dauerText(AppTexte t, Duration dauer) {
  final sekunden = dauer.inSeconds;
  if (sekunden < 60) {
    return t.restaurDauerSekunden(sekunden < 1 ? 1 : sekunden);
  }
  return t.restaurDauerMinuten((dauer.inSeconds / 60).round().clamp(1, 1 << 30));
}

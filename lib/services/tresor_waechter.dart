import 'package:flutter/widgets.dart';

/// Sperrt den Tresor wieder, sobald die App aus dem Blick gerät.
///
/// **Was vorher galt.** Der Master-Key blieb vom ersten richtigen PIN bis
/// zum Beenden im Speicher, und der einzige Weg, ihn loszuwerden, war ein
/// Knopf in den Einstellungen. Wer den Rechner mit laufender App verliess,
/// liess den Tresor offen – und mit ihm die entschlüsselten
/// Zwischenkopien im Temp-Verzeichnis. Die App beobachtete ihren eigenen
/// Lebenszyklus überhaupt nicht: kein `AppLifecycleListener`, kein
/// `WidgetsBindingObserver`, in 199 Dateien nicht einer.
///
/// **Warum `hidden` und `paused`, aber nicht `inactive`.** `inactive`
/// heisst nur „ein anderes Fenster hat den Fokus" – das passiert beim
/// Blick in den Dateimanager, beim Wechsel in den Browser, bei jedem
/// Systemdialog. Danach jedes Mal den PIN zu verlangen, hiesse den Schutz
/// so lästig zu machen, dass ihn niemand einschaltet. `hidden` dagegen
/// ist das Minimieren oder Verbergen des Fensters, `paused` das
/// Weglegen – beides das Zeichen, dass jemand geht.
class Tresorwaechter {
  Tresorwaechter(this._sperre);

  /// Was beim Wegsehen zu tun ist – in der App
  /// `LibraryState.sperreTresor`.
  final Future<void> Function() _sperre;

  AppLifecycleListener? _horcher;

  void horche() {
    _horcher?.dispose();
    _horcher = AppLifecycleListener(onStateChange: aufZustand);
  }

  void schweige() {
    _horcher?.dispose();
    _horcher = null;
  }

  /// Offen für den Prüfstand: Einen echten Fensterwechsel gibt es im Test
  /// nicht, die Entscheidung dahinter schon.
  @visibleForTesting
  void aufZustand(AppLifecycleState zustand) {
    if (sperrtBei(zustand)) _sperre();
  }
}

/// Ob dieser Zustand bedeutet, dass jemand die App aus dem Blick gibt.
///
/// Als eigene Funktion, damit die Regel prüfbar ist, ohne dass ein
/// Fenster im Spiel wäre – und damit sie an genau einer Stelle steht.
bool sperrtBei(AppLifecycleState zustand) =>
    zustand == AppLifecycleState.hidden ||
    zustand == AppLifecycleState.paused ||
    zustand == AppLifecycleState.detached;

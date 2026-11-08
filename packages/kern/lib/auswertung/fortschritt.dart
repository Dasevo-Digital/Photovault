/// Wie weit ein Lauf ist – der Import ebenso wie jede Auswertung.
///
/// Liegt im Kern, weil die Läufe dort liegen; die App zeigt ihn an, der
/// Server meldet ihn weiter.
class ImportProgress {
  final int done;
  final int total;
  final String? currentFile;

  /// Der volle Pfad zu [currentFile] – damit sich eine gescheiterte Datei
  /// noch einmal versuchen lässt.
  final String? pfad;

  /// Gesetzt, sobald diese Fortschritts-Meldung eine tatsächlich neu
  /// importierte Datei betrifft (nicht bei Duplikaten/Fehlern) – für Aufrufer
  /// wie das Fortschrittsblatt der App, die nach dem Import direkt in den
  /// Sichtungs-Modus (Culling) springen wollen, ohne die importierten Fotos
  /// erneut aus der DB abfragen zu müssen.
  final String? assetId;

  /// Ob genau diese Datei uebersprungen wurde, weil sie schon in der
  /// Bibliothek liegt.
  ///
  /// Sie wurde immer schon uebersprungen - nur sagte es niemand. Wer
  /// zweihundert Dateien hereinzieht und danach hundertachtzig Fotos
  /// vorfindet, sucht den Fehler bei sich.
  final bool duplikat;

  /// Ob diese Datei gar nicht hereinkam.
  final bool gescheitert;

  /// Woran sie scheiterte – die Ausnahme oder der Text des Servers, so wie
  /// sie kam. Die Oberfläche macht daraus einen Satz.
  ///
  /// **Warum es das braucht.** 41 von 55 Fotos einer SD-Karte „kamen nicht
  /// herein“ (#335), und warum, stand nirgends: nicht in der App, nicht im
  /// Protokoll des Servers, den sie nie erreichten, und im Systemprotokoll
  /// des Macs nur geschwärzt.
  final Object? grund;

  /// Wie viele Dinge wirklich getan wurden – nicht wie viele angesehen.
  ///
  /// **Warum es die Zahl gesondert braucht.** „N bearbeitet" ist die
  /// Zahl der angesehenen Dinge. Beim Ordnen der Ablage stand deshalb am
  /// Ende nichts, woraus man ablesen konnte, ob etwas verschoben wurde –
  /// aus dem Erstlauf-Bericht (A08): „Aufgabe lief ohne Fehlermeldung
  /// durch, genannt wurde nichts."
  ///
  /// `null` bei allen Läufen, bei denen angesehen und getan dasselbe
  /// ist; gesetzt wird sie am letzten `yield`.
  final int? getan;

  ImportProgress(
    this.done,
    this.total, {
    this.currentFile,
    this.pfad,
    this.assetId,
    this.duplikat = false,
    this.gescheitert = false,
    this.grund,
    this.getan,
  });
}

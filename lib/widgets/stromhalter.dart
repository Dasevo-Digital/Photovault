import 'dart:async';

/// Hält einen Datenstrom fest, solange sein Schlüssel gleich bleibt.
///
/// **Warum es das braucht.** `db.watchTimeline(limit: 600)` liefert bei
/// jedem Aufruf ein NEUES Stream-Objekt. Steht so ein Aufruf im `stream:`
/// eines `StreamBuilder` — und er stand an sechsunddreissig Stellen so da —,
/// dann sieht der StreamBuilder bei jedem Neubau einen anderen Strom, kündigt
/// das alte Abo und schliesst ein neues. Drift teilt dabei nichts: Das neue
/// Abo führt die Abfrage von vorn aus, auch wenn nebenan noch ein Abo auf
/// genau dieselbe Abfrage offen ist.
///
/// An der gewachsenen Bibliothek gemessen, je Neubau:
///
/// ```
/// watchTimeline(600)          5,1 ms
/// watchTimeline(3000)        12,9 ms
/// watchTimeline() ohne Grenze 35,9 ms
/// watchTrash()                3,0 ms
/// watchAlbums(), watchPeople()  0,1 ms
/// ```
///
/// Teuer wird das erst zusammen mit dem, was Neubauten auslöst. In der
/// Zeitleiste ist das **jeder Pfeiltastendruck** ([Rasterbedienung] setzt
/// `aktiveKachel` per `setState`) und **jeder Klick in der Mehrfachauswahl**.
/// Wer eine Taste gedrückt hält, löst rund dreissig Neubauten je Sekunde
/// aus — und das Ladefenster wächst beim Scrollen bis auf die ganze
/// Bibliothek.
///
/// Der Schlüssel ist alles, was die Abfrage bestimmt: die Fenstergrösse, das
/// Jahr, die Album-Kennung. Ändert er sich, entsteht ein neuer Strom — genau
/// dann soll ja auch neu gefragt werden.
///
/// ```dart
/// stream: _zeitleiste.hole(_fenster, () => db.watchTimeline(limit: _fenster)),
/// ```
class Stromhalter<T> {
  Stream<T>? _strom;
  Object? _schluessel;
  var _hatSchluessel = false;

  /// Der gehaltene Strom zu [schluessel] – oder ein frisch von [bau]
  /// erzeugter, wenn es zu diesem Schlüssel noch keinen gibt.
  ///
  /// [schluessel] darf `null` sein (ein Album ohne Auswahl etwa); dass noch
  /// gar nichts geholt wurde, wird getrennt gemerkt.
  Stream<T> hole(Object? schluessel, Stream<T> Function() bau) {
    if (!_hatSchluessel || _schluessel != schluessel) {
      _schluessel = schluessel;
      _hatSchluessel = true;
      _strom = bau();
    }
    return _strom!;
  }
}

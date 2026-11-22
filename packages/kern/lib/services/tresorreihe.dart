import 'storage_paths.dart';

final _reihen = Expando<Future<void>>('tresorreihe');

/// Reiht [arbeit] hinter alles ein, was in der Bibliothek von [paths]
/// gerade sperrt, entsperrt oder Dateien einer Aufnahme ablegt (#430).
///
/// Das Sperren verschlüsselt die Dateien, die eine Aufnahme in diesem
/// Augenblick hat. Legte eine Restaurierung, ein Neu-Rendern oder eine neue
/// Miniatur danach noch eine Datei ab, lag sie im Klartext in einem
/// gesperrten Foto, und jedes spätere Entsperren scheiterte an ihr. In der
/// Reihe sieht jeder Schritt den Stand, den der vorige hinterlassen hat.
///
/// Auch die Auswertung legt ihre Ergebnisse darin ab (Gesichter,
/// Einbettungen, erkannter Text …), damit kein Sperren zwischen ihrer
/// Prüfung und dem Schreiben liegt (siehe `Auswertungen.inOffeneAufnahme`).
/// Am Server gibt es kein Sperren; dort reiht sich nur die Auswertung
/// selbst ein.
///
/// Ein Fehler von [arbeit] geht an den Aufrufer; die Reihe läuft weiter.
/// **Nicht schachteln:** Wer in der Reihe läuft und noch einmal einreiht,
/// wartet auf sich selbst.
Future<T> inTresorreihe<T>(StoragePaths paths, Future<T> Function() arbeit) {
  final lauf = (_reihen[paths] ?? Future<void>.value()).then((_) => arbeit());
  _reihen[paths] = lauf.then<void>((_) {}, onError: (Object _) {});
  return lauf;
}

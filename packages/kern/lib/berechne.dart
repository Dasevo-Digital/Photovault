/// Rechnen in einem eigenen Isolate, ohne Flutter.
library;

import 'dart:async';
import 'dart:isolate';

/// Rechnet [arbeit] mit [eingabe] in einem eigenen Isolate – dasselbe wie
/// Flutters `compute`, das es im Kern nicht gibt.
///
/// Bewusst als Funktion mit eigenem Rahmen und nicht als
/// `Isolate.run(() => …)` an der Aufrufstelle: Eine Closure dort nimmt
/// den Rahmen ihres Gültigkeitsbereichs mit, und hält eine andere Closure
/// darin etwas fest, das sich nicht übertragen lässt (einen Prozess, einen
/// Port), scheitert der Versand. Hier sieht die Closure nur [arbeit] und
/// [eingabe].
Future<R> berechne<Q, R>(FutureOr<R> Function(Q eingabe) arbeit, Q eingabe) =>
    Isolate.run(() => arbeit(eingabe));

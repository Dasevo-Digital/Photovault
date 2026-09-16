import 'dart:async';

/// Verzögert den Aufruf von [run] um [delay] und verwirft einen noch
/// wartenden vorherigen Aufruf – für Regler/Textfelder, bei denen jede
/// Änderung sonst sofort eine teure Aktion (z.B. eine native Rendering-
/// Anfrage) auslösen würde.
class Debouncer {
  Debouncer(this.delay);
  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}

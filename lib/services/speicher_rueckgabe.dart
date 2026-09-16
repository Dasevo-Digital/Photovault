import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Gibt freigegebenen Speicher an das Betriebssystem zurück – unter Linux.
///
/// **Warum das nötig ist.** Die KI-Modelle werden alle zwei Minuten
/// freigegeben, wenn niemand sie benutzt (siehe
/// `ModellHalter.freigebenWennUnbenutzt`). Das gibt den Speicher an die
/// C-Bibliothek zurück, aber nicht an das System: glibc behält die Seiten
/// im Heap für die nächste Anforderung. Auf einer Instanz, die knapp
/// dreizehn Stunden gelaufen war und dabei 2025 s Rechenzeit verbraucht
/// hatte, sah das am 25.08.2026 so aus:
///
/// ```
///                  vorher        nach malloc_trim(0)
///   RSS         2.415.440 kB     1.723.084 kB   (-692 MB)
///   davon Heap  1.532.592 kB       908.876 kB   (-624 MB)
/// ```
///
/// Der Dart-Heap lag dabei bei 62 MB – es war also kein Leck im Programm,
/// sondern liegengebliebener Platz in der C-Bibliothek. 692 MB, die eine
/// Maschine mit 7,7 GB RAM anderweitig gebrauchen kann.
///
/// **Nur Linux.** Windows verkleinert seinen Arbeitssatz von selbst
/// (gemessen 513 → 282 MB ohne Zutun). Unter macOS gibt es
/// `malloc_zone_pressure_relief`, aber dort ist das Problem nicht
/// nachgewiesen – und was nicht gemessen ist, wird hier nicht gebaut.
///
/// **Nicht jede Linux-Umgebung hat es.** `malloc_trim` ist eine
/// GNU-Erweiterung; unter musl (Alpine) fehlt sie. Der Symbolzugriff wird
/// deshalb einmalig versucht und das Ergebnis gemerkt.
class SpeicherRueckgabe {
  SpeicherRueckgabe._();

  static bool _gesucht = false;
  static int Function(int)? _trim;

  /// Ob diese Plattform Speicher zurückgeben kann.
  static bool get moeglich {
    _suche();
    return _trim != null;
  }

  static void _suche() {
    if (_gesucht) return;
    _gesucht = true;
    if (!Platform.isLinux) return;
    try {
      _trim = DynamicLibrary.process()
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'malloc_trim');
    } on ArgumentError {
      // Kein glibc (musl) – dann bleibt es beim Normalverhalten.
      _trim = null;
    }
  }

  /// Fordert die C-Bibliothek auf, ungenutzte Heap-Seiten freizugeben.
  ///
  /// Gibt zurück, ob tatsächlich etwas zurückgegeben wurde. Kostet Zeit
  /// proportional zur Heap-Grösse, weil alle Arenen durchgegangen werden –
  /// der Aufrufer entscheidet, wann das passt.
  static bool jetzt() {
    _suche();
    final f = _trim;
    if (f == null) return false;
    final uhr = Stopwatch()..start();
    final etwasFrei = f(0) != 0;
    uhr.stop();
    if (kDebugMode) {
      debugPrint('malloc_trim: ${etwasFrei ? "etwas" : "nichts"} '
          'zurueckgegeben in ${uhr.elapsedMilliseconds} ms');
    }
    return etwasFrei;
  }
}

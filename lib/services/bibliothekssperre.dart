import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Was der Versuch ergeben hat, eine Bibliothek für diese Instanz zu
/// beanspruchen.
enum Sperrzustand {
  /// Diese Instanz hält sie jetzt und gibt sie erst beim Beenden her.
  genommen,

  /// Eine andere Instanz hält sie. Das ist der einzige Fall, in dem
  /// abgewiesen werden darf.
  belegt,

  /// Nicht feststellbar – die Sperre liess sich aus einem *anderen* Grund
  /// als Belegung nicht nehmen.
  unklar,
}

/// [zustand] samt Begründung für das Protokoll. [grund] ist nur bei
/// [Sperrzustand.unklar] gesetzt und **nicht** für die Oberfläche gedacht:
/// Es ist eine Betriebssystemmeldung in Systemsprache.
typedef Sperrbefund = ({Sperrzustand zustand, String? grund});

/// **Verhindert, dass zwei Instanzen dieselbe Bibliothek öffnen.**
///
/// Gesperrt wird die **Bibliothek, nicht das Programm**. Der Ort ist zur
/// Laufzeit umschaltbar (siehe [LibraryLocation.wechsleZu]), und zwei
/// Instanzen auf zwei *verschiedenen* Bibliotheken tun einander nichts –
/// eine programmweite Sperre verböte etwas Erlaubtes, etwa die Testfassung
/// neben der produktiven.
///
/// Das Mittel ist eine **ausschliessliche Dateisperre des Betriebssystems**
/// auf einer eigenen, sonst leeren Datei in der Bibliothekswurzel – bewusst
/// keine Datei mit der Prozessnummer darin. Eine solche müsste nach einem
/// Absturz entscheiden, ob der eingetragene Prozess noch lebt und ob es
/// überhaupt unserer ist, und genau dieser Code sperrt Leute erfahrungsgemäss
/// aus ihren eigenen Daten aus. Eine echte Dateisperre gibt der Kern beim
/// Wegfall des Prozesses von selbst wieder her; es gibt hier deshalb weder
/// eine Aufräumroutine noch eine Lebendprüfung noch einen Zeitstempel.
///
/// An allen drei Plattformen gemessen (Halter, zweiter Versuch, danach
/// harter Abschuss des Halters):
///
/// ```
///                gehalten          nach hartem Abschuss
/// macOS      abgewiesen, 0 ms       frei, 0 ms      EAGAIN 35
/// Linux      abgewiesen, 0 ms       frei, 0 ms      EAGAIN 11
/// Windows    abgewiesen, 0 ms       frei, 0 ms      Fehler 33
/// ```
///
/// **Der wichtigste Teil ist [Sperrzustand.unklar].** Lässt sich die Sperre
/// aus einem anderen Grund als Belegung nicht nehmen – eine Netzfreigabe
/// ohne verlässliches `flock`, ein schreibgeschütztes Medium –, dann wird
/// **durchgelassen** und protokolliert. Nur die Fehlercodes in [_belegtCodes]
/// heissen „ein anderer hat sie"; alles andere heisst „ich weiss es nicht",
/// und darauf jemanden von seiner eigenen Bibliothek auszusperren wäre
/// schlimmer als das Problem, das die Sperre löst.
class Bibliothekssperre {
  Bibliothekssperre._();

  /// Eigene Datei, nicht `library.sqlite`: Auf Windows ist die Sperre
  /// zwingend (`LockFileEx`) und nicht bloss beratend – eine Sperre auf der
  /// Datenbankdatei selbst brächte SQLite in Bedrängnis.
  static const dateiname = '.pv-instanz.lock';

  /// Muss über die ganze Laufzeit gehalten werden. Ohne diese Referenz
  /// schlösse der Finalizer die Datei irgendwann und gäbe die Sperre mit
  /// ihr her – lautlos und zu einem nicht vorhersagbaren Zeitpunkt.
  static RandomAccessFile? _gehalten;
  static String? _ort;

  /// Die Bibliothek, die diese Instanz hält – `null`, solange keine gehalten
  /// wird (auch bei [Sperrzustand.unklar], wo bewusst nichts gehalten wird).
  static String? get gehaltenerOrt => _ort;

  /// Womit die jeweilige Plattform „hat schon jemand" meldet. Gemessen,
  /// nicht aus der Dokumentation abgeschrieben: macOS und Linux nennen
  /// beide EAGAIN, haben dafür aber verschiedene Nummern; Windows meldet
  /// ERROR_LOCK_VIOLATION (33), bei geöffneter Datei auch
  /// ERROR_SHARING_VIOLATION (32).
  static Set<int> get _belegtCodes {
    if (Platform.isWindows) return const {32, 33};
    if (Platform.isMacOS) return const {35};
    return const {11};
  }

  /// Beansprucht [wurzel] für diese Instanz.
  ///
  /// Wird eine andere Bibliothek gehalten, wird diese zuerst hergegeben –
  /// so bleibt beim Umschalten nie eine Sperre auf einem Ort zurück, den
  /// niemand mehr benutzt.
  static Future<Sperrbefund> nimm(Directory wurzel) async {
    final ziel = p.join(wurzel.path, dateiname);
    if (_ort != null && p.equals(_ort!, ziel)) {
      return (zustand: Sperrzustand.genommen, grund: null);
    }
    await gib();

    try {
      await wurzel.create(recursive: true);
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      final grund = '${e.osError?.message ?? e.message} (${code ?? '?'})';
      debugPrint(
          'Bibliothekssperre nicht prüfbar unter ${wurzel.path}: $grund');
      return (zustand: Sperrzustand.unklar, grund: grund);
    }

    // Nach einem hart beendeten Prozess kann Windows das freigegebene Handle
    // noch für wenige Takte als belegt melden. Ein kurzer erneuter Versuch
    // verhindert, dass ein sofortiger Neustart fälschlich abgewiesen wird.
    final versuche = Platform.isWindows ? 6 : 1;
    for (var versuch = 0; versuch < versuche; versuch++) {
      RandomAccessFile? datei;
      try {
        // `append` statt `write`: `write` kürzt die Datei beim Öffnen, und
        // das ist ein Schreibzugriff auf etwas, das eine fremde Instanz
        // gerade gesperrt hält.
        datei = await File(ziel).open(mode: FileMode.append);
        datei.lockSync(FileLock.exclusive);
        _gehalten = datei;
        _ort = ziel;
        return (zustand: Sperrzustand.genommen, grund: null);
      } on FileSystemException catch (e) {
        await _schliesse(datei);
        final code = e.osError?.errorCode;
        if (code != null && _belegtCodes.contains(code)) {
          if (versuch + 1 < versuche) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            continue;
          }
          return (zustand: Sperrzustand.belegt, grund: null);
        }
        final grund = '${e.osError?.message ?? e.message} (${code ?? '?'})';
        debugPrint(
            'Bibliothekssperre nicht prüfbar unter ${wurzel.path}: $grund');
        return (zustand: Sperrzustand.unklar, grund: grund);
      }
    }
    return (zustand: Sperrzustand.belegt, grund: null);
  }

  /// Gibt eine gehaltene Sperre her. Im Betrieb erledigt das der Kern beim
  /// Beenden; gebraucht wird es beim Umschalten und in den Prüfständen.
  static Future<void> gib() async {
    final datei = _gehalten;
    _gehalten = null;
    _ort = null;
    if (datei == null) return;
    try {
      datei.unlockSync();
    } on FileSystemException catch (e) {
      debugPrint('Bibliothekssperre liess sich nicht lösen: $e');
    }
    await _schliesse(datei);
  }

  static Future<void> _schliesse(RandomAccessFile? datei) async {
    if (datei == null) return;
    try {
      await datei.close();
    } on FileSystemException catch (_) {
      // Schon zu. Kein Grund, den Start daran scheitern zu lassen.
    }
  }

  @visibleForTesting
  static bool get haeltEtwas => _gehalten != null;
}

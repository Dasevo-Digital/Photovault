import 'dart:async';

import 'package:flutter/foundation.dart';

/// Hält ein KI-Modell, das erst beim ersten Gebrauch geladen und nach
/// getaner Arbeit wieder freigegeben wird.
///
/// Warum überhaupt: Beim Start alle Modelle zu laden kostete gemessen
/// 1538 MB (1751 MB mit Modellen gegen 213 MB ohne). Wer die App nur
/// öffnet, um ein Foto anzusehen, bezahlte das vollständig mit.
///
/// Der Halter löst dabei drei Dinge, die einzeln leicht zu übersehen sind:
///
/// 1. **Doppeltes Laden bei Parallelzugriff.** Fragen zwei Stellen
///    gleichzeitig nach demselben Modell, entsteht trotzdem nur eine
///    Sitzung – die zweite wartet auf dieselbe [Future].
/// 2. **Freigeben mitten in der Benutzung.** Eine ONNX-Sitzung zu
///    entsorgen, während eine Inferenz darauf läuft, bringt die App zum
///    Absturz. Der Nutzerzähler macht das strukturell unmöglich, statt
///    sich auf Sorgfalt an jeder Aufrufstelle zu verlassen. (Genau dafür
///    stand vorher ein Sonderfall in `LibraryState.reloadModels()`, der
///    nur die Restaurierung abdeckte.)
/// 3. **Installiert ist nicht geladen.** [installiert] beantwortet, ob
///    die Dateien da sind – unabhängig davon, ob gerade eine Sitzung
///    offen ist. Nur so können die KI-Knöpfe in der Oberfläche schon vor
///    der ersten Benutzung sichtbar sein.
class ModellHalter<T> {
  ModellHalter({
    required this.name,
    required this.installiert,
    required Future<T> Function() laden,
    required Future<void> Function(T) entsorgen,
  })  : _laden = laden,
        _entsorgen = entsorgen;

  /// Für Protokollausgaben – z.B. "CLIP-Bild".
  final String name;

  /// Ob die Modelldateien vorliegen. Wird einmalig beim Anlegen ermittelt
  /// (billige Dateiprüfung, siehe die `isAvailable`-Methoden der Dienste)
  /// und ändert sich erst wieder nach einem Download, der den Halter neu
  /// anlegt.
  final bool installiert;

  final Future<T> Function() _laden;
  final Future<void> Function(T) _entsorgen;

  T? _instanz;
  Future<T>? _imFlug;
  int _nutzer = 0;

  /// Ob gerade eine Sitzung offen ist (nur für Anzeige und Tests).
  bool get istGeladen => _instanz != null;

  /// Ob gerade geladen wird – für den "Modell wird geladen …"-Hinweis.
  bool get laedtGerade => _imFlug != null;

  /// Wie viele Stellen das Modell gerade in Benutzung haben.
  @visibleForTesting
  int get nutzer => _nutzer;

  /// Führt [arbeit] mit dem Modell aus und lädt es dabei bei Bedarf.
  /// Gibt `null` zurück, wenn das Modell nicht installiert ist – so
  /// braucht die Aufrufstelle keine eigene Vorabprüfung.
  ///
  /// Solange [arbeit] läuft, gibt [freigebenWennUnbenutzt] das Modell
  /// nicht frei.
  Future<R?> mit<R>(Future<R> Function(T modell) arbeit) async {
    if (!installiert) return null;
    // Vor dem Laden hochzählen, damit auch eine noch laufende Ladung
    // gegen ein zwischenzeitliches Freigeben geschützt ist.
    _nutzer++;
    try {
      return await arbeit(await _hole());
    } finally {
      _nutzer--;
    }
  }

  /// Leiht das Modell über längere Zeit aus – für Bildschirme, die es
  /// über eine ganze Sitzung brauchen (die KI-Maske im Entwickeln lädt
  /// einmal die Bildeinbettung und sagt danach mehrfach Masken vorher).
  /// Jede erfolgreiche Leihe MUSS mit [zurueckgeben] beendet werden,
  /// sonst bleibt das Modell bis zum Beenden im Speicher.
  Future<T?> leihen() async {
    if (!installiert) return null;
    _nutzer++;
    try {
      return await _hole();
    } catch (_) {
      _nutzer--; // die Leihe kam nicht zustande
      rethrow;
    }
  }

  /// Gegenstück zu [leihen].
  void zurueckgeben() {
    if (_nutzer > 0) _nutzer--;
  }

  /// Gibt das Modell frei, sofern gerade niemand damit arbeitet.
  /// Liefert `true`, wenn tatsächlich eine Sitzung geschlossen wurde.
  ///
  /// Ein `false` ist kein Fehler, sondern der Normalfall, wenn nichts
  /// geladen war oder noch jemand arbeitet – der nächste Aufruf holt es
  /// dann nach.
  Future<bool> freigebenWennUnbenutzt() async {
    if (_nutzer > 0) return false;
    final da = _instanz;
    if (da == null) return false;
    // Erst abhängen, dann entsorgen: Wer in der Zwischenzeit etwas
    // braucht, lädt sauber neu, statt die gerade sterbende Sitzung zu
    // bekommen.
    _instanz = null;
    try {
      await _entsorgen(da);
    } catch (e) {
      debugPrint('Modell "$name" liess sich nicht sauber entsorgen: $e');
    }
    return true;
  }

  Future<T> _hole() async {
    final da = _instanz;
    if (da != null) return da;
    return _imFlug ??= () async {
      try {
        final neu = await _laden();
        _instanz = neu;
        return neu;
      } finally {
        // Auch im Fehlerfall zurücksetzen, damit ein späterer Versuch
        // nicht dauerhaft an einer fehlgeschlagenen Ladung hängen bleibt.
        _imFlug = null;
      }
    }();
  }
}

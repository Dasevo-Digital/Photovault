import 'package:flutter/services.dart';

/// Nimmt die Frage „darf ich beenden?" von der nativen Seite entgegen
/// (siehe macos/Runner/BeendenChannel.swift).
///
/// Der Wächter kennt weder Aufgaben noch Dialoge – er reicht die Frage an
/// eine Rückrufstelle weiter und deren Antwort zurück. Dadurch lässt er sich
/// mit einem gefälschten Kanal prüfen, ohne dass dafür ein Fenster,
/// ein Navigator oder eine laufende Auswertung nötig wären.
class BeendenWaechter {
  BeendenWaechter({MethodChannel? kanal})
      : _kanal = kanal ?? const MethodChannel(kanalName);

  static const kanalName = 'photo_vault/beenden';
  static const methode = 'darfBeenden';

  final MethodChannel _kanal;

  /// Beantwortet künftige Anfragen mit [darfBeenden].
  ///
  /// Wirft die Rückrufstelle, wird beendet: Eine Ausnahme im Weg zum
  /// Bestätigungsdialog darf nicht dazu führen, dass sich die App nicht mehr
  /// schliessen lässt.
  void horche(Future<bool> Function() darfBeenden) {
    _kanal.setMethodCallHandler((aufruf) async {
      if (aufruf.method != methode) return null;
      try {
        return await darfBeenden();
      } catch (_) {
        return true;
      }
    });
  }

  /// Für Tests und den Abbau: nimmt den Empfänger wieder weg.
  void schweige() => _kanal.setMethodCallHandler(null);
}

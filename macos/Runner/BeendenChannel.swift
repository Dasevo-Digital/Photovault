import Cocoa
import FlutterMacOS

/// Fragt vor dem Beenden auf der Dart-Seite nach, ob dort noch etwas läuft.
///
/// Warum überhaupt nativ: Die Hintergrundaufgaben laufen jetzt wirklich
/// weiter, während man die App benutzt (siehe `Hintergrundlauf`). Damit wird
/// das Beenden zur folgenreichen Handlung – ein Cmd-Q mitten in einem Lauf
/// über 8000 Fotos verwirft die Arbeit der laufenden Datei kommentarlos.
/// Flutter selbst bekommt vom Beenden nichts mit: AppKit fragt
/// `applicationShouldTerminate`, nicht das Framework.
///
/// Die Antwort kommt asynchron aus Dart. Beide Aufrufstellen sind darauf
/// eingerichtet (`.terminateLater` bzw. ein zurückgestelltes `close()`).
class BeendenChannel {
    private static var kanal: FlutterMethodChannel?

    /// Hat der Nutzer einmal zugestimmt, wird nicht erneut gefragt: Das
    /// Schliessen des Fensters läuft anschliessend noch durch
    /// `applicationShouldTerminate`, und zweimal dieselbe Frage wäre eine
    /// Zumutung.
    private static var bestaetigt = false

    static func register(with registrar: FlutterPluginRegistrar) {
        kanal = FlutterMethodChannel(
            name: "photo_vault/beenden",
            binaryMessenger: registrar.messenger)
    }

    /// Ruft [antwort] genau einmal – synchron, wenn schon feststeht, dass
    /// beendet werden darf, sonst nach der Rückmeldung aus Dart.
    static func frage(_ antwort: @escaping (Bool) -> Void) {
        if bestaetigt || kanal == nil {
            antwort(true)
            return
        }
        // Bewusst OHNE Zeitlimit. Ein Limit klingt nach Vorsicht, wäre hier
        // aber eine Frist zum Nachdenken: Wer den Hinweis liest und
        // abwägt, braucht länger als jede Zahl, die man einsetzen möchte –
        // und ein abgelaufener Zähler würde seine Antwort übergehen und
        // genau das tun, wovor der Hinweis warnt.
        //
        // Der Fall „niemand antwortet" ist trotzdem abgedeckt: Fehlt auf
        // der Dart-Seite ein Empfänger, meldet Flutter das von sich aus
        // (FlutterMethodNotImplemented), und `as? Bool` ergibt dann nil.
        kanal!.invokeMethod("darfBeenden", arguments: nil) { ergebnis in
            let erlaubt = (ergebnis as? Bool) ?? true
            if erlaubt { bestaetigt = true }
            antwort(erlaubt)
        }
    }
}

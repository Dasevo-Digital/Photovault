import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  /// Fängt Cmd-Q und „Photo Vault → Beenden" ab, solange noch eine
  /// Hintergrundaufgabe läuft (siehe BeendenChannel).
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    var sofort: Bool?
    var zurueckgestellt = false
    BeendenChannel.frage { erlaubt in
      if zurueckgestellt {
        sender.reply(toApplicationShouldTerminate: erlaubt)
      } else {
        // Die Antwort kam synchron – dann braucht es kein terminateLater.
        sofort = erlaubt
      }
    }
    if let entschieden = sofort {
      return entschieden ? .terminateNow : .terminateCancel
    }
    zurueckgestellt = true
    return .terminateLater
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

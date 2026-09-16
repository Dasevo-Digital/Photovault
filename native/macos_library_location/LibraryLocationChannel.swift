// LibraryLocationChannel.swift
//
// Ermöglicht, den Speicherort der Bibliothek (Datenbank + Fotos/Videos/
// Thumbnails) auf einen beliebigen, vom Nutzer gewählten Ordner zu verlegen
// (Einstellungen → Speicherort) – z.B. eine externe Festplatte oder einen
// Cloud-Sync-Ordner.
//
// Der schwierige Teil dabei ist die macOS-App-Sandbox: Zugriff auf einen vom
// Nutzer über einen Dateidialog gewählten Ordner gilt normalerweise nur für
// die aktuelle App-Sitzung. Nach einem Neustart der App wäre der Zugriff
// sonst wieder weg. Die von Apple vorgesehene Lösung dafür sind
// "Security-Scoped Bookmarks": ein Datenblob, der den Zugriff dauerhaft
// festhält und nach jedem Neustart erneut "aufgelöst" werden kann, um den
// Zugriff wiederherzustellen – dafür ist native Swift-Code nötig, es gibt
// dafür keine reine Dart/Flutter-API.
//
// WICHTIG: Der Ordnerauswahl-Dialog UND die Bookmark-Erzeugung müssen in
// EINEM nativen Aufruf passieren (deshalb hier ein eigenes NSOpenPanel statt
// z.B. des Dart-Pakets `file_picker`): Die Sandbox-Berechtigung hängt am
// konkreten `NSURL`-Objekt, das der Dialog zurückgibt – nicht am Pfad-String.
// Reicht man nur den Pfad als String durch Dart (wie `file_picker` es tut)
// und baut daraus später in Swift ein neues `URL(fileURLWithPath:)`, ist die
// Berechtigung schon wieder verloren und `bookmarkData(.withSecurityScope)`
// schlägt fehl.
//
// Einbindung: siehe ImageConverter.swift – derselbe Ablauf (Datei nach
// macos/Runner/ kopieren, in Xcode zum Runner-Target hinzufügen, in
// MainFlutterWindow.swift registrieren). Ohne diesen Schritt bleibt der
// Speicherort auf dem Standardordner fixiert – die restliche App
// funktioniert davon unabhängig normal weiter.
//
// BEKANNTE EINSCHRÄNKUNG: Der "Neuer Ordner"-Button im Panel
// (canCreateDirectories) funktioniert bei ad-hoc-signierten Entwickler-
// Builds (CODE_SIGN_IDENTITY = "-", der Flutter-Standard ohne eigenes
// Apple-Entwickler-Team) auf macOS 26 nicht zuverlässig – Apple hat dort die
// Validierung des `com.apple.appkit.xpc.openAndSavePanelService`-Dienstes
// verschärft und lehnt Anfragen von Prozessen ohne stabile Code-Identität
// ab. Für PhotoVault ist das unkritisch, da jeder bereits vorhandene Ordner
// als Speicherort funktioniert (der Nutzer legt einen neuen Ordner nötigenfalls
// vorher im Finder an) – der Auswahl-Dialog selbst (Ordner browsen/wählen)
// ist von der Einschränkung nicht betroffen. Mit einem echten
// Apple-Entwickler-Zertifikat (DEVELOPMENT_TEAM gesetzt) tritt das Problem
// nicht auf.

import Cocoa
import FlutterMacOS

class LibraryLocationChannel: NSObject {
    // Hält die Security-Scope-URLs am Leben, solange die App läuft –
    // `stopAccessingSecurityScopedResource()` würde den Zugriff sonst sofort
    // wieder beenden.
    private static var accessedURLs: [URL] = []

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "photo_vault/library_location",
            binaryMessenger: registrar.messenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "pickFolderAndCreateBookmark":
                let args = call.arguments as? [String: Any]
                let message = args?["message"] as? String
                // NSOpenPanel muss auf dem Main-Thread laufen.
                DispatchQueue.main.async {
                    pickFolderAndCreateBookmark(message: message, result: result)
                }
            case "resolveBookmark":
                guard
                    let args = call.arguments as? [String: Any],
                    let bookmarkBase64 = args["bookmark"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "bookmark fehlt", details: nil))
                    return
                }
                result(resolveBookmark(base64: bookmarkBase64))
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Zeigt einen nativen Ordnerauswahl-Dialog und erzeugt – noch bevor die
    /// dadurch gewährte Sandbox-Berechtigung wieder verloren gehen kann –
    /// sofort ein dauerhaftes Security-Scoped-Bookmark für den gewählten
    /// Ordner. Liefert `{"path": ..., "bookmark": ...}`, oder `nil`, falls
    /// der Nutzer abgebrochen hat oder die Bookmark-Erzeugung fehlschlägt.
    private static func pickFolderAndCreateBookmark(message: String?, result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let message = message {
            panel.message = message
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                result(nil)
                return
            }
            guard let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else {
                result(nil)
                return
            }
            result([
                "path": url.path,
                "bookmark": data.base64EncodedString(),
            ])
        }
    }

    /// Löst ein zuvor erzeugtes Bookmark wieder auf und stellt den
    /// Sandbox-Zugriff auf den Ordner wieder her (nötig nach jedem
    /// App-Neustart). Gibt den aufgelösten Pfad zurück, oder `nil`, falls
    /// das Bookmark ungültig geworden ist (z.B. Ordner gelöscht/umbenannt
    /// oder Laufwerk nicht eingebunden).
    private static func resolveBookmark(base64: String) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessedURLs.append(url)

        return url.path
    }
}

import Foundation
import Security

/// Die Verbindung zum Server, geteilt zwischen der App und ihren
/// Erweiterungen (Widget „Vor x Jahren“, Teilen „An Photo Vault“).
///
/// **Warum der Schlüsselbund und keine App Group.** Eine App Group gibt es
/// nur mit bezahlter Mitgliedschaft; die App wird kostenlos signiert. Eine
/// gemeinsame Schlüsselbund-Gruppe dagegen deckt das Profil ab, das Xcode
/// dafür anlegt (`<Team>.*`). Darin steht nur, was die Erweiterungen
/// brauchen: die Adresse des Servers und das Token dieses Telefons.
/// Die App schreibt es beim Anmelden und löscht es beim Abmelden.
struct GemeinsameVerbindung: Codable {
  let server: String
  let token: String

  private static let dienst = "de.dasevo.photovault.verbindung"

  /// `<Team>.<Kennung der App>.gemeinsam` – Präfix und Kennung trägt jedes
  /// Ziel in seiner Info.plist (`AppIdentifierPrefix`, `PVAppKennung`).
  static var gruppe: String? {
    guard
      let praefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
      let kennung = Bundle.main.object(forInfoDictionaryKey: "PVAppKennung") as? String,
      !praefix.isEmpty, !kennung.isEmpty
    else { return nil }
    return "\(praefix)\(kennung).gemeinsam"
  }

  private static func anfrage() -> [String: Any]? {
    guard let gruppe else { return nil }
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: dienst,
      kSecAttrAccount as String: "server",
      kSecAttrAccessGroup as String: gruppe,
    ]
  }

  static func lies() -> GemeinsameVerbindung? {
    guard var a = anfrage() else { return nil }
    a[kSecReturnData as String] = true
    a[kSecMatchLimit as String] = kSecMatchLimitOne
    var ergebnis: CFTypeRef?
    guard SecItemCopyMatching(a as CFDictionary, &ergebnis) == errSecSuccess,
      let daten = ergebnis as? Data
    else { return nil }
    return try? JSONDecoder().decode(GemeinsameVerbindung.self, from: daten)
  }

  /// Schreibt die Verbindung – oder löscht sie mit `nil`.
  @discardableResult
  static func schreibe(_ v: GemeinsameVerbindung?) -> Bool {
    guard let a = anfrage() else { return false }
    SecItemDelete(a as CFDictionary)
    guard let v, let daten = try? JSONEncoder().encode(v) else { return true }
    var neu = a
    neu[kSecValueData as String] = daten
    // Auch das Widget im gesperrten Telefon braucht sie – nach dem ersten
    // Entsperren seit dem Start.
    neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(neu as CFDictionary, nil) == errSecSuccess
  }

  /// Eine Anfrage an den Server mit dem Token dieses Telefons.
  func anfrage(_ pfad: String, methode: String = "GET") -> URLRequest? {
    let basis = server.hasSuffix("/") ? server : server + "/"
    let rest = pfad.hasPrefix("/") ? String(pfad.dropFirst()) : pfad
    guard let url = URL(string: basis + rest) else { return nil }
    var r = URLRequest(url: url)
    r.httpMethod = methode
    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    return r
  }
}

/// Deutsch oder Englisch, wie das Telefon – wie die App.
enum Sprache {
  static var deutsch: Bool {
    (Locale.preferredLanguages.first ?? "de").hasPrefix("de")
  }
}

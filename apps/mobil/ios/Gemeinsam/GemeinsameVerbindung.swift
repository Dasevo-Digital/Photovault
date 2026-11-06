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

  private static let konto = "server"

  static func lies() -> GemeinsameVerbindung? {
    guard let daten = GemeinsamerSpeicher.lies(konto) else { return nil }
    return try? JSONDecoder().decode(GemeinsameVerbindung.self, from: daten)
  }

  /// Schreibt die Verbindung – oder löscht sie mit `nil`.
  @discardableResult
  static func schreibe(_ v: GemeinsameVerbindung?) -> Bool {
    GemeinsamerSpeicher.schreibe(konto, v.flatMap { try? JSONEncoder().encode($0) })
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

/// Der gemeinsame Schlüsselbund, in dem die App und ihre Erweiterungen sich
/// kleine Einträge teilen.
enum GemeinsamerSpeicher {
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

  private static func anfrage(_ konto: String) -> [String: Any]? {
    guard let gruppe else { return nil }
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: dienst,
      kSecAttrAccount as String: konto,
      kSecAttrAccessGroup as String: gruppe,
    ]
  }

  static func lies(_ konto: String) -> Data? {
    guard var a = anfrage(konto) else { return nil }
    a[kSecReturnData as String] = true
    a[kSecMatchLimit as String] = kSecMatchLimitOne
    var ergebnis: CFTypeRef?
    guard SecItemCopyMatching(a as CFDictionary, &ergebnis) == errSecSuccess else { return nil }
    return ergebnis as? Data
  }

  /// Ob sich der Eintrag gerade lesen lässt, ob es ihn gibt oder nicht. Vor
  /// dem ersten Entsperren nach dem Start geht das nicht; [lies] sagt dann
  /// `nil`, als gäbe es ihn nicht.
  static func lesbar(_ konto: String) -> Bool {
    guard var a = anfrage(konto) else { return false }
    a[kSecMatchLimit as String] = kSecMatchLimitOne
    let s = SecItemCopyMatching(a as CFDictionary, nil)
    return s == errSecSuccess || s == errSecItemNotFound
  }

  /// Schreibt den Eintrag – oder löscht ihn mit `nil`.
  @discardableResult
  static func schreibe(_ konto: String, _ daten: Data?) -> Bool {
    guard let a = anfrage(konto) else { return false }
    SecItemDelete(a as CFDictionary)
    guard let daten else { return true }
    var neu = a
    neu[kSecValueData as String] = daten
    // Auch Erweiterungen im gesperrten Telefon brauchen ihn – nach dem
    // ersten Entsperren seit dem Start.
    neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(neu as CFDictionary, nil) == errSecSuccess
  }
}

/// Deutsch oder Englisch, wie das Telefon – wie die App.
enum Sprache {
  static var deutsch: Bool {
    (Locale.preferredLanguages.first ?? "de").hasPrefix("de")
  }
}

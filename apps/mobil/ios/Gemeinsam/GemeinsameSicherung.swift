import Foundation

/// Was die Erweiterung `Sofortsicherung` aus den Einstellungen der App
/// braucht. Die App schreibt es, sobald sich etwas ändert; kein Eintrag
/// heisst: Die Sicherung ist aus.
struct GemeinsameSicherung: Codable {
  var videos: Bool
  var nurWlan: Bool

  /// Die Kennungen der gewählten Alben; leer heisst alle Fotos.
  var alben: [String]

  /// Seit wann die Erweiterung zuständig ist. Was älter ist, sichert die
  /// App; ändert sich der Wert, beginnt die Erweiterung neu.
  var ab: Date

  /// Bis wann die App alles gesichert hat. Schaut der Nutzer nach dem Foto
  /// in die App, ist es meist längst oben; die Erweiterung braucht es dann
  /// nicht noch einmal zu schicken.
  var geschafft: Date?

  private static let konto = "sicherung"

  /// `false`, solange der Schlüsselbund gesperrt ist: Dann lässt sich nicht
  /// sagen, ob die Sicherung aus ist.
  static var lesbar: Bool { GemeinsamerSpeicher.lesbar(konto) }

  static func lies() -> GemeinsameSicherung? {
    guard let daten = GemeinsamerSpeicher.lies(konto) else { return nil }
    return try? JSONDecoder().decode(GemeinsameSicherung.self, from: daten)
  }

  @discardableResult
  static func schreibe(_ e: GemeinsameSicherung?) -> Bool {
    GemeinsamerSpeicher.schreibe(konto, e.flatMap { try? JSONEncoder().encode($0) })
  }
}

/// Was die Erweiterung zuletzt getan hat – die App zeigt es an. Wann iOS
/// sie startet, sagt es nicht vorher; ohne diese Spur liesse sich nicht
/// unterscheiden, ob sie nichts zu tun hatte oder gar nicht lief.
struct Sofortbericht: Codable {
  /// Wann iOS die Erweiterung zuletzt gestartet hat.
  var zeit: Date

  /// So viele Dateien kamen seit dem Einschalten im Hintergrund an.
  var gesichert: Int

  /// So viele scheiterten endgültig; die App holt sie nach.
  var gescheitert: Int

  /// So viele warten gerade beim System.
  var unterwegs: Int

  var fehler: String?

  private static let konto = "sofortbericht"

  static func lies() -> Sofortbericht? {
    guard let daten = GemeinsamerSpeicher.lies(konto) else { return nil }
    return try? JSONDecoder().decode(Sofortbericht.self, from: daten)
  }

  @discardableResult
  static func schreibe(_ b: Sofortbericht?) -> Bool {
    GemeinsamerSpeicher.schreibe(konto, b.flatMap { try? JSONEncoder().encode($0) })
  }
}

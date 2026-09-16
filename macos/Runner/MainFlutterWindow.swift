import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  /// Gesetzt, sobald das Schliessen freigegeben ist – siehe
  /// [windowShouldClose].
  private var darfSchliessen = false

  /// Unter diesem Schlüssel liegen Grösse und Ort des Fensters.
  ///
  /// Er darf sich nie ändern: Ein neuer Name hiesse, dass alle ihre
  /// Fenstergrösse verlieren.
  ///
  /// **Warum von Hand und nicht über `setFrameAutosaveName`.** Cocoa
  /// bringt dafür einen Merknamen mit, der eine Zeile statt zwanzig
  /// wäre. Der kann aber zweierlei nicht, was hier gebraucht wird: eine
  /// Untergrenze für die Grösse, und die Frage, ob das gemerkte Fenster
  /// auf einem noch angeschlossenen Bildschirm läge. Beides steht in
  /// [lageZurueckholen]. Ausserdem liegt es damit auf allen drei
  /// Plattformen gleich – unter Linux und Windows gibt es nichts
  /// Eingebautes.
  private static let fensterMerkschluessel = "PhotoVaultFensterlage"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // macOS bringt eine eigene Fensterwiederherstellung mit, und die
    // greift NACH `awakeFromNib`: Gemessen setzte sie den gemerkten Stand
    // sofort wieder auf den der letzten Sitzung zurueck. Zwei Mechanismen
    // fuer dieselbe Sache streiten sich immer; abgeschaltet wird der
    // fremde, weil nur der eigene die beiden Vorbehalte kennt
    // (Untergrenze, angeschlossener Bildschirm) und weil er auf allen
    // drei Plattformen derselbe ist. Ausserdem laesst die
    // Wiederherstellung nach einem Absturz nichts uebrig - unsere Datei
    // schon.
    self.isRestorable = false
    lageZurueckholen()

    RegisterGeneratedPlugins(registry: flutterViewController)
      ImageConverterChannel.register(with: flutterViewController.registrar(forPlugin: "ImageConverter"))
      LibraryLocationChannel.register(with: flutterViewController.registrar(forPlugin: "LibraryLocation"))
      BeendenChannel.register(with: flutterViewController.registrar(forPlugin: "Beenden"))

    // Das Fenster ist sein eigener Delegierter, damit der rote Schliessknopf
    // dieselbe Rückfrage auslöst wie Cmd-Q. Über
    // `applicationShouldTerminate` allein käme sie zu spät: Das Fenster wäre
    // dann bereits zu, und ein Abbrechen liesse die App ohne Fenster
    // zurück.
    self.delegate = self

    super.awakeFromNib()
  }

  /// Holt Grösse und Ort des letzten Laufs zurück.
  ///
  /// Nichts Gemerktes, etwas Unleserliches oder ein Fenster, das auf
  /// keinem angeschlossenen Bildschirm mehr läge (ein abgezogener zweiter
  /// Monitor), bleibt ohne Wirkung – dann gilt die Vorgabe. Ein Fenster,
  /// das man nicht sieht, wäre schlimmer als ein zu kleines.
  private func lageZurueckholen() {
    guard let gemerkt = UserDefaults.standard.string(
            forKey: MainFlutterWindow.fensterMerkschluessel)
    else { return }
    let lage = NSRectFromString(gemerkt)
    guard lage.width >= 640, lage.height >= 480 else { return }
    let sichtbar = NSScreen.screens.contains { $0.visibleFrame.intersects(lage) }
    guard sichtbar else { return }
    self.setFrame(lage, display: true)
  }

  private func lageSichern() {
    UserDefaults.standard.set(NSStringFromRect(self.frame),
                              forKey: MainFlutterWindow.fensterMerkschluessel)
  }

  // Beim Ziehen kommt das dutzendfach je Sekunde; UserDefaults sammelt
  // das selbst und schreibt gebündelt auf die Platte.
  func windowDidResize(_ notification: Notification) { lageSichern() }
  func windowDidMove(_ notification: Notification) { lageSichern() }

  // Und noch einmal beim Schliessen: Wer das Fenster maximiert und sofort
  // zumacht, soll es maximiert wiederfinden.
  func windowWillClose(_ notification: Notification) { lageSichern() }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if darfSchliessen { return true }
    BeendenChannel.frage { erlaubt in
      guard erlaubt else { return }
      self.darfSchliessen = true
      // Zurückgestellt, weil `frage` auch synchron antworten kann – ein
      // `close()` mitten in `windowShouldClose` wäre ein Aufruf in sich
      // selbst hinein.
      DispatchQueue.main.async { self.close() }
    }
    return false
  }
}

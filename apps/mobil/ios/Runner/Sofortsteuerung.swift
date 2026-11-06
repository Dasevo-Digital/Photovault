import Foundation
import Photos

/// Schaltet die Erweiterung `Sofortsicherung` ein oder aus (#308) und gibt
/// ihr die Einstellungen der Sicherung mit.
enum Sofortsteuerung {
  /// Was die Sicherung in der Einstellung gerade tut, für die Anzeige:
  /// `an`, `aus`, `system` (iOS zu alt) oder `zugriff` (ohne vollen Zugriff
  /// auf die Fotos startet iOS sie nicht); sonst der Text des Fehlers.
  static func setze(
    an: Bool, videos: Bool, nurWlan: Bool, alben: [String]
  ) -> String {
    guard #available(iOS 26.5, *) else { return "system" }
    let bibliothek = PHPhotoLibrary.shared()
    guard an else {
      schalteAus(bibliothek)
      return "aus"
    }
    guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
      schalteAus(bibliothek)
      return "zugriff"
    }
    let bisher = GemeinsameSicherung.lies()
    if bisher == nil { Sofortbericht.schreibe(nil) }
    GemeinsameSicherung.schreibe(
      GemeinsameSicherung(
        videos: videos, nurWlan: nurWlan, alben: alben, ab: bisher?.ab ?? Date(),
        geschafft: bisher?.geschafft))
    do {
      if !bibliothek.uploadJobExtensionEnabled {
        try bibliothek.setUploadJobExtensionEnabled(true)
      }
      return "an"
    } catch {
      return "\(error)"
    }
  }

  /// Die App hat alles gesichert, was bis [zeit] entstand.
  static func geschafft(bis zeit: Date) {
    guard var e = GemeinsameSicherung.lies() else { return }
    e.geschafft = zeit
    GemeinsameSicherung.schreibe(e)
  }

  /// Was schon beim System wartet, geht nicht mehr hoch.
  @available(iOS 26.5, *)
  private static func schalteAus(_ bibliothek: PHPhotoLibrary) {
    GemeinsameSicherung.schreibe(nil)
    guard bibliothek.uploadJobExtensionEnabled else { return }
    var offen: [PHAssetResourceUploadJob] = []
    PHAssetResourceUploadJob.fetchJobs(action: .process, options: nil)
      .enumerateObjects { job, _, _ in offen.append(job) }
    try? bibliothek.performChangesAndWait {
      for job in offen {
        PHAssetResourceUploadJobChangeRequest(for: job)?.cancel()
      }
    }
    try? bibliothek.setUploadJobExtensionEnabled(false)
  }

  /// Der Bericht der Erweiterung als JSON-Text; `nil`, wenn sie noch nie
  /// lief.
  static var bericht: String? {
    guard let b = Sofortbericht.lies() else { return nil }
    let werte: [String: Any?] = [
      "zeit": Int64(b.zeit.timeIntervalSince1970 * 1000),
      "gesichert": b.gesichert,
      "gescheitert": b.gescheitert,
      "unterwegs": b.unterwegs,
      "fehler": b.fehler,
    ]
    guard
      let daten = try? JSONSerialization.data(
        withJSONObject: werte.compactMapValues { $0 })
    else { return nil }
    return String(data: daten, encoding: .utf8)
  }
}

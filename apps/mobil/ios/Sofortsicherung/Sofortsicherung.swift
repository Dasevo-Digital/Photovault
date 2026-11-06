import ExtensionFoundation
import Foundation
import Network
import OSLog
import Photos

private let protokoll = Logger(subsystem: "de.dasevo.photovault", category: "sofortsicherung")

/// Sichert neue Fotos, wenn die App nicht läuft (#308).
///
/// Eine Hintergrundaufgabe der App kommt unter iOS selten dran, meist nachts
/// am Ladekabel. Diese Erweiterung dagegen startet das System von sich aus,
/// wenn Netz und Akku passen, und das Hochladen übernimmt es dann selbst –
/// auch im gesperrten Telefon und ohne dass die App läuft. Sie gibt dafür
/// nur Aufträge auf (`PHAssetResourceUploadJob`).
///
/// **Wann, bestimmt iOS.** Sofort im strengen Sinn ist das nicht, und in
/// manchen Fassungen von iOS startet das System die Erweiterung lange
/// nicht. Sie ersetzt darum die Sicherung der App nicht: Die App sieht beim
/// nächsten Lauf, was hier nicht ankam, und holt es nach. Umgekehrt ist
/// eine Datei, die beide schicken, kein Schaden – der Server erkennt sie
/// an der Prüfsumme.
///
/// Der Stand liegt in den `UserDefaults` der Erweiterung, Verbindung und
/// Einstellungen im gemeinsamen Schlüsselbund (siehe
/// `GemeinsameVerbindung`).
@main
final class Sofortsicherung: PHBackgroundResourceUploadExtension {
  required init() {}

  func process() -> PHBackgroundResourceUploadProcessingResult {
    // Vor dem ersten Entsperren: nicht mit „Sicherung aus“ verwechseln.
    guard GemeinsameSicherung.lesbar else { return .processing }
    var bericht =
      Sofortbericht.lies()
      ?? Sofortbericht(zeit: Date(), gesichert: 0, gescheitert: 0, unterwegs: 0)
    bericht.zeit = Date()
    bericht.fehler = nil
    defer { Sofortbericht.schreibe(bericht) }

    let lauf = Sofortlauf()
    do {
      let fertig = try lauf.raeumeAuf()
      bericht.gesichert += fertig.gesichert
      bericht.gescheitert += fertig.gescheitert
      try lauf.reiheEin()
      bericht.unterwegs = lauf.unterwegs()
      protokoll.info("Lauf fertig, unterwegs: \(bericht.unterwegs)")
      return lauf.hatArbeit ? .processing : .completed
    } catch let f as NSError
      where f.domain == PHPhotosErrorDomain && f.code == PHPhotosError.limitExceeded.rawValue
    {
      // Die Warteschlange des Systems ist voll: Beim nächsten Start ist
      // wieder Platz.
      bericht.unterwegs = lauf.unterwegs()
      return .processing
    } catch {
      protokoll.error("Lauf gescheitert: \(error, privacy: .public)")
      bericht.fehler = "\(error)"
      return .failure
    }
  }

  func notifyTermination() {
    // Jeder Schritt ist für sich abgeschlossen; aufzuräumen gibt es nichts.
    protokoll.info("Das System beendet die Erweiterung")
  }
}

/// Ein Durchgang der Erweiterung: die Aufträge beim System. Was als
/// Nächstes dran ist, entscheidet [Sofortauswahl].
final class Sofortlauf {
  private let bibliothek = PHPhotoLibrary.shared()

  /// `nil`: Die Sicherung ist aus oder das Telefon abgemeldet.
  private let auswahl: Sofortauswahl? = {
    guard let v = GemeinsameVerbindung.lies(), let e = GemeinsameSicherung.lies() else {
      return nil
    }
    return Sofortauswahl(verbindung: v, einstellungen: e)
  }()

  /// Ob es beim nächsten Start noch etwas zu tun gibt.
  var hatArbeit: Bool {
    auswahl?.wartet == true || unterwegs() > 0 || !auftraege(.acknowledge).isEmpty
  }

  private func auftraege(_ was: PHAssetResourceUploadJob.Action) -> [PHAssetResourceUploadJob] {
    var aus: [PHAssetResourceUploadJob] = []
    PHAssetResourceUploadJob.fetchJobs(action: was, options: nil).enumerateObjects { job, _, _ in
      aus.append(job)
    }
    return aus
  }

  func unterwegs() -> Int { auftraege(.process).count }

  /// Wiederholt, was gescheitert ist, einmal mit frischer Anmeldung und
  /// quittiert den Rest: Erst danach ist für neue Aufträge wieder Platz.
  /// Ist die Sicherung aus oder das Telefon abgemeldet, wird nichts mehr
  /// hochgeladen.
  func raeumeAuf() throws -> (gesichert: Int, gescheitert: Int) {
    var wiederholt = Set<String>()
    if let auswahl {
      let nochmal = auftraege(.retry).compactMap { job in
        auswahl.ziel(wie: job.destination).map { (job, $0) }
      }
      if !nochmal.isEmpty {
        try bibliothek.performChangesAndWait {
          for (job, ziel) in nochmal {
            PHAssetResourceUploadJobChangeRequest(for: job)?.retry(destination: ziel)
          }
        }
        wiederholt = Set(nochmal.map(\.0.localIdentifier))
      }
    } else {
      let offen = auftraege(.process)
      if !offen.isEmpty {
        try bibliothek.performChangesAndWait {
          for job in offen {
            PHAssetResourceUploadJobChangeRequest(for: job)?.cancel()
          }
        }
      }
    }
    let fertig = auftraege(.acknowledge).filter { !wiederholt.contains($0.localIdentifier) }
    if !fertig.isEmpty {
      try bibliothek.performChangesAndWait {
        for job in fertig {
          PHAssetResourceUploadJobChangeRequest(for: job)?.acknowledge()
        }
      }
    }
    let gesichert = fertig.filter { $0.state == .succeeded }.count
    return (gesichert, fertig.count - gesichert)
  }

  /// Gibt für neue Fotos Aufträge auf, so viele das System annimmt.
  func reiheEin() throws {
    guard let auswahl else {
      Sofortauswahl.vergiss()
      return
    }
    try auswahl.merkeNeue()
    // Die Aufträge selbst lassen sich vor iOS 27 nicht aufs WLAN festlegen;
    // die Angaben in `ziel` sind nur eine Bitte an das System.
    if auswahl.einstellungen.nurWlan && Self.imMobilfunk() { return }

    let (dateien, erledigt) = auswahl.naechste(frei: freiePlaetze())
    if !dateien.isEmpty {
      try bibliothek.performChangesAndWait {
        for datei in dateien {
          _ = PHAssetResourceUploadJobChangeRequest.creationRequestForJob(
            destination: datei.ziel, resource: datei.quelle)
        }
      }
    }
    auswahl.bestaetige(erledigt)
  }

  private func freiePlaetze() -> Int {
    let belegt = Set(
      (auftraege(.process) + auftraege(.retry) + auftraege(.acknowledge)).map(\.localIdentifier))
    return max(0, PHAssetResourceUploadJob.jobLimit - belegt.count)
  }

  /// Ob das Telefon gerade über Mobilfunk im Netz ist. Ein Hotspot gilt als
  /// WLAN, wie in `netzPasst` der App.
  private static func imMobilfunk() -> Bool {
    let antwort = DispatchSemaphore(value: 0)
    let beobachter = NWPathMonitor()
    var mobil = false
    beobachter.pathUpdateHandler = { pfad in
      mobil = pfad.usesInterfaceType(.cellular) && !pfad.usesInterfaceType(.wifi)
      antwort.signal()
    }
    beobachter.start(queue: DispatchQueue(label: "de.dasevo.photovault.netz"))
    _ = antwort.wait(timeout: .now() + 2)
    beobachter.cancel()
    return mobil
  }
}

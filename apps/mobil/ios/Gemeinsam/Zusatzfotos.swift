import Foundation
import Photos

/// Was die Sicherung über `photo_manager` nicht erreicht (#314): die übrigen
/// Bilder einer Serie. Das Plugin setzt `includeAllBurstAssets` nie; in der
/// Rolle stand von einer Serie deshalb nur das Titelbild, und die übrigen
/// Bilder lagen nirgends sonst.
///
/// Ausgeblendete Fotos gehören nicht dazu: Gemessen unter iOS 26.5 mit vollem
/// Zugriff liefert PhotoKit sie auch mit `includeHiddenAssets` nicht, weder
/// in Listen noch über ihre Kennung, obwohl sie in der Mediathek liegen.
enum Zusatzfotos {
  private static var ohneFilter: PHFetchOptions {
    let o = PHFetchOptions()
    o.includeAllBurstAssets = true
    return o
  }

  /// Hier liegen die Kopien, bis die Sicherung sie hochgeladen hat.
  private static var ordner: URL {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("zusatzfotos", isDirectory: true)
  }

  /// Alle Bilder jeder Serie, auch ihr Titelbild. [alben] leer heisst alle
  /// Fotos; sonst zählt von einer Serie, die in einem Album liegt, die ganze
  /// Serie.
  static func liste(alben: [String]) -> [[String: Any]] {
    var gefunden: [String: PHAsset] = [:]
    func nimm(_ foto: PHAsset) {
      if foto.burstIdentifier != nil { gefunden[foto.localIdentifier] = foto }
    }
    if alben.isEmpty {
      PHAsset.fetchAssets(with: ohneFilter).enumerateObjects { foto, _, _ in nimm(foto) }
    } else {
      var serien = Set<String>()
      PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: alben, options: nil)
        .enumerateObjects { album, _, _ in
          PHAsset.fetchAssets(in: album, options: ohneFilter).enumerateObjects { foto, _, _ in
            nimm(foto)
            if let serie = foto.burstIdentifier { serien.insert(serie) }
          }
        }
      for serie in serien {
        PHAsset.fetchAssets(withBurstIdentifier: serie, options: ohneFilter)
          .enumerateObjects { foto, _, _ in nimm(foto) }
      }
    }
    return gefunden.values.map(wert)
  }

  /// Welche von [kennungen] zu einer Serie gehören.
  static func serienglieder(_ kennungen: [String]) -> [String] {
    var aus: [String] = []
    PHAsset.fetchAssets(withLocalIdentifiers: kennungen, options: ohneFilter)
      .enumerateObjects { foto, _, _ in
        if foto.burstIdentifier != nil { aus.append(foto.localIdentifier) }
      }
    return aus
  }

  /// Kopiert die Originale eines Fotos in den Zwischenspeicher, auch aus
  /// iCloud. Dieselben Teile wie in `PhotoManagerRolle`. `nil`, wenn das
  /// Foto weg ist oder sich nicht laden lässt.
  static func dateien(kennung: String, fertig: @escaping ([[String: String]]?) -> Void) {
    guard
      let foto = PHAsset.fetchAssets(withLocalIdentifiers: [kennung], options: ohneFilter)
        .firstObject
    else {
      fertig(nil)
      return
    }
    let alle = PHAssetResource.assetResources(for: foto)
    let arten: [(PHAssetResourceType, String)] =
      foto.mediaType == .video
      ? [(.video, "video")]
      : [(.photo, "bild"), (.pairedVideo, "video"), (.fullSizePhoto, "bearbeitet")]
    let teile = arten.compactMap { art, teil in
      alle.first { $0.type == art }.map { (teil, $0) }
    }
    guard let haupt = teile.first, haupt.0 == "bild" || haupt.0 == "video" else {
      fertig(nil)
      return
    }
    let ziel = ordner.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: ziel, withIntermediateDirectories: true)
    } catch {
      fertig(nil)
      return
    }
    let optionen = PHAssetResourceRequestOptions()
    optionen.isNetworkAccessAllowed = true
    let stamm = (haupt.1.originalFilename as NSString).deletingPathExtension
    var aus: [[String: String]] = []
    func naechste(_ i: Int) {
      guard i < teile.count else {
        fertig(aus)
        return
      }
      let (teil, quelle) = teile[i]
      let datei = ziel.appendingPathComponent("\(i)-\(quelle.originalFilename)")
      PHAssetResourceManager.default().writeData(for: quelle, toFile: datei, options: optionen) {
        fehler in
        guard fehler == nil else {
          fertig(nil)
          return
        }
        // Wie in der App: Ein eigener Stamm, sonst gälte die Bearbeitung
        // ohne Original auf dem Server als Hälfte eines Live Photos.
        let endung = (quelle.originalFilename as NSString).pathExtension
        let name = teil == "bearbeitet" ? "\(stamm)_bearbeitet.\(endung)" : quelle.originalFilename
        aus.append(["teil": teil, "name": name, "pfad": datei.path])
        naechste(i + 1)
      }
    }
    naechste(0)
  }

  static func aufraeumen() {
    try? FileManager.default.removeItem(at: ordner)
  }

  private static func wert(_ foto: PHAsset) -> [String: Any] {
    var w: [String: Any] = [
      "id": foto.localIdentifier,
      "aufgenommen": ms(foto.creationDate),
      "geaendert": ms(foto.modificationDate ?? foto.creationDate),
      "video": foto.mediaType == .video,
      "titel": foto.representsBurst,
    ]
    if let serie = foto.burstIdentifier { w["serie"] = serie }
    return w
  }

  /// Auf ganze Sekunden, wie `photo_manager` die Zeiten liefert.
  private static func ms(_ zeit: Date?) -> Int64 {
    Int64(zeit?.timeIntervalSince1970 ?? 0) * 1000
  }
}

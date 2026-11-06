import Foundation
import Photos

/// Welche Dateien die Erweiterung `Sofortsicherung` als Nächstes aufgibt
/// (#308): neue Fotos finden, sie sich merken und daraus Anfragen bauen.
///
/// Getrennt von den Aufträgen, denn die gibt es nur auf einem echten Gerät.
/// Das hier läuft auch im Simulator und wird dort geprüft
/// (`RunnerTests/SofortauswahlTests.swift`).
final class Sofortauswahl {
  init(
    verbindung: GemeinsameVerbindung, einstellungen: GemeinsameSicherung,
    stand: UserDefaults = .standard, bibliothek: PHPhotoLibrary = .shared()
  ) {
    self.verbindung = verbindung
    self.einstellungen = einstellungen
    self.stand = stand
    self.bibliothek = bibliothek
  }

  /// Eine Datei und wohin sie geht.
  struct Datei {
    let ziel: URLRequest
    let quelle: PHAssetResource
  }

  private let verbindung: GemeinsameVerbindung
  let einstellungen: GemeinsameSicherung
  private let stand: UserDefaults
  private let bibliothek: PHPhotoLibrary

  private enum Schluessel {
    static let marke = "marke"
    static let ab = "ab"
    static let schlange = "schlange"
  }

  /// So viele Fotos merkt sich die Warteschlange höchstens. Was darüber
  /// hinausgeht (ein ganzes Fotoarchiv kommt aus iCloud), sichert die App.
  static let hoechstensInSchlange = 2000

  private var schlange: [String] {
    get { stand.stringArray(forKey: Schluessel.schlange) ?? [] }
    set { stand.set(newValue, forKey: Schluessel.schlange) }
  }

  /// Ob noch Fotos warten.
  var wartet: Bool { !schlange.isEmpty }

  /// Die Sicherung ist aus: Beim nächsten Einschalten beginnt alles neu.
  static func vergiss(_ stand: UserDefaults = .standard) {
    stand.removeObject(forKey: Schluessel.marke)
    stand.removeObject(forKey: Schluessel.schlange)
  }

  /// Merkt sich, was seit dem letzten Mal in die Mediathek kam, nach ihrem
  /// eigenen Änderungsprotokoll: Darin steht auch ein Foto aus AirDrop oder
  /// aus einer Nachricht, dessen Aufnahmedatum weit zurückliegt.
  func merkeNeue() throws {
    let ab = einstellungen.ab.timeIntervalSince1970
    if abs(stand.double(forKey: Schluessel.ab) - ab) > 0.001 {
      Self.vergiss(stand)
      stand.set(ab, forKey: Schluessel.ab)
    }
    var neu: [String] = []
    if let marke = lesMarke() {
      do {
        var letzte = marke
        for aenderung in try bibliothek.fetchPersistentChanges(since: marke) {
          neu += try aenderung.changeDetails(for: .asset).insertedLocalIdentifiers
          letzte = aenderung.changeToken
        }
        schreibMarke(letzte)
      } catch let f as NSError
        where f.domain == PHPhotosErrorDomain
        && f.code == PHPhotosError.persistentChangeTokenExpired.rawValue
      {
        // Das Protokoll reicht nicht so weit zurück; die App holt nach.
        schreibMarke(bibliothek.currentChangeToken)
      }
    } else {
      // Beim ersten Start: alles seit dem Einschalten.
      let o = PHFetchOptions()
      o.predicate = NSPredicate(format: "creationDate >= %@", einstellungen.ab as NSDate)
      o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
      PHAsset.fetchAssets(with: o).enumerateObjects { foto, _, _ in
        neu.append(foto.localIdentifier)
      }
      schreibMarke(bibliothek.currentChangeToken)
    }
    guard !neu.isEmpty else { return }
    var alle = schlange
    let bekannt = Set(alle)
    alle += neu.filter { !bekannt.contains($0) }
    schlange = Array(alle.suffix(Self.hoechstensInSchlange))
  }

  /// Die nächsten Dateien, höchstens [frei] – ein Live Photo besteht aus
  /// zweien und wird nie geteilt. [erledigt] gehört danach an [bestaetige],
  /// sobald die Aufträge stehen. Was gelöscht, ausgeblendet oder nicht
  /// gewählt ist, fällt dabei heraus.
  func naechste(frei: Int) -> (dateien: [Datei], erledigt: Set<String>) {
    var platz = frei
    var aus: [Datei] = []
    var erledigt = Set<String>()
    let kennungen = schlange
    let fotos = auswaehlen(kennungen)
    for kennung in kennungen {
      guard platz > 0 else { break }
      guard let foto = fotos[kennung] else {
        erledigt.insert(kennung)
        continue
      }
      let dateien = Self.dateien(von: foto).compactMap { quelle in
        ziel(name: quelle.originalFilename, aufnahme: foto.creationDate).map {
          Datei(ziel: $0, quelle: quelle)
        }
      }
      guard dateien.count <= platz else { break }
      aus += dateien
      platz -= dateien.count
      erledigt.insert(kennung)
    }
    return (aus, erledigt)
  }

  func bestaetige(_ erledigt: Set<String>) {
    guard !erledigt.isEmpty else { return }
    schlange = schlange.filter { !erledigt.contains($0) }
  }

  private func lesMarke() -> PHPersistentChangeToken? {
    guard let daten = stand.data(forKey: Schluessel.marke) else { return nil }
    return try? NSKeyedUnarchiver.unarchivedObject(
      ofClass: PHPersistentChangeToken.self, from: daten)
  }

  private func schreibMarke(_ marke: PHPersistentChangeToken) {
    let daten = try? NSKeyedArchiver.archivedData(
      withRootObject: marke, requiringSecureCoding: true)
    stand.set(daten, forKey: Schluessel.marke)
  }

  /// Die Fotos zu [kennungen], die nach den Einstellungen dazugehören. Was
  /// die App schon gesichert hat, braucht nicht noch einmal zu gehen.
  private func auswaehlen(_ kennungen: [String]) -> [String: PHAsset] {
    guard !kennungen.isEmpty else { return [:] }
    var fotos: [String: PHAsset] = [:]
    let geschafft = einstellungen.geschafft ?? .distantPast
    PHAsset.fetchAssets(withLocalIdentifiers: kennungen, options: nil)
      .enumerateObjects { foto, _, _ in
        guard (foto.creationDate ?? .distantFuture) > geschafft else { return }
        if foto.mediaType == .image
          || (foto.mediaType == .video && self.einstellungen.videos)
        {
          fotos[foto.localIdentifier] = foto
        }
      }
    guard !einstellungen.alben.isEmpty else { return fotos }
    var gewaehlt: [String: PHAsset] = [:]
    let o = PHFetchOptions()
    o.predicate = NSPredicate(format: "localIdentifier IN %@", kennungen)
    PHAssetCollection.fetchAssetCollections(
      withLocalIdentifiers: einstellungen.alben, options: nil
    ).enumerateObjects { album, _, _ in
      PHAsset.fetchAssets(in: album, options: o).enumerateObjects { foto, _, _ in
        gewaehlt[foto.localIdentifier] = fotos[foto.localIdentifier]
      }
    }
    return gewaehlt
  }

  /// Die Originale, dieselben wie in der App (`PhotoManagerRolle`) – so
  /// erkennt der Server eine Datei wieder, die beide schicken. Beim Live
  /// Photo gehört das Video dazu; der Server fügt beide am gemeinsamen
  /// Namensstamm zusammen. Eine Bearbeitung in der Fotos-App bringt die
  /// App nach.
  private static func dateien(von foto: PHAsset) -> [PHAssetResource] {
    let alle = PHAssetResource.assetResources(for: foto)
    let arten: [PHAssetResourceType] = foto.mediaType == .video ? [.video] : [.photo, .pairedVideo]
    return arten.compactMap { art in alle.first { $0.type == art } }
  }

  private func ziel(name: String, aufnahme: Date?) -> URLRequest? {
    var teile = URLComponents()
    teile.queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(
        name: "geaendert",
        value: aufnahme.map { String(Int64($0.timeIntervalSince1970 * 1000)) }),
    ].filter { $0.value != nil }
    guard let abfrage = teile.percentEncodedQuery else { return nil }
    return ziel(abfrage: abfrage.replacingOccurrences(of: "+", with: "%2B"))
  }

  /// Dasselbe Ziel wie [alt], mit der aktuellen Adresse und Anmeldung: Ein
  /// Auftrag kann lange warten.
  func ziel(wie alt: URLRequest) -> URLRequest? {
    guard let abfrage = alt.url?.query(percentEncoded: true) else { return nil }
    return ziel(abfrage: abfrage)
  }

  private func ziel(abfrage: String) -> URLRequest? {
    guard var r = verbindung.anfrage("api/v1/sofort?\(abfrage)", methode: "PUT") else {
      return nil
    }
    r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    r.allowsCellularAccess = !einstellungen.nurWlan
    r.allowsExpensiveNetworkAccess = !einstellungen.nurWlan
    return r
  }
}

import AVFoundation
import CoreMedia
import CryptoKit
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
import XCTest

/// Was die Erweiterung `Sofortsicherung` aufgibt (#308), gegen die echte
/// Mediathek des Simulators. Die Aufträge selbst gibt es dort nicht; was das
/// System mit ihnen täte, steht in [testHochladenWieDasSystem].
///
/// Löscht, was es anlegt, nicht wieder: iOS fragte dafür jedes Mal nach. Also
/// nur in einem eigenen Simulator laufen lassen, und zwar nacheinander
/// (`-parallel-testing-enabled NO`): Kopien des Simulators haben den Zugriff
/// nicht. Ohne vollen Zugriff auf die Mediathek wird alles **übersprungen**,
/// und xcodebuild meldet trotzdem Erfolg.
///
/// `simctl privacy … grant photos` reicht unter iOS 26.5 nicht: Es trägt die
/// alte Art des Zugriffs ein. Im `TCC.db` des Simulators muss für
/// `kTCCServicePhotos` zusätzlich `auth_version` 2 stehen (bei
/// heruntergefahrenem Simulator ändern).
///
/// Mit `TEST_RUNNER_PV_SERVER` und `TEST_RUNNER_PV_TOKEN` lädt es zu einem
/// echten Server hoch.
final class SofortauswahlTests: XCTestCase {
  private var stand: UserDefaults!
  private var suite = ""
  private var beginn = Date()
  private let verbindung = GemeinsameVerbindung(server: "http://server.test/", token: "geheim")

  override func setUp() async throws {
    let zugriff = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    try XCTSkipUnless(
      zugriff == .authorized,
      "Braucht vollen Zugriff auf die Mediathek (\(zugriff.rawValue), \(Bundle.main.bundleIdentifier ?? "?"))"
    )
    suite = "sofort-\(UUID().uuidString)"
    stand = UserDefaults(suiteName: suite)
    beginn = Date()
  }

  override func tearDown() async throws {
    UserDefaults().removePersistentDomain(forName: suite)
  }

  private func auswahl(
    videos: Bool = true, nurWlan: Bool = true, alben: [String] = [], ab: Date? = nil,
    geschafft: Date? = nil, verbindung: GemeinsameVerbindung? = nil
  ) -> Sofortauswahl {
    Sofortauswahl(
      verbindung: verbindung ?? self.verbindung,
      einstellungen: GemeinsameSicherung(
        videos: videos, nurWlan: nurWlan, alben: alben, ab: ab ?? beginn, geschafft: geschafft),
      stand: stand)
  }

  // MARK: Neue Fotos finden

  func testErsterStartNimmtAllesSeitDemEinschalten() async throws {
    // Nicht in der Zukunft: Das Foto bliebe in der Mediathek und fiele dem
    // nächsten Test in die Hände.
    let zeit = beginn
    _ = try await legeFotoAn(aufgenommen: zeit, name: "IMG_1.JPG")
    let a = auswahl()
    try a.merkeNeue()
    let (dateien, erledigt) = a.naechste(frei: 10)
    XCTAssertEqual(dateien.count, 1)
    XCTAssertEqual(erledigt.count, 1)
    let r = try XCTUnwrap(dateien.first?.ziel)
    XCTAssertEqual(r.httpMethod, "PUT")
    XCTAssertEqual(r.url?.host, "server.test")
    XCTAssertEqual(r.url?.path, "/api/v1/sofort")
    XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
    XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
    let abfrage = try XCTUnwrap(URLComponents(url: r.url!, resolvingAgainstBaseURL: false))
    let werte = Dictionary(
      uniqueKeysWithValues: (abfrage.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(werte["name"], "IMG_1.JPG")
    let ms = try XCTUnwrap(Int64(werte["geaendert"] ?? ""))
    XCTAssertEqual(Double(ms) / 1000, zeit.timeIntervalSince1970, accuracy: 0.01)
  }

  func testAeltereFotosBleibenDerApp() async throws {
    _ = try await legeFotoAn(aufgenommen: beginn.addingTimeInterval(-3600), name: "ALT.JPG")
    let a = auswahl()
    try a.merkeNeue()
    XCTAssertFalse(a.wartet)
  }

  func testNeuesFotoMitAltemDatumKommtNachDemStartMit() async throws {
    let a = auswahl()
    try a.merkeNeue()
    XCTAssertFalse(a.wartet)
    // Wie aus AirDrop: Das Aufnahmedatum liegt weit zurück, neu ist es doch.
    _ = try await legeFotoAn(aufgenommen: Date(timeIntervalSince1970: 1_000_000), name: "A.JPG")
    try a.merkeNeue()
    XCTAssertEqual(a.naechste(frei: 10).dateien.count, 1)
  }

  func testEinNeuerLaufFindetDasselbeNichtNochmal() async throws {
    let a = auswahl()
    try a.merkeNeue()
    _ = try await legeFotoAn(aufgenommen: Date(), name: "B.JPG")
    try a.merkeNeue()
    a.bestaetige(a.naechste(frei: 10).erledigt)
    XCTAssertFalse(a.wartet)
    let zweiter = auswahl()
    try zweiter.merkeNeue()
    XCTAssertFalse(zweiter.wartet)
  }

  func testAuchEinZweiterLaufSiehtWasDazwischenKam() async throws {
    try auswahl().merkeNeue()
    _ = try await legeFotoAn(aufgenommen: Date(), name: "C.JPG")
    let zweiter = auswahl()
    try zweiter.merkeNeue()
    XCTAssertEqual(zweiter.naechste(frei: 10).dateien.count, 1)
  }

  func testNeuEinschaltenBeginntVonVorn() async throws {
    let a = auswahl()
    try a.merkeNeue()
    _ = try await legeFotoAn(aufgenommen: Date(), name: "D.JPG")
    try a.merkeNeue()
    XCTAssertTrue(a.wartet)
    let spaeter = auswahl(ab: Date().addingTimeInterval(60))
    try spaeter.merkeNeue()
    XCTAssertFalse(spaeter.wartet)
  }

  func testDieWarteschlangeBleibtBegrenzt() async throws {
    let a = auswahl()
    try a.merkeNeue()
    let n = Sofortauswahl.hoechstensInSchlange
    stand.set((0..<n).map { "alt-\($0)" }, forKey: "schlange")
    let foto = try await legeFotoAn(aufgenommen: Date(), name: "E.JPG")
    try a.merkeNeue()
    let schlange = stand.stringArray(forKey: "schlange") ?? []
    XCTAssertEqual(schlange.count, n)
    XCTAssertEqual(schlange.last, foto)
    XCTAssertEqual(schlange.first, "alt-1")
  }

  // MARK: Was dazugehört

  func testVideosLassenSichAbwaehlen() async throws {
    let a = auswahl(videos: false)
    try a.merkeNeue()
    _ = try await legeVideoAn(name: "V.MOV")
    try a.merkeNeue()
    let (dateien, erledigt) = a.naechste(frei: 10)
    XCTAssertTrue(dateien.isEmpty)
    a.bestaetige(erledigt)
    XCTAssertFalse(a.wartet, "Ein abgewähltes Video darf nicht ewig warten")
  }

  func testEinVideoGehtMit() async throws {
    let a = auswahl()
    try a.merkeNeue()
    _ = try await legeVideoAn(name: "W.MOV")
    try a.merkeNeue()
    let dateien = a.naechste(frei: 10).dateien
    XCTAssertEqual(dateien.map(\.quelle.type), [.video])
  }

  func testNurGewaehlteAlben() async throws {
    let album = try await legeAlbumAn()
    let a = auswahl(alben: [album])
    try a.merkeNeue()
    let drin = try await legeFotoAn(aufgenommen: Date(), name: "IN.JPG", album: album)
    _ = try await legeFotoAn(aufgenommen: Date(), name: "AUS.JPG")
    try a.merkeNeue()
    let (dateien, erledigt) = a.naechste(frei: 10)
    XCTAssertEqual(dateien.map(\.quelle.originalFilename), ["IN.JPG"])
    XCTAssertEqual(dateien.first?.quelle.assetLocalIdentifier, drin)
    a.bestaetige(erledigt)
    XCTAssertFalse(a.wartet)
  }

  func testWasDieAppGeschafftHatBleibtWeg() async throws {
    try auswahl().merkeNeue()
    let zeit = Date()
    _ = try await legeFotoAn(aufgenommen: zeit, name: "F.JPG")
    let a = auswahl(geschafft: zeit.addingTimeInterval(5))
    try a.merkeNeue()
    let (dateien, erledigt) = a.naechste(frei: 10)
    XCTAssertTrue(dateien.isEmpty)
    XCTAssertEqual(erledigt.count, 1)
  }

  func testEinAltesFotoNachDemLaufDerAppGehtMit() async throws {
    let a = auswahl(geschafft: Date().addingTimeInterval(-60))
    try a.merkeNeue()
    // Wie aus AirDrop, nachdem die App schon alles gesichert hatte.
    _ = try await legeFotoAn(aufgenommen: Date(timeIntervalSince1970: 1_000_000), name: "K.JPG")
    try a.merkeNeue()
    XCTAssertEqual(a.naechste(frei: 10).dateien.count, 1)
  }

  func testEinGeloeschtesFotoFaelltHeraus() async throws {
    let a = auswahl()
    try a.merkeNeue()
    stand.set(["gibt-es-nicht"], forKey: "schlange")
    let (dateien, erledigt) = a.naechste(frei: 10)
    XCTAssertTrue(dateien.isEmpty)
    a.bestaetige(erledigt)
    XCTAssertFalse(a.wartet)
  }

  func testOhnePlatzWartetDerRest() async throws {
    let a = auswahl()
    try a.merkeNeue()
    let erstes = try await legeFotoAn(aufgenommen: Date(), name: "G1.JPG")
    let zweites = try await legeFotoAn(aufgenommen: Date(), name: "G2.JPG")
    try a.merkeNeue()
    XCTAssertTrue(a.naechste(frei: 0).dateien.isEmpty)
    let eins = a.naechste(frei: 1)
    XCTAssertEqual(eins.erledigt, [erstes])
    a.bestaetige(eins.erledigt)
    XCTAssertTrue(a.wartet)
    XCTAssertEqual(a.naechste(frei: 1).erledigt, [zweites])
  }

  func testEinLivePhotoWirdNieGeteilt() async throws {
    let a = auswahl()
    try a.merkeNeue()
    _ = try await legeLivePhotoAn(stamm: "IMG_9001")
    try a.merkeNeue()
    let knapp = a.naechste(frei: 1)
    XCTAssertTrue(knapp.dateien.isEmpty)
    XCTAssertTrue(knapp.erledigt.isEmpty)
    let (dateien, _) = a.naechste(frei: 2)
    XCTAssertEqual(dateien.map(\.quelle.type), [.photo, .pairedVideo])
    XCTAssertEqual(
      dateien.map(\.quelle.originalFilename), ["IMG_9001.JPG", "IMG_9001.MOV"])
    // Dieselbe Zeit: Daran und am Namen erkennt der Server das Paar.
    XCTAssertEqual(
      dateien[0].ziel.url?.query?.split(separator: "&").last,
      dateien[1].ziel.url?.query?.split(separator: "&").last)
  }

  // MARK: Das Ziel

  func testMitNurWlanDarfMobilfunkNicht() async throws {
    let mit = auswahl(nurWlan: true)
    try mit.merkeNeue()
    _ = try await legeFotoAn(aufgenommen: Date(), name: "H.JPG")
    try mit.merkeNeue()
    let r = try XCTUnwrap(mit.naechste(frei: 1).dateien.first?.ziel)
    XCTAssertFalse(r.allowsCellularAccess)
    XCTAssertFalse(r.allowsExpensiveNetworkAccess)
    let ohne = auswahl(nurWlan: false)
    let q = try XCTUnwrap(ohne.ziel(wie: r))
    XCTAssertTrue(q.allowsCellularAccess)
    XCTAssertTrue(q.allowsExpensiveNetworkAccess)
  }

  func testNameMitSonderzeichenKommtHeil() async throws {
    let a = auswahl()
    try a.merkeNeue()
    let n = "Mein Foto + mehr & ü?#.JPG"
    _ = try await legeFotoAn(aufgenommen: Date(), name: n)
    try a.merkeNeue()
    let r = try XCTUnwrap(a.naechste(frei: 1).dateien.first?.ziel)
    let roh = try XCTUnwrap(r.url?.query(percentEncoded: true))
    XCTAssertFalse(roh.contains("+"), "Der Server läse ein Plus als Leerzeichen")
    XCTAssertEqual(
      URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?
        .queryItems?.first?.value, n)
  }

  func testEineWiederholungNimmtDieNeueAnmeldung() async throws {
    let a = auswahl()
    try a.merkeNeue()
    _ = try await legeFotoAn(aufgenommen: Date(), name: "J.JPG")
    try a.merkeNeue()
    let alt = try XCTUnwrap(a.naechste(frei: 1).dateien.first?.ziel)
    let neu = auswahl(
      verbindung: GemeinsameVerbindung(server: "https://neu.test/pv", token: "frisch"))
    let r = try XCTUnwrap(neu.ziel(wie: alt))
    XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer frisch")
    XCTAssertEqual(r.url?.host, "neu.test")
    XCTAssertEqual(r.url?.path, "/pv/api/v1/sofort")
    XCTAssertEqual(r.url?.query, alt.url?.query)
  }

  // MARK: Gegen einen echten Server

  /// Schickt die Dateien so, wie das System es täte: das Original als Körper
  /// der Anfrage, die [Sofortauswahl] baut.
  func testHochladenWieDasSystem() async throws {
    let umgebung = ProcessInfo.processInfo.environment
    guard let server = umgebung["PV_SERVER"], let token = umgebung["PV_TOKEN"] else {
      throw XCTSkip("Ohne Server")
    }
    let v = GemeinsameVerbindung(server: server, token: token)
    let a = auswahl(verbindung: v)
    try a.merkeNeue()
    let stamm = "IMG_\(Int(Date().timeIntervalSince1970))"
    _ = try await legeFotoAn(aufgenommen: Date(), name: "\(stamm)_A + B.JPG")
    _ = try await legeVideoAn(name: "\(stamm)_V.MOV")
    _ = try await legeLivePhotoAn(stamm: "\(stamm)_L")
    try a.merkeNeue()
    let dateien = a.naechste(frei: 10).dateien
    XCTAssertEqual(dateien.count, 4)

    var summen: [String] = []
    for d in dateien {
      let (status, antwort, summe) = try await lade(d)
      XCTAssertEqual(status, 201, d.quelle.originalFilename)
      XCTAssertEqual(antwort["ausgang"] as? String, "imported", d.quelle.originalFilename)
      XCTAssertNotNil(antwort["aufnahme"] as? String)
      summen.append(summe)
    }
    // Dasselbe noch einmal, etwa weil auch die App es geschickt hat.
    for d in dateien {
      let (status, antwort, _) = try await lade(d)
      XCTAssertEqual(status, 201)
      XCTAssertEqual(antwort["ausgang"] as? String, "duplicateSkipped")
    }
    // Das fragt der Lauf der App, bevor er hochlädt: Er findet alles vor.
    var frage = try XCTUnwrap(v.anfrage("api/v1/pruefsummen", methode: "POST"))
    frage.setValue("application/json", forHTTPHeaderField: "Content-Type")
    frage.httpBody = try JSONSerialization.data(withJSONObject: ["pruefsummen": summen])
    let (daten, _) = try await URLSession.shared.data(for: frage)
    let j = try XCTUnwrap(JSONSerialization.jsonObject(with: daten) as? [String: Any])
    let vorhanden = try XCTUnwrap(j["vorhanden"] as? [String: String])
    XCTAssertEqual(Set(vorhanden.keys), Set(summen))
  }

  private func lade(
    _ d: Sofortauswahl.Datei
  ) async throws -> (status: Int, antwort: [String: Any], summe: String) {
    let datei = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: datei) }
    try await PHAssetResourceManager.default().writeData(for: d.quelle, toFile: datei, options: nil)
    let (daten, antwort) = try await URLSession.shared.upload(for: d.ziel, fromFile: datei)
    let status = (antwort as? HTTPURLResponse)?.statusCode ?? 0
    let j = (try? JSONSerialization.jsonObject(with: daten) as? [String: Any]) ?? [:]
    let summe = SHA256.hash(data: try Data(contentsOf: datei))
      .map { String(format: "%02x", $0) }.joined()
    return (status, j, summe)
  }

  // MARK: Fotos anlegen

  private func bild(_ farbe: UIColor = .init(hue: .random(in: 0...1), saturation: 1, brightness: 1, alpha: 1)) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { k in
      farbe.setFill()
      k.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    }
  }

  private func legeFotoAn(
    aufgenommen: Date, name: String, album: String? = nil
  ) async throws -> String {
    let daten = try XCTUnwrap(bild().jpegData(compressionQuality: 0.9))
    var kennung = ""
    try await PHPhotoLibrary.shared().performChanges {
      let c = PHAssetCreationRequest.forAsset()
      c.creationDate = aufgenommen
      let o = PHAssetResourceCreationOptions()
      o.originalFilename = name
      c.addResource(with: .photo, data: daten, options: o)
      kennung = c.placeholderForCreatedAsset?.localIdentifier ?? ""
      if let album, let platz = c.placeholderForCreatedAsset,
        let sammlung = PHAssetCollection.fetchAssetCollections(
          withLocalIdentifiers: [album], options: nil
        ).firstObject
      {
        PHAssetCollectionChangeRequest(for: sammlung)?
          .addAssets([platz] as NSArray)
      }
    }
    return kennung
  }

  private func legeAlbumAn() async throws -> String {
    var kennung = ""
    try await PHPhotoLibrary.shared().performChanges {
      let c = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
        withTitle: "Test \(UUID().uuidString)")
      kennung = c.placeholderForCreatedAssetCollection.localIdentifier
    }
    return kennung
  }

  private func legeVideoAn(name: String) async throws -> String {
    let film = try await schreibeFilm(kennung: nil)
    defer { try? FileManager.default.removeItem(at: film) }
    var kennung = ""
    try await PHPhotoLibrary.shared().performChanges {
      let c = PHAssetCreationRequest.forAsset()
      let o = PHAssetResourceCreationOptions()
      o.originalFilename = name
      c.addResource(with: .video, fileURL: film, options: o)
      kennung = c.placeholderForCreatedAsset?.localIdentifier ?? ""
    }
    return kennung
  }

  /// Ein Live Photo: Bild und Film tragen dieselbe Kennung.
  private func legeLivePhotoAn(stamm: String) async throws -> String {
    let id = UUID().uuidString
    let film = try await schreibeFilm(kennung: id)
    defer { try? FileManager.default.removeItem(at: film) }
    let foto = NSMutableData()
    let ziel = try XCTUnwrap(
      CGImageDestinationCreateWithData(foto, UTType.jpeg.identifier as CFString, 1, nil))
    let angaben = [kCGImagePropertyMakerAppleDictionary: ["17": id]] as CFDictionary
    CGImageDestinationAddImage(ziel, try XCTUnwrap(bild().cgImage), angaben)
    XCTAssertTrue(CGImageDestinationFinalize(ziel))
    let daten = foto as Data
    var kennung = ""
    try await PHPhotoLibrary.shared().performChanges {
      let c = PHAssetCreationRequest.forAsset()
      let oB = PHAssetResourceCreationOptions()
      oB.originalFilename = "\(stamm).JPG"
      c.addResource(with: .photo, data: daten, options: oB)
      let oF = PHAssetResourceCreationOptions()
      oF.originalFilename = "\(stamm).MOV"
      c.addResource(with: .pairedVideo, fileURL: film, options: oF)
      kennung = c.placeholderForCreatedAsset?.localIdentifier ?? ""
    }
    return kennung
  }

  /// Ein Film von einer halben Sekunde. Mit [kennung] so ausgezeichnet, wie
  /// die Kamera die Hälfte eines Live Photos auszeichnet.
  private func schreibeFilm(kennung: String?) async throws -> URL {
    let datei = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).mov")
    let w = try AVAssetWriter(outputURL: datei, fileType: .mov)
    let bilder = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
      ])
    let puffer = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: bilder,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
      ])
    w.add(bilder)
    var standbild: AVAssetWriterInputMetadataAdaptor?
    if let kennung {
      let m = AVMutableMetadataItem()
      m.keySpace = .quickTimeMetadata
      m.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
      m.value = kennung as NSString
      m.dataType = kCMMetadataBaseDataType_UTF8 as String
      w.metadata = [m]
      let angaben: [String: Any] = [
        kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String:
          "mdta/com.apple.quicktime.still-image-time",
        kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String:
          kCMMetadataBaseDataType_SInt8 as String,
      ]
      var beschreibung: CMFormatDescription?
      CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
        allocator: kCFAllocatorDefault,
        metadataType: kCMMetadataFormatType_Boxed,
        metadataSpecifications: [angaben] as CFArray,
        formatDescriptionOut: &beschreibung)
      let spur = AVAssetWriterInput(
        mediaType: .metadata, outputSettings: nil, sourceFormatHint: beschreibung)
      let a = AVAssetWriterInputMetadataAdaptor(assetWriterInput: spur)
      w.add(spur)
      standbild = a
    }
    XCTAssertTrue(w.startWriting())
    w.startSession(atSourceTime: .zero)
    if let standbild {
      let m = AVMutableMetadataItem()
      m.key = "com.apple.quicktime.still-image-time" as NSString
      m.keySpace = .quickTimeMetadata
      m.value = 0 as NSNumber
      m.dataType = kCMMetadataBaseDataType_SInt8 as String
      let gruppe = AVTimedMetadataGroup(
        items: [m],
        timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 30)))
      XCTAssertTrue(standbild.append(gruppe))
      standbild.assetWriterInput.markAsFinished()
    }
    for i in 0..<15 {
      while !bilder.isReadyForMoreMediaData {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
      var p: CVPixelBuffer?
      CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &p)
      let b = try XCTUnwrap(p)
      CVPixelBufferLockBaseAddress(b, [])
      if let basis = CVPixelBufferGetBaseAddress(b) {
        memset(basis, Int32(i * 10), CVPixelBufferGetDataSize(b))
      }
      CVPixelBufferUnlockBaseAddress(b, [])
      XCTAssertTrue(puffer.append(b, withPresentationTime: CMTime(value: Int64(i), timescale: 30)))
    }
    bilder.markAsFinished()
    await w.finishWriting()
    XCTAssertEqual(w.status, .completed, "\(String(describing: w.error))")
    return datei
  }
}

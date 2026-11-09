import Photos
import UIKit
import XCTest

/// Was die Sicherung neben `photo_manager` holt (#314), gegen die echte
/// Mediathek des Simulators. Eine echte Serie lässt sich dort nicht anlegen;
/// geprüft wird der Weg der Dateien an einem gewöhnlichen Foto.
///
/// Braucht dieselben Voraussetzungen wie [SofortauswahlTests].
final class ZusatzfotosTests: XCTestCase {
  override func setUp() async throws {
    let zugriff = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    try XCTSkipUnless(zugriff == .authorized, "Braucht vollen Zugriff auf die Mediathek")
  }

  private func legeFotoAn(ausgeblendet: Bool = false) async throws -> String {
    let bild = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(
      withCompressionQuality: 0.9
    ) { kontext in
      UIColor.systemTeal.setFill()
      kontext.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    }
    var kennung = ""
    try await PHPhotoLibrary.shared().performChanges {
      let neu = PHAssetCreationRequest.forAsset()
      neu.addResource(with: .photo, data: bild, options: nil)
      neu.isHidden = ausgeblendet
      kennung = neu.placeholderForCreatedAsset!.localIdentifier
    }
    return kennung
  }

  func testGewoehnlicheFotosGehoerenNichtDazu() async throws {
    let kennung = try await legeFotoAn()
    XCTAssertFalse(Zusatzfotos.liste(alben: []).contains { $0["id"] as? String == kennung })
    XCTAssertEqual(Zusatzfotos.serienglieder([kennung]), [])
  }

  /// Festgehalten, weil es überrascht: Das Foto liegt in der Mediathek, aber
  /// auch `includeHiddenAssets` bringt es nicht zum Vorschein. Scheitert
  /// dieser Test, gibt iOS sie inzwischen heraus.
  func testAusgeblendeteGibtIOSNichtHeraus() async throws {
    let kennung = try await legeFotoAn(ausgeblendet: true)
    let o = PHFetchOptions()
    o.includeHiddenAssets = true
    XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: [kennung], options: o).count, 0)
  }

  func testDateienEinesFotos() async throws {
    let kennung = try await legeFotoAn()
    let dateien = await withCheckedContinuation { fortsetzung in
      Zusatzfotos.dateien(kennung: kennung) { fortsetzung.resume(returning: $0) }
    }
    let liste = try XCTUnwrap(dateien)
    XCTAssertEqual(liste.map { $0["teil"] }, ["bild"])
    let pfad = try XCTUnwrap(liste[0]["pfad"])
    XCTAssertGreaterThan(try Data(contentsOf: URL(fileURLWithPath: pfad)).count, 0)
    Zusatzfotos.aufraeumen()
    XCTAssertFalse(FileManager.default.fileExists(atPath: pfad))
  }

  func testUnbekannteKennung() async {
    let dateien = await withCheckedContinuation { fortsetzung in
      Zusatzfotos.dateien(kennung: "gibt-es-nicht") { fortsetzung.resume(returning: $0) }
    }
    XCTAssertNil(dateien)
  }
}

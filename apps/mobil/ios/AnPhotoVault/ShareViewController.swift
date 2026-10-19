import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// „An Photo Vault“ im Teilen-Menü (Issue #171): Fotos und Videos aus der
/// Fotos-App oder einer anderen App gehen direkt auf den Server – über
/// denselben Weg wie die Sicherung der Kamerarolle (tus,
/// `/api/v1/hochladen`, Stücke zu 8 MB) und mit der Verbindung, die die
/// App im gemeinsamen Schlüsselbund ablegt. Danach erscheinen sie über
/// den Abgleich in der Zeitleiste, auf dem Telefon wie am Rechner.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
  private let uebertragung = Uebertragung()

  override func viewDidLoad() {
    super.viewDidLoad()
    let ansicht = UIHostingController(
      rootView: TeilenAnsicht(
        uebertragung: uebertragung,
        schliessen: { [weak self] in self?.schliesse() }))
    addChild(ansicht)
    ansicht.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(ansicht.view)
    NSLayoutConstraint.activate([
      ansicht.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      ansicht.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      ansicht.view.topAnchor.constraint(equalTo: view.topAnchor),
      ansicht.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    ansicht.didMove(toParent: self)
    let anhaenge = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    Task { await uebertragung.starte(anhaenge) }
  }

  private func schliesse() {
    uebertragung.abbrechen = true
    extensionContext?.completeRequest(returningItems: nil)
  }
}

private enum Texte {
  static var d: Bool { Sprache.deutsch }
  static var titel: String { d ? "An Photo Vault" : "To Photo Vault" }
  static var anmelden: String {
    d
      ? "Erst in der App Photo Vault mit dem Server verbinden."
      : "Connect the Photo Vault app to your server first."
  }
  static var nichts: String { d ? "Hier ist nichts, was sich sichern liesse." : "Nothing here can be backed up." }
  static func stand(_ fertig: Int, _ gesamt: Int) -> String {
    d ? "\(fertig) von \(gesamt) gesichert" : "\(fertig) of \(gesamt) backed up"
  }
  static var fertig: String {
    d ? "Gesichert – erscheint gleich in der Zeitleiste." : "Backed up – it will appear in the timeline shortly."
  }
  static var schon: String { d ? "schon in der Bibliothek" : "already in the library" }
  static var format: String { d ? "Format nicht unterstützt" : "Format not supported" }
  static var voll: String { d ? "Der Speicher des Servers ist voll." : "The server is out of space." }
  static var netz: String { d ? "Server nicht erreichbar" : "Server not reachable" }
  static var fehlgeschlagen: String { d ? "Hat nicht geklappt" : "Did not work" }
  static var schliessen: String { d ? "Schliessen" : "Close" }
  static var abbrechen: String { d ? "Abbrechen" : "Cancel" }
}

private struct Fehler: LocalizedError {
  let text: String
  var errorDescription: String? { text }
}

@MainActor
final class Uebertragung: ObservableObject {
  @Published var gesamt = 0
  @Published var fertig = 0
  @Published var schon = 0
  @Published var anteil = 0.0
  @Published var laeuft = true
  @Published var hinweis: String?
  @Published var fehler: [String] = []
  var abbrechen = false

  private static let stueck = 8 << 20

  func starte(_ anhaenge: [NSItemProvider]) async {
    defer { laeuft = false }
    guard let v = GemeinsameVerbindung.lies() else {
      hinweis = Texte.anmelden
      return
    }
    let passend = anhaenge.compactMap { a -> (NSItemProvider, String)? in
      // Das Original zuerst: HEIC vor JPEG, das Video vor einem Standbild.
      let typ = a.registeredTypeIdentifiers.first { id in
        guard let t = UTType(id) else { return false }
        return t.conforms(to: .image) || t.conforms(to: .movie)
      }
      return typ.map { (a, $0) }
    }
    gesamt = passend.count
    if passend.isEmpty {
      hinweis = Texte.nichts
      return
    }
    for (i, (anhang, typ)) in passend.enumerated() {
      if abbrechen { return }
      do {
        let datei = try await kopie(anhang, typ)
        defer { try? FileManager.default.removeItem(at: datei.deletingLastPathComponent()) }
        let ausgang = try await lade(datei, v) { teil in
          self.anteil = (Double(i) + teil) / Double(self.gesamt)
        }
        if ausgang == "duplicateSkipped" { schon += 1 }
        fertig += 1
      } catch {
        fehler.append(error.localizedDescription)
      }
      anteil = Double(i + 1) / Double(gesamt)
    }
  }

  /// Die Datei des Anhangs gilt nur im Rückruf – also gleich kopieren,
  /// unter ihrem Namen und mit einer Endung, die der Server kennt.
  private func kopie(_ a: NSItemProvider, _ typ: String) async throws -> URL {
    try await withCheckedThrowingContinuation { (fortsetzung: CheckedContinuation<URL, Error>) in
      _ = a.loadFileRepresentation(forTypeIdentifier: typ) { url, fehler in
        guard let url else {
          fortsetzung.resume(throwing: fehler ?? Fehler(text: Texte.fehlgeschlagen))
          return
        }
        do {
          let ordner = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
          try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
          var name = url.lastPathComponent
          if (name as NSString).pathExtension.isEmpty,
            let endung = UTType(typ)?.preferredFilenameExtension
          {
            name = (a.suggestedName ?? "Aufnahme") + "." + endung
          }
          let ziel = ordner.appendingPathComponent(name)
          try FileManager.default.copyItem(at: url, to: ziel)
          fortsetzung.resume(returning: ziel)
        } catch {
          fortsetzung.resume(throwing: error)
        }
      }
    }
  }

  /// tus: anlegen, dann in Stücken anhängen. Gibt `pv-ausgang` zurück.
  private func lade(
    _ datei: URL, _ v: GemeinsameVerbindung, fortschritt: @escaping (Double) -> Void
  ) async throws -> String? {
    let werte = try FileManager.default.attributesOfItem(atPath: datei.path)
    let groesse = (werte[.size] as? NSNumber)?.intValue ?? 0
    var meta = "filename " + Data(datei.lastPathComponent.utf8).base64EncodedString()
    if let geaendert = werte[.modificationDate] as? Date {
      let ms = Int(geaendert.timeIntervalSince1970 * 1000)
      meta += ",geaendert " + Data(String(ms).utf8).base64EncodedString()
    }
    guard var anlegen = v.anfrage("api/v1/hochladen", methode: "POST") else {
      throw Fehler(text: Texte.netz)
    }
    anlegen.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
    anlegen.setValue(String(groesse), forHTTPHeaderField: "Upload-Length")
    anlegen.setValue(meta, forHTTPHeaderField: "Upload-Metadata")
    let ort: String
    do {
      let (_, antwort) = try await URLSession.shared.data(for: anlegen)
      let h = antwort as? HTTPURLResponse
      switch h?.statusCode {
      case 201: ort = h?.value(forHTTPHeaderField: "Location") ?? ""
      case 415: throw Fehler(text: "\(datei.lastPathComponent): \(Texte.format)")
      case 507: throw Fehler(text: Texte.voll)
      default: throw Fehler(text: "\(datei.lastPathComponent): \(Texte.fehlgeschlagen) (\(h?.statusCode ?? 0))")
      }
    } catch let f as Fehler {
      throw f
    } catch {
      throw Fehler(text: Texte.netz)
    }
    let griff = try FileHandle(forReadingFrom: datei)
    defer { try? griff.close() }
    var versatz = 0
    var ausgang: String?
    repeat {
      if abbrechen { throw CancellationError() }
      let teil = try griff.read(upToCount: Self.stueck) ?? Data()
      guard var anhaengen = v.anfrage(ort, methode: "PATCH") else { throw Fehler(text: Texte.netz) }
      anhaengen.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
      anhaengen.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
      anhaengen.setValue(String(versatz), forHTTPHeaderField: "Upload-Offset")
      let (_, antwort) = try await URLSession.shared.upload(for: anhaengen, from: teil)
      let h = antwort as? HTTPURLResponse
      guard h?.statusCode == 204 else {
        throw Fehler(text: "\(datei.lastPathComponent): \(Texte.fehlgeschlagen) (\(h?.statusCode ?? 0))")
      }
      versatz += teil.count
      ausgang = h?.value(forHTTPHeaderField: "pv-ausgang")
      fortschritt(groesse == 0 ? 1 : Double(versatz) / Double(groesse))
      if teil.isEmpty { break }
    } while versatz < groesse
    if ausgang == "failed" {
      throw Fehler(text: "\(datei.lastPathComponent): \(Texte.fehlgeschlagen)")
    }
    return ausgang
  }
}

struct TeilenAnsicht: View {
  @ObservedObject var uebertragung: Uebertragung
  let schliessen: () -> Void

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        Spacer()
        if let hinweis = uebertragung.hinweis {
          Image(systemName: "exclamationmark.circle").font(.system(size: 44)).foregroundStyle(.secondary)
          Text(hinweis).multilineTextAlignment(.center)
        } else if uebertragung.laeuft {
          ProgressView(value: uebertragung.anteil).progressViewStyle(.linear).frame(maxWidth: 280)
          Text(Texte.stand(uebertragung.fertig, uebertragung.gesamt)).monospacedDigit()
        } else {
          Image(systemName: uebertragung.fehler.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 44))
            .foregroundStyle(uebertragung.fehler.isEmpty ? Color.green : Color.orange)
          Text(Texte.stand(uebertragung.fertig, uebertragung.gesamt)).font(.headline)
          if uebertragung.fertig > 0 { Text(Texte.fertig).font(.subheadline).foregroundStyle(.secondary) }
          if uebertragung.schon > 0 {
            Text("\(uebertragung.schon) \(Texte.schon)").font(.footnote).foregroundStyle(.secondary)
          }
          ForEach(Array(uebertragung.fehler.prefix(5).enumerated()), id: \.offset) { _, f in
            Text(f).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
          }
        }
        Spacer()
      }
      .padding(24)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(Texte.titel)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: uebertragung.laeuft ? .cancellationAction : .confirmationAction) {
          Button(uebertragung.laeuft ? Texte.abbrechen : Texte.schliessen, action: schliessen)
        }
      }
    }
  }
}

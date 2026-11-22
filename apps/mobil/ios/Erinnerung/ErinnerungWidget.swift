import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Das Widget „Vor x Jahren“ (Issue #172): ein Foto von heute vor ein
/// paar Jahren – dieselbe Auswahl wie die Erinnerungen oben in der
/// Zeitleiste (`/api/v1/erinnerungen`, waehleRueckblick im Kern).
///
/// Es holt sich das Bild selbst vom Server, mit der Verbindung, die die
/// App im gemeinsamen Schlüsselbund ablegt (GemeinsameVerbindung). Ohne
/// Netz bleibt das zuletzt geladene stehen; WidgetKit hält es fest.
///
/// Ist die App-Sperre an, zeigt es nur ein Schloss und fragt den Server gar
/// nicht erst (#467). Schaltet die App sie ein, lädt sie das Widget neu;
/// das zuletzt gezeigte Foto weicht damit sofort.

struct Erinnerungseintrag: TimelineEntry {
  let date: Date
  let bild: UIImage?
  let titel: String
  let unterzeile: String?
  var gesperrt = false

  static var mitSperre: Erinnerungseintrag {
    Erinnerungseintrag(date: .now, bild: nil, titel: Texte.gesperrt, unterzeile: nil, gesperrt: true)
  }
}

private struct Antwort: Decodable {
  struct Aufnahme: Decodable {
    let id: String
    let art: String
    let aufgenommen: String
    let miniatur: Bool?
  }
  struct Gruppe: Decodable {
    let jahreHer: Int
    let aufnahmen: [Aufnahme]
  }
  let art: String
  let gruppen: [Gruppe]
}

struct Erinnerungsanbieter: TimelineProvider {
  func placeholder(in context: Context) -> Erinnerungseintrag {
    Erinnerungseintrag(date: .now, bild: nil, titel: Texte.vorJahren(3), unterzeile: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (Erinnerungseintrag) -> Void) {
    Task { completion(await lade(groesse: context.displaySize)) }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<Erinnerungseintrag>) -> Void) {
    Task {
      let eintrag = await lade(groesse: context.displaySize)
      // Am nächsten Morgen ist ein anderer Tag – spätestens dann neu,
      // sonst alle sechs Stunden (ein anderes Foto desselben Tages).
      let morgen = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(300)
      let naechste = min(morgen, .now.addingTimeInterval(6 * 3600))
      completion(Timeline(entries: [eintrag], policy: .after(naechste)))
    }
  }

  private func lade(groesse: CGSize) async -> Erinnerungseintrag {
    guard let v = GemeinsameVerbindung.lies() else {
      return Erinnerungseintrag(date: .now, bild: nil, titel: "Photo Vault", unterzeile: Texte.anmelden)
    }
    if GemeinsameAppSperre.an { return .mitSperre }
    guard let r = v.anfrage("api/v1/erinnerungen"),
      let (daten, antwort) = try? await URLSession.shared.data(for: r),
      (antwort as? HTTPURLResponse)?.statusCode == 200,
      let e = try? JSONDecoder().decode(Antwort.self, from: daten)
    else {
      return Erinnerungseintrag(date: .now, bild: nil, titel: "Photo Vault", unterzeile: Texte.keinServer)
    }
    // Ein Foto für heute: jeden Tag und alle sechs Stunden ein anderes,
    // aber nicht bei jedem Neuzeichnen.
    let fotos = e.gruppen.flatMap { g in g.aufnahmen.filter { $0.art == "bild" }.map { (g.jahreHer, $0) } }
    guard !fotos.isEmpty else {
      return Erinnerungseintrag(date: .now, bild: nil, titel: Texte.keineErinnerung, unterzeile: nil)
    }
    let stunde = Calendar.current.ordinality(of: .hour, in: .year, for: .now) ?? 0
    let (jahre, foto) = fotos[(stunde / 6) % fotos.count]
    let bild = await ladeBild(v, foto.id, groesse: groesse)
    // Während des Ladens eingeschaltet: Der neue Lauf, den die App
    // angestossen hat, könnte vor diesem fertig sein.
    if GemeinsameAppSperre.an { return .mitSperre }
    return Erinnerungseintrag(
      date: .now, bild: bild, titel: Texte.vorJahren(jahre), unterzeile: Texte.datum(foto.aufgenommen))
  }

  /// Die Ansicht, gleich beim Lesen auf die Grösse des Widgets
  /// verkleinert – ein Widget darf nur wenige Megabyte belegen, und ein
  /// Foto vom Telefon hat 48 Megapixel.
  private func ladeBild(_ v: GemeinsameVerbindung, _ id: String, groesse: CGSize) async -> UIImage? {
    let kante = max(groesse.width, groesse.height) * 3
    for art in ["ansicht", "miniatur"] {
      guard let r = v.anfrage("api/v1/aufnahmen/\(id)/\(art)"),
        let (datei, antwort) = try? await URLSession.shared.download(for: r),
        (antwort as? HTTPURLResponse)?.statusCode == 200,
        let quelle = CGImageSourceCreateWithURL(datei as CFURL, nil)
      else { continue }
      defer { try? FileManager.default.removeItem(at: datei) }
      let optionen: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(kante, 300),
      ]
      if let cg = CGImageSourceCreateThumbnailAtIndex(quelle, 0, optionen as CFDictionary) {
        return UIImage(cgImage: cg)
      }
    }
    return nil
  }
}

enum Texte {
  static func vorJahren(_ n: Int) -> String {
    Sprache.deutsch
      ? (n == 1 ? "Vor einem Jahr" : "Vor \(n) Jahren")
      : (n == 1 ? "One year ago" : "\(n) years ago")
  }
  static var anmelden: String { Sprache.deutsch ? "In der App anmelden" : "Sign in in the app" }
  static var keinServer: String { Sprache.deutsch ? "Server nicht erreichbar" : "Server not reachable" }
  static var keineErinnerung: String { Sprache.deutsch ? "Heute keine Erinnerung" : "No memory today" }
  /// Wie die App über ihrer Sperre (appSperreGesperrt).
  static var gesperrt: String { Sprache.deutsch ? "Photo Vault ist gesperrt" : "Photo Vault is locked" }
  static var name: String { Sprache.deutsch ? "Vor x Jahren" : "Years ago" }
  static var beschreibung: String {
    Sprache.deutsch
      ? "Ein Foto von heute vor ein paar Jahren – aus deiner Bibliothek."
      : "A photo from this day a few years ago – from your library."
  }
  /// Der Server schreibt die Ortszeit der Aufnahme ohne Zone
  /// („2023-10-19T14:30:00.000“) – die ersten 19 Zeichen genügen.
  static func datum(_ iso: String) -> String? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard let d = f.date(from: String(iso.prefix(19))) else { return nil }
    return d.formatted(date: .long, time: .omitted)
  }
}

struct ErinnerungAnsicht: View {
  var eintrag: Erinnerungseintrag

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let bild = eintrag.bild {
        // Ist das iPhone gesperrt, blendet iOS es je nach Einstellung aus
        // (Heute-Ansicht, StandBy; #467).
        Color.clear.overlay(Image(uiImage: bild).resizable().scaledToFill().privacySensitive())
          .clipped()
        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
      } else {
        LinearGradient(
          colors: [Color(red: 0.13, green: 0.63, blue: 0.58), Color(red: 0.05, green: 0.42, blue: 0.38)],
          startPoint: .top, endPoint: .bottom)
      }
      if eintrag.gesperrt {
        VStack(spacing: 8) {
          Image(systemName: "lock.fill").font(.title)
          Text(eintrag.titel).font(.caption).bold().multilineTextAlignment(.center).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text(eintrag.titel).font(.headline).bold().lineLimit(2)
          if let u = eintrag.unterzeile {
            Text(u).font(.caption).lineLimit(1).opacity(0.9).privacySensitive(eintrag.bild != nil)
          }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 2)
        .padding(12)
      }
    }
    .containerBackground(for: .widget) { Color.black }
  }
}

@main
struct ErinnerungWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Erinnerung", provider: Erinnerungsanbieter()) { eintrag in
      ErinnerungAnsicht(eintrag: eintrag)
    }
    .configurationDisplayName(Texte.name)
    .description(Texte.beschreibung)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

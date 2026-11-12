import Flutter
import UIKit
import WidgetKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Die Sicherung der Kamerarolle im Hintergrund: Die Aufgabe läuft in
    // einer eigenen Flutter-Engine, die die Plugins selbst braucht. Beide
    // Anmeldungen müssen vor dem Ende von didFinishLaunching geschehen –
    // mit Szenen meldet Flutter die Plugins sonst zu spät an.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      if let registrar = registry.registrar(forPlugin: "Zusatzfotos") {
        Zusatzfotokanal.richteEin(registrar)
      }
    }
    Abdeckung.richteEin()
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "de.dasevo.photovault.sicherung")
    // Kurze Auffrischungen über den Tag (BGAppRefreshTask, rund 30 s je
    // Lauf): Die Verarbeitungsaufgabe allein lässt iOS meist nur nachts am
    // Ladekabel laufen (#214).
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "de.dasevo.photovault.sicherung.kurz",
      earliestBeginInSeconds: NSNumber(value: 15 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Das Video des Überfluges (lib/seiten/landschaft.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Flugvideo") {
      Flugvideokanal.richteEin(registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Zusatzfotos") {
      Zusatzfotokanal.richteEin(registrar)
    }
    // Die Verbindung für Widget und Teilen-Erweiterung (lib/gemeinsam.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Gemeinsam") {
      let kanal = FlutterMethodChannel(
        name: "de.dasevo.photovault/gemeinsam", binaryMessenger: registrar.messenger())
      kanal.setMethodCallHandler { aufruf, antwort in
        switch aufruf.method {
        case "setze":
          guard let w = aufruf.arguments as? [String: Any],
            let server = w["server"] as? String, let token = w["token"] as? String
          else {
            antwort(FlutterError(code: "werte", message: nil, details: nil))
            return
          }
          let ok = GemeinsameVerbindung.schreibe(GemeinsameVerbindung(server: server, token: token))
          WidgetCenter.shared.reloadAllTimelines()
          antwort(ok ? nil : FlutterError(code: "schluesselbund", message: nil, details: nil))
        case "loesche":
          GemeinsameVerbindung.schreibe(nil)
          WidgetCenter.shared.reloadAllTimelines()
          antwort(nil)
        case "sofort":
          guard let w = aufruf.arguments as? [String: Any],
            let an = w["an"] as? Bool, let videos = w["videos"] as? Bool,
            let nurWlan = w["nurWlan"] as? Bool, let alben = w["alben"] as? [String]
          else {
            antwort(FlutterError(code: "werte", message: nil, details: nil))
            return
          }
          Sofortsteuerung.reihe.async {
            let stand = Sofortsteuerung.setze(
              an: an, videos: videos, nurWlan: nurWlan, alben: alben)
            DispatchQueue.main.async { antwort(stand) }
          }
        case "abdeckung":
          Abdeckung.an = (aufruf.arguments as? Bool) ?? false
          antwort(nil)
        case "sofortbericht":
          antwort(Sofortsteuerung.bericht)
        case "sofortGeschafft":
          let ms = aufruf.arguments as? Int64
          Sofortsteuerung.reihe.async {
            if let ms {
              Sofortsteuerung.geschafft(bis: Date(timeIntervalSince1970: Double(ms) / 1000))
            }
            DispatchQueue.main.async { antwort(nil) }
          }
        default:
          antwort(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// Serienbilder für die Sicherung (#314), in der App und in der Engine der
/// Hintergrundaufgabe.
enum Zusatzfotokanal {
  private static let reihe = DispatchQueue(
    label: "de.dasevo.photovault.zusatzfotos", qos: .userInitiated)

  static func richteEin(_ registrar: FlutterPluginRegistrar) {
    let kanal = FlutterMethodChannel(
      name: "de.dasevo.photovault/zusatzfotos", binaryMessenger: registrar.messenger())
    kanal.setMethodCallHandler { aufruf, antwort in
      let w = aufruf.arguments as? [String: Any] ?? [:]
      let melde: (Any?) -> Void = { wert in DispatchQueue.main.async { antwort(wert) } }
      reihe.async {
        switch aufruf.method {
        case "liste":
          melde(Zusatzfotos.liste(alben: w["alben"] as? [String] ?? []))
        case "serienglieder":
          melde(Zusatzfotos.serienglieder(w["kennungen"] as? [String] ?? []))
        case "dateien":
          guard let kennung = w["kennung"] as? String else {
            melde(nil)
            return
          }
          Zusatzfotos.dateien(kennung: kennung, fertig: melde)
        case "aufraeumen":
          Zusatzfotos.aufraeumen()
          melde(nil)
        default:
          melde(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

/// Die Abdeckung im App-Umschalter (#376): iOS macht beim Verlassen ein
/// Bild der App und zeigt es im Umschalter. Ist die App-Sperre an, liegt
/// davor eine leere Fläche – sonst sähe man dort die Fotos, auch wenn die
/// App beim Zurückkommen nach Face ID fragt. Über die Benachrichtigungen
/// der Szenen statt im SceneDelegate: FlutterSceneDelegate gibt dafür keine
/// überschreibbaren Methoden her und braucht seine eigenen.
enum Abdeckung {
  private static let schluessel = "appSperreAbdecken"
  private static var flaechen: [ObjectIdentifier: UIView] = [:]

  static var an: Bool {
    get { UserDefaults.standard.bool(forKey: schluessel) }
    set { UserDefaults.standard.set(newValue, forKey: schluessel) }
  }

  static func richteEin() {
    let mitte = NotificationCenter.default
    mitte.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) {
      zeige(auf: $0.object as? UIWindowScene)
    }
    mitte.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) {
      guard let szene = $0.object as? UIWindowScene else { return }
      flaechen.removeValue(forKey: ObjectIdentifier(szene))?.removeFromSuperview()
    }
  }

  private static func zeige(auf szene: UIWindowScene?) {
    guard an, let szene, flaechen[ObjectIdentifier(szene)] == nil,
      let fenster = szene.windows.first(where: { $0.isKeyWindow }) ?? szene.windows.first
    else { return }
    let flaeche = UIView(frame: fenster.bounds)
    flaeche.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    flaeche.backgroundColor = .systemBackground
    let schloss = UIImageView(image: UIImage(systemName: "lock.fill"))
    schloss.tintColor = .secondaryLabel
    schloss.translatesAutoresizingMaskIntoConstraints = false
    flaeche.addSubview(schloss)
    NSLayoutConstraint.activate([
      schloss.centerXAnchor.constraint(equalTo: flaeche.centerXAnchor),
      schloss.centerYAnchor.constraint(equalTo: flaeche.centerYAnchor),
    ])
    fenster.addSubview(flaeche)
    flaechen[ObjectIdentifier(szene)] = flaeche
  }
}

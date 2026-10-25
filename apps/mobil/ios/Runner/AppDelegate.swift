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
    }
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
        default:
          antwort(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

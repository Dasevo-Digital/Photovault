// Das Flugvideo der Landschaft am iPhone (packages/gelaende,
// lib/seiten/landschaft.dart): dieselbe Schreibweise wie am Mac
// (macos/Runner/ImageConverter.swift) – AVFoundation kodiert in Hardware,
// die Bilder kommen als RGBA aus Flutter.

import AVFoundation
import Accelerate
import CoreVideo
import Flutter

/// Der Kanal `de.dasevo.photovault/flugvideo`: beginnen, Bild für Bild
/// anhängen, abschliessen oder verwerfen.
enum Flugvideokanal {
    static func richteEin(_ registrar: FlutterPluginRegistrar) {
        let kanal = FlutterMethodChannel(
            name: "de.dasevo.photovault/flugvideo", binaryMessenger: registrar.messenger())
        kanal.setMethodCallHandler { aufruf, antwort in
            switch aufruf.method {
            case "videoStart":
                guard
                    let w = aufruf.arguments as? [String: Any],
                    let pfad = w["path"] as? String,
                    let breite = (w["breite"] as? NSNumber)?.intValue,
                    let hoehe = (w["hoehe"] as? NSNumber)?.intValue,
                    let takt = (w["bilderJeSekunde"] as? NSNumber)?.intValue
                else {
                    antwort(FlutterError(code: "bad_args", message: "path/breite/hoehe/bilderJeSekunde fehlt", details: nil))
                    return
                }
                Flugvideoschreiber.laufend?.verwirf()
                Flugvideoschreiber.laufend = nil
                do {
                    Flugvideoschreiber.laufend = try Flugvideoschreiber(
                        ziel: URL(fileURLWithPath: pfad),
                        breite: breite, hoehe: hoehe, bilderJeSekunde: takt)
                    antwort(nil)
                } catch let f as Flugvideofehler {
                    antwort(FlutterError(code: "video", message: f.text, details: nil))
                } catch {
                    antwort(FlutterError(code: "video", message: "\(error.localizedDescription)", details: nil))
                }
            case "videoBild":
                guard
                    let w = aufruf.arguments as? [String: Any],
                    let punkte = w["rgba"] as? FlutterStandardTypedData
                else {
                    antwort(FlutterError(code: "bad_args", message: "rgba fehlt", details: nil))
                    return
                }
                guard let schreiber = Flugvideoschreiber.laufend else {
                    antwort(FlutterError(code: "video", message: "kein Lauf begonnen", details: nil))
                    return
                }
                // Nicht auf dem Hauptthread: Umsortieren und Anhängen
                // kosten je Bild Millisekunden, und darüber stockte die
                // Fortschrittsanzeige.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try schreiber.bild(punkte.data)
                        DispatchQueue.main.async { antwort(nil) }
                    } catch let f as Flugvideofehler {
                        DispatchQueue.main.async {
                            antwort(FlutterError(code: "video", message: f.text, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            antwort(FlutterError(code: "video", message: "\(error.localizedDescription)", details: nil))
                        }
                    }
                }
            case "videoFertig":
                guard let schreiber = Flugvideoschreiber.laufend else {
                    antwort(FlutterError(code: "video", message: "kein Lauf begonnen", details: nil))
                    return
                }
                Flugvideoschreiber.laufend = nil
                schreiber.beende { grund in
                    DispatchQueue.main.async {
                        if let grund = grund {
                            antwort(FlutterError(code: "video", message: grund, details: nil))
                        } else {
                            antwort(nil)
                        }
                    }
                }
            case "videoVerwerfen":
                Flugvideoschreiber.laufend?.verwirf()
                Flugvideoschreiber.laufend = nil
                antwort(nil)
            default:
                antwort(FlutterMethodNotImplemented)
            }
        }
    }
}

/// Schreibt die Bilder des Fluges als H.264 in eine MP4-Datei – wie am
/// Mac über AVFoundation, also in Hardware.
///
/// **Bildpunkte kommen als RGBA, AVFoundation will BGRA.** Das Umsortieren
/// macht `vImagePermuteChannels_ARGB8888` in einem Durchlauf über die ganze
/// Fläche.
final class Flugvideoschreiber {
    /// Es gibt hoechstens einen Lauf. Die Oberflaeche sperrt den Knopf,
    /// solange einer laeuft; hier steht die Sperre noch einmal, damit ein
    /// zweiter Aufruf nicht stillschweigend in denselben Schreiber malt.
    static var laufend: Flugvideoschreiber?

    private let ziel: URL
    private let schreiber: AVAssetWriter
    private let eingang: AVAssetWriterInput
    private let anpasser: AVAssetWriterInputPixelBufferAdaptor
    private let breite: Int
    private let hoehe: Int
    private let takt: Int32
    private var nummer: Int64 = 0

    init(ziel: URL, breite: Int, hoehe: Int, bilderJeSekunde: Int) throws {
        self.ziel = ziel
        self.breite = breite
        self.hoehe = hoehe
        self.takt = Int32(bilderJeSekunde)

        // AVAssetWriter weigert sich, auf eine vorhandene Datei zu
        // schreiben - und der Speichern-Dialog liefert regelmaessig eine,
        // weil er selbst schon eine leere angelegt hat.
        try? FileManager.default.removeItem(at: ziel)

        schreiber = try AVAssetWriter(outputURL: ziel, fileType: .mp4)
        // Das Gegenstueck zu ffmpegs `-movflags +faststart`: Ohne das
        // faengt ein Abspieler im Netz erst an, wenn die ganze Datei da
        // ist.
        schreiber.shouldOptimizeForNetworkUse = true

        // **Die Datenrate aus der Bildflaeche, nicht als feste Zahl.** Bei
        // 1920 x 1080 und dreissig Bildern kommen so rund 12 Mbit/s
        // heraus - das liegt dort, wo ffmpeg mit `-crf 20` landet, und es
        // stimmt auch noch, wenn die Ausgabegroesse einmal eine andere
        // ist.
        let rate = Int(Double(breite * hoehe * bilderJeSekunde) * 0.2)
        eingang = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: breite,
                AVVideoHeightKey: hoehe,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: rate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: bilderJeSekunde,
                    // Alle zwei Sekunden ein Vollbild: Danach richtet sich,
                    // wie fein sich im Video springen laesst.
                    AVVideoMaxKeyFrameIntervalKey: bilderJeSekunde * 2,
                ],
            ]
        )
        // Die Bilder entstehen so schnell, wie sie gemalt werden koennen -
        // das ist keine Aufnahme in Echtzeit. Stuende hier `true`, wuerfe
        // AVFoundation Bilder weg, sobald das Malen nicht Schritt haelt.
        eingang.expectsMediaDataInRealTime = false

        anpasser = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: eingang,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: breite,
                kCVPixelBufferHeightKey as String: hoehe,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            ]
        )

        guard schreiber.canAdd(eingang) else {
            throw Flugvideofehler.abgelehnt("AVAssetWriter nimmt die Videospur nicht an")
        }
        schreiber.add(eingang)
        guard schreiber.startWriting() else {
            throw Flugvideofehler.abgelehnt(Flugvideoschreiber.grund(schreiber))
        }
        schreiber.startSession(atSourceTime: .zero)
    }

    /// Haengt ein Bild an. [rgba] muss genau `breite * hoehe * 4` Bytes
    /// lang sein - alles andere ist ein Programmierfehler und keine Lage,
    /// aus der sich etwas retten liesse.
    func bild(_ rgba: Data) throws {
        guard rgba.count == breite * hoehe * 4 else {
            throw Flugvideofehler.abgelehnt(
                "Bild hat \(rgba.count) Bytes, erwartet \(breite * hoehe * 4)")
        }
        guard schreiber.status == .writing else {
            throw Flugvideofehler.abgelehnt(Flugvideoschreiber.grund(schreiber))
        }
        guard let vorrat = anpasser.pixelBufferPool else {
            throw Flugvideofehler.abgelehnt("kein Bildpunktvorrat")
        }

        var puffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, vorrat, &puffer) == kCVReturnSuccess,
            let bildpuffer = puffer
        else {
            throw Flugvideofehler.abgelehnt("kein Bildpuffer zu bekommen")
        }

        CVPixelBufferLockBaseAddress(bildpuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(bildpuffer, []) }
        guard let ziel = CVPixelBufferGetBaseAddress(bildpuffer) else {
            throw Flugvideofehler.abgelehnt("Bildpuffer ohne Adresse")
        }
        let zielSchritt = CVPixelBufferGetBytesPerRow(bildpuffer)

        try rgba.withUnsafeBytes { roh in
            guard let quelle = roh.baseAddress else {
                throw Flugvideofehler.abgelehnt("Bild ohne Adresse")
            }
            var von = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: quelle),
                height: vImagePixelCount(hoehe),
                width: vImagePixelCount(breite),
                rowBytes: breite * 4)
            var nach = vImage_Buffer(
                data: ziel,
                height: vImagePixelCount(hoehe),
                width: vImagePixelCount(breite),
                rowBytes: zielSchritt)
            // R und B tauschen, G und A bleiben: aus RGBA wird BGRA.
            let ordnung: [UInt8] = [2, 1, 0, 3]
            let fehler = vImagePermuteChannels_ARGB8888(&von, &nach, ordnung, 0)
            guard fehler == kvImageNoError else {
                throw Flugvideofehler.abgelehnt("vImage \(fehler)")
            }
        }

        // **Warten, nicht verwerfen.** `isReadyForMoreMediaData` ist
        // praktisch immer wahr, weil der Aufrufer ohnehin auf jedes Bild
        // wartet; wenn nicht, ist Warten richtig und Wegwerfen falsch -
        // ein fehlendes Bild verkuerzte das Video lautlos.
        var gewartet = 0
        while !eingang.isReadyForMoreMediaData && gewartet < 20_000 {
            usleep(1000)
            gewartet += 1
        }
        guard anpasser.append(bildpuffer, withPresentationTime: CMTime(value: nummer, timescale: takt))
        else {
            throw Flugvideofehler.abgelehnt(Flugvideoschreiber.grund(schreiber))
        }
        nummer += 1
    }

    /// Schliesst die Datei ab. [fertig] bekommt `nil` bei Erfolg, sonst
    /// den Grund.
    func beende(_ fertig: @escaping (String?) -> Void) {
        guard nummer > 0 else {
            verwirf()
            fertig("kein einziges Bild geschrieben")
            return
        }
        eingang.markAsFinished()
        schreiber.finishWriting { [self] in
            if schreiber.status == .completed {
                fertig(nil)
            } else {
                try? FileManager.default.removeItem(at: ziel)
                fertig(Flugvideoschreiber.grund(schreiber))
            }
        }
    }

    /// Bricht ab und laesst **keine** halbe Datei zurueck: Die sieht aus
    /// wie eine fertige und laesst sich nicht abspielen.
    func verwirf() {
        if schreiber.status == .writing { schreiber.cancelWriting() }
        try? FileManager.default.removeItem(at: ziel)
    }

    private static func grund(_ schreiber: AVAssetWriter) -> String {
        if let fehler = schreiber.error { return "\(fehler.localizedDescription)" }
        return "AVAssetWriter im Zustand \(schreiber.status.rawValue)"
    }
}

enum Flugvideofehler: Error {
    case abgelehnt(String)

    var text: String {
        switch self {
        case .abgelehnt(let grund): return grund
        }
    }
}

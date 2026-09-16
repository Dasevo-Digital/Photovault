// ImageConverter.swift
//
// Behebt zwei grundlegende Probleme:
//
//   1. Flutter selbst (Skia) kann HEIC/HEIF und die meisten RAW-Formate
//      (z.B. DNG) nicht rendern, und das Dart-Paket `image` kann sie nicht
//      dekodieren. macOS bringt mit ImageIO aber genau dafür eine native,
//      systemeigene Lösung mit (dieselbe, die z.B. auch die Vorschau im
//      Finder nutzt) – hierüber wird auf jedes von ImageIO unterstützte
//      Format zurückgegriffen, um es zu einem JPEG zu konvertieren, das dann
//      sowohl für Thumbnails als auch für die Vollbildvorschau verwendet
//      werden kann.
//   2. Für Videos gibt es in Flutter/Dart keine Möglichkeit, ein
//      Vorschaubild (einen Frame) zu extrahieren – AVFoundation liefert das
//      systemeigen mit ("videoThumbnail"-Methode unten), inkl. Videolänge.
//
// Einbindung:
//   1. Diese Datei nach macos/Runner/ImageConverter.swift kopieren.
//   2. In Xcode (macos/Runner.xcworkspace öffnen): Rechtsklick auf den
//      "Runner"-Ordner → "Add Files to Runner…" → ImageConverter.swift
//      auswählen, Target "Runner" ankreuzen.
//   3. In macos/Runner/MainFlutterWindow.swift direkt nach der Zeile
//      `RegisterGeneratedPlugins(registry: flutterViewController)` diese
//      eine Zeile ergänzen (offizieller Standardweg für Method Channels auf
//      macOS, kein Import nötig):
//
//      ImageConverterChannel.register(with: flutterViewController.registrar(forPlugin: "ImageConverter"))
//
// Ohne diesen Schritt läuft die App normal weiter – für HEIC/DNG-Dateien
// fehlen dann aber weiterhin Thumbnails/Vorschau (erkennbar über
// `NativeImageConverter.isSupported()` in den Werkzeugen).

import AVFoundation
import Accelerate
import Cocoa
import CoreLocation
import CoreImage
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers
import Vision

class ImageConverterChannel: NSObject {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "photo_vault/image_convert",
            binaryMessenger: registrar.messenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "ping":
                result(true)
            case "convertToJpeg":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                let maxDimension = (args["maxDimension"] as? NSNumber)?.intValue ?? 2048
                let quality = (args["quality"] as? NSNumber)?.doubleValue ?? 0.9
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = convertToJpeg(path: path, maxDimension: maxDimension, quality: quality)
                    DispatchQueue.main.async {
                        if let data = data {
                            result(FlutterStandardTypedData(bytes: data))
                        } else {
                            result(nil)
                        }
                    }
                }
            case "currentLocation":
                // Einmalige Standortabfrage fuer den Knopf in der
                // Kartenansicht. Bewusst kein Dauerabo: Die App verfolgt
                // niemanden, sie zeigt einmal an, wo man gerade ist.
                Standortgeber.geteilt.einmalHolen { antwort in
                    DispatchQueue.main.async { result(antwort) }
                }
            case "cameraMetadata":
                // Aufnahmewerte fuer Dateien, aus denen package:exif nichts
                // herausbekommt. Anlass war CR3: Canons neueres RAW-Format
                // ist ein ISO-BMFF-Container (wie MP4), kein TIFF - und
                // package:exif kann nur TIFF/JPEG. Gemessen kamen dort NULL
                // Tags heraus, womit weder Kamera noch Objektiv noch das
                // Aufnahmedatum ankamen; das Datum fiel auf den Zeitstempel
                // der Datei zurueck und sortierte die Fotos in den falschen
                // Monat. ImageIO liest denselben Container problemlos.
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let werte = cameraMetadata(path: path)
                    DispatchQueue.main.async { result(werte) }
                }
            case "depthMask":
                // Die Tiefenkarte eines Porträtfotos als Graustufenmaske.
                // Nur macOS: Die Daten liegen als Hilfsbild im
                // HEIC-Container, und ImageIO gibt sie heraus - LibRaw und
                // libheif, die unter Linux und Windows den Weg machen, tun
                // das nicht. Der Dart-Teil sagt das dem Nutzer, statt den
                // Eintrag stillschweigend wegzulassen.
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let antwort = depthMask(path: path)
                    DispatchQueue.main.async { result(antwort) }
                }
            case "lensCorrectionStatus":
                // Sagt für EINE Datei, was der Objektivkorrektur-Schalter im
                // Entwickeln-Bildschirm tatsächlich bewirken würde. Vorher
                // stand dort für jedes Foto derselbe allgemeine Hinweis –
                // auch für JPEGs, wo es nie etwas zu korrigieren gibt, und
                // für RAWs, die Apples Datenbank nicht kennt.
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let status = lensCorrectionStatus(path: path)
                    DispatchQueue.main.async { result(status) }
                }
            case "developImage":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                let maxDimension = (args["maxDimension"] as? NSNumber)?.intValue ?? 2048
                let quality = (args["quality"] as? NSNumber)?.doubleValue ?? 0.9
                let adjustments = DevelopAdjustments(
                    exposure: (args["exposure"] as? NSNumber)?.floatValue ?? 0,
                    temperature: (args["temperature"] as? NSNumber)?.floatValue,
                    tint: (args["tint"] as? NSNumber)?.floatValue,
                    contrast: (args["contrast"] as? NSNumber)?.floatValue ?? 0,
                    shadows: (args["shadows"] as? NSNumber)?.floatValue ?? 0,
                    highlights: (args["highlights"] as? NSNumber)?.floatValue ?? 0,
                    sharpness: (args["sharpness"] as? NSNumber)?.floatValue ?? 0,
                    noiseReduction: (args["noiseReduction"] as? NSNumber)?.floatValue ?? 0,
                    clarity: (args["clarity"] as? NSNumber)?.floatValue ?? 0,
                    vignette: (args["vignette"] as? NSNumber)?.floatValue ?? 0,
                    lensCorrectionEnabled: (args["lensCorrectionEnabled"] as? Bool) ?? true,
                    curveLut: floatArray(args["toneCurveLut"]),
                    colorCube: floatArray(args["colorCube"]),
                    colorCubeSize: (args["colorCubeSize"] as? NSNumber)?.intValue ?? 0
                )
                // KI-Objektmasken (siehe MaskEditor/DevelopMasks): jede trägt
                // eine Grauwert-PNG-Alphamaske + ihren eigenen Regler-Satz,
                // wirksam NUR innerhalb der Maske (siehe developImage unten).
                let maskLayers: [MaskLayer] = ((args["masks"] as? [[String: Any]]) ?? []).compactMap { m in
                    guard let path = m["path"] as? String else { return nil }
                    return MaskLayer(
                        path: path,
                        adjustments: DevelopAdjustments(
                            exposure: (m["exposure"] as? NSNumber)?.floatValue ?? 0,
                            temperature: (m["temperature"] as? NSNumber)?.floatValue,
                            tint: (m["tint"] as? NSNumber)?.floatValue,
                            contrast: (m["contrast"] as? NSNumber)?.floatValue ?? 0,
                            shadows: (m["shadows"] as? NSNumber)?.floatValue ?? 0,
                            highlights: (m["highlights"] as? NSNumber)?.floatValue ?? 0,
                            sharpness: (m["sharpness"] as? NSNumber)?.floatValue ?? 0,
                            noiseReduction: (m["noiseReduction"] as? NSNumber)?.floatValue ?? 0,
                            clarity: (m["clarity"] as? NSNumber)?.floatValue ?? 0,
                            vignette: (m["vignette"] as? NSNumber)?.floatValue ?? 0,
                            lensCorrectionEnabled: true
                        )
                    )
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = developImage(
                        path: path, maxDimension: maxDimension, quality: quality, adjustments: adjustments,
                        maskLayers: maskLayers
                    )
                    DispatchQueue.main.async {
                        if let data = data {
                            result(FlutterStandardTypedData(bytes: data))
                        } else {
                            result(nil)
                        }
                    }
                }
            case "videoThumbnail":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                let maxDimension = (args["maxDimension"] as? NSNumber)?.intValue ?? 800
                // Anteil der Laufzeit, an dem gegriffen wird. Fehlt er,
                // bleibt es beim bisherigen Verhalten (kurz nach dem Start).
                let anteil = (args["anteil"] as? NSNumber)?.doubleValue
                DispatchQueue.global(qos: .userInitiated).async {
                    let thumbnail = videoThumbnail(
                        path: path, maxDimension: maxDimension, anteil: anteil)
                    DispatchQueue.main.async {
                        if let thumbnail = thumbnail {
                            result([
                                "jpeg": FlutterStandardTypedData(bytes: thumbnail.jpeg),
                                "durationSeconds": thumbnail.durationSeconds,
                            ])
                        } else {
                            result(nil)
                        }
                    }
                }
            case "recognizeText":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let erkannt = recognizeText(path: path)
                    DispatchQueue.main.async {
                        result(erkannt)
                    }
                }
            case "trimVideo":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String,
                    let outputPath = args["outputPath"] as? String,
                    let startSeconds = (args["startSeconds"] as? NSNumber)?.doubleValue,
                    let endSeconds = (args["endSeconds"] as? NSNumber)?.doubleValue
                else {
                    result(FlutterError(code: "bad_args", message: "path/outputPath/startSeconds/endSeconds fehlt", details: nil))
                    return
                }
                trimVideo(
                    path: path, outputPath: outputPath, startSeconds: startSeconds, endSeconds: endSeconds
                ) { success in
                    DispatchQueue.main.async {
                        result(success)
                    }
                }
            case "videoNativ":
                // Fragt nur, ob dieser Bau den nativen Schreiber kennt.
                // Ein `ping` genuegte dafuer nicht: Den gab es schon,
                // bevor es die Videoausgabe gab.
                result(true)
            case "videoStart":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String,
                    let breite = (args["breite"] as? NSNumber)?.intValue,
                    let hoehe = (args["hoehe"] as? NSNumber)?.intValue,
                    let takt = (args["bilderJeSekunde"] as? NSNumber)?.intValue
                else {
                    result(FlutterError(code: "bad_args", message: "path/breite/hoehe/bilderJeSekunde fehlt", details: nil))
                    return
                }
                Flugvideoschreiber.laufend?.verwirf()
                Flugvideoschreiber.laufend = nil
                do {
                    Flugvideoschreiber.laufend = try Flugvideoschreiber(
                        ziel: URL(fileURLWithPath: path),
                        breite: breite, hoehe: hoehe, bilderJeSekunde: takt)
                    result(nil)
                } catch let f as Flugvideofehler {
                    result(FlutterError(code: "video", message: f.text, details: nil))
                } catch {
                    result(FlutterError(code: "video", message: "\(error.localizedDescription)", details: nil))
                }
            case "videoBild":
                guard
                    let args = call.arguments as? [String: Any],
                    let punkte = args["rgba"] as? FlutterStandardTypedData
                else {
                    result(FlutterError(code: "bad_args", message: "rgba fehlt", details: nil))
                    return
                }
                guard let schreiber = Flugvideoschreiber.laufend else {
                    result(FlutterError(code: "video", message: "kein Lauf begonnen", details: nil))
                    return
                }
                // **Nicht auf dem Hauptthread.** Das Umsortieren und das
                // Anhaengen kosten je Bild Millisekunden; auf dem
                // Hauptthread stockte darueber die Fortschrittsanzeige der
                // Oberflaeche, die genau waehrenddessen laeuft.
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try schreiber.bild(punkte.data)
                        DispatchQueue.main.async { result(nil) }
                    } catch let f as Flugvideofehler {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "video", message: f.text, details: nil))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(FlutterError(code: "video", message: "\(error.localizedDescription)", details: nil))
                        }
                    }
                }
            case "videoFertig":
                guard let schreiber = Flugvideoschreiber.laufend else {
                    result(FlutterError(code: "video", message: "kein Lauf begonnen", details: nil))
                    return
                }
                Flugvideoschreiber.laufend = nil
                schreiber.beende { grund in
                    DispatchQueue.main.async {
                        if let grund = grund {
                            result(FlutterError(code: "video", message: grund, details: nil))
                        } else {
                            result(nil)
                        }
                    }
                }
            case "videoVerwerfen":
                Flugvideoschreiber.laufend?.verwirf()
                Flugvideoschreiber.laufend = nil
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Lädt eine Bilddatei über ImageIO (deckt HEIC/HEIF, DNG/RAW, TIFF-
    /// Sonderfälle usw. ab), skaliert sie ggf. auf maximal [maxDimension] px
    /// (längste Seite) und gibt sie als JPEG-Bytes zurück.
    ///
    /// Enthält das Bild eine eingebettete HDR-Gain-Map (Apples "Adaptive
    /// HDR", z.B. bei iPhone-Fotos im HDR-Modus), wird zuerst versucht, sie
    /// über Core Image einzubeziehen (siehe [convertHdrAwareJpeg]) – JPEG
    /// selbst kann kein HDR darstellen, aber ein damit ton-gemapptes Bild
    /// gibt die Kontrast-/Helligkeitsabsicht der Aufnahme deutlich besser
    /// wieder als das nackte SDR-Basisbild, das der normale Pfad unten liefern
    /// würde. Schlägt das aus irgendeinem Grund fehl (ältere macOS-Version,
    /// keine Gain-Map, o.ä.), fällt es lückenlos auf den bisherigen,
    /// unveränderten ImageIO-Pfad zurück.
    private static func convertToJpeg(path: String, maxDimension: Int, quality: Double) -> Data? {
        if #available(macOS 14.0, *),
            let hdrData = convertHdrAwareJpeg(path: path, maxDimension: maxDimension, quality: quality)
        {
            return hdrData
        }

        if #available(macOS 12.0, *),
            rawExtensions.contains((path as NSString).pathExtension.lowercased()),
            let rawData = convertRawWithLensCorrection(path: path, maxDimension: maxDimension, quality: quality)
        {
            return rawData
        }

        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            // Fallback: Vollauflösung laden, falls die Thumbnail-Erzeugung scheitert.
            guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return encodeJpeg(full, quality: quality)
        }
        return encodeJpeg(cgImage, quality: quality)
    }

    /// Ob [source] eine eingebettete HDR-Gain-Map besitzt (Apples "Adaptive
    /// HDR" in HEIC: neben dem normalen SDR-Basisbild eine zusätzliche
    /// Zusatzebene mit den Aufhellungs-/Kontrastinformationen für HDR-fähige
    /// Anzeigen). Ein günstiger Metadaten-Check statt eines vollen Decodes,
    /// damit ganz normale (Nicht-HDR-)Fotos weiterhin den bestehenden,
    /// schnelleren Pfad in [convertToJpeg] nehmen.
    @available(macOS 14.0, *)
    private static func hasHdrGainMap(source: CGImageSource) -> Bool {
        guard
            let auxInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
                source, 0, kCGImageAuxiliaryDataTypeHDRGainMap
            ) as? [CFString: Any]
        else { return false }
        return !auxInfo.isEmpty
    }

    /// Dekodiert [path] inkl. HDR-Gain-Map über Core Image
    /// (`.expandToHDR`) und rendert das Ergebnis über einen [CIContext] in
    /// den sRGB-Zielfarbraum zurück – dabei wendet Core Image automatisch
    /// die passende Ton-Kurve an, um den erweiterten HDR-Dynamikumfang auf
    /// den regulären SDR-Bereich abzubilden (dieselbe Technik, mit der z.B.
    /// Apple selbst HDR-Fotos für Apps/Websites ohne HDR-Unterstützung
    /// darstellt). Gibt `nil` zurück, wenn [path] keine Gain-Map enthält
    /// oder irgendein Schritt fehlschlägt – der Aufrufer fällt dann auf den
    /// normalen ImageIO-Pfad zurück.
    @available(macOS 14.0, *)
    private static func convertHdrAwareJpeg(path: String, maxDimension: Int, quality: Double) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            hasHdrGainMap(source: source)
        else { return nil }

        // .applyOrientationProperty ist hier zwingend nötig: anders als der
        // ImageIO-Pfad oben (kCGImageSourceCreateThumbnailWithTransform)
        // dreht Core Image ein geladenes Bild NICHT automatisch nach seiner
        // EXIF-Orientierung – ohne diese Option kämen hochkant aufgenommene
        // Fotos seitlich verdreht heraus.
        guard
            let hdrImage = CIImage(
                contentsOf: url, options: [.expandToHDR: true, .applyOrientationProperty: true]
            )
        else { return nil }

        let scaledImage = downscale(hdrImage, maxDimension: maxDimension)
        guard let colorSpace = ausgabefarbraum else { return nil }
        guard
            let cgImage = sharedCIContext.createCGImage(
                scaledImage, from: scaledImage.extent, format: .RGBA8, colorSpace: colorSpace
            )
        else { return nil }

        return encodeJpeg(cgImage, quality: quality)
    }

    /// Dateiendungen, die macOS' ImageIO/CIRAWFilter als Hersteller-RAW-
    /// Format erkennt (bestätigt über `CGImageSourceCopyTypeIdentifiers()`
    /// auf diesem System: 30 registrierte RAW-UTIs). Muss von Hand mit
    /// `lib/services/raw_formats.dart` synchron gehalten werden, da Swift
    /// die Dart-Datei nicht importieren kann.
    private static let rawExtensions: Set<String> = [
        "dng", "cr2", "cr3", "crw", // Canon (+ Adobe DNG, iPhone DNG)
        "nef", "nrw", "nefx", // Nikon
        "arw", "sr2", "srf", "axr", // Sony
        "raf", // Fujifilm
        "orf", // Olympus/OM System
        "rw2", // Panasonic
        "pef", // Pentax
        "3fr", "fff", // Hasselblad
        "iiq", // Phase One
        "dcr", // Kodak
        "mrw", // Minolta
        "mos", // Leaf
        "srw", // Samsung
        "erf", // Epson
        "rwl", "raw", // Leica
        "dxo", // DxO
    ]

    /// Die Tiefenkarte eines Fotos als Graustufen-PNG.
    ///
    /// **Warum das ueberhaupt geht:** Ein Porträtfoto neuerer iPhones
    /// traegt neben dem Bild ein Hilfsbild mit der Entfernung je Pixel.
    /// ImageIO gibt es heraus; daraus wird hier eine Maske, wie sie die
    /// App ohnehin schon kennt (DevelopMasks: ein Graustufen-PNG plus
    /// eigene Reglerwerte). Es entsteht also keine neue Maschinerie -
    /// nur eine neue Quelle fuer dieselbe Maske.
    ///
    /// **Disparitaet, nicht Entfernung.** Apple liefert meist
    /// `kCGImageAuxiliaryDataTypeDisparity` - den Kehrwert der
    /// Entfernung. Hoher Wert heisst nah. Das passt zur Maske: Weiss ist
    /// das Nahe, also das Motiv. Wer den Hintergrund treffen will,
    /// kehrt die Maske um - dafuer gibt es den Schalter im
    /// Maskeneditor.
    ///
    /// Normiert wird auf das tatsaechlich vorkommende Wertepaar, nicht auf
    /// einen festen Bereich: Eine Innenaufnahme spannt vielleicht 0,5 bis
    /// 2 Meter, eine Landschaft 2 bis 50. Feste Grenzen ergaeben in einem
    /// der beiden Faelle eine fast einfarbige Maske.
    ///
    /// Rueckgabe: `stand` immer, `png` nur bei `verfuegbar`.
    private static func depthMask(path: String) -> [String: Any] {
        guard let quelle = CGImageSourceCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, nil)
        else {
            return ["stand": "nichtLesbar"]
        }

        // Disparitaet zuerst, Tiefe als Rueckfall - beides kommt vor, und
        // AVDepthData rechnet ohnehin um.
        var info: CFDictionary?
        for art in [kCGImageAuxiliaryDataTypeDisparity, kCGImageAuxiliaryDataTypeDepth] {
            if let gefunden = CGImageSourceCopyAuxiliaryDataInfoAtIndex(quelle, 0, art) {
                info = gefunden
                break
            }
        }
        guard let daten = info as? [AnyHashable: Any] else {
            return ["stand": "keineTiefendaten"]
        }

        guard let tiefe = try? AVDepthData(fromDictionaryRepresentation: daten) else {
            return ["stand": "nichtLesbar"]
        }
        // Auf ein einheitliches Format bringen: Die Kamera liefert je nach
        // Geraet 16-Bit-Halbfliess- oder 32-Bit-Fliesskomma.
        let umgerechnet = tiefe.converting(
            toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let puffer = umgerechnet.depthDataMap

        CVPixelBufferLockBaseAddress(puffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(puffer, .readOnly) }

        let breite = CVPixelBufferGetWidth(puffer)
        let hoehe = CVPixelBufferGetHeight(puffer)
        let zeilenBytes = CVPixelBufferGetBytesPerRow(puffer)
        guard let basis = CVPixelBufferGetBaseAddress(puffer), breite > 0, hoehe > 0 else {
            return ["stand": "nichtLesbar"]
        }

        // Erst das Wertepaar suchen, dann normieren. NaN kommt vor, wo die
        // Kamera nichts messen konnte - solche Stellen werden spaeter
        // schwarz, zaehlen aber nicht in die Spanne hinein.
        var kleinster = Float.greatestFiniteMagnitude
        var groesster = -Float.greatestFiniteMagnitude
        for y in 0..<hoehe {
            let zeile = basis.advanced(by: y * zeilenBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<breite {
                let w = zeile[x]
                if w.isFinite {
                    if w < kleinster { kleinster = w }
                    if w > groesster { groesster = w }
                }
            }
        }
        guard kleinster < groesster else { return ["stand": "nichtLesbar"] }
        let spanne = groesster - kleinster

        var grau = [UInt8](repeating: 0, count: breite * hoehe)
        for y in 0..<hoehe {
            let zeile = basis.advanced(by: y * zeilenBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<breite {
                let w = zeile[x]
                grau[y * breite + x] = w.isFinite
                    ? UInt8(max(0, min(255, ((w - kleinster) / spanne) * 255)))
                    : 0
            }
        }

        guard
            let farbraum = CGColorSpace(name: CGColorSpace.linearGray),
            let kontext = CGContext(
                data: &grau, width: breite, height: hoehe, bitsPerComponent: 8,
                bytesPerRow: breite, space: farbraum,
                bitmapInfo: CGImageAlphaInfo.none.rawValue),
            let bild = kontext.makeImage(),
            let png = encodePng(bild)
        else {
            return ["stand": "nichtLesbar"]
        }

        return [
            "stand": "verfuegbar",
            "png": FlutterStandardTypedData(bytes: png),
            "breite": breite,
            "hoehe": hoehe,
        ]
    }

    /// Was die Objektivkorrektur für diese eine Datei leisten kann.
    ///
    /// Vier Antworten, weil sie zu vier verschiedenen Sätzen in der
    /// Oberfläche führen – ein blosses Ja/Nein würde „ist kein RAW" und
    /// „ist RAW, aber unbekannt" in denselben Topf werfen, obwohl das eine
    /// erwartbar und das andere eine Einschränkung ist:
    ///
    /// - `keinRaw`: JPEG, HEIC, PNG. Da gibt es nichts zu korrigieren, die
    ///   Kamera hat es längst getan.
    /// - `verfuegbar`: Apples Kamera-/Objektivdatenbank kennt die Kombination.
    /// - `nichtInDatenbank`: gültiges RAW, aber keine Profile dafür. Betrifft
    ///   auch Apples ProRAW-DNGs – dort ist das richtig so, die Korrektur
    ///   steckt schon in der Datei.
    /// - `nichtLesbar`: `CIRAWFilter` bekommt die Datei gar nicht auf. Dann
    ///   greift auch die übrige RAW-Entwicklung nicht, und der Nutzer sollte
    ///   das erfahren, statt sich über wirkungslose Regler zu wundern.
    @available(macOS 12.0, *)
    /// Aufnahmewerte ueber ImageIO – derselbe Weg, den auch der Finder
    /// und Fotos.app nehmen. Liefert eine Map fuer den Method-Channel;
    /// fehlende Werte fehlen schlicht, statt als 0 dazustehen.
    ///
    /// Zur ISO-Zeile: Kanonisch waere `ISOSpeedRatings`, doch Canon-CR3
    /// legt den Wert unter `ISOSpeed` ab. Beide zu lesen kostet eine Zeile
    /// und war an einer echten Datei noetig – mit nur dem kanonischen
    /// Schluessel kam ISO nicht an.
    private static func cameraMetadata(path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path)
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return nil }

        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]

        var werte: [String: Any] = [:]
        func text(_ schluessel: String, _ quellen: [[String: Any]]) {
            for q in quellen {
                if let v = q[schluessel] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty {
                    werte[schluessel] = v
                    return
                }
            }
        }
        func zahl(_ ziel: String, _ schluessel: [String], _ quellen: [[String: Any]]) {
            for k in schluessel {
                for q in quellen {
                    if let v = q[k] as? NSNumber {
                        werte[ziel] = v.doubleValue
                        return
                    }
                    // ISOSpeedRatings steht als Feld da, nicht als Einzelwert.
                    if let a = q[k] as? [NSNumber], let erste = a.first {
                        werte[ziel] = erste.doubleValue
                        return
                    }
                }
            }
        }

        text("Make", [tiff])
        text("Model", [tiff])
        text("LensModel", [exif, aux])
        zahl("FocalLength", ["FocalLength"], [exif])
        zahl("FocalLenIn35mmFilm", ["FocalLenIn35mmFilm"], [exif])
        zahl("FNumber", ["FNumber"], [exif])
        zahl("ISO", ["ISOSpeedRatings", "ISOSpeed"], [exif, aux])
        zahl("ExposureTime", ["ExposureTime"], [exif])
        zahl("ExposureBiasValue", ["ExposureBiasValue"], [exif])
        text("DateTimeOriginal", [exif])
        if werte["DateTimeOriginal"] == nil, let d = exif["DateTimeDigitized"] as? String {
            werte["DateTimeOriginal"] = d
        }
        return werte.isEmpty ? nil : werte
    }

    private static func lensCorrectionStatus(path: String) -> String {
        let url = URL(fileURLWithPath: path)
        guard rawExtensions.contains(url.pathExtension.lowercased()) else {
            return "keinRaw"
        }
        guard let filter = CIRAWFilter(imageURL: url) else { return "nichtLesbar" }
        // Eine nativeSize von 0 heisst: Der Dekoder hat die Datei zwar
        // angenommen, kann aber nichts damit anfangen (real beobachtet bei
        // 96-MB-DNGs einer Canon EOS R10).
        if filter.nativeSize.width <= 0 || filter.nativeSize.height <= 0 {
            return "nichtLesbar"
        }
        return filter.isLensCorrectionSupported ? "verfuegbar" : "nichtInDatenbank"
    }

    /// Dekodiert eine RAW-Datei über Apples `CIRAWFilter` statt der
    /// einfachen ImageIO-Vorschau weiter unten – dieselbe API, mit der z.B.
    /// auch Fotos.app RAW-Dateien verarbeitet. `CIRAWFilter` erkennt Kamera
    /// und Objektiv dafür selbst aus den RAW-Metadaten und gleicht sie mit
    /// Apples eigener, über System-Updates gepflegter Kamera-/Objektiv-
    /// Datenbank ab – bei einem Treffer (`isLensCorrectionSupported`) wird
    /// automatisch eine Objektivkorrektur (Verzeichnung, Vignettierung)
    /// angewendet, ganz ohne eigene Profildatenbank. Nicht jede Kamera/jedes
    /// Objektiv wird unterstützt (bei eigenen Testfotos von einem iPhone 17
    /// Pro und einer Canon EOS R10 z.B. nicht) – dann bleibt es beim reinen,
    /// unkorrigierten RAW-Dekodieren. Gibt `nil` zurück, wenn die Datei kein
    /// gültiges RAW-Format ist oder irgendein Schritt fehlschlägt; der
    /// Aufrufer fällt dann auf den bisherigen ImageIO-Pfad zurück, der
    /// ebenfalls RAW lesen kann, nur ohne Objektivkorrektur.
    @available(macOS 12.0, *)
    private static func convertRawWithLensCorrection(path: String, maxDimension: Int, quality: Double) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }

        // Direkt in der gewünschten Zielgröße dekodieren lassen, statt in
        // voller Auflösung zu rendern und danach herunterzuskalieren wie bei
        // [downscale] – CIRAWFilter unterstützt das nativ und spart bei
        // großen RAW-Dateien (oft 40+ Megapixel) unnötige Rechenzeit.
        let longSide = max(filter.nativeSize.width, filter.nativeSize.height)
        if longSide > 0 {
            filter.scaleFactor = min(1, Float(maxDimension) / Float(longSide))
        }
        if filter.isLensCorrectionSupported {
            filter.isLensCorrectionEnabled = true
        }

        guard let outputImage = filter.outputImage,
            let colorSpace = ausgabefarbraum,
            let cgImage = sharedCIContext.createCGImage(
                outputImage, from: outputImage.extent, format: .RGBA8, colorSpace: colorSpace
            )
        else { return nil }

        return encodeJpeg(cgImage, quality: quality)
    }

    /// Ein einzelner, wiederverwendeter [CIContext] statt eines neuen pro
    /// Konvertierung: die Erstellung baut eine eigene Metal/GPU-Rendering-
    /// Pipeline auf (mehrere zehn Millisekunden) und ist damit deutlich
    /// teurer als das eigentliche Bild-Rendering selbst – bei vielen
    /// HDR-Fotos hintereinander (z.B. beim Import) summiert sich das sonst zu
    /// spürbar unnötigem Overhead. `CIContext` ist laut Apple-Dokumentation
    /// sicher von mehreren Threads gleichzeitig nutzbar, passt also zu den
    /// parallelen Aufrufen über `DispatchQueue.global` oben in
    /// `ImageConverterChannel`.
    private static let sharedCIContext = CIContext()

    /// Regler-Werte des DevelopScreen (siehe lib/screens/develop_screen.dart)
    /// – ein "neutraler" Wert (0 bzw. `nil` bei Weißabgleich) entspricht
    /// unverändert, damit ein frisch geöffnetes Foto ohne gespeicherte
    /// DevelopSettings optisch identisch zur normalen Vorschau bleibt.
    private struct DevelopAdjustments {
        let exposure: Float
        let temperature: Float?
        let tint: Float?
        let contrast: Float
        let shadows: Float
        /// Lichter, -1..1 - das Gegenstueck zu shadows.
        let highlights: Float
        let sharpness: Float
        let noiseReduction: Float
        let clarity: Float
        let vignette: Float
        let lensCorrectionEnabled: Bool

        /// Tonwertkurve und Farbmischer kommen NICHT als Regler-Zahlen an,
        /// sondern als fertig ausgerechnete Nachschlagetabellen (siehe
        /// lib/services/develop_color.dart). Der Grund ist Absicht: Sonst
        /// müssten die Kurveninterpolation und die Farbband-Mathematik hier
        /// ein zweites Mal stehen – neben der Fassung im GPU-Shader für die
        /// Live-Vorschau – und beide könnten unbemerkt auseinanderlaufen.
        ///
        /// Fehlt eine der beiden, ist das Werkzeug neutral und der Filter
        /// entfällt; Masken übertragen sie grundsätzlich nicht.
        var curveLut: [Float]? = nil
        var colorCube: [Float]? = nil
        var colorCubeSize: Int = 0
    }

    /// Eine KI-Objektmaske (siehe MaskEditor/DevelopMasks): [path] zeigt auf
    /// eine Grauwert-PNG-Alphamaske (weiß = Anpassung wirksam, schwarz =
    /// unverändert), [adjustments] gilt NUR innerhalb dieser Maske.
    private struct MaskLayer {
        let path: String
        let adjustments: DevelopAdjustments
    }

    /// Rendert eine Bilddatei (RAW oder normales Format) mit den
    /// angegebenen, nicht-destruktiven Anpassungen. Für RAW-Dateien über
    /// CIRAWFilter-Eigenschaften (arbeitet auf den Rohdaten vor dem
    /// Demosaicing – höhere Qualität als eine Filterkette auf dem bereits
    /// demosaicten Bild), für alle anderen Formate über eine äquivalente
    /// CIFilter-Kette auf dem dekodierten Bild (siehe
    /// [applyNonRawAdjustments]). [maskLayers] werden NACH den globalen
    /// Reglern der Reihe nach übereinandergelegt (siehe
    /// [compositeMaskLayers]) – dieselbe [applyNonRawAdjustments]-Filterkette
    /// wie für die globalen Regler, nur pro Maske auf das bereits global
    /// angepasste Bild angewendet und über `CIBlendWithMask` zurück-
    /// kompositiert. Gibt `nil` zurück, wenn die Datei nicht geladen werden
    /// kann.
    private static func developImage(
        path: String, maxDimension: Int, quality: Double, adjustments: DevelopAdjustments,
        maskLayers: [MaskLayer] = []
    ) -> Data? {
        let url = URL(fileURLWithPath: path)
        let ext = (path as NSString).pathExtension.lowercased()
        let output: CIImage?

        // #available (statt einer Funktionssignatur-weiten @available-
        // Annotation wie bei convertRawWithLensCorrection) wird hier
        // gebraucht, weil developImage ungated vom Method-Channel-Handler
        // aufgerufen wird – auf macOS < 12 fällt selbst eine RAW-Datei auf
        // die CIFilter-Kette unten zurück (ohne CIRAWFilter-spezifische
        // Anpassungen wie Objektivkorrektur, aber immer noch mit Belichtung/
        // Weißabgleich/Kontrast/etc.).
        if #available(macOS 12.0, *), rawExtensions.contains(ext), let filter = CIRAWFilter(imageURL: url) {
            filter.exposure = adjustments.exposure
            if let temperature = adjustments.temperature {
                filter.neutralTemperature = temperature
            }
            if let tint = adjustments.tint {
                filter.neutralTint = tint
            }
            if filter.isContrastSupported {
                filter.contrastAmount = 1.0 + adjustments.contrast
            }
            filter.shadowBias = adjustments.shadows
            if filter.isSharpnessSupported {
                filter.sharpnessAmount = adjustments.sharpness
            }
            if filter.isLuminanceNoiseReductionSupported {
                filter.luminanceNoiseReductionAmount = adjustments.noiseReduction
            }
            if filter.isColorNoiseReductionSupported {
                filter.colorNoiseReductionAmount = adjustments.noiseReduction
            }
            if filter.isLensCorrectionSupported {
                filter.isLensCorrectionEnabled = adjustments.lensCorrectionEnabled
            }
            let longSide = max(filter.nativeSize.width, filter.nativeSize.height)
            if longSide > 0 {
                filter.scaleFactor = min(1, Float(maxDimension) / Float(longSide))
            }
            // CIRAWFilter kennt weder Kurve noch Farbmischer – beide laufen
            // deshalb als Nachkette auf seiner Ausgabe. Dieselbe Funktion
            // wie im Nicht-RAW-Zweig, die beiden Pfade teilen sich hier
            // erstmals Code, statt ihn zu spiegeln.
            output = filter.outputImage.map {
                // Reihenfolge wie im Shader: Lichter nach dem Kontrast
                // (den CIRAWFilter oben erledigt), vor Kurve und Mischer.
                applyCurveAndMixer(lichterAnwenden($0, adjustments.highlights), adjustments)
            }
        } else {
            guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
            else { return nil }
            output = applyNonRawAdjustments(downscale(source, maxDimension: maxDimension), adjustments)
        }

        guard var renderedImage = output else { return nil }
        renderedImage = compositeMaskLayers(renderedImage, maskLayers)

        guard let colorSpace = ausgabefarbraum,
            let cgImage = sharedCIContext.createCGImage(
                renderedImage, from: renderedImage.extent, format: .RGBA8, colorSpace: colorSpace
            )
        else { return nil }

        return encodeJpeg(cgImage, quality: quality)
    }

    /// Legt [maskLayers] der Reihe nach über [base] (das bereits global
    /// angepasste Bild): pro Maske wird [applyNonRawAdjustments] auf den
    /// AKTUELLEN Zwischenstand angewendet (nicht auf [base] selbst – so
    /// wirken mehrere überlappende Masken tatsächlich nacheinander statt
    /// dass die letzte alle vorherigen überschreibt) und über
    /// `CIBlendWithMask` nur innerhalb der Maske zurückkompositiert. Die
    /// PNG-Maskendatei wird dafür auf die tatsächliche Arbeitsgröße von
    /// [base] skaliert (die kann je nach `maxDimension` von der Original-
    /// Auflösung abweichen, in der die Maske gespeichert wurde). Maske
    /// fehlt/unlesbar → diese eine Maske wird übersprungen, der Rest läuft
    /// normal weiter.
    private static func compositeMaskLayers(_ base: CIImage, _ maskLayers: [MaskLayer]) -> CIImage {
        var result = base
        for layer in maskLayers {
            guard let maskImage = CIImage(contentsOf: URL(fileURLWithPath: layer.path)) else { continue }
            let scaleX = result.extent.width / maskImage.extent.width
            let scaleY = result.extent.height / maskImage.extent.height
            let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

            let adjusted = applyNonRawAdjustments(result, layer.adjustments)

            guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { continue }
            blendFilter.setValue(adjusted, forKey: kCIInputImageKey)
            blendFilter.setValue(result, forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)
            result = blendFilter.outputImage ?? result
        }
        return result
    }

    /// Liest eine Float32List vom Method-Channel als Swift-Array.
    ///
    /// Gibt `nil` zurück, wenn nichts da ist oder die Länge kein Vielfaches
    /// von 4 Byte ist – lieber den Filter weglassen als aus einem halben
    /// Wert eine Farbe zu erfinden.
    private static func floatArray(_ value: Any?) -> [Float]? {
        guard let typed = value as? FlutterStandardTypedData else { return nil }
        let data = typed.data
        guard !data.isEmpty, data.count % MemoryLayout<Float32>.size == 0 else { return nil }
        return data.withUnsafeBytes { roh in Array(roh.bindMemory(to: Float32.self)) }
    }

    /// Tonwertkurve und Farbmischer als Core-Image-Filter.
    ///
    /// Beide arbeiten in **sRGB**, nicht linear: Das ist die Konvention von
    /// Lightroom und darktable, und nur so entspricht die im Programm
    /// gezeichnete Kurve dem, was am Ende im Bild steht. `inputColorSpace`
    /// deshalb ausdrücklich setzen statt der Vorgabe zu vertrauen.
    ///
    /// Die Tabellen kommen fertig aus Dart – hier wird nichts gerechnet,
    /// nur übergeben (siehe [DevelopAdjustments.curveLut]).
    /// Der Lichter-Regler als eigener Kern.
    ///
    /// Warum nicht `CIHighlightShadowAdjust`: Dessen `inputHighlightAmount`
    /// reicht von 0 bis 1 mit 1 = neutral - es kann Lichter nur
    /// zuruecknehmen, nicht anheben. Der Regler in der Oberflaeche geht
    /// aber wie der Tiefen-Regler von -1 bis +1, und ein einseitiger
    /// Lichter-Regler neben einem zweiseitigen Tiefen-Regler waere kaputt.
    ///
    /// Die Rechnung ist Zeile fuer Zeile dieselbe wie in
    /// `shaders/develop_adjustments.frag`, Schritt 4b. Genau das ist der
    /// Zweck: Die Live-Vorschau laeuft ueber den Shader, das gespeicherte
    /// Ergebnis hier - laufen die beiden auseinander, sieht der Nutzer beim
    /// Speichern ein anderes Bild als beim Ziehen.
    ///
    /// Core Image rechnet im linearen Arbeitsraum, der Shader an dieser
    /// Stelle ebenfalls (die Ruecknahme nach sRGB kommt erst danach) - die
    /// Werte, auf die der Kern trifft, sind also dieselben.
    ///
    /// **Bewusst ungleich:** Die Tiefen laufen weiter ueber `shadowBias`
    /// bzw. `CIHighlightShadowAdjust`. Sie auf denselben Kern umzustellen
    /// waere sauberer, wuerde aber jede bereits gespeicherte Entwicklung
    /// anders aussehen lassen - die Werte werden bei jeder Anzeige neu
    /// angewandt, es gibt kein eingebranntes Ergebnis.
    private static let lichterKern: CIColorKernel? = CIColorKernel(source: """
        kernel vec4 lichter(__sample s, float betrag) {
          vec3 c = s.rgb;
          float luma = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
          float gewicht = smoothstep(0.4, 1.0, luma);
          c += betrag * 0.35 * gewicht;
          return vec4(c, s.a);
        }
        """)

    /// Wendet den Lichter-Regler an. Bei 0 oder fehlendem Kern bleibt das
    /// Bild unveraendert - ein nicht uebersetzbarer Kern darf die
    /// Entwicklung nicht scheitern lassen, nur diesen einen Regler.
    private static func lichterAnwenden(_ image: CIImage, _ betrag: Float) -> CIImage {
        guard betrag != 0, let kern = lichterKern else { return image }
        let raus = kern.apply(
            extent: image.extent,
            arguments: [image, betrag]
        )
        return raus ?? image
    }

    private static func applyCurveAndMixer(_ input: CIImage, _ a: DevelopAdjustments) -> CIImage {
        var image = input
        // **Arbeitsfarbraum, nicht Ausgabefarbraum.** Hier steht, in
        // welchem Raum Kurve und Farbmischer rechnen - und das muss sRGB
        // bleiben: Die Dart-Seite stellt fuer die Shader-Vorschau
        // dieselbe Rechnung an (siehe develop_color.dart, "die Mathematik
        // nur einmal"). Wuerde hier P3 stehen, zeigte die Vorschau beim
        // Ziehen etwas anderes als das gerenderte Ergebnis.
        guard let raum = CGColorSpace(name: CGColorSpace.sRGB) else { return image }

        if let lut = a.curveLut, lut.count == 256 * 3, let f = CIFilter(name: "CIColorCurves") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(Data(bytes: lut, count: lut.count * MemoryLayout<Float>.size),
                       forKey: "inputCurvesData")
            f.setValue(CIVector(x: 0, y: 1), forKey: "inputCurvesDomain")
            f.setValue(raum, forKey: "inputColorSpace")
            image = f.outputImage ?? image
        }

        if let cube = a.colorCube, a.colorCubeSize > 1,
            cube.count == a.colorCubeSize * a.colorCubeSize * a.colorCubeSize * 4,
            let f = CIFilter(name: "CIColorCubeWithColorSpace")
        {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(a.colorCubeSize, forKey: "inputCubeDimension")
            f.setValue(Data(bytes: cube, count: cube.count * MemoryLayout<Float>.size),
                       forKey: "inputCubeData")
            f.setValue(raum, forKey: "inputColorSpace")
            image = f.outputImage ?? image
        }

        return image
    }

    /// CIFilter-Kette für Nicht-RAW-Formate (JPEG/HEIC/PNG & Co.), als
    /// Ersatz für die CIRAWFilter-Eigenschaften oben – dieselben sechs
    /// Regler, nur auf dem bereits demosaicten Bild angewendet.
    /// Reihenfolge bewusst: Belichtung zuerst (wirkt sich sinnvoll auf
    /// nachfolgende Kontrast-/Schatten-Berechnungen aus), Weißabgleich vor
    /// Kontrast, Schärfen/Rauschunterdrückung zuletzt (arbeiten auf dem
    /// fertig tonkorrigierten Bild, wie bei RAW-Entwicklern üblich).
    /// Objektivkorrektur entfällt hier – die betrifft nur RAW-Rohdaten.
    private static func applyNonRawAdjustments(_ input: CIImage, _ a: DevelopAdjustments) -> CIImage {
        var image = input
        if a.exposure != 0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(a.exposure, forKey: kCIInputEVKey)
            image = f.outputImage ?? image
        }
        if let temperature = a.temperature, let f = CIFilter(name: "CITemperatureAndTint") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            f.setValue(CIVector(x: CGFloat(temperature), y: CGFloat(a.tint ?? 0)), forKey: "inputTargetNeutral")
            image = f.outputImage ?? image
        }
        if a.contrast != 0, let f = CIFilter(name: "CIColorControls") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.0 + a.contrast, forKey: kCIInputContrastKey)
            image = f.outputImage ?? image
        }
        if a.shadows != 0, let f = CIFilter(name: "CIHighlightShadowAdjust") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.0 + a.shadows, forKey: "inputShadowAmount")
            image = f.outputImage ?? image
        }
        image = lichterAnwenden(image, a.highlights)
        // Tonwertkurve und Farbmischer wirken auf dem tonkorrigierten Bild,
        // aber VOR Schärfe und Rauschunterdrückung: Eine steile Kurve nach
        // dem Schärfen würde dessen Säume mit verstärken. Im RAW-Zweig
        // ergibt sich dieselbe Reihenfolge von selbst, weil CIRAWFilter
        // Schärfe und Entrauschen schon vor seiner Ausgabe erledigt.
        image = applyCurveAndMixer(image, a)

        if a.sharpness > 0, let f = CIFilter(name: "CISharpenLuminance") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(a.sharpness * 2.0, forKey: kCIInputSharpnessKey)
            image = f.outputImage ?? image
        }
        if a.noiseReduction > 0, let f = CIFilter(name: "CINoiseReduction") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(a.noiseReduction, forKey: "inputNoiseLevel")
            f.setValue(0.4, forKey: kCIInputSharpnessKey)
            image = f.outputImage ?? image
        }

        // Klarheit: eine Unschärfemaske mit grossem Radius. Genau das
        // unterscheidet sie vom Schärfen darüber – der kleine Radius dort
        // arbeitet Kanten heraus, der grosse hier den Eindruck von Struktur
        // über grössere Flächen. Deshalb auch NACH dem Schärfen: Beide
        // greifen an verschiedenen Grössenordnungen an.
        if a.clarity != 0, let f = CIFilter(name: "CIUnsharpMask") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(20.0, forKey: kCIInputRadiusKey)
            f.setValue(abs(a.clarity) * 1.5, forKey: kCIInputIntensityKey)
            if let raus = f.outputImage {
                // Negative Klarheit gibt es als Filter nicht; sie entsteht
                // durch Zurückblenden über das Original hinaus.
                image = a.clarity > 0 ? raus : mische(image, raus, -Double(a.clarity))
            }
        }

        // Vignettierung. CIVignette dunkelt nur ab; zum Aufhellen wird der
        // Effekt gespiegelt und zurückgeblendet.
        if a.vignette != 0, let f = CIFilter(name: "CIVignette") {
            f.setValue(image, forKey: kCIInputImageKey)
            f.setValue(1.0, forKey: kCIInputRadiusKey)
            f.setValue(-abs(a.vignette) * 2.0, forKey: kCIInputIntensityKey)
            if let raus = f.outputImage {
                image = a.vignette < 0 ? raus : mische(image, raus, -Double(a.vignette))
            }
        }
        return image
    }

    /// Blendet [b] mit [anteil] über [a]. Bei negativem [anteil] wird über
    /// [a] hinaus in die Gegenrichtung extrapoliert – so entsteht aus einem
    /// Filter, den es nur in eine Richtung gibt, auch die andere.
    private static func mische(_ a: CIImage, _ b: CIImage, _ anteil: Double) -> CIImage {
        guard let f = CIFilter(name: "CIMix") else { return a }
        f.setValue(a, forKey: kCIInputImageKey)
        f.setValue(b, forKey: kCIInputBackgroundImageKey)
        f.setValue(anteil, forKey: "inputAmount")
        return f.outputImage ?? a
    }

    /// Skaliert [image] gleichmäßig herunter, falls die längste Seite über
    /// [maxDimension] px liegt – Core Image hat (anders als ImageIOs
    /// Thumbnail-Erzeugung) keine eingebaute "maximale Kantenlänge"-Option.
    private static func downscale(_ image: CIImage, maxDimension: Int) -> CIImage {
        let longSide = max(image.extent.width, image.extent.height)
        guard longSide > CGFloat(maxDimension), longSide > 0 else { return image }
        let scale = CGFloat(maxDimension) / longSide
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    /// Verlustfrei, anders als [encodeJpeg]. Fuer eine Maske ist das keine
    /// Feinheit: JPEG saeumt Kanten, und eine Maske besteht praktisch nur
    /// aus Kanten - die Saeume laegen als Schleier neben dem Motiv.
    private static func encodePng(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let ziel = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(ziel, image, nil)
        guard CGImageDestinationFinalize(ziel) else { return nil }
        return data as Data
    }

    /// Der Farbraum, in dem alles herausgerendert wird.
    ///
    /// **Warum nicht sRGB.** Hier stand an drei Stellen fest sRGB, und
    /// ImageIO schreibt fuer sRGB gar kein Profil in die Datei - das ist
    /// der stillschweigende Standard. Gemessen an der echten Bibliothek:
    /// Eine iPhone-HEIC in Display P3 mit HDR-Gainmap ergab eine Vorschau
    /// ohne jedes Profil, also sRGB. 42 von 80 iPhone-Aufnahmen sind
    /// Display P3, und jede neuere Kamera liefert mehr als sRGB.
    ///
    /// Display P3 enthaelt sRGB vollstaendig: Ein sRGB-Foto sieht danach
    /// gleich aus, ein P3-Foto endlich richtig. Und ImageIO bettet das
    /// Profil ein, sobald es nicht sRGB ist - nachgemessen, das ist der
    /// ganze Unterschied zwischen "ohne Profil" und "Display P3" in der
    /// Ausgabedatei.
    ///
    /// **Nicht zu verwechseln mit dem Arbeitsfarbraum** in
    /// [applyCurveAndMixer]: Der bestimmt, wie Kurve und Farbmischer
    /// rechnen, und muss sRGB bleiben, weil die Dart-Seite dieselbe
    /// Rechnung fuer die Shader-Vorschau anstellt.
    private static var ausgabefarbraum: CGColorSpace? {
        CGColorSpace(name: CGColorSpace.displayP3)
    }

    private static func encodeJpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Erkennt Text in einer Bilddatei über Apples Vision-Framework (rein
    /// on-device, kein Modell-Download nötig, seit macOS 10.13 eingebaut).
    /// `.recognitionLevel = .accurate` statt `.fast`, da OCR beim Import im
    /// Hintergrund läuft und nicht interaktiv blockiert – Genauigkeit zählt
    /// hier mehr als Geschwindigkeit. Erkannte Zeilen werden mit `\n`
    /// verbunden zurückgegeben; bei keinem gefundenen Text ein leerer
    /// String (nicht `nil` – `nil` bedeutet "Erkennung fehlgeschlagen",
    /// siehe NativeImageConverter.recognizeText auf Dart-Seite).
    ///
    /// Zusätzlich kommt zu jeder Zeile ihr Platz im Bild zurück (siehe
    /// `services/textstellen.dart`). Vision liefert ihn als Anteil der
    /// Bildkante, rechnet dabei aber **von unten links**; hier wird daraus
    /// der oben-links-Ursprung, den Flutter überall sonst verwendet. Die
    /// Umrechnung gehört an diese eine Stelle und nicht in die Anzeige.
    private static func recognizeText(path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary
            )
        else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        var lines: [String] = []
        var stellen: [[String: Any]] = []
        for beobachtung in request.results ?? [] {
            guard let text = beobachtung.topCandidates(1).first?.string, !text.isEmpty else {
                continue
            }
            lines.append(text)
            let kasten = beobachtung.boundingBox
            stellen.append([
                "t": text,
                "x": kasten.origin.x,
                "y": 1.0 - (kasten.origin.y + kasten.height),
                "b": kasten.width,
                "h": kasten.height,
            ])
        }
        return ["text": lines.joined(separator: "\n"), "stellen": stellen]
    }

    private struct VideoThumbnail {
        let jpeg: Data
        let durationSeconds: Double
    }

    /// Extrahiert einen einzelnen Frame aus einer Videodatei über
    /// AVFoundation (behebt das Platzhalter-Icon für Video-Thumbnails in der
    /// Kachelansicht) und liefert gleich die Videolänge mit, da beides über
    /// dasselbe AVAsset ohnehin benötigt wird.
    /// Ein Standbild aus einem Video.
    ///
    /// [anteil] ist die Stelle in der Laufzeit, 0 bis 1. Ohne Angabe wird
    /// wie bisher kurz nach dem Start gegriffen; mit Angabe entstehen die
    /// weiteren Standbilder, aus denen die Auswertung eines laengeren
    /// Videos besteht (siehe `videostandbilder.dart`).
    ///
    /// `requestedTimeToleranceBefore/After` auf zero: Ohne das liefert
    /// AVFoundation das naechstgelegene KEYFRAME, und bei einem Video mit
    /// weit auseinanderliegenden Keyframes waeren mehrere angeforderte
    /// Stellen dasselbe Bild.
    private static func videoThumbnail(
        path: String, maxDimension: Int, anteil: Double? = nil
    ) -> VideoThumbnail? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let rawDuration = CMTimeGetSeconds(asset.duration)
        let durationSeconds = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        // Ein kleines Stück nach dem Start greifen statt exakt Frame 0 – bei
        // vielen Videos ist der allererste Frame schwarz oder unbrauchbar.
        let offsetSeconds: Double
        if let anteil = anteil, durationSeconds > 0 {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            offsetSeconds = min(max(anteil, 0), 1) * durationSeconds
        } else {
            offsetSeconds = durationSeconds > 0 ? min(0.5, durationSeconds / 2) : 0
        }
        let requestedTime = CMTime(seconds: offsetSeconds, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: requestedTime, actualTime: nil) else {
            return nil
        }
        guard let jpeg = encodeJpeg(cgImage, quality: 0.8) else { return nil }
        return VideoThumbnail(jpeg: jpeg, durationSeconds: durationSeconds)
    }

    /// Schneidet ein Video nicht-destruktiv auf [startSeconds, endSeconds] zu
    /// – über AVFoundations `AVAssetExportSession` (dieselbe Art API, mit der
    /// z.B. auch Fotos.app/iMovie exportieren). Das Original bleibt
    /// unangetastet, das Ergebnis landet unter [outputPath]. Re-encodiert
    /// nach H.264/MP4 (`AVAssetExportPresetHighestQuality`) statt eines
    /// verlustfreien "Passthrough"-Exports, damit das Ergebnis unabhängig
    /// vom Quellcodec zuverlässig abspielbar bleibt. Ruft [completion] mit
    /// `true` bei Erfolg auf – auf einer beliebigen Queue (siehe
    /// `exportAsynchronously`), der Aufrufer (Channel-Handler oben) springt
    /// selbst auf den Hauptthread zurück, bevor er an Flutter antwortet.
    private static func trimVideo(
        path: String, outputPath: String, startSeconds: Double, endSeconds: Double,
        completion: @escaping (Bool) -> Void
    ) {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard
            let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else {
            completion(false)
            return
        }

        let outputURL = URL(fileURLWithPath: outputPath)
        try? FileManager.default.removeItem(at: outputURL)

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )
        session.exportAsynchronously {
            completion(session.status == .completed)
        }
    }
}


/// Einmalige Standortabfrage ueber CoreLocation.
///
/// Warum eine eigene Klasse und kein Einzeiler: CLLocationManager
/// antwortet ueber einen Delegierten, nicht als Rueckgabewert, und er muss
/// am Leben bleiben, bis die Antwort da ist. Eine lokale Variable waere
/// vorher abgeraeumt – der Rueckruf kaeme nie.
///
/// Rueckgabe an Flutter: eine Map mit breite/laenge/genauigkeit, oder nil.
/// Ein `nil` heisst „kein Standort", nicht „Fehler" – die Oberflaeche
/// sagt dann, dass nichts zu holen war, statt eine Ausnahme zu zeigen.
private final class Standortgeber: NSObject, CLLocationManagerDelegate {
    static let geteilt = Standortgeber()

    private let verwalter = CLLocationManager()
    private var wartende: [([String: Any]?) -> Void] = []
    private let schloss = NSLock()
    private var laeuft = false

    override init() {
        super.init()
        verwalter.delegate = self
        verwalter.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func einmalHolen(_ fertig: @escaping ([String: Any]?) -> Void) {
        schloss.lock()
        wartende.append(fertig)
        let schonUnterwegs = laeuft
        laeuft = true
        schloss.unlock()
        if schonUnterwegs { return }

        DispatchQueue.main.async {
            // Ohne Erlaubnis fragt requestLocation nicht nach, sondern
            // liefert stillschweigend nichts. Erst fragen, dann holen.
            let stand = self.verwalter.authorizationStatus
            if stand == .notDetermined {
                self.verwalter.requestWhenInUseAuthorization()
                // Die Antwort kommt ueber locationManagerDidChangeAuthorization.
                return
            }
            if stand == .denied || stand == .restricted {
                self.antworten(nil)
                return
            }
            self.verwalter.requestLocation()
        }

        // Nicht ewig warten: Ohne Sichtverbindung zu WLAN-Ortung oder GPS
        // antwortet CoreLocation gar nicht. Zwoelf Sekunden sind laenger
        // als jede erfolgreiche Abfrage hier gedauert hat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            self.antworten(nil)
        }
    }

    private func antworten(_ werte: [String: Any]?) {
        schloss.lock()
        let offen = wartende
        wartende.removeAll()
        laeuft = false
        schloss.unlock()
        for r in offen { r(werte) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            antworten(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations orte: [CLLocation]) {
        guard let ort = orte.last else { antworten(nil); return }
        antworten([
            "breite": ort.coordinate.latitude,
            "laenge": ort.coordinate.longitude,
            "genauigkeit": ort.horizontalAccuracy,
        ])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        antworten(nil)
    }
}


// ===== FLUGVIDEO-ANFANG =====
// Alles zwischen diesen beiden Marken ist frei von Flutter-Typen und wird
// von `tool/flugvideo_nativ_probe.sh` woertlich herausgeschnitten und
// einzeln uebersetzt. So laeuft derselbe Quelltext, den die App
// ausliefert, auch im Pruefstand - und der schreibt eine echte Datei, die
// `ffprobe` lesen muss.

/// **Der Videoschreiber fuer macOS - ohne ffmpeg.**
///
/// Unter Linux und Windows liegt ffmpeg im Paket; unter macOS lag der
/// Videoexport bisher an einem selbst installierten ffmpeg. Das konnte
/// gar nicht gehen, und zwar aus zwei voneinander unabhaengigen Gruenden:
///
///   1. **Der Sandkasten laesst kein fremdes Programm starten.** Gemessen
///      an einem eigens signierten Probebuendel mit denselben Rechten wie
///      die App: `stat()` auf `/opt/homebrew/bin/ffmpeg` gelingt,
///      `access(X_OK)` und `posix_spawn` scheitern beide mit EPERM. Die
///      Werkzeugsuche haette es also sogar gefunden - und der Start waere
///      trotzdem gescheitert.
///   2. **Aus dem Dock gestartet ist `/opt/homebrew/bin` nicht im PATH.**
///      Eine App, die der Finder startet, bekommt
///      `/usr/bin:/bin:/usr/sbin:/sbin` und sonst nichts. Aus einem
///      Terminal heraus sieht das anders aus - deshalb faellt es bei
///      jeder Pruefung durch, die von der Kommandozeile ausgeht.
///
/// Beides zusammen heisst: Ein Ratschlag „installieren Sie ffmpeg" war
/// falsch. AVFoundation dagegen steckt im System, laeuft im Sandkasten,
/// kodiert ueber VideoToolbox in Hardware und bringt keine
/// GPL-Verpflichtung mit.
///
/// **Bildpunkte kommen als RGBA, AVFoundation will BGRA.** Das Umsortieren
/// macht `vImagePermuteChannels_ARGB8888` - zwei Kanaele tauschen, in
/// einem Durchlauf ueber die ganze Flaeche, statt einer Schleife ueber
/// zwei Millionen Bildpunkte in Swift.
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
// ===== FLUGVIDEO-ENDE =====

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
import Cocoa
import FlutterMacOS
import ImageIO
import UniformTypeIdentifiers

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
            case "videoThumbnail":
                guard
                    let args = call.arguments as? [String: Any],
                    let path = args["path"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "path fehlt", details: nil))
                    return
                }
                let maxDimension = (args["maxDimension"] as? NSNumber)?.intValue ?? 800
                DispatchQueue.global(qos: .userInitiated).async {
                    let thumbnail = videoThumbnail(path: path, maxDimension: maxDimension)
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
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Lädt eine Bilddatei über ImageIO (deckt HEIC/HEIF, DNG/RAW, TIFF-
    /// Sonderfälle usw. ab), skaliert sie ggf. auf maximal [maxDimension] px
    /// (längste Seite) und gibt sie als JPEG-Bytes zurück.
    private static func convertToJpeg(path: String, maxDimension: Int, quality: Double) -> Data? {
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

    private struct VideoThumbnail {
        let jpeg: Data
        let durationSeconds: Double
    }

    /// Extrahiert einen einzelnen Frame aus einer Videodatei über
    /// AVFoundation (behebt das Platzhalter-Icon für Video-Thumbnails in der
    /// Kachelansicht) und liefert gleich die Videolänge mit, da beides über
    /// dasselbe AVAsset ohnehin benötigt wird.
    private static func videoThumbnail(path: String, maxDimension: Int) -> VideoThumbnail? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let rawDuration = CMTimeGetSeconds(asset.duration)
        let durationSeconds = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 0

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)

        // Ein kleines Stück nach dem Start greifen statt exakt Frame 0 – bei
        // vielen Videos ist der allererste Frame schwarz oder unbrauchbar.
        let offsetSeconds = durationSeconds > 0 ? min(0.5, durationSeconds / 2) : 0
        let requestedTime = CMTime(seconds: offsetSeconds, preferredTimescale: 600)

        guard let cgImage = try? generator.copyCGImage(at: requestedTime, actualTime: nil) else {
            return nil
        }
        guard let jpeg = encodeJpeg(cgImage, quality: 0.8) else { return nil }
        return VideoThumbnail(jpeg: jpeg, durationSeconds: durationSeconds)
    }
}

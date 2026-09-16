// Messgeraet: Was AVFoundation aus echten Videos an Standbildern hergibt.
//
// Dieselbe API und dieselben Einstellungen wie ImageConverter.swift -
// AVAssetImageGenerator mit maximumSize und einem Griff 0,5 s nach dem
// Start. Gebraucht, weil im reinen Flutter-Pruflauf auf macOS weder der
// Method-Channel noch ffmpeg zur Verfuegung steht.
//
//   swift tool/messe_standbild.swift 2048 <datei> ...
//
// An 25 echten Videos gemessen:
//   800 Punkte:  23 von 25, 19 ms je Video, lange Kante durchweg 800
//  2048 Punkte:  23 von 25, 26 ms je Video, Median 1744, bis 2048
import AVFoundation
import CoreGraphics
import Foundation

let kante = CGFloat(Int(CommandLine.arguments[1]) ?? 2048)
var gelungen = 0, gescheitert = 0
var kanten: [Int] = []
let start = Date()
for pfad in CommandLine.arguments.dropFirst(2) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: pfad))
    let dauer = CMTimeGetSeconds(asset.duration)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: kante, height: kante)
    let versatz = dauer > 0 ? min(0.5, dauer / 2) : 0
    let zeit = CMTime(seconds: versatz, preferredTimescale: 600)
    if let bild = try? gen.copyCGImage(at: zeit, actualTime: nil) {
        gelungen += 1
        kanten.append(max(bild.width, bild.height))
    } else {
        gescheitert += 1
    }
}
let ms = Int(Date().timeIntervalSince(start) * 1000)
kanten.sort()
print("gelungen \(gelungen), gescheitert \(gescheitert), \(ms) ms "
    + "(\(gelungen > 0 ? ms / (gelungen + gescheitert) : 0) ms je Video)")
if !kanten.isEmpty {
    print("lange Kante: \(kanten.first!) .. \(kanten.last!), Median \(kanten[kanten.count/2])")
}

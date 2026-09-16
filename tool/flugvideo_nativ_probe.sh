#!/bin/bash
# **Der native Videoschreiber, an echtem AVFoundation gemessen.**
#
# `test/flugvideo_nativ_test.dart` stellt den Kanal nach und prueft, was
# Dart hinueberreicht. Was ein gestellter Kanal nicht beantworten kann,
# ist die Frage, ob am Ende eine **abspielbare Datei** steht.
#
# Dieses Skript schneidet die Klasse `Flugvideoschreiber` woertlich aus
# `macos/Runner/ImageConverter.swift` heraus - zwischen den Marken
# FLUGVIDEO-ANFANG und FLUGVIDEO-ENDE - uebersetzt sie einzeln und laesst
# sie ein Video schreiben. Es laeuft also derselbe Quelltext, den die App
# ausliefert, und nicht eine Abschrift davon.
#
#   tool/flugvideo_nativ_probe.sh
set -euo pipefail
cd "$(dirname "$0")/.."
QUELLE=macos/Runner/ImageConverter.swift
ORDNER=$(mktemp -d)
trap 'rm -rf "$ORDNER"' EXIT

{
  echo 'import AVFoundation'
  echo 'import Accelerate'
  echo 'import Foundation'
  sed -n '/===== FLUGVIDEO-ANFANG =====/,/===== FLUGVIDEO-ENDE =====/p' "$QUELLE"
  cat <<'MAIN'

// --- Der Pruefstand ---
let breite = 1920, hoehe = 1080, takt = 30, bilder = 90
let ziel = URL(fileURLWithPath: CommandLine.arguments[1])
let schreiber = try Flugvideoschreiber(
  ziel: ziel, breite: breite, hoehe: hoehe, bilderJeSekunde: takt)

// Etwas, das sich bewegt und Kanten hat - ein Standbild waere auch dann
// klein, wenn die Bilder gar nicht ankaemen. Und die drei Kanaele sind
// verschieden hell, damit ein vertauschtes R/B im Bild auffiele.
var punkte = [UInt8](repeating: 0, count: breite * hoehe * 4)
let uhr = Date()
for i in 0..<bilder {
  let t = Double(i) / Double(bilder - 1)
  let versatz = Int(t * Double(breite))
  for y in 0..<hoehe {
    for x in 0..<breite {
      let p = (y * breite + x) * 4
      let balken = ((x + versatz) / 64) % 2 == 0
      punkte[p + 0] = balken ? 220 : 20            // R
      punkte[p + 1] = UInt8(y * 255 / hoehe)       // G
      punkte[p + 2] = balken ? 20 : 200            // B
      punkte[p + 3] = 255
    }
  }
  try schreiber.bild(Data(punkte))
}
let malzeit = Date().timeIntervalSince(uhr)

let warte = DispatchSemaphore(value: 0)
var grund: String?
schreiber.beende { g in grund = g; warte.signal() }
warte.wait()
if let grund = grund {
  FileHandle.standardError.write("FEHLER: \(grund)\n".data(using: .utf8)!)
  exit(1)
}
let groesse = (try FileManager.default.attributesOfItem(atPath: ziel.path)[.size] as? Int) ?? 0
print(String(format: "%d Bilder in %dx%d: %.1f s, %d kB",
             bilder, breite, hoehe, malzeit, groesse / 1024))
MAIN
} > "$ORDNER/probe.swift"

echo "== uebersetzen =="
swiftc -O -o "$ORDNER/probe" "$ORDNER/probe.swift"

ZIEL=${1:-$ORDNER/probe.mp4}
echo "== laufen lassen =="
"$ORDNER/probe" "$ZIEL"

echo "== ffprobe =="
ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=width,height,codec_name,nb_read_frames,pix_fmt \
  -of default=noprint_wrappers=1 "$ZIEL"

# **Und die Farbkanaele.** AVFoundation will BGRA, Flutter liefert RGBA -
# stuenden im Umsortieren zwei Zahlen falsch, entstuende trotzdem ein
# tadellos abspielbares Video, nur mit vertauschtem Rot und Blau. Kein
# ffprobe-Feld sagt darueber etwas; nur die Bildpunkte selbst.
echo "== Farbkanaele =="
ffmpeg -v error -i "$ZIEL" -frames:v 1 -f rawvideo -pix_fmt rgb24 -y "$ORDNER/erst.raw"
python3 - "$ORDNER/erst.raw" <<'PUNKTE'
import sys
d = open(sys.argv[1], 'rb').read()
W = 1920
def px(x, y):
    o = (y * W + x) * 3
    return tuple(d[o:o + 3])
# Der Pruefstand malt Balken: bei x=10 R=220/B=20, bei x=100 R=20/B=200.
# Ein vertauschtes R/B kehrte beide um - und 220 gegen 20 ist ein
# Unterschied, den keine yuv420p-Rundung erzeugt.
links, rechts = px(10, 540), px(100, 540)
print("x=10  %s   erwartet ~ (220, 128, 20)" % (links,))
print("x=100 %s  erwartet ~ (20, 128, 200)" % (rechts,))
if not (links[0] > 150 and links[2] < 90 and rechts[0] < 90 and rechts[2] > 150):
    print("FEHLER: Rot und Blau stehen vertauscht")
    sys.exit(1)
print("Rot und Blau stehen richtig")
PUNKTE
echo "Datei: $ZIEL"

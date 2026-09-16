# Portierung nach Linux und Windows

Stand: August 2026, Branch `portierung/linux-windows`.

Dieses Dokument hält fest, was für die Portierung bereits vorbereitet ist und
was noch fehlt. Die Arbeit liegt bewusst auf einem eigenen Branch, damit der
macOS-Stand auf `main` unberührt bleibt.

## Leitgedanke

Plattformabhängiger Code liegt gebündelt unter `lib/services/platform/`,
statt als verstreute `Platform.isMacOS`-Abfragen quer durch die App. Jede
Fähigkeit bekommt dort eine Schnittstelle und je Plattform eine Umsetzung.
So bleibt sichtbar, was portiert werden muss – und der Rest der App merkt
von der Plattform nichts.

## Was bereits erledigt ist

| Punkt | Status |
|---|---|
| `linux/`- und `windows/`-Projektgerüst | angelegt (`flutter create --platforms=linux,windows .`) |
| Bibliotheksordner wählen und wiederfinden | abstrahiert, Linux/Windows-Umsetzung vorhanden |
| „Ordner anzeigen" (Dateimanager) | abstrahiert, alle drei Plattformen umgesetzt |
| Prüfung aller Abhängigkeiten auf Plattformunterstützung | abgeschlossen, siehe unten |

### Bibliotheksordner (war der eigentliche Blocker)

`LibraryLocation` lief ausnahmslos über macOS-Security-Scoped-Bookmarks.
Unter Linux/Windows hätte sich damit **kein Bibliotheksordner wählen lassen –
die App wäre schlicht unbenutzbar gewesen.**

Jetzt entscheidet `FolderAccess.forCurrentPlatform()`:

- `folder_access_macos.dart` – Bookmarks über den bestehenden nativen Kanal.
  Die Sandbox entzieht den Zugriff bei jedem Neustart, nur das Bookmark
  stellt ihn wieder her.
- `folder_access_desktop.dart` – Linux/Windows kennen diese Einschränkung
  nicht; dort genügt der gespeicherte Pfad, die Auswahl übernimmt
  `file_picker` mit dem jeweils systemeigenen Dialog.

Bestehende Installationen bleiben lesbar: `currentRoot()` akzeptiert weiter
den alten Schlüssel `bookmark` und schreibt künftig `token`.

## Abhängigkeiten

Geprüft wurde jede Abhängigkeit aus `pubspec.yaml` auf ihre deklarierten
Plattformen.

**Unterstützen Linux und Windows:** `flutter_onnxruntime` (alle KI-Funktionen),
`sqlite3`, `drift`, `path_provider`, `file_picker`, `share_plus`,
`flutter_map`, `photo_view` sowie sämtliche reinen
Dart-Pakete (`image`, `exif`, `crypto`, `cryptography`, `archive`, `xml`,
`fl_chart`, `panorama_viewer`, `flutter_cube`, `flutter_earth_globe`, …).

**Der einzige Paket-Blocker ist beseitigt:** `video_player` unterstützte
nur Android/iOS/macOS/Web und ist inzwischen vollständig durch `media_kit`
ersetzt, das alle sechs Plattformen abdeckt (siehe Phase 1 in
[plan_linux.md](plan_linux.md)). Damit unterstützt **jede** Abhängigkeit
des Projekts Linux und Windows.

## Was noch fehlt

### 1. Native Bildverarbeitung

`macos/Runner/ImageConverter.swift` stellt sechs Funktionen bereit, die es
unter Linux/Windows noch nicht gibt. Der Dart-Wrapper
(`native_image_converter.dart`) ist bereits abgesichert: außerhalb von macOS
liefert jede Methode `null`, statt zu scheitern. Die App startet und läuft
also – nur diese Funktionen fehlen.

| Funktion | Folge ohne Umsetzung | Möglicher Weg |
|---|---|---|
| `convertToJpeg` | HEIC/RAW ohne Vorschaubild, nicht anzeigbar | `libheif` / `libraw` per FFI, oder externes Werkzeug |
| `developImage` | „Entwickeln" wirkungslos | Basisregler in Dart über `image`; RAW braucht `libraw` |
| `videoThumbnail` | Videos ohne Vorschaubild | ffmpeg |
| `trimVideo` | Videoschnitt nicht verfügbar | ffmpeg |
| `recognizeText` | keine Texterkennung (OCR) | Tesseract, oder ein ONNX-OCR-Modell über die bereits vorhandene ONNX-Runtime |

JPG/PNG/WebP/GIF/BMP/TIFF funktionieren unabhängig davon überall, da sie
das reine Dart-Paket `image` abdeckt.

**Empfohlene Reihenfolge:** zuerst `convertToJpeg` (ohne HEIC bleiben
iPhone-Fotos unsichtbar – das trifft am meisten Nutzer), dann
`videoThumbnail`, danach der Rest.

### 2. Noch nicht geprüft

- **Bauen und Starten** auf echten Linux-/Windows-Systemen. Von macOS aus
  lässt sich das nicht erzeugen; `flutter analyze` und die Testsuite laufen
  sauber, das ersetzt aber keinen echten Build.
- **Dateipfade:** Windows nutzt `\` als Trennzeichen und kennt
  Laufwerksbuchstaben. Der Code verwendet durchgängig `package:path`, was
  das abfangen sollte – bestätigt ist es noch nicht.
- **Verschlüsselter Ordner:** rein Dart-basiert (AES-256-GCM), sollte
  plattformunabhängig funktionieren, ungetestet außerhalb von macOS.
- **Groß-/Kleinschreibung:** Linux unterscheidet sie bei Dateinamen,
  macOS und Windows üblicherweise nicht – relevant für die
  Duplikaterkennung über Dateinamen.

## Prüfen

```bash
flutter analyze                       # läuft sauber
flutter test                          # läuft sauber (ein bekannt flakiger Timing-Test)
flutter build linux                   # nur auf einem Linux-System
flutter build windows                 # nur auf einem Windows-System
```

# Umsetzungsplan Linux (voller Funktionsumfang)

Stand: August 2026, Branch `portierung/linux-windows`.
Voraussetzung: die Vorbereitung aus [portierung_linux_windows.md](portierung_linux_windows.md)
ist erledigt (Projektgerüst, Ordnerauswahl, Dateimanager).

Ziel dieses Plans: **Funktionsgleichheit mit der macOS-Fassung**, nicht nur
Lauffähigkeit.

## Die Lücke in Zahlen

Sieben Fähigkeiten fehlen unter Linux. Sechs stammen aus
`macos/Runner/ImageConverter.swift`, eine aus einem Paket:

| # | Fähigkeit | Heute (macOS) | Ohne Umsetzung fehlt |
|---|---|---|---|
| 1 | ~~Videowiedergabe~~ | ~~`video_player`~~ | **erledigt** – jetzt `media_kit` |
| 2 | HEIC/RAW → JPEG | ImageIO | alle iPhone-Fotos und RAW-Dateien unsichtbar |
| 3 | RAW-Entwicklung | CIRAWFilter / Core Image | „Entwickeln" wirkungslos |
| 4 | Video-Vorschaubild | AVFoundation | Videos ohne Thumbnail |
| 5 | Video-Zuschnitt | AVFoundation | Funktion nicht verfügbar |
| 6 | Texterkennung (OCR) | Vision | keine Textsuche in Fotos |
| 7 | Objektivkorrektur | CIRAWFilter | Teil von (3) |

## Grundsatzentscheidung: Systembibliotheken statt Eigenbau

Unter Linux gibt es für jede dieser Aufgaben eine etablierte Bibliothek.
Zwei Wege stehen offen:

**A – Kommandozeilenwerkzeuge aufrufen** (`heif-convert`, `dcraw_emu`,
`ffmpeg`, `tesseract`). Schnell umgesetzt, robust, aber die App hängt an
installierten Fremdprogrammen.

**B – Bibliotheken per Dart FFI einbinden** (`libheif`, `libraw`,
`libavcodec`, `libtesseract`). Kein Prozessstart je Bild, feinere Kontrolle,
aber deutlich mehr Aufwand: Für keine dieser Bibliotheken existiert ein
brauchbares fertiges Dart-Paket (geprüft – `heic_to_png_jpg` fällt auf
Desktop auf das Dart-`image`-Paket zurück und kann HEIC dort gerade nicht).
Ein eigener FFI-Wrapper je Bibliothek wäre nötig.

**Empfehlung: A, ausgeliefert als Flatpak.** Der Einwand gegen A – die
Fremdabhängigkeiten – verschwindet, sobald die App als Flatpak
ausgeliefert wird: dort werden `ffmpeg`, `libheif`, `tesseract` und
`libmpv` mit ins Bundle gepackt und sind garantiert vorhanden. Man bekommt
den geringen Aufwand von A ohne dessen Nachteil. FFI bleibt später als
Optimierung möglich, ohne dass sich die Schnittstelle ändert.

## Phasen

Reihenfolge nach Nutzen: Was die meisten Fotos betrifft, kommt zuerst.

### Phase 0 – Bauen und starten — **ERLEDIGT, auf echter Hardware**

Am 20.08.2026 auf einer frisch aufgesetzten **Ubuntu 26.04** (x86_64,
12 Kerne, GNOME/Wayland) durchgeführt. Alles der Reihe nach durchgelaufen:
`flutter pub get`, `dart run build_runner build`, `flutter analyze` ohne
Befund, `flutter build linux --debug` **auf Anhieb erfolgreich**.

Die App startet, legt `~/.local/share/com.example.photo_vault/PhotoVault/`
mit Datenbank und Ordnerstruktur an (drift und das gebündelte SQLite
funktionieren also), registriert `media_kit_libs_linux` und zeigt die
Oberfläche vollständig: Navigationsleiste, leerer Bibliothekszustand,
Importknopf, deutsche Texte, dunkles Thema.

**Die Testsuite läuft auf Linux durch:** 1089 Tests, alle grün, 9
übersprungen. Übersprungen sind ausschliesslich die Goldbild-Vergleiche –
sie prüfen Pixel gegen auf macOS erzeugte Referenzen, und Linux rastert
Schrift anders. Vor dieser Änderung waren das die einzigen 9 Fehlschläge
des gesamten Laufs; kein einziger Sachtest fiel durch (siehe
`test/goldbilder.dart`).

**Drei Funde, die ohne echte Maschine nicht zu haben waren:**

1. **`git` fehlte in der Bereitschaftsprüfung.** Ohne git bricht das
   `flutter`-Kommando sofort ab, noch bevor irgendetwas übersetzt wird –
   auf einer frischen Ubuntu-Installation ist git nicht dabei.
2. **`heif-convert` allein reicht nicht für HEIC** – siehe Phase 2.
3. **Ein Flutter-Fenster erscheint erst mit dem ersten gerenderten Bild**
   (`first_frame_cb` im Runner). Unter Xvfb kommt keins, weil dort kein
   brauchbares OpenGL zur Verfügung steht; eine leere `flutter
   create`-App verhält sich identisch, es liegt also nicht an dieser
   Anwendung. Für die Fernprüfung heisst das: in der laufenden
   GNOME-Sitzung starten (`XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`,
   `WAYLAND_DISPLAY` bzw. XWayland-Cookie aus
   `/run/user/1000/.mutter-Xwaylandauth.*`), nicht unter Xvfb.

### Phase 0 – ursprüngliche Anleitung

**Auf der Linux-Maschine als Erstes ausführen:**

```bash
tool/linux_setup_check.sh
```

Das Skript prüft Bau-Voraussetzungen (Flutter, clang, cmake, ninja,
pkg-config, GTK 3, **libmpv-dev**) und Laufzeit-Werkzeuge (ffmpeg,
heif-dec, dcraw_emu) und nennt zu jedem fehlenden Stück den
Installationsbefehl. Fehlende Laufzeit-Werkzeuge verhindern den Build
nicht – sie kosten nur einzelne Funktionen.

`libmpv` steht bewusst oben bei den Bau-Voraussetzungen: `media_kit_video`
sucht beim Bauen über pkg-config danach, und ohne die Entwicklungsdateien
bricht CMake ab, bevor irgendetwas übersetzt wird. Bis Prüfrunde 12 stand
es unten und wurde am Programm `mpv` geprüft – eine Maschine mit dem
Programm, aber ohne `libmpv-dev`, kam durch und scheiterte dann am Bau.

Auf Debian/Ubuntu meist in einem Rutsch:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
                 libmpv-dev mpv ffmpeg libheif-examples libraw-bin
```

Danach:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d linux
```

**Worauf beim ersten Start zu achten ist:**

1. Startet die App und erscheint die Timeline?
2. Lässt sich unter Einstellungen → Speicherort ein Ordner wählen? (Das
   war der ursprüngliche Blocker, jetzt über `folder_access_desktop.dart`.)
3. Importieren JPG/PNG samt Thumbnail?
4. Spielt ein Video ab? (media_kit, braucht libmpv)
5. Erscheint bei HEIC/RAW ein Vorschaubild? (braucht heif-convert bzw.
   dcraw_emu, siehe Phase 2)

Erwartete Stolpersteine: Pfadtrennzeichen, die sqlite3-Bibliothek und
Groß-/Kleinschreibung bei Dateinamen (Linux unterscheidet sie, macOS
üblicherweise nicht).

### Phase 1 – Videowiedergabe (`media_kit`) — **ERLEDIGT**

`video_player` ist vollständig durch `media_kit` ersetzt. Da dieses alle
sechs Plattformen abdeckt, war keine plattformabhängige Variante nötig –
es gibt weiterhin genau eine Wiedergabe-Implementierung.

Umgesetzt in `lib/widgets/video_playback.dart`:
`VideoPlaybackController` (öffnen, abspielen, pausieren, spulen,
Dauerschleife, Dauer, Seitenverhältnis), `VideoSurface` (Bildausgabe) und
`VideoProgressBar` – letztere ersetzt `VideoProgressIndicator`, für das es
bei `media_kit` keine Entsprechung gibt.

Angepasst: `asset_viewer_screen.dart`, `video_trim_screen.dart`,
`live_photo_view.dart`; `MediaKit.ensureInitialized()` in `main.dart`.

Auf macOS real gegen ein Video aus der Bibliothek geprüft: Öffnen in
457 ms, korrekte Dauer (31,96 s) und Seitenverhältnis, Position läuft in
Echtzeit weiter, 29,9 % nicht-schwarze Pixel (es wird also wirklich Bild
gerendert, nicht nur Ton), Pausieren und Zurückspulen funktionieren.

Die Plugin-Registrierung für Linux (`media_kit_libs_linux`) und Windows
(`media_kit_libs_windows_video`) ist erzeugt, dort aber **noch ungetestet**
– unter Linux wird zusätzlich `libmpv` gebraucht (im Flatpak zu bündeln).

Nebeneffekt: Das Projekt nutzt für macOS/iOS jetzt CocoaPods statt Swift
Package Manager, da `media_kit` nur damit ausgeliefert wird.

### Phase 2 – HEIC und RAW lesbar machen — **AUF LINUX VERIFIZIERT**

Beide Wege gegen echte Dateien geprüft
(`test/linux_werkzeuge_echt_test.dart`), beide grün:

* **HEIC** – eine echte HEIC-Datei wird umgewandelt, auf die längste
  Kante skaliert, und über zwei Farbflächen ist belegt, dass wirklich
  dieses Bild herauskam und nicht irgendeines.
* **RAW** – eine echte iPhone-DNG (CC0, raw.pixls.us) wird entwickelt und
  skaliert. Der Test prüft zusätzlich, dass die Eingabedatei unverändert
  bleibt und im Ordner daneben nichts liegen bleibt: `dcraw_emu` schreibt
  sein Ergebnis NEBEN die Eingabe, und genau dafür wird vorher in den
  Temp-Ordner kopiert. Ohne das läge in der Bibliothek zu jedem RAW eine
  36-MB-TIFF-Datei, die niemand bestellt hat. Der angenommene
  Ausgabename (`<eingabe>.tiff`, also angehängt statt ersetzt) stimmt.

Der Weg dorthin führte über einen Fund, der die Paketliste betraf – der
Code selbst war richtig:

**`libheif-examples` allein reicht nicht.** Auf Ubuntu 26.04 mit
installiertem `libheif-examples` scheitert **jede** HEIC-Datei:

```
$ heif-convert probe.heic out.jpg
File contains 1 image
Could not decode image: Decoder plugin generated an error: Unspecified
```

Der Grund steht in `heif-convert --list-decoders`: Unter „HEIC decoders"
steht nichts. libheif liefert die Codecs seit 1.20 als eigene
Plugin-Pakete, und Ubuntu installiert von Haus aus nur die AV1-Plugins –
für HEVC, also genau das, was in jeder iPhone-Datei steckt, ist keines
dabei.

**Nötig ist zusätzlich `libheif-plugin-libde265`** (oder
`libheif-plugin-ffmpegdec`). Die Bereitschaftsprüfung testet das jetzt
nicht mehr über „ist das Programm da", sondern über die tatsächlich
gemeldeten Dekoder – „heif-convert ist installiert" hätte grün gemeldet
und jedes iPhone-Foto wäre unsichtbar geblieben.

Für das Flatpak (Phase 6) heisst das: das Dekoder-Plugin gehört
ausdrücklich mit ins Bundle.

### Phase 2 – Umsetzung (unverändert gültig)

Umgesetzt in `lib/services/platform/linux_image_tools.dart`:

- **HEIC/HEIF:** `heif-convert` (Paket `libheif-examples`)
- **RAW:** `dcraw_emu` aus LibRaw (Paket `libraw-bin`), Ausgabe als TIFF

Beide schreiben in einen temporären Ordner, der anschließend immer
aufgeräumt wird; das Verkleinern übernimmt das `image`-Paket in einem
Isolate (`compute`), damit die UI nicht blockiert. Die RAW-Datei wird
vorher in den Temp-Ordner kopiert, weil `dcraw_emu` sonst neben das
Original schreiben würde – die Bibliothek bleibt unangetastet.

`NativeImageConverter` bleibt die einzige Anlaufstelle und verzweigt
intern nach Plattform; die 11 Aufrufstellen in der App sind unverändert.

**Noch offen:** `developImage` (die Entwickeln-Regler) hat unter Linux
weiterhin keine Entsprechung – dafür braucht es Phase 3 als maßgeblichen
Renderpfad. Ebenso die HDR-Gain-Map-Behandlung aus `convertHdrAwareJpeg`:
Das Bild wird korrekt angezeigt, nur ohne HDR-Feinheiten.

### Phase 3 – Entwickeln — **MASSGEBLICHER RENDERPFAD STEHT**

`lib/services/develop_render.dart` rendert die Anpassungen über denselben
Shader in fertige JPEG-Bytes; `NativeImageConverter.developImage` nimmt
diesen Weg überall ausser auf macOS. Vorher wirkten die Entwickeln-Regler
dort auf gar nichts – es war der einzige Regler-Satz der App, der auf
manchen Plattformen schlicht wirkungslos blieb.

Umgesetzt: Belichtung, Weissabgleich, Kontrast, Schatten, Tonwertkurve,
Farbmischer – und **Masken**. Die Maskenkomposition entsteht auf der
Leinwand statt in Core Image: je Schicht die angepasste Fassung des ganzen
Bildes zeichnen und mit der Maske als Alphakanal (`BlendMode.dstIn`)
wieder wegnehmen, was ausserhalb liegt. Reihenfolge wie auf macOS.

Der Farbwürfel läuft hier mit der vollen Kantenlänge (`colorCubeSize`, 32)
statt der gröberen der Live-Vorschau (16) – das gespeicherte Ergebnis ist
also genauer als das, was beim Ziehen zu sehen war, nicht ungenauer.

**Eine Stelle für beide Wege:** `setzeDevelopUniforms` belegt die Uniforms
für Vorschau und Ergebnis gemeinsam. Zwei Fassungen davon wären die
naheliegendste Art, dass beides auseinanderläuft, ohne dass es auffällt.

**Vier Regler bleiben ohne Wirkung** – Schärfe, Rauschunterdrückung,
Klarheit, Vignettierung. Die ersten beiden brauchen Nachbarpixel, die ein
Fragment-Shader so nicht sieht; die anderen beiden sind reine
Core-Image-Filter. Sie zu nähern wäre schlechter, als sie zu benennen: Im
Entwickeln-Bedienfeld sind sie ausserhalb von macOS **abgeschaltet**, mit
einer Zeile darunter, die den Grund nennt. Ein Regler, der sich bewegen
lässt und nichts tut, ist die unangenehmste Art von Fehler.

**Was noch offen ist:** Die Abweichung des Shaders vom nativen Render ist
für die Live-Vorschau gemessen (Tabelle unten) – für den gespeicherten
Weg **nicht neu gemessen**, weil der native Pfad über einen
Plattform-Kanal läuft, den ein Unit-Test nicht bedienen kann. Die
Rechnung ist dieselbe, die Zahlen sollten also übertragbar sein; belegt
ist das nicht. Besonders die 6,1 % bei 3200 K wiegen jetzt schwerer als
vorher: In der Vorschau waren Temperatur und Tint deshalb ausgenommen –
im gespeicherten Bild lassen sie sich nicht ausnehmen. Eine Messung im
laufenden Programm (Integrationstest auf macOS) wäre der nächste Schritt.

### Phase 3 – Live-Vorschau (Vorgeschichte)

`shaders/develop_adjustments.frag` bildet Belichtung, Weißabgleich,
Kontrast und Schatten in GLSL nach – die portable Entsprechung zu
`applyNonRawAdjustments`. Angebunden über
`lib/widgets/develop_preview.dart`.

**Rolle heute:** Live-Vorschau während des Regler-Ziehens. Maßgeblich für
das gespeicherte Ergebnis bleibt der native Renderpfad – bei RAW wirken
die Regler dort auf den Rohdaten (CIRAWFilter beim Demosaicing), was
deutlich mehr Spielraum hat als eine nachträgliche Korrektur.

**Real gemessene Abweichung** vom nativen Render (mittlere Helligkeit
desselben Fotos):

| Einstellung | Abweichung |
|---|---|
| neutral | 0,1 % |
| Belichtung +1 EV | 0,1 % |
| Kontrast +0,5 | 1,3 % |
| Temperatur 3200 K | 6,1 % |
| Temperatur 9000 K | 0,4 % |

Wegen der Abweichung beim warmen Weißabgleich sind **Temperatur und Tint
von der Live-Vorschau ausgenommen** (`liveVorschau: false` am jeweiligen
Regler): Gerade dort beurteilt man die Farbe, eine genäherte Vorschau
würde zu falschen Einstellungen verleiten.

Ebenfalls nicht im Shader: Schärfe und Rauschunterdrückung (brauchen
Nachbarpixel bzw. echte Entrauschung) sowie Masken – bei vorhandenen
Masken bleibt es beim nativen Render, da die neutrale Basis keine
Maskenwirkung enthält.

**Für Linux bleibt zu tun:** den Shader vom Vorschau- zum maßgeblichen
Renderpfad machen (dort gibt es kein Core Image), inklusive Schärfe,
Rauschunterdrückung und Maskenkomposition, gespeist aus einem per LibRaw
dekodierten Bild (Phase 2).

### Phase 4 – Video-Vorschaubild und -Zuschnitt — **AUF LINUX VERIFIZIERT**

Gegen echte, mit ffmpeg erzeugte Videos geprüft
(`test/linux_werkzeuge_echt_test.dart`), beides grün:

* **Vorschaubild und Länge** – 320 px breites JPEG aus einem
  640x480-Video, Länge 4,0 s korrekt ermittelt, und der Frame ist
  nachweislich nicht schwarz (genau der Fall, gegen den die
  Sekunde-1-Regel eingebaut wurde).
* **Verlustfreier Zuschnitt** – aus 10 s die Spanne 2–6 s geschnitten,
  Ergebnis 4 s (±1,2 s Toleranz für den Schlüsselbild-Abstand). Die
  Reihenfolge von `-ss`/`-to` vor `-i` stimmt also; eine falsche hätte
  hier die volle Länge oder fast nichts ergeben.

### Phase 4 – Umsetzung (unverändert gültig)

Ebenfalls in `linux_image_tools.dart`:
- Vorschaubild: `ffmpeg` extrahiert einen Frame bei Sekunde 1 (nicht bei 0
  – der allererste Frame ist bei vielen Videos schwarz) und skaliert dabei
  gleich mit
- Länge: `ffprobe`
- Zuschnitt: `ffmpeg -c copy`, also verlustfrei ohne Neukodierung –
  entspricht dem nicht-destruktiven Verhalten unter macOS

### Phase 5 – Texterkennung — **UMGESETZT, auch unter Linux (Fremdfehler umgangen)**

`lib/services/ocr_service.dart` setzt die Empfehlung um: zwei ONNX-Modelle
aus der PaddleOCR-Familie statt eines Systempakets, nachladbar über den
bestehenden Katalog (`ocr_ppocr_latin`, zusammen 13,7 MB). Erst finden
(DBNet), dann lesen (CRNN mit CTC).

**Gegen die echten Modelle belegt** – auf macOS über
`integration_test/ocr_test.dart`, an einer deutschen Testtafel:

```
öffnungszeiten
Straße des 17. Juni 135
Preis: 12,50 EUR
GrúBe aus Köln
```

177 ms für das ganze Bild, 95,5 % der Zeichen richtig, zwei von vier
Zeilen fehlerfrei. Umlaute und `ß` kommen durch – deshalb die
**lateinische** Zeichentabelle: Die chinesische kennt weder `ö` noch `Ä`,
`Ö`, `ß` oder `€`, aus „Straße" wäre „Strae" geworden.

**Unter Linux liest das Modell nichts.** Die Ursache ist gefunden und
auf einen einzigen Rechenschritt eingegrenzt: **`HardSwish` liefert im
Flutter-Prozess unter Linux durchweg null.**

Der Weg dorthin, weil die Zwischenstände täuschen:

* Ein Modell mit **allen 233 Zwischenausgaben** zeigt die Bruchstelle
  auf die Zeile genau. `Conv` stimmt (−14,3852 auf beiden Systemen),
  `BatchNormalization` stimmt (−8190,3269 gegen −8190,3271), der
  darauffolgende `HardSwish` liefert unter Linux **0,0000** statt
  14806,0702. Alles danach ist Folgeschaden – daher der Eindruck, die
  Eingabe käme nicht an.
* **Kleinstfassung:** ein Modell mit genau einem Knoten. `HardSwish`
  gibt für `[−4, −3, −1, −0,5, 0, 0,5, 1, 3]` acht Nullen zurück statt
  `[−0, −0, −0,333, −0,208, 0, 0,292, 0,667, 3]`.
* **Nur dieser eine Schritt.** `HardSigmoid`, `Sigmoid`, `Relu`, `Elu`,
  `Softplus`, `Celu` und `Mish` rechnen im selben Prozess richtig – auch
  `Celu` und `Mish`, die wie `HardSwish` in ONNX als Funktion definiert
  sind. Es liegt also nicht an der Funktionsdefinition.
* **Nicht das Plugin.** Eine vollständig eigenständige C++-Inferenz
  *innerhalb* des Flutter-Prozesses – eigene Umgebung, eigene Sitzung,
  eigener Tensor, keine Zeile Plugin-Code – liefert denselben Fehlwert.
  Umgekehrt rechnet ein **Kindprozess derselben App**, im selben
  Augenblick abgespalten, richtig.
* **Nicht unsere App.** Eine blanke `flutter create`-App mit nichts
  weiter als `flutter_onnxruntime` zeigt den Fehler ebenso.
* **Ausgeschlossen:** Ladereihenfolge und Symbolüberlagerung (alle 272
  Bibliotheken des Prozesses in die Sonde vorgeladen, auch ORT zuletzt –
  ohne Wirkung), Rechenfäden (auch mit einem Faden und serieller
  Ausführung), Speichermuster, Vorpacken der Gewichte, Graphoptimierung
  (auch ganz abgeschaltet), ORT-Fassung (1.22.0 und 1.23.0 gleich),
  Tensorgrösse (schon ein einzelner Wert schlägt fehl), Fadenzustand
  (frischer Faden gleich falsch, MXCSR unauffällig bei 0x1fa0),
  Umgebungsvariablen und Grenzen (der Kindprozess erbt sie und rechnet
  richtig).

Warum ein einzelner Rechenschritt nur in einem bestimmten Adressraum
falsch rechnet, lässt sich von aussen nicht weiter aufklären – dazu
braucht es ONNX Runtime mit Symbolen. Die Reproduktion liegt unter
`docs/hardswish_fehler/` und ist klein genug, um sie zu melden.

> **Nachtrag 24.08.2026 – aufgelöst, und einer der Schlüsse oben war
> falsch.** Es lag sehr wohl an der Funktionsdefinition: ONNX (≤ 1.22)
> liest deren Rümpfe als **Text**, mit einem locale-abhängigen
> `std::stof`. GTK setzt die Prozess-Locale aus der Umgebung, und unter
> `de_DE` wird HardSwishs α = 1/6 zu 0.
>
> Der Umkehrschluss „`Celu` und `Mish` sind auch Funktionen und stimmen,
> also liegt es nicht daran" ging fehl, weil deren Rümpfe **keine
> gebrochene Konstante** enthalten. Und „nur in einem bestimmten
> Adressraum" war die richtige Beobachtung mit der falschen Erklärung:
> Der Kindprozess rechnete nicht wegen des Adressraums richtig, sondern
> weil er GTK nie startete und damit unter `C` blieb.
>
> Behoben im Plugin ab `flutter_onnxruntime` 1.8.4. Einzelheiten,
> Messwerte und die Verweise nach oben: `docs/hardswish_fehler/`.

**Warum das Findemodell trotzdem läuft:** Es benutzt `Relu` und `Clip`,
kein `HardSwish`. An einem echten Bild geprüft: Summe 13629,77 gegen
13629,78 auf macOS, gleiche Zahl gefundener Punkte (13702). Der Fehler
trifft ausschliesslich das Lesemodell, dessen MobileNetV3-Stamm
27 `HardSwish`-Knoten enthält.

**Umgangen, und zwar exakt.** `HardSwish(x)` ist nichts anderes als
`x · HardSigmoid(x; α = 1/6, β = 0,5)`, und beide Schritte rechnen
richtig. `lib/services/onnx_hardswish.dart` schreibt die 27 Knoten beim
ersten Laden entsprechend um; `OcrService` legt die umgebaute Fassung
neben das heruntergeladene Modell, das selbst unangetastet bleibt (seine
Prüfsumme ist die Garantie). Der Umbau zerlegt die Datei in ihre Felder
und übernimmt alles ausser der Knotenliste **byteweise** – Gewichte und
Formen werden nicht neu kodiert.

Gegengerechnet mit `onnxruntime` an zufälligen Eingaben bei den Breiten
160, 320 und 640: **grösste Abweichung 0,000** – nicht „nah dran",
sondern dieselben Zahlen. Und am Ende zählt das Ergebnis auf der
Zielmaschine:

```
öffnungszeiten
Straße des 17. Juni 135
Preis: 12,50 EUR
GrúBe aus Köln
```

Dieselben vier Zeilen wie auf macOS, 472 ms. Die Meldung an das Plugin
bleibt trotzdem sinnvoll – die Umgehung hilft nur diesem einen Modell,
nicht jedem anderen mit MobileNetV3-Stamm.

**Kein stiller Datenschaden:** Findet die Erkennung Schrift, liefert aber
keine einzige lesbare Stelle, wirft der Dienst `LesungLiefertNichts`
statt ein leeres Ergebnis zurückzugeben. Ohne das würden die Fotos als
durchsucht vermerkt und nach einer Reparatur nie wieder angefasst.

**Auf macOS bleibt es bei Apples Vision-Framework:** dort besser, ohne
Download, bereits eingebaut. Zwei Wege sind hier kein Versäumnis, sondern
die Entscheidung, auf jeder Plattform das Beste zu nehmen, was sie hat.

### Phase 5 – ursprüngliche Abwägung

Zwei Wege:
- **`tesseract`** – ausgereift, viele Sprachen, ein weiteres Systempaket
- **ONNX-OCR-Modell** – die ONNX-Runtime ist bereits eingebunden und
  unterstützt Linux; das Modell ließe sich über den bestehenden
  Modellkatalog nachladen, ganz ohne Systemabhängigkeit, und würde auf
  **allen** Plattformen gleich funktionieren

Empfehlung: das ONNX-Modell, passend zur bestehenden Architektur
(„nichts wird mitgeliefert, alles nachladbar"). Tesseract nur, falls die
Erkennungsqualität nicht reicht.

### Phase 6 – Paketierung — **UMGESETZT**

`packaging/flatpak/` enthält Bauplan, Desktop-Eintrag, AppStream-Metadaten
und Startskript; `tool/flatpak_bauen.sh` baut, spielt ein und prüft nach.
Laufzeit ist **GNOME 49** (48 ist seit März abgekündigt). Ergebnis: 58,3 MB
über der Laufzeit, mit genau fünf Einträgen in `/app/bin`.

**Was mitgeliefert wird und warum:**

| Baustein | wofür | warum nicht aus der Laufzeit |
|---|---|---|
| libde265 | HEVC-Dekoder für libheif | fehlt dort ganz |
| libheif 1.23.1 | `heif-convert` | die Laufzeit hat die Bibliothek, aber nicht das Werkzeug |
| LibRaw 0.22.2 | `dcraw_emu` | fehlt ganz |
| libass, libplacebo, mpv | `libmpv.so` für media_kit | fehlen ganz |
| zenity | Ordnerauswahl | `file_picker` startet es als eigenen Prozess |

**Kein eigener ffmpeg-Bau.** Der Plan ging davon aus, ffmpeg gehöre ins
Bündel, weil Flatpak-Laufzeiten HEVC und H.264 aus Patentgründen
weglassen. Im Sandkasten nachgemessen stimmt das für GNOME 49 nicht:
`ffmpeg` und `ffprobe` sind da, beide Dekoder ebenso. Ein eigener Bau
hätte eine Viertelstunde Bauzeit und ein paar Megabyte gekostet, ohne
etwas hinzuzufügen.

**Der Dekoder ist fest einkompiliert**, nicht nachladbar
(`ENABLE_PLUGIN_LOADING=OFF`). Ein Plugin müsste zur Laufzeit gefunden
werden; einkompiliert kann es nicht fehlen. Genau daran war der erste
Versuch auf echter Hardware gescheitert.

**AVIF war beinahe verlorengegangen.** libheif brach ab, weil das SDK eine
`AOMConfig.cmake` mitbringt, die auf nicht installierte Dateien zeigt. Der
naheliegende Griff wäre gewesen, AOM abzuschalten und weiterzugehen – dann
hätte das Paket `.avif` und `.avifs` nicht mehr lesen können, die beide in
`lib/services/asset_format.dart` stehen. Mit `dav1d` (liegt sauber als
pkg-config-Modul bereit) bleiben sie lesbar.

**„Vorhanden" ist nicht „läuft".** Der erste Bau legte unter
`/app/bin/dcraw_emu` das libtool-Hüllskript ab statt des Programms.
`which` war zufrieden; beim Aufruf versuchte es, sich selbst zu übersetzen,
und scheiterte am schreibgeschützten `/app`. Behoben mit `libtool
--mode=install`, und die Prüfung im Bauskript ruft die Werkzeuge seither
auf, statt sie nur zu suchen.

**Und „läuft" muss auch geprüft werden, wie es gemeint ist.** Beim
Aufräumen der überzähligen Beispielprogramme flog `heif-dec` mit – seit
libheif 1.23 ist `heif-convert` nur noch ein Verweis darauf. Das Paket
konnte danach keine HEIC-Fotos mehr öffnen. Die verschärfte Prüfung
**meldete es trotzdem grün**: Sie suchte nach „not found", bwrap sagt aber
„No such file or directory". Zwei Lehren in einem Fehlschlag – erst die
Prüfung, die auf Rückgabewert *und* Meldung achtet, hat es gefangen.

**Belegt auf echter Hardware:**

```
heif-convert probe.heic → JPEG geschrieben   (HEVC in HEIF, mit sips erzeugt)
ffprobe probe_hevc.mp4  → 3.000000 Sekunden
ffmpeg  -ss 1 …         → Einzelbild als JPEG
ffmpeg  -ss 0.5 -to 2 -c copy → 12439 Bytes, ohne Neukodierung
```

Und die App selbst: Fenster 2664×1638, `media_kit_libs_linux registered`,
volle Datenablage unter `~/.var/app/…` angelegt, `library.sqlite` mit
**user_version 45** und 30 Tabellen – aus einem gelöschten Datenordner neu
erzeugt, die Migrationen laufen im Sandkasten also von null durch.

Ein Bildschirmfoto gibt es nicht: GNOME 49 verweigert den
Screenshot-Dienst über D-Bus, und wurzelloses Xwayland liefert bei
`x11grab` nur Schwarz. `xwd` und ImageMagick fehlen auf der Maschine und
liessen sich ohne `sudo` nicht nachinstallieren.

**Rechte:** `--filesystem=home` samt `/media`, `/run/media` und den
gvfs-Pfaden – ohne die letzten beiden wäre eine Bibliothek auf einer
Netzfreigabe, die der Dateimanager eingehängt hat, im Sandkasten schlicht
nicht vorhanden (Shotwell führt sie aus demselben Grund). Über das
Dateiportal ginge nur die Auswahl, nicht das fortlaufende Lesen tausender
Dateien im gewählten Bibliotheksordner.

Zum Vergleich, an den Flathub-Angaben abgelesen: digiKam verlangt dasselbe
(`home`, `/media`, `/run/media`), darktable sogar `host` – also das ganze
Dateisystem. Shotwell kommt mit `xdg-pictures` aus, kann dafür aber auch
keine frei gewählte Bibliothek irgendwo im Heimatordner.

**Was der Heimatordner nicht einschliesst:** `~/.ssh`, `~/.gnupg` und
`~/.local/share/keyrings` sind ausdrücklich ausgenommen
(`--nofilesystem=…`). Eine Fotoverwaltung hat dort nichts zu suchen, und
die Bildparser im Bündel – libheif, libde265, LibRaw – packen fremde
Dateien aus und sind ein beliebtes Angriffsziel. Nachgemessen: Im
Sandkasten ist `~/.ssh` ein leerer Ordner, draussen liegt eine Datei darin;
`~/Bilder` bleibt lesbar. In der Ausgabe von `flatpak info
--show-permissions` tauchen die Ausnahmen **nicht** auf – sie stehen in den
Metadaten als `!~/.ssh` und sind nur dort zu sehen.

**Aus der zehnten Prüfrunde nachgezogen:**

* Die **Fensterklasse** hiess `com.example.photo_vault`, der Starter
  erwartete `photo_vault` – beides falsch. Damit ordnet die Arbeitsumgebung
  das Fenster keinem Starter zu: kein Symbol, kein Name in der Leiste. Jetzt
  heissen Kennung, Starter und Fensterklasse einheitlich
  `com.example.PhotoVault`, gegengemessen mit `xwininfo`.
* Das **Flutter-Programm war ungehärtet** – RELRO nur teilweise, keine
  sofortige Bindung, kein Stapelschutz –, während alle selbst gebauten
  Bibliotheken beides hatten. Die Vorlage von `flutter create` macht dazu
  keine Angaben. Mit `-fstack-protector-strong`, `_FORTIFY_SOURCE=2` und
  `-Wl,-z,relro,-z,now` in `linux/CMakeLists.txt` gemessen behoben.
* **zenity 4.0.5 → 4.2.2** und ein **512er-Symbol** dazu; bisher gab es nur
  256 Pixel, was auf grossen Anzeigen sichtbar unscharf wird.

**Offen:** Die Kennung `com.example.PhotoVault` ist ein Platzhalter und im
Bauplan als solcher vermerkt – vor einer öffentlichen Verteilung gehört
dort eine eigene Domäne hin, an vier Stellen. Ergänzend wären `.deb` oder
AppImage denkbar; dann müssen die Abhängigkeiten als Paketabhängigkeiten
deklariert werden.

## Reihenfolge auf einen Blick

```
Phase 0  bauen/starten            ERLEDIGT auf Ubuntu 26.04, Suite grün
Phase 1  Videowiedergabe          ERLEDIGT (auf macOS verifiziert)
Phase 4  Video-Thumbnail/Schnitt  ERLEDIGT, auf Linux gegen echte Dateien
Phase 2  HEIC/RAW lesbar          ERLEDIGT, auf Linux gegen echte Dateien
Phase 3  Entwickeln               Renderpfad steht; 4 Regler ohne Wirkung
Phase 5  OCR                      umgesetzt; Linux läuft (HardSwish umgangen)
Phase 6  Flatpak                  ERLEDIGT, auf echter Hardware belegt
```

Phase 2 vor Phase 1: Ein unsichtbares Foto wiegt schwerer als ein nicht
abspielbares Video, und HEIC betrifft praktisch jede iPhone-Bibliothek.

## Was dieser Plan bewusst offen lässt

- **Windows** – dieselbe Struktur, andere Werkzeuge (Media Foundation bzw.
  dieselben CLI-Werkzeuge als mitgelieferte Binärdateien). Erst nach Linux
  sinnvoll, da die Abstraktionen dann bereits stehen.
- **Zeitschätzungen** – ohne einen realen Linux-Build (Phase 0) wären sie
  geraten.

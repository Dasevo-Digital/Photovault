# Portierung nach Windows

Der Plan zur Linux-Portierung (`docs/plan_linux.md`) hat sich als
tragfähig erwiesen: sechs Phasen, jede für sich lauffähig, jede auf echter
Hardware belegt. Dieser Plan folgt derselben Form – und profitiert davon,
dass die Linux-Arbeit die plattformabhängigen Stellen bereits
herausgezogen hat.

## Der Ausgangspunkt ist deutlich besser als bei Linux

**Erhoben, nicht geschätzt** (Stand v1.8.3):

| | |
|---|---|
| `Platform.isWindows` im Quelltext | **1** Stelle (`reveal_in_file_manager.dart`, `explorer`) |
| Dateien mit Plattformweichen insgesamt | 8 |
| `windows/`-Gerüst | vorhanden, 18 Dateien, in Git |
| Pakete mit Windows-Unterstützung | alle geprüften |

Nachgesehen in den Paket-Metadaten: `flutter_onnxruntime`,
`media_kit_video` (samt `media_kit_libs_windows_video`), `file_picker`
(über Dart und `win32`, **kein** externer Dialog nötig), `url_launcher`,
`path_provider` und `share_plus` führen Windows ausdrücklich. Das ist der
grösste Unterschied zu Linux: Dort fehlte mit `libmpv` und dem
HEVC-Dekoder handfeste Infrastruktur.

**Drei Dinge fallen Windows ohne eigene Arbeit zu**, weil die
Linux-Portierung sie plattformneutral gebaut hat:

1. **Entwickeln.** `lib/services/develop_render.dart` rendert über den
   Fragment-Shader und gilt für *alles ausser macOS*
   (`istMassgeblich => !Platform.isMacOS`). Windows bekommt damit sofort
   den vollen Regler-Satz bis auf die vier bekannten Ausnahmen (Schärfe,
   Rauschunterdrückung, Klarheit, Vignettierung).
2. **Texterkennung.** `OcrService` läuft über nachladbare ONNX-Modelle,
   nicht über eine Systemschnittstelle – einschliesslich des
   `HardSwish`-Umbaus, der die Modelldatei beim ersten Laden umschreibt.
   Ob der zugrundeliegende Fremdfehler auch unter Windows auftritt, ist
   offen; der Umbau schadet dort nicht.
3. **Die Oberflächenschrift.** Seit v1.8.3 wählt `app_theme.dart` je
   Plattform: macOS `.AppleSystemUIFont`, Windows `Segoe UI Variable`
   (Rückfall `Segoe UI`), sonst `Adwaita Sans`.

## Was fehlt

`NativeImageConverter.isSupported()` gibt ausserhalb von macOS `false`
zurück, und `LinuxImageTools` heisst nicht ohne Grund so. Unter Windows
fehlen damit heute:

| Fähigkeit | heute | Folge |
|---|---|---|
| HEIC/HEIF lesen | – | iPhone-Fotos ohne Vorschau, nicht zu öffnen |
| RAW lesen | – | dasselbe für alle Hersteller-RAWs |
| Video-Vorschaubild | – | Videos ohne Bild in der Zeitleiste |
| Videolänge | – | keine Dauer in den Angaben |
| Video-Zuschnitt | – | Funktion fehlt |

## Der entscheidende Entwurf: Werkzeuge oder Systemschnittstelle?

Windows böte für HEIC die **Windows Imaging Component** an. Das ist ein
Irrweg, und zwar aus einem Grund, den man kennen muss: HEIF-Dateien
öffnet WIC nur, wenn die **HEVC Video Extensions** installiert sind – ein
Paket, das Microsoft im Store **kostenpflichtig** anbietet. Eine
Fotoverwaltung, die iPhone-Fotos erst nach einem Kauf anzeigt, ist keine.

Dieselbe Falle wie unter Linux, wo Ubuntu libheif ohne Dekoder
ausliefert – nur teurer. Die Antwort ist deshalb dieselbe: **die Werkzeuge
mitliefern.** `heif-convert.exe`, `dcraw_emu.exe`, `ffmpeg.exe` und
`ffprobe.exe` neben die Anwendung legen, so wie das Flatpak sie ins Bündel
nimmt.

Damit wird aus `LinuxImageTools` eine gemeinsame Klasse. Der Umbau ist
klein, weil die Struktur schon steht:

* Die Werkzeugsuche über `PATH` liegt bereits in Dart und kennt keine
  Linux-Eigenheit – nur `Platform.pathSeparator` und das Ausführungsbit,
  das unter Windows entfällt (dort zählt die Endung `.exe`).
* Alle Aufrufe laufen über `Process.run` mit Argumentlisten, nicht über
  eine Shell. Anführungszeichen und Leerzeichen in Pfaden sind damit
  bereits richtig behandelt.
* `dcraw_emu` schreibt neben die Eingabedatei, weshalb schon heute in
  einen Temp-Ordner kopiert wird – unter Windows genauso nötig.

**Zu prüfen bleibt:** ob `heif-convert.exe` bei mehrbildrigen Dateien
dieselbe `out-1.jpg`-Benennung verwendet (der Sonderfall ist in
`convertToJpeg` bereits behandelt) und ob `ffmpeg` mit Laufwerksbuchstaben
in `-i` klarkommt, wenn der Pfad ein Doppelpunkt enthält.

## Zuschnitt: sechs Phasen

| | Inhalt | Wichtigster Beleg |
|---|---|---|
| **0** ✔ | **ERLEDIGT** – baut, startet, Suite grün | `user_version` 45, 1112 Tests grün |
| **1** ✔ | **ERLEDIGT** – Werkzeugschicht: `LinuxImageTools` → `DesktopImageTools`, Endung `.exe`, Suche ohne Ausführungsbit | ffmpeg gefunden und gestartet, Suite auf beiden Seiten grün |
| **2** ✔ | **ERLEDIGT** – HEIC und RAW gegen echte Dateien | dieselbe Testtafel wie unter Linux, grün |
| **3** ✔ | **ERLEDIGT** (fiel mit Phase 2 ab) – Video: Vorschaubild, Länge, verlustfreier Zuschnitt | `-ss`/`-to` **vor** `-i`, wie unter Linux |
| **4** ✔ | **ERLEDIGT** – Wiedergabe über `media_kit` | Position rückt vor, Textur wird zugewiesen |
| **5** ✔ | **ERLEDIGT** – Namen und Optik: Fenstertitel, `Runner.rc`, Symbol | Fenstertitel im laufenden Paket: „Photo Vault“ |
| **6** ✔ | **ERLEDIGT** – Paketierung: Verzeichnis samt Werkzeugen | startet aus dem Zip mit geleertem `PATH` |

Phase 5 ist klein, aber nicht optional: In `windows/runner/main.cpp` und
dreimal in `windows/runner/Runner.rc` steht `photo_vault`. Dasselbe Versäumnis
wie unter Linux, wo das Fenster bis v1.8.3 `photo_vault` hiess.

## Phase 0 — erledigt (2026-08-22)

Windows 11 Pro 26200, i7-8750H, 32 GB. Eingerichtet über SSH: Git und
Visual Studio Community 2022 mit der C++-Arbeitslast über `winget`,
Flutter **3.44.8** von Hand ausgepackt — dieselbe Fassung wie auf Mac und
Linux, damit die Bauten vergleichbar bleiben.

```
flutter doctor:  Flutter ✓   Windows-Version ✓   Visual Studio ✓
                 Windows-SDK 10.0.26100        Zielgerät „Windows (desktop)" ✓
flutter build windows --release   →  photo_vault.exe in 154 s
App gestartet                     →  läuft
%APPDATA%\com.example\photo_vault\PhotoVault\library.sqlite
                                  →  user_version 45, von null angelegt
flutter test                      →  1112 grün, 10 übersprungen
```

**Der erste Bau lief auf Anhieb durch.** Die einzigen Warnungen kommen aus
dem media_kit-Plugin (CMake-Richtlinie CMP0175) und betreffen unseren Code
nicht.

### Fünf Tests fielen durch — vier davon Testfehler, keiner im Programm

* **Dreimal Pfadtrenner.** `keine_festen_texte_test` verglich seine
  Ausnahmeliste und den l10n-Ausschluss mit Schrägstrichen, Windows
  liefert Backslashes — dadurch meldete der Wächter die erzeugten
  Sprachdateien und das Schlagwort-Vokabular als Fund.
  `audit5_leihe_und_reste_test` zerlegte Pfade mit `split('/')` statt mit
  `p.basename`. Beides behoben, der Pfad wird jetzt **einmal** normiert
  statt an jeder Vergleichsstelle.
* **`linux_werkzeugsuche_test`** prüft Unix-Semantik: Ausführungsbit und
  eine Shell namens `sh`. Beides gibt es unter Windows nicht. Die Datei
  läuft jetzt mit `@TestOn('mac-os || linux')` nur dort, wo sie gilt —
  die Windows-Werkzeugschicht bekommt in Phase 1 eigene Prüfungen.
* **Windows lässt keine offene Datei löschen.** Im Abbau von
  `gesicht_kontextmenue_test` blieb die angezeigte Originaldatei gesperrt.
  Gemessen: acht Sekunden, 54 Versuche, ohne Erfolg; den
  Bildzwischenspeicher zu leeren ändert nichts.

  **Es ist kein Fehler im Löschpfad der App.** Die vier übrigen Tests
  derselben Datei zeigen dasselbe Foto an und löschen es anschliessend in
  *null Millisekunden beim ersten Versuch*. Es hängt an dieser einen
  Aktion im Testkontext. Der Abbau versucht es deshalb mehrfach und gibt
  danach auf, statt einen grünen Test an seinem Aufräumen scheitern zu
  lassen.

### Eine Falle beim Übertragen

Ein `tar` vom Mac schleppt **`._`-Beidateien** mit (Ressourcezweige). Der
Flutter-Testlader versucht, sie als Dart-Quelltext zu lesen, und stürzt mit
`Failed to decode data using encoding 'utf-8'` ab — 183 Stück waren es.
`git archive` erzeugt sie nicht, deshalb lief der erste Lauf sauber. Wer
von Hand packt: `COPYFILE_DISABLE=1 tar --exclude '._*'`.

## Was aus der Linux-Runde zu übernehmen ist

Diese Punkte haben dort Zeit gekostet und sind hier vorhersehbar:

* **Auf der Zielmaschine messen, nicht auf der Baumaschine.** Das Flatpak
  lud ONNX Runtime klaglos aus dem Bauverzeichnis; erst das Ausblenden des
  Heimatordners zeigte, dass die Bibliothek im Bündel fehlte. Unter
  Windows ist das Gegenstück: eine DLL, die nur deshalb gefunden wird,
  weil sie im Bauordner oder in `PATH` liegt. **Die Probe gehört auf eine
  Maschine ohne Entwicklungsumgebung.**
* **„Vorhanden" ist nicht „läuft".** `where heif-convert.exe` genügt
  nicht; das Werkzeug muss aufgerufen werden. Unter Linux lag einmal ein
  libtool-Hüllskript statt des Programms an der Stelle.
* **Die Kennung nicht anfassen.** Aus ihr leitet sich der Ablageort ab.
  Unter Windows ist das `%APPDATA%\<Kennung>` – ein Wechsel liesse die
  Bibliothek einer benutzten Installation verschwinden.
  `test/linux_kennung_test.dart` hält das für Linux fest; ein Gegenstück
  für Windows gehört dazu.
* **Debug-Bauten messen nicht.** Ein Download kam im Debug-Bau auf ein
  Sechstel der echten Geschwindigkeit.

## Offene Fragen, die nur eine Maschine beantwortet

1. **Gibt es überhaupt eine Windows-Maschine?** Die Linux-Portierung kam
   erst voran, als eine bereitstand. Ohne sie lässt sich Phase 0 nicht
   abschliessen, und alles Weitere wäre geraten.
2. **`sqlite3_flutter_libs`** liefert in der eingesetzten Fassung keine
   eigenen Plattformordner mehr, sondern zieht die Bibliothek über
   Build-Hooks. Ob das unter Windows greift, zeigt der erste Bau.
3. **Woher kommen die Werkzeug-Binärdateien?** Für Linux liefert das
   Flatpak sie aus dem Quellcode. Für Windows gibt es fertige Bauten
   (libheif, LibRaw, ffmpeg als `gyan.dev`- oder `BtbN`-Bauten). Sie
   müssen mit Prüfsumme festgelegt werden, wie die Modelle im Katalog –
   ein Werkzeug ohne Prüfsumme im Installationspaket wäre ein
   Einfallstor.
4. **Signatur.** Ohne Zertifikat meldet sich SmartScreen bei jedem
   Download, ähnlich wie Gatekeeper auf macOS. Ein
   EV-Code-Signing-Zertifikat kostet jährlich; ohne es bleibt es bei der
   Warnung.

## Was dieser Plan bewusst offen lässt

* **Windows on ARM.** Flutter baut dafür, die Werkzeug-Binärdateien gibt
  es aber überwiegend nur für x64. Erst nach x64 sinnvoll.
* **Die Objektivkorrektur.** Sie hängt auf macOS an `CIRAWFilter`; unter
  Linux fehlt sie ebenso. LibRaw kann sie nicht ersetzen, ohne eine
  eigene Objektivdatenbank mitzubringen.
* **Zeitschätzungen.** Ohne einen ersten echten Bau wären sie geraten –
  dieselbe Zurückhaltung wie im Linux-Plan.

## Phase 1 — erledigt (2026-08-22)

Aus `LinuxImageTools` ist `DesktopImageTools` geworden. Die Umbenennung
war der kleinste Teil; die Arbeit steckte in der Werkzeugsuche, denn
genau dort – und nur dort – unterscheiden sich die beiden Plattformen.

**Drei Unterschiede, alle in der Suche:**

| | Unix | Windows |
|---|---|---|
| Dateiname | `ffmpeg` | `ffmpeg.exe` |
| `PATH`-Trenner | `:` | `;` |
| ausführbar heisst | Ausführungsbit gesetzt | Endung `.exe` |

Der `PATH`-Trenner war der gefährlichste davon: Mit Doppelpunkt getrennt
zerfällt unter Windows **jeder** Eintrag am Laufwerksbuchstaben
(`C:\Windows` wird zu `C` und `\Windows`). Die Suche hätte nichts
gefunden und die App hätte gemeldet, es fehlten sämtliche Werkzeuge –
ohne Fehler, ohne Hinweis.

`dateiname()` hängt die Endung an, und **Suche wie Aufruf gehen beide
hindurch**. Liefe der Aufruf am Namen der Suche vorbei, könnte die App
etwas finden, das sie nicht starten kann. Eine schon vorhandene Endung
bleibt stehen, sonst würde ein vollständiger Pfad zu `ffmpeg.exe.exe`.

Als ausführbar gilt bewusst **nur** `.exe`, nicht `PATHEXT`: `.bat` und
`.cmd` lassen sich mit `Process.run` gar nicht starten (Windows braucht
dafür `cmd.exe`). Sie als gefunden zu melden hiesse, eine Fähigkeit zu
behaupten, die beim ersten Aufruf scheitert.

**Neu dazugekommen: der Programmordner.** Gesucht wird jetzt zuerst neben
der Anwendung und in einem Unterordner `tools`, erst danach im `PATH`.
Unter Windows gibt es keine Paketquelle, aus der sich `heif-convert`
nachinstallieren liesse – die Werkzeuge müssen mitgeliefert werden
(Phase 6), und ohne diesen Zweig fände die App sie dort nie. Unter Linux
schadet der Blick nicht: Im Flatpak liegen sie in `/app/bin` und damit
ohnehin im `PATH`.

**Die Auskunft im Werkzeuge-Bildschirm** hing an `Platform.isLinux` und
hätte unter Windows weiterhin „Inaktiv – native Swift-Datei muss noch ins
Xcode-Projekt eingebunden werden" gesagt. Sie fragt jetzt, wie die
Werkzeugschicht selbst, nach der Verneinung von macOS. Dieselbe Regel
steht im Test: Als Aufzählung von Linux und Windows geschrieben, prüfte
er unter Windows den falschen Zweig und wäre trotzdem grün gewesen.

### Gemessen, nicht gelesen

Die eingecheckten Tests arbeiten mit angelegten Dateien – die belegen die
Mechanik, nicht das Zusammenspiel mit einem echten Programm. Deshalb eine
einmalige Gegenprobe mit einem über `winget` installierten ffmpeg
(Gyan.FFmpeg, ffmpeg 9.0):

```
pruefeWerkzeuge()  {heif-convert: false, dcraw_emu: false,
                    ffmpeg: true, ffprobe: true}
Process.run(dateiname('ffmpeg'), ['-version'])   Rückgabewert 0
videoDauer(probe.mp4)                            3.0 s   (erzeugt: 3 s)
videoThumbnail(probe.mp4, 160)                   4170 Bytes JPEG
trimVideo(0,5 s → 2,0 s)                         true, Ergebnis 1,9 s
```

Damit ist auch die im Plan offen notierte Frage beantwortet: **ffmpeg
kommt mit dem Laufwerksbuchstaben in `-i` zurecht.** Der Pfad war
`C:\Users\…\Temp\pv_p1_8ae88ef8\probe.mp4`, Doppelpunkt inklusive.

Die 1,9 statt 1,5 Sekunden beim Zuschnitt sind kein Fehler: Verlustfrei
(`-c copy`) wird an Schlüsselbildern geschnitten, nicht an Einzelbildern.
Unter Linux ist es dasselbe, und der dortige Test lässt aus genau diesem
Grund eine Abweichung von bis zu 1,2 Sekunden zu.

Dass `heif-convert` und `dcraw_emu` als fehlend gemeldet werden, ist
richtig so – sie sind auf dieser Maschine nicht installiert. Der
Werkzeuge-Bildschirm sagt jetzt „Eingeschränkt – es fehlen: dcraw_emu,
heif-convert" statt einer Auskunft über eine Swift-Datei.

### Stand der Suiten

```
macOS     1128 grün,  6 übersprungen
Windows   1122 grün, 12 übersprungen
```

Beide Seiten zählen 1134 Tests; welche übersprungen werden, ist der
einzige Unterschied.

### Nachgeprüft: Linux (24.08.2026)

Beim Schreiben dieses Plans teilten sich Linux- und Windows-Testmaschine
eine Adresse; unter ihr antwortete Windows, und der umbenannte Test war
seit der Umbenennung nie gelaufen. Seit dem 24.08.2026 sind es zwei
getrennte Rechner mit je eigener Adresse, und die Prüfung ist nachgeholt.

`test/werkzeuge_echt_test.dart` – so heisst die Datei inzwischen, und sie
trägt `@TestOn('linux || windows')` statt nur `linux` – gegen echte
Werkzeuge auf der Linux-Maschine:

```
HEIC wird gelesen, skaliert und behält seinen Inhalt        ✓
AVIF wird über libheif gelesen, nicht über den RAW-Entwickler ✓
RAW wird entwickelt, skaliert und lässt das Original in Ruhe  ✓
Video Vorschaubild und Länge                                  ✓
Video Zuschnitt trifft die verlangte Länge                    ✓
```

Damit ist die Vermutung von damals – der Namenswechsel ändert am
Verhalten nichts – nicht mehr Vermutung, sondern gemessen.

## Phase 2 — erledigt (2026-08-22)

HEIC und RAW werden unter Windows gelesen. Der Weg dahin hatte einen
Fund, mit dem der Plan nicht gerechnet hat.

### libheif hat das Programm umbenannt

`heif-convert` gibt es nicht mehr. libheif hat es mit Fassung **1.18** in
`heif-dec` umbenannt; beim Einspielen legt der Bauplan unter Unix einen
Symlink unter dem alten Namen an, unter Windows eine Kopie. **Das
MSYS2-Paket tut weder das eine noch das andere** – dort liegt
ausschliesslich `heif-dec.exe`:

```
C:\msys64\mingw64\bin\  heif-dec.exe  heif-enc.exe  heif-info.exe
                          heif-thumbnailer.exe  heif-view.exe
```

Die Schicht suchte nach `heif-convert` und hätte unter Windows nichts
gefunden. Jedes iPhone-Foto wäre unsichtbar geblieben – ohne Fehler, mit
der ordentlichen Meldung „es fehlt: heif-convert", die zu einem Paket
rät, das genau dieses Programm nicht mehr enthält.

Das ist derselbe Symlink, der unter Linux schon einmal einen Ausfall
verursacht hat: Beim Aufräumen des Flatpak-Bündels fiel `heif-dec` weg,
und `heif-convert` zeigte ins Leere. **Beide Namen zu kennen ist deshalb
keine Windows-Frage.** Die Schicht sucht jetzt der Reihe nach
`heif-dec`, dann `heif-convert`, und meldet fehlend unter dem heutigen
Namen. Die beiden Linux-Skripte (`tool/flatpak_bauen.sh`,
`tool/linux_setup_check.sh`) prüfen ebenfalls `heif-dec` – sie sollen
prüfen, was die App wirklich aufruft.

### Die Suche merkt sich jetzt den Ort, nicht nur die Antwort

Damit fiel eine Lücke aus Phase 1 auf: Gefunden wurde ein `bool`,
aufgerufen wurde der blosse Name. Für ein Werkzeug im **Programmordner**
– und genau dort werden sie unter Windows liegen – hätte das nicht
gereicht: Der Ordner steht nicht im `PATH`, ein Aufruf über den Namen
liefe ins Leere. Gemerkt wird jetzt der vollständige Pfad, und
`Process.run` bekommt genau den. Suche und Aufruf können damit nicht
mehr auseinanderlaufen.

### Woher die Werkzeuge kommen

Damit ist die dritte offene Frage des Plans beantwortet:

| Werkzeug | Quelle | Fassung | Anmerkung |
|---|---|---|---|
| `dcraw_emu.exe` | libraw.org, `LibRaw-0.22.2-Win64.zip` | 0.22.2 | MSVC-2022-Bau, braucht nur `libraw.dll` |
| `heif-dec.exe` | MSYS2, `mingw-w64-x86_64-libheif` | 1.23.1-3 | mingw-Bau, braucht die DLLs aus `mingw64\bin` |
| `ffmpeg.exe`, `ffprobe.exe` | winget, `Gyan.FFmpeg` | 9.0 | in sich geschlossen |

Prüfsumme des LibRaw-Pakets (SHA-256):
`ac64fa12bb00a7581332d4c6ab918c0533fb3f119d6b668d47a6875410dca948`

Welche DLLs `heif-dec.exe` tatsächlich braucht, gehört zu Phase 6 –
LibRaw ist mit einer einzigen DLL der angenehmere Fall.

**Der entscheidende Punkt ist nicht, dass die Dateien da sind, sondern
dass libheif einen HEVC-Dekoder mitbringt.** Genau daran ist unter Linux
der erste Versuch gescheitert. Nachgesehen, nicht angenommen:

```
heif-dec --list-decoders
  HEIC decoders:  libde265 = libde265 HEVC decoder, version 1.1.1
  AVIF decoders:  dav1d v7.0.0,  aom v3.14.1
  JPEG decoders:  libjpeg-turbo 3.2.0
```

### Gemessen

`test/linux_werkzeuge_echt_test.dart` heisst jetzt
`test/werkzeuge_echt_test.dart` und läuft unter Linux **und** Windows.
Die Vorlage ist von `test/fixtures/linux/` nach `test/fixtures/werkzeuge/`
gewandert – sie hat nie etwas Linux-Eigenes gehabt.

```
HEIC   probe.heic → JPEG, auf 600 px skaliert (600x400)
       links rot, rechts grün – es ist wirklich dieses Bild
RAW    iphone_6s_plus.dng (10,2 MB) → JPEG, auf 800 px skaliert
       Original unverändert, kein TIFF im Ordner der Eingabe
Video  Vorschaubild 320 px, nicht schwarz; Länge 4,0 s
       Zuschnitt 2–6 s trifft die verlangte Länge
```

Der RAW-Test belegt nebenbei den Grund, aus dem überhaupt in einen
Temp-Ordner kopiert wird: `dcraw_emu` schreibt sein Ergebnis **neben die
Eingabe**. Täte es das in der Bibliothek, läge dort zu jedem RAW eine
36-MB-TIFF-Datei, die niemand bestellt hat. Der Test zählt die Nachbarn
vorher und nachher.

**Phase 3 ist damit abgefallen.** Die Videogruppe derselben Datei prüft
genau die drei Punkte, die dort stehen – Vorschaubild, Länge,
verlustfreier Zuschnitt –, und sie ist unter Windows grün. Auch die im
Plan offen notierte Frage nach dem Laufwerksbuchstaben in `-i` ist damit
zum zweiten Mal beantwortet.

### Fehlt ein Werkzeug, wird übersprungen – nicht rot

Diese Datei braucht echte Werkzeuge. Eine Maschine ohne libheif darf die
Suite nicht rot färben, sonst ist ein echter Fund von einer fehlenden
Installation nicht mehr zu unterscheiden. `skip:` genügt dafür nicht: Es
wird schon beim Einsammeln der Tests ausgewertet, die Werkzeugsuche ist
aber asynchron. Deshalb `markTestSkipped` im Test selbst. Nachgeprüft,
indem die Suite noch einmal ohne die Werkzeugordner im `PATH` lief:

```
HEIC   ~ heif-dec ist auf dieser Maschine nicht installiert
RAW    ~ dcraw_emu ist auf dieser Maschine nicht installiert
Video  + grün (ffmpeg steht im Benutzer-PATH)
```

### Die RAW-Vorlage

`tool/fetch_format_samples.sh` gab es nicht, obwohl `.gitignore` und der
Test darauf verwiesen. Jetzt gibt es das Skript: Es lädt die Vorlage von
raw.pixls.us (CC0) und prüft die Prüfsumme. Erst neben das Ziel, dann
umbenannt – ein abgebrochener Download hinterliesse sonst eine halbe
Datei, die beim nächsten Lauf als vorhanden gilt und den Test mit einem
unverständlichen Fehler scheitern lässt.

### Stand der Suiten

```
macOS     1129 grün,  6 übersprungen   (1135 gesammelt)
Windows   1127 grün, 12 übersprungen   (1139 gesammelt)
```

Der Unterschied von vier sind die Werkzeugtests: Sie tragen
`@TestOn('linux || windows')` und werden auf macOS gar nicht erst
eingesammelt.

### Weiterhin nicht nachgeprüft: Linux

Die Umstellung auf `heif-dec` betrifft Linux mit. Unter Debian und im
Flatpak gibt es beide Namen, die Suche findet also weiterhin etwas –
gelaufen ist der dortige Test seit der Änderung aber nicht, die Maschine
ist nach wie vor nicht erreichbar.

## Phase 4 — erledigt (2026-08-22)

Die Videowiedergabe läuft. Belegt wird nicht „stürzt nicht ab", sondern:

```
Dauer               3000 ms
Seitenverhältnis    1,333  (4:3 – nicht der Rückfallwert 16:9)
Position nach 1,2 s 1200 ms
Textur              zugewiesen, VideoOutput.Resize auf 320x240
```

Das Seitenverhältnis steht mit Absicht dabei: `aspectRatio` fällt auf
16:9 zurück, solange die Bildmaße fehlen. Ein Test auf „grösser als null"
wäre auch dann grün, wenn nie ein Maß angekommen ist.

### Zweimal hing der Test, und zweimal lag es am Test

Das ist der eigentliche Ertrag dieser Phase, denn beide Fallen gelten für
jeden, der hier später etwas prüft.

**Der relative Pfad.** libmpv ist eine native Bibliothek mit eigenem
Arbeitsverzeichnis. Ein Pfad, den Dart klaglos auflöst – `existsSync()`
war die ganze Zeit `true` –, kommt dort als nicht vorhanden an. Keine
Dauer, keine Wiedergabe, **keine Fehlermeldung**.
`VideoPlaybackController.open()` reicht den Pfad jetzt absolut weiter; die
App übergibt heute ohnehin nur absolute, aber darauf sollte sich diese
Stelle nicht verlassen müssen.

**Die Reihenfolge.** `media_kit` zeichnet seine Textur im Rasterschritt
von Flutter. Ohne Widget-Baum plant Flutter gar keine Bilder, und
`open()` wartet auf ein erstes Bild, das nie kommt – der Aufruf kehrt
überhaupt nicht zurück, weder mit Fehler noch mit Zeitüberschreitung. Der
Test baut die Bildfläche jetzt zuerst und öffnet erst danach.

Eingegrenzt wurde das über die Protokollströme von mpv
(`player.stream.error` und `player.stream.log`), nachdem drei Verdächtige
im Raum standen. **Der erste war es nicht:** Die SSH-Sitzung läuft in
Sitzung 0 und hat keinen Desktop – naheliegend, aber falsch. In der
angemeldeten Konsolensitzung, über eine geplante Aufgabe mit `/IT`
gestartet, hing es genauso. Erst mpvs eigene Meldung
(`No video or audio streams selected`) zeigte, wo es klemmte.

### Nicht unter macOS

Nicht, weil es dort nicht ginge: Die Testfassung läuft im Sandkasten, ihr
Arbeitsverzeichnis zeigt nach
`~/Library/Containers/com.example.photoVault.test/Data/`, und die Vorlage
aus dem Projektordner ist für sie schlicht nicht vorhanden. Die Textur
wird dort ebenso angelegt, nur eben ohne Datei.

## Phase 5 — erledigt (2026-08-22)

Das Fenster hiess `photo_vault` – dasselbe Versäumnis wie unter Linux, wo
es bis 1.8.3 so stand. Geändert wurden **drei** Stellen, nicht fünf:

| Stelle | vorher | jetzt |
|---|---|---|
| `main.cpp`, Fenstertitel | `photo_vault` | **Photo Vault** |
| `Runner.rc`, `FileDescription` | `photo_vault` | **Photo Vault** |
| `Runner.rc`, `LegalCopyright` | `… com.example …` | `… Photo Vault …` |
| `Runner.rc`, `CompanyName` | `com.example` | **unverändert** |
| `Runner.rc`, `ProductName` | `photo_vault` | **unverändert** |

**Die letzten beiden sind der Punkt.** `path_provider_windows` liest
CompanyName und ProductName mit `GetFileVersionInfo` aus der eigenen .exe
und setzt daraus `%APPDATA%\<CompanyName>\<ProductName>\` zusammen
(nachgelesen in `path_provider_windows_real.dart`, Zeilen 208/210). Eine
Änderung liesse die Bibliothek einer benutzten Installation verschwinden –
genau das ist unter Linux schon einmal passiert, beim Versuch, die
Fensterklasse an die Flatpak-Kennung anzugleichen.
`test/windows_kennung_test.dart` hält beide fest, als Gegenstück zu
`linux_kennung_test.dart`.

Das Programmsymbol war noch Flutters blaues Logo. Es stammt jetzt aus
derselben Vorlage wie das von macOS, in sieben Stufen von 16 bis 256
Pixeln. Geprüft nicht über die Dateigrösse, sondern über die Bytes: Die
256er-Stufe der `.ico` ist Byte für Byte dieselbe wie `app_icon_256.png`,
und dieselbe Folge steckt in der gebauten `.exe` (ab Byte 73.944).

## Phase 6 — erledigt (2026-08-22)

**Kein MSIX.** Ein MSIX-Paket muss signiert sein; ohne Zertifikat müsste
der Nutzer erst ein selbst erzeugtes in seinen Stammspeicher aufnehmen –
eine höhere Hürde als die SmartScreen-Warnung, die er ohnehin bekommt.
Ein Verzeichnis zum Auspacken entspricht dem, was das Flatpak unter Linux
leistet: alles dabei, nichts nachzuinstallieren.

Drei Skripte, dieselbe Aufteilung wie unter Linux:

| | |
|---|---|
| `tool/windows_libheif.sh` | baut libheif in MSYS2, **nur mit Dekodern** |
| `tool/windows_werkzeuge.ps1` | holt LibRaw und ffmpeg mit Prüfsumme, ruft den libheif-Bau |
| `tool/windows_bauen.ps1` | baut, stellt zusammen, **prüft**, packt ein |

### Warum libheif selbst gebaut wird

Das fertige MSYS2-Paket zieht **63 MB** DLLs nach sich – darunter 22 MB
libx265, 9 MB libaom, 7,5 MB SVT-AV1 und 3,5 MB rav1e. Das sind
**Encoder**. Zum Lesen von iPhone-Fotos braucht es davon nichts.

Mit abgeschalteten Encodern sind es **16 MB** und 19 statt 31 DLLs, bei
unverändertem Funktionsumfang für unseren Zweck:

```
HEIC decoders:  libde265 1.1.1
AVIF decoders:  dav1d v7.0.0
JPEG decoders:  libjpeg-turbo 3.2.0
```

Dieselbe Überlegung steht im Flatpak-Bauplan, wo aus demselben Grund
dav1d statt aom genommen wurde. Nebenbei liefert der eigene Bau
`heif-convert.exe` als Kopie mit – das MSYS2-Paket tut das nicht.

### Woher die Werkzeuge kommen, mit Prüfsumme

| Werkzeug | Quelle | Fassung |
|---|---|---|
| `dcraw_emu.exe`, `libraw.dll` | libraw.org, `LibRaw-0.22.2-Win64.zip` | 0.22.2 |
| `ffmpeg.exe`, `ffprobe.exe` | BtbN, **LGPL**-shared, datierte Marke | n9.0.1 |
| `heif-dec.exe` + 18 DLLs | selbst gebaut, libheif v1.23.1 | 1.23.1 |

Die LGPL-Fassung von ffmpeg statt der GPL-Fassung ist eine bewusste Wahl:
Wir dekodieren und kopieren (`-c copy`), wir kodieren kein H.264. Die
datierte Marke bei BtbN ist unveränderlich, `latest` wäre es nicht.

**Und genau das wurde sofort sichtbar.** Sobald der Werkzeugordner des
Pakets im `PATH` stand, wurden die beiden Videotests rot: Sie erzeugten
ihre Vorlage mit `-c:v libx264`, und den Kodierer gibt es in der
LGPL-Fassung nicht. Die App braucht ihn auch nicht – sie schneidet mit
`-c copy` und schreibt Vorschaubilder als JPEG. Der Test prüfte also eine
Fähigkeit, die im Paket weder vorhanden noch nötig ist; er nimmt jetzt
`mpeg4`. Dazu prüft `windows_bauen.ps1` seither ausdrücklich den
**mjpeg-Kodierer** – der wird gebraucht, und ein Dekoder allein genügt
dafür nicht.

### Das Paket

```
entpackt   245 MB
Zip        102 MB
```

Davon sind 145 MB Werkzeuge und rund 100 MB die App samt
`onnxruntime.dll` (12 MB), `libmpv-2.dll` (28 MB) und
`flutter_windows.dll` (20 MB). Der grösste Einzelposten sind ffmpegs
gemeinsame Bibliotheken; ein eigener ffmpeg-Bau mit nur den gebrauchten
Kodierern wäre die nächste Verkleinerung, aber ein eigenes Vorhaben.

### Geprüft wird ohne den PATH dieses Rechners

Das ist der wichtigste Handgriff, und er kommt direkt aus der
Linux-Erfahrung: Das Flatpak lud ONNX Runtime einmal klaglos aus dem
Bauverzeichnis, während sie im Bündel fehlte. Mit dem eigenen `PATH`
fände sich `heif-dec.exe` auch dann, wenn es im Paket fehlte – es liegt
auf dieser Maschine unter `C:\msys64`.

```
Werkzeuge - ohne den PATH dieses Rechners
  heif-dec.exe laeuft          dcraw_emu.exe laeuft
  ffmpeg.exe laeuft            ffprobe.exe laeuft
  libheif hat einen HEVC-Dekoder
  libheif hat einen AVIF-Dekoder
  ffmpeg kann HEVC lesen
  HEIC ausgepackt (17.989 Bytes JPEG)
```

Die letzte Zeile ist die wichtigste: **Vorhandensein genügt nicht.** Unter
Linux lag einmal ein libtool-Hüllskript statt des Programms an der Stelle,
und Ubuntu liefert libheif ohne HEVC-Dekoder aus.

### Start auf einer Maschine, die nicht gebaut hat

Eine zweite Maschine gibt es nicht – ihr Zustand wurde nachgestellt: aus
dem Zip nach `C:\Test` ausgepackt, also ausserhalb des Bauverzeichnisses,
und mit `PATH=C:\WINDOWS\System32;C:\WINDOWS` gestartet.

```
laeuft, PID 13632
Fenstertitel: 'Photo Vault'
Arbeitsspeicher: 178 MB
Datenordner: C:\Users\<Benutzer>\AppData\Roaming\com.example\photo_vault\PhotoVault
  geodata  library  models  library.sqlite (286.720 Bytes)
```

Der Ablageort ist derselbe wie in Phase 0 – die Kennung hat der
Namenswechsel also nicht angefasst. Und der Fenstertitel belegt Phase 5 im
laufenden Betrieb, nicht bloss im Quelltext.

### Findet die App ihre Werkzeuge auch selbst?

Darauf ruht die ganze Paketierung, und die Prüfung oben belegt es nicht:
Sie ruft die Werkzeuge im Paketordner selbst auf. Deshalb eine eigene
Gegenprobe – der Werkzeugordner neben den Testläufer gelegt, `PATH` ohne
MSYS2, ohne LibRaw, ohne das WinGet-ffmpeg:

```
Anwendung:    …\engine\windows-x64
Suchpfade:    …\windows-x64,  …\windows-x64\tools,  …
heif-dec gefunden unter: …\windows-x64\tools\heif-dec.exe
Aufruf: Rueckgabewert 0, libheif 1.23.1
```

Gefunden **und** gestartet, allein über den Programmordner.

### Drei Fallen in PowerShell 5.1

Alle drei haben still zugeschlagen, und alle drei stehen jetzt als
Kommentar an der Stelle, an der sie zuschlugen:

* **Stderr eines fremden Programms bricht ab.** Mit
  `$ErrorActionPreference = 'Stop'` genügt eine blosse Warnung („Paket ist
  aktuell, überspringe"), um das Skript zu beenden – mit Rückgabewert 0
  und einem halben Werkzeugordner.
* **`-replace` kennt keine Skriptblöcke.** Erst PowerShell 6. Unter 5.1
  fiel der Laufwerksbuchstabe still weg, und der Bau suchte sein Skript
  unter `/src/…` statt `/c/src/…`.
* **Variablennamen unterscheiden keine Gross- und Kleinschreibung.** Die
  lokale `$zip` überschrieb den Schalter `$Zip`; der Versuch, eine
  Zeichenkette in einen Schalter zu schreiben, brach das Skript mitten im
  Abschnitt ab.

Dazu eine vierte, die keine Sprachfalle ist: `Compress-Archive` scheiterte
an den langen Pfaden unter `data\flutter_assets`. Es packt jetzt
`System.IO.Compression.ZipFile`.

### Und eine in MSYS2

`set -u` **vor** `source /etc/profile` beendet die Shell sofort und ohne
Meldung: MSYS2s Profil greift auf nicht gesetzte Variablen zu. Zwei
Bauläufe endeten so mit Rückgabewert 0 und ohne jede Ausgabe.

### Stand der Suiten am Ende der Portierung

```
macOS     1134 grün,  6 übersprungen
Windows   1132 grün, 12 übersprungen
```

Der Windows-Lauf lief dabei gegen die **mitgelieferten** Werkzeuge
(`C:\Test\PhotoVault\tools` an erster Stelle im `PATH`), nicht gegen die,
mit denen entwickelt wurde. Genau so ist der libx264-Fund aufgefallen.

### Was offen bleibt

* **Linux ist seit Phase 2 nicht gelaufen.** Die Umstellung auf
  `heif-dec`, die gemeinsame Werkzeugschicht und der absolute Pfad in der
  Videowiedergabe betreffen die Plattform mit. Der Übersetzer deckt die
  Umbenennungen ab, aber geprüft ist dort nichts. Die Maschine teilt sich
  die Adresse mit dem Windows-Rechner.
* **Ein eigener ffmpeg-Bau** mit nur den gebrauchten Kodierern wäre die
  nächste Verkleinerung des Pakets – 145 der 245 MB sind Werkzeuge, der
  grösste Einzelposten ffmpegs gemeinsame Bibliotheken.
* **Signatur.** Ohne Zertifikat meldet sich SmartScreen bei jedem
  Download. Daran ändert die Paketierung nichts.

## Nachtrag: die KI-Modelle unter Windows (2026-08-22)

Nach Abschluss der sechs Phasen war `onnxruntime.dll` zwar im Paket, aber
**nie ausgeführt worden**. Das ist keine Kleinigkeit: Der `HardSwish`-Fund
unter Linux war ein Operator, der sich *nur innerhalb eines
Flutter-Prozesses auf einer Plattform* falsch verhielt – im Unittest und
im nackten C++ dagegen richtig. Dass eine DLL im Paket liegt, sagt
darüber nichts.

Die elf gebrauchten Dateien (475 MB) wurden vom Mac herübergespielt und
**vor dem ersten Lauf über SHA-256 gegengeprüft**, alle elf Byte-identisch.
Ein beschädigtes Modell liefert Unsinn statt eines Absturzes, und der sähe
wie ein Plattformfehler aus.

```
Texterkennung      410 ms
                   öffnungszeiten / Straße des 17. Juni 135
                   Preis: 12,50 EUR / GrúBe aus Köln
Objektentfernung   mittlerer Fehler 1,4 von 255 im gefüllten Bereich, 2161 ms
Bildbeschreibung   „A square shaped light is on a blue background."
                   „A blue circle is in the middle of a yellow background."
                   3425 / 3378 ms
```

Alle drei grün. Bemerkenswert daran:

* **Der `HardSwish`-Umbau greift auch hier.** Nach dem Lauf liegt
  `ocr_rec_ohne_hardswish.onnx` (8.982.083 Bytes gegen 8.977.705 der
  Vorlage) neben den Modellen – die Schicht hat also gearbeitet, ohne dass
  es unter Windows nötig gewesen wäre.
* **macOS liefert denselben Text, Zeichen für Zeichen** – einschliesslich
  des fehlerhaften „GrúBe". Das ist eine Grenze des Modells, keine der
  Plattform. Wäre unter Windows etwas anderes herausgekommen, hätte genau
  hier der zweite `HardSwish`-Fall gestanden.
* **Die Bildbeschreibung unterscheidet die beiden Bilder** – Balken gegen
  Kreis, blau gegen gelb. Das ist der Test, der den Fehler im
  Kreuz-Aufmerksamkeits-Cache aufdeckt: Käme für jedes Foto derselbe Satz,
  wäre das Bild nach dem ersten Schritt nicht mehr angekommen.

Geschwindigkeit: 410 ms gegen 169 ms auf dem Mac für dieselbe
Texterkennung. Das ist die Hardware (i7-8750H von 2018), nicht die
Portierung.

### Zwei Testfehler kamen dabei ans Licht

* **`HOME` gibt es unter Windows nicht** – dort heisst die Variable
  `USERPROFILE`. `ocr_test.dart` suchte seine Modelle buchstäblich unter
  `null/ocr_modelle` und hätte „Modelle fehlen" gemeldet: sieht aus wie
  ein fehlendes Modell und ist keins.
* **Zwei Tests kehrten ohne Modell einfach zurück** und meldeten sich
  damit als *bestanden*. Beim Durchsehen einer Suite ist das von einem
  echten Lauf nicht zu unterscheiden – und es sind die einzigen Tests, die
  Bildbeschreibung und Objektentfernung überhaupt prüfen. Sie rufen jetzt
  `markTestSkipped`.

## Prüfrunde Windows: Code, Ressourcen, Sicherheit (2026-08-22)

Alles hier ist gemessen, nicht gelesen.

### Befund 1: AVIF blieb ohne Vorschau — und zwar auch unter Linux

`heicAndRawExtensions` führt `.avif` und `.avifs` ausdrücklich auf, die
Verzweigung in `convertToJpeg` prüfte aber nur `.heic`/`.heif`. **Alles
andere ging an `dcraw_emu`** – einen RAW-Entwickler, der kein AVIF lesen
kann.

```
convertToJpeg(probe.avif)   → null          (keine Vorschau)
heif-dec probe.avif out.jpg → rc 0, 3570 Bytes
```

Der Dekoder war die ganze Zeit da: dav1d liegt im selben Bündel und wird
von der Paketprüfung sogar ausdrücklich bestätigt („libheif hat einen
AVIF-Dekoder"). Nur kam die Datei nie dort an.

Unter macOS fällt das nicht auf, weil ImageIO AVIF selbst kann – **unter
Linux gilt der Fehler seit der Portierung**. Behoben durch
`libheifEndungen`; dazu ein hermetischer Wächter (die Endungsmenge darf
sich nicht mit `rawImageExtensions` überschneiden) und ein echter Test
gegen eine 535-Byte-Vorlage.

### Befund 2: Control Flow Guard war eingebaut, aber wirkungslos

`dumpbin` zeigte vorher:

```
Dynamic base · NX compatible · High Entropy Virtual Addresses
Guard Flags  00000100   (CF instrumented)
```

ASLR, DEP und High-Entropy bringt MSVC von sich aus mit. **CFG aber
nicht:** Flag `0x100` heisst „der Code trägt die Prüfungen", es fehlte
jedoch die Funktionstabelle (`0x400`). Ohne die wertet zur Laufzeit
niemand etwas aus. Genau die Sorte halbe Absicherung, die in einem
Bericht wie eine ganze aussieht.

Mit `/guard:cf` auf beiden Seiten und `/CETCOMPAT` nachher:

```
Dynamic base · NX compatible · High Entropy · CET compatible
Guard CF function table  vorhanden
Guard Flags  00017500   (CF instrumented, Protect delayload IAT)
```

Das ist das Gegenstück zu `-z relro -z now` und `-fstack-protector-strong`
unter Linux. `/CETCOMPAT` wirkt nur auf Prozessoren mit Schattenstapel;
ältere ignorieren die Markierung.

### Befund 3: Die Bibliothek liegt im Roaming-Profil

`getApplicationSupportDirectory()` gibt unter Windows **RoamingAppData**
zurück (`path_provider_windows_real.dart`, `WindowsKnownFolder.RoamingAppData`).
Dort liegen heute `library.sqlite`, `location.json`, `geodata` – und der
Modellordner, der mit allen Modellen über ein Gigabyte erreicht.

Auf einem privaten Rechner ist das harmlos. **Auf einem Rechner mit
servergespeichertem Profil wäre es das nicht:** Windows kopierte den
gesamten Ordner bei jeder An- und Abmeldung zum Server. Microsofts eigene
Regel ist eindeutig – grosse, maschinengebundene Daten gehören nach
`LocalAppData`.

**Nicht geändert**, und zwar bewusst: Der Ordner ist über CompanyName und
ProductName festgelegt; ihn zu verschieben liesse die Bibliothek einer
bestehenden Installation verschwinden. Das braucht eine Umzugslogik und
ist ein eigener Vorgang, kein Nebenbei-Fix in einer Prüfrunde. Bis dahin
steht es hier.

### Was geprüft wurde und in Ordnung war

**Pfade mit Leerzeichen.** Der Klassiker „unquoted path" sitzt genau
dort, wo eine Anwendung unter `C:\Program Files\…` liegt. Gemessen mit
den Werkzeugen unter `C:\Test\Photo Vault mit Leerzeichen\tools`:

```
imPfad                                  true
Process.run(…\heif-dec.exe, --version)  rc 0
Argumente mit Leerzeichen               rc 0, 17.989 Bytes
```

Alle drei Wege sauber – Dart setzt die Anführungszeichen richtig. Kein
Fund, aber jetzt eine Messung statt einer Annahme.

**Keine Debugreste im Paket.** Kein `.pdb`, `.ilk`, `.exp` oder `.lib`.

### Ressourcen: wo die 245 MB stecken

```
tools\avcodec-63.dll     69,4 MB
tools\avfilter-12.dll    29,3 MB
libmpv-2.dll             29,1 MB
tools\avformat-63.dll    21,6 MB
flutter_windows.dll      20,8 MB
data\app.so              15,2 MB
onnxruntime.dll          12,1 MB
```

**ffmpeg macht 127 der 145 MB im Werkzeugordner aus.** Zu streichen ist
dort nichts: Alle sieben `av*`/`sw*`-Bibliotheken hängen als
Ladezeit-Abhängigkeit an `ffmpeg.exe`, auch `avdevice`, das wir nie
benutzen. Der einzige echte Hebel wäre ein eigener ffmpeg-Bau mit nur den
gebrauchten Kodierern – rund 15 statt 127 MB, aber ein eigenes Vorhaben.

Bei libheif ist der Hebel schon gezogen: 16 statt 63 MB (siehe Phase 6).

### Zwei Punkte, die bleiben

* **Keine Signatur.** SmartScreen warnt bei jedem Download. Ein
  EV-Zertifikat kostet jährlich; ohne es bleibt es dabei.
* **Der Programmordner wird vor dem `PATH` durchsucht.** Das ist Absicht
  und die Voraussetzung dafür, dass mitgelieferte Werkzeuge überhaupt
  gefunden werden. Es heisst aber auch: Wer in den Programmordner
  schreiben kann, bestimmt, welches `ffmpeg.exe` läuft. Bei einem
  ausgepackten Verzeichnis unter `Downloads` kann das jeder Prozess des
  angemeldeten Benutzers. Das liegt in der Natur eines tragbaren Pakets
  und wäre nur mit einer Installation unter `Program Files` zu ändern.

### Am Skript

`windows_bauen.ps1` rief `flutter build` unmittelbar auf, während
`$ErrorActionPreference` auf `Stop` stand. Es ging gut, aber nur zufällig:
Dieselbe Konstellation hat in `windows_werkzeuge.ps1` einen Lauf still
beendet – Rückgabewert 0, halber Werkzeugordner. Der Aufruf geht jetzt
durch dieselbe Hülle.

## Gegenprüfung Linux und macOS (2026-08-23)

Die Windows-Arbeit hat an gemeinsamem Code gerührt: `DesktopImageTools`,
`heif-dec` statt `heif-convert`, der absolute Pfad in der Videowiedergabe,
die AVIF-Verzweigung. Das war auf der Linux-Maschine seit Phase 1 nicht
gelaufen. Nachgeholt auf demselben Rechner – es ist ein Dualboot-System,
Windows und Ubuntu 26.04 teilen sich die Adresse.

```
Linux    analyze sauber
         volle Suite            1132 grün, 14 übersprungen
         echte Werkzeuge        HEIC · AVIF · RAW · Video (Bild, Länge, Zuschnitt)
         Videowiedergabe        3000 ms, 4:3, Position 1200 ms, Textur da
         Texterkennung          485 ms, gleicher Text wie macOS und Windows
```

Die Annahme aus Phase 2 hat gehalten: **`heif-convert` ist auf Ubuntu
26.04 ein Symlink auf `heif-dec`** (`/usr/bin/heif-convert -> heif-dec`).
Die Suche findet dort weiterhin etwas, egal welchen Namen sie zuerst
probiert.

Und der AVIF-Fund ist dort belegt: Der Dekoder war die ganze Zeit vorhanden
(`AVIF decoders: aom 3.13.1`), nur kam die Datei nie bei ihm an.

### macOS: die Annahme war richtig, jetzt ist sie gemessen

`.avif` steht in `heicAndRawExtensions`, und unter macOS geht die Datei an
den nativen Kanal. Ob ImageIO AVIF wirklich kann, war nie geprüft – wäre
es nicht so, sähe der Nutzer dort dasselbe wie unter Linux: ein Foto ohne
Vorschau, das sich nicht öffnen lässt.

```
convertToJpegBytes(probe.avif) → 4433 Bytes, 400x400
links r=252 g=0    rechts r=0 g=128
```

`integration_test/avif_macos_test.dart` hält das fest. Die Vorlage steckt
dort als Base64 im Quelltext, nicht als Datei: Die Testfassung läuft im
Sandkasten und sieht den Projektordner nicht – dieselbe Grenze wie beim
Videotest, nur diesmal umgangen statt umschifft.

### Ein Fund am Rand

`tool/linux_setup_check.sh` meldete unter „Noch nicht umgesetzt"
weiterhin *Entwickeln* und *Texterkennung* und verwies auf die Phasen 2, 3
und 5 des Linux-Plans. Alle drei sind seit Langem fertig. Das war das
Erste, was ein Linux-Nutzer beim Aufsetzen zu lesen bekam – und es war
schlicht falsch. Der Abschnitt sagt jetzt, was ohne die einzelnen
Werkzeuge fehlt.

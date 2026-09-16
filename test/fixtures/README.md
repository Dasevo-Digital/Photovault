# Testdaten

Dieses Projekt enthält **keine** Beispielfotos. Alle automatisierten Tests
kommen ohne fremdes Bildmaterial aus – `flutter test` läuft direkt nach dem
Klonen durch, ohne dass irgendetwas heruntergeladen werden muss.

## Was hier liegt

| Pfad | Inhalt | Herkunft |
|---|---|---|
| `sample_images.dart` | Erzeugt Testbilder zur Laufzeit (JPG/PNG/TIFF/BMP/GIF) | selbst erzeugt, lizenzfrei |
| `clip/vocab.json`, `clip/merges.txt` | Winziges, handgeschriebenes Vokabular für die Tokenizer-Tests (nicht die echten CLIP-Dateien) | selbst erstellt |
| `samples/` | Echte Kameradateien, per Skript geladen | extern, **nicht versioniert** |

## Automatisierte Formatprüfung

`test/image_format_test.dart` erzeugt echte Bilddaten in allen Formaten, die
das reine Dart-Paket `image` schreiben kann, und schickt sie durch den
kompletten Import: Formaterkennung → Import → Maße aus den echten Daten →
Thumbnail, das anschließend wieder dekodiert wird.

Abgedeckt: `.jpg`, `.png`, `.tiff`, `.bmp`, `.gif`

## Was sich NICHT automatisiert prüfen lässt

**HEIC/HEIF und alle RAW-Formate.** Beide kann das `image`-Paket weder
schreiben noch lesen; sie laufen über die native macOS-Schicht
(`macos/Runner/ImageConverter.swift` mit ImageIO/CIRAWFilter), die in
`flutter test` gar nicht existiert. Die Tests prüfen für diese Formate
deshalb nur, dass die Dateiendungen als unterstützt gelten – nicht, dass
die Dekodierung tatsächlich klappt.

Für eine echte Prüfung gibt es ein Skript, das Beispieldateien aus
öffentlichen Quellen lädt:

```bash
tool/fetch_format_samples.sh                      # Standardsatz (1 DNG, 1 HEIC)
tool/fetch_format_samples.sh --list Canon         # verfügbare Modelle anzeigen
tool/fetch_format_samples.sh --make Canon --model "EOS R6"
```

Die Dateien landen in `samples/` und sind über `.gitignore` ausgeschlossen.
Anschließend manuell prüfen:

1. `flutter run -d macos`
2. Die Dateien aus `test/fixtures/samples/` importieren
3. Erwartung: Vorschaubild in der Timeline, Vollbildansicht öffnet, und bei
   RAW-Dateien ist „Entwickeln" verfügbar

## Lizenzhinweis zu den geladenen Dateien

Die Beispieldateien werden **nur lokal zum Testen** geladen und bewusst
nicht mit ausgeliefert – ihre Lizenzen unterscheiden sich je Datei:

- **[raw.pixls.us](https://raw.pixls.us/)** – Sammlung von RAW-Beispielen,
  überwiegend CC0, aber nicht ausnahmslos; die Seite führt die nicht-CC0-
  Dateien getrennt auf.
- **[nokiatech/heif_conformance](https://github.com/nokiatech/heif_conformance)** –
  HEIF-Conformance-Dateien. Das Repository enthält **keine Lizenzdatei**;
  die Nutzungsbedingungen sind entsprechend unklar. Für lokale Tests
  unproblematisch, für eine Weiterverbreitung nicht geeignet.

Nach dem Download schreibt das Skript Herkunft und Lizenz jeder Datei in
`samples/HERKUNFT.tsv`.

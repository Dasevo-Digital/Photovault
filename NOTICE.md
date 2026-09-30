# Herkunft und Lizenzen von Drittinhalten

Dieses Projekt selbst steht unter der Lizenz in [LICENSE](LICENSE). Die
folgenden Bestandteile stammen von Dritten und behalten ihre eigene Lizenz.

## Mitgelieferte Dateien

### Globus-Texturen (`assets/globe/`)

| Datei | Quelle | Lizenz |
|---|---|---|
| `2k_earth_daymap.jpg` | [Solar System Scope](https://www.solarsystemscope.com/textures/) | CC BY 4.0 |
| `2k_stars_milky_way.jpg` | [Solar System Scope](https://www.solarsystemscope.com/textures/) | CC BY 4.0 |

> **Erforderliche Namensnennung:** Textures by [Solar System Scope](https://www.solarsystemscope.com/textures/),
> licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Verwendet für den 3D-Globus in der Kartenansicht. Die Herkunft ist belegt:
beide Dateien sind byte-identisch mit den Originalen der „2k"-Reihe
(SHA-256 geprüft gegen `solarsystemscope.com/textures/download/`).

    2k_earth_daymap.jpg      767ee1dc6eb3802699bfccf6f264880f8acd0b80de3191cd24984fe279b07b7c
    2k_stars_milky_way.jpg   ec2240e6f3784d962ab81609b228bfd470e87c86d1fed5e99134d4cd3de24239

### Bildschirmfotos (`docs/screenshots/`)

Die Aufnahmen zeigen eine eigens aufgebaute Demo-Bibliothek. Alle darin
enthaltenen Fotos sind **gemeinfrei** (Public Domain) und stammen von
[Wikimedia Commons](https://commons.wikimedia.org/):

| Motiv | Urheber / Quelle |
|---|---|
| Erdaufnahmen, Apollo-Missionen | NASA (Werke der US-Bundesregierung, gemeinfrei) |
| Landschaften und Architektur | Ansel Adams, National Archives (gemeinfrei) |
| „Migrant Mother" | Dorothea Lange, Farm Security Administration (gemeinfrei) |
| Porträts (Lincoln, Curie, Einstein) | historische Aufnahmen, gemeinfrei |

Aufnahmedaten, Koordinaten und Kameramodelle dieser Demo-Fotos wurden für
die Darstellung gesetzt und sind nicht die historischen Originalangaben.

### App-Symbole

Die Icons unter `assets/icon/`, `macos/Runner/Assets.xcassets/`,
`ios/Runner/Assets.xcassets/` und `android/app/src/main/res/` gehören zu
diesem Projekt bzw. sind die unveränderten Platzhalter aus `flutter create`
(BSD-3-Clause, siehe Flutter SDK).

## Nicht mitgelieferte, aber nachladbare Inhalte

### KI-Modelle

Es wird **kein** Modell mit der App ausgeliefert. Alle Dateien werden auf
Wunsch in der App heruntergeladen (Einstellungen → KI-Modelle); die
Quell-URLs stehen in `lib/services/model_catalog.dart`.

| Modell | Zweck | Lizenz | Quelle |
|---|---|---|---|
| YuNet | Gesichtserkennung | Apache-2.0 | [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_detection_yunet) |
| SFace | Gesichts-Wiedererkennung | Apache-2.0 | [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) |
| CLIP ViT-B/32 | KI-Bildsuche | MIT (OpenAI-Gewichte) | [Xenova/HuggingFace](https://huggingface.co/Xenova/clip-vit-base-patch32) |
| SAM ViT-Base | KI-Objektmasken | Apache-2.0 (Meta Segment Anything) | [Xenova/HuggingFace](https://huggingface.co/Xenova/sam-vit-base) |
| Florence-2 base-ft | Bildbeschreibung | MIT | [onnx-community/HuggingFace](https://huggingface.co/onnx-community/Florence-2-base-ft) |
| OCEC | Geschlossene Augen | MIT | [PINTO0309/OCEC](https://github.com/PINTO0309/OCEC) |
| Real-ESRGAN x4 | KI-Restaurierung | BSD-3-Clause | [SceneWorks/HuggingFace](https://huggingface.co/SceneWorks/real-esrgan-onnx) |
| LaMa | Objektentfernung | Apache-2.0 | [Carve/HuggingFace](https://huggingface.co/Carve/LaMa-ONNX) |
| PaddleOCR | Texterkennung | Apache-2.0 | [PaddlePaddle/HuggingFace](https://huggingface.co/PaddlePaddle/latin_PP-OCRv5_mobile_rec_onnx) |
| OPUS-MT en→de / de→en | Übersetzung | Apache-2.0 | [Xenova/HuggingFace](https://huggingface.co/Xenova) |

### Geodaten

Die Umkehr-Geokodierung nutzt den [GeoNames](https://www.geonames.org/)-
Datensatz `cities1000` (CC BY 4.0), ebenfalls erst auf Anforderung geladen.

### Karten-, Gelände- und Wanderinformationen

Die Kartenansichten können Daten beziehungsweise Kacheln von OpenStreetMap
(ODbL-1.0), OpenTopoMap, CyclOSM, CARTO, Esri/ArcGIS, Mapbox, MapTiler,
Thunderforest und Google Maps laden. Es gelten die Bedingungen und
Namensnennung des jeweils ausgewählten Anbieters. Bei OpenStreetMap ist
zusätzlich die
[Tile-Usage-Policy](https://operations.osmfoundation.org/policies/tiles/)
zu beachten.

Geländeansichten verwenden Höhendaten von AWS Open Data sowie Wanderwege von
Waymarked Trails. Wanderobjekte werden über die Overpass API aus
OpenStreetMap-Daten abgefragt. Die erforderlichen Quellenhinweise werden in
der jeweiligen Ansicht angezeigt.

### Testdateien

`tool/fetch_format_samples.sh` lädt auf Wunsch echte Kameradateien für
manuelle Formatprüfungen. Diese werden **nicht** mit ausgeliefert und sind
je Datei unterschiedlich lizenziert – siehe
[test/fixtures/README.md](test/fixtures/README.md).

## Abhängigkeiten

Die verwendeten Dart-/Flutter-Pakete stehen in `pubspec.yaml`; ihre Lizenzen
lassen sich mit `flutter pub deps` bzw. über pub.dev einsehen.

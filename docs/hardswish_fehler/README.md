# `HardSwish` liefert im Flutter-Prozess unter Linux nur Nullen

Ein ONNX-Modell mit **einem einzigen `HardSwish`-Knoten** gibt in einer
Flutter-Linux-Anwendung durchweg Nullen zurück. Dieselbe Modelldatei,
gerechnet von derselben `libonnxruntime.so` in einem gewöhnlichen
C++-Programm auf derselben Maschine, liefert das richtige Ergebnis.

```
Eingabe   -4      -3      -1      -0,5     0      0,5     1       3
Soll      -0      -0      -0,3333 -0,2083  0      0,2917  0,6667  3
Ist        0       0       0       0       0      0       0       0
```

## Aufgelöst (24.08.2026)

**Es war eine Frage der Spracheinstellung, nicht der Plattform.** ONNX
(≤ 1.22) liest die Rümpfe funktionsdefinierter Operatoren aus ihrer
Textform, mit einem `std::stof`, das der Locale folgt. GTK setzt die
Prozess-Locale aus der Umgebung; unter Komma-Sprachen wie `de_DE` wird
HardSwishs α = 1/6 dabei zu **0**, und der Schritt liefert durchweg null.

Das erklärt auch, warum `Celu` und `Mish` unauffällig blieben, obwohl sie
ebenfalls funktionsdefiniert sind: Ihre Rümpfe enthalten keine gebrochene
Konstante, die falsch gelesen werden könnte.

Und es erklärt, warum macOS nie betroffen war — nicht wegen des Systems,
sondern weil dort `LC_NUMERIC` auf `C` steht und der Swift-Runner die
Prozess-Locale gar nicht erst aus der Umgebung setzt.

Oben: [onnx/onnx#8111](https://github.com/onnx/onnx/issues/8111), behoben
durch [#8112](https://github.com/onnx/onnx/pull/8112) – die Nachbesserung
hat aber weder onnx 1.22.0 noch eine ONNX-Runtime-Veröffentlichung
erreicht. Dieselbe Ursache steckte hinter
[microsoft/DirectML#736](https://github.com/microsoft/DirectML/issues/736),
wo es `Gelu` traf.

**Behoben im Plugin ab `flutter_onnxruntime` 1.8.4** (unser Bericht:
[masicai/flutter_onnxruntime#73](https://github.com/masicai/flutter_onnxruntime/issues/73)).
Es legt `LC_NUMERIC` über `uselocale` fadenlokal auf `C`, solange die
Umgebung und die Sitzung angelegt werden – die Locale der Anwendung selbst
bleibt unangetastet.

Nachgemessen am 24.08. auf der Testmaschine unter `LC_NUMERIC=de_DE.UTF-8`
mit 1.8.4, im echten Flutter-Prozess:

```
hardswish  -0.0000 -0.0000 -0.3333 -0.2083 0.0000 0.2917 0.6667 3.0000
```

Also die Referenzwerte, vorher achtmal null.

**Waren andere Modelle auch betroffen?** Der Plugin-Kommentar nennt
`LayerNormalization` und `Gelu` als weitere Rümpfe, die beim Anlegen der
Sitzung gelesen werden – beide stecken in CLIP, Florence, SAM und der
Übersetzung. Nachgemessen am 24.08. auf derselben deutschen Maschine, ein
CLIP-Text-Embedding für dieselbe Eingabe:

```
1.8.4:  -0.010342 0.018376 0.038650 -0.031528 -0.053567 0.032077 …
1.8.3:  -0.010342 0.018376 0.038650 -0.031528 -0.053567 0.032077 …
```

**Bitgleich.** Dasselbe für die übrigen Modelle, die ihre Ergebnisse
dauerhaft ablegen – gleiches Verfahren, gleiche Maschine, nur die
Plugin-Fassung getauscht:

| | 1.8.3 gegen 1.8.4 |
|---|---|
| Übersetzung en→de | „ein rotes Fahrrad vor einer Steinmauer" – gleich |
| Florence-Bildbeschreibung | „A colorful image of lines in a geometric pattern." – gleich |
| SAM-Bild-Embedding (1.048.576 Werte) | Summe 17748,690397 – gleich |
| Gesichts-Embedding (128 Werte) | Summe −0,019388 – gleich |

ORT hat für `LayerNormalization` und `Gelu` eigene Kerne und nimmt den
Textweg gar nicht erst – anders als bei `HardSwish`, für das keiner
existiert. **Der Schaden blieb auf das Lesemodell beschränkt**; was unter
Linux an Embeddings, Beschreibungen und Übersetzungen in der Datenbank
steht, ist unverdächtig.

Sonden: `integration_test/clip_locale_probe_test.dart` und
`integration_test/locale_modelle_probe_test.dart`. Die zweite berechnet ihr
Prüfbild, statt eine Datei zu laden – es geht nicht darum, ob das Ergebnis
sinnvoll ist, sondern ob zwei Läufe dasselbe ergeben.

**Die Ausschlussliste unten bleibt gültig** – sie war nur nie vollständig
genug, um bis zur Ursache zu reichen. Was fehlte, war der Verdacht auf
etwas ausserhalb des Rechenwegs: eine Textumwandlung.

## Nachstellen

```bash
python3 modelle_bauen.py            # legt nur_*.onnx an (braucht onnx)
flutter create probe && cd probe
flutter pub add flutter_onnxruntime
flutter pub add dev:integration_test --sdk flutter
cp ../hardswish_test.dart integration_test/
flutter test integration_test/hardswish_test.dart -d linux
```

Der Test legt die Modelle unter `$HOME/ocr_modelle/` ab und erwartet sie
dort.

## Umfang

Betroffen ist **nur** `HardSwish`. Im selben Prozess rechnen richtig:
`HardSigmoid`, `Sigmoid`, `Relu`, `Elu`, `Softplus`, `Celu`, `Mish` –
darunter mit `Celu` und `Mish` zwei, die in ONNX ebenfalls über eine
Funktionsdefinition beschrieben sind.

## Was ausgeschlossen wurde

| Verdacht | Prüfung | Ergebnis |
|---|---|---|
| Anbindung des Plugins | eigenständige C++-Inferenz *im* Flutter-Prozess, ohne Plugin-Code | gleicher Fehler |
| Umgebung, Grenzen, Verzeichnis | Kindprozess derselben App | rechnet richtig |
| die Anwendung selbst | blanke `flutter create`-App, nur dieses Plugin | gleicher Fehler |
| Symbolüberlagerung | alle 272 Bibliotheken des Prozesses vorgeladen, ORT zuletzt | ohne Wirkung |
| Rechenfäden | ein Faden, serielle Ausführung; frisch gestarteter Faden | gleicher Fehler |
| Speichermuster, Vorpacken | `DisableMemPattern`, `DisableCpuMemArena`, `session.disable_prepacking` | gleicher Fehler |
| Graphoptimierung | `ORT_DISABLE_ALL` | gleicher Fehler |
| ORT-Fassung | 1.22.0 und 1.23.0 | beide betroffen |
| Grösse des Tensors | 1 bis 1024 Werte | schon bei einem Wert falsch |
| Gleitkomma-Zustand | MXCSR gelesen | 0x1fa0, unauffällig |

## Umgebung

Ubuntu 25.10 (Kernel 7.0), x86-64, Flutter 3.44.8,
`flutter_onnxruntime` 1.8.3, ONNX Runtime 1.22.0 (Linux-x64-Paket des
Plugins), Modelle mit Opset 14.

## Auswirkung

Jedes Modell mit einem MobileNetV3-Stamm ist unbrauchbar. Konkret
betrifft es hier die Texterkennung: Das PP-OCR-Lesemodell enthält
27 `HardSwish`-Knoten; ab dem ersten ist die weitere Rechnung wertlos.
Der Ausgabewert hängt danach weder von den Bilddaten noch von der Form
des Eingabetensors ab – ein Fehlerbild, das leicht als „die Eingabe
kommt nicht an" fehlgedeutet wird.

## Umgehung in dieser App

`HardSwish(x)` ist per ONNX-Definition genau
`x · HardSigmoid(x; α = 1/6, β = 0,5)`, und beide Schritte rechnen
richtig. `lib/services/onnx_hardswish.dart` schreibt die Knoten beim
ersten Laden entsprechend um. Gegengerechnet mit `onnxruntime`: grösste
Abweichung 0,000.

Das behebt den Fehler nicht, es geht ihm aus dem Weg – und nur für dieses
eine Modell. Jedes andere Modell mit MobileNetV3-Stamm ist weiterhin
betroffen.

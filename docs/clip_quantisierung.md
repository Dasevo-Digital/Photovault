# CLIP kleiner machen – was geht und was nicht

21. Prüfrunde. CLIP ist das **einzige unquantisierte Modell im Katalog**:
352 MB Bild-Encoder plus 254 MB Text-Encoder, zusammen 606 MB von 1429 MB
aller Modelle. Alle übrigen Einträge holen ausdrücklich eine
`_quantized`-Fassung; bei CLIP steht kein Grund dafür im Quelltext, dass
es anders ist – es war das erste Modell und wurde nie wieder angefasst.

Bei Xenova liegen sieben Fassungen desselben Modells. Gemessen wurden die
beiden, die etwas ändern würden: `uint8` (quantisiert) und `fp16`.

## Der Aufbau

600 zufällige Aufnahmen der echten Bibliothek (derselbe Zufallsstartwert
wie bei der SigLIP-Messung), dieselbe Vorverarbeitung wie
`aufClipGroesse`. Verglichen wird nicht „welches Modell ist besser",
sondern: **Ändert sich etwas, das in der App sichtbar wird?** Sichtbar
wird der Vektor an drei Stellen, und alle drei hängen an demselben:

1. die Kontext-Suche (Rangfolge Bild gegen Text),
2. die KI-Schlagwörter (Schwelle auf dem Kosinuswert),
3. Duplikate und Serien (Schwelle 0,92 auf Bild gegen Bild).

Werkzeug: `tool/siglip_vergleich/clipq_vergleich.py`, `clipf16.py`,
`coreml_test.py`, `text_test.py`.

## uint8: verworfen

```
Kosinus fp32 <-> uint8, je Bild    Median 0,9236   min 0,7198
```

Das klingt nach „fast gleich" und ist es nicht. Zwei **verschiedene**
Fotos dieser Bibliothek liegen im Median bei 0,477. Ein Wert von 0,92
zwischen zwei Fassungen **desselben** Fotos ist auf dieser Skala weit
weg – so weit, dass die Schwellen ins Leere greifen:

| Paare über der Schwelle | fp32 | uint8 |
|---|---|---|
| 0,92 (Duplikate/Serien) | 103 | 52 |
| 0,95 | 10 | 5 |
| 0,97 | 1 | 2 |

Die Duplikatsuche fände die Hälfte. Und die Suche ändert sich sichtbar:
über zehn Fragen stimmen nur **37 von 60** der ersten sechs Treffer
überein, bei „a screenshot" 1 von 6.

Dazu kommt: uint8 ist **nicht schneller** (20,0 statt 16,8 ms je Bild).
Die Rechnung läuft weiterhin in Gleitkomma, das Modell wird nur beim
Laden entpackt.

> 452 MB gespart, dafür jede Schwelle neu zu eichen und 7548
> Einbettungen neu zu rechnen. Dieselbe Rechnung wie bei SigLIP, mit
> demselben Ergebnis.

## fp16: kostenlos in der Sache, teuer in der Zeit

```
Kosinus fp32 <-> fp16, Bild        Median 0,999999   min 0,999993
Kosinus fp32 <-> fp16, Text        1,000000 bei allen sechs Fragen
```

Nicht unterscheidbar. Alle drei Schwellen liefern **dieselbe Zahl**
(103/103, 10/10, 1/1), und die Suche liefert dieselbe Rangfolge:
**60 von 60** der ersten sechs, 199 von 200 der ersten zwanzig.

Der Punkt, der das interessant macht: **die vorhandenen 7548
Einbettungen bleiben gültig.** Ein Wechsel kostet keine Neuberechnung.

Der Preis ist Rechenzeit, denn die CPU rechnet fp16 nicht selbst –
ONNX Runtime wandelt vor jeder Rechenstufe:

| | Platte | je Bild bzw. je Suche |
|---|---|---|
| Bild-Encoder fp32 | 352 MB | 16,8 ms |
| Bild-Encoder fp16 | 176 MB | 27,0 ms |
| Text-Encoder fp32 | 254 MB | 12,5 ms |
| Text-Encoder fp16 | 127 MB | 17,9 ms |

Daraus folgt für die beiden Hälften Verschiedenes:

- **Der Text-Encoder ist der klare Fall.** Er läuft, wenn jemand eine
  Suche eintippt – einmal, und 5 ms mehr sieht kein Mensch. 127 MB für
  nichts.
- **Beim Bild-Encoder ist es eine Abwägung.** Er läuft einmal je
  Aufnahme in der Hintergrundanalyse; über eine Bibliothek dieser Grösse
  sind das rund 75 Sekunden mehr, einmalig. Dafür 176 MB.

## CoreML: gemessen und verworfen

Naheliegender Verdacht, weil Real-ESRGAN im Katalog mit 4,8 s gegen
20,1 s ausdrücklich danach fragt und CLIP gar keine Anbieter angibt –
und ohne Angabe hängt `flutter_onnxruntime` **keinen CoreML-Anbieter
an**, es bleibt bei reiner CPU.

Gemessen bringt es nichts:

```
Bild-Encoder fp32   CPU 16,8 ms   CoreML 17,1 ms
Bild-Encoder fp16   CPU 27,0 ms   CoreML 27,0 ms
```

Real-ESRGAN ist ein Faltungsnetz auf grossen Kacheln, CLIP ViT-B/32 ein
Aufmerksamkeitsnetz auf 224×224. Was dem einen hilft, hilft dem anderen
nicht. **Kein Posten.**

## Der Haken, der beide Vorschläge betraf – und was daraus wurde

`ModelDownloadService.isEntryInstalled` prüfte ausschliesslich, ob die
Datei **da ist**:

```dart
entry.files.every((f) => File(p.join(modelsDir, f.fileName)).existsSync());
```

Eine geänderte Adresse und Prüfsumme im Katalog hätte damit nur
Neuinstallationen erreicht. Wer die Modelle schon hatte, wäre für immer
bei fp32 geblieben – ohne Hinweis. Und die Lücke, die der Katalog selbst
beschreibt (die Prüfsumme schütze vor „stillschweigend veränderten
Downloads"), bestand genau so lange, wie eine Datei liegt: Geprüft wurde
einmal, beim Herunterladen.

Beides ist behoben, in zwei Stufen:

- **`ModelFile.bytes`** – die erwartete Länge, nicht abgetippt, sondern
  aus den Kopfzeilen der Auslieferung geholt und gegen alle 23
  installierten Dateien gegengelesen (bei HuggingFace steht in
  `x-linked-etag` genau die SHA-256, was Länge und Prüfsumme in einem Zug
  bestätigt). `isEntryInstalled` vergleicht sie. Kostet ein `stat` und
  fängt zwei Fälle: die abgeschnittene Übertragung und die veraltete
  Fassung.
- **„Modelle nachrechnen"** in den Einstellungen – rechnet jede
  Prüfsumme neu. Der Fall, den allein das findet: richtige Länge,
  falscher Inhalt.

Nachrechnen kostet 1,12 s für die 606 MB von CLIP, rund 2,6 s für alle
Modelle – zu viel für jeden Start, wenig genug für einen Knopf.

## Was daraus geworden ist

**Der Katalog steht seit der 21. Prüfrunde auf fp16**, beide Encoder.
Beim nächsten Blick in die Einstellungen meldet die App die alten
352-MB- und 254-MB-Dateien als falsch lang und bietet sie neu an;
303 MB weniger, danach.

Die gespeicherten Einbettungen bleiben gültig und werden nicht angefasst
– das ist der Grund, warum dieser Tausch überhaupt vertretbar ist.

## Was das nicht heisst

Nicht, dass jede kleinere Fassung besser ist. uint8 spart dreimal so
viel und ist gemessen unbrauchbar. Der Unterschied zwischen den beiden
liegt nicht in der Ersparnis, sondern darin, dass fp16 dieselbe Zahl
liefert und uint8 eine andere.

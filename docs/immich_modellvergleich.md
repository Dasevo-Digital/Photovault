# Dieselben Modelle wie Immich?

Drei Fragen aus der Wunschliste vom 02.09.2026:

> 19. KI: Clip:ViT-B-32__openai – wie immich?
> 20. KI: Gesichtserkennung: Buffalo_l?
> 21. KI: siehe <https://huggingface.co/immich-app>

Nachgemessen, nicht nachgeschlagen.

---

## 19. CLIP: ja, dasselbe Modell – und unsere Fassung ist die richtige

Photo Vault lädt CLIP ViT-B/32 als ONNX-Ausfuhr von
[Xenova/clip-vit-base-patch32](https://huggingface.co/Xenova/clip-vit-base-patch32),
Immich seine eigene aus
[immich-app/ViT-B-32__openai](https://huggingface.co/immich-app/ViT-B-32__openai).
Beide gehen auf dieselben OpenAI-Gewichte zurück. Schon die Dateigrössen
liegen dicht beieinander:

```
Bild-Encoder    unser 351.685.709 B    immich 351.613.724 B
Text-Encoder    unser 254.058.553 B    immich 254.193.396 B
```

**Die Gewichte sind bitgleich.** Von den grossen Tensoren stimmen 116
Byte für Byte überein; der Rest unterscheidet sich nur in der
*Verpackung*: Die HuggingFace-Ausfuhr führt die Aufmerksamkeit als drei
getrennte Matrizen (je 768×768), die OpenCLIP-Ausfuhr als eine
zusammengefasste (768×2304). Dieselben Zahlen, anders sortiert. Die
Bildeinbettungs-Matrix (`visual.proj` bzw. `onnx::MatMul_1859`) und die
Patch-Gewichte weichen um **0** ab.

**Trotzdem kamen verschiedene Einbettungen heraus** – Kosinus 0,952 bis
0,966 auf denselben Eingaben. Die Ursache steht im Graphen:

```
unser    Sigmoid × 12      → QuickGELU,  x · σ(1,702 x)
immich   Erf     × 12      → GELU (exakt)
```

Der Faktor 1,702 ist nachgesehen, nicht vermutet. **OpenAI hat CLIP mit
QuickGELU trainiert**; OpenCLIP hat seine Vorgabe später auf `nn.GELU`
umgestellt und führt die passenden Bauformen unter dem Namenszusatz
`-quickgelu`. Wer die OpenAI-Gewichte in die Bauform ohne diesen Zusatz
lädt, bekommt eine Genauigkeitseinbusse
([open_clip#441](https://github.com/mlfoundations/open_clip/issues/441)).
Genau das ist hier passiert.

**Die Gegenprobe.** Ich habe in Immichs Graphen die zwölf GELU-Blöcke
gegen QuickGELU getauscht und erneut verglichen:

```
                          unser ↔ immich
mit GELU (wie geliefert)        0,952 … 0,966
mit QuickGELU (getauscht)       0,99999988 … 1,00000012
```

Damit ist es entschieden: **ein und dasselbe Modell**, und der
Unterschied liegt allein in der Aktivierung der Ausfuhr. Unsere ist die,
die zu den Gewichten passt.

Zu tun ist also nichts. Was Immich darüber hinaus anbietet, sind
**andere** Modelle – SigLIP2, mehrsprachige NLLB-CLIP-Varianten. Die
mehrsprachige Spur wurde in der 2. Auflage der Stufe 2 schon einmal
gemessen und verworfen, SigLIP in `siglip_messung.md`.

## 20. Gesichter: buffalo_l wäre besser – und teurer, als es aussieht

Heute im Einsatz (beide OpenCV Zoo, **Apache-2.0**):

| | Datei | Grösse | Einbettung |
|---|---|---|---|
| Finden | YuNet 2023mar | 0,23 MB | – |
| Wiedererkennen | SFace 2021dec | 38,7 MB | **128** Zahlen |

Immichs buffalo_l (InsightFace):

| | Datei | Grösse | Einbettung |
|---|---|---|---|
| Finden | RetinaFace-10GF | 16,9 MB | – |
| Wiedererkennen | ResNet50 @ WebFace600K | 174,4 MB | **512** Zahlen |

InsightFace nennt für das Erkennungsmodell LFW 99,83 %, CFP-FP 99,33 %,
IJB-C(E4) 97,25 % – deutlich über dem, was SFace erreicht. Der Preis
steht daneben:

* **Vierfache Modellgrösse.** 191 MB statt 39 MB im Auslieferungspaket
  bzw. im Download.
* **Alle gespeicherten Gesichter werden ungültig.** 128 Zahlen und 512
  Zahlen sind nicht dasselbe Koordinatensystem; es gibt keine
  Umrechnung. In der Produktivbibliothek betrifft das **18.386
  Gesichter**, davon 2.471 einer Person zugeordnet, auf 8.096
  durchsuchten Aufnahmen. Ein vollständiger Neulauf, und die
  Zuordnungen müssten mitgenommen werden (die Person hängt am Gesicht,
  nicht an der Einbettung – das ginge, aber es ist Arbeit).
* **Die Schwelle stimmt nicht mehr.** 0,363 ist der für SFace
  dokumentierte Wert; ArcFace liegt anderswo.
* **Die Lizenz.** InsightFace stellt seine vortrainierten Modelle
  ausdrücklich *„for non-commercial research purposes only"* bereit.
  Photo Vault liefert bisher ausschliesslich Apache-2.0 und MIT aus.
  Das ist kein technisches, sondern ein grundsätzliches Hindernis.

### An deinen Gesichtern nachgemessen

Nicht an LFW, sondern an den **1.053 von Hand zugeordneten Gesichtern**
dieser Bibliothek (43 Personen; nur Aufnahmen, die Python direkt öffnen
kann, also JPEG und PNG – 1.318 kamen infrage). Jedes Modell mit seiner
eigenen Ausrichtung: SFace mit den gespeicherten Einbettungen aus der
Datenbank, ArcFace mit den Landmarken, die buffalos eigener Erkenner
liefert. Verglichen werden **alle** Paare: 71.385 gleiche Person,
482.493 verschiedene.

```
                      gleiche Person   verschiedene    AUC     beste
                                                             Genauigkeit
SFace   (heute)       0,335 ± 0,188    0,119 ± 0,109   0,8364   0,9099
buffalo (ArcFace)     0,417 ± 0,187    0,028 ± 0,066   0,9720   0,9717
```

**Die Fehlerrate (1 − AUC) fällt von 16,4 % auf 2,8 %** – ein Faktor
5,8. An der jeweils besten Schwelle:

```
SFace   bei 0,383   39,4 % der gleichen erkannt,  1,38 % falsch zusammengelegt
buffalo bei 0,220   84,3 % der gleichen erkannt,  0,93 % falsch zusammengelegt
```

Und an der **eingestellten** Schwelle 0,363, die heute wirklich läuft:
43,0 % der gleichen Person erkannt, 2,00 % falsch zusammengelegt. Das
ist die Zahl hinter dem Gefühl, dass „Ähnliche mit auswählen" oft nur
einen Teil findet.

### Aber: der Erkenner findet nicht alles

Bevor ArcFace überhaupt rechnen kann, muss buffalos eigener Erkenner
(SCRFD-10G) das Gesicht finden. Von den 1.318 zugeordneten Gesichtern
fand er bei Eingabegrösse 640 nur 1.057 – **261 nicht**, knapp 20 %. Und
zwar nicht die kleinen:

```
Gesichtsbreite als Anteil der Bildbreite     Gesichter   verfehlt
0,00 – 0,05                                        268    36  (13 %)
0,05 – 0,10                                        343    50  (15 %)
0,10 – 0,20                                        299    64  (21 %)
0,20 – 0,40                                        275    79  (29 %)
0,40 – 1,00                                        133    32  (24 %)
```

Bei 174 der 261 lag überhaupt kein Kasten in der Nähe. Eine grössere
Eingabe machte es **schlechter**, nicht besser (22,5 % bei 1024) – was
zum Bild passt: SCRFD ist auf Gesichter bis zu einer bestimmten Grösse
im Eingabebild angelegt, und eine grössere Eingabe macht die Gesichter
darin grösser.

**Ehrlich zur Aussagekraft:** Das ist *meine* Umsetzung von SCRFD
(Letterbox auf 640, Schwelle 0,5, eigenes NMS), nicht InsightFace' eigene
Pipeline. Ein Teil der 261 mag an ihr liegen; ein Teil sind vermutlich
von Hand eingezeichnete Kästen, die gar kein Erkenner je gefunden hat.
Die **Wiedererkennung** oben ist davon unberührt – sie rechnet nur auf
den 1.053 Gesichtern, die beide Wege kennen.

### Was das zusammen heisst

Die Wiedererkennung ist der Grund, warum man wechseln würde, und sie
gewinnt deutlich. Das Finden ist der Grund, warum es kein Austausch von
zwei Dateien ist: Der Erkenner müsste eigens abgeglichen werden, sonst
tauscht man einen schlechteren Vergleicher gegen ein schlechteres
Finden.

**Offen und nicht entschieden.** Die Genauigkeit spricht dafür, die
Lizenz dagegen, der Neulauf über 18.386 Gesichter ist nichts, was
nebenbei passiert – und der Erkenner wäre eine eigene Arbeit.

## 21. Was es bei immich-app sonst gibt

| Familie | Was |
|---|---|
| Gesichter | buffalo_s / buffalo_m / **buffalo_l** / antelopev2 (alle InsightFace) |
| CLIP | ViT-B-32__openai, ViT-B-32__laion2b-s34b-b79k |
| SigLIP | ViT-B-16-SigLIP__webli, ViT-B-16-SigLIP2__webli, ViT-SO400M-16-SigLIP2-384__webli |
| Mehrsprachig | nllb-clip-base/large-siglip, XLM-Roberta-Large-ViT-H-14 |

Jede Ablage enthält dieselben Gewichte in mehreren Fassungen: `model.onnx`
(fp32), `fp16/model.armnn`, `rknpu/rk35xx/model.rknn`. Die beiden
letzten sind für ARM-Beschleuniger und Rockchip-NPUs – für uns ohne
Belang.

**Ein Hinweis zur fp16-Spur.** Immich liefert fp16 nur als `.armnn` aus,
nicht als ONNX. Das passt zu dem, was uns am 30.08. zwei Tage lang die
Suche gekostet hat: Die mitgelieferte ONNX Runtime 1.23 lädt fp16-CLIP
auf der CPU nicht (siehe `project_clip_fp16_ausfall`).

---

*Gemessen am 02.09.2026 mit ONNX Runtime 1.19.2. Der CLIP-Vergleich
läuft auf synthetischen Eingaben; die Gesichtsmessung auf der echten
Bibliothek, aber vollständig auf diesem Rechner – kein Bild und keine
Einbettung hat ihn verlassen.*

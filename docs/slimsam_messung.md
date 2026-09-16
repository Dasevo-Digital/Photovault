# SlimSAM statt SAM ViT-Base – gemessen

21. Prüfrunde. Die KI-Objektmasken im Entwickeln-Bildschirm laufen auf
SAM ViT-Base (quantisiert), 106 MB. SlimSAM-77 ist dasselbe Modell,
beschnitten auf 77 % weniger Gewichte – und liegt beim **selben
Anbieter** (Xenova), also auf derselben Vertrauensbasis wie der
vorhandene Export.

## Es ist ein Austausch ohne Umbau

Die Ein- und Ausgabetensoren sind **Zeichen für Zeichen dieselben** –
real gegen die heruntergeladenen Dateien geprüft, nicht angenommen:

```
Encoder  pixel_values [b,3,1024,1024]
      -> image_embeddings, image_positional_embeddings  [b,256,64,64]
Decoder  input_points [b,p,n,2], input_labels [b,p,n],
         image_embeddings, image_positional_embeddings
      -> iou_scores [b,p,3], pred_masks [b,p,3,256,256]
```

Für `SegmentationService` ändert sich damit nichts ausser zwei Adressen
und zwei Prüfsummen im Katalog.

## Die Zahlen

20 echte Fotos, je drei Klicke, dieselben Klickpunkte für beide Modelle:

| | SAM ViT-B | SlimSAM-77 |
|---|---|---|
| Platte | 106 MB | **14 MB** |
| je Klick (Encoder + Decoder) | 2192 ms | **468 ms** |
| Überdeckung der Masken (IoU) | Median 0,924, Mittel 0,815 | |
| davon unter 0,5 | 8 von 60 | |

Der Zeitgewinn ist der eigentliche Punkt: Eine Maske entsteht auf einen
Klick hin, und zwei Sekunden Warten sind an dieser Stelle das, was den
Unterschied zwischen „Werkzeug" und „Zumutung" ausmacht.

## Die Sichtprüfung, die das entscheiden sollte

Die Klicke oben waren willkürlich gesetzt (Mitte, ein Drittel, zwei
Drittel). Ein Klick ins Nichts hat keine richtige Antwort, und dort
dürfen zwei Modelle auseinanderlaufen – die Vermutung war also, dass
gezielte Klicke die Abweichung erklären würden.

**Sie tun das Gegenteil.** Zwölf Klicke auf den Mittelpunkt eines
Gesichtsrahmens aus der Datenbank:

| | willkürlich (60 Klicke) | gezielt (12 Klicke) |
|---|---|---|
| IoU Median | 0,924 | 0,809 |
| IoU Mittel | 0,815 | 0,680 |
| unter 0,5 | 8 von 60 (13 %) | **3 von 12 (25 %)** |

Und die Bilder nebeneinander zeigen, was die Zahl verschweigt:

- **Wo der Klick eindeutig ist, sind beide brauchbar.** Bei einem Klick
  mitten auf ein Gesicht wählen beide Kopf und Schultern, IoU 0,93.
- **Wo er auf einer Kante liegt, wählen sie Verschiedenes** – aber das
  täte SAM gegen sich selbst mit einem um zehn Pixel verschobenen Klick
  ebenso. Zwei der drei schwachen Fälle sind von dieser Art. (Mein
  Klickpunkt lag dort daneben, weil die Gesichtsrahmen in der Datenbank
  im ungedrehten Koordinatensystem stehen und das Foto gedreht war.)
- **SlimSAMs Ränder sind sichtbar gröber.** Auch dort, wo beide dasselbe
  meinen, franst die Kante aus – treppenförmig statt der Kontur folgend.

Der letzte Punkt ist der, der zählt. Diese Masken sind kein Selbstzweck:
Sie tragen örtliche Regler im Entwickeln-Bildschirm. Eine ausgefranste
Kante wird dort zum Saum um die Person – sichtbar genau in dem Moment,
in dem jemand die Belichtung nur eines Bereichs anhebt.

## Empfehlung: nicht tauschen, notiert lassen

468 statt 2192 ms sind ein echter Gewinn, und 14 statt 106 MB auch. Sie
kaufen aber eine schlechtere Kante in einem Werkzeug, dessen ganzer Zweck
die Kante ist. Solange die Masken das tun, was sie heute tun, wiegt das
schwerer als die Wartezeit.

Wieder hervorholen, wenn eines von beidem eintritt:

- Die Masken bekommen eine Kantenverfeinerung (Weichzeichnen des
  Übergangs, Anlehnen an Kanten im Bild). Dann ist der gröbere Ausgang
  weniger wert und die Zeit mehr.
- Die zwei Sekunden werden zum eigentlichen Ärgernis – etwa weil jemand
  auf einem Bild zehnmal klickt.

## Werkzeug

`tool/siglip_vergleich/slimsam_test.py` (willkürliche Klicke, nur Zahlen)
und `slimsam_sicht.py` (gezielte Klicke, schreibt Kontaktabzüge). Die
Abzüge zeigen **echte Fotos** und gehören nirgendwo hin, wo sie jemand
anders sieht – sie landen unter `~/Desktop/pv_slimsam` und nicht im
Repository. Die Modelldateien sind nicht mitgeliefert:

```sh
B=https://huggingface.co/Xenova/slimsam-77-uniform/resolve/main/onnx
mkdir slim && cd slim
curl -sSLO $B/vision_encoder_quantized.onnx
curl -sSLO $B/prompt_encoder_mask_decoder_quantized.onnx
```

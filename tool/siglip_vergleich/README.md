# CLIP ViT-B/32 gegen SigLIP 2 Base

Das Messgerät zu der Frage, ob sich der Modelltausch lohnt, den die
6. Vergleichsauflage vorgeschlagen hat. **Ergebnis: nein** – siehe
`docs/siglip_messung.md`. Die Skripte bleiben liegen, damit sich die
Messung wiederholen lässt, wenn ein kleineres mehrsprachiges Modell
auftaucht.

Kein Teil der App. Läuft ausserhalb, gegen die ONNX-Dateien, die die App
ohnehin heruntergeladen hat, und gegen eine Kopie der Bibliothek.

```
python3 -m venv venv
./venv/bin/pip install numpy pillow onnxruntime tokenizers

# SigLIP 2 holen (1,5 GB) – nicht mitgeliefert
mkdir siglip && cd siglip
B=https://huggingface.co/onnx-community/siglip2-base-patch16-256-ONNX/resolve/main
curl -sSLO $B/tokenizer.json
curl -sSL -o vision_model.onnx $B/onnx/vision_model.onnx
curl -sSL -o text_model.onnx   $B/onnx/text_model.onnx
cd ..

./venv/bin/python einbetten.py   # beide Modelle über 600 echte Fotos
./venv/bin/python suchen.py      # sechs Fragen, drei Reihen je Blatt
```

`suchen.py` schreibt Kontaktabzüge mit **echten Fotos**. Die gehören
nirgendwo hin, wo sie jemand anders sieht – nicht ins Repository und
nicht in den Spiegel.

`einbetten.py` erwartet `lib3.sqlite` (eine Kopie der Bibliothek) neben
sich und liest die Bilddateien aus `~/Pictures/Photo_Vault_Productive`.

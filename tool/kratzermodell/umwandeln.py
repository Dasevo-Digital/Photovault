"""Wandelt das Kratzer-Erkennungsnetz aus „Bringing Old Photos Back to Life"
(Microsoft, MIT-Lizenz) in die ONNX-Datei um, die Photo Vault lädt.

Aufruf (Python 3.9+, mit torch, onnx, onnxconverter-common, onnxruntime):

    python3 tool/kratzermodell/umwandeln.py <arbeitsordner>

Was geschieht:
  1. Aus dem 2 GB grossen Archiv der Autoren wird per HTTP-Range nur der
     eine Eintrag `checkpoints/detection/FT_Epoch_latest.pt` (452 MB)
     geholt – der Rest sind Netze, die hier niemand braucht.
  2. Der Netzcode kommt aus dem Repository der Autoren, auf einen Commit
     festgelegt. Die Batch-Normierung für mehrere Grafikkarten wird durch
     die gewöhnliche ersetzt; die Gewichte bleiben dieselben.
  3. Export mit freier Höhe und Breite, Prüfung gegen PyTorch, dann
     float16 mit float32 an Ein- und Ausgang.

Die Gewichte werden mit `weights_only=True` geladen: Die Datei ist ein
Pickle, und ein Pickle aus dem Netz darf keinen Code ausführen.
"""
import hashlib, os, struct, sys, urllib.request, zlib

ARCHIV = "https://github.com/microsoft/Bringing-Old-Photos-Back-to-Life/releases/download/v1.0/global_checkpoints.zip"
EINTRAG = "checkpoints/detection/FT_Epoch_latest.pt"
GEWICHTE_SHA256 = "b2d7ab04e9b3885c6b1991bb7a0b823129dd6e3ac078a9fd059ebd2a7ba59a95"
COMMIT = "33875eccf4ebcd3665cf38cc56f3a0ce563d3a9c"
CODE = f"https://raw.githubusercontent.com/microsoft/Bringing-Old-Photos-Back-to-Life/{COMMIT}/Global/detection_models/"


def hole(a, b):
    r = urllib.request.Request(ARCHIV, headers={"Range": f"bytes={a}-{b}"})
    return urllib.request.urlopen(r).read()


def eintrag_laden(name, ziel):
    n = int(urllib.request.urlopen(urllib.request.Request(ARCHIV, method="HEAD")).headers["Content-Length"])
    ende = hole(n - 65536, n - 1)
    eocd = ende[ende.rfind(b"PK\x05\x06"):]
    _, cd_groesse, cd_ofs = struct.unpack("<HII", eocd[10:20])
    if cd_ofs == 0xFFFFFFFF:
        z64 = ende[ende.rfind(b"PK\x06\x06"):]
        _, cd_groesse, cd_ofs = struct.unpack("<QQQ", z64[32:56])
    cd = hole(cd_ofs, cd_ofs + cd_groesse - 1)
    p = 0
    while cd[p:p + 4] == b"PK\x01\x02":
        meth, = struct.unpack("<H", cd[p + 10:p + 12])
        csize, usize = struct.unpack("<II", cd[p + 20:p + 28])
        nl, el, kl = struct.unpack("<HHH", cd[p + 28:p + 34])
        lofs, = struct.unpack("<I", cd[p + 42:p + 46])
        eigen = cd[p + 46:p + 46 + nl].decode()
        extra = cd[p + 46 + nl:p + 46 + nl + el]
        q = 0
        while q < len(extra):
            hid, hl = struct.unpack("<HH", extra[q:q + 4]); d = extra[q + 4:q + 4 + hl]; k = 0
            if hid == 1:
                if usize == 0xFFFFFFFF: usize, = struct.unpack("<Q", d[k:k + 8]); k += 8
                if csize == 0xFFFFFFFF: csize, = struct.unpack("<Q", d[k:k + 8]); k += 8
                if lofs == 0xFFFFFFFF: lofs, = struct.unpack("<Q", d[k:k + 8]); k += 8
            q += 4 + hl
        if eigen == name:
            lk = hole(lofs, lofs + 29); nl2, el2 = struct.unpack("<HH", lk[26:30])
            roh = hole(lofs + 30 + nl2 + el2, lofs + 30 + nl2 + el2 + csize - 1)
            daten = roh if meth == 0 else zlib.decompress(roh, -15)
            assert len(daten) == usize
            open(ziel, "wb").write(daten)
            return
        p += 46 + nl + el + kl
    raise SystemExit(f"{name} nicht im Archiv")


def sha(pfad):
    h = hashlib.sha256()
    with open(pfad, "rb") as f:
        for teil in iter(lambda: f.read(1 << 20), b""):
            h.update(teil)
    return h.hexdigest()


def main():
    ordner = sys.argv[1]
    os.makedirs(os.path.join(ordner, "detection_models"), exist_ok=True)
    gewichte = os.path.join(ordner, "FT_Epoch_latest.pt")
    if not os.path.exists(gewichte):
        eintrag_laden(EINTRAG, gewichte)
    assert sha(gewichte) == GEWICHTE_SHA256, "Gewichte weichen ab"
    for datei in ["networks.py", "antialiasing.py"]:
        code = urllib.request.urlopen(CODE + datei).read().decode()
        code = code.replace(
            "from detection_models.sync_batchnorm import DataParallelWithCallback",
            "DataParallelWithCallback = None",
        )
        open(os.path.join(ordner, "detection_models", datei), "w").write(code)
    open(os.path.join(ordner, "detection_models", "__init__.py"), "w").close()

    import numpy as np, onnx, onnxruntime as ort, torch
    from onnxconverter_common import float16
    sys.path.insert(0, ordner)
    from detection_models import networks
    netz = networks.UNet(in_channels=1, out_channels=1, depth=4, conv_num=2, wf=6, padding=True,
                         batch_norm=True, up_mode="upsample", with_tanh=False, sync_bn=False, antialiasing=True)
    fehlend, zuviel = netz.load_state_dict(
        torch.load(gewichte, map_location="cpu", weights_only=True)["model_state"], strict=False)
    assert not fehlend and not zuviel, (fehlend, zuviel)
    netz.eval()
    fp32 = os.path.join(ordner, "kratzererkennung_fp32.onnx")
    torch.onnx.export(netz, torch.zeros(1, 1, 256, 384), fp32, input_names=["input"], output_names=["logits"],
                      dynamic_axes={"input": {2: "h", 3: "w"}, "logits": {2: "h", 3: "w"}},
                      opset_version=17, dynamo=False)
    fp16 = os.path.join(ordner, "kratzererkennung_fp16.onnx")
    onnx.save(float16.convert_float_to_float16(onnx.load(fp32), keep_io_types=True), fp16)

    x = np.random.default_rng(1).random((1, 1, 512, 768), dtype=np.float32) * 2 - 1
    with torch.no_grad():
        soll = torch.sigmoid(netz(torch.from_numpy(x))).numpy() >= 0.4
    ist = ort.InferenceSession(fp16).run(None, {"input": x})[0]
    gleich = float(((1 / (1 + np.exp(-ist)) >= 0.4) == soll).mean())
    print(f"Maske fp16 = PyTorch: {gleich * 100:.3f} %")
    print(f"{fp16}\n  {os.path.getsize(fp16)} Bytes\n  sha256 {sha(fp16)}")


if __name__ == "__main__":
    main()

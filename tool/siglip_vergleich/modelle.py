"""Vergleicht CLIP ViT-B/32 (wie in der App) gegen SigLIP 2 Base an echten Fotos."""
import json, os, sqlite3, sys, random
import numpy as np, onnxruntime as ort
from PIL import Image
from tokenizers import Tokenizer

MODELLE = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                             'Application Support/com.example.photoVault/PhotoVault/models')
LIB = os.path.expanduser('~/Pictures/Photo_Vault_Productive/library')
opt = ort.SessionOptions(); opt.log_severity_level = 3

# ---------------------------------------------------------------- CLIP
clip_bild = ort.InferenceSession(f'{MODELLE}/clip_image_encoder.onnx', opt)
clip_text = ort.InferenceSession(f'{MODELLE}/clip_text_encoder.onnx', opt)
CLIP_MEAN = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
CLIP_STD  = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)

def clip_vorbereiten(bild):
    # Kurze Seite auf 224, dann Mitte beschneiden – wie aufClipGroesse.
    w, h = bild.size
    s = 224 / min(w, h)
    bild = bild.resize((max(224, round(w*s)), max(224, round(h*s))), Image.BICUBIC)
    w, h = bild.size
    l, o = (w-224)//2, (h-224)//2
    a = np.asarray(bild.crop((l, o, l+224, o+224)).convert('RGB'), dtype=np.float32)/255.0
    return np.transpose((a - CLIP_MEAN)/CLIP_STD, (2,0,1))[None].astype(np.float32)

# CLIP-BPE über die Vokabeldateien der App
clip_tok = Tokenizer.from_pretrained('openai/clip-vit-base-patch32')

def clip_textvektor(satz):
    ids = clip_tok.encode(satz).ids[:77]
    ids = ids + [0]*(77-len(ids))
    e = clip_text.get_inputs()[0].name
    v = clip_text.run(None, {e: np.array([ids], dtype=np.int64)})[0][0]
    return v/np.linalg.norm(v)

# ---------------------------------------------------------------- SigLIP 2
sig_bild = ort.InferenceSession('siglip/vision_model.onnx', opt)
sig_text = ort.InferenceSession('siglip/text_model.onnx', opt)
sig_tok = Tokenizer.from_file('siglip/tokenizer.json')

def sig_vorbereiten(bild):
    a = np.asarray(bild.convert('RGB').resize((256,256), Image.BILINEAR), dtype=np.float32)/255.0
    return np.transpose((a-0.5)/0.5, (2,0,1))[None].astype(np.float32)

def sig_textvektor(satz):
    # SigLIP: kleingeschrieben, feste Länge 64, mit <pad> aufgefüllt.
    # Der Zerleger fuellt selbst auf 64 auf und haengt <eos> an; <pad> ist 0.
    ids = sig_tok.encode(satz.lower()).ids[:64]
    ids = ids + [0]*(64-len(ids))
    e = sig_text.get_inputs()[0].name
    v = sig_text.run(None, {e: np.array([ids], dtype=np.int64)})[1][0]
    return v/np.linalg.norm(v)

if __name__ == '__main__':
    print('CLIP  Bild ', [(i.name, i.shape) for i in clip_bild.get_inputs()],
          '->', [(o.name, o.shape) for o in clip_bild.get_outputs()])
    print('CLIP  Text ', [(i.name, i.shape) for i in clip_text.get_inputs()],
          '->', [(o.name, o.shape) for o in clip_text.get_outputs()])
    print('SigLIP Bild', [(i.name, i.shape) for i in sig_bild.get_inputs()],
          '->', [(o.name, o.shape) for o in sig_bild.get_outputs()])
    print('SigLIP Text', [(i.name, i.shape) for i in sig_text.get_inputs()],
          '->', [(o.name, o.shape) for o in sig_text.get_outputs()])

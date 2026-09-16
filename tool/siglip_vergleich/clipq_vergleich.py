"""fp32-CLIP (ausgeliefert) gegen quantisiertes CLIP – an echten Fotos.

Die Frage ist nicht „welches ist besser", sondern: Aendert die Quantisierung
etwas, das in der App sichtbar wird? Sichtbar wird sie an drei Stellen, und
alle drei haengen am selben Vektor:
  1. die Kontext-Suche (Rangfolge Bild/Text)
  2. die KI-Schlagwoerter (Schwelle auf dem Kosinuswert)
  3. Duplikate/Serien (Schwelle 0,92 auf Bild/Bild)
"""
import os, sqlite3, random, time, json
import numpy as np, onnxruntime as ort
from PIL import Image
from tokenizers import Tokenizer

MODELLE = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                             'Application Support/com.example.photoVault/PhotoVault/models')
LIB = os.path.expanduser('~/Pictures/Photo_Vault_Productive/library')
MEAN = np.array([0.48145466, 0.4578275, 0.40821073], dtype=np.float32)
STD  = np.array([0.26862954, 0.26130258, 0.27577711], dtype=np.float32)
opt = ort.SessionOptions(); opt.log_severity_level = 3

def vorbereiten(bild):
    w, h = bild.size
    s = 224 / min(w, h)
    bild = bild.resize((max(224, round(w*s)), max(224, round(h*s))), Image.BICUBIC)
    w, h = bild.size
    l, o = (w-224)//2, (h-224)//2
    a = np.asarray(bild.crop((l, o, l+224, o+224)).convert('RGB'), dtype=np.float32)/255.0
    return np.transpose((a - MEAN)/STD, (2,0,1))[None].astype(np.float32)

bild32 = ort.InferenceSession(f'{MODELLE}/clip_image_encoder.onnx', opt)
bildq  = ort.InferenceSession('clipq/vision_model_quantized.onnx', opt)
text32 = ort.InferenceSession(f'{MODELLE}/clip_text_encoder.onnx', opt)
textq  = ort.InferenceSession('clipq/text_model_quantized.onnx', opt)
tok = Tokenizer.from_pretrained('openai/clip-vit-base-patch32')

def textvektor(sess, satz):
    ids = tok.encode(satz).ids[:77]
    ids = ids + [0]*(77-len(ids))
    v = sess.run(None, {sess.get_inputs()[0].name: np.array([ids], dtype=np.int64)})[0][0]
    return v/np.linalg.norm(v)

db = sqlite3.connect('file:lib3.sqlite?mode=ro', uri=True)
rows = db.execute("SELECT id, coalesce(preview_relative_path, thumbnail_relative_path, relative_path) "
                  "FROM assets WHERE is_trashed=0 AND is_locked=0").fetchall()
random.seed(1234)
pfade = [(i, os.path.join(LIB, p)) for i, p in random.sample(rows, min(700, len(rows)))]
pfade = [(i, p) for i, p in pfade if os.path.exists(p)][:600]
print(len(pfade), 'Fotos', flush=True)

ids, v32, vq, t32, tq = [], [], [], 0.0, 0.0
for n, (i, p) in enumerate(pfade):
    try:
        x = vorbereiten(Image.open(p))
    except Exception:
        continue
    a = time.perf_counter(); r32 = bild32.run(None, {'pixel_values': x})[0][0]; t32 += time.perf_counter()-a
    a = time.perf_counter(); rq  = bildq.run(None,  {'pixel_values': x})[0][0]; tq  += time.perf_counter()-a
    ids.append(i); v32.append(r32/np.linalg.norm(r32)); vq.append(rq/np.linalg.norm(rq))
    if n % 100 == 0: print(f'  {n}', flush=True)

v32 = np.array(v32, dtype=np.float32); vq = np.array(vq, dtype=np.float32)
np.savez('clipq.npz', ids=np.array(ids), fp32=v32, q8=vq,
         pfade=np.array([p for _, p in pfade[:len(ids)]]))
print(f'\n{len(ids)} Bilder | fp32 {t32/len(ids)*1000:.0f} ms/Bild | q8 {tq/len(ids)*1000:.0f} ms/Bild')

# 1. Wie nah steht der quantisierte Vektor am fp32-Vektor?
paar = (v32*vq).sum(1)
print(f'\nKosinus fp32<->q8 je Bild: Median {np.median(paar):.4f}  '
      f'min {paar.min():.4f}  5%-Quantil {np.quantile(paar,0.05):.4f}')

# 2. Die Bild/Bild-Schwellen (Duplikate 0,97 / Serien 0,92)
def paarwerte(v):
    s = v @ v.T
    return s[np.triu_indices(len(v), 1)]
p32, pq = paarwerte(v32), paarwerte(vq)
print(f'\nBild/Bild-Aehnlichkeit  fp32: Median {np.median(p32):.4f} 99,9% {np.quantile(p32,0.999):.4f}'
      f'\n                          q8: Median {np.median(pq):.4f} 99,9% {np.quantile(pq,0.999):.4f}')
for schwelle in (0.92, 0.95, 0.97):
    print(f'   ueber {schwelle}: fp32 {(p32>schwelle).sum():6d}   q8 {(pq>schwelle).sum():6d}')

# 3. Die Suche: dieselben Fragen wie bei der SigLIP-Messung
FRAGEN = ['a dog', 'snow in winter', 'a birthday cake', 'a boat on the water',
          'a church', 'food on a plate', 'a screenshot', 'a sunset',
          'people at a table', 'a mountain landscape']
print('\nTreffer-Ueberschneidung der Rangliste (dieselbe Frage, beide Modelle):')
ueber6, ueber20 = [], []
for f in FRAGEN:
    a, b = textvektor(text32, f), textvektor(textq, f)
    r32 = np.argsort(-(v32 @ a)); rq = np.argsort(-(vq @ b))
    o6 = len(set(r32[:6]) & set(rq[:6])); o20 = len(set(r32[:20]) & set(rq[:20]))
    ueber6.append(o6); ueber20.append(o20)
    print(f'  {f:24s} top-6 {o6}/6   top-20 {o20}/20   erster gleich: {r32[0]==rq[0]}')
print(f'  ZUSAMMEN top-6 {sum(ueber6)}/{6*len(FRAGEN)}   top-20 {sum(ueber20)}/{20*len(FRAGEN)}')

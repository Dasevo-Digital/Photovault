import os, sqlite3, random, time
import numpy as np, onnxruntime as ort
from PIL import Image
from tokenizers import Tokenizer
MODELLE = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                             'Application Support/com.example.photoVault/PhotoVault/models')
LIB = os.path.expanduser('~/Pictures/Photo_Vault_Productive/library')
MEAN = np.array([0.48145466,0.4578275,0.40821073],dtype=np.float32)
STD  = np.array([0.26862954,0.26130258,0.27577711],dtype=np.float32)
opt = ort.SessionOptions(); opt.log_severity_level = 3
def vorb(b):
    w,h=b.size; s=224/min(w,h)
    b=b.resize((max(224,round(w*s)),max(224,round(h*s))),Image.BICUBIC)
    w,h=b.size; l,o=(w-224)//2,(h-224)//2
    a=np.asarray(b.crop((l,o,l+224,o+224)).convert('RGB'),dtype=np.float32)/255.0
    return np.transpose((a-MEAN)/STD,(2,0,1))[None].astype(np.float32)
b32=ort.InferenceSession(f'{MODELLE}/clip_image_encoder.onnx',opt)
b16=ort.InferenceSession('clipq/vision_model_fp16.onnx',opt)
t32=ort.InferenceSession(f'{MODELLE}/clip_text_encoder.onnx',opt)
t16=ort.InferenceSession('clipq/text_model_fp16.onnx',opt)
tok=Tokenizer.from_pretrained('openai/clip-vit-base-patch32')
ein16 = b16.get_inputs()[0]
print('fp16-Eingabe:', ein16.name, ein16.type)
def tv(s,satz):
    ids=tok.encode(satz).ids[:77]; ids=ids+[0]*(77-len(ids))
    v=s.run(None,{s.get_inputs()[0].name:np.array([ids],dtype=np.int64)})[0][0]
    return (v.astype(np.float32))/np.linalg.norm(v.astype(np.float32))
db=sqlite3.connect('file:lib3.sqlite?mode=ro',uri=True)
rows=db.execute("SELECT id, coalesce(preview_relative_path,thumbnail_relative_path,relative_path) "
                "FROM assets WHERE is_trashed=0 AND is_locked=0").fetchall()
random.seed(1234)
pf=[(i,os.path.join(LIB,p)) for i,p in random.sample(rows,min(700,len(rows)))]
pf=[(i,p) for i,p in pf if os.path.exists(p)][:600]
v32,v16,z32,z16=[],[],0.0,0.0
halb = 'float16' in ein16.type
for n,(i,p) in enumerate(pf):
    try: x=vorb(Image.open(p))
    except Exception: continue
    a=time.perf_counter(); r=b32.run(None,{'pixel_values':x})[0][0]; z32+=time.perf_counter()-a
    xs = x.astype(np.float16) if halb else x
    a=time.perf_counter(); q=b16.run(None,{'pixel_values':xs})[0][0].astype(np.float32); z16+=time.perf_counter()-a
    v32.append(r/np.linalg.norm(r)); v16.append(q/np.linalg.norm(q))
    if n%200==0: print(' ',n,flush=True)
v32=np.array(v32,dtype=np.float32); v16=np.array(v16,dtype=np.float32)
print(f'\n{len(v32)} Bilder | fp32 {z32/len(v32)*1000:.0f} ms | fp16 {z16/len(v16)*1000:.0f} ms')
paar=(v32*v16).sum(1)
print(f'Kosinus fp32<->fp16: Median {np.median(paar):.6f} min {paar.min():.6f}')
def pw(v):
    s=v@v.T; return s[np.triu_indices(len(v),1)]
p32,p16=pw(v32),pw(v16)
for sch in (0.92,0.95,0.97):
    print(f'  ueber {sch}: fp32 {(p32>sch).sum():6d}   fp16 {(p16>sch).sum():6d}')
FRAGEN=['a dog','snow in winter','a birthday cake','a boat on the water','a church',
        'food on a plate','a screenshot','a sunset','people at a table','a mountain landscape']
s6=s20=0
for f in FRAGEN:
    a,b=tv(t32,f),tv(t16,f)
    r32=np.argsort(-(v32@a)); r16=np.argsort(-(v16@b))
    o6=len(set(r32[:6])&set(r16[:6])); o20=len(set(r32[:20])&set(r16[:20])); s6+=o6; s20+=o20
    print(f'  {f:24s} top-6 {o6}/6  top-20 {o20}/20  erster gleich: {r32[0]==r16[0]}')
print(f'  ZUSAMMEN top-6 {s6}/60  top-20 {s20}/200')

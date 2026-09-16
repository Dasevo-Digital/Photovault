"""SAM ViT-B (ausgeliefert) gegen SlimSAM-77 – gleicher Klick, gleiches Foto."""
import os, sqlite3, random, time
import numpy as np, onnxruntime as ort
from PIL import Image
M = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                       'Application Support/com.example.photoVault/PhotoVault/models')
LIB = os.path.expanduser('~/Pictures/Photo_Vault_Productive/library')
MEAN=np.array([0.485,0.456,0.406],dtype=np.float32); STD=np.array([0.229,0.224,0.225],dtype=np.float32)
opt=ort.SessionOptions(); opt.log_severity_level=3
P=['CPUExecutionProvider']
sam_v=ort.InferenceSession(f'{M}/sam_vision_encoder.onnx',opt,providers=P)
sam_d=ort.InferenceSession(f'{M}/sam_prompt_mask_decoder.onnx',opt,providers=P)
sl_v =ort.InferenceSession('slim/vision_encoder_quantized.onnx',opt,providers=P)
sl_d =ort.InferenceSession('slim/prompt_encoder_mask_decoder_quantized.onnx',opt,providers=P)
for n,s in [('SAM  Enc',sam_v),('Slim Enc',sl_v)]:
    print(n,[(i.name,i.shape) for i in s.get_inputs()],'->',[(o.name,tuple(o.shape)) for o in s.get_outputs()])
for n,s in [('SAM  Dec',sam_d),('Slim Dec',sl_d)]:
    print(n,[(i.name,tuple(i.shape)) for i in s.get_inputs()],'->',[(o.name,tuple(o.shape)) for o in s.get_outputs()])

def vorb(bild):
    b=bild.convert('RGB'); w,h=b.size; s=1024/max(w,h)
    nw,nh=round(w*s),round(h*s)
    a=np.asarray(b.resize((nw,nh),Image.BILINEAR),dtype=np.float32)/255.0
    a=(a-MEAN)/STD
    aus=np.zeros((1024,1024,3),dtype=np.float32); aus[:nh,:nw]=a
    return np.transpose(aus,(2,0,1))[None].astype(np.float32),(nw,nh)

def maske(venc,dec,x,punkt):
    e=venc.run(None,{'pixel_values':x})
    namen=[o.name for o in venc.get_outputs()]
    emb=dict(zip(namen,e))
    ein={'image_embeddings':emb['image_embeddings'],
         'image_positional_embeddings':emb['image_positional_embeddings'],
         'input_points':np.array([[[punkt]]],dtype=np.float32),
         'input_labels':np.array([[[1]]],dtype=np.int64)}
    ein={k:v for k,v in ein.items() if k in [i.name for i in dec.get_inputs()]}
    aus=dec.run(None,ein)
    on=[o.name for o in dec.get_outputs()]
    iou=aus[on.index('iou_scores')][0][0]; m=aus[on.index('pred_masks')][0][0]
    best=int(np.argmax(iou))
    return m[best]>0, float(iou[best])

db=sqlite3.connect('file:lib3.sqlite?mode=ro',uri=True)
rows=db.execute("SELECT coalesce(preview_relative_path,relative_path) FROM assets "
                "WHERE type='IMAGE' AND is_trashed=0").fetchall()
random.seed(7)
pf=[os.path.join(LIB,p) for (p,) in random.sample(rows,60)]
pf=[p for p in pf if os.path.exists(p) and p.lower().endswith(('.jpg','.jpeg','.png'))][:20]
print(f'\n{len(pf)} Fotos, je 3 Klicke\n')
ious,tsam,tsl=[],0.0,0.0
for p in pf:
    try: x,(nw,nh)=vorb(Image.open(p))
    except Exception: continue
    for fx,fy in ((0.5,0.5),(0.33,0.4),(0.66,0.6)):
        pt=[nw*fx,nh*fy]
        a=time.perf_counter(); m1,i1=maske(sam_v,sam_d,x,pt); tsam+=time.perf_counter()-a
        a=time.perf_counter(); m2,i2=maske(sl_v,sl_d,x,pt);  tsl +=time.perf_counter()-a
        v=(m1&m2).sum(); u=(m1|m2).sum()
        ious.append(v/u if u else 1.0)
ious=np.array(ious)
print(f'Ueberdeckung (IoU) der beiden Masken: Median {np.median(ious):.3f}  '
      f'Mittel {ious.mean():.3f}  unter 0,5: {(ious<0.5).sum()}/{len(ious)}')
print(f'Zeit je Klick: SAM {tsam/len(ious)*1000:.0f} ms   SlimSAM {tsl/len(ious)*1000:.0f} ms')
print(f'Platte: SAM {(os.path.getsize(f"{M}/sam_vision_encoder.onnx")+os.path.getsize(f"{M}/sam_prompt_mask_decoder.onnx"))/1e6:.0f} MB'
      f'   SlimSAM {(os.path.getsize("slim/vision_encoder_quantized.onnx")+os.path.getsize("slim/prompt_encoder_mask_decoder_quantized.onnx"))/1e6:.0f} MB')

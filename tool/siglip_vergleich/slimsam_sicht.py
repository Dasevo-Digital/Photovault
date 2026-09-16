"""SAM gegen SlimSAM an GEZIELTEN Klicken: der Mittelpunkt eines Gesichts.

Die erste Messung setzte die Klicke willkuerlich (Mitte, ein Drittel, zwei
Drittel). Ein Klick ins Nichts hat keine richtige Antwort, und dort duerfen
zwei Modelle auseinanderlaufen. Diese Fassung klickt auf etwas, das
nachweislich da ist - einen Gesichtsrahmen aus der Datenbank.

Schreibt Kontaktabzuege mit ECHTEN Fotos. Sie gehoeren nirgendwo hin, wo
sie jemand anders sieht.
"""
import os, sqlite3, time
import numpy as np, onnxruntime as ort
from PIL import Image, ImageDraw

M = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                       'Application Support/com.example.photoVault/PhotoVault/models')
LIB = os.path.expanduser('~/Pictures/Photo_Vault_Productive/library')
AUS = os.path.expanduser('~/Desktop/pv_slimsam')
os.makedirs(AUS, exist_ok=True)
MEAN=np.array([0.485,0.456,0.406],dtype=np.float32); STD=np.array([0.229,0.224,0.225],dtype=np.float32)
opt=ort.SessionOptions(); opt.log_severity_level=3; P=['CPUExecutionProvider']

sam_v=ort.InferenceSession(f'{M}/sam_vision_encoder.onnx',opt,providers=P)
sam_d=ort.InferenceSession(f'{M}/sam_prompt_mask_decoder.onnx',opt,providers=P)
sl_v =ort.InferenceSession('slim/vision_encoder_quantized.onnx',opt,providers=P)
sl_d =ort.InferenceSession('slim/prompt_encoder_mask_decoder_quantized.onnx',opt,providers=P)

def vorb(bild):
    b=bild.convert('RGB'); w,h=b.size; s=1024/max(w,h)
    nw,nh=max(1,round(w*s)),max(1,round(h*s))
    a=np.asarray(b.resize((nw,nh),Image.BILINEAR),dtype=np.float32)/255.0
    a=(a-MEAN)/STD
    aus=np.zeros((1024,1024,3),dtype=np.float32); aus[:nh,:nw]=a
    return np.transpose(aus,(2,0,1))[None].astype(np.float32),(nw,nh)

def maske(venc,dec,x,punkt):
    namen=[o.name for o in venc.get_outputs()]
    emb=dict(zip(namen,venc.run(None,{'pixel_values':x})))
    ein={'image_embeddings':emb['image_embeddings'],
         'image_positional_embeddings':emb['image_positional_embeddings'],
         'input_points':np.array([[[punkt]]],dtype=np.float32),
         'input_labels':np.array([[[1]]],dtype=np.int64)}
    aus=dec.run(None,ein); on=[o.name for o in dec.get_outputs()]
    iou=aus[on.index('iou_scores')][0][0]; m=aus[on.index('pred_masks')][0][0]
    b=int(np.argmax(iou))
    return m[b]>0, float(iou[b])

def male(bild,masse,m,punkt,titel,farbe):
    nw,nh=masse
    # Maske (256x256, bezogen auf die 1024er Leinwand) auf das Bild legen
    voll=np.array(Image.fromarray((m*255).astype(np.uint8)).resize((1024,1024),Image.NEAREST))[:nh,:nw]
    grund=bild.convert('RGB').resize((nw,nh),Image.BILINEAR)
    schicht=Image.new('RGBA',(nw,nh),(0,0,0,0))
    px=np.array(schicht); px[voll>127]=farbe
    schicht=Image.fromarray(px,'RGBA')
    erg=Image.alpha_composite(grund.convert('RGBA'),schicht).convert('RGB')
    z=ImageDraw.Draw(erg)
    z.ellipse([punkt[0]-9,punkt[1]-9,punkt[0]+9,punkt[1]+9],outline=(255,255,0),width=4)
    z.rectangle([0,0,nw,26],fill=(0,0,0)); z.text((6,7),titel,fill=(255,255,255))
    return erg

db=sqlite3.connect('file:lib3.sqlite?mode=ro',uri=True)
zeilen=db.execute("""
  SELECT coalesce(a.preview_relative_path, a.relative_path), f.box_x, f.box_y, f.box_w, f.box_h
  FROM faces f JOIN assets a ON a.id=f.asset_id
  WHERE a.is_trashed=0 AND a.is_locked=0 AND f.box_w > 0.10
  ORDER BY f.box_w DESC LIMIT 400""").fetchall()

ious,tsam,tsl,n=[],0.0,0.0,0
gesehen=set()
for rel,bx,by,bw,bh in zeilen:
    if n>=12: break
    if rel in gesehen: continue
    pfad=os.path.join(LIB,rel)
    if not os.path.exists(pfad) or not pfad.lower().endswith(('.jpg','.jpeg','.png')): continue
    try: bild=Image.open(pfad); x,(nw,nh)=vorb(bild)
    except Exception: continue
    gesehen.add(rel)
    punkt=[(bx+bw/2)*nw,(by+bh/2)*nh]
    a=time.perf_counter(); m1,_=maske(sam_v,sam_d,x,punkt); tsam+=time.perf_counter()-a
    a=time.perf_counter(); m2,_=maske(sl_v,sl_d,x,punkt);  tsl +=time.perf_counter()-a
    v=(m1&m2).sum(); u=(m1|m2).sum(); iou=v/u if u else 1.0
    ious.append(iou)
    links =male(bild,(nw,nh),m1,punkt,f'SAM ViT-B',(255,64,64,110))
    rechts=male(bild,(nw,nh),m2,punkt,f'SlimSAM-77  (IoU {iou:.2f})',(64,160,255,110))
    blatt=Image.new('RGB',(nw*2+12,nh),(20,20,20))
    blatt.paste(links,(0,0)); blatt.paste(rechts,(nw+12,0))
    blatt.thumbnail((1600,1600))
    blatt.save(f'{AUS}/{n:02d}.jpg',quality=88)
    n+=1
    print(f'  {n:2d}  IoU {iou:.3f}  {os.path.basename(rel)}',flush=True)

ious=np.array(ious)
print(f'\n{n} gezielte Klicke auf Gesichter')
print(f'IoU: Median {np.median(ious):.3f}  Mittel {ious.mean():.3f}  '
      f'unter 0,5: {(ious<0.5).sum()}/{len(ious)}')
print(f'Zeit je Klick: SAM {tsam/n*1000:.0f} ms   SlimSAM {tsl/n*1000:.0f} ms')
print(f'\nBlaetter liegen in {AUS}')

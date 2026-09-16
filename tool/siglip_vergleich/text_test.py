import os, time, numpy as np, onnxruntime as ort
M = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                       'Application Support/com.example.photoVault/PhotoVault/models')
opt=ort.SessionOptions(); opt.log_severity_level=3
ids=np.random.randint(0,49000,(1,77)).astype(np.int64)
for name,p in [('Text fp32', f'{M}/clip_text_encoder.onnx'),
               ('Text fp16', 'clipq/text_model_fp16.onnx'),
               ('Text q8  ', 'clipq/text_model_quantized.onnx')]:
    s=ort.InferenceSession(p,opt,providers=['CPUExecutionProvider'])
    n=s.get_inputs()[0].name
    for _ in range(3): s.run(None,{n:ids})
    t=time.perf_counter()
    for _ in range(30): s.run(None,{n:ids})
    mb=os.path.getsize(p)/1e6
    print(f'{name}  {(time.perf_counter()-t)/30*1000:6.1f} ms je Suche   {mb:6.1f} MB')
# Und: bleibt die Textseite in fp16 deckungsgleich?
from tokenizers import Tokenizer
tok=Tokenizer.from_pretrained('openai/clip-vit-base-patch32')
a=ort.InferenceSession(f'{M}/clip_text_encoder.onnx',opt,providers=['CPUExecutionProvider'])
b=ort.InferenceSession('clipq/text_model_fp16.onnx',opt,providers=['CPUExecutionProvider'])
w=[]
for satz in ['a dog','snow in winter','a birthday cake','a church','a sunset','food on a plate']:
    i=tok.encode(satz).ids[:77]; i=np.array([i+[0]*(77-len(i))],dtype=np.int64)
    va=a.run(None,{a.get_inputs()[0].name:i})[0][0].astype(np.float32)
    vb=b.run(None,{b.get_inputs()[0].name:i})[0][0].astype(np.float32)
    w.append(float(va@vb/(np.linalg.norm(va)*np.linalg.norm(vb))))
print('Kosinus fp32<->fp16 der Fragen:', ' '.join(f'{x:.6f}' for x in w))

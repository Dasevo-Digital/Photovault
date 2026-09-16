import os, time, numpy as np, onnxruntime as ort
from PIL import Image
print('Anbieter:', ort.get_available_providers())
M = os.path.expanduser('~/Library/Containers/com.example.photoVault/Data/Library/'
                       'Application Support/com.example.photoVault/PhotoVault/models')
MEAN=np.array([0.48145466,0.4578275,0.40821073],dtype=np.float32)
STD =np.array([0.26862954,0.26130258,0.27577711],dtype=np.float32)
x = np.random.rand(1,3,224,224).astype(np.float32)
opt=ort.SessionOptions(); opt.log_severity_level=3
def messe(pfad, prov, n=40):
    try:
        s=ort.InferenceSession(pfad, opt, providers=prov)
    except Exception as e:
        return f'FEHLER {e}'
    name=s.get_inputs()[0].name
    xx = x.astype(np.float16) if 'float16' in s.get_inputs()[0].type else x
    for _ in range(5): s.run(None,{name:xx})
    t=time.perf_counter()
    for _ in range(n): s.run(None,{name:xx})
    return f'{(time.perf_counter()-t)/n*1000:6.1f} ms   (tatsaechlich: {s.get_providers()})'
for name,pfad in [('CLIP Bild fp32', f'{M}/clip_image_encoder.onnx'),
                  ('CLIP Bild fp16', 'clipq/vision_model_fp16.onnx'),
                  ('CLIP Bild q8  ', 'clipq/vision_model_quantized.onnx')]:
    print(f'{name}  CPU     {messe(pfad,["CPUExecutionProvider"])}')
    print(f'{name}  CoreML  {messe(pfad,["CoreMLExecutionProvider","CPUExecutionProvider"])}')

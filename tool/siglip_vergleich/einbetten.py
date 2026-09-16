import os, sqlite3, random, time
import numpy as np
from PIL import Image
from modelle import (clip_bild, clip_vorbereiten, sig_bild, sig_vorbereiten, LIB)

db = sqlite3.connect('lib3.sqlite')
rows = db.execute("SELECT id, coalesce(preview_relative_path, thumbnail_relative_path, relative_path) "
                  "FROM assets WHERE type='IMAGE' AND is_trashed=0 AND is_locked=0").fetchall()
random.seed(1234)
probe = random.sample(rows, 600)
pfade = [(i, os.path.join(LIB, p)) for i, p in probe]
pfade = [(i, p) for i, p in pfade if os.path.exists(p)]
print(len(pfade), 'Fotos')

ids, c_vecs, s_vecs = [], [], []
t0 = time.time()
for n, (i, p) in enumerate(pfade):
    try:
        bild = Image.open(p)
        cv = clip_bild.run(None, {'pixel_values': clip_vorbereiten(bild)})[0][0]
        sv = sig_bild.run(None, {'pixel_values': sig_vorbereiten(bild)})[1][0]
    except Exception as e:
        continue
    ids.append(i)
    c_vecs.append(cv/np.linalg.norm(cv))
    s_vecs.append(sv/np.linalg.norm(sv))
    if n % 100 == 0: print(f'  {n}  {time.time()-t0:.0f}s', flush=True)
np.savez('einbettungen.npz', ids=np.array(ids), clip=np.array(c_vecs, dtype=np.float32),
         siglip=np.array(s_vecs, dtype=np.float32),
         pfade=np.array([p for i,p in pfade if i in set(ids)]))
print('fertig', len(ids), f'{time.time()-t0:.0f}s')

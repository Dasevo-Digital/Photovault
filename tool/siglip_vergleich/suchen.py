import numpy as np, os
from PIL import Image, ImageDraw
from modelle import clip_textvektor, sig_textvektor

d = np.load('einbettungen.npz')
pfade = list(d['pfade']); C = d['clip']; S = d['siglip']

FRAGEN = [
    ('ein Hund',                    'a dog'),
    ('Schnee im Winter',            'snow in winter'),
    ('eine Geburtstagstorte',       'a birthday cake'),
    ('ein Boot auf dem Wasser',     'a boat on the water'),
    ('eine Kirche',                 'a church'),
    ('Essen auf einem Teller',      'food on a plate'),
]
N = 6
for nr, (de, en) in enumerate(FRAGEN):
    cv = clip_textvektor(en)
    sv_de = sig_textvektor(de)
    sv_en = sig_textvektor(f'a photo of {en}')
    ci = np.argsort(-(C @ cv))[:N]
    sie = np.argsort(-(S @ sv_en))[:N]
    sid = np.argsort(-(S @ sv_de))[:N]
    blatt = Image.new('RGB', (N*150, 3*170+30), (18,18,22))
    zeichner = ImageDraw.Draw(blatt)
    for reihe, (idx, titel) in enumerate([(ci, f'CLIP  englisch: "{en}"'),
                                          (sie, f'SigLIP 2  englisch: "a photo of {en}"'),
                                          (sid, f'SigLIP 2  deutsch: "{de}"')]):
        for k, i in enumerate(idx):
            try:
                b = Image.open(pfade[i]).convert('RGB')
                b.thumbnail((140,140))
                blatt.paste(b, (k*150+5, reihe*170+22))
            except Exception:
                pass
        zeichner.text((5, reihe*170+5), titel, fill=(150,220,255))
    blatt.save(f'suche_{nr}.png')
    print(f'{nr}: {de}')

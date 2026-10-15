#!/usr/bin/env python3
"""Erzeugt die App-Symbole der Handy-App aus dem Symbol der Desktop-App.

Quelle ist das macOS-Symbol (abgerundetes Quadrat mit Rand). iOS will ein
volles Quadrat ohne Alphakanal und rundet selbst ab; Android bekommt ein
adaptives Symbol (Hintergrund und Vordergrund getrennt, die Maske legt das
System darüber) und für ältere Fassungen das abgerundete Quadrat.

Aufruf aus dem Wurzelordner: python3 tool/handy_symbole.py
"""
import json
import os

from PIL import Image

QUELLE = 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png'
IOS = 'apps/mobil/ios/Runner/Assets.xcassets/AppIcon.appiconset'
ANDROID = 'apps/mobil/android/app/src/main/res'

# Das abgerundete Quadrat in der Quelle, das Schloss darin.
FLAECHE = (80, 80, 944, 944)
SCHLOSS = (270, 290, 755, 905)

quelle = Image.open(QUELLE).convert('RGBA')


def verlauf(groesse):
    """Der senkrechte Verlauf der Fläche, gemessen links neben dem Schloss."""
    oben, unten = FLAECHE[1] + 30, FLAECHE[3] - 30
    farben = [quelle.getpixel((200, y))[:3] for y in range(oben, unten)]
    bild = Image.new('RGBA', (groesse, groesse))
    for y in range(groesse):
        i = min(len(farben) - 1, max(0, round(y / (groesse - 1) * (len(farben) - 1))))
        for x in range(groesse):
            bild.putpixel((x, y), farben[i] + (255,))
    return bild


def vordergrund():
    """Nur das Schloss samt Schatten, vom Verlauf gelöst: Helles wird Weiss
    mit Deckkraft, Dunkles (der Schatten) Schwarz mit Deckkraft – so passt
    es auf jeden Verlauf, auch an anderer Stelle."""
    x0, y0, x1, y1 = SCHLOSS
    teil = quelle.crop(SCHLOSS)
    for y in range(y1 - y0):
        grund = quelle.getpixel((200, y + y0))[:3]
        g = sum(grund) / 3
        for x in range(x1 - x0):
            p = teil.getpixel((x, y))[:3]
            if max(abs(p[i] - grund[i]) for i in range(3)) <= 4:
                teil.putpixel((x, y), (0, 0, 0, 0))
            elif sum(p) / 3 > g:
                a = max((p[i] - grund[i]) / (255 - grund[i]) for i in range(3))
                teil.putpixel((x, y), (255, 255, 255, round(255 * min(1, a))))
            else:
                a = 1 - (sum(p) / 3) / g
                teil.putpixel((x, y), (0, 0, 0, round(255 * min(1, a))))
    return teil


# iOS: volles Quadrat, ohne Alphakanal, eine Grösse (Xcode leitet ab).
flaeche = quelle.crop(FLAECHE).resize((1024, 1024), Image.LANCZOS)
ios = Image.alpha_composite(verlauf(1024), flaeche).convert('RGB')
for f in os.listdir(IOS):
    if f.endswith('.png'):
        os.remove(os.path.join(IOS, f))
ios.save(os.path.join(IOS, 'Icon-App-1024x1024@1x.png'))
with open(os.path.join(IOS, 'Contents.json'), 'w') as f:
    json.dump({
        'images': [{
            'filename': 'Icon-App-1024x1024@1x.png',
            'idiom': 'universal',
            'platform': 'ios',
            'size': '1024x1024',
        }],
        'info': {'author': 'xcode', 'version': 1},
    }, f, indent=2)
    f.write('\n')

# Android: 108 dp je Ebene; sichtbar bleibt ein Kreis von 66 dp, das
# Schloss muss ganz hinein.
schloss = vordergrund()
dichten = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, faktor in dichten.items():
    ordner = os.path.join(ANDROID, f'mipmap-{name}')
    os.makedirs(ordner, exist_ok=True)
    seite = round(108 * faktor)
    verlauf(seite).convert('RGB').save(os.path.join(ordner, 'ic_launcher_background.png'))
    hoehe = round(seite * 0.40)
    breite = round(hoehe * schloss.width / schloss.height)
    vorne = Image.new('RGBA', (seite, seite))
    klein = schloss.resize((breite, hoehe), Image.LANCZOS)
    vorne.paste(klein, ((seite - breite) // 2, (seite - hoehe) // 2), klein)
    vorne.save(os.path.join(ordner, 'ic_launcher_foreground.png'))
    alt = round(48 * faktor)
    quelle.crop(FLAECHE).resize((alt, alt), Image.LANCZOS).save(
        os.path.join(ordner, 'ic_launcher.png'))

adaptiv = os.path.join(ANDROID, 'mipmap-anydpi-v26')
os.makedirs(adaptiv, exist_ok=True)
with open(os.path.join(adaptiv, 'ic_launcher.xml'), 'w') as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
print('fertig')

"""Handwerkszeug fuer tool/gebiete_bauen.py: Vereinfachen und Flaechen.

Steht in einer eigenen Datei, damit sich der Douglas-Peucker-Durchlauf
einzeln ausprobieren laesst, ohne den ganzen Bau anzuwerfen.
"""
import math

def dp(pts, tol):
    """Douglas-Peucker auf einem Ring, in Grad."""
    if len(pts) < 3: return pts
    keep=[False]*len(pts); keep[0]=keep[-1]=True
    stack=[(0,len(pts)-1)]
    while stack:
        a,b=stack.pop()
        if b<=a+1: continue
        ax,ay=pts[a]; bx,by=pts[b]
        dx,dy=bx-ax,by-ay
        n=math.hypot(dx,dy)
        best=-1.0; bi=-1
        for i in range(a+1,b):
            px,py=pts[i]
            if n==0: d=math.hypot(px-ax,py-ay)
            else: d=abs(dy*px-dx*py+bx*ay-by*ax)/n
            if d>best: best=d; bi=i
        if best>tol:
            keep[bi]=True; stack.append((a,bi)); stack.append((bi,b))
    return [p for p,k in zip(pts,keep) if k]

def ringflaeche(r):
    s=0.0
    for i in range(len(r)-1):
        s+=r[i][0]*r[i+1][1]-r[i+1][0]*r[i][1]
    return abs(s)/2

def polygone(geom):
    t=geom['type']
    if t=='Polygon': return [geom['coordinates']]
    if t=='MultiPolygon': return geom['coordinates']
    return []

def bearbeite(geom, tol, minflaeche, stellen):
    raus=[]
    for poly in polygone(geom):
        aussen=poly[0]
        if ringflaeche(aussen)<minflaeche: continue
        v=dp([tuple(c[:2]) for c in aussen], tol)
        if len(v)<4: continue
        raus.append([[round(x,stellen),round(y,stellen)] for x,y in v])
    if not raus:
        # Immer wenigstens den groessten Ring behalten.
        alle=[p[0] for p in polygone(geom)]
        if not alle: return []
        g=max(alle,key=ringflaeche)
        v=dp([tuple(c[:2]) for c in g],tol)
        if len(v)>=4: raus.append([[round(x,stellen),round(y,stellen)] for x,y in v])
    return raus

"""Erzeugt assets/geo/gebiete.bin.gz aus Natural Earth und GeoNames.

Zwei Quellen, ein Ziel:
  ne_10m_admin_0_countries        -> Laender,  Schluessel = ISO-2 ("DE")
  ne_10m_admin_1_states_provinces -> Regionen, Schluessel = GeoNames-Code ("DE.02")

Beide Ebenen kommen aus derselben Aufloesung (1:10m) und werden mit derselben
Toleranz vereinfacht. Das ist keine Kleinigkeit: Vorher war die Region feiner
gezeichnet als das Land, in dem sie liegt, und Latium ragte sichtbar aus
Italien heraus.

Der Schluessel einer Region kommt zuerst ueber die GeoNames-Kennung, die
Natural Earth mitfuehrt - Namen weichen zwischen zwei Datensaetzen ab,
Kennungen nicht. Wo die Kennung ins Leere laeuft, entscheidet die Mehrheit
der enthaltenen Orte aus cities1000.txt (siehe schluessel_aus_staedten).
"""
import json,math,os,sys,gzip,unicodedata,re,collections
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from vereinfache import dp, ringflaeche, polygone

if len(sys.argv)<7:
    sys.exit(__doc__ + '''
Aufruf:
  python3 tool/gebiete_bauen.py \\
      <admin1CodesASCII.txt> <countryInfo.txt> <cities1000.txt> \\
      <ne_10m_admin_0_countries.geojson> \\
      <ne_10m_admin_1_states_provinces.geojson> \\
      assets/geo/gebiete.bin.gz

Die beiden Natural-Earth-Dateien liegen unter
https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/
und sind gemeinfrei. Die drei GeoNames-Dateien liegen im Datenordner der App,
sobald der Ortsdatensatz einmal geladen wurde (Unterordner geodata).''')
ADMIN1,COUNTRY,CITIES,NE_A0,NE_A1,ZIEL=sys.argv[1:7]

def norm(s):
    s=unicodedata.normalize('NFKD',s or '')
    s=''.join(ch for ch in s if not unicodedata.combining(ch))
    return re.sub(r'[^a-z0-9]','',s.lower())

# --- GeoNames-Schluessel einlesen -------------------------------------
gn2code={}; name2code={}
for line in open(ADMIN1,encoding='utf-8'):
    c=line.rstrip('\n').split('\t')
    if len(c)<2: continue
    code=c[0]; iso=code.split('.')[0]
    if len(c)>=4 and c[3].isdigit(): gn2code[int(c[3])]=code
    for nm in {c[1]}|({c[2]} if len(c)>2 else set()):
        name2code.setdefault(iso+'|'+norm(nm),code)

alle_codes=set(gn2code.values())|{c.split('\t')[0] for c in open(ADMIN1,encoding='utf-8') if '\t' in c}

iso_namen={}
for line in open(COUNTRY,encoding='utf-8'):
    if line.startswith('#') or not line.strip(): continue
    c=line.rstrip('\n').split('\t')
    if len(c)>=5: iso_namen[norm(c[4])]=c[0]

# --- Staedte als Zuordnungshilfe --------------------------------------
#
# Der Schluessel einer Region soll ueber die GeoNames-Kennung kommen. Fuer
# Italien, Frankreich und Grossbritannien geht das schief: Dort hat GeoNames
# die Gliederung geaendert (Frankreich 2016 von 22 auf 13 Regionen), Natural
# Earth zeigt noch die alten Einheiten oder gleich die Provinzen. Die
# Kennungen laufen auseinander, die Namen auch.
#
# Was nicht auseinanderlaeuft, sind die Staedte: Jede Zeile in cities1000.txt
# traegt Koordinate UND Regionscode. Welche Region eine Flaeche ist, sagen
# also die Orte, die darin liegen - die Mehrheit gewinnt. Ist Natural Earth
# feiner gegliedert als GeoNames (Italien: 107 Provinzen gegen 20 Regionen),
# fallen mehrere Flaechen auf denselben Schluessel und werden vereinigt.
staedte=[]
for line in open(CITIES,encoding='utf-8'):
    c=line.rstrip('\n').split('\t')
    if len(c)<11: continue
    try: lat=float(c[4]); lon=float(c[5])
    except ValueError: continue
    if not c[10]: continue
    staedte.append((lon,lat,c[8]+'.'+c[10]))
gitter=collections.defaultdict(list)
for i,(lon,lat,_) in enumerate(staedte):
    gitter[(int(lon//1),int(lat//1))].append(i)

def im_ring(ring,x,y):
    drin=False; j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i]; xj,yj=ring[j]
        if (yi>y)!=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi: drin=not drin
        j=i
    return drin

def schluessel_aus_staedten(rs,iso=None):
    """Der Regionscode der Mehrheit der Orte in diesen Ringen.

    [iso] engt auf das Land der Flaeche ein und ist wichtiger, als es
    aussieht: Ein vereinfachter Umriss ragt an der Grenze ueber sie
    hinaus. Ohne die Einengung bekam die surinamische Provinz Sipaliwini
    den Code von Franzoesisch-Guayana und zwei mazedonische Gemeinden
    einen albanischen.
    """
    zaehler=collections.Counter()
    for r in rs:
        xs=[p[0] for p in r]; ys=[p[1] for p in r]
        for zx in range(int(min(xs)//1),int(max(xs)//1)+1):
            for zy in range(int(min(ys)//1),int(max(ys)//1)+1):
                for i in gitter.get((zx,zy),()):
                    lon,lat,code=staedte[i]
                    if iso and not code.startswith(iso+'.'): continue
                    # Nur Codes, die im Verzeichnis stehen. cities1000
                    # traegt vereinzelt Regionscodes, die admin1CodesASCII
                    # nicht kennt - eine Flaeche unter so einem Schluessel
                    # wuerde die App nie abfragen.
                    if code not in alle_codes: continue
                    if im_ring(r,lon,lat): zaehler[code]+=1
    if not zaehler: return None
    return zaehler.most_common(1)[0][0]

def verschmelze(ringe):
    """Vereinigt aneinandergrenzende Ringe zu ihren Aussengrenzen.

    Natural Earth ist an vielen Stellen feiner gegliedert als GeoNames -
    fuer Italien 110 Provinzen gegen 20 Regionen. Wuerde man die Stuecke
    einfach nebeneinander zeichnen, saehe eine Region wie ein Flickenteppich
    aus, weil jede Provinzgrenze als Strich stehen bliebe.

    Die Stuecke stammen aus einem topologisch gebauten Datensatz: Eine
    gemeinsame Grenze steht in beiden Nachbarn mit denselben Punkten, nur
    gegenlaeufig. Wer alle Kanten sammelt und die doppelten streicht, behaelt
    genau die Aussenkanten (fuer Italien 69 Prozent doppelt). Kanten, die
    nicht paarweise auftreten - weil ein Nachbar fehlt oder sich die
    Datensaetze widersprechen - bleiben stehen; die Verschmelzung ist dann
    unvollstaendig, aber nie falsch.
    """
    zaehler=collections.Counter()
    for r in ringe:
        for i in range(len(r)-1):
            zaehler[frozenset((r[i],r[i+1]))]+=1
    nachfolger=collections.defaultdict(list)
    for r in ringe:
        for i in range(len(r)-1):
            a,b=r[i],r[i+1]
            if a==b: continue
            if zaehler[frozenset((a,b))]==1: nachfolger[a].append(b)
    raus=[]
    while nachfolger:
        start=next(iter(nachfolger))
        weg=[start]; hier=start
        while True:
            folge=nachfolger.get(hier)
            if not folge: break
            naechster=folge.pop()
            if not folge: del nachfolger[hier]
            weg.append(naechster)
            hier=naechster
            if hier==start: break
        if len(weg)>=4 and weg[0]==weg[-1]: raus.append(weg)
    return raus or ringe


def diagonale(ringe):
    xs=[];ys=[]
    for r in ringe:
        for x,y in r: xs.append(x);ys.append(y)
    return 0 if not xs else math.hypot(max(xs)-min(xs),max(ys)-min(ys))

# Gebiete, die kleiner sind als die Ungenauigkeit des Datensatzes, kommen
# nicht in die Datei. Natural Earth 1:50m zeichnet den Vatikan als Fuenfeck
# rund anderthalb Kilometer westlich seiner GeoNames-Koordinate – eine
# Flaeche, die den eigenen Mittelpunkt nicht enthaelt, ist schlimmer als
# gar keine. Fuer diese Laender bleibt es beim Punkt auf der Karte.
MINDESTAUSDEHNUNG=0.05

# Eine feste Toleranz fuer alle: rund 1,1 Kilometer.
#
# Zuerst stand hier eine Toleranz nach Groesse des Gebiets. Das Ergebnis war
# eine Karte, auf der die Regionen feiner gezeichnet waren als das Land, in
# dem sie liegen - Latium ragte sichtbar aus Italien heraus. Zwei Ebenen,
# die uebereinanderliegen, muessen gleich genau sein.
TOLERANZ=0.02


def aussenringe(geom):
    """Die Aussenringe einer Geometrie, ohne Loecher, als Punktlisten."""
    return [[tuple(c[:2]) for c in poly[0]] for poly in polygone(geom)]


def ringe(rohe):
    dg=diagonale(rohe)
    if dg<MINDESTAUSDEHNUNG: return []
    minA=TOLERANZ*TOLERANZ*4
    raus=[]
    for r in rohe:
        if ringflaeche(r)<minA: continue
        v=dp(r,TOLERANZ)
        if len(v)>=4: raus.append(v)
    if not raus:
        v=dp(max(rohe,key=ringflaeche),TOLERANZ)
        if len(v)>=4: raus.append(v)
    # Ringe, die mehr als eine halbe Welt umspannen, entstehen am
    # Datumswechsel und wuerden quer ueber die Karte gezeichnet.
    return [r for r in raus if max(x for x,_ in r)-min(x for x,_ in r)<180]


def kodiere(rs):
    teile=[]
    for r in rs:
        px=py=0; s=[]
        for x,y in r:
            ix=round(x*2000); iy=round(y*2000)
            s.append(f'{ix-px},{iy-py}'); px,py=ix,iy
        teile.append(' '.join(s))
    return ';'.join(teile)

zeilen=[]
bericht=collections.Counter()

d=json.load(open(NE_A0))
for f in d['features']:
    p=f['properties']
    # Nicht nur auf „-99" pruefen: Natural Earth traegt fuer Taiwan
    # „CN-TW" ein. Gueltig ist genau ein zweibuchstabiger Code.
    def gueltig(v): return isinstance(v,str) and re.fullmatch(r'[A-Z]{2}',v)
    iso=p.get('ISO_A2')
    if not gueltig(iso): iso=p.get('ISO_A2_EH')
    if not gueltig(iso): iso=iso_namen.get(norm(p.get('NAME_EN') or p.get('NAME')))
    if not gueltig(iso): bericht['land ohne ISO']+=1; continue
    rs=ringe(aussenringe(f['geometry']))
    if not rs: bericht['land ohne Flaeche']+=1; continue
    zeilen.append(f'L\t{iso}\t{kodiere(rs)}')
    bericht['Laender']+=1

d=json.load(open(NE_A1))
uneins=[]
# Erst den Schluessel bestimmen, dann alle Stuecke eines Schluessels
# zusammenlegen und verschmelzen - in dieser Reihenfolge, weil die
# Kantenpaare nur in den unvereinfachten Punkten exakt zusammenfallen.
stuecke=collections.defaultdict(list)
for f in d['features']:
    p=f['properties']; g=p.get('gn_id'); code=None
    rohe=aussenringe(f['geometry'])
    if not rohe: bericht['Region ohne Flaeche']+=1; continue
    # Die Mehrheit der enthaltenen Orte ist die verlaesslichste Auskunft,
    # weil sie aus demselben Datensatz kommt, mit dem die App spaeter
    # sucht. Kennung und Name sind Rueckfallwege fuer Flaechen ohne Ort.
    iso_f=p.get('iso_a2')
    if g and int(g) in gn2code:
        code=gn2code[int(g)]; bericht['Region ueber Kennung']+=1
    if code is None:
        code=schluessel_aus_staedten(rohe, iso_f if re.fullmatch(r'[A-Z]{2}',iso_f or '') else None)
        if code: bericht['Region ueber Orte']+=1
    if code is None:
        for kand in (p.get('gn_name'),p.get('name'),p.get('name_en')):
            k=(p.get('iso_a2') or '')+'|'+norm(kand)
            if kand and k in name2code:
                code=name2code[k]; bericht['Region ueber Namen']+=1; break
    if code is None: bericht['Region ohne Schluessel']+=1; continue
    # Gegenprobe: Wo Kennung und Orte etwas Verschiedenes sagen, wird das
    # gezaehlt - eine stille Mehrheitsentscheidung waere hier gefaehrlich.
    if g and int(g) in gn2code and gn2code[int(g)]!=code:
        bericht['Orte und Kennung uneins']+=1
        uneins.append((p.get('iso_a2'),p.get('name'),gn2code[int(g)],code))
    stuecke[code].extend(rohe)

for code,rohe in stuecke.items():
    if len(rohe)>1:
        vorher=len(rohe); rohe=verschmelze(rohe)
        if len(rohe)<vorher: bericht['Region aus Stuecken verschmolzen']+=1
    rs=ringe(rohe)
    if not rs: bericht['Region zu klein']+=1; continue
    zeilen.append(f'R\t{code}\t{kodiere(rs)}')

# Mehrere Natural-Earth-Flaechen koennen auf denselben GeoNames-Code fallen
# (geteilte Gebiete). Zusammenfassen statt die zweite zu verlieren.
zus={}
for z in zeilen:
    art,sch,daten=z.split('\t')
    k=(art,sch)
    zus[k]=daten if k not in zus else zus[k]+';'+daten
text='\n'.join(f'{a}\t{s}\t{d}' for (a,s),d in zus.items())
roh=text.encode()
open(ZIEL,'wb').write(gzip.compress(roh,9))
print('Gebiete:',len(zus))
for k,v in sorted(bericht.items()): print(f'  {k}: {v}')
if uneins:
    print('  Beispiele fuer Uneinigkeit (Land, Flaeche, Kennung sagt, Orte sagen):')
    for e in uneins[:10]: print('   ',e)
print(f'roh {len(roh)/1024:.0f} KB, gepackt {len(gzip.compress(roh,9))/1024:.0f} KB')

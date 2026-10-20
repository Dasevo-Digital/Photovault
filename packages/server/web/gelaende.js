'use strict';

// --- Die Landschaft im Browser (Issue #181) ---------------------------------
//
// Dieselbe Spur, dasselbe Gelände und derselbe Flug wie am Rechner
// (lib/screens/gelaende_screen.dart, lib/widgets/gelaende.dart,
// lib/services/gelaendeflug.dart): Höhen von Tilezen (Terrarium), darauf
// Wanderkarte, Strassenkarte oder Luftbild, wahlweise Wanderwege,
// Ortsnamen, Höhenlinien und Gipfel/Hütten/Quellen; vier Tageszeiten; ein
// Flug mit Einflug und Abspann, Messwerten, mitlaufendem Profil und den
// Fotos an ihrer Stelle; und der Flug als Video.
//
// **Gezeichnet von MapLibre und nicht nachgebaut.** Am Rechner rechnet
// Photo Vault Netz, Licht und Kamera selbst, weil Flutter keine
// Kartenbibliothek mit Gelände hat. Im Browser gibt es eine, die genau das
// kann; nachgebaut sind hier nur die Entscheidungen – welche Quelle,
// welches Licht, welche Kamera, welcher Takt –, nicht das Zeichnen.
//
// Geladen wird diese Datei erst mit dem ersten Klick auf „Gelände
// ansehen“, MapLibre (1,1 MB) erst danach.

const LANDSCHAFT_MERKER = 'pv-landschaft';

// Wie am Rechner (gelaendesicht.dart): dreifach. Flacher sieht ein
// Mittelgebirge aus wie ein Tisch.
const UEBERHOEHUNG = 3;

// Meter je Sekunde über Grund (gelaende.dart `_flugtempo`).
const FLUGTEMPO = 300;
const EINFLUG = 0.07;
const ABSPANN = 0.10;
const BILDER_JE_SEKUNDE = 30;

// Blick in der Übersicht: von Südsüdwest, rund 55° geneigt.
const UEBERSICHT_DREHUNG = 0.35 * 180 / Math.PI;
const NEIGUNG = 0.95 * 180 / Math.PI;

const HOEHEN_URL = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';
const HOEHEN_NENNUNG = 'Höhen: Tilezen / AWS Open Data';

// Der Grund – was unten liegt (kern/services/gelaendeebenen.dart).
// `pvref://` geht über [kachelHolen]: Die Server von OpenStreetMap sperren
// Abrufe ohne Referer, und diese Seite schickt sonst keinen.
const GRUENDE = {
  wanderkarte: {
    name: 'Topografie',
    kacheln: ['pvref://tile.opentopomap.org/{z}/{x}/{y}.png'],
    max: 16,
    nennung: '© OpenStreetMap contributors, SRTM | © opentopomap.org (CC-BY-SA)',
  },
  hell: {
    name: 'Hell',
    kacheln: ['pvref://tile.openstreetmap.org/{z}/{x}/{y}.png'],
    max: 17,
    nennung: '© OpenStreetMap contributors',
  },
  // OSM-Kacheln, umgekehrt und im Farbton gedreht – wie am Rechner ohne
  // CARTO-Schlüssel: Grün bleibt grün, Wasser wird dunkelblau.
  dunkel: {
    name: 'Dunkel',
    kacheln: ['pvref://tile.openstreetmap.org/{z}/{x}/{y}.png'],
    max: 17,
    nennung: '© OpenStreetMap contributors',
    umkehren: true,
  },
  luftbild: {
    name: 'Luftbild',
    kacheln: ['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
    max: 18,
    nennung: 'Esri, Maxar, Earthstar Geographics',
  },
};
const GRUND_REIHE = ['wanderkarte', 'hell', 'dunkel', 'luftbild'];

const EBENEN = {
  wege: [
    { id: 'wanderwege', kacheln: ['https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png'], max: 16, nennung: '© waymarkedtrails.org (CC-BY-SA)' },
    { id: 'strassen', kacheln: ['https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}'], max: 18, nennung: 'Esri, HERE, Garmin' },
  ],
  beschriftung: [
    { id: 'orte', kacheln: ['https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}'], max: 18, nennung: 'Esri, HERE, Garmin, © OpenStreetMap contributors' },
  ],
};

// Die Tageszeiten (lib/services/lichtstimmung.dart): Sonne als Richtung
// (x Ost, y Nord, z oben), Grund- und Richtungslicht, Lichtfarbe, Himmel.
const STIMMUNGEN = {
  morgen: { name: 'Morgen', sonne: [-0.614, 0.692, 0.375], grund: 0.62, richtung: 0.38, licht: '#FFF4E6', oben: '#9CC0E6', unten: '#FFE8CC', dunst: '#F2E2CE' },
  mittag: { name: 'Mittag', sonne: [-0.5, 0.5, 0.707], grund: 0.72, richtung: 0.28, licht: '#FFFFFF', oben: '#5B93CE', unten: '#CFE4F5', dunst: '#C6DCEF' },
  abend: { name: 'Abend', sonne: [-0.684, 0.664, 0.302], grund: 0.58, richtung: 0.42, licht: '#FFD09C', oben: '#7C7FA8', unten: '#F09A4E', dunst: '#E0A070' },
  blaueStunde: { name: 'Blaue Stunde', sonne: [-0.573, 0.573, 0.586], grund: 0.70, richtung: 0.30, licht: '#A8B6DC', oben: '#16233F', unten: '#64789E', dunst: '#5B6E94' },
};
const STIMMUNG_REIHE = ['morgen', 'mittag', 'abend', 'blaueStunde'];

// Wie am Rechner: Gipfel braun, Hütten rot, Wasser blaugrün.
const SCHILDFARBEN = {
  gipfel: '#8D5524', sattel: '#8D5524', aussicht: '#1565C0', huette: '#B3261E', schutzhuette: '#B3261E',
  quelle: '#00838F', wasserfall: '#00838F', wegweiser: '#5D6B3A', ruine: '#5B5B5B',
};
const SCHILDZEICHEN = {
  gipfel: '▲', sattel: '⌒', aussicht: '◉', huette: '⌂', schutzhuette: '⌂', quelle: '◆', wasserfall: '≋', wegweiser: '✛', ruine: '▤',
};
const SPURFARBE = '#FF5722';

// Die Wahl dieses Browsers – wie am Rechner je Gerät und nicht für alle.
function landschaftWahl() {
  const vorgabe = { grund: 'wanderkarte', wege: false, beschriftung: false, hoehenlinien: false, wanderobjekte: false, stimmung: 'mittag' };
  try {
    const roh = JSON.parse(localStorage.getItem(LANDSCHAFT_MERKER) || '{}');
    return {
      grund: GRUENDE[roh.grund] ? roh.grund : vorgabe.grund,
      wege: roh.wege === true,
      beschriftung: roh.beschriftung === true,
      hoehenlinien: roh.hoehenlinien === true,
      wanderobjekte: roh.wanderobjekte === true,
      stimmung: STIMMUNGEN[roh.stimmung] ? roh.stimmung : vorgabe.stimmung,
    };
  } catch (_) {
    return vorgabe;
  }
}
function merkeLandschaftWahl(w) {
  try { localStorage.setItem(LANDSCHAFT_MERKER, JSON.stringify(w)); } catch (_) { /* privat */ }
}

// --- MapLibre laden --------------------------------------------------------

let maplibreLaden = null;
function ladeMaplibre() {
  if (!maplibreLaden) {
    const stil = document.createElement('link');
    stil.rel = 'stylesheet';
    stil.href = 'maplibre/maplibre-gl.css';
    document.head.insertBefore(stil, document.querySelector('link[href="app.css"]'));
    const stilDa = new Promise((fertig, fehler) => {
      stil.addEventListener('load', fertig, { once: true });
      stil.addEventListener('error', () => fehler(new Error(t('Die Karte ließ sich nicht laden.'))), { once: true });
    });
    maplibreLaden = Promise.all([import('./maplibre/maplibre-gl.mjs'), stilDa]).then(([ml]) => {
      ml.addProtocol('pvref', kachelHolen);
      return ml;
    }).catch((x) => {
      maplibreLaden = null;
      stil.remove();
      throw x;
    });
  }
  return maplibreLaden;
}

// Eine Kachel mit dem Ursprung als Referer (siehe osmKacheln in app.js):
// welche Seite gerade offen ist, erfährt der Kartenserver nicht.
async function kachelHolen(anfrage, abbruch) {
  const r = await fetch(`https://${anfrage.url.slice('pvref://'.length)}`, {
    referrerPolicy: 'strict-origin-when-cross-origin',
    signal: abbruch.signal,
  });
  if (!r.ok) throw new Error(`${r.status}`);
  return { data: await r.arrayBuffer() };
}

// --- Rechnen: Strecke, Kamera, Flug ---------------------------------------

const ERDE = 6378137;

// Die Spur in Metern um ihre Mitte (x Ost, y Nord) – für Strecke und
// Richtung genügt die flache Näherung, eine Wanderung ist kein Kontinent.
function spurInMetern(punkte) {
  let s = 0, w = 0;
  for (const p of punkte) { s += p[0]; w += p[1]; }
  const breite0 = s / punkte.length, laenge0 = w / punkte.length;
  const kx = Math.cos(breite0 * Math.PI / 180) * Math.PI / 180 * ERDE;
  const ky = Math.PI / 180 * ERDE;
  return {
    breite0, laenge0, kx, ky,
    xy: punkte.map((p) => ({ x: (p[1] - laenge0) * kx, y: (p[0] - breite0) * ky })),
    zurueck: (x, y) => [laenge0 + x / kx, breite0 + y / ky],
  };
}

// Der Flug längs der Spur (gelaendeflug.dart): geglätteter Blickpunkt,
// stark geglättete Richtung, Höhe, Tempo, Steigung, Dauer.
class Flug {
  constructor(punkte, { glaettung = 120, blickglaettung = 900 } = {}) {
    this.punkte = punkte;
    this.raum = spurInMetern(punkte);
    this.glaettung = glaettung;
    this.blickglaettung = blickglaettung;
    const xy = this.raum.xy;
    this.bisHier = [0];
    for (let i = 1; i < xy.length; i++) {
      this.bisHier.push(this.bisHier[i - 1] + Math.hypot(xy[i].x - xy[i - 1].x, xy[i].y - xy[i - 1].y));
    }
    this.laenge = this.bisHier[this.bisHier.length - 1] || 0;
    this.moeglich = punkte.length >= 2 && this.laenge > 1;
    this.richtungen = this.richtungstafel();
  }

  stelle(meter) {
    const n = this.bisHier.length;
    if (n < 2 || meter <= 0) return { tief: 0, hoch: 0, anteil: 0 };
    if (meter >= this.laenge) return { tief: n - 1, hoch: n - 1, anteil: 0 };
    let tief = 0, hoch = n - 1;
    while (hoch - tief > 1) {
      const mitte = (tief + hoch) >> 1;
      if (this.bisHier[mitte] <= meter) tief = mitte; else hoch = mitte;
    }
    const abschnitt = this.bisHier[hoch] - this.bisHier[tief];
    return { tief, hoch, anteil: abschnitt <= 0 ? 0 : (meter - this.bisHier[tief]) / abschnitt };
  }

  punktBei(meter) {
    const s = this.stelle(meter), a = this.raum.xy[s.tief], b = this.raum.xy[s.hoch];
    return { x: a.x + (b.x - a.x) * s.anteil, y: a.y + (b.y - a.y) * s.anteil };
  }

  // Der Mittelwert der Spur in einem Fenster um die Stelle – damit die
  // Kamera nicht jedes Zucken des Empfängers mitmacht.
  blickpunktBei(meter) {
    const m = Math.min(Math.max(meter, 0), this.laenge);
    const halb = Math.min(Math.min(this.glaettung, this.laenge / 2), Math.min(m, this.laenge - m));
    const von = m - halb, bis = m + halb, breite = bis - von;
    if (breite <= 0) return this.punktBei(m);
    let x = 0, y = 0;
    for (let i = this.stelle(von).tief; i < this.bisHier.length - 1; i++) {
      const a = this.bisHier[i], b = this.bisHier[i + 1];
      if (a >= bis) break;
      const l = Math.min(b, bis) - Math.max(a, von);
      if (l <= 0) continue;
      const pa = this.punktBei(Math.max(a, von)), pb = this.punktBei(Math.min(b, bis));
      x += (pa.x + pb.x) / 2 * l;
      y += (pa.y + pb.y) / 2 * l;
    }
    return { x: x / breite, y: y / breite };
  }

  fenster(meter) {
    const halb = Math.min(this.glaettung, this.laenge / 2);
    let von = meter - halb, bis = meter + halb;
    if (von < 0) { bis -= von; von = 0; }
    if (bis > this.laenge) { von -= bis - this.laenge; bis = this.laenge; }
    return { von: Math.max(0, von), bis: Math.min(this.laenge, bis) };
  }

  hoeheBei(meter) {
    const s = this.stelle(meter), a = this.punkte[s.tief]?.[2], b = this.punkte[s.hoch]?.[2];
    if (a == null) return b ?? null;
    if (b == null) return a;
    return a + (b - a) * s.anteil;
  }

  zeitBei(meter) {
    const s = this.stelle(meter), a = this.punkte[s.tief]?.[3], b = this.punkte[s.hoch]?.[3];
    if (a == null) return b ?? null;
    if (b == null) return a;
    return a + (b - a) * s.anteil;
  }

  // Die Richtung als Tafel über die Strecke: Einheitsvektoren, zweimal
  // gleitend gemittelt, dann als Winkel ohne Sprung über ±180°.
  richtungstafel() {
    if (!this.moeglich) return { schritt: 1, winkel: [0] };
    const schritt = Math.max(5, this.laenge / 4000);
    const n = Math.ceil(this.laenge / schritt) + 1;
    let vx = new Float64Array(n), vy = new Float64Array(n);
    for (let i = 0; i < n; i++) {
      const m = Math.min(this.laenge, i * schritt);
      const a = this.punktBei(Math.max(0, m - schritt)), b = this.punktBei(Math.min(this.laenge, m + schritt));
      let dx = b.x - a.x, dy = b.y - a.y;
      const l = Math.hypot(dx, dy);
      if (l > 0) { dx /= l; dy /= l; } else if (i > 0) { dx = vx[i - 1]; dy = vy[i - 1]; }
      vx[i] = dx; vy[i] = dy;
    }
    const halb = Math.max(1, Math.round(this.blickglaettung / 2 / schritt));
    for (let r = 0; r < 2; r++) { vx = kastenmittel(vx, halb); vy = kastenmittel(vy, halb); }
    const winkel = new Float64Array(n);
    let letzt = 0, haben = false;
    for (let i = 0; i < n; i++) {
      let w;
      if (Math.hypot(vx[i], vy[i]) < 1e-9) w = haben ? letzt : 0;
      else {
        w = Math.atan2(vx[i], vy[i]);
        if (haben) {
          while (w - letzt > Math.PI) w -= 2 * Math.PI;
          while (w - letzt < -Math.PI) w += 2 * Math.PI;
        }
        haben = true;
      }
      winkel[i] = w;
      letzt = w;
    }
    return { schritt, winkel };
  }

  richtungBei(meter) {
    const { schritt, winkel } = this.richtungen;
    if (winkel.length < 2) return winkel[0] || 0;
    const x = Math.min(Math.max(meter / schritt, 0), winkel.length - 1);
    const i = Math.min(Math.max(Math.floor(x), 0), winkel.length - 2);
    return winkel[i] + (winkel[i + 1] - winkel[i]) * (x - i);
  }

  bei(anteil) {
    const meter = this.laenge * Math.min(Math.max(anteil, 0), 1);
    const f = this.fenster(meter), strecke = f.bis - f.von;
    const hVon = this.hoeheBei(f.von), hBis = this.hoeheBei(f.bis);
    const zVon = this.zeitBei(f.von), zBis = this.zeitBei(f.bis);
    const start = this.zeitBei(0), jetzt = this.zeitBei(meter);
    let tempo = null, steigung = null;
    if (zVon != null && zBis != null && strecke > 0 && zBis > zVon) tempo = strecke / ((zBis - zVon) / 1000);
    if (hVon != null && hBis != null && strecke > 0) steigung = (hBis - hVon) / strecke * 100;
    return {
      blickpunkt: this.blickpunktBei(meter),
      drehung: this.richtungBei(meter),
      meter,
      hoehe: this.hoeheBei(meter),
      tempo,
      steigung,
      seitStart: start == null || jetzt == null ? null : Math.max(0, jetzt - start),
    };
  }

  // Aufstieg mit drei Metern Rauschschwelle, wie am Rechner.
  get aufstieg() {
    let letzte = null, summe = 0, gesehen = false;
    for (const p of this.punkte) {
      const h = p[2];
      if (h == null) continue;
      gesehen = true;
      if (letzte == null) { letzte = h; continue; }
      const d = h - letzte;
      if (d > 3) { summe += d; letzte = h; } else if (d < -3) letzte = h;
    }
    return gesehen ? summe : null;
  }

  get gesamtdauer() {
    let erste = null, letzte = null;
    for (const p of this.punkte) { if (p[3] == null) continue; erste ??= p[3]; letzte = p[3]; }
    return erste == null || letzte < erste ? null : letzte - erste;
  }

  // Zehn Sekunden bis drei Minuten, dazu Einflug und Abspann obendrauf.
  get dauerMs() {
    const flug = this.moeglich ? Math.min(Math.max(this.laenge / FLUGTEMPO, 10), 180) : 10;
    return flug * 1000 / (1 - EINFLUG - ABSPANN);
  }
}

function kastenmittel(werte, halb) {
  const n = werte.length, summe = new Float64Array(n + 1);
  for (let i = 0; i < n; i++) summe[i + 1] = summe[i] + werte[i];
  const bis = (i) => summe[Math.min(Math.max(i, 0), n)] + (i < 0 ? werte[0] * i : 0) + (i > n ? werte[n - 1] * (i - n) : 0);
  const aus = new Float64Array(n);
  for (let i = 0; i < n; i++) aus[i] = (bis(i + halb + 1) - bis(i - halb)) / (2 * halb + 1);
  return aus;
}

function abschnittBei(u) {
  const b = 1 - ABSPANN;
  return {
    einflug: u < EINFLUG ? Math.min(Math.max(u / EINFLUG, 0), 1) : 1,
    flug: Math.min(Math.max((u - EINFLUG) / (b - EINFLUG), 0), 1),
    abspann: u <= b ? 0 : Math.min(Math.max((u - b) / (1 - b), 0), 1),
  };
}

const sanft = (u) => (u < 0.5 ? 4 * u * u * u : 1 - (-2 * u + 2) ** 3 / 2);
const einblenden = (u) => 1 - (1 - u) * (1 - u);
const ausblenden = (u) => u * u;

// Die Zoomstufe, bei der die Kamera [meter] vom Blickpunkt entfernt ist.
function zoomFuerAbstand(meter, breite, hoeheBild, fovGrad = 36.87) {
  const mittelpunktAbstand = 0.5 * hoeheBild / Math.tan(fovGrad * Math.PI / 360);
  return Math.log2(2 * Math.PI * ERDE * Math.cos(breite * Math.PI / 180) * mittelpunktAbstand / (512 * meter));
}

// Zwischen zwei Kameras mischen – die Drehung auf dem kürzeren Weg, sonst
// dreht sich die Landschaft beim Einflug einmal ganz herum.
function mischeKamera(a, b, u) {
  const m = (x, y) => x + (y - x) * u;
  let dd = b.bearing - a.bearing;
  while (dd > 180) dd -= 360;
  while (dd < -180) dd += 360;
  return {
    center: [m(a.center[0], b.center[0]), m(a.center[1], b.center[1])],
    zoom: m(a.zoom, b.zoom),
    pitch: m(a.pitch, b.pitch),
    bearing: a.bearing + dd * u,
  };
}

// --- Höhenlinien -----------------------------------------------------------
//
// Selbst gerechnet wie am Rechner (hoehenlinien.dart): Terrarium-Kacheln
// auf ein Gitter, dann Marching Squares. Abstand nach der Spanne, höchstens
// dreissig Linien; jede fünfte ist eine Zähllinie.

function hoehenlinienAbstand(spanne) {
  for (const s of [5, 10, 20, 25, 50, 100, 200, 500, 1000]) if (spanne / s <= 30) return s;
  return 1000;
}

const kachelX = (laenge, z) => (laenge + 180) / 360 * 2 ** z;
const kachelY = (breite, z) => {
  const r = breite * Math.PI / 180;
  return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * 2 ** z;
};
const laengeAus = (x, z) => x / 2 ** z * 360 - 180;
const breiteAus = (y, z) => {
  const n = Math.PI - 2 * Math.PI * y / 2 ** z;
  return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)));
};

async function hoehengitter(kasten, signal) {
  // So fein, dass der Ausschnitt höchstens vier mal vier Kacheln braucht.
  let z = 14;
  while (z > 8 && (Math.floor(kachelX(kasten.ost, z)) - Math.floor(kachelX(kasten.west, z)) > 3
    || Math.floor(kachelY(kasten.sued, z)) - Math.floor(kachelY(kasten.nord, z)) > 3)) z--;
  const x0 = Math.floor(kachelX(kasten.west, z)), x1 = Math.floor(kachelX(kasten.ost, z));
  const y0 = Math.floor(kachelY(kasten.nord, z)), y1 = Math.floor(kachelY(kasten.sued, z));
  const breite = (x1 - x0 + 1) * 256, hoehe = (y1 - y0 + 1) * 256;
  const leinwand = document.createElement('canvas');
  leinwand.width = breite;
  leinwand.height = hoehe;
  const ctx = leinwand.getContext('2d', { willReadFrequently: true });
  const auftraege = [];
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      auftraege.push(fetch(HOEHEN_URL.replace('{z}', z).replace('{x}', x).replace('{y}', y), { signal })
        .then((r) => (r.ok ? r.blob() : null))
        .then((b) => (b ? createImageBitmap(b) : null))
        .then((bild) => { if (bild) ctx.drawImage(bild, (x - x0) * 256, (y - y0) * 256); })
        .catch(() => {}));
    }
  }
  await Promise.all(auftraege);
  const roh = ctx.getImageData(0, 0, breite, hoehe).data;
  return {
    hoeheBei(laenge, breiteGrad) {
      const px = (kachelX(laenge, z) - x0) * 256, py = (kachelY(breiteGrad, z) - y0) * 256;
      const i = Math.floor(px), j = Math.floor(py);
      if (i < 0 || j < 0 || i >= breite - 1 || j >= hoehe - 1) return null;
      const fx = px - i, fy = py - j;
      const h = (a, b) => {
        const k = (b * breite + a) * 4;
        if (roh[k + 3] === 0) return null;
        return roh[k] * 256 + roh[k + 1] + roh[k + 2] / 256 - 32768;
      };
      const a = h(i, j), b = h(i + 1, j), c = h(i, j + 1), d = h(i + 1, j + 1);
      if (a == null || b == null || c == null || d == null) return null;
      return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
    },
  };
}

function hoehenlinien(gitter, kasten, maschen = 160) {
  const n = maschen + 1;
  const h = new Array(n * n);
  let tief = Infinity, hoch = -Infinity;
  const z = 16;
  const xW = kachelX(kasten.west, z), xO = kachelX(kasten.ost, z);
  const yN = kachelY(kasten.nord, z), yS = kachelY(kasten.sued, z);
  const laengeBei = (u) => laengeAus(xW + (xO - xW) * u, z);
  const breiteBei = (u) => breiteAus(yN + (yS - yN) * u, z);
  for (let j = 0; j < n; j++) {
    const b = breiteBei(j / maschen);
    for (let i = 0; i < n; i++) {
      const w = gitter.hoeheBei(laengeBei(i / maschen), b);
      h[j * n + i] = w;
      if (w != null) { if (w < tief) tief = w; if (w > hoch) hoch = w; }
    }
  }
  const linien = [], zaehl = [];
  if (!Number.isFinite(tief)) return { linien, zaehl };
  const abstand = hoehenlinienAbstand(hoch - tief);
  const anteil = (a, b, ziel) => (Math.abs(b - a) < 1e-9 ? 0.5 : Math.min(Math.max((ziel - a) / (b - a), 0), 1));
  const ort = (x, y) => [laengeBei(x), breiteBei(y)];
  const erste = Math.ceil(tief / abstand), letzte = Math.floor(hoch / abstand);
  for (let k = erste; k <= letzte && k - erste < 200; k++) {
    const ziel = k * abstand;
    const wohin = k % 5 === 0 ? zaehl : linien;
    for (let j = 0; j < maschen; j++) {
      for (let i = 0; i < maschen; i++) {
        const a = h[j * n + i], b = h[j * n + i + 1], c = h[(j + 1) * n + i + 1], d = h[(j + 1) * n + i];
        if (a == null || b == null || c == null || d == null) continue;
        // Eine Zelle ohne Höhenunterschied (See, Talsohle) bekommt keine
        // Linie – das Rauschen der Interpolation zöge sonst eine hindurch.
        if (Math.max(a, b, c, d) - Math.min(a, b, c, d) < 1e-6) continue;
        const x0 = i / maschen, x1 = (i + 1) / maschen, y0 = j / maschen, y1 = (j + 1) / maschen;
        const p = [];
        if ((a > ziel) !== (b > ziel)) p.push(ort(x0 + (x1 - x0) * anteil(a, b, ziel), y0));
        if ((b > ziel) !== (c > ziel)) p.push(ort(x1, y0 + (y1 - y0) * anteil(b, c, ziel)));
        if ((d > ziel) !== (c > ziel)) p.push(ort(x0 + (x1 - x0) * anteil(d, c, ziel), y1));
        if ((a > ziel) !== (d > ziel)) p.push(ort(x0, y0 + (y1 - y0) * anteil(a, d, ziel)));
        for (let q = 0; q + 1 < p.length; q += 2) wohin.push([p[q], p[q + 1]]);
      }
    }
  }
  return { linien, zaehl };
}

// --- Darstellung -----------------------------------------------------------

function farbteile(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

// Was eine Tageszeit an Grund, Relief und Himmel ändert. Das Licht ist am
// Rechner Grundlicht plus Richtungslicht mal Lichtfarbe; MapLibre kann den
// Grund nur aufhellen oder abdunkeln, die Farbe kommt als Schleier.
function stimmungsfarben(s, grund) {
  const [r, g, b] = farbteile(s.licht);
  const hell = Math.min(1, (s.grund + s.richtung * s.sonne[2]) * (r + g + b) / 765 + 0.08);
  const schleier = (1 - Math.min(r, g, b) / 255) * 0.6;
  // Der Schleier färbt und dunkelt zugleich: die Lichtfarbe, so hell wie
  // das Licht. Eine helle Farbe darüber machte den Abend blasser statt
  // wärmer.
  const schleierfarbe = `rgb(${Math.round(r * hell)}, ${Math.round(g * hell)}, ${Math.round(b * hell)})`;
  const richtung = (Math.atan2(s.sonne[0], s.sonne[1]) * 180 / Math.PI + 360) % 360;
  const hoehe = Math.asin(Math.min(1, s.sonne[2])) * 180 / Math.PI;
  const relief = grund === 'luftbild' ? 0.45 : 1;
  return { hell, schleier, schleierfarbe, richtung, hoehe, relief };
}

function rasterFarbe(grundName, s) {
  const f = stimmungsfarben(s, grundName);
  if (GRUENDE[grundName].umkehren) {
    return { 'raster-brightness-min': f.hell * 0.95, 'raster-brightness-max': 0.04, 'raster-hue-rotate': 180, 'raster-saturation': -0.2 };
  }
  return { 'raster-brightness-min': 0, 'raster-brightness-max': f.hell, 'raster-hue-rotate': 0, 'raster-saturation': 0 };
}

function himmel(s) {
  return {
    'sky-color': s.oben,
    'horizon-color': s.unten,
    'fog-color': s.dunst,
    'sky-horizon-blend': 0.6,
    'horizon-fog-blend': 0.7,
    'fog-ground-blend': 0.8,
    'atmosphere-blend': 0,
  };
}

function reliefFarbe(grundName, s) {
  const f = stimmungsfarben(s, grundName);
  const [r, g, b] = farbteile(s.licht);
  return {
    'hillshade-illumination-direction': f.richtung,
    'hillshade-illumination-altitude': f.hoehe,
    'hillshade-illumination-anchor': 'map',
    'hillshade-exaggeration': 0.55 * f.relief,
    'hillshade-shadow-color': `rgba(18, 22, 40, ${0.55 * f.relief})`,
    'hillshade-highlight-color': `rgba(${r}, ${g}, ${b}, ${0.35 * f.relief})`,
    'hillshade-accent-color': `rgba(18, 22, 40, ${0.25 * f.relief})`,
  };
}

function nennung(wahl, mitSchildern) {
  const teile = [GRUENDE[wahl.grund].nennung];
  for (const e of [...(wahl.wege ? EBENEN.wege : []), ...(wahl.beschriftung ? EBENEN.beschriftung : [])]) {
    if (!teile.includes(e.nennung)) teile.push(e.nennung);
  }
  if (mitSchildern && !teile.some((x) => x.includes('OpenStreetMap'))) teile.push('© OpenStreetMap contributors (ODbL)');
  teile.push(t(HOEHEN_NENNUNG));
  return teile.join(' · ');
}

// „1:04:37“ bzw. „4:37“ – wie man eine Dauer liest.
function dauerUhr(ms) {
  const g = Math.round(ms / 1000);
  const h = Math.floor(g / 3600), m = Math.floor((g % 3600) / 60), s = String(g % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

const eineStelle = new Intl.NumberFormat(GEBIET, { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function messwerte(stand) {
  const werte = [];
  if (stand.hoehe != null) werte.push({ name: t('Höhe'), wert: t('{meter} m', { meter: zahl.format(Math.round(stand.hoehe)) }) });
  if (stand.tempo != null) werte.push({ name: t('Tempo'), wert: t('{wert} km/h', { wert: eineStelle.format(stand.tempo * 3.6) }) });
  if (stand.steigung != null) {
    const st = stand.steigung;
    werte.push({ name: t('Steigung'), wert: t('{wert} %', { wert: eineStelle.format(st) }), richtung: Math.abs(st) < 1 ? null : st > 0 ? 'auf' : 'ab' });
  }
  if (stand.seitStart != null) werte.push({ name: t('unterwegs'), wert: dauerUhr(stand.seitStart) });
  return werte;
}

// --- Die Ansicht -----------------------------------------------------------

let landschaft = null;

async function oeffneLandschaft(spur, aktivitaet, aufnahmen) {
  schliesseLandschaft();
  const flug = new Flug(spur.punkte);
  const wahl = landschaftWahl();
  const box = el('div', 'landschaft');
  box.id = 'landschaft';
  box.setAttribute('role', 'dialog');
  box.setAttribute('aria-label', t('Gelände'));

  // Kopf: Titel, Karte, Tageszeit, schliessen.
  const kopf = el('header', 'l-kopf');
  const titel = el('div', 'l-titel');
  titel.append(el('h2', null, aktivitaet.name), el('p', 'leise klein', t('Ziehen dreht und kippt · Rollen zoomt')));
  const karteKnopf = el('button', 'knopf-flach', `🗺 ${t('Karte auf der Landschaft')}`);
  karteKnopf.type = 'button';
  const stimmungKnopf = el('button', 'knopf-flach', `☀ ${t('Tageszeit')}`);
  stimmungKnopf.type = 'button';
  const zu = el('button', 'l-zu', '×');
  zu.type = 'button';
  zu.setAttribute('aria-label', t('Schliessen'));
  kopf.append(titel, karteKnopf, stimmungKnopf, zu);

  const flaeche = el('div', 'l-flaeche');
  const kartenbox = el('div', 'l-karte');
  const laden = el('div', 'l-laden', t('Holt Geländehöhen …'));
  const flugbild = el('figure', 'l-flugbild');
  const flugbildImg = el('img');
  flugbildImg.alt = '';
  const flugbildText = el('figcaption');
  flugbild.append(flugbildImg, flugbildText);
  const abspann = el('div', 'l-abspann');
  const fuss = el('p', 'l-fuss');
  flaeche.append(kartenbox, laden, flugbild, abspann, fuss);

  // Leiste: Steuerung, Regler, Messwerte, Profil.
  const leiste = el('footer', 'l-leiste');
  const reihe = el('div', 'l-reihe');
  const spielen = el('button', 'knopf', `▶ ${t('Flug starten')}`);
  spielen.type = 'button';
  const beenden = el('button', 'knopf-flach', `⤺ ${t('Zur Übersicht')}`);
  beenden.type = 'button';
  beenden.hidden = true;
  const video = el('button', 'knopf-flach', `⤓ ${t('Als Video ausgeben')}`);
  video.type = 'button';
  const regler = el('input');
  regler.type = 'range';
  regler.min = '0';
  regler.max = '1000';
  regler.value = '0';
  regler.setAttribute('aria-label', t('Stelle auf der Spur'));
  const kmText = el('span', 'l-km');
  reihe.append(spielen, beenden, video, regler, kmText);
  const werteZeile = el('div', 'l-werte');
  const ausgabe = el('div', 'l-ausgabe');
  ausgabe.hidden = true;
  const ausgabeBalken = el('progress');
  ausgabeBalken.max = 1;
  const ausgabeText = el('span', 'leise klein');
  ausgabe.append(ausgabeBalken, ausgabeText);
  const profil = flugprofil(flug);
  leiste.append(ausgabe, reihe, werteZeile, profil.box);

  box.append(kopf, flaeche, leiste);
  document.body.append(box);
  document.body.classList.add('landschaft-offen');

  const zustand = {
    box, flug, wahl, karte: null, ml: null, lauf: 0,
    uhr: 0, spielt: false, imFlug: false, letzterTakt: 0,
    versatz: 0, zoomVersatz: 0, neigung: NEIGUNG,
    automatisch: null, schilder: [], fotos: [], gitter: null, kasten: null,
    abbruch: new AbortController(), video: null,
    spielen, beenden, regler, kmText, werteZeile, flugbild, flugbildImg, flugbildText, abspann, fuss, profil,
    ausgabe, ausgabeBalken, ausgabeText, videoKnopf: video, laden, karteKnopf, stimmungKnopf,
  };
  landschaft = zustand;

  zu.addEventListener('click', schliesseLandschaft);
  spielen.addEventListener('click', () => flugSchalten(zustand));
  beenden.addEventListener('click', () => flugBeenden(zustand));
  regler.addEventListener('input', () => spulen(zustand, Number(regler.value) / 1000));
  video.addEventListener('click', () => videoAusgeben(zustand));
  karteKnopf.addEventListener('click', () => karteMenue(zustand));
  stimmungKnopf.addEventListener('click', () => stimmungMenue(zustand));
  zeigeStand(zustand);

  try {
    const ml = await ladeMaplibre();
    if (landschaft !== zustand) return;
    zustand.ml = ml;
    baueKarte(zustand, kartenbox);
  } catch (x) {
    laden.textContent = x.message;
    return;
  }
  zustand.fotos = fotosAufDieSpur(flug, aufnahmen);
}

function schliesseLandschaft() {
  const z = landschaft;
  if (!z) return;
  landschaft = null;
  z.lauf++;
  z.abbruch.abort();
  if (z.video) z.video.abbruch = true;
  z.karte?.remove();
  z.box.remove();
  document.body.classList.remove('landschaft-offen');
}

function kastenUm(flug) {
  let sued = 90, nord = -90, west = 180, ost = -180;
  for (const p of flug.punkte) {
    sued = Math.min(sued, p[0]); nord = Math.max(nord, p[0]);
    west = Math.min(west, p[1]); ost = Math.max(ost, p[1]);
  }
  // Ein Fünftel Rand – ein Weg am Abgrund der Welt sieht falsch aus.
  const rb = Math.max((nord - sued) * 0.2, 0.004), rl = Math.max((ost - west) * 0.2, 0.006);
  return { sued: sued - rb, nord: nord + rb, west: west - rl, ost: ost + rl };
}

function stilFuer(z) {
  const w = z.wahl, s = STIMMUNGEN[w.stimmung], g = GRUENDE[w.grund];
  const sources = {
    hoehen: { type: 'raster-dem', tiles: [HOEHEN_URL], encoding: 'terrarium', tileSize: 256, maxzoom: 15 },
    relief: { type: 'raster-dem', tiles: [HOEHEN_URL], encoding: 'terrarium', tileSize: 256, maxzoom: 15 },
    grund: { type: 'raster', tiles: g.kacheln, tileSize: 256, maxzoom: g.max },
    spur: { type: 'geojson', lineMetrics: true, data: { type: 'Feature', geometry: { type: 'LineString', coordinates: z.flug.punkte.map((p) => [p[1], p[0]]) } } },
    hoehenlinien: { type: 'geojson', data: { type: 'FeatureCollection', features: [] } },
    schleier: { type: 'geojson', data: { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[-180, -85], [180, -85], [180, 85], [-180, 85], [-180, -85]]] } } },
  };
  for (const e of [...EBENEN.wege, ...EBENEN.beschriftung]) sources[e.id] = { type: 'raster', tiles: e.kacheln, tileSize: 256, maxzoom: e.max };
  const layers = [
    { id: 'hintergrund', type: 'background', paint: { 'background-color': s.dunst } },
    { id: 'grund', type: 'raster', source: 'grund', paint: { ...rasterFarbe(w.grund, s), 'raster-fade-duration': 0 } },
    { id: 'relief', type: 'hillshade', source: 'relief', paint: reliefFarbe(w.grund, s) },
    ...EBENEN.wege.map((e) => ({ id: e.id, type: 'raster', source: e.id, layout: { visibility: w.wege ? 'visible' : 'none' }, paint: { 'raster-opacity': 0.9 } })),
    ...EBENEN.beschriftung.map((e) => ({ id: e.id, type: 'raster', source: e.id, layout: { visibility: w.beschriftung ? 'visible' : 'none' } })),
    { id: 'schleier', type: 'fill', source: 'schleier', paint: { 'fill-color': stimmungsfarben(s, w.grund).schleierfarbe, 'fill-opacity': stimmungsfarben(s, w.grund).schleier } },
    { id: 'hoehenlinien', type: 'line', source: 'hoehenlinien', filter: ['!=', ['get', 'zaehl'], true], layout: { visibility: w.hoehenlinien ? 'visible' : 'none' }, paint: { 'line-color': 'rgba(110, 72, 36, 0.55)', 'line-width': 0.8 } },
    { id: 'zaehllinien', type: 'line', source: 'hoehenlinien', filter: ['==', ['get', 'zaehl'], true], layout: { visibility: w.hoehenlinien ? 'visible' : 'none' }, paint: { 'line-color': 'rgba(110, 72, 36, 0.75)', 'line-width': 1.6 } },
    { id: 'spur-rand', type: 'line', source: 'spur', layout: { 'line-join': 'round', 'line-cap': 'round' }, paint: { 'line-color': 'rgba(255, 255, 255, 0.85)', 'line-width': 7 } },
    { id: 'spur', type: 'line', source: 'spur', layout: { 'line-join': 'round', 'line-cap': 'round' }, paint: { 'line-color': SPURFARBE, 'line-width': 4, 'line-gradient': spurVerlauf(1) } },
  ];
  return {
    version: 8,
    sources,
    layers,
    terrain: { source: 'hoehen', exaggeration: UEBERHOEHUNG },
    sky: himmel(s),
  };
}

// MapLibre legt das, was auf dem Gelände liegt, als Textur ab und zeichnet
// sie erst neu, wenn sich Kacheln oder die Liste der sichtbaren Ebenen
// ändern – eine neue Farbe allein reicht nicht (render_to_texture.ts,
// 6.11). Eine unsichtbare Ebene, die kommt oder geht, ändert die Liste.
function auffrischen(karte) {
  if (karte.getLayer('auffrischen')) karte.removeLayer('auffrischen');
  else karte.addLayer({ id: 'auffrischen', type: 'background', paint: { 'background-opacity': 0 } }, 'hintergrund');
}

// Der zurückgelegte Teil voll, der kommende blass – wie am Rechner.
function spurVerlauf(anteil) {
  const voll = SPURFARBE, blass = 'rgba(255, 87, 34, 0.4)';
  if (anteil >= 0.999) return ['interpolate', ['linear'], ['line-progress'], 0, voll, 1, voll];
  if (anteil <= 0.001) return ['interpolate', ['linear'], ['line-progress'], 0, blass, 1, blass];
  return ['interpolate', ['linear'], ['line-progress'], 0, voll, anteil, voll, Math.min(0.9999, anteil + 0.0005), blass, 1, blass];
}

function baueKarte(z, kartenbox) {
  const ml = z.ml;
  z.kasten = kastenUm(z.flug);
  z.gebaut = z.wahl;
  z.uebersicht = null;
  const karte = new ml.Map({
    container: kartenbox,
    style: stilFuer(z),
    bounds: [[z.kasten.west, z.kasten.sued], [z.kasten.ost, z.kasten.nord]],
    pitch: NEIGUNG,
    bearing: UEBERSICHT_DREHUNG,
    maxPitch: 85,
    attributionControl: false,
  });
  z.karte = karte;
  karte.addControl(new ml.NavigationControl({ visualizePitch: true }), 'top-right');
  karte.on('load', () => {
    if (landschaft !== z) return;
    z.uebersicht = uebersichtKamera(z);
    karte.jumpTo(z.uebersicht);
    z.laden.hidden = true;
    // Die Karte entstand mit der Wahl von damals; was seither im Menü
    // umgestellt wurde, kommt jetzt dazu.
    z.angewandt = z.gebaut;
    wendeWahlAn(z);
    if (z.wahl.wanderobjekte) holeSchilder(z);
    if (z.wahl.hoehenlinien) rechneHoehenlinien(z);
    zeigeFuss(z);
    setzeFotomarken(z);
  });
  karte.on('error', (e) => {
    // Eine fehlende Kachel ist kein Fehler der Ansicht; nur wenn die
    // Höhen gar nicht kommen, sagt die Ansicht es – mit einem zweiten
    // Versuch, wie am Rechner.
    if (e?.sourceId !== 'hoehen' || karte.loaded() || landschaft !== z) return;
    const nochmal = el('button', 'knopf-flach', t('Noch einmal versuchen'));
    nochmal.type = 'button';
    nochmal.addEventListener('click', () => {
      karte.remove();
      z.laden.replaceChildren(t('Holt Geländehöhen …'));
      baueKarte(z, kartenbox);
    });
    const text = el('p', null, t('Für diesen Ausschnitt kamen keine Geländehöhen an. Die Kacheln liegen im Netz; ohne Verbindung gibt es keine Landschaft.'));
    z.laden.replaceChildren(text, nochmal);
    z.laden.hidden = false;
  });
  // Wer im Flug zieht, dreht sich um – die Richtung gehört weiter dem Weg.
  const vomNutzer = (e) => e && e.originalEvent;
  karte.on('rotate', (e) => { if (z.imFlug && vomNutzer(e) && z.automatisch) z.versatz = karte.getBearing() - z.automatisch.bearing; });
  karte.on('pitch', (e) => { if (vomNutzer(e)) z.neigung = karte.getPitch(); });
  karte.on('zoom', (e) => { if (z.imFlug && vomNutzer(e) && z.automatisch) z.zoomVersatz = karte.getZoom() - z.automatisch.zoom; });
}

function uebersichtKamera(z) {
  const karte = z.karte;
  const k = z.kasten;
  const breite = karte.getContainer().clientWidth, hoehe = karte.getContainer().clientHeight;
  const rand = Math.min(60, Math.max(16, Math.min(breite, hoehe) / 10));
  const kamera = karte.cameraForBounds([[k.west, k.sued], [k.ost, k.nord]], { padding: rand, bearing: UEBERSICHT_DREHUNG, pitch: z.neigung });
  return {
    center: kamera ? [kamera.center.lng ?? kamera.center[0], kamera.center.lat ?? kamera.center[1]] : [(k.west + k.ost) / 2, (k.sued + k.nord) / 2],
    // Geneigt rückt der nahe Rand heran und der ferne weg; was von oben
    // genau passt, ist schräg zu klein. Ein halber Schritt näher füllt
    // die Ansicht wie am Rechner der Geländeblock.
    zoom: (kamera?.zoom ?? 12) + 0.5,
    bearing: UEBERSICHT_DREHUNG,
    pitch: z.neigung,
  };
}

// Wo die Kamera im Flug steht: hinter dem geglätteten Blickpunkt, in
// Richtung des Weges, im Abstand eines Bruchteils des Ausschnitts.
function flugKamera(z, stand) {
  const karte = z.karte;
  const ort = z.flug.raum.zurueck(stand.blickpunkt.x, stand.blickpunkt.y);
  const k = z.kasten;
  const ausdehnung = Math.max((k.ost - k.west) * z.flug.raum.kx, (k.nord - k.sued) * z.flug.raum.ky);
  // Knapp die Hälfte des Ausschnitts: näher sieht man nur noch den Weg
  // und nicht mehr, wo im Gelände er liegt.
  const abstand = Math.min(Math.max(ausdehnung * 0.45, 800), 8000);
  const zoom = zoomFuerAbstand(abstand, ort[1], karte.getContainer().clientHeight || 600);
  return { center: ort, zoom, bearing: stand.drehung * 180 / Math.PI, pitch: z.neigung };
}

function kameraBei(z, u) {
  const a = abschnittBei(u);
  const stand = z.flug.bei(a.flug);
  const uebersicht = { ...z.uebersicht, pitch: z.neigung };
  if (a.einflug < 1) return { stand, abschnitt: a, kamera: mischeKamera(uebersicht, flugKamera(z, z.flug.bei(0)), sanft(a.einflug)) };
  if (a.abspann > 0) return { stand, abschnitt: a, kamera: mischeKamera(flugKamera(z, z.flug.bei(1)), uebersicht, sanft(a.abspann)) };
  return { stand, abschnitt: a, kamera: flugKamera(z, stand) };
}

function zeigeBild(z, u) {
  if (!z.karte || !z.uebersicht) return;
  const { stand, abschnitt, kamera } = kameraBei(z, u);
  z.automatisch = kamera;
  const nutzer = { ...kamera, bearing: kamera.bearing + z.versatz, zoom: kamera.zoom + z.zoomVersatz };
  z.karte.jumpTo(nutzer);
  setzeSpurstand(z.karte, z, stand.meter, !z.spielt);
  zeigeStand(z, stand, abschnitt);
}

// Wie weit die Spur schon voll gezeichnet ist. Im laufenden Flug höchstens
// alle drei Zehntelsekunden neu (siehe [auffrischen]): Alles auf dem
// Gelände neu zu zeichnen kostet, und die Kamera bewegt sich ohnehin.
function setzeSpurstand(karte, z, meter, sofort) {
  karte.setPaintProperty('spur', 'line-gradient', spurVerlauf(meter / (z.flug.laenge || 1)));
  const jetzt = performance.now();
  if (sofort || !z.spurGefrischt || jetzt - z.spurGefrischt > 300) {
    z.spurGefrischt = jetzt;
    auffrischen(karte);
  }
}

function takt(z, jetzt) {
  if (landschaft !== z || !z.spielt) return;
  const dt = z.letzterTakt ? jetzt - z.letzterTakt : 0;
  z.letzterTakt = jetzt;
  z.uhr = Math.min(1, z.uhr + dt / z.flug.dauerMs);
  zeigeBild(z, z.uhr);
  if (z.uhr >= 1) { z.spielt = false; zeigeStand(z); return; }
  requestAnimationFrame((x) => takt(z, x));
}

function flugSchalten(z) {
  if (!z.karte || !z.uebersicht) return;
  if (!z.imFlug) {
    z.imFlug = true;
    z.versatz = 0;
    z.zoomVersatz = 0;
    z.uhr = 0;
  } else if (z.spielt) {
    z.spielt = false;
    zeigeStand(z);
    return;
  } else if (z.uhr >= 1) {
    z.uhr = 0;
  }
  z.spielt = true;
  z.letzterTakt = 0;
  requestAnimationFrame((x) => takt(z, x));
  zeigeStand(z);
}

function flugBeenden(z) {
  z.spielt = false;
  z.imFlug = false;
  z.uhr = 0;
  z.versatz = 0;
  z.zoomVersatz = 0;
  if (z.karte) setzeSpurstand(z.karte, z, z.flug.laenge, true);
  if (z.uebersicht) z.karte.easeTo({ ...z.uebersicht, pitch: z.neigung, duration: 800 });
  zeigeStand(z);
}

function spulen(z, wert) {
  if (!z.karte || !z.uebersicht) return;
  z.spielt = false;
  z.imFlug = true;
  z.uhr = Math.min(Math.max(wert, 0), 1);
  zeigeBild(z, z.uhr);
}

// Knöpfe, Regler, Messwerte, Foto und Abspann zum Stand der Uhr.
function zeigeStand(z, stand, abschnitt) {
  const s = stand || (z.imFlug ? z.flug.bei(abschnittBei(z.uhr).flug) : null);
  const a = abschnitt || abschnittBei(z.uhr);
  z.spielen.textContent = !z.imFlug ? `▶ ${t('Flug starten')}` : z.spielt ? `❚❚ ${t('Anhalten')}` : z.uhr >= 1 ? `↻ ${t('Noch einmal')}` : `▶ ${t('Weiter')}`;
  z.beenden.hidden = !z.imFlug;
  z.regler.value = String(Math.round(z.uhr * 1000));
  z.kmText.textContent = t('{wert} km', { wert: eineStelle.format((s ? s.meter : z.flug.laenge) / 1000) });
  z.werteZeile.replaceChildren();
  if (s) {
    const werte = messwerte(s);
    if (!werte.length) z.werteZeile.append(el('span', 'leise klein', t('Die Spur trägt keine Zeitstempel – ohne sie gibt es kein Tempo.')));
    for (const w of werte) z.werteZeile.append(messwertEl(w));
  }
  z.profil.zeige(s ? s.meter : null);
  // Das Foto zur Stelle: das zuletzt erreichte, aufblendend.
  const foto = s && z.imFlug ? fotoBei(z, s.meter) : null;
  if (foto) {
    if (z.flugbildImg.dataset.id !== foto.id) {
      z.flugbildImg.dataset.id = foto.id;
      z.flugbildImg.src = miniaturUrl(foto.id);
      z.flugbildText.textContent = foto.unterschrift;
    }
    const weg = Math.max(40, z.flug.laenge * 0.01);
    z.flugbild.style.opacity = String(Math.min(Math.max((s.meter - foto.meter) / weg, 0), 1) * (1 - ausblenden(a.abspann)));
    z.flugbild.hidden = false;
  } else {
    z.flugbild.hidden = true;
  }
  // Der Abspann: die Zahlen der Tour, wenn die Kamera wieder aufzieht.
  if (z.imFlug && a.abspann > 0) {
    if (!z.abspann.childElementCount) z.abspann.append(...abspannInhalt(z.flug));
    z.abspann.style.opacity = String(ausblenden(a.abspann));
    z.abspann.hidden = false;
  } else {
    z.abspann.hidden = true;
  }
}

function messwertEl(w) {
  const e = el('span', 'l-wert');
  const wert = el('b', w.richtung ? `l-${w.richtung}` : null, w.wert);
  e.append(el('span', 'leise klein', w.name), wert);
  return e;
}

function abspannInhalt(flug) {
  const teile = [el('div', 'l-gross', `${eineStelle.format(flug.laenge / 1000)} km`)];
  const zahlen = el('div', 'l-zahlen');
  const auf = flug.aufstieg, dauer = flug.gesamtdauer;
  if (auf != null) zahlen.append(zahlEl(`${zahl.format(Math.round(auf))} m`, t('Aufstieg')));
  if (dauer != null) zahlen.append(zahlEl(dauerUhr(dauer), t('unterwegs')));
  if (zahlen.childElementCount) teile.push(zahlen);
  return teile;
}

function zahlEl(wert, was) {
  const e = el('div');
  e.append(el('b', null, wert), el('span', 'leise klein', was));
  return e;
}

function zeigeFuss(z) {
  z.fuss.textContent = `${nennung(z.wahl, z.wahl.wanderobjekte && z.schilder.length > 0)} · ${t('Höhe {faktor}-fach überhöht', { faktor: UEBERHOEHUNG })}`;
}

// Das Profil in der Leiste, mit der Stelle des Fluges.
function flugprofil(flug) {
  const box = el('div', 'l-profil');
  const punkte = [];
  flug.punkte.forEach((p, i) => { if (p[2] != null) punkte.push({ m: flug.bisHier[i], h: p[2] }); });
  if (punkte.length < 2) return { box, zeige() {} };
  const B = 1000, H = 60;
  const tief = Math.min(...punkte.map((p) => p.h)), hoch = Math.max(...punkte.map((p) => p.h));
  const spanne = Math.max(hoch - tief, 10);
  const x = (m) => m / (flug.laenge || 1) * B;
  const y = (h) => 4 + (1 - (h - tief) / spanne) * (H - 8);
  const linie = punkte.map((p) => `${x(p.m).toFixed(1)},${y(p.h).toFixed(1)}`).join(' ');
  const bild = svg('svg', { viewBox: `0 0 ${B} ${H}`, preserveAspectRatio: 'none', 'aria-hidden': 'true' });
  const schnitt = svg('clipPath', { id: 'l-gefahren' });
  const rechteck = svg('rect', { x: 0, y: 0, width: 0, height: H });
  schnitt.append(rechteck);
  const defs = svg('defs');
  defs.append(schnitt);
  const flaeche = `0,${H} ${linie} ${B},${H}`;
  const gefahren = svg('g', { 'clip-path': 'url(#l-gefahren)' });
  gefahren.append(svg('polygon', { class: 'flaeche-voll', points: flaeche }), svg('polyline', { class: 'linie', points: linie }));
  const strich = svg('line', { class: 'strich', y1: 0, y2: H, visibility: 'hidden' });
  bild.append(defs, svg('polygon', { class: 'flaeche', points: flaeche }), svg('polyline', { class: 'linie-blass', points: linie }), gefahren, strich);
  box.append(bild);
  return {
    box,
    zeige(meter) {
      const px = meter == null ? 0 : x(meter);
      rechteck.setAttribute('width', meter == null ? 0 : px);
      strich.setAttribute('x1', px);
      strich.setAttribute('x2', px);
      strich.setAttribute('visibility', meter == null ? 'hidden' : 'visible');
    },
  };
}

// --- Fotos längs der Spur ---------------------------------------------------

// Jedes verortete Foto an die nächste Stelle der Spur; was weiter als ein
// Zwanzigstel des Ausschnitts (mindestens hundert Meter) daneben liegt,
// gehört nicht zu diesem Weg.
function fotosAufDieSpur(flug, aufnahmen) {
  const r = flug.raum;
  let breite = 0, hoehe = 0;
  for (const p of r.xy) { breite = Math.max(breite, Math.abs(p.x)); hoehe = Math.max(hoehe, Math.abs(p.y)); }
  const grenze = Math.max(100, Math.max(breite, hoehe) * 2 * 1.4 / 20);
  const uhr = new Intl.DateTimeFormat(GEBIET, { hour: '2-digit', minute: '2-digit' });
  const aus = [];
  for (const a of aufnahmen || []) {
    if (!a.ort || !a.miniatur) continue;
    const x = (a.ort.laenge - r.laenge0) * r.kx, y = (a.ort.breite - r.breite0) * r.ky;
    let beste = Infinity, stelle = 0;
    r.xy.forEach((p, i) => {
      const d = (p.x - x) ** 2 + (p.y - y) ** 2;
      if (d < beste) { beste = d; stelle = flug.bisHier[i]; }
    });
    if (Math.sqrt(beste) > grenze) continue;
    aus.push({ id: a.id, meter: stelle, ort: a.ort, unterschrift: uhr.format(new Date(a.aufgenommen)) });
  }
  return aus.sort((a, b) => a.meter - b.meter);
}

// Das zuletzt erreichte – es bleibt stehen, bis das nächste kommt; vor
// dem ersten bleibt es leer.
function fotoBei(z, meter) {
  let erreicht = null;
  for (const f of z.fotos) { if (f.meter > meter) break; erreicht = f; }
  return erreicht;
}

function setzeFotomarken(z) {
  for (const f of z.fotos) {
    const e = el('button', 'l-fotomarke');
    e.type = 'button';
    e.setAttribute('aria-label', f.unterschrift);
    const img = el('img');
    img.alt = '';
    img.loading = 'lazy';
    img.src = miniaturUrl(f.id);
    e.append(img);
    e.addEventListener('click', () => {
      const n = liste?.aufnahmen?.findIndex((x) => x.id === f.id) ?? -1;
      if (n >= 0) { schliesseLandschaft(); oeffne(n); }
    });
    new z.ml.Marker({ element: e, anchor: 'bottom', opacityWhenCovered: '0.2' }).setLngLat([f.ort.laenge, f.ort.breite]).addTo(z.karte);
  }
}

// --- Gipfel, Hütten, Quellen -------------------------------------------------

async function holeSchilder(z) {
  if (z.schilder.length || z.schilderLaden) return;
  const k = z.kasten;
  const q = new URLSearchParams({ sued: k.sued.toFixed(5), west: k.west.toFixed(5), nord: k.nord.toFixed(5), ost: k.ost.toFixed(5) });
  let d;
  z.schilderLaden = true;
  try { d = await api(`/api/v1/wanderobjekte?${q}`); } catch (_) { return; } finally { z.schilderLaden = false; }
  if (landschaft !== z || !z.wahl.wanderobjekte || z.schilder.length) return;
  for (const p of d.punkte || []) {
    const e = el('div', 'l-schild');
    const farbe = SCHILDFARBEN[p.art] || '#5B5B5B';
    const zeichen = el('span', 'l-zeichen', SCHILDZEICHEN[p.art] || '•');
    zeichen.style.color = farbe;
    e.append(zeichen);
    if (p.name) {
      const name = el('span', 'l-name', p.hoehe != null ? `${p.name}  ${Math.round(p.hoehe)} m` : p.name);
      name.style.borderColor = farbe;
      e.append(name);
    }
    z.schilder.push(new z.ml.Marker({ element: e, anchor: 'bottom-left', opacityWhenCovered: '0' }).setLngLat([p.laenge, p.breite]).addTo(z.karte));
  }
  zeigeFuss(z);
}

function nimmSchilderWeg(z) {
  for (const m of z.schilder) m.remove();
  z.schilder = [];
  zeigeFuss(z);
}

async function rechneHoehenlinien(z) {
  const quelle = z.karte?.getSource('hoehenlinien');
  if (!quelle || z.linienDa) return;
  z.linienDa = true;
  try {
    z.gitter ??= await hoehengitter(z.kasten, z.abbruch.signal);
    if (landschaft !== z) return;
    const { linien, zaehl } = hoehenlinien(z.gitter, z.kasten);
    z.linien = {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', properties: { zaehl: false }, geometry: { type: 'MultiLineString', coordinates: linien } },
        { type: 'Feature', properties: { zaehl: true }, geometry: { type: 'MultiLineString', coordinates: zaehl } },
      ],
    };
    quelle.setData(z.linien);
  } catch (_) {
    z.linienDa = false;
  }
}

// --- Menüs ------------------------------------------------------------------

function menue(z, knopf, baue) {
  z.box.querySelector('.l-menue')?.remove();
  const m = el('div', 'l-menue');
  m.setAttribute('role', 'menu');
  baue(m);
  const r = knopf.getBoundingClientRect(), b = z.box.getBoundingClientRect();
  m.style.top = `${r.bottom - b.top + 4}px`;
  m.style.right = `${Math.max(8, b.right - r.right)}px`;
  z.box.append(m);
  const weg = (e) => {
    if (m.contains(e.target) || e.target === knopf) return;
    m.remove();
    document.removeEventListener('pointerdown', weg, true);
  };
  setTimeout(() => document.addEventListener('pointerdown', weg, true));
}

function menuePunkt(text, gewaehlt, art, wenn) {
  const b = el('button', 'l-punkt');
  b.type = 'button';
  b.setAttribute('role', art);
  b.setAttribute('aria-checked', String(gewaehlt));
  b.setAttribute('aria-label', text);
  b.append(el('span', 'l-haken', gewaehlt ? (art === 'menuitemradio' ? '●' : '✓') : ''), el('span', null, text));
  b.addEventListener('click', wenn);
  return b;
}

function karteMenue(z) {
  menue(z, z.karteKnopf, (m) => {
    const neu = () => karteMenue(z);
    for (const g of GRUND_REIHE) {
      m.append(menuePunkt(t(GRUENDE[g].name), z.wahl.grund === g, 'menuitemradio', () => { setzeWahl(z, { grund: g }); neu(); }));
    }
    m.append(el('hr'));
    m.append(menuePunkt(t('Wanderwege'), z.wahl.wege, 'menuitemcheckbox', () => { setzeWahl(z, { wege: !z.wahl.wege }); neu(); }));
    m.append(menuePunkt(t('Strassen und Ortsnamen'), z.wahl.beschriftung, 'menuitemcheckbox', () => { setzeWahl(z, { beschriftung: !z.wahl.beschriftung }); neu(); }));
    m.append(menuePunkt(t('Höhenlinien'), z.wahl.hoehenlinien, 'menuitemcheckbox', () => { setzeWahl(z, { hoehenlinien: !z.wahl.hoehenlinien }); neu(); }));
    m.append(menuePunkt(t('Gipfel, Hütten, Quellen'), z.wahl.wanderobjekte, 'menuitemcheckbox', () => { setzeWahl(z, { wanderobjekte: !z.wahl.wanderobjekte }); neu(); }));
  });
}

function stimmungMenue(z) {
  menue(z, z.stimmungKnopf, (m) => {
    for (const s of STIMMUNG_REIHE) {
      m.append(menuePunkt(t(STIMMUNGEN[s].name), z.wahl.stimmung === s, 'menuitemradio', () => { setzeWahl(z, { stimmung: s }); stimmungMenue(z); }));
    }
  });
}

// Wechselt Grund, Ebenen oder Tageszeit, ohne die Höhen neu zu holen.
function setzeWahl(z, aenderung) {
  z.wahl = { ...z.wahl, ...aenderung };
  merkeLandschaftWahl(z.wahl);
  wendeWahlAn(z);
}

// Bringt die Karte auf die Wahl – verglichen mit dem, was gerade auf ihr
// liegt. Vor dem ersten Laden wartet das; der Halt danach holt es nach.
function wendeWahlAn(z) {
  const karte = z.karte;
  if (!karte || !z.uebersicht) return;
  const alt = z.angewandt;
  z.angewandt = z.wahl;
  const w = z.wahl, s = STIMMUNGEN[w.stimmung];
  if (w.grund !== alt.grund) {
    karte.removeLayer('grund');
    karte.removeSource('grund');
    const g = GRUENDE[w.grund];
    karte.addSource('grund', { type: 'raster', tiles: g.kacheln, tileSize: 256, maxzoom: g.max });
    karte.addLayer({ id: 'grund', type: 'raster', source: 'grund', paint: { ...rasterFarbe(w.grund, s), 'raster-fade-duration': 0 } }, 'relief');
  }
  if (w.grund !== alt.grund || w.stimmung !== alt.stimmung) {
    for (const [k, v] of Object.entries(rasterFarbe(w.grund, s))) karte.setPaintProperty('grund', k, v);
    for (const [k, v] of Object.entries(reliefFarbe(w.grund, s))) karte.setPaintProperty('relief', k, v);
    karte.setPaintProperty('schleier', 'fill-color', stimmungsfarben(s, w.grund).schleierfarbe);
    karte.setPaintProperty('schleier', 'fill-opacity', stimmungsfarben(s, w.grund).schleier);
    karte.setPaintProperty('hintergrund', 'background-color', s.dunst);
    karte.setSky(himmel(s));
  }
  for (const e of EBENEN.wege) karte.setLayoutProperty(e.id, 'visibility', w.wege ? 'visible' : 'none');
  for (const e of EBENEN.beschriftung) karte.setLayoutProperty(e.id, 'visibility', w.beschriftung ? 'visible' : 'none');
  for (const id of ['hoehenlinien', 'zaehllinien']) karte.setLayoutProperty(id, 'visibility', w.hoehenlinien ? 'visible' : 'none');
  auffrischen(karte);
  if (w.hoehenlinien) rechneHoehenlinien(z);
  if (w.wanderobjekte && !alt.wanderobjekte) holeSchilder(z);
  if (!w.wanderobjekte && alt.wanderobjekte) nimmSchilderWeg(z);
  zeigeFuss(z);
}

// --- Video --------------------------------------------------------------------
//
// Wie am Rechner: Bild für Bild abseits des Bildschirms, jedes erst, wenn
// seine Kacheln da sind, mit Messwerten, Foto und Abspann. Kodiert von
// WebCodecs (H.264), verpackt von mp4-muxer – jedes Bild mit seinem festen
// Zeitstempel, also ruckelt das Video nicht, wenn eine Kachel länger
// braucht.

function videoMoeglich() {
  return typeof VideoEncoder !== 'undefined' && typeof VideoFrame !== 'undefined';
}

function videoDialog(vorgabeMs) {
  return new Promise((fertig) => {
    const d = el('dialog', 'l-videodialog');
    const groessen = [[1280, 720], [1920, 1080], [2560, 1440]];
    let grad = 1;
    let sekunden = Math.round(vorgabeMs / 1000);
    if (sekunden < 5) sekunden = 20;
    if (sekunden > 300) sekunden = 300;
    const form = el('form');
    form.method = 'dialog';
    form.append(el('h3', null, t('Video ausgeben')), el('p', 'klein', t('Auflösung')));
    const knoepfe = el('div', 'l-segmente');
    const info = el('p', 'leise klein');
    const dauerWert = el('span', 'klein');
    const neu = () => {
      knoepfe.replaceChildren(...groessen.map(([b, h], i) => {
        const k = el('button', i === grad ? 'knopf' : 'knopf-flach', `${b}×${h}`);
        k.type = 'button';
        k.setAttribute('aria-pressed', String(i === grad));
        k.addEventListener('click', () => { grad = i; neu(); });
        return k;
      }));
      dauerWert.textContent = t('{sekunden} Sekunden', { sekunden });
      info.textContent = `${t('{bilder} Bilder', { bilder: zahl.format(sekunden * BILDER_JE_SEKUNDE) })} · ${groessen[grad][0]}×${groessen[grad][1]}`;
    };
    const dauer = el('input');
    dauer.type = 'range';
    dauer.min = '5';
    dauer.max = '300';
    dauer.step = '5';
    dauer.value = String(sekunden);
    dauer.setAttribute('aria-label', t('Dauer'));
    dauer.addEventListener('input', () => { sekunden = Number(dauer.value); neu(); });
    const dauerZeile = el('div', 'l-dauer');
    dauerZeile.append(dauer, dauerWert);
    const aktionen = el('div', 'dialog-knoepfe');
    const ab = el('button', 'knopf-flach', t('Abbrechen'));
    ab.type = 'button';
    ab.addEventListener('click', () => { d.close(); fertig(null); });
    const weiter = el('button', 'knopf', t('Speichern unter …'));
    weiter.type = 'button';
    weiter.addEventListener('click', () => { d.close(); fertig({ breite: groessen[grad][0], hoehe: groessen[grad][1], sekunden }); });
    aktionen.append(ab, weiter);
    form.append(knoepfe, el('p', 'klein', t('Dauer')), dauerZeile, info, el('p', 'leise klein', t('Die Bilder entstehen abseits des Bildschirms – der Flug wird dafür nicht abgespielt. Diese Ansicht muss so lange offen bleiben.')), aktionen);
    d.append(form);
    d.addEventListener('cancel', () => fertig(null));
    d.addEventListener('close', () => d.remove());
    (landschaft?.box || document.body).append(d);
    neu();
    d.showModal();
  });
}

// Zeichnet das Bild, sobald die Karte alles dafür hat – höchstens acht
// Sekunden, eine Kachel, die nicht kommt, hält das Video nicht auf.
//
// **Synchron mit `redraw()` und nicht über `idle`.** MapLibre zeichnet
// sonst im Takt von requestAnimationFrame, und den drosselt der Browser in
// einem Tab im Hintergrund auf ein Bild je Sekunde; die Ausgabe dauerte
// dann Stunden. Gewartet wird nur noch auf Kacheln aus dem Netz.
async function bildFertig(karte) {
  const ende = performance.now() + 8000;
  for (;;) {
    karte.redraw();
    if ((karte.loaded() && karte.areTilesLoaded()) || performance.now() > ende) break;
    await new Promise((r) => setTimeout(r, 15));
  }
  // Die Gelände-Texturen werden nach und nach erneuert (eine je Bild,
  // siehe auffrischen); ein paar Durchgänge holen den Rest nach.
  for (let i = 0; i < 3; i++) karte.redraw();
}

async function ladeBild(url) {
  try {
    const r = await fetch(url, { credentials: 'same-origin' });
    if (!r.ok) return null;
    return await createImageBitmap(await r.blob());
  } catch (_) {
    return null;
  }
}

async function videoAusgeben(z) {
  if (z.video) { z.video.abbruch = true; return; }
  if (!z.karte || !z.uebersicht) return;
  if (!videoMoeglich()) { meldung(t('Dieser Browser kann keine Videos schreiben. Chrome, Edge, Safari ab 16.4 und Firefox ab 130 können es.')); return; }
  const wahl = await videoDialog(z.flug.dauerMs);
  if (!wahl || landschaft !== z) return;
  z.spielt = false;
  const auftrag = { abbruch: false };
  z.video = auftrag;
  z.videoKnopf.textContent = `■ ${t('Ausgabe abbrechen')}`;
  z.ausgabe.hidden = false;
  const begann = Date.now();
  let ergebnis = null;
  const huelle = el('div', 'l-videokarte');
  huelle.style.width = `${wahl.breite}px`;
  huelle.style.height = `${wahl.hoehe}px`;
  document.body.append(huelle);
  let karte = null;
  try {
    const { Muxer, ArrayBufferTarget } = await import('./mp4muxer/mp4-muxer.mjs');
    karte = new z.ml.Map({
      container: huelle,
      style: stilFuer(z),
      pixelRatio: 1,
      interactive: false,
      attributionControl: false,
      fadeDuration: 0,
      canvasContextAttributes: { preserveDrawingBuffer: true, antialias: true },
      center: z.uebersicht.center,
      zoom: z.uebersicht.zoom,
      pitch: z.neigung,
      bearing: z.uebersicht.bearing,
    });
    await new Promise((fertig) => karte.once('load', fertig));
    if (z.linien && z.wahl.hoehenlinien) karte.getSource('hoehenlinien').setData(z.linien);
    const schilder = z.schilder.map((m) => ({ ort: m.getLngLat(), text: m.getElement().textContent }));
    const fotos = new Map();
    for (const f of z.fotos) fotos.set(f.id, await ladeBild(miniaturUrl(f.id)));

    const ziel = new ArrayBufferTarget();
    const muxer = new Muxer({ target: ziel, video: { codec: 'avc', width: wahl.breite, height: wahl.hoehe }, fastStart: 'in-memory' });
    let kodierfehler = null;
    const kodierer = new VideoEncoder({
      output: (stueck, meta) => muxer.addVideoChunk(stueck, meta),
      error: (e) => { kodierfehler = e; },
    });
    const pixel = wahl.breite * wahl.hoehe;
    kodierer.configure({
      codec: pixel > 1920 * 1080 ? 'avc1.640033' : 'avc1.640028',
      width: wahl.breite,
      height: wahl.hoehe,
      bitrate: Math.round(12e6 * pixel / (1920 * 1080)),
      framerate: BILDER_JE_SEKUNDE,
    });
    const leinwand = document.createElement('canvas');
    leinwand.width = wahl.breite;
    leinwand.height = wahl.hoehe;
    const ctx = leinwand.getContext('2d');
    const anzahl = Math.max(2, wahl.sekunden * BILDER_JE_SEKUNDE);
    const breitesteWerte = breitesteMesswerte(z.flug);
    // Die Kamera des Videos rechnet mit seiner Grösse, nicht mit dem Fenster.
    const vz = { ...z, karte, uebersicht: null, neigung: z.neigung };
    vz.uebersicht = uebersichtKamera(vz);
    for (let i = 0; i < anzahl; i++) {
      if (auftrag.abbruch || landschaft !== z) break;
      if (kodierfehler) throw kodierfehler;
      const zeit = i / (anzahl - 1);
      const { stand, abschnitt, kamera } = kameraBei(vz, zeit);
      karte.jumpTo(kamera);
      setzeSpurstand(karte, vz, stand.meter, true);
      await bildFertig(karte);
      ctx.drawImage(karte.getCanvas(), 0, 0, wahl.breite, wahl.hoehe);
      maleSchilder(ctx, karte, schilder, wahl);
      maleUeberlagen(ctx, z, stand, abschnitt, wahl, fotos, breitesteWerte);
      const bild = new VideoFrame(leinwand, { timestamp: Math.round(i * 1e6 / BILDER_JE_SEKUNDE), duration: Math.round(1e6 / BILDER_JE_SEKUNDE) });
      kodierer.encode(bild, { keyFrame: i % (BILDER_JE_SEKUNDE * 2) === 0 });
      bild.close();
      // Nicht mehr als ein paar Bilder vorauslaufen lassen.
      while (kodierer.encodeQueueSize > 4) await new Promise((r) => setTimeout(r, 5));
      const anteil = (i + 1) / anzahl;
      z.ausgabeBalken.value = anteil;
      const her = Date.now() - begann;
      z.ausgabeText.textContent = anteil > 0.02
        ? t('Video wird geschrieben – {prozent} %, noch etwa {rest}', { prozent: Math.round(anteil * 100), rest: dauerUhr(her / anteil - her) })
        : t('Video wird geschrieben – {prozent} %', { prozent: Math.round(anteil * 100) });
    }
    if (auftrag.abbruch || landschaft !== z) {
      kodierer.close();
      ergebnis = 'abgebrochen';
    } else {
      await kodierer.flush();
      kodierer.close();
      muxer.finalize();
      const datei = new Blob([ziel.buffer], { type: 'video/mp4' });
      const a = el('a');
      a.href = URL.createObjectURL(datei);
      a.download = `${(z.box.querySelector('h2')?.textContent || 'ueberflug').replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '_') || 'ueberflug'}.mp4`;
      document.body.append(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 60000);
      ergebnis = 'fertig';
      meldung(t('Video gespeichert: {datei}', { datei: a.download }));
    }
    for (const b of fotos.values()) b?.close();
  } catch (x) {
    meldung(t('Die Videoausgabe ist fehlgeschlagen: {grund}', { grund: x?.message || String(x) }));
  } finally {
    karte?.remove();
    huelle.remove();
    if (ergebnis === 'abgebrochen') meldung(t('Ausgabe abgebrochen'));
    z.video = null;
    if (landschaft === z) {
      z.videoKnopf.textContent = `⤓ ${t('Als Video ausgeben')}`;
      z.ausgabe.hidden = true;
    }
  }
}

function breitesteMesswerte(flug) {
  const breiteste = {};
  for (let i = 0; i <= 200; i++) {
    for (const w of messwerte(flug.bei(i / 200))) {
      if (!breiteste[w.name] || w.wert.length > breiteste[w.name].length) breiteste[w.name] = w.wert;
    }
  }
  return breiteste;
}

function rundesRechteck(ctx, x, y, b, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + b, y, x + b, y + h, r);
  ctx.arcTo(x + b, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + b, y, r);
  ctx.closePath();
}

const SCHRIFT = 'system-ui, -apple-system, "Segoe UI", sans-serif';

function maleSchilder(ctx, karte, schilder, wahl) {
  const s = wahl.hoehe / 1080;
  ctx.font = `${Math.round(15 * s)}px ${SCHRIFT}`;
  for (const p of schilder) {
    const pt = karte.project(p.ort);
    if (pt.x < 0 || pt.y < 0 || pt.x > wahl.breite || pt.y > wahl.hoehe) continue;
    const text = p.text;
    const breite = ctx.measureText(text).width + 12 * s;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.86)';
    rundesRechteck(ctx, pt.x + 4 * s, pt.y - 30 * s, breite, 24 * s, 4 * s);
    ctx.fill();
    ctx.fillStyle = '#222';
    ctx.fillText(text, pt.x + 10 * s, pt.y - 13 * s);
  }
}

function maleUeberlagen(ctx, z, stand, abschnitt, wahl, fotos, breiteste) {
  const s = wahl.hoehe / 1080;
  // Die Messwerte unten links – eingeblendet nach dem Einflug, aus vor dem
  // Abspann. Gesetzt in der Breite ihres breitesten Wertes, damit nichts
  // springt, wenn aus 9,9 km/h 10,0 werden.
  const sicht = einblenden(abschnitt.einflug) * (1 - ausblenden(abschnitt.abspann));
  const werte = messwerte(stand).filter((w) => w.name !== t('unterwegs'));
  if (sicht > 0 && werte.length) {
    ctx.save();
    ctx.globalAlpha = sicht;
    const groesse = Math.round(30 * s), klein = Math.round(15 * s);
    ctx.font = `600 ${groesse}px ${SCHRIFT}`;
    const breiten = werte.map((w) => Math.max(ctx.measureText(breiteste[w.name] || w.wert).width, ctx.measureText(w.wert).width));
    const gesamt = breiten.reduce((a, b) => a + b, 0) + 40 * s * (werte.length - 1) + 40 * s;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
    rundesRechteck(ctx, 28 * s, wahl.hoehe - 120 * s, gesamt, 92 * s, 12 * s);
    ctx.fill();
    let x = 48 * s;
    werte.forEach((w, i) => {
      ctx.font = `${klein}px ${SCHRIFT}`;
      ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
      ctx.fillText(w.name, x, wahl.hoehe - 88 * s);
      ctx.font = `600 ${groesse}px ${SCHRIFT}`;
      ctx.fillStyle = w.richtung === 'auf' ? '#FFAB91' : w.richtung === 'ab' ? '#80DEEA' : '#fff';
      ctx.fillText(w.wert, x, wahl.hoehe - 50 * s);
      x += breiten[i] + 40 * s;
    });
    ctx.restore();
  }
  // Das Foto oben rechts.
  const foto = fotoBei(z, stand.meter);
  const bild = foto ? fotos.get(foto.id) : null;
  if (bild) {
    const weg = Math.max(40, z.flug.laenge * 0.01);
    const deck = Math.min(Math.max((stand.meter - foto.meter) / weg, 0), 1) * (1 - ausblenden(abschnitt.abspann));
    if (deck > 0) {
      ctx.save();
      ctx.globalAlpha = deck;
      const kante = 360 * s, h = kante * bild.height / bild.width;
      const x = wahl.breite - kante - 32 * s, y = 32 * s;
      ctx.fillStyle = 'rgba(255, 255, 255, 0.92)';
      rundesRechteck(ctx, x - 8 * s, y - 8 * s, kante + 16 * s, h + 40 * s, 10 * s);
      ctx.fill();
      ctx.drawImage(bild, x, y, kante, h);
      ctx.fillStyle = '#222';
      ctx.font = `${Math.round(16 * s)}px ${SCHRIFT}`;
      ctx.textAlign = 'center';
      ctx.fillText(foto.unterschrift, x + kante / 2, y + h + 22 * s);
      ctx.restore();
    }
  }
  // Der Abspann in der Mitte.
  if (abschnitt.abspann > 0) {
    ctx.save();
    ctx.globalAlpha = ausblenden(abschnitt.abspann);
    const b = 520 * s, h = 200 * s, x = (wahl.breite - b) / 2, y = (wahl.hoehe - h) / 2;
    ctx.fillStyle = 'rgba(255, 255, 255, 0.88)';
    rundesRechteck(ctx, x, y, b, h, 14 * s);
    ctx.fill();
    ctx.textAlign = 'center';
    ctx.fillStyle = '#111';
    ctx.font = `600 ${Math.round(56 * s)}px ${SCHRIFT}`;
    ctx.fillText(`${eineStelle.format(z.flug.laenge / 1000)} km`, wahl.breite / 2, y + 78 * s);
    const teile = [];
    if (z.flug.aufstieg != null) teile.push([`${zahl.format(Math.round(z.flug.aufstieg))} m`, t('Aufstieg')]);
    if (z.flug.gesamtdauer != null) teile.push([dauerUhr(z.flug.gesamtdauer), t('unterwegs')]);
    teile.forEach(([wert, was], i) => {
      const mx = wahl.breite / 2 + (i - (teile.length - 1) / 2) * 200 * s;
      ctx.font = `600 ${Math.round(30 * s)}px ${SCHRIFT}`;
      ctx.fillText(wert, mx, y + 140 * s);
      ctx.font = `${Math.round(15 * s)}px ${SCHRIFT}`;
      ctx.fillStyle = '#555';
      ctx.fillText(was, mx, y + 166 * s);
      ctx.fillStyle = '#111';
    });
    ctx.restore();
  }
  // Die Namensnennung gehört auch ins Video.
  ctx.save();
  ctx.font = `${Math.round(13 * s)}px ${SCHRIFT}`;
  ctx.textAlign = 'right';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
  ctx.shadowColor = 'rgba(0, 0, 0, 0.6)';
  ctx.shadowBlur = 3 * s;
  ctx.fillText(nennung(z.wahl, z.schilder.length > 0), wahl.breite - 16 * s, wahl.hoehe - 14 * s);
  ctx.restore();
}

// Tasten in der Landschaft: Leertaste startet und hält an, Esc schliesst.
document.addEventListener('keydown', (e) => {
  const z = landschaft;
  if (!z || document.querySelector('dialog[open]')) return;
  if (e.key === 'Escape') { e.preventDefault(); if (z.box.querySelector('.l-menue')) z.box.querySelector('.l-menue').remove(); else schliesseLandschaft(); }
  else if (e.key === ' ' && !(e.target instanceof HTMLButtonElement || e.target instanceof HTMLInputElement)) { e.preventDefault(); flugSchalten(z); }
});

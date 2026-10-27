'use strict';

// --- Stammbaum im Browser ----------------------------------------------------
//
// Derselbe Zierbaum wie am Rechner (#234): Der Server liefert das Geflecht
// und die fertige Anordnung aus dem Kern (zierbaumplan, in den Massen des
// Rechners), hier wird gemalt wie in packages/zierbild/zierbaum_maler.dart
// und zierbaum_schild.dart – warmer Grund mit Goldstaub, ein Stamm unter
// der Mitte, Äste, die sich zum Elternhaus hin verbreitern, Ranken, und
// goldene Schilder mit Porträt, Name, Verwandtschaft und Lebensdaten.
//
// Bewegt wird wie am Rechner: ziehen verschiebt, das Rad (und zwei Finger
// auf der Tastfläche) zoomt um den Zeiger, zwei Finger auf dem Bildschirm
// ebenso; daneben die drei Knöpfe. Vorher war der Baum ein Bild in einem
// Rollbereich – mit der Maus liess er sich nicht greifen.
//
// Braucht lbBezeichnung aus lebensbaum.js (dieselben Wörter auf beiden
// Bäumen); app.js lädt beide, bevor es zeigeStammbaum aufruft.

// zierbild/zierbaum_farben.dart
const BAUM_FARBEN = {
  dunkel: {
    grundAussen: '#120A06', grundInnen: '#3A1E0C', holzDunkel: '#8A6013', holzHell: '#E8C271',
    ranken: '#B08637', schildOben: '#F6DFA4', schildUnten: '#C9992F', schildRand: '#7A5410',
    schrift: '#2A1B05', nebenschrift: '#5C4212', mitteRand: '#FFF0C4', familienname: '#E8C271', staub: '#FFD980',
  },
  hell: {
    grundAussen: '#E8DCC2', grundInnen: '#F7EFDC', holzDunkel: '#6B4A1E', holzHell: '#A97C33',
    ranken: '#B39154', schildOben: '#FFF8E6', schildUnten: '#E3CD95', schildRand: '#9A7527',
    schrift: '#2E2008', nebenschrift: '#6B5426', mitteRand: '#6B4A1E', familienname: '#6B4A1E', staub: '#C9A96A',
  },
};
const baumDunkel = window.matchMedia('(prefers-color-scheme: dark)');
const baumFarben = () => (baumDunkel.matches ? BAUM_FARBEN.dunkel : BAUM_FARBEN.hell);

// lib/services/baumnavigation.dart
const BAUM_ZOOM_MIN = 0.25;
const BAUM_ZOOM_MAX = 3;
const BAUM_ZOOM_SCHRITT = 1.25;

const svgNs = 'http://www.w3.org/2000/svg';
const svgEl = (tag, attrs = {}, text) => {
  const e = document.createElementNS(svgNs, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  if (text !== undefined) e.textContent = text;
  return e;
};

// Wie weit der Baum reicht (#233): Generationen darüber, darunter und der
// Kreis bis zu den Cousins zweiten Grades. Ohne Wahl gilt, was am Rechner
// zuletzt eingestellt war; was gilt, meldet der Server in `optionen`.
const baumGewaehlt = {};
for (const [id, name] of [['baum-oben', 'oben'], ['baum-unten', 'unten'], ['baum-kreis', 'kreis']]) {
  $(id).addEventListener('change', () => {
    baumGewaehlt[name] = $(id).value;
    zeigeStammbaum($('baum-person').value || null).catch((x) => { $('baum-hinweis').textContent = x.message; });
  });
}
$('baum-person').addEventListener('change', () => { location.hash = `#/stammbaum/${encodeURIComponent($('baum-person').value)}`; });
$('baum-zum-lebensbaum').addEventListener('click', () => { location.hash = `#/lebensbaum/${encodeURIComponent($('baum-person').value || '')}`; });

function baumUmfangZeigen(o) {
  if (!o) return;
  const zahlen = (id, von, wert) => {
    const s = $(id);
    s.replaceChildren();
    for (let n = von; n <= o.maxGenerationen; n++) {
      const opt = el('option', null, String(n));
      opt.value = String(n);
      s.append(opt);
    }
    s.value = String(wert);
  };
  zahlen('baum-oben', 1, o.oben);
  zahlen('baum-unten', 0, o.unten);
  $('baum-kreis').value = o.kreis;
}

async function zeigeStammbaum(fokus) {
  markiereNav('stammbaum');
  zeigeBereich(['stammbaum']);
  $('baum-hinweis').textContent = '';
  const q = new URLSearchParams();
  if (fokus) q.set('fokus', fokus);
  for (const [name, wert] of Object.entries(baumGewaehlt)) q.set(name, wert);
  const abfrage = q.toString();
  const d = await api(`/api/v1/stammbaum${abfrage ? `?${abfrage}` : ''}`);
  baumUmfangZeigen(d.optionen);
  const wahl = $('baum-person');
  wahl.replaceChildren();
  for (const p of [...d.personen].sort((a, b) => a.name.localeCompare(b.name))) {
    const o = el('option', null, p.verwandt ? p.name : t('{name} (ohne Verwandtschaft)', { name: p.name }));
    o.value = p.id;
    wahl.append(o);
  }
  wahl.value = d.fokus || '';
  if (!d.fokus) {
    baum.bild = null;
    $('baum-buehne').replaceChildren();
    $('baum-hinweis').textContent = t('Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.');
    return;
  }
  const hinweise = [];
  const fokusVerwandt = d.personen.some((p) => p.id === d.fokus && p.verwandt);
  if (d.haushalte.length === 1 && d.haushalte[0].personen.length === 1 && !fokusVerwandt) hinweise.push(t('Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.'));
  if (d.verschwiegen) hinweise.push(t('{n} Haushalte passen nicht mehr ins Bild.', { n: d.verschwiegen }));
  $('baum-hinweis').textContent = hinweise.join(' ');
  // Die Schrift muss da sein, bevor gemessen wird – sonst bricht der Name
  // nach den Massen einer Ersatzschrift um.
  await Promise.all(['600 14px Zierschrift', '700 14px Zierschrift', '11px Zierschrift', '46px "Zierschrift Gross"'].map((f) => document.fonts.load(f).catch(() => null)));
  baumHoeheSetzen();
  baum.bild = baumSvg(d);
  $('baum-buehne').replaceChildren(baum.bild);
  baum.groesse = { b: d.plan.breite, h: d.plan.hoehe };
  baumGrundMalen();
  // Ein anderer Fokus oder Umfang: neu einpassen, wie am Rechner.
  baumErsterBlick(d);
}

// --- Malen -------------------------------------------------------------------

// Ein Punkt der Kurve vom Schild (von) zum Elternhaus (nach) – kubisch,
// beide Steuerpunkte auf halber Höhe (zierbaum.dart, Ast.steuer1Y/2Y).
function astPunkt(a, anteil) {
  const m = (a.y1 + a.y2) / 2;
  const u = 1 - anteil;
  return {
    x: a.x1 * u * u * u + a.x1 * 3 * u * u * anteil + a.x2 * 3 * u * anteil * anteil + a.x2 * anteil * anteil * anteil,
    y: a.y1 * u * u * u + m * 3 * u * u * anteil + m * 3 * u * anteil * anteil + a.y2 * anteil * anteil * anteil,
  };
}

function astRichtung(a, anteil) {
  const m = (a.y1 + a.y2) / 2;
  const u = 1 - anteil;
  const dx = (a.x2 - a.x1) * 6 * u * anteil;
  const dy = (m - a.y1) * 3 * u * u + (a.y2 - m) * 3 * anteil * anteil;
  const l = Math.hypot(dx, dy);
  return l < 0.0001 ? { x: 0, y: -1 } : { x: dx / l, y: dy / l };
}

// Ein Ast als gefüllte Form: zwei Ränder links und rechts der Kurve mit
// wachsendem Abstand – ein Strich gleicher Breite sähe aus wie ein Draht.
function astForm(a, unten, oben) {
  const links = [], rechts = [];
  for (let i = 0; i <= 24; i++) {
    const anteil = i / 24;
    const p = astPunkt(a, anteil), r = astRichtung(a, anteil);
    const halb = (unten + (oben - unten) * anteil) / 2;
    links.push(`${(p.x - r.y * halb).toFixed(2)},${(p.y + r.x * halb).toFixed(2)}`);
    rechts.push(`${(p.x + r.y * halb).toFixed(2)},${(p.y - r.x * halb).toFixed(2)}`);
  }
  return `M${links.join(' L')} L${rechts.reverse().join(' L')} Z`;
}

// Die Ranke: drei kleiner werdende Bögen bei zwei Dritteln des Astes, zur
// Seite, zu der er sich neigt. Die Grösse kommt vom Server (rankenGroesse
// im Kern), damit sie dieselbe ist wie am Rechner.
function rankenPfad(a) {
  if (!a.ranke) return null;
  const start = astPunkt(a, 0.66), r = astRichtung(a, 0.66);
  const quer = { x: -r.y, y: r.x };
  const seite = a.x2 >= a.x1 ? -1 : 1;
  let p = start, weite = a.ranke, winkel = Math.atan2(quer.y * seite, quer.x * seite);
  let d = `M${p.x.toFixed(2)},${p.y.toFixed(2)}`;
  for (let i = 0; i < 3; i++) {
    const n = { x: p.x + Math.cos(winkel) * weite, y: p.y + Math.sin(winkel) * weite };
    const s = { x: p.x + Math.cos(winkel - 0.9) * weite, y: p.y + Math.sin(winkel - 0.9) * weite };
    d += ` Q${s.x.toFixed(2)},${s.y.toFixed(2)} ${n.x.toFixed(2)},${n.y.toFixed(2)}`;
    p = n;
    winkel += 1.9;
    weite *= 0.62;
  }
  return d;
}

// Material „person_outline" – das Zeichen ohne Porträt, wie am Rechner.
const PERSON_UMRISS = 'M12 5.9c1.16 0 2.1.94 2.1 2.1s-.94 2.1-2.1 2.1S9.9 9.16 9.9 8s.94-2.1 2.1-2.1m0 9c2.97 0 6.1 1.46 6.1 2.1v1.1H5.9V17c0-.64 3.13-2.1 6.1-2.1M12 4C9.79 4 8 5.79 8 8s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm0 9c-2.67 0-8 1.34-8 4v3h16v-3c0-2.66-5.33-4-8-4z';

// Zeilen, wie Flutter sie bricht: an Wortgrenzen, höchstens [max], die
// letzte mit Auslassung, wenn der Rest nicht passt.
const baumMesser = document.createElement('canvas').getContext('2d');
function umbrechen(text, schrift, breite, max) {
  baumMesser.font = schrift;
  const passt = (s) => baumMesser.measureText(s).width <= breite;
  const kuerzen = (s) => {
    if (passt(s)) return s;
    while (s.length > 1 && !passt(`${s}…`)) s = s.slice(0, -1);
    return `${s.trimEnd()}…`;
  };
  const woerter = text.trim().split(/\s+/);
  const zeilen = [];
  let zeile = '';
  for (let i = 0; i < woerter.length; i++) {
    const probe = zeile ? `${zeile} ${woerter[i]}` : woerter[i];
    if (passt(probe) || !zeile) { zeile = probe; continue; }
    if (zeilen.length === max - 1) return [...zeilen, kuerzen(woerter.slice(i).reduce((a, w) => `${a} ${w}`, zeile))];
    zeilen.push(kuerzen(zeile));
    zeile = woerter[i];
  }
  if (zeile) zeilen.push(kuerzen(zeile));
  return zeilen.slice(0, max);
}

function baumSvg(d) {
  const f = baumFarben();
  const plan = d.plan;
  const m = plan.schild;
  const nachId = Object.fromEntries(d.personen.map((p) => [p.id, p]));
  const svg = svgEl('svg', { viewBox: `0 0 ${plan.breite} ${plan.hoehe}`, width: plan.breite, height: plan.hoehe, class: 'zierbaum' });
  const defs = svgEl('defs');
  svg.append(defs);
  const verlauf = (id, x1, y1, x2, y2, von, nach) => {
    const g = svgEl('linearGradient', { id, gradientUnits: 'userSpaceOnUse', x1, y1, x2, y2 });
    g.append(svgEl('stop', { offset: 0, 'stop-color': von }), svgEl('stop', { offset: 1, 'stop-color': nach }));
    defs.append(g);
    return `url(#${id})`;
  };
  const tafel = svgEl('linearGradient', { id: 'zb-tafel', x1: 0, y1: 0, x2: 0, y2: 1 });
  tafel.append(svgEl('stop', { offset: 0, 'stop-color': f.schildOben }), svgEl('stop', { offset: 1, 'stop-color': f.schildUnten }));
  defs.append(tafel);

  // Der Stamm: vom unteren Rand herauf an das Schild der Mitte.
  const mitte = plan.schilder.find((s) => s.id === d.fokus);
  if (plan.schilder.length) {
    const oben = mitte ? mitte.y + mitte.h : Math.max(...plan.schilder.map((s) => s.y + s.h));
    const stamm = { x1: plan.stammX, y1: plan.hoehe, x2: plan.stammX, y2: oben };
    svg.append(svgEl('path', { d: astForm(stamm, 26, 9), fill: verlauf('zb-stamm', stamm.x1, stamm.y1, stamm.x2, stamm.y2, f.holzDunkel, f.holzHell) }));
  }
  plan.aeste.forEach((a, i) => {
    svg.append(svgEl('path', { d: astForm(a, 3.5, 8), fill: verlauf(`zb-ast${i}`, a.x1, a.y1, a.x2, a.y2, f.holzDunkel, f.holzHell) }));
  });
  for (const b of plan.paare) {
    svg.append(svgEl('path', { d: `M${b.x1},${b.y} Q${(b.x1 + b.x2) / 2},${b.y + 5} ${b.x2},${b.y}`, fill: 'none', stroke: f.holzHell, 'stroke-width': 2.5, 'stroke-linecap': 'round' }));
  }
  for (const a of plan.aeste) {
    const r = rankenPfad(a);
    if (r) svg.append(svgEl('path', { d: r, fill: 'none', stroke: f.ranken, 'stroke-width': 1.6, 'stroke-linecap': 'round' }));
  }
  if (d.familienname) {
    svg.append(svgEl('text', { x: plan.breite / 2, y: plan.hoehe - 28 - 12, 'text-anchor': 'middle', fill: f.familienname, 'font-family': '"Zierschrift Gross"', 'font-size': 46, 'letter-spacing': 2 }, d.familienname));
  }

  const oben = new Set(d.weitereOben), unten = new Set(d.weitereUnten);
  plan.schilder.forEach((s, i) => {
    const p = nachId[s.id] || { name: '?' };
    const istMitte = s.id === d.fokus;
    const g = svgEl('g', { class: `zb-schild${istMitte ? ' mitte' : ''}`, transform: `translate(${s.x},${s.y})`, 'data-id': s.id });
    const r = m.portraitRadius;
    // Das Porträt über der Tafel, wie ein Bildnis über einer Tafel.
    g.append(svgEl('circle', { cx: s.b / 2, cy: r, r, fill: f.schildUnten }));
    if (p.bild) {
      const clip = svgEl('clipPath', { id: `zb-bild${i}` });
      clip.append(svgEl('circle', { cx: s.b / 2, cy: r, r }));
      defs.append(clip);
      g.append(svgEl('image', { href: `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}`, x: s.b / 2 - r, y: 0, width: 2 * r, height: 2 * r, preserveAspectRatio: 'xMidYMid slice', 'clip-path': `url(#zb-bild${i})` }));
    } else {
      const k = (r + 1) / 24;
      g.append(svgEl('path', { d: PERSON_UMRISS, fill: f.schildRand, transform: `translate(${s.b / 2 - 12 * k},${r - 12 * k}) scale(${k})` }));
    }
    const ty = 2 * r + m.portraitAbstand, th = s.h - ty;
    const rand = istMitte ? m.randStark : m.randSchwach;
    g.append(svgEl('rect', { x: rand / 2, y: ty + rand / 2, width: s.b - rand, height: th - rand, rx: m.rundung, fill: 'url(#zb-tafel)', stroke: istMitte ? f.mitteRand : f.schildRand, 'stroke-width': rand }));
    // Name, Verwandtschaft, Lebensdaten – mittig in der Tafel.
    const innen = s.b - 2 * m.polsterX;
    const nameSchrift = `${istMitte ? 700 : 600} ${m.schriftName}px Zierschrift`;
    const nebenSchrift = `${m.schriftNeben}px Zierschrift`;
    const bezug = istMitte ? null : lbBezeichnung(p);
    const zeilen = [
      ...umbrechen(p.name, nameSchrift, innen, 2).map((z) => ({ z, gross: true })),
      ...(bezug ? umbrechen(bezug, nebenSchrift, innen, 1).map((z) => ({ z })) : []),
      ...(p.lebensspanne ? [{ z: p.lebensspanne }] : []),
    ];
    const hoehe = (z) => (z.gross ? m.schriftName * 1.1 : m.schriftNeben * 1.3);
    let y = ty + th / 2 - zeilen.reduce((a, z) => a + hoehe(z), 0) / 2;
    for (const z of zeilen) {
      y += hoehe(z);
      g.append(svgEl('text', {
        x: s.b / 2, y: y - (z.gross ? m.schriftName * 0.28 : m.schriftNeben * 0.34), 'text-anchor': 'middle',
        fill: z.gross ? f.schrift : f.nebenschrift, 'font-family': 'Zierschrift',
        'font-size': z.gross ? m.schriftName : m.schriftNeben, 'font-weight': z.gross ? (istMitte ? 700 : 600) : 400,
      }, z.z));
    }
    // Die Mehrzeichen: hier geht es weiter, aber nicht in diesem Bild.
    const mehr = (my) => {
      for (const dx of [-4.3, 0, 4.3]) g.append(svgEl('circle', { cx: s.b / 2 + dx, cy: my, r: 1.35, fill: f.schildRand }));
    };
    if (oben.has(s.id)) mehr(ty + m.zeichenGroesse / 2 - 1);
    if (unten.has(s.id)) mehr(s.h - m.zeichenGroesse / 2 + 1);
    const titel = svgEl('title');
    titel.textContent = [p.name, bezug, p.lebensspanne].filter(Boolean).join(', ');
    g.append(titel);
    svg.append(g);
  });
  return svg;
}

// Der Grund steht still hinter dem Baum und füllt die ganze Fläche – wie
// Zierbaumgrund am Rechner: ein warmer Schein, Goldstaub auf festem Raster.
function baumGrundMalen() {
  const flaeche = $('baum-flaeche');
  const c = $('baum-grund');
  const w = flaeche.clientWidth, h = flaeche.clientHeight;
  const dpr = window.devicePixelRatio || 1;
  c.width = Math.round(w * dpr);
  c.height = Math.round(h * dpr);
  const g = c.getContext('2d');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  const f = baumFarben();
  g.fillStyle = f.grundAussen;
  g.fillRect(0, 0, w, h);
  const schein = g.createRadialGradient(w / 2, h * 0.62, 0, w / 2, h * 0.62, Math.max(w, h) * 0.7);
  schein.addColorStop(0, f.grundInnen);
  schein.addColorStop(1, f.grundAussen);
  g.fillStyle = schein;
  g.fillRect(0, 0, w, h);
  g.fillStyle = f.staub;
  g.globalAlpha = 0.22;
  const abstand = 47;
  for (let x = abstand / 2; x < w; x += abstand) {
    for (let y = abstand / 2; y < h; y += abstand) {
      if (Math.floor((x * 7 + y * 13) / abstand) % 5 !== 0) continue;
      g.beginPath();
      g.arc(x, y, 0.8 + ((x + y) % 3) * 0.5, 0, Math.PI * 2);
      g.fill();
    }
  }
  g.globalAlpha = 1;
}

// --- Bewegen -----------------------------------------------------------------

const baum = { bild: null, groesse: null, daten: null, eingepasst: false, s: 1, x: 0, y: 0 };

// Die Fläche reicht bis knapp über den unteren Rand – auf dem Telefon bis
// über die Reiterleiste. Eine feste Höhe in CSS passte nicht: Dort bricht
// die Leiste über dem Baum in drei Zeilen um, und die Fläche rutschte mit
// ihren Knöpfen unter die Reiter.
function baumHoeheSetzen() {
  const f = $('baum-flaeche');
  const nav = $('nav');
  const unten = nav && getComputedStyle(nav).position === 'fixed' ? nav.getBoundingClientRect().height : 0;
  const h = window.innerHeight - f.getBoundingClientRect().top - unten - 16;
  f.style.height = `${Math.max(320, Math.round(h))}px`;
}

function baumFenster() {
  const f = $('baum-flaeche');
  return { w: f.clientWidth, h: f.clientHeight };
}

// Ein Stück des Baums bleibt immer im Bild: Ganz hinausgeschoben stünde
// man vor einer leeren Fläche und fände nicht zurück.
function baumSetzen(s, x, y) {
  const { w, h } = baumFenster();
  const rest = 80;
  baum.s = Math.min(BAUM_ZOOM_MAX, Math.max(BAUM_ZOOM_MIN, s));
  if (baum.groesse) {
    x = Math.min(w - rest, Math.max(rest - baum.groesse.b * baum.s, x));
    y = Math.min(h - rest, Math.max(rest - baum.groesse.h * baum.s, y));
  }
  baum.x = x;
  baum.y = y;
  $('baum-buehne').style.transform = `translate(${x}px, ${y}px) scale(${baum.s})`;
}

// Um [faktor] zoomen, festgehalten am Punkt (px, py) im Fenster.
function baumZoomen(faktor, px, py) {
  const neu = Math.min(BAUM_ZOOM_MAX, Math.max(BAUM_ZOOM_MIN, baum.s * faktor));
  const k = neu / baum.s;
  baumSetzen(neu, px - (px - baum.x) * k, py - (py - baum.y) * k);
}

// Erst den ganzen Baum einmitten; fällt das Schild der Mitte dabei aus dem
// Bild, auf dieses Schild rücken (baumErsterBlick am Rechner).
function baumErsterBlick(d) {
  const { w, h } = baumFenster();
  baum.daten = d;
  // Noch ohne Grösse (der Bereich wird gerade erst sichtbar): später
  // einpassen, sobald die Fläche eine hat – sonst klebte der Baum am Rand.
  baum.eingepasst = w > 0 && h > 0;
  const x = w / 2 - d.plan.breite / 2, y = h / 2 - d.plan.hoehe / 2;
  const s = d.plan.schilder.find((k) => k.id === d.fokus);
  const drin = !s || (x + s.x >= 0 && y + s.y >= 0 && x + s.x + s.b <= w && y + s.y + s.h <= h);
  if (drin) baumSetzen(1, x, y);
  else baumSetzen(1, w / 2 - (s.x + s.b / 2), h / 2 - (s.y + s.h / 2));
}

// „Ganz zeigen": eingepasst, aber nie über die eigene Grösse hinaus.
function baumGanz() {
  if (!baum.groesse) return;
  const { w, h } = baumFenster();
  const s = Math.min(1, Math.max(BAUM_ZOOM_MIN, Math.min(w / baum.groesse.b, h / baum.groesse.h)));
  baumSetzen(s, (w - baum.groesse.b * s) / 2, (h - baum.groesse.h * s) / 2);
}

(() => {
  const flaeche = $('baum-flaeche');
  const zeiger = new Map();
  let gezogen = false, start = null, zwei = null;
  flaeche.addEventListener('pointerdown', (e) => {
    if (e.target.closest('.baum-knoepfe')) return;
    // Eingefangen wird erst beim Ziehen: Ein eingefangener Zeiger schickt
    // auch den Klick an die Fläche, und das Schild darunter erführe nie,
    // dass es gemeint war.
    // Ein Zeiger, der ausserhalb losgelassen wurde, bevor er eingefangen
    // war, meldet sich nie ab; der erste Finger und die Maus fangen neu an.
    if (e.isPrimary) zeiger.clear();
    zeiger.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (zeiger.size === 1) {
      gezogen = false;
      start = { x: e.clientX, y: e.clientY, bx: baum.x, by: baum.y };
    } else if (zeiger.size === 2) {
      const [a, b] = [...zeiger.values()];
      zwei = { abstand: Math.hypot(a.x - b.x, a.y - b.y), s: baum.s };
      for (const id of zeiger.keys()) flaeche.setPointerCapture(id);
    }
  });
  flaeche.addEventListener('pointermove', (e) => {
    if (!zeiger.has(e.pointerId)) return;
    zeiger.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (zeiger.size === 2 && zwei) {
      // Zwei Finger: um ihre Mitte zoomen.
      const [a, b] = [...zeiger.values()];
      const r = flaeche.getBoundingClientRect();
      const faktor = (zwei.s * Math.hypot(a.x - b.x, a.y - b.y)) / zwei.abstand / baum.s;
      baumZoomen(faktor, (a.x + b.x) / 2 - r.left, (a.y + b.y) / 2 - r.top);
      gezogen = true;
      return;
    }
    if (!start) return;
    const dx = e.clientX - start.x, dy = e.clientY - start.y;
    // Erst ab ein paar Punkten ein Ziehen – sonst wäre jeder Klick auf ein
    // Schild eines, und die Mitte liesse sich nicht mehr umsetzen.
    if (!gezogen && Math.hypot(dx, dy) < 4) return;
    if (!gezogen) flaeche.setPointerCapture(e.pointerId);
    gezogen = true;
    flaeche.classList.add('zieht');
    baumSetzen(baum.s, start.bx + dx, start.by + dy);
  });
  const los = (e) => {
    zeiger.delete(e.pointerId);
    if (zeiger.size < 2) zwei = null;
    if (zeiger.size === 0) { start = null; flaeche.classList.remove('zieht'); }
    if (zeiger.size === 1) {
      const [rest] = [...zeiger.values()];
      start = { x: rest.x, y: rest.y, bx: baum.x, by: baum.y };
    }
  };
  flaeche.addEventListener('pointerup', los);
  flaeche.addEventListener('pointercancel', los);
  // Ein Klick ist ein Klick nur, wenn nicht gezogen wurde.
  flaeche.addEventListener('click', (e) => {
    if (gezogen) { gezogen = false; return; }
    const schild = e.target.closest('.zb-schild');
    if (schild && !schild.classList.contains('mitte')) location.hash = `#/stammbaum/${encodeURIComponent(schild.dataset.id)}`;
  });
  // Das Rad zoomt um den Zeiger – wie am Rechner, wo Wischen auf Tastfläche
  // und Magic Mouse zoomt, damit auch Geräte ohne Rad einen Zoom haben.
  flaeche.addEventListener('wheel', (e) => {
    e.preventDefault();
    const r = flaeche.getBoundingClientRect();
    const schritt = e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
    baumZoomen(Math.exp(-schritt * (e.ctrlKey ? 0.01 : 0.0015)), e.clientX - r.left, e.clientY - r.top);
  }, { passive: false });
  $('baum-hinein').addEventListener('click', () => { const { w, h } = baumFenster(); baumZoomen(BAUM_ZOOM_SCHRITT, w / 2, h / 2); });
  $('baum-hinaus').addEventListener('click', () => { const { w, h } = baumFenster(); baumZoomen(1 / BAUM_ZOOM_SCHRITT, w / 2, h / 2); });
  $('baum-ganz').addEventListener('click', baumGanz);
  // Die Kurzhinweise stehen deutsch im HTML; übersetzt werden dort nur
  // Texte, nicht Attribute.
  for (const [id, text] of [['baum-hinein', 'Vergrössern'], ['baum-hinaus', 'Verkleinern'], ['baum-ganz', 'Ganz zeigen']]) {
    $(id).title = t(text);
    $(id).setAttribute('aria-label', t(text));
  }
  new ResizeObserver(() => {
    if (!baum.bild) return;
    baumGrundMalen();
    if (!baum.eingepasst && baum.daten) baumErsterBlick(baum.daten);
    else baumSetzen(baum.s, baum.x, baum.y);
  }).observe(flaeche);
  window.addEventListener('resize', () => { if (!$('bereich-stammbaum').hidden) baumHoeheSetzen(); });
  // Hell und Dunkel wechseln mit dem System – der Baum mit.
  baumDunkel.addEventListener('change', () => { if (baum.bild && !$('bereich-stammbaum').hidden) zeigeStammbaum($('baum-person').value || null).catch(() => null); });
})();

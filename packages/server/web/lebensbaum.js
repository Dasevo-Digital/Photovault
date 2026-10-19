'use strict';

// --- Lebensbaum im Browser ---------------------------------------------------
//
// Die Anordnung kommt fertig vom Server (dieselbe wie am Rechner, aus dem
// Kern); hier wird gemalt wie in lib/widgets/lebensbaum_maler.dart: das
// Vorlagenbild, gesetzte Schilder, die Namen so gross, wie das Schild sie
// fasst, Porträts im Kreis, Titel und Untertitel.

const LB_FAKTOR = 2; // Bildpunkte je Vorlageneinheit – scharf genug zum Drucken.

// Verwandtschaftsbezeichnungen wie in lib/l10n (grad*). g: 'w', 'm' oder 'other'.
const LB_GRAD = {
  de: {
    selbst: () => 'diese Person',
    eltern: { w: 'Mutter', m: 'Vater', other: 'Elternteil' },
    grosseltern: { w: 'Großmutter', m: 'Großvater', other: 'Großelternteil' },
    urgrosseltern: { w: 'Urgroßmutter', m: 'Urgroßvater', other: 'Urgroßelternteil' },
    ururgrosseltern: { w: 'Ururgroßmutter', m: 'Ururgroßvater', other: 'Ururgroßelternteil' },
    vorfahreN: (n) => `Vorfahre der ${n}. Generation`,
    kind: { w: 'Tochter', m: 'Sohn', other: 'Kind' },
    enkel: { w: 'Enkelin', m: 'Enkel', other: 'Enkelkind' },
    urenkel: { w: 'Urenkelin', m: 'Urenkel', other: 'Urenkelkind' },
    ururenkel: { w: 'Ururenkelin', m: 'Ururenkel', other: 'Ururenkelkind' },
    nachkommeN: (n) => `Nachkomme der ${n}. Generation`,
    geschwister: { w: 'Schwester', m: 'Bruder', other: 'Geschwister' },
    halbgeschwister: { w: 'Halbschwester', m: 'Halbbruder', other: 'Halbgeschwister' },
    neffeNichte: { w: 'Nichte', m: 'Neffe', other: 'Geschwisterkind' },
    grossneffeNichte: { w: 'Großnichte', m: 'Großneffe', other: 'Großgeschwisterkind' },
    geschwisterNachkommeN: (n) => `Nachkomme eines Geschwisters, ${n} Stufen entfernt`,
    onkelTante: { w: 'Tante', m: 'Onkel', other: 'Elterngeschwister' },
    grossonkelTante: { w: 'Großtante', m: 'Großonkel', other: 'Großelterngeschwister' },
    vorfahrengeschwisterN: (n) => `Geschwister eines Vorfahren der ${n}. Generation`,
    cousin: (g, n) => `${{ w: 'Cousine', m: 'Cousin', other: 'Cousin/Cousine' }[g]} ${n}. Grades`,
    entfernt: (b, n) => `${b}, ${n}-fach entfernt`,
    partner: { w: 'Partnerin', m: 'Partner', other: 'Partner' },
    schwager: { w: 'Schwägerin', m: 'Schwager', other: 'Schwager/Schwägerin' },
    schwiegereltern: { w: 'Schwiegermutter', m: 'Schwiegervater', other: 'Schwiegerelternteil' },
    schwiegerkind: { w: 'Schwiegertochter', m: 'Schwiegersohn', other: 'Schwiegerkind' },
    stiefeltern: { w: 'Stiefmutter', m: 'Stiefvater', other: 'Stiefelternteil' },
    stiefkind: { w: 'Stieftochter', m: 'Stiefsohn', other: 'Stiefkind' },
    stiefgeschwister: { w: 'Stiefschwester', m: 'Stiefbruder', other: 'Stiefgeschwister' },
    adoptiveltern: { w: 'Adoptivmutter', m: 'Adoptivvater', other: 'Adoptivelternteil' },
    pflegeeltern: { w: 'Pflegemutter', m: 'Pflegevater', other: 'Pflegeelternteil' },
    adoptivkind: { w: 'Adoptivtochter', m: 'Adoptivsohn', other: 'Adoptivkind' },
    pflegekind: { w: 'Pflegetochter', m: 'Pflegesohn', other: 'Pflegekind' },
    angeheiratet: () => 'angeheiratet',
    keine: () => 'nicht verwandt',
    ueberWeg: (schritt, bezug, name) => `${schritt} von ${bezug} ${name}`,
    titel: (n) => `Stammbaum der Familie ${n}`,
    titelKurz: (n) => `Familie ${n}`,
    titelOhneName: 'Stammbaum',
    untertitel: {
      vorfahren: (n) => `Die Vorfahren von ${n}`,
      paar: (n) => `Die Vorfahren von ${n}`,
      nachkommen: (n) => `Die Nachkommen von ${n}`,
      familie: (n) => `Die Familie von ${n}`,
    },
  },
  en: {
    selbst: () => 'this person',
    eltern: { w: 'Mother', m: 'Father', other: 'Parent' },
    grosseltern: { w: 'Grandmother', m: 'Grandfather', other: 'Grandparent' },
    urgrosseltern: { w: 'Great-grandmother', m: 'Great-grandfather', other: 'Great-grandparent' },
    ururgrosseltern: { w: 'Great-great-grandmother', m: 'Great-great-grandfather', other: 'Great-great-grandparent' },
    vorfahreN: (n) => `Ancestor, ${n} generations up`,
    kind: { w: 'Daughter', m: 'Son', other: 'Child' },
    enkel: { w: 'Granddaughter', m: 'Grandson', other: 'Grandchild' },
    urenkel: { w: 'Great-granddaughter', m: 'Great-grandson', other: 'Great-grandchild' },
    ururenkel: { w: 'Great-great-granddaughter', m: 'Great-great-grandson', other: 'Great-great-grandchild' },
    nachkommeN: (n) => `Descendant, ${n} generations down`,
    geschwister: { w: 'Sister', m: 'Brother', other: 'Sibling' },
    halbgeschwister: { w: 'Half-sister', m: 'Half-brother', other: 'Half-sibling' },
    neffeNichte: { w: 'Niece', m: 'Nephew', other: 'Sibling’s child' },
    grossneffeNichte: { w: 'Great-niece', m: 'Great-nephew', other: 'Sibling’s grandchild' },
    geschwisterNachkommeN: (n) => `Descendant of a sibling, ${n} steps down`,
    onkelTante: { w: 'Aunt', m: 'Uncle', other: 'Parent’s sibling' },
    grossonkelTante: { w: 'Great-aunt', m: 'Great-uncle', other: 'Grandparent’s sibling' },
    vorfahrengeschwisterN: (n) => `Sibling of an ancestor, ${n} generations up`,
    cousin: (_g, n) => `${n === 1 ? 'First' : n === 2 ? 'Second' : `Degree-${n}`} cousin`,
    entfernt: (b, n) => `${b}, ${n} times removed`,
    partner: { w: 'Partner', m: 'Partner', other: 'Partner' },
    schwager: { w: 'Sister-in-law', m: 'Brother-in-law', other: 'Sibling-in-law' },
    schwiegereltern: { w: 'Mother-in-law', m: 'Father-in-law', other: 'Parent-in-law' },
    schwiegerkind: { w: 'Daughter-in-law', m: 'Son-in-law', other: 'Child-in-law' },
    stiefeltern: { w: 'Stepmother', m: 'Stepfather', other: 'Stepparent' },
    stiefkind: { w: 'Stepdaughter', m: 'Stepson', other: 'Stepchild' },
    stiefgeschwister: { w: 'Stepsister', m: 'Stepbrother', other: 'Stepsibling' },
    adoptiveltern: { w: 'Adoptive mother', m: 'Adoptive father', other: 'Adoptive parent' },
    pflegeeltern: { w: 'Foster mother', m: 'Foster father', other: 'Foster parent' },
    adoptivkind: { w: 'Adopted daughter', m: 'Adopted son', other: 'Adopted child' },
    pflegekind: { w: 'Foster daughter', m: 'Foster son', other: 'Foster child' },
    angeheiratet: () => 'related by marriage',
    keine: () => 'not related',
    ueberWeg: (schritt, bezug, name) => `${schritt} of ${bezug} ${name}`,
    titel: (n) => `The ${n} family tree`,
    titelKurz: (n) => `The ${n} family`,
    titelOhneName: 'Family tree',
    untertitel: {
      vorfahren: (n) => `The ancestors of ${n}`,
      paar: (n) => `The ancestors of ${n}`,
      nachkommen: (n) => `The descendants of ${n}`,
      familie: (n) => `The family of ${n}`,
    },
  },
};

const lbSprache = () => (typeof spracheJetzt === 'function' ? spracheJetzt() : 'de');
const lbG = (geschlecht) => (geschlecht === 'w' ? 'w' : geschlecht === 'm' ? 'm' : 'other');

// lib/widgets/verwandtschaft_text.dart
function lbGradText(grad, geschlecht) {
  const t = LB_GRAD[lbSprache()] || LB_GRAD.de;
  const g = lbG(geschlecht);
  const w = (tabelle) => tabelle[g];
  const auf = grad.aufwaerts || 0, ab = grad.abwaerts || 0;
  switch (grad.art) {
    case 'selbst': return t.selbst();
    case 'vorfahre':
      if (grad.elternArt === 'adoptivelternteil') return w(t.adoptiveltern);
      if (grad.elternArt === 'pflegeelternteil') return w(t.pflegeeltern);
      return [null, t.eltern, t.grosseltern, t.urgrosseltern, t.ururgrosseltern][auf] ? w([null, t.eltern, t.grosseltern, t.urgrosseltern, t.ururgrosseltern][auf]) : t.vorfahreN(auf);
    case 'nachkomme':
      if (grad.elternArt === 'adoptivelternteil') return w(t.adoptivkind);
      if (grad.elternArt === 'pflegeelternteil') return w(t.pflegekind);
      return [null, t.kind, t.enkel, t.urenkel, t.ururenkel][ab] ? w([null, t.kind, t.enkel, t.urenkel, t.ururenkel][ab]) : t.nachkommeN(ab);
    case 'geschwister': return w(grad.halb ? t.halbgeschwister : t.geschwister);
    case 'geschwisterkind': return ab === 2 ? w(t.neffeNichte) : ab === 3 ? w(t.grossneffeNichte) : t.geschwisterNachkommeN(ab);
    case 'vorfahrengeschwister': return auf === 2 ? w(t.onkelTante) : auf === 3 ? w(t.grossonkelTante) : t.vorfahrengeschwisterN(auf);
    case 'cousin': {
      const grund = t.cousin(g, Math.min(auf, ab) - 1);
      const entfernung = Math.abs(auf - ab);
      return entfernung === 0 ? grund : t.entfernt(grund, entfernung);
    }
    case 'partner': return w(t.partner);
    case 'schwager': return w(t.schwager);
    case 'schwiegerelternteil': return w(t.schwiegereltern);
    case 'schwiegerkind': return w(t.schwiegerkind);
    case 'stiefelternteil': return w(t.stiefeltern);
    case 'stiefkind': return w(t.stiefkind);
    case 'stiefgeschwister': return w(t.stiefgeschwister);
    case 'angeheiratet': return t.angeheiratet();
    default: return t.keine();
  }
}

function lbBezeichnung(person) {
  if (!person.grad) return null;
  const t = LB_GRAD[lbSprache()] || LB_GRAD.de;
  if (person.umweg) {
    return t.ueberWeg(
      lbGradText(person.umweg.schritt, person.geschlecht),
      lbGradText(person.umweg.ueberGrad, person.umweg.geschlecht),
      person.umweg.name,
    );
  }
  return lbGradText(person.grad, person.geschlecht);
}

let lb = null;

function lbBild(url) {
  return new Promise((fertig) => {
    const i = new Image();
    i.onload = () => fertig(i);
    i.onerror = () => fertig(null);
    i.src = url;
  });
}

async function zeigeLebensbaum(fokus) {
  markiereNav('stammbaum');
  zeigeBereich(['lebensbaum']);
  const q = new URLSearchParams();
  if (fokus) q.set('fokus', fokus);
  for (const [name, id] of [['stil', 'lb-stil'], ['richtung', 'lb-richtung'], ['generationen', 'lb-generationen'], ['oben', 'lb-oben'], ['unten', 'lb-unten'], ['kreis', 'lb-kreis']]) {
    if (lb && lb.gewaehlt && lb.gewaehlt[name] != null) q.set(name, lb.gewaehlt[name]);
  }
  $('lb-hinweis').textContent = t('Lade …');
  const d = await api(`/api/v1/lebensbaum?${q}`);
  if (!d.fokus) {
    $('lb-hinweis').textContent = t('Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.');
    return;
  }
  lb = { ...(lb || {}), d, gewaehlt: { ...d.optionen } };
  const wahl = $('lb-person');
  wahl.replaceChildren();
  for (const p of [...d.alle].sort((a, b) => a.name.localeCompare(b.name))) {
    const o = el('option', null, p.name);
    o.value = p.id;
    wahl.append(o);
  }
  wahl.value = d.fokus;
  $('lb-stil').value = d.optionen.stil;
  $('lb-richtung').value = d.optionen.richtung;
  $('lb-generationen').value = String(d.optionen.generationen);
  $('lb-oben').value = String(d.optionen.oben);
  $('lb-unten').value = String(d.optionen.unten);
  $('lb-kreis').value = d.optionen.kreis;
  const familie = d.optionen.richtung === 'familie';
  for (const e of document.querySelectorAll('.lb-familie')) e.hidden = !familie;
  for (const e of document.querySelectorAll('.lb-nicht-familie')) e.hidden = familie;

  // Bilder und Schriften laden, bevor gemalt wird.
  const v = d.vorlage;
  const [hintergrund, schild] = await Promise.all([
    lbBild(`lebensbaum/${d.hintergrund}`),
    v.schildBild ? lbBild(`lebensbaum/${v.schildBild}`) : Promise.resolve(null),
    document.fonts.load("620 40px 'Zierschrift'"),
    document.fonts.load("italic 40px 'Zierschrift'"),
    document.fonts.load("40px 'Zierschrift Gross'"),
  ]);
  const portraits = {};
  await Promise.all(Object.entries(d.personen).map(async ([id, p]) => {
    if (!p.bild) return;
    const bild = await lbBild(`/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}`);
    if (bild) portraits[id] = bild;
  }));
  lb.bilder = { hintergrund, schild, portraits };
  const hinweise = [];
  if (!hintergrund) hinweise.push(t('Das Vorlagenbild fehlt auf dem Server.'));
  if (d.verschwiegen) hinweise.push(t('{n} Haushalte passen nicht mehr ins Bild.', { n: d.verschwiegen }));
  $('lb-hinweis').textContent = hinweise.join(' ');
  lbMale();
}

// Die Schrift in CSS-Form; px in Vorlageneinheiten.
const lbSchrift = (px, { gewicht = 400, kursiv = false, gross = false } = {}) =>
  gross ? `${px}px 'Zierschrift Gross'` : `${kursiv ? 'italic ' : ''}${gewicht} ${px}px 'Zierschrift'`;

// Bricht einen Namen in höchstens zwei Zeilen; null, wenn er nicht passt.
function lbUmbruch(ctx, text, breite) {
  const woerter = text.split(' ');
  for (const w of woerter) if (ctx.measureText(w).width > breite) return null;
  const zeilen = [];
  let zeile = '';
  for (const w of woerter) {
    const probe = zeile ? `${zeile} ${w}` : w;
    if (ctx.measureText(probe).width <= breite) { zeile = probe; continue; }
    zeilen.push(zeile);
    zeile = w;
  }
  if (zeile) zeilen.push(zeile);
  return zeilen.length <= 2 ? zeilen : null;
}

// _beschrifte: so gross, wie das Schild es fasst; wird es unleserlich,
// fällt erst die Verwandtschaft, dann die Lebensdaten weg.
function lbBeschrifte(ctx, r, leute, amStamm, v) {
  if (!leute.length) return;
  const lesbar = 6.5;
  const [l, t, rr, b] = r;
  const breite = rr - l, hoehe = b - t;
  for (let stufe = 0; stufe < 3; stufe++) {
    if (stufe === 0 && amStamm) continue;
    const mitBezeichnung = stufe === 0, mitSpanne = stufe < 2;
    const start = (hoehe / (leute.length * 2 + 0.6)) * 1.1;
    for (let g = start; g >= 3; g *= 0.93) {
      if (stufe < 2 && g < lesbar) break;
      const klein = g * 0.74;
      const zeilen = [];
      let passt = true;
      leute.forEach((p, n) => {
        if (n > 0) zeilen.push({ text: '&', schrift: lbSchrift(klein), farbe: v.nebenschrift, hoehe: klein * 1.1 });
        if (mitBezeichnung && p.bezeichnung) {
          ctx.font = lbSchrift(klein, { kursiv: true });
          if (ctx.measureText(p.bezeichnung).width > breite) passt = false;
          zeilen.push({ text: p.bezeichnung, schrift: ctx.font, farbe: v.nebenschrift, hoehe: klein * 1.1 });
        }
        ctx.font = lbSchrift(g, { gewicht: 620 });
        const name = lbUmbruch(ctx, p.name, breite);
        if (!name) passt = false;
        for (const z of name || []) zeilen.push({ text: z, schrift: lbSchrift(g, { gewicht: 620 }), farbe: v.schrift, hoehe: g * 1.05 });
        if (mitSpanne && p.lebensspanne) {
          ctx.font = lbSchrift(klein);
          if (ctx.measureText(p.lebensspanne).width > breite) passt = false;
          zeilen.push({ text: p.lebensspanne, schrift: lbSchrift(klein), farbe: v.nebenschrift, hoehe: klein * 1.1 });
        }
      });
      const gesamt = zeilen.reduce((s, z) => s + z.hoehe, 0);
      if (!passt || gesamt > hoehe) continue;
      let y = t + (hoehe - gesamt) / 2;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      for (const z of zeilen) {
        ctx.font = z.schrift;
        ctx.fillStyle = z.farbe;
        ctx.fillText(z.text, l + breite / 2, y + z.hoehe / 2);
        y += z.hoehe;
      }
      return;
    }
  }
}

function lbTitel(ctx, d) {
  const v = d.vorlage;
  const t = LB_GRAD[lbSprache()] || LB_GRAD.de;
  const titel = d.nachname ? (v.untertitel ? t.titelKurz(d.nachname) : t.titel(d.nachname)) : t.titelOhneName;
  const [l, o, r, u] = v.titel;
  let g = (u - o) * 0.8;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  while (true) {
    ctx.font = lbSchrift(g, { gross: true });
    if (ctx.measureText(titel).width <= r - l || g < 6) break;
    g *= 0.92;
  }
  ctx.fillStyle = v.schrift;
  ctx.fillText(titel, (l + r) / 2, (o + u) / 2);
  if (!v.untertitel) return;
  const [ul, uo, ur, uu] = v.untertitel;
  const text = t.untertitel[d.optionen.richtung](d.fokusName);
  ctx.font = lbSchrift(Math.min((uu - uo) * 0.6, g * 0.42), { kursiv: true });
  ctx.fillStyle = v.nebenschrift;
  ctx.textBaseline = 'top';
  let zeile = text;
  while (ctx.measureText(zeile).width > ur - ul && zeile.length > 2) zeile = `${zeile.slice(0, -2)}…`;
  ctx.fillText(zeile, (ul + ur) / 2, uo);
}

function lbMale() {
  if (!lb || !lb.d) return;
  const { d, bilder } = lb;
  const v = d.vorlage;
  const [w, h] = v.groesse;
  const leinwand = $('lb-leinwand');
  leinwand.width = Math.round(w * LB_FAKTOR);
  leinwand.height = Math.round(h * LB_FAKTOR);
  const ctx = leinwand.getContext('2d');
  ctx.setTransform(LB_FAKTOR, 0, 0, LB_FAKTOR, 0, 0);
  ctx.imageSmoothingQuality = 'high';
  ctx.clearRect(0, 0, w, h);
  if (bilder.hintergrund) ctx.drawImage(bilder.hintergrund, 0, 0, w, h);
  const mitPortraits = $('lb-portraits').checked;
  for (const p of d.plaetze) {
    const [l, t, r, b] = p.rahmen;
    if (bilder.schild && p.zuSetzen) ctx.drawImage(bilder.schild, l, t, r - l, b - t);
    const leute = p.personen.map((id) => {
      const x = d.personen[id] || { name: '?' };
      return { name: x.name, lebensspanne: x.lebensspanne, bezeichnung: p.amStamm ? null : lbBezeichnung(x) };
    });
    const schrift = mitPortraits && p.kreise.some((k) => bilder.portraits[k.id]) ? p.schriftMitPortrait : p.schrift;
    lbBeschrifte(ctx, schrift, leute, !!p.amStamm, v);
  }
  if (mitPortraits) {
    for (const p of d.plaetze) {
      for (const { kreis, id } of p.kreise) {
        const bild = bilder.portraits[id];
        if (!bild) continue;
        const [l, t, r, b] = kreis;
        const cx = (l + r) / 2, cy = (t + b) / 2, rad = (r - l) / 2;
        const seite = Math.min(bild.naturalWidth, bild.naturalHeight);
        ctx.save();
        ctx.beginPath();
        ctx.arc(cx, cy, rad, 0, Math.PI * 2);
        ctx.clip();
        ctx.drawImage(bild, (bild.naturalWidth - seite) / 2, (bild.naturalHeight - seite) / 2, seite, seite, l, t, r - l, b - t);
        ctx.restore();
        ctx.beginPath();
        ctx.arc(cx, cy, rad, 0, Math.PI * 2);
        ctx.lineWidth = (r - l) * 0.04;
        ctx.strokeStyle = v.nebenschrift;
        ctx.stroke();
      }
    }
  }
  lbTitel(ctx, d);
}

// Wer unter dem Finger liegt: Schilder mit zwei Personen teilen sich die
// Höhe (Lebensbaumplatz.flaechen).
function lbPersonBei(x, y) {
  for (const p of lb.d.plaetze) {
    const [l, t, r, b] = p.rahmen;
    if (x < l || x >= r || y < t || y >= b) continue;
    const n = p.personen.length;
    return p.personen[Math.min(n - 1, Math.floor(((y - t) / (b - t)) * n))];
  }
  return null;
}

$('lb-leinwand').addEventListener('click', (e) => {
  if (!lb || !lb.d) return;
  const rect = e.target.getBoundingClientRect();
  const [w, h] = lb.d.vorlage.groesse;
  const id = lbPersonBei(((e.clientX - rect.left) / rect.width) * w, ((e.clientY - rect.top) / rect.height) * h);
  if (id && id !== lb.d.fokus) location.hash = `#/lebensbaum/${encodeURIComponent(id)}`;
});

for (const [id, name] of [['lb-stil', 'stil'], ['lb-richtung', 'richtung'], ['lb-generationen', 'generationen'], ['lb-oben', 'oben'], ['lb-unten', 'unten'], ['lb-kreis', 'kreis']]) {
  $(id).addEventListener('change', () => {
    if (!lb) return;
    lb.gewaehlt[name] = $(id).value;
    zeigeLebensbaum(lb.d && lb.d.fokus).catch((x) => { $('lb-hinweis').textContent = x.message; });
  });
}
$('lb-person').addEventListener('change', () => { location.hash = `#/lebensbaum/${encodeURIComponent($('lb-person').value)}`; });
$('lb-portraits').addEventListener('change', lbMale);
$('lb-zum-stammbaum').addEventListener('click', () => { location.hash = `#/stammbaum/${encodeURIComponent((lb && lb.d && lb.d.fokus) || '')}`; });
$('lb-laden').addEventListener('click', () => {
  $('lb-leinwand').toBlob((blob) => {
    if (!blob) return;
    const a = el('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'lebensbaum.png';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }, 'image/png');
});

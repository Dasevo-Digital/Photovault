// Die Weboberfläche von Photo Vault – ohne Bibliothek, ohne Bauschritt.
//
// Alles, was vom Server kommt, wird als Text eingesetzt (textContent),
// nie als HTML. Jede schreibende Anfrage trägt den Kopf X-PV-Web (siehe
// anfrageAusDerOberflaeche auf dem Server). Das Cookie der Sitzung sieht
// dieses Skript nie; der Browser schickt es von selbst mit.
'use strict';

const $ = (id) => document.getElementById(id);
const api = async (pfad, { methode = 'GET', json } = {}) => {
  const antwort = await fetch(pfad, {
    method: methode,
    credentials: 'same-origin',
    headers: {
      'X-PV-Web': '1',
      ...(json === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: json === undefined ? undefined : JSON.stringify(json),
  });
  let daten = null;
  try { daten = await antwort.json(); } catch (_) { /* keine Daten */ }
  if (antwort.status === 401) { zeigeAnmeldung(); throw new Error('nicht angemeldet'); }
  if (!antwort.ok) {
    const f = new Error((daten && daten.fehler) || `Fehler ${antwort.status}`);
    f.status = antwort.status;
    throw f;
  }
  return daten;
};
const befehl = (art, werte) => api('/api/v1/befehle', { methode: 'POST', json: { art, werte } });
const el = (tag, klasse, text) => {
  const e = document.createElement(tag);
  if (klasse) e.className = klasse;
  if (text !== undefined) e.textContent = text;
  return e;
};
const miniaturUrl = (id) => `/api/v1/aufnahmen/${encodeURIComponent(id)}/miniatur`;
const datum = new Intl.DateTimeFormat(undefined, { dateStyle: 'full' });
const datumZeit = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });

let sitzung = null;   // {name, verwalter, geraet}

// --- Ansichten -------------------------------------------------------------

function zeigeAnmeldung() {
  sitzung = null;
  $('kopf').hidden = true;
  $('inhalt').hidden = true;
  $('anmeldung').hidden = false;
  $('form-anmelden').hidden = false;
  $('form-totp').hidden = true;
  auswahlAufheben();
}

function zeigeBereich(name) {
  for (const s of document.querySelectorAll('#inhalt > section')) s.hidden = true;
  for (const b of name) $(`bereich-${b}`).hidden = false;
}

function markiereNav(bereich) {
  for (const a of $('nav').querySelectorAll('a')) {
    a.classList.toggle('aktiv', a.dataset.bereich === bereich);
  }
}

// --- Anmeldung -------------------------------------------------------------

let vorgang = null;
function fehler(text) { $('fehler').textContent = text || ''; }

async function nachAnmeldung(d) {
  if (d.angemeldet) {
    fehler('');
    if (d.wiederherstellungscodes) {
      alert('Deine Wiederherstellungscodes – bitte sicher aufbewahren:\n\n' + d.wiederherstellungscodes.join('\n'));
    }
    await starte();
    return;
  }
  vorgang = d.vorgang;
  $('form-anmelden').hidden = true;
  $('form-totp').hidden = false;
  const einrichten = d.schritt === 'totp_einrichten';
  $('totp-einrichten').hidden = !einrichten;
  $('totp-hinweis').textContent = einrichten
    ? 'Dieses Konto braucht einen zweiten Faktor.'
    : 'Gib den Code aus deiner Authenticator-App ein.';
  if (einrichten) {
    $('totp-geheimnis').textContent = d.geheimnis;
    $('totp-link').href = d.adresse;
  }
  $('form-totp').code.focus();
}

$('form-anmelden').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    await nachAnmeldung(await api('/api/v1/web/anmelden', {
      methode: 'POST',
      json: { name: f.name.value.trim(), passwort: f.passwort.value },
    }));
    f.passwort.value = '';
  } catch (x) { fehler(x.message); }
});

$('form-totp').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    await nachAnmeldung(await api('/api/v1/web/anmelden/totp', {
      methode: 'POST',
      json: { vorgang, code: f.code.value.trim() },
    }));
    f.code.value = '';
  } catch (x) { fehler(x.message); }
});

async function abmelden() {
  try { await api('/api/v1/web/abmelden', { methode: 'POST' }); } catch (_) { /* egal */ }
  zeitleiste.leeren();
  $('form-anmelden').reset();
  location.hash = '#/';
  zeigeAnmeldung();
}
$('abmelden').addEventListener('click', abmelden);

// --- Raster ----------------------------------------------------------------
//
// Eine Liste trägt ihre Aufnahmen, ob sie nach Tagen gegliedert wird, und
// wie sie nachlädt (nur die Zeitleiste). Der Betrachter läuft über die
// gerade gezeigte Liste.

let liste = null;
let letzterTag = null;

function kachel(a, index) {
  const k = el('button', 'kachel');
  k.type = 'button';
  k.dataset.index = index;
  const img = el('img');
  img.loading = 'lazy';
  img.decoding = 'async';
  img.alt = '';
  img.src = miniaturUrl(a.id);
  k.append(img);
  if (a.art === 'video') k.append(el('span', 'marke', '▶'));
  if (a.favorit) k.append(el('span', 'herz', '♥'));
  if (a.serie && a.serie.titel && a.serie.groesse > 1) k.append(el('span', 'stapel', `⧉ ${a.serie.groesse}`));
  if (auswahl.has(a.id)) k.classList.add('gewaehlt');
  k.addEventListener('click', () => (auswahlModus ? schalteAuswahl(a.id, k) : oeffne(index)));
  let halten;
  k.addEventListener('pointerdown', () => { halten = setTimeout(() => { auswahlModus = true; schalteAuswahl(a.id, k); }, 500); });
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel']) k.addEventListener(ev, () => clearTimeout(halten));
  return k;
}

function haengeAn(aufnahmen) {
  const raster = $('raster');
  for (const a of aufnahmen) {
    if (liste.nachTagen) {
      const tag = datum.format(new Date(a.aufgenommen));
      if (tag !== letzterTag) {
        letzterTag = tag;
        raster.append(el('h2', null, tag));
      }
    }
    raster.append(kachel(a, liste.aufnahmen.length));
    liste.aufnahmen.push(a);
  }
}

function zeigeListe(neu, titel) {
  liste = { aufnahmen: [], nachTagen: false, mehr: null, ...neu, aufnahmen: [] };
  $('erinnerungen').hidden = true;
  $('auswahl-papierkorb').hidden = !!liste.papierkorb;
  $('auswahl-zurueck').hidden = !liste.papierkorb;
  letzterTag = null;
  $('raster').replaceChildren();
  $('raster-titel').hidden = !titel;
  $('raster-titel').textContent = titel || '';
  $('ende').textContent = '';
  haengeAn(neu.aufnahmen || []);
  if (!liste.mehr) $('ende').textContent = liste.aufnahmen.length ? `${liste.aufnahmen.length} Aufnahmen` : 'Keine Aufnahmen.';
}

async function ladeMehr() {
  if (!liste || !liste.mehr || liste.laedt) return;
  liste.laedt = true;
  try {
    const d = await liste.mehr();
    haengeAn(d.aufnahmen);
    if (!d.weiter) {
      liste.mehr = null;
      $('ende').textContent = liste.aufnahmen.length ? `${liste.aufnahmen.length} Aufnahmen` : 'Noch keine Aufnahmen.';
    }
  } catch (x) {
    $('ende').textContent = x.message;
  } finally {
    liste.laedt = false;
  }
}

const waechter = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) ladeMehr(); });
waechter.observe($('ende'));

// Die Zeitleiste merkt sich ihr Lesezeichen, damit ein Wechsel in ein
// Album nicht alles neu lädt.
const zeitleiste = {
  weiter: undefined,
  geladen: [],
  leeren() { this.weiter = undefined; this.geladen = []; },
  async mehr() {
    const q = new URLSearchParams({ anzahl: '200' });
    if (this.weiter) q.set('nach', this.weiter);
    const d = await api(`/api/v1/aufnahmen?${q}`);
    this.weiter = d.weiter;
    this.geladen.push(...d.aufnahmen);
    return d;
  },
};

// --- Bereiche --------------------------------------------------------------

async function zeigeFotos() {
  markiereNav('fotos');
  zeigeBereich(['raster']);
  zeigeListe({ aufnahmen: zeitleiste.geladen, nachTagen: true, mehr: zeitleiste.weiter === null ? null : () => zeitleiste.mehr() });
  if (zeitleiste.geladen.length === 0) await ladeMehr();
  zeigeErinnerungen().catch(() => {});
}

// „Vor x Jahren“ über der Zeitleiste – ein Kärtchen je Jahrgang.
const monate = new Intl.DateTimeFormat(undefined, { month: 'long' });
async function zeigeErinnerungen() {
  const d = await api('/api/v1/erinnerungen');
  const box = $('erinnerungen');
  const karten = $('erinnerungen-karten');
  karten.replaceChildren();
  box.hidden = d.art === 'keiner' || d.gruppen.length === 0;
  if (box.hidden) return;
  const monat = monate.format(new Date(2000, d.monat - 1, 1));
  for (const g of d.gruppen) {
    const k = el('button', 'erinnerung');
    k.type = 'button';
    const img = el('img'); img.alt = ''; img.loading = 'lazy'; img.src = miniaturUrl(g.aufnahmen[0].id);
    const text = d.art === 'tag' ? `Vor ${g.jahreHer} Jahr${g.jahreHer === 1 ? '' : 'en'}` : `${monat} vor ${g.jahreHer} Jahr${g.jahreHer === 1 ? '' : 'en'}`;
    k.append(img, el('span', null, `${text} · ${g.aufnahmen.length}`));
    k.addEventListener('click', () => { zeigeBereich(['raster']); $('erinnerungen').hidden = true; zeigeListe({ aufnahmen: g.aufnahmen }, text); oeffne(0); });
    karten.append(k);
  }
}

async function zeigePapierkorb() {
  markiereNav('papierkorb');
  zeigeBereich(['raster']);
  const d = await api('/api/v1/papierkorb');
  zeigeListe({ aufnahmen: d.aufnahmen, papierkorb: true }, 'Papierkorb');
  if (d.aufnahmen.length === 0) $('ende').textContent = 'Der Papierkorb ist leer.';
}

function karte(bildUrl, titel, untertitel, ziel) {
  const a = el('a', 'albumkarte');
  a.href = ziel;
  const bild = el('div', 'albumbild');
  if (bildUrl) { const img = el('img'); img.loading = 'lazy'; img.alt = ''; img.src = bildUrl; bild.append(img); }
  a.append(bild, el('div', 'titel', titel), el('div', 'leise klein', untertitel));
  return a;
}

async function zeigeAlben() {
  markiereNav('alben');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = 'Alben';
  $('karten').replaceChildren();
  const d = await api('/api/v1/alben');
  if (d.alben.length === 0) $('karten').append(el('p', 'leise', 'Noch keine Alben.'));
  for (const a of d.alben) {
    $('karten').append(karte(a.titelbild ? miniaturUrl(a.titelbild) : null, a.name, `${a.anzahl} Aufnahmen`, `#/alben/${encodeURIComponent(a.id)}`));
  }
}

async function zeigeAlbum(id) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/alben/${encodeURIComponent(id)}`);
  zeigeListe({ aufnahmen: d.aufnahmen }, d.album.name);
}

const zeitraum = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' });
async function zeigeReisen() {
  markiereNav('reisen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = 'Reisen';
  $('karten').replaceChildren();
  const d = await api('/api/v1/reisen');
  if (d.reisen.length === 0) $('karten').append(el('p', 'leise', 'Noch keine Reisen.'));
  for (const r of d.reisen) {
    $('karten').append(karte(r.titelbild ? miniaturUrl(r.titelbild) : null, r.name, `${zeitraum.format(new Date(r.von))} – ${zeitraum.format(new Date(r.bis))} · ${r.anzahl} Aufnahmen`, `#/reisen/${encodeURIComponent(r.id)}`));
  }
}

async function zeigeReise(id) {
  markiereNav('reisen');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/reisen/${encodeURIComponent(id)}`);
  zeigeListe({ aufnahmen: d.aufnahmen, nachTagen: true }, `${d.reise.name} · ${zeitraum.format(new Date(d.reise.von))} – ${zeitraum.format(new Date(d.reise.bis))}`);
}

const zahl = new Intl.NumberFormat();
const groesse = (b) => (b >= 1073741824 ? `${(b / 1073741824).toFixed(1)} GB` : b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.round(b / 1024)} KB`);
const monatsname = new Intl.DateTimeFormat(undefined, { month: 'short' });

function kennzahl(wert, name) {
  const k = el('div', 'kennzahl');
  k.append(el('div', 'wert', wert), el('div', 'name', name));
  return k;
}

// Ein Balkendiagramm aus Spalten; die Höhe setzt das Skript über das CSSOM,
// was die CSP erlaubt (sie sperrt nur style-Attribute im Markup).
function balken(ziel, werte, beschrifte) {
  ziel.replaceChildren();
  const max = Math.max(0, ...werte.map(([, n]) => n));
  ziel.setAttribute('aria-label', werte.map(([k, n]) => `${beschrifte(k)}: ${zahl.format(n)}`).join(', '));
  for (const [k, n] of werte) {
    const spalte = el('div', 'spalte');
    spalte.title = `${beschrifte(k)}: ${zahl.format(n)}`;
    const raum = el('div', 'raum');
    const stab = el('div', 'stab');
    stab.style.height = max ? `${Math.max(n ? 2 : 0, Math.round((n / max) * 100))}%` : '0';
    raum.append(stab);
    spalte.append(el('span', 'wert', n ? zahl.format(n) : ''), raum, el('span', 'achse', beschrifte(k)));
    ziel.append(spalte);
  }
}

async function zeigeStatistik() {
  markiereNav('statistik');
  zeigeBereich(['statistik']);
  const s = await api('/api/v1/statistik');
  $('stat-leer').hidden = s.insgesamt > 0;
  $('stat-diagramme').hidden = s.insgesamt === 0;
  $('stat-kennzahlen').replaceChildren(
    kennzahl(zahl.format(s.insgesamt), 'Medien insgesamt'),
    kennzahl(zahl.format(s.fotos), 'Fotos'),
    kennzahl(zahl.format(s.videos), 'Videos'),
    kennzahl(zahl.format(s.favoriten), 'Favoriten'),
    kennzahl(groesse(s.bytes), 'Speicherplatz'),
    kennzahl(zahl.format(s.papierkorb), 'Im Papierkorb'),
    kennzahl(zahl.format(s.gesperrt), 'Gesperrter Ordner'),
  );
  if (s.insgesamt === 0) return;
  // Jahre lückenlos vom ersten bis zum letzten, damit leere Jahre sichtbar bleiben.
  const jahre = Object.keys(s.proJahr).map(Number).sort((a, b) => a - b);
  const jahrWerte = [];
  for (let j = jahre[0]; j <= jahre[jahre.length - 1]; j++) jahrWerte.push([j, s.proJahr[j] || 0]);
  balken($('stat-jahre'), jahrWerte, String);
  balken($('stat-monate'), Array.from({ length: 12 }, (_, i) => [i + 1, s.proMonat[i + 1] || 0]), (m) => monatsname.format(new Date(2000, m - 1, 1)));
  $('stat-kameras-titel').hidden = $('stat-kameras').hidden = s.kameras.length === 0;
  $('stat-kameras').replaceChildren();
  const max = Math.max(0, ...s.kameras.map((k) => k.anzahl));
  for (const k of s.kameras) {
    const li = el('li');
    const leiste = el('div', 'leiste');
    const fuell = el('div', 'fuell');
    fuell.style.width = max ? `${Math.round((k.anzahl / max) * 100)}%` : '0';
    leiste.append(fuell);
    const name = el('span', 'name', k.name);
    name.title = k.name;
    li.append(name, leiste, el('span', 'n', zahl.format(k.anzahl)));
    $('stat-kameras').append(li);
  }
}

// --- Duplikate -------------------------------------------------------------
// Die Gruppen kommen vom Server (dieselbe Suche wie auf dem Rechner); hier
// wird nur gezeigt und entschieden. „Behalten“ führt die Gruppe über den
// Befehl zusammen, der Rest geht in den Papierkorb.

let duplikate = null;
const prozent = (w) => `${Math.round(w * 100)} %`;
$('dupl-schwelle').addEventListener('input', () => { $('dupl-schwelle-wert').textContent = prozent($('dupl-schwelle').value); });
$('dupl-suchen').addEventListener('click', () => sucheDuplikate().catch((x) => { $('dupl-hinweis').textContent = x.message; }));

async function zeigeDuplikate() {
  markiereNav('duplikate');
  zeigeBereich(['duplikate']);
  if (duplikate) zeichneDuplikate(); else await sucheDuplikate();
}

async function sucheDuplikate() {
  $('dupl-hinweis').textContent = 'Suche …';
  $('dupl-gruppen').replaceChildren();
  $('dupl-alle').hidden = true;
  duplikate = await api(`/api/v1/duplikate?schwelle=${$('dupl-schwelle').value}`);
  zeichneDuplikate();
}

function zeichneDuplikate() {
  const d = duplikate;
  const ziel = $('dupl-gruppen');
  ziel.replaceChildren();
  const loeschbar = d.gruppen.reduce((n, g) => n + g.loeschbar.length, 0);
  $('dupl-alle').hidden = loeschbar === 0;
  $('dupl-alle').textContent = `${loeschbar} Kopien in den Papierkorb`;
  if (d.einbettungen === 0) {
    $('dupl-hinweis').textContent = 'Noch keine Bildeinbettungen – die Auswertung auf dem Server muss zuerst gelaufen sein.';
  } else if (d.gruppen.length === 0) {
    $('dupl-hinweis').textContent = `Keine Duplikate bei ${prozent(d.schwelle)} Ähnlichkeit.${d.ausnahmen ? ` ${d.ausnahmen} Paare sind ausgenommen.` : ''}`;
  } else {
    $('dupl-hinweis').textContent = `${d.gruppen.length} Gruppen bei ${prozent(d.schwelle)} Ähnlichkeit. Das umrandete Foto würde beim Aufräumen behalten; Gruppen mit mehreren Favoriten oder Bewertungen bleiben unangetastet.`;
  }
  for (const g of d.gruppen) ziel.append(duplikatgruppe(g));
}

function duplikatgruppe(g) {
  const box = el('div', 'gruppe');
  const ids = g.aufnahmen.map((a) => a.id);
  const entferne = () => { duplikate.gruppen = duplikate.gruppen.filter((x) => x !== g); zeichneDuplikate(); };
  const kopf = el('div', 'gruppenkopf');
  const ignorieren = el('button', null, 'Keine Duplikate');
  ignorieren.type = 'button';
  ignorieren.addEventListener('click', async () => {
    try { await befehl('duplikatgruppeIgnorieren', { ids }); entferne(); } catch (x) { $('dupl-hinweis').textContent = x.message; }
  });
  kopf.append(el('span', null, `${g.aufnahmen.length} Aufnahmen${g.loeschbar.length ? '' : ' · mehrere ausgezeichnet, nur von Hand'}`), ignorieren);
  box.append(kopf);
  const reihe = el('div', 'reihe');
  g.aufnahmen.forEach((a, i) => {
    const t = el('div', 'dupl');
    if (a.id === g.behalten) t.classList.add('beste');
    const img = el('img');
    img.loading = 'lazy';
    img.alt = '';
    img.src = miniaturUrl(a.id);
    img.addEventListener('click', () => { liste = { aufnahmen: g.aufnahmen, nachTagen: false, mehr: null }; oeffne(i); });
    const knopf = el('button', null, 'Behalten');
    knopf.type = 'button';
    knopf.addEventListener('click', async () => {
      const andere = ids.filter((x) => x !== a.id);
      if (!confirm(`„${a.name}“ behalten und ${andere.length === 1 ? 'die andere Aufnahme' : `die ${andere.length} anderen`} in den Papierkorb legen?`)) return;
      try {
        await befehl('duplikateZusammenfuehren', { behaltenId: a.id, duplikatIds: andere, beschreibungenVerbinden: true });
        entferne();
      } catch (x) { $('dupl-hinweis').textContent = x.message; }
    });
    const angaben = [a.breite && a.hoehe ? `${a.breite} × ${a.hoehe}` : '', datumZeit.format(new Date(a.aufgenommen)), a.favorit ? '♥' : '', a.bewertung ? '★'.repeat(a.bewertung) : ''].filter(Boolean).join(' · ');
    const name = el('div', 'name', a.name);
    name.title = a.name;
    t.append(img, name, el('div', 'angaben', angaben), knopf);
    reihe.append(t);
  });
  box.append(reihe);
  return box;
}

$('dupl-alle').addEventListener('click', async () => {
  const faellig = duplikate.gruppen.filter((g) => g.loeschbar.length);
  const n = faellig.reduce((s, g) => s + g.loeschbar.length, 0);
  if (!confirm(`${n} Kopien aus ${faellig.length} Gruppen in den Papierkorb legen? Je Gruppe bleibt das umrandete Foto.`)) return;
  try {
    for (const g of faellig) {
      await befehl('duplikateZusammenfuehren', { behaltenId: g.behalten, duplikatIds: g.loeschbar, beschreibungenVerbinden: true });
    }
    await sucheDuplikate();
  } catch (x) { $('dupl-hinweis').textContent = x.message; }
});

async function zeigeSerie(id) {
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/serien/${encodeURIComponent(id)}`);
  zeigeListe({ aufnahmen: d.aufnahmen }, `Serie · ${d.aufnahmen.length} Aufnahmen`);
}

// --- Stammbaum -------------------------------------------------------------
// Der Server liefert das Geflecht aus dem Kern (Haushalte je Band, die
// Elternhäuser jeder Person); hier wird es als SVG gesetzt: ein Band je
// Generation, Haushalte nebeneinander, Äste von den Elternhäusern zu den
// Kindern. Ein Klick auf eine Person rückt sie in die Mitte.

const svgNs = 'http://www.w3.org/2000/svg';
const svgEl = (tag, attrs = {}, text) => {
  const e = document.createElementNS(svgNs, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  if (text !== undefined) e.textContent = text;
  return e;
};
const jahr = (iso) => (iso ? String(new Date(iso).getFullYear()) : '');
const lebensjahre = (p) => (p.geburt || p.tod ? `${jahr(p.geburt) || '?'} – ${p.tod ? jahr(p.tod) : ''}`.replace(/ – $/, p.tod ? '' : ' –') : '');

let baumZoomWert = 1;
$('baum-zoom').addEventListener('input', () => { baumZoomWert = Number($('baum-zoom').value); const svg = $('baum-flaeche').querySelector('svg'); if (svg) { svg.setAttribute('width', svg.dataset.breite * baumZoomWert); svg.setAttribute('height', svg.dataset.hoehe * baumZoomWert); } });
$('baum-person').addEventListener('change', () => { location.hash = `#/stammbaum/${encodeURIComponent($('baum-person').value)}`; });

async function zeigeStammbaum(fokus) {
  markiereNav('stammbaum');
  zeigeBereich(['stammbaum']);
  $('baum-hinweis').textContent = '';
  const d = await api(`/api/v1/stammbaum${fokus ? `?fokus=${encodeURIComponent(fokus)}` : ''}`);
  const wahl = $('baum-person');
  wahl.replaceChildren();
  for (const p of [...d.personen].sort((a, b) => a.name.localeCompare(b.name))) {
    const o = el('option', null, p.verwandt ? p.name : `${p.name} (ohne Verwandtschaft)`);
    o.value = p.id;
    wahl.append(o);
  }
  wahl.value = d.fokus || '';
  $('baum-flaeche').replaceChildren();
  if (!d.fokus) { $('baum-hinweis').textContent = 'Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.'; return; }
  const hinweise = [];
  if (d.haushalte.length === 1 && d.haushalte[0].personen.length === 1) hinweise.push('Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.');
  if (d.verschwiegen) hinweise.push(`${d.verschwiegen} Haushalte passen nicht mehr ins Bild.`);
  $('baum-hinweis').textContent = hinweise.join(' ');
  $('baum-flaeche').append(baumSvg(d));
}

function baumSvg(d) {
  const nachId = Object.fromEntries(d.personen.map((p) => [p.id, p]));
  const kB = 118, kH = 140, abstand = 10, hausAbstand = 36, bandH = 200, rand = 24;
  const baender = [...new Set(d.haushalte.map((h) => h.band))].sort((a, b) => a - b);
  // Breite je Band, dann alles auf die breiteste Zeile mittig.
  const breiteVon = (h) => h.personen.length * kB + (h.personen.length - 1) * abstand;
  const bandBreite = {};
  for (const b of baender) bandBreite[b] = d.haushalte.filter((h) => h.band === b).reduce((s, h, i) => s + breiteVon(h) + (i ? hausAbstand : 0), 0);
  const gesamt = Math.max(...Object.values(bandBreite)) + 2 * rand;
  const hoehe = baender.length * bandH + 2 * rand;
  const svg = svgEl('svg', { viewBox: `0 0 ${gesamt} ${hoehe}`, width: gesamt * baumZoomWert, height: hoehe * baumZoomWert });
  svg.dataset.breite = gesamt;
  svg.dataset.hoehe = hoehe;
  const defs = svgEl('defs');
  svg.append(defs);
  const lage = {}; // personId -> {x, y, mitte}
  const hausLage = {}; // haushaltId -> {mitte, unten, oben}
  baender.forEach((b, zeile) => {
    const y = rand + zeile * bandH + 20;
    let x = (gesamt - bandBreite[b]) / 2;
    for (const h of d.haushalte.filter((x) => x.band === b)) {
      const links = x;
      h.personen.forEach((id, i) => {
        const px = x + i * (kB + abstand);
        lage[id] = { x: px, y, mitte: px + kB / 2 };
        if (i > 0) svg.append(svgEl('line', { class: 'baum-paar', x1: px - abstand, y1: y + 46, x2: px, y2: y + 46 }));
      });
      const breite = breiteVon(h);
      hausLage[h.id] = { mitte: links + breite / 2, unten: y + kH, oben: y };
      x += breite + hausAbstand;
    }
  });
  // Äste: vom Elternhaus (unten) orthogonal zur Person (oben).
  for (const [kind, haeuser] of Object.entries(d.elternhaeuser)) {
    const k = lage[kind];
    if (!k) continue;
    for (const hid of haeuser) {
      const h = hausLage[hid];
      if (!h) continue;
      const mitteY = (h.unten + k.y) / 2;
      svg.append(svgEl('path', { class: 'baum-kante', d: `M${h.mitte},${h.unten} V${mitteY} H${k.mitte} V${k.y}` }));
    }
  }
  // Schilder.
  let n = 0;
  for (const [id, l] of Object.entries(lage)) {
    const p = nachId[id] || { name: '?' };
    const g = svgEl('g', { class: `baum-karte${id === d.fokus ? ' fokus' : ''}`, transform: `translate(${l.x},${l.y})` });
    g.append(svgEl('rect', { width: kB, height: kH, rx: 12 }));
    g.append(svgEl('circle', { class: 'rahmen', cx: kB / 2, cy: 46, r: 32 }));
    if (p.bild) {
      const cid = `k${n++}`;
      const clip = svgEl('clipPath', { id: cid });
      clip.append(svgEl('circle', { cx: kB / 2, cy: 46, r: 30 }));
      defs.append(clip);
      g.append(svgEl('image', { href: `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}`, x: kB / 2 - 30, y: 16, width: 60, height: 60, preserveAspectRatio: 'xMidYMid slice', 'clip-path': `url(#${cid})` }));
    } else {
      g.append(svgEl('text', { class: 'initiale', x: kB / 2, y: 54 }, (p.name || '?').trim().charAt(0).toUpperCase()));
    }
    // Lange Namen auf zwei Zeilen, am letzten Leerzeichen vor der Grenze.
    const zeilen = [];
    let rest = p.name.trim();
    while (rest && zeilen.length < 2) {
      if (rest.length <= 16 || zeilen.length === 1) { zeilen.push(rest.length > 16 ? `${rest.slice(0, 15)}…` : rest); break; }
      const schnitt = rest.lastIndexOf(' ', 16);
      if (schnitt < 4) { zeilen.push(`${rest.slice(0, 15)}…`); break; }
      zeilen.push(rest.slice(0, schnitt));
      rest = rest.slice(schnitt + 1);
    }
    const titel = svgEl('title');
    titel.textContent = p.name;
    g.append(titel);
    zeilen.forEach((z, i) => g.append(svgEl('text', { x: kB / 2, y: 98 + i * 14 }, z)));
    g.append(svgEl('text', { class: 'jahre', x: kB / 2, y: 98 + zeilen.length * 14 }, lebensjahre(p)));
    if (d.weitereOben.includes(id)) g.append(svgEl('text', { class: 'baum-pfeil', x: kB / 2, y: -6 }, '▲'));
    if (d.weitereUnten.includes(id)) g.append(svgEl('text', { class: 'baum-pfeil', x: kB / 2, y: kH + 14 }, '▼'));
    g.addEventListener('click', () => { location.hash = `#/stammbaum/${encodeURIComponent(id)}`; });
    svg.append(g);
  }
  return svg;
}

async function zeigePersonen() {
  markiereNav('personen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = 'Personen';
  $('karten').replaceChildren();
  const d = await api('/api/v1/personen');
  if (d.personen.length === 0) $('karten').append(el('p', 'leise', 'Noch keine Personen.'));
  for (const p of d.personen) {
    const bild = p.bild ? `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}` : null;
    const k = karte(bild, p.name, `${p.anzahl} Aufnahmen`, `#/personen/${encodeURIComponent(p.id)}`);
    k.classList.add('person');
    $('karten').append(k);
  }
}

async function zeigePerson(id) {
  markiereNav('personen');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/personen/${encodeURIComponent(id)}`);
  zeigeListe({ aufnahmen: d.aufnahmen }, d.person.name);
}

function zeigeSuche() {
  markiereNav('suche');
  zeigeBereich(['suche', 'raster']);
  if (!liste || !liste.suche) zeigeListe({ aufnahmen: [], suche: true });
  $('form-suche').text.focus();
}

$('form-suche').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const text = f.text.value.trim();
  if (!text) return;
  $('suche-hinweis').textContent = 'Sucht …';
  try {
    const q = new URLSearchParams({ text, art: f.art.value });
    const d = await api(`/api/v1/suche?${q}`);
    zeigeListe({ aufnahmen: d.aufnahmen, suche: true });
    $('suche-hinweis').textContent = d.aufnahmen.length ? '' : 'Nichts gefunden.';
  } catch (x) {
    $('suche-hinweis').textContent = x.status === 404
      ? 'Der Server hat kein Modell für die Bildsuche – suche nach Text.'
      : x.message;
  }
});

async function zeigeKonto() {
  markiereNav('konto');
  zeigeBereich(['konto']);
  const k = await api('/api/v1/konto');
  $('konto-wer').textContent = `${k.name}${k.verwalter ? ' · Verwalter' : ''}${k.totp ? ' · TOTP eingerichtet' : ''}`;
  $('passwort-code-feld').hidden = !k.totp;
  zeigeFassung($('konto-fassung'));
  $('verwaltung').hidden = !k.verwalter;
  if (k.verwalter) zeigeVerwaltung().catch((x) => { $('server-stand').replaceChildren(el('li', null, x.message)); });
  const g = await api('/api/v1/geraete');
  const ul = $('geraete');
  ul.replaceChildren();
  for (const x of g.geraete) {
    const li = el('li');
    const dieses = x.id === sitzung.geraet;
    li.append(el('span', null, `${x.name}${dieses ? ' (dieser Browser)' : ''} · zuletzt ${datumZeit.format(new Date(x.zuletzt))}${x.adresse ? ' · ' + x.adresse : ''}`));
    const b = el('button', null, dieses ? 'Abmelden' : 'Gerät abmelden');
    b.type = 'button';
    b.addEventListener('click', async () => {
      if (dieses) return abmelden();
      if (!confirm(`„${x.name}“ abmelden?`)) return;
      try { await api(`/api/v1/geraete/${encodeURIComponent(x.id)}`, { methode: 'DELETE' }); li.remove(); } catch (y) { alert(y.message); }
    });
    li.append(b);
    ul.append(li);
  }
}

$('form-passwort').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const m = $('passwort-meldung');
  if (f.neu.value !== f.neu2.value) { m.textContent = 'Die neuen Passwörter stimmen nicht überein.'; return; }
  try {
    await api('/api/v1/konto/passwort', {
      methode: 'POST',
      json: {
        alt: f.alt.value, neu: f.neu.value,
        ...(f.code.value ? { code: f.code.value.trim() } : {}),
        andereAbmelden: f.andere.checked,
      },
    });
    f.reset();
    m.textContent = 'Passwort geändert.';
  } catch (x) { m.textContent = x.message; }
});

async function zeigeFassung(ziel) {
  try {
    const z = await api('/api/v1/zustand');
    ziel.textContent = `Server ${z.fassung || '?'}${z.commit ? ' (' + z.commit + ')' : ''} · Protokoll ${z.protokoll}`;
  } catch (_) { /* egal */ }
}
zeigeFassung($('anmeldung-fassung'));

// --- Karte -----------------------------------------------------------------
//
// Leaflet aus dem eigenen Bündel (web/leaflet, BSD-2), Kacheln von
// OpenStreetMap. Die Punkte rechnet der Server mit derselben Regel wie das
// Telefon (kartengruppen); bei jedem Verschieben oder Zoomen neu.

let leafletKarte = null;
let karteGruppe = null;  // die zuletzt angetippte Gruppe, für #/karte/gruppe
let karteMarker = null;
let karteLauf = 0;

async function zeigeKarte() {
  markiereNav('karte');
  zeigeBereich(['karte']);
  if (!leafletKarte) {
    leafletKarte = L.map('karte', { worldCopyJump: true }).setView([51, 10], 5);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    }).addTo(leafletKarte);
    karteMarker = L.layerGroup().addTo(leafletKarte);
    leafletKarte.on('moveend', () => ladeOrte());
    await ladeOrte(true);
  } else {
    setTimeout(() => leafletKarte.invalidateSize(), 50);
  }
}

async function ladeOrte(zentrieren = false) {
  const lauf = ++karteLauf;
  const d = await api(`/api/v1/orte?zoom=${Math.round(leafletKarte.getZoom())}`);
  if (lauf !== karteLauf) return;
  karteMarker.clearLayers();
  const punkte = [];
  for (const g of d.gruppen) {
    const icon = L.divIcon({ className: '', html: `<div class="punkt${g.anzahl > 99 ? ' gross' : ''}">${g.anzahl}</div>`, iconSize: [36, 36] });
    const m = L.marker([g.breite, g.laenge], { icon });
    m.on('click', async () => {
      if (g.anzahl > 1 && leafletKarte.getZoom() < 17) { leafletKarte.setView([g.breite, g.laenge], leafletKarte.getZoom() + 2); return; }
      const r = await api('/api/v1/aufnahmen/liste', { methode: 'POST', json: { ids: g.ids } });
      karteGruppe = { aufnahmen: r.aufnahmen, titel: `${g.anzahl} Aufnahme${g.anzahl === 1 ? '' : 'n'} an diesem Ort` };
      location.hash = '#/karte/gruppe';
    });
    m.addTo(karteMarker);
    punkte.push([g.breite, g.laenge]);
  }
  if (zentrieren && punkte.length) leafletKarte.fitBounds(punkte, { padding: [30, 30], maxZoom: 12 });
}

// --- Verwaltung (nur Verwalter) -------------------------------------------

const gb = (b) => `${(b / 1073741824).toFixed(1)} GB`;
async function zeigeVerwaltung() {
  const ul = $('server-stand');
  ul.replaceChildren();
  const zeile = (t) => { const li = el('li'); li.append(el('span', null, t)); ul.append(li); };
  try {
    const sp = await api('/api/v1/speicher');
    zeile(`Speicher: ${gb(sp.frei)} frei von ${gb(sp.gesamt)}${sp.stufe !== 'ok' ? ' – ' + sp.stufe : ''}`);
  } catch (_) { /* kein Speicherwächter */ }
  try {
    const sv = await api('/api/v1/sicherung');
    zeile(`Sicherung: ${sv.stufe}${sv.letzterErfolg ? ' · zuletzt ' + datumZeit.format(new Date(sv.letzterErfolg)) : ''}${sv.naechster ? ' · nächste ' + datumZeit.format(new Date(sv.naechster)) : ''}${sv.fehler ? ' · ' + sv.fehler : ''}`);
    $('sicherung-jetzt').hidden = sv.stufe === 'aus' || sv.stufe === 'nichtEingerichtet';
  } catch (_) { $('sicherung-jetzt').hidden = true; }
  try {
    const a = await api('/api/v1/auswertung');
    zeile(a.laeuft && a.stand ? `Auswertung läuft: ${a.stand.stufe} (${a.stand.stufeNummer}/${a.stand.stufenGesamt}), ${a.stand.erledigt} von ${a.stand.gesamt}` : 'Auswertung: nichts offen');
  } catch (_) { /* ohne Modelle */ }
  const kl = $('konten');
  kl.replaceChildren();
  const d = await api('/api/v1/konten');
  for (const k of d.konten) {
    const li = el('li');
    li.append(el('span', null, `${k.name}${k.verwalter ? ' · Verwalter' : ''}${k.totp ? ' · TOTP' : ''}${k.gesperrt ? ' · gesperrt' : ''} · ${k.geraete} Gerät${k.geraete === 1 ? '' : 'e'}${k.du ? ' · du' : ''}`));
    const kn = el('span');
    if (k.gesperrt) { const b = el('button', null, 'Entsperren'); b.type = 'button'; b.addEventListener('click', async () => { await api(`/api/v1/konten/${encodeURIComponent(k.id)}/entsperren`, { methode: 'POST', json: {} }); zeigeVerwaltung(); }); kn.append(b); }
    if (!k.du) { const b = el('button', null, 'Entfernen'); b.type = 'button'; b.addEventListener('click', async () => { if (!confirm(`„${k.name}“ entfernen? Die Bibliothek bleibt auf dem Server liegen.`)) return; try { await api(`/api/v1/konten/${encodeURIComponent(k.id)}`, { methode: 'DELETE' }); zeigeVerwaltung(); } catch (x) { alert(x.message); } }); kn.append(b); }
    li.append(kn);
    kl.append(li);
  }
}
$('auswertung-anstossen').addEventListener('click', async () => { try { await api('/api/v1/auswertung', { methode: 'POST', json: {} }); zeigeVerwaltung(); } catch (x) { alert(x.message); } });
$('sicherung-jetzt').addEventListener('click', async () => { try { await api('/api/v1/sicherung/jetzt', { methode: 'POST', json: {} }); $('ende').textContent = ''; zeigeVerwaltung(); } catch (x) { alert(x.message); } });
$('form-konto-neu').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    await api('/api/v1/konten', { methode: 'POST', json: { name: f.name.value.trim(), passwort: f.passwort.value, verwalter: f.verwalter.checked } });
    f.reset();
    zeigeVerwaltung();
  } catch (x) { alert(x.message); }
});

// --- Auswahl ---------------------------------------------------------------

let auswahlModus = false;
const auswahl = new Set();

function schalteAuswahl(id, k) {
  if (auswahl.has(id)) auswahl.delete(id); else auswahl.add(id);
  k.classList.toggle('gewaehlt', auswahl.has(id));
  zeigeAuswahl();
}

function zeigeAuswahl() {
  const n = auswahl.size;
  $('auswahlleiste').hidden = n === 0;
  $('auswahl-anzahl').textContent = `${n} ausgewählt`;
  $('auswaehlen').classList.toggle('aktiv', auswahlModus);
  document.body.classList.toggle('mit-leiste', n > 0);
}

function auswahlAufheben() {
  auswahl.clear();
  auswahlModus = false;
  for (const k of $('raster').querySelectorAll('.kachel.gewaehlt')) k.classList.remove('gewaehlt');
  zeigeAuswahl();
}

$('auswaehlen').addEventListener('click', () => { auswahlModus = !auswahlModus; if (!auswahlModus) auswahlAufheben(); else zeigeAuswahl(); });
$('auswahl-zu').addEventListener('click', auswahlAufheben);

const gewaehlte = () => liste.aufnahmen.filter((a) => auswahl.has(a.id));

$('auswahl-favorit').addEventListener('click', async () => {
  const g = gewaehlte();
  const alle = g.every((a) => a.favorit);
  try {
    await befehl('favoritSetzen', { ids: g.map((a) => a.id), favorit: !alle });
    for (const a of g) a.favorit = !alle;
    neuZeichnen();
  } catch (x) { alert(x.message); }
});

$('auswahl-laden').addEventListener('click', () => {
  // Nacheinander, damit der Browser jedes als Datei anbietet.
  let i = 0;
  const naechste = () => {
    const a = gewaehlte()[i++];
    if (!a) return;
    const l = el('a');
    l.href = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/original`;
    l.download = a.name || '';
    document.body.append(l);
    l.click();
    l.remove();
    setTimeout(naechste, 400);
  };
  naechste();
});

$('auswahl-papierkorb').addEventListener('click', async () => {
  const g = gewaehlte();
  if (!confirm(`${g.length} Aufnahme${g.length === 1 ? '' : 'n'} in den Papierkorb legen? Sie verschwinden überall – zurückholen geht am Rechner.`)) return;
  try {
    await befehl('inDenPapierkorb', { ids: g.map((a) => a.id) });
    const weg = new Set(g.map((a) => a.id));
    liste.aufnahmen = liste.aufnahmen.filter((a) => !weg.has(a.id));
    zeitleiste.geladen = zeitleiste.geladen.filter((a) => !weg.has(a.id));
    auswahlAufheben();
    neuZeichnen();
  } catch (x) { alert(x.message); }
});

$('auswahl-zurueck').addEventListener('click', async () => {
  const g = gewaehlte();
  try {
    await befehl('ausDemPapierkorb', { ids: g.map((a) => a.id) });
    const weg = new Set(g.map((a) => a.id));
    liste.aufnahmen = liste.aufnahmen.filter((a) => !weg.has(a.id));
    zeitleiste.leeren();
    auswahlAufheben();
    neuZeichnen();
    $('ende').textContent = `${g.length} zurückgeholt`;
  } catch (x) { alert(x.message); }
});

$('auswahl-album').addEventListener('click', async () => {
  const d = await api('/api/v1/alben');
  const ul = $('album-liste');
  ul.replaceChildren();
  for (const a of d.alben) {
    const li = el('li');
    const lab = el('label');
    const r = el('input'); r.type = 'radio'; r.name = 'album'; r.value = a.id;
    lab.append(r, document.createTextNode(` ${a.name} (${a.anzahl})`));
    li.append(lab);
    ul.append(li);
  }
  $('form-album').neu.value = '';
  $('album-dialog').showModal();
});
$('album-abbrechen').addEventListener('click', () => $('album-dialog').close());
$('form-album').addEventListener('submit', async (e) => {
  const f = e.target;
  const g = gewaehlte();
  const neu = f.neu.value.trim();
  const gewaehlt = f.album && f.album.value;
  if (!neu && !gewaehlt) { e.preventDefault(); return; }
  try {
    let albumId = gewaehlt;
    let name = gewaehlt ? [...f.album].find((r) => r.checked)?.parentElement.textContent.trim() : neu;
    if (neu) {
      albumId = crypto.randomUUID();
      name = neu;
      await befehl('albumAnlegen', { albumId, name, angelegtAm: new Date().toISOString() });
    }
    await befehl('albumFuellen', { albumId, ids: g.map((a) => a.id) });
    auswahlAufheben();
    $('ende').textContent = `${g.length} im Album „${name}“`;
  } catch (x) { alert(x.message); }
});

function neuZeichnen() {
  if (!liste) return;
  const alt = liste;
  zeigeListe({ aufnahmen: alt.aufnahmen, nachTagen: alt.nachTagen, mehr: alt.mehr, suche: alt.suche, papierkorb: alt.papierkorb }, $('raster-titel').hidden ? null : $('raster-titel').textContent);
}

// --- Betrachter ------------------------------------------------------------

let offen = -1;

function oeffne(i) {
  if (!liste || i < 0 || i >= liste.aufnahmen.length) return;
  offen = i;
  const a = liste.aufnahmen[i];
  const bild = $('bild'), video = $('video');
  video.pause();
  video.removeAttribute('src');
  video.load();
  if (a.art === 'video') {
    bild.hidden = true;
    video.hidden = false;
    video.src = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/original`;
  } else {
    video.hidden = true;
    bild.hidden = false;
    bild.src = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/vorschau`;
  }
  $('angaben').textContent = `${datumZeit.format(new Date(a.aufgenommen))} · ${a.name}`;
  $('favorit').textContent = a.favorit ? '♥' : '♡';
  $('laden').href = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/original`;
  $('laden').download = a.name || '';
  $('betrachter').hidden = false;
  zeigeAngaben();
  if (i >= liste.aufnahmen.length - 20) ladeMehr();
}

// --- Angaben zur Aufnahme --------------------------------------------------
// Dieselben Zeilen wie die Info-Ansicht des Rechners: Datum, Datei, Kamera,
// Ort, Personen, Schlagwörter, Alben, Beschreibung, Bewertung, Serie.

let angabenOffen = false;
const landname = (() => { try { return new Intl.DisplayNames(undefined, { type: 'region' }); } catch (_) { return null; } })();
const land = (code) => (code && /^[A-Z]{2}$/.test(code) && landname ? landname.of(code) : code);
const belichtung = (t) => (t >= 1 ? `${t} s` : `1/${Math.round(1 / t)} s`);

function reihe(zeichen, haupt, neben) {
  const r = el('div', 'reihe');
  const inhalt = el('div', 'inhalt');
  if (haupt instanceof Node) inhalt.append(haupt); else inhalt.append(el('div', 'haupt', haupt));
  if (neben) { if (neben instanceof Node) inhalt.append(neben); else inhalt.append(el('div', 'neben', neben)); }
  r.append(el('span', 'zeichen', zeichen), inhalt);
  return r;
}

function verweise(liste, ziel) {
  const box = el('div');
  for (const x of liste) {
    const a = el('a', 'marke', x.name);
    a.href = `${ziel}/${encodeURIComponent(x.id)}`;
    a.addEventListener('click', schliesse);
    box.append(a);
  }
  return box;
}

async function zeigeAngaben() {
  const a = liste && liste.aufnahmen[offen];
  const feld = $('angaben-feld');
  if (!a || !angabenOffen) return;
  feld.replaceChildren(el('p', 'neben', 'Lade …'));
  let d;
  try { d = await api(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/angaben`); } catch (x) { feld.replaceChildren(el('p', 'fehler', x.message)); return; }
  if (!liste || liste.aufnahmen[offen] !== a) return; // inzwischen weitergeblättert
  const teile = [];
  teile.push(el('h3', null, 'Angaben'));
  teile.push(reihe('📅', datumZeit.format(new Date(d.aufgenommen)), d.datumGeschaetzt ? 'Datum geschätzt' : null));
  const datei = [d.breite && d.hoehe ? `${d.breite} × ${d.hoehe}` : '', d.bytes ? groesse(d.bytes) : '', d.format ? d.format.toUpperCase() : '', d.dauer ? `${Math.round(d.dauer)} s` : '', d.bearbeitet ? 'bearbeitet' : ''].filter(Boolean).join(' · ');
  teile.push(reihe('🖼', d.name, datei));
  const k = d.kamera;
  if (k.modell || k.hersteller) {
    const modell = k.modell && k.hersteller && k.modell.toLowerCase().startsWith(k.hersteller.toLowerCase()) ? k.modell : [k.hersteller, k.modell].filter(Boolean).join(' ');
    const werte = [k.brennweite ? `${k.brennweite} mm` : '', k.blende ? `f/${k.blende}` : '', k.belichtung ? belichtung(k.belichtung) : '', k.iso ? `ISO ${k.iso}` : ''].filter(Boolean).join(' · ');
    teile.push(reihe('📷', modell, [k.objektiv, werte].filter(Boolean).join('\n')));
  }
  if (d.ort) {
    const name = [d.ort.stadt, d.ort.region, land(d.ort.land)].filter(Boolean).join(', ');
    teile.push(reihe('📍', name || 'Standort bekannt', `${d.ort.breite.toFixed(5)}, ${d.ort.laenge.toFixed(5)}${d.ort.geerbt ? ' · vom Nachbarfoto übernommen' : ''}`));
  }
  if (d.personen.length) teile.push(reihe('👤', verweise(d.personen, '#/personen')));
  if (d.schlagwoerter.length) { const box = el('div'); for (const t of d.schlagwoerter) box.append(el('span', 'marke', t.name)); teile.push(reihe('🏷', box)); }
  if (d.alben.length) teile.push(reihe('📚', verweise(d.alben, '#/alben')));
  // Beschreibung – änderbar, über denselben Befehl wie am Rechner.
  const text = el('textarea');
  text.value = d.beschreibung || '';
  text.placeholder = 'Beschreibung';
  const speichern = el('button', 'speichern', 'Speichern');
  speichern.type = 'button';
  speichern.addEventListener('click', async () => {
    try { await befehl('beschreibungSetzen', { ids: [a.id], beschreibung: text.value }); speichern.textContent = 'Gespeichert'; } catch (x) { speichern.textContent = x.message; }
  });
  text.addEventListener('input', () => { speichern.textContent = 'Speichern'; });
  const beschr = el('div', 'beschreibung');
  beschr.append(text, speichern);
  teile.push(reihe('✎', beschr, d.kiBeschreibung ? `Automatisch: ${d.kiBeschreibung}` : null));
  // Bewertung
  const sterne = el('div', 'sterne');
  const male = (n) => { for (const [i, b] of [...sterne.children].entries()) b.classList.toggle('voll', i < n); };
  for (let i = 1; i <= 5; i++) {
    const b = el('button', null, '★');
    b.type = 'button';
    b.title = `${i} von 5`;
    b.addEventListener('click', async () => {
      const neu = d.bewertung === i ? 0 : i;
      try { await befehl('bewertungSetzen', { ids: [a.id], bewertung: neu }); d.bewertung = neu; a.bewertung = neu || undefined; male(neu); } catch (x) { feld.append(el('p', 'fehler', x.message)); }
    });
    sterne.append(b);
  }
  male(d.bewertung || 0);
  teile.push(reihe('☆', sterne));
  if (d.serie && d.serie.groesse > 1) {
    const v = el('a', null, `Serie mit ${d.serie.groesse} Aufnahmen`);
    v.href = `#/serie/${encodeURIComponent(d.serie.id)}`;
    v.addEventListener('click', schliesse);
    teile.push(reihe('⧉', v));
  }
  if (d.text) { const det = el('details'); det.append(el('summary', null, 'Erkannter Text'), el('pre', null, d.text)); teile.push(det); }
  if (d.transkript) { const det = el('details'); det.append(el('summary', null, 'Transkript'), el('pre', null, d.transkript)); teile.push(det); }
  teile.push(el('p', 'neben', `Importiert ${datumZeit.format(new Date(d.importiert))}`));
  feld.replaceChildren(...teile);
}

$('info').addEventListener('click', () => {
  angabenOffen = !angabenOffen;
  $('info').setAttribute('aria-pressed', String(angabenOffen));
  $('betrachter').classList.toggle('mit-angaben', angabenOffen);
  $('angaben-feld').hidden = !angabenOffen;
  zeigeAngaben();
});

function schliesse() {
  $('betrachter').hidden = true;
  $('video').pause();
  offen = -1;
}

$('zu').addEventListener('click', schliesse);
$('zurueck').addEventListener('click', () => oeffne(offen - 1));
$('vor').addEventListener('click', () => oeffne(offen + 1));
$('favorit').addEventListener('click', async () => {
  const a = liste && liste.aufnahmen[offen];
  if (!a) return;
  try {
    await befehl('favoritSetzen', { ids: [a.id], favorit: !a.favorit });
    a.favorit = !a.favorit;
    $('favorit').textContent = a.favorit ? '♥' : '♡';
    const k = $('raster').querySelector(`.kachel[data-index="${offen}"]`);
    if (k) {
      let h = k.querySelector('.herz');
      if (a.favorit && !h) k.append(el('span', 'herz', '♥'));
      if (!a.favorit && h) h.remove();
    }
  } catch (x) { $('angaben').textContent = x.message; }
});

document.addEventListener('keydown', (e) => {
  if (offen < 0) return;
  if (e.key === 'Escape') schliesse();
  else if (e.key === 'ArrowLeft') oeffne(offen - 1);
  else if (e.key === 'ArrowRight') oeffne(offen + 1);
});

// --- Wege ------------------------------------------------------------------

async function zeigeWeg() {
  if (!sitzung) return;
  schliesse();
  auswahlAufheben();
  const teile = location.hash.replace(/^#\/?/, '').split('/').map(decodeURIComponent);
  try {
    switch (teile[0]) {
      case 'suche': zeigeSuche(); break;
      case 'alben': await (teile[1] ? zeigeAlbum(teile[1]) : zeigeAlben()); break;
      case 'personen': await (teile[1] ? zeigePerson(teile[1]) : zeigePersonen()); break;
      case 'konto': await zeigeKonto(); break;
      case 'reisen': await (teile[1] ? zeigeReise(teile[1]) : zeigeReisen()); break;
      case 'statistik': await zeigeStatistik(); break;
      case 'stammbaum': await zeigeStammbaum(teile[1]); break;
      case 'duplikate': await zeigeDuplikate(); break;
      case 'serie': await zeigeSerie(teile[1]); break;
      case 'karte':
        if (teile[1] === 'gruppe' && karteGruppe) {
          markiereNav('karte');
          zeigeBereich(['raster']);
          zeigeListe({ aufnahmen: karteGruppe.aufnahmen }, karteGruppe.titel);
        } else {
          await zeigeKarte();
        }
        break;
      case 'papierkorb': await zeigePapierkorb(); break;
      default: await zeigeFotos();
    }
  } catch (x) {
    if (x.message !== 'nicht angemeldet') $('ende').textContent = x.message;
  }
}
window.addEventListener('hashchange', zeigeWeg);

async function starte() {
  sitzung = await api('/api/v1/web/sitzung');
  $('anmeldung').hidden = true;
  $('kopf').hidden = false;
  $('inhalt').hidden = false;
  await zeigeWeg();
}

starte().catch(() => zeigeAnmeldung());

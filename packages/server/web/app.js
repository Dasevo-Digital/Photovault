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
    const f = new Error(daten && daten.fehler ? t(daten.fehler) : t('Fehler {n}', { n: antwort.status }));
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
// „1 Aufnahme“, „3 Aufnahmen“ – wie auf dem Telefon.
const anzahlText = (n) => (n === 1 ? t('1 Aufnahme') : t('{n} Aufnahmen', { n }));
const miniaturUrl = (id) => `/api/v1/aufnahmen/${encodeURIComponent(id)}/miniatur`;
const datum = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'full' });
const datumZeit = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium', timeStyle: 'short' });
const monatJahr = new Intl.DateTimeFormat(GEBIET, { month: 'long', year: 'numeric' });
const tagKopf = new Intl.DateTimeFormat(GEBIET, { weekday: 'long', day: 'numeric', month: 'long' });

let sitzung = null;   // {name, verwalter, geraet}

// --- Ansichten -------------------------------------------------------------

function zeigeAnmeldung() {
  sitzung = null;
  $('kopf').hidden = true;
  $('nav').hidden = true;
  $('inhalt').hidden = true;
  $('anmeldung').hidden = false;
  $('form-anmelden').hidden = false;
  $('form-totp').hidden = true;
  auswahlAufheben();
}

function zeigeBereich(name) {
  for (const s of document.querySelectorAll('#inhalt > section')) s.hidden = true;
  $('ohne-namen').hidden = true;
  for (const b of name) $(`bereich-${b}`).hidden = false;
}

// --- Navigation ------------------------------------------------------------
//
// Wie in der Handy-App: vier Hauptbereiche, und was sonst dazugehört,
// gesammelt in der Bibliothek – in Gruppen, jedes mit eigener Farbe. Am
// breiten Bildschirm steht das alles in der Seitenleiste, am schmalen
// bleiben unten die vier Reiter und die Bibliothek ist eine eigene Seite.

const HAUPTBEREICHE = [
  { bereich: 'fotos', weg: '#/', text: 'Fotos', symbol: 'fotos' },
  { bereich: 'suche', weg: '#/suche', text: 'Suche', symbol: 'suche' },
  { bereich: 'alben', weg: '#/alben', text: 'Alben', symbol: 'alben' },
  { bereich: 'bibliothek', weg: '#/bibliothek', text: 'Bibliothek', symbol: 'bibliothek' },
];

// Dieselben Gruppen, Reihenfolge und Farben wie auf dem Telefon
// (apps/mobil/lib/seiten/bibliothek.dart).
const BIBLIOTHEK = [
  {
    titel: 'Entdecken',
    eintraege: [
      { bereich: 'favoriten', weg: '#/favoriten', text: 'Favoriten', symbol: 'favoriten', farbe: '#e5484d' },
      { bereich: 'personen', weg: '#/personen', text: 'Personen', symbol: 'personen', farbe: '#8e4ec6' },
      { bereich: 'karte', weg: '#/karte', text: 'Karte', symbol: 'karte', farbe: '#30a46c' },
      { bereich: 'reisen', weg: '#/reisen', text: 'Reisen', symbol: 'reisen', farbe: '#f76b15' },
      { bereich: 'stammbaum', weg: '#/stammbaum', text: 'Stammbaum', symbol: 'stammbaum', farbe: '#a18072' },
      { bereich: 'statistik', weg: '#/statistik', text: 'Statistik', symbol: 'statistik', farbe: '#0090ff' },
    ],
  },
  {
    titel: 'Verwalten',
    eintraege: [
      { bereich: 'duplikate', weg: '#/duplikate', text: 'Duplikate', symbol: 'duplikate', farbe: '#3e63dd' },
      { bereich: 'papierkorb', weg: '#/papierkorb', text: 'Papierkorb', symbol: 'papierkorb', farbe: '#8b8d98' },
      { bereich: 'einstellungen', weg: '#/einstellungen', text: 'Einstellungen', symbol: 'einstellungen', farbe: '#12a594' },
    ],
  },
];
const ZUR_BIBLIOTHEK = new Set(BIBLIOTHEK.flatMap((g) => g.eintraege.map((e) => e.bereich)));

const SVG_NS = 'http://www.w3.org/2000/svg';
function symbol(name) {
  const s = document.createElementNS(SVG_NS, 'svg');
  s.setAttribute('class', 'symbol');
  s.setAttribute('aria-hidden', 'true');
  const u = document.createElementNS(SVG_NS, 'use');
  u.setAttribute('href', `#i-${name}`);
  s.append(u);
  return s;
}

// Das farbige Feld mit dem Symbol eines Eintrags der Bibliothek.
function farbsymbol(e) {
  const f = el('span', 'farbsymbol');
  f.style.setProperty('--farbe', e.farbe);
  f.append(symbol(e.symbol));
  return f;
}

function baueNavigation() {
  const nav = $('nav');
  const haupt = el('div', 'nav-haupt');
  for (const e of HAUPTBEREICHE) {
    const a = el('a', e.bereich === 'bibliothek' ? 'nur-schmal' : null);
    a.href = e.weg;
    a.dataset.bereich = e.bereich;
    a.title = t(e.text);
    a.setAttribute('aria-label', t(e.text));
    a.append(el('span', 'nav-symbol'), el('span', 'nav-text', t(e.text)));
    a.firstChild.append(symbol(e.symbol));
    haupt.append(a);
  }
  const marke = el('a', 'nav-marke');
  marke.href = '#/';
  const bild = el('img');
  bild.src = 'symbol.png';
  bild.alt = '';
  marke.append(bild, el('span', null, 'Photo Vault'));
  nav.replaceChildren(marke, haupt);
  for (const g of BIBLIOTHEK) {
    const gruppe = el('div', 'nav-gruppe');
    gruppe.append(el('h2', null, t(g.titel)));
    for (const e of g.eintraege) {
      const a = el('a');
      a.href = e.weg;
      a.dataset.bereich = e.bereich;
      a.title = t(e.text);
      a.setAttribute('aria-label', t(e.text));
      a.append(farbsymbol(e), el('span', 'nav-text', t(e.text)));
      gruppe.append(a);
    }
    nav.append(gruppe);
  }
  // Unten die Pinnnadel: hält die Leiste offen (nur am breiten Bildschirm).
  const fuss = el('div', 'nav-fuss');
  const nadel = el('button', 'nav-nadel');
  nadel.type = 'button';
  nadel.id = 'nav-nadel';
  nadel.append(el('span', 'nav-symbol'), el('span', 'nav-text'));
  nadel.firstChild.append(symbol('pinnen'));
  fuss.append(nadel);
  nav.append(fuss);
  // Die Bibliothek als Seite: dieselben Gruppen als Kacheln.
  const seite = $('bib-gruppen');
  seite.replaceChildren();
  for (const g of BIBLIOTHEK) {
    const abschnitt = el('div', 'bib-abschnitt');
    abschnitt.append(el('div', 'bib-kopf'));
    abschnitt.firstChild.append(el('h2', null, t(g.titel)));
    const liste = el('div', g.titel === 'Verwalten' ? 'bib-liste' : 'bib-kacheln');
    for (const e of g.eintraege) {
      const a = el('a', 'bib-eintrag');
      a.href = e.weg;
      a.append(farbsymbol(e), el('span', 'nav-text', t(e.text)));
      if (g.titel === 'Verwalten') a.append(symbol('weiter'));
      liste.append(a);
    }
    abschnitt.append(liste);
    seite.append(abschnitt);
  }
}
baueNavigation();

// Die Seitenleiste am breiten Bildschirm: sonst eine schmale Leiste aus
// Symbolen, die sich öffnet, sobald die Maus darauf kommt (oder ein
// Eintrag den Fokus hat) – über dem Inhalt, ohne ihn zu verschieben. Die
// Pinnnadel hält sie offen; das merkt sich dieser Browser.
const NAV_MERKER = 'pv-nav-fixiert';
function setzeNavFixiert(fixiert) {
  document.body.classList.toggle('nav-fixiert', fixiert);
  const nadel = $('nav-nadel');
  const text = fixiert ? t('Fixierung lösen') : t('Leiste fixieren');
  nadel.setAttribute('aria-pressed', String(fixiert));
  nadel.title = text;
  nadel.querySelector('.nav-text').textContent = text;
  // Die Karte misst ihre Fläche nur beim Anlegen nach.
  setTimeout(() => { if (typeof leafletKarte !== 'undefined' && leafletKarte) leafletKarte.invalidateSize(); }, 250);
}
{
  let fixiert = false;
  try {
    fixiert = localStorage.getItem(NAV_MERKER) === '1';
    localStorage.removeItem('pv-nav-schmal');
  } catch (_) { /* privat */ }
  setzeNavFixiert(fixiert);
}
$('nav-nadel').addEventListener('click', () => {
  const fixiert = !document.body.classList.contains('nav-fixiert');
  setzeNavFixiert(fixiert);
  // Gelöst: gleich zuklappen, nicht erst, wenn die Maus geht.
  if (!fixiert) $('nav-nadel').blur();
  try { localStorage.setItem(NAV_MERKER, fixiert ? '1' : '0'); } catch (_) { /* privat */ }
});

const BEREICHSTITEL = Object.fromEntries([
  ...HAUPTBEREICHE.map((e) => [e.bereich, e.text]),
  ...BIBLIOTHEK.flatMap((g) => g.eintraege.map((e) => [e.bereich, e.text])),
  ['konto', 'Konto'],
]);

function markiereNav(bereich) {
  for (const a of document.querySelectorAll('#nav a[data-bereich], #konto-knopf')) {
    const b = a.dataset.bereich;
    a.classList.toggle('aktiv', b === bereich || (b === 'bibliothek' && ZUR_BIBLIOTHEK.has(bereich)));
  }
  $('kopf-titel').textContent = BEREICHSTITEL[bereich] ? t(BEREICHSTITEL[bereich]) : '';
}

// Die Bibliothek als Seite – vor allem für den schmalen Bildschirm, wo die
// Seitenleiste fehlt: oben die Personen, darunter die Gruppen.
async function zeigeBibliothek() {
  markiereNav('bibliothek');
  zeigeBereich(['bibliothek']);
  const streifen = $('bib-personen');
  const d = await api('/api/v1/personen');
  const benannt = d.personen.filter((p) => (p.name || '').trim());
  streifen.replaceChildren();
  if (benannt.length === 0) { streifen.append(el('p', 'leise', t('Noch keine Personen.'))); return; }
  for (const p of benannt) {
    const a = el('a', 'bib-person');
    a.href = `#/personen/${encodeURIComponent(p.id)}`;
    const rund = el('span', 'bib-gesicht');
    if (p.bild) {
      const img = el('img');
      img.loading = 'lazy';
      img.alt = '';
      img.src = `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}`;
      rund.append(img);
    } else {
      rund.textContent = p.name.trim().charAt(0).toUpperCase();
    }
    a.append(rund, el('span', 'bib-name', p.name));
    streifen.append(a);
  }
}

// --- Anmeldung -------------------------------------------------------------

let vorgang = null;
function fehler(text) { $('fehler').textContent = text || ''; }

async function nachAnmeldung(d) {
  if (d.angemeldet) {
    fehler('');
    if (d.wiederherstellungscodes) {
      alert(`${t('Deine Wiederherstellungscodes – bitte sicher aufbewahren:')}\n\n${d.wiederherstellungscodes.join('\n')}`);
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
    ? t('Dieses Konto braucht einen zweiten Faktor.')
    : t('Gib den Code aus deiner Authenticator-App ein.');
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
// wie sie nachlädt (Zeitleiste, Favoriten). Der Betrachter läuft über die
// gerade gezeigte Liste.
//
// Gegliedert wird wie auf dem Telefon: ein Kopf je Monat, darunter je Tag
// das Datum mit dem Kreis, der den ganzen Tag wählt.

let liste = null;
let letzterTag = null;
let letzterMonat = null;

// Der Tag einer Aufnahme in der Zeit des Browsers – Schlüssel für die
// Tagesauswahl.
const tagVon = (a) => { const d = new Date(a.aufgenommen); return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`; };

// Ein gefülltes Zeichen für eine Kachel (Symbole m-… in index.html).
function kachelzeichen(name, klasse = '') {
  const s = symbol(name);
  s.setAttribute('class', `zeichen ${klasse}`.trim());
  s.firstChild.setAttribute('href', `#m-${name}`);
  return s;
}

// „m:ss“, ab einer Stunde „h:mm:ss“ – wie am Rechner.
function videodauer(sekunden) {
  const g = Math.round(sekunden);
  const h = Math.floor(g / 3600), m = Math.floor((g % 3600) / 60), s = String(g % 60).padStart(2, '0');
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`;
}

// Die Marken einer Kachel, dieselben wie am Rechner
// (asset_thumbnail_tile.dart) und auf dem Telefon (bilder.dart,
// Miniatur): Favorit oben links, Ort unten links, Videolänge oder Live
// unten rechts, Serie oder Dateiformat oben rechts.
function marken(k, a) {
  if (a.favorit) k.append(kachelzeichen('herz', 'herz'));
  if (a.ort) k.append(kachelzeichen('ort', 'ort'));
  if (a.art === 'video') {
    const v = el('span', 'unten-rechts');
    if (a.dauer != null) v.append(el('span', 'dauer', videodauer(a.dauer)));
    v.append(kachelzeichen('abspielen'));
    k.append(v);
  } else if (a.partner) {
    const v = el('span', 'unten-rechts');
    v.append(kachelzeichen('live'));
    k.append(v);
  }
  if (a.serie && a.serie.titel && a.serie.groesse > 1) {
    const s = el('span', 'schild');
    s.append(kachelzeichen('serie'), document.createTextNode(String(a.serie.groesse)));
    k.append(s);
  } else if (a.format) {
    k.append(el('span', 'schild', a.format));
  }
}

function kachel(a, index) {
  const k = el('button', 'kachel');
  k.type = 'button';
  k.dataset.index = index;
  const img = el('img');
  img.loading = 'lazy';
  img.decoding = 'async';
  img.alt = '';
  img.draggable = false;
  img.src = miniaturUrl(a.id);
  k.append(img);
  marken(k, a);
  if (auswahl.has(a.id)) k.classList.add('gewaehlt');
  k.addEventListener('click', () => {
    // Nach dem Ziehen kommt noch ein Klick – der gehört zum Ziehen.
    if (zieh.schlucke) { zieh.schlucke = false; return; }
    if (auswahlModus || auswahl.size) schalteAuswahl(a.id, k); else oeffne(index);
  });
  return k;
}

function tageskopf(a, tag) {
  const k = el('button', 'tageskopf');
  k.type = 'button';
  k.dataset.tag = tag;
  k.title = t('Ganzen Tag auswählen');
  k.append(el('span', 'tag', tagKopf.format(new Date(a.aufgenommen))), el('span', 'kreis'));
  k.addEventListener('click', () => schalteTag(tag));
  return k;
}

function haengeAn(aufnahmen) {
  // Erst sammeln, dann auf einmal einhängen: 200 einzelne Einfügungen in
  // die lebende Seite waren 200 Gelegenheiten, das Layout zu verwerfen.
  const raster = document.createDocumentFragment();
  for (const a of aufnahmen) {
    const tag = tagVon(a);
    if (liste.nachTagen) {
      const d = new Date(a.aufgenommen);
      const monat = `${d.getFullYear()}-${d.getMonth()}`;
      if (monat !== letzterMonat) {
        letzterMonat = monat;
        letzterTag = null;
        raster.append(el('h2', 'monat', monatJahr.format(d)));
      }
      if (tag !== letzterTag) {
        letzterTag = tag;
        const kopf = tageskopf(a, tag);
        liste.koepfe.set(tag, kopf);
        raster.append(kopf);
      }
    }
    if (!liste.tage.has(tag)) liste.tage.set(tag, []);
    liste.tage.get(tag).push(a.id);
    const k = kachel(a, liste.aufnahmen.length);
    liste.kacheln.push(k);
    raster.append(k);
    liste.aufnahmen.push(a);
  }
  $('raster').append(raster);
  if (liste.nachTagen) zeichneTage();
}

function zeigeListe(neu, titel) {
  liste = { aufnahmen: [], nachTagen: false, mehr: null, ...neu, aufnahmen: [], tage: new Map(), kacheln: [], koepfe: new Map() };
  $('erinnerungen').hidden = true;
  $('auswahl-papierkorb').hidden = !!liste.papierkorb;
  $('auswahl-zurueck').hidden = !liste.papierkorb;
  letzterTag = null;
  letzterMonat = null;
  $('raster').replaceChildren();
  $('raster-titel').hidden = !titel;
  $('raster-titel').textContent = titel || '';
  $('raster-kopf').replaceChildren(...(liste.kopf ? [liste.kopf] : []));
  $('raster-kopf').hidden = !liste.kopf;
  $('ende').textContent = '';
  haengeAn(neu.aufnahmen || []);
  if (!liste.mehr) $('ende').textContent = liste.aufnahmen.length ? anzahlText(liste.aufnahmen.length) : t('Keine Aufnahmen.');
}

async function ladeMehr() {
  if (!liste || !liste.mehr || liste.laedt) return;
  liste.laedt = true;
  try {
    const d = await liste.mehr();
    haengeAn(d.aufnahmen);
    if (!d.weiter) {
      liste.mehr = null;
      $('ende').textContent = liste.aufnahmen.length ? anzahlText(liste.aufnahmen.length) : t('Noch keine Aufnahmen.');
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

// Die Favoriten wie in der Bibliothek des Telefons: nach Tagen gegliedert,
// seitenweise wie die Zeitleiste.
const favoriten = {
  weiter: undefined,
  async mehr() {
    const q = new URLSearchParams({ anzahl: '200', favoriten: '1' });
    if (this.weiter) q.set('nach', this.weiter);
    const d = await api(`/api/v1/aufnahmen?${q}`);
    this.weiter = d.weiter;
    return d;
  },
};

async function zeigeFavoriten() {
  markiereNav('favoriten');
  zeigeBereich(['raster']);
  favoriten.weiter = undefined;
  zeigeListe({ aufnahmen: [], nachTagen: true, favoriten: true, mehr: () => favoriten.mehr() }, t('Favoriten'));
  await ladeMehr();
  if (liste.favoriten && liste.aufnahmen.length === 0 && !liste.mehr) $('ende').textContent = t('Noch keine Favoriten.');
}

// „Vor x Jahren“ über der Zeitleiste – ein Kärtchen je Jahrgang.
const monate = new Intl.DateTimeFormat(GEBIET, { month: 'long' });
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
    const text = d.art === 'tag'
      ? (g.jahreHer === 1 ? t('Vor einem Jahr') : t('Vor {n} Jahren', { n: g.jahreHer }))
      : (g.jahreHer === 1 ? t('{monat} vor einem Jahr', { monat }) : t('{monat} vor {n} Jahren', { monat, n: g.jahreHer }));
    k.append(img, el('span', null, `${text} · ${g.aufnahmen.length}`));
    k.addEventListener('click', () => { zeigeBereich(['raster']); $('erinnerungen').hidden = true; zeigeListe({ aufnahmen: g.aufnahmen }, text); oeffne(0); });
    karten.append(k);
  }
}

async function zeigePapierkorb() {
  markiereNav('papierkorb');
  zeigeBereich(['raster']);
  const d = await api('/api/v1/papierkorb');
  zeigeListe({ aufnahmen: d.aufnahmen, papierkorb: true }, t('Papierkorb'));
  if (d.aufnahmen.length === 0) $('ende').textContent = t('Der Papierkorb ist leer.');
}

function karte(bildUrl, titel, untertitel, ziel, { zusatz, kennzeichen } = {}) {
  const a = el('a', 'albumkarte');
  a.href = ziel;
  const bild = el('div', 'albumbild');
  if (bildUrl) { const img = el('img'); img.loading = 'lazy'; img.alt = ''; img.src = bildUrl; bild.append(img); }
  if (kennzeichen) bild.append(el('span', 'kennzeichen', kennzeichen));
  a.append(bild, el('div', 'titel', titel), el('div', 'leise klein', untertitel));
  if (zusatz) a.append(el('div', 'leise klein', zusatz));
  return a;
}

async function zeigeAlben() {
  markiereNav('alben');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Alben');
  $('karten').replaceChildren();
  const d = await api('/api/v1/alben');
  if (d.alben.length === 0) $('karten').append(el('p', 'leise', t('Noch keine Alben.')));
  for (const a of d.alben) {
    $('karten').append(karte(a.titelbild ? miniaturUrl(a.titelbild) : null, a.name, anzahlText(a.anzahl), `#/alben/${encodeURIComponent(a.id)}`));
  }
}

async function zeigeAlbum(id) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/alben/${encodeURIComponent(id)}`);
  const kopf = el('div', 'reisekopf');
  const teilen = el('button', 'knopf', t('Als Link teilen …'));
  teilen.type = 'button';
  teilen.addEventListener('click', () => oeffneLinkDialog({ album: d.album.id }, d.album.name));
  kopf.append(teilen);
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, d.album.name);
}

// --- Als Link teilen (Issue #106) ------------------------------------------
//
// Ein Album oder eine Auswahl als Link nach aussen: mit Ablauf, auf Wunsch
// mit Passwort, Originale nur, wenn erlaubt. Wer den Link öffnet, sieht
// /teilen/<link> – Bilder ohne Metadaten, sonst nichts.

let linkFall = null;

function oeffneLinkDialog(fall, titel) {
  linkFall = fall;
  const f = $('form-link');
  f.reset();
  f.titel.value = titel || '';
  $('link-anlegen').hidden = false;
  $('link-fertig').hidden = true;
  $('link-erstellen').hidden = false;
  $('link-kopieren').hidden = true;
  $('link-teilen').hidden = true;
  $('link-meldung').textContent = '';
  // Beiträge von Gästen gehen nur in ein Album.
  $('link-hochladen').hidden = !fall.album;
  $('link-dialog').showModal();
}

// Eine Adresse, die von aussen niemand erreicht: im Heimnetz oder lokal.
function nurImHeimnetz(adresse) {
  let h = '';
  try { h = new URL(adresse).hostname; } catch (_) { return false; }
  return h === 'localhost' || h.endsWith('.local') || h.endsWith('.lan') || /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|\[?fe80:|\[?fd[0-9a-f]{2}:)/i.test(h);
}

$('form-link').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const titel = f.titel.value.trim();
  if (!titel) { $('link-meldung').textContent = t('Bitte einen Titel eingeben.'); return; }
  const koerper = {
    titel,
    ...linkFall,
    ...(f.tage.value ? { tage: Number(f.tage.value) } : {}),
    ...(f.passwort.value ? { passwort: f.passwort.value } : {}),
    herunterladen: f.herunterladen.checked,
    ...(linkFall.album && f.hochladen.checked ? { hochladen: true } : {}),
  };
  try {
    const d = await api('/api/v1/freigaben', { methode: 'POST', json: koerper });
    $('link-adresse').value = d.link;
    $('link-heimnetz').hidden = !nurImHeimnetz(d.link);
    $('link-anlegen').hidden = true;
    $('link-fertig').hidden = false;
    $('link-erstellen').hidden = true;
    $('link-kopieren').hidden = false;
    $('link-teilen').hidden = !navigator.share;
    $('link-adresse').select();
  } catch (x) {
    $('link-meldung').textContent = x.message;
  }
});

async function kopiere(text) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    // Ohne HTTPS gibt es keine Zwischenablage-Schnittstelle.
    const feld = el('textarea');
    feld.value = text;
    document.body.append(feld);
    feld.select();
    document.execCommand('copy');
    feld.remove();
  }
  meldung(t('Link kopiert'));
}

$('link-kopieren').addEventListener('click', () => kopiere($('link-adresse').value));
$('link-teilen').addEventListener('click', () => navigator.share({ url: $('link-adresse').value, title: $('form-link').titel.value }).catch(() => {}));
$('link-abbrechen').addEventListener('click', () => $('link-dialog').close());

async function zeigeFreigaben() {
  const ul = $('freigaben');
  const d = await api('/api/v1/freigaben');
  ul.replaceChildren();
  if (!d.freigaben.length) ul.append(el('li', 'leise', t('Noch nichts geteilt.')));
  for (const x of d.freigaben) {
    const li = el('li');
    const abgelaufen = x.ablauf && new Date(x.ablauf) <= new Date();
    const teile = [
      anzahlText(x.anzahl),
      x.ablauf ? (abgelaufen ? t('abgelaufen') : t('bis {datum}', { datum: datumZeit.format(new Date(x.ablauf)) })) : t('unbegrenzt'),
      x.passwort ? t('mit Passwort') : null,
      x.herunterladen ? t('Originale erlaubt') : null,
      x.hochladen ? (x.beitraege ? (x.beitraege === 1 ? t('1 Beitrag offen') : t('{n} Beiträge offen', { n: x.beitraege })) : t('Gäste dürfen hinzufügen')) : null,
      x.aufrufe === 1 ? t('1 Aufruf') : t('{n} Aufrufe', { n: x.aufrufe }),
    ].filter(Boolean);
    li.append(el('span', null, `${x.titel} · ${teile.join(' · ')}`));
    const knoepfe = el('span', 'knoepfe');
    const kopieren = el('button', null, t('Kopieren'));
    kopieren.type = 'button';
    kopieren.addEventListener('click', () => kopiere(x.link));
    const weg = el('button', null, t('Löschen'));
    weg.type = 'button';
    weg.addEventListener('click', async () => {
      if (!confirm(t('Den Link „{titel}“ löschen? Wer ihn hat, sieht danach nichts mehr.', { titel: x.titel }))) return;
      try { await api(`/api/v1/freigaben/${encodeURIComponent(x.id)}`, { methode: 'DELETE' }); li.remove(); zeigeBeitraege().catch(() => {}); } catch (y) { alert(y.message); }
    });
    knoepfe.append(kopieren, weg);
    li.append(knoepfe);
    ul.append(li);
  }
}

// --- Beiträge von Gästen (Issue #106) ---------------------------------------
//
// Was Gäste über einen Link hochgeladen haben: abgeschottet geprüft und
// neu geschrieben (gastpruefung.dart). Ins Album kommt nur, was hier
// angenommen wird; Abgelehntes verschwindet samt Datei.

let beitraegeTakt = null;

const groesseText = (b) => (b >= 1e9 ? `${(b / 1e9).toFixed(1)} GB` : b >= 1e6 ? `${(b / 1e6).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1e3))} kB`);

async function nimmAn(ids) {
  for (const id of ids) {
    await api(`/api/v1/beitraege/${encodeURIComponent(id)}/annehmen`, { methode: 'POST' });
  }
}

async function zeigeBeitraege() {
  clearTimeout(beitraegeTakt);
  const d = await api('/api/v1/beitraege');
  const box = $('beitraege');
  box.replaceChildren();
  $('beitraege-bereich').hidden = !d.beitraege.length;
  $('beitraege-hinweis').textContent = d.abgeschottet
    ? t('Jede Datei wurde in einem eigenen Prozess ohne Netz geprüft und neu geschrieben – mit Aufnahmezeit, Ort und Kamera, sonst nichts.')
    : t('Jede Datei wurde in einem eigenen Prozess geprüft und neu geschrieben. Eine Netzsperre erlaubt dieses System nicht.');
  const bereit = d.beitraege.filter((b) => b.zustand === 'bereit');
  $('beitraege-alle').hidden = bereit.length < 2;
  $('beitraege-alle').onclick = async () => {
    try { await nimmAn(bereit.map((b) => b.id)); meldung(t('{n} Beiträge angenommen', { n: bereit.length })); } catch (x) { meldung(x.message); }
    zeigeBeitraege().catch(() => {});
    zeigeFreigaben().catch(() => {});
  };
  for (const b of d.beitraege) {
    const k = el('div', `beitrag ${b.zustand}`);
    const bild = el('div', 'beitrag-bild');
    if (b.zustand === 'bereit') {
      const img = el('img');
      img.alt = '';
      img.loading = 'lazy';
      img.src = `/api/v1/beitraege/${encodeURIComponent(b.id)}/vorschau`;
      bild.append(img);
      if (b.art === 'video') {
        const v = el('span', 'unten-rechts');
        if (b.dauer != null) v.append(el('span', 'dauer', videodauer(b.dauer)));
        v.append(kachelzeichen('abspielen'));
        bild.append(v);
      }
    } else {
      bild.append(el('span', 'leise', b.zustand === 'pruefung' ? t('wird geprüft …') : t('abgewiesen')));
    }
    const text = el('div', 'beitrag-text');
    text.append(el('strong', null, b.name));
    text.append(el('span', 'leise', [
      b.von ? t('von {name}', { name: b.von }) : null,
      b.freigabe.titel,
      groesseText(b.groesse),
    ].filter(Boolean).join(' · ')));
    if (b.grund) text.append(el('span', 'fehler', b.grund));
    const knoepfe = el('span', 'knoepfe');
    if (b.zustand === 'bereit') {
      const ja = el('button', 'primaer', t('Annehmen'));
      ja.type = 'button';
      ja.addEventListener('click', async () => {
        ja.disabled = true;
        try { await nimmAn([b.id]); k.remove(); } catch (x) { meldung(x.message); ja.disabled = false; }
        zeigeFreigaben().catch(() => {});
      });
      knoepfe.append(ja);
    }
    if (b.zustand !== 'pruefung') {
      const nein = el('button', null, b.zustand === 'bereit' ? t('Ablehnen') : t('Entfernen'));
      nein.type = 'button';
      nein.addEventListener('click', async () => {
        try { await api(`/api/v1/beitraege/${encodeURIComponent(b.id)}`, { methode: 'DELETE' }); k.remove(); } catch (x) { meldung(x.message); }
        zeigeFreigaben().catch(() => {});
      });
      knoepfe.append(nein);
    }
    k.append(bild, text, knoepfe);
    box.append(k);
  }
  // Was noch geprüft wird, kommt gleich – solange die Seite offen ist.
  if (d.beitraege.some((b) => b.zustand === 'pruefung') && !$('beitraege-bereich').closest('[hidden]')) {
    beitraegeTakt = setTimeout(() => zeigeBeitraege().catch(() => {}), 3000);
  }
}

const zeitraum = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium' });
// --- Reisen und Aktivitäten ---------------------------------------------------
//
// Dieselbe Gliederung wie auf dem Telefon: oben die Reisen, darunter die
// Aktivitäten; eine Reise zeigt ihre Aktivitäten über den Aufnahmen, eine
// Aktivität ihre Route. Gerechnet wird im Kern (reiseuebersicht.dart).

const AKT_ARTEN = {
  spaziergang: ['Spaziergang', '🚶'],
  wanderung: ['Wanderung', '🥾'],
  radtour: ['Radtour', '🚴'],
  ausflug: ['Ausflug', '🚗'],
  besichtigung: ['Besichtigung', '🏛'],
  bootsfahrt: ['Bootsfahrt', '⛵'],
  sonstiges: ['Sonstiges', '🧭'],
};
// Eine selbst eingetragene Art ist ihr eigener Name.
const artName = (k) => (AKT_ARTEN[k] ? t(AKT_ARTEN[k][0]) : k);
const artZeichen = (k) => (AKT_ARTEN[k] ? AKT_ARTEN[k][1] : '🧭');
const uhrzeit = new Intl.DateTimeFormat(GEBIET, { hour: '2-digit', minute: '2-digit' });
const kilometer = new Intl.NumberFormat(GEBIET, { minimumFractionDigits: 1, maximumFractionDigits: 1 });

function ortText(o) {
  if (!o) return null;
  if (!o.weitere) return o.text;
  return `${o.text} · ${o.weitere === 1 ? t('ein weiterer Ort') : t('{n} weitere Orte', { n: o.weitere })}`;
}

function dauerText(von, bis) {
  const minuten = Math.max(0, Math.round((new Date(bis) - new Date(von)) / 60000));
  return minuten < 60 ? t('{m}\u00a0min', { m: minuten }) : t('{h}\u00a0h {m}\u00a0min', { h: Math.floor(minuten / 60), m: minuten % 60 });
}

function reisekarte(r) {
  return karte(r.titelbild ? miniaturUrl(r.titelbild) : null, r.name,
    `${zeitraum.format(new Date(r.von))} – ${zeitraum.format(new Date(r.bis))} · ${anzahlText(r.anzahl)}`,
    `#/reisen/${encodeURIComponent(r.id)}`, { zusatz: ortText(r.ort) });
}

function aktivitaetskarte(a, inReise) {
  const zusatz = [ortText(a.ort), !inReise && a.reisename ? t('Gehört zu: {reise}', { reise: a.reisename }) : null].filter(Boolean).join(' · ');
  return karte(a.titelbild ? miniaturUrl(a.titelbild) : null, a.name,
    `${zeitraum.format(new Date(a.von))} · ${anzahlText(a.anzahl)}`,
    `#/aktivitaeten/${encodeURIComponent(a.id)}`, { zusatz, kennzeichen: `${artZeichen(a.art)} ${artName(a.art)}` });
}

async function zeigeReisen() {
  markiereNav('reisen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Reisen');
  const ziel = $('karten');
  ziel.replaceChildren();
  const d = await api(`/api/v1/reisen?sprache=${SPRACHE}`);
  if (d.reisen.length === 0) ziel.append(el('p', 'leise abschnitt', t('Noch keine Reisen.')));
  for (const r of d.reisen) ziel.append(reisekarte(r));
  ziel.append(el('h3', 'abschnitt', t('Aktivitäten')));
  if (d.aktivitaeten.length === 0) ziel.append(el('p', 'leise abschnitt', t('Noch keine Aktivitäten.')));
  for (const a of d.aktivitaeten) ziel.append(aktivitaetskarte(a, false));
}

async function zeigeReise(id) {
  markiereNav('reisen');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/reisen/${encodeURIComponent(id)}?sprache=${SPRACHE}`);
  const r = d.reise;
  const kopf = el('div', 'reisekopf');
  kopf.append(el('p', 'fakten', `${zeitraum.format(new Date(r.von))} – ${zeitraum.format(new Date(r.bis))} · ${anzahlText(r.anzahl)}`));
  if (r.notiz) kopf.append(el('p', 'notiz', r.notiz));
  if (d.aktivitaeten.length) {
    kopf.append(el('h3', null, t('Aktivitäten')));
    const reihe = el('div', 'kartenreihe');
    for (const a of d.aktivitaeten) reihe.append(aktivitaetskarte(a, true));
    kopf.append(reihe);
  }
  zeigeListe({ aufnahmen: d.aufnahmen, nachTagen: true, kopf }, r.name);
}

async function zeigeAktivitaet(id) {
  markiereNav('reisen');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/aktivitaeten/${encodeURIComponent(id)}?sprache=${SPRACHE}`);
  const a = d.aktivitaet;
  const kopf = el('div', 'reisekopf');
  kopf.append(el('p', 'fakten', [
    `${artZeichen(a.art)} ${artName(a.art)}`,
    zeitraum.format(new Date(a.von)),
    `${uhrzeit.format(new Date(a.von))}–${uhrzeit.format(new Date(a.bis))}`,
    dauerText(a.von, a.bis),
    a.streckeKm > 0 ? t('{km}\u00a0km', { km: kilometer.format(a.streckeKm) }) : null,
    anzahlText(a.anzahl),
  ].filter(Boolean).join(' · ')));
  const ort = ortText(a.ort);
  if (ort) kopf.append(el('p', 'nebenzeile', `📍 ${ort}`));
  if (a.reise) {
    const p = el('p', 'nebenzeile');
    const l = el('a', null, t('Gehört zu: {reise}', { reise: a.reise.name }));
    l.href = `#/reisen/${encodeURIComponent(a.reise.id)}`;
    p.append(l);
    kopf.append(p);
  }
  if (a.notiz) kopf.append(el('p', 'notiz', a.notiz));
  let route = null;
  if (d.route.length > 1) {
    route = el('div', 'routenkarte');
    kopf.append(route);
  } else if (d.aufnahmen.length) {
    kopf.append(el('p', 'nebenzeile', t('Zu wenige verortete Aufnahmen für eine Strecke.')));
  }
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, a.name);
  if (route) ladeLeaflet().then(() => zeichneRoute(route, d.route)).catch((x) => route.replaceChildren(el('p', 'fehler', x.message)));
}

// Leaflet erst, wenn eine Karte gebraucht wird: Skript und Stil sind gut
// 150 KB, die vorher jede Seite lud, auch wenn nie eine Karte kam.
let leafletLaden = null;
// Was nur ein Bereich braucht, kommt erst mit ihm: Entwickeln (WebGL)
// und der Lebensbaum sind zusammen 43 KB, die beim Start niemand braucht.
const skripte = new Map();
function ladeSkript(name) {
  if (!skripte.has(name)) {
    skripte.set(name, new Promise((fertig, fehler) => {
      const s = document.createElement('script');
      s.src = name;
      s.addEventListener('load', fertig, { once: true });
      s.addEventListener('error', () => {
        skripte.delete(name);
        s.remove();
        fehler(new Error(t('Keine Verbindung zum Server.')));
      }, { once: true });
      document.body.append(s);
    }));
  }
  return skripte.get(name);
}

function ladeLeaflet() {
  if (typeof L !== 'undefined') return Promise.resolve();
  if (!leafletLaden) {
    const geladen = (e) => new Promise((fertig, fehler) => {
      e.addEventListener('load', fertig, { once: true });
      e.addEventListener('error', () => fehler(new Error(t('Die Karte ließ sich nicht laden.'))), { once: true });
    });
    const stil = document.createElement('link');
    stil.rel = 'stylesheet';
    stil.href = 'leaflet/leaflet.css';
    // Vor app.css, damit die eigenen Regeln weiter gewinnen.
    document.head.insertBefore(stil, document.querySelector('link[href="app.css"]'));
    const skript = document.createElement('script');
    skript.src = 'leaflet/leaflet.js';
    document.head.append(skript);
    leafletLaden = Promise.all([geladen(stil), geladen(skript)]).catch((x) => {
      leafletLaden = null;
      stil.remove();
      skript.remove();
      throw x;
    });
  }
  return leafletLaden;
}

// Die Route: Linie durch die verorteten Aufnahmen in ihrer Zeitfolge, ein
// Punkt je Aufnahme – ein Tipp darauf öffnet sie.
function zeichneRoute(box, punkte) {
  const karte = L.map(box, { scrollWheelZoom: false });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(karte);
  const farbe = getComputedStyle(document.documentElement).getPropertyValue('--akzent').trim() || '#0d8a7a';
  const linie = L.polyline(punkte.map((p) => [p.breite, p.laenge]), { color: farbe, weight: 4, opacity: 0.85 }).addTo(karte);
  punkte.forEach((p, i) => {
    const ende = i === 0 || i === punkte.length - 1;
    L.circleMarker([p.breite, p.laenge], { radius: ende ? 7 : 4, color: '#fff', weight: 2, fillColor: farbe, fillOpacity: 1 })
      .addTo(karte)
      .on('click', () => { const n = liste.aufnahmen.findIndex((x) => x.id === p.id); if (n >= 0) oeffne(n); });
  });
  karte.fitBounds(linie.getBounds(), { padding: [24, 24], maxZoom: 16 });
}

const zahl = new Intl.NumberFormat(GEBIET);
const groesse = (b) => (b >= 1073741824 ? `${(b / 1073741824).toFixed(1)} GB` : b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.round(b / 1024)} KB`);
const monatsname = new Intl.DateTimeFormat(GEBIET, { month: 'short' });

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
    kennzahl(zahl.format(s.insgesamt), t('Medien insgesamt')),
    kennzahl(zahl.format(s.fotos), t('Fotos')),
    kennzahl(zahl.format(s.videos), t('Videos')),
    kennzahl(zahl.format(s.favoriten), t('Favoriten')),
    kennzahl(groesse(s.bytes), t('Speicherplatz')),
    kennzahl(zahl.format(s.papierkorb), t('Im Papierkorb')),
    kennzahl(zahl.format(s.gesperrt), t('Gesperrter Ordner')),
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
  $('dupl-hinweis').textContent = t('Suche …');
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
  $('dupl-alle').textContent = t('{n} Kopien in den Papierkorb', { n: loeschbar });
  if (d.einbettungen === 0) {
    $('dupl-hinweis').textContent = t('Noch keine Bildeinbettungen – die Auswertung auf dem Server muss zuerst gelaufen sein.');
  } else if (d.gruppen.length === 0) {
    $('dupl-hinweis').textContent = t('Keine Duplikate bei {p} Ähnlichkeit.', { p: prozent(d.schwelle) }) + (d.ausnahmen ? ` ${t('{n} Paare sind ausgenommen.', { n: d.ausnahmen })}` : '');
  } else {
    $('dupl-hinweis').textContent = t('{n} Gruppen bei {p} Ähnlichkeit. Das umrandete Foto würde beim Aufräumen behalten; Gruppen mit mehreren Favoriten oder Bewertungen bleiben unangetastet.', { n: d.gruppen.length, p: prozent(d.schwelle) });
  }
  for (const g of d.gruppen) ziel.append(duplikatgruppe(g));
}

function duplikatgruppe(g) {
  const box = el('div', 'gruppe');
  const ids = g.aufnahmen.map((a) => a.id);
  const entferne = () => { duplikate.gruppen = duplikate.gruppen.filter((x) => x !== g); zeichneDuplikate(); };
  const kopf = el('div', 'gruppenkopf');
  const ignorieren = el('button', null, t('Keine Duplikate'));
  ignorieren.type = 'button';
  ignorieren.addEventListener('click', async () => {
    try { await befehl('duplikatgruppeIgnorieren', { ids }); entferne(); } catch (x) { $('dupl-hinweis').textContent = x.message; }
  });
  kopf.append(el('span', null, g.loeschbar.length ? anzahlText(g.aufnahmen.length) : t('{n} Aufnahmen · mehrere ausgezeichnet, nur von Hand', { n: g.aufnahmen.length })), ignorieren);
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
    const knopf = el('button', null, t('Behalten'));
    knopf.type = 'button';
    knopf.addEventListener('click', async () => {
      const andere = ids.filter((x) => x !== a.id);
      if (!confirm(andere.length === 1 ? t('„{name}“ behalten und die andere Aufnahme in den Papierkorb legen?', { name: a.name }) : t('„{name}“ behalten und die {n} anderen in den Papierkorb legen?', { name: a.name, n: andere.length }))) return;
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
  if (!confirm(t('{n} Kopien aus {g} Gruppen in den Papierkorb legen? Je Gruppe bleibt das umrandete Foto.', { n, g: faellig.length }))) return;
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
  zeigeListe({ aufnahmen: d.aufnahmen }, t('Serie · {n} Aufnahmen', { n: d.aufnahmen.length }));
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

$('baum-zum-lebensbaum').addEventListener('click', () => { location.hash = `#/lebensbaum/${encodeURIComponent($('baum-person').value || '')}`; });

async function zeigeStammbaum(fokus) {
  markiereNav('stammbaum');
  zeigeBereich(['stammbaum']);
  $('baum-hinweis').textContent = '';
  const d = await api(`/api/v1/stammbaum${fokus ? `?fokus=${encodeURIComponent(fokus)}` : ''}`);
  const wahl = $('baum-person');
  wahl.replaceChildren();
  for (const p of [...d.personen].sort((a, b) => a.name.localeCompare(b.name))) {
    const o = el('option', null, p.verwandt ? p.name : t('{name} (ohne Verwandtschaft)', { name: p.name }));
    o.value = p.id;
    wahl.append(o);
  }
  wahl.value = d.fokus || '';
  $('baum-flaeche').replaceChildren();
  if (!d.fokus) { $('baum-hinweis').textContent = t('Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.'); return; }
  const hinweise = [];
  if (d.haushalte.length === 1 && d.haushalte[0].personen.length === 1) hinweise.push(t('Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.'));
  if (d.verschwiegen) hinweise.push(t('{n} Haushalte passen nicht mehr ins Bild.', { n: d.verschwiegen }));
  $('baum-hinweis').textContent = hinweise.join(' ');
  $('baum-flaeche').append(baumSvg(d));
}

function baumSvg(d) {
  const nachId = Object.fromEntries(d.personen.map((p) => [p.id, p]));
  const kB = 118, kH = 140;
  // Die Plätze rechnet der Server wie der Rechner (zierbaumplan): Kinder
  // unter ihren Elternhäusern. Vorher wurden die Haushalte eines Bandes
  // nur der Reihe nach gesetzt, und ein Kind konnte unter dem falschen
  // Paar stehen.
  const plan = d.plan;
  const gesamt = plan.breite, hoehe = plan.hoehe;
  const svg = svgEl('svg', { viewBox: `0 0 ${gesamt} ${hoehe}`, width: gesamt * baumZoomWert, height: hoehe * baumZoomWert });
  svg.dataset.breite = gesamt;
  svg.dataset.hoehe = hoehe;
  const defs = svgEl('defs');
  svg.append(defs);
  const lage = {}; // personId -> {x, y}
  for (const s of plan.schilder) lage[s.id] = { x: s.x, y: s.y };
  // Äste: vom Schild (oben) in einer Kurve zur Mitte des Elternhauses.
  for (const a of plan.aeste) {
    const m = (a.y1 + a.y2) / 2;
    svg.append(svgEl('path', { class: 'baum-kante', d: `M${a.x1},${a.y1} C${a.x1},${m} ${a.x2},${m} ${a.x2},${a.y2}` }));
  }
  // Partner: auf Höhe der Bilder verbunden.
  for (const p of plan.paare) {
    const y = p.y - kH / 2 + 46;
    svg.append(svgEl('line', { class: 'baum-paar', x1: p.x1, y1: y, x2: p.x2, y2: y }));
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

// --- Einstellungen der Bibliothek ------------------------------------------

$('einst-sprache').addEventListener('change', () => spracheWaehlen($('einst-sprache').value));

async function zeigeEinstellungen() {
  markiereNav('einstellungen');
  zeigeBereich(['einstellungen']);
  let gewaehlt = 'auto';
  try { gewaehlt = localStorage.getItem(SPRACHE_MERKER) || 'auto'; } catch (_) { /* privat */ }
  $('einst-sprache').value = gewaehlt;
  const e = await api('/api/v1/einstellungen');
  const ziel = $('einst-liste');
  const melde = (t) => { $('einst-meldung').textContent = t; };
  const sende = async (art, werte) => {
    try { await befehl(art, werte); melde(t('Gespeichert.')); } catch (x) { melde(x.message); }
  };
  const zeile = (titel, text, an, beiAenderung, zusatz) => {
    const z = el('label', 'einst');
    const kasten = el('input');
    kasten.type = 'checkbox';
    kasten.checked = an;
    kasten.addEventListener('change', () => beiAenderung(kasten.checked));
    const inhalt = el('div', 'inhalt');
    inhalt.append(el('div', 'titel', t(titel)), el('div', 'text', t(text)));
    if (zusatz) inhalt.append(zusatz);
    z.append(kasten, inhalt);
    return z;
  };
  const regler = (min, max, schritt, wert, anzeige, beiAenderung) => {
    const box = el('div', 'regler');
    const r = el('input');
    r.type = 'range'; r.min = min; r.max = max; r.step = schritt; r.value = wert;
    const w = el('span', null, anzeige(wert));
    r.addEventListener('input', () => { w.textContent = anzeige(r.value); });
    r.addEventListener('change', () => beiAenderung(Number(r.value)));
    box.append(r, w);
    return box;
  };
  const tage = el('input');
  tage.type = 'number'; tage.min = '1'; tage.max = '3650'; tage.value = e.papierkorbTage;
  const tageBox = el('div', 'regler');
  tageBox.append(el('span', null, t('nach')), tage, el('span', null, t('Tagen')));
  let leeren = e.papierkorbLeeren;
  tage.addEventListener('change', () => sende('papierkorbFristSetzen', { an: leeren, tage: Number(tage.value) }));
  let vorschlaegeAb = e.vorschlaegeAb ?? 0.9;
  const vorschlagRegler = regler(0.8, 0.99, 0.01, vorschlaegeAb, (v) => t('ab {p}', { p: `${Math.round(v * 100)} %` }), (v) => { vorschlaegeAb = v; if (vorschlaegeAn) sende('vorschlaegeAutomatischSetzen', { ab: v }); });
  let vorschlaegeAn = e.vorschlaegeAb != null;
  ziel.replaceChildren(
    zeile('Papierkorb automatisch leeren', 'Löscht Aufnahmen im Papierkorb nach Ablauf der Frist endgültig – unwiderruflich.', leeren, (an) => { leeren = an; sende('papierkorbFristSetzen', { an, tage: Number(tage.value) }); }, tageBox),
    zeile('Sichere Vorschläge automatisch übernehmen', 'Erkannte Gesichter, die einer Person sehr ähnlich sind, werden ohne Rückfrage zugeordnet.', vorschlaegeAn, (an) => { vorschlaegeAn = an; sende('vorschlaegeAutomatischSetzen', { ab: an ? vorschlaegeAb : null }); }, vorschlagRegler),
    zeile('KI-Auswertung nach dem Import automatisch nachholen', 'Neue Aufnahmen werden gleich ausgewertet: Gesichter, Bildinhalt, Text, Schlagwörter.', e.auswertenNachImport, (an) => sende('auswertenNachImportSetzen', { an })),
    zeile('Suche und Schlagwörter übersetzen', 'Sucht auf Deutsch und Englisch gleichzeitig und führt Schlagwörter in beiden Sprachen.', e.sucheUebersetzen, (an) => sende('sucheUebersetzenSetzen', { an })),
    zeile('Private Metadaten schützen', 'Neu gesperrte Aufnahmen legen auch Ort, Beschreibung und Text verschlüsselt ab.', e.angabenSchuetzen, (an) => sende('angabenSchuetzenSetzen', { an })),
  );
  const schwelle = el('div', 'einst');
  const sInhalt = el('div', 'inhalt');
  sInhalt.append(el('div', 'titel', t('Schwelle der Gesichtserkennung')), el('div', 'text', t('Wie ähnlich ein Gesicht sein muss, um einer Person vorgeschlagen zu werden. Höher heisst vorsichtiger.')), regler(0.2, 0.8, 0.01, e.gesichtsschwelle, (v) => Number(v).toFixed(2), (v) => sende('gesichtsschwelleSetzen', { schwelle: v })));
  schwelle.append(el('span'), sInhalt);
  ziel.append(schwelle);
  melde('');
}

async function zeigePersonen() {
  markiereNav('personen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Personen');
  $('karten').replaceChildren();
  const d = await api('/api/v1/personen');
  if (d.personen.length === 0) $('karten').append(el('p', 'leise', t('Noch keine Personen.')));
  for (const p of d.personen) {
    const bild = p.bild ? `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}` : null;
    const k = karte(bild, p.name, anzahlText(p.anzahl), `#/personen/${encodeURIComponent(p.id)}`);
    k.classList.add('person');
    $('karten').append(k);
  }
  zeigeOhneNamen().catch(() => {});
}

// --- Gesichter benennen ----------------------------------------------------
//
// Wie am Rechner und auf dem Telefon: Ähnliche Gesichter ohne Namen stehen
// als Gruppe oben bei den Personen; die Angaben eines Fotos zeigen jedes
// Gesicht für sich. Benennen heisst: einer vorhandenen Person zuordnen
// oder eine neue anlegen. Alles geht über die Befehle des Kerns.

const dateiUrl = (pfad) => `/api/v1/dateien/${pfad.split('/').map(encodeURIComponent).join('/')}`;

// Eine Kennung wie crypto.randomUUID – das gibt es nur über HTTPS, im
// Heimnetz läuft der Browser aber oft über http.
function neueKennung() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

function gesichtsbild(g) {
  const img = el('img');
  img.alt = '';
  img.loading = 'lazy';
  if (g.ausschnitt) img.src = dateiUrl(g.ausschnitt);
  return img;
}

async function zeigeOhneNamen() {
  const box = $('ohne-namen');
  const d = await api('/api/v1/gesichter/ohne-namen');
  box.replaceChildren();
  if (!d.gruppen.length) { box.hidden = true; return; }
  const kopf = el('div', 'bib-kopf');
  kopf.append(el('h3', null, t('Ohne Namen')), el('span', 'leise', t('{n} Gesichter', { n: d.gesamt })));
  const reihe = el('div', 'gesichtsgruppen');
  for (const g of d.gruppen.slice(0, 60)) {
    const b = el('button', 'gesichtsgruppe');
    b.type = 'button';
    const mosaik = el('span', 'mosaik');
    for (const f of g.gesichter.slice(0, 4)) mosaik.append(gesichtsbild(f));
    b.append(mosaik, el('span', 'wer', g.vorschlag ? t('{name}?', { name: g.vorschlag.name }) : t('Wer ist das?')), el('span', 'leise', t('{n} Gesichter', { n: g.gesichter.length })));
    b.addEventListener('click', () => oeffneGesichter({
      titel: t('{n} ähnliche Gesichter', { n: g.gesichter.length }),
      gesichter: g.gesichter,
      vorschlag: g.vorschlag,
      aehnlichkeit: g.aehnlichkeit,
      schwelle: d.schwelle,
      fertig: () => zeigePersonen(),
    }));
    reihe.append(b);
  }
  box.append(kopf, reihe);
  box.hidden = $('bereich-karten').hidden;
}

let gesichtFall = null;

async function oeffneGesichter(fall) {
  gesichtFall = { ...fall, aus: new Set(), personen: [] };
  $('gesicht-titel').textContent = fall.titel;
  const raster = $('gesicht-auswahl');
  raster.replaceChildren();
  for (const g of fall.gesichter) {
    const b = el('button', 'gesicht');
    b.type = 'button';
    b.append(gesichtsbild(g));
    if (fall.gesichter.length > 1) {
      b.addEventListener('click', () => {
        if (gesichtFall.aus.has(g.id)) gesichtFall.aus.delete(g.id); else gesichtFall.aus.add(g.id);
        b.classList.toggle('aus');
      });
    }
    raster.append(b);
  }
  $('gesicht-hinweis').hidden = fall.gesichter.length < 2;
  $('gesicht-ja').hidden = !fall.vorschlag;
  if (fall.vorschlag) $('gesicht-ja').textContent = t('Das ist {name}', { name: fall.vorschlag.name });
  $('gesicht-loesen').hidden = !fall.person;
  $('form-gesicht').name.value = fall.person ? fall.person.name : '';
  $('gesicht-meldung').textContent = '';
  $('gesicht-namen').replaceChildren();
  $('gesicht-dialog').showModal();
  try { gesichtFall.personen = (await api('/api/v1/personen')).personen; } catch (_) { /* ohne Vorschläge */ }
  for (const p of gesichtFall.personen) {
    if (!(p.name || '').trim()) continue;
    const o = el('option');
    o.value = p.name;
    $('gesicht-namen').append(o);
  }
}

async function gesichterFertig(ausfuehren) {
  const fall = gesichtFall;
  if (!fall) return;
  const ids = fall.gesichter.map((g) => g.id).filter((id) => !fall.aus.has(id));
  if (!ids.length) { $('gesicht-meldung').textContent = t('Kein Gesicht gewählt.'); return; }
  try {
    await ausfuehren(ids, fall);
    $('gesicht-dialog').close();
    gesichtFall = null;
    if (fall.fertig) fall.fertig();
  } catch (x) {
    $('gesicht-meldung').textContent = x.message;
  }
}

// Hatte die Gruppe einen Vorschlag, ist die Wahl ein Urteil darüber:
// dieselbe Person bestätigt ihn, eine andere lehnt ihn ab. Daraus lernt
// die Schwelle dieser Person – ein Eintrag für die ganze Gruppe, wie am
// Rechner (gesichtsuebersicht.dart, gruppeEntschieden). Beiseitelegen
// sagt darüber nichts.
async function merkeGruppe(fall, ids, personId) {
  if (!fall.vorschlag || fall.aehnlichkeit == null || fall.schwelle == null) return;
  await befehl('gesichtsEntscheidungenMerken', {
    personId: fall.vorschlag.id,
    entscheidungen: [{ faceId: ids[0], accepted: personId === fall.vorschlag.id, similarity: fall.aehnlichkeit }],
    allgemeineSchwelle: fall.schwelle,
  });
}

$('gesicht-ja').addEventListener('click', () => gesichterFertig(async (ids, fall) => {
  await befehl('gesichterZuordnen', { gesichtIds: ids, personId: fall.vorschlag.id });
  await merkeGruppe(fall, ids, fall.vorschlag.id);
}));
$('form-gesicht').addEventListener('submit', (e) => {
  e.preventDefault();
  const name = e.target.name.value.trim();
  if (!name) { $('gesicht-meldung').textContent = t('Bitte einen Namen eingeben.'); return; }
  gesichterFertig(async (ids, fall) => {
    // Ein vorhandener Name heisst: diese Person – sonst eine neue.
    const da = fall.personen.find((p) => (p.name || '').trim().toLowerCase() === name.toLowerCase());
    let personId = da && da.id;
    if (!personId) {
      personId = neueKennung();
      await befehl('personAnlegen', { personId, name });
    }
    await befehl('gesichterZuordnen', { gesichtIds: ids, personId });
    await merkeGruppe(fall, ids, personId);
  });
});
$('gesicht-beiseite').addEventListener('click', () => gesichterFertig((ids) => befehl('gesichterBeiseitelegen', { gesichtIds: ids, beiseite: true })));
$('gesicht-loesen').addEventListener('click', () => gesichterFertig(async (ids) => { for (const id of ids) await befehl('zuordnungLoesen', { gesichtId: id }); }));
$('gesicht-abbrechen').addEventListener('click', () => $('gesicht-dialog').close());

// Die Gesichter eines Fotos in den Angaben: jedes antippbar.
function gesichterReihe(gesichter) {
  const box = el('div', 'gesichter-reihe');
  for (const g of gesichter) {
    const b = el('button', `angaben-gesicht${g.person ? '' : ' unbekannt'}`);
    b.type = 'button';
    b.title = g.person ? g.person.name : t('Wer ist das?');
    b.append(gesichtsbild(g), el('span', null, g.person ? g.person.name : '?'));
    b.addEventListener('click', () => oeffneGesichter({
      titel: g.person ? g.person.name : t('Wer ist das?'),
      gesichter: [g],
      person: g.person,
      fertig: () => zeigeAngaben(),
    }));
    box.append(b);
  }
  return box;
}

// Zwei Einträge für dieselbe Person: einer geht im anderen auf.
let zusammenFall = null;
async function oeffneZusammenfuehren(person) {
  const d = await api('/api/v1/personen');
  const andere = d.personen.filter((p) => p.id !== person.id).sort((a, b) => (a.name || '').localeCompare(b.name || ''));
  const sel = $('zusammen-andere');
  sel.replaceChildren();
  for (const p of andere) {
    const o = el('option', null, `${p.name || '?'} (${anzahlText(p.anzahl)})`);
    o.value = p.id;
    sel.append(o);
  }
  zusammenFall = person;
  $('zusammen-titel').textContent = t('In „{name}“ aufnehmen', { name: person.name });
  $('zusammen-meldung').textContent = '';
  $('zusammen-dialog').showModal();
}
$('zusammen-abbrechen').addEventListener('click', () => $('zusammen-dialog').close());
$('form-zusammen').addEventListener('submit', async (e) => {
  e.preventDefault();
  const person = zusammenFall;
  const andere = $('zusammen-andere').value;
  if (!person || !andere) return;
  const name = $('zusammen-andere').selectedOptions[0]?.textContent || '';
  if (!confirm(t('„{andere}“ in „{name}“ aufnehmen? Das lässt sich nicht rückgängig machen.', { andere: name, name: person.name }))) return;
  try {
    await befehl('personenZusammenfuehren', { behalten: person.id, entfernen: andere });
    $('zusammen-dialog').close();
    zeigePerson(person.id);
  } catch (x) {
    $('zusammen-meldung').textContent = x.message;
  }
});

// --- Weitere Fotos einer Person ----------------------------------------------
//
// Wie „Vorschläge suchen“ am Rechner: unbenannte Gesichter, die der Person
// ähnlich genug sind, alle schon gewählt. Was man herausnimmt, gilt als
// Ablehnung – die Schwelle der Person steigt, und derselbe Fehlvorschlag
// kommt nicht wieder.

let vorschlagFall = null;

function vorschlagKnopf() {
  const f = vorschlagFall;
  const n = f.vorschlaege.filter((v) => f.gewaehlt.has(v.id)).length;
  $('vorschlag-ok').textContent = n === 0 ? t('Nichts ausgewählt') : n === 1 ? t('Ein Gesicht zuordnen') : t('{n} Gesichter zuordnen', { n });
  $('vorschlag-alle').textContent = n === f.vorschlaege.length ? t('Keine wählen') : t('Alle wählen');
}

async function oeffneVorschlaege(person) {
  const d = await api(`/api/v1/personen/${encodeURIComponent(person.id)}/vorschlaege`);
  if (!d.vorschlaege.length) {
    meldung(t('Kein unbenanntes Gesicht liegt über der Schwelle {schwelle} dieser Person.', { schwelle: d.schwelle.toFixed(2) }));
    return;
  }
  vorschlagFall = { person, ...d, gewaehlt: new Set(d.vorschlaege.map((v) => v.id)) };
  $('vorschlag-titel').textContent = t('Vorschläge für {name}', { name: person.name });
  const raster = $('vorschlag-auswahl');
  raster.replaceChildren();
  for (const v of d.vorschlaege) {
    const b = el('button', 'gesicht');
    b.type = 'button';
    b.title = `${Math.round(v.aehnlichkeit * 100)} %`;
    b.dataset.id = v.id;
    b.append(gesichtsbild(v));
    b.addEventListener('click', () => {
      if (vorschlagFall.gewaehlt.has(v.id)) vorschlagFall.gewaehlt.delete(v.id); else vorschlagFall.gewaehlt.add(v.id);
      b.classList.toggle('aus', !vorschlagFall.gewaehlt.has(v.id));
      vorschlagKnopf();
    });
    raster.append(b);
  }
  $('vorschlag-meldung').textContent = '';
  vorschlagKnopf();
  $('vorschlag-dialog').showModal();
}

$('vorschlag-alle').addEventListener('click', () => {
  const f = vorschlagFall;
  if (!f) return;
  const alle = f.gewaehlt.size === f.vorschlaege.length;
  f.gewaehlt = alle ? new Set() : new Set(f.vorschlaege.map((v) => v.id));
  for (const b of $('vorschlag-auswahl').children) b.classList.toggle('aus', !f.gewaehlt.has(b.dataset.id));
  vorschlagKnopf();
});
$('vorschlag-abbrechen').addEventListener('click', () => $('vorschlag-dialog').close());
$('form-vorschlag').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = vorschlagFall;
  if (!f) return;
  // Dieselben drei Schritte wie am Rechner (gesichtsuebersicht.dart,
  // vorschlaegeEntschieden): zuordnen, den Rest verwerfen, beides merken.
  const ja = f.vorschlaege.filter((v) => f.gewaehlt.has(v.id)).map((v) => v.id);
  const nein = f.vorschlaege.filter((v) => !f.gewaehlt.has(v.id)).map((v) => v.id);
  try {
    if (ja.length) await befehl('gesichterZuordnen', { gesichtIds: ja, personId: f.person.id });
    if (nein.length) await befehl('vorschlaegeVerwerfen', { gesichtIds: nein });
    await befehl('gesichtsEntscheidungenMerken', {
      personId: f.person.id,
      entscheidungen: f.vorschlaege.map((v) => ({ faceId: v.id, accepted: f.gewaehlt.has(v.id), similarity: v.aehnlichkeit })),
      allgemeineSchwelle: f.allgemein,
    });
    $('vorschlag-dialog').close();
    vorschlagFall = null;
    meldung(ja.length === 0 ? t('Nichts übernommen – die Rückmeldung ist trotzdem gespeichert.') : ja.length === 1 ? t('Ein Foto hinzugefügt.') : t('{n} Fotos hinzugefügt.', { n: ja.length }));
    zeigePerson(f.person.id);
  } catch (x) {
    $('vorschlag-meldung').textContent = x.message;
  }
});

async function zeigePerson(id) {
  markiereNav('personen');
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/personen/${encodeURIComponent(id)}`);
  const kopf = el('div', 'reisekopf');
  const weitere = el('button', 'knopf', t('Weitere Fotos finden'));
  weitere.type = 'button';
  weitere.addEventListener('click', () => oeffneVorschlaege(d.person).catch((x) => meldung(x.message)));
  const zusammen = el('button', 'knopf', t('Zusammenführen …'));
  zusammen.type = 'button';
  zusammen.addEventListener('click', () => oeffneZusammenfuehren(d.person).catch((x) => meldung(x.message)));
  kopf.append(weitere, zusammen);
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, d.person.name);
}

function zeigeSuche() {
  markiereNav('suche');
  zeigeBereich(['suche', 'raster']);
  if (!liste || !liste.suche) zeigeListe({ aufnahmen: [], suche: true });
  $('form-suche').text.focus();
}

// --- Filter der Suche --------------------------------------------------------
//
// Dieselben Filter wie auf dem Telefon (suchlauf.dart im Kern): Personen
// (alle müssen drauf sein), Land und Stadt, Zeitraum, Art, Kamera, nur
// Favoriten. Mit Filtern darf das Suchfeld leer bleiben.

const suchfilter = { personen: new Set(), geladen: null };

async function ladeSuchauswahl() {
  if (suchfilter.geladen) return suchfilter.geladen;
  const w = await api(`/api/v1/suche/auswahl?sprache=${SPRACHE}`);
  suchfilter.geladen = w;
  const personen = $('filter-personen');
  personen.replaceChildren();
  for (const p of w.personen) {
    const b = el('button', 'filter-person');
    b.type = 'button';
    b.setAttribute('aria-pressed', 'false');
    const rund = el('span', 'filter-gesicht');
    if (p.bild) { const img = el('img'); img.alt = ''; img.loading = 'lazy'; img.src = dateiUrl(p.bild); rund.append(img); } else rund.textContent = p.name.trim().charAt(0).toUpperCase();
    b.append(rund, el('span', null, p.name));
    b.addEventListener('click', () => {
      if (suchfilter.personen.has(p.id)) suchfilter.personen.delete(p.id); else suchfilter.personen.add(p.id);
      b.setAttribute('aria-pressed', String(suchfilter.personen.has(p.id)));
      zeigeFilterzeile();
    });
    personen.append(b);
  }
  if (!w.personen.length) personen.append(el('span', 'leise', t('Noch keine Personen.')));
  const land = $('filter-land');
  for (const o of w.orte) { const x = el('option', null, o.name); x.value = o.land; land.append(x); }
  const kamera = $('filter-kamera');
  for (const k of w.kameras) { const x = el('option', null, k); x.value = k; kamera.append(x); }
  return w;
}

function fuelleStaedte() {
  const w = suchfilter.geladen;
  const stadt = $('filter-stadt');
  stadt.replaceChildren(el('option', null, t('Alle')));
  stadt.firstChild.value = '';
  const ort = w && w.orte.find((o) => o.land === $('filter-land').value);
  stadt.disabled = !ort || !ort.staedte.length;
  for (const s of ort ? ort.staedte : []) { const x = el('option', null, s); x.value = s; stadt.append(x); }
}

function filterParameter() {
  const q = new URLSearchParams();
  for (const id of suchfilter.personen) q.append('person', id);
  for (const [name, feld] of [['land', 'filter-land'], ['stadt', 'filter-stadt'], ['von', 'filter-von'], ['bis', 'filter-bis'], ['art', 'filter-art'], ['kamera', 'filter-kamera']]) {
    if ($(feld).value) q.set(name, $(feld).value);
  }
  if ($('filter-favoriten').checked) q.set('favoriten', '1');
  return q;
}

// Was gerade gefiltert wird, als eine Zeile unter dem Suchfeld.
function zeigeFilterzeile() {
  const w = suchfilter.geladen;
  const teile = [];
  if (w) for (const p of w.personen) if (suchfilter.personen.has(p.id)) teile.push(p.name);
  const land = $('filter-land');
  if (land.value) teile.push([$('filter-stadt').value, land.selectedOptions[0].textContent].filter(Boolean).join(', '));
  const von = $('filter-von').value, bis = $('filter-bis').value;
  if (von || bis) teile.push(`${von || '…'} – ${bis || '…'}`);
  if ($('filter-art').value) teile.push($('filter-art').selectedOptions[0].textContent);
  if ($('filter-kamera').value) teile.push($('filter-kamera').value);
  if ($('filter-favoriten').checked) teile.push(t('Favoriten'));
  $('suche-filterzeile').textContent = teile.length ? `${t('Filter')}: ${teile.join(' · ')}` : '';
  $('suche-filterzeile').hidden = !teile.length;
  $('filter-knopf').classList.toggle('aktiv', teile.length > 0);
}

$('filter-knopf').addEventListener('click', async () => {
  const auf = $('suchfilter').hidden;
  $('suchfilter').hidden = !auf;
  $('filter-knopf').setAttribute('aria-expanded', String(auf));
  if (auf) { try { await ladeSuchauswahl(); } catch (x) { $('suche-hinweis').textContent = x.message; } }
});
$('filter-land').addEventListener('change', () => { fuelleStaedte(); zeigeFilterzeile(); });
for (const id of ['filter-stadt', 'filter-von', 'filter-bis', 'filter-art', 'filter-kamera', 'filter-favoriten']) $(id).addEventListener('change', zeigeFilterzeile);
$('filter-leeren').addEventListener('click', () => {
  suchfilter.personen.clear();
  for (const b of $('filter-personen').querySelectorAll('[aria-pressed]')) b.setAttribute('aria-pressed', 'false');
  for (const id of ['filter-land', 'filter-von', 'filter-bis', 'filter-art', 'filter-kamera']) $(id).value = '';
  $('filter-favoriten').checked = false;
  fuelleStaedte();
  zeigeFilterzeile();
});

$('form-suche').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const text = f.text.value.trim();
  const q = filterParameter();
  if (!text && ![...q.keys()].length) { $('suche-hinweis').textContent = t('Suchtext eingeben oder einen Filter wählen.'); return; }
  $('suche-hinweis').textContent = t('Sucht …');
  try {
    if (text) { q.set('text', text); q.set('art', f.art.value); }
    const d = await api(`/api/v1/suche?${q}`);
    zeigeListe({ aufnahmen: d.aufnahmen, suche: true });
    $('suche-hinweis').textContent = d.aufnahmen.length ? '' : t('Nichts gefunden.');
  } catch (x) {
    $('suche-hinweis').textContent = x.status === 404
      ? t('Der Server hat kein Modell für die Bildsuche – suche nach Text.')
      : x.message;
  }
});

async function zeigeKonto() {
  markiereNav('konto');
  zeigeBereich(['konto']);
  const k = await api('/api/v1/konto');
  $('konto-wer').textContent = `${k.name}${k.verwalter ? ` · ${t('Verwalter')}` : ''}${k.totp ? ` · ${t('TOTP eingerichtet')}` : ''}`;
  $('passwort-code-feld').hidden = !k.totp;
  zeigeFassung($('konto-fassung'));
  $('verwaltung').hidden = !k.verwalter;
  if (k.verwalter) zeigeVerwaltung().catch((x) => { $('server-stand').replaceChildren(el('li', null, x.message)); });
  zeigeFreigaben().catch((x) => $('freigaben').replaceChildren(el('li', 'fehler', x.message)));
  zeigeBeitraege().catch(() => {});
  const g = await api('/api/v1/geraete');
  const ul = $('geraete');
  ul.replaceChildren();
  for (const x of g.geraete) {
    const li = el('li');
    const dieses = x.id === sitzung.geraet;
    li.append(el('span', null, `${x.name}${dieses ? ` ${t('(dieser Browser)')}` : ''} · ${t('zuletzt {datum}', { datum: datumZeit.format(new Date(x.zuletzt)) })}${x.adresse ? ' · ' + x.adresse : ''}`));
    const b = el('button', null, dieses ? t('Abmelden') : t('Gerät abmelden'));
    b.type = 'button';
    b.addEventListener('click', async () => {
      if (dieses) return abmelden();
      if (!confirm(t('„{name}“ abmelden?', { name: x.name }))) return;
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
  if (f.neu.value !== f.neu2.value) { m.textContent = t('Die neuen Passwörter stimmen nicht überein.'); return; }
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
    m.textContent = t('Passwort geändert.');
  } catch (x) { m.textContent = x.message; }
});

async function zeigeFassung(ziel) {
  try {
    const z = await api('/api/v1/zustand');
    ziel.textContent = `${t('Server')} ${z.fassung || '?'}${z.commit ? ' (' + z.commit + ')' : ''} · ${t('Protokoll')} ${z.protokoll}`;
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
  await ladeLeaflet();
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
      karteGruppe = { aufnahmen: r.aufnahmen, titel: t(g.anzahl === 1 ? '{n} Aufnahme an diesem Ort' : '{n} Aufnahmen an diesem Ort', { n: g.anzahl }) };
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
    zeile(t('Speicher: {frei} frei von {gesamt}', { frei: gb(sp.frei), gesamt: gb(sp.gesamt) }) + (sp.stufe !== 'ok' ? ' – ' + t(sp.stufe) : ''));
  } catch (_) { /* kein Speicherwächter */ }
  try {
    const sv = await api('/api/v1/sicherung');
    zeile(t('Sicherung: {stufe}', { stufe: t(sv.stufe) }) + (sv.letzterErfolg ? ' · ' + t('zuletzt {datum}', { datum: datumZeit.format(new Date(sv.letzterErfolg)) }) : '') + (sv.naechster ? ' · ' + t('nächste {datum}', { datum: datumZeit.format(new Date(sv.naechster)) }) : '') + (sv.fehler ? ' · ' + sv.fehler : ''));
    $('sicherung-jetzt').hidden = sv.stufe === 'aus' || sv.stufe === 'nichtEingerichtet';
  } catch (_) { $('sicherung-jetzt').hidden = true; }
  try {
    const a = await api('/api/v1/auswertung');
    zeile(a.laeuft && a.stand ? t('Auswertung läuft: {stufe} ({nr}/{von}), {erledigt} von {gesamt}', { stufe: a.stand.stufe, nr: a.stand.stufeNummer, von: a.stand.stufenGesamt, erledigt: a.stand.erledigt, gesamt: a.stand.gesamt }) : t('Auswertung: nichts offen'));
  } catch (_) { /* ohne Modelle */ }
  const kl = $('konten');
  kl.replaceChildren();
  const d = await api('/api/v1/konten');
  for (const k of d.konten) {
    const li = el('li');
    li.append(el('span', null, `${k.name}${k.verwalter ? ` · ${t('Verwalter')}` : ''}${k.totp ? ' · TOTP' : ''}${k.gesperrt ? ` · ${t('gesperrt')}` : ''} · ${t(k.geraete === 1 ? '{n} Gerät' : '{n} Geräte', { n: k.geraete })}${k.du ? ` · ${t('du')}` : ''}`));
    const kn = el('span');
    if (k.gesperrt) { const b = el('button', null, t('Entsperren')); b.type = 'button'; b.addEventListener('click', async () => { await api(`/api/v1/konten/${encodeURIComponent(k.id)}/entsperren`, { methode: 'POST', json: {} }); zeigeVerwaltung(); }); kn.append(b); }
    if (!k.du) { const b = el('button', null, t('Entfernen')); b.type = 'button'; b.addEventListener('click', async () => { if (!confirm(t('„{name}“ entfernen? Die Bibliothek bleibt auf dem Server liegen.', { name: k.name }))) return; try { await api(`/api/v1/konten/${encodeURIComponent(k.id)}`, { methode: 'DELETE' }); zeigeVerwaltung(); } catch (x) { alert(x.message); } }); kn.append(b); }
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
  const a = liste && liste.aufnahmen[Number(k.dataset.index)];
  zeichneTage(a ? [tagVon(a)] : undefined);
  zeigeAuswahl();
}

// Der ganze Tag – sind schon alle gewählt, fallen sie wieder heraus.
function schalteTag(tag) {
  const ids = liste && liste.tage.get(tag);
  if (!ids || !ids.length) return;
  const alle = ids.every((id) => auswahl.has(id));
  for (const id of ids) { if (alle) auswahl.delete(id); else auswahl.add(id); }
  zeichneAuswahl();
}

// Der Kreis am Tageskopf ist voll, wenn der ganze Tag gewählt ist – für
// alle Tage oder nur die genannten.
function zeichneTage(nur) {
  if (!liste || !liste.koepfe) return;
  for (const tag of nur || liste.koepfe.keys()) {
    const h = liste.koepfe.get(tag);
    if (!h) continue;
    const ids = liste.tage.get(tag) || [];
    const alle = ids.length > 0 && ids.every((id) => auswahl.has(id));
    h.classList.toggle('alle', alle);
    h.title = alle ? t('Ganzen Tag abwählen') : t('Ganzen Tag auswählen');
  }
}

// Alle Kacheln oder nur die von `von` bis `bis` (samt ihren Tagen). Beim
// Ziehen ändert sich nur dieser Bereich; jedes Mal alle abzulaufen
// kostete bei 6000 geladenen Kacheln 8 ms je Schritt am Rechner.
function zeichneAuswahl(von, bis) {
  if (liste && liste.kacheln) {
    const ganz = von === undefined;
    const a0 = ganz ? 0 : Math.max(0, von), a1 = ganz ? liste.kacheln.length - 1 : Math.min(bis, liste.kacheln.length - 1);
    const tage = ganz ? undefined : new Set();
    for (let i = a0; i <= a1; i++) {
      const a = liste.aufnahmen[i];
      liste.kacheln[i].classList.toggle('gewaehlt', !!a && auswahl.has(a.id));
      if (tage && a) tage.add(tagVon(a));
    }
    zeichneTage(tage);
  }
  zeigeAuswahl();
}

function zeigeAuswahl() {
  const n = auswahl.size;
  const war = !$('auswahlleiste').hidden;
  $('auswahlleiste').hidden = n === 0;
  if (n > 0 && !war) ladeAlbenstreifen();
  $('auswahl-anzahl').textContent = t('{n} ausgewählt', { n });
  $('auswaehlen').classList.toggle('aktiv', auswahlModus);
  document.body.classList.toggle('mit-leiste', n > 0);
  document.body.classList.toggle('waehlt', auswahlModus || n > 0);
}

function auswahlAufheben() {
  auswahl.clear();
  auswahlModus = false;
  for (const k of $('raster').querySelectorAll('.kachel.gewaehlt')) k.classList.remove('gewaehlt');
  zeichneTage();
  zeigeAuswahl();
}

// --- Ziehen zum Auswählen --------------------------------------------------
//
// Wie auf dem Telefon: langes Drücken wählt eine Aufnahme, und wer danach
// weiterzieht, nimmt alles bis dorthin mit – oder wählt ab, wenn die erste
// schon gewählt war. Mit der Maus geht es, solange ausgewählt wird, auch
// ohne Warten. Am oberen und unteren Rand rollt das Raster weiter.

const zieh = { anker: null, letzter: null, waehlt: true, vorher: null, x: 0, y: 0, art: null, rollen: null, schlucke: false, von: 0, zu: -1 };
let druck = null;
let halteUhr = null;

function ziehBeginn(i, art) {
  const a = liste && liste.aufnahmen[i];
  clearTimeout(halteUhr);
  druck = null;
  if (!a) return;
  auswahlModus = true;
  Object.assign(zieh, { anker: i, letzter: i, art, waehlt: !auswahl.has(a.id), vorher: new Set(auswahl), schlucke: true, von: i, zu: i });
  if (navigator.vibrate) navigator.vibrate(8);
  wendeAn(i);
}

function wendeAn(bis) {
  const von = Math.min(zieh.anker, bis), zu = Math.max(zieh.anker, bis);
  // Was vorher im Bereich lag, bekommt seinen alten Stand zurück; nur der
  // alte und der neue Bereich zusammen müssen neu gezeichnet werden.
  for (let i = zieh.von; i <= zieh.zu; i++) {
    const id = liste.aufnahmen[i].id;
    if (zieh.vorher.has(id)) auswahl.add(id); else auswahl.delete(id);
  }
  for (let i = von; i <= zu; i++) {
    const id = liste.aufnahmen[i].id;
    if (zieh.waehlt) auswahl.add(id); else auswahl.delete(id);
  }
  const a0 = Math.min(von, zieh.von), a1 = Math.max(zu, zieh.zu);
  zieh.von = von;
  zieh.zu = zu;
  zeichneAuswahl(a0, a1);
}

function folge() {
  const ziel = document.elementFromPoint(zieh.x, zieh.y);
  const k = ziel && ziel.closest ? ziel.closest('#raster .kachel') : null;
  if (!k) return;
  const i = Number(k.dataset.index);
  if (i === zieh.letzter || !liste.aufnahmen[i]) return;
  zieh.letzter = i;
  wendeAn(i);
}

// -1 oben am Rand, 1 unten, sonst 0.
function randRichtung() {
  const oben = $('kopf').getBoundingClientRect().bottom + 56;
  const unten = innerHeight - untenBelegt() - 56;
  return zieh.y < oben ? -1 : zieh.y > unten ? 1 : 0;
}

function pruefeRand() {
  if (randRichtung() === 0) { clearInterval(zieh.rollen); zieh.rollen = null; return; }
  if (zieh.rollen) return;
  zieh.rollen = setInterval(() => {
    const r = randRichtung();
    if (r === 0 || zieh.anker === null) { clearInterval(zieh.rollen); zieh.rollen = null; return; }
    window.scrollBy(0, r * 14);
    folge();
  }, 16);
}

function ziehEnde() {
  clearTimeout(halteUhr);
  druck = null;
  if (zieh.anker === null) return;
  const art = zieh.art;
  Object.assign(zieh, { anker: null, letzter: null, art: null });
  clearInterval(zieh.rollen);
  zieh.rollen = null;
  // Der Klick, der dem Loslassen folgt, kommt mit der Maus in derselben
  // Runde, nach einem Finger etwas später.
  setTimeout(() => { zieh.schlucke = false; }, art === 'touch' ? 400 : 0);
}

$('raster').addEventListener('pointerdown', (e) => {
  const k = e.target.closest('.kachel');
  if (!k || e.button > 0 || kneif) return;
  druck = { index: Number(k.dataset.index), x: e.clientX, y: e.clientY, art: e.pointerType };
  clearTimeout(halteUhr);
  halteUhr = setTimeout(() => { if (druck) ziehBeginn(druck.index, druck.art); }, 500);
});
document.addEventListener('pointermove', (e) => {
  if (zieh.anker !== null) {
    if (zieh.art === 'touch') return; // kommt über touchmove
    zieh.x = e.clientX; zieh.y = e.clientY;
    folge();
    pruefeRand();
    return;
  }
  if (!druck || Math.hypot(e.clientX - druck.x, e.clientY - druck.y) < 8) return;
  if (druck.art === 'mouse' && (auswahlModus || auswahl.size)) {
    ziehBeginn(druck.index, 'mouse');
    zieh.x = e.clientX; zieh.y = e.clientY;
    folge();
    return;
  }
  // Bewegt, bevor die Zeit um war: Das ist Rollen, kein Halten.
  clearTimeout(halteUhr);
  druck = null;
});
document.addEventListener('pointerup', ziehEnde);
// Rollt der Browser, bricht er den Zeiger ab – beim Ziehen mit dem Finger
// nicht, das hält touchmove auf.
document.addEventListener('pointercancel', () => { if (zieh.anker === null || zieh.art !== 'touch') ziehEnde(); });
// Mit dem Finger: Solange gezogen wird, darf die Seite nicht rollen.
document.addEventListener('touchmove', (e) => {
  if (zieh.anker === null || zieh.art !== 'touch') return;
  e.preventDefault();
  zieh.x = e.touches[0].clientX; zieh.y = e.touches[0].clientY;
  folge();
  pruefeRand();
}, { passive: false });
document.addEventListener('touchend', (e) => { if (e.touches.length === 0) ziehEnde(); });
// Langes Drücken öffnet sonst das Menü des Bildes.
$('raster').addEventListener('contextmenu', (e) => { if (e.target.closest('.kachel')) e.preventDefault(); });

// --- Spalten ----------------------------------------------------------------
//
// Zwei Finger auseinander: weniger, grössere Kacheln; zusammen: mehr. Am
// Rechner dasselbe mit Strg und Mausrad oder zwei Fingern auf dem Trackpad.
// Die Zahl gilt für diesen Browser.

const SPALTEN_MERKER = 'pv-spalten';
let spalten = (() => { try { const n = Number(localStorage.getItem(SPALTEN_MERKER)); return n >= 2 ? n : null; } catch (_) { return null; } })();
let kneif = null;

const meisteSpalten = () => Math.max(6, Math.floor($('raster').clientWidth / 80));
const spaltenJetzt = () => spalten || getComputedStyle($('raster')).gridTemplateColumns.split(' ').filter(Boolean).length;

function setzeSpalten(n, merken) {
  const r = $('raster');
  const ziel = Math.min(meisteSpalten(), Math.max(2, Math.round(n)));
  if (ziel !== spalten) {
    // Ungefähr dieselbe Stelle im Raster danach.
    const vorher = document.documentElement.scrollHeight - innerHeight;
    const anteil = vorher > 0 ? scrollY / vorher : 0;
    spalten = ziel;
    r.style.setProperty('--spalten', String(ziel));
    r.classList.add('feste-spalten');
    window.scrollTo(0, anteil * (document.documentElement.scrollHeight - innerHeight));
  }
  if (merken) { try { localStorage.setItem(SPALTEN_MERKER, String(spalten)); } catch (_) { /* privat */ } }
}
if (spalten) { $('raster').style.setProperty('--spalten', String(spalten)); $('raster').classList.add('feste-spalten'); }

const fingerAbstand = (ts) => Math.hypot(ts[0].clientX - ts[1].clientX, ts[0].clientY - ts[1].clientY);
$('raster').addEventListener('touchstart', (e) => {
  if (e.touches.length !== 2) return;
  clearTimeout(halteUhr);
  druck = null;
  kneif = { abstand: fingerAbstand(e.touches), spalten: spaltenJetzt() };
}, { passive: true });
$('raster').addEventListener('touchmove', (e) => {
  if (!kneif || e.touches.length !== 2) return;
  e.preventDefault();
  if (kneif.abstand < 30) return;
  setzeSpalten(kneif.spalten / (fingerAbstand(e.touches) / kneif.abstand), false);
}, { passive: false });
$('raster').addEventListener('touchend', (e) => {
  if (!kneif || e.touches.length >= 2) return;
  kneif = null;
  if (spalten) setzeSpalten(spalten, true);
});
let radRest = 0;
$('raster').addEventListener('wheel', (e) => {
  if (!e.ctrlKey) return;
  e.preventDefault();
  // Eine Raste des Mausrads ist eine Spalte; das Trackpad liefert viele
  // kleine Schritte, die sich erst sammeln.
  radRest += e.deltaY;
  if (Math.abs(radRest) < 40) return;
  const schritt = Math.sign(radRest);
  radRest = 0;
  setzeSpalten(spaltenJetzt() + schritt, true);
}, { passive: false });
// Safari meldet das Kneifen auf dem Trackpad als eigene Geste.
let gesteVon = null;
$('raster').addEventListener('gesturestart', (e) => { e.preventDefault(); if (!kneif) gesteVon = spaltenJetzt(); });
$('raster').addEventListener('gesturechange', (e) => { e.preventDefault(); if (gesteVon && !kneif) setzeSpalten(gesteVon / e.scale, false); });
$('raster').addEventListener('gestureend', (e) => { e.preventDefault(); if (gesteVon && spalten) setzeSpalten(spalten, true); gesteVon = null; });

// --- Bildlaufleiste -----------------------------------------------------------
//
// Rechts am Rand: erscheint beim Rollen, verschwindet nach einer Pause; wer
// den Griff zieht, springt durch das Raster und sieht oben den Monat.

const bildlauf = { aus: null, zieht: false };

// Was unten über dem Raster liegt: das Auswahlblatt oder, am schmalen
// Bildschirm, die Reiter.
function untenBelegt() {
  const leiste = $('auswahlleiste').hidden ? 0 : $('auswahlleiste').getBoundingClientRect().height;
  const n = $('nav').getBoundingClientRect();
  const reiter = !$('nav').hidden && n.top > innerHeight / 2 ? n.height : 0;
  return Math.max(leiste, reiter);
}

function bildlaufHoehe() { return document.documentElement.scrollHeight - innerHeight; }

function zeigeBildlauf() {
  const b = $('bildlauf');
  const lang = !$('bereich-raster').hidden && $('betrachter').hidden && liste && liste.aufnahmen.length > 0 && bildlaufHoehe() > innerHeight * 2;
  if (!lang) { b.classList.remove('sichtbar'); return; }
  // Erst lesen, dann nur schreiben, was sich geändert hat: Jedes Setzen
  // verwarf das Layout, und das Lesen gleich danach rechnete es neu – bei
  // jedem Bildlauf-Ereignis zweimal.
  const oben = `${$('kopf').getBoundingClientRect().bottom + 6}px`;
  const unten = `${untenBelegt() + 12}px`;
  if (b.style.top !== oben) b.style.top = oben;
  if (b.style.bottom !== unten) b.style.bottom = unten;
  b.classList.add('sichtbar');
  setzeGriff();
  clearTimeout(bildlauf.aus);
  if (!bildlauf.zieht) bildlauf.aus = setTimeout(() => { if (!bildlauf.zieht) b.classList.remove('sichtbar'); }, 1500);
}

function setzeGriff() {
  const b = $('bildlauf'), g = $('bildlauf-griff');
  const raum = b.clientHeight - g.offsetHeight;
  const max = bildlaufHoehe();
  const anteil = max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
  g.style.transform = `translateY(${anteil * raum}px)`;
  $('bildlauf-monat').style.transform = `translateY(${anteil * raum}px)`;
}

// Der Monat der obersten sichtbaren Kachel.
function monatOben() {
  const oben = $('kopf').getBoundingClientRect().bottom;
  const x = $('raster').getBoundingClientRect().left + 24;
  for (let y = oben + 8; y < oben + 260; y += 24) {
    const ziel = document.elementFromPoint(x, y);
    const k = ziel && ziel.closest ? ziel.closest('#raster .kachel') : null;
    const a = k && liste.aufnahmen[Number(k.dataset.index)];
    if (a) return monatJahr.format(new Date(a.aufgenommen));
  }
  return null;
}

function zieheBildlauf(y) {
  const b = $('bildlauf').getBoundingClientRect(), g = $('bildlauf-griff').offsetHeight;
  const anteil = Math.min(1, Math.max(0, (y - b.top - g / 2) / (b.height - g)));
  window.scrollTo(0, anteil * bildlaufHoehe());
  const m = monatOben();
  if (m) { $('bildlauf-monat').textContent = m; $('bildlauf-monat').hidden = false; }
  setzeGriff();
}

let bildlaufGeplant = false;
window.addEventListener('scroll', () => {
  if (bildlaufGeplant) return;
  bildlaufGeplant = true;
  requestAnimationFrame(() => { bildlaufGeplant = false; zeigeBildlauf(); });
}, { passive: true });
$('bildlauf-griff').addEventListener('pointerdown', (e) => {
  e.preventDefault();
  try { $('bildlauf-griff').setPointerCapture(e.pointerId); } catch (_) { /* ohne geht es auch */ }
  bildlauf.zieht = true;
  clearTimeout(bildlauf.aus);
  $('bildlauf').classList.add('zieht');
  zieheBildlauf(e.clientY);
});
$('bildlauf-griff').addEventListener('pointermove', (e) => { if (bildlauf.zieht) zieheBildlauf(e.clientY); });
for (const ev of ['pointerup', 'pointercancel']) {
  $('bildlauf-griff').addEventListener(ev, () => {
    if (!bildlauf.zieht) return;
    bildlauf.zieht = false;
    $('bildlauf').classList.remove('zieht');
    $('bildlauf-monat').hidden = true;
    zeigeBildlauf();
  });
}

// --- Meldung, Teilen, Albenstreifen -----------------------------------------

let meldungAus = null;
function meldung(text, bleibt) {
  const m = $('meldung');
  clearTimeout(meldungAus);
  m.textContent = text || '';
  m.hidden = !text;
  if (text && !bleibt) meldungAus = setTimeout(() => { m.hidden = true; }, 3500);
}

// Teilen geht nur, wo der Browser Dateien an andere Apps geben kann – auf
// dem Telefon und in Safari meist ja, am Rechner oft nicht.
const teilenMoeglich = (() => {
  try { return !!navigator.canShare && navigator.canShare({ files: [new File(['x'], 'x.jpg', { type: 'image/jpeg' })] }); } catch (_) { return false; }
})();
let geteiltBereit = null;

async function teile(aufnahmen) {
  const schluessel = aufnahmen.map((a) => a.id).join(',');
  // Safari lässt Teilen nur direkt nach einem Tipp zu; nach dem Laden ist
  // der vorbei. Dann liegt alles bereit, und der nächste Tipp teilt.
  if (geteiltBereit && geteiltBereit.schluessel === schluessel) {
    const dateien = geteiltBereit.dateien;
    geteiltBereit = null;
    meldung('');
    try { await navigator.share({ files: dateien }); return true; } catch (x) { if (x.name !== 'AbortError') meldung(x.message); return false; }
  }
  meldung(t('Lade …'), true);
  const dateien = [];
  try {
    for (const a of aufnahmen) {
      const r = await fetch(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/original`, { credentials: 'same-origin' });
      if (!r.ok) throw new Error(t('Fehler {n}', { n: r.status }));
      const b = await r.blob();
      dateien.push(new File([b], a.name || a.id, { type: b.type || 'application/octet-stream', lastModified: Date.parse(a.aufgenommen) || Date.now() }));
    }
  } catch (x) { meldung(x.message); return false; }
  if (!navigator.canShare({ files: dateien })) { meldung(t('Dieses Format kann der Browser nicht teilen.')); return false; }
  try {
    await navigator.share({ files: dateien });
    meldung('');
    return true;
  } catch (x) {
    if (x.name === 'NotAllowedError') { geteiltBereit = { schluessel, dateien }; meldung(t('Bereit – zum Teilen noch einmal tippen.'), true); return false; }
    meldung(x.name === 'AbortError' ? '' : x.message);
    return false;
  }
}

// In ein Album mit einem Tipp – der Streifen unter den Aktionen, wie auf
// dem Telefon. Das Feld „Album“ mit der Liste bleibt daneben.
async function ladeAlbenstreifen() {
  const feld = $('auswahl-alben-feld'), reihe = $('auswahl-alben');
  feld.hidden = !!(liste && liste.papierkorb);
  if (feld.hidden) return;
  reihe.replaceChildren(albumkachel(null));
  let d;
  try { d = await api('/api/v1/alben'); } catch (_) { return; }
  for (const a of d.alben) reihe.append(albumkachel(a));
}

function albumkachel(a) {
  const k = el('button', 'albumkachel');
  k.type = 'button';
  const bild = el('span', 'bild', a ? undefined : '+');
  if (a && a.titelbild) { const img = el('img'); img.alt = ''; img.loading = 'lazy'; img.src = miniaturUrl(a.titelbild); bild.append(img); }
  k.append(bild, el('span', 'name', a ? a.name : t('Neues Album')));
  k.addEventListener('click', () => (a ? insAlbum(a.id, a.name) : neuesAlbum()));
  return k;
}

async function insAlbum(albumId, name) {
  const g = gewaehlte();
  try {
    await befehl('albumFuellen', { albumId, ids: g.map((x) => x.id) });
    auswahlAufheben();
    meldung(t('{n} im Album „{name}“', { n: g.length, name }));
  } catch (x) { meldung(x.message); }
}

async function neuesAlbum() {
  try { await zeigeAlbumDialog(); $('form-album').neu.focus(); } catch (x) { meldung(x.message); }
}

$('auswahl-teilen').hidden = !teilenMoeglich;
$('auswahl-teilen').addEventListener('click', async () => { if (await teile(gewaehlte())) auswahlAufheben(); });

$('auswaehlen').addEventListener('click', () => { auswahlModus = !auswahlModus; if (!auswahlModus) auswahlAufheben(); else zeigeAuswahl(); });
$('auswahl-zu').addEventListener('click', auswahlAufheben);

const gewaehlte = () => liste.aufnahmen.filter((a) => auswahl.has(a.id));

$('auswahl-favorit').addEventListener('click', async () => {
  const g = gewaehlte();
  const alle = g.every((a) => a.favorit);
  try {
    await befehl('favoritSetzen', { ids: g.map((a) => a.id), favorit: !alle });
    for (const a of g) a.favorit = !alle;
    if (liste.favoriten && alle) { const weg = new Set(g.map((a) => a.id)); liste.aufnahmen = liste.aufnahmen.filter((a) => !weg.has(a.id)); auswahlAufheben(); }
    neuZeichnen();
  } catch (x) { alert(x.message); }
});

$('auswahl-link').addEventListener('click', () => {
  const g = gewaehlte();
  if (!g.length) return;
  oeffneLinkDialog({ ids: g.map((a) => a.id) }, g.length === 1 ? t('1 Aufnahme') : t('{n} Aufnahmen', { n: g.length }));
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
  if (!confirm(g.length === 1 ? t('Eine Aufnahme in den Papierkorb legen? Sie verschwindet überall – zurückholen geht am Rechner und hier im Papierkorb.') : t('{n} Aufnahmen in den Papierkorb legen? Sie verschwinden überall – zurückholen geht am Rechner und hier im Papierkorb.', { n: g.length }))) return;
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
    $('ende').textContent = t('{n} zurückgeholt', { n: g.length });
  } catch (x) { alert(x.message); }
});

async function zeigeAlbumDialog() {
  const d = await api('/api/v1/alben');
  const ul = $('album-liste');
  ul.replaceChildren();
  for (const a of d.alben) {
    const li = el('li');
    const lab = el('label');
    const r = el('input'); r.type = 'radio'; r.name = 'album'; r.value = a.id; r.dataset.name = a.name;
    lab.append(r, document.createTextNode(` ${a.name} (${a.anzahl})`));
    li.append(lab);
    ul.append(li);
  }
  $('form-album').neu.value = '';
  $('album-dialog').showModal();
}
$('auswahl-album').addEventListener('click', () => zeigeAlbumDialog().catch((x) => meldung(x.message)));
$('album-abbrechen').addEventListener('click', () => $('album-dialog').close());
$('form-album').addEventListener('submit', async (e) => {
  const f = e.target;
  const g = gewaehlte();
  const neu = f.neu.value.trim();
  // Nicht über `f.album`: Bei genau einem Album ist das der eine Knopf
  // statt einer Liste – sein `value` steht dann auch ohne Haken, und
  // darüber zu laufen warf „f.album is not iterable“.
  const knopf = f.querySelector('input[name="album"]:checked');
  const gewaehlt = knopf ? knopf.value : '';
  if (!neu && !gewaehlt) { e.preventDefault(); return; }
  try {
    let albumId = gewaehlt;
    let name = knopf ? knopf.dataset.name : neu;
    if (neu) {
      albumId = neueKennung();
      name = neu;
      await befehl('albumAnlegen', { albumId, name, angelegtAm: new Date().toISOString() });
    }
    await befehl('albumFuellen', { albumId, ids: g.map((a) => a.id) });
    auswahlAufheben();
    meldung(t('{n} im Album „{name}“', { n: g.length, name }));
  } catch (x) { alert(x.message); }
});

function neuZeichnen() {
  if (!liste) return;
  const alt = liste;
  zeigeListe({ aufnahmen: alt.aufnahmen, nachTagen: alt.nachTagen, mehr: alt.mehr, suche: alt.suche, papierkorb: alt.papierkorb, favoriten: alt.favoriten, kopf: alt.kopf }, $('raster-titel').hidden ? null : $('raster-titel').textContent);
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
  videoLauf++;
  liveSpielt = false;
  $('live').classList.remove('aktiv');
  $('video-hinweis').hidden = true;
  video.controls = true;
  video.onended = null;
  if (a.art === 'video') {
    bild.hidden = true;
    video.hidden = false;
    spieleVideo(a.id);
  } else {
    video.hidden = true;
    bild.hidden = false;
    bild.src = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/ansicht`;
  }
  $('bearbeiten').hidden = a.art === 'video';
  const korb = !!liste.papierkorb;
  $('favorit').hidden = korb;
  $('weg').hidden = korb;
  $('holen').hidden = !korb;
  $('teilen').hidden = !teilenMoeglich;
  $('live').hidden = !(a.art !== 'video' && a.partner);
  // Spielt dieser Browser kein HEVC, die Fassung des Bewegungsteils schon
  // jetzt anstossen – dann ist sie da, wenn man auf LIVE zeigt.
  if (a.art !== 'video' && a.partner && !kannHevc) fetch(fassungUrl(a.partner, true), { credentials: 'same-origin' }).catch(() => {});
  ordneKnoepfe();
  blickZurueck(false);
  $('betrachter').classList.remove('still');
  $('betrachter').style.removeProperty('background');
  $('angaben').textContent = `${datumZeit.format(new Date(a.aufgenommen))} · ${a.name}`;
  $('favorit').textContent = a.favorit ? '♥' : '♡';
  $('laden').href = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/original`;
  $('laden').download = a.name || '';
  $('betrachter').hidden = false;
  zeigeAngaben();
  if (i >= liste.aufnahmen.length - 20) ladeMehr();
}

// --- Videos, die der Browser nicht abspielt ---------------------------------
//
// Das iPhone filmt in HEVC; Chrome unter Linux, Firefox und manches
// Chromium spielen das nicht ab – das Video meldet einen Fehler oder bleibt
// schwarz (Breite 0). Dann holt der Betrachter die H.264-Fassung des
// Servers. Die entsteht beim ersten Mal; bis dahin steht ein Hinweis da.

// Nur mit vollem Profil ehrlich: Ein blosses „hvc1“ verneint auch ein
// Browser, der HEVC abspielt. Main 10 für die HDR-Videos des iPhones.
const kannHevc = (() => {
  const v = document.createElement('video');
  return ['hvc1.1.6.L93.B0', 'hvc1.2.4.L123.B0'].every((c) => v.canPlayType(`video/mp4; codecs="${c}"`));
})();
let videoLauf = 0;
const fassungUrl = (id, pruefen) => `/api/v1/aufnahmen/${encodeURIComponent(id)}/abspielbar${pruefen ? '?pruefen=1' : ''}`;

function videoHinweis(text) {
  $('video-hinweis').textContent = text || '';
  $('video-hinweis').hidden = !text;
}

function spieleVideo(id, { live = false } = {}) {
  const video = $('video');
  const lauf = videoLauf;
  const original = `/api/v1/aufnahmen/${encodeURIComponent(id)}/wiedergabe`;
  let gewechselt = false;
  const wechsle = () => {
    if (gewechselt || lauf !== videoLauf) return;
    gewechselt = true;
    holeFassung(id, lauf, live);
  };
  video.onerror = () => { if (video.getAttribute('src') === original) wechsle(); };
  video.onloadedmetadata = () => { if (video.getAttribute('src') === original && video.videoWidth === 0) wechsle(); };
  // Ohne HEVC gleich die Fassung: Ein Bewegungsteil vom iPhone ist immer
  // HEVC, und ein Fehlversuch kostete hier nur Zeit.
  if (live && !kannHevc) { wechsle(); return; }
  video.src = original;
  if (live) video.play().catch(() => {});
}

async function holeFassung(id, lauf, live) {
  const video = $('video');
  if (!live) videoHinweis(t('Das Video wird für diesen Browser umgewandelt …'));
  for (let i = 0; i < 900 && lauf === videoLauf; i++) {
    let r;
    try { r = await fetch(fassungUrl(id, true), { credentials: 'same-origin' }); } catch (_) { break; }
    if (r.status === 200) {
      if (lauf !== videoLauf) return;
      videoHinweis('');
      video.src = fassungUrl(id, false);
      if (live) video.play().catch(() => {});
      return;
    }
    if (r.status !== 202) break;
    await new Promise((fertig) => setTimeout(fertig, 1000));
  }
  if (lauf === videoLauf && !live) videoHinweis(t('Dieses Video lässt sich im Browser nicht abspielen – „Herunterladen“ holt das Original.'));
}

// Live Photos: Zeigen oder Halten auf LIVE spielt den Bewegungsteil an der
// Stelle des Bildes, Loslassen zeigt wieder das Foto – wie die
// Schwebevorschau am Rechner und das Halten auf dem Telefon.
let liveSpielt = false;
function liveAn() {
  const a = liste && liste.aufnahmen[offen];
  if (!a || !a.partner || liveSpielt) return;
  liveSpielt = true;
  const video = $('video');
  videoLauf++;
  video.controls = false;
  video.loop = false;
  video.onended = liveAus;
  $('bild').hidden = true;
  video.hidden = false;
  $('live').classList.add('aktiv');
  spieleVideo(a.partner, { live: true });
}
function liveAus() {
  if (!liveSpielt) return;
  liveSpielt = false;
  const video = $('video');
  videoLauf++;
  video.pause();
  video.onended = null;
  video.removeAttribute('src');
  video.load();
  video.hidden = true;
  video.controls = true;
  $('bild').hidden = false;
  $('live').classList.remove('aktiv');
}
$('live').addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') liveAn(); });
$('live').addEventListener('pointerleave', liveAus);
$('live').addEventListener('pointerdown', (e) => { e.preventDefault(); liveAn(); });
$('live').addEventListener('pointerup', (e) => { if (e.pointerType !== 'mouse') liveAus(); });
$('live').addEventListener('pointercancel', liveAus);
$('live').addEventListener('click', (e) => e.stopPropagation());

// --- Angaben zur Aufnahme --------------------------------------------------
// Dieselben Zeilen wie die Info-Ansicht des Rechners: Datum, Datei, Kamera,
// Ort, Personen, Schlagwörter, Alben, Beschreibung, Bewertung, Serie.

let angabenOffen = false;
const landname = (() => { try { return new Intl.DisplayNames(GEBIET, { type: 'region' }); } catch (_) { return null; } })();
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
  feld.replaceChildren(el('p', 'neben', t('Lade …')));
  let d;
  try { d = await api(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/angaben?sprache=${SPRACHE}`); } catch (x) { feld.replaceChildren(el('p', 'fehler', x.message)); return; }
  if (!liste || liste.aufnahmen[offen] !== a) return; // inzwischen weitergeblättert
  const teile = [];
  teile.push(el('h3', null, t('Angaben')));
  teile.push(reihe('📅', datumZeit.format(new Date(d.aufgenommen)), d.datumGeschaetzt ? t('Datum geschätzt') : null));
  const datei = [d.breite && d.hoehe ? `${d.breite} × ${d.hoehe}` : '', d.bytes ? groesse(d.bytes) : '', d.format ? d.format.toUpperCase() : '', d.dauer ? `${Math.round(d.dauer)} s` : '', d.bearbeitet ? t('bearbeitet') : ''].filter(Boolean).join(' · ');
  teile.push(reihe('🖼', d.name, datei));
  const k = d.kamera;
  if (k.modell || k.hersteller) {
    const modell = k.modell && k.hersteller && k.modell.toLowerCase().startsWith(k.hersteller.toLowerCase()) ? k.modell : [k.hersteller, k.modell].filter(Boolean).join(' ');
    const werte = [k.brennweite ? `${k.brennweite} mm` : '', k.blende ? `f/${k.blende}` : '', k.belichtung ? belichtung(k.belichtung) : '', k.iso ? `ISO ${k.iso}` : ''].filter(Boolean).join(' · ');
    teile.push(reihe('📷', modell, [k.objektiv, werte].filter(Boolean).join('\n')));
  }
  if (d.ort) {
    const name = [d.ort.stadt, d.ort.region, land(d.ort.land)].filter(Boolean).join(', ');
    teile.push(reihe('📍', name || t('Standort bekannt'), `${d.ort.breite.toFixed(5)}, ${d.ort.laenge.toFixed(5)}${d.ort.geerbt ? ` · ${t('vom Nachbarfoto übernommen')}` : ''}`));
  }
  if (d.personen.length) teile.push(reihe('👤', verweise(d.personen, '#/personen')));
  if (d.gesichter && d.gesichter.length) teile.push(reihe('🙂', gesichterReihe(d.gesichter), t('Antippen, um zu benennen oder zu ändern')));
  if (d.schlagwoerter.length) { const box = el('div'); for (const t of d.schlagwoerter) box.append(el('span', 'marke', t.name)); teile.push(reihe('🏷', box)); }
  if (d.alben.length) teile.push(reihe('📚', verweise(d.alben, '#/alben')));
  // Beschreibung – änderbar, über denselben Befehl wie am Rechner.
  const text = el('textarea');
  text.value = d.beschreibung || '';
  text.placeholder = t('Beschreibung');
  const speichern = el('button', 'speichern', t('Speichern'));
  speichern.type = 'button';
  speichern.addEventListener('click', async () => {
    try { await befehl('beschreibungSetzen', { ids: [a.id], beschreibung: text.value }); speichern.textContent = t('Gespeichert'); } catch (x) { speichern.textContent = x.message; }
  });
  text.addEventListener('input', () => { speichern.textContent = t('Speichern'); });
  const beschr = el('div', 'beschreibung');
  beschr.append(text, speichern);
  teile.push(reihe('✎', beschr, d.kiBeschreibung ? t('Automatisch: {text}', { text: d.kiBeschreibung }) : null));
  // Bewertung
  const sterne = el('div', 'sterne');
  const male = (n) => { for (const [i, b] of [...sterne.children].entries()) b.classList.toggle('voll', i < n); };
  for (let i = 1; i <= 5; i++) {
    const b = el('button', null, '★');
    b.type = 'button';
    b.title = t('{i} von 5', { i });
    b.addEventListener('click', async () => {
      const neu = d.bewertung === i ? 0 : i;
      try { await befehl('bewertungSetzen', { ids: [a.id], bewertung: neu }); d.bewertung = neu; a.bewertung = neu || undefined; male(neu); } catch (x) { feld.append(el('p', 'fehler', x.message)); }
    });
    sterne.append(b);
  }
  male(d.bewertung || 0);
  teile.push(reihe('☆', sterne));
  if (d.serie && d.serie.groesse > 1) {
    const v = el('a', null, t('Serie mit {n} Aufnahmen', { n: d.serie.groesse }));
    v.href = `#/serie/${encodeURIComponent(d.serie.id)}`;
    v.addEventListener('click', schliesse);
    teile.push(reihe('⧉', v));
  }
  if (d.text) { const det = el('details'); det.append(el('summary', null, t('Erkannter Text')), el('pre', null, d.text)); teile.push(det); }
  if (d.transkript) { const det = el('details'); det.append(el('summary', null, t('Transkript')), el('pre', null, d.transkript)); teile.push(det); }
  teile.push(el('p', 'neben', t('Importiert {datum}', { datum: datumZeit.format(new Date(d.importiert)) })));
  feld.replaceChildren(...teile);
}

$('bearbeiten').addEventListener('click', () => {
  const a = liste && liste.aufnahmen[offen];
  if (a && a.art !== 'video') location.hash = `#/entwickeln/${encodeURIComponent(a.id)}`;
});

function setzeAngabenOffen(an) {
  angabenOffen = an;
  $('info').setAttribute('aria-pressed', String(angabenOffen));
  $('betrachter').classList.toggle('mit-angaben', angabenOffen);
  $('angaben-feld').hidden = !angabenOffen;
  zeigeAngaben();
}
$('info').addEventListener('click', () => setzeAngabenOffen(!angabenOffen));

function schliesse() {
  $('betrachter').hidden = true;
  liveAus();
  videoLauf++;
  $('video').pause();
  offen = -1;
  zeigeBildlauf();
}

// Die Knöpfe oben links rücken zusammen, wenn einer fehlt.
function ordneKnoepfe() {
  let i = 0;
  for (const id of ['favorit', 'laden', 'teilen', 'info', 'bearbeiten', 'weg', 'holen', 'live']) {
    if (!$(id).hidden) $(id).style.setProperty('--platz', String(i++));
  }
}

$('teilen').addEventListener('click', () => { const a = liste && liste.aufnahmen[offen]; if (a) teile([a]); });

// Aus dem Betrachter in den Papierkorb – und, im Papierkorb, zurück.
async function nimmAusListe(a, art) {
  await befehl(art, { ids: [a.id] });
  liste.aufnahmen = liste.aufnahmen.filter((x) => x.id !== a.id);
  if (art === 'inDenPapierkorb') zeitleiste.geladen = zeitleiste.geladen.filter((x) => x.id !== a.id);
  else zeitleiste.leeren();
  schliesse();
  neuZeichnen();
}
$('weg').addEventListener('click', async () => {
  const a = liste && liste.aufnahmen[offen];
  if (!a || !confirm(t('Eine Aufnahme in den Papierkorb legen? Sie verschwindet überall – zurückholen geht am Rechner und hier im Papierkorb.'))) return;
  try { await nimmAusListe(a, 'inDenPapierkorb'); } catch (x) { $('angaben').textContent = x.message; }
});
$('holen').addEventListener('click', async () => {
  const a = liste && liste.aufnahmen[offen];
  if (!a) return;
  try { await nimmAusListe(a, 'ausDemPapierkorb'); meldung(t('{n} zurückgeholt', { n: 1 })); } catch (x) { $('angaben').textContent = x.message; }
});

// --- Betrachter: wischen und zoomen ----------------------------------------
//
// Wie auf dem Telefon: zur Seite wischen blättert, nach unten wischen
// schliesst (das Bild folgt dem Finger, dahinter erscheint das Raster),
// nach oben wischen zeigt die Angaben. Zwei Finger oder ein Doppeltipp
// zoomen; vergrössert gehört das Ziehen dem Verschieben. Ein Tipp blendet
// die Knöpfe aus und wieder ein. Am Rechner zoomt das Mausrad.

const figur = document.querySelector('#betrachter figure');
const blick = { zoom: 1, x: 0, y: 0 };
const finger = new Map();
let wisch = null;
let zwei = null;
let letzterTipp = 0;
let tippUhr = null;

const medium = () => ($('video').hidden ? $('bild') : $('video'));

function setzeBlick(gleitend) {
  const b = $('bild');
  b.classList.toggle('gleitet', !!gleitend);
  b.style.transform = blick.zoom === 1 && blick.x === 0 && blick.y === 0 ? '' : `translate(${blick.x}px, ${blick.y}px) scale(${blick.zoom})`;
}

function blickZurueck(gleitend) {
  Object.assign(blick, { zoom: 1, x: 0, y: 0 });
  setzeBlick(gleitend);
  $('video').style.transform = '';
}

// Die Mitte des Bildes, ohne Verschiebung.
function bildMitte() {
  const b = $('bild'), f = figur.getBoundingClientRect();
  return { x: f.left + b.offsetLeft + b.offsetWidth / 2, y: f.top + b.offsetTop + b.offsetHeight / 2 };
}

// Zoomt auf [ziel], und der Punkt unter (px, py) bleibt, wo er ist.
function zoomeUm(ziel, px, py, gleitend) {
  const z = Math.min(6, Math.max(1, ziel));
  const m = bildMitte();
  const f = z / blick.zoom;
  blick.x = (px - m.x) - f * ((px - m.x) - blick.x);
  blick.y = (py - m.y) - f * ((py - m.y) - blick.y);
  blick.zoom = z;
  if (z === 1) { blick.x = 0; blick.y = 0; }
  setzeBlick(gleitend);
}

function wischZiel(dx, dy) {
  const m = medium();
  if (wisch.achse === 'seite') {
    m.style.transform = `translateX(${dx}px)`;
  } else if (dy > 0) {
    const anteil = Math.min(1, dy / 400);
    m.style.transform = `translate(${dx * 0.3}px, ${dy}px) scale(${1 - anteil * 0.25})`;
    $('betrachter').style.background = `rgba(0, 0, 0, ${1 - anteil * 0.85})`;
  } else {
    m.style.transform = `translateY(${dy * 0.25}px)`;
  }
}

function wischEnde(dx, dy, dauer) {
  const m = medium();
  const tempoX = dx / Math.max(dauer, 1), tempoY = dy / Math.max(dauer, 1);
  m.classList.add('gleitet');
  m.style.transform = '';
  $('betrachter').style.removeProperty('background');
  setTimeout(() => m.classList.remove('gleitet'), 200);
  if (wisch.achse === 'seite') {
    if (dx < -60 || tempoX < -0.5) oeffne(offen + 1);
    else if (dx > 60 || tempoX > 0.5) oeffne(offen - 1);
  } else if (dy > 110 || tempoY > 0.9) {
    m.classList.remove('gleitet');
    schliesse();
  } else if (dy < -50 || tempoY < -0.7) {
    setzeAngabenOffen(true);
  }
}

function tippe(x, y) {
  const jetzt = Date.now();
  if (jetzt - letzterTipp < 300 && $('video').hidden) {
    clearTimeout(tippUhr);
    letzterTipp = 0;
    if (blick.zoom > 1) blickZurueck(true); else zoomeUm(2.5, x, y, true);
    return;
  }
  letzterTipp = jetzt;
  clearTimeout(tippUhr);
  if ($('video').hidden) tippUhr = setTimeout(() => $('betrachter').classList.toggle('still'), 300);
}

figur.addEventListener('pointerdown', (e) => {
  if (e.button > 0) return;
  // Die Bedienelemente des Videos gehören dem Video.
  if (e.target === $('video') && e.pointerType !== 'touch') return;
  finger.set(e.pointerId, { x: e.clientX, y: e.clientY });
  try { figur.setPointerCapture(e.pointerId); } catch (_) { /* egal */ }
  if (finger.size === 2 && $('video').hidden) {
    const [a, b] = [...finger.values()];
    zwei = { abstand: Math.hypot(a.x - b.x, a.y - b.y), zoom: blick.zoom, x: blick.x, y: blick.y };
    wisch = null;
    return;
  }
  if (finger.size === 1) wisch = { x0: e.clientX, y0: e.clientY, bx: blick.x, by: blick.y, zeit: Date.now(), achse: null, art: e.pointerType };
});

figur.addEventListener('pointermove', (e) => {
  if (!finger.has(e.pointerId)) return;
  finger.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (zwei && finger.size === 2) {
    const [a, b] = [...finger.values()];
    const d = Math.hypot(a.x - b.x, a.y - b.y);
    if (zwei.abstand < 20) return;
    Object.assign(blick, { zoom: zwei.zoom, x: zwei.x, y: zwei.y });
    zoomeUm(zwei.zoom * (d / zwei.abstand), (a.x + b.x) / 2, (a.y + b.y) / 2, false);
    return;
  }
  if (!wisch) return;
  const dx = e.clientX - wisch.x0, dy = e.clientY - wisch.y0;
  if (blick.zoom > 1) {
    blick.x = wisch.bx + dx;
    blick.y = wisch.by + dy;
    setzeBlick(false);
    return;
  }
  if (wisch.art === 'mouse') return;
  if (!wisch.achse) {
    if (Math.hypot(dx, dy) < 10) return;
    wisch.achse = Math.abs(dx) > Math.abs(dy) ? 'seite' : 'hoch';
  }
  wischZiel(dx, dy);
});

function fingerWeg(e) {
  if (!finger.has(e.pointerId)) return;
  finger.delete(e.pointerId);
  if (zwei) {
    if (finger.size < 2) {
      zwei = null;
      if (blick.zoom < 1.05) blickZurueck(true);
      // Der verbliebene Finger verschiebt weiter, ohne zu springen.
      const rest = [...finger.values()][0];
      wisch = rest ? { x0: rest.x, y0: rest.y, bx: blick.x, by: blick.y, zeit: Date.now(), achse: 'fertig', art: 'touch' } : null;
    }
    return;
  }
  if (!wisch || e.type === 'pointercancel') { wisch = null; return; }
  const dx = e.clientX - wisch.x0, dy = e.clientY - wisch.y0;
  if (Math.hypot(dx, dy) < 8 && wisch.achse === null) tippe(e.clientX, e.clientY);
  else if (blick.zoom === 1 && (wisch.achse === 'seite' || wisch.achse === 'hoch')) wischEnde(dx, dy, Date.now() - wisch.zeit);
  wisch = null;
}
figur.addEventListener('pointerup', fingerWeg);
figur.addEventListener('pointercancel', fingerWeg);
figur.addEventListener('wheel', (e) => {
  if (!$('video').hidden) return;
  e.preventDefault();
  zoomeUm(blick.zoom * Math.exp(-e.deltaY * 0.0025), e.clientX, e.clientY, false);
}, { passive: false });
// Doppelklick der Maus: dasselbe wie der Doppeltipp (der kommt schon über tippe).
$('bild').draggable = false;

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
      case 'aktivitaeten': await zeigeAktivitaet(teile[1]); break;
      case 'statistik': await zeigeStatistik(); break;
      case 'einstellungen': await zeigeEinstellungen(); break;
      case 'stammbaum': await zeigeStammbaum(teile[1]); break;
      case 'lebensbaum': await ladeSkript('lebensbaum.js'); await zeigeLebensbaum(teile[1]); break;
      case 'duplikate': await zeigeDuplikate(); break;
      case 'serie': await zeigeSerie(teile[1]); break;
      case 'entwickeln': await ladeSkript('entwickeln.js'); await zeigeEntwickeln(teile[1]); break;
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
      case 'favoriten': await zeigeFavoriten(); break;
      case 'bibliothek': await zeigeBibliothek(); break;
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
  $('nav').hidden = false;
  $('inhalt').hidden = false;
  // Das Konto als Kreis mit dem Anfangsbuchstaben, oben rechts wie auf
  // dem Telefon.
  $('konto-knopf').textContent = (sitzung.name || '?').trim().charAt(0).toUpperCase();
  $('konto-knopf').title = `${t('Konto')}: ${sitzung.name}`;
  await zeigeWeg();
}

starte().catch(() => zeigeAnmeldung());

// Die Weboberfläche von Photo Vault – ohne Bibliothek, ohne Bauschritt.
//
// Alles, was vom Server kommt, wird als Text eingesetzt (textContent),
// nie als HTML. Jede schreibende Anfrage trägt den Kopf X-PV-Web (siehe
// anfrageAusDerOberflaeche auf dem Server). Das Cookie der Sitzung sieht
// dieses Skript nie; der Browser schickt es von selbst mit.
'use strict';

const $ = (id) => document.getElementById(id);
// Was eine Ansicht beim Aufbau lädt, bricht der nächste Weg ab (siehe
// zeigeWeg): Sonst schriebe eine späte Antwort in die neue Ansicht.
let wegSignal = null;
// Ein Lauf, den eine Änderung am Server anstösst, nicht der Nutzer (#329):
// Er lässt stehen, was gleich geblieben ist, und zeichnet den Rest ohne
// Sprung neu.
let stillerLauf = false;
const live = { stand: null, abbruch: null, laeuft: false, faellig: false, nochmal: false, uhr: null, zuletzt: 0, abstand: 5000 };
const api = async (pfad, { methode = 'GET', json } = {}) => {
  const antwort = await fetch(pfad, {
    method: methode,
    credentials: 'same-origin',
    signal: methode === 'GET' && wegSignal ? wegSignal : undefined,
    headers: {
      'X-PV-Web': '1',
      ...(json === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: json === undefined ? undefined : JSON.stringify(json),
  });
  let daten = null;
  try { daten = await antwort.json(); } catch (_) { /* keine Daten */ }
  // Nur die abgelaufene Sitzung: Ein falsches Passwort oder ein falscher Code
  // antworten ebenfalls mit 401 und sollen dort stehen, wo sie eingegeben wurden.
  if (antwort.status === 401 && (!daten || daten.fehler === 'nicht angemeldet')) {
    zeigeAnmeldung();
    throw new Error('nicht angemeldet');
  }
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
// Bilder hält der Browser unter ihrer Adresse vor. `stand` aus der Liste
// (#259) ändert sich mit jeder neuen Fassung – ohne es zeigte er nach
// einer Bearbeitung bis zu einen Tag lang das alte Bild.
const bildUrl = (id, art, stand) => `/api/v1/aufnahmen/${encodeURIComponent(id)}/${art}${stand ? `?v=${encodeURIComponent(stand)}` : ''}`;
const miniaturUrl = (id, stand) => bildUrl(id, 'miniatur', stand);
// Die Dateien der gezeigten Liste: aus der eigenen Bibliothek oder aus
// einem Album, das ein anderes Konto teilt (#105, `liste.fremd`). Raster,
// Betrachter, Video, Diashow und Herunterladen gehen hierüber; Karten und
// Personen zeigen immer Eigenes und nehmen [bildUrl].
const fremdeListe = () => !!(liste && liste.fremd);
// Fotos eines Partners in der eigenen Zeitleiste (#299) tragen das Konto,
// dem sie gehören – ihre Dateien kommen über dessen Freigabe, und ändern
// lässt sich an ihnen nichts.
const partnerBasis = (konto) => `/api/v1/partner/von/${encodeURIComponent(konto)}/aufnahmen`;
const fremdeAufnahmen = new Map();
const fremdeAufnahme = (a) => fremdeListe() || !!(a && a.konto);
const aufnahmeUrl = (id, art, stand) => `${fremdeAufnahmen.get(id) || (liste && liste.fremd) || '/api/v1/aufnahmen'}/${encodeURIComponent(id)}/${art}${stand ? `?v=${encodeURIComponent(stand)}` : ''}`;
const datum = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'full' });
const datumZeit = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium', timeStyle: 'short' });
const monatJahr = new Intl.DateTimeFormat(GEBIET, { month: 'long', year: 'numeric' });
const tagKopf = new Intl.DateTimeFormat(GEBIET, { weekday: 'long', day: 'numeric', month: 'long' });

let sitzung = null;   // {name, verwalter, geraet}

// --- Ansichten -------------------------------------------------------------

function zeigeAnmeldung() {
  sitzung = null;
  if (live.abbruch) live.abbruch.abort();
  live.stand = null;
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
  if (!stillerLauf) $('ohne-namen').hidden = true;
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
      { bereich: 'orte', weg: '#/orte', text: 'Orte', symbol: 'orte', farbe: '#00a2c7' },
      { bereich: 'reisen', weg: '#/reisen', text: 'Reisen', symbol: 'reisen', farbe: '#f76b15' },
      { bereich: 'stammbaum', weg: '#/stammbaum', text: 'Stammbaum', symbol: 'stammbaum', farbe: '#a18072' },
      { bereich: 'statistik', weg: '#/statistik', text: 'Statistik', symbol: 'statistik', farbe: '#0090ff' },
      // Wie am Rechner (#185): dieselben Farben wie dort.
      { bereich: 'rueckblick', weg: '#/rueckblick', text: 'Rückblick', symbol: 'rueckblick', farbe: '#d6409f' },
      { bereich: 'kalender', weg: '#/kalender', text: 'Kalender', symbol: 'kalender', farbe: '#6e56cf' },
    ],
  },
  {
    titel: 'Verwalten',
    eintraege: [
      // Nur hier und am Rechner, nicht auf dem Telefon (#336).
      { bereich: 'fotokammer', weg: '#/fotokammer', text: 'Fotokammer', symbol: 'fotokammer', farbe: '#ad7f58' },
      { bereich: 'duplikate', weg: '#/duplikate', text: 'Duplikate', symbol: 'duplikate', farbe: '#3e63dd' },
      { bereich: 'aufnahmedaten', weg: '#/aufnahmedaten', text: 'Aufnahmedaten', symbol: 'aufnahmedaten', farbe: '#ffa01c' },
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
    if (e.bereich === 'fotos') a.addEventListener('click', fotosNachOben);
    haupt.append(a);
  }
  const marke = el('a', 'nav-marke');
  marke.href = '#/';
  marke.addEventListener('click', fotosNachOben);
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

// Die Wiederherstellungscodes in einem eigenen Fenster: markierbar, mit
// „Kopieren“ und „Als Datei sichern“. Vorher standen sie in alert(), aus
// dem sich im Browser nichts kopieren liess. Kehrt zurück, wenn es
// geschlossen ist.
function zeigeCodes(codes) {
  const text = codes.join('\n');
  $('codes-liste').textContent = text;
  $('codes-meldung').textContent = '';
  const d = $('codes-dialog');
  d.showModal();
  return new Promise((fertig) => d.addEventListener('close', fertig, { once: true }));
}

$('codes-kopieren').addEventListener('click', async () => {
  const text = $('codes-liste').textContent;
  let ok = false;
  // Über http im Heimnetz gibt es navigator.clipboard nicht – dann über die
  // Markierung.
  try { await navigator.clipboard.writeText(text); ok = true; } catch (_) { /* weiter unten */ }
  if (!ok) {
    const r = document.createRange();
    r.selectNodeContents($('codes-liste'));
    const s = getSelection();
    s.removeAllRanges();
    s.addRange(r);
    try { ok = document.execCommand('copy'); } catch (_) { ok = false; }
  }
  $('codes-meldung').textContent = ok ? t('Kopiert.') : t('Bitte markieren und mit Strg+C bzw. ⌘C kopieren.');
});

$('codes-sichern').addEventListener('click', () => {
  const inhalt = `${t('Photo Vault – Wiederherstellungscodes')}\n${location.host}\n\n${$('codes-liste').textContent}\n`;
  const a = el('a');
  a.href = URL.createObjectURL(new Blob([inhalt], { type: 'text/plain;charset=utf-8' }));
  a.download = 'photo-vault-wiederherstellungscodes.txt';
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  $('codes-meldung').textContent = t('Gesichert.');
});

async function nachAnmeldung(d) {
  if (d.angemeldet) {
    fehler('');
    if (d.wiederherstellungscodes) await zeigeCodes(d.wiederherstellungscodes);
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
  // Neu laden statt aufräumen: Suchfilter, Duplikate und andere Listen des
  // Kontos sähe sonst, wer sich im selben Tab anmeldet.
  location.hash = '#/';
  location.reload();
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
  // Aus der Bibliothek eines Partners (#299): sein Anfangsbuchstabe oben
  // links, wo sonst der Favorit sitzt – den gibt es an fremden Fotos nicht.
  if (a.konto && a.von) k.append(el('span', 'partnermarke', a.von.slice(0, 1).toUpperCase()));
  if (a.serie && a.serie.titel && a.serie.groesse > 1) {
    const s = el('span', 'schild');
    s.append(kachelzeichen('serie'), document.createTextNode(String(a.serie.groesse)));
    k.append(s);
  } else if (a.format) {
    k.append(el('span', 'schild', a.format));
  }
}

// Grosse Kacheln werden scharf: Die Miniatur hat 400 Punkte an der langen
// Seite. In wenigen Spalten auf einem Bildschirm mit doppelter Dichte ist
// eine Kachel deutlich grösser, und das Foto sah weich aus. Steht eine
// Kachel eine Viertelsekunde im Bild, holt sie die Fassung des Betrachters
// nach – beim schnellen Durchscrollen nicht. Die Miniatur bleibt, bis die
// grosse da ist.
const KACHEL_SPIELRAUM = 1.15;
const schaerfer = 'IntersectionObserver' in window
  ? new IntersectionObserver((eintraege) => {
    for (const e of eintraege) {
      const img = e.target;
      clearTimeout(img.schaerferUhr);
      if (!img.isConnected) { schaerfer.unobserve(img); continue; }
      if (e.isIntersecting) img.schaerferUhr = setTimeout(() => werdeSchaerfer(img), 250);
    }
  })
  : null;

function werdeSchaerfer(img) {
  if (!img.isConnected || !img.dataset.gross) return;
  if (!img.complete || !img.naturalWidth) {
    img.addEventListener('load', () => werdeSchaerfer(img), { once: true });
    return;
  }
  const r = img.getBoundingClientRect();
  const noetig = Math.max(r.width / img.naturalWidth, r.height / img.naturalHeight) * (window.devicePixelRatio || 1);
  if (noetig <= KACHEL_SPIELRAUM) return;
  const quelle = img.dataset.gross;
  delete img.dataset.gross;
  schaerfer.unobserve(img);
  const gross = new Image();
  gross.decoding = 'async';
  gross.onload = () => { if (img.isConnected) img.src = quelle; };
  gross.src = quelle;
}

// Werden Kacheln grösser, ohne dass sich etwas an ihrer Sichtbarkeit ändert
// (mehr Platz, weniger Spalten), meldet der Beobachter nichts – dann hier.
let scharfUhr = null;
function pruefeScharf() {
  if (!schaerfer) return;
  clearTimeout(scharfUhr);
  scharfUhr = setTimeout(() => {
    for (const img of document.querySelectorAll('#raster img[data-gross]')) {
      const r = img.getBoundingClientRect();
      if (r.bottom > 0 && r.top < innerHeight) werdeSchaerfer(img);
    }
  }, 250);
}
window.addEventListener('resize', pruefeScharf);

function kachel(a, index) {
  const vorrat = kachelVorrat && kachelVorrat.get(a.id);
  if (vorrat && vorrat.zeile === JSON.stringify(a)) {
    vorrat.k.dataset.index = index;
    return vorrat.k;
  }
  const k = el('button', 'kachel');
  k.type = 'button';
  k.dataset.index = index;
  const img = el('img');
  img.loading = 'lazy';
  img.decoding = 'async';
  img.alt = '';
  img.draggable = false;
  img.src = aufnahmeUrl(a.id, 'miniatur', a.stand);
  if (schaerfer && !(liste && liste.alsListe)) {
    img.dataset.gross = aufnahmeUrl(a.id, 'ansicht', a.stand);
    schaerfer.observe(img);
  }
  k.append(img);
  if (a.von) k.title = a.konto ? t('Aus der Bibliothek von {name}', { name: a.von }) : t('Beigetragen von {name}', { name: a.von });
  if (liste && liste.alsListe) {
    // In der Liste trägt die Zeile die Angaben statt der Marken – Auswahl,
    // Ziehen, Pfeiltasten und Betrachter bleiben dieselben wie bei Kacheln.
    k.classList.add('zeile');
    zeilenzellen(k, a);
  } else {
    k.style.setProperty('--v', seitenverhaeltnis(a).toFixed(4));
    marken(k, a);
  }
  if (auswahl.has(a.id)) k.classList.add('gewaehlt');
  if (schwebeVideoId(a)) {
    k.addEventListener('pointerenter', (e) => { if (e.pointerType === 'mouse') schwebeBeginn(k, a); });
    k.addEventListener('pointerleave', () => { if (schwebe.kachel === k) schwebeEnde(); });
  }
  k.addEventListener('click', (e) => {
    // Nach dem Ziehen kommt noch ein Klick – der gehört zum Ziehen.
    if (zieh.schlucke) { zieh.schlucke = false; return; }
    // Aus dem Element: Eine Kachel wandert mit, wenn oben Neues dazukommt.
    const index = Number(k.dataset.index);
    // Wie am Rechner: Umschalt nimmt alles bis hierher dazu, Strg/⌘ eine.
    // Aus einem geteilten Album lässt sich nichts auswählen: Alles, was
    // die Auswahl kann, ändert die eigene Bibliothek.
    if (fremdeAufnahme(a)) { setzeRahmen(index, false); oeffne(index); return; }
    if (e.shiftKey && rahmen >= 0) { waehleBereich(rahmen, index); setzeRahmen(index, false); return; }
    if (e.metaKey || e.ctrlKey) { schalteAuswahl(a.id, k); setzeRahmen(index, false); return; }
    setzeRahmen(index, false);
    if (auswahlModus || auswahl.size) schalteAuswahl(a.id, k); else oeffne(index);
  });
  return k;
}

// --- Die Liste (#195) ---------------------------------------------------------
//
// Wie die Listenansicht am Rechner: die Aufnahmen untereinander mit den
// Angaben in Spalten, die sich wählen und in der Breite ziehen lassen.
// Geschrieben wird wie dort (listengliederung.dart): „Canon EOS R10“,
// „24 mm · f/4.0 · 1/250 · ISO 200“.

function kamerabezeichnung(hersteller, modell) {
  const h = (hersteller || '').trim();
  const m = (modell || '').trim();
  if (!h && !m) return '';
  if (!m) return h;
  if (!h) return m;
  return m.toLowerCase().startsWith(h.toLowerCase()) ? m : `${h} ${m}`;
}

function belichtungstext(a) {
  const teile = [];
  if (a.brennweite != null) teile.push(`${Math.round(a.brennweite)} mm`);
  if (a.blende != null) teile.push(`f/${Number(a.blende).toFixed(1)}`);
  if (a.zeit != null && a.zeit > 0) teile.push(a.zeit >= 1 ? `${Number(a.zeit).toFixed(1)} s` : `1/${Math.round(1 / a.zeit)}`);
  if (a.iso != null) teile.push(`ISO ${a.iso}`);
  return teile.join(' · ');
}

const FARBPUNKTE = { red: '#e53935', yellow: '#fdd835', green: '#43a047', blue: '#1e88e5', purple: '#8e24aa' };
const listenDatum = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'short' });
const listenDatumZeit = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'short', timeStyle: 'short' });

function zelleVon(s, a) {
  const z = el('span', `zelle ${s}`);
  let text = '';
  switch (s) {
    case 'dateiname': text = a.name || ''; break;
    // Die Uhrzeit weicht dem Vermerk, wenn das Datum geschätzt ist – sie
    // wäre die genaueste Angabe und zugleich die, die sicher nicht stimmt.
    case 'datum': text = a.geschaetzt ? `${listenDatum.format(new Date(a.aufgenommen))} (${t('geschätzt')})` : listenDatumZeit.format(new Date(a.aufgenommen)); break;
    case 'kamera': text = kamerabezeichnung(a.kamera, a.modell); break;
    case 'objektiv': text = a.objektiv || ''; break;
    case 'belichtung': text = belichtungstext(a); break;
    case 'bewertung':
      if (a.bewertung) { z.append(el('span', 'sterne-klein', '★'.repeat(a.bewertung))); z.title = t('{i} von 5', { i: a.bewertung }); return z; }
      break;
    case 'farbe':
      if (a.farbe) { const p = el('span', 'farbpunkt'); p.style.background = FARBPUNKTE[a.farbe] || 'var(--rand)'; z.append(p); return z; }
      break;
    case 'masse': text = a.breite && a.hoehe ? `${a.breite} × ${a.hoehe}` : ''; break;
    case 'groesse': text = a.bytes ? groesse(a.bytes) : ''; break;
    case 'art': text = a.art === 'video' ? t('Video') : t('Foto'); break;
    case 'ort': text = [a.stadt, a.land ? land(a.land) : ''].filter(Boolean).join(', '); break;
    default: break;
  }
  if (!text) { z.classList.add('leer'); z.textContent = '—'; } else { z.textContent = text; z.title = text; }
  return z;
}

// Der Name steht für sich; die übrigen Spalten in einem Behälter, der in
// der breiten Liste verschwindet (display: contents) und in der schmalen
// zur zweiten Zeile wird.
function zeilenzellen(k, a) {
  const spalten = ansicht.spalten;
  const mitName = spalten.includes('dateiname');
  if (mitName) k.append(zelleVon('dateiname', a));
  const weitere = el('span', 'weitere');
  for (const s of spalten) if (s !== 'dateiname') weitere.append(zelleVon(s, a));
  k.append(weitere);
}

function legeListenspalten() {
  $('raster').style.setProperty('--listen-spalten', ansicht.spalten.map((s) => `${spaltenbreite(s)}px`).join(' '));
}

// Die Kopfzeile mit den Spaltennamen; am rechten Rand jeder Zelle ein
// Griff, der die Breite zieht (60 bis 600 Punkte, wie am Rechner).
function listenkopf() {
  const kopf = el('div', 'listenkopf');
  kopf.append(el('span'));
  for (const s of ansicht.spalten) {
    const zelle = el('span', 'kopfzelle', t(LISTENTITEL[s]));
    const griff = el('span', 'griff');
    griff.title = t('Breite ändern');
    griff.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      griff.setPointerCapture(e.pointerId);
      const start = e.clientX, von = spaltenbreite(s);
      const zieh = (m) => { ansicht.breiten[s] = Math.min(600, Math.max(60, Math.round(von + m.clientX - start))); legeListenspalten(); };
      const los = () => { griff.removeEventListener('pointermove', zieh); merkeAnsicht(); };
      griff.addEventListener('pointermove', zieh);
      griff.addEventListener('pointerup', los, { once: true });
      griff.addEventListener('pointercancel', los, { once: true });
    });
    zelle.append(griff);
    kopf.append(zelle);
  }
  return kopf;
}

// Wonach die Liste ihre Köpfe setzt. Nur nach dem Datum geordnet gibt es
// Monate, Tage und Kameras – sonst eine durchgehende Liste.
function listenGliederung() {
  return liste && liste.alsListe && nachDatum() ? ansicht.gliederung : 'keine';
}

// Nach Kamera: Die Gruppen stehen alphabetisch, ohne Angabe am Ende – und
// das über alles Geladene. Jede neue Seite ordnet deshalb neu.
function nachKameraOrdnen() {
  const gruppen = new Map();
  for (const a of liste.roh) {
    const k = kamerabezeichnung(a.kamera, a.modell);
    if (!gruppen.has(k)) gruppen.set(k, []);
    gruppen.get(k).push(a);
  }
  return [...gruppen.keys()].sort((x, y) => (!x ? 1 : !y ? -1 : x.toLowerCase().localeCompare(y.toLowerCase()))).map((k) => ({ k, aufnahmen: gruppen.get(k) }));
}

// --- Vorschau beim Darüberfahren (#193) -------------------------------------
//
// Wie die Schwebevorschau am Rechner: Ein Video und ein Live Photo sind in
// der Kachelwand nicht voneinander zu unterscheiden. Bleibt die Maus einen
// Augenblick darauf stehen, läuft es in der Kachel an – ohne Ton und in
// Dauerschleife, bis der Zeiger weiterwandert. Es läuft immer nur eines.
// Die Wartezeit hält einen Zeiger, der quer über die Wand fährt, davon
// ab, eine Spur anlaufender Videos hinter sich herzuziehen.

const SCHWEBE_MERKER = 'pv-schwebevorschau';
const SCHWEBE_WARTEN = 300;
let schwebeAn = (() => { try { return localStorage.getItem(SCHWEBE_MERKER) !== '0'; } catch (_) { return true; } })();
const schwebe = { kachel: null, uhr: 0, video: null, lauf: 0 };

// Welche Aufnahme das Video trägt: ein Video sich selbst, ein Live Photo
// seinen Bewegungsteil, alles andere keins.
function schwebeVideoId(a) {
  if (a.art === 'video') return a.id;
  return a.partner || null;
}

function schwebeBeginn(k, a) {
  if (!schwebeAn) return;
  schwebeEnde();
  schwebe.kachel = k;
  schwebe.uhr = setTimeout(() => schwebeStart(k, a), SCHWEBE_WARTEN);
}

function schwebeEnde() {
  clearTimeout(schwebe.uhr);
  schwebe.lauf++;
  const v = schwebe.video;
  if (v) {
    v.pause();
    v.removeAttribute('src');
    v.load();
    v.remove();
  }
  if (schwebe.kachel) schwebe.kachel.classList.remove('schwebt');
  schwebe.video = null;
  schwebe.kachel = null;
}

async function schwebeStart(k, a) {
  const id = schwebeVideoId(a);
  if (!id || schwebe.kachel !== k) return;
  const lauf = schwebe.lauf;
  const v = el('video', 'schwebe');
  v.muted = true;
  v.defaultMuted = true;
  v.loop = true;
  v.playsInline = true;
  v.disablePictureInPicture = true;
  v.setAttribute('aria-hidden', 'true');
  schwebe.video = v;
  // Sichtbar erst mit dem ersten Bild – bis dahin bleibt das Standbild.
  v.addEventListener('playing', () => { if (lauf === schwebe.lauf) k.classList.add('schwebt'); });
  const original = aufnahmeUrl(id, 'wiedergabe');
  // Wie im Betrachter: Kann der Browser kein HEVC, die H.264-Fassung des
  // Servers. Ein Bewegungsteil vom iPhone ist immer HEVC, da gleich.
  const fassung = async () => {
    for (let i = 0; i < 120 && lauf === schwebe.lauf; i++) {
      let r;
      try { r = await fetch(fassungUrl(id, true), { credentials: 'same-origin' }); } catch (_) { return; }
      if (r.status === 200) {
        if (lauf === schwebe.lauf) { v.src = fassungUrl(id, false); v.play().catch(() => {}); }
        return;
      }
      if (r.status !== 202) return;
      await new Promise((fertig) => setTimeout(fertig, 1000));
    }
  };
  let gewechselt = false;
  const wechsle = () => { if (!gewechselt && lauf === schwebe.lauf) { gewechselt = true; fassung(); } };
  v.onerror = () => { if (v.getAttribute('src') === original) wechsle(); };
  v.onloadedmetadata = () => { if (v.getAttribute('src') === original && v.videoWidth === 0) wechsle(); };
  k.append(v);
  if (a.partner && a.art !== 'video' && !kannHevc) { wechsle(); return; }
  v.src = original;
  v.play().catch(() => {});
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
  // Vor jeder Überschrift ein Füller: In bündigen Reihen bleibt so die
  // letzte Reihe einer Gruppe ungestreckt.
  const kopfDazu = (kopf) => {
    if (liste.kacheln.length) raster.append(el('span', 'fueller'));
    raster.append(kopf);
  };
  const gliederung = listenGliederung();
  if (gliederung === 'kamera') {
    // Neu ordnen und ganz neu zeichnen; die Auswahl hängt an Kennungen. Der
    // offene Betrachter hängt am Index und muss mitgehen.
    const gezeigt = offen >= 0 ? liste.aufnahmen[offen] : null;
    liste.roh.push(...aufnahmen);
    liste.aufnahmen = [];
    liste.kacheln = [];
    liste.tage = new Map();
    const r = $('raster');
    r.replaceChildren(listenkopf());
    for (const g of nachKameraOrdnen()) {
      raster.append(el('h2', 'monat', g.k || t('Ohne Kameraangabe')));
      for (const a of g.aufnahmen) {
        const k = kachel(a, liste.aufnahmen.length);
        liste.kacheln.push(k);
        raster.append(k);
        liste.aufnahmen.push(a);
      }
    }
    r.append(raster);
    if (gezeigt) offen = liste.aufnahmen.indexOf(gezeigt);
    return;
  }
  const mitTagen = liste.alsListe ? gliederung === 'tag' : ansicht.tage;
  const mitMonaten = liste.alsListe ? gliederung === 'monat' : true;
  for (const a of aufnahmen) {
    const tag = tagVon(a);
    if (liste.alsListe && gliederung === 'tag') {
      // Die Liste kennt keine Monatsköpfe darüber; der Tag nennt das ganze Datum.
      if (tag !== letzterTag) {
        letzterTag = tag;
        raster.append(el('h2', 'monat', datum.format(new Date(a.aufgenommen))));
      }
    } else if (liste.nachTagen && mitMonaten) {
      const d = new Date(a.aufgenommen);
      const monat = `${d.getFullYear()}-${d.getMonth()}`;
      if (monat !== letzterMonat) {
        letzterMonat = monat;
        letzterTag = null;
        const kopf = el('h2', 'monat', monatJahr.format(d));
        kopf.dataset.monat = monatsschluessel(d);
        kopfDazu(kopf);
      }
      if (mitTagen && tag !== letzterTag) {
        letzterTag = tag;
        const kopf = tageskopf(a, tag);
        liste.koepfe.set(tag, kopf);
        kopfDazu(kopf);
      }
    }
    if (!liste.tage.has(tag)) liste.tage.set(tag, []);
    // Fotos eines Partners (#299) wählt auch der ganze Tag nicht mit.
    if (!a.konto) liste.tage.get(tag).push(a.id);
    const k = kachel(a, liste.aufnahmen.length);
    liste.kacheln.push(k);
    raster.append(k);
    liste.aufnahmen.push(a);
  }
  $('raster').append(raster);
  if (liste.nachTagen) zeichneTage();
}

// Zählt die Listen: Was eine frühere nachlädt, gehört nicht in die jetzige.
let ansichtNr = 0;

// Bilder blitzen auf, wenn eine Kachel neu entsteht. Darum nimmt ein stiller
// Lauf (#329) die vorhandenen wieder, solange sich an der Zeile nichts änderte.
let kachelVorrat = null;

// Die oberste Kachel im Fenster und wo sie steht: Kommt darüber etwas dazu,
// bleibt sie dort. Am Anfang der Liste bleibt es beim Anfang, damit Neues
// zu sehen ist.
function bildlaufAnker() {
  const k = liste.kacheln;
  if (window.scrollY < 8 || !k.length) return null;
  const oben = $('kopf').getBoundingClientRect().bottom;
  let von = 0, bis = k.length - 1;
  while (von < bis) {
    const mitte = (von + bis) >> 1;
    if (k[mitte].getBoundingClientRect().bottom > oben) bis = mitte; else von = mitte + 1;
  }
  return { id: liste.aufnahmen[von].id, y: k[von].getBoundingClientRect().top };
}

function stelleBildlaufWieder(anker) {
  const i = liste.aufnahmen.findIndex((a) => a.id === anker.id);
  if (i >= 0) window.scrollBy({ top: liste.kacheln[i].getBoundingClientRect().top - anker.y, behavior: 'instant' });
}

function zeigeListe(neu, titel) {
  const still = stillerLauf && !neu.neuGezeichnet && !!liste;
  let anker = null, gerahmt = null;
  if (still) {
    const bisher = liste.roh.length ? liste.roh : liste.aufnahmen;
    const titelBisher = $('raster-titel').hidden ? '' : $('raster-titel').textContent;
    if ((titel || '') === titelBisher && JSON.stringify(bisher) === JSON.stringify(neu.aufnahmen || [])) return;
    if (ansichtGesperrt()) { live.nochmal = true; return; }
    anker = bildlaufAnker();
    gerahmt = liste.aufnahmen[rahmen] ? liste.aufnahmen[rahmen].id : null;
    kachelVorrat = new Map(liste.aufnahmen.map((a, i) => [a.id, { k: liste.kacheln[i], zeile: JSON.stringify(a) }]));
  }
  if (!neu.neuGezeichnet) {
    ansichtNr++;
    auswahlAufheben();
  }
  liste = { aufnahmen: [], nachTagen: false, mehr: null, ...neu, aufnahmen: [], tage: new Map(), kacheln: [], koepfe: new Map() };
  if (!still) $('erinnerungen').hidden = true;
  $('auswahl-papierkorb').hidden = !!liste.papierkorb;
  $('auswahl-kammer').hidden = !!liste.papierkorb;
  $('auswahl-ort').hidden = !!liste.papierkorb;
  $('auswahl-zurueck').hidden = !liste.papierkorb;
  $('auswahl-endgueltig').hidden = !liste.papierkorb;
  letzterTag = null;
  letzterMonat = null;
  schwebeEnde();
  $('raster').replaceChildren();
  $('raster-titel').hidden = !titel;
  $('raster-titel').textContent = titel || '';
  $('raster-kopf').replaceChildren(...(liste.kopf ? [liste.kopf] : []));
  $('raster-kopf').hidden = !liste.kopf;
  $('ansichtsleiste').hidden = !liste.zeitleiste;
  // Aus einem geteilten Album lässt sich nichts auswählen (#292).
  $('auswaehlen').hidden = !!liste.fremd;
  liste.roh = [];
  $('raster').classList.toggle('liste', !!liste.alsListe);
  if (liste.alsListe) { legeListenspalten(); $('raster').append(listenkopf()); }
  legeForm();
  $('ende').textContent = '';
  haengeAn(neu.aufnahmen || []);
  if (!liste.mehr) $('ende').textContent = liste.aufnahmen.length ? anzahlText(liste.aufnahmen.length) : t('Keine Aufnahmen.');
  if (still) {
    kachelVorrat = null;
    rahmen = liste.aufnahmen.findIndex((a) => a.id === gerahmt);
    if (anker) stelleBildlaufWieder(anker);
  }
}

async function ladeMehr() {
  if (!liste || !liste.mehr || liste.laedt || stillerLauf) return;
  const nr = ansichtNr;
  liste.laedt = true;
  try {
    const d = await liste.mehr();
    if (nr !== ansichtNr) return;
    haengeAn(d.aufnahmen);
    if (!d.weiter) {
      liste.mehr = null;
      $('ende').textContent = liste.aufnahmen.length ? anzahlText(liste.aufnahmen.length) : t('Noch keine Aufnahmen.');
    }
  } catch (x) {
    if (nr === ansichtNr) $('ende').textContent = x.message;
  } finally {
    if (nr === ansichtNr) {
      liste.laedt = false;
      // Füllt eine Seite den Schirm nicht, bleibt #ende sichtbar, und der
      // Beobachter meldet keinen neuen Wechsel.
      const r = $('ende').getBoundingClientRect();
      if (liste.mehr && r.height && r.top < innerHeight) setTimeout(ladeMehr);
    }
  }
}

const waechter = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) ladeMehr(); });
waechter.observe($('ende'));

// --- Ansicht der Zeitleiste (#194) ------------------------------------------
//
// Wie die Leiste über der Zeitleiste am Rechner: die Reihenfolge, nach
// Tagen oder nur nach Monaten gegliedert, quadratische Kacheln oder
// bündige Reihen – jedes Foto in seinem Format – und grösser oder kleiner.
// Gemerkt wird das je Browser.

const ANSICHT_MERKER = 'pv-ansicht';
const SORTIERUNGEN = ['aufnahmeNeu', 'aufnahmeAlt', 'importNeu', 'name', 'bewertung', 'groesse'];
// Die Spalten der Liste wie am Rechner (listenspalten.dart): Vorgabe die
// fünf von früher, jede mit ihrer Breite.
const LISTENSPALTEN = ['dateiname', 'datum', 'kamera', 'objektiv', 'belichtung', 'bewertung', 'farbe', 'masse', 'groesse', 'art', 'ort'];
const LISTENSPALTEN_VORGABE = ['dateiname', 'datum', 'kamera', 'belichtung', 'bewertung'];
const LISTENBREITEN = { dateiname: 260, datum: 150, kamera: 180, objektiv: 200, belichtung: 190, bewertung: 116, farbe: 70, masse: 120, groesse: 100, art: 90, ort: 180 };
const LISTENTITEL = { dateiname: 'Dateiname', datum: 'Aufgenommen', kamera: 'Kamera', objektiv: 'Objektiv', belichtung: 'Belichtung', bewertung: 'Bewertung', farbe: 'Farbe', masse: 'Masse', groesse: 'Dateigrösse', art: 'Art', ort: 'Ort' };
const GLIEDERUNGEN = ['monat', 'tag', 'kamera', 'keine'];
const ansicht = (() => {
  const v = { sortierung: 'aufnahmeNeu', tage: true, form: 'quadrate', liste: false, gliederung: 'monat', spalten: LISTENSPALTEN_VORGABE, breiten: {} };
  try { Object.assign(v, JSON.parse(localStorage.getItem(ANSICHT_MERKER) || '{}')); } catch (_) { /* privat */ }
  if (!SORTIERUNGEN.includes(v.sortierung)) v.sortierung = 'aufnahmeNeu';
  if (v.form !== 'reihen') v.form = 'quadrate';
  v.tage = v.tage !== false;
  v.liste = v.liste === true;
  if (!GLIEDERUNGEN.includes(v.gliederung)) v.gliederung = 'monat';
  // Namen, die es nicht mehr gibt, fallen still weg – wie am Rechner.
  v.spalten = Array.isArray(v.spalten) ? LISTENSPALTEN.filter((s) => v.spalten.includes(s)) : [];
  if (!v.spalten.length) v.spalten = [...LISTENSPALTEN_VORGABE];
  if (!v.breiten || typeof v.breiten !== 'object') v.breiten = {};
  return v;
})();
const spaltenbreite = (s) => Math.min(600, Math.max(60, Number(ansicht.breiten[s]) || LISTENBREITEN[s]));
function merkeAnsicht() {
  try { localStorage.setItem(ANSICHT_MERKER, JSON.stringify(ansicht)); } catch (_) { /* privat */ }
}
// Nur nach dem Aufnahmedatum geordnet gibt es Monate und Tage: Eine
// Überschrift „März 2019“ über Fotos, die nach Grösse sortiert sind, wäre
// falsch (wie am Rechner).
const nachDatum = () => ansicht.sortierung === 'aufnahmeNeu' || ansicht.sortierung === 'aufnahmeAlt';

// Das Format einer Aufnahme für die bündigen Reihen; ohne Angabe ein
// Kleinbildformat, das in keiner Richtung auffällt.
function seitenverhaeltnis(a) {
  const v = a.breite > 0 && a.hoehe > 0 ? a.breite / a.hoehe : 1.5;
  return Number.isFinite(v) && v > 0 ? v : 1.5;
}

// Die Zeitleiste merkt sich ihr Lesezeichen, damit ein Wechsel in ein
// Album nicht alles neu lädt.
// Die ersten `anzahl` Aufnahmen einer Liste, die seitenweise kommt, von vorn –
// für den stillen Lauf (#329). `hole(nach, n)` liefert eine Seite.
async function seitenBis(hole, anzahl) {
  const aufnahmen = [];
  let weiter;
  do {
    const d = await hole(weiter, Math.min(1000, Math.max(200, anzahl - aufnahmen.length)));
    aufnahmen.push(...d.aufnahmen);
    weiter = d.weiter;
  } while (weiter && aufnahmen.length < anzahl);
  return { aufnahmen, weiter: weiter ?? null };
}

const zeitleiste = {
  weiter: undefined,
  geladen: [],
  // Grössere Seiten, solange die Leiste zu einem fernen Monat springt.
  seite: 200,
  leeren() { this.weiter = undefined; this.geladen = []; zeitleistenmonate.liste = null; },
  // Läuft schon eine Anfrage, gilt ihre Antwort auch für den zweiten Aufrufer.
  // Sonst käme nach Fotos, Favoriten, Fotos dieselbe Seite doppelt.
  lauf: null,
  mehr() {
    return (this.lauf ??= this.hole().finally(() => { this.lauf = null; }));
  },
  async hole() {
    const d = await this.holeSeite(this.weiter, this.seite);
    this.weiter = d.weiter;
    this.geladen.push(...d.aufnahmen);
    return d;
  },
  async holeSeite(nach, anzahl) {
    const q = new URLSearchParams({ anzahl: String(anzahl) });
    if (nach) q.set('nach', nach);
    if (ansicht.sortierung !== 'aufnahmeNeu') q.set('sortierung', ansicht.sortierung);
    if (ansicht.liste) q.set('voll', '1');
    const d = await api(`/api/v1/aufnahmen?${q}`);
    for (const a of d.aufnahmen) {
      if (!a.konto) continue;
      fremdeAufnahmen.set(a.id, partnerBasis(a.konto));
      if (a.partner) fremdeAufnahmen.set(a.partner, partnerBasis(a.konto));
    }
    return d;
  },
  // Holt so viel neu, wie geladen ist. Nichts übernehmen, wenn die Liste
  // gerade nicht wechseln darf: Das Lesezeichen passte sonst nicht mehr zu ihr.
  async frisch(anzahl) {
    const d = await seitenBis((nach, n) => this.holeSeite(nach, n), anzahl);
    if (ansichtGesperrt()) { live.nochmal = true; return false; }
    this.weiter = d.weiter;
    this.geladen = d.aufnahmen;
    return true;
  },
};

// --- Bereiche --------------------------------------------------------------

// Wie am Rechner: „Fotos“ fährt zu den neuesten Aufnahmen zurück – auch
// wenn die Zeitleiste schon offen ist und weit unten steht. Dann ändert
// sich die Adresse nicht, und ohne das hier geschähe gar nichts.
let fotosNachObenGewuenscht = false;
function fotosNachOben() {
  const schonDa = (location.hash || '#/') === '#/' && liste && liste.zeitleiste && !$('bereich-raster').hidden;
  if (schonDa) window.scrollTo({ top: 0, behavior: 'smooth' });
  else {
    fotosNachObenGewuenscht = true;
    // Unter #/ gibt es kein hashchange, das die Zeitleiste zurückholte.
    if ((location.hash || '#/') === '#/') zeigeWeg();
  }
}

const zeitleistenAngaben = () => ({ aufnahmen: zeitleiste.geladen, nachTagen: nachDatum(), zeitleiste: true, alsListe: ansicht.liste, mehr: zeitleiste.weiter === null ? null : () => zeitleiste.mehr() });

async function zeigeFotos() {
  markiereNav('fotos');
  zeigeBereich(['raster']);
  if (stillerLauf && liste && liste.zeitleiste) {
    if (!await zeitleiste.frisch(liste.aufnahmen.length)) return;
    zeigeListe(zeitleistenAngaben());
    await holeZeitleistenmonate();
    return;
  }
  zeigeListe(zeitleistenAngaben());
  if (fotosNachObenGewuenscht) {
    fotosNachObenGewuenscht = false;
    window.scrollTo(0, 0);
  }
  if (zeitleiste.geladen.length === 0) await ladeMehr();
  zeigeErinnerungen().catch(() => {});
  holeZeitleistenmonate().catch(() => {});
  zeigeNachlassHinweis().catch(() => {});
}

// Die Favoriten wie in der Bibliothek des Telefons: nach Tagen gegliedert,
// seitenweise wie die Zeitleiste.
const favoriten = {
  weiter: undefined,
  holeSeite(nach, anzahl) {
    const q = new URLSearchParams({ anzahl: String(anzahl), favoriten: '1' });
    if (nach) q.set('nach', nach);
    return api(`/api/v1/aufnahmen?${q}`);
  },
  async mehr() {
    const d = await this.holeSeite(this.weiter, 200);
    this.weiter = d.weiter;
    return d;
  },
};

async function zeigeFavoriten() {
  markiereNav('favoriten');
  zeigeBereich(['raster']);
  if (stillerLauf && liste && liste.favoriten) {
    const d = await seitenBis((nach, n) => favoriten.holeSeite(nach, n), liste.aufnahmen.length);
    if (ansichtGesperrt()) { live.nochmal = true; return; }
    favoriten.weiter = d.weiter;
    zeigeListe({ aufnahmen: d.aufnahmen, nachTagen: true, favoriten: true, mehr: d.weiter ? () => favoriten.mehr() : null }, t('Favoriten'));
    return;
  }
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
  let kopf = null;
  if (d.aufnahmen.length > 0) {
    // Endgültig löschen (#296) – vorher ging das nur am Rechner ohne Server.
    kopf = el('div', 'reisekopf');
    const leeren = el('button', 'knopf', t('Papierkorb leeren'));
    leeren.type = 'button';
    leeren.addEventListener('click', () => endgueltigLoeschen(null, d.aufnahmen.length));
    kopf.append(leeren);
  }
  zeigeListe({ aufnahmen: d.aufnahmen, papierkorb: true, kopf }, t('Papierkorb'));
  if (d.aufnahmen.length === 0) $('ende').textContent = t('Der Papierkorb ist leer.');
}

// Löscht [aufnahmen] endgültig – ohne sie den ganzen Papierkorb (#296).
async function endgueltigLoeschen(aufnahmen, anzahl) {
  const n = aufnahmen ? aufnahmen.length : anzahl;
  if (!confirm(n === 1 ? t('Eine Aufnahme endgültig löschen? Das lässt sich nicht rückgängig machen und gilt auf allen Geräten.') : t('{n} Aufnahmen endgültig löschen? Das lässt sich nicht rückgängig machen und gilt auf allen Geräten.', { n }))) return;
  try {
    const r = await api('/api/v1/papierkorb/leeren', { methode: 'POST', json: aufnahmen ? { ids: aufnahmen.map((a) => a.id) } : { alle: true } });
    auswahlAufheben();
    await zeigePapierkorb();
    $('ende').textContent = t('{n} endgültig gelöscht', { n: r.geloescht });
  } catch (x) { alert(x.message); }
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
  const [d, neu, g, p, k] = await Promise.all([
    api('/api/v1/alben'),
    // Was andere in geteilte Alben gelegt haben (#295).
    api('/api/v1/kontobeitraege').catch(() => ({ alben: [] })),
    api('/api/v1/geteilt').catch(() => ({ alben: [] })),
    api('/api/v1/partner').catch(() => ({ mitMir: [] })),
    api('/api/v1/intelligente-alben').catch(() => ({ alben: [] })),
  ]);
  if (unveraendert([d, neu, g, p, k])) return;
  $('karten').replaceChildren();
  const neuIn = new Map(neu.alben.map((x) => [x.id, x.anzahl]));
  if (d.alben.length === 0) $('karten').append(el('p', 'leise', t('Noch keine Alben.')));
  for (const a of d.alben) {
    const n = neuIn.get(a.id);
    $('karten').append(karte(a.titelbild ? miniaturUrl(a.titelbild) : null, a.name, anzahlText(a.anzahl), `#/alben/${encodeURIComponent(a.id)}`, {
      kennzeichen: n ? t('{n} neu', { n }) : a.geteilt ? t('Geteilt') : a.automatisch ? t('Automatisch') : null,
    }));
  }
  // Was andere Konten mit diesem teilen (#105) – Alben und ganze
  // Bibliotheken (#293).
  if (g.alben.length || p.mitMir.length) {
    $('karten').append(el('h3', 'karten-abschnitt', t('Geteilt mit mir')));
    for (const b of p.mitMir) {
      const basis = `/api/v1/partner/von/${encodeURIComponent(b.konto)}/aufnahmen`;
      const bild = b.titelbild ? `${basis}/${encodeURIComponent(b.titelbild)}/miniatur${b.titelstand ? `?v=${encodeURIComponent(b.titelstand)}` : ''}` : null;
      $('karten').append(karte(bild, t('Bibliothek von {name}', { name: b.name }), anzahlText(b.anzahl), `#/partner/${encodeURIComponent(b.konto)}`, {
        kennzeichen: t('Ganze Bibliothek'),
      }));
    }
    for (const a of g.alben) {
      const basis = `/api/v1/geteilt/${encodeURIComponent(a.id)}/aufnahmen`;
      const bild = a.titelbild ? `${basis}/${encodeURIComponent(a.titelbild)}/miniatur${a.titelstand ? `?v=${encodeURIComponent(a.titelstand)}` : ''}` : null;
      $('karten').append(karte(bild, a.name, anzahlText(a.anzahl), `#/geteilt/${encodeURIComponent(a.id)}`, {
        zusatz: t('von {name}', { name: a.besitzer }),
      }));
    }
  }
  // Die gemerkten Suchen – wie am Rechner (#187).
  if (k.alben.length) {
    $('karten').append(el('h3', 'karten-abschnitt', t('Intelligente Alben')));
    for (const a of k.alben) {
      const karteKlug = karte(null, a.name, a.inhalt ? t('Sucht nach Bildinhalt') : t('Gemerkte Suche'), `#/alben/klug/${encodeURIComponent(a.id)}`);
      karteKlug.classList.add('intelligent');
      karteKlug.querySelector('.albumbild').append(symbol('intelligent'));
      $('karten').append(karteKlug);
    }
  }
}

// Ein intelligentes Album: die gemerkte Suche, frisch ausgeführt.
async function zeigeIntelligentesAlbum(id) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  let d;
  try {
    d = await api(`/api/v1/intelligente-alben/${encodeURIComponent(id)}`);
  } catch (x) {
    if (x.status === 404) { meldung(t('Der Server hat kein Modell für die Bildsuche – suche nach Text.')); location.hash = '#/alben'; return; }
    throw x;
  }
  const kopf = el('div', 'reisekopf');
  const diashow = el('button', 'knopf', t('Diashow'));
  diashow.type = 'button';
  diashow.addEventListener('click', () => starteDiashow(liste.aufnahmen, 0));
  const weg = el('button', 'knopf', t('Album löschen'));
  weg.type = 'button';
  weg.addEventListener('click', async () => {
    if (!confirm(t('„{name}“ löschen? Die Fotos bleiben, nur die gemerkte Suche geht.', { name: d.name }))) return;
    try { await befehl('sucheVergessen', { sucheId: id }); location.hash = '#/alben'; } catch (x) { meldung(x.message); }
  });
  kopf.append(diashow, weg);
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, d.name);
}

// --- Orte (Issue #173) --------------------------------------------------------
//
// Wie „Orte“ in Immich und auf dem Telefon: die Länder als Karten mit
// Titelbild, darin die Städte; gerechnet im Kern (ortsuebersicht.dart).

let orteListe = null;

async function zeigeOrte() {
  markiereNav('orte');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Orte');
  const d = await api(`/api/v1/laender?sprache=${SPRACHE}`);
  orteListe = d.laender;
  if (unveraendert(d)) return;
  $('karten').replaceChildren();
  if (!d.laender.length) $('karten').append(el('p', 'leise', t('Noch keine Orte. Sie entstehen, sobald Aufnahmen einen Ort tragen und die Ortsdaten eingerichtet sind.')));
  for (const l of d.laender) {
    const n = l.staedte.length;
    $('karten').append(karte(l.miniatur ? miniaturUrl(l.titelbild) : null, l.name, anzahlText(l.anzahl), `#/orte/${encodeURIComponent(l.land)}`, {
      zusatz: n ? (n === 1 ? l.staedte[0].stadt : t('{n} Orte', { n })) : null,
    }));
  }
}

async function zeigeOrt(land, stadt) {
  markiereNav('orte');
  zeigeBereich(['raster']);
  const q = new URLSearchParams({ land });
  if (stadt) q.set('stadt', stadt);
  const [d, uebersicht] = await Promise.all([
    api(`/api/v1/laender/aufnahmen?${q}`),
    orteListe ? Promise.resolve({ laender: orteListe }) : api(`/api/v1/laender?sprache=${SPRACHE}`),
  ]);
  orteListe = uebersicht.laender;
  const l = orteListe.find((x) => x.land === land);
  const name = l ? l.name : land;
  let kopf;
  if (!stadt && l && l.staedte.length > 1) {
    // Die Städte des Landes als Reihe über den Aufnahmen.
    kopf = el('div', 'ortsreihe');
    for (const s of l.staedte) {
      kopf.append(karte(s.miniatur ? miniaturUrl(s.titelbild) : null, s.stadt, anzahlText(s.anzahl), `#/orte/${encodeURIComponent(land)}/${encodeURIComponent(s.stadt)}`));
    }
  }
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, stadt ? `${stadt} · ${name}` : name);
}

async function zeigeAlbum(id) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  const [d, neu, teilungen, regel] = await Promise.all([
    api(`/api/v1/alben/${encodeURIComponent(id)}`),
    api('/api/v1/kontobeitraege').catch(() => ({ alben: [] })),
    api(`/api/v1/alben/${encodeURIComponent(id)}/teilungen`).catch(() => ({ teilungen: [] })),
    // Ein älterer Server kennt keine Regeln (#298): dann ohne Knopf.
    api(`/api/v1/alben/${encodeURIComponent(id)}/regel`).catch(() => null),
  ]);
  const kopf = el('div', 'reisekopf');
  // Neue Beiträge anderer Konten (#295): einmal sagen, dann gelten sie als
  // gesehen.
  const hier = neu.alben.find((x) => x.id === id);
  if (hier) {
    kopf.append(el('span', 'leise', t('{n} neu von {namen}', { n: hier.anzahl, namen: hier.von.join(', ') })));
    api(`/api/v1/alben/${encodeURIComponent(id)}/kontobeitraege/gesehen`, { methode: 'POST' }).catch(() => {});
  }
  const teilen = el('button', 'knopf', t('Als Link teilen …'));
  teilen.type = 'button';
  teilen.addEventListener('click', () => oeffneLinkDialog({ album: d.album.id }, d.album.name));
  const diashow = el('button', 'knopf', t('Diashow'));
  diashow.type = 'button';
  diashow.addEventListener('click', () => starteDiashow(liste.aufnahmen, 0));
  const konten = el('button', 'knopf', t('Mit Konten teilen …'));
  konten.type = 'button';
  konten.addEventListener('click', () => oeffneKontenDialog(d.album.id, d.album.name));
  kopf.append(diashow, teilen, konten);
  if (regel) {
    const r = regel.regel;
    const fuellen = el('button', 'knopf', r ? t('Automatisch füllen ✓') : t('Automatisch füllen …'));
    fuellen.type = 'button';
    fuellen.addEventListener('click', () => oeffneRegelDialog({ art: 'album', id: d.album.id, name: d.album.name }, r));
    kopf.append(fuellen);
    if (r) kopf.append(el('span', 'leise', regelText(r)));
  }
  // Kommentare und „Gefällt mir“, sobald jemand mitschaut (#297).
  const aktivitaet = teilungen.teilungen.length ? neueAktivitaet(`/api/v1/alben/${encodeURIComponent(id)}`, kopf) : null;
  zeigeListe({ aufnahmen: d.aufnahmen, kopf, aktivitaet }, d.album.name);
  if (aktivitaet) ladeAktivitaet();
}

// --- Collagen (#301) --------------------------------------------------------------
//
// Zwei bis neun Fotos in einer Vorlage, als neues Foto in der Bibliothek.
// Gezeichnet wird am Server; die Vorschau holt der Browser klein, sobald
// sich etwas ändert.

const COLLAGE_VORLAGEN = {
  raster: 'Raster',
  reihe: 'Nebeneinander',
  stapel: 'Untereinander',
  gross_links: 'Gross links',
  gross_oben: 'Gross oben',
};
const COLLAGE_FORMATE = [['quadrat', 'Quadrat', 1], ['quer', '3:2', 1.5], ['hoch', '2:3', 2 / 3], ['story', '9:16', 9 / 16]];
const COLLAGE_FARBEN = ['#ffffff', '#000000', '#2b2b2b', '#f3ebdd'];

// Welche Vorlagen es für n Fotos gibt – dieselben wie im Kern
// (packages/kern/lib/services/collage.dart, collagevorlagen).
function collageVorlagenFuer(n) {
  const v = ['raster'];
  if (n > 2 && n <= 4) v.push('reihe');
  if (n <= 4) v.push('stapel');
  if (n >= 3) v.push('gross_links', 'gross_oben');
  return v;
}

const collage = { ids: [], vorlage: 'raster', format: 'quadrat', abstand: 0.01, ecken: 0, hintergrund: '#ffffff', url: null, nummer: 0, uhr: null };

function oeffneCollage(aufnahmen) {
  const bilder = aufnahmen.filter((a) => a.art !== 'video' && !a.konto);
  if (bilder.length < 2 || bilder.length > 9) { meldung(t('Eine Collage braucht 2 bis 9 Fotos.')); return; }
  // Älteste zuerst – wie sie im Album stünden.
  bilder.sort((a, b) => new Date(a.aufgenommen) - new Date(b.aufgenommen));
  Object.assign(collage, { ids: bilder.map((a) => a.id), vorlage: 'raster' });
  const vor = $('collage-vorlagen');
  vor.replaceChildren(...collageVorlagenFuer(bilder.length).map((id) => {
    const b = el('button', 'knopf', t(COLLAGE_VORLAGEN[id]));
    b.type = 'button';
    b.dataset.vorlage = id;
    b.addEventListener('click', () => { collage.vorlage = id; collageZeichnen(); });
    return b;
  }));
  const fmt = $('collage-format');
  fmt.replaceChildren(...COLLAGE_FORMATE.map(([id, name]) => new Option(t(name), id)));
  fmt.value = collage.format;
  const farben = $('collage-farben');
  farben.replaceChildren(...COLLAGE_FARBEN.map((f) => {
    const b = el('button', 'farbknopf');
    b.type = 'button';
    b.style.background = f;
    b.dataset.farbe = f;
    b.setAttribute('aria-label', f);
    b.addEventListener('click', () => { collage.hintergrund = f; collageZeichnen(); });
    return b;
  }));
  zeigeCollageReihe();
  $('collage-abstand').value = String(collage.abstand * 1000);
  $('collage-ecken').value = String(collage.ecken * 1000);
  $('collage-meldung').textContent = '';
  $('collage-dialog').showModal();
  collageZeichnen();
}

function zeigeCollageReihe() {
  const reihe = $('collage-reihe');
  reihe.replaceChildren(...collage.ids.map((id, i) => {
    const b = el('button', `collagekachel${i === 0 ? ' vorn' : ''}`);
    b.type = 'button';
    const img = el('img'); img.alt = ''; img.src = miniaturUrl(id);
    b.append(img);
    b.addEventListener('click', () => {
      if (i === 0) return;
      collage.ids = [id, ...collage.ids.filter((x) => x !== id)];
      zeigeCollageReihe();
      collageZeichnen();
    });
    return b;
  }));
}

function collageWahl(vorschau) {
  return { ids: collage.ids, vorlage: collage.vorlage, format: collage.format, abstand: collage.abstand, ecken: collage.ecken, hintergrund: collage.hintergrund, ...(vorschau ? { vorschau: true } : {}) };
}

function collageZeichnen() {
  for (const b of $('collage-vorlagen').children) b.classList.toggle('gewaehlt', b.dataset.vorlage === collage.vorlage);
  for (const b of $('collage-farben').children) b.classList.toggle('gewaehlt', b.dataset.farbe === collage.hintergrund);
  const [, , seiten] = COLLAGE_FORMATE.find(([id]) => id === collage.format);
  $('collage-bild').style.aspectRatio = String(seiten);
  clearTimeout(collage.uhr);
  collage.uhr = setTimeout(async () => {
    const nummer = ++collage.nummer;
    $('collage-bild').classList.add('laedt');
    try {
      const r = await fetch('/api/v1/collage', { method: 'POST', credentials: 'same-origin', headers: { 'X-PV-Web': '1', 'Content-Type': 'application/json' }, body: JSON.stringify(collageWahl(true)) });
      if (!r.ok) { let f = null; try { f = (await r.json()).fehler; } catch (_) { /* leer */ } throw new Error(f ? t(f) : t('Fehler {n}', { n: r.status })); }
      const blob = await r.blob();
      if (nummer !== collage.nummer) return;
      if (collage.url) URL.revokeObjectURL(collage.url);
      collage.url = URL.createObjectURL(blob);
      $('collage-bild').src = collage.url;
      $('collage-meldung').textContent = '';
    } catch (x) {
      if (nummer === collage.nummer) $('collage-meldung').textContent = x.message;
    } finally {
      if (nummer === collage.nummer) $('collage-bild').classList.remove('laedt');
    }
  }, 250);
}

$('collage-format').addEventListener('change', (e) => { collage.format = e.target.value; collageZeichnen(); });
$('collage-abstand').addEventListener('input', (e) => { collage.abstand = Number(e.target.value) / 1000; collageZeichnen(); });
$('collage-ecken').addEventListener('input', (e) => { collage.ecken = Number(e.target.value) / 1000; collageZeichnen(); });
$('collage-abbrechen').addEventListener('click', () => $('collage-dialog').close());
$('collage-speichern').addEventListener('click', async () => {
  const knopf = $('collage-speichern');
  knopf.disabled = true;
  $('collage-meldung').textContent = t('Collage wird gespeichert …');
  try {
    await api('/api/v1/collage', { methode: 'POST', json: collageWahl(false) });
    $('collage-dialog').close();
    auswahlAufheben();
    zeitleiste.leeren();
    // Die Ansicht neu – in der Zeitleiste steht die Collage dann schon.
    await zeigeWeg();
    meldung(t('Collage gespeichert – sie steht in der Zeitleiste bei ihren Fotos.'));
  } catch (x) {
    $('collage-meldung').textContent = x.message;
  } finally {
    knopf.disabled = false;
  }
});
$('auswahl-collage').addEventListener('click', () => oeffneCollage(gewaehlte()));

// --- Nachlasskontakt (#300) -----------------------------------------------------
//
// Wen dieses Konto benennt, und für wen es benannt ist – auf der Kontoseite.
// Verlangt jemand Zugang, steht das über der Zeitleiste, bis widersprochen
// oder die Frist um ist.

const nachlassTag = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium' });
const nachlassDatum = (iso) => nachlassTag.format(new Date(iso));
const fristText = (n) => t('{n} Tage', { n });

function nachlassStand(e, eigen) {
  if (e.freigegeben) return eigen ? t('hat Zugang seit {tag}', { tag: nachlassDatum(e.freigegeben) }) : t('Zugang seit {tag} – unter „Geteilt mit mir“', { tag: nachlassDatum(e.freigegeben) });
  if (e.angefordert) return t('verlangt Zugang – ohne Widerspruch ab {tag}', { tag: nachlassDatum(e.faellig) });
  return t('Frist: {frist}', { frist: fristText(e.frist) });
}

async function nachlassTue(pfad, methode, json) {
  try { await api(pfad, { methode, json }); } catch (x) { meldung(x.message); return false; }
  await Promise.all([zeigeNachlass().catch(() => {}), zeigeNachlassHinweis().catch(() => {})]);
  return true;
}

async function zeigeNachlass() {
  const [d, andere] = await Promise.all([api('/api/v1/nachlass'), api('/api/v1/konten/andere')]);
  const meine = $('nachlass-meine');
  meine.replaceChildren();
  for (const e of d.kontakte) {
    const zeile = el('li', 'teilungszeile');
    const knoepfe = [];
    if (e.angefordert && !e.freigegeben) {
      const nein = el('button', 'knopf', t('Ablehnen'));
      nein.type = 'button';
      nein.addEventListener('click', () => nachlassTue(`/api/v1/nachlass/${encodeURIComponent(e.konto)}/ablehnen`, 'POST'));
      knoepfe.push(nein);
    }
    const weg = el('button', 'knopf', t('Entfernen'));
    weg.type = 'button';
    weg.addEventListener('click', () => nachlassTue(`/api/v1/nachlass/${encodeURIComponent(e.konto)}`, 'DELETE'));
    knoepfe.push(weg);
    zeile.append(el('span', 'name', e.name), ...knoepfe, el('span', 'leise klein einschraenkung', nachlassStand(e, true)));
    meine.append(zeile);
  }
  if (!d.kontakte.length) meine.append(el('li', 'leise', t('Noch niemand benannt.')));
  const schon = new Set(d.kontakte.map((e) => e.konto));
  const frei = andere.konten.filter((k) => !schon.has(k.id));
  $('nachlass-wahl').replaceChildren(...frei.map((k) => new Option(k.name, k.id)));
  const frist = $('nachlass-frist');
  if (!frist.options.length) {
    frist.replaceChildren(...d.fristen.map((f) => new Option(fristText(f), String(f))));
    frist.value = '30';
  }
  $('nachlass-neu').hidden = !frei.length;

  const fuer = $('nachlass-fuer');
  fuer.replaceChildren();
  $('nachlass-fuer-titel').hidden = !d.fuerMich.length;
  for (const e of d.fuerMich) {
    const zeile = el('li', 'teilungszeile');
    const knoepfe = [];
    if (!e.freigegeben) {
      const b = el('button', 'knopf', e.angefordert ? t('Anfrage zurückziehen') : t('Zugang verlangen'));
      b.type = 'button';
      b.addEventListener('click', () => {
        const pfad = `/api/v1/nachlass/von/${encodeURIComponent(e.konto)}/anfordern`;
        if (e.angefordert) { nachlassTue(pfad, 'DELETE'); return; }
        if (!confirm(t('Zugang zur Bibliothek von {name} verlangen? {name} sieht die Anfrage und kann {frist} lang widersprechen. Danach siehst du die ganze Bibliothek, nur zum Ansehen und Herunterladen.', { name: e.name, frist: fristText(e.frist) }))) return;
        nachlassTue(pfad, 'POST');
      });
      knoepfe.push(b);
    }
    zeile.append(el('span', 'name', e.name), ...knoepfe, el('span', 'leise klein einschraenkung', nachlassStand(e, false)));
    fuer.append(zeile);
  }
}

$('nachlass-hinzu').addEventListener('click', () => {
  const konto = $('nachlass-wahl').value;
  if (!konto) return;
  nachlassTue(`/api/v1/nachlass/${encodeURIComponent(konto)}`, 'PUT', { frist: Number($('nachlass-frist').value) });
});

// Über der Zeitleiste: wer gerade Zugang verlangt.
async function zeigeNachlassHinweis() {
  const box = $('nachlass-hinweis');
  let d;
  try { d = await api('/api/v1/nachlass'); } catch (_) { box.hidden = true; return; }
  const offen = d.kontakte.filter((e) => e.angefordert && !e.freigegeben);
  box.replaceChildren();
  box.hidden = !offen.length;
  for (const e of offen) {
    const zeile = el('div', 'nachlasszeile');
    const nein = el('button', 'knopf', t('Ablehnen'));
    nein.type = 'button';
    nein.addEventListener('click', () => nachlassTue(`/api/v1/nachlass/${encodeURIComponent(e.konto)}/ablehnen`, 'POST'));
    zeile.append(el('span', null, t('{name} verlangt Zugang zu deiner Bibliothek (Nachlasskontakt). Ohne Widerspruch bekommt {name} ihn am {tag}.', { name: e.name, tag: nachlassDatum(e.faellig) })), nein);
    box.append(zeile);
  }
}

// --- Alben, die sich selbst füllen (#298), und was ein Partner sieht (#299) ---
//
// Ein Dialog für beides: Personen wählen, wahlweise ein Tag. Beim Album
// dazu, ob eine der Personen genügt oder alle zusammen drauf sein müssen;
// bei der Partnerfreigabe genügt immer eine.

const tagFormat = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium' });
const tagText = (t0) => { const [j, m, d] = t0.split('-').map(Number); return tagFormat.format(new Date(j, m - 1, d)); };

// „Anna, Ben · ab 1. Jan. 2020“ – für Album und Partner.
function regelText(r) {
  const teile = [];
  const namen = (r.personen || []).map((p) => p.name);
  if (namen.length) teile.push(r.alle ? t('{namen} zusammen', { namen: namen.join(' & ') }) : t('mit {namen}', { namen: namen.join(', ') }));
  if (r.fehlend) teile.push(r.fehlend === 1 ? t('Eine gewählte Person gibt es nicht mehr.') : t('{n} gewählte Personen gibt es nicht mehr.', { n: r.fehlend }));
  if (r.ab) teile.push(t('ab {tag}', { tag: tagText(r.ab) }));
  return teile.join(' · ');
}

let regelZiel = null;
let regelPersonen = [];
const regelGewaehlt = new Set();

async function oeffneRegelDialog(ziel, vorher) {
  regelZiel = ziel;
  regelGewaehlt.clear();
  for (const p of (vorher && vorher.personen) || []) regelGewaehlt.add(p.id);
  const album = ziel.art === 'album';
  $('regel-titel').textContent = album ? t('„{name}“ automatisch füllen', { name: ziel.name }) : t('Was {name} sieht', { name: ziel.name });
  $('regel-hinweis').textContent = album
    ? t('Fotos der gewählten Personen kommen von selbst in dieses Album – auch solche, auf denen sie erst später erkannt werden. Was du herausnimmst, bleibt draussen.')
    : t('Ohne Auswahl sieht {name} deine ganze Bibliothek. Mit Personen nur Fotos, auf denen mindestens eine davon ist – das gilt für jede Datei, nicht nur für die Liste.', { name: ziel.name });
  $('regel-art').hidden = !album;
  document.querySelector(`input[name="regel-art"][value="${vorher && vorher.alle ? 'alle' : 'eine'}"]`).checked = true;
  $('regel-ab').value = (vorher && vorher.ab) || '';
  $('regel-suche').value = '';
  $('regel-meldung').textContent = vorher && vorher.fehlend
    ? (vorher.fehlend === 1 ? t('Eine gewählte Person gibt es nicht mehr.') : t('{n} gewählte Personen gibt es nicht mehr.', { n: vorher.fehlend }))
    : '';
  $('regel-weg').hidden = !(album && vorher);
  $('regel-personen').replaceChildren(el('li', 'leise', t('Lade …')));
  $('regel-dialog').showModal();
  try {
    regelPersonen = (await api('/api/v1/personen')).personen.filter((p) => p.name);
  } catch (x) { regelPersonen = []; $('regel-meldung').textContent = x.message; }
  if (regelZiel === ziel) zeigeRegelPersonen();
}

function zeigeRegelPersonen() {
  const q = $('regel-suche').value.trim().toLocaleLowerCase(GEBIET);
  const passt = regelPersonen
    .filter((p) => !q || p.name.toLocaleLowerCase(GEBIET).includes(q))
    // Gewählte zuerst, sonst wie der Server sie liefert: die häufigsten oben.
    .sort((a, b) => Number(regelGewaehlt.has(b.id)) - Number(regelGewaehlt.has(a.id)));
  const ul = $('regel-personen');
  ul.replaceChildren();
  for (const p of passt.slice(0, 300)) {
    const li = el('li');
    const l = el('label');
    const c = el('input');
    c.type = 'checkbox';
    c.checked = regelGewaehlt.has(p.id);
    c.addEventListener('change', () => { if (c.checked) regelGewaehlt.add(p.id); else regelGewaehlt.delete(p.id); });
    l.append(c, el('span', null, p.name), el('span', 'leise klein anzahl', String(p.anzahl)));
    li.append(l);
    ul.append(li);
  }
  if (!passt.length) ul.append(el('li', 'leise', regelPersonen.length ? t('Keine Person gefunden.') : t('Noch keine Personen mit Namen.')));
}

$('regel-suche').addEventListener('input', zeigeRegelPersonen);
$('regel-abbrechen').addEventListener('click', () => $('regel-dialog').close());
$('regel-speichern').addEventListener('click', async () => {
  const z = regelZiel;
  if (!z) return;
  const personen = [...regelGewaehlt];
  const ab = $('regel-ab').value || null;
  if (personen.length > 20) { $('regel-meldung').textContent = t('Höchstens 20 Personen.'); return; }
  try {
    if (z.art === 'album') {
      if (!personen.length) { $('regel-meldung').textContent = t('Wähle mindestens eine Person.'); return; }
      const alle = document.querySelector('input[name="regel-art"]:checked').value === 'alle';
      const r = await api(`/api/v1/alben/${encodeURIComponent(z.id)}/regel`, { methode: 'PUT', json: { personen, alle, ab } });
      $('regel-dialog').close();
      meldung(r.dazu === 1 ? t('Eine Aufnahme dazugelegt') : t('{n} Aufnahmen dazugelegt', { n: r.dazu }));
      await zeigeAlbum(z.id);
    } else {
      await api(`/api/v1/partner/${encodeURIComponent(z.konto)}`, { methode: 'PUT', json: { ab, personen } });
      $('regel-dialog').close();
      await zeigePartner();
    }
  } catch (x) { $('regel-meldung').textContent = x.message; }
});
$('regel-weg').addEventListener('click', async () => {
  const z = regelZiel;
  if (!z || z.art !== 'album') return;
  try {
    await api(`/api/v1/alben/${encodeURIComponent(z.id)}/regel`, { methode: 'DELETE' });
    $('regel-dialog').close();
    meldung(t('Das Album füllt sich nicht mehr selbst. Was darin liegt, bleibt.'));
    await zeigeAlbum(z.id);
  } catch (x) { $('regel-meldung').textContent = x.message; }
});

// --- Alben zwischen Konten teilen (#105) ---------------------------------------
//
// Der Besitzer teilt ein Album mit anderen Konten dieses Servers, jedes
// zum Ansehen oder zum Beitragen. Sie finden es unter „Geteilt mit mir“ –
// hier und auf dem Telefon. Was sie beitragen, kommt ohne Rückfrage in die
// Bibliothek des Besitzers und ins Album.

let kontenAlbum = null;

async function oeffneKontenDialog(album, name) {
  kontenAlbum = album;
  $('konten-titel').textContent = t('„{name}“ mit Konten teilen', { name });
  $('konten-meldung').textContent = '';
  $('konten-dialog').showModal();
  await zeigeTeilungen();
}

async function zeigeTeilungen() {
  const album = kontenAlbum;
  const pfad = `/api/v1/alben/${encodeURIComponent(album)}/teilungen`;
  let teilungen, andere;
  try {
    [teilungen, andere] = await Promise.all([api(pfad), api('/api/v1/konten/andere')]);
  } catch (x) { $('konten-meldung').textContent = x.message; return; }
  if (album !== kontenAlbum) return;
  const zeilen = $('konten-liste');
  zeilen.replaceChildren();
  for (const z of teilungen.teilungen) {
    const zeile = el('li', 'teilungszeile');
    const recht = el('select');
    recht.append(new Option(t('Ansehen'), ''), new Option(t('Beitragen'), '1'));
    recht.value = z.beitragen ? '1' : '';
    recht.setAttribute('aria-label', t('Recht von {name}', { name: z.name }));
    recht.addEventListener('change', () => teileMit(z.konto, recht.value === '1'));
    const weg = el('button', 'knopf', t('Entfernen'));
    weg.type = 'button';
    weg.addEventListener('click', async () => {
      try { await api(`${pfad}/${encodeURIComponent(z.konto)}`, { methode: 'DELETE' }); } catch (x) { $('konten-meldung').textContent = x.message; return; }
      await zeigeTeilungen();
    });
    zeile.append(el('span', 'name', z.name), recht, weg);
    zeilen.append(zeile);
  }
  if (!teilungen.teilungen.length) zeilen.append(el('li', 'leise', t('Mit niemandem geteilt.')));
  const schon = new Set(teilungen.teilungen.map((z) => z.konto));
  const frei = andere.konten.filter((k) => !schon.has(k.id));
  const wahl = $('konten-wahl');
  wahl.replaceChildren(...frei.map((k) => new Option(k.name, k.id)));
  $('konten-neu').hidden = !frei.length;
  if (!andere.konten.length) zeilen.append(el('li', 'leise', t('Auf diesem Server gibt es kein weiteres Konto.')));
}

async function teileMit(konto, beitragen) {
  try {
    await api(`/api/v1/alben/${encodeURIComponent(kontenAlbum)}/teilungen/${encodeURIComponent(konto)}`, { methode: 'PUT', json: { beitragen } });
  } catch (x) { $('konten-meldung').textContent = x.message; return; }
  await zeigeTeilungen();
  // Die Karte in der Albenliste trägt das Kennzeichen erst nach dem Neuladen.
}

$('konten-hinzu').addEventListener('click', () => {
  const konto = $('konten-wahl').value;
  if (konto) teileMit(konto, $('konten-recht').value === '1');
});

// --- Partnerfreigabe (#293) -----------------------------------------------------
//
// Die ganze Bibliothek für ein anderes Konto zum Ansehen: verwaltet auf der
// Kontoseite, zu sehen unter „Geteilt mit mir“ als blätternde Zeitleiste.

async function zeigePartner() {
  const [p, andere] = await Promise.all([api('/api/v1/partner'), api('/api/v1/konten/andere')]);
  const zeilen = $('partner');
  zeilen.replaceChildren();
  for (const k of p.meine) {
    const zeile = el('li', 'teilungszeile');
    const weg = el('button', 'knopf', t('Entfernen'));
    weg.type = 'button';
    weg.addEventListener('click', async () => {
      try { await api(`/api/v1/partner/${encodeURIComponent(k.konto)}`, { methode: 'DELETE' }); } catch (x) { meldung(x.message); return; }
      await zeigePartner();
    });
    // Nur ab einem Tag, nur mit bestimmten Personen (#299).
    const eng = el('button', 'knopf', t('Einschränken …'));
    eng.type = 'button';
    eng.addEventListener('click', () => oeffneRegelDialog({ art: 'partner', konto: k.konto, name: k.name }, k.ab || k.personen ? k : null));
    zeile.append(el('span', 'name', k.name), eng, weg);
    zeile.append(el('span', 'leise klein einschraenkung', k.ab || k.personen ? regelText(k) : t('Die ganze Bibliothek')));
    zeilen.append(zeile);
  }
  if (!p.meine.length) zeilen.append(el('li', 'leise', t('Mit niemandem geteilt.')));
  const schon = new Set(p.meine.map((k) => k.konto));
  const frei = andere.konten.filter((k) => !schon.has(k.id));
  $('partner-wahl').replaceChildren(...frei.map((k) => new Option(k.name, k.id)));
  $('partner-neu').hidden = !frei.length;
}

$('partner-hinzu').addEventListener('click', async () => {
  const konto = $('partner-wahl').value;
  if (!konto) return;
  try { await api(`/api/v1/partner/${encodeURIComponent(konto)}`, { methode: 'PUT' }); } catch (x) { meldung(x.message); return; }
  await zeigePartner();
});

async function zeigePartnerbibliothek(konto) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  const basis = `/api/v1/partner/von/${encodeURIComponent(konto)}/aufnahmen`;
  let weiter = null;
  const seite = async () => {
    const d = await api(`${basis}?anzahl=300${weiter ? `&nach=${encodeURIComponent(weiter)}` : ''}`);
    weiter = d.weiter;
    return d;
  };
  let erste;
  try {
    erste = await seite();
  } catch (x) {
    if (x.status === 404) { meldung(t('Diese Bibliothek ist nicht mehr mit dir geteilt.')); location.hash = '#/alben'; return; }
    throw x;
  }
  const kopf = el('div', 'reisekopf');
  const diashow = el('button', 'knopf', t('Diashow'));
  diashow.type = 'button';
  diashow.addEventListener('click', () => starteDiashow(liste.aufnahmen, 0));
  const verlassen = el('button', 'knopf', t('Nicht mehr anzeigen'));
  verlassen.type = 'button';
  verlassen.addEventListener('click', async () => {
    if (!confirm(t('Die Bibliothek von {name} nicht mehr anzeigen? Teilen kann nur {name} sie wieder.', { name: erste.name }))) return;
    try { await api(`/api/v1/partner/von/${encodeURIComponent(konto)}`, { methode: 'DELETE' }); location.hash = '#/alben'; } catch (x) { meldung(x.message); }
  });
  // In der eigenen Zeitleiste zeigen (#299) – das gilt für dieses Konto,
  // im Browser und auf dem Telefon.
  const stand = (await api('/api/v1/partner').catch(() => ({ mitMir: [] }))).mitMir.find((b) => b.konto === konto);
  if (stand && stand.inZeitleiste !== undefined) {
    const schalter = el('label', 'leise');
    const kasten = el('input');
    kasten.type = 'checkbox';
    kasten.checked = !!stand.inZeitleiste;
    kasten.addEventListener('change', async () => {
      try {
        await api(`/api/v1/partner/von/${encodeURIComponent(konto)}/zeitleiste`, { methode: 'PUT', json: { an: kasten.checked } });
        zeitleiste.leeren();
      } catch (x) { kasten.checked = !kasten.checked; meldung(x.message); }
    });
    schalter.append(kasten, document.createTextNode(` ${t('In meiner Zeitleiste zeigen')}`));
    kopf.append(schalter);
  }
  kopf.append(diashow, verlassen);
  zeigeListe({
    aufnahmen: erste.aufnahmen,
    nachTagen: true,
    kopf,
    fremd: basis,
    mehr: erste.weiter ? () => seite() : null,
  }, t('Bibliothek von {name}', { name: erste.name }));
}

// Ein Album, das ein anderes Konto teilt: dasselbe Raster und derselbe
// Betrachter, die Dateien über die Teilung (`liste.fremd`).
async function zeigeGeteiltesAlbum(id) {
  markiereNav('alben');
  zeigeBereich(['raster']);
  let d;
  try {
    d = await api(`/api/v1/geteilt/${encodeURIComponent(id)}`);
  } catch (x) {
    if (x.status === 404) { meldung(t('Dieses Album ist nicht mehr mit dir geteilt.')); location.hash = '#/alben'; return; }
    throw x;
  }
  const kopf = el('div', 'reisekopf');
  kopf.append(el('span', 'leise', t('Geteilt von {name}', { name: d.album.besitzer })));
  const diashow = el('button', 'knopf', t('Diashow'));
  diashow.type = 'button';
  diashow.addEventListener('click', () => starteDiashow(liste.aufnahmen, 0));
  kopf.append(diashow);
  if (d.album.beitragen) {
    const wahl = el('input');
    wahl.type = 'file';
    wahl.accept = 'image/*,video/*';
    wahl.multiple = true;
    wahl.hidden = true;
    const hinzu = el('button', 'knopf', t('Fotos hinzufügen …'));
    hinzu.type = 'button';
    hinzu.addEventListener('click', () => wahl.click());
    const stand = el('span', 'leise klein');
    wahl.addEventListener('change', async () => {
      const dateien = [...wahl.files];
      wahl.value = '';
      if (!dateien.length) return;
      hinzu.disabled = true;
      let gut = 0;
      for (let i = 0; i < dateien.length; i++) {
        const status = await schickeBeitrag(id, dateien[i], (anteil) => {
          stand.textContent = t('{i} von {n} · {p} %', { i: i + 1, n: dateien.length, p: Math.round(anteil * 100) });
        });
        if (status === 201) gut++;
        else if (status === 507) { meldung(t('Der Speicher des Servers ist voll.')); break; }
        else if (status === 403 || status === 404) { meldung(t('Du darfst in dieses Album nichts mehr legen.')); break; }
        else meldung(t('„{name}“ ging nicht (Fehler {n}).', { name: dateien[i].name, n: status }));
      }
      hinzu.disabled = false;
      stand.textContent = '';
      if (gut) { meldung(t('{n} hinzugefügt', { n: gut })); await zeigeGeteiltesAlbum(id); }
    });
    kopf.append(hinzu, wahl, stand);
  }
  const verlassen = el('button', 'knopf', t('Nicht mehr anzeigen'));
  verlassen.type = 'button';
  verlassen.addEventListener('click', async () => {
    if (!confirm(t('„{name}“ nicht mehr anzeigen? Die Fotos bleiben bei {besitzer}; teilen kann nur {besitzer} es wieder.', { name: d.album.name, besitzer: d.album.besitzer }))) return;
    try { await api(`/api/v1/geteilt/${encodeURIComponent(id)}`, { methode: 'DELETE' }); location.hash = '#/alben'; } catch (x) { meldung(x.message); }
  });
  kopf.append(verlassen);
  const aktivitaet = neueAktivitaet(`/api/v1/geteilt/${encodeURIComponent(id)}`, kopf);
  zeigeListe({ aufnahmen: d.aufnahmen, kopf, fremd: `/api/v1/geteilt/${encodeURIComponent(id)}/aufnahmen`, aktivitaet }, d.album.name);
  ladeAktivitaet();
}

// --- Kommentare und „Gefällt mir“ in geteilten Alben (#297) -------------------
//
// Für den Besitzer (`/api/v1/alben/<Album>`) und für jeden, mit dem das
// Album geteilt ist (`/api/v1/geteilt/<Teilung>`): Kommentare zum Album
// im Kopf, zu einem Foto im Betrachter, dazu „Gefällt mir“ je Foto.

function neueAktivitaet(basis, kopf) {
  const knopf = el('button', 'knopf', t('Kommentare'));
  knopf.type = 'button';
  knopf.addEventListener('click', () => oeffneAlbumkommentare());
  kopf.append(knopf);
  return { basis, daten: { kommentare: [], gefaellt: {} }, knopf };
}

async function ladeAktivitaet() {
  const akt = liste && liste.aktivitaet;
  if (!akt) return;
  let d;
  try { d = await api(`${akt.basis}/aktivitaet`); } catch (_) { return; }
  if (!liste || liste.aktivitaet !== akt) return;
  akt.daten = d;
  const n = d.kommentare.filter((k) => !k.aufnahme).length;
  akt.knopf.textContent = n ? t('Kommentare ({n})', { n }) : t('Kommentare');
  if (!$('betrachter').hidden) zeigeAktivitaetKnoepfe();
}

// Kommentare zu [aufnahme] (ohne: zum Album) mit einem Feld zum Schreiben.
function kommentarBereich(aufnahme) {
  const box = el('div', 'kommentare');
  const zeichne = () => {
    const akt = liste && liste.aktivitaet;
    box.replaceChildren();
    if (!akt) return;
    const hier = akt.daten.kommentare.filter((k) => (k.aufnahme || null) === (aufnahme || null));
    const ul = el('ul', 'kommentarliste');
    for (const k of hier) {
      const li = el('li', 'kommentar');
      const zeile = el('div', 'kommentarkopf');
      zeile.append(el('span', 'name', k.name), el('span', 'leise klein', datumZeit.format(new Date(k.angelegt))));
      if (k.loeschbar) {
        const weg = el('button', 'kommentar-weg', '×');
        weg.type = 'button';
        weg.title = t('Kommentar entfernen');
        weg.setAttribute('aria-label', weg.title);
        weg.addEventListener('click', async () => {
          if (!confirm(t('Diesen Kommentar entfernen?'))) return;
          try { await api(`${akt.basis}/kommentare/${encodeURIComponent(k.id)}`, { methode: 'DELETE' }); } catch (x) { meldung(x.message); return; }
          await ladeAktivitaet();
          zeichne();
        });
        zeile.append(weg);
      }
      li.append(zeile, el('p', 'text', k.text));
      ul.append(li);
    }
    if (!hier.length) ul.append(el('li', 'leise', t('Noch keine Kommentare.')));
    const form = el('form', 'kommentarform');
    const feld = el('textarea');
    feld.rows = 2;
    feld.maxLength = 2000;
    feld.placeholder = t('Kommentar schreiben …');
    feld.setAttribute('aria-label', t('Kommentar'));
    const senden = el('button', 'knopf', t('Senden'));
    senden.type = 'submit';
    form.append(feld, senden);
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const text = feld.value.trim();
      if (!text) return;
      senden.disabled = true;
      try {
        await api(`${akt.basis}/kommentare`, { methode: 'POST', json: aufnahme ? { text, aufnahme } : { text } });
      } catch (x) { meldung(x.message); senden.disabled = false; return; }
      await ladeAktivitaet();
      zeichne();
    });
    box.append(ul, form);
  };
  zeichne();
  return box;
}

function oeffneAlbumkommentare() {
  $('kommentar-titel').textContent = $('raster-titel').textContent || t('Kommentare');
  $('kommentar-inhalt').replaceChildren(kommentarBereich(null));
  $('kommentar-dialog').showModal();
}

// Die beiden Knöpfe im Betrachter: „Gefällt mir“ mit Zahl, Kommentare.
function zeigeAktivitaetKnoepfe() {
  const akt = liste && liste.aktivitaet;
  const a = liste && liste.aufnahmen[offen];
  const an = !!(akt && a);
  $('gefaellt').hidden = !an;
  $('kommentare-knopf').hidden = !an;
  if (!an) return;
  const g = akt.daten.gefaellt[a.id];
  $('gefaellt').textContent = `👍\uFE0E${g && g.anzahl ? ` ${g.anzahl}` : ''}`;
  $('gefaellt').classList.toggle('aktiv', !!(g && g.ich));
  $('gefaellt').setAttribute('aria-pressed', String(!!(g && g.ich)));
  $('gefaellt').title = g && g.namen.length ? t('Gefällt {namen}', { namen: g.namen.join(', ') }) : t('Gefällt mir');
  const n = akt.daten.kommentare.filter((k) => k.aufnahme === a.id).length;
  $('kommentare-knopf').textContent = `💬\uFE0E${n ? ` ${n}` : ''}`;
}

$('gefaellt').addEventListener('click', async () => {
  const akt = liste && liste.aktivitaet;
  const a = liste && liste.aufnahmen[offen];
  if (!akt || !a) return;
  const ich = !!(akt.daten.gefaellt[a.id] && akt.daten.gefaellt[a.id].ich);
  try {
    await api(`${akt.basis}/gefaellt/${encodeURIComponent(a.id)}`, { methode: ich ? 'DELETE' : 'PUT' });
  } catch (x) { meldung(x.message); return; }
  await ladeAktivitaet();
});

$('kommentare-knopf').addEventListener('click', () => setzeAngabenOffen(true));
$('kommentar-zu').addEventListener('click', () => $('kommentar-dialog').close());

// Den eigenen Beitrag wieder aus einem geteilten Album nehmen (#290).
// Beim Besitzer landet er im Papierkorb, solange er in keinem anderen
// seiner Alben liegt.
async function entferneBeitrag(a) {
  if (!confirm(t('Deinen Beitrag „{name}“ aus dem Album entfernen? Liegt er in keinem anderen Album, kommt er in den Papierkorb des Besitzers.', { name: a.name || '' }))) return;
  try {
    await api(`${liste.fremd}/${encodeURIComponent(a.id)}`, { methode: 'DELETE' });
  } catch (x) { $('angaben').textContent = x.message; return; }
  liste.aufnahmen = liste.aufnahmen.filter((x) => x.id !== a.id);
  schliesse();
  neuZeichnen();
}

// Eine Datei ins geteilte Album – als XHR, damit der Fortschritt sichtbar
// ist. Gibt den Status zurück (0 ohne Verbindung).
function schickeBeitrag(id, datei, fortschritt) {
  return new Promise((fertig) => {
    const x = new XMLHttpRequest();
    const q = new URLSearchParams({ name: datei.name, geaendert: String(datei.lastModified || Date.now()) });
    x.open('POST', `/api/v1/geteilt/${encodeURIComponent(id)}/beitrag?${q}`);
    x.setRequestHeader('X-PV-Web', '1');
    x.upload.addEventListener('progress', (e) => { if (e.lengthComputable) fortschritt(e.loaded / e.total); });
    x.onload = () => fertig(x.status);
    x.onerror = () => fertig(0);
    x.send(datei);
  });
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
  const d = await api(`/api/v1/reisen?sprache=${SPRACHE}`);
  if (unveraendert(d)) return;
  ziel.replaceChildren();
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
  // Die aufgezeichnete Spur: Was das Gerät gemessen hat, ist der Weg; die
  // Fotos ergeben nur eine Vermutung über ihn.
  const spuren = (d.spuren || []).filter((s) => s.punkte.length > 1);
  let route = null;
  if (d.route.length > 1 || spuren.length) {
    route = el('div', 'routenkarte');
    kopf.append(route);
  } else if (d.aufnahmen.length) {
    kopf.append(el('p', 'nebenzeile', t('Zu wenige verortete Aufnahmen für eine Strecke.')));
  }
  const stelle = { zeige: () => {} };
  for (const s of spuren) kopf.append(spurabschnitt(s, (p) => stelle.zeige(p), a, d.aufnahmen));
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, a.name);
  if (route) {
    ladeLeaflet()
      .then(() => { stelle.zeige = zeichneRoute(route, d.route, spuren); })
      .catch((x) => route.replaceChildren(el('p', 'fehler', x.message)));
  }
}

// Kennzahlen und Höhenprofil einer Spur, wie am Rechner. Fährt man über
// das Profil, zeigt [zeige] die Stelle auf der Karte (null = weg).
function spurabschnitt(s, zeige, aktivitaet, aufnahmen) {
  const box = el('section', 'spur');
  const kopf = el('div', 'spurkopf');
  kopf.append(el('h3', null, t('Aufgezeichnete Spur')));
  const flug = el('button', 'knopf-flach', `⛰ ${t('Gelände ansehen')}`);
  flug.type = 'button';
  flug.addEventListener('click', () => {
    flug.disabled = true;
    ladeSkript('gelaende.js')
      .then(() => oeffneLandschaft(s, aktivitaet, aufnahmen))
      .catch((x) => meldung(x.message))
      .finally(() => { flug.disabled = false; });
  });
  kopf.append(flug);
  box.append(kopf);
  const km = kilometer.format(s.laengeKm);
  box.append(el('p', 'nebenzeile', [
    s.aufstieg == null
      ? t('{km} km · keine Höhenangaben', { km })
      : t('{km} km · ▲ {auf} m · ▼ {ab} m', { km, auf: zahl.format(Math.round(s.aufstieg)), ab: zahl.format(Math.round(s.abstieg || 0)) }),
    t('{anzahl} Punkte', { anzahl: String(s.punkte.length) }),
  ].join(' · ')));
  const profil = profilpunkte(s.punkte);
  if (profil.length > 1) {
    box.append(el('p', 'leise klein', t('Höhenprofil')));
    box.append(hoehenprofil(profil, (i) => zeige(i == null ? null : s.punkte[profil[i].index])));
  } else {
    box.append(el('p', 'leise klein', t('Diese Datei führt keine Höhen – ohne sie gibt es kein Profil.')));
  }
  return box;
}

// Entfernung zweier Punkte in Kilometern (Haversine, wie im Kern).
function abstandKm(a, b) {
  const r = Math.PI / 180;
  const db = (b[0] - a[0]) * r, dl = (b[1] - a[1]) * r;
  const h = Math.sin(db / 2) ** 2 + Math.cos(a[0] * r) * Math.cos(b[0] * r) * Math.sin(dl / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.min(1, Math.sqrt(h)));
}

// Die Punkte des Profils: Strecke bis hierher und Höhe – Punkte ohne Höhe
// fallen heraus, nachdem ihre Strecke gezählt wurde. Die Waagerechte ist
// die Strecke, nicht die Zeit: Über der Zeit würde jede Rast eine Ebene.
function profilpunkte(punkte) {
  const aus = [];
  let km = 0;
  punkte.forEach((p, i) => {
    if (i > 0) km += abstandKm(punkte[i - 1], p);
    if (p[2] != null) aus.push({ km, hoehe: p[2], index: i });
  });
  return aus;
}

const SVG = 'http://www.w3.org/2000/svg';
function svg(tag, werte) {
  const e = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(werte || {})) e.setAttribute(k, v);
  return e;
}

// Das Höhenprofil als SVG, mit einer Marke unter dem Zeiger.
function hoehenprofil(punkte, beiStelle) {
  const B = 600, H = 140, oben = 8, unten = 18;
  const gesamt = punkte[punkte.length - 1].km || 1;
  const hoehen = punkte.map((p) => p.hoehe);
  const tief = Math.min(...hoehen), hoch = Math.max(...hoehen);
  const spanne = Math.max(hoch - tief, 10);
  const x = (km) => (km / gesamt) * B;
  const y = (h) => oben + (1 - (h - tief) / spanne) * (H - oben - unten);
  const box = el('div', 'hoehenprofil');
  box.setAttribute('role', 'img');
  box.setAttribute('aria-label', t('Höhenprofil über {km} km, von {tief} bis {hoch} Meter, {auf} Meter Aufstieg.', {
    km: kilometer.format(gesamt), tief: zahl.format(Math.round(tief)), hoch: zahl.format(Math.round(hoch)),
    auf: zahl.format(Math.round(punkte.reduce((s, p, i) => s + (i && p.hoehe > punkte[i - 1].hoehe ? p.hoehe - punkte[i - 1].hoehe : 0), 0))),
  }));
  const bild = svg('svg', { viewBox: `0 0 ${B} ${H}`, preserveAspectRatio: 'none' });
  const linie = punkte.map((p) => `${x(p.km).toFixed(1)},${y(p.hoehe).toFixed(1)}`).join(' ');
  bild.append(
    svg('polygon', { class: 'flaeche', points: `0,${H - unten} ${linie} ${B},${H - unten}` }),
    svg('polyline', { class: 'linie', points: linie }),
  );
  const strich = svg('line', { class: 'strich', y1: oben, y2: H - unten, visibility: 'hidden' });
  bild.append(strich);
  const achse = el('div', 'achse');
  achse.append(el('span', null, `${zahl.format(Math.round(tief))} m`), el('span', null, t('{km}\u00a0km', { km: kilometer.format(gesamt) })), el('span', null, `${zahl.format(Math.round(hoch))} m`));
  const marke = el('div', 'marke');
  marke.hidden = true;
  box.append(bild, marke, achse);
  const zeigeBei = (clientX) => {
    const r = bild.getBoundingClientRect();
    const gesucht = Math.min(1, Math.max(0, (clientX - r.left) / r.width)) * gesamt;
    let bester = 0;
    for (let i = 1; i < punkte.length; i++) if (Math.abs(punkte[i].km - gesucht) < Math.abs(punkte[bester].km - gesucht)) bester = i;
    const p = punkte[bester];
    strich.setAttribute('x1', x(p.km));
    strich.setAttribute('x2', x(p.km));
    strich.setAttribute('visibility', 'visible');
    marke.textContent = t('{km} km · {hoehe} m', { km: kilometer.format(p.km), hoehe: zahl.format(Math.round(p.hoehe)) });
    marke.hidden = false;
    beiStelle(bester);
  };
  const weg = () => { strich.setAttribute('visibility', 'hidden'); marke.hidden = true; beiStelle(null); };
  bild.addEventListener('pointermove', (e) => zeigeBei(e.clientX));
  bild.addEventListener('pointerdown', (e) => zeigeBei(e.clientX));
  bild.addEventListener('pointerleave', weg);
  bild.addEventListener('pointerup', (e) => { if (e.pointerType !== 'mouse') weg(); });
  return box;
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

// Die Kacheln von OpenStreetMap. Der Server schickt jeder Seite
// `Referrer-Policy: no-referrer` mit; ohne Referer sperren die
// OSM-Server Browser aber („Access blocked“, osm.wiki/Blocked). Für die
// Kacheln geht deshalb nur der Ursprung mit (https://<server>/), kein
// Pfad – welche Reise oder Person gerade offen ist, erfährt OSM nicht.
function osmKacheln() {
  return L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    referrerPolicy: 'strict-origin-when-cross-origin',
    attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  });
}

// Die Route: Linie durch die verorteten Aufnahmen in ihrer Zeitfolge, ein
// Punkt je Aufnahme – ein Tipp darauf öffnet sie. Darunter die
// aufgezeichneten Spuren in der zweiten Farbe. Gibt zurück, wie eine Stelle
// der Spur markiert wird (aus dem Höhenprofil; null nimmt sie weg).
function zeichneRoute(box, punkte, spuren = []) {
  const karte = L.map(box, { scrollWheelZoom: false });
  osmKacheln().addTo(karte);
  const stil = getComputedStyle(document.documentElement);
  const farbe = stil.getPropertyValue('--akzent').trim() || '#0d8a7a';
  const spurfarbe = stil.getPropertyValue('--spur').trim() || '#c2410c';
  const grenzen = L.latLngBounds([]);
  for (const s of spuren) {
    const l = L.polyline(s.punkte.map((p) => [p[0], p[1]]), { color: spurfarbe, weight: 4, opacity: 0.9 }).addTo(karte);
    grenzen.extend(l.getBounds());
  }
  if (punkte.length > 1) {
    const linie = L.polyline(punkte.map((p) => [p.breite, p.laenge]), { color: farbe, weight: spuren.length ? 3 : 4, opacity: 0.85 }).addTo(karte);
    grenzen.extend(linie.getBounds());
  }
  punkte.forEach((p, i) => {
    const ende = i === 0 || i === punkte.length - 1;
    L.circleMarker([p.breite, p.laenge], { radius: ende ? 7 : 4, color: '#fff', weight: 2, fillColor: farbe, fillOpacity: 1 })
      .addTo(karte)
      .on('click', () => { const n = liste.aufnahmen.findIndex((x) => x.id === p.id); if (n >= 0) oeffne(n); });
  });
  if (grenzen.isValid()) karte.fitBounds(grenzen, { padding: [24, 24], maxZoom: 16 });
  const fehlerfarbe = stil.getPropertyValue('--fehler').trim() || '#b3261e';
  let stelle = null;
  return (p) => {
    if (!p) { if (stelle) { stelle.remove(); stelle = null; } return; }
    if (!stelle) stelle = L.circleMarker([p[0], p[1]], { radius: 7, color: '#fff', weight: 2, fillColor: fehlerfarbe, fillOpacity: 1, interactive: false }).addTo(karte);
    else stelle.setLatLng([p[0], p[1]]);
  };
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
  if (unveraendert(s)) return;
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
    // Nicht „t“: Das verdeckte die Übersetzung, und schon „Behalten“
    // brach mit „t is not a function“ ab.
    const zelle = el('div', 'dupl');
    if (a.id === g.behalten) zelle.classList.add('beste');
    const img = el('img');
    img.loading = 'lazy';
    img.alt = '';
    img.src = miniaturUrl(a.id, a.stand);
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
    zelle.append(img, name, el('div', 'angaben', angaben), knopf);
    reihe.append(zelle);
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

// --- Aufnahmedaten (#203) --------------------------------------------------
// Der Server vergleicht das Datum jeder Aufnahme mit dem, was ihr
// Dateiname nennt, und liest die Datei, wo das nötig ist (dieselbe Prüfung
// wie am Rechner). Hier wird nur gezeigt und übernommen, über den Befehl.

let datumsvorschlaege = null;
const gewaehlteDaten = new Set();
const QUELLEN = { dateiname: 'laut Dateiname', dateiUndName: 'laut Datei und Dateiname' };
$('daten-pruefen').addEventListener('click', () => pruefeAufnahmedaten().catch((x) => { $('daten-hinweis').textContent = x.message; }));

async function zeigeAufnahmedaten() {
  markiereNav('aufnahmedaten');
  zeigeBereich(['aufnahmedaten']);
  if (datumsvorschlaege) zeichneAufnahmedaten(); else await pruefeAufnahmedaten();
  if (datierungsfunde) zeichneDatierung(); else await holeDatierung();
}

// --- Alte Fotos zeitlich einordnen (#279) -----------------------------------
//
// Dieselbe Liste wie am Rechner (Werkzeuge) und auf dem Telefon: Fotos ohne
// echtes Datum, die alt aussehen, mit dem Jahrzehnt, das die Bildsuche
// schätzt. Gerechnet auf dem Server, der das Textmodell hat; übernommen
// wird die Jahresmitte über denselben Befehl wie am Rechner.

let datierungsfunde = null;
const datierungUebernommen = new Set();

async function holeDatierung() {
  $('datierung').hidden = false;
  $('datierung-hinweis').textContent = t('Prüfe …');
  $('datierung-liste').replaceChildren();
  $('datierung-alle').hidden = true;
  try {
    const d = await api('/api/v1/datierung');
    datierungsfunde = d.funde;
  } catch (x) {
    $('datierung-hinweis').textContent = x.status === 404
      ? t('Für die Schätzung braucht der Server das Modell der Bildsuche (CLIP).')
      : x.message;
    return;
  }
  datierungUebernommen.clear();
  for (const f of datierungsfunde) if (f.uebernommen) datierungUebernommen.add(f.aufnahme.id);
  zeichneDatierung();
}

const offeneSchaetzungen = () => datierungsfunde.filter((f) => f.belastbar && !datierungUebernommen.has(f.aufnahme.id));

function zeichneDatierung() {
  $('datierung').hidden = false;
  $('datierung-hinweis').textContent = datierungsfunde.length === 0
    ? t('Unter den Fotos ohne echtes Aufnahmedatum sieht keines alt aus.')
    : t('Diese Fotos tragen kein echtes Aufnahmedatum – geraten beim Import oder vom Scanner gesetzt – und sehen alt aus. Die Bildsuche schätzt daraus das Jahrzehnt. Ist die Spanne zu breit, weiß das Modell es nicht, und es gibt nichts zu übernehmen. Übernommen wird die Mitte des Jahres; das Datum bleibt als geschätzt markiert.');
  const offen = offeneSchaetzungen();
  const alle = $('datierung-alle');
  alle.hidden = offen.length === 0;
  alle.textContent = offen.length === 1 ? t('1 Schätzung übernehmen') : t('{n} Schätzungen übernehmen', { n: offen.length });
  $('datierung-liste').replaceChildren(...datierungsfunde.map((f, i) => datierungszeile(f, i)));
}

function datierungszeile(f, i) {
  const a = f.aufnahme;
  const zeile = el('div', 'datumszeile');
  const img = el('img');
  img.loading = 'lazy';
  img.alt = '';
  img.src = miniaturUrl(a.id, a.stand);
  img.addEventListener('click', () => {
    liste = { aufnahmen: datierungsfunde.map((x) => x.aufnahme), nachTagen: false, mehr: null };
    oeffne(i);
  });
  const inhalt = el('div', 'inhalt');
  inhalt.append(
    el('div', 'name', t('um {jahr}', { jahr: f.jahr })),
    el('div', 'neben', f.belastbar
      ? t('{von} bis {bis}', { von: f.von, bis: f.bis })
      : t('zu unsicher ({von} bis {bis})', { von: f.von, bis: f.bis })),
  );
  zeile.append(img, inhalt);
  if (datierungUebernommen.has(a.id)) {
    zeile.append(el('span', 'leise datierung-ende', t('Übernommen')));
  } else if (f.belastbar) {
    const knopf = el('button', 'datierung-ende', t('Übernehmen'));
    knopf.type = 'button';
    knopf.addEventListener('click', () => uebernimmSchaetzungen([f]).catch((x) => { knopf.textContent = x.message; }));
    zeile.append(knopf);
  }
  return zeile;
}

async function uebernimmSchaetzungen(welche) {
  for (const f of welche) {
    await befehl('jahrSchaetzen', { id: f.aufnahme.id, jahr: f.jahr });
    datierungUebernommen.add(f.aufnahme.id);
  }
  zeitleiste.leeren(); // die Fotos stehen jetzt an anderer Stelle
  zeichneDatierung();
}

$('datierung-alle').addEventListener('click', () => {
  const offen = offeneSchaetzungen();
  if (!offen.length) return;
  uebernimmSchaetzungen(offen).catch((x) => { $('datierung-hinweis').textContent = x.message; });
});

async function pruefeAufnahmedaten() {
  $('daten-hinweis').textContent = t('Prüfe …');
  $('daten-liste').replaceChildren();
  $('daten-uebernehmen').hidden = true;
  const d = await api('/api/v1/aufnahmedaten');
  datumsvorschlaege = d.vorschlaege;
  gewaehlteDaten.clear();
  for (const v of datumsvorschlaege) gewaehlteDaten.add(v.aufnahme.id);
  zeichneAufnahmedaten();
}

// Ein Datum ohne Uhrzeit (der Name nennt nur den Tag) ohne Uhrzeit zeigen.
const vorschlagsdatum = (v) => (v.geschaetzt ? zeitraum : datumZeit).format(new Date(v.neu));

function zeichneAufnahmedaten() {
  const ziel = $('daten-liste');
  ziel.replaceChildren();
  const n = datumsvorschlaege.length;
  $('daten-hinweis').textContent = n === 0
    ? t('Alle Aufnahmedaten passen zu ihren Dateinamen.')
    : n === 1
      ? t('Bei einer Aufnahme nennt der Dateiname ein anderes Datum. Übernommen wird nur das Datum in der Bibliothek; die Datei bleibt unverändert.')
      : t('Bei {n} Aufnahmen nennt der Dateiname ein anderes Datum. Übernommen wird nur das Datum in der Bibliothek; die Dateien bleiben unverändert.', { n });
  aktualisiereDatenknopf();
  datumsvorschlaege.forEach((v, i) => ziel.append(datumszeile(v, i)));
}

function aktualisiereDatenknopf() {
  const knopf = $('daten-uebernehmen');
  knopf.hidden = gewaehlteDaten.size === 0;
  knopf.textContent = t('{n} übernehmen', { n: gewaehlteDaten.size });
}

function datumszeile(v, i) {
  const a = v.aufnahme;
  const zeile = el('label', 'datumszeile');
  const wahl = el('input');
  wahl.type = 'checkbox';
  wahl.checked = gewaehlteDaten.has(a.id);
  wahl.addEventListener('change', () => {
    if (wahl.checked) gewaehlteDaten.add(a.id); else gewaehlteDaten.delete(a.id);
    aktualisiereDatenknopf();
  });
  const img = el('img');
  img.loading = 'lazy';
  img.alt = '';
  img.src = miniaturUrl(a.id, a.stand);
  img.addEventListener('click', (e) => {
    e.preventDefault(); // nicht zugleich das Häkchen umschalten
    liste = { aufnahmen: datumsvorschlaege.map((x) => x.aufnahme), nachTagen: false, mehr: null };
    oeffne(i);
  });
  const inhalt = el('div', 'inhalt');
  const name = el('div', 'name', a.name);
  name.title = a.name;
  const bisher = datumZeit.format(new Date(v.bisher)) + (v.bisherGeschaetzt ? ` (${t('geschätzt')})` : '');
  inhalt.append(
    name,
    el('div', 'wechsel', `${bisher} → ${vorschlagsdatum(v)}`),
    el('div', 'neben', t(QUELLEN[v.quelle]) + (v.geschaetzt ? ` · ${t('nur der Tag, bleibt geschätzt')}` : '')),
  );
  zeile.append(wahl, img, inhalt);
  return zeile;
}

$('daten-uebernehmen').addEventListener('click', async () => {
  const daten = datumsvorschlaege
    .filter((v) => gewaehlteDaten.has(v.aufnahme.id))
    .map((v) => ({ id: v.aufnahme.id, zeitpunkt: v.neu, geschaetzt: v.geschaetzt }));
  if (!daten.length || !confirm(daten.length === 1 ? t('Das Datum dieser Aufnahme übernehmen?') : t('Das Datum von {n} Aufnahmen übernehmen?', { n: daten.length }))) return;
  try {
    // In Stücken, damit kein Befehl tausende Zeilen auf einmal trägt.
    for (let i = 0; i < daten.length; i += 200) await befehl('aufnahmedatenSetzen', { daten: daten.slice(i, i + 200) });
    await pruefeAufnahmedaten();
  } catch (x) { $('daten-hinweis').textContent = x.message; }
});

// Im Infobereich: was der Dateiname nennt, mit „Übernehmen“.
function datumsvorschlagHinweis(a, v) {
  const box = el('div', 'datumsvorschlag');
  const text = v.quelle === 'dateiUndName' ? 'Datei und Dateiname nennen {d}' : 'Der Dateiname nennt {d}';
  box.append(el('span', null, t(text, { d: vorschlagsdatum(v) })));
  const knopf = el('button', null, t('Übernehmen'));
  knopf.type = 'button';
  knopf.addEventListener('click', async () => {
    try {
      await befehl('aufnahmedatenSetzen', { daten: [{ id: a.id, zeitpunkt: v.neu, geschaetzt: v.geschaetzt }] });
      a.aufgenommen = v.neu;
      datumsvorschlaege = null; // die Liste unter „Aufnahmedaten“ neu holen
      await zeigeAngaben();
    } catch (x) { knopf.textContent = x.message; }
  });
  box.append(knopf);
  return box;
}

async function zeigeSerie(id) {
  zeigeBereich(['raster']);
  const d = await api(`/api/v1/serien/${encodeURIComponent(id)}`);
  if (!istVarianten(id)) {
    zeigeListe({ aufnahmen: d.aufnahmen }, t('Serie · {n} Aufnahmen', { n: d.aufnahmen.length }));
    return;
  }
  // Varianten wie am Rechner (Varianten vergleichen): die Hauptversion
  // wechseln oder alle wieder einzeln zeigen (#219).
  const kopf = el('div', 'zeile');
  const haupt = el('button', null, t('Hauptversion wählen'));
  haupt.type = 'button';
  haupt.addEventListener('click', () => waehle(t('Hauptversion wählen'), d.aufnahmen.map((a) => ({
    text: a.name,
    hinweis: a.serie && a.serie.titel ? t('Hauptversion') : '',
    an: !(a.serie && a.serie.titel),
    aktion: async () => { await befehl('variantenHauptbildSetzen', { stackId: id, assetId: a.id }); zeitleiste.leeren(); await zeigeSerie(id); },
  }))));
  const einzeln = el('button', null, t('Varianten einzeln zeigen'));
  einzeln.type = 'button';
  einzeln.addEventListener('click', async () => {
    if (!confirm(t('Die {n} Fassungen wieder einzeln zeigen? Keine Datei wird gelöscht.', { n: d.aufnahmen.length }))) return;
    try { await befehl('variantenAufloesen', { stackId: id }); zeitleiste.leeren(); history.back(); } catch (x) { meldung(x.message); }
  });
  kopf.append(haupt, einzeln);
  zeigeListe({ aufnahmen: d.aufnahmen, kopf }, t('Varianten · {n} Fassungen', { n: d.aufnahmen.length }));
}

// --- Varianten (#219) ---------------------------------------------------------
//
// Mehrere Fassungen derselben Aufnahme unter einer Hauptversion, wie am
// Rechner: ein gewöhnlicher Stapel, dessen Kennung mit `variante:` beginnt
// (kern/db/abfragen/serien.dart). Die Befehle sind dieselben.

const istVarianten = (stackId) => typeof stackId === 'string' && stackId.startsWith('variante:');

function variantenBilden(aufnahmen) {
  if (aufnahmen.length < 2) return;
  // Ein Foto gehört höchstens zu einem Stapel – Serie oder Varianten.
  if (aufnahmen.some((a) => a.serie)) { meldung(t('Mindestens eine Aufnahme gehört bereits zu einem Stapel. Löse diesen zuerst auf.')); return; }
  waehle(t('Hauptversion wählen'), aufnahmen.map((a) => ({
    text: a.name,
    hinweis: t('Bleibt in Übersichten sichtbar; alle Fassungen bleiben erhalten.'),
    aktion: async () => {
      const variantenId = neueKennung();
      await befehl('variantenBilden', { variantenId, ids: aufnahmen.map((x) => x.id), hauptId: a.id });
      // Wie beim Papierkorb: Die übrigen Fassungen verschwinden aus der
      // Übersicht, die Hauptversion trägt den Stapel.
      const weg = new Set(aufnahmen.filter((x) => x.id !== a.id).map((x) => x.id));
      a.serie = { id: `variante:${variantenId}`, titel: true, groesse: aufnahmen.length };
      liste.aufnahmen = liste.aufnahmen.filter((x) => !weg.has(x.id));
      zeitleiste.geladen = zeitleiste.geladen.filter((x) => !weg.has(x.id));
      meldung(t('{n} Fassungen als Varianten gestapelt', { n: aufnahmen.length }));
      auswahlAufheben();
      neuZeichnen();
    },
  })));
}

// --- Stammbaum -------------------------------------------------------------
// Steht in stammbaum.js und wird erst geladen, wenn er gebraucht wird – wie
// der Lebensbaum, dessen Bezeichnungen er mitbenutzt.

// --- Einstellungen der Bibliothek ------------------------------------------

$('einst-sprache').addEventListener('change', () => spracheWaehlen($('einst-sprache').value));

// Regeln für neue Fotos. Greifen tun sie beim Import, am Server wie am Rechner;
// hier lassen sie sich pflegen und auf das anwenden, was schon da ist.
let autoregelStand = null;
let autoregelId = null;
const AUSLOESER = { location: 'Ort (Umkreis)', dateRange: 'Datumsbereich', dateiname: 'Dateiname enthält', dateiendung: 'Dateiendung', aiTag: 'KI-Schlagwort' };

function autoregelText(r, d) {
  const teile = [];
  if (r.ausloeser === 'location') teile.push(t('Umkreis {km} km', { km: r.umkreisKm }));
  else if (r.ausloeser === 'dateRange') teile.push(`${(r.von || '').slice(0, 10)} – ${(r.bis || '').slice(0, 10)}`);
  else teile.push(`${t(AUSLOESER[r.ausloeser] || r.ausloeser)}: ${r.begriff || ''}`);
  const album = d.alben.find((a) => a.id === r.album);
  if (album) teile.push(`→ ${album.name}`);
  const namen = r.schlagwoerter.map((id) => d.schlagwoerter.find((s) => s.id === id)?.name).filter(Boolean);
  if (namen.length) teile.push(`🏷 ${namen.join(', ')}`);
  if (r.favorit) teile.push(`♥ ${t('Favorit')}`);
  return teile.join(' · ');
}

async function zeigeAutoregeln() {
  const d = await api('/api/v1/regeln');
  autoregelStand = d;
  const ul = $('autoregeln');
  ul.replaceChildren();
  if (!d.regeln.length) ul.append(el('li', 'leise', t('Noch keine Regeln.')));
  for (const r of d.regeln) {
    const li = el('li');
    const wer = el('div', 'wer');
    wer.append(el('div', null, r.name), el('div', 'text', autoregelText(r, d)));
    const anwenden = el('button', null, t('Auf vorhandene Fotos anwenden'));
    anwenden.type = 'button';
    anwenden.addEventListener('click', () => autoregelAnwenden(r).catch((x) => meldung(x.message)));
    const aendern = el('button', null, t('Bearbeiten'));
    aendern.type = 'button';
    aendern.addEventListener('click', () => autoregelDialog(r));
    const weg = el('button', null, t('Löschen'));
    weg.type = 'button';
    weg.addEventListener('click', async () => {
      if (!confirm(t('Die Regel „{name}“ löschen? Was sie schon getan hat, bleibt.', { name: r.name }))) return;
      try { await befehl('regelLoeschen', { regelId: r.id }); await zeigeAutoregeln(); } catch (x) { meldung(x.message); }
    });
    li.append(wer, anwenden, aendern, weg);
    ul.append(li);
  }
}

async function autoregelAnwenden(r) {
  const pfad = `/api/v1/regeln/${encodeURIComponent(r.id)}/anwenden`;
  const probe = await api(`${pfad}?probe=1`, { methode: 'POST', json: {} });
  if (!probe.treffer) { meldung(t('Kein vorhandenes Foto passt.')); return; }
  if (!confirm(t('{n} vorhandene Fotos passen zu „{name}“. Regel jetzt auf sie anwenden? Das lässt sich nicht als Ganzes zurücknehmen.', { n: probe.treffer, name: r.name }))) return;
  const d = await api(pfad, { methode: 'POST', json: {} });
  meldung(t('Regel auf {n} Fotos angewendet.', { n: d.treffer }));
}

function autoregelAusloeser() {
  const f = $('form-autoregel');
  const a = f.ausloeser.value;
  for (const x of f.querySelectorAll('.nur-ausloeser')) x.hidden = !x.dataset.ausloeser.split(' ').includes(a);
  $('autoregel-text-name').textContent = a === 'dateiendung' ? t('Endungen, mit Komma getrennt') : t('Text im Dateinamen');
}

function autoregelDialog(r) {
  const d = autoregelStand;
  const f = $('form-autoregel');
  f.reset();
  autoregelId = r ? r.id : null;
  $('autoregel-titel').textContent = r ? t('Regel bearbeiten') : t('Neue Regel');
  $('autoregel-meldung').textContent = '';
  $('autoregel-orte').replaceChildren();
  const option = (wert, text) => { const o = el('option', null, text); o.value = wert; return o; };
  f.album.replaceChildren(option('', t('Kein Album')), ...d.alben.map((a) => option(a.id, a.name)));
  f.schlagwoerter.replaceChildren(...d.schlagwoerter.map((s) => option(s.id, s.name)));
  f.begriff.replaceChildren(...d.kiBegriffe.map((b) => option(b, b)));
  if (r) {
    f.name.value = r.name;
    f.ausloeser.value = r.ausloeser;
    f.breite.value = r.breite ?? '';
    f.laenge.value = r.laenge ?? '';
    if (r.umkreisKm) f.umkreis.value = r.umkreisKm;
    f.von.value = (r.von || '').slice(0, 10);
    f.bis.value = (r.bis || '').slice(0, 10);
    f.text.value = ['dateiname', 'dateiendung'].includes(r.ausloeser) ? r.begriff || '' : '';
    if (r.ausloeser === 'aiTag') f.begriff.value = r.begriff || '';
    f.album.value = r.album || '';
    for (const o of f.schlagwoerter.options) o.selected = r.schlagwoerter.includes(o.value);
    f.favorit.checked = r.favorit;
  }
  autoregelAusloeser();
  $('autoregel-dialog').showModal();
  f.name.focus();
}

// Dieselben Prüfungen wie am Rechner: Eine Regel mit unmöglichen Werten träfe
// nie zu, ohne dass es jemand merkt.
function autoregelWerte(f) {
  const a = f.ausloeser.value;
  const zahl = (x) => Number(String(x).trim().replace(',', '.'));
  const w = { id: autoregelId || neueKennung(), name: f.name.value.trim(), trigger_type: a, region_center_lat: null, region_center_lon: null, region_radius_km: null, ai_tag_term: null, date_from: null, date_to: null, target_album_id: f.album.value || null, auto_favorite: f.favorit.checked };
  if (!w.name) throw new Error(t('Die Regel braucht einen Namen.'));
  if (a === 'location') {
    const breite = zahl(f.breite.value), laenge = zahl(f.laenge.value), km = zahl(f.umkreis.value);
    if (f.breite.value.trim() === '' || f.laenge.value.trim() === '' || !(breite >= -90 && breite <= 90) || !(laenge >= -180 && laenge <= 180)) throw new Error(t('Breiten- und Längengrad stimmen nicht.'));
    if (!(km > 0)) throw new Error(t('Der Umkreis stimmt nicht.'));
    Object.assign(w, { region_center_lat: breite, region_center_lon: laenge, region_radius_km: km });
  } else if (a === 'dateRange') {
    if (!f.von.value || !f.bis.value) throw new Error(t('Bitte Start- und Enddatum wählen.'));
    if (f.von.value > f.bis.value) throw new Error(t('Das Startdatum muss vor dem Enddatum liegen.'));
    Object.assign(w, { date_from: `${f.von.value}T00:00:00`, date_to: `${f.bis.value}T23:59:59` });
  } else if (a === 'aiTag') {
    if (!f.begriff.value) throw new Error(t('Bitte ein KI-Schlagwort wählen.'));
    w.ai_tag_term = f.begriff.value;
  } else {
    const text = f.text.value.trim();
    const endungen = /^\.?[a-zA-Z0-9]{1,10}$/;
    if (!text || (a === 'dateiendung' && !text.split(',').every((s) => endungen.test(s.trim())))) throw new Error(t('Der Text stimmt nicht.'));
    w.ai_tag_term = text;
  }
  return w;
}

$('autoregel-neu').addEventListener('click', () => autoregelDialog(null));
$('autoregel-abbrechen').addEventListener('click', () => $('autoregel-dialog').close());
$('form-autoregel').ausloeser.addEventListener('change', autoregelAusloeser);
$('form-autoregel').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    const regel = autoregelWerte(f);
    const schlagwortIds = [...f.schlagwoerter.selectedOptions].map((o) => o.value);
    await befehl('regelSpeichern', { regel });
    await befehl('regelSchlagwoerterSetzen', { regelId: regel.id, schlagwortIds });
    $('autoregel-dialog').close();
    await zeigeAutoregeln();
  } catch (x) { $('autoregel-meldung').textContent = x.message; }
});
let autoregelUhr = null;
$('form-autoregel').ortsuche.addEventListener('input', () => {
  clearTimeout(autoregelUhr);
  autoregelUhr = setTimeout(async () => {
    const f = $('form-autoregel');
    const text = f.ortsuche.value.trim();
    const feld = $('autoregel-orte');
    if (text.length < 2) { feld.replaceChildren(); return; }
    try {
      const d = await api(`/api/v1/orte/suche?text=${encodeURIComponent(text)}`);
      if (f.ortsuche.value.trim() !== text) return;
      feld.replaceChildren(...d.treffer.map((o) => {
        const b = el('button');
        b.type = 'button';
        b.append(el('span', 'haupt', o.name), el('span', 'neben', o.herkunft));
        b.addEventListener('click', () => { f.breite.value = o.breite; f.laenge.value = o.laenge; f.ortsuche.value = o.name; feld.replaceChildren(); });
        return b;
      }));
    } catch (x) { $('autoregel-meldung').textContent = x.message; }
  }, 150);
});

async function zeigeEinstellungen() {
  markiereNav('einstellungen');
  zeigeBereich(['einstellungen']);
  zeigeAutoregeln().catch((x) => { $('einst-meldung').textContent = x.message; });
  let gewaehlt = 'auto';
  try { gewaehlt = localStorage.getItem(SPRACHE_MERKER) || 'auto'; } catch (_) { /* privat */ }
  $('einst-sprache').value = gewaehlt;
  const e = await api('/api/v1/einstellungen');
  const ziel = $('einst-liste');
  const melde = (text) => { $('einst-meldung').textContent = text; };
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
  // Dieselbe Skala wie am Rechner (Werkzeuge → Gesichtserkennung): Die
  // Ähnlichkeit von SFace liegt für dieselbe Person meist zwischen 0,5 und
  // 0,8. Bis 3.51 stand hier 0,8 bis 0,99 mit 0,9 als Vorgabe – damit
  // wurde fast nie etwas übernommen.
  let vorschlaegeAb = e.vorschlaegeAb ?? 0.7;
  const vorschlagRegler = regler(0.6, 0.9, 0.05, vorschlaegeAb, (v) => t('ab {p}', { p: `${Math.round(v * 100)} %` }), (v) => { vorschlaegeAb = v; if (vorschlaegeAn) sende('vorschlaegeAutomatischSetzen', { ab: v }); });
  let vorschlaegeAn = e.vorschlaegeAb != null;
  ziel.replaceChildren(
    zeile('Papierkorb automatisch leeren', 'Löscht Aufnahmen im Papierkorb nach Ablauf der Frist endgültig – unwiderruflich.', leeren, (an) => { leeren = an; sende('papierkorbFristSetzen', { an, tage: Number(tage.value) }); }, tageBox),
    zeile('Sichere Vorschläge automatisch übernehmen', 'Wiedererkannte Gesichter ab dieser Sicherheit werden ohne Rückfrage zugeordnet und dabei gekennzeichnet, ebenso ganze Gruppen, in denen jedes Gesicht auf dieselbe Person zeigt; unsichere bleiben Vorschläge.', vorschlaegeAn, (an) => { vorschlaegeAn = an; sende('vorschlaegeAutomatischSetzen', { ab: an ? vorschlaegeAb : null }); }, vorschlagRegler),
    zeile('KI-Auswertung nach dem Import automatisch nachholen', 'Neue Aufnahmen werden gleich ausgewertet: Gesichter, Bildinhalt, Text, Schlagwörter.', e.auswertenNachImport, (an) => sende('auswertenNachImportSetzen', { an })),
    zeile('Suche und Schlagwörter übersetzen', 'Sucht auf Deutsch und Englisch gleichzeitig und führt Schlagwörter in beiden Sprachen.', e.sucheUebersetzen, (an) => sende('sucheUebersetzenSetzen', { an })),
    zeile('Private Metadaten schützen', 'Neu gesperrte Aufnahmen legen auch Ort, Beschreibung und Text verschlüsselt ab.', e.angabenSchuetzen, (an) => sende('angabenSchuetzenSetzen', { an })),
  );
  const schwelle = el('div', 'einst');
  const sInhalt = el('div', 'inhalt');
  sInhalt.append(el('div', 'titel', t('Schwelle der Gesichtserkennung')), el('div', 'text', t('Wie ähnlich ein Gesicht sein muss, um einer Person vorgeschlagen zu werden. Höher heisst vorsichtiger.')), regler(0.2, 0.8, 0.01, e.gesichtsschwelle, (v) => Number(v).toFixed(2), (v) => sende('gesichtsschwelleSetzen', { schwelle: v })));
  schwelle.append(el('span'), sInhalt);
  ziel.append(schwelle);
  // Gilt nur für diesen Browser, wie am Rechner für das Gerät.
  ziel.append(zeile('Videos beim Schweben abspielen', 'Bleibt die Maus einen Augenblick über einem Video oder einem Live Photo stehen, läuft es in der Kachel an – ohne Ton und in Dauerschleife, bis der Zeiger weiterwandert. Es läuft immer nur eines. Gilt für diesen Browser.', schwebeAn, (an) => {
    schwebeAn = an;
    if (!an) schwebeEnde();
    try { localStorage.setItem(SCHWEBE_MERKER, an ? '1' : '0'); } catch (_) { /* privat */ }
    melde(t('Gespeichert.'));
  }));
  melde('');
}

async function zeigePersonen() {
  markiereNav('personen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Personen');
  const d = await api('/api/v1/personen');
  if (unveraendert(d)) return;
  $('karten').replaceChildren();
  if (d.personen.length === 0) $('karten').append(el('p', 'leise', t('Noch keine Personen.')));
  for (const p of d.personen) {
    const bild = p.bild ? `/api/v1/dateien/${p.bild.split('/').map(encodeURIComponent).join('/')}` : null;
    const k = karte(bild, p.name, anzahlText(p.anzahl), `#/personen/${encodeURIComponent(p.id)}`);
    k.classList.add('person');
    $('karten').append(k);
  }
  // Gruppen, an denen gerade jemand arbeitet, bleiben im stillen Lauf stehen.
  if (!stillerLauf) zeigeOhneNamen().catch(() => {});
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

// Ein Gesicht zum Auswählen, mit einem Knopf in der Ecke, der es im
// ganzen Foto zeigt (#189): Der kleine Ausschnitt sagt oft nicht, wer das
// ist – das Foto drumherum schon.
function gesichtszelle(g, beiTipp) {
  const zelle = el('span', 'gesicht-zelle');
  const b = el('button', 'gesicht');
  b.type = 'button';
  b.dataset.id = g.id;
  b.append(gesichtsbild(g));
  if (beiTipp) b.addEventListener('click', () => beiTipp(b));
  zelle.append(b);
  if (g.aufnahme) {
    const foto = el('button', 'im-foto');
    foto.type = 'button';
    foto.title = t('Im Foto zeigen');
    foto.setAttribute('aria-label', t('Im Foto zeigen'));
    foto.append(symbol('imfoto'));
    foto.addEventListener('click', (e) => { e.stopPropagation(); zeigeImFoto(g).catch((x) => meldung(x.message)); });
    zelle.append(foto);
  }
  return zelle;
}

// Das Foto zu einem Gesicht, mit allen Gesichtern darauf; das gewählte
// hervorgehoben, die übrigen abgeblendet.
async function zeigeImFoto(g) {
  const fig = $('imfoto-bild');
  const img = el('img');
  img.alt = '';
  img.src = `/api/v1/aufnahmen/${encodeURIComponent(g.aufnahme)}/vorschau`;
  fig.replaceChildren(img);
  $('imfoto-text').textContent = '';
  $('imfoto-dialog').showModal();
  let d = null;
  try { d = await api(`/api/v1/aufnahmen/${encodeURIComponent(g.aufnahme)}/angaben?sprache=${SPRACHE}`); } catch (_) { /* nur das eine Gesicht */ }
  if (fig.firstChild !== img) return; // inzwischen ein anderes
  const gesichter = d && d.gesichter && d.gesichter.length ? d.gesichter : [g];
  for (const f of gesichter) {
    if (!f.kasten) continue;
    const [x, y, w, h] = f.kasten;
    const r = el('span', `imfoto-rahmen${f.person ? ' benannt' : ''}${f.id === g.id ? ' gewaehlt' : ''}`);
    r.style.left = `${x * 100}%`;
    r.style.top = `${y * 100}%`;
    r.style.width = `${w * 100}%`;
    r.style.height = `${h * 100}%`;
    if (f.person && f.id !== g.id) r.append(el('span', 'name', f.person.name));
    fig.append(r);
  }
  if (d) {
    const ort = d.ort ? [d.ort.stadt, land(d.ort.land)].filter(Boolean).join(', ') : '';
    $('imfoto-text').textContent = [datumZeit.format(new Date(d.aufgenommen)), ort, d.name].filter(Boolean).join(' · ');
  }
}
$('imfoto-zu').addEventListener('click', () => $('imfoto-dialog').close());

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
  // Auch wenn nichts mehr offen ist, solange es Ignorierte gibt: Über das
  // Menü holt man sie zurück.
  if (!d.gruppen.length && !d.ignoriert) { box.hidden = true; return; }
  const kopf = el('div', 'bib-kopf');
  const rechts = el('span', 'rechts');
  const menue = el('button', 'kopf-menue', '⋯');
  menue.type = 'button';
  menue.title = t('Mehr');
  menue.setAttribute('aria-label', t('Mehr'));
  menue.addEventListener('click', () => ohneNamenMenue(d));
  rechts.append(el('span', 'leise', t('{n} Gesichter', { n: d.gesamt })), menue);
  kopf.append(el('h3', null, t('Ohne Namen')), rechts);
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

// Eine kleine Auswahl wie die Menüs am Rechner: je Eintrag ein Knopf mit
// einer Zeile darunter, die sagt, was er tut.
function waehle(titel, eintraege) {
  $('wahl-titel').textContent = titel;
  const liste = $('wahl-liste');
  liste.replaceChildren();
  for (const e of eintraege) {
    const b = el('button', `wahl${e.gefahr ? ' gefahr' : ''}`);
    b.type = 'button';
    b.disabled = e.an === false;
    b.append(el('span', null, e.text));
    if (e.hinweis) b.append(el('span', 'leise klein', e.hinweis));
    b.addEventListener('click', () => {
      $('wahl-dialog').close();
      Promise.resolve(e.aktion()).catch((x) => meldung(x.message));
    });
    liste.append(b);
  }
  $('wahl-dialog').showModal();
}
$('wahl-zu').addEventListener('click', () => $('wahl-dialog').close());

// Alle unbenannten auf einmal – wie das Menü über „Ohne Namen“ am
// Rechner (#192). Die Kennungen sucht der Server heraus.
async function alleUnbenannten(aktion) {
  return (await api('/api/v1/gesichter/unbenannte', { methode: 'POST', json: { aktion } })).anzahl;
}

function ohneNamenMenue(d) {
  waehle(t('Ohne Namen'), [
    {
      text: t('Alle unbenannten Gesichter ignorieren'),
      hinweis: d.gesamt === 1 ? t('Ein Gesicht wandert nach „Ignoriert“') : d.gesamt ? t('{n} Gesichter wandern nach „Ignoriert“', { n: d.gesamt }) : t('Nichts mehr offen'),
      an: d.gesamt > 0,
      aktion: async () => {
        const n = await alleUnbenannten('ignorieren');
        meldung(n === 1 ? t('Ein Gesicht ignoriert. Unter „Ignoriert“ holst du einzelne zurück.') : t('{n} Gesichter ignoriert. Unter „Ignoriert“ holst du einzelne zurück.', { n }));
        zeigePersonen();
      },
    },
    {
      text: t('Alle unbenannten Erkennungen löschen'),
      hinweis: t('Gibt Platz frei, kommt beim nächsten Scan aber wieder'),
      gefahr: true,
      aktion: async () => {
        if (!confirm(t('Alle unbenannten Erkennungen werden samt ihrer Ausschnitte gelöscht – auch die bereits ignorierten. Benannte Personen bleiben unberührt.\n\nDas ist nicht dauerhaft: Der nächste Gesichts-Scan findet dieselben Stellen wieder. Wenn du sie dauerhaft loswerden willst, nimm stattdessen „Alle unbenannten Gesichter ignorieren“ – das überlebt auch einen erneuten Scan.'))) return;
        const n = await alleUnbenannten('loeschen');
        meldung(n === 1 ? t('Eine Erkennung gelöscht.') : t('{n} Erkennungen gelöscht.', { n }));
        zeigePersonen();
      },
    },
    {
      text: t('Ignoriert'),
      hinweis: t('{n} Gesichter', { n: d.ignoriert || 0 }),
      an: (d.ignoriert || 0) > 0,
      aktion: () => { location.hash = '#/ignoriert'; },
    },
  ]);
}

// Die beiseitegelegten Gesichter, wie der Reiter „Ignoriert“ am Rechner:
// antippen wählt aus, „Zurückholen“ stellt sie wieder zu „Ohne Namen“.
async function zeigeIgnoriert() {
  markiereNav('personen');
  zeigeBereich(['karten']);
  $('karten-titel').textContent = t('Ignoriert');
  const box = $('karten');
  box.replaceChildren(el('p', 'neben', t('Lade …')));
  const d = await api('/api/v1/gesichter/ignoriert');
  const gewaehlt = new Set();
  const kopf = el('div', 'ignoriert-kopf');
  const text = el('span', 'leise');
  const alle = el('button', null, t('Alle wählen'));
  alle.type = 'button';
  const zurueck = el('button', 'primaer');
  zurueck.type = 'button';
  const raster = el('div', 'ignoriert-raster');
  const neu = () => {
    text.textContent = d.gesichter.length < d.gesamt
      ? t('Die ersten {n} von {gesamt} ignorierten Gesichtern', { n: d.gesichter.length, gesamt: d.gesamt })
      : t('{n} Gesichter', { n: d.gesamt });
    zurueck.textContent = gewaehlt.size ? t('{n} zurückholen', { n: gewaehlt.size }) : t('Zurückholen');
    zurueck.disabled = !gewaehlt.size;
    alle.textContent = gewaehlt.size === d.gesichter.length && gewaehlt.size ? t('Auswahl aufheben') : t('Alle wählen');
    alle.disabled = !d.gesichter.length;
  };
  for (const g of d.gesichter) {
    raster.append(gesichtszelle(g, (b) => {
      if (gewaehlt.has(g.id)) gewaehlt.delete(g.id); else gewaehlt.add(g.id);
      b.classList.toggle('gewaehlt', gewaehlt.has(g.id));
      neu();
    }));
  }
  alle.addEventListener('click', () => {
    const an = gewaehlt.size !== d.gesichter.length;
    for (const g of d.gesichter) if (an) gewaehlt.add(g.id); else gewaehlt.delete(g.id);
    for (const b of raster.querySelectorAll('.gesicht')) b.classList.toggle('gewaehlt', an);
    neu();
  });
  zurueck.addEventListener('click', async () => {
    const ids = [...gewaehlt];
    try {
      await befehl('gesichterBeiseitelegen', { gesichtIds: ids, beiseite: false });
      meldung(t('{n} zurückgeholt', { n: ids.length }));
      await zeigeIgnoriert();
    } catch (x) {
      meldung(x.message);
    }
  });
  kopf.append(text, alle, zurueck);
  box.replaceChildren(kopf, d.gesichter.length ? raster : el('p', 'leise abschnitt', t('Keine ignorierten Gesichter.')));
  neu();
}

let gesichtFall = null;

async function oeffneGesichter(fall) {
  gesichtFall = { ...fall, aus: new Set(), personen: [] };
  $('gesicht-titel').textContent = fall.titel;
  const raster = $('gesicht-auswahl');
  raster.replaceChildren();
  for (const g of fall.gesichter) {
    raster.append(gesichtszelle(g, fall.gesichter.length > 1 ? (b) => {
      if (gesichtFall.aus.has(g.id)) gesichtFall.aus.delete(g.id); else gesichtFall.aus.add(g.id);
      b.classList.toggle('aus');
    } : null));
  }
  $('gesicht-hinweis').hidden = fall.gesichter.length < 2;
  $('gesicht-ja').hidden = !fall.vorschlag;
  if (fall.vorschlag) $('gesicht-ja').textContent = t('Das ist {name}', { name: fall.vorschlag.name });
  $('gesicht-loesen').hidden = !fall.person;
  // Löschen nur einzeln: Es nimmt den Rahmen aus dem Foto, und das will
  // man sehen, bevor man es tut.
  $('gesicht-loeschen').hidden = fall.gesichter.length !== 1;
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
$('gesicht-loeschen').addEventListener('click', () => {
  if (!confirm(t('Diesen Rahmen löschen? Die Erkennung verschwindet überall.'))) return;
  gesichterFertig(async (ids) => { for (const id of ids) await befehl('gesichtLoeschen', { gesichtId: id }); });
});
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
    const zelle = gesichtszelle(v, (b) => {
      if (vorschlagFall.gewaehlt.has(v.id)) vorschlagFall.gewaehlt.delete(v.id); else vorschlagFall.gewaehlt.add(v.id);
      b.classList.toggle('aus', !vorschlagFall.gewaehlt.has(v.id));
      vorschlagKnopf();
    });
    zelle.firstChild.title = `${Math.round(v.aehnlichkeit * 100)} %`;
    raster.append(zelle);
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
  for (const b of $('vorschlag-auswahl').querySelectorAll('.gesicht')) b.classList.toggle('aus', !f.gewaehlt.has(b.dataset.id));
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

let suchlauf = 0;

function filterParameter() {
  const q = new URLSearchParams();
  for (const id of suchfilter.personen) q.append('person', id);
  for (const [name, feld] of [['land', 'filter-land'], ['stadt', 'filter-stadt'], ['von', 'filter-von'], ['bis', 'filter-bis'], ['art', 'filter-art'], ['kamera', 'filter-kamera'], ['herkunft', 'filter-herkunft']]) {
    if ($(feld).value) q.set(name, $(feld).value);
  }
  if ($('filter-favoriten').checked) q.set('favoriten', '1');
  if ($('filter-ohne-album').checked) q.set('ohneAlbum', '1');
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
  if ($('filter-herkunft').value) teile.push($('filter-herkunft').selectedOptions[0].textContent);
  if ($('filter-favoriten').checked) teile.push(t('Favoriten'));
  if ($('filter-ohne-album').checked) teile.push(t('Nicht in einem Album'));
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
for (const id of ['filter-stadt', 'filter-von', 'filter-bis', 'filter-art', 'filter-kamera', 'filter-herkunft', 'filter-favoriten', 'filter-ohne-album']) $(id).addEventListener('change', zeigeFilterzeile);
$('filter-leeren').addEventListener('click', () => {
  suchfilter.personen.clear();
  for (const b of $('filter-personen').querySelectorAll('[aria-pressed]')) b.setAttribute('aria-pressed', 'false');
  for (const id of ['filter-land', 'filter-von', 'filter-bis', 'filter-art', 'filter-kamera', 'filter-herkunft']) $(id).value = '';
  $('filter-favoriten').checked = false;
  $('filter-ohne-album').checked = false;
  fuelleStaedte();
  zeigeFilterzeile();
});

// Die zuletzt gelaufene Suche – zum Merken als intelligentes Album (#187).
let letzteSuche = null;
$('suche-merken').addEventListener('click', () => {
  if (!letzteSuche) return;
  const f = $('form-merken');
  f.name.value = letzteSuche.text || '';
  $('merken-meldung').textContent = '';
  $('merken-dialog').showModal();
  f.name.focus();
});
$('merken-abbrechen').addEventListener('click', () => $('merken-dialog').close());
$('form-merken').addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = e.target.name.value.trim();
  if (!name || !letzteSuche) return;
  try {
    await api(`/api/v1/intelligente-alben?${letzteSuche.q}`, { methode: 'POST', json: { sucheId: neueKennung(), name } });
    $('merken-dialog').close();
    meldung(t('„{name}“ steht jetzt unter Alben.', { name }));
  } catch (x) { $('merken-meldung').textContent = x.message; }
});

$('form-suche').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const text = f.text.value.trim();
  const q = filterParameter();
  if (!text && ![...q.keys()].length) { $('suche-hinweis').textContent = t('Suchtext eingeben oder einen Filter wählen.'); return; }
  $('suche-hinweis').textContent = t('Sucht …');
  try {
    // Eigener Name: `art` ist der Filter bild|video.
    if (text) { q.set('text', text); q.set('modus', f.art.value); }
    const lauf = ++suchlauf;
    const d = await api(`/api/v1/suche?${q}`);
    if (lauf !== suchlauf) return;
    // Seitenweise (#186): Der Server schickt alle Kennungen, die Zeilen nur
    // für die erste Seite; den Rest holt das Raster beim Blättern.
    const ids = d.kennungen || d.aufnahmen.map((a) => a.id);
    let pos = d.aufnahmen.length;
    const mehr = async () => {
      const stueck = ids.slice(pos, pos + 300);
      pos += stueck.length;
      const s = await api('/api/v1/aufnahmen/liste', { methode: 'POST', json: { ids: stueck } });
      return { aufnahmen: s.aufnahmen, weiter: pos < ids.length ? 'mehr' : null };
    };
    zeigeListe({ aufnahmen: d.aufnahmen, suche: true, mehr: pos < ids.length ? mehr : null });
    if (pos < ids.length) $('ende').textContent = t('{n} Treffer', { n: zahl.format(ids.length) });
    $('suche-hinweis').textContent = ids.length ? '' : t('Nichts gefunden.');
    letzteSuche = { q: q.toString(), text };
    $('suche-merken').hidden = false;
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
  // Neue Wiederherstellungscodes – etwa wenn die alten irgendwo offen
  // lagen. Bestätigt mit einem Code aus der Authenticator-App.
  $('codes-feld').hidden = !k.totp;
  $('codes-stand').textContent = k.wiederherstellungscodes === 1
    ? t('Noch ein Code übrig.')
    : t('Noch {n} Codes übrig.', { n: k.wiederherstellungscodes ?? 0 });
  $('codes-fehler').textContent = '';
  zeigeFassung($('konto-fassung'));
  $('verwaltung').hidden = !k.verwalter;
  if (k.verwalter) ladeImmich();
  if (k.verwalter) zeigeVerwaltung().catch((x) => { $('server-stand').replaceChildren(el('li', null, x.message)); });
  zeigeFreigaben().catch((x) => $('freigaben').replaceChildren(el('li', 'fehler', x.message)));
  zeigePartner().catch((x) => $('partner').replaceChildren(el('li', 'fehler', x.message)));
  zeigeNachlass().catch((x) => $('nachlass-meine').replaceChildren(el('li', 'fehler', x.message)));
  zeigeBeitraege().catch(() => {});
  zeigeOidc(k).catch(() => {});
  zeigePasskeys().catch((x) => { $('passkey-meldung').textContent = x.message; });
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

// --- Passkeys des Kontos (#277) --------------------------------------------------

async function zeigePasskeys() {
  $('passkey-feld').hidden = !passkeysMoeglich();
  if (!passkeysMoeglich()) return;
  const d = await api('/api/v1/konto/passkeys');
  const ul = $('passkeys');
  ul.replaceChildren();
  if (!d.passkeys.length) ul.append(el('li', 'leise', t('Noch keiner.')));
  for (const p of d.passkeys) {
    const li = el('li');
    const zuletzt = p.zuletzt ? t('zuletzt {datum}', { datum: datumZeit.format(new Date(p.zuletzt)) }) : t('noch nie benutzt');
    li.append(el('span', null, `${p.name} · ${t('angelegt {datum}', { datum: datum.format(new Date(p.angelegt)) })} · ${zuletzt}`));
    const b = el('button', null, t('Entfernen'));
    b.type = 'button';
    b.addEventListener('click', async () => {
      if (!confirm(t('Den Passkey „{name}“ entfernen? Auf dem Gerät bleibt er liegen, anmelden lässt sich damit nicht mehr.', { name: p.name }))) return;
      try { await api(`/api/v1/konto/passkeys/${encodeURIComponent(p.id)}`, { methode: 'DELETE' }); await zeigePasskeys(); } catch (y) { $('passkey-meldung').textContent = y.message; }
    });
    li.append(b);
    ul.append(li);
  }
}

$('passkey-hinzufuegen').addEventListener('click', async () => {
  const name = prompt(t('Wie soll der Passkey heissen? Etwa nach dem Gerät, auf dem er liegt.'), '');
  if (name === null) return;
  $('passkey-meldung').textContent = '';
  try {
    const o = await api('/api/v1/konto/passkeys/optionen', { methode: 'POST', json: {} });
    const antwort = await passkeyAnlegen(o.optionen);
    await api('/api/v1/konto/passkeys', { methode: 'POST', json: { antwort, name: name.trim() } });
    $('passkey-meldung').textContent = t('Der Passkey ist angelegt.');
    await zeigePasskeys();
  } catch (x) {
    $('passkey-meldung').textContent = passkeyAbgebrochen(x) ? t('Abgebrochen.') : x.message;
  }
});

// Anmelden mit Passkey: Das Gerät bietet an, was es für diesen Server hat.
$('passkey-anmelden').hidden = !passkeysMoeglich();
$('passkey-anmelden').addEventListener('click', async () => {
  fehler('');
  try {
    const o = await api('/api/v1/anmelden/passkey/optionen', { methode: 'POST', json: {} });
    const antwort = await passkeyBestaetigen(o.optionen);
    await nachAnmeldung(await api('/api/v1/web/anmelden/passkey', { methode: 'POST', json: { antwort } }));
  } catch (x) {
    if (!passkeyAbgebrochen(x)) fehler(x.message);
  }
});

$('form-codes').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  $('codes-fehler').textContent = '';
  try {
    const d = await api('/api/v1/konto/wiederherstellungscodes', { methode: 'POST', json: { code: f.code.value.trim() } });
    f.reset();
    await zeigeCodes(d.wiederherstellungscodes);
    zeigeKonto();
  } catch (x) {
    $('codes-fehler').textContent = x.message;
  }
});

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

// --- Anmeldung über den Anbieter (OIDC, #182) ----------------------------
//
// Wie am Rechner und auf dem Telefon (kern/abgleich/oidc_verknuepfung.dart):
// Der Server nennt die Adresse beim Anbieter, der Browser geht hin und kommt
// über den Server auf diese Seite zurück. Den Prüfer (PKCE) kennt nur diese
// Seite – er liegt bis zur Rückkehr im sessionStorage dieses Tabs. Der
// Server nimmt als Rückweg ins Netz nur seine eigene Weboberfläche unter der
// Adresse von aussen an; über eine andere Adresse geht es deshalb nicht.

const OIDC_MERKER = 'pv-oidc';
let oidcSeite = null;
let oidcErgebnis = null;

const zufallsText = (n) => {
  const zeichen = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const b = crypto.getRandomValues(new Uint8Array(n));
  return Array.from(b, (x) => zeichen[x & 63]).join('');
};
const base64url = (puffer) => btoa(String.fromCharCode(...new Uint8Array(puffer)))
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function zeigeOidc(k) {
  const a = (await api('/api/v1/zustand')).anmeldung || {};
  $('oidc-feld').hidden = !a.oidc;
  if (!a.oidc) return;
  oidcSeite = a.weboberflaeche || null;
  const anbieter = k.oidc || [];
  $('oidc-stand').textContent = anbieter.length
    ? t('Verknüpft mit {anbieter}', { anbieter: anbieter.join(', ') })
    : t('Nicht verknüpft – die Anmeldung geht dann nur mit Passwort.');
  // Nur unter der Adresse, die der Anbieter kennt – und nur dort, wo der
  // Browser rechnen darf (crypto.subtle gibt es nur über HTTPS).
  const hier = oidcSeite && new URL(oidcSeite).origin === location.origin && window.crypto && crypto.subtle;
  $('oidc-verknuepfen').disabled = !hier;
  const anderswo = $('oidc-anderswo');
  anderswo.hidden = !!hier;
  if (!hier && oidcSeite) {
    const link = el('a', null, oidcSeite);
    link.href = oidcSeite;
    anderswo.replaceChildren(t('Verknüpfen geht nur über die Adresse, die der Anbieter kennt:') + ' ', link);
  }
  $('oidc-meldung').textContent = oidcErgebnis || '';
  oidcErgebnis = null;
}

$('oidc-verknuepfen').addEventListener('click', async () => {
  const m = $('oidc-meldung');
  m.textContent = '';
  try {
    const pruefer = zufallsText(64);
    const zustand = zufallsText(24);
    const pruefwert = base64url(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(pruefer)));
    const d = await api('/api/v1/konto/oidc', { methode: 'POST', json: { rueckweg: oidcSeite, pruefwert, zustand } });
    sessionStorage.setItem(OIDC_MERKER, JSON.stringify({ pruefer, zustand }));
    location.assign(d.adresse);
  } catch (x) { m.textContent = x.message; }
});

// Zurück vom Anbieter: `?code=…&zustand=…` (oder `fehler=…`). Die Angaben
// verschwinden sofort aus der Adresszeile – sie gehören weder in den
// Verlauf noch in ein Lesezeichen.
async function oidcZurueck() {
  const q = new URLSearchParams(location.search);
  if (!q.has('zustand') || !(q.has('code') || q.has('fehler'))) return;
  history.replaceState(null, '', `${location.pathname}#/konto`);
  let gemerkt = null;
  try {
    gemerkt = JSON.parse(sessionStorage.getItem(OIDC_MERKER) || 'null');
    sessionStorage.removeItem(OIDC_MERKER);
  } catch (_) { /* privat */ }
  const code = q.get('code');
  if (!gemerkt || gemerkt.zustand !== q.get('zustand') || !code) {
    oidcErgebnis = t('Nicht verknüpft – im Browser abgebrochen oder abgelehnt.');
    return;
  }
  try {
    const e = await api('/api/v1/anmelden/oidc/einloesen', { methode: 'POST', json: { code, pruefer: gemerkt.pruefer } });
    oidcErgebnis = e.verknuepft
      ? t('Verknüpft. Künftig geht die Anmeldung auch über den Anbieter.')
      : t('Nicht verknüpft – im Browser abgebrochen oder abgelehnt.');
  } catch (x) {
    oidcErgebnis = x.status === 409 ? t('Dieses Konto beim Anbieter gehört schon zu einem anderen Konto.') : x.message;
  }
}

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
let orteZoom = null;

async function zeigeKarte() {
  markiereNav('karte');
  zeigeBereich(['karte']);
  await ladeLeaflet();
  if (!leafletKarte) {
    leafletKarte = L.map('karte', { worldCopyJump: true }).setView([51, 10], 5);
    osmKacheln().addTo(leafletKarte);
    karteMarker = L.layerGroup().addTo(leafletKarte);
    leafletKarte.on('moveend', () => ladeOrte());
    await ladeOrte(true);
  } else if (stillerLauf) {
    orteZoom = null;
    await ladeOrte();
  } else {
    setTimeout(() => leafletKarte.invalidateSize(), 50);
  }
}

async function ladeOrte(zentrieren = false) {
  // Die Antwort hängt nur vom Zoom ab; blosses Verschieben braucht nichts Neues.
  const zoom = Math.round(leafletKarte.getZoom());
  if (zoom === orteZoom && !zentrieren) return;
  orteZoom = zoom;
  const lauf = ++karteLauf;
  const d = await api(`/api/v1/orte?zoom=${zoom}`);
  if (lauf !== karteLauf) return;
  karteMarker.clearLayers();
  const punkte = [];
  for (const g of d.gruppen) {
    const icon = L.divIcon({ className: '', html: `<div class="punkt${g.anzahl > 99 ? ' gross' : ''}">${g.anzahl}</div>`, iconSize: [36, 36] });
    const m = L.marker([g.breite, g.laenge], { icon });
    m.on('click', async () => {
      if (g.anzahl > 1 && leafletKarte.getZoom() < 17) { leafletKarte.setView([g.breite, g.laenge], leafletKarte.getZoom() + 2); return; }
      let r;
      try {
        r = await api('/api/v1/aufnahmen/liste', { methode: 'POST', json: { ids: g.ids } });
      } catch (x) { meldung(x.message); return; }
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
  const zeile = (text) => { const li = el('li'); li.append(el('span', null, text)); ul.append(li); };
  try {
    const sp = await api('/api/v1/speicher');
    zeile(t('Speicher: {frei} frei von {gesamt}', { frei: gb(sp.frei), gesamt: gb(sp.gesamt) }) + (sp.stufe !== 'ok' ? ' – ' + t(sp.stufe) : ''));
  } catch (_) { /* kein Speicherwächter */ }
  try {
    const sv = await api('/api/v1/sicherung');
    zeile(t('Sicherung: {stufe}', { stufe: t(sv.stufe) }) + (sv.letzterErfolg ? ' · ' + t('zuletzt {datum}', { datum: datumZeit.format(new Date(sv.letzterErfolg)) }) : '') + (sv.naechster ? ' · ' + t('nächste {datum}', { datum: datumZeit.format(new Date(sv.naechster)) }) : '') + (sv.fehler ? ' · ' + sv.fehler : ''));
    $('sicherung-jetzt').hidden = sv.stufe === 'aus' || sv.stufe === 'nichtEingerichtet';
    zeigeAussen(sv.ausserHaus, sv.stufe);
  } catch (_) { $('sicherung-jetzt').hidden = true; $('aussen').hidden = true; }
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
const aussenStufen = { aus: 'nicht eingerichtet', ausstehend: 'wartet auf den ersten Lauf', fehler: 'gescheitert', veraltet: 'veraltet', ok: 'in Ordnung' };
const mb = (b) => `${(b / 1048576).toFixed(0)} MB`;
let aussenUhr = null;
let aussenGezeigt = '';
function zeigeAussen(a, stufe) {
  clearTimeout(aussenUhr);
  // Ohne eigene Sicherung gibt es nichts zu übertragen.
  const da = Boolean(a) && a.moeglich && stufe !== 'nichtEingerichtet';
  $('aussen').hidden = !da;
  if (!da) return;
  const teile = [t('Stand: {stufe}', { stufe: t(aussenStufen[a.stufe] || a.stufe) })];
  if (a.laeuft) {
    const f = a.fortschritt;
    teile.push(f ? t('läuft: {n} von {von} Dateien, {mb} von {gesamt}', { n: f.erledigt, von: f.gesamt, mb: mb(f.bytes), gesamt: mb(f.bytesGesamt) }) : t('läuft'));
  }
  if (a.letzterErfolg) teile.push(t('zuletzt {datum}', { datum: datumZeit.format(new Date(a.letzterErfolg)) }));
  if (a.fehler) teile.push(a.fehler === 'pv_stichprobe_abweichend' ? t('Eine Stichprobe stimmt nicht mit dem Original überein.') : a.fehler);
  $('aussen-stand').textContent = teile.join(' · ');
  const f = $('form-aussen');
  const z = a.ziel;
  // Nur wenn sich am Ziel etwas geändert hat: Der Stand kommt während eines
  // Laufs immer wieder, und getippt wird dabei vielleicht gerade.
  if (z && JSON.stringify(z) !== aussenGezeigt) {
    aussenGezeigt = JSON.stringify(z);
    f.art.value = z.art;
    f.adresse.value = z.adresse || '';
    f.bucket.value = z.bucket || '';
    f.region.value = z.region || '';
    f.zugang.value = z.zugang || '';
    f.praefix.value = z.praefix || '';
    f.drosselMb.value = z.drosselMb || '';
  }
  f.geheimnis.placeholder = z ? t('unverändert') : '';
  f.geheimnis.required = !z;
  $('aussen-jetzt').hidden = !z || a.laeuft;
  $('aussen-entfernen').hidden = !z;
  aussenArtGeaendert();
  if (a.laeuft) {
    aussenUhr = setTimeout(async () => {
      if (!$('aussen').offsetParent) return;
      try { const sv = await api('/api/v1/sicherung'); zeigeAussen(sv.ausserHaus, sv.stufe); } catch (_) { /* beim nächsten Öffnen */ }
    }, 4000);
  }
}
function aussenArtGeaendert() {
  const f = $('form-aussen');
  const s3 = f.art.value === 's3';
  for (const x of f.querySelectorAll('.nur-s3')) x.hidden = !s3;
  f.bucket.required = s3;
  f.adresse.placeholder = s3 ? 'https://s3.eu-central-1.amazonaws.com' : 'https://cloud.example.org/remote.php/dav/files/name/';
  $('aussen-zugang-text').textContent = t(s3 ? 'Schlüssel-ID' : 'Benutzer');
  $('aussen-geheimnis-text').textContent = t(s3 ? 'Geheimschlüssel' : 'Passwort');
}
$('form-aussen').art.addEventListener('change', aussenArtGeaendert);
$('form-aussen').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  const knopf = f.querySelector('button[type=submit]');
  knopf.disabled = true;
  try {
    await api('/api/v1/sicherung/ausser-haus', { methode: 'PUT', json: {
      art: f.art.value, adresse: f.adresse.value.trim(), bucket: f.bucket.value.trim(), region: f.region.value.trim(),
      zugang: f.zugang.value.trim(), geheimnis: f.geheimnis.value, praefix: f.praefix.value.trim(), drosselMb: Number(f.drosselMb.value) || null,
    } });
    f.geheimnis.value = '';
    zeigeVerwaltung();
  } catch (x) { alert(x.message); } finally { knopf.disabled = false; }
});
$('aussen-jetzt').addEventListener('click', async () => { try { await api('/api/v1/sicherung/ausser-haus/jetzt', { methode: 'POST', json: {} }); zeigeVerwaltung(); } catch (x) { alert(x.message); } });
$('aussen-entfernen').addEventListener('click', async () => {
  if (!confirm(t('Das Ziel vergessen? Was dort liegt, bleibt liegen.'))) return;
  try { await api('/api/v1/sicherung/ausser-haus', { methode: 'DELETE' }); $('form-aussen').reset(); aussenGezeigt = ''; zeigeVerwaltung(); } catch (x) { alert(x.message); }
});
// Aus Immich übernehmen (#305): erst prüfen, dann die gewählten Teile.
let immichUhr = null;
const immichStufen = { laden: 'Liest aus Immich …', pruefsummen: 'Vergleicht die Originale …', gesichter: 'Liest die Gesichter …', uebernehmen: 'Übernimmt …' };
function zeigeImmich(s) {
  clearTimeout(immichUhr);
  const laeuft = Object.hasOwn(immichStufen, s.stufe);
  const knopf = $('form-immich').querySelector('button[type=submit]');
  knopf.disabled = laeuft;
  let text = '';
  if (laeuft) text = t(immichStufen[s.stufe]) + (s.fertig ? ` ${s.fertig}${s.von ? ` / ${s.von}` : ''}` : '');
  else if (s.stufe === 'fehler') text = s.fehler || t('Das ist gescheitert.');
  else if (s.stufe === 'fertig') text = t('Übernommen: {a} Aufnahmen in Alben, {f} Favoriten, {b} Beschreibungen, {g} Gesichter, {p} neue Personen, {r} im Archiv-Album.', { a: s.ergebnis.albumAufnahmen, f: s.ergebnis.favoriten, b: s.ergebnis.beschreibungen, g: s.ergebnis.gesichter, p: s.ergebnis.personenNeu, r: s.ergebnis.archiv });
  $('immich-stand').textContent = text;
  $('immich-bericht').hidden = !s.bericht || laeuft;
  if (s.bericht && !laeuft) zeigeImmichBericht(s.bericht);
  if (laeuft) {
    immichUhr = setTimeout(async () => {
      if (!$('immich').offsetParent) return;
      try { zeigeImmich(await api('/api/v1/immich')); } catch (_) { /* beim nächsten Öffnen */ }
    }, 1500);
  }
}
function zeigeImmichBericht(b) {
  const z = b.zuordnung, v = b.vorhaben, zeilen = $('immich-zahlen');
  zeilen.replaceChildren();
  const zeile = (text) => zeilen.append(el('li', null, text));
  zeile(t('Immich {f}: {n} Aufnahmen, {a} Alben, {p} benannte Personen', { f: b.fassung, n: b.immich.aufnahmen, a: b.immich.alben, p: b.immich.personen }));
  zeile(t('Gefunden: {g} bitgleich, {s} mit anderen Metadaten', { g: z.bitgleich, s: z.aehnlich }));
  zeile(t('Fehlen hier: {n}', { n: z.fehlen }));
  if (z.andereZeit) zeile(t('Gleicher Name, andere Zeit (bitte ansehen): {n}', { n: z.andereZeit }));
  if (z.papierkorb) zeile(t('Hier im Papierkorb: {n}', { n: z.papierkorb }));
  if (v.beschreibungenAbweichend) zeile(t('Beschreibungen, die hier anders lauten und bleiben: {n}', { n: v.beschreibungenAbweichend }));
  const ohne = z.beispiele || [];
  $('immich-ohne').hidden = !ohne.length;
  $('immich-ohne-titel').textContent = t('Nicht zugeordnet: {n}', { n: ohne.length });
  $('immich-ohne-liste').replaceChildren(...ohne.map((o) => el('li', null, `${o.name} · ${datumZeit.format(new Date(o.zeit))} · ${t(({ fehlt: 'fehlt', andereZeit: 'andere Zeit', papierkorb: 'im Papierkorb', mehrdeutig: 'mehrdeutig' })[o.grund] || o.grund)}`)));
  const namen = [
    ...v.abweichendeNamen.map((n) => t('In Immich „{i}“, hier „{b}“: bleibt „{b}“', { i: n.immich, b: n.bibliothek })),
    ...v.unklar.map((n) => t('„{n}“: keine klare Zuordnung, nichts geändert', { n })),
  ];
  $('immich-namen').hidden = !namen.length;
  $('immich-namen-liste').replaceChildren(...namen.map((n) => el('li', null, n)));
  const teile = [
    ['alben', t('{n} Aufnahmen in {a} Alben', { n: v.albumAufnahmen, a: v.albenNeu + v.albenErgaenzt })],
    ['favoriten', t('{n} Favoriten', { n: v.favoriten })],
    ['beschreibungen', t('{n} Beschreibungen', { n: v.beschreibungen })],
    ['personen', t('{g} Gesichter, {p} neue Personen, {b} Geburtstage', { g: v.gesichter, p: v.personenNeu, b: v.geburtstage })],
    ['archiv', t('{n} archivierte Aufnahmen ins Album „Archiv (aus Immich)“', { n: v.archiv })],
  ];
  $('immich-teile').replaceChildren(...teile.map(([name, text]) => {
    const l = el('label'), kasten = el('input');
    kasten.type = 'checkbox'; kasten.name = name; kasten.checked = true;
    l.append(kasten, ' ', text);
    return l;
  }));
  $('form-immich-teile').querySelector('button[type=submit]').disabled = !v.aenderungen;
}
async function ladeImmich() { try { zeigeImmich(await api('/api/v1/immich')); } catch (_) { /* später */ } }
$('form-immich').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target;
  try {
    zeigeImmich(await api('/api/v1/immich/pruefen', { methode: 'POST', json: { adresse: f.adresse.value.trim(), schluessel: f.schluessel.value } }));
    f.schluessel.value = '';
  } catch (x) { alert(x.message); }
});
$('form-immich-teile').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!confirm(t('Jetzt in die Bibliothek übernehmen?'))) return;
  const teile = {};
  for (const k of e.target.querySelectorAll('input[type=checkbox]')) teile[k.name] = k.checked;
  try { zeigeImmich(await api('/api/v1/immich/uebernehmen', { methode: 'POST', json: teile })); } catch (x) { alert(x.message); }
});
$('immich-verwerfen').addEventListener('click', async () => { try { zeigeImmich(await api('/api/v1/immich', { methode: 'DELETE' })); } catch (x) { alert(x.message); } });
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
  const a = liste && liste.aufnahmen[Number(k.dataset.index)];
  if (fremdeAufnahme(a)) return;
  if (auswahl.has(id)) auswahl.delete(id); else auswahl.add(id);
  k.classList.toggle('gewaehlt', auswahl.has(id));
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
  // Vergleichen gibt es für genau zwei – wie am Rechner.
  $('auswahl-vergleichen').hidden = n !== 2;
  // Collagen aus 2 bis 9 eigenen Fotos (#301).
  $('auswahl-collage').hidden = n < 2 || n > 9 || !!liste.papierkorb || fremdeListe();
  $('auswahl-varianten').hidden = n < 2 || !!liste.papierkorb;
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
  if (!a || fremdeAufnahme(a)) return;
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
    if (liste.aufnahmen[i].konto) continue;
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
// Ohne feste Wahl so viele, wie das Raster von selbst legt (mindestens
// 140 Punkte je Kachel); in bündigen Reihen gibt es keine Spalten, dort
// ist es dieselbe Rechnung.
const spaltenJetzt = () => spalten || (ansicht.form === 'reihen'
  ? Math.max(2, Math.floor(($('raster').clientWidth - 2) / 142))
  : getComputedStyle($('raster')).gridTemplateColumns.split(' ').filter(Boolean).length);

// Die Reihenhöhe der bündigen Reihen: so hoch, wie eine quadratische
// Kachel breit wäre – Grösser und Kleiner wirken in beiden Formen gleich.
function legeForm() {
  const r = $('raster');
  // In der Liste gibt es keine Form – sie gilt fürs Raster.
  const reihen = ansicht.form === 'reihen' && !(liste && liste.alsListe);
  r.classList.toggle('reihen', reihen);
  if (reihen) {
    const n = spaltenJetzt();
    const breite = r.clientWidth - 4;
    if (breite > 0) r.style.setProperty('--hoehe', `${Math.max(60, Math.round((breite - 2 * (n - 1)) / n))}px`);
  }
  zeigeAnsichtsleiste();
}
window.addEventListener('resize', () => { if (ansicht.form === 'reihen') legeForm(); });

function zeigeAnsichtsleiste() {
  if ($('ansichtsleiste').hidden) return;
  $('ansicht-sortierung').value = ansicht.sortierung;
  const alsListe = ansicht.liste;
  $('ansicht-raster').setAttribute('aria-pressed', String(!alsListe));
  $('ansicht-liste').setAttribute('aria-pressed', String(alsListe));
  // Wie am Rechner: Gliederung und Spalten nur bei der Liste, Tage, Form
  // und Grösse nur beim Raster – ein Knopf, der nichts bewirkt, wäre
  // irreführend.
  $('ansicht-gliederung').hidden = !alsListe || !nachDatum();
  $('ansicht-gliederung').value = ansicht.gliederung;
  $('ansicht-spalten').hidden = !alsListe;
  for (const id of ['ansicht-form', 'ansicht-kleiner', 'ansicht-groesser']) $(id).hidden = alsListe;
  const tage = $('ansicht-tage');
  tage.hidden = alsListe || !nachDatum();
  tage.setAttribute('aria-pressed', String(ansicht.tage));
  const tageText = ansicht.tage ? t('Nur nach Monaten gliedern') : t('Nach Tagen gliedern');
  tage.title = tageText;
  tage.setAttribute('aria-label', tageText);
  const form = $('ansicht-form');
  const formText = ansicht.form === 'reihen' ? t('Quadratisches Raster') : t('Bündige Reihen – jedes Foto in seinem Format');
  form.title = formText;
  form.setAttribute('aria-label', formText);
  form.querySelector('use').setAttribute('href', ansicht.form === 'reihen' ? '#i-quadrate' : '#i-reihen');
  const n = spaltenJetzt();
  $('ansicht-groesser').disabled = n <= 2;
  $('ansicht-kleiner').disabled = n >= meisteSpalten();
}

$('ansicht-sortierung').addEventListener('change', (e) => {
  ansicht.sortierung = SORTIERUNGEN.includes(e.target.value) ? e.target.value : 'aufnahmeNeu';
  merkeAnsicht();
  zeitleiste.leeren();
  window.scrollTo(0, 0);
  zeigeFotos();
});
function wechsleAnsicht(alsListe) {
  if (ansicht.liste === alsListe) return;
  ansicht.liste = alsListe;
  merkeAnsicht();
  // Die Liste braucht mehr Angaben je Zeile – neu laden.
  zeitleiste.leeren();
  window.scrollTo(0, 0);
  zeigeFotos();
}
// Die Jahre auf einen Blick (#196) – wie am Rechner; der Kalender zeigt
// sie samt Titelbild, ein Tipp führt zu den Monaten.
$('ansicht-jahre').addEventListener('click', () => { location.hash = '#/kalender'; });
$('ansicht-raster').addEventListener('click', () => wechsleAnsicht(false));
$('ansicht-liste').addEventListener('click', () => wechsleAnsicht(true));
$('ansicht-gliederung').addEventListener('change', (e) => {
  ansicht.gliederung = GLIEDERUNGEN.includes(e.target.value) ? e.target.value : 'monat';
  merkeAnsicht();
  zeigeFotos();
});
// Die Spalten an- und abschalten; die letzte bleibt, sonst wäre die Liste
// eine leere Fläche ohne Weg zurück (wie am Rechner).
$('ansicht-spalten').addEventListener('click', () => {
  const box = $('spalten-liste');
  box.replaceChildren();
  for (const s of LISTENSPALTEN) {
    const z = el('label');
    const k = el('input');
    k.type = 'checkbox';
    k.checked = ansicht.spalten.includes(s);
    k.addEventListener('change', () => {
      const an = k.checked;
      if (!an && ansicht.spalten.length <= 1) { k.checked = true; return; }
      // Beim Einschalten an ihren Platz, nicht ans Ende.
      ansicht.spalten = LISTENSPALTEN.filter((x) => (x === s ? an : ansicht.spalten.includes(x)));
      merkeAnsicht();
      zeigeFotos();
    });
    z.append(k, el('span', null, t(LISTENTITEL[s])));
    box.append(z);
  }
  $('spalten-dialog').showModal();
});
$('spalten-zu').addEventListener('click', () => $('spalten-dialog').close());
$('ansicht-tage').addEventListener('click', () => {
  ansicht.tage = !ansicht.tage;
  merkeAnsicht();
  zeigeFotos();
});
$('ansicht-form').addEventListener('click', () => {
  ansicht.form = ansicht.form === 'reihen' ? 'quadrate' : 'reihen';
  merkeAnsicht();
  legeForm();
});
// Kleiner heisst mehr Fotos nebeneinander und damit mehr Monate auf einmal.
$('ansicht-kleiner').addEventListener('click', () => setzeSpalten(spaltenJetzt() + 1, true));
$('ansicht-groesser').addEventListener('click', () => setzeSpalten(spaltenJetzt() - 1, true));

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
  legeForm();
  pruefeScharf();
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
  const lang = !$('bereich-raster').hidden && $('betrachter').hidden && liste && liste.aufnahmen.length > 0 &&
    (bildlaufHoehe() > innerHeight * 2 || (monatsleiste() && !!liste.mehr));
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

function setzeGriff(anteil) {
  const b = $('bildlauf'), g = $('bildlauf-griff');
  const raum = b.clientHeight - g.offsetHeight;
  if (anteil === undefined) {
    const m = monatsleiste() ? monatsschluesselOben() : null;
    if (m && zeitleistenmonate.ab.has(m)) {
      anteil = zeitleistenmonate.ab.get(m);
    } else {
      const max = bildlaufHoehe();
      anteil = max > 0 ? Math.min(1, Math.max(0, scrollY / max)) : 0;
    }
  }
  g.style.transform = `translateY(${anteil * raum}px)`;
  $('bildlauf-monat').style.transform = `translateY(${anteil * raum}px)`;
  if (bildlauf.zieht) blendeJahreNahe(anteil * raum + g.offsetHeight / 2);
}

// --- Die ganze Zeitleiste an der Leiste (#278) ----------------------------
//
// Geladen ist die Zeitleiste seitenweise; die Leiste reichte deshalb nur
// bis zum Ende dessen, was schon da war. In der Zeitleiste nach
// Aufnahmedatum kennt sie jetzt alle Monate samt Anzahl vom Server: Ihre
// Länge ist die ganze Bibliothek, beim Ziehen stehen die Jahre an ihrer
// Stelle, und ein Monat, der noch nicht geladen ist, wird beim Loslassen
// nachgeladen – wie in der Handy-App und am Rechner.

const zeitleistenmonate = { liste: null, ab: new Map(), fuer: null };

function monatsschluessel(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
}

async function holeZeitleistenmonate() {
  const d = await api(`/api/v1/zeitleiste/monate?sortierung=${encodeURIComponent(ansicht.sortierung)}`);
  const monate = ansicht.sortierung === 'aufnahmeAlt' ? [...d.monate].reverse() : d.monate;
  const gesamt = monate.reduce((n, m) => n + m.anzahl, 0);
  let vorher = 0;
  zeitleistenmonate.ab = new Map();
  for (const m of monate) {
    zeitleistenmonate.ab.set(m.monat, gesamt ? vorher / gesamt : 0);
    vorher += m.anzahl;
  }
  zeitleistenmonate.liste = monate;
  zeitleistenmonate.fuer = ansicht.sortierung;
}

// Nur, wo die Reihenfolge der Monate die des Servers ist.
function monatsleiste() {
  return !!(liste && liste.zeitleiste && liste.nachTagen && !liste.alsListe &&
    zeitleistenmonate.liste && zeitleistenmonate.liste.length > 1 &&
    zeitleistenmonate.fuer === ansicht.sortierung &&
    (ansicht.sortierung === 'aufnahmeNeu' || ansicht.sortierung === 'aufnahmeAlt'));
}

// Der Monat der obersten sichtbaren Kachel als Schlüssel.
function monatsschluesselOben() {
  const oben = $('kopf').getBoundingClientRect().bottom;
  const x = $('raster').getBoundingClientRect().left + 24;
  for (let y = oben + 8; y < oben + 260; y += 24) {
    const ziel = document.elementFromPoint(x, y);
    const k = ziel && ziel.closest ? ziel.closest('#raster .kachel') : null;
    const a = k && liste.aufnahmen[Number(k.dataset.index)];
    if (a) return monatsschluessel(new Date(a.aufgenommen));
  }
  return null;
}

// Der Monat an der Stelle [anteil] der Leiste.
function monatBei(anteil) {
  let treffer = zeitleistenmonate.liste[0].monat;
  for (const m of zeitleistenmonate.liste) {
    if (zeitleistenmonate.ab.get(m.monat) <= anteil + 1e-9) treffer = m.monat;
    else break;
  }
  return treffer;
}

function monatAusSchluessel(schluessel) {
  const [j, m] = schluessel.split('-').map(Number);
  return monatJahr.format(new Date(j, m - 1, 1));
}

function monatskopf(schluessel) {
  return $('raster').querySelector(`h2.monat[data-monat="${schluessel}"]`);
}

function fahreZuKopf(k) {
  window.scrollTo(0, k.getBoundingClientRect().top + scrollY - $('kopf').getBoundingClientRect().bottom - 4);
}

// Die Jahreszahlen an ihrer Stelle; dicht beieinander nur die erste.
function legeJahre() {
  const b = $('bildlauf'), g = $('bildlauf-griff'), j = $('bildlauf-jahre');
  const raum = b.clientHeight - g.offsetHeight;
  const spans = [];
  let jahr = null, zuletzt = -Infinity;
  for (const m of zeitleistenmonate.liste) {
    const dieses = m.monat.slice(0, 4);
    if (dieses === jahr) continue;
    jahr = dieses;
    const y = zeitleistenmonate.ab.get(m.monat) * raum + g.offsetHeight / 2;
    if (y - zuletzt < 18) continue;
    zuletzt = y;
    const s = el('span', '', dieses);
    s.style.top = `${y}px`;
    spans.push(s);
  }
  j.replaceChildren(...spans);
}

function blendeJahreNahe(mitte) {
  for (const s of $('bildlauf-jahre').children) {
    s.classList.toggle('nah', Math.abs(parseFloat(s.style.top) - mitte) < 26);
  }
}

async function springeZuMonat(schluessel) {
  const m = $('bildlauf-monat');
  m.classList.add('laedt');
  zeitleiste.seite = 1000;
  try {
    for (let i = 0; i < 400 && !monatskopf(schluessel) && liste && liste.mehr; i++) {
      if (liste.laedt || stillerLauf) { await new Promise((fertig) => setTimeout(fertig, 60)); continue; }
      await ladeMehr();
    }
  } finally {
    zeitleiste.seite = 200;
    m.classList.remove('laedt');
    m.hidden = true;
  }
  const k = monatskopf(schluessel);
  if (k) fahreZuKopf(k);
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
  if (monatsleiste()) {
    // Der Griff folgt dem Finger; geladene Monate kommen sofort, die
    // übrigen beim Loslassen.
    const ziel = monatBei(anteil);
    bildlauf.ziel = ziel;
    const k = monatskopf(ziel);
    if (k) fahreZuKopf(k);
    $('bildlauf-monat').textContent = monatAusSchluessel(ziel);
    $('bildlauf-monat').hidden = false;
    setzeGriff(anteil);
    return;
  }
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
  bildlauf.ziel = null;
  clearTimeout(bildlauf.aus);
  $('bildlauf').classList.add('zieht');
  if (monatsleiste()) legeJahre();
  else $('bildlauf-jahre').replaceChildren();
  zieheBildlauf(e.clientY);
});
$('bildlauf-griff').addEventListener('pointermove', (e) => { if (bildlauf.zieht) zieheBildlauf(e.clientY); });
for (const ev of ['pointerup', 'pointercancel']) {
  $('bildlauf-griff').addEventListener(ev, () => {
    if (!bildlauf.zieht) return;
    bildlauf.zieht = false;
    $('bildlauf').classList.remove('zieht');
    const ziel = bildlauf.ziel;
    bildlauf.ziel = null;
    if (ziel && monatsleiste() && !monatskopf(ziel)) {
      springeZuMonat(ziel).catch(() => { $('bildlauf-monat').hidden = true; }).finally(zeigeBildlauf);
      return;
    }
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
      const r = await fetch(aufnahmeUrl(a.id, 'original'), { credentials: 'same-origin' });
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

// --- Zwei Fotos vergleichen (#197) --------------------------------------------
//
// Wie am Rechner: zwei frei gewählte Fotos nebeneinander oder
// übereinander, mit gekoppeltem Zoom – zoomt oder schiebt man das eine,
// folgt das andere genau. Entkoppelt hat jedes seinen eigenen Ausschnitt.
// Mausrad oder zwei Finger zoomen, Ziehen verschiebt, ein Doppelklick
// setzt zurück.

const vergleich = { gekoppelt: true, uebereinander: false, sicht: [{ z: 1, x: 0, y: 0 }, { z: 1, x: 0, y: 0 }], finger: [new Map(), new Map()] };
const vergleichFelder = [...document.querySelectorAll('#vergleich .vergleich-feld')];
const vergleichSicht = (i) => vergleich.sicht[vergleich.gekoppelt ? 0 : i];

function vergleichZeichne() {
  vergleichFelder.forEach((f, i) => {
    const s = vergleichSicht(i);
    f.querySelector('img').style.transform = `translate(${s.x}px, ${s.y}px) scale(${s.z})`;
  });
  $('vergleich').classList.toggle('uebereinander', vergleich.uebereinander);
  $('vergleich-lage').textContent = vergleich.uebereinander ? t('Nebeneinander') : t('Übereinander');
  $('vergleich-koppeln').textContent = vergleich.gekoppelt ? t('Ansichten entkoppeln') : t('Ansichten koppeln');
}

// Nie über den Rand hinaus: Vergrössert lässt sich höchstens so weit
// schieben, wie das Bild über sein Feld hinausragt.
function vergleichGrenze(s, feld) {
  s.z = Math.min(8, Math.max(1, s.z));
  const r = feld.getBoundingClientRect();
  const mx = (r.width * (s.z - 1)) / 2, my = (r.height * (s.z - 1)) / 2;
  s.x = Math.min(mx, Math.max(-mx, s.x));
  s.y = Math.min(my, Math.max(-my, s.y));
}

// Um den Punkt (px, py) – Bildschirmkoordinaten – zoomen, sodass er an
// seiner Stelle bleibt.
function vergleichZoome(i, faktor, px, py) {
  const feld = vergleichFelder[i].querySelector('.vergleich-bild');
  const r = feld.getBoundingClientRect();
  const s = vergleichSicht(i);
  const z = Math.min(8, Math.max(1, s.z * faktor));
  const k = z / s.z;
  const cx = px - r.left - r.width / 2, cy = py - r.top - r.height / 2;
  s.x = cx - (cx - s.x) * k;
  s.y = cy - (cy - s.y) * k;
  s.z = z;
  vergleichGrenze(s, feld);
  vergleichZeichne();
}

function vergleichZurueck() {
  vergleich.sicht = [{ z: 1, x: 0, y: 0 }, { z: 1, x: 0, y: 0 }];
  vergleichZeichne();
}

function oeffneVergleich(paar) {
  if (paar.length !== 2) return;
  // Hochformatiger Bildschirm: übereinander, sonst blieben zwei schmale
  // Streifen.
  vergleich.uebereinander = innerHeight > innerWidth;
  vergleich.gekoppelt = true;
  paar.forEach((a, i) => {
    const f = vergleichFelder[i];
    f.querySelector('img').src = aufnahmeUrl(a.id, 'ansicht', a.stand);
    f.querySelector('figcaption').textContent = a.name || '';
  });
  vergleichZurueck();
  $('vergleich').hidden = false;
}

function schliesseVergleich() {
  $('vergleich').hidden = true;
  for (const f of vergleichFelder) f.querySelector('img').removeAttribute('src');
}

vergleichFelder.forEach((f, i) => {
  const feld = f.querySelector('.vergleich-bild');
  feld.addEventListener('wheel', (e) => {
    e.preventDefault();
    vergleichZoome(i, Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.002)), e.clientX, e.clientY);
  }, { passive: false });
  feld.addEventListener('dblclick', vergleichZurueck);
  const finger = vergleich.finger[i];
  let zug = null;
  feld.addEventListener('pointerdown', (e) => {
    try { feld.setPointerCapture(e.pointerId); } catch (_) { /* schon weg */ }
    finger.set(e.pointerId, { x: e.clientX, y: e.clientY });
    zug = finger.size === 2 ? { abstand: null } : { x: e.clientX, y: e.clientY };
  });
  feld.addEventListener('pointermove', (e) => {
    if (!finger.has(e.pointerId)) return;
    finger.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const s = vergleichSicht(i);
    if (finger.size === 2) {
      const [a, b] = [...finger.values()];
      const abstand = Math.hypot(a.x - b.x, a.y - b.y);
      if (zug && zug.abstand) vergleichZoome(i, abstand / zug.abstand, (a.x + b.x) / 2, (a.y + b.y) / 2);
      zug = { abstand };
      return;
    }
    if (!zug || zug.x === undefined) return;
    s.x += e.clientX - zug.x;
    s.y += e.clientY - zug.y;
    zug = { x: e.clientX, y: e.clientY };
    vergleichGrenze(s, feld);
    vergleichZeichne();
  });
  const los = (e) => { finger.delete(e.pointerId); zug = null; };
  feld.addEventListener('pointerup', los);
  feld.addEventListener('pointercancel', los);
});

$('vergleich-lage').addEventListener('click', () => { vergleich.uebereinander = !vergleich.uebereinander; vergleichZurueck(); });
$('vergleich-koppeln').addEventListener('click', () => {
  vergleich.gekoppelt = !vergleich.gekoppelt;
  // Entkoppelt beginnt die zweite Seite dort, wo beide gerade stehen.
  if (!vergleich.gekoppelt) vergleich.sicht[1] = { ...vergleich.sicht[0] };
  vergleichZeichne();
});
$('vergleich-zurueck').addEventListener('click', vergleichZurueck);
$('vergleich-zu').addEventListener('click', schliesseVergleich);
$('auswahl-vergleichen').addEventListener('click', () => oeffneVergleich(gewaehlte()));
$('auswahl-varianten').addEventListener('click', () => variantenBilden(gewaehlte()));

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

// --- Herunterladen: Original oder als JPEG (#210) ---------------------------
// Ein DNG, CR3 oder HEIC wandelt der Browser nicht – das tut der Server, aus
// dem, was man sieht (restauriert, entwickelt, sonst das Original).

const JPEG_GROESSEN = [
  { kante: 0, text: 'JPEG – volle Grösse' },
  { kante: 4096, text: 'JPEG – 4096 px' },
  { kante: 2048, text: 'JPEG – 2048 px' },
  { kante: 1024, text: 'JPEG – 1024 px' },
];
const originalUrl = (id) => aufnahmeUrl(id, 'original');
const jpegUrl = (id, kante) => `${aufnahmeUrl(id, 'jpeg')}${kante ? `?kante=${kante}` : ''}`;
const jpegName = (a) => `${(a.name || 'Foto').replace(/\.[^.]+$/, '')}.jpg`;

// Nacheinander, damit der Browser jede als eigene Datei anbietet.
function ladeDateien(aufnahmen, url, name) {
  let i = 0;
  const naechste = () => {
    const a = aufnahmen[i++];
    if (!a) return;
    const l = el('a');
    l.href = url(a);
    l.download = name(a);
    document.body.append(l);
    l.click();
    l.remove();
    setTimeout(naechste, 400);
  };
  naechste();
}

function herunterladenWaehlen(aufnahmen) {
  if (!aufnahmen.length) return;
  const fotos = aufnahmen.filter((a) => a.art !== 'video');
  const ohneVideos = fotos.length < aufnahmen.length ? ` ${t('Videos bleiben aussen vor.')}` : '';
  waehle(aufnahmen.length === 1 ? t('Herunterladen') : t('{n} Aufnahmen herunterladen', { n: aufnahmen.length }), [
    {
      text: t('Original'),
      hinweis: t('Die Datei, wie sie aufgenommen wurde – auch RAW und Video.'),
      aktion: () => ladeDateien(aufnahmen, (a) => originalUrl(a.id), (a) => a.name || ''),
    },
    ...JPEG_GROESSEN.map((g, i) => ({
      text: t(g.text),
      hinweis: i === 0 ? t('Mit der Bearbeitung. Datum und Kamera kommen mit, der Ort nicht.') + ohneVideos : null,
      an: fotos.length > 0,
      aktion: () => ladeDateien(fotos, (a) => jpegUrl(a.id, g.kante), jpegName),
    })),
  ]);
}

$('auswahl-laden').addEventListener('click', () => herunterladenWaehlen(gewaehlte()));

// Im Betrachter: Fotos fragen, Videos laden gleich das Original.
$('laden').addEventListener('click', (e) => {
  const a = liste && liste.aufnahmen[offen];
  if (!a || a.art === 'video') return;
  e.preventDefault();
  herunterladenWaehlen([a]);
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

$('auswahl-endgueltig').addEventListener('click', () => endgueltigLoeschen(gewaehlte()));

// Zurück in die Fotokammer (#337): Der Server legt die Datei dorthin und die
// Aufnahme in den Papierkorb; Freigeben holt sie samt Alben und
// Bearbeitungen zurück.
$('auswahl-kammer').addEventListener('click', async () => {
  const g = gewaehlte();
  if (!g.length) return;
  if (!confirm(g.length === 1
    ? t('Ein Foto in die Fotokammer legen? Es verschwindet aus der Zeitleiste und liegt bis zur Entscheidung im Papierkorb. Freigeben holt es mit Alben, Bewertungen und Bearbeitungen zurück.')
    : t('{n} Fotos in die Fotokammer legen? Sie verschwinden aus der Zeitleiste und liegen bis zur Entscheidung im Papierkorb. Freigeben holt sie mit Alben, Bewertungen und Bearbeitungen zurück.', { n: g.length }))) return;
  try {
    const drin = new Set();
    const nicht = [];
    for (let i = 0; i < g.length; i += 8) {
      const r = await api('/api/v1/kammer/aufnehmen', { methode: 'POST', json: { ids: g.slice(i, i + 8).map((a) => a.id) } });
      for (const e of r.ergebnisse) {
        if (e.ausgang === 'kammer') drin.add(e.aufnahme);
        else nicht.push(e.ausgang === 'unbekannt' ? t('nicht in deiner Bibliothek oder schon im Papierkorb') : e.ausgang === 'gesperrt' ? t('im gesperrten Ordner') : (e.fehler || e.ausgang));
      }
    }
    liste.aufnahmen = liste.aufnahmen.filter((a) => !drin.has(a.id));
    zeitleiste.geladen = zeitleiste.geladen.filter((a) => !drin.has(a.id));
    auswahlAufheben();
    neuZeichnen();
    meldung([
      t('{n} in der Fotokammer', { n: drin.size }),
      ...(nicht.length ? [t('{n} nicht: {grund}', { n: nicht.length, grund: [...new Set(nicht)].join('; ') })] : []),
    ].join(' · '), nicht.length > 0 && drin.size === 0);
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
  // Mit `fremd` und `aktivitaet`: Ohne sie lud ein geteiltes Album nach
  // jedem Umsortieren seine Bilder aus der eigenen Bibliothek – und fand
  // keines.
  // Alles mit: Bisher fehlten `zeitleiste` und `alsListe`, und nach jedem
  // Favoriten oder Löschen verschwand die Ansichtsleiste.
  zeigeListe({ ...alt, neuGezeichnet: true }, $('raster-titel').hidden ? null : $('raster-titel').textContent);
}

// --- Betrachter ------------------------------------------------------------

let offen = -1;

// Die volle Auflösung (#256): Zeigt die Ansicht nur die Vorschau – bei
// HEIC, RAW und DNG 2048 Punkte –, kommt das Foto in Originalgrösse nach,
// sobald es da ist. Ob es mehr gibt, sagen die Masse aus der Liste; ein
// JPEG ist schon das Original und wird nicht zweimal geladen. Wie auf dem
// Handy (apps/mobil, vollesBild).
let vollLauf = 0;
function holeVoll(a) {
  const lauf = vollLauf;
  const bild = $('bild');
  bild.addEventListener('load', () => {
    if (lauf !== vollLauf) return;
    const lang = Math.max(a.breite || 0, a.hoehe || 0);
    if (Math.max(bild.naturalWidth, bild.naturalHeight) >= lang) return;
    // Die Vorschau reicht, solange das Fenster sie nicht vergrössert (#332).
    const dichte = window.devicePixelRatio || 1;
    if (Math.min(innerWidth * dichte / bild.naturalWidth, innerHeight * dichte / bild.naturalHeight) <= 1.02) return;
    // Erst nach kurzem Verweilen, wie in der Handy-App (#266): Wer mit den
    // Pfeiltasten durch HEIC oder RAW blättert, stiess sonst für jedes Foto
    // eine Wandlung am Server an.
    setTimeout(() => {
      if (lauf !== vollLauf) return;
      const voll = new Image();
      voll.onload = () => { if (lauf === vollLauf) bild.src = voll.src; };
      voll.src = aufnahmeUrl(a.id, 'voll', a.stand);
    }, 400);
  }, { once: true });
}

function oeffne(i) {
  if (!liste || i < 0 || i >= liste.aufnahmen.length) return;
  schwebeEnde();
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
  vollLauf++;
  if (a.art === 'video') {
    bild.hidden = true;
    video.hidden = false;
    spieleVideo(a.id);
  } else {
    video.hidden = true;
    bild.hidden = false;
    holeVoll(a);
    bild.src = aufnahmeUrl(a.id, 'ansicht', a.stand);
  }
  // Was die eigene Bibliothek ändert, fehlt in einem geteilten Album.
  const fremd = fremdeAufnahme(a);
  $('bearbeiten').hidden = a.art === 'video' || fremd;
  $('gesichter-knopf').hidden = a.art === 'video' || fremd;
  setzeAufziehen(false);
  $('aufziehen-knopf').hidden = a.art === 'video' || !gesichterAn || fremd;
  $('gesichtsmenue-knopf').hidden = a.art === 'video' || !gesichterAn || fremd;
  zeigeRahmen();
  const korb = !!liste.papierkorb;
  $('favorit').hidden = korb || fremd;
  // In einem geteilten Album nur bei eigenen Beiträgen (#290).
  $('weg').hidden = korb || (fremd && !a.eigene);
  $('weg').title = fremd ? t('Aus dem Album entfernen') : t('In den Papierkorb');
  $('weg').setAttribute('aria-label', $('weg').title);
  $('holen').hidden = !korb;
  $('teilen').hidden = !teilenMoeglich;
  $('live').hidden = !(a.art !== 'video' && a.partner);
  // Spielt dieser Browser kein HEVC, die Fassung des Bewegungsteils schon
  // jetzt anstossen – dann ist sie da, wenn man auf LIVE zeigt.
  if (a.art !== 'video' && a.partner && !kannHevc) fetch(fassungUrl(a.partner, true), { credentials: 'same-origin' }).catch(() => {});
  zeigeAktivitaetKnoepfe();
  ordneKnoepfe();
  blickZurueck(false);
  $('betrachter').classList.remove('still');
  $('betrachter').style.removeProperty('background');
  $('angaben').textContent = `${datumZeit.format(new Date(a.aufgenommen))} · ${a.name}${a.von ? ` · ${t('von {name}', { name: a.von })}` : ''}`;
  $('favorit').textContent = a.favorit ? '♥' : '♡';
  $('laden').href = aufnahmeUrl(a.id, 'original');
  $('laden').download = a.name || '';
  $('betrachter').hidden = false;
  zeigeAngaben();
  if (i >= liste.aufnahmen.length - 20) ladeMehr();
}

// --- Gesichter im Betrachter (#190) -------------------------------------------
//
// Wie am Rechner: Die erkannten Gesichter als Rahmen über dem Foto, jeder
// antippbar zum Benennen; und ein Gesicht, das die Erkennung übersehen hat,
// von Hand aufziehen. Angelegt wird es am Server – er hat das Original und
// das Modell; zurück kommt es wie jede Änderung.

let gesichterAn = false;
let aufziehen = false;
const rahmenflaeche = $('rahmenflaeche');

// Legt die Fläche genau über das gezeigte Bild.
function legeRahmenflaeche() {
  const b = $('bild');
  if (!gesichterAn || b.hidden || !b.naturalWidth) { rahmenflaeche.hidden = true; return; }
  rahmenflaeche.style.left = `${b.offsetLeft}px`;
  rahmenflaeche.style.top = `${b.offsetTop}px`;
  rahmenflaeche.style.width = `${b.offsetWidth}px`;
  rahmenflaeche.style.height = `${b.offsetHeight}px`;
  rahmenflaeche.style.transform = b.style.transform;
  rahmenflaeche.hidden = false;
}
$('bild').addEventListener('load', legeRahmenflaeche);
window.addEventListener('resize', legeRahmenflaeche);
// Zoom, Verschiebung und Wischen setzen die Verwandlung des Bildes – die
// Fläche übernimmt sie, wo immer sie gesetzt wird.
new MutationObserver(() => {
  rahmenflaeche.style.transform = $('bild').style.transform;
  rahmenflaeche.classList.toggle('gleitet', $('bild').classList.contains('gleitet'));
}).observe($('bild'), { attributes: true, attributeFilter: ['style', 'class'] });

async function zeigeRahmen() {
  rahmenflaeche.querySelectorAll('.rahmen').forEach((r) => r.remove());
  rahmenDaten = null;
  const a = liste && liste.aufnahmen[offen];
  if (!gesichterAn || !a || a.art === 'video' || fremdeAufnahme(a)) { legeRahmenflaeche(); return; }
  let d;
  try { d = await api(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/angaben?sprache=${SPRACHE}`); } catch (_) { return; }
  if (!liste || liste.aufnahmen[offen] !== a) return;
  rahmenDaten = { id: a.id, gesichter: d.gesichter || [], aus: !!d.gesichtssucheAus };
  for (const g of d.gesichter || []) {
    if (!g.kasten) continue;
    const [x, y, w, h] = g.kasten;
    const r = el('button', `rahmen${g.person ? ' benannt' : ''}${g.beiseite ? ' beiseite' : ''}`);
    r.type = 'button';
    r.style.left = `${x * 100}%`;
    r.style.top = `${y * 100}%`;
    r.style.width = `${w * 100}%`;
    r.style.height = `${h * 100}%`;
    const name = g.beiseite ? t('Beiseitegelegt') : g.person ? g.person.name : t('Wer ist das?');
    r.title = name;
    r.append(el('span', 'name', name));
    // Der Rahmen gehört nicht zum Wischen und Zoomen des Bildes.
    r.addEventListener('pointerdown', (e) => e.stopPropagation());
    r.addEventListener('click', (e) => {
      e.stopPropagation();
      oeffneGesichter({
        titel: g.person ? g.person.name : t('Wer ist das?'),
        gesichter: [{ ...g, aufnahme: undefined }],
        person: g.person,
        fertig: () => { zeigeRahmen(); if (angabenOffen) zeigeAngaben(); },
      });
    });
    rahmenflaeche.append(r);
  }
  legeRahmenflaeche();
  if (!d.gesichter || !d.gesichter.length) meldung(t('Auf diesem Foto ist kein Gesicht erkannt. Mit ⬚ lässt sich eines aufziehen.'));
}

function setzeAufziehen(an) {
  aufziehen = an;
  $('aufziehen-knopf').setAttribute('aria-pressed', String(an));
  rahmenflaeche.classList.toggle('ziehen', an);
}

// Was sich mit den Gesichtern dieses Fotos auf einmal tun lässt – wie das
// Menü der Gesichtsansicht am Rechner (#191, #192): die unbenannten
// ignorieren oder löschen, und das Foto von der Suche ausnehmen. Ein
// Foto, auf dem jeder Durchlauf neue „Gesichter“ findet – eine
// Gemäldewand, ein Plakat –, nimmt man aus; was erkannt ist, bleibt.
let rahmenDaten = null;

$('gesichtsmenue-knopf').addEventListener('click', () => {
  const a = liste && liste.aufnahmen[offen];
  const d = rahmenDaten;
  if (!a || !d || d.id !== a.id) return;
  const offene = d.gesichter.filter((g) => !g.person && !g.beiseite).map((g) => g.id);
  // Löschen trifft auch die beiseitegelegten, wie bei „Ohne Namen“.
  const unbenannte = d.gesichter.filter((g) => !g.person).map((g) => g.id);
  const fertig = () => { zeigeRahmen(); if (angabenOffen) zeigeAngaben(); };
  waehle(t('Gesichter auf diesem Foto'), [
    {
      text: offene.length === 0 ? t('Keine unbenannten Gesichter') : offene.length === 1 ? t('Unbenanntes Gesicht ignorieren') : t('{n} unbenannte Gesichter ignorieren', { n: offene.length }),
      an: offene.length > 0,
      aktion: async () => {
        await befehl('gesichterBeiseitelegen', { gesichtIds: offene, beiseite: true });
        fertig();
      },
    },
    {
      text: unbenannte.length === 0 ? t('Keine unbenannten Erkennungen') : unbenannte.length === 1 ? t('Unbenannte Erkennung löschen') : t('{n} unbenannte Erkennungen löschen', { n: unbenannte.length }),
      gefahr: true,
      an: unbenannte.length > 0,
      aktion: async () => {
        if (!confirm(unbenannte.length === 1 ? t('Die unbenannte Erkennung auf diesem Foto löschen? Benannte Gesichter bleiben.') : t('Die {n} unbenannten Erkennungen auf diesem Foto löschen? Benannte Gesichter bleiben.', { n: unbenannte.length }))) return;
        await befehl('gesichterLoeschen', { gesichtIds: unbenannte });
        fertig();
      },
    },
    {
      text: d.aus ? t('Wieder nach Gesichtern durchsuchen') : t('Nicht mehr nach Gesichtern durchsuchen'),
      hinweis: d.aus ? null : t('Für Bilder, auf denen jeder Durchlauf neue „Gesichter“ findet. Erkannte bleiben.'),
      aktion: async () => {
        const aus = !d.aus;
        await befehl('gesichtssucheAusnehmen', { id: a.id, ausgenommen: aus });
        d.aus = aus;
        meldung(aus ? t('Dieses Foto wird beim erneuten Durchsuchen übersprungen. Erkannte Gesichter bleiben.') : t('Dieses Foto wird wieder mitdurchsucht.'));
      },
    },
  ]);
});

$('gesichter-knopf').addEventListener('click', () => {
  gesichterAn = !gesichterAn;
  $('gesichter-knopf').setAttribute('aria-pressed', String(gesichterAn));
  $('aufziehen-knopf').hidden = !gesichterAn;
  $('gesichtsmenue-knopf').hidden = !gesichterAn;
  if (!gesichterAn) setzeAufziehen(false);
  ordneKnoepfe();
  zeigeRahmen();
});
$('aufziehen-knopf').addEventListener('click', () => {
  setzeAufziehen(!aufziehen);
  if (aufziehen) meldung(t('Einen Rahmen um das Gesicht ziehen.'));
});

let zug = null;
rahmenflaeche.addEventListener('pointerdown', (e) => {
  if (!aufziehen || e.button > 0) return;
  e.stopPropagation();
  e.preventDefault();
  const r = rahmenflaeche.getBoundingClientRect();
  const neu = el('div', 'neu');
  rahmenflaeche.append(neu);
  zug = { r, x0: (e.clientX - r.left) / r.width, y0: (e.clientY - r.top) / r.height, neu, x1: 0, y1: 0 };
  try { rahmenflaeche.setPointerCapture(e.pointerId); } catch (_) { /* egal */ }
});
rahmenflaeche.addEventListener('pointermove', (e) => {
  if (!zug) return;
  e.stopPropagation();
  const k = (v) => Math.min(1, Math.max(0, v));
  zug.x1 = k((e.clientX - zug.r.left) / zug.r.width);
  zug.y1 = k((e.clientY - zug.r.top) / zug.r.height);
  const x = Math.min(zug.x0, zug.x1), y = Math.min(zug.y0, zug.y1);
  Object.assign(zug.neu.style, { left: `${x * 100}%`, top: `${y * 100}%`, width: `${Math.abs(zug.x1 - zug.x0) * 100}%`, height: `${Math.abs(zug.y1 - zug.y0) * 100}%` });
});
async function zugEnde(e) {
  if (!zug) return;
  e.stopPropagation();
  const z = zug;
  zug = null;
  z.neu.remove();
  const kasten = [Math.min(z.x0, z.x1), Math.min(z.y0, z.y1), Math.abs(z.x1 - z.x0), Math.abs(z.y1 - z.y0)];
  if (kasten[2] < 0.01 || kasten[3] < 0.01) { meldung(t('Der Rahmen ist zu klein – bitte um das ganze Gesicht ziehen.')); return; }
  const a = liste && liste.aufnahmen[offen];
  if (!a) return;
  setzeAufziehen(false);
  try {
    const d = await api(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/gesichter`, { methode: 'POST', json: { kasten } });
    await zeigeRahmen();
    // Gleich benennen – wie am Rechner, wo die Person zuerst gefragt wird.
    oeffneGesichter({
      titel: t('Wer ist das?'),
      gesichter: [d.gesicht],
      fertig: () => { zeigeRahmen(); if (angabenOffen) zeigeAngaben(); },
    });
  } catch (x) { meldung(x.message); }
}
rahmenflaeche.addEventListener('pointerup', zugEnde);
rahmenflaeche.addEventListener('pointercancel', (e) => { if (zug) { zug.neu.remove(); zug = null; } e.stopPropagation(); });

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
const fassungUrl = (id, pruefen) => `${aufnahmeUrl(id, 'abspielbar')}${pruefen ? '?pruefen=1' : ''}`;

function videoHinweis(text) {
  $('video-hinweis').textContent = text || '';
  $('video-hinweis').hidden = !text;
}

function spieleVideo(id, { live = false } = {}) {
  const video = $('video');
  const lauf = videoLauf;
  const original = aufnahmeUrl(id, 'wiedergabe');
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
const belichtung = (s) => (s >= 1 ? `${s} s` : `1/${Math.round(1 / s)} s`);

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

// Ein Schlagwort umbenennen (#273) – an allen Fotos zugleich, wie am Rechner
// und auf dem Handy. Die Kennung bleibt; einen vergebenen Namen lehnt der
// Server ab (409).
async function schlagwortUmbenennen(w) {
  const name = (prompt(t('Neuer Name für „{name}“ – gilt für alle Fotos mit diesem Schlagwort.', { name: w.name }), w.name) || '').trim();
  if (!name || name === w.name) return;
  try {
    await befehl('schlagwortUmbenennen', { schlagwortId: w.id, name });
  } catch (x) {
    alert(x.status === 409 ? t('Ein Schlagwort „{name}“ gibt es schon.', { name }) : x.message);
    return;
  }
  zeigeAngaben();
}

async function zeigeAngaben() {
  const a = liste && liste.aufnahmen[offen];
  const feld = $('angaben-feld');
  if (!a || !angabenOffen) return;
  // Kommentare zu diesem Foto, wenn das Album geteilt ist (#297).
  const kommentare = liste.aktivitaet ? [el('h3', null, t('Kommentare')), kommentarBereich(a.id)] : [];
  if (fremdeAufnahme(a)) {
    // Ein geteiltes Album: nur, was die Liste weiss – die Angaben der
    // Bibliothek gehören dem Besitzer.
    feld.replaceChildren(
      ...kommentare,
      el('h3', null, t('Angaben')),
      el('p', '', datumZeit.format(new Date(a.aufgenommen))),
      el('p', 'leise', a.name || ''),
      ...(a.breite && a.hoehe ? [el('p', 'leise', `${a.breite} × ${a.hoehe}`)] : []),
      ...(a.von ? [el('p', 'leise', a.konto ? t('Aus der Bibliothek von {name}', { name: a.von }) : t('Beigetragen von {name}', { name: a.von }))] : []),
    );
    return;
  }
  feld.replaceChildren(el('p', 'neben', t('Lade …')));
  let d;
  try { d = await api(`/api/v1/aufnahmen/${encodeURIComponent(a.id)}/angaben?sprache=${SPRACHE}`); } catch (x) { feld.replaceChildren(el('p', 'fehler', x.message)); return; }
  if (!liste || liste.aufnahmen[offen] !== a) return; // inzwischen weitergeblättert
  const teile = [...kommentare];
  teile.push(el('h3', null, t('Angaben')));
  const datumsreihe = reihe('📅', datumZeit.format(new Date(d.aufgenommen)), d.datumGeschaetzt ? t('Datum geschätzt') : null);
  if (d.datumsvorschlag) datumsreihe.querySelector('.inhalt').append(datumsvorschlagHinweis(a, d.datumsvorschlag));
  teile.push(datumsreihe);
  const datei = [d.breite && d.hoehe ? `${d.breite} × ${d.hoehe}` : '', d.bytes ? groesse(d.bytes) : '', d.format ? d.format.toUpperCase() : '', d.dauer ? `${Math.round(d.dauer)} s` : '', d.bearbeitet ? t('bearbeitet') : ''].filter(Boolean).join(' · ');
  teile.push(reihe('🖼', d.name, datei));
  const k = d.kamera;
  if (k.modell || k.hersteller) {
    const modell = k.modell && k.hersteller && k.modell.toLowerCase().startsWith(k.hersteller.toLowerCase()) ? k.modell : [k.hersteller, k.modell].filter(Boolean).join(' ');
    const werte = [k.brennweite ? `${k.brennweite} mm` : '', k.blende ? `f/${k.blende}` : '', k.belichtung ? belichtung(k.belichtung) : '', k.iso ? `ISO ${k.iso}` : ''].filter(Boolean).join(' · ');
    teile.push(reihe('📷', modell, [k.objektiv, werte].filter(Boolean).join('\n')));
  }
  const ortKnopf = el('button', 'marke', d.ort ? t('Ort ändern') : t('Ort setzen'));
  ortKnopf.type = 'button';
  ortKnopf.addEventListener('click', () => ortDialog([a], Boolean(d.ort), zeigeAngaben));
  if (d.ort) {
    const name = [d.ort.stadt, d.ort.region, land(d.ort.land)].filter(Boolean).join(', ');
    const r = reihe('📍', name || t('Standort bekannt'), `${d.ort.breite.toFixed(5)}, ${d.ort.laenge.toFixed(5)}${d.ort.geerbt ? ` · ${t('vom Nachbarfoto übernommen')}` : ''}`);
    r.querySelector('.inhalt').append(ortKnopf);
    teile.push(r);
  } else {
    teile.push(reihe('📍', ortKnopf));
  }
  if (d.personen.length) teile.push(reihe('👤', verweise(d.personen, '#/personen')));
  if (d.gesichter && d.gesichter.length) teile.push(reihe('🙂', gesichterReihe(d.gesichter), t('Antippen, um zu benennen oder zu ändern')));
  if (d.schlagwoerter.length) {
    const box = el('div');
    for (const w of d.schlagwoerter) {
      const knopf = el('button', 'marke', w.name);
      knopf.type = 'button';
      knopf.title = t('Umbenennen – gilt für alle Fotos mit diesem Schlagwort');
      knopf.addEventListener('click', () => schlagwortUmbenennen(w));
      box.append(knopf);
    }
    teile.push(reihe('🏷', box));
  }
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
    const v = el('a', null, istVarianten(d.serie.id)
      ? t('{n} Varianten dieser Aufnahme', { n: d.serie.groesse })
      : t('Serie mit {n} Aufnahmen', { n: d.serie.groesse }));
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
  // Am Telefon in Reihen: In einer lagen sie sonst unter dem Schliessen-Knopf,
  // und der Tipp auf × traf den Papierkorb.
  const spalten = innerWidth <= 520 ? Math.max(1, Math.floor((innerWidth - 62) / 44)) : 99;
  let i = 0;
  for (const id of ['favorit', 'gefaellt', 'kommentare-knopf', 'laden', 'teilen', 'info', 'gesichter-knopf', 'aufziehen-knopf', 'gesichtsmenue-knopf', 'bearbeiten', 'diashow-knopf', 'weg', 'holen', 'live']) {
    if ($(id).hidden) continue;
    $(id).style.setProperty('--platz', String(i % spalten));
    $(id).style.setProperty('--reihe', String(Math.floor(i / spalten)));
    i++;
  }
}
window.addEventListener('resize', () => { if (offen >= 0) ordneKnoepfe(); });

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
  if (a && a.konto) return;
  if (a && fremdeListe()) { await entferneBeitrag(a); return; }
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
    erneuereMarken(offen);
  } catch (x) { $('angaben').textContent = x.message; }
});

// --- Diashow (Issue #170) -----------------------------------------------------
//
// Wie am Rechner: Fotos nacheinander, vier Sekunden je Bild, mit
// Überblendung und einem langsamen Zoom; Videos bleiben draussen. Zwei
// Bilder liegen übereinander – das neue wird erst gezeigt, wenn es
// dekodiert ist, sonst blitzte zwischen zwei Fotos Schwarz auf.

const DIA_TAKT = 4000;
const dia = { fotos: [], i: 0, laeuft: true, takt: null, oben: 0, lauf: 0, wachbleiben: null, ausBetrachter: false };

function starteDiashow(aufnahmen, ab = 0) {
  const start = aufnahmen[ab];
  dia.fotos = aufnahmen.filter((a) => a.art !== 'video');
  if (!dia.fotos.length) { meldung(t('Hier sind keine Fotos für eine Diashow – Videos bleiben draussen.')); return; }
  const i = start ? dia.fotos.indexOf(start) : -1;
  dia.i = i >= 0 ? i : Math.max(0, dia.fotos.findIndex((a) => aufnahmen.indexOf(a) >= ab));
  dia.laeuft = true;
  dia.ausBetrachter = offen >= 0;
  for (const b of $('diashow').querySelectorAll('.dia')) { b.classList.remove('sichtbar'); b.removeAttribute('src'); }
  $('diashow').hidden = false;
  $('dia-pause').textContent = '❚❚';
  // Vollbild und wach bleiben, wo der Browser es erlaubt.
  $('diashow').requestFullscreen?.().catch(() => {});
  navigator.wakeLock?.request('screen').then((w) => { dia.wachbleiben = w; }).catch(() => {});
  zeigeDia(dia.i);
}

function diaUrl(a) { return aufnahmeUrl(a.id, 'ansicht', a.stand); }

// Geladen und möglichst dekodiert. decode() hängt in manchen Lagen (etwa
// wenn die Seite im Hintergrund nicht zeichnet) – deshalb mit Frist.
async function diaGeladen(img) {
  if (!img.complete) {
    await new Promise((fertig) => {
      img.addEventListener('load', fertig, { once: true });
      img.addEventListener('error', fertig, { once: true });
    });
  }
  await Promise.race([img.decode().catch(() => {}), new Promise((fertig) => setTimeout(fertig, 400))]);
}

async function zeigeDia(i) {
  clearTimeout(dia.takt);
  const n = dia.fotos.length;
  dia.i = ((i % n) + n) % n;
  const meinLauf = ++dia.lauf;
  const a = dia.fotos[dia.i];
  const bilder = $('diashow').querySelectorAll('.dia');
  const neu = bilder[1 - dia.oben], alt = bilder[dia.oben];
  neu.src = diaUrl(a);
  await diaGeladen(neu);
  if (meinLauf !== dia.lauf || $('diashow').hidden) return;
  // Der Zoom beginnt bei jedem Bild neu, abwechselnd in eine andere Ecke.
  neu.classList.remove('sichtbar', 'links', 'rechts');
  void neu.offsetWidth;
  neu.classList.add('sichtbar', dia.i % 2 ? 'links' : 'rechts');
  alt.classList.remove('sichtbar');
  dia.oben = 1 - dia.oben;
  $('dia-stand').textContent = `${dia.i + 1} / ${n}`;
  // Das nächste schon laden.
  const weiter = dia.fotos[(dia.i + 1) % n];
  if (weiter) { const v = new Image(); v.src = diaUrl(weiter); }
  if (dia.laeuft) dia.takt = setTimeout(() => zeigeDia(dia.i + 1), DIA_TAKT);
}

function diaPause(an = !dia.laeuft) {
  dia.laeuft = an;
  $('dia-pause').textContent = an ? '❚❚' : '▶';
  $('dia-pause').setAttribute('aria-label', an ? t('Anhalten') : t('Weiter'));
  clearTimeout(dia.takt);
  if (an) dia.takt = setTimeout(() => zeigeDia(dia.i + 1), DIA_TAKT);
}

function beendeDiashow() {
  clearTimeout(dia.takt);
  dia.lauf++;
  $('diashow').hidden = true;
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  dia.wachbleiben?.release().catch(() => {});
  dia.wachbleiben = null;
  // Kam sie aus dem Betrachter, steht er danach beim zuletzt gezeigten Foto.
  const a = dia.fotos[dia.i];
  if (dia.ausBetrachter && liste && a) {
    const j = liste.aufnahmen.indexOf(a);
    if (j >= 0) oeffne(j);
  }
}

// --- Diashow als Video (#281) -------------------------------------------------
//
// Wie am Rechner (lib/services/diashow.dart): eine Titelkarte, dann jedes
// Foto 3,5 Sekunden mit langsamem Zoom und Schwenk, dazwischen 0,8 Sekunden
// Überblendung, höchstens 40 Fotos, Full HD. Die Zeitrechnung und das
// Malen sind dieselben Formeln. Aufgenommen wird, was ein Canvas in
// Echtzeit zeigt (MediaRecorder): MP4, wo der Browser es schreibt
// (Safari, neuere Chrome), sonst WebM. Musik von der Platte läuft
// wiederholt darunter und wird am Ende ausgeblendet – wie dort.

// nachlauf: So lange steht das letzte Bild noch, ehe die Aufnahme endet.
// MediaRecorder verwirft beim Anhalten, was er noch nicht kodiert hat –
// gemessen fehlten vom letzten Foto sonst 1,8 Sekunden.
const DIAVIDEO = { breite: 1920, hoehe: 1080, jeBild: 3500, ueberblendung: 800, titel: 2500, hoechstens: 40, bilderJeSekunde: 30, nachlauf: 2000 };

function diavideoTakt(ms, anzahl) {
  const { jeBild, ueberblendung, titel } = DIAVIDEO;
  if (ms < titel || anzahl === 0) {
    const rest = titel - ms;
    const ein = anzahl === 0 || rest > ueberblendung ? 0 : 1 - rest / ueberblendung;
    return { titel: true, index: 0, naechster: ein > 0 ? 0 : null, ueberblendung: ein, fortschritt: 0 };
  }
  const imFoto = ms - titel;
  const index = Math.min(Math.floor(imFoto / jeBild), anzahl - 1);
  const inDiesem = imFoto - jeBild * index;
  const fortschritt = Math.min(1, Math.max(0, inDiesem / jeBild));
  const bisEnde = jeBild - inDiesem;
  if (index !== anzahl - 1 && bisEnde < ueberblendung) {
    return { titel: false, index, naechster: index + 1, ueberblendung: 1 - bisEnde / ueberblendung, fortschritt };
  }
  return { titel: false, index, naechster: null, ueberblendung: 0, fortschritt };
}

// Bildfüllend, gerade und ungerade Fotos in entgegengesetzter Richtung.
function maleDiavideoFoto(c, bild, index, fortschritt, deckkraft = 1) {
  const W = c.canvas.width, H = c.canvas.height;
  const b = bild.width, h = bild.height;
  const deckend = Math.max(W / b, H / h);
  const zoom = 1 + 0.08 * (index % 2 === 0 ? fortschritt : 1 - fortschritt);
  const massstab = deckend * zoom;
  const aw = W / massstab, ah = H / massstab;
  const richtung = index % 2 === 0 ? fortschritt : 1 - fortschritt;
  c.globalAlpha = deckkraft;
  c.imageSmoothingQuality = 'high';
  c.drawImage(bild, (b - aw) * (0.3 + 0.4 * richtung), (h - ah) * 0.5, aw, ah, 0, 0, W, H);
  c.globalAlpha = 1;
}

function maleDiavideoTitel(c, titel, untertitel) {
  const W = c.canvas.width, H = c.canvas.height;
  c.fillStyle = '#141414';
  c.fillRect(0, 0, W, H);
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  c.fillStyle = '#f5f0e6';
  c.font = `${Math.round(H * 0.075)}px Zierschrift, Georgia, serif`;
  const mitte = untertitel ? H / 2 - H * 0.03 : H / 2;
  c.fillText(titel, W / 2, mitte, W * 0.8);
  if (untertitel) {
    c.fillStyle = 'rgba(245, 240, 230, 0.7)';
    c.font = `${Math.round(H * 0.035)}px Zierschrift, Georgia, serif`;
    c.fillText(untertitel, W / 2, mitte + H * 0.075, W * 0.8);
  }
}

// So gross, dass es das Video füllt – nicht grösser, wie am Rechner.
async function ladeDiavideoBild(a) {
  try {
    const blob = await (await fetch(aufnahmeUrl(a.id, 'ansicht', a.stand), { credentials: 'same-origin' })).blob();
    const roh = await createImageBitmap(blob);
    const m = Math.max(DIAVIDEO.breite / roh.width, DIAVIDEO.hoehe / roh.height) * 1.1;
    if (m >= 1) return roh;
    const klein = await createImageBitmap(roh, { resizeWidth: Math.round(roh.width * m), resizeHeight: Math.round(roh.height * m), resizeQuality: 'high' });
    roh.close();
    return klein;
  } catch (_) {
    return null; // steht als schwarzes Bild da und nimmt das Video nicht mit
  }
}

const DIAVIDEO_FORMATE = ['video/mp4;codecs=avc1.640028,mp4a.40.2', 'video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm'];

const diavideo = { abbruch: false, laeuft: false };

async function schreibeDiavideo({ fotos, titel, untertitel, musik, fortschritt }) {
  const format = DIAVIDEO_FORMATE.find((f) => window.MediaRecorder && MediaRecorder.isTypeSupported(f));
  if (!format) throw new Error(t('Dieser Browser kann kein Video aufnehmen.'));
  await document.fonts?.load(`20px Zierschrift`).catch(() => {});
  const leinwand = document.createElement('canvas');
  leinwand.width = DIAVIDEO.breite;
  leinwand.height = DIAVIDEO.hoehe;
  const c = leinwand.getContext('2d');
  const strom = leinwand.captureStream(DIAVIDEO.bilderJeSekunde);
  const dauer = DIAVIDEO.titel + DIAVIDEO.jeBild * fotos.length;
  let ton = null;
  if (musik) {
    const ac = new AudioContext();
    const puffer = await ac.decodeAudioData(await musik.arrayBuffer());
    const quelle = ac.createBufferSource();
    quelle.buffer = puffer;
    quelle.loop = true;
    const lautstaerke = ac.createGain();
    const ziel = ac.createMediaStreamDestination();
    quelle.connect(lautstaerke).connect(ziel);
    for (const spur of ziel.stream.getAudioTracks()) strom.addTrack(spur);
    ton = { ac, quelle, lautstaerke };
  }
  const geladen = new Map();
  const lade = (i) => {
    if (i < fotos.length && !geladen.has(i)) geladen.set(i, ladeDiavideoBild(fotos[i]).then((b) => { geladen.set(i, b); return b; }));
  };
  lade(0); lade(1);
  await Promise.all([geladen.get(0), geladen.get(1)]);
  const aufnahme = new MediaRecorder(strom, { mimeType: format, videoBitsPerSecond: 12000000 });
  const stuecke = [];
  aufnahme.ondataavailable = (e) => { if (e.data && e.data.size) stuecke.push(e.data); };
  const fertig = new Promise((ok) => { aufnahme.onstop = ok; });
  aufnahme.start(1000);
  if (ton) {
    const jetzt = ton.ac.currentTime;
    ton.quelle.start();
    ton.lautstaerke.gain.setValueAtTime(1, jetzt + Math.max(0, dauer / 1000 - 2));
    ton.lautstaerke.gain.linearRampToValueAtTime(0, jetzt + dauer / 1000);
  }
  // Ist die Seite verborgen, zeichnet der Browser nichts – die Aufnahme
  // liefe mit einem stehenden Bild weiter. Dann halten Aufnahme, Uhr und
  // Musik an und gehen danach dort weiter, wo sie waren.
  let anfang = performance.now();
  let verborgenSeit = null;
  const sichtbarkeit = () => {
    if (document.hidden && verborgenSeit === null) {
      verborgenSeit = performance.now();
      if (aufnahme.state === 'recording') aufnahme.pause();
      ton?.ac.suspend();
    } else if (!document.hidden && verborgenSeit !== null) {
      anfang += performance.now() - verborgenSeit;
      verborgenSeit = null;
      if (aufnahme.state === 'paused') aufnahme.resume();
      ton?.ac.resume();
    }
  };
  document.addEventListener('visibilitychange', sichtbarkeit);
  await new Promise((ende) => {
    const bild = () => {
      if (verborgenSeit !== null) { requestAnimationFrame(bild); return; }
      const jetzt = performance.now() - anfang;
      if (diavideo.abbruch || jetzt >= dauer + DIAVIDEO.nachlauf) { ende(); return; }
      const ms = Math.min(jetzt, dauer - 1);
      const takt = diavideoTakt(ms, fotos.length);
      // Vorausladen, was gleich kommt, und freigeben, was vorbei ist.
      lade(takt.index + 1); lade(takt.index + 2);
      for (const [i, b] of geladen) {
        if (i < takt.index - 1 && b && !(b instanceof Promise)) { b.close(); geladen.delete(i); }
      }
      c.fillStyle = '#000';
      c.fillRect(0, 0, leinwand.width, leinwand.height);
      const zeige = (i, f, d) => { const b = geladen.get(i); if (b && !(b instanceof Promise)) maleDiavideoFoto(c, b, i, f, d); };
      if (takt.titel) maleDiavideoTitel(c, titel, untertitel);
      else zeige(takt.index, takt.fortschritt, 1);
      if (takt.naechster !== null) zeige(takt.naechster, 0, takt.ueberblendung);
      fortschritt(jetzt / (dauer + DIAVIDEO.nachlauf), leinwand);
      requestAnimationFrame(bild);
    };
    requestAnimationFrame(bild);
  });
  document.removeEventListener('visibilitychange', sichtbarkeit);
  aufnahme.stop();
  await fertig;
  ton?.quelle.stop();
  ton?.ac.close();
  for (const b of geladen.values()) if (b && !(b instanceof Promise)) b.close();
  if (diavideo.abbruch) return null;
  return { blob: new Blob(stuecke, { type: format.split(';')[0] }), endung: format.startsWith('video/mp4') ? 'mp4' : 'webm' };
}

function oeffneDiavideo() {
  const fotos = dia.fotos.slice(0, DIAVIDEO.hoechstens);
  if (!fotos.length) return;
  diaPause(false);
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  const f = $('form-diavideo');
  f.titel.value = ($('raster-titel').hidden ? '' : $('raster-titel').textContent) || t('Diashow');
  f.untertitel.value = '';
  f.musik.value = '';
  $('diavideo-umfang').textContent = dia.fotos.length > DIAVIDEO.hoechstens
    ? t('Die ersten {n} von {m} Fotos, gut {s} Sekunden.', { n: fotos.length, m: dia.fotos.length, s: Math.round((DIAVIDEO.titel + DIAVIDEO.jeBild * fotos.length) / 1000) })
    : t('{n} Fotos, gut {s} Sekunden.', { n: fotos.length, s: Math.round((DIAVIDEO.titel + DIAVIDEO.jeBild * fotos.length) / 1000) });
  $('diavideo-meldung').textContent = '';
  $('diavideo-bild').hidden = true;
  $('diavideo-los').disabled = false;
  $('diavideo-dialog').showModal();
}

$('dia-video').addEventListener('click', oeffneDiavideo);
$('diavideo-abbrechen').addEventListener('click', () => {
  if (diavideo.laeuft) diavideo.abbruch = true;
  else $('diavideo-dialog').close();
});
$('form-diavideo').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (diavideo.laeuft) return;
  const f = e.target;
  const vorschau = $('diavideo-bild');
  const vc = vorschau.getContext('2d');
  diavideo.laeuft = true;
  diavideo.abbruch = false;
  $('diavideo-los').disabled = true;
  vorschau.hidden = false;
  try {
    const ergebnis = await schreibeDiavideo({
      fotos: dia.fotos.slice(0, DIAVIDEO.hoechstens),
      titel: f.titel.value.trim() || t('Diashow'),
      untertitel: f.untertitel.value.trim() || null,
      musik: f.musik.files[0] || null,
      fortschritt: (anteil, leinwand) => {
        $('diavideo-meldung').textContent = t('Video wird erstellt … {p} %', { p: Math.floor(anteil * 100) });
        vc.drawImage(leinwand, 0, 0, vorschau.width, vorschau.height);
      },
    });
    if (ergebnis) {
      const a = el('a');
      a.href = URL.createObjectURL(ergebnis.blob);
      a.download = `${(f.titel.value.trim() || t('Diashow')).replace(/[\\/:*?"<>|]+/g, '-')}.${ergebnis.endung}`;
      document.body.append(a);
      a.click();
      a.remove();
      setTimeout(() => URL.revokeObjectURL(a.href), 60000);
      $('diavideo-dialog').close();
      meldung(t('Video gespeichert.'));
    } else {
      $('diavideo-meldung').textContent = t('Abgebrochen.');
    }
  } catch (x) {
    $('diavideo-meldung').textContent = x.message;
  } finally {
    diavideo.laeuft = false;
    $('diavideo-los').disabled = false;
  }
});

$('dia-zu').addEventListener('click', beendeDiashow);
$('dia-pause').addEventListener('click', () => diaPause());
$('dia-vor').addEventListener('click', () => zeigeDia(dia.i + 1));
$('dia-zurueck').addEventListener('click', () => zeigeDia(dia.i - 1));
// Die Leiste verschwindet, solange niemand die Maus bewegt.
let diaRuhe = null;
$('diashow').addEventListener('pointermove', () => {
  $('diashow').classList.add('mit-leiste');
  clearTimeout(diaRuhe);
  diaRuhe = setTimeout(() => $('diashow').classList.remove('mit-leiste'), 2500);
});
$('diashow').addEventListener('click', (e) => {
  if (e.target.closest('#dia-leiste')) return;
  $('diashow').classList.toggle('mit-leiste');
});
document.addEventListener('fullscreenchange', () => {
  // Wer das Vollbild mit Esc verlässt, will meist ganz hinaus.
  if (!document.fullscreenElement && !$('diashow').hidden && dia.verliess) beendeDiashow();
  dia.verliess = !!document.fullscreenElement;
});
$('diashow-knopf').addEventListener('click', () => { if (liste && offen >= 0) starteDiashow(liste.aufnahmen, offen); });
$('auswahl-diashow').addEventListener('click', () => { const g = gewaehlte(); if (g.length) { starteDiashow(g, 0); } });

// --- Tastenkürzel (Issue #169) ------------------------------------------------
//
// Dieselben Tasten wie am Rechner (tastenkuerzel.dart): Im Raster wandert
// ein Rahmen mit den Pfeiltasten, Umschalt zieht die Auswahl mit, ⏎
// öffnet. F, 0–5 (Sterne), 6–9 (Farbe) und Entf wirken auf die Auswahl –
// gibt es keine, auf die Kachel im Rahmen. Im Betrachter dasselbe für das
// gezeigte Foto, dazu I für die Angaben und die Leertaste fürs nächste.

let rahmen = -1;
let rahmenAnker = -1;

const FARBTASTEN = { 6: 'red', 7: 'yellow', 8: 'green', 9: 'blue' };

function setzeRahmen(i, sichtbar = true) {
  if (!liste || !liste.kacheln || !liste.kacheln.length) { rahmen = -1; return; }
  const alt = liste.kacheln[rahmen];
  if (alt) alt.classList.remove('rahmen');
  rahmen = Math.max(0, Math.min(liste.kacheln.length - 1, i));
  if (!sichtbar) return;
  const k = liste.kacheln[rahmen];
  k.classList.add('rahmen');
  k.scrollIntoView({ block: 'nearest' });
}

function waehleBereich(von, bis) {
  if (fremdeListe()) return;
  const [a0, a1] = von < bis ? [von, bis] : [bis, von];
  for (let i = a0; i <= a1; i++) if (!liste.aufnahmen[i].konto) auswahl.add(liste.aufnahmen[i].id);
  zeichneAuswahl(a0, a1);
}

// Die Kachel eine Reihe höher oder tiefer, möglichst an derselben Stelle –
// die Reihen sind wegen der Tagesköpfe nicht gleich lang.
function reiheWeiter(i, richtung) {
  const k = liste.kacheln;
  const hier = k[i];
  let j = i;
  while (j >= 0 && j < k.length && k[j].offsetTop === hier.offsetTop) j += richtung;
  if (j < 0 || j >= k.length) return i;
  const oben = k[j].offsetTop;
  let bester = j;
  for (let m = j; m >= 0 && m < k.length && k[m].offsetTop === oben; m += richtung) {
    if (Math.abs(k[m].offsetLeft - hier.offsetLeft) < Math.abs(k[bester].offsetLeft - hier.offsetLeft)) bester = m;
  }
  return bester;
}

// Worauf eine Taste wirkt: die Auswahl, sonst die Kachel im Rahmen.
function tastenziele() {
  if (!liste) return [];
  if (auswahl.size) return gewaehlte();
  const a = liste.aufnahmen[rahmen];
  // An Fotos eines Partners (#299) lässt sich nichts ändern.
  return a && !a.konto && rahmen >= 0 && liste.kacheln[rahmen]?.classList.contains('rahmen') ? [a] : [];
}

function erneuereMarken(i) {
  const k = liste && liste.kacheln && liste.kacheln[i];
  if (!k) return;
  if (k.classList.contains('zeile')) {
    k.querySelectorAll(':scope > .zelle, :scope > .weitere').forEach((x) => x.remove());
    zeilenzellen(k, liste.aufnahmen[i]);
    return;
  }
  k.querySelectorAll(':scope > .zeichen, :scope > .schild, :scope > .unten-rechts').forEach((x) => x.remove());
  marken(k, liste.aufnahmen[i]);
}

function erneuereMarkenVon(ziele) {
  const ids = new Set(ziele.map((a) => a.id));
  liste.aufnahmen.forEach((a, i) => { if (ids.has(a.id)) erneuereMarken(i); });
}

// Ort von Hand, wie im Infoblatt am Rechner. Das Ortsverzeichnis liegt auf
// dem Server; die Namen gehen mit dem Befehl auf alle Geräte.
let ortAuftrag = null;
let ortUhr = null;
let ortAnfrage = 0;
function ortDialog(ziele, hatOrt, fertig) {
  const f = $('form-ort');
  f.reset();
  ortAuftrag = { ziele, fertig };
  $('ort-titel').textContent = ziele.length > 1 ? t('Ort für {n} Aufnahmen setzen', { n: ziele.length }) : t('Ort setzen');
  $('ort-vorschlaege').replaceChildren();
  $('ort-meldung').textContent = '';
  $('ort-entfernen').hidden = !hatOrt;
  $('ort-dialog').showModal();
  f.ort.focus();
}
async function ortSende(werte, text) {
  const { ziele, fertig } = ortAuftrag;
  try {
    await befehl('ortSetzen', { ids: ziele.map((a) => a.id), ...werte });
    $('ort-dialog').close();
    meldung(text);
    if (fertig) await fertig();
  } catch (x) { $('ort-meldung').textContent = x.message; }
}
async function ortSuche() {
  const text = $('form-ort').ort.value.trim();
  const nummer = ++ortAnfrage;
  const feld = $('ort-vorschlaege');
  if (text.length < 2) { feld.replaceChildren(); $('ort-meldung').textContent = ''; return; }
  let d;
  try { d = await api(`/api/v1/orte/suche?text=${encodeURIComponent(text)}`); } catch (x) {
    if (nummer === ortAnfrage) $('ort-meldung').textContent = x.message;
    return;
  }
  if (nummer !== ortAnfrage) return; // inzwischen weitergetippt
  $('ort-meldung').textContent = !d.verzeichnis ? t('Auf dem Server liegt kein Ortsverzeichnis.') : d.treffer.length ? '' : t('Kein Ort gefunden.');
  feld.replaceChildren(...d.treffer.map((o) => {
    const b = el('button');
    b.type = 'button';
    b.append(el('span', 'haupt', o.name), el('span', 'neben', o.herkunft));
    b.addEventListener('click', () => ortSende(
      { breite: o.breite, laenge: o.laenge, land: o.land, region: o.region, stadt: o.stadt },
      t('Ort gesetzt: {name}', { name: o.herkunft ? `${o.name}, ${o.herkunft}` : o.name }),
    ));
    return b;
  }));
}
$('form-ort').ort.addEventListener('input', () => { clearTimeout(ortUhr); ortUhr = setTimeout(ortSuche, 150); });
$('form-ort').addEventListener('submit', (e) => {
  // Enter nimmt den ersten Vorschlag, wie der Knopf daneben am Rechner.
  e.preventDefault();
  const erster = $('ort-vorschlaege').querySelector('button');
  if (erster) erster.click();
});
$('ort-abbrechen').addEventListener('click', () => $('ort-dialog').close());
$('ort-entfernen').addEventListener('click', () => ortSende({ breite: null, laenge: null }, t('Ort entfernt')));
$('auswahl-ort').addEventListener('click', () => {
  const g = gewaehlte().filter((a) => !fremdeAufnahme(a));
  if (g.length) ortDialog(g, false, auswahlAufheben);
});

async function setzeFavorit(ziele) {
  if (!ziele.length) return;
  const alle = ziele.every((a) => a.favorit);
  await befehl('favoritSetzen', { ids: ziele.map((a) => a.id), favorit: !alle });
  for (const a of ziele) a.favorit = !alle;
  erneuereMarkenVon(ziele);
  if (offen >= 0) $('favorit').textContent = liste.aufnahmen[offen].favorit ? '♥' : '♡';
  meldung(alle ? t('Kein Favorit mehr') : t('Favorit'));
}

async function setzeSterne(ziele, n) {
  if (!ziele.length) return;
  await befehl('bewertungSetzen', { ids: ziele.map((a) => a.id), bewertung: n });
  for (const a of ziele) a.bewertung = n || undefined;
  meldung(n ? '★'.repeat(n) : t('Ohne Sterne'));
  if (offen >= 0 && angabenOffen) zeigeAngaben();
}

async function setzeFarbe(ziele, farbe) {
  if (!ziele.length) return;
  // Dieselbe Farbe noch einmal nimmt sie weg – wie am Rechner.
  const neu = ziele[0].farbe === farbe ? null : farbe;
  await befehl('farbmarkeSetzen', { ids: ziele.map((a) => a.id), farbe: neu });
  for (const a of ziele) a.farbe = neu || undefined;
  meldung(neu ? t('Farbmarke gesetzt') : t('Farbmarke entfernt'));
}

async function inDenKorb(ziele) {
  if (!ziele.length) return;
  if (!confirm(ziele.length === 1 ? t('Eine Aufnahme in den Papierkorb legen? Sie verschwindet überall – zurückholen geht am Rechner und hier im Papierkorb.') : t('{n} Aufnahmen in den Papierkorb legen? Sie verschwinden überall – zurückholen geht am Rechner und hier im Papierkorb.', { n: ziele.length }))) return;
  await befehl('inDenPapierkorb', { ids: ziele.map((a) => a.id) });
  const weg = new Set(ziele.map((a) => a.id));
  liste.aufnahmen = liste.aufnahmen.filter((a) => !weg.has(a.id));
  zeitleiste.geladen = zeitleiste.geladen.filter((a) => !weg.has(a.id));
  if (offen >= 0) schliesse();
  auswahlAufheben();
  neuZeichnen();
}

const KUERZEL = [
  ['Überall', [
    ['?', 'Diese Übersicht'],
    ['/', 'Suchen'],
  ]],
  ['Raster', [
    ['← ↑ ↓ →', 'Den Rahmen durchs Raster bewegen'],
    ['Umschalt + Pfeil', 'Die Auswahl mitziehen'],
    ['Umschalt-Klick', 'Alles bis hierher dazunehmen'],
    ['Strg-/⌘-Klick', 'Eine einzelne Kachel umschalten'],
    ['Leertaste', 'Kachel im Rahmen wählen'],
    ['Strg/⌘ + A', 'Alle wählen'],
    ['⏎', 'Foto öffnen'],
    ['Esc', 'Auswahl leeren'],
  ]],
  ['Raster und Betrachter', [
    ['F', 'Favorit umschalten'],
    ['0 – 5', 'Sternebewertung setzen'],
    ['6 – 9', 'Farbmarke setzen (rot, gelb, grün, blau)'],
    ['Entf / ⌫', 'In den Papierkorb (mit Rückfrage)'],
  ]],
  ['Betrachter', [
    ['← / →', 'Vorheriges / nächstes Foto'],
    ['Leertaste', 'Nächstes Foto'],
    ['I', 'Angaben ein- und ausblenden'],
    ['Esc', 'Schliessen'],
  ]],
  ['Diashow', [
    ['Leertaste', 'Anhalten / weiter'],
    ['← / →', 'Vorheriges / nächstes Foto'],
    ['Esc', 'Beenden'],
  ]],
  ['Gelände', [
    ['Leertaste', 'Flug starten / anhalten'],
    ['Esc', 'Schliessen'],
  ]],
];

function zeigeKuerzel() {
  const box = $('kuerzel-liste');
  box.replaceChildren();
  for (const [titel, zeilen] of KUERZEL) {
    box.append(el('h4', null, t(titel)));
    const dl = el('dl');
    for (const [taste, was] of zeilen) dl.append(el('dt', null, t(taste)), el('dd', null, t(was)));
    box.append(dl);
  }
  box.append(el('p', 'leise klein', t('Die Tasten wirken auf die Auswahl. Gibt es keine, wirken sie auf die Kachel, auf der der Rahmen steht.')));
  $('kuerzel-dialog').showModal();
}
$('kuerzel-zu').addEventListener('click', () => $('kuerzel-dialog').close());
$('einst-kuerzel').addEventListener('click', zeigeKuerzel);

document.addEventListener('keydown', async (e) => {
  // Die Landschaft hat ihre eigenen Tasten (gelaende.js).
  if (document.body.classList.contains('landschaft-offen')) return;
  // Nicht beim Schreiben und nicht über einem offenen Dialog.
  const ziel = e.target;
  if (ziel instanceof HTMLElement && (ziel.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(ziel.tagName))) return;
  if (document.querySelector('dialog[open]')) return;
  const strg = e.metaKey || e.ctrlKey;
  if (e.altKey) return;
  const taste = e.key;
  try {
    if (!$('vergleich').hidden) {
      if (taste === 'Escape') schliesseVergleich();
      else if (taste === '0') vergleichZurueck();
      return;
    }
    if (!$('diashow').hidden) {
      if (taste === 'Escape') beendeDiashow();
      else if (taste === ' ') { e.preventDefault(); diaPause(); }
      else if (taste === 'ArrowRight') zeigeDia(dia.i + 1);
      else if (taste === 'ArrowLeft') zeigeDia(dia.i - 1);
      return;
    }
    if (offen >= 0) {
      if (strg) return;
      const a = liste.aufnahmen[offen];
      if (taste === 'Escape') schliesse();
      else if (taste === 'ArrowLeft') oeffne(offen - 1);
      else if (taste === 'ArrowRight' || taste === ' ') { e.preventDefault(); oeffne(offen + 1); }
      else if (taste === 'i' || taste === 'I') setzeAngabenOffen(!angabenOffen);
      else if (fremdeAufnahme(a)) return;
      else if (taste === 'f' || taste === 'F') await setzeFavorit([a]);
      else if (/^[0-5]$/.test(taste)) await setzeSterne([a], Number(taste));
      else if (FARBTASTEN[taste]) await setzeFarbe([a], FARBTASTEN[taste]);
      else if ((taste === 'Delete' || taste === 'Backspace') && !liste.papierkorb) await inDenKorb([a]);
      return;
    }
    if (taste === '?') { e.preventDefault(); zeigeKuerzel(); return; }
    if (taste === '/' && !strg) { e.preventDefault(); location.hash = '#/suche'; return; }
    if ($('bereich-raster').hidden || !liste || !liste.kacheln || !liste.kacheln.length) return;
    if (strg && (taste === 'a' || taste === 'A') && !liste.fremd) {
      e.preventDefault();
      for (const x of liste.aufnahmen) if (!x.konto) auswahl.add(x.id);
      zeichneAuswahl();
      return;
    }
    if (strg) return;
    const pfeil = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: 'oben', ArrowDown: 'unten' }[taste];
    if (pfeil !== undefined) {
      e.preventDefault();
      const ohneRahmen = rahmen < 0 || !liste.kacheln[rahmen]?.classList.contains('rahmen');
      if (ohneRahmen) {
        // Der erste Druck setzt den Rahmen auf die erste sichtbare Kachel.
        const sichtbar = liste.kacheln.findIndex((k) => k.getBoundingClientRect().bottom > 60);
        setzeRahmen(Math.max(0, sichtbar));
        rahmenAnker = rahmen;
        return;
      }
      const von = rahmen;
      const neu = pfeil === 'oben' ? reiheWeiter(von, -1) : pfeil === 'unten' ? reiheWeiter(von, 1) : von + pfeil;
      if (!e.shiftKey) rahmenAnker = neu;
      else if (!auswahl.size) { rahmenAnker = von; }
      setzeRahmen(neu);
      if (e.shiftKey) waehleBereich(rahmenAnker, rahmen);
      return;
    }
    if (liste.fremd) { if (taste === 'Enter' && rahmen >= 0) oeffne(rahmen); return; }
    const ziele = tastenziele();
    if (taste === 'Enter' && rahmen >= 0) oeffne(rahmen);
    else if (taste === ' ' && rahmen >= 0 && liste.kacheln[rahmen].classList.contains('rahmen')) { e.preventDefault(); schalteAuswahl(liste.aufnahmen[rahmen].id, liste.kacheln[rahmen]); }
    // Erst die Auswahl, beim zweiten Mal der Rahmen.
    else if (taste === 'Escape') { if (auswahl.size || auswahlModus) auswahlAufheben(); else setzeRahmen(rahmen, false); }
    else if (taste === 'f' || taste === 'F') await setzeFavorit(ziele);
    else if (/^[0-5]$/.test(taste)) await setzeSterne(ziele, Number(taste));
    else if (FARBTASTEN[taste]) await setzeFarbe(ziele, FARBTASTEN[taste]);
    else if ((taste === 'Delete' || taste === 'Backspace') && !liste.papierkorb) { e.preventDefault(); await inDenKorb(ziele); }
  } catch (x) { meldung(x.message); }
});

// --- Wege ------------------------------------------------------------------

let wegAbbruch = null;

async function zeigeWeg(art) {
  if (!sitzung) return;
  if (wegAbbruch) wegAbbruch.abort();
  const abbruch = wegAbbruch = new AbortController();
  wegSignal = abbruch.signal;
  const still = stillerLauf = art === 'still';
  if (!still) {
    ansichtNr++;
    suchlauf++;
    schliesse();
    auswahlAufheben();
    $('auswaehlen').hidden = false;
    $('karten').replaceChildren();
  }
  const teile = wegTeile();
  try {
    switch (teile[0]) {
      case 'suche': zeigeSuche(); break;
      case 'alben': await (teile[1] === 'klug' ? zeigeIntelligentesAlbum(teile[2]) : teile[1] ? zeigeAlbum(teile[1]) : zeigeAlben()); break;
      case 'geteilt': await zeigeGeteiltesAlbum(teile[1]); break;
      case 'partner': await zeigePartnerbibliothek(teile[1]); break;
      case 'personen': await (teile[1] ? zeigePerson(teile[1]) : zeigePersonen()); break;
      case 'ignoriert': await zeigeIgnoriert(); break;
      case 'konto': await zeigeKonto(); break;
      case 'reisen': await (teile[1] ? zeigeReise(teile[1]) : zeigeReisen()); break;
      case 'aktivitaeten': await zeigeAktivitaet(teile[1]); break;
      case 'statistik': await zeigeStatistik(); break;
      case 'rueckblick': await ladeSkript('rueckblick.js'); await zeigeRueckblick(); break;
      case 'jahresrueckblick': await ladeSkript('rueckblick.js'); await zeigeJahresrueckblick(teile[1]); break;
      case 'kalender': await ladeSkript('rueckblick.js'); await zeigeKalender(teile[1], teile[2]); break;
      case 'einstellungen': await zeigeEinstellungen(); break;
      case 'stammbaum': await ladeSkript('lebensbaum.js'); await ladeSkript('stammbaum.js'); await zeigeStammbaum(teile[1]); break;
      case 'lebensbaum': await ladeSkript('lebensbaum.js'); await zeigeLebensbaum(teile[1]); break;
      case 'duplikate': await zeigeDuplikate(); break;
      case 'fotokammer': await ladeSkript('kammer.js'); await zeigeKammer(); break;
      case 'aufnahmedaten': await zeigeAufnahmedaten(); break;
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
      case 'orte': await (teile[1] ? zeigeOrt(teile[1], teile[2]) : zeigeOrte()); break;
      case 'bibliothek': await zeigeBibliothek(); break;
      default: await zeigeFotos();
    }
  } catch (x) {
    // Als Meldung: #ende liegt im Raster und wäre in den meisten Ansichten
    // gar nicht zu sehen.
    if (!still && x.name !== 'AbortError' && x.message !== 'nicht angemeldet') meldung(x.message, true);
  } finally {
    if (wegAbbruch === abbruch) { wegSignal = null; stillerLauf = false; }
  }
}
window.addEventListener('hashchange', zeigeWeg);

// --- Von selbst aktuell (#329) ------------------------------------------------
//
// Was ein anderes Gerät ändert – vor allem neue Fotos vom Handy –, kommt ohne
// Neuladen an. Die Seite fragt den Server, und der antwortet, sobald sich sein
// Protokoll ändert. Nur im sichtbaren Tab: Jeder wartende Tab hielte sonst eine
// der wenigen Verbindungen, die ein Browser je Server hat.
//
// Während jemand etwas tut, bleibt die Ansicht stehen und kommt danach dran:
// Betrachter, Auswahl, Dialog, Eingabe, Ziehen. Scrollt jemand weiter unten,
// bleibt das Foto dort, wo es ist, auch wenn oben neue dazukommen.

function wegTeile() {
  return location.hash.replace(/^#\/?/, '').split('/').map(decodeURIComponent);
}

// Ein stiller Lauf lässt stehen, was dieselbe Antwort bekäme.
let letzteAntwort = null;
function unveraendert(d) {
  const text = JSON.stringify(d);
  const gleich = stillerLauf && text === letzteAntwort;
  letzteAntwort = text;
  return gleich;
}

function ansichtGesperrt() {
  const fokus = document.activeElement;
  return (!!wegSignal && !stillerLauf) || offen >= 0
    || !$('diashow').hidden || !$('vergleich').hidden
    || auswahl.size > 0 || auswahlModus
    || !!(liste && liste.laedt) || zeitleiste.seite !== 200
    || bildlauf.zieht || zieh.anker !== null || schwebe.kachel !== null
    || !!document.querySelector('dialog[open]')
    || !!(fokus && fokus.matches('input, textarea, select'));
}

// Was sich neu holen lässt, ohne jemandem etwas wegzunehmen. Nicht dabei:
// Formulare, Suchergebnisse, gemerkte Suchen (die rechnen am Server) und
// Ansichten aus fremden Bibliotheken, deren Änderungen hier nicht ankommen.
function ansichtLebt() {
  const [wurzel, teil] = wegTeile();
  if (wurzel === 'alben') return teil !== 'klug';
  if (wurzel === 'karte') return !teil;
  return ['', 'favoriten', 'papierkorb', 'personen', 'orte', 'reisen', 'statistik'].includes(wurzel);
}

function plane(warte) {
  // Während einer Prüfung nicht: Ihr Ende plant selbst und kennt den Abstand.
  if (live.uhr !== null || stillerLauf) return;
  live.uhr = setTimeout(pruefeAnsicht, warte ?? Math.max(1000, live.zuletzt + live.abstand - performance.now()));
}

async function pruefeAnsicht() {
  live.uhr = null;
  if (!live.faellig || stillerLauf || !sitzung || document.hidden) return;
  if (ansichtGesperrt()) { plane(2000); return; }
  live.faellig = false;
  const beginn = performance.now();
  // Liegt die Zeitleiste im Hintergrund, lädt sie beim Zurückkommen frisch.
  if (wegTeile()[0] !== '') zeitleiste.leeren();
  orteListe = null;
  if (ansichtLebt()) {
    await zeigeWeg('still');
    const ende = $('ende').getBoundingClientRect();
    if (liste && liste.mehr && ende.height && ende.top < innerHeight) ladeMehr();
  }
  live.zuletzt = performance.now();
  // Bibliotheken, an denen der Server lange rechnet, ändern sich ständig;
  // die Prüfung soll davon nur einen kleinen Teil der Zeit brauchen.
  live.abstand = Math.max(5000, 20 * (live.zuletzt - beginn));
  if (live.nochmal) { live.nochmal = false; live.faellig = true; }
  if (live.faellig) plane();
}

async function lausche() {
  if (live.laeuft) return;
  live.laeuft = true;
  let fehlversuche = 0;
  while (sitzung && !document.hidden) {
    const abbruch = live.abbruch = new AbortController();
    let pause = 0;
    try {
      const q = new URLSearchParams({ warten: '25' });
      if (live.stand !== null) q.set('bisher', live.stand);
      const antwort = await fetch(`/api/v1/ansicht/stand?${q}`, { credentials: 'same-origin', signal: abbruch.signal, headers: { 'X-PV-Web': '1' } });
      if (antwort.status === 401) { zeigeAnmeldung(); break; }
      if (!antwort.ok) throw new Error(String(antwort.status));
      const d = await antwort.json();
      fehlversuche = 0;
      if (live.stand !== null && d.stand !== live.stand) {
        live.faellig = true;
        plane();
        // Solange der Server schreibt, nicht bei jeder Zeile neu fragen.
        pause = 2000;
      }
      live.stand = d.stand;
    } catch (x) {
      if (x.name === 'AbortError') break;
      // Server weg oder Rechner aufgewacht: Mit dem alten Stand holt die
      // nächste Antwort nach, was dazwischen geschah.
      fehlversuche++;
      pause = Math.min(30000, 1000 * 2 ** fehlversuche);
    }
    if (pause) await new Promise((fertig) => setTimeout(fertig, pause));
  }
  live.laeuft = false;
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) { if (live.abbruch) live.abbruch.abort(); return; }
  if (!sitzung) return;
  lausche();
  if (live.faellig) plane();
});

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
  await oidcZurueck();
  lausche();
  await zeigeWeg();
}

starte().catch(() => zeigeAnmeldung());

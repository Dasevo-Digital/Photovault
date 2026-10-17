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
  for (const b of ['suche', 'karten', 'konto', 'raster', 'karte']) $(`bereich-${b}`).hidden = true;
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
  if (i >= liste.aufnahmen.length - 20) ladeMehr();
}

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

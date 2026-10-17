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
  for (const b of ['suche', 'karten', 'konto', 'raster']) $(`bereich-${b}`).hidden = true;
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
  zeigeListe({ aufnahmen: alt.aufnahmen, nachTagen: alt.nachTagen, mehr: alt.mehr, suche: alt.suche }, $('raster-titel').hidden ? null : $('raster-titel').textContent);
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

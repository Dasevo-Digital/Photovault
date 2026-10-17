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
  if (antwort.status === 401) { zeige('anmeldung'); throw new Error('nicht angemeldet'); }
  if (!antwort.ok) throw new Error((daten && daten.fehler) || `Fehler ${antwort.status}`);
  return daten;
};

const ansichten = ['anmeldung', 'zeitleiste'];
function zeige(name) {
  for (const a of ansichten) $(a).hidden = a !== name;
  $('kopf').hidden = name !== 'zeitleiste';
  if (name === 'anmeldung') { $('form-anmelden').hidden = false; $('form-totp').hidden = true; }
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

$('abmelden').addEventListener('click', async () => {
  try { await api('/api/v1/web/abmelden', { methode: 'POST' }); } catch (_) { /* egal */ }
  aufnahmen = []; weiter = undefined; letzterTag = null; $('raster').replaceChildren();
  $('form-anmelden').reset();
  zeige('anmeldung');
});

// --- Zeitleiste ------------------------------------------------------------

let aufnahmen = [];   // alle geladenen, in der Reihenfolge des Rasters
let weiter;           // Lesezeichen für die nächste Seite; null = Ende
let laedt = false;
let letzterTag = null;
const datum = new Intl.DateTimeFormat(undefined, { dateStyle: 'full' });
const datumZeit = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });

function kachel(a, index) {
  const k = document.createElement('button');
  k.type = 'button';
  k.className = 'kachel';
  k.dataset.index = index;
  const img = document.createElement('img');
  img.loading = 'lazy';
  img.decoding = 'async';
  img.alt = '';
  img.src = `/api/v1/aufnahmen/${encodeURIComponent(a.id)}/miniatur`;
  k.append(img);
  if (a.art === 'video') { const m = document.createElement('span'); m.className = 'marke'; m.textContent = '▶'; k.append(m); }
  if (a.favorit) { const h = document.createElement('span'); h.className = 'herz'; h.textContent = '♥'; k.append(h); }
  k.addEventListener('click', () => oeffne(index));
  return k;
}

async function ladeMehr() {
  if (laedt || weiter === null) return;
  laedt = true;
  try {
    const q = new URLSearchParams({ anzahl: '200' });
    if (weiter) q.set('nach', weiter);
    const d = await api(`/api/v1/aufnahmen?${q}`);
    const raster = $('raster');
    for (const a of d.aufnahmen) {
      const tag = datum.format(new Date(a.aufgenommen));
      if (tag !== letzterTag) {
        letzterTag = tag;
        const h = document.createElement('h2');
        h.textContent = tag;
        raster.append(h);
      }
      raster.append(kachel(a, aufnahmen.length));
      aufnahmen.push(a);
    }
    weiter = d.weiter;
    $('ende').textContent = aufnahmen.length === 0
      ? 'Noch keine Aufnahmen.'
      : weiter === null ? `${aufnahmen.length} Aufnahmen` : '';
  } catch (x) {
    $('ende').textContent = x.message;
  } finally {
    laedt = false;
  }
}

const waechter = new IntersectionObserver((e) => { if (e.some((x) => x.isIntersecting)) ladeMehr(); });

async function starte() {
  const s = await api('/api/v1/web/sitzung');
  $('wer').textContent = s.name;
  zeige('zeitleiste');
  if (aufnahmen.length === 0) await ladeMehr();
  waechter.observe($('ende'));
}

// --- Betrachter ------------------------------------------------------------

let offen = -1;

function oeffne(i) {
  if (i < 0 || i >= aufnahmen.length) return;
  offen = i;
  const a = aufnahmen[i];
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
  $('betrachter').hidden = false;
  if (i >= aufnahmen.length - 20) ladeMehr();
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
  const a = aufnahmen[offen];
  if (!a) return;
  try {
    await api('/api/v1/befehle', {
      methode: 'POST',
      json: { art: 'favoritSetzen', werte: { ids: [a.id], favorit: !a.favorit } },
    });
    a.favorit = !a.favorit;
    $('favorit').textContent = a.favorit ? '♥' : '♡';
    const k = $('raster').querySelector(`.kachel[data-index="${offen}"]`);
    if (k) {
      let h = k.querySelector('.herz');
      if (a.favorit && !h) { h = document.createElement('span'); h.className = 'herz'; h.textContent = '♥'; k.append(h); }
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

// --- Start ---------------------------------------------------------------

starte().catch(() => zeige('anmeldung'));

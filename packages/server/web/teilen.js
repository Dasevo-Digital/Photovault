'use strict';

// Die Seite einer Freigabe (Issue #106): Wer den Link hat, sieht genau die
// Aufnahmen darin – Bilder ohne Metadaten, Videos als H.264 –, und lädt
// Originale nur, wenn der Besitzer es erlaubt hat. Diese Seite spricht nur
// mit /api/v1/teilen/<link>, nie mit der übrigen Schnittstelle.

const $ = (id) => document.getElementById(id);
const el = (tag, klasse, text) => {
  const e = document.createElement(tag);
  if (klasse) e.className = klasse;
  if (text !== undefined) e.textContent = text;
  return e;
};
const link = location.pathname.split('/').filter(Boolean).pop() || '';
const basis = `/api/v1/teilen/${encodeURIComponent(link)}`;
const datei = (id, art, pruefen) => `${basis}/${encodeURIComponent(id)}/${art}${pruefen ? '?pruefen=1' : ''}`;
const datumZeit = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'medium', timeStyle: 'short' });
const tagFormat = new Intl.DateTimeFormat(GEBIET, { dateStyle: 'long' });

let freigabe = null;
let offen = -1;
let lauf = 0;

function hinweis(text) {
  $('teilen-hinweis').textContent = text || '';
  $('teilen-hinweis').hidden = !text;
}

async function lade() {
  let r;
  try { r = await fetch(basis, { credentials: 'same-origin' }); } catch (_) { hinweis(t('Keine Verbindung zum Server.')); return; }
  if (r.status === 404) { hinweis(t('Diese Freigabe gibt es nicht oder nicht mehr.')); return; }
  if (r.status === 401) { $('teilen-passwort').hidden = false; return; }
  if (!r.ok) { hinweis(t('Die Freigabe ließ sich nicht laden.')); return; }
  freigabe = await r.json();
  $('teilen-passwort').hidden = true;
  zeige();
}

function zeige() {
  const d = freigabe;
  document.title = d.titel;
  $('teilen-titel').textContent = d.titel;
  const n = d.aufnahmen.length;
  $('teilen-unterzeile').textContent = [
    n === 1 ? t('1 Aufnahme') : t('{n} Aufnahmen', { n }),
    d.ablauf ? t('Gültig bis {datum}', { datum: tagFormat.format(new Date(d.ablauf)) }) : null,
  ].filter(Boolean).join(' · ');
  const raster = $('teilen-raster');
  raster.replaceChildren();
  if (!n) hinweis(t('Hier liegt nichts mehr.'));
  d.aufnahmen.forEach((a, i) => {
    const k = el('button', 'kachel');
    k.type = 'button';
    const img = el('img');
    img.alt = '';
    img.loading = 'lazy';
    img.decoding = 'async';
    img.src = datei(a.id, 'miniatur');
    k.append(img);
    if (a.art === 'video') k.append(el('span', 'marke', '▶'));
    k.addEventListener('click', () => oeffne(i));
    raster.append(k);
  });
}

$('teilen-passwort').addEventListener('submit', async (e) => {
  e.preventDefault();
  const passwort = e.target.passwort.value;
  $('teilen-fehler').textContent = '';
  let r;
  try {
    r = await fetch(`${basis}/passwort`, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ passwort }),
    });
  } catch (_) { $('teilen-fehler').textContent = t('Keine Verbindung zum Server.'); return; }
  if (r.status === 204) { e.target.passwort.value = ''; lade(); return; }
  $('teilen-fehler').textContent = r.status === 429
    ? t('Zu viele Versuche – bitte später noch einmal.')
    : t('Das Passwort stimmt nicht.');
});

// --- Betrachter ------------------------------------------------------------

function videoHinweis(text) {
  $('t-hinweis').textContent = text || '';
  $('t-hinweis').hidden = !text;
}

async function spieleVideo(a, meinLauf) {
  const video = $('t-video');
  videoHinweis(t('Das Video wird vorbereitet …'));
  for (let i = 0; i < 900 && meinLauf === lauf; i++) {
    let r;
    try { r = await fetch(datei(a.id, 'video', true), { credentials: 'same-origin' }); } catch (_) { break; }
    if (r.status === 200) {
      if (meinLauf !== lauf) return;
      videoHinweis('');
      video.src = datei(a.id, 'video');
      video.play().catch(() => {});
      return;
    }
    if (r.status !== 202) break;
    await new Promise((fertig) => setTimeout(fertig, 1000));
  }
  if (meinLauf === lauf) videoHinweis(t('Dieses Video lässt sich nicht abspielen.'));
}

function oeffne(i) {
  const d = freigabe;
  if (!d || i < 0 || i >= d.aufnahmen.length) return;
  offen = i;
  lauf++;
  const a = d.aufnahmen[i];
  const bild = $('t-bild'), video = $('t-video');
  video.pause();
  video.removeAttribute('src');
  video.load();
  videoHinweis('');
  if (a.art === 'video') {
    bild.hidden = true;
    video.hidden = false;
    spieleVideo(a, lauf);
  } else {
    video.hidden = true;
    bild.hidden = false;
    bild.src = datei(a.id, 'ansicht');
  }
  $('t-laden').hidden = !d.herunterladen;
  if (d.herunterladen) $('t-laden').href = datei(a.id, 'original');
  $('t-zurueck').disabled = i === 0;
  $('t-vor').disabled = i === d.aufnahmen.length - 1;
  $('teilen-betrachter').hidden = false;
  bild.alt = datumZeit.format(new Date(a.aufgenommen));
}

function schliesse() {
  lauf++;
  $('t-video').pause();
  $('teilen-betrachter').hidden = true;
  offen = -1;
}

$('t-zu').addEventListener('click', schliesse);
$('t-zurueck').addEventListener('click', () => oeffne(offen - 1));
$('t-vor').addEventListener('click', () => oeffne(offen + 1));
document.addEventListener('keydown', (e) => {
  if (offen < 0) return;
  if (e.key === 'Escape') schliesse();
  else if (e.key === 'ArrowLeft') oeffne(offen - 1);
  else if (e.key === 'ArrowRight') oeffne(offen + 1);
});
// Wischen zum Blättern.
let start = null;
$('teilen-betrachter').addEventListener('pointerdown', (e) => { start = { x: e.clientX, y: e.clientY }; });
$('teilen-betrachter').addEventListener('pointerup', (e) => {
  if (!start) return;
  const dx = e.clientX - start.x, dy = e.clientY - start.y;
  start = null;
  if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy)) oeffne(offen + (dx < 0 ? 1 : -1));
  else if (dy > 90 && Math.abs(dy) > Math.abs(dx)) schliesse();
});

lade();

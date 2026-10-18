'use strict';

// --- Hochladen ------------------------------------------------------------------
//
// Was auf dem Telefon die Sicherung der Kamerarolle ist, ist im Browser
// das Hochladen: Dateien auswählen (auf dem Telefon öffnet das die
// Fotomediathek) oder ins Fenster ziehen. Es geht derselbe Weg wie die App –
// tus in Stücken an /api/v1/hochladen, danach derselbe Import. Ein Stück
// bleibt weit unter der Grenze eines Reverse Proxys; bricht die Verbindung
// ab, fragt der Browser nach, wie weit der Server ist, und macht dort weiter.
// Was der Server schon hat, erkennt sein Import und meldet es als Dublette.

const HL_STUECK = 8 * 1024 * 1024;
const HL_TUS = { 'Tus-Resumable': '1.0.0', 'X-PV-Web': '1' };

const hl = { laeuft: false, abbrechen: false, warteschlange: [], neu: 0, da: 0, fehler: [], gesamt: 0, fertig: 0 };

// Upload-Metadata: Schlüssel und Base64-Wert, durch Kommas getrennt.
function hlMeta(werte) {
  return Object.entries(werte).map(([k, v]) => {
    const bytes = new TextEncoder().encode(String(v));
    let roh = '';
    for (const b of bytes) roh += String.fromCharCode(b);
    return `${k} ${btoa(roh)}`;
  }).join(',');
}

async function hlFrage(pfad, methode, kopf, inhalt) {
  const r = await fetch(pfad, { method: methode, credentials: 'same-origin', headers: { ...HL_TUS, ...kopf }, body: inhalt });
  if (r.status === 401) { zeigeAnmeldung(); throw new Error('nicht angemeldet'); }
  return r;
}

async function hlStand(ort) {
  const r = await hlFrage(ort, 'HEAD', {});
  if (!r.ok) throw new Error(t('Fehler {n}', { n: r.status }));
  return Number(r.headers.get('Upload-Offset') || 0);
}

// Eine Datei hoch; gibt den Ausgang des Imports zurück.
async function hlDatei(datei, fortschritt) {
  const angelegt = await hlFrage('/api/v1/hochladen', 'POST', {
    'Upload-Length': String(datei.size),
    'Upload-Metadata': hlMeta({ filename: datei.name, geaendert: datei.lastModified || Date.now() }),
  });
  if (angelegt.status === 415) return { ausgang: 'abgelehnt', grund: (await angelegt.text()).trim() || t('Format nicht unterstützt') };
  if (angelegt.status === 507 || angelegt.status === 413) return { ausgang: 'abgelehnt', grund: t('Kein Platz auf dem Server') };
  if (angelegt.status !== 201) throw new Error(t('Fehler {n}', { n: angelegt.status }));
  const ort = angelegt.headers.get('Location');
  let versatz = 0;
  let ausgang = null;
  let versuche = 0;
  for (;;) {
    if (hl.abbrechen) { try { await hlFrage(ort, 'DELETE', {}); } catch (_) { /* egal */ } return { ausgang: 'abgebrochen' }; }
    let r;
    try {
      r = await hlFrage(ort, 'PATCH', {
        'Upload-Offset': String(versatz),
        'Content-Type': 'application/offset+octet-stream',
      }, datei.slice(versatz, versatz + HL_STUECK));
    } catch (x) {
      // Die Verbindung riss ab: nachfragen, wie weit der Server ist, und
      // dort weiter – ein paar Mal.
      if (++versuche > 3 || x.message === 'nicht angemeldet') throw x;
      await new Promise((fertig) => setTimeout(fertig, 1000 * versuche));
      versatz = await hlStand(ort);
      if (datei.size > 0 && versatz >= datei.size) break;
      continue;
    }
    if (r.status === 409) {
      versatz = await hlStand(ort);
      if (versatz >= datei.size) break;
      continue;
    }
    if (r.status === 507) return { ausgang: 'abgelehnt', grund: t('Kein Platz auf dem Server') };
    if (!r.ok) throw new Error(t('Fehler {n}', { n: r.status }));
    versuche = 0;
    versatz = Number(r.headers.get('Upload-Offset') || versatz);
    fortschritt(datei.size ? versatz / datei.size : 1);
    ausgang = r.headers.get('Pv-Ausgang');
    if (ausgang || versatz >= datei.size) break;
  }
  // Ging die letzte Antwort verloren, weiss der Server das Ergebnis noch.
  if (!ausgang) {
    const r = await hlFrage(ort, 'GET', {});
    if (r.ok) { const j = await r.json(); ausgang = j.ergebnis && j.ergebnis.ausgang; }
  }
  if (ausgang === 'imported') return { ausgang: 'neu' };
  if (ausgang === 'duplicateSkipped') return { ausgang: 'da' };
  return { ausgang: 'abgelehnt', grund: t('Der Server konnte die Datei nicht aufnehmen') };
}

function hlZeige(text, anteil) {
  $('hochladen-stand').hidden = false;
  $('hochladen-text').textContent = text;
  $('hochladen-balken').value = anteil;
  const teile = [];
  if (hl.neu) teile.push(t('{n} neu', { n: hl.neu }));
  if (hl.da) teile.push(t('{n} schon da', { n: hl.da }));
  if (hl.fehler.length) teile.push(t('{n} abgelehnt', { n: hl.fehler.length }));
  $('hochladen-ergebnis').textContent = teile.join(' · ');
  $('hochladen-abbrechen').hidden = !hl.laeuft;
  $('hochladen-zu').hidden = hl.laeuft;
}

async function ladeHoch(dateien) {
  if (!dateien.length) return;
  hl.warteschlange.push(...dateien);
  hl.gesamt += dateien.length;
  if (hl.laeuft) return;
  hl.laeuft = true;
  hl.abbrechen = false;
  $('hochladen-fehler').replaceChildren();
  while (hl.warteschlange.length && !hl.abbrechen) {
    const d = hl.warteschlange.shift();
    const nummer = hl.fertig + 1;
    const text = () => t('{i} von {n}', { i: nummer, n: hl.gesamt }) + ` · ${d.name}`;
    hlZeige(text(), hl.fertig / hl.gesamt);
    let e;
    try {
      e = await hlDatei(d, (anteil) => hlZeige(text(), (hl.fertig + anteil) / hl.gesamt));
    } catch (x) {
      e = { ausgang: 'abgelehnt', grund: x.message };
      if (x.message === 'nicht angemeldet') hl.abbrechen = true;
    }
    if (e.ausgang === 'neu') hl.neu++;
    else if (e.ausgang === 'da') hl.da++;
    else if (e.ausgang === 'abgelehnt') {
      hl.fehler.push(d.name);
      $('hochladen-fehler').append(el('li', null, `${d.name}: ${e.grund}`));
    }
    hl.fertig++;
  }
  const abgebrochen = hl.abbrechen;
  hl.laeuft = false;
  hl.warteschlange = [];
  hlZeige(abgebrochen ? t('Abgebrochen') : t('Fertig'), 1);
  // Neues erscheint in der Zeitleiste.
  if (hl.neu) {
    zeitleiste.leeren();
    if ((location.hash || '#/').replace(/^#\/?/, '') === '') zeigeFotos().catch(() => {});
  }
}

function hlZuruecksetzen() {
  Object.assign(hl, { neu: 0, da: 0, fehler: [], gesamt: 0, fertig: 0 });
  $('hochladen-stand').hidden = true;
}

$('hochladen').addEventListener('click', () => $('hochladen-datei').click());
$('hochladen-datei').addEventListener('change', (e) => {
  const dateien = [...e.target.files];
  e.target.value = '';
  if (!hl.laeuft) hlZuruecksetzen();
  ladeHoch(dateien);
});
$('hochladen-abbrechen').addEventListener('click', () => { hl.abbrechen = true; });
$('hochladen-zu').addEventListener('click', hlZuruecksetzen);

// Ins Fenster ziehen – nur Dateien, und nur angemeldet.
const mitDateien = (e) => sitzung && e.dataTransfer && [...e.dataTransfer.types].includes('Files');
let ablageTiefe = 0;
window.addEventListener('dragenter', (e) => { if (!mitDateien(e)) return; e.preventDefault(); ablageTiefe++; $('ablage').hidden = false; });
window.addEventListener('dragover', (e) => { if (!mitDateien(e)) return; e.preventDefault(); e.dataTransfer.dropEffect = 'copy'; });
window.addEventListener('dragleave', (e) => { if (!mitDateien(e)) return; if (--ablageTiefe <= 0) { ablageTiefe = 0; $('ablage').hidden = true; } });
window.addEventListener('drop', (e) => {
  if (!mitDateien(e)) return;
  e.preventDefault();
  ablageTiefe = 0;
  $('ablage').hidden = true;
  if (!hl.laeuft) hlZuruecksetzen();
  ladeHoch([...e.dataTransfer.files]);
});

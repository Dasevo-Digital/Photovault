'use strict';

// --- Fotokammer (#336) ---------------------------------------------------------
//
// Fotos, die schon auf dem Server liegen, aber erst nach „Freigeben“ in die
// Bibliothek kommen – bis dahin stehen sie nirgends sonst, nicht in der
// Zeitleiste, nicht in der Suche, nicht auf dem Handy. Hochladen legt sie
// hierher, wenn „Neue Uploads erst in die Fotokammer“ angehakt ist (siehe
// hochladen.js; der Haken gilt nur in diesem Browser), und aus der
// Zeitleiste kommen sie über „Fotokammer“ in der Auswahlleiste (#337).
//
// Sichten: Eine Kachel anklicken wählt sie aus, doppelt klicken zeigt das
// Foto gross. Dort blättern die Pfeiltasten, die Leertaste wählt aus, Esc
// schliesst. Danach die Auswahl freigeben – und mit „Auswahl umkehren“ den
// Rest verwerfen.

const kammer = { eintraege: [], auswahl: new Set(), offen: -1, arbeit: false, bytes: 0 };

// So viele auf einmal: Der Server importiert sie nacheinander, ein RAW
// braucht Sekunden, und ein Proxy davor wartet nicht ewig.
const KAMMER_STAPEL = 4;

async function zeigeKammer() {
  markiereNav('fotokammer');
  zeigeBereich(['fotokammer']);
  $('kammer-erst').checked = kammerAn();
  await ladeKammer();
}

async function ladeKammer() {
  const d = await api('/api/v1/kammer');
  kammer.eintraege = d.eintraege;
  kammer.bytes = d.bytes;
  const da = new Set(d.eintraege.map((e) => e.id));
  for (const id of [...kammer.auswahl]) if (!da.has(id)) kammer.auswahl.delete(id);
  zeichneKammer();
}

function zeichneKammer() {
  const ziel = $('kammer-raster');
  ziel.replaceChildren();
  const n = kammer.eintraege.length;
  $('kammer-hinweis').textContent = n === 0
    ? t('Die Fotokammer ist leer. Ist „Neue Uploads erst in die Fotokammer“ angehakt, landen hochgeladene Fotos zuerst hier.')
    : t('{n} Fotos, {g}. Klicken wählt aus, doppelt klicken zeigt das Foto groß.', { n, g: groesse(kammer.bytes) });
  kammer.eintraege.forEach((e, i) => {
    const k = el('button', 'kammerkachel');
    k.type = 'button';
    k.title = e.name;
    k.dataset.id = e.id;
    // Ohne Masse hat der Server keine Vorschau machen können – dann gar
    // nicht erst nach einer fragen.
    if (e.breite) {
      const img = el('img');
      img.loading = 'lazy';
      img.alt = '';
      img.src = `/api/v1/kammer/${e.id}/miniatur`;
      img.addEventListener('error', () => img.replaceWith(el('span', 'ohne', e.name)));
      k.append(img);
    } else {
      k.append(el('span', 'ohne', e.name));
    }
    if (e.art === 'VIDEO') k.append(el('span', 'video', '▶'));
    k.classList.toggle('gewaehlt', kammer.auswahl.has(e.id));
    k.addEventListener('click', () => { umschalteKammer(e.id); });
    k.addEventListener('dblclick', () => oeffneKammer(i));
    ziel.append(k);
  });
  kammerKnoepfe();
}

function umschalteKammer(id) {
  if (!kammer.auswahl.delete(id)) kammer.auswahl.add(id);
  const k = document.querySelector(`.kammerkachel[data-id="${id}"]`);
  if (k) k.classList.toggle('gewaehlt', kammer.auswahl.has(id));
  kammerKnoepfe();
}

function kammerKnoepfe() {
  const n = kammer.auswahl.size;
  const alle = n > 0 && n === kammer.eintraege.length;
  $('kammer-alle').textContent = alle ? t('Keine auswählen') : t('Alle auswählen');
  $('kammer-alle').hidden = kammer.eintraege.length === 0;
  $('kammer-umkehren').hidden = kammer.eintraege.length === 0;
  $('kammer-freigeben').disabled = n === 0 || kammer.arbeit;
  $('kammer-verwerfen').disabled = n === 0 || kammer.arbeit;
  $('kammer-freigeben').textContent = n ? t('{n} freigeben', { n }) : t('Freigeben');
  $('kammer-verwerfen').textContent = n ? t('{n} verwerfen', { n }) : t('Verwerfen');
  if (kammer.offen >= 0) zeigeKammerGross();
}

async function kammerFreigeben() {
  const ids = kammer.eintraege.filter((e) => kammer.auswahl.has(e.id)).map((e) => e.id);
  if (!ids.length || kammer.arbeit) return;
  kammer.arbeit = true;
  kammerKnoepfe();
  let neu = 0;
  const fehler = [];
  try {
    for (let i = 0; i < ids.length; i += KAMMER_STAPEL) {
      $('kammer-hinweis').textContent = t('Gebe frei … {i} von {n}', { i: i, n: ids.length });
      const r = await api('/api/v1/kammer/freigeben', { methode: 'POST', json: { ids: ids.slice(i, i + KAMMER_STAPEL) } });
      for (const e of r.ergebnisse) {
        if (e.ausgang === 'imported' || e.ausgang === 'duplicateSkipped') neu++;
        else fehler.push(e.fehler || e.ausgang);
      }
    }
  } catch (x) {
    fehler.push(x.message);
  } finally {
    kammer.arbeit = false;
    kammer.auswahl.clear();
    // Neues erscheint in der Zeitleiste.
    if (neu) zeitleiste.leeren();
    await ladeKammer().catch(() => {});
  }
  meldung([
    t('{n} in die Bibliothek übernommen', { n: neu }),
    ...(fehler.length ? [t('{n} nicht: {grund}', { n: fehler.length, grund: [...new Set(fehler)].join('; ') })] : []),
  ].join(' · '), fehler.length > 0);
}

async function kammerVerwerfen() {
  const ids = [...kammer.auswahl];
  if (!ids.length || kammer.arbeit) return;
  if (!confirm(ids.length === 1
    ? t('Ein Foto endgültig verwerfen? Die Fotokammer hat keinen Papierkorb – es liegt dann nur noch dort, woher es kam. Fotos aus der Zeitleiste bleiben bis zum Ablauf im Papierkorb.')
    : t('{n} Fotos endgültig verwerfen? Die Fotokammer hat keinen Papierkorb – sie liegen dann nur noch dort, woher sie kamen. Fotos aus der Zeitleiste bleiben bis zum Ablauf im Papierkorb.', { n: ids.length }))) return;
  kammer.arbeit = true;
  kammerKnoepfe();
  try {
    const r = await api('/api/v1/kammer/verwerfen', { methode: 'POST', json: { ids } });
    meldung(t('{n} verworfen', { n: r.verworfen }));
  } catch (x) {
    meldung(x.message, true);
  } finally {
    kammer.arbeit = false;
    kammer.auswahl.clear();
    await ladeKammer().catch(() => {});
  }
}

// --- Gross ansehen ---------------------------------------------------------------

function oeffneKammer(i) {
  kammer.offen = i;
  $('kammer-gross').hidden = false;
  zeigeKammerGross();
}

function schliesseKammer() {
  kammer.offen = -1;
  $('kammer-gross').hidden = true;
  $('kammer-gross-bild').removeAttribute('src');
}

function zeigeKammerGross() {
  const e = kammer.eintraege[kammer.offen];
  if (!e) { schliesseKammer(); return; }
  const bild = $('kammer-gross-bild');
  if (bild.dataset.id !== e.id) {
    bild.dataset.id = e.id;
    if (e.breite) bild.src = `/api/v1/kammer/${e.id}/vorschau`;
    else bild.removeAttribute('src');
  }
  const datum = new Date(e.datum);
  $('kammer-gross-titel').textContent = [
    e.name,
    datum.toLocaleString(GEBIET, { dateStyle: 'medium', timeStyle: 'short' }),
    e.modell,
    `${kammer.offen + 1} / ${kammer.eintraege.length}`,
  ].filter(Boolean).join(' · ');
  const gewaehlt = kammer.auswahl.has(e.id);
  $('kammer-gross-waehlen').textContent = gewaehlt ? t('✓ Ausgewählt (Leertaste)') : t('Auswählen (Leertaste)');
  $('kammer-gross-waehlen').classList.toggle('primaer', gewaehlt);
  // Das nächste schon holen, damit Blättern nicht wartet.
  const weiter = kammer.eintraege[kammer.offen + 1];
  if (weiter && weiter.breite) new Image().src = `/api/v1/kammer/${weiter.id}/vorschau`;
}

function blaettereKammer(schritt) {
  const neu = Math.min(Math.max(kammer.offen + schritt, 0), kammer.eintraege.length - 1);
  if (neu !== kammer.offen) { kammer.offen = neu; zeigeKammerGross(); }
}

$('kammer-alle').addEventListener('click', () => {
  if (kammer.auswahl.size === kammer.eintraege.length) kammer.auswahl.clear();
  else for (const e of kammer.eintraege) kammer.auswahl.add(e.id);
  zeichneKammer();
});
$('kammer-umkehren').addEventListener('click', () => {
  const neu = kammer.eintraege.map((e) => e.id).filter((id) => !kammer.auswahl.has(id));
  kammer.auswahl = new Set(neu);
  zeichneKammer();
});
$('kammer-freigeben').addEventListener('click', kammerFreigeben);
$('kammer-verwerfen').addEventListener('click', kammerVerwerfen);
$('kammer-erst').addEventListener('change', (e) => kammerSetzen(e.target.checked));
$('kammer-gross-zu').addEventListener('click', schliesseKammer);
$('kammer-gross-zurueck').addEventListener('click', () => blaettereKammer(-1));
$('kammer-gross-vor').addEventListener('click', () => blaettereKammer(1));
$('kammer-gross-waehlen').addEventListener('click', () => {
  const e = kammer.eintraege[kammer.offen];
  if (e) umschalteKammer(e.id);
});
document.addEventListener('keydown', (e) => {
  if (kammer.offen < 0) return;
  if (e.key === 'ArrowRight') { e.preventDefault(); blaettereKammer(1); }
  else if (e.key === 'ArrowLeft') { e.preventDefault(); blaettereKammer(-1); }
  else if (e.key === ' ') { e.preventDefault(); const x = kammer.eintraege[kammer.offen]; if (x) umschalteKammer(x.id); }
  else if (e.key === 'Escape') { e.preventDefault(); schliesseKammer(); }
});

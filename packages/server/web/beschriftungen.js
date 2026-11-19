'use strict';

function sammlungsFehler(fehler) {
  const texte = {
    pv_beschriftung_geaendert: 'Dieses Foto wurde geändert. Bitte erneut prüfen.',
    pv_beschriftung_mehrdeutig: 'Bitte eine gleichnamige Person auswählen.',
    pv_beschriftung_entschieden: 'Dieser Vorschlag wurde bereits entschieden.',
    pv_beschriftung_umfang: 'Zu viele offene Vorschläge. Bitte zuerst vorhandene Vorschläge prüfen.',
    pv_beschriftung_gesicht: 'Dieses Gesicht ist nicht mehr verfügbar. Bitte aktualisieren.',
  };
  return texte[fehler.message] ? t(texte[fehler.message]) : fehler.message;
}

function sammlungsDialog(titel) {
  const dialog = el('dialog', 'sammlungs-dialog');
  const inhalt = el('div');
  const fehler = el('p', 'meldung');
  fehler.setAttribute('role', 'alert');
  const schliessen = el('button', 'knopf', t('Schließen'));
  schliessen.type = 'button';
  schliessen.addEventListener('click', () => dialog.close());
  dialog.append(el('h2', null, t(titel)), inhalt, fehler, schliessen);
  dialog.addEventListener('close', () => dialog.remove(), { once: true });
  document.body.append(dialog);
  dialog.showModal();
  return { dialog, inhalt, fehler };
}

async function oeffneErinnerungsfilter() {
  const [e, p, a] = await Promise.all([
    api('/api/v1/einstellungen'), api('/api/v1/personen'), api('/api/v1/alben'),
  ]);
  const filter = e.erinnerungsfilter;
  if (!filter || ![1, 2].includes(filter.fassung)) throw new Error(t('Erinnerungsfilter kann nicht geladen werden.'));
  const { dialog, inhalt, fehler } = sammlungsDialog('Erinnerungen steuern');
  inhalt.append(el('p', null, t('Ausgewählte Personen, Alben und Zeiträume erscheinen nicht in automatischen Erinnerungen. Die Fotos bleiben in der Bibliothek.')));
  if (filter.beschaedigt) inhalt.append(el('p', 'meldung', t('Die gespeicherten Ausschlüsse sind nicht lesbar. Rückblicke bleiben gesperrt. Speichern ersetzt die Ausschlüsse durch die gewählte Auswahl.')));
  if (filter.zeitraeume.some((z) => !z.vonUtc || !z.bisUtc)) inhalt.append(el('p', 'meldung', t('Speichern bestätigt ältere Zeiträume nach der Zeitzone dieses Geräts. Bis dahin bleiben automatische Rückblicke gesperrt.')));
  const wahl = (titel, daten, gespeichert) => {
    inhalt.append(el('h3', null, t(titel)));
    const namen = new Map(daten.map((d) => [d.id, d.name || t('Ohne Namen')]));
    for (const id of gespeichert) if (!namen.has(id)) namen.set(id, t('Nicht mehr vorhanden'));
    const gruppe = el('div', 'sammlungs-wahl');
    const auswahl = new Set(gespeichert);
    for (const [id, name] of namen) {
      const label = el('label');
      const feld = el('input'); feld.type = 'checkbox'; feld.checked = auswahl.has(id);
      feld.addEventListener('change', () => feld.checked ? auswahl.add(id) : auswahl.delete(id));
      label.append(feld, document.createTextNode(name)); gruppe.append(label);
    }
    inhalt.append(gruppe);
    return auswahl;
  };
  const personen = wahl('Personen', p.personen, filter.personen);
  const alben = wahl('Alben', a.alben, filter.alben);
  inhalt.append(el('h3', null, t('Zeiträume')));
  const zeiten = el('div'); inhalt.append(zeiten);
  const zeitraum = (z = {}) => {
    const reihe = el('div', 'sammlungs-zeit');
    for (const key of ['von', 'bis']) {
      const label = el('label', null, t(key === 'von' ? 'Von' : 'Bis'));
      const f = el('input'); f.type = 'date'; f.required = true; f.value = z[key] || '';
      f.name = key; label.append(f); reihe.append(label);
    }
    const weg = el('button', 'knopf', t('Entfernen')); weg.type = 'button';
    weg.addEventListener('click', () => reihe.remove()); reihe.append(weg); zeiten.append(reihe);
  };
  for (const z of filter.zeitraeume) zeitraum(z);
  const hinzu = el('button', 'knopf', t('Zeitraum hinzufügen')); hinzu.type = 'button';
  hinzu.addEventListener('click', () => { if (zeiten.children.length < 50) zeitraum(); });
  const speichern = el('button', 'knopf primaer', t('Speichern')); speichern.type = 'button';
  speichern.addEventListener('click', async () => {
    const zeitraeume = [...zeiten.children].map((r) => ({ von: r.querySelector('[name=von]').value, bis: r.querySelector('[name=bis]').value }));
    if (zeitraeume.some((z) => !z.von || !z.bis || z.von > z.bis)) { fehler.textContent = t('Bitte gültige Zeiträume auswählen.'); return; }
    speichern.disabled = true;
    try {
      const grenze = (s, folgetag = false) => {
        const [y, m, d] = s.split('-').map(Number);
        const zeit = new Date(0);
        zeit.setHours(0, 0, 0, 0); zeit.setFullYear(y, m - 1, d + (folgetag ? 1 : 0));
        return zeit.toISOString();
      };
      const benutzt = new Set();
      const grenzen = zeitraeume.map((z) => {
        const i = filter.zeitraeume.findIndex((a, index) => !benutzt.has(index) && a.von === z.von && a.bis === z.bis && a.vonUtc && a.bisUtc);
        if (i >= 0) { benutzt.add(i); return filter.zeitraeume[i]; }
        return { ...z, vonUtc: grenze(z.von), bisUtc: grenze(z.bis, true) };
      });
      await befehl('erinnerungsfilterSetzen', { filter: { fassung: 2, personen: [...personen], alben: [...alben], zeitraeume: grenzen } });
      dialog.close();
    } catch (x) { fehler.textContent = sammlungsFehler(x); speichern.disabled = false; }
  });
  inhalt.append(hinzu, speichern);
}

async function oeffneBeschriftungen(basis, aufnahme) {
  const route = `${basis}/beschriftungen`;
  const { dialog, inhalt, fehler } = sammlungsDialog('Beschriftungsvorschläge');
  let seite = 0;
  const laden = async () => {
    const parameter = new URLSearchParams({ seite: String(seite), ...(aufnahme ? { aufnahme } : {}) });
    const d = await api(`${route}?${parameter}`);
    if (!dialog.isConnected) return;
    inhalt.replaceChildren(el('p', null, t('Schlage Personen, Orte oder ein ungefähres Aufnahmejahr vor. Der Besitzer prüft und übernimmt die Angaben.')));
    const artText = (art) => t(({ person: 'Person', ort: 'Ort', jahr: 'Ungefähres Aufnahmejahr' })[art]);
    for (const v of d.vorschlaege) {
      const zeile = el('section', 'beschriftung');
      zeile.append(el('h3', null, `${artText(v.art)}: ${v.wert}`),
        el('p', 'leise', `${v.von} · ${datumZeit.format(new Date(v.angelegt))} · ${t(v.zustand)}`));
      if (d.besitzer) zeile.append(el('p', null, `${t('Aktuell')}: ${v.aktuell || '—'}`));
      if (!aufnahme) {
        const foto = el('button', 'knopf', t('Foto prüfen')); foto.type = 'button';
        foto.addEventListener('click', () => oeffneBeschriftungen(basis, v.aufnahme).catch((x) => { fehler.textContent = sammlungsFehler(x); }));
        zeile.append(foto);
      }
      if (d.besitzer && v.zustand === 'offen') {
        const person = el('select');
        let gleiche = (d.personen || []).filter((p) => p.name === v.wert);
        if (v.art === 'person') {
          const leer = el('option', null, t('Person auswählen')); leer.value = ''; person.append(leer);
          for (const p of gleiche) { const o = el('option', null, `${p.name} (${p.id.slice(0, 8)})`); o.value = p.id; person.append(o); }
          person.setAttribute('aria-label', t('Person auswählen')); zeile.append(person);
          if (d.personenMehr) {
            let personenseite = 0;
            const weitere = el('button', 'knopf', t('Weitere gleichnamige Personen')); weitere.type = 'button';
            weitere.addEventListener('click', async () => {
              weitere.disabled = true;
              try {
                const params = new URLSearchParams({ seite, personenname: v.wert, personenseite });
                if (aufnahme) params.set('aufnahme', aufnahme);
                const neu = await api(`${route}?${params}`);
                const bekannt = new Set(gleiche.map((p) => p.id));
                for (const p of neu.personen) {
                  if (bekannt.has(p.id)) continue;
                  gleiche.push(p); bekannt.add(p.id);
                  const o = el('option', null, `${p.name} (${p.id.slice(0, 8)})`); o.value = p.id; person.append(o);
                }
                personenseite++; weitere.hidden = !neu.personenMehr;
              } catch (x) { fehler.textContent = sammlungsFehler(x); }
              finally { weitere.disabled = false; }
            });
            zeile.append(weitere);
          }
        }
        for (const annehmen of [true, false]) {
          const b = el('button', 'knopf', t(annehmen ? 'Annehmen' : 'Ablehnen')); b.type = 'button';
          b.addEventListener('click', async () => {
            if (annehmen && gleiche.length > 1 && !person.value) { fehler.textContent = t('Person auswählen'); return; }
            zeile.querySelectorAll('button').forEach((k) => { k.disabled = true; });
            try { await api(`${route}/${encodeURIComponent(v.id)}`, { methode: 'POST', json: { annehmen, stand: v.stand, ...(person.value ? { person: person.value } : {}) } }); await laden(); }
            catch (x) { fehler.textContent = sammlungsFehler(x); await laden(); }
          });
          zeile.append(b);
        }
      }
      inhalt.append(zeile);
    }
    for (const [an, richtung] of [[seite > 0, -1], [d.mehr, 1]]) {
      if (!an) continue;
      const b = el('button', 'knopf', t(richtung < 0 ? 'Vorherige Vorschläge' : 'Weitere Vorschläge')); b.type = 'button';
      b.addEventListener('click', async () => { b.disabled = true; seite += richtung; try { await laden(); } catch (x) { fehler.textContent = sammlungsFehler(x); b.disabled = false; } });
      inhalt.append(b);
    }
    if (!aufnahme) return;
    const form = el('form');
    const bild = el('div', 'beschriftung-bild');
    const img = el('img'); img.alt = t('Foto');
    img.src = `${basis}/aufnahmen/${encodeURIComponent(aufnahme)}/miniatur`;
    if (basis.startsWith('/api/v1/alben/')) img.src = miniaturUrl(aufnahme);
    bild.append(img);
    for (const [i, f] of d.gesichter.entries()) {
      const marke = el('span', null, String(i + 1));
      Object.assign(marke.style, { left: `${f.x * 100}%`, top: `${f.y * 100}%`, width: `${f.breite * 100}%`, height: `${f.hoehe * 100}%` });
      bild.append(marke);
    }
    const art = el('select'); art.setAttribute('aria-label', t('Angabe'));
    for (const a of ['ort', 'jahr', ...(d.gesichter.length ? ['person'] : [])]) { const o = el('option', null, artText(a)); o.value = a; art.append(o); }
    const gesicht = el('select'); gesicht.hidden = true; gesicht.setAttribute('aria-label', t('Gesicht'));
    for (const [i, f] of d.gesichter.entries()) { const o = el('option', null, `${t('Gesicht')} ${i + 1}`); o.value = f.id; gesicht.append(o); }
    const wert = el('input'); wert.required = true; wert.maxLength = 200; wert.setAttribute('aria-label', t('Vorschlag'));
    art.addEventListener('change', () => { gesicht.hidden = art.value !== 'person'; wert.type = art.value === 'jahr' ? 'number' : 'text'; wert.min = '1'; wert.max = '9999'; });
    const senden = el('button', 'knopf primaer', t('Vorschlagen')); senden.type = 'submit';
    form.append(bild, art, gesicht, wert, senden);
    form.addEventListener('submit', async (e) => {
      e.preventDefault(); senden.disabled = true;
      try { await api(route, { methode: 'POST', json: { aufnahme, art: art.value, wert: wert.value.trim(), ...(art.value === 'person' ? { gesicht: gesicht.value } : {}) } }); await laden(); }
      catch (x) { fehler.textContent = sammlungsFehler(x); senden.disabled = false; }
    });
    inhalt.append(form);
  };
  try { await laden(); } catch (x) { fehler.textContent = sammlungsFehler(x); }
}

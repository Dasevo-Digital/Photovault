'use strict';
// --- Rückblick, Jahresrückblick und Kalender (Issue #185) ------------------
//
// Wie am Rechner und auf dem Telefon: Familientage aus dem Stammbaum,
// „Heute vor x Jahren“, die Erinnerungen der letzten zwei Wochen (zum
// Merken), die schönsten Reisen und das Jahr in Zahlen und Bildern; dazu
// der Kalender mit Jahren und Monaten. Gerechnet wird im Kern
// (rueckblickseite.dart), hier nur gezeigt. Erst bei Bedarf geladen.

const heuteText = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const datumLang = new Intl.DateTimeFormat(GEBIET, { day: 'numeric', month: 'long', year: 'numeric' });
const monatLang = new Intl.DateTimeFormat(GEBIET, { month: 'long' });

const vorJahren = (n) => (n === 1 ? t('vor einem Jahr') : t('vor {n} Jahren', { n }));

// Ein Streifen Miniaturen; ein Klick öffnet die Reihe im Betrachter.
function rbStreifen(aufnahmen, titel) {
  const reihe = el('div', 'rb-streifen');
  aufnahmen.forEach((a, i) => {
    const b = el('button', 'rb-bild');
    b.type = 'button';
    b.title = titel;
    const img = el('img');
    img.loading = 'lazy';
    img.alt = '';
    img.src = miniaturUrl(a.id);
    b.append(img);
    b.addEventListener('click', () => {
      zeigeBereich(['raster']);
      zeigeListe({ aufnahmen }, titel);
      oeffne(i);
    });
    reihe.append(b);
  });
  return reihe;
}

function rbAbschnitt(titel, ...inhalt) {
  const box = el('div', 'rb-abschnitt');
  box.append(el('h3', null, titel), ...inhalt);
  return box;
}

function familientagSatz(f) {
  const name = f.namen.join(' & ');
  switch (f.art) {
    case 'geburtstag': return f.verstorben ? t('{name} wäre {jahre} geworden', { name, jahre: f.jahre }) : t('{name} wird {jahre}', { name, jahre: f.jahre });
    case 'todestag': return f.jahre === 1 ? t('{name} starb vor einem Jahr', { name }) : t('{name} starb vor {jahre} Jahren', { name, jahre: f.jahre });
    default: return t('{jahre}. Hochzeitstag von {namen}', { jahre: f.jahre, namen: name });
  }
}
// Ganze Sätze als Schlüssel: „Morgen“ allein steht im Wörterbuch schon als
// Tageszeit.
const wannSatz = (n, satz) => (n === 0 ? t('Heute: {satz}', { satz }) : n === 1 ? t('Morgen: {satz}', { satz }) : t('In {n} Tagen: {satz}', { n, satz }));

async function zeigeRueckblick() {
  markiereNav('rueckblick');
  zeigeBereich(['rueckblick']);
  const ziel = $('rueckblick-inhalt');
  ziel.replaceChildren(el('p', 'leise', t('Lade …')));
  const [d, heute] = await Promise.all([
    api(`/api/v1/rueckblick?heute=${heuteText()}`),
    api('/api/v1/erinnerungen').catch(() => null),
  ]);
  const teile = [];

  // Das Jahr in Zahlen und Bildern – als Einstieg ganz oben.
  const jahr = el('a', 'rb-jahr');
  jahr.href = `#/jahresrueckblick/${d.jahr}`;
  jahr.append(el('strong', null, t('Dein Jahr {jahr}', { jahr: d.jahr })), el('span', 'leise', t('In Zahlen und Bildern – mit Personen, Reisen und den besten Fotos')));
  teile.push(jahr);

  if (d.familientage.length) {
    const box = el('div', 'rb-liste');
    for (const f of d.familientage) {
      const eintrag = el('div', 'rb-eintrag');
      eintrag.append(el('div', 'rb-kopf', wannSatz(f.inTagen, familientagSatz(f))));
      if (f.aufnahmen.length) eintrag.append(rbStreifen(f.aufnahmen, familientagSatz(f)));
      box.append(eintrag);
    }
    teile.push(rbAbschnitt(t('Familientage'), box));
  }

  if (heute && heute.gruppen.length) {
    const box = el('div', 'rb-liste');
    for (const g of heute.gruppen) {
      const titel = heute.art === 'monat' ? t('Diesen Monat {wann}', { wann: vorJahren(g.jahreHer) }) : t('Heute {wann}', { wann: vorJahren(g.jahreHer) });
      const eintrag = el('div', 'rb-eintrag');
      eintrag.append(el('div', 'rb-kopf', titel), rbStreifen(g.aufnahmen, titel));
      box.append(eintrag);
    }
    teile.push(rbAbschnitt(t('Vor x Jahren'), box));
  }

  if (d.gemerkt.length) {
    const box = el('div', 'rb-liste');
    for (const g of d.gemerkt) {
      const eintrag = el('div', 'rb-eintrag');
      const kopf = el('div', 'rb-kopf');
      const weg = el('button', 'rb-knopf', t('Nicht mehr merken'));
      weg.type = 'button';
      weg.addEventListener('click', async () => {
        try { await befehl('erinnerungVergessen', { erinnerungId: g.id }); await zeigeRueckblick(); } catch (x) { meldung(x.message); }
      });
      kopf.append(el('span', null, g.titel), weg);
      eintrag.append(kopf, rbStreifen(g.aufnahmen, g.titel));
      box.append(eintrag);
    }
    teile.push(rbAbschnitt(t('Gemerkt'), box));
  }

  const letzte = el('div', 'rb-liste');
  const gemerkteIds = new Set(d.gemerkt.map((g) => g.id));
  for (const l of d.letzte) {
    const [j, m, tg] = l.tag.split('-').map(Number);
    const titel = `${datumLang.format(new Date(j - l.jahreHer, m - 1, tg))} · ${vorJahren(l.jahreHer)}`;
    const eintrag = el('div', 'rb-eintrag');
    const kopf = el('div', 'rb-kopf');
    kopf.append(el('span', null, titel));
    if (!gemerkteIds.has(l.kennung)) {
      const merken = el('button', 'rb-knopf', t('Merken'));
      merken.type = 'button';
      merken.addEventListener('click', async () => {
        try {
          await befehl('erinnerungMerken', { erinnerungId: l.kennung, titel, tag: new Date(j - l.jahreHer, m - 1, tg).toISOString(), ids: l.aufnahmen.map((a) => a.id) });
          await zeigeRueckblick();
        } catch (x) { meldung(x.message); }
      });
      kopf.append(merken);
    }
    eintrag.append(kopf, rbStreifen(l.aufnahmen, titel));
    letzte.append(eintrag);
  }
  if (!d.letzte.length) letzte.append(el('p', 'leise', t('An keinem der letzten vierzehn Tage gibt es Fotos aus früheren Jahren.')));
  teile.push(rbAbschnitt(t('Die letzten zwei Wochen'), letzte));

  if (d.reisen.length) {
    const box = el('div', 'rb-karten');
    for (const r of d.reisen) {
      const n = r.lieblinge;
      box.append(karte(null, r.name, `${new Date(r.von).getFullYear()} · ${n === 1 ? t('1 Lieblingsfoto') : t('{n} Lieblingsfotos', { n })}`, `#/reisen/${encodeURIComponent(r.id)}`));
    }
    teile.push(rbAbschnitt(t('Die schönsten Reisen'), box));
  }
  ziel.replaceChildren(...teile);
}

async function zeigeJahresrueckblick(jahrText) {
  markiereNav('rueckblick');
  zeigeBereich(['rueckblick']);
  const jahr = Number(jahrText) || new Date().getFullYear();
  const ziel = $('rueckblick-inhalt');
  ziel.replaceChildren(el('p', 'leise', t('Lade …')));
  const d = await api(`/api/v1/jahresrueckblick/${jahr}?sprache=${SPRACHE}`);
  const kopf = el('div', 'rb-jahrkopf');
  const zurueck = el('a', 'rb-knopf', '‹');
  zurueck.href = `#/jahresrueckblick/${jahr - 1}`;
  zurueck.title = t('Vorjahr');
  const vor = el('a', 'rb-knopf', '›');
  vor.href = `#/jahresrueckblick/${jahr + 1}`;
  vor.title = t('Folgejahr');
  if (jahr >= new Date().getFullYear()) vor.classList.add('aus');
  kopf.append(zurueck, el('h3', null, t('Dein Jahr {jahr}', { jahr })), vor);
  const teile = [kopf];
  if (d.fotos + d.videos === 0) {
    teile.push(el('p', 'leise', t('Aus {jahr} gibt es keine Aufnahmen.', { jahr })));
    ziel.replaceChildren(...teile);
    return;
  }
  const zahlen = el('div', 'kennzahlen');
  zahlen.append(
    kennzahl(zahl.format(d.fotos), t('Fotos')),
    kennzahl(zahl.format(d.videos), t('Videos')),
    kennzahl(zahl.format(d.tage), t('Tage mit Fotos')),
    kennzahl(zahl.format(d.laender.length), t('Länder')),
    kennzahl(zahl.format(d.orte), t('Orte')),
  );
  if (d.staerksterMonat) zahlen.append(kennzahl(monatLang.format(new Date(jahr, d.staerksterMonat - 1, 1)), t('stärkster Monat')));
  teile.push(zahlen);
  const monate = el('div', 'balken');
  balken(monate, d.jeMonat.map((n, i) => [i + 1, n]), (m) => monatsname.format(new Date(2000, m - 1, 1)));
  teile.push(monate);
  if (d.laender.length) teile.push(el('p', 'leise', d.laender.join(' · ')));
  if (d.auswahl.length) {
    const raster = el('div', 'rb-auswahl');
    d.auswahl.forEach((a, i) => {
      const b = el('button', 'rb-bild');
      b.type = 'button';
      const img = el('img');
      img.loading = 'lazy';
      img.alt = '';
      img.src = miniaturUrl(a.id);
      b.append(img);
      b.addEventListener('click', () => { zeigeBereich(['raster']); zeigeListe({ aufnahmen: d.auswahl }, t('Dein Jahr {jahr}', { jahr })); oeffne(i); });
      raster.append(b);
    });
    teile.push(rbAbschnitt(t('Die besten Fotos'), raster));
  }
  if (d.personen.length) {
    const box = el('div', 'rb-karten');
    for (const p of d.personen.slice(0, 12)) {
      const k = karte(p.bild ? dateiUrl(p.bild) : null, p.name, anzahlText(p.anzahl), `#/personen/${encodeURIComponent(p.id)}`);
      k.classList.add('person');
      box.append(k);
    }
    teile.push(rbAbschnitt(t('Am häufigsten dabei'), box));
  }
  if (d.reisen.length) {
    const box = el('div', 'rb-karten');
    for (const r of d.reisen) box.append(karte(null, r.name, datumLang.format(new Date(r.von)), `#/reisen/${encodeURIComponent(r.id)}`));
    teile.push(rbAbschnitt(t('Reisen'), box));
  }
  ziel.replaceChildren(...teile);
}

async function zeigeKalender(jahr, monat) {
  markiereNav('kalender');
  if (jahr && monat) {
    const d = await api(`/api/v1/kalender/${encodeURIComponent(jahr)}/${encodeURIComponent(monat)}`);
    zeigeBereich(['raster']);
    zeigeListe({ aufnahmen: d.aufnahmen }, `${monatLang.format(new Date(d.jahr, d.monat - 1, 1))} ${d.jahr}`);
    return;
  }
  zeigeBereich(['karten']);
  $('karten').replaceChildren();
  if (jahr) {
    const d = await api(`/api/v1/kalender/${encodeURIComponent(jahr)}`);
    $('karten-titel').textContent = String(d.jahr);
    const rb = el('a', 'albumkarte rb-jahrkarte');
    rb.href = `#/jahresrueckblick/${d.jahr}`;
    rb.append(el('div', 'titel', t('Dein Jahr {jahr}', { jahr: d.jahr })), el('div', 'leise klein', t('In Zahlen und Bildern – mit Personen, Reisen und den besten Fotos')));
    for (const m of d.monate) {
      $('karten').append(karte(m.titelbild ? miniaturUrl(m.titelbild.id) : null, monatLang.format(new Date(d.jahr, m.nummer - 1, 1)), anzahlText(m.anzahl), `#/kalender/${d.jahr}/${m.nummer}`));
    }
    $('karten').append(rb);
    return;
  }
  $('karten-titel').textContent = t('Kalender');
  const d = await api('/api/v1/kalender');
  if (!d.jahre.length) $('karten').append(el('p', 'leise', t('Noch keine Fotos oder Videos in der Bibliothek.')));
  for (const j of d.jahre) {
    $('karten').append(karte(j.titelbild ? miniaturUrl(j.titelbild.id) : null, String(j.nummer), anzahlText(j.anzahl), `#/kalender/${j.nummer}`));
  }
}

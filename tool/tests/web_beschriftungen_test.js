'use strict';

// Kleiner DOM-Vertrag für die Dialoglogik. Bilder und Layout bleiben der
// Oberfläche vorbehalten; geprüft werden Eingaben, Anfragen und Fehler.
class Knoten {
  constructor(tag) { this.tag = tag; this.children = []; this.events = {}; this.style = {}; this.attrs = {}; this._text = ''; }
  get isConnected() { return this === document.body || !!(this.parent && this.parent.isConnected); }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(''); }
  set textContent(s) { this._text = String(s); this.children = []; }
  get innerHTML() { throw Error('HTML darf nicht eingesetzt werden'); }
  set innerHTML(_) { throw Error('HTML darf nicht eingesetzt werden'); }
  get value() { return this._value === undefined ? (this.tag === 'select' ? (this.children[0]?.value || '') : '') : this._value; }
  set value(v) { this._value = String(v); }
  append(...nodes) { for (const n of nodes) { n.parent = this; this.children.push(n); } }
  replaceChildren(...nodes) { this.children = []; this._text = ''; this.append(...nodes); }
  addEventListener(name, f) { (this.events[name] ||= []).push(f); }
  async fire(name) { for (const f of this.events[name] || []) await f({ preventDefault() {} }); }
  setAttribute(k, v) { this.attrs[k] = v; }
  remove() { if (this.parent) this.parent.children = this.parent.children.filter((n) => n !== this); this.parent = null; }
  showModal() { this.open = true; }
  close() { this.open = false; return this.fire('close'); }
  querySelectorAll(selector) {
    const name = /^\[name=(.+)\]$/.exec(selector);
    const test = (n) => name ? n.name === name[1] : n.tag === selector;
    return this.children.flatMap((n) => [...(test(n) ? [n] : []), ...n.querySelectorAll(selector)]);
  }
  querySelector(s) { return this.querySelectorAll(s)[0]; }
}
const document = { body: new Knoten('body'), createElement: (tag) => new Knoten(tag), createTextNode: (text) => { const n = new Knoten('#text'); n.textContent = text; return n; } };
const el = (tag, cls, text) => { const n = document.createElement(tag); n.className = cls || ''; if (text !== undefined) n.textContent = text; return n; };
const assert = (bedingung, text) => { if (!bedingung) throw Error(text); };
const button = (text) => { const b = document.body.querySelectorAll('button').find((n) => n.textContent === text); assert(b, `Knopf fehlt: ${text}`); return b; };
const quelle = typeof require === 'function' ? require('fs').readFileSync('packages/server/web/beschriftungen.js', 'utf8') : readFile('packages/server/web/beschriftungen.js');
const Parameter = typeof URLSearchParams === 'function' ? URLSearchParams : class {
  constructor(werte) { this.werte = werte; }
  toString() { return Object.entries(this.werte).map(([k,v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&'); }
};
const lade = new Function('el', 'api', 'befehl', 'document', 't', 'datumZeit', 'miniaturUrl', 'URLSearchParams', quelle + '\nreturn {oeffneErinnerungsfilter,oeffneBeschriftungen};');

(async () => {
  let filter, besitzer = true, konflikt = false;
  let v = { id: 'v', aufnahme: 'foto', von: '<img src=x>', angelegt: '2026-11-19T10:00:00Z', art: 'ort', wert: '<script>Testort</script>', aktuell: 'Alt', stand: 'geprueft', zustand: 'offen' };
  const anfragen = [];
  const api = async (pfad, o = {}) => {
    anfragen.push([pfad, o]);
    if (pfad.endsWith('/einstellungen')) return { erinnerungsfilter: { fassung: 1, personen: [], alben: [], zeitraeume: [] } };
    if (pfad.endsWith('/personen')) return { personen: [{ id: 'p', name: '<img src=x>' }] };
    if (pfad.endsWith('/alben')) return { alben: [{ id: 'al', name: 'Album' }] };
    if (o.methode === 'POST') {
      if (konflikt) throw Error('pv_beschriftung_geaendert');
      if (pfad.endsWith('/v')) { assert(o.json.stand === 'geprueft', 'Stand fehlt'); v = { ...v, zustand: o.json.annehmen ? 'angenommen' : 'abgelehnt' }; }
      return {};
    }
    return { besitzer, personen: [], gesichter: [], vorschlaege: [v], mehr: false };
  };
  const dialoge = lade(el, api, async (_, j) => { filter = j.filter; }, document, (s) => s, new Intl.DateTimeFormat('de'), () => 'bild', Parameter);
  await dialoge.oeffneErinnerungsfilter();
  const person = document.body.querySelectorAll('input')[0]; person.checked = true; await person.fire('change');
  await button('Zeitraum hinzufügen').fire('click');
  await button('Speichern').fire('click');
  assert(!filter, 'Leerer Zeitraum darf nicht gespeichert werden');
  document.body.querySelector('[name=von]').value = '2020-01-01'; document.body.querySelector('[name=bis]').value = '2020-01-31';
  await button('Speichern').fire('click');
  assert(filter.personen[0] === 'p' && filter.zeitraeume[0].bis === '2020-01-31', 'Auswahl verloren');
  assert(!document.body.querySelector('dialog'), 'Gespeicherter Dialog bleibt offen');

  await dialoge.oeffneBeschriftungen('/api/v1/alben/al');
  assert(document.body.textContent.includes('<script>Testort</script>'), 'Vorschlag nicht als Text dargestellt');
  assert(document.body.querySelectorAll('script').length === 0, 'Metadaten wurden zu HTML');
  konflikt = true;
  await button('Annehmen').fire('click');
  assert(v.zustand === 'offen', 'Konflikt wurde angenommen');
  assert(document.body.textContent.includes('Dieses Foto wurde geändert'), 'Verständlicher Konflikthinweis fehlt');
  konflikt = false; await button('Annehmen').fire('click');
  assert(v.zustand === 'angenommen', 'Annahme fehlt');
  assert(!document.body.querySelectorAll('button').some((b) => b.textContent === 'Annehmen'), 'Erledigte Vorschläge bleiben entscheidbar');
  await button('Schließen').fire('click');

  besitzer = false;
  await dialoge.oeffneBeschriftungen('/api/v1/geteilt/g', 'foto');
  assert(!document.body.querySelectorAll('button').some((b) => ['Annehmen', 'Ablehnen'].includes(b.textContent)), 'Empfänger bekommt Besitzeraktionen');
  const art = document.body.querySelector('select'); art.value = 'jahr'; await art.fire('change');
  const wert = document.body.querySelector('input'); wert.value = '1985';
  await document.body.querySelector('form').fire('submit');
  const post = anfragen.filter((a) => a[1].methode === 'POST').pop();
  assert(post[0] === '/api/v1/geteilt/g/beschriftungen' && post[1].json.wert === '1985' && post[1].json.art === 'jahr', 'Vorschlag geht an falsches Album oder verliert Angaben');
  await button('Schließen').fire('click');
})().then(() => {
  if (typeof print === 'function') print('Dialogregressionen bestanden'); else console.log('Dialogregressionen bestanden');
}, (e) => {
  if (typeof print === 'function') { print(`${e}\n${e.stack || ''}`); quit(1); }
  else { console.error(e); process.exitCode = 1; }
});

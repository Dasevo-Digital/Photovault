'use strict';

// --- Entwickeln im Browser ---------------------------------------------------
//
// Dieselbe Rechnung wie unter Linux und Windows (lib/services/develop_render
// .dart): ein Durchgang für Belichtung, Weissabgleich, Kontrast, Schatten,
// Lichter, Tonkurve und Farbmischer, danach die Stufen, die Nachbarpixel
// brauchen – Schärfe, Rauschminderung, Klarheit, Vignette. Die Shader sind
// aus shaders/develop_*.frag übertragen; Tonkurve und Farbwürfel kommen als
// fertige Texturen vom Server, gebaut vom selben Code wie am Rechner.
//
// Koordinaten: Texturen werden ohne Spiegelung geladen, Zeile 0 ist oben.
// So liest readPixels das Ergebnis in der Reihenfolge, die ein Bild hat;
// nur die Kopie auf den Bildschirm dreht die y-Achse um.

const ENTW_ECKE = `#version 300 es
in vec2 p;
void main() { gl_Position = vec4(p, 0.0, 1.0); }`;

const ENTW_FARBRAUM = `
vec3 srgbToLinear(vec3 c) {
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 linearToSrgb(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}`;

// shaders/develop_adjustments.frag
const ENTW_ANPASSUNG = `#version 300 es
precision highp float;
uniform vec2 uSize;
uniform vec2 uQuelle;
uniform float uExposure, uTemperature, uTint, uContrast, uShadows, uHighlights;
uniform float uApplyWhiteBalance, uCurveActive, uMixerActive, uCubeSize;
uniform sampler2D uTexture, uCurveLut, uColorCube;
out vec4 fragColor;
${ENTW_FARBRAUM}
vec3 whiteBalanceGain(float kelvin, float tint) {
  float t = clamp(kelvin, 2000.0, 12000.0) / 6500.0;
  return vec3(pow(1.0 / t, 0.55), 1.0 - clamp(tint, -100.0, 100.0) / 400.0, pow(t, 0.55));
}
vec3 tonwertkurve(vec3 c) {
  return vec3(
    texture(uCurveLut, vec2((c.r * 255.0 + 0.5) / 256.0, 0.5)).r,
    texture(uCurveLut, vec2((c.g * 255.0 + 0.5) / 256.0, 0.5)).g,
    texture(uCurveLut, vec2((c.b * 255.0 + 0.5) / 256.0, 0.5)).b);
}
vec3 wuerfelScheibe(float scheibe, vec2 rg) {
  float breite = uCubeSize * uCubeSize;
  float x = scheibe * uCubeSize + rg.r * (uCubeSize - 1.0) + 0.5;
  float y = rg.g * (uCubeSize - 1.0) + 0.5;
  return texture(uColorCube, vec2(x / breite, y / uCubeSize)).rgb;
}
vec3 farbwuerfel(vec3 c) {
  float bf = clamp(c.b, 0.0, 1.0) * (uCubeSize - 1.0);
  float unten = floor(bf);
  float oben = min(unten + 1.0, uCubeSize - 1.0);
  vec2 rg = clamp(c.rg, 0.0, 1.0);
  return mix(wuerfelScheibe(unten, rg), wuerfelScheibe(oben, rg), bf - unten);
}
void main() {
  vec2 uv = gl_FragCoord.xy / uSize;
  vec4 quelle = texture(uTexture, uv);
  vec3 c = srgbToLinear(quelle.rgb);
  c *= pow(2.0, uExposure);
  if (uApplyWhiteBalance > 0.5) c *= whiteBalanceGain(uTemperature, uTint);
  c = (c - 0.5) * (1.0 + uContrast) + 0.5;
  if (abs(uShadows) > 0.001) {
    float luma = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
    c += uShadows * 0.35 * (1.0 - smoothstep(0.0, 0.6, luma));
  }
  if (abs(uHighlights) > 0.001) {
    float luma = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
    c += uHighlights * 0.35 * smoothstep(0.4, 1.0, luma);
  }
  vec3 srgb = linearToSrgb(clamp(c, 0.0, 1.0));
  if (uCurveActive > 0.5) srgb = tonwertkurve(srgb);
  if (uMixerActive > 0.5) srgb = farbwuerfel(srgb);
  fragColor = vec4(srgb, quelle.a);
}`;

// shaders/develop_weich.frag
const ENTW_WEICH = `#version 300 es
precision highp float;
uniform vec2 uSize;
uniform vec2 uRichtung;
uniform float uSigma;
uniform sampler2D uBild;
out vec4 fragColor;
${ENTW_FARBRAUM}
const int kHalb = 32;
void main() {
  vec2 pos = gl_FragCoord.xy;
  float schritt = max(1.0, 3.0 * uSigma / float(kHalb));
  float reichweite = ceil(3.0 * uSigma / schritt);
  float nenner = 2.0 * uSigma * uSigma;
  vec3 summe = srgbToLinear(texture(uBild, pos / uSize).rgb);
  float gewichte = 1.0;
  for (int i = 1; i <= kHalb; i++) {
    if (float(i) > reichweite) break;
    float d = float(i) * schritt;
    float g = exp(-(d * d) / nenner);
    vec2 vor = clamp(pos + uRichtung * d, vec2(0.5), uSize - vec2(0.5));
    vec2 zurueck = clamp(pos - uRichtung * d, vec2(0.5), uSize - vec2(0.5));
    summe += g * (srgbToLinear(texture(uBild, vor / uSize).rgb) + srgbToLinear(texture(uBild, zurueck / uSize).rgb));
    gewichte += 2.0 * g;
  }
  fragColor = vec4(linearToSrgb(summe / gewichte), texture(uBild, pos / uSize).a);
}`;

// shaders/develop_nachbarn.frag
const ENTW_NACHBARN = `#version 300 es
precision highp float;
uniform vec2 uSize;
uniform float uSchaerfe, uRauschen, uKlarheit, uVignette;
uniform sampler2D uBild, uWeich;
out vec4 fragColor;
${ENTW_FARBRAUM}
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
void main() {
  vec2 pos = gl_FragCoord.xy;
  vec2 uv = pos / uSize;
  vec4 quelle = texture(uBild, uv);
  vec3 x = srgbToLinear(quelle.rgb);
  vec3 weich = srgbToLinear(texture(uWeich, uv).rgb);
  if (uSchaerfe != 0.0) x += vec3(uSchaerfe * (luma(x) - luma(weich)));
  if (uRauschen > 0.0) {
    vec3 detail = x - weich;
    float rauschen = 1.0 - smoothstep(0.7 * uRauschen, 1.3 * uRauschen, abs(luma(detail)));
    x += detail * (-rauschen + (1.0 - rauschen) * 0.4);
  }
  if (uKlarheit != 0.0) x += uKlarheit * (x - weich);
  if (uVignette != 0.0) {
    float r = length(pos - 0.5 * uSize) / (0.5 * min(uSize.x, uSize.y));
    float r2 = r * r;
    x *= exp(-uVignette * (r2 * (0.2235 + r2 * (0.01083 + r2 * 0.0016))));
  }
  fragColor = vec4(linearToSrgb(clamp(x, 0.0, 1.0)), quelle.a);
}`;

// Kopie auf den Bildschirm – hier und nur hier steht das Bild auf dem Kopf.
const ENTW_ZEIGEN = `#version 300 es
precision highp float;
uniform vec2 uSize;
uniform sampler2D uBild;
out vec4 fragColor;
void main() {
  vec2 uv = gl_FragCoord.xy / uSize;
  fragColor = texture(uBild, vec2(uv.x, 1.0 - uv.y));
}`;

// Die Regler wie am Rechner (bedienfelder.dart), mit Spaltennamen der
// Tabelle develop_settings.
const ENTW_REGLER = [
  { spalte: 'exposure', name: 'Belichtung', min: -3, max: 3, schritt: 0.01 },
  { spalte: 'contrast', name: 'Kontrast', min: -1, max: 1, schritt: 0.01 },
  { spalte: 'highlights', name: 'Lichter', min: -1, max: 1, schritt: 0.01 },
  { spalte: 'shadows', name: 'Schatten', min: -1, max: 1, schritt: 0.01 },
  { spalte: 'temperature', name: 'Farbtemperatur', min: 2000, max: 12000, schritt: 50, vorgabe: 6500, wb: true },
  { spalte: 'tint', name: 'Tönung', min: -100, max: 100, schritt: 1, wb: true },
  { spalte: 'clarity', name: 'Klarheit', min: -1, max: 1, schritt: 0.01 },
  { spalte: 'sharpness', name: 'Schärfe', min: 0, max: 1, schritt: 0.01 },
  { spalte: 'noise_reduction', name: 'Rauschminderung', min: 0, max: 1, schritt: 0.01 },
  { spalte: 'vignette', name: 'Vignettierung', min: -1, max: 1, schritt: 0.01 },
];

// develop_nachbarn.dart
const ENTW_SCHAERFE_SIGMA = 1.69;
const ENTW_RAUSCHEN_SIGMA = 1.2;
const entwKlarheitSigma = (b, h) => (20 * Math.max(b, h)) / 1600;
const entwKlarheitStaerke = (c) => (c > 0 ? 1.5 * c : 0.5 * c);

let entw = null;
let entwK = null;

function entwFehler(text) {
  $('entw-hinweis').textContent = text;
}

function entwKontext() {
  const leinwand = $('entw-leinwand');
  const gl = leinwand.getContext('webgl2', { preserveDrawingBuffer: true, premultipliedAlpha: false });
  if (!gl) return null;
  const programm = (quelle) => {
    const p = gl.createProgram();
    for (const [art, text] of [[gl.VERTEX_SHADER, ENTW_ECKE], [gl.FRAGMENT_SHADER, quelle]]) {
      const s = gl.createShader(art);
      gl.shaderSource(s, text);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      gl.attachShader(p, s);
    }
    gl.bindAttribLocation(p, 0, 'p');
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const orte = {};
    const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const name = gl.getActiveUniform(p, i).name;
      orte[name] = gl.getUniformLocation(p, name);
    }
    return { p, orte };
  };
  // Ein Dreieck, das die ganze Fläche deckt.
  const puffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, puffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
  return {
    gl,
    anpassung: programm(ENTW_ANPASSUNG),
    weich: programm(ENTW_WEICH),
    nachbarn: programm(ENTW_NACHBARN),
    zeigen: programm(ENTW_ZEIGEN),
  };
}

function entwTextur(gl, breite, hoehe, daten, { linear = true, mipmap = false } = {}) {
  const t = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, t);
  if (daten instanceof ImageBitmap) {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, daten);
  } else {
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, breite, hoehe, 0, gl.RGBA, gl.UNSIGNED_BYTE, daten || null);
  }
  const f = linear ? gl.LINEAR : gl.NEAREST;
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, mipmap ? gl.LINEAR_MIPMAP_LINEAR : f);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, f);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  if (mipmap) gl.generateMipmap(gl.TEXTURE_2D);
  return t;
}

// Eine Zielfläche (Textur samt Framebuffer) in der Arbeitsgrösse.
function entwFlaeche(gl, breite, hoehe) {
  const textur = entwTextur(gl, breite, hoehe, null);
  const fb = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
  gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, textur, 0);
  return { textur, fb, breite, hoehe };
}

function entwZeichne(k, prog, ziel, breite, hoehe, setze) {
  const { gl } = k;
  gl.useProgram(prog.p);
  gl.bindFramebuffer(gl.FRAMEBUFFER, ziel ? ziel.fb : null);
  gl.viewport(0, 0, breite, hoehe);
  gl.uniform2f(prog.orte.uSize, breite, hoehe);
  let einheit = 0;
  const bild = (name, textur) => {
    gl.activeTexture(gl.TEXTURE0 + einheit);
    gl.bindTexture(gl.TEXTURE_2D, textur);
    gl.uniform1i(prog.orte[name], einheit);
    einheit++;
  };
  setze((name, wert) => gl.uniform1f(prog.orte[name], wert), bild, (name, a, b) => gl.uniform2f(prog.orte[name], a, b));
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}

// Die ganze Kette in der Grösse breite × hoehe; gibt die Fläche mit dem
// Ergebnis zurück. Alle Zwischenflächen räumt der Aufrufer über `weg` ab.
function entwRechne(k, werte, breite, hoehe, weg) {
  const { gl } = k;
  const neu = () => { const f = entwFlaeche(gl, breite, hoehe); weg.push(f); return f; };
  const wb = werte.temperature != null;
  let x = neu();
  entwZeichne(k, k.anpassung, x, breite, hoehe, (f, bild) => {
    f('uExposure', werte.exposure);
    f('uTemperature', wb ? werte.temperature : 6500);
    f('uTint', wb ? (werte.tint ?? 0) : 0);
    f('uContrast', werte.contrast);
    f('uShadows', werte.shadows);
    f('uHighlights', werte.highlights ?? 0);
    f('uApplyWhiteBalance', wb ? 1 : 0);
    f('uCurveActive', entw.kurve ? 1 : 0);
    f('uMixerActive', entw.wuerfel ? 1 : 0);
    f('uCubeSize', entw.wuerfelKante || 1);
    bild('uTexture', entw.quellTextur);
    bild('uCurveLut', entw.kurve || entw.leer);
    bild('uColorCube', entw.wuerfel || entw.leer);
  });
  const weich = (bild, sigma) => {
    const h = neu();
    entwZeichne(k, k.weich, h, breite, hoehe, (f, b, f2) => { f2('uRichtung', 1, 0); f('uSigma', sigma); b('uBild', bild.textur); });
    const v = neu();
    entwZeichne(k, k.weich, v, breite, hoehe, (f, b, f2) => { f2('uRichtung', 0, 1); f('uSigma', sigma); b('uBild', h.textur); });
    return v;
  };
  const stufe = (bild, weichBild, { schaerfe = 0, rauschen = 0, klarheit = 0, vignette = 0 }) => {
    const aus = neu();
    entwZeichne(k, k.nachbarn, aus, breite, hoehe, (f, b) => {
      f('uSchaerfe', schaerfe);
      f('uRauschen', rauschen);
      f('uKlarheit', klarheit);
      f('uVignette', vignette);
      b('uBild', bild.textur);
      b('uWeich', weichBild.textur);
    });
    return aus;
  };
  if (werte.sharpness > 0) x = stufe(x, weich(x, ENTW_SCHAERFE_SIGMA), { schaerfe: 2 * werte.sharpness });
  if (werte.noise_reduction > 0) x = stufe(x, weich(x, ENTW_RAUSCHEN_SIGMA), { rauschen: werte.noise_reduction });
  if (werte.clarity !== 0 || werte.vignette !== 0) {
    const w = werte.clarity !== 0 ? weich(x, entwKlarheitSigma(breite, hoehe)) : x;
    x = stufe(x, w, { klarheit: entwKlarheitStaerke(werte.clarity), vignette: 2 * werte.vignette });
  }
  return x;
}

function entwRaeumeAuf(weg) {
  const { gl } = entw.k;
  for (const f of weg) { gl.deleteFramebuffer(f.fb); gl.deleteTexture(f.textur); }
  weg.length = 0;
}

const ENTW_NEUTRAL = { exposure: 0, contrast: 0, highlights: 0, shadows: 0, temperature: null, tint: null, clarity: 0, sharpness: 0, noise_reduction: 0, vignette: 0 };

// Auf den Bildschirm, in der Grösse der Leinwand.
function entwZeigeJetzt() {
  if (!entw || !entw.k) return;
  const { gl } = entw.k;
  const leinwand = $('entw-leinwand');
  const { breite, hoehe } = entw.vorschau;
  if (leinwand.width !== breite || leinwand.height !== hoehe) { leinwand.width = breite; leinwand.height = hoehe; }
  const weg = [];
  try {
    const werte = entw.vergleich ? ENTW_NEUTRAL : entw.werte;
    const aus = entwRechne(entw.k, werte, breite, hoehe, weg);
    entwZeichne(entw.k, entw.k.zeigen, null, breite, hoehe, (f, b) => b('uBild', aus.textur));
  } finally {
    entwRaeumeAuf(weg);
  }
}

let entwGeplant = false;
function entwZeige() {
  if (entwGeplant) return;
  entwGeplant = true;
  requestAnimationFrame(() => { entwGeplant = false; entwZeigeJetzt(); });
}

function entwVorschauGroesse() {
  const rahmen = $('entw-leinwand').parentElement.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  const maxB = Math.max(200, rahmen.width * dpr), maxH = Math.max(200, (window.innerHeight - 140) * dpr);
  const f = Math.min(1, maxB / entw.breite, maxH / entw.hoehe, 2048 / Math.max(entw.breite, entw.hoehe));
  return { breite: Math.max(1, Math.round(entw.breite * f)), hoehe: Math.max(1, Math.round(entw.hoehe * f)) };
}

function entwFelder() {
  const ziel = $('entw-felder');
  ziel.replaceChildren();
  const auto = el('label', 'entw-auto');
  const kasten = el('input');
  kasten.type = 'checkbox';
  kasten.checked = entw.werte.temperature == null;
  auto.append(kasten, document.createTextNode(' Automatischer Weissabgleich'));
  const wbRegler = [];
  for (const r of ENTW_REGLER) {
    if (r.spalte === 'temperature') ziel.append(auto);
    const zeile = el('label', 'entw-regler-zeile');
    const kopf = el('span', 'entw-name', r.name);
    const zahl = el('span', 'entw-zahl');
    const regler = el('input');
    regler.type = 'range';
    regler.min = r.min; regler.max = r.max; regler.step = r.schritt;
    const wert = () => entw.werte[r.spalte] ?? r.vorgabe ?? 0;
    const zeigeZahl = () => { zahl.textContent = Math.abs(r.min) >= 100 ? String(Math.round(wert())) : Number(wert()).toFixed(2); };
    regler.value = wert();
    zeigeZahl();
    regler.addEventListener('input', () => { entw.werte[r.spalte] = Number(regler.value); entw.geaendert = true; zeigeZahl(); entwZeige(); });
    // Doppelklick setzt den Regler zurück.
    regler.addEventListener('dblclick', () => { entw.werte[r.spalte] = r.wb ? (r.vorgabe ?? 0) : 0; regler.value = wert(); zeigeZahl(); entw.geaendert = true; entwZeige(); });
    const oben = el('div', 'entw-oben');
    oben.append(kopf, zahl);
    zeile.append(oben, regler);
    if (r.wb) { wbRegler.push({ regler, zeile, r }); regler.disabled = kasten.checked; zeile.classList.toggle('aus', kasten.checked); }
    ziel.append(zeile);
  }
  kasten.addEventListener('change', () => {
    if (kasten.checked) { entw.werte.temperature = null; entw.werte.tint = null; } else { entw.werte.temperature = 6500; entw.werte.tint = 0; }
    for (const { regler, zeile, r } of wbRegler) { regler.disabled = kasten.checked; zeile.classList.toggle('aus', kasten.checked); regler.value = entw.werte[r.spalte] ?? r.vorgabe ?? 0; }
    entw.geaendert = true;
    entwZeige();
  });
}

async function zeigeEntwickeln(id) {
  markiereNav('');
  zeigeBereich(['entwickeln']);
  entwFehler('Lade …');
  $('entw-meldung').textContent = '';
  if (entw && entw.k) {
    const { gl } = entw.k;
    for (const t of [entw.quellTextur, entw.kurve, entw.wuerfel, entw.leer]) if (t) gl.deleteTexture(t);
  }
  entw = null;
  const d = await api(`/api/v1/entwickeln/${encodeURIComponent(id)}`);
  // Ein Kontext für die ganze Sitzung: Die Leinwand gibt immer denselben her.
  if (!entwK) {
    try { entwK = entwKontext(); } catch (x) { entwFehler(`WebGL: ${x.message}`); return; }
  }
  const k = entwK;
  if (!k) { entwFehler('Dieser Browser kann kein WebGL 2 – Entwickeln geht hier nicht.'); return; }
  const e = d.einstellungen || {};
  entw = {
    id,
    k,
    d,
    geaendert: false,
    vergleich: false,
    werte: {
      exposure: e.exposure ?? 0,
      contrast: e.contrast ?? 0,
      highlights: e.highlights ?? 0,
      shadows: e.shadows ?? 0,
      temperature: e.temperature ?? null,
      tint: e.tint ?? null,
      clarity: e.clarity ?? 0,
      sharpness: e.sharpness ?? 0,
      noise_reduction: e.noise_reduction ?? 0,
      vignette: e.vignette ?? 0,
    },
  };
  const { gl } = k;
  entw.leer = entwTextur(gl, 1, 1, new Uint8Array([0, 0, 0, 255]));
  const ausBase64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  if (d.kurve) entw.kurve = entwTextur(gl, 256, 1, ausBase64(d.kurve));
  if (d.wuerfel) { entw.wuerfelKante = d.wuerfelKante; entw.wuerfel = entwTextur(gl, d.wuerfelKante * d.wuerfelKante, d.wuerfelKante, ausBase64(d.wuerfel)); }

  const antwort = await fetch(`/api/v1/aufnahmen/${encodeURIComponent(id)}/${d.quelle}`, { credentials: 'same-origin' });
  if (!antwort.ok) { entwFehler(`Das Bild liess sich nicht laden (${antwort.status}).`); return; }
  const blob = await antwort.blob();
  let quelle = await createImageBitmap(blob, { imageOrientation: 'from-image', premultiplyAlpha: 'none' });
  const grenze = Math.min(gl.getParameter(gl.MAX_TEXTURE_SIZE), 8192);
  if (Math.max(quelle.width, quelle.height) > grenze) {
    const f = grenze / Math.max(quelle.width, quelle.height);
    const resizeWidth = Math.round(quelle.width * f), resizeHeight = Math.round(quelle.height * f);
    quelle.close();
    quelle = await createImageBitmap(blob, { imageOrientation: 'from-image', premultiplyAlpha: 'none', resizeWidth, resizeHeight, resizeQuality: 'high' }).catch(() => null);
  }
  if (!quelle) { entwFehler('Das Bild ist für diesen Browser zu gross.'); return; }
  entw.breite = quelle.width;
  entw.hoehe = quelle.height;
  entw.quellTextur = entwTextur(gl, quelle.width, quelle.height, quelle, { mipmap: true });
  quelle.close();
  entw.vorschau = entwVorschauGroesse();

  const hinweise = [];
  if (d.quelle === 'vorschau') hinweise.push('Rohformat oder HEIC: Der Browser rechnet aus der Vorschau (höchstens 2048 Pixel). In voller Grösse entwickelt der Rechner.');
  if (e.tone_curve_json || e.color_mixer_json || e.lut_path) hinweise.push('Tonkurve, Farbmischer und Look vom Rechner wirken mit und bleiben erhalten.');
  entwFehler(hinweise.join(' '));
  $('entw-original').hidden = !d.entwickelt && !d.einstellungen;
  entwFelder();
  entwZeigeJetzt();
}

async function entwSpeichern() {
  if (!entw) return;
  const knoepfe = ['entw-speichern', 'entw-zurueck', 'entw-original'].map($);
  for (const b of knoepfe) b.disabled = true;
  const meldung = $('entw-meldung');
  meldung.textContent = `Rechne in voller Grösse (${entw.breite} × ${entw.hoehe}) …`;
  const weg = [];
  try {
    const { gl } = entw.k;
    const aus = entwRechne(entw.k, entw.werte, entw.breite, entw.hoehe, weg);
    gl.bindFramebuffer(gl.FRAMEBUFFER, aus.fb);
    const pixel = new Uint8ClampedArray(entw.breite * entw.hoehe * 4);
    gl.readPixels(0, 0, entw.breite, entw.hoehe, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
    entwRaeumeAuf(weg);
    const flaeche = document.createElement('canvas');
    flaeche.width = entw.breite;
    flaeche.height = entw.hoehe;
    flaeche.getContext('2d').putImageData(new ImageData(pixel, entw.breite, entw.hoehe), 0, 0);
    const jpeg = await new Promise((fertig) => flaeche.toBlob(fertig, 'image/jpeg', 0.92));
    if (!jpeg) throw new Error('Das Bild liess sich nicht kodieren.');
    meldung.textContent = 'Lade hoch …';
    // Ein neuer Name je Speichern: Geräte halten Dateien unter ihrem Namen vor.
    const pfad = `developed/${entw.id}-${Date.now()}.jpg`;
    const hoch = await fetch(`/api/v1/dateien/${pfad.split('/').map(encodeURIComponent).join('/')}`, {
      method: 'PUT',
      credentials: 'same-origin',
      headers: { 'X-PV-Web': '1', 'Content-Type': 'image/jpeg' },
      body: jpeg,
    });
    if (!hoch.ok) throw new Error(`Hochladen gescheitert (${hoch.status}).`);
    const e = entw.d.einstellungen || {};
    await befehl('entwicklungSpeichern', {
      id: entw.id,
      pfad,
      einstellungen: {
        asset_id: entw.id,
        ...entw.werte,
        lut_path: e.lut_path ?? null,
        lut_strength: e.lut_strength ?? 1,
        lens_correction_enabled: e.lens_correction_enabled ?? true,
        tone_curve_json: e.tone_curve_json ?? null,
        color_mixer_json: e.color_mixer_json ?? null,
        updated_at: new Date().toISOString(),
      },
    });
    entw.geaendert = false;
    meldung.textContent = 'Gespeichert.';
    history.back();
  } catch (x) {
    entwRaeumeAuf(weg);
    meldung.textContent = x.message;
  } finally {
    for (const b of knoepfe) b.disabled = false;
  }
}

$('entw-speichern').addEventListener('click', entwSpeichern);
$('entw-abbrechen').addEventListener('click', () => {
  if (entw && entw.geaendert && !confirm('Änderungen verwerfen?')) return;
  history.back();
});
$('entw-zurueck').addEventListener('click', () => {
  if (!entw) return;
  Object.assign(entw.werte, ENTW_NEUTRAL);
  entw.geaendert = true;
  entwFelder();
  entwZeige();
});
$('entw-original').addEventListener('click', async () => {
  if (!entw || !confirm('Die Entwicklung entfernen und das Original zeigen?')) return;
  try {
    await befehl('entwicklungZuruecksetzen', { id: entw.id });
    entw.geaendert = false;
    history.back();
  } catch (x) { $('entw-meldung').textContent = x.message; }
});
// Gedrückt halten zeigt das Original.
for (const [ereignis, an] of [['pointerdown', true], ['pointerup', false], ['pointerleave', false], ['pointercancel', false]]) {
  $('entw-vergleich').addEventListener(ereignis, () => { if (entw && entw.vergleich !== an) { entw.vergleich = an; entwZeige(); } });
}
window.addEventListener('resize', () => {
  if (!entw || $('bereich-entwickeln').hidden) return;
  entw.vorschau = entwVorschauGroesse();
  entwZeige();
});

#version 460 core
#include <flutter/runtime_effect.glsl>

// Entwickeln-Regler auf der GPU – plattformübergreifende Entsprechung zu
// applyNonRawAdjustments() aus macos/Runner/ImageConverter.swift.
//
// Zweck: LIVE-Vorschau während des Regler-Ziehens. Maßgeblich für das
// gespeicherte Ergebnis bleibt der native Renderpfad (bei RAW wirken die
// Regler dort auf den Rohdaten, was deutlich mehr Spielraum hat).
//
// Bewusst NICHT enthalten: Schärfe und Rauschunterdrückung (brauchen
// Nachbarpixel bzw. echte Entrauschung) sowie Masken.

// Ohne eigene layout(location = …): Flutter vergibt die Float-Indizes in
// Deklarationsreihenfolge (uSize belegt 0 und 1), Sampler haben einen
// eigenen Indexraum. Eigene Locations führen sonst zu
// "overlapping use of location 0" zwischen vec2 und sampler2D.
uniform vec2 uSize;
uniform float uExposure;    // EV, -3 … +3
uniform float uTemperature; // Kelvin, 2000 … 12000
uniform float uTint;        // -100 … +100
uniform float uContrast;    // -1 … +1
uniform float uShadows;     // -1 … +1
uniform float uHighlights;  // -1 … +1
uniform float uApplyWhiteBalance; // 0 = aus (Automatik)
uniform float uCurveActive;       // 0 = keine Tonwertkurve
uniform float uMixerActive;       // 0 = kein Farbmischer
uniform float uCubeSize;          // Kantenlänge des Farbwürfels

// Beschneidungswarnung: 0 = aus. NUR für die Anzeige – im Renderpfad
// (develop_render.dart) muss hier eine 0 stehen, sonst tragen die
// exportierten Dateien die Markierungen. Dafür gibt es einen eigenen Test.
uniform float uClipWarn;

uniform sampler2D uTexture;

// Fertig ausgerechnete Nachschlagetabellen aus develop_color.dart – hier
// wird weder eine Kurve interpoliert noch mit Farbtönen gerechnet, es wird
// nur nachgeschlagen. Genau dieselben Tabellen bekommt Core Image für das
// gespeicherte Ergebnis; deshalb kann beides nicht auseinanderlaufen.
uniform sampler2D uCurveLut;  // 256x1
uniform sampler2D uColorCube; // (n*n) x n, siehe farbwuerfel()

out vec4 fragColor;

// sRGB -> linear. Core Image rechnet linear; ohne diese Umrechnung weicht
// schon die Belichtung sichtbar ab.
vec3 srgbToLinear(vec3 c) {
  return mix(c / 12.92,
             pow((c + 0.055) / 1.055, vec3(2.4)),
             step(vec3(0.04045), c));
}

vec3 linearToSrgb(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(c * 12.92,
             1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055,
             step(vec3(0.0031308), c));
}

// Grobe Kelvin -> RGB-Faktoren, bezogen auf 6500 K als neutral.
// Näherung: Wärmer (< 6500) hebt Rot und senkt Blau, kühler umgekehrt.
// Entspricht nicht exakt CITemperatureAndTint – siehe Dateikopf.
vec3 whiteBalanceGain(float kelvin, float tint) {
  float t = clamp(kelvin, 2000.0, 12000.0) / 6500.0;
  // Exponent gedämpft, damit die Enden des Reglers nicht überzeichnen.
  float r = pow(1.0 / t, 0.55);
  float b = pow(t, 0.55);
  // Tint verschiebt zwischen Grün (negativ) und Magenta (positiv).
  float g = 1.0 - clamp(tint, -100.0, 100.0) / 400.0;
  return vec3(r, g, b);
}

// Tonwertkurve: je Kanal ein eigener Eintrag derselben 256er-Tabelle.
// Die lineare Filterung der Textur glättet zwischen den Stufen – ohne sie
// wären 256 sichtbare Sprünge statt eines Verlaufs.
vec3 tonwertkurve(vec3 c) {
  return vec3(
    texture(uCurveLut, vec2((c.r * 255.0 + 0.5) / 256.0, 0.5)).r,
    texture(uCurveLut, vec2((c.g * 255.0 + 0.5) / 256.0, 0.5)).g,
    texture(uCurveLut, vec2((c.b * 255.0 + 0.5) / 256.0, 0.5)).b
  );
}

// Eine einzelne Blau-Scheibe des Farbwürfels abtasten.
//
// Flutter-Shader kennen nur zweidimensionale Abtaster, ein echter
// 3D-Würfel ist also nicht übertragbar. Die Scheiben liegen deshalb
// nebeneinander: Rot läuft innerhalb einer Scheibe waagerecht, Grün
// senkrecht, Blau wählt die Scheibe (siehe packColorCubeForTexture).
//
// Rot und Grün interpoliert die Textur selbst. Der Abtastpunkt liegt in
// Rot höchstens auf der Mitte des letzten Texels einer Scheibe, greift
// also nie in die Nachbarscheibe hinüber.
vec3 wuerfelScheibe(float scheibe, vec2 rg) {
  float breite = uCubeSize * uCubeSize;
  float x = scheibe * uCubeSize + rg.r * (uCubeSize - 1.0) + 0.5;
  float y = rg.g * (uCubeSize - 1.0) + 0.5;
  return texture(uColorCube, vec2(x / breite, y / uCubeSize)).rgb;
}

// Zwischen den beiden benachbarten Blau-Scheiben wird von Hand geblendet –
// diese eine Achse kann die Textur nicht für uns interpolieren.
vec3 farbwuerfel(vec3 c) {
  float bf = clamp(c.b, 0.0, 1.0) * (uCubeSize - 1.0);
  float unten = floor(bf);
  float oben = min(unten + 1.0, uCubeSize - 1.0);
  vec2 rg = clamp(c.rg, 0.0, 1.0);
  return mix(wuerfelScheibe(unten, rg), wuerfelScheibe(oben, rg), bf - unten);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 quelle = texture(uTexture, uv);
  vec3 c = srgbToLinear(quelle.rgb);

  // 1. Belichtung (CIExposureAdjust: linearer Faktor 2^EV)
  c *= pow(2.0, uExposure);

  // 2. Weißabgleich – nur wenn nicht auf Automatik
  if (uApplyWhiteBalance > 0.5) {
    c *= whiteBalanceGain(uTemperature, uTint);
  }

  // 3. Kontrast (CIColorControls: um 0,5 herum spreizen)
  c = (c - 0.5) * (1.0 + uContrast) + 0.5;

  // 4. Schatten: dunkle Bereiche anheben bzw. absenken, Lichter kaum
  //    antasten. Gewichtung über die Luminanz (Rec. 709).
  if (abs(uShadows) > 0.001) {
    float luma = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
    float gewicht = 1.0 - smoothstep(0.0, 0.6, luma);
    c += uShadows * 0.35 * gewicht;
  }

  // 4b. Lichter – der Spiegel dazu: helle Bereiche absenken bzw. anheben,
  //     Schatten kaum antasten. Dieselbe Gewichtung, nur andersherum, und
  //     derselbe Faktor 0,35. Ein negativer Wert holt einen überstrahlten
  //     Himmel zurück; das ist der Fall, für den es RAW gibt.
  if (abs(uHighlights) > 0.001) {
    float luma = dot(clamp(c, 0.0, 1.0), vec3(0.2126, 0.7152, 0.0722));
    float gewicht = smoothstep(0.4, 1.0, luma);
    c += uHighlights * 0.35 * gewicht;
  }

  // 5. Tonwertkurve und Farbmischer – bewusst NACH der Rückrechnung nach
  //    sRGB. Beide sind auf Anzeigewerte bezogen (Konvention von Lightroom
  //    und darktable); linear angewendet ergäbe dieselbe gezeichnete Kurve
  //    ein deutlich anderes Bild. Die native Seite hält es genauso.
  vec3 srgb = linearToSrgb(clamp(c, 0.0, 1.0));
  if (uCurveActive > 0.5) {
    srgb = tonwertkurve(srgb);
  }
  if (uMixerActive > 0.5) {
    srgb = farbwuerfel(srgb);
  }

  // Beschneidungswarnung ganz am Ende: Sie beurteilt, was tatsächlich
  // herauskommt, nicht einen Zwischenstand. Rot für ausgefressen, Blau für
  // abgesoffen – die Konvention, die auch Lightroom und darktable nutzen.
  if (uClipWarn > 0.5) {
    float hoch = max(max(srgb.r, srgb.g), srgb.b);
    float tief = min(min(srgb.r, srgb.g), srgb.b);
    if (hoch >= 0.996) {
      srgb = vec3(1.0, 0.0, 0.0);
    } else if (tief <= 0.004) {
      srgb = vec3(0.0, 0.35, 1.0);
    }
  }

  fragColor = vec4(srgb, quelle.a);
}

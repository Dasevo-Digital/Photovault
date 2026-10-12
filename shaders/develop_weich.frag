#version 460 core
#include <flutter/runtime_effect.glsl>

// Gaußscher Weichzeichner in EINE Richtung, im linearen Licht gerechnet.
// Zwei Durchgänge (waagerecht, dann senkrecht) ergeben den vollen
// zweidimensionalen Gauß. Gebraucht von den Nachbarpixel-Reglern
// (develop_nachbarn.frag, lib/services/develop_nachbarn.dart).
//
// Warum nicht ImageFilter.blur von Flutter: Der zeichnet die gespeicherten
// sRGB-Werte weich, Core Image dagegen das lineare Licht. Gegen Core Image
// gemessen weicht die Klarheit damit um 4 bis 11 Stufen (von 255) im
// Mittel ab, linear gerechnet um 0,3 bis 0,6. Gespeichert wird das
// Ergebnis trotzdem wieder sRGB-codiert: Ein 8-Bit-Zwischenbild in linearen
// Werten verlöre in den Schatten bis zu zehn Stufen.
uniform vec2 uSize;
uniform vec2 uRichtung; // (1, 0) waagerecht, (0, 1) senkrecht
uniform float uSigma;   // Standardabweichung in Pixeln

uniform sampler2D uBild;

out vec4 fragColor;

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

// Höchstzahl von Stützstellen je Seite – Schleifen brauchen hier feste
// Grenzen. Bis σ ≈ 10 liegen sie auf ganzen Pixeln (genauer diskreter
// Gauß), darüber rücken sie auseinander und decken weiter ±3σ ab; die
// Textur mittelt dann zwischen den Nachbarn (bilinear, siehe
// develop_nachbarn.dart). Gebraucht werden nur so viele, wie ±3σ
// abdecken: Für σ 1,2 (Rauschminderung) sind das 4 statt 32 je Seite.
const int kHalb = 32;

void main() {
  vec2 pos = FlutterFragCoord().xy;
  float schritt = max(1.0, 3.0 * uSigma / float(kHalb));
  float reichweite = ceil(3.0 * uSigma / schritt);
  float nenner = 2.0 * uSigma * uSigma;
  vec3 summe = srgbToLinear(texture(uBild, pos / uSize).rgb);
  float gewichte = 1.0;
  for (int i = 1; i <= kHalb; i++) {
    if (float(i) > reichweite) {
      break;
    }
    float d = float(i) * schritt;
    float g = exp(-(d * d) / nenner);
    // Am Rand wird der letzte Pixel fortgesetzt (wie TileMode.clamp) –
    // sonst dunkelte jeder Weichzeichner die Bildränder ab.
    vec2 vor = clamp(pos + uRichtung * d, vec2(0.5), uSize - vec2(0.5));
    vec2 zurueck = clamp(pos - uRichtung * d, vec2(0.5), uSize - vec2(0.5));
    summe += g * (srgbToLinear(texture(uBild, vor / uSize).rgb) +
                  srgbToLinear(texture(uBild, zurueck / uSize).rgb));
    gewichte += 2.0 * g;
  }
  fragColor = vec4(linearToSrgb(summe / gewichte),
                   texture(uBild, pos / uSize).a);
}

#version 460 core
#include <flutter/runtime_effect.glsl>

// Legt eine Maskenschicht über das bisher entwickelte Bild – dasselbe wie
// CIBlendWithMask unter macOS: Ergebnis = unten + Deckung·(oben − unten),
// im linearen Licht, Deckung = Helligkeit der Maske (weiß = ausgewählt).
//
// Warum ein Shader und nicht BlendMode.dstIn: Die App speichert Masken
// als deckende Graustufenbilder, dstIn liest aber den Alphakanal (überall
// voll). Ein Farbfilter, der die Helligkeit zum Alphakanal macht, half
// unter Skia; Impeller (macOS) überging dabei den Mischmodus und
// zeichnete Schwarz in die Maske. Ein Zeichenaufruf ohne Mischmodus
// verhält sich auf jedem Renderer gleich.
uniform vec2 uSize;

uniform sampler2D uUnten;
uniform sampler2D uOben;
uniform sampler2D uMaske;

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

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 unten = texture(uUnten, uv);
  vec4 oben = texture(uOben, uv);
  float deckung = clamp(dot(texture(uMaske, uv).rgb,
                            vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  vec3 c = mix(srgbToLinear(unten.rgb), srgbToLinear(oben.rgb), deckung);
  fragColor = vec4(linearToSrgb(c), mix(unten.a, oben.a, deckung));
}

#version 460 core
#include <flutter/runtime_effect.glsl>

// Die vier Entwickeln-Regler, die Nachbarpixel brauchen: Schärfe,
// Rauschminderung, Klarheit und Vignettierung. Je Aufruf EINE Stufe,
// in der Reihenfolge von Core Image (applyNonRawAdjustments in
// macos/Runner/ImageConverter.swift): erst schärfen, dann entrauschen,
// dann Klarheit und Vignette. Jede Stufe bekommt das Ergebnis der
// vorigen und dessen Weichbild (develop_weich.frag) mit dem Radius, den
// sie braucht. Eine Stufe mit Stärke 0 lässt das Bild, wie es ist.
//
// Die Formeln sind an Core Image gemessen, nicht nachgelesen – Apple
// beschreibt die Filter nur in Worten. Herleitung und Abweichungen stehen
// in lib/services/develop_nachbarn.dart.
uniform vec2 uSize;
uniform float uSchaerfe;  // Verstärkung der Helligkeitsdetails
uniform float uRauschen;  // Schwelle der Rauschminderung, 0 = aus
uniform float uKlarheit;  // Stärke der grossen Unschärfemaske
uniform float uVignette;  // Stärke wie CIVignette.inputIntensity
uniform float uClipWarn;  // Beschneidungswarnung, nur Anzeige

uniform sampler2D uBild;
uniform sampler2D uWeich;

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

float luma(vec3 c) {
  return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = pos / uSize;
  vec4 quelle = texture(uBild, uv);
  vec3 x = srgbToLinear(quelle.rgb);
  vec3 weich = srgbToLinear(texture(uWeich, uv).rgb);

  // Schärfe (CISharpenLuminance): nur die Helligkeit, damit an Kanten
  // keine Farbsäume entstehen.
  if (uSchaerfe != 0.0) {
    x += vec3(uSchaerfe * (luma(x) - luma(weich)));
  }

  // Rauschminderung (CINoiseReduction): Was unter der Schwelle liegt,
  // gilt als Rauschen und wird geglättet; was darüber liegt, ist eine
  // Kante und wird mit 0,4 nachgeschärft wie bei Core Image.
  if (uRauschen > 0.0) {
    vec3 detail = x - weich;
    float rauschen = 1.0 - smoothstep(0.7 * uRauschen, 1.3 * uRauschen,
                                      abs(luma(detail)));
    x += detail * (-rauschen + (1.0 - rauschen) * 0.4);
  }

  // Klarheit (CIUnsharpMask mit grossem Radius): positiv hebt, negativ
  // senkt den Kontrast über grössere Flächen.
  if (uKlarheit != 0.0) {
    x += uKlarheit * (x - weich);
  }

  // Vignettierung (CIVignette): Faktor auf das lineare Licht, abhängig
  // vom Abstand zur Mitte in halben kurzen Seiten. Positiv dunkelt ab,
  // negativ hellt auf.
  if (uVignette != 0.0) {
    float r = length(pos - 0.5 * uSize) / (0.5 * min(uSize.x, uSize.y));
    float r2 = r * r;
    float abfall = r2 * (0.2235 + r2 * (0.01083 + r2 * 0.0016));
    x *= exp(-uVignette * abfall);
  }

  vec3 srgb = linearToSrgb(clamp(x, 0.0, 1.0));

  // Wie in develop_adjustments.frag, aber hier ganz am Ende: Beurteilt
  // wird, was tatsächlich herauskommt.
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

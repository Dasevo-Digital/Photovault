import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:farbverwaltung/farbverwaltung.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:kern/services/jpeg_icc.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:zierbild/wasserzeichen_text.dart';

import 'farbverwaltung.dart';
import 'fotobuch.dart' show jpegGroesse;

/// Das Zeichen, das in ein [bildBreite] Pixel breites Foto eingerechnet
/// wird (#497) – das Logo, oder der Text, gezeichnet in genau der Breite,
/// die das Zeichen dort bekommt. `null`, wenn [wasserzeichen] nichts
/// Einrechenbares beschreibt oder sich das Logo nicht lesen lässt.
///
/// [zielprofil]: der Farbraum, in dem das Foto hinausgeht (`null` = sRGB).
/// Ein Logo trägt sRGB (ein PNG ohne Profil gilt als sRGB) und wird dorthin
/// umgerechnet; sonst stünde sein Rot in einem Display-P3-Export
/// gesättigter da als im Logo. Der Text bleibt, wie er ist: Weiss, Schwarz
/// und das Grau dazwischen sind in sRGB und Display P3 dieselben Werte.
///
/// **Zwischengespeichert.** Ein Export rechnet dasselbe Zeichen in Hunderte
/// Fotos, fast immer in wenige verschiedene Breiten und einen Farbraum.
/// Gelesen, umgerechnet und gezeichnet wird deshalb je Logo und Farbraum
/// bzw. je Text und Breite einmal. Der Text wird trotzdem für jede Breite
/// eigens gezeichnet statt einmal gross und dann verkleinert: Ein Zeichen,
/// das bei einem E-Mail-Bild 200 Pixel breit ist, bleibt so genauso scharf
/// wie eines mit 2000.
Future<Zeichenpixel?> wasserzeichenpixelFuer(
  Wasserzeichen wasserzeichen, {
  required int bildBreite,
  Uint8List? zielprofil,
  int intent = 1,
}) async {
  switch (wasserzeichen.art) {
    case Wasserzeichenart.bild:
      final daten = wasserzeichen.bild;
      if (daten == null) return null;
      // Nach dem Logo selbst (Bytes vergleichen sich nach ihrer Identität:
      // ein Export, eine Vorgabe, dasselbe Objekt) und dem Farbraum.
      final schluessel = (
        daten,
        zielprofil == null ? '' : sha256.convert(zielprofil).toString(),
        intent,
      );
      if (_logos.hole(schluessel) case final fertig?) return fertig;
      final pixel = await compute(_logoPixel, (
        daten: daten,
        ziel: zielprofil,
        intent: intent,
      ));
      if (pixel != null) _logos.lege(schluessel, pixel);
      return pixel;
    case Wasserzeichenart.text:
      final text = wasserzeichen.text.trim();
      if (text.isEmpty) return null;
      // Breiter als [wasserzeichentextHoechstensBreite] zeichnet es nicht;
      // ein breiteres Zeichen wird beim Einrechnen vergrössert.
      final breite = (wasserzeichen.groesse * bildBreite).round().clamp(
        1,
        wasserzeichentextHoechstensBreite,
      );
      final schluessel = (text, breite);
      if (_texte.hole(schluessel) case final fertig?) return fertig;
      final pixel = await zeichneWasserzeichentextPixel(text, breite: breite);
      _texte.lege(schluessel, pixel);
      return pixel;
  }
}

/// Höchstens so viele gezeichnete Texte bzw. gelesene Logos bleiben im
/// Speicher. Ein Textbild ist höchstens 8000 Pixel breit
/// ([wasserzeichentextHoechstensBreite]) und, weil die Schrift bei 1200
/// Punkt endet, keine 1800 hoch; ein Logo hat höchstens 1600 Pixel an der
/// langen Seite.
final _texte = _Zuletzt<(String, int), Zeichenpixel>(4);
final _logos = _Zuletzt<(Uint8List, String, int), Zeichenpixel>(2);

/// Leert die Zwischenspeicher – für Tests, die zählen, wie oft gezeichnet
/// wird.
@visibleForTesting
void vergissWasserzeichenpixel() {
  _texte.leere();
  _logos.leere();
}

Zeichenpixel? _logoPixel(({Uint8List daten, Uint8List? ziel, int intent}) a) {
  final pixel = Wasserzeichenbild.pixel(a.daten);
  final ziel = a.ziel;
  if (pixel == null || ziel == null) return pixel;
  try {
    return pixel.umgerechnet(
      (rgb) => Farbengine.transformiere(rgb, ziel: ziel, intent: a.intent),
    );
  } on FarbprofilFehler {
    // Ein Profil, das kein RGB beschreibt (ein Graustufen-JPEG mit eigenem
    // Profil): Dort gibt es kein sRGB-Rot umzurechnen, und das Zeichen
    // bleibt, wie es ist – wie vor der Umrechnung.
    return pixel;
  }
}

/// [jpeg] mit eingerechnetem [wasserzeichen], neu kodiert in [qualitaet]
/// (1–100) – für das Fotobuch. Gerechnet wird in einem Isolate
/// (`jpegMitWasserzeichen` im Kern), gezeichnet wird ein Text vorher hier –
/// dart:ui gibt es nur im Haupt-Isolate. Ein Logo kommt in den Farbraum,
/// dessen Profil das JPEG trägt.
///
/// Wirft, wenn sich das Foto oder das Zeichen nicht lesen lässt: Der
/// Aufrufer soll dann nicht ohne Zeichen weitermachen.
Future<Uint8List> jpegMitWasserzeichenAuf(
  Uint8List jpeg,
  Wasserzeichen wasserzeichen, {
  required int qualitaet,
}) async {
  final masse = jpegGroesse(jpeg);
  if (masse == null) throw const FormatException('pv_wasserzeichen_foto');
  final zeichen = await wasserzeichenpixelFuer(
    wasserzeichen,
    bildBreite: masse.$1,
    zielprofil: JpegIcc.lesen(jpeg),
  );
  if (zeichen == null) throw const FormatException('pv_wasserzeichen_bild');
  return compute(jpegMitWasserzeichen, (
    jpeg: jpeg,
    zeichen: zeichen,
    wasserzeichen: wasserzeichen,
    qualitaet: qualitaet,
  ));
}

/// Der Export eines gerenderten Bildes mit Wasserzeichen: die Farbumrechnung
/// von [farbe] und das Zeichen in einem Durchgang
/// ([Farbverwaltung.exportiere]), das Zeichen im Farbraum, in dem das Bild
/// hinausgeht.
///
/// Wirft wie [jpegMitWasserzeichenAuf]; ein [FarbprofilFehler] kommt aus
/// der Umrechnung selbst.
Future<Uint8List> exportiereMitWasserzeichen(
  Farbverwaltung farbe,
  Uint8List jpeg,
  Wasserzeichen wasserzeichen, {
  required bool datenschutz,
  required int qualitaet,
}) async {
  final masse = jpegGroesse(jpeg);
  if (masse == null) throw const FormatException('pv_wasserzeichen_foto');
  final ziel = await farbe.exportziel(datenschutz: datenschutz);
  final zeichen = await wasserzeichenpixelFuer(
    wasserzeichen,
    bildBreite: masse.$1,
    // Ohne Umrechnung behält das Bild sein Profil; sonst bekommt es das
    // Ziel (dort heisst `null` sRGB).
    zielprofil: ziel == null ? JpegIcc.lesen(jpeg) : ziel.ziel,
    intent: ziel?.intent ?? 1,
  );
  if (zeichen == null) throw const FormatException('pv_wasserzeichen_bild');
  return farbe.exportiere(
    jpeg,
    datenschutz: datenschutz,
    zeichen: (
      pixel: zeichen,
      wasserzeichen: wasserzeichen,
      qualitaet: qualitaet,
    ),
  );
}

/// Ein kleiner Zwischenspeicher, der das am längsten nicht Gebrauchte
/// zuerst vergisst.
class _Zuletzt<K, V> {
  _Zuletzt(this.hoechstens);

  final int hoechstens;
  final _werte = <K, V>{};

  V? hole(K schluessel) {
    final wert = _werte.remove(schluessel);
    if (wert != null) _werte[schluessel] = wert;
    return wert;
  }

  void lege(K schluessel, V wert) {
    _werte
      ..remove(schluessel)
      ..[schluessel] = wert;
    while (_werte.length > hoechstens) {
      _werte.remove(_werte.keys.first);
    }
  }

  void leere() => _werte.clear();
}

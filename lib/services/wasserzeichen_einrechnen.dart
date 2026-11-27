import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:kern/services/wasserzeichen.dart';
import 'package:zierbild/wasserzeichen_text.dart';

import 'fotobuch.dart' show jpegGroesse;

/// Das PNG, das in ein [bildBreite] Pixel breites Foto eingerechnet wird
/// (#497) – das Logo, oder der Text, gezeichnet in genau der Breite, die
/// das Zeichen dort bekommt. `null`, wenn [wasserzeichen] nichts
/// Einrechenbares beschreibt.
///
/// Der Text wird für jedes Foto neu gezeichnet statt einmal gross und dann
/// verkleinert: Das kostet am Rechner Millisekunden, und ein Zeichen, das
/// bei einem E-Mail-Bild 200 Pixel breit ist, bleibt so genauso scharf wie
/// eines mit 2000.
Future<Uint8List?> wasserzeichenbildFuer(
  Wasserzeichen wasserzeichen, {
  required int bildBreite,
}) async {
  switch (wasserzeichen.art) {
    case Wasserzeichenart.bild:
      return wasserzeichen.bild;
    case Wasserzeichenart.text:
      final text = wasserzeichen.text.trim();
      if (text.isEmpty) return null;
      final breite = (wasserzeichen.groesse * bildBreite).round();
      return zeichneWasserzeichentext(text, breite: breite < 1 ? 1 : breite);
  }
}

/// [jpeg] mit eingerechnetem [wasserzeichen], neu kodiert in [qualitaet]
/// (1–100). Gerechnet wird in einem Isolate (`jpegMitWasserzeichen` im
/// Kern), gezeichnet wird ein Text vorher hier – dart:ui gibt es nur im
/// Haupt-Isolate.
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
  final zeichen = await wasserzeichenbildFuer(
    wasserzeichen,
    bildBreite: masse.$1,
  );
  if (zeichen == null) throw const FormatException('pv_wasserzeichen_bild');
  return compute(jpegMitWasserzeichen, (
    jpeg: jpeg,
    zeichen: zeichen,
    wasserzeichen: wasserzeichen,
    qualitaet: qualitaet,
  ));
}

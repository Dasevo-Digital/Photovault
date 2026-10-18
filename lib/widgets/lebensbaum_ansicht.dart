import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/services/lebensbaum_bild.dart';
import 'package:zierbild/lebensbaum_flaeche.dart';
import 'package:zierbild/lebensbaum_maler.dart';

import 'profilbild.dart';

/// Der Lebensbaum auf dem Schirm des Rechners – die Fläche aus dem Paket
/// zierbild (dieselbe wie auf dem Telefon) mit den Porträts aus Dateien.
class LebensbaumAnsicht extends StatelessWidget {
  final Lebensbaumbild inhalt;
  final Lebensbaumschild Function(String personId) beschriftung;
  final String titel;
  final String? untertitel;
  final ValueChanged<String> beiTipp;

  /// Das Porträt einer Person, oder `null`.
  final File? Function(String personId)? portrait;

  const LebensbaumAnsicht({
    super.key,
    required this.inhalt,
    required this.beschriftung,
    required this.titel,
    required this.beiTipp,
    this.untertitel,
    this.portrait,
  });

  @override
  Widget build(BuildContext context) {
    final portrait = this.portrait;
    return Lebensbaumflaeche(
      inhalt: inhalt,
      beschriftung: beschriftung,
      titel: titel,
      untertitel: untertitel,
      beiTipp: beiTipp,
      hatPortrait: portrait == null ? null : (id) => portrait(id) != null,
      portraitBild: portrait == null
          ? null
          : (id, radius) => Profilbild(datei: portrait(id), radius: radius),
    );
  }
}

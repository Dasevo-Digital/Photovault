/// Die Diashow als Video am Rechner – Takt und Bilder liegen im Paket
/// `gelaende`, das auch das Telefon benutzt (#281); hier nur der Weg in die
/// Datei, derselbe wie beim Überflug ([schreibeFlugvideo]).
library;

import 'dart:io';

import 'package:gelaende/diashow.dart';

import 'flugvideo.dart';

export 'package:gelaende/diashow.dart';

/// Schreibt [dateien] als Diashow nach [ziel] (siehe [Diashowbilder]).
Future<Videoergebnis> schreibeDiashow({
  required File ziel,
  required List<File> dateien,
  required String titel,
  String? untertitel,
  String? schrift,
  void Function(double anteil)? fortschritt,
  bool Function()? abbruch,
  int breite = diashowBreite,
  int hoehe = diashowHoehe,
  int bilderJeSekunde = videoBilderJeSekunde,
  String? ffmpeg,
  bool? nativ,
}) async {
  final bilder = Diashowbilder(
    dateien: dateien,
    titel: titel,
    untertitel: untertitel,
    schrift: schrift,
    breite: breite,
    hoehe: hoehe,
  );
  try {
    return await schreibeFlugvideo(
      ziel: ziel,
      breite: breite,
      hoehe: hoehe,
      dauer: bilder.dauer,
      bilderJeSekunde: bilderJeSekunde,
      fortschritt: fortschritt,
      abbruch: abbruch,
      ffmpeg: ffmpeg,
      nativ: nativ,
      vorBild: bilder.vorBild,
      maleBild: bilder.maleBild,
    );
  } finally {
    bilder.freigeben();
  }
}

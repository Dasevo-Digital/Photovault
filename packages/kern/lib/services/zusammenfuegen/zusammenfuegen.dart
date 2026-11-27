/// HDR und Panorama aus mehreren Aufnahmen (#498): der Auftrag, die
/// Arbeit in einem eigenen Isolat mit Fortschritt und Abbruch, und was
/// dabei herauskommt.
///
/// **Warum ein eigenes Isolat mit `kill`.** `berechne` (Isolate.run)
/// kennt weder Zwischenstände noch Abbrechen: Ein Panorama aus zwölf
/// Fotos rechnet eine Minute, und wer abbricht, will nicht, dass es im
/// Hintergrund weiterläuft und den Speicher hält. Hier meldet das Isolat
/// jeden Schritt über einen Port, und das Ende des Abonnements beendet es
/// sofort.
///
/// **Was das Isolat liest.** Nur JPEG- und PNG-Dateien: Was in einem
/// anderen Format vorliegt (HEIC, RAW …), wandelt vorher die App mit ihren
/// Bildwerkzeugen, denn die stehen nur im Hauptisolat bereit.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'belichtungsfusion.dart';
import 'fehler.dart';
import 'panorama.dart';
import 'raster.dart';

export 'belichtungsfusion.dart'
    show hdrMindestens, hdrHoechstens, hdrHoechstensPixel;
export 'fehler.dart';
export 'panorama.dart'
    show
        panoramaMindestens,
        panoramaHoechstens,
        panoramaHoechstensPixel,
        panoramaHoechstensKante;

/// Was zusammengefügt wird.
enum Fuegeart {
  /// Eine Belichtungsreihe zu einem Bild mit mehr Zeichnung in Lichtern
  /// und Schatten.
  hdr,

  /// Die Aufnahmen eines Schwenks zu einem breiten Bild.
  panorama;

  int get mindestens => this == hdr ? hdrMindestens : panoramaMindestens;
  int get hoechstens => this == hdr ? hdrHoechstens : panoramaHoechstens;

  /// So viele Bildpunkte darf eine Quelle haben, ehe sie verkleinert
  /// gelesen wird. Beim HDR ist das zugleich die Grösse des Ergebnisses;
  /// beim Panorama hält es das Lesen in Grenzen: Eine Quelle mit 48 MP
  /// belegte beim Dekodieren allein 150 MB, und das Ergebnis darf ohnehin
  /// höchstens 50 MP haben.
  int get quellenPixel => hdrHoechstensPixel;
}

/// Was die Arbeit braucht – lässt sich ans Isolat schicken.
class Fuegeauftrag {
  const Fuegeauftrag({
    required this.art,
    required this.dateien,
    required this.ziel,
    this.brennweiten35 = const [],
    this.ausrichten = true,
    this.drehung = true,
    this.zuschneiden = true,
    this.qualitaet = 93,
  });

  final Fuegeart art;

  /// Die Quellen als JPEG- oder PNG-Dateien, in der Reihenfolge der
  /// Auswahl.
  final List<String> dateien;

  /// Wohin das Ergebnis als JPEG geschrieben wird.
  final String ziel;

  /// Je Quelle die Brennweite als 35-mm-Äquivalent, wo bekannt (nur
  /// Panorama).
  final List<double?> brennweiten35;

  /// Nur HDR: aus der Hand aufgenommen ausrichten, auch drehen.
  final bool ausrichten;
  final bool drehung;

  /// Nur Panorama: auf das grösste volle Rechteck zuschneiden.
  final bool zuschneiden;

  final int qualitaet;
}

/// Was entstanden ist: die JPEG-Datei, ihre Grösse und welche Quellen
/// darin stecken (Stellen in [Fuegeauftrag.dateien]).
class Fuegeergebnis {
  const Fuegeergebnis({
    required this.datei,
    required this.breite,
    required this.hoehe,
    required this.verwendet,
  });

  final String datei;
  final int breite;
  final int hoehe;
  final List<int> verwendet;
}

/// Ein Zwischenstand aus dem Isolat – oder, mit [ergebnis], das Ende.
class Fuegestand {
  const Fuegestand(this.erledigt, this.gesamt, [this.ergebnis]);

  final int erledigt;
  final int gesamt;
  final Fuegeergebnis? ergebnis;
}

/// Fügt nach [a] zusammen, im selben Isolat – für Tests und für das
/// Isolat von [fuegeZusammen].
Fuegeergebnis fuegeZusammenJetzt(
  Fuegeauftrag a, {
  void Function(int erledigt, int gesamt)? fortschritt,
}) {
  final n = a.dateien.length;
  if (n < a.art.mindestens || n > a.art.hoechstens) {
    throw const Zusammenfuegefehler(Fuegegrund.anzahl);
  }
  Farbbild lade(int i) {
    final Uint8List bytes;
    try {
      bytes = File(a.dateien[i]).readAsBytesSync();
    } on FileSystemException {
      throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: i);
    }
    return dekodiereBild(bytes, hoechstensPixel: a.art.quellenPixel, quelle: i);
  }

  final Farbbild bild;
  final List<int> verwendet;
  switch (a.art) {
    case Fuegeart.hdr:
      final e = fuegeBelichtungen(
        n,
        lade,
        optionen: HdrOptionen(ausrichten: a.ausrichten, drehung: a.drehung),
        fortschritt: fortschritt,
      );
      bild = e.bild;
      verwendet = List<int>.generate(n, (i) => i);
    case Fuegeart.panorama:
      final e = fuegePanorama(
        n,
        lade,
        brennweiten35: a.brennweiten35,
        optionen: PanoramaOptionen(zuschneiden: a.zuschneiden),
        fortschritt: fortschritt,
      );
      bild = e.bild;
      verwendet = e.verwendet;
  }
  File(a.ziel).writeAsBytesSync(bild.alsJpeg(qualitaet: a.qualitaet));
  return Fuegeergebnis(
    datei: a.ziel,
    breite: bild.breite,
    hoehe: bild.hoehe,
    verwendet: verwendet,
  );
}

/// Fügt nach [a] in einem eigenen Isolat zusammen und meldet jeden
/// Schritt; der letzte Stand trägt das Ergebnis. Wer das Abonnement
/// kündigt, beendet das Isolat sofort.
///
/// Scheitert es aus einem bekannten Grund, endet der Strom mit
/// [Zusammenfuegefehler].
Stream<Fuegestand> fuegeZusammen(Fuegeauftrag a) async* {
  final empfang = ReceivePort();
  Isolate? isolat;
  try {
    isolat = await Isolate.spawn(
      _arbeite,
      (a, empfang.sendPort),
      onError: empfang.sendPort,
      onExit: empfang.sendPort,
      errorsAreFatal: true,
    );
    await for (final m in empfang) {
      switch (m) {
        case (final int erledigt, final int gesamt):
          yield Fuegestand(erledigt, gesamt);
        case final Fuegeergebnis ergebnis:
          yield Fuegestand(1, 1, ergebnis);
          return;
        case (final Fuegegrund grund, final int? quelle):
          throw Zusammenfuegefehler(grund, quelle: quelle);
        case [final Object? fehler, _]:
          // Ein unerwarteter Fehler im Isolat: als Text, mehr kommt nicht
          // über den Port.
          throw StateError('pv_fuegen_fehler: $fehler');
        case null:
          throw StateError('pv_fuegen_ohne_ergebnis');
      }
    }
  } finally {
    empfang.close();
    isolat?.kill(priority: Isolate.immediate);
  }
}

void _arbeite((Fuegeauftrag, SendPort) eingabe) {
  final (a, port) = eingabe;
  try {
    port.send(fuegeZusammenJetzt(a, fortschritt: (e, g) => port.send((e, g))));
  } on Zusammenfuegefehler catch (f) {
    port.send((f.grund, f.quelle));
  }
}

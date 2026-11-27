/// HDR und Panorama aus mehreren Aufnahmen (#498): der Auftrag, die
/// Arbeit in einem eigenen Isolat mit Fortschritt und Abbruch, und was
/// dabei herauskommt.
///
/// **Warum ein eigenes Isolat mit `kill`.** `berechne` (Isolate.run)
/// kennt weder Zwischenstände noch Abbrechen: Ein Panorama aus zwölf
/// Fotos rechnet eine Minute, und wer abbricht, will nicht, dass es im
/// Hintergrund weiterläuft und den Speicher hält. Hier meldet das Isolat
/// jeden Schritt über einen Port, und das Ende des Abonnements beendet es
/// sofort – auch mitten in einem Schritt, nicht erst bei der nächsten
/// Meldung (siehe [fuegeZusammen]).
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
    this.vorschauen = const [],
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

  /// Je Quelle eine kleine, aufrechte Fassung (JPEG oder PNG) für den
  /// ersten Durchgang, wo die App sie erzeugen konnte – beim HDR
  /// höchstens gut 3200 Punkte an der langen Seite, beim Panorama
  /// wenigstens 0,6 MP. Fehlt sie oder passt sie nicht zur Quelle, liest
  /// der erste Durchgang die Quelle selbst.
  final List<String?> vorschauen;

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
  Uint8List lies(int i) {
    try {
      return File(a.dateien[i]).readAsBytesSync();
    } on FileSystemException {
      throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: i);
    }
  }

  Farbbild lade(int i) =>
      dekodiereBild(lies(i), hoechstensPixel: a.art.quellenPixel, quelle: i);

  // Die kleine Fassung, mit der Grösse der vollen aus deren Kopf. Taugt
  // sie nicht – unlesbar, oder anders geformt als die Quelle, etwa weil
  // der Wandler sie anders gedreht hat –, wird die Quelle selbst gelesen.
  Kleinfassung ladeKlein(int i) {
    final voll = lies(i);
    final groesse = dekodierteGroesse(
      voll,
      hoechstensPixel: a.art.quellenPixel,
    );
    final pfad = i < a.vorschauen.length ? a.vorschauen[i] : null;
    if (groesse != null && pfad != null) {
      try {
        final klein = dekodiereBild(File(pfad).readAsBytesSync(), quelle: i);
        final soll = groesse.breite / groesse.hoehe;
        if ((klein.breite / klein.hoehe - soll).abs() / soll <= 0.015) {
          return (bild: klein, breite: groesse.breite, hoehe: groesse.hoehe);
        }
      } on Object {
        // Dann eben die Quelle selbst.
      }
    }
    final b = dekodiereBild(
      voll,
      hoechstensPixel: a.art.quellenPixel,
      quelle: i,
    );
    return (bild: b, breite: b.breite, hoehe: b.hoehe);
  }

  final mitKlein = a.vorschauen.any((v) => v != null);
  final Farbbild bild;
  final List<int> verwendet;
  switch (a.art) {
    case Fuegeart.hdr:
      final e = fuegeBelichtungen(
        n,
        lade,
        ladeKlein: mitKlein ? ladeKlein : null,
        optionen: HdrOptionen(ausrichten: a.ausrichten, drehung: a.drehung),
        fortschritt: fortschritt,
      );
      bild = e.bild;
      verwendet = List<int>.generate(n, (i) => i);
    case Fuegeart.panorama:
      final e = fuegePanorama(
        n,
        lade,
        ladeKlein: mitKlein ? ladeKlein : null,
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
/// **Sofort heisst sofort.** Vorher war das ein `async*`-Generator mit
/// `await for` über den Port. Den hält ein Kündigen erst beim nächsten
/// `yield` an – das Isolat rechnete bis zu seiner nächsten Meldung weiter,
/// nach der letzten also bis zum fertigen JPEG, und der Speicher blieb so
/// lange belegt. Hier beendet das Kündigen ([StreamController.onCancel])
/// das Isolat auf der Stelle und schliesst den Port.
///
/// Scheitert es, endet der Strom mit [Zusammenfuegefehler] – für die
/// bekannten Gründe mit ihrem, sonst mit [Fuegegrund.rechenfehler] oder
/// [Fuegegrund.ohneErgebnis].
Stream<Fuegestand> fuegeZusammen(Fuegeauftrag a) {
  final empfang = ReceivePort();
  Isolate? isolat;
  var vorbei = false;
  late final StreamController<Fuegestand> aus;

  void beende() {
    if (vorbei) return;
    vorbei = true;
    empfang.close();
    isolat?.kill(priority: Isolate.immediate);
  }

  void scheitere(Zusammenfuegefehler f) {
    beende();
    aus.addError(f);
    unawaited(aus.close());
  }

  aus = StreamController<Fuegestand>(
    onListen: () {
      empfang.listen((m) {
        if (vorbei) return;
        switch (m) {
          case (final int erledigt, final int gesamt):
            aus.add(Fuegestand(erledigt, gesamt));
          case final Fuegeergebnis ergebnis:
            beende();
            aus.add(Fuegestand(1, 1, ergebnis));
            unawaited(aus.close());
          case (final Fuegegrund grund, final int? quelle):
            scheitere(Zusammenfuegefehler(grund, quelle: quelle));
          case [final Object? fehler, _]:
            // Ein unerwarteter Fehler im Isolat: als Text, mehr kommt nicht
            // über den Port.
            scheitere(
              Zusammenfuegefehler(Fuegegrund.rechenfehler, ursache: '$fehler'),
            );
          case null:
            scheitere(const Zusammenfuegefehler(Fuegegrund.ohneErgebnis));
        }
      });
      Isolate.spawn(
        _arbeite,
        (a, empfang.sendPort),
        onError: empfang.sendPort,
        onExit: empfang.sendPort,
        errorsAreFatal: true,
      ).then(
        (i) {
          // Schon gekündigt, während es startete: gleich wieder beenden.
          if (vorbei) {
            i.kill(priority: Isolate.immediate);
          } else {
            isolat = i;
          }
        },
        onError: (Object e) {
          if (!vorbei) {
            scheitere(
              Zusammenfuegefehler(Fuegegrund.rechenfehler, ursache: '$e'),
            );
          }
        },
      );
    },
    onCancel: beende,
  );
  return aus.stream;
}

void _arbeite((Fuegeauftrag, SendPort) eingabe) {
  final (a, port) = eingabe;
  try {
    port.send(fuegeZusammenJetzt(a, fortschritt: (e, g) => port.send((e, g))));
  } on Zusammenfuegefehler catch (f) {
    port.send((f.grund, f.quelle));
  }
}

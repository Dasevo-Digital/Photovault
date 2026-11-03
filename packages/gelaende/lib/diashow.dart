/// **Eine Diashow als Video** – für den Rückblick und den Jahresrückblick
/// am Rechner, für jede Diashow auf dem Telefon (#281).
///
/// Apple, Google und Immich machen aus Erinnerungen kurze Filme, weil man
/// sie so weitergibt: Wer keine Fotoverwaltung mit denselben Bildern hat,
/// braucht eine Datei. Die Ausgabe selbst übernimmt dieselbe Stelle wie
/// beim Überflug (ein [Videoschreiber] bzw. `schreibeFlugvideo` am
/// Rechner); hier steht nur, was in jedem Bild zu sehen ist – darum hier im
/// Paket, das Rechner und Telefon teilen. Der Browser rechnet dieselben
/// Formeln nach (web/app.js, schreibeDiavideo).
///
/// Der Ablauf: eine Titelkarte, dann jedes Foto einige Sekunden mit einem
/// langsamen Schwenk und Zoom (dem „Ken-Burns-Effekt"), und zwischen zwei
/// Fotos eine Überblendung. Die Zeitrechnung ist eine reine Funktion
/// ([diashowTakt]), damit sich prüfen lässt, dass kein Foto verloren geht
/// und keine Überblendung ins Leere läuft.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Wie lange ein Foto steht – die Überblendung eingeschlossen.
const diashowJeBild = Duration(milliseconds: 3500);

/// Wie lange zwei Fotos ineinander übergehen.
const diashowUeberblendung = Duration(milliseconds: 800);

/// Wie lange die Titelkarte steht.
const diashowTitel = Duration(milliseconds: 2500);

/// Breite und Höhe des Videos: Full HD, das spielt jedes Gerät ab.
const diashowBreite = 1920;
const diashowHoehe = 1080;

/// Höchstens so viele Fotos – sonst wird aus einem Rückblick ein Abend.
const diashowHoechstensBilder = 40;

/// Was zu einem Zeitpunkt zu sehen ist.
typedef Diashowtakt = ({
  /// Die Titelkarte statt eines Fotos.
  bool titel,

  /// Das Foto, das steht (bei der Titelkarte das erste, das kommt).
  int index,

  /// Das Foto, in das gerade übergeblendet wird, oder `null`.
  int? naechster,

  /// Wie weit die Überblendung ist, 0 bis 1.
  double ueberblendung,

  /// Wie weit das Foto in seiner Zeit ist, 0 bis 1 – für den Schwenk.
  double fortschritt,
});

/// Wie lang die ganze Diashow mit [anzahl] Fotos ist.
Duration diashowDauer(int anzahl) => diashowTitel + diashowJeBild * anzahl;

/// Was nach [vergangen] zu sehen ist.
Diashowtakt diashowTakt(Duration vergangen, int anzahl) {
  if (vergangen < diashowTitel || anzahl == 0) {
    // Gegen Ende der Titelkarte blendet das erste Foto schon ein.
    final rest = diashowTitel - vergangen;
    final ein = anzahl == 0 || rest > diashowUeberblendung
        ? 0.0
        : 1 - rest.inMicroseconds / diashowUeberblendung.inMicroseconds;
    return (
      titel: true,
      index: 0,
      naechster: ein > 0 ? 0 : null,
      ueberblendung: ein,
      fortschritt: 0,
    );
  }
  final imFoto = vergangen - diashowTitel;
  final index = math.min(
    imFoto.inMicroseconds ~/ diashowJeBild.inMicroseconds,
    anzahl - 1,
  );
  final inDiesem = imFoto - diashowJeBild * index;
  final fortschritt = (inDiesem.inMicroseconds / diashowJeBild.inMicroseconds)
      .clamp(0.0, 1.0);
  final bisEnde = diashowJeBild - inDiesem;
  final letztes = index == anzahl - 1;
  if (!letztes && bisEnde < diashowUeberblendung) {
    return (
      titel: false,
      index: index,
      naechster: index + 1,
      ueberblendung:
          1 - bisEnde.inMicroseconds / diashowUeberblendung.inMicroseconds,
      fortschritt: fortschritt,
    );
  }
  return (
    titel: false,
    index: index,
    naechster: null,
    ueberblendung: 0,
    fortschritt: fortschritt,
  );
}

/// Malt ein Foto bildfüllend mit langsamem Zoom und Schwenk. Gerade und
/// ungerade Fotos laufen in entgegengesetzte Richtungen, sonst wirkt die
/// Folge wie ein einziges Gleiten.
void maleDiashowFoto(
  Canvas leinwand,
  Size flaeche,
  ui.Image bild,
  int index,
  double fortschritt, {
  double deckkraft = 1,
}) {
  final b = bild.width.toDouble(), h = bild.height.toDouble();
  final deckend = math.max(flaeche.width / b, flaeche.height / h);
  final zoom = 1.0 + 0.08 * (index.isEven ? fortschritt : 1 - fortschritt);
  final massstab = deckend * zoom;
  final ausschnitt = Size(flaeche.width / massstab, flaeche.height / massstab);
  final spielX = b - ausschnitt.width, spielY = h - ausschnitt.height;
  final richtung = index.isEven ? fortschritt : 1 - fortschritt;
  final quelle = Rect.fromLTWH(
    spielX * (0.3 + 0.4 * richtung),
    spielY * 0.5,
    ausschnitt.width,
    ausschnitt.height,
  );
  leinwand.drawImageRect(
    bild,
    quelle,
    Offset.zero & flaeche,
    Paint()
      ..filterQuality = FilterQuality.high
      ..color = Color.fromRGBO(0, 0, 0, deckkraft),
  );
}

/// Die Titelkarte: dunkler Grund, Titel und Untertitel in der Mitte.
void maleDiashowTitel(
  Canvas leinwand,
  Size flaeche,
  String titel,
  String? untertitel, {
  String? schrift,
}) {
  leinwand.drawRect(
    Offset.zero & flaeche,
    Paint()..color = const Color(0xFF141414),
  );
  final gross = TextPainter(
    text: TextSpan(
      text: titel,
      style: TextStyle(
        fontFamily: schrift,
        fontSize: flaeche.height * 0.075,
        color: const Color(0xFFF5F0E6),
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: flaeche.width * 0.8);
  final klein = untertitel == null
      ? null
      : (TextPainter(
          text: TextSpan(
            text: untertitel,
            style: TextStyle(
              fontFamily: schrift,
              fontSize: flaeche.height * 0.035,
              color: const Color(0xB3F5F0E6),
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: flaeche.width * 0.8));
  final hoehe = gross.height + (klein == null ? 0 : klein.height + 16);
  var y = (flaeche.height - hoehe) / 2;
  gross.paint(leinwand, Offset((flaeche.width - gross.width) / 2, y));
  y += gross.height + 16;
  klein?.paint(leinwand, Offset((flaeche.width - klein.width) / 2, y));
  gross.dispose();
  klein?.dispose();
}

/// Was ein Video für eine Diashow aus [dateien] braucht: wie lang es wird,
/// was vor jedem Bild zu laden und was zu malen ist.
///
/// Die Fotos werden erst geladen, wenn sie dran sind, und gleich wieder
/// freigegeben: Vierzig Fotos in Full HD wären sonst über 300 MB im
/// Speicher, bevor das erste Bild kodiert ist. Ein Foto, das sich nicht
/// lesen lässt, steht als schwarzes Bild da und nimmt das Video nicht mit.
/// Nach dem Schreiben [freigeben].
class Diashowbilder {
  Diashowbilder({
    required List<File> dateien,
    required this.titel,
    this.untertitel,
    this.schrift,
    this.breite = diashowBreite,
    this.hoehe = diashowHoehe,
  }) : _fotos = dateien.take(diashowHoechstensBilder).toList();

  final List<File> _fotos;
  final String titel;
  final String? untertitel;
  final String? schrift;
  final int breite;
  final int hoehe;
  final _geladen = <int, ui.Image?>{};

  Duration get dauer => diashowDauer(_fotos.length);

  Future<ui.Image?> _lade(int i) async {
    try {
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(await _fotos[i].readAsBytes()),
        getTargetSize: (b, h) {
          // So gross, dass es das Video füllt – nicht grösser.
          final m = math.max(breite / b, hoehe / h) * 1.1;
          if (m >= 1) return ui.TargetImageSize(width: b, height: h);
          return ui.TargetImageSize(
            width: (b * m).round(),
            height: (h * m).round(),
          );
        },
      );
      final bild = (await codec.getNextFrame()).image;
      codec.dispose();
      return bild;
    } on Object {
      return null;
    }
  }

  Future<void> vorBild(double t) async {
    if (_fotos.isEmpty) return;
    final takt = diashowTakt(dauer * t, _fotos.length);
    final brauche = {takt.index, ?takt.naechster};
    for (final i in brauche) {
      if (!_geladen.containsKey(i)) _geladen[i] = await _lade(i);
    }
    for (final i in _geladen.keys.toList()) {
      if (!brauche.contains(i)) _geladen.remove(i)?.dispose();
    }
  }

  void maleBild(Canvas leinwand, Size flaeche, double t) {
    final takt = diashowTakt(dauer * t, _fotos.length);
    leinwand.drawRect(
      Offset.zero & flaeche,
      Paint()..color = const Color(0xFF000000),
    );
    if (takt.titel) {
      maleDiashowTitel(leinwand, flaeche, titel, untertitel, schrift: schrift);
    } else if (_geladen[takt.index] case final bild?) {
      maleDiashowFoto(leinwand, flaeche, bild, takt.index, takt.fortschritt);
    }
    final naechster = takt.naechster;
    if (naechster != null) {
      if (_geladen[naechster] case final bild?) {
        maleDiashowFoto(
          leinwand,
          flaeche,
          bild,
          naechster,
          0,
          deckkraft: takt.ueberblendung,
        );
      }
    }
  }

  void freigeben() {
    for (final b in _geladen.values) {
      b?.dispose();
    }
    _geladen.clear();
  }
}

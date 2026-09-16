/// **Vorher und nachher, am selben Ausschnitt.**
///
/// Kein Teil der Prüfsuite – holt echte Kacheln aus dem Netz. Rendert
/// dieselbe Kameraeinstellung zweimal: einmal mit der Übersichtskarte
/// über der ganzen Landschaft (so war es bis Version 3.4.1) und einmal
/// mit den Texturen der einzelnen Blöcke. Dazwischen liegt der ganze
/// Umbau, und nur das Bild kann sagen, ob er etwas bringt.
///
/// ```sh
/// PV_BILDER=~/Desktop/pv_schaerfe flutter test tool/gelaende_schaerfe_test.dart
/// ```
///
/// **`flutter test` schiebt einen Attrappen-HTTP-Client unter**, der jede
/// Anfrage mit 400 beantwortet. Deshalb wird er für die Dauer des Ladens
/// abgeschaltet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_vault/services/blocktexturen.dart';
import 'package:photo_vault/services/gelaende_laden.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/gelaendetextur.dart';
import 'package:photo_vault/services/wanderobjekte.dart';
import 'package:photo_vault/widgets/gelaende.dart';
import 'package:photo_vault/widgets/gelaendeschilder.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';

/// Die Wanderung durch das Ilsetal – dieselbe, an der die Zahlen im
/// Entwurf gemessen sind.
const _sued = 51.8280;
const _west = 10.6280;
const _nord = 51.8580;
const _ost = 10.6560;

/// Luftbild mit allem, was darauf gehoert – die neue Vorgabe.
const _auflage = Gelaendekarte(
    grund: Gelaendegrund.luftbild,
    wege: true,
    beschriftung: true,
    hoehenlinien: true);

const _breite = 1200.0;
const _hoehe = 800.0;

/// Ein Bild, das als Flugfoto herhalten kann – ein Farbverlauf mit
/// einem Muster, an dem sich Zuschnitt und Verzerrung ablesen lassen.
Future<ui.Image> _probefoto() async {
  const b = 400, h = 300;
  final daten = Uint8List(b * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < b; x++) {
      final i = (y * b + x) * 4;
      final karo = ((x ~/ 40) + (y ~/ 40)).isEven;
      daten[i] = karo ? 220 : 90;
      daten[i + 1] = (y / h * 200).round();
      daten[i + 2] = (x / b * 200).round();
      daten[i + 3] = 255;
    }
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      daten, b, h, ui.PixelFormat.rgba8888, fertig.complete);
  return fertig.future;
}

void main() {
  testWidgets('Blocktexturen gegen Uebersichtskarte', (tester) async {
    final ziel = Platform.environment['PV_BILDER'];
    if (ziel == null) {
      markTestSkipped('PV_BILDER nicht gesetzt');
      return;
    }
    Directory(ziel).createSync(recursive: true);

    // **Eine echte Schrift laden.** `flutter test` setzt sonst „Ahem",
    // und die malt jedes Zeichen als gefuellten Kasten - die Schilder
    // saehen dann aus wie schwarze Balken, und ueber ihre Groesse und
    // Lage liesse sich nichts sagen. Genau das ist beim ersten Lauf
    // passiert.
    //
    // Und `load()` muss in `runAsync`: Es liest von der Platte, und ein
    // `await` darauf kehrt in der gestellten Zeit eines Widget-Tests nie
    // zurueck - der Lauf haengt wortlos bis zur Zeitgrenze.
    await tester.runAsync(() async {
      final schrift = FontLoader('Zierschrift')
        ..addFont(File('assets/fonts/EBGaramond-Variable.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer)));
      await schrift.load();
    });

    tester.view.physicalSize = const Size(_breite, _hoehe);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Hoehengitter? gitter;
    ui.Image? uebersicht;
    Blocktexturlader? lader;
    List<Wanderobjekt>? objekte;

    // `flutter test` schiebt einen Attrappen-Client unter, der jede
    // Anfrage mit 400 beantwortet – ohne diese Zeile meldet der Lauf
    // „keine Kacheln erreichbar", obwohl `curl` dieselbe Kachel holt.
    final vorher = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = vorher);

    await tester.runAsync(() async {
      final klient = http.Client();
      gitter = await ladeHoehengitter(
          sued: _sued, west: _west, nord: _nord, ost: _ost,
          netz: klient, speicher: const DisabledMapCachingProvider());
      uebersicht = await ladeKartenbild(
          sued: _sued, west: _west, nord: _nord, ost: _ost,
          netz: klient, karte: _auflage, hoehen: gitter,
          speicher: const DisabledMapCachingProvider());
      objekte = await holeWanderobjekte(
          sued: _sued, west: _west, nord: _nord, ost: _ost, netz: klient);
      klient.close();
    });

    final g = gitter;
    if (g == null) {
      markTestSkipped('Keine Hoehenkacheln erreichbar');
      return;
    }
    final netz = baueNetz(g,
        grundfarbe:
            uebersicht == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
        reliefstaerke: _auflage.reliefstaerke);
    stdout.writeln('Gitter ${g.spalten}x${g.zeilen}, '
        '${netz.bloecke.length} Bloecke auf Stufe ${netz.grundstufe}, '
        '${netz.dreiecke} Dreiecke');
    if (uebersicht != null) {
      final mLaenge = meterJeGradLaenge((g.nord + g.sued) / 2);
      stdout.writeln('Uebersicht ${uebersicht!.width}x${uebersicht!.height}, '
          '${((g.ost - g.west) * mLaenge / uebersicht!.width).toStringAsFixed(2)}'
          ' m je Bildpunkt');
    }

    // Eine Kamera wie im Flug: tief, nach Norden, mitten in der
    // Landschaft.
    final kamera = Gelaendekamera(
      drehung: 0.15,
      neigung: 0.30,
      entfernung: 1600,
      brennweite: math.min(_breite, _hoehe) * 1.1,
      mitte: const Offset(_breite / 2, _hoehe * 0.62),
      blickpunkt: (x: 0.0, y: -netz.hoeheMeter * 0.30, z: 0.0),
    );

    // Die Schilder – auf die Hoehe des Gitters gesetzt, nicht auf die aus
    // OpenStreetMap: Sie muessen auf DIESER Landschaft sitzen.
    final schilder = <Gelaendeschild>[];
    for (final o in objekte ?? const <Wanderobjekt>[]) {
      final h = g.anOrt(o.breite, o.laenge);
      if (h == null) continue;
      schilder.add(Gelaendeschild(
        art: o.art,
        beschriftung: o.name == null
            ? null
            : (o.hoehe == null
                ? o.name
                : '${o.name}  ${o.hoehe!.round()} m'),
        ort: (
          x: ((o.laenge - g.west) / (g.ost - g.west) - 0.5) * netz.breiteMeter,
          y: (0.5 - (g.nord - o.breite) / (g.nord - g.sued)) * netz.hoeheMeter,
          z: (h - netz.mittlereHoehe) * gelaendeUeberhoehung +
              schildHoeheMeter * gelaendeUeberhoehung,
        ),
      ));
    }
    stdout.writeln('${objekte?.length ?? 0} Wanderobjekte, '
        '${schilder.length} davon im Ausschnitt, '
        '${schilder.where((s) => s.beschriftung != null).length} mit Namen');

    double? hoeheBei(double x, double y) {
      final laenge = g.west + (x / netz.breiteMeter + 0.5) * (g.ost - g.west);
      final breite = g.nord - (0.5 - y / netz.hoeheMeter) * (g.nord - g.sued);
      final h = g.anOrt(breite, laenge);
      return h == null ? null : (h - netz.mittlereHoehe) * gelaendeUeberhoehung;
    }

    Future<void> schreibe(String name, Map<Texturblock, ui.Image>? texturen) =>
        tester.runAsync(() async {
          final sammler = ui.PictureRecorder();
          Gelaendemaler(
            netz: netz,
            kamera: kamera,
            spur: const [],
            spurfarbe: const Color(0xFFFF7043),
            karte: uebersicht,
            blocktexturen: texturen,
            schilder: schilder,
            hoeheBei: hoeheBei,
            schriftart: 'Zierschrift',
          ).paint(ui.Canvas(sammler), const Size(_breite, _hoehe));
          final bild = await sammler
              .endRecording()
              .toImage(_breite.round(), _hoehe.round());
          final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
          bild.dispose();
          File('$ziel/$name.png').writeAsBytesSync(
              daten!.buffer.asUint8List(), flush: true);
          stdout.writeln('  -> $ziel/$name.png');
        });

    await schreibe('a-uebersicht', null);

    final wunsch = bloeckeImBild(netz, kamera, const Size(_breite, _hoehe),
        uebersichtAufloesung: uebersicht == null
            ? null
            : (g.ost - g.west) *
                meterJeGradLaenge((g.nord + g.sued) / 2) /
                uebersicht!.width);
    stdout.writeln('${wunsch.length} Bloecke im Bild, Stufen '
        '${wunsch.map((w) => w.stufe).reduce(math.min)}..'
        '${wunsch.map((w) => w.stufe).reduce(math.max)}');

    await tester.runAsync(() async {
      lader = Blocktexturlader(
        karte: _auflage,
        hoehen: g,
        grundstufe: netz.grundstufe,
        speicher: const DisabledMapCachingProvider(),
      );
      lader!.brauche(wunsch);
      final uhr = Stopwatch()..start();
      while (lader!.bilder.length < wunsch.length &&
          uhr.elapsedMilliseconds < 120000) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      stdout.writeln('${lader!.bilder.length} von ${wunsch.length} Texturen '
          'in ${(uhr.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
          '${(lader!.belegt / 1024 / 1024).toStringAsFixed(1)} MB');
    });

    await schreibe('b-bloecke', lader!.bilder);

    // Und ein Bild, wie es ins Video geht: mit Foto, Messwerten,
    // Namensnennung und Abspann. Die vier entstehen nur beim
    // Videoexport und sind sonst nirgends zu sehen - ohne dieses
    // Standbild wuesste niemand, ob sie sitzen.
    await tester.runAsync(() async {
      final foto = await _probefoto();
      final sammler = ui.PictureRecorder();
      Gelaendemaler(
        netz: netz,
        kamera: kamera,
        spur: const [],
        spurfarbe: const Color(0xFFFF7043),
        karte: uebersicht,
        blocktexturen: lader!.bilder,
        schilder: schilder,
        hoeheBei: hoeheBei,
        schriftart: 'Zierschrift',
        flugbild: (bild: foto, deckkraft: 1.0, unterschrift: '11:42'),
        namensnennung: 'Hoehen: Tilezen / AWS Open Data · '
            'Esri, Maxar, Earthstar Geographics · '
            '© waymarkedtrails.org (CC-BY-SA)',
        // Die drei Zahlen des Fluges - hier alle drei zugleich sichtbar,
        // im Video blenden sie zum Abspann hin weg. Die Werte sind
        // schmaler als ihre breiteste Fassung: Genau so soll das Fach
        // aussehen, wenn gerade eine Ziffer fehlt.
        messwerte: (
          werte: const [
            (name: 'Höhe', wert: '812 m', breitester: '1.204 m', farbe: null),
            (
              name: 'Tempo',
              wert: '4,3 km/h',
              breitester: '12,7 km/h',
              farbe: null
            ),
            (
              name: 'Steigung',
              wert: '6,1 %',
              breitester: '−12,4 %',
              farbe: Color(0xFFFFAB91)
            ),
          ],
          deckkraft: 1.0
        ),
        abspann: (
          zeilen: ['16,1 km', '742 m Aufstieg   ·   4:35 h unterwegs'],
          deckkraft: 1.0
        ),
      ).paint(ui.Canvas(sammler), const Size(_breite, _hoehe));
      final bild = await sammler
          .endRecording()
          .toImage(_breite.round(), _hoehe.round());
      final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
      bild.dispose();
      foto.dispose();
      File('$ziel/c-videobild.png')
          .writeAsBytesSync(daten!.buffer.asUint8List(), flush: true);
      stdout.writeln('  -> $ziel/c-videobild.png');
    });

    lader!.schliessen();
  }, timeout: const Timeout(Duration(minutes: 5)));
}

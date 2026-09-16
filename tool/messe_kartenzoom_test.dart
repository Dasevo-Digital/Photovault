// Messstand: Was ein schneller Zoom an Kachelarbeit auslöst.
//
// Keine Behauptung, eine Waage. Aufruf:
//   flutter test tool/messe_kartenzoom_test.dart
//
// Gezählt wird dreierlei, und der Unterschied ist wesentlich:
//  * ANGELEGT  – `TileLayer.build` legt bei JEDEM Bild die fehlenden
//                Kacheln an, am Umformer vorbei. Jede angelegte Kachel
//                kostet bei `TileDisplay.fadeIn` einen AnimationController.
//  * GELADEN   – erst das ist ein Abruf: Platte oder Netz, danach
//                dekodieren. Das ist die Zahl, die der Kachelserver sieht.
//  * ABGEBROCHEN – geladen und vor dem Ankommen weggeworfen.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

class _Waage extends TileProvider {
  _Waage(this.pixel, this.lauf);

  final ui.Image pixel;

  /// Laufende Nummer des Messlaufs.
  ///
  /// **Ohne sie misst der zweite Lauf nichts.** Flutters Bildspeicher
  /// ist einer fuer den ganzen Prozess; ein Schluessel `13/4/2`, den
  /// Lauf 1 schon dekodiert hat, wird in Lauf 2 gar nicht mehr geladen.
  /// Genau so kam beim ersten Anlauf heraus, dass ein Schub mit Drossel
  /// 0 Kacheln braucht.
  final int lauf;
  final jeStufe = <int, int>{};
  final verschieden = <String>{};
  var angelegt = 0, geladenGesamt = 0, abgebrochen = 0;
  var laeuft = true;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
      TileCoordinates c, TileLayer o, Future<void> abbruch) {
    angelegt++;
    unawaited(abbruch.then((_) {
      if (laeuft) abgebrochen++;
    }));
    return _Sofort(pixel, '$lauf:${c.z}/${c.x}/${c.y}', () {
      geladenGesamt++;
      jeStufe[c.z] = (jeStufe[c.z] ?? 0) + 1;
      verschieden.add('${c.z}/${c.x}/${c.y}');
    });
  }
}

@immutable
class _Sofort extends ImageProvider<_Sofort> {
  const _Sofort(this.pixel, this.schluessel, this.melde);
  final ui.Image pixel;
  final String schluessel;
  final void Function() melde;

  @override
  Future<_Sofort> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Sofort key, ImageDecoderCallback decode) {
    melde();
    return OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: pixel.clone())));
  }

  @override
  bool operator ==(Object other) =>
      other is _Sofort && other.schluessel == schluessel;

  @override
  int get hashCode => schluessel.hashCode;
}

Future<ui.Image> _einPixel() {
  final r = ui.PictureRecorder();
  Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 1, 1), Paint());
  return r.endRecording().toImage(1, 1);
}

void main() {
  testWidgets('Kachelarbeit eines schnellen Zooms', (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final pixel = await _einPixel();
    const mitte = ll.LatLng(52.37, 9.73);
    var laufNr = 0;

    Future<void> lauf(
      String name, {
      TileUpdateTransformer? umformer,
      TileDisplay anzeige = const TileDisplay.fadeIn(),
      bool retina = true,
      bool schieben = false,
      int randpuffer = 1,
      int schritte = 40,
    }) async {
      final waage = _Waage(pixel, ++laufNr);
      final steuer = MapController();
      PaintingBinding.instance.imageCache.clear();

      await tester.pumpWidget(MaterialApp(
        home: FlutterMap(
          mapController: steuer,
          options: const MapOptions(
              initialCenter: mitte, initialZoom: 6, maxZoom: 21),
          children: [
            TileLayer(
              urlTemplate: 'https://example.invalid/{z}/{x}/{y}.png',
              tileProvider: waage,
              retinaMode: retina,
              maxNativeZoom: 19,
              tileDisplay: anzeige,
              panBuffer: randpuffer,
              tileUpdateTransformer: umformer,
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      final beimStart = waage.geladenGesamt;

      final uhr = Stopwatch()..start();
      if (schieben) {
        // Ein Schub über anderthalb Bildschirmbreiten in 600 ms.
        steuer.move(mitte, 13);
        await tester.pumpAndSettle();
        for (var i = 1; i <= 40; i++) {
          steuer.move(ll.LatLng(52.37, 9.73 + 0.06 * i / 40), 13);
          await tester.pump(const Duration(milliseconds: 15));
        }
      } else {
        // Stufe 6 -> 16 in 40 Schritten zu je 15 ms, also 600 ms –
        // ein Zweifingerwisch, wie ihn eine Hand wirklich macht.
        for (var i = 1; i <= schritte; i++) {
          steuer.move(mitte, 6 + 10 * i / schritte);
          await tester.pump(const Duration(milliseconds: 15));
        }
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        for (var i = 1; i <= schritte; i++) {
          steuer.move(mitte, 16 - 10 * i / schritte);
          await tester.pump(const Duration(milliseconds: 15));
        }
      }
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      uhr.stop();

      waage.laeuft = false;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final stufen = (waage.jeStufe.keys.toList()..sort())
          .map((z) => '$z:${waage.jeStufe[z]}')
          .join(' ');
      debugPrint('--- $name');
      debugPrint('    geladen ${waage.geladenGesamt} (Start $beimStart), '
          'verschieden ${waage.verschieden.length}, '
          'angelegt ${waage.angelegt}, abgebrochen ${waage.abgebrochen}');
      debugPrint('    Rechenzeit ${uhr.elapsedMilliseconds} ms');
      debugPrint('    je Stufe: $stufen');
    }

    for (final schritte in [20, 40, 80]) {
      debugPrint('===== Zoom 6 -> 16 -> 6 in ${schritte * 15} ms je Richtung');
      await lauf('wie heute', schritte: schritte);
      for (final ms in [100, 150, 200, 300, 500]) {
        await lauf('throttle $ms ms',
            umformer:
                TileUpdateTransformers.throttle(Duration(milliseconds: ms)),
            schritte: schritte);
      }
    }
    debugPrint('===== Randpuffer =====');
    await lauf('wie heute, panBuffer 0', randpuffer: 0);
    await lauf('throttle 150 ms, panBuffer 0',
        umformer:
            TileUpdateTransformers.throttle(const Duration(milliseconds: 150)),
        randpuffer: 0);
    debugPrint('===== Schieben auf Stufe 13 =====');
    await lauf('wie heute', schieben: true);
    await lauf('throttle 150 ms',
        umformer:
            TileUpdateTransformers.throttle(const Duration(milliseconds: 150)),
        schieben: true);
    await lauf('throttle 500 ms',
        umformer:
            TileUpdateTransformers.throttle(const Duration(milliseconds: 500)),
        schieben: true);
  });
}

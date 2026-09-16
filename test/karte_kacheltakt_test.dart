// **Ein schneller Zoom lud zehn Stufen, gesehen wurde eine.**
//
// flutter_map laedt seine Kacheln fuer die gerundete Stufe. Wer von
// Stufe 6 auf 16 wischt, kommt durch zehn Stufen, und jede fordert ihren
// ganzen Bildschirm voll Kacheln an. An einem Fenster von 1440x900 mit
// doppelter Punktdichte gemessen, einmal hinein und wieder heraus: 4252
// Ladevorgaenge fuer rund 150 Kacheln, die am Ende zu sehen sind. Ohne
// Netz steht dahinter eine Warteschlange mit sechs Plaetzen, in der die
// gebrauchte Kachel hinter tausenden wartet, die niemand mehr sehen will.
//
// Geprueft wird beides: dass die Drossel greift – und dass sie nichts
// verschluckt. Eine Drossel, die Kacheln verliert, waere schlimmer als
// keine.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Zaehlt, was wirklich geladen wird.
///
/// **Nicht, was angelegt wird**, und der Unterschied ist der ganze
/// Messpunkt: `TileLayer.build` legt bei jedem Einzelbild die fehlenden
/// Kacheln an – am Umformer vorbei –, laedt sie aber nicht. Erst
/// `loadImage` kostet einen Abruf, ein Lesen von der Platte und ein
/// Dekodieren.
class _Zaehler extends TileProvider {
  _Zaehler(this.pixel, this.lauf);

  final ui.Image pixel;

  /// Laufende Nummer. **Ohne sie misst der zweite Lauf nichts**: Flutters
  /// Bildspeicher gilt fuer den ganzen Prozess, und ein Schluessel, den
  /// Lauf 1 schon dekodiert hat, wird in Lauf 2 gar nicht mehr geladen.
  final int lauf;

  final jeStufe = <int, Set<String>>{};
  var geladen = 0;

  @override
  bool get supportsCancelLoading => true;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
          TileCoordinates c, TileLayer o, Future<void> abbruch) =>
      _Sofort(pixel, '$lauf:${c.z}/${c.x}/${c.y}', () {
        geladen++;
        (jeStufe[c.z] ??= <String>{}).add('${c.x}/${c.y}');
      });
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

const _mitte = ll.LatLng(52.37, 9.73);
const _ziel = 16.0;

void main() {
  late ui.Image pixel;
  var laufNr = 0;

  setUpAll(() async => pixel = await _einPixel());
  tearDown(() => kachelAnbieterFuerTest = null);

  /// Baut eine Karte und wischt von Stufe 6 auf [_ziel] – oder bleibt
  /// gleich stehen, wenn [wischen] falsch ist.
  Future<_Zaehler> lauf(
    WidgetTester tester, {
    required bool mitDrossel,
    bool wischen = true,
  }) async {
    final zaehler = _Zaehler(pixel, ++laufNr);
    kachelAnbieterFuerTest = zaehler;
    PaintingBinding.instance.imageCache.clear();
    final steuer = MapController();

    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        mapController: steuer,
        options: MapOptions(
            initialCenter: _mitte,
            initialZoom: wischen ? 6 : _ziel,
            maxZoom: 21),
        children: [
          if (mitDrossel)
            const Kachelschicht(stil: Kartenstil.hell)
          else
            // Dieselbe Schicht ohne den Takt – die Gegenprobe. Die
            // Aufloesung muss mitgehen: Bei doppelter Punktdichte holt
            // die echte Schicht vier Kacheln je Feld, und eine Gegenprobe
            // mit einfacher Aufloesung verglich zwei verschiedene Karten.
            Builder(
                builder: (context) => TileLayer(
                      urlTemplate: Kartenstil.hell.kachelUrl,
                      tileProvider: zaehler,
                      maxNativeZoom: 19,
                      retinaMode: RetinaMode.isHighDensity(context),
                    )),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    if (wischen) {
      // Vierzig Schritte zu je 15 ms – ein Zweifingerwisch, wie ihn eine
      // Hand wirklich macht.
      for (var i = 1; i <= 40; i++) {
        steuer.move(_mitte, 6 + (_ziel - 6) * i / 40);
        await tester.pump(const Duration(milliseconds: 15));
      }
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    return zaehler;
  }

  testWidgets('der Wisch laedt einen Bruchteil dessen, was er ohne Takt laedt',
      (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final ohne = await lauf(tester, mitDrossel: false);
    final mit = await lauf(tester, mitDrossel: true);

    debugPrint('ohne Takt ${ohne.geladen}, mit Takt ${mit.geladen}');
    expect(mit.geladen, lessThan(ohne.geladen ~/ 2),
        reason: 'gemessen 4252 -> 948 beim Hin und Zurueck');
    expect(ohne.jeStufe.keys.length, greaterThan(5),
        reason: 'ohne Takt wird jede durchquerte Stufe voll geladen');
  });

  testWidgets('und verschluckt dabei keine einzige Kachel der Zielstufe',
      (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // Was die Zielstufe braucht, wenn man gleich dort anfaengt.
    final stehend = await lauf(tester, mitDrossel: true, wischen: false);
    final gewischt = await lauf(tester, mitDrossel: true);

    final noetig = stehend.jeStufe[_ziel.toInt()]!;
    final da = gewischt.jeStufe[_ziel.toInt()] ?? <String>{};
    expect(noetig, isNotEmpty);
    expect(da.difference(noetig), isEmpty,
        reason: 'keine Kachel ausserhalb des Ausschnitts');
    expect(noetig.difference(da), isEmpty,
        reason: 'der Takt darf nichts liegen lassen, nur spaeter holen');
  });

  testWidgets('beim Schieben kostet der Takt nichts', (tester) async {
    tester.view.physicalSize = const Size(2880, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    Future<int> schub({required bool mitDrossel}) async {
      final zaehler = _Zaehler(pixel, ++laufNr);
      kachelAnbieterFuerTest = zaehler;
      PaintingBinding.instance.imageCache.clear();
      final steuer = MapController();
      await tester.pumpWidget(MaterialApp(
        home: FlutterMap(
          mapController: steuer,
          options: const MapOptions(initialCenter: _mitte, initialZoom: 13),
          children: [
            if (mitDrossel)
              const Kachelschicht(stil: Kartenstil.hell)
            else
              Builder(
                  builder: (context) => TileLayer(
                        urlTemplate: Kartenstil.hell.kachelUrl,
                        tileProvider: zaehler,
                        maxNativeZoom: 19,
                        retinaMode: RetinaMode.isHighDensity(context),
                      )),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      for (var i = 1; i <= 40; i++) {
        steuer.move(ll.LatLng(52.37, 9.73 + 0.06 * i / 40), 13);
        await tester.pump(const Duration(milliseconds: 15));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      return zaehler.geladen;
    }

    final ohne = await schub(mitDrossel: false);
    final mit = await schub(mitDrossel: true);
    debugPrint('Schieben: ohne Takt $ohne, mit Takt $mit');
    expect(mit, ohne,
        reason: 'beim Schieben wechselt die Stufe nicht, also faellt '
            'nichts weg – waere das anders, kostete der Takt Bild');
  });

  testWidgets('nach dem Abbauen bleibt keine Uhr stehen', (tester) async {
    // **Der Grund, warum der Takt selbst geschrieben ist.** Die
    // eingebaute Drossel von flutter_map raeumt ihre Uhr nur auf, wenn
    // der Ereignisstrom sich schliesst. `TileLayer.dispose` meldet sich
    // aber bloss ab, und eine Abmeldung loest kein `handleDone` aus. Mit
    // der eingebauten Drossel fielen daran 34 bestehende Tests mit
    // „A Timer is still pending even after the widget tree was disposed".
    final zaehler = _Zaehler(pixel, ++laufNr);
    kachelAnbieterFuerTest = zaehler;
    final steuer = MapController();

    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        mapController: steuer,
        options: const MapOptions(initialCenter: _mitte, initialZoom: 13),
        children: const [Kachelschicht(stil: Kartenstil.hell)],
      ),
    ));
    await tester.pumpAndSettle();

    // Bewegen, damit die Uhr wirklich laeuft – und sofort abbauen.
    steuer.move(_mitte, 14);
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // Das Pruefgeruest faellt hier von selbst um, wenn noch eine Uhr
    // laeuft; die Zusicherung haelt nur fest, wonach gesucht wurde.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('zwei Karten nebeneinander nehmen sich nichts weg',
      (tester) async {
    // Der Takt ist EIN Stueck fuer die ganze App, also muss sein Zustand
    // der Anmeldung gehoeren und nicht dem Stueck. Traege ihn das Stueck
    // – so wie [TileUpdateTransformers.throttle] es tut –, dann ginge
    // das Ereignis der zweiten Karte in den Strom der ERSTEN: Deren Uhr
    // laeuft noch, die zweite landet als Nachzuegler, und nachgereicht
    // wird sie an die Senke, die die Uhr gestellt hat. Die erste Karte
    // lüde dann Kacheln aus Lissabon, die zweite gar keine.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final zaehler = _Zaehler(pixel, ++laufNr);
    kachelAnbieterFuerTest = zaehler;
    PaintingBinding.instance.imageCache.clear();
    const lissabon = ll.LatLng(38.72, -9.14);
    final hier = MapController();
    final dort = MapController();

    Widget karte(MapController steuer, ll.LatLng wo) => SizedBox(
          height: 300,
          child: FlutterMap(
            mapController: steuer,
            options: MapOptions(initialCenter: wo, initialZoom: 12),
            children: const [Kachelschicht(stil: Kartenstil.hell)],
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: Column(children: [karte(hier, _mitte), karte(dort, lissabon)]),
    ));
    await tester.pumpAndSettle();

    // Beide innerhalb desselben Zeitfensters – das ist der Fall, um den
    // es geht.
    hier.move(_mitte, 13);
    await tester.pump(const Duration(milliseconds: 20));
    dort.move(lissabon, 13);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    final aufStufe13 = zaehler.jeStufe[13] ?? <String>{};
    final spalten = aufStufe13.map((k) => int.parse(k.split('/').first));
    // Bei doppelter Punktdichte holt die Schicht die Kacheln der
    // naechsttieferen Stufe: Hannover liegt dort bei Spalte ~8635,
    // Lissabon bei ~7775.
    expect(spalten.where((x) => x > 8000), isNotEmpty,
        reason: 'die erste Karte muss ihre eigene Gegend laden');
    expect(spalten.where((x) => x < 8000), isNotEmpty,
        reason: 'und die zweite ihre – sonst hat das eine Stueck seinen '
            'Zustand mit der anderen Karte geteilt');
  });
}

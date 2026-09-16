import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:photo_vault/widgets/mini_location_map.dart';

/// **Eine gescheiterte Kachel bleibt grau, bis jemand nachfasst.**
///
/// Anlass sind zwei Bildschirmfotos vom 27.08.2026: die Weltkarte zu
/// drei Vierteln grau, obwohl der Kachelserver längst wieder antwortete.
/// Im Systemprotokoll der App stand die Ursache – 951 Verbindungen für
/// 178 angekommene Kacheln in einer Minute, davor und danach eins zu
/// eins. Ein Aussetzer von einer Minute also; das Loch blieb trotzdem,
/// weil eine Kachel im Bild nach ihren zwei Wiederholungen nie wieder
/// versucht wird.
///
/// Geprüft wird deshalb nicht der Aussetzer (den kann man nicht
/// bestellen), sondern die Erholung davon.

/// Ein Anbieter, dessen Kacheln auf Ansage scheitern.
class _Launigg extends TileProvider {
  _Launigg({required this.pixel});

  final ui.Image pixel;

  /// Solange gesetzt, scheitert jede Kachel.
  bool abweisen = true;

  var anfragen = 0;

  /// Durchlaufend über alle Prüfläufe: Ein Bildschlüssel, der in zwei
  /// Läufen derselbe ist, träfe im Bildspeicher auf das Ergebnis des
  /// ersten – und der zweite Lauf prüfte dann gar nichts.
  static var _naechsteNummer = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    anfragen++;
    return _Probebild(
        nummer: ++_naechsteNummer, scheitert: abweisen, pixel: pixel);
  }
}

/// Ein Bild je Anfrage – mit eigener Nummer, damit ein zweiter Anlauf
/// nicht am Bildspeicher hängenbleibt.
@immutable
class _Probebild extends ImageProvider<_Probebild> {
  const _Probebild({
    required this.nummer,
    required this.scheitert,
    required this.pixel,
  });

  final int nummer;
  final bool scheitert;
  final ui.Image pixel;

  @override
  Future<_Probebild> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Probebild key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(scheitert
          ? Future.error(Exception('Kachel abgelehnt'))
          : SynchronousFuture(ImageInfo(image: pixel.clone())));

  @override
  bool operator ==(Object other) => other is _Probebild && other.nummer == nummer;

  @override
  int get hashCode => nummer;
}

/// Ein Anbieter, dessen Bildschlüssel die **Adresse** ist – so wie beim
/// echten `NetworkTileImageProvider`, der sich über `Object.hash(url,
/// fallbackUrl)` vergleicht.
///
/// **Warum [_Launigg] das nicht sieht.** Der gibt jedem Abruf eine eigene
/// laufende Nummer, damit ein zweiter Anlauf nicht am Bildspeicher
/// hängenbleibt. Der Kunstgriff stellt aber nebenbei genau das her, was
/// dem echten Anbieter fehlt: einen anderen Schlüssel je Anlauf. Damit
/// prüften die drei Stände oben eine Verdrahtung, die es so nur im
/// Prüfstand gab.
class _WieDasNetz extends Nachfassanbieter {
  _WieDasNetz(this.pixel);

  final ui.Image pixel;

  /// Jede angefragte Adresse, in der Reihenfolge der Abrufe.
  final gefragt = <String>[];

  /// Die eine Kachel, die scheitert – mitten im Bild, nicht im
  /// Vorratsrand: Eine Kachel am Rand wird nach dem Fehlschlag
  /// weggeworfen ([EvictErrorTileStrategy.notVisible]) und taucht im
  /// Nachfassen gar nicht mehr auf.
  TileCoordinates? opfer;

  @override
  ImageProvider getImage(TileCoordinates c, TileLayer o) {
    final adresse = getTileUrl(c, o);
    gefragt.add(adresse);
    return _NachAdresse(pixel, adresse, c == opfer);
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
          TileCoordinates c, TileLayer o, Future<void> abbruch) =>
      getImage(c, o);
}

@immutable
class _NachAdresse extends ImageProvider<_NachAdresse> {
  const _NachAdresse(this.pixel, this.adresse, this.scheitert);

  final ui.Image pixel;
  final String adresse;
  final bool scheitert;

  @override
  Future<_NachAdresse> obtainKey(ImageConfiguration k) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _NachAdresse key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(scheitert
          ? Future.error(Exception('Kachel abgelehnt'))
          : SynchronousFuture(ImageInfo(image: pixel.clone())));

  @override
  bool operator ==(Object other) =>
      other is _NachAdresse && other.adresse == adresse;

  @override
  int get hashCode => adresse.hashCode;
}

Future<ui.Image> _einPixel() {
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      Uint8List.fromList([0, 0, 0, 255]), 1, 1, ui.PixelFormat.rgba8888,
      fertig.complete);
  return fertig.future;
}

/// Führt den Prüflauf aus, ohne dass jede abgelehnte Kachel im
/// Protokoll landet.
///
/// Nicht in `setUp`/`tearDown`: `debugPrint` muss schon am Ende des
/// Testrumpfes wieder stehen, sonst meldet flutter_test „The value of a
/// foundation debug variable was changed by the test".
Future<void> _leise(Future<void> Function() lauf) async {
  final alt = debugPrint;
  debugPrint = (nachricht, {wrapWidth}) {
    if (nachricht != null && nachricht.contains('Kachel abgelehnt')) return;
    alt(nachricht, wrapWidth: wrapWidth);
  };
  try {
    await lauf();
  } finally {
    debugPrint = alt;
  }
}

Widget _karte(Widget schicht) => MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: ll.LatLng(50, 14),
          initialZoom: 8,
          maxZoom: 21,
        ),
        children: [schicht],
      ),
    );

void main() {
  late ui.Image pixel;

  setUpAll(() async => pixel = await _einPixel());

  late void Function(FlutterErrorDetails) alterMelder;

  setUp(() {
    kachelAnbieterFuerTest = null;
    PaintingBinding.instance.imageCache.clear();
    // Eine abgelehnte Kachel schreibt flutter_map über `debugPrint` ins
    // Protokoll. Hier ist das der Zweck der Übung, nicht ein
    // Missgeschick – ohne diesen Filter stünden hundert Meldungen im
    // Protokoll der Suite.
    alterMelder = FlutterError.onError!;
    FlutterError.onError = (fehler) {
      if (fehler.exception.toString().contains('Kachel abgelehnt')) return;
      alterMelder(fehler);
    };
  });

  tearDown(() {
    kachelAnbieterFuerTest = null;
    FlutterError.onError = alterMelder;
  });

  testWidgets('ohne Nachfassen bleibt die Lücke für immer', (tester) async {
    await _leise(() async {
      final anbieter = _Launigg(pixel: pixel);
      kachelAnbieterFuerTest = anbieter;

      await tester.pumpWidget(_karte(
        Builder(builder: (context) => buildMapTileLayer(context)),
      ));
      await tester.pump();
      final ersteRunde = anbieter.anfragen;
      expect(ersteRunde, greaterThan(0), reason: 'gar keine Kachel angefragt?');

      // Eine ganze Minute vergeht.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 5));
      }
      expect(anbieter.anfragen, ersteRunde,
          reason: 'Die gescheiterte Kachel wurde nie wieder versucht – '
              'genau das ist der Befund.');
    });
  });

  testWidgets('mit Nachfassen kommt nach fünf Sekunden ein neuer Anlauf',
      (tester) async {
    await _leise(() async {
      final anbieter = _Launigg(pixel: pixel);
      kachelAnbieterFuerTest = anbieter;

      await tester.pumpWidget(_karte(const Kachelschicht()));
      await tester.pump();
      final ersteRunde = anbieter.anfragen;
      expect(ersteRunde, greaterThan(0));

      // Kurz davor passiert noch nichts.
      await tester.pump(const Duration(seconds: 4));
      expect(anbieter.anfragen, ersteRunde, reason: 'zu früh nachgefasst');

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(anbieter.anfragen, greaterThan(ersteRunde),
          reason: 'nach fünf Sekunden muss ein zweiter Anlauf kommen');

      // Der dritte Anlauf lässt sich länger Zeit: 15 statt 5 Sekunden.
      final zweiteRunde = anbieter.anfragen;
      await tester.pump(const Duration(seconds: 10));
      expect(anbieter.anfragen, zweiteRunde, reason: 'zu schnell hintereinander');
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(anbieter.anfragen, greaterThan(zweiteRunde));

      // Und die Uhr wird beim Verlassen abgeräumt.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(minutes: 2));
    });
  });

  testWidgets('nach der Erholung fängt die nächste Störung wieder bei fünf an',
      (tester) async {
    await _leise(() async {
      final anbieter = _Launigg(pixel: pixel);
      kachelAnbieterFuerTest = anbieter;

      await tester.pumpWidget(_karte(const Kachelschicht(stil: Kartenstil.hell)));
      await tester.pump();

      // Der erste Anlauf nach fünf Sekunden gelingt.
      anbieter.abweisen = false;
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      // Danach ist es still, und die Störung gilt als vorbei.
      await tester.pump(kachelGeheiltNach + const Duration(seconds: 1));
      final nachErholung = anbieter.anfragen;

      // Neue Störung: ein anderer Stil lädt die Kacheln neu, und
      // diesmal weist der Anbieter wieder ab.
      anbieter.abweisen = true;
      await tester.pumpWidget(_karte(const Kachelschicht(stil: Kartenstil.topo)));
      await tester.pump();
      expect(anbieter.anfragen, greaterThan(nachErholung),
          reason: 'der Stilwechsel muss neu laden');
      final neueStoerung = anbieter.anfragen;

      // Wäre die Stufe nicht zurückgesetzt, käme der nächste Anlauf
      // erst nach fünfzehn Sekunden.
      await tester.pump(const Duration(seconds: 4));
      expect(anbieter.anfragen, neueStoerung, reason: 'zu früh');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(anbieter.anfragen, greaterThan(neueStoerung),
          reason: 'nach der Erholung muss wieder fünf Sekunden gelten, '
              'nicht fünfzehn');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(minutes: 2));
    });
  });

  test('gleichzeitige Verbindungen sind gedeckelt', () async {
    // Am eigenen Server gemessen statt an einer Zusicherung abgelesen.
    // flutter_test schiebt sonst einen Ersatz-HttpClient unter, der
    // gar nicht erst ins Netz geht und jede Antwort mit 400 beantwortet.
    HttpOverrides.global = null;
    var gleichzeitig = 0;
    var hoechstens = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((anfrage) async {
      gleichzeitig++;
      if (gleichzeitig > hoechstens) hoechstens = gleichzeitig;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      gleichzeitig--;
      anfrage.response.add([1, 2, 3]);
      await anfrage.response.close();
    }));
    addTearDown(() => server.close(force: true));

    final netz = kachelNetzClient();
    await Future.wait([
      for (var i = 0; i < 40; i++)
        netz.get(Uri.parse('http://127.0.0.1:${server.port}/$i.png')),
    ]);
    expect(hoechstens, lessThanOrEqualTo(kachelVerbindungen),
        reason: 'Es liefen $hoechstens Abrufe auf einmal');
    expect(hoechstens, greaterThan(1), reason: 'gar keine Nebenläufigkeit?');
  });

  group('mit dem Bildschluessel des echten Anbieters', () {
    /// **Der Befund, den die drei Staende oben nicht sehen konnten.**
    ///
    /// `TileImage.load` haengt seinen Horcher nur an, wenn der
    /// Bildschluessel sich geaendert hat:
    ///
    /// ```dart
    /// _imageStream = imageProvider.resolve(ImageConfiguration.empty);
    /// if (_imageStream!.key != oldImageStream?.key) { ... addListener ... }
    /// ```
    ///
    /// Der Rundenzaehler stand bewusst in keiner Adresse. Also blieb der
    /// Schluessel gleich, es kam kein Horcher dazu, und es wurde nie
    /// wieder ein Fehler gemeldet. Eine Kachel in der Bildmitte, die
    /// dauerhaft scheitert, ueber acht Takte zu sechs Sekunden gemessen:
    ///
    /// ```
    ///                    Nachfassen  1  2  3  4  5  6  7  8
    /// vorher                          1  0  0  0  0  0  0  0
    /// mit [Nachfassanbieter]          1  0  0  1  0  0  0  0
    /// ```
    ///
    /// Vorher war nach dem ersten Anlauf Schluss: Wer nach fuenf
    /// Sekunden noch fehlte, fehlte bis zum Programmende. Jetzt greift
    /// die Staffel aus [kachelNachfassen] wie vorgesehen.
    testWidgets('eine fehlende Kachel wird auch ein zweites Mal versucht',
        (tester) async {
      await _leise(() async {
        tester.view.physicalSize = const Size(1830, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final anbieter = _WieDasNetz(pixel);
        anbieter.opfer = const TileCoordinates(2159, 1349, 12);
        kachelAnbieterFuerTest = anbieter;

        await tester.pumpWidget(const MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: ll.LatLng(52.2, 9.8),
              initialZoom: 12,
              maxZoom: 19,
            ),
            children: [Kachelschicht(stil: Kartenstil.topo)],
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        anbieter.gefragt.clear();

        var anlaeufe = 0;
        for (var i = 1; i <= 8; i++) {
          await tester.pump(const Duration(seconds: 6));
          await tester.pump(const Duration(milliseconds: 100));
          anlaeufe += anbieter.gefragt
              .where((u) => u.contains('/12/2159/1349'))
              .length;
          anbieter.gefragt.clear();
        }

        expect(anlaeufe, greaterThanOrEqualTo(2),
            reason: 'nach dem ersten Anlauf war Schluss – die Staffel '
                '5/15/45 Sekunden wurde nie erreicht');

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump(const Duration(minutes: 2));
      });
    });

    testWidgets('nur die gescheiterte Kachel bekommt einen Anhang',
        (tester) async {
      // Die Gegenprobe zur Sparsamkeit: Wuerde der Anhang an ALLE
      // Adressen gehen, zoege jedes Nachfassen den ganzen Bildschirm neu
      // ueber die Leitung. Die Kachelserver werden gespendet.
      await _leise(() async {
        tester.view.physicalSize = const Size(1830, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final anbieter = _WieDasNetz(pixel);
        anbieter.opfer = const TileCoordinates(2159, 1349, 12);
        kachelAnbieterFuerTest = anbieter;

        await tester.pumpWidget(const MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: ll.LatLng(52.2, 9.8),
              initialZoom: 12,
              maxZoom: 19,
            ),
            children: [Kachelschicht(stil: Kartenstil.topo)],
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        anbieter.gefragt.clear();

        await tester.pump(const Duration(seconds: 6));
        await tester.pump(const Duration(milliseconds: 100));

        final mitAnhang = anbieter.gefragt.where((u) => u.contains('#'));
        expect(mitAnhang, hasLength(1));
        expect(mitAnhang.single, contains('/12/2159/1349'));
        expect(anbieter.gefragt.length, greaterThan(50),
            reason: 'der Rest des Bildes wird sehr wohl mit durchgesehen – '
                'nur eben unter derselben Adresse und damit aus dem '
                'Bildspeicher');

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump(const Duration(minutes: 2));
      });
    });
  });
}

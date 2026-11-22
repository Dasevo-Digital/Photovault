import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:kern/abgleich/kachelumleitung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// **Verbunden nie direkt beim Anbieter (IMP-122).**
///
/// Die Karten am Rechner holen OpenStreetMap- und OpenTopoMap-Kacheln
/// über den eigenen Server, sobald er sie liefert (#180). Solange er das
/// nicht meldet – kurz nach dem Start vor der Abfrage, oder weil die
/// Karten dort abgeschaltet sind –, holten sie sie direkt beim Anbieter,
/// mit der Adresse des Rechners und den Orten der Fotos. Jetzt bleibt die
/// Karte einer verbundenen Bibliothek dann leer und sagt das.
///
/// Eine eigene Datei, weil der Kachelweg ein Einzelstück ist: Er wird
/// hier unter dem Netz-Ersatz von flutter_test gebaut und darf keinem
/// Test begegnen, der echte Verbindungen braucht.
/// Ein Anbieter, dessen Kacheln scheitern, solange [abweisen] gesetzt ist –
/// wie eine Karte, die auf ihren Server wartet.
class _Wartend extends TileProvider {
  _Wartend(this.pixel);

  final ui.Image pixel;
  bool abweisen = true;
  var anfragen = 0;
  static var _nummer = 0;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    anfragen++;
    return _Bild(++_nummer, abweisen, pixel);
  }
}

@immutable
class _Bild extends ImageProvider<_Bild> {
  const _Bild(this.nummer, this.scheitert, this.pixel);

  final int nummer;
  final bool scheitert;
  final ui.Image pixel;

  @override
  Future<_Bild> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_Bild key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        scheitert
            ? Future.error(Exception('Kachel wartet'))
            : SynchronousFuture(ImageInfo(image: pixel.clone())),
      );

  @override
  bool operator ==(Object other) => other is _Bild && other.nummer == nummer;

  @override
  int get hashCode => nummer;
}

Future<ui.Image> _einPixel() {
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList([0, 0, 0, 255]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    fertig.complete,
  );
  return fertig.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory ablage;
  const kanal = MethodChannel('plugins.flutter.io/path_provider');
  late ui.Image pixel;

  // Ausserhalb des Prüfstands: Das Dekodieren braucht die echte Uhr.
  setUpAll(() async => pixel = await _einPixel());

  setUp(() {
    // Der Rückfall auf die Platte sucht im Kachelspeicher; der braucht
    // ein Verzeichnis.
    ablage = Directory.systemTemp.createTempSync('pv_kacheln_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, (_) async => ablage.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kanal, null);
    setzeKachelserver(null);
  });

  test('eine verbundene Bibliothek holt nie beim Anbieter, auch nicht, '
      'solange ihr Server keine Kacheln liefert', () async {
    setzeKachelserver(null, verbunden: true);
    expect(kachelnNurUeberServer.value, isTrue);
    for (final adresse in [
      'https://tile.openstreetmap.org/5/16/10.png',
      'https://tile.opentopomap.org/5/16/10.png',
    ]) {
      await expectLater(
        kachelNetzClient().get(Uri.parse(adresse)),
        throwsA(isA<KachelNurUeberServer>()),
      );
    }
  });

  test('eine lokale Bibliothek holt weiter selbst', () {
    setzeKachelserver(null);
    expect(kachelnNurUeberServer.value, isFalse);
  });

  testWidgets('die Karte sagt, dass sie auf den Server wartet', (tester) async {
    Future<void> zeige() => tester.pumpWidget(
      const MaterialApp(
        locale: Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 340,
            height: 200,
            child: Builder(builder: buildMapAttribution),
          ),
        ),
      ),
    );
    const hinweis =
        'Die Karte kommt über den Server. Er liefert gerade keine Kacheln.';
    setzeKachelserver(null, verbunden: true);
    await zeige();
    expect(find.text(hinweis), findsOneWidget);
    // Die Namensnennung bleibt.
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);

    // Meldet der Server Kacheln, verschwindet der Hinweis.
    setzeKachelserver(
      Serververbindung(Uri.parse('http://heimserver.test/'), 'pv1_test'),
      verbunden: true,
    );
    await tester.pump();
    expect(find.text(hinweis), findsNothing);
  });

  testWidgets('liefert der Server Kacheln, lädt die Karte gleich neu', (
    tester,
  ) async {
    final anbieter = _Wartend(pixel);
    kachelAnbieterFuerTest = anbieter;
    final alterMelder = FlutterError.onError!;
    FlutterError.onError = (fehler) {
      if (fehler.exception.toString().contains('Kachel wartet')) return;
      alterMelder(fehler);
    };
    final altesDebugPrint = debugPrint;
    debugPrint = (nachricht, {wrapWidth}) {
      if (nachricht != null && nachricht.contains('Kachel wartet')) return;
      altesDebugPrint(nachricht, wrapWidth: wrapWidth);
    };
    try {
      setzeKachelserver(null, verbunden: true);
      await tester.pumpWidget(
        const MaterialApp(
          home: FlutterMap(
            options: MapOptions(
              initialCenter: ll.LatLng(50, 14),
              initialZoom: 8,
            ),
            children: [Kachelschicht()],
          ),
        ),
      );
      await tester.pump();
      final vorher = anbieter.anfragen;
      expect(vorher, greaterThan(0));

      // Eine Sekunde später meldet der Server Kacheln. Das nächste
      // Nachfassen stünde erst nach fünf Sekunden an.
      await tester.pump(const Duration(seconds: 1));
      anbieter.abweisen = false;
      setzeKachelserver(
        Serververbindung(Uri.parse('http://heimserver.test/'), 'pv1_test'),
        verbunden: true,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(anbieter.anfragen, greaterThan(vorher));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 50));
    } finally {
      kachelAnbieterFuerTest = null;
      FlutterError.onError = alterMelder;
      debugPrint = altesDebugPrint;
    }
  });
}

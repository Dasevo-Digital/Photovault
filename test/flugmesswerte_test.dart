// **Höhe, Tempo und Steigung im ausgegebenen Video.**
//
// Am Bildschirm stehen die drei Zahlen als Widgetzeile unter der
// Ansicht (`_Messwerte`). Ein Video hat kein Darunter: Was aus der App
// herausgeht, ist die Leinwand und sonst nichts. Ein Überflug ohne
// Zahlen zeigt eine hübsche Landschaft, aber nicht, wie hoch, wie steil
// und wie schnell – und genau das ist der Grund, warum jemand einen
// Flyover ansieht.
//
// **Geprüft wird an den Bildpunkten, und zweimal.** Einmal am Maler
// allein (steht die Tafel an der richtigen Stelle, bleibt sie gleich
// breit, geht sie zum Abspann wieder weg) und einmal am **wirklich
// ausgegebenen Video**: Die Bilder gehen als rohe Bildpunkte durch
// `stdin`, ein gestelltes „ffmpeg" fängt sie auf, und im Bild aus der
// Mitte des Fluges muss stehen, was der Maler dort hinmalen soll.
//
// Der zweite Teil ist kein Übermass. Der Anlass steht im Kopf von
// `flugvideo_bedienung_test.dart`: Ein Wert, der gerechnet und
// weitergereicht wird, ist deshalb noch lange nicht gezeichnet.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';
import 'package:photo_vault/services/gelaendesicht.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';
import 'package:photo_vault/services/platform/nativer_videoschreiber.dart';
import 'package:photo_vault/widgets/gelaende.dart';

const int _breite = 400;
const int _hoehe = 300;

Gelaendenetz _netz() {
  const n = 16;
  final hoehen = Float32List(n * n);
  for (var i = 0; i < n * n; i++) {
    hoehen[i] = 400 + 50 * math.sin(i / 7);
  }
  return baueNetz(Hoehengitter(
    spalten: n,
    zeilen: n,
    hoehen: hoehen,
    nord: 50.63,
    sued: 50.60,
    west: 9.85,
    ost: 9.91,
  ));
}

({List<Raumpunkt> linie, List<Flugwert> werte}) _spur() {
  final linie = <Raumpunkt>[];
  final werte = <Flugwert>[];
  final start = DateTime.utc(2026, 9, 4, 10);
  for (var i = 0; i <= 100; i++) {
    linie.add((x: -1000 + i * 20.0, y: i * 4.0, z: i * 3.0));
    werte.add((
      hoehe: 400 + i * 1.0,
      zeit: start.add(Duration(seconds: i * 12)),
    ));
  }
  return (linie: linie, werte: werte);
}

const _kamera = Gelaendekamera(
  drehung: 0.2,
  neigung: 0.5,
  entfernung: 2500,
  brennweite: 400,
  mitte: Offset(_breite / 2, _hoehe * 0.62),
);

/// Malt ein Bild und gibt seine Bildpunkte zurück.
Future<Uint8List> _bild({
  ({List<Flugmesswert> werte, double deckkraft})? messwerte,
  String? namensnennung,
}) async {
  final sammler = ui.PictureRecorder();
  Gelaendemaler(
    netz: _netz(),
    kamera: _kamera,
    spur: const [],
    spurfarbe: const Color(0xFFFF5722),
    messwerte: messwerte,
    namensnennung: namensnennung,
  ).paint(ui.Canvas(sammler), const Size(_breite * 1.0, _hoehe * 1.0));
  final aufnahme = sammler.endRecording();
  final bild = await aufnahme.toImage(_breite, _hoehe);
  aufnahme.dispose();
  final roh = await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
  bild.dispose();
  return roh!.buffer.asUint8List();
}

/// Wo sich zwei Bilder unterscheiden – `null`, wenn nirgends.
///
/// Beide Bilder entstehen aus derselben Landschaft und derselben Kamera;
/// was sich unterscheidet, ist die Zutat, um die es gerade geht. Der
/// Umriss dieser Unterschiede ist genau ihr Platz im Bild.
Rect? _unterschied(Uint8List a, Uint8List b,
    {int breite = _breite, int hoehe = _hoehe}) {
  var links = breite, rechts = -1, oben = hoehe, unten = -1;
  for (var y = 0; y < hoehe; y++) {
    for (var x = 0; x < breite; x++) {
      final i = (y * breite + x) * 4;
      // Eine Schwelle und kein exakter Vergleich: Die Ränder der Tafel
      // sind abgerundet und weich, dort unterscheiden sich einzelne
      // Punkte um einen Hauch.
      final d = math.max((a[i] - b[i]).abs(),
          math.max((a[i + 1] - b[i + 1]).abs(), (a[i + 2] - b[i + 2]).abs()));
      if (d <= 8) continue;
      if (x < links) links = x;
      if (x > rechts) rechts = x;
      if (y < oben) oben = y;
      if (y > unten) unten = y;
    }
  }
  if (rechts < 0) return null;
  return Rect.fromLTRB(
      links.toDouble(), oben.toDouble(), rechts + 1.0, unten + 1.0);
}

Flugmesswert _wert(String name, String wert, String breitester,
        {Color? farbe}) =>
    (name: name, wert: wert, breitester: breitester, farbe: farbe);

void main() {
  group('Die Zahlen im Bild', () {
    testWidgets('sie stehen unten links, ueber der Namensnennung',
        (tester) async {
      await tester.runAsync(() async {
        const nennung = 'Hoehen: Tilezen · Karte: Esri';
        final ohne = await _bild(namensnennung: nennung);
        final mit = await _bild(
          namensnennung: nennung,
          messwerte: (
            werte: [
              _wert('Hoehe', '812 m', '1.204 m'),
              _wert('Tempo', '4,3 km/h', '12,7 km/h'),
              _wert('Steigung', '6,1 %', '-12,4 %'),
            ],
            deckkraft: 1.0,
          ),
        );
        final tafel = _unterschied(ohne, mit);
        expect(tafel, isNotNull,
            reason: 'die Messwerte aendern am Bild gar nichts - '
                'dann sind sie nicht gemalt');

        expect(tafel!.left, lessThan(_breite * 0.1),
            reason: 'die Tafel klebt nicht am linken Rand');
        expect(tafel.top, greaterThan(_hoehe * 0.5),
            reason: 'sie sitzt in der oberen Bildhaelfte, wo das Foto steht');
        // **Ueber die Breite sagt dieser Lauf wenig.** `flutter test`
        // setzt „Ahem", und die malt jedes Zeichen als volles Geviert –
        // knapp doppelt so breit wie eine Schrift, mit der jemand liest.
        // Geprueft wird deshalb nur, dass die Tafel nicht bis an den
        // rechten Rand laeuft; wie sie wirklich aussieht, entscheidet
        // `tool/gelaende_schaerfe_test.dart` am gerenderten Bild.
        expect(tafel.right, lessThan(_breite * 0.95),
            reason: 'sie laeuft bis an den rechten Bildrand');

        // Und die Namensnennung muss darunter frei bleiben: Sie ist eine
        // Lizenzauflage, keine Fussnote, die man ueberdecken darf.
        final leer = await _bild();
        final nennungsfeld = _unterschied(leer, ohne);
        expect(nennungsfeld, isNotNull);
        expect(tafel.bottom, lessThanOrEqualTo(nennungsfeld!.top),
            reason: 'die Tafel reicht bis ${tafel.bottom}, die '
                'Namensnennung beginnt bei ${nennungsfeld.top}');
      });
    });

    testWidgets('sie bleibt gleich breit, egal was gerade dasteht',
        (tester) async {
      await tester.runAsync(() async {
        // Derselbe Flug, zwei Augenblicke: einmal einstellig, einmal
        // zweistellig. Der breiteste Wert des Fluges ist in beiden
        // Faellen derselbe - also darf sich am Fach nichts ruehren.
        final leer = await _bild();
        Future<Rect?> tafelMit(String tempo) async => _unterschied(
              leer,
              await _bild(
                messwerte: (
                  werte: [
                    _wert('Hoehe', '812 m', '812 m'),
                    _wert('Tempo', tempo, '12,7 km/h'),
                  ],
                  deckkraft: 1.0,
                ),
              ),
            );
        final schmal = await tafelMit('4,3 km/h');
        final breit = await tafelMit('12,7 km/h');
        expect(schmal, isNotNull);
        expect(breit, isNotNull);
        expect(schmal!.width, breit!.width,
            reason: 'die Tafel waechst mit dem Wert - im Video verschoebe '
                'sich dann dreissigmal in der Sekunde alles rechts davon');

        // **Die Gegenprobe.** Ohne die breiteste Fassung - wenn also
        // jeder Wert sein eigenes Mass waere - muss sich die Breite sehr
        // wohl aendern. Sonst prueft der Test oben nichts.
        Future<Rect?> tafelOhneVorlage(String tempo) async => _unterschied(
              leer,
              await _bild(
                messwerte: (
                  werte: [
                    _wert('Hoehe', '812 m', '812 m'),
                    _wert('Tempo', tempo, tempo),
                  ],
                  deckkraft: 1.0,
                ),
              ),
            );
        final a = await tafelOhneVorlage('4,3 km/h');
        final b = await tafelOhneVorlage('12,7 km/h');
        expect(a!.width, isNot(b!.width),
            reason: 'ohne Vorlage waere die Breite gleich geblieben - dann '
                'misst dieser Test die falsche Sache');
      });
    });

    testWidgets('zum Abspann hin sind sie weg', (tester) async {
      await tester.runAsync(() async {
        final leer = await _bild();
        final verblasst = await _bild(
          messwerte: (
            werte: [_wert('Hoehe', '812 m', '812 m')],
            deckkraft: 0.0,
          ),
        );
        expect(_unterschied(leer, verblasst), isNull,
            reason: 'bei voller Ausblendung steht immer noch etwas da');
      });
    });

    testWidgets('ohne Zahlen steht auch keine leere Tafel da', (tester) async {
      await tester.runAsync(() async {
        final leer = await _bild();
        final ohneWerte = await _bild(
          messwerte: (werte: const <Flugmesswert>[], deckkraft: 1.0),
        );
        expect(_unterschied(leer, ohneWerte), isNull,
            reason: 'ein Flug ohne Zeiten bekaeme eine leere Tafel');
      });
    });
  });

  group('Im wirklich ausgegebenen Video', () {
    late Directory ordner;

    setUp(() {
      ordner = Directory.systemTemp.createTempSync('pv_flugmesswerte');
    });
    tearDown(() {
      if (ordner.existsSync()) ordner.deleteSync(recursive: true);
    });

    /// Ein „ffmpeg", das die rohen Bildpunkte einfach wegschreibt.
    ///
    /// **Alles hier ist absichtlich unmittelbar und nicht `await`.** Ein
    /// Widget-Test läuft in einer gestellten Zeit; ein `await` auf die
    /// Platte oder auf einen Prozess kehrt darin nie zurück. Der erste
    /// Anlauf schrieb das Skript mit `writeAsString` – der Lauf hing
    /// dann zwei Minuten lang, ohne dass auch nur die erste Zeile des
    /// Tests lief.
    File gestelltesFfmpeg(File rohziel) {
      final skript = File('${ordner.path}/ffmpeg.sh');
      skript.writeAsStringSync('''
#!/bin/sh
cat > "${rohziel.path}"
for letztes in "\$@"; do :; done
: > "\$letztes"
exit 0
''');
      Process.runSync('chmod', ['+x', skript.path]);
      return skript;
    }

    /// Gibt den Flug aus und liefert das Bild aus seiner Mitte.
    ///
    /// [mitWerten] entscheidet, ob die Spur Höhen und Zeiten trägt – und
    /// damit, ob es überhaupt etwas zu messen gibt. Alles andere ist in
    /// beiden Läufen gleich: Die Flugbahn hängt an der Linie, nicht an
    /// den Werten.
    Future<Uint8List> mittleresBild(WidgetTester tester,
        {required bool mitWerten}) async {
      final roh = File('${ordner.path}/bilder-$mitWerten.raw');
      final ffmpeg = gestelltesFfmpeg(roh);
      DesktopImageTools.stelleWerkzeuge({'ffmpeg': ffmpeg.path});
      addTearDown(DesktopImageTools.vergissWerkzeuge);
      // Den nativen Weg abschalten: Sonst entschiede die Maschine, auf
      // der der Test laeuft, welchen Weg er prueft.
      NativerVideoschreiber.vergiss();
      final bote =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      bote.setMockMethodCallHandler(
          NativerVideoschreiber.kanal, (_) async => false);
      // **Und der Kachelspeicher braucht einen Ordner.** Er fragt beim
      // Anlegen nach dem Zwischenspeicher des Systems; ohne Antwort
      // wirft er eine `MissingPluginException` in den Lauf hinein –
      // nicht am Ort des Fehlers, sondern irgendwo dazwischen.
      const ablage = MethodChannel('plugins.flutter.io/path_provider');
      bote.setMockMethodCallHandler(ablage, (_) async => ordner.path);
      addTearDown(() {
        bote.setMockMethodCallHandler(NativerVideoschreiber.kanal, null);
        bote.setMockMethodCallHandler(ablage, null);
        NativerVideoschreiber.vergiss();
      });

      final s = _spur();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: Gelaendeansicht(
            netz: _netz(),
            spur: s.linie,
            spurwerte: mitWerten ? s.werte : const [],
            beimVideoZiel: (_) async => (
              ziel: File('${ordner.path}/flug-$mitWerten.mp4'),
              breite: _breite,
              hoehe: _hoehe,
              dauer: const Duration(milliseconds: 700),
            ),
          ),
        ),
      ));
      // **Die Ausgabe muss IN `runAsync` anlaufen.** Ein Videobild
      // entsteht ueber `Picture.toImage`, und das ist echte Arbeit
      // ausserhalb der Testbuehne: In der gestellten Zeit eines
      // Widget-Tests kehrt das `await` nie zurueck. Der erste Anlauf
      // tippte davor – der Lauf hing dann wortlos, bis die Zeitgrenze
      // ihn abraeumte.
      //
      // **Und getippt wird nicht, sondern der Knopf selbst gedrueckt.**
      // `tester.tap` haelt in `runAsync` seine eigene Wache und blockt;
      // was hier zu pruefen ist, haengt aber nicht am Zeigergeraet,
      // sondern an dem, was der Knopf ausloest.
      final knopf = tester.widget<IconButton>(find
          .ancestor(
              of: find.byIcon(Icons.movie_outlined),
              matching: find.byType(IconButton))
          .first);
      await tester.runAsync(() async {
        knopf.onPressed!();
        // Gewartet wird auf **alle** Bilder und nicht auf genug: Ein
        // Lauf, der noch schreibt, schriebe in den naechsten Test
        // hinein.
        const alle = _breite * _hoehe * 4 * 21;
        for (var i = 0; i < 400; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          if (roh.existsSync() && roh.lengthSync() >= alle) break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      final alle = roh.readAsBytesSync();
      const jeBild = _breite * _hoehe * 4;
      final anzahl = alle.length ~/ jeBild;
      expect(anzahl, greaterThanOrEqualTo(10),
          reason: 'nur $anzahl Bilder angekommen - die Ausgabe lief nicht');
      // Aus der Mitte: dort ist der Einflug vorbei und der Abspann noch
      // nicht da.
      final mitte = anzahl ~/ 2;
      return Uint8List.sublistView(alle, mitte * jeBild, (mitte + 1) * jeBild);
    }

    testWidgets('das ausgegebene Bild traegt die Zahlen', (tester) async {
      final ohne = await mittleresBild(tester, mitWerten: false);
      final mit = await mittleresBild(tester, mitWerten: true);
      // **Die Gegenprobe steckt im Aufbau.** Ohne Höhen und Zeiten gibt
      // es nichts zu melden, und dasselbe Bild derselben Flugbahn muss
      // dann nackt sein. Der Unterschied zwischen beiden ist genau das,
      // was die Zahlen hinzufuegen.
      final tafel = _unterschied(ohne, mit);
      expect(tafel, isNotNull,
          reason: 'das ausgegebene Bild sieht mit und ohne Messwerte gleich '
              'aus - gerechnet und weitergereicht, aber nicht gezeichnet');
      expect(tafel!.left, lessThan(_breite * 0.1));
      expect(tafel.top, greaterThan(_hoehe * 0.5));
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: Platform.isWindows
          ? 'Der POSIX-ffmpeg-Doppelgänger ist unter Windows nicht ausführbar.'
          : false);
}

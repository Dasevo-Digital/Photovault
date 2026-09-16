// Der Videoexport über AVFoundation – geprüft an einem gestellten Kanal.
//
// **Warum gestellt und nicht echt.** Ein Method Channel führt unter
// `flutter test` nirgendwohin: Es gibt keine App, keinen Swift-Teil, kein
// AVFoundation. Was hier zu prüfen ist, ist deshalb genau die Naht –
// welche Aufrufe hinübergehen, in welcher Reihenfolge, mit welchen
// Werten, und was mit einer Beschwerde von drüben passiert.
//
// Dass am Ende eine **abspielbare Datei** steht, beantwortet das nicht.
// Dafür gibt es `tool/flugvideo_nativ_probe.sh`: Es schneidet die Klasse
// `Flugvideoschreiber` wörtlich aus `ImageConverter.swift` heraus,
// übersetzt sie einzeln und lässt `ffprobe` das Ergebnis lesen.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/flugvideo.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';
import 'package:photo_vault/services/platform/nativer_videoschreiber.dart';

void main() {
  late Directory ordner;
  late List<MethodCall> rufe;
  late List<int> bildgroessen;

  /// Setzt den gestellten Kanal auf. [stolpert] darf für einen
  /// Methodennamen eine Ausnahme werfen.
  void kanalStellen({
    Object? Function(MethodCall ruf)? stolpert,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativerVideoschreiber.kanal, (ruf) async {
      rufe.add(ruf);
      if (ruf.method == 'videoBild') {
        final punkte = (ruf.arguments as Map)['rgba'] as Uint8List;
        bildgroessen.add(punkte.length);
      }
      final stolper = stolpert?.call(ruf);
      if (stolper is Exception) throw stolper;
      if (ruf.method == 'videoNativ') return true;
      return null;
    });
  }

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_flugvideo_nativ');
    rufe = [];
    bildgroessen = [];
    NativerVideoschreiber.vergiss();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativerVideoschreiber.kanal, null);
    NativerVideoschreiber.vergiss();
    if (ordner.existsSync()) ordner.deleteSync(recursive: true);
  });

  void malEtwas(ui.Canvas leinwand, ui.Size flaeche, double t) {
    leinwand.drawRect(
      ui.Rect.fromLTWH(0, 0, flaeche.width, flaeche.height),
      ui.Paint()..color = Color.lerp(Colors.red, Colors.blue, t)!,
    );
  }

  List<String> nurNamen() => [for (final r in rufe) r.method];

  testWidgets('so viele Bilder wie gerechnet, und die Groesse geht mit',
      (tester) async {
    await tester.runAsync(() async {
      kanalStellen();
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 64,
        hoehe: 48,
        dauer: const Duration(seconds: 1),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.fertig, reason: '${e.meldung}');
      expect(nurNamen().first, 'videoStart');
      expect(nurNamen().last, 'videoFertig');
      expect(nurNamen().where((n) => n == 'videoBild').length, 10);
      final start = rufe.first.arguments as Map;
      expect(start['breite'], 64);
      expect(start['hoehe'], 48);
      expect(start['bilderJeSekunde'], 10);
      expect(start['path'], '${ordner.path}/flug.mp4');
    });
  });

  testWidgets('jedes Bild kommt vollstaendig an', (tester) async {
    // Vier Bytes je Bildpunkt, kein Rand, keine Zeilenpolsterung. Waere
    // hier etwas abgeschnitten, verschoebe sich drueben jede Zeile gegen
    // die vorige - das Video zeigte eine Schraege statt eines Bildes.
    await tester.runAsync(() async {
      kanalStellen();
      await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 64,
        hoehe: 48,
        dauer: const Duration(milliseconds: 300),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(bildgroessen, everyElement(64 * 48 * 4));
      expect(bildgroessen, hasLength(3));
    });
  });

  testWidgets('ungerade Kanten werden gerade gemacht', (tester) async {
    // Auch der native Weg braucht das: `yuv420p` tastet die Farbe halb so
    // fein ab wie die Helligkeit.
    await tester.runAsync(() async {
      kanalStellen();
      await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 65,
        hoehe: 49,
        dauer: const Duration(milliseconds: 200),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      final start = rufe.first.arguments as Map;
      expect(start['breite'], 64);
      expect(start['hoehe'], 48);
      expect(bildgroessen, everyElement(64 * 48 * 4));
    });
  });

  testWidgets('ein Abbruch verwirft, statt abzuschliessen', (tester) async {
    // Ein `videoFertig` nach einem Abbruch hinterliesse eine Datei, die
    // aussieht wie eine fertige.
    await tester.runAsync(() async {
      kanalStellen();
      var bilder = 0;
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(seconds: 2),
        bilderJeSekunde: 10,
        maleBild: (l, f, t) {
          bilder++;
          malEtwas(l, f, t);
        },
        abbruch: () => bilder >= 3,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.abgebrochen);
      expect(bilder, 3, reason: 'der Abbruch greift zu spaet');
      expect(nurNamen(), contains('videoVerwerfen'));
      expect(nurNamen(), isNot(contains('videoFertig')));
    });
  });

  testWidgets('beschwert sich AVFoundation beim Start, kommt es an',
      (tester) async {
    await tester.runAsync(() async {
      kanalStellen(
        stolpert: (r) => r.method == 'videoStart'
            ? PlatformException(code: 'video', message: 'Kein Platz mehr')
            : null,
      );
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(milliseconds: 300),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.fehler);
      expect(e.meldung, contains('Kein Platz mehr'));
      expect(nurNamen(), ['videoStart']);
    });
  });

  testWidgets('bricht es mitten im Lauf ab, bleibt keine halbe Datei',
      (tester) async {
    await tester.runAsync(() async {
      var bilder = 0;
      kanalStellen(stolpert: (r) {
        if (r.method != 'videoBild') return null;
        bilder++;
        return bilder == 3
            ? PlatformException(code: 'video', message: 'vImage 1')
            : null;
      });
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(seconds: 1),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.fehler);
      expect(e.meldung, contains('vImage'));
      expect(nurNamen(), contains('videoVerwerfen'));
      expect(nurNamen(), isNot(contains('videoFertig')));
    });
  });

  testWidgets('schlaegt der Abschluss fehl, ist es ein Fehler',
      (tester) async {
    // AVAssetWriter meldet das meiste erst beim Abschliessen - dort
    // faellt auf, ob die Datei ueberhaupt geschrieben wurde.
    await tester.runAsync(() async {
      kanalStellen(
        stolpert: (r) => r.method == 'videoFertig'
            ? PlatformException(code: 'video', message: 'Session unvollstaendig')
            : null,
      );
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(milliseconds: 200),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.fehler);
      expect(e.meldung, contains('unvollstaendig'));
    });
  });

  testWidgets('kennt der Bau den Schreiber nicht, ist es keinWerkzeug',
      (tester) async {
    // Eine aeltere Fassung ohne die Swift-Seite: Dann ist es kein Fehler,
    // sondern eine fehlende Faehigkeit - und die Oberflaeche sagt einen
    // anderen Satz.
    await tester.runAsync(() async {
      kanalStellen(
          stolpert: (r) =>
              r.method == 'videoStart' ? MissingPluginException('weg') : null);
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(milliseconds: 200),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
        nativ: true,
      );
      expect(e.ausgang, Videoausgang.keinWerkzeug);
    });
  });

  test('ohne Kanal ist nichts verfuegbar', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativerVideoschreiber.kanal, (_) async {
      throw MissingPluginException('kein Kanal');
    });
    expect(await NativerVideoschreiber.verfuegbar(), isFalse);
  });

  test('mit Kanal ist er verfuegbar - aber nur unter macOS', () async {
    kanalStellen();
    expect(await NativerVideoschreiber.verfuegbar(), Platform.isMacOS,
        reason: 'unter Linux und Windows gibt es AVFoundation nicht, '
            'egal was ein gestellter Kanal antwortet');
  });

  testWidgets('ohne Vorgabe entscheidet die Plattform', (tester) async {
    // Der eigentliche Fehler von 3.5.0 sass hier: Unter macOS ging der
    // Weg zu ffmpeg, und ffmpeg kann es dort gar nicht geben.
    if (!Platform.isMacOS) {
      markTestSkipped('nur unter macOS');
      return;
    }
    await tester.runAsync(() async {
      kanalStellen();
      final e = await schreibeFlugvideo(
        ziel: File('${ordner.path}/flug.mp4'),
        breite: 32,
        hoehe: 32,
        dauer: const Duration(milliseconds: 200),
        bilderJeSekunde: 10,
        maleBild: malEtwas,
      );
      expect(e.ausgang, Videoausgang.fertig, reason: '${e.meldung}');
      expect(nurNamen(), contains('videoStart'));
    });
  });

  testWidgets('die Oberflaeche fragt nicht mehr nach ffmpeg allein',
      (tester) async {
    if (!Platform.isMacOS) {
      markTestSkipped('nur unter macOS');
      return;
    }
    // **Die Werkzeugsuche wird gestellt, und das ist der Kern.** Meine
    // erste Fassung dieses Tests verliess sich darauf, dass auf dieser
    // Maschine kein ffmpeg liegt - hier liegt aber eins, in Homebrew.
    // Der Test ging deshalb auch mit der alten, falschen Fassung durch.
    DesktopImageTools.stelleWerkzeuge(const {'ffmpeg': null});
    addTearDown(DesktopImageTools.vergissWerkzeuge);
    expect(await ffmpegPfad(), isNull, reason: 'die Stellung greift nicht');
    kanalStellen();
    expect(await videoausgabeMoeglich(), isTrue,
        reason: 'ohne ffmpeg muss der native Weg allein genuegen');
  });

  test('ohne beides ist die Ausgabe unmoeglich', () async {
    // Die Gegenrichtung: Faende die Pruefung immer einen Weg, sagte sie
    // nichts aus.
    DesktopImageTools.stelleWerkzeuge(const {'ffmpeg': null});
    addTearDown(DesktopImageTools.vergissWerkzeuge);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativerVideoschreiber.kanal, (_) async {
      throw MissingPluginException('kein Kanal');
    });
    expect(await videoausgabeMoeglich(), isFalse);
  });
}

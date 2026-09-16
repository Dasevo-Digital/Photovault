@TestOn('linux || windows')
library;

// ignore_for_file: avoid_print
// Spielt ein Video wirklich ab.
//
// Das lässt sich nicht im Unittest prüfen: `media_kit` bringt libmpv als
// native Bibliothek mit, und ob die auf dieser Plattform überhaupt
// geladen wird, entscheidet sich erst im laufenden Prozess. Genau das war
// unter Linux der Punkt, an dem die Videowiedergabe hing – dort fehlte
// libmpv im Bündel, während alles andere lief.
//
// Geprüft wird nicht „stürzt nicht ab", sondern dass die Bildmaße
// ankommen und die Abspielposition tatsächlich vorrückt. Ein Player, der
// die Datei annimmt und dann stillsteht, sähe sonst wie ein Erfolg aus.
//
// **Nicht unter macOS**, und zwar nicht, weil es dort nicht ginge: Die
// Testfassung läuft im Sandkasten, ihr Arbeitsverzeichnis zeigt nach
// `~/Library/Containers/com.example.photoVault.test/Data/`, und die
// Vorlage aus dem Projektordner ist für sie schlicht nicht vorhanden.
// Ausprobiert – die Textur wird dort übrigens ebenso angelegt
// (`NativeVideoController: Texture ID: …`), nur eben ohne Datei. Diese
// Datei prüft die beiden Plattformen, für die die Frage offen war.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/widgets/video_playback.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  /// 320x240, drei Sekunden, 14 KB – klein genug fürs Repository.
  ///
  /// Absolut, und das ist keine Kosmetik: Mit dem relativen Pfad meldete
  /// libmpv unter Windows weder Dauer noch Fehler, es geschah schlicht
  /// nichts. `File.existsSync()` war dabei die ganze Zeit `true` – Dart
  /// löst relativ zum Arbeitsverzeichnis auf, die native Bibliothek nicht.
  final probe =
      File(p.join('test', 'fixtures', 'werkzeuge', 'probe.mp4')).absolute;

  /// Baut die Bildfläche in den Baum, BEVOR geöffnet wird.
  ///
  /// Das ist keine Kosmetik, sondern die Voraussetzung: `media_kit`
  /// zeichnet seine Textur im Rasterschritt von Flutter. Ohne Widget-Baum
  /// plant Flutter gar keine Bilder – und `open()` wartet dann auf ein
  /// erstes Bild, das nie kommt. Gemessen unter Windows: Der Aufruf kehrt
  /// überhaupt nicht zurück, weder mit Fehler noch mit Zeitüberschreitung.
  Future<VideoPlaybackController> zeigeUndOeffne(WidgetTester tester) async {
    final steuerung = VideoPlaybackController();
    addTearDown(steuerung.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 240,
            child: VideoSurface(controller: steuerung),
          ),
        ),
      ),
    ));

    // runAsync, weil das Öffnen echte Zeit braucht: Der Testrahmen hält
    // sonst die Uhr an, und libmpv kommt nie zum Zug.
    final offen = await tester.runAsync(() => steuerung.open(probe));
    expect(offen, isTrue,
        reason: 'libmpv hat die Datei nicht angenommen – genau der Zustand, '
            'in dem unter Linux jedes Video schwarz blieb');
    await tester.pump(const Duration(milliseconds: 300));
    return steuerung;
  }

  testWidgets('öffnet ein Video und rückt die Position vor', (tester) async {
    expect(probe.existsSync(), isTrue, reason: 'Vorlage fehlt: ${probe.path}');
    final steuerung = await zeigeUndOeffne(tester);

    print('Dauer: ${steuerung.duration.inMilliseconds} ms');
    print('Seitenverhältnis: ${steuerung.aspectRatio}');

    // Drei Sekunden, mit etwas Spiel für die Containerangabe.
    expect(steuerung.duration.inMilliseconds, greaterThan(2500));
    expect(steuerung.duration.inMilliseconds, lessThan(3500));

    // Das Video hat keine Tonspur. Das ist Absicht: Ohne Bildausgabe wählt
    // mpv gar keinen Strom aus und meldet „No video or audio streams
    // selected". Dass es hier trotzdem läuft, belegt, dass die Bildausgabe
    // steht – und nicht bloss die Tonspur abgespielt wird.
    //
    // 320x240 sind 4:3. Der Rückfallwert von 16:9 gälte auch dann, wenn
    // die Maße nie angekommen wären – deshalb auf den echten Wert prüfen
    // und nicht bloss auf „grösser als null".
    expect(steuerung.aspectRatio, closeTo(4 / 3, 0.01),
        reason: '16/9 hiesse: die Bildmaße sind nie angekommen');

    await tester.runAsync(() async {
      await steuerung.play();
      // Echte Zeit vergehen lassen – der Fortschritt kommt aus libmpv,
      // nicht aus Flutters Uhr.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    });
    final position = steuerung.position;
    print('Position nach 1,2 s: ${position.inMilliseconds} ms');

    expect(position.inMilliseconds, greaterThan(200),
        reason: 'die Datei war offen, aber es wurde nichts abgespielt');
    expect(steuerung.isPlaying, isTrue);

    await tester.runAsync(() async {
      await steuerung.pause();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    final angehalten = steuerung.position;
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    expect(steuerung.position.inMilliseconds,
        closeTo(angehalten.inMilliseconds.toDouble(), 150),
        reason: 'nach pause() lief es weiter');
  });

  testWidgets('die Bildfläche bekommt eine Textur', (tester) async {
    final steuerung = await zeigeUndOeffne(tester);

    // Der eigentliche Beleg. Unter Linux hing genau daran die Wiedergabe:
    // Der Player lief, aber die Textur kam nie an – und ohne sie bleibt
    // die Fläche schwarz, ohne dass irgendetwas einen Fehler meldet.
    final id = steuerung.videoController.id.value;
    print('Textur: $id');
    expect(id, isNotNull,
        reason: 'ohne Textur bleibt die Videofläche schwarz');

    expect(find.byType(VideoSurface), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

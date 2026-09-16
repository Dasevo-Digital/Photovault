import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Das Standbild an **echten** Videos.
///
/// Läuft nur, wenn `PV_VIDEOPROBE` auf einen Ordner mit `library.sqlite`
/// und `library/` zeigt. An gebauten Bytes lässt sich prüfen, dass die
/// Abfragen die richtigen Aufnahmen auswählen; ob AVFoundation bzw. ffmpeg
/// aus einer echten Aufnahme ein brauchbares Bild holen, lässt sich nur
/// hier feststellen.
void main() {
  final ordner = Platform.environment['PV_VIDEOPROBE'];

  test('jedes Video bekommt ein Standbild in Vorschaugrösse', () async {
    if (ordner == null) {
      markTestSkipped('PV_VIDEOPROBE nicht gesetzt');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(p.join(ordner, 'library.sqlite'))));
    addTearDown(db.close);
    final pfade =
        await StoragePaths.forTesting(Directory(p.join(ordner, 'library')));
    final library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = ImportService(db, pfade);

    // **Erst prüfen, ob es hier überhaupt einen Bildgreifer gibt.** Im
    // reinen Prüflauf auf macOS steht der Method-Channel nicht bereit und
    // ffmpeg ist nicht installiert – dann greift niemand ein Standbild, und
    // ein Test, der daraufhin durchliefe, prüfte nichts. Er soll sich
    // deshalb ausdrücklich abmelden und nicht stillschweigend bestehen.
    final werkzeuge = await NativeImageConverter.bildwerkzeugstand();
    if (!werkzeuge.bereit) {
      markTestSkipped('kein Bildgreifer: ${werkzeuge.fehlende}');
      return;
    }

    final offen = await db.countThumbnailRegen(onlyMissing: true);
    final uhr = Stopwatch()..start();
    await library.regenerateThumbnails(onlyMissing: true).drain<void>();
    uhr.stop();

    final videos = await db.select(db.assets).get();
    final mitVorschau =
        videos.where((a) => a.previewRelativePath != null).toList();
    var kanten = <int>[];
    for (final a in mitVorschau) {
      final datei = pfade.absolute(a.previewRelativePath!);
      expect(datei.existsSync(), isTrue, reason: a.originalFileName);
      final bild = img.decodeImage(datei.readAsBytesSync())!;
      kanten.add(bild.width > bild.height ? bild.width : bild.height);
    }
    kanten = kanten..sort();

    // ignore: avoid_print
    print('offen $offen -> ${mitVorschau.length} von ${videos.length} mit '
        'Standbild, ${uhr.elapsedMilliseconds} ms '
        '(${(uhr.elapsedMilliseconds / videos.length).round()} ms je Video)');
    // ignore: avoid_print
    print('lange Kante: ${kanten.isEmpty ? '-' : '${kanten.first}..${kanten.last}'}');

    expect(mitVorschau.length, greaterThan(videos.length ~/ 2),
        reason: 'die Mehrheit muss ein Bild hergeben');
    // Gross genug für Gesichtserkennung und Texterkennung – das war der
    // Zweck der Umstellung von 800 auf 2048.
    expect(kanten.last, greaterThan(800));
  }, timeout: const Timeout(Duration(minutes: 15)));
}

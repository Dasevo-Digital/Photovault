import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/abgleich/zwischenspeicher.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Der Zwischenspeicher einer verbundenen Kopie (Issue #131): Vorschauen
/// und Originale werden gemessen, nach Alter begrenzt und geleert; der
/// Vorrat (Miniaturen, Gesichter) bleibt unangetastet.
void main() {
  late Directory ordner;
  late StoragePaths paths;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_zwischenspeicher_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    paths = await StoragePaths.forTesting(ordner);
  });

  File datei(Directory d, String name, int bytes, DateTime alt) {
    final f = File(p.join(d.path, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 7));
    f.setLastModifiedSync(alt);
    return f;
  }

  test('misst, begrenzt nach Alter und leert – der Vorrat bleibt', () async {
    final z = Zwischenspeicher(paths);
    expect(await z.groesse(), 0);
    final alt = datei(paths.previewsDir, 'a.jpg', 400, DateTime(2026, 1, 1));
    final mittel = datei(
      paths.originalsDir,
      'b.jpg',
      400,
      DateTime(2026, 2, 1),
    );
    final neu = datei(paths.previewsDir, 'c.jpg', 400, DateTime(2026, 3, 1));
    final mini = datei(paths.thumbnailsDir, 'm.jpg', 400, DateTime(2025));
    expect(await z.groesse(), 1200);

    // Unter 1000 Bytes bleiben heisst: auf 800 herunter – das Älteste geht.
    expect(await z.begrenze(1000), 400);
    expect(alt.existsSync(), isFalse);
    expect(mittel.existsSync(), isTrue);
    expect(neu.existsSync(), isTrue);
    expect(await z.begrenze(1000), 0, reason: 'schon unter der Grenze');

    expect(await z.leere(), 800);
    expect(await z.groesse(), 0);
    expect(mini.existsSync(), isTrue, reason: 'Miniaturen sind Vorrat');
  });

  test('ein Zugriff über bereit() macht die Datei wieder jung', () async {
    paths.beschaffe = (_) async => fail('liegt schon da');
    final f = datei(paths.previewsDir, 'a.jpg', 10, DateTime(2026, 1, 1));
    await paths.bereit('previews/a.jpg');
    expect(
      f.lastModifiedSync().isAfter(DateTime(2026, 6)),
      isTrue,
      reason: 'die Zeit des Zugriffs zählt beim Begrenzen',
    );
  });

  test('die Grenze steht in der Verbindungsdatei', () async {
    final v = Verbindungsdatei(
      server: Uri.parse('https://fotos.example.de/'),
      konto: 'anna',
      geraet: 'Telefon',
      token: 't',
    );
    await v.schreibe(ordner);
    expect((await Verbindungsdatei.lies(ordner))!.zwischenspeicherMb, isNull);
    await v.mitZwischenspeicher(512).schreibe(ordner);
    final gelesen = (await Verbindungsdatei.lies(ordner))!;
    expect(gelesen.zwischenspeicherMb, 512);
    expect(gelesen.mitRechenhilfe(true).zwischenspeicherMb, 512);
  });

  test('die Sprache der Handy-App steht in der Verbindungsdatei', () async {
    final v = Verbindungsdatei(
      server: Uri.parse('https://fotos.example.de/'),
      konto: 'anna',
      geraet: 'Telefon',
      token: 't',
      rasterspalten: 3,
    );
    await v.mitSprache('en').schreibe(ordner);
    final gelesen = (await Verbindungsdatei.lies(ordner))!;
    expect(gelesen.sprache, 'en');
    expect(gelesen.rasterspalten, 3, reason: 'anderes bleibt');
    await gelesen.mitSprache(null).schreibe(ordner);
    expect((await Verbindungsdatei.lies(ordner))!.sprache, isNull);
  });
}

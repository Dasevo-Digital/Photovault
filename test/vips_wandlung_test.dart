@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:path/path.dart' as p;

/// libvips verkleinert am Server (#274): schneller, mit einem Bruchteil
/// des Speichers und im linearen Licht. Ein vorgetäuschtes
/// `vipsthumbnail` schreibt hier auf, womit es gerufen wird; ob libvips
/// selbst richtig rechnet, prüft werkzeuge_echt_test.dart unter Linux.
void main() {
  late Directory temp;
  late File protokoll;
  late File antwort;

  /// Ein Skript, das seine Argumente notiert und [antwort] an die Stelle
  /// hinter `-o` legt (ohne die Optionen in eckigen Klammern) – oder mit
  /// [code] scheitert.
  String werkzeug(String name, {int code = 0}) {
    final f = File(p.join(temp.path, name))
      ..writeAsStringSync('''#!/bin/sh
for a in "\$@"; do printf '%s\\n' "\$a"; done >> "${protokoll.path}"
echo --- >> "${protokoll.path}"
[ $code -ne 0 ] && exit $code
ziel=""; vorher=""
for a in "\$@"; do
  if [ "\$vorher" = "-o" ]; then ziel="\${a%%[*}"; fi
  vorher="\$a"
done
cp "${antwort.path}" "\$ziel"
''');
    Process.runSync('chmod', ['+x', f.path]);
    return f.path;
  }

  List<List<String>> aufrufe() {
    final teile = <List<String>>[[]];
    for (final z in protokoll.readAsLinesSync()) {
      if (z == '---') {
        teile.add([]);
      } else {
        teile.last.add(z);
      }
    }
    return teile.where((t) => t.isNotEmpty).toList();
  }

  File jpeg(String name, int breite, int hoehe) => File(p.join(temp.path, name))
    ..writeAsBytesSync(img.encodeJpg(img.Image(width: breite, height: hoehe)));

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_vips_');
    protokoll = File(p.join(temp.path, 'aufrufe.txt'))..writeAsStringSync('');
    antwort = jpeg('antwort.jpg', 8, 6);
  });

  tearDown(() {
    DesktopImageTools.vergissWerkzeuge();
    temp.deleteSync(recursive: true);
  });

  test('ein JPEG: verkleinert im linearen Licht, gedreht, nur das Profil '
      'bleibt', () async {
    DesktopImageTools.stelleWerkzeuge({
      'vipsthumbnail': werkzeug('vipsthumbnail'),
    });
    final quelle = jpeg('foto.jpg', 64, 48);

    final r = await DesktopImageTools.convertToJpeg(quelle, maxDimension: 2048);

    expect(r, antwort.readAsBytesSync(), reason: 'das Ergebnis von libvips');
    final a = aufrufe().single;
    expect(a.first, quelle.path);
    expect(a, containsAllInOrder(['--size', '2048x2048>']));
    expect(a, contains('--linear'));
    expect(a, isNot(contains('--no-rotate')), reason: 'EXIF-Lage anwenden');
    expect(a.last, endsWith('[Q=90,keep=icc]'));
  });

  test('volle Auflösung: nicht verkleinern, kein lineares Licht', () async {
    DesktopImageTools.stelleWerkzeuge({
      'vipsthumbnail': werkzeug('vipsthumbnail'),
    });

    await DesktopImageTools.convertToJpeg(
      jpeg('foto.jpg', 64, 48),
      maxDimension: 1 << 20,
      quality: 85,
    );

    final a = aufrufe().single;
    expect(a, containsAllInOrder(['--size', '65536x65536>']));
    expect(a, isNot(contains('--linear')));
    expect(a.last, endsWith('[Q=85,keep=icc]'));
  });

  test('das Bild von heif-dec liegt schon richtig', () async {
    DesktopImageTools.stelleWerkzeuge({
      'heif-dec': werkzeug('heif-dec-ersatz'),
      'vipsthumbnail': werkzeug('vipsthumbnail'),
    });
    // heif-dec schreibt sein Ergebnis an das zweite Argument.
    File(p.join(temp.path, 'heif-dec-ersatz')).writeAsStringSync('''#!/bin/sh
echo heif-dec >> "${protokoll.path}"
echo --- >> "${protokoll.path}"
cp "${antwort.path}" "\$2"
''');
    final heic = File(p.join(temp.path, 'foto.heic'))..writeAsBytesSync([0]);

    final r = await DesktopImageTools.convertToJpeg(heic, maxDimension: 2048);

    expect(r, antwort.readAsBytesSync());
    final vips = aufrufe().last;
    expect(vips, contains('--no-rotate'));
    expect(vips, contains('--linear'));
  });

  test('scheitert libvips, rechnet Dart wie bisher', () async {
    DesktopImageTools.stelleWerkzeuge({
      'vipsthumbnail': werkzeug('vipsthumbnail', code: 1),
    });

    final r = await DesktopImageTools.convertToJpeg(
      jpeg('foto.jpg', 64, 48),
      maxDimension: 32,
    );

    final bild = img.decodeJpg(r!)!;
    expect(bild.width, 32, reason: 'von Dart verkleinert');
    expect(aufrufe(), hasLength(1), reason: 'libvips wurde gefragt');
  });

  test('ohne libvips fragt niemand danach', () async {
    DesktopImageTools.stelleWerkzeuge({});
    final r = await DesktopImageTools.convertToJpeg(
      jpeg('foto.jpg', 64, 48),
      maxDimension: 16,
    );
    expect(img.decodeJpg(r!)!.width, 16);
    expect(protokoll.readAsStringSync(), isEmpty);
  });
}

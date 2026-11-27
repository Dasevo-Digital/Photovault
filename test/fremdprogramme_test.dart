import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/fremdprogramme.dart';

/// Ein nachgestelltes Dateisystem: jeder Eintrag ein Pfad, die Ordner
/// ergeben sich daraus. So lässt sich die Erkennung für alle drei Systeme
/// auf einem Rechner prüfen, auf dem keines der Programme installiert ist.
class _Blick implements Systemblick {
  _Blick(
    this.system,
    Iterable<String> pfade, {
    this.umgebung = const {},
    this.registrierung = const {},
  }) : _pfade = pfade.toSet();

  @override
  final String system;
  @override
  final Map<String, String> umgebung;
  final Map<String, String> registrierung;
  final Set<String> _pfade;
  final gelesen = <String>[];

  p.Context get _k => system == 'windows' ? p.windows : p.posix;

  @override
  Future<List<String>> namenIn(String ordner) async {
    gelesen.add(ordner);
    final namen = <String>{};
    for (final x in _pfade) {
      if (!_k.isWithin(ordner, x)) continue;
      namen.add(_k.split(_k.relative(x, from: ordner)).first);
    }
    return namen.toList();
  }

  @override
  Future<bool> gibtEs(String pfad) async =>
      _pfade.any((x) => _k.equals(x, pfad) || _k.isWithin(pfad, x));

  @override
  Future<String?> appPfad(String exe) async => registrierung[exe];
}

void main() {
  group('Erkennung macOS', () {
    test('findet Bündel, auch in Herstellerordnern, und nimmt das neueste '
        'Jahr', () async {
      final gefunden = await erkenneProgramme(
        _Blick(
          'macos',
          [
            '/Applications/darktable.app/Contents/Info.plist',
            '/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app/x',
            '/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app/x',
            '/Applications/ON1 Photo RAW 2026.app/x',
            '/Applications/ON1 Photo RAW 2027/ON1 Photo RAW 2027.app/x',
            '/Applications/Affinity Photo 2.app/x',
            '/Users/x/Applications/GIMP.app/x',
          ],
          // In der Sandbox: HOME ist der Container.
          umgebung: {
            'HOME': '/Users/x/Library/Containers/de.dasevo.photovault/Data',
          },
        ),
      );
      expect(gefunden, {
        Bekannt.darktable: '/Applications/darktable.app',
        Bekannt.photoshop:
            '/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app',
        Bekannt.on1: '/Applications/ON1 Photo RAW 2027/ON1 Photo RAW 2027.app',
        Bekannt.affinity: '/Applications/Affinity Photo 2.app',
        Bekannt.gimp: '/Users/x/Applications/GIMP.app',
      });
    });

    test('Gegenprobe: Lightroom und Elements sind kein Photoshop, und in '
        'fremde Ordner wird nicht hineingesehen', () async {
      final blick = _Blick('macos', [
        '/Applications/Adobe Photoshop Lightroom Classic/'
            'Adobe Lightroom Classic.app/x',
        '/Applications/Adobe Photoshop Elements 2025/'
            'Adobe Photoshop Elements 2025.app/x',
        '/Applications/Werkzeuge/GIMP.app/x',
        '/Applications/Safari.app/x',
      ]);
      expect(await erkenneProgramme(blick), isEmpty);
      expect(blick.gelesen, isNot(contains('/Applications/Werkzeuge')));
    });

    test('GIMP 2.10 heisst anders als GIMP 3', () async {
      final gefunden = await erkenneProgramme(
        _Blick('macos', [
          '/Applications/GIMP-2.10.app/x',
          '/Applications/GIMP.app/x',
        ]),
      );
      expect(gefunden[Bekannt.gimp], '/Applications/GIMP-2.10.app');
    });
  });

  group('Erkennung Windows', () {
    const umgebung = {
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      'LOCALAPPDATA': r'C:\Users\x\AppData\Local',
    };

    test('Programmordner, Herstellerordner und Nutzerinstallation', () async {
      final gefunden = await erkenneProgramme(
        _Blick('windows', [
          r'C:\Program Files\darktable\bin\darktable.exe',
          r'C:\Program Files\GIMP 3\bin\gimp-3.0.exe',
          r'C:\Program Files\GIMP 3\bin\gimp-console-3.0.exe',
          r'C:\Program Files\Adobe\Adobe Photoshop 2025\Photoshop.exe',
          r'C:\Program Files\Adobe\Adobe Photoshop 2026\Photoshop.exe',
          r'C:\Program Files\Affinity\Photo 2\Photo.exe',
          r'C:\Users\x\AppData\Local\Programs\ON1\ON1 Photo RAW 2027'
              r'\ON1 Photo RAW 2027.exe',
        ], umgebung: umgebung),
      );
      expect(gefunden, {
        Bekannt.darktable: r'C:\Program Files\darktable\bin\darktable.exe',
        Bekannt.gimp: r'C:\Program Files\GIMP 3\bin\gimp-3.0.exe',
        Bekannt.photoshop:
            r'C:\Program Files\Adobe\Adobe Photoshop 2026\Photoshop.exe',
        Bekannt.affinity: r'C:\Program Files\Affinity\Photo 2\Photo.exe',
        Bekannt.on1:
            r'C:\Users\x\AppData\Local\Programs\ON1\ON1 Photo RAW 2027'
            r'\ON1 Photo RAW 2027.exe',
      });
    });

    test('die Registrierung hilft, wo die Ordner nichts ergeben – aber nur '
        'mit einer Datei dahinter', () async {
      final gefunden = await erkenneProgramme(
        _Blick(
          'windows',
          [r'D:\Adobe\Photoshop\Photoshop.exe'],
          umgebung: umgebung,
          registrierung: {
            'Photoshop.exe': r'D:\Adobe\Photoshop\Photoshop.exe',
            'darktable.exe': r'E:\weg\darktable.exe',
          },
        ),
      );
      expect(gefunden, {
        Bekannt.photoshop: r'D:\Adobe\Photoshop\Photoshop.exe',
      });
    });

    test('appPfadAus liest den Standardwert und löst Variablen auf', () {
      const ausgabe =
          '\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\'
          'CurrentVersion\\App Paths\\Photoshop.exe\r\n'
          '    (Standard)    REG_EXPAND_SZ    "%ProgramFiles%\\Adobe\\'
          'Photoshop.exe"\r\n\r\n';
      expect(
        appPfadAus(ausgabe, const {'PROGRAMFILES': r'C:\Program Files'}),
        r'C:\Program Files\Adobe\Photoshop.exe',
      );
      expect(appPfadAus('FEHLER: nicht gefunden', const {}), isNull);
    });
  });

  group('Erkennung Linux', () {
    test('PATH vor Flatpak; Photoshop gibt es dort nicht', () async {
      final gefunden = await erkenneProgramme(
        _Blick(
          'linux',
          [
            '/usr/bin/darktable',
            '/var/lib/flatpak/exports/bin/org.darktable.Darktable',
            '/home/x/.local/share/flatpak/exports/bin/org.gimp.GIMP',
          ],
          umgebung: {'PATH': '/usr/local/bin:/usr/bin', 'HOME': '/home/x'},
        ),
      );
      expect(gefunden, {
        Bekannt.darktable: '/usr/bin/darktable',
        Bekannt.gimp: '/home/x/.local/share/flatpak/exports/bin/org.gimp.GIMP',
      });
      expect(Bekannt.photoshop.gibtEsAuf('linux'), isFalse);
      expect(Bekannt.gimp.gibtEsAuf('linux'), isTrue);
    });

    test('Gegenprobe: im eigenen Flatpak wird nichts gemeldet', () async {
      final gefunden = await erkenneProgramme(
        _Blick(
          'linux',
          ['/usr/bin/darktable', '/usr/bin/gimp'],
          umgebung: {'PATH': '/usr/bin', 'FLATPAK_ID': 'de.dasevo.photovault'},
        ),
      );
      expect(gefunden, isEmpty);
    });
  });

  group('Start', () {
    // Als Text: Ein Datensatz mit einer Liste darin vergliche die Liste
    // nach Identität.
    late List<String> aufrufe;
    late bool klappt;
    Future<bool> ausfuehren(
      String programm,
      List<String> argumente, {
      required bool warten,
    }) async {
      aufrufe.add([programm, ...argumente, if (warten) '(wartet)'].join(' | '));
      return klappt;
    }

    setUp(() {
      aufrufe = [];
      klappt = true;
    });

    test('macOS: open -a mit dem gefundenen Bündel', () async {
      final starter = Programmstarter(system: 'macos', ausfuehren: ausfuehren);
      final ok = await starter.starte(
        Fremdprogramm.bekannt(Bekannt.gimp, pfad: '/Applications/GIMP.app'),
        '/x/a.jpg',
      );
      expect(ok, isTrue);
      expect(
        aufrufe.single,
        'open | -a | /Applications/GIMP.app | /x/a.jpg | (wartet)',
      );
      klappt = false;
      expect(
        await starter.starte(
          Fremdprogramm.bekannt(Bekannt.gimp, pfad: '/Applications/GIMP.app'),
          '/x/a.jpg',
        ),
        isFalse,
        reason: 'open meldet einen Fehler',
      );
    });

    test('darktable ohne Fund: der Weg von vor #499', () async {
      final darktable = Fremdprogramm.bekannt(Bekannt.darktable);
      await Programmstarter(
        system: 'macos',
        ausfuehren: ausfuehren,
      ).starte(darktable, '/x/a.cr3');
      await Programmstarter(
        system: 'linux',
        umgebung: const {},
        ausfuehren: ausfuehren,
      ).starte(darktable, '/x/a.cr3');
      await Programmstarter(
        system: 'windows',
        umgebung: const {'ProgramFiles': r'C:\Programme'},
        gibtEs: (_) async => true,
        ausfuehren: ausfuehren,
      ).starte(darktable, r'C:\x\a.cr3');
      expect(aufrufe, [
        'open | -a | darktable | /x/a.cr3 | (wartet)',
        'darktable | /x/a.cr3',
        r'C:\Programme\darktable\bin\darktable.exe | C:\x\a.cr3',
      ]);
    });

    test('Windows: nur eine vorhandene .exe wird gestartet', () async {
      final starter = Programmstarter(
        system: 'windows',
        umgebung: const {},
        gibtEs: (pfad) async => pfad == r'C:\Adobe\Photoshop.exe',
        ausfuehren: ausfuehren,
      );
      expect(
        await starter.starte(
          Fremdprogramm.bekannt(
            Bekannt.photoshop,
            pfad: r'C:\Adobe\Photoshop.exe',
          ),
          r'C:\x\a.tif',
        ),
        isTrue,
      );
      expect(
        await starter.starte(
          Fremdprogramm.bekannt(Bekannt.photoshop, pfad: r'C:\weg.exe'),
          r'C:\x\a.tif',
        ),
        isFalse,
      );
      expect(
        await starter.starte(
          Fremdprogramm.bekannt(Bekannt.affinity),
          r'C:\x\a.tif',
        ),
        isFalse,
        reason: 'ohne Pfad kein Start',
      );
      expect(aufrufe.single, r'C:\Adobe\Photoshop.exe | C:\x\a.tif');
    });

    test('Linux: im Flatpak wird nichts gestartet', () async {
      final gimp = Fremdprogramm.bekannt(Bekannt.gimp, pfad: '/usr/bin/gimp');
      expect(
        await Programmstarter(
          system: 'linux',
          umgebung: const {},
          ausfuehren: ausfuehren,
        ).starte(gimp, '/x/a.jpg'),
        isTrue,
      );
      expect(
        await Programmstarter(
          system: 'linux',
          umgebung: const {'FLATPAK_ID': 'de.dasevo.photovault'},
          ausfuehren: ausfuehren,
        ).starte(gimp, '/x/a.jpg'),
        isFalse,
      );
      expect(aufrufe.single, '/usr/bin/gimp | /x/a.jpg');
    });
  });

  group('ergebnisAlsJpeg', () {
    late Directory ordner;
    setUp(() => ordner = Directory.systemTemp.createTempSync('pv_wandeln_'));
    tearDown(() => ordner.deleteSync(recursive: true));

    File lege(String name, Uint8List bytes) =>
        File(p.join(ordner.path, name))..writeAsBytesSync(bytes);

    test(
      'ein JPEG geht unverändert durch, auch unter falscher Endung',
      () async {
        final jpeg = img.encodeJpg(img.Image(width: 4, height: 3));
        expect(await ergebnisAlsJpeg(lege('a.jpg', jpeg)), jpeg);
        expect(await ergebnisAlsJpeg(lege('a.tif', jpeg)), jpeg);
      },
    );

    test('TIFF und PNG werden zu JPEG in voller Grösse', () async {
      final bild = img.Image(width: 30, height: 20)
        ..clear(img.ColorRgb8(200, 40, 40));
      for (final datei in [
        lege('a.tif', img.encodeTiff(bild)),
        lege('a.png', img.encodePng(bild)),
      ]) {
        final jpeg = await ergebnisAlsJpeg(datei);
        expect(jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF], reason: datei.path);
        final zurueck = img.decodeJpg(jpeg)!;
        expect((zurueck.width, zurueck.height), (30, 20));
        expect(zurueck.getPixel(5, 5).r, closeTo(200, 8));
      }
    });

    test('ein durchsichtiges PNG wird weiss, nicht schwarz', () async {
      final bild = img.Image(width: 8, height: 8, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      final jpeg = await ergebnisAlsJpeg(lege('a.png', img.encodePng(bild)));
      expect(img.decodeJpg(jpeg)!.getPixel(2, 2).r, greaterThan(240));
    });

    test('Gegenprobe: kein Bild → ErgebnisUnlesbar', () async {
      await expectLater(
        ergebnisAlsJpeg(lege('a.tif', Uint8List.fromList([1, 2, 3, 4, 5]))),
        throwsA(isA<ErgebnisUnlesbar>()),
      );
    });
  });
}

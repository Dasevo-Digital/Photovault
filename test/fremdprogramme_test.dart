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

    test('der Nachfolger ohne Nummer gewinnt: GIMP 3 vor GIMP 2.10, das '
        'neue Affinity vor Affinity Photo 2', () async {
      final gefunden = await erkenneProgramme(
        _Blick('macos', [
          '/Applications/GIMP-2.10.app/x',
          '/Applications/GIMP.app/x',
          '/Applications/Affinity Photo 2.app/x',
          '/Applications/Affinity Photo.app/x',
          '/Applications/Affinity.app/x',
        ]),
      );
      expect(gefunden[Bekannt.gimp], '/Applications/GIMP.app');
      expect(gefunden[Bekannt.affinity], '/Applications/Affinity.app');
    });

    test(
      'Gegenprobe: innerhalb einer Generation zählt weiter die Nummer',
      () async {
        final gefunden = await erkenneProgramme(
          _Blick('macos', [
            '/Applications/GIMP-2.8.app/x',
            '/Applications/GIMP-2.10.app/x',
            '/Applications/Affinity Photo.app/x',
            '/Applications/Affinity Photo 2.app/x',
          ]),
        );
        expect(gefunden[Bekannt.gimp], '/Applications/GIMP-2.10.app');
        expect(
          gefunden[Bekannt.affinity],
          '/Applications/Affinity Photo 2.app',
        );
      },
    );
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

    test('das neue Affinity vor Affinity Photo 2', () async {
      final gefunden = await erkenneProgramme(
        _Blick('windows', [
          r'C:\Program Files\Affinity\Photo 2\Photo.exe',
          r'C:\Program Files\Affinity\Affinity\Affinity.exe',
        ], umgebung: umgebung),
      );
      expect(
        gefunden[Bekannt.affinity],
        r'C:\Program Files\Affinity\Affinity\Affinity.exe',
      );
    });

    test('Gegenprobe: eine .bat aus der Registrierung gilt nicht', () async {
      final gefunden = await erkenneProgramme(
        _Blick(
          'windows',
          [r'D:\x\photoshop.bat', r'D:\y\Photoshop.exe'],
          umgebung: umgebung,
          registrierung: {'Photoshop.exe': r'D:\x\photoshop.bat'},
        ),
      );
      expect(gefunden, isEmpty);
    });

    test('reg.exe mit vollem Pfad aus dem Systemordner', () async {
      final aufrufe = <String>[];
      final blick = EchterSystemblick(
        system: 'windows',
        umgebung: const {'SystemRoot': r'D:\Win'},
        laufe: (programm, argumente) async {
          aufrufe.add(programm);
          return ProcessResult(
            0,
            0,
            '    (Standard)    REG_SZ    C:\\PS\\Photoshop.exe\r\n',
            '',
          );
        },
      );
      expect(await blick.appPfad('Photoshop.exe'), r'C:\PS\Photoshop.exe');
      expect(aufrufe, [r'D:\Win\System32\reg.exe']);
      expect(regPfad(const {}), r'C:\Windows\System32\reg.exe');
      expect(
        await const EchterSystemblick(system: 'macos').appPfad('x.exe'),
        isNull,
      );
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

    test('Windows: eine .bat oder .cmd wird nie gestartet', () async {
      final starter = Programmstarter(
        system: 'windows',
        umgebung: const {},
        gibtEs: (_) async => true,
        ausfuehren: ausfuehren,
      );
      for (final pfad in [r'C:\x\Bild.bat', r'C:\x\Bild.CMD', r'C:\x\b']) {
        expect(
          await starter.starte(
            Fremdprogramm(
              kennung: 'eigen:$pfad',
              name: 'x',
              ordner: 'o',
              pfad: pfad,
            ),
            r'C:\x\a & calc.jpg',
          ),
          isFalse,
          reason: pfad,
        );
      }
      expect(aufrufe, isEmpty);
      expect(
        await starter.starte(
          const Fremdprogramm(
            kennung: 'eigen:x',
            name: 'x',
            ordner: 'o',
            pfad: r'C:\x\Bild.EXE',
          ),
          r'C:\x\a.jpg',
        ),
        isTrue,
      );
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

    // Ohne Werkzeuge des Systems: so, wie auf einem Prüfrechner ohne
    // libvips und ohne den Kanal der App.
    Future<Uint8List?> ohneWerkzeug(File _) async => null;

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
        final jpeg = await ergebnisAlsJpeg(datei, tiff: ohneWerkzeug);
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

    group('vollständig (#499)', () {
      Uint8List rauschen(int kante) {
        final bild = img.Image(width: kante, height: kante);
        var x = 7;
        for (final px in bild) {
          x = (x * 1103515245 + 12345) & 0x7fffffff;
          px
            ..r = x & 0xff
            ..g = (x >> 8) & 0xff
            ..b = (x >> 16) & 0xff;
        }
        return img.encodeJpg(bild, quality: 90);
      }

      test('ein abgeschnittenes JPEG wird nicht übernommen', () async {
        final ganz = rauschen(64);
        expect(jpegVollstaendig(ganz), isTrue);
        final halb = Uint8List.sublistView(ganz, 0, ganz.length ~/ 2);
        expect(jpegVollstaendig(halb), isFalse);
        await expectLater(
          ergebnisAlsJpeg(lege('a.jpg', halb)),
          throwsA(
            isA<ErgebnisUnlesbar>().having(
              (e) => e.grund,
              'grund',
              Unlesbarkeit.unvollstaendig,
            ),
          ),
        );
      });

      test('Daten hinter dem Ende sind erlaubt', () async {
        final ganz = rauschen(16);
        final mitAnhang = Uint8List.fromList([...ganz, 0, 0, 1, 2, 3, 0xFF]);
        expect(await ergebnisAlsJpeg(lege('a.jpg', mitAnhang)), mitAnhang);
      });

      test('Gegenprobe: das Ende des Vorschaubilds im EXIF ist nicht das '
          'Ende des Bildes', () {
        final vorschau = rauschen(8);
        final haupt = rauschen(64);
        final inhalt = [...'Exif'.codeUnits, 0, 0, ...vorschau];
        final laenge = inhalt.length + 2;
        final mitVorschau = Uint8List.fromList([
          0xFF, 0xD8, // SOI
          0xFF, 0xE1, laenge >> 8, laenge & 0xff, ...inhalt, // APP1
          ...haupt.sublist(2),
        ]);
        expect(jpegVollstaendig(mitVorschau), isTrue);
        final abgeschnitten = Uint8List.sublistView(
          mitVorschau,
          0,
          mitVorschau.length - haupt.length ~/ 2,
        );
        expect(jpegVollstaendig(abgeschnitten), isFalse);
      });
    });

    group('TIFF (#499)', () {
      test('TIFF geht zuerst an die Werkzeuge des Systems, PNG und JPEG '
          'nicht', () async {
        final vonWerkzeug = img.encodeJpg(img.Image(width: 2, height: 2));
        final gefragt = <String>[];
        Future<Uint8List?> werkzeug(File f) async {
          gefragt.add(p.basename(f.path));
          return vonWerkzeug;
        }

        final bild = img.Image(width: 4, height: 3);
        expect(
          await ergebnisAlsJpeg(
            lege('a.tif', img.encodeTiff(bild)),
            tiff: werkzeug,
          ),
          vonWerkzeug,
        );
        await ergebnisAlsJpeg(
          lege('a.png', img.encodePng(bild)),
          tiff: werkzeug,
        );
        await ergebnisAlsJpeg(
          lege('a.jpg', img.encodeJpg(bild)),
          tiff: werkzeug,
        );
        expect(gefragt, ['a.tif']);
      });

      test(
        'scheitert das Werkzeug oder liefert es Halbes, rechnet Dart',
        () async {
          final tif = lege('a.tif', _tiff());
          for (final werkzeug in <Future<Uint8List?> Function(File)>[
            ohneWerkzeug,
            (_) async => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16]),
            (_) async => throw const FileSystemException('weg'),
          ]) {
            final jpeg = await ergebnisAlsJpeg(tif, tiff: werkzeug);
            expect(img.decodeJpg(jpeg)!.width, 4);
          }
        },
      );

      test('das Farbprofil geht mit', () async {
        final icc = Uint8List.fromList(List.generate(300, (i) => i % 251));
        // Gegenprobe: Der Leser von package:image allein verliert es.
        expect(img.decodeTiff(_tiff(icc: icc))!.iccProfile, isNull);
        final jpeg = await ergebnisAlsJpeg(
          lege('a.tif', _tiff(icc: icc)),
          tiff: ohneWerkzeug,
        );
        expect(img.decodeJpg(jpeg)!.iccProfile?.decompressed(), icc);
      });

      test('ohne Werkzeug abgelehnt: LZW, Deflate mit Prädiktor, 16-Bit-LZW, '
          'JPEG im TIFF', () async {
        for (final (kompression, praediktor, bits) in [
          (5, 1, 8),
          (5, 2, 8),
          (5, 2, 16),
          (8, 2, 8),
          (32946, 2, 16),
          (7, 1, 8),
        ]) {
          final datei = lege(
            'a.tif',
            _tiff(kompression: kompression, praediktor: praediktor, bits: bits),
          );
          await expectLater(
            ergebnisAlsJpeg(datei, tiff: ohneWerkzeug),
            throwsA(
              isA<ErgebnisUnlesbar>().having(
                (e) => e.grund,
                'grund',
                Unlesbarkeit.nurMitWerkzeug,
              ),
            ),
            reason: '$kompression/$praediktor/$bits',
          );
          // Gegenprobe: Das Werkzeug des Systems liest es.
          final vonWerkzeug = img.encodeJpg(img.Image(width: 4, height: 3));
          expect(
            await ergebnisAlsJpeg(datei, tiff: (_) async => vonWerkzeug),
            vonWerkzeug,
          );
        }
      });

      test('Gegenprobe: Deflate ohne Prädiktor rechnet Dart selbst', () async {
        final jpeg = await ergebnisAlsJpeg(
          lege('a.tif', _tiff(kompression: 8)),
          tiff: ohneWerkzeug,
        );
        expect(img.decodeJpg(jpeg)!.getPixel(1, 1).r, closeTo(200, 8));
      });

      test('zu gross: abgelehnt, ehe etwas dekodiert wird', () async {
        final datei = lege(
          'a.tif',
          _tiff(breiteAngabe: 20000, hoeheAngabe: 10000),
        );
        await expectLater(
          ergebnisAlsJpeg(datei, tiff: ohneWerkzeug),
          throwsA(
            isA<ErgebnisUnlesbar>()
                .having((e) => e.grund, 'grund', Unlesbarkeit.zuGross)
                .having((e) => e.megapixel, 'megapixel', 200),
          ),
        );
      });

      test(
        'nur die erste Seite eines mehrseitigen TIFF wird gelesen',
        () async {
          final zweiseitig = _tiff(zweiteSeiteKaputt: true);
          // Gegenprobe: Alle Seiten zu lesen scheitert an der zweiten.
          expect(() => img.decodeTiff(zweiseitig), throwsA(anything));
          final jpeg = await ergebnisAlsJpeg(
            lege('a.tif', zweiseitig),
            tiff: ohneWerkzeug,
          );
          expect(img.decodeJpg(jpeg)!.width, 4);
        },
      );
    });
  });
}

/// Ein kleines TIFF von Hand: RGB, ein Streifen, rot – mit frei wählbarer
/// Kompression, Prädiktor und Bittiefe und auf Wunsch einem Farbprofil.
/// So lässt sich prüfen, was Dart ablehnt, ohne solche Dateien echt
/// kodieren zu müssen; abgelehnt wird vor dem Lesen der Pixel.
Uint8List _tiff({
  int kompression = 1,
  int praediktor = 1,
  int bits = 8,
  Uint8List? icc,
  int? breiteAngabe,
  int? hoeheAngabe,
  bool zweiteSeiteKaputt = false,
}) {
  const breite = 4, hoehe = 3;
  final roh = <int>[
    for (var i = 0; i < breite * hoehe; i++)
      for (final wert in [200, 40, 40]) ...(bits == 16 ? [0, wert] : [wert]),
  ];
  final pixel = kompression == 8
      ? Uint8List.fromList(zlib.encode(roh))
      : Uint8List.fromList(roh);

  final eintraege = <(int, int, int, int)>[];
  final anhang = BytesBuilder();
  const kopf = 8;
  int eintragszahl(bool mitIcc) => 11 + (mitIcc ? 1 : 0);
  final ifdLaenge = 2 + eintragszahl(icc != null) * 12 + 4;
  var frei = kopf + ifdLaenge;
  int lege(List<int> daten) {
    final stelle = frei;
    anhang.add(daten);
    frei += daten.length;
    return stelle;
  }

  final bpsStelle = lege([bits, 0, bits, 0, bits, 0]);
  final iccStelle = icc == null ? null : lege(icc);
  final pixelStelle = lege(pixel);
  const kurz = 3, lang = 4, undef = 7;
  eintraege
    ..add((256, lang, 1, breiteAngabe ?? breite))
    ..add((257, lang, 1, hoeheAngabe ?? hoehe))
    ..add((258, kurz, 3, bpsStelle))
    ..add((259, kurz, 1, kompression))
    ..add((262, kurz, 1, 2))
    ..add((273, lang, 1, pixelStelle))
    ..add((277, kurz, 1, 3))
    ..add((278, lang, 1, hoehe))
    ..add((279, lang, 1, pixel.length))
    ..add((284, kurz, 1, 1))
    ..add((317, kurz, 1, praediktor));
  if (icc != null) eintraege.add((34675, undef, icc.length, iccStelle!));

  int? zweiteSeite;
  final zweite = BytesBuilder();
  if (zweiteSeiteKaputt) {
    zweiteSeite = frei;
    final d = ByteData(2 + 4 * 12 + 4)..setUint16(0, 4, Endian.little);
    var o = 2;
    for (final (tag, typ, zahl, wert) in [
      (256, lang, 1, 50),
      (257, lang, 1, 50),
      // Der Streifen liegt weit hinter dem Ende der Datei.
      (273, lang, 1, 1 << 24),
      (279, lang, 1, 7500),
    ]) {
      d
        ..setUint16(o, tag, Endian.little)
        ..setUint16(o + 2, typ, Endian.little)
        ..setUint32(o + 4, zahl, Endian.little)
        ..setUint32(o + 8, wert, Endian.little);
      o += 12;
    }
    zweite.add(d.buffer.asUint8List());
  }

  final ifd = ByteData(ifdLaenge)
    ..setUint16(0, eintraege.length, Endian.little);
  var o = 2;
  for (final (tag, typ, zahl, wert) in eintraege) {
    ifd
      ..setUint16(o, tag, Endian.little)
      ..setUint16(o + 2, typ, Endian.little)
      ..setUint32(o + 4, zahl, Endian.little);
    if (typ == kurz && zahl == 1) {
      ifd.setUint16(o + 8, wert, Endian.little);
    } else {
      ifd.setUint32(o + 8, wert, Endian.little);
    }
    o += 12;
  }
  ifd.setUint32(o, zweiteSeite ?? 0, Endian.little);
  return Uint8List.fromList([
    0x49, 0x49, 42, 0, kopf, 0, 0, 0, //
    ...ifd.buffer.asUint8List(),
    ...anhang.takeBytes(),
    ...zweite.takeBytes(),
  ]);
}

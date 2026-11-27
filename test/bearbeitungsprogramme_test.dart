import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/bearbeitungsbruecke.dart';
import 'package:photo_vault/services/bearbeitungsprogramme.dart';
import 'package:photo_vault/services/darktable_bruecke.dart';
import 'package:photo_vault/services/fremdprogramme.dart';

/// Die Liste unter „Bearbeiten in“ (#499): was ohne Einstellung gilt, was
/// gespeichert wird, und wohin die Arbeitskopien gehen.
void main() {
  late Directory wurzel;
  late File datei;
  late Map<Bekannt, String> gefunden;
  late List<String> aufrufe;

  setUp(() {
    wurzel = Directory.systemTemp.createTempSync('pv_programme_');
    datei = File(p.join(wurzel.path, 'daten', 'bearbeiten_in.json'));
    gefunden = {Bekannt.gimp: '/Applications/GIMP.app'};
    aufrufe = [];
  });
  tearDown(() => wurzel.deleteSync(recursive: true));

  Bearbeitungsprogramme neu({String system = 'macos'}) => Bearbeitungsprogramme(
    basis: Directory(p.join(wurzel.path, 'Bilder')),
    einstellungen: () async => datei,
    system: system,
    erkenne: () async => gefunden,
    starter: Programmstarter(
      system: system,
      umgebung: const {},
      ausfuehren: (programm, argumente, {required warten}) async {
        aufrufe.add([programm, ...argumente].join(' | '));
        return true;
      },
    ),
  );

  Map<String, bool> schalter(Bearbeitungsprogramme x) => {
    for (final y in x.alle) y.kennung: y.aktiv,
  };

  test('ohne Einstellung: darktable immer, sonst was gefunden wurde', () async {
    final programme = neu();
    expect(programme.aktive.map((x) => x.name), ['darktable']);
    await programme.laden();
    expect(schalter(programme), {
      'darktable': true,
      'on1': false,
      'affinity': false,
      'photoshop': false,
      'gimp': true,
    });
    expect(
      programme.alle.singleWhere((x) => x.art == Bekannt.gimp).pfad,
      '/Applications/GIMP.app',
    );
  });

  test('unter Linux stehen nur darktable und GIMP in der Liste', () async {
    final programme = neu(system: 'linux');
    await programme.laden();
    expect(programme.alle.map((x) => x.art), [Bekannt.darktable, Bekannt.gimp]);
  });

  test('Schalter überdauern einen Neustart', () async {
    final programme = neu();
    await programme.laden();
    await programme.schalte('darktable', false);
    await programme.schalte('photoshop', true);
    final danach = neu();
    await danach.laden();
    expect(schalter(danach)['darktable'], isFalse);
    expect(schalter(danach)['photoshop'], isTrue);
    expect(danach.aktive.map((x) => x.name), ['Adobe Photoshop', 'GIMP']);
  });

  test('wer schaltet, bevor gelesen ist, verliert die eigenen Programme '
      'nicht', () async {
    final erste = neu();
    await erste.fuegeHinzu('/Applications/Pixelmator Pro.app');
    // Ein frischer Lauf: Die Einstellungen werden bedient, ehe das
    // Vollbild die Liste geladen hat.
    final zweite = neu();
    await zweite.schalte('gimp', false);
    final dritte = neu();
    await dritte.laden();
    expect(dritte.alle.where((x) => x.eigenes).map((x) => x.name), [
      'Pixelmator Pro',
    ]);
    expect(schalter(dritte)['gimp'], isFalse);
  });

  test('eine kaputte Einstellungsdatei kostet nur die Einstellung – und '
      'wird beiseitegelegt, nicht überschrieben', () async {
    datei
      ..createSync(recursive: true)
      ..writeAsStringSync('{kaputt');
    final programme = neu();
    await programme.laden();
    expect(programme.aktive.map((x) => x.name), ['darktable', 'GIMP']);
    await programme.schalte('gimp', false);
    expect(File('${datei.path}.kaputt').readAsStringSync(), '{kaputt');
    expect(jsonDecode(datei.readAsStringSync())['fassung'], 1);
  });

  test('Speichern geht nacheinander: viele Änderungen auf einmal, eine '
      'heile Datei mit allen', () async {
    final programme = neu();
    await programme.laden();
    await Future.wait([
      programme.schalte('gimp', false),
      programme.fuegeHinzu('/Applications/Pixelmator Pro.app'),
      programme.schalte('photoshop', true),
      programme.fuegeHinzu('/Applications/Krita.app'),
      programme.schalte('darktable', false),
    ]);
    final danach = neu();
    await danach.laden();
    expect(schalter(danach), {
      'darktable': false,
      'on1': false,
      'affinity': false,
      'photoshop': true,
      'gimp': false,
      'eigen:/Applications/Pixelmator Pro.app': true,
      'eigen:/Applications/Krita.app': true,
    });
    expect(File('${datei.path}.neu').existsSync(), isFalse);
  });

  test('Ordner aus der Datei werden geprüft: nichts ausserhalb, nichts '
      'Fremdes', () async {
    datei
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'fassung': 1,
          'eigene': [
            for (final (name, ordner) in [
              ('A', '../../Dokumente'),
              ('B', '/tmp/irgendwo'),
              ('C', 'PhotoVault-darktable'),
              ('D', 'PhotoVault-..'),
              ('E', 'PhotoVault-Gut'),
              ('F', 'photovault-gut'),
            ])
              {
                'name': name,
                'pfad': '/Applications/$name.app',
                'ordner': ordner,
              },
          ],
        }),
      );
    final programme = neu();
    await programme.laden();
    final eigene = [
      for (final x in programme.alle)
        if (x.eigenes) x.ordner,
    ];
    expect(eigene, [
      'PhotoVault-A',
      'PhotoVault-B',
      'PhotoVault-C',
      'PhotoVault-D',
      'PhotoVault-Gut',
      'PhotoVault-F',
    ]);
    for (final x in programme.alle) {
      expect(
        p.isWithin(programme.basis.path, programme.bruecke(x).ablage.path),
        isTrue,
        reason: x.ordner,
      );
    }
    // Die neuen Namen stehen gleich in der Datei, damit sie beim nächsten
    // Start dieselben sind.
    final gespeichert = jsonDecode(datei.readAsStringSync())['eigene'] as List;
    expect([for (final e in gespeichert) (e as Map)['ordner']], eigene);
  });

  test('ein eigenes Programm: Name aus dem Bündel, eigener Ordner, '
      'gespeichert', () async {
    final programme = neu();
    await programme.laden();
    final pixelmator = await programme.fuegeHinzu(
      '/Applications/Pixelmator Pro.app',
    );
    expect(pixelmator.name, 'Pixelmator Pro');
    expect(pixelmator.ordner, 'PhotoVault-Pixelmator Pro');
    expect(pixelmator.eigenes, isTrue);
    expect(pixelmator.aktiv, isTrue);
    // Ein zweites gleichen Namens und eines, das wie ein bekanntes heisst.
    final zweites = await programme.fuegeHinzu(
      '/Volumes/Alt/Pixelmator Pro.app',
    );
    final gimp = await programme.fuegeHinzu('/Volumes/Alt/GIMP.app');
    expect(zweites.ordner, 'PhotoVault-Pixelmator Pro 2');
    expect(gimp.ordner, 'PhotoVault-GIMP 2');

    final danach = neu();
    await danach.laden();
    expect(
      [
        for (final x in danach.alle)
          if (x.eigenes) x.ordner,
      ],
      [
        'PhotoVault-Pixelmator Pro',
        'PhotoVault-Pixelmator Pro 2',
        'PhotoVault-GIMP 2',
      ],
    );

    await danach.entferne(pixelmator.kennung);
    expect(
      [
        for (final x in danach.alle)
          if (x.eigenes) x.ordner,
      ],
      ['PhotoVault-Pixelmator Pro 2', 'PhotoVault-GIMP 2'],
      reason: 'der Ordner des zweiten bleibt, wo er war',
    );
  });

  test('ein freigewordener Ordner geht nicht an ein anderes Programm, aber '
      'zurück an dasselbe', () async {
    final programme = neu();
    await programme.laden();
    final erstes = await programme.fuegeHinzu('/Applications/Foto.app');
    expect(erstes.ordner, 'PhotoVault-Foto');
    await programme.entferne(erstes.kennung);
    final anderes = await programme.fuegeHinzu('/Volumes/Alt/Foto.app');
    expect(anderes.ordner, 'PhotoVault-Foto 2');
    final danach = neu();
    await danach.laden();
    final wieder = await danach.fuegeHinzu('/Applications/Foto.app');
    expect(
      wieder.ordner,
      'PhotoVault-Foto',
      reason: 'seine Kopien liegen dort',
    );
  });

  test('Gegenprobe: ein Ordner, den keine Einstellung kennt, ist auch '
      'vergeben', () async {
    Directory(
      p.join(wurzel.path, 'Bilder', 'PhotoVault-Foto', 'a1'),
    ).createSync(recursive: true);
    final programme = neu();
    await programme.laden();
    final x = await programme.fuegeHinzu('/Applications/Foto.app');
    expect(x.ordner, 'PhotoVault-Foto 2');
  });

  group('Aufräumen (#499)', () {
    late File original;
    setUp(() {
      original = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
    });

    test('ein Programm mit seinen Kopien entfernen: Kopien gehen, '
        'Arbeitsdateien bleiben', () async {
      final programme = neu();
      await programme.laden();
      final foto = await programme.fuegeHinzu('/Applications/Foto.app');
      final b = programme.bruecke(foto);
      expect(await programme.hatArbeitsordner(foto), isFalse);
      await b.oeffne(id: 'a1', name: 'a.jpg', original: original);
      await b.oeffne(id: 'a2', name: 'b.jpg', original: original);
      File(p.join(b.ordner('a2').path, 'b.psd')).writeAsStringSync('ebenen');
      expect(await programme.hatArbeitsordner(foto), isTrue);
      final geblieben = await programme.entferne(foto.kennung, kopienWeg: true);
      expect(geblieben.map((d) => d.path), [b.ordner('a2').path]);
      expect(b.ordner('a1').existsSync(), isFalse);
      expect(File(p.join(b.ordner('a2').path, 'b.jpg')).existsSync(), isFalse);
      expect(File(p.join(b.ordner('a2').path, 'b.psd')).existsSync(), isTrue);
    });

    test('Gegenprobe: ohne kopienWeg bleibt alles liegen', () async {
      final programme = neu();
      await programme.laden();
      final foto = await programme.fuegeHinzu('/Applications/Foto.app');
      final b = programme.bruecke(foto);
      await b.oeffne(id: 'a1', name: 'a.jpg', original: original);
      expect(await programme.entferne(foto.kennung), isEmpty);
      expect(File(p.join(b.ordner('a1').path, 'a.jpg')).existsSync(), isTrue);
    });

    test('beim Sperren: in allen Ordnern, auch entfernter Programme und '
        'unbekannter', () async {
      final programme = neu();
      await programme.laden();
      final gimp = programme.alle.singleWhere((x) => x.art == Bekannt.gimp);
      await programme
          .bruecke(gimp)
          .oeffne(id: 'a1', name: 'a.jpg', original: original);
      final foto = await programme.fuegeHinzu('/Applications/Foto.app');
      final fb = programme.bruecke(foto);
      await fb.oeffne(id: 'a1', name: 'a.jpg', original: original);
      File(p.join(fb.ordner('a1').path, 'a.psd')).writeAsStringSync('ebenen');
      await programme.entferne(foto.kennung);
      final unbekannt = Bearbeitungsbruecke(
        Directory(p.join(wurzel.path, 'Bilder', 'PhotoVault-Alt')),
        starte: (_) async => true,
      );
      await unbekannt.oeffne(id: 'a1', name: 'a.jpg', original: original);
      await unbekannt.oeffne(id: 'a9', name: 'z.jpg', original: original);
      final fremd = Directory(p.join(wurzel.path, 'Bilder', 'Urlaub', 'a1'))
        ..createSync(recursive: true);
      File(p.join(fremd.path, 'a.jpg')).writeAsStringSync('nicht unseres');
      // Heisst wie ein Arbeitsordner, ist aber eine Sicherung: ohne Marke
      // bleibt sie unberührt.
      final sicherung = Directory(
        p.join(wurzel.path, 'Bilder', 'PhotoVault-Backup', 'a1'),
      )..createSync(recursive: true);
      File(p.join(sicherung.path, 'a.jpg')).writeAsStringSync('gesichert');

      final geblieben = await programme.raeumeKlartextWeg(['a1']);
      expect(geblieben.map((d) => d.path), [fb.ordner('a1').path]);
      expect(programme.bruecke(gimp).ordner('a1').existsSync(), isFalse);
      expect(unbekannt.ordner('a1').existsSync(), isFalse);
      expect(unbekannt.ordner('a9').existsSync(), isTrue, reason: 'nur a1');
      expect(File(p.join(fremd.path, 'a.jpg')).existsSync(), isTrue);
      expect(sicherung.listSync().map((e) => p.basename(e.path)), ['a.jpg']);
    });
  });

  test('Gegenprobe: ein schon gefundenes Programm wird nicht doppelt '
      'aufgenommen, nur eingeschaltet', () async {
    final programme = neu();
    await programme.laden();
    await programme.schalte('gimp', false);
    final gimp = await programme.fuegeHinzu('/Applications/GIMP.app/');
    expect(gimp.art, Bekannt.gimp);
    expect(gimp.aktiv, isTrue);
    expect(programme.alle.where((x) => x.eigenes), isEmpty);
  });

  test('der Start nimmt den gefundenen Pfad, auch wenn die Brücke vor der '
      'Erkennung entstand', () async {
    final programme = neu();
    final vorher = programme.alle.singleWhere((x) => x.art == Bekannt.gimp);
    final bruecke = programme.bruecke(vorher);
    await programme.laden();
    final original = File(p.join(wurzel.path, 'a.jpg'))..writeAsStringSync('x');
    await bruecke.oeffne(id: 'a1', name: 'a.jpg', original: original);
    final kopie = p.join(
      wurzel.path,
      'Bilder',
      'PhotoVault-GIMP',
      'a1',
      'a.jpg',
    );
    expect(aufrufe, ['open | -a | /Applications/GIMP.app | $kopie']);
  });

  test('darktable findet seine Arbeitsordner am alten Ort', () async {
    final programme = neu();
    final alt = Directory(
      p.join(wurzel.path, 'Bilder', 'PhotoVault-darktable', 'a9'),
    )..createSync(recursive: true);
    final darktable = programme.alle.first;
    final bruecke = programme.bruecke(darktable);
    expect(bruecke, isA<DarktableBruecke>());
    expect(bruecke.ordner('a9').path, alt.path);
    expect(await bruecke.offen('a9'), isTrue);
  });

  test('programmnameAus', () {
    expect(
      programmnameAus('/Applications/Affinity Photo 2.app'),
      'Affinity Photo 2',
    );
    expect(programmnameAus(r'C:\Tools\Krita\bin\krita.exe'), 'krita');
    expect(programmnameAus('/opt/rawtherapee/rawtherapee'), 'rawtherapee');
  });
}

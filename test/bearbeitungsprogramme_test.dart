import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  test('eine kaputte Einstellungsdatei kostet nur die Einstellung', () async {
    datei
      ..createSync(recursive: true)
      ..writeAsStringSync('{kaputt');
    final programme = neu();
    await programme.laden();
    expect(programme.aktive.map((x) => x.name), ['darktable', 'GIMP']);
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
    expect(bruecke.offen('a9'), isTrue);
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

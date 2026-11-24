import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/platform/folder_access.dart';
import 'package:photo_vault/services/platform/speicherlaufwerk.dart';
import 'package:photo_vault/services/speicherinventar.dart';

class _Zugriff extends FolderAccess {
  @override
  bool get usesAccessToken => true;
  @override
  Future<PickedFolder?> pickFolder({String? message}) async => null;
  @override
  Future<String?> resolveRoot({String? path, String? token}) async =>
      token == 'gesperrt' ? null : path;
}

void main() {
  late Directory temp, privat, aktiv, archiv, ziel;
  late List<Bibliothekseintrag> bekannt;
  late Speicherinventar inventar;
  const id = '00000000-0000-4000-8000-000000000001';

  Directory bibliothek(String name, {bool marker = true}) {
    final d = Directory(p.join(temp.path, name))..createSync(recursive: true);
    final daten = Directory(p.join(d.path, 'library'))..createSync();
    final db = sql.sqlite3.open(p.join(d.path, 'library.sqlite'));
    try {
      db.execute('CREATE TABLE assets(id TEXT PRIMARY KEY)');
      db.execute('PRAGMA user_version=99');
    } finally {
      db.close();
    }
    File(p.join(daten.path, 'original.jpg')).writeAsBytesSync([1, 2, 3, 4]);
    if (marker) {
      File(p.join(daten.path, '.standortkennung')).writeAsStringSync(id);
    }
    return d;
  }

  Map<String, String> fingerabdruck(Directory d) => {
    for (final f
        in d.listSync(recursive: true, followLinks: false).whereType<File>())
      p.relative(f.path, from: d.path): sha256
          .convert(f.readAsBytesSync())
          .toString(),
  };

  Future<void> nachweis({bool gut = true, String token = ''}) async {
    final f = File(p.join(privat.path, 'speicherkarte', '$id.json'));
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode({
        'fassung': 1,
        'nachweise': [
          {
            'id': 'ziel',
            'ziel': ziel.path,
            'token': token,
            'am': '2026-01-02T03:04:05Z',
            'vollstaendig': true,
            'befunde': {
              if (gut) 'a' * 64: 'bestaetigt' else 'ungueltig': 'bestaetigt',
            },
          },
        ],
      }),
    );
  }

  setUp(() {
    temp = Directory(
      Directory.systemTemp
          .createTempSync('pv_inventar_')
          .resolveSymbolicLinksSync(),
    );
    privat = Directory(p.join(temp.path, 'privat'))..createSync();
    aktiv = bibliothek('aktiv', marker: false);
    archiv = bibliothek('Archiv');
    ziel = Directory(p.join(temp.path, 'Sicherung'))..createSync();
    bekannt = [Bibliothekseintrag(path: archiv.path, name: 'Archiv')];
    inventar = Speicherinventar(
      aktiveWurzel: aktiv,
      privat: privat,
      zugriff: _Zugriff(),
      bekannte: () async => [
        for (final b in bekannt)
          BibliothekMitZustand(
            eintrag: b,
            erreichbar: Directory(b.path).existsSync(),
            istAktiv: true,
            istStandard: false,
            aufgeloesterPfad: Directory(b.path).existsSync() ? b.path : null,
          ),
      ],
      laufwerk: (pfad) async => Speicherlaufwerk(
        pfad.startsWith(archiv.path)
            ? 'archiv-disk'
            : pfad.startsWith(ziel.path)
            ? 'sicherungs-disk'
            : 'lokal',
        pfad.startsWith(archiv.path)
            ? 'Archivplatte'
            : pfad.startsWith(ziel.path)
            ? 'Sicherungsplatte'
            : 'Lokal',
        temp.path,
      ),
    );
  });

  tearDown(() {
    LibraryLocation.zuruecksetzenFuerTests();
    temp.deleteSync(recursive: true);
  });

  test(
    'auch inaktive und nicht erreichbare Bibliotheken stehen in der Übersicht',
    () async {
      final weg = p.join(temp.path, 'Abgezogen', 'Bibliothek');
      bekannt.add(Bibliothekseintrag(path: weg, name: 'Unterwegs'));
      final unbekannt = bibliothek('NichtRegistriert');
      final s = await inventar.laden();
      expect(
        s.orte.where((e) => e.art == Speicherortart.bibliothek),
        hasLength(3),
      );
      expect(s.orte.where((e) => e.aktiv).single.pfad, aktiv.path);
      expect(
        s.orte.singleWhere((e) => e.pfad == archiv.path).erreichbar,
        isTrue,
      );
      expect(s.orte.singleWhere((e) => e.pfad == weg).erreichbar, isFalse);
      expect(s.orte.any((e) => e.pfad == unbekannt.path), isFalse);
    },
  );

  test(
    'älterer Katalog, Fotos, WAL und fehlende Kennung bleiben unverändert',
    () async {
      final alt = bibliothek('OhneKennung', marker: false);
      File(p.join(alt.path, 'library.sqlite-wal')).writeAsBytesSync([1, 2, 3]);
      File(p.join(alt.path, 'library.sqlite-shm')).writeAsBytesSync([4, 5, 6]);
      bekannt.add(Bibliothekseintrag(path: alt.path, name: 'Alt'));
      final vorher = fingerabdruck(alt);
      await inventar.laden();
      expect(fingerabdruck(alt), vorher);
      expect(
        ByteData.sublistView(
          File(p.join(alt.path, 'library.sqlite')).readAsBytesSync(),
        ).getUint32(60, Endian.big),
        99,
      );
      expect(
        File(p.join(alt.path, 'library', '.standortkennung')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'Sicherungsziele anderer Bibliotheken erscheinen mit Datum und damaligem Umfang',
    () async {
      await nachweis();
      final vorher = fingerabdruck(archiv);
      final s = await inventar.laden();
      final n = s.orte.singleWhere((e) => e.art == Speicherortart.sicherung);
      expect(n.name, 'Archiv');
      expect(n.pfad, ziel.path);
      expect(n.erreichbar, isTrue);
      expect(n.pruefung!.am, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(n.pruefung!.bestaetigt, 1);
      expect(fingerabdruck(archiv), vorher);
    },
  );

  test(
    'abgezogene Bibliothek und Sicherungsziel behalten ihre letzte Zuordnung',
    () async {
      await nachweis();
      await inventar.laden();
      await archiv.rename('${archiv.path}-weg');
      await ziel.rename('${ziel.path}-weg');
      final s = await inventar.laden();
      final a = s.orte.singleWhere((e) => e.pfad == archiv.path);
      final b = s.orte.singleWhere((e) => e.pfad == ziel.path);
      expect(a.erreichbar, isFalse);
      expect(a.laufwerk!.name, 'Archivplatte');
      expect(a.laufwerkHistorisch, isTrue);
      expect(b.erreichbar, isFalse);
      expect(b.laufwerk!.name, 'Sicherungsplatte');
      expect(b.pruefung!.bestaetigt, 1);
      expect(b.laufwerkHistorisch, isTrue);
    },
  );

  test(
    'eine neue Bibliothek am früheren Pfad erbt keine alten Sicherungsnachweise',
    () async {
      await nachweis();
      await inventar.laden();
      await archiv.rename('${archiv.path}-alt');
      bibliothek('Archiv', marker: false);
      final s = await inventar.laden();
      expect(s.orte.where((e) => e.art == Speicherortart.sicherung), isEmpty);
    },
  );

  test('ungültiger Nachweis lässt den Bibliothekspfad sichtbar', () async {
    await nachweis(gut: false);
    final s = await inventar.laden();
    expect(
      s.orte.singleWhere((e) => e.pfad == archiv.path).nachweiseUnlesbar,
      isTrue,
    );
    expect(s.orte.where((e) => e.art == Speicherortart.sicherung), isEmpty);
  });

  test(
    'ein nicht freigegebenes Lesezeichen wird nicht über den bloßen Pfad umgangen',
    () async {
      await nachweis(token: 'gesperrt');
      final s = await inventar.laden();
      expect(
        s.orte.singleWhere((e) => e.pfad == ziel.path).erreichbar,
        isFalse,
      );
    },
  );

  test('umbenannte Ordner zeigen gespeicherten und aufgelösten Pfad', () async {
    final alt = p.join(temp.path, 'frueher');
    final dienst = Speicherinventar(
      aktiveWurzel: aktiv,
      privat: privat,
      bekannte: () async => [
        BibliothekMitZustand(
          eintrag: Bibliothekseintrag(path: alt, name: 'Archiv'),
          erreichbar: true,
          istAktiv: false,
          istStandard: false,
          aufgeloesterPfad: archiv.path,
        ),
      ],
      laufwerk: (_) async => null,
    );
    final s = await dienst.laden();
    final e = s.orte.singleWhere((e) => e.name == 'Archiv');
    expect(e.pfad, alt);
    expect(e.aufgeloesterPfad, archiv.path);
  });

  test('Aliase zählen nicht als zusätzliche Bibliotheken', () async {
    final alias = Link(p.join(temp.path, 'Alias'))..createSync(archiv.path);
    bekannt.add(Bibliothekseintrag(path: alias.path, name: 'Verknuepfung'));
    final s = await inventar.laden();
    expect(
      s.orte.where((e) => e.art == Speicherortart.bibliothek),
      hasLength(2),
    );
    expect(s.orte.singleWhere((e) => e.pfad == archiv.path).weiterePfade, [
      alias.path,
    ]);
  }, skip: Platform.isWindows ? 'Symlinks erfordern eigene Rechte' : false);

  test(
    'defekte Ortsliste fällt sichtbar auf die tatsächlich geöffnete Bibliothek zurück',
    () async {
      LibraryLocation.nutzeFuerTests(anker: privat, zugriff: _Zugriff());
      await File(p.join(privat.path, 'location.json')).writeAsString('{kaputt');
      final dienst = Speicherinventar(
        aktiveWurzel: aktiv,
        privat: privat,
        laufwerk: (_) async => null,
      );
      final s = await dienst.laden();
      expect(s.listeUnlesbar, isTrue);
      expect(s.orte.single.pfad, aktiv.path);
      expect(
        await File(p.join(privat.path, 'location.json')).readAsString(),
        '{kaputt',
      );
    },
  );

  test(
    'Abbruch legt keine Merkliste oder Kennung in einer Bibliothek an',
    () async {
      await expectLater(
        inventar.laden(abgebrochen: () => true),
        throwsStateError,
      );
      expect(
        File(p.join(privat.path, 'speicherinventar.json')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'vorhandene Bibliothek wird erkannt, der Originalordner allein nicht',
    () async {
      final vorher = fingerabdruck(archiv);
      expect(await Speicherinventar.istBibliotheksordner(archiv), isTrue);
      expect(
        await Speicherinventar.istBibliotheksordner(
          Directory(p.join(archiv.path, 'library')),
        ),
        isFalse,
      );
      expect(fingerabdruck(archiv), vorher);
      final leer = Directory(p.join(temp.path, 'leer'))..createSync();
      expect(await Speicherinventar.istBibliotheksordner(leer), isFalse);
    },
  );

  test(
    'Linux-Einhängepfade mit Leerzeichen, Bind-Mounts und Präfixgrenzen',
    () {
      const mount = r'''
1 0 8:1 / / rw - ext4 /dev/root rw
2 1 8:2 / /media/test/Foto\040Archiv rw - ext4 /dev/data rw
3 1 8:2 /unterordner /mnt/bind rw - ext4 /dev/data rw
''';
      final a = Laufwerksauskunft.ausLinuxMountinfo(
        '/media/test/Foto Archiv/Bibliothek',
        mount,
      )!;
      final b = Laufwerksauskunft.ausLinuxMountinfo(
        '/mnt/bind/Bibliothek',
        mount,
      )!;
      expect(a.name, 'Foto Archiv');
      expect(a.id, b.id);
      expect(a.pfad, '/media/test/Foto Archiv');
      expect(
        Laufwerksauskunft.ausLinuxMountinfo(
          '/media/test/Foto Archiv2/Bibliothek',
          mount,
        )!.pfad,
        '/',
      );
      expect(Laufwerksauskunft.ausLinuxMountinfo('relativ', mount), isNull);
    },
  );
  test(
    'ausgelagerte Originale zeigen ihren tatsächlichen Datenträger',
    () async {
      final originalpfad = p.join(archiv.path, 'library', 'originals');
      Link(originalpfad).createSync(ziel.path);
      final vorher = fingerabdruck(archiv);
      final stand = await inventar.laden();
      final ort = stand.orte.singleWhere(
        (o) => o.art == Speicherortart.dateien,
      );
      expect(ort.pfad, originalpfad);
      expect(ort.aufgeloesterPfad, ziel.path);
      expect(ort.laufwerk!.name, 'Sicherungsplatte');
      expect(ort.erreichbar, isTrue);
      expect(ort.pruefung, isNull);
      expect(fingerabdruck(archiv), vorher);
      ziel.deleteSync(recursive: true);
      final weg = (await inventar.laden()).orte.singleWhere(
        (o) => o.art == Speicherortart.dateien,
      );
      expect(weg.erreichbar, isFalse);
      expect(weg.pfad, originalpfad);
    },
    skip: Platform.isWindows ? 'Symlinks erfordern eigene Rechte' : false,
  );

  test(
    'defekter lokaler Zwischenspeicher erfindet keine Offline-Zuordnung',
    () async {
      File(
        p.join(privat.path, 'speicherinventar.json'),
      ).writeAsStringSync('{kaputt');
      archiv.renameSync('${archiv.path}-weg');
      final stand = await inventar.laden();
      final ort = stand.orte.singleWhere((o) => o.pfad == archiv.path);
      expect(stand.listeUnlesbar, isTrue);
      expect(ort.laufwerk, isNull);
      expect(ort.pruefung, isNull);
      expect(stand.orte.any((o) => o.aktiv), isTrue);
    },
  );

  test(
    'Hinzufügen merkt den Ordner ohne Wechsel oder Katalogzugriff',
    () async {
      LibraryLocation.nutzeFuerTests(anker: privat, zugriff: _Zugriff());
      final vorher = fingerabdruck(archiv);
      final aktiverPfad = (await LibraryLocation.currentRoot()).path;
      expect(await Speicherinventar.istBibliotheksordner(archiv), isTrue);
      await LibraryLocation.fuegeHinzu(
        PickedFolder(archiv.path, ''),
        fehlerMelden: true,
      );
      expect((await LibraryLocation.currentRoot()).path, aktiverPfad);
      expect(
        (await LibraryLocation.bekannte()).any(
          (b) => b.eintrag.path == archiv.path,
        ),
        isTrue,
      );
      expect(fingerabdruck(archiv), vorher);
    },
  );

  test('widersprüchliche Linux-Mounts ergeben keine erfundene Zuordnung', () {
    const mount =
        '1 0 8:1 / / rw - ext4 /dev/root rw\n'
        '2 1 8:2 / /media/fotos rw - ext4 /dev/data rw\n'
        '3 1 8:3 / /media/fotos rw - ext4 /dev/other rw\n';
    expect(
      Laufwerksauskunft.ausLinuxMountinfo('/media/fotos/Archiv', mount),
      isNull,
    );
    expect(
      Laufwerksauskunft.ausLinuxMountinfo('/anderer-ordner', mount)!.pfad,
      '/',
    );
  });
  test('Hinzufügen überschreibt eine defekte Bibliotheksliste nicht', () async {
    LibraryLocation.nutzeFuerTests(anker: privat, zugriff: _Zugriff());
    final datei = File(p.join(privat.path, 'location.json'))
      ..writeAsStringSync('{kaputt');
    await expectLater(
      LibraryLocation.fuegeHinzu(
        PickedFolder(archiv.path, ''),
        fehlerMelden: true,
      ),
      throwsFormatException,
    );
    expect(datei.readAsStringSync(), '{kaputt');
  });

  test('der Standardordner bleibt als solcher erkennbar (#489)', () async {
    // Sein Name ist das feste „Standard“; übersetzen kann ihn nur die
    // Oberfläche, und dafür muss sie wissen, welcher Eintrag er ist.
    Speicherinventar mit(List<BibliothekMitZustand> liste) => Speicherinventar(
      aktiveWurzel: aktiv,
      privat: privat,
      zugriff: _Zugriff(),
      bekannte: () async => liste,
      laufwerk: (_) async => null,
    );
    BibliothekMitZustand eintrag(
      Directory d,
      String name, {
      required bool istAktiv,
      required bool istStandard,
    }) => BibliothekMitZustand(
      eintrag: Bibliothekseintrag(path: d.path, name: name),
      erreichbar: true,
      istAktiv: istAktiv,
      istStandard: istStandard,
      aufgeloesterPfad: d.path,
    );

    // Geöffnet ist der Standardordner.
    var s = await mit([
      eintrag(aktiv, 'Standard', istAktiv: true, istStandard: true),
      eintrag(archiv, 'Archiv', istAktiv: false, istStandard: false),
    ]).laden();
    var orte = s.orte.where((e) => e.art == Speicherortart.bibliothek);
    expect(orte.singleWhere((e) => e.aktiv).standard, isTrue);
    expect(orte.singleWhere((e) => e.pfad == archiv.path).standard, isFalse);
    expect(orte.singleWhere((e) => e.aktiv).anzeigename('Default'), 'Default');

    // Geöffnet ist eine andere; der Standardordner samt Sicherungsziel
    // steht daneben.
    await nachweis();
    s = await mit([
      eintrag(aktiv, 'Aktiv', istAktiv: true, istStandard: false),
      eintrag(archiv, 'Standard', istAktiv: false, istStandard: true),
    ]).laden();
    orte = s.orte.where((e) => e.art == Speicherortart.bibliothek);
    expect(orte.singleWhere((e) => e.aktiv).standard, isFalse);
    expect(orte.singleWhere((e) => e.aktiv).anzeigename('Default'), 'Aktiv');
    expect(orte.singleWhere((e) => e.pfad == archiv.path).standard, isTrue);
    expect(
      s.orte.singleWhere((e) => e.art == Speicherortart.sicherung).standard,
      isTrue,
    );
  });
}

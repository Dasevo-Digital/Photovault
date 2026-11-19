import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/umzugsquelle.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('pv_umzugsabbruch_'),
  );
  tearDown(() => root.delete(recursive: true));

  test('Datei- und Ordnergrenzen greifen während der Aufzählung', () async {
    for (var i = 0; i < 12; i++) {
      File(p.join(root.path, '$i.jpg')).writeAsBytesSync([1]);
      Directory(p.join(root.path, 'ordner$i')).createSync();
    }
    await expectLater(
      Umzugsquelle.ordner(root.path, hoechstensDateien: 10),
      throwsFormatException,
    );
    await expectLater(
      Umzugsquelle.ordner(root.path, hoechstensOrdner: 10),
      throwsFormatException,
    );
    final q = await Umzugsquelle.ordner(
      root.path,
      hoechstensDateien: 12,
      hoechstensOrdner: 13,
    );
    expect(q.dateien.length, 12);
    await q.schliesse();
  });

  test(
    'Abbruch beendet laufenden Worker und lässt die Quelle unverändert',
    () async {
      for (var i = 0; i < 1200; i++) {
        File(p.join(root.path, '$i.jpg')).writeAsBytesSync([1]);
      }
      final abbruch = Umzugsabbruch();
      var meldungen = 0;
      await expectLater(
        Umzugsquelle.ordner(
          root.path,
          abbruch: abbruch,
          fortschritt: (_) {
            meldungen++;
            abbruch.abbrechen();
          },
        ),
        throwsA(isA<UmzugAbgebrochen>()),
      );
      expect(meldungen, 1);
      expect(root.listSync().length, 1200);
      final q = await Umzugsquelle.ordner(root.path);
      expect(q.dateien.length, 1200);
      await q.schliesse();
    },
  );

  test('Abbruch vor dem Start öffnet keine Quelle', () async {
    final abbruch = Umzugsabbruch()..abbrechen();
    await expectLater(
      Umzugsquelle.ordner(p.join(root.path, 'fehlt'), abbruch: abbruch),
      throwsA(isA<UmzugAbgebrochen>()),
    );
  });

  test(
    'Archivabbruch wartet auf den Worker und entfernt dessen Tempordner',
    () async {
      final archiv = Archive();
      for (var i = 0; i < 110; i++) {
        archiv.addFile(ArchiveFile('$i.jpg', 3, [1, 2, 3]));
      }
      final zip = File(p.join(root.path, 'quelle.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(archiv));
      final abbruch = Umzugsabbruch();
      await expectLater(
        IOOverrides.runZoned(
          () => Umzugsquelle.archive(
            [zip.path],
            abbruch: abbruch,
            fortschritt: (_) => abbruch.abbrechen(),
          ),
          getSystemTempDirectory: () => root,
        ),
        throwsA(isA<UmzugAbgebrochen>()),
      );
      expect(root.listSync().map((f) => p.basename(f.path)), ['quelle.zip']);
      final q = await Umzugsquelle.archive([zip.path]);
      expect(q.dateien.length, 110);
      await q.schliesse();
    },
  );
}

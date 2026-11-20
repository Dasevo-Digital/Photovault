import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/referenz_katalog.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/speicherlaufwerk.dart';
import 'package:photo_vault/services/referenz_abgleich.dart';

void main() {
  late Directory temp, quelle;
  late AppDatabase db;
  late StoragePaths paths;
  late OriginalReferenzen refs;
  late ImportService import;
  late ReferenzAbgleich dienst;
  late String ordner;
  var jetzt = DateTime.utc(2026, 1, 1);
  var extern = true;
  Future<File> foto(String name, {int rot = 42}) async {
    final f = File(p.join(quelle.path, name));
    await f.parent.create(recursive: true);
    return f.writeAsBytes(
      img.encodeJpg(
        img.Image(width: 12, height: 10)..clear(img.ColorRgb8(rot, 20, 30)),
      ),
    );
  }

  ReferenzAbgleich neuerDienst() => ReferenzAbgleich(
    db,
    paths,
    import,
    uhr: () => jetzt,
    laufwerk: (_) async =>
        Speicherlaufwerk(extern ? 'extern' : 'intern', 'Test', '/'),
  );
  Future<void> seed() async {
    await for (final _ in ReferenzKatalog(db, paths, import).scanne(quelle)) {}
  }

  Future<Map<String, String>> originals() async => {
    for (final f in quelle.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: quelle.path): sha256
          .convert(f.readAsBytesSync())
          .toString(),
  };
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_referenz_abgleich_');
    quelle = await Directory(p.join(temp.path, 'quelle')).create();
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    refs = OriginalReferenzen(File(p.join(temp.path, 'privat', 'orte.json')));
    paths.referenzen = refs;
    db = AppDatabase(NativeDatabase.memory());
    import = ImportService(db, paths);
    ordner = await refs.ordnerHinzufuegen(quelle);
    jetzt = DateTime.utc(2026, 1, 1);
    extern = true;
    dienst = neuerDienst();
  });
  tearDown(() async {
    dienst.beende();
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'Vorschau unterscheidet neu, verändert und fehlend ohne Originale oder Katalog zu ändern',
    () async {
      final a = await foto('a.jpg');
      final b = await foto('b.jpg', rot: 80);
      await seed();
      final vorher = (await db.select(db.assets).get())
          .map((a) => a.toJson())
          .toList();
      await foto('a.jpg', rot: 90);
      await b.delete();
      await foto('c.jpg', rot: 120);
      final dateien = await originals();
      final plan = await dienst.pruefe(ordner);
      expect(plan.erreichbar, isTrue);
      expect(plan.vollstaendig, isTrue);
      expect(
        {for (final e in plan.eintraege) e.relativ: e.art},
        {
          'a.jpg': ReferenzAenderung.geaendert,
          'b.jpg': ReferenzAenderung.fehlt,
          'c.jpg': ReferenzAenderung.neu,
        },
      );
      expect(
        (await db.select(db.assets).get()).map((a) => a.toJson()).toList(),
        vorher,
      );
      expect(await originals(), dateien);
      expect(await dienst.uebernehmeNeue(plan), 1);
      final nachher = await db.select(db.assets).get();
      expect(nachher, hasLength(3));
      for (final alt in vorher) {
        expect(nachher.singleWhere((a) => a.id == alt['id']).toJson(), alt);
      }
      expect(await originals(), dateien);
      expect(await a.exists(), isTrue);
    },
  );

  test(
    'Zeitplan und Ausschlüsse überstehen einen Neustart und importieren nicht automatisch',
    () async {
      await dienst.plane(ordner, 24, ausschliessen: ['**/aus/**']);
      await dienst.pruefeFaellige();
      await foto('neu.jpg');
      await foto('aus/privat.jpg', rot: 55);
      jetzt = jetzt.add(const Duration(hours: 23));
      dienst = neuerDienst();
      await dienst.pruefeFaellige();
      expect(dienst.plaene[ordner]!.eintraege, isEmpty);
      jetzt = jetzt.add(const Duration(hours: 1));
      await dienst.pruefeFaellige();
      expect(dienst.intervalle[ordner], 24);
      expect(dienst.plaene[ordner]!.eintraege.map((e) => e.relativ), [
        'neu.jpg',
      ]);
      expect(await db.select(db.assets).get(), isEmpty);
    },
  );

  test(
    'Leerer Einhängeordner auf anderem Dateisystem gilt als unerreichbar',
    () async {
      await foto('alt.jpg');
      await seed();
      await dienst.pruefe(ordner);
      final vorher = (await db.select(db.assets).get())
          .map((a) => a.toJson())
          .toList();
      await quelle.rename('${quelle.path}-abgezogen');
      await quelle.create();
      extern = false;
      dienst = neuerDienst();
      final plan = await dienst.pruefe(ordner);
      expect(plan.erreichbar, isFalse);
      expect(plan.vollstaendig, isFalse);
      expect(plan.eintraege, isEmpty);
      expect(
        (await db.select(db.assets).get()).map((a) => a.toJson()).toList(),
        vorher,
      );
    },
  );

  test(
    'Geänderte Datei nach der Vorschau stoppt vor dem ersten Import',
    () async {
      await foto('eins.jpg');
      await foto('zwei.jpg', rot: 55);
      final plan = await dienst.pruefe(ordner);
      await foto('zwei.jpg', rot: 77);
      await expectLater(dienst.uebernehmeNeue(plan), throwsFormatException);
      expect(await db.select(db.assets).get(), isEmpty);
    },
  );

  test('Abbruch speichert keine scheinbar vollständige Vorschau', () async {
    for (var i = 0; i < 10; i++) {
      await foto('$i.jpg', rot: i);
    }
    var kontrollen = 0;
    await expectLater(
      dienst.pruefe(ordner, abgebrochen: () => ++kontrollen > 4),
      throwsA(isA<ReferenzAbbruch>()),
    );
    expect(dienst.plaene, isEmpty);
    expect(await dienst.datei.exists(), isFalse);
    expect(await db.select(db.assets).get(), isEmpty);
  });

  test(
    'Beschädigter Zeitplan wird nicht durch eine neue Einstellung überschrieben',
    () async {
      await dienst.datei.parent.create(recursive: true);
      await dienst.datei.writeAsString('{kaputt');
      await expectLater(dienst.plane(ordner, 24), throwsFormatException);
      expect(await dienst.datei.readAsString(), '{kaputt');
    },
  );

  test('Ausgeschlossene Dateien gelten nicht als gelöscht', () async {
    await foto('aus/alt.jpg');
    await seed();
    final plan = await dienst.pruefe(ordner, ausschliessen: ['**/aus/**']);
    expect(plan.eintraege, isEmpty);
    expect(await db.select(db.assets).get(), hasLength(1));
  });
}

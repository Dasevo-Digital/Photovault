import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_restore.dart';
import 'package:kern/services/beschriftungsvorschlaege.dart';
import 'package:kern/services/erinnerungsfilter.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';

void main() {
  test(
    'Schnappschuss erhält Vorschlagshistorie und Ausschlüsse bei neuen Aufnahme- und Albumkennungen',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'pv_beschriftung_restore_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final quelle = AppDatabase(NativeDatabase.memory());
      final ziel = AppDatabase(NativeDatabase.memory());
      addTearDown(quelle.close);
      addTearDown(ziel.close);
      final quellPfade = await StoragePaths.forTesting(
        Directory('${temp.path}/quelle'),
      );
      final zielPfade = await StoragePaths.forTesting(
        Directory('${temp.path}/ziel'),
      );
      final original = File('${temp.path}/foto.jpg');
      await original.writeAsBytes([1, 2, 3]);
      await ImportService(quelle, quellPfade).importFile(original.path);
      final alt = (await quelle.select(quelle.assets).get()).single;
      await quelle.fuehreAus(
        AlbumAnlegen('album', 'Familienalbum', DateTime(2026)),
      );
      await quelle.fuehreAus(AlbumFuellen('album', [alt.id]));
      final dienst = Beschriftungsdienst(quelle);
      final id = await dienst.vorschlagen(
        id: alt.id,
        album: 'album',
        von: 'gast',
        name: 'Testgast',
        art: 'jahr',
        wert: '1985',
      );
      await dienst.entscheiden(
        id,
        annehmen: false,
        erwartet: await dienst.stand(alt.id),
      );
      final vorher =
          (await quelle.select(quelle.beschriftungsvorschlaege).get()).single;
      await quelle.fuehreAus(
        ErinnerungsfilterSetzen(
          Erinnerungsfilter(
            alben: ['album'],
            zeitraeume: [(von: '1980-01-01', bis: '1980-12-31')],
          ),
        ),
      );
      final snapshot = File('${temp.path}/snapshot.sqlite');
      await quelle.customStatement('VACUUM INTO ?', [snapshot.path]);
      await ImportService(ziel, zielPfade).importFile(original.path);
      final neu = (await ziel.select(ziel.assets).get()).single;
      expect(neu.id, isNot(alt.id));
      final wiederhersteller = BackupWiederhersteller(ziel, zielPfade);
      await wiederhersteller.uebernimmAusSchnappschuss(
        snapshot,
        streng: true,
        nurPruefsummen: {},
      );
      expect((await ziel.erinnerungsfilter()).leer, isTrue);
      expect(await ziel.select(ziel.beschriftungsvorschlaege).get(), isEmpty);
      expect(await ziel.select(ziel.albums).get(), isEmpty);
      await wiederhersteller.uebernimmAusSchnappschuss(snapshot, streng: true);
      final nachher =
          (await ziel.select(ziel.beschriftungsvorschlaege).get()).single;
      expect(
        (
          nachher.id,
          nachher.assetId,
          nachher.von,
          nachher.vonName,
          nachher.angelegt,
          nachher.entschieden,
          nachher.zustand,
        ),
        (
          vorher.id,
          neu.id,
          vorher.von,
          vorher.vonName,
          vorher.angelegt,
          vorher.entschieden,
          'abgelehnt',
        ),
      );
      final album = (await ziel.select(ziel.albums).get()).single;
      expect(nachher.albumId, album.id);
      expect(album.name, 'Familienalbum');
      expect((await ziel.erinnerungsfilter()).alben, [album.id]);
      expect((await ziel.erinnerungsfilter()).zeitraeume, [
        (von: '1980-01-01', bis: '1980-12-31'),
      ]);
      expect((await ziel.albumAufnahmen(album.id)).single.id, neu.id);
    },
  );
}

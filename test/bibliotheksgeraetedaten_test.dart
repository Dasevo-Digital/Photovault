import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/services/bibliotheksgeraetedaten.dart';
import 'package:photo_vault/services/farbverwaltung.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/speicherkarte.dart';

void main() {
  test(
    'Bibliotheksumzug erhält gerätebezogene Profile und Nachweiszuordnung',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_geraetebindung_');
      addTearDown(() => temp.delete(recursive: true));
      LibraryLocation.nutzeFuerTests(anker: Directory('${temp.path}/privat'));
      addTearDown(LibraryLocation.zuruecksetzenFuerTests);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final alt = await StoragePaths.forTesting(Directory('${temp.path}/alt'));
      final id = await Bibliotheksgeraetedaten.kennung(alt);
      final farbe = await Farbverwaltung.fuer(alt);
      await farbe.speichern(const Farbeinstellungen(ausgabe: 'p3'));
      final karte = await SpeicherkarteDienst.fuer(db, alt);
      await alt.root.rename('${temp.path}/verschoben');
      final neu = await StoragePaths.forTesting(
        Directory('${temp.path}/verschoben'),
      );
      expect(await Bibliotheksgeraetedaten.kennung(neu), id);
      expect((await (await Farbverwaltung.fuer(neu)).laden()).ausgabe, 'p3');
      expect(
        (await SpeicherkarteDienst.fuer(db, neu)).nachweisdatei.path,
        karte.nachweisdatei.path,
      );
      final leer = await StoragePaths.forTesting(
        Directory('${temp.path}/andere'),
      );
      expect(await Bibliotheksgeraetedaten.kennung(leer), isNot(id));
    },
  );
}

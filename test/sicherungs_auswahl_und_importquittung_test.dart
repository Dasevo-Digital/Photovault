import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/auswertung/fortschritt.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/backup_auswahl_screen.dart';
import 'package:photo_vault/services/importquittungen.dart';

void main() {
  late Directory temp;
  late Directory backup;
  late Directory ziel;
  late Directory bibliothek;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_auswahl_probe_');
    backup = await Directory(p.join(temp.path, 'backup')).create();
    ziel = await Directory(p.join(temp.path, 'export')).create();
    bibliothek = await Directory(p.join(temp.path, 'bibliothek')).create();
  });
  tearDown(() => temp.delete(recursive: true));

  String hash(List<int> bytes) => sha256.convert(bytes).toString();

  Map<String, Object> aufnahme(
    String name,
    String pfad,
    List<int> bytes, {
    String datum = '1993-07-12T10:00:00',
    bool anlegen = true,
  }) {
    if (anlegen) {
      File(p.join(backup.path, pfad))
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
    return {
      'checksum': hash(bytes),
      'backupRelativePath': pfad,
      'originalFileName': name,
      'fileCreatedAt': datum,
    };
  }

  void manifest(
    List<Map<String, Object>> dateien, {
    List<Map<String, Object>> alben = const [],
  }) {
    File(p.join(backup.path, 'metadata.json')).writeAsStringSync(
      jsonEncode({'format': 1, 'assets': dateien, 'albums': alben}),
    );
  }

  Future<BackupAuswahl> oeffne() =>
      BackupAuswahl.oeffne(backup.path, schemaVersion: 999);

  test(
    'Katalog sucht Name, Datum und Album und exportiert nur die Auswahl',
    () async {
      final a = aufnahme('wald.jpg', 'originals/a.jpg', [1, 2, 3]);
      final b = aufnahme('meer.jpg', 'originals/b.jpg', [
        4,
        5,
      ], datum: '1994-08-01T12:00:00');
      manifest(
        [a, b],
        alben: [
          {
            'name': 'Ferien',
            'assetChecksums': [a['checksum']!],
          },
        ],
      );
      final katalog = await oeffne();
      final wald = katalog.aufnahmen.singleWhere(
        (e) => e.passtZu('Ferien 1993-07 Wald'),
      );
      expect(wald.liegtVor, isTrue);
      expect(
        katalog.aufnahmen.where((e) => e.passtZu('1994')).single.name,
        'meer.jpg',
      );
      final vorher = File(p.join(ziel.path, 'wald.jpg'))
        ..writeAsStringSync('bleibt');
      final stand = await katalog.exportiere({wald.pruefsumme}, ziel).last;
      expect(stand.fehler, isEmpty);
      final geschrieben = stand.ordner.listSync().whereType<File>().single;
      expect(p.basename(geschrieben.path), '0001_wald.jpg');
      expect(geschrieben.readAsBytesSync(), [1, 2, 3]);
      expect(vorher.readAsStringSync(), 'bleibt');
      expect(backup.listSync().length, 2);
    },
  );

  test('Katalog löst plattformübergreifend Windows-Ablagepfade auf', () async {
    final a = aufnahme('a.jpg', 'originals/a.jpg', [1]);
    a['backupRelativePath'] = r'originals\a.jpg';
    manifest([a]);
    final katalog = await oeffne();
    expect(await katalog.pruefeOriginal(hash([1])), isTrue);
  });

  test('Fehlschlag lässt nur vollständig geprüfte Exporte stehen', () async {
    final a = aufnahme('a.jpg', 'originals/a.jpg', [2, 3]);
    final kaputt = aufnahme('kaputt.jpg', 'originals/b.jpg', [4, 5]);
    final fehlt = aufnahme('fehlt.jpg', 'originals/c.jpg', [
      6,
      7,
    ], anlegen: false);
    manifest([a, kaputt, fehlt]);
    final katalog = await oeffne();
    expect(katalog.aufnahmen.last.liegtVor, isFalse);
    File(p.join(backup.path, 'originals/b.jpg')).writeAsBytesSync([4, 0]);
    final stand = await katalog
        .exportiere(katalog.aufnahmen.map((e) => e.pruefsumme).toSet(), ziel)
        .last;
    expect(stand.fehler, ['kaputt.jpg', 'fehlt.jpg']);
    expect(stand.ordner.listSync().whereType<File>().single.readAsBytesSync(), [
      2,
      3,
    ]);
    final allesFehlte = await katalog.exportiere({
      hash([4, 5]),
    }, ziel).last;
    expect(allesFehlte.ordner.existsSync(), isFalse);
  });

  test(
    'gleichen und unsicheren Dateinamen bleiben getrennte Ausgabedateien',
    () async {
      manifest([
        aufnahme(r'../../CON.jpg', 'originals/a.jpg', [1]),
        aufnahme(r'x\\CON.jpg', 'originals/b.jpg', [2]),
      ]);
      final katalog = await oeffne();
      final auswahl = katalog.aufnahmen.map((e) => e.pruefsumme).toSet();
      await expectLater(
        katalog.exportiere(auswahl, backup).drain<void>(),
        throwsFormatException,
      );
      await expectLater(
        katalog
            .exportiere(auswahl, bibliothek, bibliothek: bibliothek)
            .drain<void>(),
        throwsFormatException,
      );
      final stand = await katalog.exportiere(auswahl, ziel).last;
      expect(
        stand.ordner.listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['0001_CON.jpg', '0002_CON.jpg']),
      );
    },
  );

  test(
    'ältere verschlüsselte Stufe bleibt auf ihrem Stand, Export prüft das Original',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(bibliothek);
      final importe = ImportService(db, paths);
      Future<List<int>> foto(String name, int farbe) async {
        final bild = img.Image(width: 24, height: 20)
          ..clear(img.ColorRgb8(farbe, 25, 50));
        final bytes = img.encodeJpg(bild);
        final datei = File(p.join(temp.path, name))..writeAsBytesSync(bytes);
        expect(
          (await importe.importFile(datei.path)).outcome,
          ImportOutcome.imported,
        );
        return bytes;
      }

      const passphrase = 'Nur fuer die synthetische Probe';
      final verpackt = await VaultCrypto.createMasterKey(passphrase);
      await db.saveBackupKey(
        kdfSalt: verpackt.kdfSalt,
        nonce: verpackt.nonce,
        wrapped: verpackt.wrapped,
      );
      final erst = await foto('alt.jpg', 1);
      final dienst = BackupService(db, paths);
      await dienst
          .performAutoBackup(backup.path, verpackt.masterKey)
          .drain<void>();
      final wurzel = p.join(backup.path, BackupService.autoBackupFolderName);
      final alt = (await dienst.autoBackupGenerations(wurzel)).single;
      await foto('spaeter.jpg', 2);
      await dienst
          .performAutoBackup(backup.path, verpackt.masterKey)
          .drain<void>();
      await expectLater(
        BackupAuswahl.oeffne(
          wurzel,
          schemaVersion: db.schemaVersion,
          passphrase: 'falsch',
        ),
        throwsA(anything),
      );
      final katalog = await BackupAuswahl.oeffne(
        wurzel,
        schemaVersion: db.schemaVersion,
        passphrase: passphrase,
        generation: alt.snapshotPath,
      );
      expect(katalog.aufnahmen.single.name, 'alt.jpg');
      final aktuellerKatalog = await BackupAuswahl.oeffne(
        wurzel,
        schemaVersion: db.schemaVersion,
        passphrase: passphrase,
      );
      expect(aktuellerKatalog.aufnahmen, hasLength(2));
      final id = katalog.aufnahmen.single.pruefsumme;
      expect(await katalog.pruefeOriginal(id), isTrue);
      final fertig = await katalog.exportiere({id}, ziel).last;
      expect(
        fertig.ordner.listSync().whereType<File>().single.readAsBytesSync(),
        erst,
      );

      final verschluesselt = File(
        p.join(
          wurzel,
          VerschluesselteNamen.ordner,
          await VerschluesselteNamen.fuerPruefsumme(id, verpackt.masterKey),
        ),
      );
      final bytes = verschluesselt.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 1;
      verschluesselt.writeAsBytesSync(bytes);
      await expectLater(katalog.pruefeOriginal(id), throwsA(anything));
      expect((await katalog.exportiere({id}, ziel).last).fehler, ['alt.jpg']);
      expect(await db.select(db.assets).get(), hasLength(2));
    },
  );

  ImportPlanEintrag eintrag(
    String name,
    List<int> inhalt, [
    ImportPlanArt art = ImportPlanArt.neu,
  ]) {
    final pfad = p.join(temp.path, 'dcim', name);
    return ImportPlanEintrag(
      pfad: pfad,
      art: art,
      angaben: ImportDateiangaben(
        pfad: pfad,
        pruefsumme: hash(inhalt),
        bytes: inhalt.length,
        datum: DateTime(2024),
        datumGeschaetzt: false,
        istBild: true,
      ),
    );
  }

  ImportPlan plan(List<ImportPlanEintrag> eintraege) => ImportPlan(
    eintraege: eintraege,
    regelstand: 'probe',
    am: DateTime(2026),
    spaetereRegeln: 0,
  );

  test(
    'Quittung bleibt nach Neustart und zählt Vorschau, Fotokammer und echte Ergebnisse',
    () async {
      final neu = eintrag('neu.jpg', [1]);
      final duplikat = eintrag('doppelt.jpg', [2], ImportPlanArt.vorhanden);
      final skip = eintrag('skip.jpg', [3]);
      final kaputt = eintrag('kaputt.jpg', [4]);
      final kammer = eintrag('kammer.jpg', [5]);
      final auswahl = plan([
        neu,
        duplikat,
        skip,
        kaputt,
        kammer,
      ]).auswahl({neu.pfad, kaputt.pfad, kammer.pfad}, mitAusgelassenen: true);
      final ablage = Importquittungen(bibliothek);
      await ablage
          .protokolliere(
            auswahl,
            Stream.fromIterable([
              ImportProgress(0, 3),
              ImportProgress(1, 3, pfad: neu.pfad, assetId: 'a'),
              ImportProgress(
                2,
                3,
                pfad: kaputt.pfad,
                gescheitert: true,
                grund: temp.path,
              ),
              ImportProgress(3, 3, pfad: kammer.pfad, kammer: true),
            ]),
          )
          .drain<void>();

      final neuGeoeffnet = Importquittungen(bibliothek);
      final kopf = (await neuGeoeffnet.liste()).single;
      final beleg = await neuGeoeffnet.lies(kopf.id);
      expect(kopf.anzahl, 5);
      expect(beleg.fertig, isTrue);
      expect(
        {for (final a in beleg.dateien) a.name: a.ergebnis},
        {
          'neu.jpg': ImportErgebnis.importiert,
          'doppelt.jpg': ImportErgebnis.duplikat,
          'skip.jpg': ImportErgebnis.ausgelassen,
          'kaputt.jpg': ImportErgebnis.fehler,
          'kammer.jpg': ImportErgebnis.kammer,
        },
      );
      expect(beleg.pruefsummen, {
        hash([1]),
        hash([2]),
        hash([5]),
      });
      final verdeckt = beleg.mitVerdecktenDateinamen({
        hash([1]),
      });
      expect(verdeckt.dateien.first.name, isEmpty);
      expect(verdeckt.pruefsummen, isNot(contains(hash([1]))));
      expect(beleg.pruefung, isNull);
      final journal = Directory(
        p.join(bibliothek.path, 'importquittungen'),
      ).listSync().whereType<File>().single;
      expect(journal.readAsStringSync(), isNot(contains(temp.path)));
    },
  );

  test(
    'reine Dubletten können ohne einen erneuten Import quittiert werden',
    () async {
      final a = eintrag('schon-da.jpg', [1], ImportPlanArt.vorhanden);
      final ablage = Importquittungen(bibliothek);
      final auswahl = plan([a]).auswahl({}, mitAusgelassenen: true);
      await ablage.protokolliere(auswahl, const Stream.empty()).drain<void>();
      final beleg = await ablage.lies((await ablage.liste()).single.id);
      expect(beleg.fertig, isTrue);
      expect(beleg.dateien.single.ergebnis, ImportErgebnis.duplikat);
    },
  );

  test('Quittung weist bei Abbruch offene Dateien aus', () async {
    final a = eintrag('a.jpg', [1]);
    final b = eintrag('b.jpg', [2]);
    final ablage = Importquittungen(bibliothek);
    Stream<ImportProgress> unterbrochen() async* {
      yield ImportProgress(1, 2, pfad: a.pfad, assetId: 'a');
      throw StateError('Abbruch');
    }

    await expectLater(
      ablage.protokolliere(plan([a, b]), unterbrochen()).drain<void>(),
      throwsStateError,
    );
    final id = (await ablage.liste()).single.id;
    final beleg = await ablage.lies(id);
    expect(beleg.fertig, isFalse);
    expect(beleg.dateien.first.ergebnis, ImportErgebnis.importiert);
    expect(beleg.dateien.last.ergebnis, ImportErgebnis.offen);
  });

  test(
    'Quittung bestätigt nach Inhaltsvergleich nur intakte vorhandene Sicherungskopien',
    () async {
      final a = eintrag('heil.jpg', [1]);
      final b = eintrag('defekt.jpg', [2]);
      final c = eintrag('fehlt.jpg', [3]);
      final ablage = Importquittungen(bibliothek);
      await ablage
          .protokolliere(
            plan([a, b, c]),
            Stream.fromIterable([
              for (final e in [a, b, c])
                ImportProgress(1, 3, pfad: e.pfad, assetId: e.pfad),
            ]),
          )
          .drain<void>();
      manifest([
        aufnahme('heil.jpg', 'originals/a.jpg', [1]),
        aufnahme('defekt.jpg', 'originals/b.jpg', [2]),
      ]);
      File(p.join(backup.path, 'originals/b.jpg')).writeAsBytesSync([6]);
      final id = (await ablage.liste()).single.id;
      await ablage.pruefeKopien(
        await ablage.lies(id),
        await oeffne(),
        'backup',
      );
      final nachweis = (await Importquittungen(bibliothek).lies(id)).pruefung!;
      expect(nachweis.ziel, 'backup');
      expect(nachweis.befunde, {
        hash([1]): Kopienbefund.bestaetigt,
        hash([2]): Kopienbefund.unlesbar,
        hash([3]): Kopienbefund.fehlt,
      });
    },
  );

  testWidgets(
    'Suche und Auswahl sind getrennt und bleiben im Katalog sichtbar',
    (tester) async {
      final katalog = await tester.runAsync(() async {
        manifest([
          aufnahme('wald.jpg', 'originals/a.jpg', [1]),
          aufnahme('meer.jpg', 'originals/b.jpg', [2]),
        ]);
        return oeffne();
      });
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppTexte.supportedLocales,
          localizationsDelegates: AppTexte.localizationsDelegates,
          home: BackupAuswahlScreen(katalog: katalog!, bibliothek: bibliothek),
        ),
      );
      await tester.enterText(find.byType(TextField), 'wald');
      await tester.pump();
      expect(find.text('wald.jpg'), findsOneWidget);
      expect(find.text('meer.jpg'), findsNothing);
      await tester.tap(find.text('wald.jpg'));
      await tester.pump();
      expect(find.text('Auswahl exportieren (1)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'meer');
      await tester.pump();
      expect(find.text('meer.jpg'), findsOneWidget);
      expect(find.text('Auswahl exportieren (1)'), findsOneWidget);
    },
  );
}

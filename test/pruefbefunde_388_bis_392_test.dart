import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_fotokammer.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:photo_vault/services/backup_koordinator.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Befunde der Prüfberichte vom 31.10. und 13.11.2026 (#388–#391) –
/// jeder als Test, der ohne die Behebung wieder durchfällt. Das
/// Release-Werkzeug (#392) prüft `tool/tests/test_release.py`.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_befunde_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory('${temp.path}/library'));
    importe = ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    );
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  List<int> jpeg(int rot) {
    final bild = img.Image(width: 16, height: 16);
    img.fill(bild, color: img.ColorRgb8(rot, 90, 180));
    return img.encodeJpg(bild);
  }

  Future<AssetData> foto(String name, int rot) async {
    final f = File('${temp.path}/$name')..writeAsBytesSync(jpeg(rot));
    final r = await importe.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported);
    return (await db.assetById(r.assetId!))!;
  }

  Future<void> zeile(String id, {String type = 'IMAGE', String? partner}) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id',
          checksum: 'summe_$id',
          type: type,
          fileCreatedAt: DateTime(2026, 10, 31),
          importedAt: DateTime(2026, 10, 31),
          linkedAssetId: Value(partner),
        ),
      );

  group('Papierkorb (#389)', () {
    test('eine vorher für sich gelöschte Variante bleibt im Papierkorb, '
        'auch in derselben Sekunde', () async {
      await zeile('haupt');
      await zeile('variante');
      await db.fuehreAus(
        const VariantenBilden('probe', ['haupt', 'variante'], 'haupt'),
      );
      await db.fuehreAus(const InDenPapierkorb(['variante']));
      await db.fuehreAus(const InDenPapierkorb(['haupt']));
      // Dieselbe Sekunde erzwingen: Bis 3.67.2 entschied allein sie.
      final am = (await db.assetById('haupt'))!.trashedAt;
      await (db.update(db.assets)..where((a) => a.id.equals('variante'))).write(
        AssetsCompanion(trashedAt: Value(am)),
      );

      await db.fuehreAus(const AusDemPapierkorb(['haupt']));

      expect((await db.assetById('haupt'))!.isTrashed, isFalse);
      final v = (await db.assetById('variante'))!;
      expect(v.isTrashed, isTrue);
      expect(v.papierkorbAktion, isNotNull);
    });

    test('was zusammen ging, kommt zusammen zurück, ohne Aktion', () async {
      await zeile('haupt');
      await zeile('variante');
      await db.fuehreAus(
        const VariantenBilden('probe', ['haupt', 'variante'], 'haupt'),
      );
      await db.fuehreAus(const InDenPapierkorb(['haupt']));
      final h = (await db.assetById('haupt'))!;
      final v = (await db.assetById('variante'))!;
      expect(v.isTrashed, isTrue);
      expect(v.papierkorbAktion, h.papierkorbAktion);

      await db.fuehreAus(const AusDemPapierkorb(['variante']));

      for (final id in ['haupt', 'variante']) {
        final a = (await db.assetById(id))!;
        expect(a.isTrashed, isFalse, reason: id);
        expect(a.papierkorbAktion, isNull, reason: id);
        expect(a.trashedAt, isNull, reason: id);
      }
    });

    test(
      'vor Schema 98 Gelöschtes kommt weiter nach Zeitpunkt zurück',
      () async {
        await zeile('haupt');
        await zeile('variante');
        await db.fuehreAus(
          const VariantenBilden('probe', ['haupt', 'variante'], 'haupt'),
        );
        await (db.update(
          db.assets,
        )..where((a) => a.id.isIn(['haupt', 'variante']))).write(
          AssetsCompanion(
            isTrashed: const Value(true),
            trashedAt: Value(DateTime(2026, 10, 30)),
          ),
        );

        await db.fuehreAus(const AusDemPapierkorb(['haupt']));

        expect((await db.assetById('variante'))!.isTrashed, isFalse);
      },
    );

    test('die Reparatur nimmt die Videohälfte einer verdeckten Variante '
        'im selben Lauf mit', () async {
      await zeile('haupt');
      await zeile('variante', partner: 'video');
      await zeile('video', type: 'VIDEO', partner: 'variante');
      await db.fuehreAus(
        const VariantenBilden('probe', ['haupt', 'variante'], 'haupt'),
      );
      await (db.update(db.assets)..where((a) => a.id.equals('haupt'))).write(
        AssetsCompanion(
          isTrashed: const Value(true),
          trashedAt: Value(DateTime(2026, 10, 30)),
          papierkorbAktion: const Value('aktion'),
        ),
      );

      await db.repariereVerdeckteZugehoerige();

      for (final id in ['variante', 'video']) {
        final a = (await db.assetById(id))!;
        expect(a.isTrashed, isTrue, reason: id);
        expect(a.papierkorbAktion, 'aktion', reason: id);
      }
      expect(await db.repariereVerdeckteZugehoerige(), 0);
    });
  });

  group('Sicherung (#388)', () {
    test(
      'verschlüsselt verlangt, ohne Schlüssel: Fehler, kein Klartext',
      () async {
        final bytes = List<int>.generate(64, (i) => i);
        final f = File('${temp.path}/probe.jpg')..writeAsBytesSync(bytes);
        expect(
          (await importe.importFile(f.path)).outcome,
          ImportOutcome.imported,
        );
        final koordinator = BackupKoordinator(
          db: db,
          backupService: BackupService(db, paths),
          istVerbunden: () => false,
          meldeWarnung: (_) {},
          meldeProbe: (_) {},
        );

        await expectLater(
          koordinator
              .runManualBackup('${temp.path}/ziel', encrypt: true)
              .drain<void>(),
          throwsStateError,
        );
        expect(Directory('${temp.path}/ziel').existsSync(), isFalse);
      },
    );

    test('eine abgeschnittene verschlüsselte Datei wird erneuert', () async {
      final asset = await foto('a.jpg', 70);
      final original = await paths.absolute(asset.relativePath).readAsBytes();
      final key = await VaultCrypto.createMasterKey('synthetischer-schluessel');
      await db.saveBackupKey(
        kdfSalt: key.kdfSalt,
        nonce: key.nonce,
        wrapped: key.wrapped,
      );
      final service = BackupService(db, paths);
      await service
          .performAutoBackup('${temp.path}/ziel', key.masterKey)
          .drain<void>();
      final root = '${temp.path}/ziel/${BackupService.autoBackupFolderName}';
      final datei = Directory('$root/data').listSync().whereType<File>().single;
      final bytes = await datei.readAsBytes();
      await datei.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));

      final lauf = await service
          .performAutoBackup('${temp.path}/ziel', key.masterKey)
          .toList();

      expect(await datei.length(), bytes.length);
      final klar = File('${temp.path}/wieder-klar.jpg');
      await VaultCrypto.decryptFile(datei, klar, key.masterKey);
      expect(await klar.readAsBytes(), original);
      expect(lauf.last.wiederherstellungsprobe?.erfolgreich, isTrue);
    });

    test('die erwartete Grösse stimmt an den Blockgrenzen', () async {
      final key = await VaultCrypto.createMasterKey('synthetischer-schluessel');
      const mib = 1024 * 1024;
      for (final n in [0, 1, mib - 1, mib, mib + 1, 2 * mib]) {
        final klar = File('${temp.path}/k$n')
          ..writeAsBytesSync(List<int>.filled(n, 7));
        final enc = File('${temp.path}/k$n.enc');
        await VaultCrypto.encryptFile(klar, enc, key.masterKey);
        expect(await VaultCrypto.passtZurGroesse(enc, n), isTrue, reason: '$n');
        final b = enc.readAsBytesSync();
        enc.writeAsBytesSync(b.sublist(0, b.length - 1));
        expect(
          await VaultCrypto.passtZurGroesse(enc, n),
          isFalse,
          reason: '$n',
        );
      }
      final fremd = File('${temp.path}/fremd')
        ..writeAsBytesSync(List<int>.filled(100, 1));
      expect(await VaultCrypto.passtZurGroesse(fremd, 100), isFalse);
      expect(
        await VaultCrypto.passtZurGroesse(File('${temp.path}/fehlt'), 1),
        isFalse,
      );
    });

    test(
      'ausgewählte Wiederherstellung lässt andere Aufnahmen in Ruhe',
      () async {
        final a = await foto('a.jpg', 20);
        final b = await foto('b.jpg', 230);
        await db.fuehreAus(BeschreibungSetzen([b.id], 'gesicherter Stand'));
        await db.fuehreAus(BewertungSetzen([b.id], 4));
        final service = BackupService(db, paths);
        await service.performBackup('${temp.path}/ziel').drain<void>();
        await db.fuehreAus(BeschreibungSetzen([b.id], 'aktueller Stand'));
        await db.fuehreAus(BewertungSetzen([b.id], 1));

        await service
            .restoreFromBackup(
              '${temp.path}/ziel/PhotoVault-Backup',
              importe,
              auswahlPruefsummen: {a.checksum},
            )
            .drain<void>();

        final jetzt = (await db.assetById(b.id))!;
        expect(jetzt.description, 'aktueller Stand');
        expect(jetzt.rating, 1);
      },
    );
  });

  group('Fotokammer in der Wiederherstellung (#388)', () {
    late AppDatabase zielDb;
    late ImportService zielImport;
    late BackupService ziel;
    setUp(() async {
      zielDb = AppDatabase(NativeDatabase.memory());
      final zielPfade = await StoragePaths.forTesting(
        Directory('${temp.path}/zielbibliothek'),
      );
      ziel = BackupService(zielDb, zielPfade);
      zielImport = ImportService(
        zielDb,
        zielPfade,
        bildwerkzeuge: const KeineBildwerkzeuge(),
      );
    });
    tearDown(() => zielDb.close());

    Future<({String root, SecretKey key})> sicherung() async {
      await foto('bibliothek.jpg', 30);
      final key = await VaultCrypto.createMasterKey('Testpassphrase');
      await db.saveBackupKey(
        kdfSalt: key.kdfSalt,
        nonce: key.nonce,
        wrapped: key.wrapped,
      );
      final backup = '${temp.path}/backup';
      await BackupService(
        db,
        paths,
      ).performAutoBackup(backup, key.masterKey).drain<void>();
      return (
        root: '$backup/${BackupService.autoBackupFolderName}',
        key: key.masterKey,
      );
    }

    Future<void> kammerfoto(
      String root,
      SecretKey key,
      String name,
      DateTime am,
    ) async {
      final kammer = Directory('${temp.path}/kammer');
      final eintrag = Directory('${kammer.path}/$name')
        ..createSync(recursive: true);
      File(
        '${eintrag.path}/$name.jpg',
      ).writeAsBytesSync(jpeg(name.length * 20));
      File(
        '${eintrag.path}/angaben.json',
      ).writeAsStringSync(jsonEncode({'name': '$name.jpg'}));
      final r = await FotokammerSicherung.sichere(
        kammer: kammer,
        sicherung: Directory(root),
        schluessel: key,
        jetzt: am,
      );
      expect(r.neu, 1);
    }

    Future<List<String>> namen() async =>
        (await zielDb.select(zielDb.assets).get())
            .map((a) => a.originalFileName)
            .toList()
          ..sort();

    test('eine ältere Stufe holt kein später gesichertes Kammerfoto', () async {
      final (:root, :key) = await sicherung();
      final service = BackupService(db, paths);
      final alt = (await service.autoBackupGenerations(root)).single;
      await kammerfoto(
        root,
        key,
        'spaeter',
        alt.createdAt.add(const Duration(days: 1)),
      );
      // Eine zweite Stufe danach, sonst ist die erste die neueste.
      await foto('zweite.jpg', 140);
      await Future<void>.delayed(const Duration(seconds: 1));
      await service.performAutoBackup('${temp.path}/backup', key).drain<void>();
      final stufen = await service.autoBackupGenerations(root);
      expect(stufen, hasLength(2));

      await ziel
          .restoreFromBackup(
            root,
            zielImport,
            entschluesselungsschluessel: key,
            generationSnapshotPath: alt.snapshotPath,
          )
          .drain<void>();

      expect(await namen(), ['bibliothek.jpg']);
    });

    test('die neueste Stufe holt auch spätere Kammerfotos', () async {
      final (:root, :key) = await sicherung();
      final service = BackupService(db, paths);
      final neueste = (await service.autoBackupGenerations(root)).single;
      await kammerfoto(
        root,
        key,
        'spaeter',
        neueste.createdAt.add(const Duration(days: 3)),
      );

      await ziel
          .restoreFromBackup(
            root,
            zielImport,
            entschluesselungsschluessel: key,
            generationSnapshotPath: neueste.snapshotPath,
          )
          .drain<void>();

      expect(await namen(), ['bibliothek.jpg', 'spaeter.jpg']);
    });

    test('beschädigte Kammerangaben verhindern den Erfolg', () async {
      final (:root, :key) = await sicherung();
      await kammerfoto(root, key, 'kaputt', DateTime(2026, 11, 13));
      File('$root/fotokammer/kaputt/angaben.enc').writeAsBytesSync([1, 2, 3]);

      final fortschritt = await ziel
          .restoreFromBackup(root, zielImport, entschluesselungsschluessel: key)
          .toList();

      final ergebnis = fortschritt.last.wiederherstellung!;
      expect(ergebnis.importiert, 1);
      expect(ergebnis.erfolgreich, isFalse);
    });

    test('Stufenzugehörigkeit', () {
      final stufe = DateTime.utc(2026, 11, 1);
      final naechste = DateTime.utc(2026, 11, 5);
      bool gehoert(DateTime? am, {DateTime? bis}) =>
          FotokammerSicherung.gehoertZuStufe(am, stufe: stufe, naechste: bis);
      expect(
        gehoert(stufe.add(const Duration(hours: 11)), bis: naechste),
        isTrue,
      );
      expect(
        gehoert(stufe.add(const Duration(hours: 13)), bis: naechste),
        isFalse,
      );
      expect(
        gehoert(
          stufe.add(const Duration(hours: 2)),
          bis: stufe.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        gehoert(stufe.subtract(const Duration(days: 9)), bis: naechste),
        isTrue,
      );
      expect(gehoert(stufe.add(const Duration(days: 30))), isTrue);
      expect(gehoert(null, bis: naechste), isTrue);
    });
  });

  group('Überwachter Ordner (#390)', () {
    Future<LibraryState> ordner(ImportService dienst) async {
      final eingang = Directory('${temp.path}/kamera')..createSync();
      File('${eingang.path}/probe.jpg')
        ..writeAsBytesSync(List.filled(64, 21))
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );
      await db.setzeUeberwachtenOrdner(pfad: eingang.path);
      final library = LibraryState()
        ..db = db
        ..paths = paths
        ..importService = dienst;
      // Nach einem Import läuft die Auswertung an. Sie soll fertig sein,
      // ehe die Datenbank schliesst.
      addTearDown(() async {
        for (var i = 0; i < 500 && library.etwasLaeuft; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      return library;
    }

    test('ein vorübergehend gescheiterter Import kommt wieder dran', () async {
      final dienst = _Scheitert(db, paths, mal: 1);
      final library = await ordner(dienst);
      expect(await library.pruefeUeberwachtenOrdner(), 0);
      expect(await library.pruefeUeberwachtenOrdner(), 1);
      expect(dienst.versuche, 2);
      expect(await library.pruefeUeberwachtenOrdner(), 0);
      expect(dienst.versuche, 2);
    });

    test('was immer scheitert, wird nicht endlos versucht', () async {
      final dienst = _Scheitert(db, paths, mal: 1000);
      final library = await ordner(dienst);
      for (var i = 0; i < 8; i++) {
        expect(await library.pruefeUeberwachtenOrdner(), 0);
      }
      expect(dienst.versuche, 5);
    });
  });

  group('Serververbindung (#391)', () {
    test(
      'das Zeitlimit gilt auch für einen stockenden Antwortinhalt',
      () async {
        final inhalt = StreamController<List<int>>();
        final verbindung = Serververbindung(
          Uri.parse('http://127.0.0.1/'),
          'synthetisch',
          client: _Strom(inhalt.stream),
        );
        addTearDown(verbindung.schliesse);
        Object? fehler;
        final offen = verbindung
            .anfrage(
              'GET',
              'probe',
              zeitlimit: const Duration(milliseconds: 15),
            )
            .then<Object?>(
              (r) => r,
              onError: (Object e) {
                fehler = e;
                return null;
              },
            );
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(fehler, isA<KeineVerbindung>());
        inhalt.add(utf8.encode('fertig'));
        await inhalt.close();
        await offen;
      },
    );

    test(
      'ein stockender Download lässt nichts liegen und geht danach wieder',
      () async {
        final stockt = StreamController<List<int>>();
        addTearDown(stockt.close);
        final verbindung = Serververbindung(
          Uri.parse('http://127.0.0.1/'),
          'synthetisch',
          client: _Folge([
            stockt.stream,
            Stream.value(utf8.encode('ganze Datei')),
          ]),
          downloadStille: const Duration(milliseconds: 20),
        );
        addTearDown(verbindung.schliesse);
        final ziel = File('${temp.path}/laden/datei.bin');
        stockt.add(utf8.encode('erster Teil'));

        await expectLater(
          verbindung.ladeHerunter('datei', ziel),
          throwsA(isA<KeineVerbindung>()),
        );
        expect(ziel.existsSync(), isFalse);
        expect(File('${ziel.path}.teil').existsSync(), isFalse);

        await verbindung.ladeHerunter('datei', ziel);
        expect(ziel.readAsStringSync(), 'ganze Datei');
      },
    );
  });
}

class _Scheitert extends ImportService {
  _Scheitert(super.db, super.paths, {required this.mal})
    : super(bildwerkzeuge: const KeineBildwerkzeuge());
  final int mal;
  int versuche = 0;

  @override
  Future<ImportResult> importFile(
    String path, {
    String? erwartetePruefsumme,
    ImportDateiangaben? erwarteteAngaben,
    Future<void> Function(String assetId)? beiEintrag,
  }) async {
    versuche++;
    if (versuche <= mal) {
      return ImportResult(
        path,
        ImportOutcome.failed,
        error: 'vorübergehend nicht verfügbar',
      );
    }
    return super.importFile(
      path,
      erwartetePruefsumme: erwartetePruefsumme,
      erwarteteAngaben: erwarteteAngaben,
      beiEintrag: beiEintrag,
    );
  }
}

/// Liefert je Anfrage den nächsten Antwortinhalt aus [inhalte].
class _Folge extends http.BaseClient {
  _Folge(this.inhalte);
  final List<Stream<List<int>>> inhalte;
  var _n = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async =>
      http.StreamedResponse(inhalte[_n++], 200);
}

class _Strom extends http.BaseClient {
  _Strom(this.stream);
  final Stream<List<int>> stream;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async =>
      http.StreamedResponse(stream, 200);
}

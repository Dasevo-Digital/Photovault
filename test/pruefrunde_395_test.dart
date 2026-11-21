import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_fotokammer.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/jpeg_ohne_angaben.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Befunde der vierten Prüfrunde nach 3.67.4 (#395) – jeder als Test,
/// der ohne die Behebung wieder durchfällt.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_runde395_');
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

  group('Sicherung ersetzt keine heile Kopie durch eine kaputte Quelle', () {
    test('verschlüsselt: abgeschnittene Bibliotheksdatei', () async {
      final asset = await foto('a.jpg', 70);
      final hier = paths.absolute(asset.relativePath);
      final original = await hier.readAsBytes();
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
      final kopie = Directory('$root/data').listSync().whereType<File>().single;
      final vorher = await kopie.readAsBytes();

      // Die Datei der Bibliothek wird beschädigt, die Datenbank weiss es
      // nicht.
      await hier.writeAsBytes(original.sublist(0, original.length ~/ 2));
      final lauf = await service
          .performAutoBackup('${temp.path}/ziel', key.masterKey)
          .toList();

      expect(await kopie.readAsBytes(), vorher, reason: 'die Kopie bleibt');
      final klar = File('${temp.path}/klar.jpg');
      await VaultCrypto.decryptFile(kopie, klar, key.masterKey);
      expect(await klar.readAsBytes(), original);
      expect(lauf.last.fehlgeschlagen, 1, reason: 'gemeldet, nicht still');
    });

    test('unverschlüsselt: am Ort geänderte Bibliotheksdatei', () async {
      final asset = await foto('b.jpg', 120);
      final hier = paths.absolute(asset.relativePath);
      final original = await hier.readAsBytes();
      final service = BackupService(db, paths);
      await service.performBackup('${temp.path}/ziel').drain<void>();
      final kopien = Directory('${temp.path}/ziel')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList();
      expect(kopien, hasLength(1));

      await hier.writeAsBytes([...original, 1, 2, 3]);
      await service.performBackup('${temp.path}/ziel').drain<void>();

      expect(await kopien.single.readAsBytes(), original);
    });

    test('die Grösse allein genügt für die Anzeige des Stands', () async {
      final key = await VaultCrypto.createMasterKey('synthetischer-schluessel');
      const mib = 1024 * 1024;
      for (final n in [0, 1, mib, mib + 1]) {
        final klar = File('${temp.path}/k$n')
          ..writeAsBytesSync(List<int>.filled(n, 3));
        final enc = File('${temp.path}/k$n.enc');
        await VaultCrypto.encryptFile(klar, enc, key.masterKey);
        final laenge = enc.lengthSync();
        expect(VaultCrypto.passtNachGroesse(laenge, n), isTrue, reason: '$n');
        expect(VaultCrypto.passtNachGroesse(laenge - 1, n), isFalse);
      }
    });
  });

  group('Fotokammer der Sicherung', () {
    late Directory kammer;
    late Directory sicherung;
    late SecretKey schluessel;
    late Map<String, String> quellAngaben;

    setUp(() async {
      kammer = Directory('${temp.path}/kammer');
      final eintrag = Directory('${kammer.path}/e1')
        ..createSync(recursive: true);
      final bytes = jpeg(40);
      File('${eintrag.path}/e1.jpg').writeAsBytesSync(bytes);
      quellAngaben = {
        'name': 'e1.jpg',
        'sha256': sha256.convert(bytes).toString(),
      };
      File(
        '${eintrag.path}/angaben.json',
      ).writeAsStringSync(jsonEncode(quellAngaben));
      sicherung = Directory('${temp.path}/sicherung')..createSync();
      schluessel = (await VaultCrypto.createMasterKey('kammer')).masterKey;
    });

    Future<KammerSicherungsbilanz> sichere(DateTime jetzt) =>
        FotokammerSicherung.sichere(
          kammer: kammer,
          sicherung: sicherung,
          schluessel: schluessel,
          jetzt: jetzt,
        );

    String platz(String name) =>
        '${sicherung.path}/${FotokammerSicherung.ordnerName}/e1/$name';

    test('fehlt die Datei in der Sicherung, kommt der Eintrag neu', () async {
      expect((await sichere(DateTime.utc(2026, 11, 14))).neu, 1);
      File(platz(FotokammerSicherung.dateiName)).deleteSync();

      final r = await sichere(DateTime.utc(2026, 11, 15));

      expect(r.neu, 1);
      expect(File(platz(FotokammerSicherung.dateiName)).existsSync(), isTrue);
      // Der Vermerk bleibt der der ersten Sicherung.
      expect(
        File(platz(FotokammerSicherung.gesichertName)).readAsStringSync(),
        DateTime.utc(2026, 11, 14).toIso8601String(),
      );
      expect((await sichere(DateTime.utc(2026, 11, 16))).neu, 0);
    });

    test('unlesbare Angaben in der Sicherung kommen neu (#396)', () async {
      await sichere(DateTime.utc(2026, 11, 14));
      final angaben = File(platz(FotokammerSicherung.angabenName));
      final b = angaben.readAsBytesSync();
      // Gleich gross, aber ein Byte im Chiffretext verdreht.
      b[b.length - 20] ^= 0xff;
      angaben.writeAsBytesSync(b);

      expect((await sichere(DateTime.utc(2026, 11, 15))).neu, 1);
      final klar = await VaultCrypto.decryptFileToBytes(angaben, schluessel);
      expect(jsonDecode(utf8.decode(klar)), quellAngaben);
    });

    test('ein Eintrag ohne Vermerk bekommt die Zeit seiner Angaben', () async {
      await sichere(DateTime.utc(2026, 10, 1));
      File(platz(FotokammerSicherung.gesichertName)).deleteSync();
      final damals = DateTime.utc(2026, 10, 2, 3, 4, 5);
      File(platz(FotokammerSicherung.angabenName)).setLastModifiedSync(damals);

      expect((await sichere(DateTime.utc(2026, 11, 15))).neu, 0);

      final vermerk = DateTime.parse(
        File(platz(FotokammerSicherung.gesichertName)).readAsStringSync(),
      );
      expect(vermerk, damals);
    });
  });

  group('Miniaturen ohne die Angaben des Originals (#380)', () {
    // Quer gespeichert, hochkant gehalten (Lage 6), mit Ort.
    img.Image bildMitOrt() {
      final bild = img.Image(width: 40, height: 20);
      img.fill(bild, color: img.ColorRgb8(200, 30, 30));
      bild.exif.imageIfd.orientation = 6;
      bild.exif.imageIfd['Make'] = img.IfdValueAscii('Kamerahersteller');
      bild.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
      bild.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(54, 1);
      return bild;
    }

    Uint8List mitOrt() => img.encodeJpg(bildMitOrt());

    void ohneAngaben(Uint8List jpeg) {
      final b = img.decodeJpg(jpeg)!;
      expect(b.exif.gpsIfd.isEmpty, isTrue, reason: 'kein Ort');
      expect(b.exif.imageIfd['Make'], isNull, reason: 'keine Kamera');
      expect(b.exif.imageIfd.hasOrientation, isFalse);
      expect(b.height > b.width, isTrue, reason: 'hochkant');
    }

    test('die Probe trägt wirklich einen Ort', () {
      // Der Dekoder dreht schon nach der Lage; der Ort bleibt dran.
      final b = img.decodeJpg(mitOrt())!;
      expect(b.exif.gpsIfd.isEmpty, isFalse);
      expect(b.exif.imageIfd['Make'], isNotNull);
    });

    test('Miniatur', () {
      ohneAngaben(decodeAndResizeThumbnail(mitOrt())!.jpegBytes);
    });

    test('Miniatur und Vorschau – auch unverkleinert', () {
      final r = decodeAndResizeThumbnailMitVorschau(mitOrt())!;
      ohneAngaben(r.jpegBytes);
      ohneAngaben(r.vorschau);
    });

    test('ungedreht wird gedreht, und das Bild selbst behält alles', () {
      final b = bildMitOrt();
      ohneAngaben(jpegOhneAngaben(b, quality: 80));
      expect(b.exif.imageIfd.orientation, 6);
      expect(b.exif.gpsIfd.isEmpty, isFalse);
      final gerade = bildMitOrt()..exif.imageIfd.orientation = 1;
      jpegOhneAngaben(gerade, quality: 80);
      expect(gerade.exif.gpsIfd.isEmpty, isFalse);
    });
  });

  group('Papierkorb: Gerät und Server schreiben dieselbe Aktion', () {
    test('Kennung und Zeitpunkt gehen mit dem Befehl', () async {
      final andere = AppDatabase(NativeDatabase.memory());
      addTearDown(andere.close);
      final f = await foto('c.jpg', 10);
      // Dieselbe Aufnahme auf der zweiten Seite.
      await andere.into(andere.assets).insert(f.toCompanion(false));

      final befehl = InDenPapierkorb([f.id]);
      await db.fuehreAus(befehl);
      // Der Server bekommt nur die Werte.
      final dort = Befehl.ausJson(
        (jsonDecode(jsonEncode(befehl.alsJson())) as Map)
            .cast<String, Object?>(),
      );
      await andere.fuehreAus(dort);

      final hier = (await db.assetById(f.id))!;
      final drueben = (await andere.assetById(f.id))!;
      expect(hier.papierkorbAktion, isNotNull);
      expect(drueben.papierkorbAktion, hier.papierkorbAktion);
      expect(drueben.trashedAt, hier.trashedAt);
    });

    test('ein Befehl ohne Kennung (ältere Fassung) bekommt eine', () async {
      final f = await foto('d.jpg', 200);
      await db.fuehreAus(
        Befehl.ausJson({
          'art': 'inDenPapierkorb',
          'werte': {
            'ids': [f.id],
          },
        }),
      );
      expect((await db.assetById(f.id))!.papierkorbAktion, isNotNull);
    });
  });

  // Mit Server lief der Fünf-Minuten-Takt nicht; später hineingelegte
  // Fotos kamen erst nach dem nächsten Einrichten (IMP-103).
  test('Überwachter Ordner: der Takt läuft auch verbunden', () async {
    final library = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = importe
      ..verbindung = Verbindungsdatei(
        server: Uri.parse('http://127.0.0.1:9/'),
        konto: 'probe',
        geraet: 'Rechner',
        token: 'probe',
      );
    expect(library.verbunden, isTrue);
    library.richteOrdnertaktEin();
    addTearDown(library.vorDemBeenden);
    expect(library.ordnertaktLaeuft, isTrue);
  });

  group('Überwachter Ordner ohne Server', () {
    test('ein nicht erreichbarer Server zählt nicht als Fehlversuch', () async {
      final eingang = Directory('${temp.path}/kamera')..createSync();
      File('${eingang.path}/probe.jpg')
        ..writeAsBytesSync(jpeg(90))
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(minutes: 10)),
        );
      await db.setzeUeberwachtenOrdner(pfad: eingang.path);
      final library = _OhneServer()
        ..db = db
        ..paths = paths
        ..importService = importe;
      // Nach dem Import läuft die Auswertung an. Sie soll fertig sein, ehe
      // die Datenbank schliesst.
      addTearDown(() async {
        for (var i = 0; i < 500 && library.etwasLaeuft; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      for (var i = 0; i < 8; i++) {
        expect(await library.pruefeUeberwachtenOrdner(), 0);
      }
      expect(library.versuche, 8, reason: 'jeder Durchgang versucht es');

      // Der Server ist wieder da – die Datei kommt noch, ohne Neustart.
      library.erreichbar = true;
      expect(await library.pruefeUeberwachtenOrdner(), 1);
    });
  });
}

/// Wie verbunden, solange [erreichbar] falsch ist: Jeder Upload scheitert
/// an der Verbindung.
class _OhneServer extends LibraryState {
  var versuche = 0;
  var erreichbar = false;

  @override
  Stream<ImportProgress> importFiles(
    List<String> filePaths, {
    ImportPlan? plan,
  }) async* {
    if (erreichbar) {
      yield* super.importFiles(filePaths, plan: plan);
      return;
    }
    var n = 0;
    for (final f in filePaths) {
      versuche++;
      yield ImportProgress(
        ++n,
        filePaths.length,
        pfad: f,
        gescheitert: true,
        grund: KeineVerbindung(const SocketException('nicht erreichbar')),
      );
    }
  }
}

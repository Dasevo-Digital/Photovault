import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/sicherung.dart' show Serversicherungsstand;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Die nächtliche Sicherung des Servers (Issue #125): verschlüsselt, nur
/// was am Ziel fehlt, nie ohne eingehängtes Ziel – und mit der App
/// wiederherstellbar.
void main() {
  const passphrase = 'eine lange passphrase';
  late Directory ordner;
  late Directory nas;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late Tresorschluessel tresor;
  late Konto erika;
  late Serversicherung sicherung;
  var jetzt = DateTime(2026, 10, 15, 3, 30);

  Serversicherung neu({
    bool ohneZiel = false,
    BackupService Function(AppDatabase db, StoragePaths pfade)? dienst,
  }) => Serversicherung(
    daten: Directory('${ordner.path}/daten'),
    ziel: ohneZiel ? null : nas,
    tresor: tresor,
    konten: konten,
    bibliotheken: bibliotheken,
    uhr: () => jetzt,
    dienst: dienst,
  );

  Future<void> foto(String name, int farbe) async {
    final f = File('${ordner.path}/quelle/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        img.encodeJpg(
          img.Image(width: 32, height: 24)
            ..clear(img.ColorRgb8(farbe, 40, 200 - farbe)),
        ),
      );
    final b = (await bibliotheken.fuer(erika.id)).bibliothek;
    final r = await b.importe.importFile(f.path);
    expect(r.outcome, ImportOutcome.imported, reason: '$name: ${r.error}');
  }

  Directory sicherungVon(Konto k) => Directory(
    '${nas.path}/${Serversicherung.ordnerFuer(k)}/PhotoVault-AutoBackup',
  );

  int verschluesselteDateien() =>
      Directory('${sicherungVon(erika).path}/data').listSync().length;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_sicherung_');
    nas = Directory('${ordner.path}/nas')..createSync();
    Directory('${ordner.path}/daten').createSync();
    sdb = Serverdatenbank.imSpeicher();
    tresor = Tresorschluessel(List.filled(32, 9));
    konten = Kontodienst(
      sdb,
      tresor,
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      ruhe: const Duration(hours: 1),
    );
    erika = await konten.legeAn('erika', 'ein langes passwort');
    await foto('a.jpg', 10);
    await foto('b.jpg', 120);
    jetzt = DateTime(2026, 10, 15, 3, 30);
    sicherung = neu();
  });

  tearDown(() async {
    sicherung.beende();
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  test('ohne Ziel aus, ohne Passphrase nicht eingerichtet', () async {
    expect(await neu(ohneZiel: true).stufe(), Sicherungsstufe.aus);
    expect(await sicherung.stufe(), Sicherungsstufe.nichtEingerichtet);
    await expectLater(sicherung.einrichten('kurz'), throwsArgumentError);
    await sicherung.einrichten(passphrase);
    expect(
      File('${nas.path}/${Serversicherung.markeName}').existsSync(),
      isTrue,
    );
    await expectLater(sicherung.einrichten(passphrase), throwsStateError);
  });

  test('alles beim ersten Lauf, beim zweiten nichts noch einmal', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    var stand = await sicherung.stand();
    expect(stand['ok'], isTrue);
    expect((stand['konten']! as List).single, containsPair('neu', 2));
    expect(verschluesselteDateien(), 2);
    expect(File('${sicherungVon(erika).path}/vault.key').existsSync(), isTrue);
    expect(await sicherung.stufe(), Sicherungsstufe.ok);

    jetzt = jetzt.add(const Duration(days: 1));
    await sicherung.jetzt();
    stand = await sicherung.stand();
    expect((stand['konten']! as List).single, containsPair('neu', 0));

    // Die abgeglichene Markierung bleibt unberührt – sie gehört den Geräten.
    final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
    expect(
      (await db.select(db.assets).get()).map((a) => a.autoBackedUp),
      everyElement(isFalse),
    );
  });

  test(
    'automatische Wiederherstellungsprobe meldet beschädigte Sicherung als Fehler und bewahrt den letzten Erfolg',
    () async {
      await sicherung.einrichten(passphrase);
      await sicherung.jetzt();
      final vorher = await sicherung.stand();
      final probe =
          ((vorher['konten'] as List).single as Map)['wiederherstellungsprobe']
              as Map;
      expect(probe['erfolgreich'], isTrue);
      expect(probe['originale'], 2);
      expect(probe['datenbank'], isTrue);
      final datei = Directory(
        '${sicherungVon(erika).path}/data',
      ).listSync().whereType<File>().first;
      // Bei gleicher Grösse: Eine gekürzte Datei schriebe der Lauf neu
      // (#388), den Schaden fände erst die Probe beim Entschlüsseln.
      final bytes = datei.readAsBytesSync();
      for (var i = bytes.length ~/ 2; i < bytes.length ~/ 2 + 8; i++) {
        bytes[i] ^= 0xff;
      }
      datei.writeAsBytesSync(bytes);
      jetzt = jetzt.add(const Duration(days: 1));
      await sicherung.jetzt();
      final nachher = await sicherung.stand();
      expect(nachher['ok'], isFalse);
      expect(nachher['letzterErfolg'], vorher['letzterErfolg']);
      final neu =
          ((nachher['konten'] as List).single as Map)['wiederherstellungsprobe']
              as Map;
      expect(neu['erfolgreich'], isFalse);
      expect(neu['letzterErfolg'], probe['letzterErfolg']);
    },
  );

  test(
    'passt kein Original ins Prüfbudget der Probe, gelingt der Lauf mit Hinweis',
    () async {
      // Wie am Rechner (SIC-057): Vorher galt der Lauf als gescheitert,
      // „Letzter Erfolg“ blieb stehen, und die Weboberfläche zeigte
      // „gescheitert · pv_probe_unlesbar“ – bei einer Bibliothek nur aus
      // grossen Videos jede Nacht.
      sicherung.beende();
      sicherung = neu(dienst: _OhneStichprobe.new);
      await sicherung.einrichten(passphrase);
      await sicherung.jetzt();
      final stand = await sicherung.stand();
      expect(stand['ok'], isTrue);
      expect(stand['stufe'], Sicherungsstufe.ok.name);
      expect(stand.containsKey('fehler'), isFalse);
      expect(stand['hinweis'], 'pv_probe_stichprobe_zu_gross');
      expect(stand['letzterErfolg'], jetzt.toUtc().toIso8601String());
      final konto = (stand['konten']! as List).single as Map;
      expect(konto['neu'], 2, reason: 'gesichert ist trotzdem alles');
      // Ein Erfolg der Probe ist es nicht: geprüft wurde nichts.
      expect((konto['wiederherstellungsprobe'] as Map)['erfolgreich'], isFalse);
      final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
      expect((await db.backupSettingsRow())!.lastAutoBackupAt, jetzt);

      // So sehen es die Apps: keine Warnung, die Probe als übersprungen.
      final inDerApp = Serversicherungsstand.ausJson(stand);
      expect(inDerApp.warnt, isFalse);
      expect(inDerApp.fehler, isNull);
      expect(inDerApp.proben.single.uebersprungen, isTrue);
    },
  );

  test(
    'eine gekürzte Sicherungsdatei wird beim nächsten Lauf erneuert',
    () async {
      await sicherung.einrichten(passphrase);
      await sicherung.jetzt();
      final datei = Directory(
        '${sicherungVon(erika).path}/data',
      ).listSync().whereType<File>().first;
      final ganz = datei.readAsBytesSync();
      datei.writeAsBytesSync(ganz.sublist(0, ganz.length ~/ 2));
      jetzt = jetzt.add(const Duration(days: 1));
      await sicherung.jetzt();
      final stand = await sicherung.stand();
      expect(stand['ok'], isTrue);
      final konto = (stand['konten']! as List).single as Map;
      expect(konto['neu'], 1);
      expect((konto['wiederherstellungsprobe'] as Map)['erfolgreich'], isTrue);
      expect(datei.lengthSync(), ganz.length);
    },
  );

  test('ein Konto mit Fehler hält die übrigen nicht auf (#404)', () async {
    final bert = await konten.legeAn('bert', 'ein langes passwort');
    final zora = await konten.legeAn('zora', 'ein langes passwort');
    await sicherung.einrichten(passphrase);
    // Wo der Ordner von bert hingehört, liegt eine Datei: Sein Ziel lässt
    // sich nicht anlegen.
    File('${nas.path}/${Serversicherung.ordnerFuer(bert)}')
      ..createSync()
      ..writeAsStringSync('im Weg');

    await sicherung.jetzt();
    final stand = await sicherung.stand();
    expect(stand['ok'], isFalse);
    final gesichert = [
      for (final k in stand['konten']! as List) (k as Map)['konto'],
    ];
    expect(gesichert, containsAll(['erika', 'zora']));
    expect(gesichert, isNot(contains('bert')));
    expect('${stand['fehler']}', contains('bert'));
    expect(sicherungVon(zora).existsSync(), isTrue);
    expect(verschluesselteDateien(), 2, reason: 'erika vollständig');
  });

  test('ohne Kennmarke kein Byte, ein neues Ziel füllt sich wieder', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    // Das NAS ist weg: der Ordner leer, ohne Marke.
    nas.deleteSync(recursive: true);
    nas.createSync();
    await sicherung.jetzt();
    expect(nas.listSync(), isEmpty, reason: 'nichts auf die eigene Platte');
    expect(await sicherung.stufe(), Sicherungsstufe.zielFehlt);
    final fehler = '${(await sicherung.stand())['fehler']}';
    expect(fehler, contains('Kennmarke'));
    // Die Weboberfläche zeigt den Satz, wie er ist.
    expect(fehler, isNot(startsWith('Bad state')));

    await sicherung.zielNeu();
    await sicherung.jetzt();
    expect(verschluesselteDateien(), 2);
    expect(await sicherung.stufe(), Sicherungsstufe.ok);
  });

  test('nach 36 Stunden ohne gelungenen Lauf: veraltet', () async {
    await sicherung.einrichten(passphrase);
    await sicherung.jetzt();
    jetzt = jetzt.add(const Duration(hours: 30));
    expect(await sicherung.stufe(), Sicherungsstufe.ok);
    jetzt = jetzt.add(const Duration(hours: 7));
    expect(await sicherung.stufe(), Sicherungsstufe.veraltet);
  });

  test('der nächste Lauf: heute um halb vier oder morgen', () {
    jetzt = DateTime(2026, 10, 15, 2);
    expect(sicherung.naechsterLauf(), DateTime(2026, 10, 15, 3, 30));
    jetzt = DateTime(2026, 10, 15, 3, 30);
    expect(sicherung.naechsterLauf(), DateTime(2026, 10, 16, 3, 30));
  });

  test(
    'mit der Passphrase lässt sie sich wie in der App zurückholen',
    () async {
      await sicherung.einrichten(passphrase);
      await sicherung.jetzt();

      final ziel = Directory('${ordner.path}/zurueck')..createSync();
      final db = await AppDatabase.open(ziel);
      addTearDown(db.close);
      final pfade = await StoragePaths.oeffne(
        Directory('${ziel.path}/library'),
      );
      await BackupService(db, pfade)
          .restoreFromBackup(
            sicherungVon(erika).path,
            ImportService(db, pfade),
            passphrase: passphrase,
          )
          .drain<void>();
      final quelle = (await bibliotheken.fuer(erika.id)).bibliothek;
      final vorher = {
        for (final a in await quelle.db.select(quelle.db.assets).get())
          a.checksum,
      };
      final nachher = {
        for (final a in await db.select(db.assets).get()) a.checksum,
      };
      expect(nachher, vorher);
      for (final a in await db.select(db.assets).get()) {
        expect(pfade.absolute(a.relativePath).existsSync(), isTrue);
      }

      await expectLater(
        BackupService(db, pfade)
            .restoreFromBackup(
              sicherungVon(erika).path,
              ImportService(db, pfade),
              passphrase: 'eine falsche passphrase',
            )
            .drain<void>(),
        throwsA(anything),
      );
    },
  );

  group('Fotokammer (#341)', () {
    late Directory kammer;

    /// Legt einen Eintrag an, wie `Fotokammer.lege` es tut.
    String eintrag(String id, String name, int farbe) {
      final platz = Directory('${kammer.path}/$id')
        ..createSync(recursive: true);
      final bytes = img.encodeJpg(
        img.Image(width: 32, height: 24)
          ..clear(img.ColorRgb8(farbe, 200 - farbe, 90)),
      );
      File('${platz.path}/$name').writeAsBytesSync(bytes);
      File('${platz.path}/angaben.json').writeAsStringSync(
        jsonEncode({
          'id': id,
          'name': name,
          'sha256': sha256.convert(bytes).toString(),
          'geaendert': DateTime(2026, 10, 1).millisecondsSinceEpoch,
          'beilage': {
            'schlagwoerter': ['Kammerwort'],
          },
        }),
      );
      return id;
    }

    Directory kopie(String id) =>
        Directory('${sicherungVon(erika).path}/fotokammer/$id');

    setUp(() async {
      final b = (await bibliotheken.fuer(erika.id)).bibliothek;
      kammer = Directory('${b.ordner.path}/fotokammer');
      await sicherung.einrichten(passphrase);
    });

    String gleich(int i) => '00000000-0000-4000-8000-00000000000$i';

    void beschaedigeBild(String id) {
      final datei = File('${kopie(id).path}/datei.enc');
      final bytes = datei.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0xff;
      datei.writeAsBytesSync(bytes);
    }

    Future<(RestoreErgebnis, int)> wiederherstellen() async {
      final ziel = await Directory('${ordner.path}/zurueck').create();
      final db = await AppDatabase.open(ziel);
      try {
        final pfade = await StoragePaths.oeffne(
          Directory('${ziel.path}/library'),
        );
        final lauf = await BackupService(db, pfade)
            .restoreFromBackup(
              sicherungVon(erika).path,
              ImportService(db, pfade),
              passphrase: passphrase,
            )
            .toList();
        return (
          lauf.last.wiederherstellung!,
          (await db.select(db.assets).get()).length,
        );
      } finally {
        await db.close();
      }
    }

    test(
      'gleich lange beschädigte Kopie wird aus der heilen Quelle repariert',
      () async {
        final id = eintrag(gleich(1), 'kammer.jpg', 48);
        await sicherung.jetzt();
        beschaedigeBild(id);
        await sicherung.jetzt();
        final stand = await sicherung.stand();
        final konto = (stand['konten'] as List).single as Map;
        expect(stand['ok'], isTrue);
        expect(konto['kammerGeprueft'], 1);
        expect(konto['kammerNeu'], 1);
        final (restore, anzahl) = await wiederherstellen();
        expect(restore.erfolgreich, isTrue);
        expect(anzahl, 3);
      },
    );

    test(
      'Stichprobe wechselt und ein bekannter Schaden bleibt ohne Quelle gemeldet',
      () async {
        for (var i = 0; i < 10; i++) {
          eintrag(gleich(i), 'kammer$i.jpg', 50 + i);
        }
        await sicherung.jetzt();
        final id = gleich(9);
        beschaedigeBild(id);
        Directory('${kammer.path}/$id').deleteSync(recursive: true);
        await sicherung.jetzt();
        final stand = await sicherung.stand();
        final konto = (stand['konten'] as List).single as Map;
        expect(konto['kammerGeprueft'], 8);
        expect(konto['kammerFehler'], 1);
        expect(stand['ok'], isFalse);
        // Andere Einträge werden weiter geprüft. Der zuvor erkannte Schaden
        // bleibt im Stand, auch in Läufen, deren Stichprobe ihn überspringt.
        for (var i = 0; i < 4; i++) {
          await sicherung.jetzt();
          expect((await sicherung.stand())['ok'], isFalse);
        }
      },
    );

    test(
      'eine geänderte Quelle ersetzt keine beschädigte Sicherungskopie',
      () async {
        final id = eintrag(gleich(1), 'kammer.jpg', 48);
        await sicherung.jetzt();
        beschaedigeBild(id);
        final datei = File('${kopie(id).path}/datei.enc');
        final vorher = datei.readAsBytesSync();
        final quelle = File('${kammer.path}/$id/kammer.jpg');
        final bytes = quelle.readAsBytesSync();
        bytes[10] ^= 0xff;
        quelle.writeAsBytesSync(bytes);
        await sicherung.jetzt();
        expect((await sicherung.stand())['ok'], isFalse);
        expect(datei.readAsBytesSync(), vorher);
        expect(File('${kopie(id).path}/angaben.enc').existsSync(), isTrue);
      },
    );

    test(
      'Wiederherstellung meldet fehlende Angaben einer fertigen Kopie',
      () async {
        final id = eintrag(gleich(1), 'kammer.jpg', 48);
        await sicherung.jetzt();
        File('${kopie(id).path}/angaben.enc').deleteSync();
        final (restore, anzahl) = await wiederherstellen();
        expect(anzahl, 2);
        expect(restore.erfolgreich, isFalse);
        expect(restore.fehler, 1);
        await sicherung.jetzt();
        expect((await sicherung.stand())['ok'], isTrue);
      },
    );

    test(
      'abgebrochene Kopie ohne Abschlussvermerk ist bei der Wiederherstellung kein Fehler',
      () async {
        final id = eintrag(gleich(1), 'kammer.jpg', 48);
        await sicherung.jetzt();
        File('${kopie(id).path}/gesichert').deleteSync();
        File('${kopie(id).path}/angaben.enc').deleteSync();
        final (restore, anzahl) = await wiederherstellen();
        expect(anzahl, 2);
        expect(restore.erfolgreich, isTrue);
      },
    );

    test('Wiederherstellung meldet abgewiesenen Kammerimport', () async {
      final id = eintrag(gleich(1), 'kammer.jpg', 48);
      await sicherung.jetzt();
      final wurzel = sicherungVon(erika).path;
      final h = jsonDecode(File('$wurzel/vault.key').readAsStringSync()) as Map;
      final key = await VaultCrypto.unwrapMasterKey(
        passphrase,
        kdfSalt: base64Decode(h['kdfSalt'] as String),
        nonce: base64Decode(h['nonce'] as String),
        wrapped: base64Decode(h['wrapped'] as String),
      );
      final angaben = File('${kammer.path}/$id/angaben.json');
      final falsch = jsonDecode(angaben.readAsStringSync()) as Map;
      falsch['sha256'] = List.filled(64, '0').join();
      final kopieMitFalscherSumme = File('${ordner.path}/angaben.json')
        ..writeAsStringSync(jsonEncode(falsch));
      await VaultCrypto.encryptFile(
        kopieMitFalscherSumme,
        File('${kopie(id).path}/angaben.enc'),
        key,
      );
      final (restore, anzahl) = await wiederherstellen();
      expect(anzahl, 2);
      expect(restore.erfolgreich, isFalse);
      expect(restore.fehler, 1);
    });

    test(
      'Kontostand behält Erfolgszeit bei gescheiterter Kammersicherung',
      () async {
        await sicherung.jetzt();
        final db = (await bibliotheken.fuer(erika.id)).bibliothek.db;
        final vorher = (await db.backupSettingsRow())!.lastAutoBackupAt;
        expect(vorher, isNotNull);
        jetzt = jetzt.add(const Duration(days: 1));
        final id = eintrag(gleich(1), 'kammer.jpg', 48);
        final quelle = File('${kammer.path}/$id/kammer.jpg');
        final bytes = quelle.readAsBytesSync();
        quelle.deleteSync();
        await sicherung.jetzt();
        expect((await sicherung.stand())['ok'], isFalse);
        expect((await db.backupSettingsRow())!.lastAutoBackupAt, vorher);
        quelle.writeAsBytesSync(bytes);
        await sicherung.jetzt();
        expect((await sicherung.stand())['ok'], isTrue);
        expect((await db.backupSettingsRow())!.lastAutoBackupAt, jetzt);
      },
    );

    test('verschlüsselt, ohne Namen, und nur einmal', () async {
      eintrag(gleich(1), 'IMG_GEHEIM.jpg', 40);
      await sicherung.jetzt();
      final dort = kopie(gleich(1));
      final dateien = dort.listSync().map((e) => e.path.split('/').last);
      expect(
        dateien,
        unorderedEquals(['datei.enc', 'angaben.enc', 'gesichert']),
      );
      // Der Vermerk trägt nur den Zeitpunkt der Sicherung (#388).
      expect(
        DateTime.tryParse(File('${dort.path}/gesichert').readAsStringSync()),
        isNotNull,
      );
      expect(
        latin1.decode(File('${dort.path}/angaben.enc').readAsBytesSync()),
        isNot(contains('IMG_GEHEIM')),
      );
      final zeit = File('${dort.path}/datei.enc').lastModifiedSync();
      await sicherung.jetzt();
      expect(File('${dort.path}/datei.enc').lastModifiedSync(), zeit);
      final konto = ((await sicherung.stand())['konten'] as List).single as Map;
      expect(konto['kammer'], 1);
      expect(konto['kammerNeu'], 0);
    });

    test('ein abgebrochener Upload wird nicht gesichert', () async {
      Directory('${kammer.path}/${gleich(2)}').createSync(recursive: true);
      await sicherung.jetzt();
      expect(kopie(gleich(2)).existsSync(), isFalse);
      expect((await sicherung.stand())['ok'], isTrue);
    });

    test('ein Eintrag ohne Datei macht den Lauf zum Fehler', () async {
      eintrag(gleich(3), 'weg.jpg', 60);
      File('${kammer.path}/${gleich(3)}/weg.jpg').deleteSync();
      await sicherung.jetzt();
      expect((await sicherung.stand())['ok'], isFalse);
      expect(
        File('${kopie(gleich(3)).path}/angaben.enc').existsSync(),
        isFalse,
      );
    });

    test('die Kopie bleibt noch sieben Tage, dann geht sie', () async {
      eintrag(gleich(4), 'bleibt.jpg', 80);
      await sicherung.jetzt();
      Directory('${kammer.path}/${gleich(4)}').deleteSync(recursive: true);
      await sicherung.jetzt();
      jetzt = jetzt.add(const Duration(days: 6));
      await sicherung.jetzt();
      expect(kopie(gleich(4)).existsSync(), isTrue);
      jetzt = jetzt.add(const Duration(days: 2));
      await sicherung.jetzt();
      expect(kopie(gleich(4)).existsSync(), isFalse);
      // Die Fotos der Bibliothek bleiben davon unberührt.
      expect(verschluesselteDateien(), 2);
    });

    test('kommt der Eintrag zurück, beginnt die Frist neu', () async {
      eintrag(gleich(5), 'zurueck.jpg', 100);
      await sicherung.jetzt();
      final platz = Directory('${kammer.path}/${gleich(5)}');
      final versteck = Directory('${ordner.path}/versteck');
      platz.renameSync(versteck.path);
      await sicherung.jetzt();
      expect(File('${kopie(gleich(5)).path}/.weg-seit').existsSync(), isTrue);
      versteck.renameSync(platz.path);
      await sicherung.jetzt();
      expect(File('${kopie(gleich(5)).path}/.weg-seit').existsSync(), isFalse);
    });

    test('kommt beim Wiederherstellen in ein eigenes Album', () async {
      eintrag(gleich(6), 'aus_der_kammer.jpg', 150);
      await sicherung.jetzt();

      final ziel = Directory('${ordner.path}/zurueck')..createSync();
      final db = await AppDatabase.open(ziel);
      addTearDown(db.close);
      final pfade = await StoragePaths.oeffne(
        Directory('${ziel.path}/library'),
      );
      await BackupService(db, pfade)
          .restoreFromBackup(
            sicherungVon(erika).path,
            ImportService(db, pfade),
            passphrase: passphrase,
          )
          .drain<void>();
      final aufnahmen = await db.select(db.assets).get();
      expect(aufnahmen, hasLength(3));
      final album = (await db.select(db.albums).get()).single;
      expect(album.name, 'Fotokammer (wiederhergestellt)');
      expect(
        (await db.select(db.tags).get()).map((t) => t.name),
        contains('Kammerwort'),
      );
      final darin = await db.select(db.albumAssets).get();
      expect(
        aufnahmen
            .firstWhere((a) => a.id == darin.single.assetId)
            .originalFileName,
        'aus_der_kammer.jpg',
      );
    });
  });

  test('die Schnittstelle nur für Verwalter', () async {
    final max = await konten.legeAn('max', 'noch ein passwort');
    final api = baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      sicherung: sicherung,
    );
    Future<Response> frag(String m, String pfad, Konto k, [Object? j]) async =>
        api(
          Request(
            m,
            Uri.parse('http://server/api/v1/$pfad'),
            headers: {
              'authorization':
                  'Bearer ${konten.meldeAn(k.id, 'Rechner', 'x').token}',
            },
            body: j == null ? null : jsonEncode(j),
          ),
        );
    expect((await frag('GET', 'sicherung', max)).statusCode, 403);
    expect(
      (await frag('POST', 'sicherung/einrichten', max, {
        'passphrase': passphrase,
      })).statusCode,
      403,
    );
    final stand = await frag('GET', 'sicherung', erika);
    expect(
      (jsonDecode(await stand.readAsString()) as Map)['stufe'],
      'nichtEingerichtet',
    );
    // Ein kaputter Körper endete als FormatException in einer 500.
    final kaputt = await api(
      Request(
        'POST',
        Uri.parse('http://server/api/v1/sicherung/einrichten'),
        headers: {
          'authorization':
              'Bearer ${konten.meldeAn(erika.id, 'Rechner', 'x').token}',
        },
        body: '{"passphrase": ',
      ),
    );
    expect(kaputt.statusCode, 400);
    final r = await frag('POST', 'sicherung/einrichten', erika, {
      'passphrase': passphrase,
    });
    expect(r.statusCode, 200);
    await sicherung.jetzt();
    expect(
      (await frag('POST', 'sicherung/einrichten', erika, {
        'passphrase': passphrase,
      })).statusCode,
      409,
    );
    expect((await frag('POST', 'sicherung/jetzt', erika)).statusCode, 202);
    await sicherung.jetzt();
  });
}

/// Sichert wie immer, meldet aber, dass kein Original ins Prüfbudget der
/// Wiederherstellungsprobe passte – das gäbe sonst erst eine Datei über
/// 128 MB.
class _OhneStichprobe extends BackupService {
  _OhneStichprobe(super.db, super.pfade);

  @override
  Stream<BackupProgress> performAutoBackup(
    String destinationRootPath,
    SecretKey encryptionKey, {
    int maxBytesPerRun = 0,
    bool markieren = true,
  }) async* {
    await for (final f in super.performAutoBackup(
      destinationRootPath,
      encryptionKey,
      maxBytesPerRun: maxBytesPerRun,
      markieren: markieren,
    )) {
      final probe = f.wiederherstellungsprobe;
      yield probe == null
          ? f
          : BackupProgress(
              f.done,
              f.total,
              wiederherstellungsprobe: BackupProbeErgebnis(
                am: probe.am,
                erfolgreich: false,
                originale: 0,
                gesamt: probe.gesamt,
                datenbank: false,
                letzterErfolg: probe.letzterErfolg,
                fehler: 'pv_probe_stichprobe_zu_gross',
                position: probe.position,
              ),
            );
    }
  }
}

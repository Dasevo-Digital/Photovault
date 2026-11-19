import 'dart:io';
import 'package:kern/db/database.dart';
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Geschuetzte API lehnt fehlende Anmeldung vor dem Puffern des Inhalts ab',
    () async {
      final temp = await Directory.systemTemp.createTemp('pv_audit_http_');
      final sdb = Serverdatenbank.imSpeicher();
      final konten = Kontodienst(
        sdb,
        Tresorschluessel(List.filled(32, 3)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
        totpPflicht: false,
      );
      final libs = Bibliotheken(
        wurzel: Directory('${temp.path}/bibliotheken'),
        eingang: Directory('${temp.path}/eingang'),
      );
      addTearDown(() async {
        await libs.schliesseAlle();
        sdb.schliesse();
        await temp.delete(recursive: true);
      });
      var gelesen = 0;
      Stream<List<int>> inhalt() async* {
        for (var i = 0; i < 32; i++) {
          gelesen += 4096;
          yield List.filled(4096, 32);
        }
      }

      final response = await baueApi(konten: konten, bibliotheken: libs)(
        Request(
          'POST',
          Uri.parse('http://server/api/v1/befehle'),
          body: inhalt(),
        ),
      );
      expect(response.statusCode, 401);
      expect(gelesen, 0);
    },
  );

  test(
    'Die 8-KiB-Grenze fuer Vorschlaege greift bereits beim Lesen des Requeststroms',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'pv_audit_beschriftung_',
      );
      final sdb = Serverdatenbank.imSpeicher();
      final konten = Kontodienst(
        sdb,
        Tresorschluessel(List.filled(32, 3)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
        totpPflicht: false,
      );
      final libs = Bibliotheken(
        wurzel: Directory('${temp.path}/bibliotheken'),
        eingang: Directory('${temp.path}/eingang'),
      );
      addTearDown(() async {
        await libs.schliesseAlle();
        sdb.schliesse();
        await temp.delete(recursive: true);
      });
      final konto = await konten.legeAn(
        'testkonto',
        'synthetisches langes Passwort',
      );
      final token = konten.meldeAn(konto.id, 'Probe', 'x').token;
      final db = (await libs.fuer(konto.id)).bibliothek.db;
      await db.fuehreAus(AlbumAnlegen('album', 'Probealbum', DateTime(2026)));
      var gelesen = 0;
      Stream<List<int>> inhalt() async* {
        for (var i = 0; i < 32; i++) {
          gelesen += 4096;
          yield List.filled(4096, 32);
        }
      }

      final response = await baueApi(konten: konten, bibliotheken: libs)(
        Request(
          'POST',
          Uri.parse('http://server/api/v1/alben/album/beschriftungen'),
          headers: {'authorization': 'Bearer $token'},
          body: inhalt(),
        ),
      );
      expect(response.statusCode, 413);
      expect(gelesen, lessThanOrEqualTo(16384));
    },
  );
}

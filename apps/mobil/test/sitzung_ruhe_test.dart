import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/sitzung.dart';

import 'hilfen/testserver.dart';

/// Im Hintergrund ruhen Abgleich und 15-Minuten-Uhr (#437); zurück in der
/// App kommt gleich, was inzwischen geschah. Gegen einen echten
/// Server-Prozess, darum kein Widget-Test (siehe sitzung_test.dart).
void main() {
  late Testserver server;
  late Sitzung sitzung;
  late Serververbindung rechner;

  Future<void> bis(Future<bool> Function() bedingung, String was) async {
    for (var i = 0; i < 150; i++) {
      if (await bedingung()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Nicht eingetreten: $was');
  }

  setUpAll(() async {
    server = await Testserver.starte('pv_mobil_ruhe_');
    rechner = await server.verbinde('Rechner');
    await Testserver.hochladen(rechner, server.jpeg('strand.jpg', 30));
    sitzung = Sitzung(
      ordner: () async => Directory(p.join(server.ordner.path, 'telefon')),
    );
    await sitzung.verbinde(
      server: server.adresse,
      konto: 'erika',
      geraet: 'Telefon',
      token: await server.anmelden('Telefon'),
    );
  });

  tearDownAll(() async {
    rechner.schliesse();
    await sitzung.beende();
    await server.beende();
  });

  test(
    'im Hintergrund ruhen Abgleich und Uhr, zurück kommt alles gleich',
    () async {
      expect(sitzung.zustand, Sitzungszustand.bereit);
      expect(sitzung.uhrLaeuft, isTrue);
      await bis(
        () async => sitzung.abgleichszustand?.erreichbar ?? false,
        'erreichbar',
      );
      final id = (await sitzung.db.alleRasterzeilen()).single.id;

      sitzung.ruheImHintergrund();
      expect(sitzung.abgleich!.ruht, isTrue);
      expect(sitzung.uhrLaeuft, isFalse);

      // Am Rechner wird das Foto Favorit; das Telefon fragt nicht nach.
      await rechner.schicke('api/v1/befehle', {
        'befehle': [
          {
            'kennung': 'rechner-favorit',
            ...FavoritSetzen([id], true).alsJson(),
          },
        ],
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      expect((await sitzung.db.assetById(id))!.isFavorite, isFalse);

      // Ein eigener Befehl geht trotzdem zum Server.
      await sitzung.db.fuehreAus(BewertungSetzen([id], 4));
      await bis(
        () async => (await rechner.hole('api/v1/aufnahmen/$id'))['rating'] == 4,
        'Bewertung auf dem Server',
      );

      sitzung.weckeInDerApp();
      expect(sitzung.abgleich!.ruht, isFalse);
      expect(sitzung.uhrLaeuft, isTrue);
      await bis(
        () async => (await sitzung.db.assetById(id))!.isFavorite,
        'Favorit auf dem Telefon',
      );
    },
  );
}

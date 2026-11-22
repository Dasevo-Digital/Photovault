import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/befehlsbasis.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// **Was eine verbundene Kopie beim Aufstufen noch nicht hinausgeschickt
/// hat (#466).** Die Befehle liegen verschlüsselt in der Warteschlange und
/// tragen die Temperatur in der früheren Bedeutung. Ohne Umrechnung schickte
/// die Kopie sie später an einen Server, der die Zahl schon mit der neuen
/// Rechnung zeigt – und wendete sie bis dahin bei jedem Abholen selbst
/// wieder an.
void main() {
  late Directory temp;
  late File datei;
  late Serververbindung verbindung;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_wb_ausgang_');
    datei = File('${temp.path}/library.sqlite');
    verbindung = Serververbindung(
      Uri.parse('http://localhost/'),
      'synthetisch',
      client: MockClient((_) async => throw http.ClientException('weg')),
    );
  });
  tearDown(() async {
    verbindung.schliesse();
    await temp.delete(recursive: true);
  });

  Future<double?> temperaturIn(Map<String, Object?> befehl, String zeile) =>
      Future.value(
        (((befehl['werte'] as Map)[zeile] as Map)['temperature'] as num?)
            ?.toDouble(),
      );

  test(
    'offene Befehle und Fälle kommen umgerechnet heraus, genau einmal',
    () async {
      final vorher = AppDatabase(NativeDatabase(datei));
      await vorher.insertAsset(
        AssetsCompanion.insert(
          id: 'a',
          originalFileName: 'a.jpg',
          relativePath: 'originals/a.jpg',
          checksum: 'a' * 64,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
        ),
      );
      final alt = Abgleich(vorher, verbindung);
      await alt.richteEin();
      // Offline entwickelt, mit 4000 K in der früheren Bedeutung …
      await vorher.fuehreAus(
        EntwicklungSpeichern(
          'a',
          DevelopSettingsCompanion.insert(
            assetId: 'a',
            temperature: const Value(4000),
            tint: const Value(5),
            updatedAt: DateTime(2026, 11, 22),
          ),
          'developed/a.jpg',
        ),
      );
      // … und eine Vorgabe, die der Server schon als Konflikt abgelehnt hat.
      await vorher.fuehreAus(
        EntwicklungsvorgabeSpeichern(
          DevelopPresetsCompanion.insert(
            name: 'Kunstlicht',
            temperature: const Value(5200),
            erstelltAm: DateTime(2026, 11, 22),
          ),
        ),
      );
      await vorher.customStatement(
        'INSERT INTO pv_abgleichsfaelle (kennung, am, grund, inhalt) '
        "SELECT kennung, angelegt, 'pv_sync_konflikt', befehl FROM pv_ausgang "
        'WHERE nr = (SELECT max(nr) FROM pv_ausgang)',
      );
      await vorher.customStatement(
        'UPDATE pv_ausgang SET bestaetigt = 1, ok = 0 '
        'WHERE nr = (SELECT max(nr) FROM pv_ausgang)',
      );
      await alt.beende();
      await vorher.close();
      final roh = sqlite.sqlite3.open(datei.path);
      roh.execute('PRAGMA user_version = 101');
      roh.close();

      for (var lauf = 0; lauf < 2; lauf++) {
        final db = AppDatabase(NativeDatabase(datei));
        final a = Abgleich(db, verbindung);
        await a.richteEin();
        expect(
          (await db.developSettingsForAsset('a'))!.temperature,
          10562.5,
          reason: 'die Kopie selbst (Migration)',
        );
        final faelle = await a.faelle();
        final offen = faelle.singleWhere((f) => f.ausstehend);
        expect(offen.befehl['art'], 'entwicklungSpeichern');
        expect(await temperaturIn(offen.befehl, 'einstellungen'), 10562.5);
        expect(
          ((offen.befehl['werte'] as Map)['einstellungen'] as Map)['tint'],
          5,
        );
        // Das Gewollte in der Basis passt dazu, samt seiner Prüfsumme.
        final b = offen.basis.singleWhere(
          (b) => b.tabelle == 'develop_settings',
        );
        expect(b.gewollt!['temperature'], 10562.5);
        expect(b.nachher, Befehlsbasis.hash(b.gewollt, b.spalten));
        final spalte =
            jsonDecode(
                  (await db
                          .customSelect(
                            'SELECT basis FROM pv_ausgang WHERE bestaetigt IS NULL',
                          )
                          .getSingle())
                      .read<String>('basis'),
                )
                as List;
        expect(
          spalte.cast<Map>().singleWhere(
            (s) => s['t'] == 'develop_settings',
          )['nachher'],
          b.nachher,
        );

        final fall = faelle.singleWhere((f) => !f.ausstehend);
        expect(fall.befehl['art'], 'entwicklungsvorgabeSpeichern');
        expect(await temperaturIn(fall.befehl, 'vorgabe'), 8125.0);
        expect(
          await db
              .customSelect(
                "SELECT 1 FROM sqlite_master WHERE name = 'pv_weissabgleich_umkehr'",
              )
              .get(),
          isEmpty,
          reason:
              'die Marke ist fort, ein zweiter Start rechnet nichts mehr um',
        );
        await a.beende();
        await db.close();
      }
    },
  );
}

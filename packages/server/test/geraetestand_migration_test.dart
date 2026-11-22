import 'dart:io';
import 'package:photo_vault_server/src/konten/serverdatenbank.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    '11 auf 12 erhält Konten und Tokens und beginnt mit unbekannten Geräteständen',
    () {
      final temp = Directory.systemTemp.createTempSync('pv_device_schema_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/server.sqlite');
      final frisch = Serverdatenbank.oeffne(file);
      frisch.db.close();
      final alt = sqlite3.open(file.path);
      alt.execute(
        "INSERT INTO konten(id,name,passwort,angelegt) VALUES ('konto','probe','hash',0)",
      );
      alt.execute(
        "INSERT INTO geraete(id,konto,name,pruefwert,angelegt,zuletzt) VALUES ('geraet','konto','test','synthetischer-pruefwert',0,0)",
      );
      final geraete = alt
          .select('SELECT * FROM geraete')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final vorher = alt
          .select('SELECT * FROM konten')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      for (final feld in [
        'client_fassung',
        'client_schema',
        'client_plattform',
        'client_offen',
        'client_gemeldet',
        'client_abgleich',
      ]) {
        alt.execute('ALTER TABLE geraete DROP COLUMN $feld');
      }
      alt.execute('PRAGMA user_version=11');
      alt.close();
      final neu = Serverdatenbank.oeffne(file);
      addTearDown(neu.db.close);
      expect(
        neu.db.select('PRAGMA user_version').single.values.single,
        Serverdatenbank.schema,
      );
      expect(
        neu.db
            .select('SELECT * FROM konten')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        vorher,
      );
      final erhalten = Map<String, Object?>.from(
        neu.db.select('SELECT * FROM geraete').single,
      );
      for (final e in geraete.single.entries) {
        expect(erhalten[e.key], e.value);
      }
      expect(erhalten['client_schema'], isNull);
      expect(
        neu.db.select('PRAGMA table_info(geraete)').map((r) => r['name']),
        contains('client_abgleich'),
      );
      expect(
        neu.db.select('PRAGMA integrity_check').single.values.single,
        'ok',
      );
    },
  );

  // #426: Falsche Passwörter werden je Freigabe gezählt.
  test('12 auf 13: Freigaben bekommen einen Zähler, bleiben sonst gleich', () {
    final temp = Directory.systemTemp.createTempSync('pv_freigabe_schema_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/server.sqlite');
    Serverdatenbank.oeffne(file).db.close();
    final alt = sqlite3.open(file.path);
    alt.execute(
      "INSERT INTO konten(id,name,passwort,angelegt) VALUES ('konto','probe','hash',0)",
    );
    alt.execute(
      'INSERT INTO freigaben(id,konto,pruefwert,link,geheimnis,titel,angelegt) '
      "VALUES ('f','konto','p','l','g','Feier',0)",
    );
    alt.execute('ALTER TABLE freigaben DROP COLUMN fehlversuche');
    alt.execute('ALTER TABLE freigaben DROP COLUMN gesperrt_bis');
    alt.execute('PRAGMA user_version=12');
    alt.close();
    final neu = Serverdatenbank.oeffne(file);
    addTearDown(neu.db.close);
    expect(neu.db.select('PRAGMA user_version').single.values.single, 13);
    final f = neu.db.select('SELECT * FROM freigaben').single;
    expect(f['titel'], 'Feier');
    expect(f['fehlversuche'], 0);
    expect(f['gesperrt_bis'], isNull);
  });
}

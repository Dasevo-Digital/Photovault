import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/herkunft.dart';
import 'package:kern/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Schema 93: woher ein Ergebnis der Auswertung stammt (Issue #104).
void main() {
  test('die Modellfassung kommt aus dem Katalog, ohne die Datei zu lesen', () {
    expect(Ergebnisart.clip.modell, 'clip_image_encoder.onnx@fd6e1402a588');
    expect(
      Ergebnisart.texterkennung.modell.split(', '),
      hasLength(2),
      reason: 'Erkennung und Lesung',
    );
    for (final a in Ergebnisart.values) {
      expect(a.modell, isNot(contains('@?')), reason: '${a.name} im Katalog');
    }
  });

  test('der Beschleuniger je Art: einer, oder verschiedene mit „+“', () {
    final hier = Rechner.hier();
    expect(hier.geraet, startsWith('Rechner ('));
    expect(hier.beschleuniger(Ergebnisart.gesichter), 'CPU');

    final server = Rechner.server(
      (datei) => datei.startsWith('face_detection') ? 'CPU' : 'OpenVINO:GPU',
    );
    expect(server.geraet, startsWith('Server ('));
    expect(server.beschleuniger(Ergebnisart.clip), 'OpenVINO:GPU');
    expect(server.beschleuniger(Ergebnisart.gesichter), 'CPU+OpenVINO:GPU');
  });

  test(
    'ein Vermerk je Aufnahme und Art, ersetzt und mit ihr gelöscht',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Future<void> vermerke(String art, String beschleuniger) =>
          db.vermerkeHerkunft(
            'a1',
            art,
            modell: 'm',
            geraet: 'Server (Linux)',
            beschleuniger: beschleuniger,
          );
      await vermerke('clip', 'CPU');
      await vermerke('clip', 'OpenVINO:GPU');
      await vermerke('gesichter', 'CPU');
      final zeilen = await db.herkunftVon('a1');
      expect(
        {for (final z in zeilen) z.art: z.beschleuniger},
        {'clip': 'OpenVINO:GPU', 'gesichter': 'CPU'},
      );

      await db.deleteAssetRows(['a1']);
      expect(await db.herkunftVon('a1'), isEmpty);
    },
  );

  test('Migration 92 auf 93 legt die Tabelle an', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v92_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');

    final neu = AppDatabase(NativeDatabase(file));
    await neu.vermerkeHerkunft(
      'a1',
      'clip',
      modell: 'm',
      geraet: 'g',
      beschleuniger: 'CPU',
    );
    await neu.close();

    // Zurück auf den Stand von 92: die Tabelle weg.
    final alt = sqlite.sqlite3.open(file.path);
    alt
      ..execute('DROP TABLE ergebnisherkunft')
      ..execute('PRAGMA user_version = 92');
    alt.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.herkunftVon('a1'), isEmpty);
    await db.vermerkeHerkunft(
      'a1',
      'clip',
      modell: 'm',
      geraet: 'g',
      beschleuniger: 'CPU',
    );
    expect(await db.herkunftVon('a1'), hasLength(1));
  });
}

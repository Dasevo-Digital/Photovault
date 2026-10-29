import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../db/database.dart';
import 'verbindungsdatei.dart';

/// Ein Geräteschlüssel bleibt bei erneuter Anmeldung erhalten. In der
/// Bibliothek liegt nur seine zufällige Kennung, nicht der Schlüssel.
/// Die Apps stellen eine eigene Ablage im privaten App-Datenordner bereit.
class Fallschluessel {
  static Future<SecretKey> lade(AppDatabase db, Tokenablage ablage) =>
      db.transaction(() async {
        await db.customStatement(
          'CREATE TABLE IF NOT EXISTS pv_fallschluessel ('
          'id INTEGER PRIMARY KEY CHECK(id = 0), kennung TEXT NOT NULL)',
        );
        final vorhanden = await db
            .customSelect('SELECT kennung FROM pv_fallschluessel WHERE id = 0')
            .getSingleOrNull();
        if (vorhanden != null) {
          final wert = await ablage.lies(vorhanden.read<String>('kennung'));
          if (wert == null) throw const TokenablageFehler();
          final bytes = base64Decode(wert);
          if (bytes.length != 32) throw const TokenablageFehler();
          return SecretKey(bytes);
        }
        final zufall = Random.secure();
        final kennung = List.generate(
          24,
          (_) => zufall.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        final key = await AesGcm.with256bits().newSecretKey();
        if (!await ablage.schreibe(
          kennung,
          base64Encode(await key.extractBytes()),
        )) {
          throw const TokenablageFehler();
        }
        await db.customStatement(
          'INSERT INTO pv_fallschluessel (id, kennung) VALUES (0, ?)',
          [kennung],
        );
        return key;
      });
}

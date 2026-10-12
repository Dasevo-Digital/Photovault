import 'dart:io';

import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Eine Bibliothek auf dem Server: dieselbe Ablage wie in der App
/// (`library.sqlite` und darunter `library/`), nur ohne Oberfläche.
class Bibliothek {
  Bibliothek._(this.ordner, this.db, this.pfade, this.importe);

  /// Öffnet die Bibliothek in [ordner] oder legt sie an.
  ///
  /// Anders als die App mit Write-Ahead-Log: Auf dem Server lesen mehrere
  /// Anfragen, während eine schreibt, und im WAL warten Lesende nicht auf
  /// den Schreiber.
  static Future<Bibliothek> oeffne(
    Directory ordner, {
    Bildwerkzeuge bildwerkzeuge = const WerkzeugBildwerkzeuge(),
  }) async {
    await ordner.create(recursive: true);
    final db = AppDatabase(
      AppDatabase.mitSperrwartezeit(
        NativeDatabase.createInBackground(
          File(p.join(ordner.path, 'library.sqlite')),
          setup: (verbindung) {
            AppDatabase.bereiteVerbindungVor(verbindung);
            verbindung.execute('PRAGMA journal_mode = WAL');
          },
        ),
      ),
    );
    final pfade = await StoragePaths.oeffne(
      Directory(p.join(ordner.path, 'library')),
    );
    return Bibliothek._(
      ordner,
      db,
      pfade,
      ImportService(db, pfade, bildwerkzeuge: bildwerkzeuge),
    );
  }

  final Directory ordner;
  final AppDatabase db;
  final StoragePaths pfade;
  final ImportService importe;

  /// Die Kennung der Aufnahme mit dieser Prüfsumme – für Dubletten, bei
  /// denen der Import nur „schon da“ meldet.
  Future<String?> kennungFuer(String pruefsumme) async =>
      (await (db.select(db.assets)
                ..where((t) => t.checksum.equals(pruefsumme))
                ..limit(1))
              .getSingleOrNull())
          ?.id;

  Future<void> schliesse() => db.close();
}

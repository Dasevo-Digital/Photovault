import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'tus.dart';
import 'verbindung.dart';

/// Wie weit der Umzug ist.
class Umzugsstand {
  const Umzugsstand(
    this.erledigt,
    this.gesamt, {
    this.datei,
    this.fertig = false,
  });

  /// Bytes.
  final int erledigt;
  final int gesamt;
  final String? datei;
  final bool fertig;
}

/// Zieht die Bibliothek dieses Rechners auf den Server (siehe dort
/// `Umzugsdienst`): erst alle Dateien mit Pfad und Prüfsumme, zuletzt die
/// Datenbank. Was der Server schon hat (ein unterbrochener Umzug), lädt er
/// nicht noch einmal.
///
/// Während des Umzugs soll sich an der Bibliothek nichts ändern: Die
/// Datenbank wird erst am Ende abgezogen, eine Datei, die danach noch
/// dazukäme, fehlte auf dem Server.
class Umzug {
  Umzug(this.verbindung, this.db, this.wurzel, {TusHochladen? tus})
    : tus = tus ?? TusHochladen(verbindung);

  final Serververbindung verbindung;
  final AppDatabase db;

  /// Der Bibliotheksordner (`StoragePaths.root`).
  final Directory wurzel;
  final TusHochladen tus;

  Stream<Umzugsstand> laufe() async* {
    await verbindung.schicke('api/v1/umzug/beginnen', const {});
    final stand = await verbindung.hole('api/v1/umzug/stand');
    final vorhanden = (stand['dateien']! as Map).cast<String, int>();

    final dateien = <(File, String, int)>[];
    await for (final e in wurzel.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.posix.joinAll(
        p.split(p.relative(e.path, from: wurzel.path)),
      );
      // Versteckte Dateien (Sperren, Systemdateien) und halbe Downloads
      // gehören nicht zur Bibliothek.
      if (p.split(rel).any((t) => t.startsWith('.')) || rel.endsWith('.teil')) {
        continue;
      }
      dateien.add((e, rel, await e.length()));
    }
    final gesamt = dateien.fold<int>(0, (s, d) => s + d.$3);
    var erledigt = 0;
    yield Umzugsstand(0, gesamt);
    for (final (datei, rel, groesse) in dateien) {
      if (vorhanden[rel] == groesse) {
        erledigt += groesse;
        continue;
      }
      final summe = (await sha256.bind(datei.openRead()).first).toString();
      final kopf = await tus.lade(datei, 'api/v1/umzug/hochladen', {
        'pfad': rel,
        'sha256': summe,
      });
      if (kopf['pv-ausgang'] != 'imported') {
        throw StateError('Umzug von $rel: ${kopf['pv-ausgang']}');
      }
      erledigt += groesse;
      yield Umzugsstand(erledigt, gesamt, datei: rel);
    }

    // Zuletzt die Datenbank, als Abzug in einem Zug.
    final tmp = await Directory.systemTemp.createTemp('pv_umzug_');
    try {
      final abzug = File(p.join(tmp.path, 'library.sqlite'));
      await db.customStatement('VACUUM INTO ?', [abzug.path]);
      final summe = (await sha256.bind(abzug.openRead()).first).toString();
      final kopf = await tus.lade(abzug, 'api/v1/umzug/hochladen', {
        'pfad': 'library.sqlite',
        'art': 'datenbank',
        'sha256': summe,
      });
      if (kopf['pv-ausgang'] != 'imported') {
        throw StateError('Umzug der Datenbank: ${kopf['pv-ausgang']}');
      }
    } finally {
      await tmp.delete(recursive: true);
    }
    await verbindung.schicke('api/v1/umzug/abschliessen', const {});
    yield Umzugsstand(gesamt, gesamt, fertig: true);
  }
}

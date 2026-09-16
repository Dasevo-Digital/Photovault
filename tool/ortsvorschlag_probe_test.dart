// ignore_for_file: avoid_print

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/ortsvorschlag.dart';

/// Misst die Ortsvorschlaege an einer **Kopie** einer echten Bibliothek.
///
/// Nie auf das Original ansetzen: Der Lauf oeffnet die Datenbank mit dem
/// Quelltext von jetzt und wandert sie auf das aktuelle Schema.
///
///     PV_DB=/pfad/zur/kopie.sqlite \
///     flutter test tool/ortsvorschlag_probe_test.dart
void main() {
  test('Ortsvorschlaege an einer echten Bibliothek', () async {
    final dbPfad = Platform.environment['PV_DB'];
    if (dbPfad == null) {
      markTestSkipped('PV_DB noetig');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(dbPfad)));
    final daten = await db.ortsvorschlagsdaten();
    print('ohne Ort ${daten.ohneOrt.length} · verortet ${daten.verortet.length}');

    for (final regeln in [
      const Ortsvorschlagsregeln(fenster: Duration(minutes: 30), spanneKm: 2),
      const Ortsvorschlagsregeln(fenster: Duration(hours: 2), spanneKm: 25),
      const Ortsvorschlagsregeln(fenster: Duration(hours: 4), spanneKm: 25),
    ]) {
      final uhr = Stopwatch()..start();
      final v = ortsvorschlaege(daten.ohneOrt, daten.verortet, regeln: regeln);
      uhr.stop();
      // Wie viele Kandidaten haette es ohne die Einigkeitspruefung gegeben?
      final ohnePruefung = ortsvorschlaege(daten.ohneOrt, daten.verortet,
              regeln: Ortsvorschlagsregeln(
                  fenster: regeln.fenster, spanneKm: 40075))
          .length;
      print('±${regeln.fenster.inMinutes} min / ${regeln.spanneKm} km: '
          '${v.length} von $ohnePruefung Kandidaten '
          '(${ohnePruefung - v.length} uneinig) in ${uhr.elapsedMilliseconds} ms');
    }

    final v = ortsvorschlaege(daten.ohneOrt, daten.verortet);
    final zeiten = {for (final o in daten.ohneOrt) o.id: o.wann};
    final buendel = buendleOrtsvorschlaege(v, zeiten);
    print('\n${buendel.length} Buendel fuer ${v.length} Aufnahmen');
    for (final b in buendel.take(12)) {
      print('  ${b.tag.toIso8601String().substring(0, 10)}  '
          '${b.vorschlaege.length.toString().padLeft(4)} Aufnahmen  '
          '${b.breite.toStringAsFixed(3)}/${b.laenge.toStringAsFixed(3)}  '
          'hoechstens ${b.groessterAbstand.inMinutes} min entfernt');
    }
    final gross = buendel.where((b) => b.vorschlaege.length >= 10).length;
    print('  ... $gross Buendel mit 10 und mehr Aufnahmen');

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

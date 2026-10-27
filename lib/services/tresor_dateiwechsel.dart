import 'dart:convert';
import 'dart:io';

import 'package:kern/services/storage_paths.dart';

/// Ein wiederaufnehmbarer Wechsel aller Dateien einer Aufnahme samt ihrem
/// Datenbankstand. Das Journal enthält nur Kennungen und relative Pfade.
///
/// Beim Sperren sind alle neuen Dateien vorbereitet, bevor die erste alte
/// ersetzt wird. Ein unterbrochenes Übernehmen lässt sich ohne Schlüssel
/// fertigstellen. Beim Entsperren bleiben die alten, verschlüsselten Dateien
/// bis zur Datenbanktransaktion erhalten; ein Abbruch nimmt den Wechsel zurück.
class TresorDateiwechsel {
  TresorDateiwechsel(this.paths);

  final StoragePaths paths;
  File get _journal => paths.absolute('vault_dateiwechsel.json');

  File zwischen(String pfad) => paths.absolute('$pfad.vaulttmp');
  File _vorher(String pfad) => paths.absolute('$pfad.vaultalt');

  Future<void> _schreibe(Map<String, Object?> plan) async {
    final teil = File('${_journal.path}.neu');
    await teil.writeAsString(jsonEncode(plan), flush: true);
    await teil.rename(_journal.path);
  }

  Future<void> _entferneDatei(File datei) async {
    if (await FileSystemEntity.type(datei.path, followLinks: false) ==
        FileSystemEntityType.file) {
      await datei.delete();
    }
  }

  Future<void> _raeumeAuf(List<String> dateien, List<String> entfernen) async {
    for (final pfad in dateien) {
      await _entferneDatei(zwischen(pfad));
      await _entferneDatei(_vorher(pfad));
    }
    for (final pfad in entfernen) {
      await _entferneDatei(paths.absolute(pfad));
    }
    await _entferneDatei(_journal);
    await _entferneDatei(File('${_journal.path}.neu'));
  }

  Future<void> _uebernehme(List<String> dateien, bool sperren) async {
    for (final pfad in dateien) {
      final teil = zwischen(pfad);
      final ziel = paths.absolute(pfad);
      if (!await teil.exists()) {
        if (!await ziel.exists()) {
          throw FileSystemException('pv_vault_datei_fehlt', pfad);
        }
        continue; // Das Umbenennen war schon vor dem Abbruch abgeschlossen.
      }
      if (!sperren && !await _vorher(pfad).exists()) {
        await ziel.rename(_vorher(pfad).path);
      }
      await teil.rename(ziel.path);
    }
  }

  Future<void> _zurueck(List<String> dateien) async {
    for (final pfad in dateien.reversed) {
      final vorher = _vorher(pfad);
      if (await vorher.exists()) await vorher.rename(paths.absolute(pfad).path);
    }
    await _raeumeAuf(dateien, const []);
  }

  /// Vor dem Öffnen der Bibliothek aufrufen, bevor Auswertungen beginnen.
  /// Ein Entsperren ohne abgeschlossene Datenbanktransaktion wird rückgängig
  /// gemacht; ein Sperren mit vorbereiteten Dateien wird fertiggestellt.
  Future<void> erhole({
    required Future<bool> Function(List<String>, bool) abgeschlossen,
    required Future<void> Function(List<String>, bool) datenbank,
  }) async {
    if (!await _journal.exists()) return;
    final plan = jsonDecode(await _journal.readAsString()) as Map;
    if (plan['fassung'] != 1 ||
        plan['sperren'] is! bool ||
        !const {'vorbereiten', 'uebernehmen'}.contains(plan['phase'])) {
      throw const FormatException('pv_vault_journal');
    }
    final ids = (plan['ids'] as List).cast<String>();
    final dateien = (plan['dateien'] as List).cast<String>();
    final entfernen = (plan['entfernen'] as List).cast<String>();
    // Alles prüfen, bevor irgendein Journalpfad zum Schreiben benutzt wird.
    for (final pfad in [...dateien, ...entfernen]) {
      paths.absolute(pfad);
    }
    final sperren = plan['sperren'] as bool;
    if (plan['phase'] == 'vorbereiten') {
      await _raeumeAuf(dateien, const []);
    } else if (await abgeschlossen(ids, sperren)) {
      await _raeumeAuf(dateien, entfernen);
    } else if (sperren) {
      await _uebernehme(dateien, true);
      await datenbank(ids, true);
      await _raeumeAuf(dateien, entfernen);
    } else {
      await _zurueck(dateien);
    }
  }

  Future<void> fuehreAus({
    required List<String> ids,
    required bool sperren,
    required List<String> dateien,
    required List<String> entfernen,
    required Future<void> Function() vorbereiten,
    required Future<void> Function() datenbank,
  }) async {
    if (await _journal.exists()) throw StateError('pv_vault_wechsel_offen');
    final plan = <String, Object?>{
      'fassung': 1,
      'ids': ids,
      'sperren': sperren,
      'dateien': dateien,
      'entfernen': entfernen,
      'phase': 'vorbereiten',
    };
    await _schreibe(plan);
    try {
      await vorbereiten();
      for (final pfad in dateien) {
        if (!await zwischen(pfad).exists()) {
          throw FileSystemException('pv_vault_vorbereitung_fehlt', pfad);
        }
      }
    } catch (_) {
      await _raeumeAuf(dateien, const []);
      rethrow;
    }
    await _schreibe({...plan, 'phase': 'uebernehmen'});
    try {
      await _uebernehme(dateien, sperren);
      await datenbank();
    } catch (_) {
      // Beim Sperren bleibt ein vollständiger, schlüssellos fortsetzbarer
      // Plan. Beim Entsperren lässt sich der alte Zustand wiederherstellen.
      if (!sperren) await _zurueck(dateien);
      rethrow;
    }
    await _raeumeAuf(dateien, entfernen);
  }
}

import 'dart:async';
import 'package:path/path.dart' as p;
import '../auswertung/fortschritt.dart';
import '../db/database.dart';
import 'import_plan.dart';
import 'import_service.dart';

/// Der lokale Importablauf kennt seine Dienste, aber keine Widgets und
/// keinen veränderlichen globalen Bibliothekszustand.
class ImportKoordinator {
  const ImportKoordinator({
    required this.db,
    required this.importe,
    required this.nachbearbeiten,
    required this.starteAnalyse,
  });
  final AppDatabase db;
  final ImportService importe;
  final Future<void> Function(String id, {bool regelnAnwenden}) nachbearbeiten;
  final Future<void> Function() starteAnalyse;

  Stream<ImportProgress> importiere(
    List<String> pfade, {
    ImportPlan? plan,
  }) async* {
    final pruefung = ImportPlanDienst(db, importe);
    final pruefsummen = plan?.pruefsummen;
    if (pruefsummen != null && pfade.any((p) => !pruefsummen.containsKey(p))) {
      throw const FormatException('pv_import_auswahl');
    }
    var done = 0;
    yield ImportProgress(0, pfade.length);
    for (final pfad in pfade) {
      if (plan != null &&
          plan.regelstand != await pruefung.aktuellerRegelstand()) {
        throw const FormatException('pv_import_regeln_geaendert');
      }
      final eintrag = plan?.eintraege.singleWhere((e) => e.pfad == pfad);
      final result = await importe.importFile(
        pfad,
        erwartetePruefsumme: pruefsummen?[pfad],
        erwarteteAngaben: eintrag?.angaben,
        beiEintrag: plan == null
            ? null
            : (id) => pruefung.uebernehme(plan, eintrag!, id),
      );
      if (result.outcome == ImportOutcome.imported && result.assetId != null) {
        await nachbearbeiten(result.assetId!, regelnAnwenden: plan == null);
      }
      yield ImportProgress(
        ++done,
        pfade.length,
        currentFile: p.basename(pfad),
        assetId: result.outcome == ImportOutcome.imported
            ? result.assetId
            : null,
        duplikat: result.outcome == ImportOutcome.duplicateSkipped,
        gescheitert: result.outcome == ImportOutcome.failed,
      );
    }
    if (await db.autoAnalyzeAfterImportEnabled()) unawaited(starteAnalyse());
  }
}

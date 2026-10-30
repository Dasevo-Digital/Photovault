import 'dart:isolate';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'duplicate_selection.dart';
import 'embedding_similarity.dart';

/// Eine Gruppe ähnlicher Aufnahmen und was das Aufräumen mit ihr täte.
typedef Duplikatgruppe = ({
  List<AssetData> aufnahmen,

  /// Das Foto, das die Regeln aus duplicate_selection.dart behalten.
  AssetData behalten,

  /// Was beim Aufräumen in den Papierkorb ginge – leer, wenn mehrere
  /// ausgezeichnet sind (dann nur von Hand).
  List<AssetData> loeschbar,
});

typedef Duplikatergebnis = ({
  int einbettungen,
  int ausnahmen,
  double schwelle,
  List<Duplikatgruppe> gruppen,
});

/// Die Duplikatsuche des Rechners – für Browser (über den Server) und
/// Telefon dieselbe: Bildeinbettungen ab [schwelle] Ähnlichkeit, ohne die
/// als „keine Duplikate“ markierten Paare, in einem eigenen Isolate.
///
/// **Varianten sind keine Duplikate (#249).** Wer ein RAW neben sein JPEG
/// stapelt oder ein Foto bearbeitet (das Original bleibt dann als Variante
/// liegen, #248), hat beide ausdrücklich behalten. Bis 3.49.6 bot die Suche
/// sie trotzdem zum Aufräumen an, und „alle aufräumen“ legte eine Fassung
/// jedes solchen Stapels in den Papierkorb. Jetzt sucht ein Stapel nur mit
/// seiner Hauptversion mit: Ein Ausnahmepaar genügte nicht, weil ein
/// drittes ähnliches Foto beide Varianten wieder in eine Gruppe zöge.
Future<Duplikatergebnis> sucheDuplikate(AppDatabase db, double schwelle) async {
  final alle = await db.einbettungenImSpeicher();
  final verdeckt = await _verdeckteVarianten(db);
  // Die Karte gehört allen Aufrufern – gefiltert wird eine Abschrift.
  final einbettungen = verdeckt.isEmpty
      ? alle
      : (Map.of(alle)..removeWhere((id, _) => verdeckt.contains(id)));
  final ausnahmen = await db.duplikatAusnahmeSchluessel();
  final ids = einbettungen.length < 2
      ? const <List<String>>[]
      : await Isolate.run(
          () => findDuplicateGroups(
            DuplicateSearchParams(einbettungen, schwelle, ausnahmen: ausnahmen),
          ),
        );
  final zeilen = await db.assetsByIds([for (final g in ids) ...g]);
  final nachId = {for (final a in zeilen) a.id: a};
  return (
    einbettungen: einbettungen.length,
    ausnahmen: ausnahmen.length,
    schwelle: schwelle,
    gruppen: [
      for (final g in ids)
        if ([for (final id in g) ?nachId[id]] case final aufnahmen
            when aufnahmen.length >= 2)
          (
            aufnahmen: aufnahmen,
            behalten: besterDerGruppe(aufnahmen),
            loeschbar: zuLoeschendeDerGruppe(aufnahmen),
          ),
    ],
  );
}

/// Die Mitglieder von Variantenstapeln, die nicht die Hauptversion sind.
Future<Set<String>> _verdeckteVarianten(AppDatabase db) async {
  final a = db.assets;
  final abfrage = db.selectOnly(a)
    ..addColumns([a.id])
    ..where(
      a.stackId.like('$variantenstapelPraefix%') & a.isStackCover.equals(false),
    );
  return {for (final z in await abfrage.get()) z.read(a.id)!};
}

import 'dart:isolate';

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
Future<Duplikatergebnis> sucheDuplikate(AppDatabase db, double schwelle) async {
  final einbettungen = await db.einbettungenImSpeicher();
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

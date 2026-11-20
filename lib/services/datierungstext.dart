import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';

String datierungstext(AufnahmeDatierung d, String sprache) => d.beschreibung(
  tag: DateFormat.yMMMd(sprache).format,
  monat: DateFormat.yMMMM(sprache).format,
);

String datierungsquelletext(AppTexte t, Datierungsquelle q) => switch (q) {
  Datierungsquelle.manuell => t.datierungManuell,
  Datierungsquelle.beschriftung => t.datierungBeschriftung,
  Datierungsquelle.ueberlieferung => t.datierungUeberlieferung,
  Datierungsquelle.datei => t.datierungDatei,
  Datierungsquelle.dateiname => t.datierungDateiname,
  Datierungsquelle.unbekannt => t.datierungUnbekannt,
};

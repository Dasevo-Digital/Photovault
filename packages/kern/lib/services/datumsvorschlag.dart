import '../db/database.dart';
import 'import_service.dart' show Datumsbefund;
import 'namensdatum.dart';

/// Woher ein vorgeschlagenes Datum kommt.
enum Datumsquelle {
  /// Nur der Dateiname nennt es; die Datei selbst trägt keines.
  dateiname,

  /// Die Datei trägt es, und der Name nennt dasselbe. Die Zeile stand nur
  /// falsch, etwa weil ein JPEG unter einem `.MOV`-Namen als Video
  /// eingelesen wurde und das Kopierdatum bekam.
  dateiUndName,
}

/// Ein Vorschlag der Prüfung „Aufnahmedaten“ (#203).
class Datumsvorschlag {
  const Datumsvorschlag({
    required this.id,
    required this.dateiname,
    required this.bisher,
    required this.bisherGeschaetzt,
    required this.neu,
    required this.geschaetzt,
    required this.quelle,
  });

  final String id;
  final String dateiname;
  final DateTime bisher;
  final bool bisherGeschaetzt;
  final DateTime neu;

  /// Der Name nennt nur den Tag: Das neue Datum bleibt „geschätzt“.
  final bool geschaetzt;
  final Datumsquelle quelle;

  /// So, wie `AufnahmedatenSetzen` ihn übernimmt.
  ({String id, DateTime zeitpunkt, bool geschaetzt}) get alsEintrag =>
      (id: id, zeitpunkt: neu, geschaetzt: geschaetzt);
}

/// Die Aufnahmen, deren Dateiname ein anderes Datum nennt als die Zeile, und
/// was stattdessen gelten sollte.
///
/// **Die Datei geht dem Namen vor.** Ein Name kann umbenannt, verrechnet
/// oder eine Zählnummer sein; der Zeitpunkt in der Datei ist der Beleg.
/// Darum:
///
/// - **Datum geschätzt**: Die Datei wurde schon gelesen und trägt keines
///   (oder es ist das Jahr aus der Bildbetrachtung). Der Name ist besser
///   als jede Schätzung.
/// - **Sonst** wird die Datei gelesen ([leseDatei]). Nennt sie dasselbe
///   wie der Name, stand die Zeile falsch. Nennt sie etwas anderes, ist
///   nichts zu entscheiden, und es gibt keinen Vorschlag. Trägt sie
///   keines und wurde nie nachgesehen, stammt die Zeile vom
///   Dateizeitstempel; dann gilt der Name. Trägt sie keines, wurde aber
///   nachgesehen, hat jemand das Datum von Hand gesetzt: Das bleibt.
///
/// [leseDatei] bekommt den Ablagepfad und liefert `null`, wenn die Datei
/// nicht zu haben ist. Gelesen wird nur, wo der Name widerspricht und das
/// Datum nicht geschätzt ist: an der Prüfbibliothek 25 von 7943 Dateien.
Future<List<Datumsvorschlag>> datumsvorschlaege(
  AppDatabase db, {
  required Future<Datumsbefund?> Function(String relativePath) leseDatei,
  DateTime? jetzt,
  String? nur,
}) async {
  final vorschlaege = <Datumsvorschlag>[];
  for (final a in await db.aufnahmenFuerNamensdatum(nur: nur)) {
    final ausName = namensdatumAus(a.name, jetzt: jetzt);
    if (ausName == null || ausName.passtZu(a.zeitpunkt)) continue;
    Datumsvorschlag vorschlag(DateTime neu, bool geschaetzt, Datumsquelle q) =>
        Datumsvorschlag(
          id: a.id,
          dateiname: a.name,
          bisher: a.zeitpunkt,
          bisherGeschaetzt: a.geschaetzt,
          neu: neu,
          geschaetzt: geschaetzt,
          quelle: q,
        );
    final ausDemNamen = vorschlag(
      ausName.zeitpunkt,
      !ausName.mitUhrzeit,
      Datumsquelle.dateiname,
    );
    if (a.geschaetzt) {
      vorschlaege.add(ausDemNamen);
      continue;
    }
    final Datumsbefund? befund;
    try {
      befund = await leseDatei(a.pfad);
    } catch (_) {
      continue;
    }
    if (befund == null || !befund.lesbar) continue;
    final inDatei = befund.zeitpunkt;
    if (inDatei == null) {
      if (!a.geprueft) vorschlaege.add(ausDemNamen);
    } else if (ausName.passtZu(inDatei)) {
      vorschlaege.add(vorschlag(inDatei, false, Datumsquelle.dateiUndName));
    }
  }
  vorschlaege.sort((x, y) => y.neu.compareTo(x.neu));
  return vorschlaege;
}

/// Der Vorschlag für eine einzelne Aufnahme – für die Info-Ansicht, nach
/// denselben Regeln wie [datumsvorschlaege].
Future<Datumsvorschlag?> datumsvorschlagFuer(
  AppDatabase db,
  String id, {
  required Future<Datumsbefund?> Function(String relativePath) leseDatei,
}) async =>
    (await datumsvorschlaege(db, leseDatei: leseDatei, nur: id)).firstOrNull;

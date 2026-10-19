import '../db/database.dart';
import 'aktivitaeten.dart';
import 'laendernamen.dart';

/// Reisen und Aktivitäten, wie die Weboberfläche und das Telefon sie
/// zeigen.
///
/// **Eine Rechnung für beide.** Der Browser bekommt sie vom Server, das
/// Telefon rechnet sie aus seiner Kopie der Bibliothek – stünde die
/// Rechnung zweimal da, zeigten beide über kurz oder lang Verschiedenes:
/// eine andere Zahl, ein anderes Titelbild, eine andere Strecke.

/// Eine Reise in der Liste.
typedef Reisekarte = ({
  ReisenData reise,
  int anzahl,
  AssetData? titelbild,
  Ortsbezug? ort,
});

/// Eine Aktivität in der Liste – mit dem Namen ihrer Reise, wenn sie zu
/// einer gehört.
typedef Aktivitaetskarte = ({
  AktivitaetenData aktivitaet,
  int anzahl,
  AssetData? titelbild,
  Ortsbezug? ort,
  String? reisename,
});

/// Ein Punkt der Route: eine verortete Aufnahme.
typedef Routenpunkt = ({
  String id,
  double breite,
  double laenge,
  DateTime zeit,
});

/// Eine Aktivität zum Ansehen: ihre Aufnahmen, die Route aus deren Orten
/// und die Strecke darauf.
typedef Aktivitaetsansicht = ({
  AktivitaetenData aktivitaet,
  ReisenData? reise,
  List<AssetData> aufnahmen,
  List<Routenpunkt> route,

  /// Die aufgezeichneten Spuren (GPX) – mit ihnen zeichnen Browser und
  /// Handy die Strecke und fliegen sie in 3D ab wie der Rechner.
  List<({SpurenData spur, List<SpurpunkteData> punkte})> spuren,

  /// Die Länge der Spuren, wenn es welche gibt – sonst die Strecke
  /// zwischen den Fotos.
  double streckeKm,
  Ortsbezug? ort,
});

/// Das Titelbild einer Reise: das gewählte, solange es noch sichtbar
/// ist, sonst die erste Aufnahme.
Future<AssetData?> _titelbildDerReise(AppDatabase db, ReisenData r) async {
  final gewaehlt = r.titelbildAssetId;
  if (gewaehlt != null) {
    final a = await db.assetById(gewaehlt);
    if (a != null && !a.isTrashed && !a.isLocked) return a;
  }
  return db.ersteAufnahmeDerReise(r.id);
}

/// Alle Reisen, jüngste zuerst.
Future<List<Reisekarte>> reisekarten(AppDatabase db) async {
  final reisen = await db.alleReisen();
  final anzahlen = await db.reiseAnzahlen();
  final orte = await db.ortsbezugJeReise();
  return [
    for (final r in reisen)
      (
        reise: r,
        anzahl: anzahlen[r.id] ?? 0,
        titelbild: await _titelbildDerReise(db, r),
        ort: orte[r.id],
      ),
  ];
}

/// Alle Aktivitäten, jüngste zuerst – oder nur die einer Reise.
Future<List<Aktivitaetskarte>> aktivitaetskarten(
  AppDatabase db, {
  String? reiseId,
}) async {
  final liste = reiseId == null
      ? await db.alleAktivitaeten()
      : await db.aktivitaetenDerReise(reiseId);
  final anzahlen = await db.aktivitaetAnzahlen();
  final orte = await db.ortsbezugJeAktivitaet();
  final reisenamen = {for (final r in await db.alleReisen()) r.id: r.name};
  return [
    for (final k in liste)
      (
        aktivitaet: k,
        anzahl: anzahlen[k.id] ?? 0,
        titelbild: await db.ersteAufnahmeDerAktivitaet(k.id),
        ort: orte[k.id],
        reisename: reisenamen[k.reiseId],
      ),
  ];
}

/// Eine Aktivität mit allem, was ihre Seite zeigt; `null`, wenn es sie
/// nicht gibt.
Future<Aktivitaetsansicht?> aktivitaetsansicht(
  AppDatabase db,
  String id,
) async {
  final k = await db.aktivitaet(id);
  if (k == null) return null;
  final aufnahmen = await db.aufnahmenDerAktivitaet(id);
  final route = <Routenpunkt>[
    for (final a in aufnahmen)
      if (a.latitude case final breite?)
        if (a.longitude case final laenge?)
          (id: a.id, breite: breite, laenge: laenge, zeit: a.fileCreatedAt),
  ];
  final reiseId = k.reiseId;
  final spuren = [
    for (final s in await db.spurenDerAktivitaet(id))
      (spur: s, punkte: await db.punkteDerSpur(s.id)),
  ];
  return (
    aktivitaet: k,
    reise: reiseId == null ? null : await db.reise(reiseId),
    aufnahmen: aufnahmen,
    route: route,
    spuren: spuren,
    streckeKm: spuren.isNotEmpty
        ? spuren.fold(0.0, (n, s) => n + s.spur.laengeKm)
        : strecke([
            for (final p in route)
              (breite: p.breite, laenge: p.laenge, zeit: p.zeit),
          ]),
    ort: (await db.ortsbezugJeAktivitaet())[id],
  );
}

/// „Ort, Region, Land“ – und, wenn es mehr als einen Ort gab, wie viele
/// weitere ([weitere] liefert den Text dafür in der Sprache der
/// Oberfläche). `null`, wenn keine Aufnahme einen Ort trug: „Unbekannt“
/// behauptete, es sei nachgesehen worden.
String? ortszeileText(
  Ortsbezug? bezug,
  String sprache,
  String Function(int anzahl) weitere,
) {
  if (bezug == null || bezug.ort == null) return null;
  final teile = [
    bezug.ort!,
    if (bezug.region case final r? when r.isNotEmpty && r != bezug.ort) r,
    if (landAnzeige(bezug.land, sprache) case final l when l.isNotEmpty) l,
  ].join(', ');
  return bezug.weitereOrte == 0
      ? teile
      : '$teile · ${weitere(bezug.weitereOrte)}';
}

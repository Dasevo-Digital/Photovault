/// Was „Rückblick“ und „Kalender“ zeigen – einmal gerechnet für Rechner,
/// Server (Browser) und Telefon (Issue #185). Vorher lag das in den
/// Bildschirmen des Rechners, und Browser und Telefon kannten beides nicht.
library;

import '../db/database.dart';
import 'familientage.dart';
import 'jahresrueckblick.dart';
import 'lebenslauf.dart';
import 'rueckblick.dart';
import 'stammbaum.dart';

// ---------------------------------------------------------------------------
// Familientage
// ---------------------------------------------------------------------------

/// Ein Familientag mit den Namen der Beteiligten und Fotos von ihnen.
typedef FamilientagMitFotos = ({
  Familientag tag,
  List<String> namen,
  List<AssetData> fotos,
});

/// Die nächsten Geburts-, Todes- und Hochzeitstage aus dem Stammbaum,
/// jeder mit Fotos der Beteiligten – bei einem Paar zuerst die, auf denen
/// beide sind.
Future<List<FamilientagMitFotos>> familientageMitFotos(
  AppDatabase db, {
  required DateTime heute,
  int hoechstensTage = 4,
  int hoechstensFotos = 12,
}) async {
  final personen = await db.allePersonen();
  if (personen.isEmpty) return const [];
  final nachId = {for (final p in personen) p.id: p};
  final netz = Verwandtschaftsnetz([
    for (final z in await db.alleBeziehungen())
      if (artAusText(z.art) case final art?) kante(z.personId, z.andereId, art),
  ]);
  final hochzeiten = <Hochzeit>[
    for (final e in await db.alleEreignisse())
      if (e.datum case final datum?)
        if (ereignisartAusText(e.art) == Ereignisart.hochzeit)
          (
            datum: datum,
            personId: e.personId,
            // Bei mehreren Partnern bleibt offen, wen die Hochzeit betraf;
            // dann steht nur die eingetragene Person da.
            partnerId: netz.partner(e.personId).length == 1
                ? netz.partner(e.personId).single
                : null,
          ),
  ];
  final tage = familientage(
    personen: [
      for (final p in personen)
        (id: p.id, geburtsdatum: p.geburtsdatum, sterbedatum: p.sterbedatum),
    ],
    hochzeiten: hochzeiten,
    heute: heute,
  ).take(hoechstensTage);

  final ergebnis = <FamilientagMitFotos>[];
  for (final tag in tage) {
    final ids = tag.personen.where(nachId.containsKey).toList();
    if (ids.isEmpty) continue;
    ergebnis.add((
      tag: tag,
      namen: [for (final id in ids) nachId[id]!.name],
      fotos: await _fotosVon(db, ids, hoechstensFotos),
    ));
  }
  return ergebnis;
}

Future<List<AssetData>> _fotosVon(
  AppDatabase db,
  List<String> ids,
  int hoechstens,
) async {
  if (ids.length == 1) {
    return (await db.assetsFuerPersonen(ids)).take(hoechstens).toList();
  }
  final je = [
    for (final id in ids) await db.assetsFuerPersonen([id]),
  ];
  final beiAllen = je.skip(1).fold({
    for (final a in je.first) a.id,
  }, (s, liste) => s.intersection({for (final a in liste) a.id}));
  final alle = await db.assetsFuerPersonen(ids);
  final gemeinsam = [
    for (final a in alle)
      if (beiAllen.contains(a.id)) a,
  ];
  return (gemeinsam.isNotEmpty ? gemeinsam : alle).take(hoechstens).toList();
}

// ---------------------------------------------------------------------------
// Erinnerungen
// ---------------------------------------------------------------------------

/// Wie weit die Erinnerungen zurückblicken: heute und die dreizehn Tage
/// davor.
const erinnerungsTage = 14;

/// Eine Erinnerung: was an [tag] vor [jahreHer] Jahren entstanden ist.
typedef Erinnerung = ({DateTime tag, int jahreHer, List<AssetData> dinge});

/// Die Kennung, unter der eine Erinnerung gemerkt wird – der Tag, an dem
/// sie spielt. Zweimal dieselbe zu merken, überschreibt also nur.
String erinnerungsKennung(DateTime tag, int jahreHer) {
  final d = DateTime(tag.year - jahreHer, tag.month, tag.day);
  String zwei(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${zwei(d.month)}-${zwei(d.day)}';
}

/// Die Erinnerungen der letzten [erinnerungsTage] Tage, neueste zuerst
/// und je Tag die jüngsten Jahre zuerst.
List<Erinnerung> erinnerungenDerLetztenTage(
  Map<DateTime, List<AssetData>> jeTag,
) {
  final tage = jeTag.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final tag in tage)
      for (final g in nachJahrenGebuendelt(
        jeTag[tag]!,
        (a) => a.fileCreatedAt,
        tag,
      ))
        (tag: tag, jahreHer: g.jahreHer, dinge: g.dinge),
  ];
}

/// Alles für die Seite „Erinnerungen“: die gemerkten, die der letzten zwei
/// Wochen und die Reisen mit den meisten Lieblingsfotos.
typedef Erinnerungsstand = ({
  List<({GemerkteErinnerungenData e, List<AssetData> dinge})> gemerkt,
  List<Erinnerung> letzte,
  List<({ReisenData reise, int lieblinge})> reisen,
});

Future<Erinnerungsstand> erinnerungsstand(
  AppDatabase db, {
  required DateTime heute,
}) async {
  final tag = DateTime(heute.year, heute.month, heute.day);
  final gemerkt = [
    for (final e in await db.alleGemerktenErinnerungen())
      (e: e, dinge: await db.aufnahmenDerErinnerung(e)),
  ];
  final jeTag = await db.assetsAnTagen([
    for (var i = 0; i < erinnerungsTage; i++)
      DateTime(tag.year, tag.month, tag.day - i),
  ]);
  return (
    gemerkt: gemerkt,
    letzte: erinnerungenDerLetztenTage(jeTag),
    reisen: await db.schoensteReisen(),
  );
}

// ---------------------------------------------------------------------------
// Jahresrückblick
// ---------------------------------------------------------------------------

/// Das Jahr, das der Rückblick anbietet: bis Februar das vergangene,
/// danach das laufende – im Januar ist vom neuen Jahr noch nichts zu sehen.
int jahresrueckblickJahr(DateTime heute) =>
    heute.month <= 2 ? heute.year - 1 : heute.year;

/// Ein Jahr in Zahlen und Bildern – siehe [jahresauswahl].
typedef Jahresinhalt = ({
  Jahreszahlen zahlen,
  List<AssetData> auswahl,
  List<({PersonData person, int anzahl})> personen,
  List<ReisenData> reisen,
});

Future<Jahresinhalt> jahresinhalt(AppDatabase db, int jahr) async {
  final von = DateTime(jahr), bis = DateTime(jahr, 12, 31);
  final aufnahmen = await db.aufnahmenImZeitraum(von, bis);
  final daten = [
    for (final a in aufnahmen)
      (
        id: a.id,
        wann: a.fileCreatedAt,
        video: a.type == 'VIDEO',
        favorit: a.isFavorite,
        bewertung: a.rating,
        schaerfe: a.sharpnessScore,
        land: a.locationCountry,
        ort: a.locationCity,
        datumGeraten: a.datumGeschaetzt,
      ),
  ];
  final nachId = {for (final a in aufnahmen) a.id: a};
  return (
    zahlen: jahreszahlen(daten),
    auswahl: [for (final id in jahresauswahl(daten)) nachId[id]!],
    personen: await db.personenImZeitraum(von, bis),
    reisen: [
      for (final r in await db.alleReisen())
        if (r.von.year <= jahr && r.bis.year >= jahr) r,
    ]..sort((a, b) => a.von.compareTo(b.von)),
  );
}

// ---------------------------------------------------------------------------
// Kalender
// ---------------------------------------------------------------------------

/// Ein Jahr oder Monat im Kalender: wie viele Aufnahmen, und das neueste
/// Foto darin als Titelbild.
typedef Kalenderfeld = ({int nummer, int anzahl, AssetData? titelbild});

/// Die Jahre mit Aufnahmen, das neueste zuerst.
Future<List<Kalenderfeld>> kalenderjahre(AppDatabase db) async {
  final zahlen = await db.assetCountsByYear();
  final jahre = zahlen.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final j in jahre)
      (
        nummer: j,
        anzahl: zahlen[j]!,
        titelbild: await db.newestAssetForYear(j),
      ),
  ];
}

/// Die Monate eines Jahres mit Aufnahmen, Januar zuerst.
Future<List<Kalenderfeld>> kalendermonate(AppDatabase db, int jahr) async {
  final zahlen = await db.assetCountsByMonth(jahr);
  final monate = zahlen.keys.toList()..sort();
  return [
    for (final m in monate)
      (
        nummer: m,
        anzahl: zahlen[m]!,
        titelbild: await db.newestAssetForMonth(jahr, m),
      ),
  ];
}

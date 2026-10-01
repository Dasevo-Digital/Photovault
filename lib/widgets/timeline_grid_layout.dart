import '../db/rasterzeile.dart';
import '../services/bildreihen.dart';
import '../services/rasterstufen.dart';

export '../services/bildreihen.dart'
    show Bildreihe, Bildplatz, reihenGesamthoehe, seitenverhaeltnisVorgabe;
export '../services/rasterstufen.dart';

/// Geschätzte Maße des von [MonthGroupedAssetGrid] erzeugten Scroll-Inhalts
/// (Monats-Überschrift, Grid-Kachelgröße/-abstände) – gemeinsam von
/// [TimelineScrubber] (Sprung zu einem Monat) und [MonthGroupedAssetGrid]
/// selbst (Sprung zu einem bestimmten Foto, siehe "Foto in der Timeline
/// anzeigen") genutzt, damit beide von denselben Annahmen ausgehen statt die
/// Formel zweimal leicht unterschiedlich zu pflegen. Muss nicht pixelgenau
/// sein (das Ziel wird nach dem Scrollen ohnehin sichtbar), soll aber grob
/// genug stimmen, damit sich Scrubber und Sprung-Funktion nicht "falsch
/// anfühlen".
///
/// **Bei den bündigen Reihen ist es keine Schätzung mehr.** Dort steht die
/// Anordnung als Rechnung in `bildreihen.dart`, und dieselbe Rechnung
/// liefert dem Zeitstrahl die Höhe. Was das Raster zeichnet und was der
/// Zeitstrahl annimmt, kann dann gar nicht mehr auseinanderlaufen.
/// Die Höhe einer Monatsüberschrift.
///
/// **Gemessen, nicht gesetzt.** Hier stand 64, und die Überschrift misst
/// 52 – `AppSpacing.xl` oben, die Zeile selbst, `AppSpacing.sm` unten.
/// Der Unterschied fällt auf keinem Bildschirm auf, summiert sich in
/// [timelineOffsetForAsset] aber über jede Monatsgruppe auf: Beim Sprung
/// in die Mitte der echten Bibliothek (Gruppe 41 von 82) landete die
/// Zeitleiste **504 Punkte zu tief** – eine halbe Bildschirmhöhe, und in
/// den ältesten Monaten wäre es eine ganze.
///
/// `zeitleiste_ueberschrift_test.dart` hält die Zahl an der wirklich
/// gezeichneten Überschrift fest; wächst sie, fällt der Test.
const double timelineHeaderHeight = 52.0;
const double timelineTrailingHeight = 40.0;
const double timelineGridMaxCrossAxisExtent = 160.0;
const double timelineGridSpacing = 4.0;
const double timelineGridHorizontalPadding =
    24.0; // 12px links + rechts (SliverPadding)

int timelineColumnsForWidth(double gridWidth,
    {double kachelbreite = timelineGridMaxCrossAxisExtent}) {
  final availableWidth = gridWidth - timelineGridHorizontalPadding;
  final count = (availableWidth / (kachelbreite + timelineGridSpacing)).ceil();
  return count < 1 ? 1 : count;
}

double timelineRowHeightForWidth(double gridWidth,
    {double kachelbreite = timelineGridMaxCrossAxisExtent}) {
  final availableWidth = gridWidth - timelineGridHorizontalPadding;
  final columns =
      timelineColumnsForWidth(gridWidth, kachelbreite: kachelbreite);
  final usable = availableWidth - timelineGridSpacing * (columns - 1);
  final tileExtent = usable / columns;
  return tileExtent + timelineGridSpacing;
}

/// Das Seitenverhältnis (Breite ÷ Höhe) einer Aufnahme.
///
/// Die Masse liegen in der Datenbank und sind bereits nach der
/// EXIF-Ausrichtung gedreht – an der echten Bibliothek gegengeprüft: 27 %
/// Hochformat, was ohne Drehung nicht herauskäme. Fehlen sie (2 von 8098),
/// gilt das Kleinbildformat.
double seitenverhaeltnisVon(Rasterzeile a) {
  final b = a.widthPx;
  final h = a.heightPx;
  if (b == null || h == null || b <= 0 || h <= 0) {
    return seitenverhaeltnisVorgabe;
  }
  return b / h;
}

/// Die bündigen Reihen einer Monatsgruppe.
///
/// [kachelbreite] – die eingestellte Kachelstufe – wirkt hier als
/// **Zielhöhe** der Reihen. So bleibt der vorhandene Zoom sinnvoll, statt
/// dass die neue Form einen zweiten Regler braucht.
List<Bildreihe> zeitleisteReihen(List<Rasterzeile> gruppe, double gridWidth,
    {double kachelbreite = timelineGridMaxCrossAxisExtent}) {
  return bildreihen(
    seitenverhaeltnisse: [for (final a in gruppe) seitenverhaeltnisVon(a)],
    breite: gridWidth - timelineGridHorizontalPadding,
    zielhoehe: kachelbreite,
    abstand: timelineGridSpacing,
  );
}

double timelineMonthGroupHeight(
  List<Rasterzeile> gruppe,
  double gridWidth, {
  double kachelbreite = timelineGridMaxCrossAxisExtent,
  Zeitleistenform form = zeitleisteFormVorgabe,
  bool mitUeberschrift = true,
  bool mitTagen = false,
}) {
  // Ohne Gliederung steht statt der Überschrift ein leerer Kasten (siehe
  // MonthGroupedAssetGrid.gliedern); die Höhe muss dasselbe sagen wie das
  // Bild, sonst schätzt der Sliver seine Gesamthöhe daneben.
  final kopf = mitUeberschrift ? timelineHeaderHeight : 0.0;
  if (mitTagen) {
    return kopf +
        tageszeilenHoehe(zeitleisteTageszeilen(gruppe, gridWidth,
            kachelbreite: kachelbreite, form: form));
  }
  if (form == Zeitleistenform.reihen) {
    final reihen =
        zeitleisteReihen(gruppe, gridWidth, kachelbreite: kachelbreite);
    return kopf + reihenGesamthoehe(reihen, timelineGridSpacing);
  }
  final columns =
      timelineColumnsForWidth(gridWidth, kachelbreite: kachelbreite);
  final rows = (gruppe.length / columns).ceil();
  // Die Zeilenhöhe trägt den Abstand UNTER sich. Hinter der letzten Zeile
  // gibt es keinen – sonst zählte jede Monatsgruppe vier Punkte zu viel,
  // und über die ganze Bibliothek wurden daraus 164.
  return kopf +
      rows * timelineRowHeightForWidth(gridWidth, kachelbreite: kachelbreite) -
      (rows > 0 ? timelineGridSpacing : 0);
}

/// Geschätzter Scroll-Offset, um [assetId] an den oberen Rand der Ansicht zu
/// bringen (Beginn der Zeile, die es enthält) – oder `null`, wenn es in
/// keiner der übergebenen Gruppen vorkommt.
double? timelineOffsetForAsset(
  List<int> orderedKeys,
  Map<int, List<Rasterzeile>> groups,
  double gridWidth,
  String assetId, {
  double kachelbreite = timelineGridMaxCrossAxisExtent,
  Zeitleistenform form = zeitleisteFormVorgabe,
  bool mitTagen = false,
}) {
  var offset = 0.0;
  for (final key in orderedKeys) {
    final group = groups[key]!;
    final indexInGroup = group.indexWhere((a) => a.id == assetId);
    if (indexInGroup != -1) {
      return offset +
          timelineHeaderHeight +
          (mitTagen
              ? _abstandBisTageszeile(
                  zeitleisteTageszeilen(group, gridWidth,
                      kachelbreite: kachelbreite, form: form),
                  indexInGroup)
              : _abstandBisZeile(
                  group, indexInGroup, gridWidth, kachelbreite, form));
    }
    offset += timelineMonthGroupHeight(group, gridWidth,
        kachelbreite: kachelbreite, form: form, mitTagen: mitTagen);
  }
  return null;
}

/// Wie weit die Zeile, in der [indexInGroup] steht, unterhalb der
/// Monatsüberschrift beginnt.
double _abstandBisZeile(List<Rasterzeile> gruppe, int indexInGroup,
    double gridWidth, double kachelbreite, Zeitleistenform form) {
  if (form == Zeitleistenform.reihen) {
    final reihen =
        zeitleisteReihen(gruppe, gridWidth, kachelbreite: kachelbreite);
    var oben = 0.0;
    for (final r in reihen) {
      if (indexInGroup <= r.letzterIndex) return oben;
      oben += r.hoehe + timelineGridSpacing;
    }
    return oben;
  }
  final columns =
      timelineColumnsForWidth(gridWidth, kachelbreite: kachelbreite);
  final zeile = indexInGroup ~/ columns;
  return zeile *
      timelineRowHeightForWidth(gridWidth, kachelbreite: kachelbreite);
}

// ---- Tage innerhalb eines Monats ----------------------------------------
//
// **Warum kleine Tage nebeneinander stehen.** An der echten Bibliothek
// (7542 Aufnahmen, 534 Tage) haben 179 Tage genau ein Foto und weitere 146
// zwei oder drei. Bekäme jeder Tag eine eigene Überschrift über einer
// eigenen Reihe, bestünde die Zeitleiste zu zwei Dritteln aus Überschriften
// und dem leeren Rest angebrochener Reihen. Deshalb rücken Tage, die in eine
// einzige Reihe passen, nebeneinander – jeder mit seiner Überschrift, wie
// bei Immich. Ein Tag, der mehr als eine Reihe braucht, steht für sich: die
// Überschrift quer über die Breite, darunter seine Reihen.
//
// Reine Rechnung wie [zeitleisteReihen]: Raster, Zeitstrahl, Sprung zum Foto
// und Tastatur nehmen ihre Einteilung alle von hier.

/// Die Höhe einer Tagesüberschrift.
///
/// Gemessen wie [timelineHeaderHeight] – `zeitleiste_tage_test.dart` hält
/// sie an der wirklich gezeichneten Überschrift fest.
const double timelineTagesKopfHoehe = 32.0;

/// Der waagerechte Abstand zwischen zwei Tagen in derselben Zeile – sichtbar
/// grösser als der zwischen zwei Fotos, sonst läse man die Tage als einen.
const double timelineTagesabstand = 16.0;

/// Ein kleiner Tag in einer [TagesblockZeile].
class Tagesblock {
  const Tagesblock({
    required this.von,
    required this.bis,
    required this.reihe,
    required this.breite,
  });

  /// Erster und letzter Index (einschliesslich) in der Monatsgruppe.
  final int von;
  final int bis;

  /// Die eine Reihe des Tages; die Indizes darin zählen in der
  /// Monatsgruppe, nicht im Tag.
  final Bildreihe reihe;

  /// So breit, wie die Fotos samt Abständen es verlangen.
  final double breite;

  int get anzahl => bis - von + 1;
}

/// Eine Zeile der Tagesgliederung – ein Eintrag in der Liste des Monats.
sealed class Tageszeile {
  const Tageszeile();

  double get hoehe;

  /// Wie viele Fotos in dieser Zeile stehen – für die Pfeiltasten.
  int get anzahl;
}

/// Mehrere kleine Tage nebeneinander, jeder mit eigener Überschrift.
class TagesblockZeile extends Tageszeile {
  const TagesblockZeile(this.bloecke);

  final List<Tagesblock> bloecke;

  @override
  double get hoehe {
    var reihe = 0.0;
    for (final b in bloecke) {
      if (b.reihe.hoehe > reihe) reihe = b.reihe.hoehe;
    }
    return timelineTagesKopfHoehe + reihe;
  }

  @override
  int get anzahl {
    var n = 0;
    for (final b in bloecke) {
      n += b.anzahl;
    }
    return n;
  }
}

/// Die Überschrift eines grossen Tages, quer über die ganze Breite.
class TageskopfZeile extends Tageszeile {
  const TageskopfZeile({required this.von, required this.bis});

  final int von;
  final int bis;

  @override
  double get hoehe => timelineTagesKopfHoehe;

  @override
  int get anzahl => 0;
}

/// Eine Fotoreihe eines grossen Tages.
class TagesbildZeile extends Tageszeile {
  const TagesbildZeile(this.reihe);

  /// Indizes in der Monatsgruppe.
  final Bildreihe reihe;

  @override
  double get hoehe => reihe.hoehe;

  @override
  int get anzahl => reihe.plaetze.length;
}

int _tagesschluessel(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

/// Die Reihen eines Tages, mit Indizes in der Monatsgruppe.
///
/// Bei Quadraten dieselbe Spaltenzahl und Kante wie im Monatsraster – ein
/// Foto ist in beiden Gliederungen gleich gross.
List<Bildreihe> _reihenDesTages(List<Rasterzeile> gruppe, int von, int bis,
    double gridWidth, double kachelbreite, Zeitleistenform form) {
  if (form == Zeitleistenform.reihen) {
    return [
      for (final r in zeitleisteReihen(gruppe.sublist(von, bis + 1), gridWidth,
          kachelbreite: kachelbreite))
        Bildreihe(hoehe: r.hoehe, plaetze: [
          for (final p in r.plaetze) (index: p.index + von, breite: p.breite),
        ]),
    ];
  }
  final spalten =
      timelineColumnsForWidth(gridWidth, kachelbreite: kachelbreite);
  final kante =
      timelineRowHeightForWidth(gridWidth, kachelbreite: kachelbreite) -
          timelineGridSpacing;
  return [
    for (var anfang = von; anfang <= bis; anfang += spalten)
      Bildreihe(hoehe: kante, plaetze: [
        for (var i = anfang; i <= bis && i < anfang + spalten; i++)
          (index: i, breite: kante),
      ]),
  ];
}

double _reihenbreite(Bildreihe r) {
  var b = timelineGridSpacing * (r.plaetze.length - 1);
  for (final p in r.plaetze) {
    b += p.breite;
  }
  return b;
}

/// Die Zeilen einer Monatsgruppe, nach Tagen gegliedert.
///
/// [gruppe] kommt nach Aufnahmedatum sortiert – in welche Richtung, ist
/// gleich; Fotos desselben Tages stehen in jedem Fall beieinander. Die
/// Reihenfolge bleibt erhalten: von links nach rechts, von oben nach unten.
List<Tageszeile> zeitleisteTageszeilen(
  List<Rasterzeile> gruppe,
  double gridWidth, {
  double kachelbreite = timelineGridMaxCrossAxisExtent,
  Zeitleistenform form = zeitleisteFormVorgabe,
}) {
  final breite = gridWidth - timelineGridHorizontalPadding;
  if (gruppe.isEmpty || !breite.isFinite || breite <= 0) return const [];

  final zeilen = <Tageszeile>[];
  var offen = <Tagesblock>[];
  var belegt = 0.0;
  void schliessen() {
    if (offen.isEmpty) return;
    zeilen.add(TagesblockZeile(offen));
    offen = <Tagesblock>[];
    belegt = 0;
  }

  var von = 0;
  while (von < gruppe.length) {
    final tag = _tagesschluessel(gruppe[von].fileCreatedAt);
    var bis = von;
    while (bis + 1 < gruppe.length &&
        _tagesschluessel(gruppe[bis + 1].fileCreatedAt) == tag) {
      bis++;
    }
    final reihen =
        _reihenDesTages(gruppe, von, bis, gridWidth, kachelbreite, form);
    if (reihen.length == 1) {
      final b = _reihenbreite(reihen.single);
      // Ein halber Punkt Spiel: Eine bündige Reihe ist auf die Breite
      // gerechnet, und Rundungsreste dürfen sie nicht in die nächste
      // Zeile schieben.
      if (offen.isNotEmpty &&
          belegt + timelineTagesabstand + b > breite + 0.5) {
        schliessen();
      }
      belegt = offen.isEmpty ? b : belegt + timelineTagesabstand + b;
      offen
          .add(Tagesblock(von: von, bis: bis, reihe: reihen.single, breite: b));
    } else {
      schliessen();
      zeilen.add(TageskopfZeile(von: von, bis: bis));
      for (final r in reihen) {
        zeilen.add(TagesbildZeile(r));
      }
    }
    von = bis + 1;
  }
  schliessen();
  return zeilen;
}

/// Die Höhe aller [zeilen] samt der Abstände dazwischen – ohne die
/// Monatsüberschrift. Hinter der letzten Zeile kein Abstand, dieselbe
/// Regel wie bei den Monatsreihen.
double tageszeilenHoehe(List<Tageszeile> zeilen) {
  if (zeilen.isEmpty) return 0;
  var summe = timelineGridSpacing * (zeilen.length - 1);
  for (final z in zeilen) {
    summe += z.hoehe;
  }
  return summe;
}

/// Wie weit die Zeile mit [indexInGroup] unter der Monatsüberschrift
/// beginnt. Bei nebeneinanderstehenden Tagen ist das der Beginn der Zeile,
/// also samt Tagesüberschrift.
double _abstandBisTageszeile(List<Tageszeile> zeilen, int indexInGroup) {
  var oben = 0.0;
  var gezaehlt = 0;
  for (final z in zeilen) {
    gezaehlt += z.anzahl;
    if (z.anzahl > 0 && indexInGroup < gezaehlt) return oben;
    oben += z.hoehe + timelineGridSpacing;
  }
  return oben;
}

/// Wie viele Fotos in jeder Zeile stehen, Überschriften ausgelassen – die
/// Reihenlängen für die Pfeiltasten (siehe `nachbarkachel`).
List<int> tageszeilenLaengen(List<Tageszeile> zeilen) => [
      for (final z in zeilen)
        if (z.anzahl > 0) z.anzahl,
    ];

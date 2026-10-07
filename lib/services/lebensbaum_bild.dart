/// Was auf dem Bild des Lebensbaums steht – unabhängig davon, ob die
/// Schilder gemalt sind oder erst gesetzt werden.
///
/// Zwei Wege führen hierher:
///
/// - [bildAusBelegung]: Die Schilder sind Teil des Bildes, die Personen
///   werden auf sie verteilt (Vorfahren, Nachkommen, Paar).
/// - [familienbild]: Das Bild hat keine Schilder; sie werden dort
///   gesetzt, wo die Familie sie braucht. Die Anordnung ist die des
///   Zierbaums – Generation für Generation, mit Geschwistern,
///   Angeheirateten und deren Eltern.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'lebensbaum_vorlage.dart';
import 'zierbaum.dart';

/// Ein Schild im Bild und wer darauf steht.
class Lebensbaumplatz {
  /// Das ganze Schild.
  final Rect rahmen;

  /// Wo darauf geschrieben wird.
  final Rect schrift;

  /// Eine Person, am Stamm auch ein Paar.
  final List<String> personen;

  /// Das Schild am Stamm: ohne Verwandtschaftsangabe.
  final bool amStamm;

  /// Ob das Schild erst gesetzt werden muss, weil das Bild keins hat.
  final bool zuSetzen;

  const Lebensbaumplatz({
    required this.rahmen,
    required this.schrift,
    required this.personen,
    this.amStamm = false,
    this.zuSetzen = false,
  });

  /// Die Flächen zum Antippen, eine je Person: Ein Paar teilt sich das
  /// Schild, oben die Person, unten der Partner.
  List<(Rect, String)> get flaechen {
    if (personen.length < 2) return [(rahmen, personen.single)];
    final r = rahmen;
    final hoehe = r.height / personen.length;
    return [
      for (final (i, id) in personen.indexed)
        (Rect.fromLTWH(r.left, r.top + i * hoehe, r.width, hoehe), id),
    ];
  }
}

class Lebensbaumbild {
  final Lebensbaumvorlage vorlage;

  /// Das Bild darunter, als Asset.
  final String hintergrund;

  final List<Lebensbaumplatz> plaetze;

  /// Personen ohne Schild.
  final int verschwiegen;

  const Lebensbaumbild({
    required this.vorlage,
    required this.hintergrund,
    required this.plaetze,
    required this.verschwiegen,
  });

  Iterable<String> get personen => [for (final p in plaetze) ...p.personen];

  List<(Rect, String)> get flaechen => [for (final p in plaetze) ...p.flaechen];

  /// Die Person an [stelle], oder `null`.
  String? personBei(Offset stelle) {
    for (final (r, id) in flaechen) {
      if (r.contains(stelle)) return id;
    }
    return null;
  }
}

/// Die verteilten Personen auf den gemalten Schildern.
Lebensbaumbild bildAusBelegung(
  Lebensbaumvorlage vorlage,
  Lebensbaumbelegung belegung,
) => Lebensbaumbild(
  vorlage: vorlage,
  hintergrund: vorlage.bild,
  plaetze: [
    Lebensbaumplatz(
      rahmen: vorlage.wurzel.rahmen,
      schrift: vorlage.wurzel.schrift,
      personen: belegung.wurzel,
      amStamm: true,
    ),
    for (final MapEntry(key: i, value: id) in belegung.felder.entries)
      Lebensbaumplatz(
        rahmen: vorlage.felder[i].rahmen,
        schrift: vorlage.felder[i].schrift,
        personen: [id],
      ),
  ],
  verschwiegen: belegung.verschwiegen,
);

/// So breit wird ein gesetztes Schild höchstens – etwas grösser als die
/// gemalten der grossen Tafeln.
const _hoechsteSchildbreite = 260.0;

/// Flacher als so viel zu eins wird ein gesetztes Schild nicht.
const _flachstes = 0.45;

/// Setzt den Zierbaum [plan] in die Krone der [vorlage].
///
/// Die Generationen werden gleichmässig über die Krone verteilt, die
/// älteste oben. Waagerecht wird der Plan so gestaucht, dass er in die
/// Krone passt; weil seine Abstände mitschrumpfen, überlappt dabei
/// nichts. Die Schilder sind alle gleich gross – so gross, wie es die
/// breiteste Generation und die Zahl der Generationen erlauben.
Lebensbaumbild familienbild(
  Zierbaumplan plan,
  Lebensbaumvorlage vorlage, {
  int verschwiegen = 0,
}) {
  final krone = vorlage.krone!;
  if (plan.schilder.isEmpty) {
    return Lebensbaumbild(
      vorlage: vorlage,
      hintergrund: vorlage.leeresBild!,
      plaetze: const [],
      verschwiegen: verschwiegen,
    );
  }
  final baender = {for (final s in plan.schilder) s.band}.toList()..sort();
  final links = plan.schilder.map((s) => s.links).reduce(math.min);
  final rechts = plan.schilder.map((s) => s.rechts).reduce(math.max);
  final mitte = (links + rechts) / 2;
  final massstab = krone.width / math.max(rechts - links, 1);

  // **Wer abstammt, steht innen.** Im Zierbaum steht in jedem Haushalt
  // der Verwandte links und der Angeheiratete rechts daneben. Links vom
  // Stamm hiesse das: der Angeheiratete zwischen dem Verwandten und dem
  // Stamm. Dort werden die Plätze im Haushalt deshalb gespiegelt – aber
  // nur unterhalb der Person in der Mitte. Ab ihrer Generation aufwärts
  // stehen über einem Angeheirateten seine eigenen Eltern, und gespiegelt
  // stünde er nicht mehr unter ihnen.
  final xVon = <String, double>{};
  final haushalte = <String, List<Schild>>{};
  for (final s in plan.schilder) {
    (haushalte[s.haushaltId] ??= []).add(s);
  }
  for (final bewohner in haushalte.values) {
    final plaetze = [for (final s in bewohner) s.mitteX]..sort();
    final mitteHaushalt = (plaetze.first + plaetze.last) / 2;
    final gespiegelt =
        bewohner.length > 1 &&
        bewohner.first.band > 0 &&
        mitteHaushalt < plan.stammX;
    final folge = [...bewohner]..sort((a, b) => a.mitteX.compareTo(b.mitteX));
    for (final (i, s) in folge.indexed) {
      xVon[s.personId] = gespiegelt
          ? plaetze[plaetze.length - 1 - i]
          : s.mitteX;
    }
  }
  // Die Lücke zwischen zwei Partnern ist die engste im Plan; ein Teil
  // davon darf das Schild breiter machen – die gemalten Schilder haben
  // ohnehin einen Rand, der wie Abstand wirkt.
  final schildBreite =
      plan.schilder.first.breite + const Zierbaummasse().partnerLuecke * 0.8;

  var breite = math.min(schildBreite * massstab, _hoechsteSchildbreite);
  // Ein sehr flaches Schild wird etwas gestreckt: Sonst fasst es nur
  // Schrift, die keiner mehr lesen kann.
  final verhaeltnis = math.max(vorlage.schildVerhaeltnis, _flachstes);
  final innen = vorlage.schildSchrift;
  var hoehe = breite * verhaeltnis;
  // Übereinander müssen die Generationen auch passen.
  final hoechstens = krone.height / (baender.length * 1.12);
  if (hoehe > hoechstens) {
    hoehe = hoechstens;
    breite = hoehe / verhaeltnis;
  }
  double zeileY(int band) {
    final i = baender.indexOf(band);
    if (baender.length == 1) return krone.center.dy;
    return krone.top +
        hoehe / 2 +
        i * (krone.height - hoehe) / (baender.length - 1);
  }

  return Lebensbaumbild(
    vorlage: vorlage,
    hintergrund: vorlage.leeresBild!,
    plaetze: [
      for (final s in plan.schilder)
        () {
          final rahmen = Rect.fromCenter(
            center: Offset(
              krone.center.dx + (xVon[s.personId]! - mitte) * massstab,
              zeileY(s.band),
            ),
            width: breite,
            height: hoehe,
          );
          return Lebensbaumplatz(
            rahmen: rahmen,
            schrift: Rect.fromLTRB(
              rahmen.left + rahmen.width * innen.left,
              rahmen.top + rahmen.height * innen.top,
              rahmen.left + rahmen.width * innen.right,
              rahmen.top + rahmen.height * innen.bottom,
            ),
            personen: [s.personId],
            zuSetzen: true,
          );
        }(),
    ],
    verschwiegen: verschwiegen,
  );
}

/// Wo die Porträts eines Platzes sitzen: auf seiner Oberkante, je Person
/// eines, gleichmässig verteilt – wie ein Bildnis über einer Tafel.
///
/// Nur für Personen, für die [hatBild] stimmt. Ein leerer Kreis mit
/// einem Symbol würde auf einem gemalten Baum wie ein Loch aussehen.
List<(Rect kreis, String id)> portraitKreise(
  Lebensbaumplatz platz,
  bool Function(String id) hatBild,
) {
  final r = platz.rahmen;
  final n = platz.personen.length;
  final radius = math.min(r.height * 0.3, r.width / n * 0.4);
  return [
    for (final (i, id) in platz.personen.indexed)
      if (hatBild(id))
        (
          Rect.fromCircle(
            center: Offset(r.left + r.width * (i + 1) / (n + 1), r.top),
            radius: radius,
          ),
          id,
        ),
  ];
}

/// Die Schriftfläche eines Platzes, unter seinen Porträts.
Rect schriftUnterPortraits(
  Lebensbaumplatz platz,
  bool Function(String id) hatBild,
) {
  final kreise = portraitKreise(platz, hatBild);
  if (kreise.isEmpty) return platz.schrift;
  final unten = kreise.map((k) => k.$1.bottom).reduce(math.max) + 2;
  if (unten <= platz.schrift.top) return platz.schrift;
  return Rect.fromLTRB(
    platz.schrift.left,
    math.min(unten, platz.schrift.bottom - platz.schrift.height * 0.5),
    platz.schrift.right,
    platz.schrift.bottom,
  );
}

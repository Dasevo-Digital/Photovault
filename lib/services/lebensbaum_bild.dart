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

/// Wie das Schildbild aufgebaut ist, als Anteile seiner Grösse: Oben die
/// Zierkante, darunter der helle Grund, auf den geschrieben wird.
const _schildSeitenverhaeltnis = 153 / 220;
const _schriftLinks = 0.105;
const _schriftOben = 0.34;
const _schriftRechts = 0.895;
const _schriftUnten = 0.86;

/// So breit wird ein gesetztes Schild höchstens – so gross wie die
/// gemalten der grossen Tafeln.
const _hoechsteSchildbreite = 220.0;

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
  // Die Lücke zwischen zwei Partnern ist die engste im Plan; ein Teil
  // davon darf das Schild breiter machen – die gemalten Schilder haben
  // ohnehin einen Rand, der wie Abstand wirkt.
  final schildBreite =
      plan.schilder.first.breite + const Zierbaummasse().partnerLuecke * 0.8;

  var breite = math.min(schildBreite * massstab, _hoechsteSchildbreite);
  var hoehe = breite * _schildSeitenverhaeltnis;
  // Übereinander müssen die Generationen auch passen.
  final hoechstens = krone.height / (baender.length * 1.12);
  if (hoehe > hoechstens) {
    hoehe = hoechstens;
    breite = hoehe / _schildSeitenverhaeltnis;
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
              krone.center.dx + (s.mitteX - mitte) * massstab,
              zeileY(s.band),
            ),
            width: breite,
            height: hoehe,
          );
          return Lebensbaumplatz(
            rahmen: rahmen,
            schrift: Rect.fromLTRB(
              rahmen.left + rahmen.width * _schriftLinks,
              rahmen.top + rahmen.height * _schriftOben,
              rahmen.left + rahmen.width * _schriftRechts,
              rahmen.top + rahmen.height * _schriftUnten,
            ),
            personen: [s.personId],
            zuSetzen: true,
          );
        }(),
    ],
    verschwiegen: verschwiegen,
  );
}

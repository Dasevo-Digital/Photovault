/// Die Anordnung des Zierbaums – ohne Oberfläche.
///
/// Der Reihenbaum stellte die Verwandtschaft nach Rolle auf: eine Zeile
/// Eltern, eine Zeile Geschwister. Hier wird sie nach **Abstammung**
/// aufgestellt: Wer von wem abstammt, steht darunter, und die beiden
/// Linien aus einem Geschwisterhaushalt gehen zu zwei verschiedenen
/// Elternhäusern (siehe [Stammbaumgeflecht.elternhaeuserVon]).
///
/// Ausgelagert aus demselben Grund wie [faechertafel.dart]: Ob sich zwei
/// Schilder um ein Hundertstel überlappen oder ein Kind wirklich mittig
/// unter seinen Eltern sitzt, sieht man einem Bild nicht an – man rechnet
/// es nach.
///
/// **Warum kein aufgeräumter Baum im Lehrbuchsinn.** Ein solcher setzt
/// voraus, dass jeder Knoten höchstens einen Vorgänger hat. Das gilt hier
/// nicht: Der Haushalt „Schwester + Schwager" hängt an **zwei**
/// Elternhäusern, weil zwei Menschen darin wohnen. Deshalb wird
/// bandweise gerechnet – jedes Band setzt sich an den Schwerpunkt seiner
/// schon gesetzten Nachbarn, danach werden Überschneidungen
/// auseinandergeschoben.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'stammbaum.dart';

/// Ein Schild: eine Person, ihr Platz.
@immutable
class Schild {
  final String personId;

  /// Der Haushalt, in dem die Person wohnt.
  final String haushaltId;

  /// Das Generationsband – 0 ist die Mitte, negativ nach oben.
  final int band;

  /// Linke obere Ecke.
  final double links;
  final double oben;
  final double breite;
  final double hoehe;

  const Schild({
    required this.personId,
    required this.haushaltId,
    required this.band,
    required this.links,
    required this.oben,
    required this.breite,
    required this.hoehe,
  });

  double get rechts => links + breite;
  double get unten => oben + hoehe;
  double get mitteX => links + breite / 2;
  double get mitteY => oben + hoehe / 2;

  /// Ob sich zwei Schilder ins Gehege kommen.
  bool ueberschneidet(Schild andere) =>
      links < andere.rechts &&
      andere.links < rechts &&
      oben < andere.unten &&
      andere.oben < unten;

  @override
  bool operator ==(Object other) =>
      other is Schild &&
      other.personId == personId &&
      other.links == links &&
      other.oben == oben &&
      other.breite == breite &&
      other.hoehe == hoehe;

  @override
  int get hashCode => Object.hash(personId, links, oben, breite, hoehe);

  @override
  String toString() =>
      'Schild($personId @${links.toStringAsFixed(1)},${oben.toStringAsFixed(1)})';
}

/// Ein Ast: von einem Schild hinauf zum Haushalt der Eltern.
///
/// Vier Punkte, also eine kubische Kurve. Gerade Linien hätten es auch
/// getan; sie sehen aber aus wie ein Organigramm, und das war ausdrücklich
/// nicht das Ziel.
@immutable
class Ast {
  /// Wessen Abstammung dieser Ast zeigt.
  final String personId;

  /// Am Schild der Person, oben.
  final double vonX;
  final double vonY;

  /// Am Elternhaus, unten.
  final double nachX;
  final double nachY;

  const Ast({
    required this.personId,
    required this.vonX,
    required this.vonY,
    required this.nachX,
    required this.nachY,
  });

  /// Die beiden Steuerpunkte der Kurve.
  ///
  /// Senkrecht aus beiden Enden heraus: So verlässt der Ast das Schild
  /// nach oben und trifft das Elternhaus von unten, statt schräg
  /// anzuschneiden. Die halbe Höhe als Ausladung ist die Zahl, bei der
  /// die Kurve voll aussieht, ohne auszubeulen.
  double get steuer1Y => vonY - (vonY - nachY) * 0.5;
  double get steuer2Y => nachY + (vonY - nachY) * 0.5;

  @override
  bool operator ==(Object other) =>
      other is Ast &&
      other.personId == personId &&
      other.vonX == vonX &&
      other.vonY == vonY &&
      other.nachX == nachX &&
      other.nachY == nachY;

  @override
  int get hashCode => Object.hash(personId, vonX, vonY, nachX, nachY);
}

/// Der Verbinder zwischen zwei Partnern eines Haushalts.
@immutable
class Partnerband {
  final double vonX;
  final double nachX;
  final double y;
  const Partnerband(this.vonX, this.nachX, this.y);

  @override
  bool operator ==(Object other) =>
      other is Partnerband &&
      other.vonX == vonX &&
      other.nachX == nachX &&
      other.y == y;

  @override
  int get hashCode => Object.hash(vonX, nachX, y);
}

/// Was am Ende zu zeichnen ist.
@immutable
class Zierbaumplan {
  final List<Schild> schilder;
  final List<Ast> aeste;
  final List<Partnerband> baender;

  /// Der belegte Bereich, mit Rand.
  final double breite;
  final double hoehe;

  /// Wo der Stamm steht – unter der Mitte.
  final double stammX;

  const Zierbaumplan({
    required this.schilder,
    required this.aeste,
    required this.baender,
    required this.breite,
    required this.hoehe,
    required this.stammX,
  });

  /// Zwei Pläne sind gleich, wenn sie dasselbe Bild ergeben.
  ///
  /// Gebraucht von `shouldRepaint`: Ohne dieses `==` verglichen sich zwei
  /// gleiche Pläne über ihre Kennung, und der Maler zeichnete bei jedem
  /// Aufbau neu, obwohl sich nichts geändert hat.
  @override
  bool operator ==(Object other) =>
      other is Zierbaumplan &&
      other.breite == breite &&
      other.hoehe == hoehe &&
      other.stammX == stammX &&
      _gleich(other.schilder, schilder) &&
      _gleich(other.aeste, aeste) &&
      _gleich(other.baender, baender);

  @override
  int get hashCode => Object.hash(breite, hoehe, stammX, schilder.length,
      aeste.length, baender.length);

}

/// Die Masse eines Schildes und der Abstände dazwischen.
///
/// Als Wertobjekt und nicht als Konstanten: Das PDF zeichnet denselben
/// Baum auf eine sehr viel grössere Leinwand, und zwei Sätze Konstanten
/// wären zwei Bäume, die auseinanderlaufen können.
@immutable
class Zierbaummasse {
  final double schildBreite;
  final double schildHoehe;

  /// Zwischen zwei Schildern desselben Haushalts.
  final double partnerLuecke;

  /// Zwischen zwei Haushalten im selben Band.
  final double haushaltLuecke;

  /// Zwischen zwei Bändern.
  final double bandLuecke;

  /// Rand um das Ganze; unten mehr, dort steht der Familienname.
  final double rand;
  final double randUnten;

  const Zierbaummasse({
    this.schildBreite = 132,
    this.schildHoehe = 108,
    this.partnerLuecke = 14,
    this.haushaltLuecke = 44,
    this.bandLuecke = 76,
    this.rand = 48,
    this.randUnten = 120,
  });

  /// Dieselben Verhältnisse, nur grösser – für die Tafel zum Aufhängen.
  Zierbaummasse mal(double faktor) => Zierbaummasse(
        schildBreite: schildBreite * faktor,
        schildHoehe: schildHoehe * faktor,
        partnerLuecke: partnerLuecke * faktor,
        haushaltLuecke: haushaltLuecke * faktor,
        bandLuecke: bandLuecke * faktor,
        rand: rand * faktor,
        randUnten: randUnten * faktor,
      );

  /// Wie breit ein Haushalt mit [anzahl] Bewohnern ist.
  double haushaltBreite(int anzahl) =>
      anzahl * schildBreite + (anzahl - 1) * partnerLuecke;
}

/// Die Masszahlen des Schildes, die Bildschirm **und** Tafel teilen.
///
/// **Warum sie hier stehen und nicht im Widget.** Auf dem Bildschirm ist
/// ein Schild ein Widget; auf der Tafel wird es gemalt. Zwei
/// Darstellungen also – und zwei Sätze Zahlen wären zwei Schilder, die
/// auseinanderlaufen, sobald jemand nur eines davon anfasst. Was beide
/// gemeinsam haben, steht deshalb an einer Stelle.
@immutable
class Schildmasse {
  final double rundung;
  final double randStark;
  final double randSchwach;
  final double polsterX;
  final double polsterY;

  /// Schriftgrössen: Name, Verhältnis, Lebensdaten.
  final double schriftName;
  final double schriftNeben;

  /// Der Kreis des Porträts über der Tafel.
  final double portraitRadius;
  final double portraitAbstand;

  /// Das Mehrzeichen an der Kante.
  final double zeichenGroesse;

  const Schildmasse({
    this.rundung = 9,
    this.randStark = 2.5,
    this.randSchwach = 1,
    this.polsterX = 6,
    this.polsterY = 4,
    this.schriftName = 14,
    this.schriftNeben = 11,
    this.portraitRadius = 19,
    this.portraitAbstand = 3,
    this.zeichenGroesse = 13,
  });

  Schildmasse mal(double faktor) => Schildmasse(
        rundung: rundung * faktor,
        randStark: randStark * faktor,
        randSchwach: randSchwach * faktor,
        polsterX: polsterX * faktor,
        polsterY: polsterY * faktor,
        schriftName: schriftName * faktor,
        schriftNeben: schriftNeben * faktor,
        portraitRadius: portraitRadius * faktor,
        portraitAbstand: portraitAbstand * faktor,
        zeichenGroesse: zeichenGroesse * faktor,
      );

  /// Wie hoch die Tafel unter dem Porträt ist.
  double tafelHoehe(double schildHoehe) =>
      schildHoehe - portraitRadius * 2 - portraitAbstand;

  /// Wie viel Höhe die drei Zeilen mindestens brauchen.
  ///
  /// **Warum das nachgerechnet gehört und nicht nachgemessen.** Auf einem
  /// Schild stehen Name, Verhältnis und Lebensdaten. Passen sie nicht,
  /// quetscht ein `Flexible` sie zusammen – die Kästen bleiben brav
  /// untereinander, aber der Text malt über seinen eigenen Rand hinaus
  /// und liegt auf der Zeile darüber. Genau so sah es im gemeldeten
  /// Bildschirmfoto aus: „Sohn" lag halb über „Martin".
  ///
  /// Ein Widget-Test findet das **nicht**: Er rendert mit einer
  /// Platzhalterschrift, deren Zeilenmasse andere sind als die von EB
  /// Garamond. Was sich prüfen lässt, ist die Rechnung – und die gilt
  /// für jede Schrift, deren Zeilen nicht höher sind als der hier
  /// angesetzte Faktor.
  double mindestTafelhoehe() =>
      schriftName * 1.35 + schriftNeben * 1.35 * 2 + polsterY * 2;

  /// Was die Tafel bräuchte, stünden die Mehrzeichen in der Reihe.
  ///
  /// Nur für den Prüfstand: Er hält damit fest, warum sie es nicht tun.
  double mindestTafelhoeheMitZeichen() =>
      mindestTafelhoehe() + 2 * zeichenGroesse;
}

/// Rechnet die Anordnung aus.
///
/// [geflecht] kommt aus [geflechtUm]. Das Ergebnis ist vollständig
/// bestimmt: dieselbe Familie ergibt zweimal dieselben Zahlen.
Zierbaumplan zierbaumplan(
  Stammbaumgeflecht geflecht, {
  Zierbaummasse masse = const Zierbaummasse(),
}) {
  final baender = geflecht.haushalte.map((h) => geflecht.band[h.id]!).toSet().toList()
    ..sort();
  if (baender.isEmpty) {
    return const Zierbaumplan(
        schilder: [], aeste: [], baender: [], breite: 0, hoehe: 0, stammX: 0);
  }

  // Haushalt -> gewünschte Mitte. Erst das Band der Mitte, dann nach
  // aussen: Jedes weitere Band richtet sich an dem aus, das schon steht.
  final mitte = <String, double>{};

  /// Setzt ein Band auf die Wünsche und schiebt Überschneidungen
  /// auseinander.
  ///
  /// Der Sortierschlüssel ist der Wunsch, nicht die Reihenfolge im
  /// Bestand: Sonst müsste der Schub Häuser umeinander herumtragen, und
  /// die Kanten kreuzten sich mehr als nötig. Bei gleichem Wunsch
  /// entscheidet die Reihenfolge – ohne sie sprängen zwei Haushalte bei
  /// jedem Aufbau umeinander.
  void setze(List<Haushalt> haushalte, Map<String, double> wunsch) {
    if (haushalte.isEmpty) return;
    final ordnung = [...haushalte]..sort((a, b) {
        final w = (wunsch[a.id] ?? 0).compareTo(wunsch[b.id] ?? 0);
        if (w != 0) return w;
        return geflecht.haushalte
            .indexOf(a)
            .compareTo(geflecht.haushalte.indexOf(b));
      });

    // Links nach rechts, jeder mindestens eine Lücke hinter dem Vorigen.
    var grenze = double.negativeInfinity;
    final gesetzt = <String, double>{};
    for (final h in ordnung) {
      final halb = masse.haushaltBreite(h.personen.length) / 2;
      final gewuenscht = wunsch[h.id] ?? 0;
      final x = math.max(gewuenscht, grenze + halb);
      gesetzt[h.id] = x;
      grenze = x + halb + masse.haushaltLuecke;
    }

    // Der Schub oben drückt alles nach rechts. Das ganze Band wieder auf
    // den Schwerpunkt der Wünsche zurückziehen, sonst wandert jedes
    // weitere Band ein Stück weiter fort und der Baum steht schief.
    var summeWunsch = 0.0;
    var summeGesetzt = 0.0;
    for (final h in ordnung) {
      summeWunsch += wunsch[h.id] ?? 0;
      summeGesetzt += gesetzt[h.id]!;
    }
    final versatz = (summeWunsch - summeGesetzt) / ordnung.length;
    for (final e in gesetzt.entries) {
      mitte[e.key] = e.value + versatz;
    }
  }

  // Das Band der Mitte zuerst, dicht an dicht in der Reihenfolge des
  // Baums. Alle wünschen sich dieselbe Stelle; der Schub darunter macht
  // daraus eine Reihe. Feste Schrittweiten wären hier falsch – ein
  // Haushalt mit Partner ist doppelt so breit wie einer ohne.
  final fokusHaus = geflecht.haushaltVon(geflecht.fokus)!;
  final bandNull = geflecht.imBand(geflecht.band[fokusHaus.id]!);
  setze(bandNull, {for (final h in bandNull) h.id: 0.0});

  /// Der Schwerpunkt der schon gesetzten Nachbarn eines Haushalts.
  ///
  /// Nachbarn sind beide Richtungen: die Kinder eines Elternhauses und
  /// die Elternhäuser eines Kinderhaushalts. Wer keine hat – eine
  /// angeheiratete Familie, von der nur die Eltern bekannt sind –, bleibt
  /// bei null und landet damit in der Mitte, statt an den Rand zu
  /// rutschen.
  double schwerpunkt(Haushalt h) {
    final werte = <double>[];
    for (final person in h.personen) {
      for (final elternhaus in geflecht.elternhaeuserVon[person] ?? const []) {
        if (mitte.containsKey(elternhaus)) werte.add(mitte[elternhaus]!);
      }
    }
    for (final e in geflecht.elternhaeuserVon.entries) {
      if (!e.value.contains(h.id)) continue;
      final kindHaus = geflecht.haushaltVon(e.key);
      if (kindHaus != null && mitte.containsKey(kindHaus.id)) {
        werte.add(mitte[kindHaus.id]!);
      }
    }
    if (werte.isEmpty) return 0;
    return werte.reduce((a, b) => a + b) / werte.length;
  }

  // Nach oben, dann nach unten – immer vom schon gesetzten Band aus.
  final nullBand = geflecht.band[fokusHaus.id]!;
  for (final b in baender.where((b) => b < nullBand).toList().reversed) {
    final haushalte = geflecht.imBand(b);
    setze(haushalte, {for (final h in haushalte) h.id: schwerpunkt(h)});
  }
  for (final b in baender.where((b) => b > nullBand)) {
    final haushalte = geflecht.imBand(b);
    setze(haushalte, {for (final h in haushalte) h.id: schwerpunkt(h)});
  }

  // **Und jetzt zurück.** Ein einziger Durchgang von der Mitte nach
  // aussen reicht nicht: Band 0 stand fest, bevor die Eltern gesetzt
  // waren, und rückte danach nie nach. Im Bild sah man das sofort – ein
  // Geschwister ohne Partner stand weit ab von seinen Eltern, weil sein
  // Platz aus einer Zeit stammte, in der sie noch nicht standen.
  //
  // Vier Durchgänge, abwechselnd von oben und von unten. Mehr bringt
  // nichts mehr: Ab dem dritten bewegt sich nur noch die letzte
  // Nachkommastelle, und die Rechnung soll enden.
  for (var runde = 0; runde < 4; runde++) {
    final reihenfolgeDerBaender =
        runde.isEven ? baender : baender.reversed.toList();
    for (final b in reihenfolgeDerBaender) {
      final haushalte = geflecht.imBand(b);
      setze(haushalte, {for (final h in haushalte) h.id: schwerpunkt(h)});
    }
  }

  // Aus den Mitten die Schilder. Y ergibt sich allein aus dem Band.
  final obenBand = baender.first;
  double bandY(int b) => (b - obenBand) * (masse.schildHoehe + masse.bandLuecke);

  final schilder = <Schild>[];
  final partnerbaender = <Partnerband>[];
  for (final h in geflecht.haushalte) {
    final b = geflecht.band[h.id]!;
    final gesamt = masse.haushaltBreite(h.personen.length);
    var x = mitte[h.id]! - gesamt / 2;
    final y = bandY(b);
    Schild? voriges;
    for (final person in h.personen) {
      final s = Schild(
        personId: person,
        haushaltId: h.id,
        band: b,
        links: x,
        oben: y,
        breite: masse.schildBreite,
        hoehe: masse.schildHoehe,
      );
      schilder.add(s);
      if (voriges != null) {
        partnerbaender.add(Partnerband(voriges.rechts, s.links, s.mitteY));
      }
      voriges = s;
      x += masse.schildBreite + masse.partnerLuecke;
    }
  }

  // Die Äste. Vom oberen Rand des Schildes zum unteren Rand des
  // Elternhauses – und zwar zu dessen Mitte, nicht zu einem der beiden
  // Schilder: Das Kind stammt vom Haushalt ab, nicht von einer Hälfte.
  final nachId = {for (final s in schilder) s.personId: s};
  final hausMitte = <String, double>{};
  final hausUnten = <String, double>{};
  for (final h in geflecht.haushalte) {
    final eigene = [for (final p in h.personen) nachId[p]!];
    hausMitte[h.id] =
        eigene.map((s) => s.mitteX).reduce((a, b) => a + b) / eigene.length;
    hausUnten[h.id] = eigene.first.unten;
  }

  // Getrennt lebende Eltern sind zwei Häuser und damit zwei Äste aus
  // demselben Schild. Sie gehen an derselben Stelle los und laufen nach
  // oben auseinander - was genau die Aussage ist.
  final aeste = <Ast>[];
  for (final e in geflecht.elternhaeuserVon.entries) {
    final schild = nachId[e.key];
    if (schild == null) continue;
    for (final haus in e.value) {
      final zielX = hausMitte[haus];
      final zielY = hausUnten[haus];
      if (zielX == null || zielY == null) continue;
      aeste.add(Ast(
        personId: e.key,
        vonX: schild.mitteX,
        vonY: schild.oben,
        nachX: zielX,
        nachY: zielY,
      ));
    }
  }

  // Alles in den sichtbaren Bereich schieben.
  final minX = schilder.map((s) => s.links).reduce(math.min);
  final maxX = schilder.map((s) => s.rechts).reduce(math.max);
  final maxY = schilder.map((s) => s.unten).reduce(math.max);
  final versatzX = masse.rand - minX;

  Schild verschoben(Schild s) => Schild(
        personId: s.personId,
        haushaltId: s.haushaltId,
        band: s.band,
        links: s.links + versatzX,
        oben: s.oben + masse.rand,
        breite: s.breite,
        hoehe: s.hoehe,
      );

  return Zierbaumplan(
    schilder: [for (final s in schilder) verschoben(s)],
    aeste: [
      for (final a in aeste)
        Ast(
          personId: a.personId,
          vonX: a.vonX + versatzX,
          vonY: a.vonY + masse.rand,
          nachX: a.nachX + versatzX,
          nachY: a.nachY + masse.rand,
        )
    ],
    baender: [
      for (final p in partnerbaender)
        Partnerband(p.vonX + versatzX, p.nachX + versatzX, p.y + masse.rand)
    ],
    breite: maxX - minX + 2 * masse.rand,
    hoehe: maxY + masse.rand + masse.randUnten,
    stammX: (nachId[geflecht.fokus]?.mitteX ?? 0) + versatzX,
  );
}

bool _gleich<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

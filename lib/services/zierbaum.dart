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

import 'package:kern/services/stammbaum.dart';

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
  int get hashCode => Object.hash(
    breite,
    hoehe,
    stammX,
    schilder.length,
    aeste.length,
    baender.length,
  );
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
///
/// **Symmetrisch um den Stamm.** Der Baum teilt sich an einer Stelle in
/// eine linke und eine rechte Familie (siehe [_aufteilung]): beim Paar in
/// der Mitte zwischen den beiden Partnern, sonst bei den Eltern zwischen
/// Vater- und Mutterseite. Was darunter liegt, steht senkrecht über dem
/// Stamm – die Person in der Mitte und ihre Eltern, solange sie nur eine
/// Linie haben. Die Geschwister verteilen sich auf beide Seiten, und die
/// Fläche reicht nach links und rechts gleich weit. Vorher teilte sich der
/// Baum nur bei einem Paar; ohne Partner stand alles, wohin die Wünsche
/// der Nachbarn es schoben, und der Stamm einer kleinen Familie rückte an
/// den Rand einer grossen.
Zierbaumplan zierbaumplan(
  Stammbaumgeflecht geflecht, {
  Zierbaummasse masse = const Zierbaummasse(),
}) {
  final baender =
      geflecht.haushalte.map((h) => geflecht.band[h.id]!).toSet().toList()
        ..sort();
  if (baender.isEmpty) {
    return const Zierbaumplan(
      schilder: [],
      aeste: [],
      baender: [],
      breite: 0,
      hoehe: 0,
      stammX: 0,
    );
  }

  final fokusHaus = geflecht.haushaltVon(geflecht.fokus)!;
  final hausVon = <String, Haushalt>{
    for (final h in geflecht.haushalte)
      for (final person in h.personen) person: h,
  };
  final rang = {for (final (i, h) in geflecht.haushalte.indexed) h.id: i};
  final kinderVon = <String, List<String>>{};
  for (final e in geflecht.elternhaeuserVon.entries) {
    for (final haus in e.value) {
      kinderVon.putIfAbsent(haus, () => []).add(e.key);
    }
  }

  /// Die Bewohner, wie sie nebeneinander stehen.
  ///
  /// Im Haus der Mitte steht die Person in der Mitte rechts, der Stamm
  /// wächst unter ihr. Links vom Stamm ist jeder Haushalt gespiegelt: Dort
  /// steht der Verwandte innen und der Angeheiratete aussen, genau wie
  /// rechts – sonst stünde der Schwager zwischen der Schwester und ihren
  /// Eltern, und sein Ast liefe quer über ihren.
  List<String> folge(Haushalt h, Map<String, int> seiten) {
    if (h.id == fokusHaus.id && h.personen.length > 1) {
      return [
        ...h.personen.where((person) => person != geflecht.fokus),
        geflecht.fokus,
      ];
    }
    if ((seiten[h.id] ?? 0) < 0) return h.personen.reversed.toList();
    return h.personen;
  }

  final aufteilung = _aufteilung(
    geflecht,
    fokusHaus,
    hausVon: hausVon,
    kinderVon: kinderVon,
    rang: rang,
    folge: (h) => folge(h, const {}),
  );
  final seiten = aufteilung.seiten;
  int seiteVon(String hausId) => seiten[hausId] ?? 0;
  final folgeVon = {for (final h in geflecht.haushalte) h.id: folge(h, seiten)};

  /// Wo ein Bewohner steht, gemessen von der Mitte seines Haushalts.
  double versatzIm(String hausId, String person) {
    final f = folgeVon[hausId]!;
    return -masse.haushaltBreite(f.length) / 2 +
        f.indexOf(person) * (masse.schildBreite + masse.partnerLuecke) +
        masse.schildBreite / 2;
  }

  // Die Achse steht fest: jedes Haus genau über dem Bewohner darunter,
  // dessen Eltern es sind.
  final fest = <String, double>{fokusHaus.id: 0};
  for (final (:haus, :ueber) in aufteilung.achse) {
    final darunter = hausVon[ueber]!.id;
    fest[haus] = fest[darunter]! + versatzIm(darunter, ueber);
  }
  final trennHaus = aufteilung.trennHaus;
  final trennPerson = aufteilung.trennPerson;
  final trennX = trennHaus == null
      ? 0.0
      : fest[trennHaus]! +
            (trennPerson == null ? 0 : versatzIm(trennHaus, trennPerson));

  // Haushalt -> Mitte.
  final mitte = <String, double>{};

  /// Wo ein Haushalt nach seinen schon gesetzten Nachbarn stehen möchte.
  ///
  /// Je **Person** gerechnet, nicht je Haushalt: Die Eltern des Schwagers
  /// gehören über den Schwager, nicht über die Mitte des Hauses, in dem
  /// er mit der Schwester wohnt. Sonst entscheidet bei zwei Elternhäusern
  /// über einem Paar nur die Reihenfolge im Bestand, welches links steht,
  /// und die Äste kreuzen sich.
  double? wunschFuer(Haushalt h) {
    final werte = <double>[];
    for (final person in h.personen) {
      for (final elternhaus in geflecht.elternhaeuserVon[person] ?? const []) {
        final x = mitte[elternhaus];
        if (x != null) werte.add(x - versatzIm(h.id, person));
      }
    }
    for (final kind in kinderVon[h.id] ?? const <String>[]) {
      final kindHaus = hausVon[kind]!.id;
      final x = mitte[kindHaus];
      if (x != null) werte.add(x + versatzIm(kindHaus, kind));
    }
    if (werte.isEmpty) return null;
    return werte.reduce((a, b) => a + b) / werte.length;
  }

  /// Setzt ein Band: links, Mitte, rechts, innerhalb der Seiten nach
  /// Wunsch, und so nah an den Wünschen, wie es ohne Überschneidung geht.
  ///
  /// Der Sortierschlüssel ist innerhalb einer Seite der Wunsch, nicht die
  /// Reihenfolge im Bestand: Sonst kreuzten sich die Kanten mehr als
  /// nötig. Bei gleichem Wunsch entscheidet die Reihenfolge – ohne sie
  /// sprängen zwei Haushalte bei jedem Aufbau umeinander.
  void setze(List<Haushalt> haushalte) {
    if (haushalte.isEmpty) return;
    final wunsch = {
      for (final h in haushalte) h.id: fest[h.id] ?? wunschFuer(h) ?? trennX,
    };
    final ordnung = [...haushalte]
      ..sort((a, b) {
        final s = seiteVon(a.id).compareTo(seiteVon(b.id));
        if (s != 0) return s;
        final w = wunsch[a.id]!.compareTo(wunsch[b.id]!);
        if (w != 0) return w;
        return rang[a.id]!.compareTo(rang[b.id]!);
      });
    // Steht ein Haus der Achse im Band, hält schon die Reihenfolge die
    // Seiten auseinander. Sonst die Trennlinie: Kein Haus der linken
    // Familie rückt über sie hinweg nach rechts und umgekehrt.
    final mitAchse = ordnung.any((h) => fest.containsKey(h.id));
    final halb = [
      for (final h in ordnung) masse.haushaltBreite(h.personen.length) / 2,
    ];
    final unten = <double>[];
    final oben = <double>[];
    for (final (i, h) in ordnung.indexed) {
      final f = fest[h.id];
      var u = double.negativeInfinity;
      var o = double.infinity;
      if (f != null) {
        u = f;
        o = f;
      } else if (!mitAchse) {
        final seite = seiteVon(h.id);
        if (seite < 0) o = trennX - masse.haushaltLuecke / 2 - halb[i];
        if (seite > 0) u = trennX + masse.haushaltLuecke / 2 + halb[i];
      }
      unten.add(u);
      oben.add(o);
    }
    final xs = _reihe(
      wunsch: [for (final h in ordnung) wunsch[h.id]!],
      // Die Mitte hält, die Seiten weichen: Ein Kind unter der Person in
      // der Mitte wurde sonst von einer kinderreichen Familie daneben weit
      // zur Seite gezogen, weil jedes Haus gleich viel zählte.
      gewicht: [for (final h in ordnung) seiteVon(h.id) == 0 ? 100.0 : 1.0],
      halb: halb,
      unten: unten,
      oben: oben,
      luecke: masse.haushaltLuecke,
    );
    for (final (i, h) in ordnung.indexed) {
      mitte[h.id] = xs[i];
    }
  }

  // Das Band der Mitte zuerst, dann nach aussen: Jedes weitere Band
  // richtet sich an dem aus, das schon steht.
  final nullBand = geflecht.band[fokusHaus.id]!;
  setze(geflecht.imBand(nullBand));
  for (final b in baender.where((b) => b < nullBand).toList().reversed) {
    setze(geflecht.imBand(b));
  }
  for (final b in baender.where((b) => b > nullBand)) {
    setze(geflecht.imBand(b));
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
    final reihenfolgeDerBaender = runde.isEven
        ? baender
        : baender.reversed.toList();
    for (final b in reihenfolgeDerBaender) {
      setze(geflecht.imBand(b));
    }
  }

  // Unter der Mitte gilt dieselbe Regel wie links vom Stamm: Ein Kind
  // mit Partner, das links vom Stamm steht, steht innen und sein Partner
  // aussen. Erst nach dem Setzen entscheidbar – vorher weiss niemand, auf
  // welcher Seite des Stammes es landet.
  final stammImHaus = versatzIm(fokusHaus.id, geflecht.fokus);
  for (final h in geflecht.haushalte) {
    if (seiteVon(h.id) != 0 || h.personen.length < 2) continue;
    if (geflecht.band[h.id]! <= nullBand) continue;
    if (mitte[h.id]! < stammImHaus) {
      folgeVon[h.id] = h.personen.reversed.toList();
    }
  }

  // Aus den Mitten die Schilder. Y ergibt sich allein aus dem Band.
  final obenBand = baender.first;
  double bandY(int b) =>
      (b - obenBand) * (masse.schildHoehe + masse.bandLuecke);

  final schilder = <Schild>[];
  final partnerbaender = <Partnerband>[];
  for (final h in geflecht.haushalte) {
    final b = geflecht.band[h.id]!;
    final gesamt = masse.haushaltBreite(h.personen.length);
    var x = mitte[h.id]! - gesamt / 2;
    final y = bandY(b);
    Schild? voriges;
    for (final person in folgeVon[h.id]!) {
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
      aeste.add(
        Ast(
          personId: e.key,
          vonX: schild.mitteX,
          vonY: schild.oben,
          nachX: zielX,
          nachY: zielY,
        ),
      );
    }
  }

  // Alles in den sichtbaren Bereich schieben – und zwar so, dass links
  // und rechts vom Stamm gleich viel Fläche liegt. Hat eine Seite mehr
  // Verwandte, bleibt auf der anderen Grund stehen; der Stamm steht in
  // der Mitte des Bildes, auf dem Bildschirm wie auf der Tafel.
  final stamm = nachId[geflecht.fokus]?.mitteX ?? 0;
  final minX = schilder.map((s) => s.links).reduce(math.min);
  final maxX = schilder.map((s) => s.rechts).reduce(math.max);
  final maxY = schilder.map((s) => s.unten).reduce(math.max);
  final halbeBreite = math.max(stamm - minX, maxX - stamm);
  final versatzX = masse.rand + halbeBreite - stamm;

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
        ),
    ],
    baender: [
      for (final p in partnerbaender)
        Partnerband(p.vonX + versatzX, p.nachX + versatzX, p.y + masse.rand),
    ],
    breite: 2 * halbeBreite + 2 * masse.rand,
    hoehe: maxY + masse.rand + masse.randUnten,
    stammX: stamm + versatzX,
  );
}

/// Setzt Haushalte in fester Reihenfolge auf eine Linie: jeden so nah an
/// seinem Wunsch, wie es die Lücken zu den Nachbarn und seine Grenzen
/// erlauben.
///
/// Das ist eine Ausgleichsrechnung mit Reihenfolge (Pool Adjacent
/// Violators): Rechnet man die Mindestabstände heraus, müssen die Plätze
/// nur noch aufsteigen. Wer seinen Nachbarn überholen will, wird mit ihm
/// zu einem Block, und der Block steht am gewichteten Mittel der Wünsche. Der frühere
/// Schub nach rechts mit anschliessendem Zurückziehen kam auf dasselbe,
/// solange niemand eine Grenze hatte; mit Grenzen stand ein Band danach
/// schief.
List<double> _reihe({
  required List<double> wunsch,
  required List<double> gewicht,
  required List<double> halb,
  required List<double> unten,
  required List<double> oben,
  required double luecke,
}) {
  final n = wunsch.length;
  final versatz = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    versatz[i] = versatz[i - 1] + halb[i - 1] + luecke + halb[i];
  }
  final bloecke = <_Block>[];
  for (var i = 0; i < n; i++) {
    var block = _Block(
      bis: i,
      summe: (wunsch[i] - versatz[i]) * gewicht[i],
      anzahl: gewicht[i],
      unten: unten[i] - versatz[i],
      oben: oben[i] - versatz[i],
    );
    while (bloecke.isNotEmpty && bloecke.last.wert > block.wert) {
      block = bloecke.removeLast().mit(block);
    }
    bloecke.add(block);
  }
  final ergebnis = List<double>.filled(n, 0);
  var von = 0;
  for (final block in bloecke) {
    for (var i = von; i <= block.bis; i++) {
      ergebnis[i] = block.wert + versatz[i];
    }
    von = block.bis + 1;
  }
  return ergebnis;
}

class _Block {
  final int bis;
  final double summe;
  final double anzahl;
  final double unten;
  final double oben;

  const _Block({
    required this.bis,
    required this.summe,
    required this.anzahl,
    required this.unten,
    required this.oben,
  });

  /// Das Mittel der Wünsche, in die Grenzen gerückt. Widersprechen sich
  /// die Grenzen, gewinnt die untere – überlappen darf trotzdem nichts.
  double get wert => math.max(unten, math.min(oben, summe / anzahl));

  _Block mit(_Block rechts) => _Block(
    bis: rechts.bis,
    summe: summe + rechts.summe,
    anzahl: anzahl + rechts.anzahl,
    unten: math.max(unten, rechts.unten),
    oben: math.min(oben, rechts.oben),
  );
}

/// Wie sich der Baum auf links und rechts verteilt.
class _Aufteilung {
  /// Haushalt -> -1 (links) oder 1 (rechts). Wer fehlt, steht in der
  /// Mitte: das Haus der Person in der Mitte, die Achse darüber und alle
  /// Nachkommen darunter.
  final Map<String, int> seiten;

  /// Die Häuser senkrecht über der Mitte, von unten nach oben – je mit
  /// der Person im Haus darunter, deren Eltern sie sind.
  final List<({String haus, String ueber})> achse;

  /// Wo sich links und rechts trennen: in einem Haus der Achse zwischen
  /// seinen Bewohnern oder, wenn [trennPerson] gesetzt ist, zwischen den
  /// getrennt lebenden Eltern dieser Person. `null`, wenn sich nichts
  /// trennt – dann stehen auch keine zwei Familien nebeneinander.
  final String? trennHaus;
  final String? trennPerson;

  const _Aufteilung({
    required this.seiten,
    required this.achse,
    required this.trennHaus,
    required this.trennPerson,
  });
}

/// Teilt den Baum in eine linke und eine rechte Familie.
///
/// Von der Person in der Mitte aus nach oben, bis zur ersten Stelle, an
/// der zwei Familienlinien zusammentreffen:
///
/// - **Ein Paar, bei dem beide Eltern im Bild haben.** Die Familie des
///   Partners geht nach links, die eigene nach rechts – in der Reihenfolge,
///   in der die beiden nebeneinander stehen.
/// - **Getrennt lebende Eltern.** Das erste Elternhaus links, das zweite
///   rechts.
/// - **Eltern in einem Haus.** Ihr Haus steht über dem Kind, und die
///   Teilung rückt eine Generation höher: die Eltern des Vaters links, die
///   der Mutter rechts.
///
/// Die Zuordnung läuft danach entlang der Eltern-Kind-Verbindungen weiter:
/// Geschwister mit ihren Partnern bleiben bei der Familie, aus der sie
/// stammen; ihre Schwiegerfamilien bei ihnen. Die Häuser der Achse werden
/// dabei nicht durchlaufen, sonst fielen die beiden Linien wieder
/// zusammen.
///
/// Die Geschwister an der Achse – die der Person in der Mitte, wenn ihre
/// Eltern über ihr stehen – gehören zu beiden Seiten. Sie werden so
/// verteilt, dass beide Seiten ungefähr gleich viel tragen: das schwerste
/// zuerst auf die leichtere Seite, bei Gleichstand die älteren links.
_Aufteilung _aufteilung(
  Stammbaumgeflecht geflecht,
  Haushalt fokusHaus, {
  required Map<String, Haushalt> hausVon,
  required Map<String, List<String>> kinderVon,
  required Map<String, int> rang,
  required List<String> Function(Haushalt h) folge,
}) {
  const links = -1;
  const rechts = 1;
  final hausNachId = {for (final h in geflecht.haushalte) h.id: h};
  final seiten = <String, int>{};
  final achse = <({String haus, String ueber})>[];
  final aufAchse = <String>{fokusHaus.id};
  String? trennHaus;
  String? trennPerson;

  /// Die Häuser, die von [hausId] aus erreichbar sind: die Eltern jedes
  /// Bewohners und die Kinder des Hauses.
  Iterable<String> nachbarn(String hausId) sync* {
    for (final person in hausNachId[hausId]!.personen) {
      yield* geflecht.elternhaeuserVon[person] ?? const <String>[];
    }
    for (final kind in kinderVon[hausId] ?? const <String>[]) {
      yield hausVon[kind]!.id;
    }
  }

  void verteile(String start, int seite) {
    if (aufAchse.contains(start) || seiten.containsKey(start)) return;
    seiten[start] = seite;
    final wartend = [start];
    while (wartend.isNotEmpty) {
      for (final n in nachbarn(wartend.removeLast())) {
        if (aufAchse.contains(n) || seiten.containsKey(n)) continue;
        seiten[n] = seite;
        wartend.add(n);
      }
    }
  }

  var haus = fokusHaus;
  while (true) {
    final mitEltern = [
      for (final person in folge(haus))
        if ((geflecht.elternhaeuserVon[person] ?? const []).isNotEmpty) person,
    ];
    if (mitEltern.isEmpty) break;
    if (mitEltern.length > 1) {
      trennHaus = haus.id;
      final aufLinks = <String>[];
      final aufRechts = <String>[];
      for (final (i, person) in mitEltern.indexed) {
        (i < mitEltern.length / 2 ? aufLinks : aufRechts).addAll(
          geflecht.elternhaeuserVon[person]!,
        );
      }
      for (final h in aufLinks) {
        verteile(h, links);
      }
      for (final h in aufRechts) {
        verteile(h, rechts);
      }
      break;
    }
    final person = mitEltern.single;
    final elternhaeuser = geflecht.elternhaeuserVon[person]!;
    if (elternhaeuser.length > 1) {
      trennHaus = haus.id;
      trennPerson = person;
      for (final (i, h) in elternhaeuser.indexed) {
        verteile(h, i == 0 ? links : rechts);
      }
      break;
    }
    final oben = elternhaeuser.single;
    if (aufAchse.contains(oben)) break;
    achse.add((haus: oben, ueber: person));
    aufAchse.add(oben);
    haus = hausNachId[oben]!;
  }

  // Die Geschwister an der Achse: die übrigen Kinder jedes Hauses über
  // ihr. Die Kinder des Hauses in der Mitte sind keine – sie hängen als
  // Nachkommen mittig darunter.
  final geschwister = <({String haus, String neben})>[];
  for (final (:haus, :ueber) in achse) {
    for (final kind in kinderVon[haus] ?? const <String>[]) {
      final kindHaus = hausVon[kind]!.id;
      if (aufAchse.contains(kindHaus) || seiten.containsKey(kindHaus)) {
        continue;
      }
      if (geschwister.any((g) => g.haus == kindHaus)) continue;
      geschwister.add((haus: kindHaus, neben: hausVon[ueber]!.id));
    }
  }
  if (geschwister.isEmpty) {
    return _Aufteilung(
      seiten: seiten,
      achse: achse,
      trennHaus: trennHaus,
      trennPerson: trennPerson,
    );
  }

  // Wie viel jedes Geschwister mitbringt: alles, was von ihm aus
  // erreichbar und noch keiner Seite zugeordnet ist.
  final frei = {for (final g in geschwister) g.haus};
  int gewicht(String start) {
    final gesehen = {start};
    final wartend = [start];
    while (wartend.isNotEmpty) {
      for (final n in nachbarn(wartend.removeLast())) {
        if (aufAchse.contains(n) || seiten.containsKey(n)) continue;
        if (frei.contains(n) && n != start) continue;
        if (gesehen.add(n)) wartend.add(n);
      }
    }
    return gesehen.length;
  }

  final gewichte = {for (final g in geschwister) g.haus: gewicht(g.haus)};
  final summe = {links: 0, rechts: 0};
  for (final h in seiten.entries) {
    summe[h.value] = summe[h.value]! + 1;
  }
  final reihe = [...geschwister]
    ..sort((a, b) {
      final w = gewichte[b.haus]!.compareTo(gewichte[a.haus]!);
      if (w != 0) return w;
      return rang[a.haus]!.compareTo(rang[b.haus]!);
    });
  for (final g in reihe) {
    final int seite;
    if (summe[links]! != summe[rechts]!) {
      seite = summe[links]! < summe[rechts]! ? links : rechts;
    } else {
      seite = rang[g.haus]! < rang[g.neben]! ? links : rechts;
    }
    verteile(g.haus, seite);
    summe[seite] = summe[seite]! + gewichte[g.haus]!;
  }

  return _Aufteilung(
    seiten: seiten,
    achse: achse,
    trennHaus: trennHaus,
    trennPerson: trennPerson,
  );
}

bool _gleich<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

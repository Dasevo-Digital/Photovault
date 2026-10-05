/// Die Bildvorlagen des Lebensbaums – und wer auf welchem Schild steht.
///
/// Der Lebensbaum ist ein fertiges Bild: ein gemalter Baum mit leeren
/// Schildern, wie eine gedruckte Stammbaumtafel. Die App schreibt nur die
/// Namen hinein. Die Schilder stehen deshalb fest, und der Baum der
/// Familie muss sich auf sie verteilen.
///
/// Das macht [belegeVorlage]: Sie nimmt den Plan aus [lebensbaumplan] als
/// Vorbild, wie der Baum ideal aussähe, und sucht für jede Person das
/// Schild, das ihrem idealen Platz am nächsten liegt – alle zugleich, so
/// dass die Summe der Abweichungen am kleinsten wird. Die Linie des Vaters
/// bleibt so links, die der Mutter rechts, und jede Generation steht über
/// der vorigen, soweit die Schilder es hergeben.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'lebensbaum.dart';

/// Die Bilder, nach den Vorlagen gedruckter Stammbaumtafeln: Pergament
/// mit Namensrollen, ein Nadelbaum vor Bergen, die heraldische Tafel mit
/// Wappenschilden und ein Laubbaum mit Goldornamenten. Den letzten gibt
/// es nur als grosse Tafel.
enum Lebensbaumstil { pergament, landschaft, wappen, gold }

/// Ein Schild im Bild, in Bildpunkten der Vorlage.
class Vorlagenfeld {
  /// Das ganze Schild – die Fläche zum Antippen.
  final Rect rahmen;

  /// Der freie Grund darin, auf den geschrieben wird. Ohne Zierkante,
  /// Nagel und Rand.
  final Rect schrift;

  const Vorlagenfeld(this.rahmen, this.schrift);

  /// Ein Schild, dessen Schriftfläche um Anteile seiner Grösse eingerückt
  /// ist – links und rechts gleich, oben und unten je für sich.
  Vorlagenfeld.eingerueckt(
    this.rahmen, {
    required double seite,
    required double oben,
    required double unten,
  }) : schrift = Rect.fromLTRB(
         rahmen.left + rahmen.width * seite,
         rahmen.top + rahmen.height * oben,
         rahmen.right - rahmen.width * seite,
         rahmen.bottom - rahmen.height * unten,
       );
}

/// Ein Bild samt seinen Schildern.
class Lebensbaumvorlage {
  final Lebensbaumstil stil;

  /// Das Bild als Asset.
  final String bild;

  /// Die Grösse des Bildes; alle Rechtecke beziehen sich darauf.
  final Size groesse;

  /// Das Schild am Fuss des Stamms: die Person, um die es geht – in den
  /// Nachkommen mit ihrem Partner.
  final Vorlagenfeld wurzel;

  /// Alle anderen Schilder, ohne Reihenfolge.
  final List<Vorlagenfeld> felder;

  /// Wo der Familienname steht, in Schreibschrift.
  final Rect titel;

  /// Eine zweite Zeile unter dem Titel, wenn das Bild Platz dafür hat.
  final Rect? untertitel;

  final Color schrift;
  final Color nebenschrift;

  const Lebensbaumvorlage({
    required this.stil,
    required this.bild,
    required this.groesse,
    required this.wurzel,
    required this.felder,
    required this.titel,
    required this.schrift,
    required this.nebenschrift,
    this.untertitel,
  });

  /// Die Person an [stelle], oder `null`.
  String? personBei(Lebensbaumbelegung belegung, Offset stelle) {
    for (final MapEntry(key: i, value: id) in belegung.felder.entries) {
      if (felder[i].rahmen.contains(stelle)) return id;
    }
    for (final (i, r) in wurzelflaechen(belegung).indexed) {
      if (r.contains(stelle)) return belegung.wurzel[i];
    }
    return null;
  }

  /// Die Flächen am Stamm, eine je Person: Steht dort ein Paar, teilt es
  /// sich das Schild, oben die Person, unten der Partner.
  List<Rect> wurzelflaechen(Lebensbaumbelegung belegung) {
    final r = wurzel.rahmen;
    if (belegung.wurzel.length < 2) return [r];
    return [
      Rect.fromLTRB(r.left, r.top, r.right, r.center.dy),
      Rect.fromLTRB(r.left, r.center.dy, r.right, r.bottom),
    ];
  }
}

/// Unter dieser halben Breite (in Schildern samt Abstand) rückt eine
/// schmale Familie nicht an den Rand, sondern bleibt in der Mitte.
const _vorlagenHalbbreite = 1.0;

Vorlagenfeld _rolle(double l, double t, double r, double b) =>
    Vorlagenfeld.eingerueckt(
      Rect.fromLTRB(l, t, r, b),
      seite: 0.1,
      oben: 0.3,
      unten: 0.1,
    );

Vorlagenfeld _tafel(double l, double t, double r, double b) =>
    Vorlagenfeld.eingerueckt(
      Rect.fromLTRB(l, t, r, b),
      seite: 0.08,
      oben: 0.16,
      unten: 0.12,
    );

Vorlagenfeld _wappen(double l, double t, double r, double b) =>
    Vorlagenfeld.eingerueckt(
      Rect.fromLTRB(l, t, r, b),
      seite: 0.16,
      oben: 0.2,
      unten: 0.27,
    );

/// Die Rollen auf dem Laub. Drei Schilder sind Kopien eines der
/// gemalten – links und rechts aussen und eins mitten am Stamm –, damit
/// vier Generationen Vorfahren ganz Platz finden (1 + 2 + 4 + 8).
final _pergament = Lebensbaumvorlage(
  stil: Lebensbaumstil.pergament,
  bild: 'assets/lebensbaum/pergament.jpg',
  groesse: const Size(1024, 1024),
  wurzel: const Vorlagenfeld(
    Rect.fromLTRB(440, 597, 582, 718),
    Rect.fromLTRB(452, 624, 570, 690),
  ),
  felder: [
    _rolle(440, 100, 590, 197),
    _rolle(346, 205, 489, 300),
    _rolle(546, 208, 687, 300),
    _rolle(167, 338, 326, 432),
    _rolle(716, 338, 872, 433),
    _rolle(446, 388, 584, 474),
    _rolle(54, 472, 186, 554),
    _rolle(205, 457, 357, 550),
    _rolle(668, 457, 821, 550),
    _rolle(838, 472, 970, 554),
    _rolle(125, 597, 272, 690),
    _rolle(300, 612, 436, 705),
    _rolle(583, 612, 717, 705),
    _rolle(748, 597, 892, 690),
  ],
  titel: const Rect.fromLTRB(300, 930, 724, 1004),
  schrift: const Color(0xFF4A3218),
  nebenschrift: const Color(0xFF7A5A32),
);

/// Die Täfelchen am Nadelbaum. Zwei sind Kopien, an den äussersten
/// Ästen.
final _landschaft = Lebensbaumvorlage(
  stil: Lebensbaumstil.landschaft,
  bild: 'assets/lebensbaum/landschaft.jpg',
  groesse: const Size(1024, 1024),
  wurzel: const Vorlagenfeld(
    Rect.fromLTRB(418, 688, 575, 825),
    Rect.fromLTRB(438, 712, 555, 806),
  ),
  felder: [
    _tafel(450, 185, 548, 232),
    _tafel(383, 252, 477, 305),
    _tafel(514, 252, 616, 305),
    // Das Medaillon: rund, beschrieben wird das Quadrat darin.
    const Vorlagenfeld(
      Rect.fromLTRB(466, 304, 530, 362),
      Rect.fromLTRB(472, 310, 524, 350),
    ),
    _tafel(317, 315, 413, 368),
    _tafel(600, 315, 697, 368),
    _tafel(257, 402, 343, 462),
    _tafel(350, 402, 430, 462),
    _tafel(445, 400, 545, 466),
    _tafel(557, 402, 645, 462),
    _tafel(660, 402, 741, 462),
    _tafel(221, 485, 309, 545),
    _tafel(393, 508, 480, 550),
    _tafel(510, 508, 598, 550),
    _tafel(692, 485, 780, 545),
  ],
  titel: const Rect.fromLTRB(356, 872, 668, 922),
  schrift: const Color(0xFF3A2C18),
  nebenschrift: const Color(0xFF6E5A36),
);

/// Die heraldische Tafel: zwanzig Wappenschilde, der Name am Fuss, der
/// Titel in der Kartusche.
final _wappenTafel = Lebensbaumvorlage(
  stil: Lebensbaumstil.wappen,
  bild: 'assets/lebensbaum/wappen.jpg',
  groesse: const Size(1024, 1024),
  wurzel: const Vorlagenfeld(
    Rect.fromLTRB(325, 878, 690, 940),
    Rect.fromLTRB(352, 888, 664, 934),
  ),
  felder: [
    _wappen(303, 295, 387, 378),
    _wappen(405, 295, 482, 378),
    _wappen(528, 295, 606, 378),
    _wappen(633, 295, 712, 378),
    _wappen(187, 400, 285, 490),
    _wappen(297, 397, 392, 488),
    _wappen(395, 400, 492, 495),
    _wappen(523, 395, 630, 488),
    _wappen(635, 397, 725, 485),
    _wappen(735, 415, 845, 490),
    _wappen(130, 500, 225, 585),
    _wappen(300, 492, 420, 588),
    _wappen(624, 490, 745, 588),
    _wappen(805, 500, 897, 590),
    _wappen(133, 605, 228, 690),
    _wappen(238, 600, 347, 692),
    _wappen(350, 600, 462, 690),
    _wappen(578, 600, 692, 692),
    _wappen(690, 600, 792, 692),
    _wappen(797, 600, 897, 692),
  ],
  titel: const Rect.fromLTRB(452, 112, 570, 150),
  untertitel: const Rect.fromLTRB(462, 150, 560, 170),
  schrift: const Color(0xFF3E2A16),
  nebenschrift: const Color(0xFF6B5034),
);

/// Ein Schild, von dem der helle Grund bekannt ist: Darauf wird
/// geschrieben, mit etwas Abstand zum Rand; getippt werden darf auch auf
/// den Rahmen ringsum.
Vorlagenfeld _innen(double l, double t, double r, double b) => Vorlagenfeld(
  Rect.fromLTRB(l - 8, t - 8, r + 8, b + 6),
  Rect.fromLTRB(l + 5, t + 3, r - 5, b - 3),
);

/// Die Schilder der grossen Tafeln: eine volle Ahnentafel über fünf
/// Generationen, 2, 4, 8 und 16 Schilder in vier Reihen. Alle drei
/// Bilder sind nach derselben Vorlage gemalt und teilen sie.
final _grosseFelder = [
  _innen(52, 278, 140, 343),
  _innen(163, 271, 250, 341),
  _innen(272, 267, 361, 335),
  _innen(383, 263, 475, 338),
  _innen(498, 259, 598, 337),
  _innen(621, 257, 722, 337),
  _innen(746, 254, 854, 336),
  _innen(877, 253, 987, 336),
  _innen(1012, 253, 1124, 336),
  _innen(1148, 254, 1254, 336),
  _innen(1278, 255, 1379, 336),
  _innen(1402, 258, 1501, 338),
  _innen(1524, 263, 1616, 339),
  _innen(1639, 266, 1728, 339),
  _innen(1750, 271, 1836, 341),
  _innen(1859, 278, 1947, 344),
  _innen(136, 472, 275, 549),
  _innen(330, 467, 492, 549),
  _innen(552, 462, 714, 545),
  _innen(780, 461, 939, 544),
  _innen(1061, 461, 1220, 544),
  _innen(1287, 461, 1447, 544),
  _innen(1507, 466, 1669, 549),
  _innen(1725, 472, 1862, 549),
  _innen(454, 645, 638, 734),
  _innen(727, 645, 906, 733),
  _innen(1104, 645, 1282, 733),
  _innen(1365, 645, 1547, 734),
  _innen(624, 848, 819, 941),
  _innen(1180, 848, 1376, 940),
];

Lebensbaumvorlage _gross(
  Lebensbaumstil stil,
  String bild,
  Color schrift,
  Color nebenschrift,
) => Lebensbaumvorlage(
  stil: stil,
  bild: bild,
  groesse: const Size(2000, 1333),
  wurzel: const Vorlagenfeld(
    Rect.fromLTRB(863, 882, 1137, 1048),
    Rect.fromLTRB(893, 912, 1107, 1016),
  ),
  felder: _grosseFelder,
  titel: const Rect.fromLTRB(788, 1136, 1208, 1207),
  schrift: schrift,
  nebenschrift: nebenschrift,
);

final _pergamentGross = _gross(
  Lebensbaumstil.pergament,
  'assets/lebensbaum/pergament_gross.jpg',
  _pergament.schrift,
  _pergament.nebenschrift,
);
final _landschaftGross = _gross(
  Lebensbaumstil.landschaft,
  'assets/lebensbaum/landschaft_gross.jpg',
  _landschaft.schrift,
  _landschaft.nebenschrift,
);
final _goldGross = _gross(
  Lebensbaumstil.gold,
  'assets/lebensbaum/gold_gross.jpg',
  _pergament.schrift,
  _pergament.nebenschrift,
);
final _wappenGross = _gross(
  Lebensbaumstil.wappen,
  'assets/lebensbaum/wappen_gross.jpg',
  _wappenTafel.schrift,
  _wappenTafel.nebenschrift,
);

/// Die kleinste Tafel eines Stils.
Lebensbaumvorlage lebensbaumvorlage(Lebensbaumstil stil) =>
    lebensbaumvorlagen(stil).first;

/// Die Tafeln eines Stils, die kleinste zuerst.
List<Lebensbaumvorlage> lebensbaumvorlagen(Lebensbaumstil stil) =>
    switch (stil) {
      Lebensbaumstil.pergament => [_pergament, _pergamentGross],
      Lebensbaumstil.landschaft => [_landschaft, _landschaftGross],
      Lebensbaumstil.wappen => [_wappenTafel, _wappenGross],
      Lebensbaumstil.gold => [_goldGross],
    };

/// Die Tafel, die zur Familie passt, samt Belegung.
///
/// Die kleine, solange alle Platz finden – auf der grossen stünden sonst
/// bei einer kleinen Familie zwei Dutzend leere Schilder. Sonst die
/// grosse, auch wenn selbst sie nicht reicht.
({Lebensbaumvorlage vorlage, Lebensbaumbelegung belegung}) passendeVorlage(
  Lebensbaumplan plan,
  Lebensbaumstil stil,
) {
  late Lebensbaumvorlage vorlage;
  late Lebensbaumbelegung belegung;
  for (vorlage in lebensbaumvorlagen(stil)) {
    belegung = belegeVorlage(plan, vorlage);
    if (belegung.verschwiegen == plan.verschwiegen) break;
  }
  return (vorlage: vorlage, belegung: belegung);
}

/// Wer auf welchem Schild steht.
class Lebensbaumbelegung {
  /// Am Stamm: die Person, in den Nachkommen auch ihr Partner.
  final List<String> wurzel;

  /// Index in [Lebensbaumvorlage.felder] → Person. Leere Schilder fehlen.
  final Map<int, String> felder;

  /// Personen ohne Schild – im Plan schon gezählte eingeschlossen.
  final int verschwiegen;

  const Lebensbaumbelegung({
    required this.wurzel,
    required this.felder,
    required this.verschwiegen,
  });

  /// Alle Personen im Bild.
  Iterable<String> get personen => [...wurzel, ...felder.values];
}

/// Verteilt [plan] auf die Schilder von [vorlage].
///
/// Generation für Generation, von unten nach oben. Die Schilder eines
/// Bildes stehen in Reihen, und jede Generation bekommt die untersten
/// noch freien Reihen, so viele, wie sie braucht – eine Reihe für sich
/// allein, solange danach noch genug Schilder für alle Übrigen bleiben.
/// Erst wenn es eng wird, teilen sich zwei Generationen eine Reihe.
///
/// Innerhalb ihrer Reihen kommt jede Person auf das Schild, das ihrem
/// idealen Platz im Plan am nächsten liegt – alle zugleich, so dass die
/// Summe der Abweichungen am kleinsten wird. Die Linie des Vaters bleibt
/// so links, die der Mutter rechts. Reichen die Schilder nicht, füllt
/// die erste Generation, die nicht mehr ganz passt, die übrigen mit
/// denen, die am besten dorthin passen; wer danach keinen Platz hat, wird
/// gezählt ([Lebensbaumbelegung.verschwiegen]).
Lebensbaumbelegung belegeVorlage(
  Lebensbaumplan plan,
  Lebensbaumvorlage vorlage, {
  Lebensbaummasse masse = const Lebensbaummasse(),
}) {
  final mitte = plan.wurzel.rahmen.center;
  final nachSchluessel = {for (final k in plan.knoten) k.schluessel: k};

  // Die Generationen über dem Stamm, jede Person mit ihrem idealen Platz.
  final generationen = <List<({String id, String knoten, double dx})>>[];
  for (final k in plan.knoten.skip(1)) {
    while (generationen.length < k.stufe) {
      generationen.add([]);
    }
    for (var i = 0; i < k.personen.length; i++) {
      generationen[k.stufe - 1].add((
        id: k.personen[i],
        knoten: k.schluessel,
        dx: k.schilder[i].center.dx - mitte.dx,
      ));
    }
  }

  // Die Seite auf derselben Skala: 0 am Stamm, ±1 am äussersten Rand.
  final einheit = masse.schildBreite + masse.spalte;
  var halbbreite = einheit * _vorlagenHalbbreite;
  for (final g in generationen) {
    for (final p in g) {
      halbbreite = math.max(halbbreite, p.dx.abs());
    }
  }
  final fuss = vorlage.wurzel.rahmen.center;
  final feldDx = [for (final f in vorlage.felder) f.rahmen.center.dx - fuss.dx];
  final feldHoch = [
    for (final f in vorlage.felder) fuss.dy - f.rahmen.center.dy,
  ];
  final breitestes = feldDx.fold(1.0, (m, d) => math.max(m, d.abs()));
  final reihen = _reihen(feldHoch);

  // Ein Schild, das nicht über dem der vorigen Generation liegt, ist
  // teuer, aber nicht verboten – lieber schief als gar nicht. Neben dem
  // Stamm zählt als darüber: Gemalte Reihen sind nicht schnurgerade.
  const nichtDarueber = 2.0;
  // Bei sonst gleichem Abstand das Schild näher am Stamm …
  const zurMitte = 0.05;
  // … und das tiefere: Bleibt unten ein Schild frei, muss es sonst eine
  // spätere Generation nehmen und steht dann unter ihren Kindern.
  const nachUnten = 0.5;
  final hoehenspanne = math.max(
    feldHoch.reduce(math.max) - feldHoch.reduce(math.min),
    1.0,
  );

  final felder = <int, String>{};
  final gesperrt = <int>{};
  final hoeheVon = <String, double>{
    plan.wurzel.schluessel: feldHoch.reduce(math.min) - _reihenAbstand,
  };
  var verschwiegen = plan.verschwiegen;
  var uebrig = generationen.fold(0, (s, g) => s + g.length);
  for (final generation in generationen) {
    uebrig -= generation.length;
    // Die untersten Reihen mit freien Schildern, bis die Generation passt.
    final kandidaten = <int>[];
    final genommen = <List<int>>[];
    for (final r in reihen) {
      if (kandidaten.length >= generation.length) break;
      final frei = [
        for (final f in r)
          if (!felder.containsKey(f) && !gesperrt.contains(f)) f,
      ];
      if (frei.isEmpty) continue;
      kandidaten.addAll(frei);
      genommen.add(frei);
    }
    if (kandidaten.isEmpty) {
      verschwiegen += generation.length;
      continue;
    }
    final spalten = math.max(kandidaten.length, generation.length);
    final unterste = kandidaten.map((f) => feldHoch[f]).reduce(math.min);
    final kosten = <List<double>>[
      for (final p in generation)
        <double>[
          for (var j = 0; j < spalten; j++)
            if (j >= kandidaten.length)
              0.0 // ausserhalb des Bildes
            else
              math.pow(
                    p.dx / halbbreite - feldDx[kandidaten[j]] / breitestes,
                    2,
                  ) +
                  zurMitte * (feldDx[kandidaten[j]] / breitestes).abs() +
                  nachUnten *
                      (feldHoch[kandidaten[j]] - unterste) /
                      hoehenspanne +
                  (feldHoch[kandidaten[j]] + _reihenAbstand >
                          hoeheVon[nachSchluessel[p.knoten]!.vorgaenger]!
                      ? 0
                      : nichtDarueber),
        ],
    ];
    for (final (i, j) in _zuordnung(kosten).indexed) {
      if (j >= kandidaten.length) {
        verschwiegen++;
        continue;
      }
      final p = generation[i];
      final f = kandidaten[j];
      felder[f] = p.id;
      hoeheVon[p.knoten] = math.max(
        hoeheVon[p.knoten] ?? feldHoch[f],
        feldHoch[f],
      );
    }
    // Was in der obersten genommenen Reihe frei blieb, bleibt frei – wenn
    // die übrigen Schilder für alle Übrigen reichen. So beginnt die
    // nächste Generation in einer eigenen Reihe.
    final rest = [
      for (final f in genommen.last)
        if (!felder.containsKey(f)) f,
    ];
    final freiDanach =
        vorlage.felder.length - felder.length - gesperrt.length - rest.length;
    if (freiDanach >= uebrig) gesperrt.addAll(rest);
  }
  return Lebensbaumbelegung(
    wurzel: plan.wurzel.personen,
    felder: felder,
    verschwiegen: verschwiegen,
  );
}

/// So nah beieinander stehen Schilder einer gemalten Reihe höchstens,
/// in Bildpunkten der Höhe.
const _reihenAbstand = 30.0;

/// Fasst Schilder ähnlicher Höhe zu Reihen zusammen, die unterste zuerst.
List<List<int>> _reihen(List<double> hoehe) {
  final folge = [for (var i = 0; i < hoehe.length; i++) i]
    ..sort((a, b) => hoehe[a].compareTo(hoehe[b]));
  final reihen = <List<int>>[];
  for (final i in folge) {
    if (reihen.isNotEmpty &&
        hoehe[i] - hoehe[reihen.last.first] <= _reihenAbstand) {
      reihen.last.add(i);
    } else {
      reihen.add([i]);
    }
  }
  return reihen;
}

/// Die günstigste Zuordnung von Zeilen zu Spalten (ungarische Methode).
///
/// [kosten] hat höchstens so viele Zeilen wie Spalten. Geliefert wird je
/// Zeile ihre Spalte.
List<int> _zuordnung(List<List<double>> kosten) {
  final n = kosten.length;
  final m = kosten.first.length;
  final u = List<double>.filled(n + 1, 0);
  final v = List<double>.filled(m + 1, 0);
  final zeileVon = List<int>.filled(m + 1, 0);
  final weg = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    zeileVon[0] = i;
    var j0 = 0;
    final minimum = List<double>.filled(m + 1, double.infinity);
    final benutzt = List<bool>.filled(m + 1, false);
    do {
      benutzt[j0] = true;
      final i0 = zeileVon[j0];
      var delta = double.infinity;
      var j1 = 0;
      for (var j = 1; j <= m; j++) {
        if (benutzt[j]) continue;
        final rest = kosten[i0 - 1][j - 1] - u[i0] - v[j];
        if (rest < minimum[j]) {
          minimum[j] = rest;
          weg[j] = j0;
        }
        if (minimum[j] < delta) {
          delta = minimum[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= m; j++) {
        if (benutzt[j]) {
          u[zeileVon[j]] += delta;
          v[j] -= delta;
        } else {
          minimum[j] -= delta;
        }
      }
      j0 = j1;
    } while (zeileVon[j0] != 0);
    do {
      final j1 = weg[j0];
      zeileVon[j0] = zeileVon[j1];
      j0 = j1;
    } while (j0 != 0);
  }
  final ergebnis = List<int>.filled(n, -1);
  for (var j = 1; j <= m; j++) {
    if (zeileVon[j] != 0) ergebnis[zeileVon[j] - 1] = j - 1;
  }
  return ergebnis;
}

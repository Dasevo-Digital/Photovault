// Die Netze des Geländes: Blöcke, Gitter und ihr Aufbau (Teil von gelaende.dart).
part of 'gelaende.dart';

/// Ein Stück der Landschaft mit **eigener Textur**.
///
/// **Warum die Landschaft überhaupt zerfällt.** Bis hierher trug sie ein
/// einziges Bild, und dessen Stufe war an die des Höhengitters gekettet:
/// bei der Wanderung durch das Ilsetal Stufe 14, also 5,90 Meter je
/// Bildpunkt. Daher der Brei. Eine einzige Textur der Stufe 18 wären
/// 270 MB in einer Bildfläche – nicht zu halten und nicht anzulegen.
///
/// Also viele kleine. Jeder Block deckt genau **eine Kachel der
/// Grundstufe** ab (siehe [Texturblock]) und wählt seine eigene Stufe
/// nach der Entfernung zur Kamera: nah scharf, fern grob. Geladen wird
/// nur, was zu sehen ist.
///
/// **Jeder Block hat seine eigenen Puffer**, und das ist keine
/// Bequemlichkeit. `ui.Vertices.raw` kopiert die übergebenen Felder nach
/// nativ; ein gemeinsames Feld für alle Blöcke würde bei hundert
/// Zeichenzügen hundertmal vollständig kopiert. Ausserdem verweist
/// Flutter auf Eckpunkte nur mit sechzehn Bit – über 65.536 Eckpunkte
/// hinaus gäbe es keine Zeichenreihenfolge mehr, und je Block sind es
/// wenige hundert.
class Blocknetz {
  /// Welches Kachelrechteck – die Adresse, unter der die Textur liegt.
  final Texturblock block;

  /// Je Eckpunkt drei Zahlen: Ost, Nord, Höhe – alles in Metern,
  /// bezogen auf die Mitte des **ganzen** Ausschnitts.
  final Float32List ecken;

  /// Je Eckpunkt zwei Zahlen: die Stelle auf der Textur **dieses
  /// Blocks**, von 0 bis 1.
  ///
  /// Blocklokal und nicht über den ganzen Ausschnitt: Jeder Block trägt
  /// sein eigenes Bild, und dessen Kanten sind seine Kachelkanten.
  final Float32List texturstellen;

  /// Je Eckpunkt eine Farbe – die Schattierung.
  final Int32List farben;

  /// Je Eckpunkt: wie weit im Inneren des **Ausschnitts** er liegt. 0 am
  /// Rand, 1 innen.
  ///
  /// Gegen den Ausschnitt gerechnet und nicht gegen den Block, sonst
  /// bekäme jeder Block seinen eigenen weichen Saum und die Landschaft
  /// sähe aus wie ein Fliesenspiegel.
  final Float32List randnaehe;

  /// Die Mitte des Blocks in Netzmetern – für die Reihenfolge.
  final double mitteX;
  final double mitteY;

  /// Der Kasten, in dem dieser Block ganz enthalten ist – in Netzmetern.
  ///
  /// Acht Ecken statt hunderter Eckpunkte: Damit lässt sich in einem
  /// Bruchteil der Zeit entscheiden, ob ein Block überhaupt ins Bild
  /// ragt. Siehe [Gelaendemaler.imBild].
  final double westM;
  final double ostM;
  final double suedM;
  final double nordM;
  final double tiefM;
  final double hochM;

  Blocknetz({
    required this.block,
    required this.ecken,
    required this.texturstellen,
    required this.farben,
    required this.randnaehe,
    required this.mitteX,
    required this.mitteY,
    required this.westM,
    required this.ostM,
    required this.suedM,
    required this.nordM,
    required this.tiefM,
    required this.hochM,
  });

  int get eckenzahl => ecken.length ~/ 3;
  int get dreiecke => ecken.length ~/ 9;

  /// Kratzpapier für den Maler.
  ///
  /// Alles hier hängt von der Kamera ab und entsteht in **jedem** Bild
  /// neu – aber es entsteht in denselben Puffern. Am Netz und nicht am
  /// Maler, weil der Maler je Bild neu gebaut wird.
  ///
  /// **Gemessen, warum das nicht egal ist.** Vorher legte der Maler je
  /// Bild eine neue `Float32List` für die Bildstellen (440 KB), eine
  /// Liste von Wahrheitswerten (55 KB) und noch einmal 440 KB für die
  /// Texturstellen an. Bei sechzig Bildern in der Sekunde – und der Flug
  /// ist eine Bewegung – sind das rund sechzig Megabyte Abfall je
  /// Sekunde, den der Aufräumer wieder einsammeln muss.
  late final Int32List dunstfarben = Int32List(eckenzahl);
  late final Float32List tiefen = Float32List(eckenzahl);
  late final Float32List bildstellen = Float32List(eckenzahl * 2);
  late final Uint8List hinterDerKamera = Uint8List(eckenzahl);

  /// Die Zeichenreihenfolge der Eckpunkte – von hinten nach vorn.
  late final Uint16List reihenfolge = Uint16List(eckenzahl);

  /// Zähler für die Eimersortierung, einer je Tiefenstufe plus einer.
  late final Int32List eimer = Int32List(tiefenstufen + 1);

  /// In wie viele Tiefenstufen einsortiert wird.
  ///
  /// Zweitausend bei einer Landschaft von zehn Kilometern sind fünf Meter
  /// je Stufe – feiner, als zwei Dreiecke desselben Gitterfeldes
  /// auseinanderliegen. Innerhalb einer Stufe bleibt die Gitterreihenfolge
  /// erhalten, weil die Zählsortierung sie nicht antastet.
  static const int tiefenstufen = 2048;

  /// Die kleinste und grösste Tiefe der letzten Projektion – der Maler
  /// braucht beide über **alle** Blöcke, damit der Dunst über die ganze
  /// Landschaft dieselbe Skala hat.
  double nahste = double.infinity;
  double fernste = 0;
}

/// Ein Foto, das beim Vorbeifliegen auftaucht.
///
/// Die Stelle steht als **Weg in Metern** und nicht als Koordinate: Wo
/// auf der Spur ein Foto liegt, weiss der Aufrufer besser – er kennt
/// beide. Hier zählt nur, wann es dran ist.
typedef Flugfoto = ({
  /// Wie weit auf der Spur, in Metern von deren Anfang.
  double meter,

  /// Das Bild – als Anbieter und nicht als Datei, damit die Landschaft
  /// nicht wissen muss, wie eine Bibliothek ihre Vorschauen ablegt.
  ImageProvider bild,

  /// Was darunter steht – Uhrzeit oder nichts.
  String? unterschrift,
});

/// Was ausgegeben werden soll – Ziel, Kantenlängen und Dauer.
///
/// **Warum nicht nur eine Datei.** Bis 3.5.1 gab die Ansicht das Video
/// starr in 1920 × 1080 und in der Länge aus, die der Flug auf dem
/// Bildschirm gerade hatte. Beides sind aber Fragen an den, der das
/// Video haben will: Ein Video zum Verschicken darf kleiner sein, eines
/// für einen grossen Bildschirm grösser, und wie lange man zusehen mag,
/// entscheidet nicht die Länge der Wanderung.
typedef Videoauftrag = ({
  File ziel,
  int breite,
  int hoehe,
  Duration dauer,
});

/// Die fertig gerechneten Dreiecke – einmal je Gitter, nicht je Bild.
///
/// Getrennt vom Zeichnen, weil sich beim Drehen nur die Kamera ändert
/// und nicht das Gelände: Das Gitter in jedem Bild neu abzutasten wäre
/// der teuerste Teil, und er ist unnötig.
class Gelaendenetz {
  /// Die Blöcke, zeilenweise von Nordwesten nach Südosten.
  final List<Blocknetz> bloecke;

  /// Die Ausdehnung in Metern – für den Anfangsabstand der Kamera.
  final double breiteMeter;
  final double hoeheMeter;

  /// Der Ausschnitt in Grad – gebraucht, um eine Übersichtskarte auf die
  /// einzelnen Blöcke abzubilden und um Kacheln nachzuladen.
  final double sued;
  final double west;
  final double nord;
  final double ost;

  /// Auf welcher Kachelstufe die Blöcke abgesteckt sind.
  final int grundstufe;

  /// Die Höhe, die als Null gilt – die Mitte zwischen tiefstem und
  /// höchstem Punkt.
  ///
  /// **Steht hier und wird nicht zweimal gerechnet.** Die Spur wird
  /// getrennt vom Netz in Meter umgerechnet und muss denselben Nullpunkt
  /// benutzen; rechnete sie ihn selbst aus einem anders beschnittenen
  /// Gitter, läge der Weg um die Differenz über oder unter dem Boden.
  final double mittlereHoehe;

  Gelaendenetz({
    required this.bloecke,
    required this.mittlereHoehe,
    required this.breiteMeter,
    required this.hoeheMeter,
    required this.sued,
    required this.west,
    required this.nord,
    required this.ost,
    required this.grundstufe,
  });

  int get dreiecke {
    var n = 0;
    for (final b in bloecke) {
      n += b.dreiecke;
    }
    return n;
  }
}

/// Wie viele Blöcke die Landschaft höchstens bekommt.
///
/// Jeder Block ist ein eigener Zeichenzug mit eigenem Shader; die lassen
/// sich nicht zusammenfassen. Hundertvierundvierzig ist die Zahl, bis zu
/// der `tool/messe_gelaendemaler_test.dart` keinen Ausschlag zeigt.
/// Darüber wird die Grundstufe gröber – eine Zwölf-Kilometer-Tour hätte
/// auf Stufe 16 über tausend Blöcke, und die sieht ohnehin niemand aus
/// der Nähe.
const int gelaendeHoechstensBloecke = 144;

/// Die feinste Grundstufe, deren Blockzahl für diesen Ausschnitt noch
/// unter [gelaendeHoechstensBloecke] bleibt.
int passendeGrundstufe({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  int feinste = texturGrundstufe,
}) {
  for (var z = feinste; z > 0; z--) {
    final n = texturbloecke(
            sued: sued, west: west, nord: nord, ost: ost, grundstufe: z)
        .length;
    if (n <= gelaendeHoechstensBloecke) return z;
  }
  return 1;
}

/// Baut die Dreiecke eines Gitters – einen Satz je Block.
///
/// [ueberhoehung] übertreibt die Höhe; siehe [gelaendeUeberhoehung] für
/// den Grund.
///
/// **Das Gitter wird an den Blockgrenzen ausgerichtet und nicht
/// gleichmässig über den Ausschnitt gelegt.** Läge es gleichmässig, ginge
/// eine Masche irgendwo quer über eine Blockgrenze; ihre Texturstellen
/// zeigten dann über den Rand des Blockbildes hinaus, und `TileMode.clamp`
/// zöge dort den letzten Bildpunkt in die Länge – ein Schmierstreifen
/// entlang jeder Blockkante. Deshalb bekommt jeder Block sein eigenes
/// Untergitter, das genau an seinen Kanten anfängt und aufhört.
///
/// **Und deshalb klaffen die Blöcke trotzdem nicht auseinander.** Zwei
/// Nachbarn teilen sich eine Kante; beide tasten das Höhengitter an
/// **denselben** Grad-Koordinaten ab und bekommen damit dieselben Höhen.
/// Innerhalb einer Blockzeile ist auch die Unterteilung dieselbe, weil
/// alle Blöcke der Zeile denselben Breitenbereich haben.
Gelaendenetz baueNetz(
  Hoehengitter gitter, {
  double ueberhoehung = gelaendeUeberhoehung,
  int kante = gelaendeGitterkante,
  Color grundfarbe = gelaendeGrundfarbe,
  Lichtstimmung stimmung = stimmungMittag,
  int? grundstufe,
  double reliefstaerke = 1.0,
}) {
  final mitteBreite = (gitter.nord + gitter.sued) / 2;
  final mLaenge = meterJeGradLaenge(mitteBreite);
  final breiteMeter = (gitter.ost - gitter.west) * mLaenge;
  final hoeheMeter = (gitter.nord - gitter.sued) * meterJeGradBreite;
  final spanne = gitter.spanne;
  final mittlereHoehe = (spanne.tief + spanne.hoch) / 2;

  final stufe = grundstufe ??
      passendeGrundstufe(
          sued: gitter.sued,
          west: gitter.west,
          nord: gitter.nord,
          ost: gitter.ost);
  final bloecke = texturbloecke(
      sued: gitter.sued,
      west: gitter.west,
      nord: gitter.nord,
      ost: gitter.ost,
      grundstufe: stufe);

  // So viele Maschen je Block, dass die Landschaft insgesamt etwa so fein
  // bleibt wie bisher: [kante] Punkte über die längere Seite des
  // Ausschnitts, verteilt auf die Blöcke dieser Seite.
  final spaltenBloecke =
      kachelX(gitter.ost, stufe) - kachelX(gitter.west, stufe) + 1;
  final zeilenBloecke =
      kachelY(gitter.sued, stufe) - kachelY(gitter.nord, stufe) + 1;
  final maschen = math
      .max(2, (kante / math.max(spaltenBloecke, zeilenBloecke)).round())
      .clamp(2, 64);

  /// Wie weit im Inneren des **Ausschnitts** ein Punkt liegt: 0 auf der
  /// Kante, 1 ab einem Zwanzigstel Abstand.
  ///
  /// Ein Zwanzigstel. Ein Zehntel war zu breit: In der Übersicht lag ein
  /// handbreiter weisser Streifen über der Gipfelkette, und der Saum fiel
  /// mehr auf als die harte Kante, die er ersetzen sollte.
  const saumanteil = 1 / 20;
  final saumL = (gitter.ost - gitter.west) * saumanteil;
  final saumB = (gitter.nord - gitter.sued) * saumanteil;
  double innen(double breite, double laenge) {
    final dl = math.min(laenge - gitter.west, gitter.ost - laenge) / saumL;
    final db = math.min(breite - gitter.sued, gitter.nord - breite) / saumB;
    return math.min(dl, db).clamp(0.0, 1.0);
  }

  final netze = <Blocknetz>[];
  for (final b in bloecke) {
    // Der Block, beschnitten auf den Ausschnitt. Ein Block ragt in der
    // Regel darüber hinaus – die Geometrie hört am Ausschnitt auf, die
    // Textur behält ihre vollen Kachelkanten.
    final west = math.max(b.west, gitter.west);
    final ost = math.min(b.ost, gitter.ost);
    final nord = math.min(b.nord, gitter.nord);
    final sued = math.max(b.sued, gitter.sued);
    if (!(ost > west) || !(nord > sued)) continue;

    Raumpunkt punkt(double breite, double laenge) {
      final h = gitter.anOrt(breite, laenge) ?? mittlereHoehe;
      return (
        x: ((laenge - gitter.west) / (gitter.ost - gitter.west) - 0.5) *
            breiteMeter,
        y: (0.5 - (gitter.nord - breite) / (gitter.nord - gitter.sued)) *
            hoeheMeter,
        z: (h - mittlereHoehe) * ueberhoehung,
      );
    }

    // Die Texturstelle: der Nachkommaanteil der Kachelkoordinate auf der
    // Grundstufe. In Mercator gerechnet, weil die Kachel es ist.
    double u(double laenge) => kachelXGenau(laenge, stufe) - b.spalte;
    double v(double breite) => kachelYGenau(breite, stufe) - b.zeile;

    // **Ein beschnittener Block bekommt weniger Maschen.** Der äusserste
    // Block einer Reihe ragt in der Regel über den Ausschnitt hinaus und
    // behält davon manchmal nur ein Zehntel. Bekäme er trotzdem die volle
    // Zahl, lägen seine Maschen zehnmal so dicht wie überall sonst –
    // Dreiecke, die niemand sieht, und ein Saum, der aus lauter winzigen
    // Maschen besteht.
    //
    // Dass die Nachbarn trotzdem zusammenpassen, liegt an der Herkunft
    // der Zahl: Sie hängt allein an der Breite der **Spalte** und der
    // Höhe der **Zeile**, und die sind für alle Blöcke einer Spalte
    // beziehungsweise Zeile dieselben.
    final maschenX =
        math.max(1, (maschen * (ost - west) / (b.ost - b.west)).round());
    final maschenY =
        math.max(1, (maschen * (nord - sued) / (b.nord - b.sued)).round());
    final felder = maschenX * maschenY;
    final ecken = Float32List(felder * 2 * 3 * 3);
    final texturstellen = Float32List(felder * 2 * 3 * 2);
    final farben = Int32List(felder * 2 * 3);
    final randnaehe = Float32List(felder * 2 * 3);

    var e = 0;
    var tz = 0;
    var f = 0;
    void lege(Raumpunkt p, double breite, double laenge, int farbe) {
      ecken[e++] = p.x;
      ecken[e++] = p.y;
      ecken[e++] = p.z;
      texturstellen[tz++] = u(laenge);
      texturstellen[tz++] = v(breite);
      final rand = innen(breite, laenge);
      randnaehe[f] = rand;
      // Die Deckkraft steckt in der Eckpunktfarbe: Am Rand des
      // Ausschnitts wird das Gelände durchsichtig, und der Himmel scheint
      // durch.
      //
      // **Nicht als Dunst darüber, sondern als Durchsichtigkeit.** Der
      // erste Versuch legte den Saum in die Dunstschicht. Das ergab ein
      // weisses Band quer über die Gipfelkette: Der nördliche Rand liegt
      // weit hinten und ragt zwischen den Bergen hervor, und dort war er
      // nicht durchsichtig, sondern weiss angestrichen. Sichtbar wurde es
      // nur am gerenderten Bild.
      farben[f++] =
          (farbe & 0x00FFFFFF) | ((rand * 255).round().clamp(0, 255) << 24);
    }

    double laengeBei(int i) => west + (ost - west) * i / maschenX;
    double breiteBei(int j) => nord - (nord - sued) * j / maschenY;

    for (var j = 0; j < maschenY; j++) {
      final b0 = breiteBei(j);
      final b1 = breiteBei(j + 1);
      for (var i = 0; i < maschenX; i++) {
        final l0 = laengeBei(i);
        final l1 = laengeBei(i + 1);
        final a = punkt(b0, l0);
        final bb = punkt(b0, l1);
        final c = punkt(b1, l0);
        final d = punkt(b1, l1);
        // Zwei Dreiecke je Feld, jedes mit seiner eigenen Schattierung.
        // Eine Schattierung je Eckpunkt sähe weicher aus und verwischte
        // genau die Kanten, die ein Gelände lesbar machen.
        final f1 = _farbe(grundfarbe,
            _gedaempft(schattierung(normale(a, bb, c), stimmung), reliefstaerke),
            stimmung);
        lege(a, b0, l0, f1);
        lege(bb, b0, l1, f1);
        lege(c, b1, l0, f1);
        final f2 = _farbe(grundfarbe,
            _gedaempft(schattierung(normale(bb, d, c), stimmung), reliefstaerke),
            stimmung);
        lege(bb, b0, l1, f2);
        lege(d, b1, l1, f2);
        lege(c, b1, l0, f2);
      }
    }

    final mitte = punkt((nord + sued) / 2, (west + ost) / 2);
    var tiefM = double.infinity;
    var hochM = double.negativeInfinity;
    for (var i = 2; i < ecken.length; i += 3) {
      if (ecken[i] < tiefM) tiefM = ecken[i];
      if (ecken[i] > hochM) hochM = ecken[i];
    }
    final nw = punkt(nord, west);
    final so = punkt(sued, ost);
    netze.add(Blocknetz(
      block: b,
      ecken: ecken,
      texturstellen: texturstellen,
      farben: farben,
      randnaehe: randnaehe,
      mitteX: mitte.x,
      mitteY: mitte.y,
      westM: nw.x,
      ostM: so.x,
      suedM: so.y,
      nordM: nw.y,
      tiefM: tiefM,
      hochM: hochM,
    ));
  }

  return Gelaendenetz(
    bloecke: netze,
    mittlereHoehe: mittlereHoehe,
    breiteMeter: breiteMeter,
    hoeheMeter: hoeheMeter,
    sued: gitter.sued,
    west: gitter.west,
    nord: gitter.nord,
    ost: gitter.ost,
    grundstufe: stufe,
  );
}

/// Zieht die Schattierung in Richtung „unbeleuchtet" – 1 lässt sie, 0
/// nimmt sie ganz weg.
///
/// **Warum es das gibt.** Die Schattierung ist eine gerechnete Sonne, und
/// `modulate` multipliziert sie auf die Textur. Bei einer Karte ist das
/// genau richtig: Eine Karte ist flach gezeichnet und bekommt hier ihr
/// Relief.
///
/// Ein **Luftbild bringt sein eigenes Licht schon mit** – als es
/// aufgenommen wurde, stand eine echte Sonne am Himmel, und ihre Schatten
/// stecken in den Bildpunkten. Unsere Sonne kommt dann obendrauf, und am
/// gerenderten Bild des Ilsetals war das Ergebnis eine fast schwarze
/// Waldflanke. Also weniger, aber nicht nichts: Ganz ohne Schattierung
/// verliert die Landschaft ihre Form, weil ein senkrecht aufgenommenes
/// Luftbild von der Steilheit eines Hangs kaum etwas verrät.
double _gedaempft(double licht, double staerke) =>
    staerke >= 1 ? licht : 1 - (1 - licht) * staerke.clamp(0.0, 1.0);

/// Grundfarbe mal Helligkeit mal Lichtfarbe.
///
/// Die Lichtfarbe kommt seit den Tageszeiten dazu: Morgenlicht ist warm,
/// die blaue Stunde kalt. Sie multipliziert wie die Helligkeit, faerbt
/// also auch die Karte mit – deshalb steht sie in [Lichtstimmung]
/// zurueckhaltend.
int _farbe(Color grund, double licht,
    [Lichtstimmung stimmung = stimmungMittag]) {
  final l = stimmung.lichtfarbe;
  int kanal(double v, double ton) =>
      (v * licht * ton * 255).round().clamp(0, 255);
  return (0xFF << 24) |
      (kanal(grund.r, l.r) << 16) |
      (kanal(grund.g, l.g) << 8) |
      kanal(grund.b, l.b);
}

/// Ob ein Block überhaupt ins Bild ragt.
///
/// **Gemessen, warum es das gibt.** Jeder Block ist ein eigener
/// Zeichenzug mit eigenem Shader, und die lassen sich nicht
/// zusammenfassen. Bei gleicher Dreieckszahl (rund 18.000) kostete das
/// Aufzeichnen eines Bildes auf einem Mac:
///
/// ```
///   6 Blöcke   1,27 ms
///  20 Blöcke   1,63 ms
///  64 Blöcke   2,39 ms
/// 240 Blöcke   3,29 ms
/// 900 Blöcke   7,02 ms
/// ```
///
/// Im Flug steht die Kamera aber mitten in der Landschaft und sieht
/// nach vorn: Der grösste Teil der Blöcke liegt hinter ihr oder neben
/// dem Bildausschnitt. Geprüft werden die **acht Ecken des Kastens**,
/// in dem der Block liegt – acht Projektionen statt mehrerer hundert.
///
/// Grosszügig geprüft: Ragt auch nur eine Ecke hinter die Kamera, gilt
/// der Block als sichtbar. Ein Block, der die Kamera umschliesst, hat
/// keine brauchbare Bildfläche – ihn wegzulassen risse ein Loch in den
/// Vordergrund.
bool blockImBild(Blocknetz b, Gelaendekamera kamera, Size size) {
  var links = double.infinity;
  var rechts = double.negativeInfinity;
  var oben = double.infinity;
  var unten = double.negativeInfinity;
  var davor = 0;
  for (var i = 0; i < 8; i++) {
    final p = kamera.projiziere((
      x: (i & 1) == 0 ? b.westM : b.ostM,
      y: (i & 2) == 0 ? b.suedM : b.nordM,
      z: (i & 4) == 0 ? b.tiefM : b.hochM,
    ));
    if (p.tiefe <= 1) return true;
    davor++;
    if (p.stelle.dx < links) links = p.stelle.dx;
    if (p.stelle.dx > rechts) rechts = p.stelle.dx;
    if (p.stelle.dy < oben) oben = p.stelle.dy;
    if (p.stelle.dy > unten) unten = p.stelle.dy;
  }
  if (davor == 0) return false;
  return rechts >= 0 && links <= size.width && unten >= 0 && oben <= size.height;
}

/// Welche Blöcke im Bild stehen, wie weit sie weg sind und wie fein
/// sie sein müssten.
///
/// **Die Regel ist gerechnet und nicht geraten** (siehe [blockstufe]):
/// Ein Bildpunkt deckt in der Entfernung *d* genau `d / brennweite`
/// Meter ab. Gesucht ist die gröbste Kachelstufe, die noch feiner ist.
///
/// [schaerfe] ist das Pixelverhältnis des Bildschirms – auf einem
/// Gerät mit doppelter Punktdichte ist die Karte sonst auf halbem Weg
/// zur Unschärfe.
///
/// [uebersichtAufloesung] ist, was die Übersichtskarte an dieser Stelle
/// hergibt, in Metern je Bildpunkt. Blöcke, die nicht schärfer würden
/// als sie, kommen gar nicht erst auf die Liste: Für sie wäre ein
/// eigener Abruf ein Bild, das genauso aussieht.
List<Blockwunsch> bloeckeImBild(
Gelaendenetz netz,
Gelaendekamera kamera,
Size size, {
  double schaerfe = 1.0,
  double? uebersichtAufloesung,
}) {
  final wo = kamera.standort;
  final aus = <Blockwunsch>[];
  for (final b in netz.bloecke) {
    if (!blockImBild(b, kamera, size)) continue;
    final dx = b.mitteX - wo.x;
    final dy = b.mitteY - wo.y;
    final dz = (b.tiefM + b.hochM) / 2 - wo.z;
    final d = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (uebersichtAufloesung != null &&
        d / (kamera.brennweite * schaerfe) >= uebersichtAufloesung) {
      continue;
    }
    aus.add((
      block: b.block,
      stufe: blockstufe(
        entfernungMeter: d,
        brennweite: kamera.brennweite,
        breite: b.block.mitteBreite,
        schaerfe: schaerfe,
      ),
      entfernung: d,
    ));
  }
  return aus;
}

/// Wie viele Blöcke bei dieser Kameraeinstellung ins Bild ragen.
///
/// Nur zum Messen und Prüfen – das Zeichnen fragt [blockImBild] selbst.
int bloeckeAnzahlImBild(
    Gelaendenetz netz, Gelaendekamera kamera, Size size) {
  var n = 0;
  for (final b in netz.bloecke) {
    if (blockImBild(b, kamera, size)) n++;
  }
  return n;
}

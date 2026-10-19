// Der Maler des Geländes (Teil von gelaende.dart).
part of 'gelaende.dart';

/// Zeichnet ein Netz mit einer Kamera.
/// Ein Messwert, wie er im Videobild steht.
///
/// [breitester] ist die **breiteste Fassung, die dieser Wert im ganzen
/// Flug annimmt** – „12,3 km/h", wenn irgendwo unterwegs zweistellig
/// gefahren wird. Der Maler richtet das Fach danach aus und malt darin
/// den jeweiligen [wert].
///
/// **Warum nicht einfach der Wert.** Ein Fach, das mit seinem Inhalt
/// wächst, verschiebt bei jedem Bild alles rechts davon – dreissigmal in
/// der Sekunde, sobald das Tempo von 9,9 auf 10,1 geht. Gleich breite
/// Ziffern allein reichen dafür nicht; es ist die **Zahl** der Ziffern,
/// die wechselt.
typedef Flugmesswert = ({
  String name,
  String wert,
  String breitester,
  Color? farbe,
});

class Gelaendemaler extends CustomPainter {
  final Gelaendenetz netz;
  final Gelaendekamera kamera;

  /// Die Übersichtskarte über dem ganzen Ausschnitt – `null` heisst:
  /// nur schattiertes Gelände.
  ///
  /// Sie ist der **Rückfall**: Solange ein Block seine eigene, feinere
  /// Textur noch nicht hat, schneidet er sich sein Stück hier heraus.
  /// Ohne diesen Rückfall wäre die Landschaft während des Ladens
  /// stellenweise leer, und Löcher fallen mehr auf als Unschärfe.
  final ui.Image? karte;

  /// Die eigene Textur je Block – schärfer als [karte], und nur da, wo
  /// sie schon geladen ist.
  final Map<Texturblock, ui.Image>? blocktexturen;

  /// Die Spur, in denselben Metern wie das Netz.
  final List<Raumpunkt> spur;
  final Color spurfarbe;

  /// Tageszeit: Himmelsfarben, Dunst und – über das Netz – das Relief.
  final Lichtstimmung stimmung;

  /// Bis wohin die Spur zurückgelegt ist, in Metern – `null` ausserhalb
  /// des Fluges.
  ///
  /// Zurückgelegt wird in voller Farbe gezeichnet, was noch kommt blass.
  /// Ohne diesen Schnitt sieht die Spur im Flug genauso aus wie im
  /// Stillstand, und man verliert, wo auf ihr man gerade ist.
  final double? gefahrenBis;

  /// Die aufsummierte Strecke bis zu jedem Punkt aus [spur] – muss zu
  /// [gefahrenBis] gehören und genauso lang sein wie [spur].
  final List<double>? streckeJePunkt;

  /// Gipfel, Hütten, Quellen – als aufrechte Schilder über der
  /// Landschaft (siehe `gelaendeschilder.dart`).
  final List<Gelaendeschild> schilder;

  /// Die Geländehöhe an einer Stelle, in Netzmetern – für die
  /// Sichtprüfung der Schilder. Ohne sie schweben Gipfelnamen durch
  /// Berge hindurch.
  final double? Function(double x, double y)? hoeheBei;

  /// Das Foto zur Stelle – **nur für den Videoexport**.
  ///
  /// Am Bildschirm ist das Flugbild ein Widget (siehe `_Flugbild`): Dort
  /// lädt Flutter die Datei selbst, blendet auf und ab und räumt hinter
  /// sich auf. Ein Video entsteht dagegen ohne Widgetbaum, Bild für Bild
  /// auf eine Leinwand – dort muss dasselbe gemalt werden.
  final ({ui.Image bild, double deckkraft, String? unterschrift})? flugbild;

  /// Die Namensnennung – ebenfalls nur für den Videoexport.
  ///
  /// **Keine Zierleiste, sondern eine Lizenzauflage.** Am Bildschirm
  /// steht sie als Fussnote unter der Ansicht; ein Video geht aus der
  /// App heraus und muss sie mitnehmen.
  final String? namensnennung;

  /// Der Abspann – die Zahlen der Tour, ebenfalls nur für das Video.
  final ({List<String> zeilen, double deckkraft})? abspann;

  /// Höhe, Steigung und Tempo im Bild – **nur für den Videoexport**.
  ///
  /// Am Bildschirm stehen sie als Widgetzeile **unter** der Ansicht
  /// (siehe `_Messwerte`); ein Video hat kein Darunter. Was aus der App
  /// herausgeht, trägt seine Zahlen im Bild oder gar nicht.
  final ({List<Flugmesswert> werte, double deckkraft})? messwerte;

  /// Die Schrift der Schilder – nur für Bildwerkzeuge nötig.
  ///
  /// `flutter test` setzt sonst „Ahem", und die malt jedes Zeichen als
  /// gefüllten Kasten; ein Standbild sähe dann aus wie eine Reihe
  /// schwarzer Balken, und über Grösse und Lage der Schilder liesse sich
  /// nichts sagen. In der laufenden App bleibt das `null` – dort steht
  /// die Schrift des Themas.
  final String? schriftart;

  Gelaendemaler({
    required this.netz,
    required this.kamera,
    required this.spur,
    required this.spurfarbe,
    this.stimmung = stimmungMittag,
    this.karte,
    this.blocktexturen,
    this.gefahrenBis,
    this.streckeJePunkt,
    this.schilder = const [],
    this.hoeheBei,
    this.schriftart,
    this.flugbild,
    this.namensnennung,
    this.abspann,
    this.messwerte,
  });

  /// Die Grösse des letzten Bildes – die Dunstschicht braucht sie für
  /// ihren Ausschnitt.
  Size _flaeche = Size.zero;

  @override
  void paint(Canvas canvas, Size size) {
    _flaeche = size;
    // **Der Himmel zuerst, und als Verlauf.** Vorher stand hier eine
    // Flaeche in der Hintergrundfarbe des Themas – im dunklen Thema eine
    // schwarze Leere, in die die Landschaft hineinragte. Ein Verlauf
    // kostet nichts weiter: `drawRect` mit einem Shader ist Flutter
    // selbst, kein Paket.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          [stimmung.himmelOben, stimmung.himmelUnten],
        ),
    );

    // **Erst alle sichtbaren Blöcke projizieren, dann zeichnen.** Der
    // Dunst braucht die nächste und die fernste Tiefe über die **ganze**
    // Landschaft; rechnete jeder Block seine eigene Skala, bekäme jeder
    // Block seinen eigenen Nebel und die Blockgrenzen wären als Stufen zu
    // sehen.
    var nahste = double.infinity;
    var fernste = 0.0;
    final sichtbar = <Blocknetz>[];
    for (final b in netz.bloecke) {
      if (!blockImBild(b, kamera, size)) continue;
      _projiziere(b);
      if (b.nahste < nahste) nahste = b.nahste;
      if (b.fernste > fernste) fernste = b.fernste;
      sichtbar.add(b);
    }

    // **Die Blöcke von hinten nach vorn.**
    //
    // `drawVertices` kennt keinen Tiefenpuffer: Was zuletzt gemalt wird,
    // gewinnt. Innerhalb eines Blocks ordnet [_reihenfolgeNachTiefe] die
    // Dreiecke; zwischen den Blöcken ordnet diese Liste.
    //
    // Sortiert wird nach dem **waagerechten Abstand zur Kamera** und
    // nicht nach der Bildtiefe des Mittelpunkts. Der Unterschied zählt
    // bei einem Block, der die Kamera umschliesst: Sein Mittelpunkt kann
    // hinter ihr liegen, seine sichtbare Hälfte aber unmittelbar vor ihr.
    // Nach Bildtiefe geriete er ganz nach hinten und verschwände unter
    // der halben Landschaft.
    final wo = kamera.standort;
    final ordnung = sichtbar
      ..sort((a, b) {
        final da =
            (a.mitteX - wo.x) * (a.mitteX - wo.x) +
            (a.mitteY - wo.y) * (a.mitteY - wo.y);
        final db =
            (b.mitteX - wo.x) * (b.mitteX - wo.x) +
            (b.mitteY - wo.y) * (b.mitteY - wo.y);
        return db.compareTo(da);
      });

    for (final b in ordnung) {
      _zeichneBlock(canvas, b);
    }

    _dunstDarueber(canvas, ordnung, nahste, fernste);

    if (spur.length > 1) {
      // Zwei Pfade statt eines: der zurückgelegte Teil und der, der noch
      // kommt. Getrennt gezeichnet und nicht als ein Pfad mit
      // wechselnder Farbe – ein Path kennt nur eine.
      final pfad = Path();
      final kommtNoch = Path();
      final teilen =
          gefahrenBis != null &&
          streckeJePunkt != null &&
          streckeJePunkt!.length == spur.length;
      var offen = false;
      var offenNoch = false;
      for (var i = 0; i < spur.length; i++) {
        final b = kamera.projiziere(spur[i]);
        if (b.tiefe <= 1) {
          offen = false;
          offenNoch = false;
          continue;
        }
        final schonDa = !teilen || streckeJePunkt![i] <= gefahrenBis!;
        final ziel = schonDa ? pfad : kommtNoch;
        final warOffen = schonDa ? offen : offenNoch;
        if (!warOffen) {
          ziel.moveTo(b.stelle.dx, b.stelle.dy);
        } else {
          ziel.lineTo(b.stelle.dx, b.stelle.dy);
        }
        if (schonDa) {
          offen = true;
          // Damit die beiden Hälften nicht auseinanderklaffen, beginnt
          // die kommende dort, wo die zurückgelegte endet.
          if (teilen) {
            kommtNoch.moveTo(b.stelle.dx, b.stelle.dy);
            offenNoch = true;
          }
        } else {
          offenNoch = true;
        }
      }
      // Erst der Teil, der noch kommt, dann der zurückgelegte: So liegt
      // der volle Strich obenauf, wo beide sich an der Nahtstelle
      // berühren.
      if (teilen) _spurZug(canvas, kommtNoch, spurfarbe, 0.4);
      _spurZug(canvas, pfad, spurfarbe, 1);
    }

    // Die Schilder ganz zuletzt: Sie gehören nicht in die Landschaft,
    // sondern davor – auch vor die Spur, denn ein Name, den ein Strich
    // durchkreuzt, ist keiner.
    zeichneSchilder(
      canvas,
      size,
      kamera,
      schilder,
      hoeheBei: hoeheBei,
      stimmung: stimmung,
      schriftart: schriftart,
    );

    _flugbildMalen(canvas, size);
    // Die Messwerte **vor** dem Abspann: Der legt sich als helle Tafel
    // über die Mitte, und die Zahlen des Fluges gehören dann darunter –
    // sie verabschieden sich, während er kommt.
    _messwerteMalen(canvas, size);
    _abspannMalen(canvas, size);
    _nennungMalen(canvas, size);
  }

  /// Baut einen Textabsatz – einmal je Aufruf, und das ist hier in
  /// Ordnung: Diese drei Dinge werden nur beim Videoexport gemalt, und
  /// dort kostet ein Bild ohnehin eine Kodierung.
  ui.Paragraph _absatz(
    String text,
    double groesse, {
    Color farbe = const Color(0xFF1B1B1B),
    FontWeight gewicht = FontWeight.w500,
    TextAlign ausrichtung = TextAlign.left,
    bool festeZifferbreite = false,
    double breite = 1200,
  }) {
    final bauer =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontFamily: schriftart,
              fontSize: groesse,
              fontWeight: gewicht,
              textAlign: ausrichtung,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: farbe,
              fontFeatures: festeZifferbreite
                  ? const [ui.FontFeature.tabularFigures()]
                  : null,
            ),
          )
          ..addText(text);
    return bauer.build()..layout(ui.ParagraphConstraints(width: breite));
  }

  /// Das Foto zur Stelle, oben rechts – dieselbe Ecke wie am Bildschirm.
  void _flugbildMalen(Canvas canvas, Size size) {
    final f = flugbild;
    if (f == null || f.deckkraft <= 0.01) return;
    final deck = f.deckkraft.clamp(0.0, 1.0);
    // Ein Fünftel der Bildbreite: Auf 1920 sind das 384 Punkte, auf einer
    // kleineren Ausgabe entsprechend weniger. Eine feste Zahl liesse das
    // Foto bei 3840 zur Briefmarke werden.
    final kante = size.width / 5;
    final bildhoehe = kante * 0.75;
    final rand = size.width * 0.02;
    final unten = f.unterschrift == null ? 0.0 : kante * 0.1;
    final kasten = Rect.fromLTWH(
      size.width - kante - rand - 8,
      rand,
      kante + 8,
      bildhoehe + 8 + unten,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(kasten, const Radius.circular(6)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92 * deck),
    );
    final ziel = Rect.fromLTWH(
      kasten.left + 4,
      kasten.top + 4,
      kante,
      bildhoehe,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(ziel, const Radius.circular(3)));
    // `cover`: Ein Vorschaubild ist selten 4:3, und verzerrt sähe es aus
    // wie ein Fehler.
    final q = _fuellend(
      f.bild.width.toDouble(),
      f.bild.height.toDouble(),
      ziel,
    );
    canvas.drawImageRect(
      f.bild,
      q,
      ziel,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: deck)
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    if (f.unterschrift case final u?) {
      final absatz = _absatz(
        u,
        kante * 0.075,
        farbe: const Color(0xFF1B1B1B).withValues(alpha: deck),
        ausrichtung: TextAlign.center,
        breite: kante,
      );
      canvas.drawParagraph(absatz, Offset(kasten.left + 4, ziel.bottom + 2));
    }
  }

  /// Der Ausschnitt aus dem Bild, der [ziel] ohne Verzerrung ausfüllt.
  static Rect _fuellend(double b, double h, Rect ziel) {
    if (b <= 0 || h <= 0) return Rect.fromLTWH(0, 0, b, h);
    final quellVerhaeltnis = b / h;
    final zielVerhaeltnis = ziel.width / ziel.height;
    if (quellVerhaeltnis > zielVerhaeltnis) {
      final neu = h * zielVerhaeltnis;
      return Rect.fromLTWH((b - neu) / 2, 0, neu, h);
    }
    final neu = b / zielVerhaeltnis;
    return Rect.fromLTWH(0, (h - neu) / 2, b, neu);
  }

  void _abspannMalen(Canvas canvas, Size size) {
    final a = abspann;
    if (a == null || a.deckkraft <= 0.01 || a.zeilen.isEmpty) return;
    final deck = a.deckkraft.clamp(0.0, 1.0);
    final gross = size.height * 0.055;
    final klein = size.height * 0.026;
    final absaetze = [
      for (var i = 0; i < a.zeilen.length; i++)
        _absatz(
          a.zeilen[i],
          i == 0 ? gross : klein,
          farbe: const Color(0xFF1B1B1B),
          gewicht: i == 0 ? FontWeight.w300 : FontWeight.w500,
          ausrichtung: TextAlign.center,
          breite: size.width * 0.6,
        ),
    ];
    var hoehe = 0.0;
    for (final p in absaetze) {
      hoehe += p.height;
    }
    final kasten = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.6,
      height: hoehe + size.height * 0.08,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(kasten, Radius.circular(size.height * 0.02)),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.88 * deck),
    );
    var y = kasten.top + size.height * 0.04;
    for (final p in absaetze) {
      canvas.drawParagraph(p, Offset(kasten.left, y));
      y += p.height;
    }
  }

  /// Höhe, Steigung und Tempo – unten links, über der Namensnennung.
  ///
  /// **Warum unten links.** Oben rechts steht das Foto zur Stelle, unten
  /// links die Namensnennung; die Zahlen setzen sich darüber und lassen
  /// die Bildmitte frei, in der die Landschaft vorbeizieht. Es ist auch
  /// die Ecke, in der jeder sie erwartet, der einmal einen Flyover
  /// gesehen hat.
  void _messwerteMalen(Canvas canvas, Size size) {
    final m = messwerte;
    if (m == null || m.werte.isEmpty || m.deckkraft <= 0.01) return;
    final deck = m.deckkraft.clamp(0.0, 1.0);

    // Alles am Bild bemessen und nichts in festen Punkten: Dieselbe
    // Ausgabe entsteht in 1280 x 720 wie in 3840 x 2160, und eine feste
    // Schriftgrösse wäre dort einmal plakativ und einmal unleserlich.
    final namensgroesse = size.height * 0.019;
    final wertgroesse = size.height * 0.042;
    final rand = size.width * 0.012;
    final luft = size.height * 0.014;
    final spalt = size.width * 0.028;

    final fach = <({ui.Paragraph name, ui.Paragraph wert, double breite})>[];
    for (final w in m.werte) {
      final name = _absatz(
        w.name,
        namensgroesse,
        farbe: const Color(0xFFFFFFFF).withValues(alpha: 0.75 * deck),
        gewicht: FontWeight.w500,
      );
      final wert = _absatz(
        w.wert,
        wertgroesse,
        farbe: (w.farbe ?? const Color(0xFFFFFFFF)).withValues(alpha: deck),
        gewicht: FontWeight.w600,
        festeZifferbreite: true,
      );
      // Gemessen wird an der breitesten Fassung, gemalt die jetzige.
      final vorlage = _absatz(
        w.breitester,
        wertgroesse,
        gewicht: FontWeight.w600,
        festeZifferbreite: true,
      );
      fach.add((
        name: name,
        wert: wert,
        breite: math.max(name.maxIntrinsicWidth, vorlage.maxIntrinsicWidth),
      ));
    }

    var breite = 0.0;
    for (final f in fach) {
      breite += f.breite;
    }
    breite += spalt * (fach.length - 1);
    final hoehe = namensgroesse * 1.35 + wertgroesse * 1.25;

    final nennung = _nennungsabsatz(size);
    final belegt = nennung == null ? 0.0 : nennung.height + 4 + luft;
    final tafel = Rect.fromLTWH(
      rand,
      size.height - rand - belegt - hoehe - luft * 2,
      breite + luft * 2,
      hoehe + luft * 2,
    );

    // Dieselbe Sorge wie bei der Namensnennung, nur ernster: Diese
    // Zahlen ziehen über Himmel, Fels und Wald hinweg, und über hellem
    // Kalk ist Weiss auf Weiss nicht zu lesen. Ein deutlicherer Grund
    // als dort (0x99 statt 0x66) – die Zahlen sind grösser und tragen
    // mehr Gewicht als eine Fussnote.
    canvas.drawRRect(
      RRect.fromRectAndRadius(tafel, Radius.circular(size.height * 0.012)),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.6 * deck),
    );

    var x = tafel.left + luft;
    for (final f in fach) {
      canvas.drawParagraph(f.name, Offset(x, tafel.top + luft));
      canvas.drawParagraph(
        f.wert,
        Offset(x, tafel.top + luft + namensgroesse * 1.35),
      );
      x += f.breite + spalt;
    }
  }

  /// Die Namensnennung als fertiger Absatz – oder `null`, wenn keine da
  /// ist. Auch die Messwerte fragen danach: Sie sitzen darüber und
  /// müssen wissen, wie viel unten schon belegt ist.
  ui.Paragraph? _nennungsabsatz(Size size) {
    final n = namensnennung;
    if (n == null || n.isEmpty) return null;
    return _absatz(
      n,
      size.height * 0.018,
      farbe: const Color(0xFFFFFFFF),
      breite: size.width * 0.9,
    );
  }

  void _nennungMalen(Canvas canvas, Size size) {
    final absatz = _nennungsabsatz(size);
    if (absatz == null) return;
    final rand = size.width * 0.012;
    final wo = Offset(rand, size.height - absatz.height - rand);
    // Ein dunkler Grund darunter: Über hellem Himmel wäre weisse Schrift
    // unlesbar, und über dunklem Wald schwarze.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          wo.dx - 4,
          wo.dy - 2,
          absatz.maxIntrinsicWidth + 8,
          absatz.height + 4,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0x66000000),
    );
    canvas.drawParagraph(absatz, wo);
  }

  /// Rechnet die Eckpunkte eines Blocks auf den Bildschirm.
  void _projiziere(Blocknetz b) {
    final anzahl = b.eckenzahl;
    final flach = b.bildstellen;
    final tiefen = b.tiefen;
    // Merkposten je Eckpunkt: Liegt er hinter der Kamera? Als Bytes und
    // nicht als `List<bool>`: Dart legt die als Zeiger auf zwei Objekte
    // ab, acht Byte je Eintrag statt einem.
    final hinten = b.hinterDerKamera;
    var nahste = double.infinity;
    var fernste = 0.0;
    for (var i = 0; i < anzahl; i++) {
      final p = kamera.projiziere((
        x: b.ecken[i * 3],
        y: b.ecken[i * 3 + 1],
        z: b.ecken[i * 3 + 2],
      ));
      flach[i * 2] = p.stelle.dx;
      flach[i * 2 + 1] = p.stelle.dy;
      tiefen[i] = p.tiefe;
      hinten[i] = p.tiefe <= 1 ? 1 : 0;
      if (hinten[i] == 0) {
        if (p.tiefe < nahste) nahste = p.tiefe;
        if (p.tiefe > fernste) fernste = p.tiefe;
      }
    }

    // **Dreiecke hinter der Kamera fallen weg.**
    //
    // `projiziere` legt einen Punkt hinter der Kamera auf die Bildmitte –
    // das steht dort ausdrücklich dabei, und für eine Linie ist es
    // richtig, weil die Linie an der Stelle ohnehin abgesetzt wird. Für
    // `drawVertices` ist es verheerend: Flutter schneidet nicht an einer
    // vorderen Ebene, also bleibt das Dreieck stehen und spannt sich vom
    // Bildrand bis in die Mitte. Am Bild sind das Schlieren, die aus
    // einem Punkt herausfächern.
    //
    // In der Übersicht kam das nie vor – dort steht die Kamera immer
    // ausserhalb der Landschaft. Beim Flug steht sie mittendrin, und
    // hinter ihr liegt die halbe Karte.
    //
    // Ein Dreieck zu einem Punkt zusammenzuziehen ist die billigste
    // Fassung von „nicht zeichnen": Es hat dann keine Fläche mehr. Das
    // richtige Beschneiden an der vorderen Ebene würde Dreiecke teilen
    // und neue Eckpunkte erzeugen – Aufwand für einen Rand, den man
    // ohnehin nicht ansieht, weil er hinter einem liegt.
    for (var d = 0; d < anzahl; d += 3) {
      if (hinten[d] != 0 || hinten[d + 1] != 0 || hinten[d + 2] != 0) {
        for (var k = 1; k < 3; k++) {
          flach[(d + k) * 2] = flach[d * 2];
          flach[(d + k) * 2 + 1] = flach[d * 2 + 1];
        }
      }
    }

    b.nahste = nahste;
    b.fernste = fernste;
  }

  /// Zeichnet einen Block mit der Textur, die für ihn da ist.
  void _zeichneBlock(Canvas canvas, Blocknetz b) {
    final bild = blocktextur(b.block);
    final ecken = ui.Vertices.raw(
      ui.VertexMode.triangles,
      b.bildstellen,
      colors: b.farben,
      indices: _reihenfolgeNachTiefe(b),
      textureCoordinates: bild == null ? null : b.texturstellen,
    );
    if (bild == null) {
      canvas.drawVertices(ecken, BlendMode.dst, Paint());
    } else {
      // `modulate` multipliziert die Karte mit der Schattierung: Man
      // sieht die Wege *und* das Relief. Nur die Karte wäre eine flache
      // Karte in Schräglage, nur die Schattierung wären Berge ohne Wege.
      canvas.drawVertices(
        ecken,
        BlendMode.modulate,
        Paint()
          ..shader = ui.ImageShader(
            bild.bild,
            TileMode.clamp,
            TileMode.clamp,
            bild.abbildung.storage,
          )
          ..filterQuality = FilterQuality.low,
      );
    }
    ecken.dispose();
  }

  /// Welches Bild auf einen Block gehört – und wie es darauf liegt.
  ///
  /// Zwei Fälle, und der zweite ist der Grund für die Rechnung: Entweder
  /// der Block hat **seine eigene** Textur, dann füllt sie ihn genau aus;
  /// oder es gibt nur die **Übersichtskarte** über dem ganzen Ausschnitt,
  /// und dann muss der Block sich sein Stück daraus herausschneiden.
  ///
  /// Das Herausschneiden steckt in der Abbildung des Shaders und nicht in
  /// den Texturstellen der Eckpunkte: Die sind blocklokal und liegen
  /// fest, die Karte darunter kann wechseln. `ui.ImageShader` rechnet
  /// Bildpunkte in eben diese blocklokalen Stellen um – bei der eigenen
  /// Textur ist das nur ein Massstab, bei der Übersicht kommt eine
  /// Verschiebung dazu.
  ({ui.Image bild, Matrix4 abbildung})? blocktextur(Texturblock block) {
    final eigen = blocktexturen?[block];
    if (eigen != null) {
      return (
        bild: eigen,
        abbildung: Matrix4.diagonal3Values(
          1 / eigen.width,
          1 / eigen.height,
          1,
        ),
      );
    }
    final k = karte;
    if (k == null) return null;
    // Wo der Block im Ausschnitt liegt – in Länge geradlinig, in Breite
    // über Mercator, weil die Karte eine Kachelkarte ist.
    final u0 = (block.west - netz.west) / (netz.ost - netz.west);
    final u1 = (block.ost - netz.west) / (netz.ost - netz.west);
    final yN = kachelYGenau(netz.nord, 0);
    final yS = kachelYGenau(netz.sued, 0);
    final v0 = (kachelYGenau(block.nord, 0) - yN) / (yS - yN);
    final v1 = (kachelYGenau(block.sued, 0) - yN) / (yS - yN);
    if (!(u1 > u0) || !(v1 > v0)) return null;
    final sx = 1 / (k.width * (u1 - u0));
    final sy = 1 / (k.height * (v1 - v0));
    return (
      bild: k,
      abbildung: Matrix4.identity()
        ..translateByDouble(-u0 / (u1 - u0), -v0 / (v1 - v0), 0, 1)
        ..scaleByDouble(sx, sy, 1, 1),
    );
  }

  /// Die Eckpunkte eines Blocks in Zeichenreihenfolge – fernste Dreiecke
  /// zuerst.
  ///
  /// **Zählsortierung und kein Vergleich.** Neuntausend Dreiecke je Bild
  /// bei sechzig Bildern in der Sekunde: `sort` wäre n·log(n) mit einem
  /// Vergleichsaufruf je Schritt, das hier ist zweimal linear plus ein
  /// Durchlauf über die Eimer.
  ///
  /// Die Tiefe eines Dreiecks ist das Mittel seiner drei Eckpunkte. Ein
  /// Dreieck mit einem Punkt hinter der Kamera ist an dieser Stelle
  /// bereits auf einen Punkt zusammengezogen (siehe [_projiziere]) – es
  /// hat keine Fläche mehr und darf deshalb irgendwohin; es kommt nach
  /// ganz hinten.
  ///
  /// **Der Fund, den das behoben hat.** Vorher verliess sich der Maler
  /// darauf, die Gitterreihenfolge (Norden nach Süden) sei schon von
  /// hinten nach vorn. Das gilt nur, solange die Kamera nach Norden
  /// sieht – **die Flugkamera dreht sich in Laufrichtung** (siehe
  /// `Gelaendeflug.drehung`). Wer nach Süden wandert, sah fernes Gelände
  /// über nahem: am gerenderten Bild ein breites Band quer durch die
  /// Landschaft, in `gelaende_zeichenreihenfolge_test.dart` 960 von 3120
  /// Bildpunkten.
  Uint16List _reihenfolgeNachTiefe(Blocknetz netz) {
    final ordnung = netz.reihenfolge;
    final eimer = netz.eimer;
    final tiefen = netz.tiefen;
    final hinten = netz.hinterDerKamera;
    final dreiecke = ordnung.length ~/ 3;
    const stufen = Blocknetz.tiefenstufen;
    final nahste = netz.nahste;
    final fernste = netz.fernste;
    final spanne = fernste - nahste;

    // Ohne Tiefenunterschied gibt es nichts zu ordnen - die Gitterfolge
    // ist dann so gut wie jede andere.
    if (!(spanne > 0)) {
      for (var i = 0; i < ordnung.length; i++) {
        ordnung[i] = i;
      }
      return ordnung;
    }

    /// Stufe 0 ist die fernste. Damit kommt sie beim Auslesen zuerst.
    int stufeVon(int d) {
      if (hinten[d * 3] != 0 ||
          hinten[d * 3 + 1] != 0 ||
          hinten[d * 3 + 2] != 0) {
        return 0;
      }
      final t = (tiefen[d * 3] + tiefen[d * 3 + 1] + tiefen[d * 3 + 2]) / 3;
      final anteil = ((fernste - t) / spanne).clamp(0.0, 1.0);
      return (anteil * (stufen - 1)).toInt();
    }

    eimer.fillRange(0, eimer.length, 0);
    for (var d = 0; d < dreiecke; d++) {
      eimer[stufeVon(d) + 1]++;
    }
    for (var s = 1; s < eimer.length; s++) {
      eimer[s] += eimer[s - 1];
    }
    for (var d = 0; d < dreiecke; d++) {
      final stelle = eimer[stufeVon(d)]++ * 3;
      ordnung[stelle] = d * 3;
      ordnung[stelle + 1] = d * 3 + 1;
      ordnung[stelle + 2] = d * 3 + 2;
    }
    return ordnung;
  }

  /// **Der Dunst in der Ferne – und die weiche Kante.**
  ///
  /// Dieselben Dreiecke ein zweites Mal, diesmal in der Dunstfarbe mit
  /// einer Deckkraft je Eckpunkt. Ein zweiter Zug und keine Rechnung an
  /// den Eckpunktfarben, weil `modulate` multipliziert: Damit lässt sich
  /// nur abdunkeln, und Dunst hellt auf. Er muss also darübergelegt
  /// werden.
  ///
  /// Was weiter weg ist, verblasst – der älteste Tiefenhinweis der
  /// Malerei und der einzige, den eine Ansicht ohne Schattenwurf hat.
  /// Die Skala kommt aus der Szene selbst (nächster und fernster
  /// Eckpunkt **über alle Blöcke**), damit sie in der Übersicht wie im
  /// Flug passt und nicht an den Blockgrenzen springt.
  ///
  /// Die weiche Kante steckt dagegen in der Deckkraft des Geländes
  /// selbst (siehe [baueNetz]) – hier wird sie nur ausgespart.
  void _dunstDarueber(
    Canvas canvas,
    List<Blocknetz> ordnung,
    double nahste,
    double fernste,
  ) {
    if (_flaeche.isEmpty) return;
    if (fernste <= nahste) return;
    final spanne = fernste - nahste;
    final rot = (stimmung.dunst.r * 255).round().clamp(0, 255);
    final gruen = (stimmung.dunst.g * 255).round().clamp(0, 255);
    final blau = (stimmung.dunst.b * 255).round().clamp(0, 255);
    final grundton = (rot << 16) | (gruen << 8) | blau;

    // **Auf eine eigene Schicht, und dort ersetzend statt überlagernd.**
    //
    // `drawVertices` kennt keinen Tiefenpuffer; für das Gelände löst das
    // die Reihenfolge, für den Dunst reicht sie nicht: Hinter einem Grat
    // liegt ferne Landschaft, deren Dunst zuerst gemalt wird – und das
    // nahe Dreieck darüber trägt fast keinen Dunst, deckt also nichts zu.
    // Übrig blieb ein weisses Band quer über die Gipfelkette. Erst die
    // Gegenprobe mit ausgeschaltetem Saum zeigte, dass es nicht der Rand
    // war.
    //
    // Auf einer eigenen Schicht mit `src` **ersetzt** jedes Dreieck, was
    // dort steht. Weil sie von hinten nach vorn kommen, gewinnt das
    // nächste – genau das, was ein Tiefenpuffer täte. Die fertige
    // Schicht kommt dann in einem Zug über das Gelände.
    //
    // **Eine Schicht für alle Blöcke**, nicht eine je Block: Eine
    // Zwischenfläche in Bildschirmgrösse ist der teuerste Einzelposten
    // dieses Malers, und hundert davon je Bild wären hundertmal der
    // Preis. Die Blöcke kommen in derselben Reihenfolge hinein wie das
    // Gelände, damit `src` innerhalb der Schicht dasselbe leistet.
    canvas.saveLayer(Offset.zero & _flaeche, Paint());
    final farbe = Paint()..blendMode = BlendMode.src;
    for (final b in ordnung) {
      final anzahl = b.eckenzahl;
      final farben = b.dunstfarben;
      final tiefen = b.tiefen;
      final hinten = b.hinterDerKamera;
      for (var i = 0; i < anzahl; i++) {
        if (hinten[i] != 0) {
          farben[i] = 0;
          continue;
        }
        final t = ((tiefen[i] - nahste) / spanne).clamp(0.0, 1.0);
        final deckung =
            _dunstStaerke *
            (1 - math.exp(-_dunstDichte * t))
            // Wo das Gelände selbst schon durchsichtig ist, darf der
            // Dunst es nicht wieder zumalen.
            *
            b.randnaehe[i];
        farben[i] = ((deckung * 255).round().clamp(0, 255) << 24) | grundton;
      }
      // Dieselbe Ordnung wie das Gelände – hier ist sie sogar zwingend:
      // Auf der eigenen Schicht ERSETZT jedes Dreieck, was dort steht,
      // und gewinnen soll das nächste.
      final schleier = ui.Vertices.raw(
        ui.VertexMode.triangles,
        b.bildstellen,
        colors: farben,
        indices: b.reihenfolge,
      );
      canvas.drawVertices(schleier, BlendMode.dst, farbe);
      schleier.dispose();
    }
    canvas.restore();
  }

  /// **Die Spur in drei Zügen.**
  ///
  /// Ein einzelner Strich verschwindet auf einer bunten Karte – im Bild
  /// vom 02.09. war er über der Wiese kaum zu finden. Deshalb:
  /// 1. ein versetzter dunkler Schatten, der ihn vom Hang abhebt,
  /// 2. ein breiter weicher Schein darunter,
  /// 3. der scharfe Kern darüber.
  ///
  /// In dieser Reihenfolge, sonst läge der Schatten über dem Kern.
  void _spurZug(Canvas canvas, Path pfad, Color farbe, double deckkraft) {
    if (deckkraft <= 0) return;
    canvas.drawPath(
      pfad.shift(const Offset(1.5, 2.5)),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.35 * deckkraft)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      pfad,
      Paint()
        ..color = farbe.withValues(alpha: 0.45 * deckkraft)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 3.5),
    );
    canvas.drawPath(
      pfad,
      Paint()
        ..color = farbe.withValues(alpha: deckkraft)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(Gelaendemaler alt) =>
      alt.netz != netz ||
      alt.kamera != kamera ||
      alt.stimmung != stimmung ||
      alt.karte != karte ||
      alt.blocktexturen != blocktexturen ||
      alt.schilder != schilder ||
      alt.flugbild != flugbild ||
      alt.abspann != abspann ||
      alt.messwerte != messwerte ||
      alt.spur != spur ||
      // Ohne diese Zeile stünde der Schnitt zwischen zurückgelegt und
      // kommend still, sobald die Kamera einmal gleich bleibt – etwa
      // beim Spulen an derselben Stelle.
      alt.gefahrenBis != gefahrenBis;
}

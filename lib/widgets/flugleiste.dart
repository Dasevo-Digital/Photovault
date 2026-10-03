// Die Leiste unter dem Kameraflug (Teil von gelaende.dart).
part of 'gelaende.dart';

/// Die Leiste unter dem Flug: Steuerung, Messwerte und das Höhenprofil,
/// das mitläuft.
///
/// **Warum die Zahlen hierher gehören und nicht in eine Ecke.** Ein Flug
/// über eine Landschaft ist schön und sagt nichts. Was er soll, ist die
/// Frage beantworten „wie war der Weg" – und die beantworten Höhe,
/// Steigung und Tempo, nicht die Aussicht. Sie stehen deshalb in der
/// Leseachse unter dem Bild und nicht als Kleingedrucktes am Rand.
///
/// **Warum eine eigene Klasse.** Die Ansicht darüber ist ein
/// `CustomPaint` mit einer selbstgerechneten Kamera; hier sind es
/// Material-Widgets. Beides in einem `build` wäre zweihundert Zeilen, in
/// denen niemand mehr die Kamera findet.
class Flugleiste extends StatelessWidget {
  final Gelaendeflug flug;

  /// Der aktuelle Stand – `null` heisst: Übersicht, es wird nicht
  /// geflogen.
  final Flugstand? stand;

  final double fortschritt;
  final bool laeuft;
  final bool imFlug;
  final VoidCallback beimSchalten;
  final VoidCallback beimBeenden;
  final ValueChanged<double> beimSpulen;

  /// Den Flug als Video schreiben – `null` heisst: geht hier nicht.
  final VoidCallback? beimAusgeben;

  /// Ob gerade ausgegeben wird. Dann ist der Knopf ein Abbruch.
  final bool gibtAus;

  /// Wie weit die Ausgabe ist – `null` heisst: läuft keine.
  final double? ausgabeFortschritt;

  /// Wie lange die Ausgabe noch braucht, oder `null`.
  final Duration? ausgabeRest;

  const Flugleiste({
    super.key,
    required this.flug,
    required this.stand,
    required this.fortschritt,
    required this.laeuft,
    required this.imFlug,
    required this.beimSchalten,
    required this.beimBeenden,
    required this.beimSpulen,
    this.beimAusgeben,
    this.gibtAus = false,
    this.ausgabeFortschritt,
    this.ausgabeRest,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toString();
    final eine = NumberFormat.decimalPatternDigits(
        locale: sprache, decimalDigits: 1);

    final anteil = ausgabeFortschritt;

    return ColoredBox(
      color: farben.surface.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // **Der Balken, den es bis 3.5.1 nicht gab.** Der Fortschritt
            // wurde gerechnet und bis hierher durchgereicht – und dann
            // nirgends gezeichnet. Zu sehen war allein, dass aus dem
            // Filmzeichen ein Stoppzeichen wurde. Wer auf eine Wanderung
            // von sechzehn Kilometern rund zweitausend Bilder ausgeben
            // liess, sass also eine Minute oder länger vor einer
            // Oberfläche, die nichts sagte, und hielt das für „es tut
            // nichts".
            if (anteil != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ausgabeRest == null
                          ? t.flugVideoLaeuft((anteil * 100).round())
                          : t.flugVideoLaeuftMitRest((anteil * 100).round(),
                              dauerText(t, ausgabeRest!)),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: anteil.clamp(0.0, 1.0)),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (imFlug) ...[
              _Messwerte(stand: stand!, flug: flug),
              const SizedBox(height: AppSpacing.sm),
              // Das Profil trägt die Stelle mit, an der der Flug steht –
              // und nimmt einen Griff darauf an: Wer hineinfährt, spult.
              // Dieselbe Geste, die es für die Karte schon konnte.
              _Flugprofil(flug: flug, fortschritt: fortschritt,
                  beimSpulen: beimSpulen),
            ],
            Row(
              children: [
                IconButton(
                  tooltip: !imFlug
                      ? t.flugStarten
                      : laeuft
                          ? t.flugAnhalten
                          : (fortschritt >= 1 ? t.flugNochmal : t.flugWeiter),
                  icon: Icon(!imFlug
                      ? Icons.flight_takeoff
                      : laeuft
                          ? Icons.pause_circle_outline
                          : (fortschritt >= 1
                              ? Icons.replay
                              : Icons.play_circle_outline)),
                  onPressed: beimSchalten,
                ),
                if (imFlug)
                  IconButton(
                    tooltip: t.flugBeenden,
                    icon: const Icon(Icons.zoom_out_map),
                    onPressed: beimBeenden,
                  ),
                // Der Ausgabeknopf steht bei den Flugknöpfen und nicht in
                // der Werkzeugleiste oben: Was ausgegeben wird, ist der
                // Flug, nicht die Ansicht.
                if (beimAusgeben != null)
                  IconButton(
                    tooltip: gibtAus ? t.flugVideoAbbrechen : t.flugVideo,
                    icon: Icon(gibtAus
                        ? Icons.stop_circle_outlined
                        : Icons.movie_outlined),
                    onPressed: beimAusgeben,
                  ),
                Expanded(
                  child: Slider(
                    value: fortschritt.clamp(0.0, 1.0),
                    // Nur beim Flug greifbar: In der Übersicht bewegt der
                    // Regler nichts, was zu sehen wäre, und ein Regler
                    // ohne Wirkung ist schlimmer als keiner.
                    onChanged: imFlug ? beimSpulen : null,
                    label: t.flugFortschritt,
                  ),
                ),
                Text(
                  t.flugKm(eine.format(
                      (stand?.gefahrenMeter ?? flug.laengeMeter) / 1000)),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Höhe, Tempo, Steigung, Dauer – in einer Zeile, die umbrechen darf.
class _Messwerte extends StatelessWidget {
  final Flugstand stand;
  final Gelaendeflug flug;
  const _Messwerte({required this.stand, required this.flug});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toString();
    final eine =
        NumberFormat.decimalPatternDigits(locale: sprache, decimalDigits: 1);

    final werte = <({String name, String wert, Color? farbe})>[
      if (stand.hoeheMeter case final h?)
        (name: t.flugHoehe, wert: t.flugMeterProfil(h.round()), farbe: null),
      if (stand.tempoMeterJeSekunde case final v?)
        // In km/h und nicht in m/s: Niemand denkt eine Wanderung in
        // Metern je Sekunde.
        (name: t.flugTempo, wert: t.flugKmH(eine.format(v * 3.6)), farbe: null),
      if (stand.steigungProzent case final st?)
        (
          name: t.flugSteigung,
          wert: t.flugProzent(eine.format(st)),
          // Bergauf und bergab unterscheiden sich schon durch das
          // Vorzeichen; die Farbe macht es auf einen Blick lesbar, ohne
          // die einzige Auskunft zu sein (siehe 18. Prüfrunde).
          farbe: st.abs() < 1
              ? null
              : (st > 0 ? farben.error : farben.primary),
        ),
      if (stand.seitStart case final d?)
        (name: t.flugUnterwegs, wert: _dauertext(d), farbe: null),
    ];

    if (werte.isEmpty) {
      return Text(t.flugOhneZeit,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: farben.onSurfaceVariant));
    }

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: [
        for (final w in werte)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w.name,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: farben.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.xs),
              Text(
                w.wert,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: w.farbe,
                      fontFeatures: const [
                        // Ohne feste Zifferbreite zappelt jede Zahl bei
                        // jedem Bild – zwanzig Mal in der Sekunde.
                        ui.FontFeature.tabularFigures(),
                      ],
                    ),
              ),
            ],
          ),
      ],
    );
  }

  /// `1:04:37` bzw. `4:37` – ohne führende Null bei den Stunden und mit
  /// zweistelligen Minuten, wie man eine Dauer liest.
  static String _dauertext(Duration d) {
    final s = d.inSeconds;
    final st = s ~/ 3600;
    final min = (s % 3600) ~/ 60;
    final sek = s % 60;
    final zwei = sek.toString().padLeft(2, '0');
    return st > 0
        ? '$st:${min.toString().padLeft(2, '0')}:$zwei'
        : '$min:$zwei';
  }
}

/// Das Höhenprofil mit der Stelle, an der der Flug steht.
///
/// Eigener Maler und nicht [Hoehenprofil]: Jenes markiert einen
/// **Stützpunkt** und will angefahren werden, damit die Karte daneben
/// mitgeht. Hier ist die Stelle ein stufenloser Wert zwischen zwei
/// Punkten, sie kommt von der Uhr und nicht vom Zeiger, und der
/// zurückgelegte Teil soll sich vom kommenden abheben. Das ist genug
/// Unterschied für einen eigenen, sehr kurzen Maler – und es hält das
/// vorhandene Profil aus der Wanderansicht unangetastet.
class _Flugprofil extends StatelessWidget {
  final Gelaendeflug flug;
  final double fortschritt;
  final ValueChanged<double> beimSpulen;

  static const double hoehe = 64;

  const _Flugprofil({
    required this.flug,
    required this.fortschritt,
    required this.beimSpulen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // Aus dem Flug und nicht hier gebaut: Diese Liste ist je Flug
    // dieselbe, die Leiste baut sich aber in jedem Bild neu.
    final punkte = flug.hoehenprofil;
    if (punkte.length < 2) return const SizedBox.shrink();

    return Semantics(
      container: true,
      label: AppTexte.of(context).flugProfilBeschreibung,
      child: LayoutBuilder(
        builder: (context, platz) {
          void spulen(double x) =>
              beimSpulen((x / platz.maxWidth).clamp(0.0, 1.0));
          return GestureDetector(
            onHorizontalDragUpdate: (d) => spulen(d.localPosition.dx),
            onTapDown: (d) => spulen(d.localPosition.dx),
            child: CustomPaint(
              size: Size(platz.maxWidth, hoehe),
              painter: _Flugprofilmaler(
                punkte: punkte,
                gesamt: flug.laengeMeter,
                fortschritt: fortschritt,
                gefahren: farben.primary,
                kommend: farben.outlineVariant,
                marke: farben.error,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Flugprofilmaler extends CustomPainter {
  final List<({double meter, double hoehe})> punkte;
  final double gesamt;
  final double fortschritt;
  final Color gefahren;
  final Color kommend;
  final Color marke;

  _Flugprofilmaler({
    required this.punkte,
    required this.gesamt,
    required this.fortschritt,
    required this.gefahren,
    required this.kommend,
    required this.marke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (punkte.length < 2 || gesamt <= 0) return;
    var tief = punkte.first.hoehe;
    var hoch = punkte.first.hoehe;
    for (final p in punkte) {
      tief = math.min(tief, p.hoehe);
      hoch = math.max(hoch, p.hoehe);
    }
    // **Nicht bei null anfangen** – dieselbe Überlegung wie im
    // Wanderprofil: Eine Runde zwischen 300 und 380 m wäre über einer
    // Nulllinie ein waagerechter Strich. Und mindestens zehn Meter Luft,
    // sonst blähte eine flache Runde ihre Wellen zu Bergen auf.
    final luft = math.max((hoch - tief) * 0.1, 10.0);
    final unten = tief - luft;
    final oben = hoch + luft;

    double x(double meter) => meter / gesamt * size.width;
    double y(double h) =>
        size.height - (h - unten) / (oben - unten) * size.height;

    final linie = Path()..moveTo(x(punkte.first.meter), y(punkte.first.hoehe));
    for (final p in punkte.skip(1)) {
      linie.lineTo(x(p.meter), y(p.hoehe));
    }
    final gefuellt = Path.from(linie)
      ..lineTo(x(punkte.last.meter), size.height)
      ..lineTo(x(punkte.first.meter), size.height)
      ..close();

    // Der zurückgelegte Teil wird durch ein Fenster gefüllt, nicht durch
    // einen zweiten Pfad: So folgt die Kante genau der Höhenlinie,
    // stufenlos zwischen zwei Stützpunkten – ein aus Punkten gebauter
    // Teilpfad spränge von Punkt zu Punkt.
    final xJetzt = size.width * fortschritt.clamp(0.0, 1.0);
    canvas.drawPath(gefuellt, Paint()..color = kommend.withValues(alpha: 0.5));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, xJetzt, size.height));
    canvas.drawPath(gefuellt, Paint()..color = gefahren.withValues(alpha: 0.35));
    canvas.restore();

    canvas.drawPath(
      linie,
      Paint()
        ..color = gefahren
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawLine(Offset(xJetzt, 0), Offset(xJetzt, size.height),
        Paint()..color = marke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_Flugprofilmaler alt) =>
      alt.fortschritt != fortschritt ||
      alt.punkte != punkte ||
      alt.gefahren != gefahren;
}

/// Das Foto zur Stelle, oben rechts im Bild.
///
/// **Der Punkt, an dem sich eine Fotoverwaltung von einem Sportprogramm
/// unterscheidet.** Strava und Relive fliegen dieselbe Spur ab; nur hier
/// liegen die Bilder schon daneben. Beim Vorbeifliegen taucht das
/// Vorschaubild auf und verblasst wieder – nicht als Liste am Rand,
/// sondern zu der Stelle, an der es entstanden ist.
class _Flugbild extends StatelessWidget {
  const _Flugbild({required this.foto, required this.deckkraft});

  final Flugfoto? foto;
  final double deckkraft;

  /// Wie gross das Bild höchstens wird.
  ///
  /// Zweihundertvierzig Punkte. Grösser verdeckt es die Landschaft, um
  /// die es geht; kleiner erkennt man nicht, was darauf ist.
  static const double kante = 240;

  @override
  Widget build(BuildContext context) {
    final f = foto;
    // **`AnimatedOpacity` und kein `if`.** Ohne die Animation springt das
    // Bild beim Wechsel von einem zum nächsten hart um; das Auf- und
    // Abblenden über die Strecke (siehe `_fotoDeckkraft`) allein reicht
    // nicht, weil zwei dicht beieinander liegende Fotos einander
    // ablösen, ohne dass die Deckkraft dazwischen auf null fällt.
    return AnimatedOpacity(
      opacity: f == null ? 0 : deckkraft.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 180),
      // **Eine feste Breite, und der Grund ist eine Fehlermeldung.** Das
      // Bild haengt in einem `Positioned` mit nur `top` und `right`; die
      // Breite ist dort unbegrenzt, und eine `Column` mit `stretch`
      // darin bricht beim Vermessen ab.
      child: f == null
          ? const SizedBox(width: kante + 8, height: 1)
          : SizedBox(
              width: kante + 8,
              child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x66000000), blurRadius: 10, spreadRadius: 1),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: kante, maxHeight: kante),
                        child: Image(
                          image: f.bild,
                          fit: BoxFit.cover,
                          width: kante,
                          height: kante * 0.75,
                          // Ein Bild, das nicht kommt, darf keinen roten
                          // Kasten in die Landschaft setzen.
                          errorBuilder: (_, _, _) =>
                              const SizedBox(width: kante, height: 1),
                        ),
                      ),
                    ),
                    if (f.unterschrift case final u?)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 1),
                        child: Text(
                          u,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// Der Abspann – die Zahlen der Tour, wenn die Kamera wieder aufzieht.
///
/// **Was am Ende bleibt, ist nicht das letzte Bild, sondern die Bilanz.**
/// Bis hierher blieb der Flug einfach stehen, wo er zu Ende war; die
/// Zahlen standen zwar in der Leiste darunter, aber sie standen dort die
/// ganze Zeit und wurden zum Schluss nicht mehr angesehen.
class _Abspann extends StatelessWidget {
  const _Abspann({super.key, required this.flug, required this.tempo});

  /// Damit ein Test die Zahlen des Abspanns von denen der Flugleiste
  /// unterscheiden kann – beide zeigen „unterwegs".
  static const schluessel = ValueKey('gelaende-abspann');

  final Gelaendeflug flug;
  final double tempo;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    // **`format` will eine Zahl, keinen Text.** Der erste Anlauf reichte
    // `toStringAsFixed(1)` hinein; das wirft erst zur Laufzeit und nur
    // dann, wenn der Abspann wirklich erscheint – gefunden hat es der
    // Bedienungstest, nicht der Übersetzer.
    final zahl = NumberFormat(
        '#,##0.0', Localizations.localeOf(context).toLanguageTag());

    final hoch = flug.aufstiegMeter;
    final dauer = flug.gesamtdauer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 18, spreadRadius: 2),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${zahl.format(flug.laengeMeter / 1000)} km',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w300,
                color: farben.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hoch != null) ...[
                  _Zahl(wert: '${hoch.round()} m', was: t.flugAufstieg),
                  const SizedBox(width: AppSpacing.xl),
                ],
                if (dauer != null)
                  _Zahl(
                      wert: _dauerText(dauer), was: t.flugUnterwegs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dauerText(Duration d) {
    final st = d.inHours;
    final mi = d.inMinutes % 60;
    return st > 0 ? '$st:${mi.toString().padLeft(2, '0')} h' : '$mi min';
  }
}

class _Zahl extends StatelessWidget {
  const _Zahl({required this.wert, required this.was});
  final String wert;
  final String was;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(wert,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: farben.onSurface)),
        Text(was,
            style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant)),
      ],
    );
  }
}

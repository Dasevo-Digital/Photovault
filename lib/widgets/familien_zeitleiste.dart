import 'package:flutter/material.dart';

import '../services/zeitleiste.dart';
import '../theme/app_spacing.dart';

/// Die Familien-Zeitleiste: eine Zeile je Person, Balken von Geburt bis
/// Tod, Ereignisse als Marken darauf.
///
/// Was sie zeigt und die vier anderen Ansichten nicht: **Gleichzeitigkeit.**
/// Ein Stammbaum sagt, wer von wem abstammt; er sagt nicht, dass die
/// Urgroßmutter und der Enkel sich um elf Jahre verpasst haben. Auf einer
/// gemeinsamen Achse steht das im Bild, ohne dass jemand rechnen müsste.
///
/// **Nicht eine einzige Leinwand, sondern eine Liste gezeichneter
/// Zeilen** – anders als beim Fächer. Der Grund ist die Sprachausgabe:
/// Eine große Leinwand ist für sie eine leere Fläche, und der Fächer
/// braucht deshalb unsichtbare Felder daneben, die von Hand an ihre
/// Stellen gerechnet werden. Eine Liste bringt Beschriftung, Antippen und
/// träges Nachladen von selbst mit; zu zeichnen bleibt nur der Balken.
class FamilienZeitleiste extends StatelessWidget {
  /// Die Zeilen, unsortiert – die Reihenfolge macht [nachZeitSortiert].
  final List<Zeitzeile> zeilen;

  /// Wer in der Mitte steht. Diese Zeile wird hervorgehoben.
  final String fokusId;

  final void Function(String personId) onTippen;

  /// Was die Sprachausgabe zu einer Zeile sagt – Name, Lebensspanne,
  /// Zahl der Ereignisse.
  ///
  /// Von außen hereingegeben, damit dieses Widget ohne
  /// Übersetzungsapparat auskommt und trotzdem in der eingestellten
  /// Sprache spricht.
  final String Function(Zeitzeile zeile) beschriftung;

  const FamilienZeitleiste({
    super.key,
    required this.zeilen,
    required this.fokusId,
    required this.onTippen,
    required this.beschriftung,
  });

  static const _zeilenHoehe = 34.0;
  static const _achsenHoehe = 26.0;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final sortiert = nachZeitSortiert(zeilen);
    final spanne = zeitspanne(sortiert);
    final marken = spanne == null ? const <int>[] : jahresmarken(spanne);

    return LayoutBuilder(
      builder: (context, platz) {
        // Die Namensspalte wächst mit dem Fenster, aber nicht unbegrenzt:
        // Unter 96 Pixeln steht kein Name mehr, über 180 frisst sie die
        // Achse auf, auf der es hier eigentlich ankommt.
        final namensBreite = (platz.maxWidth * 0.28).clamp(96.0, 180.0);
        final anteile = [
          if (spanne != null)
            for (final j in marken) (jahr: j, x: spanne.anteil(DateTime(j))),
        ];

        return Column(
          children: [
            SizedBox(
              height: _achsenHoehe,
              child: Row(
                children: [
                  SizedBox(width: namensBreite + AppSpacing.md),
                  Expanded(
                    child: CustomPaint(
                      painter: _AchsenMaler(
                        marken: anteile,
                        farben: farben,
                        textRichtung: Directionality.of(context),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: sortiert.length,
                itemExtent: _zeilenHoehe,
                itemBuilder: (context, i) {
                  final z = sortiert[i];
                  final istFokus = z.personId == fokusId;
                  return Semantics(
                    container: true,
                    button: true,
                    label: beschriftung(z),
                    onTap: () => onTippen(z.personId),
                    // Ohne dies stünde der Name zweimal in der Ansage:
                    // einmal aus der Beschriftung, einmal aus dem Text
                    // daneben. Weil damit auch das Antippen des InkWell
                    // aus der Sprachausgabe fällt, steht es oben noch
                    // einmal ausdrücklich.
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () => onTippen(z.personId),
                      child: Container(
                        color: istFokus
                            ? farben.primaryContainer.withValues(alpha: 0.25)
                            : null,
                        child: Row(
                          children: [
                            const SizedBox(width: AppSpacing.md),
                            SizedBox(
                              width: namensBreite - AppSpacing.md,
                              child: Text(
                                z.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: istFokus
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  // Eine undatierte Zeile ist blass, nicht
                                  // weg: Dass jemand da ist und man von
                                  // ihm kein Datum hat, ist selbst eine
                                  // Auskunft.
                                  color: z.datiert
                                      ? farben.onSurface
                                      : farben.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: CustomPaint(
                                painter: _ZeilenMaler(
                                  zeile: z,
                                  spanne: spanne,
                                  gitter: [for (final m in anteile) m.x],
                                  farben: farben,
                                  hervorgehoben: istFokus,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Die Jahreszahlen über der Leiste.
class _AchsenMaler extends CustomPainter {
  final List<({int jahr, double x})> marken;
  final ColorScheme farben;
  final TextDirection textRichtung;

  _AchsenMaler({
    required this.marken,
    required this.farben,
    required this.textRichtung,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final m in marken) {
      final x = m.x * size.width;
      final maler = TextPainter(
        text: TextSpan(
          text: '${m.jahr}',
          style: TextStyle(
            fontSize: 11,
            color: farben.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: textRichtung,
      )..layout();
      // Die erste und die letzte Zahl werden nach innen gerückt, sonst
      // stehen sie halb außerhalb.
      final links = (x - maler.width / 2)
          .clamp(0.0, (size.width - maler.width).clamp(0.0, double.infinity));
      maler.paint(canvas, Offset(links, size.height - maler.height - 4));
      canvas.drawLine(
        Offset(x, size.height - 3),
        Offset(x, size.height),
        Paint()
          ..color = farben.outlineVariant
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_AchsenMaler alt) =>
      alt.marken != marken || alt.farben != farben;
}

/// Der Balken einer Person.
class _ZeilenMaler extends CustomPainter {
  final Zeitzeile zeile;
  final Zeitspanne? spanne;
  final List<double> gitter;
  final ColorScheme farben;
  final bool hervorgehoben;

  _ZeilenMaler({
    required this.zeile,
    required this.spanne,
    required this.gitter,
    required this.farben,
    required this.hervorgehoben,
  });

  static const _balkenHoehe = 12.0;
  static const _markenGroesse = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final mitte = size.height / 2;

    // Die senkrechten Hilfslinien laufen durch alle Zeilen hindurch –
    // erst dadurch lässt sich zwischen zwei weit auseinanderliegenden
    // Zeilen überhaupt vergleichen.
    final gitterStift = Paint()
      ..color = farben.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (final g in gitter) {
      final x = g * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gitterStift);
    }

    final s = spanne;
    if (s == null || !zeile.datiert) return;

    double x(DateTime d) => s.anteil(d) * size.width;

    final fuellung = hervorgehoben
        ? farben.primaryContainer
        : farben.secondaryContainer;
    final rand = hervorgehoben ? farben.primary : farben.outlineVariant;
    final markenFarbe = hervorgehoben
        ? farben.onPrimaryContainer
        : farben.onSecondaryContainer;

    final geburt = zeile.geburt;
    if (geburt != null) {
      final links = x(geburt);
      // Bei einer offenen Zeile reicht der feste Teil bis zum letzten
      // bekannten Zeitpunkt; danach läuft er gestrichelt weiter. Er hört
      // damit weder an einem erfundenen Ende auf noch zieht er bis heute
      // durch – beides wäre eine Behauptung.
      final festesEnde = zeile.offen
          ? x(zeile.spaeteste ?? geburt)
          : x(zeile.tod ?? geburt);
      // Mindestens so breit wie hoch: Wer nur mit Geburtsjahr eingetragen
      // ist, bekommt eine runde Marke statt eines Strichs von null
      // Breite. Das sind bei einem Jahrhundert auf dem Schirm gut ein
      // Jahr – weniger, als jede Jahresangabe ohnehin offen lässt.
      final rechts = festesEnde < links + _balkenHoehe
          ? links + _balkenHoehe
          : festesEnde;
      final balken = RRect.fromRectAndRadius(
        Rect.fromLTRB(links, mitte - _balkenHoehe / 2, rechts,
            mitte + _balkenHoehe / 2),
        const Radius.circular(_balkenHoehe / 2),
      );
      canvas.drawRRect(balken, Paint()..color = fuellung);
      canvas.drawRRect(
        balken,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = hervorgehoben ? 1.5 : 1
          ..color = rand,
      );
      if (zeile.offen && rechts < size.width - 2) {
        _gestrichelt(canvas, rechts + 3, size.width, mitte, rand);
      }
    } else {
      // Ohne Geburt gibt es keinen Balken – nur den Punkt, den man kennt.
      // Ein Balken, der irgendwo anfängt, wäre erfunden.
      final tod = zeile.tod;
      if (tod != null) {
        canvas.drawLine(
          Offset(x(tod), mitte - _balkenHoehe / 2),
          Offset(x(tod), mitte + _balkenHoehe / 2),
          Paint()
            ..color = rand
            ..strokeWidth = 2,
        );
      }
    }

    // Die Marken zuletzt, damit sie über dem Balken liegen.
    //
    // Alle in derselben Form: Bei zwölf Pixeln Zeilenhöhe wäre ein Symbol
    // je Ereignisart nicht mehr zu erkennen, und Farbe allein trägt keine
    // Auskunft, auf die man sich verlassen kann. Was ein Ereignis war,
    // steht im Lebenslauf; hier steht, wann und wie viele.
    for (final m in zeile.marken) {
      final punkt = Offset(x(m.datum), mitte);
      final raute = Path()
        ..moveTo(punkt.dx, punkt.dy - _markenGroesse)
        ..lineTo(punkt.dx + _markenGroesse, punkt.dy)
        ..lineTo(punkt.dx, punkt.dy + _markenGroesse)
        ..lineTo(punkt.dx - _markenGroesse, punkt.dy)
        ..close();
      canvas.drawPath(raute, Paint()..color = markenFarbe);
      // Ein heller Rand hält die Marke auch dort sichtbar, wo sie neben
      // dem Balken auf den Hintergrund fällt – nach dem Tod eingetragene
      // Ereignisse gibt es (Umbettung, Nachlass).
      canvas.drawPath(
        raute,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = farben.surface,
      );
    }
  }

  /// Die offene Fortsetzung.
  ///
  /// Bewusst leiser als der Balken: In einer Familie, in der bei den
  /// Lebenden kein Sterbedatum steht, ist die halbe Leiste gestrichelt.
  /// In voller Stärke gezeichnet übertönte das Unbekannte das Bekannte.
  void _gestrichelt(
      Canvas canvas, double von, double bis, double y, Color farbe) {
    const strich = 3.0;
    const luecke = 4.0;
    final stift = Paint()
      ..color = farbe.withValues(alpha: 0.55)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var x = von; x < bis; x += strich + luecke) {
      canvas.drawLine(
          Offset(x, y), Offset((x + strich).clamp(von, bis), y), stift);
    }
  }

  @override
  bool shouldRepaint(_ZeilenMaler alt) =>
      alt.zeile != zeile ||
      alt.spanne != spanne ||
      alt.hervorgehoben != hervorgehoben ||
      alt.farben != farben;
}

/// Die Meldungen, wie man sie sieht: oben rechts, gestapelt, wegklickbar.
///
/// **Warum nicht mehr unten.** Die SnackBar liegt am unteren Rand – dort,
/// wo in dieser App der Import-Knopf, die Auswahlleiste und die
/// Navigationsleiste des schmalen Fensters sitzen. Sie hat also
/// regelmässig genau das verdeckt, womit man weiterarbeiten wollte.
/// Oben rechts ist im Regelfall leer.
///
/// **Und warum unterhalb der Titelleiste.** Eine Einblendung ganz oben
/// rechts läge über den Knöpfen der AppBar. Der Stapel beginnt deshalb
/// eine Titelleistenhöhe tiefer – auf Bildschirmen ohne AppBar kostet das
/// etwas Platz, auf allen anderen verhindert es einen unbedienbaren Knopf.
///
/// **Im schmalen Fenster weicht er nach unten.** Bei wenig Breite wäre
/// eine Karte oben rechts entweder winzig oder über die ganze Breite –
/// und über die ganze Breite verdeckt sie oben mehr als unten.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Ab dieser Breite steht der Stapel oben rechts, darunter unten.
const double _schmalAb = 600;

/// Legt den Meldungsstapel über [kind]. Gehört in `MaterialApp.builder`,
/// damit er über jedem Bildschirm und über jedem geöffneten Blatt liegt.
///
/// **Mit eigenem Overlay.** `MaterialApp.builder` läuft *ausserhalb* des
/// Navigators – hier oben gibt es also weder Overlay noch Navigator.
/// Ohne ein eigenes Overlay wirft schon der erste Tooltip („Meldung
/// schliessen"), und ein Dialog liesse sich von hier gar nicht öffnen.
/// Genau deshalb steht der Verlauf als aufklappbare Tafel im Stapel und
/// nicht in einem Dialog.
Widget mitMeldungen(Widget? kind, {Meldungsdienst? dienst}) => Stack(
      children: [
        kind ?? const SizedBox.shrink(),
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) =>
                    Meldungsfenster(dienst: dienst ?? Meldungsdienst.zentral),
              ),
            ],
          ),
        ),
      ],
    );

class Meldungsfenster extends StatefulWidget {
  final Meldungsdienst dienst;

  const Meldungsfenster({super.key, required this.dienst});

  @override
  State<Meldungsfenster> createState() => _MeldungsfensterState();
}

class _MeldungsfensterState extends State<Meldungsfenster> {
  /// Die höchste bereits vorgelesene Nummer. Ohne sie würde jede
  /// Neuzeichnung – auch das blosse Ablaufen eines Balkens – dieselbe
  /// Meldung erneut ansagen.
  int _zuletztAngesagt = 0;

  @override
  void initState() {
    super.initState();
    widget.dienst.addListener(_geaendert);
  }

  @override
  void didUpdateWidget(Meldungsfenster alt) {
    super.didUpdateWidget(alt);
    if (alt.dienst != widget.dienst) {
      alt.dienst.removeListener(_geaendert);
      widget.dienst.addListener(_geaendert);
    }
  }

  @override
  void dispose() {
    widget.dienst.removeListener(_geaendert);
    super.dispose();
  }

  void _geaendert() {
    if (mounted) setState(() {});
  }

  /// **Eine Meldung, die nur erscheint, wird nicht vorgelesen.** Die
  /// SnackBar hatte das umsonst; hier muss es von Hand kommen.
  void _ansagen(List<Meldung> sichtbare) {
    for (final m in sichtbare) {
      if (m.nummer <= _zuletztAngesagt) continue;
      _zuletztAngesagt = m.nummer;
      // Die Ansage gehört an die Ansicht, in der die Meldung steht –
      // `announce` ohne Ansicht ist abgekündigt, weil es bei mehreren
      // Fenstern nicht mehr eindeutig ist.
      SemanticsService.sendAnnouncement(
        View.of(context),
        m.text,
        Directionality.of(context),
      );
    }
  }

  /// Ob die Verlaufstafel aufgeklappt ist.
  bool _verlaufOffen = false;

  void _verlaufUmschalten() {
    setState(() => _verlaufOffen = !_verlaufOffen);
    if (_verlaufOffen) widget.dienst.verlaufGelesen();
  }

  @override
  Widget build(BuildContext context) {
    final sichtbare = widget.dienst.sichtbare;
    _ansagen(sichtbare);

    final t = AppTexte.of(context);
    final breite = MediaQuery.of(context).size.width;
    final schmal = breite < _schmalAb;
    final ungelesen = widget.dienst.ungelesen;

    if (sichtbare.isEmpty && ungelesen == 0 && !_verlaufOffen) {
      return const SizedBox.shrink();
    }

    final karten = <Widget>[
      if (ungelesen > 0 || _verlaufOffen)
        Align(
          alignment: schmal ? Alignment.centerLeft : Alignment.centerRight,
          child: _Glocke(
            anzahl: ungelesen,
            beiDruck: _verlaufUmschalten,
            beschriftung: t.meldungenGlocke,
            offen: _verlaufOffen,
          ),
        ),
      if (_verlaufOffen)
        _Verlaufstafel(
          dienst: widget.dienst,
          beiSchliessen: _verlaufUmschalten,
        ),
      // Erst ab dreien: Bei zweien ist einzeln wegklicken schneller als
      // erst den Sammelknopf zu suchen.
      if (sichtbare.length > 2)
        Align(
          alignment: schmal ? Alignment.centerLeft : Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.dienst.alleSchliessen,
            icon: const Icon(Icons.clear_all, size: 16),
            label: Text(t.meldungenAlleSchliessen),
          ),
        ),
      for (final m in sichtbare)
        _Meldungskarte(
          key: ValueKey(m.nummer),
          meldung: m,
          beiSchliessen: () => widget.dienst.schliesse(m.nummer),
        ),
    ];

    // **Ohne IgnorePointer.** Naheliegend wäre, die Fläche neben den
    // Karten ausdrücklich durchlässig zu machen. Nötig ist es nicht:
    // `Align` und `Padding` prüfen nur ihr Kind auf Treffer, ihre eigene
    // Fläche fangen sie nicht ab. Ein IgnorePointer darüber wäre sogar
    // schädlich – er nähme den ganzen Teilbaum aus der Trefferprüfung,
    // und ein inneres `ignoring: false` holte ihn nicht zurück.
    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: schmal ? AppSpacing.lg : kToolbarHeight + AppSpacing.md,
            bottom: AppSpacing.lg,
          ),
          child: Align(
            alignment: schmal ? Alignment.bottomCenter : Alignment.topRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < karten.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    karten[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Farbe und Symbol einer Art – an einer Stelle, damit Einblendung und
/// Verlauf nicht auseinanderlaufen.
({Color farbe, IconData symbol, String name}) _aussehen(
    BuildContext context, Meldungsart art) {
  final schema = Theme.of(context).colorScheme;
  final semantik = Theme.of(context).extension<AppSemantik>();
  final t = AppTexte.of(context);
  return switch (art) {
    Meldungsart.hinweis => (
        farbe: schema.primary,
        symbol: Icons.info_outline,
        name: t.meldungArtHinweis,
      ),
    Meldungsart.erfolg => (
        farbe: semantik?.erfolg ?? schema.primary,
        symbol: Icons.check_circle_outline,
        name: t.meldungArtErfolg,
      ),
    Meldungsart.warnung => (
        farbe: semantik?.warnung ?? schema.tertiary,
        symbol: Icons.warning_amber_outlined,
        name: t.meldungArtWarnung,
      ),
    Meldungsart.fehler => (
        farbe: schema.error,
        symbol: Icons.error_outline,
        name: t.meldungArtFehler,
      ),
  };
}

class _Glocke extends StatelessWidget {
  final int anzahl;
  final VoidCallback beiDruck;
  final String beschriftung;
  final bool offen;

  const _Glocke({
    required this.anzahl,
    required this.beiDruck,
    required this.beschriftung,
    required this.offen,
  });

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$beschriftung ($anzahl)',
      child: Tooltip(
        message: beschriftung,
        child: Material(
          color: schema.surfaceContainerHighest,
          shape: const StadiumBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: beiDruck,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      offen
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none,
                      size: 18,
                      color: schema.onSurfaceVariant),
                  if (anzahl > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text('$anzahl',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Meldungskarte extends StatelessWidget {
  final Meldung meldung;
  final VoidCallback beiSchliessen;

  const _Meldungskarte({
    super.key,
    required this.meldung,
    required this.beiSchliessen,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final schema = Theme.of(context).colorScheme;
    final aussehen = _aussehen(context, meldung.art);

    return Semantics(
      liveRegion: true,
      child: Material(
        color: schema.surfaceContainerHigh,
        elevation: 4,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(aussehen.symbol, size: 20, color: aussehen.farbe),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meldung.text,
                            style: Theme.of(context).textTheme.bodyMedium),
                        if (meldung.anzahl > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text(
                              t.meldungWiederholt(meldung.anzahl),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: schema.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (meldung.aktion != null)
                    TextButton(
                      onPressed: () {
                        meldung.aktion!.beiDruck();
                        beiSchliessen();
                      },
                      child: Text(meldung.aktion!.beschriftung),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: t.meldungSchliessen,
                    visualDensity: VisualDensity.compact,
                    onPressed: beiSchliessen,
                  ),
                ],
              ),
            ),
            // Der ablaufende Balken – er sagt, wie viel Zeit noch bleibt,
            // statt dass die Karte ohne Vorwarnung verschwindet. Bei einem
            // Fehler gibt es ihn nicht, weil dort nichts abläuft.
            if (meldung.dauer != null)
              _Ablauf(dauer: meldung.dauer!, farbe: aussehen.farbe),
          ],
        ),
      ),
    );
  }
}

class _Ablauf extends StatelessWidget {
  final Duration dauer;
  final Color farbe;

  const _Ablauf({required this.dauer, required this.farbe});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: dauer,
      builder: (context, wert, _) => ClipRRect(
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(AppRadius.md)),
        child: LinearProgressIndicator(
          value: wert,
          minHeight: 3,
          color: farbe,
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}

/// Der Verlauf: was gemeldet wurde, neueste zuerst.
///
/// Eine Tafel im Stapel, kein Dialog – hier oben gibt es keinen
/// Navigator (siehe [mitMeldungen]). Sie klappt unter der Glocke auf,
/// also genau dort, wo die Meldungen standen.
class _Verlaufstafel extends StatelessWidget {
  final Meldungsdienst dienst;
  final VoidCallback beiSchliessen;

  const _Verlaufstafel({required this.dienst, required this.beiSchliessen});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final schema = Theme.of(context).colorScheme;
    final verlauf = dienst.verlauf;
    return Material(
      color: schema.surfaceContainerHigh,
      elevation: 4,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ConstrainedBox(
        // Höchstens die halbe Höhe: Ein Verlauf mit fünfzig Zeilen wäre
        // sonst der Bildschirm.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height / 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t.meldungenTitel,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (verlauf.isNotEmpty)
                    TextButton(
                      onPressed: dienst.verlaufLeeren,
                      child: Text(t.meldungenVerlaufLeeren),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: beiSchliessen,
                  ),
                ],
              ),
            ),
            if (verlauf.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(t.meldungenKeine),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  children: [
                    for (final m in verlauf) _Verlaufszeile(meldung: m),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Verlaufszeile extends StatelessWidget {
  final Meldung meldung;

  const _Verlaufszeile({required this.meldung});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final aussehen = _aussehen(context, meldung.art);
    final uhrzeit = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(meldung.zeit));
    return ListTile(
      dense: true,
      leading: Icon(aussehen.symbol, color: aussehen.farbe),
      title: Text(meldung.text),
      subtitle: Text(meldung.anzahl > 1
          ? '$uhrzeit · ${aussehen.name} · ${t.meldungWiederholt(meldung.anzahl)}'
          : '$uhrzeit · ${aussehen.name}'),
    );
  }
}

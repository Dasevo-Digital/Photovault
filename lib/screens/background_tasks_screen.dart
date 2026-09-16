import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/hintergrundlauf.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../services/meldungsdienst.dart';

/// Eine Aktion innerhalb einer [_TaskCard] – startet einen der
/// `Stream<ImportProgress>`-Backfills auf [LibraryState] als Lauf, der das
/// Wegnavigieren überlebt.
/// Einheitlicher Hinweistext für ein fehlendes KI-Modell/Datenset – dieselbe
/// Formulierung wie in ToolsScreen (Werkzeuge), damit beide Einstiegspunkte
/// nicht auseinanderdriften.
String? _modelHint(AppTexte t, bool available, String model, String where) =>
    available ? null : t.aufgModellNoetig(model, where);

/// Wie viel eine Aufgabe anfasst.
///
/// **Zwei Angaben statt fünfzehn.** Vorher trug jede Aktion ihre eigene
/// Beschriftung und ihr eigenes Symbol: „Fehlende", „Neue Fotos",
/// „Ungetaggte", „Starten", „Alle erneut", „Alle neu", „Alle Fotos" – sieben
/// Wörter für zwei Sachverhalte, und auf welchem Knopf welches stand, war
/// von Karte zu Karte verschieden. Gemeint ist immer dasselbe: entweder
/// alles, oder nur das, was noch fehlt.
enum Aufgabenmodus {
  /// Über den ganzen Bestand, auch über das, was schon ein Ergebnis hat.
  alle,

  /// Nur über das, was noch keines hat.
  fehlende,
}

String modusName(AppTexte t, Aufgabenmodus m) => switch (m) {
      Aufgabenmodus.alle => t.aufgModusAlle,
      Aufgabenmodus.fehlende => t.aufgFehlende,
    };

IconData modusSymbol(Aufgabenmodus m) => switch (m) {
      Aufgabenmodus.alle => Icons.all_inclusive,
      Aufgabenmodus.fehlende => Icons.image_search,
    };

/// Eine der Möglichkeiten, eine Aufgabe zu starten.
class Aufgabenaktion {
  final Aufgabenmodus modus;

  /// Was während des Laufs in der Karte steht.
  final String laufTitel;

  /// Was statt „0 / 0" dasteht, wenn es nichts zu tun gab.
  final String emptyMessage;

  final Stream<ImportProgress> Function() stream;

  /// Wie die Schlussbilanz heisst – siehe [Hintergrundlauf.bilanztext].
  /// `null` bei allen Aufgaben, bei denen angesehen und getan dasselbe ist.
  final String Function(int getan, int gesamt)? bilanztext;

  /// Rückfrage vor dem Start, oder `null`.
  ///
  /// Zwei Aufgaben haben eine, und beide aus demselben Grund: Sie fassen
  /// Dateien auf der Platte an. Die Datumskorrektur schreibt Aufnahmedaten
  /// um und verschiebt danach, das Neuordnen der Ablage verschiebt ohne
  /// das Datum anzufassen. Alle anderen ergänzen nur Fehlendes, und eine
  /// Rückfrage, die man immer bejaht, liest bald niemand mehr.
  final Future<bool> Function(BuildContext)? bestaetigung;

  const Aufgabenaktion({
    required this.modus,
    required this.laufTitel,
    required this.emptyMessage,
    required this.stream,
    this.bilanztext,
    this.bestaetigung,
  });
}

class _Laufanzeige extends StatelessWidget {
  final Hintergrundlauf lauf;
  const _Laufanzeige({required this.lauf});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;

    final String satz;
    if (lauf.fehler != null) {
      satz = t.fortschrittFehlgeschlagen('${lauf.fehler}');
    } else if (lauf.gesamt == 0) {
      // Der Strom war sofort durch: Es gab nichts nachzuholen. Die Meldung
      // der Karte ist genauer als ein „0 / 0".
      satz = lauf.beendet ? lauf.leermeldung : t.aufgWirdErmittelt;
    } else if (lauf.abgebrochen) {
      satz = t.aufgAbgebrochenBei(lauf.erledigt, lauf.gesamt);
    } else if (lauf.beendet) {
      // Was der Lauf wirklich getan hat, geht vor: „N bearbeitet" ist
      // die Zahl der angesehenen Dinge.
      final getan = lauf.getan;
      satz = (getan != null && lauf.bilanztext != null)
          ? lauf.bilanztext!(getan, lauf.gesamt)
          : t.aufgFertigMit(lauf.gesamt);
    } else {
      satz = '${lauf.erledigt} / ${lauf.gesamt}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lauf.titel, style: TextStyle(fontSize: 13, color: farben.onSurface)),
        const SizedBox(height: AppSpacing.sm),
        // Ein Balken auch im beendeten Zustand, damit die Karte nicht in der
        // Höhe springt, sobald der Vorgang durch ist.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: lauf.beendet ? 1.0 : lauf.anteil,
            minHeight: 6,
            color: lauf.fehler != null ? farben.error : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          satz,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: lauf.fehler != null ? farben.error : farben.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (lauf.laeuft && lauf.datei != null)
          Text(
            lauf.datei!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Ein Zahlenfeld der Kopfzeile: Beschriftung links, Wert rechts.
///
/// Zwei davon nebeneinander bilden die Zeile „Aktiv / Wartend" – das
/// auffällige Feld links, das ruhige rechts.
class _Zahlenfeld extends StatelessWidget {
  final String beschriftung;
  final String wert;
  final bool hervorgehoben;
  const _Zahlenfeld({
    required this.beschriftung,
    required this.wert,
    this.hervorgehoben = false,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // Die Paare aus dem Farbschema statt eigener Werte: Sie sind auf
    // ausreichenden Kontrast ausgelegt und gelten in beiden Helligkeiten.
    final grund = hervorgehoben ? farben.primaryContainer : farben.surfaceContainerHighest;
    final schrift = hervorgehoben ? farben.onPrimaryContainer : farben.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(color: grund, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(beschriftung,
                overflow: TextOverflow.ellipsis, style: TextStyle(color: schrift)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(wert,
              style: TextStyle(
                color: schrift,
                fontWeight: FontWeight.w600,
                // Damit die Zahlen zweier Karten untereinander fluchten.
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ],
      ),
    );
  }
}

/// Die Zahlenzeile einer Karte.
class _Zahlenreihe extends StatelessWidget {
  final String linksBeschriftung;
  final String linksWert;
  final String rechtsBeschriftung;
  final String rechtsWert;
  const _Zahlenreihe({
    required this.linksBeschriftung,
    required this.linksWert,
    required this.rechtsBeschriftung,
    required this.rechtsWert,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Zahlenfeld(
              beschriftung: linksBeschriftung, wert: linksWert, hervorgehoben: true),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Zahlenfeld(beschriftung: rechtsBeschriftung, wert: rechtsWert),
        ),
      ],
    );
  }
}

/// Ein Knopf der Aktionsleiste.
///
/// Bewusst nicht [Aufgabenaktion]: Die Gesamtanalyse-Karte startet nicht über
/// ein Fortschrittsfenster, sondern über [LibraryState]. Sie müsste sonst
/// eine Aktion mit leerem Strom und leerem Titel erfinden, nur um in die
/// Leiste zu passen.
class _Leistenknopf {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _Leistenknopf({required this.label, required this.icon, this.onTap});
}

/// Die Aktionsleiste rechts an der Karte, über deren volle Höhe.
///
/// Die Knöpfe stehen aussen statt unter dem Text, weil sie dadurch bei allen
/// Karten an derselben Stelle sitzen – gleich, ob die Beschreibung ein oder
/// zwei Zeilen braucht. Man findet „Alle erneut" dann mit den Augen, ohne
/// jede Karte einzeln zu lesen.
class _Aktionsleiste extends StatelessWidget {
  final List<_Leistenknopf> knoepfe;

  /// Falsch, wenn ein Modell oder Datensatz fehlt – die Knöpfe sind dann
  /// abgeschaltet, der Grund steht in der Karte.
  final bool bedienbar;

  const _Aktionsleiste({required this.knoepfe, required this.bedienbar});

  /// Fest, nicht anteilig: Zwei Karten nebeneinander hätten sonst
  /// unterschiedlich breite Leisten, je nach Länge ihrer Beschreibung.
  static const double breite = 112;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Container(
      width: breite,
      color: farben.surfaceContainerHigh,
      child: Column(
        children: [
          for (var i = 0; i < knoepfe.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: farben.outlineVariant),
            Expanded(
              child: InkWell(
                onTap: bedienbar ? knoepfe[i].onTap : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.md),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(knoepfe[i].icon,
                          size: 26,
                          color: bedienbar ? farben.onSurface : farben.onSurface.withValues(alpha: 0.38)),
                      const SizedBox(height: 6),
                      Text(
                        knoepfe[i].label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: bedienbar
                              ? farben.onSurfaceVariant
                              : farben.onSurface.withValues(alpha: 0.38),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Der gemeinsame Rahmen aller Aufgabenkarten: links Inhalt, rechts die
/// Aktionsleiste über die volle Höhe.
class _Aufgabenrahmen extends StatelessWidget {
  final IconData icon;
  final String titel;
  final String beschreibung;
  final Widget inhalt;
  final List<_Leistenknopf> knoepfe;
  final bool bedienbar;

  /// Diese Karte ist das Ziel eines Verweises von aussen (siehe
  /// [BackgroundTasksScreen.hervorheben]).
  final bool hervorgehoben;

  const _Aufgabenrahmen({
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.inhalt,
    required this.knoepfe,
    required this.bedienbar,
    this.hervorgehoben = false,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: hervorgehoben
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: farben.primary, width: 2),
            )
          : null,
      // Ohne das Beschneiden stünde die Leiste rechts über die abgerundeten
      // Ecken der Karte hinaus.
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 20, color: farben.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(titel,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: farben.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(beschreibung,
                        style: TextStyle(fontSize: 13, color: farben.onSurfaceVariant)),
                    const SizedBox(height: AppSpacing.md),
                    inhalt,
                  ],
                ),
              ),
            ),
            _Aktionsleiste(knoepfe: knoepfe, bedienbar: bedienbar),
          ],
        ),
      ),
    );
  }
}

/// Alles, was eine Aufgabe ausmacht – als Angabe, nicht als Baustein.
///
/// **Warum als Daten.** Dieselbe Liste speist zwei Dinge: die Karten dieses
/// Bildschirms und den Dialog „Aufgabe erstellen", der mehrere auf einmal
/// einreiht. Als Widget-Baum geschrieben liesse sich die Liste nur ansehen,
/// nicht befragen – der Dialog müsste seine eigene führen, und die beiden
/// liefen beim ersten Zusatz auseinander.
class Aufgabe {
  /// Kennung des Laufs. Fest im Quelltext vergeben statt aus dem Titel
  /// abgeleitet: Ein übersetzter Titel wäre in jeder Sprache eine andere
  /// Kennung, und ein beim Sprachwechsel laufender Vorgang verschwände aus
  /// seiner Karte.
  final String schluessel;

  final IconData icon;
  final String titel;
  final String beschreibung;

  /// Wie viele Fotos dieser Aufgabe noch fehlen.
  final Future<int> Function() offeneZahl;

  /// Beschriftung der offenen Zahl, wenn „offen" nicht das richtige Wort
  /// ist – bei „neu rendern" etwa sind es nicht offene, sondern betroffene
  /// Fotos.
  final String? offenLabel;

  /// Ob diese Aufgabe zu den teuren gehört (KI-Modell im Speicher oder
  /// dieselbe Arbeit wie eine Stufe der Hintergrundanalyse). Nur solche
  /// warten aufeinander – siehe [LibraryState.maxGleichzeitig].
  final bool rechenintensiv;

  /// Die Stufe der Hintergrundanalyse, die dieselbe Arbeit erledigt – oder
  /// `null`, wenn diese Aufgabe nur von Hand läuft.
  final Analysestufe? stufe;

  /// Gesetzt, wenn ein Modell oder Datensatz fehlt: Die Aufgabe steht dann
  /// mit dem Grund da, statt bedienbar zu sein.
  final String? nichtVerfuegbar;

  final List<Aufgabenaktion> aktionen;

  const Aufgabe({
    required this.schluessel,
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.offeneZahl,
    required this.aktionen,
    this.offenLabel,
    this.rechenintensiv = false,
    this.stufe,
    this.nichtVerfuegbar,
  });

  bool get bedienbar => nichtVerfuegbar == null;

  /// Die Aktion, die der Sammeldialog nimmt.
  ///
  /// Dort wird angekreuzt, nicht je Aufgabe zwischen zwei Knöpfen gewählt.
  /// Gibt es den gewünschten Modus nicht, tut es der andere: Bei „XMP
  /// schreiben" gibt es nur „Alle", und diese Aufgabe deshalb aus einer
  /// Sammelauswahl herauszulassen wäre schwerer zu verstehen als sie
  /// mitlaufen zu lassen.
  Aufgabenaktion aktionFuer(Aufgabenmodus modus) =>
      aktionen.firstWhere((a) => a.modus == modus, orElse: () => aktionen.first);
}

/// Eine Aufgaben-Karte: Symbol und Titel, Kurzbeschreibung, die Zahlen
/// „Aktiv" und „Wartend", darunter die Zahl der offenen Fotos, und rechts
/// die Aktionsleiste.
///
/// **„Aktiv" und „Wartend" zählen Aufgaben, nicht Fotos.** Seit es die
/// Warteschlange gibt (siehe [LibraryState.reiheAufgabeEin]), ist das eine
/// echte Aussage: Wer drei schwere Aufgaben anstösst, sieht eine aktiv und
/// zwei wartend. Vorher wurde die zweite abgewiesen, und „Wartend" trug
/// die Zahl der offenen Fotos – zwei verschiedene Dinge unter einem Wort.
/// Die offenen Fotos stehen jetzt in eigener Zeile darunter.
///
/// Eine Aufgabe kann auch aktiv sein, ohne dass jemand sie hier gestartet
/// hat: Vier von ihnen sind zugleich Stufen der Hintergrundanalyse
/// ([Aufgabe.stufe]), die nach dem Import von selbst läuft.
class _TaskCard extends StatefulWidget {
  final LibraryState library;
  final Aufgabe aufgabe;
  final bool hervorgehoben;
  const _TaskCard(
      {required this.library,
      required this.aufgabe,
      this.hervorgehoben = false});

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  Aufgabe get _a => widget.aufgabe;

  // Nur berechnen, wenn die Karte den Zähler überhaupt anzeigt – bei
  // fehlendem Modell würde die Abfrage sonst unnötig eine volle
  // Tabellen-Zählung auslösen, ohne dass das Ergebnis je sichtbar wird.
  late Future<int>? _countFuture = _a.bedienbar ? _a.offeneZahl() : null;

  /// Ob der Lauf dieser Karte beim letzten Bescheid schon beendet war –
  /// damit der Zähler genau einmal aufgefrischt wird, wenn ein Vorgang
  /// durchläuft, und nicht bei jedem der tausenden Fortschritts-Bescheide.
  bool _warBeendet = true;

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_aufLaufwechsel);
  }

  @override
  void dispose() {
    widget.library.removeListener(_aufLaufwechsel);
    super.dispose();
  }

  void _aufLaufwechsel() {
    final lauf = widget.library.lauf(_a.schluessel);
    final beendet = lauf == null || lauf.beendet;
    if (beendet && !_warBeendet) _refreshCount();
    _warBeendet = beendet;
  }

  void _refreshCount() {
    if (!_a.bedienbar || !mounted) return;
    // Die Abfrage VOR setState anstossen und nur die fertige Future
    // hineinreichen: Ein Pfeilrumpf gäbe hier das `Future` der Zuweisung
    // zurück, und setState verbietet einen Rückgabewert dieser Art
    // ausdrücklich (Zusicherung im Framework).
    final naechste = _a.offeneZahl();
    setState(() {
      // Ein Pfeilrumpf gäbe hier das `Future` der Zuweisung zurück, und
      // setState verbietet einen Rückgabewert dieser Art ausdrücklich.
      _countFuture = naechste;
    });
  }

  Future<void> _runAction(Aufgabenaktion action) async {
    final bestaetigung = action.bestaetigung;
    if (bestaetigung != null && !await bestaetigung(context)) return;
    if (!mounted) return;
    final abweisung = reiheEin(widget.library, _a, action);
    if (abweisung != null) {
      melde.warnung(abweisungstext(AppTexte.of(context), abweisung));
    }
  }

  /// Wie viele Fotos die Hintergrundanalyse in dieser Stufe gerade noch vor
  /// sich hat – `0`, wenn sie nicht läuft oder woanders steht.
  int _analyseOffen() {
    final analyse = widget.library.analyse;
    if (analyse == null || analyse.stufe != _a.stufe) return 0;
    final offen = analyse.gesamt - analyse.erledigt;
    return offen < 0 ? 0 : offen;
  }

  @override
  Widget build(BuildContext context) {
    // Auf LibraryState hören, damit die Zahlen mitlaufen – auch während die
    // Hintergrundanalyse arbeitet, und für den eigenen Lauf dieser Karte.
    return ListenableBuilder(
      listenable: widget.library,
      builder: (context, _) {
        final t = AppTexte.of(context);
        final lauf = widget.library.lauf(_a.schluessel);

        // Aktiv: der eigene Lauf, und die Analyse, wenn sie gerade genau
        // diese Stufe abarbeitet. Beides sind Aufgaben, die diese Arbeit
        // tun – die Karte, die nur die eine zählte, log die andere weg.
        final aktiv = (lauf?.laeuft ?? false ? 1 : 0) +
            (_analyseOffen() > 0 ? 1 : 0);
        final wartend = (lauf?.wartet ?? false) ? 1 : 0;

        // Während ein Lauf offen ist, tritt die Aktionsleiste hinter einen
        // einzigen Knopf zurück: Abbrechen, solange etwas aussteht, danach
        // Schliessen. Mehrere Aktionen anzubieten, von denen keine etwas
        // tut, wäre die schlechtere Antwort als eine, die zum Zustand passt.
        final List<_Leistenknopf> knoepfe;
        if (lauf == null) {
          knoepfe = [
            for (final aktion in _a.aktionen)
              _Leistenknopf(
                label: modusName(t, aktion.modus),
                icon: modusSymbol(aktion.modus),
                onTap: () => unawaited(_runAction(aktion)),
              ),
          ];
        } else if (lauf.offen) {
          knoepfe = [
            _Leistenknopf(
              label: t.allgAbbrechen,
              icon: Icons.stop_circle_outlined,
              onTap: () => widget.library.brichAufgabeAb(_a.schluessel),
            ),
          ];
        } else {
          knoepfe = [
            _Leistenknopf(
              label: t.allgSchliessen,
              icon: Icons.check,
              onTap: () {
                widget.library.verwerfeLauf(_a.schluessel);
                _refreshCount();
              },
            ),
          ];
        }

        return _Aufgabenrahmen(
          hervorgehoben: widget.hervorgehoben,
          icon: _a.icon,
          titel: _a.titel,
          beschreibung: _a.beschreibung,
          knoepfe: knoepfe,
          bedienbar: _a.bedienbar,
          inhalt: _a.nichtVerfuegbar != null
              ? Text(_a.nichtVerfuegbar!,
                  style: TextStyle(fontSize: 12, color: context.semantik.warnung))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Zahlenreihe(
                      linksBeschriftung: t.aufgAktiv,
                      linksWert: '$aktiv',
                      rechtsBeschriftung: t.aufgWartend,
                      rechtsWert: '$wartend',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (lauf != null)
                      _Laufanzeige(lauf: lauf)
                    else
                      FutureBuilder<int>(
                        future: _countFuture,
                        builder: (context, snapshot) => Text(
                          snapshot.hasData
                              ? (_a.offenLabel == null
                                  ? t.aufgOffeneFotos(snapshot.data!)
                                  : '${_a.offenLabel}: ${snapshot.data}')
                              : '…',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

/// Reiht [aktion] von [aufgabe] ein – der eine Weg, auf dem in dieser App
/// eine Aufgabe startet.
///
/// Als freie Funktion, weil zwei Stellen sie brauchen: die Karte und der
/// Sammeldialog. Kein `await`: Der Lauf soll weiterlaufen, wenn dieser
/// Bildschirm längst weg ist.
Startabweisung? reiheEin(
        LibraryState library, Aufgabe aufgabe, Aufgabenaktion aktion) =>
    library.reiheAufgabeEin(
      schluessel: aufgabe.schluessel,
      titel: aktion.laufTitel,
      leermeldung: aktion.emptyMessage,
      bilanztext: aktion.bilanztext,
      strom: aktion.stream,
      rechenintensiv: aufgabe.rechenintensiv,
    );

/// Sonderkarte für [LibraryState.starteHintergrundanalyse]: läuft (anders als
/// die übrigen Aufgaben hier) bereits echt im Hintergrund weiter, während man
/// navigiert – deshalb zeigt sie neben der Zahl der aktiven Fotos die gerade
/// bearbeitete Stufe im Klartext, gespeist aus
/// [LibraryState.analyse]/[LibraryState.analyseLaeuft] über ListenableBuilder
/// (LibraryState ist ein ChangeNotifier).
class _CombinedAnalysisCard extends StatelessWidget {
  final LibraryState library;
  const _CombinedAnalysisCard({required this.library});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final t = AppTexte.of(context);
        final analyse = library.analyse;
        final laeuft = library.analyseLaeuft;
        final offen = analyse == null ? 0 : (analyse.gesamt - analyse.erledigt).clamp(0, 1 << 31);

        return _Aufgabenrahmen(
          icon: Icons.auto_awesome_outlined,
          titel: t.werkzAllesNachholenTitel,
          beschreibung: t.werkzAllesNachholenText,
          // Anders als bei den übrigen Karten bleibt die Leiste bedienbar,
          // während gearbeitet wird – sonst gäbe es keinen Weg, einen Lauf
          // über 8000 Fotos wieder anzuhalten, ausser die App zu beenden.
          bedienbar: true,
          knoepfe: [
            if (laeuft)
              _Leistenknopf(
                label: t.allgAbbrechen,
                icon: Icons.stop_circle_outlined,
                onTap: library.brichHintergrundanalyseAb,
              )
            else
              _Leistenknopf(
                label: t.aufgJetztStarten,
                icon: Icons.play_arrow,
                onTap: () {
                  library.starteHintergrundanalyse();
                  melde.hinweis(t.aufgLaeuft);
                },
              ),
          ],
          inhalt: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Zahlenreihe(
                linksBeschriftung: t.aufgAktiv,
                linksWert: '$offen',
                rechtsBeschriftung: t.aufgStatus,
                rechtsWert: laeuft && analyse != null
                    ? t.aufgStufeKurz(analyse.stufeNummer, analyse.stufenGesamt)
                    : t.aufgBereit,
              ),
              if (laeuft && analyse != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  t.aufgStufe(analysestufeName(t, analyse.stufe), analyse.erledigt,
                      analyse.gesamt, analyse.stufeNummer, analyse.stufenGesamt),
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Alle Aufgaben, in der Reihenfolge, in der sie auf dem Bildschirm stehen.
///
/// Öffentlich, damit ein Prüfstand sie befragen kann: Dass jede Aufgabe eine
/// eindeutige Kennung hat und mindestens eine Aktion, lässt sich so
/// nachrechnen, statt es fünfzehnmal von Hand nachzusehen.
List<Aufgabe> aufgabenliste(AppTexte t, LibraryState library) => [
      Aufgabe(
        schluessel: 'gesichter',
        rechenintensiv: true,
        // Dieselbe Stufe wie Unschärfe und Einbettung: Der gemeinsame
        // Durchgang der Analyse dekodiert jedes Foto einmal und erledigt
        // alle drei daran. Ohne diese Angabe stand hier „Aktiv 0",
        // während die Analyse sichtbar genau diese Arbeit tat.
        stufe: Analysestufe.bildanalyse,
        icon: Icons.face_retouching_natural,
        titel: t.werkzGesichterScannenTitel,
        beschreibung: t.aufgGesichterText,
        offeneZahl: () => library.db.countFaceScan(onlyNew: true),
        nichtVerfuegbar: _modelHint(
            t, library.faceDetectionAvailable, t.aufgYunetModell, t.aufgWoModelle),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzScanneAlle,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.rescanFaces(onlyNewPhotos: false),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzScanneNeue,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.rescanFaces(onlyNewPhotos: true),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'wiedererkennung',
        icon: Icons.person_search_outlined,
        titel: t.aufgWiedererkennungTitel,
        beschreibung: t.aufgWiedererkennungText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countWiedererkennungOffen(),
        aktionen: [
          // „Alle" fragt auch dort noch einmal, wo schon verglichen
          // wurde – der Weg, nachdem neue Personen benannt wurden: Ein
          // Gesicht ohne Kern von damals kann heute einen haben.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzWiedererkennung,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillWiedererkennung(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzWiedererkennung,
            emptyMessage: t.werkzAlleVerglichen,
            stream: () => library.backfillWiedererkennung(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'vorschau',
        icon: Icons.photo_size_select_actual_outlined,
        // Ein eigener Titel und nicht mehr die Abschnittsüberschrift der
        // Werkzeuge: Dieselbe Zeichenkette an zwei Stellen liest sich
        // harmlos und macht jede Prüfung „steht diese Aufgabe wirklich
        // nur hier?" unmöglich.
        titel: t.aufgVorschauTitel,
        beschreibung: t.aufgVorschauText,
        offeneZahl: () => library.db.countThumbnailRegen(onlyMissing: true),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzErstelleAlle,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.regenerateThumbnails(onlyMissing: false),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzErstelleFehlende,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.regenerateThumbnails(onlyMissing: true),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'ocr',
        rechenintensiv: true,
        icon: Icons.text_fields,
        titel: t.aufgOcrTitel,
        stufe: Analysestufe.texterkennung,
        beschreibung: t.aufgOcrText,
        offeneZahl: () => library.db.countOcrBackfill(),
        // Auf macOS immer verfügbar (Vision-Framework), sonst erst mit
        // den beiden nachgeladenen Modellen.
        nichtVerfuegbar:
            _modelHint(t, library.ocrAvailable, t.aufgOcrModell, t.aufgWoModelle),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzErkenneText,
            emptyMessage: t.werkzAlleTextDurchsucht,
            stream: () => library.backfillOcrText(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'beschreibungen',
        rechenintensiv: true,
        icon: Icons.subtitles_outlined,
        titel: t.aufgBeschreibungenTitel,
        stufe: Analysestufe.bildbeschreibung,
        beschreibung: t.aufgBeschreibungenText,
        offeneZahl: () => library.db.countCaptionBackfill(),
        nichtVerfuegbar: _modelHint(
            t, library.captioningAvailable, t.aufgBeschreibungsmodell, t.aufgWoModelle),
        aktionen: [
          // Nach dem Modellwechsel der eigentlich sinnvolle Weg: Die
          // vorhandenen Sätze stammen vom abgelösten Modell.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzErzeugeBeschreibungen,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillCaptions(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzErzeugeBeschreibungen,
            emptyMessage: t.werkzAlleHabenBeschreibung,
            stream: () => library.backfillCaptions(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'beschreibungen_de',
        rechenintensiv: true,
        icon: Icons.translate,
        titel: t.aufgUebersetzenTitel,
        beschreibung: t.aufgUebersetzenText,
        offeneZahl: () => library.db.countCaptionTranslation(),
        nichtVerfuegbar: _modelHint(t, library.uebersetzungEnDeAvailable,
            t.aufgUebersetzungsmodell, t.aufgWoModelle),
        aktionen: [
          // Nach einem Wechsel des Übersetzungsmodells der sinnvolle Weg.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzUebersetzeBeschreibungen,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.uebersetzeBildbeschreibungen(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzUebersetzeBeschreibungen,
            emptyMessage: t.werkzAlleUebersetzt,
            stream: () => library.uebersetzeBildbeschreibungen(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'gesichtsschaerfe',
        // Kein Modell und kein neuer Dekodiervorgang: Gerechnet wird auf
        // den bereits gespeicherten 160x160-Ausschnitten, rund zwei
        // Millisekunden je Gesicht.
        rechenintensiv: false,
        icon: Icons.blur_on,
        titel: t.aufgGesichtsschaerfeTitel,
        beschreibung: t.aufgGesichtsschaerfeText,
        offeneZahl: () => library.db.countGesichterOhneSchaerfe(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzBerechneGesichtsschaerfe,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillGesichtsschaerfe(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'embeddings',
        rechenintensiv: true,
        icon: Icons.scatter_plot_outlined,
        titel: t.aufgEmbeddingsTitel,
        stufe: Analysestufe.bildanalyse,
        beschreibung: t.aufgEmbeddingsText,
        offeneZahl: () => library.db.countEmbeddingBackfill(),
        nichtVerfuegbar:
            _modelHint(t, library.clipAvailable, t.aufgClipModell, t.aufgWoModelle),
        aktionen: [
          // Nach der Umstellung der Bildvorverarbeitung der eigentlich
          // sinnvolle Weg: Die gespeicherten Vektoren stammen noch vom
          // gestauchten Bild.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzBerechneEmbeddings,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillClipEmbeddings(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzBerechneEmbeddings,
            emptyMessage: t.werkzAlleHabenEmbedding,
            stream: () => library.backfillClipEmbeddings(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'kitags',
        rechenintensiv: true,
        icon: Icons.sell_outlined,
        titel: t.aufgKiTagsTitel,
        stufe: Analysestufe.schlagwoerter,
        beschreibung: t.aufgKiTagsText,
        offeneZahl: () => library.db.countAiTagging(onlyUntagged: true),
        nichtVerfuegbar:
            _modelHint(t, library.clipAvailable, t.aufgClipModell, t.aufgWoModelle),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzBerechneKiTags,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillAiTags(onlyUntagged: false),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzBerechneKiTags,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillAiTags(onlyUntagged: true),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'unschaerfe',
        rechenintensiv: true,
        // Teil des gemeinsamen Durchgangs, siehe Gesichter.
        stufe: Analysestufe.bildanalyse,
        icon: Icons.blur_on,
        titel: t.aufgUnschaerfeTitel,
        beschreibung: t.aufgUnschaerfeText,
        offeneZahl: () => library.db.countBlurBackfill(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzBerechneUnschaerfe,
            emptyMessage: t.werkzAlleHabenUnschaerfe,
            stream: () => library.backfillBlurScores(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'videobilder',
        rechenintensiv: true,
        icon: Icons.video_library_outlined,
        titel: t.aufgVideobilderTitel,
        beschreibung: t.aufgVideobilderText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countVideobilder(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzVideobilder,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillVideobilder(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzVideobilder,
            emptyMessage: t.werkzAlleVideobilder,
            stream: () => library.backfillVideobilder(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'datumsherkunft',
        icon: Icons.event_busy_outlined,
        titel: t.aufgDatumsherkunftTitel,
        beschreibung: t.aufgDatumsherkunftText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countDatumsherkunft(),
        aktionen: [
          // „Alle" sieht auch dort noch einmal nach, wo schon geprüft
          // wurde – der Weg für Dateien, die ausserhalb der App
          // nachträglich ein Datum bekommen haben.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzPruefeDatumsherkunft,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillDatumsherkunft(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzPruefeDatumsherkunft,
            emptyMessage: t.werkzAlleDatumGeprueft,
            stream: () => library.backfillDatumsherkunft(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'orte',
        icon: Icons.place_outlined,
        titel: t.aufgOrteTitel,
        beschreibung: t.aufgOrteText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countLocationBackfill(),
        aktionen: [
          // „Alle" liest auch die, in denen schon einmal nachgesehen
          // wurde – der Weg für Dateien, die ausserhalb der App
          // nachträglich Koordinaten bekommen haben.
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzLeseOrte,
            emptyMessage: t.werkzKeinePassenden,
            stream: () => library.backfillLocations(alle: true),
          ),
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzLeseOrte,
            emptyMessage: t.werkzAlleHabenOrt,
            stream: () => library.backfillLocations(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'ortsnamen',
        icon: Icons.map_outlined,
        titel: t.werkzOrteAufloesenTitel,
        beschreibung: t.aufgOrteAufloesenText,
        offeneZahl: () => library.db.countLocationNameBackfill(),
        nichtVerfuegbar: _modelHint(
            t, library.geoDataAvailable, t.aufgGeoDatensatz, t.aufgWoStandortdaten),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzLoeseOrteAuf,
            emptyMessage: t.werkzAlleAufgeloest,
            stream: () => library.backfillLocationNames(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'kameradaten',
        icon: Icons.photo_camera_outlined,
        titel: t.aufgKameraTitel,
        beschreibung: t.aufgKameraText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countCameraMetadataBackfill(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzLeseKameradaten,
            emptyMessage: t.werkzAlleHabenKameradaten,
            stream: () => library.backfillCameraMetadata(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'aufnahmedatum',
        icon: Icons.event_repeat_outlined,
        titel: t.werkzDatumTitel,
        beschreibung: t.aufgDatumText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countDatumskorrektur(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzKorrigiereDatum,
            emptyMessage: t.werkzKeineRawFotos,
            stream: () => library.korrigiereAufnahmedaten(),
            // Eine der beiden Aufgaben mit Rückfrage: Sie schreibt
            // Aufnahmedaten um und verschiebt Dateien auf der Platte.
            bestaetigung: _frageDatumskorrektur,
          ),
        ],
      ),
      // Direkt hinter der Datumskorrektur: Die verschiebt Dateien nach
      // dem neu gelesenen Datum, und was danach noch schief liegt, ist
      // genau der Fall für diese Karte.
      Aufgabe(
        schluessel: 'ablage',
        icon: Icons.folder_copy_outlined,
        titel: t.aufgAblageTitel,
        beschreibung: t.aufgAblageText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.zaehleAblageordnung(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzOrdneAblage,
            emptyMessage: t.werkzAblageStimmt,
            // Am Ende soll die Zahl der wirklich umgelegten Dateien
            // dastehen, nicht die der angesehenen.
            bilanztext: (getan, gesamt) => t.werkzAblageBilanz(getan, gesamt),
            stream: () => library.ordneAblageNeu(),
            // Die zweite Aufgabe mit Rückfrage, aus demselben Grund wie
            // die erste: Sie fasst Dateien auf der Platte an.
            bestaetigung: _frageAblage,
          ),
        ],
      ),
      // Vor den Live-Photo-Paaren: Wer als Video geführt wird, obwohl er
      // ein Standbild ist, wird auch bei der Paarsuche nicht gefunden.
      Aufgabe(
        schluessel: 'dateiarten',
        icon: Icons.rule_folder_outlined,
        titel: t.aufgDateiartTitel,
        beschreibung: t.aufgDateiartText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countAssetsOfType('VIDEO'),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzPruefeDateiarten,
            emptyMessage: t.werkzAlleArtenStimmen,
            stream: () => library.repariereDateiarten(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'livephotos',
        icon: Icons.motion_photos_on_outlined,
        titel: t.aufgLivePhotoTitel,
        beschreibung: t.aufgLivePhotoText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countUnlinkedAssetsOfType('IMAGE'),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.fehlende,
            laufTitel: t.werkzPruefeLivePhotos,
            emptyMessage: t.werkzKeineUnverknuepften,
            stream: () => library.relinkLivePhotos(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'rendern',
        icon: Icons.tune,
        titel: t.werkzNeuRendernTitel,
        beschreibung: t.aufgRendernText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countAssetsWithDevelopSettings(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzRendereNeu,
            emptyMessage: t.werkzKeineEntwickelten,
            stream: () => library.redevelopAll(),
          ),
        ],
      ),
      Aufgabe(
        schluessel: 'xmp',
        icon: Icons.description_outlined,
        titel: t.werkzXmpSchreibenTitel,
        beschreibung: t.aufgXmpText,
        offenLabel: t.aufgBetrifft,
        offeneZahl: () => library.db.countXmpExport(),
        aktionen: [
          Aufgabenaktion(
            modus: Aufgabenmodus.alle,
            laufTitel: t.werkzSchreibeXmp,
            emptyMessage: t.werkzKeineFotosGesperrt,
            stream: () => library.writeXmpSidecars(),
          ),
        ],
      ),
    ];

/// Die Rückfrage vor der Datumskorrektur.
Future<bool> _frageDatumskorrektur(BuildContext context) async {
  final t = AppTexte.of(context);
  final los = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.werkzDatumFrageTitel),
      content: Text(t.werkzDatumFrage),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.allgAbbrechen)),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.werkzDatumStarten),
        ),
      ],
    ),
  );
  return los == true;
}

/// Die Rückfrage vor dem Neuordnen der Ablage.
Future<bool> _frageAblage(BuildContext context) async {
  final t = AppTexte.of(context);
  final los = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.werkzAblageFrageTitel),
      content: Text(t.werkzAblageFrage),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.allgAbbrechen)),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t.werkzAblageStarten),
        ),
      ],
    ),
  );
  return los == true;
}

/// Die Aufgabenverwaltung: **jede** Arbeit, die der Mensch von Hand
/// anstossen kann, an einer Stelle.
///
/// **Das war der eigentliche Fund.** Dieselben fünfzehn Läufe standen
/// vorher zweimal in der App – hier als Karten und in den Werkzeugen als
/// Listeneinträge. Zwei Oberflächen für dieselbe Sache heisst: zwei Wege,
/// eine Aufgabe zu starten, zwei Orte, an denen ein Zusatz vergessen
/// werden kann, und für den Menschen die Frage, ob das dort dasselbe ist
/// wie hier. Die Werkzeuge behalten jetzt, was **keine** Aufgabe ist:
/// Sichten, Duplikate, Stapel, Integritätsprüfung, Vorgaben, Regeln.
///
/// Aufbau nach Immichs „Auftrags-Schlangen": je Aufgabe eine Karte mit
/// Kurzbeschreibung, den Zahlen „Aktiv" und „Wartend", der Zahl der noch
/// offenen Fotos und rechts einer Leiste mit „Alle" und „Fehlende". In der
/// Kopfzeile das, was für alle zusammen gilt: mehrere auf einmal einreihen,
/// und wie viele nebeneinander laufen dürfen.
class BackgroundTasksScreen extends StatelessWidget {
  final LibraryState library;

  /// Schluessel der Aufgabe, um derentwillen dieser Bildschirm geoeffnet
  /// wurde – sie steht dann oben und traegt einen Rahmen.
  ///
  /// **Warum umsortieren und nicht hinscrollen.** Die Liste haelt zwanzig
  /// Karten; `Scrollable.ensureVisible` erreicht nur, was gerade gebaut
  /// ist, und eine faule Liste baut das Ziel erst, wenn es fast sichtbar
  /// ist. Wer von einer Meldung kommt, die eine Zahl nennt, soll die
  /// zugehoerige Karte sofort sehen – nicht sie suchen.
  final String? hervorheben;

  const BackgroundTasksScreen(
      {super.key, required this.library, this.hervorheben});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final aufgaben = aufgabenliste(t, library);
    final ziel = hervorheben;
    if (ziel != null) {
      final stelle = aufgaben.indexWhere((a) => a.schluessel == ziel);
      if (stelle > 0) aufgaben.insert(0, aufgaben.removeAt(stelle));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.aufgTitel),
        // **Ab einer gewissen Enge nur noch Symbole.** „Gleichzeitige
        // Ausführungen verwalten" ist ein langes Wort; bei 640 Punkten
        // Fensterbreite lief die Kopfzeile über, und ein Überlauf fällt im
        // Betrieb nur als roter Balken auf, den niemand meldet. Der
        // Prüfstand hat es gefangen, bevor es jemand zu sehen bekam.
        actions: [
          _Kopfknopf(
            symbol: Icons.add,
            beschriftung: t.aufgErstellen,
            beiKlick: () => unawaited(_zeigeSammeldialog(context, library, aufgaben)),
          ),
          _Kopfknopf(
            symbol: Icons.settings_outlined,
            beschriftung: t.aufgGleichzeitigTitel,
            beiKlick: () => unawaited(_zeigeGleichzeitig(context, library)),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _CombinedAnalysisCard(library: library),
          const SizedBox(height: AppSpacing.md),
          for (final aufgabe in aufgaben)
            _TaskCard(
              library: library,
              aufgabe: aufgabe,
              hervorgehoben: aufgabe.schluessel == ziel,
            ),
        ],
      ),
    );
  }
}

/// Ein Knopf der Kopfzeile: mit Beschriftung, solange sie hinpasst.
///
/// Die Schwelle liegt bei 1000 Punkten und ist gemessen, nicht geraten:
/// Beide Beschriftungen zusammen brauchen samt Symbolen und Titel gut
/// 800 Punkte. Darunter bleibt das Symbol, und der Text steht im
/// Kurzhinweis – verloren geht er also nicht, auch nicht für die
/// Sprachausgabe.
///
/// **Die Schwelle wächst mit der Systemschrift.** Sie war an einer
/// Fensterbreite festgemacht, der Platzbedarf hängt aber an der
/// Schriftgrösse: Bei 1,6-facher Systemschrift und 1100 Punkten Fenster
/// zeigte die Kopfzeile beide Beschriftungen — und lief um 180 Punkte
/// über, weil sie rund 1280 gebraucht hätten. Genau der Überlauf, den
/// der Kommentar oben für erledigt erklärte, nur eine Ebene tiefer.
class _Kopfknopf extends StatelessWidget {
  const _Kopfknopf({
    required this.symbol,
    required this.beschriftung,
    required this.beiKlick,
  });

  final IconData symbol;
  final String beschriftung;
  final VoidCallback beiKlick;

  static const schwelle = 1000.0;

  @override
  Widget build(BuildContext context) {
    // Nicht die rohe Schwelle, sondern die mit der Systemschrift
    // skalierte: Doppelt so grosse Schrift braucht doppelt so viel Platz.
    final noetig = MediaQuery.textScalerOf(context).scale(schwelle);
    if (MediaQuery.sizeOf(context).width < noetig) {
      return IconButton(
        icon: Icon(symbol),
        tooltip: beschriftung,
        onPressed: beiKlick,
      );
    }
    return TextButton.icon(
      onPressed: beiKlick,
      icon: Icon(symbol),
      label: Text(beschriftung),
    );
  }
}

/// Reiht mehrere Aufgaben auf einmal ein.
///
/// **Erst mit der Warteschlange ist das mehr als eine Spielerei.** Vorher
/// wäre die zweite Aufgabe abgewiesen worden, und ein Dialog, der fünf
/// ankreuzen lässt und vier davon verwirft, wäre eine Zumutung. Jetzt
/// laufen sie der Reihe nach durch.
Future<void> _zeigeSammeldialog(
    BuildContext context, LibraryState library, List<Aufgabe> aufgaben) async {
  final t = AppTexte.of(context);
  final waehlbar = aufgaben.where((a) => a.bedienbar).toList();
  final gewaehlt = <String>{};
  var modus = Aufgabenmodus.fehlende;

  final los = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setzeZustand) => AlertDialog(
        title: Text(t.aufgErstellen),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.aufgErstellenText,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<Aufgabenmodus>(
                segments: [
                  for (final m in Aufgabenmodus.values)
                    ButtonSegment(
                        value: m, label: Text(modusName(t, m)), icon: Icon(modusSymbol(m))),
                ],
                selected: {modus},
                onSelectionChanged: (auswahl) =>
                    setzeZustand(() => modus = auswahl.first),
              ),
              const Divider(height: AppSpacing.xl),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in waehlbar)
                      CheckboxListTile(
                        dense: true,
                        value: gewaehlt.contains(a.schluessel),
                        title: Text(a.titel),
                        secondary: Icon(a.icon),
                        onChanged: (an) => setzeZustand(() =>
                            an == true ? gewaehlt.add(a.schluessel) : gewaehlt.remove(a.schluessel)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.allgAbbrechen)),
          FilledButton(
            // Abgeschaltet statt mit einer Meldung quittiert: Ein Knopf,
            // der nichts tun kann, soll das vorher zeigen.
            onPressed: gewaehlt.isEmpty ? null : () => Navigator.pop(context, true),
            child: Text(t.aufgEinreihen),
          ),
        ],
      ),
    ),
  );
  if (los != true) return;

  var eingereiht = 0;
  for (final a in waehlbar.where((a) => gewaehlt.contains(a.schluessel))) {
    // Rückfragen übergeht der Sammelweg nicht – er lässt die betroffene
    // Aufgabe aus. Fünf Dialoge hintereinander wären das Gegenteil dessen,
    // wofür der Sammelweg da ist, und stillschweigend Dateien zu
    // verschieben kommt nicht in Frage.
    final aktion = a.aktionFuer(modus);
    if (aktion.bestaetigung != null) continue;
    if (reiheEin(library, a, aktion) == null) eingereiht++;
  }
  melde.hinweis(t.aufgEingereiht(eingereiht));
}

/// Wie viele schwere Aufgaben nebeneinander laufen dürfen.
Future<void> _zeigeGleichzeitig(BuildContext context, LibraryState library) async {
  final t = AppTexte.of(context);
  var wert = library.maxGleichzeitig;
  final neu = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setzeZustand) => AlertDialog(
        title: Text(t.aufgGleichzeitigTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.aufgGleichzeitigText,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  // Ohne Kurzhinweis liest die Sprachausgabe hier zwei
                  // namenlose Knoepfe um eine nackte Zahl vor.
                  tooltip: t.aufgWenigerGleichzeitig,
                  onPressed: wert <= 1 ? null : () => setzeZustand(() => wert--),
                ),
                SizedBox(
                  width: 56,
                  child: Text('$wert',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: t.aufgMehrGleichzeitig,
                  // Vier ist keine technische Grenze, sondern eine
                  // Zumutungsgrenze: Jede schwere Aufgabe hält ein Modell
                  // im Speicher (CLIP-Bild 335 MB, Bildbeschreibung
                  // 235 MB, gemessen) und dekodiert dieselben Fotos noch
                  // einmal.
                  onPressed: wert >= 4 ? null : () => setzeZustand(() => wert++),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, wert),
              child: Text(t.allgSpeichern)),
        ],
      ),
    ),
  );
  if (neu != null) await library.setzeMaxGleichzeitig(neu);
}

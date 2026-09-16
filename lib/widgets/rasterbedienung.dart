import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database.dart';
import '../services/rasterauswahl.dart';
import '../theme/app_spacing.dart';

/// Maus mit Zusatztasten und Tastatur für die Fotoraster – an einer Stelle
/// für alle vier Bildschirme, die eine Mehrfachauswahl kennen (Zeitleiste,
/// Kalenderjahr, Album, Suche).
///
/// **Warum ein Mixin und keine vier Umsetzungen.** Genau diese Frage hat
/// schon einmal Geld gekostet: Die Liste der zu einem Foto gehörenden Dateien
/// stand dreimal von Hand da und lief zweimal auseinander (siehe
/// `LibraryState.dateienVon`). Eine Bedienung, die auf einem Raster anders
/// reagiert als auf dem daneben, ist derselbe Fehler in Grün.
///
/// Der Mixin verwaltet die Auswahlmenge **nicht** selbst – die Bildschirme
/// haben sie längst und reichen sie über [auswahl] herein. So kommt kein
/// zweiter Ort dazu, an dem steht, was ausgewählt ist.
/// [Z] ist der Zeilentyp des jeweiligen Bildschirms.
///
/// **Warum nicht fest auf einen Typ.** Die Tastensteuerung fasst von einer
/// Zeile nur die Kennung an und reicht sie sonst unbesehen an
/// [rasterOeffne] weiter. Die Zeitleiste arbeitet inzwischen mit der
/// schmalen [Rasterzeile], Alben und Suche mit der vollen `AssetData` –
/// beide auf einen Typ zu zwingen hiesse, an einer der beiden Stellen bei
/// jedem Tastendruck eine Liste umzuwandeln.
mixin Rasterbedienung<T extends StatefulWidget, Z extends Object>
    on State<T> {
  // ---- vom Bildschirm zu liefern ----

  /// Die Auswahlmenge des Bildschirms. Wird von hier aus verändert.
  Set<String> get auswahl;

  AppDatabase get rasterDb;

  /// Die Fotos in Anzeigereihenfolge. Leer, solange nichts geladen ist.
  List<Z> get rasterAssets;

  /// Wie viele Spalten das Raster gerade zeigt – aus dem `LayoutBuilder` des
  /// Bildschirms. Bestimmt, wie weit „Pfeil nach unten" springt.
  int get rasterSpalten;

  /// Je Gruppe die Länge jeder Reihe – nur für Raster **ohne** feste
  /// Spaltenzahl.
  ///
  /// `null` heisst: Es gibt eine, [rasterSpalten] genügt. Die Zeitleiste
  /// liefert hier ihre bündigen Reihen; ohne das spränge „nach unten"
  /// irgendwohin, weil dort mal drei und mal dreizehn Fotos nebeneinander
  /// stehen.
  List<List<int>>? get rasterReihenlaengen => null;

  /// Öffnet die Vollbildansicht bei diesem Foto (einfacher Klick ohne
  /// bestehende Auswahl, oder Eingabetaste).
  void rasterOeffne(Z asset);

  /// Die Kennung einer Zeile. Getrennt von [rasterMerkmale], weil sie in
  /// Schleifen über die ganze Liste gebraucht wird und dort nichts
  /// entstehen soll.
  String rasterKennung(Z zeile);

  /// Was die Tasten `F` und `1`–`6` von einer Zeile wissen müssen.
  /// Einmal je Tastendruck, nicht je Zeile.
  ({bool favorit, String? farbe}) rasterMerkmale(Z zeile);

  /// Die Gruppen, in denen das Raster die Fotos zeigt. Vorgabe ist eine
  /// einzige Gruppe – richtig für jedes flache `GridView`. Die Zeitleiste und
  /// das Kalenderjahr überschreiben das mit ihren Monatsgruppen, sonst spränge
  /// der Zeiger über eine Monatsüberschrift hinweg an die falsche Stelle.
  List<List<String>> get rasterGruppen => [
        [for (final a in rasterAssets) rasterKennung(a)],
      ];

  // ---- Zustand ----

  /// Wo ein mit der Umschalttaste aufgezogener Bereich beginnt.
  String? anker;

  /// Die Kachel, auf der die Tastatur steht (bekommt den Rahmen).
  String? aktiveKachel;

  /// Wird nach jeder Änderung an Bewertung/Farbmarke/Favorit aufgerufen –
  /// Bildschirme mit einem Datenstrom brauchen nichts zu tun, Bildschirme mit
  /// einer einmal geladenen Liste laden hier nach.
  Future<void> rasterAktualisieren() async {}

  // ---- Maus ----

  /// Wählt eine Kachel an oder ab – und merkt sie sich als [anker].
  ///
  /// **Warum der Anker hier stehen muss.** [rasterKlick] setzt ihn bei
  /// jedem Klick; das Auswählen per langem Druck (und über eine
  /// Monatsüberschrift) tat es nicht. Wer so begann und dann mit
  /// Umschalt weiterklickte, bekam entweder genau diese eine Kachel dazu
  /// – es gab ja keinen Anker – oder einen Bereich, der bei einem längst
  /// vergessenen Foto begann. Aus dem Erstlauf-Bericht: „Einzelauswahl
  /// funktioniert, Umschalt-Klick nur bis zu dem gewählten Foto,
  /// teilweise auch einige zusammenhängende Fotos, aber nicht der ganze
  /// Bereich."
  ///
  /// Auch beim Abwählen wandert der Anker mit: Bezugspunkt ist die
  /// zuletzt angefasste Kachel, nicht die zuletzt hinzugefügte.
  void rasterUmschalten(String kennung) {
    setState(() {
      if (!auswahl.remove(kennung)) auswahl.add(kennung);
      anker = kennung;
      aktiveKachel = kennung;
    });
  }

  /// Wählt eine ganze Gruppe an oder ab – etwa über eine Monatsüberschrift.
  ///
  /// Der Anker landet auf der letzten Kachel der Gruppe: Von dort aus
  /// geht es beim nächsten Umschalt-Klick lückenlos weiter.
  void rasterGruppeUmschalten(List<String> kennungen) {
    if (kennungen.isEmpty) return;
    setState(() {
      final alleDrin = kennungen.every(auswahl.contains);
      for (final id in kennungen) {
        if (alleDrin) {
          auswahl.remove(id);
        } else {
          auswahl.add(id);
        }
      }
      if (!alleDrin) {
        anker = kennungen.last;
        aktiveKachel = kennungen.last;
      }
    });
  }

  /// Ein Klick auf eine Kachel, mit oder ohne Zusatztaste.
  ///
  /// Ohne Zusatztaste bleibt alles beim Alten: Gibt es schon eine Auswahl,
  /// schaltet der Klick diese Kachel um; gibt es keine, öffnet er das Foto.
  /// Das ist die Bedienung, die es immer gab, und sie funktioniert weiterhin
  /// mit dem Finger.
  void rasterKlick(Z asset) {
    final art = klickartAus(HardwareKeyboard.instance.logicalKeysPressed);
    final ankerVorher = anker;

    switch (art) {
      case Klickart.bereich:
        setState(() {
          aktiveKachel = rasterKennung(asset);
          if (ankerVorher == null) {
            auswahl.add(rasterKennung(asset));
            anker = rasterKennung(asset);
          } else {
            final erweitert = auswahlMitBereich(
              [for (final a in rasterAssets) rasterKennung(a)],
              auswahl,
              ankerVorher,
              rasterKennung(asset),
            );
            auswahl
              ..clear()
              ..addAll(erweitert);
          }
        });

      case Klickart.einzeln:
        setState(() {
          if (!auswahl.remove(rasterKennung(asset))) auswahl.add(rasterKennung(asset));
          anker = rasterKennung(asset);
          aktiveKachel = rasterKennung(asset);
        });

      case Klickart.einfach:
        if (auswahl.isNotEmpty) {
          setState(() {
            if (!auswahl.remove(rasterKennung(asset))) auswahl.add(rasterKennung(asset));
            anker = rasterKennung(asset);
            aktiveKachel = rasterKennung(asset);
          });
        } else {
          setState(() {
            anker = rasterKennung(asset);
            aktiveKachel = rasterKennung(asset);
          });
          rasterOeffne(asset);
        }
    }
  }

  // ---- Tastatur ----

  /// Der eigene Fokusknoten des Rasters.
  ///
  /// **Warum nicht mehr `autofocus`.** Die Hülle legt ihrerseits einen
  /// `Focus` über den ganzen Bildschirm (für ⌘1…⌘0 und „?", siehe
  /// `HomeShell`), ebenfalls mit `autofocus`. Zwei Knoten desselben
  /// Bereichs bitten damit im selben Atemzug um den Fokus – und Flutter
  /// gibt ihn dem, der zuerst dran ist: der Hülle. Das Raster ging leer
  /// aus, und weil Tasten von der fokussierten Stelle nur nach **oben**
  /// weiterwandern, kam bei ihm nie eine an. Bewertung, Farbmarke, Pfeile,
  /// F und Esc taten nichts; das Nummernfeld quittierte mit einem Piep.
  /// Belegt in `test/fokus_verschachtelt_test.dart`.
  ///
  /// Eine ausdrückliche Anforderung schlägt die frühere Autofokus-Bitte.
  /// Die Hülle verliert dabei nichts: Tasten laufen vom Raster aus weiter
  /// zu ihr hinauf, ⌘1…⌘0 kommt also weiterhin an.
  final FocusNode rasterFokus = FocusNode();
  bool _fokusErbeten = false;

  /// Holt den Fokus zum Raster – beim ersten Aufbau und nach jedem Klick
  /// hinein.
  ///
  /// Das Nachfassen beim Klick ist kein Beiwerk: Wer ein Foto anklickt und
  /// danach „3" drückt, erwartet drei Sterne. Ohne das läge der Fokus nach
  /// dem Klick womöglich auf der angeklickten Kachel selbst oder – wenn
  /// vorher gesucht wurde – noch im Suchfeld.
  void rasterFokusHolen() {
    if (!mounted) return;
    if (!rasterFokus.hasFocus) rasterFokus.requestFocus();
  }

  /// Umschliesst [kind] mit der Tastaturbedienung.
  Widget mitTastatur({required Widget kind}) {
    if (!_fokusErbeten) {
      _fokusErbeten = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => rasterFokusHolen());
    }
    return Listener(
      // `down` statt `up`: Bis der Finger wieder hochgeht, hat die Kachel
      // ihre eigene Reaktion schon begonnen.
      onPointerDown: (_) => rasterFokusHolen(),
      child: Focus(focusNode: rasterFokus, onKeyEvent: rasterTaste, child: kind),
    );
  }

  @override
  void dispose() {
    rasterFokus.dispose();
    super.dispose();
  }

  /// Ob gerade in ein Textfeld geschrieben wird.
  ///
  /// Ohne diese Prüfung wäre die Suche unbenutzbar: Der Mixin sitzt als
  /// `Focus` über dem ganzen Bildschirm, und Zifferntasten laufen an einem
  /// Textfeld vorbei nach oben durch. „2026" ins Suchfeld getippt hiesse
  /// sonst: vier Bewertungen vergeben.
  bool _schreibtGerade() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  KeyEventResult rasterTaste(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_schreibtGerade()) return KeyEventResult.ignored;
    if (rasterAssets.isEmpty) return KeyEventResult.ignored;

    final taste = event.logicalKey;
    final gedrueckt = HardwareKeyboard.instance.logicalKeysPressed;
    final art = klickartAus(gedrueckt);
    final mitUmschalt = art == Klickart.bereich;

    // Strg bzw. Command gehören den Fensterkürzeln, nicht dem Raster: Die
    // Hülle schaltet mit ⌘1…⌘9 den Bereich um (siehe HomeShell). Ohne diese
    // Zeile fingen wir ⌘3 ab, setzten eine Bewertung und meldeten die Taste
    // als erledigt – der Bereichswechsel käme nie an.
    if (art == Klickart.einzeln) return KeyEventResult.ignored;

    final richtungen = <LogicalKeyboardKey, Rasterrichtung>{
      LogicalKeyboardKey.arrowLeft: Rasterrichtung.links,
      LogicalKeyboardKey.arrowRight: Rasterrichtung.rechts,
      LogicalKeyboardKey.arrowUp: Rasterrichtung.hoch,
      LogicalKeyboardKey.arrowDown: Rasterrichtung.runter,
    };
    final richtung = richtungen[taste];
    if (richtung != null) {
      _bewegeZeiger(richtung, mitUmschalt: mitUmschalt);
      return KeyEventResult.handled;
    }

    if (taste == LogicalKeyboardKey.escape) {
      if (auswahl.isEmpty) return KeyEventResult.ignored;
      setState(() {
        auswahl.clear();
        anker = null;
      });
      return KeyEventResult.handled;
    }

    if (taste == LogicalKeyboardKey.enter ||
        taste == LogicalKeyboardKey.numpadEnter) {
      final id = aktiveKachel;
      if (id == null) return KeyEventResult.ignored;
      final treffer = rasterAssets.where((a) => rasterKennung(a) == id);
      if (treffer.isEmpty) return KeyEventResult.ignored;
      rasterOeffne(treffer.first);
      return KeyEventResult.handled;
    }

    final ziele = tastenziel(auswahl, aktiveKachel);
    if (ziele.isEmpty) return KeyEventResult.ignored;

    final bewertung = bewertungFuerZiffer(taste);
    if (bewertung != null) {
      _fuehreAus(rasterDb.setRatingBulk(ziele, bewertung));
      return KeyEventResult.handled;
    }

    final farbe = farbmarkeFuerZiffer(taste);
    if (farbe != null) {
      // Dieselbe Farbe erneut nimmt die Marke wieder weg – genau wie ein
      // zweiter Klick auf denselben Kreis in der Palette. Massgeblich ist
      // dabei die aktive Kachel bzw. das erste Foto der Auswahl; bei
      // gemischten Marken setzt die Taste also erst einmal alle gleich.
      final erstes =
          rasterAssets.where((a) => rasterKennung(a) == ziele.first);
      final schonSo =
          erstes.isNotEmpty && rasterMerkmale(erstes.first).farbe == farbe;
      _fuehreAus(rasterDb.setColorLabelBulk(ziele, schonSo ? null : farbe));
      return KeyEventResult.handled;
    }

    if (taste == LogicalKeyboardKey.keyF) {
      final erstes =
          rasterAssets.where((a) => rasterKennung(a) == ziele.first);
      final schonSo =
          erstes.isNotEmpty && rasterMerkmale(erstes.first).favorit;
      _fuehreAus(rasterDb.setFavoriteBulk(ziele, !schonSo));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Führt eine Datenbankänderung aus und lädt danach nach.
  ///
  /// Kein `await` im Tastenpfad: Ein `KeyEventResult` muss sofort zurück,
  /// sonst gilt die Taste als unbehandelt und wandert weiter nach oben.
  void _fuehreAus(Future<void> aenderung) {
    aenderung.then((_) {
      if (mounted) rasterAktualisieren();
    });
  }

  void _bewegeZeiger(Rasterrichtung richtung, {required bool mitUmschalt}) {
    final start = aktiveKachel;
    if (start == null) {
      // Erster Tastendruck ohne Zeiger: beim ersten Foto anfangen, statt
      // wortlos nichts zu tun.
      setState(() {
        aktiveKachel = rasterKennung(rasterAssets.first);
        anker ??= aktiveKachel;
      });
      return;
    }
    final ziel = nachbarkachel(
      gruppen: rasterGruppen,
      von: start,
      richtung: richtung,
      spalten: rasterSpalten,
      reihenlaengen: rasterReihenlaengen,
    );
    if (ziel == null) return;
    setState(() {
      aktiveKachel = ziel;
      if (mitUmschalt) {
        final ab = anker ?? start;
        anker = ab;
        final erweitert = auswahlMitBereich(
          [for (final a in rasterAssets) rasterKennung(a)],
          auswahl,
          ab,
          ziel,
        );
        auswahl
          ..clear()
          ..addAll(erweitert);
      } else {
        anker = ziel;
      }
    });
  }
}

/// Spaltenzahl eines flachen Fotorasters (Album, Suche) bei dieser Breite.
///
/// Dieselbe Formel wie in `SliverGridDelegateWithMaxCrossAxisExtent`; die
/// Zeitleiste hat ihre eigene, weil dort noch der Zeitstrahl abgeht (siehe
/// `rasterSpaltenzahl`). [seitenpolster] ist die Summe aus linkem und rechtem
/// Rand.
int flachesRasterSpalten(
  double breite, {
  double seitenpolster = 0,
  double maxKachel = 160,
  double abstand = 4,
}) {
  final nutzbar = breite - seitenpolster;
  if (nutzbar <= 0) return 1;
  final zahl = (nutzbar / (maxKachel + abstand)).ceil();
  return zahl < 1 ? 1 : zahl;
}

/// Bleibender Rahmen um die Kachel, auf der die Tastatur steht.
///
/// Bewusst anders als das Auswahl-Overlay: Die aktive Kachel ist nicht
/// dasselbe wie eine ausgewählte, und beides kann gleichzeitig zutreffen. Der
/// Rahmen liegt deshalb aussen um die Kachel herum statt darauf.
class AktiveKachelRahmen extends StatelessWidget {
  final Widget child;
  const AktiveKachelRahmen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border:
            Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: child,
    );
  }
}

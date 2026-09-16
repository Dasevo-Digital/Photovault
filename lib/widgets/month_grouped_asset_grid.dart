import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../db/rasterzeile.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import 'asset_thumbnail_tile.dart';
import 'rasterbedienung.dart';
import 'timeline_grid_layout.dart';
import 'timeline_scrubber.dart';
import '../services/meldungsdienst.dart';

const double _scrubberWidth = 64.0;

/// Die Monatsgruppen einer bereits absteigend sortierten Asset-Liste, in
/// Anzeigereihenfolge.
///
/// Frei zugänglich, weil die Tastaturbedienung (siehe
/// `widgets/rasterbedienung.dart`) dieselbe Gruppierung braucht wie das Raster
/// selbst: Pfeil nach unten springt eine Zeile INNERHALB eines Monats, und
/// wenn Bildschirm und Raster hier verschieden gruppierten, spränge der Zeiger
/// woanders hin als der Rahmen.
///
/// Günstiger Integer-Schlüssel (Jahr*100+Monat) statt eines pro Foto neu
/// formatierten Datums-Strings – bei jeder DB-Änderung liefert
/// `watchTimeline()` die komplette Liste neu, wodurch diese Gruppierung bei
/// großen Bibliotheken sonst unnötig oft (kostspielig) neu läuft.
({List<int> schluessel, Map<int, List<Rasterzeile>> gruppen}) monatsgruppen(
    List<Rasterzeile> assets, {bool absteigend = true}) {
  final gruppen = <int, List<Rasterzeile>>{};
  for (final a in assets) {
    final key = a.fileCreatedAt.year * 100 + a.fileCreatedAt.month;
    gruppen.putIfAbsent(key, () => []).add(a);
  }
  // Die Monate laufen in dieselbe Richtung wie die Fotos darin. Stünde
  // hier fest „neueste zuerst", zeigte die Zeitleiste bei aufsteigender
  // Sortierung die Monate rückwärts und die Fotos darin vorwärts.
  final schluessel = gruppen.keys.toList()
    ..sort((a, b) => absteigend ? b.compareTo(a) : a.compareTo(b));
  return (schluessel: schluessel, gruppen: gruppen);
}

/// Aufnahmen nach **Tagen** gruppiert – für die Monatsansicht.
///
/// Innerhalb eines Monats gibt es nur eine Monatsgruppe; nach Monaten zu
/// gliedern hiesse dort, gar nicht zu gliedern, und der Zeitstrahl fiele
/// mangels zweiter Gruppe weg. Der Schlüssel ist wieder ein günstiger
/// Integer (Jahr*10000 + Monat*100 + Tag), aus demselben Grund wie oben.
({List<int> schluessel, Map<int, List<Rasterzeile>> gruppen}) tagesgruppen(
    List<Rasterzeile> assets, {bool absteigend = true}) {
  final gruppen = <int, List<Rasterzeile>>{};
  for (final a in assets) {
    final d = a.fileCreatedAt;
    gruppen.putIfAbsent(d.year * 10000 + d.month * 100 + d.day, () => [])
        .add(a);
  }
  final schluessel = gruppen.keys.toList()
    ..sort((a, b) => absteigend ? b.compareTo(a) : a.compareTo(b));
  return (schluessel: schluessel, gruppen: gruppen);
}

/// Ob neben dem Raster der Zeitstrahl steht – erst ab zwei Gruppen.
bool rasterMitZeitstrahl(int gruppenAnzahl) => gruppenAnzahl > 1;

/// Wie viele Spalten das Raster bei dieser Gesamtbreite verwendet.
///
/// Nimmt die GESAMTE verfügbare Breite entgegen und zieht den Zeitstrahl
/// selbst ab. Wer die Spaltenzahl von aussen braucht (Tastaturbedienung),
/// kennt sonst die Breite des Zeitstrahls nicht und käme bei schmalen Fenstern
/// auf eine Spalte zu viel.
int rasterSpaltenzahl(double gesamtbreite,
        {required bool mitZeitstrahl,
        double kachelbreite = timelineGridMaxCrossAxisExtent}) =>
    timelineColumnsForWidth(
        mitZeitstrahl ? gesamtbreite - _scrubberWidth : gesamtbreite,
        kachelbreite: kachelbreite);

/// Die Breite, die dem Foto-Raster wirklich bleibt.
///
/// Dieselbe Rechnung wie im Raster selbst – für alle, die sie von aussen
/// brauchen. Ohne sie rechnete die Tastaturbedienung mit der vollen
/// Fensterbreite und käme auf andere Reihen als die, die zu sehen sind.
double rasterGridbreite(double gesamtbreite, {required bool mitZeitstrahl}) =>
    mitZeitstrahl ? gesamtbreite - _scrubberWidth : gesamtbreite;

/// Rendert eine Liste von Assets gruppiert nach Monat (Überschrift + darunter
/// ein Foto-Grid) – gemeinsame Darstellung für die Timeline und die
/// Jahres-Detailansicht (Kalender). Gruppierung passiert client-seitig auf
/// der übergebenen (bereits absteigend nach Datum sortierten) Liste.
///
/// Rechts eingeblendet: ein [TimelineScrubber] zum schnellen Springen zu
/// einem Jahr/Monat (nur wenn es mindestens 2 Monatsgruppen gibt).
class MonthGroupedAssetGrid extends StatefulWidget {
  final List<Rasterzeile> assets;
  final StoragePaths paths;
  final void Function(Rasterzeile asset) onTap;

  /// Startet/erweitert die Mehrfachauswahl per langem Druck (siehe
  /// SelectionActionBar). Ohne diesen Callback verhält sich das Grid wie
  /// zuvor (keine Auswahl möglich).
  final void Function(Rasterzeile asset)? onLongPress;

  /// Wird aufgerufen, wenn auf die Monatsüberschrift getippt wird – der
  /// Aufrufer entscheidet (siehe [_MonthGroupedAssetGridState]'s Nutzer),
  /// ob das die komplette Monatsgruppe zur Auswahl hinzufügt oder wieder
  /// entfernt. Ohne diesen Callback ist die Überschrift nicht antippbar.
  final void Function(List<Rasterzeile> groupAssets)? onHeaderTap;

  /// IDs der aktuell ausgewählten Fotos – rendert das Auswahl-Overlay auf
  /// den entsprechenden Kacheln (siehe [AssetThumbnailTile.selected]) sowie
  /// das Auswahl-Symbol vor der Monatsüberschrift.
  final Set<String>? selectedIds;

  /// Springt einmalig zu diesem Foto und hebt es kurz hervor (siehe
  /// "Foto in der Timeline anzeigen" im Kontextmenü der Vollbildansicht).
  /// Wird pro neuem Wert nur einmal verarbeitet, auch wenn der übergeordnete
  /// Widget-Baum zwischenzeitlich mehrfach neu baut.
  final String? highlightAssetId;

  /// Die Kachel, auf der die Tastatur gerade steht – bekommt einen bleibenden
  /// Rahmen und wird bei jedem Wechsel in den sichtbaren Bereich gescrollt.
  ///
  /// Unterschied zu [highlightAssetId]: Das dort ist ein einmaliger Sprung mit
  /// ausklingendem Blinken ("hier ist das gesuchte Foto"), das hier ein
  /// dauerhafter Zeiger, der sich mit den Pfeiltasten bewegt.
  final String? aktiveKachelId;

  /// Wird aufgerufen, sobald nahe genug ans Ende des aktuell geladenen
  /// Ausschnitts gescrollt wurde – der Aufrufer entscheidet, ob und wie viel
  /// mehr nachgeladen wird (siehe TimelineScreens wachsendes Ladefenster).
  /// Ohne diesen Callback (z.B. wenn [assets] ohnehin schon die komplette
  /// Bibliothek enthält) passiert nichts Zusätzliches.
  final VoidCallback? onScrollNearEnd;

  /// Jede Änderung dieses Werts springt an den Anfang der Liste – also zu
  /// den neuesten Fotos, denn sortiert wird absteigend.
  ///
  /// Ein Zähler und kein `bool`: Zweimal hintereinander „nach oben" muss
  /// zweimal wirken. Ein Schalter, der schon auf `true` steht, löst beim
  /// zweiten Mal nichts aus.
  final ValueListenable<int>? nachObenSignal;

  /// Nach Tagen gliedern statt nach Monaten (siehe [tagesgruppen]).
  final bool nachTag;

  /// Wie breit eine Kachel höchstens wird – siehe
  /// [zeitleisteKachelstufen]. Kleiner heisst mehr Fotos und damit mehr
  /// Monate auf einmal im Bild.
  ///
  /// Bei [Zeitleistenform.reihen] ist dieselbe Zahl die **Zielhöhe** der
  /// Reihen: Der vorhandene Zoom soll in beiden Formen wirken, statt dass
  /// die zweite einen eigenen Regler bekommt.
  final double kachelbreite;

  /// Quadrate oder bündige Reihen.
  final Zeitleistenform form;

  /// Ob überhaupt nach Zeit gegliedert wird.
  ///
  /// **Warum das abschaltbar sein muss.** Die Überschrift einer Gruppe
  /// nennt den Monat der ersten Aufnahme darin. Sortiert die Zeitleiste
  /// nach Dateigrösse oder Bewertung, stünde über einer Gruppe „März
  /// 2019", obwohl die Aufnahme darunter von 2024 sein kann – und der
  /// Zeitstrahl daneben führte an Monate, die es so nicht gibt. Ohne
  /// Gliederung fällt beides weg, und die Fotos stehen in genau der
  /// Reihenfolge, die eingestellt ist.
  final bool gliedern;

  /// In welche Richtung die Gruppen laufen – siehe [monatsgruppen].
  final bool absteigend;

  const MonthGroupedAssetGrid({
    super.key,
    required this.assets,
    required this.paths,
    required this.onTap,
    this.onLongPress,
    this.onHeaderTap,
    this.selectedIds,
    this.highlightAssetId,
    this.aktiveKachelId,
    this.onScrollNearEnd,
    this.nachObenSignal,
    this.nachTag = false,
    this.kachelbreite = timelineGridMaxCrossAxisExtent,
    this.form = zeitleisteFormVorgabe,
    this.gliedern = true,
    this.absteigend = true,
  });

  @override
  State<MonthGroupedAssetGrid> createState() => _MonthGroupedAssetGridState();
}

class _MonthGroupedAssetGridState extends State<MonthGroupedAssetGrid> {
  final _scrollController = ScrollController();
  String? _handledHighlightId;
  String? _flashingAssetId;

  // Von build() bei jedem Durchlauf aktuell gehalten (siehe LayoutBuilder
  // unten) – [_scrollToAndFlash] läuft außerhalb von build() (per
  // Post-Frame-Callback) und braucht dieselben Werte, die das Grid für sein
  // eigenes Layout verwendet, statt sie separat (und für große Bibliotheken
  // spürbar teuer) ein zweites Mal aus der kompletten Asset-Liste
  // herzuleiten.
  double? _lastGridWidth;
  Map<int, List<Rasterzeile>>? _lastGroups;
  List<int>? _lastOrderedKeys;

  @override
  void initState() {
    super.initState();
    _maybeHandleHighlight();
    _scrollController.addListener(_handleScroll);
    widget.nachObenSignal?.addListener(_nachOben);
  }

  @override
  void didUpdateWidget(covariant MonthGroupedAssetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeHandleHighlight();
    if (widget.aktiveKachelId != null && widget.aktiveKachelId != oldWidget.aktiveKachelId) {
      final ziel = widget.aktiveKachelId!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _zeigeAktiveKachel(ziel));
    }
    if (oldWidget.nachObenSignal != widget.nachObenSignal) {
      oldWidget.nachObenSignal?.removeListener(_nachOben);
      widget.nachObenSignal?.addListener(_nachOben);
    }
  }

  /// An den Anfang – dorthin, wo die neuesten Fotos stehen.
  void _nachOben() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_scrollController.offset <= 0) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    widget.nachObenSignal?.removeListener(_nachOben);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Löst [MonthGroupedAssetGrid.onScrollNearEnd] aus, sobald weniger als
  /// eine Bildschirmhöhe (grob geschätzt über einen festen Pixel-Puffer) bis
  /// zum Ende des aktuell geladenen Ausschnitts übrig ist. Der Aufrufer
  /// (TimelineScreen) muss selbst dafür sorgen, dass ein mehrfaches Auslösen
  /// (z.B. bei mehreren Scroll-Events kurz hintereinander) harmlos ist –
  /// hier keine eigene Drosselung, um die Logik nicht doppelt zu halten.
  void _handleScroll() {
    final onNearEnd = widget.onScrollNearEnd;
    if (onNearEnd == null || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 2000) {
      onNearEnd();
    }
  }

  void _maybeHandleHighlight() {
    final targetId = widget.highlightAssetId;
    if (targetId == null || targetId == _handledHighlightId) return;
    _handledHighlightId = targetId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToAndFlash(targetId));
  }

  void _scrollToAndFlash(String assetId) {
    final gridWidth = _lastGridWidth;
    final groups = _lastGroups;
    final orderedKeys = _lastOrderedKeys;
    if (!mounted || !_scrollController.hasClients || gridWidth == null || groups == null || orderedKeys == null) {
      return;
    }
    final offset = timelineOffsetForAsset(orderedKeys, groups, gridWidth, assetId,
        kachelbreite: widget.kachelbreite, form: widget.form);
    if (offset == null) {
      melde.warnung(AppTexte.of(context).rasterFotoNichtGefunden);
      return;
    }
    final clamped = offset.clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(clamped, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    setState(() => _flashingAssetId = assetId);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _flashingAssetId == assetId) setState(() => _flashingAssetId = null);
    });
  }

  /// Scrollt die aktive Kachel in den sichtbaren Bereich – aber nur, wenn sie
  /// wirklich ausserhalb liegt.
  ///
  /// Die Bedingung ist der Kern: Wer mit dem Pfeil eine Zeile weiter geht,
  /// erwartet, dass die Liste stehen bleibt. Bedingungslos zu scrollen hiesse,
  /// bei jedem Tastendruck den ganzen Ausschnitt zu verschieben.
  void _zeigeAktiveKachel(String assetId) {
    final gridWidth = _lastGridWidth;
    final groups = _lastGroups;
    final orderedKeys = _lastOrderedKeys;
    if (!mounted || !_scrollController.hasClients || gridWidth == null || groups == null || orderedKeys == null) {
      return;
    }
    final offset = timelineOffsetForAsset(orderedKeys, groups, gridWidth, assetId,
        kachelbreite: widget.kachelbreite, form: widget.form);
    if (offset == null) return;
    final position = _scrollController.position;
    // Bei Reihen ist die Zeilenhöhe nicht fest; die eingestellte Stufe ist
    // ihre Obergrenze und damit das richtige Mass für den Sicherheitsrand.
    final zeilenhoehe = widget.form == Zeitleistenform.reihen
        ? widget.kachelbreite + timelineGridSpacing
        : timelineRowHeightForWidth(gridWidth,
            kachelbreite: widget.kachelbreite);
    final oben = position.pixels;
    final unten = oben + position.viewportDimension;
    // Etwas Luft, damit die Kachel nicht genau abgeschnitten am Rand klebt.
    if (offset < oben) {
      _scrollController.animateTo(
        (offset - zeilenhoehe * 0.5).clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else if (offset + zeilenhoehe > unten) {
      _scrollController.animateTo(
        (offset + zeilenhoehe * 1.5 - position.viewportDimension).clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  /// Eine Kachel samt der beiden Hüllen, die es in beiden Rasterformen
  /// gibt: das kurze Aufblitzen nach einem Sprung und der Rahmen um die
  /// Kachel, die gerade mit den Pfeiltasten angesteuert ist.
  ///
  /// Herausgezogen, weil beide Formen sie brauchen – zweimal geschrieben
  /// wäre sie die Stelle, an der eine Form den Rahmen bekommt und die
  /// andere nicht.
  Widget _kachel(Rasterzeile asset) {
    final tile = AssetThumbnailTile(
      asset: asset,
      paths: widget.paths,
      selected: widget.selectedIds?.contains(asset.id) ?? false,
      onTap: () => widget.onTap(asset),
      onLongPress:
          widget.onLongPress == null ? null : () => widget.onLongPress!(asset),
    );
    final Widget kachel =
        asset.id == _flashingAssetId ? _FlashHighlight(child: tile) : tile;
    return asset.id == widget.aktiveKachelId
        ? AktiveKachelRahmen(child: kachel)
        : kachel;
  }

  /// Die Überschrift einer Gruppe – für beide Rasterformen dieselbe.
  Widget _ueberschrift(BuildContext context, List<Rasterzeile> gruppe) =>
      _MonthHeader(
        label: (widget.nachTag
                ? DateFormat.yMMMMEEEEd(
                    Localizations.localeOf(context).toString())
                : DateFormat.yMMMM(Localizations.localeOf(context).toString()))
            .format(gruppe.first.fileCreatedAt),
        groupAssets: gruppe,
        selectedIds: widget.selectedIds,
        onTap: widget.onHeaderTap,
      );

  /// Eine Monatsgruppe als ein einziger Sliver – **Überschrift, dann
  /// Reihe für Reihe**, in beiden Rasterformen.
  ///
  /// **Warum die Überschrift hineingehört und nicht danebensteht.** Ein
  /// Sliver baut immer sein erstes Kind – auch einer, der vollständig
  /// unterhalb des Sichtfensters liegt; der Viewport legt jeden Sliver
  /// aus, um zu wissen, wie hoch er ist. Die Zeitleiste hat **je Monat
  /// einen eigenen Sliver**, und dieses erste Kind war ein Foto (Raster)
  /// beziehungsweise eine ganze Fotoreihe (bündige Reihen). Gemessen an
  /// der echten Bibliothek – 82 Monate, 7307 Aufnahmen, ein Fenster von
  /// 1600 × 1000 Punkten bei doppelter Pixeldichte:
  ///
  /// ```
  ///                       Bilder dekodiert   Speicher   erster Bildschirm
  /// Reihen, vorher               581           99,7 MB       184 ms
  /// Reihen, nachher               79           27,3 MB        57 ms
  /// Raster, vorher               161           68,4 MB        65 ms
  /// Raster, nachher               80           34,4 MB        54 ms
  /// ```
  ///
  /// Sichtbar sind davon immer neunundsechzig beziehungsweise siebzig.
  /// Alles darüber wurde dekodiert, damit einundachtzig Monate sagen
  /// konnten, wie hoch sie sind. Als Kind 0 ist die Überschrift genau das
  /// billige erste Kind, das jeder Sliver ohnehin baut – und sie kostet
  /// kein Bild.
  ///
  /// **Belegt, nicht geschlossen.** Diese Kinder entstehen und vergehen
  /// während des ersten Auslegens; im Widget-Baum steht hinterher nur,
  /// was zu sehen ist, und ein Test, der Kacheln zählt, sieht deshalb
  /// keinen Unterschied. Ablesbar ist es am Bildspeicher: Vorher lag das
  /// **Erstfoto aller 82 Monate** darin, auch das des ältesten;
  /// hinterher eines. `zeitleiste_gruppensliver_test.dart` prüft genau
  /// das.
  ///
  /// **Ein `SliverList` und kein `SliverGrid`**, auch für die Quadrate:
  /// Ein `SliverGrid` kann kein fremdes erstes Kind aufnehmen. Die
  /// Spaltenzahl und die Kachelkante kommen jetzt aus
  /// [timelineColumnsForWidth] und [timelineRowHeightForWidth] – aus
  /// derselben Rechnung also, aus der auch der Zeitstrahl seine Höhen
  /// nimmt. Vorher stand die Anordnung im `SliverGridDelegate` und die
  /// Höhe daneben in der Rechnung; zwei Regeln für dieselbe Sache sind
  /// zwei Regeln, die auseinanderlaufen können.
  ///
  /// **Die Überschrift behält ihre natürliche Höhe** – deshalb
  /// `SliverList` und nicht `SliverVariedExtentList`, das jedem Kind eine
  /// feste Höhe aufzwänge. Bei grösserer Systemschrift wächst sie, und ein
  /// Deckel darauf wäre genau der Fehler, den die 18. Prüfrunde gefunden
  /// hat.
  ///
  /// **Und deshalb muss die Gesamthöhe von aussen kommen.** Ein
  /// `SliverList` schätzt seine Höhe aus dem Mittel der gebauten Kinder –
  /// und gebaut ist bei einem Monat ausserhalb des Sichtfensters nur noch
  /// die Überschrift. Ohne [_ReihenDelegate] sank die geschätzte
  /// Gesamthöhe der Zeitleiste von 148.523 auf 55.029 Punkte, und der
  /// Zeitstrahl hätte beim Sprung in einen späten Monat weit vor dem Ziel
  /// angehalten. Mit ihr steht sie bei 153.232 – der **gerechneten** Höhe,
  /// mit der der Zeitstrahl ohnehin arbeitet.
  Widget _gruppenSliver(
      List<Rasterzeile> gruppe, double gridWidth, Widget ueberschrift) {
    final buendig = widget.form == Zeitleistenform.reihen;
    final reihen = buendig
        ? zeitleisteReihen(gruppe, gridWidth, kachelbreite: widget.kachelbreite)
        : const <Bildreihe>[];
    final spalten = buendig
        ? 0
        : timelineColumnsForWidth(gridWidth, kachelbreite: widget.kachelbreite);
    // Die Rechnung liefert die Zeilenhöhe MIT dem Abstand darunter; die
    // Kachel selbst ist um diesen Abstand kleiner und quadratisch.
    final kante = buendig
        ? 0.0
        : timelineRowHeightForWidth(gridWidth,
                kachelbreite: widget.kachelbreite) -
            timelineGridSpacing;
    final anzahl =
        buendig ? reihen.length : (gruppe.length / spalten).ceil();

    Widget reiheBauen(int r) {
      final kinder = <Widget>[];
      if (buendig) {
        final reihe = reihen[r];
        for (var i = 0; i < reihe.plaetze.length; i++) {
          if (i > 0) kinder.add(const SizedBox(width: timelineGridSpacing));
          kinder.add(SizedBox(
            width: reihe.plaetze[i].breite,
            height: reihe.hoehe,
            child: _kachel(gruppe[reihe.plaetze[i].index]),
          ));
        }
      } else {
        for (var i = 0; i < spalten; i++) {
          final index = r * spalten + i;
          if (i > 0) kinder.add(const SizedBox(width: timelineGridSpacing));
          // Die letzte Zeile ist selten voll. Die leeren Plätze bleiben
          // als Kästen stehen, damit die vorhandenen dort sitzen, wo sie
          // im Raster sässen - und nicht mittig verteilt werden.
          kinder.add(SizedBox(
            width: kante,
            height: kante,
            child: index < gruppe.length ? _kachel(gruppe[index]) : null,
          ));
        }
      }
      return Padding(
        // Seitlich derselbe Rand wie zuvor am Sliver - dort läge jetzt
        // auch die Überschrift darin, die ihren eigenen mitbringt.
        //
        // Zwischen den Reihen derselbe Abstand wie zwischen den Bildern
        // einer Reihe; hinter der letzten keiner, sonst klaffte unter
        // jedem Monat eine Lücke zu viel.
        padding: EdgeInsets.only(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: r == anzahl - 1 ? 0 : timelineGridSpacing),
        child: Row(children: kinder),
      );
    }

    return SliverList(
      delegate: _ReihenDelegate(
        gesamthoehe: timelineMonthGroupHeight(gruppe, gridWidth,
            kachelbreite: widget.kachelbreite,
            form: widget.form,
            mitUeberschrift: widget.gliedern),
        anzahl: anzahl + 1,
        bauen: (context, index) =>
            index == 0 ? ueberschrift : reiheBauen(index - 1),
      ),
    );
  }

  /// Die letzte Gruppierung samt der Liste, aus der sie entstand.
  ({List<int> schluessel, Map<int, List<Rasterzeile>> gruppen})? _gruppenCache;
  List<Rasterzeile>? _gruppenFuer;
  bool? _gruppenNachTag;
  bool? _gruppenGliedern;
  bool? _gruppenAbsteigend;

  /// Gruppiert – aber nur, wenn sich etwas geändert hat.
  ///
  /// **Warum gemerkt.** Das Aufteilen lief bei JEDEM Neuaufbau, und
  /// Neuaufbauten löst hier schon jeder Pfeiltastendruck aus (siehe
  /// [Rasterbedienung]) und jeder Klick in der Mehrfachauswahl. An der
  /// gewachsenen Bibliothek gemessen: 0,30 ms beim Startfenster von 600
  /// Aufnahmen, 0,94 ms sobald das Fenster auf die ganze Bibliothek
  /// gewachsen ist – dazu rund achtzig frische Listen je Tastendruck.
  ///
  /// Verglichen wird auf **Gleichheit der Liste selbst**, nicht auf
  /// ihren Inhalt: Der Strom liefert bei jeder Änderung eine neue Liste,
  /// und dieselbe Liste heisst zuverlässig „nichts hat sich geändert".
  /// Sie Eintrag für Eintrag zu vergleichen wäre teurer als das
  /// Gruppieren selbst.
  /// Nur für den Prüfstand: die zuletzt errechnete Gruppierung **als
  /// Objekt**. Damit lässt sich zeigen, dass sie bei einem Neuaufbau
  /// nicht noch einmal entstanden ist – eine gleiche Gruppierung wäre
  /// kein Beleg, eine identische ist einer.
  @visibleForTesting
  Object? get lastGroupsFuerTest => _gruppenCache?.gruppen;

  ({List<int> schluessel, Map<int, List<Rasterzeile>> gruppen}) _gruppierung() {
    final cache = _gruppenCache;
    if (cache != null &&
        identical(_gruppenFuer, widget.assets) &&
        _gruppenNachTag == widget.nachTag &&
        _gruppenGliedern == widget.gliedern &&
        _gruppenAbsteigend == widget.absteigend) {
      return cache;
    }
    _gruppenFuer = widget.assets;
    _gruppenNachTag = widget.nachTag;
    _gruppenGliedern = widget.gliedern;
    _gruppenAbsteigend = widget.absteigend;
    // Ohne Gliederung eine einzige Gruppe, die die Liste unveraendert
    // durchreicht - und keine zweite Sortierung darauf: Die Reihenfolge
    // kommt aus dem ORDER BY und soll genau so stehen bleiben.
    if (!widget.gliedern) {
      return _gruppenCache =
          (schluessel: const [0], gruppen: {0: widget.assets});
    }
    return _gruppenCache = widget.nachTag
        ? tagesgruppen(widget.assets, absteigend: widget.absteigend)
        : monatsgruppen(widget.assets, absteigend: widget.absteigend);
  }

  @override
  Widget build(BuildContext context) {
    // Günstiger Integer-Schlüssel (Jahr*100+Monat) statt eines pro Foto neu
    // formatierten Datums-Strings – bei jeder DB-Änderung liefert
    // `watchTimeline()` die komplette Liste neu, wodurch diese Gruppierung
    // bei großen Bibliotheken sonst unnötig oft (kostspielig) neu läuft. Der
    // menschenlesbare Monatsname wird weiterhin nur einmal pro Gruppe für
    // die Überschrift formatiert, nicht pro Foto.
    final geteilt = _gruppierung();
    final groups = geteilt.gruppen;
    final orderedKeys = geteilt.schluessel;
    final showScrubber =
        widget.gliedern && rasterMitZeitstrahl(orderedKeys.length);
    _lastGroups = groups;
    _lastOrderedKeys = orderedKeys;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = showScrubber ? constraints.maxWidth - _scrubberWidth : constraints.maxWidth;
        _lastGridWidth = gridWidth;
        return Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: gridWidth,
              // Kein eigener Rollbalken, solange der Zeitstrahl daneben
              // steht: Auf dem Rechner blendet Flutter von sich aus einen
              // ein, und dann stehen zwei Bedienelemente für dieselbe Sache
              // nebeneinander – der schmale graue Streifen direkt links vom
              // Zeitstrahl. Ohne Zeitstrahl (weniger als zwei Monatsgruppen)
              // bleibt er, sonst gäbe es überhaupt keine Rückmeldung mehr,
              // wo man sich in der Liste befindet.
              child: ScrollConfiguration(
                behavior: showScrubber
                    ? ScrollConfiguration.of(context).copyWith(scrollbars: false)
                    : ScrollConfiguration.of(context),
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    for (final key in orderedKeys) ...[
                      _gruppenSliver(
                          groups[key]!,
                          gridWidth,
                          widget.gliedern
                              ? _ueberschrift(context, groups[key]!)
                              : const SizedBox.shrink()),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                ),
              ),
            ),
            if (showScrubber)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: _scrubberWidth,
                child: TimelineScrubber(
                  orderedKeys: orderedKeys,
                  groups: groups,
                  controller: _scrollController,
                  gridWidth: gridWidth,
                  kachelbreite: widget.kachelbreite,
                  form: widget.form,
                  tageweise: widget.nachTag,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Monatsüberschrift der Timeline/Jahresansicht. Antippbar (wenn [onTap]
/// gesetzt ist): fügt alle Fotos/Videos dieses Monats auf einen Schlag zur
/// Mehrfachauswahl hinzu bzw. entfernt sie wieder, falls schon alle
/// ausgewählt sind ("Auswahl umschalten" statt reinem "immer hinzufügen" –
/// so lässt sich ein versehentlich ausgewählter Monat genauso einfach per
/// erneutem Antippen wieder abwählen).
/// Ein `SliverChildBuilderDelegate`, der seine Gesamthöhe **weiss**.
///
/// Ohne ihn schätzt `RenderSliverList` sie aus dem Mittel der gebauten
/// Kinder hoch – und ausserhalb des Sichtfensters ist das nur die
/// Überschrift. Siehe [MonthGroupedAssetGridState._reihenSliver].
class _ReihenDelegate extends SliverChildBuilderDelegate {
  _ReihenDelegate({
    required NullableIndexedWidgetBuilder bauen,
    required int anzahl,
    required this.gesamthoehe,
  }) : super(bauen, childCount: anzahl);

  /// Überschrift plus alle Reihen samt Abständen.
  final double gesamthoehe;

  @override
  double? estimateMaxScrollOffset(int firstIndex, int lastIndex,
          double leadingScrollOffset, double trailingScrollOffset) =>
      gesamthoehe;
}

class _MonthHeader extends StatelessWidget {
  final String label;
  final List<Rasterzeile> groupAssets;
  final Set<String>? selectedIds;
  final void Function(List<Rasterzeile> groupAssets)? onTap;

  const _MonthHeader({
    required this.label,
    required this.groupAssets,
    required this.selectedIds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ids = selectedIds;
    final allSelected = ids != null && ids.isNotEmpty && groupAssets.every((a) => ids.contains(a.id));

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(groupAssets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onTap != null) ...[
              Icon(
                allSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: allSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
            ],
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Kurz ausklingender, farbiger Rahmen um eine Kachel – zeigt "hier ist das
/// gesuchte Foto", nachdem "Foto in der Timeline anzeigen" dorthin
/// gescrollt hat.
class _FlashHighlight extends StatelessWidget {
  final Widget child;
  const _FlashHighlight({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.0, end: 0.0),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeOut,
      builder: (context, value, child) => Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.tealAccent.withValues(alpha: value), width: 3),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: child,
      ),
      child: child,
    );
  }
}

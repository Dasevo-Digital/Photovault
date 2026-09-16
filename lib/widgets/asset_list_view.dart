import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/asset_grouping.dart';
import '../services/groessentext.dart';
import '../services/listenspalten.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import '../widgets/color_label_picker.dart';
import '../widgets/star_rating.dart';

/// Die Fotos als Liste mit Metadaten-Spalten statt als Raster.
///
/// Das Raster war bisher die einzige Ansicht. Eine Liste ist die
/// Arbeitsweise, wenn man nicht das Bild sucht, sondern die Aufnahme: „Wo
/// stand die Blende?", „Welches Objektiv war das?". Die Angaben liegen alle
/// bereits in der Datenbank – sie waren nur nirgends nebeneinander zu
/// sehen.
///
/// **Was sich geändert hat.** Bis hierher waren es fünf feste Angaben,
/// deren Sichtbarkeit allein an der Fensterbreite hing, ohne Überschrift
/// und ohne Zutun. Jetzt hat jede Spalte einen Namen, eine Breite, die
/// sich ziehen lässt, und ein Häkchen im Menü daneben – siehe
/// [Listenspaltenwahl]. Wer nichts einstellt, sieht dieselben fünf.
class AssetListView extends StatefulWidget {
  final List<AssetData> assets;
  final StoragePaths paths;
  final ListenGruppierung gruppierung;

  /// In welche Richtung die Monatsgruppen laufen – siehe
  /// [gruppiereAssets]. Bei aufsteigender Sortierung stünden die Monate
  /// sonst rückwärts und die Fotos darin vorwärts.
  final bool absteigend;
  final Set<String> selectedIds;
  final void Function(AssetData asset) onTap;
  final void Function(AssetData asset) onLongPress;
  final String? highlightAssetId;

  /// Welche Spalten in welcher Breite.
  final Listenspaltenwahl spalten;

  /// Wird gerufen, wenn eine Spalte gezogen oder umgeschaltet wurde – der
  /// Aufrufer legt die Wahl ab.
  final ValueChanged<Listenspaltenwahl> onSpalten;

  /// Jede Änderung springt an den Listenanfang – zu den neuesten Fotos.
  /// Siehe [MonthGroupedAssetGrid.nachObenSignal]; die Listenansicht muss
  /// dasselbe tun, sonst hinge das Verhalten daran, welche Darstellung
  /// gerade gewählt ist.
  final ValueListenable<int>? nachObenSignal;

  const AssetListView({
    super.key,
    required this.assets,
    required this.paths,
    required this.gruppierung,
    this.absteigend = true,
    required this.selectedIds,
    required this.onTap,
    required this.onLongPress,
    required this.spalten,
    required this.onSpalten,
    this.highlightAssetId,
    this.nachObenSignal,
  });

  String _gruppentitel(BuildContext context, String schluessel) {
    if (gruppierung == ListenGruppierung.kamera) {
      return schluessel.isEmpty
          ? AppTexte.of(context).listeOhneKamera
          : schluessel;
    }
    final zahl = int.tryParse(schluessel);
    if (zahl == null) return schluessel;
    final datum = DateTime(zahl ~/ 100, zahl % 100);
    return DateFormat.yMMMM(Localizations.localeOf(context).toString()).format(datum);
  }

  @override
  State<AssetListView> createState() => _AssetListViewState();
}

/// Die Beschriftung einer Spalte.
///
/// Hier und nicht in der Aufzählung: [Listenspalte] gehört zum Dienst und
/// kennt keine Sprache – dieselbe Trennung wie beim Modellkatalog.
String listenspaltenName(AppTexte t, Listenspalte s) => switch (s) {
      Listenspalte.dateiname => t.listeSpalteDateiname,
      Listenspalte.datum => t.listeSpalteDatum,
      Listenspalte.kamera => t.listeSpalteKamera,
      Listenspalte.objektiv => t.listeSpalteObjektiv,
      Listenspalte.belichtung => t.listeSpalteBelichtung,
      Listenspalte.bewertung => t.listeSpalteBewertung,
      Listenspalte.farbe => t.listeSpalteFarbe,
      Listenspalte.masse => t.listeSpalteMasse,
      Listenspalte.groesse => t.listeSpalteGroesse,
      Listenspalte.art => t.listeSpalteArt,
      Listenspalte.ort => t.listeSpalteOrt,
    };

class _AssetListViewState extends State<AssetListView> {
  final _scrollController = ScrollController();

  /// Die Breite, die gerade gezogen wird – erst beim Loslassen abgelegt.
  ///
  /// Bei jedem Punkt Bewegung in die Datenbank zu schreiben wären
  /// hunderte Schreibvorgänge für eine einzige Geste.
  Listenspalte? _amZiehen;
  double _ziehbreite = 0;

  @override
  void initState() {
    super.initState();
    widget.nachObenSignal?.addListener(_nachOben);
  }

  @override
  void didUpdateWidget(covariant AssetListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nachObenSignal != widget.nachObenSignal) {
      oldWidget.nachObenSignal?.removeListener(_nachOben);
      widget.nachObenSignal?.addListener(_nachOben);
    }
  }

  @override
  void dispose() {
    widget.nachObenSignal?.removeListener(_nachOben);
    _scrollController.dispose();
    super.dispose();
  }

  void _nachOben() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_scrollController.offset <= 0) return;
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  double _breiteVon(Listenspalte s) =>
      s == _amZiehen ? _ziehbreite : widget.spalten.breiteVon(s);

  double get _gesamtbreite {
    var summe = 0.0;
    for (final s in widget.spalten.spalten) {
      summe += _breiteVon(s);
    }
    // Der Platz fuer das Spaltenmenue am rechten Ende der Kopfzeile
    // gehoert dazu. Ohne ihn ist die Reihe genau so breit wie ihre
    // Spalten - und das Menue laeuft ueber den Rand hinaus, sobald die
    // Spalten das Fenster fuellen.
    return summe + _bildbreite + AppSpacing.md * 2 + _menuebreite;
  }

  /// Das Vorschaubild ganz links – keine Spalte, sondern die Zeile selbst.
  static const _bildbreite = 48.0 + AppSpacing.md;

  /// Der Knopf für das Spaltenmenü ganz rechts in der Kopfzeile.
  static const _menuebreite = 48.0;

  @override
  Widget build(BuildContext context) {
    final gruppen = gruppiereAssets(widget.assets, widget.gruppierung,
        absteigend: widget.absteigend);

    // Eine flache Liste aus Kopfzeilen und Fotos: So bleibt das Bauen
    // faul, auch wenn eine Gruppe mehrere tausend Fotos enthält.
    final eintraege = <Object>[];
    for (final gruppe in gruppen) {
      if (widget.gruppierung != ListenGruppierung.keine) {
        eintraege.add(gruppe.schluessel);
      }
      eintraege.addAll(gruppe.assets);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Kopfzeile und Zeilen liegen in EINER waagerechten Rolle. Zwei
        // getrennte Rollen müsste jemand von Hand gleichhalten, und bei
        // der ersten Ungleichheit stünde die Überschrift über der
        // falschen Spalte.
        final breite = _gesamtbreite > constraints.maxWidth
            ? _gesamtbreite
            : constraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: breite,
            height: constraints.maxHeight,
            child: Column(
              children: [
                _Kopfleiste(
                  spalten: widget.spalten,
                  breiteVon: _breiteVon,
                  bildbreite: _bildbreite,
                  onZiehStart: (s) => setState(() {
                    _amZiehen = s;
                    _ziehbreite = widget.spalten.breiteVon(s);
                  }),
                  onZiehen: (dx) => setState(() {
                    _ziehbreite = (_ziehbreite + dx).clamp(
                        listenspalteMindestbreite, listenspalteHoechstbreite);
                  }),
                  onZiehEnde: () {
                    final s = _amZiehen;
                    if (s == null) return;
                    final breite = _ziehbreite;
                    setState(() => _amZiehen = null);
                    widget.onSpalten(widget.spalten.mitBreite(s, breite));
                  },
                  onUmschalten: (s) =>
                      widget.onSpalten(widget.spalten.umgeschaltet(s)),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: eintraege.length,
                    itemBuilder: (context, index) {
                      final eintrag = eintraege[index];
                      if (eintrag is String) {
                        return _Kopfzeile(
                            titel: widget._gruppentitel(context, eintrag));
                      }
                      final asset = eintrag as AssetData;
                      return _Zeile(
                        asset: asset,
                        paths: widget.paths,
                        ausgewaehlt: widget.selectedIds.contains(asset.id),
                        hervorgehoben: asset.id == widget.highlightAssetId,
                        spalten: widget.spalten.spalten,
                        breiteVon: _breiteVon,
                        bildbreite: _bildbreite,
                        onTap: () => widget.onTap(asset),
                        onLongPress: () => widget.onLongPress(asset),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Die Überschriftenzeile mit den Ziehgriffen und dem Spaltenmenü.
class _Kopfleiste extends StatelessWidget {
  final Listenspaltenwahl spalten;
  final double Function(Listenspalte) breiteVon;
  final double bildbreite;
  final ValueChanged<Listenspalte> onZiehStart;
  final ValueChanged<double> onZiehen;
  final VoidCallback onZiehEnde;
  final ValueChanged<Listenspalte> onUmschalten;

  const _Kopfleiste({
    required this.spalten,
    required this.breiteVon,
    required this.bildbreite,
    required this.onZiehStart,
    required this.onZiehen,
    required this.onZiehEnde,
    required this.onUmschalten,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final stil = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: farben.onSurfaceVariant,
        );
    return Container(
      // Feste Hoehe: Die Ziehgriffe zwischen den Spalten sollen ueber die
      // ganze Zeile gehen, und dafuer brauchen sie eine, an der sie sich
      // strecken koennen - in einer Reihe ohne Hoehe waere das eine
      // unendliche Vorgabe.
      height: _kopfhoehe,
      decoration: BoxDecoration(
        color: farben.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: farben.outlineVariant)),
      ),
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: bildbreite),
          for (final s in spalten.spalten) ...[
            SizedBox(
              width: breiteVon(s) - _griffbreite,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(listenspaltenName(t, s),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: stil),
              ),
            ),
            _Ziehgriff(
              tooltip: t.listeSpalteBreiteAendern,
              onStart: () => onZiehStart(s),
              onZiehen: onZiehen,
              onEnde: onZiehEnde,
            ),
          ],
          const Spacer(),
          // Das Menü steht rechts in der Kopfzeile und nicht in der
          // Ansichtsleiste darüber: Es gehört zu den Spalten, und dort
          // sucht man es.
          PopupMenuButton<Listenspalte>(
            tooltip: t.listeSpalten,
            icon: Icon(Icons.view_column_outlined,
                size: 18, color: farben.onSurfaceVariant),
            onSelected: onUmschalten,
            itemBuilder: (context) => [
              for (final s in Listenspalte.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: spalten.zeigt(s),
                  child: Text(listenspaltenName(t, s)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wie breit der Griff zwischen zwei Spalten ist.
///
/// Sechs Punkte: schmal genug, um nicht als Lücke aufzufallen, breit
/// genug, um ihn mit der Maus zu treffen.
const double _griffbreite = 6;

/// Wie hoch die Ueberschriftenzeile ist.
const double _kopfhoehe = 34;

class _Ziehgriff extends StatelessWidget {
  final String tooltip;
  final VoidCallback onStart;
  final ValueChanged<double> onZiehen;
  final VoidCallback onEnde;

  const _Ziehgriff({
    required this.tooltip,
    required this.onStart,
    required this.onZiehen,
    required this.onEnde,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Vom Aufsetzen an zaehlen, nicht erst ab der Wackelschwelle:
        // Sonst verliert die Spalte die ersten achtzehn Punkte jeder
        // Geste, und ein kurzes Zupfen bewirkt gar nichts.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => onStart(),
        onHorizontalDragUpdate: (d) => onZiehen(d.delta.dx),
        onHorizontalDragEnd: (_) => onEnde(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: _griffbreite,
            child: Center(
              child: Container(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Kopfzeile extends StatelessWidget {
  final String titel;
  const _Kopfzeile({required this.titel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Text(titel,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}

class _Zeile extends StatelessWidget {
  final AssetData asset;
  final StoragePaths paths;
  final bool ausgewaehlt;
  final bool hervorgehoben;
  final List<Listenspalte> spalten;
  final double Function(Listenspalte) breiteVon;
  final double bildbreite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _Zeile({
    required this.asset,
    required this.paths,
    required this.ausgewaehlt,
    required this.hervorgehoben,
    required this.spalten,
    required this.breiteVon,
    required this.bildbreite,
    required this.onTap,
    required this.onLongPress,
  });

  /// Belichtungsangaben in der Schreibweise, die auf jedem Gehäuse steht.
  ///
  /// Die Verschlusszeit als Bruch, sobald sie kürzer als eine Sekunde ist –
  /// „0,004 s" liest niemand, „1/250" jeder.
  String _belichtung() {
    final teile = <String>[];
    if (asset.focalLengthMm != null) {
      teile.add('${asset.focalLengthMm!.round()} mm');
    }
    if (asset.fNumber != null) {
      teile.add('f/${asset.fNumber!.toStringAsFixed(1)}');
    }
    final zeit = asset.exposureTimeSeconds;
    if (zeit != null && zeit > 0) {
      teile.add(zeit >= 1 ? '${zeit.toStringAsFixed(1)} s' : '1/${(1 / zeit).round()}');
    }
    if (asset.iso != null) teile.add('ISO ${asset.iso}');
    return teile.join(' · ');
  }

  String _ort() {
    final teile = [
      if (asset.locationCity != null && asset.locationCity!.isNotEmpty)
        asset.locationCity!,
      if (asset.locationCountry != null && asset.locationCountry!.isNotEmpty)
        asset.locationCountry!,
    ];
    return teile.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final thumb = asset.thumbnailRelativePath;
    final sprache = Localizations.localeOf(context).toString();

    /// Text in einer Spalte – schmal, grau und mit fluchtenden Ziffern.
    Widget text(String wert, {bool ziffern = false}) => Text(
          wert.isEmpty ? '—' : wert,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: farben.onSurfaceVariant,
            fontSize: 12,
            fontFeatures:
                ziffern ? const [FontFeature.tabularFigures()] : null,
          ),
        );

    Widget inhalt(Listenspalte s) => switch (s) {
          Listenspalte.dateiname => Text(asset.originalFileName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          // Die Uhrzeit weicht dem Vermerk, wenn das Datum geraten ist:
          // Sie waere hier die genaueste Angabe der ganzen Zeile und
          // zugleich die einzige, die sicher nicht stimmt. Und die
          // Listenansicht ist die Stelle, an der jemand Daten
          // nebeneinander liest - dort faellt eine Reihe gleicher
          // Zeitstempel ueberhaupt erst auf.
          Listenspalte.datum => text(
              asset.datumGeschaetzt
                  ? '${DateFormat.yMd(sprache).format(asset.fileCreatedAt)} '
                      '(${AppTexte.of(context).infoDatumGeschaetztKurz})'
                  : DateFormat.yMd(sprache).add_Hm().format(asset.fileCreatedAt),
              ziffern: true),
          Listenspalte.kamera => text(kamerabezeichnung(asset) ?? ''),
          Listenspalte.objektiv => text(asset.lensModel ?? ''),
          Listenspalte.belichtung => text(_belichtung(), ziffern: true),
          // Die Sterne sind das einzige, was nicht schrumpft, wenn die
          // Spalte schmaler wird - ohne den Deckel laeuft die Reihe bei
          // der Mindestbreite ueber ihren Rand hinaus.
          Listenspalte.bewertung => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: StarRating(value: asset.rating, size: 14),
            ),
          Listenspalte.farbe => asset.colorLabel == null
              ? text('')
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorLabelSwatches[asset.colorLabel!] ??
                          farben.outlineVariant,
                    ),
                  ),
                ),
          Listenspalte.masse =>
            text(asset.widthPx == null || asset.heightPx == null
                ? ''
                : '${asset.widthPx} × ${asset.heightPx}', ziffern: true),
          Listenspalte.groesse => text(
              asset.fileSizeBytes <= 0 ? '' : groessentext(asset.fileSizeBytes),
              ziffern: true),
          Listenspalte.art =>
            text(asset.type == 'VIDEO' ? t.allgVideo : t.allgFoto),
          Listenspalte.ort => text(_ort()),
        };

    return Material(
      color: ausgewaehlt
          ? farben.primaryContainer
          : hervorgehoben
              ? farben.surfaceContainerHigh
              : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.md, top: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 36,
                child: thumb == null
                    ? Icon(Icons.image_outlined, size: 18, color: farben.outline)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: Image.file(
                          paths.absolute(thumb),
                          fit: BoxFit.cover,
                          cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context)).round(),
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.broken_image_outlined, size: 18, color: farben.outline),
                        ),
                      ),
              ),
              SizedBox(width: bildbreite - 48),
              for (final s in spalten)
                SizedBox(
                  // Die **volle** Spaltenbreite, und der Griff als Polster
                  // darin. In der Kopfleiste steht der Griff als eigener
                  // Kasten hinter der Ueberschrift; zoege man ihn hier
                  // ebenfalls ab, waere jede Zeilenspalte sechs Punkte
                  // schmaler als ihre Ueberschrift – und der Versatz
                  // summierte sich ueber die Reihe (bei der dritten Spalte
                  // gemessene 12 Punkte).
                  width: breiteVon(s),
                  child: Padding(
                    padding: const EdgeInsets.only(right: _griffbreite),
                    child: inhalt(s),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../utils/dauertext.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/arbeitsbereich.dart';
import '../widgets/tastenkuerzel.dart';
import 'albums_screen.dart';
import 'calendar_screen.dart';
import 'explore_screen.dart';
import 'import_progress_sheet.dart';
import 'map_screen.dart';
import 'people_screen.dart';
import '../services/restore_queue_service.dart';
import '../services/tresor_waechter.dart';
import 'restore_queue_screen.dart';
import 'reisen_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'stammbaum_screen.dart';
import 'timeline_screen.dart';
import 'tools_screen.dart';

/// Dauerhafter, kleiner Hinweis auf laufende/wartende KI-Restaurierungs-
/// Aufträge (siehe RestoreQueueService) – bleibt sichtbar, während der
/// Nutzer zwischen den Hauptbereichen wechselt, da es (anders als eine
/// SnackBar auf einem einzelnen Screen) Teil der dauerhaften App-Hülle ist.
/// Tippen öffnet die vollständige Warteschlange ([RestoreQueueScreen]).
/// Unsichtbar (`SizedBox.shrink`), solange kein Auftrag wartet/läuft.
///
/// Das Öffnen liegt beim Aufrufer ([oeffnen]) und nicht mehr hier: Das Band
/// hängt über der Menüleiste, sein eigenes `Navigator.of(context)` fände
/// also das Fenster und verdeckte die Leiste. Die Warteschlange ist eine
/// gewöhnliche Liste – sie gehört neben die Leiste, nicht darüber.
class _RestoreQueueBanner extends StatelessWidget {
  final LibraryState library;
  final VoidCallback oeffnen;
  const _RestoreQueueBanner({required this.library, required this.oeffnen});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RestoreJobData>>(
      stream: library.db.watchRestoreJobs(),
      builder: (context, snapshot) {
        final jobs = snapshot.data ?? const <RestoreJobData>[];
        final running = jobs.where((j) => j.status == 'running').firstOrNull;
        final queuedCount = jobs.where((j) => j.status == 'queued').length;
        if (running == null && queuedCount == 0) return const SizedBox.shrink();

        final t = AppTexte.of(context);
        // Prozent statt „Kachel 12 von 20": Die Kachel ist ein Begriff
        // aus dem Modell, nicht aus der Welt des Nutzers. Die Restzeit
        // steht nur da, wenn sie sich aus bereits erledigten Kacheln
        // wirklich rechnen lässt (siehe [restzeitSchaetzung]).
        final prozent = running == null ? null : fortschrittProzent(running);
        final rest = running == null ? null : restzeitSchaetzung(running);
        final String text;
        if (running == null) {
          text = queuedCount > 0
              ? t.restaurierungWartend(queuedCount)
              : t.restaurierungWirdVorbereitet;
        } else if (prozent == null) {
          // Die Gesamtzahl der Kacheln steht erst fest, wenn das Bild
          // dekodiert ist. Bis dahin gibt es keinen Anteil zu zeigen.
          text = t.restaurierungWirdVorbereitet;
        } else if (queuedCount > 0) {
          text = t.restaurProzentMitWarteschlange(prozent, queuedCount);
        } else if (rest != null && rest > Duration.zero) {
          text = t.restaurProzentMitRest(prozent, dauerText(t, rest));
        } else {
          text = t.restaurProzentLaeuft(prozent);
        }

        return Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: InkWell(
            onTap: oeffnen,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(text,
                          style: Theme.of(context).textTheme.bodySmall)),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Eine Zeile des Hinweisbandes: Ringfortschritt, Text, Abbrechen-Knopf.
///
/// Nur der Knopf bricht ab, nicht die ganze Zeile: Ein Tipp auf den
/// Fortschrittstext beendete sonst einen stundenlangen Lauf (Audit-Fund).
class _Laufzeile extends StatelessWidget {
  final double? anteil;
  final String text;
  final VoidCallback abbrechen;
  const _Laufzeile(
      {required this.anteil, required this.text, required this.abbrechen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.sm,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: anteil),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          TextButton(
            onPressed: abbrechen,
            child: Text(AppTexte.of(context).allgAbbrechen),
          ),
        ],
      ),
    );
  }
}

/// Zeigt an, was gerade im Hintergrund läuft – die Nachanalyse nach einem
/// Import (siehe LibraryState.starteHintergrundanalyse) und jede von Hand
/// gestartete Aufgabe (siehe LibraryState.starteAufgabe). Unsichtbar,
/// solange nichts läuft.
///
/// Die zweite Hälfte ist neu und der eigentliche Punkt: Seit die Aufgaben
/// kein sperrendes Fenster mehr aufziehen, wäre ohne diesen Hinweis
/// nirgends zu sehen, dass überhaupt gearbeitet wird – man startet etwas,
/// navigiert weg und hat keinen Anhaltspunkt mehr.
class _AnalyseBanner extends StatelessWidget {
  final LibraryState library;
  const _AnalyseBanner({required this.library});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final a = library.analyse;
    final laeufe = library.laufendeAufgaben.toList();
    if (a == null && laeufe.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (a != null)
            _Laufzeile(
              anteil: a.gesamt > 0 ? a.erledigt / a.gesamt : null,
              text: t.analyseLaeuft(
                analysestufeName(t, a.stufe),
                a.stufeNummer,
                a.stufenGesamt,
                a.gesamt > 0 ? ', ${a.erledigt}/${a.gesamt}' : '',
              ),
              abbrechen: library.brichHintergrundanalyseAb,
            ),
          for (final lauf in laeufe)
            _Laufzeile(
              anteil: lauf.anteil,
              text: lauf.gesamt > 0
                  ? '${lauf.titel}  ${lauf.erledigt}/${lauf.gesamt}'
                  : lauf.titel,
              abbrechen: () => library.brichAufgabeAb(lauf.schluessel),
            ),
        ],
      ),
    );
  }
}

/// Icon für einen Navigationseintrag mit Hover-"Pop"-Effekt (leichtes
/// Aufskalieren + Tooltip mit dem Namen) für Maus-Nutzer auf dem Desktop –
/// relevant, weil bei `labelType: NavigationRailLabelType.selected` nicht
/// ausgewählte Einträge sonst nur als reines Icon ohne Beschriftung
/// erscheinen.
class _HoverNavIcon extends StatefulWidget {
  final IconData icon;
  final String label;
  final double size;
  const _HoverNavIcon(
      {required this.icon, required this.label, this.size = 24});

  @override
  State<_HoverNavIcon> createState() => _HoverNavIconState();
}

class _HoverNavIconState extends State<_HoverNavIcon> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 300),
        child: AnimatedScale(
          scale: _hovering ? 1.25 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Icon(widget.icon, size: widget.size),
        ),
      ),
    );
  }
}

/// Die Nummern der Hauptbereiche – dieselbe Reihenfolge wie
/// [_HomeShellState._destinationLabels], und die ist die eine Quelle der
/// Wahrheit dafür.
///
/// Sie stehen hier, weil ein Bildschirm tief im Arbeitsbereich über
/// [LibraryState.zeigeBereich] dorthin schicken können muss und eine nackte
/// `6` an jener Stelle niemandem sagt, wohin.
abstract final class Hauptbereich {
  static const zeitleiste = 0;
  static const erkunden = 1;
  static const kalender = 2;
  static const karte = 3;
  static const reisen = 4;
  static const suche = 5;
  static const personen = 6;
  static const stammbaum = 7;
  static const alben = 8;
  static const werkzeuge = 9;
  static const einstellungen = 10;
}

class HomeShell extends StatefulWidget {
  final LibraryState library;
  const HomeShell({super.key, required this.library});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Der gezeigte Hauptbereich – als Notifier, nicht als schlichtes Feld.
  ///
  /// Der Grund ist die stehende Menüleiste: Die Seite liegt seit ihr in
  /// einem eigenen Navigator ([Arbeitsbereich]), und dessen Blatt baut
  /// **nicht** mit dieser Hülle neu auf. Ein `setState` hier bliebe für
  /// die Seite folgenlos; der Notifier erreicht beide, Leiste und Seite.
  final ValueNotifier<int> _seite = ValueNotifier(0);

  /// Der Navigator der Fläche neben der Leiste – siehe [Arbeitsbereich].
  /// Gebraucht wird er von den Bändern darüber, die ausserhalb liegen.
  final GlobalKey<NavigatorState> _bereich = GlobalKey<NavigatorState>();

  /// Sperrt den Tresor, sobald das Fenster aus dem Blick gerät.
  ///
  /// Hier und nicht in `main.dart`: Dort gibt es die [LibraryState] noch
  /// nicht als Feld, sondern erst im Aufbau. Hier liegt sie am Widget, und
  /// dieser Bildschirm ist die ganze Sitzung über da.
  late final Tresorwaechter _tresor =
      Tresorwaechter(widget.library.sperreTresor)..horche();

  /// Zähler, den das Zeitleisten-Symbol hochzählt. Die Zeitleiste springt
  /// bei jeder Änderung zu den neuesten Fotos.
  ///
  /// Ein Zähler statt eines Schalters: Zweimal tippen muss zweimal
  /// wirken, auch wenn man zwischendurch nichts anderes getan hat.
  final ValueNotifier<int> _zeitleisteNachOben = ValueNotifier(0);

  // labelType.selected zeigt den Namen nur beim ausgewählten Eintrag an
  // (siehe Kommentar unten) – beim Hovern über einen NICHT ausgewählten
  // Eintrag mit der Maus soll er trotzdem kurz sichtbar werden, kombiniert
  // mit einem leichten Pop/Scale-Effekt (siehe _HoverNavIcon).
  //
  // [iconSize]/[itemPadding] skalieren mit der Fensterhöhe (siehe
  // [_railScale] in build()) – ohne das stehen die 9 Einträge bei einem
  // hohen Fenster winzig oben zusammengedrängt, mit viel ungenutztem Platz
  // darunter bis zum Import-Button.
  List<NavigationRailDestination> _buildDestinations(
      AppTexte t, double iconSize, double itemPadding) {
    final labels = _destinationLabels(t);
    NavigationRailDestination dest(
        IconData outlined, IconData filled, String label) {
      return NavigationRailDestination(
        icon: _HoverNavIcon(icon: outlined, label: label, size: iconSize),
        selectedIcon: _HoverNavIcon(icon: filled, label: label, size: iconSize),
        label: Text(label),
        padding: EdgeInsets.symmetric(vertical: itemPadding),
      );
    }

    return [
      for (var i = 0; i < labels.length; i++)
        dest(_destinationIconsOutlined[i], _destinationIconsFilled[i],
            labels[i]),
    ];
  }

  /// Reihenfolge = Tab-Index = ⌘1…⌘9 (siehe [_handleKeyEvent]) = Reihenfolge
  /// der [NavigationBar]-Ziele unten – eine einzige Quelle der Wahrheit statt
  /// dreier parallel gepflegter Listen.
  ///
  /// Nicht mehr `const`, seit die Oberfläche übersetzbar ist: Die
  /// Beschriftungen hängen jetzt an der aktiven Sprache und müssen bei
  /// jedem Aufbau neu geholt werden – die Reihenfolge bleibt aber genau
  /// die eine Quelle der Wahrheit, die sie vorher war.
  static List<String> _destinationLabels(AppTexte t) => [
        t.navTimeline,
        t.navErkunden,
        t.navKalender,
        t.navKarte,
        t.navReisen,
        t.navSuche,
        t.navPersonen,
        t.navStammbaum,
        t.navAlben,
        t.navWerkzeuge,
        t.navEinstellungen,
      ];
  static const _destinationIconsOutlined = [
    Icons.photo_outlined,
    Icons.explore_outlined,
    Icons.calendar_today_outlined,
    Icons.map_outlined,
    Icons.luggage_outlined,
    Icons.search_outlined,
    Icons.face_outlined,
    Icons.account_tree_outlined,
    Icons.photo_album_outlined,
    Icons.build_outlined,
    Icons.settings_outlined,
  ];
  static const _destinationIconsFilled = [
    Icons.photo,
    Icons.explore,
    Icons.calendar_today,
    Icons.map,
    Icons.luggage,
    Icons.search,
    Icons.face,
    Icons.account_tree,
    Icons.photo_album,
    Icons.build,
    Icons.settings,
  ];

  /// Auf einer schmalen Fläche passen elf gleichrangige Ziele weder lesbar
  /// noch als gut treffbare Bedienelemente nebeneinander. Die vier häufigsten
  /// bleiben direkt erreichbar; alle übrigen stehen in einem echten
  /// „Mehr“-Menü. Die Zahlen sind weiterhin die Seitenindizes der einen
  /// Zielliste oben.
  static const _compactPrimaryIndices = [0, 1, 5, 8];

  Future<void> _showCommandPalette() async {
    final t = AppTexte.of(context);
    final ziel = await showSearch<int?>(
      context: context,
      delegate: _CommandPaletteDelegate(
        labels: _destinationLabels(t),
        icons: _destinationIconsOutlined,
        current: _seite.value,
        hint: t.befehlspaletteHinweis,
        empty: t.befehlspaletteLeer,
      ),
    );
    if (ziel != null && mounted) _zielGewaehlt(ziel);
  }

  Future<void> _showCompactMore(AppTexte t) async {
    final labels = _destinationLabels(t);
    final weitere = [
      for (var i = 0; i < labels.length; i++)
        if (!_compactPrimaryIndices.contains(i)) i,
    ];
    final ziel = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.manage_search_outlined),
              title: Text(t.befehlspaletteTitel),
              subtitle: Text(t.befehlspaletteHinweis),
              onTap: () => Navigator.pop(context, -1),
            ),
            const Divider(height: 1),
            for (final i in weitere)
              ListTile(
                leading: Icon(i == _seite.value
                    ? _destinationIconsFilled[i]
                    : _destinationIconsOutlined[i]),
                title: Text(labels[i]),
                selected: i == _seite.value,
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (ziel == -1 && mounted) {
      await _showCommandPalette();
    } else if (ziel != null && mounted) {
      _zielGewaehlt(ziel);
    }
  }

  /// Welches Ziel hinter ⌘1 … ⌘0 liegt – als Reihenfolge der **Ziele**,
  /// nicht der Zifferntasten.
  ///
  /// Der Unterschied wurde wichtig, als die Reisen einen eigenen
  /// Menüpunkt bekamen. Sie gehören neben die Karte, also mitten in die
  /// Reihe; hätten die Ziffern weiter an der Position geklebt, wäre
  /// jedes Kürzel ab ⌘5 auf einen anderen Bildschirm gerutscht. Die
  /// zehn Ziffern waren bereits vergeben, ein elftes Kürzel gibt es also
  /// nicht: **Die Reisen bekommen keines** – und das steht in der
  /// Kürzelübersicht, statt dass man es durch Ausprobieren herausfindet.
  static const _kuerzelZiele = [0, 1, 2, 3, 5, 6, 7, 8, 9, 10];

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed) {
      final ziffern = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
        // Das zehnte Ziel liegt auf ⌘0. Es hinten anzuhängen wäre die
        // Alternative gewesen – dann stünde der Stammbaum aber weit weg
        // von den Personen, zu denen er gehört. Lieber eine Taste, die
        // sich aus der Reihe ergibt, als eine Reihenfolge nach dem
        // Tastenfeld.
        LogicalKeyboardKey.digit0,
      ];
      // Das Nummernfeld trägt eigene Tasten. Wer es benutzt, drückt
      // dieselbe Ziffer und erwartet dasselbe – bis zur Prüfrunde vom
      // 04.09.2026 passierte dort nichts.
      const nummernfeld = [
        LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad2,
        LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad4,
        LogicalKeyboardKey.numpad5,
        LogicalKeyboardKey.numpad6,
        LogicalKeyboardKey.numpad7,
        LogicalKeyboardKey.numpad8,
        LogicalKeyboardKey.numpad9,
        LogicalKeyboardKey.numpad0,
      ];
      final digitKeys = <LogicalKeyboardKey, int>{
        for (var i = 0; i < _kuerzelZiele.length && i < ziffern.length; i++)
          ziffern[i]: _kuerzelZiele[i],
        for (var i = 0; i < _kuerzelZiele.length && i < nummernfeld.length; i++)
          nummernfeld[i]: _kuerzelZiele[i],
      };
      final target = digitKeys[event.logicalKey];
      if (target != null) {
        // Über denselben Weg wie ein Tippen in der Leiste: Das Kürzel muss
        // auch aus einer offenen Detailseite herausführen, sonst schaltet
        // es einen Bereich um, den niemand zu sehen bekommt.
        _zielGewaehlt(target);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyK) {
        _showCommandPalette();
        return KeyEventResult.handled;
      }
    }
    // event.character statt LogicalKeyboardKey.slash, damit es unabhängig
    // vom Tastaturlayout funktioniert ("?" liegt auf deutschen Tastaturen
    // z.B. auf Umschalt+ß, nicht auf Umschalt+/ wie im US-Layout).
    //
    // Die logische Taste steht als zweiter Weg daneben: Nicht jede Umgebung
    // liefert zu einem Tastendruck ein Zeichen mit (gemeldet in der
    // Prüfrunde vom 04.09.2026 – „passiert nichts, auch nicht mit
    // Umschalt+ß"). Zwei Wege zu prüfen kostet nichts; einer, der still
    // ausfällt, kostet die ganze Tafel.
    if (event.character == '?' ||
        event.logicalKey == LogicalKeyboardKey.question ||
        (HardwareKeyboard.instance.isShiftPressed &&
            // Über die Lage der Taste, nicht über ihr Zeichen: Auf der
            // deutschen Tastatur sitzt das ß dort, wo im US-Layout der
            // Bindestrich liegt – und Umschalt darauf ergibt beide Male „?".
            (event.physicalKey == PhysicalKeyboardKey.slash ||
                event.physicalKey == PhysicalKeyboardKey.minus))) {
      _showShortcutsOverview();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showShortcutsOverview() {
    showDialog<void>(
        context: context,
        builder: (context) => const _ShortcutsOverviewDialog());
  }

  @override
  void dispose() {
    _tresor.schweige();
    _seite.dispose();
    _zeitleisteNachOben.dispose();
    super.dispose();
  }

  /// Ein Tippen in der Navigation.
  ///
  /// Das Zeitleisten-Symbol tut mehr als umschalten: Es springt zu den
  /// neuesten Fotos zurück – auch dann, wenn die Zeitleiste schon offen
  /// ist und weit unten steht. Genau dafür greift man im Zweifel danach.
  /// Ein Tippen auf den Bereich, in dem man schon steht, führt zurück:
  /// Steht eine Detailseite offen, schliesst sie sich. Danach greift man,
  /// wenn man sich verlaufen hat – und vorher war es eine tote Taste.
  void _zielGewaehlt(int i) {
    if (i == 0) _zeitleisteNachOben.value++;
    if (i == _seite.value) {
      _bereich.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    // Das Aufräumen des Bereichs hängt am Notifier, nicht hier – siehe
    // [Arbeitsbereich.seite].
    _seite.value = i;
  }

  /// Baut den Hauptbereich mit der Nummer [i].
  ///
  /// Läuft im [Arbeitsbereich] und nicht mehr in der Hülle: Nur dort wird
  /// bei einer Meldung der [LibraryState] überhaupt noch neu aufgebaut.
  Widget _seiteBauen(BuildContext context, int i) {
    // "Foto in der Timeline anzeigen" (Kontextmenü der Vollbildansicht):
    // einmalig auf den Timeline-Tab wechseln und die Ziel-ID durchreichen.
    // Ein Bereichswunsch von unten (siehe [LibraryState.zeigeBereich]).
    // Vor dem Hervorheben, weil das Hervorheben selbst auf die Zeitleiste
    // schaltet – stünde es davor, überschriebe es den Wunsch.
    final wunsch = widget.library.bereichswunsch;
    if (wunsch != null && wunsch >= 0 && wunsch <= Hauptbereich.einstellungen) {
      widget.library.bereichswunschErledigt();
      i = wunsch;
      // Erst nach diesem Bild, aus demselben Grund wie beim Hervorheben
      // unten: Die Leiste liegt neben dem Bereich, nicht darin. Das
      // Aufräumen des Bereichs hängt am Notifier – siehe
      // [Arbeitsbereich.seite] –, es braucht hier keinen zweiten Weg.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seite.value = wunsch;
      });
    }

    final pendingHighlight = widget.library.timelineHighlightAssetId;
    if (pendingHighlight != null) {
      widget.library.clearTimelineHighlightRequest();
      i = 0;
      // Die Leiste erst nach diesem Bild nachziehen: Sie liegt **neben**
      // dem Bereich, nicht darin. Sie mitten im Aufbau des Bereichs für
      // ungültig zu erklären, ist genau der Fehler, den Flutter mit
      // "setState() or markNeedsBuild() called during build" meldet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _seite.value = 0;
      });
    }

    final pages = [
      TimelineScreen(
        library: widget.library,
        highlightAssetId: pendingHighlight,
        nachObenSignal: _zeitleisteNachOben,
      ),
      ExploreScreen(library: widget.library),
      CalendarScreen(library: widget.library),
      MapScreen(library: widget.library),
      ReisenScreen(library: widget.library),
      SearchScreen(library: widget.library),
      PeopleScreen(library: widget.library),
      StammbaumScreen(library: widget.library),
      AlbumsScreen(library: widget.library),
      ToolsScreen(library: widget.library),
      SettingsScreen(library: widget.library),
    ];
    return pages[i];
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    final t = AppTexte.of(context);
    final navLabels = _destinationLabels(t);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<int>(
        valueListenable: _seite,
        builder: (context, seite, _) => Scaffold(
          body: Column(
            children: [
              _RestoreQueueBanner(
                library: widget.library,
                oeffnen: () => _bereich.currentState?.push(MaterialPageRoute(
                  builder: (_) => RestoreQueueScreen(library: widget.library),
                )),
              ),
              _AnalyseBanner(library: widget.library),
              Expanded(child: LayoutBuilder(
                builder: (context, constraints) {
                  // Skaliert Icon-Größe und Abstand zwischen den 9 Einträgen mit der
                  // verfügbaren Fensterhöhe: bei einem hohen Fenster/Bildschirm
                  // stünden sie sonst winzig oben gedrängt, mit viel ungenutztem
                  // Platz darunter bis zum Import-Button. 700px ist die Bezugshöhe,
                  // ab der die Rail genau wie zuvor (Icon-Größe 24, kein Extra-
                  // Abstand) aussieht; die Obergrenze verhindert unangemessen große
                  // Icons auf sehr hohen Bildschirmen.
                  final railScale =
                      (constraints.maxHeight / 700).clamp(1.0, 1.8);
                  final railIconSize = 24.0 * railScale;
                  final railItemPadding = 10.0 * (railScale - 1.0);

                  return Row(
                    children: [
                      if (wide)
                        NavigationRail(
                          selectedIndex: seite,
                          onDestinationSelected: _zielGewaehlt,
                          // "selected" statt "all": bei 9 Einträgen würde die Rail mit
                          // Label unter jedem Icon bei normaler Fensterhöhe überlaufen.
                          labelType: NavigationRailLabelType.selected,
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image(
                                  image: const AssetImage(
                                      'assets/icon/app_icon.png'),
                                  width: 32 * railScale,
                                  height: 32 * railScale,
                                ),
                                // Name der geöffneten Bibliothek – erst, wenn es
                                // überhaupt mehr als eine gibt. Ohne diesen
                                // Hinweis ist nach einem Wechsel nicht
                                // erkennbar, worin man gerade arbeitet.
                                if (widget.library.aktiveBibliothek !=
                                    null) ...[
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    width: 72,
                                    child: Tooltip(
                                      message: t.geoeffneteBibliothek(
                                          widget.library.aktiveBibliothek!),
                                      child: Text(
                                        widget.library.aktiveBibliothek!,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          destinations: _buildDestinations(
                              t, railIconSize, railItemPadding),
                          trailing: Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.lg),
                                child: FloatingActionButton(
                                  heroTag: 'import-rail',
                                  tooltip: t.importierenTooltip,
                                  onPressed: () =>
                                      showImportSheet(context, widget.library),
                                  child: const Icon(
                                      Icons.add_photo_alternate_outlined),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (wide) const VerticalDivider(width: 1),
                      // Der eigentliche Umbau: Die Seite liegt in einem
                      // eigenen Navigator, damit alles, was von ihr aus
                      // geöffnet wird, **neben** der Leiste steht statt
                      // über ihr. Wer die ganze Fläche will, schiebt auf
                      // den Navigator des Fensters – siehe [Arbeitsbereich].
                      Expanded(
                        child: Arbeitsbereich(
                          seite: _seite,
                          auchBei: widget.library,
                          navigatorSchluessel: _bereich,
                          bauen: _seiteBauen,
                        ),
                      ),
                    ],
                  );
                },
              )),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _compactPrimaryIndices.contains(seite)
                      ? _compactPrimaryIndices.indexOf(seite)
                      : _compactPrimaryIndices.length,
                  onDestinationSelected: (index) {
                    if (index < _compactPrimaryIndices.length) {
                      _zielGewaehlt(_compactPrimaryIndices[index]);
                    } else {
                      _showCompactMore(t);
                    }
                  },
                  destinations: [
                    for (final i in _compactPrimaryIndices)
                      NavigationDestination(
                        icon: Icon(_destinationIconsOutlined[i]),
                        selectedIcon: Icon(_destinationIconsFilled[i]),
                        label: navLabels[i],
                      ),
                    NavigationDestination(
                      icon: const Icon(Icons.more_horiz),
                      selectedIcon: const Icon(Icons.more),
                      label: t.allgMehr,
                    ),
                  ],
                ),
          floatingActionButton: wide
              ? null
              : FloatingActionButton(
                  heroTag: 'import-bottom',
                  onPressed: () => showImportSheet(context, widget.library),
                  child: const Icon(Icons.add_photo_alternate_outlined),
                ),
        ),
      ),
    );
  }
}

class _CommandPaletteDelegate extends SearchDelegate<int?> {
  _CommandPaletteDelegate({
    required this.labels,
    required this.icons,
    required this.current,
    required String hint,
    required this.empty,
  }) : super(searchFieldLabel: hint);

  final List<String> labels;
  final List<IconData> icons;
  final int current;
  final String empty;

  List<int> get _matches {
    final needle = query.trim().toLowerCase();
    return [
      for (var i = 0; i < labels.length; i++)
        if (needle.isEmpty || labels[i].toLowerCase().contains(needle)) i,
    ];
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            onPressed: () => query = '',
            icon: const Icon(Icons.clear),
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => BackButton(
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final matches = _matches;
    if (matches.isEmpty) return Center(child: Text(empty));
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final i = matches[index];
        return ListTile(
          leading: Icon(icons[i]),
          title: Text(labels[i]),
          selected: i == current,
          onTap: () => close(context, i),
        );
      },
    );
  }
}

/// Das Fenster hinter „?" (siehe [_HomeShellState._handleKeyEvent]).
///
/// Die Tafel selbst steht in [Tastenkuerzeltafel] – sie hängt seit der
/// 19. Prüfrunde auch in den Einstellungen, weil „?" nirgends genannt wurde.
class _ShortcutsOverviewDialog extends StatelessWidget {
  const _ShortcutsOverviewDialog();

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.kuerzelTitel),
      content: const SizedBox(
        width: 460,
        child: SingleChildScrollView(child: Tastenkuerzeltafel()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.allgSchliessen)),
      ],
    );
  }
}

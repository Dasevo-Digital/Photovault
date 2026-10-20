import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';
import 'package:zierbild/bibliothek_eintraege.dart';

import '../l10n/app_localizations.dart';
import '../services/groessentext.dart';
import '../utils/dauertext.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/arbeitsbereich.dart';
import '../widgets/seitenleiste.dart';
import '../widgets/tastenkuerzel.dart';
import 'albums_screen.dart';
import 'calendar_screen.dart';
import 'duplicates_screen.dart';
import 'explore_screen.dart';
import 'import_progress_sheet.dart';
import 'laenderliste_screen.dart';
import 'map_screen.dart';
import 'people_screen.dart';
import '../services/restore_queue_service.dart';
import '../services/tresor_waechter.dart';
import 'restore_queue_screen.dart';
import 'reisen_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'stammbaum_screen.dart';
import 'statistics_screen.dart';
import 'timeline_screen.dart';
import 'tools_screen.dart';
import 'trash_screen.dart';

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
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
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
  const _Laufzeile({
    required this.anteil,
    required this.text,
    required this.abbrechen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, value: anteil),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
    // Die Zahlen zählen über [LibraryState.fortschritt] weiter, ohne dass
    // dafür die ganze App neu aufgebaut wird.
    return ListenableBuilder(
      listenable: library.fortschritt,
      builder: (context, _) => _baue(context),
    );
  }

  Widget _baue(BuildContext context) {
    final t = AppTexte.of(context);
    final a = library.analyse;
    final laeufe = library.laufendeAufgaben.toList();
    // Im verbundenen Betrieb nur, wenn etwas zu sagen ist: Ein Gerät, das
    // abgleicht, soll nicht bei jedem Stern eine Zeile aufblitzen lassen.
    final z = library.verbunden ? library.abgleichszustand : null;
    final server = z == null
        ? null
        : z.schemaAnders
        ? (z.appZuAlt ? t.serverAppZuAlt : t.serverZuAlt)
        : z.abgemeldet
        ? t.serverAbgemeldet
        : !z.erreichbar && !z.ungeklaert
        ? t.serverOffline(z.ausstehend)
        : null;
    final sp = library.verbunden ? library.serverspeicher : null;
    final speicher = sp == null
        ? null
        : sp.voll
        ? t.serverSpeicherVoll
        : sp.knapp
        ? t.serverSpeicherKnapp(groessentext(sp.frei ?? 0))
        : null;
    final sicherung =
        library.verbunden && (library.serversicherung?.warnt ?? false)
        ? t.serverSicherungWarnung
        : null;
    if (a == null &&
        laeufe.isEmpty &&
        server == null &&
        speicher == null &&
        sicherung == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (server != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(server),
            ),
          if (sicherung != null)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.backup_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(sicherung),
            ),
          if (speicher != null)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.storage_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(speicher),
            ),
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

/// Die Nummern der Hauptbereiche – dieselbe Reihenfolge wie
/// [_HomeShellState._gruppen], und die ist die eine Quelle der Wahrheit
/// dafür. Gegliedert wie im Browser und auf dem Handy: oben Fotos, Suche,
/// Alben, darunter „Entdecken“ und „Verwalten“. Rückblick, Kalender und
/// Werkzeuge gibt es nur hier als eigenen Bereich.
///
/// Sie stehen hier, weil ein Bildschirm tief im Arbeitsbereich über
/// [LibraryState.zeigeBereich] dorthin schicken können muss und eine nackte
/// `6` an jener Stelle niemandem sagt, wohin.
abstract final class Hauptbereich {
  static const zeitleiste = 0;
  static const suche = 1;
  static const alben = 2;
  static const favoriten = 3;
  static const personen = 4;
  static const karte = 5;
  static const orte = 6;
  static const reisen = 7;
  static const stammbaum = 8;
  static const statistik = 9;
  static const rueckblick = 10;
  static const kalender = 11;
  static const duplikate = 12;
  static const papierkorb = 13;
  static const werkzeuge = 14;
  static const einstellungen = 15;

  /// Die ersten drei stehen am schmalen Fenster unten als Reiter; der
  /// Rest liegt dort im Blatt „Bibliothek“.
  static const reiter = 3;
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
  late final Tresorwaechter _tresor = Tresorwaechter(
    widget.library.sperreTresor,
  )..horche();

  /// Zähler, den das Zeitleisten-Symbol hochzählt. Die Zeitleiste springt
  /// bei jeder Änderung zu den neuesten Fotos.
  ///
  /// Ein Zähler statt eines Schalters: Zweimal tippen muss zweimal
  /// wirken, auch wenn man zwischendurch nichts anderes getan hat.
  final ValueNotifier<int> _zeitleisteNachOben = ValueNotifier(0);

  /// Wieder im Vordergrund (etwa nach dem Ruhezustand): verbunden gleich
  /// beim Server nachfragen, statt die abgerissene wartende Abfrage
  /// auslaufen zu lassen – wie die Handy-App.
  late final AppLifecycleListener _lebenslauf = AppLifecycleListener(
    onResume: () => widget.library.abgleich?.jetzt(),
  );

  /// Ob die Seitenleiste offen bleibt – siehe [Seitenleiste]. Gemerkt
  /// über [Leistenmerker]; bis die Datei gelesen ist, zugeklappt.
  bool _fixiert = false;

  @override
  void initState() {
    super.initState();
    _lebenslauf;
    Leistenmerker.lies().then((f) {
      if (mounted && f != _fixiert) setState(() => _fixiert = f);
    });
  }

  void _fixieren(bool fixiert) {
    setState(() => _fixiert = fixiert);
    Leistenmerker.schreibe(fixiert);
  }

  /// Alle Ziele in Gruppen – Reihenfolge = Nummer in [Hauptbereich] =
  /// ⌘1…⌘9 (siehe [_kuerzelZiele]) = Reihenfolge in der Befehlspalette.
  /// Farben und Symbole teilen sich Rechner, Handy und Browser
  /// ([Bibliotheksfarben]).
  static List<Leistengruppe> _gruppen(AppTexte t) => [
    Leistengruppe(
      eintraege: [
        Leisteneintrag(
          text: t.navFotos,
          icon: Bibliothekssymbole.fotos,
          iconGewaehlt: Bibliothekssymbole.fotosGewaehlt,
        ),
        Leisteneintrag(text: t.navSuche, icon: Bibliothekssymbole.suche),
        Leisteneintrag(
          text: t.navAlben,
          icon: Bibliothekssymbole.alben,
          iconGewaehlt: Bibliothekssymbole.albenGewaehlt,
        ),
      ],
    ),
    Leistengruppe(
      titel: t.navGruppeEntdecken,
      eintraege: [
        Leisteneintrag(
          text: t.navFavoriten,
          icon: Bibliothekssymbole.favoriten,
          farbe: Bibliotheksfarben.favoriten,
        ),
        Leisteneintrag(
          text: t.navPersonen,
          icon: Bibliothekssymbole.personen,
          farbe: Bibliotheksfarben.personen,
        ),
        Leisteneintrag(
          text: t.navKarte,
          icon: Bibliothekssymbole.karte,
          farbe: Bibliotheksfarben.karte,
        ),
        Leisteneintrag(
          text: t.navOrte,
          icon: Bibliothekssymbole.orte,
          farbe: Bibliotheksfarben.orte,
        ),
        Leisteneintrag(
          text: t.navReisen,
          icon: Bibliothekssymbole.reisen,
          farbe: Bibliotheksfarben.reisen,
        ),
        Leisteneintrag(
          text: t.navStammbaum,
          icon: Bibliothekssymbole.stammbaum,
          farbe: Bibliotheksfarben.stammbaum,
        ),
        Leisteneintrag(
          text: t.navStatistik,
          icon: Bibliothekssymbole.statistik,
          farbe: Bibliotheksfarben.statistik,
        ),
        Leisteneintrag(
          text: t.navRueckblick,
          icon: Bibliothekssymbole.rueckblick,
          farbe: Bibliotheksfarben.rueckblick,
        ),
        Leisteneintrag(
          text: t.navKalender,
          icon: Bibliothekssymbole.kalender,
          farbe: Bibliotheksfarben.kalender,
        ),
      ],
    ),
    Leistengruppe(
      titel: t.navGruppeVerwalten,
      eintraege: [
        Leisteneintrag(
          text: t.navDuplikate,
          icon: Bibliothekssymbole.duplikate,
          farbe: Bibliotheksfarben.duplikate,
        ),
        Leisteneintrag(
          text: t.navPapierkorb,
          icon: Bibliothekssymbole.papierkorb,
          farbe: Bibliotheksfarben.papierkorb,
        ),
        Leisteneintrag(
          text: t.navWerkzeuge,
          icon: Bibliothekssymbole.werkzeuge,
          farbe: Bibliotheksfarben.werkzeuge,
        ),
        Leisteneintrag(
          text: t.navEinstellungen,
          icon: Bibliothekssymbole.einstellungen,
          farbe: Bibliotheksfarben.einstellungen,
        ),
      ],
    ),
  ];

  static List<Leisteneintrag> _ziele(AppTexte t) => [
    for (final g in _gruppen(t)) ...g.eintraege,
  ];

  Future<void> _showCommandPalette() async {
    final t = AppTexte.of(context);
    final ziel = await showSearch<int?>(
      context: context,
      delegate: _CommandPaletteDelegate(
        ziele: _ziele(t),
        current: _seite.value,
        hint: t.befehlspaletteHinweis,
        empty: t.befehlspaletteLeer,
      ),
    );
    if (ziel != null && mounted) _zielGewaehlt(ziel);
  }

  /// „Bibliothek“ am schmalen Fenster: was nicht unten als Reiter steht,
  /// in denselben Gruppen und Farben wie in der Leiste – und darüber die
  /// Befehlspalette, die dort sonst nur über ⌘K zu finden wäre.
  Future<void> _zeigeBibliothek(AppTexte t) async {
    final ziel = await zeigeBibliotheksblatt(
      context,
      gruppen: _gruppen(t).skip(1).toList(),
      ersteNummer: Hauptbereich.reiter,
      gewaehlt: _seite.value,
      kopf: Builder(
        builder: (context) => ListTile(
          leading: const Icon(Icons.manage_search_outlined),
          title: Text(t.befehlspaletteTitel),
          subtitle: Text(t.befehlspaletteHinweis),
          onTap: () => Navigator.pop(context, -1),
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
  /// Die Ziffern folgen der Leiste von oben, so wie man sie sieht: ⌘1
  /// Fotos bis ⌘9 Stammbaum. ⌘0 bleibt bei den Einstellungen, wo es seit
  /// jeher lag und wo es die meisten Programme haben. Was dazwischen
  /// liegt, erreicht man über ⌘K – und das steht in der Kürzelübersicht.
  static const _kuerzelZiele = [0, 1, 2, 3, 4, 5, 6, 7, 8, 15];

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
      builder: (context) => const _ShortcutsOverviewDialog(),
    );
  }

  @override
  void dispose() {
    _tresor.schweige();
    _lebenslauf.dispose();
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

    final t = AppTexte.of(context);
    final l = widget.library;
    final pages = [
      TimelineScreen(
        library: l,
        highlightAssetId: pendingHighlight,
        nachObenSignal: _zeitleisteNachOben,
      ),
      SearchScreen(library: l),
      AlbumsScreen(library: l),
      // Wie im Browser: die Favoriten als Suche mit gesetztem Filter – man
      // kann darin weitersuchen.
      SearchScreen(
        library: l,
        startFilter: const SearchFilters(favoritesOnly: true),
        titel: t.navFavoriten,
      ),
      PeopleScreen(library: l),
      MapScreen(library: l),
      LaenderlisteScreen(library: l),
      ReisenScreen(library: l),
      StammbaumScreen(library: l),
      StatisticsScreen(library: l),
      ExploreScreen(library: l),
      CalendarScreen(library: l),
      DuplicatesScreen(library: l),
      TrashScreen(library: l),
      ToolsScreen(library: l),
      SettingsScreen(library: l),
    ];
    // Die Nummer als Schlüssel: Suche und Favoriten sind derselbe
    // Bildschirm und teilten sich sonst beim Wechsel ihren Zustand.
    return KeyedSubtree(key: ValueKey(i), child: pages[i]);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    final t = AppTexte.of(context);
    final ziele = _ziele(t);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: ValueListenableBuilder<int>(
        valueListenable: _seite,
        builder: (context, seite, _) {
          // Der eigentliche Umbau: Die Seite liegt in einem eigenen
          // Navigator, damit alles, was von ihr aus geöffnet wird,
          // **neben** der Leiste steht statt über ihr. Wer die ganze Fläche
          // will, schiebt auf den Navigator des Fensters – siehe
          // [Arbeitsbereich].
          final bereich = Arbeitsbereich(
            seite: _seite,
            auchBei: widget.library,
            navigatorSchluessel: _bereich,
            bauen: _seiteBauen,
          );
          final bibliothek = widget.library.aktiveBibliothek;
          return Scaffold(
            body: Column(
              children: [
                _RestoreQueueBanner(
                  library: widget.library,
                  oeffnen: () => _bereich.currentState?.push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RestoreQueueScreen(library: widget.library),
                    ),
                  ),
                ),
                _AnalyseBanner(library: widget.library),
                Expanded(
                  child: !wide
                      ? bereich
                      : Seitenleiste(
                          gruppen: _gruppen(t),
                          gewaehlt: seite,
                          beiWahl: _zielGewaehlt,
                          fixiert: _fixiert,
                          beiFixieren: _fixieren,
                          marke: const Image(
                            image: AssetImage('assets/icon/app_icon.png'),
                          ),
                          markeText: 'Photo Vault',
                          // Name der geöffneten Bibliothek – erst, wenn es
                          // überhaupt mehr als eine gibt. Ohne diesen
                          // Hinweis ist nach einem Wechsel nicht
                          // erkennbar, worin man gerade arbeitet.
                          unterzeile: bibliothek,
                          unterzeileHinweis: bibliothek == null
                              ? null
                              : t.geoeffneteBibliothek(bibliothek),
                          fuss: [
                            Leistenknopf(
                              text: t.navImportieren,
                              icon: Icons.add_photo_alternate_outlined,
                              beiTippen: () =>
                                  showImportSheet(context, widget.library),
                            ),
                          ],
                          fixierenText: t.navLeisteFixieren,
                          loesenText: t.navLeisteLoesen,
                          inhalt: bereich,
                        ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: math.min(seite, Hauptbereich.reiter),
                    onDestinationSelected: (index) {
                      if (index < Hauptbereich.reiter) {
                        _zielGewaehlt(index);
                      } else {
                        _zeigeBibliothek(t);
                      }
                    },
                    destinations: [
                      for (final z in ziele.take(Hauptbereich.reiter))
                        NavigationDestination(
                          icon: Icon(z.icon),
                          selectedIcon: Icon(z.iconGewaehlt ?? z.icon),
                          label: z.text,
                        ),
                      NavigationDestination(
                        icon: const Icon(Bibliothekssymbole.bibliothek),
                        selectedIcon: const Icon(
                          Bibliothekssymbole.bibliothekGewaehlt,
                        ),
                        label: t.navBibliothek,
                      ),
                    ],
                  ),
            floatingActionButton: wide
                ? null
                : FloatingActionButton(
                    heroTag: 'import-bottom',
                    tooltip: t.importierenTooltip,
                    onPressed: () => showImportSheet(context, widget.library),
                    child: const Icon(Icons.add_photo_alternate_outlined),
                  ),
          );
        },
      ),
    );
  }
}

class _CommandPaletteDelegate extends SearchDelegate<int?> {
  _CommandPaletteDelegate({
    required this.ziele,
    required this.current,
    required String hint,
    required this.empty,
  }) : super(searchFieldLabel: hint);

  final List<Leisteneintrag> ziele;
  final int current;
  final String empty;

  List<int> get _matches {
    final needle = query.trim().toLowerCase();
    return [
      for (var i = 0; i < ziele.length; i++)
        if (needle.isEmpty || ziele[i].text.toLowerCase().contains(needle)) i,
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
  Widget buildLeading(BuildContext context) =>
      BackButton(onPressed: () => close(context, null));

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
        final z = ziele[i];
        return ListTile(
          leading: z.farbe == null
              ? Icon(z.icon)
              : Farbsymbol(icon: z.icon, farbe: z.farbe!, groesse: 32),
          title: Text(z.text),
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
          child: Text(t.allgSchliessen),
        ),
      ],
    );
  }
}

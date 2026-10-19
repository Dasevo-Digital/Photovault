import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zierbild/bibliothek_eintraege.dart';

import '../services/library_location.dart';

/// Ein Ziel der [Seitenleiste].
class Leisteneintrag {
  const Leisteneintrag({
    required this.text,
    required this.icon,
    this.iconGewaehlt,
    this.farbe,
  });

  final String text;
  final IconData icon;
  final IconData? iconGewaehlt;

  /// Die Farbe des Felds unter dem Symbol, wie in der Bibliothek von
  /// Browser und Handy. Ohne steht das Symbol schlicht da – so die
  /// Hauptbereiche oben.
  final Color? farbe;
}

/// Eine Gruppe von Zielen; die erste ohne [titel] sind die Hauptbereiche.
class Leistengruppe {
  const Leistengruppe({this.titel, required this.eintraege});

  final String? titel;
  final List<Leisteneintrag> eintraege;
}

/// Die Seitenleiste am breiten Fenster – dieselbe wie im Browser
/// (packages/server/web/app.css, `#nav`): sonst eine schmale Spalte aus
/// Symbolen, die sich öffnet, sobald die Maus darauf kommt (oder ein
/// Eintrag den Fokus hat), und sich dabei **über** den Inhalt legt, ohne
/// ihn zu verschieben. Die Pinnnadel unten hält sie offen; dann rückt der
/// Inhalt zur Seite.
///
/// Die Nummer eines Ziels ist seine Stelle über alle [gruppen] hinweg.
class Seitenleiste extends StatefulWidget {
  const Seitenleiste({
    super.key,
    required this.gruppen,
    required this.gewaehlt,
    required this.beiWahl,
    required this.fixiert,
    required this.beiFixieren,
    required this.marke,
    required this.markeText,
    required this.fixierenText,
    required this.loesenText,
    required this.inhalt,
    this.unterzeile,
    this.unterzeileHinweis,
    this.fuss = const [],
  });

  static const schmal = 68.0;
  static const offen = 248.0;

  final List<Leistengruppe> gruppen;
  final int gewaehlt;
  final ValueChanged<int> beiWahl;
  final bool fixiert;
  final ValueChanged<bool> beiFixieren;

  /// Das Bild oben links und der Name daneben; ein Tippen führt zum
  /// ersten Ziel.
  final Widget marke;
  final String markeText;

  /// Klein unter dem Namen, etwa die geöffnete Bibliothek.
  final String? unterzeile;
  final String? unterzeileHinweis;

  /// Knöpfe über der Pinnnadel (am Rechner: Importieren).
  final List<Leistenknopf> fuss;

  final String fixierenText;
  final String loesenText;

  /// Die Fläche neben der Leiste. Sie bleibt beim An- und Abpinnen an
  /// derselben Stelle im Baum – sonst ginge ihr Zustand (der Navigator des
  /// Arbeitsbereichs) mit jedem Klick auf die Nadel verloren.
  final Widget inhalt;

  @override
  State<Seitenleiste> createState() => _SeitenleisteState();
}

/// Ein Knopf unten in der Leiste, der kein Ziel ist.
class Leistenknopf {
  const Leistenknopf({
    required this.text,
    required this.icon,
    required this.beiTippen,
  });

  final String text;
  final IconData icon;
  final VoidCallback beiTippen;
}

class _SeitenleisteState extends State<Seitenleiste> {
  var _maus = false;
  var _fokus = false;
  var _offen = false;
  Timer? _uhr;

  /// Wie im Browser: Öffnen kaum verzögert, damit ein Streifen mit der
  /// Maus nicht gleich aufklappt; Schliessen mit einer Viertelsekunde
  /// Nachsicht, damit ein kurzer Ausrutscher nicht alles zuklappt.
  void _pruefe() {
    final soll = _maus || _fokus;
    _uhr?.cancel();
    if (soll == _offen) return;
    _uhr = Timer(
      Duration(milliseconds: soll ? 60 : 250),
      () => mounted ? setState(() => _offen = soll) : null,
    );
  }

  @override
  void didUpdateWidget(Seitenleiste alt) {
    super.didUpdateWidget(alt);
    // Gelöst: gleich zuklappen, nicht erst, wenn die Maus geht.
    if (alt.fixiert && !widget.fixiert) {
      _uhr?.cancel();
      _maus = false;
      _offen = false;
    }
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aufgeklappt = widget.fixiert || _offen;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          left: widget.fixiert ? Seitenleiste.offen : Seitenleiste.schmal,
          top: 0,
          right: 0,
          bottom: 0,
          child: widget.inhalt,
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            onEnter: (_) {
              _maus = true;
              _pruefe();
            },
            onExit: (_) {
              _maus = false;
              _pruefe();
            },
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (f) {
                _fokus = f;
                _pruefe();
              },
              child: _leiste(context, aufgeklappt),
            ),
          ),
        ),
      ],
    );
  }

  Widget _leiste(BuildContext context, bool aufgeklappt) {
    final farben = Theme.of(context).colorScheme;
    final ueberInhalt = aufgeklappt && !widget.fixiert;
    var nummer = 0;
    final gruppen = <Widget>[];
    for (final g in widget.gruppen) {
      final eintraege = <Widget>[];
      for (final e in g.eintraege) {
        final i = nummer++;
        eintraege.add(
          _Zeile(
            eintrag: e,
            gewaehlt: i == widget.gewaehlt,
            aufgeklappt: aufgeklappt,
            beiTippen: () => widget.beiWahl(i),
          ),
        );
      }
      gruppen.add(
        g.titel == null
            ? Column(children: eintraege)
            : _Gruppe(
                titel: g.titel!,
                aufgeklappt: aufgeklappt,
                children: eintraege,
              ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: aufgeklappt ? Seitenleiste.offen : Seitenleiste.schmal,
      decoration: BoxDecoration(
        // Wie `--karte` im Browser: eine Spur heller als der Grund – hell
        // weiss, dunkel die erste Stufe über dem Hintergrund.
        color: Theme.of(context).brightness == Brightness.dark
            ? farben.surfaceContainerLow
            : farben.surfaceContainerLowest,
        border: Border(right: BorderSide(color: farben.outlineVariant)),
        boxShadow: [
          if (ueberInhalt)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(6, 0),
            ),
        ],
      ),
      // Der Inhalt hat immer die volle Breite und wird nur beschnitten:
      // So stehen die Symbole in beiden Zuständen an derselben Stelle, und
      // beim Öffnen springt nichts.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: Seitenleiste.offen - 1,
          maxWidth: Seitenleiste.offen - 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Marke(
                  bild: widget.marke,
                  text: widget.markeText,
                  unterzeile: widget.unterzeile,
                  unterzeileHinweis: widget.unterzeileHinweis,
                  aufgeklappt: aufgeklappt,
                  beiTippen: () => widget.beiWahl(0),
                ),
                // Der Rechner hat drei Bereiche mehr als Browser und
                // Handy, darum die Zeilen etwas flacher als dort (4 statt 7
                // Punkt); was dann noch nicht ins Fenster passt, rollt.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(children: gruppen),
                  ),
                ),
                const SizedBox(height: 12),
                for (final k in widget.fuss)
                  _Zeile(
                    eintrag: Leisteneintrag(text: k.text, icon: k.icon),
                    betont: true,
                    gewaehlt: false,
                    aufgeklappt: aufgeklappt,
                    beiTippen: k.beiTippen,
                  ),
                _Nadel(
                  fixiert: widget.fixiert,
                  text: widget.fixiert
                      ? widget.loesenText
                      : widget.fixierenText,
                  aufgeklappt: aufgeklappt,
                  beiTippen: () => widget.beiFixieren(!widget.fixiert),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blendet den Text ein, sobald die Leiste offen ist – mit etwas
/// Verzögerung beim Öffnen, damit er nicht in die wachsende Leiste
/// hineingequetscht erscheint. Für Vorleser bleibt er immer da.
class _Blende extends StatelessWidget {
  const _Blende({required this.sichtbar, required this.child});

  final bool sichtbar;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: sichtbar ? 1 : 0,
    duration: const Duration(milliseconds: 120),
    alwaysIncludeSemantics: true,
    child: child,
  );
}

class _Marke extends StatelessWidget {
  const _Marke({
    required this.bild,
    required this.text,
    required this.unterzeile,
    required this.unterzeileHinweis,
    required this.aufgeklappt,
    required this.beiTippen,
  });

  final Widget bild;
  final String text;
  final String? unterzeile;
  final String? unterzeileHinweis;
  final bool aufgeklappt;
  final VoidCallback beiTippen;

  @override
  Widget build(BuildContext context) {
    final thema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: beiTippen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
          child: Row(
            children: [
              SizedBox(width: 30, height: 30, child: bild),
              const SizedBox(width: 12),
              Expanded(
                child: _Blende(
                  sichtbar: aufgeklappt,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: thema.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (unterzeile != null)
                        Tooltip(
                          message: unterzeileHinweis ?? unterzeile!,
                          child: Text(
                            unterzeile!,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: thema.textTheme.labelSmall?.copyWith(
                              color: thema.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// „Entdecken“, „Verwalten“: Überschrift in Versalien, zugeklappt statt
/// ihrer eine feine Linie, damit die Gruppen auch dann getrennt bleiben.
class _Gruppe extends StatelessWidget {
  const _Gruppe({
    required this.titel,
    required this.aufgeklappt,
    required this.children,
  });

  final String titel;
  final bool aufgeklappt;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: aufgeklappt ? Colors.transparent : farben.outlineVariant,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: _Blende(
              sichtbar: aufgeklappt,
              child: Text(
                titel.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                  color: farben.onSurfaceVariant,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.eintrag,
    required this.gewaehlt,
    required this.aufgeklappt,
    required this.beiTippen,
    this.betont = false,
  });

  final Leisteneintrag eintrag;
  final bool gewaehlt;
  final bool aufgeklappt;
  final VoidCallback beiTippen;

  /// Der Knopf zum Importieren: das Symbol auf vollem Akzent.
  final bool betont;

  @override
  Widget build(BuildContext context) {
    final thema = Theme.of(context);
    final farben = thema.colorScheme;
    final farbe = eintrag.farbe;
    final Widget symbol = betont
        ? Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: farben.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(eintrag.icon, size: 19, color: farben.onPrimary),
          )
        : farbe != null
        ? Farbsymbol(icon: eintrag.icon, farbe: farbe, groesse: 32)
        : SizedBox(
            width: 32,
            child: Icon(
              gewaehlt ? (eintrag.iconGewaehlt ?? eintrag.icon) : eintrag.icon,
              size: 22,
              color: gewaehlt ? farben.primary : farben.onSurfaceVariant,
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: gewaehlt,
        button: true,
        child: Material(
          color: gewaehlt
              ? farben.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: beiTippen,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  symbol,
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Blende(
                      sichtbar: aufgeklappt,
                      child: Text(
                        eintrag.text,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: thema.textTheme.bodyMedium?.copyWith(
                          fontWeight: gewaehlt
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Pinnnadel: schräg, solange die Leiste nur auf Zeit aufgeht; gerade
/// und im Akzent, wenn sie offen bleibt.
class _Nadel extends StatelessWidget {
  const _Nadel({
    required this.fixiert,
    required this.text,
    required this.aufgeklappt,
    required this.beiTippen,
  });

  final bool fixiert;
  final String text;
  final bool aufgeklappt;
  final VoidCallback beiTippen;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Semantics(
      toggled: fixiert,
      child: InkWell(
        onTap: beiTippen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                child: AnimatedRotation(
                  turns: fixiert ? 0 : 35 / 360,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    fixiert ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 20,
                    color: fixiert ? farben.primary : farben.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Blende(
                  sichtbar: aufgeklappt,
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: fixiert ? null : farben.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Merkt sich die Pinnnadel über das Programmende hinaus – wie der Browser
/// in `localStorage` (`pv-nav-fixiert`), hier als kleine Datei im
/// Datenordner der App. Eine Kleinigkeit: Was nicht zu lesen oder zu
/// schreiben ist, bleibt beim Zuklappen und wird nicht gemeldet.
abstract final class Leistenmerker {
  static const _datei = 'seitenleiste_fixiert';

  static Future<bool> lies() async {
    try {
      final ordner = await LibraryLocation.datenordner();
      final f = File('${ordner.path}${Platform.pathSeparator}$_datei');
      return await f.exists() && (await f.readAsString()).trim() == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> schreibe(bool fixiert) async {
    try {
      final ordner = await LibraryLocation.datenordner();
      await File(
        '${ordner.path}${Platform.pathSeparator}$_datei',
      ).writeAsString(fixiert ? '1' : '0', flush: true);
    } catch (_) {}
  }
}

/// Die Bibliothek als Blatt am schmalen Fenster – wie die Bibliotheksseite
/// in Browser und Handy: die Gruppen mit ihren Farben.
Future<int?> zeigeBibliotheksblatt(
  BuildContext context, {
  required List<Leistengruppe> gruppen,
  required int ersteNummer,
  required int gewaehlt,
  required Widget kopf,
}) {
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final thema = Theme.of(context);
      var nummer = ersteNummer;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(240, MediaQuery.sizeOf(context).height * 0.8),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                kopf,
                for (final g in gruppen) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(
                      g.titel ?? '',
                      style: thema.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final e in g.eintraege)
                    () {
                      final i = nummer++;
                      return ListTile(
                        leading: e.farbe == null
                            ? Icon(e.icon)
                            : Farbsymbol(
                                icon: e.icon,
                                farbe: e.farbe!,
                                groesse: 32,
                              ),
                        title: Text(e.text),
                        selected: i == gewaehlt,
                        onTap: () => Navigator.pop(context, i),
                      );
                    }(),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

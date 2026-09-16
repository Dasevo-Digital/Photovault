import 'package:flutter/material.dart';

/// Die Fläche neben der Menüleiste – mit einem **eigenen Navigator**.
///
/// Darin liegt der ganze Zweck dieses Widgets. `Navigator.push` sucht sich
/// den nächstgelegenen Navigator; gibt es hier keinen, ist das der des
/// ganzen Fensters, und jeder geöffnete Unterbildschirm legt sich über
/// alles – auch über die Menüleiste. Mit diesem Navigator bleibt die
/// Leiste stehen, und der Unterbildschirm füllt nur die Fläche daneben.
///
/// Wer die ganze Fläche braucht – die Vollbildansicht eines Fotos, das
/// Entwickeln, der 3D-Flug –, schiebt ausdrücklich auf den Navigator des
/// Fensters: `Navigator.of(context, rootNavigator: true).push(...)`.
/// Das ist die einzige Stelle, an der ein Bildschirm sagt „ich will alles".
class Arbeitsbereich extends StatefulWidget {
  /// Welcher Hauptbereich gezeigt wird.
  ///
  /// Ein Wechsel räumt auf, was hier offen steht. Ohne das stünde man nach
  /// dem Tippen auf „Alben" weiter in der Detailseite, die vorher offen
  /// war – die Leiste zeigte einen Bereich an, den man gar nicht sähe.
  /// Dasselbe Ziel noch einmal zu wählen führt deshalb zurück zur
  /// Übersicht; genau danach greift man, wenn man sich verlaufen hat.
  final ValueNotifier<int> seite;

  /// Eine zweite Quelle, auf die der Bereich neu aufbaut.
  ///
  /// Notwendig, nicht bequem: Das Blatt eines Navigators baut **nicht**
  /// neu auf, wenn ein Vorfahre neu aufbaut – die Seite hing bisher am
  /// Neuaufbau der Hülle. Ohne dieses Horchen bliebe sie auf dem Stand
  /// des ersten Aufbaus stehen.
  final Listenable? auchBei;

  /// Baut den Hauptbereich zur gegebenen Nummer.
  final Widget Function(BuildContext kontext, int seite) bauen;

  /// Der Navigator dieses Bereichs, für Aufrufer **ausserhalb** davon.
  ///
  /// Die Hinweisbänder über der Leiste liegen über dem Bereich, nicht
  /// darin; ihr `Navigator.of(context)` fände sonst das Fenster und
  /// verdeckte die Leiste, die dieses Widget gerade sichtbar hält.
  final GlobalKey<NavigatorState>? navigatorSchluessel;

  const Arbeitsbereich({
    super.key,
    required this.seite,
    required this.bauen,
    this.auchBei,
    this.navigatorSchluessel,
  });

  @override
  State<Arbeitsbereich> createState() => _ArbeitsbereichState();
}

class _ArbeitsbereichState extends State<Arbeitsbereich> {
  late final GlobalKey<NavigatorState> _nav =
      widget.navigatorSchluessel ?? GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.seite.addListener(_zurueckZurUebersicht);
  }

  @override
  void didUpdateWidget(covariant Arbeitsbereich alt) {
    super.didUpdateWidget(alt);
    if (alt.seite != widget.seite) {
      alt.seite.removeListener(_zurueckZurUebersicht);
      widget.seite.addListener(_zurueckZurUebersicht);
    }
  }

  @override
  void dispose() {
    widget.seite.removeListener(_zurueckZurUebersicht);
    super.dispose();
  }

  void _zurueckZurUebersicht() =>
      _nav.currentState?.popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _nav,
      onGenerateRoute: (einstellungen) => MaterialPageRoute<void>(
        settings: einstellungen,
        builder: (kontext) => ListenableBuilder(
          listenable: Listenable.merge([widget.seite, widget.auchBei]),
          builder: (kontext, _) => widget.bauen(kontext, widget.seite.value),
        ),
      ),
    );
  }
}

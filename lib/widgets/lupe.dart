import 'package:flutter/material.dart';

/// Wie stark die Lupe vergrössert.
const lupenVergroesserung = 3.0;

/// Der Durchmesser der Lupe in Punkten.
const lupenDurchmesser = 180.0;

/// Eine Lupe über [child]: Solange [aktiv] ist, folgt ein runder
/// Ausschnitt in [lupenVergroesserung]-facher Grösse dem Zeiger – mit der
/// Maus beim Darüberfahren, mit Finger oder Stift beim Ziehen.
///
/// **Vergrössert wird, was schon gezeichnet ist.** Die Lupe liest die
/// Bildpunkte unter sich, nicht die Originaldatei. Bei der Vorschau beim
/// Entwickeln ist das die Vorschau in Bildschirmauflösung; für ein Urteil
/// über Schärfe und Rauschen in einem Ausschnitt reicht das, für einzelne
/// Pixel der Kamera nicht.
class Lupenbereich extends StatefulWidget {
  final bool aktiv;
  final Widget child;

  const Lupenbereich({super.key, required this.aktiv, required this.child});

  @override
  State<Lupenbereich> createState() => _LupenbereichState();
}

class _LupenbereichState extends State<Lupenbereich> {
  Offset? _ort;

  void _setze(Offset? ort) {
    if (!widget.aktiv) return;
    setState(() => _ort = ort);
  }

  @override
  void didUpdateWidget(Lupenbereich alt) {
    super.didUpdateWidget(alt);
    if (!widget.aktiv) _ort = null;
  }

  @override
  Widget build(BuildContext context) {
    final ort = _ort;
    return MouseRegion(
      cursor: widget.aktiv ? SystemMouseCursors.precise : MouseCursor.defer,
      onHover: (e) => _setze(e.localPosition),
      onExit: (_) => _setze(null),
      child: Listener(
        // Ein Listener nimmt niemandem die Geste weg: Langes Drücken für
        // „Original zeigen" darunter funktioniert weiter.
        onPointerMove: (e) => _setze(e.localPosition),
        onPointerDown: (e) => _setze(e.localPosition),
        child: Stack(
          // Das Bild darunter bekommt genau die Vorgaben, die es ohne
          // Lupe hätte – sonst schrumpfte, was keine eigene Grösse hat.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (widget.aktiv && ort != null)
              Positioned(
                left: ort.dx - lupenDurchmesser / 2,
                top: ort.dy - lupenDurchmesser / 2,
                child: const IgnorePointer(
                  child: RawMagnifier(
                    size: Size.square(lupenDurchmesser),
                    magnificationScale: lupenVergroesserung,
                    decoration: MagnifierDecoration(
                      shape: CircleBorder(
                        side: BorderSide(color: Colors.white70, width: 2),
                      ),
                      shadows: [
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

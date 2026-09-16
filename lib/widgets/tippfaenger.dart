import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

/// Nimmt den Tipp entgegen, ohne sich um ihn zu streiten.
///
/// Gemeinsam genutzt von [Gesichtsrahmen] und `Textrahmen` – beide liegen
/// über demselben `PhotoView` und stossen deshalb auf dasselbe Problem.
///
/// **Warum kein gewöhnlicher [GestureDetector].** Im Vollbild liegt das
/// Foto in einem `PhotoView`, und das erkennt Zoom- und Schiebegesten mit
/// einem eigenen Erkenner. In der Auseinandersetzung darüber, wem eine
/// Berührung gehört, gewinnt dieser – ein Tipp auf einen Rahmen kam nie
/// an, gemessen: die Behandlungsroutine wurde kein einziges Mal
/// aufgerufen. Ein [Listener] nimmt an dieser Auseinandersetzung gar
/// nicht teil und bekommt seine Ereignisse in jedem Fall.
///
/// Der Preis ist, dass „Tipp" hier selbst entschieden werden muss: als
/// Berührung, die sich zwischen Aufsetzen und Abheben um weniger als
/// [Tippfaenger.wackeln] bewegt hat. Wer über das Foto zieht,
/// verschiebt es also weiterhin, auch wenn er dabei auf einem Gesicht
/// beginnt.
class Tippfaenger extends StatefulWidget {
  final VoidCallback? beiTipp;
  final void Function(Offset stelle)? beiMenue;
  final Widget child;

  const Tippfaenger({
    super.key,
    required this.beiTipp,
    required this.beiMenue,
    required this.child,
  });

  /// Wie weit der Finger zwischen Aufsetzen und Abheben wandern darf,
  /// damit es noch als Tipp gilt.
  static const double wackeln = 8;

  @override
  State<Tippfaenger> createState() => TippfaengerState();
}

class TippfaengerState extends State<Tippfaenger> {
  Offset? _start;

  @override
  Widget build(BuildContext context) {
    Widget inhalt = Listener(
      // Nur die linke Taste. Ohne diese Prüfung löste ein Rechtsklick
      // beides aus: das Menü und das Benennen – zwei Fenster übereinander
      // für einen Klick.
      onPointerDown: (e) =>
          _start = e.buttons == kPrimaryButton ? e.position : null,
      onPointerUp: (e) {
        final start = _start;
        _start = null;
        if (start == null || widget.beiTipp == null) return;
        if ((e.position - start).distance > Tippfaenger.wackeln) return;
        widget.beiTipp!();
      },
      onPointerCancel: (_) => _start = null,
      child: widget.child,
    );
    // Der Rechtsklick bleibt beim Gestenerkenner: Um ihn streitet sich
    // niemand, und so bleibt das Menü dort, wo es in der
    // Gesichts-Bearbeitung schon war.
    if (widget.beiMenue != null) {
      inhalt = GestureDetector(
        onSecondaryTapDown: (d) => widget.beiMenue!(d.globalPosition),
        child: inhalt,
      );
    }
    return inhalt;
  }
}

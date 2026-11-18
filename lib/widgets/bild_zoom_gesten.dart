import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart';

import 'wisch_zoom.dart' show istWischen;

/// Wieviel Zoom eine Wischstrecke von einem Bildpunkt ergibt.
///
/// Anders als bei der Karte ist der Bildzoom ein **Faktor** und keine
/// Stufe, deshalb geht es über die Exponentialfunktion: Gleich lange
/// Wischwege ergeben gleich grosse Sprünge, egal wie weit man schon
/// hineingezoomt ist. 0,004 heisst rund 250 Punkte Wischweg für eine
/// Verdopplung – etwa ein bequemer Wisch.
const double bildWischFaktor = 0.004;

/// Der neue Massstab für eine Wischstrecke.
double bildWischZoom({
  required double startZoom,
  required double wischWegY,
  required double kleinster,
  required double groesster,
}) => (startZoom * math.exp(-wischWegY * bildWischFaktor)).clamp(
  kleinster,
  groesster,
);

/// Ob diese Tastenkombination den Zoom auslösen soll.
///
/// Command (macOS) oder Strg (Linux/Windows) – beide werden überall
/// angenommen, wie schon bei der Rasterauswahl: Eine externe Tastatur an
/// einem Mac meldet je nach Belegung das eine oder das andere.
bool zoomtaste(Set<LogicalKeyboardKey> gedrueckt) => gedrueckt.any(
  {
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
  }.contains,
);

/// Legt Zoom per Wischgeste über eine [PhotoView].
///
/// **Warum es das braucht.** Aus dem Erstlauf-Bericht (C10): „mit
/// Trackpad funktioniert Zwei-Finger-Zoom, mit Magic Mouse nicht". Eine
/// Magic Mouse hat kein Rad und keine zwei Finger zum Kneifen – sie
/// kennt nur das Wischen auf ihrer Tastfläche, und macOS meldet das als
/// fortlaufende Geste. PhotoView macht daraus ein Verschieben.
///
/// **Warum das Wischen trotzdem verschiebt.** Weil es das soll: Ein
/// hineingezoomtes Foto zu verschieben ist die häufigere Absicht, und
/// auf einem Trackpad ist der Zweifinger-Wisch genau dafür da. Wer den
/// Wisch zum Zoomen umwidmete, nähme allen Trackpad-Nutzern das
/// Verschieben weg, um einer Maus zu helfen.
///
/// Der Zoom liegt deshalb auf **Command/Strg + Wischen**. Das ist keine
/// Erfindung: macOS zoomt seine Bildschirmlupe seit jeher mit
/// Steuerung + Wischen, und die Kürzeltafel sagt es an.
class BildZoomGesten extends StatefulWidget {
  const BildZoomGesten({
    super.key,
    required this.steuerung,
    required this.child,
    this.kleinster = 0.1,
    this.groesster = 8.0,
  });

  final PhotoViewControllerBase steuerung;
  final Widget child;
  final double kleinster;
  final double groesster;

  @override
  State<BildZoomGesten> createState() => _BildZoomGestenState();
}

class _BildZoomGestenState extends State<BildZoomGesten> {
  /// Der Massstab beim Beginn der Geste – `pan` ist der Gesamtweg seit
  /// dem Beginn, nicht der Weg seit dem letzten Ereignis.
  double? _start;

  void _beginn() => _start = widget.steuerung.scale ?? 1;

  void _weiter(PointerPanZoomUpdateEvent e) {
    final start = _start;
    if (start == null) return;
    widget.steuerung.scale = istWischen(e.scale)
        ? bildWischZoom(
            startZoom: start,
            wischWegY: e.pan.dy,
            kleinster: widget.kleinster,
            groesster: widget.groesster,
          )
        // Ein Kneifen bei gehaltener Taste: Die Geste gehört jetzt hier
        // her, PhotoView sieht sie nicht mehr – also selbst mitgehen.
        : (start * e.scale).clamp(widget.kleinster, widget.groesster);
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    // Ein eigener Erkenner statt eines blossen Listener: PhotoView
    // bekommt dieselben Trackpad-Ereignisse über seine
    // Skalierungserkennung (Massstab 1) und setzte den Zoom nach jedem
    // Ereignis auf den Anfangswert der Geste zurück. Wer die Geste in
    // der Gestenarena gewinnt, bekommt sie allein.
    gestures: {
      _WischZoomErkenner:
          GestureRecognizerFactoryWithHandlers<_WischZoomErkenner>(
            _WischZoomErkenner.new,
            (erkenner) => erkenner
              ..beiBeginn = _beginn
              ..beiWisch = _weiter
              ..beiEnde = () => _start = null,
          ),
    },
    child: widget.child,
  );
}

/// Beansprucht eine Trackpad-Geste, wenn bei ihrem Beginn die Zoomtaste
/// gehalten wird – sonst nimmt er gar nicht erst teil, und PhotoView
/// verschiebt und kneift wie gewohnt.
class _WischZoomErkenner extends OneSequenceGestureRecognizer {
  VoidCallback? beiBeginn;
  void Function(PointerPanZoomUpdateEvent)? beiWisch;
  VoidCallback? beiEnde;

  @override
  void addAllowedPointer(PointerDownEvent event) {}

  @override
  bool isPointerAllowed(PointerDownEvent event) => false;

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (!zoomtaste(HardwareKeyboard.instance.logicalKeysPressed)) return;
    startTrackingPointer(event.pointer, event.transform);
    // Gleich gewinnen: Die Arena schliesst erst nach diesem Ereignis,
    // dann verlieren PhotoView und die Seitenleiste die Geste.
    resolve(GestureDisposition.accepted);
    beiBeginn?.call();
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      beiWisch?.call(event);
    } else if (event is PointerPanZoomEndEvent || event is PointerCancelEvent) {
      beiEnde?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    beiEnde?.call();
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'wisch-zoom';
}

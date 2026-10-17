/// Von den Typen des Kerns (geometrie.dart) zu denen von `dart:ui` und
/// zurück – für die Stellen, an denen die App die Anordnung des
/// Lebensbaums malt oder einen Tipp auf sie umrechnet.
library;

import 'dart:ui' as ui;

import 'package:kern/services/geometrie.dart' as g;

extension RechteckAlsUi on g.Rect {
  ui.Rect get alsUi => ui.Rect.fromLTRB(left, top, right, bottom);
}

extension PunktAlsUi on g.Offset {
  ui.Offset get alsUi => ui.Offset(dx, dy);
}

extension GroesseAlsUi on g.Size {
  ui.Size get alsUi => ui.Size(width, height);
}

extension FarbeAlsUi on g.Color {
  ui.Color get alsUi => ui.Color(value);
}

extension RechteckAlsKern on ui.Rect {
  g.Rect get alsKern => g.Rect.fromLTRB(left, top, right, bottom);
}

extension PunktAlsKern on ui.Offset {
  g.Offset get alsKern => g.Offset(dx, dy);
}

extension GroesseAlsKern on ui.Size {
  g.Size get alsKern => g.Size(width, height);
}

/// Punkt, Grösse, Rechteck und Farbe ohne `dart:ui`.
///
/// Die Anordnung des Lebensbaums (lebensbaum*.dart) rechnet mit Rechtecken
/// auf einer Vorlage. Mit den Typen aus `dart:ui` lief sie nur in der App –
/// der Server, der den Baum für den Browser anordnet, kennt `dart:ui` nicht.
/// Hier stehen dieselben Namen mit derselben Bedeutung, so weit die
/// Anordnung sie braucht; die App rechnet beim Malen in ihre eigenen um
/// (lib/services/geometrie_ui.dart).
library;

import 'dart:math' as math;

class Offset {
  const Offset(this.dx, this.dy);

  final double dx;
  final double dy;

  static const zero = Offset(0, 0);

  double get distance => math.sqrt(dx * dx + dy * dy);

  Offset operator +(Offset o) => Offset(dx + o.dx, dy + o.dy);
  Offset operator -(Offset o) => Offset(dx - o.dx, dy - o.dy);
  Offset operator -() => Offset(-dx, -dy);
  Offset operator *(double f) => Offset(dx * f, dy * f);
  Offset operator /(double f) => Offset(dx / f, dy / f);

  /// Ein Rechteck ab diesem Punkt in der Grösse [groesse].
  Rect operator &(Size groesse) =>
      Rect.fromLTWH(dx, dy, groesse.width, groesse.height);

  Offset translate(double x, double y) => Offset(dx + x, dy + y);

  @override
  bool operator ==(Object other) =>
      other is Offset && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);

  @override
  String toString() => 'Offset($dx, $dy)';
}

class Size {
  const Size(this.width, this.height);

  final double width;
  final double height;

  static const zero = Size(0, 0);

  double get aspectRatio => height == 0 ? 0 : width / height;
  double get shortestSide => math.min(width, height);
  double get longestSide => math.max(width, height);
  bool get isEmpty => width <= 0 || height <= 0;

  Size operator *(double f) => Size(width * f, height * f);
  Size operator /(double f) => Size(width / f, height / f);

  Offset center(Offset ursprung) =>
      Offset(ursprung.dx + width / 2, ursprung.dy + height / 2);

  @override
  bool operator ==(Object other) =>
      other is Size && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'Size($width, $height)';
}

class Rect {
  const Rect.fromLTRB(this.left, this.top, this.right, this.bottom);

  const Rect.fromLTWH(double left, double top, double width, double height)
    : this.fromLTRB(left, top, left + width, top + height);

  Rect.fromCircle({required Offset center, required double radius})
    : this.fromLTRB(
        center.dx - radius,
        center.dy - radius,
        center.dx + radius,
        center.dy + radius,
      );

  Rect.fromCenter({
    required Offset center,
    required double width,
    required double height,
  }) : this.fromLTRB(
         center.dx - width / 2,
         center.dy - height / 2,
         center.dx + width / 2,
         center.dy + height / 2,
       );

  Rect.fromPoints(Offset a, Offset b)
    : this.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx),
        math.max(a.dy, b.dy),
      );

  final double left;
  final double top;
  final double right;
  final double bottom;

  static const zero = Rect.fromLTRB(0, 0, 0, 0);

  double get width => right - left;
  double get height => bottom - top;
  Size get size => Size(width, height);
  double get shortestSide => math.min(width.abs(), height.abs());
  double get longestSide => math.max(width.abs(), height.abs());
  bool get isEmpty => left >= right || top >= bottom;

  Offset get center => Offset(left + width / 2, top + height / 2);
  Offset get topLeft => Offset(left, top);
  Offset get topCenter => Offset(left + width / 2, top);
  Offset get topRight => Offset(right, top);
  Offset get centerLeft => Offset(left, top + height / 2);
  Offset get centerRight => Offset(right, top + height / 2);
  Offset get bottomLeft => Offset(left, bottom);
  Offset get bottomCenter => Offset(left + width / 2, bottom);
  Offset get bottomRight => Offset(right, bottom);

  /// Wie in `dart:ui`: links und oben eingeschlossen, rechts und unten
  /// nicht.
  bool contains(Offset p) =>
      p.dx >= left && p.dx < right && p.dy >= top && p.dy < bottom;

  bool overlaps(Rect o) =>
      right > o.left && o.right > left && bottom > o.top && o.bottom > top;

  Rect shift(Offset o) =>
      Rect.fromLTRB(left + o.dx, top + o.dy, right + o.dx, bottom + o.dy);

  Rect translate(double x, double y) =>
      Rect.fromLTRB(left + x, top + y, right + x, bottom + y);

  Rect inflate(double d) =>
      Rect.fromLTRB(left - d, top - d, right + d, bottom + d);

  Rect deflate(double d) => inflate(-d);

  Rect intersect(Rect o) => Rect.fromLTRB(
    math.max(left, o.left),
    math.max(top, o.top),
    math.min(right, o.right),
    math.min(bottom, o.bottom),
  );

  Rect expandToInclude(Rect o) => Rect.fromLTRB(
    math.min(left, o.left),
    math.min(top, o.top),
    math.max(right, o.right),
    math.max(bottom, o.bottom),
  );

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'Rect.fromLTRB($left, $top, $right, $bottom)';
}

/// Eine Farbe als ARGB-Zahl, wie `dart:ui` sie schreibt (0xAARRGGBB).
class Color {
  const Color(this.value);

  final int value;

  int get alpha => (value >> 24) & 0xFF;
  int get red => (value >> 16) & 0xFF;
  int get green => (value >> 8) & 0xFF;
  int get blue => value & 0xFF;

  /// Als CSS-Farbe für den Browser: `#rrggbb` oder `rgba(…)`.
  String get css => alpha == 0xFF
      ? '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'
      : 'rgba($red, $green, $blue, ${(alpha / 255).toStringAsFixed(3)})';

  @override
  bool operator ==(Object other) => other is Color && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Color(0x${value.toRadixString(16).padLeft(8, '0')})';
}

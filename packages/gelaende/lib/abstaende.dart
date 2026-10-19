/// Abstände und Radien – dieselben Werte wie `AppSpacing`/`AppRadius` der
/// Rechner-App, damit die Landschaft in beiden Apps gleich aussieht.
library;

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
}

abstract final class AppRadius {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const pill = 100.0;
}

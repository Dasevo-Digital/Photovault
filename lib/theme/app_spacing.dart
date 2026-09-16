/// Benannte Abstands-/Radien-Konstanten, abgeleitet aus den tatsächlich am
/// häufigsten im Code vorkommenden Werten (Audit: ~160 verstreute inline
/// `EdgeInsets`/`BorderRadius`-Stellen ohne gemeinsames System) – keine neu
/// erfundene Skala, sondern die bestehenden, am häufigsten benutzten Werte
/// benannt und app-weit konsequent wiederverwendet.
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
  /// Vollständig runde ("Pillen"-)Form, z.B. für Chips/Badges.
  static const pill = 100.0;
}

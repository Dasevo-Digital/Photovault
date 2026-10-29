/// Gemeinsame Grenzen für Vorbereitung, Warteschlange und HTTP-Transport.
abstract final class Abgleichsgrenzen {
  static const basisZeilen = 50000;
  static const befehlBytes = 6 * 1024 * 1024;
  static const stapelBytes = 8 * 1024 * 1024;
}

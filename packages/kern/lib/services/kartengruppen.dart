import 'dart:math' as math;

import '../db/rasterzeile.dart';

/// Fasst Aufnahmen mit Ort zu Punkten zusammen, die bei [zoom] nicht
/// übereinanderlägen: Die Welt wird in Zellen von [kante] Bildpunkten
/// geteilt (Web-Mercator), alles in einer Zelle ist ein Punkt. Dieselbe
/// Rechnung auf dem Telefon und für den Browser auf dem Server – damit
/// zwei Karten dieselben Punkte zeigen.
List<List<Rasterzeile>> kartengruppen(
  List<Rasterzeile> orte,
  double zoom, {
  double kante = 64,
}) {
  final welt = 256 * math.pow(2, zoom);
  final zellen = <(int, int), List<Rasterzeile>>{};
  for (final z in orte) {
    final x = (z.longitude! + 180) / 360 * welt;
    final s = math.sin(z.latitude! * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * welt;
    zellen.putIfAbsent((x ~/ kante, y ~/ kante), () => []).add(z);
  }
  return zellen.values.toList();
}

/// Der Schwerpunkt einer Gruppe.
({double breite, double laenge}) gruppenmitte(List<Rasterzeile> g) => (
  breite: g.map((z) => z.latitude!).reduce((a, b) => a + b) / g.length,
  laenge: g.map((z) => z.longitude!).reduce((a, b) => a + b) / g.length,
);

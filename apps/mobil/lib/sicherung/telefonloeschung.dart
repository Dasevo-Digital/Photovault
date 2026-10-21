import 'package:kern/db/database.dart';

import 'kamerarolle.dart';
import 'stand.dart';

/// Aufnahmen auch aus der Fotomediathek des Telefons löschen (#205): Apple
/// Fotos unter iOS, die Galerie unter Android.
///
/// Welches Foto des Telefons zu welcher Aufnahme auf dem Server gehört,
/// weiss die Sicherung (`erledigt.aufnahme`) – auch für Fotos, die schon
/// vorher auf dem Server lagen, etwa vom Rechner. Fotos, die nie von
/// diesem Telefon gesichert wurden, kennt sie nicht; die bleiben.
///
/// Gelöscht wird immer über das System, das selbst noch einmal fragt.
/// Unter iOS liegen die Fotos danach 30 Tage unter „Zuletzt gelöscht“.
class Telefonloeschung {
  const Telefonloeschung({
    required this.stand,
    required this.rolle,
    required this.db,
  });

  final Sicherungsstand stand;
  final Kamerarolle rolle;
  final AppDatabase db;

  /// Die Kennungen auf dem Telefon zu [aufnahmen] (Kennungen auf dem
  /// Server), die dort noch liegen.
  Future<List<String>> zu(Iterable<String> aufnahmen) async {
    final lokal = stand.lokaleZu(aufnahmen);
    return lokal.isEmpty ? const [] : rolle.vorhanden(lokal);
  }

  /// Was in Photo Vault im Papierkorb liegt – hier oder auf einem anderen
  /// Gerät gelöscht – und auf dem Telefon noch da ist.
  Future<List<String>> ausDemPapierkorb() async {
    final gesichert = stand.gesichertMitAufnahme();
    if (gesichert.isEmpty) return const [];
    final imKorb = await db.aufnahmenImPapierkorb(
      gesichert.values.map((g) => g.aufnahme),
    );
    final lokal = [
      for (final MapEntry(key: lokal, value: g) in gesichert.entries)
        if (imKorb.contains(g.aufnahme)) lokal,
    ];
    return lokal.isEmpty ? const [] : rolle.vorhanden(lokal);
  }

  /// Löscht [lokal] vom Telefon; gibt zurück, wie viele wirklich gingen.
  Future<int> loesche(List<String> lokal) =>
      lokal.isEmpty ? Future.value(0) : rolle.loesche(lokal);
}

import 'verbindung.dart';

/// Der Speicher des Servers (siehe dort `Speicherwaechter`): knapp heisst
/// warnen, voll heisst, er nimmt keine neuen Fotos an.
class Serverspeicher {
  const Serverspeicher({required this.stufe, this.gesamt, this.frei});

  factory Serverspeicher.ausJson(Map<String, Object?> j) => Serverspeicher(
    stufe: '${j['stufe'] ?? 'unbekannt'}',
    gesamt: (j['gesamt'] as num?)?.toInt(),
    frei: (j['frei'] as num?)?.toInt(),
  );

  /// `ausreichend`, `knapp`, `voll` oder `unbekannt`.
  final String stufe;

  /// Bytes; `null`, wenn der Server nicht messen konnte.
  final int? gesamt;
  final int? frei;

  bool get knapp => stufe == 'knapp';
  bool get voll => stufe == 'voll';

  /// Fragt den Server. `null`, wenn er das noch nicht kann (vor 3.33).
  static Future<Serverspeicher?> hole(Serververbindung v) async {
    try {
      return Serverspeicher.ausJson(await v.hole('api/v1/speicher'));
    } on Serverfehler catch (f) {
      if (f.status == 404) return null;
      rethrow;
    }
  }

  /// Ob sich für die Anzeige etwas geändert hat – die Stufe oder der freie
  /// Platz um mindestens ein Gigabyte.
  static bool anders(Serverspeicher? a, Serverspeicher? b) =>
      a?.stufe != b?.stufe ||
      ((a?.frei ?? 0) ~/ (1 << 30)) != ((b?.frei ?? 0) ~/ (1 << 30));
}

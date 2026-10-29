import '../services/backup_service.dart' show BackupProbeErgebnis;
import 'verbindung.dart';

/// Wie die Sicherung des Servers steht (siehe dort `Serversicherung`) –
/// nur für Verwalter.
class Serversicherungsstand {
  const Serversicherungsstand({
    required this.stufe,
    this.ziel,
    this.laeuft = false,
    this.letzterErfolg,
    this.ende,
    this.fehler,
    this.naechster,
    this.neu = 0,
    this.proben = const [],
  });

  factory Serversicherungsstand.ausJson(Map<String, Object?> j) =>
      Serversicherungsstand(
        stufe: '${j['stufe'] ?? 'aus'}',
        proben: [
          for (final k in (j['konten'] as List?) ?? const [])
            if ((k as Map)['wiederherstellungsprobe'] case final Map p)
              BackupProbeErgebnis.ausJson(p.cast<String, dynamic>()),
        ],
        ziel: j['ziel'] as String?,
        laeuft: j['laeuft'] == true,
        letzterErfolg: DateTime.tryParse('${j['letzterErfolg']}')?.toLocal(),
        ende: DateTime.tryParse('${j['ende']}')?.toLocal(),
        fehler: j['fehler'] as String?,
        naechster: DateTime.tryParse('${j['naechster']}')?.toLocal(),
        neu: [
          for (final k in (j['konten'] as List?) ?? const [])
            ((k as Map)['neu'] as num?)?.toInt() ?? 0,
        ].fold(0, (a, b) => a + b),
      );

  /// `aus`, `nichtEingerichtet`, `zielFehlt`, `fehler`, `veraltet`, `ok`.
  final String stufe;
  final String? ziel;
  final bool laeuft;
  final DateTime? letzterErfolg;

  /// Wann der letzte Lauf endete, gelungen oder nicht.
  final DateTime? ende;
  final String? fehler;
  final DateTime? naechster;

  /// Neue Dateien im letzten Lauf, über alle Konten.
  final int neu;
  final List<BackupProbeErgebnis> proben;

  /// Ob ein Verwalter hinsehen sollte.
  bool get warnt => const {'zielFehlt', 'fehler', 'veraltet'}.contains(stufe);

  /// Fragt den Server. `null`, wenn das Konto kein Verwalter ist oder der
  /// Server das noch nicht kann.
  static Future<Serversicherungsstand?> hole(Serververbindung v) async {
    try {
      return Serversicherungsstand.ausJson(await v.hole('api/v1/sicherung'));
    } on Serverfehler catch (f) {
      if (f.status == 403 || f.status == 404) return null;
      rethrow;
    }
  }

  static Future<Serversicherungsstand> einrichten(
    Serververbindung v,
    String passphrase,
  ) async => Serversicherungsstand.ausJson(
    await v.schicke('api/v1/sicherung/einrichten', {'passphrase': passphrase}),
  );

  static Future<Serversicherungsstand> zielNeu(Serververbindung v) async =>
      Serversicherungsstand.ausJson(
        await v.schicke('api/v1/sicherung/ziel', const {}),
      );

  static Future<Serversicherungsstand> jetzt(Serververbindung v) async =>
      Serversicherungsstand.ausJson(
        await v.schicke('api/v1/sicherung/jetzt', const {}),
      );
}

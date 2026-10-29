/// Geworfen, wenn ein verschlüsseltes Backup ohne Passphrase geöffnet werden
/// soll – der Aufrufer zeigt seinen eigenen, übersetzten Hinweis.
class BackupBrauchtPassphrase implements Exception {
  const BackupBrauchtPassphrase();
}

/// Ein unveränderlicher Datenbankstand eines automatischen Backups.
///
/// Die verschlüsselten Originale bleiben im gemeinsamen Datenbestand des
/// Backups liegen. Eine Generation enthält deshalb nur den zugehörigen,
/// verschlüsselten Datenbank-Schnappschuss.
class BackupGeneration {
  const BackupGeneration({
    required this.id,
    required this.createdAt,
    required this.snapshotPath,
  });

  final String id;
  final DateTime createdAt;
  final String snapshotPath;
}

class BackupProgress {
  final int done;
  final int total;
  final String? currentFile;

  /// Wie viele Dateien beim nächsten Lauf folgen, weil die Mengenbegrenzung
  /// gegriffen hat – sonst null.
  ///
  /// Als Zahl statt als fertigem Satz: Der Dienst kennt keine
  /// Oberflächensprache, und der Satz stünde sonst in `currentFile`, wo
  /// eigentlich ein Dateiname erwartet wird.
  final int? grenzeOffen;

  /// Wie viele Dateien in diesem Lauf nicht gesichert werden konnten –
  /// sonst null.
  ///
  /// Auch das eine Zahl statt eines Satzes, aus demselben Grund wie
  /// [grenzeOffen]. Sie muss sichtbar werden: Eine Sicherung, die einzelne
  /// Dateien auslässt, darf nicht wie eine vollständige aussehen.
  final int? fehlgeschlagen;

  /// Wie viele Zeilen aus dem Datenbank-Schnappschuss übernommen wurden –
  /// Personen, Gesichter, Verwandtschaften, Reisen, Aktivitäten und alles
  /// Weitere, was in keiner Datei-Beilage steht. `null`, wenn die Sicherung
  /// keinen Schnappschuss enthielt (eine von Hand angestossene tut das
  /// nicht) oder er sich nicht lesen liess.
  final int? uebernommeneZeilen;

  /// Wahr, solange die Wiederherstellung die Gesichtsausschnitte neu
  /// zeichnet. Das ist eine eigene Stufe mit eigener Zählung – ohne diesen
  /// Hinweis sähe es aus, als finge der Lauf von vorne an.
  final bool ausschnitteNeu;

  final BackupProbeErgebnis? wiederherstellungsprobe;
  final RestoreErgebnis? wiederherstellung;

  BackupProgress(
    this.done,
    this.total, {
    this.currentFile,
    this.grenzeOffen,
    this.fehlgeschlagen,
    this.uebernommeneZeilen,
    this.ausschnitteNeu = false,
    this.wiederherstellungsprobe,
    this.wiederherstellung,
  });
}

/// Der Nachweis gehört zum Sicherungsziel. Er enthält weder Dateinamen
/// noch Prüfsummen einzelner Fotos oder Schlüsselmaterial.
class BackupProbeErgebnis {
  const BackupProbeErgebnis({
    required this.am,
    required this.erfolgreich,
    required this.originale,
    required this.gesamt,
    required this.datenbank,
    this.letzterErfolg,
    this.fehler,
    this.position = 0,
    this.passphraseGeprueft,
  });

  final DateTime am;
  final bool erfolgreich;
  final int originale;
  final int gesamt;
  final bool datenbank;
  final DateTime? letzterErfolg;
  final String? fehler;
  final int position;
  final bool? passphraseGeprueft;

  Map<String, Object?> alsJson() => {
    'format': 1,
    'am': am.toUtc().toIso8601String(),
    'erfolgreich': erfolgreich,
    'originale': originale,
    'gesamt': gesamt,
    'datenbank': datenbank,
    'letzterErfolg': letzterErfolg?.toUtc().toIso8601String(),
    'fehler': fehler,
    'position': position,
    'passphraseGeprueft': passphraseGeprueft,
  };

  static BackupProbeErgebnis ausJson(Map<String, dynamic> j) {
    if (j['format'] != 1) throw const FormatException('pv_probe_format');
    return BackupProbeErgebnis(
      am: DateTime.parse(j['am'] as String),
      erfolgreich: j['erfolgreich'] as bool,
      originale: j['originale'] as int,
      gesamt: j['gesamt'] as int,
      datenbank: j['datenbank'] as bool,
      letzterErfolg: DateTime.tryParse('${j['letzterErfolg']}'),
      fehler: j['fehler'] as String?,
      position: j['position'] as int? ?? 0,
      passphraseGeprueft: j['passphraseGeprueft'] as bool?,
    );
  }
}

/// Ein Fehlercode ohne Dateinamen oder Schlüsselmaterial.
class RestoreProblem {
  const RestoreProblem(this.code);
  final String code;
}

/// Die Bilanz unterscheidet verarbeitete Dateien von tatsächlich importierten.
class RestoreErgebnis {
  RestoreErgebnis({
    required this.geplant,
    required this.importiert,
    required this.vorhanden,
    required this.fehlend,
    required this.gescheitert,
    required this.abgeschlossen,
    List<RestoreProblem> probleme = const [],
  }) : probleme = List.unmodifiable(probleme);
  final int geplant, importiert, vorhanden, fehlend, gescheitert;
  final bool abgeschlossen;
  final List<RestoreProblem> probleme;
  int get fehler => fehlend + gescheitert + probleme.length;
  bool get erfolgreich => abgeschlossen && fehler == 0;
}

class WiederherstellungUnvollstaendig implements Exception {
  const WiederherstellungUnvollstaendig(this.ergebnis);
  final RestoreErgebnis ergebnis;
}

/// Null als Dialogergebnis bleibt ausschließlich dem Abbruch vorbehalten.
class Wiederherstellungsauswahl {
  const Wiederherstellungsauswahl.aktuell() : generation = null;
  const Wiederherstellungsauswahl.generation(BackupGeneration punkt)
    : generation = punkt;
  final BackupGeneration? generation;
}

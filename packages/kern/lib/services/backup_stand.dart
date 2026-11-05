part of 'backup_service.dart';

/// Wie viel des automatischen Backups im Ziel liegt (#303).
///
/// **Das Ziel zählt, nicht die Markierung.** [Assets.autoBackedUp] setzt
/// nur ein Rechner ohne Server, und nach einem Zielwechsel stimmt sie
/// nicht mehr (siehe [BackupService.performAutoBackup]). Eine Anzeige
/// daraus meldete „alles gesichert“ für einen leeren Ordner – deshalb
/// fragt sie dieselbe Stelle wie die Sicherung selbst.
///
/// **Dafür braucht es den Schlüssel:** Die Dateien im Ziel heissen nach
/// der Prüfsumme, verschlüsselt mit ihm. Ohne ihn bleibt [letzterStand],
/// was der letzte Lauf gesehen hat.
extension BackupStand on BackupService {
  static const standDateiname = 'sicherungsstand.json';

  /// Was der letzte Lauf in [wurzel] hinterlassen hat; `null`, wenn dort
  /// noch keiner lief.
  Future<Sicherungsstand?> letzterStand(String wurzel) async {
    try {
      return Sicherungsstand.ausJson(
        jsonDecode(await File(p.join(wurzel, standDateiname)).readAsString())
            as Map<String, dynamic>,
      );
    } on Object {
      return null;
    }
  }

  /// Gescheitert wird hier nicht: Der Stand ist eine Anzeige, die Sicherung
  /// selbst ist da schon im Ziel.
  Future<void> merkeStand(String wurzel, Sicherungsstand stand) async {
    final ziel = File(p.join(wurzel, standDateiname));
    final teil = File('${ziel.path}.${const Uuid().v4()}.neu');
    try {
      await teil.writeAsString(jsonEncode(stand.alsJson()), flush: true);
      await teil.rename(ziel.path);
    } on FileSystemException catch (e) {
      protokoll('Stand der Sicherung nicht gemerkt: $e');
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }

  /// Zählt, was vom automatischen Backup in [zielordner] liegt.
  ///
  /// In einem eigenen Isolate: Name und Dateiabfrage je Aufnahme liessen
  /// bei Zehntausenden sonst die Oberfläche stocken. Ist
  /// [zielordner] selbst nicht da (eine Platte oder Freigabe, die gerade
  /// fehlt), ist das eine [FileSystemException] und keine „0 gesichert“.
  Future<Sicherungsstand> sicherungsstand(
    String zielordner,
    SecretKey schluessel,
  ) async => berechne(_zaehleImZiel, (
    zielordner: zielordner,
    schluessel: await schluessel.extractBytes(),
    umfang: await _db.sicherungsumfang(),
  ));
}

Future<Sicherungsstand> _zaehleImZiel(
  ({
    String zielordner,
    List<int> schluessel,
    List<({String pruefsumme, int bytes})> umfang,
  })
  a,
) async {
  if (!Directory(a.zielordner).existsSync()) {
    throw FileSystemException('pv_backup_ziel_fehlt', a.zielordner);
  }
  final daten = p.join(
    a.zielordner,
    BackupService.autoBackupFolderName,
    VerschluesselteNamen.ordner,
  );
  final schluessel = SecretKey(a.schluessel);
  var gesichert = 0, gesichertBytes = 0, offen = 0, offenBytes = 0;
  for (final x in a.umfang) {
    final name = await VerschluesselteNamen.fuerPruefsumme(
      x.pruefsumme,
      schluessel,
    );
    // Wie BackupService._liegtImZiel, hier ohne Umweg: Im eigenen Isolate
    // stört das Warten niemanden.
    final stat = FileStat.statSync(p.join(daten, name));
    if (stat.type == FileSystemEntityType.file && stat.size > 0) {
      gesichert++;
      gesichertBytes += x.bytes;
    } else {
      offen++;
      offenBytes += x.bytes;
    }
  }
  return Sicherungsstand(
    am: DateTime.now(),
    gesichert: gesichert,
    gesichertBytes: gesichertBytes,
    offen: offen,
    offenBytes: offenBytes,
  );
}

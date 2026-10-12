part of 'befehl.dart';

/// Eine Exportvorgabe anlegen oder überschreiben.
final class ExportvorgabeSpeichern extends Befehl<void> {
  ExportvorgabeSpeichern(Insertable<ExportPresetData> vorgabe)
    : vorgabe = _zeileAlsWerte(vorgabe);

  const ExportvorgabeSpeichern._(this.vorgabe);

  static ExportvorgabeSpeichern aus(Map<String, Object?> w) =>
      ExportvorgabeSpeichern._(_abbildung(w['vorgabe']));

  final Map<String, Object?> vorgabe;

  @override
  String get art => 'exportvorgabeSpeichern';

  @override
  Map<String, Object?> get werte => {'vorgabe': vorgabe};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.upsertExportPreset(_zeileAus(db.exportPresets, vorgabe));
}

final class ExportvorgabeLoeschen extends Befehl<void> {
  const ExportvorgabeLoeschen(this.vorgabeId);

  static ExportvorgabeLoeschen aus(Map<String, Object?> w) =>
      ExportvorgabeLoeschen(w['vorgabeId']! as int);

  final int vorgabeId;

  @override
  String get art => 'exportvorgabeLoeschen';

  @override
  Map<String, Object?> get werte => {'vorgabeId': vorgabeId};

  @override
  Future<void> anwenden(AppDatabase db) => db.deleteExportPreset(vorgabeId);
}

/// Eine Entwicklungsvorgabe anlegen oder überschreiben.
final class EntwicklungsvorgabeSpeichern extends Befehl<void> {
  EntwicklungsvorgabeSpeichern(Insertable<DevelopPresetData> vorgabe)
    : vorgabe = _zeileAlsWerte(vorgabe);

  const EntwicklungsvorgabeSpeichern._(this.vorgabe);

  static EntwicklungsvorgabeSpeichern aus(Map<String, Object?> w) =>
      EntwicklungsvorgabeSpeichern._(_abbildung(w['vorgabe']));

  final Map<String, Object?> vorgabe;

  @override
  String get art => 'entwicklungsvorgabeSpeichern';

  @override
  Map<String, Object?> get werte => {'vorgabe': vorgabe};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.upsertDevelopPreset(_zeileAus(db.developPresets, vorgabe));
}

/// Was beim Import einer bestimmten Kamera geschieht – anlegen oder
/// überschreiben.
final class KameravorgabeSpeichern extends Befehl<void> {
  KameravorgabeSpeichern(Insertable<CameraPresetData> vorgabe)
    : vorgabe = _zeileAlsWerte(vorgabe);

  const KameravorgabeSpeichern._(this.vorgabe);

  static KameravorgabeSpeichern aus(Map<String, Object?> w) =>
      KameravorgabeSpeichern._(_abbildung(w['vorgabe']));

  final Map<String, Object?> vorgabe;

  @override
  String get art => 'kameravorgabeSpeichern';

  @override
  Map<String, Object?> get werte => {'vorgabe': vorgabe};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.upsertCameraPreset(_zeileAus(db.cameraPresets, vorgabe));
}

/// Die Schlagwörter einer Kameravorgabe – alle auf einmal.
final class KameravorgabeSchlagwoerterSetzen extends Befehl<void> {
  const KameravorgabeSchlagwoerterSetzen(this.vorgabeId, this.schlagwortIds);

  static KameravorgabeSchlagwoerterSetzen aus(Map<String, Object?> w) =>
      KameravorgabeSchlagwoerterSetzen(
        w['vorgabeId']! as String,
        _kennungen(w['schlagwortIds']),
      );

  final String vorgabeId;
  final List<String> schlagwortIds;

  @override
  String get art => 'kameravorgabeSchlagwoerterSetzen';

  @override
  Map<String, Object?> get werte => {
    'vorgabeId': vorgabeId,
    'schlagwortIds': schlagwortIds,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setCameraPresetTags(vorgabeId, schlagwortIds);
}

final class KameravorgabeLoeschen extends Befehl<void> {
  const KameravorgabeLoeschen(this.vorgabeId);

  static KameravorgabeLoeschen aus(Map<String, Object?> w) =>
      KameravorgabeLoeschen(w['vorgabeId']! as String);

  final String vorgabeId;

  @override
  String get art => 'kameravorgabeLoeschen';

  @override
  Map<String, Object?> get werte => {'vorgabeId': vorgabeId};

  @override
  Future<void> anwenden(AppDatabase db) => db.deleteCameraPreset(vorgabeId);
}

/// Eine Regel für den Import – anlegen oder überschreiben.
final class RegelSpeichern extends Befehl<void> {
  RegelSpeichern(Insertable<AutomationRuleData> regel)
    : regel = _zeileAlsWerte(regel);

  const RegelSpeichern._(this.regel);

  static RegelSpeichern aus(Map<String, Object?> w) =>
      RegelSpeichern._(_abbildung(w['regel']));

  final Map<String, Object?> regel;

  @override
  String get art => 'regelSpeichern';

  @override
  Map<String, Object?> get werte => {'regel': regel};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.upsertAutomationRule(_zeileAus(db.automationRules, regel));
}

/// Die Schlagwörter einer Regel – alle auf einmal.
final class RegelSchlagwoerterSetzen extends Befehl<void> {
  const RegelSchlagwoerterSetzen(this.regelId, this.schlagwortIds);

  static RegelSchlagwoerterSetzen aus(Map<String, Object?> w) =>
      RegelSchlagwoerterSetzen(
        w['regelId']! as String,
        _kennungen(w['schlagwortIds']),
      );

  final String regelId;
  final List<String> schlagwortIds;

  @override
  String get art => 'regelSchlagwoerterSetzen';

  @override
  Map<String, Object?> get werte => {
    'regelId': regelId,
    'schlagwortIds': schlagwortIds,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setAutomationRuleTags(regelId, schlagwortIds);
}

final class RegelLoeschen extends Befehl<void> {
  const RegelLoeschen(this.regelId);

  static RegelLoeschen aus(Map<String, Object?> w) =>
      RegelLoeschen(w['regelId']! as String);

  final String regelId;

  @override
  String get art => 'regelLoeschen';

  @override
  Map<String, Object?> get werte => {'regelId': regelId};

  @override
  Future<void> anwenden(AppDatabase db) => db.deleteAutomationRule(regelId);
}

/// Ob der Papierkorb nach [tage] Tagen von selbst leert.
final class PapierkorbFristSetzen extends Befehl<void> {
  const PapierkorbFristSetzen({required this.an, this.tage});

  static PapierkorbFristSetzen aus(Map<String, Object?> w) =>
      PapierkorbFristSetzen(an: w['an']! as bool, tage: w['tage'] as int?);

  final bool an;
  final int? tage;

  @override
  String get art => 'papierkorbFristSetzen';

  @override
  Map<String, Object?> get werte => {'an': an, 'tage': tage};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setTrashAutoDeleteConfig(enabled: an, afterDays: tage);
}

/// Die allgemeine Schwelle der Gesichtserkennung.
final class GesichtsschwelleSetzen extends Befehl<void> {
  const GesichtsschwelleSetzen(this.schwelle);

  static GesichtsschwelleSetzen aus(Map<String, Object?> w) =>
      GesichtsschwelleSetzen((w['schwelle']! as num).toDouble());

  final double schwelle;

  @override
  String get art => 'gesichtsschwelleSetzen';

  @override
  Map<String, Object?> get werte => {'schwelle': schwelle};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setFaceSimilarityThreshold(schwelle);
}

/// Ob nach jedem Import gleich ausgewertet wird.
final class AuswertenNachImportSetzen extends Befehl<void> {
  const AuswertenNachImportSetzen(this.an);

  static AuswertenNachImportSetzen aus(Map<String, Object?> w) =>
      AuswertenNachImportSetzen(w['an']! as bool);

  final bool an;

  @override
  String get art => 'auswertenNachImportSetzen';

  @override
  Map<String, Object?> get werte => {'an': an};

  @override
  Future<void> anwenden(AppDatabase db) => db.setAutoAnalyzeAfterImport(an);
}

/// Ob Suche und Schlagwörter zwischen Deutsch und Englisch übersetzt werden.
final class SucheUebersetzenSetzen extends Befehl<void> {
  const SucheUebersetzenSetzen(this.an);

  static SucheUebersetzenSetzen aus(Map<String, Object?> w) =>
      SucheUebersetzenSetzen(w['an']! as bool);

  final bool an;

  @override
  String get art => 'sucheUebersetzenSetzen';

  @override
  Map<String, Object?> get werte => {'an': an};

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeUebersetzeSucheUndTags(an);
}

/// Ob neu gesperrte Fotos auch ihre lesbaren Angaben verschlüsselt ablegen
/// (Ort, Beschreibung …), statt sie in der Datenbank zu lassen.
final class AngabenSchuetzenSetzen extends Befehl<void> {
  const AngabenSchuetzenSetzen(this.an);

  static AngabenSchuetzenSetzen aus(Map<String, Object?> w) =>
      AngabenSchuetzenSetzen(w['an']! as bool);

  final bool an;

  @override
  String get art => 'angabenSchuetzenSetzen';

  @override
  Map<String, Object?> get werte => {'an': an};

  @override
  Future<void> anwenden(AppDatabase db) => db.setProtectPrivateMetadata(an);
}

part of 'befehl.dart';

/// Duplikate in einer Aufnahme zusammenführen: [behaltenId] bleibt, die
/// anderen gehen in den Papierkorb, ihre Angaben gehen mit.
final class DuplikateZusammenfuehren extends Befehl<void> {
  const DuplikateZusammenfuehren({
    required this.behaltenId,
    required this.duplikatIds,
    this.beschreibungenVerbinden = true,
  });

  static DuplikateZusammenfuehren aus(Map<String, Object?> w) =>
      DuplikateZusammenfuehren(
        behaltenId: w['behaltenId']! as String,
        duplikatIds: _kennungen(w['duplikatIds']),
        beschreibungenVerbinden: w['beschreibungenVerbinden']! as bool,
      );

  final String behaltenId;
  final List<String> duplikatIds;
  final bool beschreibungenVerbinden;

  @override
  String get art => 'duplikateZusammenfuehren';

  @override
  Map<String, Object?> get werte => {
    'behaltenId': behaltenId,
    'duplikatIds': duplikatIds,
    'beschreibungenVerbinden': beschreibungenVerbinden,
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.fuehreDuplikateZusammen(
    behaltenId: behaltenId,
    duplikatIds: duplikatIds,
    beschreibungenVerbinden: beschreibungenVerbinden,
  );
}

/// Diese Fotos sind keine Duplikate voneinander – nicht mehr vorschlagen.
final class DuplikatgruppeIgnorieren extends Befehl<void> {
  const DuplikatgruppeIgnorieren(this.ids);

  static DuplikatgruppeIgnorieren aus(Map<String, Object?> w) =>
      DuplikatgruppeIgnorieren(_kennungen(w['ids']));

  final List<String> ids;

  @override
  String get art => 'duplikatgruppeIgnorieren';

  @override
  Map<String, Object?> get werte => {'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.ignoriereDuplikatgruppe(ids);
}

/// Das Ignorieren einer Gruppe zurücknehmen.
final class DuplikatgruppeAufheben extends Befehl<void> {
  const DuplikatgruppeAufheben(this.ids);

  static DuplikatgruppeAufheben aus(Map<String, Object?> w) =>
      DuplikatgruppeAufheben(_kennungen(w['ids']));

  final List<String> ids;

  @override
  String get art => 'duplikatgruppeAufheben';

  @override
  Map<String, Object?> get werte => {'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.hebeDuplikatgruppeAuf(ids);
}

/// Alle Ausnahmen der Duplikatsuche vergessen; liefert ihre Zahl.
final class DuplikatAusnahmenLoeschen extends Befehl<int> {
  const DuplikatAusnahmenLoeschen();

  static DuplikatAusnahmenLoeschen aus(Map<String, Object?> w) =>
      const DuplikatAusnahmenLoeschen();

  @override
  String get art => 'duplikatAusnahmenLoeschen';

  @override
  Map<String, Object?> get werte => const {};

  @override
  Future<int> anwenden(AppDatabase db) => db.loescheDuplikatAusnahmen();
}

/// Aufnahmen zu einer Serie stapeln, mit [titelId] obenauf.
final class SerieBilden extends Befehl<void> {
  const SerieBilden(this.serieId, this.ids, this.titelId);

  static SerieBilden aus(Map<String, Object?> w) => SerieBilden(
    w['serieId']! as String,
    _kennungen(w['ids']),
    w['titelId']! as String,
  );

  final String serieId;
  final List<String> ids;
  final String titelId;

  @override
  String get art => 'serieBilden';

  @override
  Map<String, Object?> get werte => {
    'serieId': serieId,
    'ids': ids,
    'titelId': titelId,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.createStack(serieId, ids, titelId);
}

/// Eine Serie wieder auflösen.
final class SerieAufloesen extends Befehl<void> {
  const SerieAufloesen(this.serieId);

  static SerieAufloesen aus(Map<String, Object?> w) =>
      SerieAufloesen(w['serieId']! as String);

  final String serieId;

  @override
  String get art => 'serieAufloesen';

  @override
  Map<String, Object?> get werte => {'serieId': serieId};

  @override
  Future<void> anwenden(AppDatabase db) => db.unstackAssets(serieId);
}

/// Einen Serienvorschlag nicht mehr zeigen.
final class SerienvorschlagVerwerfen extends Befehl<void> {
  const SerienvorschlagVerwerfen(this.schluessel);

  static SerienvorschlagVerwerfen aus(Map<String, Object?> w) =>
      SerienvorschlagVerwerfen(w['schluessel']! as String);

  final String schluessel;

  @override
  String get art => 'serienvorschlagVerwerfen';

  @override
  Map<String, Object?> get werte => {'schluessel': schluessel};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.verwirfSerienvorschlag(schluessel);
}

/// Diese Aufnahmen sind keine Dokumente – nicht mehr vorschlagen.
final class DokumentvorschlaegeVerwerfen extends Befehl<void> {
  const DokumentvorschlaegeVerwerfen(this.ids);

  static DokumentvorschlaegeVerwerfen aus(Map<String, Object?> w) =>
      DokumentvorschlaegeVerwerfen(_kennungen(w['ids']));

  final List<String> ids;

  @override
  String get art => 'dokumentvorschlaegeVerwerfen';

  @override
  Map<String, Object?> get werte => {'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.verwirfDokumentvorschlaege(ids);
}

/// Einen Ortsvorschlag nicht mehr zeigen.
final class OrtsvorschlagVerwerfen extends Befehl<void> {
  const OrtsvorschlagVerwerfen(this.schluessel);

  static OrtsvorschlagVerwerfen aus(Map<String, Object?> w) =>
      OrtsvorschlagVerwerfen(w['schluessel']! as String);

  final String schluessel;

  @override
  String get art => 'ortsvorschlagVerwerfen';

  @override
  Map<String, Object?> get werte => {'schluessel': schluessel};

  @override
  Future<void> anwenden(AppDatabase db) => db.verwirfOrtsvorschlag(schluessel);
}

/// Einen Ortsvorschlag für Aufnahmen ohne Ort übernehmen.
final class OrtsvorschlagUebernehmen extends Befehl<void> {
  const OrtsvorschlagUebernehmen(this.ids, this.breite, this.laenge);

  static OrtsvorschlagUebernehmen aus(Map<String, Object?> w) =>
      OrtsvorschlagUebernehmen(
        _kennungen(w['ids']),
        (w['breite']! as num).toDouble(),
        (w['laenge']! as num).toDouble(),
      );

  final List<String> ids;
  final double breite;
  final double laenge;

  @override
  String get art => 'ortsvorschlagUebernehmen';

  @override
  Map<String, Object?> get werte => {
    'ids': ids,
    'breite': breite,
    'laenge': laenge,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.uebernimmOrtsvorschlag(ids, breite, laenge);
}

/// Orte aus einer GPX-Spur auf Aufnahmen übertragen, samt Namen.
final class OrteAusSpurSetzen extends Befehl<void> {
  const OrteAusSpurSetzen(this.eintraege);

  static OrteAusSpurSetzen aus(Map<String, Object?> w) => OrteAusSpurSetzen([
    for (final e in (w['eintraege']! as List).cast<Map>())
      (
        assetId: e['assetId']! as String,
        breite: (e['breite']! as num).toDouble(),
        laenge: (e['laenge']! as num).toDouble(),
        land: e['land'] as String?,
        region: e['region'] as String?,
        ort: e['ort'] as String?,
      ),
  ]);

  final List<
    ({
      String assetId,
      double breite,
      double laenge,
      String? land,
      String? region,
      String? ort,
    })
  >
  eintraege;

  @override
  String get art => 'orteAusSpurSetzen';

  @override
  Map<String, Object?> get werte => {
    'eintraege': [
      for (final e in eintraege)
        {
          'assetId': e.assetId,
          'breite': e.breite,
          'laenge': e.laenge,
          'land': e.land,
          'region': e.region,
          'ort': e.ort,
        },
    ],
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeOrte(eintraege);
}

/// Eine Erinnerung merken.
final class ErinnerungMerken extends Befehl<void> {
  const ErinnerungMerken({
    required this.erinnerungId,
    required this.titel,
    required this.tag,
    required this.ids,
  });

  static ErinnerungMerken aus(Map<String, Object?> w) => ErinnerungMerken(
    erinnerungId: w['erinnerungId']! as String,
    titel: w['titel']! as String,
    tag: DateTime.parse(w['tag']! as String),
    ids: _kennungen(w['ids']),
  );

  final String erinnerungId;
  final String titel;
  final DateTime tag;
  final List<String> ids;

  @override
  String get art => 'erinnerungMerken';

  @override
  Map<String, Object?> get werte => {
    'erinnerungId': erinnerungId,
    'titel': titel,
    'tag': tag.toIso8601String(),
    'ids': ids,
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.merkeErinnerung(
    id: erinnerungId,
    titel: titel,
    tag: tag,
    assetIds: ids,
  );
}

/// Eine gemerkte Erinnerung vergessen.
final class ErinnerungVergessen extends Befehl<void> {
  const ErinnerungVergessen(this.erinnerungId);

  static ErinnerungVergessen aus(Map<String, Object?> w) =>
      ErinnerungVergessen(w['erinnerungId']! as String);

  final String erinnerungId;

  @override
  String get art => 'erinnerungVergessen';

  @override
  Map<String, Object?> get werte => {'erinnerungId': erinnerungId};

  @override
  Future<void> anwenden(AppDatabase db) => db.vergissErinnerung(erinnerungId);
}

/// Ein Land oder einen Ort auf der Weltkarte markieren.
final class OrtsmarkeSetzen extends Befehl<void> {
  OrtsmarkeSetzen(Insertable<OrtsmarkenData> marke)
    : marke = _zeileAlsWerte(marke);

  const OrtsmarkeSetzen._(this.marke);

  static OrtsmarkeSetzen aus(Map<String, Object?> w) =>
      OrtsmarkeSetzen._(_abbildung(w['marke']));

  final Map<String, Object?> marke;

  @override
  String get art => 'ortsmarkeSetzen';

  @override
  Map<String, Object?> get werte => {'marke': marke};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeOrtsmarke(_zeileAus(db.ortsmarken, marke));
}

/// Eine Markierung auf der Weltkarte entfernen.
final class OrtsmarkeLoeschen extends Befehl<void> {
  const OrtsmarkeLoeschen(this.markenart, this.schluessel);

  static OrtsmarkeLoeschen aus(Map<String, Object?> w) =>
      OrtsmarkeLoeschen(w['markenart']! as String, w['schluessel']! as String);

  final String markenart;
  final String schluessel;

  @override
  String get art => 'ortsmarkeLoeschen';

  @override
  Map<String, Object?> get werte => {
    'markenart': markenart,
    'schluessel': schluessel,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.loescheOrtsmarke(markenart, schluessel);
}

/// Alle Entwicklungseinstellungen einer Aufnahme verwerfen.
final class EntwicklungZuruecksetzen extends Befehl<void> {
  const EntwicklungZuruecksetzen(this.id);

  static EntwicklungZuruecksetzen aus(Map<String, Object?> w) =>
      EntwicklungZuruecksetzen(w['id']! as String);

  final String id;

  @override
  String get art => 'entwicklungZuruecksetzen';

  @override
  Map<String, Object?> get werte => {'id': id};

  @override
  Future<void> anwenden(AppDatabase db) => db.resetDevelopSettings(id);
}

/// Eine Entwicklung speichern: die Regler und wo das gerenderte Bild
/// liegt. Die Datei selbst geht vorher ihren eigenen Weg (in einer
/// verbundenen Bibliothek zum Server, siehe `StoragePaths.abgelegt`);
/// der Befehl trägt nur ihren Pfad – wie bei jeder anderen Aufnahme auch.
final class EntwicklungSpeichern extends Befehl<void> {
  EntwicklungSpeichern(
    this.id,
    Insertable<DevelopSettingsData> einstellungen,
    this.pfad,
  ) : einstellungen = _zeileAlsWerte(einstellungen);

  const EntwicklungSpeichern._(this.id, this.einstellungen, this.pfad);

  static EntwicklungSpeichern aus(Map<String, Object?> w) =>
      EntwicklungSpeichern._(
        w['id']! as String,
        _abbildung(w['einstellungen']),
        w['pfad']! as String,
      );

  final String id;
  final Map<String, Object?> einstellungen;

  /// Der relative Pfad des gerenderten Bilds (`developed/<id>.jpg`).
  final String pfad;

  @override
  String get art => 'entwicklungSpeichern';

  @override
  Map<String, Object?> get werte => {
    'id': id,
    'einstellungen': einstellungen,
    'pfad': pfad,
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.saveDevelopResult(
    id,
    settings: _zeileAus(db.developSettings, einstellungen),
    developedRelativePath: pfad,
  );
}

/// Die Regler einer Maske ändern (ihre Form bleibt).
final class MaskeneinstellungAendern extends Befehl<void> {
  MaskeneinstellungAendern(this.maskeId, Insertable<DevelopMaskData> aenderung)
    : aenderung = _zeileAlsWerte(aenderung);

  const MaskeneinstellungAendern._(this.maskeId, this.aenderung);

  static MaskeneinstellungAendern aus(Map<String, Object?> w) =>
      MaskeneinstellungAendern._(
        w['maskeId']! as int,
        _abbildung(w['aenderung']),
      );

  final int maskeId;
  final Map<String, Object?> aenderung;

  @override
  String get art => 'maskeneinstellungAendern';

  @override
  Map<String, Object?> get werte => {
    'maskeId': maskeId,
    'aenderung': aenderung,
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.updateDevelopMaskAdjustments(
    maskeId,
    _zeileAus(db.developMasks, aenderung),
  );
}

part of 'befehl.dart';

/// Ein Lebensereignis, wie es ein Befehl trägt.
typedef Ereignisangaben = ({
  String id,
  String personId,
  String art,
  DateTime? datum,
  String? ort,
  String? notiz,
});

/// Eine Person aus einer GEDCOM-Datei, wie sie ein Befehl trägt.
typedef Gedcomperson = ({
  String id,
  String name,
  Geschlecht? geschlecht,
  DateTime? geburt,
  DateTime? tod,
});

Map<String, Object?> _ereignisAlsWerte(Ereignisangaben e) => {
  'id': e.id,
  'personId': e.personId,
  'art': e.art,
  'datum': e.datum?.toIso8601String(),
  'ort': e.ort,
  'notiz': e.notiz,
};

Ereignisangaben _ereignisAus(Map w) => (
  id: w['id']! as String,
  personId: w['personId']! as String,
  art: w['art']! as String,
  datum: _zeitOderNichts(w['datum']),
  ort: w['ort'] as String?,
  notiz: w['notiz'] as String?,
);

LebensereignisseCompanion _ereignisZeile(Ereignisangaben e) =>
    LebensereignisseCompanion.insert(
      id: e.id,
      personId: e.personId,
      art: e.art,
      datum: Value(e.datum),
      ort: Value(e.ort),
      notiz: Value(e.notiz),
    );

Map<String, Object?> _kanteAlsWerte(Kante k) => {
  'personId': k.personId,
  'andereId': k.andereId,
  'art': k.art.name,
};

Kante _kanteAus(Map w) => (
  personId: w['personId']! as String,
  andereId: w['andereId']! as String,
  art: Verwandtschaft.values.byName(w['art']! as String),
);

/// Eine Verwandtschaft; liefert den Grund, falls sie nicht passt (etwa ein
/// dritter leiblicher Elternteil).
final class BeziehungHinzufuegen extends Befehl<Beziehungsfehler?> {
  const BeziehungHinzufuegen(this.personId, this.andereId, this.verwandtschaft);

  static BeziehungHinzufuegen aus(Map<String, Object?> w) =>
      BeziehungHinzufuegen(
        w['personId']! as String,
        w['andereId']! as String,
        Verwandtschaft.values.byName(w['verwandtschaft']! as String),
      );

  final String personId;
  final String andereId;
  final Verwandtschaft verwandtschaft;

  @override
  String get art => 'beziehungHinzufuegen';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'andereId': andereId,
    'verwandtschaft': verwandtschaft.name,
  };

  @override
  Future<Beziehungsfehler?> anwenden(AppDatabase db) =>
      db.fuegeBeziehungHinzu(personId, andereId, verwandtschaft);
}

/// Mehrere Verwandtschaften in einem Zug – alle oder keine.
final class BeziehungenHinzufuegen extends Befehl<Beziehungsfehler?> {
  const BeziehungenHinzufuegen(this.kanten);

  static BeziehungenHinzufuegen aus(Map<String, Object?> w) =>
      BeziehungenHinzufuegen([
        for (final k in (w['kanten']! as List).cast<Map>()) _kanteAus(k),
      ]);

  final List<Kante> kanten;

  @override
  String get art => 'beziehungenHinzufuegen';

  @override
  Map<String, Object?> get werte => {
    'kanten': [for (final k in kanten) _kanteAlsWerte(k)],
  };

  @override
  Future<Beziehungsfehler?> anwenden(AppDatabase db) =>
      db.fuegeBeziehungenHinzu(kanten);
}

/// Eine Verwandtschaft lösen; liefert, ob es sie gab.
final class BeziehungEntfernen extends Befehl<bool> {
  const BeziehungEntfernen(this.personId, this.andereId, this.verwandtschaft);

  static BeziehungEntfernen aus(Map<String, Object?> w) => BeziehungEntfernen(
    w['personId']! as String,
    w['andereId']! as String,
    Verwandtschaft.values.byName(w['verwandtschaft']! as String),
  );

  final String personId;
  final String andereId;
  final Verwandtschaft verwandtschaft;

  @override
  String get art => 'beziehungEntfernen';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'andereId': andereId,
    'verwandtschaft': verwandtschaft.name,
  };

  @override
  Future<bool> anwenden(AppDatabase db) =>
      db.entferneBeziehung(personId, andereId, verwandtschaft);
}

/// Aus „leiblich“ wird „Stief-“ oder „Pflege-“ und umgekehrt; liefert, ob
/// es gelang.
final class ElternartAendern extends Befehl<bool> {
  const ElternartAendern(this.kindId, this.elternteilId, this.neueArt);

  static ElternartAendern aus(Map<String, Object?> w) => ElternartAendern(
    w['kindId']! as String,
    w['elternteilId']! as String,
    Verwandtschaft.values.byName(w['neueArt']! as String),
  );

  final String kindId;
  final String elternteilId;
  final Verwandtschaft neueArt;

  @override
  String get art => 'elternartAendern';

  @override
  Map<String, Object?> get werte => {
    'kindId': kindId,
    'elternteilId': elternteilId,
    'neueArt': neueArt.name,
  };

  @override
  Future<bool> anwenden(AppDatabase db) =>
      db.aendereElternart(kindId, elternteilId, neueArt);
}

/// Geburts- und Sterbedatum einer Person.
final class LebensdatenSetzen extends Befehl<void> {
  const LebensdatenSetzen(
    this.personId, {
    required this.geburt,
    required this.tod,
  });

  static LebensdatenSetzen aus(Map<String, Object?> w) => LebensdatenSetzen(
    w['personId']! as String,
    geburt: _zeitOderNichts(w['geburt']),
    tod: _zeitOderNichts(w['tod']),
  );

  final String personId;
  final DateTime? geburt;
  final DateTime? tod;

  @override
  String get art => 'lebensdatenSetzen';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'geburt': geburt?.toIso8601String(),
    'tod': tod?.toIso8601String(),
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeLebensdaten(personId, geburt: geburt, tod: tod);
}

/// Das Geschlecht einer Person; `null` heisst „nicht angegeben“.
final class GeschlechtSetzen extends Befehl<void> {
  const GeschlechtSetzen(this.personId, this.geschlecht);

  static GeschlechtSetzen aus(Map<String, Object?> w) => GeschlechtSetzen(
    w['personId']! as String,
    geschlechtAusText(w['geschlecht'] as String?),
  );

  final String personId;
  final Geschlecht? geschlecht;

  @override
  String get art => 'geschlechtSetzen';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'geschlecht': geschlecht == null ? null : geschlechtZuText(geschlecht!),
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeGeschlecht(personId, geschlecht);
}

/// Ein Ereignis im Lebenslauf einer Person.
final class EreignisHinzufuegen extends Befehl<void> {
  const EreignisHinzufuegen(this.ereignis);

  static EreignisHinzufuegen aus(Map<String, Object?> w) =>
      EreignisHinzufuegen(_ereignisAus(w['ereignis']! as Map));

  final Ereignisangaben ereignis;

  @override
  String get art => 'ereignisHinzufuegen';

  @override
  Map<String, Object?> get werte => {'ereignis': _ereignisAlsWerte(ereignis)};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.fuegeEreignisHinzu(_ereignisZeile(ereignis));
}

/// Ein Ereignis aus dem Lebenslauf nehmen.
final class EreignisLoeschen extends Befehl<void> {
  const EreignisLoeschen(this.ereignisId);

  static EreignisLoeschen aus(Map<String, Object?> w) =>
      EreignisLoeschen(w['ereignisId']! as String);

  final String ereignisId;

  @override
  String get art => 'ereignisLoeschen';

  @override
  Map<String, Object?> get werte => {'ereignisId': ereignisId};

  @override
  Future<void> anwenden(AppDatabase db) => db.loescheEreignis(ereignisId);
}

/// Wo ein Ereignis stattfand; ohne Koordinaten ist es wieder unverortet.
final class EreignisortSetzen extends Befehl<void> {
  const EreignisortSetzen(this.ereignisId, {this.breite, this.laenge});

  static EreignisortSetzen aus(Map<String, Object?> w) => EreignisortSetzen(
    w['ereignisId']! as String,
    breite: (w['breite'] as num?)?.toDouble(),
    laenge: (w['laenge'] as num?)?.toDouble(),
  );

  final String ereignisId;
  final double? breite;
  final double? laenge;

  @override
  String get art => 'ereignisortSetzen';

  @override
  Map<String, Object?> get werte => {
    'ereignisId': ereignisId,
    'breite': breite,
    'laenge': laenge,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeEreignisort(ereignisId, breite: breite, laenge: laenge);
}

/// Eine eingelesene GEDCOM-Datei übernehmen – Personen, Verwandtschaften
/// und Ereignisse in einem Zug.
final class GedcomUebernehmen extends Befehl<void> {
  const GedcomUebernehmen({
    required this.personen,
    required this.kanten,
    required this.ereignisse,
  });

  static GedcomUebernehmen aus(Map<String, Object?> w) => GedcomUebernehmen(
    personen: [
      for (final p in (w['personen']! as List).cast<Map>())
        (
          id: p['id']! as String,
          name: p['name']! as String,
          geschlecht: geschlechtAusText(p['geschlecht'] as String?),
          geburt: _zeitOderNichts(p['geburt']),
          tod: _zeitOderNichts(p['tod']),
        ),
    ],
    kanten: [for (final k in (w['kanten']! as List).cast<Map>()) _kanteAus(k)],
    ereignisse: [
      for (final e in (w['ereignisse']! as List).cast<Map>()) _ereignisAus(e),
    ],
  );

  final List<Gedcomperson> personen;
  final List<Kante> kanten;
  final List<Ereignisangaben> ereignisse;

  @override
  String get art => 'gedcomUebernehmen';

  @override
  Map<String, Object?> get werte => {
    'personen': [
      for (final p in personen)
        {
          'id': p.id,
          'name': p.name,
          'geschlecht': p.geschlecht == null
              ? null
              : geschlechtZuText(p.geschlecht!),
          'geburt': p.geburt?.toIso8601String(),
          'tod': p.tod?.toIso8601String(),
        },
    ],
    'kanten': [for (final k in kanten) _kanteAlsWerte(k)],
    'ereignisse': [for (final e in ereignisse) _ereignisAlsWerte(e)],
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.uebernehmeGedcom(
    personen: [
      for (final p in personen)
        PeopleCompanion.insert(
          id: p.id,
          name: p.name,
          geschlecht: Value(
            p.geschlecht == null ? null : geschlechtZuText(p.geschlecht!),
          ),
          geburtsdatum: Value(p.geburt),
          sterbedatum: Value(p.tod),
        ),
    ],
    kanten: kanten,
    ereignisse: [for (final e in ereignisse) _ereignisZeile(e)],
  );
}

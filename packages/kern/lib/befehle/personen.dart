part of 'befehl.dart';

/// Eine neue Person; die Kennung vergibt, wer den Befehl erzeugt.
final class PersonAnlegen extends Befehl<void> {
  const PersonAnlegen(this.personId, this.name);

  static PersonAnlegen aus(Map<String, Object?> w) =>
      PersonAnlegen(w['personId']! as String, w['name']! as String);

  final String personId;
  final String name;

  @override
  String get art => 'personAnlegen';

  @override
  Map<String, Object?> get werte => {'personId': personId, 'name': name};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.createPerson(PeopleCompanion.insert(id: personId, name: name));
}

/// Gesichter einer Person zuordnen.
final class GesichterZuordnen extends Befehl<void> {
  const GesichterZuordnen(this.gesichtIds, this.personId);

  static GesichterZuordnen aus(Map<String, Object?> w) =>
      GesichterZuordnen(_kennungen(w['gesichtIds']), w['personId']! as String);

  final List<String> gesichtIds;
  final String personId;

  @override
  String get art => 'gesichterZuordnen';

  @override
  Map<String, Object?> get werte => {
    'gesichtIds': gesichtIds,
    'personId': personId,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.assignFacesToPerson(gesichtIds, personId);
}

/// Zwei Personen sind dieselbe: [entfernen] geht in [behalten] auf.
final class PersonenZusammenfuehren extends Befehl<void> {
  const PersonenZusammenfuehren({
    required this.behalten,
    required this.entfernen,
  });

  static PersonenZusammenfuehren aus(Map<String, Object?> w) =>
      PersonenZusammenfuehren(
        behalten: w['behalten']! as String,
        entfernen: w['entfernen']! as String,
      );

  final String behalten;
  final String entfernen;

  @override
  String get art => 'personenZusammenfuehren';

  @override
  Map<String, Object?> get werte => {
    'behalten': behalten,
    'entfernen': entfernen,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.mergePeople(keepPersonId: behalten, removePersonId: entfernen);
}

/// Das Profilbild einer Person: der Ausschnitt eines ihrer Gesichter.
final class PersonTitelbildSetzen extends Befehl<void> {
  const PersonTitelbildSetzen(this.personId, this.ausschnitt);

  static PersonTitelbildSetzen aus(Map<String, Object?> w) =>
      PersonTitelbildSetzen(
        w['personId']! as String,
        w['ausschnitt']! as String,
      );

  final String personId;

  /// Pfad des Gesichtsausschnitts, relativ zur Bibliothek.
  final String ausschnitt;

  @override
  String get art => 'personTitelbildSetzen';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'ausschnitt': ausschnitt,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setPersonCover(personId, ausschnitt);
}

/// Gesichter beiseitelegen oder zurückholen.
final class GesichterBeiseitelegen extends Befehl<void> {
  const GesichterBeiseitelegen(this.gesichtIds, this.beiseite);

  static GesichterBeiseitelegen aus(Map<String, Object?> w) =>
      GesichterBeiseitelegen(
        _kennungen(w['gesichtIds']),
        w['beiseite']! as bool,
      );

  final List<String> gesichtIds;
  final bool beiseite;

  @override
  String get art => 'gesichterBeiseitelegen';

  @override
  Map<String, Object?> get werte => {
    'gesichtIds': gesichtIds,
    'beiseite': beiseite,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setFacesIgnored(gesichtIds, beiseite);
}

/// Ein Gesicht wieder ohne Namen.
final class ZuordnungLoesen extends Befehl<void> {
  const ZuordnungLoesen(this.gesichtId);

  static ZuordnungLoesen aus(Map<String, Object?> w) =>
      ZuordnungLoesen(w['gesichtId']! as String);

  final String gesichtId;

  @override
  String get art => 'zuordnungLoesen';

  @override
  Map<String, Object?> get werte => {'gesichtId': gesichtId};

  @override
  Future<void> anwenden(AppDatabase db) => db.loeseZuordnung(gesichtId);
}

/// Eine Erkennung löschen – der Rahmen war kein Gesicht (Issue #191).
///
/// Anders als [GesichterBeiseitelegen] verschwindet sie ganz. Ein Befehl,
/// damit es auch am verbundenen Rechner, im Browser und auf dem Handy geht
/// – deren Kopien dürfen nicht selbst löschen. Gibt den Pfad des
/// Ausschnitts zurück; die Datei räumt der auf, der die Bibliothek hält.
final class GesichtLoeschen extends Befehl<String?> {
  const GesichtLoeschen(this.gesichtId);

  static GesichtLoeschen aus(Map<String, Object?> w) =>
      GesichtLoeschen(w['gesichtId']! as String);

  final String gesichtId;

  @override
  String get art => 'gesichtLoeschen';

  @override
  Map<String, Object?> get werte => {'gesichtId': gesichtId};

  @override
  Future<String?> anwenden(AppDatabase db) => db.loescheGesicht(gesichtId);
}

/// Das Rückgängig einer Zuordnung: jedes Gesicht zurück in seinen Stand,
/// die Rückmeldungen seit [rueckmeldungenSeit] weg, eine eigens angelegte
/// Person wieder weg.
final class ZuordnungZuruecknehmen extends Befehl<void> {
  const ZuordnungZuruecknehmen({
    required this.gesichter,
    required this.personId,
    required this.personWarNeu,
    required this.titelbildVorher,
    required this.rueckmeldungenSeit,
    required this.allgemeineSchwelle,
  });

  static ZuordnungZuruecknehmen aus(Map<String, Object?> w) =>
      ZuordnungZuruecknehmen(
        gesichter: [
          for (final g in (w['gesichter']! as List).cast<Map>())
            (
              id: g['id']! as String,
              personId: g['personId'] as String?,
              ignoriert: g['ignoriert']! as bool,
            ),
        ],
        personId: w['personId']! as String,
        personWarNeu: w['personWarNeu']! as bool,
        titelbildVorher: w['titelbildVorher'] as String?,
        rueckmeldungenSeit: _zeitOderNichts(w['rueckmeldungenSeit']),
        allgemeineSchwelle: (w['allgemeineSchwelle']! as num).toDouble(),
      );

  final List<Gesichtsstand> gesichter;
  final String personId;
  final bool personWarNeu;
  final String? titelbildVorher;
  final DateTime? rueckmeldungenSeit;
  final double allgemeineSchwelle;

  @override
  String get art => 'zuordnungZuruecknehmen';

  @override
  Map<String, Object?> get werte => {
    'gesichter': [
      for (final g in gesichter)
        {'id': g.id, 'personId': g.personId, 'ignoriert': g.ignoriert},
    ],
    'personId': personId,
    'personWarNeu': personWarNeu,
    'titelbildVorher': titelbildVorher,
    'rueckmeldungenSeit': rueckmeldungenSeit?.toIso8601String(),
    'allgemeineSchwelle': allgemeineSchwelle,
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.nimmZuordnungZurueck(
    gesichter: gesichter,
    personId: personId,
    personWarNeu: personWarNeu,
    titelbildVorher: titelbildVorher,
    rueckmeldungenSeit: rueckmeldungenSeit,
    allgemeineSchwelle: allgemeineSchwelle,
  );
}

/// Was der Nutzer zu Vorschlägen gesagt hat, für die lernende
/// Wiedererkennung; liefert den Zeitpunkt der Rückmeldungen (für das
/// Rückgängig).
final class GesichtsEntscheidungenMerken extends Befehl<DateTime?> {
  const GesichtsEntscheidungenMerken(
    this.personId,
    this.entscheidungen, {
    required this.allgemeineSchwelle,
  });

  static GesichtsEntscheidungenMerken aus(Map<String, Object?> w) =>
      GesichtsEntscheidungenMerken(w['personId']! as String, [
        for (final e in (w['entscheidungen']! as List).cast<Map>())
          (
            faceId: e['faceId']! as String,
            accepted: e['accepted']! as bool,
            similarity: (e['similarity']! as num).toDouble(),
          ),
      ], allgemeineSchwelle: (w['allgemeineSchwelle']! as num).toDouble());

  final String personId;
  final List<({String faceId, bool accepted, double similarity})>
  entscheidungen;
  final double allgemeineSchwelle;

  @override
  String get art => 'gesichtsEntscheidungenMerken';

  @override
  Map<String, Object?> get werte => {
    'personId': personId,
    'entscheidungen': [
      for (final e in entscheidungen)
        {
          'faceId': e.faceId,
          'accepted': e.accepted,
          'similarity': e.similarity,
        },
    ],
    'allgemeineSchwelle': allgemeineSchwelle,
  };

  @override
  Future<DateTime?> anwenden(AppDatabase db) => db.merkeGesichtsEntscheidungen(
    personId,
    entscheidungen,
    allgemeineSchwelle: allgemeineSchwelle,
  );
}

/// Die gelernten Rückmeldungen einer Person vergessen.
final class GesichtsEntscheidungenVergessen extends Befehl<void> {
  const GesichtsEntscheidungenVergessen(this.personId);

  static GesichtsEntscheidungenVergessen aus(Map<String, Object?> w) =>
      GesichtsEntscheidungenVergessen(w['personId']! as String);

  final String personId;

  @override
  String get art => 'gesichtsEntscheidungenVergessen';

  @override
  Map<String, Object?> get werte => {'personId': personId};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.vergissGesichtsEntscheidungen(personId);
}

/// Vorschläge der Wiedererkennung ablehnen.
final class VorschlaegeVerwerfen extends Befehl<void> {
  const VorschlaegeVerwerfen(this.gesichtIds);

  static VorschlaegeVerwerfen aus(Map<String, Object?> w) =>
      VorschlaegeVerwerfen(_kennungen(w['gesichtIds']));

  final List<String> gesichtIds;

  @override
  String get art => 'vorschlaegeVerwerfen';

  @override
  Map<String, Object?> get werte => {'gesichtIds': gesichtIds};

  @override
  Future<void> anwenden(AppDatabase db) => db.verwirfVorschlaege(gesichtIds);
}

/// Ein Foto von der Gesichtssuche ausnehmen (oder wieder aufnehmen).
final class GesichtssucheAusnehmen extends Befehl<void> {
  const GesichtssucheAusnehmen(this.id, this.ausgenommen);

  static GesichtssucheAusnehmen aus(Map<String, Object?> w) =>
      GesichtssucheAusnehmen(w['id']! as String, w['ausgenommen']! as bool);

  final String id;
  final bool ausgenommen;

  @override
  String get art => 'gesichtssucheAusnehmen';

  @override
  Map<String, Object?> get werte => {'id': id, 'ausgenommen': ausgenommen};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeGesichtssucheAusgenommen(id, ausgenommen);
}

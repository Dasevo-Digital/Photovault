part of '../database.dart';

/// Stammbaum und Lebensereignisse.
extension StammbaumAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Stammbaum (siehe services/stammbaum.dart)
  // -----------------------------------------------------------------------

  /// Alle Verwandtschaften. Als vollständige Liste und nicht je Person
  /// abgefragt: Der Stammbaum braucht für seine Hinweise („hat noch Eltern")
  /// ohnehin die Nachbarschaft der Nachbarn, und die Tabelle bleibt selbst
  /// bei einer sehr großen Familie klein gegenüber allem anderen hier.
  Stream<List<PersonBeziehungenData>> watchBeziehungen() =>
      select(personBeziehungen).watch();

  Future<List<PersonBeziehungenData>> alleBeziehungen() =>
      select(personBeziehungen).get();

  /// Trägt eine Verwandtschaft ein.
  ///
  /// Die Prüfung läuft hier und nicht nur in der Oberfläche: Ein Kreis
  /// („jemand ist sein eigener Urgroßvater") ließe jede Auswertung nach
  /// oben endlos laufen, und das wäre nach dem Speichern nicht mehr
  /// bequem zu heilen. Gibt den Grund zurück, wenn nichts eingetragen
  /// wurde.
  Future<Beziehungsfehler?> fuegeBeziehungHinzu(
    String personId,
    String andereId,
    Verwandtschaft art,
  ) async {
    final netz = Verwandtschaftsnetz(await _kanten());
    final fehler = pruefeBeziehung(netz, personId, andereId, art);
    if (fehler != null) return fehler;
    final k = art == Verwandtschaft.partner
        ? partnerKanteFuer(personId, andereId)
        : kante(personId, andereId, art);
    await into(personBeziehungen).insert(
      PersonBeziehungenCompanion.insert(
        personId: k.personId,
        andereId: k.andereId,
        art: artZuText(k.art),
      ),
    );
    return null;
  }

  /// Trägt mehrere Verwandtschaften auf einmal ein – für die Grade, die
  /// über eine Zwischenperson entstehen (siehe verwandte_anlegen.dart).
  ///
  /// In einer Transaktion, weil ein Geschwisterkind an beiden Eltern
  /// gleichzeitig hängt: Bräche der zweite Eintrag ab, stünde ein
  /// Halbgeschwisterkind im Baum, das nie jemand so gemeint hat.
  ///
  /// Die Prüfung läuft je Kante gegen den **fortgeschriebenen** Stand, nicht
  /// gegen den Anfangszustand – sonst könnten zwei Kanten eines Aufrufs
  /// gemeinsam einen Kreis schliessen, den keine für sich geschlossen hätte.
  ///
  /// Gibt den ersten Grund zurück, an dem es scheiterte; dann wurde nichts
  /// geschrieben.
  Future<Beziehungsfehler?> fuegeBeziehungenHinzu(List<Kante> kanten) async {
    if (kanten.isEmpty) return null;
    try {
      await transaction(() async {
        final gesammelt = <Kante>[...await _kanten()];
        for (final k in kanten) {
          final netz = Verwandtschaftsnetz(gesammelt);
          final fehler = pruefeBeziehung(netz, k.personId, k.andereId, k.art);
          // Der Wurf rollt die Transaktion zurück und macht damit auch die
          // bereits eingefügten Kanten dieses Aufrufs rückgängig.
          if (fehler != null) throw _BeziehungAbbruch(fehler);
          final fest = k.art == Verwandtschaft.partner
              ? partnerKanteFuer(k.personId, k.andereId)
              : k;
          await into(personBeziehungen).insert(
            PersonBeziehungenCompanion.insert(
              personId: fest.personId,
              andereId: fest.andereId,
              art: artZuText(fest.art),
            ),
          );
          gesammelt.add(fest);
        }
      });
      return null;
    } on _BeziehungAbbruch catch (e) {
      return e.grund;
    }
  }

  /// Entfernt eine Verwandtschaft. Bei Partnerschaften ist die
  /// Eingaberichtung gleichgültig – gespeichert ist nur eine Zeile.
  ///
  /// Bei einer Elternverbindung wird die Art **nicht** mitverglichen: Zwei
  /// Menschen können nur auf genau eine Weise Eltern und Kind sein (das
  /// stellt [pruefeBeziehung] sicher), also ist „löse diese
  /// Elternverbindung" auch ohne die Art eindeutig.
  ///
  /// Vorher stand hier ein Vergleich auf die genaue Art – und die
  /// Oberfläche übergab für jede Elternreihe fest „leiblich". Bei einem
  /// Adoptiv- oder Pflegeelternteil traf die Bedingung deshalb keine
  /// Zeile: Es passierte nichts, ohne Fehler, ohne Hinweis.
  ///
  /// Gibt zurück, ob tatsächlich etwas entfernt wurde. Ein Aufrufer, der
  /// ins Leere greift, soll das erfahren können statt es zu vermuten.
  Future<bool> entferneBeziehung(
    String personId,
    String andereId,
    Verwandtschaft art,
  ) async {
    final k = art == Verwandtschaft.partner
        ? partnerKanteFuer(personId, andereId)
        : kante(personId, andereId, art);
    final betroffen =
        await (delete(personBeziehungen)..where((t) {
              final gleicheStelle =
                  t.personId.equals(k.personId) & t.andereId.equals(k.andereId);
              return istElternArt(k.art)
                  ? gleicheStelle &
                        t.art.isIn([for (final e in elternArten) artZuText(e)])
                  : gleicheStelle & t.art.equals(artZuText(k.art));
            }))
            .go();
    return betroffen > 0;
  }

  /// Ändert die Art einer bestehenden Elternverbindung – aus „leiblich"
  /// wird „Adoptiv", ohne die Verbindung erst zu lösen und neu zu legen.
  ///
  /// Die Art steht im Primärschlüssel, deshalb ist es kein einfaches
  /// Ändern der Spalte, sondern Entfernen und Neuanlegen – beides in einer
  /// Transaktion, damit die Verbindung nie zwischendurch fehlt.
  ///
  /// Gibt zurück, ob es die Verbindung überhaupt gab.
  Future<bool> aendereElternart(
    String kindId,
    String elternteilId,
    Verwandtschaft neueArt,
  ) async {
    if (!istElternArt(neueArt)) return false;
    return transaction(() async {
      final entfernt = await entferneBeziehung(kindId, elternteilId, neueArt);
      if (!entfernt) return false;
      await into(personBeziehungen).insert(
        PersonBeziehungenCompanion.insert(
          personId: kindId,
          andereId: elternteilId,
          art: artZuText(neueArt),
        ),
      );
      return true;
    });
  }

  Future<List<Kante>> _kanten() async {
    final zeilen = await alleBeziehungen();
    return [
      for (final z in zeilen)
        if (artAusText(z.art) case final art?)
          kante(z.personId, z.andereId, art),
    ];
  }

  /// Hängt alle Kanten von [vonId] auf [aufId] um – für [mergePeople].
  ///
  /// Kanten, die dabei zur Selbstbeziehung würden (die beiden waren
  /// miteinander verwandt eingetragen), fallen weg statt einen Kreis zu
  /// bilden. Doppelte ebenfalls: `insertOnConflictUpdate` würde die
  /// bestehende Zeile nur mit sich selbst überschreiben.
  Future<void> _uebertrageBeziehungen(String vonId, String aufId) async {
    final betroffen = await (select(
      personBeziehungen,
    )..where((t) => t.personId.equals(vonId) | t.andereId.equals(vonId))).get();
    await (delete(
      personBeziehungen,
    )..where((t) => t.personId.equals(vonId) | t.andereId.equals(vonId))).go();
    for (final z in betroffen) {
      final art = artAusText(z.art);
      if (art == null) continue;
      final person = z.personId == vonId ? aufId : z.personId;
      final andere = z.andereId == vonId ? aufId : z.andereId;
      if (person == andere) continue;
      final k = art == Verwandtschaft.partner
          ? partnerKanteFuer(person, andere)
          : kante(person, andere, art);
      await into(personBeziehungen).insert(
        PersonBeziehungenCompanion.insert(
          personId: k.personId,
          andereId: k.andereId,
          art: artZuText(k.art),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  // -----------------------------------------------------------------------
  // Lebensereignisse (siehe services/lebenslauf.dart)
  // -----------------------------------------------------------------------

  Stream<List<LebensereignisseData>> watchEreignisse(String personId) =>
      (select(
        lebensereignisse,
      )..where((t) => t.personId.equals(personId))).watch();

  Future<void> fuegeEreignisHinzu(LebensereignisseCompanion ereignis) =>
      into(lebensereignisse).insert(ereignis);

  Future<void> loescheEreignis(String id) =>
      (delete(lebensereignisse)..where((t) => t.id.equals(id))).go();

  /// Übernimmt eine eingelesene GEDCOM-Datei – Personen, Ereignisse und
  /// Verwandtschaften in einem Zug.
  ///
  /// In **einer** Transaktion, weil eine halb eingelesene Datei der
  /// schlechteste aller Zustände wäre: Personen ohne ihre
  /// Verwandtschaften sehen aus wie richtige Einträge, und niemand
  /// könnte hinterher sagen, wo der Abbruch war.
  ///
  /// Die Kanten laufen hier **nicht** noch einmal durch
  /// [pruefeBeziehung], anders als bei [fuegeBeziehungenHinzu]. Zwei
  /// Gründe: Der Einleser hat die Datei bereits gegen Kreise geprüft
  /// (siehe `gedcom_import.dart`), und jede Person dieser Datei wird
  /// **neu** angelegt – eine Kante zwischen zwei frischen Kennungen kann
  /// mit dem Bestand keinen Kreis bilden, weil sie ihn nirgends berührt.
  /// Die Prüfung je Kante gegen den fortgeschriebenen Stand wäre bei
  /// dreitausend Personen ausserdem quadratisch.
  Future<void> uebernehmeGedcom({
    required List<PeopleCompanion> personen,
    required List<Kante> kanten,
    required List<LebensereignisseCompanion> ereignisse,
  }) => transaction(() async {
    await batch((b) {
      b.insertAll(people, personen);
      b.insertAll(lebensereignisse, ereignisse);
      b.insertAll(personBeziehungen, [
        for (final k in kanten)
          PersonBeziehungenCompanion.insert(
            personId: k.personId,
            andereId: k.andereId,
            art: artZuText(k.art),
          ),
      ]);
    });
  });

  /// Ereignisse mit Ortsnamen, aber noch ohne Koordinate.
  ///
  /// Die Grundlage für das einmalige Nachtragen (siehe
  /// `LibraryState.trageEreignisorteNach`). Bewusst nur die ohne
  /// Koordinate: Ein von Hand berichtigter Punkt darf nicht bei jedem
  /// Start wieder überschrieben werden.
  Future<List<LebensereignisseData>> ereignisseOhneKoordinate() =>
      (select(lebensereignisse)..where(
            (t) =>
                t.ort.isNotNull() &
                t.ort.equals('').not() &
                t.ortBreite.isNull(),
          ))
          .get();

  /// Alle Ereignisse, die auf einer Karte darstellbar sind.
  Future<List<LebensereignisseData>> ereignisseMitKoordinate() =>
      (select(lebensereignisse)..where((t) => t.ortBreite.isNotNull())).get();

  /// Alle verorteten Ereignisse der Bibliothek, samt Personennamen –
  /// für die allgemeine Karte, die keine Familie eingrenzt.
  Future<List<({LebensereignisseData ereignis, String personName})>>
  ereignisseMitKoordinateUndName() async {
    final abfrage = select(lebensereignisse).join([
      innerJoin(people, people.id.equalsExp(lebensereignisse.personId)),
    ])..where(lebensereignisse.ortBreite.isNotNull());
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        (
          ereignis: z.readTable(lebensereignisse),
          personName: z.readTable(people).name,
        ),
    ];
  }

  /// Verortete Ereignisse bestimmter Personen, samt deren Namen.
  ///
  /// Der Name kommt gleich mit: Ein Punkt auf der Familienkarte ohne die
  /// Person, zu der er gehört, beantwortet keine Frage.
  Future<List<({LebensereignisseData ereignis, String personName})>>
  verorteteEreignisseFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return const [];
    final abfrage =
        select(lebensereignisse).join([
          innerJoin(people, people.id.equalsExp(lebensereignisse.personId)),
        ])..where(
          lebensereignisse.ortBreite.isNotNull() &
              lebensereignisse.personId.isIn(personIds),
        );
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        (
          ereignis: z.readTable(lebensereignisse),
          personName: z.readTable(people).name,
        ),
    ];
  }
}

/// Bricht [AppDatabase.fuegeBeziehungenHinzu] ab und rollt die Transaktion
/// zurück. Rein intern – nach aussen wird daraus wieder ein
/// [Beziehungsfehler].
class _BeziehungAbbruch implements Exception {
  final Beziehungsfehler grund;
  const _BeziehungAbbruch(this.grund);
}

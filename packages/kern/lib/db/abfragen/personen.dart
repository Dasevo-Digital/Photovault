part of '../database.dart';

/// Personen, Gesichter und die lernende Wiedererkennung.
extension PersonenAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Personen / Gesichter
  // -----------------------------------------------------------------------

  Stream<List<PersonData>> watchPeople() => select(people).watch();

  /// Dasselbe als einmalige Abfrage – siehe [alleTags].
  Future<List<PersonData>> allePersonen() => select(people).get();

  /// Wie viele Personen angelegt sind – für die Zahl am Reiter.
  ///
  /// Als Zählung und nicht über [watchPeople]: Ein zweiter Beobachter auf
  /// derselben Tabelle würde bei jeder Zuordnung den ganzen Bildschirm neu
  /// aufbauen, samt der 200 Gesichtskacheln darunter – genau das, was das
  /// stückweise Entfernen im Raster gerade vermeidet.
  /// Wie viele Aufnahmen jede Person zeigt (Gesichter je Aufnahme einmal
  /// gezählt), nach Kennung – für Listen, die keine Kopie halten.
  Future<Map<String, int>> personenAnzahlen() async {
    final n = faces.assetId.count(distinct: true);
    final q =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([faces.personId, n])
          ..where(
            faces.personId.isNotNull() &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..groupBy([faces.personId]);
    return {for (final z in await q.get()) z.read(faces.personId)!: z.read(n)!};
  }

  Future<int> countPeople() async {
    final anzahl = people.id.count();
    final row = await (selectOnly(people)..addColumns([anzahl])).getSingle();
    return row.read(anzahl) ?? 0;
  }

  Stream<PersonData?> watchPerson(String id) =>
      (select(people)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> createPerson(PeopleCompanion person) =>
      into(people).insert(person);

  Future<void> insertFace(FacesCompanion face) => into(faces).insert(face);

  /// Unbenannte Gesichter für den "Unbenannte Gesichter"-Tab – über einen
  /// Join gegen Assets gefiltert, damit Gesichter aus gelöschten oder
  /// gesperrten Fotos dort nicht auftauchen (sonst würde ein Foto-Crop aus
  /// dem gesperrten Ordner beiläufig sichtbar, obwohl das zugehörige Foto
  /// selbst versteckt ist).
  Future<List<FaceData>> unassignedFaces({int limit = 200}) async {
    final query =
        select(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..where(
            faces.personId.isNull() &
                faces.isIgnored.equals(false) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Unlimitierte Variante von [unassignedFaces] – ein vollständiger
  /// Clustering-Lauf (siehe face_clustering_service.dart) braucht alle
  /// unzugeordneten Gesichter, nicht nur die ersten 200 (Standard-Limit für
  /// die Rasteransicht im "Unbenannte Gesichter"-Tab).
  Future<List<FaceData>> allUnassignedFaces() async {
    final query =
        select(
          faces,
        ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])..where(
          faces.personId.isNull() &
              faces.isIgnored.equals(false) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false),
        );
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Beiseitegelegte Gesichter für den Tab „Ignoriert" – dieselbe
  /// Absicherung über Assets wie [unassignedFaces], damit auch hier kein
  /// Ausschnitt aus einem gesperrten Foto sichtbar wird.
  Future<List<FaceData>> ignoredFaces({int limit = 200}) async {
    final query =
        select(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..where(
            faces.isIgnored.equals(true) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Wie viele Gesichter insgesamt beiseitegelegt sind – für die Zahl am
  /// Tab, damit auch jenseits des Anzeigelimits von 200 ersichtlich ist,
  /// wie viel dort liegt.
  Future<int> ignoredFacesCount() async {
    final anzahl = faces.id.count();
    final query =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([anzahl])
          ..where(
            faces.isIgnored.equals(true) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          );
    final row = await query.getSingle();
    return row.read(anzahl) ?? 0;
  }

  /// Löscht eine einzelne Erkennung und liefert den Pfad ihres
  /// Ausschnitts, damit der Aufrufer die Datei mit wegräumen kann.
  ///
  /// Für den offensichtlichen Fehlgriff der Erkennung, den man direkt im
  /// Foto sieht. Wie jedes Löschen ist auch das nicht dauerhaft – der
  /// nächste Scan findet die Stelle wieder. Wer sie loswerden will, legt
  /// sie beiseite (siehe [Faces.isIgnored]).
  Future<String?> loescheGesicht(String faceId) async {
    final vorher = await (select(
      faces,
    )..where((t) => t.id.equals(faceId))).getSingleOrNull();
    if (vorher == null) return null;
    await (delete(faces)..where((t) => t.id.equals(faceId))).go();
    return vorher.cropRelativePath;
  }

  /// Nimmt einem Gesicht seine Person, ohne es zu löschen – es landet
  /// wieder unter „Unbenannte Gesichter".
  ///
  /// Für die falsch zugeordnete Erkennung: Sie zu löschen wäre zu viel
  /// (die Stelle IST ein Gesicht), sie beiseitezulegen auch (man will sie
  /// ja richtig benennen).
  Future<void> loeseZuordnung(String faceId) =>
      (update(faces)..where((t) => t.id.equals(faceId))).write(
        const FacesCompanion(personId: Value(null)),
      );

  /// Legt alle noch unbenannten Gesichter auf einen Schlag beiseite und
  /// liefert, wie viele es waren.
  ///
  /// Für den Fall, dass die Erkennung überwiegend Unbrauchbares gefunden
  /// hat – Plakate, Statuen, Passanten. Von Hand wären das hunderte Klicks;
  /// danach holt man sich unter „Ignoriert" die wenigen zurück, die man
  /// wirklich benennen will.
  ///
  /// Bereits benannte Gesichter bleiben unberührt: Sie sind ja gerade das
  /// Ergebnis der Arbeit, die hier nicht verloren gehen darf.
  Future<int> ignoriereAlleUnbenannten() async {
    final betroffen = await allUnassignedFaces();
    if (betroffen.isEmpty) return 0;
    await setFacesIgnored([for (final f in betroffen) f.id], true);
    return betroffen.length;
  }

  /// Löscht alle unbenannten Erkennungen und liefert ihre Zahl sowie die
  /// Pfade ihrer Ausschnitte, damit der Aufrufer auch die Dateien wegräumen
  /// kann.
  ///
  /// Beides getrennt, weil es nicht dasselbe ist: Ein Gesicht ohne
  /// Embedding-Modell bekommt zwar eine Zeile, aber nicht zwangsläufig
  /// einen Ausschnitt. Die Pfade zu zählen und das Ergebnis als Zahl der
  /// gelöschten Erkennungen zu melden, ergäbe eine zu kleine Zahl.
  ///
  /// Anders als das Beiseitelegen ist das **nicht dauerhaft**: Der nächste
  /// Gesichts-Scan findet dieselben Stellen wieder und legt sie neu an.
  /// Dafür wird der Platz auf der Platte frei. Wer die Erkennungen
  /// endgültig loswerden will, legt sie beiseite – siehe
  /// [ignoriereAlleUnbenannten].
  ///
  /// Beiseitegelegte werden mitgelöscht: Wer „alle Erkennungen löschen"
  /// wählt, meint auch die, die schon aussortiert waren.
  Future<({int anzahl, List<String> pfade})>
  loescheAlleUnbenanntenErkennungen() async {
    final query =
        select(
          faces,
        ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])..where(
          faces.personId.isNull() &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false),
        );
    final betroffen = (await query.get())
        .map((r) => r.readTable(faces))
        .toList();
    if (betroffen.isEmpty) return (anzahl: 0, pfade: const <String>[]);
    await (delete(
      faces,
    )..where((t) => t.id.isIn([for (final f in betroffen) f.id]))).go();
    return (
      anzahl: betroffen.length,
      pfade: [
        for (final f in betroffen)
          if (f.cropRelativePath != null) f.cropRelativePath!,
      ],
    );
  }

  /// Wie viele unbenannte Erkennungen es insgesamt gibt – für die Zahlen in
  /// der Rückfrage, die über das Anzeigelimit von 200 hinausgeht.
  Future<int> unassignedFacesCount() async {
    final anzahl = faces.id.count();
    final query =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([anzahl])
          ..where(
            faces.personId.isNull() &
                faces.isIgnored.equals(false) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          );
    return (await query.getSingle()).read(anzahl) ?? 0;
  }

  /// Legt Gesichter beiseite bzw. holt sie zurück.
  ///
  /// Beim Beiseitelegen wird eine bestehende Personen-Zuordnung entfernt:
  /// Ein Gesicht, das noch als „Anna" zählte und zugleich ignoriert wäre,
  /// hinge zwischen beiden Zuständen – es erschiene weiter in Annas Fotos,
  /// wäre aber unter „Ignoriert" gelistet.
  Future<void> setFacesIgnored(List<String> faceIds, bool ignoriert) async {
    if (faceIds.isEmpty) return;
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      FacesCompanion(
        isIgnored: Value(ignoriert),
        personId: ignoriert ? const Value(null) : const Value.absent(),
      ),
    );
  }

  /// Alle erkannten (und ggf. manuell hinzugefügten) Gesichter eines
  /// einzelnen Fotos – für die Foto-Detailansicht mit Gesichts-Overlay.
  Future<List<FaceData>> facesForAsset(String assetId) =>
      (select(faces)..where((t) => t.assetId.equals(assetId))).get();

  /// Für die Bibliotheks-Integritätsprüfung – ein einzelner Full-Table-Select
  /// statt N+1-Abfragen pro Asset.
  Future<List<FaceData>> allFaces() => select(faces).get();

  /// Alle Gesichter, die bereits einer bestimmten Person zugeordnet sind –
  /// z.B. um in der Personen-Detailansicht ein anderes Profilbild auswählen
  /// zu lassen. Ebenfalls ohne gelöschte/gesperrte Fotos (siehe
  /// [unassignedFaces]), sonst ließe sich darüber ein Profilbild aus einem
  /// gesperrten Foto auswählen.
  /// Alle Einbettungen zugeordneter Gesichter, in EINER Abfrage.
  ///
  /// Für den Personenvorschlag. [facesForPerson] daneben zu benutzen hiesse
  /// eine Abfrage je Person – bei 39 Personen also 39 Abfragen, jedes Mal,
  /// wenn jemand ein Gesicht antippt. An der gewachsenen Bibliothek sind es
  /// so 2060 Zeilen zu je 512 Byte, zusammen ein Megabyte.
  ///
  /// Gesperrte und gelöschte Aufnahmen bleiben draussen – aus demselben
  /// Grund wie bei [facesForPerson]: Sonst schlüge die App einen Namen vor,
  /// der aus einem Foto stammt, das der Benutzer gerade weggeschlossen hat.
  Future<List<({String personId, Uint8List vektor})>>
  einbettungenZugeordneterGesichter() async {
    final abfrage =
        select(
          faces,
        ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])..where(
          faces.personId.isNotNull() &
              faces.embedding.isNotNull() &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false),
        );
    final zeilen = await abfrage.get();
    return [
      for (final z in zeilen)
        if (z.readTable(faces) case final f
            when f.personId != null && f.embedding != null)
          (personId: f.personId!, vektor: f.embedding!),
    ];
  }

  Future<List<FaceData>> facesForPerson(String personId) async {
    final query =
        select(
          faces,
        ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])..where(
          faces.personId.equals(personId) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false),
        );
    final rows = await query.get();
    return rows.map((r) => r.readTable(faces)).toList();
  }

  /// Benannte Personen, die auf diesem Foto erkannt wurden (über die
  /// zugeordneten Gesichter) – für die "Personen"-Sektion der Info-Ansicht.
  Future<List<PersonData>> peopleForAsset(String assetId) async {
    final query = select(people).join([
      innerJoin(faces, faces.personId.equalsExp(people.id)),
    ])..where(faces.assetId.equals(assetId));
    final rows = await query.get();
    final seen = <String>{};
    final result = <PersonData>[];
    for (final row in rows) {
      final person = row.readTable(people);
      if (seen.add(person.id)) result.add(person);
    }
    return result;
  }

  /// Gesichter ohne berechnete Schärfe – für den Nachlauf nach Schema 61.
  ///
  /// Nur solche mit gespeichertem Ausschnitt: Ohne ihn gäbe es nichts zu
  /// messen, und sie stünden bei jedem Lauf erneut in der Liste.
  Future<List<FaceData>> gesichterOhneSchaerfe() async {
    final zeilen = await (select(faces).join([
      innerJoin(assets, assets.id.equalsExp(faces.assetId)),
    ])..where(_schaerfeOffen)).get();
    return [for (final z in zeilen) z.readTable(faces)];
  }

  /// Zählvariante von [gesichterOhneSchaerfe].
  Future<int> countGesichterOhneSchaerfe() async {
    final abfrage =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([faces.id.count()])
          ..where(_schaerfeOffen);
    final zeile = await abfrage.getSingle();
    return zeile.read(faces.id.count()) ?? 0;
  }

  /// Wessen Schärfe noch aussteht.
  ///
  /// **Gesperrte Aufnahmen bleiben draussen.** Ihr Ausschnitt liegt als
  /// Chiffrat auf der Platte; `decodeImage` gibt dafür `null` zurück, der
  /// Wert bliebe leer, und die Aufgabe fände dieselben Gesichter beim
  /// nächsten Lauf wieder. Eine Hintergrundaufgabe, die dauerhaft „noch N
  /// offen" meldet und nie fertig wird, ist schlimmer als eine, die es gar
  /// nicht gibt – und die Zahl gehört ausserdem zu den Auskünften, die der
  /// gesperrte Ordner nicht geben soll.
  Expression<bool> get _schaerfeOffen =>
      faces.schaerfe.isNull() &
      faces.cropRelativePath.isNotNull() &
      assets.isLocked.equals(false);

  /// Trägt einen neu gezeichneten Ausschnitt samt seiner Schärfe ein.
  Future<void> setzeGesichtsausschnitt(
    String faceId,
    String pfad, {
    double? schaerfe,
  }) => (update(faces)..where((f) => f.id.equals(faceId))).write(
    FacesCompanion(
      cropRelativePath: Value(pfad),
      schaerfe: schaerfe == null ? const Value.absent() : Value(schaerfe),
    ),
  );

  Future<void> setzeGesichtsschaerfe(String faceId, double wert) =>
      (update(faces)..where((f) => f.id.equals(faceId))).write(
        FacesCompanion(schaerfe: Value(wert)),
      );

  /// Gesichter, fuer die noch kein Vorschlag gerechnet wurde.
  ///
  /// [alle] nimmt auch die schon geprueften wieder mit – der Weg, nachdem
  /// neue Personen benannt wurden: Ein Gesicht, zu dem es vor einem Monat
  /// keinen Kern gab, kann heute einen haben.
  ///
  /// [beiseite] entscheidet ueber die 14.065 beiseitegelegten. Sie sind
  /// standardmaessig **draussen**: Wer sie weggelegt hat, hat entschieden,
  /// und dieselbe Frage von selbst noch einmal zu stellen waere keine
  /// Hilfe, sondern Widerspruch. Als ausdruecklicher Durchgang lohnt es
  /// sich trotzdem – an der echten Bibliothek liegen dort 960 Gesichter,
  /// die heute ueber der Schwelle einer inzwischen benannten Person
  /// liegen.
  Expression<bool> _wiedererkennungOffen({
    required bool alle,
    required bool beiseite,
  }) =>
      faces.personId.isNull() &
      faces.embedding.isNotNull() &
      (beiseite
          ? const CustomExpression<bool>('1')
          : faces.isIgnored.equals(false)) &
      (alle
          ? const CustomExpression<bool>('1')
          : faces.vorschlagGeprueftAm.isNull());

  Future<List<FaceData>> gesichterFuerWiedererkennung({
    bool alle = false,
    bool beiseite = false,
  }) async {
    final zeilen =
        await (select(faces).join([
              innerJoin(assets, assets.id.equalsExp(faces.assetId)),
            ])..where(
              _wiedererkennungOffen(alle: alle, beiseite: beiseite) &
                  assets.isTrashed.equals(false) &
                  assets.isLocked.equals(false),
            ))
            .get();
    return [for (final z in zeilen) z.readTable(faces)];
  }

  /// Zaehlvariante von [gesichterFuerWiedererkennung].
  Future<int> countWiedererkennungOffen({
    bool alle = false,
    bool beiseite = false,
  }) async =>
      _zaehleGesichter(_wiedererkennungOffen(alle: alle, beiseite: beiseite));

  /// Beiseitegelegte Gesichter, die noch nie mit den benannten Personen
  /// verglichen wurden.
  ///
  /// **Warum das eine eigene Zahl braucht.** Der Lauf nach dem Import
  /// sieht sie nicht an – sie sind entschieden. Wer aber, wie an der
  /// echten Bibliothek, **14.065** Gesichter weggelegt hat, bevor es die
  /// heutigen 45 Personen gab, hat dort 960 liegen, die heute einen Namen
  /// bekommen koennten. [countVorschlaege] meldet davon nichts: Ohne
  /// Durchgang gibt es keinen Vorschlag, und ohne Vorschlag keine Karte –
  /// die Funktion waere genau dort unsichtbar, wo sie gebraucht wird.
  Future<int> countBeiseiteNieVerglichen() => _zaehleGesichter(
    faces.personId.isNull() &
        faces.isIgnored.equals(true) &
        faces.embedding.isNotNull() &
        faces.vorschlagGeprueftAm.isNull(),
  );

  /// Wie viele Vorschlaege auf eine Entscheidung warten – die Zahl fuer
  /// den Gesundheitsbildschirm.
  ///
  /// Beiseitegelegte zaehlen hier **nicht** mit: Sie sind entschieden, und
  /// eine Zahl, die mehr verspricht als die Liste dahinter zeigt, ist
  /// schlimmer als keine (siehe [countOffeneGesichter]).
  Future<int> countVorschlaege({bool beiseite = false}) => _zaehleGesichter(
    faces.personId.isNull() &
        faces.vorschlagPersonId.isNotNull() &
        faces.isIgnored.equals(beiseite),
  );

  Future<int> _zaehleGesichter(Expression<bool> bedingung) async {
    final anzahl = faces.id.count();
    final zeile =
        await (selectOnly(
                faces,
              ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
              ..addColumns([anzahl])
              ..where(
                bedingung &
                    assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false),
              ))
            .getSingle();
    return zeile.read(anzahl) ?? 0;
  }

  /// Schreibt das Ergebnis eines Wiedererkennungslaufs.
  ///
  /// **In einem Zug und nicht je Gesicht.** Bei den Ortsnamen kostete das
  /// einzeln 2131 ms gegen 139 ms in Bloecken; hier geht es um
  /// zehntausende Zeilen. Die Marke [Faces.vorschlagGeprueftAm] wird auch
  /// dort gesetzt, wo nichts gefunden wurde – sonst begaenne der naechste
  /// Lauf wieder von vorn.
  Future<void> merkeVorschlaege(
    List<({String faceId, String? personId, double? wert})> ergebnisse, {
    DateTime? jetzt,
  }) async {
    if (ergebnisse.isEmpty) return;
    final zeitpunkt = jetzt ?? DateTime.now();
    await batch((b) {
      for (final e in ergebnisse) {
        b.update(
          faces,
          FacesCompanion(
            vorschlagPersonId: Value(e.personId),
            vorschlagWert: Value(e.wert),
            vorschlagGeprueftAm: Value(zeitpunkt),
          ),
          where: (t) => t.id.equals(e.faceId),
        );
      }
    });
  }

  /// Die wartenden Vorschlaege, nach Person gebuendelt und nach Menge
  /// sortiert.
  Future<List<({PersonData person, int anzahl})>> vorschlaegeJePerson({
    bool beiseite = false,
  }) async {
    // Erst zaehlen, dann die Personen dazuholen. Ein `readTable` auf die
    // gruppierte Abfrage geht nicht: Eine Gruppe ist keine Zeile der
    // Personentabelle, und drift sagt das auch so.
    final anzahl = faces.id.count();
    final zeilen =
        await (selectOnly(
                faces,
              ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
              ..addColumns([faces.vorschlagPersonId, anzahl])
              ..where(
                faces.personId.isNull() &
                    faces.vorschlagPersonId.isNotNull() &
                    faces.isIgnored.equals(beiseite) &
                    assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false),
              )
              ..groupBy([faces.vorschlagPersonId]))
            .get();
    final mengen = {
      for (final z in zeilen)
        z.read(faces.vorschlagPersonId)!: z.read(anzahl) ?? 0,
    };
    if (mengen.isEmpty) return const [];
    final leute = await (select(
      people,
    )..where((t) => t.id.isIn(mengen.keys.toList()))).get();
    final liste = [
      for (final p in leute) (person: p, anzahl: mengen[p.id] ?? 0),
    ]..sort((a, b) => b.anzahl.compareTo(a.anzahl));
    return liste;
  }

  /// Die Vorschlaege zu einer Person, wie [PersonSuggestionsScreen] sie
  /// erwartet – absteigend nach Aehnlichkeit, das Sicherste zuerst.
  Future<List<({FaceData gesicht, double aehnlichkeit})>> vorschlaegeFuerPerson(
    String personId, {
    bool beiseite = false,
  }) async {
    final zeilen =
        await (select(faces).join([
              innerJoin(assets, assets.id.equalsExp(faces.assetId)),
            ])..where(
              faces.personId.isNull() &
                  faces.vorschlagPersonId.equals(personId) &
                  faces.isIgnored.equals(beiseite) &
                  assets.isTrashed.equals(false) &
                  assets.isLocked.equals(false),
            ))
            .get();
    final liste = [
      for (final z in zeilen)
        (
          gesicht: z.readTable(faces),
          aehnlichkeit: z.readTable(faces).vorschlagWert ?? 0,
        ),
    ]..sort((a, b) => b.aehnlichkeit.compareTo(a.aehnlichkeit));
    return liste;
  }

  /// Nimmt den Vorschlag von diesen Gesichtern weg – nach einer
  /// Ablehnung.
  ///
  /// Die Marke [Faces.vorschlagGeprueftAm] bleibt stehen: Der naechste
  /// Lauf soll dieselbe Frage nicht sofort wieder stellen. Erst ein Lauf
  /// mit „alle" fragt erneut, und bis dahin ist die Schwelle dieser
  /// Person durch die Ablehnung gestiegen.
  Future<void> verwirfVorschlaege(List<String> faceIds) =>
      (update(faces)..where((t) => t.id.isIn(faceIds))).write(
        const FacesCompanion(
          vorschlagPersonId: Value(null),
          vorschlagWert: Value(null),
        ),
      );

  Future<void> assignFacesToPerson(
    List<String> faceIds,
    String personId,
  ) async {
    // Wer einem beiseitegelegten Gesicht einen Namen gibt, hat es damit
    // zurückgeholt – sonst verschwände es unmittelbar nach dem Benennen
    // wieder aus der Personenansicht.
    await (update(faces)..where((t) => t.id.isIn(faceIds))).write(
      FacesCompanion(
        personId: Value(personId),
        isIgnored: const Value(false),
        // Der Vorschlag ist erledigt, sobald er angenommen wurde – er
        // stuende sonst weiter in der Warteschlange.
        vorschlagPersonId: const Value(null),
        vorschlagWert: const Value(null),
      ),
    );
    final assignedFaces = await (select(
      faces,
    )..where((t) => t.id.isIn(faceIds))).get();
    final withCrop = assignedFaces.where((f) => f.cropRelativePath != null);
    if (withCrop.isNotEmpty) {
      await setPersonCoverIfUnset(personId, withCrop.first.cropRelativePath!);
    }
  }

  /// Der Stand der Gesichter vor einer Zuordnung – genau das, was
  /// [nimmZuordnungZurueck] zurückschreiben muss.
  ///
  /// Vorher lesen statt hinterher raten: Ein Gesicht kann schon jemandem
  /// gehört haben oder beiseitegelegt gewesen sein, und [assignFacesToPerson]
  /// holt Beiseitegelegtes ausdrücklich zurück.
  Future<List<Gesichtsstand>> gesichtsstand(List<String> faceIds) async {
    final rows = await (select(faces)..where((t) => t.id.isIn(faceIds))).get();
    return [
      for (final f in rows)
        (id: f.id, personId: f.personId, ignoriert: f.isIgnored),
    ];
  }

  /// Nimmt eine Zuordnung samt allem zurück, was sie ausgelöst hat.
  ///
  /// Eine Zuordnung ändert mehr als die eine Spalte: Sie holt
  /// beiseitegelegte Gesichter zurück, setzt gegebenenfalls das Titelbild
  /// der Person, legt Rückmeldungen für die lernende Wiedererkennung an und
  /// verschiebt damit deren Schwelle. Ein Rückgängig, das nur `person_id`
  /// leert, liesse die Person mit einem fremden Titelbild und einer
  /// Schwelle zurück, die aus einer zurückgenommenen Entscheidung stammt.
  ///
  /// [rueckmeldungenSeit] ist der Zeitpunkt, den
  /// [merkeGesichtsEntscheidungen] verwendet hat; `null`, wenn keine
  /// Rückmeldungen entstanden sind.
  Future<void> nimmZuordnungZurueck({
    required List<Gesichtsstand> gesichter,
    required String personId,
    required bool personWarNeu,
    required String? titelbildVorher,
    required DateTime? rueckmeldungenSeit,
    required double allgemeineSchwelle,
  }) async {
    if (gesichter.isEmpty) return;
    await transaction(() async {
      for (final g in gesichter) {
        await (update(faces)..where((t) => t.id.equals(g.id))).write(
          FacesCompanion(
            personId: Value(g.personId),
            isIgnored: Value(g.ignoriert),
          ),
        );
      }
      if (rueckmeldungenSeit != null) {
        await (delete(faceMatchFeedback)..where(
              (t) =>
                  t.personId.equals(personId) &
                  t.faceId.isIn([for (final g in gesichter) g.id]) &
                  t.createdAt.isBiggerOrEqualValue(rueckmeldungenSeit),
            ))
            .go();
      }
      if (personWarNeu) {
        // Die Person entstand allein für diese Zuordnung; ohne sie bliebe
        // ein leerer Name in der Liste stehen.
        await (delete(people)..where((t) => t.id.equals(personId))).go();
      } else {
        await (update(people)..where((t) => t.id.equals(personId))).write(
          PeopleCompanion(coverFaceCropPath: Value(titelbildVorher)),
        );
        await _aktualisiereSchwelle(personId, allgemeineSchwelle);
      }
    });
  }

  // -----------------------------------------------------------------------
  // Lernende Wiedererkennung (siehe face_threshold.dart)
  // -----------------------------------------------------------------------

  /// Hält Entscheidungen über Wiedererkennungs-Vorschläge fest und führt
  /// die persönliche Schwelle der Person in einem Zug nach.
  ///
  /// Beides zusammen in einer Transaktion, damit die gespeicherte Schwelle
  /// nie zu einem anderen Satz Rückmeldungen gehört als dem, der in der
  /// Oberfläche als Begründung angezeigt wird.
  ///
  /// Gibt den Zeitpunkt zurück, unter dem die Rückmeldungen abgelegt wurden
  /// – [nimmZuordnungZurueck] braucht ihn, um genau diese Zeilen wieder zu
  /// entfernen und nicht ältere zu derselben Person. `null`, wenn nichts
  /// abzulegen war.
  Future<DateTime?> merkeGesichtsEntscheidungen(
    String personId,
    List<({String faceId, bool accepted, double similarity})> entscheidungen, {
    required double allgemeineSchwelle,
  }) async {
    if (entscheidungen.isEmpty) return null;
    final jetzt = DateTime.now();
    await transaction(() async {
      await batch(
        (b) => b.insertAll(faceMatchFeedback, [
          for (final e in entscheidungen)
            FaceMatchFeedbackCompanion.insert(
              personId: personId,
              faceId: e.faceId,
              accepted: e.accepted,
              similarity: e.similarity,
              createdAt: jetzt,
            ),
        ]),
      );
      await _aktualisiereSchwelle(personId, allgemeineSchwelle);
    });
    return jetzt;
  }

  Future<void> _aktualisiereSchwelle(String personId, double allgemein) async {
    final rueckmeldungen = await gesichtsRueckmeldungen(personId);
    final abgeleitet = leiteSchwelleAb(rueckmeldungen, allgemein);
    await (update(people)..where((t) => t.id.equals(personId))).write(
      // Genau die allgemeine Schwelle wird als "nichts Eigenes" gespeichert
      // – sonst wanderte sie nicht mit, wenn der Nutzer die allgemeine
      // später in den Werkzeugen ändert.
      PeopleCompanion(
        similarityThreshold: Value(abgeleitet == allgemein ? null : abgeleitet),
      ),
    );
  }

  Future<List<GesichtsRueckmeldung>> gesichtsRueckmeldungen(
    String personId,
  ) async {
    final rows = await (select(
      faceMatchFeedback,
    )..where((t) => t.personId.equals(personId))).get();
    return [
      for (final r in rows)
        GesichtsRueckmeldung(
          bestaetigt: r.accepted,
          aehnlichkeit: r.similarity,
        ),
    ];
  }

  /// Verwirft alles Gelernte zu einer Person – der Ausweg, wenn die
  /// Anpassung einmal danebenliegt und der Nutzer nicht nachvollziehen
  /// kann, warum.
  Future<void> vergissGesichtsEntscheidungen(String personId) =>
      transaction(() async {
        await (delete(
          faceMatchFeedback,
        )..where((t) => t.personId.equals(personId))).go();
        await (update(people)..where((t) => t.id.equals(personId))).write(
          const PeopleCompanion(similarityThreshold: Value(null)),
        );
      });

  /// Rechnet die persönlichen Schwellen aller Personen neu.
  ///
  /// Nötig, wenn der Nutzer die allgemeine Schwelle ändert: Die
  /// persönlichen sind daran gebunden (Ausgangspunkt und Deckel), sonst
  /// hätte der Regler in den Werkzeugen für gelernte Personen keine
  /// Wirkung mehr.
  Future<void> rechneAlleSchwellenNeu(double allgemein) async {
    for (final person in await select(people).get()) {
      await _aktualisiereSchwelle(person.id, allgemein);
    }
  }

  /// Setzt das Profilbild einer Person auf den Foto-Ausschnitt (Crop) eines
  /// bestimmten Gesichts – sowohl für die automatische Erstzuordnung als
  /// auch für die manuelle Auswahl in der Personen-Detailansicht.
  Future<void> setPersonCover(String personId, String cropRelativePath) =>
      (update(people)..where((t) => t.id.equals(personId))).write(
        PeopleCompanion(coverFaceCropPath: Value(cropRelativePath)),
      );

  /// Wie [setPersonCover], setzt das Profilbild aber nur, wenn die Person
  /// noch keins hat – wird beim automatischen Zuordnen eines Gesichts
  /// aufgerufen, damit ein bereits manuell gewähltes Profilbild nicht
  /// überschrieben wird.
  Future<void> setPersonCoverIfUnset(
    String personId,
    String cropRelativePath,
  ) async {
    final person = await (select(
      people,
    )..where((t) => t.id.equals(personId))).getSingleOrNull();
    if (person != null && person.coverFaceCropPath == null) {
      await setPersonCover(personId, cropRelativePath);
    }
  }

  /// Führt zwei Personen zusammen: alle Gesichter von [removePersonId] werden
  /// [keepPersonId] zugeordnet, anschließend wird die überflüssige
  /// Personen-Zeile gelöscht. Nützlich, wenn die Gesichtserkennung
  /// dieselbe reale Person versehentlich als zwei Personen angelegt hat.
  Future<void> mergePeople({
    required String keepPersonId,
    required String removePersonId,
  }) async {
    await transaction(() async {
      await (update(faces)..where((t) => t.personId.equals(removePersonId)))
          .write(FacesCompanion(personId: Value(keepPersonId)));
      // Die Verwandtschaften der aufgelösten Person würden sonst ins Leere
      // zeigen: Kanten auf eine nicht mehr vorhandene Kennung erscheinen im
      // Stammbaum als namenlose Karte. Übertragen statt löschen – wer zwei
      // Einträge derselben Person zusammenführt, will deren Familie
      // behalten.
      await _uebertrageBeziehungen(removePersonId, keepPersonId);
      await (delete(people)..where((t) => t.id.equals(removePersonId))).go();
    });
  }
}

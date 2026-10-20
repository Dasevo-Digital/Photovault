part of '../database.dart';

/// Aufgezeichnete Spuren.
extension SpurenAbfragen on AppDatabase {
  // ---------------------------------------------------------------
  // Aufgezeichnete Spuren.

  Future<List<SpurenData>> alleSpuren() =>
      (select(spuren)..orderBy([(t) => OrderingTerm.desc(t.angelegtAm)])).get();

  /// Die Spuren einer Reise – dieselbe Tabelle, die andere Spalte.
  Future<List<SpurenData>> spurenDerReise(String reiseId) =>
      (select(spuren)
            ..where((t) => t.reiseId.equals(reiseId))
            ..orderBy([(t) => OrderingTerm(expression: t.angelegtAm)]))
          .get();

  Future<List<SpurenData>> spurenDerAktivitaet(String aktivitaetId) =>
      (select(spuren)
            ..where((t) => t.aktivitaetId.equals(aktivitaetId))
            ..orderBy([(t) => OrderingTerm.asc(t.angelegtAm)]))
          .get();

  /// Die Punkte einer Spur, in der Reihenfolge der Datei.
  Future<List<SpurpunkteData>> punkteDerSpur(String spurId) =>
      (select(spurpunkte)
            ..where((t) => t.spurId.equals(spurId))
            ..orderBy([(t) => OrderingTerm.asc(t.nummer)]))
          .get();

  /// Legt eine Spur samt ihren Punkten an.
  ///
  /// In einer Transaktion und als Stapel: Eine Aufzeichnung hat schnell
  /// zehntausend Punkte, und zehntausend einzelne Einfügungen wären
  /// zehntausend Schreibvorgänge.
  Future<void> spurAnlegen(
    SpurenCompanion spur,
    List<SpurpunkteCompanion> punkte,
  ) => transaction(() async {
    await into(spuren).insert(spur);
    await batch((b) => b.insertAll(spurpunkte, punkte));
  });

  /// Legt eine Spur an oder ersetzt sie samt Punkten, wenn es sie unter
  /// dieser Kennung schon gibt (siehe `SpurAnlegen`).
  Future<void> spurUebernehmen(
    SpurenCompanion spur,
    List<SpurpunkteCompanion> punkte,
  ) => transaction(() async {
    final id = spur.id.value;
    await (delete(spurpunkte)..where((t) => t.spurId.equals(id))).go();
    await (delete(spuren)..where((t) => t.id.equals(id))).go();
    await into(spuren).insert(spur);
    await batch((b) => b.insertAll(spurpunkte, punkte));
  });

  Future<void> spurLoeschen(String id) => transaction(() async {
    await (delete(spurpunkte)..where((t) => t.spurId.equals(id))).go();
    await (delete(spuren)..where((t) => t.id.equals(id))).go();
  });

  Future<void> spurAendern(String id, SpurenCompanion aenderung) =>
      (update(spuren)..where((t) => t.id.equals(id))).write(aenderung);

  Future<Set<String>> verworfeneAktivitaetsvorschlaege() async => {
    for (final z in await select(verworfeneAktivitaeten).get()) z.schluessel,
  };

  Future<void> verwirfAktivitaetsvorschlag(String schluessel) =>
      into(verworfeneAktivitaeten).insertOnConflictUpdate(
        VerworfeneAktivitaetenCompanion.insert(
          schluessel: schluessel,
          verworfenAm: DateTime.now(),
        ),
      );

  Future<Set<String>> verworfeneReisevorschlaege() async => {
    for (final z in await select(verworfeneReisen).get()) z.schluessel,
  };

  Future<void> verwirfReisevorschlag(String schluessel) =>
      into(verworfeneReisen).insertOnConflictUpdate(
        VerworfeneReisenCompanion.insert(
          schluessel: schluessel,
          verworfenAm: DateTime.now(),
        ),
      );

  /// Alles, was die Reiseerkennung braucht – verortete, nicht gelöschte
  /// Aufnahmen.
  ///
  /// Eine Abfrage über die ganze Bibliothek, aber nur mit den fünf
  /// Spalten, die zählen: Bei hunderttausend Aufnahmen wäre das Laden
  /// vollständiger Zeilen der teuerste Teil des ganzen Vorgangs.
  Future<
    List<
      ({
        String id,
        DateTime zeit,
        double breite,
        double laenge,
        String? land,
        String? region,
        String? stadt,
      })
    >
  >
  aufnahmenFuerReiseerkennung() async {
    // `_isPrimaryGridEntry` wie überall sonst: Die Videohälfte eines Live
    // Photos ist keine eigene Aufnahme, und ein Stapel zählt einmal.
    //
    // OHNE DIESE ZEILE kam ein bestätigter Ausflug als Vorschlag zurück.
    // Bestätigt wurde, was die Zeitleiste zeigt – die JPGs. Die MOV-Hälften
    // blieben unzugeordnet, trugen aber dieselbe Zeit und denselben Ort und
    // fanden sich beim nächsten Blick zu einem neuen Vorschlag desselben
    // Ausflugs zusammen. An der gewachsenen Bibliothek: ALLE drei noch
    // offenen Aktivitätsvorschläge waren solche Schatten – „Rautheim" mit
    // vier Videohälften zu einer bestätigten Aktivität aus vier Fotos, auf
    // die Sekunde dieselben Aufnahmen.
    final abfrage = selectOnly(assets)
      ..addColumns([
        assets.id,
        assets.fileCreatedAt,
        assets.latitude,
        assets.longitude,
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
      ])
      ..where(
        assets.latitude.isNotNull() &
            assets.longitude.isNotNull() &
            assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            _isPrimaryGridEntry(assets),
      )
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [
      for (final z in await abfrage.get())
        (
          id: z.read(assets.id)!,
          zeit: z.read(assets.fileCreatedAt)!,
          breite: z.read(assets.latitude)!,
          laenge: z.read(assets.longitude)!,
          land: z.read(assets.locationCountry),
          region: z.read(assets.locationState),
          stadt: z.read(assets.locationCity),
        ),
    ];
  }

  /// Setzt Koordinate **und** Ortsnamen in einem Zug.
  ///
  /// Beides zusammen und nicht nacheinander: Wer Fotos aus einer
  /// GPX-Spur verortet, hat sonst hinterher Punkte auf der Karte, aber
  /// keine Länder im Reisezähler – und müsste ein zweites Werkzeug
  /// starten, von dem er nichts weiss.
  Future<void> setzeOrte(
    List<
      ({
        String assetId,
        double breite,
        double laenge,
        String? land,
        String? region,
        String? ort,
      })
    >
    eintraege,
  ) => batch((b) {
    for (final e in eintraege) {
      b.update(
        assets,
        AssetsCompanion(
          latitude: Value(e.breite),
          longitude: Value(e.laenge),
          // Nur schreiben, wenn ein Name da ist: Ohne geladenen
          // GeoNames-Auszug bleibt die Spalte leer, statt einen
          // vorhandenen Namen zu löschen.
          locationCountry: e.ort == null ? const Value.absent() : Value(e.land),
          locationState: e.ort == null ? const Value.absent() : Value(e.region),
          locationCity: e.ort == null ? const Value.absent() : Value(e.ort),
        ),
        where: (t) => t.id.equals(e.assetId),
      );
    }
  });

  /// Land, Region und Ort aller verorteten Aufnahmen, mit Anzahl.
  ///
  /// Gruppiert in der Datenbank und nicht in Dart: Für den Länderzähler
  /// zählen nur die verschiedenen Kombinationen, und die sind auch bei
  /// hunderttausend Aufnahmen wenige hundert Zeilen.
  Future<List<({String? land, String? region, String? ort, int anzahl})>>
  besuchteOrte() async {
    final anzahl = assets.id.count();
    final abfrage = selectOnly(assets)
      ..addColumns([
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
        anzahl,
      ])
      ..where(
        assets.latitude.isNotNull() &
            assets.isTrashed.equals(false) &
            assets.isLocked.equals(false),
      )
      ..groupBy([
        assets.locationCountry,
        assets.locationState,
        assets.locationCity,
      ]);
    return [
      for (final z in await abfrage.get())
        (
          land: z.read(assets.locationCountry),
          region: z.read(assets.locationState),
          ort: z.read(assets.locationCity),
          anzahl: z.read(anzahl) ?? 0,
        ),
    ];
  }

  /// Wer wann auf welchem Bild zu sehen ist – für die Familienstatistik.
  ///
  /// Nur die angefragten Personen, damit bei einer grossen Bibliothek
  /// nicht jedes erkannte Gesicht durch den Speicher wandert.
  ///
  /// **Der gesperrte Ordner bleibt draussen**, ebenso der Papierkorb. Was
  /// hinter der PIN liegt, darf ausserhalb nicht auftauchen – auch nicht
  /// als Strich in einem Balkendiagramm, der verrät, dass es dort etwas
  /// gibt.
  Future<List<({String personId, String assetId, DateTime zeit})>>
  auftritteFuerPersonen(Set<String> personIds) async {
    if (personIds.isEmpty) return const [];
    final abfrage =
        select(
          faces,
        ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])..where(
          faces.personId.isIn(personIds) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false),
        );
    return [
      for (final z in await abfrage.get())
        (
          personId: z.readTable(faces).personId!,
          assetId: z.readTable(assets).id,
          zeit: z.readTable(assets).fileCreatedAt,
        ),
    ];
  }

  /// Jedes benannte Gesicht als Paar aus Person und Foto – für das
  /// Soziogramm. Beiseitegelegte Gesichter, gelöschte und gesperrte Fotos
  /// zählen nicht.
  Future<List<({String personId, String assetId})>> personenAuftritte() async {
    final abfrage =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([faces.personId, faces.assetId])
          ..where(
            faces.personId.isNotNull() &
                faces.isIgnored.equals(false) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          );
    return [
      for (final z in await abfrage.get())
        (personId: z.read(faces.personId)!, assetId: z.read(faces.assetId)!),
    ];
  }

  /// Alle selbst gesetzten Ortsmarken.
  Future<List<OrtsmarkenData>> alleOrtsmarken() => select(ortsmarken).get();

  /// Dieselben, als Strom – die Weltkarte soll sich sofort umfärben,
  /// wenn woanders ein Haken gesetzt wird.
  Stream<List<OrtsmarkenData>> beobachteOrtsmarken() =>
      select(ortsmarken).watch();

  /// Setzt eine Marke oder ersetzt die vorhandene.
  ///
  /// `insertOnConflictUpdate` und nicht erst suchen: Art und Schlüssel
  /// sind zusammen der Primärschlüssel, ein zweiter Haken auf dasselbe
  /// Land ist also gar nicht möglich – und ein Umschalten von „geplant"
  /// auf „besucht" ist genau dieselbe Zeile mit anderem Wert.
  Future<void> setzeOrtsmarke(Insertable<OrtsmarkenData> marke) =>
      into(ortsmarken).insertOnConflictUpdate(marke);

  /// Nimmt eine Marke zurück.
  Future<void> loescheOrtsmarke(String art, String schluessel) => (delete(
    ortsmarken,
  )..where((o) => o.art.equals(art) & o.schluessel.equals(schluessel))).go();

  /// Aufnahmen **ohne** Koordinate – für das Auffüllen erkannter Reisen.
  ///
  /// Sie taugen nicht zum Erkennen, gehören aber dazu: An der echten
  /// Bibliothek trugen von einer Reise nur zwei Tage GPS-Daten, und im
  /// Fenster dieser zwei Tage lagen 28 weitere Aufnahmen ohne Koordinate.
  /// Dieselbe Einschränkung wie in [aufnahmenFuerReiseerkennung], und aus
  /// demselben Grund: Diese Aufnahmen werden einer erkannten Reise
  /// zugeschlagen, und eine Videohälfte doppelt sonst jedes Live Photo.
  Future<List<({String id, DateTime zeit})>> aufnahmenOhneKoordinate() async {
    final abfrage = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(
        assets.latitude.isNull() &
            assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            _isPrimaryGridEntry(assets),
      )
      ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [
      for (final z in await abfrage.get())
        (id: z.read(assets.id)!, zeit: z.read(assets.fileCreatedAt)!),
    ];
  }

  /// Alle Lebensereignisse, in einem Zug.
  ///
  /// Für die Familien-Zeitleiste, die Dutzende Personen zugleich zeigt.
  /// Je Person einzeln zu fragen ergäbe dieselbe Zahl kleiner Abfragen
  /// wie Zeilen – und die Tabelle ist selbst bei ausgiebiger Forschung
  /// klein gegenüber allem anderen hier.
  Future<List<LebensereignisseData>> alleEreignisse() =>
      select(lebensereignisse).get();

  /// Setzt oder löscht die Koordinate eines Ereignisses.
  ///
  /// `null` für beide Werte heisst „nicht verortet" – so lässt sich eine
  /// falsch geratene Zuordnung auch wieder wegnehmen, ohne den
  /// aufgeschriebenen Ortsnamen zu verlieren.
  Future<void> setzeEreignisort(String id, {double? breite, double? laenge}) =>
      (update(lebensereignisse)..where((t) => t.id.equals(id))).write(
        LebensereignisseCompanion(
          ortBreite: Value(breite),
          ortLaenge: Value(laenge),
        ),
      );

  /// Setzt das Geschlecht einer Person. `null` bedeutet „nicht angegeben".
  Future<void> setzeGeschlecht(String personId, Geschlecht? geschlecht) =>
      (update(people)..where((t) => t.id.equals(personId))).write(
        PeopleCompanion(
          geschlecht: Value(
            geschlecht == null ? null : geschlechtZuText(geschlecht),
          ),
        ),
      );

  /// Setzt die Lebensdaten einer Person. `null` löscht die Angabe.
  Future<void> setzeLebensdaten(
    String personId, {
    required DateTime? geburt,
    required DateTime? tod,
  }) => (update(people)..where((t) => t.id.equals(personId))).write(
    PeopleCompanion(geburtsdatum: Value(geburt), sterbedatum: Value(tod)),
  );

  /// Alle Personen in der Reihenfolge, in der sie im Stammbaum stehen
  /// sollen: die Älteren zuerst, Unbekanntes zuletzt, bei Gleichstand nach
  /// Namen.
  ///
  /// Die Sortierung steckt hier und nicht in der Darstellung, weil sie
  /// auch die Reihenfolge innerhalb einer Geschwisterreihe bestimmt – und
  /// die soll überall dieselbe sein.
  List<PersonData> nachAlterSortiert(List<PersonData> personen) {
    final sortiert = [...personen];
    sortiert.sort((a, b) {
      final ga = a.geburtsdatum, gb = b.geburtsdatum;
      if (ga != null && gb != null && ga != gb) return ga.compareTo(gb);
      if (ga != null && gb == null) return -1;
      if (ga == null && gb != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sortiert;
  }

  /// Alle Fotos, auf denen mindestens eine der genannten Personen erkannt
  /// wurde – für „Fotos der Familie".
  ///
  /// Die eigentliche Verbindung zwischen den beiden Hälften dieser App:
  /// Gesichter sind Personen zugeordnet, Personen sind miteinander
  /// verwandt. Erst diese Abfrage macht daraus „zeig mir alles von diesem
  /// Familienzweig". Ein Foto mit mehreren Verwandten darauf erscheint
  /// einmal, nicht mehrfach.
  Future<List<AssetData>> assetsFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return [];
    final query =
        select(
            assets,
          ).join([innerJoin(faces, faces.assetId.equalsExp(assets.id))])
          ..where(
            faces.personId.isIn(personIds) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                _isPrimaryGridEntry(assets),
          )
          ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    final rows = await query.get();
    final gesehen = <String>{};
    final ergebnis = <AssetData>[];
    for (final row in rows) {
      final a = row.readTable(assets);
      if (gesehen.add(a.id)) ergebnis.add(a);
    }
    return ergebnis;
  }

  /// Verortete Fotos einer Personengruppe, samt der Personen darauf.
  ///
  /// Für die Familienkarte: Ein Foto kann mehrere Verwandte zeigen, und
  /// erst die Liste der Personen erlaubt der Karte zu entscheiden, welcher
  /// Verwandtschaftsgrad die Farbe bestimmt. Ein einzelnes „gehört zur
  /// Familie“ genügte dafür nicht.
  Future<List<({AssetData asset, Set<String> personen})>>
  verorteteAssetsFuerPersonen(List<String> personIds) async {
    if (personIds.isEmpty) return [];
    final query =
        select(
            assets,
          ).join([innerJoin(faces, faces.assetId.equalsExp(assets.id))])
          ..where(
            faces.personId.isIn(personIds) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                assets.latitude.isNotNull() &
                assets.longitude.isNotNull() &
                _isPrimaryGridEntry(assets),
          )
          ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    final rows = await query.get();
    final nachId = <String, AssetData>{};
    final leute = <String, Set<String>>{};
    for (final row in rows) {
      final a = row.readTable(assets);
      nachId[a.id] = a;
      final pid = row.readTable(faces).personId;
      if (pid != null) leute.putIfAbsent(a.id, () => {}).add(pid);
    }
    return [
      for (final e in nachId.entries)
        (asset: e.value, personen: leute[e.key] ?? const <String>{}),
    ];
  }

  Stream<List<AssetData>> watchAssetsForPerson(String personId) {
    final query =
        select(
            assets,
          ).join([innerJoin(faces, faces.assetId.equalsExp(assets.id))])
          ..where(
            faces.personId.equals(personId) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..orderBy([OrderingTerm.desc(assets.fileCreatedAt)]);
    // Ein Foto mit zwei Gesichtern derselben Person steht zweimal im
    // Verbund – hier bleibt es bei einem Eintrag.
    return _gedrosselt(
      () => query.map((r) => r.readTable(assets)),
      TableUpdateQuery.allOf([
        TableUpdateQuery.onTable(assets),
        TableUpdateQuery.onTable(faces),
      ]),
    ).map((zeilen) {
      final gesehen = <String>{};
      return [
        for (final a in zeilen)
          if (gesehen.add(a.id)) a,
      ];
    });
  }

  /// Liefert alle Bild-Assets, die für einen (erneuten) Gesichts-Scan
  /// infrage kommen. Bei [onlyNew] werden nur Fotos zurückgegeben, die noch
  /// nie durch die Gesichtserkennung gelaufen sind.
  Future<List<AssetData>> assetsForFaceScan({required bool onlyNew}) {
    // Gesperrte Fotos bewusst ausgeschlossen: sonst würden ihre Gesichter im
    // "Unbenannte Gesichter"-Tab auftauchen, obwohl das Foto selbst versteckt
    // ist (siehe [unassignedFaces]).
    final query = select(assets)
      ..where(
        (t) =>
            _auswertbar(t) &
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            // Gilt auch fuer "alle erneut durchsuchen" - sonst waere die
            // Ausnahme wertlos, denn nur dort greift sie ueberhaupt.
            t.faceScanExcluded.equals(false),
      );
    if (onlyNew) {
      query.where((t) => t.facesScanned.equals(false));
    }
    return query.get();
  }

  /// Nimmt ein Foto von der Gesichtssuche aus oder holt es zurueck.
  Future<void> setzeGesichtssucheAusgenommen(String assetId, bool wert) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(faceScanExcluded: Value(wert)),
      );

  /// Zählvariante von [assetsForFaceScan], siehe [countLocationBackfill].
  Future<int> countFaceScan({required bool onlyNew}) {
    var predicate =
        _auswertbar(assets) &
        assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        assets.faceScanExcluded.equals(false);
    if (onlyNew) predicate = predicate & assets.facesScanned.equals(false);
    return _countWhere(predicate);
  }

  Future<void> markFacesScanned(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(facesScanned: Value(true)),
      );

  /// Löscht bereits erkannte, aber noch keiner Person zugeordnete Gesichter
  /// eines Assets, bevor ein erneuter Scan neue Erkennungen einfügt – manuell
  /// zugeordnete Gesichter (mit personId) bleiben dabei bewusst unangetastet.
  ///
  /// Beiseitegelegte Gesichter bleiben ebenfalls stehen. Sonst wäre das
  /// Ignorieren beim ersten „alle Fotos erneut scannen" stillschweigend
  /// wieder weg – und genau davor soll es schützen (siehe [Faces.isIgnored]).
  /// Gibt die Ausschnitts-Pfade der gelöschten Zeilen zurück, damit der
  /// Aufrufer die Dateien mit wegräumt – wie [loescheGesichter].
  ///
  /// Diese Rückgabe fehlte hier als einziger der drei Löschwege, und
  /// ausgerechnet dieser läuft nicht auf Knopfdruck, sondern bei jedem
  /// „alle Fotos erneut scannen" über den ganzen Bestand. In der
  /// Prüfbibliothek lagen dadurch 17 643 Ausschnitte ohne Datenbankzeile
  /// – 160 MB, genau die Hälfte des Ordners, alle aus einem einzigen
  /// Durchlauf. Jeder weitere Scan hätte den Bestand erneut verdoppelt
  /// (Prüfrunde 8).
  Future<List<String>> deleteUnassignedFacesForAsset(String assetId) async {
    final auswahl = select(faces)
      ..where(
        (t) =>
            t.assetId.equals(assetId) &
            t.personId.isNull() &
            t.isIgnored.equals(false),
      );
    final betroffen = await auswahl.get();
    if (betroffen.isEmpty) return const [];
    await (delete(
      faces,
    )..where((t) => t.id.isIn([for (final f in betroffen) f.id]))).go();
    return [
      for (final f in betroffen)
        if (f.cropRelativePath != null) f.cropRelativePath!,
    ];
  }
}

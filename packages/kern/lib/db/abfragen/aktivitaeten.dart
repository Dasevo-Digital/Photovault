part of '../database.dart';

/// Aktivitäten.
extension AktivitaetenAbfragen on AppDatabase {
  // ---------------------------------------------------------------
  // Aktivitäten. Dieselbe Bauart wie die Reisen darüber – bis auf die
  // eine Stelle, an der sie sich unterscheiden: `reiseId` darf leer
  // bleiben.

  /// Alle Aktivitäten, jüngste zuerst.
  Future<List<AktivitaetenData>> alleAktivitaeten() =>
      (select(aktivitaeten)..orderBy([(t) => OrderingTerm.desc(t.von)])).get();

  /// Dasselbe als Strom – für Übersichten, die sich selbst nachführen
  /// sollen (Erkunden). Gegenstück zu [watchReisen].
  Stream<List<AktivitaetenData>> watchAktivitaeten() => (select(
    aktivitaeten,
  )..orderBy([(t) => OrderingTerm.desc(t.von)])).watch();

  Future<AktivitaetenData?> aktivitaet(String id) =>
      (select(aktivitaeten)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Die Aktivitäten einer Reise, chronologisch **aufsteigend**.
  ///
  /// Anders als die Liste der Reisen: Innerhalb einer Reise liest man
  /// vorwärts – erster Tag zuerst –, wie die Tageskapitel daneben.
  Future<List<AktivitaetenData>> aktivitaetenDerReise(String reiseId) =>
      (select(aktivitaeten)
            ..where((t) => t.reiseId.equals(reiseId))
            ..orderBy([(t) => OrderingTerm.asc(t.von)]))
          .get();

  /// Aktivitäten, die zu keiner Reise gehören – jüngste zuerst.
  Future<List<AktivitaetenData>> aktivitaetenOhneReise() =>
      (select(aktivitaeten)
            ..where((t) => t.reiseId.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.von)]))
          .get();

  /// Legt eine bestätigte Aktivität samt ihren Aufnahmen an – in einer
  /// Transaktion, aus demselben Grund wie bei [reiseAnlegen].
  Future<void> aktivitaetAnlegen(
    Insertable<AktivitaetenData> neue,
    List<String> assetIds,
  ) => transaction(() async {
    await into(aktivitaeten).insert(neue);
    await batch(
      (b) => b.insertAll(aktivitaetAufnahmen, [
        for (final id in assetIds)
          AktivitaetAufnahmenCompanion.insert(
            aktivitaetId: _textSpalte(neue, 'id'),
            assetId: id,
          ),
      ]),
    );
  });

  Future<void> aktivitaetLoeschen(String id) => transaction(() async {
    await (delete(
      aktivitaetAufnahmen,
    )..where((t) => t.aktivitaetId.equals(id))).go();
    await (delete(aktivitaeten)..where((t) => t.id.equals(id))).go();
  });

  Future<void> aktivitaetAendern(
    String id,
    Insertable<AktivitaetenData> aenderung,
  ) => (update(aktivitaeten)..where((t) => t.id.equals(id))).write(aenderung);

  /// Die Aufnahmen einer Aktivität, chronologisch. Gelöschte und
  /// gesperrte fallen heraus – siehe die Regel über [aufnahmenDerReise].
  Future<List<AssetData>> aufnahmenDerAktivitaet(String aktivitaetId) async {
    final abfrage =
        select(assets).join([
            innerJoin(
              aktivitaetAufnahmen,
              aktivitaetAufnahmen.assetId.equalsExp(assets.id),
            ),
          ])
          ..where(
            aktivitaetAufnahmen.aktivitaetId.equals(aktivitaetId) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [for (final z in await abfrage.get()) z.readTable(assets)];
  }

  /// Nur die erste Aufnahme – für das Vorschaubild in der Liste. Eigene
  /// Abfrage mit `LIMIT 1`, aus demselben Grund wie
  /// [ersteAufnahmeDerReise].
  Future<AssetData?> ersteAufnahmeDerAktivitaet(String aktivitaetId) async {
    final abfrage =
        select(assets).join([
            innerJoin(
              aktivitaetAufnahmen,
              aktivitaetAufnahmen.assetId.equalsExp(assets.id),
            ),
          ])
          ..where(
            aktivitaetAufnahmen.aktivitaetId.equals(aktivitaetId) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)])
          ..limit(1);
    final zeile = await abfrage.getSingleOrNull();
    return zeile?.readTable(assets);
  }

  /// Die Aufnahmen eines Zeitraums – für eine von Hand angelegte Reise
  /// oder Aktivität.
  ///
  /// **Der Zeitraum ist die ganze Eingabe.** Zugeordnet wird in dieser App
  /// über die Fotos und nicht über den Kalender; wer eine Reise von Hand
  /// anlegt, nennt deshalb ihren Zeitraum, und die Bilder darin kommen
  /// mit. Ein Auswahlraster für einzelne Fotos wäre der zweite Schritt,
  /// nicht der erste.
  ///
  /// [bis] ist einschliessend gemeint: Wer den 14. Juni als letzten Tag
  /// nennt, meint auch das Foto von 23:50 Uhr.
  /// Wie viele Aufnahmen im Zeitraum liegen – als Zahl, nicht als Liste.
  ///
  /// Der Zeitraum-Dialog zeigt beim Verschieben der Daten eine Zahl an.
  /// Er holte dafür bisher die vollen Zeilen und nahm deren `length` –
  /// bei einem weiten Zeitraum die halbe Bibliothek für eine einzige
  /// Ziffer, und das bei jeder Änderung.
  Future<int> zahlImZeitraum(DateTime von, DateTime bis) async {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    final zaehler = assets.id.count();
    final abfrage = selectOnly(assets)
      ..addColumns([zaehler])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            assets.fileCreatedAt.isBiggerOrEqualValue(anfang) &
            assets.fileCreatedAt.isSmallerOrEqualValue(ende) &
            _isPrimaryGridEntry(assets),
      );
    return (await abfrage.getSingle()).read(zaehler)!;
  }

  /// Dieselbe Menge wie [aufnahmenImZeitraum] als schmale Rasterzeilen.
  Future<List<Rasterzeile>> rasterzeilenImZeitraum(
    DateTime von,
    DateTime bis,
  ) async {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    return (await customSelect(
      'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
      'AND file_created_at >= ? AND file_created_at <= ? '
      'ORDER BY file_created_at ASC',
      variables: [Variable.withDateTime(anfang), Variable.withDateTime(ende)],
      readsFrom: {assets},
    ).get()).map(Rasterzeile.ausZeile).toList();
  }

  /// Die Personen, die zwischen [von] und [bis] am häufigsten auf Fotos
  /// sind, mit der Zahl der Aufnahmen – für den Jahresrückblick.
  ///
  /// Gezählt werden Aufnahmen, nicht Gesichter: Wer auf einem Gruppenbild
  /// zweimal erkannt wurde, war trotzdem nur einmal dabei.
  Future<List<({PersonData person, int anzahl})>> personenImZeitraum(
    DateTime von,
    DateTime bis, {
    int hoechstens = 8,
  }) async {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    final anzahl = faces.assetId.count(distinct: true);
    final query =
        selectOnly(
            faces,
          ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
          ..addColumns([faces.personId, anzahl])
          ..where(
            faces.personId.isNotNull() &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false) &
                assets.fileCreatedAt.isBiggerOrEqualValue(anfang) &
                assets.fileCreatedAt.isSmallerOrEqualValue(ende),
          )
          ..groupBy([faces.personId])
          ..orderBy([OrderingTerm.desc(anzahl)])
          ..limit(hoechstens);
    final zeilen = await query.get();
    final ids = [for (final z in zeilen) z.read(faces.personId)!];
    if (ids.isEmpty) return const [];
    final personen = {
      for (final p in await (select(
        people,
      )..where((t) => t.id.isIn(ids))).get())
        p.id: p,
    };
    return [
      for (final z in zeilen)
        if (personen[z.read(faces.personId)] case final p?)
          (person: p, anzahl: z.read(anzahl) ?? 0),
    ];
  }

  Future<List<AssetData>> aufnahmenImZeitraum(DateTime von, DateTime bis) {
    final ende = DateTime(bis.year, bis.month, bis.day, 23, 59, 59, 999);
    final anfang = DateTime(von.year, von.month, von.day);
    return (select(assets)
          ..where(
            (t) =>
                t.isTrashed.equals(false) &
                t.isLocked.equals(false) &
                t.fileCreatedAt.isBiggerOrEqualValue(anfang) &
                t.fileCreatedAt.isSmallerOrEqualValue(ende) &
                _isPrimaryGridEntry(t),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
        .get();
  }

  Future<Set<String>> zugeordneteAktivitaetsAufnahmen() async => {
    for (final z in await select(aktivitaetAufnahmen).get()) z.assetId,
  };

  /// Die Kennungen, die WIRKLICH zu dieser Aktivität gespeichert sind.
  ///
  /// **Warum das nicht dasselbe ist wie [aufnahmenDerAktivitaet].** Jene
  /// Abfrage liefert, was sich *zeigen* lässt: Aufnahmen im Papierkorb
  /// und gesperrte bleiben draussen. Wer aus ihrem Ergebnis die
  /// Ausgangsmenge für den Auswahlbildschirm baut, hat die
  /// verschwiegenen Zuordnungen schon verloren – und weil dort beim
  /// Sichern die Tabelle geleert und neu geschrieben wird
  /// ([setzeAufnahmenDerAktivitaet]), verschwinden sie endgültig, ohne
  /// dass jemand etwas angetippt hätte.
  ///
  /// Für „was gehört dazu" ist deshalb diese Abfrage die richtige und
  /// jene die falsche. Sie liest die Zuordnungstabelle selbst und
  /// verbindet sich mit nichts.
  Future<Set<String>> zuordnungenDerAktivitaet(String aktivitaetId) async => {
    for (final z in await (select(
      aktivitaetAufnahmen,
    )..where((t) => t.aktivitaetId.equals(aktivitaetId))).get())
      z.assetId,
  };

  /// Wie [zuordnungenDerAktivitaet], nur eine Tabelle weiter.
  Future<Set<String>> zuordnungenDerReise(String reiseId) async => {
    for (final z in await (select(
      reiseAufnahmen,
    )..where((t) => t.reiseId.equals(reiseId))).get())
      z.assetId,
  };

  /// Die selbst eingetragenen Arten: was in der Spalte steht und keine
  /// mitgelieferte Art ist.
  ///
  /// **Abgeleitet und nicht in einer eigenen Tabelle.** Eine Art
  /// existiert, solange eine Aktivität sie trägt – so kann keine Liste
  /// mit Namen volllaufen, die niemand mehr benutzt, und es braucht
  /// weder einen Schemaschritt noch ein Aufräumen. Der Preis: Wer die
  /// letzte Aktivität einer eigenen Art umträgt, verliert den Namen aus
  /// der Auswahl. Er steht danach genau so wieder da, wie er
  /// hineingekommen ist – als Eingabe.
  Future<List<String>> eigeneAktivitaetsarten() async {
    final zeilen = await customSelect(
      'SELECT DISTINCT art FROM aktivitaeten ORDER BY art',
      readsFrom: {aktivitaeten},
    ).get();
    return [
      for (final z in zeilen)
        if (!istBekannteArt(z.read<String>('art'))) z.read<String>('art'),
    ];
  }

  /// Setzt die Aufnahmen einer Aktivität auf genau [assetIds].
  ///
  /// **Setzen und nicht einzeln hinzufügen/entfernen.** Der Bildschirm
  /// zeigt eine Auswahl und gibt eine Auswahl zurück; die Unterschiede
  /// dazwischen sind Sache dieser Zeile und nicht die des Aufrufers.
  /// Zwei getrennte Aufrufe wären ausserdem zwei Gelegenheiten, dass
  /// dazwischen etwas schiefgeht.
  ///
  /// Führt danach den Zeitraum nach: `von`/`bis` sind aus den Aufnahmen
  /// abgeleitet und trotzdem gespeichert (damit die Liste sortieren kann,
  /// ohne für jede Zeile ihre Aufnahmen nachzuschlagen) – ohne diese
  /// Zeile stünde nach dem Bearbeiten ein Zeitraum da, den keine
  /// Aufnahme mehr belegt.
  Future<void> setzeAufnahmenDerAktivitaet(
    String aktivitaetId,
    Set<String> assetIds,
  ) => transaction(() async {
    await (delete(
      aktivitaetAufnahmen,
    )..where((t) => t.aktivitaetId.equals(aktivitaetId))).go();
    await batch(
      (b) => b.insertAll(aktivitaetAufnahmen, [
        for (final id in assetIds)
          AktivitaetAufnahmenCompanion.insert(
            aktivitaetId: aktivitaetId,
            assetId: id,
          ),
      ]),
    );
    final zeitraum = await _zeitraumVon(assetIds);
    if (zeitraum != null) {
      await (update(
        aktivitaeten,
      )..where((t) => t.id.equals(aktivitaetId))).write(
        AktivitaetenCompanion(
          von: Value(zeitraum.von),
          bis: Value(zeitraum.bis),
        ),
      );
    }
  });

  /// Setzt die Aufnahmen einer Reise auf genau [assetIds] – wie
  /// [setzeAufnahmenDerAktivitaet], nur eine Tabelle weiter.
  Future<void> setzeAufnahmenDerReise(String reiseId, Set<String> assetIds) =>
      transaction(() async {
        await (delete(
          reiseAufnahmen,
        )..where((t) => t.reiseId.equals(reiseId))).go();
        await batch(
          (b) => b.insertAll(reiseAufnahmen, [
            for (final id in assetIds)
              ReiseAufnahmenCompanion.insert(reiseId: reiseId, assetId: id),
          ]),
        );
        final zeitraum = await _zeitraumVon(assetIds);
        if (zeitraum != null) {
          await (update(reisen)..where((t) => t.id.equals(reiseId))).write(
            ReisenCompanion(von: Value(zeitraum.von), bis: Value(zeitraum.bis)),
          );
        }
      });

  /// Erste und letzte Aufnahmezeit einer Menge – `null` bei einer leeren
  /// Menge.
  ///
  /// Dann bleibt der bisherige Zeitraum stehen: Eine Reise ohne Bilder
  /// hat keinen belegten Zeitraum, und „1970" wäre eine Behauptung. Sie
  /// steht dann eben mit ihrem alten Datum in der Liste, bis wieder etwas
  /// darin liegt.
  Future<({DateTime von, DateTime bis})?> _zeitraumVon(
    Set<String> assetIds,
  ) async {
    if (assetIds.isEmpty) return null;
    final zeiten =
        await (select(assets)
              ..where((t) => t.id.isIn(assetIds))
              ..orderBy([(t) => OrderingTerm.asc(t.fileCreatedAt)]))
            .get();
    if (zeiten.isEmpty) return null;
    return (von: zeiten.first.fileCreatedAt, bis: zeiten.last.fileCreatedAt);
  }

  /// Welche Aufnahme zu welcher Reise gehört – für die Zuordnung einer
  /// Aktivität (siehe `reiseFuerAktivitaet`).
  /// Wie viele Aufnahmen je Reise – eine Abfrage für alle.
  ///
  /// Als Zahl und nicht als Liste: Gebraucht wird sie dort, wo man
  /// entscheidet, welche Reisen zusammengehören, und dafür genügt die
  /// Ziffer. (Siehe die Papierkorb-Kennzahl der Runde vom 31.08.: Zwei
  /// Stellen zogen 618 volle Zeilen, um deren Länge zu zeigen.)
  Future<Map<String, int>> aufnahmenzahlJeReise() async {
    final zeilen = await customSelect(
      'SELECT reise_id, count(*) AS n FROM reise_aufnahmen GROUP BY reise_id',
      readsFrom: {reiseAufnahmen},
    ).get();
    return {
      for (final z in zeilen) z.read<String>('reise_id'): z.read<int>('n'),
    };
  }

  /// Setzt die Art einer Reise (siehe [Reiseart]).
  Future<void> setzeReiseart(String id, String art) => (update(
    reisen,
  )..where((t) => t.id.equals(id))).write(ReisenCompanion(art: Value(art)));

  Future<Map<String, String>> reiseJeAufnahme() async => {
    for (final z in await select(reiseAufnahmen).get()) z.assetId: z.reiseId,
  };
}

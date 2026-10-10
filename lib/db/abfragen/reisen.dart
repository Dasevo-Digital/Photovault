part of '../database.dart';

/// Reisen.
extension ReisenAbfragen on AppDatabase {
  // ------------------------------------------------------------------
  // Reisen
  // ------------------------------------------------------------------

  // **Der gesperrte Ordner bleibt aus ALLEN Abfragen dieses Abschnitts
  // heraus** – auch aus denen, die nichts anzeigen.
  //
  // Nicht nur aus dem Raster: Eine gesperrte Aufnahme, die an der
  // Reiseerkennung teilnimmt, landet in einer bestätigten Reise und wird
  // dann angezeigt. Und selbst der Länderzähler verriete etwas – ein
  // Land, das nur auf gesperrten Fotos vorkommt, stünde dort und sagte
  // „da war jemand".
  //
  // Eine Regel für alle statt vier Einzelfallentscheidungen. Wer die Orte
  // gesperrter Aufnahmen sehen will, öffnet den gesperrten Ordner – dort
  // gehören sie hin.
  //
  // Der Unterschied zu Abfragen wie `assetsForLocationBackfill`, die
  // gesperrte Aufnahmen bewusst mitnehmen: Jene **verarbeiten** nur. Die
  // hier münden alle in eine Anzeige.

  Stream<List<ReisenData>> watchReisen() =>
      (select(reisen)..orderBy([(t) => OrderingTerm.desc(t.von)])).watch();

  Future<List<ReisenData>> alleReisen() =>
      (select(reisen)..orderBy([(t) => OrderingTerm.desc(t.von)])).get();

  Future<ReisenData?> reise(String id) =>
      (select(reisen)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Legt eine bestätigte Reise samt ihren Aufnahmen an.
  ///
  /// In einer Transaktion: Eine Reise ohne ihre Aufnahmen sähe aus wie
  /// eine leere Reise, und niemand könnte hinterher sagen, ob sie so
  /// gemeint war.
  Future<void> reiseAnlegen(ReisenCompanion reise, List<String> assetIds) =>
      transaction(() async {
        await into(reisen).insert(reise);
        await batch(
          (b) => b.insertAll(reiseAufnahmen, [
            for (final id in assetIds)
              ReiseAufnahmenCompanion.insert(
                reiseId: reise.id.value,
                assetId: id,
              ),
          ]),
        );
      });

  Future<void> reiseLoeschen(String id) => transaction(() async {
    await (delete(reiseAufnahmen)..where((t) => t.reiseId.equals(id))).go();
    // Sonst blieben die Tagesnotizen einer geloeschten Reise stehen
    // und taeten so, als gehoerten sie zur naechsten mit derselben
    // Kennung - dieselbe Sorte Rest wie die verwaisten
    // Gesichtsausschnitte der 8. Pruefrunde.
    await (delete(reisetagnotizen)..where((t) => t.reiseId.equals(id))).go();
    // **Aktivitäten und Spuren überleben, ihre Reise nicht.** Sie
    // hingen bisher an der Kennung der gelöschten Reise weiter: eine
    // Wanderung, die zu einer Reise gehört, die es nicht mehr gibt.
    // Gezeigt hätte sie „Gehört zu: " und nichts dahinter.
    await (update(aktivitaeten)..where((t) => t.reiseId.equals(id))).write(
      const AktivitaetenCompanion(reiseId: Value(null)),
    );
    await (update(spuren)..where((t) => t.reiseId.equals(id))).write(
      const SpurenCompanion(reiseId: Value(null)),
    );
    await (delete(reisen)..where((t) => t.id.equals(id))).go();
  });

  /// Führt Reisen zusammen: Die [quellen] gehen in [ziel] auf.
  ///
  /// **Warum es das braucht.** Die Erkennung trennt zwei Reisen, sobald
  /// mehr als zwei Tage ohne Aufnahme dazwischenliegen (siehe
  /// `reiseLueckeTage`). Bei einem Urlaub ist das richtig; bei einem
  /// langen Aufenthalt ist es genau falsch – die 199 verorteten
  /// Aufnahmen eines zweimonatigen Auslandseinsatzes zerfielen dadurch
  /// in vier Vorschläge von 25, 63, 89 und 20 Bildern, und zwei weitere
  /// fielen ganz heraus, weil sie unter der Mindestzahl blieben. Ein
  /// Einsatz ist keine Reise mit Lücken; er *ist* die Lücken.
  ///
  /// Die Schwelle deshalb zu lockern wäre der falsche Griff: Sie ist für
  /// den Regelfall richtig, und wer sie hochsetzt, bekommt aus zwei
  /// Wochenenden im selben Monat eine Reise. Zusammenführen ist die
  /// Entscheidung eines Menschen, und die trifft er einmal.
  ///
  /// **[ziel] behält Namen, Art, Titelbild und Notiz** – es ist die
  /// Reise, die stehenbleibt. Zeitraum und Aufnahmen wachsen um die der
  /// Quellen; Tagesnotizen kommen mit, wo das Ziel für den Tag noch
  /// keine hat. Aktivitäten und Spuren der Quellen hängen danach am Ziel.
  Future<void> reisenZusammenfuehren(String ziel, List<String> quellen) async {
    final andere = quellen.where((q) => q != ziel).toList();
    if (andere.isEmpty) return;
    final platzhalter = List.filled(andere.length, '?').join(', ');

    await transaction(() async {
      // `OR IGNORE`: Eine Aufnahme, die in beiden Reisen steht, ist kein
      // Fehler – sie steht danach einmal in der einen.
      await customStatement(
        'INSERT OR IGNORE INTO reise_aufnahmen (reise_id, asset_id) '
        'SELECT ?, asset_id FROM reise_aufnahmen WHERE reise_id IN ($platzhalter)',
        [ziel, ...andere],
      );
      // Beim Tag gewinnt die Notiz des Ziels: Sie ist die, die
      // stehenbleibt, und zwei Sätze zu einem Tag zusammenzukleben
      // ergäbe einen dritten, den niemand geschrieben hat.
      await customStatement(
        'INSERT OR IGNORE INTO reisetagnotizen '
        '(reise_id, tag, notiz, geaendert_am) '
        'SELECT ?, tag, notiz, geaendert_am FROM reisetagnotizen '
        'WHERE reise_id IN ($platzhalter)',
        [ziel, ...andere],
      );
      await (update(aktivitaeten)..where((t) => t.reiseId.isIn(andere))).write(
        AktivitaetenCompanion(reiseId: Value(ziel)),
      );
      await (update(spuren)..where((t) => t.reiseId.isIn(andere))).write(
        SpurenCompanion(reiseId: Value(ziel)),
      );
      await (delete(reiseAufnahmen)..where((t) => t.reiseId.isIn(andere))).go();
      await (delete(
        reisetagnotizen,
      )..where((t) => t.reiseId.isIn(andere))).go();
      await (delete(reisen)..where((t) => t.id.isIn(andere))).go();

      // **Zeitraum aus den Aufnahmen und nicht aus den Reisen.** Wer
      // eine Aufnahme aus einer der Quellen genommen hatte, soll ihren
      // Tag nicht über den Umweg des gespeicherten Zeitraums
      // zurückbekommen.
      final frueheste = assets.fileCreatedAt.min();
      final spaeteste = assets.fileCreatedAt.max();
      final spanne =
          await (selectOnly(reiseAufnahmen).join([
                  innerJoin(
                    assets,
                    assets.id.equalsExp(reiseAufnahmen.assetId),
                  ),
                ])
                ..addColumns([frueheste, spaeteste])
                ..where(reiseAufnahmen.reiseId.equals(ziel)))
              .getSingleOrNull();
      final anfang = spanne?.read(frueheste);
      final ende = spanne?.read(spaeteste);
      if (anfang != null && ende != null) {
        await (update(reisen)..where((t) => t.id.equals(ziel))).write(
          ReisenCompanion(von: Value(anfang), bis: Value(ende)),
        );
      }
    });
  }

  /// Die Tagesnotizen einer Reise, nach Tag.
  ///
  /// Als Karte und nicht als Liste: Die Ansicht fragt je Kapitel genau
  /// einen Tag ab, und eine Liste hiesse, sie bei jedem Kapitel erneut
  /// zu durchsuchen.
  Future<Map<DateTime, String>> reisetagnotizenFuer(String reiseId) async {
    final zeilen = await (select(
      reisetagnotizen,
    )..where((t) => t.reiseId.equals(reiseId))).get();
    return {for (final z in zeilen) z.tag: z.notiz};
  }

  /// Schreibt die Notiz eines Reisetages – leerer Text loescht sie.
  ///
  /// Leer heisst „keine Notiz" und nicht „eine leere Notiz": Sonst
  /// stuende unter der Ueberschrift ein leerer Absatz, und das Kapitel
  /// saehe aus, als fehle etwas.
  Future<void> setzeReisetagnotiz(
    String reiseId,
    DateTime tag,
    String text,
  ) async {
    final tagesbeginn = DateTime(tag.year, tag.month, tag.day);
    final sauber = text.trim();
    if (sauber.isEmpty) {
      await (delete(reisetagnotizen)..where(
            (t) => t.reiseId.equals(reiseId) & t.tag.equals(tagesbeginn),
          ))
          .go();
      return;
    }
    await into(reisetagnotizen).insertOnConflictUpdate(
      ReisetagnotizenCompanion.insert(
        reiseId: reiseId,
        tag: tagesbeginn,
        notiz: sauber,
        geaendertAm: DateTime.now(),
      ),
    );
  }

  Future<void> reiseAendern(String id, ReisenCompanion aenderung) =>
      (update(reisen)..where((t) => t.id.equals(id))).write(aenderung);

  /// Die Aufnahmen einer Reise, chronologisch.
  ///
  /// Gelöschte und in den Papierkorb gelegte fallen heraus – eine Reise
  /// soll nicht auf Bilder verweisen, die es nicht mehr gibt.
  Future<List<AssetData>> aufnahmenDerReise(String reiseId) async {
    final abfrage =
        select(assets).join([
            innerJoin(
              reiseAufnahmen,
              reiseAufnahmen.assetId.equalsExp(assets.id),
            ),
          ])
          ..where(
            reiseAufnahmen.reiseId.equals(reiseId) &
                assets.isTrashed.equals(false) &
                // Siehe die Regel am Anfang dieses Abschnitts.
                assets.isLocked.equals(false),
          )
          ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)]);
    return [for (final z in await abfrage.get()) z.readTable(assets)];
  }

  /// Nur die erste Aufnahme einer Reise – für das Vorschaubild in der
  /// Liste.
  ///
  /// Eine eigene Abfrage mit `LIMIT 1` statt [aufnahmenDerReise] und
  /// `.first`. Gemessen an zwanzig Reisen mit je dreihundert Aufnahmen:
  /// 5865 geladene Zeilen und 92 ms, um zwanzig Vorschaubilder zu zeigen.
  /// Der Aufwand wächst mit der Größe der Reisen, der Nutzen nicht.
  Future<AssetData?> ersteAufnahmeDerReise(String reiseId) async {
    final abfrage =
        select(assets).join([
            innerJoin(
              reiseAufnahmen,
              reiseAufnahmen.assetId.equalsExp(assets.id),
            ),
          ])
          ..where(
            reiseAufnahmen.reiseId.equals(reiseId) &
                assets.isTrashed.equals(false) &
                assets.isLocked.equals(false),
          )
          ..orderBy([OrderingTerm.asc(assets.fileCreatedAt)])
          ..limit(1);
    final zeile = await abfrage.getSingleOrNull();
    return zeile?.readTable(assets);
  }

  /// Der Ortsbezug jeder Reise, in einer Abfrage für alle.
  ///
  /// **Warum nicht je Zeile nachschlagen.** Die Übersicht zeigt zu jeder
  /// Reise, wo sie stattfand. Der Ort steht aber nicht an der Reise – er
  /// steht an ihren Aufnahmen, und zwar an jeder einzelnen. Für eine
  /// Liste von dreissig Reisen hiesse „je Zeile nachschlagen" dreissig
  /// Abfragen über zusammen mehrere tausend Aufnahmen, nur um drei
  /// Wörter anzuzeigen.
  ///
  /// Gruppiert liefert dieselbe Auskunft eine einzige Abfrage: je Reise
  /// und Ort eine Zeile mit Anzahl. Das sind auch bei grossen
  /// Bibliotheken wenige hundert Zeilen, weil zusammengefasst wird, was
  /// gleich ist.
  Future<Map<String, Ortsbezug>> ortsbezugJeReise() =>
      _ortsbezug('reise_aufnahmen', 'reise_id', reiseAufnahmen);

  /// Der Ortsbezug jeder Aktivität – wie [ortsbezugJeReise].
  Future<Map<String, Ortsbezug>> ortsbezugJeAktivitaet() =>
      _ortsbezug('aktivitaet_aufnahmen', 'aktivitaet_id', aktivitaetAufnahmen);

  Future<Map<String, Ortsbezug>> _ortsbezug(
    String tabelle,
    String spalte,
    TableInfo zuordnung,
  ) async {
    // **CROSS JOIN und nicht JOIN, und das ist keine Kosmetik.** In
    // SQLite ist beides bedeutungsgleich; `CROSS` schaltet nur die
    // Umsortierung der Schleifen ab und legt fest, dass die
    // **Zuordnungstabelle** aussen läuft.
    //
    // Ohne das entscheidet der Planer falsch herum: Er sieht den Index
    // über `is_trashed`/`is_locked`, hält ihn für den engeren Filter und
    // beginnt bei den Aufnahmen. Für jede einzelne davon schlägt er dann
    // in der Zuordnung nach — auch für die neunundneunzig Prozent, die
    // zu gar keiner Reise gehören. An einer auf 103.844 Aufnahmen
    // aufgeblasenen Kopie der echten Bibliothek nachgemessen, bei 423
    // Zuordnungen:
    //
    // ```
    // JOIN        SEARCH a USING idx_assets_trashed_locked_created   36,5 ms
    // CROSS JOIN  SCAN z USING COVERING INDEX, SEARCH a (id=?)        0,3 ms
    // ```
    //
    // Heute, bei 7.988 Aufnahmen, sind es 20 ms — nicht zu spüren.
    // Genau deshalb steht die Messung hier: Der Unterschied wächst mit
    // der Bibliothek, die Zuordnungstabelle wächst nicht mit.
    final zeilen = await customSelect(
      'SELECT z.$spalte AS kennung, a.location_city AS ort, '
      '       a.location_state AS region, a.location_country AS land, '
      '       COUNT(*) AS anzahl '
      'FROM $tabelle z CROSS JOIN assets a ON a.id = z.asset_id '
      'WHERE a.is_trashed = 0 AND a.is_locked = 0 '
      'GROUP BY z.$spalte, a.location_city, a.location_state, '
      '         a.location_country',
      readsFrom: {assets, zuordnung},
    ).get();

    // Je Kennung: die Aufnahmen zusammenzählen und den häufigsten Ort
    // behalten. Bei Gleichstand gewinnt der alphabetisch erste - nicht
    // weil er der bessere wäre, sondern damit dieselbe Bibliothek
    // zweimal dasselbe anzeigt.
    final gesamt = <String, int>{};
    final beste =
        <String, ({String ort, String? region, String? land, int n})>{};
    final orte = <String, Set<String>>{};
    for (final z in zeilen) {
      final kennung = z.read<String>('kennung');
      final anzahl = z.read<int>('anzahl');
      gesamt[kennung] = (gesamt[kennung] ?? 0) + anzahl;

      final ort = z.read<String?>('ort');
      if (ort == null || ort.isEmpty) continue;
      orte.putIfAbsent(kennung, () => <String>{}).add(ort);
      final bisher = beste[kennung];
      if (bisher == null ||
          anzahl > bisher.n ||
          (anzahl == bisher.n && ort.compareTo(bisher.ort) < 0)) {
        beste[kennung] = (
          ort: ort,
          region: z.read<String?>('region'),
          land: z.read<String?>('land'),
          n: anzahl,
        );
      }
    }

    return {
      for (final kennung in gesamt.keys)
        kennung: (
          ort: beste[kennung]?.ort,
          region: beste[kennung]?.region,
          land: beste[kennung]?.land,
          // Der häufigste zählt nicht als „weiterer".
          weitereOrte: (orte[kennung]?.length ?? 0) == 0
              ? 0
              : orte[kennung]!.length - 1,
          aufnahmen: gesamt[kennung]!,
        ),
    };
  }

  /// Welche Aufnahmen bereits einer Reise zugeordnet sind.
  Future<Set<String>> zugeordneteReiseAufnahmen() async => {
    for (final z in await select(reiseAufnahmen).get()) z.assetId,
  };

  Future<void> aufnahmenZurReise(String reiseId, List<String> assetIds) =>
      batch(
        (b) => b.insertAll(reiseAufnahmen, [
          for (final id in assetIds)
            ReiseAufnahmenCompanion.insert(reiseId: reiseId, assetId: id),
        ], mode: InsertMode.insertOrIgnore),
      );

  Future<void> aufnahmeAusReise(String reiseId, String assetId) => (delete(
    reiseAufnahmen,
  )..where((t) => t.reiseId.equals(reiseId) & t.assetId.equals(assetId))).go();
}

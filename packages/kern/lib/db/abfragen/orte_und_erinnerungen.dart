part of '../database.dart';

/// Verortete Aufnahmen, „An diesem Tag“, gemerkte Erinnerungen, bearbeitete Dateien.
extension ErinnerungsAbfragen on AppDatabase {
  /// Alle nicht gelöschten Assets mit aufgelöstem Orts-Namen (Land/
  /// Bundesland/Stadt), neueste zuerst – für die "Erkannte Orte"-Sektion im
  /// Erkunden-Tab. Die Gruppierung zu einem repräsentativen Foto je Ort
  /// (erstes Vorkommen = zeitlich aktuellstes Foto dieses Orts) übernimmt der
  /// Aufrufer, da sie reine Präsentationslogik ist.
  Future<List<AssetData>> assetsWithResolvedLocation() =>
      (select(assets)
            ..where(
              (t) =>
                  t.isTrashed.equals(false) &
                  t.isLocked.equals(false) &
                  t.locationCity.isNotNull() &
                  // Sonst würde das .mov eines Live-Photos als eigenes Foto am
                  // selben Ort mitgezählt (siehe searchAssets).
                  _isPrimaryGridEntry(t),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]))
          .get();

  /// Alle nicht gelöschten Assets mit bekanntem Ort – für die Kartenansicht.
  Future<List<AssetData>> assetsWithLocation() =>
      (select(assets)..where(_mitOrt)).get();

  /// Zählvariante, siehe [countLocationBackfill].
  ///
  /// Gebraucht dort, wo nur die Frage „gibt es überhaupt einen Ort?"
  /// ansteht – die Übersicht blendet den Abschnitt sonst ein und zeigt
  /// eine leere Karte. Die Liste dafür zu laden hiesse, mehrere tausend
  /// Zeilen zu holen, um `isNotEmpty` zu fragen, und zwar ein zweites
  /// Mal neben der Karte, die sie ohnehin lädt.
  Future<int> countAssetsWithLocation() => _countWhere(_mitOrt(assets));

  Expression<bool> _mitOrt($AssetsTable t) =>
      t.isTrashed.equals(false) &
      t.isLocked.equals(false) &
      t.latitude.isNotNull() &
      t.longitude.isNotNull() &
      _isPrimaryGridEntry(t);

  /// Der Schwerpunkt aller verorteten Aufnahmen – als eine Zeile.
  ///
  /// Dieselbe Menge wie [assetsWithLocation], nur eben nicht als Menge:
  /// Wer den Mittelpunkt sucht, braucht keine 1091 vollständigen Zeilen.
  /// An einer echten Bibliothek gemessen (7988 Aufnahmen, 1091 davon
  /// verortet): **76 ms für die vollen Zeilen, 2 ms für diese Abfrage** –
  /// und der Weg, auf dem sie gebraucht wird, läuft bei jedem Start
  /// (siehe `LibraryState.trageEreignisorteNach`).
  ///
  /// `null`, wenn keine einzige Aufnahme verortet ist – dann gibt es
  /// keinen Schwerpunkt, und ein geratener wäre schlimmer als keiner.
  Future<({double breite, double laenge})?> schwerpunktVerorteterFotos() async {
    final breite = assets.latitude.avg();
    final laenge = assets.longitude.avg();
    final zeile =
        await (selectOnly(assets)
              ..addColumns([breite, laenge])
              ..where(
                assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false) &
                    assets.latitude.isNotNull() &
                    assets.longitude.isNotNull() &
                    _isPrimaryGridEntry(assets),
              ))
            .getSingle();
    final b = zeile.read(breite);
    final l = zeile.read(laenge);
    return b == null || l == null ? null : (breite: b, laenge: l);
  }

  /// Trägt für mehrere Ereignisse auf einmal die Koordinate nach.
  ///
  /// **In einem Rutsch und nicht Zeile für Zeile.** Jedes einzelne
  /// `UPDATE` ist sonst eine eigene Transaktion mit eigenem Schreiben auf
  /// die Platte. An einer Dateidatenbank gemessen, 600 Ereignisse – so
  /// viele bringt ein GEDCOM mit 300 Personen mit:
  /// **einzeln 209 ms, gesammelt 4 ms.**
  Future<void> setzeEreignisorte(
    Map<String, ({double breite, double laenge})> orte,
  ) => batch((b) {
    for (final e in orte.entries) {
      b.update(
        lebensereignisse,
        LebensereignisseCompanion(
          ortBreite: Value(e.value.breite),
          ortLaenge: Value(e.value.laenge),
        ),
        where: (t) => t.id.equals(e.key),
      );
    }
  });

  /// Alle Fotos/Videos, die exakt heute vor 1, 2, 3 … Jahren aufgenommen
  /// wurden (Monat+Tag, unabhängig vom Aufnahmejahr) – für die
  /// "Erinnerungen"-Sektion im Erkunden-Tab, analog zu "Vor X Jahren" in
  /// Google Fotos/Apple Fotos.
  ///
  /// **In zwei Schritten: erst fragen, wer gemeint ist, dann die Gemeinten
  /// laden.** Der Tagesvergleich bleibt in Dart – `strftime(…, 'localtime')`
  /// wäre eine Wette auf die Zeitzonenrechnung von SQLite gegen die von
  /// Dart, und an einem ganzen Jahr durchgespielt lieferte sie zwar überall
  /// dieselbe Anzahl, aber bei gleichen Zeitstempeln eine andere
  /// Reihenfolge. Gefragt wird deshalb nur nach Kennung und Datum, und erst
  /// die Handvoll Treffer wird vollständig geladen.
  ///
  /// Vorher wurde die **ganze Bibliothek** in Objekte umgesetzt, um daraus
  /// zwei Fotos zu behalten – 56 Spalten mal 7341 Zeilen für einen Vergleich
  /// von Monat und Tag. An der gewachsenen Bibliothek gemessen, und über
  /// alle 366 Tage gegen die alte Fassung geprüft (6141 Treffer an 260
  /// Tagen, keine Abweichung):
  ///
  /// ```
  /// alles laden, in Dart filtern   250,1 ms
  /// erst Kennung und Datum          30,9 ms
  /// ```
  /// Die Erinnerungen: was heute vor Jahren entstanden ist.
  ///
  /// **Ohne geschätzte Daten.** Ein geratener Zeitstempel ist hier
  /// besonders schädlich, weil dieser Abschnitt aus dem Datum eine
  /// Behauptung macht: „vor 20 Jahren, an genau diesem Tag". An der
  /// echten Bibliothek liegen 948 Aufnahmen auf einem einzigen erfundenen
  /// Zeitpunkt – am 27. August wären sie alle auf einmal erschienen, und
  /// keine einzige davon entstand an diesem Tag.
  ///
  /// **Die Marke allein genuegt nicht.** `datum_geschaetzt` wird erst
  /// gesetzt, wenn der Lauf „Herkunft der Aufnahmedaten" ueber die
  /// Bibliothek gegangen ist – an der echten stand sie am 10.09.2026 bei
  /// **0**, und die Abwehr oben war damit wirkungslos: Am 27. August
  /// haette dieser Abschnitt 1103 Aufnahmen gezeigt, 1096 davon mit einer
  /// erfundenen Uhrzeit.
  ///
  /// Deshalb zusaetzlich der Verdacht selbst, der keinen Lauf braucht:
  /// ein Zeitstempel auf voller Ortszeit-Stunde (siehe
  /// [countAuffaelligeAufnahmedaten]). Der Preis dafuer sind die rund
  /// **zwei** Aufnahmen, die eine volle Stunde zufaellig treffen; der
  /// Ertrag sind die 1095, die es nicht zufaellig tun.
  Future<List<AssetData>> assetsOnThisDay(DateTime today) async {
    final schlank = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            assets.datumGeschaetzt.equals(false) &
            _nichtAufVollerStunde() &
            _isPrimaryGridEntry(assets),
      );
    final treffer = <String>[];
    for (final zeile in await schlank.get()) {
      // Über `rawData` und nicht über `zeile.read(assets.fileCreatedAt)`:
      // Der bequeme Weg schlägt jede Spalte über ihren Typ-Umsetzer nach,
      // und bei 7341 Zeilen kostete allein das die Hälfte der Zeit (58 ms
      // gegen 31 ms). Die Namen sind die, die drift der Abfrage gibt –
      // stimmten sie nicht, führe das Lesen sofort in einen Fehler, und
      // [assetsOnThisDayGleichAlterWeg] fängt das im Prüfstand ab.
      final wann = DateTime.fromMillisecondsSinceEpoch(
        zeile.rawData.read<int>('assets.file_created_at') * 1000,
      );
      if (wann.month == today.month &&
          wann.day == today.day &&
          wann.year != today.year) {
        treffer.add(zeile.rawData.read<String>('assets.id'));
      }
    }
    if (treffer.isEmpty) return const [];
    final geladen = await (select(
      assets,
    )..where((t) => t.id.isIn(treffer))).get();
    return geladen..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
  }

  /// Was an jedem der [tage] in früheren Jahren entstanden ist – für die
  /// Erinnerungsseite, die zwei Wochen zurückblickt.
  ///
  /// **Ein Durchgang statt einer Frage je Tag.** [assetsOnThisDay] liest
  /// die schlanke Liste aller Aufnahmen (31 ms an der echten
  /// Bibliothek); vierzehnmal hintereinander wäre fast eine halbe Sekunde.
  /// Dieselben Regeln: kein geratenes Datum, keins auf voller Stunde,
  /// nichts aus Papierkorb oder Tresor, nur das Gesicht eines Stapels.
  Future<Map<DateTime, List<AssetData>>> assetsAnTagen(
    List<DateTime> tage,
  ) async {
    final gesucht = {for (final t in tage) t.month * 100 + t.day: t};
    final schlank = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            assets.datumGeschaetzt.equals(false) &
            _nichtAufVollerStunde() &
            _isPrimaryGridEntry(assets),
      );
    final jeTag = <DateTime, List<String>>{};
    for (final zeile in await schlank.get()) {
      final wann = DateTime.fromMillisecondsSinceEpoch(
        zeile.rawData.read<int>('assets.file_created_at') * 1000,
      );
      final tag = gesucht[wann.month * 100 + wann.day];
      if (tag == null || wann.year >= tag.year) continue;
      (jeTag[tag] ??= []).add(zeile.rawData.read<String>('assets.id'));
    }
    if (jeTag.isEmpty) return const {};
    final alle = {
      for (final a in await (select(
        assets,
      )..where((t) => t.id.isIn(jeTag.values.expand((x) => x)))).get())
        a.id: a,
    };
    return {
      for (final MapEntry(key: tag, value: ids) in jeTag.entries)
        tag: [for (final id in ids) ?alle[id]]
          ..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt)),
    };
  }

  /// Die Reisen mit den meisten Lieblingsfotos – favorisiert oder mit
  /// vier, fünf Sternen –, die besten zuerst. Reisen ohne ein einziges
  /// bleiben draussen: „schönste" nach einer Zahl, die null ist, wäre nur
  /// die Reihenfolge der Tabelle.
  Future<List<({ReisenData reise, int lieblinge})>> schoensteReisen({
    int hoechstens = 8,
  }) async {
    final zeilen = await customSelect(
      '''SELECT ra.reise_id AS id, COUNT(*) AS n
         FROM reise_aufnahmen ra JOIN assets a ON a.id = ra.asset_id
         WHERE a.is_trashed = 0 AND a.is_locked = 0
           AND (a.is_favorite = 1 OR a.rating >= 4)
         GROUP BY ra.reise_id ORDER BY n DESC LIMIT ?''',
      variables: [Variable.withInt(hoechstens)],
      readsFrom: {reiseAufnahmen, assets},
    ).get();
    final gefunden = {
      for (final r
          in await (select(reisen)..where(
                (t) =>
                    t.id.isIn([for (final z in zeilen) z.read<String>('id')]),
              ))
              .get())
        r.id: r,
    };
    return [
      for (final z in zeilen)
        if (gefunden[z.read<String>('id')] case final reise?)
          (reise: reise, lieblinge: z.read<int>('n')),
    ];
  }

  Future<List<GemerkteErinnerungenData>> alleGemerktenErinnerungen() => (select(
    gemerkteErinnerungen,
  )..orderBy([(t) => OrderingTerm.desc(t.tag)])).get();

  Future<void> merkeErinnerung({
    required String id,
    required String titel,
    required DateTime tag,
    required List<String> assetIds,
  }) => into(gemerkteErinnerungen).insertOnConflictUpdate(
    GemerkteErinnerungenCompanion.insert(
      id: id,
      titel: titel,
      tag: tag,
      assetIds: jsonEncode(assetIds),
      gemerktAm: DateTime.now(),
    ),
  );

  Future<void> vergissErinnerung(String id) =>
      (delete(gemerkteErinnerungen)..where((t) => t.id.equals(id))).go();

  /// Die Aufnahmen einer gemerkten Erinnerung, in ihrer Reihenfolge –
  /// ohne die, die inzwischen gelöscht oder gesperrt sind.
  Future<List<AssetData>> aufnahmenDerErinnerung(
    GemerkteErinnerungenData e,
  ) async {
    final ids = (jsonDecode(e.assetIds) as List).cast<String>();
    return [
      for (final a in await assetsByIds(ids))
        if (!a.isTrashed && !a.isLocked) a,
    ];
  }

  /// Was in diesem **Monat** frueherer Jahre entstanden ist – ohne den
  /// heutigen Tag, denn den zeigt [assetsOnThisDay].
  ///
  /// **Warum es die zweite, weitere Frage braucht.** Der Tagesabschnitt
  /// trifft an der echten Bibliothek nur an **261 von 365** Tagen etwas,
  /// und an 107 davon sind es hoechstens drei Aufnahmen. An den uebrigen
  /// 104 Tagen verschwand der Abschnitt wortlos – heute, am 12.
  /// September, war das so. Der Monat ist die naechstgroessere Frage, die
  /// fast immer eine Antwort hat, und sie ist genauso wahr: „im
  /// September vor 13 Jahren" behauptet nichts ueber den Tag.
  ///
  /// [hoechstensJeJahr] deckelt, was ein einzelner Jahrgang beisteuert –
  /// ohne das waere ein Monat mit 900 Aufnahmen kein Rueckblick, sondern
  /// die Zeitleiste.
  Future<List<AssetData>> assetsInDiesemMonat(
    DateTime heute, {
    int hoechstensJeJahr = 12,
  }) async {
    final schlank = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            assets.datumGeschaetzt.equals(false) &
            _nichtAufVollerStunde() &
            _isPrimaryGridEntry(assets),
      );
    final jeJahr = <int, List<String>>{};
    for (final zeile in await schlank.get()) {
      final wann = DateTime.fromMillisecondsSinceEpoch(
        zeile.rawData.read<int>('assets.file_created_at') * 1000,
      );
      if (wann.month != heute.month || wann.year == heute.year) continue;
      if (wann.day == heute.day) continue;
      final liste = jeJahr.putIfAbsent(wann.year, () => []);
      if (liste.length < hoechstensJeJahr) {
        liste.add(zeile.rawData.read<String>('assets.id'));
      }
    }
    final treffer = [for (final l in jeJahr.values) ...l];
    if (treffer.isEmpty) return const [];
    final geladen = await (select(
      assets,
    )..where((t) => t.id.isIn(treffer))).get();
    return geladen..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
  }

  /// Ersetzt Original-Datei (Pfad + Prüfsumme) eines Assets nach einer
  /// Bildbearbeitung (Zuschneiden/Drehen/Spiegeln, siehe
  /// `speichereBearbeitung`). Löscht eine ggf. vorhandene konvertierte
  /// Vorschau (HEIC/RAW & Co.): nach der Bearbeitung ist die neue
  /// Originaldatei selbst bereits ein direkt darstellbares JPEG.
  ///
  /// [fileSizeBytes] ist die Grösse der neuen Datei. Ohne sie führte ein
  /// 3-MP-JPEG weiter die 68 MB seines DNG.
  Future<void> setEditedAssetFile(
    String assetId, {
    required String relativePath,
    required String checksum,
    int? fileSizeBytes,
  }) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      relativePath: Value(relativePath),
      checksum: Value(checksum),
      fileSizeBytes: fileSizeBytes == null
          ? const Value.absent()
          : Value(fileSizeBytes),
      previewRelativePath: const Value(null),
      // Ein evtl. vorhandenes entwickeltes Bild wurde für die ALTE
      // Pixel-Grundlage berechnet (vor Zuschnitt/Drehung) und würde nach
      // dem destruktiven Bearbeiten falschen Inhalt zeigen – die
      // DevelopSettings-Zeile selbst bleibt bewusst bestehen (der Nutzer
      // müsste sie sonst nach jedem Zuschnitt neu einstellen), nur der
      // veraltete gerenderte Cache wird hier zurückgesetzt.
      developedRelativePath: const Value(null),
    ),
  );

  /// Setzt den ursprünglichen, für Menschen lesbaren Dateinamen – u.a. nach
  /// einem Restore aus einem Backup nötig: der Reimport dort liest den
  /// Namen zunächst aus dem Backup-Pfad (`originals/{yyyy}/{mm}/{id}.ext`,
  /// also der Asset-UUID statt des Originalnamens), erst
  /// [BackupService._applyMetadataExport] korrigiert ihn anschließend
  /// anhand von metadata.json.
  Future<void> setOriginalFileName(String assetId, String name) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(originalFileName: Value(name)),
      );
}

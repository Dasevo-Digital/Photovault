part of '../database.dart';

/// Aufnahmen, Zeitleiste und die Datenströme, die einen Schwall aushalten.
extension AufnahmenAbfragen on AppDatabase {
  Future<AssetData?> assetById(String id) =>
      (select(assets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Prüft anhand der Prüfsumme, ob eine Datei bereits importiert wurde
  /// (Duplikaterkennung beim Import).
  Future<bool> checksumExists(String checksum) async {
    final row = await (select(
      assets,
    )..where((t) => t.checksum.equals(checksum))).getSingleOrNull();
    return row != null;
  }

  /// "Eigenständig sichtbar" in Timeline/Kalender/Karte/Alben/Suche & Co.:
  /// weder das Video-Gegenstück eines Live-Photo-Paares (bleibt nur über das
  /// verknüpfte Foto sichtbar, siehe LivePhotoView) noch ein
  /// nicht-Titelbild-Mitglied eines Serien-Stapels (siehe createStack) –
  /// exakt dasselbe OR-Muster wie beim Live-Photo-Verstecken, nur einmal
  /// formuliert statt an jeder der rund ein Dutzend Fundstellen wiederholt.
  Expression<bool> _isPrimaryGridEntry($AssetsTable t) =>
      (t.type.equals('IMAGE') | t.linkedAssetId.isNull()) &
      (t.stackId.isNull() | t.isStackCover.equals(true));

  /// Ein Datenstrom auf [bauen], der bei einem **Schwall** von Änderungen
  /// nicht jede einzelne nachrechnet.
  ///
  /// **Warum es das braucht.** Drift lässt eine `watch`-Abfrage bei jeder
  /// Änderung an einer beteiligten Tabelle neu laufen. Das ist richtig,
  /// solange Änderungen einzeln kommen — die Hintergrundaufgaben schreiben
  /// aber Zeile für Zeile, tausendfach hintereinander. An der gewachsenen
  /// Bibliothek gemessen, 200 einzelne Schreibvorgänge:
  ///
  /// ```
  /// ohne offene Zeitleiste                    0,5 s
  /// Zeitleiste offen, Ladefenster 600         3,7 s
  /// Zeitleiste offen, ganze Bibliothek       41,9 s
  /// ```
  ///
  /// Über 8000 Aufnahmen wären das aus einer halben Minute Schreibarbeit
  /// fast eine halbe Stunde — und die fällt im selben Faden an, in dem
  /// gezeichnet wird. Was da so teuer ist, sind nicht die Schreibvorgänge,
  /// sondern die 101 Neudurchläufe, die sie auslösen.
  ///
  /// **Die erste Antwort kommt trotzdem sofort.** Gedrosselt wird nur, was
  /// innerhalb von [drosselfenster] auf einen frischen Durchlauf folgt. Ein
  /// einzelner Handgriff — ein Herz gesetzt, ein Foto in den Papierkorb —
  /// wirkt also unverändert augenblicklich; erst der zweite Schreibvorgang
  /// in derselben Zehntelsekunde wartet. Eine Drosselung, die auch den
  /// ersten verzögerte, wäre an jeder einzelnen Stelle der Oberfläche zu
  /// spüren und hier nirgends nötig.
  Stream<List<D>> _gedrosselt<D>(
    Selectable<D> Function() bauen,
    TableUpdateQuery worauf, {
    Duration fenster = AppDatabase.drosselfenster,
  }) {
    late StreamController<List<D>> regler;
    StreamSubscription<void>? horcher;
    Timer? nachzuegler;
    var laeuft = false;
    var nochmal = false;
    DateTime? zuletzt;

    Future<void> frage() async {
      // Läuft schon eine Abfrage, wird die nächste einmal nachgeholt – aber
      // nur einmal. Ohne diese Klammer stapelten sich bei langsamen
      // Abfragen die Durchläufe genau dann, wenn es ohnehin eng ist.
      if (laeuft) {
        nochmal = true;
        return;
      }
      laeuft = true;
      zuletzt = DateTime.now();
      try {
        final zeilen = await bauen().get();
        if (!regler.isClosed) regler.add(zeilen);
      } catch (e, spur) {
        if (!regler.isClosed) regler.addError(e, spur);
      } finally {
        laeuft = false;
        if (nochmal) {
          nochmal = false;
          unawaited(frage());
        }
      }
    }

    void gemeldet() {
      // Ein Nachzügler ist schon bestellt – der holt alles mit ab.
      if (nachzuegler != null) return;
      final seit = zuletzt == null
          ? fenster
          : DateTime.now().difference(zuletzt!);
      if (seit >= fenster) {
        unawaited(frage());
      } else {
        nachzuegler = Timer(fenster - seit, () {
          nachzuegler = null;
          unawaited(frage());
        });
      }
    }

    regler = StreamController<List<D>>.broadcast(
      onListen: () {
        unawaited(frage());
        horcher = tableUpdates(worauf).listen((_) => gemeldet());
      },
      onCancel: () {
        nachzuegler?.cancel();
        nachzuegler = null;
        unawaited(horcher?.cancel());
        horcher = null;
      },
    );
    return regler.stream;
  }

  /// [limit] begrenzt auf die neuesten [limit] Fotos/Videos (per
  /// `idx_assets_trashed_locked_created` indexgestützt, also auch bei sehr
  /// großen Bibliotheken ein günstiger Index-Walk statt eines vollständigen
  /// Tabellen-Scans). Ohne [limit] wird – wie bisher – die komplette
  /// Zeitleiste geliefert; TimelineScreen nutzt [limit] für ein wachsendes
  /// Ladefenster (siehe dort), damit weder bei jeder Mutation noch beim
  /// ersten Öffnen zwingend die GESAMTE Bibliothek aus der DB geladen und in
  /// Dart neu gruppiert werden muss.
  Stream<List<AssetData>> watchTimeline({
    bool favoritesOnly = false,
    int? limit,
    Rastersortierung sortierung = rastersortierungVorgabe,
  }) {
    final query = select(assets)
      ..where(
        (t) =>
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            _isPrimaryGridEntry(t),
      );
    if (favoritesOnly) {
      query.where((t) => t.isFavorite.equals(true));
    }
    query.orderBy(_sortierterme(sortierung));
    if (limit != null) {
      query.limit(limit);
    }
    return _gedrosselt(() => query, TableUpdateQuery.onTable(assets));
  }

  /// [sortierungSql] als Abfragebauer-Fassung – fuer die Abfragen, die
  /// nicht als rohes SQL dastehen.
  ///
  /// Zwei Fassungen derselben Reihenfolge sind zwei Regeln, die
  /// auseinanderlaufen koennen; `sortierung_test.dart` haelt sie
  /// zusammen, indem es die erzeugte Abfrage gegen [sortierungSql]
  /// stellt.
  List<OrderingTerm Function($AssetsTable)> _sortierterme(
    Rastersortierung s,
  ) => switch (s) {
    Rastersortierung.aufnahmeNeu => [(t) => OrderingTerm.desc(t.fileCreatedAt)],
    Rastersortierung.aufnahmeAlt => [(t) => OrderingTerm.asc(t.fileCreatedAt)],
    Rastersortierung.importNeu => [
      (t) => OrderingTerm.desc(t.importedAt),
      (t) => OrderingTerm.desc(t.fileCreatedAt),
    ],
    Rastersortierung.name => [
      (t) => OrderingTerm.asc(t.originalFileName.collate(Collate.noCase)),
      (t) => OrderingTerm.desc(t.fileCreatedAt),
    ],
    Rastersortierung.bewertung => [
      (t) => OrderingTerm.desc(t.rating),
      (t) => OrderingTerm.desc(t.fileCreatedAt),
    ],
    Rastersortierung.groesse => [
      (t) => OrderingTerm.desc(t.fileSizeBytes),
      (t) => OrderingTerm.desc(t.fileCreatedAt),
    ],
  };

  /// Dieselbe Auswahl wie [watchTimeline], aber **nur die Spalten, die
  /// ein Raster anfasst** – siehe [Rasterzeile] für die Messung.
  ///
  /// Als rohes SQL und nicht über den Abfragebauer: Der liefert immer
  /// die ganze Zeile samt Abbildung auf `AssetData`, und genau die
  /// beiden Posten sollen hier wegfallen. `readsFrom` sorgt dafür, dass
  /// der Strom trotzdem meldet, wenn sich an `assets` etwas ändert.
  Stream<List<Rasterzeile>> watchRasterzeilen({
    bool favoritesOnly = false,
    int? limit,
    Rastersortierung sortierung = rastersortierungVorgabe,
  }) {
    final wo = StringBuffer(rasterSichtbar);
    if (favoritesOnly) wo.write(' AND is_favorite = 1');
    final grenze = limit == null ? '' : ' LIMIT $limit';
    return _gedrosselt(
      () => customSelect(
        'SELECT $rasterSpalten FROM assets WHERE $wo '
        'ORDER BY ${sortierungSql(sortierung)}$grenze',
        readsFrom: {assets},
      ).map(Rasterzeile.ausZeile),
      TableUpdateQuery.onTable(assets),
    );
  }

  /// Dieselbe Liste wie [watchTimeline], aber einmalig statt als Strom.
  ///
  /// Für Ansichten, die eine Auswahl treffen und danach fertig sind
  /// (siehe `AufnahmenWaehlenScreen`). Ein Strom wäre dort nicht nur
  /// unnötig, sondern lästig: Er hinterlässt beim Abbauen einen
  /// Zeitgeber, und die Liste unter der Hand zu ändern, während jemand
  /// Häkchen setzt, wäre ohnehin das Gegenteil von hilfreich.
  /// Dieselbe Menge wie [alleAufnahmen], aber als schmale Rasterzeilen.
  ///
  /// Der Fotowähler zeigt ein Raster und wandelt jede Zeile ohnehin in
  /// eine [Rasterzeile] um – die 56 Spalten davor waren an dieser
  /// Bibliothek 80 ms, die 20 gebrauchten sind 30.
  Future<List<Rasterzeile>> alleRasterzeilen() async => (await customSelect(
    'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
    'ORDER BY file_created_at DESC',
    readsFrom: {assets},
  ).get()).map(Rasterzeile.ausZeile).toList();

  Future<List<AssetData>> alleAufnahmen() =>
      (select(assets)
            ..where(
              (t) =>
                  t.isTrashed.equals(false) &
                  t.isLocked.equals(false) &
                  _isPrimaryGridEntry(t),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]))
          .get();

  /// Fotos/Videos genau eines Kalenderjahres – im Gegensatz zu
  /// `watchTimeline()` + Dart-seitigem Filtern (früheres Verhalten von
  /// YearDetailScreen) direkt als indexgestützte SQL-Bereichsabfrage, die bei
  /// großen Bibliotheken nicht erst alle anderen Jahre mitladen muss.
  Stream<List<AssetData>> watchTimelineForYear(int year) {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    final abfrage = select(assets)
      ..where(
        (t) =>
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            _isPrimaryGridEntry(t) &
            t.fileCreatedAt.isBiggerOrEqualValue(start) &
            t.fileCreatedAt.isSmallerThanValue(end),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Anzahl Fotos/Videos pro Kalenderjahr für die Jahresübersicht
  /// (CalendarScreen) – eine einzelne aggregierte SQL-Abfrage statt (wie
  /// zuvor) die komplette Zeitleiste zu laden und in Dart pro Jahr zu
  /// zählen. `strftime('%Y', ...)` arbeitet auf demselben, bereits über
  /// `idx_assets_trashed_locked_created` indexierten Filter.
  Stream<Map<int, int>> watchAssetCountsByYear() {
    // 'unixepoch' ist zwingend nötig: drift speichert DateTimeColumn
    // standardmäßig als Unix-Timestamp (Sekunden) statt als ISO8601-Text –
    // ohne den Modifier interpretiert SQLites strftime() die rohe Zahl als
    // Julianisches Datum statt als Unix-Zeit und liefert NULL zurück.
    const yearExpr = CustomExpression<String>(
      "strftime('%Y', file_created_at, 'unixepoch')",
    );
    final query = selectOnly(assets)
      ..addColumns([yearExpr, assets.id.count()])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            _isPrimaryGridEntry(assets),
      )
      ..groupBy([yearExpr]);
    return query.watch().map(
      (rows) => {
        for (final row in rows)
          int.parse(row.read(yearExpr)!): row.read(assets.id.count())!,
      },
    );
  }

  Future<int> _countWhere(Expression<bool> predicate) async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([countExpr])
      ..where(predicate);
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Gebündelte Kennzahlen für die Analyseseite (StatisticsScreen) – bewusst
  /// eine einzelne Momentaufnahme (`Future`, kein `Stream`) statt mehrerer
  /// reaktiver Einzel-Queries: die Seite selbst nutzt Pull-to-Refresh statt
  /// Live-Aktualisierung, da bei einer großen Bibliothek sonst nach jeder
  /// Mutation (z.B. Favorit toggeln) sämtliche Aggregate neu berechnet
  /// würden, obwohl sich für die Analyseseite selbst nichts geändert hat.
  Future<LibraryStats> loadLibraryStats() async {
    // Dieselbe Definition von "sichtbares Medium" wie in watchTimeline() &
    // Co.: nicht im Papierkorb, nicht gesperrt, und beim Live-Photo-Paar nur
    // das Foto zählen (das zugehörige Video wird sonst doppelt gezählt).
    final visible =
        assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        _isPrimaryGridEntry(assets);

    final results = await Future.wait([
      _countWhere(visible & assets.type.equals('IMAGE')),
      _countWhere(visible & assets.type.equals('VIDEO')),
      _countWhere(visible & assets.isFavorite.equals(true)),
      _countWhere(
        assets.isTrashed.equals(true) & assets.isLocked.equals(false),
      ),
      _countWhere(
        assets.isLocked.equals(true) & assets.isTrashed.equals(false),
      ),
      _loadTotalSizeBytes(),
      watchAssetCountsByYear().first,
      _loadCountsByMonth(visible),
      _loadTopCameras(visible),
    ]);

    return LibraryStats(
      imageCount: results[0] as int,
      videoCount: results[1] as int,
      favoriteCount: results[2] as int,
      trashedCount: results[3] as int,
      lockedCount: results[4] as int,
      totalSizeBytes: results[5] as int,
      countsByYear: results[6] as Map<int, int>,
      countsByMonth: results[7] as Map<int, int>,
      topCameras: results[8] as List<CameraStat>,
    );
  }

  /// Tatsächlich belegter Speicherplatz aller nicht gelöschten Dateien –
  /// bewusst OHNE den `visible`-Filter von [loadLibraryStats]: das
  /// zugehörige Video eines Live-Photo-Paares belegt real Speicherplatz auf
  /// der Festplatte, auch wenn es in der UI nicht als eigenes Element
  /// gezählt wird. Gesperrte Assets werden trotzdem ausgeschlossen, damit
  /// die Analyseseite (ohne PIN-Eingabe erreichbar) keine Information über
  /// den Inhalt des gesperrten Ordners preisgibt.
  Future<int> _loadTotalSizeBytes() async {
    final sumExpr = assets.fileSizeBytes.sum();
    final query = selectOnly(assets)
      ..addColumns([sumExpr])
      ..where(assets.isTrashed.equals(false) & assets.isLocked.equals(false));
    final row = await query.getSingle();
    return row.read<int>(sumExpr) ?? 0;
  }

  /// Anzahl Fotos/Videos je Kalendermonat (1-12), über alle Jahre summiert –
  /// zeigt saisonale Muster (z.B. mehr Fotos im Sommer/an Feiertagen).
  Future<Map<int, int>> _loadCountsByMonth(Expression<bool> visible) async {
    const monthExpr = CustomExpression<String>(
      "strftime('%m', file_created_at, 'unixepoch')",
    );
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([monthExpr, countExpr])
      ..where(visible)
      ..groupBy([monthExpr]);
    final rows = await query.get();
    return {
      for (final row in rows)
        int.parse(row.read<String>(monthExpr)!): row.read<int>(countExpr) ?? 0,
    };
  }

  /// Die [limit] häufigsten Kamera-Kombinationen (Hersteller + Modell) für
  /// die Analyseseite – schließt Fotos ganz ohne Kamerainformation
  /// (Screenshots, Scans, ...) bewusst NICHT aus, damit deren Anteil an der
  /// Bibliothek sichtbar wird.
  Future<List<CameraStat>> _loadTopCameras(
    Expression<bool> visible, {
    int limit = 12,
  }) async {
    final countExpr = assets.id.count();
    final query = selectOnly(assets)
      ..addColumns([assets.cameraMake, assets.cameraModel, countExpr])
      ..where(visible)
      ..groupBy([assets.cameraMake, assets.cameraModel])
      ..orderBy([OrderingTerm.desc(countExpr)])
      ..limit(limit);
    final rows = await query.get();
    return [
      for (final row in rows)
        CameraStat(
          make: row.read<String>(assets.cameraMake),
          model: row.read<String>(assets.cameraModel),
          count: row.read<int>(countExpr) ?? 0,
        ),
    ];
  }

  /// Position (0-basiert) eines Assets in der absteigend nach Datum
  /// sortierten Zeitleiste – wie viele andere (nicht Papierkorb/gesperrte)
  /// Assets neuer sind. Für TimelineScreen: bei "Foto in der Timeline
  /// anzeigen" (Kontextmenü der Vollbildansicht) muss das Ladefenster (siehe
  /// `watchTimeline(limit: ...)`) mindestens so weit geöffnet werden, dass
  /// das Zielfoto enthalten ist – auch wenn es weit "unten" in einer sehr
  /// großen Bibliothek liegt. Gibt `null` zurück, wenn das Asset nicht
  /// existiert.
  Future<int?> timelineRankOfAsset(String assetId) async {
    final asset = await assetById(assetId);
    if (asset == null) return null;
    final Expression<int> countExpr = assets.id.count();
    final JoinedSelectStatement<Assets, AssetData> query = selectOnly(assets)
      ..addColumns([countExpr])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            _isPrimaryGridEntry(assets) &
            assets.fileCreatedAt.isBiggerThanValue(asset.fileCreatedAt),
      );
    final row = await query.getSingle();
    return row.read<int>(countExpr) ?? 0;
  }

  /// Anzahl Fotos/Videos je Monat **eines Jahres** – für die
  /// Monatsübersicht.
  ///
  /// Dieselbe Bauart wie [watchAssetCountsByYear], nur mit `%m` statt
  /// `%Y` und einer Bereichsgrenze davor. Die Grenze steht als
  /// gewöhnlicher Vergleich auf `file_created_at` und nicht als
  /// `strftime`-Bedingung: So bleibt der Index nutzbar, während ein
  /// `strftime('%Y', …) = '2026'` ihn verwürfe.
  ///
  /// Der Schlüssel ist die Monatszahl 1..12.
  Stream<Map<int, int>> watchAssetCountsByMonth(int jahr) {
    const monatExpr = CustomExpression<String>(
      "strftime('%m', file_created_at, 'unixepoch')",
    );
    final start = DateTime(jahr);
    final ende = DateTime(jahr + 1);
    final query = selectOnly(assets)
      ..addColumns([monatExpr, assets.id.count()])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            _isPrimaryGridEntry(assets) &
            assets.fileCreatedAt.isBiggerOrEqualValue(start) &
            assets.fileCreatedAt.isSmallerThanValue(ende),
      )
      ..groupBy([monatExpr]);
    return query.watch().map(
      (rows) => {
        for (final row in rows)
          int.parse(row.read(monatExpr)!): row.read(assets.id.count())!,
      },
    );
  }

  /// Alle Aufnahmen eines Monats, neueste zuerst – wie
  /// [watchTimelineForYear], nur enger.
  Stream<List<AssetData>> watchTimelineForMonth(int jahr, int monat) {
    final start = DateTime(jahr, monat);
    final ende = DateTime(jahr, monat + 1);
    final abfrage = select(assets)
      ..where(
        (t) =>
            t.isTrashed.equals(false) &
            t.isLocked.equals(false) &
            _isPrimaryGridEntry(t) &
            t.fileCreatedAt.isBiggerOrEqualValue(start) &
            t.fileCreatedAt.isSmallerThanValue(ende),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Titelbild eines Monats – neuestes Foto/Video darin.
  Future<AssetData?> newestAssetForMonth(int jahr, int monat) {
    final start = DateTime(jahr, monat);
    final ende = DateTime(jahr, monat + 1);
    return (select(assets)
          ..where(
            (t) =>
                t.isTrashed.equals(false) &
                t.isLocked.equals(false) &
                _isPrimaryGridEntry(t) &
                t.fileCreatedAt.isBiggerOrEqualValue(start) &
                t.fileCreatedAt.isSmallerThanValue(ende),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Neuestes Foto/Video eines Jahres als Titelbild für die Jahresübersicht
  /// (CalendarScreen) – dieselbe indexgestützte Bereichsabfrage wie
  /// [watchTimelineForYear], aber auf ein einzelnes Ergebnis begrenzt (pro
  /// Jahr wird dort nur ein Titelbild gebraucht, nicht die volle Liste).
  Future<AssetData?> newestAssetForYear(int year) {
    final start = DateTime(year);
    final end = DateTime(year + 1);
    return (select(assets)
          ..where(
            (t) =>
                t.isTrashed.equals(false) &
                t.isLocked.equals(false) &
                _isPrimaryGridEntry(t) &
                t.fileCreatedAt.isBiggerOrEqualValue(start) &
                t.fileCreatedAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Der normale, ungeschützte Papierkorb – gesperrte (verschlüsselte)
  /// Assets werden hier bewusst ausgeblendet (siehe [watchLockedTrash]):
  /// sonst könnte jeder ohne PIN ein gesperrtes Foto wiederherstellen oder
  /// sogar endgültig löschen, nur weil es zwischenzeitlich im Papierkorb
  /// liegt.
  Stream<List<AssetData>> watchTrash() {
    final abfrage = select(assets)
      ..where((t) => t.isTrashed.equals(true) & t.isLocked.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  /// Wie viel im Papierkorb liegt – **ohne die Aufnahmen selbst zu holen**.
  ///
  /// Zwei Stellen zeigen nur diese Kennzahl an (die Papierkorbzeile im
  /// Erkunden-Bildschirm und die Papierkorb-Einstellung), und beide
  /// zogen dafür bisher jede Zeile des Papierkorbs mitsamt allen 56
  /// Spalten über die Isolate-Grenze. An der gewachsenen Bibliothek
  /// gemessen, 618 Aufnahmen im Papierkorb:
  ///
  /// ```
  /// watchTrash() - volle Zeilen   13,0 ms
  /// diese Zusammenfassung          0,3 ms
  /// ```
  ///
  /// Das zählt, weil der ganze Widgetbaum bei JEDER Meldung des
  /// Bibliothekszustands neu gebaut wird – in der Hintergrundanalyse
  /// zehnmal je Sekunde.
  Stream<Papierkorbumfang> watchPapierkorbUmfang() {
    final anzahl = assets.id.count();
    final bytes = assets.fileSizeBytes.sum();
    Selectable<Papierkorbumfang> bauen() {
      final abfrage = selectOnly(assets)
        ..addColumns([anzahl, bytes])
        ..where(assets.isTrashed.equals(true) & assets.isLocked.equals(false));
      return abfrage.map(
        (zeile) => Papierkorbumfang(
          anzahl: zeile.read(anzahl) ?? 0,
          bytes: zeile.read(bytes) ?? 0,
        ),
      );
    }

    // `_gedrosselt` liefert Listen; eine Zusammenfassung ist immer genau
    // eine Zeile.
    return _gedrosselt(bauen, TableUpdateQuery.onTable(assets)).map(
      (zeilen) => zeilen.isEmpty
          ? const Papierkorbumfang(anzahl: 0, bytes: 0)
          : zeilen.first,
    );
  }

  /// Eigener, PIN-geschützter Papierkorb für aus dem gesperrten Ordner
  /// gelöschte Fotos – nur über den gesperrten Ordner erreichbar (siehe
  /// LockedFolderScreen), damit "gelöscht" bei gesperrten Fotos denselben
  /// Schutz genießt wie "sichtbar".
  Stream<List<AssetData>> watchLockedTrash() {
    final abfrage = select(assets)
      ..where((t) => t.isTrashed.equals(true) & t.isLocked.equals(true))
      ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }

  Future<void> setFavorite(String assetId, bool value) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(isFavorite: Value(value)),
      );

  Future<void> setRating(String assetId, int rating) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(rating: Value(rating)),
      );

  Future<void> setRatingBulk(List<String> assetIds, int rating) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        AssetsCompanion(rating: Value(rating)),
      );

  Future<void> setColorLabel(String assetId, String? colorLabel) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(colorLabel: Value(colorLabel)),
      );

  /// Setzt den Favoriten-Status für mehrere Assets in EINER Anweisung.
  ///
  /// Die Auswahlleiste lief vorher in einer Schleife über die Auswahl – bei
  /// 500 markierten Fotos also 500 einzelne Schreibvorgänge statt einem.
  Future<void> setFavoriteBulk(List<String> assetIds, bool value) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        AssetsCompanion(isFavorite: Value(value)),
      );

  Future<void> setColorLabelBulk(List<String> assetIds, String? colorLabel) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        AssetsCompanion(colorLabel: Value(colorLabel)),
      );
}

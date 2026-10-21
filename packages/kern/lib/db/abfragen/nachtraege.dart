part of '../database.dart';

/// Angaben an Aufnahmen setzen und die Nachträge (Ort, Datum, Kamera, Texterkennung, Beschreibung).
extension NachtragsAbfragen on AppDatabase {
  Future<void> setDescription(String assetId, String description) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(description: Value(description)),
      );

  /// **Schreibt nur die Spalte.** Wer ein Datum auf Wunsch des Menschen
  /// ändert, muss über [LibraryState.setzeAufnahmedatumVonHand] gehen: Das
  /// Datum bestimmt den Ablageort, und die Datei muss mitgehen. Hier
  /// stehenzubleiben hinterliess an der echten Bibliothek 1102 Aufnahmen,
  /// deren Ordner etwas anderes behauptet als ihre Zeile. Ein Prüfstand
  /// hält die Bildschirme davon fern (siehe
  /// `datum_setzen_verschiebt_test.dart`); für Prüfstände selbst ist der
  /// kurze Weg hier richtig.
  Future<void> setFileCreatedAt(String assetId, DateTime fileCreatedAt) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          fileCreatedAt: Value(fileCreatedAt),
          // Wie bei [setAufnahmezeitpunkt]: Ein gesetztes Datum ist kein
          // geratenes mehr.
          datumGeschaetzt: const Value(false),
        ),
      );

  /// Setzt (oder löscht, bei `null`) den Ort eines Assets – entweder aus
  /// EXIF-GPS-Daten beim Import übernommen oder manuell in der Info-Ansicht
  /// der Vollbildvorschau gesetzt/korrigiert.
  ///
  /// **Die ausgeschriebenen Ortsnamen fallen mit.** Sie gehören zur alten
  /// Koordinate; nach einer Korrektur wären sie schlicht falsch. Und weil
  /// [assetsForLocationNameBackfill] nur dort nachträgt, wo noch gar kein
  /// Land steht, blieben sie es für immer: Ein Foto, dessen Ort man von
  /// Afghanistan nach Niedersachsen zieht, hiesse weiterhin „Baghlān,
  /// Afghanistan" – im Infoblatt, in den Ortsgruppen der Übersicht und im
  /// Suchfilter. Genau so hielt sich das Phantomland einer Kamera mit
  /// verrutschtem Empfänger (31 Aufnahmen einer TG-810 von 2013, die
  /// wirklich so in der Datei stehen – mit exiftool gegengelesen).
  ///
  /// Nach dem Leeren trägt der Nachtrag die richtigen Namen ein; ohne
  /// Koordinate bleibt es leer, und das ist die Wahrheit.
  Future<void> setLocation(
    String assetId,
    double? latitude,
    double? longitude,
  ) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      latitude: Value(latitude),
      longitude: Value(longitude),
      locationCountry: const Value(null),
      locationState: const Value(null),
      locationCity: const Value(null),
      // Wer eine Koordinate setzt oder aus der Datei liest, ersetzt
      // eine Vermutung durch etwas Belegtes (siehe [Assets.ortGeerbt]).
      ortGeerbt: const Value(false),
    ),
  );

  /// Gibt dem aus einem Motion Photo gelösten Video Zeit und Ort des
  /// Fotos, zu dem es gehört.
  Future<void> uebernimmFotoangabenFuerBewegtbild(
    String videoId,
    AssetData foto,
  ) => (update(assets)..where((t) => t.id.equals(videoId))).write(
    AssetsCompanion(
      fileCreatedAt: Value(foto.fileCreatedAt),
      datumGeschaetzt: Value(foto.datumGeschaetzt),
      datumGeprueft: const Value(true),
      zeitversatzMinuten: Value(foto.zeitversatzMinuten),
      latitude: Value(foto.latitude),
      longitude: Value(foto.longitude),
      locationCountry: Value(foto.locationCountry),
      locationState: Value(foto.locationState),
      locationCity: Value(foto.locationCity),
      ortGeerbt: Value(foto.ortGeerbt),
      gpsGeprueft: const Value(true),
      cameraMake: Value(foto.cameraMake),
      cameraModel: Value(foto.cameraModel),
    ),
  );

  /// Gibt einem aus [video] gesicherten Standbild, was das Video über
  /// sich weiss: Zeitpunkt ([wann]), Ort, Kamera, Zeitzone – und ob
  /// davon etwas nur geschätzt oder geerbt war.
  ///
  /// Das Standbild selbst trägt nichts davon. Es ist ein frisch kodiertes
  /// JPEG ohne EXIF; der Import gäbe ihm den Augenblick des Sicherns als
  /// Aufnahmezeit und keinen Ort, und es stünde in der Zeitleiste beim
  /// heutigen Tag statt neben seinem Video.
  Future<void> uebernimmVideoangaben(
    String fotoId,
    AssetData video,
    DateTime wann,
  ) => (update(assets)..where((t) => t.id.equals(fotoId))).write(
    AssetsCompanion(
      fileCreatedAt: Value(wann),
      datumGeschaetzt: Value(video.datumGeschaetzt),
      datumGeprueft: const Value(true),
      zeitversatzMinuten: Value(video.zeitversatzMinuten),
      latitude: Value(video.latitude),
      longitude: Value(video.longitude),
      locationCountry: Value(video.locationCountry),
      locationState: Value(video.locationState),
      locationCity: Value(video.locationCity),
      ortGeerbt: Value(video.ortGeerbt),
      gpsGeprueft: const Value(true),
      cameraMake: Value(video.cameraMake),
      cameraModel: Value(video.cameraModel),
    ),
  );

  /// Die Daten, aus denen die Ortsvorschlaege entstehen: die
  /// unverorteten Aufnahmen und die verorteten, je nur mit dem, was die
  /// Rechnung braucht.
  ///
  /// **Zwei schlanke Abfragen statt zweier voller.** Es geht um 5351 und
  /// 2092 Zeilen; `select(assets)` zoege fuer jede alle 57 Spalten
  /// herueber, um daraus drei Zahlen zu lesen.
  ///
  /// Papierkorb und Tresor bleiben draussen: Ein geloeschtes Foto braucht
  /// keinen Ort, und ein gesperrtes soll nicht ueber seine Nachbarn
  /// verraten, wo es entstand.
  Future<({List<Ortsloser> ohneOrt, List<Ortsnachbar> verortet})>
  ortsvorschlagsdaten() async {
    Expression<bool> grund() =>
        assets.isTrashed.equals(false) & assets.isLocked.equals(false);

    final ohne = selectOnly(assets)
      ..addColumns([assets.id, assets.fileCreatedAt])
      ..where(grund() & assets.latitude.isNull());
    final mit = selectOnly(assets)
      ..addColumns([assets.fileCreatedAt, assets.latitude, assets.longitude])
      ..where(grund() & assets.latitude.isNotNull());

    return (
      ohneOrt: [
        for (final z in await ohne.get())
          (
            id: z.read<String>(assets.id)!,
            wann: z.read<DateTime>(assets.fileCreatedAt)!,
          ),
      ],
      verortet: [
        for (final z in await mit.get())
          (
            wann: z.read<DateTime>(assets.fileCreatedAt)!,
            breite: z.read<double>(assets.latitude)!,
            laenge: z.read<double>(assets.longitude)!,
          ),
      ],
    );
  }

  /// Uebernimmt einen Ortsvorschlag fuer eine ganze Gruppe – **in einer
  /// Anweisung je Koordinate**.
  ///
  /// Die ausgeschriebenen Ortsnamen bleiben leer; die traegt der
  /// vorhandene Nachtrag [assetsForLocationNameBackfill] nach, der genau
  /// nach Zeilen mit Koordinate und ohne Land sucht.
  Future<void> uebernimmOrtsvorschlag(
    List<String> assetIds,
    double breite,
    double laenge,
  ) => (update(assets)..where((t) => t.id.isIn(assetIds))).write(
    AssetsCompanion(
      latitude: Value(breite),
      longitude: Value(laenge),
      locationCountry: const Value(null),
      locationState: const Value(null),
      locationCity: const Value(null),
      ortGeerbt: const Value(true),
    ),
  );

  /// Erkannter Text aller offen liegenden Aufnahmen, deren Vorschlag für
  /// den gesperrten Ordner nicht abgelehnt wurde – der Stoff für
  /// `dokumentImText`.
  ///
  /// Nur die beiden Spalten: Der Text wird in Dart geprüft (Prüfziffern
  /// lassen sich in SQL nicht nachrechnen), und ganze Zeilen für jedes
  /// Foto mit Text zu laden hiesse, Tausende Datensätze für eine Handvoll
  /// Treffer zu bauen.
  Future<List<({String id, String text})>> texteFuerDokumentsuche() async {
    final rows = await customSelect(
      '''SELECT id, ocr_text FROM assets
         WHERE is_locked = 0 AND is_trashed = 0
           AND ocr_text IS NOT NULL AND ocr_text <> ''
           AND id NOT IN (SELECT asset_id FROM verworfene_dokumente)''',
      readsFrom: {assets, verworfeneDokumente},
    ).get();
    return [
      for (final r in rows)
        (id: r.read<String>('id'), text: r.read<String>('ocr_text')),
    ];
  }

  Future<void> verwirfDokumentvorschlaege(Iterable<String> ids) => batch((b) {
    final jetzt = DateTime.now();
    for (final id in ids) {
      b.insert(
        verworfeneDokumente,
        VerworfeneDokumenteCompanion.insert(assetId: id, verworfenAm: jetzt),
        mode: InsertMode.insertOrReplace,
      );
    }
  });

  Future<Set<String>> verworfeneOrtsvorschlagsschluessel() async => {
    for (final z in await select(verworfeneOrtsvorschlaege).get()) z.schluessel,
  };

  Future<void> verwirfOrtsvorschlag(String schluessel) =>
      into(verworfeneOrtsvorschlaege).insertOnConflictUpdate(
        VerworfeneOrtsvorschlaegeCompanion.insert(
          schluessel: schluessel,
          verworfenAm: DateTime.now(),
        ),
      );

  /// Fotos ohne bekannten Ort – für das nachträgliche Einlesen von
  /// EXIF-GPS-Daten (Werkzeuge), z.B. für Fotos, die vor Einführung dieser
  /// Funktion importiert wurden. Nur Fotos, da Videos i.d.R. keine
  /// EXIF-GPS-Daten haben (Ort muss dort manuell in der Info-Ansicht
  /// gesetzt werden).
  /// Alles ohne Ort – **Videos eingeschlossen**.
  ///
  /// Der Filter auf `IMAGE` stand hier von Anfang an und schloss damit
  /// genau die Gruppe aus, bei der noch etwas zu holen war: In der
  /// Prüfbibliothek trugen 43 von 60 zufällig geprüften Videos einen Ort
  /// in der Datei und keines von 440 einen in der Datenbank. Bei den
  /// Fotos ist der Topf dagegen leer – von 59 geprüften unverorteten
  /// iPhone- und Canon-Aufnahmen trug keine einzige noch GPS.
  ///
  /// **[alle] = false überspringt, was schon einmal angesehen wurde**
  /// (siehe [Assets.gpsGeprueft]). Ohne das las jeder Lauf dieselben
  /// tausende Dateien vollständig ein, um wieder nichts zu finden:
  /// gemessen 3,3 s und 1215 MB je 400 Fotos, hochgerechnet 47 s und
  /// 17,5 GB. `alle = true` ist der Weg für den Fall, dass jemand die
  /// Dateien ausserhalb der App mit Koordinaten versehen hat.
  Expression<bool> _ohneOrt(bool alle) {
    final grund = assets.isTrashed.equals(false) & assets.latitude.isNull();
    return alle ? grund : grund & assets.gpsGeprueft.equals(false);
  }

  Future<List<AssetData>> assetsForLocationBackfill({bool alle = false}) =>
      (select(assets)..where((_) => _ohneOrt(alle))).get();

  /// Zählvariante von [assetsForLocationBackfill] – für Anzeigezwecke (siehe
  /// BackgroundTasksScreen), ohne die vollen Zeilen aus der DB zu holen.
  Future<int> countLocationBackfill({bool alle = false}) =>
      _countWhere(_ohneOrt(alle));

  /// Wie viele ortlose Aufnahmen einen **verorteten zeitlichen Nachbarn**
  /// haben und deshalb im Ortsvorschlag landen können.
  ///
  /// Nicht dasselbe wie [countLocationBackfill]: Das zählt alles ohne Ort
  /// (an dieser Bibliothek 5143), hiervon sind aber nur 408 überhaupt
  /// erbbar. Eine Zahl, die zehnmal grösser ist als das, was der Bildschirm
  /// dahinter anbietet, wäre keine Auskunft, sondern ein Ärgernis.
  ///
  /// **In einem Durchlauf, nicht als Nachbarschaftssuche je Zeile.** Das
  /// nächstliegende `EXISTS (… abs(differenz) <= fenster)` braucht an
  /// dieser Bibliothek **2,4 s** – für einen Bildschirm, der ohnehin schon
  /// eine halbe Sekunde lädt, das Ende. Über zwei Fensterfunktionen auf
  /// derselben Sortierung – der letzte verortete davor, der nächste
  /// danach – sind es **27 ms** bei identischem Ergebnis.
  ///
  /// [fenster] in Sekunden, und die Vorgabe ist dieselbe wie in
  /// [Ortsvorschlagsregeln]: Was hier gezählt wird, muss das sein, was
  /// dort auch herauskommt.
  Future<int> countOrtsvorschlagskandidaten({
    int fensterSekunden = 2 * 60 * 60,
  }) async {
    final zeile = await customSelect(
      'WITH t AS (SELECT file_created_at AS ts, (latitude IS NOT NULL) AS hat '
      '           FROM assets WHERE is_trashed = 0), '
      '     f AS (SELECT ts, hat, '
      '             max(CASE WHEN hat THEN ts END) OVER (ORDER BY ts '
      '                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) '
      '               AS vorher, '
      '             min(CASE WHEN hat THEN ts END) OVER (ORDER BY ts '
      '                 ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) '
      '               AS nachher '
      '           FROM t) '
      'SELECT count(*) AS n FROM f WHERE hat = 0 '
      '  AND (ts - vorher <= ?1 OR nachher - ts <= ?1)',
      variables: [Variable<int>(fensterSekunden)],
      readsFrom: {assets},
    ).getSingle();
    return zeile.read<int>('n');
  }

  /// Wie viele erkannte Gesichter noch keiner Person gehören.
  ///
  /// Dieselbe Einschränkung wie [unassignedFaces] – beiseitegelegte
  /// Gesichter und solche an gelöschten oder gesperrten Aufnahmen zählen
  /// nicht mit. Eine Zahl, die mehr verspricht als die Liste dahinter
  /// zeigt, ist schlimmer als keine.
  Future<int> countOffeneGesichter() async {
    final n = faces.id.count();
    final zeile =
        await (selectOnly(
                faces,
              ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
              ..addColumns([n])
              ..where(
                faces.personId.isNull() &
                    faces.isIgnored.equals(false) &
                    assets.isTrashed.equals(false) &
                    assets.isLocked.equals(false),
              ))
            .getSingle();
    return zeile.read(n) ?? 0;
  }

  /// Vermerkt für mehrere Aufnahmen auf einmal, dass in ihrer Datei nach
  /// einem Ort gesucht wurde – gleich ob mit Erfolg.
  ///
  /// Blockweise und nicht je Datei: Das Suchen selbst ist der teure Teil,
  /// aber tausende Einzelschreibvorgänge daneben wären es auch (gemessen
  /// bei den Ortsnamen: 2131 ms einzeln gegen 139 ms in Blöcken).
  Future<void> markGpsGeprueft(List<String> assetIds) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(gpsGeprueft: Value(true)),
      );

  /// Aufnahmen, in deren Datei noch nicht nach einem Aufnahmedatum
  /// gesehen wurde (siehe [Assets.datumGeprueft]).
  ///
  /// Der Papierkorb ist dabei: Ein zurückgeholtes Foto soll nicht als
  /// einziges ohne Herkunftsvermerk dastehen.
  Expression<bool> _datumOffen(bool alle) => alle
      ? const CustomExpression<bool>('1')
      : assets.datumGeprueft.equals(false);

  Future<List<AssetData>> assetsFuerDatumsherkunft({bool alle = false}) =>
      (select(assets)..where((_) => _datumOffen(alle))).get();

  /// Zählvariante von [assetsFuerDatumsherkunft], siehe [countLocationBackfill].
  Future<int> countDatumsherkunft({bool alle = false}) =>
      _countWhere(_datumOffen(alle));

  /// Nur die Aufnahmen, bei denen der Lauf voraussichtlich etwas ändert:
  /// solche, deren Zeitstempel auf einer **vollen Stunde** sitzt.
  ///
  /// **Warum genau dieses Merkmal.** Ein echter Auslösezeitpunkt trifft die
  /// volle Stunde mit einer Wahrscheinlichkeit von 1:3600. An der
  /// Produktivbibliothek wären das bei 7443 Aufnahmen rund **2** – gezählt
  /// wurden **1097**, davon **948** auf ein und derselben Sekunde. Das ist
  /// kein Zufall, sondern ein Datum ohne Uhrzeit, das jemand beim Einlesen
  /// auf 00:00 aufgefüllt hat.
  ///
  /// [countDatumsherkunft] zählt dagegen alles, was noch niemand
  /// nachgesehen hat – an derselben Bibliothek 8098. Als Zahl auf dem
  /// Gesundheitsbildschirm verspräche sie Arbeit, die der Lauf gar nicht
  /// leistet, und das ist schlimmer als keine Zahl (siehe
  /// [countOffeneGesichter]).
  ///
  /// **Gerechnet wird in Ortszeit, nicht in UTC.** Die volle Stunde ist
  /// eine Eigenschaft der Uhrzeit, die jemand gesehen hat, als der Wert
  /// entstand. In Zonen mit halbstuendigem Versatz – Indien, Teile
  /// Australiens – laege eine erfundene Mitternacht in UTC bei 1800
  /// Sekunden und bliebe ungezaehlt. Der Sommerzeitsprung stoert dabei
  /// nicht: Er betraegt ueberall volle Stunden und aendert am Rest der
  /// Division nichts.
  /// Der Verdacht als Ausdruck, fuer alle, die ihn ausschliessen wollen –
  /// siehe [countAuffaelligeAufnahmedaten] fuer die Begruendung der
  /// vollen Stunde.
  ///
  /// **Er gilt nur, solange niemand nachgesehen hat.** Der Lauf
  /// „Herkunft der Aufnahmedaten" oeffnet die Datei und setzt
  /// [Assets.datumGeprueft]; was er dabei nicht als geschaetzt markiert,
  /// hat dort ein echtes Datum stehen. An der echten Bibliothek sind das
  /// **149 Aufnahmen auf voller Stunde, die der Lauf bestaetigt hat** –
  /// 148 davon am 27. August. Sie danach weiter auszuschliessen hiesse,
  /// eine Vermutung ueber einen Beleg zu stellen.
  Expression<bool> _nichtAufVollerStunde() => CustomExpression<bool>(
    '(datum_geprueft = 1 OR (file_created_at + '
    '${DateTime.now().timeZoneOffset.inSeconds}) % 3600 <> 0)',
  );

  Future<int> countAuffaelligeAufnahmedaten() => _countWhere(
    _datumOffen(false) &
        assets.fileCreatedAt.isNotNull() &
        // file_created_at liegt als Sekunden seit 1970 vor, nicht als
        // Text und nicht in Millisekunden – der Rest der Division ist
        // deshalb direkt zu haben.
        CustomExpression<bool>(
          '(file_created_at + '
          '${DateTime.now().timeZoneOffset.inSeconds}) % 3600 = 0',
        ),
  );

  /// Vermerkt „nachgesehen" für eine ganze Gruppe – und setzt bei denen
  /// aus [geschaetzt] zugleich die Marke.
  ///
  /// **Zwei Anweisungen und nicht zweitausend.** Der Nachtrag geht über
  /// die ganze Bibliothek; je Aufnahme ein eigenes UPDATE wäre derselbe
  /// Fehler, der bei den Ortsnamen 163 ms gegen 2 ms kostete. Und ein
  /// Abbruch mittendrin lässt hier keinen halben Zustand zurück: Beide
  /// Anweisungen betreffen denselben Block.
  ///
  /// Die Marke wird auch **zurückgenommen**: Wer den Lauf mit „alle"
  /// wiederholt, nachdem er die Kameradaten ausserhalb der App
  /// nachgetragen hat, soll die Marke wieder los sein.
  Future<void> markDatumGeprueft(
    List<String> assetIds, {
    required List<String> geschaetzt,
    Map<String, int> versatz = const {},
  }) async {
    if (assetIds.isEmpty) return;
    final geraten = geschaetzt.toSet();
    await transaction(() async {
      await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        const AssetsCompanion(
          datumGeprueft: Value(true),
          datumGeschaetzt: Value(false),
          // Auch der Versatz wird zurueckgenommen: Wer den Lauf mit
          // „alle" wiederholt, soll eine Angabe loswerden, die in der
          // Datei nicht mehr steht.
          zeitversatzMinuten: Value(null),
        ),
      );
      if (geraten.isNotEmpty) {
        await (update(assets)..where((t) => t.id.isIn(geraten.toList()))).write(
          const AssetsCompanion(datumGeschaetzt: Value(true)),
        );
      }
      // Nach Wert gebuendelt: Eine Anweisung je vorkommender Zone statt
      // einer je Aufnahme. In der echten Bibliothek kommen zwei vor.
      final nachWert = <int, List<String>>{};
      for (final e in versatz.entries) {
        nachWert.putIfAbsent(e.value, () => []).add(e.key);
      }
      for (final e in nachWert.entries) {
        await (update(assets)..where((t) => t.id.isIn(e.value))).write(
          AssetsCompanion(zeitversatzMinuten: Value(e.key)),
        );
      }
    });
  }

  /// Setzt die Kamera-/Objektiv-/Aufnahme-Angaben eines Assets (siehe
  /// CameraInfo) – beim Import automatisch oder nachträglich über das
  /// Werkzeug "Kameradaten einlesen".
  Future<void> setCameraMetadata(String assetId, CameraInfo info) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          cameraMake: Value(info.make),
          cameraModel: Value(info.model),
          lensModel: Value(info.lensModel),
          focalLengthMm: Value(info.focalLengthMm),
          fNumber: Value(info.fNumber),
          iso: Value(info.iso),
          exposureTimeSeconds: Value(info.exposureTimeSeconds),
          exposureBiasEv: Value(info.exposureBiasEv),
          focalLength35mm: Value(info.focalLength35mm),
        ),
      );

  /// Fotos ohne bekannte Kamera-Angaben – für das nachträgliche Einlesen in
  /// den Werkzeugen (Fotos, die vor Einführung dieser Funktion importiert
  /// wurden). Prüft nur Hersteller+Modell als "schon verarbeitet"-Signal;
  /// Fotos, deren EXIF-Daten tatsächlich keine Kamera-Angaben enthalten
  /// (z.B. Screenshots), werden dadurch bei jedem Lauf erneut geprüft – wie
  /// bei [assetsForLocationBackfill] bewusst in Kauf genommen, da das
  /// erneute Prüfen sehr günstig ist.
  /// **Videos gehören dazu.** Bis Fassung 2.5 stand hier `type = 'IMAGE'`,
  /// und damit blieben 275 Videos aussen vor, die Hersteller und Gerät in
  /// der Datei tragen – 228 davon in Apples Schlüsselliste, weitere acht
  /// in den klassischen Atomen `©mak`/`©mod` (siehe [kameraAusMoov]).
  /// Der Lauf las stattdessen 842 Fotos, von denen nachweislich **keines**
  /// eine Kameraangabe in der Datei hat, und änderte nichts.
  Expression<bool> get _ohneKameraangabe =>
      assets.isTrashed.equals(false) &
      assets.cameraMake.isNull() &
      assets.cameraModel.isNull();

  Future<List<AssetData>> assetsForCameraMetadataBackfill() =>
      (select(assets)..where((_) => _ohneKameraangabe)).get();

  /// Zählvariante von [assetsForCameraMetadataBackfill], siehe [countLocationBackfill].
  Future<int> countCameraMetadataBackfill({DateTime? importiertNach}) =>
      _countWhere(_ohneKameraangabe & _importiertNach(importiertNach));

  /// Setzt Aufnahmezeitpunkt und – falls der Monat wechselt – den neuen
  /// Ablageort einer Datei.
  ///
  /// Beides zusammen, weil beides zusammengehört: Der Ordner unter
  /// `originals/` wird aus dem Aufnahmedatum gebildet. Ein neues Datum
  /// ohne neuen Pfad hiesse, dass die Ablage auf der Platte nicht mehr zu
  /// dem passt, was die App anzeigt.
  /// Setzt den Aufnahmezeitpunkt – und nimmt dabei die Marke
  /// „geschätzt" zurück (siehe [Assets.datumGeschaetzt]).
  ///
  /// Wer ein Datum von Hand einträgt, weiss mehr als die Datei. Bliebe
  /// die Marke stehen, hinge sie ausgerechnet an dem Wert, der von allen
  /// der belegteste ist – und das Foto fiele weiter aus Erinnerungen und
  /// Serien heraus, obwohl der Grund dafür gerade behoben wurde.
  Future<void> setAufnahmezeitpunkt(
    String assetId,
    DateTime zeitpunkt, {
    String? neuerPfad,
  }) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      fileCreatedAt: Value(zeitpunkt),
      datumGeschaetzt: const Value(false),
      relativePath: neuerPfad == null ? const Value.absent() : Value(neuerPfad),
    ),
  );

  /// Was die Prüfung „Aufnahmedaten“ (#203, `datumsvorschlaege`) über jede
  /// Aufnahme braucht – sechs Spalten statt der ganzen Zeile mit Texten
  /// und Beschreibungen. Ohne Papierkorb und gesperrten Ordner: Die
  /// tauchen nirgends auf, wo ein Datum stört. [nur] beschränkt auf eine
  /// Aufnahme (die Info-Ansicht).
  Future<
    List<
      ({
        String id,
        String name,
        DateTime zeitpunkt,
        bool geschaetzt,
        bool geprueft,
        String pfad,
      })
    >
  >
  aufnahmenFuerNamensdatum({String? nur}) async {
    final q = selectOnly(assets)
      ..addColumns([
        assets.id,
        assets.originalFileName,
        assets.fileCreatedAt,
        assets.datumGeschaetzt,
        assets.datumGeprueft,
        assets.relativePath,
      ])
      ..where(
        assets.isTrashed.equals(false) &
            assets.isLocked.equals(false) &
            (nur == null ? const Constant(true) : assets.id.equals(nur)),
      );
    return [
      for (final z in await q.get())
        (
          id: z.read(assets.id)!,
          name: z.read(assets.originalFileName)!,
          zeitpunkt: z.read(assets.fileCreatedAt)!,
          geschaetzt: z.read(assets.datumGeschaetzt)!,
          geprueft: z.read(assets.datumGeprueft)!,
          pfad: z.read(assets.relativePath)!,
        ),
    ];
  }

  /// Setzt die Aufnahmedaten aus der Prüfung (#203, Befehl
  /// [AufnahmedatenSetzen]) und vermerkt sie als nachgesehen.
  ///
  /// **Nur die Zeilen, nicht die Ablage.** Der Ordner unter `originals/`
  /// folgt dem Datum, aber verbundene Geräte holen ihre Dateien über eben
  /// diesen Pfad und halten sie darunter vor: Ein Umzug auf dem Server
  /// hiesse, dass jedes Gerät jedes Original noch einmal lädt und die
  /// alte Kopie liegen lässt. Wie beim geschätzten Jahr
  /// ([setzeGeschaetztesJahr]) bleibt die Datei deshalb, wo sie ist; ohne
  /// Server zieht [LibraryState] sie selbst nach.
  Future<void> setzeAufnahmedaten(
    List<({String id, DateTime zeitpunkt, bool geschaetzt})> daten,
  ) => transaction(() async {
    for (final d in daten) {
      await (update(assets)..where((t) => t.id.equals(d.id))).write(
        AssetsCompanion(
          fileCreatedAt: Value(d.zeitpunkt),
          datumGeschaetzt: Value(d.geschaetzt),
          datumGeprueft: const Value(true),
        ),
      );
    }
  });

  /// RAW-Fotos, deren Aufnahmedatum aus dem Dateizeitstempel stammen
  /// könnte – Kandidaten für die Datumskorrektur.
  ///
  /// Warum RAW **und Video**: `package:exif` liest nur TIFF/JPEG. Formate
  /// wie CR3 und die Videocontainer MOV/MP4 liefern dort NULL Tags, und
  /// dann fällt der Import auf `lastModified()` der Quelldatei zurück –
  /// also auf den Zeitpunkt des letzten Kopierens.
  ///
  /// **Die Videos fehlten hier bis Fassung 2.5.** Der Kommentar an dieser
  /// Stelle begründete das damit, dass es den Rückfall nur bei RAW gebe.
  /// An der echten Bibliothek nachgezählt war das falsch: 309 von 440
  /// Videos tragen einen Aufnahmezeitpunkt in der Datei, **kein einziges**
  /// trug den richtigen in der Datenbank, und 196 lagen um mehr als einen
  /// Tag daneben. Der Leser dafür steht in [zeitAusMoov]; diese Abfrage
  /// war das, was ihn nie zu Gesicht bekam.
  ///
  /// Gewöhnliche JPEG bleiben aussen vor: Dort kam das Datum immer aus den
  /// EXIF-Daten oder es gab überhaupt keines in der Datei (nachgezählt:
  /// 1774 Aufnahmen ohne jede Zeitangabe, die auch ein erneutes Lesen
  /// nicht datieren könnte).
  ///
  /// Bewusst ohne weitere Einschränkung: Ob ein Datum wirklich falsch ist,
  /// weiss erst der Vergleich mit der Datei. Diese Abfrage grenzt nur die
  /// Menge ein, die überhaupt betroffen sein kann.
  /// RAW-Aufnahmen, deren Aufnahmedatum nachgelesen werden soll.
  ///
  /// **Die RAW-Bedingung steht hier und nicht mehr im Aufrufer.** Vorher
  /// lud diese Abfrage ALLE Bilder – bei 7.988 Aufnahmen also achttausend
  /// Zeilen –, und `korrigiereAufnahmedaten` warf davon in Dart alles weg,
  /// was keine RAW-Endung hatte. Nebenbei liess sich die Zahl damit nicht
  /// anzeigen, ohne dieselbe Arbeit ein zweites Mal zu tun. Jetzt
  /// entscheidet SQL, [countDatumskorrektur] fragt dasselbe, und beide
  /// können nicht auseinanderlaufen.
  ///
  /// Über die Endung des Ablagepfades und **nicht** über die Spalte
  /// `dateiformat`: Die ist erst seit Fassung 47 da und darf leer sein –
  /// eine Datei, die ohne Endung hereinkam, hat dort nichts stehen. Mit
  /// `dateiformat` fielen solche Zeilen stillschweigend heraus, und der
  /// Prüfstand hat genau das gefangen. Der Ablagepfad dagegen trägt die
  /// kleingeschriebene Endung der Quelldatei, immer.
  ///
  /// Fünfundzwanzig `LIKE` über die ganze Tabelle sind kein Vergnügen,
  /// aber es ist eine Abfrage statt achttausend Zeilen durch den
  /// Dart-Speicher.
  Expression<bool> get _rohaufnahme {
    Expression<bool>? endungen;
    for (final e in rawImageExtensions) {
      final eine = assets.relativePath.lower().like('%$e');
      endungen = endungen == null ? eine : endungen | eine;
    }
    return assets.isTrashed.equals(false) &
        (assets.type.equals('VIDEO') |
            (assets.type.equals('IMAGE') & endungen!));
  }

  /// Aufnahmen, deren **Ablageordner nicht zu ihrem Datum passt**.
  ///
  /// Der Ablagepfad ist `originals/JJJJ/MM/<Kennung><Endung>` (siehe
  /// [StoragePaths.originalRelativePath]). Wer das Datum von Hand setzte,
  /// bekam bis Fassung 2.6 nur die Spalte geändert – die Datei blieb im
  /// Ordner des alten Monats. An einer echten Bibliothek betraf das
  /// **1102 von 7988 Aufnahmen**, davon 948 aus einer einzigen
  /// Sammelbearbeitung.
  ///
  /// Die Ursache ist behoben (siehe
  /// [LibraryState.setzeAufnahmedatumVonHand]); das hier räumt auf, was
  /// vorher entstanden ist.
  ///
  /// **In SQL und nicht in Dart**, obwohl der Pfad in Dart gebaut wird:
  /// Sonst kämen achttausend Zeilen herüber, damit von jeder zwei Zahlen
  /// verglichen werden. `substr(…, 11, 7)` schneidet die sieben Zeichen
  /// `JJJJ/MM` hinter `originals/` heraus.
  ///
  /// `'localtime'` ist zwingend: `originalRelativePath` nimmt Jahr und
  /// Monat der **Ortszeit**. Ohne den Modifier läge jede Aufnahme aus der
  /// ersten Stunde eines Monats scheinbar falsch.
  ///
  /// **Vor 1970 entscheidet Dart** ([_ablageVor1970], [_ablageStimmt]).
  /// Dort setzt SQLite ein Ersatzjahr ohne die damalige Sommerzeit ein
  /// (gemessen, siehe `_jahrAusdruck` in aufnahmen.dart), und das war
  /// nicht harmlos: Ein auf Neujahr 1941 datiertes Foto lag richtig unter
  /// `1941/01`, SQLite sah `1940/12`. Der Lauf berechnete denselben Pfad
  /// und verschob nichts – die Aufgabe blieb für immer offen. Umgekehrt
  /// blieb ein Foto vom 30. Juni 1955, 23:30, unter `1955/07` unentdeckt
  /// liegen.
  ///
  /// **Der Papierkorb ist dabei**, anders als bei der Datumskorrektur: Ein
  /// gelöschtes Foto liegt weiterhin unter `originals/`, und die Frage
  /// lautet hier nicht „stimmt das Datum", sondern „stimmt der Ordner".
  Expression<bool> get _ablageFalsch => const CustomExpression<bool>(
    'file_created_at >= 0 AND '
    "replace(relative_path, char(92), '/') LIKE 'originals/%' AND "
    "substr(replace(relative_path, char(92), '/'), 11, 7) "
    "<> strftime('%Y/%m', file_created_at, 'unixepoch', 'localtime')",
  );

  /// Die Aufnahmen vor 1970 unter `originals/` – ob ihr Ordner stimmt,
  /// sagt erst [_ablageStimmt]. Alte Aufnahmen sind wenige.
  Expression<bool> get _ablageVor1970 => const CustomExpression<bool>(
    'file_created_at < 0 AND '
    "replace(relative_path, char(92), '/') LIKE 'originals/%'",
  );

  /// Ob [relativPfad] im Monatsordner von [aufgenommen] liegt – dieselbe
  /// Rechnung wie [StoragePaths.originalRelativePath] und derselbe
  /// Vergleich wie [_ablageFalsch]: die sieben Zeichen `JJJJ/MM` hinter
  /// `originals/`.
  static bool _ablageStimmt(String relativPfad, DateTime aufgenommen) {
    final pfad = relativPfad.replaceAll(r'\', '/');
    final ortszeit = aufgenommen.toLocal();
    final ordner =
        '${ortszeit.year.toString().padLeft(4, '0')}/'
        '${ortszeit.month.toString().padLeft(2, '0')}';
    return pfad.length >= 17 && pfad.substring(10, 17) == ordner;
  }

  Future<List<AssetData>> assetsFuerAblageordnung() async => [
    ...await (select(assets)..where((_) => _ablageFalsch)).get(),
    for (final a in await (select(assets)..where((_) => _ablageVor1970)).get())
      if (!_ablageStimmt(a.relativePath, a.fileCreatedAt)) a,
  ];

  /// Zählvariante von [assetsFuerAblageordnung], siehe [countLocationBackfill].
  /// Für die Aufnahmen vor 1970 kommen nur Pfad und Datum herüber.
  Future<int> countAblageordnung() async {
    final vor1970 = selectOnly(assets)
      ..addColumns([assets.relativePath, assets.fileCreatedAt])
      ..where(_ablageVor1970);
    final alte = await vor1970.get();
    return await _countWhere(_ablageFalsch) +
        alte
            .where(
              (z) => !_ablageStimmt(
                z.read(assets.relativePath)!,
                z.read(assets.fileCreatedAt)!,
              ),
            )
            .length;
  }

  Future<List<AssetData>> assetsFuerDatumskorrektur() =>
      (select(assets)..where((_) => _rohaufnahme)).get();

  /// Zählvariante von [assetsFuerDatumskorrektur], siehe [countLocationBackfill].
  Future<int> countDatumskorrektur({DateTime? importiertNach}) =>
      _countWhere(_rohaufnahme & _importiertNach(importiertNach));

  /// Setzt das Ergebnis der Texterkennung (siehe ImageConverter.swift
  /// `recognizeText`) – [text] darf leer sein (kein Text im Bild gefunden),
  /// `ocrScanned` unterscheidet das von "noch nicht gescannt".
  Future<void> setOcrResult(String assetId, String text, {String? boxen}) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(
          ocrText: Value(text),
          ocrBoxen: Value(boxen),
          ocrScanned: const Value(true),
        ),
      );

  /// Bild-Assets ohne Texterkennung – für den nachträglichen Lauf in den
  /// Werkzeugen (Fotos, die vor Einführung dieser Funktion importiert wurden).
  ///
  /// Ohne gesperrte Fotos, aus demselben Grund wie bei [assetsForAiTagging]:
  /// Erkannter Text ist Bildinhalt und hätte in der unverschlüsselten
  /// Datenbank nichts zu suchen. Bisher fehlte dieser Filter (Audit-Fund) –
  /// folgenlos nur deshalb, weil die mitverschlüsselte Vorschau ohnehin
  /// nicht dekodierbar ist; verlassen sollte sich darauf niemand.
  /// [alle] liest auch bereits durchsuchte Aufnahmen erneut. Das wird nur
  /// nach einem Modellwechsel angeboten; sonst bleibt der reguläre Lauf
  /// inkrementell und spart unnötige lokale Inferenz.
  Future<List<AssetData>> assetsForOcrBackfill({bool alle = false}) =>
      (select(assets)..where(
            (t) => alle
                ? _auswertbar(t) &
                      t.isTrashed.equals(false) &
                      t.isLocked.equals(false)
                : _ocrOffen(t),
          ))
          .get();

  /// Zählvariante von [assetsForOcrBackfill], siehe [countLocationBackfill].
  Future<int> countOcrBackfill() => _countWhere(_ocrOffen(assets));

  /// Auf wie vielen Aufnahmen überhaupt Text erkannt worden ist.
  ///
  /// Für die Suche im erkannten Text: Steht hier eine Null, dann liegt es
  /// nicht an der Suchanfrage, dass nichts kommt – dann ist die
  /// Texterkennung schlicht noch nie gelaufen. "Keine Treffer" wäre
  /// dafür die falsche Auskunft.
  Future<int> zaehleMitErkanntemText() =>
      _countWhere(assets.ocrText.isNotNull() & assets.ocrText.equals('').not());

  /// Was die Texterkennung noch vor sich hat.
  ///
  /// Zwei Fälle, nicht einer. Der erste ist der alte: nie gescannt. Der
  /// zweite kam mit Schema 60 dazu – gescannt, Text gefunden, aber ohne die
  /// Stellen im Bild. Ohne diesen zweiten Fall blieben die 2406 bereits
  /// erkannten Texte für immer ohne Kästchen, denn `ocrScanned` steht bei
  /// ihnen längst auf wahr und nichts holte sie je wieder hervor.
  ///
  /// Fotos, in denen nachweislich kein Text steht (`ocrText` leer), bleiben
  /// aussen vor: Bei ihnen gäbe es auch beim zweiten Lauf keine Stellen, und
  /// es wären über fünftausend vergebliche Durchläufe.
  /// Was sich aus dem Bildinhalt auswerten lässt.
  ///
  /// Jedes Bild – **und jedes Video, von dem ein Standbild vorliegt**. Der
  /// Filter `type = 'IMAGE'` stand in dreiundzwanzig Abfragen und liess
  /// damit die 440 Videos der Prüfbibliothek aus jeder Stufe heraus: null
  /// Beschreibungen, null Schlagwörter, null Gesichter, null Einbettungen,
  /// null erkannte Texte. Immich wertet bei Videos genau dieses eine
  /// Standbild aus und schreibt die Einschränkung in seine Doku; hier lag
  /// das Bild seit dem Import auf der Platte und niemand sah es an.
  ///
  /// Die Vorschau ist zugleich die Bedingung und der Weg dorthin: Sie ist
  /// das, was `LibraryState._decodableFile` liefert. Ein Video ohne
  /// Standbild (die Extraktion scheitert an beschädigten Dateien) bleibt
  /// deshalb aussen vor, statt jede Stufe einzeln scheitern zu lassen.
  Expression<bool> _auswertbar($AssetsTable t) =>
      t.type.equals('IMAGE') |
      (t.type.equals('VIDEO') & t.previewRelativePath.isNotNull());

  Expression<bool> _ocrOffen($AssetsTable t) =>
      _auswertbar(t) &
      t.isTrashed.equals(false) &
      t.isLocked.equals(false) &
      (t.ocrScanned.equals(false) |
          (t.ocrText.isNotNull() &
              t.ocrText.equals('').not() &
              t.ocrBoxen.isNull()));

  /// Setzt das Ergebnis der KI-Bildbeschreibung (siehe FlorenceCaptioningService) –
  /// analog zu [setOcrResult].
  ///
  /// [deutsch] ist die übersetzte Fassung, sofern das Übersetzungsmodell
  /// installiert und eingeschaltet ist. Das englische Original bleibt in
  /// jedem Fall stehen.
  Future<void> setAiCaption(
    String assetId,
    String caption, {
    String? deutsch,
  }) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      aiCaption: Value(caption),
      aiCaptionDe: Value(deutsch),
      aiCaptionScanned: const Value(true),
    ),
  );

  Future<bool> uebersetzeBeschreibungen() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.translateCaptions ?? false;
  }

  Future<bool> uebersetzeSucheUndTags() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.translateSearchAndTags ?? false;
  }

  Future<void> setzeUebersetzeBeschreibungen(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          translateCaptions: Value(an),
        ),
      );
}

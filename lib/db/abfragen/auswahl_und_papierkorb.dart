part of '../database.dart';

/// Was die Auswahlleiste auf einmal ändert, Papierkorb und Ausnahmen der Duplikatsuche.
extension AuswahlAbfragen on AppDatabase {
  // ---- Rückgängig für die Auswahlleiste -------------------------------
  //
  // Jede Stapelaktion merkt sich vorher, was sie ändert, und stellt es auf
  // Wunsch wieder her (siehe widgets/stapel_rueckgaengig.dart). Gemerkt
  // wird je Foto, nicht ein gemeinsamer Wert: Von 200 markierten Fotos
  // hatten vorher vielleicht 30 schon fünf Sterne.

  /// Favorit, Bewertung und Farbe je Foto, wie sie jetzt sind.
  Future<Map<String, ({bool favorit, int bewertung, String? farbe})>>
  markierungen(List<String> assetIds) async => {
    for (final a in await (select(
      assets,
    )..where((t) => t.id.isIn(assetIds))).get())
      a.id: (favorit: a.isFavorite, bewertung: a.rating, farbe: a.colorLabel),
  };

  /// Stellt [vorher] wieder her – gruppiert nach Wert, also so viele
  /// Schreibvorgänge, wie es verschiedene Werte gab, nicht je Foto einen.
  Future<void> setzeMarkierungen(
    Map<String, ({bool favorit, int bewertung, String? farbe})> vorher,
  ) => transaction(() async {
    final nach =
        <({bool favorit, int bewertung, String? farbe}), List<String>>{};
    for (final MapEntry(key: id, value: m) in vorher.entries) {
      (nach[m] ??= []).add(id);
    }
    for (final MapEntry(key: m, value: ids) in nach.entries) {
      await (update(assets)..where((t) => t.id.isIn(ids))).write(
        AssetsCompanion(
          isFavorite: Value(m.favorit),
          rating: Value(m.bewertung),
          colorLabel: Value(m.farbe),
        ),
      );
    }
  });

  /// Welche von [assetIds] das Schlagwort [tagName] schon tragen.
  Future<Set<String>> tragenSchlagwort(
    List<String> assetIds,
    String tagName,
  ) async {
    final tag = await (select(
      tags,
    )..where((t) => t.name.equals(tagName))).getSingleOrNull();
    if (tag == null) return const {};
    return {
      for (final z in await (select(
        assetTags,
      )..where((t) => t.tagId.equals(tag.id) & t.assetId.isIn(assetIds))).get())
        z.assetId,
    };
  }

  /// Nimmt das Schlagwort [tagName] von [assetIds] wieder ab. Hängt es
  /// danach an keinem Foto mehr, verschwindet es ganz – es war erst eben
  /// angelegt worden.
  Future<void> nimmSchlagwortAb(List<String> assetIds, String tagName) =>
      transaction(() async {
        final tag = await (select(
          tags,
        )..where((t) => t.name.equals(tagName))).getSingleOrNull();
        if (tag == null) return;
        await (delete(assetTags)
              ..where((t) => t.tagId.equals(tag.id) & t.assetId.isIn(assetIds)))
            .go();
        final rest =
            await (select(assetTags)
                  ..where((t) => t.tagId.equals(tag.id))
                  ..limit(1))
                .get();
        if (rest.isEmpty) {
          await (delete(tags)..where((t) => t.id.equals(tag.id))).go();
        }
      });

  /// Welche von [assetIds] schon im Album [albumId] liegen.
  Future<Set<String>> imAlbum(String albumId, List<String> assetIds) async => {
    for (final z
        in await (select(albumAssets)..where(
              (t) => t.albumId.equals(albumId) & t.assetId.isIn(assetIds),
            ))
            .get())
      z.assetId,
  };

  /// Nimmt [assetIds] aus dem Album [albumId]; mit [albumLoeschen] auch das
  /// Album selbst – wenn es erst für diese Aktion angelegt wurde.
  Future<void> nimmAusAlbum(
    String albumId,
    List<String> assetIds, {
    bool albumLoeschen = false,
  }) => transaction(() async {
    await (delete(
      albumAssets,
    )..where((t) => t.albumId.equals(albumId) & t.assetId.isIn(assetIds))).go();
    if (albumLoeschen) {
      await (delete(albumAssets)..where((t) => t.albumId.equals(albumId))).go();
      await (delete(albums)..where((t) => t.id.equals(albumId))).go();
    }
  });

  /// Setzt dieselbe Beschreibung für mehrere Assets auf einmal (Auswahlleiste
  /// "Metadaten bearbeiten") – überschreibt, statt anzuhängen.
  Future<void> setDescriptionBulk(List<String> assetIds, String description) =>
      (update(assets)..where((t) => t.id.isIn(assetIds))).write(
        AssetsCompanion(description: Value(description)),
      );

  /// Setzt denselben Zeitpunkt für mehrere Assets auf einmal – bewusst kein
  /// relatives Verschieben (jedes Foto würde sonst seinen ursprünglichen
  /// Abstand zu den anderen behalten müssen), sondern ein einfaches
  /// "alle auf diesen einen Zeitpunkt setzen" für die Auswahlleiste.
  /// **Schreibt nur die Spalte.** Wer ein Datum auf Wunsch des Menschen
  /// ändert, muss über [LibraryState.setzeAufnahmedatumVonHand] gehen: Das
  /// Datum bestimmt den Ablageort, und die Datei muss mitgehen. Hier
  /// stehenzubleiben hinterliess an der echten Bibliothek 1102 Aufnahmen,
  /// deren Ordner etwas anderes behauptet als ihre Zeile. Ein Prüfstand
  /// hält die Bildschirme davon fern (siehe
  /// `datum_setzen_verschiebt_test.dart`); für Prüfstände selbst ist der
  /// kurze Weg hier richtig.
  Future<void> setFileCreatedAtBulk(
    List<String> assetIds,
    DateTime fileCreatedAt,
  ) => (update(assets)..where((t) => t.id.isIn(assetIds))).write(
    AssetsCompanion(
      fileCreatedAt: Value(fileCreatedAt),
      // Wie bei [setAufnahmezeitpunkt]: Ein gesetztes Datum ist kein
      // geratenes mehr.
      datumGeschaetzt: const Value(false),
    ),
  );

  /// Siehe [setLocation] – auch hier fallen die alten Ortsnamen mit.
  /// Setzt Land, Region und Ort für viele Aufnahmen auf **denselben**
  /// Wert – in einer einzigen Anweisung.
  ///
  /// **Warum nicht in einer Schleife.** Genau das stand vorher in
  /// [LibraryState.setzeOrtVonHand]: je Aufnahme ein eigenes UPDATE, und
  /// jedes ist für SQLite eine eigene Übertragung samt Sichern auf die
  /// Platte. An einer Datei gemessen
  /// (`tool/messe_sammelaenderung_test.dart`), 500 Aufnahmen:
  ///
  /// ```
  /// je Aufnahme ein UPDATE   163 ms
  /// eine Klammer darum         24 ms
  /// eine einzige Anweisung      2 ms
  /// ```
  ///
  /// Und der wichtigere Grund ist gar nicht die Zeit: Eine Schleife
  /// hinterlässt, wenn sie in der Mitte scheitert, die eine Hälfte der
  /// Fotos am neuen Ort und die andere am alten. Eine Anweisung tut das
  /// nicht.
  Future<void> setLocationNamesBulk(
    List<String> assetIds, {
    String? country,
    String? state,
    required String city,
  }) => (update(assets)..where((t) => t.id.isIn(assetIds))).write(
    AssetsCompanion(
      locationCountry: Value(country),
      locationState: Value(state),
      locationCity: Value(city),
    ),
  );

  Future<void> setLocationBulk(
    List<String> assetIds,
    double? latitude,
    double? longitude,
  ) => (update(assets)..where((t) => t.id.isIn(assetIds))).write(
    AssetsCompanion(
      latitude: Value(latitude),
      longitude: Value(longitude),
      locationCountry: const Value(null),
      locationState: const Value(null),
      locationCity: const Value(null),
    ),
  );

  Future<void> moveToTrash(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
      AssetsCompanion(
        isTrashed: const Value(true),
        trashedAt: Value(DateTime.now()),
      ),
    );
    _embeddingsGeneration++;
  }

  /// Führt die Metadaten ähnlicher Aufnahmen auf [behaltenId] zusammen und
  /// verschiebt die übrigen Dateien anschließend in den Papierkorb.
  ///
  /// Der Pixelinhalt wird nie verändert. Tags und Albumzuordnungen werden
  /// vereinigt; Favorit und höchste Sterne bleiben erhalten. Bei gleicher
  /// Beschreibung würde ein Anhängen nur Dubletten erzeugen, bei
  /// unterschiedlichen entscheidet [beschreibungenVerbinden], ob beide
  /// lesbar bleiben sollen. Die ganze Operation ist eine Transaktion, damit
  /// nie eine halbe Metadatenübernahme neben noch sichtbaren Kopien steht.
  Future<void> fuehreDuplikateZusammen({
    required String behaltenId,
    required List<String> duplikatIds,
    bool beschreibungenVerbinden = true,
  }) => transaction(() async {
    final ids = duplikatIds.where((id) => id != behaltenId).toSet().toList();
    if (ids.isEmpty) {
      return;
    }
    final behalten = await assetById(behaltenId);
    if (behalten == null) {
      throw ArgumentError.value(behaltenId, 'behaltenId');
    }
    final kopien = await (select(assets)..where((t) => t.id.isIn(ids))).get();
    if (kopien.isEmpty) {
      return;
    }

    var favorit = behalten.isFavorite;
    var bewertung = behalten.rating;
    var farbe = behalten.colorLabel;
    final beschreibungen = <String>{
      if (behalten.description?.trim().isNotEmpty == true)
        behalten.description!.trim(),
    };
    for (final kopie in kopien) {
      favorit = favorit || kopie.isFavorite;
      if (kopie.rating > bewertung) bewertung = kopie.rating;
      farbe ??= kopie.colorLabel;
      if (kopie.description?.trim().isNotEmpty == true) {
        beschreibungen.add(kopie.description!.trim());
      }
    }

    for (final id in ids) {
      final tagsDerKopie = await (select(
        assetTags,
      )..where((t) => t.assetId.equals(id))).get();
      final albenDerKopie = await (select(
        albumAssets,
      )..where((t) => t.assetId.equals(id))).get();
      for (final tag in tagsDerKopie) {
        if (tag.quelle == Tagquelle.hand) {
          // Hand schlägt KI – dieselbe Regel wie in [tagAsset].
          await into(assetTags).insertOnConflictUpdate(
            AssetTagsCompanion.insert(
              assetId: behaltenId,
              tagId: tag.tagId,
              quelle: const Value(Tagquelle.hand),
            ),
          );
        } else {
          await into(assetTags).insert(
            AssetTagsCompanion.insert(
              assetId: behaltenId,
              tagId: tag.tagId,
              quelle: Value(tag.quelle),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
      for (final album in albenDerKopie) {
        await into(albumAssets).insert(
          AlbumAssetsCompanion.insert(
            albumId: album.albumId,
            assetId: behaltenId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }

    final beschreibung = beschreibungen.isEmpty
        ? null
        : beschreibungenVerbinden
        ? beschreibungen.join('\n\n')
        : beschreibungen.first;
    await (update(assets)..where((t) => t.id.equals(behaltenId))).write(
      AssetsCompanion(
        isFavorite: Value(favorit),
        rating: Value(bewertung),
        colorLabel: Value(farbe),
        description: Value(beschreibung),
      ),
    );
    await moveToTrash(ids);
  });

  Future<void> restoreFromTrash(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
      const AssetsCompanion(isTrashed: Value(false), trashedAt: Value(null)),
    );
    _embeddingsGeneration++;
  }

  /// Löscht die Datenbankzeile endgültig. Das eigentliche Löschen der Datei
  /// auf der Festplatte übernimmt StoragePaths.
  Future<void> deleteAssetRows(List<String> assetIds) async {
    await (delete(assets)..where((t) => t.id.isIn(assetIds))).go();
    // Ausnahmen der Duplikatsuche mit wegräumen. Sie würden sonst als
    // Zeilen ohne Foto liegen bleiben und niemandem mehr auffallen – ein
    // Paar, dessen eine Hälfte es nicht mehr gibt, kann nie wieder wirken.
    await (delete(
      duplikatAusnahmen,
    )..where((t) => t.assetA.isIn(assetIds) | t.assetB.isIn(assetIds))).go();
    _embeddingsGeneration++;
  }

  // --- Ausnahmen der Duplikatsuche --------------------------------------

  /// Alle Ausnahmen als Schlüsselmenge für [findDuplicateGroups].
  ///
  /// Nicht `duplikatAusnahmen()` – so heisst bereits die von drift erzeugte
  /// Tabelle, und eine Methode gleichen Namens verdeckt sie im ganzen
  /// Klassenrumpf.
  Future<Set<String>> duplikatAusnahmeSchluessel() async {
    final zeilen = await select(duplikatAusnahmen).get();
    return {for (final z in zeilen) duplikatPaarSchluessel(z.assetA, z.assetB)};
  }

  Future<int> zaehleDuplikatAusnahmen() async {
    final zaehler = duplikatAusnahmen.assetA.count();
    final zeile = await (selectOnly(
      duplikatAusnahmen,
    )..addColumns([zaehler])).getSingle();
    return zeile.read(zaehler) ?? 0;
  }

  /// Nimmt alle Paare innerhalb von [assetIds] von der Duplikatsuche aus –
  /// also eine ganze Gruppe auf einmal.
  ///
  /// Alle Paare und nicht nur ein Merkmal an der Gruppe: Gruppen entstehen
  /// bei jedem Lauf neu und hängen an der eingestellten Schwelle; eine
  /// gespeicherte Gruppen-Kennung wäre beim nächsten Regler-Ruck wertlos.
  Future<void> ignoriereDuplikatgruppe(List<String> assetIds) async {
    if (assetIds.length < 2) return;
    final jetzt = DateTime.now();
    await batch((b) {
      for (var i = 0; i < assetIds.length; i++) {
        for (var j = i + 1; j < assetIds.length; j++) {
          final a = assetIds[i], c = assetIds[j];
          final klein = a.compareTo(c) <= 0 ? a : c;
          final gross = a.compareTo(c) <= 0 ? c : a;
          b.insert(
            duplikatAusnahmen,
            DuplikatAusnahmenCompanion.insert(
              assetA: klein,
              assetB: gross,
              angelegtAm: jetzt,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });
  }

  /// Nimmt die Ausnahmen einer einzelnen Gruppe zurück – für das
  /// „Rückgängig" direkt nach dem Ausblenden.
  Future<void> hebeDuplikatgruppeAuf(List<String> assetIds) async {
    if (assetIds.length < 2) return;
    await batch((b) {
      for (var i = 0; i < assetIds.length; i++) {
        for (var j = i + 1; j < assetIds.length; j++) {
          final a = assetIds[i], c = assetIds[j];
          final klein = a.compareTo(c) <= 0 ? a : c;
          final gross = a.compareTo(c) <= 0 ? c : a;
          b.deleteWhere(
            duplikatAusnahmen,
            ($DuplikatAusnahmenTable t) =>
                t.assetA.equals(klein) & t.assetB.equals(gross),
          );
        }
      }
    });
  }

  /// Hebt alle Ausnahmen wieder auf – der Weg zurück, wenn zu viel
  /// ausgeblendet wurde.
  Future<int> loescheDuplikatAusnahmen() => delete(duplikatAusnahmen).go();
}

/// Was im Papierkorb liegt, in zwei Zahlen – siehe
/// [AppDatabase.watchPapierkorbUmfang].
class Papierkorbumfang {
  const Papierkorbumfang({required this.anzahl, required this.bytes});

  final int anzahl;
  final int bytes;

  bool get istLeer => anzahl == 0;

  @override
  bool operator ==(Object other) =>
      other is Papierkorbumfang &&
      other.anzahl == anzahl &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(anzahl, bytes);
}

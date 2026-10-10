part of '../database.dart';

/// Bildbeschreibungen, Schärfe, gemeinsame Bildanalyse, XMP-Ausgabe, Sichten, Ortsnamen.
extension AuswertungsAbfragen on AppDatabase {
  /// Bild-Assets ohne KI-Bildbeschreibung – für den nachträglichen Lauf in
  /// den Werkzeugen, analog zu [assetsForOcrBackfill] (gesperrte Fotos
  /// ebenfalls ausgenommen, siehe dort).
  /// [alle] nimmt auch Fotos mit, die schon eine Beschreibung haben – für
  /// den Modellwechsel: Die vorhandenen Sätze stammen vom abgelösten
  /// ViT-GPT2 und sind messbar schlechter (siehe
  /// [ModelCatalog.captioningFlorence]).
  /// Bedingung für „braucht (noch) eine Bildunterschrift vom Modell".
  ///
  /// [aiCaptionEdited] schliesst aus, was von Hand geschrieben wurde – auch
  /// bei [alle]. „Alle Fotos" ist für einen Modellwechsel gedacht, nicht
  /// zum Wegwerfen getippter Sätze; wer die Maschine wieder ranlassen will,
  /// leert das Feld.
  Expression<bool> _brauchtBeschreibung(bool alle) =>
      _auswertbar(assets) &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      assets.aiCaptionEdited.equals(false) &
      (alle ? const Constant(true) : assets.aiCaptionScanned.equals(false));

  Future<List<AssetData>> assetsForCaptionBackfill({bool alle = false}) =>
      (select(assets)..where((t) => _brauchtBeschreibung(alle))).get();

  /// Zählvariante von [assetsForCaptionBackfill], siehe [countLocationBackfill].
  Future<int> countCaptionBackfill() =>
      _countWhere(_brauchtBeschreibung(false));

  /// Bedingung für „hat eine englische Bildunterschrift, aber (noch) keine
  /// deutsche".
  ///
  /// Einmal geschrieben und von Liste wie Zählung genutzt: Die übrigen Paare
  /// hier tippen ihr WHERE zweimal, was ein eigener Test absichern muss
  /// (siehe background_task_counts_test.dart). Bei einer Bedingung mit
  /// Schalter ist das Auseinanderdriften zu wahrscheinlich, um es nur zu
  /// prüfen.
  Expression<bool> _uebersetzbareBeschreibung(bool alle) =>
      _auswertbar(assets) &
      assets.isTrashed.equals(false) &
      assets.isLocked.equals(false) &
      assets.aiCaption.isNotNull() &
      assets.aiCaption.equals('').not() &
      // Ein von Hand geschriebener Satz wird nicht maschinell überschrieben.
      assets.aiCaptionEdited.equals(false) &
      (alle ? const Constant(true) : assets.aiCaptionDe.isNull());

  /// Fotos, deren englische Bildunterschrift noch übersetzt werden kann.
  ///
  /// Eigene Aufgabe statt eines Nebenwegs der Bildbeschreibung: Wer die
  /// Übersetzung erst nachträglich einschaltet, müsste sonst das
  /// 275-MB-Modell über die ganze Bibliothek erneut laufen lassen, um an
  /// deutsche Sätze zu kommen. Das Übersetzen allein kostet gemessen
  /// 0,03–0,05 s je Satz – die Sätze sind längst da.
  Future<List<AssetData>> assetsForCaptionTranslation({bool alle = false}) =>
      (select(assets)..where((t) => _uebersetzbareBeschreibung(alle))).get();

  /// Zählvariante von [assetsForCaptionTranslation].
  Future<int> countCaptionTranslation() =>
      _countWhere(_uebersetzbareBeschreibung(false));

  /// Trägt die deutsche Fassung nach, ohne das englische Original oder das
  /// `aiCaptionScanned`-Merkmal anzufassen.
  Future<void> setAiCaptionDe(String assetId, String deutsch) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(aiCaptionDe: Value(deutsch)),
      );

  /// Übernimmt eine von Hand geänderte Bildunterschrift.
  ///
  /// [deutsch] wählt die Spalte; leerer Text wird zu `null`. Das Merkmal
  /// [Assets.aiCaptionEdited] wird gesetzt, solange in einer der beiden
  /// Sprachen etwas steht – ist danach beides leer, fällt es wieder weg und
  /// das Foto ist erneut Kandidat für das Modell. Genau so lässt sich eine
  /// Bearbeitung zurücknehmen, ohne dafür einen eigenen Knopf zu brauchen.
  Future<void> setAiCaptionVonHand(
    String assetId,
    String? text, {
    required bool deutsch,
  }) async {
    final gesetzt = (text ?? '').trim();
    final wert = Value<String?>(gesetzt.isEmpty ? null : gesetzt);
    final vorher = await assetById(assetId);
    if (vorher == null) return;

    final englischDanach = deutsch ? (vorher.aiCaption ?? '') : gesetzt;
    final deutschDanach = deutsch ? gesetzt : (vorher.aiCaptionDe ?? '');
    final nochWas =
        englischDanach.trim().isNotEmpty || deutschDanach.trim().isNotEmpty;

    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        aiCaption: deutsch ? const Value.absent() : wert,
        aiCaptionDe: deutsch ? wert : const Value.absent(),
        aiCaptionEdited: Value(nochWas),
        // Ein von Hand geschriebener Satz zählt als vorhanden – sonst stünde
        // das Foto weiter unter „Wartend", obwohl da etwas steht. Und
        // umgekehrt: Sind beide Felder leer, ist es wieder Kandidat für das
        // Modell. Das ist der einzige Weg zurück, und er braucht keinen
        // eigenen Knopf.
        //
        // Das Zurücksetzen ist hier ungefährlich, obwohl `aiCaptionScanned`
        // sonst gerade verhindern soll, dass ein Foto ohne brauchbares
        // Ergebnis endlos erneut durchs Modell läuft: Hierher kommt nur, wer
        // wirklich etwas geändert hat – ein Feld zu leeren, in dem schon
        // nichts stand, schreibt gar nicht erst.
        aiCaptionScanned: Value(nochWas),
      ),
    );
  }

  Future<void> setSharpnessScore(String assetId, double score) =>
      (update(assets)..where((t) => t.id.equals(assetId))).write(
        AssetsCompanion(sharpnessScore: Value(score)),
      );

  /// Bild-Assets, denen mindestens eine der drei Auswertungen fehlt, die
  /// DASSELBE dekodierte Bild brauchen: Unschärfe, Gesichter, CLIP-Embedding.
  ///
  /// Grundlage für den gemeinsamen Durchlauf in
  /// [LibraryState.starteHintergrundanalyse]: Statt dass jede Stufe die
  /// Bibliothek für sich durchgeht und jedes Foto erneut dekodiert (gemessen
  /// rund 85 ms je Foto), wird einmal dekodiert und das Ergebnis an alle drei
  /// weitergereicht.
  ///
  /// `hatEmbedding` kommt aus dem Left Join und sagt, ob die CLIP-Stufe für
  /// dieses Foto noch etwas zu tun hat – die beiden anderen Stufen lassen
  /// sich direkt am Asset ablesen ([Assets.sharpnessScore], [Assets.facesScanned]).
  Future<List<({AssetData asset, bool hatEmbedding})>>
  assetsForCombinedImageAnalysis() async {
    final query =
        select(assets).join([
          leftOuterJoin(
            imageEmbeddings,
            imageEmbeddings.assetId.equalsExp(assets.id),
          ),
        ])..where(
          _auswertbar(assets) &
              assets.isTrashed.equals(false) &
              assets.isLocked.equals(false) &
              (assets.sharpnessScore.isNull() |
                  assets.facesScanned.equals(false) |
                  imageEmbeddings.assetId.isNull()),
        );
    final rows = await query.get();
    return [
      for (final r in rows)
        (
          asset: r.readTable(assets),
          hatEmbedding: r.readTableOrNull(imageEmbeddings) != null,
        ),
    ];
  }

  /// Bild-Assets ohne Schärfe-Score – für den nachträglichen Lauf in den
  /// Werkzeugen. Gesperrte Fotos ausgenommen, siehe [assetsForOcrBackfill].
  Future<List<AssetData>> assetsForBlurBackfill() =>
      (select(assets)..where(
            (t) =>
                _auswertbar(t) &
                t.isTrashed.equals(false) &
                t.isLocked.equals(false) &
                t.sharpnessScore.isNull(),
          ))
          .get();

  /// Zählvariante von [assetsForBlurBackfill], siehe [countLocationBackfill].
  Future<int> countBlurBackfill() => _countWhere(
    _auswertbar(assets) &
        assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        assets.sharpnessScore.isNull(),
  );

  /// Assets für den XMP-Sidecar-Export (Bibliothek + Backup) – bewusst OHNE
  /// gesperrte Assets: ein Sidecar würde Beschreibung/GPS/Tags im Klartext
  /// neben die (im Falle der Bibliothek noch verschlüsselte, im Falle des
  /// Backups gar nicht erst kopierte) Originaldatei legen und damit genau
  /// die Vertraulichkeit unterlaufen, wegen der das Foto gesperrt wurde –
  /// exakt dieselbe `isLocked`-Ausnahme wie bei [assetsNotBackedUp]. Beim
  /// manuellen Export (siehe ExportService.exportAsset) gilt das NICHT: dort
  /// hat der Nutzer das Entschlüsseln/Exportieren bereits aktiv angestoßen.
  Future<List<AssetData>> assetsForXmpExport() => (select(
    assets,
  )..where((t) => t.isTrashed.equals(false) & t.isLocked.equals(false))).get();

  /// Zählvariante von [assetsForXmpExport], siehe [countLocationBackfill].
  Future<int> countXmpExport({DateTime? importiertNach}) => _countWhere(
    assets.isTrashed.equals(false) &
        assets.isLocked.equals(false) &
        _importiertNach(importiertNach),
  );

  /// Noch unbewertete Fotos/Videos für den Sichtungs-Modus (Culling) –
  /// bewusst `rating == 0` statt eines eigenen "gesichtet"-Flags: sobald ein
  /// Foto eine Bewertung (auch 0 Sterne explizit gesetzt gäbe es nicht, da
  /// die Sternereihe bei erneutem Tippen auf 0 zurücksetzt) oder eine
  /// Ablehnung (Papierkorb) erhalten hat, verschwindet es automatisch aus
  /// dieser Liste. Neueste zuerst, da frisch importierte Fotos der
  /// Hauptanwendungsfall sind.
  Future<List<AssetData>> assetsForCulling({int limit = 500}) =>
      (select(assets)
            ..where(
              (t) =>
                  t.rating.equals(0) &
                  t.isTrashed.equals(false) &
                  t.isLocked.equals(false),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)])
            ..limit(limit))
          .get();

  /// Setzt die per Umkehr-Geokodierung ermittelten Orts-Namen eines Assets
  /// (siehe ReverseGeocoder) – beim Import automatisch (falls der
  /// GeoNames-Datensatz bereits heruntergeladen ist) oder nachträglich über
  /// das Werkzeug "Orte auflösen".
  Future<void> setLocationNames(
    String assetId, {
    String? country,
    String? state,
    required String city,
  }) => (update(assets)..where((t) => t.id.equals(assetId))).write(
    AssetsCompanion(
      locationCountry: Value(country),
      locationState: Value(state),
      locationCity: Value(city),
    ),
  );

  /// Fotos mit bekanntem GPS-Ort, aber noch ohne aufgelösten Orts-Namen – für
  /// das nachträgliche Auflösen (Werkzeuge) sowie den erstmaligen Lauf,
  /// nachdem der GeoNames-Datensatz heruntergeladen wurde.
  Future<List<AssetData>> assetsForLocationNameBackfill() =>
      (select(assets)..where(
            (t) =>
                t.isTrashed.equals(false) &
                t.latitude.isNotNull() &
                t.longitude.isNotNull() &
                t.locationCountry.isNull(),
          ))
          .get();

  /// Zählvariante von [assetsForLocationNameBackfill], siehe [countLocationBackfill].
  Future<int> countLocationNameBackfill() => _countWhere(
    assets.isTrashed.equals(false) &
        assets.latitude.isNotNull() &
        assets.longitude.isNotNull() &
        assets.locationCountry.isNull(),
  );
}

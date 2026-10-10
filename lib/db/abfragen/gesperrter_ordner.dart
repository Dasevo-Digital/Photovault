part of '../database.dart';

/// Der gesperrte Ordner (PIN und Verschlüsselung).
extension GesperrteAbfragen on AppDatabase {
  // -----------------------------------------------------------------------
  // Gesperrter Ordner (PIN-Schutz + echte Verschlüsselung für private Fotos)
  // -----------------------------------------------------------------------
  //
  // Die eigentliche Kryptografie (Master-Key erzeugen/verpacken/entpacken,
  // Dateien ver-/entschlüsseln) läuft über VaultCrypto/LibraryState – hier
  // wird nur das Ergebnis (verpackter Master-Key + Salt/Nonce) gespeichert
  // bzw. ausgelesen.

  Future<bool> hasPinSet() async {
    final row = await (select(
      privacySettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.wrappedMasterKey != null;
  }

  Future<PrivacySettingsData?> privacySettingsRow() =>
      (select(privacySettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> saveVaultKey({
    required Uint8List kdfSalt,
    required Uint8List nonce,
    required Uint8List wrapped,
  }) => into(privacySettings).insertOnConflictUpdate(
    PrivacySettingsCompanion.insert(
      id: const Value(0),
      kdfSalt: Value(kdfSalt),
      wrappedMasterKeyNonce: Value(nonce),
      wrappedMasterKey: Value(wrapped),
    ),
  );

  Future<void> clearVaultKey() =>
      (delete(privacySettings)..where((t) => t.id.equals(0))).go();

  Future<void> setProtectPrivateMetadata(bool value) =>
      into(privacySettings).insertOnConflictUpdate(
        PrivacySettingsCompanion.insert(
          id: const Value(0),
          protectMetadata: Value(value),
        ),
      );

  Future<Map<String, List<String>>> privateRelationsForAsset(
    String assetId,
  ) async {
    final tagRows = await (select(
      assetTags,
    )..where((t) => t.assetId.equals(assetId))).get();
    final albumRows = await (select(
      albumAssets,
    )..where((a) => a.assetId.equals(assetId))).get();
    return {
      'tags': [for (final row in tagRows) '${row.tagId}\u0000${row.quelle}'],
      'albums': [for (final row in albumRows) row.albumId],
    };
  }

  /// Ersetzt die unmittelbar lesbaren privaten Angaben durch neutrale
  /// Werte. Der Aufrufer muss die Originalwerte zuvor verschlüsselt haben.
  Future<void> hidePrivateMetadata(String assetId) => transaction(() async {
    await (update(assets)..where((a) => a.id.equals(assetId))).write(
      AssetsCompanion(
        originalFileName: const Value('Private Aufnahme'),
        fileCreatedAt: Value(DateTime.utc(1970)),
        importedAt: Value(DateTime.utc(1970)),
        isFavorite: const Value(false),
        description: const Value(null),
        latitude: const Value(null),
        longitude: const Value(null),
        cameraMake: const Value(null),
        cameraModel: const Value(null),
        lensModel: const Value(null),
        focalLengthMm: const Value(null),
        fNumber: const Value(null),
        iso: const Value(null),
        exposureTimeSeconds: const Value(null),
        exposureBiasEv: const Value(null),
        focalLength35mm: const Value(null),
        locationCountry: const Value(null),
        locationState: const Value(null),
        locationCity: const Value(null),
        rating: const Value(0),
        colorLabel: const Value(null),
        ocrText: const Value(null),
        ocrBoxen: const Value(null),
        zeitversatzMinuten: const Value(null),
        aiCaption: const Value(null),
        aiCaptionDe: const Value(null),
      ),
    );
    await (delete(assetTags)..where((t) => t.assetId.equals(assetId))).go();
    await (delete(albumAssets)..where((a) => a.assetId.equals(assetId))).go();
  });

  Future<void> restorePrivateMetadata(
    String assetId,
    AssetsCompanion metadata, {
    required List<(String, String)> tags,
    required List<String> albumIds,
  }) => transaction(() async {
    await (update(assets)..where((a) => a.id.equals(assetId))).write(metadata);
    await batch((b) {
      for (final (tagId, source) in tags) {
        b.insert(
          assetTags,
          AssetTagsCompanion.insert(
            assetId: assetId,
            tagId: tagId,
            quelle: Value(source),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      for (final albumId in albumIds) {
        b.insert(
          albumAssets,
          AlbumAssetsCompanion.insert(albumId: albumId, assetId: assetId),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  });

  Future<void> setAssetsLocked(List<String> assetIds, bool locked) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
      AssetsCompanion(isLocked: Value(locked)),
    );
    _embeddingsGeneration++;
  }

  /// Entfernt die maschinell aus dem BILDINHALT abgeleiteten Daten eines
  /// Assets: erkannten Text, KI-Bildunterschrift (in **beiden** Sprachen)
  /// und CLIP-Embedding.
  ///
  /// Wird beim Sperren aufgerufen. Ohne das blieb der Inhalt eines
  /// gesperrten Fotos in der unverschlüsselten `library.sqlite` lesbar –
  /// bei einem abfotografierten Dokument also genau der Text, wegen dem es
  /// gesperrt wurde (Audit-Fund). Über die Oberfläche war er zwar nicht
  /// erreichbar (searchAssets filtert `isLocked`), wohl aber für jeden mit
  /// Dateizugriff.
  ///
  /// Verlustfrei, nur nicht kostenlos: Die `*Scanned`-Flags werden
  /// zurückgesetzt, sodass die Hintergrundanalyse alles neu berechnet,
  /// sobald das Foto wieder entsperrt ist.
  ///
  /// Seit Fassung 56 gehören auch die **Schlagwörter der Bilderkennung**
  /// dazu. Sie standen vorher als einzige aus dem Bildinhalt abgeleitete
  /// Angabe weiter im Klartext – nicht aus Nachlässigkeit, sondern weil
  /// sie von Handvergaben nicht zu unterscheiden waren. Siehe [Tagquelle].
  ///
  /// Bewusst NICHT angetastet:
  /// - [description] – Nutzer-Freitext, kein abgeleiteter Wert.
  /// - Schlagwörter mit [Tagquelle.hand] – die zu löschen wäre echter
  ///   Datenverlust, nicht nur eine Neuberechnung.
  /// - Eine Bildunterschrift mit [Assets.aiCaptionEdited] – dann sind es
  ///   die Worte des Nutzers, und dieselbe Regel wie bei [description]
  ///   gilt. Bis zur 17. Prüfrunde wurde sie trotzdem gelöscht, und zwar
  ///   **unwiederbringlich**: Das Merkmal blieb dabei stehen, und
  ///   [_brauchtBeschreibung] schliesst genau damit aus, was von Hand
  ///   geschrieben wurde – nach dem Entsperren hätte sie also auch
  ///   niemand neu berechnet.
  /// - [Assets.latitude]/[Assets.longitude] – Aufnahmedaten der Datei,
  ///   nicht aus dem Bild gerechnet, und teils von Hand gesetzt. Sichtbar
  ///   sind sie nicht: [assetsWithLocation] filtert `isLocked`.
  /// - [sharpnessScore] – eine Zahl über die Bildschärfe verrät nichts
  ///   über den Bildinhalt und wird für die Ausschuss-Sichtung gebraucht.
  /// - Die **Einbettung eines Gesichts** (`faces.embedding`). Sie ist aus
  ///   dem Bildinhalt abgeleitet und gehörte nach derselben Regel hierher –
  ///   aber sie liesse sich nicht wiederherstellen. Berechnet wurde sie aus
  ///   einem an den Landmarken **ausgerichteten** Ausschnitt; die Landmarken
  ///   stehen nirgends in der Zeile, und ohne sie fällt
  ///   `FaceEngineService.embedFace` auf einen einfachen Kastenausschnitt
  ///   zurück. Das ergäbe eine andere und schlechtere Einbettung, und die
  ///   Wiedererkennung würde für genau die Fotos schlechter, die jemand
  ///   gesperrt hat. Ein Klartextrest von 512 Byte ist der kleinere Preis;
  ///   festgehalten in der 15. Prüfrunde.
  Future<void> clearDerivedContentData(List<String> assetIds) async {
    await (update(assets)..where((t) => t.id.isIn(assetIds))).write(
      const AssetsCompanion(
        ocrText: Value(null),
        // Die Stellen stehen im Klartext neben dem Text und verraten mit ihm
        // dasselbe – ohne diese Zeile bliebe der Wortlaut eines gesperrten
        // Fotos in der unverschlüsselten Datenbank stehen.
        ocrBoxen: Value(null),
        ocrScanned: Value(false),
        // Damit die Verschlagwortung nach dem Entsperren neu läuft und die
        // gelöschten Begriffe zurückbringt.
        aiTagsScanned: Value(false),
      ),
    );

    // Die Bildunterschrift getrennt, weil sie nur wegdarf, solange sie
    // wirklich von der Maschine stammt – siehe [aiCaptionEdited] oben.
    await (update(assets)
          ..where((t) => t.id.isIn(assetIds) & t.aiCaptionEdited.equals(false)))
        .write(
          const AssetsCompanion(
            aiCaption: Value(null),
            // **Beide** Sprachen. Bis zur 17. Prüfrunde stand hier nur die
            // englische, und die Übersetzung blieb im Klartext stehen: Wer sie
            // eingeschaltet hatte, dem nahm das Sperren den einen Satz weg und
            // liess denselben Satz auf Deutsch liegen. Der Test dazu hatte das
            // Feld nie gesetzt und ging deshalb durch.
            aiCaptionDe: Value(null),
            aiCaptionScanned: Value(false),
          ),
        );
    await (delete(
      imageEmbeddings,
    )..where((t) => t.assetId.isIn(assetIds))).go();
    await (delete(assetTags)..where(
          (t) => t.assetId.isIn(assetIds) & t.quelle.equals(Tagquelle.ki),
        ))
        .go();
    _embeddingsGeneration++;
  }

  /// Hängt Profilbilder um, die auf einen Gesichts-Ausschnitt aus einem
  /// gerade gesperrten Foto zeigen.
  ///
  /// Die Ausschnittdatei selbst wird beim Sperren mitverschlüsselt (siehe
  /// `LibraryState._encryptAssetFiles`) – sie ist also kein Leck. Aber der
  /// Pfad im Profilbild zeigt danach auf Chiffrat: Die Person verliert
  /// ihren Avatar in Erkunden, Personen und Stammbaum, bis das Foto wieder
  /// entsperrt wird.
  ///
  /// Ersetzt wird durch einen Ausschnitt aus einem nicht gesperrten Foto;
  /// gibt es keinen, bleibt die Person ohne Profilbild. Beim Entsperren
  /// wird nichts zurückgehängt – jeder gültige Ausschnitt tut es, und ein
  /// automatisches Zurücksetzen würde eine inzwischen von Hand getroffene
  /// Wahl überschreiben.
  Future<int> verlegeProfilbilderVon(List<String> assetIds) async {
    final betroffen =
        await (select(faces)..where(
              (t) => t.assetId.isIn(assetIds) & t.cropRelativePath.isNotNull(),
            ))
            .get();
    final pfade = [for (final f in betroffen) f.cropRelativePath!];
    if (pfade.isEmpty) return 0;

    final personen = await (select(
      people,
    )..where((t) => t.coverFaceCropPath.isIn(pfade))).get();
    for (final person in personen) {
      final ersatz =
          await (select(
                  faces,
                ).join([innerJoin(assets, assets.id.equalsExp(faces.assetId))])
                ..where(
                  faces.personId.equals(person.id) &
                      faces.cropRelativePath.isNotNull() &
                      assets.isLocked.equals(false) &
                      assets.isTrashed.equals(false),
                )
                ..limit(1))
              .get();
      await (update(people)..where((t) => t.id.equals(person.id))).write(
        PeopleCompanion(
          coverFaceCropPath: Value(
            ersatz.isEmpty
                ? null
                : ersatz.first.readTable(faces).cropRelativePath,
          ),
        ),
      );
    }
    return personen.length;
  }

  Stream<List<AssetData>> watchLockedAssets() {
    final abfrage = select(assets)
      ..where((t) => t.isLocked.equals(true) & t.isTrashed.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.fileCreatedAt)]);
    return _gedrosselt(() => abfrage, TableUpdateQuery.onTable(assets));
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/search_filters.dart';

import 'hilfen/quelltext.dart';

/// Die Befehlsschicht (packages/kern/lib/befehle): Jede Änderung durch den
/// Nutzer soll als Befehl laufen, damit sie sich später an einen Server
/// schicken lässt (Issue #86).
///
/// Geprüft wird dreierlei: dass jeder Befehl den Weg über JSON übersteht,
/// dass er wirkt wie der direkte Aufruf, den er ersetzt, und dass jede
/// Schreibmethode der Datenbank eingeordnet ist – samt der Zusage, dass,
/// was schon Befehl ist, niemand mehr direkt aufruft.
void main() {
  group('Befehle über JSON', () {
    /// Ein Beispiel je Art. Die Weiche in [artVon] ist erschöpfend: Eine
    /// neue Befehlsklasse ohne Beispiel hier kompiliert nicht.
    final beispiele = <Befehl<Object?>>[
      const FavoritSetzen(['a1', 'a2'], true),
      const BewertungSetzen(['a1'], 4),
      const FarbmarkeSetzen(['a1', 'a3'], null),
      const BeschreibungSetzen(['a2'], 'Am Strand – „mit Ü“'),
      const MarkierungenSetzen({
        'a1': (favorit: true, bewertung: 3, farbe: 'rot'),
        'a2': (favorit: false, bewertung: 0, farbe: null),
      }),
      const SchlagwortAnheften(['a1'], 'Strand', quelle: Tagquelle.ki),
      const SchlagwortAnheftenPerKennung('a1', 't1'),
      const SchlagwortLoesen('a1', 't1'),
      const SchlagwortAbnehmen(['a1', 'a2'], 'Strand'),
      const KiSchlagwoerterZuruecknehmen(),
      const KiBegriffHinzufuegen('Leuchtturm'),
      const KiBegriffEntfernen(7),
      const VokabularUebersetzen({'Strand': 'Beach'}),
      AlbumAnlegen('al1', 'Sommer', DateTime(2026, 7, 1, 12, 30)),
      const AlbumFuellen('al1', ['a1', 'a2']),
      const AusAlbumNehmen('al1', ['a2'], albumLoeschen: true),
      const AlbumTitelbildSetzen('al1', null),
      const SucheMerken(
        's1',
        'Rote Fünfer',
        SearchFilters(query: 'Hafen', minRating: 5),
      ),
      const SucheVergessen('s1'),
    ];

    String artVon(Befehl<Object?> b) => switch (b) {
      FavoritSetzen() => 'favoritSetzen',
      BewertungSetzen() => 'bewertungSetzen',
      FarbmarkeSetzen() => 'farbmarkeSetzen',
      BeschreibungSetzen() => 'beschreibungSetzen',
      MarkierungenSetzen() => 'markierungenSetzen',
      SchlagwortAnheften() => 'schlagwortAnheften',
      SchlagwortAnheftenPerKennung() => 'schlagwortAnheftenPerKennung',
      SchlagwortLoesen() => 'schlagwortLoesen',
      SchlagwortAbnehmen() => 'schlagwortAbnehmen',
      KiSchlagwoerterZuruecknehmen() => 'kiSchlagwoerterZuruecknehmen',
      KiBegriffHinzufuegen() => 'kiBegriffHinzufuegen',
      KiBegriffEntfernen() => 'kiBegriffEntfernen',
      VokabularUebersetzen() => 'vokabularUebersetzen',
      AlbumAnlegen() => 'albumAnlegen',
      AlbumFuellen() => 'albumFuellen',
      AusAlbumNehmen() => 'ausAlbumNehmen',
      AlbumTitelbildSetzen() => 'albumTitelbildSetzen',
      SucheMerken() => 'sucheMerken',
      SucheVergessen() => 'sucheVergessen',
    };

    test('jede Art hat ein Beispiel und ist zum Lesen eingetragen', () {
      expect({for (final b in beispiele) artVon(b)}, Befehl.arten.toSet());
      for (final b in beispiele) {
        expect(b.art, artVon(b));
      }
    });

    test('hin und zurück bleibt jeder Befehl derselbe', () {
      for (final b in beispiele) {
        final text = jsonEncode(b.alsJson());
        final zurueck = Befehl.ausJson(
          (jsonDecode(text) as Map).cast<String, Object?>(),
        );
        expect(zurueck.runtimeType, b.runtimeType);
        expect(jsonEncode(zurueck.alsJson()), text, reason: b.art);
      }
    });

    test('ein unbekannter Befehl ist ein Fehler, kein Stillschweigen', () {
      expect(
        () => Befehl.ausJson({'art': 'gibtEsNicht', 'werte': {}}),
        throwsFormatException,
      );
    });
  });

  group('Befehle wirken wie der direkte Aufruf', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      for (final id in ['a1', 'a2', 'a3']) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2025),
                importedAt: DateTime(2026),
              ),
            );
      }
    });
    tearDown(() => db.close());

    Future<AssetData> aufnahme(String id) async =>
        (await db.assetsByIds([id])).single;

    test(
      'Favorit, Sterne, Farbe und Beschreibung – einzeln und mehrere',
      () async {
        await db.fuehreAus(const FavoritSetzen(['a1'], true));
        await db.fuehreAus(const BewertungSetzen(['a1', 'a2'], 5));
        await db.fuehreAus(const FarbmarkeSetzen(['a2'], 'gruen'));
        await db.fuehreAus(const BeschreibungSetzen(['a2', 'a3'], 'Hafen'));
        final a1 = await aufnahme('a1');
        final a2 = await aufnahme('a2');
        final a3 = await aufnahme('a3');
        expect([a1.isFavorite, a1.rating, a1.colorLabel], [true, 5, null]);
        expect([a2.isFavorite, a2.rating, a2.colorLabel], [false, 5, 'gruen']);
        expect([a2.description, a3.description], ['Hafen', 'Hafen']);
        expect(a3.rating, 0);
      },
    );

    test('Markierungen stellen je Aufnahme den Stand davor her', () async {
      await db.fuehreAus(const FavoritSetzen(['a1', 'a2'], true));
      await db.fuehreAus(const BewertungSetzen(['a1', 'a2'], 4));
      await db.fuehreAus(
        const MarkierungenSetzen({
          'a1': (favorit: false, bewertung: 2, farbe: 'rot'),
          'a2': (favorit: true, bewertung: 0, farbe: null),
        }),
      );
      final a1 = await aufnahme('a1');
      final a2 = await aufnahme('a2');
      expect([a1.isFavorite, a1.rating, a1.colorLabel], [false, 2, 'rot']);
      expect([a2.isFavorite, a2.rating, a2.colorLabel], [true, 0, null]);
    });

    test('Schlagwörter: Hand schlägt KI, Abnehmen räumt auf', () async {
      await db.fuehreAus(
        const SchlagwortAnheften(['a1'], 'Strand', quelle: Tagquelle.ki),
      );
      await db.fuehreAus(const SchlagwortAnheften(['a1', 'a2'], 'Strand'));
      // Die Bilderkennung darf die Handvergabe nicht zurückholen.
      await db.fuehreAus(
        const SchlagwortAnheften(['a2'], 'Strand', quelle: Tagquelle.ki),
      );
      expect(await db.kiTagAnzahl(), 0);
      expect(await db.tragenSchlagwort(['a1', 'a2', 'a3'], 'Strand'), {
        'a1',
        'a2',
      });
      await db.fuehreAus(const SchlagwortAbnehmen(['a1', 'a2'], 'Strand'));
      expect(await db.tragenSchlagwort(['a1', 'a2'], 'Strand'), isEmpty);
      await db.fuehreAus(
        const SchlagwortAnheften(['a3'], 'Hafen', quelle: Tagquelle.ki),
      );
      expect(await db.fuehreAus(const KiSchlagwoerterZuruecknehmen()), 1);
    });

    test('Alben: anlegen, füllen, Titelbild, wieder herausnehmen', () async {
      await db.fuehreAus(AlbumAnlegen('al1', 'Sommer', DateTime(2026, 7, 1)));
      await db.fuehreAus(const AlbumFuellen('al1', ['a1', 'a2', 'a3']));
      await db.fuehreAus(const AlbumTitelbildSetzen('al1', 'a2'));
      await db.fuehreAus(const AusAlbumNehmen('al1', ['a3']));
      expect(await db.imAlbum('al1', ['a1', 'a2', 'a3']), {'a1', 'a2'});
      await db.fuehreAus(
        const AusAlbumNehmen('al1', ['a1'], albumLoeschen: true),
      );
      expect(await db.imAlbum('al1', ['a1', 'a2', 'a3']), isEmpty);
    });

    test('jeder ausgeführte Befehl wird gemeldet, nach der Wirkung', () async {
      final gemeldet = <String>[];
      db.befehlsbeobachter.add((b) async {
        gemeldet.add('${b.art}:${(await aufnahme('a1')).rating}');
      });
      await db.fuehreAus(const BewertungSetzen(['a1'], 3));
      await pumpEventQueue();
      expect(gemeldet, ['bewertungSetzen:3']);
    });
  });

  group('Jeder Schreibzugriff ist eingeordnet', () {
    final gefunden = _schreibmethoden();

    test('die Suche findet die Schreibmethoden', () {
      // Ein Riegel gegen einen Suchausdruck, der nach einer Umformatierung
      // nichts mehr findet – dann wäre der Rest dieser Gruppe grün, weil er
      // nichts prüft.
      expect(gefunden.length, greaterThan(150));
      expect(gefunden, contains('setFavorite'));
    });

    test('jede Schreibmethode steht in der Einordnung', () {
      final fehlt = gefunden.difference(_einordnung.keys.toSet());
      expect(
        fehlt,
        isEmpty,
        reason:
            'Neue Schreibmethode ohne Einordnung. Ist sie eine Änderung '
            'durch den Nutzer, gehört sie als Befehl nach '
            'packages/kern/lib/befehle; sonst in _einordnung unten.',
      );
    });

    test('die Einordnung nennt keine Methode, die es nicht mehr gibt', () {
      expect(_einordnung.keys.toSet().difference(gefunden), isEmpty);
    });

    test('was ein Befehl ist, ruft niemand mehr direkt auf', () {
      final befehle = [
        for (final e in _einordnung.entries)
          if (e.value == _Art.befehl) e.key,
      ];
      final funde = <String>[];
      for (final datei in dartQuellen()) {
        final pfad = datei.path.replaceAll(r'\', '/');
        if (pfad.contains('/kern/lib/db/') ||
            pfad.contains('/kern/lib/befehle/')) {
          continue;
        }
        final zeilen = datei.readAsLinesSync();
        for (var i = 0; i < zeilen.length; i++) {
          for (final m in befehle) {
            if (zeilen[i].contains('.$m(')) funde.add('$pfad:${i + 1} $m');
          }
        }
      }
      expect(funde, isEmpty);
    });
  });
}

/// Was eine Schreibmethode der Datenbank ist.
enum _Art {
  /// Als Befehl umgesetzt (packages/kern/lib/befehle) – nur noch über
  /// `fuehreAus` erreichbar.
  befehl,

  /// Eine Änderung durch den Nutzer, die noch als Befehl umzusetzen ist.
  nutzer,

  /// Eine Änderung, an der Dateien hängen (Import, Sperren, Bearbeitungen
  /// mit gerechnetem Ergebnis). Wie sie sich abgleicht, entscheidet erst
  /// das Protokoll für Dateien.
  datei,

  /// Ergebnis einer Auswertung; geht später als Ergebnis eines Auftrags
  /// an den Server, nicht als Befehl.
  ergebnis,

  /// Gilt nur auf diesem Rechner: Ansicht, Schlüssel, Warteschlangen,
  /// Sicherungsstand, Reparaturen am Dateibestand.
  lokal,
}

/// Die Einordnung aller Schreibmethoden in packages/kern/lib/db/abfragen.
const _einordnung = <String, _Art>{
  // Aufnahmen
  'setFavorite': _Art.befehl,
  'setFavoriteBulk': _Art.befehl,
  'setRating': _Art.befehl,
  'setRatingBulk': _Art.befehl,
  'setColorLabel': _Art.befehl,
  'setColorLabelBulk': _Art.befehl,
  'setDescription': _Art.befehl,
  'setDescriptionBulk': _Art.befehl,
  'setzeMarkierungen': _Art.befehl,
  'setLocation': _Art.nutzer,
  'setLocationBulk': _Art.nutzer,
  'setFileCreatedAt': _Art.nutzer,
  'setFileCreatedAtBulk': _Art.nutzer,
  'setAufnahmezeitpunkt': _Art.nutzer,
  'setCameraMetadata': _Art.nutzer,
  'setAiCaptionVonHand': _Art.nutzer,
  'setzeGeschaetztesJahr': _Art.nutzer,
  'setOriginalFileName': _Art.nutzer,
  'moveToTrash': _Art.nutzer,
  'restoreFromTrash': _Art.nutzer,
  'deleteAssetRows': _Art.datei,
  'insertAsset': _Art.datei,
  'setEditedAssetFile': _Art.datei,
  // Schlagwörter, Alben, Suchen
  'tagAsset': _Art.befehl,
  'tagAssetById': _Art.befehl,
  'tagAssetsBulk': _Art.befehl,
  'untagAsset': _Art.befehl,
  'nimmSchlagwortAb': _Art.befehl,
  'nimmKiTagsZurueck': _Art.befehl,
  'ensureTag': _Art.nutzer,
  'createAlbum': _Art.befehl,
  'addAssetsToAlbum': _Art.befehl,
  'removeAssetFromAlbum': _Art.befehl,
  'nimmAusAlbum': _Art.befehl,
  'setzeAlbumTitelbild': _Art.befehl,
  'createSavedSearch': _Art.befehl,
  'deleteSavedSearch': _Art.befehl,
  'addAiTagTerm': _Art.befehl,
  'removeAiTagTerm': _Art.befehl,
  'uebersetzeVokabular': _Art.befehl,
  // Duplikate und Serien
  'fuehreDuplikateZusammen': _Art.nutzer,
  'hebeDuplikatgruppeAuf': _Art.nutzer,
  'ignoriereDuplikatgruppe': _Art.nutzer,
  'loescheDuplikatAusnahmen': _Art.nutzer,
  'createStack': _Art.nutzer,
  'unstackAssets': _Art.nutzer,
  'verwirfSerienvorschlag': _Art.nutzer,
  // Vorschläge, Erinnerungen, Orte
  'verwirfDokumentvorschlaege': _Art.nutzer,
  'verwirfOrtsvorschlag': _Art.nutzer,
  'uebernimmOrtsvorschlag': _Art.nutzer,
  'merkeErinnerung': _Art.nutzer,
  'vergissErinnerung': _Art.nutzer,
  'setzeOrtsmarke': _Art.nutzer,
  'loescheOrtsmarke': _Art.nutzer,
  'setzeOrte': _Art.nutzer,
  // Personen und Gesichter
  'createPerson': _Art.nutzer,
  'assignFacesToPerson': _Art.nutzer,
  'mergePeople': _Art.nutzer,
  'setPersonCover': _Art.nutzer,
  'setFacesIgnored': _Art.nutzer,
  'loescheAlleUnbenanntenErkennungen': _Art.nutzer,
  'loescheGesicht': _Art.nutzer,
  'loeseZuordnung': _Art.nutzer,
  'nimmZuordnungZurueck': _Art.nutzer,
  'merkeGesichtsEntscheidungen': _Art.nutzer,
  'vergissGesichtsEntscheidungen': _Art.nutzer,
  'verwirfVorschlaege': _Art.nutzer,
  'setzeGesichtssucheAusgenommen': _Art.nutzer,
  'insertFace': _Art.nutzer,
  // Stammbaum
  'setzeGeschlecht': _Art.nutzer,
  'setzeLebensdaten': _Art.nutzer,
  'setzeEreignisort': _Art.nutzer,
  'aendereElternart': _Art.nutzer,
  'entferneBeziehung': _Art.nutzer,
  'fuegeBeziehungHinzu': _Art.nutzer,
  'fuegeBeziehungenHinzu': _Art.nutzer,
  'fuegeEreignisHinzu': _Art.nutzer,
  'loescheEreignis': _Art.nutzer,
  'uebernehmeGedcom': _Art.nutzer,
  // Reisen, Aktivitäten, Spuren
  'reiseAnlegen': _Art.nutzer,
  'reiseAendern': _Art.nutzer,
  'reiseLoeschen': _Art.nutzer,
  'reisenZusammenfuehren': _Art.nutzer,
  'setzeReisetagnotiz': _Art.nutzer,
  'setzeReiseart': _Art.nutzer,
  'aufnahmeAusReise': _Art.nutzer,
  'aufnahmenZurReise': _Art.nutzer,
  'setzeAufnahmenDerReise': _Art.nutzer,
  'verwirfReisevorschlag': _Art.nutzer,
  'aktivitaetAnlegen': _Art.nutzer,
  'aktivitaetAendern': _Art.nutzer,
  'aktivitaetLoeschen': _Art.nutzer,
  'setzeAufnahmenDerAktivitaet': _Art.nutzer,
  'verwirfAktivitaetsvorschlag': _Art.nutzer,
  'spurAnlegen': _Art.nutzer,
  'spurAendern': _Art.nutzer,
  'spurLoeschen': _Art.nutzer,
  // Bearbeiten: Einstellungen sind Befehle, das gerechnete Bild eine Datei
  'resetDevelopSettings': _Art.nutzer,
  'saveDevelopResult': _Art.datei,
  'createDevelopMask': _Art.datei,
  'updateDevelopMaskShape': _Art.datei,
  'updateDevelopMaskAdjustments': _Art.nutzer,
  'deleteDevelopMask': _Art.datei,
  'saveVideoTrim': _Art.datei,
  'resetVideoTrim': _Art.datei,
  // Vorgaben der Bibliothek
  'upsertAutomationRule': _Art.nutzer,
  'deleteAutomationRule': _Art.nutzer,
  'setAutomationRuleTags': _Art.nutzer,
  'upsertCameraPreset': _Art.nutzer,
  'deleteCameraPreset': _Art.nutzer,
  'setCameraPresetTags': _Art.nutzer,
  'upsertDevelopPreset': _Art.nutzer,
  'deleteDevelopPreset': _Art.nutzer,
  'upsertExportPreset': _Art.nutzer,
  'deleteExportPreset': _Art.nutzer,
  'setTrashAutoDeleteConfig': _Art.nutzer,
  'setFaceSimilarityThreshold': _Art.nutzer,
  'setAutoAnalyzeAfterImport': _Art.nutzer,
  'setzeUebersetzeSucheUndTags': _Art.nutzer,
  'setzeUebersetzeBeschreibungen': _Art.nutzer,
  // Gesperrter Ordner: Inhalte werden auf dem Gerät verschlüsselt
  'setAssetsLocked': _Art.datei,
  'hidePrivateMetadata': _Art.datei,
  'restorePrivateMetadata': _Art.datei,
  'setProtectPrivateMetadata': _Art.nutzer,
  'verlegeProfilbilderVon': _Art.datei,
  // Ergebnisse der Auswertungen
  'saveEmbedding': _Art.ergebnis,
  'setzeVideoeinbettungen': _Art.ergebnis,
  'markVideobilderGeprueft': _Art.ergebnis,
  'markAiTagsScanned': _Art.ergebnis,
  'setAiCaption': _Art.ergebnis,
  'setAiCaptionDe': _Art.ergebnis,
  'setOcrResult': _Art.ergebnis,
  'setTranskript': _Art.ergebnis,
  'setSharpnessScore': _Art.ergebnis,
  'setLocationNames': _Art.ergebnis,
  'setLocationNamesBulk': _Art.ergebnis,
  'markDatumGeprueft': _Art.ergebnis,
  'markGpsGeprueft': _Art.ergebnis,
  'uebernimmFotoangabenFuerBewegtbild': _Art.ergebnis,
  'uebernimmVideoangaben': _Art.ergebnis,
  'setzeEreignisorte': _Art.ergebnis,
  'merkeVorschlaege': _Art.ergebnis,
  'setzeGesichtsschaerfe': _Art.ergebnis,
  'setzeGesichtsausschnitt': _Art.ergebnis,
  'deleteUnassignedFacesForAsset': _Art.ergebnis,
  'markFacesScanned': _Art.ergebnis,
  'linkAssets': _Art.ergebnis,
  'setzeDateiart': _Art.ergebnis,
  'updateThumbnailInfo': _Art.ergebnis,
  'clearDerivedContentData': _Art.ergebnis,
  'wanderpunkteFuer': _Art.ergebnis,
  // Nur dieser Rechner
  'setSprache': _Art.lokal,
  'setThemeMode': _Art.lokal,
  'setzeSchwebeVorschau': _Art.lokal,
  'setzeCartoSchluesselWert': _Art.lokal,
  'setzeEigeneKarteWert': _Art.lokal,
  'setzeGelaendeKarte': _Art.lokal,
  'setzeGelaendeStimmung': _Art.lokal,
  'setzeKarteHochaufloesend': _Art.lokal,
  'setzeKartenansicht': _Art.lokal,
  'setzeLebensbaum': _Art.lokal,
  'setzeStammbaumZuletzt': _Art.lokal,
  'setzeListenspalten': _Art.lokal,
  'setzeZeitleisteForm': _Art.lokal,
  'setzeZeitleisteKachelstufe': _Art.lokal,
  'setzeZeitleisteMitTagen': _Art.lokal,
  'setzeZeitleisteSortierung': _Art.lokal,
  'setzeMaxGleichzeitigeAufgaben': _Art.lokal,
  'setzeUeberwachtenOrdner': _Art.lokal,
  'setLastTrashPurgeAt': _Art.lokal,
  'merkeAufgabenlauf': _Art.lokal,
  'saveVaultKey': _Art.lokal,
  'clearVaultKey': _Art.lokal,
  'saveBackupKey': _Art.lokal,
  'clearBackupKey': _Art.lokal,
  'insertBackupRecord': _Art.lokal,
  'markBackedUp': _Art.lokal,
  'markAutoBackedUp': _Art.lokal,
  'setAutoBackupConfig': _Art.lokal,
  'setAutoBackupMaxMbPerRun': _Art.lokal,
  'setLastAutoBackupAt': _Art.lokal,
  'clearAutoBackupDestination': _Art.lokal,
  'createRestoreJob': _Art.lokal,
  'completeRestoreJob': _Art.lokal,
  'deleteRestoreJob': _Art.lokal,
  'markRestoreJobStatus': _Art.lokal,
  'requeueRestoreJob': _Art.lokal,
  'resetStuckRunningRestoreJobs': _Art.lokal,
  'updateRestoreJobProgress': _Art.lokal,
  'clearMissingDevelopedPath': _Art.lokal,
  'clearMissingFaceCropPath': _Art.lokal,
  'clearMissingPreviewPath': _Art.lokal,
  'clearMissingRestoredPath': _Art.lokal,
  'clearMissingThumbnailPath': _Art.lokal,
  'clearMissingTrimmedPath': _Art.lokal,
};

/// Die öffentlichen Methoden der Abfrage-Erweiterungen, die schreiben.
///
/// Gelesen wird der Quelltext: Kopf einer Methode auf der ersten
/// Einrückungsstufe, ihr Rumpf bis zum nächsten Kopf, und darin ein
/// schreibender Aufruf von drift.
Set<String> _schreibmethoden() {
  final kopf = RegExp(
    r'^  (?:Future<[^\n]*?>|Stream<[^\n]*?>|void|int|bool|String\??|'
    r'[A-Z][A-Za-z<>?, ]*)\s+([a-z][A-Za-z0-9]*)\s*\(',
    multiLine: true,
  );
  final schreibt = RegExp(
    r'\b(update|into|delete|customStatement|customUpdate|customInsert|batch|'
    r'transaction|insertOnConflictUpdate|replace|write)\(',
  );
  final namen = <String>{};
  final dateien = [
    ...Directory('packages/kern/lib/db/abfragen').listSync().whereType<File>(),
    File('packages/kern/lib/db/database.dart'),
  ].where((f) => f.path.endsWith('.dart'));
  for (final datei in dateien) {
    final text = datei.readAsStringSync();
    final koepfe = kopf.allMatches(text).toList();
    for (var i = 0; i < koepfe.length; i++) {
      final name = koepfe[i].group(1)!;
      if (name.startsWith('watch')) continue;
      final ende = i + 1 < koepfe.length ? koepfe[i + 1].start : text.length;
      if (schreibt.hasMatch(text.substring(koepfe[i].end, ende))) {
        namen.add(name);
      }
    }
  }
  return namen;
}

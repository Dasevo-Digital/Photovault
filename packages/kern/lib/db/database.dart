import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:drift/native.dart';
// Nur fuer den Typ der Verbindung in [AppDatabase.bereiteVerbindungVor].
import 'package:sqlite3/sqlite3.dart' show Database;
import 'package:path/path.dart' as p;

import '../services/ki_vokabular_vorgabe.dart' show defaultAiTagVocabulary;
import '../services/aktivitaeten.dart' show istBekannteArt;
import '../services/embedding_codec.dart';
import '../services/embedding_similarity.dart' show duplikatPaarSchluessel;
import '../services/exif_camera.dart';
import '../services/face_threshold.dart';
import '../services/gelaendeebenen.dart';
import '../services/library_stats.dart';
import '../services/tageszeit.dart';
import '../services/reisen.dart' show Reiseart, reiseartVorgabe;
import '../services/listenspalten.dart';
import '../services/ortsvorschlag.dart' show Ortsloser, Ortsnachbar;
import 'rasterzeile.dart';
import '../services/rasterstufen.dart'
    show
        zeitleisteKachelstufeVorgabe,
        zeitleisteFormVorgabe,
        zeitleisteForm,
        Zeitleistenform;
import '../services/raw_formats.dart' show rawImageExtensions;
import '../services/search_filters.dart';
import '../services/sortierung.dart'
    show
        Rastersortierung,
        rastersortierung,
        rastersortierungVorgabe,
        sortierungSql;
import '../services/stammbaum.dart';
import '../services/verwandtschaftsgrad.dart';
import '../services/videostandbilder.dart'
    show videoZweitblickAb, videostandbildstellen;
import '../services/xmp_regionen.dart';
import '../services/eigenkarte.dart';

// **Aufbau (#85).** Diese Bibliothek ist auf Teildateien verteilt: die
// Tabellen unter tabellen/, die Schritte der Migration in migration.dart,
// die Abfragen nach Themen unter abfragen/ – dort als Erweiterungen
// (`extension … on AppDatabase`). In der Klasse selbst bleibt nur, was
// überschrieben wird oder statisch ist. Drei Methoden stehen deshalb dort
// und nicht bei ihrem Thema: insertAsset, assetsByIds und
// autoAnalyzeAfterImportEnabled. Tests überschreiben sie, und eine
// Erweiterung lässt sich nicht überschreiben.
//
// Eine Folge für Aufrufer: Eine Abfrage ist nur sichtbar, wo diese Datei
// importiert ist. Meldet der Analyzer „The method … isn't defined for the
// type 'AppDatabase'“, fehlt `import '…/db/database.dart';`.
part 'database.g.dart';
part 'tabellen/aufnahmen.dart';
part 'tabellen/alben_und_tags.dart';
part 'tabellen/bearbeitung.dart';
part 'tabellen/personen.dart';
part 'tabellen/orte.dart';
part 'tabellen/einstellungen.dart';
part 'migration.dart';
part 'abfragen/aufnahmen.dart';
part 'abfragen/auswahl_und_papierkorb.dart';
part 'abfragen/einstellungen.dart';
part 'abfragen/nachtraege.dart';
part 'abfragen/auswertungen.dart';
part 'abfragen/orte_und_erinnerungen.dart';
part 'abfragen/serien.dart';
part 'abfragen/bearbeitung.dart';
part 'abfragen/alben_und_tags.dart';
part 'abfragen/vorgaben.dart';
part 'abfragen/ki_vokabular.dart';
part 'abfragen/suchen.dart';
part 'abfragen/personen.dart';
part 'abfragen/stammbaum.dart';
part 'abfragen/reisen.dart';
part 'abfragen/aktivitaeten.dart';
part 'abfragen/spuren.dart';
part 'abfragen/einbettungen.dart';
part 'abfragen/sicherung.dart';
part 'abfragen/gesperrter_ordner.dart';

class _SperrWiederholung extends QueryInterceptor {
  Future<T> _wiederhole<T>(Future<T> Function() arbeit) async {
    final uhr = Stopwatch()..start();
    while (true) {
      try {
        return await arbeit();
      } catch (e, stack) {
        if (!_istSperre(e) ||
            uhr.elapsedMilliseconds >= AppDatabase.sperrwartezeitMs) {
          Error.throwWithStackTrace(e, stack);
        }
        final rest = AppDatabase.sperrwartezeitMs - uhr.elapsedMilliseconds;
        await Future<void>.delayed(Duration(milliseconds: rest.clamp(1, 40)));
      }
    }
  }

  // Fehler eines Hintergrund-Isolats können von Drift als entferntes
  // Fehlerobjekt zurückkommen. Dann bleibt der SQLite-Code in der stabilen
  // Textdarstellung erhalten, auch wenn der konkrete Dart-Typ verloren ist.
  bool _istSperre(Object fehler) {
    if (fehler is SqliteException) {
      return fehler.resultCode == 5 || fehler.resultCode == 6;
    }
    final fund = RegExp(r'^SqliteException\((\d+)\):').firstMatch('$fehler');
    final code = fund == null ? null : int.tryParse(fund.group(1)!);
    return code != null && (code & 0xff == 5 || code & 0xff == 6);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _wiederhole(() => executor.runBatched(statements));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _wiederhole(() => executor.runCustom(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _wiederhole(() => executor.runInsert(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _wiederhole(() => executor.runDelete(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _wiederhole(() => executor.runUpdate(statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _wiederhole(() => executor.runSelect(statement, args));
}

@DriftDatabase(
  tables: [
    Assets,
    Albums,
    AlbumAssets,
    Tags,
    AssetTags,
    People,
    Faces,
    FaceMatchFeedback,
    ImageEmbeddings,
    BackupRecords,
    PrivacySettings,
    BackupSettings,
    SavedSearches,
    TrashSettings,
    DuplikatAusnahmen,
    CameraPresets,
    CameraPresetTags,
    DevelopSettings,
    DevelopHistory,
    VideoTrims,
    DevelopMasks,
    RestoreJobs,
    AppSettings,
    AiTagVocabulary,
    AutomationRules,
    AutomationRuleTags,
    DevelopPresets,
    ExportPresets,
    PersonBeziehungen,
    Lebensereignisse,
    Reisen,
    ReiseAufnahmen,
    Reisetagnotizen,
    VerworfeneReisen,
    Ortsmarken,
    Aktivitaeten,
    AktivitaetAufnahmen,
    VerworfeneAktivitaeten,
    Spuren,
    Spurpunkte,
    VerworfeneSerien,
    VerworfeneOrtsvorschlaege,
    Videoeinbettungen,
    Wanderpunkte,
    Wanderabfragen,
    VerworfeneDokumente,
    GemerkteErinnerungen,
    Aufgabenlaeufe,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Wird bei jeder Mutation erhöht, die das Ergebnis von [allEmbeddings]
  /// verändern könnte (neues/aktualisiertes Embedding, Papierkorb/
  /// Wiederherstellen, endgültiges Löschen, Sperren/Entsperren) – LibraryState
  /// nutzt das als billigen "ist mein gecachtes allEmbeddings()-Ergebnis noch
  /// aktuell?"-Check, ohne bei jeder Suche erneut alle Embeddings (oft
  /// hunderte MB bei großen Bibliotheken) aus der DB laden zu müssen.
  int _embeddingsGeneration = 0;
  int get embeddingsGeneration => _embeddingsGeneration;

  @override
  int get schemaVersion => 92;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPerformanceIndices(m);
      await _createIndicesV14(m);
      await _createIndicesV48(m);
      await _createIndicesV51(m);
      await _createIndicesV54(m);
      await _createIndicesV55(m);
      await _createAssetSearchFts();
      await _seedAiTagVocabulary();
    },
    // Die Schritte stehen in [Migrationsschritte.stufeAuf].
    onUpgrade: (m, from, to) => stufeAuf(m, from, to),
  );

  /// Öffnet (bzw. legt beim ersten Start an) die SQLite-Datei der
  /// Bibliothek in [libraryRoot].
  ///
  /// Wo die Bibliothek liegt, weiss die App (`LibraryLocation`), nicht die
  /// Datenbank – so öffnet ein Server seine Bibliotheken auf demselben Weg.
  static Future<AppDatabase> open(Directory libraryRoot) async {
    await libraryRoot.create(recursive: true);
    final dbFile = File(p.join(libraryRoot.path, 'library.sqlite'));
    return AppDatabase(
      mitSperrwartezeit(
        NativeDatabase.createInBackground(dbFile, setup: bereiteVerbindungVor),
      ),
    );
  }

  /// Ergänzt SQLites native Wartezeit um Wiederholungen für Plattformen, auf
  /// denen der gebündelte Treiber `busy_timeout` bei einzelnen Sperrarten
  /// vorzeitig mit `SQLITE_BUSY` oder `SQLITE_LOCKED` beendet.
  static QueryExecutor mitSperrwartezeit(QueryExecutor executor) =>
      executor.interceptWith(_SperrWiederholung());

  /// Wie lange auf eine belegte Datenbank gewartet wird, bevor
  /// aufgegeben wird.
  ///
  /// **SQLites Vorgabe ist null** – wer auf eine gesperrte Datei trifft,
  /// bekommt sofort „database is locked" und keinen zweiten Versuch. Das
  /// ist so lange folgenlos, wie genau ein Prozess die Datei anfasst, und
  /// genau das ist nicht zugesichert: Nichts in diesem Programm hindert
  /// jemanden daran, es zweimal zu starten (auf dem Windows-Prüfrechner
  /// liefen zwei Fassungen stundenlang nebeneinander), und ein
  /// Sicherungsdienst, ein Synchronisationsordner oder ein Blick mit dem
  /// `sqlite3`-Werkzeug halten die Sperre ebenfalls kurz.
  ///
  /// Gemessen an zwei Prozessen, die gleichzeitig 400 Zeilen schreiben:
  ///
  /// ```
  /// ohne Wartezeit    734 von 800 Schreibvorgängen scheitern
  /// 5 Sekunden          0 von 800, zusammen 170 ms
  /// ```
  ///
  /// Fünf Sekunden sind lang genug für jede Schreibfolge, die dieses
  /// Programm kennt, und kurz genug, dass eine wirklich klemmende
  /// Datenbank nicht als Aufhänger erscheint.
  static const int sperrwartezeitMs = 5000;

  /// Was an jeder frisch geöffneten Verbindung eingestellt gehört.
  ///
  /// Öffentlich, damit die Prüfstände dieselbe Einstellung bekommen wie
  /// der Betrieb – eine Einstellung, die nur im Betrieb gilt, ist eine,
  /// die nie geprüft wird.
  static void bereiteVerbindungVor(Database db) {
    db.execute('PRAGMA busy_timeout = $sperrwartezeitMs');
  }

  // -----------------------------------------------------------------------
  // Assets / Timeline
  // -----------------------------------------------------------------------

  Future<void> insertAsset(AssetsCompanion asset) => into(assets).insert(asset);

  Future<List<AssetData>> assetsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await (select(assets)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    // Reihenfolge der übergebenen IDs beibehalten (z.B. Ranking nach Ähnlichkeit).
    return ids.map((id) => byId[id]).whereType<AssetData>().toList();
  }

  // ---------------------------------------------------------------------
  // Datenströme, die einen Schwall aushalten
  // ---------------------------------------------------------------------

  /// Wie viel Zeit zwischen zwei Durchläufen derselben Abfrage mindestens
  /// liegt, wenn die Änderungen nicht aufhören.
  ///
  /// Nicht kürzer, weil sonst wenig gespart wäre; nicht länger, weil ein
  /// Hintergrundlauf sonst zu lange ein veraltetes Raster stehen liesse.
  @visibleForTesting
  static const drosselfenster = Duration(milliseconds: 400);

  Future<bool> autoAnalyzeAfterImportEnabled() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.autoAnalyzeAfterImport ?? true;
  }
}

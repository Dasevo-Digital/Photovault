import 'dart:io';

import 'package:drift/native.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/herkunft.dart';
import 'package:kern/auswertung/rechenhilfe.dart' show Vergabe;
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/nachbearbeitung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/model_processing_state.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:path/path.dart' as p;

import 'onnx_ffi.dart';

/// Eine Bibliothek auf dem Server: dieselbe Ablage wie in der App
/// (`library.sqlite` und darunter `library/`), nur ohne Oberfläche.
class Bibliothek {
  Bibliothek._(
    this.ordner,
    this.db,
    this.pfade,
    this.importe,
    this.modelle,
    this.bildwerkzeuge,
    ReverseGeocoder? ortsverzeichnis,
    this.protokoll,
    Vergabe? vergabe,
  ) {
    // Gelöschte Erkennungen: Die Zeile nimmt der Befehl, den Ausschnitt
    // räumt der Server hier auf – Geräte schicken nur den Befehl (#191).
    db.befehlsbeobachter.add((befehl) {
      final weg = switch (befehl) {
        GesichtLoeschen(:final gesichtId) => [gesichtId],
        GesichterLoeschen(:final gesichtIds) => gesichtIds,
        _ => const <String>[],
      };
      for (final id in weg) {
        final datei = pfade.absolute(pfade.faceRelativePath(id));
        datei.delete().catchError((Object _) => datei);
      }
    });
    final modellstand = ModelProcessingState(pfade.modelProcessingStateFile);
    auswertungen = Auswertungen(
      db: db,
      paths: pfade,
      modelle: modelle,
      bildwerkzeuge: bildwerkzeuge,
      abgebrochen: () => auswertungAbbrechen,
      vergabe: vergabe,
      // Die Herkunft jedes Ergebnisses: der Server, und je Modell, ob es
      // auf dem Beschleuniger rechnete (siehe FfiOnnxPlattform).
      rechner: Rechner.server(
        (datei) => switch (OnnxRuntimePlatform.instance) {
          final FfiOnnxPlattform f => f.anbieterFuer(datei),
          _ => 'CPU',
        },
      ),
      pipelineAktuell: (pipeline) async {
        final abdruck = ModelProcessingState.currentFingerprints()[pipeline];
        if (abdruck != null) await modellstand.markCurrent(pipeline, abdruck);
      },
    );
    nachbearbeitung = Nachbearbeitung(
      db: db,
      paths: pfade,
      importe: () => importe,
      auswertungen: auswertungen,
      ortsverzeichnis: () => ortsverzeichnis,
    );
  }

  /// Öffnet die Bibliothek in [ordner] oder legt sie an.
  ///
  /// Anders als die App mit Write-Ahead-Log: Auf dem Server lesen mehrere
  /// Anfragen, während eine schreibt, und im WAL warten Lesende nicht auf
  /// den Schreiber.
  ///
  /// [modelle] teilen sich alle Bibliotheken eines Servers – ein Modell
  /// liegt nur einmal im Speicher, gleich für wen es rechnet. Ohne Angabe
  /// sind keine eingerichtet, und die Auswertungen überspringen alles, was
  /// ein Modell braucht.
  static Future<Bibliothek> oeffne(
    Directory ordner, {
    Bildwerkzeuge bildwerkzeuge = const WerkzeugBildwerkzeuge(),
    Modelle? modelle,
    ReverseGeocoder? ortsverzeichnis,
    Vergabe? vergabe,
  }) async {
    await ordner.create(recursive: true);
    final db = AppDatabase(
      AppDatabase.mitSperrwartezeit(
        NativeDatabase.createInBackground(
          File(p.join(ordner.path, 'library.sqlite')),
          setup: (verbindung) {
            AppDatabase.bereiteVerbindungVor(verbindung);
            verbindung.execute('PRAGMA journal_mode = WAL');
          },
        ),
      ),
    );
    final pfade = await StoragePaths.oeffne(
      Directory(p.join(ordner.path, 'library')),
    );
    // Jede Änderung mitschreiben – für die verbundenen Geräte (Stufe 2).
    // Neu bei jedem Öffnen: Eine Migration kann Tabellen neu angelegt und
    // ihre Trigger mitgenommen haben.
    final protokoll = Protokoll(db);
    await protokoll.richteEin(mitschreiben: -1);
    await protokoll.verdichte();
    // Welche Befehle schon ausgeführt sind – damit ein Gerät, dessen
    // Antwort verloren ging, denselben Befehl gefahrlos noch einmal
    // schicken kann.
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_erledigt ('
      'kennung TEXT PRIMARY KEY, stand INTEGER NOT NULL, am INTEGER NOT NULL)',
    );
    return Bibliothek._(
      ordner,
      db,
      pfade,
      ImportService(db, pfade, bildwerkzeuge: bildwerkzeuge),
      modelle ?? Modelle(),
      bildwerkzeuge,
      ortsverzeichnis,
      protokoll,
      vergabe,
    );
  }

  final Directory ordner;
  final AppDatabase db;
  final StoragePaths pfade;
  final ImportService importe;
  final Modelle modelle;

  /// Wandelt Bilder – für Vorschauen, die Auswertungen und das Herunterladen
  /// als JPEG (#210).
  final Bildwerkzeuge bildwerkzeuge;
  final Protokoll protokoll;
  late final Auswertungen auswertungen;
  late final Nachbearbeitung nachbearbeitung;

  /// Gesetzt, wenn die laufende Auswertung nach der aktuellen Aufnahme
  /// aufhören soll (siehe Auswertungsdienst).
  bool auswertungAbbrechen = false;

  /// Die Kennung der Aufnahme mit dieser Prüfsumme – für Dubletten, bei
  /// denen der Import nur „schon da“ meldet.
  Future<String?> kennungFuer(String pruefsumme) async =>
      (await (db.select(db.assets)
                ..where((t) => t.checksum.equals(pruefsumme))
                ..limit(1))
              .getSingleOrNull())
          ?.id;

  Future<void> schliesse() => db.close();
}

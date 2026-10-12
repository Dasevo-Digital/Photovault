import 'dart:io';

import 'package:drift/native.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/nachbearbeitung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/model_processing_state.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Eine Bibliothek auf dem Server: dieselbe Ablage wie in der App
/// (`library.sqlite` und darunter `library/`), nur ohne Oberfläche.
class Bibliothek {
  Bibliothek._(
    this.ordner,
    this.db,
    this.pfade,
    this.importe,
    this.modelle,
    Bildwerkzeuge bildwerkzeuge,
    ReverseGeocoder? ortsverzeichnis,
  ) {
    final modellstand = ModelProcessingState(pfade.modelProcessingStateFile);
    auswertungen = Auswertungen(
      db: db,
      paths: pfade,
      modelle: modelle,
      bildwerkzeuge: bildwerkzeuge,
      abgebrochen: () => auswertungAbbrechen,
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
    return Bibliothek._(
      ordner,
      db,
      pfade,
      ImportService(db, pfade, bildwerkzeuge: bildwerkzeuge),
      modelle ?? Modelle(),
      bildwerkzeuge,
      ortsverzeichnis,
    );
  }

  final Directory ordner;
  final AppDatabase db;
  final StoragePaths pfade;
  final ImportService importe;
  final Modelle modelle;
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

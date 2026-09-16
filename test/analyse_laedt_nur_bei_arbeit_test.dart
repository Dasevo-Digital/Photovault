import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/florence_captioning_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/eye_state_service.dart';
import 'package:photo_vault/services/face_engine_service.dart';
import 'package:photo_vault/services/modell_halter.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Hintergrundanalyse läuft bei jedem Programmstart automatisch an.
/// Lieh sie sich ihre Modelle, BEVOR sie nachsah, ob überhaupt Fotos offen
/// sind, belegte die App bei fertig ausgewerteter Bibliothek 1076 statt
/// 214 MB – ohne ein einziges Foto anzufassen. Damit war der Zweck des
/// bedarfsweisen Ladens für den Normalfall aufgehoben.
///
/// Dieser Test hält fest, dass keine Stufe ein Modell anfordert, solange es
/// nichts zu tun gibt.
void main() {
  test('ohne offene Fotos fordert keine Analysestufe ein Modell an', () async {
    final tempRoot = Directory.systemTemp.createTempSync('pv_lazy_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));

    // Jeder Ladeversuch wird vermerkt und schlägt dann fehl. Echte Modelle
    // gibt es im Test nicht (die ONNX-Anbindung läuft über einen
    // Plattformkanal) – gebraucht werden sie hier auch nicht, denn erwartet
    // wird ja gerade, dass NICHT geladen wird. Dass die Stufen den Fehler
    // ihrerseits abfangen, ist gewollt und ändert am Vermerk nichts.
    final versuche = <String>[];
    ModellHalter<T> falle<T>(String name) => ModellHalter<T>(
          name: name,
          installiert: true,
          laden: () async {
            versuche.add(name);
            throw StateError('$name hätte nicht geladen werden dürfen');
          },
          entsorgen: (_) async {},
        );

    final lib = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths)
      ..faceEngineHalter = falle<FaceEngineService>('Gesichter')
      ..eyeStateHalter = falle<EyeStateService>('Augen')
      ..clipBildHalter = falle<ClipService>('CLIP-Bild')
      ..clipTextHalter = falle<ClipService>('CLIP-Text')
      ..captioningHalter = falle<FlorenceCaptioningService>('Bildbeschreibung');

    // Leere Bibliothek: keine Stufe hat etwas zu tun.
    await lib.starteHintergrundanalyse();

    expect(versuche, isEmpty,
        reason: 'ohne offene Fotos darf kein Modell in den Speicher – '
            'angefordert wurde aber: ${versuche.join(", ")}');
  });

  /// **„Gescannt" darf nur dastehen, wenn hingesehen wurde.**
  ///
  /// Bis Fassung 2.5 setzte `_scanFacesForDecodedAsset` den Vermerk auch
  /// dann, wenn sich das Foto gar nicht dekodieren liess – der Aufruf
  /// stand ausserhalb der `decoded != null`-Prüfung. Danach ging der Modus
  /// „nur Fehlende" für immer daran vorbei, samt Hintergrundanalyse. Ein
  /// Lauf, der an beschädigten Dateien vorbeirauscht und „fertig" meldet,
  /// ist genau die Art Ergebnis, der man nicht ansieht, dass sie keines
  /// ist.
  ///
  /// Ein Prüfstand mit echter Erkennung geht hier nicht – die braucht das
  /// YuNet-Modell, das im Prüflauf nicht liegt. Also wird der Quelltext
  /// gelesen: Der frühe Ausstieg muss VOR jedem Schreibvorgang stehen.
  test('ohne dekodiertes Bild wird nichts vermerkt', () {
    final quelle = File('lib/state/library_state.dart').readAsStringSync();
    final von = quelle.indexOf('Future<void> _scanFacesForDecodedAsset(');
    expect(von, greaterThan(0), reason: 'Methode umbenannt? Dann hier mit.');
    final bis = quelle.indexOf('\n  Future<', von + 10);
    final rumpf = quelle.substring(von, bis);

    final ausstieg = rumpf.indexOf('if (decoded == null) return;');
    expect(ausstieg, greaterThan(0),
        reason: 'der frühe Ausstieg fehlt – ein nicht dekodierbares Foto '
            'würde wieder als gescannt vermerkt');
    for (final schreibt in [
      'db.markFacesScanned',
      'db.insertFace',
      'db.deleteUnassignedFacesForAsset',
    ]) {
      expect(rumpf.indexOf(schreibt), greaterThan(ausstieg),
          reason: '$schreibt steht vor dem Ausstieg');
    }
  });
}

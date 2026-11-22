import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/face_engine_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Die Auswertung rechnet mit dem Stand vom Beginn ihres Laufs. Wird ein
/// Foto zwischen Dekodieren und Ablegen gesperrt, gelöscht oder in den
/// Papierkorb gelegt, legt sie nichts mehr ab (#430): kein Ausschnitt im
/// Klartext im gesperrten Foto – an dem jedes spätere Entsperren scheiterte
/// –, keine Einbettung in der Datenbank, die das Sperren gerade geleert hat.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_auswertung_gesperrt_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..klartextOrdnerFuerTests = Directory(p.join(temp.path, 'klartext'));
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<AssetData> foto() async {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(180, 120, 90));
    final f = File(p.join(temp.path, 'foto.jpg'))
      ..writeAsBytesSync(img.encodeJpg(bild));
    final r = await ImportService(
      db,
      paths,
      bildwerkzeuge: const KeineBildwerkzeuge(),
    ).importFile(f.path);
    return (await db.assetById(r.assetId!))!;
  }

  List<File> ausschnitte() =>
      paths.facesDir.listSync(recursive: true).whereType<File>().toList();

  test('Gesichtsausschnitte kommen nicht in ein inzwischen gesperrtes Foto, '
      'es lässt sich wieder entsperren', () async {
    final asset = await foto();
    await library.setupVaultPin('1234');
    final engine = _Gesichter();
    library.faceEngineHalter = ModellHalter<FaceEngineService>(
      name: 'Gesichter',
      installiert: true,
      laden: () async => engine,
      entsorgen: (_) async {},
    );

    final lauf = library.rescanFaces(onlyNewPhotos: true).toList();
    // Das Foto ist dekodiert, die Erkennung rechnet – jetzt wird gesperrt.
    await engine.begonnen.future;
    await library.lockAsset(asset);
    engine.weiter.complete();
    await lauf;

    expect(await db.facesForAsset(asset.id), isEmpty);
    expect(
      ausschnitte(),
      isEmpty,
      reason: 'bisher lag der Ausschnitt im Klartext im gesperrten Foto',
    );
    await library.unlockAsset((await db.assetById(asset.id))!);
    expect((await db.assetById(asset.id))!.isLocked, isFalse);
    expect(
      (await db.assetById(asset.id))!.facesScanned,
      isFalse,
      reason: 'nichts vermerkt: der nächste Lauf sieht es wieder',
    );
  });

  test('keine Einbettung für ein inzwischen gesperrtes Foto', () async {
    final asset = await foto();
    await library.setupVaultPin('1234');
    final clip = _Clip();
    library.clipBildHalter = ModellHalter<ClipService>(
      name: 'CLIP',
      installiert: true,
      laden: () async => clip,
      entsorgen: (_) async {},
    );

    final lauf = library.auswertungen.backfillClipEmbeddings().toList();
    await clip.begonnen.future;
    await library.lockAsset(asset);
    clip.weiter.complete();
    await lauf;

    expect(
      await db.embeddingForAsset(asset.id),
      isNull,
      reason: 'das Sperren hatte die Einbettungen gerade gelöscht',
    );
  });

  test('ein Ergebnis eines Rechners für ein Foto im Papierkorb wird '
      'verworfen', () async {
    // Der Weg des Servers: Dort gibt es kein Sperren, aber den Papierkorb –
    // und dessen Fotos wertet keine Stufe aus.
    final asset = await foto();
    final auswertungen = Auswertungen(db: db, paths: paths, modelle: Modelle());
    await db.fuehreAus(
      Befehl.ausJson({
        'art': 'inDenPapierkorb',
        'werte': {
          'ids': [asset.id],
        },
      }),
    );

    await auswertungen.trageEin(
      Rechenauftrag(
        id: 'a1',
        art: Rechenart.bildanalyse,
        aufnahme: asset.id,
        datei: asset.relativePath,
      ),
      Rechenergebnis(
        clip: Float32List.fromList([0.1, 0.2, 0.3]),
        gesichter: [
          Gesichtsfund(
            x: 0.2,
            y: 0.2,
            breite: 0.3,
            hoehe: 0.3,
            schaerfe: 1,
            ausschnitt: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      ),
    );

    expect(await db.facesForAsset(asset.id), isEmpty);
    expect(ausschnitte(), isEmpty);
    expect(await db.embeddingForAsset(asset.id), isNull);

    // Ein offenes Foto bekommt sie wie bisher.
    final offen = await foto2(db, paths, temp);
    await auswertungen.trageEin(
      Rechenauftrag(
        id: 'a2',
        art: Rechenart.bildanalyse,
        aufnahme: offen.id,
        datei: offen.relativePath,
      ),
      Rechenergebnis(clip: Float32List.fromList([0.1, 0.2, 0.3])),
    );
    expect(await db.embeddingForAsset(offen.id), isNotNull);
  });
}

Future<AssetData> foto2(
  AppDatabase db,
  StoragePaths paths,
  Directory temp,
) async {
  final bild = img.Image(width: 64, height: 48);
  img.fill(bild, color: img.ColorRgb8(20, 200, 90));
  final f = File(p.join(temp.path, 'foto2.jpg'))
    ..writeAsBytesSync(img.encodeJpg(bild));
  final r = await ImportService(
    db,
    paths,
    bildwerkzeuge: const KeineBildwerkzeuge(),
  ).importFile(f.path);
  return (await db.assetById(r.assetId!))!;
}

/// Findet ein Gesicht – aber erst, wenn der Test es erlaubt.
class _Gesichter implements FaceEngineService {
  final begonnen = Completer<void>();
  final weiter = Completer<void>();

  @override
  bool get canEmbed => false;

  @override
  Future<List<DetectedFace>> detectFaces(
    img.Image decoded, {
    double scoreThreshold = 0.7,
  }) async {
    begonnen.complete();
    await weiter.future;
    return [DetectedFace(0.25, 0.25, 0.4, 0.4, 0.9)];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Rechnet eine Einbettung – aber erst, wenn der Test es erlaubt.
class _Clip implements ClipService {
  final begonnen = Completer<void>();
  final weiter = Completer<void>();

  @override
  Future<Float32List> embedImage(img.Image decoded) async {
    begonnen.complete();
    await weiter.future;
    return Float32List.fromList([0.5, 0.5, 0.5]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

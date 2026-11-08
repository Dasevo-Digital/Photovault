import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/removable_media_service.dart';

/// Prüft die Erkennung von Kameras/SD-Karten für "Von Kamera importieren":
/// [RemovableMediaService.detect] soll jeden eingehängten "Datenträger"
/// (hier: Unterordner eines temporären /Volumes-Ersatzes) mit einem
/// DCIM-Ordner finden, case-insensitiv, und alles andere ignorieren.
void main() {
  late Directory tempVolumes;

  setUp(() {
    tempVolumes = Directory.systemTemp.createTempSync(
      'photo_vault_volumes_test_',
    );
  });

  tearDown(() {
    if (tempVolumes.existsSync()) tempVolumes.deleteSync(recursive: true);
  });

  test('findet einen Datenträger mit DCIM-Ordner', () async {
    Directory(
      p.join(tempVolumes.path, 'EOS_DIGITAL', 'DCIM', '100CANON'),
    ).createSync(recursive: true);

    final sources = await RemovableMediaService(
      volumesPath: tempVolumes.path,
    ).detect();

    expect(sources, hasLength(1));
    expect(sources.single.name, 'EOS_DIGITAL');
    expect(
      sources.single.dcimPath,
      p.join(tempVolumes.path, 'EOS_DIGITAL', 'DCIM'),
    );
  });

  test('erkennt DCIM case-insensitiv', () async {
    Directory(
      p.join(tempVolumes.path, 'SDCARD', 'dcim'),
    ).createSync(recursive: true);

    final sources = await RemovableMediaService(
      volumesPath: tempVolumes.path,
    ).detect();

    expect(sources, hasLength(1));
    expect(sources.single.dcimPath, p.join(tempVolumes.path, 'SDCARD', 'dcim'));
  });

  test('ignoriert Datenträger ohne DCIM-Ordner', () async {
    Directory(
      p.join(tempVolumes.path, 'Backup-Festplatte', 'Documents'),
    ).createSync(recursive: true);

    final sources = await RemovableMediaService(
      volumesPath: tempVolumes.path,
    ).detect();

    expect(sources, isEmpty);
  });

  test('findet mehrere gleichzeitig angeschlossene Datenträger', () async {
    Directory(
      p.join(tempVolumes.path, 'CameraA', 'DCIM'),
    ).createSync(recursive: true);
    Directory(
      p.join(tempVolumes.path, 'CameraB', 'DCIM'),
    ).createSync(recursive: true);
    Directory(
      p.join(tempVolumes.path, 'KeinFotoLaufwerk'),
    ).createSync(recursive: true);

    final sources = await RemovableMediaService(
      volumesPath: tempVolumes.path,
    ).detect();

    expect(sources.map((s) => s.name).toSet(), {'CameraA', 'CameraB'});
  });

  test(
    'liefert eine leere Liste, wenn das Wurzelverzeichnis gar nicht existiert',
    () async {
      final sources = await RemovableMediaService(
        volumesPath: p.join(tempVolumes.path, 'existiert-nicht'),
      ).detect();
      expect(sources, isEmpty);
    },
  );

  test('findet unter Linux Karten eine Ebene unter dem Nutzerordner', () async {
    // /media/<Nutzer>/<Karte> und /run/media/<Nutzer>/<Karte> wie bei den
    // Desktops, /media/<Karte> wie von Hand eingehängt.
    final media = p.join(tempVolumes.path, 'media');
    final runMedia = p.join(tempVolumes.path, 'run', 'media');
    Directory(
      p.join(media, 'nutzer', 'EOS_DIGITAL', 'DCIM'),
    ).createSync(recursive: true);
    Directory(
      p.join(runMedia, 'nutzer', 'NIKON', 'DCIM'),
    ).createSync(recursive: true);
    Directory(p.join(media, 'SDKARTE', 'DCIM')).createSync(recursive: true);

    final kandidaten = await RemovableMediaService.linuxKandidaten([
      media,
      runMedia,
    ]);
    final namen = kandidaten.map((k) => k.$1).toSet();
    expect(namen, containsAll(['EOS_DIGITAL', 'NIKON', 'SDKARTE']));
  });
}

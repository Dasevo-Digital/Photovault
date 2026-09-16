@Tags(['netz'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';

/// Einmalige Sonde: Laedt die KLEINEN Katalog-Eintraege ueber den echten
/// Weg der App herunter und meldet, woran es scheitert. Laeuft nicht in der
/// normalen Suite (Marke `netz`), sondern nur auf Zuruf:
///
///   flutter test --tags netz test/modell_download_probe_test.dart
void main() {
  test('alle Katalog-Eintraege laden ueber ModelDownloadService', () async {
    final ordner = await Directory.systemTemp.createTemp('modellsonde');
    final dienst = ModelDownloadService(ordner.path);

    // Der ganze Katalog: Es geht darum, WELCHER Eintrag scheitert.
    final eintraege = <ModelCatalogEntry>[...ModelCatalog.all];

    final fehler = <String>[];

    for (final eintrag in eintraege) {
      stdout.writeln('--- ${eintrag.id} (${eintrag.files.length} Dateien)');
      try {
        await for (final fortschritt in dienst.download(eintrag)) {
          if (fortschritt.receivedBytes == fortschritt.totalBytes &&
              fortschritt.totalBytes > 0) {
            stdout.writeln('    ${fortschritt.fileName}: '
                '${(fortschritt.totalBytes / 1e6).toStringAsFixed(1)} MB');
          }
        }
        final fertig = dienst.isEntryInstalled(eintrag);
        stdout.writeln('    installiert: $fertig');
        if (!fertig) fehler.add('${eintrag.id}: Dateien fehlen nach dem Lauf');
      } catch (e) {
        stdout.writeln('    FEHLER: $e');
        fehler.add('${eintrag.id}: $e');
      }
    }

    // Liegengebliebene Rumpfdateien sind ein eigener Befund.
    final reste = ordner
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.part'))
        .map((f) => f.uri.pathSegments.last)
        .toList();
    if (reste.isNotEmpty) {
      stdout.writeln('LIEGENGEBLIEBEN: ${reste.join(", ")}');
    }

    await ordner.delete(recursive: true);
    expect(fehler, isEmpty, reason: fehler.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}

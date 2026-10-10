// ignore_for_file: avoid_print
// **Wo der Klartext des gesperrten Ordners liegt – im laufenden Programm.**
//
// Unittests können zwei Dinge nicht zeigen: die Zugriffsliste, die Windows
// dem Zwischenspeicher gibt, und ein echtes „Platte voll“ im tmpfs. Beides
// prüft dieser Test auf der Plattform, auf der er läuft (#7, #8):
//
//   * **Windows:** Der Zwischenspeicher liegt im lokalen App-Ordner, nicht
//     in `%TEMP%`, und nur der eigene Benutzer steht in seiner
//     Zugriffsliste – kein SYSTEM, keine Administratoren.
//   * **Linux:** Eine Datei, die nicht ins tmpfs passt, weicht in den
//     Cache-Ordner auf der Platte aus. Mit `PV_GROSS=1` wird dafür eine
//     900-MB-Datei gegen ein tmpfs von 789 MB (`$XDG_RUNTIME_DIR`)
//     geschrieben; das ist ein echter ENOSPC, kein gestellter.
//   * **macOS:** Der Zwischenspeicher liegt im Sandkasten-Container.
//
//   flutter test integration_test/klartext_ablage_test.dart -d windows
//   PV_GROSS=1 flutter test integration_test/klartext_ablage_test.dart -d linux
//
// Die Bibliothek ist eine leere Probebibliothek im Temp-Ordner; die echte
// wird nicht angefasst.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_klartext_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'library')),
    );
    library = LibraryState()
      ..db = db
      ..paths = paths;
    await library.setupVaultPin('4711');
  });

  tearDown(() async {
    await library.clearDecryptCache();
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Eine gesperrte Aufnahme aus [bytes] Bytes, geschrieben in Stücken.
  Future<String> gesperrt(String id, int bytes) async {
    final datei = paths.absolute('originals/$id.mp4');
    await datei.parent.create(recursive: true);
    final raf = await datei.open(mode: FileMode.write);
    final stueck = List<int>.generate(1 << 20, (i) => i % 251);
    for (var rest = bytes; rest > 0; rest -= stueck.length) {
      await raf.writeFrom(stueck, 0, rest < stueck.length ? rest : null);
    }
    await raf.close();
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.mp4',
            relativePath: 'originals/$id.mp4',
            checksum: 'pruef-$id',
            type: 'VIDEO',
            fileCreatedAt: DateTime(2026),
            importedAt: DateTime(2026),
            fileSizeBytes: Value(bytes),
          ),
        );
    await library.lockAsset((await db.assetById(id))!);
    return (await db.assetById(id))!.relativePath;
  }

  testWidgets('der Zwischenspeicher liegt, wo er hingehört', (tester) async {
    late File f;
    await tester.runAsync(() async {
      f = await library.decryptForViewing(await gesperrt('klein', 300000));
    });
    final ordner = f.parent.path;
    print('Klartext liegt unter: $ordner');
    expect(f.lengthSync(), 300000);

    if (Platform.isWindows) {
      final lokal = Platform.environment['LOCALAPPDATA']!;
      final temp = Platform.environment['TEMP']!;
      expect(ordner.toLowerCase(), startsWith(lokal.toLowerCase()));
      expect(
        ordner.toLowerCase().startsWith(temp.toLowerCase()),
        isFalse,
        reason: 'nicht mehr im gemeinsamen %TEMP%',
      );
      final liste = (await Process.run('icacls', [ordner])).stdout as String;
      print(liste);
      final benutzer = Platform.environment['USERNAME']!.toLowerCase();
      expect(liste.toLowerCase(), contains(benutzer));
      expect(liste, isNot(contains('SYSTEM')));
      expect(liste, isNot(contains('Administrators')));
      expect(liste, isNot(contains('Administratoren')));
    } else if (Platform.isLinux) {
      expect(ordner, startsWith(Directory.systemTemp.path));
    }
  });

  testWidgets(
    'Linux: was nicht ins tmpfs passt, weicht auf die Platte aus',
    (tester) async {
      final klein = Platform.environment['XDG_RUNTIME_DIR'];
      if (klein == null) {
        markTestSkipped('kein XDG_RUNTIME_DIR');
        return;
      }
      // Ein tmpfs mit zehn Prozent des Arbeitsspeichers – dieselbe Grösse
      // wie das /tmp des Flatpaks.
      final voll = Directory(p.join(klein, 'pv_klartext_probe'));
      library.klartextOrdnerFuerTests = voll;
      late File f;
      final uhr = Stopwatch()..start();
      await tester.runAsync(() async {
        f = await library.decryptForViewing(
          await gesperrt('gross', 900 * 1024 * 1024),
        );
      });
      print(
        'Klartext liegt unter: ${f.parent.path} '
        '(${(uhr.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)',
      );
      expect(f.lengthSync(), 900 * 1024 * 1024);
      expect(f.path.startsWith(voll.path), isFalse);
      expect(
        voll.existsSync() ? voll.listSync() : const [],
        isEmpty,
        reason: 'der abgebrochene Rumpf gibt den Platz im tmpfs wieder frei',
      );
    },
    skip: !Platform.isLinux || Platform.environment['PV_GROSS'] == null,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

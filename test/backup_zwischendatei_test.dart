import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';

/// Anlass (13. Prüfrunde, 25.08.2026): Unter Flatpak ist `/tmp` ein
/// tmpfs von 789 MiB. Die Sicherung legte dort jede Datei zwischen, und in
/// einer echten Bibliothek liegen Videos bis 9,1 GB. Die erste zu grosse
/// Datei warf eine Ausnahme, und weil die Schleife in einem `try/finally`
/// **ohne catch** stand, brach der ganze Lauf ab – alles dahinter wurde
/// nie gesichert.
///
/// Ein Dateisystem fester Grösse lässt sich im Test nicht anlegen. Statt
/// dessen bekommt der Dienst ein Zwischenlager, das es gar nicht gibt:
/// Derselbe Zweig, dieselbe Ausnahmeart (`FileSystemException`).
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_backup_zwischen_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
    importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<List<String>> importiere(int anzahl) async {
    final incoming = Directory(p.join(tempRoot.path, 'incoming'))
      ..createSync(recursive: true);
    final namen = <String>[];
    for (var i = 0; i < anzahl; i++) {
      final f = File(p.join(incoming.path, 'foto_$i.jpg'));
      await f.writeAsBytes(List.filled(2048, i % 256));
      await importService.importFile(f.path);
      namen.add('foto_$i.jpg');
    }
    return namen;
  }

  Directory zielOrdner() =>
      Directory(p.join(tempRoot.path, 'ziel'))..createSync(recursive: true);

  List<File> gesicherteDateien(Directory ziel) {
    final o = Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals'));
    if (!o.existsSync()) return [];
    return o
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => !f.path.endsWith('.xmp'))
        .toList();
  }

  test('untaugliches Zwischenlager: gesichert wird trotzdem', () async {
    await importiere(3);
    final ziel = zielOrdner();
    // Ein Ordner, den es nicht gibt – jeder Schreibversuch dort scheitert.
    final kaputt = Directory(p.join(tempRoot.path, 'gibtesnicht'));
    final dienst = BackupService(db, paths, zwischenlager: kaputt);

    final meldungen = await dienst.performBackup(ziel.path).toList();

    expect(gesicherteDateien(ziel).length, 3,
        reason: 'trotz untauglichem Zwischenlager muss alles ankommen');
    expect(meldungen.where((m) => m.fehlgeschlagen != null), isEmpty,
        reason: 'der Ausweichweg ist kein Fehlschlag');
    // Nichts darf liegenbleiben.
    final reste = Directory(p.join(ziel.path, 'PhotoVault-Backup'))
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.pv-teil'));
    expect(reste, isEmpty, reason: 'Zwischendateien müssen weg sein');
  });

  test('eine unschreibbare Datei bricht den Lauf nicht ab', () async {
    await importiere(3);
    final ziel = zielOrdner();
    final dienst = BackupService(db, paths);

    // Der Zielpfad einer Datei wird durch einen Ordner gleichen Namens
    // blockiert. Welche das trifft, ist gleich - eine von dreien.
    final alle = await db.assetsNotBackedUp();
    final opfer = alle.first;
    final blockiert = p.join(ziel.path, 'PhotoVault-Backup', 'originals',
        opfer.relativePath.replaceFirst('originals${Platform.pathSeparator}', ''));
    Directory(blockiert).createSync(recursive: true);

    final meldungen = await dienst.performBackup(ziel.path).toList();

    expect(meldungen.last.fehlgeschlagen, 1,
        reason: 'der Ausfall muss gemeldet werden, sonst sieht der Lauf '
            'vollständig aus');
    expect(gesicherteDateien(ziel).length, 2,
        reason: 'die anderen beiden müssen durchgelaufen sein');

    // Der wichtigste Teil: Was nicht geschrieben wurde, darf nicht als
    // gesichert markiert sein - sonst ginge es dauerhaft verloren.
    final offen = await db.assetsNotBackedUp();
    expect(offen.map((a) => a.id), [opfer.id]);
  });

  test('ein untaugliches Ziel eicht NICHT das Zwischenlager', () async {
    // Der Unterschied, an dem der erste Entwurf scheiterte: Scheitert das
    // Ablegen im Ziel, liegt das nicht am Zwischenlager. Wurde das
    // verwechselt, schaltete eine einzige unschreibbare Datei den Umweg
    // ueber das System-Temp fuer den ganzen restlichen Lauf ab - und damit
    // den Schutz, halbfertige Dateien nicht in den Sync-Ordner zu legen.
    await importiere(2);
    final ziel = zielOrdner();
    final dienst = BackupService(db, paths);
    final opfer = (await db.assetsNotBackedUp()).first;
    Directory(p.join(ziel.path, 'PhotoVault-Backup', 'originals',
            opfer.relativePath
                .replaceFirst('originals${Platform.pathSeparator}', '')))
        .createSync(recursive: true);

    await dienst.performBackup(ziel.path).toList();

    expect(dienst.zwischenlagerGrenze, isNull,
        reason: 'ein Zielfehler darf das Zwischenlager nicht abwerten');
  });

  test('ein untaugliches Zwischenlager wird geeicht', () async {
    await importiere(1);
    final dienst = BackupService(db, paths,
        zwischenlager: Directory(p.join(tempRoot.path, 'gibtesnicht')));
    await dienst.performBackup(zielOrdner().path).toList();
    expect(dienst.zwischenlagerGrenze, isNotNull,
        reason: 'sonst versucht es die naechste grosse Datei wieder');
  });

  test('ohne Zwischenfall bleibt keine .pv-teil-Datei zurueck', () async {
    await importiere(2);
    final ziel = zielOrdner();
    await BackupService(db, paths).performBackup(ziel.path).toList();
    final reste = Directory(p.join(ziel.path, 'PhotoVault-Backup'))
        .listSync(recursive: true)
        .where((e) => e.path.endsWith('.pv-teil'));
    expect(reste, isEmpty);
  });
}

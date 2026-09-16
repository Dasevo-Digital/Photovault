import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/storage_paths.dart';

void main() {
  late Directory temp;
  late StoragePaths paths;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_paths_sicher_');
    paths =
        await StoragePaths.forTesting(Directory(p.join(temp.path, 'library')));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('normaler relativer Pfad bleibt innerhalb der Bibliothek', () {
    final file = paths.absolute(p.join('originals', '2026', 'foto.jpg'));
    expect(p.isWithin(paths.root.path, file.path), isTrue);
  });

  test('absolute Pfade werden abgelehnt', () {
    expect(() => paths.absolute(p.absolute('fremd.jpg')), throwsArgumentError);
  });

  test('Traversal wird vor Lesen und Löschen abgelehnt', () async {
    final ausserhalb = File(p.join(temp.path, 'nicht-loeschen.txt'))
      ..writeAsStringSync('bleibt');

    expect(() => paths.absolute(p.join('..', 'nicht-loeschen.txt')),
        throwsArgumentError);
    await expectLater(
      paths.deletePermanently(p.join('..', 'nicht-loeschen.txt')),
      throwsArgumentError,
    );
    expect(ausserhalb.readAsStringSync(), 'bleibt');
  });

  test('Speicherbereinigung löscht nur alte unvollständige Schreibreste',
      () async {
    final alt = paths.absolute('previews/alt.part')
      ..writeAsBytesSync([1, 2, 3]);
    alt.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    final frisch = paths.absolute('previews/frisch.part')
      ..writeAsBytesSync([4]);
    final original = paths.absolute('previews/fertig.jpg')
      ..writeAsBytesSync([5]);

    final result = await paths.bereinigeSchreibreste();

    expect(result.dateien, 1);
    expect(result.bytes, 3);
    expect(alt.existsSync(), isFalse);
    expect(frisch.existsSync(), isTrue);
    expect(original.existsSync(), isTrue);
  });
}

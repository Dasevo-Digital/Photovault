// **Eine Uhr, die den Abbau überlebt, hält genau das am Leben, was sie
// freigeben soll.**
//
// Der Einbettungsspeicher gibt sich nach drei Minuten Ruhe selbst frei;
// dafür hängt an jeder Nutzung ein Zeitgeber. `dispose()` räumte die
// vier anderen Zeitgeber der Klasse ab, diesen nicht. Der Abschluss des
// Zeitgebers zeigt auf die `LibraryState` – die bliebe nach dem Abbau
// samt ihrem Einbettungsspeicher noch drei Minuten erreichbar.
//
// Aufgefallen ist es als „A Timer is still pending even after the widget
// tree was disposed" in drei Prüfungen der Duplikatansicht; dort ist es
// über `clearEmbeddingCaches()` gelöst. Diese Prüfung hält den Weg über
// `dispose()` fest, den sonst keine abdeckt.
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

void main() {
  late Directory tempRoot;

  setUp(() => tempRoot = Directory.systemTemp.createTempSync('pv_uhr_'));
  tearDown(() => tempRoot.deleteSync(recursive: true));

  Future<LibraryState> gebaut() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    await db.saveEmbedding('a1', Float32List.fromList([1, 0]));
    return LibraryState()
      ..db = db
      ..paths = paths;
  }

  test('dispose raeumt die Uhr des Einbettungsspeichers ab', () async {
    final library = await gebaut();
    // Erst benutzen: Vorher gibt es gar keine Uhr, und der Test prüfte
    // dann nichts.
    await library.cachedEmbeddings();

    var offen = 0;
    fakeAsync((zeit) {
      // Eine zweite Nutzung INNERHALB der gestellten Zeit stellt die Uhr
      // dort neu – damit hängt sie an dieser Zeitrechnung und ist
      // zählbar.
      library.cachedEmbeddings();
      zeit.flushMicrotasks();
      expect(zeit.pendingTimers, isNotEmpty,
          reason: 'ohne laufende Uhr prueft der Rest nichts');
      library.dispose();
      zeit.flushMicrotasks();
      offen = zeit.pendingTimers.length;
    });

    expect(offen, 0,
        reason: 'nach dem Abbau darf keine Uhr mehr laufen – sie hielte '
            'sonst die abgebaute LibraryState samt Einbettungen fest');
  });
}

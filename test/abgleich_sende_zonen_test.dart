import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';

/// **Ein geteilter Sendelauf und mehrere Fehlerzonen (#422).**
///
/// Die Hintergrundschleife, `sendeBald` und die Oberfläche teilen sich
/// einen Lauf. Endete er mit einem Fehler, erreichte der nur Wartende aus
/// der Zone, in der er entstand: Wer aus einer anderen Fehlerzone wartete,
/// wartete für immer, und der Fehler – ohne Server [KeineVerbindung] –
/// stand im Ursprung als unbehandelt da.
void main() {
  test(
    'jeder Aufrufer bekommt KeineVerbindung, keiner bleibt hängen',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'foto',
          originalFileName: 'foto.jpg',
          relativePath: 'originals/foto.jpg',
          checksum: 'hash',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
        ),
      );
      final v = Serververbindung(
        Uri.parse('http://localhost/'),
        'synthetisch',
        client: MockClient((_) async => throw http.ClientException('weg')),
      );
      addTearDown(v.schliesse);

      final unbehandeltA = <Object>[];
      final unbehandeltB = <Object>[];
      final bereit = Completer<Abgleich>();
      final ausA = Completer<Object?>();

      // Zone A: Hier entsteht der Abgleich, und hier beginnt der Lauf.
      runZonedGuarded(() async {
        final a = Abgleich(db, v);
        await a.richteEin();
        await db.fuehreAus(const BeschreibungSetzen(['foto'], 'neu'));
        bereit.complete(a);
        a.sende().then(
          (_) => ausA.complete(null),
          onError: (Object f) => ausA.complete(f),
        );
      }, (f, _) => unbehandeltA.add(f));
      final a = await bereit.future;

      // Zone B: Die Oberfläche wartet auf denselben Lauf.
      final ausB = Completer<Object?>();
      runZonedGuarded(() {
        a.sende().then(
          (_) => ausB.complete(null),
          onError: (Object f) => ausB.complete(f),
        );
      }, (f, _) => unbehandeltB.add(f));

      expect(
        await ausA.future.timeout(const Duration(seconds: 5)),
        isA<KeineVerbindung>(),
      );
      expect(
        await ausB.future.timeout(const Duration(seconds: 5)),
        isA<KeineVerbindung>(),
        reason: 'der Fehler kommt auch in der anderen Zone an',
      );
      await Future<void>.delayed(Duration.zero);
      expect(unbehandeltA, isEmpty);
      expect(unbehandeltB, isEmpty);
      await a.beende();
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:path/path.dart' as p;

import 'hilfen/synthetische_bilder.dart';

/// Die Arbeit im eigenen Isolat (#498): Zwischenstände, Ergebnis als
/// Datei, bekannte Fehler als [Zusammenfuegefehler], Abbrechen beendet.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('pv_fuegelauf_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String schreibe(String name, List<int> bytes) =>
      (File(p.join(temp.path, name))..writeAsBytesSync(bytes)).path;

  test('HDR im Isolat: Stände steigen, am Ende steht das JPEG', () async {
    final dateien = [
      for (final (i, ev) in [(0, -1.5), (1, 0.0), (2, 1.5)])
        schreibe(
          'q$i.jpg',
          belichtungsaufnahme(200, 150, ev, dx: i * 2.0).alsJpeg(),
        ),
    ];
    final ziel = p.join(temp.path, 'hdr.jpg');
    final staende = await fuegeZusammen(
      Fuegeauftrag(art: Fuegeart.hdr, dateien: dateien, ziel: ziel),
    ).toList();
    final ergebnis = staende.last.ergebnis!;
    expect(ergebnis.datei, ziel);
    expect(ergebnis.verwendet, [0, 1, 2]);
    final bild = img.decodeJpg(File(ziel).readAsBytesSync())!;
    expect((bild.width, bild.height), (ergebnis.breite, ergebnis.hoehe));
    expect(bild.width, inInclusiveRange(190, 200));
    final zwischen = staende.where((s) => s.ergebnis == null).toList();
    expect(zwischen, isNotEmpty);
    for (var k = 1; k < zwischen.length; k++) {
      expect(
        zwischen[k].erledigt,
        greaterThanOrEqualTo(zwischen[k - 1].erledigt),
      );
    }
  });

  test('ein bekannter Grund kommt als Zusammenfuegefehler über den Port, '
      'mit der Stelle der Quelle', () async {
    final gut = schreibe(
      'gut.jpg',
      schwenkaufnahme(160, 120, 140, 0).alsJpeg(),
    );
    final kaputt = schreibe('kaputt.jpg', [1, 2, 3, 4, 5]);
    await expectLater(
      fuegeZusammen(
        Fuegeauftrag(
          art: Fuegeart.panorama,
          dateien: [gut, kaputt],
          ziel: p.join(temp.path, 'x.jpg'),
        ),
      ).toList(),
      throwsA(
        isA<Zusammenfuegefehler>()
            .having((f) => f.grund, 'grund', Fuegegrund.unlesbar)
            .having((f) => f.quelle, 'quelle', 1),
      ),
    );
    final fremd = schreibe(
      'fremd.jpg',
      schwenkaufnahme(160, 120, 140, 0, saat: 3).alsJpeg(),
    );
    await expectLater(
      fuegeZusammen(
        Fuegeauftrag(
          art: Fuegeart.panorama,
          dateien: [gut, fremd],
          ziel: p.join(temp.path, 'y.jpg'),
        ),
      ).toList(),
      throwsA(
        isA<Zusammenfuegefehler>().having(
          (f) => f.grund,
          'grund',
          Fuegegrund.keineUeberlappung,
        ),
      ),
    );
  });

  test(
    'Abbrechen beendet das Isolat: Es schreibt kein Ergebnis mehr',
    () async {
      final dateien = [
        for (var i = 0; i < 4; i++)
          schreibe(
            's$i.jpg',
            schwenkaufnahme(480, 360, 420, i * 25.0).alsJpeg(),
          ),
      ];
      final ziel = p.join(temp.path, 'abgebrochen.jpg');
      final erster = Completer<void>();
      final abo =
          fuegeZusammen(
            Fuegeauftrag(art: Fuegeart.panorama, dateien: dateien, ziel: ziel),
          ).listen((_) {
            if (!erster.isCompleted) erster.complete();
          });
      await erster.future;
      await abo.cancel();
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(File(ziel).existsSync(), isFalse);
    },
  );
}

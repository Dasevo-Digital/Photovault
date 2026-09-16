import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_download_service.dart';
import 'package:photo_vault/services/modell_halter.dart';

/// Befunde der fünften Prüfrunde.
void main() {
  group('Leihe überlebt einen Fehler in der Arbeit nicht als Dauerbelegung', () {
    /// Bildet nach, was `_ensureEmbedding` im Entwickeln-Bildschirm tut:
    /// leihen, arbeiten, im Erfolgsfall behalten – und in JEDEM anderen
    /// Fall zurückgeben. Ohne das `finally` blieb der Nutzerzähler nach
    /// einem Fehler für immer auf 1 und das Modell (101 MB) liess sich bis
    /// zum Programmende nicht mehr freigeben.
    Future<void> leihenUndArbeiten(
      ModellHalter<String> halter, {
      required bool wirft,
      required bool behaltenBeiErfolg,
    }) async {
      final modell = await halter.leihen();
      if (modell == null) return;
      var behalten = false;
      try {
        if (wirft) throw StateError('Inferenz fehlgeschlagen');
        behalten = behaltenBeiErfolg;
      } catch (_) {
        // wie im Bildschirm: Meldung an den Nutzer, kein erneutes Werfen
      } finally {
        if (!behalten) halter.zurueckgeben();
      }
    }

    ModellHalter<String> halter() => ModellHalter<String>(
          name: 'Segmentierung',
          installiert: true,
          laden: () async => 'modell',
          entsorgen: (_) async {},
        );

    test('nach einem Fehler bleibt das Modell freigebbar', () async {
      final h = halter();
      await leihenUndArbeiten(h, wirft: true, behaltenBeiErfolg: true);

      expect(h.nutzer, 0, reason: 'ein Fehler darf die Leihe nicht festhalten');
      expect(await h.freigebenWennUnbenutzt(), isTrue,
          reason: 'sonst bliebe das Modell bis zum Programmende im Speicher');
    });

    test('im Erfolgsfall bleibt die Leihe bestehen', () async {
      final h = halter();
      await leihenUndArbeiten(h, wirft: false, behaltenBeiErfolg: true);

      expect(h.nutzer, 1, reason: 'der Bildschirm braucht das Modell weiter');
      expect(await h.freigebenWennUnbenutzt(), isFalse);

      // Erst das Verlassen des Bildschirms gibt frei.
      h.zurueckgeben();
      expect(await h.freigebenWennUnbenutzt(), isTrue);
    });

    test('mehrere Fehlversuche summieren sich nicht auf', () async {
      final h = halter();
      for (var i = 0; i < 5; i++) {
        await leihenUndArbeiten(h, wirft: true, behaltenBeiErfolg: true);
      }
      expect(h.nutzer, 0);
    });
  });

  group('Reste abgebrochener Downloads', () {
    late Directory dir;
    late ModelDownloadService dienst;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pv_dl_');
      dienst = ModelDownloadService(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('werden entfernt, fertige Modelle bleiben unangetastet', () async {
      File('${dir.path}/clip_text_encoder.onnx').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/clip_image_encoder.onnx.part').writeAsBytesSync([4, 5]);
      File('${dir.path}/caption_decoder.onnx.part').writeAsBytesSync([6]);
      File('${dir.path}/vocab.json').writeAsStringSync('{}');

      final entfernt = await dienst.raeumeAbgebrocheneDownloads();

      expect(entfernt, 2);
      // p.basename statt split('/'): Windows trennt mit Backslash, und
      // der Vergleich lief dort gegen ganze Pfade statt gegen Dateinamen.
      final uebrig = dir.listSync().map((e) => p.basename(e.path)).toSet();
      expect(uebrig, {'clip_text_encoder.onnx', 'vocab.json'},
          reason: 'nur die .part-Reste dürfen verschwinden');
    });

    test('ohne Reste passiert nichts', () async {
      File('${dir.path}/vocab.json').writeAsStringSync('{}');
      expect(await dienst.raeumeAbgebrocheneDownloads(), 0);
      expect(dir.listSync(), hasLength(1));
    });

    test('ein fehlender Ordner ist kein Fehler', () async {
      final weg = ModelDownloadService('${dir.path}/gibtesnicht');
      expect(await weg.raeumeAbgebrocheneDownloads(), 0);
    });
  });
}

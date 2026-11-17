// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-gru: ANS-092 mit dem Wegwerf-Server, der
// selbst rechnet (PV_E2E_SERVER=1 PV_E2E_RECHNEN=alles, dazu
// PV_ONNXRUNTIME und PV_MODELLE). Eigene Datei: Die Albumregeln laufen am
// Server alle zehn Minuten, die Prüfung dauert deshalb über 20 Minuten.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/screens/album_detail_screen.dart';
import 'package:photo_vault/screens/aufnahmen_waehlen_screen.dart';

import 'katalog_kit.dart';
import 'katalog_r2_gru_server_test.dart' hide main;
import 'katalog_r2_gru_test.dart' hide main;

void main() {
  lebenszeichen();

  testWidgets(
    'ANS-092 Albumregel: neues Foto mit Person A kommt dazu, abgeschaltet nicht',
    (tester) async {
      filtereSemantik();
      await starte(tester);
      await importiere(tester, [
        testfoto('a2019.jpg', datum: DateTime(2019, 6, 1, 10)),
        testfoto('a2021.jpg', datum: DateTime(2021, 6, 1, 10)),
        testfoto('a2023.jpg', datum: DateTime(2023, 6, 1, 10)),
      ]);
      final personA = uuid.v4();
      await befehl(tester, PersonAnlegen(personA, 'Person A'));
      for (final n in ['a2019.jpg', 'a2021.jpg', 'a2023.jpg']) {
        await gesichtFuer(tester, n, personA);
      }
      final albumId = uuid.v4();
      await befehl(tester, AlbumAnlegen(albumId, 'Familie', DateTime.now()));
      final server = Uri.parse(serverAdresse);
      final k = await verbinde(tester, server);
      final v = Serververbindung(server, k.token);
      addTearDown(v.schliesse);
      final zustand = await mitDb(tester, () => v.hole('api/v1/zustand'));
      print('ANS-092: Server ${zustand['funktionen']}');

      Finder regelKnopf() => find.byWidgetPredicate(
        (w) =>
            w is IconButton &&
            (w.tooltip ?? '').startsWith(teilenDe.automatischFuellen),
      );
      Future<void> albumOeffnen() async {
        await alleZurueck(tester);
        await openSection(tester, Hauptbereich.alben);
        await tippe(tester, find.text('Familie').first);
        await waitFor(tester, find.byType(AlbumDetailScreen));
        await waitFor(tester, regelKnopf());
      }

      // Album mit aktiver Regel für Person A.
      await albumOeffnen();
      await tippe(tester, regelKnopf());
      await waitFor(tester, find.text(teilenDe.automatischTitel('Familie')));
      final hakenA = find.widgetWithText(CheckboxListTile, 'Person A');
      await waitFor(tester, hakenA);
      await tester.ensureVisible(hakenA);
      await tester.tap(hakenA);
      await tester.pump();
      await tester.tap(find.text(teilenDe.speichern).last);
      await waitFor(
        tester,
        find.text(teilenDe.automatischDazu(3)),
        timeout: const Duration(seconds: 30),
      );
      await eventually(
        tester,
        () async => (await albumInhalt(tester, 'Familie')).length == 3,
        timeout: const Duration(seconds: 60),
        was: 'Album gefüllt',
      );
      // Ein Foto über „Fotos hinzufügen“ abhaken.
      await tippe(tester, find.byTooltip(de.albumFotosHinzufuegen));
      await waitFor(tester, find.byType(AufnahmenWaehlenScreen));
      await tippe(tester, kachelName('a2021.jpg'));
      await tippe(tester, find.widgetWithText(TextButton, de.allgFertig));
      await eventually(
        tester,
        () async =>
            !(await albumInhalt(tester, 'Familie')).contains('a2021.jpg'),
        was: 'abgehakt',
      );
      await alleZurueck(tester);

      // Ein neues Foto mit Person A hochladen und zuordnen.
      Future<String> neuesFotoMitA(String fixture) async {
        final datei = mlFixture('gesichter/$fixture');
        await importiere(tester, [datei]);
        late AssetData neu;
        await eventually(
          tester,
          () async {
            final l = await bibliothek.db.select(bibliothek.db.assets).get();
            final t = l.where((a) => a.originalFileName == fixture);
            if (t.isEmpty) return false;
            neu = t.first;
            return true;
          },
          timeout: const Duration(seconds: 90),
          was: '$fixture hochgeladen',
        );
        // Das Gesicht erkennt der Server (PV_SELBST_RECHNEN=alles); die
        // Kopie erfährt es über den Abgleich.
        schritt = 'ANS-092 Gesicht in $fixture';
        late List<FaceData> g;
        await eventually(
          tester,
          () async {
            g = await (bibliothek.db.select(
              bibliothek.db.faces,
            )..where((t) => t.assetId.equals(neu.id))).get();
            return g.isNotEmpty;
          },
          timeout: const Duration(minutes: 6),
          was: 'Gesicht in $fixture vom Server',
        );
        print('ANS-092: $fixture mit ${g.length} Gesicht(ern)');
        await befehl(
          tester,
          GesichterZuordnen([for (final x in g) x.id], personA),
        );
        return neu.id;
      }

      await neuesFotoMitA('person_a_5.jpg');
      // Die Regeln laufen am Server alle zehn Minuten
      // (packages/server/lib/src/albumregeln.dart:300–349).
      schritt = 'ANS-092 warten auf die Regel';
      final zugeordnet = DateTime.now();
      await eventually(
        tester,
        () async =>
            (await albumInhalt(tester, 'Familie')).contains('person_a_5.jpg'),
        timeout: const Duration(minutes: 11),
        was: 'neues Foto im Album',
      );
      print(
        'ANS-092: neues Foto nach '
        '${DateTime.now().difference(zugeordnet).inSeconds} s im Album',
      );
      final mitNeuem = await albumInhalt(tester, 'Familie');
      print('ANS-092: mit dem neuen $mitNeuem');
      expect(mitNeuem, ['a2019.jpg', 'a2023.jpg', 'person_a_5.jpg']);

      // Regel abschalten.
      await albumOeffnen();
      await tippe(tester, regelKnopf());
      await tester.tap(find.text(teilenDe.automatischAus));
      await waitFor(
        tester,
        find.text(teilenDe.automatischAusGemacht),
        timeout: const Duration(seconds: 30),
      );
      await alleZurueck(tester);
      await neuesFotoMitA('person_a_6.jpg');
      // Länger als ein Durchgang der Regeln am Server.
      schritt = 'ANS-092 ein Durchgang der Regeln';
      await warte(tester, const Duration(minutes: 10, seconds: 40));
      final danach = await albumInhalt(tester, 'Familie');
      print('ANS-092: nach dem Abschalten $danach');
      expect(danach, mitNeuem, reason: 'nichts dazu, vorhandene bleiben');
      await ende(tester);
    },
    timeout: const Timeout(Duration(minutes: 36)),
  );
}

// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-gru: GRU-057 – als erste Prüfung in einem
// eigenen Prozess (PV_E2E_SERVER=1).
//
// **Warum eine eigene Datei.** In Runde 1 (und hier zuerst auch) kam eine
// KeineVerbindung aus Abgleich._sende als „unbehandelt“ an – angelastet
// der ersten Prüfung der Datei. Das ist ein Effekt des Prüfstands, kein
// Fehler der App: Der Abgleich merkt sich beim Anlegen die Zone, in der er
// sendet (`_betriebszone = Zone.current`, packages/kern/lib/abgleich/
// abgleich.dart:117), und sendeBald hängt das catchError in der Zone des
// Aufrufers an (:343–349). Gebaut wird die App im Prüfstand in der Zone,
// in der der Taktgeber des Kits läuft – der Zone der ersten Prüfung des
// Prozesses –, der Stern kommt aus der Zone der laufenden Prüfung. Dart
// reicht Fehler nicht über die Grenze zweier Fehlerzonen weiter, sondern
// meldet sie in der Zone des Futures als unbehandelt. In der App gibt es
// nur die Wurzelzone (lib/main.dart: runApp ohne runZonedGuarded); dort
// fängt das catchError den Fehler. Ist diese Prüfung die erste ihres
// Prozesses, sind beide Zonen dieselbe – wie in der App.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';

import 'katalog_kit.dart';
import 'katalog_r2_gru_test.dart' hide main;

void main() {
  lebenszeichen();

  testWidgets(
    'GRU-057 Server weg und wieder da: Band, wartende Änderung kommt an',
    (tester) async {
      filtereSemantik();
      for (var durchgang = 1; durchgang <= 2; durchgang++) {
        final server = Uri.parse(serverAdresse);
        final d = Durchreiche(server);
        await starte(tester);
        final name = 'stern$durchgang.jpg';
        await importiere(tester, [testfoto(name)]);
        await tester.runAsync(d.starte);
        final k = await verbinde(
          tester,
          server,
          adresseInDatei: Uri.parse(d.adresse),
        );
        final a = await aufnahme(tester, name);
        // Der Server ist weg: Verbindungen brechen ab, neue werden
        // abgewiesen.
        schritt = 'GRU-057 Server weg';
        await tester.runAsync(d.halteAn);
        await oeffneFoto(tester, a.id);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await settle(tester);
        expect(
          (await mitDb(
            tester,
            () => bibliothek.db.assetById(a.id),
          ))!.isFavorite,
          isTrue,
        );
        await key(tester, LogicalKeyboardKey.escape);
        await waitGone(tester, find.byType(AssetViewerScreen));
        await waitFor(
          tester,
          find.text(de.serverOffline(1)),
          timeout: const Duration(seconds: 90),
        );
        print('GRU-057 Durchgang $durchgang: Band „${de.serverOffline(1)}“');
        // Der Server ist wieder da.
        schritt = 'GRU-057 Server wieder da';
        await tester.runAsync(d.starte);
        await waitGone(
          tester,
          find.text(de.serverOffline(1)),
          timeout: const Duration(seconds: 180),
        );
        final v = Serververbindung(server, k.token);
        try {
          late Map<String, Object?> amServer;
          await eventually(
            tester,
            () async {
              amServer = await v.hole('api/v1/aufnahmen/${a.id}');
              return amServer['isFavorite'] == true;
            },
            timeout: const Duration(seconds: 60),
            was: 'Stern am Server',
          );
          print('GRU-057: am Server isFavorite ${amServer['isFavorite']}');
        } finally {
          v.schliesse();
        }
        await eventually(
          tester,
          () async => bibliothek.abgleichszustand?.ausstehend == 0,
          was: 'nichts wartet mehr',
        );
        expect(find.textContaining('Server nicht erreichbar'), findsNothing);
        await ende(tester);
        await tester.runAsync(d.halteAn);
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

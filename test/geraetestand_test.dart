import 'dart:convert';

import 'package:abgleich_ui/geraetestand_anzeige.dart';
import 'package:abgleich_ui/l10n/sync_texte.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';

void main() {
  test(
    'Abgleich meldet Schema und Warteschlange, drosselt Wiederholungen und hält Erfolg getrennt',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final gemeldet = <Map>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/geraete/stand');
        gemeldet.add(jsonDecode(request.body) as Map);
        return http.Response('{"gespeichert":true}', 200);
      });
      final verbindung = Serververbindung(
        Uri.parse('https://server.invalid/'),
        'test',
        client: client,
        clientFassung: '3.67.12',
      );
      final a = Abgleich(db, verbindung);
      try {
        await a.richteEin();
        await a.meldeGeraetestand();
        await a.meldeGeraetestand();
        expect(gemeldet, hasLength(1));
        expect(gemeldet.single['fassung'], '3.67.12');
        expect(gemeldet.single['schema'], db.schemaVersion);
        expect(gemeldet.single['offen'], 0);
        expect(gemeldet.single['erfolgreich'], isFalse);
        await a.meldeGeraetestand(erfolgreich: true);
        expect(gemeldet, hasLength(2));
        expect(gemeldet.last['erfolgreich'], isTrue);
      } finally {
        await a.beende();
        await db.close();
        client.close();
      }
    },
  );

  test(
    'Älterer Server ohne Zustandsendpunkt verhindert den Abgleich nicht',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = MockClient((_) async => http.Response('{}', 404));
      final a = Abgleich(
        db,
        Serververbindung(
          Uri.parse('https://server.invalid/'),
          'test',
          client: client,
        ),
      );
      try {
        await a.richteEin();
        await a.meldeGeraetestand();
      } finally {
        await a.beende();
        await db.close();
        client.close();
      }
    },
  );

  testWidgets(
    'Fehlende Geräteangaben bleiben unbekannt und Schemaabweichungen werden sichtbar',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final daten = <String, Object?>{
        'name': 'Telefon',
        'clientSchema': 99,
        'clientOffen': 2,
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: SyncTexte.localizationsDelegates,
          supportedLocales: SyncTexte.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Column(
                  children: [
                    GeraetestandAnzeige(daten: daten, zielSchema: 100),
                    GeraeteAktualisierungsplan(
                      geraete: [daten],
                      zielSchema: 100,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('App-Version nicht gemeldet'), findsOneWidget);
      expect(find.textContaining('benötigt: 100'), findsOneWidget);
      expect(find.textContaining('Offene Änderungen zuerst'), findsOneWidget);
      expect(find.textContaining('Telefon'), findsOneWidget);
      expect(
        find.textContaining('Kein erfolgreicher Abgleich'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

// Verwaltung auf der Kontoseite: behobene Befunde aus dem Prüfkatalog der
// Handy-App (MOB, Issue #418): je Befund ein Test, der ohne die Korrektur
// scheitert.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/sicherung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/konto.dart';
import 'package:photo_vault_mobil/sitzung.dart';

void main() {
  testWidgets('MOB-155 nach dem Anstossen zeigt die Zeile den Lauf, nach '
      '„Jetzt sichern“ den neuen Zeitpunkt', (tester) async {
    final frueher = DateTime.utc(2026, 11, 17, 13, 37);
    final spaeter = DateTime.utc(2026, 11, 17, 13, 40);
    // Was der Server der Reihe nach meldet.
    final auswertung = <Map<String, Object?>>[
      {'laeuft': false},
      {'laeuft': true},
      {
        'laeuft': true,
        'stand': {
          'stufe': 'texterkennung',
          'stufeNummer': 3,
          'stufenGesamt': 7,
          'erledigt': 19,
          'gesamt': 24,
        },
      },
      {'laeuft': false},
    ];
    final sicherung = <Map<String, Object?>>[
      {'stufe': 'ok', 'laeuft': true, 'ende': frueher.toIso8601String()},
      {
        'stufe': 'ok',
        'laeuft': false,
        'ende': spaeter.toIso8601String(),
        'letzterErfolg': spaeter.toIso8601String(),
      },
    ];
    http.Response json(Object? d) => http.Response(jsonEncode(d), 200);
    final client = MockClient((r) async {
      switch ('${r.method} ${r.url.path}') {
        case 'GET /api/v1/konto':
          return json({'name': 'anna', 'verwalter': true, 'geraet': 'g1'});
        case 'GET /api/v1/auswertung':
          return json(
            auswertung.length > 1 ? auswertung.removeAt(0) : auswertung.first,
          );
        case 'GET /api/v1/sicherung':
          return json(
            sicherung.length > 1 ? sicherung.removeAt(0) : sicherung.first,
          );
        case 'POST /api/v1/auswertung' || 'POST /api/v1/sicherung/jetzt':
          return json(const {});
      }
      return http.Response('{}', 404);
    });

    final ordner = Directory.systemTemp.createTempSync('pv_konto_befund_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final server = Uri.parse('https://fotos.example/');
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade
      ..verbindung = Verbindungsdatei(
        server: server,
        konto: 'anna',
        geraet: 'Telefon',
        token: 't',
      )
      ..abgleich = Abgleich(db, Serververbindung(server, 't', client: client))
      ..serversicherung = Serversicherungsstand(
        stufe: 'ok',
        letzterErfolg: frueher.toLocal(),
        ende: frueher.toLocal(),
      );
    await tester.binding.setSurfaceSize(const Size(500, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Konto(sitzung: sitzung),
      ),
    );
    Future<void> ruhe([Duration d = Duration.zero]) async {
      await tester.pump(d);
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await ruhe();
    final t = AppTexte.of(tester.element(find.byType(Konto)));
    expect(find.text(t.verwAuswertungRuht), findsOneWidget);

    await tester.tap(find.text(t.verwAnstossen));
    await ruhe();
    expect(find.text(t.verwAuswertungStartet), findsOneWidget);
    await ruhe(const Duration(seconds: 3));
    expect(
      find.text(t.verwAuswertungLaeuft('texterkennung', 3, 7, 19, 24)),
      findsOneWidget,
    );
    await ruhe(const Duration(seconds: 3));
    expect(find.text(t.verwAuswertungRuht), findsOneWidget);

    String stand(DateTime d) => t.serverSicherungStand(
      DateFormat.yMd('de').add_Hm().format(d.toLocal()),
    );
    expect(find.text(stand(frueher)), findsOneWidget);
    await tester.tap(find.text(t.verwJetztSichern));
    await ruhe();
    await ruhe(const Duration(seconds: 3));
    expect(find.text(stand(spaeter)), findsOneWidget);

    // Läuft nichts mehr, fragt die Zeile auch nicht weiter.
    await ruhe(const Duration(seconds: 30));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

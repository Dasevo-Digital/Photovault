import 'dart:convert';

import 'package:abgleich_ui/abgleichsuebersicht.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;
  late Serververbindung v;
  late Abgleich a;
  late Map<String, Object?> serverfoto;
  var offline = false;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'foto',
        originalFileName: 'probe.jpg',
        relativePath: 'probe.jpg',
        checksum: 'synthetisch',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
      ),
    );
    v = Serververbindung(
      Uri.parse('http://127.0.0.1/'),
      'test',
      client: MockClient((r) async {
        if (offline) throw StateError('synthetisch offline');
        final Object antwort;
        if (r.url.path.endsWith('/zustand')) {
          antwort = {
            'funktionen': {'konfliktpruefung': 1},
          };
        } else if (r.url.path.endsWith('/befehle')) {
          final j = jsonDecode(r.body) as Map;
          antwort = {
            'stand': 0,
            'ergebnisse': [
              for (final b in j['befehle'] as List)
                {
                  'kennung': (b as Map)['kennung'],
                  'ok': false,
                  'konflikt': true,
                  'fehler': 'pv_sync_konflikt',
                },
            ],
          };
        } else if (r.url.path.endsWith('/zeilen')) {
          final j = jsonDecode(r.body) as Map;
          antwort = {
            'zeilen': [
              for (final b in j['schluessel'] as List)
                Zeilenstand(
                  'assets',
                  (b['s'] as List).cast<Object?>(),
                  serverfoto,
                ).alsJson(),
            ],
          };
        } else {
          antwort = {'bis': 0, 'mehr': false, 'zeilen': []};
        }
        return http.Response(
          jsonEncode(antwort),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    a = Abgleich(db, v);
    await a.richteEin();
    serverfoto = {
      ...(await a.protokoll.lies('assets', ['foto'])).werte!,
      'description': 'Serverbeschreibung',
    };
    offline = false;
  });
  tearDown(() async {
    await a.beende();
    v.schliesse();
    await db.close();
  });
  Future<void> vorbereiten({bool offen = false, bool gesperrt = false}) async {
    await db.fuehreAus(
      const BeschreibungSetzen(['foto'], 'Meine private Absicht'),
    );
    if (gesperrt) {
      serverfoto['is_locked'] = 1;
      serverfoto['description'] = null;
    }
    if (!offen) {
      await a.sende();
      await a.empfange();
    }
    offline = offen;
  }

  Future<void> zeige(WidgetTester t) async {
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppTexte.supportedLocales,
        localizationsDelegates: AppTexte.localizationsDelegates,
        home: Abgleichsuebersicht(abgleich: a),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Beschreibung ändern'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'offene Absicht ist offline lesbar ohne Serverstand zu behaupten',
    (t) async {
      await vorbereiten(offen: true);
      await zeige(t);
      expect(find.textContaining('Meine private Absicht'), findsOneWidget);
      expect(find.textContaining('Server: Serverbeschreibung'), findsNothing);
      expect(find.text('Eigene Änderung erneut anwenden'), findsNothing);
      expect(
        find.textContaining('gespeicherte lokale Absicht'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'gesperrter Fall zeigt weder Inhalt noch Namen und erlaubt keinen erneuten Auftrag',
    (t) async {
      await vorbereiten(gesperrt: true);
      await zeige(t);
      expect(find.textContaining('Meine private Absicht'), findsNothing);
      expect(find.text('probe.jpg'), findsNothing);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Eigene Änderung erneut anwenden',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('Aufnahme ist gesperrt'), findsOneWidget);
    },
  );
  testWidgets(
    'Vergleich und ausdrückliche Bestätigung wenden die ganze Absicht erneut an',
    (t) async {
      await vorbereiten();
      await zeige(t);
      expect(find.text('probe.jpg'), findsWidgets);
      expect(find.text('Server: Serverbeschreibung'), findsOneWidget);
      await t.ensureVisible(find.text('Eigene Änderung erneut anwenden'));
      await t.tap(find.text('Eigene Änderung erneut anwenden'));
      await t.pumpAndSettle();
      expect((await a.faelle()).single.ausstehend, isFalse);
      await t.tap(find.text('Bestätigen'));
      await t.pumpAndSettle();
      expect((await a.faelle()).single.ausstehend, isTrue);
    },
  );
  testWidgets('geänderter Serverstand fordert eine neue Entscheidung', (
    t,
  ) async {
    await vorbereiten();
    await zeige(t);
    serverfoto['description'] = 'Inzwischen geändert';
    await t.ensureVisible(find.text('Eigene Änderung erneut anwenden'));
    await t.tap(find.text('Eigene Änderung erneut anwenden'));
    await t.pumpAndSettle();
    await t.tap(find.text('Bestätigen'));
    await t.pumpAndSettle();
    expect((await a.faelle()).single.ausstehend, isFalse);
    expect(
      find.textContaining('Serverstand hat sich inzwischen geändert'),
      findsOneWidget,
    );
  });
}

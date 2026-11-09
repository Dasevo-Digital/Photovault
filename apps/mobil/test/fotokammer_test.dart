import 'dart:convert';

import 'package:abgleich_ui/fotokammer_dienst.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/fotokammer.dart';

/// Die Fotokammer am Handy (#350) gegen einen nachgebauten Server.
void main() {
  late List<Map<String, Object?>> eintraege;
  late List<List<String>> freigegeben;
  late List<List<String>> verworfen;
  late List<Map<String, Object?>> urteile;
  late int stufe;

  final jpeg = img.encodeJpg(img.Image(width: 8, height: 6));

  Map<String, Object?> eintrag(int i) => {
    'id': '00000000-0000-4000-8000-00000000000$i',
    'name': 'IMG_$i.CR3',
    'groesse': 1000,
    'datum': '2026-11-07T08:4$i:00.000Z',
    'art': 'IMAGE',
    'breite': 2048,
    'hoehe': 1365,
  };

  Fotokammerdienst dienst() => Fotokammerdienst(
    Serververbindung(
      Uri.parse('http://server/'),
      'x',
      client: MockClient((r) async {
        final pfad = r.url.path;
        http.Response json(Object? o) => http.Response(
          jsonEncode(o),
          200,
          headers: {'content-type': 'application/json'},
        );
        if (pfad == '/api/v1/zustand') {
          return json({
            'funktionen': {'fotokammer': stufe},
          });
        }
        if (pfad == '/api/v1/kammer') {
          return json({'eintraege': eintraege, 'anzahl': eintraege.length});
        }
        if (r.method == 'GET') {
          return http.Response.bytes(
            jpeg,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        final k = (jsonDecode(r.body) as Map).cast<String, Object?>();
        if (pfad.endsWith('/sichten')) {
          urteile.add(k);
          return json({'geaendert': 1});
        }
        final ids = (k['ids']! as List).cast<String>();
        if (pfad.endsWith('/freigeben')) {
          freigegeben.add(ids);
          eintraege.removeWhere((e) => ids.contains(e['id']));
          return json({
            'ergebnisse': [
              for (final id in ids)
                {'id': id, 'ausgang': 'imported', 'aufnahme': 'a$id'},
            ],
          });
        }
        verworfen.add(ids);
        eintraege.removeWhere((e) => ids.contains(e['id']));
        return json({'verworfen': ids.length});
      }),
    ),
  );

  setUp(() {
    eintraege = [for (var i = 1; i <= 3; i++) eintrag(i)];
    freigegeben = [];
    verworfen = [];
    urteile = [];
    stufe = 4;
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: FotokammerSeite(dienst: dienst()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder kachel(int i) => find.byType(GestureDetector).at(i);

  testWidgets('langes Drücken wählt aus, Freigeben schickt die Auswahl', (
    tester,
  ) async {
    await zeige(tester);
    await tester.longPress(kachel(0));
    await tester.pump();
    expect(find.text('1 ausgewählt'), findsOneWidget);
    await tester.tap(find.text('Freigeben'));
    await tester.pumpAndSettle();
    expect(freigegeben.single, hasLength(1));
  });

  testWidgets('Verwerfen fragt vorher', (tester) async {
    await zeige(tester);
    await tester.longPress(kachel(1));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('1 Foto endgültig verwerfen?'), findsOneWidget);
    expect(verworfen, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    expect(verworfen.single, hasLength(1));
  });

  testWidgets('im Foto: Sterne setzen, Ablehnen geht weiter', (tester) async {
    await zeige(tester);
    await tester.tap(kachel(0));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('4'));
    await tester.pumpAndSettle();
    expect(urteile.last['sterne'], 4);
    await tester.tap(find.byTooltip('Ablehnen'));
    await tester.pumpAndSettle();
    expect(urteile.last['abgelehnt'], isTrue);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('älterer Server: ansehen ja, sichten nein', (tester) async {
    stufe = 2;
    await zeige(tester);
    await tester.tap(kachel(0));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Ablehnen'), findsNothing);
  });

  testWidgets('Sichtung abschliessen fragt und trennt richtig', (tester) async {
    eintraege[0] = {...eintraege[0], 'abgelehnt': true};
    await zeige(tester);
    await tester.tap(find.byTooltip('Sichtung abschliessen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 abgelehntes Foto'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Sichtung abschliessen'),
    );
    await tester.pumpAndSettle();
    expect(verworfen.single, [eintrag(1)['id']]);
    expect(freigegeben.expand((s) => s), hasLength(2));
  });

  group('Erinnerung', () {
    test('erst nach drei Tagen, mit Zahl und Dauer', () async {
      final d = dienst();
      eintraege = [
        {...eintrag(1), 'angelegt': '2026-11-01T10:00:00.000Z'},
        {...eintrag(2), 'angelegt': '2026-11-05T10:00:00.000Z'},
      ];
      await d.aktualisiere();
      expect(d.anzahl.value, 2);
      expect(d.faelligeErinnerung(DateTime.utc(2026, 11, 3, 12)), isNull);
      final e = d.faelligeErinnerung(DateTime.utc(2026, 11, 6, 12))!;
      expect((e.anzahl, e.tage), (2, 5));
    });

    test('eine leere Kammer erinnert nie', () async {
      final d = dienst();
      eintraege = [];
      await d.aktualisiere();
      expect(d.faelligeErinnerung(DateTime.utc(2030)), isNull);
    });

    test('ein Server ohne Kammer ist kein Fehler', () async {
      stufe = 0;
      final d = dienst();
      await d.aktualisiere();
      expect(d.anzahl.value, isNull);
    });
  });
}

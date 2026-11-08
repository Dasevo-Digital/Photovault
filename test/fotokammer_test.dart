import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/fotokammer_screen.dart';
import 'package:photo_vault/services/fotokammer_dienst.dart';

/// Die Fotokammer am Rechner (#336) gegen einen nachgebauten Server:
/// zeigen, auswählen, in Stapeln freigeben, nach Rückfrage verwerfen.
void main() {
  late List<Map<String, Object?>> eintraege;
  late List<String> anfragen;
  late List<List<String>> freigegeben;
  late List<List<String>> verworfen;
  late int nachFreigabe;

  final jpeg = img.encodeJpg(img.Image(width: 8, height: 6));

  Map<String, Object?> eintrag(int i, {bool bild = true}) => {
    'id': '00000000-0000-4000-8000-00000000000$i',
    'name': 'IMG_14$i.CR3',
    'groesse': 35000000,
    'datum': '2026-11-07T08:4$i:00.000Z',
    'art': 'IMAGE',
    'modell': 'Canon EOS R10',
    if (bild) 'breite': 2048,
    if (bild) 'hoehe': 1365,
  };

  Fotokammerdienst dienst() {
    final client = MockClient((r) async {
      final pfad = r.url.path;
      anfragen.add('${r.method} $pfad');
      http.Response json(Object? o) => http.Response(
        jsonEncode(o),
        200,
        headers: {'content-type': 'application/json'},
      );
      if (pfad == '/api/v1/zustand') {
        return json({
          'funktionen': {'fotokammer': 1},
        });
      }
      if (pfad == '/api/v1/kammer') {
        return json({
          'eintraege': eintraege,
          'anzahl': eintraege.length,
          'bytes': 0,
        });
      }
      if (pfad.endsWith('/miniatur') || pfad.endsWith('/vorschau')) {
        return http.Response.bytes(
          jpeg,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }
      final ids = (jsonDecode(r.body)['ids'] as List).cast<String>();
      if (pfad == '/api/v1/kammer/freigeben') {
        freigegeben.add(ids);
        eintraege.removeWhere((e) => ids.contains(e['id']));
        return json({
          'ergebnisse': [
            for (final id in ids)
              {'id': id, 'ausgang': 'imported', 'aufnahme': 'a$id'},
          ],
        });
      }
      if (pfad == '/api/v1/kammer/verwerfen') {
        verworfen.add(ids);
        eintraege.removeWhere((e) => ids.contains(e['id']));
        return json({'verworfen': ids.length});
      }
      return http.Response('', 404);
    });
    return Fotokammerdienst(
      Serververbindung(Uri.parse('http://server/'), 'x', client: client),
      nachFreigabe: () async => nachFreigabe++,
    );
  }

  setUp(() {
    eintraege = [
      for (var i = 1; i <= 5; i++) eintrag(i),
      eintrag(6, bild: false),
    ];
    anfragen = [];
    freigegeben = [];
    verworfen = [];
    nachFreigabe = 0;
  });

  Future<void> zeige(WidgetTester tester, Fotokammerdienst? d) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: FotokammerScreen(dienst: d),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ohne Server ein Hinweis statt der Kammer', (tester) async {
    await zeige(tester, null);
    expect(find.textContaining('Photo Vault Server'), findsOneWidget);
  });

  testWidgets('zeigt die Kammer und fragt nur nach vorhandenen Bildern', (
    tester,
  ) async {
    await zeige(tester, dienst());
    expect(find.textContaining('6 Fotos · '), findsOneWidget);
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(6));
    // Der sechste Eintrag hat keine Vorschau – nach ihr wird nicht gefragt.
    final miniaturen = anfragen.where((a) => a.endsWith('/miniatur'));
    expect(miniaturen, hasLength(5));
    expect(miniaturen.any((a) => a.contains('000000000006')), isFalse);
  });

  testWidgets('alle auswählen und in Stapeln zu vier freigeben', (
    tester,
  ) async {
    await zeige(tester, dienst());
    await tester.tap(find.byTooltip('Alle auswählen'));
    await tester.pump();
    expect(find.text('6 ausgewählt'), findsOneWidget);
    await tester.tap(find.text('Freigeben'));
    await tester.pumpAndSettle();
    expect(freigegeben.map((s) => s.length), [4, 2]);
    expect(nachFreigabe, 1);
    expect(find.textContaining('6 Fotos in die Bibliothek'), findsOneWidget);
    expect(find.textContaining('Die Fotokammer ist leer'), findsOneWidget);
  });

  testWidgets('verwerfen erst nach Rückfrage, und nur die Auswahl', (
    tester,
  ) async {
    await zeige(tester, dienst());
    await tester.tap(find.byIcon(Icons.circle_outlined).at(1));
    await tester.pump();
    expect(find.text('1 ausgewählt'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    expect(find.text('1 Foto endgültig verwerfen?'), findsOneWidget);
    // Abbrechen lässt alles, wie es war.
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(verworfen, isEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Verwerfen'));
    await tester.pumpAndSettle();
    expect(verworfen, [
      ['00000000-0000-4000-8000-000000000002'],
    ]);
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(5));
  });

  testWidgets('Auswahl umkehren', (tester) async {
    await zeige(tester, dienst());
    await tester.tap(find.byIcon(Icons.circle_outlined).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Auswahl umkehren'));
    await tester.pump();
    expect(find.text('5 ausgewählt'), findsOneWidget);
  });

  testWidgets('doppelt klicken öffnet das Foto, ohne die Auswahl zu ändern', (
    tester,
  ) async {
    await zeige(tester, dienst());
    final kachel = find.byIcon(Icons.circle_outlined).at(2);
    await tester.tap(kachel);
    await tester.tap(kachel);
    await tester.pumpAndSettle();
    expect(find.textContaining('IMG_143.CR3'), findsOneWidget);
    expect(find.text('3 / 6'), findsOneWidget);
    expect(anfragen.where((a) => a.endsWith('/vorschau')), hasLength(2));
    // Leertaste wählt aus, Pfeil blättert, Esc schliesst.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('4 / 6'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('1 ausgewählt'), findsOneWidget);
  });
}

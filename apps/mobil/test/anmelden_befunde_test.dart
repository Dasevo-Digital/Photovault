// Anmeldung: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/sitzung.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppTexte.localizationsDelegates,
  supportedLocales: AppTexte.supportedLocales,
  home: home,
);

/// Eine Adresse im eigenen Netz, zur Laufzeit zusammengesetzt.
final _adresse = 'http://${[127, 0, 0, 1].join('.')}:8790';

Future<AppTexte> _anmeldeseite(
  WidgetTester tester,
  Sitzung sitzung,
  http.Client client,
) async {
  await tester.binding.setSurfaceSize(const Size(360, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _app(
      Anmelden(
        sitzung: sitzung,
        anmeldungFuer: (s) => Anmeldung(s, client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final t = AppTexte.of(tester.element(find.byType(Anmelden)));
  await tester.enterText(
    find.widgetWithText(TextField, t.anmeldenAdresse),
    _adresse,
  );
  await tester.enterText(
    find.widgetWithText(TextField, t.anmeldenName),
    'anna',
  );
  await tester.enterText(
    find.widgetWithText(TextField, t.anmeldenPasswort),
    'ein langes passwort',
  );
  return t;
}

/// Ein Server, der die Anmeldung ohne Zwei-Faktor sofort annimmt.
http.Response _photoVault(http.Request r) => switch (r.url.path) {
  '/api/v1/zustand' => http.Response(
    jsonEncode({
      'dienst': 'photo-vault',
      'protokoll': 2,
      'anmeldung': {'totp': false, 'oidc': false},
    }),
    200,
  ),
  '/api/v1/anmelden' => http.Response(jsonEncode({'token': 't'}), 200),
  _ => http.Response('{}', 404),
};

/// Holt die Bibliothek beim ersten Mal nicht (Server fällt aus).
class _ScheiterndeSitzung extends Sitzung {
  var versuche = 0;

  @override
  Future<void> verbinde({
    required Uri server,
    required String konto,
    required String geraet,
    required String token,
  }) async {
    versuche++;
    if (versuche == 1) throw KeineVerbindung('Verbindung abgerissen');
  }
}

void main() {
  testWidgets('MOB-002 ein fremder Dienst: verständliche Meldung, nichts '
      'gespeichert', (tester) async {
    for (final antwort in [
      http.Response('404 page not found', 404),
      http.Response('<html><body>Router</body></html>', 200),
    ]) {
      final sitzung = Sitzung();
      final t = await _anmeldeseite(
        tester,
        sitzung,
        MockClient((_) async => antwort),
      );
      await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
      await tester.pumpAndSettle();
      expect(find.text(t.anmeldenKeinServer), findsOneWidget);
      expect(find.textContaining('FormatException'), findsNothing);
      expect(sitzung.verbindung, isNull);
    }
  });

  testWidgets('MOB-014 Server fällt beim Laden der Bibliothek aus: Meldung, '
      'zweiter Versuch, Weg zurück', (tester) async {
    final sitzung = _ScheiterndeSitzung();
    final t = await _anmeldeseite(
      tester,
      sitzung,
      MockClient((r) async => _photoVault(r)),
    );
    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'kein Fehlerbild');
    expect(find.text(t.anmeldenNichtErreichbar), findsOneWidget);
    expect(find.text(t.anmeldenZurueck), findsOneWidget);

    // Der Weg zurück zur Anmeldung …
    await tester.tap(find.text(t.anmeldenZurueck));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenNichtErreichbar), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenPasswort),
      'ein langes passwort',
    );
    sitzung.versuche = 0;
    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenNichtErreichbar), findsOneWidget);

    // … und der zweite Versuch, der klappt.
    await tester.tap(find.text(t.startfehlerErneut));
    await tester.pumpAndSettle();
    expect(sitzung.versuche, 2);
    expect(find.text(t.anmeldenNichtErreichbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MOB-013 von aussen: „Neuer Server?“ führt zum ersten Konto, '
      'der Server sagt, dass das nur aus dem Heimnetz geht', (tester) async {
    // Von aussen fehlt `einrichten` im Zustand – ob der Server schon
    // Konten hat, erfährt die App nicht.
    final pfade = <String>[];
    final t = await _anmeldeseite(
      tester,
      Sitzung(),
      MockClient((r) async {
        pfade.add(r.url.path);
        return switch (r.url.path) {
          '/api/v1/einrichten' => http.Response(
            jsonEncode({
              'fehler':
                  'Das erste Konto lässt sich nur aus dem Heimnetz anlegen, '
                  'nicht von aussen.',
            }),
            403,
          ),
          _ => _photoVault(r),
        };
      }),
    );
    await tester.ensureVisible(find.text(t.anmeldenNeuerServer));
    await tester.tap(find.text(t.anmeldenNeuerServer));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenErstesTitel), findsOneWidget);
    expect(find.text(t.anmeldenErstesTextOffen('anna')), findsOneWidget);
    expect(pfade, isNot(contains('/api/v1/anmelden')));

    await tester.enterText(
      find.widgetWithText(TextField, t.anmeldenPasswortWiederholen),
      'ein langes passwort',
    );
    await tester.tap(find.text(t.anmeldenErstesAnlegen));
    await tester.pumpAndSettle();
    expect(pfade, contains('/api/v1/einrichten'));
    expect(find.text(t.anmeldenErstesNurHeimnetz), findsOneWidget);
    expect(find.textContaining('fehler'), findsNothing, reason: 'kein JSON');
    expect(tester.takeException(), isNull);
  });
}

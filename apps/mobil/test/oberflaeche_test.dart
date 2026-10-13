import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/anmelden.dart';
import 'package:photo_vault_mobil/seiten/karte.dart';
import 'package:photo_vault_mobil/seiten/sicherung.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';
import 'package:photo_vault_mobil/sitzung.dart';

Rasterzeile _zeile(String id, double breite, double laenge) => Rasterzeile(
  id: id,
  type: 'IMAGE',
  originalFileName: '$id.jpg',
  relativePath: 'originals/$id.jpg',
  thumbnailRelativePath: null,
  fileCreatedAt: DateTime(2025),
  durationSeconds: null,
  isFavorite: false,
  isStackCover: false,
  stackId: null,
  stackSize: null,
  linkedAssetId: null,
  rating: 0,
  colorLabel: null,
  widthPx: null,
  heightPx: null,
  latitude: breite,
  longitude: laenge,
  cameraMake: null,
  isLocked: false,
);

void main() {
  test('die Karte fasst nahe Fotos zusammen, je nach Zoom', () {
    final orte = [
      _zeile('tor', 52.5163, 13.3777),
      _zeile('dom', 52.5191, 13.4010),
      _zeile('hafen', 53.5413, 9.9841),
    ];
    Set<Set<String>> gruppen(double zoom) => {
      for (final g in kartengruppen(orte, zoom)) {for (final z in g) z.id},
    };
    expect(gruppen(4), {
      {'tor', 'dom'},
      {'hafen'},
    });
    expect(gruppen(16), {
      {'tor'},
      {'dom'},
      {'hafen'},
    });
  });

  test('Deutsch und Englisch haben dieselben Texte', () {
    Set<String> schluessel(String sprache) =>
        (jsonDecode(File('lib/l10n/app_$sprache.arb').readAsStringSync())
                as Map<String, Object?>)
            .keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(schluessel('en'), schluessel('de'));
  });

  testWidgets('die Anmeldung sagt, wenn die Adresse fehlt', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Anmelden(sitzung: Sitzung()),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Anmelden)));
    expect(find.text(t.anmeldenGeraet), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, t.anmeldenGeraet))
          .controller!
          .text,
      t.geraetVorgabe,
    );

    await tester.tap(find.widgetWithText(FilledButton, t.anmeldenAnmelden));
    await tester.pumpAndSettle();
    expect(find.text(t.anmeldenNichtErreichbar), findsOneWidget);
  });

  testWidgets('die Sicherungsseite zeigt Stand, Probleme und Knopf', (
    tester,
  ) async {
    final ordner = Directory.systemTemp.createTempSync('pv_sicherungsseite_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    Sicherungsstand.oeffne(ordner)
      ..einstellungen = const Sicherungseinstellungen(an: true)
      ..letzterLauf = Laufbericht(
        ende: DateTime(2026, 10, 13, 9, 30),
        gesamt: 5,
        offen: 1,
        hochgeladen: 3,
        vorhanden: 0,
        fehlgeschlagen: 1,
        vollstaendig: false,
      )
      ..fehlschlag('x', 'Datei nicht verfügbar')
      ..schliesse();
    final dienst = Sicherungsdienst(
      ordner: ordner,
      server: Uri.parse('http://localhost:1/'),
      token: 'pv1_test',
    );
    addTearDown(dienst.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Sicherungsseite(dienst: dienst),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.sicherungStand(3, 5)), findsOneWidget);
    expect(find.text(t.sicherungProbleme(1)), findsOneWidget);
    expect(find.text('Datei nicht verfügbar'), findsOneWidget);
    expect(find.text(t.sicherungJetzt), findsOneWidget);
    expect(find.text(t.sicherungAlleFotos), findsOneWidget);
    expect(sicherungKurz(t, dienst), t.sicherungStand(3, 5));
  });
}

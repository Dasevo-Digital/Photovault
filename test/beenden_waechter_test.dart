import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/beenden_waechter.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/beenden_dialog.dart';

/// Seit die Hintergrundaufgaben wirklich weiterlaufen, ist das Beenden eine
/// folgenreiche Handlung: Ein Cmd-Q mitten in einem Lauf über tausende Fotos
/// verwirft die gerade bearbeitete Datei. Die native Seite fragt deshalb
/// vorher nach (macos/Runner/BeendenChannel.swift) – hier steht, was die
/// Dart-Seite darauf antworten muss.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kanal = MethodChannel(BeendenWaechter.kanalName);
  late BeendenWaechter waechter;

  /// Stellt die Frage so, wie sie nativ hereinkommt.
  Future<Object?> frage() async {
    final binaer = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Object? antwort;
    await binaer.handlePlatformMessage(
      BeendenWaechter.kanalName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall(BeendenWaechter.methode),
      ),
      (daten) => antwort = daten == null
          ? null
          : const StandardMethodCodec().decodeEnvelope(daten),
    );
    return antwort;
  }

  setUp(() => waechter = BeendenWaechter(kanal: kanal));
  tearDown(() => waechter.schweige());

  test('gibt weiter, was die Rückrufstelle entscheidet', () async {
    waechter.horche(() async => true);
    expect(await frage(), isTrue);

    waechter.schweige();
    waechter.horche(() async => false);
    expect(await frage(), isFalse);
  });

  test('eine Ausnahme auf dem Weg zum Dialog verhindert das Beenden nicht', () async {
    // Sonst liesse sich die App nach einem Fehler in der Oberfläche nur noch
    // über die Aktivitätsanzeige schliessen.
    waechter.horche(() async => throw StateError('kein Fenster da'));
    expect(await frage(), isTrue);
  });

  test('auf eine unbekannte Methode antwortet der Wächter nicht', () async {
    var gefragt = false;
    waechter.horche(() async {
      gefragt = true;
      return false;
    });

    final binaer = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    await binaer.handlePlatformMessage(
      BeendenWaechter.kanalName,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('irgendwas')),
      (_) {},
    );

    expect(gefragt, isFalse);
  });

  group('die Rückfrage selbst', () {
    late LibraryState library;
    late StreamController<ImportProgress> regler;

    setUp(() async {
      library = LibraryState();
      regler = StreamController<ImportProgress>();
      library.reiheAufgabeEin(
        schluessel: 'beschreibungen',
        titel: 'Erzeuge Bildbeschreibungen …',
        leermeldung: 'nichts zu tun',
        strom: () => regler.stream,
      );
    });

    tearDown(() async {
      library.brichAufgabeAb('beschreibungen');
      await regler.close();
    });

    Future<bool?> zeige(WidgetTester tester, {required String knopf}) async {
      bool? ergebnis;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => ergebnis = await zeigeBeendenFrage(context, library),
            child: const Text('fragen'),
          ),
        ),
      ));
      await tester.tap(find.text('fragen'));
      await tester.pumpAndSettle();

      // Nennt beim Namen, was läuft – „es läuft noch etwas" liesse offen,
      // ob es um Sekunden oder um eine Stunde geht.
      expect(find.text('Erzeuge Bildbeschreibungen …'), findsNothing);
      expect(find.text('• Erzeuge Bildbeschreibungen …'), findsOneWidget);

      await tester.tap(find.text(knopf));
      await tester.pumpAndSettle();
      return ergebnis;
    }

    testWidgets('„Weiterlaufen lassen" verhindert das Beenden', (tester) async {
      expect(await zeige(tester, knopf: 'Weiterlaufen lassen'), isFalse);
    });

    testWidgets('„Trotzdem beenden" lässt es zu', (tester) async {
      expect(await zeige(tester, knopf: 'Trotzdem beenden'), isTrue);
    });
  });
}

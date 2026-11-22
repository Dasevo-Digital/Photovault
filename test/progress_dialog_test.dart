import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:cryptography/cryptography.dart';
import 'package:photo_vault/services/backup_koordinator.dart';
import 'package:photo_vault/services/backup_verification_service.dart';
import 'package:photo_vault/services/vault_crypto.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/progress_dialog.dart';

/// Das Fortschrittsfenster übersetzt einen Fehler auch dann, wenn der
/// Aufrufer keine eigene Übersetzung mitgibt.
void main() {
  final de = lookupAppTexte(const Locale('de'));

  Future<void> zeige(
    WidgetTester tester,
    Stream<String> strom, {
    String sprache = 'de',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(sprache),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildLightTheme(),
        home: Scaffold(
          // Jeder Aufruf ist ein neues Fenster: Ein bestehendes behält
          // seinen ersten Strom (#423).
          body: ProgressDialog(
            key: UniqueKey(),
            title: 'Backup läuft',
            stream: strom,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  // SIC-041: Das Fenster des automatischen Backups hatte kein fehlerText
  // und zeigte „Fehlgeschlagen: Instance of 'BackupLaeuftBereits'“.
  testWidgets('ohne fehlerText gilt die gemeinsame Übersetzung', (
    tester,
  ) async {
    await zeige(tester, Stream<String>.error(const BackupLaeuftBereits()));
    expect(
      find.text(de.fortschrittFehlgeschlagen(de.backupLaeuftBereits)),
      findsOneWidget,
    );
    expect(find.textContaining('Instance of'), findsNothing);
  });

  testWidgets('ein eigenes fehlerText geht weiter vor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildLightTheme(),
        home: Scaffold(
          body: ProgressDialog(
            title: 'Backup läuft',
            stream: Stream<String>.error(const BackupLaeuftBereits()),
            fehlerText: (_) => 'eigener Satz',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text(de.fortschrittFehlgeschlagen('eigener Satz')),
      findsOneWidget,
    );
  });
  // SIC-061, SIC-065: Prüffehler und falsche Passphrase kamen als feste
  // deutsche Sätze bzw. roher Fehler der Entschlüsselung an – auch in der
  // englischen Oberfläche.
  testWidgets('Prüffehler und falsche Passphrase erscheinen übersetzt', (
    tester,
  ) async {
    final en = lookupAppTexte(const Locale('en'));
    for (final (fehler, text) in <(Object, String)>[
      (
        const BackupManifestFehler(Manifestproblem.fehlt),
        en.backupManifestFehlt,
      ),
      (
        const BackupManifestFehler(Manifestproblem.unlesbar),
        en.backupManifestUnlesbar,
      ),
      (const BackupManifestFehler(Manifestproblem.leer), en.backupManifestLeer),
      (const PassphraseFalsch(), en.passphraseFalsch),
      (SecretBoxAuthenticationError(), en.entschluesselnFehlgeschlagen),
    ]) {
      await zeige(tester, Stream<String>.error(fehler), sprache: 'en');
      expect(
        find.text(en.fortschrittFehlgeschlagen(text)),
        findsOneWidget,
        reason: '$fehler',
      );
    }
  });

  // #423: Die App baut die MaterialApp bei jeder Meldung des
  // Bibliothekszustands neu. Der Navigator lässt dann den Builder von
  // showDialog noch einmal laufen; das Fenster kündigte daraufhin den
  // laufenden Strom und abonnierte den neu erzeugten – die Arbeit begann
  // von vorn und wurde verbunden nie fertig.
  testWidgets('ein Neuaufbau der App bei offenem Fenster startet die Arbeit '
      'nicht neu', (tester) async {
    final neuaufbau = ValueNotifier<int>(0);
    addTearDown(neuaufbau.dispose);
    final weiter = Completer<void>();
    var gestartet = 0;
    var erzeugt = 0;
    Stream<String> arbeit() async* {
      gestartet++;
      yield 'Foto 1 / 2';
      await weiter.future;
      yield 'Foto 2 / 2';
    }

    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: neuaufbau,
        builder: (context, stand, _) => MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildLightTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  // Wie die alten Aufrufer: Der Strom entsteht im Builder.
                  builder: (_) {
                    erzeugt++;
                    return ProgressDialog(title: 'Läuft', stream: arbeit());
                  },
                ),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('los'));
    // Kein pumpAndSettle: Der Fortschrittsbalken läuft endlos.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Foto 1 / 2'), findsOneWidget);
    expect(gestartet, 1);

    // Neuaufbau der App, während das Fenster offen ist.
    neuaufbau.value++;
    await tester.pump();
    await tester.pump();
    expect(erzeugt, greaterThan(1), reason: 'der Builder lief noch einmal');
    expect(gestartet, 1, reason: 'die Arbeit darf nicht neu beginnen');
    expect(find.text('Foto 1 / 2'), findsOneWidget);

    weiter.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Foto 2 / 2'), findsOneWidget);
    expect(find.text(de.allgSchliessen), findsOneWidget);
    expect(gestartet, 1);
  });
}

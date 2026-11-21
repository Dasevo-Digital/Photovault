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
          body: ProgressDialog(title: 'Backup läuft', stream: strom),
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
}

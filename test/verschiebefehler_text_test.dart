import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/gemeinsam.dart';
import 'package:photo_vault/services/library_location.dart';

/// Was die Meldung nach einem gescheiterten Verlegen oder Zurücksetzen
/// zeigt (#490). Vorher stand dort der Rohtext der Ausnahme, etwa
/// „PathAccessException: Cannot open file, path = '…/library/
/// .standortkennung' (OS Error: Permission denied, errno = 13)“.
void main() {
  Future<String Function(Object)> texte(WidgetTester tester, Locale l) async {
    late BuildContext kontext;
    await tester.pumpWidget(
      MaterialApp(
        locale: l,
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) {
            kontext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return (fehler) => fehlertext(kontext, fehler);
  }

  const ziel = '/Volumes/Platte/Fotos';

  testWidgets('ein fehlender Schreibzugriff nennt den gewählten Ordner', (
    tester,
  ) async {
    final text = await texte(tester, const Locale('de'));
    final fehler = BibliotheksVerschiebefehler.aus(
      ziel,
      const PathAccessException(
        '$ziel/library/.standortkennung',
        OSError('Permission denied', 13),
        'Cannot open file',
      ),
    );
    expect(fehler.problem, Verschiebeproblem.zugriff);
    final satz = text(fehler);
    expect(satz, contains('„$ziel“'));
    expect(satz, contains('Zugriffsrechte'));
    expect(satz, contains('bleibt am bisherigen Ort'));
    expect(satz, isNot(contains('standortkennung')));
    expect(satz, isNot(contains('Exception')));
  });

  testWidgets('ein voller Datenträger und eine halbe Kopie', (tester) async {
    final text = await texte(tester, const Locale('de'));
    final voll = BibliotheksVerschiebefehler.aus(
      ziel,
      FileSystemException(
        'Write failed',
        '$ziel/library/originals/a.jpg',
        OSError('No space left on device', Platform.isWindows ? 112 : 28),
      ),
    );
    expect(voll.problem, Verschiebeproblem.platz);
    expect(
      text(voll),
      'In „$ziel“ ist nicht genug Platz für die Bibliothek. '
      'Die Bibliothek bleibt am bisherigen Ort.',
    );

    final halb = BibliotheksVerschiebefehler.aus(
      ziel,
      const FileSystemException('pv_verschieben_kopie', '$ziel/library.sqlite'),
    );
    expect(halb.problem, Verschiebeproblem.kopie);
    expect(
      text(halb),
      'Die Bibliothek konnte nicht vollständig nach „$ziel“ kopiert werden '
      '(eine Datei kam nicht vollständig an). Sie bleibt am bisherigen Ort.',
    );

    final sonst = BibliotheksVerschiebefehler.aus(
      ziel,
      const FileSystemException(
        'Cannot open file',
        '$ziel/library/originals/c.jpg',
        OSError('Is a directory', 21),
      ),
    );
    expect(sonst.problem, Verschiebeproblem.kopie);
    expect(text(sonst), contains('(Is a directory)'));
    expect(text(sonst), isNot(contains('c.jpg')));
  });

  testWidgets('auf Englisch, und die Hindernisse vom Zurücksetzen', (
    tester,
  ) async {
    final text = await texte(tester, const Locale('en'));
    expect(
      text(const BibliotheksVerschiebefehler(ziel, Verschiebeproblem.zugriff)),
      startsWith('Photo Vault is not allowed to write to “$ziel”.'),
    );
    // Aus resetLibraryLocation, falls sich das Ziel nach der Prüfung in
    // den Einstellungen noch füllt – bisher „Bad state: pv_verschieben_…“.
    expect(
      text(const VerschiebenVerhindert(Verschiebehindernis.belegt)),
      'This folder already holds a library. Choose an empty folder.',
    );
    expect(
      text(const VerschiebenVerhindert(Verschiebehindernis.inDerBibliothek)),
      startsWith('This folder is inside the library itself.'),
    );
  });
}

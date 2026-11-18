import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/import_koordinator.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/import_progress_sheet.dart';

/// **Duplikate wurden stillschweigend uebersprungen.**
///
/// Aus dem Bericht: "Fotos werden nicht doppelt angelegt, jedoch ohne
/// Meldung." Uebersprungen wurden sie immer schon - wer zweihundert
/// Dateien hereinzieht und danach hundertachtzig Fotos vorfindet, sucht
/// den Fehler bei sich.
void main() {
  late AppTexte de;
  late AppTexte en;

  setUpAll(() async {
    de = await AppTexte.delegate.load(const Locale('de'));
    en = await AppTexte.delegate.load(const Locale('en'));
  });

  test('ohne Duplikat und ohne Fehler steht da nichts', () {
    // Die Zahl der neuen Aufnahmen steht ohnehin schon im Fortschritt
    // darueber. "0 uebersprungen, 0 Fehler" waere Rauschen.
    expect(importBilanz(de, neu: 12, duplikate: 0, fehler: 0), isNull);
  });

  test('uebersprungene Dateien werden genannt', () {
    final zeile = importBilanz(de, neu: 180, duplikate: 20, fehler: 0)!;
    expect(zeile, contains('180'));
    expect(zeile, contains('20'));
    expect(zeile, contains('übersprungen'));
  });

  test('die Einzahl ist eine eigene Form', () {
    final zeile = importBilanz(de, neu: 3, duplikate: 1, fehler: 0)!;
    expect(zeile, contains('1 lag schon'));
    expect(zeile, isNot(contains('lagen')));
  });

  test('Fehler stehen daneben, nicht statt dessen', () {
    final zeile = importBilanz(de, neu: 5, duplikate: 2, fehler: 1)!;
    expect(zeile, contains('5'));
    expect(zeile, contains('2'));
    expect(zeile, contains('1'));
  });

  test('ein Fehler allein genuegt fuer die Zeile', () {
    expect(importBilanz(de, neu: 5, duplikate: 0, fehler: 1), isNotNull);
  });

  test('auf Englisch steht dasselbe', () {
    final zeile = importBilanz(en, neu: 180, duplikate: 20, fehler: 0)!;
    expect(zeile, contains('skipped'));
    expect(zeile, contains('20'));
  });

  group('Fehlergrund (#335)', () {
    test('Fehlerseite eines Proxys wird zu ihrem Titel', () {
      final seite =
          '<html>\r\n<head><title>502 Bad Gateway</title></head>\r\n'
          '<body>\r\n<center><h1>502 Bad Gateway</h1></center>\r\n'
          '<hr><center>openresty</center>\r\n</body>\r\n</html>\r\n';
      expect(
        importFehlertext(de, Serverfehler(502, seite)),
        'Server antwortete mit 502: 502 Bad Gateway',
      );
    });

    test('JSON-Fehler des Servers wird zu seinem Text', () {
      expect(
        importFehlertext(
          de,
          Serverfehler(503, '{"fehler":"pv_anfrage_grenze"}'),
        ),
        'Server antwortete mit 503: pv_anfrage_grenze',
      );
    });

    test('bekannte Gründe werden zu Sätzen, unbekannte bleiben stehen', () {
      expect(
        importFehlertext(de, KeineVerbindung('weg')),
        'Server nicht erreichbar',
      );
      expect(importFehlertext(de, null), 'Grund unbekannt');
      expect(
        importFehlertext(
          de,
          const FormatException('pv_import_quelle_geaendert'),
        ),
        de.importFehlerQuelleGeaendert,
      );
      expect(
        importFehlertext(
          de,
          const FormatException('pv_import_regeln_geaendert'),
        ),
        de.importPlanGeaendert,
      );
      expect(
        importFehlertext(
          de,
          const FileSystemException(
            'Datei nicht lesbar',
            '/x',
            OSError('Operation not permitted', 1),
          ),
        ),
        'Datei nicht lesbar (Operation not permitted)',
      );
      expect(
        importFehlertext(en, KeineVerbindung('x')),
        'Server not reachable',
      );
    });

    test('Kennungen als Text werden ebenso zu Sätzen (IMP-028, IMP-087)', () {
      // So reicht sie der Server in der Kopfzeile weiter – ältere Server
      // noch mit dem Namen der Ausnahme davor.
      for (final roh in [
        'pv_import_quelle_geaendert',
        'FormatException: pv_import_quelle_geaendert',
      ]) {
        expect(importFehlertext(de, roh), de.importFehlerQuelleGeaendert);
      }
      expect(
        importFehlertext(de, const FormatException('pv_import_server_zu_alt')),
        de.importPlanServerAlt,
      );
      expect(importFehlertext(de, 'Platte voll'), 'Platte voll');
    });

    test(
      'ohne Server: nach der Prüfung veränderte Datei nennt den Grund als Satz (IMP-028)',
      () async {
        final temp = await Directory.systemTemp.createTemp('pv_grund_');
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          await temp.delete(recursive: true);
        });
        final pfade = await StoragePaths.forTesting(
          Directory('${temp.path}/bibliothek'),
        );
        final importe = ImportService(
          db,
          pfade,
          bildwerkzeuge: const KeineBildwerkzeuge(),
        );
        final a = File('${temp.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
        final plan = await ImportPlanDienst(db, importe).erstelle([a.path]);
        a.writeAsBytesSync([4], mode: FileMode.append);
        final lauf = await ImportKoordinator(
          db: db,
          importe: importe,
          nachbearbeiten: (_, {regelnAnwenden = true}) async {},
          starteAnalyse: () async {},
        ).importiere([a.path], plan: plan).toList();
        expect(lauf.last.gescheitert, isTrue);
        // Die Ausnahme selbst, nicht ihr Text.
        expect(lauf.last.grund, isA<FormatException>());
        expect(
          importFehlertext(de, lauf.last.grund),
          de.importFehlerQuelleGeaendert,
        );
      },
    );
  });
}

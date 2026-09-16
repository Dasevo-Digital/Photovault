import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/state/library_state.dart';

/// Der Platz einer abgebrochenen Aufgabe wird erst frei, wenn sie ihn
/// wirklich geräumt hat.
///
/// Abbrechen heisst: das Abonnement kündigen. Der Generator hält dann bei
/// seinem nächsten `yield` an und durchläuft seinen `finally`-Block –
/// und erst dort gibt er sein geliehenes KI-Modell zurück. Bis zur
/// 17. Prüfrunde stiess `brichAufgabeAb` das Kündigen nur an und liess
/// sofort den nächsten los.
void main() {
  test('der naechste startet erst, wenn der Abgebrochene aufgeraeumt hat',
      () async {
    final library = LibraryState();

    // Der Abgebrochene: Sein Aufraeumen dauert – so wie eine laufende
    // Modell-Inferenz erst zu Ende laeuft, bevor der Generator sein
    // `finally` erreicht und das Modell zurueckgibt.
    var modellFreigegeben = false;
    final erster = StreamController<ImportProgress>();
    erster.onCancel = () async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      modellFreigegeben = true;
    };

    var zweiterHatModellGeholt = false;
    final zweiter = StreamController<ImportProgress>();

    library.reiheAufgabeEin(
        schluessel: 'beschreibung',
        titel: 'Bildbeschreibungen',
        leermeldung: '-',
        rechenintensiv: true,
        strom: () => erster.stream);
    library.reiheAufgabeEin(
        schluessel: 'kitags',
        titel: 'Schlagwoerter',
        leermeldung: '-',
        rechenintensiv: true,
        strom: () {
          zweiterHatModellGeholt = true;
          return zweiter.stream;
        });
    await pumpEventQueue();

    expect(library.lauf('beschreibung')!.laeuft, isTrue);
    expect(library.lauf('kitags')!.wartet, isTrue, reason: 'Grenze ist 1');

    library.brichAufgabeAb('beschreibung');
    await pumpEventQueue();

    // Solange das Aufraeumen laeuft, gehoert der Platz noch dem Ersten.
    expect(modellFreigegeben, isFalse, reason: 'der Test misst zu spaet');
    expect(zweiterHatModellGeholt, isFalse,
        reason: 'sonst laegen zwei Modelle gleichzeitig im Speicher');
    expect(library.lauf('beschreibung')!.laeuft, isTrue,
        reason: 'er arbeitet seine letzte Datei noch ab');
    expect(library.lauf('beschreibung')!.abgebrochen, isTrue);

    // Jetzt ist das Aufraeumen durch.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await pumpEventQueue();

    expect(modellFreigegeben, isTrue);
    expect(zweiterHatModellGeholt, isTrue, reason: 'jetzt darf der Zweite');
    expect(library.lauf('beschreibung')!.beendet, isTrue);
    expect(library.lauf('kitags')!.laeuft, isTrue);

    await erster.close();
    await zweiter.close();
  });

  test('ohne Aufraeumarbeit geht es unmittelbar weiter', () async {
    // Der Normalfall: Kuendigen ist sofort durch, und dann soll der
    // Naechste auch sofort los - nicht erst beim naechsten Anlass.
    final library = LibraryState();
    final erster = StreamController<ImportProgress>();
    final zweiter = StreamController<ImportProgress>();

    for (final e in [('beschreibung', erster), ('kitags', zweiter)]) {
      library.reiheAufgabeEin(
          schluessel: e.$1,
          titel: e.$1,
          leermeldung: '-',
          rechenintensiv: true,
          strom: () => e.$2.stream);
    }
    await pumpEventQueue();

    library.brichAufgabeAb('beschreibung');
    await pumpEventQueue();

    expect(library.lauf('beschreibung')!.beendet, isTrue);
    expect(library.lauf('kitags')!.laeuft, isTrue);

    await erster.close();
    await zweiter.close();
  });
}

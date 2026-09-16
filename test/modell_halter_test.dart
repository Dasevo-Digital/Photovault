import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/modell_halter.dart';

/// Der Halter entscheidet, wann ein KI-Modell im Speicher liegt. Fehler
/// darin sind teuer: doppeltes Laden kostet hunderte Megabyte, Freigeben
/// zur Unzeit bringt die App mitten in einer Inferenz zum Absturz.
void main() {
  /// Attrappe statt echtem Modell – hier zählt nur, wie oft geladen und
  /// entsorgt wird.
  ({
    ModellHalter<String> halter,
    List<String> verlauf,
    void Function() ladenFreigeben,
  }) baueHalter({bool installiert = true, bool langsam = false}) {
    final verlauf = <String>[];
    var zaehler = 0;
    final tor = Completer<void>();
    return (
      halter: ModellHalter<String>(
        name: 'Attrappe',
        installiert: installiert,
        laden: () async {
          if (langsam) await tor.future;
          zaehler++;
          verlauf.add('laden#$zaehler');
          return 'modell#$zaehler';
        },
        entsorgen: (m) async => verlauf.add('entsorgen $m'),
      ),
      verlauf: verlauf,
      ladenFreigeben: () => tor.isCompleted ? null : tor.complete(),
    );
  }

  test('lädt erst beim ersten Gebrauch', () async {
    final h = baueHalter();
    expect(h.halter.istGeladen, isFalse);
    expect(h.verlauf, isEmpty, reason: 'das Anlegen allein darf nichts laden');

    final ergebnis = await h.halter.mit((m) async => m.toUpperCase());

    expect(ergebnis, 'MODELL#1');
    expect(h.verlauf, ['laden#1']);
    expect(h.halter.istGeladen, isTrue);
  });

  test('lädt kein zweites Mal, solange die Sitzung offen ist', () async {
    final h = baueHalter();
    await h.halter.mit((m) async => m);
    await h.halter.mit((m) async => m);
    expect(h.verlauf, ['laden#1'], reason: 'eine Sitzung muss reichen');
  });

  test('zwei gleichzeitige Anfragen ergeben nur EINE Ladung', () async {
    final h = baueHalter(langsam: true);

    // Beide starten, bevor die Ladung durch ist.
    final a = h.halter.mit((m) async => m);
    final b = h.halter.mit((m) async => m);
    h.ladenFreigeben();
    final ergebnisse = await Future.wait([a, b]);

    expect(h.verlauf, ['laden#1'],
        reason: 'sonst lägen zwei Sitzungen desselben Modells im Speicher');
    expect(ergebnisse, ['modell#1', 'modell#1']);
  });

  test('gibt nicht frei, solange gearbeitet wird', () async {
    final h = baueHalter();
    final tor = Completer<void>();

    final arbeit = h.halter.mit((m) async {
      await tor.future;
      return m;
    });

    // Mitten in der Arbeit: Freigeben muss abgelehnt werden.
    await Future<void>.delayed(Duration.zero);
    expect(h.halter.nutzer, 1);
    expect(await h.halter.freigebenWennUnbenutzt(), isFalse,
        reason: 'Entsorgen während einer laufenden Inferenz stürzt ab');
    expect(h.verlauf, ['laden#1']);

    tor.complete();
    await arbeit;

    // Danach schon.
    expect(await h.halter.freigebenWennUnbenutzt(), isTrue);
    expect(h.verlauf, ['laden#1', 'entsorgen modell#1']);
    expect(h.halter.istGeladen, isFalse);
  });

  test('nach dem Freigeben wird beim nächsten Zugriff neu geladen', () async {
    final h = baueHalter();
    await h.halter.mit((m) async => m);
    await h.halter.freigebenWennUnbenutzt();
    final wieder = await h.halter.mit((m) async => m);

    expect(wieder, 'modell#2');
    expect(h.verlauf, ['laden#1', 'entsorgen modell#1', 'laden#2']);
  });

  test('Leihe hält das Modell über mehrere Aufrufe hinweg', () async {
    final h = baueHalter();
    final geliehen = await h.halter.leihen();
    expect(geliehen, 'modell#1');

    // Solange geliehen, darf nichts freigegeben werden.
    expect(await h.halter.freigebenWennUnbenutzt(), isFalse);

    h.halter.zurueckgeben();
    expect(await h.halter.freigebenWennUnbenutzt(), isTrue);
    expect(h.verlauf, ['laden#1', 'entsorgen modell#1']);
  });

  test('mehrfaches Zurückgeben zählt nicht ins Minus', () async {
    final h = baueHalter();
    await h.halter.leihen();
    h.halter.zurueckgeben();
    h.halter.zurueckgeben(); // versehentlich doppelt
    h.halter.zurueckgeben();
    expect(h.halter.nutzer, 0,
        reason: 'ein negativer Zähler würde spätere Leihen ungeschützt lassen');
  });

  test('ohne installierte Dateien passiert nichts', () async {
    final h = baueHalter(installiert: false);
    expect(await h.halter.mit((m) async => m), isNull);
    expect(await h.halter.leihen(), isNull);
    expect(h.verlauf, isEmpty, reason: 'es gibt nichts zu laden');
    expect(h.halter.istGeladen, isFalse);
  });

  test('der Zähler bleibt sauber, wenn die Arbeit wirft', () async {
    final h = baueHalter();
    await expectLater(
      h.halter.mit<void>((m) async => throw StateError('Inferenz kaputt')),
      throwsStateError,
    );
    expect(h.halter.nutzer, 0,
        reason: 'sonst liesse sich das Modell nie wieder freigeben');
    expect(await h.halter.freigebenWennUnbenutzt(), isTrue);
  });

  test('eine fehlgeschlagene Ladung blockiert spätere Versuche nicht', () async {
    var versuch = 0;
    final halter = ModellHalter<String>(
      name: 'wacklig',
      installiert: true,
      laden: () async {
        versuch++;
        if (versuch == 1) throw StateError('Datei beschädigt');
        return 'modell';
      },
      entsorgen: (_) async {},
    );

    await expectLater(halter.mit((m) async => m), throwsStateError);
    expect(halter.istGeladen, isFalse);

    // Zweiter Anlauf muss durchkommen.
    expect(await halter.mit((m) async => m), 'modell');
    expect(versuch, 2);
  });
}

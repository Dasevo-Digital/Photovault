import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/auswertungen.dart';
import 'package:photo_vault/state/library_state.dart';

/// Die Hintergrundanalyse läuft nie zweimal nebeneinander (#433). Ihre
/// Sperre griff erst mit dem ersten Stand; davor liegen Sekunden, in denen
/// jeder weitere Aufruf einen zweiten Durchgang startete.
void main() {
  test('ein zweiter Aufruf vor dem ersten Stand startet keinen zweiten '
      'Durchgang, sondern einen danach', () async {
    final lib = _Zaehlend();
    final erster = lib.starteHintergrundanalyse();
    // Die erste Stufe fragt noch ihre Kandidaten ab und lädt Modelle.
    await Future<void>.delayed(Duration.zero);
    expect(lib.analyseLaeuft, isTrue, reason: 'läuft ab dem Aufruf');
    expect(lib.analyse, isNull, reason: 'noch ohne Stand');

    await lib.starteHintergrundanalyse();
    await Future<void>.delayed(Duration.zero);
    expect(
      lib.aufrufe[Analysestufe.values.first],
      1,
      reason: 'bisher lief hier ein zweiter Durchgang daneben',
    );

    lib.weiter.complete();
    await erster;
    // Der angefragte zweite Durchgang folgt danach, nicht daneben.
    for (var i = 0; i < 100 && lib.analyseLaeuft; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(lib.analyseLaeuft, isFalse);
    expect(lib.aufrufe[Analysestufe.values.first], 2);
    expect(lib.gleichzeitigHoechstens, 1);
  });

  test('ein abgebrochener Durchgang holt nichts nach', () async {
    final lib = _Zaehlend();
    final erster = lib.starteHintergrundanalyse();
    await Future<void>.delayed(Duration.zero);
    await lib.starteHintergrundanalyse();
    lib.brichHintergrundanalyseAb();
    lib.weiter.complete();
    await erster;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(lib.aufrufe[Analysestufe.values.first], 1);
  });
}

class _Zaehlend extends LibraryState {
  final weiter = Completer<void>();
  final aufrufe = <Analysestufe, int>{};
  var _laufend = 0;
  var gleichzeitigHoechstens = 0;

  @override
  Auswertungen get auswertungen => _Auswertungen(this);
}

class _Auswertungen implements Auswertungen {
  _Auswertungen(this.lib);
  final _Zaehlend lib;

  @override
  Stream<ImportProgress> stufe(Analysestufe stufe) async* {
    lib.aufrufe[stufe] = (lib.aufrufe[stufe] ?? 0) + 1;
    if (stufe != Analysestufe.values.first) return;
    lib._laufend++;
    if (lib._laufend > lib.gleichzeitigHoechstens) {
      lib.gleichzeitigHoechstens = lib._laufend;
    }
    try {
      // Wie die echte Stufe: erst Kandidaten und Modelle, dann Stände.
      await lib.weiter.future;
      yield ImportProgress(1, 1);
    } finally {
      lib._laufend--;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

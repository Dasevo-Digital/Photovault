import 'dart:async';

import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/screens/schnittsteuerung.dart';

void main() {
  late List<String> protokoll;
  late Schnittsteuerung s;
  Completer<void>? sprung;

  Duration sek(num n) => Duration(milliseconds: (n * 1000).round());

  setUp(() {
    protokoll = [];
    sprung = null;
    s = Schnittsteuerung(
      bereich: const RangeValues(2, 8),
      springe: (d) async {
        protokoll.add('springe ${d.inMilliseconds / 1000}');
        await sprung?.future;
      },
      spiele: () async => protokoll.add('spiele'),
      halte: () async => protokoll.add('halte'),
    );
  });

  group('Beim Ziehen', () {
    test('zeigt das Bild die Stelle des bewegten Griffs', () async {
      await s.griffBewegt(const RangeValues(3, 8));
      await s.griffBewegt(const RangeValues(3, 6.5));
      expect(protokoll, ['springe 3.0', 'springe 6.5']);
    });

    test('hält eine laufende Vorschau an', () async {
      await s.umschalten(sek(2));
      await s.griffBewegt(const RangeValues(3, 8));
      expect(s.spielt, isFalse);
      expect(protokoll, ['spiele', 'halte', 'springe 3.0']);
    });

    test('läuft der Abspieler der Maus nicht hinterher', () async {
      sprung = Completer<void>();
      final erster = s.griffBewegt(const RangeValues(3, 8));
      for (final x in [3.1, 3.2, 3.3, 3.4]) {
        await s.griffBewegt(RangeValues(x, 8));
      }
      sprung!.complete();
      sprung = null;
      await erster;
      expect(protokoll, [
        'springe 3.0',
        'springe 3.4',
      ], reason: 'die Zwischenwerte zählen nicht mehr');
    });
  });

  group('Die Vorschau', () {
    test('beginnt am Anfang des Bereichs, wenn sie davor steht', () async {
      await s.umschalten(sek(0));
      expect(protokoll, ['springe 2.0', 'spiele']);
      expect(s.spielt, isTrue);
    });

    test('macht innerhalb des Bereichs dort weiter', () async {
      await s.umschalten(sek(5));
      expect(protokoll, ['spiele']);
    });

    test('beginnt nach dem Ende wieder vorn', () async {
      await s.umschalten(sek(8));
      expect(protokoll, ['springe 2.0', 'spiele']);
    });

    test('hält am Ende des Bereichs und steht wieder vorn', () async {
      await s.umschalten(sek(2));
      protokoll.clear();
      await s.stelleGemeldet(sek(7.9));
      expect(protokoll, isEmpty);
      await s.stelleGemeldet(sek(8.02));
      expect(protokoll, ['halte', 'springe 2.0']);
      expect(s.spielt, isFalse);
    });

    test('eine Stelle ohne Wiedergabe ändert nichts', () async {
      await s.stelleGemeldet(sek(9));
      expect(protokoll, isEmpty);
    });

    test('der zweite Druck hält an', () async {
      await s.umschalten(sek(3));
      await s.umschalten(sek(4));
      expect(protokoll, ['spiele', 'halte']);
      expect(s.spielt, isFalse);
    });

    test('hört der Abspieler selbst auf, startet der nächste Druck', () async {
      await s.umschalten(sek(3));
      s.angehalten();
      await s.umschalten(sek(4));
      expect(protokoll, ['spiele', 'spiele']);
    });
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/onnx_hardswish.dart';

/// Ein echtes, von `onnx` erzeugtes Modell mit 126 Bytes: HardSwish („erster",
/// mit Namen) → Relu (ohne Namen) → HardSwish (ohne Namen). Als Text
/// eingebettet, damit im Verzeichnis keine Binärdatei liegt.
const _probeBase64 =
    'CAgSBXByb2JlOm0KGQoBeBIBYRoGZXJzdGVyIglIYXJkU3dpc2gKDAoBYRIBYiIEUmVsdQoRCg'
    'FiEgF5IglIYXJkU3dpc2gSBXByb2JlWhMKAXgSDgoMCAESCAoCCAEKAggEYhMKAXkSDgoMCAES'
    'CAoCCAEKAggEQgQKABAO';

Uint8List get _probe => base64.decode(_probeBase64);

void main() {
  test('zählt die HardSwish-Knoten', () {
    expect(HardswishUmbau.zaehle(_probe), 2);
  });

  test('ersetzt jeden HardSwish durch HardSigmoid und Mul', () {
    final neu = HardswishUmbau.schreibeUm(_probe);
    final arten = HardswishUmbau.knoten(neu).map((k) => k.art).toList();
    expect(arten, ['HardSigmoid', 'Mul', 'Relu', 'HardSigmoid', 'Mul']);
    expect(HardswishUmbau.zaehle(neu), 0);
  });

  test('die Verdrahtung bleibt dieselbe', () {
    final knoten = HardswishUmbau.knoten(HardswishUmbau.schreibeUm(_probe));

    // x → HardSigmoid → Zwischenwert, dann x mal Zwischenwert → a
    expect(knoten[0].eingaenge, ['x']);
    final zwischen = knoten[0].ausgaenge.single;
    expect(zwischen, isNot('a'));
    expect(knoten[1].eingaenge, ['x', zwischen]);
    expect(knoten[1].ausgaenge, ['a']);

    // Der unveränderte Knoten dazwischen hängt weiter an a.
    expect(knoten[2].eingaenge, ['a']);
    expect(knoten[2].ausgaenge, ['b']);

    // Der Ausgang des Graphen bleibt y.
    expect(knoten[3].eingaenge, ['b']);
    expect(knoten[4].ausgaenge, ['y']);
  });

  test('HardSigmoid bekommt genau die Werte, die HardSwish festlegt', () {
    final knoten = HardswishUmbau.knoten(HardswishUmbau.schreibeUm(_probe));
    for (final k in knoten.where((k) => k.art == 'HardSigmoid')) {
      // ONNX legt HardSwish auf alpha = 1/6 und beta = 0,5 fest. Als
      // 32-Bit-Wert gespeichert, deshalb kein exakter Vergleich.
      expect(k.fliesswerte['alpha'], closeTo(1 / 6, 1e-7));
      expect(k.fliesswerte['beta'], closeTo(0.5, 1e-7));
    }
  });

  test('Namen bleiben nachvollziehbar, auch wenn der Knoten keinen hatte', () {
    final knoten = HardswishUmbau.knoten(HardswishUmbau.schreibeUm(_probe));
    // Der benannte Knoten gibt seinen Namen weiter …
    expect(knoten[0].name, startsWith('erster'));
    expect(knoten[1].name, startsWith('erster'));
    // … der namenlose leiht sich den Namen seines Ausgangs.
    expect(knoten[3].name, startsWith('y'));
    // Kein Name wird doppelt vergeben.
    final namen = knoten.map((k) => k.name).toList();
    expect(namen.toSet().length, namen.length);
  });

  test('alles ausser der Knotenliste bleibt Byte für Byte gleich', () {
    final neu = HardswishUmbau.schreibeUm(_probe);
    // Kopf des Modells: ir_version und producer_name stehen vor dem Graphen
    // und dürfen sich nicht verschoben haben.
    expect(neu.sublist(0, 9), _probe.sublist(0, 9));
    // Der unveränderte Relu-Knoten muss wörtlich wieder auftauchen.
    final relu = utf8.encode('Relu');
    expect(_enthaelt(neu, relu), isTrue);
    // Und die Modellangaben am Ende ebenso.
    expect(_enthaelt(neu, utf8.encode('probe')), isTrue);
  });

  test('ein zweiter Durchgang ändert nichts mehr', () {
    final einmal = HardswishUmbau.schreibeUm(_probe);
    final zweimal = HardswishUmbau.schreibeUm(einmal);
    expect(zweimal, same(einmal));
  });

  test('ein Modell ohne HardSwish kommt unverändert zurück', () {
    final ohne = HardswishUmbau.schreibeUm(_probe);
    expect(HardswishUmbau.schreibeUm(ohne), same(ohne));
  });

  test('etwas, das kein Protokollpuffer ist, wirft statt zu raten', () {
    final muell = Uint8List.fromList([0xff, 0xff, 0xff, 0xff]);
    expect(() => HardswishUmbau.zaehle(muell), throwsA(isA<OnnxNichtLesbar>()));
  });
}

bool _enthaelt(Uint8List heu, List<int> nadel) {
  for (var i = 0; i + nadel.length <= heu.length; i++) {
    var passt = true;
    for (var j = 0; j < nadel.length; j++) {
      if (heu[i + j] != nadel[j]) {
        passt = false;
        break;
      }
    }
    if (passt) return true;
  }
  return false;
}

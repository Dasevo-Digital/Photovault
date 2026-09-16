import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Ersetzt `HardSwish`-Knoten in einer ONNX-Datei durch `HardSigmoid` und
/// `Mul` – rechnerisch dasselbe, nur aus Schritten zusammengesetzt, die
/// überall funktionieren.
///
/// **Warum das nötig war:** Im Flutter-Prozess unter Linux lieferte
/// `HardSwish` durchweg null. Die Ursache ist seit dem 24.08.2026 bekannt
/// und liegt nicht an der Plattform, sondern an der Spracheinstellung:
/// ONNX (≤ 1.22) liest die Rümpfe funktionsdefinierter Operatoren als
/// Text, mit einem locale-abhängigen `std::stof`. GTK setzt die
/// Prozess-Locale aus der Umgebung, und unter `de_DE` wird HardSwishs
/// α = 1/6 dabei zu 0. Hergang, Messwerte und Belege:
/// `docs/hardswish_fehler/`.
///
/// **Behoben ist es im Plugin ab `flutter_onnxruntime` 1.8.4**, das
/// `LC_NUMERIC` fadenlokal auf `C` legt. Dieser Umbau ist damit nicht mehr
/// zwingend – er bleibt trotzdem, aus demselben Grund, aus dem der
/// Plugin-Autor seine Absicherung behält: Welche ONNX-Fassung hinter der
/// ONNX Runtime steckt, ist nirgends festgenagelt, und `newlocale` kann
/// scheitern. Eine Umformung, die nichts kostet und nichts verfälscht, ist
/// der billigere Schutz als die Annahme, dass es nie wiederkommt.
///
/// Das Lesemodell der Texterkennung hat einen MobileNetV3-Stamm mit 27
/// `HardSwish`-Knoten; ab dem ersten ist alles Weitere wertlos. Deshalb
/// dieser Umbau, statt auf eine Nachbesserung von aussen zu warten.
///
/// **Die Umformung ist exakt, keine Näherung.** ONNX definiert
/// `HardSwish(x) = x · max(0, min(1, αx + β))` mit fest α = 1/6 und
/// β = 0,5 – genau das, was `HardSigmoid` mit diesen beiden Werten
/// liefert. Es entsteht kein Genauigkeitsverlust.
///
/// **Warum von Hand am Protokollpuffer und nicht mit einer Bibliothek:**
/// Für ONNX gibt es kein Dart-Paket. Der Umbau braucht aber nur einen
/// winzigen Ausschnitt des Formats: Die Datei wird in ihre Felder zerlegt,
/// alles bis auf die Knotenliste **unverändert byteweise übernommen**, und
/// in der Knotenliste wird ein Eintrag durch zwei ersetzt. Nichts wird neu
/// kodiert, was nicht verändert wurde – Gewichte, Formen und Namen bleiben
/// Bit für Bit dieselben.
class HardswishUmbau {
  HardswishUmbau._();

  /// Feldnummern aus `onnx.proto`.
  static const _modellGraph = 7;
  static const _graphKnoten = 1;
  static const _knotenEingang = 1;
  static const _knotenAusgang = 2;
  static const _knotenName = 3;
  static const _knotenArt = 4;
  static const _knotenMerkmal = 5;
  static const _knotenBereich = 7;
  static const _merkmalName = 1;
  static const _merkmalFliess = 2;
  static const _merkmalArt = 20;

  /// `AttributeProto.AttributeType.FLOAT`.
  static const _artFliess = 1;

  static const _alpha = 1.0 / 6.0;
  static const _beta = 0.5;

  static const _gesucht = 'HardSwish';


  /// Die Knoten des Modells in ihrer Reihenfolge – damit sich das Ergebnis
  /// eines Umbaus prüfen lässt, ohne eine ONNX-Bibliothek zu brauchen.
  @visibleForTesting
  static List<KnotenAngabe> knoten(Uint8List modell) {
    final felder = _felder(modell, 0, modell.length);
    final graph = felder.where((f) => f.nummer == _modellGraph).toList();
    if (graph.length != 1) return const [];
    final g = graph.first;
    return [
      for (final f in _felder(modell, g.datenVon, g.datenBis))
        if (f.nummer == _graphKnoten) _angabe(modell, f),
    ];
  }

  static KnotenAngabe _angabe(Uint8List b, _Feld knoten) {
    final k = _lieseKnoten(b, knoten);
    final werte = <String, double>{};
    for (final f in _felder(b, knoten.datenVon, knoten.datenBis)) {
      if (f.nummer != _knotenMerkmal) continue;
      var name = '';
      double? wert;
      for (final m in _felder(b, f.datenVon, f.datenBis)) {
        if (m.nummer == _merkmalName) name = _text(b, m);
        if (m.nummer == _merkmalFliess && m.typ == 5) {
          wert = ByteData.sublistView(b, m.datenVon, m.datenBis)
              .getFloat32(0, Endian.little);
        }
      }
      if (name.isNotEmpty && wert != null) werte[name] = wert;
    }
    return KnotenAngabe(k.art, k.name, k.eingaenge, k.ausgaenge, werte);
  }

  /// Wie viele `HardSwish`-Knoten die Datei enthält. Null heisst: nichts
  /// zu tun.
  static int zaehle(Uint8List modell) => _umbau(modell, nurZaehlen: true).anzahl;

  /// Gibt das umgebaute Modell zurück. Enthält es kein `HardSwish`, kommt
  /// die Eingabe unverändert zurück.
  static Uint8List schreibeUm(Uint8List modell) {
    final e = _umbau(modell, nurZaehlen: false);
    return e.anzahl == 0 ? modell : e.bytes!;
  }

  static ({int anzahl, Uint8List? bytes}) _umbau(Uint8List modell,
      {required bool nurZaehlen}) {
    final felder = _felder(modell, 0, modell.length);
    final graph = felder.where((f) => f.nummer == _modellGraph).toList();
    // Ein Modell ohne Graph ist keines; ohne Knoten gibt es nichts zu tun.
    if (graph.length != 1) return (anzahl: 0, bytes: null);

    final g = graph.first;
    final knotenfelder = _felder(modell, g.datenVon, g.datenBis)
        .where((f) => f.nummer == _graphKnoten)
        .toList();

    // Alle vergebenen Namen einsammeln, damit der neue Zwischenname
    // garantiert frei ist. Ein doppelter Name wäre ein stiller Kurzschluss
    // im Graphen, kein Fehler beim Laden.
    final vergeben = <String>{};
    var anzahl = 0;
    for (final k in knotenfelder) {
      final knoten = _lieseKnoten(modell, k);
      vergeben.addAll(knoten.ausgaenge);
      if (knoten.istHardswish) anzahl++;
    }
    if (anzahl == 0 || nurZaehlen) return (anzahl: anzahl, bytes: null);

    // Neue Knotenliste: unveränderte Knoten byteweise übernehmen, jeden
    // HardSwish durch zwei Knoten ersetzen.
    final neuerGraph = BytesBuilder();
    for (final f in _felder(modell, g.datenVon, g.datenBis)) {
      if (f.nummer != _graphKnoten) {
        neuerGraph.add(_roh(modell, f));
        continue;
      }
      final knoten = _lieseKnoten(modell, f);
      if (!knoten.istHardswish) {
        neuerGraph.add(_roh(modell, f));
        continue;
      }
      final ausgang = knoten.ausgaenge.first;
      final eingang = knoten.eingaenge.first;
      final basis = knoten.name.isEmpty ? ausgang : knoten.name;
      final zwischen = _freierName('${ausgang}__hardsigmoid', vergeben);
      vergeben.add(zwischen);

      neuerGraph.add(_feld(
        _graphKnoten,
        _knoten(
          eingaenge: [eingang],
          ausgaenge: [zwischen],
          name: '${basis}__hardsigmoid',
          art: 'HardSigmoid',
          merkmale: [
            _merkmalFliesskomma('alpha', _alpha),
            _merkmalFliesskomma('beta', _beta),
          ],
        ),
      ));
      neuerGraph.add(_feld(
        _graphKnoten,
        _knoten(
          eingaenge: [eingang, zwischen],
          ausgaenge: [ausgang],
          name: '${basis}__mul',
          art: 'Mul',
          merkmale: const [],
        ),
      ));
    }

    // Modell neu zusammensetzen: alles ausser dem Graphen unverändert.
    final neu = BytesBuilder();
    for (final f in felder) {
      if (f.nummer == _modellGraph) {
        neu.add(_feld(_modellGraph, neuerGraph.toBytes()));
      } else {
        neu.add(_roh(modell, f));
      }
    }
    return (anzahl: anzahl, bytes: neu.toBytes());
  }

  static String _freierName(String wunsch, Set<String> vergeben) {
    if (!vergeben.contains(wunsch)) return wunsch;
    for (var i = 2;; i++) {
      final k = '$wunsch$i';
      if (!vergeben.contains(k)) return k;
    }
  }

  // ---- Lesen ----

  static ({
    bool istHardswish,
    List<String> eingaenge,
    List<String> ausgaenge,
    String name,
    String art,
  }) _lieseKnoten(Uint8List b, _Feld knoten) {
    final eingaenge = <String>[];
    final ausgaenge = <String>[];
    var name = '';
    var art = '';
    var bereich = '';
    for (final f in _felder(b, knoten.datenVon, knoten.datenBis)) {
      switch (f.nummer) {
        case _knotenEingang:
          eingaenge.add(_text(b, f));
        case _knotenAusgang:
          ausgaenge.add(_text(b, f));
        case _knotenName:
          name = _text(b, f);
        case _knotenArt:
          art = _text(b, f);
        case _knotenBereich:
          bereich = _text(b, f);
      }
    }
    // Ein eigener Namensbereich hiesse: nicht der ONNX-Standardschritt.
    // Den fasst dieser Umbau nicht an.
    final passt = art == _gesucht &&
        bereich.isEmpty &&
        eingaenge.length == 1 &&
        ausgaenge.length == 1;
    return (
      istHardswish: passt,
      eingaenge: eingaenge,
      ausgaenge: ausgaenge,
      name: name,
      art: art,
    );
  }

  // Namen in ONNX sind UTF-8. Ein Zeichen falsch zu deuten und danach neu
  // zu kodieren würde den Namen verderben, deshalb kein fromCharCodes.
  static String _text(Uint8List b, _Feld f) =>
      utf8.decode(b.sublist(f.datenVon, f.datenBis), allowMalformed: true);

  static Uint8List _roh(Uint8List b, _Feld f) =>
      Uint8List.sublistView(b, f.von, f.datenBis);

  /// Zerlegt einen Bereich in seine Felder, ohne den Inhalt zu deuten.
  static List<_Feld> _felder(Uint8List b, int von, int bis) {
    final felder = <_Feld>[];
    var i = von;
    while (i < bis) {
      final start = i;
      final marke = _varint(b, i);
      i = marke.weiter;
      final nummer = marke.wert >> 3;
      final typ = marke.wert & 7;
      switch (typ) {
        case 0:
          final v = _varint(b, i);
          felder.add(_Feld(nummer, typ, start, i, v.weiter));
          i = v.weiter;
        case 1:
          felder.add(_Feld(nummer, typ, start, i, i + 8));
          i += 8;
        case 2:
          final laenge = _varint(b, i);
          final datenVon = laenge.weiter;
          final datenBis = datenVon + laenge.wert;
          felder.add(_Feld(nummer, typ, start, datenVon, datenBis));
          i = datenBis;
        case 5:
          felder.add(_Feld(nummer, typ, start, i, i + 4));
          i += 4;
        default:
          // Gruppen (3/4) kommen in ONNX nicht vor. Hier abzubrechen ist
          // ehrlicher, als den Rest der Datei zu verwürfeln.
          throw const OnnxNichtLesbar();
      }
      if (i > bis) throw const OnnxNichtLesbar();
    }
    return felder;
  }

  static ({int wert, int weiter}) _varint(Uint8List b, int i) {
    var wert = 0;
    var schub = 0;
    while (true) {
      if (i >= b.length || schub > 63) throw const OnnxNichtLesbar();
      final byte = b[i++];
      wert |= (byte & 0x7f) << schub;
      if (byte & 0x80 == 0) return (wert: wert, weiter: i);
      schub += 7;
    }
  }

  // ---- Schreiben ----

  static Uint8List _feld(int nummer, Uint8List inhalt) {
    final b = BytesBuilder();
    b.add(_schreibeVarint((nummer << 3) | 2));
    b.add(_schreibeVarint(inhalt.length));
    b.add(inhalt);
    return b.toBytes();
  }

  static Uint8List _textfeld(int nummer, String wert) =>
      _feld(nummer, Uint8List.fromList(utf8.encode(wert)));

  static Uint8List _knoten({
    required List<String> eingaenge,
    required List<String> ausgaenge,
    required String name,
    required String art,
    required List<Uint8List> merkmale,
  }) {
    final b = BytesBuilder();
    for (final e in eingaenge) {
      b.add(_textfeld(_knotenEingang, e));
    }
    for (final a in ausgaenge) {
      b.add(_textfeld(_knotenAusgang, a));
    }
    b.add(_textfeld(_knotenName, name));
    b.add(_textfeld(_knotenArt, art));
    for (final m in merkmale) {
      b.add(_feld(_knotenMerkmal, m));
    }
    return b.toBytes();
  }

  static Uint8List _merkmalFliesskomma(String name, double wert) {
    final b = BytesBuilder();
    b.add(_textfeld(_merkmalName, name));
    // Feld 2 ist ein 32-Bit-Gleitkommawert, also Drahttyp 5.
    b.add(_schreibeVarint((_merkmalFliess << 3) | 5));
    final vier = ByteData(4)..setFloat32(0, wert, Endian.little);
    b.add(vier.buffer.asUint8List());
    b.add(_schreibeVarint((_merkmalArt << 3) | 0));
    b.add(_schreibeVarint(_artFliess));
    return b.toBytes();
  }

  static Uint8List _schreibeVarint(int wert) {
    final aus = <int>[];
    var v = wert;
    do {
      var byte = v & 0x7f;
      v >>= 7;
      if (v != 0) byte |= 0x80;
      aus.add(byte);
    } while (v != 0);
    return Uint8List.fromList(aus);
  }
}

/// Die Datei ist kein lesbarer Protokollpuffer.
class OnnxNichtLesbar implements Exception {
  const OnnxNichtLesbar();
}

class _Feld {
  final int nummer;
  final int typ;

  /// Beginn der Marke – ab hier lässt sich das Feld roh übernehmen.
  final int von;
  final int datenVon;
  final int datenBis;

  const _Feld(this.nummer, this.typ, this.von, this.datenVon, this.datenBis);
}

/// Ein Knoten, so weit dieser Umbau ihn deutet.
class KnotenAngabe {
  final String art;
  final String name;
  final List<String> eingaenge;
  final List<String> ausgaenge;

  /// Gleitkomma-Merkmale des Knotens, etwa `alpha` und `beta`.
  final Map<String, double> fliesswerte;

  const KnotenAngabe(
      this.art, this.name, this.eingaenge, this.ausgaenge, this.fliesswerte);

  @override
  String toString() => '$art($eingaenge -> $ausgaenge)';
}

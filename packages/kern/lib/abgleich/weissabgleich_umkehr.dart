/// Befehle aus der Zeit vor Schema 102 in die heutige Bedeutung der
/// Temperatur bringen (#466).
library;

import '../db/database.dart';
import '../services/weissabgleich.dart';
import 'befehlsbasis.dart';

/// Die Befehle, deren Werte eine Temperatur als Spalte `temperature`
/// tragen, und unter welchem Schlüssel die Zeile steht.
///
/// `entwicklungsvarianteSpeichern` fehlt mit Absicht: Ein Variantenstand
/// trägt seine Fassung selbst und wird beim Lesen umgerechnet
/// (`Entwicklungsstand.decode`).
const _zeilenMitTemperatur = {
  'entwicklungSpeichern': 'einstellungen',
  'maskeneinstellungAendern': 'aenderung',
  'entwicklungsvorgabeSpeichern': 'vorgabe',
};

Map<String, Object?> _zeileUmgerechnet(Map<String, Object?> zeile) {
  final t = zeile['temperature'];
  if (t is! num) return zeile;
  return {
    ...zeile,
    'temperature': temperaturAusFruehererBedeutung(t.toDouble()),
  };
}

/// [auftrag] (`{'befehl': Befehl.alsJson(), 'basis': [Befehlsbasis.vorschauJson()]}`,
/// wie er verschlüsselt in `pv_ausgang` und `pv_abgleichsfaelle` liegt) mit
/// der Temperatur in der heutigen Bedeutung, und die Basis aus
/// [basisSpalte] (die unverschlüsselte Spalte `basis` von `pv_ausgang`,
/// gleiche Reihenfolge) passend dazu.
///
/// Umgerechnet werden die Werte des Befehls – sie wendet der Server an und
/// die Kopie beim Wiederholen ihrer Vorwegnahme – und in der Basis das
/// Gewollte samt dessen Prüfsumme (`nachher`): Hatte der Server den Befehl
/// vor seiner eigenen Umrechnung schon ausgeführt und nur die Bestätigung
/// ging verloren, erkennt er ihn so wieder. Die Prüfsumme des Stands davor
/// (`vorher`) lässt sich nicht nachrechnen, die Zeile selbst liegt nirgends
/// mehr. Hat der Server die Zeile umgerechnet, meldet er deshalb einen
/// Konflikt, und der Fall zeigt die umgerechneten Werte zum erneuten
/// Anwenden – nie die alte Zahl mit neuer Bedeutung.
///
/// Wer das aufruft, muss wissen, dass der Auftrag noch aus der Zeit vor
/// Schema 102 stammt (siehe die Marke `pv_weissabgleich_umkehr`).
({Map<String, Object?> auftrag, List<Object?>? basisSpalte})
auftragInHeutigerBedeutung(
  Map<String, Object?> auftrag, {
  List<Object?>? basisSpalte,
}) {
  var befehl = (auftrag['befehl'] as Map?)?.cast<String, Object?>();
  final schluessel = _zeilenMitTemperatur[befehl?['art']];
  if (befehl != null && schluessel != null) {
    final werte = (befehl['werte'] as Map).cast<String, Object?>();
    final zeile = (werte[schluessel] as Map?)?.cast<String, Object?>();
    if (zeile != null) {
      befehl = {
        ...befehl,
        'werte': {...werte, schluessel: _zeileUmgerechnet(zeile)},
      };
    }
  }
  final basis = [...(auftrag['basis'] as List? ?? const [])];
  final spalte = basisSpalte == null ? null : [...basisSpalte];
  for (var i = 0; i < basis.length; i++) {
    final b = (basis[i] as Map).cast<String, Object?>();
    final gewollt = (b['gewollt'] as Map?)?.cast<String, Object?>();
    if (!Migrationsschritte.temperaturTabellen.contains(b['t']) ||
        gewollt == null ||
        gewollt['temperature'] is! num) {
      continue;
    }
    final neu = _zeileUmgerechnet(gewollt);
    final nachher = Befehlsbasis.hash(
      neu,
      (b['spalten'] as List).cast<String>(),
    );
    basis[i] = {...b, 'gewollt': neu, 'nachher': nachher};
    if (spalte != null && i < spalte.length) {
      final s = (spalte[i] as Map).cast<String, Object?>();
      if (s['t'] == b['t'] && '${s['s']}' == '${b['s']}') {
        spalte[i] = {...s, 'nachher': nachher};
      }
    }
  }
  return (
    auftrag: {...auftrag, 'befehl': ?befehl, 'basis': basis},
    basisSpalte: spalte,
  );
}

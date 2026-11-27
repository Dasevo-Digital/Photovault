/// Das Ergebnis eines Zusammenfügens (#498) als neue Aufnahme ablegen:
/// Angaben der Quellen ins JPEG, einlesen, und mit den Quellen zu einem
/// Variantenstapel ordnen, in dem das Ergebnis vorn liegt.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../jpeg_angaben.dart';
import 'zusammenfuegen.dart';

/// Ob [a] als Quelle taugt: ein Foto, nicht gesperrt, nicht im Papierkorb.
///
/// Gesperrte Fotos bleiben draussen, auch wenn sie in einer Auswahl
/// auftauchen: Ihr Original ist verschlüsselt, und das Ergebnis läge im
/// Klartext in der Bibliothek – mit genau dem Inhalt, der gesperrt ist.
bool alsQuelleGeeignet(AssetData a) =>
    a.type == 'IMAGE' && !a.isLocked && !a.isTrashed;

/// Die Quelle, deren Aufnahmezeit, Kamera und Ort das Ergebnis trägt: die
/// mittlere nach der Aufnahmezeit. So steht ein HDR in der Zeitleiste
/// mitten in seiner Reihe und ein Panorama mitten in seinem Schwenk.
AssetData leitquelle(List<AssetData> quellen) {
  final reihe = [...quellen]
    ..sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
  return reihe[(reihe.length - 1) ~/ 2];
}

/// Der Dateiname des Ergebnisses: der Name der Leitquelle mit `-HDR` bzw.
/// `-Panorama`. Kein Zusatz, den die Formatstapel als „dieselbe Aufnahme
/// in einem anderen Format" lesen (siehe `formatstamm`) – sonst hinge das
/// Ergebnis plötzlich am RAW seiner Leitquelle.
String fuegeDateiname(AssetData leit, Fuegeart art) {
  final stamm = p
      .basenameWithoutExtension(leit.originalFileName)
      .replaceAll(RegExp(r'[/\\]'), '_');
  final zusatz = art == Fuegeart.hdr ? 'HDR' : 'Panorama';
  return '${stamm.isEmpty ? 'Foto' : stamm}-$zusatz.jpg';
}

/// [jpeg] mit Aufnahmezeit und Kamera der Leitquelle und dem ersten
/// bekannten Ort unter den Quellen (die Leitquelle zuerst). Damit liest
/// der Import – am Rechner wie am Server – dieselben Angaben ein, und sie
/// reisen mit der Datei, wenn sie exportiert wird.
Uint8List mitAngabenDerQuellen(Uint8List jpeg, List<AssetData> quellen) {
  final leit = leitquelle(quellen);
  final ort = [
    leit,
    ...quellen,
  ].where((a) => a.latitude != null && a.longitude != null).firstOrNull;
  final traeger = ort == null
      ? leit
      : leit.copyWith(
          latitude: Value(ort.latitude),
          longitude: Value(ort.longitude),
        );
  return mitAufnahmeangaben(jpeg, traeger, mitOrt: ort != null);
}

/// Legt [jpeg] als neue Aufnahme an und ordnet sie mit den [quellen] zu
/// einem Variantenstapel, in dem sie vorn liegt. Gibt ihre Kennung.
///
/// [einlesen] bringt die Datei in die Bibliothek – am Rechner über den
/// Import, verbunden über das Hochladen zum Server – und gibt die neue
/// Kennung, oder `null`, wenn genau dieses Bild schon da ist.
Future<String> legeZusammengefuegtesAb({
  required AppDatabase db,
  required List<AssetData> quellen,
  required Uint8List jpeg,
  required Fuegeart art,
  required Future<String?> Function(Uint8List jpeg, String name) einlesen,
}) async {
  final leit = leitquelle(quellen);
  final id = await einlesen(
    mitAngabenDerQuellen(jpeg, quellen),
    fuegeDateiname(leit, art),
  );
  if (id == null) throw StateError('pv_fuegen_schon_da');
  await stapleMitQuellen(db, id, quellen, leit);
  return id;
}

/// Ordnet [ergebnis] und [quellen] zu einem Variantenstapel mit
/// [ergebnis] vorn.
///
/// **Liegen Quellen schon in Stapeln**, kommen deren übrige Glieder mit
/// – sonst blieben halbe Stapel zurück, deren Titel fehlt oder deren
/// Zählung nicht mehr stimmt. Ein einzelner gewöhnlicher Variantenstapel
/// behält dabei seine Kennung; ein Formatstapel (RAW neben JPEG) oder eine
/// Serie wird, wie beim Speichern einer Bearbeitung, ein gewöhnlicher
/// Variantenstapel.
///
/// **Erst mit dem bisherigen Titel, dann das Ergebnis nach vorn**
/// (`VariantenHauptbildSetzen`): So ziehen Alben, Favorit, Sterne und
/// Schlagwörter des bisher sichtbaren Fotos auf das Ergebnis um (#363).
/// Sonst verschwände das Foto aus seinem Album, sobald es hinter dem
/// Ergebnis liegt.
Future<void> stapleMitQuellen(
  AppDatabase db,
  String ergebnis,
  List<AssetData> quellen,
  AssetData leit,
) async {
  final aktuell = await db.assetsByIds([for (final q in quellen) q.id]);
  final stapel = <String>{
    for (final a in aktuell)
      if (a.stackId != null) a.stackId!,
  };
  final ids = <String>{for (final a in aktuell) a.id};
  final titelJeStapel = <String, String>{};
  for (final s in stapel) {
    for (final m in await db.assetsInStack(s)) {
      ids.add(m.id);
      if (m.isStackCover) titelJeStapel[s] = m.id;
    }
  }
  final leitJetzt = aktuell.where((a) => a.id == leit.id).firstOrNull ?? leit;
  final titel = switch (leitJetzt.stackId) {
    final String s => titelJeStapel[s] ?? leitJetzt.id,
    null => leitJetzt.id,
  };
  final einzeln = stapel.length == 1 ? stapel.first : null;
  final kennung =
      einzeln != null &&
          istVariantenstapel(einzeln) &&
          !istFormatstapel(einzeln)
      ? einzeln.substring(variantenstapelPraefix.length)
      : const Uuid().v4();
  await db.fuehreAus(VariantenBilden(kennung, [ergebnis, ...ids], titel));
  await db.fuehreAus(
    VariantenHauptbildSetzen(variantenstapelId(kennung), ergebnis),
  );
}

/// Das Ergebnis eines Zusammenfügens (#498) als neue Aufnahme ablegen:
/// Angaben der Quellen ins JPEG, einlesen, und mit den Quellen zu einem
/// Variantenstapel ordnen, in dem das Ergebnis vorn liegt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../db/database.dart';
import '../import_service.dart';
import '../jpeg_angaben.dart';
import '../storage_paths.dart';
import '../tresorreihe.dart';
import 'zusammenfuegen.dart';

/// Ob [a] als Quelle taugt: ein Foto, nicht gesperrt, nicht im Papierkorb.
///
/// Gesperrte Fotos bleiben draussen, auch wenn sie in einer Auswahl
/// auftauchen: Ihr Original ist verschlüsselt, und das Ergebnis läge im
/// Klartext in der Bibliothek – mit genau dem Inhalt, der gesperrt ist.
/// Geprüft wird beim Start und noch einmal beim Ablegen
/// ([legeZusammengefuegtesAb]).
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

/// Die Quelle, deren Ort das Ergebnis trägt: die Leitquelle, sonst die
/// erste der [quellen] mit einem Ort.
AssetData? ortsquelle(List<AssetData> quellen) => [
  leitquelle(quellen),
  ...quellen,
].where((a) => a.latitude != null && a.longitude != null).firstOrNull;

/// [jpeg] mit Aufnahmezeit, Zeitzone und Kamera der Leitquelle und dem
/// ersten bekannten Ort unter den Quellen (die Leitquelle zuerst). Damit
/// liest der Import – am Rechner wie am Server – dieselben Angaben ein, und
/// sie reisen mit der Datei, wenn sie exportiert wird.
Uint8List mitAngabenDerQuellen(Uint8List jpeg, List<AssetData> quellen) {
  final leit = leitquelle(quellen);
  final ort = ortsquelle(quellen);
  final traeger = ort == null
      ? leit
      : leit.copyWith(
          latitude: Value(ort.latitude),
          longitude: Value(ort.longitude),
        );
  return mitAufnahmeangaben(
    jpeg,
    traeger,
    mitOrt: ort != null,
    mitZeitversatz: true,
  );
}

/// Was beim Ablegen herauskam: die Aufnahme, ob sie neu angelegt wurde
/// (sonst gab es genau dieses Bild schon) und ob sie dafür aus dem
/// Papierkorb zurückgeholt wurde.
class Fuegeablage {
  const Fuegeablage(this.id, {this.neu = true, this.zurueckgeholt = false});

  final String id;
  final bool neu;
  final bool zurueckgeholt;
}

/// Legt [jpeg] in dieser Bibliothek als neue Aufnahme an und ordnet sie mit
/// den [quellen] zu einem Variantenstapel, in dem sie vorn liegt.
///
/// **In der [inTresorreihe] (#430).** Gerechnet wurde mit dem Stand vom
/// Beginn, womöglich minutenlang. Wurde eine Quelle seither gesperrt,
/// entstünde sonst eine Klartextkopie eines gesperrten Fotos, offen in der
/// Zeitleiste. Prüfen, Importieren und Einordnen laufen deshalb ohne ein
/// Sperren dazwischen; ist eine Quelle gesperrt, gelöscht oder im
/// Papierkorb, scheitert es mit [Fuegegrund.quelleGesperrt] bzw.
/// [Fuegegrund.quelleWeg] (die Stelle in [quellen]), und nichts ist
/// angelegt. Darin läuft nur der blosse Import – was er sonst anstösst
/// (Nachbearbeitung, Auswertung), reiht sich selbst in die Tresorreihe
/// ein und kommt deshalb erst danach, beim Aufrufer.
///
/// [abgebrochen] wird darin zuletzt gefragt: Wer abgebrochen hat, bekommt
/// `null` und keine Aufnahme.
///
/// Gibt es genau dieses Bild schon – das Ergebnis ist bei denselben Quellen
/// immer dasselbe –, siehe [_vorhandenes].
Future<Fuegeablage?> legeZusammengefuegtesAb({
  required AppDatabase db,
  required StoragePaths paths,
  required ImportService importe,
  required List<AssetData> quellen,
  required Uint8List jpeg,
  required Fuegeart art,
  bool Function()? abgebrochen,
}) => inTresorreihe(paths, () async {
  final frisch = await _offeneQuellen(db, quellen);
  if (abgebrochen?.call() ?? false) return null;
  final bytes = mitAngabenDerQuellen(jpeg, frisch);
  final ablage = await _mitDatei(bytes, frisch, art, (datei) async {
    final r = await importe.importFile(datei.path);
    return switch (r.outcome) {
      ImportOutcome.imported when r.assetId != null => Fuegeablage(r.assetId!),
      ImportOutcome.duplicateSkipped => await _vorhandenes(db, bytes),
      _ => throw Zusammenfuegefehler(
        Fuegegrund.einlesen,
        ursache: r.error ?? 'pv_import_gescheitert',
      ),
    };
  });
  await ordneZusammengefuegtesEin(db, ablage, frisch);
  return ablage;
});

/// Wie [legeZusammengefuegtesAb], für eine mit dem Server verbundene
/// Kopie: Die Datei geht über [hochladen] zum Server (der importiert sie
/// wie jeden Upload, prüft dabei ihre Prüfsumme und gibt die Kennung im
/// Kopf `pv-aufnahme` zurück, auch für ein Bild, das er schon hat),
/// [abholen] holt die neue Aufnahme in die Kopie, und die Befehle zum
/// Einordnen gehen wieder zum Server.
///
/// **Vorher frisch abgeglichen.** Verbunden lässt sich hier nicht sperren,
/// wohl aber an einem anderen Gerät. Darum holt [abholen] vor dem
/// Hochladen den Stand des Servers, und die Quellen werden daran geprüft
/// wie am Rechner. Ohne Tresorreihe: Es gibt hier kein Sperren, und das
/// Hochladen kann dauern.
Future<Fuegeablage?> legeZusammengefuegtesAmServerAb({
  required AppDatabase db,
  required List<AssetData> quellen,
  required Uint8List jpeg,
  required Fuegeart art,
  required Future<Map<String, String>> Function(
    File datei,
    Map<String, String> angaben,
  )
  hochladen,
  required Future<void> Function() abholen,
  bool Function()? abgebrochen,
}) async {
  await abholen();
  final frisch = await _offeneQuellen(db, quellen);
  if (abgebrochen?.call() ?? false) return null;
  final bytes = mitAngabenDerQuellen(jpeg, frisch);
  final leit = leitquelle(frisch);
  final ablage = await _mitDatei(bytes, frisch, art, (datei) async {
    final kopf = await hochladen(datei, {
      'filename': p.basename(datei.path),
      'sha256': sha256.convert(bytes).toString(),
      // Der Server setzt damit die Dateizeit; ohne EXIF-Zeit (bei einer
      // Kalenderdatierung) wird sie dort zur Aufnahmezeit.
      'geaendert': '${leit.fileCreatedAt.millisecondsSinceEpoch}',
    });
    final ausgang = kopf['pv-ausgang'];
    if (ausgang != 'imported' && ausgang != 'duplicateSkipped') {
      throw Zusammenfuegefehler(
        Fuegegrund.einlesen,
        ursache: Uri.decodeComponent(
          kopf['pv-fehler'] ?? ausgang ?? 'pv_import_gescheitert',
        ),
      );
    }
    await abholen();
    final id = kopf['pv-aufnahme'];
    final zeile = id == null ? null : await db.assetById(id);
    if (ausgang == 'imported' && zeile != null) return Fuegeablage(zeile.id);
    // Eine Dublette, oder die neue Zeile ist noch nicht da: am Inhalt
    // suchen.
    return _vorhandenes(db, bytes);
  });
  await ordneZusammengefuegtesEin(db, ablage, frisch);
  return ablage;
}

/// Die [quellen], wie sie jetzt sind – oder [Zusammenfuegefehler], wenn
/// eine gesperrt, gelöscht oder im Papierkorb ist.
Future<List<AssetData>> _offeneQuellen(
  AppDatabase db,
  List<AssetData> quellen,
) async {
  final jetzt = {
    for (final a in await db.assetsByIds([for (final q in quellen) q.id]))
      a.id: a,
  };
  for (var i = 0; i < quellen.length; i++) {
    final a = jetzt[quellen[i].id];
    if (a != null && a.isLocked) {
      throw Zusammenfuegefehler(Fuegegrund.quelleGesperrt, quelle: i);
    }
    if (a == null || !alsQuelleGeeignet(a)) {
      throw Zusammenfuegefehler(Fuegegrund.quelleWeg, quelle: i);
    }
  }
  return [for (final q in quellen) jetzt[q.id]!];
}

/// Schreibt [bytes] unter dem Namen des Ergebnisses in einen eigenen
/// Arbeitsordner, gibt die Datei an [arbeit] und räumt danach auf.
///
/// Die Dateizeit ist die Aufnahmezeit der Leitquelle: Der Import (hier wie
/// am Server) nimmt sie, wo das JPEG keine EXIF-Zeit trägt – bei einer
/// Kalenderdatierung –, und legt die Datei so gleich unter das richtige
/// Datum statt unter den Tag des Zusammenfügens.
Future<T> _mitDatei<T>(
  Uint8List bytes,
  List<AssetData> quellen,
  Fuegeart art,
  Future<T> Function(File datei) arbeit,
) async {
  final leit = leitquelle(quellen);
  final ordner = await Directory.systemTemp.createTemp('pv_fuegen_ab_');
  try {
    final datei = File(p.join(ordner.path, fuegeDateiname(leit, art)));
    await datei.writeAsBytes(bytes, flush: true);
    await datei.setLastModified(leit.fileCreatedAt);
    return await arbeit(datei);
  } finally {
    await ordner.delete(recursive: true);
  }
}

/// Die Aufnahme mit genau den Bytes [bytes], die es schon gibt.
///
/// Das Ergebnis eines Zusammenfügens ist bei denselben Quellen Bit für Bit
/// dasselbe. Ein zweiter Lauf – nach einem halben Erfolg (eingelesen, aber
/// nicht eingeordnet, etwa weil verbunden das Abholen scheiterte) oder
/// einfach noch einmal – traf deshalb immer auf eine Dublette und endete
/// bisher mit einer unverständlichen Meldung, für immer. Jetzt wird die
/// vorhandene Aufnahme genommen und eingeordnet; liegt sie im Papierkorb,
/// wird sie zurückgeholt – wer dasselbe Bild noch einmal zusammenfügt,
/// will es haben. Liegt sie im gesperrten Ordner, scheitert es mit
/// [Fuegegrund.ergebnisGesperrt]; ist sie (verbunden) noch nicht da, mit
/// [Fuegegrund.nichtAngekommen].
Future<Fuegeablage> _vorhandenes(AppDatabase db, Uint8List bytes) async {
  final summe = sha256.convert(bytes).toString();
  final treffer = await (db.select(
    db.assets,
  )..where((t) => t.checksum.equals(summe))).get();
  final offen = treffer.where((a) => !a.isLocked && !a.isTrashed).firstOrNull;
  if (offen != null) return Fuegeablage(offen.id, neu: false);
  final weg = treffer.where((a) => !a.isLocked).firstOrNull;
  if (weg != null) {
    await db.fuehreAus(AusDemPapierkorb([weg.id]));
    return Fuegeablage(weg.id, neu: false, zurueckgeholt: true);
  }
  if (treffer.isNotEmpty) {
    throw const Zusammenfuegefehler(Fuegegrund.ergebnisGesperrt);
  }
  throw const Zusammenfuegefehler(Fuegegrund.nichtAngekommen);
}

/// Gibt dem Ergebnis [ablage] die Angaben seiner [quellen] und ordnet es
/// mit ihnen zu einem Variantenstapel, in dem es vorn liegt.
///
/// **Was mitkommt.** Aufnahmezeit der Leitquelle (mit Kalenderdatierung,
/// falls nur ein Jahr oder Zeitraum bekannt ist, und ob sie geschätzt
/// ist) und der Ort samt Namen. Das neu kodierte JPEG trägt das zwar als
/// EXIF, aber keine Datierung, keine Schätzung und keine Ortsnamen; ohne
/// diese Befehle stünde es bei einer datierten Reihe am Tag des
/// Zusammenfügens. Zeitzone und Kamera liest der Import aus dem EXIF
/// ([mitAngabenDerQuellen]).
///
/// **Von der Gesichtssuche ausgenommen**, gleich als Erstes – vor jeder
/// Auswertung: Die Gesichter stehen schon in den Quellen und stünden sonst
/// zweimal bei jeder Person. Verbunden wertet der Server womöglich schon
/// aus, während das hier ankommt; der Befehl geht darum vor allen anderen.
///
/// Für ein schon vorhandenes Ergebnis, das bereits mit allen Quellen
/// gestapelt ist, ändert sich nichts – ein zweiter Lauf überschreibt
/// nichts, was seither von Hand geändert wurde. Sonst (ein halber Erfolg)
/// wird es eingeordnet wie ein neues.
Future<void> ordneZusammengefuegtesEin(
  AppDatabase db,
  Fuegeablage ablage,
  List<AssetData> quellen,
) async {
  final id = ablage.id;
  final ergebnis = await db.assetById(id);
  if (ergebnis == null) {
    throw const Zusammenfuegefehler(Fuegegrund.nichtAngekommen);
  }
  if (!ablage.neu) {
    final stapel = ergebnis.stackId;
    final aktuell = await db.assetsByIds([for (final q in quellen) q.id]);
    if (stapel != null && aktuell.every((a) => a.stackId == stapel)) return;
  }
  final leit = leitquelle(quellen);
  final ort = ortsquelle(quellen);
  final befehle = <Befehl<void>>[
    GesichtssucheAusnehmen(id, true),
    AufnahmedatenSetzen([
      (id: id, zeitpunkt: leit.fileCreatedAt, geschaetzt: leit.datumGeschaetzt),
    ]),
    if (leit.kalenderdatierung case final datierung?)
      DatierungSetzen([id], datierung),
    if (ort != null)
      OrtSetzen(
        [id],
        ort.latitude,
        ort.longitude,
        land: ort.locationCountry,
        region: ort.locationState,
        stadt: ort.locationCity,
      ),
  ];
  for (final befehl in befehle) {
    await db.fuehreAus(befehl);
  }
  await stapleMitQuellen(db, id, quellen, leit);
}

/// Ordnet [ergebnis] und [quellen] zu einem Variantenstapel mit
/// [ergebnis] vorn.
///
/// **Liegen Quellen schon in Stapeln**, kommen deren übrige Glieder mit
/// – sonst blieben halbe Stapel zurück, deren Titel fehlt oder deren
/// Zählung nicht mehr stimmt. Dasselbe gilt für einen Stapel, in dem das
/// Ergebnis selbst schon liegt. Ein einzelner gewöhnlicher Variantenstapel
/// behält dabei seine Kennung; ein Formatstapel (RAW neben JPEG) oder eine
/// Serie wird, wie beim Speichern einer Bearbeitung, ein gewöhnlicher
/// Variantenstapel.
///
/// **Was jedes bisher sichtbare Foto trug, zieht auf das Ergebnis um.**
/// Sichtbar war jede Quelle ohne Stapel und von jedem Stapel sein Titel.
/// `VariantenHauptbildSetzen` bringt Alben, Favorit, Sterne (das
/// Maximum), Farbe, Schlagwörter und Beschreibung des bisherigen Titels
/// auf den neuen (#363) – aber eben nur von *einem*. Bisher verloren
/// darum alle anderen sichtbaren Quellen ihre Alben und Favoriten, sobald
/// sie hinter dem Ergebnis lagen. Jetzt wird der Titel der Reihe nach über
/// jedes sichtbare Foto weitergereicht und zuletzt dem Ergebnis gegeben:
/// Jeder Schritt vereinigt, was der bisherige Titel trug, mit dem, was der
/// neue schon hat. Die Leitquelle kommt zuletzt vor dem Ergebnis, damit
/// ihre Beschreibung vorgeht.
Future<void> stapleMitQuellen(
  AppDatabase db,
  String ergebnis,
  List<AssetData> quellen,
  AssetData leit,
) async {
  final aktuell = await db.assetsByIds([
    for (final q in quellen) q.id,
    ergebnis,
  ]);
  final stapel = <String>{
    for (final a in aktuell)
      if (a.stackId != null) a.stackId!,
  };
  final ids = <String>{ergebnis, for (final a in aktuell) a.id};
  final titelJeStapel = <String, AssetData>{};
  for (final s in stapel) {
    for (final m in await db.assetsInStack(s)) {
      ids.add(m.id);
      if (m.isStackCover) titelJeStapel[s] = m;
    }
  }
  // Was bisher sichtbar war, in der Reihenfolge der Quellen, jedes einmal.
  AssetData? sichtbar(AssetData a) => switch (a.stackId) {
    final String s => titelJeStapel[s],
    null => a,
  };
  final leitJetzt = aktuell.where((a) => a.id == leit.id).firstOrNull ?? leit;
  final leitTitel = sichtbar(leitJetzt);
  final kette = <String>[];
  for (final q in quellen) {
    final a = aktuell.where((x) => x.id == q.id).firstOrNull;
    final s = a == null ? null : sichtbar(a);
    if (s == null || s.isLocked || s.isTrashed) continue;
    if (s.id == ergebnis || s.id == leitTitel?.id || kette.contains(s.id)) {
      continue;
    }
    kette.add(s.id);
  }
  if (leitTitel != null &&
      leitTitel.id != ergebnis &&
      !leitTitel.isLocked &&
      !leitTitel.isTrashed) {
    kette.add(leitTitel.id);
  }
  final einzeln = stapel.length == 1 ? stapel.first : null;
  final kennung =
      einzeln != null &&
          istVariantenstapel(einzeln) &&
          !istFormatstapel(einzeln)
      ? einzeln.substring(variantenstapelPraefix.length)
      : const Uuid().v4();
  final stapelId = variantenstapelId(kennung);
  await db.fuehreAus(
    VariantenBilden(kennung, ids.toList(), kette.firstOrNull ?? ergebnis),
  );
  for (final titel in [...kette.skip(1), if (kette.isNotEmpty) ergebnis]) {
    await db.fuehreAus(VariantenHauptbildSetzen(stapelId, titel));
  }
}

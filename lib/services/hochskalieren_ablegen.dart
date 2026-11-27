import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'entwicklung_ablegen.dart' show AufnahmeNichtAblegbar;
import 'hochskalieren.dart';
import 'tresorreihe.dart';

/// **Das Ergebnis des Hochskalierens als Variante (#500).**
///
/// Anders als eine Restaurierung liegt das hochskalierte Foto nicht als
/// Anzeige über dem Original, sondern wird eine eigene Aufnahme: eine Datei,
/// die man exportieren, drucken und weitergeben kann, die verbundene Geräte
/// bekommen und die eine Sicherung mitnimmt. Damit sie nicht als zweites,
/// fast gleiches Foto in der Zeitleiste steht, kommt sie in einen
/// Variantenstapel mit dem Original, und das Original bleibt Hauptbild.
///
/// Ohne Server über den Import dieser Bibliothek ([legeHochskaliertAb]), mit
/// Server über das Hochladen ([legeHochskaliertAmServerAb]); eingeordnet
/// wird in beiden Fällen gleich ([ordneHochskaliertEin]), über Befehle, die
/// verbunden zum Server gehen.

/// Legt [jpeg] als Hochskalierung von [originalId] um [faktor] in diese
/// Bibliothek und ordnet es ein. Gibt die Kennung der neuen Aufnahme zurück.
///
/// **In der [inTresorreihe] (#430).** Gerechnet wurde Minuten lang mit dem
/// Stand vom Beginn. Wurde das Original seither gesperrt, entstünde sonst
/// eine Klartextkopie eines gesperrten Fotos, offen in der Zeitleiste.
/// Prüfen, Importieren und Stapeln laufen deshalb ohne ein Sperren
/// dazwischen; ist das Original gesperrt, gelöscht oder im Papierkorb, wirft
/// es [AufnahmeNichtAblegbar], und nichts ist angelegt. Darin läuft nur der
/// blosse Import – was er sonst anstösst (Auswertung, Regeln), reiht sich
/// selbst in die Tresorreihe ein und kommt deshalb erst danach (siehe
/// `LibraryState`).
///
/// Liegt genau diese Datei schon in der Bibliothek – dasselbe Foto mit
/// demselben Faktor ein zweites Mal hochskaliert –, wird die vorhandene
/// Aufnahme eingeordnet, falls sie es noch nicht ist; `null` nur, wenn sie
/// im Papierkorb oder im gesperrten Ordner liegt.
Future<String?> legeHochskaliertAb({
  required AppDatabase db,
  required StoragePaths paths,
  required ImportService importe,
  required String originalId,
  required Uint8List jpeg,
  required int faktor,
}) => inTresorreihe(paths, () async {
  final original = await _offenesOriginal(db, originalId);
  return _mitDatei(original, jpeg, faktor, (datei) async {
    final r = await importe.importFile(datei.path);
    final String? id = switch (r.outcome) {
      ImportOutcome.imported => r.assetId,
      ImportOutcome.duplicateSkipped => (await _gleicheAufnahme(db, jpeg))?.id,
      ImportOutcome.failed => throw StateError(
        'pv_hochskalieren_import: ${r.error}',
      ),
    };
    if (id != null) {
      await ordneHochskaliertEin(db: db, original: original, neuId: id);
    }
    return id;
  });
});

/// Wie [legeHochskaliertAb], für eine mit dem Server verbundene Kopie: Die
/// Datei geht über [hochladen] zum Server (der importiert sie wie jeden
/// Upload und gibt die Kennung im Kopf `pv-aufnahme` zurück), [abholen]
/// holt die neue Aufnahme in die Kopie, und die Befehle zum Einordnen gehen
/// wieder zum Server.
///
/// Ohne Tresorreihe: Verbunden lässt sich nicht sperren (`pv_nur_ueber_server`),
/// und das Hochladen kann dauern – die Reihe hielte so lange jede Miniatur
/// und jedes Ergebnis der Auswertung auf.
Future<String?> legeHochskaliertAmServerAb({
  required AppDatabase db,
  required String originalId,
  required Uint8List jpeg,
  required int faktor,
  required Future<Map<String, String>> Function(
    File datei,
    Map<String, String> angaben,
  )
  hochladen,
  required Future<void> Function() abholen,
}) async {
  final original = await _offenesOriginal(db, originalId);
  return _mitDatei(original, jpeg, faktor, (datei) async {
    final kopf = await hochladen(datei, {
      'filename': p.basename(datei.path),
      'sha256': sha256.convert(jpeg).toString(),
      // Der Server setzt damit die Dateizeit; ohne EXIF wird sie dort zur
      // Aufnahmezeit, wie hier beim Import.
      'geaendert': '${original.fileCreatedAt.millisecondsSinceEpoch}',
    });
    final ausgang = kopf['pv-ausgang'];
    if (ausgang != 'imported' && ausgang != 'duplicateSkipped') {
      throw StateError(
        'pv_hochskalieren_hochladen: '
        '${Uri.decodeComponent(kopf['pv-fehler'] ?? ausgang ?? '')}',
      );
    }
    await abholen();
    final id = ausgang == 'imported'
        ? kopf['pv-aufnahme']
        : (await _gleicheAufnahme(db, jpeg))?.id;
    if (id == null || await db.assetById(id) == null) return null;
    await ordneHochskaliertEin(db: db, original: original, neuId: id);
    return id;
  });
}

/// Gibt der hochskalierten Aufnahme [neuId] die Angaben ihres [original]s
/// und stapelt beide.
///
/// **Was mitkommt.** Aufnahmezeit (mit Kalenderdatierung, falls nur ein
/// Jahr oder Zeitraum bekannt ist), Ort samt Namen, die eigene
/// Beschreibung, die von Hand vergebenen Schlagwörter und die Sterne. Das
/// neu kodierte JPEG trägt kein EXIF; ohne diese Befehle stünde es beim Tag
/// des Hochskalierens und ohne Ort da, und die Suche fände nur das
/// Original. Schlagwörter der Bilderkennung kommen nicht mit – die
/// Auswertung vergibt sie dem neuen Bild selbst.
///
/// **Von der Gesichtssuche ausgenommen** wie das Original nach einer
/// Bearbeitung (`speichereBearbeitung`): Sonst stünden dieselben Gesichter
/// zweimal bei jeder Person.
///
/// **Der Stapel.** `createStack` ändert nur die Aufnahmen, die es genannt
/// bekommt, und setzt die Grösse des Stapels auf deren Zahl. Ein Stapel mit
/// nur Original und Ergebnis risse das Original deshalb aus einem
/// vorhandenen Stapel heraus und liesse dort ein Titelbild mit falscher
/// Grösse zurück. Steht das Original schon in einem Stapel, kommt das
/// Ergebnis darum dorthin dazu, mit allen bisherigen Mitgliedern und dem
/// bisherigen Titelbild – dieselbe Regel wie in `speichereBearbeitung`:
/// Varianten bleiben derselbe Variantenstapel, eine Serie bleibt eine
/// Serie, und aus einem Formatstapel wird ein gewöhnlicher Variantenstapel
/// (#363), weil die Vergrösserung kein weiteres Format derselben Aufnahme
/// ist. Ohne Stapel entsteht ein neuer mit dem Original als Hauptbild.
///
/// Wiederholbar: Ist [neuId] schon Mitglied, bleibt der Stapel, wie er ist.
Future<void> ordneHochskaliertEin({
  required AppDatabase db,
  required AssetData original,
  required String neuId,
}) async {
  // Frisch gelesen: Seit dem Einreihen kann das Foto gestapelt, beschrieben
  // oder bewertet worden sein.
  final frisch = await db.assetById(original.id) ?? original;
  final schlagwoerter =
      await (db.select(db.assetTags)..where(
            (t) =>
                t.assetId.equals(frisch.id) & t.quelle.equals(Tagquelle.hand),
          ))
          .get();
  final beschreibung = frisch.description?.trim() ?? '';
  final befehle = <Befehl<void>>[
    AufnahmedatenSetzen([
      (
        id: neuId,
        zeitpunkt: frisch.fileCreatedAt,
        geschaetzt: frisch.datumGeschaetzt,
      ),
    ]),
    if (frisch.kalenderdatierung case final datierung?)
      DatierungSetzen([neuId], datierung),
    if ((frisch.latitude, frisch.longitude) case (final breite?, final laenge?))
      OrtSetzen(
        [neuId],
        breite,
        laenge,
        land: frisch.locationCountry,
        region: frisch.locationState,
        stadt: frisch.locationCity,
      ),
    if (beschreibung.isNotEmpty) BeschreibungSetzen([neuId], beschreibung),
    for (final s in schlagwoerter) SchlagwortAnheftenPerKennung(neuId, s.tagId),
    if (frisch.rating > 0) BewertungSetzen([neuId], frisch.rating),
    GesichtssucheAusnehmen(neuId, true),
    await _stapelbefehl(db, frisch, neuId),
  ];
  for (final befehl in befehle) {
    await db.fuehreAus(befehl);
  }
}

/// Der Befehl, der [neuId] mit [original] stapelt – siehe
/// [ordneHochskaliertEin].
Future<Befehl<void>> _stapelbefehl(
  AppDatabase db,
  AssetData original,
  String neuId,
) async {
  final stapel = original.stackId;
  if (stapel == null) {
    return VariantenBilden(const Uuid().v4(), [
      original.id,
      neuId,
    ], original.id);
  }
  final mitglieder = await db.assetsInStack(stapel);
  final titel = mitglieder
      .firstWhere((m) => m.isStackCover, orElse: () => original)
      .id;
  // Als Menge: Ein zweiter Lauf mit demselben Ergebnis zählte die neue
  // Aufnahme sonst doppelt in die Grösse des Stapels.
  final ids = {for (final m in mitglieder) m.id, original.id, neuId}.toList();
  if (istVariantenstapel(stapel)) {
    return VariantenBilden(
      stapel.substring(variantenstapelPraefix.length),
      ids,
      titel,
    );
  }
  if (istFormatstapel(stapel)) {
    return VariantenBilden(const Uuid().v4(), ids, titel);
  }
  return SerieBilden(stapel, ids, titel);
}

/// Das Original, wie es jetzt ist – oder [AufnahmeNichtAblegbar], wenn es
/// gelöscht, gesperrt oder im Papierkorb ist.
Future<AssetData> _offenesOriginal(AppDatabase db, String originalId) async {
  final original = await db.assetById(originalId);
  if (original == null || original.isLocked || original.isTrashed) {
    throw AufnahmeNichtAblegbar(gesperrt: original?.isLocked ?? false);
  }
  return original;
}

/// Schreibt [jpeg] unter dem Namen des Ergebnisses in einen eigenen
/// Arbeitsordner, gibt die Datei an [arbeit] und räumt danach auf.
///
/// Die Dateizeit ist die Aufnahmezeit des Originals: Der Import (hier wie am
/// Server) nimmt sie in Ermangelung von EXIF als Aufnahmezeit und legt die
/// Datei gleich unter das richtige Datum.
Future<T> _mitDatei<T>(
  AssetData original,
  Uint8List jpeg,
  int faktor,
  Future<T> Function(File datei) arbeit,
) async {
  final ordner = await Directory.systemTemp.createTemp('pv_hochskaliert_');
  try {
    final datei = File(
      p.join(ordner.path, hochskalierName(original.originalFileName, faktor)),
    );
    await datei.writeAsBytes(jpeg, flush: true);
    await datei.setLastModified(original.fileCreatedAt);
    return await arbeit(datei);
  } finally {
    await ordner.delete(recursive: true);
  }
}

/// Die offene Aufnahme mit genau diesen Bytes, falls es sie gibt.
Future<AssetData?> _gleicheAufnahme(AppDatabase db, Uint8List jpeg) async {
  final summe = sha256.convert(jpeg).toString();
  final treffer = await (db.select(
    db.assets,
  )..where((t) => t.checksum.equals(summe))).get();
  return treffer.where((a) => !a.isLocked && !a.isTrashed).firstOrNull;
}

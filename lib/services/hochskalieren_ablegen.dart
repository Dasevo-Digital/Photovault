import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/jpeg_angaben.dart';
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

/// Was zum Ablegen eines fertig gerechneten Hochskalierens gehört.
class Hochskalierablage {
  const Hochskalierablage({
    required this.originalId,
    required this.jpeg,
    required this.faktor,
    this.abgebrochen,
    this.hochladeort,
    this.hochladeortMerken,
  });

  final String originalId;

  /// Die fertige Datei, schon mit den Angaben des Originals (siehe
  /// [mitHochskalierangaben]).
  final Uint8List jpeg;
  final int faktor;

  /// Gefragt vor jedem Schritt, der die Datenbank oder den Server anfasst:
  /// Beim Beenden schliesst die App die Datenbank nach einer kurzen Frist,
  /// auch wenn das Ablegen noch läuft. Ein Ja endet mit
  /// [AblageAbgebrochen]; der Auftrag bleibt offen und legt beim nächsten
  /// Start dieselbe Datei ab.
  final bool Function()? abgebrochen;

  /// Wo ein früher angefangenes Hochladen genau dieser Datei steht (tus) –
  /// dort geht es weiter, statt sie noch einmal ganz zu senden.
  final String? hochladeort;

  /// Bekommt den Ort eines neu angefangenen Hochladens.
  final void Function(String ort)? hochladeortMerken;

  void pruefeAbbruch() {
    if (abgebrochen?.call() ?? false) throw const AblageAbgebrochen();
  }
}

/// Das Ablegen wurde beim Beenden abgebrochen; der Auftrag bleibt offen.
class AblageAbgebrochen implements Exception {
  const AblageAbgebrochen();

  @override
  String toString() => 'pv_ablage_abgebrochen';
}

/// Wie die Datei zum Server geht – im Betrieb `TusHochladen.lade`.
typedef Hochladen =
    Future<Map<String, String>> Function(
      File datei,
      Map<String, String> angaben, {
      String? fortsetzen,
      void Function(String ort)? angelegt,
      bool Function()? abbrechen,
    });

/// [jpeg] mit Aufnahmezeit, Zeitzone und Ort von [original] im EXIF.
///
/// Das Netz liefert nur Bildpunkte; ohne diese Angaben stünde die Datei
/// beim Export oder in einem anderen Programm am Tag des Hochskalierens und
/// ohne Ort. Der Import – hier wie am Server – liest sie wieder ein, auch
/// den Zeitzonenversatz, für den es keinen Befehl gibt. Ein Datum, das nur
/// als Jahr oder Zeitraum bekannt ist, kommt nicht ins EXIF (siehe
/// [mitAufnahmeangaben]); das setzt [ordneHochskaliertEin].
///
/// **Ohne Kamera.** Nach dem Import legt die Nachbearbeitung eine
/// Kameravorgabe auf jedes Foto ihrer Kamera; die Vergrösserung trägt die
/// Entwicklung aber schon in ihren Bildpunkten und wäre danach zweimal
/// entwickelt.
///
/// Einmal, bevor das Ergebnis aufgehoben wird: So bleibt die Datei über
/// jede Wiederholung des Ablegens dieselbe, ein zweiter Versuch erkennt
/// sie als schon vorhanden, und ein unterbrochenes Hochladen lässt sich
/// fortsetzen.
Uint8List mitHochskalierangaben(Uint8List jpeg, AssetData original) =>
    mitAufnahmeangaben(
      jpeg,
      original.copyWith(
        cameraMake: const Value(null),
        cameraModel: const Value(null),
      ),
      mitOrt: true,
      mitZeitversatz: true,
    );

/// Legt die Datei aus [ablage] als Hochskalierung in diese Bibliothek und
/// ordnet sie ein. Gibt die Kennung der neuen Aufnahme zurück.
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
/// Liegt genau diese Datei schon in der Bibliothek – ein zweiter Versuch
/// nach einem abgebrochenen, oder dasselbe Foto mit demselben Faktor noch
/// einmal –, wird die vorhandene Aufnahme eingeordnet, falls sie es noch
/// nicht ist; liegt sie im Papierkorb, kommt sie zurück. `null` nur, wenn
/// sie im gesperrten Ordner liegt.
///
/// [nachbearbeiten] bekommt die neue Aufnahme nach der Tresorreihe. Was
/// dort scheitert, lässt das Ablegen gelten: Die Aufnahme ist angelegt und
/// eingeordnet, und ein Auftrag, der „gescheitert“ meldete, würde beim
/// nächsten Versuch nur dieselbe Datei als schon vorhanden finden.
Future<String?> legeHochskaliertAb({
  required AppDatabase db,
  required StoragePaths paths,
  required ImportService importe,
  required Hochskalierablage ablage,
  Future<void> Function(String neuId)? nachbearbeiten,
}) async {
  final id = await _legeImportiertAb(db, paths, importe, ablage);
  if (id != null && nachbearbeiten != null) {
    try {
      await nachbearbeiten(id);
    } catch (e) {
      debugPrint('Nachbearbeitung des hochskalierten Fotos: $e');
    }
  }
  return id;
}

Future<String?> _legeImportiertAb(
  AppDatabase db,
  StoragePaths paths,
  ImportService importe,
  Hochskalierablage ablage,
) => inTresorreihe(paths, () async {
  ablage.pruefeAbbruch();
  final original = await _offenesOriginal(db, ablage.originalId);
  return _mitDatei(original, ablage, (datei, summe) async {
    ablage.pruefeAbbruch();
    final r = await importe.importFile(datei.path);
    final String? id = switch (r.outcome) {
      ImportOutcome.imported => r.assetId,
      ImportOutcome.duplicateSkipped => await _gleicheAufnahme(db, summe),
      ImportOutcome.failed => throw StateError(
        'pv_hochskalieren_import: ${r.error}',
      ),
    };
    if (id != null) {
      // Angelegt ist sie; abgebrochen, bliebe sie ohne Stapel, und der
      // nächste Versuch fände sie als schon vorhanden wieder.
      ablage.pruefeAbbruch();
      await ordneHochskaliertEin(
        db: db,
        original: original,
        neuId: id,
        paths: paths,
      );
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
/// Ohne Tresorreihe: Verbunden lässt sich hier nicht sperren
/// (`pv_nur_ueber_server`), und das Hochladen kann dauern – die Reihe hielte
/// so lange jede Miniatur und jedes Ergebnis der Auswertung auf.
///
/// **Gesperrt wird anderswo (#430).** Ein anderes Gerät kann das Original
/// sperren, bevor diese Kopie es erfährt oder während die Datei unterwegs
/// ist; sie läge dann als Klartext offen am Server. Deshalb:
///
/// * vor dem Prüfen frisch abholen, nicht dem Stand der Kopie trauen;
/// * die Kennung des Originals mitschicken (`abgeleitetVon`): Ein Server ab
///   dieser Fassung nimmt die Datei nicht an, wenn das Original bei ihm
///   gesperrt, gelöscht oder im Papierkorb ist – im selben Schritt wie der
///   Import, ohne die Laufzeit bis zur Kopie;
/// * nach dem Hochladen noch einmal abholen und prüfen; ist das Original
///   jetzt gesperrt, oder scheitert das Einordnen, kommt die eben angelegte
///   Aufnahme gleich wieder in den Papierkorb ([InDenPapierkorb]).
///
/// **Die Gesichtssuche zuerst.** Der Server wertet zehn Sekunden nach dem
/// Import aus. Bis hierher ging [GesichtssucheAusnehmen] erst nach dem
/// Abholen und weiteren Befehlen hinaus, oft zu spät – und dieselben
/// Gesichter standen danach zweimal bei jeder Person. Jetzt ist es der
/// erste Befehl nach dem Hochladen; was der Server bis dahin schon erkannt
/// hat, nimmt [ordneHochskaliertEin] wieder weg.
Future<String?> legeHochskaliertAmServerAb({
  required AppDatabase db,
  required Hochskalierablage ablage,
  required Hochladen hochladen,
  required Future<void> Function() abholen,
  StoragePaths? paths,
}) async {
  ablage.pruefeAbbruch();
  await abholen();
  ablage.pruefeAbbruch();
  final original = await _offenesOriginal(db, ablage.originalId);
  return _mitDatei(original, ablage, (datei, summe) async {
    final kopf = await hochladen(
      datei,
      {
        'filename': p.basename(datei.path),
        'sha256': summe,
        // Der Server setzt damit die Dateizeit; ohne EXIF wird sie dort zur
        // Aufnahmezeit, wie hier beim Import.
        'geaendert': '${original.fileCreatedAt.millisecondsSinceEpoch}',
        'abgeleitetVon': original.id,
      },
      fortsetzen: ablage.hochladeort,
      angelegt: ablage.hochladeortMerken,
      abbrechen: ablage.abgebrochen,
    );
    final ausgang = kopf['pv-ausgang'];
    final fehler = Uri.decodeComponent(kopf['pv-fehler'] ?? '');
    // Siehe `Hochladen.importiereDatei` im Server.
    if (ausgang == 'failed' &&
        (fehler == 'pv_original_gesperrt' || fehler == 'pv_original_weg')) {
      throw AufnahmeNichtAblegbar(gesperrt: fehler == 'pv_original_gesperrt');
    }
    if (ausgang != 'imported' && ausgang != 'duplicateSkipped') {
      throw StateError(
        'pv_hochskalieren_hochladen: '
        '${fehler.isEmpty ? ausgang ?? '' : fehler}',
      );
    }
    // Nur, was dieser Lauf angelegt hat, darf er wieder wegräumen.
    final neu = ausgang == 'imported' ? kopf['pv-aufnahme'] : null;
    try {
      if (neu != null) await db.fuehreAus(GesichtssucheAusnehmen(neu, true));
      ablage.pruefeAbbruch();
      await abholen();
      ablage.pruefeAbbruch();
      // Erst das Original: Eine Dublette käme sonst womöglich aus dem
      // Papierkorb zurück, bevor sich zeigt, dass es gesperrt ist.
      final jetzt = await db.assetById(original.id);
      if (jetzt == null || jetzt.isLocked || jetzt.isTrashed) {
        throw AufnahmeNichtAblegbar(gesperrt: jetzt?.isLocked ?? false);
      }
      final id = neu ?? await _gleicheAufnahme(db, summe);
      if (id == null || await db.assetById(id) == null) return null;
      await ordneHochskaliertEin(
        db: db,
        original: jetzt,
        neuId: id,
        paths: paths,
      );
      return id;
    } on AblageAbgebrochen {
      // Beim Beenden: Der nächste Start findet die Aufnahme als schon
      // vorhanden und ordnet sie ein.
      rethrow;
    } catch (_) {
      if (neu != null) {
        try {
          await db.fuehreAus(InDenPapierkorb([neu]));
        } catch (_) {
          // Bestmöglich – der ursprüngliche Fehler zählt.
        }
      }
      rethrow;
    }
  });
}

/// Gibt der hochskalierten Aufnahme [neuId] die Angaben ihres [original]s
/// und stapelt beide.
///
/// **Zuerst von der Gesichtssuche ausnehmen**, wie das Original nach einer
/// Bearbeitung (`speichereBearbeitung`): Sonst stünden dieselben Gesichter
/// zweimal bei jeder Person. Was schon erkannt ist und niemand von Hand
/// zugeordnet hat, wird gelöscht ([GesichterLoeschen]; die Ausschnitte
/// räumt [paths] weg, verbunden der Server).
///
/// **Was mitkommt.** Aufnahmezeit (mit Kalenderdatierung, falls nur ein
/// Jahr oder Zeitraum bekannt ist), Ort samt Namen, die eigene
/// Beschreibung, die von Hand vergebenen Schlagwörter, Sterne, Farbmarke
/// und Favorit. Die Datei trägt Zeit, Zeitzone, Kamera und Ort schon im EXIF
/// ([mitHochskalierangaben]); die Befehle setzen den Stand von jetzt, falls
/// das Original seit dem Rechnen geändert wurde. Schlagwörter der
/// Bilderkennung kommen nicht mit – die Auswertung vergibt sie dem neuen
/// Bild selbst. Alben auch nicht: Eine verdeckte Variante zeigt kein Album,
/// und wird sie zum Hauptbild, ziehen die Alben ohnehin zu ihr um
/// (`VariantenHauptbildSetzen`).
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
  StoragePaths? paths,
}) async {
  await db.fuehreAus(GesichtssucheAusnehmen(neuId, true));
  final erkannt = [
    for (final f in await db.facesForAsset(neuId))
      if (f.personId == null || f.automatischZugeordnet) f.id,
  ];
  if (erkannt.isNotEmpty) {
    final ausschnitte = await db.fuehreAus(GesichterLoeschen(erkannt));
    for (final pfad in ausschnitte) {
      try {
        await paths?.deletePermanently(pfad);
      } catch (_) {
        // Ein Ausschnitt, der fehlt, ist schon weg.
      }
    }
  }
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
    if (frisch.colorLabel case final farbe?) FarbmarkeSetzen([neuId], farbe),
    if (frisch.isFavorite) FavoritSetzen([neuId], true),
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
  // Der Formatstapel zuerst: Sein Vorsatz `variante:format-` beginnt mit
  // dem der Varianten, die Prüfung darunter träfe also auch ihn – und das
  // Ergebnis landete im Formatstapel, als wäre es ein weiteres Format.
  if (istFormatstapel(stapel)) {
    return VariantenBilden(const Uuid().v4(), ids, titel);
  }
  if (istVariantenstapel(stapel)) {
    return VariantenBilden(
      stapel.substring(variantenstapelPraefix.length),
      ids,
      titel,
    );
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

/// Schreibt die Datei aus [ablage] unter dem Namen des Ergebnisses in einen
/// eigenen Arbeitsordner, gibt sie samt Prüfsumme an [arbeit] und räumt
/// danach auf.
///
/// Die Dateizeit ist die Aufnahmezeit des Originals: Der Import (hier wie am
/// Server) nimmt sie in Ermangelung von EXIF als Aufnahmezeit und legt die
/// Datei gleich unter das richtige Datum.
///
/// **Die Prüfsumme in einem eigenen Isolat**, aus der Datei: Das Ergebnis
/// hat schnell 30 bis 60 MB, und `sha256.convert` rechnete das bis hierher
/// zweimal am Stück auf dem Faden der Oberfläche.
Future<T> _mitDatei<T>(
  AssetData original,
  Hochskalierablage ablage,
  Future<T> Function(File datei, String summe) arbeit,
) async {
  final ordner = await Directory.systemTemp.createTemp('pv_hochskaliert_');
  try {
    final datei = File(
      p.join(
        ordner.path,
        hochskalierName(original.originalFileName, ablage.faktor),
      ),
    );
    await datei.writeAsBytes(ablage.jpeg, flush: true);
    await datei.setLastModified(original.fileCreatedAt);
    return await arbeit(datei, await _pruefsumme(datei.path));
  } finally {
    await ordner.delete(recursive: true);
  }
}

/// SHA-256 der Datei [pfad], gerechnet in einem eigenen Isolat. Eine eigene
/// Funktion, damit der Abschluss nichts weiter mitnimmt als den Pfad.
Future<String> _pruefsumme(String pfad) => Isolate.run(
  () async => (await sha256.bind(File(pfad).openRead()).first).toString(),
);

/// Die Aufnahme mit genau dieser Prüfsumme, falls es sie gibt und sie nicht
/// gesperrt ist. Liegt sie im Papierkorb, kommt sie zurück: Wer dasselbe
/// Foto noch einmal genauso hochskaliert, will das Ergebnis sehen – sonst
/// meldete der Auftrag „fertig“, und nirgends stünde eine neue Aufnahme.
Future<String?> _gleicheAufnahme(AppDatabase db, String summe) async {
  final treffer = await (db.select(
    db.assets,
  )..where((t) => t.checksum.equals(summe))).get();
  final offen = treffer.where((a) => !a.isLocked).firstOrNull;
  if (offen == null) return null;
  if (offen.isTrashed) await db.fuehreAus(AusDemPapierkorb([offen.id]));
  return offen.id;
}

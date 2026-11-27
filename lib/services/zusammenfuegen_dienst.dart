import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:kern/abgleich/tus.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart' show lesbarerPfad;
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/zusammenfuegen/ablage.dart';
import 'package:kern/services/zusammenfuegen/raster.dart' show leseBildkopf;
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';
import 'package:path/path.dart' as p;

import '../state/library_state.dart';
import 'native_image_converter.dart';

/// Unter diesem Schlüssel steht ein Zusammenfügen (#498) in der
/// Aufgabenleiste. Ein fester Schlüssel und kein neuer je Lauf: Zwei
/// Panoramen zugleich hielten zweimal ein halbes Gigabyte, und die
/// Aufgabenleiste weist ein zweites ab, solange das erste läuft.
const zusammenfuegenSchluessel = 'zusammenfuegen';

/// Was ein gelungener Lauf meldet: die neue Aufnahme, und wie viele der
/// Quellen darin stecken – ein Panorama nimmt nur, was sich verbinden
/// liess. [zurueckgeholt]: Genau dieses Bild lag schon im Papierkorb und
/// ist von dort zurückgeholt.
class Fuegeausgang {
  const Fuegeausgang(
    this.assetId,
    this.verwendet,
    this.angeboten, {
    this.zurueckgeholt = false,
  });

  final String assetId;
  final int verwendet;
  final int angeboten;
  final bool zurueckgeholt;
}

/// Die Aufnahmen aus [ids], die als Quelle taugen ([alsQuelleGeeignet]),
/// nach Aufnahmezeit, und wie viele herausfielen.
Future<({List<AssetData> quellen, int ausgelassen})> zusammenfuegbare(
  AppDatabase db,
  List<String> ids,
) async {
  final alle = await db.assetsByIds(ids);
  final quellen = [
    for (final a in alle)
      if (alsQuelleGeeignet(a)) a,
  ]..sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
  return (quellen: quellen, ausgelassen: ids.length - quellen.length);
}

/// Fügt [quellen] zu einem Bild der Art [art] zusammen und legt es als
/// Variante vor ihnen ab – als Strom für die Aufgabenleiste (0 bis 100).
///
/// Drei Abschnitte: die Quellen lesbar bereitstellen (bis 15), im eigenen
/// Isolat rechnen (bis 95), ablegen. Scheitert es, endet der Strom mit dem
/// Fehler – [Zusammenfuegefehler] für die bekannten Gründe.
///
/// **Abbrechen wirkt sofort und legt nichts ab.** Vorher war das ein
/// `async*`-Generator. Den hält ein Kündigen nur an einem `yield` an; nach
/// der letzten Meldung des Isolats kam keines mehr vor dem Ablegen. Wer
/// dann abbrach, bekam das Bild trotzdem: eingelesen, hochgeladen,
/// gestapelt – und keine Meldung, weil ein abgebrochener Lauf keine
/// bekommt. Jetzt beendet das Kündigen ([StreamController.onCancel]) das
/// Isolat auf der Stelle, und vor dem Ablegen (zuletzt in der Tresorreihe)
/// wird ausdrücklich gefragt, ob abgebrochen wurde. Das Kündigen ist erst
/// erfüllt, wenn der Arbeitsordner geräumt ist. Lief das Ablegen schon,
/// kommt es zu Ende, und [fertig] meldet es wie sonst.
Stream<ImportProgress> zusammenfuegenLauf(
  LibraryState library, {
  required List<AssetData> quellen,
  required Fuegeart art,
  bool ausrichten = true,
  bool drehung = true,
  bool zuschneiden = true,
  void Function(Fuegeausgang ausgang)? fertig,
}) {
  final abbruch = Completer<void>();
  late final StreamController<ImportProgress> aus;
  Future<void>? lauf;
  aus = StreamController<ImportProgress>(
    onListen: () {
      lauf =
          _fuegeUndLegeAb(
                library,
                quellen: quellen,
                art: art,
                ausrichten: ausrichten,
                drehung: drehung,
                zuschneiden: zuschneiden,
                melde: (s) {
                  if (!abbruch.isCompleted) aus.add(s);
                },
                abbruch: abbruch,
                fertig: fertig,
              )
              .then<void>(
                (_) {},
                onError: (Object e, StackTrace s) {
                  if (!abbruch.isCompleted) aus.addError(e, s);
                },
              )
              // Nicht abwarten: Nach dem Kündigen wird `close` erst
              // erfüllt, wenn [lauf] es ist – das wäre ein Warten auf sich
              // selbst.
              .whenComplete(() => unawaited(aus.close()));
    },
    onCancel: () {
      if (!abbruch.isCompleted) abbruch.complete();
      return lauf;
    },
  );
  return aus.stream;
}

Future<void> _fuegeUndLegeAb(
  LibraryState library, {
  required List<AssetData> quellen,
  required Fuegeart art,
  required bool ausrichten,
  required bool drehung,
  required bool zuschneiden,
  required void Function(ImportProgress stand) melde,
  required Completer<void> abbruch,
  void Function(Fuegeausgang ausgang)? fertig,
}) async {
  bool abgebrochen() => abbruch.isCompleted;
  const gesamt = 100;
  final arbeit = await Directory.systemTemp.createTemp('pv_fuegen_');
  try {
    melde(ImportProgress(0, gesamt));
    final dateien = <String>[];
    final vorschauen = <String?>[];
    for (var i = 0; i < quellen.length; i++) {
      if (abgebrochen()) return;
      final b = await _bereitstellen(library, quellen[i], arbeit, i, art);
      dateien.add(b.datei);
      vorschauen.add(b.vorschau);
      melde(
        ImportProgress(
          (i + 1) * 15 ~/ quellen.length,
          gesamt,
          currentFile: quellen[i].originalFileName,
        ),
      );
    }
    if (abgebrochen()) return;
    final e = await _rechne(
      Fuegeauftrag(
        art: art,
        dateien: dateien,
        vorschauen: vorschauen,
        ziel: p.join(arbeit.path, 'ergebnis.jpg'),
        brennweiten35: [for (final q in quellen) q.focalLength35mm],
        ausrichten: ausrichten,
        drehung: drehung,
        zuschneiden: zuschneiden,
      ),
      melde,
      abbruch.future,
    );
    if (e == null || abgebrochen()) return;
    final verwendet = [for (final i in e.verwendet) quellen[i]];
    final jpeg = await File(e.datei).readAsBytes();
    if (abgebrochen()) return;
    final Fuegeablage? ablage;
    try {
      ablage = library.verbunden
          ? await _amServerAblegen(library, verwendet, jpeg, art, abgebrochen)
          : await legeZusammengefuegtesAb(
              db: library.db,
              paths: library.paths,
              importe: library.importService,
              quellen: verwendet,
              jpeg: jpeg,
              art: art,
              abgebrochen: abgebrochen,
            );
    } on Zusammenfuegefehler catch (f) {
      // Die Stelle zählt dort in [verwendet], gemeldet wird sie in
      // [quellen].
      final stelle = f.quelle;
      if (stelle == null) rethrow;
      throw Zusammenfuegefehler(
        f.grund,
        quelle: e.verwendet[stelle],
        ursache: f.ursache,
      );
    }
    if (ablage == null) return;
    // Erst nach dem Ablegen, also ausserhalb der Tresorreihe: Die
    // Auswertung reiht sich dort selbst ein und wartete sonst auf sich
    // selbst. Verbunden erledigt das der Server.
    if (!library.verbunden && ablage.neu) {
      try {
        await library.nachbearbeitung.neueAufnahme(ablage.id);
      } on Object {
        // Das Bild ist abgelegt und eingeordnet; Regeln und Ortsnamen
        // holt der nächste Lauf der Hintergrundaufgaben nach.
      }
      if (await library.db.autoAnalyzeAfterImportEnabled()) {
        unawaited(library.starteHintergrundanalyse());
      }
    }
    fertig?.call(
      Fuegeausgang(
        ablage.id,
        verwendet.length,
        quellen.length,
        zurueckgeholt: ablage.zurueckgeholt,
      ),
    );
    melde(ImportProgress(gesamt, gesamt, assetId: ablage.id, getan: 1));
  } finally {
    try {
      await arbeit.delete(recursive: true);
    } on FileSystemException {
      // Liegt im Temp-Ordner und wird dort ohnehin geräumt.
    }
  }
}

/// Rechnet [auftrag] im eigenen Isolat ([fuegeZusammen]) und meldet die
/// Zwischenstände (15 bis 95). `null`, wenn vorher [abbruch] kam – dann
/// ist das Isolat schon beendet.
Future<Fuegeergebnis?> _rechne(
  Fuegeauftrag auftrag,
  void Function(ImportProgress stand) melde,
  Future<void> abbruch,
) {
  final ende = Completer<Fuegeergebnis?>();
  final abo = fuegeZusammen(auftrag).listen(
    (s) {
      if (s.ergebnis case final e?) {
        if (!ende.isCompleted) ende.complete(e);
        return;
      }
      melde(ImportProgress(15 + s.erledigt * 80 ~/ math.max(1, s.gesamt), 100));
    },
    onError: (Object f, StackTrace st) {
      if (!ende.isCompleted) ende.completeError(f, st);
    },
    onDone: () {
      if (!ende.isCompleted) {
        ende.completeError(const Zusammenfuegefehler(Fuegegrund.ohneErgebnis));
      }
    },
    cancelOnError: true,
  );
  unawaited(
    abbruch.then((_) {
      if (ende.isCompleted) return null;
      ende.complete(null);
      return abo.cancel();
    }),
  );
  return ende.future;
}

/// Verbunden: Hochladen und Einordnen wie [legeZusammengefuegtesAmServerAb].
Future<Fuegeablage?> _amServerAblegen(
  LibraryState library,
  List<AssetData> quellen,
  Uint8List jpeg,
  Fuegeart art,
  bool Function() abgebrochen,
) async {
  final a = library.abgleich;
  if (a == null) throw const Zusammenfuegefehler(Fuegegrund.nichtVerbunden);
  final ablage = await legeZusammengefuegtesAmServerAb(
    db: library.db,
    quellen: quellen,
    jpeg: jpeg,
    art: art,
    hochladen: (datei, angaben) =>
        TusHochladen(a.verbindung).lade(datei, 'api/v1/hochladen', angaben),
    abholen: a.empfange,
    abgebrochen: abgebrochen,
  );
  unawaited(library.pruefeServerspeicher());
  return ablage;
}

/// So lang wird die lange Seite der kleinen Fassung einer Quelle mit der
/// langen Seite [lang] – `null`, wo sie sich nicht lohnt.
///
/// **Panorama:** 1600 Punkte, sicher über den 0,6 MP der Registrierung;
/// die rechnet ohnehin auf einer verkleinerten Fassung.
///
/// **HDR:** die Hälfte, ein Viertel … der Quelle, bis höchstens 3200 –
/// genau die Stufe, auf der ausgerichtet wird. Ein ganzer Teiler und kein
/// beliebiger: An 24-MP-Reihen lag die Lage aus einer Fassung mit 3200
/// Punkten (Faktor 1,875) bis 0,7 Punkte daneben, weil feine Kanten in
/// jeder Aufnahme anders auf das gröbere Raster fallen; mit 3000 (Faktor 2)
/// waren es wie aus der vollen Quelle unter 0,15.
int? _vorschauKante(Fuegeart art, int lang) {
  if (art == Fuegeart.panorama) return lang > 2000 ? 1600 : null;
  var teiler = 1;
  while (lang ~/ teiler > 3200) {
    teiler *= 2;
  }
  return teiler == 1 ? null : lang ~/ teiler;
}

/// Macht aus [a] eine Datei, die das Isolat lesen kann (JPEG oder PNG),
/// und gibt ihren Pfad – dazu, wo es sich lohnt, eine kleine Fassung für
/// den ersten Durchgang.
///
/// **Aus dem Original, nicht aus der Entwicklung.** Eine Belichtungsreihe
/// lebt davon, dass ihre Aufnahmen verschieden belichtet sind; eine je
/// Bild nachgeregelte Belichtung verschöbe genau das. Das Ergebnis lässt
/// sich danach entwickeln wie jedes Foto.
///
/// Ein JPEG oder PNG wird gelesen, wie es in der Bibliothek liegt (mit
/// Server vorher geholt, `paths.bereit`). Alles andere – HEIC, RAW, ein
/// JPEG über der Grösse, die das Ergebnis braucht – wandeln die
/// Bildwerkzeuge (RAW mit Objektivkorrektur, wie für die Vorschau). Geht
/// auch das nicht, bleibt die lesbare Fassung ([lesbarerPfad], die
/// Vorschau mit gut 2000 Punkten); dann wird das Ergebnis eben kleiner.
///
/// **Die Grösse kommt notfalls aus dem Kopf der Datei.** Fehlt sie in der
/// Datenbank, ging ein JPEG oder PNG bisher ungeprüft ins Isolat, auch mit
/// 100 MP. Jetzt entscheidet ihr Kopf, ob gewandelt wird; das Isolat
/// prüft ihn vor dem Dekodieren ohnehin selbst (`dekodiereBild`).
///
/// **Die kleine Fassung** ([_vorschauKante]) machen ebenfalls die
/// Bildwerkzeuge, und zwar aus genau der Datei, die das Isolat voll liest –
/// so hat sie dieselbe Geometrie, auch nach Objektivkorrektur. Gemessen an
/// 24 MP: Dart braucht zum Dekodieren gut 0,6 s je Quelle, das Lesen der
/// kleinen Fassung 0,1 s, die Bildwerkzeuge für sie um 0,1 bis 0,2 s.
Future<({String datei, String? vorschau})> _bereitstellen(
  LibraryState library,
  AssetData a,
  Directory arbeit,
  int nummer,
  Fuegeart art,
) async {
  final grenze = art.quellenPixel;
  final File original;
  try {
    original = await library.paths.bereit(a.relativePath);
  } on Object {
    throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: nummer);
  }
  final kennung = await _kennung(original);
  final lesbar = kennung == '.jpg' || kennung == '.png';
  // Beim JPEG und PNG gilt ihr Kopf – er sagt, was das Isolat liest.
  var b = a.widthPx ?? 0, h = a.heightPx ?? 0;
  if (lesbar) {
    final kopf = await _kopfmasse(original);
    if (kopf != null) (b, h) = kopf;
  }
  final zuGross = b * h > grenze;
  String? datei;
  if (lesbar && !zuGross) {
    datei = original.path;
  } else {
    final kante = zuGross
        ? (math.max(b, h) * math.sqrt(grenze / (b * h))).floor()
        : null;
    final jpeg = await NativeImageConverter.convertToJpegBytes(
      original,
      maxDimension: kante,
      quality: 0.95,
    );
    if (jpeg != null) {
      final ziel = File(p.join(arbeit.path, 'quelle_$nummer.jpg'));
      await ziel.writeAsBytes(jpeg, flush: true);
      datei = ziel.path;
    } else if (lesbar) {
      datei = original.path;
    } else {
      try {
        final lesbare = await library.paths.bereit(lesbarerPfad(a));
        final k = await _kennung(lesbare);
        if (k == '.jpg' || k == '.png') datei = lesbare.path;
      } on Object {
        // Unten gemeldet.
      }
    }
  }
  if (datei == null) {
    throw Zusammenfuegefehler(Fuegegrund.unlesbar, quelle: nummer);
  }
  return (
    datei: datei,
    vorschau: await _kleineFassung(File(datei), art, arbeit, nummer),
  );
}

/// Die kleine Fassung von [datei] für den ersten Durchgang – `null`, wenn
/// sie sich nicht lohnt (die Quelle ist kaum grösser), ihr Kopf sich nicht
/// lesen lässt oder die Bildwerkzeuge sie nicht machen können.
Future<String?> _kleineFassung(
  File datei,
  Fuegeart art,
  Directory arbeit,
  int nummer,
) async {
  final kopf = await _kopfmasse(datei);
  if (kopf == null) return null;
  final kante = _vorschauKante(art, math.max(kopf.$1, kopf.$2));
  if (kante == null) return null;
  final jpeg = await NativeImageConverter.convertToJpegBytes(
    datei,
    maxDimension: kante,
    quality: 0.9,
    objektivkorrektur: false,
  );
  if (jpeg == null) return null;
  final ziel = File(p.join(arbeit.path, 'klein_$nummer.jpg'));
  await ziel.writeAsBytes(jpeg, flush: true);
  return ziel.path;
}

/// Breite und Höhe aus dem Kopf eines JPEG oder PNG (die ersten 256 KB),
/// ohne es zu dekodieren.
Future<(int, int)?> _kopfmasse(File datei) async {
  try {
    final r = await datei.open();
    try {
      final kopf = leseBildkopf(await r.read(256 * 1024));
      return kopf == null ? null : (kopf.breite, kopf.hoehe);
    } finally {
      await r.close();
    }
  } on FileSystemException {
    return null;
  }
}

Future<String?> _kennung(File datei) async {
  try {
    final r = await datei.open();
    try {
      return kennungAus(await r.read(kennungBytes));
    } finally {
      await r.close();
    }
  } on FileSystemException {
    return null;
  }
}

import 'dart:convert';

import '../db/database.dart';

/// Was eine XMP-Beilage neben einem Foto über dieses sagt und beim Import
/// mitkommt (#346): Wer in darktable oder Lightroom sortiert hat, soll das
/// nicht noch einmal tun müssen.
///
/// Ein eigener kleiner Träger statt des XMP selbst: Beim Hochladen geht er
/// in den Metadaten mit, denn die Beilage liegt auf dem Rechner, das Foto
/// landet auf dem Server.
class Beilagenangaben {
  const Beilagenangaben({
    this.sterne,
    this.abgelehnt = false,
    this.farbe,
    this.beschreibung,
    this.schlagwoerter = const [],
    this.breite,
    this.laenge,
  });

  /// 1 bis 5; `null`, wenn keine vergeben sind.
  final int? sterne;
  final bool abgelehnt;
  final String? farbe;
  final String? beschreibung;
  final List<String> schlagwoerter;
  final double? breite;
  final double? laenge;

  /// So viel darf als Text in die Metadaten eines Uploads: Sie gehen als
  /// Kopfzeile über die Leitung.
  static const hoechstensBytes = 4096;

  Map<String, Object?> alsMap() => {
    'sterne': ?sterne,
    if (abgelehnt) 'abgelehnt': true,
    'farbe': ?farbe,
    'beschreibung': ?beschreibung,
    if (schlagwoerter.isNotEmpty) 'schlagwoerter': schlagwoerter,
    'breite': ?breite,
    'laenge': ?laenge,
  };

  /// Als Text für den Upload. Passt er nicht, fehlen Beschreibung und
  /// Schlagwörter: Das Urteil ist der Teil, den niemand neu vergeben will.
  String alsText() {
    final ganz = jsonEncode(alsMap());
    if (utf8.encode(ganz).length <= hoechstensBytes) return ganz;
    return jsonEncode(
      Beilagenangaben(
        sterne: sterne,
        abgelehnt: abgelehnt,
        farbe: farbe,
        breite: breite,
        laenge: laenge,
      ).alsMap(),
    );
  }

  /// Aus [alsMap]; was nicht passt, fällt weg, statt den Upload scheitern
  /// zu lassen. `null`, wenn nichts bleibt.
  static Beilagenangaben? aus(Object? j) {
    if (j is! Map) return null;
    final s = j['sterne'];
    final tags = j['schlagwoerter'];
    double? zahl(Object? v, double grenze) =>
        v is num && v.abs() <= grenze ? v.toDouble() : null;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final a = Beilagenangaben(
      sterne: s is int && s >= 1 && s <= 5 ? s : null,
      abgelehnt: j['abgelehnt'] == true,
      farbe: text(j['farbe']),
      beschreibung: text(j['beschreibung']),
      schlagwoerter: tags is List
          ? [
              for (final t in tags)
                if (t is String && t.isNotEmpty) t,
            ]
          : const [],
      breite: zahl(j['breite'], 90),
      laenge: zahl(j['laenge'], 180),
    );
    return a.alsMap().isEmpty ? null : a;
  }

  /// Aus [alsText]; `null` bei allem, was keiner ist.
  static Beilagenangaben? ausText(Object? text) {
    if (text is! String) return null;
    try {
      return aus(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  /// Trägt alles an der neuen Aufnahme [id] ein. „Abgelehnt“ lässt sie in
  /// Ruhe: Wer ein Foto ausdrücklich importiert, will es auch haben.
  /// [mitSternen] ist `false`, wenn die Sichtung der Kammer das letzte Wort
  /// hat.
  Future<void> wendeAn(
    AppDatabase db,
    String id, {
    bool mitSternen = true,
  }) async {
    // Beim Import ist die Datei womöglich gerade hinter ihr JPEG gerückt.
    // Dann ergänzt die Beilage die Hauptversion, statt ihre Angaben zu
    // ersetzen – wie beim Stapeln selbst, sonst hinge das Ergebnis davon ab,
    // welche Datei zuerst ankam.
    final ziel = await db.sichtbareFassung(id);
    final oben = ziel == id ? null : await db.assetById(ziel);
    id = ziel;
    if (sterne case final s? when mitSternen && s > (oben?.rating ?? -1)) {
      await db.fuehreAus(BewertungSetzen([id], s));
    }
    if (farbe != null && oben?.colorLabel == null) {
      await db.fuehreAus(FarbmarkeSetzen([id], farbe));
    }
    if (beschreibung case final b?
        when oben?.description?.trim().isNotEmpty != true) {
      await db.fuehreAus(BeschreibungSetzen([id], b));
    }
    for (final t in schlagwoerter) {
      await db.fuehreAus(SchlagwortAnheften([id], t));
    }
    // Der Ort aus der Kamera bleibt: Er ist die genauere Angabe.
    if (breite != null && laenge != null) {
      final a = await db.assetById(id);
      if (a != null && a.latitude == null) {
        await db.fuehreAus(OrtSetzen([id], breite, laenge));
      }
    }
  }
}

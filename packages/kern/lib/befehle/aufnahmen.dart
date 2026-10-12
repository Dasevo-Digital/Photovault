part of 'befehl.dart';

/// Favorit an oder aus – für eine oder viele Aufnahmen.
final class FavoritSetzen extends Befehl<void> {
  const FavoritSetzen(this.ids, this.favorit);

  static FavoritSetzen aus(Map<String, Object?> w) =>
      FavoritSetzen(_kennungen(w['ids']), w['favorit']! as bool);

  final List<String> ids;
  final bool favorit;

  @override
  String get art => 'favoritSetzen';

  @override
  Map<String, Object?> get werte => {'ids': ids, 'favorit': favorit};

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1
      ? db.setFavorite(ids.single, favorit)
      : db.setFavoriteBulk(ids, favorit);
}

/// Sterne von 0 bis 5.
final class BewertungSetzen extends Befehl<void> {
  const BewertungSetzen(this.ids, this.bewertung);

  static BewertungSetzen aus(Map<String, Object?> w) =>
      BewertungSetzen(_kennungen(w['ids']), w['bewertung']! as int);

  final List<String> ids;
  final int bewertung;

  @override
  String get art => 'bewertungSetzen';

  @override
  Map<String, Object?> get werte => {'ids': ids, 'bewertung': bewertung};

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1
      ? db.setRating(ids.single, bewertung)
      : db.setRatingBulk(ids, bewertung);
}

/// Die Farbmarke; `null` nimmt sie ab.
final class FarbmarkeSetzen extends Befehl<void> {
  const FarbmarkeSetzen(this.ids, this.farbe);

  static FarbmarkeSetzen aus(Map<String, Object?> w) =>
      FarbmarkeSetzen(_kennungen(w['ids']), w['farbe'] as String?);

  final List<String> ids;
  final String? farbe;

  @override
  String get art => 'farbmarkeSetzen';

  @override
  Map<String, Object?> get werte => {'ids': ids, 'farbe': farbe};

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1
      ? db.setColorLabel(ids.single, farbe)
      : db.setColorLabelBulk(ids, farbe);
}

/// Die Beschreibung, die der Nutzer selbst schreibt.
final class BeschreibungSetzen extends Befehl<void> {
  const BeschreibungSetzen(this.ids, this.beschreibung);

  static BeschreibungSetzen aus(Map<String, Object?> w) =>
      BeschreibungSetzen(_kennungen(w['ids']), w['beschreibung']! as String);

  final List<String> ids;
  final String beschreibung;

  @override
  String get art => 'beschreibungSetzen';

  @override
  Map<String, Object?> get werte => {'ids': ids, 'beschreibung': beschreibung};

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1
      ? db.setDescription(ids.single, beschreibung)
      : db.setDescriptionBulk(ids, beschreibung);
}

/// Favorit, Sterne und Farbmarke je Aufnahme auf einmal – so stellt das
/// Rückgängig einer Mehrfachmarkierung den Stand davor wieder her.
final class MarkierungenSetzen extends Befehl<void> {
  const MarkierungenSetzen(this.markierungen);

  static MarkierungenSetzen aus(Map<String, Object?> w) => MarkierungenSetzen({
    for (final e in (w['markierungen']! as Map).cast<String, Object?>().entries)
      e.key: () {
        final m = (e.value! as Map).cast<String, Object?>();
        return (
          favorit: m['favorit']! as bool,
          bewertung: m['bewertung']! as int,
          farbe: m['farbe'] as String?,
        );
      }(),
  });

  final Map<String, ({bool favorit, int bewertung, String? farbe})>
  markierungen;

  @override
  String get art => 'markierungenSetzen';

  @override
  Map<String, Object?> get werte => {
    'markierungen': {
      for (final e in markierungen.entries)
        e.key: {
          'favorit': e.value.favorit,
          'bewertung': e.value.bewertung,
          'farbe': e.value.farbe,
        },
    },
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeMarkierungen(markierungen);
}

/// Ort von Hand: Koordinaten setzen oder (beide `null`) entfernen.
final class OrtSetzen extends Befehl<void> {
  const OrtSetzen(this.ids, this.breite, this.laenge);

  static OrtSetzen aus(Map<String, Object?> w) => OrtSetzen(
    _kennungen(w['ids']),
    (w['breite'] as num?)?.toDouble(),
    (w['laenge'] as num?)?.toDouble(),
  );

  final List<String> ids;
  final double? breite;
  final double? laenge;

  @override
  String get art => 'ortSetzen';

  @override
  Map<String, Object?> get werte => {
    'ids': ids,
    'breite': breite,
    'laenge': laenge,
  };

  @override
  Future<void> anwenden(AppDatabase db) => ids.length == 1
      ? db.setLocation(ids.single, breite, laenge)
      : db.setLocationBulk(ids, breite, laenge);
}

/// Kamera, Objektiv und Belichtung einer Aufnahme.
final class KameraangabenSetzen extends Befehl<void> {
  const KameraangabenSetzen(this.id, this.angaben);

  static KameraangabenSetzen aus(Map<String, Object?> w) {
    final a = _abbildung(w['angaben']);
    double? zahl(String k) => (a[k] as num?)?.toDouble();
    return KameraangabenSetzen(
      w['id']! as String,
      CameraInfo(
        make: a['make'] as String?,
        model: a['model'] as String?,
        lensModel: a['lensModel'] as String?,
        focalLengthMm: zahl('focalLengthMm'),
        fNumber: zahl('fNumber'),
        iso: a['iso'] as int?,
        exposureTimeSeconds: zahl('exposureTimeSeconds'),
        exposureBiasEv: zahl('exposureBiasEv'),
        focalLength35mm: zahl('focalLength35mm'),
      ),
    );
  }

  final String id;
  final CameraInfo angaben;

  @override
  String get art => 'kameraangabenSetzen';

  @override
  Map<String, Object?> get werte => {
    'id': id,
    'angaben': {
      'make': angaben.make,
      'model': angaben.model,
      'lensModel': angaben.lensModel,
      'focalLengthMm': angaben.focalLengthMm,
      'fNumber': angaben.fNumber,
      'iso': angaben.iso,
      'exposureTimeSeconds': angaben.exposureTimeSeconds,
      'exposureBiasEv': angaben.exposureBiasEv,
      'focalLength35mm': angaben.focalLength35mm,
    },
  };

  @override
  Future<void> anwenden(AppDatabase db) => db.setCameraMetadata(id, angaben);
}

/// Die Bildbeschreibung von Hand (deutsch oder englisch); leer nimmt sie
/// zurück.
final class BildbeschreibungSetzen extends Befehl<void> {
  const BildbeschreibungSetzen(this.id, this.text, {required this.deutsch});

  static BildbeschreibungSetzen aus(Map<String, Object?> w) =>
      BildbeschreibungSetzen(
        w['id']! as String,
        w['text'] as String?,
        deutsch: w['deutsch']! as bool,
      );

  final String id;
  final String? text;
  final bool deutsch;

  @override
  String get art => 'bildbeschreibungSetzen';

  @override
  Map<String, Object?> get werte => {
    'id': id,
    'text': text,
    'deutsch': deutsch,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setAiCaptionVonHand(id, text, deutsch: deutsch);
}

/// Ein geschätztes Aufnahmejahr übernehmen.
final class JahrSchaetzen extends Befehl<void> {
  const JahrSchaetzen(this.id, this.jahr);

  static JahrSchaetzen aus(Map<String, Object?> w) =>
      JahrSchaetzen(w['id']! as String, w['jahr']! as int);

  final String id;
  final int jahr;

  @override
  String get art => 'jahrSchaetzen';

  @override
  Map<String, Object?> get werte => {'id': id, 'jahr': jahr};

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeGeschaetztesJahr(id, jahr);
}

/// Der Dateiname, unter dem eine Aufnahme geführt wird.
final class DateinameSetzen extends Befehl<void> {
  const DateinameSetzen(this.id, this.name);

  static DateinameSetzen aus(Map<String, Object?> w) =>
      DateinameSetzen(w['id']! as String, w['name']! as String);

  final String id;
  final String name;

  @override
  String get art => 'dateinameSetzen';

  @override
  Map<String, Object?> get werte => {'id': id, 'name': name};

  @override
  Future<void> anwenden(AppDatabase db) => db.setOriginalFileName(id, name);
}

/// In den Papierkorb legen.
final class InDenPapierkorb extends Befehl<void> {
  const InDenPapierkorb(this.ids);

  static InDenPapierkorb aus(Map<String, Object?> w) =>
      InDenPapierkorb(_kennungen(w['ids']));

  final List<String> ids;

  @override
  String get art => 'inDenPapierkorb';

  @override
  Map<String, Object?> get werte => {'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.moveToTrash(ids);
}

/// Aus dem Papierkorb zurückholen.
final class AusDemPapierkorb extends Befehl<void> {
  const AusDemPapierkorb(this.ids);

  static AusDemPapierkorb aus(Map<String, Object?> w) =>
      AusDemPapierkorb(_kennungen(w['ids']));

  final List<String> ids;

  @override
  String get art => 'ausDemPapierkorb';

  @override
  Map<String, Object?> get werte => {'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) => db.restoreFromTrash(ids);
}

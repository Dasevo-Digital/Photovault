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

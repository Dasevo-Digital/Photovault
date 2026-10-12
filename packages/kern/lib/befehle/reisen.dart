part of 'befehl.dart';

/// Eine Reise samt ihren Aufnahmen.
final class ReiseAnlegen extends Befehl<void> {
  ReiseAnlegen(Insertable<ReisenData> reise, this.ids)
    : reise = _zeileAlsWerte(reise);

  const ReiseAnlegen._(this.reise, this.ids);

  static ReiseAnlegen aus(Map<String, Object?> w) =>
      ReiseAnlegen._(_abbildung(w['reise']), _kennungen(w['ids']));

  final Map<String, Object?> reise;
  final List<String> ids;

  @override
  String get art => 'reiseAnlegen';

  @override
  Map<String, Object?> get werte => {'reise': reise, 'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.reiseAnlegen(_zeileAus(db.reisen, reise), ids);
}

/// Name, Zeitraum, Notiz oder Titelbild einer Reise – was gesetzt ist.
final class ReiseAendern extends Befehl<void> {
  ReiseAendern(this.reiseId, Insertable<ReisenData> aenderung)
    : aenderung = _zeileAlsWerte(aenderung);

  const ReiseAendern._(this.reiseId, this.aenderung);

  static ReiseAendern aus(Map<String, Object?> w) =>
      ReiseAendern._(w['reiseId']! as String, _abbildung(w['aenderung']));

  final String reiseId;
  final Map<String, Object?> aenderung;

  @override
  String get art => 'reiseAendern';

  @override
  Map<String, Object?> get werte => {
    'reiseId': reiseId,
    'aenderung': aenderung,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.reiseAendern(reiseId, _zeileAus(db.reisen, aenderung));
}

final class ReiseLoeschen extends Befehl<void> {
  const ReiseLoeschen(this.reiseId);

  static ReiseLoeschen aus(Map<String, Object?> w) =>
      ReiseLoeschen(w['reiseId']! as String);

  final String reiseId;

  @override
  String get art => 'reiseLoeschen';

  @override
  Map<String, Object?> get werte => {'reiseId': reiseId};

  @override
  Future<void> anwenden(AppDatabase db) => db.reiseLoeschen(reiseId);
}

/// Mehrere Reisen gehen in [ziel] auf.
final class ReisenZusammenfuehren extends Befehl<void> {
  const ReisenZusammenfuehren(this.ziel, this.quellen);

  static ReisenZusammenfuehren aus(Map<String, Object?> w) =>
      ReisenZusammenfuehren(w['ziel']! as String, _kennungen(w['quellen']));

  final String ziel;
  final List<String> quellen;

  @override
  String get art => 'reisenZusammenfuehren';

  @override
  Map<String, Object?> get werte => {'ziel': ziel, 'quellen': quellen};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.reisenZusammenfuehren(ziel, quellen);
}

/// Die Notiz zu einem Reisetag; leerer Text löscht sie.
final class ReisetagnotizSetzen extends Befehl<void> {
  const ReisetagnotizSetzen(this.reiseId, this.tag, this.text);

  static ReisetagnotizSetzen aus(Map<String, Object?> w) => ReisetagnotizSetzen(
    w['reiseId']! as String,
    DateTime.parse(w['tag']! as String),
    w['text']! as String,
  );

  final String reiseId;
  final DateTime tag;
  final String text;

  @override
  String get art => 'reisetagnotizSetzen';

  @override
  Map<String, Object?> get werte => {
    'reiseId': reiseId,
    'tag': tag.toIso8601String(),
    'text': text,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeReisetagnotiz(reiseId, tag, text);
}

/// Die Art einer Reise (Städtereise, Wandern …) als Kennung.
final class ReiseartSetzen extends Befehl<void> {
  const ReiseartSetzen(this.reiseId, this.reiseart);

  static ReiseartSetzen aus(Map<String, Object?> w) =>
      ReiseartSetzen(w['reiseId']! as String, w['reiseart']! as String);

  final String reiseId;
  final String reiseart;

  @override
  String get art => 'reiseartSetzen';

  @override
  Map<String, Object?> get werte => {'reiseId': reiseId, 'reiseart': reiseart};

  @override
  Future<void> anwenden(AppDatabase db) => db.setzeReiseart(reiseId, reiseart);
}

/// Welche Aufnahmen zu einer Reise gehören – alle auf einmal.
final class AufnahmenDerReiseSetzen extends Befehl<void> {
  const AufnahmenDerReiseSetzen(this.reiseId, this.ids);

  static AufnahmenDerReiseSetzen aus(Map<String, Object?> w) =>
      AufnahmenDerReiseSetzen(
        w['reiseId']! as String,
        _kennungen(w['ids']).toSet(),
      );

  final String reiseId;
  final Set<String> ids;

  @override
  String get art => 'aufnahmenDerReiseSetzen';

  @override
  Map<String, Object?> get werte => {
    'reiseId': reiseId,
    'ids': [...ids],
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeAufnahmenDerReise(reiseId, ids);
}

/// Einen Reisevorschlag nicht mehr zeigen.
final class ReisevorschlagVerwerfen extends Befehl<void> {
  const ReisevorschlagVerwerfen(this.schluessel);

  static ReisevorschlagVerwerfen aus(Map<String, Object?> w) =>
      ReisevorschlagVerwerfen(w['schluessel']! as String);

  final String schluessel;

  @override
  String get art => 'reisevorschlagVerwerfen';

  @override
  Map<String, Object?> get werte => {'schluessel': schluessel};

  @override
  Future<void> anwenden(AppDatabase db) => db.verwirfReisevorschlag(schluessel);
}

/// Eine Aktivität samt ihren Aufnahmen.
final class AktivitaetAnlegen extends Befehl<void> {
  AktivitaetAnlegen(Insertable<AktivitaetenData> aktivitaet, this.ids)
    : aktivitaet = _zeileAlsWerte(aktivitaet);

  const AktivitaetAnlegen._(this.aktivitaet, this.ids);

  static AktivitaetAnlegen aus(Map<String, Object?> w) =>
      AktivitaetAnlegen._(_abbildung(w['aktivitaet']), _kennungen(w['ids']));

  final Map<String, Object?> aktivitaet;
  final List<String> ids;

  @override
  String get art => 'aktivitaetAnlegen';

  @override
  Map<String, Object?> get werte => {'aktivitaet': aktivitaet, 'ids': ids};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.aktivitaetAnlegen(_zeileAus(db.aktivitaeten, aktivitaet), ids);
}

/// Was an einer Aktivität gesetzt ist, ändern.
final class AktivitaetAendern extends Befehl<void> {
  AktivitaetAendern(this.aktivitaetId, Insertable<AktivitaetenData> aenderung)
    : aenderung = _zeileAlsWerte(aenderung);

  const AktivitaetAendern._(this.aktivitaetId, this.aenderung);

  static AktivitaetAendern aus(Map<String, Object?> w) => AktivitaetAendern._(
    w['aktivitaetId']! as String,
    _abbildung(w['aenderung']),
  );

  final String aktivitaetId;
  final Map<String, Object?> aenderung;

  @override
  String get art => 'aktivitaetAendern';

  @override
  Map<String, Object?> get werte => {
    'aktivitaetId': aktivitaetId,
    'aenderung': aenderung,
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.aktivitaetAendern(aktivitaetId, _zeileAus(db.aktivitaeten, aenderung));
}

final class AktivitaetLoeschen extends Befehl<void> {
  const AktivitaetLoeschen(this.aktivitaetId);

  static AktivitaetLoeschen aus(Map<String, Object?> w) =>
      AktivitaetLoeschen(w['aktivitaetId']! as String);

  final String aktivitaetId;

  @override
  String get art => 'aktivitaetLoeschen';

  @override
  Map<String, Object?> get werte => {'aktivitaetId': aktivitaetId};

  @override
  Future<void> anwenden(AppDatabase db) => db.aktivitaetLoeschen(aktivitaetId);
}

/// Welche Aufnahmen zu einer Aktivität gehören – alle auf einmal.
final class AufnahmenDerAktivitaetSetzen extends Befehl<void> {
  const AufnahmenDerAktivitaetSetzen(this.aktivitaetId, this.ids);

  static AufnahmenDerAktivitaetSetzen aus(Map<String, Object?> w) =>
      AufnahmenDerAktivitaetSetzen(
        w['aktivitaetId']! as String,
        _kennungen(w['ids']).toSet(),
      );

  final String aktivitaetId;
  final Set<String> ids;

  @override
  String get art => 'aufnahmenDerAktivitaetSetzen';

  @override
  Map<String, Object?> get werte => {
    'aktivitaetId': aktivitaetId,
    'ids': [...ids],
  };

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.setzeAufnahmenDerAktivitaet(aktivitaetId, ids);
}

/// Einen Aktivitätsvorschlag nicht mehr zeigen.
final class AktivitaetsvorschlagVerwerfen extends Befehl<void> {
  const AktivitaetsvorschlagVerwerfen(this.schluessel);

  static AktivitaetsvorschlagVerwerfen aus(Map<String, Object?> w) =>
      AktivitaetsvorschlagVerwerfen(w['schluessel']! as String);

  final String schluessel;

  @override
  String get art => 'aktivitaetsvorschlagVerwerfen';

  @override
  Map<String, Object?> get werte => {'schluessel': schluessel};

  @override
  Future<void> anwenden(AppDatabase db) =>
      db.verwirfAktivitaetsvorschlag(schluessel);
}

/// Eine GPX-Spur samt Punkten löschen.
final class SpurLoeschen extends Befehl<void> {
  const SpurLoeschen(this.spurId);

  static SpurLoeschen aus(Map<String, Object?> w) =>
      SpurLoeschen(w['spurId']! as String);

  final String spurId;

  @override
  String get art => 'spurLoeschen';

  @override
  Map<String, Object?> get werte => {'spurId': spurId};

  @override
  Future<void> anwenden(AppDatabase db) => db.spurLoeschen(spurId);
}

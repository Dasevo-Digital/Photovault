/// Kurzlebige Einträge, die Anfragen ohne Anmeldung anlegen: die
/// Herausforderungen der Passkeys und die angefangenen Anmeldungen über
/// OIDC (#426).
///
/// **Gedeckelt.** Höchstens [insgesamt] Einträge und je Absender höchstens
/// [jeAbsender]. Kommt einer dazu, wenn es voll ist, fällt der älteste
/// heraus – zuerst der desselben Absenders, sonst der älteste überhaupt.
/// Vorher wuchs die eine Ablage ohne Grenze, und die andere wurde ab 1000
/// Einträgen ganz geleert, mit allen echten Anmeldungen darin.
///
/// **Aufgeräumt wird nur vorn.** Alle Einträge leben gleich lang
/// ([dauer]); in der Reihenfolge, in der sie dazukamen, laufen sie also
/// auch ab. Vorher ging jede Anfrage die ganze Ablage durch.
class Kurzablage<W> {
  Kurzablage({
    required this.dauer,
    required this.insgesamt,
    required this.jeAbsender,
    DateTime Function()? uhr,
  }) : _uhr = uhr ?? DateTime.now;

  final Duration dauer;
  final int insgesamt;
  final int jeAbsender;
  final DateTime Function() _uhr;

  final _eintraege = <String, ({W wert, String absender, DateTime ablauf})>{};
  final _vonAbsender = <String, List<String>>{};

  /// Wie viele Einträge gerade gelten.
  int get length {
    raeumeAuf();
    return _eintraege.length;
  }

  /// Legt [wert] unter [schluessel] ab, für [absender] gezählt.
  void lege(String schluessel, W wert, {required String absender}) {
    raeumeAuf();
    _entferne(schluessel);
    final eigene = _vonAbsender[absender];
    while (eigene != null && eigene.isNotEmpty && eigene.length >= jeAbsender) {
      _entferne(eigene.first);
    }
    while (_eintraege.isNotEmpty && _eintraege.length >= insgesamt) {
      _entferne(_eintraege.keys.first);
    }
    _eintraege[schluessel] = (
      wert: wert,
      absender: absender,
      ablauf: _uhr().add(dauer),
    );
    _vonAbsender.putIfAbsent(absender, () => []).add(schluessel);
  }

  /// Nimmt den Eintrag unter [schluessel] heraus – einmal; `null`, wenn es
  /// ihn nicht (mehr) gibt.
  W? nimm(String schluessel) {
    raeumeAuf();
    final e = _eintraege[schluessel];
    if (e == null) return null;
    _entferne(schluessel);
    return e.wert;
  }

  /// Entfernt, was abgelaufen ist.
  void raeumeAuf() {
    final jetzt = _uhr();
    while (_eintraege.isNotEmpty) {
      final erster = _eintraege.keys.first;
      if (!_eintraege[erster]!.ablauf.isBefore(jetzt)) break;
      _entferne(erster);
    }
  }

  void _entferne(String schluessel) {
    final e = _eintraege.remove(schluessel);
    if (e == null) return;
    final liste = _vonAbsender[e.absender];
    if (liste == null) return;
    liste.remove(schluessel);
    if (liste.isEmpty) _vonAbsender.remove(e.absender);
  }
}

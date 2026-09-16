/// Die Meldungen der App – gesammelt statt vergessen.
///
/// **Bisher gab es 82 Meldungen in 24 Dateien und keine Historie.** Jede
/// war eine SnackBar unten am Rand: vier Sekunden da, dann weg. Wer in
/// dem Moment woanders hinsah, hat sie verpasst, und es gab keinen Ort,
/// an dem sie nachzulesen gewesen wäre.
///
/// Dieser Dienst trennt zwei Dinge, die die SnackBar vermischt hat: das
/// **Erscheinen** (kurz, oben rechts, wegklickbar) und das **Nachlesen**
/// (der Verlauf hinter der Glocke). Die Regeln – wann etwas verblasst,
/// was zusammengefasst wird, was liegen bleibt – stehen als reine
/// Funktionen darüber, damit sie prüfbar sind, ohne ein Fenster zu
/// öffnen.
///
/// **Nur im Speicher.** Eine Meldung, die den Neustart überlebt, ist
/// keine Meldung mehr, sondern eine Aufgabe – und dafür gibt es die
/// Aufgabenliste.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wie ernst eine Meldung ist. Bestimmt Farbe, Symbol und Verweildauer.
enum Meldungsart { hinweis, erfolg, warnung, fehler }

/// Ein Knopf an einer Meldung – „Rückgängig", „Öffnen", „Erneut".
typedef Meldungsaktion = ({String beschriftung, void Function() beiDruck});

/// Eine einzelne Meldung.
@immutable
class Meldung {
  /// Laufende Nummer und zugleich Identität. Zwei Meldungen mit
  /// demselben Text sind nicht dieselbe Meldung – deshalb keine
  /// Kennung aus dem Inhalt.
  final int nummer;
  final Meldungsart art;
  final String text;
  final DateTime zeit;
  final Meldungsaktion? aktion;

  /// Wie lange sie stehen bleibt – `null` heisst: bis jemand sie
  /// wegklickt. Steht an der Meldung, nicht nur in der Uhr, damit der
  /// ablaufende Balken dieselbe Zahl benutzt wie das Verschwinden.
  final Duration? dauer;

  /// Wie oft dieselbe Meldung hintereinander kam. 1 ist der Normalfall;
  /// darüber steht „(3×)" daneben, statt dass sich der Stapel füllt.
  final int anzahl;

  const Meldung({
    required this.nummer,
    required this.art,
    required this.text,
    required this.zeit,
    this.aktion,
    this.dauer,
    this.anzahl = 1,
  });

  Meldung nochmal(DateTime zeit) => Meldung(
        nummer: nummer,
        art: art,
        text: text,
        zeit: zeit,
        aktion: aktion,
        dauer: dauer,
        anzahl: anzahl + 1,
      );
}

/// Wie lange eine Meldung stehen bleibt – `null` heisst: bis jemand sie
/// wegklickt.
///
/// **Ein Fehler verblasst nicht.** Er ist der einzige Fall, in dem das
/// Verpassen etwas kostet: Wer nicht erfährt, dass ein Export
/// fehlgeschlagen ist, hält ihn für erledigt. Alles andere geht von
/// selbst, denn eine Meldung, die man wegklicken muss, wird zu einem
/// Möbelstück.
///
/// **Mit Knopf dauert es länger.** Vier Sekunden reichen, um einen Satz
/// zu lesen, nicht um ihn zu lesen *und* zu handeln. Das ist dieselbe
/// Überlegung, die vorher in `meldung_mit_knopf.dart` stand – Flutters
/// eigene Antwort darauf war `persist = persist ?? action != null`, also
/// „für immer", und genau die hat den Fehler erzeugt, der diese Stufe
/// ausgelöst hat.
Duration? meldungsdauer(Meldungsart art, {bool mitAktion = false}) =>
    switch (art) {
      Meldungsart.fehler => null,
      Meldungsart.warnung => const Duration(seconds: 8),
      _ => mitAktion ? const Duration(seconds: 8) : const Duration(seconds: 4),
    };

/// Ob eine neue Meldung in einer bereits stehenden aufgeht.
///
/// Gleiche Art und gleicher Wortlaut heisst: dasselbe ist noch einmal
/// passiert. Fünf Dateien, die nacheinander nicht lesbar sind, sollen
/// fünfmal zählen und einmal dastehen.
///
/// **Meldungen mit Knopf gehen nie ineinander auf.** Der Knopf gehört zu
/// genau einem Vorgang; „Rückgängig" an einer zusammengefassten Meldung
/// nähme die falsche Löschung zurück.
bool gehtAufIn(Meldung stehende, Meldungsart art, String text,
        {required bool hatAktion}) =>
    !hatAktion &&
    stehende.aktion == null &&
    stehende.art == art &&
    stehende.text == text;

/// Höchstens so viele Meldungen stehen gleichzeitig da. Darüber weicht
/// die älteste – ein Stapel, der den halben Bildschirm füllt, verdeckt
/// genau das, worüber er berichtet.
const int hoechstensSichtbar = 4;

/// So viele Meldungen hält der Verlauf. Ältere fallen hinten heraus.
const int verlaufsLaenge = 50;

/// Sammelt die Meldungen und lässt sie zur rechten Zeit verblassen.
class Meldungsdienst extends ChangeNotifier {
  /// Der Dienst der laufenden App. Ein Einzelstück, weil eine Meldung
  /// von überall kommt – aus einem Knopfdruck, aus einem Hintergrundlauf,
  /// aus einem `catch` tief in einem Dienst. Für Tests lässt sich ein
  /// eigener bauen.
  static final Meldungsdienst zentral = Meldungsdienst();

  final _sichtbare = <Meldung>[];
  final _verlauf = <Meldung>[];
  final _uhren = <int, Timer>{};
  int _naechsteNummer = 1;
  int _ungelesen = 0;

  /// Die gerade eingeblendeten, älteste zuerst.
  List<Meldung> get sichtbare => List.unmodifiable(_sichtbare);

  /// Alles, was gemeldet wurde – **neueste zuerst**, wie man einen
  /// Verlauf liest.
  List<Meldung> get verlauf => List.unmodifiable(_verlauf);

  /// Wie viele seit dem letzten Blick in den Verlauf dazugekommen sind.
  int get ungelesen => _ungelesen;

  /// Meldet etwas. Gibt die Meldung zurück – die zusammengefasste, falls
  /// dieselbe schon dasteht.
  Meldung zeige(
    String text, {
    Meldungsart art = Meldungsart.hinweis,
    Meldungsaktion? aktion,
    Duration? dauer,
  }) {
    final jetzt = DateTime.now();

    final stelle = _sichtbare
        .indexWhere((m) => gehtAufIn(m, art, text, hatAktion: aktion != null));
    if (stelle >= 0) {
      final gebuendelt = _sichtbare[stelle].nochmal(jetzt);
      _sichtbare[stelle] = gebuendelt;
      _ersetzeImVerlauf(gebuendelt);
      _stelleUhr(gebuendelt, dauer ?? meldungsdauer(art));
      _ungelesen++;
      notifyListeners();
      return gebuendelt;
    }

    final neu = Meldung(
      nummer: _naechsteNummer++,
      art: art,
      text: text,
      zeit: jetzt,
      aktion: aktion,
      dauer: dauer ?? meldungsdauer(art, mitAktion: aktion != null),
    );
    _sichtbare.add(neu);
    // Der Älteste weicht, nicht der Neueste: Was gerade passiert ist,
    // interessiert mehr als das von vor zehn Sekunden. Verloren ist er
    // nicht – er steht im Verlauf.
    while (_sichtbare.length > hoechstensSichtbar) {
      _schliesseStill(_sichtbare.first.nummer);
    }
    _verlauf.insert(0, neu);
    if (_verlauf.length > verlaufsLaenge) _verlauf.removeLast();
    _ungelesen++;
    _stelleUhr(neu, neu.dauer);
    notifyListeners();
    return neu;
  }

  /// Kurzwege für die Aufrufer – `melde.fehler(t.exportFehlgeschlagen)`
  /// liest sich als das, was es ist.
  Meldung hinweis(String text, {Meldungsaktion? aktion}) =>
      zeige(text, aktion: aktion);
  Meldung erfolg(String text, {Meldungsaktion? aktion}) =>
      zeige(text, art: Meldungsart.erfolg, aktion: aktion);
  Meldung warnung(String text, {Meldungsaktion? aktion}) =>
      zeige(text, art: Meldungsart.warnung, aktion: aktion);
  Meldung fehler(String text, {Meldungsaktion? aktion}) =>
      zeige(text, art: Meldungsart.fehler, aktion: aktion);

  /// Blendet eine Meldung aus. Im Verlauf bleibt sie.
  void schliesse(int nummer) {
    if (_schliesseStill(nummer)) notifyListeners();
  }

  void alleSchliessen() {
    if (_sichtbare.isEmpty) return;
    for (final m in [..._sichtbare]) {
      _schliesseStill(m.nummer);
    }
    notifyListeners();
  }

  /// Der Verlauf wurde angesehen.
  void verlaufGelesen() {
    if (_ungelesen == 0) return;
    _ungelesen = 0;
    notifyListeners();
  }

  void verlaufLeeren() {
    if (_verlauf.isEmpty && _sichtbare.isEmpty) return;
    _verlauf.clear();
    alleSchliessen();
    _ungelesen = 0;
    notifyListeners();
  }

  bool _schliesseStill(int nummer) {
    _uhren.remove(nummer)?.cancel();
    final vorher = _sichtbare.length;
    _sichtbare.removeWhere((m) => m.nummer == nummer);
    return _sichtbare.length != vorher;
  }

  void _ersetzeImVerlauf(Meldung m) {
    final i = _verlauf.indexWhere((v) => v.nummer == m.nummer);
    if (i >= 0) _verlauf[i] = m;
  }

  /// **Eine Frist läuft nur, solange jemand zusieht.**
  ///
  /// Ohne Zuhörer zeigt niemand die Meldung an – ein Ablauf hätte dann
  /// nichts zu beenden. Das ist nicht nur sparsam, sondern nötig: Im
  /// Widget-Test hängt sonst nach jedem Bildschirm, der etwas meldet,
  /// eine Uhr in der Luft, und der Rahmen bricht mit „A Timer is still
  /// pending" ab – in Tests, die mit Meldungen gar nichts zu tun haben.
  void _stelleUhr(Meldung m, Duration? dauer) {
    _uhren.remove(m.nummer)?.cancel();
    if (dauer == null || !hasListeners) return;
    _uhren[m.nummer] = Timer(dauer, () => schliesse(m.nummer));
  }

  @override
  void addListener(VoidCallback listener) {
    final ersterZuschauer = !hasListeners;
    super.addListener(listener);
    // Was in der Zwischenzeit auflief, bekommt jetzt seine Frist.
    if (ersterZuschauer) {
      for (final m in _sichtbare) {
        _stelleUhr(m, m.dauer);
      }
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _uhrenAnhalten();
  }

  void _uhrenAnhalten() {
    for (final u in _uhren.values) {
      u.cancel();
    }
    _uhren.clear();
  }

  @override
  void dispose() {
    _uhrenAnhalten();
    super.dispose();
  }
}

/// Der Dienst der laufenden App, kurz.
Meldungsdienst get melde => Meldungsdienst.zentral;

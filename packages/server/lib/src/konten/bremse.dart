/// Bremst das Raten von Passwörtern und Codes – je Absender und je Name.
///
/// **Je Absender:** Mehr als [jeAdresse] Fehlschläge in [fenster] von
/// einer Adresse, und sie wird abgewiesen, bevor überhaupt gerechnet wird.
/// Das schützt auch die Rechenzeit: Jede Passwortprüfung kostet 19 MiB und
/// einige zehn Millisekunden.
///
/// **Je Name:** Nach fünf Fehlschlägen in Folge ist ein Konto eine Minute
/// gesperrt, danach verdoppelt sich die Sperre mit jedem weiteren bis zu
/// einer Stunde (siehe [sperrdauer]). Der Zähler eines Kontos steht in der
/// Serverdatenbank; Namen, die es nicht gibt, zählt diese Klasse genauso –
/// sonst verriete die Sperre, welche Namen es gibt.
class Bremse {
  Bremse({
    DateTime Function()? uhr,
    this.jeAdresse = 10,
    this.fenster = const Duration(minutes: 15),
  }) : _uhr = uhr ?? DateTime.now;

  final DateTime Function() _uhr;
  final int jeAdresse;
  final Duration fenster;

  final _fehlschlaege = <String, List<DateTime>>{};
  final _unbekannte = <String, ({int fehlversuche, DateTime? bis})>{};

  /// Ab wie vielen Fehlschlägen in Folge ein Name gesperrt wird.
  static const sperreAb = 5;

  /// Wie lange nach [fehlversuche] Fehlschlägen in Folge gesperrt wird.
  static Duration? sperrdauer(int fehlversuche) {
    if (fehlversuche < sperreAb) return null;
    final stufe = fehlversuche - sperreAb;
    return Duration(minutes: stufe >= 6 ? 60 : 1 << stufe);
  }

  /// Wie lange [adresse] noch warten muss; `null`, wenn sie darf.
  Duration? wartezeit(String adresse) {
    final liste = _aufgeraeumt(adresse);
    if (liste.length < jeAdresse) return null;
    return liste.first.add(fenster).difference(_uhr());
  }

  void fehlschlag(String adresse) {
    _aufgeraeumt(adresse).add(_uhr());
  }

  List<DateTime> _aufgeraeumt(String adresse) {
    final grenze = _uhr().subtract(fenster);
    final liste = _fehlschlaege.putIfAbsent(adresse, () => []);
    liste.removeWhere((t) => t.isBefore(grenze));
    if (_fehlschlaege.length > 10000) {
      _fehlschlaege.removeWhere((_, l) => l.isEmpty);
    }
    return liste;
  }

  /// Bis wann ein unbekannter Name „gesperrt“ ist.
  DateTime? unbekanntGesperrtBis(String name) {
    final bis = _unbekannte[name.toLowerCase()]?.bis;
    return bis != null && bis.isAfter(_uhr()) ? bis : null;
  }

  /// Ein Fehlschlag für einen unbekannten Namen – gezählt wie bei einem
  /// Konto.
  void unbekanntFehlschlag(String name) {
    final schluessel = name.toLowerCase();
    if (_unbekannte.length > 10000) _unbekannte.clear();
    final n = (_unbekannte[schluessel]?.fehlversuche ?? 0) + 1;
    final dauer = sperrdauer(n);
    _unbekannte[schluessel] = (
      fehlversuche: n,
      bis: dauer == null ? null : _uhr().add(dauer),
    );
  }
}

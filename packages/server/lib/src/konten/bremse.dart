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

  /// Höchstens so viele Adressen und unbekannte Namen merkt sich die
  /// Bremse. Mehr kommen nur bei einem Angriff mit sehr vielen Adressen
  /// oder Namen zusammen (ein IPv6-Netz hat Milliarden); dann gehen die,
  /// die am längsten nicht mehr da waren – nie alle auf einmal und nie die
  /// gerade gezählte.
  static const hoechstensEintraege = 10000;

  /// Wie lange [adresse] noch warten muss; `null`, wenn sie darf.
  Duration? wartezeit(String adresse) {
    final liste = _fehlschlaege[adresse];
    if (liste == null) return null;
    final grenze = _uhr().subtract(fenster);
    liste.removeWhere((t) => t.isBefore(grenze));
    if (liste.isEmpty) {
      _fehlschlaege.remove(adresse);
      return null;
    }
    if (liste.length < jeAdresse) return null;
    return liste.first.add(fenster).difference(_uhr());
  }

  /// Zählt einen Fehlschlag von [adresse].
  ///
  /// Eine Adresse steht nur mit mindestens einem Fehlschlag in der Liste,
  /// und frisch gezählte rücken ans Ende. Vorher legte schon jede Frage
  /// einen leeren Eintrag an; ab 10 000 Adressen räumte die Bremse nur die
  /// leeren weg – darunter den gerade angelegten der fragenden Adresse.
  /// Gezählt wurde dann in eine Liste, die niemand mehr ansah, und die
  /// Bremse war für jede Adresse still abgeschaltet.
  void fehlschlag(String adresse) {
    final grenze = _uhr().subtract(fenster);
    final liste = (_fehlschlaege.remove(adresse) ?? <DateTime>[])
      ..removeWhere((t) => t.isBefore(grenze))
      ..add(_uhr());
    if (_fehlschlaege.length >= hoechstensEintraege) {
      // Erst alles, was ganz abgelaufen ist, …
      _fehlschlaege.removeWhere((_, l) => l.last.isBefore(grenze));
      // … dann, falls noch nötig, die am längsten nicht gesehenen.
      _kuerze(_fehlschlaege);
    }
    _fehlschlaege[adresse] = liste;
  }

  /// Bis auf neun Zehntel von [hoechstensEintraege], die ältesten zuerst
  /// (eine Map behält die Reihenfolge des Einfügens). Mit Abstand, damit
  /// nicht jeder weitere Eintrag die ganze Map durchgeht.
  static void _kuerze(Map<String, Object> eintraege) {
    const ziel = hoechstensEintraege * 9 ~/ 10;
    final zuViel = eintraege.length - ziel;
    if (zuViel <= 0) return;
    for (final k in eintraege.keys.take(zuViel).toList()) {
      eintraege.remove(k);
    }
  }

  /// Bis wann ein unbekannter Name „gesperrt“ ist.
  DateTime? unbekanntGesperrtBis(String name) {
    final bis = _unbekannte[name.toLowerCase()]?.bis;
    return bis != null && bis.isAfter(_uhr()) ? bis : null;
  }

  /// Ein Fehlschlag für einen unbekannten Namen – gezählt wie bei einem
  /// Konto.
  ///
  /// Ist die Liste voll, gehen zuerst die Namen ohne laufende Sperre, dann
  /// die am längsten nicht mehr versuchten. Vorher wurde sie ganz geleert,
  /// und mit ihr jede laufende Sperre.
  void unbekanntFehlschlag(String name) {
    final schluessel = name.toLowerCase();
    final n = (_unbekannte.remove(schluessel)?.fehlversuche ?? 0) + 1;
    if (_unbekannte.length >= hoechstensEintraege) {
      final jetzt = _uhr();
      _unbekannte.removeWhere((_, e) => !(e.bis?.isAfter(jetzt) ?? false));
      _kuerze(_unbekannte);
    }
    final dauer = sperrdauer(n);
    _unbekannte[schluessel] = (
      fehlversuche: n,
      bis: dauer == null ? null : _uhr().add(dauer),
    );
  }
}

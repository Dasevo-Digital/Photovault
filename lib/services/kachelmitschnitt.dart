import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

/// Ein einzelner Kachelabruf, so wie er wirklich lief.
///
/// [status] und [fehler] schliessen einander **nicht** aus: Ein Abruf kann
/// mit 200 anfangen und beim Lesen des Rumpfes scheitern.
///
/// **Warum das kein unveränderliches Wertobjekt ist.** Der Eintrag
/// entsteht, sobald die Kopfzeilen da sind, und wächst danach weiter:
/// Bytes und wahre Dauer stehen erst fest, wenn der Rumpf durch ist. Ihn
/// erst am Ende anzulegen wäre die sauberere Bauform gewesen und hätte
/// die Hälfte der Abrufe verschluckt – siehe [abgebrochen].
class Kachelabruf {
  Kachelabruf({
    required this.zeit,
    required this.adresse,
    required this.dauer,
    this.status,
    this.fehler,
    this.bytes = 0,
    this.dauerverbindung = true,
    this.abgebrochen = false,
  });

  final DateTime zeit;
  final String adresse;
  final int? status;

  /// Ob der Server die Verbindung offen lassen wollte (`Connection:
  /// keep-alive` bzw. die Vorgabe von HTTP/1.1).
  ///
  /// **Die Angabe, um die es hier eigentlich geht.** Schliesst der Server
  /// nach jeder Kachel, muss für die nächste ein neuer TLS-Handschlag
  /// stattfinden – und genau so entstehen tausende Verbindungen für
  /// hunderte Kacheln.
  final bool dauerverbindung;

  /// Bis zu den Kopfzeilen, und nach dem Rumpf noch einmal fortgeschrieben.
  Duration dauer;
  int bytes;
  String? fehler;

  /// Der Rumpf wurde nie zu Ende gelesen.
  ///
  /// **Der häufigste Fall ist kein Fehler, sondern Absicht:** Entscheidet
  /// der `RetryClient`, es noch einmal zu versuchen, bricht er den Rumpf
  /// der gescheiterten Antwort sofort ab. Genauso hält es flutter_map mit
  /// Kacheln, die beim Ziehen aus dem Bild laufen. Ohne diese Spalte sähe
  /// beides aus wie ein Abruf, den es nie gegeben hat.
  bool abgebrochen;

  /// Angekommen: Der Server hat geliefert, und der Rumpf ist ganz
  /// gelesen worden. [abgebrochen] gehört ausdrücklich dazu – eine
  /// Kachel mit Status 200, deren Rumpf niemand zu Ende gelesen hat, ist
  /// nicht angekommen.
  bool get geglueckt =>
      status != null &&
      status! >= 200 &&
      status! < 300 &&
      fehler == null &&
      !abgebrochen;

  /// Die Kachel, um die es ging – `Stufe/x/y`, aus der Adresse gelesen.
  ///
  /// Für die Anzeige: Die volle Adresse ist über hundert Zeichen lang und
  /// in einer Liste nicht zu überblicken. Passt die Adresse nicht auf das
  /// übliche Muster, steht sie eben ganz da.
  String get kachel {
    final teile = Uri.parse(adresse).pathSegments;
    if (teile.length < 3) return adresse;
    final letzte = teile.sublist(teile.length - 3);
    final y = letzte[2].split('.').first;
    return '${letzte[0]}/${letzte[1]}/$y';
  }
}

/// Wie viele Abrufe der Mitschnitt höchstens aufhebt.
///
/// Die gemessene halbe Minute Zoomen brachte rund 500 Kacheln; fünftausend
/// Einträge decken damit ein Vielfaches davon ab, und sie kosten unter
/// einem Megabyte. Läuft es über, fallen die ÄLTESTEN heraus und der
/// Mitschnitt sagt in [Kachelbilanz.verworfen], wie viele.
const kachelMitschnittGrenze = 5000;

/// Was am Ende in der Übersicht steht – aus den Einträgen gerechnet und
/// sonst nichts.
///
/// Eine eigene Klasse mit einer reinen Rechenfunktion ([bilanzAus]), damit
/// sich die Zahlen prüfen lassen, ohne dass ein Netz, ein Server oder eine
/// Oberfläche im Spiel wäre. Genau daran hat es bei der Kachelfrage
/// bisher gefehlt: gemessen wurde von aussen, mit `log show`.
@immutable
class Kachelbilanz {
  const Kachelbilanz({
    required this.abrufe,
    required this.verbindungen,
    required this.adressen,
    required this.wiederholte,
    required this.geglueckt,
    required this.verworfen,
    required this.ohneDauerverbindung,
    required this.abgebrochen,
    required this.nachStatus,
    required this.nachFehler,
    required this.mittlereDauer,
    required this.laengsteDauer,
    required this.bytes,
  });

  /// HTTP-Abrufe, jeder Wiederholversuch einzeln gezählt.
  final int abrufe;

  /// Neu geöffnete TCP-Verbindungen – gezählt an der Stelle, an der die
  /// Verbindung tatsächlich entsteht (siehe `kachelNetzClient`).
  final int verbindungen;

  /// Verschiedene Kacheladressen.
  final int adressen;

  /// Adressen, die mehr als einmal abgerufen wurden.
  final int wiederholte;

  final int geglueckt;

  /// Wie viele Einträge die Grenze verschluckt hat.
  final int verworfen;

  /// Antworten, nach denen der Server die Verbindung schliessen wollte.
  final int ohneDauerverbindung;

  /// Abrufe, deren Rumpf nie zu Ende gelesen wurde – Wiederholungen und
  /// weggezogene Kacheln (siehe [Kachelabruf.abgebrochen]).
  final int abgebrochen;

  final Map<int, int> nachStatus;
  final Map<String, int> nachFehler;
  final Duration mittlereDauer;
  final Duration laengsteDauer;
  final int bytes;

  /// Was weder angekommen noch absichtlich abgebrochen wurde.
  ///
  /// Die Unterscheidung ist keine Feinheit: In einer gesunden Zoomfahrt
  /// sind Dutzende Abbrüche normal – flutter_map bricht jede Kachel ab,
  /// die aus dem Bild läuft. Stünden die als Fehlschläge da, schickte die
  /// Übersicht jeden auf die Suche nach einem Fehler, den es nicht gibt.
  /// Gemessen an einer Zoomfahrt über echte Server: 312 angekommen,
  /// 56 abgebrochen, **null** fehlgeschlagen.
  int get fehlgeschlagen => abrufe - geglueckt - abgebrochen;

  /// **Die Zahl, wegen der es diesen Mitschnitt gibt.**
  ///
  /// Von aussen gemessen standen 5702 Verbindungen gegen 496 angekommene
  /// Kacheln. Ob daran die Abrufe schuld sind (dann steht
  /// [abrufeJeAdresse] hoch) oder die Verbindungen (dann steht diese Zahl
  /// hoch, und [ohneDauerverbindung] sagt warum), lässt sich von aussen
  /// nicht unterscheiden. Hier steht beides nebeneinander.
  double get verbindungenJeAbruf => abrufe == 0 ? 0 : verbindungen / abrufe;

  /// Abrufe je verschiedener Kachel – 1,0 heisst: jede genau einmal.
  double get abrufeJeAdresse => adressen == 0 ? 0 : abrufe / adressen;
}

/// Rechnet die Übersicht aus den Einträgen. Rein, ohne jeden Nebeneffekt.
Kachelbilanz bilanzAus(
  Iterable<Kachelabruf> eintraege, {
  int verbindungen = 0,
  int verworfen = 0,
}) {
  final nachStatus = <int, int>{};
  final nachFehler = <String, int>{};
  final jeAdresse = <String, int>{};
  var geglueckt = 0;
  var ohneDauerverbindung = 0;
  var abgebrochen = 0;
  var bytes = 0;
  var summeMikro = 0;
  var laengste = Duration.zero;
  var abrufe = 0;

  for (final a in eintraege) {
    abrufe++;
    jeAdresse.update(a.adresse, (n) => n + 1, ifAbsent: () => 1);
    if (a.status != null) {
      nachStatus.update(a.status!, (n) => n + 1, ifAbsent: () => 1);
    }
    if (a.fehler != null) {
      nachFehler.update(a.fehler!, (n) => n + 1, ifAbsent: () => 1);
    }
    if (a.geglueckt) geglueckt++;
    if (!a.dauerverbindung) ohneDauerverbindung++;
    if (a.abgebrochen) abgebrochen++;
    bytes += a.bytes;
    summeMikro += a.dauer.inMicroseconds;
    if (a.dauer > laengste) laengste = a.dauer;
  }

  return Kachelbilanz(
    abrufe: abrufe,
    verbindungen: verbindungen,
    adressen: jeAdresse.length,
    wiederholte: jeAdresse.values.where((n) => n > 1).length,
    geglueckt: geglueckt,
    verworfen: verworfen,
    ohneDauerverbindung: ohneDauerverbindung,
    abgebrochen: abgebrochen,
    // Absteigend, damit das Häufigste oben steht.
    nachStatus: _sortiert(nachStatus),
    nachFehler: _sortiert(nachFehler),
    mittlereDauer: abrufe == 0 ? Duration.zero : Duration(microseconds: summeMikro ~/ abrufe),
    laengsteDauer: laengste,
    bytes: bytes,
  );
}

Map<K, int> _sortiert<K>(Map<K, int> roh) {
  final schluessel = roh.keys.toList()..sort((a, b) => roh[b]!.compareTo(roh[a]!));
  return {for (final k in schluessel) k: roh[k]!};
}

/// Schreibt mit, was beim Kachelabruf wirklich passiert.
///
/// **Warum es das gibt.** Bei dreissig Sekunden Zoomen zählte das
/// Systemprotokoll von macOS 5702 TLS-Handschläge, während im
/// Kachelspeicher 496 Kacheln ankamen – elfeinhalb Verbindungen je
/// Kachel. Auf der Konsole stand dazu **nichts**, und zwar zwangsläufig:
/// flutter_map hängt an den Bildstrom jeder Kachel einen eigenen
/// Fehlerbehandler, damit gilt jeder Fehlschlag als behandelt und
/// erreicht `FlutterError` nie. Der Prüfstand im Widget-Test wiederum
/// macht dieselbe Zoombewegung mit 1,0 Abrufen je Kachel.
///
/// Von aussen war damit Schluss. Was fehlte, war die Sicht von innen:
/// Statuscode, Ausnahme, Dauer und Dauerverbindung je einzelnem Abruf.
///
/// **Aus- statt eingeschaltet.** Der Mitschnitt kostet im Ruhezustand
/// einen Wahrheitswert je Abruf; erst wenn er läuft, entstehen Einträge
/// und wird der Antwortstrom durchgereicht. Niemand soll dauerhaft
/// mitgeschnitten werden, nur weil er einmal eine graue Kachel gesehen
/// hat.
///
/// **Was hier NICHT auftaucht:** Kacheln aus dem Speicher. Der
/// Kachelspeicher von flutter_map sitzt über diesem Client – was er
/// liefert, kommt nie am Netz an. Die Abrufe hier sind also die
/// Fehlschläge des Speichers, und das ist die richtige Menge für diese
/// Frage.
class Kachelmitschnitt {
  Kachelmitschnitt();

  /// Der eine, den die Karten benutzen.
  ///
  /// Ein Einzelstück aus demselben Grund wie der Kachelanbieter selbst:
  /// Der Client wird einmal gebaut und app-weit weitergereicht; ein
  /// Mitschnitt je Bildschirm hätte nichts zum Mitschreiben.
  static final Kachelmitschnitt instanz = Kachelmitschnitt();

  final _eintraege = ListQueue<Kachelabruf>();
  bool _laeuft = false;
  int _verbindungen = 0;
  int _verworfen = 0;

  bool get laeuft => _laeuft;

  /// Die Einträge, älteste zuerst.
  List<Kachelabruf> get eintraege => List.unmodifiable(_eintraege);

  Kachelbilanz get bilanz => bilanzAus(
        _eintraege,
        verbindungen: _verbindungen,
        verworfen: _verworfen,
      );

  /// Fängt von vorn an. Ein laufender Mitschnitt wird dabei verworfen –
  /// zwei Zoomfahrten in einer Zahl wären keine Messung.
  void starte() {
    leere();
    _laeuft = true;
  }

  void halteAn() => _laeuft = false;

  void leere() {
    _eintraege.clear();
    _verbindungen = 0;
    _verworfen = 0;
  }

  /// Meldet eine neu geöffnete Verbindung.
  ///
  /// Wird von der Verbindungsfabrik des `HttpClient` gerufen, also
  /// genau dann, wenn wirklich eine Verbindung entsteht – und nicht,
  /// wenn eine bestehende wiederverwendet wird.
  void verbindungGeoeffnet() {
    if (_laeuft) _verbindungen++;
  }

  void notiere(Kachelabruf abruf) {
    if (!_laeuft) return;
    _eintraege.add(abruf);
    while (_eintraege.length > kachelMitschnittGrenze) {
      _eintraege.removeFirst();
      _verworfen++;
    }
  }
}

/// Legt sich zwischen die Wiederholungen und das Netz und schreibt jeden
/// einzelnen Abruf mit.
///
/// **Die Reihenfolge ist die Aussage.** Der `RetryClient` gehört
/// darüber, nicht darunter: Nur so erscheint jeder Wiederholversuch als
/// eigener Eintrag. Andersherum sähe der Mitschnitt zwei Fehlschläge und
/// einen Erfolg als einen einzigen geglückten Abruf – und genau die
/// Wiederholungen sind einer der Verdächtigen.
class MitschnittClient extends BaseClient {
  MitschnittClient(this._innen, this._mitschnitt);

  final Client _innen;
  final Kachelmitschnitt _mitschnitt;

  @override
  Future<StreamedResponse> send(BaseRequest anfrage) async {
    if (!_mitschnitt.laeuft) return _innen.send(anfrage);

    final uhr = Stopwatch()..start();
    final adresse = anfrage.url.toString();

    final StreamedResponse antwort;
    try {
      antwort = await _innen.send(anfrage);
    } catch (fehler) {
      _mitschnitt.notiere(Kachelabruf(
        zeit: DateTime.now(),
        adresse: adresse,
        dauer: uhr.elapsed,
        fehler: fehlertext(fehler),
        abgebrochen: istAbbruch(fehler),
      ));
      rethrow;
    }

    // **Der Eintrag entsteht hier, nicht am Ende des Rumpfes.** Das ist
    // kein Schönheitsfehler, sondern der Unterschied zwischen einem
    // brauchbaren und einem blinden Mitschnitt: Der `RetryClient` liest
    // den Rumpf einer gescheiterten Antwort gar nicht erst, er bricht ihn
    // ab. Wer erst beim `onDone` notiert, verliert damit ausgerechnet die
    // Abrufe, wegen derer es diesen Mitschnitt gibt. Gemessen: von drei
    // Versuchen kam genau einer an.
    final eintrag = Kachelabruf(
      zeit: DateTime.now(),
      adresse: adresse,
      dauer: uhr.elapsed,
      status: antwort.statusCode,
      dauerverbindung: antwort.persistentConnection,
    );
    _mitschnitt.notiere(eintrag);

    // Der Rumpf wird durchgereicht und nicht gesammelt – ihn hier zu
    // lesen hiesse, jede Kachel zweimal im Speicher zu halten. Von Hand
    // und nicht mit `StreamTransformer.fromHandlers`, weil nur ein
    // eigener Controller das Abbrechen mitbekommt.
    var fertig = false;
    StreamSubscription<List<int>>? abo;
    late final StreamController<List<int>> steuerung;
    steuerung = StreamController<List<int>>(
      onListen: () {
        abo = antwort.stream.listen(
          (stueck) {
            eintrag.bytes += stueck.length;
            steuerung.add(stueck);
          },
          onError: (Object fehler, StackTrace spur) {
            fertig = true;
            eintrag.fehler = fehlertext(fehler);
            eintrag.dauer = uhr.elapsed;
            steuerung.addError(fehler, spur);
          },
          onDone: () {
            fertig = true;
            eintrag.dauer = uhr.elapsed;
            steuerung.close();
          },
        );
      },
      onPause: () => abo?.pause(),
      onResume: () => abo?.resume(),
      onCancel: () {
        // Nach einem regulären `close()` ruft Dart dies ebenfalls – dann
        // war der Rumpf aber vollständig da.
        if (!fertig) {
          eintrag.abgebrochen = true;
          eintrag.dauer = uhr.elapsed;
        }
        return abo?.cancel();
      },
    );

    return StreamedResponse(
      ByteStream(steuerung.stream),
      antwort.statusCode,
      contentLength: antwort.contentLength,
      request: antwort.request,
      headers: antwort.headers,
      isRedirect: antwort.isRedirect,
      persistentConnection: antwort.persistentConnection,
      reasonPhrase: antwort.reasonPhrase,
    );
  }

  @override
  void close() {
    _innen.close();
    super.close();
  }
}

/// Der Fehler in einer Zeile, die sich zählen lässt.
///
/// Die Meldung selbst enthält oft die Adresse (`… uri=https://…/14/8/5.png`),
/// und damit wäre jeder Fehler einzigartig und keine Häufung zu sehen.
/// Hier bleibt der Typ und der Anfang der Meldung bis zum ersten Komma.
@visibleForTesting
String fehlertext(Object fehler) {
  final art = fehler.runtimeType.toString();
  var meldung = fehler.toString();
  final doppelpunkt = meldung.indexOf(': ');
  if (meldung.startsWith(art) && doppelpunkt >= 0) {
    meldung = meldung.substring(doppelpunkt + 2);
  }
  meldung = meldung.split(',').first.trim();
  if (meldung.length > 80) meldung = '${meldung.substring(0, 80)}…';
  return meldung.isEmpty ? art : '$art: $meldung';
}

/// Der Mitschnitt als Text zum Weitergeben.
///
/// Ohne Sprachdatei und bewusst maschinenlesbar: Das hier landet in einer
/// Fehlerbeschreibung, nicht in der Oberfläche.
String berichtAus(Kachelmitschnitt mitschnitt) {
  final b = mitschnitt.bilanz;
  final zeilen = <String>[
    'Kachel-Mitschnitt',
    'Abrufe: ${b.abrufe}',
    'Verbindungen: ${b.verbindungen}',
    'Verbindungen je Abruf: ${b.verbindungenJeAbruf.toStringAsFixed(2)}',
    'Kacheln: ${b.adressen}',
    'Abrufe je Kachel: ${b.abrufeJeAdresse.toStringAsFixed(2)}',
    'Geglueckt: ${b.geglueckt}, fehlgeschlagen: ${b.fehlgeschlagen}, '
        'abgebrochen: ${b.abgebrochen}',
    'Ohne Dauerverbindung: ${b.ohneDauerverbindung}',
    'Dauer: ${b.mittlereDauer.inMilliseconds} ms im Mittel, '
        '${b.laengsteDauer.inMilliseconds} ms laengste',
    'Bytes: ${b.bytes}',
    if (b.verworfen > 0) 'Verworfen: ${b.verworfen}',
    '',
    'Status:',
    for (final e in b.nachStatus.entries) '  ${e.key}: ${e.value}',
    if (b.nachFehler.isNotEmpty) ...[
      '',
      'Fehler:',
      for (final e in b.nachFehler.entries) '  ${e.key}: ${e.value}',
    ],
    '',
    'Abrufe:',
    for (final a in mitschnitt.eintraege)
      '  ${a.zeit.toIso8601String()} ${a.kachel} '
          '${a.status ?? '-'} ${a.dauer.inMilliseconds}ms ${a.bytes}B'
          '${a.dauerverbindung ? '' : ' close'}'
          '${a.abgebrochen ? ' abgebrochen' : ''}'
          '${a.fehler == null ? '' : ' ${a.fehler}'}',
  ];
  return zeilen.join('\n');
}

/// Ob ein Fehler in Wahrheit ein Abbruch war.
///
/// flutter_map bricht den Abruf einer Kachel ab, sobald sie beim Ziehen
/// oder Zoomen aus dem Bild läuft; das kommt als geworfene Ausnahme
/// zurück (`RequestAbortedException`, die Meldung nennt den
/// `abortTrigger`). Am Typnamen allein ist das nicht festzumachen: Der
/// `RetryClient` reicht denselben Sachverhalt als `ClientException`
/// weiter. Dieselbe Unterscheidung trifft [kachelFehlerNochmalVersuchen]
/// in mini_location_map.dart, aus demselben Grund – dort entscheidet sie,
/// ob wiederholt wird.
@visibleForTesting
bool istAbbruch(Object fehler) {
  final text = fehler.toString().toLowerCase();
  return text.contains('abort') || text.contains('cancel');
}

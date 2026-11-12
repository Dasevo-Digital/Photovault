/// Kartenkacheln über den eigenen Server (#180).
///
/// **Warum.** Bis 3.66 holte jedes Gerät seine Kacheln selbst bei
/// OpenStreetMap und OpenTopoMap – mit seiner IP-Adresse und den
/// Koordinaten, die es gerade ansieht, also mittelbar den Orten der Fotos.
/// Im verbundenen Betrieb holt sie jetzt der Server mit seiner eigenen
/// Kennung, hält sie vor und reicht sie an die angemeldeten Geräte weiter.
/// Die Anbieter sehen nur noch ihn.
///
/// Hier steht, was Server, Rechner und Handy gemeinsam wissen müssen:
/// welche Quellen über den Server gehen und wie ein Gerät seine Abrufe
/// dorthin umlenkt.
library;

import 'package:http/http.dart' as http;

import 'verbindung.dart';

/// Die Kachelquellen, die der Server holt – **und nur diese**.
///
/// Eine feste Liste und keine frei angegebene Adresse: Sonst wäre der
/// Server ein offener Vermittler, über den jeder Angemeldete beliebige
/// Adressen abrufen liesse. Es sind die beiden schlüssellosen Karten, die
/// die Apps und die Weboberfläche zeigen. CARTO trägt den eigenen
/// Schlüssel in der Adresse und die eigene Kartenquelle ist frei
/// eingetragen – beide gehen weiter direkt.
///
/// [hoechsteStufe] ist die letzte Stufe mit echten Kacheln (siehe
/// `Kartenstil.hoechsteEchteStufe`): OSM antwortet darüber mit 400,
/// OpenTopoMap mit einfarbigen Bildern.
const serverKartenquellen = <String, ({String host, int hoechsteStufe})>{
  'osm': (host: 'tile.openstreetmap.org', hoechsteStufe: 19),
  'topo': (host: 'tile.opentopomap.org', hoechsteStufe: 17),
};

/// Ob der Server laut `/api/v1/zustand` Kartenkacheln liefert. Ein Server
/// bis 3.66 kennt `funktionen.karte` nicht; dann holt das Gerät sie wie
/// bisher selbst.
bool serverLiefertKacheln(Map<String, Object?> zustand) =>
    ((zustand['funktionen'] as Map?)?['karte'] as int? ?? 0) >= 1;

/// Der Pfad, unter dem der Server die Kachel [kachel] liefert – `null`,
/// wenn sie zu keiner der [serverKartenquellen] gehört.
String? serverKachelpfad(Uri kachel) {
  if (kachel.scheme != 'https' || kachel.hasQuery) return null;
  final stil = [
    for (final MapEntry(:key, :value) in serverKartenquellen.entries)
      if (value.host == kachel.host) key,
  ].firstOrNull;
  if (stil == null) return null;
  final m = RegExp(
    r'^/(\d{1,2})/(\d{1,7})/(\d{1,7})\.png$',
  ).firstMatch(kachel.path);
  if (m == null) return null;
  return 'api/v1/karte/$stil/${m[1]}/${m[2]}/${m[3]}.png';
}

/// Lenkt die Abrufe der [serverKartenquellen] zum eigenen Server um, wenn
/// [server] einen nennt; alles andere geht unverändert weiter.
///
/// **Umgelenkt wird erst hier, die Adresse der Kachel bleibt die des
/// Anbieters.** Karte und Kachelspeicher auf der Platte sehen weiter
/// `https://tile.openstreetmap.org/…`. Damit gilt eine einmal geholte
/// Kachel unabhängig davon, auf welchem Weg sie kam: Eine vorgeladene
/// Gegend bleibt brauchbar, ohne Netz greift dieselbe Kopie, und meldet
/// ein Server die Fähigkeit erst nach dem Start (oder gar nicht, weil er
/// älter ist), ändert sich am Speicher nichts.
///
/// Das Token geht nur an den eigenen Server und nur mit einer umgelenkten
/// Kachel.
class Kachelumleitung extends http.BaseClient {
  Kachelumleitung(this._innen, {required this.server});

  final http.Client _innen;

  /// Der eigene Server, solange er Kacheln liefert (siehe
  /// [serverLiefertKacheln]); sonst `null`.
  final Serververbindung? Function() server;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest anfrage) async {
    final s = server();
    final pfad = s == null || anfrage.method != 'GET'
        ? null
        : serverKachelpfad(anfrage.url);
    if (s == null || pfad == null) return _innen.send(anfrage);
    final umgelenkt =
        http.AbortableRequest(
            'GET',
            s.adresse(pfad),
            // Der Abbruch der Karte (Kachel aus dem Bild gelaufen) muss
            // weiter durchschlagen.
            abortTrigger: anfrage is http.Abortable
                ? anfrage.abortTrigger
                : null,
          )
          ..headers.addAll(anfrage.headers)
          ..headers['authorization'] = 'Bearer ${s.token}'
          ..followRedirects = anfrage.followRedirects
          ..maxRedirects = anfrage.maxRedirects
          ..persistentConnection = anfrage.persistentConnection;
    final antwort = await _innen.send(umgelenkt);
    // **Kommt der Server nicht an die Kachel, zählt das wie kein Netz.**
    // 502 heisst: Der Anbieter antwortet ihm nicht, und eine ältere Kopie
    // hat er nicht; 503 und 504 kommen vom Reverse Proxy, wenn der Server
    // selbst fehlt. Als Fehlerstatus liesse flutter_map die eigene Kopie
    // auf der Platte links liegen (der Rückfall am Rechner greift nur bei
    // einem Fehler der Verbindung, siehe `Offlinerueckfall`); als
    // Verbindungsfehler zeigt es sie.
    if (const {502, 503, 504}.contains(antwort.statusCode)) {
      await antwort.stream.drain<void>();
      throw http.ClientException(
        'Tile server unavailable (${antwort.statusCode})',
        umgelenkt.url,
      );
    }
    return antwort;
  }

  @override
  void close() => _innen.close();
}

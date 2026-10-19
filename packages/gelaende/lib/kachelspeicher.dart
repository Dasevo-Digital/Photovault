/// Der Kachelspeicher, den Karten und Landschaft gemeinsam benutzen, und
/// wann ein Kachelabruf einen zweiten Versuch verdient.
///
/// Hier und nicht bei einer der Karten, weil Rechner- und Handy-App die
/// Landschaft gleich zeichnen (`gelaende_laden.dart`) und dafür beide
/// denselben Speicher brauchen.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' show ClientException;

/// Wie lange eine einmal geholte Kachel als frisch gilt.
///
/// **Ohne diese Angabe richtet sich flutter_map nach `max-age` der
/// Antwort – und genau dort liegt das Problem.** OpenTopoMap rendert
/// Kacheln bei Bedarf und gibt ausgerechnet den frisch gerenderten die
/// kürzeste Haltbarkeit. Gemessen an echten Abrufen:
///
/// ```
/// x-cache-status: MISS   max-age=15875   (4,4 h)   Abruf 1,72 s
/// x-cache-status: MISS   max-age=13615   (3,8 h)   Abruf 1,63 s
/// x-cache-status: MISS   max-age=12590   (3,5 h)   Abruf 1,48 s
/// vorgerendert           max-age=604800  (7 Tage)  Abruf 0,09 s
/// ```
///
/// Die teuersten Kacheln laufen also nach wenigen Stunden ab, und
/// flutter_map macht dann **vor** der Anzeige einen blockierenden
/// Rückfrage-Umlauf. Am selben Ort einen Tag später wartet man erneut.
///
/// Dreissig Tage sind hier vertretbar: Höhenlinien und Geländeschatten
/// ändern sich über Jahre, nicht über Stunden, und die Karte ist
/// Hintergrund für Fotopins, kein Navigationsgerät. Es schont zugleich
/// die freiwillig betriebenen Kachelserver.
const kartenKachelFrische = Duration(days: 30);

/// Obergrenze des Kachelspeichers auf der Platte.
///
/// **Von 300 MB auf 4 GB angehoben**, seit sich Gebiete vorladen lassen
/// (siehe `services/kachelvorrat.dart`). An der echten Bibliothek
/// gerechnet: 1.092 verortete Aufnahmen ergeben neun Gebiete, und die
/// bis Stufe 14 vorzuhalten sind 29.039 Kacheln – rund 850 MB. Für
/// einen zweiten Kartenstil noch einmal so viel. Mit der alten Grenze
/// hätte der Aufräumer weggeworfen, was gerade erst geholt wurde.
///
/// Vier Gigabyte sind viel für einen Zwischenspeicher und wenig neben
/// einer Fotobibliothek. Wer nichts vorlädt, merkt davon nichts: Der
/// Speicher wächst nur mit dem, was tatsächlich angesehen wird.
const kartenSpeicherGrenze = 4 * 1024 * 1024 * 1024;

/// Der eine Kachelspeicher dieser App, zum Mitbenutzen.
///
/// Nicht nur die Karten holen Kacheln: Die Geländeansicht holt dieselben
/// OpenTopoMap-Bilder und dazu die Höhenkacheln
/// (`services/gelaende_laden.dart`). Ginge sie am Speicher vorbei, lüde
/// sie beim zweiten Öffnen derselben Wanderung alles noch einmal – und
/// ohne Netz gar nichts, während die Karte daneben ihre Kacheln von der
/// Platte nimmt.
///
/// Die Angaben stehen bei jedem Aufruf dabei und nicht nur beim ersten.
/// Sie wirken zwar ohnehin nur beim ersten – aber so kann kein zweiter
/// Aufrufer versehentlich ANDERE mitgeben und sich wundern, dass sie
/// nichts tun. Genau das prüft `karten_kachelspeicher_test.dart`.
MapCachingProvider kartenKachelspeicher() =>
    BuiltInMapCachingProvider.getOrCreateInstance(
      overrideFreshAge: kartenKachelFrische,
      maxCacheSize: kartenSpeicherGrenze,
    );

/// Bei welchen Statuscodes ein zweiter Versuch sinnvoll ist.
///
/// **404 steht hier mit Absicht, und das ist der Kern der Sache.**
/// OpenTopoMap rendert Kacheln bei Bedarf; ist eine noch nicht fertig,
/// antwortet der Server nicht mit „warte", sondern mit 404. An einer
/// echten Kartenfahrt im Alpenraum gemessen:
///
/// ```
/// 170 Kachelabrufe -> 126 x 200, 44 x 404   (alle auf Stufe 17)
/// dieselben 404-Kacheln Sekunden später -> 200, in 70-90 ms
/// ```
///
/// Dieselbe Fahrt kurz darauf: 142 Abrufe, kein einziger Fehler. Es ist
/// also nichts, was man beim Programmieren sieht – und für den
/// Betrachter bleibt eine graue Lücke im Kartenbild, dauerhaft.
///
/// Denn ohne diese Liste hilft niemand nach: Der Vorgabe-[RetryClient]
/// von flutter_map wiederholt **allein bei 503**, und
/// [EvictErrorTileStrategy.none] behält die gescheiterte Kachel für
/// immer. Ein einziger Fehlschlag wird so zu einem Loch, das bis zum
/// nächsten Programmstart bleibt.
///
/// Bei OSM und CARTO ist ein 404 dagegen echt. Der Preis dafür sind
/// zwei überflüssige Abrufe für eine Kachel, die es ohnehin nicht gibt –
/// gegenüber einer Lücke im Bild ist das der bessere Handel.
bool kachelNochmalVersuchen(int status) =>
    status == 404 || // noch nicht gerendert, siehe oben
    status == 408 || // Zeitüberschreitung beim Server
    status == 429 || // zu viele Abrufe, gleich wieder gut
    (status >= 500 && status < 600);

/// Ob ein geworfener Fehler einen zweiten Versuch verdient.
///
/// Abgebrochene Abrufe gehören ausdrücklich **nicht** dazu: flutter_map
/// bricht selbst ab, wenn eine Kachel beim schnellen Ziehen gar nicht
/// mehr gebraucht wird. Die zu wiederholen hiesse, dem Server Arbeit für
/// Bilder aufzuladen, die niemand mehr sieht.
bool kachelFehlerNochmalVersuchen(Object fehler) {
  if (fehler is ClientException) {
    final m = fehler.message.toLowerCase();
    if (m.contains('cancel') || m.contains('abort')) return false;
    return true;
  }
  return fehler is SocketException ||
      fehler is HttpException ||
      fehler is TimeoutException;
}

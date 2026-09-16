/// **Was beim Wandern zählt – aus OpenStreetMap.**
///
/// Die Karte unter der Landschaft zeigt Wege und Höhenlinien. Was sie
/// nicht zeigt, ist der Name des Gipfels, auf den man gestiegen ist, die
/// Hütte, in der man eingekehrt ist, oder die Quelle, an der man Wasser
/// geholt hat – jedenfalls nicht so, dass man es beim Überflug lesen
/// könnte. Auf einer Kachel steht die Beschriftung flach im Gelände und
/// kippt mit ihm weg.
///
/// Deshalb kommen diese Dinge getrennt und werden als **Schilder**
/// gezeichnet, die aufrecht stehen bleiben.
///
/// **Gefiltert auf das, was beim Wandern zählt.** Overpass gibt zu einem
/// Ausschnitt alles her, was in OpenStreetMap steht; das Ilsetal
/// (2,8 × 3,3 km) liefert bei der Abfrage hier 41 Punkte, davon 27
/// Wegweiser. Ein Briefkasten oder eine Bushaltestelle stünden auch drin
/// und hätten in einer Landschaft nichts verloren.
///
/// ```
/// Art                Ilsetal   davon benannt
/// Wegweiser              27          9
/// Gipfel                  7          7
/// Aussichtspunkt          5          1
/// Wasserfall              1          1
/// Quelle                  1          0
/// ```
///
/// **Overpass ist ein öffentlicher Dienst mit Grenzen.** Er wird
/// ehrenamtlich betrieben und drosselt bei zu vielen Anfragen. Deshalb
/// wird jede Abfrage in der Bibliothek behalten (siehe
/// `AppDatabase.wanderobjekteFuer`), und eine Tour, die schon einmal
/// angesehen wurde, fragt niemanden mehr.
///
/// Das Zerlegen der Antwort steht getrennt vom Abruf: So lässt es sich
/// an einer echten gespeicherten Antwort prüfen, ohne einen Server zu
/// fragen.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Wofür ein Punkt steht.
enum Wanderart {
  gipfel,
  sattel,
  aussicht,
  huette,
  schutzhuette,
  quelle,
  wasserfall,
  wegweiser,
  ruine,
}

/// Ein Punkt in der Landschaft, der einen Namen verdient.
class Wanderobjekt {
  const Wanderobjekt({
    required this.osmId,
    required this.art,
    required this.breite,
    required this.laenge,
    this.name,
    this.hoehe,
  });

  /// Die Kennung aus OpenStreetMap – damit derselbe Punkt aus zwei
  /// überlappenden Abfragen nicht zweimal im Bild steht.
  final int osmId;
  final Wanderart art;
  final double breite;
  final double laenge;

  /// Der Name, wenn es einen gibt. **Die meisten Wegweiser haben
  /// keinen** – 18 von 41 Punkten im Ilsetal trugen einen.
  final String? name;

  /// Die Höhe in Metern, wie sie in OpenStreetMap steht.
  ///
  /// **Nicht die aus dem Höhengitter.** Wenn jemand die Höhe eines
  /// Gipfels eingetragen hat, ist sie vermessen; das Gitter kommt aus
  /// Kacheln und liegt bei einer Spitze regelmässig zu tief, weil ein
  /// Bildpunkt dort dreissig Meter breit ist.
  final double? hoehe;

  @override
  bool operator ==(Object other) =>
      other is Wanderobjekt && other.osmId == osmId;

  @override
  int get hashCode => osmId.hashCode;

  @override
  String toString() => 'Wanderobjekt($osmId, ${art.name}, $name)';
}

/// Welche Merkmale geholt werden – Schlüssel, Wert, Art.
///
/// **Warum genau diese neun.** Sie beantworten je eine Frage, die beim
/// Ansehen einer Wanderung aufkommt: „Wie hiess der Berg", „wo waren wir
/// eingekehrt", „wo war die Aussicht", „wo kam das Wasser her". Alles
/// andere – Bänke, Abfalleimer, Parkplätze – beantwortet keine.
const wanderMerkmale = <({String schluessel, String wert, Wanderart art})>[
  (schluessel: 'natural', wert: 'peak', art: Wanderart.gipfel),
  (schluessel: 'natural', wert: 'saddle', art: Wanderart.sattel),
  (schluessel: 'tourism', wert: 'viewpoint', art: Wanderart.aussicht),
  (schluessel: 'tourism', wert: 'alpine_hut', art: Wanderart.huette),
  (schluessel: 'tourism', wert: 'wilderness_hut', art: Wanderart.huette),
  (schluessel: 'amenity', wert: 'shelter', art: Wanderart.schutzhuette),
  (schluessel: 'natural', wert: 'spring', art: Wanderart.quelle),
  (schluessel: 'waterway', wert: 'waterfall', art: Wanderart.wasserfall),
  (schluessel: 'information', wert: 'guidepost', art: Wanderart.wegweiser),
  (schluessel: 'historic', wert: 'ruins', art: Wanderart.ruine),
];

/// Die Adresse des Overpass-Dienstes.
const String overpassAdresse = 'https://overpass-api.de/api/interpreter';

/// Wie lange auf eine Antwort gewartet wird.
///
/// Fünfzehn Sekunden. Overpass rechnet die Abfrage bei Bedarf und
/// antwortet bei Andrang gar nicht; eine Landschaft, die darauf wartet,
/// erscheint nie. Die Schilder sind eine Zugabe – ohne sie ist der
/// Überflug vollständig.
const Duration overpassZeitgrenze = Duration(seconds: 15);

/// Baut die Abfrage für einen Ausschnitt.
///
/// Als eigene Funktion, damit sie sich lesen und prüfen lässt, ohne
/// einen Server zu fragen: Ein vertauschtes Paar aus Breite und Länge
/// liefert eine gültige Antwort über der falschen Weltgegend.
String overpassAbfrage({
  required double sued,
  required double west,
  required double nord,
  required double ost,
}) {
  String kasten() => '($sued,$west,$nord,$ost)';
  final zeilen = [
    for (final m in wanderMerkmale)
      '  node["${m.schluessel}"="${m.wert}"]${kasten()};',
  ];
  return '[out:json][timeout:25];\n(\n${zeilen.join('\n')}\n);\nout body;';
}

/// Zerlegt die Antwort von Overpass.
///
/// Fehlerhafte Einträge werden **übersprungen**, nicht als Fehler
/// behandelt: Ein Punkt ohne Koordinate nimmt die vierzig anderen nicht
/// mit.
List<Wanderobjekt> ausOverpass(String rumpf) {
  final aus = <Wanderobjekt>[];
  final gesehen = <int>{};
  Object? roh;
  try {
    roh = jsonDecode(rumpf);
  } catch (_) {
    return aus;
  }
  if (roh is! Map) return aus;
  final elemente = roh['elements'];
  if (elemente is! List) return aus;

  for (final e in elemente) {
    if (e is! Map) continue;
    final id = e['id'];
    final breite = e['lat'];
    final laenge = e['lon'];
    if (id is! int || breite is! num || laenge is! num) continue;
    if (!gesehen.add(id)) continue;
    final marken = e['tags'];
    if (marken is! Map) continue;

    // **Die erste passende Art gewinnt.** Die Ilsefälle tragen zugleich
    // `tourism=attraction` und `waterway=waterfall`; die Reihenfolge in
    // [wanderMerkmale] entscheidet, und dort steht der Wasserfall vor
    // dem Wegweiser.
    Wanderart? art;
    for (final m in wanderMerkmale) {
      if (marken[m.schluessel] == m.wert) {
        art = m.art;
        break;
      }
    }
    if (art == null) continue;

    final name = marken['name'];
    aus.add(Wanderobjekt(
      osmId: id,
      art: art,
      breite: breite.toDouble(),
      laenge: laenge.toDouble(),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      hoehe: _hoehe(marken['ele']),
    ));
  }
  return aus;
}

/// Die Höhe aus `ele` – in OpenStreetMap steht dort mal eine Zahl, mal
/// „565.9", mal „565 m".
double? _hoehe(Object? roh) {
  if (roh is num) return roh.toDouble();
  if (roh is! String) return null;
  final treffer = RegExp(r'-?\d+([.,]\d+)?').firstMatch(roh);
  if (treffer == null) return null;
  return double.tryParse(treffer.group(0)!.replaceAll(',', '.'));
}

/// Holt die Punkte eines Ausschnitts von Overpass.
///
/// Kommt nichts an, ist das Ergebnis `null` – **nicht** eine leere
/// Liste. Der Unterschied zählt für den Zwischenspeicher: „hier gibt es
/// nichts" darf behalten werden, „der Server hat nicht geantwortet"
/// nicht.
Future<List<Wanderobjekt>?> holeWanderobjekte({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  required http.Client netz,
  String adresse = overpassAdresse,
}) async {
  try {
    final antwort = await netz
        .post(
          Uri.parse(adresse),
          headers: const {
            'User-Agent': 'com.example.photoVault',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'data':
                overpassAbfrage(sued: sued, west: west, nord: nord, ost: ost)
          },
        )
        .timeout(overpassZeitgrenze);
    if (antwort.statusCode != 200) return null;
    return ausOverpass(utf8.decode(antwort.bodyBytes, allowMalformed: true));
  } catch (_) {
    // Zeitüberschreitung, Drosselung, kein Netz – die Schilder sind eine
    // Zugabe, und ohne sie ist der Überflug vollständig.
    return null;
  }
}

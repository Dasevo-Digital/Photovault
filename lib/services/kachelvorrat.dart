import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart';

import '../widgets/mini_location_map.dart';

/// Ein rechteckiger Kartenausschnitt in Grad.
typedef Gebiet = ({double sued, double west, double nord, double ost});

/// Eine einzelne Kachel.
typedef Kachel = ({int z, int x, int y});

/// Wie weit ein Gebiet über die äussersten Fotos hinausreicht.
///
/// Ein Ausschnitt, der genau am letzten Foto endet, ist unbrauchbar:
/// Beim Betrachten schiebt man die Karte, und dann steht man sofort im
/// Ungeladenen. Ein Zehntel Grad sind rund elf Kilometer.
const gebietsrand = 0.1;

/// Bis zu diesem Abstand gehören zwei Fotos ins selbe Gebiet.
///
/// Ein Grad Breite sind rund 111 km. Wer im selben Urlaub zweihundert
/// Kilometer weiterfährt, bekommt trotzdem ein Gebiet – erst darüber
/// wird daraus ein zweites.
const gebietsabstandGrad = 2.0;

/// Die **Anzeigestufen**, die vorgeladen werden.
///
/// Nach oben offen wäre sinnlos: Stufe 14 zeigt einzelne Strassen, und
/// von dort an vervierfacht jede weitere Stufe die Zahl der Kacheln. Für
/// „wo war ich" reicht das aus; wer weiter hineingeht, lädt die letzten
/// Kacheln unterwegs nach.
///
/// **Anzeigestufen und nicht Serveradressen**, und dieser Unterschied
/// hat gefehlt: Bei nachgebildeter doppelter Auflösung fragt die Karte
/// für die Anzeigestufe z die Serverstufe z+1 an. Der Vorrat lud
/// unverändert 3 bis 14 und bediente damit nur noch die Anzeigestufen 2
/// bis 13 – wer auf 14 hineinzoomte, wartete trotz vollem Vorrat aufs
/// Netz. Siehe [vorratStufen].
const vorratKleinsteStufe = 3;
const vorratGroessteStufe = 14;

/// Welche **Serverstufen** für die gewünschten Anzeigestufen zu laden
/// sind.
///
/// Die eine Stelle, an der aus Anzeige- Serveradressen werden – dieselbe
/// Rechnung, die [buildMapTileLayer] anstellt, über [stufenversatz]
/// geteilt statt zweimal geschrieben.
({int von, int bis}) vorratStufen(
  Kartenstil stil,
  double punktdichte, {
  int von = vorratKleinsteStufe,
  int bis = vorratGroessteStufe,
}) {
  final versatz = stufenversatz(stil, punktdichte);
  // Nach oben ist bei der letzten Stufe Schluss, für die es echte
  // Kacheln gibt; darüber liefert der Server nichts Neues mehr.
  final hoechste = stil.hoechsteEchteStufe ?? 19;
  return (
    von: math.min(von + versatz, hoechste),
    bis: math.min(bis + versatz, hoechste),
  );
}

/// Fasst verortete Aufnahmen zu Gebieten zusammen.
///
/// **Reine Funktion, deshalb prüfbar.** Der Reihe nach: Jede Aufnahme
/// kommt in das erste Gebiet, dessen Rand sie um weniger als
/// [gebietsabstandGrad] verfehlt; sonst beginnt sie ein neues. Das ist
/// kein Cluster-Verfahren mit Anspruch, sondern genau die Frage, um die
/// es geht: Welche Rechtecke muss ich laden, damit meine Fotos darin
/// liegen?
List<Gebiet> gebieteAus(
  Iterable<({double breite, double laenge})> orte, {
  double abstand = gebietsabstandGrad,
  double rand = gebietsrand,
}) {
  final gebiete = <({double sued, double west, double nord, double ost})>[];
  for (final ort in orte) {
    var gefunden = false;
    for (var i = 0; i < gebiete.length; i++) {
      final g = gebiete[i];
      final nahDran = ort.breite >= g.sued - abstand &&
          ort.breite <= g.nord + abstand &&
          ort.laenge >= g.west - abstand &&
          ort.laenge <= g.ost + abstand;
      if (!nahDran) continue;
      gebiete[i] = (
        sued: math.min(g.sued, ort.breite),
        west: math.min(g.west, ort.laenge),
        nord: math.max(g.nord, ort.breite),
        ost: math.max(g.ost, ort.laenge),
      );
      gefunden = true;
      break;
    }
    if (!gefunden) {
      gebiete.add((
        sued: ort.breite,
        west: ort.laenge,
        nord: ort.breite,
        ost: ort.laenge
      ));
    }
  }
  return [
    for (final g in gebiete)
      (
        sued: (g.sued - rand).clamp(-85.0, 85.0),
        west: (g.west - rand).clamp(-180.0, 180.0),
        nord: (g.nord + rand).clamp(-85.0, 85.0),
        ost: (g.ost + rand).clamp(-180.0, 180.0),
      )
  ];
}

int _kachelX(double laenge, int z) =>
    ((laenge + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);

int _kachelY(double breite, int z) {
  final rad = breite * math.pi / 180;
  final y = (1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2;
  return (y * (1 << z)).floor().clamp(0, (1 << z) - 1);
}

/// Alle Kacheln, die für [gebiete] in den Stufen [von] bis [bis] gebraucht
/// werden – ohne Doppelte.
///
/// Sich überlappende Gebiete teilen sich auf den unteren Stufen fast alle
/// Kacheln; ohne die Entdopplung lüde man dieselbe Kachel zwanzig Mal.
List<Kachel> kachelListe(
  List<Gebiet> gebiete, {
  int von = vorratKleinsteStufe,
  int bis = vorratGroessteStufe,
}) {
  final gesehen = <String>{};
  final kacheln = <Kachel>[];
  for (var z = von; z <= bis; z++) {
    for (final g in gebiete) {
      final x0 = _kachelX(g.west, z), x1 = _kachelX(g.ost, z);
      // Norden ist die KLEINERE Kachelnummer – die y-Achse zeigt nach
      // unten. Wer das verwechselt, lädt ein leeres Rechteck.
      final y0 = _kachelY(g.nord, z), y1 = _kachelY(g.sued, z);
      for (var x = math.min(x0, x1); x <= math.max(x0, x1); x++) {
        for (var y = math.min(y0, y1); y <= math.max(y0, y1); y++) {
          final schluessel = '$z/$x/$y';
          if (gesehen.add(schluessel)) kacheln.add((z: z, x: x, y: y));
        }
      }
    }
  }
  return kacheln;
}

/// Die Adresse einer Kachel im gewählten Stil.
String kachelAdresse(Kartenstil stil, Kachel k) {
  var url = stil.kachelUrl
      .replaceAll('{z}', '${k.z}')
      .replaceAll('{x}', '${k.x}')
      .replaceAll('{y}', '${k.y}')
      .replaceAll('{r}', '');
  final bereiche = stil.unterbereiche;
  if (bereiche.isNotEmpty) {
    // Dieselbe Verteilung wie flutter_map sie wählt – sonst landete die
    // vorgeladene Kachel unter einem anderen Schlüssel als die, die die
    // Karte später anfordert.
    url = url.replaceAll('{s}', bereiche[(k.x + k.y) % bereiche.length]);
  }
  return url;
}

/// Wie lange die geholte Kachel als frisch gilt.
///
/// **Mit Auffanglösung, und das ist kein Zierrat.** Die Rechnung von
/// flutter_map wirft, wenn ein Server `max-age` schickt, aber weder
/// `age` noch `date` – dort steht ein Ausrufezeichen auf dem
/// `date`-Feld. Ohne diesen Auffang zählte eine angekommene Kachel als
/// unerreichbar, nur weil ihre Kopfzeilen unvollständig waren.
CachedMapTileMetadata _haltbarkeit(Map<String, String> kopfzeilen) {
  try {
    return CachedMapTileMetadata.fromHttpHeaders(kopfzeilen);
  } catch (_) {
    // Dieselben sieben Tage, die flutter_map selbst als Rückfallwert
    // benutzt, wenn ein Server gar nichts sagt.
    return CachedMapTileMetadata(
      staleAt: DateTime.timestamp().add(const Duration(days: 7)),
      lastModified: null,
      etag: null,
    );
  }
}

/// Wie weit das Vorladen ist.
typedef Vorratsstand = ({int fertig, int gesamt, int geladen, int fehler});

/// Lädt die Kacheln der [gebiete] in den Kachelspeicher.
///
/// **Warum überhaupt.** Die Karte holt jede Kachel in dem Augenblick, in
/// dem sie gebraucht wird. Wenn der Server dann klemmt, bleibt ein
/// graues Loch stehen – und die Kachelserver sind gespendet, also wird
/// jeder erneute Abruf zum Ärgernis für beide Seiten. Wer seine Gebiete
/// einmal vorlädt, ist davon frei: Die Karte nimmt sie danach von der
/// Platte.
///
/// Bereits vorhandene und noch frische Kacheln werden **übersprungen** –
/// der zweite Lauf kostet fast nichts.
Stream<Vorratsstand> ladeVorrat(
  List<Gebiet> gebiete,
  Kartenstil stil, {
  MapCachingProvider? speicher,
  Client? netz,
  int von = vorratKleinsteStufe,
  int bis = vorratGroessteStufe,
}) async* {
  final kacheln = kachelListe(gebiete, von: von, bis: bis);
  final lager = speicher ?? kartenKachelspeicher();
  final client = netz ?? kachelNetzClient();
  var fertig = 0, geladen = 0, fehler = 0;

  yield (fertig: 0, gesamt: kacheln.length, geladen: 0, fehler: 0);

  for (final k in kacheln) {
    final url = kachelAdresse(stil, k);
    try {
      if (lager.isSupported) {
        final vorhanden = await lager.getTile(url);
        if (vorhanden != null && !vorhanden.metadata.isStale) {
          fertig++;
          yield (
            fertig: fertig,
            gesamt: kacheln.length,
            geladen: geladen,
            fehler: fehler
          );
          continue;
        }
      }
      final antwort = await client.get(Uri.parse(url),
          headers: const {'User-Agent': 'flutter_map (com.example.photoVault)'});
      if (antwort.statusCode == 200 && antwort.bodyBytes.isNotEmpty) {
        if (lager.isSupported) {
          await lager.putTile(
            url: url,
            metadata: _haltbarkeit(antwort.headers),
            bytes: antwort.bodyBytes,
          );
        }
        geladen++;
      } else {
        fehler++;
      }
    } catch (_) {
      // Ein Fehlschlag beim Vorladen ist kein Grund abzubrechen: Die
      // übrigen Kacheln sind trotzdem etwas wert, und die Karte holt
      // eine fehlende später von selbst.
      fehler++;
    }
    fertig++;
    yield (
      fertig: fertig,
      gesamt: kacheln.length,
      geladen: geladen,
      fehler: fehler
    );
  }
}

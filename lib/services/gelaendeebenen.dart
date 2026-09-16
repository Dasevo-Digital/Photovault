/// **Was auf der Landschaft liegt – Schicht für Schicht.**
///
/// Bis hierher trug die Geländeansicht genau eine Kachelquelle: dieselbe
/// Wanderkarte, die auch die Routenkarte zeigt. Für eine Wanderung ist
/// das die halbe Antwort. Die andere Hälfte steht im Luftbild – wie es
/// dort **aussieht**, welcher Hang bewaldet ist, wo die Lichtung war.
///
/// **Und warum das Luftbild allein nicht reicht.** An der echten Kachel
/// nachgesehen (Ilsetal, 51,8433 N / 10,6553 O, Stufe 17): Das Luftbild
/// zeigt dichten Wald – der Weg, auf dem die Wanderung verlief, ist
/// darauf **nicht zu sehen**. Erst die Wegeebene macht ihn sichtbar. Die
/// Ebenen sind also kein Zierrat, sondern der Grund, warum ein Luftbild
/// überhaupt als Wanderkarte taugt.
///
/// ```
/// Ebene                    Stufe 17   Grösse   Inhalt
/// Esri Weltbild            200        10,0 kB  Wald, kein Weg
/// Waymarked Wandern        200         3,9 kB  der Weg, farbig
/// Esri Verkehr             200         0,9 kB  leer (Wald)
/// Esri Grenzen und Orte    200         0,9 kB  leer (Wald)
/// ```
///
/// **Jede Ebene hat ihre eigene Obergrenze**, und die richtet sich nicht
/// nur danach, was der Anbieter liefert, sondern auch danach, was man ihm
/// zumuten darf. Waymarked Trails ist ein ehrenamtlicher Dienst;
/// OpenTopoMap rendert bei Bedarf und braucht dafür Sekunden (gemessen:
/// 31 von 88 Blöcken in zwei Minuten). Esri liefert aus einem
/// Auslieferungsnetz und antwortet in Millisekunden. Deshalb steht die
/// zumutbare Stufe getrennt von der lieferbaren.
library;

import '../widgets/mini_location_map.dart' show Kartenstil;

/// Eine Kachelebene, aus der eine Blocktextur zusammengesetzt wird.
class Kartenebene {
  const Kartenebene({
    required this.name,
    required this.urlVorlage,
    required this.hoechsteStufe,
    required this.nennung,
    this.seite,
  });

  /// Zum Wiedererkennen in Messungen und Fehlermeldungen – kein
  /// Oberflächentext.
  final String name;

  /// Die Kacheladresse mit `{z}`, `{x}` und `{y}`.
  ///
  /// Bei Esri stehen `{y}` und `{x}` **vertauscht** in der Adresse; das
  /// steht so in der Vorlage und braucht keine Sonderbehandlung, weil
  /// eingesetzt und nicht gerechnet wird.
  final String urlVorlage;

  /// Bis hierher wird geladen – und darüber die letzte Kachel gedehnt.
  final int hoechsteStufe;

  final String nennung;
  final String? seite;
}

/// Das Luftbild von Esri.
///
/// Bis Stufe 19 geprüft, alle mit Inhalt und jede verschieden – keine
/// Ersatzkachel-Falle wie bei OpenTopoMap, wo oberhalb der echten Stufe
/// eine einfarbige Kachel mit Status 200 kommt.
///
/// **Achtzehn und nicht neunzehn.** Auf 18 belegt ein Block 4 MB, auf 19
/// wären es 16 MB und der Vorrat fasste noch fünf Blöcke. Der Unterschied
/// am Bildschirm ist zu diesem Preis keiner: 0,37 gegen 0,18 Meter je
/// Bildpunkt, und die Höhen darunter kommen ohnehin nur bis Stufe 15.
const luftbildEbene = Kartenebene(
  name: 'esri-weltbild',
  urlVorlage: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'World_Imagery/MapServer/tile/{z}/{y}/{x}',
  hoechsteStufe: 18,
  nennung: 'Esri, Maxar, Earthstar Geographics',
  seite: 'https://www.arcgis.com/home/item.html'
      '?id=10df2279f9684e4a9f6a7f08febac2a9',
);

/// Die Wanderwege von Waymarked Trails – gefärbt nach Wegemarkierung.
///
/// **Sechzehn, obwohl der Dienst bis 18 liefert.** Waymarked Trails wird
/// ehrenamtlich betrieben; ein Überflug berührt bei Stufe 18 sechzehnmal
/// so viele Kacheln wie bei 16. Eine Linienzeichnung verträgt das
/// Hochskalieren – ein Luftbild nicht, deshalb steht die Grenze hier
/// niedriger als beim Grund.
const wanderwegeEbene = Kartenebene(
  name: 'waymarked-wandern',
  urlVorlage: 'https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png',
  hoechsteStufe: 16,
  nennung: '© waymarkedtrails.org (CC-BY-SA)',
  seite: 'https://hiking.waymarkedtrails.org/#?map=copyright',
);

/// Strassen und Wege als Linienzeichnung über dem Luftbild.
const strassenEbene = Kartenebene(
  name: 'esri-verkehr',
  urlVorlage: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
  hoechsteStufe: 18,
  nennung: 'Esri, HERE, Garmin',
  seite: 'https://www.arcgis.com/home/item.html'
      '?id=00f90f3f3c9141e4bea329679b257142',
);

/// Ortsnamen, Grenzen und Beschriftung.
const orteEbene = Kartenebene(
  name: 'esri-orte',
  urlVorlage: 'https://server.arcgisonline.com/ArcGIS/rest/services/'
      'Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
  hoechsteStufe: 18,
  nennung: 'Esri, HERE, Garmin, © OpenStreetMap contributors',
  seite: 'https://www.arcgis.com/home/item.html'
      '?id=97fa1365da1e43eabb90d0364326bc2d',
);

/// Was unten liegt: eine Karte oder ein Luftbild.
enum Gelaendegrund {
  /// Die Wanderkarte – genau das, was die Geländeansicht bisher zeigte.
  wanderkarte,

  /// Die helle Strassenkarte.
  hell,

  /// Die dunkle Karte.
  dunkel,

  /// Die selbst eingetragene Quelle.
  eigene,

  /// Das Luftbild.
  luftbild;

  /// Der Kartenstil dahinter – `null` beim Luftbild, das keiner ist.
  Kartenstil? get stil => switch (this) {
        Gelaendegrund.wanderkarte => Kartenstil.topo,
        Gelaendegrund.hell => Kartenstil.hell,
        Gelaendegrund.dunkel => Kartenstil.dunkel,
        Gelaendegrund.eigene => Kartenstil.eigene,
        Gelaendegrund.luftbild => null,
      };

  /// Wie fein ein Block dieser Quelle zugemutet werden darf.
  ///
  /// **Nicht dasselbe wie „was der Anbieter liefert".** OpenTopoMap
  /// rendert Kacheln bei Bedarf; ein Überflug über das Ilsetal wollte 88
  /// Blöcke auf Stufe 17 und bekam in zwei Minuten 31 davon. Bei Stufe 16
  /// ist es **eine** Kachel je Block statt vier, und das schafft derselbe
  /// Server. Esri liefert aus einem Auslieferungsnetz und verträgt 18.
  int get hoechsteStufe => switch (this) {
        Gelaendegrund.wanderkarte => 16,
        Gelaendegrund.hell => 17,
        Gelaendegrund.dunkel => 17,
        // Was jemand selbst einträgt, ist meistens ein eigener Server
        // oder ein bezahlter Dienst – aber wissen kann die App das nicht.
        // Deshalb zurückhaltend.
        Gelaendegrund.eigene => 16,
        Gelaendegrund.luftbild => 18,
      };

  Kartenebene get ebene {
    if (this == Gelaendegrund.luftbild) return luftbildEbene;
    final s = stil!;
    return Kartenebene(
      name: s.name,
      urlVorlage: s.kachelUrl
          .replaceAll(
              '{s}', s.unterbereiche.isEmpty ? '' : s.unterbereiche.first)
          .replaceAll('{r}', ''),
      hoechsteStufe: hoechsteStufe,
      nennung: s.namensnennung,
      seite: s.seite,
    );
  }
}

/// Die ganze Auflage: Grund, Ebenen darüber und Höhenlinien.
///
/// **Warum die Ebenen einzeln schaltbar sind und nicht in drei fertigen
/// Stilen stecken.** Wer eine Waldwanderung ansieht, will Wege und
/// Luftbild; wer eine Radtour über Land ansieht, will Strassen und
/// Ortsnamen; wer die Form des Geländes lesen will, will Höhenlinien und
/// sonst möglichst wenig. Drei feste Stile träfen keinen davon genau.
class Gelaendekarte {
  const Gelaendekarte({
    this.grund = Gelaendegrund.wanderkarte,
    this.wege = false,
    this.beschriftung = false,
    this.hoehenlinien = false,
    this.wanderobjekte = false,
  });

  final Gelaendegrund grund;

  /// Wanderwege und Strassen als Linienzeichnung.
  final bool wege;

  /// Ortsnamen und Grenzen.
  final bool beschriftung;

  /// Höhenlinien – **selbst gerechnet und nicht geladen** (siehe
  /// `hoehenlinien.dart`). Deshalb stehen sie hier neben den Ebenen und
  /// nicht darunter.
  final bool hoehenlinien;

  /// Ob Gipfel, Hütten und Quellen als Schilder über der Landschaft
  /// stehen.
  ///
  /// **Eigener Schalter und nicht an [beschriftung] gehängt.** Die
  /// anderen Ebenen sind Kacheln von einem Auslieferungsnetz; diese hier
  /// kostet eine Abfrage bei Overpass, einem öffentlichen Dienst mit
  /// Grenzen. Wer sie nicht braucht, soll ihn nicht fragen müssen.
  final bool wanderobjekte;

  /// Wie stark die gerechnete Sonne auf den Grund wirken darf.
  ///
  /// **Bei einer Karte voll, bei einem Luftbild nur zur Hälfte.** Eine
  /// Karte ist flach gezeichnet und bekommt ihr Relief erst hier. Ein
  /// Luftbild bringt sein eigenes Licht mit – als es aufgenommen wurde,
  /// stand eine echte Sonne am Himmel. Unsere kommt dann obendrauf, und
  /// am gerenderten Bild des Ilsetals war das Ergebnis eine fast schwarze
  /// Waldflanke.
  ///
  /// Nicht null: Ein senkrecht aufgenommenes Luftbild verrät von der
  /// Steilheit eines Hangs kaum etwas, und ohne jede Schattierung sähe
  /// die Landschaft aus wie eine gewellte Tapete.
  double get reliefstaerke =>
      grund == Gelaendegrund.luftbild ? 0.45 : 1.0;

  /// Die Ebenen von unten nach oben.
  List<Kartenebene> get ebenen => [
        grund.ebene,
        if (wege) ...[wanderwegeEbene, strassenEbene],
        if (beschriftung) orteEbene,
      ];

  /// Die Namensnennung aller beteiligten Quellen, jede genau einmal.
  ///
  /// OpenStreetMap steht dabei, sobald Schilder im Bild sind: Die Daten
  /// dahinter stehen unter der ODbL, und die verlangt die Nennung.
  ///
  /// Eine Lizenzauflage, und sie muss zu dem passen, was tatsächlich im
  /// Bild steht: Wer die Wegeebene abschaltet, soll Waymarked Trails
  /// nicht mehr genannt sehen.
  String get nennung {
    final teile = <String>[];
    for (final e in ebenen) {
      if (!teile.contains(e.nennung)) teile.add(e.nennung);
    }
    if (wanderobjekte) {
      const osm = '© OpenStreetMap contributors (ODbL)';
      if (!teile.any((t) => t.contains('OpenStreetMap'))) teile.add(osm);
    }
    return teile.join(' · ');
  }

  Gelaendekarte kopieMit({
    Gelaendegrund? grund,
    bool? wege,
    bool? beschriftung,
    bool? hoehenlinien,
    bool? wanderobjekte,
  }) =>
      Gelaendekarte(
        grund: grund ?? this.grund,
        wege: wege ?? this.wege,
        beschriftung: beschriftung ?? this.beschriftung,
        hoehenlinien: hoehenlinien ?? this.hoehenlinien,
        wanderobjekte: wanderobjekte ?? this.wanderobjekte,
      );

  @override
  bool operator ==(Object other) =>
      other is Gelaendekarte &&
      other.grund == grund &&
      other.wege == wege &&
      other.beschriftung == beschriftung &&
      other.hoehenlinien == hoehenlinien &&
      other.wanderobjekte == wanderobjekte;

  @override
  int get hashCode =>
      Object.hash(grund, wege, beschriftung, hoehenlinien, wanderobjekte);
}

/// Die Nummer, unter der eine Wahl in der Datenbank steht.
///
/// Als Zahl und nicht als Name, aus demselben Grund wie beim Kartenstil:
/// Ein Name aus einer älteren Fassung könnte einer sein, den es nicht
/// mehr gibt. Eine Nummer ausserhalb der Reihe fällt auf die Vorgabe
/// zurück.
Gelaendegrund gelaendegrundAus(int nr) => nr >= 0 &&
        nr < Gelaendegrund.values.length
    ? Gelaendegrund.values[nr]
    : Gelaendegrund.wanderkarte;

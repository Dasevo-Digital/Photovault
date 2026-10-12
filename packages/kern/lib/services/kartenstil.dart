/// Die Kartenstile und ihre app-weiten Einstellungen (CARTO-Schlüssel,
/// eigene Karte, hohe Auflösung) – reine Daten ohne Flutter, damit auch
/// die Datenbank und der Server sie kennen. Gezeichnet wird in
/// `widgets/mini_location_map.dart`.
library;

import 'eigenkarte.dart';

/// Der eigene CARTO-Schlüssel, oder null.
///
/// Modulweit und nicht als Parameter durchgereicht, aus demselben Grund
/// wie beim Kachelspeicher: [buildMapTileLayer] wird an sechs Stellen
/// ohne jeden Zustand aufgerufen. Ein zusätzlicher Parameter müsste
/// durch jeden dieser Bildschirme wandern, obwohl es um eine einzige,
/// app-weite Angabe geht.
String? _cartoSchluessel;

/// Der gerade geltende CARTO-Schlüssel, oder null.
String? get cartoSchluessel => _cartoSchluessel;

/// Setzt den CARTO-Schlüssel für alle Karten dieser App.
///
/// Leer und null sind dasselbe: kein Schlüssel. Das ist wichtiger, als
/// es aussieht – eine leere Zeichenkette ergäbe die Adresse `…?key=`,
/// und darauf antwortet CARTO mit derselben gestempelten Kachel wie
/// ganz ohne Schlüssel.
void setzeCartoSchluessel(String? schluessel) {
  final wert = schluessel?.trim();
  _cartoSchluessel = wert == null || wert.isEmpty ? null : wert;
}

/// Die eingerichtete eigene Kartenquelle, oder null.
Eigenkarte? _eigeneKarte;

/// Die gerade geltende eigene Kartenquelle, oder null.
Eigenkarte? get eigeneKarte => _eigeneKarte;

/// Setzt die eigene Kartenquelle für alle Karten dieser App.
///
/// Modulweit aus demselben Grund wie beim CARTO-Schlüssel: Es ist eine
/// app-weite Angabe, und [buildMapTileLayer] wird an sechs Stellen ohne
/// jeden Zustand aufgerufen.
void setzeEigeneKarte(Eigenkarte? karte) => _eigeneKarte = karte;

/// Ob die Karte auf dichten Bildschirmen in doppelter Auflösung zeichnet.
///
/// Siehe `AppSettings.karteHochaufloesend` für den gemessenen Handel.
/// Modulweit aus demselben Grund wie die beiden Angaben darüber.
bool _karteHochaufloesend = true;

bool get karteHochaufloesend => _karteHochaufloesend;

void setzeKarteHochaufloesend(bool an) => _karteHochaufloesend = an;

/// Ob für [stil] auf **diesem** Bildschirm die doppelte Auflösung
/// nachgebildet wird – vier Kacheln der nächsttieferen Stufe an der
/// Stelle einer.
///
/// **Die eine Stelle, an der diese Frage beantwortet wird**, und das ist
/// der Zweck: Der Vorrat muss genau die Stufen laden, die die Karte
/// anfordert. Solange beide dieselbe Rechnung eigenständig anstellten,
/// liefen sie auseinander – der Vorrat lud die Serverstufen 3 bis 14 und
/// die Karte fragte für die Anzeigestufe z die Serverstufe z+1 an. Am
/// Bildschirm hiess das: eine vorgeladene Stufe, die niemand abrief, und
/// eine abgerufene, die niemand vorgeladen hatte.
///
/// Bei einer Adresse mit `{r}` liefert der Server selbst doppelt
/// aufgelöste Kacheln; dann verschiebt sich gar nichts.
bool nachgebildeteRetina(Kartenstil stil, double punktdichte) =>
    _karteHochaufloesend &&
    punktdichte > 1.0 &&
    !stil.kachelUrl.contains('{r}');

/// Um wie viele Stufen die angeforderte Serverstufe über der
/// Anzeigestufe liegt.
int stufenversatz(Kartenstil stil, double punktdichte) =>
    nachgebildeteRetina(stil, punktdichte) ? 1 : 0;

/// Die verfügbaren Kartenstile.
///
/// Ein Aufzählungstyp und kein `bool dark` mehr: Ein dritter Stil passt
/// nicht in einen Wahrheitswert, und „hell oder eben nicht hell" hätte
/// bei jeder weiteren Ergänzung erneut umgebaut werden müssen.
enum Kartenstil {
  /// OpenStreetMap-Standard statt Google Maps: quelloffen, kein
  /// API-Schlüssel nötig – passt zur restlichen App (keine proprietären
  /// Cloud-Dienste ausser den einmaligen KI-Modell-Downloads, siehe
  /// README).
  hell(
    kachelUrl: osmKachelUrl,
    namensnennung: _osmNennung,
    seite: _osmSeite,
    // Ausdrücklich, nicht über die Vorgabe: Ab Stufe 20 antwortet der
    // Server mit 400, nachgemessen.
    hoechsteEchteStufe: 19,
  ),

  /// Die dunkle Karte – **mit zwei Gesichtern**, je nachdem, ob ein
  /// CARTO-Schlüssel hinterlegt ist.
  ///
  /// Bis August 2026 lag hier CARTO Dark Matter, kostenlos und ohne
  /// Schlüssel. Das ist vorbei: CARTO schreibt seither quer über jede
  /// ausgelieferte Kachel „API KEY REQUIRED / carto.com/basemaps/apikey".
  /// An einer Kachel Berlin-Mitte nachgesehen, und zwar auf jeder Stufe:
  ///
  /// ```
  /// z10  z14  z16  z18  z20   -> Stempel auf allen
  /// cartodb-basemaps-a.global.ssl.fastly.net (alter Name) -> ebenso
  /// ```
  ///
  /// Beim Herauszoomen deckt eine Kachel den halben Schirm und der
  /// Schriftzug steht einmal im Bild; beim Hereinzoomen kacheln sich die
  /// Stempel. Deshalb fällt es erst dort auf – der Fehler war aber immer
  /// da.
  ///
  /// **Ohne Schlüssel** zeichnet dieser Stil deshalb dieselben
  /// OSM-Kacheln wie [hell], invertiert und im Farbton um 180° gedreht
  /// (siehe [invertieren]). Kein zweiter Anbieter, keine Anmeldung, und
  /// die Karte ist sofort dunkel. Grün bleibt grün, Wasser wird
  /// dunkelblau, Beschriftung hell – nachgesehen, bevor das hier stand.
  ///
  /// **Mit Schlüssel** kommt Dark Matter zurück, samt Stufe 20. CARTO
  /// gibt Schlüssel kostenlos und ohne Konto aus (5 Millionen Kacheln im
  /// Monat). Dass die Rasterkacheln laut CARTO „being retired" sind, ist
  /// der zweite Grund, warum der schlüssellose Weg die Vorgabe ist und
  /// nicht der Notnagel: Fällt CARTO eines Tages ganz weg, ändert sich
  /// für alle, die keinen Schlüssel eingetragen haben, gar nichts.
  dunkel(
    kachelUrl: osmKachelUrl,
    namensnennung: _osmNennung,
    seite: _osmSeite,
    hoechsteEchteStufe: 19,
  ),

  /// OpenTopoMap: Höhenlinien und Schummerung. Das Relief steckt in den
  /// Kacheln, nicht in einer 3D-Maschine – deshalb ist es hier ohne neue
  /// Abhängigkeit und auf allen drei Plattformen zu haben.
  ///
  /// **Nur bis Zoomstufe 17**, und das ist wichtiger als es klingt:
  /// Oberhalb davon antwortet der Server nicht etwa mit 404, sondern
  /// mit **HTTP 200 und einer einfarbigen Kachel**. An der Zugspitze
  /// nachgemessen:
  ///
  /// ```
  /// Zoom 16  200  53031 B  256 Farben
  /// Zoom 17  200  51161 B  255 Farben
  /// Zoom 18  200   4343 B    1 Farbe
  /// Zoom 19  200   4343 B    1 Farbe
  /// ```
  ///
  /// Ohne [hoechsteEchteStufe] wäre die Karte beim Hereinzoomen also
  /// schlicht leer – ohne Fehler, ohne Meldung, ohne Anhaltspunkt. Mit
  /// der Angabe vergrössert flutter_map die Kachel von Stufe 17.
  topo(
    kachelUrl: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    namensnennung:
        '© OpenStreetMap contributors, SRTM | © opentopomap.org (CC-BY-SA)',
    seite: 'https://opentopomap.org/about',
    hoechsteEchteStufe: 17,
  ),

  /// Die selbst eingetragene Quelle – Adresse, Namensnennung und
  /// Zoomgrenze kommen aus den Einstellungen (siehe [Eigenkarte]).
  ///
  /// **Der einzige Stil ohne feste Adresse**, und deshalb der einzige,
  /// der `null` liefern kann: Ist keine Quelle eingerichtet, taucht er
  /// im Kartenmenü gar nicht erst auf (siehe `Kartenansicht`). Die
  /// Ausweichwerte hier sind nur da, damit ein versehentlicher Aufruf
  /// nicht wirft – die Karte fiele dann auf OpenStreetMap zurück, was
  /// sichtbar falsch ist und nichts kaputt macht.
  eigene(
    kachelUrl: osmKachelUrl,
    namensnennung: _osmNennung,
    hoechsteEchteStufe: 19,
  );

  const Kartenstil({
    required this._kachelUrl,
    required this._namensnennung,
    this._seite,
    this._hoechsteEchteStufe,
  });

  final String _kachelUrl;
  final String _namensnennung;
  final String? _seite;
  final int? _hoechsteEchteStufe;

  /// Ob dieser Stil gerade auf CARTO zeigt – also nur die dunkle Karte,
  /// und nur mit hinterlegtem Schlüssel.
  bool get _ueberCarto => this == dunkel && _cartoSchluessel != null;

  /// Die Adresse der Kacheln.
  ///
  /// Der Fragezeichen-Teil steckt mit in [_cartoKacheln] und nicht hier:
  /// Ein Literal `'?key='` an dieser Stelle sähe für
  /// `keine_festen_texte_test.dart` wie ein vergessener
  /// Oberflächentext aus – „key" sind drei Buchstaben am Stück. Als Teil
  /// einer Adresse, die mit `https` beginnt, ist es eindeutig keiner.
  String get kachelUrl {
    if (this == eigene && _eigeneKarte != null) return _eigeneKarte!.url;
    return _ueberCarto ? '$_cartoKacheln$_cartoSchluessel' : _kachelUrl;
  }

  /// Die Namensnennung – eine Lizenzauflage, und sie muss zu den
  /// Kacheln passen, die tatsächlich im Bild stehen. CARTO verlangt sie
  /// ausdrücklich auch bei Nutzung mit Schlüssel.
  String get namensnennung {
    if (this == eigene && _eigeneKarte != null) return _eigeneKarte!.nennung;
    return _ueberCarto ? _cartoNennung : _namensnennung;
  }

  /// Die Seite des Anbieters – Lizenz und Bedingungen zu genau den
  /// Kacheln, die gerade im Bild stehen.
  ///
  /// Bei der eigenen Quelle `null`: Was dort eingetragen ist, weiss die
  /// App nicht, und eine geratene Adresse wäre schlimmer als keine.
  String? get seite {
    if (this == eigene) return null;
    return _ueberCarto ? _cartoSeite : _seite;
  }

  /// Nur CARTO verteilt seine Kacheln auf Unterbereiche; alle übrigen
  /// Quellen haben eine einzige Adresse.
  List<String> get unterbereiche =>
      _ueberCarto ? _cartoUnterbereiche : const <String>[];

  /// Ob die Kacheln beim Zeichnen invertiert werden müssen.
  ///
  /// Nur für die dunkle Karte ohne Schlüssel: Dort liegen helle
  /// OSM-Kacheln an, die erst durch die Farbmatrix dunkel werden.
  bool get invertieren => this == dunkel && _cartoSchluessel == null;

  /// Höchste Stufe, für die der Anbieter echte Kacheln liefert. `null`
  /// heisst „so weit wie die Karte zoomt".
  int? get hoechsteEchteStufe {
    if (this == eigene && _eigeneKarte != null) {
      return _eigeneKarte!.hoechsteEchteStufe;
    }
    return _ueberCarto ? 20 : _hoechsteEchteStufe;
  }

  /// Bis hierhin darf die Karte zoomen.
  ///
  /// **Ohne diese Grenze zoomt die Karte ins Nichts.** Oberhalb der
  /// echten Stufe vergrössert flutter_map die letzte vorhandene Kachel
  /// weiter und weiter: auf Anzeigestufe 24 deckt eine einzige
  /// Topo-Kachel 32.768 Punkte ab, auf Stufe 28 über eine halbe Million.
  /// So etwas kann keine Grafikeinheit mehr zeichnen – und am Bildschirm
  /// sieht es aus, als würden die Kacheln „nicht mehr laden".
  ///
  /// Zwei Stufen darüber sind bewusst erlaubt statt hart bei der echten
  /// Stufe abzuschneiden: Die Kachel wird dabei vierfach vergrössert,
  /// also unschärfer, aber sie ist **da**. Ein hartes Ende fühlte sich
  /// wie ein Defekt an, ein leerer Bildschirm erst recht.
  ///
  /// An den Servern nachgemessen, mitten in Berlin:
  ///
  /// ```
  /// OSM     z19 200,  z20 400            -> harte Grenze bei 19
  /// CARTO   z20 200 (3.765 B, Inhalt)    -> trägt bis 20
  /// Topo    z17 200,  z18 200 aber 4.343 B einfarbig -> Ende bei 17
  /// ```
  int get hoechsteAnzeigeStufe => (hoechsteEchteStufe ?? 19) + 2;
}

const osmKachelUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmNennung = '© OpenStreetMap contributors';

/// Die CARTO-Adresse **einschliesslich** des Schlüsselparameters – der
/// Schlüssel selbst wird angehängt (siehe [Kartenstil.kachelUrl]).
const _cartoKacheln =
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png?key=';
const _cartoNennung = '© OpenStreetMap contributors © CARTO';
const _cartoUnterbereiche = ['a', 'b', 'c', 'd'];

/// Die Seite hinter der Namensnennung – dort stehen die Bedingungen, zu
/// denen die Kacheln benutzt werden dürfen.
const _osmSeite = 'https://www.openstreetmap.org/copyright';
const _cartoSeite = 'https://carto.com/attributions';

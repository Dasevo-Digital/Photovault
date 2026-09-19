// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppTexteDe extends AppTexte {
  AppTexteDe([String locale = 'de']) : super(locale);

  @override
  String get allgAbbrechen => 'Abbrechen';

  @override
  String get allgSpeichern => 'Speichern';

  @override
  String get allgSchliessen => 'Schließen';

  @override
  String get allgErstellen => 'Erstellen';

  @override
  String get allgStarten => 'Starten';

  @override
  String get allgName => 'Name';

  @override
  String get allgMehr => 'Mehr';

  @override
  String get allgAlleAnzeigen => 'Alle anzeigen';

  @override
  String get navTimeline => 'Timeline';

  @override
  String get navErkunden => 'Erkunden';

  @override
  String get navKalender => 'Kalender';

  @override
  String get navReisen => 'Reisen';

  @override
  String get kuerzelReisenOhne =>
      'Die Reisen haben kein Kürzel – die zehn Ziffern waren vergeben, und eine Umnummerierung hätte alle eingeübten verschoben.';

  @override
  String get navKarte => 'Karte';

  @override
  String get navSuche => 'Suche';

  @override
  String get navPersonen => 'Personen';

  @override
  String get navAlben => 'Alben';

  @override
  String get navWerkzeuge => 'Werkzeuge';

  @override
  String get navEinstellungen => 'Einstellungen';

  @override
  String get importierenTooltip => 'Fotos/Videos importieren';

  @override
  String geoeffneteBibliothek(String name) {
    return 'Geöffnete Bibliothek: $name';
  }

  @override
  String get restaurierungWirdVorbereitet =>
      'KI-Restaurierung wird vorbereitet …';

  @override
  String restaurierungWartend(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos in der Warteschlange für die KI-Restaurierung',
      one: '1 Foto in der Warteschlange für die KI-Restaurierung',
    );
    return '$_temp0';
  }

  @override
  String analyseLaeuft(
      String stufe, int nummer, int gesamt, String fortschritt) {
    return '$stufe wird berechnet (Schritt $nummer von $gesamt$fortschritt)';
  }

  @override
  String get kuerzelTitel => 'Tastaturkürzel';

  @override
  String get kuerzelRaster => 'Raster (Zeitleiste, Kalender, Album, Suche)';

  @override
  String get kuerzelUmschaltKlick => 'Umschalt-Klick';

  @override
  String get kuerzelStrgKlick => 'Strg-/⌘-Klick';

  @override
  String get kuerzelUmschaltPfeil => 'Umschalt + Pfeil';

  @override
  String get kuerzelBereichWaehlen => 'Alles bis hierher dazunehmen';

  @override
  String get kuerzelEinzelnWaehlen => 'Eine einzelne Kachel umschalten';

  @override
  String get kuerzelRahmenBewegen => 'Den Rahmen durchs Raster bewegen';

  @override
  String get kuerzelAuswahlZiehen => 'Die Auswahl mitziehen';

  @override
  String get kuerzelFarbmarkeSetzen => 'Farbmarke setzen';

  @override
  String get kuerzelAuswahlLeeren => 'Auswahl leeren';

  @override
  String get kuerzelFotoOeffnen => 'Foto öffnen';

  @override
  String get kuerzelWirktAuf =>
      'Die Tasten wirken auf die Auswahl. Gibt es keine, wirken sie auf die Kachel, auf der der Rahmen steht.';

  @override
  String get einstBeschrKuerzel => 'Alle Tastaturkürzel auf einen Blick';

  @override
  String get kuerzelNavigation => 'Navigation';

  @override
  String get kuerzelVollbild => 'Vollbildansicht';

  @override
  String get kuerzelSichtung => 'Sichtungs-Modus (Culling)';

  @override
  String get kuerzelBereicheWechseln => 'Zwischen den Hauptbereichen wechseln';

  @override
  String get kuerzelUebersichtOeffnen => 'Diese Übersicht öffnen';

  @override
  String get kuerzelVorherigesNaechstes => 'Vorheriges / nächstes Foto';

  @override
  String get kuerzelLeertaste => 'Leertaste';

  @override
  String get kuerzelNaechstesFoto => 'Nächstes Foto';

  @override
  String get kuerzelBewertungSetzen => 'Sternebewertung setzen';

  @override
  String get kuerzelFavoritUmschalten => 'Favorit umschalten';

  @override
  String get kuerzelPapierkorbMitBestaetigung =>
      'In den Papierkorb verschieben (mit Bestätigung)';

  @override
  String get kuerzelSofortAblehnen =>
      'Sofort ablehnen und weiter (ohne Bestätigung)';

  @override
  String get kuerzelZoomWischen => '⌘/Strg + Wischen';

  @override
  String get kuerzelZoomImBild =>
      'Ins Bild hinein- und herauszoomen (auch mit einer Magic Mouse)';

  @override
  String get timelineLeer => 'Noch keine Fotos in der Bibliothek.';

  @override
  String loeschenTitel(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos löschen?',
      one: 'Foto löschen?',
    );
    return '$_temp0';
  }

  @override
  String loeschenHinweis(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'Diese Fotos werden in den Papierkorb verschoben.',
      one: 'Wird in den Papierkorb verschoben.',
    );
    return '$_temp0';
  }

  @override
  String get albumNeu => 'Neues Album';

  @override
  String get albumName => 'Albumname';

  @override
  String get albenLeer => 'Noch keine Alben vorhanden.';

  @override
  String get albenIntelligente => 'Intelligente Alben';

  @override
  String get albenGewoehnliche => 'Alben';

  @override
  String get albumIntelligentLoeschen => 'Intelligentes Album löschen';

  @override
  String albumIntelligentLoeschenFrage(String name) {
    return '„$name“ entfernen? Die Aufnahmen bleiben, nur die gespeicherte Suche verschwindet.';
  }

  @override
  String get albenIntelligentWoher =>
      'Ein intelligentes Album ist eine gespeicherte Suche: Es sammelt keine Aufnahmen ein, sondern zeigt jedes Mal neu, was gerade passt. Angelegt wird es in der Suche über das Lesezeichen neben dem Suchfeld.';

  @override
  String get erkundenPersonen => 'Personen';

  @override
  String get erkundenOrte => 'Orte';

  @override
  String get erkundenLetzteAlben => 'Zuletzt hinzugefügte Alben';

  @override
  String get erkundenLetzteFotos => 'Zuletzt hinzugefügte Fotos';

  @override
  String get erkundenErinnerungen => 'Erinnerungen';

  @override
  String get ohneOrtLeer => 'Noch keine Fotos mit bekanntem Ort.';

  @override
  String get karteTitel => 'Karte';

  @override
  String get karteAnsicht => 'Kartenansicht';

  @override
  String get karteTexturNachweis =>
      'Erd-/Sternentextur: Solar System Scope (CC BY 4.0)';

  @override
  String get kalenderLeer => 'Noch keine Fotos für eine Jahresübersicht.';

  @override
  String get kalenderJahrLeer => 'Keine Fotos in diesem Jahr.';

  @override
  String kalenderAnzahlFotos(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos/Videos',
      one: '$anzahl Foto/Video',
    );
    return '$_temp0';
  }

  @override
  String get sucheSpeichernTitel => 'Suche speichern';

  @override
  String get sucheModellFehlt =>
      'Für die Kontext-Suche fehlt das Bildsuche-Modell. Es lässt sich in den Einstellungen unter „KI-Modelle“ laden.';

  @override
  String get sucheModellLaedt => 'Modell für die Bildsuche wird geladen …';

  @override
  String get sucheOhneEmbeddings =>
      'Noch ist kein Foto für die KI-Bildsuche ausgewertet. Der Durchgang steht unter Werkzeuge → Aufgaben („CLIP-Embeddings“).';

  @override
  String get sucheOhneTexterkennung =>
      'Noch ist auf keinem Foto Text erkannt worden. Der Durchgang steht unter Werkzeuge → Aufgaben („Text erkennen (OCR)“).';

  @override
  String sucheModellUnbrauchbar(String datei) {
    return 'Das Modell $datei liegt zwar auf der Platte, lässt sich aber nicht öffnen. Lade es unter Einstellungen → KI-Modelle neu – die Suche und die KI-Schlagwörter brauchen es.';
  }

  @override
  String sucheFehlgeschlagen(String fehler) {
    return 'Suche fehlgeschlagen: $fehler';
  }

  @override
  String get suchePlatzhalterKontext =>
      'z.B. „Sonnenuntergang am Meer“, „Hund im Schnee“ …';

  @override
  String get suchePlatzhalterDateiname => 'Dateiname …';

  @override
  String get suchePlatzhalterBeschreibung => 'Beschreibung …';

  @override
  String get suchePlatzhalterText => 'Text im Foto …';

  @override
  String get suchePlatzhalterBildunterschrift => 'z.B. „dog“, „sunset“ …';

  @override
  String get werkzStaubText =>
      'Untersucht eine Stichprobe der Aufnahmen einer Kamera darauf, ob an immer derselben Stelle ein dunkler Fleck sitzt.';

  @override
  String get staubTitel => 'Sensorstaub suchen';

  @override
  String get staubErklaerung =>
      'Sensorstaub sitzt bei jeder Aufnahme derselben Kamera an derselben Stelle. Genau daran ist er zu erkennen: Die App untersucht eine über den ganzen Zeitraum verteilte Stichprobe und meldet nur, was immer wieder an derselben Stelle auftaucht. Ein einzelnes dunkles Pünktchen kann alles sein.';

  @override
  String get staubKeineKameras =>
      'In dieser Bibliothek ist keine Kamera vermerkt.';

  @override
  String get staubSuchen => 'Suchen';

  @override
  String staubFortschritt(int erledigt, int gesamt) {
    return '$erledigt von $gesamt Aufnahmen untersucht';
  }

  @override
  String staubNichtsGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          'Auf $anzahl untersuchten Aufnahmen wurde kein Sensorstaub gefunden.',
      one: 'Auf der untersuchten Aufnahme wurde kein Sensorstaub gefunden.',
    );
    return '$_temp0';
  }

  @override
  String staubGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Stellen, die immer wieder auftauchen',
      one: '1 Stelle, die immer wieder auftaucht',
    );
    return '$_temp0';
  }

  @override
  String staubAufWievielen(int treffer, int gesamt) {
    return 'auf $treffer von $gesamt untersuchten Aufnahmen';
  }

  @override
  String staubUebersprungen(int anzahl, int gesamt) {
    return '$anzahl von $gesamt Aufnahmen liessen sich nicht lesen und wurden übersprungen.';
  }

  @override
  String get staubImEditorOeffnen =>
      'Eine betroffene Aufnahme im Bildeditor öffnen';

  @override
  String get allgKamera => 'Kamera';

  @override
  String get sucheSatzVerwerfen => 'Deutung zurücknehmen und wörtlich suchen';

  @override
  String get sucheOptionen => 'Suchoptionen';

  @override
  String get sucheAusloesen => 'Suchen';

  @override
  String get sucheAnleitung =>
      'Gib einen Suchbegriff ein oder wähle Suchoptionen.';

  @override
  String get sucheKeineTreffer => 'Keine Treffer.';

  @override
  String get viewerInfo => 'Info';

  @override
  String get viewerTeilen => 'Teilen';

  @override
  String get viewerExportieren => 'Exportieren';

  @override
  String get viewerEntwickeln => 'Entwickeln';

  @override
  String get viewerBearbeiten => 'Bearbeiten';

  @override
  String get viewerZuschneiden => 'Zuschneiden';

  @override
  String get viewerDiaschauStarten => 'Diaschau starten';

  @override
  String get viewerDiaschauStoppen => 'Diaschau stoppen';

  @override
  String get viewerFavoritSetzen => 'Als Favorit markieren (F)';

  @override
  String get viewerFavoritEntfernen => 'Favorit entfernen (F)';

  @override
  String get viewerInGesperrtenOrdner =>
      'In gesperrten Ordner verschieben (verschlüsselt)';

  @override
  String get viewerInPapierkorb => 'In den Papierkorb verschieben (⌫)';

  @override
  String get viewerVorherigesFoto => 'Vorheriges Foto';

  @override
  String get viewerNaechstesFoto => 'Nächstes Foto';

  @override
  String get viewerInTimelineZeigen => 'Foto in der Timeline anzeigen';

  @override
  String get viewerAehnlicheZeigen => 'Ähnliche Bilder anzeigen';

  @override
  String get viewerMetadatenBearbeiten => 'Metadaten bearbeiten';

  @override
  String get viewerGesichterBearbeiten => 'Gesichter bearbeiten';

  @override
  String get viewerGesichterZeigen => 'Gesichter zeigen';

  @override
  String get viewerGesichterVerbergen => 'Gesichter verbergen';

  @override
  String get viewerKeineGesichter =>
      'Auf diesem Foto ist kein Gesicht erkannt.';

  @override
  String get viewerGesichtBenennen => 'Gesicht benennen';

  @override
  String get viewerEntwicklungAnwenden => 'Kopierte Entwicklung anwenden';

  @override
  String get viewerEntwicklungAnwendenLang =>
      'Kopierte Entwicklung auf dieses Foto anwenden';

  @override
  String get viewerFokusPeaking => 'Fokus-Peaking (scharfe Kanten hervorheben)';

  @override
  String get viewerGesichtUnscharf => 'Auch das schärfste Gesicht ist unscharf';

  @override
  String get viewerTextZeigen => 'Erkannten Text hervorheben';

  @override
  String get viewerTextVerbergen => 'Texthervorhebung ausblenden';

  @override
  String get viewerKeinText => 'In diesem Foto wurde kein Text erkannt.';

  @override
  String get viewerTextNochNicht =>
      'Für dieses Foto sind noch keine Textstellen gespeichert – ein Lauf der Texterkennung holt sie nach.';

  @override
  String viewerZeileKopiert(String text) {
    return '„$text“ kopiert';
  }

  @override
  String get viewerFlachesSchwenken => 'Flaches Schwenken statt 3D-Kugel';

  @override
  String get viewerFlacheVorschau => 'Flache Vorschau statt 360°-Ansicht';

  @override
  String get viewerExportZielordner => 'Zielordner zum Exportieren wählen';

  @override
  String viewerExportiert(String dateien) {
    return 'Exportiert: $dateien';
  }

  @override
  String viewerExportFehlgeschlagen(String fehler) {
    return 'Export fehlgeschlagen: $fehler';
  }

  @override
  String viewerTeilenFehlgeschlagen(String fehler) {
    return 'Teilen fehlgeschlagen: $fehler';
  }

  @override
  String get personenTab => 'Personen';

  @override
  String get personenUnbenannteTab => 'Unbenannte Gesichter';

  @override
  String get personenLeer =>
      'Noch keine Personen angelegt. Wechsle zum Tab „Unbenannte Gesichter“, wähle ein paar Gesichter aus und ordne sie einer neuen Person zu.';

  @override
  String get personenLangeDruecken => 'lange drücken: zusammenführen';

  @override
  String get personenKeineUnbenannten =>
      'Keine unbenannten Gesichter (mehr). Neue erscheinen hier automatisch, sobald du weitere Fotos importierst oder erneut nach Gesichtern suchst. Einzelne kannst du auch selbst markieren: Foto öffnen, Rechtsklick → „Gesichter bearbeiten“, dann oben rechts auf „Gesicht manuell hinzufügen“.';

  @override
  String get personenOhneGesichtsmodell =>
      'Ohne ein Modell für die Gesichtserkennung findet Photo Vault keine Gesichter.';

  @override
  String personenNochNichtDurchsucht(int offen) {
    String _temp0 = intl.Intl.pluralLogic(
      offen,
      locale: localeName,
      other: '$offen Aufnahmen sind noch nicht nach Gesichtern durchsucht.',
      one: 'Eine Aufnahme ist noch nicht nach Gesichtern durchsucht.',
    );
    return '$_temp0 Solange das aussteht, kann hier nichts stehen.';
  }

  @override
  String get personenJetztSuchen => 'Jetzt nach Gesichtern suchen';

  @override
  String get personenSucheLaeuft =>
      'Die Gesichtssuche läuft gerade. Die ersten Funde erscheinen hier, sobald sie durch ist.';

  @override
  String get personenSchwellenHinweis =>
      'Ähnlichkeitsschwelle einstellbar unter Werkzeuge → Gesichtserkennung.';

  @override
  String get personenDoppelklickHinweis =>
      'Doppelklick auf ein Gesicht öffnet das ganze Foto zur Kontrolle.';

  @override
  String get personenAutomatischGruppieren => 'Automatisch gruppieren';

  @override
  String get personenAehnlicheAuswaehlen => 'Ähnliche mit auswählen';

  @override
  String get personenAehnlicheAbwaehlen => 'Ähnliche abwählen';

  @override
  String personenZuordnen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter zuordnen',
      one: 'Gesicht zuordnen',
    );
    return '$_temp0';
  }

  @override
  String get personenModellFehlt =>
      'Für die Ähnlichkeitssuche wird das SFace-Modell benötigt (siehe Einstellungen → Modelle).';

  @override
  String personenKeineAehnlichen(String schwelle) {
    return 'Keine ähnlichen Gesichter über der Schwelle $schwelle gefunden.';
  }

  @override
  String get personenZuWenigeFuerClustering =>
      'Nicht genug unbenannte Gesichter mit Embedding für ein Clustering.';

  @override
  String get personenKeineGruppen => 'Keine ähnlichen Gruppen gefunden.';

  @override
  String get personenDauertTitel => 'Das kann etwas dauern';

  @override
  String personenDauertText(int anzahl) {
    return '$anzahl unbenannte Gesichter gefunden. Die automatische Gruppierung vergleicht jedes mit jedem und kann bei so vielen Gesichtern einige Zeit dauern (die App bleibt währenddessen bedienbar). Trotzdem starten?';
  }

  @override
  String personenZusammenfuehrenMit(String name) {
    return '„$name“ zusammenführen mit …';
  }

  @override
  String get personenZusammenfuehrenTitel => 'Zusammenführen bestätigen';

  @override
  String personenZusammenfuehrenText(String quelle, String ziel) {
    return 'Alle Fotos von „$quelle“ werden „$ziel“ zugeordnet. „$quelle“ wird danach gelöscht. Das lässt sich nicht rückgängig machen.';
  }

  @override
  String get personenZusammenfuehren => 'Zusammenführen';

  @override
  String get spracheTitel => 'Sprache';

  @override
  String get spracheSystem => 'Systemsprache';

  @override
  String get spracheDeutsch => 'Deutsch';

  @override
  String get spracheEnglisch => 'English';

  @override
  String get spracheHinweis =>
      'Betrifft nur die Oberfläche. Deine Alben, Schlagwörter und Personennamen bleiben, wie sie sind.';

  @override
  String get spracheVokabularTitel => 'Schlagwort-Vokabular mitübersetzen?';

  @override
  String spracheVokabularText(int bekannt, int gesamt) {
    return '$bekannt der $gesamt Begriffe im Vokabular stammen aus der mitgelieferten Startbestückung und lassen sich zuverlässig übersetzen. Bereits vergebene Schlagwörter wandern mit, es geht nichts verloren.';
  }

  @override
  String spracheVokabularSelbstAngelegt(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl selbst hinzugefügte Begriffe bleiben unverändert.',
      one: 'Ein selbst hinzugefügter Begriff bleibt unverändert.',
      zero: '',
    );
    return '$_temp0';
  }

  @override
  String get spracheVokabularUebersetzen => 'Übersetzen';

  @override
  String get spracheVokabularBehalten => 'Unverändert lassen';

  @override
  String spracheVokabularFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Begriffe übersetzt.',
      one: 'Ein Begriff übersetzt.',
    );
    return '$_temp0';
  }

  @override
  String get erkundenKeineOrte =>
      'Noch keine Orte aufgelöst (siehe Werkzeuge → Orte).';

  @override
  String get erkundenKeineFotos => 'Noch keine Fotos importiert.';

  @override
  String get karteKeineOrteLang =>
      'Noch keine Fotos mit bekanntem Ort.\n\nDer Ort wird beim Import automatisch aus den GPS-Daten eines Fotos übernommen (falls vorhanden) oder lässt sich in der Info-Ansicht eines Fotos/Videos (Vollbildvorschau → ⓘ) manuell festlegen.';

  @override
  String einstOrdnerNichtGeoeffnet(String pfad) {
    return 'Ordner konnte nicht geöffnet werden: $pfad';
  }

  @override
  String einstBibWechselnTitel(String name) {
    return 'Zu „$name“ wechseln?';
  }

  @override
  String get einstBibWechselnText =>
      'Die App wird danach geschlossen und öffnet beim nächsten Start die gewählte Bibliothek.\n\nEs werden keine Fotos verschoben oder gelöscht – beide Bibliotheken bleiben unverändert an ihrem Ort.';

  @override
  String get einstBibGewechselt =>
      'Die Bibliothek wurde gewechselt. Es wurden keine Daten verschoben. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen.';

  @override
  String get einstBibHinzufuegenAuswahl =>
      'Ordner einer bestehenden Bibliothek wählen – oder einen leeren Ordner für eine neue. Es wird nichts verschoben.';

  @override
  String get einstBibBestehendHinzugefuegt =>
      'Bestehende Bibliothek hinzugefügt.';

  @override
  String get einstBibLeerHinzugefuegt =>
      'Leerer Ordner hinzugefügt – beim Wechseln dorthin entsteht eine neue, leere Bibliothek.';

  @override
  String einstBibEntfernenTitel(String name) {
    return '„$name“ aus der Liste entfernen?';
  }

  @override
  String get einstBibEntfernenText =>
      'Die Bibliothek verschwindet nur aus dieser Liste. Fotos, Datenbank und Ordner bleiben unverändert erhalten und lassen sich jederzeit wieder hinzufügen.';

  @override
  String get einstBibNichtEntfernbar =>
      'Dieser Eintrag lässt sich nicht entfernen.';

  @override
  String get einstBibListe => 'Bibliotheken';

  @override
  String get einstBibHinzufuegen => 'Bibliothek hinzufügen…';

  @override
  String get einstBibAusListeEntfernen =>
      'Aus der Liste entfernen (löscht keine Fotos)';

  @override
  String get einstBibNichtGefunden =>
      'Ordner nicht gefunden – Laufwerk eingebunden?';

  @override
  String get einstBibWechselHinweis =>
      'Ein Wechsel biegt nur um, welche Bibliothek geöffnet wird – es werden keine Fotos verschoben. Zum Verlegen der aktuellen Bibliothek an einen anderen Ort dient „Speicherort ändern\" weiter unten.';

  @override
  String get einstSpeicherortTitel => 'Speicherort der aktiven Bibliothek';

  @override
  String get einstSpeicherortWaehlen =>
      'Fotos, Videos, Thumbnails und die Datenbank werden in diesen Ordner verschoben. Bitte einen bereits vorhandenen Ordner wählen (falls nötig vorher im Finder anlegen).';

  @override
  String get einstSpeicherortZuruecksetzenTitel => 'Speicherort zurücksetzen?';

  @override
  String get einstSpeicherortZuruecksetzenText =>
      'Die Bibliothek wird zurück in den Standard-App-Support-Ordner verschoben. Die App wird danach automatisch geschlossen – bitte anschließend neu öffnen.';

  @override
  String get einstSpeicherortZuruecksetzenLaeuft =>
      'Setze Speicherort zurück …';

  @override
  String get einstSpeicherortGeaendert =>
      'Der Speicherort wurde geändert. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen, damit sie die Bibliothek am neuen Ort lädt.';

  @override
  String get einstImFinderAnzeigen => 'Im Finder anzeigen';

  @override
  String get einstAendern => 'Ändern…';

  @override
  String get einstZuruecksetzen => 'Zurücksetzen';

  @override
  String get einstWirdBerechnet => 'wird berechnet …';

  @override
  String get einstUeberwachtTitel => 'Überwachter Ordner';

  @override
  String get einstUeberwachtKeiner => 'Kein Ordner eingerichtet';

  @override
  String get einstUeberwachtErklaerung =>
      'Was in einem gewählten Ordner auftaucht, wird von selbst in die Bibliothek aufgenommen – alle fünf Minuten und bei jedem Start.';

  @override
  String get einstUeberwachtAktiv =>
      'Wird alle fünf Minuten geprüft. Die Dateien bleiben dort liegen.';

  @override
  String get einstUeberwachtWaehlen => 'Ordner wählen…';

  @override
  String get einstUeberwachtAndererWaehlen => 'Anderen Ordner…';

  @override
  String get einstUeberwachtBeenden => 'Nicht mehr überwachen';

  @override
  String get einstUeberwachtAuswahl =>
      'Ordner wählen, der laufend auf neue Fotos geprüft werden soll. Die Dateien bleiben dort liegen; sie werden nur zusätzlich in die Bibliothek aufgenommen.';

  @override
  String einstUeberwachtUebernommen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl neue Fotos aus dem Ordner übernommen.',
      one: '1 neues Foto aus dem Ordner übernommen.',
    );
    return '$_temp0';
  }

  @override
  String get einstKiHinweis =>
      'Wie bei digiKam laufen alle KI-Funktionen offline auf diesem Rechner. Die Modelldateien werden nicht mitgeliefert, sondern bei Bedarf aus offiziellen Open-Source-Quellen heruntergeladen (einmalig, danach komplett offline nutzbar).';

  @override
  String get einstAutoAnalyseTitel =>
      'KI-Auswertung nach dem Import automatisch nachholen';

  @override
  String get einstAutoAnalyseText =>
      'Der Import legt die Fotos nur ab und bleibt dadurch schnell. Gesichter, Texterkennung, Bildsuche und Bildbeschreibung laufen danach im Hintergrund nach. Ausgeschaltet lässt sich das jederzeit unter Werkzeuge von Hand anstoßen.';

  @override
  String get einstNurErkennung =>
      'Nur Erkennung aktiv (Wiedererkennung: SFace-Modell fehlt noch)';

  @override
  String get einstAufgabenTitel => 'Aufgaben-Übersicht';

  @override
  String get einstAufgabenText =>
      'Alle Auswertungen mit Anzahl noch offener Fotos, einzeln anstoßbar';

  @override
  String get einstModellLoeschen => 'Modell löschen';

  @override
  String einstModellNichtGeladen(String beschreibung) {
    return '$beschreibung\n\nDas zugehörige Modell ist noch nicht geladen.';
  }

  @override
  String get einstVokabularText =>
      'Begriffe, die automatisch per KI-Bildsuche-Modell (CLIP) auf neu importierte Fotos angewendet werden. Änderungen hier gelten nur für künftige Fotos – um sie rückwirkend auf die vorhandene Bibliothek anzuwenden, siehe Werkzeuge → \"KI-Tags berechnen\" → \"Alle Fotos\".';

  @override
  String get einstBegriffHinzufuegenFeld => 'Begriff hinzufügen …';

  @override
  String get einstBegriffHinzufuegen => 'Begriff hinzufügen';

  @override
  String get einstOrteText =>
      'Ordnet dem GPS-Ort eines Fotos Land, Bundesland/Provinz und Stadt zu – komplett lokal über die nächstgelegene bekannte Stadt (GeoNames-Datensatz), ohne Anfrage an einen Online-Kartendienst. Für die Land-/Bundesland-/Stadt-Filter in den Suchoptionen nötig.';

  @override
  String get einstGeoTitel => 'GeoNames – Städte, Länder, Bundesländer';

  @override
  String einstGeoText(String lizenz) {
    return 'Städte ab 1000 Einwohnern weltweit (~10 MB). Lizenz: $lizenz.';
  }

  @override
  String get einstGeoLoeschen => 'GeoNames-Datensatz löschen';

  @override
  String get einstGesperrtText =>
      'Verschlüsselt private Fotos mit AES-256 (echte Verschlüsselung, nicht nur ein Anzeige-Filter) und blendet sie überall sonst (Timeline, Suche, Alben, Personen, Karte, Backup) aus. Ohne den PIN gibt es keine Wiederherstellung.';

  @override
  String get einstGesperrtEntsperrt =>
      'PIN eingerichtet – für diese Sitzung bereits entsperrt.';

  @override
  String get einstGesperrtOeffnen => 'Öffnen';

  @override
  String get einstPinAendern => 'PIN ändern';

  @override
  String get einstGesperrtAufloesenText =>
      'Alle Fotos im gesperrten Ordner werden entschlüsselt und wieder normal sichtbar (Timeline, Suche, Alben, Personen, Karte, Backup). Das lässt sich nicht rückgängig machen.';

  @override
  String get einstBackupVerschluesselungTitel => 'Backup-Verschlüsselung';

  @override
  String get einstBackupVerschluesselungText =>
      'Ermöglicht, manuelle und automatische Backups mit AES-256 zu verschlüsseln. Eigene Passphrase, unabhängig vom PIN des gesperrten Ordners – ein Backup landet oft extern und muss auch ohne diesen Rechner entschlüsselbar sein.';

  @override
  String get einstBackupEntsperrt =>
      'Eingerichtet – für diese Sitzung bereits entsperrt.';

  @override
  String get einstBackupGesperrt =>
      'Eingerichtet – wird beim nächsten Backup abgefragt.';

  @override
  String get einstBackupAendern => 'Ändern';

  @override
  String get einstBackupNieGesichert => 'Noch nie gesichert.';

  @override
  String get einstBackupVerschluesseln => 'Backup verschlüsseln';

  @override
  String get einstBackupPassphraseAbfrage =>
      'Fragt bei Bedarf die Backup-Passphrase von oben ab.';

  @override
  String get einstBackupZielWaehlen =>
      'Backup-Ziel wählen (z.B. dein Dropbox- oder Google-Drive-Ordner)';

  @override
  String get einstBackupOrdnerWaehlen =>
      'Backup-Ordner wählen (enthält \"PhotoVault-Backup\" bzw. \"originals\")';

  @override
  String get einstBackupEntschluesselnTitel =>
      'Backup-Verschlüsselung entfernen?';

  @override
  String get einstBackupEntschluesselnText =>
      'Neue Backups werden danach nicht mehr verschlüsselt. Bereits bestehende verschlüsselte Backups am Zielort bleiben unverändert und weiterhin nur mit der bisherigen Passphrase entschlüsselbar.';

  @override
  String get einstBackupLaeuft => 'Automatisches Backup läuft …';

  @override
  String get einstBackupKeineNeuen =>
      'Keine neuen Dateien – Datenbank-Schnappschuss wird aktualisiert.';

  @override
  String get einstBackupZielHinweis =>
      'Wähle als Ziel z.B. deinen lokalen Dropbox- oder Google-Drive-Ordner – die Desktop-App des jeweiligen Anbieters lädt die Dateien dann automatisch in die Cloud hoch.';

  @override
  String get einstBackupAutoHinweis =>
      'Läuft nur, während die App geöffnet ist (kein Hintergrunddienst) – prüft beim Start und danach alle 30 Minuten, ob das Intervall abgelaufen ist. Sichert immer verschlüsselt, zusätzlich zu den Originaldateien auch einen Schnappschuss der gesamten Datenbank (Gesichter, Orte, Tags, Alben, Favoriten, …), damit sich bei Datenverlust der komplette Zustand wiederherstellen lässt. Löscht am Zielort nie etwas – lokale Löschungen werden bewusst nicht nachvollzogen.';

  @override
  String get einstBackupZuerstZiel => 'Zuerst einen Zielordner wählen.';

  @override
  String get einstBackupKeinOrdner => 'Kein Ordner gewählt.';

  @override
  String get einstBackupAutoZielWaehlen =>
      'Zielordner für automatisches Backup wählen';

  @override
  String get einstWaehlen => 'Wählen…';

  @override
  String get einstStuendlich => 'Stündlich';

  @override
  String get einstTaeglich => 'Täglich';

  @override
  String get einstWoechentlich => 'Wöchentlich';

  @override
  String get einstBackupGrenzeText =>
      'Begrenzt, wie viel pro Durchlauf ins Ziel geschrieben wird. Sinnvoll bei Cloud-Ordnern: Der Upload kommt sonst tagelang nicht hinterher. Der Rest folgt beim nächsten Intervall.';

  @override
  String get einstNieAusgefuehrt => 'Noch nie ausgeführt.';

  @override
  String get einstBackupPassphraseGesperrt =>
      'Backup-Passphrase muss für diese Sitzung noch entsperrt werden, bevor das automatische Backup laufen kann – z.B. über \"Jetzt synchronisieren\".';

  @override
  String get einstPapierkorbText =>
      'Löscht in den Papierkorb verschobene Fotos/Videos nach Ablauf der gewählten Frist endgültig – unwiderruflich, auch aus dem PIN-geschützten Papierkorb des gesperrten Ordners. Standardmäßig deaktiviert.';

  @override
  String get einstPapierkorbAus =>
      'Papierkorb-Ablauf ist standardmäßig ausgeschaltet.';

  @override
  String get einstResetText =>
      'Löscht unwiderruflich ALLE Fotos, Videos und die gesamte Datenbank dieser Bibliothek und beginnt danach mit einer leeren Bibliothek neu. Heruntergeladene KI-Modelle und Geodaten bleiben erhalten (kein erneuter Download nötig).';

  @override
  String get einstResetTitel => 'Datenbank zurücksetzen';

  @override
  String get einstResetKurz =>
      'Löscht alle Medien und Metadaten – nicht rückgängig zu machen.';

  @override
  String get einstResetKnopf => 'Zurücksetzen…';

  @override
  String get einstResetBestaetigenTitel => 'Datenbank wirklich zurücksetzen?';

  @override
  String get einstResetBestaetigenText =>
      'Löscht UNWIDERRUFLICH alle Fotos, Videos, Thumbnails und die gesamte Datenbank dieser Bibliothek (Alben, Personen, Tags, Orte, Favoriten, gesperrter Ordner, Papierkorb, gespeicherte Suchen, …). Heruntergeladene KI-Modelle und Geodaten bleiben erhalten. Erstelle vorher ein Backup, falls du dir nicht sicher bist – diese Aktion lässt sich NICHT rückgängig machen.';

  @override
  String get einstResetWort => 'ZURÜCKSETZEN';

  @override
  String get einstResetEndgueltig => 'Endgültig zurücksetzen';

  @override
  String get einstResetLaeuft => 'Lösche Bibliothek …';

  @override
  String get einstResetFertig =>
      'Die Bibliothek wurde vollständig gelöscht. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen, um mit einer leeren Bibliothek neu zu beginnen.';

  @override
  String get einstResetFehlgeschlagen => 'Zurücksetzen fehlgeschlagen';

  @override
  String get einstUeberTitel => 'Über diese App';

  @override
  String get einstKeineModelle => 'Keine KI-Modelle geladen';

  @override
  String einstModelleGeladen(int geladen, int gesamt) {
    return '$geladen von $gesamt KI-Modellen geladen';
  }

  @override
  String get einstModelleUnbenutzt =>
      'Die KI-Funktionen bleiben ohne sie unbenutzt.';

  @override
  String get einstAktualisierungHinweis =>
      'Die Prüfung fragt einmalig beim öffentlichen Veröffentlichungsverzeichnis nach der neuesten Versionsnummer. Es wird nichts über die Bibliothek übertragen, und es geschieht nur auf diesen Knopfdruck – nie von selbst.';

  @override
  String einstAktualisierungNeuer(String version) {
    return 'Neuere Fassung verfügbar: $version';
  }

  @override
  String get einstAktualisierungAktuell => 'Diese Fassung ist aktuell.';

  @override
  String einstAktualisierungFehler(String fehler) {
    return 'Prüfung fehlgeschlagen: $fehler';
  }

  @override
  String get einstVerschiebenFehlgeschlagen => 'Verschieben fehlgeschlagen';

  @override
  String get einstWechselnFehlgeschlagen => 'Wechseln fehlgeschlagen';

  @override
  String get einstNeustartTitel => 'Neustart erforderlich';

  @override
  String get einstUebersetzeBeschreibungTitel =>
      'Bildbeschreibungen in die Oberflächensprache übersetzen';

  @override
  String get einstUebersetzeBeschreibungText =>
      'Das Beschreibungsmodell liefert nur Englisch – es gibt kein vergleichbar kleines deutsches. Ist das Modell „Übersetzung Englisch → Deutsch“ geladen, wird jede neue Beschreibung zusätzlich übersetzt. Das englische Original bleibt erhalten, die Suche findet beide.';

  @override
  String get einstUebersetzeSucheTitel => 'Suche und Schlagwörter übersetzen';

  @override
  String get einstUebersetzeSucheText =>
      'Der Text-Teil des Bildsuche-Modells versteht nur Englisch, das Schlagwort-Vokabular ist aber deutsch. Eingeschaltet wandern Suchanfrage und Vokabelbegriffe vorher durch die Übersetzung. An 103 Fotos gemessen trifft das bei 33 von 56 Begriffen genauer, bei 19 schlechter – und es vergibt deutlich weniger Schlagwörter. Deshalb zum Ausprobieren, nicht als Vorgabe.';

  @override
  String get allgEntfernen => 'Entfernen';

  @override
  String get allgEinrichten => 'Einrichten';

  @override
  String get allgHerunterladen => 'Herunterladen';

  @override
  String get allgAktiv => 'Aktiv';

  @override
  String get einstAbschnittErscheinungsbild => 'Erscheinungsbild';

  @override
  String get einstAbschnittModelle => 'KI-Modelle (lokal & quelloffen)';

  @override
  String get einstAbschnittHintergrund => 'Hintergrundaufgaben';

  @override
  String get einstAbschnittVokabular => 'KI-Tagging-Vokabular';

  @override
  String get einstAbschnittStandortdaten =>
      'Standortdaten (lokal & quelloffen)';

  @override
  String get einstAbschnittGesperrterOrdner => 'Gesperrter Ordner';

  @override
  String get einstAbschnittManuellesBackup => 'Manuelles Cloud-Backup';

  @override
  String get einstAbschnittAutoBackup => 'Automatisches Backup';

  @override
  String get einstAbschnittPapierkorb => 'Papierkorb';

  @override
  String get einstAbschnittGefahrenzone => 'Gefahrenzone';

  @override
  String get einstDesign => 'Design';

  @override
  String get einstDesignHell => 'Hell';

  @override
  String get einstDesignDunkel => 'Dunkel';

  @override
  String get einstDesignSystem => 'System';

  @override
  String get einstUeberwachtNichtsNeues =>
      'Ordner eingerichtet – nichts Neues gefunden.';

  @override
  String get einstBibWechselnAktion => 'Wechseln';

  @override
  String get einstBibWechselnLaeuft => 'Wechsle Bibliothek …';

  @override
  String get einstBibAktiv => 'aktiv';

  @override
  String get einstBibImmerVorhanden => 'immer vorhanden';

  @override
  String get einstSpeicherort => 'Speicherort';

  @override
  String get einstSpeicherortVerschiebenLaeuft => 'Verschiebe Bibliothek …';

  @override
  String einstSpeicherortFortschritt(
      String kopiert, String gesamt, int dateien, int dateienGesamt) {
    return '$kopiert von $gesamt · $dateien von $dateienGesamt Dateien';
  }

  @override
  String get einstSpeicherbedarf => 'Speicherbedarf';

  @override
  String get belegung_originals => 'Originale';

  @override
  String get belegung_previews => 'Vorschauen';

  @override
  String get belegung_thumbnails => 'Miniaturen';

  @override
  String get belegung_developed => 'Entwickelte Fassungen';

  @override
  String get belegung_restored => 'Restaurierte Fassungen';

  @override
  String get belegung_trimmed => 'Zugeschnittene Videos';

  @override
  String get belegung_masks => 'Masken';

  @override
  String get belegung_faces => 'Gesichtsausschnitte';

  @override
  String get belegung_luts => 'Farbtabellen';

  @override
  String get belegung_trash => 'Papierkorb';

  @override
  String get belegung_datenbank => 'Datenbank';

  @override
  String get belegung_sonstiges => 'Sonstiges';

  @override
  String einstModellLaedt(String titel) {
    return 'Lade „$titel“ herunter …';
  }

  @override
  String get einstModellePruefenTitel => 'Modelle nachrechnen';

  @override
  String get einstModellePruefenText =>
      'Rechnet die Prüfsumme jeder installierten Modelldatei neu und vergleicht sie mit dem Katalog. Dauert wenige Sekunden. Findet Dateien, die sich nach dem Herunterladen verändert haben – beim Herunterladen selbst wird ohnehin geprüft.';

  @override
  String einstModellePruefenLaeuft(String datei) {
    return 'Rechnet nach: $datei';
  }

  @override
  String einstModellePruefenAlleGut(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Modelldateien geprüft, alle stimmen.',
      one: 'Eine Modelldatei geprüft, sie stimmt.',
    );
    return '$_temp0';
  }

  @override
  String get einstModellePruefenNichtsDa => 'Es ist kein Modell installiert.';

  @override
  String get einstModellePruefenBefundTitel => 'Auffällige Modelldateien';

  @override
  String get einstModellePruefenBefundText =>
      'Diese Dateien sind nicht die, die der Katalog nennt. Lösche das betroffene Modell und lade es neu – erst danach ist verlässlich, was es liefert.';

  @override
  String get einstModellZustandFehlt => 'fehlt';

  @override
  String get einstModellZustandZuKurz => 'falsche Länge';

  @override
  String get einstModellZustandWeichtAb => 'Inhalt weicht ab';

  @override
  String einstModelleBelegterPlatz(String groesse) {
    return 'Belegter Platz aller Modelle: $groesse';
  }

  @override
  String einstModellLizenzZeile(String lizenz) {
    return 'Lizenz: $lizenz';
  }

  @override
  String get einstGesichtserkennungAktiv => 'Gesichtserkennung aktiv';

  @override
  String get einstGesichtserkennungBeides =>
      'Erkennung + Wiedererkennungs-Embeddings aktiv';

  @override
  String get einstGesichtserkennungInaktiv =>
      'Inaktiv – YuNet-Modell oben herunterladen';

  @override
  String get einstGeoLaedt => 'Lade Standortdaten herunter …';

  @override
  String get einstPinEinrichten => 'PIN einrichten';

  @override
  String get einstGesperrterOrdner => 'Gesperrter Ordner';

  @override
  String get einstPinEingerichtet => 'PIN eingerichtet.';

  @override
  String get einstPinEntfernen => 'PIN entfernen';

  @override
  String get einstGesperrtAufloesenTitel => 'PIN-Schutz entfernen?';

  @override
  String get einstSitzungSperren => 'Sitzung jetzt sperren';

  @override
  String get einstPassphraseEinrichten => 'Passphrase einrichten';

  @override
  String get einstBackupPassphrase => 'Backup-Passphrase';

  @override
  String get einstBackupPassphraseEingeben => 'Backup-Passphrase eingeben';

  @override
  String get einstBackupSichertLaeuft => 'Sichere Bibliothek …';

  @override
  String get einstBackupWiederherstellenLaeuft =>
      'Stelle Bibliothek wieder her …';

  @override
  String get einstLetztesBackup => 'Letztes Backup';

  @override
  String einstBackupZusammenfassung(String datum, int anzahl, String ziel) {
    return '$datum – $anzahl Datei(en) nach $ziel';
  }

  @override
  String get einstJetztSichern => 'Jetzt sichern';

  @override
  String get einstWiederherstellen => 'Wiederherstellen';

  @override
  String get einstBackupPruefen => 'Backup prüfen';

  @override
  String get einstBackupPruefungLaeuft => 'Prüfe Wiederherstellbarkeit …';

  @override
  String einstBackupPruefungErfolgreich(int anzahl) {
    return '$anzahl Datei(en) sind vollständig wiederherstellbar.';
  }

  @override
  String einstBackupPruefungFehler(int gueltig, int fehlend, int beschaedigt) {
    return '$gueltig gültig, $fehlend fehlend, $beschaedigt beschädigt.';
  }

  @override
  String get einstZielordner => 'Zielordner';

  @override
  String get einstIntervall => 'Intervall';

  @override
  String get einstIntervallSechsStunden => 'Alle 6 Stunden';

  @override
  String get einstMengeJeLauf => 'Menge je Lauf';

  @override
  String get einstUnbegrenzt => 'Unbegrenzt';

  @override
  String get einstLetzterLauf => 'Letzter Lauf';

  @override
  String get einstJetztSynchronisieren => 'Jetzt synchronisieren';

  @override
  String get einstNachTagen => 'Nach';

  @override
  String einstTageDropdown(int tage) {
    return '$tage Tagen';
  }

  @override
  String get einstDatenbank => 'Datenbank';

  @override
  String einstDatenbankStand(int version) {
    return 'Stand $version';
  }

  @override
  String einstBauZeile(String bau, String system, String systemversion) {
    return 'Bau $bau · $system $systemversion';
  }

  @override
  String get einstLizenzen => 'Lizenzen';

  @override
  String get einstLizenzenText =>
      'Die Lizenzen der mitgelieferten Schriften und aller verwendeten Bibliotheken.';

  @override
  String get einstNachAktualisierungSuchen => 'Nach Aktualisierung suchen';

  @override
  String get modellYunetTitel => 'Gesichtserkennung – YuNet';

  @override
  String get modellYunetText =>
      'Erkennt Gesichter (Bounding Boxes) in Fotos. Leichtgewichtiges CNN, Teil von OpenCV Zoo.';

  @override
  String get modellYunetLizenz => 'Apache-2.0';

  @override
  String get modellSfaceTitel => 'Gesichts-Wiedererkennung – SFace';

  @override
  String get modellSfaceText =>
      'Berechnet ein Embedding pro Gesicht, um ähnliche/gleiche Gesichter beim manuellen Zuordnen leichter zu gruppieren. Teil von OpenCV Zoo.';

  @override
  String get modellSfaceLizenz => 'Apache-2.0';

  @override
  String get modellClipTitel => 'KI-Bildsuche – CLIP ViT-B/32';

  @override
  String einstAlleModelleLaden(int anzahl) {
    return 'Alle fehlenden laden ($anzahl)';
  }

  @override
  String get einstAlleModelleDa => 'Alle Modelle liegen bereit';

  @override
  String einstAlleModelleLaeuft(int nummer, int gesamt) {
    return 'Modell $nummer von $gesamt';
  }

  @override
  String get modellClipText =>
      'Ermöglicht die Suche nach Fotos in natürlicher Sprache (z.B. \"Sonnenuntergang am Meer\"). OpenAI-Originalgewichte, als separate Bild-/Text-Encoder-ONNX-Graphen exportiert.';

  @override
  String get modellClipLizenz => 'MIT (Gewichte: OpenAI CLIP, siehe Quelle)';

  @override
  String get modellSamTitel => 'KI-Objektmasken – SAM ViT-Base';

  @override
  String get modellSamText =>
      'Erlaubt gezielte Anpassungen nur auf einem ausgewählten Bereich (z.B. nur den Himmel aufhellen) im Entwickeln-Screen, statt jede Anpassung auf das ganze Bild anzuwenden. Nutzer setzt Vordergrund-/Hintergrund-Punkte, ein promptbares Segmentierungsmodell schlägt die passende Maske vor.';

  @override
  String get modellSamLizenz =>
      'Apache-2.0 (Gewichte: Meta Segment Anything, siehe Quelle)';

  @override
  String get modellCaptionTitel =>
      'KI-Bildbeschreibung – Florence-2 (Englisch)';

  @override
  String get modellCaptionText =>
      'Erzeugt automatisch eine Bildunterschrift pro Foto – für die Suche und als schnelle Übersicht. Liest dabei auch Schrift im Bild, etwa Ladenschilder oder Ortstafeln. Ausgabe ist Englisch; auf Wunsch übersetzt die App sie ins Deutsche (eigenes Modell). Ein vergleichbar kleines mehrsprachiges Modell gibt es nicht – die mehrsprachigen liegen im Gigabyte-Bereich.';

  @override
  String get modellCaptionLizenz =>
      'MIT (Basis: microsoft/Florence-2-base-ft, ONNX-Port: onnx-community)';

  @override
  String get modellOcecTitel => 'Geschlossene-Augen-Erkennung – OCEC';

  @override
  String get modellOcecText =>
      'Markiert Gesichter mit geschlossenen Augen in der Sichtung – schnelleres Aussortieren von Fotos mit Blinzlern in Porträt-/Gruppenserien.';

  @override
  String get modellOcecLizenz => 'MIT';

  @override
  String get modellEsrganTitel => 'KI-Restaurierung – Real-ESRGAN x4';

  @override
  String get modellEsrganText =>
      'Skaliert ein Foto um Faktor 4 hoch und entrauscht dabei. Läuft als Hintergrund-Warteschlange (Einstellungen/Entwickeln) und dauert je nach Fotogröße mehrere Minuten.';

  @override
  String get modellEsrganLizenz =>
      'BSD-3-Clause (Real-ESRGAN-Originalgewichte)';

  @override
  String get modellEnDeTitel => 'Übersetzung Englisch → Deutsch – OPUS-MT';

  @override
  String get modellEnDeText =>
      'Übersetzt die automatisch erzeugten Bildbeschreibungen ins Deutsche. Das Beschreibungsmodell selbst liefert nur Englisch; ohne diese Ergänzung muss man auf Englisch suchen, was man auf Deutsch sieht. Rund 100 MB.';

  @override
  String get modellEnDeLizenz =>
      'Apache-2.0 (Basis: Helsinki-NLP/opus-mt-en-de, ONNX-Port: Xenova)';

  @override
  String get modellDeEnTitel => 'Übersetzung Deutsch → Englisch – OPUS-MT';

  @override
  String get modellDeEnText =>
      'Übersetzt deutsche Suchanfragen und Schlagwörter, bevor sie an die KI-Bildsuche gehen – deren Text-Encoder versteht nur Englisch. Rund 100 MB.';

  @override
  String get modellDeEnLizenz =>
      'Apache-2.0 (Basis: Helsinki-NLP/opus-mt-de-en, ONNX-Port: Xenova)';

  @override
  String get werkzKeineUnbewerteten => 'Keine unbewerteten Fotos gefunden.';

  @override
  String get werkzKeinePassenden => 'Keine passenden Fotos gefunden.';

  @override
  String get werkzGesichterScannenTitel => 'Gesichter scannen';

  @override
  String get werkzScanneNeue => 'Scanne neue Fotos …';

  @override
  String get werkzScanneAlle => 'Scanne alle Fotos erneut …';

  @override
  String get werkzErstelleFehlende => 'Erstelle fehlende Vorschaubilder …';

  @override
  String get werkzErstelleAlle => 'Erstelle alle Vorschaubilder neu …';

  @override
  String get werkzRendereNeu => 'Rendere entwickelte Fotos neu …';

  @override
  String get werkzKeineEntwickelten => 'Keine entwickelten Fotos gefunden.';

  @override
  String get werkzPruefeLivePhotos => 'Prüfe auf Live-Photo-Paare …';

  @override
  String get werkzKeineUnverknuepften => 'Keine unverknüpften Fotos gefunden.';

  @override
  String get werkzBerechneEmbeddings => 'Berechne CLIP-Embeddings …';

  @override
  String get werkzAlleHabenEmbedding =>
      'Alle Fotos haben bereits ein Embedding.';

  @override
  String get werkzBerechneKiTags => 'Berechne KI-Tags …';

  @override
  String get werkzLeseOrte => 'Lese Orte aus Fotos ein …';

  @override
  String get werkzAlleHabenOrt =>
      'Alle Fotos haben bereits einen Ort (oder keine EXIF-GPS-Daten).';

  @override
  String get werkzLoeseOrteAuf => 'Löse Land/Bundesland/Stadt auf …';

  @override
  String get werkzAlleAufgeloest =>
      'Alle Fotos mit bekanntem Ort sind bereits aufgelöst.';

  @override
  String get werkzLeseKameradaten => 'Lese Kameradaten aus Fotos ein …';

  @override
  String get werkzAlleHabenKameradaten =>
      'Alle Fotos haben bereits Kameradaten (oder keine passenden EXIF-Daten).';

  @override
  String get werkzSchreibeXmp => 'Schreibe XMP-Sidecars …';

  @override
  String get werkzKeineFotosGesperrt =>
      'Keine Fotos gefunden (gesperrte Fotos werden übersprungen).';

  @override
  String get werkzErkenneText => 'Erkenne Text in Fotos …';

  @override
  String get werkzAlleTextDurchsucht =>
      'Alle Fotos wurden bereits nach Text durchsucht.';

  @override
  String get werkzErzeugeBeschreibungen => 'Erzeuge Bildbeschreibungen …';

  @override
  String get werkzAlleHabenBeschreibung =>
      'Alle Fotos haben bereits eine KI-Beschreibung.';

  @override
  String get werkzBerechneUnschaerfe => 'Berechne Unschärfe-Scores …';

  @override
  String get werkzAlleHabenUnschaerfe =>
      'Für alle Fotos wurde bereits ein Unschärfe-Score berechnet.';

  @override
  String get werkzAbschnittStatistik => 'Statistik';

  @override
  String get werkzAnalyseseiteTitel => 'Analyseseite';

  @override
  String get werkzAnalyseseiteText =>
      'Anzahl Fotos/Videos, Speicherplatz, Aufnahmen pro Jahr/Monat, häufigste Kameras';

  @override
  String get werkzAbschnittGesichtserkennung => 'Gesichtserkennung';

  @override
  String get werkzSchwelleLabel =>
      'Ähnlichkeitsschwelle für\n\"Ähnliche mit auswählen\"';

  @override
  String get werkzSchwelleErklaerung =>
      'Höhere Werte = strengerer Abgleich (weniger, aber sicherere Treffer). Gilt für den Button \"Ähnliche mit auswählen\" im Personen-Tab bei \"Unbenannte Gesichter\".';

  @override
  String get werkzAbschnittVorschau => 'Vorschaubilder';

  @override
  String get werkzHeicTitel => 'HEIC/HEIF & RAW-Unterstützung';

  @override
  String get werkzHeicAktiv =>
      'Aktiv – iPhone-Fotos (HEIC) und RAW-Dateien (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 & Co.) werden über die native macOS-Bildkonvertierung unterstützt.';

  @override
  String get werkzHeicInaktiv =>
      'Inaktiv – native Swift-Datei muss noch ins Xcode-Projekt eingebunden werden (siehe README). JPG/PNG/WebP/GIF/BMP/TIFF funktionieren auch ohne das.';

  @override
  String get werkzHeicWerkzeugeAktiv =>
      'Aktiv – iPhone-Fotos (HEIC) und RAW-Dateien (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 & Co.) werden über die mitgelieferten Werkzeuge unterstützt.';

  @override
  String werkzHeicWerkzeugeFehlen(String namen) {
    return 'Eingeschränkt – es fehlen: $namen. Die davon abhängigen Formate bleiben ohne Vorschau; JPG/PNG/WebP/GIF/BMP/TIFF funktionieren weiter.';
  }

  @override
  String get werkzNeuRendernTitel => 'Entwickelte Fotos neu rendern';

  @override
  String get werkzAbschnittOrte => 'Orte';

  @override
  String get werkzOrteAufloesenTitel => 'Land/Bundesland/Stadt auflösen';

  @override
  String get werkzAbschnittKamera => 'Kamera';

  @override
  String get werkzPresetsTitel => 'Kamera-Presets verwalten';

  @override
  String get werkzPresetsText =>
      'Fotos einer bestimmten Kamera automatisch beim Import einem Album/Tag zuordnen oder favorisieren – analog zu Digikams \"Kamera für den Import voreinstellen\".';

  @override
  String get werkzRegelnTitel => 'Automatisierungsregeln verwalten';

  @override
  String get werkzRegelnText =>
      'Fotos automatisch anhand von Ort, KI-Tag oder Aufnahmedatum einem Album/Tag zuordnen oder favorisieren – wie Kamera-Presets, nur für andere Bedingungen.';

  @override
  String get werkzAllesNachholenTitel => 'Alle Auswertungen jetzt nachholen';

  @override
  String get werkzAllesNachholenText =>
      'Startet alle rechenintensiven Schritte nacheinander im Hintergrund: Unschärfe, Gesichter, Texterkennung, Bildsuche, Schlagwörter und Bildbeschreibung. Jeder Schritt überspringt, was er schon hat – die App bleibt bedienbar.';

  @override
  String get werkzAbschnittBibliothek => 'Bibliothek';

  @override
  String get werkzSichtenTitel => 'Unbewertete Fotos sichten';

  @override
  String get werkzSichtenText =>
      'Öffnet alle noch unbewerteten Fotos/Videos im Vollbild-Sichtungs-Modus, zum schnellen Durchgehen und Bewerten.';

  @override
  String get werkzDuplikateTitel => 'Duplikate & ähnliche Fotos suchen';

  @override
  String get werkzDuplikateText => 'Auf Basis der CLIP-Bild-Embeddings';

  @override
  String get werkzStapelTitel => 'Serienbilder gruppieren';

  @override
  String get werkzStapelText =>
      'Findet zeitlich nahe, ähnliche Fotos (z.B. Serienbilder) und fasst sie auf Wunsch zu einem Stapel mit einem Titelbild zusammen.';

  @override
  String get werkzIntegritaetTitel => 'Bibliotheks-Integritätsprüfung';

  @override
  String get werkzIntegritaetText =>
      'Gleicht die Datenbank gegen die tatsächlichen Dateien auf der Platte ab: fehlende Dateien, verwaiste Dateien, optional Prüfsummen-Abweichungen.';

  @override
  String get werkzAbschnittInterop => 'Interoperabilität';

  @override
  String get werkzXmpSchreibenTitel => 'XMP-Sidecars schreiben';

  @override
  String get werkzXmpLesenTitel => 'XMP-Sidecars einlesen';

  @override
  String get werkzXmpLesenText =>
      'Liest vorhandene .xmp-Dateien (z.B. extern in Lightroom/darktable/digiKam bearbeitet) und zeigt Abweichungen zur Datenbank – Bewertung, Farbmarkierung, Beschreibung, Tags, Standort.';

  @override
  String sichtungHilfeleiste(int aktuell, int gesamt) {
    return '$aktuell / $gesamt   ·   0–5 Bewertung   ·   ⌫ Ablehnen   ·   ← → weiter';
  }

  @override
  String get ansicht360 => '360°-Ansicht';

  @override
  String personenZuordnenKnopf(int anzahl) {
    return '$anzahl zuordnen';
  }

  @override
  String get aufgStatus => 'Status';

  @override
  String get aufgBereit => 'Bereit';

  @override
  String get aufgLaeuft => 'Auswertung läuft im Hintergrund.';

  @override
  String get aufgJetztStarten => 'Jetzt starten';

  @override
  String get aufgWartend => 'Wartend';

  @override
  String get aufgWenigerGleichzeitig => 'Eine weniger';

  @override
  String get aufgMehrGleichzeitig => 'Eine mehr';

  @override
  String get aufgBetrifft => 'Betrifft';

  @override
  String aufgStufe(
      String stufe, int erledigt, int gesamt, int nummer, int stufenGesamt) {
    return '$stufe ($erledigt/$gesamt) – Stufe $nummer/$stufenGesamt';
  }

  @override
  String aufgModellNoetig(String modell, String wo) {
    return 'Dafür wird zuerst $modell benötigt ($wo).';
  }

  @override
  String get aufgYunetModell => 'das YuNet-Modell';

  @override
  String get aufgClipModell => 'das CLIP-Modell';

  @override
  String get aufgBeschreibungsmodell => 'das Bildbeschreibungs-Modell';

  @override
  String get aufgGeoDatensatz => 'der GeoNames-Datensatz';

  @override
  String get aufgWoModelle => 'Einstellungen → KI-Modelle';

  @override
  String get aufgWoStandortdaten => 'Einstellungen → Standortdaten';

  @override
  String get aufgGesichterText =>
      'Erkennt und ordnet Gesichter zu, sofern das YuNet-Modell installiert ist.';

  @override
  String get aufgVorschauText =>
      'Erzeugt Miniaturen und Vorschauen für Fotos und Videos. Bei einem Video entsteht dabei ein Standbild aus der ersten Sekunde – erst damit kann es überhaupt ausgewertet werden (Beschreibung, Schlagwörter, Gesichter, Text). Nach diesem Lauf lohnen die übrigen Aufgaben einen Durchgang.';

  @override
  String get aufgFehlende => 'Fehlende';

  @override
  String get aufgGesichtsschaerfeTitel => 'Gesichtsschärfe';

  @override
  String get aufgGesichtsschaerfeText =>
      'Misst für jedes erkannte Gesicht, wie scharf es ist – auf dem bereits gespeicherten Ausschnitt, ohne die Fotos erneut zu dekodieren. Beim Sichten warnt die App danach, wenn auch das schärfste Gesicht einer Aufnahme unscharf ist.';

  @override
  String get werkzBerechneGesichtsschaerfe => 'Gesichtsschärfe berechnen';

  @override
  String get aufgOcrTitel => 'Text erkennen (OCR)';

  @override
  String get aufgOcrText =>
      'Erkennt sichtbaren Text in Fotos, rein lokal über Apples Vision-Framework.';

  @override
  String get aufgBeschreibungenTitel => 'Bildbeschreibungen';

  @override
  String get aufgBeschreibungenText =>
      'Erzeugt eine kurze, englische KI-Bildunterschrift pro Foto.';

  @override
  String get aufgEmbeddingsTitel => 'CLIP-Embeddings';

  @override
  String get aufgEmbeddingsText =>
      'Grundlage für KI-Bildsuche und Duplikatsuche.';

  @override
  String get aufgKiTagsTitel => 'KI-Tags';

  @override
  String get aufgKiTagsText =>
      'Ordnet Fotos automatisch passende Tags aus dem Vokabular zu (auf CLIP-Basis).';

  @override
  String get aufgUnschaerfeTitel => 'Unschärfe';

  @override
  String get aufgUnschaerfeText =>
      'Ermöglicht den Suchfilter \"Nur unscharfe Fotos anzeigen\".';

  @override
  String get aufgOrteTitel => 'Orte einlesen';

  @override
  String get aufgOrteText =>
      'Liest EXIF-GPS-Daten aus Fotos nachträglich ein. Die Zahl ist die der Fotos ohne Ort – wie viele davon einen in der Datei tragen, weiss erst der Durchgang.';

  @override
  String get aufgOrteAufloesenText =>
      'Ordnet dem GPS-Ort eines Fotos Land, Bundesland/Provinz und Stadt zu.';

  @override
  String get aufgKameraTitel => 'Kameradaten einlesen';

  @override
  String get aufgKameraText =>
      'Liest Kamera, Objektiv, Brennweite, Blende, ISO und Belichtungszeit aus den Metadaten ein – bei Fotos aus EXIF, bei Videos aus dem Container. Die Zahl ist die der Aufnahmen ohne Kameraangabe; was gar keine Metadaten trägt, bleibt darunter.';

  @override
  String get aufgDateiartTitel => 'Dateiarten prüfen';

  @override
  String get aufgDateiartText =>
      'Manche Standbilder kommen unter einem Videonamen an – als Video geführt fallen sie aus jeder Auswertung heraus, bekommen kein Vorschaubild und keinen Ort. Der Lauf sieht in die Bytes und berichtigt die Art. Danach lohnt ein Durchgang der übrigen Aufgaben.';

  @override
  String get werkzPruefeDateiarten => 'Prüfe Dateiarten …';

  @override
  String get werkzAlleArtenStimmen =>
      'Alle Aufnahmen sind richtig eingeordnet.';

  @override
  String get aufgLivePhotoTitel => 'Live-Photo-Paare prüfen';

  @override
  String get aufgLivePhotoText =>
      'Verknüpft HEIC/JPG-Standbilder mit gleichnamigen MOV-Videos. Die Zahl ist die der Fotos ohne Partner – die allermeisten haben keinen und bekommen auch keinen.';

  @override
  String get aufgRendernText =>
      'Rendert Fotos mit gespeicherten Entwicklungs-Anpassungen unverändert neu.';

  @override
  String get aufgXmpText =>
      'Legt für jedes Foto eine .xmp-Datei für Lightroom/darktable/digiKam daneben ab.';

  @override
  String get auswAufheben => 'Auswahl aufheben';

  @override
  String auswAnzahl(int anzahl) {
    return '$anzahl ausgewählt';
  }

  @override
  String get auswFavorisieren => 'Favorisieren';

  @override
  String get auswZuAlbum => 'Zu Album hinzufügen';

  @override
  String get auswTagHinzufuegen => 'Tag hinzufügen';

  @override
  String get auswBewertungSetzen => 'Bewertung setzen';

  @override
  String get auswFarbeSetzen => 'Farbmarkierung setzen';

  @override
  String get auswMetadaten => 'Metadaten bearbeiten';

  @override
  String get auswEntwicklungUebertragen => 'Kopierte Entwicklung übertragen';

  @override
  String get auswExportieren => 'Exportieren';

  @override
  String get allgLoeschen => 'Löschen';

  @override
  String get allgHinzufuegen => 'Hinzufügen';

  @override
  String get allgWaehlen => 'Wählen';

  @override
  String auswBewertungTitel(int anzahl) {
    return 'Bewertung für $anzahl Foto(s)';
  }

  @override
  String get auswKeineBewertung => 'Keine Bewertung';

  @override
  String auswFarbeTitel(int anzahl) {
    return 'Farbmarkierung für $anzahl Foto(s)';
  }

  @override
  String get auswKeineFarbe => 'Keine Farbe';

  @override
  String auswMetadatenTitel(int anzahl) {
    return 'Metadaten für $anzahl Foto(s) bearbeiten';
  }

  @override
  String get auswBeschreibungFeld => 'Beschreibung (überschreibt bestehende)';

  @override
  String get auswDatumUnveraendert => 'Datum unverändert lassen';

  @override
  String auswDatumGesetzt(String datum) {
    return 'Datum: $datum';
  }

  @override
  String get auswOrtHinweis => 'Ort (unverändert lassen: nicht antippen)';

  @override
  String get auswOrtEntfernen => 'Ort entfernen';

  @override
  String auswTagTitel(int anzahl) {
    return 'Tag zu $anzahl Foto(s) hinzufügen';
  }

  @override
  String get auswTagFeld => 'Tag';

  @override
  String auswExportTitel(int anzahl) {
    return '$anzahl Foto(s) exportieren';
  }

  @override
  String get auswVorgabeAnwenden => 'Vorgabe anwenden';

  @override
  String auswVorgabeAnwendenTitel(int anzahl) {
    return 'Vorgabe auf $anzahl Foto(s) anwenden';
  }

  @override
  String auswUebertragenTitel(int anzahl) {
    return 'Entwicklung auf $anzahl Foto(s) übertragen?';
  }

  @override
  String get auswUebertragenText =>
      'Die kopierten Werte für Belichtung, Weissabgleich, Kontrast und Schatten werden übernommen; jedes Foto wird dabei neu gerendert.\n\nMasken werden nicht übertragen. Der bisherige Stand jedes Fotos bleibt in dessen Verlauf erhalten.';

  @override
  String get auswUebertragen => 'Übertragen';

  @override
  String get auswUebertrageLaeuft => 'Übertrage Entwicklung …';

  @override
  String get auswKeineGeeigneten =>
      'Keine geeigneten Fotos – gesperrte Fotos und Videos bleiben aussen vor.';

  @override
  String auswZielordner(int anzahl) {
    return 'Zielordner für $anzahl Foto(s) wählen';
  }

  @override
  String auswExportiereLaeuft(int erledigt, int gesamt) {
    return 'Exportiere … ($erledigt / $gesamt)';
  }

  @override
  String auswExportFertig(int erledigt, int gesamt, String ziel) {
    return '$erledigt von $gesamt Foto(s) exportiert nach $ziel';
  }

  @override
  String get exportOriginal => 'Original';

  @override
  String get exportGross => 'Gross – 4096 px';

  @override
  String get exportWeb => 'Web – 2048 px';

  @override
  String get exportEmail => 'E-Mail – 1024 px';

  @override
  String get exportUnveraendert => 'Datei unverändert, mit XMP-Datei daneben';

  @override
  String exportJpegKante(int kante) {
    return 'Als JPEG, lange Kante höchstens $kante px';
  }

  @override
  String get allgUebernehmen => 'Übernehmen';

  @override
  String get allgAlle => 'Alle';

  @override
  String get suchoptTagsWaehlen => 'Tags auswählen';

  @override
  String get suchoptTagsFiltern => 'Tags filtern …';

  @override
  String get suchoptKeineTags => 'Keine Tags gefunden.';

  @override
  String get suchoptTitel => 'Suchoptionen';

  @override
  String get suchoptKeineTreffer =>
      'Keine Fotos gefunden – diese Filterkombination liefert 0 Treffer.';

  @override
  String get suchoptAllesLeeren => 'Alles leeren';

  @override
  String get suchoptSuchen => 'Suche';

  @override
  String get suchoptPersonenFiltern => 'Personen filtern';

  @override
  String get suchoptKeinePersonenBenannt => 'Noch keine Personen benannt.';

  @override
  String get suchoptKeinePersonenGefunden => 'Keine Personen gefunden.';

  @override
  String get suchoptTypTitel => 'Suche nach Typ';

  @override
  String get suchoptTypKontext => 'Kontext';

  @override
  String get suchoptTypDateiname => 'Dateiname';

  @override
  String get suchoptTypBeschreibung => 'Beschreibung';

  @override
  String get suchoptTypOcr => 'Text im Foto (OCR)';

  @override
  String get suchoptTypCaption => 'KI-Beschreibung (Englisch)';

  @override
  String get suchoptNachKontext => 'Suche nach Kontext';

  @override
  String get suchoptNachDateiname => 'Suche nach Dateiname';

  @override
  String get suchoptNachBeschreibung => 'Suche nach Beschreibung';

  @override
  String get suchoptNachOcr => 'Suche nach erkanntem Text im Foto';

  @override
  String get suchoptNachCaption => 'Suche nach KI-Beschreibung (Englisch)';

  @override
  String get suchoptHintKontext =>
      'z.B. \"Sonnenaufgang am Strand\", \"Hund im Schnee\" …';

  @override
  String get suchoptHintDateiname => 'Dateiname …';

  @override
  String get suchoptHintBeschreibung => 'Beschreibung …';

  @override
  String get suchoptHintOcr => 'Text im Foto …';

  @override
  String get suchoptHintCaption => 'z.B. \"dog\", \"sunset\" (Englisch) …';

  @override
  String get suchoptClipFehlt =>
      'KI-Bildsuche nicht verfügbar – Modell fehlt (siehe Einstellungen → KI-Modelle).';

  @override
  String get suchoptCaptionFehlt =>
      'KI-Bildbeschreibung nicht verfügbar – Modell fehlt (siehe Einstellungen → KI-Modelle).';

  @override
  String get suchoptTagsTitel => 'Tags';

  @override
  String get suchoptTagsHint => 'Suche nach Tags …';

  @override
  String get suchoptOhneTag => 'Ohne Tag';

  @override
  String get suchoptMindestbewertung => 'Mindestbewertung';

  @override
  String get suchoptFarbmarkierung => 'Farbmarkierung';

  @override
  String get suchoptDateiformat => 'Dateiformat';

  @override
  String get suchoptNurRaw => 'Nur RAW';

  @override
  String get farbeRot => 'Rot';

  @override
  String get farbeGelb => 'Gelb';

  @override
  String get farbeGruen => 'Grün';

  @override
  String get farbeBlau => 'Blau';

  @override
  String get farbeLila => 'Lila';

  @override
  String get suchoptAufnahmewerte => 'Aufnahmewerte';

  @override
  String get suchoptIsoVon => 'ISO von';

  @override
  String get suchoptIsoBis => 'ISO bis';

  @override
  String get suchoptBlendeVon => 'Blende von (f/…)';

  @override
  String get suchoptBlendeBis => 'Blende bis (f/…)';

  @override
  String get suchoptBrennweiteVon => 'Brennweite von (mm)';

  @override
  String get suchoptBrennweiteBis => 'Brennweite bis (mm)';

  @override
  String get suchoptNurUnscharfe => 'Nur unscharfe Fotos anzeigen';

  @override
  String get suchoptMarke => 'Marke';

  @override
  String get suchoptModell => 'Modell';

  @override
  String get suchoptObjektiv => 'Objektiv';

  @override
  String get suchoptOrtTitel => 'Ort';

  @override
  String get suchoptLand => 'Land';

  @override
  String get suchoptBundesland => 'Bundesland';

  @override
  String get suchoptStadt => 'Stadt';

  @override
  String get suchoptGeoFehlt =>
      'Noch keine Orte aufgelöst – GeoNames-Datensatz herunterladen und Fotos auflösen (siehe Einstellungen → Standortdaten, Werkzeuge → Orte).';

  @override
  String get suchoptAnfangsdatum => 'Anfangsdatum';

  @override
  String get suchoptEnddatum => 'Enddatum';

  @override
  String get suchoptDatumEntfernen => 'Datum entfernen';

  @override
  String get suchoptDatumPlatzhalter => 'tt.mm.jjjj';

  @override
  String get suchoptMedientyp => 'Medientyp';

  @override
  String get suchoptBild => 'Bild';

  @override
  String get suchoptVideo => 'Video';

  @override
  String get suchoptAnzeigeoptionen => 'Anzeigeoptionen';

  @override
  String get suchoptInKeinemAlbum => 'In keinem Album';

  @override
  String get suchoptFavoriten => 'Favoriten';

  @override
  String get entwTitel => 'Entwickeln';

  @override
  String get entwVerlaufSitzung => 'Diese Sitzung';

  @override
  String get entwVerlaufGespeichert => 'Gespeichert';

  @override
  String get entwVerlaufAusgangsstand => 'Stand beim Öffnen';

  @override
  String get entwVerlaufOhneAenderung => 'Ohne Änderung';

  @override
  String get entwVerlaufJetzt => 'Aktueller Stand';

  @override
  String get entwWerkzBelichtung => 'Belichtung';

  @override
  String get entwWerkzWeissabgleich => 'Weissabgleich';

  @override
  String get entwWerkzTemperatur => 'Temperatur';

  @override
  String get entwWerkzTint => 'Farbstich';

  @override
  String get entwWerkzKontrast => 'Kontrast';

  @override
  String get entwWerkzLichter => 'Lichter';

  @override
  String get entwWerkzSchatten => 'Schatten';

  @override
  String get entwWerkzSchaerfe => 'Schärfe';

  @override
  String get entwWerkzRauschen => 'Rauschunterdrückung';

  @override
  String get entwWerkzKlarheit => 'Klarheit';

  @override
  String get entwWerkzVignettierung => 'Vignettierung';

  @override
  String get entwWerkzKurve => 'Tonwertkurve';

  @override
  String get entwWerkzFarbmischer => 'Farbmischer';

  @override
  String get entwWerkzFarbtabelle => 'Farbtabelle';

  @override
  String get entwWerkzObjektiv => 'Objektivkorrektur';

  @override
  String get entwKeinVerlauf =>
      'Noch kein Verlauf vorhanden – ein Eintrag entsteht, sobald du nach einer ersten Anpassung erneut speicherst.';

  @override
  String get entwKopiert =>
      'Einstellungen kopiert. Sie lassen sich jetzt auf andere Fotos übertragen – auch ohne dieses hier zu speichern.';

  @override
  String get entwEingesetzt =>
      'Kopierte Einstellungen eingesetzt – noch nicht gespeichert.';

  @override
  String get entwSpeichernFehlgeschlagen =>
      'Speichern fehlgeschlagen: Bild konnte nicht gerendert werden.';

  @override
  String get entwRestaurierungLaeuft => 'KI-Restaurierung';

  @override
  String get entwRestaurierungEingereiht =>
      'Zur Warteschlange für KI-Restaurierung hinzugefügt.';

  @override
  String entwRestaurierungFehler(String fehler) {
    return 'Konnte nicht zur Warteschlange hinzugefügt werden: $fehler';
  }

  @override
  String entwKiAuswahlLadefehler(String fehler) {
    return 'KI-Auswahl konnte nicht geladen werden: $fehler';
  }

  @override
  String get entwVorschauNichtDekodiert =>
      'Vorschaubild konnte nicht für die Maskierung dekodiert werden.';

  @override
  String entwKiAuswahlFehler(String fehler) {
    return 'KI-Auswahl fehlgeschlagen: $fehler';
  }

  @override
  String entwMaskeNummer(int nummer) {
    return 'Maske $nummer';
  }

  @override
  String get entwAufloesungUnbekannt =>
      'Bildauflösung unbekannt – Maske kann nicht gespeichert werden.';

  @override
  String get entwRestaurierungEntfernen => 'KI-Restaurierung entfernen';

  @override
  String get entwRestaurierungModellFehlt =>
      'Benötigt das Restaurierungs-Modell (Einstellungen → KI-Modelle)';

  @override
  String get entwRestaurierungAnwenden =>
      'KI-Restaurierung anwenden (läuft im Hintergrund, dauert mehrere Minuten)';

  @override
  String get entwMaskeHinzufuegen => 'Maske hinzufügen';

  @override
  String get entwVerlauf => 'Verlauf';

  @override
  String get entwEinstellungenKopieren =>
      'Einstellungen kopieren (zum Übertragen auf andere Fotos)';

  @override
  String get entwEinstellungenEinsetzen =>
      'Kopierte Einstellungen in die Regler setzen';

  @override
  String get entwOriginal => 'Original';

  @override
  String get entwVergleichen => 'Zum Vergleichen gedrückt halten';

  @override
  String get entwVorher => 'Vorher';

  @override
  String get entwNachher => 'Nachher';

  @override
  String get entwTrennstrich =>
      'Vorher/Nachher nebeneinander (Strich zum Ziehen)';

  @override
  String get entwTrennstrichWartet =>
      'Das unbearbeitete Bild wird noch berechnet – einen Moment.';

  @override
  String get entwMaskeErstellen => 'Maske erstellen';

  @override
  String get entwFormKi => 'KI';

  @override
  String get entwFormKiFehlt =>
      'Benötigt das Segmentierungs-Modell (Einstellungen → KI-Modelle)';

  @override
  String get entwFormPinsel => 'Pinsel';

  @override
  String get entwFormEllipse => 'Ellipse';

  @override
  String get entwFormVerlauf => 'Verlauf';

  @override
  String get allgFertig => 'Fertig';

  @override
  String get entwKiHinweis =>
      'Auf den Bereich tippen, den du anpassen möchtest. Mehrere Tipps verfeinern die Auswahl.';

  @override
  String get entwPunktHinzufuegen => 'Hinzufügen';

  @override
  String get entwPunktEntfernen => 'Entfernen';

  @override
  String get entwLetztenPunktEntfernen => 'Letzten Punkt entfernen';

  @override
  String get entwPinselHinweis =>
      'Über den Bereich ziehen, den du anpassen möchtest.';

  @override
  String get entwNeuZeichnen => 'Neu zeichnen';

  @override
  String get entwEllipseHinweis =>
      'Über den Bereich ziehen, um die Ellipse aufzuziehen.';

  @override
  String get entwVerlaufHinweis =>
      'Von einer Kante zur anderen ziehen, um den Verlauf festzulegen.';

  @override
  String get entwAnpassungFuer => 'Anpassung für';

  @override
  String get entwGanzesBild => 'Ganzes Bild';

  @override
  String get entwFormBearbeiten => 'Form bearbeiten';

  @override
  String get entwAutoWeissabgleich => 'Automatischer Weißabgleich';

  @override
  String get entwObjektivkorrektur => 'Objektivkorrektur';

  @override
  String get entwObjektivkorrekturHinweis =>
      'Nur wirksam für RAW-Fotos, deren Kamera/Objektiv unterstützt wird.';

  @override
  String get entwMaskenHinweis =>
      'Diese Anpassungen wirken nur innerhalb der ausgewählten Maske.';

  @override
  String get entwBelichtung => 'Belichtung';

  @override
  String get entwTemperatur => 'Temperatur (K)';

  @override
  String get entwTint => 'Tint';

  @override
  String get entwKontrast => 'Kontrast';

  @override
  String get entwBeschneidungWarnung =>
      'Beschneidung anzeigen (Rot = ausgefressen, Blau = abgesoffen)';

  @override
  String get entwBeschneidungMitMasken =>
      'Beschneidung anzeigen geht nicht, solange Masken im Bild liegen – die Markierung entsteht in der Shader-Vorschau, und die kann Masken nicht darstellen.';

  @override
  String get entwBeschneidungVorschauHinweis =>
      'Beschneidungs-Vorschau – Schärfe, Rauschen, Klarheit und Vignette zeigt sie nicht';

  @override
  String get entwVorgabeSichern => 'Als Vorgabe sichern';

  @override
  String get entwVorgabeAnwenden => 'Vorgabe anwenden';

  @override
  String get entwVorgabeWaehlen => 'Vorgabe wählen';

  @override
  String get entwVorgabeName => 'Name der Vorgabe';

  @override
  String get entwKeineVorgaben => 'Es gibt noch keine Entwicklungs-Vorgabe.';

  @override
  String entwVorgabeGesichert(String name) {
    return 'Vorgabe „$name“ gesichert';
  }

  @override
  String entwVorgabeNameVergeben(String name) {
    return 'Es gibt bereits eine Vorgabe namens „$name“.';
  }

  @override
  String get entwAutomatisch => 'Belichtung und Kontrast automatisch';

  @override
  String get entwAutomatikOhneHistogramm =>
      'Noch kein Histogramm – einen Moment.';

  @override
  String get entwTiefenmaske => 'Maske aus der Tiefenkarte';

  @override
  String get entwTiefenmaskeName => 'Tiefe';

  @override
  String get entwTiefenKeine =>
      'Dieses Foto bringt keine Tiefenkarte mit. Nur Porträtaufnahmen neuerer iPhones tragen eine.';

  @override
  String get entwTiefenNichtLesbar =>
      'Die Tiefenkarte liess sich nicht auswerten.';

  @override
  String get entwTiefenNurMacos =>
      'Dieses Foto könnte eine Tiefenkarte mitbringen, aber das installierte Bildwerkzeug kann ihre Hilfsebene nicht lesen. Aktualisiere die mitgelieferte libheif-Werkzeugschicht.';

  @override
  String get entwLichter => 'Lichter';

  @override
  String get entwSchatten => 'Schatten';

  @override
  String get entwSchaerfe => 'Schärfe';

  @override
  String get entwRauschunterdrueckung => 'Rauschunterdrückung';

  @override
  String get entwStrichbreite => 'Strichbreite';

  @override
  String get entwRotation => 'Rotation (°)';

  @override
  String get entwWeichzeichnung => 'Weichzeichnung';

  @override
  String get entwGesperrt =>
      'Entwickeln ist für Fotos im gesperrten Ordner nicht verfügbar.';

  @override
  String get entwVorschauFehlt =>
      'Vorschau konnte nicht erzeugt werden – native Bildkonvertierung nicht verfügbar?';

  @override
  String get entwModellLaedt => 'Modell für die KI-Auswahl wird geladen …';

  @override
  String get entwBildWirdVorbereitet =>
      'Bild wird für die Maskierung vorbereitet …';

  @override
  String get allgOder => '— oder —';

  @override
  String get albumBestehendes => 'Bestehendes Album';

  @override
  String get albumNeuAnlegen => 'Neues Album anlegen';

  @override
  String get personZuordnenTitel => 'Person zuordnen';

  @override
  String personAktuell(String name) {
    return 'Aktuell: $name';
  }

  @override
  String get personZuordnenAktion => 'Zuordnen';

  @override
  String get bestaetigEndgueltigLoeschen => 'Endgültig löschen';

  @override
  String get bestaetigTippeVor => 'Tippe zur Bestätigung ';

  @override
  String get bestaetigTippeNach => ' ein:';

  @override
  String fortschrittFehlgeschlagen(String fehler) {
    return 'Fehlgeschlagen: $fehler';
  }

  @override
  String sterneStern(int nummer) {
    return 'Stern $nummer von 5';
  }

  @override
  String sterneSternVoll(int nummer) {
    return 'Stern $nummer von 5, ausgefüllt';
  }

  @override
  String sterneSetzen(int nummer) {
    return 'Bewertung: $nummer von 5 Sternen setzen';
  }

  @override
  String sterneBewertungAnzeige(int nummer) {
    return 'Bewertung $nummer von 5 Sternen';
  }

  @override
  String get scrubberTooltip => 'Schnellnavigation zum Datum';

  @override
  String get farbeViolett => 'Violett';

  @override
  String farbeAusgewaehlt(String farbe) {
    return '$farbe, ausgewählt';
  }

  @override
  String farbeSetzen(String farbe) {
    return 'Farbmarkierung $farbe setzen';
  }

  @override
  String get histogrammTitel => 'Histogramm';

  @override
  String get histogrammKeineVorschau => 'Noch keine Vorschau';

  @override
  String get histogrammHelligkeit => 'Helligkeit';

  @override
  String get livePhotoHalten => 'Gedrückt halten zum Abspielen';

  @override
  String get metaBelichtungBeispiel => 'z.B. 1/125 oder 0.5';

  @override
  String get karteTippenFuerOrt => 'Tippen, um einen Ort festzulegen';

  @override
  String get rasterFotoNichtGefunden => 'Foto nicht in der Timeline gefunden.';

  @override
  String get kameraImportTitel => 'Von Kamera/SD-Karte importieren';

  @override
  String get kameraKeinDatentraeger =>
      'Kein Datenträger mit Fotos/Videos gefunden. Kamera oder SD-Karte per USB einstecken – die Liste aktualisiert sich automatisch, sobald sie erkannt wird.';

  @override
  String get mischerTitel => 'Farbmischer';

  @override
  String get mischerFarbton => 'Farbton';

  @override
  String get mischerSaettigung => 'Sättigung';

  @override
  String get mischerHelligkeit => 'Helligkeit';

  @override
  String get mischerHinweis =>
      'Wirkt nur auf farbige Bildbereiche – Graustufen bleiben unberührt.';

  @override
  String get bandRot => 'Rot';

  @override
  String get bandOrange => 'Orange';

  @override
  String get bandGelb => 'Gelb';

  @override
  String get bandGruen => 'Grün';

  @override
  String get bandAqua => 'Aqua';

  @override
  String get bandBlau => 'Blau';

  @override
  String get bandViolett => 'Violett';

  @override
  String get bandMagenta => 'Magenta';

  @override
  String get kurveTitel => 'Tonwertkurve';

  @override
  String get kurveHinweis =>
      'Ziehen setzt oder verschiebt einen Punkt, langes Drücken entfernt ihn.';

  @override
  String get pinFeld => 'PIN';

  @override
  String get pinFestlegenTitel => 'PIN festlegen';

  @override
  String get pinNeuFeld => 'Neuer PIN (8-10 Ziffern)';

  @override
  String get pinWiederholen => 'PIN wiederholen';

  @override
  String get pinWarnung =>
      'Wichtig: Fotos im gesperrten Ordner werden echt verschlüsselt (AES-256). Ohne diesen PIN gibt es KEINE Möglichkeit, sie wiederherzustellen – auch nicht durch Zurücksetzen der App.';

  @override
  String get pinZiffernFehler => 'PIN muss aus 8-10 Ziffern bestehen.';

  @override
  String get pinUngleich => 'PINs stimmen nicht überein.';

  @override
  String get allgFestlegen => 'Festlegen';

  @override
  String get pinEingebenTitel => 'PIN eingeben';

  @override
  String get pinFalsch => 'Falscher PIN.';

  @override
  String get passphraseFeld => 'Passphrase';

  @override
  String get passphraseFestlegenTitel => 'Backup-Passphrase festlegen';

  @override
  String get passphraseNeuFeld => 'Neue Passphrase (mind. 8 Zeichen)';

  @override
  String get passphraseWiederholen => 'Passphrase wiederholen';

  @override
  String get passphraseWarnung =>
      'Wichtig: Backups werden echt verschlüsselt (AES-256). Ohne diese Passphrase gibt es KEINE Möglichkeit, sie wiederherzustellen – auch nicht auf einem anderen Rechner. Am besten zusätzlich an einem sicheren Ort notieren.';

  @override
  String get passphraseUngleich => 'Passphrasen stimmen nicht überein.';

  @override
  String get passphraseFalsch => 'Falsche Passphrase.';

  @override
  String get allgFoto => 'Foto';

  @override
  String get allgVideo => 'Video';

  @override
  String get kachelFavorisiert => 'favorisiert';

  @override
  String kachelBeschreibung(String typ, String name, String datum) {
    return '$typ $name, $datum';
  }

  @override
  String albumFotosLoeschenTitel(int anzahl) {
    return '$anzahl Foto(s) löschen?';
  }

  @override
  String get albumFotosLoeschenText =>
      'Diese Fotos werden aus dem Album entfernt und in den Papierkorb verschoben.';

  @override
  String albumZielordner(String album) {
    return 'Zielordner für \"$album\" wählen';
  }

  @override
  String get albumExportieren => 'Album exportieren';

  @override
  String get albumLeer => 'Dieses Album enthält noch keine Fotos.';

  @override
  String get albumFotosHinzufuegen => 'Fotos hinzufügen';

  @override
  String get albumTitelbildSetzen => 'Als Titelbild';

  @override
  String get albumTitelbildGesetzt => 'Titelbild gesetzt';

  @override
  String albumFotosWaehlenTitel(String album) {
    return 'Fotos für „$album“';
  }

  @override
  String get regelLoeschenTitel => 'Regel löschen?';

  @override
  String regelLoeschenText(String name) {
    return 'Die Regel \"$name\" wirklich löschen? Bereits angewendete Aktionen bleiben erhalten.';
  }

  @override
  String get regelOrtUnvollstaendig => 'Ort: unvollständig konfiguriert';

  @override
  String get regelDatumUnvollstaendig =>
      'Datumsbereich: unvollständig konfiguriert';

  @override
  String get regelTitel => 'Automatisierungsregeln';

  @override
  String get regelNeu => 'Neue Regel';

  @override
  String get regelLeer =>
      'Noch keine Automatisierungsregeln.\n\nLege eine Regel an, um Fotos automatisch anhand von Ort, KI-Tag oder Aufnahmedatum einem Album/Tag zuzuordnen oder zu favorisieren – wie Kamera-Presets, nur für andere Bedingungen.';

  @override
  String get allgBearbeiten => 'Bearbeiten';

  @override
  String get regelNameNoetig => 'Ein Name für die Regel ist erforderlich.';

  @override
  String get regelKoordinatenUngueltig =>
      'Breiten- und Längengrad müssen gültige Zahlen sein.';

  @override
  String get regelBreitengradBereich =>
      'Der Breitengrad muss zwischen -90 und 90 liegen.';

  @override
  String get regelLaengengradBereich =>
      'Der Längengrad muss zwischen -180 und 180 liegen.';

  @override
  String get regelTagWaehlen => 'Bitte einen KI-Tag-Begriff wählen.';

  @override
  String get regelDatumWaehlen => 'Bitte Start- und Enddatum wählen.';

  @override
  String get regelDatumReihenfolge =>
      'Das Startdatum muss vor dem Enddatum liegen.';

  @override
  String get regelBreitengrad => 'Breitengrad';

  @override
  String get regelLaengengrad => 'Längengrad';

  @override
  String get regelKeinVokabular =>
      'Kein KI-Tag-Vokabular vorhanden (Einstellungen → KI-Tagging-Vokabular).';

  @override
  String get regelTagBegriff => 'KI-Tag-Begriff';

  @override
  String get regelNameFeld => 'Name (z.B. \"Urlaub Italien\")';

  @override
  String get regelBedingung => 'Bedingung';

  @override
  String get presetZielalbum => 'Zielalbum (optional)';

  @override
  String get presetKeinAlbum => 'Kein Album';

  @override
  String get presetNeuesAlbum => 'oder: neues Album anlegen';

  @override
  String get presetFavorisieren => 'Automatisch favorisieren';

  @override
  String get presetTagsWaehlenPlatzhalter => 'Tags auswählen …';

  @override
  String get presetKeineTags => 'Keine Tags vorhanden.';

  @override
  String get presetLoeschenTitel => 'Preset löschen?';

  @override
  String presetLoeschenText(String kamera) {
    return 'Das Kamera-Preset für \"$kamera\" wirklich löschen? Bereits importierte Fotos bleiben unverändert.';
  }

  @override
  String get presetTitel => 'Kamera-Presets';

  @override
  String get presetNeu => 'Neues Preset';

  @override
  String get presetLeer =>
      'Noch keine Kamera-Presets.\n\nLege ein Preset für eine bestimmte Kamera an, um künftig importierte Fotos dieser Kamera automatisch einem Album/Tag zuzuordnen – auch schon bevor das erste Foto dieser Kamera importiert wurde.';

  @override
  String get presetHerstellerModellNoetig =>
      'Hersteller und Modell sind beide erforderlich.';

  @override
  String get presetBekannteKamera => 'Bekannte Kamera übernehmen (optional)';

  @override
  String get presetHersteller => 'Hersteller (z.B. Canon, Apple)';

  @override
  String get presetModell => 'Modell (z.B. EOS R5, iPhone 15 Pro)';

  @override
  String get allgClipNoetigKurz =>
      'Benötigt das CLIP-Modell (Einstellungen → KI-Modelle).';

  @override
  String get duplNichtsLoeschbar =>
      'Nichts automatisch löschbar: In allen Gruppen sind mehrere Fotos favorisiert oder bewertet – die bitte von Hand durchsehen.';

  @override
  String get duplNichtsZuLoeschen => 'Nichts zu löschen.';

  @override
  String get duplPapierkorbTitel => 'Kopien in den Papierkorb?';

  @override
  String duplPapierkorbAnzahl(int fotos, int gruppen) {
    return '$fotos Foto(s) aus $gruppen Gruppe(n) werden in den Papierkorb verschoben.';
  }

  @override
  String get duplBehaltenRegel =>
      'Behalten wird je Gruppe: Favorit, sonst höchste Bewertung, sonst das schärfste, sonst das mit der höchsten Auflösung.';

  @override
  String duplUebersprungen(int anzahl) {
    return '$anzahl Gruppe(n) bleiben unangetastet, weil dort mehrere Fotos favorisiert oder bewertet sind.';
  }

  @override
  String get duplRueckgaengig =>
      'Rückgängig: über den Papierkorb wiederherstellbar.';

  @override
  String get duplInPapierkorb => 'In den Papierkorb';

  @override
  String duplVerschoben(int anzahl) {
    return '$anzahl Foto(s) in den Papierkorb verschoben.';
  }

  @override
  String get duplTitel => 'Duplikate & ähnliche Fotos';

  @override
  String get duplZweiteBibliothek => 'Zweite Bibliothek';

  @override
  String get duplAlleKopienLoeschen => 'Alle Kopien löschen';

  @override
  String get duplAehnlichkeit => 'Ähnlichkeit:';

  @override
  String get duplSchwelleHinweis =>
      'Höhere Werte = nur sehr ähnliche Fotos werden als Gruppe erkannt. Niedrigere Werte finden mehr, aber auch weniger sichere Treffer.';

  @override
  String get duplKeineGruppen => 'Keine ähnlichen Fotogruppen gefunden.';

  @override
  String get duplVerschiebenTooltip => 'In den Papierkorb verschieben';

  @override
  String get duplZusammenfuehren => 'Zusammenführen';

  @override
  String get duplZusammenfuehrenTitel => 'Ähnliche Fotos zusammenführen';

  @override
  String duplZusammenfuehrenText(int anzahl) {
    return 'Metadaten aller $anzahl Fotos werden auf die gewählte Aufnahme übertragen. Die übrigen Fotos landen im Papierkorb und können dort wiederhergestellt werden.';
  }

  @override
  String get duplBehaltenAuswahl => 'Diese Aufnahme behalten';

  @override
  String duplBehaltenDetails(int sterne, int favorit) {
    return '$sterne Sterne · $favorit Favorit(en)';
  }

  @override
  String get duplBeschreibungenVerbinden =>
      'Unterschiedliche Beschreibungen verbinden';

  @override
  String duplZusammengefuehrt(int anzahl) {
    return '$anzahl Foto(s) zusammengeführt und in den Papierkorb verschoben.';
  }

  @override
  String get clusterTitel => 'Vorschläge prüfen';

  @override
  String get clusterFertig => 'Alle Vorschläge durchgesehen.';

  @override
  String clusterAehnlichZu(String name) {
    return 'Ähnlich zu: $name';
  }

  @override
  String get clusterUeberspringen => 'Überspringen';

  @override
  String get gesichtUmbenennen => 'Person umbenennen/ändern';

  @override
  String get gesichtNeuBenennen => 'Neues Gesicht benennen';

  @override
  String get gesichtGesperrt =>
      'Gesichts-Bearbeitung ist für Fotos im gesperrten Ordner nicht verfügbar.';

  @override
  String get gesichtManuellHinzufuegen => 'Gesicht manuell hinzufügen';

  @override
  String get gesichtHinzufuegenBeenden => 'Hinzufügen beenden';

  @override
  String get gesichtRechteckHinweis =>
      'Ziehe ein Rechteck über ein Gesicht, um es manuell zu markieren.';

  @override
  String get bearbBildNichtLesbar => 'Bild konnte nicht gelesen werden.';

  @override
  String bearbBildNichtLesbarFehler(String fehler) {
    return 'Bild konnte nicht gelesen werden: $fehler';
  }

  @override
  String get bearbSpeichernTitel => 'Änderungen speichern?';

  @override
  String get bearbSpeichernText =>
      'Die Originaldatei wird durch die bearbeitete Version ersetzt. Das lässt sich nicht rückgängig machen.';

  @override
  String get bearbNichtFinalisiert => 'Bild konnte nicht finalisiert werden.';

  @override
  String get bearbZuschneidenAnwenden => 'Zuschneiden anwenden';

  @override
  String get bearbTitel => 'Bearbeiten';

  @override
  String get importWasTitel => 'Was möchtest du importieren?';

  @override
  String get importWasText =>
      'Wähle einzelne Fotos/Videos aus, importiere einen kompletten Ordner (inkl. aller Unterordner), oder importiere direkt von einer angeschlossenen Kamera/SD-Karte.';

  @override
  String get importEinzelneDateien => 'Einzelne Dateien wählen';

  @override
  String get importGanzerOrdner => 'Ganzen Ordner wählen';

  @override
  String get importVonKamera => 'Von Kamera/SD-Karte';

  @override
  String get importOrdnerWaehlen => 'Ordner zum Importieren wählen';

  @override
  String get importNichtsImOrdner =>
      'Keine unterstützten Fotos/Videos in diesem Ordner gefunden.';

  @override
  String get importNichtsAufDatentraeger =>
      'Keine unterstützten Fotos/Videos auf diesem Datenträger gefunden.';

  @override
  String get importAbgeschlossen => 'Import abgeschlossen';

  @override
  String importBilanzNeu(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl neu hereingekommen',
      one: '1 neu hereingekommen',
    );
    return '$_temp0';
  }

  @override
  String importBilanzDuplikate(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl lagen schon in der Bibliothek und wurden übersprungen',
      one: '1 lag schon in der Bibliothek und wurde übersprungen',
    );
    return '$_temp0';
  }

  @override
  String importBilanzFehler(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl kamen nicht herein',
      one: '1 kam nicht herein',
    );
    return '$_temp0';
  }

  @override
  String get importLaeuft => 'Importiere Fotos & Videos …';

  @override
  String get importJetztSichten => 'Jetzt sichten';

  @override
  String integPruefungFehlgeschlagen(String fehler) {
    return 'Prüfung fehlgeschlagen: $fehler';
  }

  @override
  String get integOriginalFehlt =>
      'Das Original fehlt auf der Platte – das gesamte Foto/Video wird aus der Bibliothek entfernt.';

  @override
  String get integMaskeFehlt =>
      'Die Maskendatei fehlt – der Maskeneintrag wird entfernt.';

  @override
  String get integCropFehlt =>
      'Der Gesichts-Crop fehlt – nur die Vorschau wird entfernt, die Zuordnung zur Person bleibt erhalten.';

  @override
  String get integPfadEntfernt =>
      'Der Datei-Pfad wird aus der Datenbank entfernt – die Datei lässt sich über \"Werkzeuge → Vorschaubilder neu erstellen\" wieder herstellen.';

  @override
  String get integDateiLoeschenTitel => 'Datei löschen?';

  @override
  String integDateiLoeschenText(String pfad) {
    return '$pfad wird unwiderruflich von der Platte gelöscht.';
  }

  @override
  String get integErneutPruefen => 'Erneut prüfen';

  @override
  String get integPruefsummen => 'Prüfsummen prüfen';

  @override
  String get integPruefsummenHinweis =>
      'Liest jede Originaldatei komplett ein und vergleicht sie mit der beim Import gespeicherten Prüfsumme – bei großen Bibliotheken deutlich langsamer als die reine Existenz-/Verwaisten-Prüfung.';

  @override
  String integKeineProbleme(int anzahl) {
    return 'Keine Probleme gefunden ($anzahl Dateien geprüft).';
  }

  @override
  String get integAusDbEntfernen => 'Aus DB entfernen';

  @override
  String get integDateiLoeschen => 'Datei löschen';

  @override
  String integAbweichungen(int anzahl) {
    return 'Prüfsummen-Abweichungen ($anzahl)';
  }

  @override
  String get integInhaltGeaendert => 'Inhalt hat sich seit dem Import geändert';

  @override
  String get integAnsehen => 'Ansehen';

  @override
  String get integVorschauTitel => 'Vorschau';

  @override
  String get integKeineVorschau =>
      'Für diese Datei lässt sich keine Vorschau zeigen.';

  @override
  String get integVorschauVerschluesselt =>
      'Das Foto ist gesperrt – die Vorschau ist mitverschlüsselt.';

  @override
  String get integFotoOeffnen => 'Foto öffnen';

  @override
  String integHeaderProbleme(int anzahl) {
    return 'Verschlüsselte Dateien mit ungültigem Header ($anzahl)';
  }

  @override
  String get integBeschaedigt =>
      'Datei ist evtl. beschädigt – keine gültige verschlüsselte Datei';

  @override
  String get gesperrtLeer =>
      'Keine gesperrten Fotos. In der Vollbildansicht eines Fotos lässt es sich über das Schloss-Symbol oben rechts hierher verschieben (dabei verschlüsselt).';

  @override
  String get gesperrtEntfernen =>
      'Aus dem gesperrten Ordner entfernen (entschlüsseln)';

  @override
  String get gesperrtEndgueltigTitel => 'Endgültig löschen?';

  @override
  String get gesperrtEndgueltigText =>
      'Die Datei wird unwiderruflich gelöscht – auch mit dem richtigen PIN gibt es danach keine Wiederherstellung mehr.';

  @override
  String get gesperrtPapierkorbLeer =>
      'Der gesperrte Papierkorb ist leer.\n\nAus dem gesperrten Ordner gelöschte Fotos landen hier statt im normalen (ungeschützten) Papierkorb.';

  @override
  String get gesperrtWiederherstellen => 'Wiederherstellen (bleibt gesperrt)';

  @override
  String get personKeineGesichter => 'Keine Gesichter dieser Person vorhanden.';

  @override
  String get personProfilbildWaehlen => 'Profilbild auswählen';

  @override
  String get personProfilbildAendern => 'Profilbild ändern';

  @override
  String get personKeineFotos => 'Noch keine Fotos für diese Person.';

  @override
  String get personDoppelklickHinweis =>
      'Doppelklick auf ein Foto öffnet es zur Kontrolle mit allen erkannten Gesichtern.';

  @override
  String get personGelerntesVerworfen =>
      'Gelerntes verworfen – es gilt wieder die allgemeine Schwelle.';

  @override
  String personSchwelleAngepasst(String schwelle, String allgemein) {
    return 'angepasst auf $schwelle statt $allgemein';
  }

  @override
  String personSchwelleWiderspruch(String allgemein) {
    return 'weiterhin $allgemein – die Entscheidungen widersprechen sich, ein abgelehntes Gesicht war ähnlicher als ein bestätigtes';
  }

  @override
  String personSchwelleWirdAngepasst(int anzahl) {
    return 'ab $anzahl Entscheidungen wird angepasst';
  }

  @override
  String get personVerwerfen => 'Verwerfen';

  @override
  String get restaurWartet => 'Wartet in der Warteschlange';

  @override
  String restaurProzentLaeuft(int prozent) {
    return 'KI-Restaurierung läuft – $prozent %';
  }

  @override
  String restaurProzentMitRest(int prozent, String rest) {
    return 'KI-Restaurierung läuft – $prozent %, noch etwa $rest';
  }

  @override
  String restaurProzentMitWarteschlange(int prozent, int wartend) {
    return 'KI-Restaurierung läuft – $prozent %, $wartend in Warteschlange';
  }

  @override
  String restaurZeileLaeuft(int prozent) {
    return 'Läuft – $prozent %';
  }

  @override
  String restaurZeileMitRest(int prozent, String rest) {
    return 'Läuft – $prozent %, noch etwa $rest';
  }

  @override
  String restaurDauerMinuten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Minuten',
      one: 'eine Minute',
    );
    return '$_temp0';
  }

  @override
  String restaurDauerSekunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Sekunden',
      one: 'eine Sekunde',
    );
    return '$_temp0';
  }

  @override
  String get restaurWasPassiert =>
      'Real-ESRGAN rechnet das Foto auf die vierfache Kantenlänge hoch und glättet dabei Rauschen und Kompressionsspuren. Das Original bleibt unangetastet; das Ergebnis liegt daneben und lässt sich jederzeit wieder entfernen.';

  @override
  String get restaurTitel => 'KI-Restaurierung – Warteschlange';

  @override
  String get restaurLeer =>
      'Keine Restaurierungs-Aufträge vorhanden.\nIm Entwickeln-Screen eines Fotos lässt sich eine KI-Restaurierung anstoßen.';

  @override
  String get restaurAusListe => 'Aus der Liste entfernen';

  @override
  String restaurFehlgeschlagen(String grund) {
    return 'Fehlgeschlagen: $grund';
  }

  @override
  String get restaurFehlgeschlagenKurz => 'Fehlgeschlagen';

  @override
  String get zweitOrdnerWaehlen =>
      'Ordner der zweiten PhotoVault-Bibliothek wählen';

  @override
  String get zweitTitel => 'Zweite Bibliothek vergleichen';

  @override
  String get allgErneutVersuchen => 'Erneut versuchen';

  @override
  String get zweitErklaerung =>
      'Vergleicht die eigene Bibliothek gegen eine zweite, unabhängige PhotoVault-Bibliothek (z.B. auf einer externen Platte oder einem alten Rechner) per KI-Bildähnlichkeit – findet Fotos, die dort schon liegen, bevor du sie erneut importierst.\n\nGesperrte Fotos der zweiten Bibliothek werden dabei nie einbezogen, ohne dass deren PIN gebraucht wird.';

  @override
  String get zweitOrdnerKnopf => 'Ordner der zweiten Bibliothek wählen';

  @override
  String get zweitSchwelleHinweis =>
      'Höhere Werte = nur sehr ähnliche Fotos gelten als Übereinstimmung.';

  @override
  String get zweitKeineTreffer =>
      'Keine ähnlichen Fotos in der zweiten Bibliothek gefunden.';

  @override
  String zweitTreffer(int anzahl) {
    return '$anzahl mögliche Übereinstimmung(en)';
  }

  @override
  String get zweitAndererOrdner => 'Anderer Ordner';

  @override
  String zweitAehnlichProzent(String prozent) {
    return '$prozent % ähnlich';
  }

  @override
  String get zweitBibliothek => 'zweite Bibliothek';

  @override
  String get aehnlTitel => 'Ähnliche Fotos';

  @override
  String get aehnlClipFehlt =>
      'KI-Bildsuche nicht verfügbar – CLIP-Modell fehlt (siehe Einstellungen → KI-Modelle).';

  @override
  String get aehnlKeineTreffer =>
      'Für dieses Foto liegt noch kein KI-Embedding vor (siehe Werkzeuge → KI-Bildsuche → CLIP-Embeddings berechnen) oder es gibt keine ähnlichen Fotos in der Bibliothek.';

  @override
  String get stapelErklaerung =>
      'Fotos, die sich ähneln UND innerhalb weniger Sekunden aufgenommen wurden, werden hier als Serie vorgeschlagen. \"Übernehmen\" fasst eine Gruppe zu einem Stapel zusammen – nur das Titelbild bleibt danach in der Übersicht sichtbar, nichts wird gelöscht.';

  @override
  String stapelAlleUebernehmen(int anzahl) {
    return 'Alle $anzahl übernehmen';
  }

  @override
  String get stapelAlleFrageTitel => 'Alle Serien übernehmen?';

  @override
  String stapelAlleFrage(int anzahl) {
    return '$anzahl Gruppen werden zu Stapeln zusammengefasst. Titelbild ist jeweils das schärfste Foto. Nichts geht dabei verloren – „Serie auflösen“ im Info-Blatt nimmt jede Gruppierung wieder zurück.';
  }

  @override
  String werkzStapelGefunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Serien warten',
      one: '1 Serie wartet',
      zero: 'Keine Serien gefunden',
    );
    return '$_temp0';
  }

  @override
  String get serienvergleichTitel => 'Serie vergleichen';

  @override
  String get serienvergleichErklaerung =>
      'Dieselben Gesichter nebeneinander. Auf einem ganzen Foto sieht man nicht, wer blinzelt – auf den Ausschnitten sofort. Der Rahmen markiert die Aufnahme mit dem schärfsten Gesicht; das ist ein Vorschlag, keine Entscheidung.';

  @override
  String get serienvergleichOhneGesichter =>
      'Auf diesen Aufnahmen wurde kein Gesicht erkannt – verglichen werden nur die Bilder selbst.';

  @override
  String get serienvergleichSchaerfstes => 'Schärfstes Gesicht der Serie';

  @override
  String serienvergleichSchaerfe(int wert) {
    return 'Schärfe $wert';
  }

  @override
  String serienvergleichAugen(int prozent) {
    return 'Augen offen: $prozent %';
  }

  @override
  String get serienvergleichOhneWert => 'Schärfe noch nicht gemessen';

  @override
  String get serienvergleichOeffnen => 'Gesichter vergleichen';

  @override
  String get serienvergleichZuKurz =>
      'Zum Vergleichen braucht es mindestens zwei Aufnahmen.';

  @override
  String get stapelKeine => 'Keine Serienbilder gefunden.';

  @override
  String get allgVerwerfen => 'Verwerfen';

  @override
  String get statTitel => 'Statistik';

  @override
  String get allgAktualisieren => 'Aktualisieren';

  @override
  String get statLeer => 'Noch keine Fotos oder Videos in der Bibliothek.';

  @override
  String get statProJahr => 'Fotos & Videos pro Jahr';

  @override
  String get statSaisonalitaet => 'Saisonalität – Aufnahmen pro Monat';

  @override
  String get statKameras => 'Häufigste Kameras';

  @override
  String get statInsgesamt => 'Medien insgesamt';

  @override
  String get statFotos => 'Fotos';

  @override
  String get statVideos => 'Videos';

  @override
  String get statSpeicherplatz => 'Speicherplatz';

  @override
  String get statImPapierkorb => 'Im Papierkorb';

  @override
  String statDiagrammJahr(String werte) {
    return 'Balkendiagramm, Fotos und Videos pro Jahr: $werte';
  }

  @override
  String statDiagrammMonat(String werte) {
    return 'Balkendiagramm, Saisonalität pro Monat: $werte';
  }

  @override
  String get papierkorbTitel => 'Papierkorb';

  @override
  String get papierkorbEndgueltigTitel => 'Endgültig löschen?';

  @override
  String papierkorbEndgueltigText(int anzahl) {
    return '$anzahl Datei(en) unwiderruflich löschen.';
  }

  @override
  String papierkorbAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos',
      one: 'ein Foto',
    );
    return '$_temp0';
  }

  @override
  String papierkorbUmfang(int anzahl, String platz) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos',
      one: 'ein Foto',
    );
    return '$_temp0 · $platz';
  }

  @override
  String get papierkorbLeer => 'Der Papierkorb ist leer.';

  @override
  String get videoNichtGeoeffnet => 'Video konnte nicht geöffnet werden.';

  @override
  String get videoZuschneidenFehler => 'Zuschneiden fehlgeschlagen.';

  @override
  String get videoZuschneiden => 'Zuschneiden';

  @override
  String get xmpAlleUebernehmen => 'Alle übernehmen';

  @override
  String get xmpErneutEinlesen => 'Erneut einlesen';

  @override
  String xmpKeineAbweichungen(int anzahl) {
    return '$anzahl Sidecar(s) geprüft – keine Abweichungen zur Datenbank gefunden.';
  }

  @override
  String get restaurWirdGestartet => 'Wird gestartet …';

  @override
  String get restaurAbgebrochen => 'Abgebrochen';

  @override
  String get restaurGrundModellLaedtNicht =>
      'Das Restaurierungs-Modell liess sich nicht laden.';

  @override
  String get restaurGrundModellWeg => 'Modell nicht mehr verfügbar.';

  @override
  String get restaurGrundFotoWeg => 'Foto wurde inzwischen gelöscht.';

  @override
  String get restaurGrundGesperrt =>
      'KI-Restaurierung ist für gesperrte Fotos nicht verfügbar.';

  @override
  String get restaurGrundAufloesung => 'Bildauflösung unbekannt.';

  @override
  String get restaurGrundNichtGerendert =>
      'Bild konnte nicht gerendert werden.';

  @override
  String get restaurGrundNichtDekodiert =>
      'Gerendertes Bild konnte nicht dekodiert werden.';

  @override
  String get restaurNichtVerfuegbar =>
      'KI-Restaurierung ist nicht verfügbar – Modell nicht installiert.';

  @override
  String personSchwelleWieAllgemein(String allgemein) {
    return 'weiterhin $allgemein';
  }

  @override
  String personWiedererkennung(
      String erklaerung, int bestaetigt, int abgelehnt) {
    String _temp0 = intl.Intl.pluralLogic(
      bestaetigt,
      locale: localeName,
      other: '$bestaetigt Bestätigungen',
      one: 'einer Bestätigung',
    );
    String _temp1 = intl.Intl.pluralLogic(
      abgelehnt,
      locale: localeName,
      other: '$abgelehnt Korrekturen',
      one: 'einer Korrektur',
    );
    return 'Wiedererkennung: $erklaerung. Aus $_temp0 und $_temp1.';
  }

  @override
  String get infoKeineUnbenannten =>
      'Keine unbenannten Gesichter auf diesem Foto gefunden – falls noch keine Gesichtserkennung gelaufen ist, siehe Werkzeuge → Gesichter scannen.';

  @override
  String get infoTitel => 'Info';

  @override
  String get infoVideoStandbild =>
      'Ausgewertet auf einem Standbild aus der ersten Sekunde – nicht auf dem ganzen Film.';

  @override
  String get infoBeschreibungHinzufuegen => 'Beschreibung hinzufügen';

  @override
  String get infoKiBeschreibung => 'KI-Beschreibung';

  @override
  String get infoErkannterText => 'Erkannter Text';

  @override
  String get infoTextKopieren => 'Text kopieren';

  @override
  String get infoTextKopiert => 'Text in die Zwischenablage kopiert';

  @override
  String infoTextStellen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Textstellen im Bild',
      one: '1 Textstelle im Bild',
    );
    return '$_temp0';
  }

  @override
  String get infoBewertung => 'Bewertung';

  @override
  String get infoNiemandZugeordnet => 'Noch niemand zugeordnet.';

  @override
  String get infoDetails => 'Details';

  @override
  String get infoStandortBekannt => 'Standort bekannt';

  @override
  String get infoOrtNichtAufgeloest =>
      'Ort noch nicht aufgelöst (Werkzeuge → Orte)';

  @override
  String get infoOrtEntfernen => 'Ort entfernen';

  @override
  String get infoBearbeitet => 'Bearbeitet';

  @override
  String get infoBearbeitetEntwickelt => 'entwickelt';

  @override
  String get infoBearbeitetRestauriert => 'restauriert';

  @override
  String get infoBearbeitetZugeschnitten => 'zugeschnitten';

  @override
  String infoOriginalUnberuehrt(String arten) {
    return '$arten – die Originaldatei ist unverändert';
  }

  @override
  String get infoOriginalHerstellen => 'Original wiederherstellen';

  @override
  String get infoOriginalHerstellenFrage =>
      'Alle Bearbeitungen dieser Aufnahme zurücknehmen? Die abgeleiteten Dateien werden gelöscht; das Original bleibt, wie es ist.';

  @override
  String get infoOriginalHergestellt => 'Original wiederhergestellt.';

  @override
  String infoSerie(int anzahl) {
    return 'Serie: $anzahl Fotos';
  }

  @override
  String get infoNurTitelbild =>
      'Nur das Titelbild ist in der Übersicht sichtbar';

  @override
  String get infoSerieAufloesen => 'Serie auflösen';

  @override
  String get infoTagHinzufuegenPlatzhalter => 'Tag hinzufügen …';

  @override
  String get stufeBildanalyse => 'Bildanalyse';

  @override
  String get stufeTexterkennung => 'Texterkennung';

  @override
  String get stufeSchlagwoerter => 'Schlagwörter';

  @override
  String get stufeBildbeschreibung => 'Bildbeschreibung';

  @override
  String get aktualisierungKeineVeroeffentlichungen =>
      'Keine Veröffentlichungen gefunden.';

  @override
  String get aktualisierungKeineVersion =>
      'Keine Versionsangabe in der Antwort gefunden.';

  @override
  String backupGrenzeErreicht(int anzahl) {
    return 'Grenze erreicht – $anzahl Datei(en) folgen beim nächsten Lauf';
  }

  @override
  String backupUebernommen(int anzahl) {
    return '$anzahl Einträge aus dem Datenbank-Schnappschuss übernommen (Personen, Stammbaum, Reisen, Aktivitäten …)';
  }

  @override
  String get backupAusschnitteNeu =>
      'Gesichtsausschnitte werden neu gezeichnet …';

  @override
  String get einstBackupManuellHinweis =>
      'Eine Sicherung mit Passphrase nimmt zusätzlich einen verschlüsselten Schnappschuss der Datenbank mit – Personen, Stammbaum, Reisen, Aktivitäten und gespeicherte Suchen kommen damit beim Wiederherstellen zurück. Ohne Passphrase enthält die Sicherung nur die Originale und die Beilagen daneben (Beschreibung, Sterne, Farbmarke, Ort, Schlagwörter, Alben); alles Übrige liesse sich danach nicht wiederherstellen.';

  @override
  String backupNichtGesichert(int anzahl) {
    return '$anzahl Datei(en) konnten nicht gesichert werden – sie werden beim nächsten Lauf erneut versucht';
  }

  @override
  String get backupPassphraseNoetig =>
      'Dieses Backup ist verschlüsselt – eine Passphrase wird benötigt.';

  @override
  String get backupOrdnerFehlt => 'Im gewählten Ordner liegt kein Backup.';

  @override
  String downloadPruefsummeFehler(
      String datei, String erhalten, String erwartet) {
    return 'Prüfsumme von $datei stimmt nicht mit der erwarteten SHA-256 überein (erhalten $erhalten, erwartet $erwartet) – Download verworfen. Die Datei am Server hat sich möglicherweise geändert oder wurde beim Transfer verändert.';
  }

  @override
  String downloadFehlgeschlagen(String datei, String fehler) {
    return 'Download von $datei fehlgeschlagen: $fehler';
  }

  @override
  String downloadEntpackenFehler(String datei, String fehler) {
    return 'Entpacken von $datei fehlgeschlagen: $fehler';
  }

  @override
  String downloadNichtImZip(String datei) {
    return '$datei nicht im Zip gefunden.';
  }

  @override
  String get regelAusloeserOrt => 'Ort (Umkreis)';

  @override
  String get regelAusloeserTag => 'KI-Tag';

  @override
  String get regelAusloeserDatum => 'Datumsbereich';

  @override
  String regelUmkreisUm(String km, String breite, String laenge) {
    return 'Umkreis $km km um $breite, $laenge';
  }

  @override
  String regelTagWert(String begriff) {
    return 'KI-Tag: $begriff';
  }

  @override
  String regelDatumBereich(String von, String bis) {
    return '$von – $bis';
  }

  @override
  String regelUmkreis(String km) {
    return 'Umkreis: $km km';
  }

  @override
  String regelAlbumTeil(String name) {
    return 'Album: $name';
  }

  @override
  String regelTagsTeil(String namen) {
    return 'Tags: $namen';
  }

  @override
  String duplGruppe(int nummer, int anzahl) {
    return 'Gruppe $nummer · $anzahl Fotos';
  }

  @override
  String stapelSerie(int nummer, int anzahl) {
    return 'Serie $nummer · $anzahl Fotos';
  }

  @override
  String clusterGesichterZuordnen(int anzahl) {
    return '$anzahl Gesichter zuordnen';
  }

  @override
  String clusterGesichterAnzahl(int anzahl) {
    return '$anzahl Gesichter';
  }

  @override
  String gesichtEmbeddingFehler(String fehler) {
    return 'Wiedererkennungs-Embedding fehlgeschlagen: $fehler';
  }

  @override
  String bearbSpeichernFehler(String fehler) {
    return 'Speichern fehlgeschlagen: $fehler';
  }

  @override
  String integFehlendeDateien(int anzahl) {
    return 'Fehlende Dateien ($anzahl)';
  }

  @override
  String integVerwaisteDateien(int anzahl) {
    return 'Verwaiste Dateien ($anzahl)';
  }

  @override
  String get viewerKugelSchwenken => '3D-Kugel statt flachem Schwenken';

  @override
  String get regelNeuTitel => 'Neue Automatisierungsregel';

  @override
  String get regelBearbeitenTitel => 'Regel bearbeiten';

  @override
  String presetZeileAlbum(String album) {
    return 'Album: $album';
  }

  @override
  String presetZeileTags(String tags) {
    return 'Tags: $tags';
  }

  @override
  String get presetKeineAktion => 'Keine Aktion konfiguriert';

  @override
  String get presetNeuTitel => 'Neues Kamera-Preset';

  @override
  String get presetBearbeitenTitel => 'Kamera-Preset bearbeiten';

  @override
  String allgSucheFehlgeschlagen(String fehler) {
    return 'Suche fehlgeschlagen: $fehler';
  }

  @override
  String get allgUnbekannterFehler => 'Unbekannter Fehler';

  @override
  String erkundenVorJahren(int jahre) {
    String _temp0 = intl.Intl.pluralLogic(
      jahre,
      locale: localeName,
      other: 'Vor $jahre Jahren',
      one: 'Vor 1 Jahr',
    );
    return '$_temp0';
  }

  @override
  String erkundenImMonatVorJahren(String monat, int jahre) {
    return 'Im $monat vor $jahre Jahren';
  }

  @override
  String get gesichtBenennen => 'Gesicht benennen';

  @override
  String get gesichtUnbenannt => 'Unbenannt';

  @override
  String get bearbZuschneiden => 'Zuschneiden';

  @override
  String get bearbLinksDrehen => 'Nach links drehen';

  @override
  String get bearbRechtsDrehen => 'Nach rechts drehen';

  @override
  String get bearbHorizontalSpiegeln => 'Horizontal spiegeln';

  @override
  String get bearbVertikalSpiegeln => 'Vertikal spiegeln';

  @override
  String get integAusDbEntfernenTitel => 'Aus Datenbank entfernen?';

  @override
  String get integArtOriginal => 'Original';

  @override
  String get integArtThumbnail => 'Thumbnail';

  @override
  String get integArtVorschau => 'Vorschau';

  @override
  String get integArtEntwickelt => 'Entwickeltes Bild';

  @override
  String get integArtRestauriert => 'KI-restauriertes Bild';

  @override
  String get integArtVideoZuschnitt => 'Geschnittenes Video';

  @override
  String get integArtGesichtsCrop => 'Gesichts-Crop';

  @override
  String get integArtMaske => 'KI-Maske';

  @override
  String get integAlleVerwaistenLoeschen => 'Alle löschen';

  @override
  String get integAlleVerwaistenTitel => 'Alle verwaisten Dateien löschen?';

  @override
  String integAlleVerwaistenText(int anzahl, String groesse) {
    return '$anzahl Dateien mit zusammen $groesse werden unwiderruflich von der Platte gelöscht. Sie sind in keiner Datenbankzeile verzeichnet – die Bibliothek verliert dadurch nichts, was sie anzeigen könnte.';
  }

  @override
  String integVerwaisteGeloescht(int anzahl) {
    return '$anzahl verwaiste Dateien gelöscht.';
  }

  @override
  String integWeitereEintraege(int anzahl, int gezeigt) {
    return '… und $anzahl weitere. Die Liste zeigt nur die ersten $gezeigt; „Alle löschen“ räumt auch den Rest weg.';
  }

  @override
  String get gesperrtTabFotos => 'Fotos';

  @override
  String get gesperrtTabPapierkorb => 'Papierkorb';

  @override
  String get karteHell => 'Hell';

  @override
  String get karteDunkel => 'Dunkel';

  @override
  String get karteTopografie => 'Topografie';

  @override
  String get karteGlobus => 'Globus';

  @override
  String zweitVergleichFehlgeschlagen(String fehler) {
    return 'Vergleich fehlgeschlagen: $fehler';
  }

  @override
  String xmpEinlesenFehlgeschlagen(String fehler) {
    return 'Einlesen fehlgeschlagen: $fehler';
  }

  @override
  String get xmpFeldBewertung => 'Bewertung';

  @override
  String get xmpFeldFarbmarkierung => 'Farbmarkierung';

  @override
  String get xmpFeldBeschreibung => 'Beschreibung';

  @override
  String get xmpFeldNeueTags => 'Neue Tags';

  @override
  String get xmpFeldStandort => 'Standort';

  @override
  String get xmpFeldGesichter => 'Namen für erkannte Gesichter';

  @override
  String xmpGesichterOhneNamen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter ohne Namen',
      one: '1 Gesicht ohne Namen',
    );
    return '$_temp0';
  }

  @override
  String get xmpKeineSidecars => 'Keine XMP-Sidecars gefunden.';

  @override
  String get liveWiedergabeStoppen => 'Wiedergabe stoppen';

  @override
  String get liveDauerschleife => 'In Dauerschleife abspielen';

  @override
  String get metaHersteller => 'Kamera-Hersteller';

  @override
  String get metaModell => 'Kamera-Modell';

  @override
  String get metaObjektiv => 'Objektiv';

  @override
  String get metaBrennweite => 'Brennweite (mm)';

  @override
  String get metaBlende => 'Blende (f/…)';

  @override
  String get metaBelichtungszeit => 'Belichtungszeit';

  @override
  String get passphraseZuKurz =>
      'Passphrase muss mindestens 8 Zeichen lang sein.';

  @override
  String get exportVorgabenTitel => 'Export-Voreinstellungen';

  @override
  String get exportVorgabenLeer =>
      'Noch keine Voreinstellung. Eine Voreinstellung merkt sich Grösse, Qualität und Dateibenennung – für alles, was Sie öfter als einmal exportieren.';

  @override
  String get exportVorgabeNeu => 'Neue Voreinstellung';

  @override
  String get exportVorgabeNeuTitel => 'Neue Export-Voreinstellung';

  @override
  String get exportVorgabeBearbeitenTitel => 'Voreinstellung bearbeiten';

  @override
  String get exportVorgabeName => 'Name';

  @override
  String get exportVorgabeNameNoetig => 'Bitte einen Namen vergeben.';

  @override
  String get exportVorgabeNachJpeg => 'Nach JPEG rendern';

  @override
  String get exportVorgabeNachJpegHinweis =>
      'Ohne das wird die Datei unverändert kopiert – der einzige Weg, der RAW und Videos unangetastet lässt.';

  @override
  String get exportVorgabeKante => 'Längere Kante (Pixel)';

  @override
  String get exportVorgabeKanteLeer => 'leer = volle Auflösung';

  @override
  String get exportVorgabeKanteUngueltig =>
      'Die Kantenlänge muss zwischen 64 und 20000 liegen.';

  @override
  String exportVorgabeQualitaet(int prozent) {
    return 'JPEG-Qualität: $prozent %';
  }

  @override
  String get exportVorgabeMuster => 'Namensmuster';

  @override
  String get exportVorgabeMusterNoetig =>
      'Das Namensmuster darf nicht leer sein.';

  @override
  String get exportVorgabeMusterHinweis =>
      'Die Endung wird immer selbst ergänzt. Die laufende Nummer zählt innerhalb eines Export-Laufs und wird vierstellig aufgefüllt.';

  @override
  String get exportVorgabeXmp => 'XMP-Beistelldatei mitschreiben';

  @override
  String get exportVorgabeXmpHinweis =>
      'Bewertung, Schlagwörter und Ort für andere Programme – als eigene Datei neben dem Foto.';

  @override
  String exportVorgabeJpegVoll(int prozent) {
    return 'JPEG, volle Auflösung, $prozent %';
  }

  @override
  String exportVorgabeJpegKante(int kante, int prozent) {
    return 'JPEG, lange Kante $kante px, $prozent %';
  }

  @override
  String get exportVorgabeOhneXmp => 'ohne XMP';

  @override
  String get exportVorgabeLoeschenTitel => 'Voreinstellung löschen?';

  @override
  String exportVorgabeLoeschenText(String name) {
    return '„$name\" wird entfernt. Bereits exportierte Dateien bleiben unberührt.';
  }

  @override
  String get exportEigeneVorgaben => 'Eigene Voreinstellungen';

  @override
  String get exportVorgabenVerwalten => 'Voreinstellungen verwalten …';

  @override
  String get werkzExportVorgabenTitel => 'Export-Voreinstellungen';

  @override
  String get werkzExportVorgabenText =>
      'Benannte Ausgabe-Vorgaben für den Export: Grösse, JPEG-Qualität, Dateibenennung und ob eine XMP-Beistelldatei mitgeschrieben wird.';

  @override
  String get exportVorgabeNameVergeben => 'Diesen Namen gibt es schon.';

  @override
  String get entwObjektivkorrekturKeinRaw =>
      'Kein RAW – die Kamera hat Verzeichnung und Vignettierung bereits korrigiert.';

  @override
  String get entwObjektivkorrekturVerfuegbar =>
      'Kamera und Objektiv sind bekannt: Verzeichnung und Vignettierung werden korrigiert.';

  @override
  String get entwObjektivkorrekturUnbekanntesObjektiv =>
      'Für diese Kamera gibt es kein Profil. Bei ProRAW-Aufnahmen ist das kein Mangel – die Korrektur steckt schon in der Datei.';

  @override
  String get entwObjektivkorrekturNichtLesbar =>
      'Die RAW-Daten dieser Datei lassen sich nicht öffnen. Auch die übrigen Regler wirken deshalb nur auf die eingebettete Vorschau.';

  @override
  String get einstSuche => 'Suche nach Einstellungen';

  @override
  String get einstNichtsGefunden => 'Keine Einstellung passt zu dieser Suche.';

  @override
  String get einstBeschrErscheinungsbild => 'Hell, dunkel oder wie das System';

  @override
  String get einstBeschrSprache =>
      'Sprache der Oberfläche und der Schlagwörter';

  @override
  String get einstBeschrUeberwacht =>
      'Ordner, aus denen neue Fotos von selbst hereinkommen';

  @override
  String get einstBeschrBibliotheken =>
      'Zwischen mehreren Bibliotheken wechseln';

  @override
  String get einstBeschrSpeicherort =>
      'Wo die Bibliothek liegt und wie viel Platz sie braucht';

  @override
  String get einstBeschrModelle =>
      'Herunterladen und entfernen der lokalen Modelle';

  @override
  String get einstBeschrHintergrund =>
      'Ob nach dem Import automatisch ausgewertet wird';

  @override
  String get einstBeschrVokabular =>
      'Die Begriffe, nach denen Fotos beschlagwortet werden';

  @override
  String get einstAbschnittKarte => 'Karte';

  @override
  String get einstBeschrKarte => 'Kachelquelle der dunklen Karte';

  @override
  String get einstKartenNetzHinweis =>
      'Die Karte holt ihre Kacheln beim Anzeigen von OpenStreetMap, OpenTopoMap, Esri und – beim Gelände – von AWS Open Data. Deren Server erfahren dabei, welchen Ausschnitt du ansiehst, und damit ungefähr, wo deine Fotos entstanden sind. Ohne Karte verlässt nichts davon den Rechner: Land, Region und Stadt zu einem GPS-Ort schlägt die App im heruntergeladenen Ortsverzeichnis nach.';

  @override
  String get einstCartoText =>
      'Die dunkle Karte zeichnet von Haus aus umgefärbte OpenStreetMap-Kacheln – ohne Anmeldung und ohne Schlüssel. Wer den feineren CARTO-Schnitt möchte, trägt hier einen Schlüssel ein.';

  @override
  String get einstCartoAktiv => 'CARTO Dark Matter, bis Zoomstufe 20.';

  @override
  String get einstCartoOhne =>
      'Umgefärbte OpenStreetMap-Kacheln, bis Zoomstufe 19.';

  @override
  String get einstCartoFeld => 'CARTO-Schlüssel';

  @override
  String get einstCartoFeldHinweis => 'Leer lassen für OpenStreetMap';

  @override
  String get einstCartoQuelle =>
      'Kostenlos und ohne Konto unter carto.com/basemaps/apikey. CARTO stellt seine Rasterkacheln nach eigener Aussage ein – ohne Schlüssel bleibt die Karte davon unberührt.';

  @override
  String get einstCartoGespeichert => 'CARTO-Schlüssel gespeichert';

  @override
  String get einstCartoEntfernt =>
      'CARTO-Schlüssel entfernt – die Karte nutzt wieder OpenStreetMap';

  @override
  String get einstBeschrStandortdaten =>
      'Ortsnamen zu GPS-Koordinaten, offline';

  @override
  String get einstBeschrGesperrt => 'PIN, Verschlüsselung und was darin liegt';

  @override
  String get einstBeschrBackupSchluessel =>
      'Passphrase für verschlüsselte Sicherungen';

  @override
  String get einstBeschrBackupManuell => 'Eine Sicherung von Hand anstoßen';

  @override
  String get einstBeschrBackupAuto =>
      'Regelmäßig sichern, ohne daran zu denken';

  @override
  String get einstBeschrPapierkorb =>
      'Gelöschte Fotos ansehen, zurückholen, endgültig entfernen';

  @override
  String get einstBeschrGefahr =>
      'Schritte, die sich nicht rückgängig machen lassen';

  @override
  String get einstBeschrUeber => 'Version, Lizenzen und Aktualisierungen';

  @override
  String get allgRueckgaengig => 'Rückgängig';

  @override
  String get personenIgnoriertTab => 'Ignoriert';

  @override
  String tabMitZahl(String beschriftung, int anzahl) {
    return '$beschriftung ($anzahl)';
  }

  @override
  String get personenIgnorierenTooltip => 'Ausgewählte Gesichter ignorieren';

  @override
  String personenZugeordnetMeldung(int anzahl, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter „$name“ zugeordnet.',
      one: 'Ein Gesicht „$name“ zugeordnet.',
    );
    return '$_temp0';
  }

  @override
  String personenIgnoriertMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter ignoriert.',
      one: 'Ein Gesicht ignoriert.',
    );
    return '$_temp0';
  }

  @override
  String get personenIgnoriertLeer =>
      'Keine ignorierten Gesichter. Was du unter „Unbenannte Gesichter“ beiseitelegst – Plakate, Spiegelungen, Statuen –, sammelt sich hier und lässt sich jederzeit zurückholen.';

  @override
  String get personenIgnoriertHinweis =>
      'Ignorierte Gesichter erscheinen nicht mehr im Raster und werden nicht mehr gruppiert. Doppelklick öffnet das ganze Foto.';

  @override
  String personenIgnoriertTeilHinweis(int gezeigt, int gesamt) {
    return '$gezeigt von $gesamt ignorierten Gesichtern. Doppelklick öffnet das ganze Foto.';
  }

  @override
  String personenZurueckholenKnopf(int anzahl) {
    return '$anzahl zurückholen';
  }

  @override
  String get clusterPhaseLaden => 'Gesichter werden geladen …';

  @override
  String get clusterPhaseVergleichen => 'Gesichter werden verglichen …';

  @override
  String get clusterPhaseVorschlaege => 'Vorschläge werden vorbereitet …';

  @override
  String get clusterOhneProzent => 'Läuft …';

  @override
  String clusterFehlgeschlagen(String fehler) {
    return 'Die automatische Gruppierung ist fehlgeschlagen: $fehler';
  }

  @override
  String get clusterIgnorierenTooltip => 'Ganze Gruppe ignorieren';

  @override
  String get gesichtIgnorieren => 'Ignorieren';

  @override
  String get gesichtIgnoriert => 'Ignoriert';

  @override
  String get gesichtZurueckgeholt => 'Gesicht wird wieder berücksichtigt.';

  @override
  String gesichtPosition(int nummer, int gesamt) {
    return '$nummer von $gesamt';
  }

  @override
  String get gesichtVoriges => 'Vorheriges Foto (Pfeil links)';

  @override
  String get gesichtNaechstes => 'Nächstes Foto (Pfeil rechts)';

  @override
  String get clusterUnerwartetBeendet =>
      'Die automatische Gruppierung wurde unerwartet beendet.';

  @override
  String get aufgAktiv => 'Aktiv';

  @override
  String aufgStufeKurz(int nummer, int gesamt) {
    return 'Stufe $nummer/$gesamt';
  }

  @override
  String get personenAlleIgnorieren => 'Alle unbenannten Gesichter ignorieren';

  @override
  String personenAlleIgnorierenHinweis(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter wandern nach „Ignoriert“',
      one: 'Ein Gesicht wandert nach „Ignoriert“',
      zero: 'Nichts mehr offen',
    );
    return '$_temp0';
  }

  @override
  String personenAlleIgnoriertMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl Gesichter ignoriert. Unter „Ignoriert“ holst du einzelne zurück.',
      one: 'Ein Gesicht ignoriert. Unter „Ignoriert“ holst du einzelne zurück.',
      zero: 'Es war nichts zu ignorieren.',
    );
    return '$_temp0';
  }

  @override
  String get personenAlleErkennungenLoeschen =>
      'Alle unbenannten Erkennungen löschen';

  @override
  String get personenAlleErkennungenLoeschenHinweis =>
      'Gibt Platz frei, kommt beim nächsten Scan aber wieder';

  @override
  String get personenErkennungenLoeschenTitel =>
      'Erkennungen wirklich löschen?';

  @override
  String get personenErkennungenLoeschenText =>
      'Alle unbenannten Erkennungen werden samt ihrer Ausschnitte von der Platte gelöscht – auch die bereits ignorierten. Benannte Personen bleiben unberührt.\n\nDas ist nicht dauerhaft: Der nächste Gesichts-Scan findet dieselben Stellen wieder. Wenn du sie dauerhaft loswerden willst, nimm stattdessen „Alle unbenannten Gesichter ignorieren“ – das überlebt auch einen erneuten Scan.';

  @override
  String personenErkennungenGeloeschtMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Erkennungen gelöscht.',
      one: 'Eine Erkennung gelöscht.',
      zero: 'Es gab keine Erkennungen zum Löschen.',
    );
    return '$_temp0';
  }

  @override
  String get gesichtZuordnungLoesen => 'Zuordnung lösen';

  @override
  String get gesichtNichtMehrIgnorieren => 'Nicht mehr ignorieren';

  @override
  String get gesichtFotoLoeschen => 'Foto löschen';

  @override
  String get zeitraumName => 'Name';

  @override
  String get zeitraumArt => 'Art';

  @override
  String get zeitraumZaehlt => 'Fotos werden gezählt …';

  @override
  String zeitraumFotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Fotos in diesem Zeitraum',
      one: '1 Foto in diesem Zeitraum',
      zero: 'Kein Foto in diesem Zeitraum',
    );
    return '$_temp0';
  }

  @override
  String get reisenSelbstAnlegen => 'Reise von Hand anlegen';

  @override
  String reisenSelbstAngelegt(String name) {
    return 'Reise „$name\" angelegt.';
  }

  @override
  String get aktivitaetenSelbstAnlegen => 'Aktivität von Hand anlegen';

  @override
  String aktivitaetenSelbstAngelegt(String name) {
    return 'Aktivität „$name\" angelegt.';
  }

  @override
  String get infoOrtSuchen => 'Ort suchen';

  @override
  String get infoOrtSuchenBeispiel => 'z. B. Goslar';

  @override
  String get infoOrtKeinVerzeichnis =>
      'Dafür fehlt das Ortsverzeichnis. Es lässt sich unter Einstellungen → Standortdaten laden.';

  @override
  String infoOrtNichtGefunden(String name) {
    return 'Kein Ort namens „$name\" im Verzeichnis.';
  }

  @override
  String infoOrtGesetzt(String ort) {
    return 'Ort auf $ort gesetzt.';
  }

  @override
  String infoOrtGesetztMehrdeutig(String ort, int weitere) {
    return 'Ort auf $ort gesetzt – es gibt $weitere weitere gleichen Namens.';
  }

  @override
  String get gesichtNichtMehrDurchsuchen =>
      'Nicht mehr nach Gesichtern durchsuchen';

  @override
  String get gesichtWiederDurchsuchen => 'Wieder nach Gesichtern durchsuchen';

  @override
  String get gesichtNichtMehrDurchsuchtHinweis =>
      'Dieses Foto wird beim erneuten Durchsuchen übersprungen. Erkannte Gesichter bleiben.';

  @override
  String get gesichtWiederDurchsuchtHinweis =>
      'Dieses Foto wird wieder mitdurchsucht.';

  @override
  String get gesichtInGesperrtemOrdner =>
      'Das Foto liegt jetzt im gesperrten Ordner.';

  @override
  String get gesichtFavoritGesetzt => 'Als Favorit gesetzt.';

  @override
  String get gesichtFavoritEntfernt => 'Favorit entfernt.';

  @override
  String get gesichtSperrenFehlgeschlagen =>
      'Das Foto konnte nicht in den gesperrten Ordner gelegt werden.';

  @override
  String get gesichtErkennungLoeschen => 'Erkennung löschen';

  @override
  String gesichtAlleUnbenanntenIgnorieren(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl unbenannte Gesichter ignorieren',
      one: 'Unbenanntes Gesicht ignorieren',
      zero: 'Keine unbenannten Gesichter',
    );
    return '$_temp0';
  }

  @override
  String get personWeitereFotosSuchen => 'Weitere Fotos suchen';

  @override
  String vorschlagTitel(String name) {
    return 'Vorschläge für $name';
  }

  @override
  String get vorschlagHinweis =>
      'Alles ist ausgewählt. Nimm heraus, was nicht stimmt – auch das lernt die Erkennung: Eine Ablehnung schiebt die Schwelle für diese Person nach oben.';

  @override
  String get vorschlagAlleWaehlen => 'Alle wählen';

  @override
  String get vorschlagKeineWaehlen => 'Keine wählen';

  @override
  String vorschlagUebernehmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter zuordnen',
      one: 'Ein Gesicht zuordnen',
      zero: 'Nichts ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String vorschlagUebernommenMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos hinzugefügt.',
      one: 'Ein Foto hinzugefügt.',
      zero: 'Nichts übernommen – die Rückmeldung ist trotzdem gespeichert.',
    );
    return '$_temp0';
  }

  @override
  String get vorschlagKeineEmbeddings =>
      'Für diese Person gibt es noch keine Wiedererkennungs-Daten. Sie entstehen beim Gesichts-Scan, sobald das SFace-Modell installiert ist.';

  @override
  String get vorschlagKeineKandidaten =>
      'Es gibt keine unbenannten Gesichter, die vorgeschlagen werden könnten.';

  @override
  String vorschlagNichtsGefunden(String schwelle) {
    return 'Kein unbenanntes Gesicht liegt über der Schwelle $schwelle dieser Person.';
  }

  @override
  String get gesichtRahmenAusblenden => 'Rahmen ausblenden';

  @override
  String get gesichtRahmenEinblenden => 'Rahmen einblenden';

  @override
  String get entwKlarheit => 'Klarheit';

  @override
  String get entwVignettierung => 'Vignettierung';

  @override
  String get entwLutKeine => 'Keine Farbtabelle';

  @override
  String get entwLutWaehlen => 'Farbtabelle wählen (.cube)';

  @override
  String get entwLutEntfernen => 'Farbtabelle entfernen';

  @override
  String get entwLutStaerke => 'Stärke';

  @override
  String entwLutFehlt(String name) {
    return 'Die Farbtabelle „$name“ lässt sich nicht mehr lesen und wurde entfernt.';
  }

  @override
  String entwLutNichtLesbar(String fehler) {
    return 'Die Datei lässt sich nicht lesen: $fehler';
  }

  @override
  String get entwLutEindimensional =>
      'Das ist eine eindimensionale Tabelle – sie beschreibt eine Kurve, keinen Farbraum. Dafür gibt es hier die Tonwertkurve.';

  @override
  String get entwLutOhneGroesse => 'In der Datei fehlt die Angabe LUT_3D_SIZE.';

  @override
  String entwLutGroesse(int zeile) {
    return 'Die Kantenlänge in Zeile $zeile liegt außerhalb des Erlaubten (2 bis 256).';
  }

  @override
  String get entwLutZeilenzahl =>
      'Die Datei enthält nicht so viele Werte, wie ihre Kantenlänge verlangt.';

  @override
  String entwLutZeile(int zeile) {
    return 'Zeile $zeile lässt sich nicht lesen.';
  }

  @override
  String get histogrammWaveform => 'Waveform';

  @override
  String get histogrammParade => 'Parade';

  @override
  String get entwFormRechteck => 'Rechteck';

  @override
  String get entwFormFarbe => 'Farbe';

  @override
  String get entwRechteckHinweis =>
      'Ziehe ein Rechteck auf. Drehung und weiche Kante stellst du darunter ein.';

  @override
  String get entwFarbauswahlHinweis =>
      'Tippe auf eine Farbe im Bild. Ausgewählt wird alles, was ihr ähnlich genug ist – auch heller oder dunkler, denn Farbe zählt mehr als Helligkeit.';

  @override
  String entwFarbeAufgenommen(int rot, int gruen, int blau) {
    return 'R $rot · G $gruen · B $blau';
  }

  @override
  String get entwToleranz => 'Toleranz';

  @override
  String get vergleichTitel => 'Zwei Fotos vergleichen';

  @override
  String get vergleichNebeneinander => 'Nebeneinander';

  @override
  String get vergleichUebereinander => 'Übereinander';

  @override
  String get vergleichKoppeln => 'Ansichten koppeln';

  @override
  String get vergleichEntkoppeln => 'Ansichten entkoppeln';

  @override
  String get vergleichZuruecksetzen => 'Zoom zurücksetzen';

  @override
  String get auswVergleichen => 'Die zwei ausgewählten Fotos vergleichen';

  @override
  String get listeOhneKamera => 'Ohne Kameraangabe';

  @override
  String get zeitleisteGroesser => 'Grössere Kacheln';

  @override
  String get zeitleisteKleiner => 'Kleinere Kacheln – mehr Monate auf einmal';

  @override
  String get zeitleisteFormReihen =>
      'Bündige Reihen – jedes Foto in seinem Format';

  @override
  String get zeitleisteFormQuadrate => 'Quadratisches Raster';

  @override
  String get listeSpalten => 'Spalten';

  @override
  String get listeSpalteDateiname => 'Dateiname';

  @override
  String get listeSpalteDatum => 'Aufgenommen';

  @override
  String get listeSpalteKamera => 'Kamera';

  @override
  String get listeSpalteObjektiv => 'Objektiv';

  @override
  String get listeSpalteBelichtung => 'Belichtung';

  @override
  String get listeSpalteBewertung => 'Bewertung';

  @override
  String get listeSpalteFarbe => 'Farbe';

  @override
  String get listeSpalteMasse => 'Masse';

  @override
  String get listeSpalteGroesse => 'Dateigrösse';

  @override
  String get listeSpalteArt => 'Art';

  @override
  String get listeSpalteOrt => 'Ort';

  @override
  String get listeSpalteBreiteAendern => 'Breite ändern';

  @override
  String get ansichtRaster => 'Raster';

  @override
  String get ansichtListe => 'Liste';

  @override
  String get gruppeMonat => 'Nach Monat';

  @override
  String get gruppeKamera => 'Nach Kamera';

  @override
  String get gruppeKeine => 'Ohne Gliederung';

  @override
  String get sortReihenfolge => 'Reihenfolge';

  @override
  String get sortAufnahmeNeu => 'Aufnahmedatum, neueste zuerst';

  @override
  String get sortAufnahmeAlt => 'Aufnahmedatum, älteste zuerst';

  @override
  String get sortImportNeu => 'Zuletzt hinzugefügt';

  @override
  String get sortName => 'Dateiname, A–Z';

  @override
  String get sortBewertung => 'Bewertung, beste zuerst';

  @override
  String get sortGroesse => 'Dateigrösse, grösste zuerst';

  @override
  String get sortFundreihenfolge => 'Fundreihenfolge';

  @override
  String get bearbGeradeziehen => 'Geradeziehen';

  @override
  String get bearbPerspektive => 'Perspektive';

  @override
  String get bearbPerspektiveAnwenden => 'Entzerren';

  @override
  String get modellLamaTitel => 'Objektentfernung (LaMa)';

  @override
  String get modellLamaText =>
      'Füllt eine markierte Stelle aus der Umgebung neu auf – für Staubflecken, Passanten oder den Mülleimer am Bildrand. Mit 208 MB das grösste Modell hier; ein Durchgang dauert rund eine Sekunde.';

  @override
  String get modellLamaLizenz =>
      'Apache 2.0 (Samsung Research), ONNX-Export von Carve';

  @override
  String get bearbRetusche => 'Objekt entfernen';

  @override
  String get aufgLamaModell => 'das LaMa-Modell';

  @override
  String get bearbRetuscheNichtsMarkiert =>
      'Nichts markiert – male über das, was verschwinden soll.';

  @override
  String get bearbRetuscheAnwenden => 'Entfernen';

  @override
  String get bearbRetuscheZurueck => 'Letzten Strich zurücknehmen';

  @override
  String get bearbPinselbreite => 'Pinselbreite';

  @override
  String bearbRetuscheFehler(String fehler) {
    return 'Das Entfernen ist fehlgeschlagen: $fehler';
  }

  @override
  String get stammbaumTitel => 'Stammbaum';

  @override
  String stammbaumTitelVon(String name) {
    return 'Stammbaum: $name';
  }

  @override
  String get stammbaumElternteilHinzufuegen => 'Elternteil hinzufügen';

  @override
  String get stammbaumPartnerHinzufuegen => 'Partner hinzufügen';

  @override
  String get stammbaumKindHinzufuegen => 'Kind hinzufügen';

  @override
  String get stammbaumInDieMitte => 'In die Mitte rücken';

  @override
  String get stammbaumLebensdaten => 'Lebensdaten …';

  @override
  String get stammbaumFotosZeigen => 'Fotos dieser Person';

  @override
  String get stammbaumVerbindungEntfernen => 'Verbindung entfernen';

  @override
  String stammbaumVerbindungEntfernenFrage(String eine, String andere) {
    return 'Die Verwandtschaft zwischen $eine und $andere wird gelöst. Beide Personen und ihre Fotos bleiben erhalten.';
  }

  @override
  String get stammbaumFehlerSelbst =>
      'Eine Person kann nicht mit sich selbst verwandt sein.';

  @override
  String get stammbaumFehlerKreis =>
      'Das ginge im Kreis: Die Person steht bereits weiter unten im selben Zweig.';

  @override
  String get stammbaumFehlerVorhanden =>
      'Diese Verwandtschaft ist schon eingetragen.';

  @override
  String stammbaumZuVieleHaushalte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl weitere Haushalte passen nicht ins Bild.',
      one: 'Ein weiterer Haushalt passt nicht ins Bild.',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumLeer =>
      'Für diese Person ist noch keine Verwandtschaft eingetragen. Oben rechts lassen sich Eltern, Partner und Kinder hinzufügen – entweder aus den bereits benannten Personen oder als neuer Name, auch ohne ein einziges Foto.';

  @override
  String get stammbaumPersonFehlt => 'Diese Person gibt es nicht mehr.';

  @override
  String get stammbaumGeboren => 'Geboren';

  @override
  String get stammbaumGestorben => 'Gestorben';

  @override
  String get stammbaumUnbekannt => 'unbekannt';

  @override
  String get stammbaumNurJahrHinweis =>
      'Ist nur das Jahr bekannt, wähle einen beliebigen Tag darin – angezeigt wird ohnehin nur die Jahreszahl.';

  @override
  String get gradSelbst => 'diese Person';

  @override
  String gradEltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Mutter',
        'm': 'Vater',
        'other': 'Elternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Großmutter',
        'm': 'Großvater',
        'other': 'Großelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrgrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Urgroßmutter',
        'm': 'Urgroßvater',
        'other': 'Urgroßelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrurgrosseltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Ururgroßmutter',
        'm': 'Ururgroßvater',
        'other': 'Ururgroßelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradVorfahreN(int stufe) {
    return 'Vorfahre der $stufe. Generation';
  }

  @override
  String gradKind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Tochter',
        'm': 'Sohn',
        'other': 'Kind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradEnkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Enkelin',
        'm': 'Enkel',
        'other': 'Enkelkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrenkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Urenkelin',
        'm': 'Urenkel',
        'other': 'Urenkelkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradUrurenkel(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Ururenkelin',
        'm': 'Ururenkel',
        'other': 'Ururenkelkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradNachkommeN(int stufe) {
    return 'Nachkomme der $stufe. Generation';
  }

  @override
  String gradGeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Schwester',
        'm': 'Bruder',
        'other': 'Geschwister',
      },
    );
    return '$_temp0';
  }

  @override
  String gradHalbgeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Halbschwester',
        'm': 'Halbbruder',
        'other': 'Halbgeschwister',
      },
    );
    return '$_temp0';
  }

  @override
  String gradNeffeNichte(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Nichte',
        'm': 'Neffe',
        'other': 'Geschwisterkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrossneffeNichte(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Großnichte',
        'm': 'Großneffe',
        'other': 'Großgeschwisterkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGeschwisterNachkommeN(int stufe) {
    return 'Nachkomme eines Geschwisters, $stufe Stufen entfernt';
  }

  @override
  String gradOnkelTante(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Tante',
        'm': 'Onkel',
        'other': 'Elterngeschwister',
      },
    );
    return '$_temp0';
  }

  @override
  String gradGrossonkelTante(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Großtante',
        'm': 'Großonkel',
        'other': 'Großelterngeschwister',
      },
    );
    return '$_temp0';
  }

  @override
  String gradVorfahrengeschwisterN(int stufe) {
    return 'Geschwister eines Vorfahren der $stufe. Generation';
  }

  @override
  String gradCousin(String geschlecht, int stufe) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Cousine',
        'm': 'Cousin',
        'other': 'Cousin/Cousine',
      },
    );
    return '$_temp0 $stufe. Grades';
  }

  @override
  String gradEntfernt(int stufe, String bezeichnung) {
    return '$bezeichnung, $stufe-fach entfernt';
  }

  @override
  String gradPartner(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Partnerin',
        'm': 'Partner',
        'other': 'Partner',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwager(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Schwägerin',
        'm': 'Schwager',
        'other': 'Schwager/Schwägerin',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwiegereltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Schwiegermutter',
        'm': 'Schwiegervater',
        'other': 'Schwiegerelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradSchwiegerkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Schwiegertochter',
        'm': 'Schwiegersohn',
        'other': 'Schwiegerkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefeltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stiefmutter',
        'm': 'Stiefvater',
        'other': 'Stiefelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stieftochter',
        'm': 'Stiefsohn',
        'other': 'Stiefkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradStiefgeschwister(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Stiefschwester',
        'm': 'Stiefbruder',
        'other': 'Stiefgeschwister',
      },
    );
    return '$_temp0';
  }

  @override
  String get gradAngeheiratet => 'angeheiratet';

  @override
  String gradUeberWeg(String schritt, String bezug, String name) {
    return '$schritt von $bezug $name';
  }

  @override
  String get gradKeine => 'nicht verwandt';

  @override
  String get navStammbaum => 'Stammbaum';

  @override
  String get stammbaumAndereWaehlen => 'Andere Person in die Mitte';

  @override
  String get stammbaumAnsichtBaum => 'Baum';

  @override
  String get stammbaumAnsichtListe => 'Verwandte';

  @override
  String stammbaumListeKopf(String name, int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl Personen sind mit $name verwandt – von den nächsten zu den entferntesten.',
      one: 'Eine Person ist mit $name verwandt.',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumKeinePersonen =>
      'Es sind noch keine Personen angelegt. Benenne im Tab „Personen\" ein paar Gesichter, oder lege hier über „Andere Person in die Mitte\" jemanden von Hand an.';

  @override
  String get stammbaumGeschlecht => 'Geschlecht';

  @override
  String get stammbaumGeschlechtWeiblich => 'weiblich';

  @override
  String get stammbaumGeschlechtMaennlich => 'männlich';

  @override
  String get stammbaumGeschlechtDivers => 'divers';

  @override
  String get stammbaumGeschlechtOffen => 'keine Angabe';

  @override
  String get stammbaumGeschlechtHinweis =>
      'Wird nur für die Verwandtschaftsbezeichnungen gebraucht – ohne Angabe steht dort „Geschwister\" statt „Schwester\".';

  @override
  String get stammbaumAngaben => 'Angaben zur Person';

  @override
  String get stammbaumAnsichtFaecher => 'Fächer';

  @override
  String get stammbaumAnsichtNachfahren => 'Nachfahren';

  @override
  String get stammbaumKeineVorfahren =>
      'Für diese Person sind noch keine Vorfahren eingetragen. Der Fächer zeigt Eltern, Großeltern und Urgroßeltern – füge oben rechts einen Elternteil hinzu, und er füllt sich von innen nach außen.';

  @override
  String get stammbaumKeineNachfahren =>
      'Für diese Person sind noch keine Kinder eingetragen. Die Gliederung zeigt alle Nachkommen, eingerückt nach Generation.';

  @override
  String get stammbaumFamilienfotos => 'Fotos der Familie';

  @override
  String stammbaumFamilienfotosVon(String name) {
    return 'Fotos der Familie von $name';
  }

  @override
  String get stammbaumGedcomImport => 'GEDCOM einlesen …';

  @override
  String get gedcomImportTitel => 'In der Datei steht';

  @override
  String gedcomImportGefunden(int personen, int kanten, int ereignisse) {
    return '$personen Personen, $kanten Verwandtschaften und $ereignisse Ereignisse.';
  }

  @override
  String get gedcomImportNeuHinweis =>
      'Alle werden neu angelegt. Nichts Bestehendes wird verändert oder zusammengeführt.';

  @override
  String get gedcomImportUebernehmen => 'Einlesen';

  @override
  String gedcomImportFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen eingelesen.',
      one: 'Eine Person eingelesen.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomFehlerTitel => 'Datei nicht lesbar';

  @override
  String get gedcomFehlerKeinKopf =>
      'Die Datei beginnt nicht mit einem GEDCOM-Kopf. Vermutlich ist es keine GEDCOM-Datei.';

  @override
  String gedcomFehlerKodierung(String kodierung) {
    return 'Die Datei ist in $kodierung geschrieben. Diese Kodierung lässt sich nicht sicher entziffern, und halb entzifferte Namen wären schlimmer als ein ehrliches Nein. Bitte im Herkunftsprogramm noch einmal als UTF-8 ausgeben.';
  }

  @override
  String get gedcomFehlerKeinePersonen =>
      'In der Datei steht keine einzige Person.';

  @override
  String get gedcomBerichtTitel => 'Was beim Einlesen auffiel';

  @override
  String get gedcomBerichtSauber => 'Nichts zu beanstanden.';

  @override
  String gedcomBerichtDoppelte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen könnte es schon geben.',
      one: 'Eine Person könnte es schon geben.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomBerichtDoppelteHinweis =>
      'Zusammengeführt wurde nichts. Wer wirklich dieselbe Person ist, entscheidest du im Personen-Bildschirm.';

  @override
  String gedcomBerichtUngenaueDaten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl Daten waren nur ungefähr angegeben und blieben deshalb leer.',
      one: 'Ein Datum war nur ungefähr angegeben und blieb deshalb leer.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtUebersprungen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Einträge gehören zu etwas, das diese App nicht führt.',
      one: 'Ein Eintrag gehört zu etwas, das diese App nicht führt.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtKreise(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl Verwandtschaften hätten einen Kreis geschlossen und blieben weg.',
      one: 'Eine Verwandtschaft hätte einen Kreis geschlossen und blieb weg.',
    );
    return '$_temp0';
  }

  @override
  String gedcomBerichtOhneNamen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen standen ohne Namen in der Datei.',
      one: 'Eine Person stand ohne Namen in der Datei.',
    );
    return '$_temp0';
  }

  @override
  String get gedcomOrtGeburt => 'Geburtsort';

  @override
  String get gedcomOrtTod => 'Sterbeort';

  @override
  String get gedcomOrtTaufe => 'Taufe';

  @override
  String get gedcomOrtBestattung => 'Bestattung';

  @override
  String get gedcomOhneNamen => 'Ohne Namen';

  @override
  String get stammbaumZeitleisteOhneDaten =>
      'Auf der Zeitleiste steht noch nichts: Bei keiner Person dieser Familie ist ein Datum eingetragen.';

  @override
  String get stammbaumAnsichtZeitleiste => 'Zeitleiste';

  @override
  String get zeitleisteOhneDatum => 'kein Datum bekannt';

  @override
  String zeitleisteEreignisse(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Ereignisse',
      one: 'ein Ereignis',
    );
    return '$_temp0';
  }

  @override
  String get stammbaumFamilienstatistik => 'Familienstatistik';

  @override
  String get famstatAufFotos => 'Auf den Fotos';

  @override
  String get famstatAusLebensdaten => 'Aus den Lebensdaten';

  @override
  String get famstatAufnahmenGesamt => 'Aufnahmen';

  @override
  String get famstatImBild => 'Im Bild';

  @override
  String get famstatZeitraum => 'Zeitraum';

  @override
  String famstatOhneBild(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen sind auf keinem Bild',
      one: 'Eine Person ist auf keinem Bild',
    );
    return '$_temp0';
  }

  @override
  String get famstatAufnahmenJeJahr => 'Aufnahmen je Jahr';

  @override
  String get famstatOftZusammen => 'Oft zusammen im Bild';

  @override
  String famstatVonBis(String von, String bis) {
    return '$von bis $bis';
  }

  @override
  String famstatAlterVonBis(int von, int bis) {
    return '$von bis $bis Jahre alt';
  }

  @override
  String famstatInJahren(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: 'in $anzahl Jahren',
      one: 'in einem Jahr',
    );
    return '$_temp0';
  }

  @override
  String get famstatFehlendeLebensdaten =>
      'Sterbealter, Heiratsalter und Alter je Generation stehen erst da, wenn Sterbe- und Hochzeitsdaten eingetragen sind. Photo Vault schätzt sie nicht.';

  @override
  String get famstatKeineFotos =>
      'Von dieser Familie ist noch niemand auf einem Foto erkannt worden.';

  @override
  String get famstatLeer => 'Zu dieser Familie ist niemand eingetragen.';

  @override
  String get famstatPersonen => 'Personen';

  @override
  String get famstatLebensalter => 'Lebensalter';

  @override
  String get famstatHeiratsalter => 'Heiratsalter';

  @override
  String get famstatHaeufigsterName => 'Häufigster Nachname';

  @override
  String famstatJahre(String jahre) {
    return '$jahre Jahre';
  }

  @override
  String famstatSpanne(int von, int bis) {
    return '$von bis $bis Jahre';
  }

  @override
  String get famstatOhneWert => 'keine Angabe';

  @override
  String famstatEingerechnet(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen eingerechnet',
      one: 'eine Person eingerechnet',
    );
    return '$_temp0';
  }

  @override
  String famstatOhneSterbedatum(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen ohne Sterbedatum sind nicht eingerechnet.',
      one: 'Eine Person ohne Sterbedatum ist nicht eingerechnet.',
    );
    return '$_temp0';
  }

  @override
  String get famstatWarumOhneSterbedatum =>
      'Wer noch lebt, hat kein Sterbedatum. Als „null Jahre“ mitgezählt käme ein Durchschnitt heraus, der plausibel aussieht und grob falsch ist.';

  @override
  String famstatOhneGeburtsdatum(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          'Bei $anzahl Hochzeiten fehlt das Geburtsdatum; sie sind nicht eingerechnet.',
      one:
          'Bei einer Hochzeit fehlt das Geburtsdatum; sie ist nicht eingerechnet.',
    );
    return '$_temp0';
  }

  @override
  String get famstatAlterJeGeneration => 'Lebensalter über die Generationen';

  @override
  String famstatGeneration(int nummer) {
    return '$nummer. Generation';
  }

  @override
  String famstatGenerationKurz(int nummer) {
    return '$nummer.';
  }

  @override
  String get famstatGenerationHinweis =>
      'Die erste ist die älteste, die in dieser Familie vorkommt. Generationen, aus denen niemand verstorben ist, fehlen.';

  @override
  String get famstatKinderzahl => 'Kinder je Person';

  @override
  String get famstatKinderHinweis =>
      'Eine Verteilung, kein Durchschnitt: Die jüngste Generation steht bei null, weil sie ihre Kinder noch vor sich hat. Gezählt werden nur Kinder, die in dieser Familie auch stehen.';

  @override
  String famstatKinderAchse(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Kinder',
      one: 'ein Kind',
      zero: 'ohne Kinder',
    );
    return '$_temp0';
  }

  @override
  String get famstatNachnamen => 'Nachnamen';

  @override
  String get famstatVornamen => 'Vornamen';

  @override
  String famstatDiagrammGenerationen(String inhalt) {
    return 'Lebensalter über die Generationen: $inhalt';
  }

  @override
  String famstatDiagrammKinder(String inhalt) {
    return 'Kinder je Person: $inhalt';
  }

  @override
  String get erkundenReisen => 'Reisen';

  @override
  String get erkundenAktivitaeten => 'Aktivitäten';

  @override
  String get gelaendeKarte => 'Karte auf der Landschaft';

  @override
  String get kalenderGanzesJahr => 'Ganzes Jahr';

  @override
  String get einstSchwebeVorschauTitel => 'Videos beim Schweben abspielen';

  @override
  String get einstSchwebeVorschauText =>
      'Bleibt die Maus einen Augenblick über einem Video oder einem Live Photo stehen, läuft es in der Kachel an – ohne Ton und in Dauerschleife, bis der Zeiger weiterwandert. Es läuft immer nur eines. Gesperrte Aufnahmen bleiben still: Sie abzuspielen hiesse, sie nebenbei zu entschlüsseln. Ausgeschaltet bleiben die Kacheln Standbilder.';

  @override
  String get gelaendeStimmung => 'Tageszeit';

  @override
  String get stimmungMorgen => 'Morgen';

  @override
  String get stimmungMittag => 'Mittag';

  @override
  String get stimmungAbend => 'Abend';

  @override
  String get stimmungBlaueStunde => 'Blaue Stunde';

  @override
  String get einstKarteScharfTitel => 'Karte in doppelter Auflösung';

  @override
  String get einstKarteScharfText =>
      'Auf einem Bildschirm mit doppelter Punktdichte holt die Karte vier Kacheln der nächsttieferen Stufe und setzt sie an die Stelle einer: viermal so viele Bildpunkte, Hausnummern und Ladennamen werden lesbar. Der Preis sind rund zweieinhalbmal so viele Kacheln je Bildschirm – auf einer langsameren Maschine ruckelt das Zoomen dadurch spürbar. Ausgeschaltet zeichnet die Karte wie zuvor.';

  @override
  String get routeVergroessern => 'Karte vergrössern';

  @override
  String get routeVerkleinern => 'Karte verkleinern';

  @override
  String get reisenTitel => 'Reisen';

  @override
  String get reisenLeer =>
      'Noch keine Reise. Photo Vault trägt sie nicht ein, sondern erkennt sie: Sobald genug verortete Aufnahmen aus der Ferne beisammen sind, erscheint hier ein Vorschlag zum Bestätigen.';

  @override
  String get reisenSuchtNoch => 'Sucht nach Reisen …';

  @override
  String get reisenVorschlaege => 'Vorschläge';

  @override
  String get reisenBestaetigte => 'Deine Reisen';

  @override
  String get reisenIstEineReise => 'War eine Reise';

  @override
  String get reisenKeineReise => 'Keine Reise';

  @override
  String get reisenBenennen => 'Reise benennen';

  @override
  String get reisenName => 'Name';

  @override
  String get reisenNotiz => 'Notiz';

  @override
  String get reisenTagesnotiz => 'Notiz zu diesem Tag';

  @override
  String reisenTagesnotizTitel(String datum) {
    return '$datum';
  }

  @override
  String get reisenTagesnotizSchreiben => 'Notiz zu diesem Tag schreiben';

  @override
  String get reisenTagesnotizAendern => 'Notiz zu diesem Tag ändern';

  @override
  String get reisenUmbenennen => 'Umbenennen';

  @override
  String get reisenLoeschen => 'Reise entfernen';

  @override
  String reisenLoeschenFrage(String name) {
    return '„$name“ entfernen? Die Aufnahmen bleiben, wo sie sind.';
  }

  @override
  String get reisenOhneOrt => 'Unbekannte Gegend';

  @override
  String reisenSpanne(String von, String bis) {
    return '$von bis $bis';
  }

  @override
  String reisenNaechte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Nächte',
      one: 'eine Nacht',
    );
    return '$_temp0';
  }

  @override
  String reisenAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Reisen',
      one: 'eine Reise',
      zero: 'keine Reise',
    );
    return '$_temp0';
  }

  @override
  String ortsbezugOrte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Orte',
      one: 'ein Ort',
    );
    return '$_temp0';
  }

  @override
  String ortsbezugWeitere(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl weitere Orte',
      one: 'ein weiterer Ort',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenAnzahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aktivitäten',
      one: 'eine Aktivität',
      zero: 'keine Aktivität',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenMitReise(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl mit Reise',
      one: 'eine mit Reise',
    );
    return '$_temp0';
  }

  @override
  String aktivitaetenOhneReiseZahl(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl einzelne',
      one: 'eine einzelne',
    );
    return '$_temp0';
  }

  @override
  String reisenAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aufnahmen',
      one: 'eine Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get reisenOrte => 'Besuchte Orte';

  @override
  String get reisenAktualisieren => 'Erneut suchen';

  @override
  String get reisenRoute => 'Route';

  @override
  String get reisenKeineRoute =>
      'Ohne verortete Aufnahme gibt es keine Strecke.';

  @override
  String get reisenAlsTitelbild => 'Als Titelbild';

  @override
  String get reisenTitelbildGesetzt => 'Titelbild gesetzt.';

  @override
  String reisenTag(String datum) {
    return '$datum';
  }

  @override
  String fortschrittLaender(int besucht, int gesamt) {
    return '$besucht von $gesamt Ländern';
  }

  @override
  String fortschrittRegionen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Regionen',
      one: 'eine Region',
    );
    return '$_temp0';
  }

  @override
  String fortschrittOrte(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Orte',
      one: 'ein Ort',
    );
    return '$_temp0';
  }

  @override
  String get fortschrittOhneGeodaten =>
      'Ohne den GeoNames-Datensatz lässt sich keine Aufnahme einem Land zuordnen. Er wird unter „Werkzeuge“ geladen.';

  @override
  String fortschrittHinweis(int gesamt) {
    return 'Gezählt wird gegen die $gesamt Länder und Gebiete des GeoNames-Datensatzes – Überseegebiete eingeschlossen, nicht nur die 195 souveränen Staaten. Eine eigene, gepflegte Liste wäre eine zweite Wahrheit neben der, nach der die Fotos tatsächlich eingeordnet werden.';
  }

  @override
  String get weltkarteTitel => 'Weltkarte';

  @override
  String get weltkarteEbenen => 'Ebenen';

  @override
  String get weltkarteLaender => 'Länder';

  @override
  String get weltkarteRegionen => 'Regionen';

  @override
  String get weltkarteOrte => 'Orte';

  @override
  String get weltkarteKeinOrt =>
      'An dieser Stelle kennt der Datensatz keinen Ort.';

  @override
  String weltkarteMarkeGesetzt(String name) {
    return '„$name“ ist markiert.';
  }

  @override
  String get weltkarteOeffnen => 'Weltkarte';

  @override
  String get laenderTitel => 'Länderliste';

  @override
  String laenderKopf(int gesamt, int besucht, int teilweise) {
    return '$gesamt Länder · $besucht besucht · $teilweise teilweise';
  }

  @override
  String get laenderSuchen => 'Land oder Hauptstadt suchen';

  @override
  String get laenderFilter => 'Filtern nach';

  @override
  String get laenderAlle => 'Alle';

  @override
  String get laenderLegende => 'Legende';

  @override
  String get laenderAusFotos => 'Durch Fotos belegt';

  @override
  String get laenderNurVonHand => 'Von Hand ausgewählt';

  @override
  String get laenderVollstaendig => 'Vollständig';

  @override
  String get laenderTeilweise => 'Teilweise';

  @override
  String get laenderNichtBesucht => 'Nicht besucht';

  @override
  String get laenderBesucht => 'Besucht';

  @override
  String get laenderGeplant => 'Geplant';

  @override
  String get laenderVerbleibend => 'Verbleibend';

  @override
  String laenderRegionen(int besucht, int gesamt) {
    return '$besucht von $gesamt Regionen';
  }

  @override
  String get laenderOhneRegionen => 'Keine Regionen verzeichnet';

  @override
  String laenderAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aufnahmen',
      one: 'eine Aufnahme',
      zero: 'keine Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get laenderNichtsGefunden => 'Kein Land passt zur Suche.';

  @override
  String get laenderMarkeBesucht => 'Als besucht markieren';

  @override
  String get laenderMarkeGeplant => 'Als geplant markieren';

  @override
  String get laenderMarkeWeg => 'Marke entfernen';

  @override
  String get laenderVonHand => 'von Hand';

  @override
  String get laenderOhneGeodaten =>
      'Ohne den GeoNames-Datensatz gibt es kein Länderverzeichnis. Er wird unter „Werkzeuge“ geladen.';

  @override
  String get laenderHinweisMarke =>
      'Was die Fotos belegen, steht hier von selbst. Von Hand markiert wird, wovon es kein Bild gibt – die Reise vor der ersten Digitalkamera oder das Ziel für nächstes Jahr.';

  @override
  String get erdteilEU => 'Europa';

  @override
  String get erdteilAS => 'Asien';

  @override
  String get erdteilNA => 'Nordamerika';

  @override
  String get erdteilSA => 'Südamerika';

  @override
  String get erdteilAF => 'Afrika';

  @override
  String get erdteilOC => 'Ozeanien';

  @override
  String get erdteilAN => 'Antarktis';

  @override
  String get erdteilUnbekannt => 'Ohne Erdteil';

  @override
  String get werkzGpxTitel => 'Aus einer GPX-Spur verorten';

  @override
  String get werkzGpxText =>
      'Eine Aufzeichnung trägt Zeitstempel. Damit bekommen auch Aufnahmen aus Kameras ohne GPS ihren Ort.';

  @override
  String get gpxTitel => 'Aus GPX verorten';

  @override
  String get gpxDateiWaehlen => 'GPX-Datei wählen …';

  @override
  String get gpxErklaerung =>
      'Wähle eine Aufzeichnung. Photo Vault legt die Aufnahmezeiten deiner Fotos gegen die Spur und trägt die Koordinate nach – nur bei Aufnahmen, die noch keine haben.';

  @override
  String gpxSpur(int punkte, String von, String bis) {
    return '$punkte Punkte · $von bis $bis';
  }

  @override
  String get gpxVersatz => 'Zeitversatz';

  @override
  String get gpxVersatzHinweis =>
      'EXIF schreibt die Aufnahmezeit ohne Zeitzone, GPX schreibt UTC. Der Vorschlag ist der Versatz, bei dem die meisten Aufnahmen auf die Spur passen – er fängt auch eine falsch gehende Kamerauhr ab.';

  @override
  String gpxTreffer(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aufnahmen bekommen einen Ort.',
      one: 'Eine Aufnahme bekommt einen Ort.',
      zero: 'Keine Aufnahme passt auf die Spur.',
    );
    return '$_temp0';
  }

  @override
  String get gpxVerorten => 'Verorten';

  @override
  String gpxFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aufnahmen verortet.',
      one: 'Eine Aufnahme verortet.',
    );
    return '$_temp0';
  }

  @override
  String get gpxKeineKandidaten =>
      'Im Zeitraum dieser Spur hat jede Aufnahme schon einen Ort.';

  @override
  String get gpxFehlerKeinGpx => 'Das ist keine GPX-Datei.';

  @override
  String get gpxFehlerOhneZeit =>
      'In dieser Spur trägt kein Punkt einen Zeitstempel. Ohne Zeit lässt sich keine Aufnahme zuordnen.';

  @override
  String get gpxFehlerLeer => 'Die Datei enthält keinen einzigen Punkt.';

  @override
  String get stammbaumKeineFamilienfotos =>
      'Auf keinem Foto wurde bisher jemand aus dieser Familie erkannt.';

  @override
  String get stammbaumGedcomExport => 'Als GEDCOM ausgeben …';

  @override
  String stammbaumGedcomFertig(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Personen ausgegeben.',
      one: 'Eine Person ausgegeben.',
    );
    return '$_temp0';
  }

  @override
  String gradAdoptiveltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Adoptivmutter',
        'm': 'Adoptivvater',
        'other': 'Adoptivelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradPflegeeltern(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Pflegemutter',
        'm': 'Pflegevater',
        'other': 'Pflegeelternteil',
      },
    );
    return '$_temp0';
  }

  @override
  String gradAdoptivkind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Adoptivtochter',
        'm': 'Adoptivsohn',
        'other': 'Adoptivkind',
      },
    );
    return '$_temp0';
  }

  @override
  String gradPflegekind(String geschlecht) {
    String _temp0 = intl.Intl.selectLogic(
      geschlecht,
      {
        'w': 'Pflegetochter',
        'm': 'Pflegesohn',
        'other': 'Pflegekind',
      },
    );
    return '$_temp0';
  }

  @override
  String get stammbaumLeiblich => 'Leiblich';

  @override
  String get stammbaumAdoptiv => 'Adoptiv';

  @override
  String get stammbaumPflege => 'Pflege';

  @override
  String get stammbaumAnsichtSanduhr => 'Sanduhr';

  @override
  String get stammbaumSeitenlinien => 'Seitenlinie';

  @override
  String get stammbaumSeitenlinienHinweis =>
      'Geschwister neben der Person, deren Kinder darunter – so werden auch Neffen, Nichten und Schwäger sichtbar.';

  @override
  String lebenslaufVon(String name) {
    return 'Lebenslauf: $name';
  }

  @override
  String get lebenslaufHinzufuegen => 'Ereignis hinzufügen';

  @override
  String get lebenslaufLeer =>
      'Für diese Person ist noch nichts eingetragen. Geburt und Tod stehen bei den Angaben zur Person; hier kommen Hochzeit, Umzug, Beruf und alles Weitere hin.';

  @override
  String get lebenslaufGeburt => 'Geboren';

  @override
  String get lebenslaufTod => 'Gestorben';

  @override
  String get lebenslaufHochzeit => 'Hochzeit';

  @override
  String get lebenslaufUmzug => 'Umzug';

  @override
  String get lebenslaufBeruf => 'Beruf';

  @override
  String get lebenslaufAusbildung => 'Ausbildung';

  @override
  String get lebenslaufSonstiges => 'Sonstiges';

  @override
  String get lebenslaufOhneDatum => 'ohne Datum';

  @override
  String get lebenslaufOrt => 'Ort';

  @override
  String get lebenslaufOrtAufKarte => 'Ort auf der Karte';

  @override
  String get lebenslaufOrtErkannt =>
      'Auf der Karte gefunden – tippen, um den Punkt zu berichtigen.';

  @override
  String get lebenslaufOrtUnbekannt =>
      'Dieser Ort ist im Ortsverzeichnis nicht enthalten. Tippen Sie auf die Karte, um ihn selbst zu setzen.';

  @override
  String get lebenslaufOrtEntfernen => 'Verortung entfernen';

  @override
  String get lebenslaufOrtOhneVerzeichnis =>
      'Ohne das Ortsverzeichnis lassen sich Orte nicht automatisch finden. Ein Punkt lässt sich trotzdem von Hand setzen.';

  @override
  String get lebenslaufNotiz => 'Notiz';

  @override
  String get stammbaumLebenslauf => 'Lebenslauf …';

  @override
  String get orteIch => 'Diese Person';

  @override
  String get orteVorfahren => 'Vorfahren';

  @override
  String get orteNachkommen => 'Nachkommen';

  @override
  String get orteSeitenlinie => 'Seitenlinie';

  @override
  String get orteAngeheiratet => 'Angeheiratet';

  @override
  String get orteEreignisse => 'Ereignisse';

  @override
  String get orteNichtsGewaehlt => 'Keine Gruppe ausgewählt.';

  @override
  String get stammbaumFamilienorte => 'Orte der Familie';

  @override
  String get stammbaumMenue => 'Mehr zu dieser Person';

  @override
  String get stammbaumVerbindungsart => 'Art der Verbindung …';

  @override
  String stammbaumVerbindungsartTitel(String kind, String elternteil) {
    return 'Wie ist $kind mit $elternteil verbunden?';
  }

  @override
  String get stammbaumVerbindungsartHinweis =>
      'Adoptiv- und Pflegeeltern zählen überall als Eltern – nur die Bezeichnung und die gestrichelte Linie unterscheiden sie.';

  @override
  String get stammbaumNichtsEntfernt => 'Diese Verbindung war schon gelöst.';

  @override
  String get stammbaumWeitereVerwandte => 'Weitere Verwandte';

  @override
  String get stammbaumVerwandtenHinzufuegen => 'Verwandten hinzufügen …';

  @override
  String get stammbaumGruppeVorfahren => 'Vorfahren';

  @override
  String get stammbaumGruppeNachkommen => 'Nachkommen';

  @override
  String get stammbaumGruppeSeitenlinie => 'Seitenlinie';

  @override
  String get stammbaumGruppeAngeheiratet => 'Angeheiratet';

  @override
  String get stammbaumGradGrosselternteil => 'Großelternteil';

  @override
  String get stammbaumGradUrgrosselternteil => 'Urgroßelternteil';

  @override
  String get stammbaumGradEnkelkind => 'Enkelkind';

  @override
  String get stammbaumGradUrenkelkind => 'Urenkelkind';

  @override
  String get stammbaumGradGeschwisterkind => 'Geschwisterkind';

  @override
  String get stammbaumGradHalbgeschwisterkind => 'Halbgeschwisterkind';

  @override
  String get stammbaumGradOnkelTante => 'Onkel oder Tante';

  @override
  String get stammbaumGradNeffeNichte => 'Neffe oder Nichte';

  @override
  String get stammbaumGradCousin => 'Cousin oder Cousine';

  @override
  String get stammbaumGradSchwiegerelternteil => 'Schwiegerelternteil';

  @override
  String get stammbaumGradSchwiegerkind => 'Schwiegerkind';

  @override
  String get stammbaumGradSchwager => 'Schwager oder Schwägerin';

  @override
  String get stammbaumGradStiefelternteil => 'Stiefelternteil';

  @override
  String get stammbaumGradStiefkind => 'Stiefkind';

  @override
  String stammbaumFehltElternteil(String name) {
    return 'Dafür braucht $name zuerst einen Elternteil.';
  }

  @override
  String stammbaumFehltGrosselternteil(String name) {
    return 'Dafür braucht $name zuerst Großeltern.';
  }

  @override
  String stammbaumFehltKind(String name) {
    return 'Dafür braucht $name zuerst ein Kind.';
  }

  @override
  String stammbaumFehltEnkelkind(String name) {
    return 'Dafür braucht $name zuerst ein Enkelkind.';
  }

  @override
  String stammbaumFehltGeschwister(String name) {
    return 'Dafür braucht $name zuerst ein Geschwisterkind.';
  }

  @override
  String stammbaumFehltOnkelTante(String name) {
    return 'Dafür braucht $name zuerst einen Onkel oder eine Tante.';
  }

  @override
  String stammbaumFehltPartner(String name) {
    return 'Dafür braucht $name zuerst einen Partner.';
  }

  @override
  String stammbaumFehltGeschwisterOderPartner(String name) {
    return 'Dafür braucht $name zuerst ein Geschwisterkind oder einen Partner.';
  }

  @override
  String stammbaumUeberWen(String grad) {
    return '$grad – über wen?';
  }

  @override
  String stammbaumVerwandterEingetragen(String name, String bezeichnung) {
    return '$name ist eingetragen – $bezeichnung.';
  }

  @override
  String stammbaumNurEintragbares(String name) {
    return 'Gezeigt wird, was sich für $name eintragen lässt. Grau bedeutet: Dafür fehlt noch eine Zwischenperson.';
  }

  @override
  String stammbaumFamilienorteVon(String name) {
    return 'Orte der Familie von $name';
  }

  @override
  String get stammbaumKeineFamilienorte =>
      'Von dieser Familie ist kein Foto mit Ortsangabe vorhanden.';

  @override
  String get stammbaumZierbaumDrucken => 'Zierbaum als PDF';

  @override
  String get stammbaumTafelDrucken => 'Tafel als PDF …';

  @override
  String get stammbaumTafelFertig => 'Die Tafel wurde geschrieben.';

  @override
  String get aufgWirdErmittelt => 'Wird ermittelt …';

  @override
  String aufgAbgebrochenBei(int erledigt, int gesamt) {
    return 'Abgebrochen bei $erledigt von $gesamt';
  }

  @override
  String aufgFertigMit(int gesamt) {
    return 'Fertig – $gesamt bearbeitet';
  }

  @override
  String get beendenTitel => 'Es wird noch ausgewertet';

  @override
  String get beendenText =>
      'Beim Beenden geht die gerade bearbeitete Datei verloren; alles bereits Ausgewertete bleibt erhalten. Noch am Laufen:';

  @override
  String get beendenTrotzdem => 'Trotzdem beenden';

  @override
  String get beendenWeiterlaufen => 'Weiterlaufen lassen';

  @override
  String get aufgUebersetzenTitel => 'Beschreibungen übersetzen';

  @override
  String get aufgUebersetzenText =>
      'Überträgt die vorhandenen englischen KI-Bildunterschriften ins Deutsche – ohne das Beschreibungsmodell erneut laufen zu lassen.';

  @override
  String get aufgUebersetzungsmodell =>
      'das Übersetzungsmodell Englisch → Deutsch';

  @override
  String get werkzUebersetzeBeschreibungen => 'Übersetze Bildbeschreibungen …';

  @override
  String get werkzAlleUebersetzt => 'Alle Beschreibungen sind übersetzt.';

  @override
  String get aufgLaeuftSchon => 'Diese Auswertung läuft bereits.';

  @override
  String get infoKiBeschreibungVonHand => 'KI-Beschreibung, von Hand geändert';

  @override
  String get infoKiVonHandHinweis =>
      'Bleibt bei „Alle Fotos“ erhalten. Zum Neuberechnen das Feld leeren.';

  @override
  String get infoSpracheDe => 'DE';

  @override
  String get infoSpracheEn => 'EN';

  @override
  String get infoKiPlatzhalterDe => 'Deutsche Fassung eintragen';

  @override
  String get infoKiPlatzhalterEn => 'Englische Fassung eintragen';

  @override
  String duplGefunden(int gruppen, int fotos) {
    return '$gruppen Gruppen mit $fotos Fotos';
  }

  @override
  String get duplNichtsGefunden => 'Keine Gruppen gefunden';

  @override
  String get duplGruppeIgnorieren => 'Übergehen';

  @override
  String duplGruppeIgnoriert(int anzahl) {
    return '$anzahl Fotos werden bei der Duplikatsuche künftig übergangen.';
  }

  @override
  String duplAusnahmenZahl(int anzahl) {
    return '$anzahl übergangen';
  }

  @override
  String get duplAusnahmenTitel => 'Übergangene wieder anzeigen';

  @override
  String duplAusnahmenFrage(int anzahl) {
    return '$anzahl Paare sind von der Suche ausgenommen. Sollen alle wieder berücksichtigt werden?';
  }

  @override
  String get duplAusnahmenLoeschen => 'Alle wieder anzeigen';

  @override
  String get entwNurMitCoreImage =>
      'Schärfe, Rauschunterdrückung, Klarheit und Vignettierung brauchen Rechenschritte, die es nur unter macOS gibt. Die übrigen Regler wirken hier vollständig.';

  @override
  String get modellOcrTitel => 'Texterkennung (PaddleOCR)';

  @override
  String get modellOcrText =>
      'Findet Text in Fotos und liest ihn – zwei Modelle, zusammen 13,7 MB. Deckt das lateinische Alphabet samt Umlauten und ß ab. Unter macOS nicht nötig: Dort erledigt das Apples Vision-Framework ohne Download.';

  @override
  String get modellOcrLizenz => 'Apache 2.0 (PaddleOCR)';

  @override
  String get aufgOcrModell => 'das Texterkennungs-Modell';

  @override
  String get werkzDatumTitel => 'Aufnahmedatum aus RAW und Videos nachtragen';

  @override
  String get werkzDatumFrageTitel => 'Aufnahmedatum richtigstellen?';

  @override
  String get werkzDatumFrage =>
      'Fotos, deren Aufnahmedatum bisher vom Dateizeitstempel stammte, bekommen das echte Datum aus der RAW-Datei. Sie rücken damit in der Zeitleiste und im Kalender an die richtige Stelle und werden auf der Festplatte in den passenden Monatsordner verschoben.\n\nDie Fotos selbst werden nicht verändert. Rückgängig machen lässt sich der Lauf nicht.';

  @override
  String get werkzDatumStarten => 'Richtigstellen';

  @override
  String get werkzKorrigiereDatum => 'Lese Aufnahmedaten aus RAW und Videos …';

  @override
  String get werkzKeineRawFotos =>
      'Keine RAW-Aufnahmen und keine Videos in der Bibliothek.';

  @override
  String get karteGlobusZoomHinweis =>
      'Weiter heranzoomen zeigt keine zusätzlichen Details – die Erdtextur ist ein einzelnes Bild. Tippe auf einen Pin, um an dieser Stelle in die Karte zu wechseln.';

  @override
  String get karteHineinzoomen => 'Näher heran';

  @override
  String get karteHerauszoomen => 'Weiter weg';

  @override
  String get zoomEinpassen => 'Ganz zeigen';

  @override
  String get karteEreignisseEinblenden => 'Lebensereignisse einblenden';

  @override
  String get karteEreignisseAusblenden => 'Lebensereignisse ausblenden';

  @override
  String get karteStandortZeigen => 'Mein Standort';

  @override
  String get karteStandortNichtErmittelbar =>
      'Standort nicht ermittelbar. Prüfe unter Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste, ob Photo Vault fragen darf.';

  @override
  String get karteStandortSuche => 'Standort wird ermittelt …';

  @override
  String get weltkarteKlickMarkiert => 'Ein Klick markiert';

  @override
  String weltkarteMarkeWeggenommen(String name) {
    return '„$name“ ist nicht mehr markiert.';
  }

  @override
  String weltkarteSchonBelegt(String name) {
    return '„$name“ belegen deine Fotos bereits.';
  }

  @override
  String get weltkarteLegende => 'Woher eine Marke stammt';

  @override
  String get weltkarteLegendeFotos =>
      'Ausgefüllt, durchgezogener Rand: durch verortete Aufnahmen belegt.';

  @override
  String get weltkarteLegendeHand =>
      'Blass, gepunkteter Rand: von Hand markiert, ohne Foto.';

  @override
  String get weltkarteLegendeGeplant =>
      'Fast leer, gestrichelter Rand: geplant – zählt nicht als besucht.';

  @override
  String get weltkarteOhneUmriss =>
      'Für kleine Gebiete wie den Vatikan liegt kein Umriss vor; sie bleiben ein Punkt.';

  @override
  String ortRegionen(int besucht, int gesamt) {
    return 'Regionen · $besucht von $gesamt';
  }

  @override
  String ortOrte(int besucht, int gesamt) {
    return 'Orte · $besucht von $gesamt';
  }

  @override
  String ortFotos(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos',
      one: 'Ein Foto',
    );
    return '$_temp0';
  }

  @override
  String get ortNichtsHier =>
      'Von hier gibt es noch nichts – kein Foto, und der Datensatz kennt keine weitere Ebene darunter.';

  @override
  String get meldungenTitel => 'Meldungen';

  @override
  String get meldungenKeine => 'Bisher nichts zu melden.';

  @override
  String get meldungenGlocke => 'Meldungen ansehen';

  @override
  String get meldungSchliessen => 'Meldung schliessen';

  @override
  String get meldungenAlleSchliessen => 'Alle ausblenden';

  @override
  String get meldungenVerlaufLeeren => 'Verlauf leeren';

  @override
  String meldungWiederholt(int anzahl) {
    return '$anzahl×';
  }

  @override
  String get meldungArtHinweis => 'Hinweis';

  @override
  String get meldungArtErfolg => 'Erledigt';

  @override
  String get meldungArtWarnung => 'Warnung';

  @override
  String get meldungArtFehler => 'Fehler';

  @override
  String get aktivitaetenTitel => 'Aktivitäten';

  @override
  String get aktivitaetenOeffnen => 'Aktivitäten ansehen';

  @override
  String get aktivitaetenVorschlaege => 'Vorschläge';

  @override
  String get aktivitaetenBestaetigte => 'Auf Reisen';

  @override
  String get aktivitaetenOhneReise => 'Für sich';

  @override
  String get aktivitaetenLeer =>
      'Noch keine Aktivität. Wanderungen, Radtouren und Ausflüge werden aus den Aufnahmen eines Tages erkannt – gebraucht werden eine Handvoll verortete Bilder über mindestens eine Dreiviertelstunde.';

  @override
  String get aktivitaetenSuchtNoch => 'Sucht nach Unternehmungen …';

  @override
  String get aktivitaetenBenennen => 'Aktivität benennen';

  @override
  String get aktivitaetenUmbenennen => 'Umbenennen';

  @override
  String get aktivitaetenName => 'Name';

  @override
  String get aktivitaetenLoeschen => 'Aktivität löschen';

  @override
  String aktivitaetenLoeschenFrage(String name) {
    return '„$name\" aus der Liste nehmen? Die Fotos bleiben, wo sie sind.';
  }

  @override
  String get aktivitaetenNotiz => 'Notiz';

  @override
  String get aktivitaetenArtAendern => 'Art ändern';

  @override
  String aktivitaetenStrecke(String km) {
    return '$km km';
  }

  @override
  String aktivitaetenDauer(int stunden, int minuten) {
    return '$stunden h $minuten min';
  }

  @override
  String aktivitaetenDauerKurz(int minuten) {
    return '$minuten min';
  }

  @override
  String aktivitaetenAufnahmen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Fotos',
      one: 'Ein Foto',
    );
    return '$_temp0';
  }

  @override
  String get aktivitaetenOhneOrt => 'Unterwegs';

  @override
  String aktivitaetenZuReise(String reise) {
    return 'Gehört zu: $reise';
  }

  @override
  String get aktivitaetenKeineRoute =>
      'Zu wenige verortete Aufnahmen für eine Strecke.';

  @override
  String get aktivitaetenInDieserReise => 'Unternehmungen';

  @override
  String get reiseartReise => 'Reise';

  @override
  String get reisenZusammenfuehren => 'Zusammenführen';

  @override
  String get reisenZusammenfuehrenAllein =>
      'Es gibt keine zweite Reise, mit der sich diese zusammenführen liesse.';

  @override
  String reisenZusammenfuehrenTitel(String name) {
    return 'Zu „$name\" hinzufügen';
  }

  @override
  String reisenZusammenfuehrenHinweis(String name) {
    return 'Die gewählten Reisen gehen in „$name\" auf: Aufnahmen, Unternehmungen, Spuren und Tagesnotizen kommen mit, die Namen der gewählten verschwinden.';
  }

  @override
  String reisenZusammengefuehrt(String name, int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Reisen gingen',
      one: 'Eine Reise ging',
    );
    return '$_temp0 in „$name\" auf.';
  }

  @override
  String get reiseartUnternehmung => 'Unternehmung';

  @override
  String get reiseartGeschaeftlich => 'Dienstlich';

  @override
  String get reiseartBesuch => 'Besuch';

  @override
  String get reiseartSonstiges => 'Sonstiges';

  @override
  String get reisenArtAendern => 'Art der Reise';

  @override
  String get reisenAktivitaetAnlegen => 'Unternehmung anlegen';

  @override
  String get reisenOhneAktivitaeten =>
      'Noch keine – „Unternehmung anlegen\" macht aus der ganzen Reise oder einem Abschnitt daraus eine.';

  @override
  String get reisenAktivitaetLeer =>
      'In diesem Zeitraum liegt keine Aufnahme dieser Reise.';

  @override
  String reisenAktivitaetAngelegt(String name, int anzahl) {
    return 'Unternehmung „$name\" angelegt, $anzahl Aufnahmen.';
  }

  @override
  String aktivitaetenAngelegt(String name) {
    return '„$name\" eingetragen.';
  }

  @override
  String aktivitaetenEntfernt(String name) {
    return '„$name\" entfernt.';
  }

  @override
  String get aufnahmenWahlTitelAktivitaet => 'Fotos der Aktivität';

  @override
  String get aufnahmenWahlTitelReise => 'Fotos der Reise';

  @override
  String aufnahmenWahlZeitraum(String von, String bis) {
    return 'Zeitraum ($von – $bis)';
  }

  @override
  String get aufnahmenWahlAlle => 'Alle Fotos';

  @override
  String aufnahmenWahlGewaehlt(num anzahl) {
    final intl.NumberFormat anzahlNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String anzahlString = anzahlNumberFormat.format(anzahl);

    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahlString Fotos gewählt',
      one: '1 Foto gewählt',
      zero: 'nichts gewählt',
    );
    return '$_temp0';
  }

  @override
  String aufnahmenWahlAusserhalb(num anzahl) {
    final intl.NumberFormat anzahlNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String anzahlString = anzahlNumberFormat.format(anzahl);

    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahlString davon ausserhalb der Ansicht',
      one: '1 davon ausserhalb der Ansicht',
    );
    return '$_temp0';
  }

  @override
  String get aufnahmenWahlLeer =>
      'In diesem Zeitraum liegt kein Foto. Über „Alle Fotos“ lässt sich eines von ausserhalb dazunehmen.';

  @override
  String aufnahmenWahlGeaendert(num dazu, num weg) {
    final intl.NumberFormat dazuNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String dazuString = dazuNumberFormat.format(dazu);
    final intl.NumberFormat wegNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String wegString = wegNumberFormat.format(weg);

    String _temp0 = intl.Intl.pluralLogic(
      dazu,
      locale: localeName,
      other: '$dazuString Fotos dazu',
      one: '1 Foto dazu',
      zero: '',
    );
    String _temp1 = intl.Intl.pluralLogic(
      weg,
      locale: localeName,
      other: ', $wegString entfernt',
      one: ', 1 entfernt',
      zero: '',
    );
    return '$_temp0$_temp1';
  }

  @override
  String get aufnahmenWahlUnveraendert => 'Nichts geändert.';

  @override
  String get aktivitaetenArtNeu => 'Neue Art …';

  @override
  String get aktivitaetenArtNeuFrage => 'Wie soll die Art heissen?';

  @override
  String get aktArtSpaziergang => 'Spaziergang';

  @override
  String get aktArtWanderung => 'Wanderung';

  @override
  String get aktArtRadtour => 'Radtour';

  @override
  String get aktArtAusflug => 'Ausflug';

  @override
  String get aktArtBesichtigung => 'Besichtigung';

  @override
  String get aktArtBootsfahrt => 'Bootsfahrt';

  @override
  String get aktArtSonstiges => 'Sonstiges';

  @override
  String get aktivitaetenIstEine => 'War eine Unternehmung';

  @override
  String get aktivitaetenKeine => 'War keine';

  @override
  String get spurHinzufuegen => 'GPX-Spur hinzufügen';

  @override
  String get spurEntfernen => 'Spur entfernen';

  @override
  String get spurEntferntMeldung => 'Spur entfernt.';

  @override
  String spurHinzugefuegtMeldung(String name, String km) {
    return 'Spur „$name“ hinzugefügt: $km km.';
  }

  @override
  String get spurTitel => 'Aufgezeichnete Spur';

  @override
  String spurKm(String km) {
    return '$km km';
  }

  @override
  String spurKennzahlen(String km, int auf, int ab) {
    return '$km km · ▲ $auf m · ▼ $ab m';
  }

  @override
  String spurKennzahlenOhneHoehe(String km) {
    return '$km km · keine Höhenangaben';
  }

  @override
  String spurPunkte(int anzahl) {
    return '$anzahl Punkte';
  }

  @override
  String get spurHoehenprofil => 'Höhenprofil';

  @override
  String get spurOhneHoehen =>
      'Diese Datei führt keine Höhen – ohne sie gibt es kein Profil.';

  @override
  String spurProfilBeschreibung(String km, int tief, int hoch, int auf) {
    return 'Höhenprofil über $km km, von $tief bis $hoch Meter, $auf Meter Aufstieg.';
  }

  @override
  String spurStelle(String km, int hoehe) {
    return '$km km · $hoehe m';
  }

  @override
  String get spurSchonDa => 'Diese Aktivität hat schon eine Spur.';

  @override
  String get flugStarten => 'Flug starten';

  @override
  String get flugAnhalten => 'Anhalten';

  @override
  String get flugWeiter => 'Weiter';

  @override
  String get flugNochmal => 'Noch einmal';

  @override
  String get flugBeenden => 'Zur Übersicht';

  @override
  String get flugFortschritt => 'Stelle auf der Spur';

  @override
  String get flugHoehe => 'Höhe';

  @override
  String get flugTempo => 'Tempo';

  @override
  String get flugSteigung => 'Steigung';

  @override
  String get flugVideo => 'Als Video ausgeben';

  @override
  String get flugVideoAbbrechen => 'Ausgabe abbrechen';

  @override
  String flugVideoFertig(String datei) {
    return 'Video gespeichert: $datei';
  }

  @override
  String get flugVideoAbgebrochen => 'Ausgabe abgebrochen';

  @override
  String get flugVideoKeinWerkzeug =>
      'Für die Videoausgabe fehlt der Videoschreiber. Unter macOS gehört er zum System, unter Linux und Windows liegt er im Paket – erscheint diese Meldung, ist die Installation unvollständig.';

  @override
  String flugVideoLaeuft(int prozent) {
    return 'Video wird geschrieben – $prozent %';
  }

  @override
  String flugVideoLaeuftMitRest(int prozent, String rest) {
    return 'Video wird geschrieben – $prozent %, noch etwa $rest';
  }

  @override
  String get flugVideoEinstellungen => 'Video ausgeben';

  @override
  String get flugVideoAufloesung => 'Auflösung';

  @override
  String get flugVideoDauer => 'Dauer';

  @override
  String flugVideoDauerWert(int sekunden) {
    return '$sekunden Sekunden';
  }

  @override
  String flugVideoBilder(int bilder) {
    return '$bilder Bilder';
  }

  @override
  String get flugVideoWeiter => 'Speichern unter …';

  @override
  String get flugVideoWaehrenddessen =>
      'Die Bilder entstehen abseits des Bildschirms – der Flug wird dafür nicht abgespielt. Diese Ansicht muss so lange offen bleiben.';

  @override
  String flugVideoFehler(String grund) {
    return 'Die Videoausgabe ist fehlgeschlagen: $grund';
  }

  @override
  String get flugAufstieg => 'Aufstieg';

  @override
  String get flugUnterwegs => 'unterwegs';

  @override
  String get flugOhneZeit =>
      'Die Spur trägt keine Zeitstempel – ohne sie gibt es kein Tempo.';

  @override
  String get flugProfilBeschreibung =>
      'Höhenprofil der Spur mit der Stelle, an der der Flug gerade steht.';

  @override
  String flugMeterProfil(int meter) {
    return '$meter m';
  }

  @override
  String flugKmH(String wert) {
    return '$wert km/h';
  }

  @override
  String flugProzent(String wert) {
    return '$wert %';
  }

  @override
  String flugKm(String wert) {
    return '$wert km';
  }

  @override
  String get gelaendeTitel => 'Gelände';

  @override
  String get gelaendeOeffnen => 'Gelände ansehen';

  @override
  String get gelaendeLaedt => 'Holt Geländehöhen …';

  @override
  String get gelaendeNichts =>
      'Für diesen Ausschnitt kamen keine Geländehöhen an. Die Kacheln liegen im Netz; ohne Verbindung gibt es keine Landschaft.';

  @override
  String get gelaendeBedienung => 'Ziehen dreht und kippt · Rollen zoomt';

  @override
  String gelaendeUeberhoeht(String faktor) {
    return 'Höhe $faktor-fach überhöht';
  }

  @override
  String get gelaendeNamensnennung => 'Höhen: Tilezen / AWS Open Data';

  @override
  String get karteLuftbild => 'Luftbild';

  @override
  String get gelaendeEbeneWege => 'Wanderwege';

  @override
  String get gelaendeEbeneBeschriftung => 'Strassen und Ortsnamen';

  @override
  String get gelaendeEbeneHoehenlinien => 'Höhenlinien';

  @override
  String get gelaendeEbeneWanderobjekte => 'Gipfel, Hütten, Quellen';

  @override
  String get gelaendeErneut => 'Noch einmal versuchen';

  @override
  String get einstKiTagsZurueck => 'KI-Schlagwörter zurücknehmen';

  @override
  String get einstKiTagsZurueckText => 'Wird gezählt …';

  @override
  String einstKiTagsZurueckAnzahl(int anzahl) {
    return '$anzahl von der Bilderkennung vergeben – von Hand vergebene bleiben';
  }

  @override
  String einstKiTagsZurueckFrage(int anzahl) {
    return '$anzahl Schlagwörter der Bilderkennung werden entfernt. Von Hand vergebene bleiben unangetastet. Danach vergibt die Bilderkennung sie nach der neuen Regel neu.';
  }

  @override
  String get einstKiTagsZurueckJetzt => 'Zurücknehmen';

  @override
  String einstKiTagsZurueckFertig(int anzahl) {
    return '$anzahl Schlagwörter zurückgenommen.';
  }

  @override
  String papierkorbAusgewaehlt(int anzahl) {
    return '$anzahl ausgewählt';
  }

  @override
  String get papierkorbHinweis =>
      'Zum Wiederherstellen den Pfeil auf dem Bild antippen. Lange drücken wählt mehrere aus.';

  @override
  String aktivitaetenWeitere(int anzahl) {
    return '+$anzahl weitere';
  }

  @override
  String get einstVorladenTitel => 'Kartengebiete vorladen';

  @override
  String get einstVorladenText =>
      'Holt die Kacheln der eigenen Fotogebiete auf die Platte – danach braucht die Karte dort kein Netz mehr';

  @override
  String get einstVorladenKeineOrte =>
      'Es gibt noch keine verorteten Aufnahmen.';

  @override
  String einstVorladenFrage(int gebiete, int kacheln, int mb) {
    return '$gebiete Gebiete, $kacheln Kacheln, rund $mb MB. Das dauert eine Weile und läuft im Hintergrund weiter, solange die Einstellungen offen sind.';
  }

  @override
  String get einstVorladenStarten => 'Vorladen';

  @override
  String einstVorladenStand(int fertig, int gesamt) {
    return '$fertig von $gesamt';
  }

  @override
  String einstVorladenFertig(int geladen, int fehler) {
    return '$geladen Kacheln geladen, $fehler nicht erreichbar.';
  }

  @override
  String get mitschnittTitel => 'Kachel-Mitschnitt';

  @override
  String get mitschnittErklaerung =>
      'Schreibt für jede Kartenkachel mit, was das Netz wirklich zurückgibt: Statuscode, Ausnahme, Dauer und ob der Server die Verbindung offen lässt. Kacheln aus dem Kartenspeicher tauchen nicht auf – sie kommen nie am Netz an.';

  @override
  String get mitschnittStarten => 'Mitschnitt starten';

  @override
  String get mitschnittAnhalten => 'Anhalten';

  @override
  String get mitschnittLeeren => 'Leeren';

  @override
  String get mitschnittLaeuft =>
      'Läuft. Jetzt die Karte öffnen und so lange zoomen, bis die grauen Kacheln auftreten.';

  @override
  String get mitschnittAus => 'Angehalten.';

  @override
  String get mitschnittNochNichts => 'Noch nichts mitgeschrieben.';

  @override
  String get mitschnittVerbJeAbruf => 'Verbindungen je Abruf';

  @override
  String get mitschnittAbrufeJeKachel => 'Abrufe je Kachel';

  @override
  String get mitschnittAbrufe => 'Abrufe';

  @override
  String get mitschnittVerbindungen => 'Verbindungen';

  @override
  String get mitschnittKacheln => 'verschiedene Kacheln';

  @override
  String get mitschnittGeglueckt => 'geglückt';

  @override
  String get mitschnittFehlgeschlagen => 'fehlgeschlagen';

  @override
  String get mitschnittAbgebrochen => 'abgebrochen';

  @override
  String get mitschnittWiederholte => 'mehrfach geholt';

  @override
  String get mitschnittOhneDauer => 'Server schloss die Verbindung';

  @override
  String get mitschnittStatusTitel => 'Statuscodes';

  @override
  String get mitschnittFehlerTitel => 'Fehler';

  @override
  String get mitschnittLetzteTitel => 'Die letzten Abrufe';

  @override
  String get mitschnittKopieren => 'Bericht kopieren';

  @override
  String get mitschnittKopiert => 'Der Bericht liegt in der Zwischenablage.';

  @override
  String get einstMitschnittTitel => 'Kachel-Mitschnitt';

  @override
  String get einstMitschnittText =>
      'Aufzeichnen, was beim Laden der Karte wirklich passiert.';

  @override
  String mitschnittDauer(int ms, int max) {
    return 'Im Mittel $ms ms, längste $max ms';
  }

  @override
  String mitschnittDaten(String mb) {
    return '$mb MB geladen';
  }

  @override
  String mitschnittVerworfen(int anzahl) {
    return '$anzahl ältere Einträge sind der Grenze zum Opfer gefallen.';
  }

  @override
  String mitschnittMalGeholt(int anzahl) {
    return '${anzahl}x';
  }

  @override
  String get aufgTitel => 'Aufgaben';

  @override
  String get aufgModusAlle => 'Alle';

  @override
  String get aufgErstellen => 'Aufgabe erstellen';

  @override
  String get aufgErstellenText =>
      'Mehrere Aufgaben auf einmal einreihen. Sie laufen der Reihe nach ab – wie viele nebeneinander, steht unter „Gleichzeitige Ausführungen verwalten\".';

  @override
  String get aufgEinreihen => 'Einreihen';

  @override
  String get aufgGleichzeitigTitel => 'Gleichzeitige Ausführungen verwalten';

  @override
  String get aufgGleichzeitigText =>
      'Wie viele rechenintensive Aufgaben nebeneinander laufen dürfen. Jede hält ein KI-Modell im Speicher und liest dieselben Fotos noch einmal von der Platte – mehr ist nicht immer schneller. Aufgaben ohne Modell laufen ohnehin sofort.';

  @override
  String get aufgDatumText =>
      'Liest bei RAW-Aufnahmen und Videos das Aufnahmedatum aus der Datei nach und rückt sie im Zeitstrahl an die richtige Stelle. Schreibt Daten um und verschiebt Dateien – deshalb mit Rückfrage.';

  @override
  String get aufgAblageTitel => 'Ablage nach Datum ordnen';

  @override
  String get aufgAblageText =>
      'Legt Aufnahmen in den Ordner ihres Aufnahmemonats, wenn sie dort nicht liegen, und legt liegengebliebene .xmp-Beipackzettel wieder neben ihr Foto. Ändert kein Datum – nur den Ort auf der Platte. Verschiebt Dateien, deshalb mit Rückfrage.';

  @override
  String get werkzOrdneAblage => 'Ordne die Ablage …';

  @override
  String get werkzAblageStimmt => 'Jede Aufnahme liegt im Ordner ihres Datums.';

  @override
  String werkzAblageBilanz(int verschoben, int gesamt) {
    return '$verschoben von $gesamt umgelegt';
  }

  @override
  String get werkzAblageFrageTitel => 'Ablage neu ordnen?';

  @override
  String get werkzAblageFrage =>
      'Aufnahmen, deren Ordner nicht zu ihrem Aufnahmedatum passt, werden in den richtigen Monatsordner verschoben. Die Aufnahmedaten selbst bleiben unverändert. In der App ändert sich dadurch nichts Sichtbares – wohl aber die Ordnerstruktur der Bibliothek auf der Platte.';

  @override
  String get werkzAblageStarten => 'Ablage ordnen';

  @override
  String aufgOffeneFotos(int anzahl) {
    return '$anzahl Fotos offen';
  }

  @override
  String aufgEingereiht(int anzahl) {
    return '$anzahl Aufgaben eingereiht.';
  }

  @override
  String get werkzZuAufgabenText =>
      'Gesichter, Vorschaubilder, Texterkennung, Orte, Schlagwörter und alles Weitere, was einen Durchgang über die Bibliothek startet. Sie stehen dort und nur dort.';

  @override
  String get aufgVorschauTitel => 'Vorschaubilder erzeugen';

  @override
  String get sperreTitel => 'Diese Bibliothek ist bereits geöffnet';

  @override
  String get sperreText =>
      'Ein anderes Fenster von Photo Vault arbeitet gerade mit denselben Daten. Zwei Fenster auf einer Bibliothek zeigen verschiedene Stände und lassen Hintergrundaufgaben doppelt laufen.\n\nEs ist nichts kaputtgegangen – diese Bibliothek wird nur nicht ein zweites Mal geöffnet.';

  @override
  String get sperreOrt => 'Ort';

  @override
  String get sperreErneut => 'Erneut versuchen';

  @override
  String get sperreNochBelegt => 'Sie ist weiterhin geöffnet.';

  @override
  String get sperreAndere => 'Andere Bibliothek öffnen';

  @override
  String get sperreBeenden => 'Photo Vault beenden';

  @override
  String get sperreAuswahlTitel => 'Andere Bibliothek öffnen';

  @override
  String get sperreAuswahlLeer =>
      'Es ist keine weitere Bibliothek eingetragen.';

  @override
  String get personVorschlag => 'Vorschlag der Wiedererkennung';

  @override
  String get personSuchenOderAnlegen => 'Person suchen oder neu anlegen';

  @override
  String get allgLeeren => 'Leeren';

  @override
  String get personNochKeine =>
      'Es gibt noch keine Person. Tippe einen Namen ein, um die erste anzulegen.';

  @override
  String personKeinTreffer(String suche) {
    return 'Keine Person heisst „$suche“. Der Knopf legt sie neu an.';
  }

  @override
  String personAnlegenAktion(String name) {
    return '„$name“ anlegen';
  }

  @override
  String get viewerGesichtAufziehen => 'Gesicht nachtragen – Rahmen aufziehen';

  @override
  String get viewerGesichtAufziehenEnde => 'Nachtragen beenden';

  @override
  String get viewerGesichtNachtragen => 'Nachgetragenes Gesicht benennen';

  @override
  String get viewerRahmenZuKlein =>
      'Der Rahmen ist zu klein. Ziehe einen Kasten um das Gesicht.';

  @override
  String get viewerRahmenNichtLesbar =>
      'Das Foto liess sich nicht lesen – kein Gesicht angelegt.';

  @override
  String get viewerAufziehenHinweis =>
      'Ziehe einen Rahmen um das fehlende Gesicht.';

  @override
  String get karteEigene => 'Eigene Karte';

  @override
  String get einstEigeneKarteTitel => 'Eigene Kartenquelle';

  @override
  String get einstEigeneKarteText =>
      'Die mitgelieferten Karten hören früh auf: OpenStreetMap liefert echte Kacheln bis Stufe 19, OpenTopoMap bis 17. Wer Hausnummern, Gebäudeumrisse oder ein Luftbild braucht, trägt hier eine eigene Quelle ein. Sie erscheint danach als vierter Eintrag im Kartenmenü.';

  @override
  String einstEigeneKarteAktiv(String name) {
    return '$name ist eingerichtet';
  }

  @override
  String get einstEigeneKarteOhne => 'Keine eigene Quelle eingerichtet';

  @override
  String get einstEigeneKarteVorlage => 'Vorlage übernehmen';

  @override
  String einstEigeneKarteVorlageGemessen(String stufe) {
    return 'bis Stufe $stufe, nachgemessen';
  }

  @override
  String einstEigeneKarteVorlageLautAnbieter(String stufe) {
    return 'bis Stufe $stufe, laut Anbieter';
  }

  @override
  String get einstEigeneKarteName => 'Name';

  @override
  String get einstEigeneKarteAdresse => 'Kacheladresse';

  @override
  String einstEigeneKarteAdresseHinweis(String muster) {
    return 'https://…/$muster.png';
  }

  @override
  String get einstEigeneKarteNennung => 'Namensnennung';

  @override
  String get einstEigeneKarteNennungHinweis =>
      '© Anbieter, © OpenStreetMap contributors';

  @override
  String get einstEigeneKarteStufe => 'Höchste Zoomstufe';

  @override
  String einstEigeneKarteSchluesselHinweis(String marke) {
    return 'Der Schlüssel gehört mit in die Adresse – ersetze $marke durch deinen eigenen.';
  }

  @override
  String einstEigeneKarteWoher(String quelle) {
    return 'Schlüssel gibt es bei $quelle';
  }

  @override
  String get einstEigeneKarteSitzung => 'Google-Sitzung holen';

  @override
  String get einstEigeneKarteSitzungText =>
      'Google liefert Kacheln erst nach einer Sitzungskennung. Trage deinen Schlüssel in die Adresse ein und hole sie hier; sie hält rund zwei Wochen.';

  @override
  String get einstEigeneKarteSitzungOk =>
      'Sitzung geholt und in die Adresse eingesetzt';

  @override
  String einstEigeneKarteSitzungFehler(String fehler) {
    return 'Google gab keine Sitzung: $fehler';
  }

  @override
  String get einstEigeneKarteSitzungOhneSchluessel =>
      'In der Adresse steht noch kein Schlüssel';

  @override
  String get einstEigeneKarteEntfernen => 'Quelle entfernen';

  @override
  String get einstEigeneKarteGespeichert => 'Eigene Kartenquelle gespeichert';

  @override
  String get einstEigeneKarteEntfernt => 'Eigene Kartenquelle entfernt';

  @override
  String get einstEigeneKarteFehlerLeer => 'Ohne Adresse geht es nicht';

  @override
  String get einstEigeneKarteFehlerHttp =>
      'Die Adresse muss mit http:// oder https:// anfangen';

  @override
  String einstEigeneKarteFehlerPlatzhalter(String teile) {
    return 'In der Adresse fehlen $teile';
  }

  @override
  String einstEigeneKarteFehlerUnbekannt(String teile) {
    return 'Die Adresse enthält einen Platzhalter in geschweiften Klammern, den die Karte nicht kennt – erlaubt sind nur $teile';
  }

  @override
  String get einstEigeneKarteFehlerNennung =>
      'Die Namensnennung ist eine Lizenzauflage und darf nicht leer bleiben';

  @override
  String get einstEigeneKarteWarnungTitel =>
      'Bevor du eine fremde Kartenquelle einschaltest';

  @override
  String get einstEigeneKarteWarnungUebermittlung =>
      'Jede Kachel ist ein Abruf bei diesem Anbieter. Er sieht daran, welchen Ausschnitt der Welt du dir gerade ansiehst, wie tief du hineinzoomst und wie lange du bleibst. Bei den mitgelieferten Karten steht am anderen Ende ein gespendeter Server ohne Konto – hier steht ein Schlüssel, der auf dich ausgestellt ist.';

  @override
  String get einstEigeneKarteWarnungOffline =>
      'Angesehene Kacheln bleiben auf der Platte und stehen auch ohne Netz wieder zur Verfügung; das Vorladen ganzer Gebiete gilt ebenso für diese Quelle. Ohne Vorladen bleibt ohne Netz grau, was du noch nie angesehen hast.';

  @override
  String get einstEigeneKarteWarnungBedingungen =>
      'Wie weit ein Anbieter das Zwischenspeichern erlaubt, steht in seinen Nutzungsregeln – manche gestatten es befristet, manche gar nicht, und Google untersagt die Offline-Nutzung ausdrücklich. Genau das tut diese App: Kacheln behalten und ohne Netz wieder zeigen. Ob das für deinen Anbieter zulässig ist, kann dir die App nicht abnehmen.';

  @override
  String get einstEigeneKarteWarnungAnnehmen => 'Verstanden, einschalten';

  @override
  String get einstEigeneKarteFehlerSchluessel =>
      'In der Adresse steht noch die Marke aus der Vorlage – setze dort deinen eigenen Schlüssel ein';

  @override
  String get aufnahmenHinzufuegen => 'Fotos hinzufügen';

  @override
  String get aufnahmenAusAktivitaetEntfernen => 'Aus der Aktivität entfernen';

  @override
  String get aufnahmenAusReiseEntfernen => 'Aus der Reise entfernen';

  @override
  String aufnahmenEntferntAktivitaet(int anzahl) {
    return '$anzahl Foto(s) aus der Aktivität entfernt';
  }

  @override
  String aufnahmenEntferntReise(int anzahl) {
    return '$anzahl Foto(s) aus der Reise entfernt';
  }

  @override
  String get auswAuswaehlen => 'Auswählen';

  @override
  String get einstKartenquellenTitel => 'Verfügbare Kartenquellen';

  @override
  String get einstKartenquellenText =>
      'Wie tief eine Karte trägt, entscheidet der Anbieter – darüber vergrössert die App nur noch. Die Angabe in Metern ist die Breite von hundert Bildpunkten auf mittlerer Breite; bei 300 m erkennt man Strassenzüge, bei 20 m einzelne Häuser.';

  @override
  String get einstKartenquellenMitgeliefert => 'mitgeliefert';

  @override
  String get einstKartenquellenVorlage => 'Vorlage';

  @override
  String einstKartenquellenTiefe(String stufe, String meter) {
    return 'bis Stufe $stufe · rund $meter';
  }

  @override
  String get einstKartenquellenGemessen => 'nachgemessen';

  @override
  String get einstKartenquellenLautAnbieter => 'laut Anbieter';

  @override
  String get einstKartenquellenSchluessel => 'Schlüssel nötig';

  @override
  String get einstKartenquellenHochaufloesend => 'liefert doppelte Auflösung';

  @override
  String get einstKartenquellenSimuliert =>
      'doppelte Auflösung wird nachgebildet';

  @override
  String get einstKartenquellenKnoepfe =>
      'Der Knopf rechts macht eine Karte zur Standardansicht – bei einer Vorlage ohne Schlüssel schaltet er sie zugleich ein. Das Vorladen weiter unten füllt den Vorrat danach für genau diese Karte.';

  @override
  String get einstKartenquellenSeite => 'Seite des Anbieters öffnen';

  @override
  String einstKartenquellenSeiteFehler(String adresse) {
    return 'Die Seite liess sich nicht öffnen: $adresse';
  }

  @override
  String get einstKartenquellenStandard => 'Standard';

  @override
  String get einstKartenquellenAlsStandard => 'Als Standard';

  @override
  String get einstKartenquellenAlsStandardHinweis =>
      'Diese Karte zeigen, sobald die Kartenansicht das nächste Mal geöffnet wird';

  @override
  String einstKartenquellenStandardGesetzt(String name) {
    return '$name ist ab dem nächsten Öffnen der Karte die Standardansicht.';
  }

  @override
  String get einstKartenquellenUebernehmen => 'Übernehmen';

  @override
  String get einstKartenquellenUebernehmenHinweis =>
      'Diese Quelle als eigene Karte einschalten und als Standard merken';

  @override
  String einstKartenquellenUebernommen(String name) {
    return '$name ist eingeschaltet und ab dem nächsten Öffnen der Karte die Standardansicht.';
  }

  @override
  String get einstKartenquellenEintragen => 'Eintragen';

  @override
  String get einstKartenquellenEintragenHinweis =>
      'Diese Vorlage unten ins Formular schreiben – der Schlüssel fehlt dann noch';

  @override
  String einstKartenquellenEingetragen(String name) {
    return '$name steht unten im Formular. Trage deinen Schlüssel ein und speichere.';
  }

  @override
  String get aufgDatumsherkunftTitel => 'Herkunft der Aufnahmedaten';

  @override
  String get aufgDatumsherkunftText =>
      'Sieht in jeder Datei nach, ob wirklich ein Aufnahmedatum darin steht. Wo keines steht, stammt das Datum aus dem Dateisystem – also vom letzten Kopieren, nicht vom Auslösen. Diese Aufnahmen werden gekennzeichnet und aus Erinnerungen und Serien herausgehalten. Im selben Zug wird der Zeitzonenversatz gelesen, den jede vierte Datei trägt.';

  @override
  String get werkzPruefeDatumsherkunft =>
      'Prüfe, woher die Aufnahmedaten stammen …';

  @override
  String get werkzAlleDatumGeprueft =>
      'Bei allen Aufnahmen wurde schon nachgesehen.';

  @override
  String get infoDatumGeschaetzt => 'Datum geschätzt – die Datei trägt keines';

  @override
  String get infoDatumGeschaetztKurz => 'geschätzt';

  @override
  String get sucheDatumGeschaetzt => 'Nur mit geschätztem Datum';

  @override
  String get ortVorschlagTitel => 'Orte von Nachbarn';

  @override
  String get ortVorschlagErklaerung =>
      'Diese Aufnahmen tragen keinen Ort – aber die Aufnahmen kurz davor und danach tun es, und sie sind sich einig. Übernommene Orte werden als geerbt gekennzeichnet: Sie sind eine begründete Vermutung, keine Messung.';

  @override
  String get ortVorschlagKeine =>
      'Keine Aufnahme lässt sich über ihre Nachbarn verorten.';

  @override
  String ortVorschlagAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String ortVorschlagBegruendung(int nachbarn, int minuten) {
    String _temp0 = intl.Intl.pluralLogic(
      nachbarn,
      locale: localeName,
      other: '$nachbarn verortete Nachbarn',
      one: '1 verorteter Nachbar',
    );
    return '$_temp0, höchstens $minuten Minuten entfernt';
  }

  @override
  String ortVorschlagAlleUebernehmen(int n) {
    return 'Alle $n übernehmen';
  }

  @override
  String get ortVorschlagAlleFrageTitel => 'Alle Vorschläge übernehmen?';

  @override
  String ortVorschlagAlleFrage(int gruppen, int aufnahmen) {
    return '$gruppen Gruppen mit zusammen $aufnahmen Aufnahmen bekommen den Ort ihrer Nachbarn. Der Ort bleibt als geerbt gekennzeichnet und lässt sich einzeln wieder entfernen.';
  }

  @override
  String get ortVorschlagWerkzTitel => 'Orte von Nachbarn erben';

  @override
  String get ortVorschlagWerkzText =>
      'Aufnahmen ohne Ort, deren zeitliche Nachbarn alle am selben Ort waren.';

  @override
  String get infoOrtGeerbt => 'Von den Nachbaraufnahmen geerbt';

  @override
  String get aufgVideobilderTitel => 'Videos: mehr als ein Standbild';

  @override
  String get aufgVideobilderText =>
      'Ein Video wurde bisher aus einem einzigen Standbild ausgewertet. Ab zehn Sekunden Laufzeit werden bis zu fünf über die Länge verteilte Bilder ausgewertet – für die Suche, die Schlagwörter und die Gesichter. Die Bilder werden nicht aufgehoben.';

  @override
  String get werkzVideobilder => 'Werte weitere Standbilder aus …';

  @override
  String get werkzAlleVideobilder =>
      'Bei allen Videos wurde schon nachgesehen.';

  @override
  String get suchoptIso => 'ISO';

  @override
  String get startFehlerTitel => 'Die Bibliothek konnte nicht geöffnet werden';

  @override
  String get startFehlerText =>
      'Photo Vault ist beim Start auf einen Fehler gestoßen. Die technischen Einzelheiten helfen bei der Fehlersuche.';

  @override
  String get startFehlerErneut => 'Erneut versuchen';

  @override
  String get befehlspaletteTitel => 'Befehl suchen';

  @override
  String get befehlspaletteHinweis => 'Bereich oder Werkzeug eingeben';

  @override
  String get befehlspaletteLeer => 'Kein passender Befehl';

  @override
  String get kuerzelBefehlspalette => 'Befehlspalette öffnen';

  @override
  String get gesundheitTitel => 'Bibliothekszustand';

  @override
  String get gesundheitWerkzeugText =>
      'Sicherung, Datenbank, Speicher und lokale Modelle gemeinsam prüfen.';

  @override
  String get gesundheitEinleitung =>
      'Hier stehen die Punkte, die darüber entscheiden, ob die Bibliothek vollständig, gesichert und arbeitsbereit ist.';

  @override
  String get gesundheitAktualisieren => 'Zustand aktualisieren';

  @override
  String get gesundheitDatenbank => 'Datenbank';

  @override
  String get gesundheitDatenbankOk =>
      'SQLite meldet keine strukturellen Fehler.';

  @override
  String get gesundheitDatenbankFehler =>
      'SQLite hat einen strukturellen Fehler gemeldet.';

  @override
  String get gesundheitIntegritaetOeffnen => 'Dateien vollständig prüfen';

  @override
  String get gesundheitSicherung => 'Automatische Sicherung';

  @override
  String get gesundheitSicherungAus =>
      'Die automatische Sicherung ist ausgeschaltet.';

  @override
  String get gesundheitSicherungNie =>
      'Die automatische Sicherung ist eingerichtet, aber noch nie erfolgreich gelaufen.';

  @override
  String gesundheitLetzteSicherung(String datum) {
    return 'Letzter erfolgreicher Lauf: $datum';
  }

  @override
  String gesundheitSicherungOffen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Aufnahmen warten auf die Sicherung.',
      one: '1 Aufnahme wartet auf die Sicherung.',
      zero: 'Alle aktuellen Aufnahmen sind gesichert.',
    );
    return '$_temp0';
  }

  @override
  String get gesundheitSpeicher => 'Speicherbelegung';

  @override
  String get gesundheitSpeicherWirdGezaehlt => 'wird gezählt …';

  @override
  String gesundheitMedien(int fotos, int videos) {
    return '$fotos Fotos, $videos Videos';
  }

  @override
  String get gesundheitModelle => 'Lokale Funktionen';

  @override
  String gesundheitModelleStand(int bereit, int gesamt) {
    return '$bereit von $gesamt lokalen Daten- und KI-Funktionen sind bereit.';
  }

  @override
  String get gesundheitOrteTitel => 'Orte zum Erben';

  @override
  String gesundheitOrteOffen(int anzahl) {
    return '$anzahl Aufnahme(n) ohne Ort haben einen verorteten Nachbarn in zeitlicher Nähe.';
  }

  @override
  String get gesundheitOrteAnsehen => 'Vorschläge ansehen';

  @override
  String get gesundheitGesichterTitel => 'Gesichter ohne Person';

  @override
  String gesundheitGesichterOffen(int anzahl) {
    return '$anzahl erkannte(s) Gesicht(er) gehören noch zu niemandem. Unter Personen lassen sie sich in Gruppen zuordnen.';
  }

  @override
  String get gesundheitGesichterZuordnen => 'Zu den Personen';

  @override
  String get gesundheitDatumTitel => 'Fragwürdige Aufnahmedaten';

  @override
  String gesundheitDatumOffen(int anzahl) {
    return '$anzahl Aufnahme(n) tragen einen Zeitstempel auf voller Stunde – bei einem echten Auslösezeitpunkt wären das rund zwei. Der Lauf sieht in der Datei nach, was wirklich dort steht.';
  }

  @override
  String get gesundheitDatumPruefen => 'Datumsherkunft prüfen';

  @override
  String get gesundheitVideobilderTitel => 'Videos aus einem Standbild';

  @override
  String gesundheitVideobilderOffen(int anzahl) {
    return '$anzahl Video(s) sind länger als zehn Sekunden und werden trotzdem nur nach ihrem ersten Standbild durchsucht.';
  }

  @override
  String get gesundheitVideobilderHolen => 'Weitere Standbilder holen';

  @override
  String get stufeWiedererkennung => 'Wiedererkennung';

  @override
  String get aufgWiedererkennungTitel => 'Wer könnte das sein?';

  @override
  String get aufgWiedererkennungText =>
      'Vergleicht namenlose Gesichter mit den benannten Personen und schlägt vor, wer zu sehen sein könnte. Zugeordnet wird nichts – das bleibt Ihre Entscheidung.';

  @override
  String get werkzWiedererkennung => 'Gesichter vergleichen';

  @override
  String get werkzAlleVerglichen => 'Alle Gesichter sind bereits verglichen.';

  @override
  String get gesundheitVorschlaegeTitel => 'Erkannte Gesichter warten';

  @override
  String gesundheitVorschlaegeOffen(int anzahl) {
    return '$anzahl namenlose(s) Gesicht(er) ähneln einer benannten Person genug für einen Vorschlag.';
  }

  @override
  String get gesundheitVorschlaegeAnsehen => 'Vorschläge ansehen';

  @override
  String get vorschlaegeTitel => 'Wer könnte das sein?';

  @override
  String get vorschlaegeEinleitung =>
      'Vorgeschlagen, nicht zugeordnet. Sie sehen je Person, was die Erkennung gefunden hat, und entscheiden.';

  @override
  String vorschlaegeAnzahl(int anzahl) {
    return '$anzahl Vorschlag/Vorschläge';
  }

  @override
  String get vorschlaegeKeine => 'Zurzeit gibt es keine Vorschläge.';

  @override
  String get vorschlaegeBeiseite => 'Beiseitegelegte einbeziehen';

  @override
  String get vorschlaegeBeiseiteHinweis =>
      'Sie haben diese Gesichter einmal weggelegt – damals gab es die heutigen Personen zum Teil noch nicht. Hier steht, was die Erkennung darin jetzt findet.';

  @override
  String get vorschlaegeBeiseiteLeer =>
      'Unter den beiseitegelegten Gesichtern findet die Erkennung nichts.';

  @override
  String get vorschlaegeLaufHinweis =>
      'Noch nichts verglichen. Der Lauf „Wer könnte das sein?“ füllt diese Liste.';

  @override
  String get gesundheitBeiseiteTitel =>
      'Beiseitegelegte Gesichter, nie verglichen';

  @override
  String gesundheitBeiseiteOffen(int anzahl) {
    return '$anzahl beiseitegelegte(s) Gesicht(er) wurden nie mit Ihren benannten Personen verglichen – weggelegt wurde, bevor es diese Personen gab.';
  }

  @override
  String get gesundheitBeiseiteAnsehen => 'Nachsehen';

  @override
  String get vorschlaegeJetztVergleichen => 'Jetzt vergleichen';

  @override
  String vorschlaegeBeiseiteNieVerglichen(int anzahl) {
    return '$anzahl beiseitegelegte(s) Gesicht(er) wurden noch nie verglichen. Der Durchgang ändert nichts – er sagt nur, wer darunter zu einer benannten Person passen könnte.';
  }

  @override
  String get vorschlaegeLaeuft => 'Der Durchgang läuft …';

  @override
  String get datenschutzExportTitel => 'Datenschutzexport';

  @override
  String get datenschutzExportText =>
      'JPEG bis 2048 Pixel, ohne EXIF, GPS oder XMP; bekannte Gesichter und erkannte Kennzeichen werden lokal unkenntlich gemacht.';

  @override
  String datenschutzAusgelassen(int anzahl) {
    return '$anzahl Aufnahme(n) ausgelassen: Videos und nicht renderbare Bilder lassen sich nicht von ihren Metadaten befreien.';
  }

  @override
  String get sicherTeilenTitel => 'Verschlüsseltes Austauschpaket';

  @override
  String get sicherTeilenText =>
      'Originale und Dateinamen in einer passwortgeschützten .pvshare-Datei weitergeben.';

  @override
  String get sicherTeilenZiel => 'Austauschpaket speichern';

  @override
  String get sicherTeilenDateiname => 'PhotoVault-Austausch.pvshare';

  @override
  String sicherTeilenFertig(String pfad) {
    return 'Verschlüsseltes Austauschpaket gespeichert: $pfad';
  }

  @override
  String sicherTeilenFehler(String fehler) {
    return 'Austauschpaket konnte nicht erstellt werden: $fehler';
  }

  @override
  String get einstPrivateMetadatenTitel => 'Private Metadaten schützen';

  @override
  String get einstPrivateMetadatenText =>
      'Entfernt bei neu gesperrten Aufnahmen Dateiname, Datum, Standort, Beschreibung, Schlagwörter und Albumzuordnungen aus der lesbaren Datenbank. Die Angaben werden mit dem Tresorschlüssel verschlüsselt und beim dauerhaften Entsperren wiederhergestellt.';

  @override
  String get gesundheitBereinigen => 'Temporäre Dateien bereinigen';

  @override
  String gesundheitBereinigt(int anzahl, String groesse) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl temporäre Dateien entfernt ($groesse).',
      one: '1 temporäre Datei entfernt ($groesse).',
      zero: 'Keine temporären Reste gefunden.',
    );
    return '$_temp0';
  }

  @override
  String get sicherTeilenImportTitel => 'Austauschpaket öffnen';

  @override
  String get sicherTeilenImportText =>
      'Eine passwortgeschützte .pvshare-Datei prüfen, entschlüsseln und in diese Bibliothek importieren.';

  @override
  String get sicherTeilenImportPassphrase => 'Passphrase des Austauschpakets';

  @override
  String sicherTeilenImportFertig(int importiert, int duplikate) {
    return '$importiert Aufnahmen importiert, $duplikate Duplikate übersprungen.';
  }

  @override
  String sicherTeilenImportFehler(String fehler) {
    return 'Austauschpaket konnte nicht geöffnet werden: $fehler';
  }

  @override
  String get gesundheitModellwechselTitel => 'KI-Ergebnisse aktualisieren';

  @override
  String gesundheitModellwechselText(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Verarbeitungen stammen von älteren Modellfassungen.',
      one: 'Eine Verarbeitung stammt von einer älteren Modellfassung.',
    );
    return '$_temp0 Die bisherigen Ergebnisse bleiben sichtbar, bis Sie die jeweilige Aufgabe vollständig neu ausführen.';
  }

  @override
  String get gesundheitModellwechselAufgaben => 'Aufgaben öffnen';

  @override
  String get einstBackupGenerationenTitel => 'Wiederherstellungspunkte';

  @override
  String get einstBackupGenerationenText =>
      'Das automatische Backup bewahrt die sieben jüngsten verschlüsselten Datenbankstände auf. Originale liegen weiterhin nur einmal im gemeinsamen verschlüsselten Datenbestand.';

  @override
  String get einstBackupWiederherstellungspunktTitel =>
      'Wiederherstellungspunkt wählen';

  @override
  String get einstBackupAktuellerStand => 'Aktueller Stand';

  @override
  String get einstBackupAktuellerStandText =>
      'Den neuesten Datenbankstand des Backups wiederherstellen.';

  @override
  String einstBackupGenerationZeit(String datum) {
    return 'Gesichert am $datum';
  }

  @override
  String get einstBackupGenerationText =>
      'Datenbankstand; die verschlüsselten Originale werden gemeinsam verwendet.';

  @override
  String get sicherTeilenAblaufTitel => 'Freigabe begrenzen?';

  @override
  String get sicherTeilenAblaufText =>
      'Optional kann dieses Austauschpaket nach einem Datum nicht mehr importiert werden.';

  @override
  String get sicherTeilenAblaufSetzen => 'Datum festlegen';

  @override
  String get sicherTeilenOhneAblauf => 'Ohne Ablauf';

  @override
  String get sicherTeilenAblaufDatum => 'Ablaufdatum auswählen';

  @override
  String get sicherTeilenImportAbgelaufen =>
      'Dieses Austauschpaket ist abgelaufen und wurde nicht importiert.';

  @override
  String get kontaktblattTitel => 'Kontaktblatt als PDF';

  @override
  String get kontaktblattText =>
      'Druckbare Übersicht mit Vorschaubildern und Aufnahmedatum erstellen.';

  @override
  String get kontaktblattZiel => 'Kontaktblatt speichern';

  @override
  String get kontaktblattDateiname => 'PhotoVault-Kontaktblatt.pdf';

  @override
  String get kontaktblattLeer =>
      'Keine ausgewählte Aufnahme lässt sich für ein Kontaktblatt darstellen.';

  @override
  String kontaktblattFertig(int enthalten, int ausgelassen) {
    return 'Kontaktblatt gespeichert: $enthalten Aufnahmen, $ausgelassen ausgelassen.';
  }

  @override
  String kontaktblattFehler(String fehler) {
    return 'Kontaktblatt konnte nicht erstellt werden: $fehler';
  }
}

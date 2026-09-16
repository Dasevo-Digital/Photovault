import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppTexte
/// returned by `AppTexte.of(context)`.
///
/// Applications need to include `AppTexte.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppTexte.localizationsDelegates,
///   supportedLocales: AppTexte.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppTexte.supportedLocales
/// property.
abstract class AppTexte {
  AppTexte(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppTexte of(BuildContext context) {
    return Localizations.of<AppTexte>(context, AppTexte)!;
  }

  static const LocalizationsDelegate<AppTexte> delegate = _AppTexteDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Verwirft einen Dialog, ohne etwas zu ändern.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get allgAbbrechen;

  /// No description provided for @allgSpeichern.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get allgSpeichern;

  /// No description provided for @allgSchliessen.
  ///
  /// In de, this message translates to:
  /// **'Schließen'**
  String get allgSchliessen;

  /// No description provided for @allgErstellen.
  ///
  /// In de, this message translates to:
  /// **'Erstellen'**
  String get allgErstellen;

  /// No description provided for @allgStarten.
  ///
  /// In de, this message translates to:
  /// **'Starten'**
  String get allgStarten;

  /// No description provided for @allgName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get allgName;

  /// No description provided for @allgMehr.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get allgMehr;

  /// No description provided for @allgAlleAnzeigen.
  ///
  /// In de, this message translates to:
  /// **'Alle anzeigen'**
  String get allgAlleAnzeigen;

  /// No description provided for @navTimeline.
  ///
  /// In de, this message translates to:
  /// **'Timeline'**
  String get navTimeline;

  /// No description provided for @navErkunden.
  ///
  /// In de, this message translates to:
  /// **'Erkunden'**
  String get navErkunden;

  /// No description provided for @navKalender.
  ///
  /// In de, this message translates to:
  /// **'Kalender'**
  String get navKalender;

  /// No description provided for @navReisen.
  ///
  /// In de, this message translates to:
  /// **'Reisen'**
  String get navReisen;

  /// No description provided for @kuerzelReisenOhne.
  ///
  /// In de, this message translates to:
  /// **'Die Reisen haben kein Kürzel – die zehn Ziffern waren vergeben, und eine Umnummerierung hätte alle eingeübten verschoben.'**
  String get kuerzelReisenOhne;

  /// No description provided for @navKarte.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get navKarte;

  /// No description provided for @navSuche.
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get navSuche;

  /// No description provided for @navPersonen.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get navPersonen;

  /// No description provided for @navAlben.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get navAlben;

  /// No description provided for @navWerkzeuge.
  ///
  /// In de, this message translates to:
  /// **'Werkzeuge'**
  String get navWerkzeuge;

  /// No description provided for @navEinstellungen.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get navEinstellungen;

  /// No description provided for @importierenTooltip.
  ///
  /// In de, this message translates to:
  /// **'Fotos/Videos importieren'**
  String get importierenTooltip;

  /// Nur sichtbar, wenn mehr als eine Bibliothek bekannt ist.
  ///
  /// In de, this message translates to:
  /// **'Geöffnete Bibliothek: {name}'**
  String geoeffneteBibliothek(String name);

  /// No description provided for @restaurierungWirdVorbereitet.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung wird vorbereitet …'**
  String get restaurierungWirdVorbereitet;

  /// No description provided for @restaurierungWartend.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 Foto in der Warteschlange für die KI-Restaurierung} other{{anzahl} Fotos in der Warteschlange für die KI-Restaurierung}}'**
  String restaurierungWartend(int anzahl);

  /// fortschritt ist entweder leer oder etwa ', 12/340' – als fertiger Text übergeben, weil er nur bei bekannter Gesamtzahl erscheint.
  ///
  /// In de, this message translates to:
  /// **'{stufe} wird berechnet (Schritt {nummer} von {gesamt}{fortschritt})'**
  String analyseLaeuft(
      String stufe, int nummer, int gesamt, String fortschritt);

  /// No description provided for @kuerzelTitel.
  ///
  /// In de, this message translates to:
  /// **'Tastaturkürzel'**
  String get kuerzelTitel;

  /// No description provided for @kuerzelRaster.
  ///
  /// In de, this message translates to:
  /// **'Raster (Zeitleiste, Kalender, Album, Suche)'**
  String get kuerzelRaster;

  /// No description provided for @kuerzelUmschaltKlick.
  ///
  /// In de, this message translates to:
  /// **'Umschalt-Klick'**
  String get kuerzelUmschaltKlick;

  /// No description provided for @kuerzelStrgKlick.
  ///
  /// In de, this message translates to:
  /// **'Strg-/⌘-Klick'**
  String get kuerzelStrgKlick;

  /// No description provided for @kuerzelUmschaltPfeil.
  ///
  /// In de, this message translates to:
  /// **'Umschalt + Pfeil'**
  String get kuerzelUmschaltPfeil;

  /// No description provided for @kuerzelBereichWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Alles bis hierher dazunehmen'**
  String get kuerzelBereichWaehlen;

  /// No description provided for @kuerzelEinzelnWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Eine einzelne Kachel umschalten'**
  String get kuerzelEinzelnWaehlen;

  /// No description provided for @kuerzelRahmenBewegen.
  ///
  /// In de, this message translates to:
  /// **'Den Rahmen durchs Raster bewegen'**
  String get kuerzelRahmenBewegen;

  /// No description provided for @kuerzelAuswahlZiehen.
  ///
  /// In de, this message translates to:
  /// **'Die Auswahl mitziehen'**
  String get kuerzelAuswahlZiehen;

  /// No description provided for @kuerzelFarbmarkeSetzen.
  ///
  /// In de, this message translates to:
  /// **'Farbmarke setzen'**
  String get kuerzelFarbmarkeSetzen;

  /// No description provided for @kuerzelAuswahlLeeren.
  ///
  /// In de, this message translates to:
  /// **'Auswahl leeren'**
  String get kuerzelAuswahlLeeren;

  /// No description provided for @kuerzelFotoOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Foto öffnen'**
  String get kuerzelFotoOeffnen;

  /// No description provided for @kuerzelWirktAuf.
  ///
  /// In de, this message translates to:
  /// **'Die Tasten wirken auf die Auswahl. Gibt es keine, wirken sie auf die Kachel, auf der der Rahmen steht.'**
  String get kuerzelWirktAuf;

  /// No description provided for @einstBeschrKuerzel.
  ///
  /// In de, this message translates to:
  /// **'Alle Tastaturkürzel auf einen Blick'**
  String get einstBeschrKuerzel;

  /// No description provided for @kuerzelNavigation.
  ///
  /// In de, this message translates to:
  /// **'Navigation'**
  String get kuerzelNavigation;

  /// No description provided for @kuerzelVollbild.
  ///
  /// In de, this message translates to:
  /// **'Vollbildansicht'**
  String get kuerzelVollbild;

  /// No description provided for @kuerzelSichtung.
  ///
  /// In de, this message translates to:
  /// **'Sichtungs-Modus (Culling)'**
  String get kuerzelSichtung;

  /// No description provided for @kuerzelBereicheWechseln.
  ///
  /// In de, this message translates to:
  /// **'Zwischen den Hauptbereichen wechseln'**
  String get kuerzelBereicheWechseln;

  /// No description provided for @kuerzelUebersichtOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Diese Übersicht öffnen'**
  String get kuerzelUebersichtOeffnen;

  /// No description provided for @kuerzelVorherigesNaechstes.
  ///
  /// In de, this message translates to:
  /// **'Vorheriges / nächstes Foto'**
  String get kuerzelVorherigesNaechstes;

  /// No description provided for @kuerzelLeertaste.
  ///
  /// In de, this message translates to:
  /// **'Leertaste'**
  String get kuerzelLeertaste;

  /// No description provided for @kuerzelNaechstesFoto.
  ///
  /// In de, this message translates to:
  /// **'Nächstes Foto'**
  String get kuerzelNaechstesFoto;

  /// No description provided for @kuerzelBewertungSetzen.
  ///
  /// In de, this message translates to:
  /// **'Sternebewertung setzen'**
  String get kuerzelBewertungSetzen;

  /// No description provided for @kuerzelFavoritUmschalten.
  ///
  /// In de, this message translates to:
  /// **'Favorit umschalten'**
  String get kuerzelFavoritUmschalten;

  /// No description provided for @kuerzelPapierkorbMitBestaetigung.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb verschieben (mit Bestätigung)'**
  String get kuerzelPapierkorbMitBestaetigung;

  /// No description provided for @kuerzelSofortAblehnen.
  ///
  /// In de, this message translates to:
  /// **'Sofort ablehnen und weiter (ohne Bestätigung)'**
  String get kuerzelSofortAblehnen;

  /// No description provided for @kuerzelZoomWischen.
  ///
  /// In de, this message translates to:
  /// **'⌘/Strg + Wischen'**
  String get kuerzelZoomWischen;

  /// No description provided for @kuerzelZoomImBild.
  ///
  /// In de, this message translates to:
  /// **'Ins Bild hinein- und herauszoomen (auch mit einer Magic Mouse)'**
  String get kuerzelZoomImBild;

  /// No description provided for @timelineLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos in der Bibliothek.'**
  String get timelineLeer;

  /// No description provided for @loeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Foto löschen?} other{{anzahl} Fotos löschen?}}'**
  String loeschenTitel(int anzahl);

  /// No description provided for @loeschenHinweis.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Wird in den Papierkorb verschoben.} other{Diese Fotos werden in den Papierkorb verschoben.}}'**
  String loeschenHinweis(int anzahl);

  /// No description provided for @albumNeu.
  ///
  /// In de, this message translates to:
  /// **'Neues Album'**
  String get albumNeu;

  /// No description provided for @albumName.
  ///
  /// In de, this message translates to:
  /// **'Albumname'**
  String get albumName;

  /// No description provided for @albenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Alben vorhanden.'**
  String get albenLeer;

  /// No description provided for @albenIntelligente.
  ///
  /// In de, this message translates to:
  /// **'Intelligente Alben'**
  String get albenIntelligente;

  /// No description provided for @albenGewoehnliche.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get albenGewoehnliche;

  /// No description provided for @albumIntelligentLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Intelligentes Album löschen'**
  String get albumIntelligentLoeschen;

  /// No description provided for @albumIntelligentLoeschenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ entfernen? Die Aufnahmen bleiben, nur die gespeicherte Suche verschwindet.'**
  String albumIntelligentLoeschenFrage(String name);

  /// No description provided for @albenIntelligentWoher.
  ///
  /// In de, this message translates to:
  /// **'Ein intelligentes Album ist eine gespeicherte Suche: Es sammelt keine Aufnahmen ein, sondern zeigt jedes Mal neu, was gerade passt. Angelegt wird es in der Suche über das Lesezeichen neben dem Suchfeld.'**
  String get albenIntelligentWoher;

  /// No description provided for @erkundenPersonen.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get erkundenPersonen;

  /// No description provided for @erkundenOrte.
  ///
  /// In de, this message translates to:
  /// **'Orte'**
  String get erkundenOrte;

  /// No description provided for @erkundenLetzteAlben.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt hinzugefügte Alben'**
  String get erkundenLetzteAlben;

  /// No description provided for @erkundenLetzteFotos.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt hinzugefügte Fotos'**
  String get erkundenLetzteFotos;

  /// No description provided for @erkundenErinnerungen.
  ///
  /// In de, this message translates to:
  /// **'Erinnerungen'**
  String get erkundenErinnerungen;

  /// No description provided for @ohneOrtLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos mit bekanntem Ort.'**
  String get ohneOrtLeer;

  /// No description provided for @karteTitel.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get karteTitel;

  /// No description provided for @karteAnsicht.
  ///
  /// In de, this message translates to:
  /// **'Kartenansicht'**
  String get karteAnsicht;

  /// No description provided for @karteTexturNachweis.
  ///
  /// In de, this message translates to:
  /// **'Erd-/Sternentextur: Solar System Scope (CC BY 4.0)'**
  String get karteTexturNachweis;

  /// No description provided for @kalenderLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos für eine Jahresübersicht.'**
  String get kalenderLeer;

  /// No description provided for @kalenderJahrLeer.
  ///
  /// In de, this message translates to:
  /// **'Keine Fotos in diesem Jahr.'**
  String get kalenderJahrLeer;

  /// No description provided for @kalenderAnzahlFotos.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{{anzahl} Foto/Video} other{{anzahl} Fotos/Videos}}'**
  String kalenderAnzahlFotos(int anzahl);

  /// No description provided for @sucheSpeichernTitel.
  ///
  /// In de, this message translates to:
  /// **'Suche speichern'**
  String get sucheSpeichernTitel;

  /// No description provided for @sucheModellFehlt.
  ///
  /// In de, this message translates to:
  /// **'Für die Kontext-Suche fehlt das Bildsuche-Modell. Es lässt sich in den Einstellungen unter „KI-Modelle“ laden.'**
  String get sucheModellFehlt;

  /// No description provided for @sucheModellLaedt.
  ///
  /// In de, this message translates to:
  /// **'Modell für die Bildsuche wird geladen …'**
  String get sucheModellLaedt;

  /// No description provided for @sucheOhneEmbeddings.
  ///
  /// In de, this message translates to:
  /// **'Noch ist kein Foto für die KI-Bildsuche ausgewertet. Der Durchgang steht unter Werkzeuge → Aufgaben („CLIP-Embeddings“).'**
  String get sucheOhneEmbeddings;

  /// No description provided for @sucheOhneTexterkennung.
  ///
  /// In de, this message translates to:
  /// **'Noch ist auf keinem Foto Text erkannt worden. Der Durchgang steht unter Werkzeuge → Aufgaben („Text erkennen (OCR)“).'**
  String get sucheOhneTexterkennung;

  /// No description provided for @sucheModellUnbrauchbar.
  ///
  /// In de, this message translates to:
  /// **'Das Modell {datei} liegt zwar auf der Platte, lässt sich aber nicht öffnen. Lade es unter Einstellungen → KI-Modelle neu – die Suche und die KI-Schlagwörter brauchen es.'**
  String sucheModellUnbrauchbar(String datei);

  /// No description provided for @sucheFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Suche fehlgeschlagen: {fehler}'**
  String sucheFehlgeschlagen(String fehler);

  /// No description provided for @suchePlatzhalterKontext.
  ///
  /// In de, this message translates to:
  /// **'z.B. „Sonnenuntergang am Meer“, „Hund im Schnee“ …'**
  String get suchePlatzhalterKontext;

  /// No description provided for @suchePlatzhalterDateiname.
  ///
  /// In de, this message translates to:
  /// **'Dateiname …'**
  String get suchePlatzhalterDateiname;

  /// No description provided for @suchePlatzhalterBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung …'**
  String get suchePlatzhalterBeschreibung;

  /// No description provided for @suchePlatzhalterText.
  ///
  /// In de, this message translates to:
  /// **'Text im Foto …'**
  String get suchePlatzhalterText;

  /// No description provided for @suchePlatzhalterBildunterschrift.
  ///
  /// In de, this message translates to:
  /// **'z.B. „dog“, „sunset“ …'**
  String get suchePlatzhalterBildunterschrift;

  /// No description provided for @werkzStaubText.
  ///
  /// In de, this message translates to:
  /// **'Untersucht eine Stichprobe der Aufnahmen einer Kamera darauf, ob an immer derselben Stelle ein dunkler Fleck sitzt.'**
  String get werkzStaubText;

  /// No description provided for @staubTitel.
  ///
  /// In de, this message translates to:
  /// **'Sensorstaub suchen'**
  String get staubTitel;

  /// No description provided for @staubErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Sensorstaub sitzt bei jeder Aufnahme derselben Kamera an derselben Stelle. Genau daran ist er zu erkennen: Die App untersucht eine über den ganzen Zeitraum verteilte Stichprobe und meldet nur, was immer wieder an derselben Stelle auftaucht. Ein einzelnes dunkles Pünktchen kann alles sein.'**
  String get staubErklaerung;

  /// No description provided for @staubKeineKameras.
  ///
  /// In de, this message translates to:
  /// **'In dieser Bibliothek ist keine Kamera vermerkt.'**
  String get staubKeineKameras;

  /// No description provided for @staubSuchen.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get staubSuchen;

  /// No description provided for @staubFortschritt.
  ///
  /// In de, this message translates to:
  /// **'{erledigt} von {gesamt} Aufnahmen untersucht'**
  String staubFortschritt(int erledigt, int gesamt);

  /// No description provided for @staubNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Auf der untersuchten Aufnahme wurde kein Sensorstaub gefunden.} other{Auf {anzahl} untersuchten Aufnahmen wurde kein Sensorstaub gefunden.}}'**
  String staubNichtsGefunden(int anzahl);

  /// No description provided for @staubGefunden.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 Stelle, die immer wieder auftaucht} other{{anzahl} Stellen, die immer wieder auftauchen}}'**
  String staubGefunden(int anzahl);

  /// No description provided for @staubAufWievielen.
  ///
  /// In de, this message translates to:
  /// **'auf {treffer} von {gesamt} untersuchten Aufnahmen'**
  String staubAufWievielen(int treffer, int gesamt);

  /// No description provided for @staubUebersprungen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} von {gesamt} Aufnahmen liessen sich nicht lesen und wurden übersprungen.'**
  String staubUebersprungen(int anzahl, int gesamt);

  /// No description provided for @staubImEditorOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Eine betroffene Aufnahme im Bildeditor öffnen'**
  String get staubImEditorOeffnen;

  /// No description provided for @allgKamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get allgKamera;

  /// No description provided for @sucheSatzVerwerfen.
  ///
  /// In de, this message translates to:
  /// **'Deutung zurücknehmen und wörtlich suchen'**
  String get sucheSatzVerwerfen;

  /// No description provided for @sucheOptionen.
  ///
  /// In de, this message translates to:
  /// **'Suchoptionen'**
  String get sucheOptionen;

  /// No description provided for @sucheAusloesen.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get sucheAusloesen;

  /// No description provided for @sucheAnleitung.
  ///
  /// In de, this message translates to:
  /// **'Gib einen Suchbegriff ein oder wähle Suchoptionen.'**
  String get sucheAnleitung;

  /// No description provided for @sucheKeineTreffer.
  ///
  /// In de, this message translates to:
  /// **'Keine Treffer.'**
  String get sucheKeineTreffer;

  /// No description provided for @viewerInfo.
  ///
  /// In de, this message translates to:
  /// **'Info'**
  String get viewerInfo;

  /// No description provided for @viewerTeilen.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get viewerTeilen;

  /// No description provided for @viewerExportieren.
  ///
  /// In de, this message translates to:
  /// **'Exportieren'**
  String get viewerExportieren;

  /// No description provided for @viewerEntwickeln.
  ///
  /// In de, this message translates to:
  /// **'Entwickeln'**
  String get viewerEntwickeln;

  /// No description provided for @viewerBearbeiten.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get viewerBearbeiten;

  /// No description provided for @viewerZuschneiden.
  ///
  /// In de, this message translates to:
  /// **'Zuschneiden'**
  String get viewerZuschneiden;

  /// No description provided for @viewerDiaschauStarten.
  ///
  /// In de, this message translates to:
  /// **'Diaschau starten'**
  String get viewerDiaschauStarten;

  /// No description provided for @viewerDiaschauStoppen.
  ///
  /// In de, this message translates to:
  /// **'Diaschau stoppen'**
  String get viewerDiaschauStoppen;

  /// No description provided for @viewerFavoritSetzen.
  ///
  /// In de, this message translates to:
  /// **'Als Favorit markieren (F)'**
  String get viewerFavoritSetzen;

  /// No description provided for @viewerFavoritEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Favorit entfernen (F)'**
  String get viewerFavoritEntfernen;

  /// No description provided for @viewerInGesperrtenOrdner.
  ///
  /// In de, this message translates to:
  /// **'In gesperrten Ordner verschieben (verschlüsselt)'**
  String get viewerInGesperrtenOrdner;

  /// No description provided for @viewerInPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb verschieben (⌫)'**
  String get viewerInPapierkorb;

  /// No description provided for @viewerVorherigesFoto.
  ///
  /// In de, this message translates to:
  /// **'Vorheriges Foto'**
  String get viewerVorherigesFoto;

  /// No description provided for @viewerNaechstesFoto.
  ///
  /// In de, this message translates to:
  /// **'Nächstes Foto'**
  String get viewerNaechstesFoto;

  /// No description provided for @viewerInTimelineZeigen.
  ///
  /// In de, this message translates to:
  /// **'Foto in der Timeline anzeigen'**
  String get viewerInTimelineZeigen;

  /// No description provided for @viewerAehnlicheZeigen.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Bilder anzeigen'**
  String get viewerAehnlicheZeigen;

  /// No description provided for @viewerMetadatenBearbeiten.
  ///
  /// In de, this message translates to:
  /// **'Metadaten bearbeiten'**
  String get viewerMetadatenBearbeiten;

  /// No description provided for @viewerGesichterBearbeiten.
  ///
  /// In de, this message translates to:
  /// **'Gesichter bearbeiten'**
  String get viewerGesichterBearbeiten;

  /// No description provided for @viewerGesichterZeigen.
  ///
  /// In de, this message translates to:
  /// **'Gesichter zeigen'**
  String get viewerGesichterZeigen;

  /// No description provided for @viewerGesichterVerbergen.
  ///
  /// In de, this message translates to:
  /// **'Gesichter verbergen'**
  String get viewerGesichterVerbergen;

  /// No description provided for @viewerKeineGesichter.
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Foto ist kein Gesicht erkannt.'**
  String get viewerKeineGesichter;

  /// No description provided for @viewerGesichtBenennen.
  ///
  /// In de, this message translates to:
  /// **'Gesicht benennen'**
  String get viewerGesichtBenennen;

  /// No description provided for @viewerEntwicklungAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Kopierte Entwicklung anwenden'**
  String get viewerEntwicklungAnwenden;

  /// No description provided for @viewerEntwicklungAnwendenLang.
  ///
  /// In de, this message translates to:
  /// **'Kopierte Entwicklung auf dieses Foto anwenden'**
  String get viewerEntwicklungAnwendenLang;

  /// No description provided for @viewerFokusPeaking.
  ///
  /// In de, this message translates to:
  /// **'Fokus-Peaking (scharfe Kanten hervorheben)'**
  String get viewerFokusPeaking;

  /// No description provided for @viewerGesichtUnscharf.
  ///
  /// In de, this message translates to:
  /// **'Auch das schärfste Gesicht ist unscharf'**
  String get viewerGesichtUnscharf;

  /// No description provided for @viewerTextZeigen.
  ///
  /// In de, this message translates to:
  /// **'Erkannten Text hervorheben'**
  String get viewerTextZeigen;

  /// No description provided for @viewerTextVerbergen.
  ///
  /// In de, this message translates to:
  /// **'Texthervorhebung ausblenden'**
  String get viewerTextVerbergen;

  /// No description provided for @viewerKeinText.
  ///
  /// In de, this message translates to:
  /// **'In diesem Foto wurde kein Text erkannt.'**
  String get viewerKeinText;

  /// No description provided for @viewerTextNochNicht.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Foto sind noch keine Textstellen gespeichert – ein Lauf der Texterkennung holt sie nach.'**
  String get viewerTextNochNicht;

  /// No description provided for @viewerZeileKopiert.
  ///
  /// In de, this message translates to:
  /// **'„{text}“ kopiert'**
  String viewerZeileKopiert(String text);

  /// No description provided for @viewerFlachesSchwenken.
  ///
  /// In de, this message translates to:
  /// **'Flaches Schwenken statt 3D-Kugel'**
  String get viewerFlachesSchwenken;

  /// No description provided for @viewerFlacheVorschau.
  ///
  /// In de, this message translates to:
  /// **'Flache Vorschau statt 360°-Ansicht'**
  String get viewerFlacheVorschau;

  /// No description provided for @viewerExportZielordner.
  ///
  /// In de, this message translates to:
  /// **'Zielordner zum Exportieren wählen'**
  String get viewerExportZielordner;

  /// No description provided for @viewerExportiert.
  ///
  /// In de, this message translates to:
  /// **'Exportiert: {dateien}'**
  String viewerExportiert(String dateien);

  /// No description provided for @viewerExportFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Export fehlgeschlagen: {fehler}'**
  String viewerExportFehlgeschlagen(String fehler);

  /// No description provided for @viewerTeilenFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Teilen fehlgeschlagen: {fehler}'**
  String viewerTeilenFehlgeschlagen(String fehler);

  /// No description provided for @personenTab.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get personenTab;

  /// No description provided for @personenUnbenannteTab.
  ///
  /// In de, this message translates to:
  /// **'Unbenannte Gesichter'**
  String get personenUnbenannteTab;

  /// No description provided for @personenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Personen angelegt. Wechsle zum Tab „Unbenannte Gesichter“, wähle ein paar Gesichter aus und ordne sie einer neuen Person zu.'**
  String get personenLeer;

  /// No description provided for @personenLangeDruecken.
  ///
  /// In de, this message translates to:
  /// **'lange drücken: zusammenführen'**
  String get personenLangeDruecken;

  /// No description provided for @personenKeineUnbenannten.
  ///
  /// In de, this message translates to:
  /// **'Keine unbenannten Gesichter (mehr). Neue erscheinen hier automatisch, sobald du weitere Fotos importierst oder erneut nach Gesichtern suchst. Einzelne kannst du auch selbst markieren: Foto öffnen, Rechtsklick → „Gesichter bearbeiten“, dann oben rechts auf „Gesicht manuell hinzufügen“.'**
  String get personenKeineUnbenannten;

  /// No description provided for @personenOhneGesichtsmodell.
  ///
  /// In de, this message translates to:
  /// **'Ohne ein Modell für die Gesichtserkennung findet Photo Vault keine Gesichter.'**
  String get personenOhneGesichtsmodell;

  /// No description provided for @personenNochNichtDurchsucht.
  ///
  /// In de, this message translates to:
  /// **'{offen, plural, =1{Eine Aufnahme ist noch nicht nach Gesichtern durchsucht.} other{{offen} Aufnahmen sind noch nicht nach Gesichtern durchsucht.}} Solange das aussteht, kann hier nichts stehen.'**
  String personenNochNichtDurchsucht(int offen);

  /// No description provided for @personenJetztSuchen.
  ///
  /// In de, this message translates to:
  /// **'Jetzt nach Gesichtern suchen'**
  String get personenJetztSuchen;

  /// No description provided for @personenSucheLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Die Gesichtssuche läuft gerade. Die ersten Funde erscheinen hier, sobald sie durch ist.'**
  String get personenSucheLaeuft;

  /// No description provided for @personenSchwellenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ähnlichkeitsschwelle einstellbar unter Werkzeuge → Gesichtserkennung.'**
  String get personenSchwellenHinweis;

  /// No description provided for @personenDoppelklickHinweis.
  ///
  /// In de, this message translates to:
  /// **'Doppelklick auf ein Gesicht öffnet das ganze Foto zur Kontrolle.'**
  String get personenDoppelklickHinweis;

  /// No description provided for @personenAutomatischGruppieren.
  ///
  /// In de, this message translates to:
  /// **'Automatisch gruppieren'**
  String get personenAutomatischGruppieren;

  /// No description provided for @personenAehnlicheAuswaehlen.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche mit auswählen'**
  String get personenAehnlicheAuswaehlen;

  /// No description provided for @personenAehnlicheAbwaehlen.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche abwählen'**
  String get personenAehnlicheAbwaehlen;

  /// No description provided for @personenZuordnen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Gesicht zuordnen} other{{anzahl} Gesichter zuordnen}}'**
  String personenZuordnen(int anzahl);

  /// No description provided for @personenModellFehlt.
  ///
  /// In de, this message translates to:
  /// **'Für die Ähnlichkeitssuche wird das SFace-Modell benötigt (siehe Einstellungen → Modelle).'**
  String get personenModellFehlt;

  /// No description provided for @personenKeineAehnlichen.
  ///
  /// In de, this message translates to:
  /// **'Keine ähnlichen Gesichter über der Schwelle {schwelle} gefunden.'**
  String personenKeineAehnlichen(String schwelle);

  /// No description provided for @personenZuWenigeFuerClustering.
  ///
  /// In de, this message translates to:
  /// **'Nicht genug unbenannte Gesichter mit Embedding für ein Clustering.'**
  String get personenZuWenigeFuerClustering;

  /// No description provided for @personenKeineGruppen.
  ///
  /// In de, this message translates to:
  /// **'Keine ähnlichen Gruppen gefunden.'**
  String get personenKeineGruppen;

  /// No description provided for @personenDauertTitel.
  ///
  /// In de, this message translates to:
  /// **'Das kann etwas dauern'**
  String get personenDauertTitel;

  /// No description provided for @personenDauertText.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} unbenannte Gesichter gefunden. Die automatische Gruppierung vergleicht jedes mit jedem und kann bei so vielen Gesichtern einige Zeit dauern (die App bleibt währenddessen bedienbar). Trotzdem starten?'**
  String personenDauertText(int anzahl);

  /// No description provided for @personenZusammenfuehrenMit.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ zusammenführen mit …'**
  String personenZusammenfuehrenMit(String name);

  /// No description provided for @personenZusammenfuehrenTitel.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen bestätigen'**
  String get personenZusammenfuehrenTitel;

  /// No description provided for @personenZusammenfuehrenText.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos von „{quelle}“ werden „{ziel}“ zugeordnet. „{quelle}“ wird danach gelöscht. Das lässt sich nicht rückgängig machen.'**
  String personenZusammenfuehrenText(String quelle, String ziel);

  /// No description provided for @personenZusammenfuehren.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get personenZusammenfuehren;

  /// No description provided for @spracheTitel.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get spracheTitel;

  /// No description provided for @spracheSystem.
  ///
  /// In de, this message translates to:
  /// **'Systemsprache'**
  String get spracheSystem;

  /// No description provided for @spracheDeutsch.
  ///
  /// In de, this message translates to:
  /// **'Deutsch'**
  String get spracheDeutsch;

  /// No description provided for @spracheEnglisch.
  ///
  /// In de, this message translates to:
  /// **'English'**
  String get spracheEnglisch;

  /// No description provided for @spracheHinweis.
  ///
  /// In de, this message translates to:
  /// **'Betrifft nur die Oberfläche. Deine Alben, Schlagwörter und Personennamen bleiben, wie sie sind.'**
  String get spracheHinweis;

  /// No description provided for @spracheVokabularTitel.
  ///
  /// In de, this message translates to:
  /// **'Schlagwort-Vokabular mitübersetzen?'**
  String get spracheVokabularTitel;

  /// No description provided for @spracheVokabularText.
  ///
  /// In de, this message translates to:
  /// **'{bekannt} der {gesamt} Begriffe im Vokabular stammen aus der mitgelieferten Startbestückung und lassen sich zuverlässig übersetzen. Bereits vergebene Schlagwörter wandern mit, es geht nichts verloren.'**
  String spracheVokabularText(int bekannt, int gesamt);

  /// No description provided for @spracheVokabularSelbstAngelegt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{} =1{Ein selbst hinzugefügter Begriff bleibt unverändert.} other{{anzahl} selbst hinzugefügte Begriffe bleiben unverändert.}}'**
  String spracheVokabularSelbstAngelegt(int anzahl);

  /// No description provided for @spracheVokabularUebersetzen.
  ///
  /// In de, this message translates to:
  /// **'Übersetzen'**
  String get spracheVokabularUebersetzen;

  /// No description provided for @spracheVokabularBehalten.
  ///
  /// In de, this message translates to:
  /// **'Unverändert lassen'**
  String get spracheVokabularBehalten;

  /// No description provided for @spracheVokabularFertig.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Begriff übersetzt.} other{{anzahl} Begriffe übersetzt.}}'**
  String spracheVokabularFertig(int anzahl);

  /// No description provided for @erkundenKeineOrte.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Orte aufgelöst (siehe Werkzeuge → Orte).'**
  String get erkundenKeineOrte;

  /// No description provided for @erkundenKeineFotos.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos importiert.'**
  String get erkundenKeineFotos;

  /// No description provided for @karteKeineOrteLang.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos mit bekanntem Ort.\n\nDer Ort wird beim Import automatisch aus den GPS-Daten eines Fotos übernommen (falls vorhanden) oder lässt sich in der Info-Ansicht eines Fotos/Videos (Vollbildvorschau → ⓘ) manuell festlegen.'**
  String get karteKeineOrteLang;

  /// No description provided for @einstOrdnerNichtGeoeffnet.
  ///
  /// In de, this message translates to:
  /// **'Ordner konnte nicht geöffnet werden: {pfad}'**
  String einstOrdnerNichtGeoeffnet(String pfad);

  /// No description provided for @einstBibWechselnTitel.
  ///
  /// In de, this message translates to:
  /// **'Zu „{name}“ wechseln?'**
  String einstBibWechselnTitel(String name);

  /// No description provided for @einstBibWechselnText.
  ///
  /// In de, this message translates to:
  /// **'Die App wird danach geschlossen und öffnet beim nächsten Start die gewählte Bibliothek.\n\nEs werden keine Fotos verschoben oder gelöscht – beide Bibliotheken bleiben unverändert an ihrem Ort.'**
  String get einstBibWechselnText;

  /// No description provided for @einstBibGewechselt.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek wurde gewechselt. Es wurden keine Daten verschoben. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen.'**
  String get einstBibGewechselt;

  /// No description provided for @einstBibHinzufuegenAuswahl.
  ///
  /// In de, this message translates to:
  /// **'Ordner einer bestehenden Bibliothek wählen – oder einen leeren Ordner für eine neue. Es wird nichts verschoben.'**
  String get einstBibHinzufuegenAuswahl;

  /// No description provided for @einstBibBestehendHinzugefuegt.
  ///
  /// In de, this message translates to:
  /// **'Bestehende Bibliothek hinzugefügt.'**
  String get einstBibBestehendHinzugefuegt;

  /// No description provided for @einstBibLeerHinzugefuegt.
  ///
  /// In de, this message translates to:
  /// **'Leerer Ordner hinzugefügt – beim Wechseln dorthin entsteht eine neue, leere Bibliothek.'**
  String get einstBibLeerHinzugefuegt;

  /// No description provided for @einstBibEntfernenTitel.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ aus der Liste entfernen?'**
  String einstBibEntfernenTitel(String name);

  /// No description provided for @einstBibEntfernenText.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek verschwindet nur aus dieser Liste. Fotos, Datenbank und Ordner bleiben unverändert erhalten und lassen sich jederzeit wieder hinzufügen.'**
  String get einstBibEntfernenText;

  /// No description provided for @einstBibNichtEntfernbar.
  ///
  /// In de, this message translates to:
  /// **'Dieser Eintrag lässt sich nicht entfernen.'**
  String get einstBibNichtEntfernbar;

  /// No description provided for @einstBibListe.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheken'**
  String get einstBibListe;

  /// No description provided for @einstBibHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek hinzufügen…'**
  String get einstBibHinzufuegen;

  /// No description provided for @einstBibAusListeEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus der Liste entfernen (löscht keine Fotos)'**
  String get einstBibAusListeEntfernen;

  /// No description provided for @einstBibNichtGefunden.
  ///
  /// In de, this message translates to:
  /// **'Ordner nicht gefunden – Laufwerk eingebunden?'**
  String get einstBibNichtGefunden;

  /// No description provided for @einstBibWechselHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ein Wechsel biegt nur um, welche Bibliothek geöffnet wird – es werden keine Fotos verschoben. Zum Verlegen der aktuellen Bibliothek an einen anderen Ort dient „Speicherort ändern\" weiter unten.'**
  String get einstBibWechselHinweis;

  /// No description provided for @einstSpeicherortTitel.
  ///
  /// In de, this message translates to:
  /// **'Speicherort der aktiven Bibliothek'**
  String get einstSpeicherortTitel;

  /// No description provided for @einstSpeicherortWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Fotos, Videos, Thumbnails und die Datenbank werden in diesen Ordner verschoben. Bitte einen bereits vorhandenen Ordner wählen (falls nötig vorher im Finder anlegen).'**
  String get einstSpeicherortWaehlen;

  /// No description provided for @einstSpeicherortZuruecksetzenTitel.
  ///
  /// In de, this message translates to:
  /// **'Speicherort zurücksetzen?'**
  String get einstSpeicherortZuruecksetzenTitel;

  /// No description provided for @einstSpeicherortZuruecksetzenText.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek wird zurück in den Standard-App-Support-Ordner verschoben. Die App wird danach automatisch geschlossen – bitte anschließend neu öffnen.'**
  String get einstSpeicherortZuruecksetzenText;

  /// No description provided for @einstSpeicherortZuruecksetzenLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Setze Speicherort zurück …'**
  String get einstSpeicherortZuruecksetzenLaeuft;

  /// No description provided for @einstSpeicherortGeaendert.
  ///
  /// In de, this message translates to:
  /// **'Der Speicherort wurde geändert. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen, damit sie die Bibliothek am neuen Ort lädt.'**
  String get einstSpeicherortGeaendert;

  /// No description provided for @einstImFinderAnzeigen.
  ///
  /// In de, this message translates to:
  /// **'Im Finder anzeigen'**
  String get einstImFinderAnzeigen;

  /// No description provided for @einstAendern.
  ///
  /// In de, this message translates to:
  /// **'Ändern…'**
  String get einstAendern;

  /// No description provided for @einstZuruecksetzen.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get einstZuruecksetzen;

  /// No description provided for @einstWirdBerechnet.
  ///
  /// In de, this message translates to:
  /// **'wird berechnet …'**
  String get einstWirdBerechnet;

  /// No description provided for @einstUeberwachtTitel.
  ///
  /// In de, this message translates to:
  /// **'Überwachter Ordner'**
  String get einstUeberwachtTitel;

  /// No description provided for @einstUeberwachtKeiner.
  ///
  /// In de, this message translates to:
  /// **'Kein Ordner eingerichtet'**
  String get einstUeberwachtKeiner;

  /// No description provided for @einstUeberwachtErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Was in einem gewählten Ordner auftaucht, wird von selbst in die Bibliothek aufgenommen – alle fünf Minuten und bei jedem Start.'**
  String get einstUeberwachtErklaerung;

  /// No description provided for @einstUeberwachtAktiv.
  ///
  /// In de, this message translates to:
  /// **'Wird alle fünf Minuten geprüft. Die Dateien bleiben dort liegen.'**
  String get einstUeberwachtAktiv;

  /// No description provided for @einstUeberwachtWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Ordner wählen…'**
  String get einstUeberwachtWaehlen;

  /// No description provided for @einstUeberwachtAndererWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Anderen Ordner…'**
  String get einstUeberwachtAndererWaehlen;

  /// No description provided for @einstUeberwachtBeenden.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr überwachen'**
  String get einstUeberwachtBeenden;

  /// No description provided for @einstUeberwachtAuswahl.
  ///
  /// In de, this message translates to:
  /// **'Ordner wählen, der laufend auf neue Fotos geprüft werden soll. Die Dateien bleiben dort liegen; sie werden nur zusätzlich in die Bibliothek aufgenommen.'**
  String get einstUeberwachtAuswahl;

  /// No description provided for @einstUeberwachtUebernommen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 neues Foto aus dem Ordner übernommen.} other{{anzahl} neue Fotos aus dem Ordner übernommen.}}'**
  String einstUeberwachtUebernommen(int anzahl);

  /// No description provided for @einstKiHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wie bei digiKam laufen alle KI-Funktionen offline auf diesem Rechner. Die Modelldateien werden nicht mitgeliefert, sondern bei Bedarf aus offiziellen Open-Source-Quellen heruntergeladen (einmalig, danach komplett offline nutzbar).'**
  String get einstKiHinweis;

  /// No description provided for @einstAutoAnalyseTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Auswertung nach dem Import automatisch nachholen'**
  String get einstAutoAnalyseTitel;

  /// No description provided for @einstAutoAnalyseText.
  ///
  /// In de, this message translates to:
  /// **'Der Import legt die Fotos nur ab und bleibt dadurch schnell. Gesichter, Texterkennung, Bildsuche und Bildbeschreibung laufen danach im Hintergrund nach. Ausgeschaltet lässt sich das jederzeit unter Werkzeuge von Hand anstoßen.'**
  String get einstAutoAnalyseText;

  /// No description provided for @einstNurErkennung.
  ///
  /// In de, this message translates to:
  /// **'Nur Erkennung aktiv (Wiedererkennung: SFace-Modell fehlt noch)'**
  String get einstNurErkennung;

  /// No description provided for @einstAufgabenTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben-Übersicht'**
  String get einstAufgabenTitel;

  /// No description provided for @einstAufgabenText.
  ///
  /// In de, this message translates to:
  /// **'Alle Auswertungen mit Anzahl noch offener Fotos, einzeln anstoßbar'**
  String get einstAufgabenText;

  /// No description provided for @einstModellLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Modell löschen'**
  String get einstModellLoeschen;

  /// No description provided for @einstModellNichtGeladen.
  ///
  /// In de, this message translates to:
  /// **'{beschreibung}\n\nDas zugehörige Modell ist noch nicht geladen.'**
  String einstModellNichtGeladen(String beschreibung);

  /// No description provided for @einstVokabularText.
  ///
  /// In de, this message translates to:
  /// **'Begriffe, die automatisch per KI-Bildsuche-Modell (CLIP) auf neu importierte Fotos angewendet werden. Änderungen hier gelten nur für künftige Fotos – um sie rückwirkend auf die vorhandene Bibliothek anzuwenden, siehe Werkzeuge → \"KI-Tags berechnen\" → \"Alle Fotos\".'**
  String get einstVokabularText;

  /// No description provided for @einstBegriffHinzufuegenFeld.
  ///
  /// In de, this message translates to:
  /// **'Begriff hinzufügen …'**
  String get einstBegriffHinzufuegenFeld;

  /// No description provided for @einstBegriffHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Begriff hinzufügen'**
  String get einstBegriffHinzufuegen;

  /// No description provided for @einstOrteText.
  ///
  /// In de, this message translates to:
  /// **'Ordnet dem GPS-Ort eines Fotos Land, Bundesland/Provinz und Stadt zu – komplett lokal über die nächstgelegene bekannte Stadt (GeoNames-Datensatz), ohne Anfrage an einen Online-Kartendienst. Für die Land-/Bundesland-/Stadt-Filter in den Suchoptionen nötig.'**
  String get einstOrteText;

  /// No description provided for @einstGeoTitel.
  ///
  /// In de, this message translates to:
  /// **'GeoNames – Städte, Länder, Bundesländer'**
  String get einstGeoTitel;

  /// No description provided for @einstGeoText.
  ///
  /// In de, this message translates to:
  /// **'Städte ab 1000 Einwohnern weltweit (~10 MB). Lizenz: {lizenz}.'**
  String einstGeoText(String lizenz);

  /// No description provided for @einstGeoLoeschen.
  ///
  /// In de, this message translates to:
  /// **'GeoNames-Datensatz löschen'**
  String get einstGeoLoeschen;

  /// No description provided for @einstGesperrtText.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselt private Fotos mit AES-256 (echte Verschlüsselung, nicht nur ein Anzeige-Filter) und blendet sie überall sonst (Timeline, Suche, Alben, Personen, Karte, Backup) aus. Ohne den PIN gibt es keine Wiederherstellung.'**
  String get einstGesperrtText;

  /// No description provided for @einstGesperrtEntsperrt.
  ///
  /// In de, this message translates to:
  /// **'PIN eingerichtet – für diese Sitzung bereits entsperrt.'**
  String get einstGesperrtEntsperrt;

  /// No description provided for @einstGesperrtOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Öffnen'**
  String get einstGesperrtOeffnen;

  /// No description provided for @einstPinAendern.
  ///
  /// In de, this message translates to:
  /// **'PIN ändern'**
  String get einstPinAendern;

  /// No description provided for @einstGesperrtAufloesenText.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos im gesperrten Ordner werden entschlüsselt und wieder normal sichtbar (Timeline, Suche, Alben, Personen, Karte, Backup). Das lässt sich nicht rückgängig machen.'**
  String get einstGesperrtAufloesenText;

  /// No description provided for @einstBackupVerschluesselungTitel.
  ///
  /// In de, this message translates to:
  /// **'Backup-Verschlüsselung'**
  String get einstBackupVerschluesselungTitel;

  /// No description provided for @einstBackupVerschluesselungText.
  ///
  /// In de, this message translates to:
  /// **'Ermöglicht, manuelle und automatische Backups mit AES-256 zu verschlüsseln. Eigene Passphrase, unabhängig vom PIN des gesperrten Ordners – ein Backup landet oft extern und muss auch ohne diesen Rechner entschlüsselbar sein.'**
  String get einstBackupVerschluesselungText;

  /// No description provided for @einstBackupEntsperrt.
  ///
  /// In de, this message translates to:
  /// **'Eingerichtet – für diese Sitzung bereits entsperrt.'**
  String get einstBackupEntsperrt;

  /// No description provided for @einstBackupGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Eingerichtet – wird beim nächsten Backup abgefragt.'**
  String get einstBackupGesperrt;

  /// No description provided for @einstBackupAendern.
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get einstBackupAendern;

  /// No description provided for @einstBackupNieGesichert.
  ///
  /// In de, this message translates to:
  /// **'Noch nie gesichert.'**
  String get einstBackupNieGesichert;

  /// No description provided for @einstBackupVerschluesseln.
  ///
  /// In de, this message translates to:
  /// **'Backup verschlüsseln'**
  String get einstBackupVerschluesseln;

  /// No description provided for @einstBackupPassphraseAbfrage.
  ///
  /// In de, this message translates to:
  /// **'Fragt bei Bedarf die Backup-Passphrase von oben ab.'**
  String get einstBackupPassphraseAbfrage;

  /// No description provided for @einstBackupZielWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Backup-Ziel wählen (z.B. dein Dropbox- oder Google-Drive-Ordner)'**
  String get einstBackupZielWaehlen;

  /// No description provided for @einstBackupOrdnerWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Backup-Ordner wählen (enthält \"PhotoVault-Backup\" bzw. \"originals\")'**
  String get einstBackupOrdnerWaehlen;

  /// No description provided for @einstBackupEntschluesselnTitel.
  ///
  /// In de, this message translates to:
  /// **'Backup-Verschlüsselung entfernen?'**
  String get einstBackupEntschluesselnTitel;

  /// No description provided for @einstBackupEntschluesselnText.
  ///
  /// In de, this message translates to:
  /// **'Neue Backups werden danach nicht mehr verschlüsselt. Bereits bestehende verschlüsselte Backups am Zielort bleiben unverändert und weiterhin nur mit der bisherigen Passphrase entschlüsselbar.'**
  String get einstBackupEntschluesselnText;

  /// No description provided for @einstBackupLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Automatisches Backup läuft …'**
  String get einstBackupLaeuft;

  /// No description provided for @einstBackupKeineNeuen.
  ///
  /// In de, this message translates to:
  /// **'Keine neuen Dateien – Datenbank-Schnappschuss wird aktualisiert.'**
  String get einstBackupKeineNeuen;

  /// No description provided for @einstBackupZielHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wähle als Ziel z.B. deinen lokalen Dropbox- oder Google-Drive-Ordner – die Desktop-App des jeweiligen Anbieters lädt die Dateien dann automatisch in die Cloud hoch.'**
  String get einstBackupZielHinweis;

  /// No description provided for @einstBackupAutoHinweis.
  ///
  /// In de, this message translates to:
  /// **'Läuft nur, während die App geöffnet ist (kein Hintergrunddienst) – prüft beim Start und danach alle 30 Minuten, ob das Intervall abgelaufen ist. Sichert immer verschlüsselt, zusätzlich zu den Originaldateien auch einen Schnappschuss der gesamten Datenbank (Gesichter, Orte, Tags, Alben, Favoriten, …), damit sich bei Datenverlust der komplette Zustand wiederherstellen lässt. Löscht am Zielort nie etwas – lokale Löschungen werden bewusst nicht nachvollzogen.'**
  String get einstBackupAutoHinweis;

  /// No description provided for @einstBackupZuerstZiel.
  ///
  /// In de, this message translates to:
  /// **'Zuerst einen Zielordner wählen.'**
  String get einstBackupZuerstZiel;

  /// No description provided for @einstBackupKeinOrdner.
  ///
  /// In de, this message translates to:
  /// **'Kein Ordner gewählt.'**
  String get einstBackupKeinOrdner;

  /// No description provided for @einstBackupAutoZielWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Zielordner für automatisches Backup wählen'**
  String get einstBackupAutoZielWaehlen;

  /// No description provided for @einstWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Wählen…'**
  String get einstWaehlen;

  /// No description provided for @einstStuendlich.
  ///
  /// In de, this message translates to:
  /// **'Stündlich'**
  String get einstStuendlich;

  /// No description provided for @einstTaeglich.
  ///
  /// In de, this message translates to:
  /// **'Täglich'**
  String get einstTaeglich;

  /// No description provided for @einstWoechentlich.
  ///
  /// In de, this message translates to:
  /// **'Wöchentlich'**
  String get einstWoechentlich;

  /// No description provided for @einstBackupGrenzeText.
  ///
  /// In de, this message translates to:
  /// **'Begrenzt, wie viel pro Durchlauf ins Ziel geschrieben wird. Sinnvoll bei Cloud-Ordnern: Der Upload kommt sonst tagelang nicht hinterher. Der Rest folgt beim nächsten Intervall.'**
  String get einstBackupGrenzeText;

  /// No description provided for @einstNieAusgefuehrt.
  ///
  /// In de, this message translates to:
  /// **'Noch nie ausgeführt.'**
  String get einstNieAusgefuehrt;

  /// No description provided for @einstBackupPassphraseGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Backup-Passphrase muss für diese Sitzung noch entsperrt werden, bevor das automatische Backup laufen kann – z.B. über \"Jetzt synchronisieren\".'**
  String get einstBackupPassphraseGesperrt;

  /// No description provided for @einstPapierkorbText.
  ///
  /// In de, this message translates to:
  /// **'Löscht in den Papierkorb verschobene Fotos/Videos nach Ablauf der gewählten Frist endgültig – unwiderruflich, auch aus dem PIN-geschützten Papierkorb des gesperrten Ordners. Standardmäßig deaktiviert.'**
  String get einstPapierkorbText;

  /// No description provided for @einstPapierkorbAus.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb-Ablauf ist standardmäßig ausgeschaltet.'**
  String get einstPapierkorbAus;

  /// No description provided for @einstResetText.
  ///
  /// In de, this message translates to:
  /// **'Löscht unwiderruflich ALLE Fotos, Videos und die gesamte Datenbank dieser Bibliothek und beginnt danach mit einer leeren Bibliothek neu. Heruntergeladene KI-Modelle und Geodaten bleiben erhalten (kein erneuter Download nötig).'**
  String get einstResetText;

  /// No description provided for @einstResetTitel.
  ///
  /// In de, this message translates to:
  /// **'Datenbank zurücksetzen'**
  String get einstResetTitel;

  /// No description provided for @einstResetKurz.
  ///
  /// In de, this message translates to:
  /// **'Löscht alle Medien und Metadaten – nicht rückgängig zu machen.'**
  String get einstResetKurz;

  /// No description provided for @einstResetKnopf.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen…'**
  String get einstResetKnopf;

  /// No description provided for @einstResetBestaetigenTitel.
  ///
  /// In de, this message translates to:
  /// **'Datenbank wirklich zurücksetzen?'**
  String get einstResetBestaetigenTitel;

  /// No description provided for @einstResetBestaetigenText.
  ///
  /// In de, this message translates to:
  /// **'Löscht UNWIDERRUFLICH alle Fotos, Videos, Thumbnails und die gesamte Datenbank dieser Bibliothek (Alben, Personen, Tags, Orte, Favoriten, gesperrter Ordner, Papierkorb, gespeicherte Suchen, …). Heruntergeladene KI-Modelle und Geodaten bleiben erhalten. Erstelle vorher ein Backup, falls du dir nicht sicher bist – diese Aktion lässt sich NICHT rückgängig machen.'**
  String get einstResetBestaetigenText;

  /// No description provided for @einstResetWort.
  ///
  /// In de, this message translates to:
  /// **'ZURÜCKSETZEN'**
  String get einstResetWort;

  /// No description provided for @einstResetEndgueltig.
  ///
  /// In de, this message translates to:
  /// **'Endgültig zurücksetzen'**
  String get einstResetEndgueltig;

  /// No description provided for @einstResetLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Lösche Bibliothek …'**
  String get einstResetLaeuft;

  /// No description provided for @einstResetFertig.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek wurde vollständig gelöscht. Die App wird jetzt geschlossen – bitte danach manuell neu öffnen, um mit einer leeren Bibliothek neu zu beginnen.'**
  String get einstResetFertig;

  /// No description provided for @einstResetFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen fehlgeschlagen'**
  String get einstResetFehlgeschlagen;

  /// No description provided for @einstUeberTitel.
  ///
  /// In de, this message translates to:
  /// **'Über diese App'**
  String get einstUeberTitel;

  /// No description provided for @einstKeineModelle.
  ///
  /// In de, this message translates to:
  /// **'Keine KI-Modelle geladen'**
  String get einstKeineModelle;

  /// No description provided for @einstModelleGeladen.
  ///
  /// In de, this message translates to:
  /// **'{geladen} von {gesamt} KI-Modellen geladen'**
  String einstModelleGeladen(int geladen, int gesamt);

  /// No description provided for @einstModelleUnbenutzt.
  ///
  /// In de, this message translates to:
  /// **'Die KI-Funktionen bleiben ohne sie unbenutzt.'**
  String get einstModelleUnbenutzt;

  /// No description provided for @einstAktualisierungHinweis.
  ///
  /// In de, this message translates to:
  /// **'Die Prüfung fragt einmalig beim öffentlichen Veröffentlichungsverzeichnis nach der neuesten Versionsnummer. Es wird nichts über die Bibliothek übertragen, und es geschieht nur auf diesen Knopfdruck – nie von selbst.'**
  String get einstAktualisierungHinweis;

  /// No description provided for @einstAktualisierungNeuer.
  ///
  /// In de, this message translates to:
  /// **'Neuere Fassung verfügbar: {version}'**
  String einstAktualisierungNeuer(String version);

  /// No description provided for @einstAktualisierungAktuell.
  ///
  /// In de, this message translates to:
  /// **'Diese Fassung ist aktuell.'**
  String get einstAktualisierungAktuell;

  /// No description provided for @einstAktualisierungFehler.
  ///
  /// In de, this message translates to:
  /// **'Prüfung fehlgeschlagen: {fehler}'**
  String einstAktualisierungFehler(String fehler);

  /// No description provided for @einstVerschiebenFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Verschieben fehlgeschlagen'**
  String get einstVerschiebenFehlgeschlagen;

  /// No description provided for @einstWechselnFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Wechseln fehlgeschlagen'**
  String get einstWechselnFehlgeschlagen;

  /// No description provided for @einstNeustartTitel.
  ///
  /// In de, this message translates to:
  /// **'Neustart erforderlich'**
  String get einstNeustartTitel;

  /// No description provided for @einstUebersetzeBeschreibungTitel.
  ///
  /// In de, this message translates to:
  /// **'Bildbeschreibungen in die Oberflächensprache übersetzen'**
  String get einstUebersetzeBeschreibungTitel;

  /// No description provided for @einstUebersetzeBeschreibungText.
  ///
  /// In de, this message translates to:
  /// **'Das Beschreibungsmodell liefert nur Englisch – es gibt kein vergleichbar kleines deutsches. Ist das Modell „Übersetzung Englisch → Deutsch“ geladen, wird jede neue Beschreibung zusätzlich übersetzt. Das englische Original bleibt erhalten, die Suche findet beide.'**
  String get einstUebersetzeBeschreibungText;

  /// No description provided for @einstUebersetzeSucheTitel.
  ///
  /// In de, this message translates to:
  /// **'Suche und Schlagwörter übersetzen'**
  String get einstUebersetzeSucheTitel;

  /// No description provided for @einstUebersetzeSucheText.
  ///
  /// In de, this message translates to:
  /// **'Der Text-Teil des Bildsuche-Modells versteht nur Englisch, das Schlagwort-Vokabular ist aber deutsch. Eingeschaltet wandern Suchanfrage und Vokabelbegriffe vorher durch die Übersetzung. An 103 Fotos gemessen trifft das bei 33 von 56 Begriffen genauer, bei 19 schlechter – und es vergibt deutlich weniger Schlagwörter. Deshalb zum Ausprobieren, nicht als Vorgabe.'**
  String get einstUebersetzeSucheText;

  /// No description provided for @allgEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get allgEntfernen;

  /// No description provided for @allgEinrichten.
  ///
  /// In de, this message translates to:
  /// **'Einrichten'**
  String get allgEinrichten;

  /// No description provided for @allgHerunterladen.
  ///
  /// In de, this message translates to:
  /// **'Herunterladen'**
  String get allgHerunterladen;

  /// No description provided for @allgAktiv.
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get allgAktiv;

  /// No description provided for @einstAbschnittErscheinungsbild.
  ///
  /// In de, this message translates to:
  /// **'Erscheinungsbild'**
  String get einstAbschnittErscheinungsbild;

  /// No description provided for @einstAbschnittModelle.
  ///
  /// In de, this message translates to:
  /// **'KI-Modelle (lokal & quelloffen)'**
  String get einstAbschnittModelle;

  /// No description provided for @einstAbschnittHintergrund.
  ///
  /// In de, this message translates to:
  /// **'Hintergrundaufgaben'**
  String get einstAbschnittHintergrund;

  /// No description provided for @einstAbschnittVokabular.
  ///
  /// In de, this message translates to:
  /// **'KI-Tagging-Vokabular'**
  String get einstAbschnittVokabular;

  /// No description provided for @einstAbschnittStandortdaten.
  ///
  /// In de, this message translates to:
  /// **'Standortdaten (lokal & quelloffen)'**
  String get einstAbschnittStandortdaten;

  /// No description provided for @einstAbschnittGesperrterOrdner.
  ///
  /// In de, this message translates to:
  /// **'Gesperrter Ordner'**
  String get einstAbschnittGesperrterOrdner;

  /// No description provided for @einstAbschnittManuellesBackup.
  ///
  /// In de, this message translates to:
  /// **'Manuelles Cloud-Backup'**
  String get einstAbschnittManuellesBackup;

  /// No description provided for @einstAbschnittAutoBackup.
  ///
  /// In de, this message translates to:
  /// **'Automatisches Backup'**
  String get einstAbschnittAutoBackup;

  /// No description provided for @einstAbschnittPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get einstAbschnittPapierkorb;

  /// No description provided for @einstAbschnittGefahrenzone.
  ///
  /// In de, this message translates to:
  /// **'Gefahrenzone'**
  String get einstAbschnittGefahrenzone;

  /// No description provided for @einstDesign.
  ///
  /// In de, this message translates to:
  /// **'Design'**
  String get einstDesign;

  /// No description provided for @einstDesignHell.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get einstDesignHell;

  /// No description provided for @einstDesignDunkel.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get einstDesignDunkel;

  /// No description provided for @einstDesignSystem.
  ///
  /// In de, this message translates to:
  /// **'System'**
  String get einstDesignSystem;

  /// No description provided for @einstUeberwachtNichtsNeues.
  ///
  /// In de, this message translates to:
  /// **'Ordner eingerichtet – nichts Neues gefunden.'**
  String get einstUeberwachtNichtsNeues;

  /// No description provided for @einstBibWechselnAktion.
  ///
  /// In de, this message translates to:
  /// **'Wechseln'**
  String get einstBibWechselnAktion;

  /// No description provided for @einstBibWechselnLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Wechsle Bibliothek …'**
  String get einstBibWechselnLaeuft;

  /// No description provided for @einstBibAktiv.
  ///
  /// In de, this message translates to:
  /// **'aktiv'**
  String get einstBibAktiv;

  /// No description provided for @einstBibImmerVorhanden.
  ///
  /// In de, this message translates to:
  /// **'immer vorhanden'**
  String get einstBibImmerVorhanden;

  /// No description provided for @einstSpeicherort.
  ///
  /// In de, this message translates to:
  /// **'Speicherort'**
  String get einstSpeicherort;

  /// No description provided for @einstSpeicherortVerschiebenLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Verschiebe Bibliothek …'**
  String get einstSpeicherortVerschiebenLaeuft;

  /// No description provided for @einstSpeicherortFortschritt.
  ///
  /// In de, this message translates to:
  /// **'{kopiert} von {gesamt} · {dateien} von {dateienGesamt} Dateien'**
  String einstSpeicherortFortschritt(
      String kopiert, String gesamt, int dateien, int dateienGesamt);

  /// No description provided for @einstSpeicherbedarf.
  ///
  /// In de, this message translates to:
  /// **'Speicherbedarf'**
  String get einstSpeicherbedarf;

  /// No description provided for @belegung_originals.
  ///
  /// In de, this message translates to:
  /// **'Originale'**
  String get belegung_originals;

  /// No description provided for @belegung_previews.
  ///
  /// In de, this message translates to:
  /// **'Vorschauen'**
  String get belegung_previews;

  /// No description provided for @belegung_thumbnails.
  ///
  /// In de, this message translates to:
  /// **'Miniaturen'**
  String get belegung_thumbnails;

  /// No description provided for @belegung_developed.
  ///
  /// In de, this message translates to:
  /// **'Entwickelte Fassungen'**
  String get belegung_developed;

  /// No description provided for @belegung_restored.
  ///
  /// In de, this message translates to:
  /// **'Restaurierte Fassungen'**
  String get belegung_restored;

  /// No description provided for @belegung_trimmed.
  ///
  /// In de, this message translates to:
  /// **'Zugeschnittene Videos'**
  String get belegung_trimmed;

  /// No description provided for @belegung_masks.
  ///
  /// In de, this message translates to:
  /// **'Masken'**
  String get belegung_masks;

  /// No description provided for @belegung_faces.
  ///
  /// In de, this message translates to:
  /// **'Gesichtsausschnitte'**
  String get belegung_faces;

  /// No description provided for @belegung_luts.
  ///
  /// In de, this message translates to:
  /// **'Farbtabellen'**
  String get belegung_luts;

  /// No description provided for @belegung_trash.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get belegung_trash;

  /// No description provided for @belegung_datenbank.
  ///
  /// In de, this message translates to:
  /// **'Datenbank'**
  String get belegung_datenbank;

  /// No description provided for @belegung_sonstiges.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get belegung_sonstiges;

  /// No description provided for @einstModellLaedt.
  ///
  /// In de, this message translates to:
  /// **'Lade „{titel}“ herunter …'**
  String einstModellLaedt(String titel);

  /// No description provided for @einstModellePruefenTitel.
  ///
  /// In de, this message translates to:
  /// **'Modelle nachrechnen'**
  String get einstModellePruefenTitel;

  /// No description provided for @einstModellePruefenText.
  ///
  /// In de, this message translates to:
  /// **'Rechnet die Prüfsumme jeder installierten Modelldatei neu und vergleicht sie mit dem Katalog. Dauert wenige Sekunden. Findet Dateien, die sich nach dem Herunterladen verändert haben – beim Herunterladen selbst wird ohnehin geprüft.'**
  String get einstModellePruefenText;

  /// No description provided for @einstModellePruefenLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Rechnet nach: {datei}'**
  String einstModellePruefenLaeuft(String datei);

  /// No description provided for @einstModellePruefenAlleGut.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Modelldatei geprüft, sie stimmt.} other{{anzahl} Modelldateien geprüft, alle stimmen.}}'**
  String einstModellePruefenAlleGut(int anzahl);

  /// No description provided for @einstModellePruefenNichtsDa.
  ///
  /// In de, this message translates to:
  /// **'Es ist kein Modell installiert.'**
  String get einstModellePruefenNichtsDa;

  /// No description provided for @einstModellePruefenBefundTitel.
  ///
  /// In de, this message translates to:
  /// **'Auffällige Modelldateien'**
  String get einstModellePruefenBefundTitel;

  /// No description provided for @einstModellePruefenBefundText.
  ///
  /// In de, this message translates to:
  /// **'Diese Dateien sind nicht die, die der Katalog nennt. Lösche das betroffene Modell und lade es neu – erst danach ist verlässlich, was es liefert.'**
  String get einstModellePruefenBefundText;

  /// No description provided for @einstModellZustandFehlt.
  ///
  /// In de, this message translates to:
  /// **'fehlt'**
  String get einstModellZustandFehlt;

  /// No description provided for @einstModellZustandZuKurz.
  ///
  /// In de, this message translates to:
  /// **'falsche Länge'**
  String get einstModellZustandZuKurz;

  /// No description provided for @einstModellZustandWeichtAb.
  ///
  /// In de, this message translates to:
  /// **'Inhalt weicht ab'**
  String get einstModellZustandWeichtAb;

  /// No description provided for @einstModelleBelegterPlatz.
  ///
  /// In de, this message translates to:
  /// **'Belegter Platz aller Modelle: {groesse}'**
  String einstModelleBelegterPlatz(String groesse);

  /// No description provided for @einstModellLizenzZeile.
  ///
  /// In de, this message translates to:
  /// **'Lizenz: {lizenz}'**
  String einstModellLizenzZeile(String lizenz);

  /// No description provided for @einstGesichtserkennungAktiv.
  ///
  /// In de, this message translates to:
  /// **'Gesichtserkennung aktiv'**
  String get einstGesichtserkennungAktiv;

  /// No description provided for @einstGesichtserkennungBeides.
  ///
  /// In de, this message translates to:
  /// **'Erkennung + Wiedererkennungs-Embeddings aktiv'**
  String get einstGesichtserkennungBeides;

  /// No description provided for @einstGesichtserkennungInaktiv.
  ///
  /// In de, this message translates to:
  /// **'Inaktiv – YuNet-Modell oben herunterladen'**
  String get einstGesichtserkennungInaktiv;

  /// No description provided for @einstGeoLaedt.
  ///
  /// In de, this message translates to:
  /// **'Lade Standortdaten herunter …'**
  String get einstGeoLaedt;

  /// No description provided for @einstPinEinrichten.
  ///
  /// In de, this message translates to:
  /// **'PIN einrichten'**
  String get einstPinEinrichten;

  /// No description provided for @einstGesperrterOrdner.
  ///
  /// In de, this message translates to:
  /// **'Gesperrter Ordner'**
  String get einstGesperrterOrdner;

  /// No description provided for @einstPinEingerichtet.
  ///
  /// In de, this message translates to:
  /// **'PIN eingerichtet.'**
  String get einstPinEingerichtet;

  /// No description provided for @einstPinEntfernen.
  ///
  /// In de, this message translates to:
  /// **'PIN entfernen'**
  String get einstPinEntfernen;

  /// No description provided for @einstGesperrtAufloesenTitel.
  ///
  /// In de, this message translates to:
  /// **'PIN-Schutz entfernen?'**
  String get einstGesperrtAufloesenTitel;

  /// No description provided for @einstSitzungSperren.
  ///
  /// In de, this message translates to:
  /// **'Sitzung jetzt sperren'**
  String get einstSitzungSperren;

  /// No description provided for @einstPassphraseEinrichten.
  ///
  /// In de, this message translates to:
  /// **'Passphrase einrichten'**
  String get einstPassphraseEinrichten;

  /// No description provided for @einstBackupPassphrase.
  ///
  /// In de, this message translates to:
  /// **'Backup-Passphrase'**
  String get einstBackupPassphrase;

  /// No description provided for @einstBackupPassphraseEingeben.
  ///
  /// In de, this message translates to:
  /// **'Backup-Passphrase eingeben'**
  String get einstBackupPassphraseEingeben;

  /// No description provided for @einstBackupSichertLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Sichere Bibliothek …'**
  String get einstBackupSichertLaeuft;

  /// No description provided for @einstBackupWiederherstellenLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Stelle Bibliothek wieder her …'**
  String get einstBackupWiederherstellenLaeuft;

  /// No description provided for @einstLetztesBackup.
  ///
  /// In de, this message translates to:
  /// **'Letztes Backup'**
  String get einstLetztesBackup;

  /// No description provided for @einstBackupZusammenfassung.
  ///
  /// In de, this message translates to:
  /// **'{datum} – {anzahl} Datei(en) nach {ziel}'**
  String einstBackupZusammenfassung(String datum, int anzahl, String ziel);

  /// No description provided for @einstJetztSichern.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichern'**
  String get einstJetztSichern;

  /// No description provided for @einstWiederherstellen.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellen'**
  String get einstWiederherstellen;

  /// No description provided for @einstBackupPruefen.
  ///
  /// In de, this message translates to:
  /// **'Backup prüfen'**
  String get einstBackupPruefen;

  /// No description provided for @einstBackupPruefungLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Prüfe Wiederherstellbarkeit …'**
  String get einstBackupPruefungLaeuft;

  /// No description provided for @einstBackupPruefungErfolgreich.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Datei(en) sind vollständig wiederherstellbar.'**
  String einstBackupPruefungErfolgreich(int anzahl);

  /// No description provided for @einstBackupPruefungFehler.
  ///
  /// In de, this message translates to:
  /// **'{gueltig} gültig, {fehlend} fehlend, {beschaedigt} beschädigt.'**
  String einstBackupPruefungFehler(int gueltig, int fehlend, int beschaedigt);

  /// No description provided for @einstZielordner.
  ///
  /// In de, this message translates to:
  /// **'Zielordner'**
  String get einstZielordner;

  /// No description provided for @einstIntervall.
  ///
  /// In de, this message translates to:
  /// **'Intervall'**
  String get einstIntervall;

  /// No description provided for @einstIntervallSechsStunden.
  ///
  /// In de, this message translates to:
  /// **'Alle 6 Stunden'**
  String get einstIntervallSechsStunden;

  /// No description provided for @einstMengeJeLauf.
  ///
  /// In de, this message translates to:
  /// **'Menge je Lauf'**
  String get einstMengeJeLauf;

  /// No description provided for @einstUnbegrenzt.
  ///
  /// In de, this message translates to:
  /// **'Unbegrenzt'**
  String get einstUnbegrenzt;

  /// No description provided for @einstLetzterLauf.
  ///
  /// In de, this message translates to:
  /// **'Letzter Lauf'**
  String get einstLetzterLauf;

  /// No description provided for @einstJetztSynchronisieren.
  ///
  /// In de, this message translates to:
  /// **'Jetzt synchronisieren'**
  String get einstJetztSynchronisieren;

  /// No description provided for @einstNachTagen.
  ///
  /// In de, this message translates to:
  /// **'Nach'**
  String get einstNachTagen;

  /// No description provided for @einstTageDropdown.
  ///
  /// In de, this message translates to:
  /// **'{tage} Tagen'**
  String einstTageDropdown(int tage);

  /// No description provided for @einstDatenbank.
  ///
  /// In de, this message translates to:
  /// **'Datenbank'**
  String get einstDatenbank;

  /// No description provided for @einstDatenbankStand.
  ///
  /// In de, this message translates to:
  /// **'Stand {version}'**
  String einstDatenbankStand(int version);

  /// No description provided for @einstBauZeile.
  ///
  /// In de, this message translates to:
  /// **'Bau {bau} · {system} {systemversion}'**
  String einstBauZeile(String bau, String system, String systemversion);

  /// No description provided for @einstLizenzen.
  ///
  /// In de, this message translates to:
  /// **'Lizenzen'**
  String get einstLizenzen;

  /// No description provided for @einstLizenzenText.
  ///
  /// In de, this message translates to:
  /// **'Die Lizenzen der mitgelieferten Schriften und aller verwendeten Bibliotheken.'**
  String get einstLizenzenText;

  /// No description provided for @einstNachAktualisierungSuchen.
  ///
  /// In de, this message translates to:
  /// **'Nach Aktualisierung suchen'**
  String get einstNachAktualisierungSuchen;

  /// No description provided for @modellYunetTitel.
  ///
  /// In de, this message translates to:
  /// **'Gesichtserkennung – YuNet'**
  String get modellYunetTitel;

  /// No description provided for @modellYunetText.
  ///
  /// In de, this message translates to:
  /// **'Erkennt Gesichter (Bounding Boxes) in Fotos. Leichtgewichtiges CNN, Teil von OpenCV Zoo.'**
  String get modellYunetText;

  /// No description provided for @modellYunetLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache-2.0'**
  String get modellYunetLizenz;

  /// No description provided for @modellSfaceTitel.
  ///
  /// In de, this message translates to:
  /// **'Gesichts-Wiedererkennung – SFace'**
  String get modellSfaceTitel;

  /// No description provided for @modellSfaceText.
  ///
  /// In de, this message translates to:
  /// **'Berechnet ein Embedding pro Gesicht, um ähnliche/gleiche Gesichter beim manuellen Zuordnen leichter zu gruppieren. Teil von OpenCV Zoo.'**
  String get modellSfaceText;

  /// No description provided for @modellSfaceLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache-2.0'**
  String get modellSfaceLizenz;

  /// No description provided for @modellClipTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Bildsuche – CLIP ViT-B/32'**
  String get modellClipTitel;

  /// No description provided for @einstAlleModelleLaden.
  ///
  /// In de, this message translates to:
  /// **'Alle fehlenden laden ({anzahl})'**
  String einstAlleModelleLaden(int anzahl);

  /// No description provided for @einstAlleModelleDa.
  ///
  /// In de, this message translates to:
  /// **'Alle Modelle liegen bereit'**
  String get einstAlleModelleDa;

  /// No description provided for @einstAlleModelleLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Modell {nummer} von {gesamt}'**
  String einstAlleModelleLaeuft(int nummer, int gesamt);

  /// No description provided for @modellClipText.
  ///
  /// In de, this message translates to:
  /// **'Ermöglicht die Suche nach Fotos in natürlicher Sprache (z.B. \"Sonnenuntergang am Meer\"). OpenAI-Originalgewichte, als separate Bild-/Text-Encoder-ONNX-Graphen exportiert.'**
  String get modellClipText;

  /// No description provided for @modellClipLizenz.
  ///
  /// In de, this message translates to:
  /// **'MIT (Gewichte: OpenAI CLIP, siehe Quelle)'**
  String get modellClipLizenz;

  /// No description provided for @modellSamTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Objektmasken – SAM ViT-Base'**
  String get modellSamTitel;

  /// No description provided for @modellSamText.
  ///
  /// In de, this message translates to:
  /// **'Erlaubt gezielte Anpassungen nur auf einem ausgewählten Bereich (z.B. nur den Himmel aufhellen) im Entwickeln-Screen, statt jede Anpassung auf das ganze Bild anzuwenden. Nutzer setzt Vordergrund-/Hintergrund-Punkte, ein promptbares Segmentierungsmodell schlägt die passende Maske vor.'**
  String get modellSamText;

  /// No description provided for @modellSamLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache-2.0 (Gewichte: Meta Segment Anything, siehe Quelle)'**
  String get modellSamLizenz;

  /// No description provided for @modellCaptionTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Bildbeschreibung – Florence-2 (Englisch)'**
  String get modellCaptionTitel;

  /// No description provided for @modellCaptionText.
  ///
  /// In de, this message translates to:
  /// **'Erzeugt automatisch eine Bildunterschrift pro Foto – für die Suche und als schnelle Übersicht. Liest dabei auch Schrift im Bild, etwa Ladenschilder oder Ortstafeln. Ausgabe ist Englisch; auf Wunsch übersetzt die App sie ins Deutsche (eigenes Modell). Ein vergleichbar kleines mehrsprachiges Modell gibt es nicht – die mehrsprachigen liegen im Gigabyte-Bereich.'**
  String get modellCaptionText;

  /// No description provided for @modellCaptionLizenz.
  ///
  /// In de, this message translates to:
  /// **'MIT (Basis: microsoft/Florence-2-base-ft, ONNX-Port: onnx-community)'**
  String get modellCaptionLizenz;

  /// No description provided for @modellOcecTitel.
  ///
  /// In de, this message translates to:
  /// **'Geschlossene-Augen-Erkennung – OCEC'**
  String get modellOcecTitel;

  /// No description provided for @modellOcecText.
  ///
  /// In de, this message translates to:
  /// **'Markiert Gesichter mit geschlossenen Augen in der Sichtung – schnelleres Aussortieren von Fotos mit Blinzlern in Porträt-/Gruppenserien.'**
  String get modellOcecText;

  /// No description provided for @modellOcecLizenz.
  ///
  /// In de, this message translates to:
  /// **'MIT'**
  String get modellOcecLizenz;

  /// No description provided for @modellEsrganTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung – Real-ESRGAN x4'**
  String get modellEsrganTitel;

  /// No description provided for @modellEsrganText.
  ///
  /// In de, this message translates to:
  /// **'Skaliert ein Foto um Faktor 4 hoch und entrauscht dabei. Läuft als Hintergrund-Warteschlange (Einstellungen/Entwickeln) und dauert je nach Fotogröße mehrere Minuten.'**
  String get modellEsrganText;

  /// No description provided for @modellEsrganLizenz.
  ///
  /// In de, this message translates to:
  /// **'BSD-3-Clause (Real-ESRGAN-Originalgewichte)'**
  String get modellEsrganLizenz;

  /// No description provided for @modellEnDeTitel.
  ///
  /// In de, this message translates to:
  /// **'Übersetzung Englisch → Deutsch – OPUS-MT'**
  String get modellEnDeTitel;

  /// No description provided for @modellEnDeText.
  ///
  /// In de, this message translates to:
  /// **'Übersetzt die automatisch erzeugten Bildbeschreibungen ins Deutsche. Das Beschreibungsmodell selbst liefert nur Englisch; ohne diese Ergänzung muss man auf Englisch suchen, was man auf Deutsch sieht. Rund 100 MB.'**
  String get modellEnDeText;

  /// No description provided for @modellEnDeLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache-2.0 (Basis: Helsinki-NLP/opus-mt-en-de, ONNX-Port: Xenova)'**
  String get modellEnDeLizenz;

  /// No description provided for @modellDeEnTitel.
  ///
  /// In de, this message translates to:
  /// **'Übersetzung Deutsch → Englisch – OPUS-MT'**
  String get modellDeEnTitel;

  /// No description provided for @modellDeEnText.
  ///
  /// In de, this message translates to:
  /// **'Übersetzt deutsche Suchanfragen und Schlagwörter, bevor sie an die KI-Bildsuche gehen – deren Text-Encoder versteht nur Englisch. Rund 100 MB.'**
  String get modellDeEnText;

  /// No description provided for @modellDeEnLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache-2.0 (Basis: Helsinki-NLP/opus-mt-de-en, ONNX-Port: Xenova)'**
  String get modellDeEnLizenz;

  /// No description provided for @werkzKeineUnbewerteten.
  ///
  /// In de, this message translates to:
  /// **'Keine unbewerteten Fotos gefunden.'**
  String get werkzKeineUnbewerteten;

  /// No description provided for @werkzKeinePassenden.
  ///
  /// In de, this message translates to:
  /// **'Keine passenden Fotos gefunden.'**
  String get werkzKeinePassenden;

  /// No description provided for @werkzGesichterScannenTitel.
  ///
  /// In de, this message translates to:
  /// **'Gesichter scannen'**
  String get werkzGesichterScannenTitel;

  /// No description provided for @werkzScanneNeue.
  ///
  /// In de, this message translates to:
  /// **'Scanne neue Fotos …'**
  String get werkzScanneNeue;

  /// No description provided for @werkzScanneAlle.
  ///
  /// In de, this message translates to:
  /// **'Scanne alle Fotos erneut …'**
  String get werkzScanneAlle;

  /// No description provided for @werkzErstelleFehlende.
  ///
  /// In de, this message translates to:
  /// **'Erstelle fehlende Vorschaubilder …'**
  String get werkzErstelleFehlende;

  /// No description provided for @werkzErstelleAlle.
  ///
  /// In de, this message translates to:
  /// **'Erstelle alle Vorschaubilder neu …'**
  String get werkzErstelleAlle;

  /// No description provided for @werkzRendereNeu.
  ///
  /// In de, this message translates to:
  /// **'Rendere entwickelte Fotos neu …'**
  String get werkzRendereNeu;

  /// No description provided for @werkzKeineEntwickelten.
  ///
  /// In de, this message translates to:
  /// **'Keine entwickelten Fotos gefunden.'**
  String get werkzKeineEntwickelten;

  /// No description provided for @werkzPruefeLivePhotos.
  ///
  /// In de, this message translates to:
  /// **'Prüfe auf Live-Photo-Paare …'**
  String get werkzPruefeLivePhotos;

  /// No description provided for @werkzKeineUnverknuepften.
  ///
  /// In de, this message translates to:
  /// **'Keine unverknüpften Fotos gefunden.'**
  String get werkzKeineUnverknuepften;

  /// No description provided for @werkzBerechneEmbeddings.
  ///
  /// In de, this message translates to:
  /// **'Berechne CLIP-Embeddings …'**
  String get werkzBerechneEmbeddings;

  /// No description provided for @werkzAlleHabenEmbedding.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos haben bereits ein Embedding.'**
  String get werkzAlleHabenEmbedding;

  /// No description provided for @werkzBerechneKiTags.
  ///
  /// In de, this message translates to:
  /// **'Berechne KI-Tags …'**
  String get werkzBerechneKiTags;

  /// No description provided for @werkzLeseOrte.
  ///
  /// In de, this message translates to:
  /// **'Lese Orte aus Fotos ein …'**
  String get werkzLeseOrte;

  /// No description provided for @werkzAlleHabenOrt.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos haben bereits einen Ort (oder keine EXIF-GPS-Daten).'**
  String get werkzAlleHabenOrt;

  /// No description provided for @werkzLoeseOrteAuf.
  ///
  /// In de, this message translates to:
  /// **'Löse Land/Bundesland/Stadt auf …'**
  String get werkzLoeseOrteAuf;

  /// No description provided for @werkzAlleAufgeloest.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos mit bekanntem Ort sind bereits aufgelöst.'**
  String get werkzAlleAufgeloest;

  /// No description provided for @werkzLeseKameradaten.
  ///
  /// In de, this message translates to:
  /// **'Lese Kameradaten aus Fotos ein …'**
  String get werkzLeseKameradaten;

  /// No description provided for @werkzAlleHabenKameradaten.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos haben bereits Kameradaten (oder keine passenden EXIF-Daten).'**
  String get werkzAlleHabenKameradaten;

  /// No description provided for @werkzSchreibeXmp.
  ///
  /// In de, this message translates to:
  /// **'Schreibe XMP-Sidecars …'**
  String get werkzSchreibeXmp;

  /// No description provided for @werkzKeineFotosGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Keine Fotos gefunden (gesperrte Fotos werden übersprungen).'**
  String get werkzKeineFotosGesperrt;

  /// No description provided for @werkzErkenneText.
  ///
  /// In de, this message translates to:
  /// **'Erkenne Text in Fotos …'**
  String get werkzErkenneText;

  /// No description provided for @werkzAlleTextDurchsucht.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos wurden bereits nach Text durchsucht.'**
  String get werkzAlleTextDurchsucht;

  /// No description provided for @werkzErzeugeBeschreibungen.
  ///
  /// In de, this message translates to:
  /// **'Erzeuge Bildbeschreibungen …'**
  String get werkzErzeugeBeschreibungen;

  /// No description provided for @werkzAlleHabenBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos haben bereits eine KI-Beschreibung.'**
  String get werkzAlleHabenBeschreibung;

  /// No description provided for @werkzBerechneUnschaerfe.
  ///
  /// In de, this message translates to:
  /// **'Berechne Unschärfe-Scores …'**
  String get werkzBerechneUnschaerfe;

  /// No description provided for @werkzAlleHabenUnschaerfe.
  ///
  /// In de, this message translates to:
  /// **'Für alle Fotos wurde bereits ein Unschärfe-Score berechnet.'**
  String get werkzAlleHabenUnschaerfe;

  /// No description provided for @werkzAbschnittStatistik.
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get werkzAbschnittStatistik;

  /// No description provided for @werkzAnalyseseiteTitel.
  ///
  /// In de, this message translates to:
  /// **'Analyseseite'**
  String get werkzAnalyseseiteTitel;

  /// No description provided for @werkzAnalyseseiteText.
  ///
  /// In de, this message translates to:
  /// **'Anzahl Fotos/Videos, Speicherplatz, Aufnahmen pro Jahr/Monat, häufigste Kameras'**
  String get werkzAnalyseseiteText;

  /// No description provided for @werkzAbschnittGesichtserkennung.
  ///
  /// In de, this message translates to:
  /// **'Gesichtserkennung'**
  String get werkzAbschnittGesichtserkennung;

  /// No description provided for @werkzSchwelleLabel.
  ///
  /// In de, this message translates to:
  /// **'Ähnlichkeitsschwelle für\n\"Ähnliche mit auswählen\"'**
  String get werkzSchwelleLabel;

  /// No description provided for @werkzSchwelleErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Höhere Werte = strengerer Abgleich (weniger, aber sicherere Treffer). Gilt für den Button \"Ähnliche mit auswählen\" im Personen-Tab bei \"Unbenannte Gesichter\".'**
  String get werkzSchwelleErklaerung;

  /// No description provided for @werkzAbschnittVorschau.
  ///
  /// In de, this message translates to:
  /// **'Vorschaubilder'**
  String get werkzAbschnittVorschau;

  /// No description provided for @werkzHeicTitel.
  ///
  /// In de, this message translates to:
  /// **'HEIC/HEIF & RAW-Unterstützung'**
  String get werkzHeicTitel;

  /// No description provided for @werkzHeicAktiv.
  ///
  /// In de, this message translates to:
  /// **'Aktiv – iPhone-Fotos (HEIC) und RAW-Dateien (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 & Co.) werden über die native macOS-Bildkonvertierung unterstützt.'**
  String get werkzHeicAktiv;

  /// No description provided for @werkzHeicInaktiv.
  ///
  /// In de, this message translates to:
  /// **'Inaktiv – native Swift-Datei muss noch ins Xcode-Projekt eingebunden werden (siehe README). JPG/PNG/WebP/GIF/BMP/TIFF funktionieren auch ohne das.'**
  String get werkzHeicInaktiv;

  /// Statuszeile der Bildumwandlung, wenn alle externen Werkzeuge da sind
  ///
  /// In de, this message translates to:
  /// **'Aktiv – iPhone-Fotos (HEIC) und RAW-Dateien (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2 & Co.) werden über die mitgelieferten Werkzeuge unterstützt.'**
  String get werkzHeicWerkzeugeAktiv;

  /// Statuszeile der Bildumwandlung, wenn Werkzeuge fehlen
  ///
  /// In de, this message translates to:
  /// **'Eingeschränkt – es fehlen: {namen}. Die davon abhängigen Formate bleiben ohne Vorschau; JPG/PNG/WebP/GIF/BMP/TIFF funktionieren weiter.'**
  String werkzHeicWerkzeugeFehlen(String namen);

  /// No description provided for @werkzNeuRendernTitel.
  ///
  /// In de, this message translates to:
  /// **'Entwickelte Fotos neu rendern'**
  String get werkzNeuRendernTitel;

  /// No description provided for @werkzAbschnittOrte.
  ///
  /// In de, this message translates to:
  /// **'Orte'**
  String get werkzAbschnittOrte;

  /// No description provided for @werkzOrteAufloesenTitel.
  ///
  /// In de, this message translates to:
  /// **'Land/Bundesland/Stadt auflösen'**
  String get werkzOrteAufloesenTitel;

  /// No description provided for @werkzAbschnittKamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get werkzAbschnittKamera;

  /// No description provided for @werkzPresetsTitel.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Presets verwalten'**
  String get werkzPresetsTitel;

  /// No description provided for @werkzPresetsText.
  ///
  /// In de, this message translates to:
  /// **'Fotos einer bestimmten Kamera automatisch beim Import einem Album/Tag zuordnen oder favorisieren – analog zu Digikams \"Kamera für den Import voreinstellen\".'**
  String get werkzPresetsText;

  /// No description provided for @werkzRegelnTitel.
  ///
  /// In de, this message translates to:
  /// **'Automatisierungsregeln verwalten'**
  String get werkzRegelnTitel;

  /// No description provided for @werkzRegelnText.
  ///
  /// In de, this message translates to:
  /// **'Fotos automatisch anhand von Ort, KI-Tag oder Aufnahmedatum einem Album/Tag zuordnen oder favorisieren – wie Kamera-Presets, nur für andere Bedingungen.'**
  String get werkzRegelnText;

  /// No description provided for @werkzAllesNachholenTitel.
  ///
  /// In de, this message translates to:
  /// **'Alle Auswertungen jetzt nachholen'**
  String get werkzAllesNachholenTitel;

  /// No description provided for @werkzAllesNachholenText.
  ///
  /// In de, this message translates to:
  /// **'Startet alle rechenintensiven Schritte nacheinander im Hintergrund: Unschärfe, Gesichter, Texterkennung, Bildsuche, Schlagwörter und Bildbeschreibung. Jeder Schritt überspringt, was er schon hat – die App bleibt bedienbar.'**
  String get werkzAllesNachholenText;

  /// No description provided for @werkzAbschnittBibliothek.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek'**
  String get werkzAbschnittBibliothek;

  /// No description provided for @werkzSichtenTitel.
  ///
  /// In de, this message translates to:
  /// **'Unbewertete Fotos sichten'**
  String get werkzSichtenTitel;

  /// No description provided for @werkzSichtenText.
  ///
  /// In de, this message translates to:
  /// **'Öffnet alle noch unbewerteten Fotos/Videos im Vollbild-Sichtungs-Modus, zum schnellen Durchgehen und Bewerten.'**
  String get werkzSichtenText;

  /// No description provided for @werkzDuplikateTitel.
  ///
  /// In de, this message translates to:
  /// **'Duplikate & ähnliche Fotos suchen'**
  String get werkzDuplikateTitel;

  /// No description provided for @werkzDuplikateText.
  ///
  /// In de, this message translates to:
  /// **'Auf Basis der CLIP-Bild-Embeddings'**
  String get werkzDuplikateText;

  /// No description provided for @werkzStapelTitel.
  ///
  /// In de, this message translates to:
  /// **'Serienbilder gruppieren'**
  String get werkzStapelTitel;

  /// No description provided for @werkzStapelText.
  ///
  /// In de, this message translates to:
  /// **'Findet zeitlich nahe, ähnliche Fotos (z.B. Serienbilder) und fasst sie auf Wunsch zu einem Stapel mit einem Titelbild zusammen.'**
  String get werkzStapelText;

  /// No description provided for @werkzIntegritaetTitel.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheks-Integritätsprüfung'**
  String get werkzIntegritaetTitel;

  /// No description provided for @werkzIntegritaetText.
  ///
  /// In de, this message translates to:
  /// **'Gleicht die Datenbank gegen die tatsächlichen Dateien auf der Platte ab: fehlende Dateien, verwaiste Dateien, optional Prüfsummen-Abweichungen.'**
  String get werkzIntegritaetText;

  /// No description provided for @werkzAbschnittInterop.
  ///
  /// In de, this message translates to:
  /// **'Interoperabilität'**
  String get werkzAbschnittInterop;

  /// No description provided for @werkzXmpSchreibenTitel.
  ///
  /// In de, this message translates to:
  /// **'XMP-Sidecars schreiben'**
  String get werkzXmpSchreibenTitel;

  /// No description provided for @werkzXmpLesenTitel.
  ///
  /// In de, this message translates to:
  /// **'XMP-Sidecars einlesen'**
  String get werkzXmpLesenTitel;

  /// No description provided for @werkzXmpLesenText.
  ///
  /// In de, this message translates to:
  /// **'Liest vorhandene .xmp-Dateien (z.B. extern in Lightroom/darktable/digiKam bearbeitet) und zeigt Abweichungen zur Datenbank – Bewertung, Farbmarkierung, Beschreibung, Tags, Standort.'**
  String get werkzXmpLesenText;

  /// No description provided for @sichtungHilfeleiste.
  ///
  /// In de, this message translates to:
  /// **'{aktuell} / {gesamt}   ·   0–5 Bewertung   ·   ⌫ Ablehnen   ·   ← → weiter'**
  String sichtungHilfeleiste(int aktuell, int gesamt);

  /// No description provided for @ansicht360.
  ///
  /// In de, this message translates to:
  /// **'360°-Ansicht'**
  String get ansicht360;

  /// Knopf unter den ausgewählten Gesichtern – knapper als der Dialogtitel.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} zuordnen'**
  String personenZuordnenKnopf(int anzahl);

  /// No description provided for @aufgStatus.
  ///
  /// In de, this message translates to:
  /// **'Status'**
  String get aufgStatus;

  /// No description provided for @aufgBereit.
  ///
  /// In de, this message translates to:
  /// **'Bereit'**
  String get aufgBereit;

  /// No description provided for @aufgLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Auswertung läuft im Hintergrund.'**
  String get aufgLaeuft;

  /// No description provided for @aufgJetztStarten.
  ///
  /// In de, this message translates to:
  /// **'Jetzt starten'**
  String get aufgJetztStarten;

  /// No description provided for @aufgWartend.
  ///
  /// In de, this message translates to:
  /// **'Wartend'**
  String get aufgWartend;

  /// No description provided for @aufgWenigerGleichzeitig.
  ///
  /// In de, this message translates to:
  /// **'Eine weniger'**
  String get aufgWenigerGleichzeitig;

  /// No description provided for @aufgMehrGleichzeitig.
  ///
  /// In de, this message translates to:
  /// **'Eine mehr'**
  String get aufgMehrGleichzeitig;

  /// No description provided for @aufgBetrifft.
  ///
  /// In de, this message translates to:
  /// **'Betrifft'**
  String get aufgBetrifft;

  /// No description provided for @aufgStufe.
  ///
  /// In de, this message translates to:
  /// **'{stufe} ({erledigt}/{gesamt}) – Stufe {nummer}/{stufenGesamt}'**
  String aufgStufe(
      String stufe, int erledigt, int gesamt, int nummer, int stufenGesamt);

  /// No description provided for @aufgModellNoetig.
  ///
  /// In de, this message translates to:
  /// **'Dafür wird zuerst {modell} benötigt ({wo}).'**
  String aufgModellNoetig(String modell, String wo);

  /// No description provided for @aufgYunetModell.
  ///
  /// In de, this message translates to:
  /// **'das YuNet-Modell'**
  String get aufgYunetModell;

  /// No description provided for @aufgClipModell.
  ///
  /// In de, this message translates to:
  /// **'das CLIP-Modell'**
  String get aufgClipModell;

  /// No description provided for @aufgBeschreibungsmodell.
  ///
  /// In de, this message translates to:
  /// **'das Bildbeschreibungs-Modell'**
  String get aufgBeschreibungsmodell;

  /// No description provided for @aufgGeoDatensatz.
  ///
  /// In de, this message translates to:
  /// **'der GeoNames-Datensatz'**
  String get aufgGeoDatensatz;

  /// No description provided for @aufgWoModelle.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen → KI-Modelle'**
  String get aufgWoModelle;

  /// No description provided for @aufgWoStandortdaten.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen → Standortdaten'**
  String get aufgWoStandortdaten;

  /// No description provided for @aufgGesichterText.
  ///
  /// In de, this message translates to:
  /// **'Erkennt und ordnet Gesichter zu, sofern das YuNet-Modell installiert ist.'**
  String get aufgGesichterText;

  /// No description provided for @aufgVorschauText.
  ///
  /// In de, this message translates to:
  /// **'Erzeugt Miniaturen und Vorschauen für Fotos und Videos. Bei einem Video entsteht dabei ein Standbild aus der ersten Sekunde – erst damit kann es überhaupt ausgewertet werden (Beschreibung, Schlagwörter, Gesichter, Text). Nach diesem Lauf lohnen die übrigen Aufgaben einen Durchgang.'**
  String get aufgVorschauText;

  /// No description provided for @aufgFehlende.
  ///
  /// In de, this message translates to:
  /// **'Fehlende'**
  String get aufgFehlende;

  /// No description provided for @aufgGesichtsschaerfeTitel.
  ///
  /// In de, this message translates to:
  /// **'Gesichtsschärfe'**
  String get aufgGesichtsschaerfeTitel;

  /// No description provided for @aufgGesichtsschaerfeText.
  ///
  /// In de, this message translates to:
  /// **'Misst für jedes erkannte Gesicht, wie scharf es ist – auf dem bereits gespeicherten Ausschnitt, ohne die Fotos erneut zu dekodieren. Beim Sichten warnt die App danach, wenn auch das schärfste Gesicht einer Aufnahme unscharf ist.'**
  String get aufgGesichtsschaerfeText;

  /// No description provided for @werkzBerechneGesichtsschaerfe.
  ///
  /// In de, this message translates to:
  /// **'Gesichtsschärfe berechnen'**
  String get werkzBerechneGesichtsschaerfe;

  /// No description provided for @aufgOcrTitel.
  ///
  /// In de, this message translates to:
  /// **'Text erkennen (OCR)'**
  String get aufgOcrTitel;

  /// No description provided for @aufgOcrText.
  ///
  /// In de, this message translates to:
  /// **'Erkennt sichtbaren Text in Fotos, rein lokal über Apples Vision-Framework.'**
  String get aufgOcrText;

  /// No description provided for @aufgBeschreibungenTitel.
  ///
  /// In de, this message translates to:
  /// **'Bildbeschreibungen'**
  String get aufgBeschreibungenTitel;

  /// No description provided for @aufgBeschreibungenText.
  ///
  /// In de, this message translates to:
  /// **'Erzeugt eine kurze, englische KI-Bildunterschrift pro Foto.'**
  String get aufgBeschreibungenText;

  /// No description provided for @aufgEmbeddingsTitel.
  ///
  /// In de, this message translates to:
  /// **'CLIP-Embeddings'**
  String get aufgEmbeddingsTitel;

  /// No description provided for @aufgEmbeddingsText.
  ///
  /// In de, this message translates to:
  /// **'Grundlage für KI-Bildsuche und Duplikatsuche.'**
  String get aufgEmbeddingsText;

  /// No description provided for @aufgKiTagsTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Tags'**
  String get aufgKiTagsTitel;

  /// No description provided for @aufgKiTagsText.
  ///
  /// In de, this message translates to:
  /// **'Ordnet Fotos automatisch passende Tags aus dem Vokabular zu (auf CLIP-Basis).'**
  String get aufgKiTagsText;

  /// No description provided for @aufgUnschaerfeTitel.
  ///
  /// In de, this message translates to:
  /// **'Unschärfe'**
  String get aufgUnschaerfeTitel;

  /// No description provided for @aufgUnschaerfeText.
  ///
  /// In de, this message translates to:
  /// **'Ermöglicht den Suchfilter \"Nur unscharfe Fotos anzeigen\".'**
  String get aufgUnschaerfeText;

  /// No description provided for @aufgOrteTitel.
  ///
  /// In de, this message translates to:
  /// **'Orte einlesen'**
  String get aufgOrteTitel;

  /// No description provided for @aufgOrteText.
  ///
  /// In de, this message translates to:
  /// **'Liest EXIF-GPS-Daten aus Fotos nachträglich ein. Die Zahl ist die der Fotos ohne Ort – wie viele davon einen in der Datei tragen, weiss erst der Durchgang.'**
  String get aufgOrteText;

  /// No description provided for @aufgOrteAufloesenText.
  ///
  /// In de, this message translates to:
  /// **'Ordnet dem GPS-Ort eines Fotos Land, Bundesland/Provinz und Stadt zu.'**
  String get aufgOrteAufloesenText;

  /// No description provided for @aufgKameraTitel.
  ///
  /// In de, this message translates to:
  /// **'Kameradaten einlesen'**
  String get aufgKameraTitel;

  /// No description provided for @aufgKameraText.
  ///
  /// In de, this message translates to:
  /// **'Liest Kamera, Objektiv, Brennweite, Blende, ISO und Belichtungszeit aus den Metadaten ein – bei Fotos aus EXIF, bei Videos aus dem Container. Die Zahl ist die der Aufnahmen ohne Kameraangabe; was gar keine Metadaten trägt, bleibt darunter.'**
  String get aufgKameraText;

  /// No description provided for @aufgDateiartTitel.
  ///
  /// In de, this message translates to:
  /// **'Dateiarten prüfen'**
  String get aufgDateiartTitel;

  /// No description provided for @aufgDateiartText.
  ///
  /// In de, this message translates to:
  /// **'Manche Standbilder kommen unter einem Videonamen an – als Video geführt fallen sie aus jeder Auswertung heraus, bekommen kein Vorschaubild und keinen Ort. Der Lauf sieht in die Bytes und berichtigt die Art. Danach lohnt ein Durchgang der übrigen Aufgaben.'**
  String get aufgDateiartText;

  /// No description provided for @werkzPruefeDateiarten.
  ///
  /// In de, this message translates to:
  /// **'Prüfe Dateiarten …'**
  String get werkzPruefeDateiarten;

  /// No description provided for @werkzAlleArtenStimmen.
  ///
  /// In de, this message translates to:
  /// **'Alle Aufnahmen sind richtig eingeordnet.'**
  String get werkzAlleArtenStimmen;

  /// No description provided for @aufgLivePhotoTitel.
  ///
  /// In de, this message translates to:
  /// **'Live-Photo-Paare prüfen'**
  String get aufgLivePhotoTitel;

  /// No description provided for @aufgLivePhotoText.
  ///
  /// In de, this message translates to:
  /// **'Verknüpft HEIC/JPG-Standbilder mit gleichnamigen MOV-Videos. Die Zahl ist die der Fotos ohne Partner – die allermeisten haben keinen und bekommen auch keinen.'**
  String get aufgLivePhotoText;

  /// No description provided for @aufgRendernText.
  ///
  /// In de, this message translates to:
  /// **'Rendert Fotos mit gespeicherten Entwicklungs-Anpassungen unverändert neu.'**
  String get aufgRendernText;

  /// No description provided for @aufgXmpText.
  ///
  /// In de, this message translates to:
  /// **'Legt für jedes Foto eine .xmp-Datei für Lightroom/darktable/digiKam daneben ab.'**
  String get aufgXmpText;

  /// No description provided for @auswAufheben.
  ///
  /// In de, this message translates to:
  /// **'Auswahl aufheben'**
  String get auswAufheben;

  /// No description provided for @auswAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} ausgewählt'**
  String auswAnzahl(int anzahl);

  /// No description provided for @auswFavorisieren.
  ///
  /// In de, this message translates to:
  /// **'Favorisieren'**
  String get auswFavorisieren;

  /// No description provided for @auswZuAlbum.
  ///
  /// In de, this message translates to:
  /// **'Zu Album hinzufügen'**
  String get auswZuAlbum;

  /// No description provided for @auswTagHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Tag hinzufügen'**
  String get auswTagHinzufuegen;

  /// No description provided for @auswBewertungSetzen.
  ///
  /// In de, this message translates to:
  /// **'Bewertung setzen'**
  String get auswBewertungSetzen;

  /// No description provided for @auswFarbeSetzen.
  ///
  /// In de, this message translates to:
  /// **'Farbmarkierung setzen'**
  String get auswFarbeSetzen;

  /// No description provided for @auswMetadaten.
  ///
  /// In de, this message translates to:
  /// **'Metadaten bearbeiten'**
  String get auswMetadaten;

  /// No description provided for @auswEntwicklungUebertragen.
  ///
  /// In de, this message translates to:
  /// **'Kopierte Entwicklung übertragen'**
  String get auswEntwicklungUebertragen;

  /// No description provided for @auswExportieren.
  ///
  /// In de, this message translates to:
  /// **'Exportieren'**
  String get auswExportieren;

  /// No description provided for @allgLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get allgLoeschen;

  /// No description provided for @allgHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get allgHinzufuegen;

  /// No description provided for @allgWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Wählen'**
  String get allgWaehlen;

  /// No description provided for @auswBewertungTitel.
  ///
  /// In de, this message translates to:
  /// **'Bewertung für {anzahl} Foto(s)'**
  String auswBewertungTitel(int anzahl);

  /// No description provided for @auswKeineBewertung.
  ///
  /// In de, this message translates to:
  /// **'Keine Bewertung'**
  String get auswKeineBewertung;

  /// No description provided for @auswFarbeTitel.
  ///
  /// In de, this message translates to:
  /// **'Farbmarkierung für {anzahl} Foto(s)'**
  String auswFarbeTitel(int anzahl);

  /// No description provided for @auswKeineFarbe.
  ///
  /// In de, this message translates to:
  /// **'Keine Farbe'**
  String get auswKeineFarbe;

  /// No description provided for @auswMetadatenTitel.
  ///
  /// In de, this message translates to:
  /// **'Metadaten für {anzahl} Foto(s) bearbeiten'**
  String auswMetadatenTitel(int anzahl);

  /// No description provided for @auswBeschreibungFeld.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung (überschreibt bestehende)'**
  String get auswBeschreibungFeld;

  /// No description provided for @auswDatumUnveraendert.
  ///
  /// In de, this message translates to:
  /// **'Datum unverändert lassen'**
  String get auswDatumUnveraendert;

  /// No description provided for @auswDatumGesetzt.
  ///
  /// In de, this message translates to:
  /// **'Datum: {datum}'**
  String auswDatumGesetzt(String datum);

  /// No description provided for @auswOrtHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ort (unverändert lassen: nicht antippen)'**
  String get auswOrtHinweis;

  /// No description provided for @auswOrtEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Ort entfernen'**
  String get auswOrtEntfernen;

  /// No description provided for @auswTagTitel.
  ///
  /// In de, this message translates to:
  /// **'Tag zu {anzahl} Foto(s) hinzufügen'**
  String auswTagTitel(int anzahl);

  /// No description provided for @auswTagFeld.
  ///
  /// In de, this message translates to:
  /// **'Tag'**
  String get auswTagFeld;

  /// No description provided for @auswExportTitel.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) exportieren'**
  String auswExportTitel(int anzahl);

  /// No description provided for @auswVorgabeAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Vorgabe anwenden'**
  String get auswVorgabeAnwenden;

  /// No description provided for @auswVorgabeAnwendenTitel.
  ///
  /// In de, this message translates to:
  /// **'Vorgabe auf {anzahl} Foto(s) anwenden'**
  String auswVorgabeAnwendenTitel(int anzahl);

  /// No description provided for @auswUebertragenTitel.
  ///
  /// In de, this message translates to:
  /// **'Entwicklung auf {anzahl} Foto(s) übertragen?'**
  String auswUebertragenTitel(int anzahl);

  /// No description provided for @auswUebertragenText.
  ///
  /// In de, this message translates to:
  /// **'Die kopierten Werte für Belichtung, Weissabgleich, Kontrast und Schatten werden übernommen; jedes Foto wird dabei neu gerendert.\n\nMasken werden nicht übertragen. Der bisherige Stand jedes Fotos bleibt in dessen Verlauf erhalten.'**
  String get auswUebertragenText;

  /// No description provided for @auswUebertragen.
  ///
  /// In de, this message translates to:
  /// **'Übertragen'**
  String get auswUebertragen;

  /// No description provided for @auswUebertrageLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Übertrage Entwicklung …'**
  String get auswUebertrageLaeuft;

  /// No description provided for @auswKeineGeeigneten.
  ///
  /// In de, this message translates to:
  /// **'Keine geeigneten Fotos – gesperrte Fotos und Videos bleiben aussen vor.'**
  String get auswKeineGeeigneten;

  /// No description provided for @auswZielordner.
  ///
  /// In de, this message translates to:
  /// **'Zielordner für {anzahl} Foto(s) wählen'**
  String auswZielordner(int anzahl);

  /// No description provided for @auswExportiereLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Exportiere … ({erledigt} / {gesamt})'**
  String auswExportiereLaeuft(int erledigt, int gesamt);

  /// No description provided for @auswExportFertig.
  ///
  /// In de, this message translates to:
  /// **'{erledigt} von {gesamt} Foto(s) exportiert nach {ziel}'**
  String auswExportFertig(int erledigt, int gesamt, String ziel);

  /// No description provided for @exportOriginal.
  ///
  /// In de, this message translates to:
  /// **'Original'**
  String get exportOriginal;

  /// No description provided for @exportGross.
  ///
  /// In de, this message translates to:
  /// **'Gross – 4096 px'**
  String get exportGross;

  /// No description provided for @exportWeb.
  ///
  /// In de, this message translates to:
  /// **'Web – 2048 px'**
  String get exportWeb;

  /// No description provided for @exportEmail.
  ///
  /// In de, this message translates to:
  /// **'E-Mail – 1024 px'**
  String get exportEmail;

  /// No description provided for @exportUnveraendert.
  ///
  /// In de, this message translates to:
  /// **'Datei unverändert, mit XMP-Datei daneben'**
  String get exportUnveraendert;

  /// No description provided for @exportJpegKante.
  ///
  /// In de, this message translates to:
  /// **'Als JPEG, lange Kante höchstens {kante} px'**
  String exportJpegKante(int kante);

  /// No description provided for @allgUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get allgUebernehmen;

  /// No description provided for @allgAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get allgAlle;

  /// No description provided for @suchoptTagsWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Tags auswählen'**
  String get suchoptTagsWaehlen;

  /// No description provided for @suchoptTagsFiltern.
  ///
  /// In de, this message translates to:
  /// **'Tags filtern …'**
  String get suchoptTagsFiltern;

  /// No description provided for @suchoptKeineTags.
  ///
  /// In de, this message translates to:
  /// **'Keine Tags gefunden.'**
  String get suchoptKeineTags;

  /// No description provided for @suchoptTitel.
  ///
  /// In de, this message translates to:
  /// **'Suchoptionen'**
  String get suchoptTitel;

  /// No description provided for @suchoptKeineTreffer.
  ///
  /// In de, this message translates to:
  /// **'Keine Fotos gefunden – diese Filterkombination liefert 0 Treffer.'**
  String get suchoptKeineTreffer;

  /// No description provided for @suchoptAllesLeeren.
  ///
  /// In de, this message translates to:
  /// **'Alles leeren'**
  String get suchoptAllesLeeren;

  /// No description provided for @suchoptSuchen.
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get suchoptSuchen;

  /// No description provided for @suchoptPersonenFiltern.
  ///
  /// In de, this message translates to:
  /// **'Personen filtern'**
  String get suchoptPersonenFiltern;

  /// No description provided for @suchoptKeinePersonenBenannt.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Personen benannt.'**
  String get suchoptKeinePersonenBenannt;

  /// No description provided for @suchoptKeinePersonenGefunden.
  ///
  /// In de, this message translates to:
  /// **'Keine Personen gefunden.'**
  String get suchoptKeinePersonenGefunden;

  /// No description provided for @suchoptTypTitel.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Typ'**
  String get suchoptTypTitel;

  /// No description provided for @suchoptTypKontext.
  ///
  /// In de, this message translates to:
  /// **'Kontext'**
  String get suchoptTypKontext;

  /// No description provided for @suchoptTypDateiname.
  ///
  /// In de, this message translates to:
  /// **'Dateiname'**
  String get suchoptTypDateiname;

  /// No description provided for @suchoptTypBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get suchoptTypBeschreibung;

  /// No description provided for @suchoptTypOcr.
  ///
  /// In de, this message translates to:
  /// **'Text im Foto (OCR)'**
  String get suchoptTypOcr;

  /// No description provided for @suchoptTypCaption.
  ///
  /// In de, this message translates to:
  /// **'KI-Beschreibung (Englisch)'**
  String get suchoptTypCaption;

  /// No description provided for @suchoptNachKontext.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Kontext'**
  String get suchoptNachKontext;

  /// No description provided for @suchoptNachDateiname.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Dateiname'**
  String get suchoptNachDateiname;

  /// No description provided for @suchoptNachBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Beschreibung'**
  String get suchoptNachBeschreibung;

  /// No description provided for @suchoptNachOcr.
  ///
  /// In de, this message translates to:
  /// **'Suche nach erkanntem Text im Foto'**
  String get suchoptNachOcr;

  /// No description provided for @suchoptNachCaption.
  ///
  /// In de, this message translates to:
  /// **'Suche nach KI-Beschreibung (Englisch)'**
  String get suchoptNachCaption;

  /// No description provided for @suchoptHintKontext.
  ///
  /// In de, this message translates to:
  /// **'z.B. \"Sonnenaufgang am Strand\", \"Hund im Schnee\" …'**
  String get suchoptHintKontext;

  /// No description provided for @suchoptHintDateiname.
  ///
  /// In de, this message translates to:
  /// **'Dateiname …'**
  String get suchoptHintDateiname;

  /// No description provided for @suchoptHintBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung …'**
  String get suchoptHintBeschreibung;

  /// No description provided for @suchoptHintOcr.
  ///
  /// In de, this message translates to:
  /// **'Text im Foto …'**
  String get suchoptHintOcr;

  /// No description provided for @suchoptHintCaption.
  ///
  /// In de, this message translates to:
  /// **'z.B. \"dog\", \"sunset\" (Englisch) …'**
  String get suchoptHintCaption;

  /// No description provided for @suchoptClipFehlt.
  ///
  /// In de, this message translates to:
  /// **'KI-Bildsuche nicht verfügbar – Modell fehlt (siehe Einstellungen → KI-Modelle).'**
  String get suchoptClipFehlt;

  /// No description provided for @suchoptCaptionFehlt.
  ///
  /// In de, this message translates to:
  /// **'KI-Bildbeschreibung nicht verfügbar – Modell fehlt (siehe Einstellungen → KI-Modelle).'**
  String get suchoptCaptionFehlt;

  /// No description provided for @suchoptTagsTitel.
  ///
  /// In de, this message translates to:
  /// **'Tags'**
  String get suchoptTagsTitel;

  /// No description provided for @suchoptTagsHint.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Tags …'**
  String get suchoptTagsHint;

  /// No description provided for @suchoptOhneTag.
  ///
  /// In de, this message translates to:
  /// **'Ohne Tag'**
  String get suchoptOhneTag;

  /// No description provided for @suchoptMindestbewertung.
  ///
  /// In de, this message translates to:
  /// **'Mindestbewertung'**
  String get suchoptMindestbewertung;

  /// No description provided for @suchoptFarbmarkierung.
  ///
  /// In de, this message translates to:
  /// **'Farbmarkierung'**
  String get suchoptFarbmarkierung;

  /// No description provided for @suchoptDateiformat.
  ///
  /// In de, this message translates to:
  /// **'Dateiformat'**
  String get suchoptDateiformat;

  /// No description provided for @suchoptNurRaw.
  ///
  /// In de, this message translates to:
  /// **'Nur RAW'**
  String get suchoptNurRaw;

  /// No description provided for @farbeRot.
  ///
  /// In de, this message translates to:
  /// **'Rot'**
  String get farbeRot;

  /// No description provided for @farbeGelb.
  ///
  /// In de, this message translates to:
  /// **'Gelb'**
  String get farbeGelb;

  /// No description provided for @farbeGruen.
  ///
  /// In de, this message translates to:
  /// **'Grün'**
  String get farbeGruen;

  /// No description provided for @farbeBlau.
  ///
  /// In de, this message translates to:
  /// **'Blau'**
  String get farbeBlau;

  /// No description provided for @farbeLila.
  ///
  /// In de, this message translates to:
  /// **'Lila'**
  String get farbeLila;

  /// No description provided for @suchoptAufnahmewerte.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmewerte'**
  String get suchoptAufnahmewerte;

  /// No description provided for @suchoptIsoVon.
  ///
  /// In de, this message translates to:
  /// **'ISO von'**
  String get suchoptIsoVon;

  /// No description provided for @suchoptIsoBis.
  ///
  /// In de, this message translates to:
  /// **'ISO bis'**
  String get suchoptIsoBis;

  /// No description provided for @suchoptBlendeVon.
  ///
  /// In de, this message translates to:
  /// **'Blende von (f/…)'**
  String get suchoptBlendeVon;

  /// No description provided for @suchoptBlendeBis.
  ///
  /// In de, this message translates to:
  /// **'Blende bis (f/…)'**
  String get suchoptBlendeBis;

  /// No description provided for @suchoptBrennweiteVon.
  ///
  /// In de, this message translates to:
  /// **'Brennweite von (mm)'**
  String get suchoptBrennweiteVon;

  /// No description provided for @suchoptBrennweiteBis.
  ///
  /// In de, this message translates to:
  /// **'Brennweite bis (mm)'**
  String get suchoptBrennweiteBis;

  /// No description provided for @suchoptNurUnscharfe.
  ///
  /// In de, this message translates to:
  /// **'Nur unscharfe Fotos anzeigen'**
  String get suchoptNurUnscharfe;

  /// No description provided for @suchoptMarke.
  ///
  /// In de, this message translates to:
  /// **'Marke'**
  String get suchoptMarke;

  /// No description provided for @suchoptModell.
  ///
  /// In de, this message translates to:
  /// **'Modell'**
  String get suchoptModell;

  /// No description provided for @suchoptObjektiv.
  ///
  /// In de, this message translates to:
  /// **'Objektiv'**
  String get suchoptObjektiv;

  /// No description provided for @suchoptOrtTitel.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get suchoptOrtTitel;

  /// No description provided for @suchoptLand.
  ///
  /// In de, this message translates to:
  /// **'Land'**
  String get suchoptLand;

  /// No description provided for @suchoptBundesland.
  ///
  /// In de, this message translates to:
  /// **'Bundesland'**
  String get suchoptBundesland;

  /// No description provided for @suchoptStadt.
  ///
  /// In de, this message translates to:
  /// **'Stadt'**
  String get suchoptStadt;

  /// No description provided for @suchoptGeoFehlt.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Orte aufgelöst – GeoNames-Datensatz herunterladen und Fotos auflösen (siehe Einstellungen → Standortdaten, Werkzeuge → Orte).'**
  String get suchoptGeoFehlt;

  /// No description provided for @suchoptAnfangsdatum.
  ///
  /// In de, this message translates to:
  /// **'Anfangsdatum'**
  String get suchoptAnfangsdatum;

  /// No description provided for @suchoptEnddatum.
  ///
  /// In de, this message translates to:
  /// **'Enddatum'**
  String get suchoptEnddatum;

  /// No description provided for @suchoptDatumEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Datum entfernen'**
  String get suchoptDatumEntfernen;

  /// No description provided for @suchoptDatumPlatzhalter.
  ///
  /// In de, this message translates to:
  /// **'tt.mm.jjjj'**
  String get suchoptDatumPlatzhalter;

  /// No description provided for @suchoptMedientyp.
  ///
  /// In de, this message translates to:
  /// **'Medientyp'**
  String get suchoptMedientyp;

  /// No description provided for @suchoptBild.
  ///
  /// In de, this message translates to:
  /// **'Bild'**
  String get suchoptBild;

  /// No description provided for @suchoptVideo.
  ///
  /// In de, this message translates to:
  /// **'Video'**
  String get suchoptVideo;

  /// No description provided for @suchoptAnzeigeoptionen.
  ///
  /// In de, this message translates to:
  /// **'Anzeigeoptionen'**
  String get suchoptAnzeigeoptionen;

  /// No description provided for @suchoptInKeinemAlbum.
  ///
  /// In de, this message translates to:
  /// **'In keinem Album'**
  String get suchoptInKeinemAlbum;

  /// No description provided for @suchoptFavoriten.
  ///
  /// In de, this message translates to:
  /// **'Favoriten'**
  String get suchoptFavoriten;

  /// No description provided for @entwTitel.
  ///
  /// In de, this message translates to:
  /// **'Entwickeln'**
  String get entwTitel;

  /// No description provided for @entwVerlaufSitzung.
  ///
  /// In de, this message translates to:
  /// **'Diese Sitzung'**
  String get entwVerlaufSitzung;

  /// No description provided for @entwVerlaufGespeichert.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get entwVerlaufGespeichert;

  /// No description provided for @entwVerlaufAusgangsstand.
  ///
  /// In de, this message translates to:
  /// **'Stand beim Öffnen'**
  String get entwVerlaufAusgangsstand;

  /// No description provided for @entwVerlaufOhneAenderung.
  ///
  /// In de, this message translates to:
  /// **'Ohne Änderung'**
  String get entwVerlaufOhneAenderung;

  /// No description provided for @entwVerlaufJetzt.
  ///
  /// In de, this message translates to:
  /// **'Aktueller Stand'**
  String get entwVerlaufJetzt;

  /// No description provided for @entwWerkzBelichtung.
  ///
  /// In de, this message translates to:
  /// **'Belichtung'**
  String get entwWerkzBelichtung;

  /// No description provided for @entwWerkzWeissabgleich.
  ///
  /// In de, this message translates to:
  /// **'Weissabgleich'**
  String get entwWerkzWeissabgleich;

  /// No description provided for @entwWerkzTemperatur.
  ///
  /// In de, this message translates to:
  /// **'Temperatur'**
  String get entwWerkzTemperatur;

  /// No description provided for @entwWerkzTint.
  ///
  /// In de, this message translates to:
  /// **'Farbstich'**
  String get entwWerkzTint;

  /// No description provided for @entwWerkzKontrast.
  ///
  /// In de, this message translates to:
  /// **'Kontrast'**
  String get entwWerkzKontrast;

  /// No description provided for @entwWerkzLichter.
  ///
  /// In de, this message translates to:
  /// **'Lichter'**
  String get entwWerkzLichter;

  /// No description provided for @entwWerkzSchatten.
  ///
  /// In de, this message translates to:
  /// **'Schatten'**
  String get entwWerkzSchatten;

  /// No description provided for @entwWerkzSchaerfe.
  ///
  /// In de, this message translates to:
  /// **'Schärfe'**
  String get entwWerkzSchaerfe;

  /// No description provided for @entwWerkzRauschen.
  ///
  /// In de, this message translates to:
  /// **'Rauschunterdrückung'**
  String get entwWerkzRauschen;

  /// No description provided for @entwWerkzKlarheit.
  ///
  /// In de, this message translates to:
  /// **'Klarheit'**
  String get entwWerkzKlarheit;

  /// No description provided for @entwWerkzVignettierung.
  ///
  /// In de, this message translates to:
  /// **'Vignettierung'**
  String get entwWerkzVignettierung;

  /// No description provided for @entwWerkzKurve.
  ///
  /// In de, this message translates to:
  /// **'Tonwertkurve'**
  String get entwWerkzKurve;

  /// No description provided for @entwWerkzFarbmischer.
  ///
  /// In de, this message translates to:
  /// **'Farbmischer'**
  String get entwWerkzFarbmischer;

  /// No description provided for @entwWerkzFarbtabelle.
  ///
  /// In de, this message translates to:
  /// **'Farbtabelle'**
  String get entwWerkzFarbtabelle;

  /// No description provided for @entwWerkzObjektiv.
  ///
  /// In de, this message translates to:
  /// **'Objektivkorrektur'**
  String get entwWerkzObjektiv;

  /// No description provided for @entwKeinVerlauf.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Verlauf vorhanden – ein Eintrag entsteht, sobald du nach einer ersten Anpassung erneut speicherst.'**
  String get entwKeinVerlauf;

  /// No description provided for @entwKopiert.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen kopiert. Sie lassen sich jetzt auf andere Fotos übertragen – auch ohne dieses hier zu speichern.'**
  String get entwKopiert;

  /// No description provided for @entwEingesetzt.
  ///
  /// In de, this message translates to:
  /// **'Kopierte Einstellungen eingesetzt – noch nicht gespeichert.'**
  String get entwEingesetzt;

  /// No description provided for @entwSpeichernFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Speichern fehlgeschlagen: Bild konnte nicht gerendert werden.'**
  String get entwSpeichernFehlgeschlagen;

  /// No description provided for @entwRestaurierungLaeuft.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung'**
  String get entwRestaurierungLaeuft;

  /// No description provided for @entwRestaurierungEingereiht.
  ///
  /// In de, this message translates to:
  /// **'Zur Warteschlange für KI-Restaurierung hinzugefügt.'**
  String get entwRestaurierungEingereiht;

  /// No description provided for @entwRestaurierungFehler.
  ///
  /// In de, this message translates to:
  /// **'Konnte nicht zur Warteschlange hinzugefügt werden: {fehler}'**
  String entwRestaurierungFehler(String fehler);

  /// No description provided for @entwKiAuswahlLadefehler.
  ///
  /// In de, this message translates to:
  /// **'KI-Auswahl konnte nicht geladen werden: {fehler}'**
  String entwKiAuswahlLadefehler(String fehler);

  /// No description provided for @entwVorschauNichtDekodiert.
  ///
  /// In de, this message translates to:
  /// **'Vorschaubild konnte nicht für die Maskierung dekodiert werden.'**
  String get entwVorschauNichtDekodiert;

  /// No description provided for @entwKiAuswahlFehler.
  ///
  /// In de, this message translates to:
  /// **'KI-Auswahl fehlgeschlagen: {fehler}'**
  String entwKiAuswahlFehler(String fehler);

  /// No description provided for @entwMaskeNummer.
  ///
  /// In de, this message translates to:
  /// **'Maske {nummer}'**
  String entwMaskeNummer(int nummer);

  /// No description provided for @entwAufloesungUnbekannt.
  ///
  /// In de, this message translates to:
  /// **'Bildauflösung unbekannt – Maske kann nicht gespeichert werden.'**
  String get entwAufloesungUnbekannt;

  /// No description provided for @entwRestaurierungEntfernen.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung entfernen'**
  String get entwRestaurierungEntfernen;

  /// No description provided for @entwRestaurierungModellFehlt.
  ///
  /// In de, this message translates to:
  /// **'Benötigt das Restaurierungs-Modell (Einstellungen → KI-Modelle)'**
  String get entwRestaurierungModellFehlt;

  /// No description provided for @entwRestaurierungAnwenden.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung anwenden (läuft im Hintergrund, dauert mehrere Minuten)'**
  String get entwRestaurierungAnwenden;

  /// No description provided for @entwMaskeHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Maske hinzufügen'**
  String get entwMaskeHinzufuegen;

  /// No description provided for @entwVerlauf.
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get entwVerlauf;

  /// No description provided for @entwEinstellungenKopieren.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen kopieren (zum Übertragen auf andere Fotos)'**
  String get entwEinstellungenKopieren;

  /// No description provided for @entwEinstellungenEinsetzen.
  ///
  /// In de, this message translates to:
  /// **'Kopierte Einstellungen in die Regler setzen'**
  String get entwEinstellungenEinsetzen;

  /// No description provided for @entwOriginal.
  ///
  /// In de, this message translates to:
  /// **'Original'**
  String get entwOriginal;

  /// No description provided for @entwVergleichen.
  ///
  /// In de, this message translates to:
  /// **'Zum Vergleichen gedrückt halten'**
  String get entwVergleichen;

  /// No description provided for @entwVorher.
  ///
  /// In de, this message translates to:
  /// **'Vorher'**
  String get entwVorher;

  /// No description provided for @entwNachher.
  ///
  /// In de, this message translates to:
  /// **'Nachher'**
  String get entwNachher;

  /// No description provided for @entwTrennstrich.
  ///
  /// In de, this message translates to:
  /// **'Vorher/Nachher nebeneinander (Strich zum Ziehen)'**
  String get entwTrennstrich;

  /// No description provided for @entwTrennstrichWartet.
  ///
  /// In de, this message translates to:
  /// **'Das unbearbeitete Bild wird noch berechnet – einen Moment.'**
  String get entwTrennstrichWartet;

  /// No description provided for @entwMaskeErstellen.
  ///
  /// In de, this message translates to:
  /// **'Maske erstellen'**
  String get entwMaskeErstellen;

  /// No description provided for @entwFormKi.
  ///
  /// In de, this message translates to:
  /// **'KI'**
  String get entwFormKi;

  /// No description provided for @entwFormKiFehlt.
  ///
  /// In de, this message translates to:
  /// **'Benötigt das Segmentierungs-Modell (Einstellungen → KI-Modelle)'**
  String get entwFormKiFehlt;

  /// No description provided for @entwFormPinsel.
  ///
  /// In de, this message translates to:
  /// **'Pinsel'**
  String get entwFormPinsel;

  /// No description provided for @entwFormEllipse.
  ///
  /// In de, this message translates to:
  /// **'Ellipse'**
  String get entwFormEllipse;

  /// No description provided for @entwFormVerlauf.
  ///
  /// In de, this message translates to:
  /// **'Verlauf'**
  String get entwFormVerlauf;

  /// No description provided for @allgFertig.
  ///
  /// In de, this message translates to:
  /// **'Fertig'**
  String get allgFertig;

  /// No description provided for @entwKiHinweis.
  ///
  /// In de, this message translates to:
  /// **'Auf den Bereich tippen, den du anpassen möchtest. Mehrere Tipps verfeinern die Auswahl.'**
  String get entwKiHinweis;

  /// No description provided for @entwPunktHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen'**
  String get entwPunktHinzufuegen;

  /// No description provided for @entwPunktEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get entwPunktEntfernen;

  /// No description provided for @entwLetztenPunktEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Letzten Punkt entfernen'**
  String get entwLetztenPunktEntfernen;

  /// No description provided for @entwPinselHinweis.
  ///
  /// In de, this message translates to:
  /// **'Über den Bereich ziehen, den du anpassen möchtest.'**
  String get entwPinselHinweis;

  /// No description provided for @entwNeuZeichnen.
  ///
  /// In de, this message translates to:
  /// **'Neu zeichnen'**
  String get entwNeuZeichnen;

  /// No description provided for @entwEllipseHinweis.
  ///
  /// In de, this message translates to:
  /// **'Über den Bereich ziehen, um die Ellipse aufzuziehen.'**
  String get entwEllipseHinweis;

  /// No description provided for @entwVerlaufHinweis.
  ///
  /// In de, this message translates to:
  /// **'Von einer Kante zur anderen ziehen, um den Verlauf festzulegen.'**
  String get entwVerlaufHinweis;

  /// No description provided for @entwAnpassungFuer.
  ///
  /// In de, this message translates to:
  /// **'Anpassung für'**
  String get entwAnpassungFuer;

  /// No description provided for @entwGanzesBild.
  ///
  /// In de, this message translates to:
  /// **'Ganzes Bild'**
  String get entwGanzesBild;

  /// No description provided for @entwFormBearbeiten.
  ///
  /// In de, this message translates to:
  /// **'Form bearbeiten'**
  String get entwFormBearbeiten;

  /// No description provided for @entwAutoWeissabgleich.
  ///
  /// In de, this message translates to:
  /// **'Automatischer Weißabgleich'**
  String get entwAutoWeissabgleich;

  /// No description provided for @entwObjektivkorrektur.
  ///
  /// In de, this message translates to:
  /// **'Objektivkorrektur'**
  String get entwObjektivkorrektur;

  /// No description provided for @entwObjektivkorrekturHinweis.
  ///
  /// In de, this message translates to:
  /// **'Nur wirksam für RAW-Fotos, deren Kamera/Objektiv unterstützt wird.'**
  String get entwObjektivkorrekturHinweis;

  /// No description provided for @entwMaskenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Diese Anpassungen wirken nur innerhalb der ausgewählten Maske.'**
  String get entwMaskenHinweis;

  /// No description provided for @entwBelichtung.
  ///
  /// In de, this message translates to:
  /// **'Belichtung'**
  String get entwBelichtung;

  /// No description provided for @entwTemperatur.
  ///
  /// In de, this message translates to:
  /// **'Temperatur (K)'**
  String get entwTemperatur;

  /// No description provided for @entwTint.
  ///
  /// In de, this message translates to:
  /// **'Tint'**
  String get entwTint;

  /// No description provided for @entwKontrast.
  ///
  /// In de, this message translates to:
  /// **'Kontrast'**
  String get entwKontrast;

  /// No description provided for @entwBeschneidungWarnung.
  ///
  /// In de, this message translates to:
  /// **'Beschneidung anzeigen (Rot = ausgefressen, Blau = abgesoffen)'**
  String get entwBeschneidungWarnung;

  /// No description provided for @entwBeschneidungMitMasken.
  ///
  /// In de, this message translates to:
  /// **'Beschneidung anzeigen geht nicht, solange Masken im Bild liegen – die Markierung entsteht in der Shader-Vorschau, und die kann Masken nicht darstellen.'**
  String get entwBeschneidungMitMasken;

  /// No description provided for @entwBeschneidungVorschauHinweis.
  ///
  /// In de, this message translates to:
  /// **'Beschneidungs-Vorschau – Schärfe, Rauschen, Klarheit und Vignette zeigt sie nicht'**
  String get entwBeschneidungVorschauHinweis;

  /// No description provided for @entwVorgabeSichern.
  ///
  /// In de, this message translates to:
  /// **'Als Vorgabe sichern'**
  String get entwVorgabeSichern;

  /// No description provided for @entwVorgabeAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Vorgabe anwenden'**
  String get entwVorgabeAnwenden;

  /// No description provided for @entwVorgabeWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Vorgabe wählen'**
  String get entwVorgabeWaehlen;

  /// No description provided for @entwVorgabeName.
  ///
  /// In de, this message translates to:
  /// **'Name der Vorgabe'**
  String get entwVorgabeName;

  /// No description provided for @entwKeineVorgaben.
  ///
  /// In de, this message translates to:
  /// **'Es gibt noch keine Entwicklungs-Vorgabe.'**
  String get entwKeineVorgaben;

  /// No description provided for @entwVorgabeGesichert.
  ///
  /// In de, this message translates to:
  /// **'Vorgabe „{name}“ gesichert'**
  String entwVorgabeGesichert(String name);

  /// No description provided for @entwVorgabeNameVergeben.
  ///
  /// In de, this message translates to:
  /// **'Es gibt bereits eine Vorgabe namens „{name}“.'**
  String entwVorgabeNameVergeben(String name);

  /// No description provided for @entwAutomatisch.
  ///
  /// In de, this message translates to:
  /// **'Belichtung und Kontrast automatisch'**
  String get entwAutomatisch;

  /// No description provided for @entwAutomatikOhneHistogramm.
  ///
  /// In de, this message translates to:
  /// **'Noch kein Histogramm – einen Moment.'**
  String get entwAutomatikOhneHistogramm;

  /// No description provided for @entwTiefenmaske.
  ///
  /// In de, this message translates to:
  /// **'Maske aus der Tiefenkarte'**
  String get entwTiefenmaske;

  /// No description provided for @entwTiefenmaskeName.
  ///
  /// In de, this message translates to:
  /// **'Tiefe'**
  String get entwTiefenmaskeName;

  /// No description provided for @entwTiefenKeine.
  ///
  /// In de, this message translates to:
  /// **'Dieses Foto bringt keine Tiefenkarte mit. Nur Porträtaufnahmen neuerer iPhones tragen eine.'**
  String get entwTiefenKeine;

  /// No description provided for @entwTiefenNichtLesbar.
  ///
  /// In de, this message translates to:
  /// **'Die Tiefenkarte liess sich nicht auswerten.'**
  String get entwTiefenNichtLesbar;

  /// No description provided for @entwTiefenNurMacos.
  ///
  /// In de, this message translates to:
  /// **'Dieses Foto könnte eine Tiefenkarte mitbringen – lesen kann sie nur die macOS-Fassung. Dort kommen die Tiefendaten aus Apples ImageIO; unter Linux und Windows läuft der Weg über LibRaw und libheif, und die geben das Hilfsbild nicht heraus.'**
  String get entwTiefenNurMacos;

  /// No description provided for @entwLichter.
  ///
  /// In de, this message translates to:
  /// **'Lichter'**
  String get entwLichter;

  /// No description provided for @entwSchatten.
  ///
  /// In de, this message translates to:
  /// **'Schatten'**
  String get entwSchatten;

  /// No description provided for @entwSchaerfe.
  ///
  /// In de, this message translates to:
  /// **'Schärfe'**
  String get entwSchaerfe;

  /// No description provided for @entwRauschunterdrueckung.
  ///
  /// In de, this message translates to:
  /// **'Rauschunterdrückung'**
  String get entwRauschunterdrueckung;

  /// No description provided for @entwStrichbreite.
  ///
  /// In de, this message translates to:
  /// **'Strichbreite'**
  String get entwStrichbreite;

  /// No description provided for @entwRotation.
  ///
  /// In de, this message translates to:
  /// **'Rotation (°)'**
  String get entwRotation;

  /// No description provided for @entwWeichzeichnung.
  ///
  /// In de, this message translates to:
  /// **'Weichzeichnung'**
  String get entwWeichzeichnung;

  /// No description provided for @entwGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Entwickeln ist für Fotos im gesperrten Ordner nicht verfügbar.'**
  String get entwGesperrt;

  /// No description provided for @entwVorschauFehlt.
  ///
  /// In de, this message translates to:
  /// **'Vorschau konnte nicht erzeugt werden – native Bildkonvertierung nicht verfügbar?'**
  String get entwVorschauFehlt;

  /// No description provided for @entwModellLaedt.
  ///
  /// In de, this message translates to:
  /// **'Modell für die KI-Auswahl wird geladen …'**
  String get entwModellLaedt;

  /// No description provided for @entwBildWirdVorbereitet.
  ///
  /// In de, this message translates to:
  /// **'Bild wird für die Maskierung vorbereitet …'**
  String get entwBildWirdVorbereitet;

  /// No description provided for @allgOder.
  ///
  /// In de, this message translates to:
  /// **'— oder —'**
  String get allgOder;

  /// No description provided for @albumBestehendes.
  ///
  /// In de, this message translates to:
  /// **'Bestehendes Album'**
  String get albumBestehendes;

  /// No description provided for @albumNeuAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Neues Album anlegen'**
  String get albumNeuAnlegen;

  /// No description provided for @personZuordnenTitel.
  ///
  /// In de, this message translates to:
  /// **'Person zuordnen'**
  String get personZuordnenTitel;

  /// No description provided for @personAktuell.
  ///
  /// In de, this message translates to:
  /// **'Aktuell: {name}'**
  String personAktuell(String name);

  /// No description provided for @personZuordnenAktion.
  ///
  /// In de, this message translates to:
  /// **'Zuordnen'**
  String get personZuordnenAktion;

  /// No description provided for @bestaetigEndgueltigLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen'**
  String get bestaetigEndgueltigLoeschen;

  /// No description provided for @bestaetigTippeVor.
  ///
  /// In de, this message translates to:
  /// **'Tippe zur Bestätigung '**
  String get bestaetigTippeVor;

  /// No description provided for @bestaetigTippeNach.
  ///
  /// In de, this message translates to:
  /// **' ein:'**
  String get bestaetigTippeNach;

  /// No description provided for @fortschrittFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen: {fehler}'**
  String fortschrittFehlgeschlagen(String fehler);

  /// No description provided for @sterneStern.
  ///
  /// In de, this message translates to:
  /// **'Stern {nummer} von 5'**
  String sterneStern(int nummer);

  /// No description provided for @sterneSternVoll.
  ///
  /// In de, this message translates to:
  /// **'Stern {nummer} von 5, ausgefüllt'**
  String sterneSternVoll(int nummer);

  /// No description provided for @sterneSetzen.
  ///
  /// In de, this message translates to:
  /// **'Bewertung: {nummer} von 5 Sternen setzen'**
  String sterneSetzen(int nummer);

  /// No description provided for @sterneBewertungAnzeige.
  ///
  /// In de, this message translates to:
  /// **'Bewertung {nummer} von 5 Sternen'**
  String sterneBewertungAnzeige(int nummer);

  /// No description provided for @scrubberTooltip.
  ///
  /// In de, this message translates to:
  /// **'Schnellnavigation zum Datum'**
  String get scrubberTooltip;

  /// No description provided for @farbeViolett.
  ///
  /// In de, this message translates to:
  /// **'Violett'**
  String get farbeViolett;

  /// No description provided for @farbeAusgewaehlt.
  ///
  /// In de, this message translates to:
  /// **'{farbe}, ausgewählt'**
  String farbeAusgewaehlt(String farbe);

  /// No description provided for @farbeSetzen.
  ///
  /// In de, this message translates to:
  /// **'Farbmarkierung {farbe} setzen'**
  String farbeSetzen(String farbe);

  /// No description provided for @histogrammTitel.
  ///
  /// In de, this message translates to:
  /// **'Histogramm'**
  String get histogrammTitel;

  /// No description provided for @histogrammKeineVorschau.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Vorschau'**
  String get histogrammKeineVorschau;

  /// No description provided for @histogrammHelligkeit.
  ///
  /// In de, this message translates to:
  /// **'Helligkeit'**
  String get histogrammHelligkeit;

  /// No description provided for @livePhotoHalten.
  ///
  /// In de, this message translates to:
  /// **'Gedrückt halten zum Abspielen'**
  String get livePhotoHalten;

  /// No description provided for @metaBelichtungBeispiel.
  ///
  /// In de, this message translates to:
  /// **'z.B. 1/125 oder 0.5'**
  String get metaBelichtungBeispiel;

  /// No description provided for @karteTippenFuerOrt.
  ///
  /// In de, this message translates to:
  /// **'Tippen, um einen Ort festzulegen'**
  String get karteTippenFuerOrt;

  /// No description provided for @rasterFotoNichtGefunden.
  ///
  /// In de, this message translates to:
  /// **'Foto nicht in der Timeline gefunden.'**
  String get rasterFotoNichtGefunden;

  /// No description provided for @kameraImportTitel.
  ///
  /// In de, this message translates to:
  /// **'Von Kamera/SD-Karte importieren'**
  String get kameraImportTitel;

  /// No description provided for @kameraKeinDatentraeger.
  ///
  /// In de, this message translates to:
  /// **'Kein Datenträger mit Fotos/Videos gefunden. Kamera oder SD-Karte per USB einstecken – die Liste aktualisiert sich automatisch, sobald sie erkannt wird.'**
  String get kameraKeinDatentraeger;

  /// No description provided for @mischerTitel.
  ///
  /// In de, this message translates to:
  /// **'Farbmischer'**
  String get mischerTitel;

  /// No description provided for @mischerFarbton.
  ///
  /// In de, this message translates to:
  /// **'Farbton'**
  String get mischerFarbton;

  /// No description provided for @mischerSaettigung.
  ///
  /// In de, this message translates to:
  /// **'Sättigung'**
  String get mischerSaettigung;

  /// No description provided for @mischerHelligkeit.
  ///
  /// In de, this message translates to:
  /// **'Helligkeit'**
  String get mischerHelligkeit;

  /// No description provided for @mischerHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wirkt nur auf farbige Bildbereiche – Graustufen bleiben unberührt.'**
  String get mischerHinweis;

  /// No description provided for @bandRot.
  ///
  /// In de, this message translates to:
  /// **'Rot'**
  String get bandRot;

  /// No description provided for @bandOrange.
  ///
  /// In de, this message translates to:
  /// **'Orange'**
  String get bandOrange;

  /// No description provided for @bandGelb.
  ///
  /// In de, this message translates to:
  /// **'Gelb'**
  String get bandGelb;

  /// No description provided for @bandGruen.
  ///
  /// In de, this message translates to:
  /// **'Grün'**
  String get bandGruen;

  /// No description provided for @bandAqua.
  ///
  /// In de, this message translates to:
  /// **'Aqua'**
  String get bandAqua;

  /// No description provided for @bandBlau.
  ///
  /// In de, this message translates to:
  /// **'Blau'**
  String get bandBlau;

  /// No description provided for @bandViolett.
  ///
  /// In de, this message translates to:
  /// **'Violett'**
  String get bandViolett;

  /// No description provided for @bandMagenta.
  ///
  /// In de, this message translates to:
  /// **'Magenta'**
  String get bandMagenta;

  /// No description provided for @kurveTitel.
  ///
  /// In de, this message translates to:
  /// **'Tonwertkurve'**
  String get kurveTitel;

  /// No description provided for @kurveHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ziehen setzt oder verschiebt einen Punkt, langes Drücken entfernt ihn.'**
  String get kurveHinweis;

  /// No description provided for @pinFeld.
  ///
  /// In de, this message translates to:
  /// **'PIN'**
  String get pinFeld;

  /// No description provided for @pinFestlegenTitel.
  ///
  /// In de, this message translates to:
  /// **'PIN festlegen'**
  String get pinFestlegenTitel;

  /// No description provided for @pinNeuFeld.
  ///
  /// In de, this message translates to:
  /// **'Neuer PIN (8-10 Ziffern)'**
  String get pinNeuFeld;

  /// No description provided for @pinWiederholen.
  ///
  /// In de, this message translates to:
  /// **'PIN wiederholen'**
  String get pinWiederholen;

  /// No description provided for @pinWarnung.
  ///
  /// In de, this message translates to:
  /// **'Wichtig: Fotos im gesperrten Ordner werden echt verschlüsselt (AES-256). Ohne diesen PIN gibt es KEINE Möglichkeit, sie wiederherzustellen – auch nicht durch Zurücksetzen der App.'**
  String get pinWarnung;

  /// No description provided for @pinZiffernFehler.
  ///
  /// In de, this message translates to:
  /// **'PIN muss aus 8-10 Ziffern bestehen.'**
  String get pinZiffernFehler;

  /// No description provided for @pinUngleich.
  ///
  /// In de, this message translates to:
  /// **'PINs stimmen nicht überein.'**
  String get pinUngleich;

  /// No description provided for @allgFestlegen.
  ///
  /// In de, this message translates to:
  /// **'Festlegen'**
  String get allgFestlegen;

  /// No description provided for @pinEingebenTitel.
  ///
  /// In de, this message translates to:
  /// **'PIN eingeben'**
  String get pinEingebenTitel;

  /// No description provided for @pinFalsch.
  ///
  /// In de, this message translates to:
  /// **'Falscher PIN.'**
  String get pinFalsch;

  /// No description provided for @passphraseFeld.
  ///
  /// In de, this message translates to:
  /// **'Passphrase'**
  String get passphraseFeld;

  /// No description provided for @passphraseFestlegenTitel.
  ///
  /// In de, this message translates to:
  /// **'Backup-Passphrase festlegen'**
  String get passphraseFestlegenTitel;

  /// No description provided for @passphraseNeuFeld.
  ///
  /// In de, this message translates to:
  /// **'Neue Passphrase (mind. 8 Zeichen)'**
  String get passphraseNeuFeld;

  /// No description provided for @passphraseWiederholen.
  ///
  /// In de, this message translates to:
  /// **'Passphrase wiederholen'**
  String get passphraseWiederholen;

  /// No description provided for @passphraseWarnung.
  ///
  /// In de, this message translates to:
  /// **'Wichtig: Backups werden echt verschlüsselt (AES-256). Ohne diese Passphrase gibt es KEINE Möglichkeit, sie wiederherzustellen – auch nicht auf einem anderen Rechner. Am besten zusätzlich an einem sicheren Ort notieren.'**
  String get passphraseWarnung;

  /// No description provided for @passphraseUngleich.
  ///
  /// In de, this message translates to:
  /// **'Passphrasen stimmen nicht überein.'**
  String get passphraseUngleich;

  /// No description provided for @passphraseFalsch.
  ///
  /// In de, this message translates to:
  /// **'Falsche Passphrase.'**
  String get passphraseFalsch;

  /// No description provided for @allgFoto.
  ///
  /// In de, this message translates to:
  /// **'Foto'**
  String get allgFoto;

  /// No description provided for @allgVideo.
  ///
  /// In de, this message translates to:
  /// **'Video'**
  String get allgVideo;

  /// No description provided for @kachelFavorisiert.
  ///
  /// In de, this message translates to:
  /// **'favorisiert'**
  String get kachelFavorisiert;

  /// No description provided for @kachelBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'{typ} {name}, {datum}'**
  String kachelBeschreibung(String typ, String name, String datum);

  /// No description provided for @albumFotosLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) löschen?'**
  String albumFotosLoeschenTitel(int anzahl);

  /// No description provided for @albumFotosLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'Diese Fotos werden aus dem Album entfernt und in den Papierkorb verschoben.'**
  String get albumFotosLoeschenText;

  /// No description provided for @albumZielordner.
  ///
  /// In de, this message translates to:
  /// **'Zielordner für \"{album}\" wählen'**
  String albumZielordner(String album);

  /// No description provided for @albumExportieren.
  ///
  /// In de, this message translates to:
  /// **'Album exportieren'**
  String get albumExportieren;

  /// No description provided for @albumLeer.
  ///
  /// In de, this message translates to:
  /// **'Dieses Album enthält noch keine Fotos.'**
  String get albumLeer;

  /// No description provided for @albumFotosHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get albumFotosHinzufuegen;

  /// No description provided for @albumTitelbildSetzen.
  ///
  /// In de, this message translates to:
  /// **'Als Titelbild'**
  String get albumTitelbildSetzen;

  /// No description provided for @albumTitelbildGesetzt.
  ///
  /// In de, this message translates to:
  /// **'Titelbild gesetzt'**
  String get albumTitelbildGesetzt;

  /// No description provided for @albumFotosWaehlenTitel.
  ///
  /// In de, this message translates to:
  /// **'Fotos für „{album}“'**
  String albumFotosWaehlenTitel(String album);

  /// No description provided for @regelLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'Regel löschen?'**
  String get regelLoeschenTitel;

  /// No description provided for @regelLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'Die Regel \"{name}\" wirklich löschen? Bereits angewendete Aktionen bleiben erhalten.'**
  String regelLoeschenText(String name);

  /// No description provided for @regelOrtUnvollstaendig.
  ///
  /// In de, this message translates to:
  /// **'Ort: unvollständig konfiguriert'**
  String get regelOrtUnvollstaendig;

  /// No description provided for @regelDatumUnvollstaendig.
  ///
  /// In de, this message translates to:
  /// **'Datumsbereich: unvollständig konfiguriert'**
  String get regelDatumUnvollstaendig;

  /// No description provided for @regelTitel.
  ///
  /// In de, this message translates to:
  /// **'Automatisierungsregeln'**
  String get regelTitel;

  /// No description provided for @regelNeu.
  ///
  /// In de, this message translates to:
  /// **'Neue Regel'**
  String get regelNeu;

  /// No description provided for @regelLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Automatisierungsregeln.\n\nLege eine Regel an, um Fotos automatisch anhand von Ort, KI-Tag oder Aufnahmedatum einem Album/Tag zuzuordnen oder zu favorisieren – wie Kamera-Presets, nur für andere Bedingungen.'**
  String get regelLeer;

  /// No description provided for @allgBearbeiten.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get allgBearbeiten;

  /// No description provided for @regelNameNoetig.
  ///
  /// In de, this message translates to:
  /// **'Ein Name für die Regel ist erforderlich.'**
  String get regelNameNoetig;

  /// No description provided for @regelKoordinatenUngueltig.
  ///
  /// In de, this message translates to:
  /// **'Breiten- und Längengrad müssen gültige Zahlen sein.'**
  String get regelKoordinatenUngueltig;

  /// No description provided for @regelBreitengradBereich.
  ///
  /// In de, this message translates to:
  /// **'Der Breitengrad muss zwischen -90 und 90 liegen.'**
  String get regelBreitengradBereich;

  /// No description provided for @regelLaengengradBereich.
  ///
  /// In de, this message translates to:
  /// **'Der Längengrad muss zwischen -180 und 180 liegen.'**
  String get regelLaengengradBereich;

  /// No description provided for @regelTagWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen KI-Tag-Begriff wählen.'**
  String get regelTagWaehlen;

  /// No description provided for @regelDatumWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Bitte Start- und Enddatum wählen.'**
  String get regelDatumWaehlen;

  /// No description provided for @regelDatumReihenfolge.
  ///
  /// In de, this message translates to:
  /// **'Das Startdatum muss vor dem Enddatum liegen.'**
  String get regelDatumReihenfolge;

  /// No description provided for @regelBreitengrad.
  ///
  /// In de, this message translates to:
  /// **'Breitengrad'**
  String get regelBreitengrad;

  /// No description provided for @regelLaengengrad.
  ///
  /// In de, this message translates to:
  /// **'Längengrad'**
  String get regelLaengengrad;

  /// No description provided for @regelKeinVokabular.
  ///
  /// In de, this message translates to:
  /// **'Kein KI-Tag-Vokabular vorhanden (Einstellungen → KI-Tagging-Vokabular).'**
  String get regelKeinVokabular;

  /// No description provided for @regelTagBegriff.
  ///
  /// In de, this message translates to:
  /// **'KI-Tag-Begriff'**
  String get regelTagBegriff;

  /// No description provided for @regelNameFeld.
  ///
  /// In de, this message translates to:
  /// **'Name (z.B. \"Urlaub Italien\")'**
  String get regelNameFeld;

  /// No description provided for @regelBedingung.
  ///
  /// In de, this message translates to:
  /// **'Bedingung'**
  String get regelBedingung;

  /// No description provided for @presetZielalbum.
  ///
  /// In de, this message translates to:
  /// **'Zielalbum (optional)'**
  String get presetZielalbum;

  /// No description provided for @presetKeinAlbum.
  ///
  /// In de, this message translates to:
  /// **'Kein Album'**
  String get presetKeinAlbum;

  /// No description provided for @presetNeuesAlbum.
  ///
  /// In de, this message translates to:
  /// **'oder: neues Album anlegen'**
  String get presetNeuesAlbum;

  /// No description provided for @presetFavorisieren.
  ///
  /// In de, this message translates to:
  /// **'Automatisch favorisieren'**
  String get presetFavorisieren;

  /// No description provided for @presetTagsWaehlenPlatzhalter.
  ///
  /// In de, this message translates to:
  /// **'Tags auswählen …'**
  String get presetTagsWaehlenPlatzhalter;

  /// No description provided for @presetKeineTags.
  ///
  /// In de, this message translates to:
  /// **'Keine Tags vorhanden.'**
  String get presetKeineTags;

  /// No description provided for @presetLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'Preset löschen?'**
  String get presetLoeschenTitel;

  /// No description provided for @presetLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'Das Kamera-Preset für \"{kamera}\" wirklich löschen? Bereits importierte Fotos bleiben unverändert.'**
  String presetLoeschenText(String kamera);

  /// No description provided for @presetTitel.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Presets'**
  String get presetTitel;

  /// No description provided for @presetNeu.
  ///
  /// In de, this message translates to:
  /// **'Neues Preset'**
  String get presetNeu;

  /// No description provided for @presetLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kamera-Presets.\n\nLege ein Preset für eine bestimmte Kamera an, um künftig importierte Fotos dieser Kamera automatisch einem Album/Tag zuzuordnen – auch schon bevor das erste Foto dieser Kamera importiert wurde.'**
  String get presetLeer;

  /// No description provided for @presetHerstellerModellNoetig.
  ///
  /// In de, this message translates to:
  /// **'Hersteller und Modell sind beide erforderlich.'**
  String get presetHerstellerModellNoetig;

  /// No description provided for @presetBekannteKamera.
  ///
  /// In de, this message translates to:
  /// **'Bekannte Kamera übernehmen (optional)'**
  String get presetBekannteKamera;

  /// No description provided for @presetHersteller.
  ///
  /// In de, this message translates to:
  /// **'Hersteller (z.B. Canon, Apple)'**
  String get presetHersteller;

  /// No description provided for @presetModell.
  ///
  /// In de, this message translates to:
  /// **'Modell (z.B. EOS R5, iPhone 15 Pro)'**
  String get presetModell;

  /// No description provided for @allgClipNoetigKurz.
  ///
  /// In de, this message translates to:
  /// **'Benötigt das CLIP-Modell (Einstellungen → KI-Modelle).'**
  String get allgClipNoetigKurz;

  /// No description provided for @duplNichtsLoeschbar.
  ///
  /// In de, this message translates to:
  /// **'Nichts automatisch löschbar: In allen Gruppen sind mehrere Fotos favorisiert oder bewertet – die bitte von Hand durchsehen.'**
  String get duplNichtsLoeschbar;

  /// No description provided for @duplNichtsZuLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Nichts zu löschen.'**
  String get duplNichtsZuLoeschen;

  /// No description provided for @duplPapierkorbTitel.
  ///
  /// In de, this message translates to:
  /// **'Kopien in den Papierkorb?'**
  String get duplPapierkorbTitel;

  /// No description provided for @duplPapierkorbAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{fotos} Foto(s) aus {gruppen} Gruppe(n) werden in den Papierkorb verschoben.'**
  String duplPapierkorbAnzahl(int fotos, int gruppen);

  /// No description provided for @duplBehaltenRegel.
  ///
  /// In de, this message translates to:
  /// **'Behalten wird je Gruppe: Favorit, sonst höchste Bewertung, sonst das schärfste, sonst das mit der höchsten Auflösung.'**
  String get duplBehaltenRegel;

  /// No description provided for @duplUebersprungen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Gruppe(n) bleiben unangetastet, weil dort mehrere Fotos favorisiert oder bewertet sind.'**
  String duplUebersprungen(int anzahl);

  /// No description provided for @duplRueckgaengig.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig: über den Papierkorb wiederherstellbar.'**
  String get duplRueckgaengig;

  /// No description provided for @duplInPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb'**
  String get duplInPapierkorb;

  /// No description provided for @duplVerschoben.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) in den Papierkorb verschoben.'**
  String duplVerschoben(int anzahl);

  /// No description provided for @duplTitel.
  ///
  /// In de, this message translates to:
  /// **'Duplikate & ähnliche Fotos'**
  String get duplTitel;

  /// No description provided for @duplZweiteBibliothek.
  ///
  /// In de, this message translates to:
  /// **'Zweite Bibliothek'**
  String get duplZweiteBibliothek;

  /// No description provided for @duplAlleKopienLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Alle Kopien löschen'**
  String get duplAlleKopienLoeschen;

  /// No description provided for @duplAehnlichkeit.
  ///
  /// In de, this message translates to:
  /// **'Ähnlichkeit:'**
  String get duplAehnlichkeit;

  /// No description provided for @duplSchwelleHinweis.
  ///
  /// In de, this message translates to:
  /// **'Höhere Werte = nur sehr ähnliche Fotos werden als Gruppe erkannt. Niedrigere Werte finden mehr, aber auch weniger sichere Treffer.'**
  String get duplSchwelleHinweis;

  /// No description provided for @duplKeineGruppen.
  ///
  /// In de, this message translates to:
  /// **'Keine ähnlichen Fotogruppen gefunden.'**
  String get duplKeineGruppen;

  /// No description provided for @duplVerschiebenTooltip.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb verschieben'**
  String get duplVerschiebenTooltip;

  /// No description provided for @duplZusammenfuehren.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get duplZusammenfuehren;

  /// No description provided for @duplZusammenfuehrenTitel.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Fotos zusammenführen'**
  String get duplZusammenfuehrenTitel;

  /// No description provided for @duplZusammenfuehrenText.
  ///
  /// In de, this message translates to:
  /// **'Metadaten aller {anzahl} Fotos werden auf die gewählte Aufnahme übertragen. Die übrigen Fotos landen im Papierkorb und können dort wiederhergestellt werden.'**
  String duplZusammenfuehrenText(int anzahl);

  /// No description provided for @duplBehaltenAuswahl.
  ///
  /// In de, this message translates to:
  /// **'Diese Aufnahme behalten'**
  String get duplBehaltenAuswahl;

  /// No description provided for @duplBehaltenDetails.
  ///
  /// In de, this message translates to:
  /// **'{sterne} Sterne · {favorit} Favorit(en)'**
  String duplBehaltenDetails(int sterne, int favorit);

  /// No description provided for @duplBeschreibungenVerbinden.
  ///
  /// In de, this message translates to:
  /// **'Unterschiedliche Beschreibungen verbinden'**
  String get duplBeschreibungenVerbinden;

  /// No description provided for @duplZusammengefuehrt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) zusammengeführt und in den Papierkorb verschoben.'**
  String duplZusammengefuehrt(int anzahl);

  /// No description provided for @clusterTitel.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge prüfen'**
  String get clusterTitel;

  /// No description provided for @clusterFertig.
  ///
  /// In de, this message translates to:
  /// **'Alle Vorschläge durchgesehen.'**
  String get clusterFertig;

  /// No description provided for @clusterAehnlichZu.
  ///
  /// In de, this message translates to:
  /// **'Ähnlich zu: {name}'**
  String clusterAehnlichZu(String name);

  /// No description provided for @clusterUeberspringen.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get clusterUeberspringen;

  /// No description provided for @gesichtUmbenennen.
  ///
  /// In de, this message translates to:
  /// **'Person umbenennen/ändern'**
  String get gesichtUmbenennen;

  /// No description provided for @gesichtNeuBenennen.
  ///
  /// In de, this message translates to:
  /// **'Neues Gesicht benennen'**
  String get gesichtNeuBenennen;

  /// No description provided for @gesichtGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Gesichts-Bearbeitung ist für Fotos im gesperrten Ordner nicht verfügbar.'**
  String get gesichtGesperrt;

  /// No description provided for @gesichtManuellHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Gesicht manuell hinzufügen'**
  String get gesichtManuellHinzufuegen;

  /// No description provided for @gesichtHinzufuegenBeenden.
  ///
  /// In de, this message translates to:
  /// **'Hinzufügen beenden'**
  String get gesichtHinzufuegenBeenden;

  /// No description provided for @gesichtRechteckHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ziehe ein Rechteck über ein Gesicht, um es manuell zu markieren.'**
  String get gesichtRechteckHinweis;

  /// No description provided for @bearbBildNichtLesbar.
  ///
  /// In de, this message translates to:
  /// **'Bild konnte nicht gelesen werden.'**
  String get bearbBildNichtLesbar;

  /// No description provided for @bearbBildNichtLesbarFehler.
  ///
  /// In de, this message translates to:
  /// **'Bild konnte nicht gelesen werden: {fehler}'**
  String bearbBildNichtLesbarFehler(String fehler);

  /// No description provided for @bearbSpeichernTitel.
  ///
  /// In de, this message translates to:
  /// **'Änderungen speichern?'**
  String get bearbSpeichernTitel;

  /// No description provided for @bearbSpeichernText.
  ///
  /// In de, this message translates to:
  /// **'Die Originaldatei wird durch die bearbeitete Version ersetzt. Das lässt sich nicht rückgängig machen.'**
  String get bearbSpeichernText;

  /// No description provided for @bearbNichtFinalisiert.
  ///
  /// In de, this message translates to:
  /// **'Bild konnte nicht finalisiert werden.'**
  String get bearbNichtFinalisiert;

  /// No description provided for @bearbZuschneidenAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Zuschneiden anwenden'**
  String get bearbZuschneidenAnwenden;

  /// No description provided for @bearbTitel.
  ///
  /// In de, this message translates to:
  /// **'Bearbeiten'**
  String get bearbTitel;

  /// No description provided for @importWasTitel.
  ///
  /// In de, this message translates to:
  /// **'Was möchtest du importieren?'**
  String get importWasTitel;

  /// No description provided for @importWasText.
  ///
  /// In de, this message translates to:
  /// **'Wähle einzelne Fotos/Videos aus, importiere einen kompletten Ordner (inkl. aller Unterordner), oder importiere direkt von einer angeschlossenen Kamera/SD-Karte.'**
  String get importWasText;

  /// No description provided for @importEinzelneDateien.
  ///
  /// In de, this message translates to:
  /// **'Einzelne Dateien wählen'**
  String get importEinzelneDateien;

  /// No description provided for @importGanzerOrdner.
  ///
  /// In de, this message translates to:
  /// **'Ganzen Ordner wählen'**
  String get importGanzerOrdner;

  /// No description provided for @importVonKamera.
  ///
  /// In de, this message translates to:
  /// **'Von Kamera/SD-Karte'**
  String get importVonKamera;

  /// No description provided for @importOrdnerWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Ordner zum Importieren wählen'**
  String get importOrdnerWaehlen;

  /// No description provided for @importNichtsImOrdner.
  ///
  /// In de, this message translates to:
  /// **'Keine unterstützten Fotos/Videos in diesem Ordner gefunden.'**
  String get importNichtsImOrdner;

  /// No description provided for @importNichtsAufDatentraeger.
  ///
  /// In de, this message translates to:
  /// **'Keine unterstützten Fotos/Videos auf diesem Datenträger gefunden.'**
  String get importNichtsAufDatentraeger;

  /// No description provided for @importAbgeschlossen.
  ///
  /// In de, this message translates to:
  /// **'Import abgeschlossen'**
  String get importAbgeschlossen;

  /// No description provided for @importBilanzNeu.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 neu hereingekommen} other{{anzahl} neu hereingekommen}}'**
  String importBilanzNeu(int anzahl);

  /// No description provided for @importBilanzDuplikate.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 lag schon in der Bibliothek und wurde übersprungen} other{{anzahl} lagen schon in der Bibliothek und wurden übersprungen}}'**
  String importBilanzDuplikate(int anzahl);

  /// No description provided for @importBilanzFehler.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 kam nicht herein} other{{anzahl} kamen nicht herein}}'**
  String importBilanzFehler(int anzahl);

  /// No description provided for @importLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Importiere Fotos & Videos …'**
  String get importLaeuft;

  /// No description provided for @importJetztSichten.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichten'**
  String get importJetztSichten;

  /// No description provided for @integPruefungFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Prüfung fehlgeschlagen: {fehler}'**
  String integPruefungFehlgeschlagen(String fehler);

  /// No description provided for @integOriginalFehlt.
  ///
  /// In de, this message translates to:
  /// **'Das Original fehlt auf der Platte – das gesamte Foto/Video wird aus der Bibliothek entfernt.'**
  String get integOriginalFehlt;

  /// No description provided for @integMaskeFehlt.
  ///
  /// In de, this message translates to:
  /// **'Die Maskendatei fehlt – der Maskeneintrag wird entfernt.'**
  String get integMaskeFehlt;

  /// No description provided for @integCropFehlt.
  ///
  /// In de, this message translates to:
  /// **'Der Gesichts-Crop fehlt – nur die Vorschau wird entfernt, die Zuordnung zur Person bleibt erhalten.'**
  String get integCropFehlt;

  /// No description provided for @integPfadEntfernt.
  ///
  /// In de, this message translates to:
  /// **'Der Datei-Pfad wird aus der Datenbank entfernt – die Datei lässt sich über \"Werkzeuge → Vorschaubilder neu erstellen\" wieder herstellen.'**
  String get integPfadEntfernt;

  /// No description provided for @integDateiLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'Datei löschen?'**
  String get integDateiLoeschenTitel;

  /// No description provided for @integDateiLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'{pfad} wird unwiderruflich von der Platte gelöscht.'**
  String integDateiLoeschenText(String pfad);

  /// No description provided for @integErneutPruefen.
  ///
  /// In de, this message translates to:
  /// **'Erneut prüfen'**
  String get integErneutPruefen;

  /// No description provided for @integPruefsummen.
  ///
  /// In de, this message translates to:
  /// **'Prüfsummen prüfen'**
  String get integPruefsummen;

  /// No description provided for @integPruefsummenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Liest jede Originaldatei komplett ein und vergleicht sie mit der beim Import gespeicherten Prüfsumme – bei großen Bibliotheken deutlich langsamer als die reine Existenz-/Verwaisten-Prüfung.'**
  String get integPruefsummenHinweis;

  /// No description provided for @integKeineProbleme.
  ///
  /// In de, this message translates to:
  /// **'Keine Probleme gefunden ({anzahl} Dateien geprüft).'**
  String integKeineProbleme(int anzahl);

  /// No description provided for @integAusDbEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus DB entfernen'**
  String get integAusDbEntfernen;

  /// No description provided for @integDateiLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Datei löschen'**
  String get integDateiLoeschen;

  /// No description provided for @integAbweichungen.
  ///
  /// In de, this message translates to:
  /// **'Prüfsummen-Abweichungen ({anzahl})'**
  String integAbweichungen(int anzahl);

  /// No description provided for @integInhaltGeaendert.
  ///
  /// In de, this message translates to:
  /// **'Inhalt hat sich seit dem Import geändert'**
  String get integInhaltGeaendert;

  /// No description provided for @integAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Ansehen'**
  String get integAnsehen;

  /// No description provided for @integVorschauTitel.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get integVorschauTitel;

  /// No description provided for @integKeineVorschau.
  ///
  /// In de, this message translates to:
  /// **'Für diese Datei lässt sich keine Vorschau zeigen.'**
  String get integKeineVorschau;

  /// No description provided for @integVorschauVerschluesselt.
  ///
  /// In de, this message translates to:
  /// **'Das Foto ist gesperrt – die Vorschau ist mitverschlüsselt.'**
  String get integVorschauVerschluesselt;

  /// No description provided for @integFotoOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Foto öffnen'**
  String get integFotoOeffnen;

  /// No description provided for @integHeaderProbleme.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsselte Dateien mit ungültigem Header ({anzahl})'**
  String integHeaderProbleme(int anzahl);

  /// No description provided for @integBeschaedigt.
  ///
  /// In de, this message translates to:
  /// **'Datei ist evtl. beschädigt – keine gültige verschlüsselte Datei'**
  String get integBeschaedigt;

  /// No description provided for @gesperrtLeer.
  ///
  /// In de, this message translates to:
  /// **'Keine gesperrten Fotos. In der Vollbildansicht eines Fotos lässt es sich über das Schloss-Symbol oben rechts hierher verschieben (dabei verschlüsselt).'**
  String get gesperrtLeer;

  /// No description provided for @gesperrtEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus dem gesperrten Ordner entfernen (entschlüsseln)'**
  String get gesperrtEntfernen;

  /// No description provided for @gesperrtEndgueltigTitel.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen?'**
  String get gesperrtEndgueltigTitel;

  /// No description provided for @gesperrtEndgueltigText.
  ///
  /// In de, this message translates to:
  /// **'Die Datei wird unwiderruflich gelöscht – auch mit dem richtigen PIN gibt es danach keine Wiederherstellung mehr.'**
  String get gesperrtEndgueltigText;

  /// No description provided for @gesperrtPapierkorbLeer.
  ///
  /// In de, this message translates to:
  /// **'Der gesperrte Papierkorb ist leer.\n\nAus dem gesperrten Ordner gelöschte Fotos landen hier statt im normalen (ungeschützten) Papierkorb.'**
  String get gesperrtPapierkorbLeer;

  /// No description provided for @gesperrtWiederherstellen.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellen (bleibt gesperrt)'**
  String get gesperrtWiederherstellen;

  /// No description provided for @personKeineGesichter.
  ///
  /// In de, this message translates to:
  /// **'Keine Gesichter dieser Person vorhanden.'**
  String get personKeineGesichter;

  /// No description provided for @personProfilbildWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Profilbild auswählen'**
  String get personProfilbildWaehlen;

  /// No description provided for @personProfilbildAendern.
  ///
  /// In de, this message translates to:
  /// **'Profilbild ändern'**
  String get personProfilbildAendern;

  /// No description provided for @personKeineFotos.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos für diese Person.'**
  String get personKeineFotos;

  /// No description provided for @personDoppelklickHinweis.
  ///
  /// In de, this message translates to:
  /// **'Doppelklick auf ein Foto öffnet es zur Kontrolle mit allen erkannten Gesichtern.'**
  String get personDoppelklickHinweis;

  /// No description provided for @personGelerntesVerworfen.
  ///
  /// In de, this message translates to:
  /// **'Gelerntes verworfen – es gilt wieder die allgemeine Schwelle.'**
  String get personGelerntesVerworfen;

  /// No description provided for @personSchwelleAngepasst.
  ///
  /// In de, this message translates to:
  /// **'angepasst auf {schwelle} statt {allgemein}'**
  String personSchwelleAngepasst(String schwelle, String allgemein);

  /// No description provided for @personSchwelleWiderspruch.
  ///
  /// In de, this message translates to:
  /// **'weiterhin {allgemein} – die Entscheidungen widersprechen sich, ein abgelehntes Gesicht war ähnlicher als ein bestätigtes'**
  String personSchwelleWiderspruch(String allgemein);

  /// No description provided for @personSchwelleWirdAngepasst.
  ///
  /// In de, this message translates to:
  /// **'ab {anzahl} Entscheidungen wird angepasst'**
  String personSchwelleWirdAngepasst(int anzahl);

  /// No description provided for @personVerwerfen.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get personVerwerfen;

  /// No description provided for @restaurWartet.
  ///
  /// In de, this message translates to:
  /// **'Wartet in der Warteschlange'**
  String get restaurWartet;

  /// No description provided for @restaurProzentLaeuft.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung läuft – {prozent} %'**
  String restaurProzentLaeuft(int prozent);

  /// No description provided for @restaurProzentMitRest.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung läuft – {prozent} %, noch etwa {rest}'**
  String restaurProzentMitRest(int prozent, String rest);

  /// No description provided for @restaurProzentMitWarteschlange.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung läuft – {prozent} %, {wartend} in Warteschlange'**
  String restaurProzentMitWarteschlange(int prozent, int wartend);

  /// No description provided for @restaurZeileLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Läuft – {prozent} %'**
  String restaurZeileLaeuft(int prozent);

  /// No description provided for @restaurZeileMitRest.
  ///
  /// In de, this message translates to:
  /// **'Läuft – {prozent} %, noch etwa {rest}'**
  String restaurZeileMitRest(int prozent, String rest);

  /// No description provided for @restaurDauerMinuten.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Minute} other{{anzahl} Minuten}}'**
  String restaurDauerMinuten(int anzahl);

  /// No description provided for @restaurDauerSekunden.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Sekunde} other{{anzahl} Sekunden}}'**
  String restaurDauerSekunden(int anzahl);

  /// No description provided for @restaurWasPassiert.
  ///
  /// In de, this message translates to:
  /// **'Real-ESRGAN rechnet das Foto auf die vierfache Kantenlänge hoch und glättet dabei Rauschen und Kompressionsspuren. Das Original bleibt unangetastet; das Ergebnis liegt daneben und lässt sich jederzeit wieder entfernen.'**
  String get restaurWasPassiert;

  /// No description provided for @restaurTitel.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung – Warteschlange'**
  String get restaurTitel;

  /// No description provided for @restaurLeer.
  ///
  /// In de, this message translates to:
  /// **'Keine Restaurierungs-Aufträge vorhanden.\nIm Entwickeln-Screen eines Fotos lässt sich eine KI-Restaurierung anstoßen.'**
  String get restaurLeer;

  /// No description provided for @restaurAusListe.
  ///
  /// In de, this message translates to:
  /// **'Aus der Liste entfernen'**
  String get restaurAusListe;

  /// No description provided for @restaurFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen: {grund}'**
  String restaurFehlgeschlagen(String grund);

  /// No description provided for @restaurFehlgeschlagenKurz.
  ///
  /// In de, this message translates to:
  /// **'Fehlgeschlagen'**
  String get restaurFehlgeschlagenKurz;

  /// No description provided for @zweitOrdnerWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Ordner der zweiten PhotoVault-Bibliothek wählen'**
  String get zweitOrdnerWaehlen;

  /// No description provided for @zweitTitel.
  ///
  /// In de, this message translates to:
  /// **'Zweite Bibliothek vergleichen'**
  String get zweitTitel;

  /// No description provided for @allgErneutVersuchen.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get allgErneutVersuchen;

  /// No description provided for @zweitErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Vergleicht die eigene Bibliothek gegen eine zweite, unabhängige PhotoVault-Bibliothek (z.B. auf einer externen Platte oder einem alten Rechner) per KI-Bildähnlichkeit – findet Fotos, die dort schon liegen, bevor du sie erneut importierst.\n\nGesperrte Fotos der zweiten Bibliothek werden dabei nie einbezogen, ohne dass deren PIN gebraucht wird.'**
  String get zweitErklaerung;

  /// No description provided for @zweitOrdnerKnopf.
  ///
  /// In de, this message translates to:
  /// **'Ordner der zweiten Bibliothek wählen'**
  String get zweitOrdnerKnopf;

  /// No description provided for @zweitSchwelleHinweis.
  ///
  /// In de, this message translates to:
  /// **'Höhere Werte = nur sehr ähnliche Fotos gelten als Übereinstimmung.'**
  String get zweitSchwelleHinweis;

  /// No description provided for @zweitKeineTreffer.
  ///
  /// In de, this message translates to:
  /// **'Keine ähnlichen Fotos in der zweiten Bibliothek gefunden.'**
  String get zweitKeineTreffer;

  /// No description provided for @zweitTreffer.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} mögliche Übereinstimmung(en)'**
  String zweitTreffer(int anzahl);

  /// No description provided for @zweitAndererOrdner.
  ///
  /// In de, this message translates to:
  /// **'Anderer Ordner'**
  String get zweitAndererOrdner;

  /// No description provided for @zweitAehnlichProzent.
  ///
  /// In de, this message translates to:
  /// **'{prozent} % ähnlich'**
  String zweitAehnlichProzent(String prozent);

  /// No description provided for @zweitBibliothek.
  ///
  /// In de, this message translates to:
  /// **'zweite Bibliothek'**
  String get zweitBibliothek;

  /// No description provided for @aehnlTitel.
  ///
  /// In de, this message translates to:
  /// **'Ähnliche Fotos'**
  String get aehnlTitel;

  /// No description provided for @aehnlClipFehlt.
  ///
  /// In de, this message translates to:
  /// **'KI-Bildsuche nicht verfügbar – CLIP-Modell fehlt (siehe Einstellungen → KI-Modelle).'**
  String get aehnlClipFehlt;

  /// No description provided for @aehnlKeineTreffer.
  ///
  /// In de, this message translates to:
  /// **'Für dieses Foto liegt noch kein KI-Embedding vor (siehe Werkzeuge → KI-Bildsuche → CLIP-Embeddings berechnen) oder es gibt keine ähnlichen Fotos in der Bibliothek.'**
  String get aehnlKeineTreffer;

  /// No description provided for @stapelErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Fotos, die sich ähneln UND innerhalb weniger Sekunden aufgenommen wurden, werden hier als Serie vorgeschlagen. \"Übernehmen\" fasst eine Gruppe zu einem Stapel zusammen – nur das Titelbild bleibt danach in der Übersicht sichtbar, nichts wird gelöscht.'**
  String get stapelErklaerung;

  /// No description provided for @stapelAlleUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Alle {anzahl} übernehmen'**
  String stapelAlleUebernehmen(int anzahl);

  /// No description provided for @stapelAlleFrageTitel.
  ///
  /// In de, this message translates to:
  /// **'Alle Serien übernehmen?'**
  String get stapelAlleFrageTitel;

  /// No description provided for @stapelAlleFrage.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Gruppen werden zu Stapeln zusammengefasst. Titelbild ist jeweils das schärfste Foto. Nichts geht dabei verloren – „Serie auflösen“ im Info-Blatt nimmt jede Gruppierung wieder zurück.'**
  String stapelAlleFrage(int anzahl);

  /// No description provided for @werkzStapelGefunden.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Keine Serien gefunden} =1{1 Serie wartet} other{{anzahl} Serien warten}}'**
  String werkzStapelGefunden(int anzahl);

  /// No description provided for @serienvergleichTitel.
  ///
  /// In de, this message translates to:
  /// **'Serie vergleichen'**
  String get serienvergleichTitel;

  /// No description provided for @serienvergleichErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Dieselben Gesichter nebeneinander. Auf einem ganzen Foto sieht man nicht, wer blinzelt – auf den Ausschnitten sofort. Der Rahmen markiert die Aufnahme mit dem schärfsten Gesicht; das ist ein Vorschlag, keine Entscheidung.'**
  String get serienvergleichErklaerung;

  /// No description provided for @serienvergleichOhneGesichter.
  ///
  /// In de, this message translates to:
  /// **'Auf diesen Aufnahmen wurde kein Gesicht erkannt – verglichen werden nur die Bilder selbst.'**
  String get serienvergleichOhneGesichter;

  /// No description provided for @serienvergleichSchaerfstes.
  ///
  /// In de, this message translates to:
  /// **'Schärfstes Gesicht der Serie'**
  String get serienvergleichSchaerfstes;

  /// No description provided for @serienvergleichSchaerfe.
  ///
  /// In de, this message translates to:
  /// **'Schärfe {wert}'**
  String serienvergleichSchaerfe(int wert);

  /// No description provided for @serienvergleichAugen.
  ///
  /// In de, this message translates to:
  /// **'Augen offen: {prozent} %'**
  String serienvergleichAugen(int prozent);

  /// No description provided for @serienvergleichOhneWert.
  ///
  /// In de, this message translates to:
  /// **'Schärfe noch nicht gemessen'**
  String get serienvergleichOhneWert;

  /// No description provided for @serienvergleichOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Gesichter vergleichen'**
  String get serienvergleichOeffnen;

  /// No description provided for @serienvergleichZuKurz.
  ///
  /// In de, this message translates to:
  /// **'Zum Vergleichen braucht es mindestens zwei Aufnahmen.'**
  String get serienvergleichZuKurz;

  /// No description provided for @stapelKeine.
  ///
  /// In de, this message translates to:
  /// **'Keine Serienbilder gefunden.'**
  String get stapelKeine;

  /// No description provided for @allgVerwerfen.
  ///
  /// In de, this message translates to:
  /// **'Verwerfen'**
  String get allgVerwerfen;

  /// No description provided for @statTitel.
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get statTitel;

  /// No description provided for @allgAktualisieren.
  ///
  /// In de, this message translates to:
  /// **'Aktualisieren'**
  String get allgAktualisieren;

  /// No description provided for @statLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos oder Videos in der Bibliothek.'**
  String get statLeer;

  /// No description provided for @statProJahr.
  ///
  /// In de, this message translates to:
  /// **'Fotos & Videos pro Jahr'**
  String get statProJahr;

  /// No description provided for @statSaisonalitaet.
  ///
  /// In de, this message translates to:
  /// **'Saisonalität – Aufnahmen pro Monat'**
  String get statSaisonalitaet;

  /// No description provided for @statKameras.
  ///
  /// In de, this message translates to:
  /// **'Häufigste Kameras'**
  String get statKameras;

  /// No description provided for @statInsgesamt.
  ///
  /// In de, this message translates to:
  /// **'Medien insgesamt'**
  String get statInsgesamt;

  /// No description provided for @statFotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get statFotos;

  /// No description provided for @statVideos.
  ///
  /// In de, this message translates to:
  /// **'Videos'**
  String get statVideos;

  /// No description provided for @statSpeicherplatz.
  ///
  /// In de, this message translates to:
  /// **'Speicherplatz'**
  String get statSpeicherplatz;

  /// No description provided for @statImPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Im Papierkorb'**
  String get statImPapierkorb;

  /// No description provided for @statDiagrammJahr.
  ///
  /// In de, this message translates to:
  /// **'Balkendiagramm, Fotos und Videos pro Jahr: {werte}'**
  String statDiagrammJahr(String werte);

  /// No description provided for @statDiagrammMonat.
  ///
  /// In de, this message translates to:
  /// **'Balkendiagramm, Saisonalität pro Monat: {werte}'**
  String statDiagrammMonat(String werte);

  /// No description provided for @papierkorbTitel.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get papierkorbTitel;

  /// No description provided for @papierkorbEndgueltigTitel.
  ///
  /// In de, this message translates to:
  /// **'Endgültig löschen?'**
  String get papierkorbEndgueltigTitel;

  /// No description provided for @papierkorbEndgueltigText.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Datei(en) unwiderruflich löschen.'**
  String papierkorbEndgueltigText(int anzahl);

  /// No description provided for @papierkorbAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein Foto} other{{anzahl} Fotos}}'**
  String papierkorbAnzahl(int anzahl);

  /// No description provided for @papierkorbUmfang.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein Foto} other{{anzahl} Fotos}} · {platz}'**
  String papierkorbUmfang(int anzahl, String platz);

  /// No description provided for @papierkorbLeer.
  ///
  /// In de, this message translates to:
  /// **'Der Papierkorb ist leer.'**
  String get papierkorbLeer;

  /// No description provided for @videoNichtGeoeffnet.
  ///
  /// In de, this message translates to:
  /// **'Video konnte nicht geöffnet werden.'**
  String get videoNichtGeoeffnet;

  /// No description provided for @videoZuschneidenFehler.
  ///
  /// In de, this message translates to:
  /// **'Zuschneiden fehlgeschlagen.'**
  String get videoZuschneidenFehler;

  /// No description provided for @videoZuschneiden.
  ///
  /// In de, this message translates to:
  /// **'Zuschneiden'**
  String get videoZuschneiden;

  /// No description provided for @xmpAlleUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Alle übernehmen'**
  String get xmpAlleUebernehmen;

  /// No description provided for @xmpErneutEinlesen.
  ///
  /// In de, this message translates to:
  /// **'Erneut einlesen'**
  String get xmpErneutEinlesen;

  /// No description provided for @xmpKeineAbweichungen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Sidecar(s) geprüft – keine Abweichungen zur Datenbank gefunden.'**
  String xmpKeineAbweichungen(int anzahl);

  /// No description provided for @restaurWirdGestartet.
  ///
  /// In de, this message translates to:
  /// **'Wird gestartet …'**
  String get restaurWirdGestartet;

  /// No description provided for @restaurAbgebrochen.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen'**
  String get restaurAbgebrochen;

  /// No description provided for @restaurGrundModellLaedtNicht.
  ///
  /// In de, this message translates to:
  /// **'Das Restaurierungs-Modell liess sich nicht laden.'**
  String get restaurGrundModellLaedtNicht;

  /// No description provided for @restaurGrundModellWeg.
  ///
  /// In de, this message translates to:
  /// **'Modell nicht mehr verfügbar.'**
  String get restaurGrundModellWeg;

  /// No description provided for @restaurGrundFotoWeg.
  ///
  /// In de, this message translates to:
  /// **'Foto wurde inzwischen gelöscht.'**
  String get restaurGrundFotoWeg;

  /// No description provided for @restaurGrundGesperrt.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung ist für gesperrte Fotos nicht verfügbar.'**
  String get restaurGrundGesperrt;

  /// No description provided for @restaurGrundAufloesung.
  ///
  /// In de, this message translates to:
  /// **'Bildauflösung unbekannt.'**
  String get restaurGrundAufloesung;

  /// No description provided for @restaurGrundNichtGerendert.
  ///
  /// In de, this message translates to:
  /// **'Bild konnte nicht gerendert werden.'**
  String get restaurGrundNichtGerendert;

  /// No description provided for @restaurGrundNichtDekodiert.
  ///
  /// In de, this message translates to:
  /// **'Gerendertes Bild konnte nicht dekodiert werden.'**
  String get restaurGrundNichtDekodiert;

  /// No description provided for @restaurNichtVerfuegbar.
  ///
  /// In de, this message translates to:
  /// **'KI-Restaurierung ist nicht verfügbar – Modell nicht installiert.'**
  String get restaurNichtVerfuegbar;

  /// No description provided for @personSchwelleWieAllgemein.
  ///
  /// In de, this message translates to:
  /// **'weiterhin {allgemein}'**
  String personSchwelleWieAllgemein(String allgemein);

  /// No description provided for @personWiedererkennung.
  ///
  /// In de, this message translates to:
  /// **'Wiedererkennung: {erklaerung}. Aus {bestaetigt, plural, =1{einer Bestätigung} other{{bestaetigt} Bestätigungen}} und {abgelehnt, plural, =1{einer Korrektur} other{{abgelehnt} Korrekturen}}.'**
  String personWiedererkennung(
      String erklaerung, int bestaetigt, int abgelehnt);

  /// No description provided for @infoKeineUnbenannten.
  ///
  /// In de, this message translates to:
  /// **'Keine unbenannten Gesichter auf diesem Foto gefunden – falls noch keine Gesichtserkennung gelaufen ist, siehe Werkzeuge → Gesichter scannen.'**
  String get infoKeineUnbenannten;

  /// No description provided for @infoTitel.
  ///
  /// In de, this message translates to:
  /// **'Info'**
  String get infoTitel;

  /// No description provided for @infoVideoStandbild.
  ///
  /// In de, this message translates to:
  /// **'Ausgewertet auf einem Standbild aus der ersten Sekunde – nicht auf dem ganzen Film.'**
  String get infoVideoStandbild;

  /// No description provided for @infoBeschreibungHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung hinzufügen'**
  String get infoBeschreibungHinzufuegen;

  /// No description provided for @infoKiBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'KI-Beschreibung'**
  String get infoKiBeschreibung;

  /// No description provided for @infoErkannterText.
  ///
  /// In de, this message translates to:
  /// **'Erkannter Text'**
  String get infoErkannterText;

  /// No description provided for @infoTextKopieren.
  ///
  /// In de, this message translates to:
  /// **'Text kopieren'**
  String get infoTextKopieren;

  /// No description provided for @infoTextKopiert.
  ///
  /// In de, this message translates to:
  /// **'Text in die Zwischenablage kopiert'**
  String get infoTextKopiert;

  /// No description provided for @infoTextStellen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 Textstelle im Bild} other{{anzahl} Textstellen im Bild}}'**
  String infoTextStellen(int anzahl);

  /// No description provided for @infoBewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung'**
  String get infoBewertung;

  /// No description provided for @infoNiemandZugeordnet.
  ///
  /// In de, this message translates to:
  /// **'Noch niemand zugeordnet.'**
  String get infoNiemandZugeordnet;

  /// No description provided for @infoDetails.
  ///
  /// In de, this message translates to:
  /// **'Details'**
  String get infoDetails;

  /// No description provided for @infoStandortBekannt.
  ///
  /// In de, this message translates to:
  /// **'Standort bekannt'**
  String get infoStandortBekannt;

  /// No description provided for @infoOrtNichtAufgeloest.
  ///
  /// In de, this message translates to:
  /// **'Ort noch nicht aufgelöst (Werkzeuge → Orte)'**
  String get infoOrtNichtAufgeloest;

  /// No description provided for @infoOrtEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Ort entfernen'**
  String get infoOrtEntfernen;

  /// No description provided for @infoBearbeitet.
  ///
  /// In de, this message translates to:
  /// **'Bearbeitet'**
  String get infoBearbeitet;

  /// No description provided for @infoBearbeitetEntwickelt.
  ///
  /// In de, this message translates to:
  /// **'entwickelt'**
  String get infoBearbeitetEntwickelt;

  /// No description provided for @infoBearbeitetRestauriert.
  ///
  /// In de, this message translates to:
  /// **'restauriert'**
  String get infoBearbeitetRestauriert;

  /// No description provided for @infoBearbeitetZugeschnitten.
  ///
  /// In de, this message translates to:
  /// **'zugeschnitten'**
  String get infoBearbeitetZugeschnitten;

  /// No description provided for @infoOriginalUnberuehrt.
  ///
  /// In de, this message translates to:
  /// **'{arten} – die Originaldatei ist unverändert'**
  String infoOriginalUnberuehrt(String arten);

  /// No description provided for @infoOriginalHerstellen.
  ///
  /// In de, this message translates to:
  /// **'Original wiederherstellen'**
  String get infoOriginalHerstellen;

  /// No description provided for @infoOriginalHerstellenFrage.
  ///
  /// In de, this message translates to:
  /// **'Alle Bearbeitungen dieser Aufnahme zurücknehmen? Die abgeleiteten Dateien werden gelöscht; das Original bleibt, wie es ist.'**
  String get infoOriginalHerstellenFrage;

  /// No description provided for @infoOriginalHergestellt.
  ///
  /// In de, this message translates to:
  /// **'Original wiederhergestellt.'**
  String get infoOriginalHergestellt;

  /// No description provided for @infoSerie.
  ///
  /// In de, this message translates to:
  /// **'Serie: {anzahl} Fotos'**
  String infoSerie(int anzahl);

  /// No description provided for @infoNurTitelbild.
  ///
  /// In de, this message translates to:
  /// **'Nur das Titelbild ist in der Übersicht sichtbar'**
  String get infoNurTitelbild;

  /// No description provided for @infoSerieAufloesen.
  ///
  /// In de, this message translates to:
  /// **'Serie auflösen'**
  String get infoSerieAufloesen;

  /// No description provided for @infoTagHinzufuegenPlatzhalter.
  ///
  /// In de, this message translates to:
  /// **'Tag hinzufügen …'**
  String get infoTagHinzufuegenPlatzhalter;

  /// No description provided for @stufeBildanalyse.
  ///
  /// In de, this message translates to:
  /// **'Bildanalyse'**
  String get stufeBildanalyse;

  /// No description provided for @stufeTexterkennung.
  ///
  /// In de, this message translates to:
  /// **'Texterkennung'**
  String get stufeTexterkennung;

  /// No description provided for @stufeSchlagwoerter.
  ///
  /// In de, this message translates to:
  /// **'Schlagwörter'**
  String get stufeSchlagwoerter;

  /// No description provided for @stufeBildbeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Bildbeschreibung'**
  String get stufeBildbeschreibung;

  /// No description provided for @aktualisierungKeineVeroeffentlichungen.
  ///
  /// In de, this message translates to:
  /// **'Keine Veröffentlichungen gefunden.'**
  String get aktualisierungKeineVeroeffentlichungen;

  /// No description provided for @aktualisierungKeineVersion.
  ///
  /// In de, this message translates to:
  /// **'Keine Versionsangabe in der Antwort gefunden.'**
  String get aktualisierungKeineVersion;

  /// No description provided for @backupGrenzeErreicht.
  ///
  /// In de, this message translates to:
  /// **'Grenze erreicht – {anzahl} Datei(en) folgen beim nächsten Lauf'**
  String backupGrenzeErreicht(int anzahl);

  /// No description provided for @backupUebernommen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Einträge aus dem Datenbank-Schnappschuss übernommen (Personen, Stammbaum, Reisen, Aktivitäten …)'**
  String backupUebernommen(int anzahl);

  /// No description provided for @backupAusschnitteNeu.
  ///
  /// In de, this message translates to:
  /// **'Gesichtsausschnitte werden neu gezeichnet …'**
  String get backupAusschnitteNeu;

  /// No description provided for @einstBackupManuellHinweis.
  ///
  /// In de, this message translates to:
  /// **'Eine Sicherung mit Passphrase nimmt zusätzlich einen verschlüsselten Schnappschuss der Datenbank mit – Personen, Stammbaum, Reisen, Aktivitäten und gespeicherte Suchen kommen damit beim Wiederherstellen zurück. Ohne Passphrase enthält die Sicherung nur die Originale und die Beilagen daneben (Beschreibung, Sterne, Farbmarke, Ort, Schlagwörter, Alben); alles Übrige liesse sich danach nicht wiederherstellen.'**
  String get einstBackupManuellHinweis;

  /// No description provided for @backupNichtGesichert.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Datei(en) konnten nicht gesichert werden – sie werden beim nächsten Lauf erneut versucht'**
  String backupNichtGesichert(int anzahl);

  /// No description provided for @backupPassphraseNoetig.
  ///
  /// In de, this message translates to:
  /// **'Dieses Backup ist verschlüsselt – eine Passphrase wird benötigt.'**
  String get backupPassphraseNoetig;

  /// No description provided for @backupOrdnerFehlt.
  ///
  /// In de, this message translates to:
  /// **'Im gewählten Ordner liegt kein Backup.'**
  String get backupOrdnerFehlt;

  /// No description provided for @downloadPruefsummeFehler.
  ///
  /// In de, this message translates to:
  /// **'Prüfsumme von {datei} stimmt nicht mit der erwarteten SHA-256 überein (erhalten {erhalten}, erwartet {erwartet}) – Download verworfen. Die Datei am Server hat sich möglicherweise geändert oder wurde beim Transfer verändert.'**
  String downloadPruefsummeFehler(
      String datei, String erhalten, String erwartet);

  /// No description provided for @downloadFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Download von {datei} fehlgeschlagen: {fehler}'**
  String downloadFehlgeschlagen(String datei, String fehler);

  /// No description provided for @downloadEntpackenFehler.
  ///
  /// In de, this message translates to:
  /// **'Entpacken von {datei} fehlgeschlagen: {fehler}'**
  String downloadEntpackenFehler(String datei, String fehler);

  /// No description provided for @downloadNichtImZip.
  ///
  /// In de, this message translates to:
  /// **'{datei} nicht im Zip gefunden.'**
  String downloadNichtImZip(String datei);

  /// No description provided for @regelAusloeserOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort (Umkreis)'**
  String get regelAusloeserOrt;

  /// No description provided for @regelAusloeserTag.
  ///
  /// In de, this message translates to:
  /// **'KI-Tag'**
  String get regelAusloeserTag;

  /// No description provided for @regelAusloeserDatum.
  ///
  /// In de, this message translates to:
  /// **'Datumsbereich'**
  String get regelAusloeserDatum;

  /// No description provided for @regelUmkreisUm.
  ///
  /// In de, this message translates to:
  /// **'Umkreis {km} km um {breite}, {laenge}'**
  String regelUmkreisUm(String km, String breite, String laenge);

  /// No description provided for @regelTagWert.
  ///
  /// In de, this message translates to:
  /// **'KI-Tag: {begriff}'**
  String regelTagWert(String begriff);

  /// No description provided for @regelDatumBereich.
  ///
  /// In de, this message translates to:
  /// **'{von} – {bis}'**
  String regelDatumBereich(String von, String bis);

  /// No description provided for @regelUmkreis.
  ///
  /// In de, this message translates to:
  /// **'Umkreis: {km} km'**
  String regelUmkreis(String km);

  /// No description provided for @regelAlbumTeil.
  ///
  /// In de, this message translates to:
  /// **'Album: {name}'**
  String regelAlbumTeil(String name);

  /// No description provided for @regelTagsTeil.
  ///
  /// In de, this message translates to:
  /// **'Tags: {namen}'**
  String regelTagsTeil(String namen);

  /// No description provided for @duplGruppe.
  ///
  /// In de, this message translates to:
  /// **'Gruppe {nummer} · {anzahl} Fotos'**
  String duplGruppe(int nummer, int anzahl);

  /// No description provided for @stapelSerie.
  ///
  /// In de, this message translates to:
  /// **'Serie {nummer} · {anzahl} Fotos'**
  String stapelSerie(int nummer, int anzahl);

  /// No description provided for @clusterGesichterZuordnen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Gesichter zuordnen'**
  String clusterGesichterZuordnen(int anzahl);

  /// No description provided for @clusterGesichterAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Gesichter'**
  String clusterGesichterAnzahl(int anzahl);

  /// No description provided for @gesichtEmbeddingFehler.
  ///
  /// In de, this message translates to:
  /// **'Wiedererkennungs-Embedding fehlgeschlagen: {fehler}'**
  String gesichtEmbeddingFehler(String fehler);

  /// No description provided for @bearbSpeichernFehler.
  ///
  /// In de, this message translates to:
  /// **'Speichern fehlgeschlagen: {fehler}'**
  String bearbSpeichernFehler(String fehler);

  /// No description provided for @integFehlendeDateien.
  ///
  /// In de, this message translates to:
  /// **'Fehlende Dateien ({anzahl})'**
  String integFehlendeDateien(int anzahl);

  /// No description provided for @integVerwaisteDateien.
  ///
  /// In de, this message translates to:
  /// **'Verwaiste Dateien ({anzahl})'**
  String integVerwaisteDateien(int anzahl);

  /// No description provided for @viewerKugelSchwenken.
  ///
  /// In de, this message translates to:
  /// **'3D-Kugel statt flachem Schwenken'**
  String get viewerKugelSchwenken;

  /// No description provided for @regelNeuTitel.
  ///
  /// In de, this message translates to:
  /// **'Neue Automatisierungsregel'**
  String get regelNeuTitel;

  /// No description provided for @regelBearbeitenTitel.
  ///
  /// In de, this message translates to:
  /// **'Regel bearbeiten'**
  String get regelBearbeitenTitel;

  /// No description provided for @presetZeileAlbum.
  ///
  /// In de, this message translates to:
  /// **'Album: {album}'**
  String presetZeileAlbum(String album);

  /// No description provided for @presetZeileTags.
  ///
  /// In de, this message translates to:
  /// **'Tags: {tags}'**
  String presetZeileTags(String tags);

  /// No description provided for @presetKeineAktion.
  ///
  /// In de, this message translates to:
  /// **'Keine Aktion konfiguriert'**
  String get presetKeineAktion;

  /// No description provided for @presetNeuTitel.
  ///
  /// In de, this message translates to:
  /// **'Neues Kamera-Preset'**
  String get presetNeuTitel;

  /// No description provided for @presetBearbeitenTitel.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Preset bearbeiten'**
  String get presetBearbeitenTitel;

  /// No description provided for @allgSucheFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Suche fehlgeschlagen: {fehler}'**
  String allgSucheFehlgeschlagen(String fehler);

  /// No description provided for @allgUnbekannterFehler.
  ///
  /// In de, this message translates to:
  /// **'Unbekannter Fehler'**
  String get allgUnbekannterFehler;

  /// No description provided for @erkundenVorJahren.
  ///
  /// In de, this message translates to:
  /// **'{jahre, plural, =1{Vor 1 Jahr} other{Vor {jahre} Jahren}}'**
  String erkundenVorJahren(int jahre);

  /// No description provided for @erkundenImMonatVorJahren.
  ///
  /// In de, this message translates to:
  /// **'Im {monat} vor {jahre} Jahren'**
  String erkundenImMonatVorJahren(String monat, int jahre);

  /// No description provided for @gesichtBenennen.
  ///
  /// In de, this message translates to:
  /// **'Gesicht benennen'**
  String get gesichtBenennen;

  /// No description provided for @gesichtUnbenannt.
  ///
  /// In de, this message translates to:
  /// **'Unbenannt'**
  String get gesichtUnbenannt;

  /// No description provided for @bearbZuschneiden.
  ///
  /// In de, this message translates to:
  /// **'Zuschneiden'**
  String get bearbZuschneiden;

  /// No description provided for @bearbLinksDrehen.
  ///
  /// In de, this message translates to:
  /// **'Nach links drehen'**
  String get bearbLinksDrehen;

  /// No description provided for @bearbRechtsDrehen.
  ///
  /// In de, this message translates to:
  /// **'Nach rechts drehen'**
  String get bearbRechtsDrehen;

  /// No description provided for @bearbHorizontalSpiegeln.
  ///
  /// In de, this message translates to:
  /// **'Horizontal spiegeln'**
  String get bearbHorizontalSpiegeln;

  /// No description provided for @bearbVertikalSpiegeln.
  ///
  /// In de, this message translates to:
  /// **'Vertikal spiegeln'**
  String get bearbVertikalSpiegeln;

  /// No description provided for @integAusDbEntfernenTitel.
  ///
  /// In de, this message translates to:
  /// **'Aus Datenbank entfernen?'**
  String get integAusDbEntfernenTitel;

  /// No description provided for @integArtOriginal.
  ///
  /// In de, this message translates to:
  /// **'Original'**
  String get integArtOriginal;

  /// No description provided for @integArtThumbnail.
  ///
  /// In de, this message translates to:
  /// **'Thumbnail'**
  String get integArtThumbnail;

  /// No description provided for @integArtVorschau.
  ///
  /// In de, this message translates to:
  /// **'Vorschau'**
  String get integArtVorschau;

  /// No description provided for @integArtEntwickelt.
  ///
  /// In de, this message translates to:
  /// **'Entwickeltes Bild'**
  String get integArtEntwickelt;

  /// No description provided for @integArtRestauriert.
  ///
  /// In de, this message translates to:
  /// **'KI-restauriertes Bild'**
  String get integArtRestauriert;

  /// No description provided for @integArtVideoZuschnitt.
  ///
  /// In de, this message translates to:
  /// **'Geschnittenes Video'**
  String get integArtVideoZuschnitt;

  /// No description provided for @integArtGesichtsCrop.
  ///
  /// In de, this message translates to:
  /// **'Gesichts-Crop'**
  String get integArtGesichtsCrop;

  /// No description provided for @integArtMaske.
  ///
  /// In de, this message translates to:
  /// **'KI-Maske'**
  String get integArtMaske;

  /// No description provided for @integAlleVerwaistenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Alle löschen'**
  String get integAlleVerwaistenLoeschen;

  /// No description provided for @integAlleVerwaistenTitel.
  ///
  /// In de, this message translates to:
  /// **'Alle verwaisten Dateien löschen?'**
  String get integAlleVerwaistenTitel;

  /// No description provided for @integAlleVerwaistenText.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Dateien mit zusammen {groesse} werden unwiderruflich von der Platte gelöscht. Sie sind in keiner Datenbankzeile verzeichnet – die Bibliothek verliert dadurch nichts, was sie anzeigen könnte.'**
  String integAlleVerwaistenText(int anzahl, String groesse);

  /// No description provided for @integVerwaisteGeloescht.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} verwaiste Dateien gelöscht.'**
  String integVerwaisteGeloescht(int anzahl);

  /// No description provided for @integWeitereEintraege.
  ///
  /// In de, this message translates to:
  /// **'… und {anzahl} weitere. Die Liste zeigt nur die ersten {gezeigt}; „Alle löschen“ räumt auch den Rest weg.'**
  String integWeitereEintraege(int anzahl, int gezeigt);

  /// No description provided for @gesperrtTabFotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get gesperrtTabFotos;

  /// No description provided for @gesperrtTabPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get gesperrtTabPapierkorb;

  /// No description provided for @karteHell.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get karteHell;

  /// No description provided for @karteDunkel.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get karteDunkel;

  /// No description provided for @karteTopografie.
  ///
  /// In de, this message translates to:
  /// **'Topografie'**
  String get karteTopografie;

  /// No description provided for @karteGlobus.
  ///
  /// In de, this message translates to:
  /// **'Globus'**
  String get karteGlobus;

  /// No description provided for @zweitVergleichFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Vergleich fehlgeschlagen: {fehler}'**
  String zweitVergleichFehlgeschlagen(String fehler);

  /// No description provided for @xmpEinlesenFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Einlesen fehlgeschlagen: {fehler}'**
  String xmpEinlesenFehlgeschlagen(String fehler);

  /// No description provided for @xmpFeldBewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung'**
  String get xmpFeldBewertung;

  /// No description provided for @xmpFeldFarbmarkierung.
  ///
  /// In de, this message translates to:
  /// **'Farbmarkierung'**
  String get xmpFeldFarbmarkierung;

  /// No description provided for @xmpFeldBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get xmpFeldBeschreibung;

  /// No description provided for @xmpFeldNeueTags.
  ///
  /// In de, this message translates to:
  /// **'Neue Tags'**
  String get xmpFeldNeueTags;

  /// No description provided for @xmpFeldStandort.
  ///
  /// In de, this message translates to:
  /// **'Standort'**
  String get xmpFeldStandort;

  /// No description provided for @xmpFeldGesichter.
  ///
  /// In de, this message translates to:
  /// **'Namen für erkannte Gesichter'**
  String get xmpFeldGesichter;

  /// No description provided for @xmpGesichterOhneNamen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 Gesicht ohne Namen} other{{anzahl} Gesichter ohne Namen}}'**
  String xmpGesichterOhneNamen(int anzahl);

  /// No description provided for @xmpKeineSidecars.
  ///
  /// In de, this message translates to:
  /// **'Keine XMP-Sidecars gefunden.'**
  String get xmpKeineSidecars;

  /// No description provided for @liveWiedergabeStoppen.
  ///
  /// In de, this message translates to:
  /// **'Wiedergabe stoppen'**
  String get liveWiedergabeStoppen;

  /// No description provided for @liveDauerschleife.
  ///
  /// In de, this message translates to:
  /// **'In Dauerschleife abspielen'**
  String get liveDauerschleife;

  /// No description provided for @metaHersteller.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Hersteller'**
  String get metaHersteller;

  /// No description provided for @metaModell.
  ///
  /// In de, this message translates to:
  /// **'Kamera-Modell'**
  String get metaModell;

  /// No description provided for @metaObjektiv.
  ///
  /// In de, this message translates to:
  /// **'Objektiv'**
  String get metaObjektiv;

  /// No description provided for @metaBrennweite.
  ///
  /// In de, this message translates to:
  /// **'Brennweite (mm)'**
  String get metaBrennweite;

  /// No description provided for @metaBlende.
  ///
  /// In de, this message translates to:
  /// **'Blende (f/…)'**
  String get metaBlende;

  /// No description provided for @metaBelichtungszeit.
  ///
  /// In de, this message translates to:
  /// **'Belichtungszeit'**
  String get metaBelichtungszeit;

  /// No description provided for @passphraseZuKurz.
  ///
  /// In de, this message translates to:
  /// **'Passphrase muss mindestens 8 Zeichen lang sein.'**
  String get passphraseZuKurz;

  /// No description provided for @exportVorgabenTitel.
  ///
  /// In de, this message translates to:
  /// **'Export-Voreinstellungen'**
  String get exportVorgabenTitel;

  /// No description provided for @exportVorgabenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Voreinstellung. Eine Voreinstellung merkt sich Grösse, Qualität und Dateibenennung – für alles, was Sie öfter als einmal exportieren.'**
  String get exportVorgabenLeer;

  /// No description provided for @exportVorgabeNeu.
  ///
  /// In de, this message translates to:
  /// **'Neue Voreinstellung'**
  String get exportVorgabeNeu;

  /// No description provided for @exportVorgabeNeuTitel.
  ///
  /// In de, this message translates to:
  /// **'Neue Export-Voreinstellung'**
  String get exportVorgabeNeuTitel;

  /// No description provided for @exportVorgabeBearbeitenTitel.
  ///
  /// In de, this message translates to:
  /// **'Voreinstellung bearbeiten'**
  String get exportVorgabeBearbeitenTitel;

  /// No description provided for @exportVorgabeName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get exportVorgabeName;

  /// No description provided for @exportVorgabeNameNoetig.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen Namen vergeben.'**
  String get exportVorgabeNameNoetig;

  /// No description provided for @exportVorgabeNachJpeg.
  ///
  /// In de, this message translates to:
  /// **'Nach JPEG rendern'**
  String get exportVorgabeNachJpeg;

  /// No description provided for @exportVorgabeNachJpegHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ohne das wird die Datei unverändert kopiert – der einzige Weg, der RAW und Videos unangetastet lässt.'**
  String get exportVorgabeNachJpegHinweis;

  /// No description provided for @exportVorgabeKante.
  ///
  /// In de, this message translates to:
  /// **'Längere Kante (Pixel)'**
  String get exportVorgabeKante;

  /// No description provided for @exportVorgabeKanteLeer.
  ///
  /// In de, this message translates to:
  /// **'leer = volle Auflösung'**
  String get exportVorgabeKanteLeer;

  /// No description provided for @exportVorgabeKanteUngueltig.
  ///
  /// In de, this message translates to:
  /// **'Die Kantenlänge muss zwischen 64 und 20000 liegen.'**
  String get exportVorgabeKanteUngueltig;

  /// No description provided for @exportVorgabeQualitaet.
  ///
  /// In de, this message translates to:
  /// **'JPEG-Qualität: {prozent} %'**
  String exportVorgabeQualitaet(int prozent);

  /// No description provided for @exportVorgabeMuster.
  ///
  /// In de, this message translates to:
  /// **'Namensmuster'**
  String get exportVorgabeMuster;

  /// No description provided for @exportVorgabeMusterNoetig.
  ///
  /// In de, this message translates to:
  /// **'Das Namensmuster darf nicht leer sein.'**
  String get exportVorgabeMusterNoetig;

  /// No description provided for @exportVorgabeMusterHinweis.
  ///
  /// In de, this message translates to:
  /// **'Die Endung wird immer selbst ergänzt. Die laufende Nummer zählt innerhalb eines Export-Laufs und wird vierstellig aufgefüllt.'**
  String get exportVorgabeMusterHinweis;

  /// No description provided for @exportVorgabeXmp.
  ///
  /// In de, this message translates to:
  /// **'XMP-Beistelldatei mitschreiben'**
  String get exportVorgabeXmp;

  /// No description provided for @exportVorgabeXmpHinweis.
  ///
  /// In de, this message translates to:
  /// **'Bewertung, Schlagwörter und Ort für andere Programme – als eigene Datei neben dem Foto.'**
  String get exportVorgabeXmpHinweis;

  /// No description provided for @exportVorgabeJpegVoll.
  ///
  /// In de, this message translates to:
  /// **'JPEG, volle Auflösung, {prozent} %'**
  String exportVorgabeJpegVoll(int prozent);

  /// No description provided for @exportVorgabeJpegKante.
  ///
  /// In de, this message translates to:
  /// **'JPEG, lange Kante {kante} px, {prozent} %'**
  String exportVorgabeJpegKante(int kante, int prozent);

  /// No description provided for @exportVorgabeOhneXmp.
  ///
  /// In de, this message translates to:
  /// **'ohne XMP'**
  String get exportVorgabeOhneXmp;

  /// No description provided for @exportVorgabeLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'Voreinstellung löschen?'**
  String get exportVorgabeLoeschenTitel;

  /// No description provided for @exportVorgabeLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'„{name}\" wird entfernt. Bereits exportierte Dateien bleiben unberührt.'**
  String exportVorgabeLoeschenText(String name);

  /// No description provided for @exportEigeneVorgaben.
  ///
  /// In de, this message translates to:
  /// **'Eigene Voreinstellungen'**
  String get exportEigeneVorgaben;

  /// No description provided for @exportVorgabenVerwalten.
  ///
  /// In de, this message translates to:
  /// **'Voreinstellungen verwalten …'**
  String get exportVorgabenVerwalten;

  /// No description provided for @werkzExportVorgabenTitel.
  ///
  /// In de, this message translates to:
  /// **'Export-Voreinstellungen'**
  String get werkzExportVorgabenTitel;

  /// No description provided for @werkzExportVorgabenText.
  ///
  /// In de, this message translates to:
  /// **'Benannte Ausgabe-Vorgaben für den Export: Grösse, JPEG-Qualität, Dateibenennung und ob eine XMP-Beistelldatei mitgeschrieben wird.'**
  String get werkzExportVorgabenText;

  /// No description provided for @exportVorgabeNameVergeben.
  ///
  /// In de, this message translates to:
  /// **'Diesen Namen gibt es schon.'**
  String get exportVorgabeNameVergeben;

  /// No description provided for @entwObjektivkorrekturKeinRaw.
  ///
  /// In de, this message translates to:
  /// **'Kein RAW – die Kamera hat Verzeichnung und Vignettierung bereits korrigiert.'**
  String get entwObjektivkorrekturKeinRaw;

  /// No description provided for @entwObjektivkorrekturVerfuegbar.
  ///
  /// In de, this message translates to:
  /// **'Kamera und Objektiv sind bekannt: Verzeichnung und Vignettierung werden korrigiert.'**
  String get entwObjektivkorrekturVerfuegbar;

  /// No description provided for @entwObjektivkorrekturUnbekanntesObjektiv.
  ///
  /// In de, this message translates to:
  /// **'Für diese Kamera gibt es kein Profil. Bei ProRAW-Aufnahmen ist das kein Mangel – die Korrektur steckt schon in der Datei.'**
  String get entwObjektivkorrekturUnbekanntesObjektiv;

  /// No description provided for @entwObjektivkorrekturNichtLesbar.
  ///
  /// In de, this message translates to:
  /// **'Die RAW-Daten dieser Datei lassen sich nicht öffnen. Auch die übrigen Regler wirken deshalb nur auf die eingebettete Vorschau.'**
  String get entwObjektivkorrekturNichtLesbar;

  /// No description provided for @einstSuche.
  ///
  /// In de, this message translates to:
  /// **'Suche nach Einstellungen'**
  String get einstSuche;

  /// No description provided for @einstNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'Keine Einstellung passt zu dieser Suche.'**
  String get einstNichtsGefunden;

  /// No description provided for @einstBeschrErscheinungsbild.
  ///
  /// In de, this message translates to:
  /// **'Hell, dunkel oder wie das System'**
  String get einstBeschrErscheinungsbild;

  /// No description provided for @einstBeschrSprache.
  ///
  /// In de, this message translates to:
  /// **'Sprache der Oberfläche und der Schlagwörter'**
  String get einstBeschrSprache;

  /// No description provided for @einstBeschrUeberwacht.
  ///
  /// In de, this message translates to:
  /// **'Ordner, aus denen neue Fotos von selbst hereinkommen'**
  String get einstBeschrUeberwacht;

  /// No description provided for @einstBeschrBibliotheken.
  ///
  /// In de, this message translates to:
  /// **'Zwischen mehreren Bibliotheken wechseln'**
  String get einstBeschrBibliotheken;

  /// No description provided for @einstBeschrSpeicherort.
  ///
  /// In de, this message translates to:
  /// **'Wo die Bibliothek liegt und wie viel Platz sie braucht'**
  String get einstBeschrSpeicherort;

  /// No description provided for @einstBeschrModelle.
  ///
  /// In de, this message translates to:
  /// **'Herunterladen und entfernen der lokalen Modelle'**
  String get einstBeschrModelle;

  /// No description provided for @einstBeschrHintergrund.
  ///
  /// In de, this message translates to:
  /// **'Ob nach dem Import automatisch ausgewertet wird'**
  String get einstBeschrHintergrund;

  /// No description provided for @einstBeschrVokabular.
  ///
  /// In de, this message translates to:
  /// **'Die Begriffe, nach denen Fotos beschlagwortet werden'**
  String get einstBeschrVokabular;

  /// No description provided for @einstAbschnittKarte.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get einstAbschnittKarte;

  /// No description provided for @einstBeschrKarte.
  ///
  /// In de, this message translates to:
  /// **'Kachelquelle der dunklen Karte'**
  String get einstBeschrKarte;

  /// No description provided for @einstKartenNetzHinweis.
  ///
  /// In de, this message translates to:
  /// **'Die Karte holt ihre Kacheln beim Anzeigen von OpenStreetMap, OpenTopoMap, Esri und – beim Gelände – von AWS Open Data. Deren Server erfahren dabei, welchen Ausschnitt du ansiehst, und damit ungefähr, wo deine Fotos entstanden sind. Ohne Karte verlässt nichts davon den Rechner: Land, Region und Stadt zu einem GPS-Ort schlägt die App im heruntergeladenen Ortsverzeichnis nach.'**
  String get einstKartenNetzHinweis;

  /// No description provided for @einstCartoText.
  ///
  /// In de, this message translates to:
  /// **'Die dunkle Karte zeichnet von Haus aus umgefärbte OpenStreetMap-Kacheln – ohne Anmeldung und ohne Schlüssel. Wer den feineren CARTO-Schnitt möchte, trägt hier einen Schlüssel ein.'**
  String get einstCartoText;

  /// No description provided for @einstCartoAktiv.
  ///
  /// In de, this message translates to:
  /// **'CARTO Dark Matter, bis Zoomstufe 20.'**
  String get einstCartoAktiv;

  /// No description provided for @einstCartoOhne.
  ///
  /// In de, this message translates to:
  /// **'Umgefärbte OpenStreetMap-Kacheln, bis Zoomstufe 19.'**
  String get einstCartoOhne;

  /// No description provided for @einstCartoFeld.
  ///
  /// In de, this message translates to:
  /// **'CARTO-Schlüssel'**
  String get einstCartoFeld;

  /// No description provided for @einstCartoFeldHinweis.
  ///
  /// In de, this message translates to:
  /// **'Leer lassen für OpenStreetMap'**
  String get einstCartoFeldHinweis;

  /// No description provided for @einstCartoQuelle.
  ///
  /// In de, this message translates to:
  /// **'Kostenlos und ohne Konto unter carto.com/basemaps/apikey. CARTO stellt seine Rasterkacheln nach eigener Aussage ein – ohne Schlüssel bleibt die Karte davon unberührt.'**
  String get einstCartoQuelle;

  /// No description provided for @einstCartoGespeichert.
  ///
  /// In de, this message translates to:
  /// **'CARTO-Schlüssel gespeichert'**
  String get einstCartoGespeichert;

  /// No description provided for @einstCartoEntfernt.
  ///
  /// In de, this message translates to:
  /// **'CARTO-Schlüssel entfernt – die Karte nutzt wieder OpenStreetMap'**
  String get einstCartoEntfernt;

  /// No description provided for @einstBeschrStandortdaten.
  ///
  /// In de, this message translates to:
  /// **'Ortsnamen zu GPS-Koordinaten, offline'**
  String get einstBeschrStandortdaten;

  /// No description provided for @einstBeschrGesperrt.
  ///
  /// In de, this message translates to:
  /// **'PIN, Verschlüsselung und was darin liegt'**
  String get einstBeschrGesperrt;

  /// No description provided for @einstBeschrBackupSchluessel.
  ///
  /// In de, this message translates to:
  /// **'Passphrase für verschlüsselte Sicherungen'**
  String get einstBeschrBackupSchluessel;

  /// No description provided for @einstBeschrBackupManuell.
  ///
  /// In de, this message translates to:
  /// **'Eine Sicherung von Hand anstoßen'**
  String get einstBeschrBackupManuell;

  /// No description provided for @einstBeschrBackupAuto.
  ///
  /// In de, this message translates to:
  /// **'Regelmäßig sichern, ohne daran zu denken'**
  String get einstBeschrBackupAuto;

  /// No description provided for @einstBeschrPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Gelöschte Fotos ansehen, zurückholen, endgültig entfernen'**
  String get einstBeschrPapierkorb;

  /// No description provided for @einstBeschrGefahr.
  ///
  /// In de, this message translates to:
  /// **'Schritte, die sich nicht rückgängig machen lassen'**
  String get einstBeschrGefahr;

  /// No description provided for @einstBeschrUeber.
  ///
  /// In de, this message translates to:
  /// **'Version, Lizenzen und Aktualisierungen'**
  String get einstBeschrUeber;

  /// No description provided for @allgRueckgaengig.
  ///
  /// In de, this message translates to:
  /// **'Rückgängig'**
  String get allgRueckgaengig;

  /// No description provided for @personenIgnoriertTab.
  ///
  /// In de, this message translates to:
  /// **'Ignoriert'**
  String get personenIgnoriertTab;

  /// Reiterbeschriftung mit der Zahl der darin liegenden Einträge. Als Textbaustein und nicht im Quelltext zusammengesetzt, weil nicht jede Sprache runde Klammern dafür verwendet.
  ///
  /// In de, this message translates to:
  /// **'{beschriftung} ({anzahl})'**
  String tabMitZahl(String beschriftung, int anzahl);

  /// No description provided for @personenIgnorierenTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ausgewählte Gesichter ignorieren'**
  String get personenIgnorierenTooltip;

  /// No description provided for @personenZugeordnetMeldung.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Gesicht „{name}“ zugeordnet.} other{{anzahl} Gesichter „{name}“ zugeordnet.}}'**
  String personenZugeordnetMeldung(int anzahl, String name);

  /// No description provided for @personenIgnoriertMeldung.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Gesicht ignoriert.} other{{anzahl} Gesichter ignoriert.}}'**
  String personenIgnoriertMeldung(int anzahl);

  /// No description provided for @personenIgnoriertLeer.
  ///
  /// In de, this message translates to:
  /// **'Keine ignorierten Gesichter. Was du unter „Unbenannte Gesichter“ beiseitelegst – Plakate, Spiegelungen, Statuen –, sammelt sich hier und lässt sich jederzeit zurückholen.'**
  String get personenIgnoriertLeer;

  /// No description provided for @personenIgnoriertHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ignorierte Gesichter erscheinen nicht mehr im Raster und werden nicht mehr gruppiert. Doppelklick öffnet das ganze Foto.'**
  String get personenIgnoriertHinweis;

  /// No description provided for @personenIgnoriertTeilHinweis.
  ///
  /// In de, this message translates to:
  /// **'{gezeigt} von {gesamt} ignorierten Gesichtern. Doppelklick öffnet das ganze Foto.'**
  String personenIgnoriertTeilHinweis(int gezeigt, int gesamt);

  /// No description provided for @personenZurueckholenKnopf.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} zurückholen'**
  String personenZurueckholenKnopf(int anzahl);

  /// No description provided for @clusterPhaseLaden.
  ///
  /// In de, this message translates to:
  /// **'Gesichter werden geladen …'**
  String get clusterPhaseLaden;

  /// No description provided for @clusterPhaseVergleichen.
  ///
  /// In de, this message translates to:
  /// **'Gesichter werden verglichen …'**
  String get clusterPhaseVergleichen;

  /// No description provided for @clusterPhaseVorschlaege.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge werden vorbereitet …'**
  String get clusterPhaseVorschlaege;

  /// No description provided for @clusterOhneProzent.
  ///
  /// In de, this message translates to:
  /// **'Läuft …'**
  String get clusterOhneProzent;

  /// No description provided for @clusterFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Die automatische Gruppierung ist fehlgeschlagen: {fehler}'**
  String clusterFehlgeschlagen(String fehler);

  /// No description provided for @clusterIgnorierenTooltip.
  ///
  /// In de, this message translates to:
  /// **'Ganze Gruppe ignorieren'**
  String get clusterIgnorierenTooltip;

  /// No description provided for @gesichtIgnorieren.
  ///
  /// In de, this message translates to:
  /// **'Ignorieren'**
  String get gesichtIgnorieren;

  /// No description provided for @gesichtIgnoriert.
  ///
  /// In de, this message translates to:
  /// **'Ignoriert'**
  String get gesichtIgnoriert;

  /// No description provided for @gesichtZurueckgeholt.
  ///
  /// In de, this message translates to:
  /// **'Gesicht wird wieder berücksichtigt.'**
  String get gesichtZurueckgeholt;

  /// No description provided for @gesichtPosition.
  ///
  /// In de, this message translates to:
  /// **'{nummer} von {gesamt}'**
  String gesichtPosition(int nummer, int gesamt);

  /// No description provided for @gesichtVoriges.
  ///
  /// In de, this message translates to:
  /// **'Vorheriges Foto (Pfeil links)'**
  String get gesichtVoriges;

  /// No description provided for @gesichtNaechstes.
  ///
  /// In de, this message translates to:
  /// **'Nächstes Foto (Pfeil rechts)'**
  String get gesichtNaechstes;

  /// No description provided for @clusterUnerwartetBeendet.
  ///
  /// In de, this message translates to:
  /// **'Die automatische Gruppierung wurde unerwartet beendet.'**
  String get clusterUnerwartetBeendet;

  /// No description provided for @aufgAktiv.
  ///
  /// In de, this message translates to:
  /// **'Aktiv'**
  String get aufgAktiv;

  /// No description provided for @aufgStufeKurz.
  ///
  /// In de, this message translates to:
  /// **'Stufe {nummer}/{gesamt}'**
  String aufgStufeKurz(int nummer, int gesamt);

  /// No description provided for @personenAlleIgnorieren.
  ///
  /// In de, this message translates to:
  /// **'Alle unbenannten Gesichter ignorieren'**
  String get personenAlleIgnorieren;

  /// No description provided for @personenAlleIgnorierenHinweis.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Nichts mehr offen} =1{Ein Gesicht wandert nach „Ignoriert“} other{{anzahl} Gesichter wandern nach „Ignoriert“}}'**
  String personenAlleIgnorierenHinweis(int anzahl);

  /// No description provided for @personenAlleIgnoriertMeldung.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Es war nichts zu ignorieren.} =1{Ein Gesicht ignoriert. Unter „Ignoriert“ holst du einzelne zurück.} other{{anzahl} Gesichter ignoriert. Unter „Ignoriert“ holst du einzelne zurück.}}'**
  String personenAlleIgnoriertMeldung(int anzahl);

  /// No description provided for @personenAlleErkennungenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Alle unbenannten Erkennungen löschen'**
  String get personenAlleErkennungenLoeschen;

  /// No description provided for @personenAlleErkennungenLoeschenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Gibt Platz frei, kommt beim nächsten Scan aber wieder'**
  String get personenAlleErkennungenLoeschenHinweis;

  /// No description provided for @personenErkennungenLoeschenTitel.
  ///
  /// In de, this message translates to:
  /// **'Erkennungen wirklich löschen?'**
  String get personenErkennungenLoeschenTitel;

  /// No description provided for @personenErkennungenLoeschenText.
  ///
  /// In de, this message translates to:
  /// **'Alle unbenannten Erkennungen werden samt ihrer Ausschnitte von der Platte gelöscht – auch die bereits ignorierten. Benannte Personen bleiben unberührt.\n\nDas ist nicht dauerhaft: Der nächste Gesichts-Scan findet dieselben Stellen wieder. Wenn du sie dauerhaft loswerden willst, nimm stattdessen „Alle unbenannten Gesichter ignorieren“ – das überlebt auch einen erneuten Scan.'**
  String get personenErkennungenLoeschenText;

  /// No description provided for @personenErkennungenGeloeschtMeldung.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Es gab keine Erkennungen zum Löschen.} =1{Eine Erkennung gelöscht.} other{{anzahl} Erkennungen gelöscht.}}'**
  String personenErkennungenGeloeschtMeldung(int anzahl);

  /// No description provided for @gesichtZuordnungLoesen.
  ///
  /// In de, this message translates to:
  /// **'Zuordnung lösen'**
  String get gesichtZuordnungLoesen;

  /// No description provided for @gesichtNichtMehrIgnorieren.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr ignorieren'**
  String get gesichtNichtMehrIgnorieren;

  /// No description provided for @gesichtFotoLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Foto löschen'**
  String get gesichtFotoLoeschen;

  /// No description provided for @zeitraumName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get zeitraumName;

  /// No description provided for @zeitraumArt.
  ///
  /// In de, this message translates to:
  /// **'Art'**
  String get zeitraumArt;

  /// No description provided for @zeitraumZaehlt.
  ///
  /// In de, this message translates to:
  /// **'Fotos werden gezählt …'**
  String get zeitraumZaehlt;

  /// No description provided for @zeitraumFotos.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Kein Foto in diesem Zeitraum} =1{1 Foto in diesem Zeitraum} other{{n} Fotos in diesem Zeitraum}}'**
  String zeitraumFotos(int n);

  /// No description provided for @reisenSelbstAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Reise von Hand anlegen'**
  String get reisenSelbstAnlegen;

  /// No description provided for @reisenSelbstAngelegt.
  ///
  /// In de, this message translates to:
  /// **'Reise „{name}\" angelegt.'**
  String reisenSelbstAngelegt(String name);

  /// No description provided for @aktivitaetenSelbstAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Aktivität von Hand anlegen'**
  String get aktivitaetenSelbstAnlegen;

  /// No description provided for @aktivitaetenSelbstAngelegt.
  ///
  /// In de, this message translates to:
  /// **'Aktivität „{name}\" angelegt.'**
  String aktivitaetenSelbstAngelegt(String name);

  /// No description provided for @infoOrtSuchen.
  ///
  /// In de, this message translates to:
  /// **'Ort suchen'**
  String get infoOrtSuchen;

  /// No description provided for @infoOrtSuchenBeispiel.
  ///
  /// In de, this message translates to:
  /// **'z. B. Goslar'**
  String get infoOrtSuchenBeispiel;

  /// No description provided for @infoOrtKeinVerzeichnis.
  ///
  /// In de, this message translates to:
  /// **'Dafür fehlt das Ortsverzeichnis. Es lässt sich unter Einstellungen → Standortdaten laden.'**
  String get infoOrtKeinVerzeichnis;

  /// No description provided for @infoOrtNichtGefunden.
  ///
  /// In de, this message translates to:
  /// **'Kein Ort namens „{name}\" im Verzeichnis.'**
  String infoOrtNichtGefunden(String name);

  /// No description provided for @infoOrtGesetzt.
  ///
  /// In de, this message translates to:
  /// **'Ort auf {ort} gesetzt.'**
  String infoOrtGesetzt(String ort);

  /// No description provided for @infoOrtGesetztMehrdeutig.
  ///
  /// In de, this message translates to:
  /// **'Ort auf {ort} gesetzt – es gibt {weitere} weitere gleichen Namens.'**
  String infoOrtGesetztMehrdeutig(String ort, int weitere);

  /// No description provided for @gesichtNichtMehrDurchsuchen.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr nach Gesichtern durchsuchen'**
  String get gesichtNichtMehrDurchsuchen;

  /// No description provided for @gesichtWiederDurchsuchen.
  ///
  /// In de, this message translates to:
  /// **'Wieder nach Gesichtern durchsuchen'**
  String get gesichtWiederDurchsuchen;

  /// No description provided for @gesichtNichtMehrDurchsuchtHinweis.
  ///
  /// In de, this message translates to:
  /// **'Dieses Foto wird beim erneuten Durchsuchen übersprungen. Erkannte Gesichter bleiben.'**
  String get gesichtNichtMehrDurchsuchtHinweis;

  /// No description provided for @gesichtWiederDurchsuchtHinweis.
  ///
  /// In de, this message translates to:
  /// **'Dieses Foto wird wieder mitdurchsucht.'**
  String get gesichtWiederDurchsuchtHinweis;

  /// No description provided for @gesichtInGesperrtemOrdner.
  ///
  /// In de, this message translates to:
  /// **'Das Foto liegt jetzt im gesperrten Ordner.'**
  String get gesichtInGesperrtemOrdner;

  /// No description provided for @gesichtFavoritGesetzt.
  ///
  /// In de, this message translates to:
  /// **'Als Favorit gesetzt.'**
  String get gesichtFavoritGesetzt;

  /// No description provided for @gesichtFavoritEntfernt.
  ///
  /// In de, this message translates to:
  /// **'Favorit entfernt.'**
  String get gesichtFavoritEntfernt;

  /// No description provided for @gesichtSperrenFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'Das Foto konnte nicht in den gesperrten Ordner gelegt werden.'**
  String get gesichtSperrenFehlgeschlagen;

  /// No description provided for @gesichtErkennungLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Erkennung löschen'**
  String get gesichtErkennungLoeschen;

  /// No description provided for @gesichtAlleUnbenanntenIgnorieren.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Keine unbenannten Gesichter} =1{Unbenanntes Gesicht ignorieren} other{{anzahl} unbenannte Gesichter ignorieren}}'**
  String gesichtAlleUnbenanntenIgnorieren(int anzahl);

  /// No description provided for @personWeitereFotosSuchen.
  ///
  /// In de, this message translates to:
  /// **'Weitere Fotos suchen'**
  String get personWeitereFotosSuchen;

  /// No description provided for @vorschlagTitel.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge für {name}'**
  String vorschlagTitel(String name);

  /// No description provided for @vorschlagHinweis.
  ///
  /// In de, this message translates to:
  /// **'Alles ist ausgewählt. Nimm heraus, was nicht stimmt – auch das lernt die Erkennung: Eine Ablehnung schiebt die Schwelle für diese Person nach oben.'**
  String get vorschlagHinweis;

  /// No description provided for @vorschlagAlleWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Alle wählen'**
  String get vorschlagAlleWaehlen;

  /// No description provided for @vorschlagKeineWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Keine wählen'**
  String get vorschlagKeineWaehlen;

  /// No description provided for @vorschlagUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Nichts ausgewählt} =1{Ein Gesicht zuordnen} other{{anzahl} Gesichter zuordnen}}'**
  String vorschlagUebernehmen(int anzahl);

  /// No description provided for @vorschlagUebernommenMeldung.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Nichts übernommen – die Rückmeldung ist trotzdem gespeichert.} =1{Ein Foto hinzugefügt.} other{{anzahl} Fotos hinzugefügt.}}'**
  String vorschlagUebernommenMeldung(int anzahl);

  /// No description provided for @vorschlagKeineEmbeddings.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person gibt es noch keine Wiedererkennungs-Daten. Sie entstehen beim Gesichts-Scan, sobald das SFace-Modell installiert ist.'**
  String get vorschlagKeineEmbeddings;

  /// No description provided for @vorschlagKeineKandidaten.
  ///
  /// In de, this message translates to:
  /// **'Es gibt keine unbenannten Gesichter, die vorgeschlagen werden könnten.'**
  String get vorschlagKeineKandidaten;

  /// No description provided for @vorschlagNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'Kein unbenanntes Gesicht liegt über der Schwelle {schwelle} dieser Person.'**
  String vorschlagNichtsGefunden(String schwelle);

  /// No description provided for @gesichtRahmenAusblenden.
  ///
  /// In de, this message translates to:
  /// **'Rahmen ausblenden'**
  String get gesichtRahmenAusblenden;

  /// No description provided for @gesichtRahmenEinblenden.
  ///
  /// In de, this message translates to:
  /// **'Rahmen einblenden'**
  String get gesichtRahmenEinblenden;

  /// No description provided for @entwKlarheit.
  ///
  /// In de, this message translates to:
  /// **'Klarheit'**
  String get entwKlarheit;

  /// No description provided for @entwVignettierung.
  ///
  /// In de, this message translates to:
  /// **'Vignettierung'**
  String get entwVignettierung;

  /// No description provided for @entwLutKeine.
  ///
  /// In de, this message translates to:
  /// **'Keine Farbtabelle'**
  String get entwLutKeine;

  /// No description provided for @entwLutWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Farbtabelle wählen (.cube)'**
  String get entwLutWaehlen;

  /// No description provided for @entwLutEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Farbtabelle entfernen'**
  String get entwLutEntfernen;

  /// No description provided for @entwLutStaerke.
  ///
  /// In de, this message translates to:
  /// **'Stärke'**
  String get entwLutStaerke;

  /// No description provided for @entwLutFehlt.
  ///
  /// In de, this message translates to:
  /// **'Die Farbtabelle „{name}“ lässt sich nicht mehr lesen und wurde entfernt.'**
  String entwLutFehlt(String name);

  /// No description provided for @entwLutNichtLesbar.
  ///
  /// In de, this message translates to:
  /// **'Die Datei lässt sich nicht lesen: {fehler}'**
  String entwLutNichtLesbar(String fehler);

  /// No description provided for @entwLutEindimensional.
  ///
  /// In de, this message translates to:
  /// **'Das ist eine eindimensionale Tabelle – sie beschreibt eine Kurve, keinen Farbraum. Dafür gibt es hier die Tonwertkurve.'**
  String get entwLutEindimensional;

  /// No description provided for @entwLutOhneGroesse.
  ///
  /// In de, this message translates to:
  /// **'In der Datei fehlt die Angabe LUT_3D_SIZE.'**
  String get entwLutOhneGroesse;

  /// No description provided for @entwLutGroesse.
  ///
  /// In de, this message translates to:
  /// **'Die Kantenlänge in Zeile {zeile} liegt außerhalb des Erlaubten (2 bis 256).'**
  String entwLutGroesse(int zeile);

  /// No description provided for @entwLutZeilenzahl.
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält nicht so viele Werte, wie ihre Kantenlänge verlangt.'**
  String get entwLutZeilenzahl;

  /// No description provided for @entwLutZeile.
  ///
  /// In de, this message translates to:
  /// **'Zeile {zeile} lässt sich nicht lesen.'**
  String entwLutZeile(int zeile);

  /// No description provided for @histogrammWaveform.
  ///
  /// In de, this message translates to:
  /// **'Waveform'**
  String get histogrammWaveform;

  /// No description provided for @histogrammParade.
  ///
  /// In de, this message translates to:
  /// **'Parade'**
  String get histogrammParade;

  /// No description provided for @entwFormRechteck.
  ///
  /// In de, this message translates to:
  /// **'Rechteck'**
  String get entwFormRechteck;

  /// No description provided for @entwFormFarbe.
  ///
  /// In de, this message translates to:
  /// **'Farbe'**
  String get entwFormFarbe;

  /// No description provided for @entwRechteckHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ziehe ein Rechteck auf. Drehung und weiche Kante stellst du darunter ein.'**
  String get entwRechteckHinweis;

  /// No description provided for @entwFarbauswahlHinweis.
  ///
  /// In de, this message translates to:
  /// **'Tippe auf eine Farbe im Bild. Ausgewählt wird alles, was ihr ähnlich genug ist – auch heller oder dunkler, denn Farbe zählt mehr als Helligkeit.'**
  String get entwFarbauswahlHinweis;

  /// No description provided for @entwFarbeAufgenommen.
  ///
  /// In de, this message translates to:
  /// **'R {rot} · G {gruen} · B {blau}'**
  String entwFarbeAufgenommen(int rot, int gruen, int blau);

  /// No description provided for @entwToleranz.
  ///
  /// In de, this message translates to:
  /// **'Toleranz'**
  String get entwToleranz;

  /// No description provided for @vergleichTitel.
  ///
  /// In de, this message translates to:
  /// **'Zwei Fotos vergleichen'**
  String get vergleichTitel;

  /// No description provided for @vergleichNebeneinander.
  ///
  /// In de, this message translates to:
  /// **'Nebeneinander'**
  String get vergleichNebeneinander;

  /// No description provided for @vergleichUebereinander.
  ///
  /// In de, this message translates to:
  /// **'Übereinander'**
  String get vergleichUebereinander;

  /// No description provided for @vergleichKoppeln.
  ///
  /// In de, this message translates to:
  /// **'Ansichten koppeln'**
  String get vergleichKoppeln;

  /// No description provided for @vergleichEntkoppeln.
  ///
  /// In de, this message translates to:
  /// **'Ansichten entkoppeln'**
  String get vergleichEntkoppeln;

  /// No description provided for @vergleichZuruecksetzen.
  ///
  /// In de, this message translates to:
  /// **'Zoom zurücksetzen'**
  String get vergleichZuruecksetzen;

  /// No description provided for @auswVergleichen.
  ///
  /// In de, this message translates to:
  /// **'Die zwei ausgewählten Fotos vergleichen'**
  String get auswVergleichen;

  /// No description provided for @listeOhneKamera.
  ///
  /// In de, this message translates to:
  /// **'Ohne Kameraangabe'**
  String get listeOhneKamera;

  /// No description provided for @zeitleisteGroesser.
  ///
  /// In de, this message translates to:
  /// **'Grössere Kacheln'**
  String get zeitleisteGroesser;

  /// No description provided for @zeitleisteKleiner.
  ///
  /// In de, this message translates to:
  /// **'Kleinere Kacheln – mehr Monate auf einmal'**
  String get zeitleisteKleiner;

  /// No description provided for @zeitleisteFormReihen.
  ///
  /// In de, this message translates to:
  /// **'Bündige Reihen – jedes Foto in seinem Format'**
  String get zeitleisteFormReihen;

  /// No description provided for @zeitleisteFormQuadrate.
  ///
  /// In de, this message translates to:
  /// **'Quadratisches Raster'**
  String get zeitleisteFormQuadrate;

  /// No description provided for @listeSpalten.
  ///
  /// In de, this message translates to:
  /// **'Spalten'**
  String get listeSpalten;

  /// No description provided for @listeSpalteDateiname.
  ///
  /// In de, this message translates to:
  /// **'Dateiname'**
  String get listeSpalteDateiname;

  /// No description provided for @listeSpalteDatum.
  ///
  /// In de, this message translates to:
  /// **'Aufgenommen'**
  String get listeSpalteDatum;

  /// No description provided for @listeSpalteKamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get listeSpalteKamera;

  /// No description provided for @listeSpalteObjektiv.
  ///
  /// In de, this message translates to:
  /// **'Objektiv'**
  String get listeSpalteObjektiv;

  /// No description provided for @listeSpalteBelichtung.
  ///
  /// In de, this message translates to:
  /// **'Belichtung'**
  String get listeSpalteBelichtung;

  /// No description provided for @listeSpalteBewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung'**
  String get listeSpalteBewertung;

  /// No description provided for @listeSpalteFarbe.
  ///
  /// In de, this message translates to:
  /// **'Farbe'**
  String get listeSpalteFarbe;

  /// No description provided for @listeSpalteMasse.
  ///
  /// In de, this message translates to:
  /// **'Masse'**
  String get listeSpalteMasse;

  /// No description provided for @listeSpalteGroesse.
  ///
  /// In de, this message translates to:
  /// **'Dateigrösse'**
  String get listeSpalteGroesse;

  /// No description provided for @listeSpalteArt.
  ///
  /// In de, this message translates to:
  /// **'Art'**
  String get listeSpalteArt;

  /// No description provided for @listeSpalteOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get listeSpalteOrt;

  /// No description provided for @listeSpalteBreiteAendern.
  ///
  /// In de, this message translates to:
  /// **'Breite ändern'**
  String get listeSpalteBreiteAendern;

  /// No description provided for @ansichtRaster.
  ///
  /// In de, this message translates to:
  /// **'Raster'**
  String get ansichtRaster;

  /// No description provided for @ansichtListe.
  ///
  /// In de, this message translates to:
  /// **'Liste'**
  String get ansichtListe;

  /// No description provided for @gruppeMonat.
  ///
  /// In de, this message translates to:
  /// **'Nach Monat'**
  String get gruppeMonat;

  /// No description provided for @gruppeKamera.
  ///
  /// In de, this message translates to:
  /// **'Nach Kamera'**
  String get gruppeKamera;

  /// No description provided for @gruppeKeine.
  ///
  /// In de, this message translates to:
  /// **'Ohne Gliederung'**
  String get gruppeKeine;

  /// No description provided for @sortReihenfolge.
  ///
  /// In de, this message translates to:
  /// **'Reihenfolge'**
  String get sortReihenfolge;

  /// No description provided for @sortAufnahmeNeu.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmedatum, neueste zuerst'**
  String get sortAufnahmeNeu;

  /// No description provided for @sortAufnahmeAlt.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmedatum, älteste zuerst'**
  String get sortAufnahmeAlt;

  /// No description provided for @sortImportNeu.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt hinzugefügt'**
  String get sortImportNeu;

  /// No description provided for @sortName.
  ///
  /// In de, this message translates to:
  /// **'Dateiname, A–Z'**
  String get sortName;

  /// No description provided for @sortBewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung, beste zuerst'**
  String get sortBewertung;

  /// No description provided for @sortGroesse.
  ///
  /// In de, this message translates to:
  /// **'Dateigrösse, grösste zuerst'**
  String get sortGroesse;

  /// No description provided for @sortFundreihenfolge.
  ///
  /// In de, this message translates to:
  /// **'Fundreihenfolge'**
  String get sortFundreihenfolge;

  /// No description provided for @bearbGeradeziehen.
  ///
  /// In de, this message translates to:
  /// **'Geradeziehen'**
  String get bearbGeradeziehen;

  /// No description provided for @bearbPerspektive.
  ///
  /// In de, this message translates to:
  /// **'Perspektive'**
  String get bearbPerspektive;

  /// No description provided for @bearbPerspektiveAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Entzerren'**
  String get bearbPerspektiveAnwenden;

  /// No description provided for @modellLamaTitel.
  ///
  /// In de, this message translates to:
  /// **'Objektentfernung (LaMa)'**
  String get modellLamaTitel;

  /// No description provided for @modellLamaText.
  ///
  /// In de, this message translates to:
  /// **'Füllt eine markierte Stelle aus der Umgebung neu auf – für Staubflecken, Passanten oder den Mülleimer am Bildrand. Mit 208 MB das grösste Modell hier; ein Durchgang dauert rund eine Sekunde.'**
  String get modellLamaText;

  /// No description provided for @modellLamaLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache 2.0 (Samsung Research), ONNX-Export von Carve'**
  String get modellLamaLizenz;

  /// No description provided for @bearbRetusche.
  ///
  /// In de, this message translates to:
  /// **'Objekt entfernen'**
  String get bearbRetusche;

  /// No description provided for @aufgLamaModell.
  ///
  /// In de, this message translates to:
  /// **'das LaMa-Modell'**
  String get aufgLamaModell;

  /// No description provided for @bearbRetuscheNichtsMarkiert.
  ///
  /// In de, this message translates to:
  /// **'Nichts markiert – male über das, was verschwinden soll.'**
  String get bearbRetuscheNichtsMarkiert;

  /// No description provided for @bearbRetuscheAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get bearbRetuscheAnwenden;

  /// No description provided for @bearbRetuscheZurueck.
  ///
  /// In de, this message translates to:
  /// **'Letzten Strich zurücknehmen'**
  String get bearbRetuscheZurueck;

  /// No description provided for @bearbPinselbreite.
  ///
  /// In de, this message translates to:
  /// **'Pinselbreite'**
  String get bearbPinselbreite;

  /// No description provided for @bearbRetuscheFehler.
  ///
  /// In de, this message translates to:
  /// **'Das Entfernen ist fehlgeschlagen: {fehler}'**
  String bearbRetuscheFehler(String fehler);

  /// No description provided for @stammbaumTitel.
  ///
  /// In de, this message translates to:
  /// **'Stammbaum'**
  String get stammbaumTitel;

  /// No description provided for @stammbaumTitelVon.
  ///
  /// In de, this message translates to:
  /// **'Stammbaum: {name}'**
  String stammbaumTitelVon(String name);

  /// No description provided for @stammbaumElternteilHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Elternteil hinzufügen'**
  String get stammbaumElternteilHinzufuegen;

  /// No description provided for @stammbaumPartnerHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Partner hinzufügen'**
  String get stammbaumPartnerHinzufuegen;

  /// No description provided for @stammbaumKindHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Kind hinzufügen'**
  String get stammbaumKindHinzufuegen;

  /// No description provided for @stammbaumInDieMitte.
  ///
  /// In de, this message translates to:
  /// **'In die Mitte rücken'**
  String get stammbaumInDieMitte;

  /// No description provided for @stammbaumLebensdaten.
  ///
  /// In de, this message translates to:
  /// **'Lebensdaten …'**
  String get stammbaumLebensdaten;

  /// No description provided for @stammbaumFotosZeigen.
  ///
  /// In de, this message translates to:
  /// **'Fotos dieser Person'**
  String get stammbaumFotosZeigen;

  /// No description provided for @stammbaumVerbindungEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Verbindung entfernen'**
  String get stammbaumVerbindungEntfernen;

  /// No description provided for @stammbaumVerbindungEntfernenFrage.
  ///
  /// In de, this message translates to:
  /// **'Die Verwandtschaft zwischen {eine} und {andere} wird gelöst. Beide Personen und ihre Fotos bleiben erhalten.'**
  String stammbaumVerbindungEntfernenFrage(String eine, String andere);

  /// No description provided for @stammbaumFehlerSelbst.
  ///
  /// In de, this message translates to:
  /// **'Eine Person kann nicht mit sich selbst verwandt sein.'**
  String get stammbaumFehlerSelbst;

  /// No description provided for @stammbaumFehlerKreis.
  ///
  /// In de, this message translates to:
  /// **'Das ginge im Kreis: Die Person steht bereits weiter unten im selben Zweig.'**
  String get stammbaumFehlerKreis;

  /// No description provided for @stammbaumFehlerVorhanden.
  ///
  /// In de, this message translates to:
  /// **'Diese Verwandtschaft ist schon eingetragen.'**
  String get stammbaumFehlerVorhanden;

  /// No description provided for @stammbaumZuVieleHaushalte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein weiterer Haushalt passt nicht ins Bild.} other{{anzahl} weitere Haushalte passen nicht ins Bild.}}'**
  String stammbaumZuVieleHaushalte(int anzahl);

  /// No description provided for @stammbaumLeer.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person ist noch keine Verwandtschaft eingetragen. Oben rechts lassen sich Eltern, Partner und Kinder hinzufügen – entweder aus den bereits benannten Personen oder als neuer Name, auch ohne ein einziges Foto.'**
  String get stammbaumLeer;

  /// No description provided for @stammbaumPersonFehlt.
  ///
  /// In de, this message translates to:
  /// **'Diese Person gibt es nicht mehr.'**
  String get stammbaumPersonFehlt;

  /// No description provided for @stammbaumGeboren.
  ///
  /// In de, this message translates to:
  /// **'Geboren'**
  String get stammbaumGeboren;

  /// No description provided for @stammbaumGestorben.
  ///
  /// In de, this message translates to:
  /// **'Gestorben'**
  String get stammbaumGestorben;

  /// No description provided for @stammbaumUnbekannt.
  ///
  /// In de, this message translates to:
  /// **'unbekannt'**
  String get stammbaumUnbekannt;

  /// No description provided for @stammbaumNurJahrHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ist nur das Jahr bekannt, wähle einen beliebigen Tag darin – angezeigt wird ohnehin nur die Jahreszahl.'**
  String get stammbaumNurJahrHinweis;

  /// No description provided for @gradSelbst.
  ///
  /// In de, this message translates to:
  /// **'diese Person'**
  String get gradSelbst;

  /// No description provided for @gradEltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Mutter} m{Vater} other{Elternteil}}'**
  String gradEltern(String geschlecht);

  /// No description provided for @gradGrosseltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Großmutter} m{Großvater} other{Großelternteil}}'**
  String gradGrosseltern(String geschlecht);

  /// No description provided for @gradUrgrosseltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Urgroßmutter} m{Urgroßvater} other{Urgroßelternteil}}'**
  String gradUrgrosseltern(String geschlecht);

  /// No description provided for @gradUrurgrosseltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Ururgroßmutter} m{Ururgroßvater} other{Ururgroßelternteil}}'**
  String gradUrurgrosseltern(String geschlecht);

  /// No description provided for @gradVorfahreN.
  ///
  /// In de, this message translates to:
  /// **'Vorfahre der {stufe}. Generation'**
  String gradVorfahreN(int stufe);

  /// No description provided for @gradKind.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Tochter} m{Sohn} other{Kind}}'**
  String gradKind(String geschlecht);

  /// No description provided for @gradEnkel.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Enkelin} m{Enkel} other{Enkelkind}}'**
  String gradEnkel(String geschlecht);

  /// No description provided for @gradUrenkel.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Urenkelin} m{Urenkel} other{Urenkelkind}}'**
  String gradUrenkel(String geschlecht);

  /// No description provided for @gradUrurenkel.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Ururenkelin} m{Ururenkel} other{Ururenkelkind}}'**
  String gradUrurenkel(String geschlecht);

  /// No description provided for @gradNachkommeN.
  ///
  /// In de, this message translates to:
  /// **'Nachkomme der {stufe}. Generation'**
  String gradNachkommeN(int stufe);

  /// No description provided for @gradGeschwister.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Schwester} m{Bruder} other{Geschwister}}'**
  String gradGeschwister(String geschlecht);

  /// No description provided for @gradHalbgeschwister.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Halbschwester} m{Halbbruder} other{Halbgeschwister}}'**
  String gradHalbgeschwister(String geschlecht);

  /// No description provided for @gradNeffeNichte.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Nichte} m{Neffe} other{Geschwisterkind}}'**
  String gradNeffeNichte(String geschlecht);

  /// No description provided for @gradGrossneffeNichte.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Großnichte} m{Großneffe} other{Großgeschwisterkind}}'**
  String gradGrossneffeNichte(String geschlecht);

  /// No description provided for @gradGeschwisterNachkommeN.
  ///
  /// In de, this message translates to:
  /// **'Nachkomme eines Geschwisters, {stufe} Stufen entfernt'**
  String gradGeschwisterNachkommeN(int stufe);

  /// No description provided for @gradOnkelTante.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Tante} m{Onkel} other{Elterngeschwister}}'**
  String gradOnkelTante(String geschlecht);

  /// No description provided for @gradGrossonkelTante.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Großtante} m{Großonkel} other{Großelterngeschwister}}'**
  String gradGrossonkelTante(String geschlecht);

  /// No description provided for @gradVorfahrengeschwisterN.
  ///
  /// In de, this message translates to:
  /// **'Geschwister eines Vorfahren der {stufe}. Generation'**
  String gradVorfahrengeschwisterN(int stufe);

  /// No description provided for @gradCousin.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Cousine} m{Cousin} other{Cousin/Cousine}} {stufe}. Grades'**
  String gradCousin(String geschlecht, int stufe);

  /// No description provided for @gradEntfernt.
  ///
  /// In de, this message translates to:
  /// **'{bezeichnung}, {stufe}-fach entfernt'**
  String gradEntfernt(int stufe, String bezeichnung);

  /// No description provided for @gradPartner.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Partnerin} m{Partner} other{Partner}}'**
  String gradPartner(String geschlecht);

  /// No description provided for @gradSchwager.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Schwägerin} m{Schwager} other{Schwager/Schwägerin}}'**
  String gradSchwager(String geschlecht);

  /// No description provided for @gradSchwiegereltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Schwiegermutter} m{Schwiegervater} other{Schwiegerelternteil}}'**
  String gradSchwiegereltern(String geschlecht);

  /// No description provided for @gradSchwiegerkind.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Schwiegertochter} m{Schwiegersohn} other{Schwiegerkind}}'**
  String gradSchwiegerkind(String geschlecht);

  /// No description provided for @gradStiefeltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Stiefmutter} m{Stiefvater} other{Stiefelternteil}}'**
  String gradStiefeltern(String geschlecht);

  /// No description provided for @gradStiefkind.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Stieftochter} m{Stiefsohn} other{Stiefkind}}'**
  String gradStiefkind(String geschlecht);

  /// No description provided for @gradStiefgeschwister.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Stiefschwester} m{Stiefbruder} other{Stiefgeschwister}}'**
  String gradStiefgeschwister(String geschlecht);

  /// No description provided for @gradAngeheiratet.
  ///
  /// In de, this message translates to:
  /// **'angeheiratet'**
  String get gradAngeheiratet;

  /// Für Verwandte, die kein eigenes Wort haben – „Mutter von Schwager Michael". schritt ist die Beziehung zur Zwischenperson, bezug deren Beziehung zur Person in der Mitte.
  ///
  /// In de, this message translates to:
  /// **'{schritt} von {bezug} {name}'**
  String gradUeberWeg(String schritt, String bezug, String name);

  /// No description provided for @gradKeine.
  ///
  /// In de, this message translates to:
  /// **'nicht verwandt'**
  String get gradKeine;

  /// No description provided for @navStammbaum.
  ///
  /// In de, this message translates to:
  /// **'Stammbaum'**
  String get navStammbaum;

  /// No description provided for @stammbaumAndereWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Andere Person in die Mitte'**
  String get stammbaumAndereWaehlen;

  /// No description provided for @stammbaumAnsichtBaum.
  ///
  /// In de, this message translates to:
  /// **'Baum'**
  String get stammbaumAnsichtBaum;

  /// No description provided for @stammbaumAnsichtListe.
  ///
  /// In de, this message translates to:
  /// **'Verwandte'**
  String get stammbaumAnsichtListe;

  /// No description provided for @stammbaumListeKopf.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person ist mit {name} verwandt.} other{{anzahl} Personen sind mit {name} verwandt – von den nächsten zu den entferntesten.}}'**
  String stammbaumListeKopf(String name, int anzahl);

  /// No description provided for @stammbaumKeinePersonen.
  ///
  /// In de, this message translates to:
  /// **'Es sind noch keine Personen angelegt. Benenne im Tab „Personen\" ein paar Gesichter, oder lege hier über „Andere Person in die Mitte\" jemanden von Hand an.'**
  String get stammbaumKeinePersonen;

  /// No description provided for @stammbaumGeschlecht.
  ///
  /// In de, this message translates to:
  /// **'Geschlecht'**
  String get stammbaumGeschlecht;

  /// No description provided for @stammbaumGeschlechtWeiblich.
  ///
  /// In de, this message translates to:
  /// **'weiblich'**
  String get stammbaumGeschlechtWeiblich;

  /// No description provided for @stammbaumGeschlechtMaennlich.
  ///
  /// In de, this message translates to:
  /// **'männlich'**
  String get stammbaumGeschlechtMaennlich;

  /// No description provided for @stammbaumGeschlechtDivers.
  ///
  /// In de, this message translates to:
  /// **'divers'**
  String get stammbaumGeschlechtDivers;

  /// No description provided for @stammbaumGeschlechtOffen.
  ///
  /// In de, this message translates to:
  /// **'keine Angabe'**
  String get stammbaumGeschlechtOffen;

  /// No description provided for @stammbaumGeschlechtHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wird nur für die Verwandtschaftsbezeichnungen gebraucht – ohne Angabe steht dort „Geschwister\" statt „Schwester\".'**
  String get stammbaumGeschlechtHinweis;

  /// No description provided for @stammbaumAngaben.
  ///
  /// In de, this message translates to:
  /// **'Angaben zur Person'**
  String get stammbaumAngaben;

  /// No description provided for @stammbaumAnsichtFaecher.
  ///
  /// In de, this message translates to:
  /// **'Fächer'**
  String get stammbaumAnsichtFaecher;

  /// No description provided for @stammbaumAnsichtNachfahren.
  ///
  /// In de, this message translates to:
  /// **'Nachfahren'**
  String get stammbaumAnsichtNachfahren;

  /// No description provided for @stammbaumKeineVorfahren.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person sind noch keine Vorfahren eingetragen. Der Fächer zeigt Eltern, Großeltern und Urgroßeltern – füge oben rechts einen Elternteil hinzu, und er füllt sich von innen nach außen.'**
  String get stammbaumKeineVorfahren;

  /// No description provided for @stammbaumKeineNachfahren.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person sind noch keine Kinder eingetragen. Die Gliederung zeigt alle Nachkommen, eingerückt nach Generation.'**
  String get stammbaumKeineNachfahren;

  /// No description provided for @stammbaumFamilienfotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos der Familie'**
  String get stammbaumFamilienfotos;

  /// No description provided for @stammbaumFamilienfotosVon.
  ///
  /// In de, this message translates to:
  /// **'Fotos der Familie von {name}'**
  String stammbaumFamilienfotosVon(String name);

  /// No description provided for @stammbaumGedcomImport.
  ///
  /// In de, this message translates to:
  /// **'GEDCOM einlesen …'**
  String get stammbaumGedcomImport;

  /// No description provided for @gedcomImportTitel.
  ///
  /// In de, this message translates to:
  /// **'In der Datei steht'**
  String get gedcomImportTitel;

  /// No description provided for @gedcomImportGefunden.
  ///
  /// In de, this message translates to:
  /// **'{personen} Personen, {kanten} Verwandtschaften und {ereignisse} Ereignisse.'**
  String gedcomImportGefunden(int personen, int kanten, int ereignisse);

  /// No description provided for @gedcomImportNeuHinweis.
  ///
  /// In de, this message translates to:
  /// **'Alle werden neu angelegt. Nichts Bestehendes wird verändert oder zusammengeführt.'**
  String get gedcomImportNeuHinweis;

  /// No description provided for @gedcomImportUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Einlesen'**
  String get gedcomImportUebernehmen;

  /// No description provided for @gedcomImportFertig.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person eingelesen.} other{{anzahl} Personen eingelesen.}}'**
  String gedcomImportFertig(int anzahl);

  /// No description provided for @gedcomFehlerTitel.
  ///
  /// In de, this message translates to:
  /// **'Datei nicht lesbar'**
  String get gedcomFehlerTitel;

  /// No description provided for @gedcomFehlerKeinKopf.
  ///
  /// In de, this message translates to:
  /// **'Die Datei beginnt nicht mit einem GEDCOM-Kopf. Vermutlich ist es keine GEDCOM-Datei.'**
  String get gedcomFehlerKeinKopf;

  /// No description provided for @gedcomFehlerKodierung.
  ///
  /// In de, this message translates to:
  /// **'Die Datei ist in {kodierung} geschrieben. Diese Kodierung lässt sich nicht sicher entziffern, und halb entzifferte Namen wären schlimmer als ein ehrliches Nein. Bitte im Herkunftsprogramm noch einmal als UTF-8 ausgeben.'**
  String gedcomFehlerKodierung(String kodierung);

  /// No description provided for @gedcomFehlerKeinePersonen.
  ///
  /// In de, this message translates to:
  /// **'In der Datei steht keine einzige Person.'**
  String get gedcomFehlerKeinePersonen;

  /// No description provided for @gedcomBerichtTitel.
  ///
  /// In de, this message translates to:
  /// **'Was beim Einlesen auffiel'**
  String get gedcomBerichtTitel;

  /// No description provided for @gedcomBerichtSauber.
  ///
  /// In de, this message translates to:
  /// **'Nichts zu beanstanden.'**
  String get gedcomBerichtSauber;

  /// No description provided for @gedcomBerichtDoppelte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person könnte es schon geben.} other{{anzahl} Personen könnte es schon geben.}}'**
  String gedcomBerichtDoppelte(int anzahl);

  /// No description provided for @gedcomBerichtDoppelteHinweis.
  ///
  /// In de, this message translates to:
  /// **'Zusammengeführt wurde nichts. Wer wirklich dieselbe Person ist, entscheidest du im Personen-Bildschirm.'**
  String get gedcomBerichtDoppelteHinweis;

  /// No description provided for @gedcomBerichtUngenaueDaten.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Datum war nur ungefähr angegeben und blieb deshalb leer.} other{{anzahl} Daten waren nur ungefähr angegeben und blieben deshalb leer.}}'**
  String gedcomBerichtUngenaueDaten(int anzahl);

  /// No description provided for @gedcomBerichtUebersprungen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Eintrag gehört zu etwas, das diese App nicht führt.} other{{anzahl} Einträge gehören zu etwas, das diese App nicht führt.}}'**
  String gedcomBerichtUebersprungen(int anzahl);

  /// No description provided for @gedcomBerichtKreise.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Verwandtschaft hätte einen Kreis geschlossen und blieb weg.} other{{anzahl} Verwandtschaften hätten einen Kreis geschlossen und blieben weg.}}'**
  String gedcomBerichtKreise(int anzahl);

  /// No description provided for @gedcomBerichtOhneNamen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person stand ohne Namen in der Datei.} other{{anzahl} Personen standen ohne Namen in der Datei.}}'**
  String gedcomBerichtOhneNamen(int anzahl);

  /// No description provided for @gedcomOrtGeburt.
  ///
  /// In de, this message translates to:
  /// **'Geburtsort'**
  String get gedcomOrtGeburt;

  /// No description provided for @gedcomOrtTod.
  ///
  /// In de, this message translates to:
  /// **'Sterbeort'**
  String get gedcomOrtTod;

  /// No description provided for @gedcomOrtTaufe.
  ///
  /// In de, this message translates to:
  /// **'Taufe'**
  String get gedcomOrtTaufe;

  /// No description provided for @gedcomOrtBestattung.
  ///
  /// In de, this message translates to:
  /// **'Bestattung'**
  String get gedcomOrtBestattung;

  /// No description provided for @gedcomOhneNamen.
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen'**
  String get gedcomOhneNamen;

  /// No description provided for @stammbaumZeitleisteOhneDaten.
  ///
  /// In de, this message translates to:
  /// **'Auf der Zeitleiste steht noch nichts: Bei keiner Person dieser Familie ist ein Datum eingetragen.'**
  String get stammbaumZeitleisteOhneDaten;

  /// No description provided for @stammbaumAnsichtZeitleiste.
  ///
  /// In de, this message translates to:
  /// **'Zeitleiste'**
  String get stammbaumAnsichtZeitleiste;

  /// No description provided for @zeitleisteOhneDatum.
  ///
  /// In de, this message translates to:
  /// **'kein Datum bekannt'**
  String get zeitleisteOhneDatum;

  /// No description provided for @zeitleisteEreignisse.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein Ereignis} other{{anzahl} Ereignisse}}'**
  String zeitleisteEreignisse(int anzahl);

  /// No description provided for @stammbaumFamilienstatistik.
  ///
  /// In de, this message translates to:
  /// **'Familienstatistik'**
  String get stammbaumFamilienstatistik;

  /// No description provided for @famstatAufFotos.
  ///
  /// In de, this message translates to:
  /// **'Auf den Fotos'**
  String get famstatAufFotos;

  /// No description provided for @famstatAusLebensdaten.
  ///
  /// In de, this message translates to:
  /// **'Aus den Lebensdaten'**
  String get famstatAusLebensdaten;

  /// No description provided for @famstatAufnahmenGesamt.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen'**
  String get famstatAufnahmenGesamt;

  /// No description provided for @famstatImBild.
  ///
  /// In de, this message translates to:
  /// **'Im Bild'**
  String get famstatImBild;

  /// No description provided for @famstatZeitraum.
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get famstatZeitraum;

  /// No description provided for @famstatOhneBild.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person ist auf keinem Bild} other{{anzahl} Personen sind auf keinem Bild}}'**
  String famstatOhneBild(int anzahl);

  /// No description provided for @famstatAufnahmenJeJahr.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen je Jahr'**
  String get famstatAufnahmenJeJahr;

  /// No description provided for @famstatOftZusammen.
  ///
  /// In de, this message translates to:
  /// **'Oft zusammen im Bild'**
  String get famstatOftZusammen;

  /// No description provided for @famstatVonBis.
  ///
  /// In de, this message translates to:
  /// **'{von} bis {bis}'**
  String famstatVonBis(String von, String bis);

  /// No description provided for @famstatAlterVonBis.
  ///
  /// In de, this message translates to:
  /// **'{von} bis {bis} Jahre alt'**
  String famstatAlterVonBis(int von, int bis);

  /// No description provided for @famstatInJahren.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{in einem Jahr} other{in {anzahl} Jahren}}'**
  String famstatInJahren(int anzahl);

  /// No description provided for @famstatFehlendeLebensdaten.
  ///
  /// In de, this message translates to:
  /// **'Sterbealter, Heiratsalter und Alter je Generation stehen erst da, wenn Sterbe- und Hochzeitsdaten eingetragen sind. Photo Vault schätzt sie nicht.'**
  String get famstatFehlendeLebensdaten;

  /// No description provided for @famstatKeineFotos.
  ///
  /// In de, this message translates to:
  /// **'Von dieser Familie ist noch niemand auf einem Foto erkannt worden.'**
  String get famstatKeineFotos;

  /// No description provided for @famstatLeer.
  ///
  /// In de, this message translates to:
  /// **'Zu dieser Familie ist niemand eingetragen.'**
  String get famstatLeer;

  /// No description provided for @famstatPersonen.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get famstatPersonen;

  /// No description provided for @famstatLebensalter.
  ///
  /// In de, this message translates to:
  /// **'Lebensalter'**
  String get famstatLebensalter;

  /// No description provided for @famstatHeiratsalter.
  ///
  /// In de, this message translates to:
  /// **'Heiratsalter'**
  String get famstatHeiratsalter;

  /// No description provided for @famstatHaeufigsterName.
  ///
  /// In de, this message translates to:
  /// **'Häufigster Nachname'**
  String get famstatHaeufigsterName;

  /// No description provided for @famstatJahre.
  ///
  /// In de, this message translates to:
  /// **'{jahre} Jahre'**
  String famstatJahre(String jahre);

  /// No description provided for @famstatSpanne.
  ///
  /// In de, this message translates to:
  /// **'{von} bis {bis} Jahre'**
  String famstatSpanne(int von, int bis);

  /// No description provided for @famstatOhneWert.
  ///
  /// In de, this message translates to:
  /// **'keine Angabe'**
  String get famstatOhneWert;

  /// No description provided for @famstatEingerechnet.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Person eingerechnet} other{{anzahl} Personen eingerechnet}}'**
  String famstatEingerechnet(int anzahl);

  /// No description provided for @famstatOhneSterbedatum.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person ohne Sterbedatum ist nicht eingerechnet.} other{{anzahl} Personen ohne Sterbedatum sind nicht eingerechnet.}}'**
  String famstatOhneSterbedatum(int anzahl);

  /// No description provided for @famstatWarumOhneSterbedatum.
  ///
  /// In de, this message translates to:
  /// **'Wer noch lebt, hat kein Sterbedatum. Als „null Jahre“ mitgezählt käme ein Durchschnitt heraus, der plausibel aussieht und grob falsch ist.'**
  String get famstatWarumOhneSterbedatum;

  /// No description provided for @famstatOhneGeburtsdatum.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Bei einer Hochzeit fehlt das Geburtsdatum; sie ist nicht eingerechnet.} other{Bei {anzahl} Hochzeiten fehlt das Geburtsdatum; sie sind nicht eingerechnet.}}'**
  String famstatOhneGeburtsdatum(int anzahl);

  /// No description provided for @famstatAlterJeGeneration.
  ///
  /// In de, this message translates to:
  /// **'Lebensalter über die Generationen'**
  String get famstatAlterJeGeneration;

  /// No description provided for @famstatGeneration.
  ///
  /// In de, this message translates to:
  /// **'{nummer}. Generation'**
  String famstatGeneration(int nummer);

  /// No description provided for @famstatGenerationKurz.
  ///
  /// In de, this message translates to:
  /// **'{nummer}.'**
  String famstatGenerationKurz(int nummer);

  /// No description provided for @famstatGenerationHinweis.
  ///
  /// In de, this message translates to:
  /// **'Die erste ist die älteste, die in dieser Familie vorkommt. Generationen, aus denen niemand verstorben ist, fehlen.'**
  String get famstatGenerationHinweis;

  /// No description provided for @famstatKinderzahl.
  ///
  /// In de, this message translates to:
  /// **'Kinder je Person'**
  String get famstatKinderzahl;

  /// No description provided for @famstatKinderHinweis.
  ///
  /// In de, this message translates to:
  /// **'Eine Verteilung, kein Durchschnitt: Die jüngste Generation steht bei null, weil sie ihre Kinder noch vor sich hat. Gezählt werden nur Kinder, die in dieser Familie auch stehen.'**
  String get famstatKinderHinweis;

  /// No description provided for @famstatKinderAchse.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{ohne Kinder} =1{ein Kind} other{{anzahl} Kinder}}'**
  String famstatKinderAchse(int anzahl);

  /// No description provided for @famstatNachnamen.
  ///
  /// In de, this message translates to:
  /// **'Nachnamen'**
  String get famstatNachnamen;

  /// No description provided for @famstatVornamen.
  ///
  /// In de, this message translates to:
  /// **'Vornamen'**
  String get famstatVornamen;

  /// No description provided for @famstatDiagrammGenerationen.
  ///
  /// In de, this message translates to:
  /// **'Lebensalter über die Generationen: {inhalt}'**
  String famstatDiagrammGenerationen(String inhalt);

  /// No description provided for @famstatDiagrammKinder.
  ///
  /// In de, this message translates to:
  /// **'Kinder je Person: {inhalt}'**
  String famstatDiagrammKinder(String inhalt);

  /// No description provided for @erkundenReisen.
  ///
  /// In de, this message translates to:
  /// **'Reisen'**
  String get erkundenReisen;

  /// No description provided for @erkundenAktivitaeten.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten'**
  String get erkundenAktivitaeten;

  /// No description provided for @gelaendeKarte.
  ///
  /// In de, this message translates to:
  /// **'Karte auf der Landschaft'**
  String get gelaendeKarte;

  /// No description provided for @kalenderGanzesJahr.
  ///
  /// In de, this message translates to:
  /// **'Ganzes Jahr'**
  String get kalenderGanzesJahr;

  /// No description provided for @einstSchwebeVorschauTitel.
  ///
  /// In de, this message translates to:
  /// **'Videos beim Schweben abspielen'**
  String get einstSchwebeVorschauTitel;

  /// No description provided for @einstSchwebeVorschauText.
  ///
  /// In de, this message translates to:
  /// **'Bleibt die Maus einen Augenblick über einem Video oder einem Live Photo stehen, läuft es in der Kachel an – ohne Ton und in Dauerschleife, bis der Zeiger weiterwandert. Es läuft immer nur eines. Gesperrte Aufnahmen bleiben still: Sie abzuspielen hiesse, sie nebenbei zu entschlüsseln. Ausgeschaltet bleiben die Kacheln Standbilder.'**
  String get einstSchwebeVorschauText;

  /// No description provided for @gelaendeStimmung.
  ///
  /// In de, this message translates to:
  /// **'Tageszeit'**
  String get gelaendeStimmung;

  /// No description provided for @stimmungMorgen.
  ///
  /// In de, this message translates to:
  /// **'Morgen'**
  String get stimmungMorgen;

  /// No description provided for @stimmungMittag.
  ///
  /// In de, this message translates to:
  /// **'Mittag'**
  String get stimmungMittag;

  /// No description provided for @stimmungAbend.
  ///
  /// In de, this message translates to:
  /// **'Abend'**
  String get stimmungAbend;

  /// No description provided for @stimmungBlaueStunde.
  ///
  /// In de, this message translates to:
  /// **'Blaue Stunde'**
  String get stimmungBlaueStunde;

  /// No description provided for @einstKarteScharfTitel.
  ///
  /// In de, this message translates to:
  /// **'Karte in doppelter Auflösung'**
  String get einstKarteScharfTitel;

  /// No description provided for @einstKarteScharfText.
  ///
  /// In de, this message translates to:
  /// **'Auf einem Bildschirm mit doppelter Punktdichte holt die Karte vier Kacheln der nächsttieferen Stufe und setzt sie an die Stelle einer: viermal so viele Bildpunkte, Hausnummern und Ladennamen werden lesbar. Der Preis sind rund zweieinhalbmal so viele Kacheln je Bildschirm – auf einer langsameren Maschine ruckelt das Zoomen dadurch spürbar. Ausgeschaltet zeichnet die Karte wie zuvor.'**
  String get einstKarteScharfText;

  /// No description provided for @routeVergroessern.
  ///
  /// In de, this message translates to:
  /// **'Karte vergrössern'**
  String get routeVergroessern;

  /// No description provided for @routeVerkleinern.
  ///
  /// In de, this message translates to:
  /// **'Karte verkleinern'**
  String get routeVerkleinern;

  /// No description provided for @reisenTitel.
  ///
  /// In de, this message translates to:
  /// **'Reisen'**
  String get reisenTitel;

  /// No description provided for @reisenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Reise. Photo Vault trägt sie nicht ein, sondern erkennt sie: Sobald genug verortete Aufnahmen aus der Ferne beisammen sind, erscheint hier ein Vorschlag zum Bestätigen.'**
  String get reisenLeer;

  /// No description provided for @reisenSuchtNoch.
  ///
  /// In de, this message translates to:
  /// **'Sucht nach Reisen …'**
  String get reisenSuchtNoch;

  /// No description provided for @reisenVorschlaege.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge'**
  String get reisenVorschlaege;

  /// No description provided for @reisenBestaetigte.
  ///
  /// In de, this message translates to:
  /// **'Deine Reisen'**
  String get reisenBestaetigte;

  /// No description provided for @reisenIstEineReise.
  ///
  /// In de, this message translates to:
  /// **'War eine Reise'**
  String get reisenIstEineReise;

  /// No description provided for @reisenKeineReise.
  ///
  /// In de, this message translates to:
  /// **'Keine Reise'**
  String get reisenKeineReise;

  /// No description provided for @reisenBenennen.
  ///
  /// In de, this message translates to:
  /// **'Reise benennen'**
  String get reisenBenennen;

  /// No description provided for @reisenName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get reisenName;

  /// No description provided for @reisenNotiz.
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get reisenNotiz;

  /// No description provided for @reisenTagesnotiz.
  ///
  /// In de, this message translates to:
  /// **'Notiz zu diesem Tag'**
  String get reisenTagesnotiz;

  /// No description provided for @reisenTagesnotizTitel.
  ///
  /// In de, this message translates to:
  /// **'{datum}'**
  String reisenTagesnotizTitel(String datum);

  /// No description provided for @reisenTagesnotizSchreiben.
  ///
  /// In de, this message translates to:
  /// **'Notiz zu diesem Tag schreiben'**
  String get reisenTagesnotizSchreiben;

  /// No description provided for @reisenTagesnotizAendern.
  ///
  /// In de, this message translates to:
  /// **'Notiz zu diesem Tag ändern'**
  String get reisenTagesnotizAendern;

  /// No description provided for @reisenUmbenennen.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get reisenUmbenennen;

  /// No description provided for @reisenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Reise entfernen'**
  String get reisenLoeschen;

  /// No description provided for @reisenLoeschenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ entfernen? Die Aufnahmen bleiben, wo sie sind.'**
  String reisenLoeschenFrage(String name);

  /// No description provided for @reisenOhneOrt.
  ///
  /// In de, this message translates to:
  /// **'Unbekannte Gegend'**
  String get reisenOhneOrt;

  /// No description provided for @reisenSpanne.
  ///
  /// In de, this message translates to:
  /// **'{von} bis {bis}'**
  String reisenSpanne(String von, String bis);

  /// No description provided for @reisenNaechte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Nacht} other{{anzahl} Nächte}}'**
  String reisenNaechte(int anzahl);

  /// No description provided for @reisenAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{keine Reise} =1{eine Reise} other{{anzahl} Reisen}}'**
  String reisenAnzahl(int anzahl);

  /// No description provided for @ortsbezugOrte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein Ort} other{{anzahl} Orte}}'**
  String ortsbezugOrte(int anzahl);

  /// No description provided for @ortsbezugWeitere.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein weiterer Ort} other{{anzahl} weitere Orte}}'**
  String ortsbezugWeitere(int anzahl);

  /// No description provided for @aktivitaetenAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{keine Aktivität} =1{eine Aktivität} other{{anzahl} Aktivitäten}}'**
  String aktivitaetenAnzahl(int anzahl);

  /// No description provided for @aktivitaetenMitReise.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine mit Reise} other{{anzahl} mit Reise}}'**
  String aktivitaetenMitReise(int anzahl);

  /// No description provided for @aktivitaetenOhneReiseZahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine einzelne} other{{anzahl} einzelne}}'**
  String aktivitaetenOhneReiseZahl(int anzahl);

  /// No description provided for @reisenAufnahmen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Aufnahme} other{{anzahl} Aufnahmen}}'**
  String reisenAufnahmen(int anzahl);

  /// No description provided for @reisenOrte.
  ///
  /// In de, this message translates to:
  /// **'Besuchte Orte'**
  String get reisenOrte;

  /// No description provided for @reisenAktualisieren.
  ///
  /// In de, this message translates to:
  /// **'Erneut suchen'**
  String get reisenAktualisieren;

  /// No description provided for @reisenRoute.
  ///
  /// In de, this message translates to:
  /// **'Route'**
  String get reisenRoute;

  /// No description provided for @reisenKeineRoute.
  ///
  /// In de, this message translates to:
  /// **'Ohne verortete Aufnahme gibt es keine Strecke.'**
  String get reisenKeineRoute;

  /// No description provided for @reisenAlsTitelbild.
  ///
  /// In de, this message translates to:
  /// **'Als Titelbild'**
  String get reisenAlsTitelbild;

  /// No description provided for @reisenTitelbildGesetzt.
  ///
  /// In de, this message translates to:
  /// **'Titelbild gesetzt.'**
  String get reisenTitelbildGesetzt;

  /// No description provided for @reisenTag.
  ///
  /// In de, this message translates to:
  /// **'{datum}'**
  String reisenTag(String datum);

  /// No description provided for @fortschrittLaender.
  ///
  /// In de, this message translates to:
  /// **'{besucht} von {gesamt} Ländern'**
  String fortschrittLaender(int besucht, int gesamt);

  /// No description provided for @fortschrittRegionen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{eine Region} other{{anzahl} Regionen}}'**
  String fortschrittRegionen(int anzahl);

  /// No description provided for @fortschrittOrte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{ein Ort} other{{anzahl} Orte}}'**
  String fortschrittOrte(int anzahl);

  /// No description provided for @fortschrittOhneGeodaten.
  ///
  /// In de, this message translates to:
  /// **'Ohne den GeoNames-Datensatz lässt sich keine Aufnahme einem Land zuordnen. Er wird unter „Werkzeuge“ geladen.'**
  String get fortschrittOhneGeodaten;

  /// No description provided for @fortschrittHinweis.
  ///
  /// In de, this message translates to:
  /// **'Gezählt wird gegen die {gesamt} Länder und Gebiete des GeoNames-Datensatzes – Überseegebiete eingeschlossen, nicht nur die 195 souveränen Staaten. Eine eigene, gepflegte Liste wäre eine zweite Wahrheit neben der, nach der die Fotos tatsächlich eingeordnet werden.'**
  String fortschrittHinweis(int gesamt);

  /// No description provided for @weltkarteTitel.
  ///
  /// In de, this message translates to:
  /// **'Weltkarte'**
  String get weltkarteTitel;

  /// No description provided for @weltkarteEbenen.
  ///
  /// In de, this message translates to:
  /// **'Ebenen'**
  String get weltkarteEbenen;

  /// No description provided for @weltkarteLaender.
  ///
  /// In de, this message translates to:
  /// **'Länder'**
  String get weltkarteLaender;

  /// No description provided for @weltkarteRegionen.
  ///
  /// In de, this message translates to:
  /// **'Regionen'**
  String get weltkarteRegionen;

  /// No description provided for @weltkarteOrte.
  ///
  /// In de, this message translates to:
  /// **'Orte'**
  String get weltkarteOrte;

  /// No description provided for @weltkarteKeinOrt.
  ///
  /// In de, this message translates to:
  /// **'An dieser Stelle kennt der Datensatz keinen Ort.'**
  String get weltkarteKeinOrt;

  /// No description provided for @weltkarteMarkeGesetzt.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist markiert.'**
  String weltkarteMarkeGesetzt(String name);

  /// No description provided for @weltkarteOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Weltkarte'**
  String get weltkarteOeffnen;

  /// No description provided for @laenderTitel.
  ///
  /// In de, this message translates to:
  /// **'Länderliste'**
  String get laenderTitel;

  /// No description provided for @laenderKopf.
  ///
  /// In de, this message translates to:
  /// **'{gesamt} Länder · {besucht} besucht · {teilweise} teilweise'**
  String laenderKopf(int gesamt, int besucht, int teilweise);

  /// No description provided for @laenderSuchen.
  ///
  /// In de, this message translates to:
  /// **'Land oder Hauptstadt suchen'**
  String get laenderSuchen;

  /// No description provided for @laenderFilter.
  ///
  /// In de, this message translates to:
  /// **'Filtern nach'**
  String get laenderFilter;

  /// No description provided for @laenderAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get laenderAlle;

  /// No description provided for @laenderLegende.
  ///
  /// In de, this message translates to:
  /// **'Legende'**
  String get laenderLegende;

  /// No description provided for @laenderAusFotos.
  ///
  /// In de, this message translates to:
  /// **'Durch Fotos belegt'**
  String get laenderAusFotos;

  /// No description provided for @laenderNurVonHand.
  ///
  /// In de, this message translates to:
  /// **'Von Hand ausgewählt'**
  String get laenderNurVonHand;

  /// No description provided for @laenderVollstaendig.
  ///
  /// In de, this message translates to:
  /// **'Vollständig'**
  String get laenderVollstaendig;

  /// No description provided for @laenderTeilweise.
  ///
  /// In de, this message translates to:
  /// **'Teilweise'**
  String get laenderTeilweise;

  /// No description provided for @laenderNichtBesucht.
  ///
  /// In de, this message translates to:
  /// **'Nicht besucht'**
  String get laenderNichtBesucht;

  /// No description provided for @laenderBesucht.
  ///
  /// In de, this message translates to:
  /// **'Besucht'**
  String get laenderBesucht;

  /// No description provided for @laenderGeplant.
  ///
  /// In de, this message translates to:
  /// **'Geplant'**
  String get laenderGeplant;

  /// No description provided for @laenderVerbleibend.
  ///
  /// In de, this message translates to:
  /// **'Verbleibend'**
  String get laenderVerbleibend;

  /// No description provided for @laenderRegionen.
  ///
  /// In de, this message translates to:
  /// **'{besucht} von {gesamt} Regionen'**
  String laenderRegionen(int besucht, int gesamt);

  /// No description provided for @laenderOhneRegionen.
  ///
  /// In de, this message translates to:
  /// **'Keine Regionen verzeichnet'**
  String get laenderOhneRegionen;

  /// No description provided for @laenderAufnahmen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{keine Aufnahme} =1{eine Aufnahme} other{{anzahl} Aufnahmen}}'**
  String laenderAufnahmen(int anzahl);

  /// No description provided for @laenderNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'Kein Land passt zur Suche.'**
  String get laenderNichtsGefunden;

  /// No description provided for @laenderMarkeBesucht.
  ///
  /// In de, this message translates to:
  /// **'Als besucht markieren'**
  String get laenderMarkeBesucht;

  /// No description provided for @laenderMarkeGeplant.
  ///
  /// In de, this message translates to:
  /// **'Als geplant markieren'**
  String get laenderMarkeGeplant;

  /// No description provided for @laenderMarkeWeg.
  ///
  /// In de, this message translates to:
  /// **'Marke entfernen'**
  String get laenderMarkeWeg;

  /// No description provided for @laenderVonHand.
  ///
  /// In de, this message translates to:
  /// **'von Hand'**
  String get laenderVonHand;

  /// No description provided for @laenderOhneGeodaten.
  ///
  /// In de, this message translates to:
  /// **'Ohne den GeoNames-Datensatz gibt es kein Länderverzeichnis. Er wird unter „Werkzeuge“ geladen.'**
  String get laenderOhneGeodaten;

  /// No description provided for @laenderHinweisMarke.
  ///
  /// In de, this message translates to:
  /// **'Was die Fotos belegen, steht hier von selbst. Von Hand markiert wird, wovon es kein Bild gibt – die Reise vor der ersten Digitalkamera oder das Ziel für nächstes Jahr.'**
  String get laenderHinweisMarke;

  /// No description provided for @erdteilEU.
  ///
  /// In de, this message translates to:
  /// **'Europa'**
  String get erdteilEU;

  /// No description provided for @erdteilAS.
  ///
  /// In de, this message translates to:
  /// **'Asien'**
  String get erdteilAS;

  /// No description provided for @erdteilNA.
  ///
  /// In de, this message translates to:
  /// **'Nordamerika'**
  String get erdteilNA;

  /// No description provided for @erdteilSA.
  ///
  /// In de, this message translates to:
  /// **'Südamerika'**
  String get erdteilSA;

  /// No description provided for @erdteilAF.
  ///
  /// In de, this message translates to:
  /// **'Afrika'**
  String get erdteilAF;

  /// No description provided for @erdteilOC.
  ///
  /// In de, this message translates to:
  /// **'Ozeanien'**
  String get erdteilOC;

  /// No description provided for @erdteilAN.
  ///
  /// In de, this message translates to:
  /// **'Antarktis'**
  String get erdteilAN;

  /// No description provided for @erdteilUnbekannt.
  ///
  /// In de, this message translates to:
  /// **'Ohne Erdteil'**
  String get erdteilUnbekannt;

  /// No description provided for @werkzGpxTitel.
  ///
  /// In de, this message translates to:
  /// **'Aus einer GPX-Spur verorten'**
  String get werkzGpxTitel;

  /// No description provided for @werkzGpxText.
  ///
  /// In de, this message translates to:
  /// **'Eine Aufzeichnung trägt Zeitstempel. Damit bekommen auch Aufnahmen aus Kameras ohne GPS ihren Ort.'**
  String get werkzGpxText;

  /// No description provided for @gpxTitel.
  ///
  /// In de, this message translates to:
  /// **'Aus GPX verorten'**
  String get gpxTitel;

  /// No description provided for @gpxDateiWaehlen.
  ///
  /// In de, this message translates to:
  /// **'GPX-Datei wählen …'**
  String get gpxDateiWaehlen;

  /// No description provided for @gpxErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Wähle eine Aufzeichnung. Photo Vault legt die Aufnahmezeiten deiner Fotos gegen die Spur und trägt die Koordinate nach – nur bei Aufnahmen, die noch keine haben.'**
  String get gpxErklaerung;

  /// No description provided for @gpxSpur.
  ///
  /// In de, this message translates to:
  /// **'{punkte} Punkte · {von} bis {bis}'**
  String gpxSpur(int punkte, String von, String bis);

  /// No description provided for @gpxVersatz.
  ///
  /// In de, this message translates to:
  /// **'Zeitversatz'**
  String get gpxVersatz;

  /// No description provided for @gpxVersatzHinweis.
  ///
  /// In de, this message translates to:
  /// **'EXIF schreibt die Aufnahmezeit ohne Zeitzone, GPX schreibt UTC. Der Vorschlag ist der Versatz, bei dem die meisten Aufnahmen auf die Spur passen – er fängt auch eine falsch gehende Kamerauhr ab.'**
  String get gpxVersatzHinweis;

  /// No description provided for @gpxTreffer.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Keine Aufnahme passt auf die Spur.} =1{Eine Aufnahme bekommt einen Ort.} other{{anzahl} Aufnahmen bekommen einen Ort.}}'**
  String gpxTreffer(int anzahl);

  /// No description provided for @gpxVerorten.
  ///
  /// In de, this message translates to:
  /// **'Verorten'**
  String get gpxVerorten;

  /// No description provided for @gpxFertig.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Aufnahme verortet.} other{{anzahl} Aufnahmen verortet.}}'**
  String gpxFertig(int anzahl);

  /// No description provided for @gpxKeineKandidaten.
  ///
  /// In de, this message translates to:
  /// **'Im Zeitraum dieser Spur hat jede Aufnahme schon einen Ort.'**
  String get gpxKeineKandidaten;

  /// No description provided for @gpxFehlerKeinGpx.
  ///
  /// In de, this message translates to:
  /// **'Das ist keine GPX-Datei.'**
  String get gpxFehlerKeinGpx;

  /// No description provided for @gpxFehlerOhneZeit.
  ///
  /// In de, this message translates to:
  /// **'In dieser Spur trägt kein Punkt einen Zeitstempel. Ohne Zeit lässt sich keine Aufnahme zuordnen.'**
  String get gpxFehlerOhneZeit;

  /// No description provided for @gpxFehlerLeer.
  ///
  /// In de, this message translates to:
  /// **'Die Datei enthält keinen einzigen Punkt.'**
  String get gpxFehlerLeer;

  /// No description provided for @stammbaumKeineFamilienfotos.
  ///
  /// In de, this message translates to:
  /// **'Auf keinem Foto wurde bisher jemand aus dieser Familie erkannt.'**
  String get stammbaumKeineFamilienfotos;

  /// No description provided for @stammbaumGedcomExport.
  ///
  /// In de, this message translates to:
  /// **'Als GEDCOM ausgeben …'**
  String get stammbaumGedcomExport;

  /// No description provided for @stammbaumGedcomFertig.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Eine Person ausgegeben.} other{{anzahl} Personen ausgegeben.}}'**
  String stammbaumGedcomFertig(int anzahl);

  /// No description provided for @gradAdoptiveltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Adoptivmutter} m{Adoptivvater} other{Adoptivelternteil}}'**
  String gradAdoptiveltern(String geschlecht);

  /// No description provided for @gradPflegeeltern.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Pflegemutter} m{Pflegevater} other{Pflegeelternteil}}'**
  String gradPflegeeltern(String geschlecht);

  /// No description provided for @gradAdoptivkind.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Adoptivtochter} m{Adoptivsohn} other{Adoptivkind}}'**
  String gradAdoptivkind(String geschlecht);

  /// No description provided for @gradPflegekind.
  ///
  /// In de, this message translates to:
  /// **'{geschlecht, select, w{Pflegetochter} m{Pflegesohn} other{Pflegekind}}'**
  String gradPflegekind(String geschlecht);

  /// No description provided for @stammbaumLeiblich.
  ///
  /// In de, this message translates to:
  /// **'Leiblich'**
  String get stammbaumLeiblich;

  /// No description provided for @stammbaumAdoptiv.
  ///
  /// In de, this message translates to:
  /// **'Adoptiv'**
  String get stammbaumAdoptiv;

  /// No description provided for @stammbaumPflege.
  ///
  /// In de, this message translates to:
  /// **'Pflege'**
  String get stammbaumPflege;

  /// No description provided for @stammbaumAnsichtSanduhr.
  ///
  /// In de, this message translates to:
  /// **'Sanduhr'**
  String get stammbaumAnsichtSanduhr;

  /// No description provided for @stammbaumSeitenlinien.
  ///
  /// In de, this message translates to:
  /// **'Seitenlinie'**
  String get stammbaumSeitenlinien;

  /// No description provided for @stammbaumSeitenlinienHinweis.
  ///
  /// In de, this message translates to:
  /// **'Geschwister neben der Person, deren Kinder darunter – so werden auch Neffen, Nichten und Schwäger sichtbar.'**
  String get stammbaumSeitenlinienHinweis;

  /// No description provided for @lebenslaufVon.
  ///
  /// In de, this message translates to:
  /// **'Lebenslauf: {name}'**
  String lebenslaufVon(String name);

  /// No description provided for @lebenslaufHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Ereignis hinzufügen'**
  String get lebenslaufHinzufuegen;

  /// No description provided for @lebenslaufLeer.
  ///
  /// In de, this message translates to:
  /// **'Für diese Person ist noch nichts eingetragen. Geburt und Tod stehen bei den Angaben zur Person; hier kommen Hochzeit, Umzug, Beruf und alles Weitere hin.'**
  String get lebenslaufLeer;

  /// No description provided for @lebenslaufGeburt.
  ///
  /// In de, this message translates to:
  /// **'Geboren'**
  String get lebenslaufGeburt;

  /// No description provided for @lebenslaufTod.
  ///
  /// In de, this message translates to:
  /// **'Gestorben'**
  String get lebenslaufTod;

  /// No description provided for @lebenslaufHochzeit.
  ///
  /// In de, this message translates to:
  /// **'Hochzeit'**
  String get lebenslaufHochzeit;

  /// No description provided for @lebenslaufUmzug.
  ///
  /// In de, this message translates to:
  /// **'Umzug'**
  String get lebenslaufUmzug;

  /// No description provided for @lebenslaufBeruf.
  ///
  /// In de, this message translates to:
  /// **'Beruf'**
  String get lebenslaufBeruf;

  /// No description provided for @lebenslaufAusbildung.
  ///
  /// In de, this message translates to:
  /// **'Ausbildung'**
  String get lebenslaufAusbildung;

  /// No description provided for @lebenslaufSonstiges.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get lebenslaufSonstiges;

  /// No description provided for @lebenslaufOhneDatum.
  ///
  /// In de, this message translates to:
  /// **'ohne Datum'**
  String get lebenslaufOhneDatum;

  /// No description provided for @lebenslaufOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get lebenslaufOrt;

  /// No description provided for @lebenslaufOrtAufKarte.
  ///
  /// In de, this message translates to:
  /// **'Ort auf der Karte'**
  String get lebenslaufOrtAufKarte;

  /// No description provided for @lebenslaufOrtErkannt.
  ///
  /// In de, this message translates to:
  /// **'Auf der Karte gefunden – tippen, um den Punkt zu berichtigen.'**
  String get lebenslaufOrtErkannt;

  /// No description provided for @lebenslaufOrtUnbekannt.
  ///
  /// In de, this message translates to:
  /// **'Dieser Ort ist im Ortsverzeichnis nicht enthalten. Tippen Sie auf die Karte, um ihn selbst zu setzen.'**
  String get lebenslaufOrtUnbekannt;

  /// No description provided for @lebenslaufOrtEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Verortung entfernen'**
  String get lebenslaufOrtEntfernen;

  /// No description provided for @lebenslaufOrtOhneVerzeichnis.
  ///
  /// In de, this message translates to:
  /// **'Ohne das Ortsverzeichnis lassen sich Orte nicht automatisch finden. Ein Punkt lässt sich trotzdem von Hand setzen.'**
  String get lebenslaufOrtOhneVerzeichnis;

  /// No description provided for @lebenslaufNotiz.
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get lebenslaufNotiz;

  /// No description provided for @stammbaumLebenslauf.
  ///
  /// In de, this message translates to:
  /// **'Lebenslauf …'**
  String get stammbaumLebenslauf;

  /// No description provided for @orteIch.
  ///
  /// In de, this message translates to:
  /// **'Diese Person'**
  String get orteIch;

  /// No description provided for @orteVorfahren.
  ///
  /// In de, this message translates to:
  /// **'Vorfahren'**
  String get orteVorfahren;

  /// No description provided for @orteNachkommen.
  ///
  /// In de, this message translates to:
  /// **'Nachkommen'**
  String get orteNachkommen;

  /// No description provided for @orteSeitenlinie.
  ///
  /// In de, this message translates to:
  /// **'Seitenlinie'**
  String get orteSeitenlinie;

  /// No description provided for @orteAngeheiratet.
  ///
  /// In de, this message translates to:
  /// **'Angeheiratet'**
  String get orteAngeheiratet;

  /// No description provided for @orteEreignisse.
  ///
  /// In de, this message translates to:
  /// **'Ereignisse'**
  String get orteEreignisse;

  /// No description provided for @orteNichtsGewaehlt.
  ///
  /// In de, this message translates to:
  /// **'Keine Gruppe ausgewählt.'**
  String get orteNichtsGewaehlt;

  /// No description provided for @stammbaumFamilienorte.
  ///
  /// In de, this message translates to:
  /// **'Orte der Familie'**
  String get stammbaumFamilienorte;

  /// No description provided for @stammbaumMenue.
  ///
  /// In de, this message translates to:
  /// **'Mehr zu dieser Person'**
  String get stammbaumMenue;

  /// No description provided for @stammbaumVerbindungsart.
  ///
  /// In de, this message translates to:
  /// **'Art der Verbindung …'**
  String get stammbaumVerbindungsart;

  /// No description provided for @stammbaumVerbindungsartTitel.
  ///
  /// In de, this message translates to:
  /// **'Wie ist {kind} mit {elternteil} verbunden?'**
  String stammbaumVerbindungsartTitel(String kind, String elternteil);

  /// No description provided for @stammbaumVerbindungsartHinweis.
  ///
  /// In de, this message translates to:
  /// **'Adoptiv- und Pflegeeltern zählen überall als Eltern – nur die Bezeichnung und die gestrichelte Linie unterscheiden sie.'**
  String get stammbaumVerbindungsartHinweis;

  /// No description provided for @stammbaumNichtsEntfernt.
  ///
  /// In de, this message translates to:
  /// **'Diese Verbindung war schon gelöst.'**
  String get stammbaumNichtsEntfernt;

  /// No description provided for @stammbaumWeitereVerwandte.
  ///
  /// In de, this message translates to:
  /// **'Weitere Verwandte'**
  String get stammbaumWeitereVerwandte;

  /// No description provided for @stammbaumVerwandtenHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Verwandten hinzufügen …'**
  String get stammbaumVerwandtenHinzufuegen;

  /// No description provided for @stammbaumGruppeVorfahren.
  ///
  /// In de, this message translates to:
  /// **'Vorfahren'**
  String get stammbaumGruppeVorfahren;

  /// No description provided for @stammbaumGruppeNachkommen.
  ///
  /// In de, this message translates to:
  /// **'Nachkommen'**
  String get stammbaumGruppeNachkommen;

  /// No description provided for @stammbaumGruppeSeitenlinie.
  ///
  /// In de, this message translates to:
  /// **'Seitenlinie'**
  String get stammbaumGruppeSeitenlinie;

  /// No description provided for @stammbaumGruppeAngeheiratet.
  ///
  /// In de, this message translates to:
  /// **'Angeheiratet'**
  String get stammbaumGruppeAngeheiratet;

  /// No description provided for @stammbaumGradGrosselternteil.
  ///
  /// In de, this message translates to:
  /// **'Großelternteil'**
  String get stammbaumGradGrosselternteil;

  /// No description provided for @stammbaumGradUrgrosselternteil.
  ///
  /// In de, this message translates to:
  /// **'Urgroßelternteil'**
  String get stammbaumGradUrgrosselternteil;

  /// No description provided for @stammbaumGradEnkelkind.
  ///
  /// In de, this message translates to:
  /// **'Enkelkind'**
  String get stammbaumGradEnkelkind;

  /// No description provided for @stammbaumGradUrenkelkind.
  ///
  /// In de, this message translates to:
  /// **'Urenkelkind'**
  String get stammbaumGradUrenkelkind;

  /// No description provided for @stammbaumGradGeschwisterkind.
  ///
  /// In de, this message translates to:
  /// **'Geschwisterkind'**
  String get stammbaumGradGeschwisterkind;

  /// No description provided for @stammbaumGradHalbgeschwisterkind.
  ///
  /// In de, this message translates to:
  /// **'Halbgeschwisterkind'**
  String get stammbaumGradHalbgeschwisterkind;

  /// No description provided for @stammbaumGradOnkelTante.
  ///
  /// In de, this message translates to:
  /// **'Onkel oder Tante'**
  String get stammbaumGradOnkelTante;

  /// No description provided for @stammbaumGradNeffeNichte.
  ///
  /// In de, this message translates to:
  /// **'Neffe oder Nichte'**
  String get stammbaumGradNeffeNichte;

  /// No description provided for @stammbaumGradCousin.
  ///
  /// In de, this message translates to:
  /// **'Cousin oder Cousine'**
  String get stammbaumGradCousin;

  /// No description provided for @stammbaumGradSchwiegerelternteil.
  ///
  /// In de, this message translates to:
  /// **'Schwiegerelternteil'**
  String get stammbaumGradSchwiegerelternteil;

  /// No description provided for @stammbaumGradSchwiegerkind.
  ///
  /// In de, this message translates to:
  /// **'Schwiegerkind'**
  String get stammbaumGradSchwiegerkind;

  /// No description provided for @stammbaumGradSchwager.
  ///
  /// In de, this message translates to:
  /// **'Schwager oder Schwägerin'**
  String get stammbaumGradSchwager;

  /// No description provided for @stammbaumGradStiefelternteil.
  ///
  /// In de, this message translates to:
  /// **'Stiefelternteil'**
  String get stammbaumGradStiefelternteil;

  /// No description provided for @stammbaumGradStiefkind.
  ///
  /// In de, this message translates to:
  /// **'Stiefkind'**
  String get stammbaumGradStiefkind;

  /// No description provided for @stammbaumFehltElternteil.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst einen Elternteil.'**
  String stammbaumFehltElternteil(String name);

  /// No description provided for @stammbaumFehltGrosselternteil.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst Großeltern.'**
  String stammbaumFehltGrosselternteil(String name);

  /// No description provided for @stammbaumFehltKind.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst ein Kind.'**
  String stammbaumFehltKind(String name);

  /// No description provided for @stammbaumFehltEnkelkind.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst ein Enkelkind.'**
  String stammbaumFehltEnkelkind(String name);

  /// No description provided for @stammbaumFehltGeschwister.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst ein Geschwisterkind.'**
  String stammbaumFehltGeschwister(String name);

  /// No description provided for @stammbaumFehltOnkelTante.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst einen Onkel oder eine Tante.'**
  String stammbaumFehltOnkelTante(String name);

  /// No description provided for @stammbaumFehltPartner.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst einen Partner.'**
  String stammbaumFehltPartner(String name);

  /// No description provided for @stammbaumFehltGeschwisterOderPartner.
  ///
  /// In de, this message translates to:
  /// **'Dafür braucht {name} zuerst ein Geschwisterkind oder einen Partner.'**
  String stammbaumFehltGeschwisterOderPartner(String name);

  /// No description provided for @stammbaumUeberWen.
  ///
  /// In de, this message translates to:
  /// **'{grad} – über wen?'**
  String stammbaumUeberWen(String grad);

  /// No description provided for @stammbaumVerwandterEingetragen.
  ///
  /// In de, this message translates to:
  /// **'{name} ist eingetragen – {bezeichnung}.'**
  String stammbaumVerwandterEingetragen(String name, String bezeichnung);

  /// No description provided for @stammbaumNurEintragbares.
  ///
  /// In de, this message translates to:
  /// **'Gezeigt wird, was sich für {name} eintragen lässt. Grau bedeutet: Dafür fehlt noch eine Zwischenperson.'**
  String stammbaumNurEintragbares(String name);

  /// No description provided for @stammbaumFamilienorteVon.
  ///
  /// In de, this message translates to:
  /// **'Orte der Familie von {name}'**
  String stammbaumFamilienorteVon(String name);

  /// No description provided for @stammbaumKeineFamilienorte.
  ///
  /// In de, this message translates to:
  /// **'Von dieser Familie ist kein Foto mit Ortsangabe vorhanden.'**
  String get stammbaumKeineFamilienorte;

  /// No description provided for @stammbaumZierbaumDrucken.
  ///
  /// In de, this message translates to:
  /// **'Zierbaum als PDF'**
  String get stammbaumZierbaumDrucken;

  /// No description provided for @stammbaumTafelDrucken.
  ///
  /// In de, this message translates to:
  /// **'Tafel als PDF …'**
  String get stammbaumTafelDrucken;

  /// No description provided for @stammbaumTafelFertig.
  ///
  /// In de, this message translates to:
  /// **'Die Tafel wurde geschrieben.'**
  String get stammbaumTafelFertig;

  /// No description provided for @aufgWirdErmittelt.
  ///
  /// In de, this message translates to:
  /// **'Wird ermittelt …'**
  String get aufgWirdErmittelt;

  /// No description provided for @aufgAbgebrochenBei.
  ///
  /// In de, this message translates to:
  /// **'Abgebrochen bei {erledigt} von {gesamt}'**
  String aufgAbgebrochenBei(int erledigt, int gesamt);

  /// No description provided for @aufgFertigMit.
  ///
  /// In de, this message translates to:
  /// **'Fertig – {gesamt} bearbeitet'**
  String aufgFertigMit(int gesamt);

  /// No description provided for @beendenTitel.
  ///
  /// In de, this message translates to:
  /// **'Es wird noch ausgewertet'**
  String get beendenTitel;

  /// No description provided for @beendenText.
  ///
  /// In de, this message translates to:
  /// **'Beim Beenden geht die gerade bearbeitete Datei verloren; alles bereits Ausgewertete bleibt erhalten. Noch am Laufen:'**
  String get beendenText;

  /// No description provided for @beendenTrotzdem.
  ///
  /// In de, this message translates to:
  /// **'Trotzdem beenden'**
  String get beendenTrotzdem;

  /// No description provided for @beendenWeiterlaufen.
  ///
  /// In de, this message translates to:
  /// **'Weiterlaufen lassen'**
  String get beendenWeiterlaufen;

  /// No description provided for @aufgUebersetzenTitel.
  ///
  /// In de, this message translates to:
  /// **'Beschreibungen übersetzen'**
  String get aufgUebersetzenTitel;

  /// No description provided for @aufgUebersetzenText.
  ///
  /// In de, this message translates to:
  /// **'Überträgt die vorhandenen englischen KI-Bildunterschriften ins Deutsche – ohne das Beschreibungsmodell erneut laufen zu lassen.'**
  String get aufgUebersetzenText;

  /// No description provided for @aufgUebersetzungsmodell.
  ///
  /// In de, this message translates to:
  /// **'das Übersetzungsmodell Englisch → Deutsch'**
  String get aufgUebersetzungsmodell;

  /// No description provided for @werkzUebersetzeBeschreibungen.
  ///
  /// In de, this message translates to:
  /// **'Übersetze Bildbeschreibungen …'**
  String get werkzUebersetzeBeschreibungen;

  /// No description provided for @werkzAlleUebersetzt.
  ///
  /// In de, this message translates to:
  /// **'Alle Beschreibungen sind übersetzt.'**
  String get werkzAlleUebersetzt;

  /// No description provided for @aufgLaeuftSchon.
  ///
  /// In de, this message translates to:
  /// **'Diese Auswertung läuft bereits.'**
  String get aufgLaeuftSchon;

  /// No description provided for @infoKiBeschreibungVonHand.
  ///
  /// In de, this message translates to:
  /// **'KI-Beschreibung, von Hand geändert'**
  String get infoKiBeschreibungVonHand;

  /// No description provided for @infoKiVonHandHinweis.
  ///
  /// In de, this message translates to:
  /// **'Bleibt bei „Alle Fotos“ erhalten. Zum Neuberechnen das Feld leeren.'**
  String get infoKiVonHandHinweis;

  /// No description provided for @infoSpracheDe.
  ///
  /// In de, this message translates to:
  /// **'DE'**
  String get infoSpracheDe;

  /// No description provided for @infoSpracheEn.
  ///
  /// In de, this message translates to:
  /// **'EN'**
  String get infoSpracheEn;

  /// No description provided for @infoKiPlatzhalterDe.
  ///
  /// In de, this message translates to:
  /// **'Deutsche Fassung eintragen'**
  String get infoKiPlatzhalterDe;

  /// No description provided for @infoKiPlatzhalterEn.
  ///
  /// In de, this message translates to:
  /// **'Englische Fassung eintragen'**
  String get infoKiPlatzhalterEn;

  /// No description provided for @duplGefunden.
  ///
  /// In de, this message translates to:
  /// **'{gruppen} Gruppen mit {fotos} Fotos'**
  String duplGefunden(int gruppen, int fotos);

  /// No description provided for @duplNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'Keine Gruppen gefunden'**
  String get duplNichtsGefunden;

  /// No description provided for @duplGruppeIgnorieren.
  ///
  /// In de, this message translates to:
  /// **'Übergehen'**
  String get duplGruppeIgnorieren;

  /// No description provided for @duplGruppeIgnoriert.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Fotos werden bei der Duplikatsuche künftig übergangen.'**
  String duplGruppeIgnoriert(int anzahl);

  /// No description provided for @duplAusnahmenZahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} übergangen'**
  String duplAusnahmenZahl(int anzahl);

  /// No description provided for @duplAusnahmenTitel.
  ///
  /// In de, this message translates to:
  /// **'Übergangene wieder anzeigen'**
  String get duplAusnahmenTitel;

  /// No description provided for @duplAusnahmenFrage.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Paare sind von der Suche ausgenommen. Sollen alle wieder berücksichtigt werden?'**
  String duplAusnahmenFrage(int anzahl);

  /// No description provided for @duplAusnahmenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Alle wieder anzeigen'**
  String get duplAusnahmenLoeschen;

  /// No description provided for @entwNurMitCoreImage.
  ///
  /// In de, this message translates to:
  /// **'Schärfe, Rauschunterdrückung, Klarheit und Vignettierung brauchen Rechenschritte, die es nur unter macOS gibt. Die übrigen Regler wirken hier vollständig.'**
  String get entwNurMitCoreImage;

  /// No description provided for @modellOcrTitel.
  ///
  /// In de, this message translates to:
  /// **'Texterkennung (PaddleOCR)'**
  String get modellOcrTitel;

  /// No description provided for @modellOcrText.
  ///
  /// In de, this message translates to:
  /// **'Findet Text in Fotos und liest ihn – zwei Modelle, zusammen 13,7 MB. Deckt das lateinische Alphabet samt Umlauten und ß ab. Unter macOS nicht nötig: Dort erledigt das Apples Vision-Framework ohne Download.'**
  String get modellOcrText;

  /// No description provided for @modellOcrLizenz.
  ///
  /// In de, this message translates to:
  /// **'Apache 2.0 (PaddleOCR)'**
  String get modellOcrLizenz;

  /// No description provided for @aufgOcrModell.
  ///
  /// In de, this message translates to:
  /// **'das Texterkennungs-Modell'**
  String get aufgOcrModell;

  /// No description provided for @werkzDatumTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmedatum aus RAW und Videos nachtragen'**
  String get werkzDatumTitel;

  /// No description provided for @werkzDatumFrageTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmedatum richtigstellen?'**
  String get werkzDatumFrageTitel;

  /// No description provided for @werkzDatumFrage.
  ///
  /// In de, this message translates to:
  /// **'Fotos, deren Aufnahmedatum bisher vom Dateizeitstempel stammte, bekommen das echte Datum aus der RAW-Datei. Sie rücken damit in der Zeitleiste und im Kalender an die richtige Stelle und werden auf der Festplatte in den passenden Monatsordner verschoben.\n\nDie Fotos selbst werden nicht verändert. Rückgängig machen lässt sich der Lauf nicht.'**
  String get werkzDatumFrage;

  /// No description provided for @werkzDatumStarten.
  ///
  /// In de, this message translates to:
  /// **'Richtigstellen'**
  String get werkzDatumStarten;

  /// No description provided for @werkzKorrigiereDatum.
  ///
  /// In de, this message translates to:
  /// **'Lese Aufnahmedaten aus RAW und Videos …'**
  String get werkzKorrigiereDatum;

  /// No description provided for @werkzKeineRawFotos.
  ///
  /// In de, this message translates to:
  /// **'Keine RAW-Aufnahmen und keine Videos in der Bibliothek.'**
  String get werkzKeineRawFotos;

  /// No description provided for @karteGlobusZoomHinweis.
  ///
  /// In de, this message translates to:
  /// **'Weiter heranzoomen zeigt keine zusätzlichen Details – die Erdtextur ist ein einzelnes Bild. Tippe auf einen Pin, um an dieser Stelle in die Karte zu wechseln.'**
  String get karteGlobusZoomHinweis;

  /// No description provided for @karteHineinzoomen.
  ///
  /// In de, this message translates to:
  /// **'Näher heran'**
  String get karteHineinzoomen;

  /// No description provided for @karteHerauszoomen.
  ///
  /// In de, this message translates to:
  /// **'Weiter weg'**
  String get karteHerauszoomen;

  /// No description provided for @zoomEinpassen.
  ///
  /// In de, this message translates to:
  /// **'Ganz zeigen'**
  String get zoomEinpassen;

  /// No description provided for @karteEreignisseEinblenden.
  ///
  /// In de, this message translates to:
  /// **'Lebensereignisse einblenden'**
  String get karteEreignisseEinblenden;

  /// No description provided for @karteEreignisseAusblenden.
  ///
  /// In de, this message translates to:
  /// **'Lebensereignisse ausblenden'**
  String get karteEreignisseAusblenden;

  /// No description provided for @karteStandortZeigen.
  ///
  /// In de, this message translates to:
  /// **'Mein Standort'**
  String get karteStandortZeigen;

  /// No description provided for @karteStandortNichtErmittelbar.
  ///
  /// In de, this message translates to:
  /// **'Standort nicht ermittelbar. Prüfe unter Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste, ob Photo Vault fragen darf.'**
  String get karteStandortNichtErmittelbar;

  /// No description provided for @karteStandortSuche.
  ///
  /// In de, this message translates to:
  /// **'Standort wird ermittelt …'**
  String get karteStandortSuche;

  /// No description provided for @weltkarteKlickMarkiert.
  ///
  /// In de, this message translates to:
  /// **'Ein Klick markiert'**
  String get weltkarteKlickMarkiert;

  /// No description provided for @weltkarteMarkeWeggenommen.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ist nicht mehr markiert.'**
  String weltkarteMarkeWeggenommen(String name);

  /// No description provided for @weltkarteSchonBelegt.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ belegen deine Fotos bereits.'**
  String weltkarteSchonBelegt(String name);

  /// No description provided for @weltkarteLegende.
  ///
  /// In de, this message translates to:
  /// **'Woher eine Marke stammt'**
  String get weltkarteLegende;

  /// No description provided for @weltkarteLegendeFotos.
  ///
  /// In de, this message translates to:
  /// **'Ausgefüllt, durchgezogener Rand: durch verortete Aufnahmen belegt.'**
  String get weltkarteLegendeFotos;

  /// No description provided for @weltkarteLegendeHand.
  ///
  /// In de, this message translates to:
  /// **'Blass, gepunkteter Rand: von Hand markiert, ohne Foto.'**
  String get weltkarteLegendeHand;

  /// No description provided for @weltkarteLegendeGeplant.
  ///
  /// In de, this message translates to:
  /// **'Fast leer, gestrichelter Rand: geplant – zählt nicht als besucht.'**
  String get weltkarteLegendeGeplant;

  /// No description provided for @weltkarteOhneUmriss.
  ///
  /// In de, this message translates to:
  /// **'Für kleine Gebiete wie den Vatikan liegt kein Umriss vor; sie bleiben ein Punkt.'**
  String get weltkarteOhneUmriss;

  /// No description provided for @ortRegionen.
  ///
  /// In de, this message translates to:
  /// **'Regionen · {besucht} von {gesamt}'**
  String ortRegionen(int besucht, int gesamt);

  /// No description provided for @ortOrte.
  ///
  /// In de, this message translates to:
  /// **'Orte · {besucht} von {gesamt}'**
  String ortOrte(int besucht, int gesamt);

  /// No description provided for @ortFotos.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Foto} other{{anzahl} Fotos}}'**
  String ortFotos(int anzahl);

  /// No description provided for @ortNichtsHier.
  ///
  /// In de, this message translates to:
  /// **'Von hier gibt es noch nichts – kein Foto, und der Datensatz kennt keine weitere Ebene darunter.'**
  String get ortNichtsHier;

  /// No description provided for @meldungenTitel.
  ///
  /// In de, this message translates to:
  /// **'Meldungen'**
  String get meldungenTitel;

  /// No description provided for @meldungenKeine.
  ///
  /// In de, this message translates to:
  /// **'Bisher nichts zu melden.'**
  String get meldungenKeine;

  /// No description provided for @meldungenGlocke.
  ///
  /// In de, this message translates to:
  /// **'Meldungen ansehen'**
  String get meldungenGlocke;

  /// No description provided for @meldungSchliessen.
  ///
  /// In de, this message translates to:
  /// **'Meldung schliessen'**
  String get meldungSchliessen;

  /// No description provided for @meldungenAlleSchliessen.
  ///
  /// In de, this message translates to:
  /// **'Alle ausblenden'**
  String get meldungenAlleSchliessen;

  /// No description provided for @meldungenVerlaufLeeren.
  ///
  /// In de, this message translates to:
  /// **'Verlauf leeren'**
  String get meldungenVerlaufLeeren;

  /// No description provided for @meldungWiederholt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl}×'**
  String meldungWiederholt(int anzahl);

  /// No description provided for @meldungArtHinweis.
  ///
  /// In de, this message translates to:
  /// **'Hinweis'**
  String get meldungArtHinweis;

  /// No description provided for @meldungArtErfolg.
  ///
  /// In de, this message translates to:
  /// **'Erledigt'**
  String get meldungArtErfolg;

  /// No description provided for @meldungArtWarnung.
  ///
  /// In de, this message translates to:
  /// **'Warnung'**
  String get meldungArtWarnung;

  /// No description provided for @meldungArtFehler.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get meldungArtFehler;

  /// No description provided for @aktivitaetenTitel.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten'**
  String get aktivitaetenTitel;

  /// No description provided for @aktivitaetenOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten ansehen'**
  String get aktivitaetenOeffnen;

  /// No description provided for @aktivitaetenVorschlaege.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge'**
  String get aktivitaetenVorschlaege;

  /// No description provided for @aktivitaetenBestaetigte.
  ///
  /// In de, this message translates to:
  /// **'Auf Reisen'**
  String get aktivitaetenBestaetigte;

  /// No description provided for @aktivitaetenOhneReise.
  ///
  /// In de, this message translates to:
  /// **'Für sich'**
  String get aktivitaetenOhneReise;

  /// No description provided for @aktivitaetenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aktivität. Wanderungen, Radtouren und Ausflüge werden aus den Aufnahmen eines Tages erkannt – gebraucht werden eine Handvoll verortete Bilder über mindestens eine Dreiviertelstunde.'**
  String get aktivitaetenLeer;

  /// No description provided for @aktivitaetenSuchtNoch.
  ///
  /// In de, this message translates to:
  /// **'Sucht nach Unternehmungen …'**
  String get aktivitaetenSuchtNoch;

  /// No description provided for @aktivitaetenBenennen.
  ///
  /// In de, this message translates to:
  /// **'Aktivität benennen'**
  String get aktivitaetenBenennen;

  /// No description provided for @aktivitaetenUmbenennen.
  ///
  /// In de, this message translates to:
  /// **'Umbenennen'**
  String get aktivitaetenUmbenennen;

  /// No description provided for @aktivitaetenName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get aktivitaetenName;

  /// No description provided for @aktivitaetenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Aktivität löschen'**
  String get aktivitaetenLoeschen;

  /// No description provided for @aktivitaetenLoeschenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{name}\" aus der Liste nehmen? Die Fotos bleiben, wo sie sind.'**
  String aktivitaetenLoeschenFrage(String name);

  /// No description provided for @aktivitaetenNotiz.
  ///
  /// In de, this message translates to:
  /// **'Notiz'**
  String get aktivitaetenNotiz;

  /// No description provided for @aktivitaetenArtAendern.
  ///
  /// In de, this message translates to:
  /// **'Art ändern'**
  String get aktivitaetenArtAendern;

  /// No description provided for @aktivitaetenStrecke.
  ///
  /// In de, this message translates to:
  /// **'{km} km'**
  String aktivitaetenStrecke(String km);

  /// No description provided for @aktivitaetenDauer.
  ///
  /// In de, this message translates to:
  /// **'{stunden} h {minuten} min'**
  String aktivitaetenDauer(int stunden, int minuten);

  /// No description provided for @aktivitaetenDauerKurz.
  ///
  /// In de, this message translates to:
  /// **'{minuten} min'**
  String aktivitaetenDauerKurz(int minuten);

  /// No description provided for @aktivitaetenAufnahmen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{Ein Foto} other{{anzahl} Fotos}}'**
  String aktivitaetenAufnahmen(int anzahl);

  /// No description provided for @aktivitaetenOhneOrt.
  ///
  /// In de, this message translates to:
  /// **'Unterwegs'**
  String get aktivitaetenOhneOrt;

  /// No description provided for @aktivitaetenZuReise.
  ///
  /// In de, this message translates to:
  /// **'Gehört zu: {reise}'**
  String aktivitaetenZuReise(String reise);

  /// No description provided for @aktivitaetenKeineRoute.
  ///
  /// In de, this message translates to:
  /// **'Zu wenige verortete Aufnahmen für eine Strecke.'**
  String get aktivitaetenKeineRoute;

  /// No description provided for @aktivitaetenInDieserReise.
  ///
  /// In de, this message translates to:
  /// **'Unternehmungen'**
  String get aktivitaetenInDieserReise;

  /// No description provided for @reiseartReise.
  ///
  /// In de, this message translates to:
  /// **'Reise'**
  String get reiseartReise;

  /// No description provided for @reisenZusammenfuehren.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get reisenZusammenfuehren;

  /// No description provided for @reisenZusammenfuehrenAllein.
  ///
  /// In de, this message translates to:
  /// **'Es gibt keine zweite Reise, mit der sich diese zusammenführen liesse.'**
  String get reisenZusammenfuehrenAllein;

  /// No description provided for @reisenZusammenfuehrenTitel.
  ///
  /// In de, this message translates to:
  /// **'Zu „{name}\" hinzufügen'**
  String reisenZusammenfuehrenTitel(String name);

  /// No description provided for @reisenZusammenfuehrenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Die gewählten Reisen gehen in „{name}\" auf: Aufnahmen, Unternehmungen, Spuren und Tagesnotizen kommen mit, die Namen der gewählten verschwinden.'**
  String reisenZusammenfuehrenHinweis(String name);

  /// No description provided for @reisenZusammengefuehrt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, one{Eine Reise ging} other{{anzahl} Reisen gingen}} in „{name}\" auf.'**
  String reisenZusammengefuehrt(String name, int anzahl);

  /// No description provided for @reiseartUnternehmung.
  ///
  /// In de, this message translates to:
  /// **'Unternehmung'**
  String get reiseartUnternehmung;

  /// No description provided for @reiseartGeschaeftlich.
  ///
  /// In de, this message translates to:
  /// **'Dienstlich'**
  String get reiseartGeschaeftlich;

  /// No description provided for @reiseartBesuch.
  ///
  /// In de, this message translates to:
  /// **'Besuch'**
  String get reiseartBesuch;

  /// No description provided for @reiseartSonstiges.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get reiseartSonstiges;

  /// No description provided for @reisenArtAendern.
  ///
  /// In de, this message translates to:
  /// **'Art der Reise'**
  String get reisenArtAendern;

  /// No description provided for @reisenAktivitaetAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Unternehmung anlegen'**
  String get reisenAktivitaetAnlegen;

  /// No description provided for @reisenOhneAktivitaeten.
  ///
  /// In de, this message translates to:
  /// **'Noch keine – „Unternehmung anlegen\" macht aus der ganzen Reise oder einem Abschnitt daraus eine.'**
  String get reisenOhneAktivitaeten;

  /// No description provided for @reisenAktivitaetLeer.
  ///
  /// In de, this message translates to:
  /// **'In diesem Zeitraum liegt keine Aufnahme dieser Reise.'**
  String get reisenAktivitaetLeer;

  /// No description provided for @reisenAktivitaetAngelegt.
  ///
  /// In de, this message translates to:
  /// **'Unternehmung „{name}\" angelegt, {anzahl} Aufnahmen.'**
  String reisenAktivitaetAngelegt(String name, int anzahl);

  /// No description provided for @aktivitaetenAngelegt.
  ///
  /// In de, this message translates to:
  /// **'„{name}\" eingetragen.'**
  String aktivitaetenAngelegt(String name);

  /// No description provided for @aktivitaetenEntfernt.
  ///
  /// In de, this message translates to:
  /// **'„{name}\" entfernt.'**
  String aktivitaetenEntfernt(String name);

  /// No description provided for @aufnahmenWahlTitelAktivitaet.
  ///
  /// In de, this message translates to:
  /// **'Fotos der Aktivität'**
  String get aufnahmenWahlTitelAktivitaet;

  /// No description provided for @aufnahmenWahlTitelReise.
  ///
  /// In de, this message translates to:
  /// **'Fotos der Reise'**
  String get aufnahmenWahlTitelReise;

  /// No description provided for @aufnahmenWahlZeitraum.
  ///
  /// In de, this message translates to:
  /// **'Zeitraum ({von} – {bis})'**
  String aufnahmenWahlZeitraum(String von, String bis);

  /// No description provided for @aufnahmenWahlAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos'**
  String get aufnahmenWahlAlle;

  /// No description provided for @aufnahmenWahlGewaehlt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{nichts gewählt} =1{1 Foto gewählt} other{{anzahl} Fotos gewählt}}'**
  String aufnahmenWahlGewaehlt(num anzahl);

  /// No description provided for @aufnahmenWahlAusserhalb.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =1{1 davon ausserhalb der Ansicht} other{{anzahl} davon ausserhalb der Ansicht}}'**
  String aufnahmenWahlAusserhalb(num anzahl);

  /// No description provided for @aufnahmenWahlLeer.
  ///
  /// In de, this message translates to:
  /// **'In diesem Zeitraum liegt kein Foto. Über „Alle Fotos“ lässt sich eines von ausserhalb dazunehmen.'**
  String get aufnahmenWahlLeer;

  /// No description provided for @aufnahmenWahlGeaendert.
  ///
  /// In de, this message translates to:
  /// **'{dazu, plural, =0{} =1{1 Foto dazu} other{{dazu} Fotos dazu}}{weg, plural, =0{} =1{, 1 entfernt} other{, {weg} entfernt}}'**
  String aufnahmenWahlGeaendert(num dazu, num weg);

  /// No description provided for @aufnahmenWahlUnveraendert.
  ///
  /// In de, this message translates to:
  /// **'Nichts geändert.'**
  String get aufnahmenWahlUnveraendert;

  /// No description provided for @aktivitaetenArtNeu.
  ///
  /// In de, this message translates to:
  /// **'Neue Art …'**
  String get aktivitaetenArtNeu;

  /// No description provided for @aktivitaetenArtNeuFrage.
  ///
  /// In de, this message translates to:
  /// **'Wie soll die Art heissen?'**
  String get aktivitaetenArtNeuFrage;

  /// No description provided for @aktArtSpaziergang.
  ///
  /// In de, this message translates to:
  /// **'Spaziergang'**
  String get aktArtSpaziergang;

  /// No description provided for @aktArtWanderung.
  ///
  /// In de, this message translates to:
  /// **'Wanderung'**
  String get aktArtWanderung;

  /// No description provided for @aktArtRadtour.
  ///
  /// In de, this message translates to:
  /// **'Radtour'**
  String get aktArtRadtour;

  /// No description provided for @aktArtAusflug.
  ///
  /// In de, this message translates to:
  /// **'Ausflug'**
  String get aktArtAusflug;

  /// No description provided for @aktArtBesichtigung.
  ///
  /// In de, this message translates to:
  /// **'Besichtigung'**
  String get aktArtBesichtigung;

  /// No description provided for @aktArtBootsfahrt.
  ///
  /// In de, this message translates to:
  /// **'Bootsfahrt'**
  String get aktArtBootsfahrt;

  /// No description provided for @aktArtSonstiges.
  ///
  /// In de, this message translates to:
  /// **'Sonstiges'**
  String get aktArtSonstiges;

  /// No description provided for @aktivitaetenIstEine.
  ///
  /// In de, this message translates to:
  /// **'War eine Unternehmung'**
  String get aktivitaetenIstEine;

  /// No description provided for @aktivitaetenKeine.
  ///
  /// In de, this message translates to:
  /// **'War keine'**
  String get aktivitaetenKeine;

  /// No description provided for @spurHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'GPX-Spur hinzufügen'**
  String get spurHinzufuegen;

  /// No description provided for @spurEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Spur entfernen'**
  String get spurEntfernen;

  /// No description provided for @spurEntferntMeldung.
  ///
  /// In de, this message translates to:
  /// **'Spur entfernt.'**
  String get spurEntferntMeldung;

  /// No description provided for @spurHinzugefuegtMeldung.
  ///
  /// In de, this message translates to:
  /// **'Spur „{name}“ hinzugefügt: {km} km.'**
  String spurHinzugefuegtMeldung(String name, String km);

  /// No description provided for @spurTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufgezeichnete Spur'**
  String get spurTitel;

  /// No description provided for @spurKm.
  ///
  /// In de, this message translates to:
  /// **'{km} km'**
  String spurKm(String km);

  /// No description provided for @spurKennzahlen.
  ///
  /// In de, this message translates to:
  /// **'{km} km · ▲ {auf} m · ▼ {ab} m'**
  String spurKennzahlen(String km, int auf, int ab);

  /// No description provided for @spurKennzahlenOhneHoehe.
  ///
  /// In de, this message translates to:
  /// **'{km} km · keine Höhenangaben'**
  String spurKennzahlenOhneHoehe(String km);

  /// No description provided for @spurPunkte.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Punkte'**
  String spurPunkte(int anzahl);

  /// No description provided for @spurHoehenprofil.
  ///
  /// In de, this message translates to:
  /// **'Höhenprofil'**
  String get spurHoehenprofil;

  /// No description provided for @spurOhneHoehen.
  ///
  /// In de, this message translates to:
  /// **'Diese Datei führt keine Höhen – ohne sie gibt es kein Profil.'**
  String get spurOhneHoehen;

  /// No description provided for @spurProfilBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Höhenprofil über {km} km, von {tief} bis {hoch} Meter, {auf} Meter Aufstieg.'**
  String spurProfilBeschreibung(String km, int tief, int hoch, int auf);

  /// No description provided for @spurStelle.
  ///
  /// In de, this message translates to:
  /// **'{km} km · {hoehe} m'**
  String spurStelle(String km, int hoehe);

  /// No description provided for @spurSchonDa.
  ///
  /// In de, this message translates to:
  /// **'Diese Aktivität hat schon eine Spur.'**
  String get spurSchonDa;

  /// No description provided for @flugStarten.
  ///
  /// In de, this message translates to:
  /// **'Flug starten'**
  String get flugStarten;

  /// No description provided for @flugAnhalten.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get flugAnhalten;

  /// No description provided for @flugWeiter.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get flugWeiter;

  /// No description provided for @flugNochmal.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get flugNochmal;

  /// No description provided for @flugBeenden.
  ///
  /// In de, this message translates to:
  /// **'Zur Übersicht'**
  String get flugBeenden;

  /// No description provided for @flugFortschritt.
  ///
  /// In de, this message translates to:
  /// **'Stelle auf der Spur'**
  String get flugFortschritt;

  /// No description provided for @flugHoehe.
  ///
  /// In de, this message translates to:
  /// **'Höhe'**
  String get flugHoehe;

  /// No description provided for @flugTempo.
  ///
  /// In de, this message translates to:
  /// **'Tempo'**
  String get flugTempo;

  /// No description provided for @flugSteigung.
  ///
  /// In de, this message translates to:
  /// **'Steigung'**
  String get flugSteigung;

  /// No description provided for @flugVideo.
  ///
  /// In de, this message translates to:
  /// **'Als Video ausgeben'**
  String get flugVideo;

  /// No description provided for @flugVideoAbbrechen.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe abbrechen'**
  String get flugVideoAbbrechen;

  /// No description provided for @flugVideoFertig.
  ///
  /// In de, this message translates to:
  /// **'Video gespeichert: {datei}'**
  String flugVideoFertig(String datei);

  /// No description provided for @flugVideoAbgebrochen.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe abgebrochen'**
  String get flugVideoAbgebrochen;

  /// No description provided for @flugVideoKeinWerkzeug.
  ///
  /// In de, this message translates to:
  /// **'Für die Videoausgabe fehlt der Videoschreiber. Unter macOS gehört er zum System, unter Linux und Windows liegt er im Paket – erscheint diese Meldung, ist die Installation unvollständig.'**
  String get flugVideoKeinWerkzeug;

  /// No description provided for @flugVideoLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Video wird geschrieben – {prozent} %'**
  String flugVideoLaeuft(int prozent);

  /// No description provided for @flugVideoLaeuftMitRest.
  ///
  /// In de, this message translates to:
  /// **'Video wird geschrieben – {prozent} %, noch etwa {rest}'**
  String flugVideoLaeuftMitRest(int prozent, String rest);

  /// No description provided for @flugVideoEinstellungen.
  ///
  /// In de, this message translates to:
  /// **'Video ausgeben'**
  String get flugVideoEinstellungen;

  /// No description provided for @flugVideoAufloesung.
  ///
  /// In de, this message translates to:
  /// **'Auflösung'**
  String get flugVideoAufloesung;

  /// No description provided for @flugVideoDauer.
  ///
  /// In de, this message translates to:
  /// **'Dauer'**
  String get flugVideoDauer;

  /// No description provided for @flugVideoDauerWert.
  ///
  /// In de, this message translates to:
  /// **'{sekunden} Sekunden'**
  String flugVideoDauerWert(int sekunden);

  /// No description provided for @flugVideoBilder.
  ///
  /// In de, this message translates to:
  /// **'{bilder} Bilder'**
  String flugVideoBilder(int bilder);

  /// No description provided for @flugVideoWeiter.
  ///
  /// In de, this message translates to:
  /// **'Speichern unter …'**
  String get flugVideoWeiter;

  /// No description provided for @flugVideoWaehrenddessen.
  ///
  /// In de, this message translates to:
  /// **'Die Bilder entstehen abseits des Bildschirms – der Flug wird dafür nicht abgespielt. Diese Ansicht muss so lange offen bleiben.'**
  String get flugVideoWaehrenddessen;

  /// No description provided for @flugVideoFehler.
  ///
  /// In de, this message translates to:
  /// **'Die Videoausgabe ist fehlgeschlagen: {grund}'**
  String flugVideoFehler(String grund);

  /// No description provided for @flugAufstieg.
  ///
  /// In de, this message translates to:
  /// **'Aufstieg'**
  String get flugAufstieg;

  /// No description provided for @flugUnterwegs.
  ///
  /// In de, this message translates to:
  /// **'unterwegs'**
  String get flugUnterwegs;

  /// No description provided for @flugOhneZeit.
  ///
  /// In de, this message translates to:
  /// **'Die Spur trägt keine Zeitstempel – ohne sie gibt es kein Tempo.'**
  String get flugOhneZeit;

  /// No description provided for @flugProfilBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Höhenprofil der Spur mit der Stelle, an der der Flug gerade steht.'**
  String get flugProfilBeschreibung;

  /// No description provided for @flugMeterProfil.
  ///
  /// In de, this message translates to:
  /// **'{meter} m'**
  String flugMeterProfil(int meter);

  /// No description provided for @flugKmH.
  ///
  /// In de, this message translates to:
  /// **'{wert} km/h'**
  String flugKmH(String wert);

  /// No description provided for @flugProzent.
  ///
  /// In de, this message translates to:
  /// **'{wert} %'**
  String flugProzent(String wert);

  /// No description provided for @flugKm.
  ///
  /// In de, this message translates to:
  /// **'{wert} km'**
  String flugKm(String wert);

  /// No description provided for @gelaendeTitel.
  ///
  /// In de, this message translates to:
  /// **'Gelände'**
  String get gelaendeTitel;

  /// No description provided for @gelaendeOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Gelände ansehen'**
  String get gelaendeOeffnen;

  /// No description provided for @gelaendeLaedt.
  ///
  /// In de, this message translates to:
  /// **'Holt Geländehöhen …'**
  String get gelaendeLaedt;

  /// No description provided for @gelaendeNichts.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Ausschnitt kamen keine Geländehöhen an. Die Kacheln liegen im Netz; ohne Verbindung gibt es keine Landschaft.'**
  String get gelaendeNichts;

  /// No description provided for @gelaendeBedienung.
  ///
  /// In de, this message translates to:
  /// **'Ziehen dreht und kippt · Rollen zoomt'**
  String get gelaendeBedienung;

  /// No description provided for @gelaendeUeberhoeht.
  ///
  /// In de, this message translates to:
  /// **'Höhe {faktor}-fach überhöht'**
  String gelaendeUeberhoeht(String faktor);

  /// No description provided for @gelaendeNamensnennung.
  ///
  /// In de, this message translates to:
  /// **'Höhen: Tilezen / AWS Open Data'**
  String get gelaendeNamensnennung;

  /// No description provided for @karteLuftbild.
  ///
  /// In de, this message translates to:
  /// **'Luftbild'**
  String get karteLuftbild;

  /// No description provided for @gelaendeEbeneWege.
  ///
  /// In de, this message translates to:
  /// **'Wanderwege'**
  String get gelaendeEbeneWege;

  /// No description provided for @gelaendeEbeneBeschriftung.
  ///
  /// In de, this message translates to:
  /// **'Strassen und Ortsnamen'**
  String get gelaendeEbeneBeschriftung;

  /// No description provided for @gelaendeEbeneHoehenlinien.
  ///
  /// In de, this message translates to:
  /// **'Höhenlinien'**
  String get gelaendeEbeneHoehenlinien;

  /// No description provided for @gelaendeEbeneWanderobjekte.
  ///
  /// In de, this message translates to:
  /// **'Gipfel, Hütten, Quellen'**
  String get gelaendeEbeneWanderobjekte;

  /// No description provided for @gelaendeErneut.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal versuchen'**
  String get gelaendeErneut;

  /// No description provided for @einstKiTagsZurueck.
  ///
  /// In de, this message translates to:
  /// **'KI-Schlagwörter zurücknehmen'**
  String get einstKiTagsZurueck;

  /// No description provided for @einstKiTagsZurueckText.
  ///
  /// In de, this message translates to:
  /// **'Wird gezählt …'**
  String get einstKiTagsZurueckText;

  /// No description provided for @einstKiTagsZurueckAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} von der Bilderkennung vergeben – von Hand vergebene bleiben'**
  String einstKiTagsZurueckAnzahl(int anzahl);

  /// No description provided for @einstKiTagsZurueckFrage.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Schlagwörter der Bilderkennung werden entfernt. Von Hand vergebene bleiben unangetastet. Danach vergibt die Bilderkennung sie nach der neuen Regel neu.'**
  String einstKiTagsZurueckFrage(int anzahl);

  /// No description provided for @einstKiTagsZurueckJetzt.
  ///
  /// In de, this message translates to:
  /// **'Zurücknehmen'**
  String get einstKiTagsZurueckJetzt;

  /// No description provided for @einstKiTagsZurueckFertig.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Schlagwörter zurückgenommen.'**
  String einstKiTagsZurueckFertig(int anzahl);

  /// No description provided for @papierkorbAusgewaehlt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} ausgewählt'**
  String papierkorbAusgewaehlt(int anzahl);

  /// No description provided for @papierkorbHinweis.
  ///
  /// In de, this message translates to:
  /// **'Zum Wiederherstellen den Pfeil auf dem Bild antippen. Lange drücken wählt mehrere aus.'**
  String get papierkorbHinweis;

  /// No description provided for @aktivitaetenWeitere.
  ///
  /// In de, this message translates to:
  /// **'+{anzahl} weitere'**
  String aktivitaetenWeitere(int anzahl);

  /// No description provided for @einstVorladenTitel.
  ///
  /// In de, this message translates to:
  /// **'Kartengebiete vorladen'**
  String get einstVorladenTitel;

  /// No description provided for @einstVorladenText.
  ///
  /// In de, this message translates to:
  /// **'Holt die Kacheln der eigenen Fotogebiete auf die Platte – danach braucht die Karte dort kein Netz mehr'**
  String get einstVorladenText;

  /// No description provided for @einstVorladenKeineOrte.
  ///
  /// In de, this message translates to:
  /// **'Es gibt noch keine verorteten Aufnahmen.'**
  String get einstVorladenKeineOrte;

  /// No description provided for @einstVorladenFrage.
  ///
  /// In de, this message translates to:
  /// **'{gebiete} Gebiete, {kacheln} Kacheln, rund {mb} MB. Das dauert eine Weile und läuft im Hintergrund weiter, solange die Einstellungen offen sind.'**
  String einstVorladenFrage(int gebiete, int kacheln, int mb);

  /// No description provided for @einstVorladenStarten.
  ///
  /// In de, this message translates to:
  /// **'Vorladen'**
  String get einstVorladenStarten;

  /// No description provided for @einstVorladenStand.
  ///
  /// In de, this message translates to:
  /// **'{fertig} von {gesamt}'**
  String einstVorladenStand(int fertig, int gesamt);

  /// No description provided for @einstVorladenFertig.
  ///
  /// In de, this message translates to:
  /// **'{geladen} Kacheln geladen, {fehler} nicht erreichbar.'**
  String einstVorladenFertig(int geladen, int fehler);

  /// No description provided for @mitschnittTitel.
  ///
  /// In de, this message translates to:
  /// **'Kachel-Mitschnitt'**
  String get mitschnittTitel;

  /// No description provided for @mitschnittErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Schreibt für jede Kartenkachel mit, was das Netz wirklich zurückgibt: Statuscode, Ausnahme, Dauer und ob der Server die Verbindung offen lässt. Kacheln aus dem Kartenspeicher tauchen nicht auf – sie kommen nie am Netz an.'**
  String get mitschnittErklaerung;

  /// No description provided for @mitschnittStarten.
  ///
  /// In de, this message translates to:
  /// **'Mitschnitt starten'**
  String get mitschnittStarten;

  /// No description provided for @mitschnittAnhalten.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get mitschnittAnhalten;

  /// No description provided for @mitschnittLeeren.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get mitschnittLeeren;

  /// No description provided for @mitschnittLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Läuft. Jetzt die Karte öffnen und so lange zoomen, bis die grauen Kacheln auftreten.'**
  String get mitschnittLaeuft;

  /// No description provided for @mitschnittAus.
  ///
  /// In de, this message translates to:
  /// **'Angehalten.'**
  String get mitschnittAus;

  /// No description provided for @mitschnittNochNichts.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts mitgeschrieben.'**
  String get mitschnittNochNichts;

  /// No description provided for @mitschnittVerbJeAbruf.
  ///
  /// In de, this message translates to:
  /// **'Verbindungen je Abruf'**
  String get mitschnittVerbJeAbruf;

  /// No description provided for @mitschnittAbrufeJeKachel.
  ///
  /// In de, this message translates to:
  /// **'Abrufe je Kachel'**
  String get mitschnittAbrufeJeKachel;

  /// No description provided for @mitschnittAbrufe.
  ///
  /// In de, this message translates to:
  /// **'Abrufe'**
  String get mitschnittAbrufe;

  /// No description provided for @mitschnittVerbindungen.
  ///
  /// In de, this message translates to:
  /// **'Verbindungen'**
  String get mitschnittVerbindungen;

  /// No description provided for @mitschnittKacheln.
  ///
  /// In de, this message translates to:
  /// **'verschiedene Kacheln'**
  String get mitschnittKacheln;

  /// No description provided for @mitschnittGeglueckt.
  ///
  /// In de, this message translates to:
  /// **'geglückt'**
  String get mitschnittGeglueckt;

  /// No description provided for @mitschnittFehlgeschlagen.
  ///
  /// In de, this message translates to:
  /// **'fehlgeschlagen'**
  String get mitschnittFehlgeschlagen;

  /// No description provided for @mitschnittAbgebrochen.
  ///
  /// In de, this message translates to:
  /// **'abgebrochen'**
  String get mitschnittAbgebrochen;

  /// No description provided for @mitschnittWiederholte.
  ///
  /// In de, this message translates to:
  /// **'mehrfach geholt'**
  String get mitschnittWiederholte;

  /// No description provided for @mitschnittOhneDauer.
  ///
  /// In de, this message translates to:
  /// **'Server schloss die Verbindung'**
  String get mitschnittOhneDauer;

  /// No description provided for @mitschnittStatusTitel.
  ///
  /// In de, this message translates to:
  /// **'Statuscodes'**
  String get mitschnittStatusTitel;

  /// No description provided for @mitschnittFehlerTitel.
  ///
  /// In de, this message translates to:
  /// **'Fehler'**
  String get mitschnittFehlerTitel;

  /// No description provided for @mitschnittLetzteTitel.
  ///
  /// In de, this message translates to:
  /// **'Die letzten Abrufe'**
  String get mitschnittLetzteTitel;

  /// No description provided for @mitschnittKopieren.
  ///
  /// In de, this message translates to:
  /// **'Bericht kopieren'**
  String get mitschnittKopieren;

  /// No description provided for @mitschnittKopiert.
  ///
  /// In de, this message translates to:
  /// **'Der Bericht liegt in der Zwischenablage.'**
  String get mitschnittKopiert;

  /// No description provided for @einstMitschnittTitel.
  ///
  /// In de, this message translates to:
  /// **'Kachel-Mitschnitt'**
  String get einstMitschnittTitel;

  /// No description provided for @einstMitschnittText.
  ///
  /// In de, this message translates to:
  /// **'Aufzeichnen, was beim Laden der Karte wirklich passiert.'**
  String get einstMitschnittText;

  /// No description provided for @mitschnittDauer.
  ///
  /// In de, this message translates to:
  /// **'Im Mittel {ms} ms, längste {max} ms'**
  String mitschnittDauer(int ms, int max);

  /// No description provided for @mitschnittDaten.
  ///
  /// In de, this message translates to:
  /// **'{mb} MB geladen'**
  String mitschnittDaten(String mb);

  /// No description provided for @mitschnittVerworfen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} ältere Einträge sind der Grenze zum Opfer gefallen.'**
  String mitschnittVerworfen(int anzahl);

  /// No description provided for @mitschnittMalGeholt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl}x'**
  String mitschnittMalGeholt(int anzahl);

  /// No description provided for @aufgTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufgaben'**
  String get aufgTitel;

  /// No description provided for @aufgModusAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get aufgModusAlle;

  /// No description provided for @aufgErstellen.
  ///
  /// In de, this message translates to:
  /// **'Aufgabe erstellen'**
  String get aufgErstellen;

  /// No description provided for @aufgErstellenText.
  ///
  /// In de, this message translates to:
  /// **'Mehrere Aufgaben auf einmal einreihen. Sie laufen der Reihe nach ab – wie viele nebeneinander, steht unter „Gleichzeitige Ausführungen verwalten\".'**
  String get aufgErstellenText;

  /// No description provided for @aufgEinreihen.
  ///
  /// In de, this message translates to:
  /// **'Einreihen'**
  String get aufgEinreihen;

  /// No description provided for @aufgGleichzeitigTitel.
  ///
  /// In de, this message translates to:
  /// **'Gleichzeitige Ausführungen verwalten'**
  String get aufgGleichzeitigTitel;

  /// No description provided for @aufgGleichzeitigText.
  ///
  /// In de, this message translates to:
  /// **'Wie viele rechenintensive Aufgaben nebeneinander laufen dürfen. Jede hält ein KI-Modell im Speicher und liest dieselben Fotos noch einmal von der Platte – mehr ist nicht immer schneller. Aufgaben ohne Modell laufen ohnehin sofort.'**
  String get aufgGleichzeitigText;

  /// No description provided for @aufgDatumText.
  ///
  /// In de, this message translates to:
  /// **'Liest bei RAW-Aufnahmen und Videos das Aufnahmedatum aus der Datei nach und rückt sie im Zeitstrahl an die richtige Stelle. Schreibt Daten um und verschiebt Dateien – deshalb mit Rückfrage.'**
  String get aufgDatumText;

  /// No description provided for @aufgAblageTitel.
  ///
  /// In de, this message translates to:
  /// **'Ablage nach Datum ordnen'**
  String get aufgAblageTitel;

  /// No description provided for @aufgAblageText.
  ///
  /// In de, this message translates to:
  /// **'Legt Aufnahmen in den Ordner ihres Aufnahmemonats, wenn sie dort nicht liegen, und legt liegengebliebene .xmp-Beipackzettel wieder neben ihr Foto. Ändert kein Datum – nur den Ort auf der Platte. Verschiebt Dateien, deshalb mit Rückfrage.'**
  String get aufgAblageText;

  /// No description provided for @werkzOrdneAblage.
  ///
  /// In de, this message translates to:
  /// **'Ordne die Ablage …'**
  String get werkzOrdneAblage;

  /// No description provided for @werkzAblageStimmt.
  ///
  /// In de, this message translates to:
  /// **'Jede Aufnahme liegt im Ordner ihres Datums.'**
  String get werkzAblageStimmt;

  /// No description provided for @werkzAblageBilanz.
  ///
  /// In de, this message translates to:
  /// **'{verschoben} von {gesamt} umgelegt'**
  String werkzAblageBilanz(int verschoben, int gesamt);

  /// No description provided for @werkzAblageFrageTitel.
  ///
  /// In de, this message translates to:
  /// **'Ablage neu ordnen?'**
  String get werkzAblageFrageTitel;

  /// No description provided for @werkzAblageFrage.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen, deren Ordner nicht zu ihrem Aufnahmedatum passt, werden in den richtigen Monatsordner verschoben. Die Aufnahmedaten selbst bleiben unverändert. In der App ändert sich dadurch nichts Sichtbares – wohl aber die Ordnerstruktur der Bibliothek auf der Platte.'**
  String get werkzAblageFrage;

  /// No description provided for @werkzAblageStarten.
  ///
  /// In de, this message translates to:
  /// **'Ablage ordnen'**
  String get werkzAblageStarten;

  /// No description provided for @aufgOffeneFotos.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Fotos offen'**
  String aufgOffeneFotos(int anzahl);

  /// No description provided for @aufgEingereiht.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Aufgaben eingereiht.'**
  String aufgEingereiht(int anzahl);

  /// No description provided for @werkzZuAufgabenText.
  ///
  /// In de, this message translates to:
  /// **'Gesichter, Vorschaubilder, Texterkennung, Orte, Schlagwörter und alles Weitere, was einen Durchgang über die Bibliothek startet. Sie stehen dort und nur dort.'**
  String get werkzZuAufgabenText;

  /// No description provided for @aufgVorschauTitel.
  ///
  /// In de, this message translates to:
  /// **'Vorschaubilder erzeugen'**
  String get aufgVorschauTitel;

  /// No description provided for @sperreTitel.
  ///
  /// In de, this message translates to:
  /// **'Diese Bibliothek ist bereits geöffnet'**
  String get sperreTitel;

  /// No description provided for @sperreText.
  ///
  /// In de, this message translates to:
  /// **'Ein anderes Fenster von Photo Vault arbeitet gerade mit denselben Daten. Zwei Fenster auf einer Bibliothek zeigen verschiedene Stände und lassen Hintergrundaufgaben doppelt laufen.\n\nEs ist nichts kaputtgegangen – diese Bibliothek wird nur nicht ein zweites Mal geöffnet.'**
  String get sperreText;

  /// No description provided for @sperreOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get sperreOrt;

  /// No description provided for @sperreErneut.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get sperreErneut;

  /// No description provided for @sperreNochBelegt.
  ///
  /// In de, this message translates to:
  /// **'Sie ist weiterhin geöffnet.'**
  String get sperreNochBelegt;

  /// No description provided for @sperreAndere.
  ///
  /// In de, this message translates to:
  /// **'Andere Bibliothek öffnen'**
  String get sperreAndere;

  /// No description provided for @sperreBeenden.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault beenden'**
  String get sperreBeenden;

  /// No description provided for @sperreAuswahlTitel.
  ///
  /// In de, this message translates to:
  /// **'Andere Bibliothek öffnen'**
  String get sperreAuswahlTitel;

  /// No description provided for @sperreAuswahlLeer.
  ///
  /// In de, this message translates to:
  /// **'Es ist keine weitere Bibliothek eingetragen.'**
  String get sperreAuswahlLeer;

  /// No description provided for @personVorschlag.
  ///
  /// In de, this message translates to:
  /// **'Vorschlag der Wiedererkennung'**
  String get personVorschlag;

  /// No description provided for @personSuchenOderAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Person suchen oder neu anlegen'**
  String get personSuchenOderAnlegen;

  /// No description provided for @allgLeeren.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get allgLeeren;

  /// No description provided for @personNochKeine.
  ///
  /// In de, this message translates to:
  /// **'Es gibt noch keine Person. Tippe einen Namen ein, um die erste anzulegen.'**
  String get personNochKeine;

  /// No description provided for @personKeinTreffer.
  ///
  /// In de, this message translates to:
  /// **'Keine Person heisst „{suche}“. Der Knopf legt sie neu an.'**
  String personKeinTreffer(String suche);

  /// No description provided for @personAnlegenAktion.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ anlegen'**
  String personAnlegenAktion(String name);

  /// No description provided for @viewerGesichtAufziehen.
  ///
  /// In de, this message translates to:
  /// **'Gesicht nachtragen – Rahmen aufziehen'**
  String get viewerGesichtAufziehen;

  /// No description provided for @viewerGesichtAufziehenEnde.
  ///
  /// In de, this message translates to:
  /// **'Nachtragen beenden'**
  String get viewerGesichtAufziehenEnde;

  /// No description provided for @viewerGesichtNachtragen.
  ///
  /// In de, this message translates to:
  /// **'Nachgetragenes Gesicht benennen'**
  String get viewerGesichtNachtragen;

  /// No description provided for @viewerRahmenZuKlein.
  ///
  /// In de, this message translates to:
  /// **'Der Rahmen ist zu klein. Ziehe einen Kasten um das Gesicht.'**
  String get viewerRahmenZuKlein;

  /// No description provided for @viewerRahmenNichtLesbar.
  ///
  /// In de, this message translates to:
  /// **'Das Foto liess sich nicht lesen – kein Gesicht angelegt.'**
  String get viewerRahmenNichtLesbar;

  /// No description provided for @viewerAufziehenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ziehe einen Rahmen um das fehlende Gesicht.'**
  String get viewerAufziehenHinweis;

  /// No description provided for @karteEigene.
  ///
  /// In de, this message translates to:
  /// **'Eigene Karte'**
  String get karteEigene;

  /// No description provided for @einstEigeneKarteTitel.
  ///
  /// In de, this message translates to:
  /// **'Eigene Kartenquelle'**
  String get einstEigeneKarteTitel;

  /// No description provided for @einstEigeneKarteText.
  ///
  /// In de, this message translates to:
  /// **'Die mitgelieferten Karten hören früh auf: OpenStreetMap liefert echte Kacheln bis Stufe 19, OpenTopoMap bis 17. Wer Hausnummern, Gebäudeumrisse oder ein Luftbild braucht, trägt hier eine eigene Quelle ein. Sie erscheint danach als vierter Eintrag im Kartenmenü.'**
  String get einstEigeneKarteText;

  /// No description provided for @einstEigeneKarteAktiv.
  ///
  /// In de, this message translates to:
  /// **'{name} ist eingerichtet'**
  String einstEigeneKarteAktiv(String name);

  /// No description provided for @einstEigeneKarteOhne.
  ///
  /// In de, this message translates to:
  /// **'Keine eigene Quelle eingerichtet'**
  String get einstEigeneKarteOhne;

  /// No description provided for @einstEigeneKarteVorlage.
  ///
  /// In de, this message translates to:
  /// **'Vorlage übernehmen'**
  String get einstEigeneKarteVorlage;

  /// No description provided for @einstEigeneKarteVorlageGemessen.
  ///
  /// In de, this message translates to:
  /// **'bis Stufe {stufe}, nachgemessen'**
  String einstEigeneKarteVorlageGemessen(String stufe);

  /// No description provided for @einstEigeneKarteVorlageLautAnbieter.
  ///
  /// In de, this message translates to:
  /// **'bis Stufe {stufe}, laut Anbieter'**
  String einstEigeneKarteVorlageLautAnbieter(String stufe);

  /// No description provided for @einstEigeneKarteName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get einstEigeneKarteName;

  /// No description provided for @einstEigeneKarteAdresse.
  ///
  /// In de, this message translates to:
  /// **'Kacheladresse'**
  String get einstEigeneKarteAdresse;

  /// No description provided for @einstEigeneKarteAdresseHinweis.
  ///
  /// In de, this message translates to:
  /// **'https://…/{muster}.png'**
  String einstEigeneKarteAdresseHinweis(String muster);

  /// No description provided for @einstEigeneKarteNennung.
  ///
  /// In de, this message translates to:
  /// **'Namensnennung'**
  String get einstEigeneKarteNennung;

  /// No description provided for @einstEigeneKarteNennungHinweis.
  ///
  /// In de, this message translates to:
  /// **'© Anbieter, © OpenStreetMap contributors'**
  String get einstEigeneKarteNennungHinweis;

  /// No description provided for @einstEigeneKarteStufe.
  ///
  /// In de, this message translates to:
  /// **'Höchste Zoomstufe'**
  String get einstEigeneKarteStufe;

  /// No description provided for @einstEigeneKarteSchluesselHinweis.
  ///
  /// In de, this message translates to:
  /// **'Der Schlüssel gehört mit in die Adresse – ersetze {marke} durch deinen eigenen.'**
  String einstEigeneKarteSchluesselHinweis(String marke);

  /// No description provided for @einstEigeneKarteWoher.
  ///
  /// In de, this message translates to:
  /// **'Schlüssel gibt es bei {quelle}'**
  String einstEigeneKarteWoher(String quelle);

  /// No description provided for @einstEigeneKarteSitzung.
  ///
  /// In de, this message translates to:
  /// **'Google-Sitzung holen'**
  String get einstEigeneKarteSitzung;

  /// No description provided for @einstEigeneKarteSitzungText.
  ///
  /// In de, this message translates to:
  /// **'Google liefert Kacheln erst nach einer Sitzungskennung. Trage deinen Schlüssel in die Adresse ein und hole sie hier; sie hält rund zwei Wochen.'**
  String get einstEigeneKarteSitzungText;

  /// No description provided for @einstEigeneKarteSitzungOk.
  ///
  /// In de, this message translates to:
  /// **'Sitzung geholt und in die Adresse eingesetzt'**
  String get einstEigeneKarteSitzungOk;

  /// No description provided for @einstEigeneKarteSitzungFehler.
  ///
  /// In de, this message translates to:
  /// **'Google gab keine Sitzung: {fehler}'**
  String einstEigeneKarteSitzungFehler(String fehler);

  /// No description provided for @einstEigeneKarteSitzungOhneSchluessel.
  ///
  /// In de, this message translates to:
  /// **'In der Adresse steht noch kein Schlüssel'**
  String get einstEigeneKarteSitzungOhneSchluessel;

  /// No description provided for @einstEigeneKarteEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Quelle entfernen'**
  String get einstEigeneKarteEntfernen;

  /// No description provided for @einstEigeneKarteGespeichert.
  ///
  /// In de, this message translates to:
  /// **'Eigene Kartenquelle gespeichert'**
  String get einstEigeneKarteGespeichert;

  /// No description provided for @einstEigeneKarteEntfernt.
  ///
  /// In de, this message translates to:
  /// **'Eigene Kartenquelle entfernt'**
  String get einstEigeneKarteEntfernt;

  /// No description provided for @einstEigeneKarteFehlerLeer.
  ///
  /// In de, this message translates to:
  /// **'Ohne Adresse geht es nicht'**
  String get einstEigeneKarteFehlerLeer;

  /// No description provided for @einstEigeneKarteFehlerHttp.
  ///
  /// In de, this message translates to:
  /// **'Die Adresse muss mit http:// oder https:// anfangen'**
  String get einstEigeneKarteFehlerHttp;

  /// No description provided for @einstEigeneKarteFehlerPlatzhalter.
  ///
  /// In de, this message translates to:
  /// **'In der Adresse fehlen {teile}'**
  String einstEigeneKarteFehlerPlatzhalter(String teile);

  /// No description provided for @einstEigeneKarteFehlerUnbekannt.
  ///
  /// In de, this message translates to:
  /// **'Die Adresse enthält einen Platzhalter in geschweiften Klammern, den die Karte nicht kennt – erlaubt sind nur {teile}'**
  String einstEigeneKarteFehlerUnbekannt(String teile);

  /// No description provided for @einstEigeneKarteFehlerNennung.
  ///
  /// In de, this message translates to:
  /// **'Die Namensnennung ist eine Lizenzauflage und darf nicht leer bleiben'**
  String get einstEigeneKarteFehlerNennung;

  /// No description provided for @einstEigeneKarteWarnungTitel.
  ///
  /// In de, this message translates to:
  /// **'Bevor du eine fremde Kartenquelle einschaltest'**
  String get einstEigeneKarteWarnungTitel;

  /// No description provided for @einstEigeneKarteWarnungUebermittlung.
  ///
  /// In de, this message translates to:
  /// **'Jede Kachel ist ein Abruf bei diesem Anbieter. Er sieht daran, welchen Ausschnitt der Welt du dir gerade ansiehst, wie tief du hineinzoomst und wie lange du bleibst. Bei den mitgelieferten Karten steht am anderen Ende ein gespendeter Server ohne Konto – hier steht ein Schlüssel, der auf dich ausgestellt ist.'**
  String get einstEigeneKarteWarnungUebermittlung;

  /// No description provided for @einstEigeneKarteWarnungOffline.
  ///
  /// In de, this message translates to:
  /// **'Angesehene Kacheln bleiben auf der Platte und stehen auch ohne Netz wieder zur Verfügung; das Vorladen ganzer Gebiete gilt ebenso für diese Quelle. Ohne Vorladen bleibt ohne Netz grau, was du noch nie angesehen hast.'**
  String get einstEigeneKarteWarnungOffline;

  /// No description provided for @einstEigeneKarteWarnungBedingungen.
  ///
  /// In de, this message translates to:
  /// **'Wie weit ein Anbieter das Zwischenspeichern erlaubt, steht in seinen Nutzungsregeln – manche gestatten es befristet, manche gar nicht, und Google untersagt die Offline-Nutzung ausdrücklich. Genau das tut diese App: Kacheln behalten und ohne Netz wieder zeigen. Ob das für deinen Anbieter zulässig ist, kann dir die App nicht abnehmen.'**
  String get einstEigeneKarteWarnungBedingungen;

  /// No description provided for @einstEigeneKarteWarnungAnnehmen.
  ///
  /// In de, this message translates to:
  /// **'Verstanden, einschalten'**
  String get einstEigeneKarteWarnungAnnehmen;

  /// No description provided for @einstEigeneKarteFehlerSchluessel.
  ///
  /// In de, this message translates to:
  /// **'In der Adresse steht noch die Marke aus der Vorlage – setze dort deinen eigenen Schlüssel ein'**
  String get einstEigeneKarteFehlerSchluessel;

  /// No description provided for @aufnahmenHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get aufnahmenHinzufuegen;

  /// No description provided for @aufnahmenAusAktivitaetEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus der Aktivität entfernen'**
  String get aufnahmenAusAktivitaetEntfernen;

  /// No description provided for @aufnahmenAusReiseEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus der Reise entfernen'**
  String get aufnahmenAusReiseEntfernen;

  /// No description provided for @aufnahmenEntferntAktivitaet.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) aus der Aktivität entfernt'**
  String aufnahmenEntferntAktivitaet(int anzahl);

  /// No description provided for @aufnahmenEntferntReise.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Foto(s) aus der Reise entfernt'**
  String aufnahmenEntferntReise(int anzahl);

  /// No description provided for @auswAuswaehlen.
  ///
  /// In de, this message translates to:
  /// **'Auswählen'**
  String get auswAuswaehlen;

  /// No description provided for @einstKartenquellenTitel.
  ///
  /// In de, this message translates to:
  /// **'Verfügbare Kartenquellen'**
  String get einstKartenquellenTitel;

  /// No description provided for @einstKartenquellenText.
  ///
  /// In de, this message translates to:
  /// **'Wie tief eine Karte trägt, entscheidet der Anbieter – darüber vergrössert die App nur noch. Die Angabe in Metern ist die Breite von hundert Bildpunkten auf mittlerer Breite; bei 300 m erkennt man Strassenzüge, bei 20 m einzelne Häuser.'**
  String get einstKartenquellenText;

  /// No description provided for @einstKartenquellenMitgeliefert.
  ///
  /// In de, this message translates to:
  /// **'mitgeliefert'**
  String get einstKartenquellenMitgeliefert;

  /// No description provided for @einstKartenquellenVorlage.
  ///
  /// In de, this message translates to:
  /// **'Vorlage'**
  String get einstKartenquellenVorlage;

  /// No description provided for @einstKartenquellenTiefe.
  ///
  /// In de, this message translates to:
  /// **'bis Stufe {stufe} · rund {meter}'**
  String einstKartenquellenTiefe(String stufe, String meter);

  /// No description provided for @einstKartenquellenGemessen.
  ///
  /// In de, this message translates to:
  /// **'nachgemessen'**
  String get einstKartenquellenGemessen;

  /// No description provided for @einstKartenquellenLautAnbieter.
  ///
  /// In de, this message translates to:
  /// **'laut Anbieter'**
  String get einstKartenquellenLautAnbieter;

  /// No description provided for @einstKartenquellenSchluessel.
  ///
  /// In de, this message translates to:
  /// **'Schlüssel nötig'**
  String get einstKartenquellenSchluessel;

  /// No description provided for @einstKartenquellenHochaufloesend.
  ///
  /// In de, this message translates to:
  /// **'liefert doppelte Auflösung'**
  String get einstKartenquellenHochaufloesend;

  /// No description provided for @einstKartenquellenSimuliert.
  ///
  /// In de, this message translates to:
  /// **'doppelte Auflösung wird nachgebildet'**
  String get einstKartenquellenSimuliert;

  /// No description provided for @einstKartenquellenKnoepfe.
  ///
  /// In de, this message translates to:
  /// **'Der Knopf rechts macht eine Karte zur Standardansicht – bei einer Vorlage ohne Schlüssel schaltet er sie zugleich ein. Das Vorladen weiter unten füllt den Vorrat danach für genau diese Karte.'**
  String get einstKartenquellenKnoepfe;

  /// No description provided for @einstKartenquellenSeite.
  ///
  /// In de, this message translates to:
  /// **'Seite des Anbieters öffnen'**
  String get einstKartenquellenSeite;

  /// No description provided for @einstKartenquellenSeiteFehler.
  ///
  /// In de, this message translates to:
  /// **'Die Seite liess sich nicht öffnen: {adresse}'**
  String einstKartenquellenSeiteFehler(String adresse);

  /// No description provided for @einstKartenquellenStandard.
  ///
  /// In de, this message translates to:
  /// **'Standard'**
  String get einstKartenquellenStandard;

  /// No description provided for @einstKartenquellenAlsStandard.
  ///
  /// In de, this message translates to:
  /// **'Als Standard'**
  String get einstKartenquellenAlsStandard;

  /// No description provided for @einstKartenquellenAlsStandardHinweis.
  ///
  /// In de, this message translates to:
  /// **'Diese Karte zeigen, sobald die Kartenansicht das nächste Mal geöffnet wird'**
  String get einstKartenquellenAlsStandardHinweis;

  /// No description provided for @einstKartenquellenStandardGesetzt.
  ///
  /// In de, this message translates to:
  /// **'{name} ist ab dem nächsten Öffnen der Karte die Standardansicht.'**
  String einstKartenquellenStandardGesetzt(String name);

  /// No description provided for @einstKartenquellenUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Übernehmen'**
  String get einstKartenquellenUebernehmen;

  /// No description provided for @einstKartenquellenUebernehmenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Diese Quelle als eigene Karte einschalten und als Standard merken'**
  String get einstKartenquellenUebernehmenHinweis;

  /// No description provided for @einstKartenquellenUebernommen.
  ///
  /// In de, this message translates to:
  /// **'{name} ist eingeschaltet und ab dem nächsten Öffnen der Karte die Standardansicht.'**
  String einstKartenquellenUebernommen(String name);

  /// No description provided for @einstKartenquellenEintragen.
  ///
  /// In de, this message translates to:
  /// **'Eintragen'**
  String get einstKartenquellenEintragen;

  /// No description provided for @einstKartenquellenEintragenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Diese Vorlage unten ins Formular schreiben – der Schlüssel fehlt dann noch'**
  String get einstKartenquellenEintragenHinweis;

  /// No description provided for @einstKartenquellenEingetragen.
  ///
  /// In de, this message translates to:
  /// **'{name} steht unten im Formular. Trage deinen Schlüssel ein und speichere.'**
  String einstKartenquellenEingetragen(String name);

  /// No description provided for @aufgDatumsherkunftTitel.
  ///
  /// In de, this message translates to:
  /// **'Herkunft der Aufnahmedaten'**
  String get aufgDatumsherkunftTitel;

  /// No description provided for @aufgDatumsherkunftText.
  ///
  /// In de, this message translates to:
  /// **'Sieht in jeder Datei nach, ob wirklich ein Aufnahmedatum darin steht. Wo keines steht, stammt das Datum aus dem Dateisystem – also vom letzten Kopieren, nicht vom Auslösen. Diese Aufnahmen werden gekennzeichnet und aus Erinnerungen und Serien herausgehalten. Im selben Zug wird der Zeitzonenversatz gelesen, den jede vierte Datei trägt.'**
  String get aufgDatumsherkunftText;

  /// No description provided for @werkzPruefeDatumsherkunft.
  ///
  /// In de, this message translates to:
  /// **'Prüfe, woher die Aufnahmedaten stammen …'**
  String get werkzPruefeDatumsherkunft;

  /// No description provided for @werkzAlleDatumGeprueft.
  ///
  /// In de, this message translates to:
  /// **'Bei allen Aufnahmen wurde schon nachgesehen.'**
  String get werkzAlleDatumGeprueft;

  /// No description provided for @infoDatumGeschaetzt.
  ///
  /// In de, this message translates to:
  /// **'Datum geschätzt – die Datei trägt keines'**
  String get infoDatumGeschaetzt;

  /// No description provided for @infoDatumGeschaetztKurz.
  ///
  /// In de, this message translates to:
  /// **'geschätzt'**
  String get infoDatumGeschaetztKurz;

  /// No description provided for @sucheDatumGeschaetzt.
  ///
  /// In de, this message translates to:
  /// **'Nur mit geschätztem Datum'**
  String get sucheDatumGeschaetzt;

  /// No description provided for @ortVorschlagTitel.
  ///
  /// In de, this message translates to:
  /// **'Orte von Nachbarn'**
  String get ortVorschlagTitel;

  /// No description provided for @ortVorschlagErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Diese Aufnahmen tragen keinen Ort – aber die Aufnahmen kurz davor und danach tun es, und sie sind sich einig. Übernommene Orte werden als geerbt gekennzeichnet: Sie sind eine begründete Vermutung, keine Messung.'**
  String get ortVorschlagErklaerung;

  /// No description provided for @ortVorschlagKeine.
  ///
  /// In de, this message translates to:
  /// **'Keine Aufnahme lässt sich über ihre Nachbarn verorten.'**
  String get ortVorschlagKeine;

  /// No description provided for @ortVorschlagAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String ortVorschlagAnzahl(int n);

  /// No description provided for @ortVorschlagBegruendung.
  ///
  /// In de, this message translates to:
  /// **'{nachbarn, plural, =1{1 verorteter Nachbar} other{{nachbarn} verortete Nachbarn}}, höchstens {minuten} Minuten entfernt'**
  String ortVorschlagBegruendung(int nachbarn, int minuten);

  /// No description provided for @ortVorschlagAlleUebernehmen.
  ///
  /// In de, this message translates to:
  /// **'Alle {n} übernehmen'**
  String ortVorschlagAlleUebernehmen(int n);

  /// No description provided for @ortVorschlagAlleFrageTitel.
  ///
  /// In de, this message translates to:
  /// **'Alle Vorschläge übernehmen?'**
  String get ortVorschlagAlleFrageTitel;

  /// No description provided for @ortVorschlagAlleFrage.
  ///
  /// In de, this message translates to:
  /// **'{gruppen} Gruppen mit zusammen {aufnahmen} Aufnahmen bekommen den Ort ihrer Nachbarn. Der Ort bleibt als geerbt gekennzeichnet und lässt sich einzeln wieder entfernen.'**
  String ortVorschlagAlleFrage(int gruppen, int aufnahmen);

  /// No description provided for @ortVorschlagWerkzTitel.
  ///
  /// In de, this message translates to:
  /// **'Orte von Nachbarn erben'**
  String get ortVorschlagWerkzTitel;

  /// No description provided for @ortVorschlagWerkzText.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmen ohne Ort, deren zeitliche Nachbarn alle am selben Ort waren.'**
  String get ortVorschlagWerkzText;

  /// No description provided for @infoOrtGeerbt.
  ///
  /// In de, this message translates to:
  /// **'Von den Nachbaraufnahmen geerbt'**
  String get infoOrtGeerbt;

  /// No description provided for @aufgVideobilderTitel.
  ///
  /// In de, this message translates to:
  /// **'Videos: mehr als ein Standbild'**
  String get aufgVideobilderTitel;

  /// No description provided for @aufgVideobilderText.
  ///
  /// In de, this message translates to:
  /// **'Ein Video wurde bisher aus einem einzigen Standbild ausgewertet. Ab zehn Sekunden Laufzeit werden bis zu fünf über die Länge verteilte Bilder ausgewertet – für die Suche, die Schlagwörter und die Gesichter. Die Bilder werden nicht aufgehoben.'**
  String get aufgVideobilderText;

  /// No description provided for @werkzVideobilder.
  ///
  /// In de, this message translates to:
  /// **'Werte weitere Standbilder aus …'**
  String get werkzVideobilder;

  /// No description provided for @werkzAlleVideobilder.
  ///
  /// In de, this message translates to:
  /// **'Bei allen Videos wurde schon nachgesehen.'**
  String get werkzAlleVideobilder;

  /// No description provided for @suchoptIso.
  ///
  /// In de, this message translates to:
  /// **'ISO'**
  String get suchoptIso;

  /// No description provided for @startFehlerTitel.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek konnte nicht geöffnet werden'**
  String get startFehlerTitel;

  /// No description provided for @startFehlerText.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault ist beim Start auf einen Fehler gestoßen. Die technischen Einzelheiten helfen bei der Fehlersuche.'**
  String get startFehlerText;

  /// No description provided for @startFehlerErneut.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get startFehlerErneut;

  /// No description provided for @befehlspaletteTitel.
  ///
  /// In de, this message translates to:
  /// **'Befehl suchen'**
  String get befehlspaletteTitel;

  /// No description provided for @befehlspaletteHinweis.
  ///
  /// In de, this message translates to:
  /// **'Bereich oder Werkzeug eingeben'**
  String get befehlspaletteHinweis;

  /// No description provided for @befehlspaletteLeer.
  ///
  /// In de, this message translates to:
  /// **'Kein passender Befehl'**
  String get befehlspaletteLeer;

  /// No description provided for @kuerzelBefehlspalette.
  ///
  /// In de, this message translates to:
  /// **'Befehlspalette öffnen'**
  String get kuerzelBefehlspalette;

  /// No description provided for @gesundheitTitel.
  ///
  /// In de, this message translates to:
  /// **'Bibliothekszustand'**
  String get gesundheitTitel;

  /// No description provided for @gesundheitWerkzeugText.
  ///
  /// In de, this message translates to:
  /// **'Sicherung, Datenbank, Speicher und lokale Modelle gemeinsam prüfen.'**
  String get gesundheitWerkzeugText;

  /// No description provided for @gesundheitEinleitung.
  ///
  /// In de, this message translates to:
  /// **'Hier stehen die Punkte, die darüber entscheiden, ob die Bibliothek vollständig, gesichert und arbeitsbereit ist.'**
  String get gesundheitEinleitung;

  /// No description provided for @gesundheitAktualisieren.
  ///
  /// In de, this message translates to:
  /// **'Zustand aktualisieren'**
  String get gesundheitAktualisieren;

  /// No description provided for @gesundheitDatenbank.
  ///
  /// In de, this message translates to:
  /// **'Datenbank'**
  String get gesundheitDatenbank;

  /// No description provided for @gesundheitDatenbankOk.
  ///
  /// In de, this message translates to:
  /// **'SQLite meldet keine strukturellen Fehler.'**
  String get gesundheitDatenbankOk;

  /// No description provided for @gesundheitDatenbankFehler.
  ///
  /// In de, this message translates to:
  /// **'SQLite hat einen strukturellen Fehler gemeldet.'**
  String get gesundheitDatenbankFehler;

  /// No description provided for @gesundheitIntegritaetOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Dateien vollständig prüfen'**
  String get gesundheitIntegritaetOeffnen;

  /// No description provided for @gesundheitSicherung.
  ///
  /// In de, this message translates to:
  /// **'Automatische Sicherung'**
  String get gesundheitSicherung;

  /// No description provided for @gesundheitSicherungAus.
  ///
  /// In de, this message translates to:
  /// **'Die automatische Sicherung ist ausgeschaltet.'**
  String get gesundheitSicherungAus;

  /// No description provided for @gesundheitSicherungNie.
  ///
  /// In de, this message translates to:
  /// **'Die automatische Sicherung ist eingerichtet, aber noch nie erfolgreich gelaufen.'**
  String get gesundheitSicherungNie;

  /// No description provided for @gesundheitLetzteSicherung.
  ///
  /// In de, this message translates to:
  /// **'Letzter erfolgreicher Lauf: {datum}'**
  String gesundheitLetzteSicherung(String datum);

  /// No description provided for @gesundheitSicherungOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Alle aktuellen Aufnahmen sind gesichert.} =1{1 Aufnahme wartet auf die Sicherung.} other{{anzahl} Aufnahmen warten auf die Sicherung.}}'**
  String gesundheitSicherungOffen(int anzahl);

  /// No description provided for @gesundheitSpeicher.
  ///
  /// In de, this message translates to:
  /// **'Speicherbelegung'**
  String get gesundheitSpeicher;

  /// No description provided for @gesundheitSpeicherWirdGezaehlt.
  ///
  /// In de, this message translates to:
  /// **'wird gezählt …'**
  String get gesundheitSpeicherWirdGezaehlt;

  /// No description provided for @gesundheitMedien.
  ///
  /// In de, this message translates to:
  /// **'{fotos} Fotos, {videos} Videos'**
  String gesundheitMedien(int fotos, int videos);

  /// No description provided for @gesundheitModelle.
  ///
  /// In de, this message translates to:
  /// **'Lokale Funktionen'**
  String get gesundheitModelle;

  /// No description provided for @gesundheitModelleStand.
  ///
  /// In de, this message translates to:
  /// **'{bereit} von {gesamt} lokalen Daten- und KI-Funktionen sind bereit.'**
  String gesundheitModelleStand(int bereit, int gesamt);

  /// No description provided for @gesundheitOrteTitel.
  ///
  /// In de, this message translates to:
  /// **'Orte zum Erben'**
  String get gesundheitOrteTitel;

  /// No description provided for @gesundheitOrteOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Aufnahme(n) ohne Ort haben einen verorteten Nachbarn in zeitlicher Nähe.'**
  String gesundheitOrteOffen(int anzahl);

  /// No description provided for @gesundheitOrteAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge ansehen'**
  String get gesundheitOrteAnsehen;

  /// No description provided for @gesundheitGesichterTitel.
  ///
  /// In de, this message translates to:
  /// **'Gesichter ohne Person'**
  String get gesundheitGesichterTitel;

  /// No description provided for @gesundheitGesichterOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} erkannte(s) Gesicht(er) gehören noch zu niemandem. Unter Personen lassen sie sich in Gruppen zuordnen.'**
  String gesundheitGesichterOffen(int anzahl);

  /// No description provided for @gesundheitGesichterZuordnen.
  ///
  /// In de, this message translates to:
  /// **'Zu den Personen'**
  String get gesundheitGesichterZuordnen;

  /// No description provided for @gesundheitDatumTitel.
  ///
  /// In de, this message translates to:
  /// **'Fragwürdige Aufnahmedaten'**
  String get gesundheitDatumTitel;

  /// No description provided for @gesundheitDatumOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Aufnahme(n) tragen einen Zeitstempel auf voller Stunde – bei einem echten Auslösezeitpunkt wären das rund zwei. Der Lauf sieht in der Datei nach, was wirklich dort steht.'**
  String gesundheitDatumOffen(int anzahl);

  /// No description provided for @gesundheitDatumPruefen.
  ///
  /// In de, this message translates to:
  /// **'Datumsherkunft prüfen'**
  String get gesundheitDatumPruefen;

  /// No description provided for @gesundheitVideobilderTitel.
  ///
  /// In de, this message translates to:
  /// **'Videos aus einem Standbild'**
  String get gesundheitVideobilderTitel;

  /// No description provided for @gesundheitVideobilderOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Video(s) sind länger als zehn Sekunden und werden trotzdem nur nach ihrem ersten Standbild durchsucht.'**
  String gesundheitVideobilderOffen(int anzahl);

  /// No description provided for @gesundheitVideobilderHolen.
  ///
  /// In de, this message translates to:
  /// **'Weitere Standbilder holen'**
  String get gesundheitVideobilderHolen;

  /// No description provided for @stufeWiedererkennung.
  ///
  /// In de, this message translates to:
  /// **'Wiedererkennung'**
  String get stufeWiedererkennung;

  /// No description provided for @aufgWiedererkennungTitel.
  ///
  /// In de, this message translates to:
  /// **'Wer könnte das sein?'**
  String get aufgWiedererkennungTitel;

  /// No description provided for @aufgWiedererkennungText.
  ///
  /// In de, this message translates to:
  /// **'Vergleicht namenlose Gesichter mit den benannten Personen und schlägt vor, wer zu sehen sein könnte. Zugeordnet wird nichts – das bleibt Ihre Entscheidung.'**
  String get aufgWiedererkennungText;

  /// No description provided for @werkzWiedererkennung.
  ///
  /// In de, this message translates to:
  /// **'Gesichter vergleichen'**
  String get werkzWiedererkennung;

  /// No description provided for @werkzAlleVerglichen.
  ///
  /// In de, this message translates to:
  /// **'Alle Gesichter sind bereits verglichen.'**
  String get werkzAlleVerglichen;

  /// No description provided for @gesundheitVorschlaegeTitel.
  ///
  /// In de, this message translates to:
  /// **'Erkannte Gesichter warten'**
  String get gesundheitVorschlaegeTitel;

  /// No description provided for @gesundheitVorschlaegeOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} namenlose(s) Gesicht(er) ähneln einer benannten Person genug für einen Vorschlag.'**
  String gesundheitVorschlaegeOffen(int anzahl);

  /// No description provided for @gesundheitVorschlaegeAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge ansehen'**
  String get gesundheitVorschlaegeAnsehen;

  /// No description provided for @vorschlaegeTitel.
  ///
  /// In de, this message translates to:
  /// **'Wer könnte das sein?'**
  String get vorschlaegeTitel;

  /// No description provided for @vorschlaegeEinleitung.
  ///
  /// In de, this message translates to:
  /// **'Vorgeschlagen, nicht zugeordnet. Sie sehen je Person, was die Erkennung gefunden hat, und entscheiden.'**
  String get vorschlaegeEinleitung;

  /// No description provided for @vorschlaegeAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Vorschlag/Vorschläge'**
  String vorschlaegeAnzahl(int anzahl);

  /// No description provided for @vorschlaegeKeine.
  ///
  /// In de, this message translates to:
  /// **'Zurzeit gibt es keine Vorschläge.'**
  String get vorschlaegeKeine;

  /// No description provided for @vorschlaegeBeiseite.
  ///
  /// In de, this message translates to:
  /// **'Beiseitegelegte einbeziehen'**
  String get vorschlaegeBeiseite;

  /// No description provided for @vorschlaegeBeiseiteHinweis.
  ///
  /// In de, this message translates to:
  /// **'Sie haben diese Gesichter einmal weggelegt – damals gab es die heutigen Personen zum Teil noch nicht. Hier steht, was die Erkennung darin jetzt findet.'**
  String get vorschlaegeBeiseiteHinweis;

  /// No description provided for @vorschlaegeBeiseiteLeer.
  ///
  /// In de, this message translates to:
  /// **'Unter den beiseitegelegten Gesichtern findet die Erkennung nichts.'**
  String get vorschlaegeBeiseiteLeer;

  /// No description provided for @vorschlaegeLaufHinweis.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts verglichen. Der Lauf „Wer könnte das sein?“ füllt diese Liste.'**
  String get vorschlaegeLaufHinweis;

  /// No description provided for @gesundheitBeiseiteTitel.
  ///
  /// In de, this message translates to:
  /// **'Beiseitegelegte Gesichter, nie verglichen'**
  String get gesundheitBeiseiteTitel;

  /// No description provided for @gesundheitBeiseiteOffen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} beiseitegelegte(s) Gesicht(er) wurden nie mit Ihren benannten Personen verglichen – weggelegt wurde, bevor es diese Personen gab.'**
  String gesundheitBeiseiteOffen(int anzahl);

  /// No description provided for @gesundheitBeiseiteAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Nachsehen'**
  String get gesundheitBeiseiteAnsehen;

  /// No description provided for @vorschlaegeJetztVergleichen.
  ///
  /// In de, this message translates to:
  /// **'Jetzt vergleichen'**
  String get vorschlaegeJetztVergleichen;

  /// No description provided for @vorschlaegeBeiseiteNieVerglichen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} beiseitegelegte(s) Gesicht(er) wurden noch nie verglichen. Der Durchgang ändert nichts – er sagt nur, wer darunter zu einer benannten Person passen könnte.'**
  String vorschlaegeBeiseiteNieVerglichen(int anzahl);

  /// No description provided for @vorschlaegeLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Der Durchgang läuft …'**
  String get vorschlaegeLaeuft;

  /// No description provided for @datenschutzExportTitel.
  ///
  /// In de, this message translates to:
  /// **'Datenschutzexport'**
  String get datenschutzExportTitel;

  /// No description provided for @datenschutzExportText.
  ///
  /// In de, this message translates to:
  /// **'JPEG bis 2048 Pixel, ohne EXIF, GPS oder XMP; bekannte Gesichter und erkannte Kennzeichen werden lokal unkenntlich gemacht.'**
  String get datenschutzExportText;

  /// No description provided for @datenschutzAusgelassen.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} Aufnahme(n) ausgelassen: Videos und nicht renderbare Bilder lassen sich nicht von ihren Metadaten befreien.'**
  String datenschutzAusgelassen(int anzahl);

  /// No description provided for @sicherTeilenTitel.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsseltes Austauschpaket'**
  String get sicherTeilenTitel;

  /// No description provided for @sicherTeilenText.
  ///
  /// In de, this message translates to:
  /// **'Originale und Dateinamen in einer passwortgeschützten .pvshare-Datei weitergeben.'**
  String get sicherTeilenText;

  /// No description provided for @sicherTeilenZiel.
  ///
  /// In de, this message translates to:
  /// **'Austauschpaket speichern'**
  String get sicherTeilenZiel;

  /// No description provided for @sicherTeilenDateiname.
  ///
  /// In de, this message translates to:
  /// **'PhotoVault-Austausch.pvshare'**
  String get sicherTeilenDateiname;

  /// No description provided for @sicherTeilenFertig.
  ///
  /// In de, this message translates to:
  /// **'Verschlüsseltes Austauschpaket gespeichert: {pfad}'**
  String sicherTeilenFertig(String pfad);

  /// No description provided for @sicherTeilenFehler.
  ///
  /// In de, this message translates to:
  /// **'Austauschpaket konnte nicht erstellt werden: {fehler}'**
  String sicherTeilenFehler(String fehler);

  /// No description provided for @einstPrivateMetadatenTitel.
  ///
  /// In de, this message translates to:
  /// **'Private Metadaten schützen'**
  String get einstPrivateMetadatenTitel;

  /// No description provided for @einstPrivateMetadatenText.
  ///
  /// In de, this message translates to:
  /// **'Entfernt bei neu gesperrten Aufnahmen Dateiname, Datum, Standort, Beschreibung, Schlagwörter und Albumzuordnungen aus der lesbaren Datenbank. Die Angaben werden mit dem Tresorschlüssel verschlüsselt und beim dauerhaften Entsperren wiederhergestellt.'**
  String get einstPrivateMetadatenText;

  /// No description provided for @gesundheitBereinigen.
  ///
  /// In de, this message translates to:
  /// **'Temporäre Dateien bereinigen'**
  String get gesundheitBereinigen;

  /// No description provided for @gesundheitBereinigt.
  ///
  /// In de, this message translates to:
  /// **'{anzahl, plural, =0{Keine temporären Reste gefunden.} =1{1 temporäre Datei entfernt ({groesse}).} other{{anzahl} temporäre Dateien entfernt ({groesse}).}}'**
  String gesundheitBereinigt(int anzahl, String groesse);

  /// No description provided for @sicherTeilenImportTitel.
  ///
  /// In de, this message translates to:
  /// **'Austauschpaket öffnen'**
  String get sicherTeilenImportTitel;

  /// No description provided for @sicherTeilenImportText.
  ///
  /// In de, this message translates to:
  /// **'Eine passwortgeschützte .pvshare-Datei prüfen, entschlüsseln und in diese Bibliothek importieren.'**
  String get sicherTeilenImportText;

  /// No description provided for @sicherTeilenImportPassphrase.
  ///
  /// In de, this message translates to:
  /// **'Passphrase des Austauschpakets'**
  String get sicherTeilenImportPassphrase;

  /// No description provided for @sicherTeilenImportFertig.
  ///
  /// In de, this message translates to:
  /// **'{importiert} Aufnahmen importiert, {duplikate} Duplikate übersprungen.'**
  String sicherTeilenImportFertig(int importiert, int duplikate);

  /// No description provided for @sicherTeilenImportFehler.
  ///
  /// In de, this message translates to:
  /// **'Austauschpaket konnte nicht geöffnet werden: {fehler}'**
  String sicherTeilenImportFehler(String fehler);
}

class _AppTexteDelegate extends LocalizationsDelegate<AppTexte> {
  const _AppTexteDelegate();

  @override
  Future<AppTexte> load(Locale locale) {
    return SynchronousFuture<AppTexte>(lookupAppTexte(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppTexteDelegate old) => false;
}

AppTexte lookupAppTexte(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppTexteDe();
    case 'en':
      return AppTexteEn();
  }

  throw FlutterError(
      'AppTexte.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

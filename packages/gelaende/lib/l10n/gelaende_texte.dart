import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'gelaende_texte_de.dart';
import 'gelaende_texte_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of GelaendeTexte
/// returned by `GelaendeTexte.of(context)`.
///
/// Applications need to include `GelaendeTexte.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/gelaende_texte.dart';
///
/// return MaterialApp(
///   localizationsDelegates: GelaendeTexte.localizationsDelegates,
///   supportedLocales: GelaendeTexte.supportedLocales,
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
/// be consistent with the languages listed in the GelaendeTexte.supportedLocales
/// property.
abstract class GelaendeTexte {
  GelaendeTexte(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static GelaendeTexte of(BuildContext context) {
    return Localizations.of<GelaendeTexte>(context, GelaendeTexte)!;
  }

  static const LocalizationsDelegate<GelaendeTexte> delegate =
      _GelaendeTexteDelegate();

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
    Locale('en'),
  ];

  /// Verwirft einen Dialog, ohne etwas zu ändern.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get allgAbbrechen;

  /// No description provided for @flugAnhalten.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get flugAnhalten;

  /// No description provided for @flugAufstieg.
  ///
  /// In de, this message translates to:
  /// **'Aufstieg'**
  String get flugAufstieg;

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

  /// No description provided for @flugKm.
  ///
  /// In de, this message translates to:
  /// **'{wert} km'**
  String flugKm(String wert);

  /// No description provided for @flugKmH.
  ///
  /// In de, this message translates to:
  /// **'{wert} km/h'**
  String flugKmH(String wert);

  /// No description provided for @flugMeterProfil.
  ///
  /// In de, this message translates to:
  /// **'{meter} m'**
  String flugMeterProfil(int meter);

  /// No description provided for @flugNochmal.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get flugNochmal;

  /// No description provided for @flugOhneZeit.
  ///
  /// In de, this message translates to:
  /// **'Die Spur trägt keine Zeitstempel – ohne sie gibt es kein Tempo.'**
  String get flugOhneZeit;

  /// No description provided for @flugProzent.
  ///
  /// In de, this message translates to:
  /// **'{wert} %'**
  String flugProzent(String wert);

  /// No description provided for @flugStarten.
  ///
  /// In de, this message translates to:
  /// **'Flug starten'**
  String get flugStarten;

  /// No description provided for @flugSteigung.
  ///
  /// In de, this message translates to:
  /// **'Steigung'**
  String get flugSteigung;

  /// No description provided for @flugTempo.
  ///
  /// In de, this message translates to:
  /// **'Tempo'**
  String get flugTempo;

  /// No description provided for @flugUnterwegs.
  ///
  /// In de, this message translates to:
  /// **'unterwegs'**
  String get flugUnterwegs;

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

  /// No description provided for @flugVideoAbgebrochen.
  ///
  /// In de, this message translates to:
  /// **'Ausgabe abgebrochen'**
  String get flugVideoAbgebrochen;

  /// No description provided for @flugVideoAufloesung.
  ///
  /// In de, this message translates to:
  /// **'Auflösung'**
  String get flugVideoAufloesung;

  /// No description provided for @flugVideoBilder.
  ///
  /// In de, this message translates to:
  /// **'{bilder} Bilder'**
  String flugVideoBilder(int bilder);

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

  /// No description provided for @flugVideoEinstellungen.
  ///
  /// In de, this message translates to:
  /// **'Video ausgeben'**
  String get flugVideoEinstellungen;

  /// No description provided for @flugVideoFehler.
  ///
  /// In de, this message translates to:
  /// **'Die Videoausgabe ist fehlgeschlagen: {grund}'**
  String flugVideoFehler(String grund);

  /// No description provided for @flugVideoFertig.
  ///
  /// In de, this message translates to:
  /// **'Video gespeichert: {datei}'**
  String flugVideoFertig(String datei);

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

  /// No description provided for @flugVideoWaehrenddessen.
  ///
  /// In de, this message translates to:
  /// **'Die Bilder entstehen abseits des Bildschirms – der Flug wird dafür nicht abgespielt. Diese Ansicht muss so lange offen bleiben.'**
  String get flugVideoWaehrenddessen;

  /// No description provided for @flugVideoWeiter.
  ///
  /// In de, this message translates to:
  /// **'Speichern unter …'**
  String get flugVideoWeiter;

  /// No description provided for @flugWeiter.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get flugWeiter;

  /// No description provided for @gelaendeBedienung.
  ///
  /// In de, this message translates to:
  /// **'Ziehen dreht und kippt · Rollen zoomt'**
  String get gelaendeBedienung;

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

  /// No description provided for @gelaendeEbeneWege.
  ///
  /// In de, this message translates to:
  /// **'Wanderwege'**
  String get gelaendeEbeneWege;

  /// No description provided for @gelaendeErneut.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal versuchen'**
  String get gelaendeErneut;

  /// No description provided for @gelaendeKarte.
  ///
  /// In de, this message translates to:
  /// **'Karte auf der Landschaft'**
  String get gelaendeKarte;

  /// No description provided for @gelaendeLaedt.
  ///
  /// In de, this message translates to:
  /// **'Holt Geländehöhen …'**
  String get gelaendeLaedt;

  /// No description provided for @gelaendeNamensnennung.
  ///
  /// In de, this message translates to:
  /// **'Höhen: Tilezen / AWS Open Data'**
  String get gelaendeNamensnennung;

  /// No description provided for @gelaendeNichts.
  ///
  /// In de, this message translates to:
  /// **'Für diesen Ausschnitt kamen keine Geländehöhen an. Die Kacheln liegen im Netz; ohne Verbindung gibt es keine Landschaft.'**
  String get gelaendeNichts;

  /// No description provided for @gelaendeStimmung.
  ///
  /// In de, this message translates to:
  /// **'Tageszeit'**
  String get gelaendeStimmung;

  /// No description provided for @gelaendeTitel.
  ///
  /// In de, this message translates to:
  /// **'Gelände'**
  String get gelaendeTitel;

  /// No description provided for @gelaendeUeberhoeht.
  ///
  /// In de, this message translates to:
  /// **'Höhe {faktor}-fach überhöht'**
  String gelaendeUeberhoeht(String faktor);

  /// No description provided for @karteDunkel.
  ///
  /// In de, this message translates to:
  /// **'Dunkel'**
  String get karteDunkel;

  /// No description provided for @karteHell.
  ///
  /// In de, this message translates to:
  /// **'Hell'**
  String get karteHell;

  /// No description provided for @karteLuftbild.
  ///
  /// In de, this message translates to:
  /// **'Luftbild'**
  String get karteLuftbild;

  /// No description provided for @karteTopografie.
  ///
  /// In de, this message translates to:
  /// **'Topografie'**
  String get karteTopografie;

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

  /// No description provided for @spurStelle.
  ///
  /// In de, this message translates to:
  /// **'{km} km · {hoehe} m'**
  String spurStelle(String km, int hoehe);

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

  /// No description provided for @stimmungMittag.
  ///
  /// In de, this message translates to:
  /// **'Mittag'**
  String get stimmungMittag;

  /// No description provided for @stimmungMorgen.
  ///
  /// In de, this message translates to:
  /// **'Morgen'**
  String get stimmungMorgen;

  /// No description provided for @flugProfilBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Höhenprofil der Spur mit der Stelle, an der der Flug gerade steht.'**
  String get flugProfilBeschreibung;
}

class _GelaendeTexteDelegate extends LocalizationsDelegate<GelaendeTexte> {
  const _GelaendeTexteDelegate();

  @override
  Future<GelaendeTexte> load(Locale locale) {
    return SynchronousFuture<GelaendeTexte>(lookupGelaendeTexte(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_GelaendeTexteDelegate old) => false;
}

GelaendeTexte lookupGelaendeTexte(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return GelaendeTexteDe();
    case 'en':
      return GelaendeTexteEn();
  }

  throw FlutterError(
    'GelaendeTexte.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

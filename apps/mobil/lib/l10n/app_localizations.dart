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
    Locale('en'),
  ];

  /// No description provided for @appTitel.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault'**
  String get appTitel;

  /// No description provided for @abbrechen.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get abbrechen;

  /// No description provided for @weiter.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get weiter;

  /// No description provided for @kopieren.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get kopieren;

  /// No description provided for @navZeitleiste.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get navZeitleiste;

  /// No description provided for @navSuche.
  ///
  /// In de, this message translates to:
  /// **'Suche'**
  String get navSuche;

  /// No description provided for @navAlben.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get navAlben;

  /// No description provided for @navPersonen.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get navPersonen;

  /// No description provided for @navKarte.
  ///
  /// In de, this message translates to:
  /// **'Karte'**
  String get navKarte;

  /// No description provided for @zeitleisteLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aufnahmen. Was auf den Server kommt, erscheint hier.'**
  String get zeitleisteLeer;

  /// No description provided for @albenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Alben.'**
  String get albenLeer;

  /// No description provided for @personenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine benannten Personen. Personen benennt man am Rechner.'**
  String get personenLeer;

  /// No description provided for @karteLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aufnahmen mit Ort.'**
  String get karteLeer;

  /// No description provided for @karteFotos.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String karteFotos(int n);

  /// No description provided for @abgemeldetHinweis.
  ///
  /// In de, this message translates to:
  /// **'Dieses Telefon ist beim Server abgemeldet. Unter „Konto“ abmelden und neu verbinden.'**
  String get abgemeldetHinweis;

  /// No description provided for @offline.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Server nicht erreichbar – 1 Änderung wartet} other{Server nicht erreichbar – {n} Änderungen warten}}'**
  String offline(int n);

  /// No description provided for @sucheInhalt.
  ///
  /// In de, this message translates to:
  /// **'Bildinhalt'**
  String get sucheInhalt;

  /// No description provided for @sucheText.
  ///
  /// In de, this message translates to:
  /// **'Text'**
  String get sucheText;

  /// No description provided for @sucheHinweisInhalt.
  ///
  /// In de, this message translates to:
  /// **'z. B. Strand bei Sonnenuntergang'**
  String get sucheHinweisInhalt;

  /// No description provided for @sucheHinweisText.
  ///
  /// In de, this message translates to:
  /// **'Dateiname, Beschreibung, erkannter Text …'**
  String get sucheHinweisText;

  /// No description provided for @sucheKeinModell.
  ///
  /// In de, this message translates to:
  /// **'Der Server kann nicht nach Bildinhalt suchen (kein Modell). Gezeigt wird die Suche im Text.'**
  String get sucheKeinModell;

  /// No description provided for @sucheFehler.
  ///
  /// In de, this message translates to:
  /// **'Die Suche hat nicht geklappt.'**
  String get sucheFehler;

  /// No description provided for @sucheNichts.
  ///
  /// In de, this message translates to:
  /// **'Nichts gefunden.'**
  String get sucheNichts;

  /// No description provided for @betrachterFavorit.
  ///
  /// In de, this message translates to:
  /// **'Favorit'**
  String get betrachterFavorit;

  /// No description provided for @betrachterTeilen.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get betrachterTeilen;

  /// No description provided for @betrachterAngaben.
  ///
  /// In de, this message translates to:
  /// **'Angaben'**
  String get betrachterAngaben;

  /// No description provided for @betrachterPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb'**
  String get betrachterPapierkorb;

  /// No description provided for @betrachterPapierkorbTitel.
  ///
  /// In de, this message translates to:
  /// **'In den Papierkorb legen?'**
  String get betrachterPapierkorbTitel;

  /// No description provided for @betrachterPapierkorbText.
  ///
  /// In de, this message translates to:
  /// **'Die Aufnahme verschwindet überall – auch am Rechner. Aus dem Papierkorb lässt sie sich am Rechner zurückholen.'**
  String get betrachterPapierkorbText;

  /// No description provided for @betrachterLaedtOriginal.
  ///
  /// In de, this message translates to:
  /// **'Das Original wird geladen …'**
  String get betrachterLaedtOriginal;

  /// No description provided for @betrachterNichtGeladen.
  ///
  /// In de, this message translates to:
  /// **'Konnte nicht geladen werden – ist der Server erreichbar?'**
  String get betrachterNichtGeladen;

  /// No description provided for @betrachterBeschreibungKi.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung der Bilderkennung'**
  String get betrachterBeschreibungKi;

  /// No description provided for @kontoTitel.
  ///
  /// In de, this message translates to:
  /// **'Konto'**
  String get kontoTitel;

  /// No description provided for @kontoKontoGeraet.
  ///
  /// In de, this message translates to:
  /// **'Konto {konto} · Gerät {geraet}'**
  String kontoKontoGeraet(String konto, String geraet);

  /// No description provided for @kontoVerbindet.
  ///
  /// In de, this message translates to:
  /// **'Verbindet …'**
  String get kontoVerbindet;

  /// No description provided for @kontoAbgeglichen.
  ///
  /// In de, this message translates to:
  /// **'Abgeglichen'**
  String get kontoAbgeglichen;

  /// No description provided for @kontoSendet.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Änderung geht zum Server} other{{n} Änderungen gehen zum Server}}'**
  String kontoSendet(int n);

  /// No description provided for @kontoAbmelden.
  ///
  /// In de, this message translates to:
  /// **'Abmelden'**
  String get kontoAbmelden;

  /// No description provided for @kontoAbmeldenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Löscht die Kopie auf diesem Telefon; auf dem Server bleibt alles.'**
  String get kontoAbmeldenHinweis;

  /// No description provided for @kontoAbmeldenTitel.
  ///
  /// In de, this message translates to:
  /// **'Abmelden?'**
  String get kontoAbmeldenTitel;

  /// No description provided for @kontoAbmeldenText.
  ///
  /// In de, this message translates to:
  /// **'Das Telefon meldet sich beim Server ab und löscht seine Kopie der Bibliothek samt aller geladenen Bilder. Änderungen, die noch warten, gehen verloren.'**
  String get kontoAbmeldenText;

  /// No description provided for @geraetVorgabe.
  ///
  /// In de, this message translates to:
  /// **'Telefon'**
  String get geraetVorgabe;

  /// No description provided for @anmeldenTitel.
  ///
  /// In de, this message translates to:
  /// **'Mit Server verbinden'**
  String get anmeldenTitel;

  /// No description provided for @anmeldenErklaerung.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault auf dem Telefon zeigt die Bibliothek deines Photo-Vault-Servers – mit Zeitleiste, Suche, Alben, Personen und Karte, auch ohne Verbindung.'**
  String get anmeldenErklaerung;

  /// No description provided for @anmeldenAdresse.
  ///
  /// In de, this message translates to:
  /// **'Adresse des Servers'**
  String get anmeldenAdresse;

  /// No description provided for @anmeldenAdresseHinweis.
  ///
  /// In de, this message translates to:
  /// **'z. B. fotos.example.de'**
  String get anmeldenAdresseHinweis;

  /// No description provided for @anmeldenName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get anmeldenName;

  /// No description provided for @anmeldenPasswort.
  ///
  /// In de, this message translates to:
  /// **'Passwort'**
  String get anmeldenPasswort;

  /// No description provided for @anmeldenGeraet.
  ///
  /// In de, this message translates to:
  /// **'Name dieses Telefons'**
  String get anmeldenGeraet;

  /// No description provided for @anmeldenAnmelden.
  ///
  /// In de, this message translates to:
  /// **'Anmelden'**
  String get anmeldenAnmelden;

  /// No description provided for @anmeldenNichtErreichbar.
  ///
  /// In de, this message translates to:
  /// **'Unter dieser Adresse antwortet kein Server.'**
  String get anmeldenNichtErreichbar;

  /// No description provided for @anmeldenKeinServer.
  ///
  /// In de, this message translates to:
  /// **'Dort antwortet kein Photo-Vault-Server in passender Fassung.'**
  String get anmeldenKeinServer;

  /// No description provided for @anmeldenNurHttps.
  ///
  /// In de, this message translates to:
  /// **'Ohne Verschlüsselung (http://) nur im eigenen Netz – für eine Adresse im Internet bitte https:// verwenden.'**
  String get anmeldenNurHttps;

  /// No description provided for @anmeldenFalsch.
  ///
  /// In de, this message translates to:
  /// **'Name, Passwort oder Code stimmt nicht.'**
  String get anmeldenFalsch;

  /// No description provided for @anmeldenGebremst.
  ///
  /// In de, this message translates to:
  /// **'Zu viele Fehlversuche – bitte in {sekunden} Sekunden erneut versuchen.'**
  String anmeldenGebremst(int sekunden);

  /// No description provided for @anmeldenCodeTitel.
  ///
  /// In de, this message translates to:
  /// **'Code aus der Authenticator-App'**
  String get anmeldenCodeTitel;

  /// No description provided for @anmeldenCodeHinweis.
  ///
  /// In de, this message translates to:
  /// **'Sechs Ziffern – oder einer der Wiederherstellungscodes.'**
  String get anmeldenCodeHinweis;

  /// No description provided for @anmeldenBestaetigen.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get anmeldenBestaetigen;

  /// No description provided for @anmeldenTotpTitel.
  ///
  /// In de, this message translates to:
  /// **'Zwei-Faktor-Anmeldung einrichten'**
  String get anmeldenTotpTitel;

  /// No description provided for @anmeldenTotpText.
  ///
  /// In de, this message translates to:
  /// **'Das Geheimnis in die Authenticator-App übernehmen – mit dem Knopf oder abgetippt – und dann den ersten Code eingeben.'**
  String get anmeldenTotpText;

  /// No description provided for @anmeldenTotpOeffnen.
  ///
  /// In de, this message translates to:
  /// **'In der Authenticator-App öffnen'**
  String get anmeldenTotpOeffnen;

  /// No description provided for @anmeldenCodesTitel.
  ///
  /// In de, this message translates to:
  /// **'Wiederherstellungscodes'**
  String get anmeldenCodesTitel;

  /// No description provided for @anmeldenCodesText.
  ///
  /// In de, this message translates to:
  /// **'Jeder Code gilt einmal, wenn das Telefon mit der Authenticator-App fehlt. Jetzt sicher aufbewahren – sie werden nicht noch einmal gezeigt.'**
  String get anmeldenCodesText;

  /// No description provided for @anmeldenLaedt.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek kommt vom Server …'**
  String get anmeldenLaedt;
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
    'that was used.',
  );
}

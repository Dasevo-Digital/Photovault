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

  /// No description provided for @navBibliothek.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek'**
  String get navBibliothek;

  /// No description provided for @bibFavoriten.
  ///
  /// In de, this message translates to:
  /// **'Favoriten'**
  String get bibFavoriten;

  /// No description provided for @bibPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get bibPapierkorb;

  /// No description provided for @bibAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get bibAlle;

  /// No description provided for @bibFavoritenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Favoriten.'**
  String get bibFavoritenLeer;

  /// No description provided for @bibPapierkorbLeer.
  ///
  /// In de, this message translates to:
  /// **'Der Papierkorb ist leer.'**
  String get bibPapierkorbLeer;

  /// No description provided for @bibPapierkorbHinweis.
  ///
  /// In de, this message translates to:
  /// **'Zurückholen geht hier; endgültig löschen am Rechner.'**
  String get bibPapierkorbHinweis;

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
  /// **'Schlagwort, Ort, Person, Beschreibung, Dateiname …'**
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

  /// No description provided for @betrachterWirdUmgewandelt.
  ///
  /// In de, this message translates to:
  /// **'Das Video wird für dieses Telefon umgewandelt …'**
  String get betrachterWirdUmgewandelt;

  /// No description provided for @betrachterLiveAbspielen.
  ///
  /// In de, this message translates to:
  /// **'Live Photo abspielen'**
  String get betrachterLiveAbspielen;

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

  /// No description provided for @serverSicherungStand.
  ///
  /// In de, this message translates to:
  /// **'Sicherung des Servers: zuletzt {wann}'**
  String serverSicherungStand(String wann);

  /// No description provided for @serverSicherungWarnung.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung des Servers braucht Aufmerksamkeit – am Rechner unter Einstellungen → Server.'**
  String get serverSicherungWarnung;

  /// No description provided for @serverSicherungOffen.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung des Servers ist noch nicht eingerichtet – am Rechner unter Einstellungen → Server.'**
  String get serverSicherungOffen;

  /// No description provided for @speicherStand.
  ///
  /// In de, this message translates to:
  /// **'Speicher auf dem Server: {frei} frei von {gesamt}'**
  String speicherStand(String frei, String gesamt);

  /// No description provided for @speicherKnapp.
  ///
  /// In de, this message translates to:
  /// **'Der Speicher des Servers wird knapp: noch {frei} frei.'**
  String speicherKnapp(String frei);

  /// No description provided for @speicherVoll.
  ///
  /// In de, this message translates to:
  /// **'Der Speicher des Servers ist voll. Neue Fotos nimmt er erst wieder an, wenn Platz frei ist.'**
  String get speicherVoll;

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

  /// No description provided for @anmeldenErstesTitel.
  ///
  /// In de, this message translates to:
  /// **'Erstes Konto anlegen'**
  String get anmeldenErstesTitel;

  /// No description provided for @anmeldenErstesText.
  ///
  /// In de, this message translates to:
  /// **'Dieser Server hat noch kein Konto. Mit dem Namen „{name}“ und dem Passwort von eben wird das erste angelegt. Es wird Verwalter und kann später weitere Konten anlegen.'**
  String anmeldenErstesText(String name);

  /// No description provided for @anmeldenPasswortWiederholen.
  ///
  /// In de, this message translates to:
  /// **'Passwort wiederholen'**
  String get anmeldenPasswortWiederholen;

  /// No description provided for @anmeldenErstesAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Konto anlegen und anmelden'**
  String get anmeldenErstesAnlegen;

  /// No description provided for @anmeldenPasswortUngleich.
  ///
  /// In de, this message translates to:
  /// **'Die beiden Passwörter stimmen nicht überein.'**
  String get anmeldenPasswortUngleich;

  /// No description provided for @anmeldenPasswortZuKurz.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort braucht mindestens {n} Zeichen.'**
  String anmeldenPasswortZuKurz(int n);

  /// No description provided for @anmeldenNameUngueltig.
  ///
  /// In de, this message translates to:
  /// **'Der Name braucht 2 bis 40 Buchstaben, Ziffern, Punkt, Strich oder Unterstrich.'**
  String get anmeldenNameUngueltig;

  /// No description provided for @anmeldenErstesNurHeimnetz.
  ///
  /// In de, this message translates to:
  /// **'Das erste Konto lässt sich nur aus dem Heimnetz anlegen, nicht über den Zugang von außen.'**
  String get anmeldenErstesNurHeimnetz;

  /// No description provided for @anmeldenSchonEingerichtet.
  ///
  /// In de, this message translates to:
  /// **'Der Server hat inzwischen ein Konto. Bitte damit anmelden.'**
  String get anmeldenSchonEingerichtet;

  /// No description provided for @fehlerAllgemein.
  ///
  /// In de, this message translates to:
  /// **'Hat nicht geklappt.'**
  String get fehlerAllgemein;

  /// No description provided for @speichern.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get speichern;

  /// No description provided for @entfernen.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get entfernen;

  /// No description provided for @kontenVerwalten.
  ///
  /// In de, this message translates to:
  /// **'Konten verwalten'**
  String get kontenVerwalten;

  /// No description provided for @kontenVerwaltenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Konten für die Familie anlegen, Passwörter neu setzen'**
  String get kontenVerwaltenHinweis;

  /// No description provided for @kontenTitel.
  ///
  /// In de, this message translates to:
  /// **'Konten auf dem Server'**
  String get kontenTitel;

  /// No description provided for @kontoAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Konto anlegen'**
  String get kontoAnlegen;

  /// No description provided for @kontoVerwalter.
  ///
  /// In de, this message translates to:
  /// **'Verwalter'**
  String get kontoVerwalter;

  /// No description provided for @kontoAlsVerwalter.
  ///
  /// In de, this message translates to:
  /// **'Darf ebenfalls Konten verwalten'**
  String get kontoAlsVerwalter;

  /// No description provided for @kontoGeraete.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{kein Gerät} =1{1 Gerät} other{{n} Geräte}}'**
  String kontoGeraete(int n);

  /// No description provided for @kontoMitTotp.
  ///
  /// In de, this message translates to:
  /// **'mit TOTP'**
  String get kontoMitTotp;

  /// No description provided for @kontoOhneTotp.
  ///
  /// In de, this message translates to:
  /// **'ohne TOTP'**
  String get kontoOhneTotp;

  /// No description provided for @kontoGesperrt.
  ///
  /// In de, this message translates to:
  /// **'gesperrt nach Fehlversuchen'**
  String get kontoGesperrt;

  /// No description provided for @kontoDu.
  ///
  /// In de, this message translates to:
  /// **'dein Konto'**
  String get kontoDu;

  /// No description provided for @kontoPasswortSetzen.
  ///
  /// In de, this message translates to:
  /// **'Passwort neu setzen'**
  String get kontoPasswortSetzen;

  /// No description provided for @kontoPasswortSetzenText.
  ///
  /// In de, this message translates to:
  /// **'Alle Geräte von „{name}“ werden dabei abgemeldet.'**
  String kontoPasswortSetzenText(String name);

  /// No description provided for @kontoTotpZuruecksetzen.
  ///
  /// In de, this message translates to:
  /// **'TOTP zurücksetzen'**
  String get kontoTotpZuruecksetzen;

  /// No description provided for @kontoTotpZurueckgesetzt.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ richtet TOTP bei der nächsten Anmeldung neu ein.'**
  String kontoTotpZurueckgesetzt(String name);

  /// No description provided for @kontoEntsperren.
  ///
  /// In de, this message translates to:
  /// **'Entsperren'**
  String get kontoEntsperren;

  /// No description provided for @kontoEntfernenTitel.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ entfernen?'**
  String kontoEntfernenTitel(String name);

  /// No description provided for @kontoEntfernenText.
  ///
  /// In de, this message translates to:
  /// **'Das Konto und seine Geräte werden entfernt. Die Bibliothek mit allen Fotos bleibt auf dem Server liegen: Sie wird beiseitegelegt, nicht gelöscht, und lässt sich nur dort von Hand löschen.'**
  String get kontoEntfernenText;

  /// No description provided for @kontoErledigt.
  ///
  /// In de, this message translates to:
  /// **'Erledigt.'**
  String get kontoErledigt;

  /// No description provided for @sicherungTitel.
  ///
  /// In de, this message translates to:
  /// **'Kamerarolle sichern'**
  String get sicherungTitel;

  /// No description provided for @sicherungAn.
  ///
  /// In de, this message translates to:
  /// **'Fotos vom Telefon sichern'**
  String get sicherungAn;

  /// No description provided for @sicherungAnHinweis.
  ///
  /// In de, this message translates to:
  /// **'Neue Fotos und Videos gehen von selbst zum Server – auch, wenn die App nicht offen ist.'**
  String get sicherungAnHinweis;

  /// No description provided for @sicherungAus.
  ///
  /// In de, this message translates to:
  /// **'Aus'**
  String get sicherungAus;

  /// No description provided for @sicherungLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Sichert gerade …'**
  String get sicherungLaeuft;

  /// No description provided for @sicherungVideos.
  ///
  /// In de, this message translates to:
  /// **'Videos sichern'**
  String get sicherungVideos;

  /// No description provided for @sicherungNurWlan.
  ///
  /// In de, this message translates to:
  /// **'Nur im WLAN'**
  String get sicherungNurWlan;

  /// No description provided for @sicherungNurBeimLaden.
  ///
  /// In de, this message translates to:
  /// **'Im Hintergrund nur beim Laden'**
  String get sicherungNurBeimLaden;

  /// No description provided for @sicherungAlben.
  ///
  /// In de, this message translates to:
  /// **'Alben'**
  String get sicherungAlben;

  /// No description provided for @sicherungAlleFotos.
  ///
  /// In de, this message translates to:
  /// **'Alle Fotos'**
  String get sicherungAlleFotos;

  /// No description provided for @sicherungAlbenAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Album} other{{n} Alben}}'**
  String sicherungAlbenAnzahl(int n);

  /// No description provided for @sicherungHinweisIos.
  ///
  /// In de, this message translates to:
  /// **'Ist die App offen, sichert sie sofort. Im Hintergrund lässt iOS sie arbeiten, wann es das für richtig hält – meist nachts am Ladekabel.'**
  String get sicherungHinweisIos;

  /// No description provided for @sicherungHinweisAndroid.
  ///
  /// In de, this message translates to:
  /// **'Ist die App offen, sichert sie sofort; im Hintergrund schaut sie alle 15 Minuten nach. Was beim Verlassen der App noch fehlt, lädt sie mit einer Benachrichtigung weiter.'**
  String get sicherungHinweisAndroid;

  /// No description provided for @sicherungKeinZugriff.
  ///
  /// In de, this message translates to:
  /// **'Kein Zugriff auf die Fotos'**
  String get sicherungKeinZugriff;

  /// No description provided for @sicherungKeinZugriffHinweis.
  ///
  /// In de, this message translates to:
  /// **'In den Einstellungen des Telefons erlauben.'**
  String get sicherungKeinZugriffHinweis;

  /// No description provided for @sicherungEinstellungenOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get sicherungEinstellungenOeffnen;

  /// No description provided for @sicherungTeilweise.
  ///
  /// In de, this message translates to:
  /// **'Nur ausgewählte Fotos freigegeben'**
  String get sicherungTeilweise;

  /// No description provided for @sicherungTeilweiseHinweis.
  ///
  /// In de, this message translates to:
  /// **'Gesichert wird nur, was die App sehen darf.'**
  String get sicherungTeilweiseHinweis;

  /// No description provided for @sicherungAuswahlAendern.
  ///
  /// In de, this message translates to:
  /// **'Auswahl ändern'**
  String get sicherungAuswahlAendern;

  /// No description provided for @sicherungWartetWlan.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf WLAN'**
  String get sicherungWartetWlan;

  /// No description provided for @sicherungWartetNetz.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf eine Verbindung'**
  String get sicherungWartetNetz;

  /// No description provided for @sicherungImHintergrund.
  ///
  /// In de, this message translates to:
  /// **'Die Sicherung läuft gerade im Hintergrund.'**
  String get sicherungImHintergrund;

  /// No description provided for @sicherungNochNicht.
  ///
  /// In de, this message translates to:
  /// **'Noch nicht gesichert'**
  String get sicherungNochNicht;

  /// No description provided for @sicherungStand.
  ///
  /// In de, this message translates to:
  /// **'{sicher} von {gesamt} gesichert'**
  String sicherungStand(int sicher, int gesamt);

  /// No description provided for @sicherungLaedt.
  ///
  /// In de, this message translates to:
  /// **'Lädt {datei} hoch'**
  String sicherungLaedt(String datei);

  /// No description provided for @sicherungZuletzt.
  ///
  /// In de, this message translates to:
  /// **'Zuletzt: {zeit}'**
  String sicherungZuletzt(String zeit);

  /// No description provided for @sicherungFehler.
  ///
  /// In de, this message translates to:
  /// **'Der Server hat die Sicherung abgebrochen. Beim nächsten Lauf geht es weiter.'**
  String get sicherungFehler;

  /// No description provided for @sicherungProbleme.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme ließ sich nicht sichern} other{{n} Aufnahmen ließen sich nicht sichern}}'**
  String sicherungProbleme(int n);

  /// No description provided for @sicherungErneut.
  ///
  /// In de, this message translates to:
  /// **'Erneut versuchen'**
  String get sicherungErneut;

  /// No description provided for @sicherungJetzt.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichern'**
  String get sicherungJetzt;

  /// No description provided for @sicherungBenachrichtigungTitel.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault sichert Fotos'**
  String get sicherungBenachrichtigungTitel;

  /// No description provided for @sicherungBenachrichtigungText.
  ///
  /// In de, this message translates to:
  /// **'Fotos und Videos gehen zum Server.'**
  String get sicherungBenachrichtigungText;

  /// No description provided for @sicherungKanal.
  ///
  /// In de, this message translates to:
  /// **'Sicherung'**
  String get sicherungKanal;

  /// No description provided for @appZuAlt.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist neuer als diese App – bitte die App aktualisieren. Bis dahin gleicht nichts ab.'**
  String get appZuAlt;

  /// No description provided for @serverZuAlt.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist älter als diese App – bitte den Server aktualisieren. Bis dahin gleicht nichts ab.'**
  String get serverZuAlt;

  /// No description provided for @auswahlAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 ausgewählt} other{{n} ausgewählt}}'**
  String auswahlAnzahl(int n);

  /// No description provided for @auswahlAufheben.
  ///
  /// In de, this message translates to:
  /// **'Auswahl aufheben'**
  String get auswahlAufheben;

  /// No description provided for @auswahlZurueckholen.
  ///
  /// In de, this message translates to:
  /// **'Zurückholen'**
  String get auswahlZurueckholen;

  /// No description provided for @auswahlTagWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Alle Aufnahmen dieses Tages auswählen'**
  String get auswahlTagWaehlen;

  /// No description provided for @auswahlTagAbwaehlen.
  ///
  /// In de, this message translates to:
  /// **'Auswahl dieses Tages aufheben'**
  String get auswahlTagAbwaehlen;

  /// No description provided for @auswahlFavorit.
  ///
  /// In de, this message translates to:
  /// **'Favorit'**
  String get auswahlFavorit;

  /// No description provided for @auswahlTeilen.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get auswahlTeilen;

  /// No description provided for @auswahlHerunterladen.
  ///
  /// In de, this message translates to:
  /// **'Aufs Telefon'**
  String get auswahlHerunterladen;

  /// No description provided for @auswahlPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb'**
  String get auswahlPapierkorb;

  /// No description provided for @auswahlPapierkorbTitel.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Die Aufnahme in den Papierkorb legen?} other{{n} Aufnahmen in den Papierkorb legen?}}'**
  String auswahlPapierkorbTitel(int n);

  /// No description provided for @auswahlPapierkorbText.
  ///
  /// In de, this message translates to:
  /// **'Sie verschwinden überall – auch am Rechner. Aus dem Papierkorb lassen sie sich am Rechner zurückholen.'**
  String get auswahlPapierkorbText;

  /// No description provided for @auswahlAlbumTitel.
  ///
  /// In de, this message translates to:
  /// **'Zum Album hinzufügen'**
  String get auswahlAlbumTitel;

  /// No description provided for @auswahlAlbumNeu.
  ///
  /// In de, this message translates to:
  /// **'Neues Album'**
  String get auswahlAlbumNeu;

  /// No description provided for @auswahlAlbumName.
  ///
  /// In de, this message translates to:
  /// **'Name des Albums'**
  String get auswahlAlbumName;

  /// No description provided for @auswahlAlbumAnlegen.
  ///
  /// In de, this message translates to:
  /// **'Anlegen'**
  String get auswahlAlbumAnlegen;

  /// No description provided for @auswahlImAlbum.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme im Album „{album}“} other{{n} Aufnahmen im Album „{album}“}}'**
  String auswahlImAlbum(int n, String album);

  /// No description provided for @auswahlLaedt.
  ///
  /// In de, this message translates to:
  /// **'Die Originale werden geladen …'**
  String get auswahlLaedt;

  /// No description provided for @auswahlGespeichert.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme auf dem Telefon gespeichert} other{{n} Aufnahmen auf dem Telefon gespeichert}}'**
  String auswahlGespeichert(int n);

  /// No description provided for @auswahlKeinZugriff.
  ///
  /// In de, this message translates to:
  /// **'Kein Zugriff auf die Fotomediathek – in den Einstellungen des Telefons erlauben.'**
  String get auswahlKeinZugriff;

  /// No description provided for @kontoZwischenspeicher.
  ///
  /// In de, this message translates to:
  /// **'Zwischenspeicher auf dem Telefon'**
  String get kontoZwischenspeicher;

  /// No description provided for @kontoZwischenspeicherStand.
  ///
  /// In de, this message translates to:
  /// **'{belegt} von {grenze} – Vorschauen und Originale, die du angesehen hast. Antippen für die Grenze.'**
  String kontoZwischenspeicherStand(String belegt, String grenze);

  /// No description provided for @kontoZwischenspeicherOhneGrenzeStand.
  ///
  /// In de, this message translates to:
  /// **'{belegt}, ohne Grenze – Vorschauen und Originale, die du angesehen hast. Antippen für die Grenze.'**
  String kontoZwischenspeicherOhneGrenzeStand(String belegt);

  /// No description provided for @kontoZwischenspeicherLeeren.
  ///
  /// In de, this message translates to:
  /// **'Leeren'**
  String get kontoZwischenspeicherLeeren;

  /// No description provided for @kontoZwischenspeicherGrenze.
  ///
  /// In de, this message translates to:
  /// **'Höchstens belegen'**
  String get kontoZwischenspeicherGrenze;

  /// No description provided for @kontoZwischenspeicherOhneGrenze.
  ///
  /// In de, this message translates to:
  /// **'Ohne Grenze'**
  String get kontoZwischenspeicherOhneGrenze;

  /// No description provided for @erinnerungenTitel.
  ///
  /// In de, this message translates to:
  /// **'Erinnerungen'**
  String get erinnerungenTitel;

  /// No description provided for @erinnerungenVorJahren.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Vor 1 Jahr} other{Vor {n} Jahren}}'**
  String erinnerungenVorJahren(int n);

  /// No description provided for @erinnerungenMonatVorJahren.
  ///
  /// In de, this message translates to:
  /// **'{monat} {n, plural, =1{vor 1 Jahr} other{vor {n} Jahren}}'**
  String erinnerungenMonatVorJahren(String monat, int n);

  /// No description provided for @erinnerungenAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String erinnerungenAnzahl(int n);

  /// No description provided for @sicherungFreigeben.
  ///
  /// In de, this message translates to:
  /// **'Speicher freigeben'**
  String get sicherungFreigeben;

  /// No description provided for @sicherungFreigebenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Gesicherte Aufnahmen vom Telefon löschen – auf dem Server bleiben sie.'**
  String get sicherungFreigebenHinweis;

  /// No description provided for @sicherungFreigebenSucht.
  ///
  /// In de, this message translates to:
  /// **'Sucht gesicherte Aufnahmen …'**
  String get sicherungFreigebenSucht;

  /// No description provided for @sicherungFreigebenNichts.
  ///
  /// In de, this message translates to:
  /// **'Nichts freizugeben: Was auf dem Server liegt, ist schon vom Telefon – oder noch nicht gesichert.'**
  String get sicherungFreigebenNichts;

  /// No description provided for @sicherungFreigebenTitel.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme vom Telefon löschen?} other{{n} Aufnahmen vom Telefon löschen?}}'**
  String sicherungFreigebenTitel(int n);

  /// No description provided for @sicherungFreigebenText.
  ///
  /// In de, this message translates to:
  /// **'Nur Aufnahmen, die unverändert und sicher auf dem Server liegen. Das Telefon fragt gleich noch einmal nach.'**
  String get sicherungFreigebenText;

  /// No description provided for @sicherungFreigebenLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get sicherungFreigebenLoeschen;

  /// No description provided for @sicherungFreigegeben.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Nichts gelöscht} =1{1 Aufnahme vom Telefon gelöscht} other{{n} Aufnahmen vom Telefon gelöscht}}'**
  String sicherungFreigegeben(int n);

  /// No description provided for @lokalNochNichtGesichert.
  ///
  /// In de, this message translates to:
  /// **'Nur auf dem Telefon – noch nicht auf dem Server'**
  String get lokalNochNichtGesichert;

  /// No description provided for @lokalJetztSichern.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichern'**
  String get lokalJetztSichern;

  /// No description provided for @lokalAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme nur auf dem Telefon} other{{n} Aufnahmen nur auf dem Telefon}}'**
  String lokalAnzahl(int n);

  /// No description provided for @kontoFassung.
  ///
  /// In de, this message translates to:
  /// **'Fassung'**
  String get kontoFassung;

  /// No description provided for @kontoUnterstuetzen.
  ///
  /// In de, this message translates to:
  /// **'Photo Vault unterstützen'**
  String get kontoUnterstuetzen;

  /// No description provided for @kontoUnterstuetzenText.
  ///
  /// In de, this message translates to:
  /// **'Kostenlos und ohne Werbung – wer mag, spendiert auf Ko-fi einen Kaffee.'**
  String get kontoUnterstuetzenText;

  /// No description provided for @kontoFassungText.
  ///
  /// In de, this message translates to:
  /// **'App {app} · Server {server}'**
  String kontoFassungText(String app, String server);

  /// No description provided for @bibReisen.
  ///
  /// In de, this message translates to:
  /// **'Reisen'**
  String get bibReisen;

  /// No description provided for @reisenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Reisen.'**
  String get reisenLeer;

  /// No description provided for @aktivitaetenTitel.
  ///
  /// In de, this message translates to:
  /// **'Aktivitäten'**
  String get aktivitaetenTitel;

  /// No description provided for @aktivitaetenLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Aktivitäten.'**
  String get aktivitaetenLeer;

  /// No description provided for @anzahlAufnahmen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String anzahlAufnahmen(int n);

  /// No description provided for @gehoertZu.
  ///
  /// In de, this message translates to:
  /// **'Gehört zu: {reise}'**
  String gehoertZu(String reise);

  /// No description provided for @ortWeitere.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{ein weiterer Ort} other{{n} weitere Orte}}'**
  String ortWeitere(int n);

  /// No description provided for @dauerMinuten.
  ///
  /// In de, this message translates to:
  /// **'{m} min'**
  String dauerMinuten(int m);

  /// No description provided for @dauerStunden.
  ///
  /// In de, this message translates to:
  /// **'{h} h {m} min'**
  String dauerStunden(int h, int m);

  /// No description provided for @streckeKm.
  ///
  /// In de, this message translates to:
  /// **'{km} km'**
  String streckeKm(String km);

  /// No description provided for @keineRoute.
  ///
  /// In de, this message translates to:
  /// **'Zu wenige verortete Aufnahmen für eine Strecke.'**
  String get keineRoute;

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

  /// No description provided for @angabenTitel.
  ///
  /// In de, this message translates to:
  /// **'Angaben'**
  String get angabenTitel;

  /// No description provided for @angabenDatumGeschaetzt.
  ///
  /// In de, this message translates to:
  /// **'Datum geschätzt'**
  String get angabenDatumGeschaetzt;

  /// No description provided for @angabenBearbeitet.
  ///
  /// In de, this message translates to:
  /// **'bearbeitet'**
  String get angabenBearbeitet;

  /// No description provided for @angabenStandortBekannt.
  ///
  /// In de, this message translates to:
  /// **'Standort bekannt'**
  String get angabenStandortBekannt;

  /// No description provided for @angabenGeerbt.
  ///
  /// In de, this message translates to:
  /// **'vom Nachbarfoto übernommen'**
  String get angabenGeerbt;

  /// No description provided for @angabenBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get angabenBeschreibung;

  /// No description provided for @angabenSpeichern.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get angabenSpeichern;

  /// No description provided for @angabenGespeichert.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert'**
  String get angabenGespeichert;

  /// No description provided for @angabenAutomatisch.
  ///
  /// In de, this message translates to:
  /// **'Automatisch: {text}'**
  String angabenAutomatisch(String text);

  /// No description provided for @angabenSterne.
  ///
  /// In de, this message translates to:
  /// **'{i} von 5'**
  String angabenSterne(int i);

  /// No description provided for @angabenSerie.
  ///
  /// In de, this message translates to:
  /// **'Serie mit {n} Aufnahmen'**
  String angabenSerie(int n);

  /// No description provided for @angabenText.
  ///
  /// In de, this message translates to:
  /// **'Erkannter Text'**
  String get angabenText;

  /// No description provided for @angabenTranskript.
  ///
  /// In de, this message translates to:
  /// **'Transkript'**
  String get angabenTranskript;

  /// No description provided for @angabenImportiert.
  ///
  /// In de, this message translates to:
  /// **'Importiert {datum}'**
  String angabenImportiert(String datum);

  /// No description provided for @angabenSerieTitel.
  ///
  /// In de, this message translates to:
  /// **'Serie · {n} Aufnahmen'**
  String angabenSerieTitel(int n);

  /// No description provided for @bibStatistik.
  ///
  /// In de, this message translates to:
  /// **'Statistik'**
  String get bibStatistik;

  /// No description provided for @statLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Fotos oder Videos in der Bibliothek.'**
  String get statLeer;

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

  /// No description provided for @statFavoriten.
  ///
  /// In de, this message translates to:
  /// **'Favoriten'**
  String get statFavoriten;

  /// No description provided for @statSpeicher.
  ///
  /// In de, this message translates to:
  /// **'Speicherplatz'**
  String get statSpeicher;

  /// No description provided for @statPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Im Papierkorb'**
  String get statPapierkorb;

  /// No description provided for @statGesperrt.
  ///
  /// In de, this message translates to:
  /// **'Gesperrter Ordner'**
  String get statGesperrt;

  /// No description provided for @statProJahr.
  ///
  /// In de, this message translates to:
  /// **'Fotos & Videos pro Jahr'**
  String get statProJahr;

  /// No description provided for @statProMonat.
  ///
  /// In de, this message translates to:
  /// **'Saisonalität – Aufnahmen pro Monat'**
  String get statProMonat;

  /// No description provided for @statKameras.
  ///
  /// In de, this message translates to:
  /// **'Häufigste Kameras'**
  String get statKameras;

  /// No description provided for @bibDuplikate.
  ///
  /// In de, this message translates to:
  /// **'Duplikate'**
  String get bibDuplikate;

  /// No description provided for @duplAehnlichkeit.
  ///
  /// In de, this message translates to:
  /// **'Ähnlichkeit'**
  String get duplAehnlichkeit;

  /// No description provided for @duplSuchen.
  ///
  /// In de, this message translates to:
  /// **'Suchen'**
  String get duplSuchen;

  /// No description provided for @duplSucht.
  ///
  /// In de, this message translates to:
  /// **'Suche …'**
  String get duplSucht;

  /// No description provided for @duplAlle.
  ///
  /// In de, this message translates to:
  /// **'{n} Kopien in den Papierkorb'**
  String duplAlle(int n);

  /// No description provided for @duplKeineEinbettungen.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Bildeinbettungen – die Auswertung auf dem Server muss zuerst gelaufen sein.'**
  String get duplKeineEinbettungen;

  /// No description provided for @duplKeine.
  ///
  /// In de, this message translates to:
  /// **'Keine Duplikate bei {p} Ähnlichkeit.'**
  String duplKeine(String p);

  /// No description provided for @duplAusnahmen.
  ///
  /// In de, this message translates to:
  /// **'{n} Paare sind ausgenommen.'**
  String duplAusnahmen(int n);

  /// No description provided for @duplGruppen.
  ///
  /// In de, this message translates to:
  /// **'{n} Gruppen bei {p} Ähnlichkeit. Das umrandete Foto würde beim Aufräumen behalten; Gruppen mit mehreren Favoriten oder Bewertungen bleiben unangetastet.'**
  String duplGruppen(int n, String p);

  /// No description provided for @duplKeineDuplikate.
  ///
  /// In de, this message translates to:
  /// **'Keine Duplikate'**
  String get duplKeineDuplikate;

  /// No description provided for @duplNurVonHand.
  ///
  /// In de, this message translates to:
  /// **'{n} Aufnahmen · mehrere ausgezeichnet, nur von Hand'**
  String duplNurVonHand(int n);

  /// No description provided for @duplBehalten.
  ///
  /// In de, this message translates to:
  /// **'Behalten'**
  String get duplBehalten;

  /// No description provided for @duplBehaltenEine.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ behalten und die andere Aufnahme in den Papierkorb legen?'**
  String duplBehaltenEine(String name);

  /// No description provided for @duplBehaltenMehrere.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ behalten und die {n} anderen in den Papierkorb legen?'**
  String duplBehaltenMehrere(String name, int n);

  /// No description provided for @duplAlleFrage.
  ///
  /// In de, this message translates to:
  /// **'{n} Kopien aus {g} Gruppen in den Papierkorb legen? Je Gruppe bleibt das umrandete Foto.'**
  String duplAlleFrage(int n, int g);

  /// No description provided for @bibEinstellungen.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get bibEinstellungen;

  /// No description provided for @einstTitel.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen der Bibliothek'**
  String get einstTitel;

  /// No description provided for @einstHinweis.
  ///
  /// In de, this message translates to:
  /// **'Diese Einstellungen stehen in der Bibliothek und gelten für alle verbundenen Geräte.'**
  String get einstHinweis;

  /// No description provided for @einstSprache.
  ///
  /// In de, this message translates to:
  /// **'Sprache dieser App'**
  String get einstSprache;

  /// No description provided for @einstSpracheHinweis.
  ///
  /// In de, this message translates to:
  /// **'Gilt nur auf diesem Telefon.'**
  String get einstSpracheHinweis;

  /// No description provided for @einstAutomatisch.
  ///
  /// In de, this message translates to:
  /// **'Automatisch'**
  String get einstAutomatisch;

  /// No description provided for @einstGespeichert.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert.'**
  String get einstGespeichert;

  /// No description provided for @einstNach.
  ///
  /// In de, this message translates to:
  /// **'nach'**
  String get einstNach;

  /// No description provided for @einstTagen.
  ///
  /// In de, this message translates to:
  /// **'Tagen'**
  String get einstTagen;

  /// No description provided for @einstAb.
  ///
  /// In de, this message translates to:
  /// **'ab {p}'**
  String einstAb(String p);

  /// No description provided for @einstPapierkorb.
  ///
  /// In de, this message translates to:
  /// **'Papierkorb automatisch leeren'**
  String get einstPapierkorb;

  /// No description provided for @einstPapierkorbText.
  ///
  /// In de, this message translates to:
  /// **'Löscht Aufnahmen im Papierkorb nach Ablauf der Frist endgültig – unwiderruflich.'**
  String get einstPapierkorbText;

  /// No description provided for @einstVorschlaege.
  ///
  /// In de, this message translates to:
  /// **'Sichere Vorschläge automatisch übernehmen'**
  String get einstVorschlaege;

  /// No description provided for @einstVorschlaegeText.
  ///
  /// In de, this message translates to:
  /// **'Erkannte Gesichter, die einer Person sehr ähnlich sind, werden ohne Rückfrage zugeordnet.'**
  String get einstVorschlaegeText;

  /// No description provided for @einstAuswerten.
  ///
  /// In de, this message translates to:
  /// **'KI-Auswertung nach dem Import automatisch nachholen'**
  String get einstAuswerten;

  /// No description provided for @einstAuswertenText.
  ///
  /// In de, this message translates to:
  /// **'Neue Aufnahmen werden gleich ausgewertet: Gesichter, Bildinhalt, Text, Schlagwörter.'**
  String get einstAuswertenText;

  /// No description provided for @einstUebersetzen.
  ///
  /// In de, this message translates to:
  /// **'Suche und Schlagwörter übersetzen'**
  String get einstUebersetzen;

  /// No description provided for @einstUebersetzenText.
  ///
  /// In de, this message translates to:
  /// **'Sucht auf Deutsch und Englisch gleichzeitig und führt Schlagwörter in beiden Sprachen.'**
  String get einstUebersetzenText;

  /// No description provided for @einstSchuetzen.
  ///
  /// In de, this message translates to:
  /// **'Private Metadaten schützen'**
  String get einstSchuetzen;

  /// No description provided for @einstSchuetzenText.
  ///
  /// In de, this message translates to:
  /// **'Neu gesperrte Aufnahmen legen auch Ort, Beschreibung und Text verschlüsselt ab.'**
  String get einstSchuetzenText;

  /// No description provided for @einstSchwelle.
  ///
  /// In de, this message translates to:
  /// **'Schwelle der Gesichtserkennung'**
  String get einstSchwelle;

  /// No description provided for @einstSchwelleText.
  ///
  /// In de, this message translates to:
  /// **'Wie ähnlich ein Gesicht sein muss, um einer Person vorgeschlagen zu werden. Höher heisst vorsichtiger.'**
  String get einstSchwelleText;

  /// No description provided for @verwAuswertungRuht.
  ///
  /// In de, this message translates to:
  /// **'Auswertung: nichts offen'**
  String get verwAuswertungRuht;

  /// No description provided for @verwAuswertungLaeuft.
  ///
  /// In de, this message translates to:
  /// **'Auswertung läuft: {stufe} ({nr}/{von}), {erledigt} von {gesamt}'**
  String verwAuswertungLaeuft(
    String stufe,
    int nr,
    int von,
    int erledigt,
    int gesamt,
  );

  /// No description provided for @verwAnstossen.
  ///
  /// In de, this message translates to:
  /// **'Auswertung anstossen'**
  String get verwAnstossen;

  /// No description provided for @verwJetztSichern.
  ///
  /// In de, this message translates to:
  /// **'Jetzt sichern'**
  String get verwJetztSichern;

  /// No description provided for @bibStammbaum.
  ///
  /// In de, this message translates to:
  /// **'Stammbaum'**
  String get bibStammbaum;

  /// Gruppe der Bibliothek: Favoriten, Personen, Karte, Reisen, Stammbaum, Statistik
  ///
  /// In de, this message translates to:
  /// **'Entdecken'**
  String get bibEntdecken;

  /// Gruppe der Bibliothek: Duplikate, Papierkorb, Einstellungen
  ///
  /// In de, this message translates to:
  /// **'Verwalten'**
  String get bibVerwalten;

  /// No description provided for @baumPerson.
  ///
  /// In de, this message translates to:
  /// **'Person'**
  String get baumPerson;

  /// No description provided for @baumLebensbaum.
  ///
  /// In de, this message translates to:
  /// **'Lebensbaum'**
  String get baumLebensbaum;

  /// No description provided for @baumOhneVerwandtschaft.
  ///
  /// In de, this message translates to:
  /// **'{name} (ohne Verwandtschaft)'**
  String baumOhneVerwandtschaft(String name);

  /// No description provided for @baumKeinePersonen.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.'**
  String get baumKeinePersonen;

  /// No description provided for @baumKeineVerwandtschaft.
  ///
  /// In de, this message translates to:
  /// **'Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.'**
  String get baumKeineVerwandtschaft;

  /// No description provided for @baumVerschwiegen.
  ///
  /// In de, this message translates to:
  /// **'{n} Haushalte passen nicht mehr ins Bild.'**
  String baumVerschwiegen(int n);

  /// No description provided for @lbStil.
  ///
  /// In de, this message translates to:
  /// **'Stil'**
  String get lbStil;

  /// No description provided for @lbPergament.
  ///
  /// In de, this message translates to:
  /// **'Pergament'**
  String get lbPergament;

  /// No description provided for @lbLandschaft.
  ///
  /// In de, this message translates to:
  /// **'Landschaft'**
  String get lbLandschaft;

  /// No description provided for @lbWappen.
  ///
  /// In de, this message translates to:
  /// **'Wappen'**
  String get lbWappen;

  /// No description provided for @lbGold.
  ///
  /// In de, this message translates to:
  /// **'Gold'**
  String get lbGold;

  /// No description provided for @lbZeigt.
  ///
  /// In de, this message translates to:
  /// **'Zeigt'**
  String get lbZeigt;

  /// No description provided for @lbVorfahren.
  ///
  /// In de, this message translates to:
  /// **'Vorfahren'**
  String get lbVorfahren;

  /// No description provided for @lbNachkommen.
  ///
  /// In de, this message translates to:
  /// **'Nachkommen'**
  String get lbNachkommen;

  /// No description provided for @lbPaar.
  ///
  /// In de, this message translates to:
  /// **'Paar'**
  String get lbPaar;

  /// No description provided for @lbFamilie.
  ///
  /// In de, this message translates to:
  /// **'Familie'**
  String get lbFamilie;

  /// No description provided for @lbGenerationen.
  ///
  /// In de, this message translates to:
  /// **'Generationen'**
  String get lbGenerationen;

  /// No description provided for @lbNachOben.
  ///
  /// In de, this message translates to:
  /// **'Nach oben'**
  String get lbNachOben;

  /// No description provided for @lbNachUnten.
  ///
  /// In de, this message translates to:
  /// **'Nach unten'**
  String get lbNachUnten;

  /// No description provided for @lbKreis.
  ///
  /// In de, this message translates to:
  /// **'Kreis'**
  String get lbKreis;

  /// No description provided for @lbDirekteLinie.
  ///
  /// In de, this message translates to:
  /// **'Direkte Linie'**
  String get lbDirekteLinie;

  /// No description provided for @lbMitGeschwistern.
  ///
  /// In de, this message translates to:
  /// **'Mit Geschwistern'**
  String get lbMitGeschwistern;

  /// No description provided for @lbAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle'**
  String get lbAlle;

  /// No description provided for @lbPortraits.
  ///
  /// In de, this message translates to:
  /// **'Porträts'**
  String get lbPortraits;

  /// No description provided for @lbSpeichern.
  ///
  /// In de, this message translates to:
  /// **'Als Bild speichern'**
  String get lbSpeichern;

  /// No description provided for @lbStammbaum.
  ///
  /// In de, this message translates to:
  /// **'Stammbaum'**
  String get lbStammbaum;

  /// No description provided for @entwTitel.
  ///
  /// In de, this message translates to:
  /// **'Entwickeln'**
  String get entwTitel;

  /// No description provided for @entwBelichtung.
  ///
  /// In de, this message translates to:
  /// **'Belichtung'**
  String get entwBelichtung;

  /// No description provided for @entwKontrast.
  ///
  /// In de, this message translates to:
  /// **'Kontrast'**
  String get entwKontrast;

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

  /// No description provided for @entwTemperatur.
  ///
  /// In de, this message translates to:
  /// **'Farbtemperatur'**
  String get entwTemperatur;

  /// No description provided for @entwToenung.
  ///
  /// In de, this message translates to:
  /// **'Tönung'**
  String get entwToenung;

  /// No description provided for @entwKlarheit.
  ///
  /// In de, this message translates to:
  /// **'Klarheit'**
  String get entwKlarheit;

  /// No description provided for @entwSchaerfe.
  ///
  /// In de, this message translates to:
  /// **'Schärfe'**
  String get entwSchaerfe;

  /// No description provided for @entwRauschen.
  ///
  /// In de, this message translates to:
  /// **'Rauschminderung'**
  String get entwRauschen;

  /// No description provided for @entwVignette.
  ///
  /// In de, this message translates to:
  /// **'Vignettierung'**
  String get entwVignette;

  /// No description provided for @entwAutoWeiss.
  ///
  /// In de, this message translates to:
  /// **'Automatischer Weissabgleich'**
  String get entwAutoWeiss;

  /// No description provided for @entwVorher.
  ///
  /// In de, this message translates to:
  /// **'Vorher'**
  String get entwVorher;

  /// No description provided for @entwZuruecksetzen.
  ///
  /// In de, this message translates to:
  /// **'Regler zurücksetzen'**
  String get entwZuruecksetzen;

  /// No description provided for @entwEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Entwicklung entfernen'**
  String get entwEntfernen;

  /// No description provided for @entwVorschauQuelle.
  ///
  /// In de, this message translates to:
  /// **'Rohformat oder HEIC: Das Telefon rechnet aus der Vorschau (höchstens 2048 Pixel). In voller Grösse entwickelt der Rechner.'**
  String get entwVorschauQuelle;

  /// No description provided for @entwVomRechner.
  ///
  /// In de, this message translates to:
  /// **'Tonkurve, Farbmischer und Look vom Rechner wirken mit und bleiben erhalten.'**
  String get entwVomRechner;

  /// No description provided for @entwRechne.
  ///
  /// In de, this message translates to:
  /// **'Rechne in voller Grösse ({b} × {h}) …'**
  String entwRechne(int b, int h);

  /// No description provided for @entwLaedtHoch.
  ///
  /// In de, this message translates to:
  /// **'Lade hoch …'**
  String get entwLaedtHoch;

  /// No description provided for @entwGespeichert.
  ///
  /// In de, this message translates to:
  /// **'Gespeichert.'**
  String get entwGespeichert;

  /// No description provided for @entwVerwerfen.
  ///
  /// In de, this message translates to:
  /// **'Änderungen verwerfen?'**
  String get entwVerwerfen;

  /// No description provided for @entwEntfernenFrage.
  ///
  /// In de, this message translates to:
  /// **'Die Entwicklung entfernen und das Original zeigen?'**
  String get entwEntfernenFrage;

  /// No description provided for @entwNichtGeladen.
  ///
  /// In de, this message translates to:
  /// **'Das Bild liess sich nicht laden.'**
  String get entwNichtGeladen;

  /// No description provided for @entwSpeichern.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get entwSpeichern;

  /// No description provided for @eigenGeraete.
  ///
  /// In de, this message translates to:
  /// **'Geräte'**
  String get eigenGeraete;

  /// No description provided for @eigenDiesesTelefon.
  ///
  /// In de, this message translates to:
  /// **'(dieses Telefon)'**
  String get eigenDiesesTelefon;

  /// No description provided for @eigenZuletzt.
  ///
  /// In de, this message translates to:
  /// **'zuletzt {datum}'**
  String eigenZuletzt(String datum);

  /// No description provided for @eigenGeraetAbmelden.
  ///
  /// In de, this message translates to:
  /// **'Gerät abmelden'**
  String get eigenGeraetAbmelden;

  /// No description provided for @eigenGeraetAbmeldenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ abmelden?'**
  String eigenGeraetAbmeldenFrage(String name);

  /// No description provided for @eigenPasswortAendern.
  ///
  /// In de, this message translates to:
  /// **'Passwort ändern'**
  String get eigenPasswortAendern;

  /// No description provided for @eigenPasswortAlt.
  ///
  /// In de, this message translates to:
  /// **'Aktuelles Passwort'**
  String get eigenPasswortAlt;

  /// No description provided for @eigenPasswortNeu.
  ///
  /// In de, this message translates to:
  /// **'Neues Passwort'**
  String get eigenPasswortNeu;

  /// No description provided for @eigenPasswortNochmal.
  ///
  /// In de, this message translates to:
  /// **'Noch einmal'**
  String get eigenPasswortNochmal;

  /// No description provided for @eigenTotpCode.
  ///
  /// In de, this message translates to:
  /// **'TOTP-Code'**
  String get eigenTotpCode;

  /// No description provided for @eigenAndereAbmelden.
  ///
  /// In de, this message translates to:
  /// **'Andere Geräte abmelden'**
  String get eigenAndereAbmelden;

  /// No description provided for @eigenAendern.
  ///
  /// In de, this message translates to:
  /// **'Ändern'**
  String get eigenAendern;

  /// No description provided for @eigenPasswortUngleich.
  ///
  /// In de, this message translates to:
  /// **'Die neuen Passwörter stimmen nicht überein.'**
  String get eigenPasswortUngleich;

  /// No description provided for @eigenPasswortGeaendert.
  ///
  /// In de, this message translates to:
  /// **'Passwort geändert.'**
  String get eigenPasswortGeaendert;

  /// No description provided for @eigenTotpEingerichtet.
  ///
  /// In de, this message translates to:
  /// **'TOTP eingerichtet'**
  String get eigenTotpEingerichtet;

  /// No description provided for @gesichterOhneNamen.
  ///
  /// In de, this message translates to:
  /// **'Ohne Namen'**
  String get gesichterOhneNamen;

  /// No description provided for @gesichterAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n} Gesichter'**
  String gesichterAnzahl(int n);

  /// No description provided for @gesichterVorschlagFrage.
  ///
  /// In de, this message translates to:
  /// **'{name}?'**
  String gesichterVorschlagFrage(String name);

  /// No description provided for @gesichterWerIstDas.
  ///
  /// In de, this message translates to:
  /// **'Wer ist das?'**
  String get gesichterWerIstDas;

  /// No description provided for @gesichterAehnliche.
  ///
  /// In de, this message translates to:
  /// **'{n} ähnliche Gesichter'**
  String gesichterAehnliche(int n);

  /// No description provided for @gesichterDasIst.
  ///
  /// In de, this message translates to:
  /// **'Das ist {name}'**
  String gesichterDasIst(String name);

  /// No description provided for @gesichterHinweis.
  ///
  /// In de, this message translates to:
  /// **'Antippen nimmt ein Gesicht heraus, das nicht dazugehört.'**
  String get gesichterHinweis;

  /// No description provided for @gesichterName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get gesichterName;

  /// No description provided for @gesichterNamePlatzhalter.
  ///
  /// In de, this message translates to:
  /// **'Neue oder vorhandene Person'**
  String get gesichterNamePlatzhalter;

  /// No description provided for @gesichterNameFehlt.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen Namen eingeben.'**
  String get gesichterNameFehlt;

  /// No description provided for @gesichterBenennen.
  ///
  /// In de, this message translates to:
  /// **'Benennen'**
  String get gesichterBenennen;

  /// No description provided for @gesichterBeiseite.
  ///
  /// In de, this message translates to:
  /// **'Beiseitelegen'**
  String get gesichterBeiseite;

  /// No description provided for @gesichterLoesen.
  ///
  /// In de, this message translates to:
  /// **'Zuordnung lösen'**
  String get gesichterLoesen;

  /// No description provided for @gesichterKeinGesicht.
  ///
  /// In de, this message translates to:
  /// **'Kein Gesicht gewählt.'**
  String get gesichterKeinGesicht;

  /// No description provided for @gesichterAntippen.
  ///
  /// In de, this message translates to:
  /// **'Antippen, um zu benennen oder zu ändern'**
  String get gesichterAntippen;

  /// No description provided for @gesichterWeitereFinden.
  ///
  /// In de, this message translates to:
  /// **'Weitere Fotos finden'**
  String get gesichterWeitereFinden;

  /// No description provided for @gesichterVorschlaegeFuer.
  ///
  /// In de, this message translates to:
  /// **'Vorschläge für {name}'**
  String gesichterVorschlaegeFuer(String name);

  /// No description provided for @gesichterVorschlagHinweis.
  ///
  /// In de, this message translates to:
  /// **'Alles ist ausgewählt. Nimm heraus, was nicht stimmt – auch das lernt die Erkennung: Eine Ablehnung schiebt die Schwelle für diese Person nach oben.'**
  String get gesichterVorschlagHinweis;

  /// No description provided for @gesichterAlleWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Alle wählen'**
  String get gesichterAlleWaehlen;

  /// No description provided for @gesichterKeineWaehlen.
  ///
  /// In de, this message translates to:
  /// **'Keine wählen'**
  String get gesichterKeineWaehlen;

  /// No description provided for @gesichterZuordnenAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Nichts ausgewählt} =1{Ein Gesicht zuordnen} other{{n} Gesichter zuordnen}}'**
  String gesichterZuordnenAnzahl(int n);

  /// No description provided for @gesichterNichtsGefunden.
  ///
  /// In de, this message translates to:
  /// **'Kein unbenanntes Gesicht liegt über der Schwelle {schwelle} dieser Person.'**
  String gesichterNichtsGefunden(String schwelle);

  /// No description provided for @gesichterUebernommen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Nichts übernommen – die Rückmeldung ist trotzdem gespeichert.} =1{Ein Foto hinzugefügt.} other{{n} Fotos hinzugefügt.}}'**
  String gesichterUebernommen(int n);

  /// No description provided for @linkGaesteHochladen.
  ///
  /// In de, this message translates to:
  /// **'Gäste dürfen Fotos und Videos hinzufügen'**
  String get linkGaesteHochladen;

  /// No description provided for @linkGaesteHinweis.
  ///
  /// In de, this message translates to:
  /// **'Jede Datei wird abgeschottet geprüft und neu geschrieben. Ins Album kommt sie erst, wenn du sie annimmst.'**
  String get linkGaesteHinweis;

  /// No description provided for @linkGaesteDuerfen.
  ///
  /// In de, this message translates to:
  /// **'Gäste dürfen hinzufügen'**
  String get linkGaesteDuerfen;

  /// No description provided for @linkBeitraegeOffen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Beitrag offen} other{{n} Beiträge offen}}'**
  String linkBeitraegeOffen(int n);

  /// No description provided for @beitraegeTitel.
  ///
  /// In de, this message translates to:
  /// **'Beiträge von Gästen'**
  String get beitraegeTitel;

  /// No description provided for @beitraegeAlleAnnehmen.
  ///
  /// In de, this message translates to:
  /// **'Alle annehmen'**
  String get beitraegeAlleAnnehmen;

  /// No description provided for @beitraegeAbgeschottet.
  ///
  /// In de, this message translates to:
  /// **'Jede Datei wurde in einem eigenen Prozess ohne Netz geprüft und neu geschrieben – mit Aufnahmezeit, Ort und Kamera, sonst nichts.'**
  String get beitraegeAbgeschottet;

  /// No description provided for @beitraegeMitNetz.
  ///
  /// In de, this message translates to:
  /// **'Jede Datei wurde in einem eigenen Prozess geprüft und neu geschrieben. Eine Netzsperre erlaubt dieses System nicht.'**
  String get beitraegeMitNetz;

  /// No description provided for @beitraegeVon.
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String beitraegeVon(String name);

  /// No description provided for @beitraegeInPruefung.
  ///
  /// In de, this message translates to:
  /// **'wird geprüft …'**
  String get beitraegeInPruefung;

  /// No description provided for @beitraegeAnnehmen.
  ///
  /// In de, this message translates to:
  /// **'Annehmen'**
  String get beitraegeAnnehmen;

  /// No description provided for @beitraegeAblehnen.
  ///
  /// In de, this message translates to:
  /// **'Ablehnen'**
  String get beitraegeAblehnen;

  /// No description provided for @beitraegeEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get beitraegeEntfernen;

  /// No description provided for @beitraegeAngenommen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Beitrag angenommen} other{{n} Beiträge angenommen}}'**
  String beitraegeAngenommen(int n);

  /// No description provided for @diashow.
  ///
  /// In de, this message translates to:
  /// **'Diashow'**
  String get diashow;

  /// No description provided for @diashowAbHier.
  ///
  /// In de, this message translates to:
  /// **'Diashow ab hier'**
  String get diashowAbHier;

  /// No description provided for @diashowKeineFotos.
  ///
  /// In de, this message translates to:
  /// **'Hier sind keine Fotos für eine Diashow – Videos bleiben draussen.'**
  String get diashowKeineFotos;

  /// No description provided for @diashowVorige.
  ///
  /// In de, this message translates to:
  /// **'Vorige'**
  String get diashowVorige;

  /// No description provided for @diashowNaechste.
  ///
  /// In de, this message translates to:
  /// **'Nächste'**
  String get diashowNaechste;

  /// No description provided for @diashowAnhalten.
  ///
  /// In de, this message translates to:
  /// **'Anhalten'**
  String get diashowAnhalten;

  /// No description provided for @diashowWeiter.
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get diashowWeiter;

  /// No description provided for @diashowBeenden.
  ///
  /// In de, this message translates to:
  /// **'Diashow beenden'**
  String get diashowBeenden;

  /// No description provided for @betrachterMehr.
  ///
  /// In de, this message translates to:
  /// **'Mehr'**
  String get betrachterMehr;

  /// No description provided for @bibOrte.
  ///
  /// In de, this message translates to:
  /// **'Orte'**
  String get bibOrte;

  /// No description provided for @orteLeer.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Orte. Sie entstehen, sobald Aufnahmen einen Ort tragen und die Ortsdaten eingerichtet sind.'**
  String get orteLeer;

  /// No description provided for @orteAnzahlOrte.
  ///
  /// In de, this message translates to:
  /// **'{n} Orte'**
  String orteAnzahlOrte(int n);

  /// No description provided for @orteAufnahmen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String orteAufnahmen(int n);

  /// No description provided for @personZusammenfuehren.
  ///
  /// In de, this message translates to:
  /// **'Zusammenführen'**
  String get personZusammenfuehren;

  /// No description provided for @personZusammenfuehrenTitel.
  ///
  /// In de, this message translates to:
  /// **'In „{name}“ aufnehmen'**
  String personZusammenfuehrenTitel(String name);

  /// No description provided for @personZusammenfuehrenText.
  ///
  /// In de, this message translates to:
  /// **'Die gewählte Person geht in dieser auf: ihre Gesichter, Fotos und Verwandtschaft kommen hierher, ihr Name verschwindet.'**
  String get personZusammenfuehrenText;

  /// No description provided for @personZusammenfuehrenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{andere}“ in „{name}“ aufnehmen? Das lässt sich nicht rückgängig machen.'**
  String personZusammenfuehrenFrage(String andere, String name);

  /// No description provided for @sucheFilter.
  ///
  /// In de, this message translates to:
  /// **'Filter'**
  String get sucheFilter;

  /// No description provided for @sucheFilterPersonen.
  ///
  /// In de, this message translates to:
  /// **'Personen'**
  String get sucheFilterPersonen;

  /// No description provided for @sucheFilterOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get sucheFilterOrt;

  /// No description provided for @sucheFilterAlleLaender.
  ///
  /// In de, this message translates to:
  /// **'Alle Länder'**
  String get sucheFilterAlleLaender;

  /// No description provided for @sucheFilterAlleStaedte.
  ///
  /// In de, this message translates to:
  /// **'Alle Städte'**
  String get sucheFilterAlleStaedte;

  /// No description provided for @sucheFilterZeitraum.
  ///
  /// In de, this message translates to:
  /// **'Zeitraum'**
  String get sucheFilterZeitraum;

  /// No description provided for @sucheFilterVon.
  ///
  /// In de, this message translates to:
  /// **'Von'**
  String get sucheFilterVon;

  /// No description provided for @sucheFilterBis.
  ///
  /// In de, this message translates to:
  /// **'Bis'**
  String get sucheFilterBis;

  /// No description provided for @sucheFilterArt.
  ///
  /// In de, this message translates to:
  /// **'Art'**
  String get sucheFilterArt;

  /// No description provided for @sucheFilterAlles.
  ///
  /// In de, this message translates to:
  /// **'Alles'**
  String get sucheFilterAlles;

  /// No description provided for @sucheFilterFotos.
  ///
  /// In de, this message translates to:
  /// **'Fotos'**
  String get sucheFilterFotos;

  /// No description provided for @sucheFilterVideos.
  ///
  /// In de, this message translates to:
  /// **'Videos'**
  String get sucheFilterVideos;

  /// No description provided for @sucheFilterKamera.
  ///
  /// In de, this message translates to:
  /// **'Kamera'**
  String get sucheFilterKamera;

  /// No description provided for @sucheFilterAlleKameras.
  ///
  /// In de, this message translates to:
  /// **'Alle Kameras'**
  String get sucheFilterAlleKameras;

  /// No description provided for @sucheFilterFavoriten.
  ///
  /// In de, this message translates to:
  /// **'Nur Favoriten'**
  String get sucheFilterFavoriten;

  /// No description provided for @sucheFilterZuruecksetzen.
  ///
  /// In de, this message translates to:
  /// **'Zurücksetzen'**
  String get sucheFilterZuruecksetzen;

  /// No description provided for @sucheFilterAnwenden.
  ///
  /// In de, this message translates to:
  /// **'Anwenden'**
  String get sucheFilterAnwenden;

  /// No description provided for @sucheFilterZeile.
  ///
  /// In de, this message translates to:
  /// **'Filter: {text}'**
  String sucheFilterZeile(String text);

  /// No description provided for @sucheTextOderFilter.
  ///
  /// In de, this message translates to:
  /// **'Suchtext eingeben oder einen Filter wählen.'**
  String get sucheTextOderFilter;

  /// No description provided for @linkTitel.
  ///
  /// In de, this message translates to:
  /// **'Als Link teilen'**
  String get linkTitel;

  /// No description provided for @linkFeldTitel.
  ///
  /// In de, this message translates to:
  /// **'Titel'**
  String get linkFeldTitel;

  /// No description provided for @linkGueltig.
  ///
  /// In de, this message translates to:
  /// **'Gültig'**
  String get linkGueltig;

  /// No description provided for @linkTag1.
  ///
  /// In de, this message translates to:
  /// **'1 Tag'**
  String get linkTag1;

  /// No description provided for @linkTage.
  ///
  /// In de, this message translates to:
  /// **'{n} Tage'**
  String linkTage(int n);

  /// No description provided for @linkJahr1.
  ///
  /// In de, this message translates to:
  /// **'1 Jahr'**
  String get linkJahr1;

  /// No description provided for @linkUnbegrenzt.
  ///
  /// In de, this message translates to:
  /// **'Unbegrenzt'**
  String get linkUnbegrenzt;

  /// No description provided for @linkPasswort.
  ///
  /// In de, this message translates to:
  /// **'Passwort (frei lassen für keins)'**
  String get linkPasswort;

  /// No description provided for @linkHerunterladen.
  ///
  /// In de, this message translates to:
  /// **'Originale herunterladen erlauben'**
  String get linkHerunterladen;

  /// No description provided for @linkOhneMetadaten.
  ///
  /// In de, this message translates to:
  /// **'Gezeigt werden Bilder ohne Orts- und Kameraangaben. Originale enthalten sie.'**
  String get linkOhneMetadaten;

  /// No description provided for @linkErstellen.
  ///
  /// In de, this message translates to:
  /// **'Link erstellen'**
  String get linkErstellen;

  /// No description provided for @linkWerHatSieht.
  ///
  /// In de, this message translates to:
  /// **'Wer diesen Link hat, sieht die Aufnahmen:'**
  String get linkWerHatSieht;

  /// No description provided for @linkNurHeimnetz.
  ///
  /// In de, this message translates to:
  /// **'Diese Adresse ist nur im Heimnetz erreichbar. Von aussen geht der Link über die öffentliche Adresse des Servers.'**
  String get linkNurHeimnetz;

  /// No description provided for @linkKopieren.
  ///
  /// In de, this message translates to:
  /// **'Kopieren'**
  String get linkKopieren;

  /// No description provided for @linkTeilen.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get linkTeilen;

  /// No description provided for @linkKopiert.
  ///
  /// In de, this message translates to:
  /// **'Link kopiert'**
  String get linkKopiert;

  /// No description provided for @linkTitelFehlt.
  ///
  /// In de, this message translates to:
  /// **'Bitte einen Titel eingeben.'**
  String get linkTitelFehlt;

  /// No description provided for @linkPasswortKurz.
  ///
  /// In de, this message translates to:
  /// **'Das Passwort braucht mindestens 4 Zeichen.'**
  String get linkPasswortKurz;

  /// No description provided for @linkOhneServer.
  ///
  /// In de, this message translates to:
  /// **'Ohne Verbindung zum Server gibt es keinen Link.'**
  String get linkOhneServer;

  /// No description provided for @linkGeteilte.
  ///
  /// In de, this message translates to:
  /// **'Geteilte Links'**
  String get linkGeteilte;

  /// No description provided for @linkNochNichts.
  ///
  /// In de, this message translates to:
  /// **'Noch nichts geteilt.'**
  String get linkNochNichts;

  /// No description provided for @linkAnzahl.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme} other{{n} Aufnahmen}}'**
  String linkAnzahl(int n);

  /// No description provided for @linkAbgelaufen.
  ///
  /// In de, this message translates to:
  /// **'abgelaufen'**
  String get linkAbgelaufen;

  /// No description provided for @linkBis.
  ///
  /// In de, this message translates to:
  /// **'bis {datum}'**
  String linkBis(String datum);

  /// No description provided for @linkMitPasswort.
  ///
  /// In de, this message translates to:
  /// **'mit Passwort'**
  String get linkMitPasswort;

  /// No description provided for @linkAufrufe.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufruf} other{{n} Aufrufe}}'**
  String linkAufrufe(int n);

  /// No description provided for @linkLoeschen.
  ///
  /// In de, this message translates to:
  /// **'Löschen'**
  String get linkLoeschen;

  /// No description provided for @linkLoeschenFrage.
  ///
  /// In de, this message translates to:
  /// **'Den Link „{titel}“ löschen? Wer ihn hat, sieht danach nichts mehr.'**
  String linkLoeschenFrage(String titel);

  /// No description provided for @auswahlLink.
  ///
  /// In de, this message translates to:
  /// **'Link'**
  String get auswahlLink;

  /// No description provided for @albumAlsLink.
  ///
  /// In de, this message translates to:
  /// **'Als Link teilen'**
  String get albumAlsLink;

  /// No description provided for @spurTitel.
  ///
  /// In de, this message translates to:
  /// **'Aufgezeichnete Spur'**
  String get spurTitel;

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

  /// No description provided for @gelaendeOeffnen.
  ///
  /// In de, this message translates to:
  /// **'Gelände ansehen'**
  String get gelaendeOeffnen;

  /// No description provided for @gelaendeVideoErstellen.
  ///
  /// In de, this message translates to:
  /// **'Video erstellen'**
  String get gelaendeVideoErstellen;
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

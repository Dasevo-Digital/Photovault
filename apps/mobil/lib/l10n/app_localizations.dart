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

  /// No description provided for @kontoFassungText.
  ///
  /// In de, this message translates to:
  /// **'App {app} · Server {server}'**
  String kontoFassungText(String app, String server);
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

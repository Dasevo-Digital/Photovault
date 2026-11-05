import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'teilen_texte_de.dart';
import 'teilen_texte_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of TeilenTexte
/// returned by `TeilenTexte.of(context)`.
///
/// Applications need to include `TeilenTexte.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/teilen_texte.dart';
///
/// return MaterialApp(
///   localizationsDelegates: TeilenTexte.localizationsDelegates,
///   supportedLocales: TeilenTexte.supportedLocales,
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
/// be consistent with the languages listed in the TeilenTexte.supportedLocales
/// property.
abstract class TeilenTexte {
  TeilenTexte(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static TeilenTexte of(BuildContext context) {
    return Localizations.of<TeilenTexte>(context, TeilenTexte)!;
  }

  static const LocalizationsDelegate<TeilenTexte> delegate =
      _TeilenTexteDelegate();

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

  /// No description provided for @geteiltMitMir.
  ///
  /// In de, this message translates to:
  /// **'Geteilt mit mir'**
  String get geteiltMitMir;

  /// No description provided for @geteiltVon.
  ///
  /// In de, this message translates to:
  /// **'von {name}'**
  String geteiltVon(String name);

  /// No description provided for @geteiltAlbumVon.
  ///
  /// In de, this message translates to:
  /// **'Geteilt von {name}'**
  String geteiltAlbumVon(String name);

  /// No description provided for @geteiltBeigetragenVon.
  ///
  /// In de, this message translates to:
  /// **'Beigetragen von {name}'**
  String geteiltBeigetragenVon(String name);

  /// No description provided for @geteiltHinzufuegen.
  ///
  /// In de, this message translates to:
  /// **'Fotos hinzufügen'**
  String get geteiltHinzufuegen;

  /// No description provided for @geteiltVerlassen.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr anzeigen'**
  String get geteiltVerlassen;

  /// No description provided for @geteiltVerlassenFrage.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ nicht mehr anzeigen? Die Fotos bleiben bei {besitzer}; teilen kann nur {besitzer} es wieder.'**
  String geteiltVerlassenFrage(String name, String besitzer);

  /// No description provided for @geteiltNichtMehr.
  ///
  /// In de, this message translates to:
  /// **'Dieses Album ist nicht mehr mit dir geteilt.'**
  String get geteiltNichtMehr;

  /// No description provided for @geteiltLaedtHoch.
  ///
  /// In de, this message translates to:
  /// **'Lade {i} von {n} hoch …'**
  String geteiltLaedtHoch(int i, int n);

  /// No description provided for @geteiltHinzugefuegt.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{1 Aufnahme hinzugefügt} other{{n} Aufnahmen hinzugefügt}}'**
  String geteiltHinzugefuegt(int n);

  /// No description provided for @geteiltNurAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Du darfst in dieses Album nichts mehr legen.'**
  String get geteiltNurAnsehen;

  /// No description provided for @geteiltSpeicherVoll.
  ///
  /// In de, this message translates to:
  /// **'Der Speicher des Servers ist voll.'**
  String get geteiltSpeicherVoll;

  /// No description provided for @geteiltFehler.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ ging nicht.'**
  String geteiltFehler(String name);

  /// No description provided for @geteiltOffline.
  ///
  /// In de, this message translates to:
  /// **'Der Server ist gerade nicht zu erreichen.'**
  String get geteiltOffline;

  /// No description provided for @geteiltLeer.
  ///
  /// In de, this message translates to:
  /// **'Das Album ist leer.'**
  String get geteiltLeer;

  /// No description provided for @geteiltEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Aus dem Album entfernen'**
  String get geteiltEntfernen;

  /// No description provided for @geteiltEntfernenFrage.
  ///
  /// In de, this message translates to:
  /// **'Deinen Beitrag „{name}“ aus dem Album entfernen? Liegt er in keinem anderen Album, kommt er in den Papierkorb des Besitzers.'**
  String geteiltEntfernenFrage(String name);

  /// No description provided for @geteiltEntfernt.
  ///
  /// In de, this message translates to:
  /// **'Aus dem Album entfernt'**
  String get geteiltEntfernt;

  /// No description provided for @kontenTeilen.
  ///
  /// In de, this message translates to:
  /// **'Mit Konten teilen'**
  String get kontenTeilen;

  /// No description provided for @kontenTeilenTitel.
  ///
  /// In de, this message translates to:
  /// **'„{titel}“ mit Konten teilen'**
  String kontenTeilenTitel(String titel);

  /// No description provided for @kontenTeilenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Andere Konten dieses Servers sehen das Album unter „Geteilt mit mir“ – im Browser und auf dem Telefon.'**
  String get kontenTeilenHinweis;

  /// No description provided for @kontenBeitragenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wer beitragen darf, legt Fotos und Videos direkt in dieses Album. Sie kommen in deine Bibliothek.'**
  String get kontenBeitragenHinweis;

  /// No description provided for @kontenAnsehen.
  ///
  /// In de, this message translates to:
  /// **'Ansehen'**
  String get kontenAnsehen;

  /// No description provided for @kontenBeitragen.
  ///
  /// In de, this message translates to:
  /// **'Beitragen'**
  String get kontenBeitragen;

  /// No description provided for @kontenNiemand.
  ///
  /// In de, this message translates to:
  /// **'Mit niemandem geteilt.'**
  String get kontenNiemand;

  /// No description provided for @kontenKeineAnderen.
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Server gibt es kein weiteres Konto.'**
  String get kontenKeineAnderen;

  /// No description provided for @kontenTeilenKnopf.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get kontenTeilenKnopf;

  /// No description provided for @abbrechen.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get abbrechen;

  /// No description provided for @entfernen.
  ///
  /// In de, this message translates to:
  /// **'Entfernen'**
  String get entfernen;

  /// No description provided for @schliessen.
  ///
  /// In de, this message translates to:
  /// **'Schliessen'**
  String get schliessen;

  /// No description provided for @neueBeitraegeTitel.
  ///
  /// In de, this message translates to:
  /// **'Neu in deinen geteilten Alben'**
  String get neueBeitraegeTitel;

  /// No description provided for @neueBeitraegeAlbum.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{„{name}“: 1 neue Aufnahme} other{„{name}“: {n} neue Aufnahmen}}'**
  String neueBeitraegeAlbum(String name, int n);

  /// No description provided for @neueBeitraegeVon.
  ///
  /// In de, this message translates to:
  /// **'von {namen}'**
  String neueBeitraegeVon(String namen);

  /// No description provided for @partnerBibliothekVon.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek von {name}'**
  String partnerBibliothekVon(String name);

  /// No description provided for @partnerGanzeBibliothek.
  ///
  /// In de, this message translates to:
  /// **'Ganze Bibliothek'**
  String get partnerGanzeBibliothek;

  /// No description provided for @partnerNichtMehr.
  ///
  /// In de, this message translates to:
  /// **'Diese Bibliothek ist nicht mehr mit dir geteilt.'**
  String get partnerNichtMehr;

  /// No description provided for @partnerVerlassenFrage.
  ///
  /// In de, this message translates to:
  /// **'Die Bibliothek von {name} nicht mehr anzeigen? Teilen kann nur {name} sie wieder.'**
  String partnerVerlassenFrage(String name);

  /// No description provided for @bibliothekTeilen.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek teilen'**
  String get bibliothekTeilen;

  /// No description provided for @bibliothekTeilenTitel.
  ///
  /// In de, this message translates to:
  /// **'Bibliothek teilen'**
  String get bibliothekTeilenTitel;

  /// No description provided for @bibliothekTeilenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Wer hier steht, sieht deine Bibliothek unter „Geteilt mit mir“ – ganz oder nur ab einem Tag und mit bestimmten Personen, ohne Gesperrtes und Papierkorb, nur zum Ansehen.'**
  String get bibliothekTeilenHinweis;

  /// No description provided for @kommentare.
  ///
  /// In de, this message translates to:
  /// **'Kommentare'**
  String get kommentare;

  /// No description provided for @kommentarSchreiben.
  ///
  /// In de, this message translates to:
  /// **'Kommentar schreiben …'**
  String get kommentarSchreiben;

  /// No description provided for @kommentarSenden.
  ///
  /// In de, this message translates to:
  /// **'Senden'**
  String get kommentarSenden;

  /// No description provided for @kommentarEntfernen.
  ///
  /// In de, this message translates to:
  /// **'Kommentar entfernen'**
  String get kommentarEntfernen;

  /// No description provided for @kommentarEntfernenFrage.
  ///
  /// In de, this message translates to:
  /// **'Diesen Kommentar entfernen?'**
  String get kommentarEntfernenFrage;

  /// No description provided for @kommentareKeine.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Kommentare.'**
  String get kommentareKeine;

  /// No description provided for @kommentarZuFoto.
  ///
  /// In de, this message translates to:
  /// **'zu einem Foto'**
  String get kommentarZuFoto;

  /// No description provided for @kommentarFehler.
  ///
  /// In de, this message translates to:
  /// **'Das hat nicht geklappt. Bitte später noch einmal versuchen.'**
  String get kommentarFehler;

  /// No description provided for @kommentareHinweis.
  ///
  /// In de, this message translates to:
  /// **'Alle, mit denen das Album geteilt ist, sehen die Kommentare.'**
  String get kommentareHinweis;

  /// No description provided for @gefaelltMir.
  ///
  /// In de, this message translates to:
  /// **'Gefällt mir'**
  String get gefaelltMir;

  /// No description provided for @gefaelltNamen.
  ///
  /// In de, this message translates to:
  /// **'Gefällt {namen}'**
  String gefaelltNamen(String namen);

  /// No description provided for @speichern.
  ///
  /// In de, this message translates to:
  /// **'Speichern'**
  String get speichern;

  /// No description provided for @automatischFuellen.
  ///
  /// In de, this message translates to:
  /// **'Automatisch füllen'**
  String get automatischFuellen;

  /// No description provided for @automatischTitel.
  ///
  /// In de, this message translates to:
  /// **'„{name}“ automatisch füllen'**
  String automatischTitel(String name);

  /// No description provided for @automatischHinweis.
  ///
  /// In de, this message translates to:
  /// **'Fotos der gewählten Personen kommen von selbst in dieses Album – auch solche, auf denen sie erst später erkannt werden. Was du herausnimmst, bleibt draussen.'**
  String get automatischHinweis;

  /// No description provided for @automatischAus.
  ///
  /// In de, this message translates to:
  /// **'Nicht mehr automatisch füllen'**
  String get automatischAus;

  /// No description provided for @automatischAusGemacht.
  ///
  /// In de, this message translates to:
  /// **'Das Album füllt sich nicht mehr selbst. Was darin liegt, bleibt.'**
  String get automatischAusGemacht;

  /// No description provided for @automatischDazu.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =0{Nichts Neues dazugelegt} =1{Eine Aufnahme dazugelegt} other{{n} Aufnahmen dazugelegt}}'**
  String automatischDazu(int n);

  /// No description provided for @regelEine.
  ///
  /// In de, this message translates to:
  /// **'Eine der Personen'**
  String get regelEine;

  /// No description provided for @regelAlle.
  ///
  /// In de, this message translates to:
  /// **'Alle zusammen'**
  String get regelAlle;

  /// No description provided for @regelMindestensEine.
  ///
  /// In de, this message translates to:
  /// **'Wähle mindestens eine Person.'**
  String get regelMindestensEine;

  /// No description provided for @regelHoechstens.
  ///
  /// In de, this message translates to:
  /// **'Höchstens 20 Personen.'**
  String get regelHoechstens;

  /// No description provided for @regelPersonenFehlen.
  ///
  /// In de, this message translates to:
  /// **'{n, plural, =1{Eine gewählte Person gibt es nicht mehr.} other{{n} gewählte Personen gibt es nicht mehr.}}'**
  String regelPersonenFehlen(int n);

  /// No description provided for @regelMit.
  ///
  /// In de, this message translates to:
  /// **'mit {namen}'**
  String regelMit(String namen);

  /// No description provided for @regelZusammen.
  ///
  /// In de, this message translates to:
  /// **'{namen} zusammen'**
  String regelZusammen(String namen);

  /// No description provided for @regelAb.
  ///
  /// In de, this message translates to:
  /// **'ab {tag}'**
  String regelAb(String tag);

  /// No description provided for @aufgenommenAb.
  ///
  /// In de, this message translates to:
  /// **'Aufgenommen ab'**
  String get aufgenommenAb;

  /// No description provided for @jedesDatum.
  ///
  /// In de, this message translates to:
  /// **'jedes Datum'**
  String get jedesDatum;

  /// No description provided for @personSuchen.
  ///
  /// In de, this message translates to:
  /// **'Person suchen'**
  String get personSuchen;

  /// No description provided for @keinePersonGefunden.
  ///
  /// In de, this message translates to:
  /// **'Keine Person gefunden.'**
  String get keinePersonGefunden;

  /// No description provided for @keinePersonenMitNamen.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Personen mit Namen.'**
  String get keinePersonenMitNamen;

  /// No description provided for @partnerEinschraenken.
  ///
  /// In de, this message translates to:
  /// **'Einschränken'**
  String get partnerEinschraenken;

  /// No description provided for @partnerWasSieht.
  ///
  /// In de, this message translates to:
  /// **'Was {name} sieht'**
  String partnerWasSieht(String name);

  /// No description provided for @partnerEinschraenkenHinweis.
  ///
  /// In de, this message translates to:
  /// **'Ohne Auswahl sieht {name} deine ganze Bibliothek. Mit Personen nur Fotos, auf denen mindestens eine davon ist – das gilt für jede Datei, nicht nur für die Liste.'**
  String partnerEinschraenkenHinweis(String name);

  /// No description provided for @partnerGanz.
  ///
  /// In de, this message translates to:
  /// **'Die ganze Bibliothek'**
  String get partnerGanz;

  /// No description provided for @partnerInZeitleiste.
  ///
  /// In de, this message translates to:
  /// **'In meiner Zeitleiste zeigen'**
  String get partnerInZeitleiste;

  /// No description provided for @partnerInZeitleisteFern.
  ///
  /// In de, this message translates to:
  /// **'In der Zeitleiste zeigen (Handy und Browser)'**
  String get partnerInZeitleisteFern;

  /// No description provided for @partnerEingeschraenkt.
  ///
  /// In de, this message translates to:
  /// **'Nur ein Teil der Bibliothek'**
  String get partnerEingeschraenkt;
}

class _TeilenTexteDelegate extends LocalizationsDelegate<TeilenTexte> {
  const _TeilenTexteDelegate();

  @override
  Future<TeilenTexte> load(Locale locale) {
    return SynchronousFuture<TeilenTexte>(lookupTeilenTexte(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_TeilenTexteDelegate old) => false;
}

TeilenTexte lookupTeilenTexte(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return TeilenTexteDe();
    case 'en':
      return TeilenTexteEn();
  }

  throw FlutterError(
    'TeilenTexte.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

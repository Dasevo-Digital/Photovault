import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'sync_texte_de.dart';
import 'sync_texte_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of SyncTexte
/// returned by `SyncTexte.of(context)`.
///
/// Applications need to include `SyncTexte.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/sync_texte.dart';
///
/// return MaterialApp(
///   localizationsDelegates: SyncTexte.localizationsDelegates,
///   supportedLocales: SyncTexte.supportedLocales,
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
/// be consistent with the languages listed in the SyncTexte.supportedLocales
/// property.
abstract class SyncTexte {
  SyncTexte(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static SyncTexte of(BuildContext context) {
    return Localizations.of<SyncTexte>(context, SyncTexte)!;
  }

  static const LocalizationsDelegate<SyncTexte> delegate = _SyncTexteDelegate();

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

  /// No description provided for @titel.
  ///
  /// In de, this message translates to:
  /// **'Änderungen und Konflikte'**
  String get titel;

  /// No description provided for @aktualisieren.
  ///
  /// In de, this message translates to:
  /// **'Abgleich erneut versuchen'**
  String get aktualisieren;

  /// No description provided for @wartet.
  ///
  /// In de, this message translates to:
  /// **'Wartet auf Übertragung'**
  String get wartet;

  /// No description provided for @konflikt.
  ///
  /// In de, this message translates to:
  /// **'Gleichzeitig geändert'**
  String get konflikt;

  /// No description provided for @abgelehnt.
  ///
  /// In de, this message translates to:
  /// **'Vom Server abgelehnt'**
  String get abgelehnt;

  /// No description provided for @unlesbar.
  ///
  /// In de, this message translates to:
  /// **'Auf diesem Gerät nicht mehr entschlüsselbar'**
  String get unlesbar;

  /// No description provided for @leer.
  ///
  /// In de, this message translates to:
  /// **'Keine offenen Änderungen oder Konflikte.'**
  String get leer;

  /// No description provided for @mehr.
  ///
  /// In de, this message translates to:
  /// **'Weitere laden'**
  String get mehr;

  /// No description provided for @fehler.
  ///
  /// In de, this message translates to:
  /// **'Die Übersicht konnte nicht aktualisiert werden. Gespeicherte Änderungen bleiben erhalten.'**
  String get fehler;

  /// No description provided for @alt.
  ///
  /// In de, this message translates to:
  /// **'Der Server muss aktualisiert werden, bevor geschützte Änderungen übertragen werden können.'**
  String get alt;

  /// No description provided for @geschuetzt.
  ///
  /// In de, this message translates to:
  /// **'Mindestens eine betroffene Aufnahme ist gesperrt. Inhalte und erneutes Anwenden bleiben gesperrt.'**
  String get geschuetzt;

  /// No description provided for @entfernt.
  ///
  /// In de, this message translates to:
  /// **'Eine betroffene Aufnahme wurde entfernt oder liegt im Papierkorb. Die alte Änderung kann nicht erneut angewandt werden.'**
  String get entfernt;

  /// No description provided for @behalten.
  ///
  /// In de, this message translates to:
  /// **'Serverstand behalten'**
  String get behalten;

  /// No description provided for @anwenden.
  ///
  /// In de, this message translates to:
  /// **'Eigene Änderung erneut anwenden'**
  String get anwenden;

  /// No description provided for @entscheidung.
  ///
  /// In de, this message translates to:
  /// **'Die Entscheidung gilt für die gesamte ursprüngliche Aktion einschließlich aller betroffenen Aufnahmen. Andere offene Änderungen bleiben erhalten.'**
  String get entscheidung;

  /// No description provided for @wartetText.
  ///
  /// In de, this message translates to:
  /// **'Dies ist die gespeicherte lokale Absicht. Der Serverstand wird erst bei einer Verbindung geprüft.'**
  String get wartetText;

  /// No description provided for @geaendert.
  ///
  /// In de, this message translates to:
  /// **'Der Serverstand hat sich inzwischen geändert. Bitte den neuen Vergleich prüfen und erneut entscheiden.'**
  String get geaendert;

  /// No description provided for @server.
  ///
  /// In de, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @eigen.
  ///
  /// In de, this message translates to:
  /// **'Eigene Absicht'**
  String get eigen;

  /// No description provided for @unbekannt.
  ///
  /// In de, this message translates to:
  /// **'Bibliotheksänderung'**
  String get unbekannt;

  /// No description provided for @favorit.
  ///
  /// In de, this message translates to:
  /// **'Favorit ändern'**
  String get favorit;

  /// No description provided for @bewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung ändern'**
  String get bewertung;

  /// No description provided for @farbe.
  ///
  /// In de, this message translates to:
  /// **'Farbmarke ändern'**
  String get farbe;

  /// No description provided for @beschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung ändern'**
  String get beschreibung;

  /// No description provided for @album.
  ///
  /// In de, this message translates to:
  /// **'Album ändern'**
  String get album;

  /// No description provided for @tag.
  ///
  /// In de, this message translates to:
  /// **'Tags ändern'**
  String get tag;

  /// No description provided for @person.
  ///
  /// In de, this message translates to:
  /// **'Personen ändern'**
  String get person;

  /// No description provided for @wertFavorit.
  ///
  /// In de, this message translates to:
  /// **'Favorit'**
  String get wertFavorit;

  /// No description provided for @wertBewertung.
  ///
  /// In de, this message translates to:
  /// **'Bewertung'**
  String get wertBewertung;

  /// No description provided for @wertFarbe.
  ///
  /// In de, this message translates to:
  /// **'Farbmarke'**
  String get wertFarbe;

  /// No description provided for @wertBeschreibung.
  ///
  /// In de, this message translates to:
  /// **'Beschreibung'**
  String get wertBeschreibung;

  /// No description provided for @wertName.
  ///
  /// In de, this message translates to:
  /// **'Name'**
  String get wertName;

  /// No description provided for @wertDatum.
  ///
  /// In de, this message translates to:
  /// **'Aufnahmedatum'**
  String get wertDatum;

  /// No description provided for @wertAlbum.
  ///
  /// In de, this message translates to:
  /// **'Album'**
  String get wertAlbum;

  /// No description provided for @wertTag.
  ///
  /// In de, this message translates to:
  /// **'Tag'**
  String get wertTag;

  /// No description provided for @wertPerson.
  ///
  /// In de, this message translates to:
  /// **'Person'**
  String get wertPerson;

  /// No description provided for @wertOrt.
  ///
  /// In de, this message translates to:
  /// **'Ort'**
  String get wertOrt;

  /// No description provided for @ja.
  ///
  /// In de, this message translates to:
  /// **'Ja'**
  String get ja;

  /// No description provided for @nein.
  ///
  /// In de, this message translates to:
  /// **'Nein'**
  String get nein;

  /// No description provided for @kein.
  ///
  /// In de, this message translates to:
  /// **'Kein Wert / entfernt'**
  String get kein;

  /// No description provided for @komplex.
  ///
  /// In de, this message translates to:
  /// **'Weitere Angaben dieser Aktion sind gespeichert; die Entscheidung gilt auch für sie.'**
  String get komplex;

  /// No description provided for @abbrechen.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get abbrechen;

  /// No description provided for @bestaetigen.
  ///
  /// In de, this message translates to:
  /// **'Bestätigen'**
  String get bestaetigen;

  /// No description provided for @grundKonflikt.
  ///
  /// In de, this message translates to:
  /// **'Ein anderes Gerät hat dieselben Angaben verändert.'**
  String get grundKonflikt;

  /// No description provided for @grundAbgelehnt.
  ///
  /// In de, this message translates to:
  /// **'Der Server konnte die Aktion nicht ausführen, etwa wegen fehlender Rechte oder ungültiger Daten.'**
  String get grundAbgelehnt;

  /// No description provided for @anzahl.
  ///
  /// In de, this message translates to:
  /// **'{offen} wartend · {faelle} zu entscheiden'**
  String anzahl(int offen, int faelle);

  /// No description provided for @fotos.
  ///
  /// In de, this message translates to:
  /// **'{anzahl} betroffene Aufnahmen'**
  String fotos(int anzahl);

  /// No description provided for @wertBreite.
  ///
  /// In de, this message translates to:
  /// **'Breitengrad'**
  String get wertBreite;

  /// No description provided for @wertLaenge.
  ///
  /// In de, this message translates to:
  /// **'Längengrad'**
  String get wertLaenge;
}

class _SyncTexteDelegate extends LocalizationsDelegate<SyncTexte> {
  const _SyncTexteDelegate();

  @override
  Future<SyncTexte> load(Locale locale) {
    return SynchronousFuture<SyncTexte>(lookupSyncTexte(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_SyncTexteDelegate old) => false;
}

SyncTexte lookupSyncTexte(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return SyncTexteDe();
    case 'en':
      return SyncTexteEn();
  }

  throw FlutterError(
    'SyncTexte.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

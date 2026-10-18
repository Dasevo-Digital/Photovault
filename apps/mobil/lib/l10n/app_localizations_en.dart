// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppTexteEn extends AppTexte {
  AppTexteEn([String locale = 'en']) : super(locale);

  @override
  String get appTitel => 'Photo Vault';

  @override
  String get abbrechen => 'Cancel';

  @override
  String get weiter => 'Continue';

  @override
  String get kopieren => 'Copy';

  @override
  String get navZeitleiste => 'Photos';

  @override
  String get navSuche => 'Search';

  @override
  String get navAlben => 'Albums';

  @override
  String get navPersonen => 'People';

  @override
  String get navKarte => 'Map';

  @override
  String get navBibliothek => 'Library';

  @override
  String get bibFavoriten => 'Favorites';

  @override
  String get bibPapierkorb => 'Trash';

  @override
  String get bibAlle => 'All';

  @override
  String get bibFavoritenLeer => 'No favorites yet.';

  @override
  String get bibPapierkorbLeer => 'The trash is empty.';

  @override
  String get bibPapierkorbHinweis =>
      'Restore here; delete permanently on the computer.';

  @override
  String get zeitleisteLeer =>
      'No photos yet. Whatever reaches the server appears here.';

  @override
  String get albenLeer => 'No albums yet.';

  @override
  String get personenLeer =>
      'No named people yet. People are named on the computer.';

  @override
  String get karteLeer => 'No photos with a location yet.';

  @override
  String karteFotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get abgemeldetHinweis =>
      'This phone was signed out on the server. Sign out under “Account” and connect again.';

  @override
  String offline(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Server unreachable – $n changes waiting',
      one: 'Server unreachable – 1 change waiting',
    );
    return '$_temp0';
  }

  @override
  String get sucheInhalt => 'Content';

  @override
  String get sucheText => 'Text';

  @override
  String get sucheHinweisInhalt => 'e.g. beach at sunset';

  @override
  String get sucheHinweisText => 'File name, description, recognised text …';

  @override
  String get sucheKeinModell =>
      'The server cannot search by content (no model). Showing the text search instead.';

  @override
  String get sucheFehler => 'The search did not work.';

  @override
  String get sucheNichts => 'Nothing found.';

  @override
  String get betrachterFavorit => 'Favorite';

  @override
  String get betrachterTeilen => 'Share';

  @override
  String get betrachterAngaben => 'Details';

  @override
  String get betrachterPapierkorb => 'Move to trash';

  @override
  String get betrachterPapierkorbTitel => 'Move to trash?';

  @override
  String get betrachterPapierkorbText =>
      'The item disappears everywhere – on the computer too. It can be restored from the trash on the computer.';

  @override
  String get betrachterLaedtOriginal => 'Loading the original …';

  @override
  String get betrachterNichtGeladen =>
      'Could not be loaded – is the server reachable?';

  @override
  String get betrachterBeschreibungKi => 'Description by image recognition';

  @override
  String get kontoTitel => 'Account';

  @override
  String kontoKontoGeraet(String konto, String geraet) {
    return 'Account $konto · device $geraet';
  }

  @override
  String get kontoVerbindet => 'Connecting …';

  @override
  String get kontoAbgeglichen => 'In sync';

  @override
  String serverSicherungStand(String wann) {
    return 'Server backup: last $wann';
  }

  @override
  String get serverSicherungWarnung =>
      'The server backup needs attention – on the computer under Settings → Server.';

  @override
  String get serverSicherungOffen =>
      'The server backup is not set up yet – on the computer under Settings → Server.';

  @override
  String speicherStand(String frei, String gesamt) {
    return 'Storage on the server: $frei free of $gesamt';
  }

  @override
  String speicherKnapp(String frei) {
    return 'The server is running low on storage: $frei left.';
  }

  @override
  String get speicherVoll =>
      'The server storage is full. It accepts new photos again once space is freed.';

  @override
  String kontoSendet(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n changes going to the server',
      one: '1 change going to the server',
    );
    return '$_temp0';
  }

  @override
  String get kontoAbmelden => 'Sign out';

  @override
  String get kontoAbmeldenHinweis =>
      'Deletes the copy on this phone; everything stays on the server.';

  @override
  String get kontoAbmeldenTitel => 'Sign out?';

  @override
  String get kontoAbmeldenText =>
      'The phone signs out of the server and deletes its copy of the library with all downloaded images. Changes still waiting are lost.';

  @override
  String get geraetVorgabe => 'Phone';

  @override
  String get anmeldenTitel => 'Connect to server';

  @override
  String get anmeldenErklaerung =>
      'Photo Vault on the phone shows the library of your Photo Vault server – with timeline, search, albums, people and map, even offline.';

  @override
  String get anmeldenAdresse => 'Server address';

  @override
  String get anmeldenAdresseHinweis => 'e.g. photos.example.com';

  @override
  String get anmeldenName => 'Name';

  @override
  String get anmeldenPasswort => 'Password';

  @override
  String get anmeldenGeraet => 'Name of this phone';

  @override
  String get anmeldenAnmelden => 'Sign in';

  @override
  String get anmeldenNichtErreichbar => 'No server responds at this address.';

  @override
  String get anmeldenKeinServer =>
      'No Photo Vault server of a matching version responds there.';

  @override
  String get anmeldenNurHttps =>
      'Unencrypted (http://) only on your own network – please use https:// for an address on the internet.';

  @override
  String get anmeldenFalsch => 'Name, password or code is wrong.';

  @override
  String anmeldenGebremst(int sekunden) {
    return 'Too many failed attempts – please try again in $sekunden seconds.';
  }

  @override
  String get anmeldenCodeTitel => 'Code from the authenticator app';

  @override
  String get anmeldenCodeHinweis =>
      'Six digits – or one of the recovery codes.';

  @override
  String get anmeldenBestaetigen => 'Confirm';

  @override
  String get anmeldenTotpTitel => 'Set up two-factor sign-in';

  @override
  String get anmeldenTotpText =>
      'Add the secret to your authenticator app – with the button or by typing it – and then enter the first code.';

  @override
  String get anmeldenTotpOeffnen => 'Open in authenticator app';

  @override
  String get anmeldenCodesTitel => 'Recovery codes';

  @override
  String get anmeldenCodesText =>
      'Each code works once if the phone with the authenticator app is missing. Store them safely now – they will not be shown again.';

  @override
  String get anmeldenLaedt => 'Loading the library from the server …';

  @override
  String get anmeldenErstesTitel => 'Create the first account';

  @override
  String anmeldenErstesText(String name) {
    return 'This server has no account yet. The first one will be created with the name “$name” and the password you just entered. It becomes the administrator and can add more accounts later.';
  }

  @override
  String get anmeldenPasswortWiederholen => 'Repeat password';

  @override
  String get anmeldenErstesAnlegen => 'Create account and sign in';

  @override
  String get anmeldenPasswortUngleich => 'The two passwords do not match.';

  @override
  String anmeldenPasswortZuKurz(int n) {
    return 'The password needs at least $n characters.';
  }

  @override
  String get anmeldenNameUngueltig =>
      'The name needs 2 to 40 letters, digits, dots, hyphens or underscores.';

  @override
  String get anmeldenErstesNurHeimnetz =>
      'The first account can only be created from the home network, not through access from outside.';

  @override
  String get anmeldenSchonEingerichtet =>
      'The server already has an account now. Please sign in with it.';

  @override
  String get fehlerAllgemein => 'That did not work.';

  @override
  String get speichern => 'Save';

  @override
  String get entfernen => 'Remove';

  @override
  String get kontenVerwalten => 'Manage accounts';

  @override
  String get kontenVerwaltenHinweis =>
      'Add accounts for the family, set new passwords';

  @override
  String get kontenTitel => 'Accounts on the server';

  @override
  String get kontoAnlegen => 'Add account';

  @override
  String get kontoVerwalter => 'Administrator';

  @override
  String get kontoAlsVerwalter => 'May also manage accounts';

  @override
  String kontoGeraete(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices',
      one: '1 device',
      zero: 'no device',
    );
    return '$_temp0';
  }

  @override
  String get kontoMitTotp => 'with TOTP';

  @override
  String get kontoOhneTotp => 'without TOTP';

  @override
  String get kontoGesperrt => 'locked after failed attempts';

  @override
  String get kontoDu => 'your account';

  @override
  String get kontoPasswortSetzen => 'Set new password';

  @override
  String kontoPasswortSetzenText(String name) {
    return 'All devices of “$name” will be signed out.';
  }

  @override
  String get kontoTotpZuruecksetzen => 'Reset TOTP';

  @override
  String kontoTotpZurueckgesetzt(String name) {
    return '“$name” will set up TOTP again at the next sign-in.';
  }

  @override
  String get kontoEntsperren => 'Unlock';

  @override
  String kontoEntfernenTitel(String name) {
    return 'Remove “$name”?';
  }

  @override
  String get kontoEntfernenText =>
      'The account and its devices will be removed. The library with all its photos stays on the server: it is set aside, not deleted, and can only be deleted there by hand.';

  @override
  String get kontoErledigt => 'Done.';

  @override
  String get sicherungTitel => 'Back up camera roll';

  @override
  String get sicherungAn => 'Back up photos from this phone';

  @override
  String get sicherungAnHinweis =>
      'New photos and videos go to the server on their own – even when the app is not open.';

  @override
  String get sicherungAus => 'Off';

  @override
  String get sicherungLaeuft => 'Backing up …';

  @override
  String get sicherungVideos => 'Back up videos';

  @override
  String get sicherungNurWlan => 'Wi-Fi only';

  @override
  String get sicherungNurBeimLaden => 'In the background only while charging';

  @override
  String get sicherungAlben => 'Albums';

  @override
  String get sicherungAlleFotos => 'All photos';

  @override
  String sicherungAlbenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n albums',
      one: '1 album',
    );
    return '$_temp0';
  }

  @override
  String get sicherungHinweisIos =>
      'While the app is open, it backs up right away. In the background, iOS lets it work when it sees fit – usually at night while charging.';

  @override
  String get sicherungHinweisAndroid =>
      'While the app is open, it backs up right away; in the background it checks every 15 minutes. Whatever is still missing when you leave the app continues to upload with a notification.';

  @override
  String get sicherungKeinZugriff => 'No access to photos';

  @override
  String get sicherungKeinZugriffHinweis =>
      'Allow it in the phone\'s settings.';

  @override
  String get sicherungEinstellungenOeffnen => 'Settings';

  @override
  String get sicherungTeilweise => 'Only selected photos shared';

  @override
  String get sicherungTeilweiseHinweis =>
      'Only what the app may see is backed up.';

  @override
  String get sicherungAuswahlAendern => 'Change selection';

  @override
  String get sicherungWartetWlan => 'Waiting for Wi-Fi';

  @override
  String get sicherungWartetNetz => 'Waiting for a connection';

  @override
  String get sicherungImHintergrund =>
      'The backup is running in the background.';

  @override
  String get sicherungNochNicht => 'Not backed up yet';

  @override
  String sicherungStand(int sicher, int gesamt) {
    return '$sicher of $gesamt backed up';
  }

  @override
  String sicherungLaedt(String datei) {
    return 'Uploading $datei';
  }

  @override
  String sicherungZuletzt(String zeit) {
    return 'Last run: $zeit';
  }

  @override
  String get sicherungFehler =>
      'The server stopped the backup. It will continue with the next run.';

  @override
  String sicherungProbleme(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items could not be backed up',
      one: '1 item could not be backed up',
    );
    return '$_temp0';
  }

  @override
  String get sicherungErneut => 'Try again';

  @override
  String get sicherungJetzt => 'Back up now';

  @override
  String get sicherungBenachrichtigungTitel =>
      'Photo Vault is backing up photos';

  @override
  String get sicherungBenachrichtigungText =>
      'Photos and videos are going to the server.';

  @override
  String get sicherungKanal => 'Backup';

  @override
  String get appZuAlt =>
      'The server is newer than this app – please update the app. Nothing syncs until then.';

  @override
  String get serverZuAlt =>
      'The server is older than this app – please update the server. Nothing syncs until then.';

  @override
  String auswahlAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get auswahlAufheben => 'Clear selection';

  @override
  String get auswahlZurueckholen => 'Restore';

  @override
  String get auswahlTagWaehlen => 'Select all from this day';

  @override
  String get auswahlTagAbwaehlen => 'Deselect this day';

  @override
  String get auswahlFavorit => 'Favorite';

  @override
  String get auswahlTeilen => 'Share';

  @override
  String get auswahlHerunterladen => 'To phone';

  @override
  String get auswahlPapierkorb => 'Trash';

  @override
  String auswahlPapierkorbTitel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Move $n photos to the trash?',
      one: 'Move this photo to the trash?',
    );
    return '$_temp0';
  }

  @override
  String get auswahlPapierkorbText =>
      'They disappear everywhere – on the computer too. They can be restored from the trash on the computer.';

  @override
  String get auswahlAlbumTitel => 'Add to album';

  @override
  String get auswahlAlbumNeu => 'New album';

  @override
  String get auswahlAlbumName => 'Album name';

  @override
  String get auswahlAlbumAnlegen => 'Create';

  @override
  String auswahlImAlbum(int n, String album) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos in album “$album”',
      one: '1 photo in album “$album”',
    );
    return '$_temp0';
  }

  @override
  String get auswahlLaedt => 'Loading the originals …';

  @override
  String auswahlGespeichert(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos saved to this phone',
      one: '1 photo saved to this phone',
    );
    return '$_temp0';
  }

  @override
  String get auswahlKeinZugriff =>
      'No access to the photo library – allow it in the phone\'s settings.';

  @override
  String get kontoZwischenspeicher => 'Cache on this phone';

  @override
  String kontoZwischenspeicherStand(String belegt, String grenze) {
    return '$belegt of $grenze – previews and originals you have viewed. Tap to set the limit.';
  }

  @override
  String kontoZwischenspeicherOhneGrenzeStand(String belegt) {
    return '$belegt, no limit – previews and originals you have viewed. Tap to set the limit.';
  }

  @override
  String get kontoZwischenspeicherLeeren => 'Clear';

  @override
  String get kontoZwischenspeicherGrenze => 'Use at most';

  @override
  String get kontoZwischenspeicherOhneGrenze => 'No limit';

  @override
  String get erinnerungenTitel => 'Memories';

  @override
  String erinnerungenVorJahren(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String erinnerungenMonatVorJahren(String monat, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years ago',
      one: '1 year ago',
    );
    return '$monat $_temp0';
  }

  @override
  String erinnerungenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get sicherungFreigeben => 'Free up space';

  @override
  String get sicherungFreigebenHinweis =>
      'Delete backed-up photos from this phone – they stay on the server.';

  @override
  String get sicherungFreigebenSucht => 'Looking for backed-up photos …';

  @override
  String get sicherungFreigebenNichts =>
      'Nothing to free up: what is on the server is already off the phone – or not backed up yet.';

  @override
  String sicherungFreigebenTitel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Delete $n photos from this phone?',
      one: 'Delete 1 photo from this phone?',
    );
    return '$_temp0';
  }

  @override
  String get sicherungFreigebenText =>
      'Only photos that are unchanged and safely on the server. The phone will ask once more.';

  @override
  String get sicherungFreigebenLoeschen => 'Delete';

  @override
  String sicherungFreigegeben(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos deleted from this phone',
      one: '1 photo deleted from this phone',
      zero: 'Nothing deleted',
    );
    return '$_temp0';
  }

  @override
  String get lokalNochNichtGesichert =>
      'Only on this phone – not on the server yet';

  @override
  String get lokalJetztSichern => 'Back up now';

  @override
  String lokalAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos only on this phone',
      one: '1 photo only on this phone',
    );
    return '$_temp0';
  }

  @override
  String get kontoFassung => 'Version';

  @override
  String kontoFassungText(String app, String server) {
    return 'App $app · server $server';
  }

  @override
  String get bibReisen => 'Trips';

  @override
  String get reisenLeer => 'No trips yet.';

  @override
  String get aktivitaetenTitel => 'Activities';

  @override
  String get aktivitaetenLeer => 'No activities yet.';

  @override
  String anzahlAufnahmen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String gehoertZu(String reise) {
    return 'Part of: $reise';
  }

  @override
  String ortWeitere(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n more places',
      one: 'one more place',
    );
    return '$_temp0';
  }

  @override
  String dauerMinuten(int m) {
    return '$m min';
  }

  @override
  String dauerStunden(int h, int m) {
    return '$h h $m min';
  }

  @override
  String streckeKm(String km) {
    return '$km km';
  }

  @override
  String get keineRoute => 'Too few located photos for a route.';

  @override
  String get aktArtSpaziergang => 'Walk';

  @override
  String get aktArtWanderung => 'Hike';

  @override
  String get aktArtRadtour => 'Bike ride';

  @override
  String get aktArtAusflug => 'Outing';

  @override
  String get aktArtBesichtigung => 'Sightseeing';

  @override
  String get aktArtBootsfahrt => 'Boat trip';

  @override
  String get aktArtSonstiges => 'Other';

  @override
  String get angabenTitel => 'Details';

  @override
  String get angabenDatumGeschaetzt => 'Date estimated';

  @override
  String get angabenBearbeitet => 'edited';

  @override
  String get angabenStandortBekannt => 'Location known';

  @override
  String get angabenGeerbt => 'taken from a neighbouring photo';

  @override
  String get angabenBeschreibung => 'Description';

  @override
  String get angabenSpeichern => 'Save';

  @override
  String get angabenGespeichert => 'Saved';

  @override
  String angabenAutomatisch(String text) {
    return 'Automatic: $text';
  }

  @override
  String angabenSterne(int i) {
    return '$i of 5';
  }

  @override
  String angabenSerie(int n) {
    return 'Stack with $n items';
  }

  @override
  String get angabenText => 'Recognized text';

  @override
  String get angabenTranskript => 'Transcript';

  @override
  String angabenImportiert(String datum) {
    return 'Imported $datum';
  }

  @override
  String angabenSerieTitel(int n) {
    return 'Stack · $n items';
  }

  @override
  String get bibStatistik => 'Statistics';

  @override
  String get statLeer => 'No photos or videos in the library yet.';

  @override
  String get statInsgesamt => 'Total items';

  @override
  String get statFotos => 'Photos';

  @override
  String get statVideos => 'Videos';

  @override
  String get statFavoriten => 'Favorites';

  @override
  String get statSpeicher => 'Storage';

  @override
  String get statPapierkorb => 'In the trash';

  @override
  String get statGesperrt => 'Locked folder';

  @override
  String get statProJahr => 'Photos & videos per year';

  @override
  String get statProMonat => 'Seasonality – items per month';

  @override
  String get statKameras => 'Most used cameras';

  @override
  String get bibDuplikate => 'Duplicates';

  @override
  String get duplAehnlichkeit => 'Similarity';

  @override
  String get duplSuchen => 'Search';

  @override
  String get duplSucht => 'Searching …';

  @override
  String duplAlle(int n) {
    return '$n copies to the trash';
  }

  @override
  String get duplKeineEinbettungen =>
      'No image embeddings yet – the analysis on the server has to run first.';

  @override
  String duplKeine(String p) {
    return 'No duplicates at $p similarity.';
  }

  @override
  String duplAusnahmen(int n) {
    return '$n pairs are excluded.';
  }

  @override
  String duplGruppen(int n, String p) {
    return '$n groups at $p similarity. The outlined photo would be kept when cleaning up; groups with several favorites or ratings stay untouched.';
  }

  @override
  String get duplKeineDuplikate => 'Not duplicates';

  @override
  String duplNurVonHand(int n) {
    return '$n items · several marked, by hand only';
  }

  @override
  String get duplBehalten => 'Keep';

  @override
  String duplBehaltenEine(String name) {
    return 'Keep “$name” and move the other item to the trash?';
  }

  @override
  String duplBehaltenMehrere(String name, int n) {
    return 'Keep “$name” and move the $n others to the trash?';
  }

  @override
  String duplAlleFrage(int n, int g) {
    return 'Move $n copies from $g groups to the trash? In each group the outlined photo stays.';
  }

  @override
  String get bibEinstellungen => 'Settings';

  @override
  String get einstTitel => 'Library settings';

  @override
  String get einstHinweis =>
      'These settings are stored in the library and apply to all connected devices.';

  @override
  String get einstSprache => 'Language of this app';

  @override
  String get einstSpracheHinweis => 'Applies to this phone only.';

  @override
  String get einstAutomatisch => 'Automatic';

  @override
  String get einstGespeichert => 'Saved.';

  @override
  String get einstNach => 'after';

  @override
  String get einstTagen => 'days';

  @override
  String einstAb(String p) {
    return 'from $p';
  }

  @override
  String get einstPapierkorb => 'Empty trash automatically';

  @override
  String get einstPapierkorbText =>
      'Permanently deletes items in the trash after the period – irreversibly.';

  @override
  String get einstVorschlaege => 'Accept confident suggestions automatically';

  @override
  String get einstVorschlaegeText =>
      'Detected faces that are very similar to a person are assigned without asking.';

  @override
  String get einstAuswerten => 'Run AI analysis automatically after import';

  @override
  String get einstAuswertenText =>
      'New items are analysed right away: faces, image content, text, keywords.';

  @override
  String get einstUebersetzen => 'Translate search and keywords';

  @override
  String get einstUebersetzenText =>
      'Searches in German and English at once and keeps keywords in both languages.';

  @override
  String get einstSchuetzen => 'Protect private metadata';

  @override
  String get einstSchuetzenText =>
      'Newly locked items also store location, description and text encrypted.';

  @override
  String get einstSchwelle => 'Face recognition threshold';

  @override
  String get einstSchwelleText =>
      'How similar a face must be to be suggested for a person. Higher means more cautious.';

  @override
  String get verwAuswertungRuht => 'Analysis: nothing pending';

  @override
  String verwAuswertungLaeuft(
    String stufe,
    int nr,
    int von,
    int erledigt,
    int gesamt,
  ) {
    return 'Analysis running: $stufe ($nr/$von), $erledigt of $gesamt';
  }

  @override
  String get verwAnstossen => 'Start analysis';

  @override
  String get verwJetztSichern => 'Back up now';

  @override
  String get bibStammbaum => 'Family tree';

  @override
  String get baumPerson => 'Person';

  @override
  String get baumLebensbaum => 'Life tree';

  @override
  String baumOhneVerwandtschaft(String name) {
    return '$name (no relatives)';
  }

  @override
  String get baumKeinePersonen =>
      'No people yet. Add them on the computer under People and Family tree.';

  @override
  String get baumKeineVerwandtschaft =>
      'No relatives are recorded for this person yet – that is done on the computer in the family tree.';

  @override
  String baumVerschwiegen(int n) {
    return '$n households no longer fit in the picture.';
  }
}

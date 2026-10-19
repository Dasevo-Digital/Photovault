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
  String get sucheHinweisText => 'Tag, place, person, description, file name …';

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
  String get betrachterWirdUmgewandelt =>
      'Converting the video for this phone …';

  @override
  String get betrachterLiveAbspielen => 'Play Live Photo';

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
  String get kontoUnterstuetzen => 'Support Photo Vault';

  @override
  String get kontoUnterstuetzenText =>
      'Free and without ads – if you like, buy a coffee on Ko-fi.';

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
  String get bibEntdecken => 'Explore';

  @override
  String get bibVerwalten => 'Manage';

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

  @override
  String get lbStil => 'Style';

  @override
  String get lbPergament => 'Parchment';

  @override
  String get lbLandschaft => 'Landscape';

  @override
  String get lbWappen => 'Heraldic';

  @override
  String get lbGold => 'Gold';

  @override
  String get lbZeigt => 'Shows';

  @override
  String get lbVorfahren => 'Ancestors';

  @override
  String get lbNachkommen => 'Descendants';

  @override
  String get lbPaar => 'Couple';

  @override
  String get lbFamilie => 'Family';

  @override
  String get lbGenerationen => 'Generations';

  @override
  String get lbNachOben => 'Upwards';

  @override
  String get lbNachUnten => 'Downwards';

  @override
  String get lbKreis => 'Circle';

  @override
  String get lbDirekteLinie => 'Direct line';

  @override
  String get lbMitGeschwistern => 'With siblings';

  @override
  String get lbAlle => 'All';

  @override
  String get lbPortraits => 'Portraits';

  @override
  String get lbSpeichern => 'Save as image';

  @override
  String get lbStammbaum => 'Family tree';

  @override
  String get entwTitel => 'Edit';

  @override
  String get entwBelichtung => 'Exposure';

  @override
  String get entwKontrast => 'Contrast';

  @override
  String get entwLichter => 'Highlights';

  @override
  String get entwSchatten => 'Shadows';

  @override
  String get entwTemperatur => 'Temperature';

  @override
  String get entwToenung => 'Tint';

  @override
  String get entwKlarheit => 'Clarity';

  @override
  String get entwSchaerfe => 'Sharpness';

  @override
  String get entwRauschen => 'Noise reduction';

  @override
  String get entwVignette => 'Vignette';

  @override
  String get entwAutoWeiss => 'Automatic white balance';

  @override
  String get entwVorher => 'Before';

  @override
  String get entwZuruecksetzen => 'Reset sliders';

  @override
  String get entwEntfernen => 'Remove edits';

  @override
  String get entwVorschauQuelle =>
      'RAW or HEIC: the phone works from the preview (at most 2048 pixels). The computer edits at full size.';

  @override
  String get entwVomRechner =>
      'Tone curve, color mixer and look from the computer apply and are kept.';

  @override
  String entwRechne(int b, int h) {
    return 'Rendering at full size ($b × $h) …';
  }

  @override
  String get entwLaedtHoch => 'Uploading …';

  @override
  String get entwGespeichert => 'Saved.';

  @override
  String get entwVerwerfen => 'Discard changes?';

  @override
  String get entwEntfernenFrage => 'Remove the edits and show the original?';

  @override
  String get entwNichtGeladen => 'The image could not be loaded.';

  @override
  String get entwSpeichern => 'Save';

  @override
  String get eigenGeraete => 'Devices';

  @override
  String get eigenDiesesTelefon => '(this phone)';

  @override
  String eigenZuletzt(String datum) {
    return 'last $datum';
  }

  @override
  String get eigenGeraetAbmelden => 'Sign out device';

  @override
  String eigenGeraetAbmeldenFrage(String name) {
    return 'Sign out “$name”?';
  }

  @override
  String get eigenPasswortAendern => 'Change password';

  @override
  String get eigenPasswortAlt => 'Current password';

  @override
  String get eigenPasswortNeu => 'New password';

  @override
  String get eigenPasswortNochmal => 'Repeat';

  @override
  String get eigenTotpCode => 'TOTP code';

  @override
  String get eigenAndereAbmelden => 'Sign out other devices';

  @override
  String get eigenAendern => 'Change';

  @override
  String get eigenPasswortUngleich => 'The new passwords do not match.';

  @override
  String get eigenPasswortGeaendert => 'Password changed.';

  @override
  String get eigenTotpEingerichtet => 'TOTP set up';

  @override
  String get gesichterOhneNamen => 'Unnamed';

  @override
  String gesichterAnzahl(int n) {
    return '$n faces';
  }

  @override
  String gesichterVorschlagFrage(String name) {
    return '$name?';
  }

  @override
  String get gesichterWerIstDas => 'Who is this?';

  @override
  String gesichterAehnliche(int n) {
    return '$n similar faces';
  }

  @override
  String gesichterDasIst(String name) {
    return 'This is $name';
  }

  @override
  String get gesichterHinweis =>
      'Tap a face to leave it out if it does not belong.';

  @override
  String get gesichterName => 'Name';

  @override
  String get gesichterNamePlatzhalter => 'New or existing person';

  @override
  String get gesichterNameFehlt => 'Please enter a name.';

  @override
  String get gesichterBenennen => 'Name';

  @override
  String get gesichterBeiseite => 'Set aside';

  @override
  String get gesichterLoesen => 'Remove name';

  @override
  String get gesichterKeinGesicht => 'No face selected.';

  @override
  String get gesichterAntippen => 'Tap to name or change';

  @override
  String get gesichterWeitereFinden => 'Find more photos';

  @override
  String gesichterVorschlaegeFuer(String name) {
    return 'Suggestions for $name';
  }

  @override
  String get gesichterVorschlagHinweis =>
      'Everything is selected. Deselect what is wrong – recognition learns from that too: a rejection raises the threshold for this person.';

  @override
  String get gesichterAlleWaehlen => 'Select all';

  @override
  String get gesichterKeineWaehlen => 'Select none';

  @override
  String gesichterZuordnenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Assign $n faces',
      one: 'Assign one face',
      zero: 'Nothing selected',
    );
    return '$_temp0';
  }

  @override
  String gesichterNichtsGefunden(String schwelle) {
    return 'No unnamed face is above this person’s threshold of $schwelle.';
  }

  @override
  String gesichterUebernommen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos added.',
      one: 'One photo added.',
      zero: 'Nothing added – the feedback was saved anyway.',
    );
    return '$_temp0';
  }

  @override
  String get linkGaesteHochladen => 'Guests may add photos and videos';

  @override
  String get linkGaesteHinweis =>
      'Every file is checked in isolation and rewritten. It only goes into the album once you accept it.';

  @override
  String get linkGaesteDuerfen => 'Guests may add';

  @override
  String linkBeitraegeOffen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n contributions pending',
      one: '1 contribution pending',
    );
    return '$_temp0';
  }

  @override
  String get beitraegeTitel => 'Contributions from guests';

  @override
  String get beitraegeAlleAnnehmen => 'Accept all';

  @override
  String get beitraegeAbgeschottet =>
      'Every file was checked in a separate process without network access and rewritten – keeping capture time, location and camera, nothing else.';

  @override
  String get beitraegeMitNetz =>
      'Every file was checked in a separate process and rewritten. This system does not allow blocking network access.';

  @override
  String beitraegeVon(String name) {
    return 'from $name';
  }

  @override
  String get beitraegeInPruefung => 'being checked …';

  @override
  String get beitraegeAnnehmen => 'Accept';

  @override
  String get beitraegeAblehnen => 'Reject';

  @override
  String get beitraegeEntfernen => 'Remove';

  @override
  String beitraegeAngenommen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n contributions accepted',
      one: 'Contribution accepted',
    );
    return '$_temp0';
  }

  @override
  String get diashow => 'Slideshow';

  @override
  String get diashowAbHier => 'Slideshow from here';

  @override
  String get diashowKeineFotos =>
      'There are no photos for a slideshow here – videos are left out.';

  @override
  String get diashowVorige => 'Previous';

  @override
  String get diashowNaechste => 'Next';

  @override
  String get diashowAnhalten => 'Pause';

  @override
  String get diashowWeiter => 'Continue';

  @override
  String get diashowBeenden => 'End slideshow';

  @override
  String get betrachterMehr => 'More';

  @override
  String get bibOrte => 'Places';

  @override
  String get orteLeer =>
      'No places yet. They appear once photos carry a location and the place data is set up.';

  @override
  String orteAnzahlOrte(int n) {
    return '$n places';
  }

  @override
  String orteAufnahmen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get personZusammenfuehren => 'Merge';

  @override
  String personZusammenfuehrenTitel(String name) {
    return 'Merge into “$name”';
  }

  @override
  String get personZusammenfuehrenText =>
      'The chosen person is merged into this one: their faces, photos and relationships move here, and their name disappears.';

  @override
  String personZusammenfuehrenFrage(String andere, String name) {
    return 'Merge “$andere” into “$name”? This cannot be undone.';
  }

  @override
  String get sucheFilter => 'Filters';

  @override
  String get sucheFilterPersonen => 'People';

  @override
  String get sucheFilterOrt => 'Place';

  @override
  String get sucheFilterAlleLaender => 'All countries';

  @override
  String get sucheFilterAlleStaedte => 'All cities';

  @override
  String get sucheFilterZeitraum => 'Period';

  @override
  String get sucheFilterVon => 'From';

  @override
  String get sucheFilterBis => 'To';

  @override
  String get sucheFilterArt => 'Type';

  @override
  String get sucheFilterAlles => 'All';

  @override
  String get sucheFilterFotos => 'Photos';

  @override
  String get sucheFilterVideos => 'Videos';

  @override
  String get sucheFilterKamera => 'Camera';

  @override
  String get sucheFilterAlleKameras => 'All cameras';

  @override
  String get sucheFilterFavoriten => 'Favorites only';

  @override
  String get sucheFilterZuruecksetzen => 'Reset';

  @override
  String get sucheFilterAnwenden => 'Apply';

  @override
  String sucheFilterZeile(String text) {
    return 'Filters: $text';
  }

  @override
  String get sucheTextOderFilter => 'Enter a search term or choose a filter.';

  @override
  String get linkTitel => 'Share as link';

  @override
  String get linkFeldTitel => 'Title';

  @override
  String get linkGueltig => 'Valid';

  @override
  String get linkTag1 => '1 day';

  @override
  String linkTage(int n) {
    return '$n days';
  }

  @override
  String get linkJahr1 => '1 year';

  @override
  String get linkUnbegrenzt => 'Unlimited';

  @override
  String get linkPasswort => 'Password (leave empty for none)';

  @override
  String get linkHerunterladen => 'Allow downloading originals';

  @override
  String get linkOhneMetadaten =>
      'Images are shown without location and camera details. Originals contain them.';

  @override
  String get linkErstellen => 'Create link';

  @override
  String get linkWerHatSieht => 'Anyone with this link can see the photos:';

  @override
  String get linkNurHeimnetz =>
      'This address only works in the home network. From outside, the link goes via the server’s public address.';

  @override
  String get linkKopieren => 'Copy';

  @override
  String get linkTeilen => 'Share';

  @override
  String get linkKopiert => 'Link copied';

  @override
  String get linkTitelFehlt => 'Please enter a title.';

  @override
  String get linkPasswortKurz => 'The password needs at least 4 characters.';

  @override
  String get linkOhneServer =>
      'Without a connection to the server there is no link.';

  @override
  String get linkGeteilte => 'Shared links';

  @override
  String get linkNochNichts => 'Nothing shared yet.';

  @override
  String linkAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get linkAbgelaufen => 'expired';

  @override
  String linkBis(String datum) {
    return 'until $datum';
  }

  @override
  String get linkMitPasswort => 'with password';

  @override
  String linkAufrufe(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n views',
      one: '1 view',
    );
    return '$_temp0';
  }

  @override
  String get linkLoeschen => 'Delete';

  @override
  String linkLoeschenFrage(String titel) {
    return 'Delete the link “$titel”? Anyone who has it will see nothing afterwards.';
  }

  @override
  String get auswahlLink => 'Link';

  @override
  String get albumAlsLink => 'Share as link';

  @override
  String get spurTitel => 'Recorded track';

  @override
  String spurKennzahlen(String km, int auf, int ab) {
    return '$km km · ▲ $auf m · ▼ $ab m';
  }

  @override
  String spurKennzahlenOhneHoehe(String km) {
    return '$km km · no elevation data';
  }

  @override
  String spurPunkte(int anzahl) {
    return '$anzahl points';
  }

  @override
  String get spurHoehenprofil => 'Elevation profile';

  @override
  String get spurOhneHoehen =>
      'This file carries no elevations – without them there is no profile.';

  @override
  String spurProfilBeschreibung(String km, int tief, int hoch, int auf) {
    return 'Elevation profile over $km km, from $tief to $hoch metres, $auf metres of ascent.';
  }

  @override
  String get gelaendeOeffnen => 'Show terrain';

  @override
  String get gelaendeVideoErstellen => 'Create video';
}

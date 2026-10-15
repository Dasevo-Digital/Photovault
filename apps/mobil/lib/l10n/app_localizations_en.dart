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
}

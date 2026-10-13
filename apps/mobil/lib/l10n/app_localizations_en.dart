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
}

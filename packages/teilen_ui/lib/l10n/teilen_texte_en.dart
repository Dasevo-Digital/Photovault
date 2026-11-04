// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'teilen_texte.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class TeilenTexteEn extends TeilenTexte {
  TeilenTexteEn([String locale = 'en']) : super(locale);

  @override
  String get geteiltMitMir => 'Shared with me';

  @override
  String geteiltVon(String name) {
    return 'by $name';
  }

  @override
  String geteiltAlbumVon(String name) {
    return 'Shared by $name';
  }

  @override
  String geteiltBeigetragenVon(String name) {
    return 'Contributed by $name';
  }

  @override
  String get geteiltHinzufuegen => 'Add photos';

  @override
  String get geteiltVerlassen => 'Stop showing';

  @override
  String geteiltVerlassenFrage(String name, String besitzer) {
    return 'Stop showing “$name”? The photos stay with $besitzer; only $besitzer can share it again.';
  }

  @override
  String get geteiltNichtMehr => 'This album is no longer shared with you.';

  @override
  String geteiltLaedtHoch(int i, int n) {
    return 'Uploading $i of $n …';
  }

  @override
  String geteiltHinzugefuegt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n items added',
      one: '1 item added',
    );
    return '$_temp0';
  }

  @override
  String get geteiltNurAnsehen => 'You can no longer add to this album.';

  @override
  String get geteiltSpeicherVoll => 'The server storage is full.';

  @override
  String geteiltFehler(String name) {
    return '“$name” failed.';
  }

  @override
  String get geteiltOffline => 'The server cannot be reached right now.';

  @override
  String get geteiltLeer => 'The album is empty.';

  @override
  String get geteiltEntfernen => 'Remove from album';

  @override
  String geteiltEntfernenFrage(String name) {
    return 'Remove your contribution “$name” from the album? If it is in no other album, it goes to the owner\'s trash.';
  }

  @override
  String get geteiltEntfernt => 'Removed from the album';

  @override
  String get kontenTeilen => 'Share with accounts';

  @override
  String kontenTeilenTitel(String titel) {
    return 'Share “$titel” with accounts';
  }

  @override
  String get kontenTeilenHinweis =>
      'Other accounts on this server see the album under “Shared with me” – in the browser and on the phone.';

  @override
  String get kontenBeitragenHinweis =>
      'Anyone allowed to contribute adds photos and videos directly to this album. They go into your library.';

  @override
  String get kontenAnsehen => 'View';

  @override
  String get kontenBeitragen => 'Contribute';

  @override
  String get kontenNiemand => 'Not shared with anyone.';

  @override
  String get kontenKeineAnderen => 'There is no other account on this server.';

  @override
  String get kontenTeilenKnopf => 'Share';

  @override
  String get abbrechen => 'Cancel';

  @override
  String get entfernen => 'Remove';

  @override
  String get schliessen => 'Close';

  @override
  String get neueBeitraegeTitel => 'New in your shared albums';

  @override
  String neueBeitraegeAlbum(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '“$name”: $n new items',
      one: '“$name”: 1 new item',
    );
    return '$_temp0';
  }

  @override
  String neueBeitraegeVon(String namen) {
    return 'from $namen';
  }

  @override
  String partnerBibliothekVon(String name) {
    return 'Library of $name';
  }

  @override
  String get partnerGanzeBibliothek => 'Whole library';

  @override
  String get partnerNichtMehr => 'This library is no longer shared with you.';

  @override
  String partnerVerlassenFrage(String name) {
    return 'Stop showing the library of $name? Only $name can share it again.';
  }

  @override
  String get bibliothekTeilen => 'Share library';

  @override
  String get bibliothekTeilenTitel => 'Share library';

  @override
  String get bibliothekTeilenHinweis =>
      'Accounts listed here see your whole library under “Shared with me” – without locked items and trash, view only.';
}

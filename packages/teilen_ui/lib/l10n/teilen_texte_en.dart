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
      'Accounts listed here see your library under “Shared with me” – all of it, or only from a date on and with certain people; without locked items and trash, view only.';

  @override
  String get kommentare => 'Comments';

  @override
  String get kommentarSchreiben => 'Write a comment …';

  @override
  String get kommentarSenden => 'Send';

  @override
  String get kommentarEntfernen => 'Remove comment';

  @override
  String get kommentarEntfernenFrage => 'Remove this comment?';

  @override
  String get kommentareKeine => 'No comments yet.';

  @override
  String get kommentarZuFoto => 'on a photo';

  @override
  String get kommentarFehler => 'That did not work. Please try again later.';

  @override
  String get kommentareHinweis =>
      'Everyone the album is shared with sees the comments.';

  @override
  String get gefaelltMir => 'Like';

  @override
  String gefaelltNamen(String namen) {
    return 'Liked by $namen';
  }

  @override
  String get speichern => 'Save';

  @override
  String get automatischFuellen => 'Fill automatically';

  @override
  String automatischTitel(String name) {
    return 'Fill “$name” automatically';
  }

  @override
  String get automatischHinweis =>
      'Photos of the chosen people go into this album by themselves – also ones on which they are recognized only later. What you take out stays out.';

  @override
  String get automatischAus => 'Stop filling automatically';

  @override
  String get automatischAusGemacht =>
      'The album no longer fills itself. What is in it stays.';

  @override
  String automatischDazu(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Added $n items',
      one: 'Added one item',
      zero: 'Nothing new added',
    );
    return '$_temp0';
  }

  @override
  String get regelEine => 'One of them';

  @override
  String get regelAlle => 'All together';

  @override
  String get regelMindestensEine => 'Choose at least one person.';

  @override
  String get regelHoechstens => 'At most 20 people.';

  @override
  String regelPersonenFehlen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n chosen people no longer exist.',
      one: 'One chosen person no longer exists.',
    );
    return '$_temp0';
  }

  @override
  String regelMit(String namen) {
    return 'with $namen';
  }

  @override
  String regelZusammen(String namen) {
    return '$namen together';
  }

  @override
  String regelAb(String tag) {
    return 'from $tag';
  }

  @override
  String get aufgenommenAb => 'Taken from';

  @override
  String get jedesDatum => 'any date';

  @override
  String get personSuchen => 'Search person';

  @override
  String get keinePersonGefunden => 'No person found.';

  @override
  String get keinePersonenMitNamen => 'No named people yet.';

  @override
  String get partnerEinschraenken => 'Restrict';

  @override
  String partnerWasSieht(String name) {
    return 'What $name sees';
  }

  @override
  String partnerEinschraenkenHinweis(String name) {
    return 'Without a choice, $name sees your whole library. With people, only photos showing at least one of them – for every file, not just the list.';
  }

  @override
  String get partnerGanz => 'The whole library';

  @override
  String get partnerInZeitleiste => 'Show in my timeline';

  @override
  String get partnerInZeitleisteFern =>
      'Show in the timeline (phone and browser)';

  @override
  String get partnerEingeschraenkt => 'Only part of the library';

  @override
  String get nachlass => 'Legacy contact';

  @override
  String get nachlassHinweis =>
      'A legacy contact can request access to your library – for instance if something happens to you. If you do not object within the waiting period, they then see your whole library under “Shared with me”, to view and download only. The request shows in the browser, on the phone and on the computer.';

  @override
  String get nachlassMeine => 'Your legacy contacts';

  @override
  String get nachlassFuerMich => 'You are the legacy contact for';

  @override
  String get nachlassKeine => 'Nobody named yet.';

  @override
  String get nachlassBenennen => 'Name';

  @override
  String get nachlassAblehnen => 'Decline';

  @override
  String get nachlassVerlangen => 'Request access';

  @override
  String get nachlassZurueckziehen => 'Withdraw request';

  @override
  String nachlassFristTage(int n) {
    return '$n days waiting period';
  }

  @override
  String nachlassOffen(String tag) {
    return 'requests access – granted on $tag unless you object';
  }

  @override
  String nachlassHatZugang(String tag) {
    return 'has access since $tag';
  }

  @override
  String nachlassDuHastZugang(String tag) {
    return 'Access since $tag – under “Shared with me”';
  }

  @override
  String nachlassVerlangenFrage(String name, int tage) {
    return 'Request access to the library of $name? $name sees the request and can object for $tage days. After that you see the whole library, to view and download only.';
  }

  @override
  String nachlassAnfrage(String name, String tag) {
    return '$name requests access to your library (legacy contact). Unless you object, $name gets it on $tag.';
  }
}

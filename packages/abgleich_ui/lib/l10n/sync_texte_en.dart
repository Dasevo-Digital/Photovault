// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'sync_texte.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class SyncTexteEn extends SyncTexte {
  SyncTexteEn([String locale = 'en']) : super(locale);

  @override
  String get titel => 'Changes and conflicts';

  @override
  String get aktualisieren => 'Retry sync';

  @override
  String get wartet => 'Waiting to be sent';

  @override
  String get konflikt => 'Changed concurrently';

  @override
  String get abgelehnt => 'Rejected by the server';

  @override
  String get unlesbar => 'Can no longer be decrypted on this device';

  @override
  String get leer => 'No pending changes or conflicts.';

  @override
  String get mehr => 'Load more';

  @override
  String get fehler =>
      'Could not refresh the overview. Saved changes are retained.';

  @override
  String get alt =>
      'The server must be updated before guarded changes can be sent.';

  @override
  String get geschuetzt =>
      'At least one affected photo is locked. Contents and reapplying remain locked.';

  @override
  String get entfernt =>
      'An affected photo has been removed or trashed. The old change cannot be reapplied.';

  @override
  String get behalten => 'Keep server version';

  @override
  String get anwenden => 'Reapply my change';

  @override
  String get entscheidung =>
      'This decision applies to the entire original action, including all affected photos. Other pending changes are retained.';

  @override
  String get wartetText =>
      'This is the saved local intent. The server version will be checked when connected.';

  @override
  String get geaendert =>
      'The server version has changed again. Review the new comparison before deciding.';

  @override
  String get server => 'Server';

  @override
  String get eigen => 'My intent';

  @override
  String get unbekannt => 'Library change';

  @override
  String get favorit => 'Change favorite';

  @override
  String get bewertung => 'Change rating';

  @override
  String get farbe => 'Change color label';

  @override
  String get beschreibung => 'Change description';

  @override
  String get album => 'Change album';

  @override
  String get tag => 'Change tags';

  @override
  String get person => 'Change people';

  @override
  String get wertFavorit => 'Favorite';

  @override
  String get wertBewertung => 'Rating';

  @override
  String get wertFarbe => 'Color label';

  @override
  String get wertBeschreibung => 'Description';

  @override
  String get wertName => 'Name';

  @override
  String get wertDatum => 'Capture date';

  @override
  String get wertAlbum => 'Album';

  @override
  String get wertTag => 'Tag';

  @override
  String get wertPerson => 'Person';

  @override
  String get wertOrt => 'Location';

  @override
  String get ja => 'Yes';

  @override
  String get nein => 'No';

  @override
  String get kein => 'No value / removed';

  @override
  String get komplex =>
      'Further details of this action are saved; the decision also applies to them.';

  @override
  String get abbrechen => 'Cancel';

  @override
  String get bestaetigen => 'Confirm';

  @override
  String get grundKonflikt => 'Another device changed the same fields.';

  @override
  String get grundAbgelehnt =>
      'The server could not perform the action, for example due to missing permissions or invalid data.';

  @override
  String anzahl(int offen, int faelle) {
    return '$offen pending · $faelle to resolve';
  }

  @override
  String fotos(int anzahl) {
    return '$anzahl affected photos';
  }

  @override
  String get wertBreite => 'Latitude';

  @override
  String get wertLaenge => 'Longitude';
}

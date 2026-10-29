// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'sync_texte.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class SyncTexteDe extends SyncTexte {
  SyncTexteDe([String locale = 'de']) : super(locale);

  @override
  String get titel => 'Änderungen und Konflikte';

  @override
  String get aktualisieren => 'Abgleich erneut versuchen';

  @override
  String get wartet => 'Wartet auf Übertragung';

  @override
  String get konflikt => 'Gleichzeitig geändert';

  @override
  String get abgelehnt => 'Vom Server abgelehnt';

  @override
  String get unlesbar => 'Auf diesem Gerät nicht mehr entschlüsselbar';

  @override
  String get leer => 'Keine offenen Änderungen oder Konflikte.';

  @override
  String get mehr => 'Weitere laden';

  @override
  String get fehler =>
      'Die Übersicht konnte nicht aktualisiert werden. Gespeicherte Änderungen bleiben erhalten.';

  @override
  String get alt =>
      'Der Server muss aktualisiert werden, bevor geschützte Änderungen übertragen werden können.';

  @override
  String get geschuetzt =>
      'Mindestens eine betroffene Aufnahme ist gesperrt. Inhalte und erneutes Anwenden bleiben gesperrt.';

  @override
  String get entfernt =>
      'Eine betroffene Aufnahme wurde entfernt oder liegt im Papierkorb. Die alte Änderung kann nicht erneut angewandt werden.';

  @override
  String get behalten => 'Serverstand behalten';

  @override
  String get anwenden => 'Eigene Änderung erneut anwenden';

  @override
  String get entscheidung =>
      'Die Entscheidung gilt für die gesamte ursprüngliche Aktion einschließlich aller betroffenen Aufnahmen. Andere offene Änderungen bleiben erhalten.';

  @override
  String get wartetText =>
      'Dies ist die gespeicherte lokale Absicht. Der Serverstand wird erst bei einer Verbindung geprüft.';

  @override
  String get geaendert =>
      'Der Serverstand hat sich inzwischen geändert. Bitte den neuen Vergleich prüfen und erneut entscheiden.';

  @override
  String get server => 'Server';

  @override
  String get eigen => 'Eigene Absicht';

  @override
  String get unbekannt => 'Bibliotheksänderung';

  @override
  String get favorit => 'Favorit ändern';

  @override
  String get bewertung => 'Bewertung ändern';

  @override
  String get farbe => 'Farbmarke ändern';

  @override
  String get beschreibung => 'Beschreibung ändern';

  @override
  String get album => 'Album ändern';

  @override
  String get tag => 'Tags ändern';

  @override
  String get person => 'Personen ändern';

  @override
  String get wertFavorit => 'Favorit';

  @override
  String get wertBewertung => 'Bewertung';

  @override
  String get wertFarbe => 'Farbmarke';

  @override
  String get wertBeschreibung => 'Beschreibung';

  @override
  String get wertName => 'Name';

  @override
  String get wertDatum => 'Aufnahmedatum';

  @override
  String get wertAlbum => 'Album';

  @override
  String get wertTag => 'Tag';

  @override
  String get wertPerson => 'Person';

  @override
  String get wertOrt => 'Ort';

  @override
  String get ja => 'Ja';

  @override
  String get nein => 'Nein';

  @override
  String get kein => 'Kein Wert / entfernt';

  @override
  String get komplex =>
      'Weitere Angaben dieser Aktion sind gespeichert; die Entscheidung gilt auch für sie.';

  @override
  String get abbrechen => 'Abbrechen';

  @override
  String get bestaetigen => 'Bestätigen';

  @override
  String get grundKonflikt =>
      'Ein anderes Gerät hat dieselben Angaben verändert.';

  @override
  String get grundAbgelehnt =>
      'Der Server konnte die Aktion nicht ausführen, etwa wegen fehlender Rechte oder ungültiger Daten.';

  @override
  String anzahl(int offen, int faelle) {
    return '$offen wartend · $faelle zu entscheiden';
  }

  @override
  String fotos(int anzahl) {
    return '$anzahl betroffene Aufnahmen';
  }

  @override
  String get wertBreite => 'Breitengrad';

  @override
  String get wertLaenge => 'Längengrad';
}

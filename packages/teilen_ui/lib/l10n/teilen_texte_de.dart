// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'teilen_texte.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class TeilenTexteDe extends TeilenTexte {
  TeilenTexteDe([String locale = 'de']) : super(locale);

  @override
  String get geteiltMitMir => 'Geteilt mit mir';

  @override
  String geteiltVon(String name) {
    return 'von $name';
  }

  @override
  String geteiltAlbumVon(String name) {
    return 'Geteilt von $name';
  }

  @override
  String geteiltBeigetragenVon(String name) {
    return 'Beigetragen von $name';
  }

  @override
  String get geteiltHinzufuegen => 'Fotos hinzufügen';

  @override
  String get geteiltVerlassen => 'Nicht mehr anzeigen';

  @override
  String geteiltVerlassenFrage(String name, String besitzer) {
    return '„$name“ nicht mehr anzeigen? Die Fotos bleiben bei $besitzer; teilen kann nur $besitzer es wieder.';
  }

  @override
  String get geteiltNichtMehr => 'Dieses Album ist nicht mehr mit dir geteilt.';

  @override
  String geteiltLaedtHoch(int i, int n) {
    return 'Lade $i von $n hoch …';
  }

  @override
  String geteiltHinzugefuegt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen hinzugefügt',
      one: '1 Aufnahme hinzugefügt',
    );
    return '$_temp0';
  }

  @override
  String get geteiltNurAnsehen =>
      'Du darfst in dieses Album nichts mehr legen.';

  @override
  String get geteiltSpeicherVoll => 'Der Speicher des Servers ist voll.';

  @override
  String geteiltFehler(String name) {
    return '„$name“ ging nicht.';
  }

  @override
  String get geteiltOffline => 'Der Server ist gerade nicht zu erreichen.';

  @override
  String get geteiltLeer => 'Das Album ist leer.';

  @override
  String get geteiltEntfernen => 'Aus dem Album entfernen';

  @override
  String geteiltEntfernenFrage(String name) {
    return 'Deinen Beitrag „$name“ aus dem Album entfernen? Liegt er in keinem anderen Album, kommt er in den Papierkorb des Besitzers.';
  }

  @override
  String get geteiltEntfernt => 'Aus dem Album entfernt';

  @override
  String get kontenTeilen => 'Mit Konten teilen';

  @override
  String kontenTeilenTitel(String titel) {
    return '„$titel“ mit Konten teilen';
  }

  @override
  String get kontenTeilenHinweis =>
      'Andere Konten dieses Servers sehen das Album unter „Geteilt mit mir“ – im Browser und auf dem Telefon.';

  @override
  String get kontenBeitragenHinweis =>
      'Wer beitragen darf, legt Fotos und Videos direkt in dieses Album. Sie kommen in deine Bibliothek.';

  @override
  String get kontenAnsehen => 'Ansehen';

  @override
  String get kontenBeitragen => 'Beitragen';

  @override
  String get kontenNiemand => 'Mit niemandem geteilt.';

  @override
  String get kontenKeineAnderen =>
      'Auf diesem Server gibt es kein weiteres Konto.';

  @override
  String get kontenTeilenKnopf => 'Teilen';

  @override
  String get abbrechen => 'Abbrechen';

  @override
  String get entfernen => 'Entfernen';

  @override
  String get schliessen => 'Schliessen';
}

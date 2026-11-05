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

  @override
  String get neueBeitraegeTitel => 'Neu in deinen geteilten Alben';

  @override
  String neueBeitraegeAlbum(String name, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '„$name“: $n neue Aufnahmen',
      one: '„$name“: 1 neue Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String neueBeitraegeVon(String namen) {
    return 'von $namen';
  }

  @override
  String partnerBibliothekVon(String name) {
    return 'Bibliothek von $name';
  }

  @override
  String get partnerGanzeBibliothek => 'Ganze Bibliothek';

  @override
  String get partnerNichtMehr =>
      'Diese Bibliothek ist nicht mehr mit dir geteilt.';

  @override
  String partnerVerlassenFrage(String name) {
    return 'Die Bibliothek von $name nicht mehr anzeigen? Teilen kann nur $name sie wieder.';
  }

  @override
  String get bibliothekTeilen => 'Bibliothek teilen';

  @override
  String get bibliothekTeilenTitel => 'Bibliothek teilen';

  @override
  String get bibliothekTeilenHinweis =>
      'Wer hier steht, sieht deine Bibliothek unter „Geteilt mit mir“ – ganz oder nur ab einem Tag und mit bestimmten Personen, ohne Gesperrtes und Papierkorb, nur zum Ansehen.';

  @override
  String get kommentare => 'Kommentare';

  @override
  String get kommentarSchreiben => 'Kommentar schreiben …';

  @override
  String get kommentarSenden => 'Senden';

  @override
  String get kommentarEntfernen => 'Kommentar entfernen';

  @override
  String get kommentarEntfernenFrage => 'Diesen Kommentar entfernen?';

  @override
  String get kommentareKeine => 'Noch keine Kommentare.';

  @override
  String get kommentarZuFoto => 'zu einem Foto';

  @override
  String get kommentarFehler =>
      'Das hat nicht geklappt. Bitte später noch einmal versuchen.';

  @override
  String get kommentareHinweis =>
      'Alle, mit denen das Album geteilt ist, sehen die Kommentare.';

  @override
  String get gefaelltMir => 'Gefällt mir';

  @override
  String gefaelltNamen(String namen) {
    return 'Gefällt $namen';
  }

  @override
  String get speichern => 'Speichern';

  @override
  String get automatischFuellen => 'Automatisch füllen';

  @override
  String automatischTitel(String name) {
    return '„$name“ automatisch füllen';
  }

  @override
  String get automatischHinweis =>
      'Fotos der gewählten Personen kommen von selbst in dieses Album – auch solche, auf denen sie erst später erkannt werden. Was du herausnimmst, bleibt draussen.';

  @override
  String get automatischAus => 'Nicht mehr automatisch füllen';

  @override
  String get automatischAusGemacht =>
      'Das Album füllt sich nicht mehr selbst. Was darin liegt, bleibt.';

  @override
  String automatischDazu(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen dazugelegt',
      one: 'Eine Aufnahme dazugelegt',
      zero: 'Nichts Neues dazugelegt',
    );
    return '$_temp0';
  }

  @override
  String get regelEine => 'Eine der Personen';

  @override
  String get regelAlle => 'Alle zusammen';

  @override
  String get regelMindestensEine => 'Wähle mindestens eine Person.';

  @override
  String get regelHoechstens => 'Höchstens 20 Personen.';

  @override
  String regelPersonenFehlen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n gewählte Personen gibt es nicht mehr.',
      one: 'Eine gewählte Person gibt es nicht mehr.',
    );
    return '$_temp0';
  }

  @override
  String regelMit(String namen) {
    return 'mit $namen';
  }

  @override
  String regelZusammen(String namen) {
    return '$namen zusammen';
  }

  @override
  String regelAb(String tag) {
    return 'ab $tag';
  }

  @override
  String get aufgenommenAb => 'Aufgenommen ab';

  @override
  String get jedesDatum => 'jedes Datum';

  @override
  String get personSuchen => 'Person suchen';

  @override
  String get keinePersonGefunden => 'Keine Person gefunden.';

  @override
  String get keinePersonenMitNamen => 'Noch keine Personen mit Namen.';

  @override
  String get partnerEinschraenken => 'Einschränken';

  @override
  String partnerWasSieht(String name) {
    return 'Was $name sieht';
  }

  @override
  String partnerEinschraenkenHinweis(String name) {
    return 'Ohne Auswahl sieht $name deine ganze Bibliothek. Mit Personen nur Fotos, auf denen mindestens eine davon ist – das gilt für jede Datei, nicht nur für die Liste.';
  }

  @override
  String get partnerGanz => 'Die ganze Bibliothek';

  @override
  String get partnerInZeitleiste => 'In meiner Zeitleiste zeigen';

  @override
  String get partnerInZeitleisteFern =>
      'In der Zeitleiste zeigen (Handy und Browser)';

  @override
  String get partnerEingeschraenkt => 'Nur ein Teil der Bibliothek';

  @override
  String get nachlass => 'Nachlasskontakt';

  @override
  String get nachlassHinweis =>
      'Ein Nachlasskontakt kann Zugang zu deiner Bibliothek verlangen – etwa, wenn dir etwas zustösst. Widersprichst du nicht innerhalb der Frist, sieht er danach deine ganze Bibliothek unter „Geteilt mit mir“, nur zum Ansehen und Herunterladen. Die Anfrage steht im Browser, am Handy und am Rechner.';

  @override
  String get nachlassMeine => 'Deine Nachlasskontakte';

  @override
  String get nachlassFuerMich => 'Du bist Nachlasskontakt für';

  @override
  String get nachlassKeine => 'Noch niemand benannt.';

  @override
  String get nachlassBenennen => 'Benennen';

  @override
  String get nachlassAblehnen => 'Ablehnen';

  @override
  String get nachlassVerlangen => 'Zugang verlangen';

  @override
  String get nachlassZurueckziehen => 'Anfrage zurückziehen';

  @override
  String nachlassFristTage(int n) {
    return '$n Tage Frist';
  }

  @override
  String nachlassOffen(String tag) {
    return 'verlangt Zugang – ohne Widerspruch ab $tag';
  }

  @override
  String nachlassHatZugang(String tag) {
    return 'hat Zugang seit $tag';
  }

  @override
  String nachlassDuHastZugang(String tag) {
    return 'Zugang seit $tag – unter „Geteilt mit mir“';
  }

  @override
  String nachlassVerlangenFrage(String name, int tage) {
    return 'Zugang zur Bibliothek von $name verlangen? $name sieht die Anfrage und kann $tage Tage lang widersprechen. Danach siehst du die ganze Bibliothek, nur zum Ansehen und Herunterladen.';
  }

  @override
  String nachlassAnfrage(String name, String tag) {
    return '$name verlangt Zugang zu deiner Bibliothek (Nachlasskontakt). Ohne Widerspruch bekommt $name ihn am $tag.';
  }

  @override
  String get collage => 'Collage';

  @override
  String get collageVorlage => 'Vorlage';

  @override
  String get collageFormat => 'Format';

  @override
  String get collageAbstand => 'Abstand';

  @override
  String get collageEcken => 'Ecken';

  @override
  String get collageHintergrund => 'Hintergrund';

  @override
  String get collageReihenfolge => 'Reihenfolge';

  @override
  String get collageReihenfolgeHinweis =>
      'Ein Tipp setzt ein Foto an den Anfang – bei „Gross links“ und „Gross oben“ wird es das grosse.';

  @override
  String get collageRaster => 'Raster';

  @override
  String get collageReihe => 'Nebeneinander';

  @override
  String get collageStapel => 'Untereinander';

  @override
  String get collageGrossLinks => 'Gross links';

  @override
  String get collageGrossOben => 'Gross oben';

  @override
  String get collageQuadrat => 'Quadrat';

  @override
  String get collageQuer => '3:2';

  @override
  String get collageHoch => '2:3';

  @override
  String get collageStory => '9:16';

  @override
  String get collageGespeichert =>
      'Collage gespeichert – sie steht in der Zeitleiste bei ihren Fotos.';

  @override
  String get collageZweiBisNeun => 'Eine Collage braucht 2 bis 9 Fotos.';
}

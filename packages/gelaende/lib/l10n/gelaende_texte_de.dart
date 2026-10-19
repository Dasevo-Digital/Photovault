// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'gelaende_texte.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class GelaendeTexteDe extends GelaendeTexte {
  GelaendeTexteDe([String locale = 'de']) : super(locale);

  @override
  String get allgAbbrechen => 'Abbrechen';

  @override
  String get flugAnhalten => 'Anhalten';

  @override
  String get flugAufstieg => 'Aufstieg';

  @override
  String get flugBeenden => 'Zur Übersicht';

  @override
  String get flugFortschritt => 'Stelle auf der Spur';

  @override
  String get flugHoehe => 'Höhe';

  @override
  String flugKm(String wert) {
    return '$wert km';
  }

  @override
  String flugKmH(String wert) {
    return '$wert km/h';
  }

  @override
  String flugMeterProfil(int meter) {
    return '$meter m';
  }

  @override
  String get flugNochmal => 'Noch einmal';

  @override
  String get flugOhneZeit =>
      'Die Spur trägt keine Zeitstempel – ohne sie gibt es kein Tempo.';

  @override
  String flugProzent(String wert) {
    return '$wert %';
  }

  @override
  String get flugStarten => 'Flug starten';

  @override
  String get flugSteigung => 'Steigung';

  @override
  String get flugTempo => 'Tempo';

  @override
  String get flugUnterwegs => 'unterwegs';

  @override
  String get flugVideo => 'Als Video ausgeben';

  @override
  String get flugVideoAbbrechen => 'Ausgabe abbrechen';

  @override
  String get flugVideoAbgebrochen => 'Ausgabe abgebrochen';

  @override
  String get flugVideoAufloesung => 'Auflösung';

  @override
  String flugVideoBilder(int bilder) {
    return '$bilder Bilder';
  }

  @override
  String get flugVideoDauer => 'Dauer';

  @override
  String flugVideoDauerWert(int sekunden) {
    return '$sekunden Sekunden';
  }

  @override
  String get flugVideoEinstellungen => 'Video ausgeben';

  @override
  String flugVideoFehler(String grund) {
    return 'Die Videoausgabe ist fehlgeschlagen: $grund';
  }

  @override
  String flugVideoFertig(String datei) {
    return 'Video gespeichert: $datei';
  }

  @override
  String get flugVideoKeinWerkzeug =>
      'Für die Videoausgabe fehlt der Videoschreiber. Unter macOS gehört er zum System, unter Linux und Windows liegt er im Paket – erscheint diese Meldung, ist die Installation unvollständig.';

  @override
  String flugVideoLaeuft(int prozent) {
    return 'Video wird geschrieben – $prozent %';
  }

  @override
  String flugVideoLaeuftMitRest(int prozent, String rest) {
    return 'Video wird geschrieben – $prozent %, noch etwa $rest';
  }

  @override
  String get flugVideoWaehrenddessen =>
      'Die Bilder entstehen abseits des Bildschirms – der Flug wird dafür nicht abgespielt. Diese Ansicht muss so lange offen bleiben.';

  @override
  String get flugVideoWeiter => 'Speichern unter …';

  @override
  String get flugWeiter => 'Weiter';

  @override
  String get gelaendeBedienung => 'Ziehen dreht und kippt · Rollen zoomt';

  @override
  String get gelaendeEbeneBeschriftung => 'Strassen und Ortsnamen';

  @override
  String get gelaendeEbeneHoehenlinien => 'Höhenlinien';

  @override
  String get gelaendeEbeneWanderobjekte => 'Gipfel, Hütten, Quellen';

  @override
  String get gelaendeEbeneWege => 'Wanderwege';

  @override
  String get gelaendeErneut => 'Noch einmal versuchen';

  @override
  String get gelaendeKarte => 'Karte auf der Landschaft';

  @override
  String get gelaendeLaedt => 'Holt Geländehöhen …';

  @override
  String get gelaendeNamensnennung => 'Höhen: Tilezen / AWS Open Data';

  @override
  String get gelaendeNichts =>
      'Für diesen Ausschnitt kamen keine Geländehöhen an. Die Kacheln liegen im Netz; ohne Verbindung gibt es keine Landschaft.';

  @override
  String get gelaendeStimmung => 'Tageszeit';

  @override
  String get gelaendeTitel => 'Gelände';

  @override
  String gelaendeUeberhoeht(String faktor) {
    return 'Höhe $faktor-fach überhöht';
  }

  @override
  String get karteDunkel => 'Dunkel';

  @override
  String get karteHell => 'Hell';

  @override
  String get karteLuftbild => 'Luftbild';

  @override
  String get karteTopografie => 'Topografie';

  @override
  String restaurDauerMinuten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Minuten',
      one: 'eine Minute',
    );
    return '$_temp0';
  }

  @override
  String restaurDauerSekunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Sekunden',
      one: 'eine Sekunde',
    );
    return '$_temp0';
  }

  @override
  String spurStelle(String km, int hoehe) {
    return '$km km · $hoehe m';
  }

  @override
  String get stimmungAbend => 'Abend';

  @override
  String get stimmungBlaueStunde => 'Blaue Stunde';

  @override
  String get stimmungMittag => 'Mittag';

  @override
  String get stimmungMorgen => 'Morgen';

  @override
  String get flugProfilBeschreibung =>
      'Höhenprofil der Spur mit der Stelle, an der der Flug gerade steht.';
}

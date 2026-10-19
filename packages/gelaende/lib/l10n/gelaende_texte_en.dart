// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'gelaende_texte.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class GelaendeTexteEn extends GelaendeTexte {
  GelaendeTexteEn([String locale = 'en']) : super(locale);

  @override
  String get allgAbbrechen => 'Cancel';

  @override
  String get flugAnhalten => 'Pause';

  @override
  String get flugAufstieg => 'Ascent';

  @override
  String get flugBeenden => 'Back to overview';

  @override
  String get flugFortschritt => 'Position along the track';

  @override
  String get flugHoehe => 'Elevation';

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
  String get flugNochmal => 'Again';

  @override
  String get flugOhneZeit =>
      'The track carries no timestamps – without them there is no speed.';

  @override
  String flugProzent(String wert) {
    return '$wert %';
  }

  @override
  String get flugStarten => 'Start flight';

  @override
  String get flugSteigung => 'Gradient';

  @override
  String get flugTempo => 'Speed';

  @override
  String get flugUnterwegs => 'elapsed';

  @override
  String get flugVideo => 'Export as video';

  @override
  String get flugVideoAbbrechen => 'Cancel export';

  @override
  String get flugVideoAbgebrochen => 'Export cancelled';

  @override
  String get flugVideoAufloesung => 'Resolution';

  @override
  String flugVideoBilder(int bilder) {
    return '$bilder frames';
  }

  @override
  String get flugVideoDauer => 'Length';

  @override
  String flugVideoDauerWert(int sekunden) {
    return '$sekunden seconds';
  }

  @override
  String get flugVideoEinstellungen => 'Export video';

  @override
  String flugVideoFehler(String grund) {
    return 'Video export failed: $grund';
  }

  @override
  String flugVideoFertig(String datei) {
    return 'Video saved: $datei';
  }

  @override
  String get flugVideoKeinWerkzeug =>
      'Video export is unavailable – the video encoder is missing. macOS provides it, Linux and Windows ship it in the package; if you see this, the installation is incomplete.';

  @override
  String flugVideoLaeuft(int prozent) {
    return 'Writing video – $prozent %';
  }

  @override
  String flugVideoLaeuftMitRest(int prozent, String rest) {
    return 'Writing video – $prozent %, about $rest left';
  }

  @override
  String get flugVideoWaehrenddessen =>
      'The frames are rendered off screen – the flight is not played for it. This view has to stay open until it is done.';

  @override
  String get flugVideoWeiter => 'Save as …';

  @override
  String get flugWeiter => 'Continue';

  @override
  String get gelaendeBedienung => 'Drag to rotate and tilt · scroll to zoom';

  @override
  String get gelaendeEbeneBeschriftung => 'Roads and place names';

  @override
  String get gelaendeEbeneHoehenlinien => 'Contour lines';

  @override
  String get gelaendeEbeneWanderobjekte => 'Peaks, huts, springs';

  @override
  String get gelaendeEbeneWege => 'Hiking routes';

  @override
  String get gelaendeErneut => 'Try again';

  @override
  String get gelaendeKarte => 'Map on the landscape';

  @override
  String get gelaendeLaedt => 'Fetching elevations …';

  @override
  String get gelaendeNamensnennung => 'Elevation: Tilezen / AWS Open Data';

  @override
  String get gelaendeNichts =>
      'No elevation data arrived for this area. The tiles live on the network; without a connection there is no landscape.';

  @override
  String get gelaendeStimmung => 'Time of day';

  @override
  String get gelaendeTitel => 'Terrain';

  @override
  String gelaendeUeberhoeht(String faktor) {
    return 'Elevation exaggerated $faktor×';
  }

  @override
  String get karteDunkel => 'Dark';

  @override
  String get karteHell => 'Light';

  @override
  String get karteLuftbild => 'Aerial imagery';

  @override
  String get karteTopografie => 'Topographic';

  @override
  String restaurDauerMinuten(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl minutes',
      one: 'one minute',
    );
    return '$_temp0';
  }

  @override
  String restaurDauerSekunden(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl seconds',
      one: 'one second',
    );
    return '$_temp0';
  }

  @override
  String spurStelle(String km, int hoehe) {
    return '$km km · $hoehe m';
  }

  @override
  String get stimmungAbend => 'Evening';

  @override
  String get stimmungBlaueStunde => 'Blue hour';

  @override
  String get stimmungMittag => 'Midday';

  @override
  String get stimmungMorgen => 'Morning';

  @override
  String get flugProfilBeschreibung =>
      'Elevation profile of the track with the point the flight has reached.';
}

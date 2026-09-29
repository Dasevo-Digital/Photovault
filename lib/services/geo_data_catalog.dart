/// Beschreibt den offenen GeoNames-Datensatz, der für die lokale/offline
/// Umkehr-Geokodierung (GPS-Koordinaten -> Land/Bundesland/Stadt, siehe
/// ReverseGeocoder) benötigt wird. Analog zu ModelCatalog werden auch diese
/// Dateien nicht mit der App ausgeliefert, sondern bei Bedarf von der
/// offiziellen, öffentlichen GeoNames-Quelle heruntergeladen – die eigentliche
/// Zuordnung läuft danach komplett offline (keine Anfrage an einen
/// Geokodierungs-Dienst).
///
/// Anders als bei den KI-Modellen wird hier bewusst KEINE SHA-256-Prüfsumme
/// verglichen: GeoNames aktualisiert cities1000.zip & Co. regelmäßig (neue
/// Orte, korrigierte Einwohnerzahlen) – eine feste Prüfsumme würde also nach
/// dem nächsten Upstream-Update jeden weiteren Download verwerfen. Vertrauen
/// entsteht stattdessen dadurch, dass ausschließlich die feste,
/// öffentlich bekannte geonames.org-Domain angesprochen wird.
///
/// Lizenz: GeoNames-Daten stehen unter CC BY 4.0 (https://www.geonames.org/).
class GeoDataFile {
  final String fileName;
  final String url;

  /// Harte Obergrenze gegen einen fehlerhaften oder missbräuchlich großen
  /// Download. Der Datensatz darf wachsen; die Grenzen liegen deshalb weit
  /// über den heutigen Größen, begrenzen aber Platte und Arbeitsspeicher.
  final int maxBytes;
  const GeoDataFile(this.fileName, this.url, this.maxBytes);
}

class GeoDataCatalog {
  static const citiesZipFileName = 'cities1000.zip';
  static const citiesFileName = 'cities1000.txt';
  static const admin1FileName = 'admin1CodesASCII.txt';
  static const countryFileName = 'countryInfo.txt';

  /// Enthält Städte ab 1000 Einwohnern (~150.000 weltweit) – für die
  /// Zuordnung "nächstgelegene Stadt" ausreichend genau und mit ca. 10 MB
  /// entpackt deutlich kleiner als der volle Datensatz (alle Orte).
  static const files = [
    GeoDataFile(
        citiesZipFileName,
        'https://download.geonames.org/export/dump/cities1000.zip',
        32 * 1024 * 1024),
    GeoDataFile(
        admin1FileName,
        'https://download.geonames.org/export/dump/admin1CodesASCII.txt',
        8 * 1024 * 1024),
    GeoDataFile(
        countryFileName,
        'https://download.geonames.org/export/dump/countryInfo.txt',
        4 * 1024 * 1024),
  ];

  static const license = 'CC BY 4.0';
  static const sourceUrl = 'https://www.geonames.org/';
}

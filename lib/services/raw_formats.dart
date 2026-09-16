/// Dateiendungen, die macOS' ImageIO/CIRAWFilter systemweit als
/// Hersteller-RAW-Formate erkennt (unabhängig vom Kamerahersteller) – über
/// dieselbe API, mit der z.B. auch die Finder-Vorschau und Fotos.app RAW-
/// Dateien lesen. Einzige Quelle der Wahrheit für "welche Endungen gelten
/// als RAW" – wird von ImportService, NativeImageConverter und dem
/// Datei-Auswahldialog importiert, damit sie nicht auseinanderlaufen
/// können. Die Swift-Seite (ImageConverter.swift) muss diese Liste von
/// Hand gespiegelt halten, da sie nicht direkt importierbar ist.
const rawImageExtensions = {
  '.dng', '.cr2', '.cr3', '.crw', // Canon (+ Adobe DNG, iPhone DNG)
  '.nef', '.nrw', '.nefx', // Nikon
  '.arw', '.sr2', '.srf', '.axr', // Sony
  '.raf', // Fujifilm
  '.orf', // Olympus/OM System
  '.rw2', // Panasonic
  '.pef', // Pentax
  '.3fr', '.fff', // Hasselblad
  '.iiq', // Phase One
  '.dcr', // Kodak
  '.mrw', // Minolta
  '.mos', // Leaf
  '.srw', // Samsung
  '.erf', // Epson
  '.rwl', '.raw', // Leica
  '.dxo', // DxO
};

/// Dieselben Endungen ohne Punkt – die Schreibweise, in der das Format in
/// der Datenbank steht (siehe `Assets.dateiformat`).
///
/// Abgeleitet und nicht abgeschrieben: Eine zweite Liste von Hand wäre
/// die naheliegendste Art, dass beide auseinanderlaufen, ohne dass es
/// jemandem auffällt.
final rawDateiformate = {
  for (final e in rawImageExtensions) e.substring(1),
};

/// Das Dateiformat eines Namens – kleingeschrieben, ohne Punkt.
///
/// `null`, wenn der Name keine Endung hat. Bewusst nicht der leere Text:
/// „hat kein Format" und „Format unbekannt" sind zwei verschiedene
/// Aussagen, und nur die erste stimmt hier.
///
/// Alles hinter dem LETZTEN Punkt – `Urlaub.2019.jpg` ist `jpg`, nicht
/// `2019.jpg`. Die Migration in `database.dart` rechnet dasselbe in SQL;
/// beide sind gegen dieselben Beispiele geprüft.
String? dateiformatAus(String dateiname) {
  final punkt = dateiname.lastIndexOf('.');
  if (punkt < 0 || punkt == dateiname.length - 1) return null;
  return dateiname.substring(punkt + 1).toLowerCase();
}

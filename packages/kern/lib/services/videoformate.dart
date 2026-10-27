/// Die Videoformate, die Photo Vault annimmt – an einer Stelle für Import,
/// Formatkürzel, Server und Dateiauswahl (#232).
///
/// Bis 3.48 waren es nur `.mp4`, `.mov`, `.m4v`, `.avi` und `.mkv`; alles
/// andere ging beim Import still vorbei. Beim Abgleich mit Immich fehlten
/// so die Camcorder-Aufnahmen von 2013 – AVCHD (`.MTS`) und MPEG-2
/// (`.MPG`) –, die Immich angenommen hatte.
///
/// Vorschaubild und Dauer entstehen unter Linux, Windows und am Server mit
/// ffmpeg, das all diese Formate liest. Browser und Telefon spielen die
/// meisten davon nicht ab; sie holen dann die H.264-Fassung des Servers
/// (`Videofassungen`), wie schon bei HEVC. Am Rechner spielt libmpv alles.
/// Unter macOS ohne Server liest AVFoundation einige der älteren Formate
/// nicht – dann fehlt dort das Vorschaubild, abspielen geht trotzdem.
library;

/// Endung (klein, mit Punkt) → Medientyp.
const videoMedientypen = <String, String>{
  '.mp4': 'video/mp4',
  '.mov': 'video/quicktime',
  '.m4v': 'video/x-m4v',
  '.avi': 'video/x-msvideo',
  '.mkv': 'video/x-matroska',
  // AVCHD-Camcorder: MPEG-2-Transportstrom mit H.264.
  '.mts': 'video/mp2t',
  '.m2ts': 'video/mp2t',
  // MPEG-1/-2-Programmstrom; .mod/.tod schreiben SD-Camcorder von JVC
  // und Panasonic.
  '.mpg': 'video/mpeg',
  '.mpeg': 'video/mpeg',
  '.mod': 'video/mpeg',
  '.tod': 'video/mpeg',
  // Alte Mobiltelefone.
  '.3gp': 'video/3gpp',
  '.3g2': 'video/3gpp2',
  '.wmv': 'video/x-ms-wmv',
  '.asf': 'video/x-ms-asf',
  '.webm': 'video/webm',
  '.flv': 'video/x-flv',
};

/// Die Endungen selbst (klein, mit Punkt).
final videoEndungen = videoMedientypen.keys.toSet();

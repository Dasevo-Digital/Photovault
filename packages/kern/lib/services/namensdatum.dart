/// Ein Aufnahmedatum, das im **Dateinamen** steht.
///
/// Viele Werkzeuge schreiben den Zeitpunkt in den Namen, auch wenn sie die
/// EXIF-Angaben unterwegs verlieren: Telefone (`IMG_20190312_081502.jpg`,
/// `PXL_20231105_123456789.jpg`), Messenger (`IMG-20180517-WA0003.jpg`,
/// `PHOTO-2026-03-14-17-05-09.jpg`), Bildschirmfotos
/// (`Bildschirmfoto vom 2026-01-20 09-30-15.png`) und Ausfuhrprogramme
/// (`24-11-13 10-48-28 1234.jpg`).
///
/// **Warum das zählt.** In der Prüfbibliothek trugen 200 Aufnahmen ein
/// geschätztes Datum (den Tag, an dem sie kopiert wurden) und zugleich den
/// wahren Zeitpunkt im Namen, auf die Sekunde. Bei 24 weiteren, JPEG unter
/// einem `.MOV`-Namen, stand das Kopierdatum sogar ohne Vermerk in der
/// Zeile; Name und EXIF der Datei waren sich dabei einig.
///
/// Erkannt wird bewusst nur, was eindeutig ist:
///
/// - Jahr vierstellig, mit oder ohne Uhrzeit (`2024-11-13`, `20241113`,
///   `2024-11-13 10.48.28`, `20241113_104828`).
/// - Jahr zweistellig **nur mit Uhrzeit** (`24-11-13 10-48-28`). Ohne die
///   Uhrzeit ist `24-11-13` nicht zu entscheiden: der 13.11.2024 oder der
///   24.11.2013. Mit ihr ist es das Format der Ausfuhrprogramme, und in der
///   Prüfbibliothek bestätigten 226 von 226 solcher Namen mit EXIF genau
///   diese Lesart.
class Namensdatum {
  const Namensdatum(this.zeitpunkt, {required this.mitUhrzeit});

  /// Ortszeit wie bei EXIF (siehe `exifDatumAusText`): Der Name nennt die
  /// Uhrzeit, die die Kamera zeigte, ohne Zone. Ohne Uhrzeit steht der
  /// Mittag da, wie beim geschätzten Jahr: Der Tag kippt dann bei keinem
  /// Zonenversatz.
  final DateTime zeitpunkt;

  /// Ob der Name die Uhrzeit nennt. Ohne sie ist nur der Tag belegt, und
  /// die Aufnahme bleibt „geschätzt“: Sonst stünden alle Bilder eines
  /// Tages auf derselben Sekunde, und die Serienerkennung hielte sie für
  /// eine Reihe.
  final bool mitUhrzeit;

  /// Ob [zeitpunkt] dasselbe meint wie [anderer]: bei Uhrzeit bis auf eine
  /// Minute (Sekundenbruchteile, die Hälfte eines Live Photos liegt ein
  /// paar Sekunden daneben), sonst derselbe Kalendertag.
  bool passtZu(DateTime anderer) {
    final ort = anderer.toLocal();
    if (mitUhrzeit) {
      return zeitpunkt.difference(ort).abs() <= const Duration(minutes: 1);
    }
    return ort.year == zeitpunkt.year &&
        ort.month == zeitpunkt.month &&
        ort.day == zeitpunkt.day;
  }

  @override
  String toString() => 'Namensdatum($zeitpunkt, mitUhrzeit: $mitUhrzeit)';
}

// Vorne darf keine Ziffer stehen: `IMG_2013…` und `IMG2013…` ja, eine
// Zählnummer wie `DSC_0201305171` nicht.
const _vorne = r'(?<!\d)';
const _jahr4 = r'((?:19|20)\d\d)';
const _monat = r'(0[1-9]|1[0-2])';
const _tag = r'(0[1-9]|[12]\d|3[01])';
const _stunde = r'([01]\d|2[0-3])';
const _minute = r'([0-5]\d)';

// Zwischen Tag und Uhrzeit: Leerzeichen, Unterstrich, Bindestrich, `T`,
// die Wörter der Bildschirmfotos („at“, „um“) oder nichts
// (`VID20190101120000`). Die Uhrzeit darf Sekundenbruchteile tragen
// (Pixel: `123456789`).
final _mitUhrzeit = RegExp(
  '$_vorne$_jahr4([-_.]?)$_monat\\2$_tag'
  r'(?:[ _T-]|\s+(?:at|um)\s+)?'
  '$_stunde[-_.:h]?$_minute[-_.:m]?$_minute'
  r'\d{0,3}(?!\d)',
);
final _kurzMitUhrzeit = RegExp(
  '$_vorne(\\d\\d)-$_monat-$_tag[ _]$_stunde[-.]$_minute[-.]$_minute(?!\\d)',
);
final _ohneUhrzeit = RegExp('$_vorne$_jahr4([-_.]?)$_monat\\2$_tag(?!\\d)');

// Ein Name aus einer Kennung (`3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f.mp4`)
// oder einer Prüfsumme trägt kein Datum, auch wenn acht seiner Zeichen
// zufällig wie eines aussehen. Als Prüfsumme gilt eine Folge von zwölf
// Hexzeichen mit mindestens zwei Buchstaben – `VID20190101120000` hat
// nur das `D` aus „VID“ und bleibt ein Name.
final _kennung = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);
final _hexfolge = RegExp(r'[0-9a-f]{12,}', caseSensitive: false);
bool _wiePruefsumme(String stamm) => _hexfolge
    .allMatches(stamm)
    .any(
      (m) =>
          RegExp(r'[a-f]', caseSensitive: false).allMatches(m[0]!).length >= 2,
    );

/// Das Datum im Dateinamen [name], oder `null`.
///
/// [jetzt] ist die Grenze nach oben (für Prüfstände); ein Datum in der
/// Zukunft ist eine Zählnummer, kein Zeitpunkt.
Namensdatum? namensdatumAus(String name, {DateTime? jetzt}) {
  // Nur der Name, ohne Ordner und Endung.
  var stamm = name.split(RegExp(r'[/\\]')).last;
  final punkt = stamm.lastIndexOf('.');
  if (punkt > 0) stamm = stamm.substring(0, punkt);
  if (_kennung.hasMatch(stamm) || _wiePruefsumme(stamm)) return null;
  final grenze = (jetzt ?? DateTime.now()).add(const Duration(days: 1));

  Namensdatum? pruefe(int j, int mo, int t, [int? h, int? mi, int? s]) {
    final d = DateTime(j, mo, t, h ?? 12, mi ?? 0, s ?? 0);
    // DateTime rechnet den 31. Februar still in den März um.
    if (d.month != mo || d.day != t) return null;
    if (d.isAfter(grenze)) return null;
    return Namensdatum(d, mitUhrzeit: h != null);
  }

  int z(String? s) => int.parse(s!);

  if (_mitUhrzeit.firstMatch(stamm) case final m?) {
    final d = pruefe(z(m[1]), z(m[3]), z(m[4]), z(m[5]), z(m[6]), z(m[7]));
    if (d != null) return d;
  }
  if (_kurzMitUhrzeit.firstMatch(stamm) case final m?) {
    final kurz = z(m[1]);
    final heute = (jetzt ?? DateTime.now()).year % 100;
    final d = pruefe(
      kurz <= heute ? 2000 + kurz : 1900 + kurz,
      z(m[2]),
      z(m[3]),
      z(m[4]),
      z(m[5]),
      z(m[6]),
    );
    if (d != null) return d;
  }
  if (_ohneUhrzeit.firstMatch(stamm) case final m?) {
    return pruefe(z(m[1]), z(m[3]), z(m[4]));
  }
  return null;
}

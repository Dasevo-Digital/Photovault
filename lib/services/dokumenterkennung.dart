/// **Ausweise, Pässe und Karten unter den Fotos finden.**
///
/// Wer seinen Ausweis fotografiert – für eine Anmeldung, eine Reise, ein
/// Formular –, hat danach ein Bild in der Bibliothek, das nicht offen
/// liegen sollte. Apple sammelt solche Bilder seit iOS 27 in einer eigenen
/// Sammlung. Hier geht es einen Schritt weiter: Sie werden für den
/// gesperrten Ordner vorgeschlagen.
///
/// **Nur aus dem erkannten Text, nicht aus dem Bild.** Die Texterkennung
/// läuft ohnehin, und sie liefert Merkmale, die sich prüfen lassen statt
/// geschätzt zu werden:
///
/// * Die **maschinenlesbare Zone** von Pass und Ausweis (ICAO 9303) trägt
///   Prüfziffern. Geburtsdatum und Ablaufdatum stehen dort mit je einer
///   Ziffer, die sich nachrechnen lässt – zwei richtige sind bei
///   zufälligen Ziffernfolgen 1 zu 100, zusammen mit dem Geschlecht
///   dazwischen noch seltener.
/// * Eine **Kartennummer** in Vierergruppen besteht die Luhn-Prüfung.
/// * Bleiben **Schlüsselwörter** wie „Reisepass“ oder „Driving Licence“
///   – die schwächste Spur, aber die einzige bei einem Führerschein.
///
/// Ein Bildmodell („sieht aus wie ein Ausweis“) wäre die Ergänzung für
/// Bilder ohne lesbaren Text, schlägt aber auch bei jedem Plakat und jeder
/// Visitenkarte an. Ein Vorschlag für den Tresor, der oft danebenliegt,
/// wird schnell weggeklickt – auch dann, wenn er einmal stimmt.
library;

enum Dokumentart { reisepass, ausweis, fuehrerschein, aufenthaltstitel, karte }

/// Woran ein Dokument erkannt wurde – zum Anzeigen, damit ein Vorschlag
/// nachvollziehbar bleibt.
enum Dokumentgrund { pruefzeile, kartennummer, schluesselwort }

typedef Dokumentfund = ({Dokumentart art, Dokumentgrund grund});

/// Schlüsselwörter je Art, grossgeschrieben und ohne Leerzeichen
/// verglichen. Deutsch, Englisch, Französisch – das deckt die
/// Ausweise ab, die in einer deutschen Bibliothek liegen.
const _schluesselwoerter = <Dokumentart, List<String>>{
  Dokumentart.reisepass: ['REISEPASS', 'PASSPORT', 'PASSEPORT'],
  Dokumentart.ausweis: [
    'PERSONALAUSWEIS',
    'IDENTITYCARD',
    "CARTED'IDENTITÉ",
    'CARTED’IDENTITÉ',
    'IDENTITÄTSKARTE',
  ],
  Dokumentart.fuehrerschein: [
    'FÜHRERSCHEIN',
    'FUHRERSCHEIN',
    'DRIVINGLICENCE',
    'DRIVINGLICENSE',
    'DRIVERLICENSE',
    "DRIVER'SLICENSE",
    'PERMISDECONDUIRE',
  ],
  Dokumentart.aufenthaltstitel: ['AUFENTHALTSTITEL', 'RESIDENCEPERMIT'],
};

/// Was im Text [text] auf ein Ausweisdokument oder eine Karte hindeutet,
/// oder `null`.
Dokumentfund? dokumentImText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final gross = text.toUpperCase();
  // Die Texterkennung liest die Füllzeichen der Prüfzeile gern als
  // spitze Klammern anderer Art; Leerzeichen setzt sie, wo keine sind.
  final zone = gross
      .replaceAll(RegExp('[«‹〈＜]'), '<')
      .replaceAll(RegExp(r'\s'), '');

  final pruefzeile = _pruefzeile(zone);
  if (pruefzeile != null) {
    return (art: pruefzeile, grund: Dokumentgrund.pruefzeile);
  }
  if (_kartennummer(gross)) {
    return (art: Dokumentart.karte, grund: Dokumentgrund.kartennummer);
  }
  for (final MapEntry(key: art, value: woerter) in _schluesselwoerter.entries) {
    if (woerter.any(zone.contains)) {
      return (art: art, grund: Dokumentgrund.schluesselwort);
    }
  }
  return null;
}

/// Sucht die zweite Zeile einer maschinenlesbaren Zone: Geburtsdatum,
/// Prüfziffer, Geschlecht, Ablaufdatum, Prüfziffer – bei Pass (TD3) und
/// Ausweis (TD1) in derselben Folge.
Dokumentart? _pruefzeile(String zone) {
  // Als Vorausschau, damit sich Treffer überlappen dürfen: Steht vor dem
  // Geburtsdatum eine Ziffer, verschluckte ein gewöhnlicher Treffer sie
  // und verfehlte die richtige Stelle um eins.
  final muster = RegExp(r'(?=(\d{6})(\d)([MFX<])(\d{6})(\d))');
  for (final m in muster.allMatches(zone)) {
    if (_pruefziffer(m.group(1)!) != int.parse(m.group(2)!)) continue;
    if (_pruefziffer(m.group(4)!) != int.parse(m.group(5)!)) continue;
    // Die erste Zeile verrät den Pass: Sie beginnt mit „P“ und dem
    // Ausstellerstaat. Ausweis und Aufenthaltstitel teilen sich das
    // Format (TD1); auseinander hält sie nur der Aufdruck.
    final davor = zone.substring(0, m.start);
    if (RegExp(r'P[A-Z<][A-Z<]{3}[A-Z<]*<<').hasMatch(davor)) {
      return Dokumentart.reisepass;
    }
    if (_schluesselwoerter[Dokumentart.aufenthaltstitel]!.any(zone.contains)) {
      return Dokumentart.aufenthaltstitel;
    }
    return Dokumentart.ausweis;
  }
  return null;
}

/// Prüfziffer nach ICAO 9303: Gewichte 7, 3, 1 im Wechsel, Buchstaben
/// zählen ab 10, das Füllzeichen als 0.
int _pruefziffer(String feld) {
  const gewichte = [7, 3, 1];
  var summe = 0;
  for (var i = 0; i < feld.length; i++) {
    final c = feld.codeUnitAt(i);
    final wert = switch (c) {
      >= 0x30 && <= 0x39 => c - 0x30,
      >= 0x41 && <= 0x5A => c - 0x41 + 10,
      _ => 0,
    };
    summe += wert * gewichte[i % 3];
  }
  return summe % 10;
}

/// Eine Kartennummer in Vierergruppen, die die Luhn-Prüfung besteht.
///
/// **Nur in Gruppen.** Eine lange Ziffernfolge ohne Gliederung steht auf
/// jedem Kassenbon und jeder Rechnung, und jede zehnte besteht Luhn
/// zufällig. Geprägt oder gedruckt steht die Nummer auf der Karte in
/// Gruppen – mit dem Abstand dazwischen, den die Texterkennung mitliest.
bool _kartennummer(String text) {
  final muster = RegExp(
    r'(?<!\d)([3-6]\d{3})[ -](\d{4})[ -](\d{4})[ -](\d{4})(?!\d)',
  );
  for (final m in muster.allMatches(text)) {
    final ziffern = [for (var i = 1; i <= 4; i++) m.group(i)!].join();
    if (_luhn(ziffern)) return true;
  }
  return false;
}

bool _luhn(String ziffern) {
  var summe = 0;
  var doppeln = false;
  for (var i = ziffern.length - 1; i >= 0; i--) {
    var d = ziffern.codeUnitAt(i) - 0x30;
    if (doppeln) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    summe += d;
    doppeln = !doppeln;
  }
  return summe % 10 == 0;
}

/// Das Verzeichnis aller Länder – Name, Hauptstadt, Erdteil, Regionen.
///
/// Bisher wurde aus `countryInfo.txt` nur eine einzige Spalte gelesen: der
/// Ländername. Die Datei liegt aber vollständig auf der Platte und führt
/// neunzehn Spalten, darunter **Hauptstadt und Erdteil**. Und
/// `admin1CodesASCII.txt` weiß, aus wie vielen Regionen ein Land besteht –
/// die Zahl, gegen die sich „3 von 16 Bundesländern" überhaupt erst
/// zählen lässt.
///
/// Rein und ohne Dateizugriff: Die Zerlegung bekommt Zeilen, keine
/// Pfade. Nur so lässt sich nachrechnen, was am fertigen Balken niemand
/// mehr sieht.
library;

import 'laendernamen.dart';

/// Ein Land, wie der Datensatz es kennt.
typedef Landeintragung = ({
  /// Zweibuchstabiger Code, „DE".
  String iso,

  /// Ausgeschriebener Name, wie GeoNames ihn führt – **englisch**.
  ///
  /// Das ist der Name, unter dem die Umkehr-Geokodierung das Land in die
  /// Aufnahmen schreibt, und damit der Schlüssel, über den beides
  /// zusammenfindet. Gezeigt wird er nur, wenn die Oberfläche englisch
  /// läuft – sonst [nameDe].
  String name,

  /// Derselbe Name auf Deutsch, aus [laendernamenDe].
  ///
  /// Fällt auf [name] zurück, wo der Datensatz einen Code führt, den CLDR
  /// nicht kennt (oder nur falsch beantwortet – siehe dort).
  String nameDe,

  /// Hauptstadt, soweit die Datei eine nennt.
  String? hauptstadt,

  /// Erdteilkürzel: EU, AS, NA, SA, AF, OC, AN.
  String kontinent,

  /// Wie viele Regionen (Bundesländer, Provinzen …) das Land hat.
  ///
  /// **Kann 0 sein.** Kleinstaaten wie Monaco und der Vatikan haben in
  /// `admin1CodesASCII.txt` keinen einzigen Eintrag. Ein Fortschritt „x
  /// von 0" wäre eine Division durch nichts – wer damit rechnet, muss
  /// den Fall vorher abfangen.
  int regionen,
});

/// Der Name eines Eintrags in der Sprache der Oberfläche.
extension LandeintragungAnzeige on Landeintragung {
  String anzeige(String sprache) => sprache.startsWith('de') ? nameDe : name;
}

/// Alle Länder, nach Namen sortiert.
class Laenderkatalog {
  final List<Landeintragung> laender;
  final Map<String, Landeintragung> _nachIso;
  final Map<String, Landeintragung> _nachName;

  Laenderkatalog._(this.laender, this._nachIso, this._nachName);

  int get anzahl => laender.length;

  Landeintragung? nachIso(String iso) => _nachIso[iso.toUpperCase()];

  /// Der Ländername, wie er in der Sprache [sprache] dastehen soll.
  ///
  /// **Nimmt den englischen Namen entgegen**, denn das ist, was in den
  /// Aufnahmen steht: Die Umkehr-Geokodierung schreibt `location_country`
  /// aus genau diesem Datensatz. Ohne Treffer bleibt es beim übergebenen
  /// Namen – ein englischer Name ist besser als ein leeres Feld.
  String anzeige(String? englisch, String sprache) {
    if (englisch == null || englisch.isEmpty) return '';
    if (!sprache.startsWith('de')) return englisch;
    // Erst der Katalog – der kennt genau die Namen, die auch in den
    // Aufnahmen stehen. Sonst die Liste, die ohne geladenen Datensatz
    // auskommt.
    return _nachName[englisch]?.nameDe ?? landAnzeige(englisch, sprache);
  }

  /// Baut den Katalog aus den Zeilen beider Dateien.
  ///
  /// [admin1Zeilen] darf leer sein – dann hat jedes Land 0 Regionen und
  /// die Ansicht zeigt eben keinen Regionenfortschritt. Das ist besser
  /// als gar kein Katalog: Die Länderliste selbst hängt nicht daran.
  factory Laenderkatalog.aus({
    required Iterable<String> countryInfoZeilen,
    required Iterable<String> admin1Zeilen,
  }) {
    // Regionen je Land zählen. Der Code steht als „DE.02" vorn; alles vor
    // dem ersten Punkt ist das Land.
    final regionen = <String, int>{};
    for (final zeile in admin1Zeilen) {
      if (zeile.isEmpty) continue;
      final punkt = zeile.indexOf('.');
      if (punkt <= 0) continue;
      final land = zeile.substring(0, punkt);
      // Nicht auf den Tabulator warten: Eine kaputte Zeile ohne Namen
      // zählt trotzdem als vorhandene Region, und die Zahl soll die des
      // Datensatzes sein und nicht die der wohlgeformten Zeilen.
      regionen[land] = (regionen[land] ?? 0) + 1;
    }

    final liste = <Landeintragung>[];
    final nachIso = <String, Landeintragung>{};
    for (final zeile in countryInfoZeilen) {
      if (zeile.isEmpty || zeile.startsWith('#')) continue;
      final s = zeile.split('\t');
      // Spalte 0 ISO, 4 Name, 5 Hauptstadt, 8 Erdteil.
      if (s.length < 9) continue;
      final iso = s[0].trim();
      final name = s[4].trim();
      if (iso.isEmpty || name.isEmpty) continue;
      final hauptstadt = s[5].trim();
      final eintrag = (
        iso: iso,
        name: name,
        nameDe: laendernamenDe[iso] ?? name,
        hauptstadt: hauptstadt.isEmpty ? null : hauptstadt,
        kontinent: s[8].trim(),
        regionen: regionen[iso] ?? 0,
      );
      if (nachIso.containsKey(iso)) continue;
      nachIso[iso] = eintrag;
      liste.add(eintrag);
    }
    liste.sort((a, b) => a.name.compareTo(b.name));
    return Laenderkatalog._(List.unmodifiable(liste), nachIso,
        {for (final e in liste) e.name: e});
  }
}

/// Die Flagge zum Ländercode, als Emoji.
///
/// Zwei Buchstaben, je 127397 hochgezählt, ergeben die beiden regionalen
/// Anzeigezeichen – aus „DE" wird 🇩🇪. **Keine einzige Bilddatei**: 252
/// Flaggen als Grafik wären mehrere Megabyte im Paket, und sie müssten
/// gepflegt werden, sobald sich eine ändert.
///
/// Gibt `null` zurück, wenn der Code keine zwei Buchstaben hat. Der Aufrufer
/// zeigt dann nichts an statt zweier leerer Kästchen.
String? flaggeAus(String iso) {
  if (iso.length != 2) return null;
  final gross = iso.toUpperCase();
  final a = gross.codeUnitAt(0);
  final b = gross.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return null;
  return String.fromCharCodes([a + 127397, b + 127397]);
}

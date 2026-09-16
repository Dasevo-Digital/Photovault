/// Die Familien-Zeitleiste – die Rechnung dahinter.
///
/// `lebenslauf.dart` bringt **eine** Person in eine Reihenfolge. Was
/// fehlte, ist das Band über alle: wer wann lebte, wer sich überlappte,
/// wo Lücken sind. Ein Stammbaum zeigt Verwandtschaft, aber keine
/// Gleichzeitigkeit – dass die Urgroßmutter und der Enkel sich um elf
/// Jahre verpasst haben, steht in keiner der bisherigen Ansichten.
///
/// Getrennt von der Zeichnung (widgets/familien_zeitleiste.dart) nach
/// demselben Muster wie `faechertafel.dart` neben `faecher_ansicht.dart`:
/// Ob ein Balken an der richtigen Stelle sitzt, ist nachrechenbar; auf
/// dem fertigen Bild ist es das nicht.
library;

import 'lebenslauf.dart';

/// Ein datiertes Ereignis auf einer Zeile.
typedef Zeitmarke = ({DateTime datum, Ereignisart art});

/// Eine Person als Band: Balken von Geburt bis Tod, Marken darauf.
class Zeitzeile {
  final String personId;
  final String name;
  final DateTime? geburt;
  final DateTime? tod;

  /// Die übrigen Ereignisse, chronologisch – Geburt und Tod sind hier
  /// **nicht** noch einmal enthalten. Sie sind die Enden des Balkens und
  /// stünden sonst doppelt im Bild.
  final List<Zeitmarke> marken;

  const Zeitzeile({
    required this.personId,
    required this.name,
    this.geburt,
    this.tod,
    this.marken = const [],
  });

  /// Der früheste bekannte Zeitpunkt dieser Person.
  ///
  /// Nicht einfach [geburt]: Von manchen Vorfahren kennt man nur das
  /// Sterbejahr oder eine Hochzeit. Sie deshalb auf Jahr 0 zu setzen
  /// verschöbe die ganze Leiste.
  DateTime? get frueheste {
    DateTime? f = geburt;
    for (final m in [if (tod != null) tod!, for (final m in marken) m.datum]) {
      if (f == null || m.isBefore(f)) f = m;
    }
    return f;
  }

  DateTime? get spaeteste {
    DateTime? s = tod ?? geburt;
    for (final m in marken) {
      if (s == null || m.datum.isAfter(s)) s = m.datum;
    }
    return s;
  }

  /// Geburt bekannt, Tod nicht.
  ///
  /// Das ist **zweideutig** und muss es bleiben: Die App kann „lebt noch"
  /// nicht von „Sterbedatum unbekannt" unterscheiden, weil niemand danach
  /// gefragt hat. Der Balken läuft deshalb offen aus, statt an einem
  /// erfundenen Ende aufzuhören oder bis heute durchzuziehen – beides
  /// wäre eine Behauptung.
  bool get offen => geburt != null && tod == null;

  /// Ob überhaupt ein Zeitpunkt bekannt ist. Wer keinen hat, bekommt
  /// keinen Platz auf der Achse – aber sehr wohl eine Zeile.
  bool get datiert => frueheste != null;
}

/// Stellt eine Zeile zusammen.
///
/// Die Reihenfolge der Marken kommt aus [lebenslauf] und nicht aus einem
/// zweiten `sort` hier: Geburt und Tod stehen an der Person, alles andere
/// in der Ereignistabelle, und diese beiden Quellen zusammenzuführen ist
/// dort bereits gelöst. Zwei Sortierungen für dieselbe Sache liefen
/// früher oder später auseinander.
Zeitzeile zeitzeile({
  required String personId,
  required String name,
  DateTime? geburt,
  DateTime? tod,
  required List<EreignisEingabe> ereignisse,
}) {
  final zeilen = lebenslauf(geburt: geburt, tod: tod, ereignisse: ereignisse);
  return Zeitzeile(
    personId: personId,
    name: name,
    geburt: geburt,
    tod: tod,
    marken: [
      for (final z in zeilen)
        if (!z.istGeburt && !z.istTod && z.datum != null && z.art != null)
          (datum: z.datum!, art: z.art!),
    ],
  );
}

/// Der Ausschnitt der Zeitachse, den die Leiste zeigt.
class Zeitspanne {
  final DateTime von;
  final DateTime bis;

  const Zeitspanne(this.von, this.bis);

  /// Wo [d] auf der Achse liegt, als Anteil zwischen 0 und 1.
  ///
  /// Geklammert: Ein Zeitpunkt außerhalb der Spanne landet am Rand statt
  /// außerhalb des Bildes. Bei einer aus denselben Zeilen gerechneten
  /// Spanne kommt das nicht vor – die Klammer ist für den Fall, dass
  /// jemand später eine feste Spanne vorgibt.
  double anteil(DateTime d) {
    final ganz = bis.difference(von).inMilliseconds;
    if (ganz <= 0) return 0.5;
    return (d.difference(von).inMilliseconds / ganz).clamp(0.0, 1.0);
  }
}

/// Die Spanne über alle Zeilen. `null`, wenn keine einzige datiert ist.
///
/// Fällt alles auf denselben Zeitpunkt, wird die Spanne auf ein Jahr
/// aufgezogen – sonst wäre jede Lage 0,5 und die Jahresachse leer.
Zeitspanne? zeitspanne(Iterable<Zeitzeile> zeilen) {
  DateTime? von;
  DateTime? bis;
  for (final z in zeilen) {
    final f = z.frueheste;
    final s = z.spaeteste;
    if (f != null && (von == null || f.isBefore(von))) von = f;
    if (s != null && (bis == null || s.isAfter(bis))) bis = s;
  }
  if (von == null || bis == null) return null;
  if (!bis.isAfter(von)) {
    return Zeitspanne(von.subtract(const Duration(days: 183)),
        bis.add(const Duration(days: 183)));
  }
  return Zeitspanne(von, bis);
}

/// Sortiert die Zeilen von früh nach spät.
///
/// Nach dem **frühesten bekannten** Zeitpunkt, nicht nach der Geburt: Wer
/// nur mit Sterbejahr eingetragen ist, gehört zu seiner Zeit und nicht
/// ans Ende. Wer gar kein Datum hat, steht hinten – nach Namen geordnet,
/// damit die Reihenfolge nicht bei jedem Aufbau springt.
List<Zeitzeile> nachZeitSortiert(Iterable<Zeitzeile> zeilen) {
  int nachName(Zeitzeile a, Zeitzeile b) {
    final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return n != 0 ? n : a.personId.compareTo(b.personId);
  }

  return zeilen.toList()
    ..sort((a, b) {
      final fa = a.frueheste;
      final fb = b.frueheste;
      if (fa == null && fb == null) return nachName(a, b);
      if (fa == null) return 1;
      if (fb == null) return -1;
      final z = fa.compareTo(fb);
      return z != 0 ? z : nachName(a, b);
    });
}

/// Die Jahreszahlen, die als Achse unter der Leiste stehen.
///
/// Runde Schritte statt gleichmäßiger Teilung: „1900, 1925, 1950" liest
/// sich, „1903, 1928, 1953" nicht. Der Schritt wächst mit der Spanne, bis
/// höchstens [hoechstens] Marken übrig sind.
List<int> jahresmarken(Zeitspanne spanne, {int hoechstens = 8}) {
  const stufen = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000];
  final vonJahr = spanne.von.year;
  final bisJahr = spanne.bis.year;
  final breite = bisJahr - vonJahr;
  final schritt = stufen.firstWhere(
    (s) => breite / s <= hoechstens,
    orElse: () => stufen.last,
  );
  final erste = (vonJahr / schritt).ceil() * schritt;
  return [for (var j = erste; j <= bisJahr; j += schritt) j];
}

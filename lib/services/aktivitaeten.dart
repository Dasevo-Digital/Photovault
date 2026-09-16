/// Aktivitäten erkennen: die Wanderung, die Radtour, der Ausflug.
///
/// **Eine Aktivität steht für sich und *kann* zu einer Reise gehören.**
/// Die Sonntagswanderung vor der Haustür braucht keine Reise, und ein
/// Programm, das sie erst nach dem Anlegen eines Urlaubs zulässt, ist im
/// Weg.
///
/// Der Unterschied zur Reise (`reisen.dart`) ist nicht die Grösse,
/// sondern die Frage: Eine Reise ist eine Häufung **weit weg von zu
/// Hause über mehrere Tage**; eine Aktivität ist ein **zusammenhängendes
/// Stück eines Tages, an dem man Boden gutgemacht hat**. Beides kann
/// zutreffen — die Wanderung im Urlaub ist beides.
///
/// Reine Funktionen, ohne Datenbankklassen. Ob eine Häufung eine
/// Wanderung war, lässt sich nur nachrechnen; am fertigen Vorschlag
/// sieht man nicht, warum er entstanden ist.
library;

import 'reverse_geocoder.dart';

/// Was für eine Art von Unternehmung es war.
enum Aktivitaetsart {
  spaziergang,
  wanderung,
  radtour,
  ausflug,
  besichtigung,
  bootsfahrt,
  sonstiges;

  /// Wie die Art in der Datenbank steht.
  ///
  /// Der Name der Aufzählung und nicht ihr Index: Wer später eine Art
  /// dazwischenschiebt, verschöbe sonst alle gespeicherten Zeilen.
  String get kennung => name;

  /// Liest zurück, was [kennung] geschrieben hat. Unbekanntes wird
  /// [sonstiges] – eine Zeile aus einer neueren Fassung soll nicht die
  /// ganze Liste zum Absturz bringen.
  static Aktivitaetsart aus(String s) => Aktivitaetsart.values.firstWhere(
        (a) => a.name == s,
        orElse: () => Aktivitaetsart.sonstiges,
      );
}

/// Ob diese Kennung eine der mitgelieferten Arten ist.
///
/// **Der Unterschied zu [Aktivitaetsart.aus] ist der ganze Punkt.** Jene
/// macht aus allem Unbekannten `sonstiges` – richtig für eine Zeile aus
/// einer neueren Fassung, falsch für eine Art, die jemand selbst
/// eingetragen hat: Deren Name ginge dabei verloren. Wer anzeigen will,
/// fragt deshalb erst hier.
bool istBekannteArt(String kennung) =>
    Aktivitaetsart.values.any((a) => a.name == kennung);

/// Was von einer eingetippten Art in der Datenbank landet.
///
/// Gibt die Kennung einer mitgelieferten Art zurück, wenn der Text eine
/// davon meint – sonst den bereinigten Text selbst. `null` heisst „das
/// war kein Name".
///
/// **Warum der Abgleich sein muss.** Wer „Wanderung" eintippt, bekäme
/// sonst eine eigene Art neben der mitgelieferten `wanderung`: zwei
/// Einträge, die dasselbe heissen, einer davon ohne Symbol und ohne
/// Übersetzung. [bekannteNamen] sind die übersetzten Namen der
/// mitgelieferten Arten, hereingegeben, damit dieser Dienst ohne
/// Übersetzungsapparat auskommt.
String? eigeneArtKennung(String eingabe, Map<Aktivitaetsart, String> bekannteNamen) {
  final sauber = eingabe.trim();
  if (sauber.isEmpty) return null;
  final klein = sauber.toLowerCase();
  for (final a in Aktivitaetsart.values) {
    if (a.name == klein) return a.name;
    if ((bekannteNamen[a] ?? '').toLowerCase() == klein) return a.name;
  }
  return sauber;
}

/// Eine Aufnahme, wie die Erkennung sie braucht.
typedef Aktivitaetsaufnahme = ({
  String id,
  DateTime zeit,
  double breite,
  double laenge,
  String? stadt,
});

/// Eine Lücke von mehr als so vielen Minuten trennt zwei Aktivitäten.
///
/// Anderthalb Stunden. Wer vormittags wandert, mittags einkehrt und
/// nachmittags ein Museum ansieht, hat zwei Unternehmungen gemacht und
/// nicht eine lange. Kürzer gewählt zerfiele jede Wanderung an ihrer
/// Rast.
const int aktivitaetLueckeMinuten = 90;

/// So viele Aufnahmen muss eine Aktivität mindestens haben.
const int aktivitaetMindestfotos = 4;

/// Und so lange muss sie mindestens gedauert haben.
///
/// Dreiviertelstunde: Darunter ist es ein Halt und keine Unternehmung.
const Duration aktivitaetMindestdauer = Duration(minutes: 45);

/// Ab dieser zurückgelegten Strecke zählt es als Bewegung.
///
/// Zwei Kilometer. Das ist der Unterschied zwischen „im Garten
/// fotografiert" und „losgegangen".
const double aktivitaetMindestwegKm = 2;

/// … oder man war wenigstens so weit von zu Hause weg.
///
/// Zwanzig Kilometer. Wer zum Wildpark fährt und dort auf zweihundert
/// Metern dreissig Bilder macht, hat einen Ausflug gemacht, auch wenn
/// die Strecke vor Ort kurz war.
const double aktivitaetMindestentfernungKm = 20;

/// Zwei Punkte darunter sind derselbe – 50 m, gut über der Ungenauigkeit
/// eines GPS-Empfängers und weit unter jeder gemeinten Strecke.
const double _wegGlaettungKm = 0.05;

/// Ab dieser Durchschnittsgeschwindigkeit war es kein Fussweg mehr.
const double radAbKmh = 8;

/// Und ab dieser war ein Motor im Spiel.
const double fahrzeugAbKmh = 25;

/// Ein Vorschlag – **keine Aktivität.** Erst die Bestätigung macht eine
/// daraus, wie bei den Reisen.
class Aktivitaetsvorschlag {
  /// Die Aufnahmen, chronologisch.
  final List<String> aufnahmeIds;

  final DateTime von;
  final DateTime bis;

  /// Der vorgeschlagene Name – der häufigste Ort der Aufnahmen.
  final String name;

  /// Die vermutete Art. Siehe [vermuteArt]: nach oben belegt, nach
  /// unten geraten.
  final Aktivitaetsart art;

  /// Die zurückgelegte Strecke in Kilometern, geglättet.
  final double streckeKm;

  const Aktivitaetsvorschlag({
    required this.aufnahmeIds,
    required this.von,
    required this.bis,
    required this.name,
    required this.art,
    required this.streckeKm,
  });

  Duration get dauer => bis.difference(von);

  int get anzahl => aufnahmeIds.length;

  /// Womit sich der Vorschlag wiedererkennen lässt, wenn er abgelehnt
  /// wurde – die erste Aufnahme, wie beim Reisevorschlag.
  String get schluessel => aufnahmeIds.first;
}

/// Die zurückgelegte Strecke, in Kilometern.
///
/// **Erst glätten, dann summieren.** Dreissig Bilder von derselben Bank
/// aus ergeben sonst über die Streuung des GPS-Empfängers eine Strecke
/// von einigen hundert Metern, ohne dass jemand aufgestanden wäre. Was
/// näher als [_wegGlaettungKm] am zuletzt gezählten Punkt liegt, ist
/// derselbe Punkt.
double strecke(Iterable<({double breite, double laenge, DateTime zeit})> punkte,
    {double glaettungKm = _wegGlaettungKm}) {
  final sortiert = punkte.toList()..sort((a, b) => a.zeit.compareTo(b.zeit));
  if (sortiert.length < 2) return 0;
  var summe = 0.0;
  var letzter = sortiert.first;
  for (final p in sortiert.skip(1)) {
    final d = ReverseGeocoder.haversineKm(
        letzter.breite, letzter.laenge, p.breite, p.laenge);
    if (d < glaettungKm) continue;
    summe += d;
    letzter = p;
  }
  return summe;
}

/// Vermutet die Art aus Strecke und Dauer.
///
/// **Nach oben belegt, nach unten geraten.** Zwischen zwei Aufnahmen
/// liegt fast immer mehr Weg als die Luftlinie und fast immer eine Pause;
/// die gerechnete Geschwindigkeit ist deshalb eine *Untergrenze*. Daraus
/// folgt sauber nur die eine Richtung: Wer im Schnitt nachweislich über
/// [fahrzeugAbKmh] zurückgelegt hat, sass in einem Fahrzeug – zu Fuss
/// geht das nicht. Umgekehrt heisst ein niedriger Wert nur, dass es auch
/// langsam gewesen sein *könnte*.
///
/// Deshalb: oben wird entschieden, unten wird der harmloseste Fall
/// gewählt. Eine falsch geratene Art ist ein Klick, eine falsch
/// behauptete ist eine Unwahrheit in der Datenbank.
Aktivitaetsart vermuteArt(double streckeKm, Duration dauer) {
  if (dauer.inMinutes <= 0) return Aktivitaetsart.sonstiges;
  if (streckeKm < aktivitaetMindestwegKm) {
    // Kaum Weg, aber Zeit vergangen: Man war irgendwo und hat sich etwas
    // angesehen.
    return Aktivitaetsart.besichtigung;
  }
  final kmh = streckeKm / (dauer.inMinutes / 60);
  if (kmh >= fahrzeugAbKmh) return Aktivitaetsart.ausflug;
  if (kmh >= radAbKmh) return Aktivitaetsart.radtour;
  return Aktivitaetsart.wanderung;
}

/// Sucht in [aufnahmen] nach Aktivitäten.
///
/// [ohneOrt] ist der Name für eine Aktivität, deren Ort die
/// Umkehr-Geokodierung nicht kennt – hereingegeben, damit dieser Dienst
/// ohne Übersetzungsapparat auskommt.
///
/// [bekannteIds] sind Aufnahmen, die schon zu einer bestätigten
/// Aktivität gehören, [verworfen] die Schlüssel abgelehnter Vorschläge.
///
/// [wohnort] darf fehlen. Dann entscheidet allein die zurückgelegte
/// Strecke – ohne Wohnort ist „weit weg" keine beantwortbare Frage, und
/// eine erfundene Antwort wäre schlechter als keine.
List<Aktivitaetsvorschlag> erkenneAktivitaeten(
  List<Aktivitaetsaufnahme> aufnahmen, {
  required String ohneOrt,
  ({double breite, double laenge})? wohnort,
  Set<String> bekannteIds = const {},
  Set<String> verworfen = const {},
  int lueckeMinuten = aktivitaetLueckeMinuten,
  int mindestfotos = aktivitaetMindestfotos,
  Duration mindestdauer = aktivitaetMindestdauer,
  double mindestwegKm = aktivitaetMindestwegKm,
  double mindestentfernungKm = aktivitaetMindestentfernungKm,
}) {
  final offen = [
    for (final a in aufnahmen)
      if (!bekannteIds.contains(a.id)) a,
  ]..sort((a, b) => a.zeit.compareTo(b.zeit));

  final ergebnis = <Aktivitaetsvorschlag>[];
  var lauf = <Aktivitaetsaufnahme>[];

  void abschliessen() {
    final gruppe = lauf;
    lauf = [];
    if (gruppe.length < mindestfotos) return;
    final von = gruppe.first.zeit;
    final bis = gruppe.last.zeit;
    final dauer = bis.difference(von);
    if (dauer < mindestdauer) return;

    final weg = strecke([
      for (final a in gruppe)
        (breite: a.breite, laenge: a.laenge, zeit: a.zeit),
    ]);
    final weitWeg = wohnort != null &&
        gruppe.any((a) =>
            ReverseGeocoder.haversineKm(
                a.breite, a.laenge, wohnort.breite, wohnort.laenge) >=
            mindestentfernungKm);
    // Bewegung ODER Entfernung: Beides heisst „losgegangen", nur auf
    // verschiedene Weise. Beides zu verlangen striche die Fahrt zum
    // Wildpark; keines von beidem zu verlangen machte jeden Tag im
    // eigenen Garten zur Unternehmung.
    if (weg < mindestwegKm && !weitWeg) return;

    final vorschlag = Aktivitaetsvorschlag(
      aufnahmeIds: [for (final a in gruppe) a.id],
      von: von,
      bis: bis,
      name: _haeufigsterOrt(gruppe.map((a) => a.stadt)) ?? ohneOrt,
      art: vermuteArt(weg, dauer),
      streckeKm: weg,
    );
    if (!verworfen.contains(vorschlag.schluessel)) ergebnis.add(vorschlag);
  }

  for (final a in offen) {
    if (lauf.isNotEmpty) {
      final letzte = lauf.last.zeit;
      // Der Kalendertag trennt zusätzlich zur Lücke: „Am 4. Juni" ist
      // die Überschrift, unter der man eine Unternehmung sucht, und
      // eine, die über Mitternacht läuft, stünde unter keiner.
      final anderertag = a.zeit.day != letzte.day ||
          a.zeit.month != letzte.month ||
          a.zeit.year != letzte.year;
      if (anderertag || a.zeit.difference(letzte).inMinutes > lueckeMinuten) {
        abschliessen();
      }
    }
    lauf.add(a);
  }
  abschliessen();

  // Die jüngste zuerst – wie überall sonst in dieser App.
  ergebnis.sort((a, b) => b.von.compareTo(a.von));
  return ergebnis;
}

/// Zu welcher Reise eine Aktivität gehört – oder zu keiner.
///
/// **Die Fotos entscheiden, nicht der Kalender.** Welche Aufnahme zu
/// welcher Reise gehört, ist eine ausdrückliche Zuordnung
/// (`ReiseAufnahmen`); wer ein Bild aus einer Reise nimmt, meint das so.
/// Eine Aktivität, deren Bilder in einer Reise liegen, gehört dorthin,
/// auch wenn ihr Zeitraum über den der Reise hinausragt – der Zeitraum
/// einer Reise ist selbst nur aus ihren Aufnahmen abgeleitet.
///
/// Erst wenn **keine** Aufnahme der Aktivität einer Reise zugeordnet ist,
/// entscheidet die Zeit: die Reise, in deren Zeitraum die Aktivität
/// beginnt.
///
/// [reiseJeAufnahme] bildet Aufnahmekennung auf Reisekennung ab.
String? reiseFuerAktivitaet({
  required Iterable<String> aufnahmeIds,
  required DateTime von,
  required Map<String, String> reiseJeAufnahme,
  Iterable<({String id, DateTime von, DateTime bis})> reisen = const [],
}) {
  final gezaehlt = <String, int>{};
  for (final id in aufnahmeIds) {
    final r = reiseJeAufnahme[id];
    if (r != null) gezaehlt[r] = (gezaehlt[r] ?? 0) + 1;
  }
  if (gezaehlt.isNotEmpty) {
    final beste = gezaehlt.keys.toList()
      ..sort((a, b) {
        final z = gezaehlt[b]!.compareTo(gezaehlt[a]!);
        return z != 0 ? z : a.compareTo(b);
      });
    return beste.first;
  }
  for (final r in reisen) {
    if (!von.isBefore(r.von) && !von.isAfter(r.bis)) return r.id;
  }
  return null;
}

String? _haeufigsterOrt(Iterable<String?> orte) {
  final gezaehlt = <String, int>{};
  for (final o in orte) {
    if (o == null || o.trim().isEmpty) continue;
    gezaehlt[o] = (gezaehlt[o] ?? 0) + 1;
  }
  if (gezaehlt.isEmpty) return null;
  final beste = gezaehlt.keys.toList()
    ..sort((a, b) {
      final z = gezaehlt[b]!.compareTo(gezaehlt[a]!);
      return z != 0 ? z : a.compareTo(b);
    });
  return beste.first;
}

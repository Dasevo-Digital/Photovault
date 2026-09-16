/// Einen ganzen Satz in die vorhandenen Suchkriterien übersetzen.
///
/// **Warum das hier steht.** Die Suche kennt 24 Felder – Personen,
/// Schlagwörter, Kamera, Objektiv, Land/Region/Stadt, Zeitraum, Bewertung,
/// Farbmarke, ISO, Blende, Brennweite, Schärfe. Wer weiss, dass es sie gibt,
/// findet damit alles; wer es nicht weiss, tippt einen Satz ins Feld und
/// bekommt eine Bildsuche über CLIP, die von „5 Sterne" nichts versteht.
///
/// **Warum kein Sprachmodell.** digiKam hat für dieselbe Aufgabe eines
/// eingebaut. Hier lägen dann rund ein Gigabyte Modelldatei mehr neben den
/// 2,3 GB, die schon da sind – für eine Aufgabe, die zum grössten Teil aus
/// zehn wiederkehrenden Mustern besteht. Der billigere Weg zuerst: Was
/// dieser Leser versteht, wird zu einem Filter; **was er nicht versteht,
/// bleibt unangetastet stehen** und geht wie bisher an die Bildsuche. Damit
/// ist die Suche in keinem Fall schlechter als vorher, und ob ein Modell
/// gebraucht wird, entscheidet sich später an echten Anfragen statt an einer
/// Vermutung.
///
/// **Was er nicht kann und nicht können soll.** Verneinungen („ohne Anna"),
/// Verknüpfungen („Anna oder Bernd"), Vergleiche („die schärfsten"). Ein
/// halbverstandenes „ohne" wäre schlimmer als gar keines: Es lieferte
/// genau das Gegenteil, ohne dass man es der Trefferliste ansieht.
library;

import 'blur_detection.dart' show blurryScoreThreshold;
import 'search_filters.dart';

/// Ein Wort oder eine Wendung, die der Leser erkannt hat.
///
/// Wird angezeigt, damit sichtbar ist, was aus dem Satz geworden ist. Eine
/// Suche, die stillschweigend etwas anderes tut, als dasteht, ist die
/// schlimmste Art von Suche.
class Satzfund {
  /// Der erkannte Ausschnitt aus der Eingabe.
  final String wortlaut;

  /// Um welche Art Kriterium es sich handelt – für die Beschriftung.
  final Satzfundart art;

  /// Der gesetzte Wert in lesbarer Form („4 Sterne", „2019", „Anna").
  final String wert;

  const Satzfund(this.art, this.wortlaut, this.wert);
}

enum Satzfundart {
  person,
  schlagwort,
  kamera,
  ort,
  zeitraum,
  bewertung,
  farbmarke,
  medienart,
  favorit,
  schaerfe,
  iso,
  datumsherkunft,
}

/// Die Wörter, gegen die der Leser prüft – aus der Bibliothek, nicht fest
/// verdrahtet.
///
/// Ohne sie könnte er „Anna" nicht von „Ananas" unterscheiden: Ob ein Wort
/// ein Personenname ist, weiss nur die Bibliothek.
class Suchvokabular {
  /// Kennung -> Name.
  final Map<String, String> personen;
  final Map<String, String> schlagwoerter;

  /// Kameramodelle, wie sie in `Assets.cameraModel` stehen.
  final List<String> kameras;
  final List<String> laender;
  final List<String> regionen;
  final List<String> staedte;

  const Suchvokabular({
    this.personen = const {},
    this.schlagwoerter = const {},
    this.kameras = const [],
    this.laender = const [],
    this.regionen = const [],
    this.staedte = const [],
  });
}

/// Was aus einem Satz geworden ist.
class Satzdeutung {
  final SearchFilters filter;

  /// Was der Leser nicht verstanden hat – geht unverändert als [query]
  /// weiter an die vorhandene Suche.
  final String rest;

  final List<Satzfund> funde;

  const Satzdeutung({required this.filter, required this.rest, required this.funde});

  bool get hatVerstanden => funde.isNotEmpty;
}

/// Liest [eingabe] und füllt damit die Kriterien.
///
/// [heute] ist der Bezugspunkt für „letztes Jahr" und Ähnliches. Wird
/// übergeben und nicht aus der Uhr geholt, damit dieselbe Eingabe im
/// Prüfstand immer dasselbe ergibt.
///
/// [grundlage] ist der Filterstand, auf dem aufgesetzt wird – so bleiben
/// von Hand gesetzte Kriterien stehen, die der Satz nicht erwähnt.
Satzdeutung deuteSuchsatz(
  String eingabe, {
  required Suchvokabular vokabular,
  required DateTime heute,
  SearchFilters grundlage = const SearchFilters(),
}) {
  var rest = eingabe;
  var filter = grundlage;
  final funde = <Satzfund>[];

  /// Schneidet den ersten Treffer aus [rest] heraus und merkt ihn.
  bool nimm(RegExp muster, Satzfundart art, String Function(Match) wert,
      SearchFilters Function(SearchFilters f, Match m) anwenden) {
    final treffer = muster.firstMatch(rest);
    if (treffer == null) return false;
    filter = anwenden(filter, treffer);
    funde.add(Satzfund(art, treffer.group(0)!.trim(), wert(treffer)));
    rest = rest.replaceRange(treffer.start, treffer.end, ' ');
    return true;
  }

  // --- Bewertung -----------------------------------------------------
  // "5 Sterne", "mit 4 Sternen", "3 stars", "5*"
  nimm(
    RegExp(r'\b([1-5])\s*(sterne?n?|stars?|\*)', caseSensitive: false),
    Satzfundart.bewertung,
    (m) => '${m.group(1)}',
    (f, m) => f.copyWith(minRating: int.parse(m.group(1)!)),
  );

  // --- Farbmarke -----------------------------------------------------
  for (final eintrag in _farbwoerter.entries) {
    if (nimm(
      RegExp('\\b${eintrag.key}\\b', caseSensitive: false),
      Satzfundart.farbmarke,
      (_) => eintrag.value,
      (f, _) => f.copyWith(colorLabels: {...f.colorLabels, eintrag.value}),
    )) {
      break;
    }
  }

  // --- Favoriten und Medienart ---------------------------------------
  nimm(
    RegExp(r'\b(favoriten|favorites?|lieblings\w*)\b', caseSensitive: false),
    Satzfundart.favorit,
    (_) => '',
    (f, _) => f.copyWith(favoritesOnly: true),
  );
  nimm(
    RegExp(r'\b(videos?|filme?n?)\b', caseSensitive: false),
    Satzfundart.medienart,
    (_) => 'Video',
    (f, _) => f.copyWith(mediaType: MediaTypeFilter.video),
  ) ||
      nimm(
        RegExp(r'\b(fotos?|bilder n?|bilder|photos?)\b', caseSensitive: false),
        Satzfundart.medienart,
        (_) => 'Foto',
        (f, _) => f.copyWith(mediaType: MediaTypeFilter.image),
      );

  // --- Unschaerfe ----------------------------------------------------
  // Die Sichtung fragt genau danach, und bis hierher gab es dafuer nur
  // das Kreuz im Optionenfenster.
  nimm(
    RegExp(r'\b(unscharfe?n?|verwackelte?n?|blurry)\b', caseSensitive: false),
    Satzfundart.schaerfe,
    (_) => '',
    (f, _) => f.copyWith(maxSharpnessScore: blurryScoreThreshold),
  );

  // --- Aufnahmewerte: ISO ---------------------------------------------
  // "ab ISO 1600", "bis ISO 400", "ISO 100". Nur ISO, nicht Blende und
  // Brennweite: Bei "Blende 2,8" ist nicht entschieden, ob genau 2,8 oder
  // "mindestens so offen" gemeint ist, und ein halbverstandener Wert ist
  // schlimmer als gar keiner (siehe der Kopf dieser Datei). Bei ISO ist
  // die Richtung dagegen eindeutig: Wer "ab ISO 1600" sagt, meint das
  // Rauschen nach oben.
  nimm(
    RegExp(r'\bab\s*iso\s*(\d{2,6})\b', caseSensitive: false),
    Satzfundart.iso,
    (m) => 'ab ${m.group(1)}',
    (f, m) => f.copyWith(minIso: int.parse(m.group(1)!)),
  ) ||
      nimm(
        RegExp(r'\bbis\s*iso\s*(\d{2,6})\b', caseSensitive: false),
        Satzfundart.iso,
        (m) => 'bis ${m.group(1)}',
        (f, m) => f.copyWith(maxIso: int.parse(m.group(1)!)),
      ) ||
      nimm(
        RegExp(r'\biso\s*(\d{2,6})\b', caseSensitive: false),
        Satzfundart.iso,
        (m) => m.group(1)!,
        (f, m) => f.copyWith(
            minIso: int.parse(m.group(1)!), maxIso: int.parse(m.group(1)!)),
      );

  // --- Herkunft des Datums --------------------------------------------
  // Der Weg zu den 1097 Aufnahmen, deren Zeitstempel aus dem Dateisystem
  // stammt (siehe [Assets.datumGeschaetzt]).
  nimm(
    RegExp(r'\b(gesch(ä|ae)tzte[nrs]?\s+datum|gesch(ä|ae)tzte[nrs]?\s+daten|'
        r'estimated\s+dates?)\b',
        caseSensitive: false),
    Satzfundart.datumsherkunft,
    (_) => '',
    (f, _) => f.copyWith(nurGeschaetztesDatum: true),
  );

  // --- Zeit ----------------------------------------------------------
  final zeit = _deuteZeit(rest, heute);
  if (zeit != null) {
    filter = filter.copyWith(startDate: zeit.von, endDate: zeit.bis);
    funde.add(Satzfund(Satzfundart.zeitraum, zeit.wortlaut, zeit.beschreibung));
    rest = rest.replaceRange(zeit.start, zeit.ende, ' ');
  }

  // --- Vokabular aus der Bibliothek ----------------------------------
  // Die längsten zuerst: Sonst schnappt „Berlin" den Ausschnitt weg, den
  // „Berlin Tegel" gebraucht hätte.
  ({String rest, List<Satzfund> funde, SearchFilters filter}) ausVokabular(
    String text,
    SearchFilters bisher,
  ) {
    var uebrig = text;
    var f = bisher;
    final gefunden = <Satzfund>[];

    void suche(
      Iterable<MapEntry<String, String>> begriffe,
      Satzfundart art,
      SearchFilters Function(SearchFilters f, String schluessel) anwenden,
    ) {
      final sortiert = begriffe.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      for (final b in sortiert) {
        if (b.value.trim().isEmpty) continue;
        final muster = RegExp('(?<![\\wäöüß])${RegExp.escape(b.value)}(?![\\wäöüß])',
            caseSensitive: false);
        final treffer = muster.firstMatch(uebrig);
        if (treffer == null) continue;
        f = anwenden(f, b.key);
        gefunden.add(Satzfund(art, treffer.group(0)!, b.value));
        uebrig = uebrig.replaceRange(treffer.start, treffer.end, ' ');
      }
    }

    suche(vokabular.personen.entries, Satzfundart.person,
        (f, id) => f.copyWith(personIds: [...f.personIds, id]));
    suche(vokabular.schlagwoerter.entries, Satzfundart.schlagwort,
        (f, id) => f.copyWith(tagIds: [...f.tagIds, id]));
    suche([for (final k in vokabular.kameras) MapEntry(k, k)], Satzfundart.kamera,
        (f, k) => f.copyWith(cameraModel: k));
    suche([for (final o in vokabular.staedte) MapEntry(o, o)], Satzfundart.ort,
        (f, o) => f.copyWith(locationCity: o));
    suche([for (final o in vokabular.regionen) MapEntry(o, o)], Satzfundart.ort,
        (f, o) => f.copyWith(locationState: o));
    suche([for (final o in vokabular.laender) MapEntry(o, o)], Satzfundart.ort,
        (f, o) => f.copyWith(locationCountry: o));

    return (rest: uebrig, funde: gefunden, filter: f);
  }

  final ausListe = ausVokabular(rest, filter);
  rest = ausListe.rest;
  filter = ausListe.filter;
  funde.addAll(ausListe.funde);

  // Füllwörter, die allein übrig bleiben, sind kein Suchbegriff.
  final uebrig = rest
      .split(RegExp(r'\s+'))
      .where((w) => w.trim().isNotEmpty)
      .where((w) => !_fuellwoerter.contains(w.toLowerCase().replaceAll(RegExp(r'[.,!?]'), '')))
      .join(' ')
      .trim();

  // In der Reihenfolge, in der es dastand – nicht in der, in der geprüft
  // wurde. Die Marken unter dem Suchfeld sollen den Satz nachzeichnen; eine
  // Reihenfolge nach Trefferstärke sähe zufällig aus.
  funde.sort((a, b) {
    final pa = eingabe.toLowerCase().indexOf(a.wortlaut.toLowerCase());
    final pb = eingabe.toLowerCase().indexOf(b.wortlaut.toLowerCase());
    return (pa < 0 ? 1 << 20 : pa).compareTo(pb < 0 ? 1 << 20 : pb);
  });

  return Satzdeutung(
    filter: filter.copyWith(query: uebrig),
    rest: uebrig,
    funde: funde,
  );
}

/// Farbwörter beider Oberflächensprachen auf die internen Schlüssel (siehe
/// `colorLabelSwatches`).
const _farbwoerter = {
  'rot\\w*': 'red',
  'red': 'red',
  'gelb\\w*': 'yellow',
  'yellow': 'yellow',
  'grün\\w*': 'green',
  'gruen\\w*': 'green',
  'green': 'green',
  'blau\\w*': 'blue',
  'blue': 'blue',
  'violett\\w*': 'purple',
  'lila': 'purple',
  'purple': 'purple',
};

/// Wörter ohne eigenen Aussagewert. Bleiben sie als Suchbegriff stehen,
/// sucht die Bildsuche nach „mit" und findet nichts Sinnvolles.
const _fuellwoerter = {
  'mit', 'von', 'aus', 'im', 'in', 'am', 'an', 'der', 'die', 'das', 'den',
  'dem', 'ein', 'eine', 'einen', 'einem', 'und', 'auf', 'bei', 'zu', 'zum',
  'zur', 'alle', 'allen', 'wo', 'ist', 'sind', 'war', 'waren', 'ich',
  'mir', 'mich', 'vom', 'beim', 'für', 'fuer', 'nach', 'meine', 'meinen',
  'unser', 'unsere', 'unseren', 'es', 'da',
  'with', 'from', 'the', 'of', 'on', 'at',
  'my', 'me', 'show', 'zeig', 'zeige', 'suche', 'finde', 'find',
};

/// Ein erkannter Zeitraum samt der Stelle, an der er im Satz stand.
class _Zeitfund {
  final DateTime von;
  final DateTime bis;
  final String wortlaut;
  final String beschreibung;
  final int start;
  final int ende;
  const _Zeitfund(this.von, this.bis, this.wortlaut, this.beschreibung, this.start, this.ende);
}

const _monate = {
  'januar': 1, 'january': 1, 'februar': 2, 'february': 2, 'märz': 3,
  'maerz': 3, 'march': 3, 'april': 4, 'mai': 5, 'may': 5, 'juni': 6,
  'june': 6, 'juli': 7, 'july': 7, 'august': 8, 'september': 9,
  'oktober': 10, 'october': 10, 'november': 11, 'dezember': 12,
  'december': 12,
};

/// Meteorologische Jahreszeiten: ganze Monate, damit „Sommer 2019" einen
/// Zeitraum ergibt, dessen Grenzen man nachrechnen kann.
const _jahreszeiten = {
  'frühling': [3, 5], 'fruehling': [3, 5], 'frühjahr': [3, 5], 'spring': [3, 5],
  'sommer': [6, 8], 'summer': [6, 8],
  'herbst': [9, 11], 'autumn': [9, 11], 'fall': [9, 11],
  'winter': [12, 2],
};

/// Sucht die erste Zeitangabe im Satz.
///
/// Die Reihenfolge ist Absicht: Je genauer die Angabe, desto früher wird
/// geprüft. „Sommer 2019" muss vor „2019" drankommen, sonst bliebe das
/// Wort „Sommer" als Suchbegriff stehen und die Suche fände Fotos, auf
/// denen „Sommer" steht.
_Zeitfund? _deuteZeit(String satz, DateTime heute) {
  DateTime monatsende(int jahr, int monat) =>
      DateTime(jahr, monat + 1).subtract(const Duration(days: 1));

  // "Sommer 2019", "Winter 2020"
  final jahreszeitMitJahr = RegExp(
    '\\b(${_jahreszeiten.keys.join('|')})\\s+((?:19|20)\\d\\d)\\b',
    caseSensitive: false,
  ).firstMatch(satz);
  if (jahreszeitMitJahr != null) {
    final spanne = _jahreszeiten[jahreszeitMitJahr.group(1)!.toLowerCase()]!;
    final jahr = int.parse(jahreszeitMitJahr.group(2)!);
    return _jahreszeitfund(spanne, jahr, jahreszeitMitJahr);
  }

  // "letzten Sommer", "diesen Winter"
  final jahreszeitRelativ = RegExp(
    '\\b(letzten?|vorigen?|diesen?|last|this)\\s+(${_jahreszeiten.keys.join('|')})\\b',
    caseSensitive: false,
  ).firstMatch(satz);
  if (jahreszeitRelativ != null) {
    final wort = jahreszeitRelativ.group(1)!.toLowerCase();
    final spanne = _jahreszeiten[jahreszeitRelativ.group(2)!.toLowerCase()]!;
    final zurueck = wort.startsWith('diese') || wort == 'this' ? 0 : 1;
    return _jahreszeitfund(spanne, heute.year - zurueck, jahreszeitRelativ);
  }

  // "Juli 2020", "im Juli"
  final monatTreffer = RegExp(
    '\\b(${_monate.keys.join('|')})(?:\\s+((?:19|20)\\d\\d))?\\b',
    caseSensitive: false,
  ).firstMatch(satz);
  if (monatTreffer != null) {
    final monat = _monate[monatTreffer.group(1)!.toLowerCase()]!;
    final jahr = monatTreffer.group(2) != null
        ? int.parse(monatTreffer.group(2)!)
        // Ohne Jahresangabe der zuletzt vergangene solche Monat – „im Juli"
        // im Mai meint den Juli des Vorjahres, nicht den in zwei Monaten.
        : (monat <= heute.month ? heute.year : heute.year - 1);
    return _Zeitfund(
      DateTime(jahr, monat),
      monatsende(jahr, monat),
      monatTreffer.group(0)!,
      '${monatTreffer.group(1)} $jahr',
      monatTreffer.start,
      monatTreffer.end,
    );
  }

  // "letztes Jahr", "dieses Jahr"
  final jahrRelativ = RegExp(
    r'\b(letztes|voriges|dieses|last|this)\s+(jahr|year)\b',
    caseSensitive: false,
  ).firstMatch(satz);
  if (jahrRelativ != null) {
    final wort = jahrRelativ.group(1)!.toLowerCase();
    final jahr = wort.startsWith('diese') || wort == 'this' ? heute.year : heute.year - 1;
    return _Zeitfund(DateTime(jahr), DateTime(jahr, 12, 31), jahrRelativ.group(0)!,
        '$jahr', jahrRelativ.start, jahrRelativ.end);
  }

  // Eine nackte Jahreszahl.
  final jahrTreffer = RegExp(r'\b((?:19|20)\d\d)\b').firstMatch(satz);
  if (jahrTreffer != null) {
    final jahr = int.parse(jahrTreffer.group(1)!);
    return _Zeitfund(DateTime(jahr), DateTime(jahr, 12, 31), jahrTreffer.group(0)!,
        '$jahr', jahrTreffer.start, jahrTreffer.end);
  }

  return null;
}

_Zeitfund _jahreszeitfund(List<int> spanne, int jahr, Match treffer) {
  final vonMonat = spanne[0], bisMonat = spanne[1];
  // Der Winter läuft über den Jahreswechsel: Dezember gehört zum Winter des
  // FOLGENDEN Jahres, so wie „Winter 2020" den Dezember 2019 einschliesst.
  final von = vonMonat > bisMonat ? DateTime(jahr - 1, vonMonat) : DateTime(jahr, vonMonat);
  final bis = DateTime(jahr, bisMonat + 1).subtract(const Duration(days: 1));
  return _Zeitfund(von, bis, treffer.group(0)!,
      '${treffer.group(treffer.groupCount)} $jahr', treffer.start, treffer.end);
}

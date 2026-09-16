/// Einlesen von GEDCOM 5.5.1 – der Weg *hinein*.
///
/// `gedcom_export.dart` schreibt das Format seit langem; gelesen hat es
/// nie jemand. Wer schon geforscht hat, hat eine GEDCOM-Datei und musste
/// bisher alles von Hand neu eintippen. Das ist der teuerste Fund der
/// ganzen Vergleichsrunde gewesen.
///
/// Diese Datei ist bewusst **ohne Datenbank und ohne Oberfläche**: Sie
/// nimmt Bytes und gibt Personen, Kanten und Ereignisse zurück. Nur so
/// lässt sich das Einlesen gegen echte fremde Dateien prüfen, ohne dafür
/// eine Bibliothek anzulegen.
///
/// **Was sie ausdrücklich nicht tut:** zusammenführen. Jede eingelesene
/// Person wird neu angelegt. Ein Programm, das selbsttätig entscheidet,
/// welche zwei Großmütter dieselbe sind, liegt irgendwann falsch – und
/// eine falsch verschmolzene Person ist nicht mehr zu trennen. Statt
/// dessen liefert [moeglicheDoppelte] eine Liste zum Nachsehen.
library;

import 'dart:convert';

import 'lebenslauf.dart';
import 'stammbaum.dart';
import 'verwandtschaftsgrad.dart';

/// Warum eine Datei gar nicht erst gelesen wurde.
enum GedcomAbbruch {
  /// Kein `0 HEAD` am Anfang – das ist keine GEDCOM-Datei.
  keinKopf,

  /// Eine Kodierung, die diese App nicht sicher entziffern kann. Die
  /// Einzelheit nennt sie beim Namen (etwa `ANSEL`).
  kodierung,

  /// Lesbar, aber ohne eine einzige Person.
  keinePersonen,
}

/// Geworfen, wenn die Datei unbrauchbar ist.
///
/// Trägt einen **Typ**, keinen fertigen Satz: Die Übersetzung gehört in
/// die Oberfläche, sonst stünde hier deutscher Text in einer englischen
/// App.
class GedcomAbbruchFehler implements Exception {
  final GedcomAbbruch grund;

  /// Nur bei [GedcomAbbruch.kodierung] gesetzt – der Name der Kodierung,
  /// wie er im Kopf der Datei stand.
  final String? einzelheit;

  const GedcomAbbruchFehler(this.grund, [this.einzelheit]);

  @override
  String toString() => 'GedcomAbbruchFehler($grund, $einzelheit)';
}

/// Was beim Einlesen auffiel, ohne es zu verhindern.
enum GedcomHinweisart {
  /// `ABT 1900`, `BEF 1912`, `BET 1900 AND 1910`. Die App führt ein
  /// volles Datum; aus „etwa 1900" eines zu machen wäre erfundene
  /// Genauigkeit. Der Wortlaut steht deshalb im Bericht und nicht in
  /// der Spalte.
  ungenauesDatum,

  /// Ein Eintrag, den diese App nicht führt – Quellenangaben,
  /// Anmerkungen, Bilder, programmeigene Sondertags.
  uebersprungen,

  /// Eine Verwandtschaft, die einen Kreis geschlossen hätte („jemand
  /// ist sein eigener Großvater"). Nicht übernommen; jede Auswertung
  /// nach oben liefe sonst endlos.
  kreisVerhindert,

  /// Eine Person ohne `NAME`. Sie wird trotzdem angelegt – sie hängt an
  /// Verwandtschaften, die sonst mitverschwänden.
  ohneNamen,
}

typedef GedcomHinweis = ({GedcomHinweisart art, String einzelheit});

/// Ein Ereignis, wie die Datei es liefert – noch ohne Kennung und ohne
/// Personenbezug aus der Datenbank.
typedef GedcomEreignis = ({
  Ereignisart art,
  DateTime? datum,
  String? ort,
  String? notiz,
});

/// Eine eingelesene Person. [kennung] ist die Verweisnummer aus der
/// Datei (`@I1@` ohne die Klammeraffen), nicht die spätere Kennung in
/// der Datenbank – die vergibt der Aufrufer.
class GedcomImportPerson {
  final String kennung;
  final String name;
  final Geschlecht? geschlecht;
  final DateTime? geburt;
  final DateTime? tod;
  final List<GedcomEreignis> ereignisse;

  const GedcomImportPerson({
    required this.kennung,
    required this.name,
    this.geschlecht,
    this.geburt,
    this.tod,
    this.ereignisse = const [],
  });
}

/// Das Ergebnis eines Durchgangs.
class GedcomEingelesen {
  final List<GedcomImportPerson> personen;

  /// Verwandtschaften, **in den Kennungen der Datei**. Bereits gegen
  /// Kreise geprüft.
  final List<Kante> kanten;

  final List<GedcomHinweis> hinweise;

  const GedcomEingelesen({
    required this.personen,
    required this.kanten,
    required this.hinweise,
  });

  int get anzahlEreignisse =>
      personen.fold(0, (s, p) => s + p.ereignisse.length);

  /// Wie oft eine Hinweisart vorkam – für den Bericht, der Zahlen nennt
  /// und nicht hundert Zeilen.
  int hinweiseMit(GedcomHinweisart art) =>
      hinweise.where((h) => h.art == art).length;
}

/// Beschriftungen für die Ereignisse, die diese App nicht als eigene Art
/// führt.
///
/// Von außen hereingegeben und nicht hier festgeschrieben: Der Dienst
/// bleibt ohne Oberfläche prüfbar, und die Notiz steht trotzdem in der
/// Sprache, die der Nutzer eingestellt hat.
typedef GedcomBezeichnungen = ({
  String geburtsort,
  String sterbeort,
  String taufe,
  String bestattung,
  String ohneNamen,
});

/// Die Bezeichnungen für Tests – deutsch, aber ohne Übersetzungsapparat.
const gedcomBezeichnungenTest = (
  geburtsort: 'Geburtsort',
  sterbeort: 'Sterbeort',
  taufe: 'Taufe',
  bestattung: 'Bestattung',
  ohneNamen: 'Ohne Namen',
);

// ---------------------------------------------------------------------
// Kodierung
// ---------------------------------------------------------------------

/// Die 32 Zeichen, in denen sich CP1252 von Latin-1 unterscheidet.
///
/// Ohne diese Tabelle würden Anführungszeichen und Gedankenstriche aus
/// Windows-Programmen zu Steuerzeichen. Es sind zweiunddreißig Einträge –
/// billiger als jede falsche Ausrede.
const _cp1252 = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
];

String _ausCp1252(List<int> bytes) => String.fromCharCodes([
      for (final b in bytes) (b >= 0x80 && b <= 0x9F) ? _cp1252[b - 0x80] : b,
    ]);

/// Liest den Kopf der Datei, um die Kodierung zu erfahren – und zwar
/// bevor der Rest entziffert wird.
///
/// Ein Henne-Ei-Fall: Die Angabe steht *in* der Datei. Der Kopf besteht
/// aber nur aus ASCII, deshalb genügt für diesen einen Blick eine
/// beliebige ASCII-verträgliche Deutung.
String? _kodierungImKopf(List<int> bytes) {
  final probe = _ausCp1252(bytes.take(4096).toList());
  for (final zeile in const LineSplitter().convert(probe)) {
    final z = _zeile(zeile);
    if (z == null) continue;
    if (z.ebene == 0 && z.tag != 'HEAD') break;
    if (z.ebene == 1 && z.tag == 'CHAR') return z.wert.trim().toUpperCase();
  }
  return null;
}

/// Entziffert die Bytes nach der Angabe im Kopf.
///
/// **ANSEL wird abgelehnt, nicht geraten.** Das ist eine
/// Bibliothekskodierung aus den Achtzigern, in der alte Dateien
/// tatsächlich vorliegen; sie legt diakritische Zeichen *vor* den
/// Buchstaben. Halb entzifferte Namen sind schlimmer als ein ehrliches
/// Nein – ein zerschossener Nachname fällt niemandem mehr auf, wenn er
/// erst einmal in der Datenbank steht.
String entziffere(List<int> bytes) {
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    throw const GedcomAbbruchFehler(GedcomAbbruch.kodierung, 'UTF-16');
  }
  var roh = bytes;
  if (roh.length >= 3 && roh[0] == 0xEF && roh[1] == 0xBB && roh[2] == 0xBF) {
    roh = roh.sublist(3);
  }
  final angabe = _kodierungImKopf(roh);
  if (angabe != null && angabe.startsWith('ANSEL')) {
    throw const GedcomAbbruchFehler(GedcomAbbruch.kodierung, 'ANSEL');
  }
  if (angabe != null && angabe.startsWith('UNICODE')) {
    // In 5.5.1 heißt „UNICODE" UTF-16. Ohne Byte-Marke ist nicht
    // entscheidbar, in welcher Reihenfolge – also nicht raten.
    throw const GedcomAbbruchFehler(GedcomAbbruch.kodierung, 'UNICODE');
  }
  final istAnsi = angabe != null &&
      (angabe.startsWith('ANSI') ||
          angabe.contains('1252') ||
          angabe.startsWith('IBM') ||
          angabe.startsWith('LATIN'));
  if (istAnsi) return _ausCp1252(roh);
  // Voreinstellung ist UTF-8, auch wenn der Kopf schweigt. Fällt das
  // durch, war die Angabe falsch – dann ist CP1252 die einzige
  // Deutung, die nirgends wirft.
  try {
    return utf8.decode(roh);
  } on FormatException {
    return _ausCp1252(roh);
  }
}

// ---------------------------------------------------------------------
// Zeilen und Bäume
// ---------------------------------------------------------------------

typedef _Zeile = ({int ebene, String? kennung, String tag, String wert});

/// Zerlegt `<Ebene> <@Kennung@>? <Tag> <Wert>`.
///
/// Von Hand und nicht mit einem regulären Ausdruck: Der Wert darf alles
/// enthalten, auch Klammeraffen (Netzadressen) und mehrfache
/// Leerzeichen. Ein Ausdruck, der das alles abdeckt, ist unlesbar.
_Zeile? _zeile(String roh) {
  final s = roh.trim();
  if (s.isEmpty) return null;
  var i = 0;
  while (i < s.length && s.codeUnitAt(i) >= 0x30 && s.codeUnitAt(i) <= 0x39) {
    i++;
  }
  if (i == 0) return null; // ohne Ebene ist es keine GEDCOM-Zeile
  final ebene = int.parse(s.substring(0, i));
  var rest = s.substring(i).trimLeft();
  String? kennung;
  if (rest.startsWith('@')) {
    final ende = rest.indexOf('@', 1);
    if (ende > 1) {
      kennung = rest.substring(1, ende);
      rest = rest.substring(ende + 1).trimLeft();
    }
  }
  if (rest.isEmpty) return null;
  final leer = rest.indexOf(' ');
  final tag = (leer < 0 ? rest : rest.substring(0, leer)).toUpperCase();
  final wert = leer < 0 ? '' : rest.substring(leer + 1);
  return (ebene: ebene, kennung: kennung, tag: tag, wert: wert);
}

/// Ein Eintrag mit seinen Untereinträgen.
class _Knoten {
  final String tag;
  final String? kennung;
  String wert;
  final List<_Knoten> kinder = [];
  _Knoten(this.tag, this.wert, [this.kennung]);

  _Knoten? kind(String tag) {
    for (final k in kinder) {
      if (k.tag == tag) return k;
    }
    return null;
  }

  Iterable<_Knoten> alle(String tag) => kinder.where((k) => k.tag == tag);
  String? wertVon(String tag) {
    final w = kind(tag)?.wert.trim();
    return (w == null || w.isEmpty) ? null : w;
  }
}

/// Baut aus den Zeilen die Datensätze der Ebene 0.
///
/// Das ist der Zustandsautomat, von dem der Plan sprach: ein Stapel über
/// die Ebenen. `CONC` und `CONT` sind keine eigenen Einträge, sondern
/// Fortsetzungen des darüberliegenden Wertes – lange Anmerkungen werden
/// im Format auf mehrere Zeilen verteilt.
List<_Knoten> _datensaetze(String inhalt) {
  final ergebnis = <_Knoten>[];
  final stapel = <_Knoten>[];
  for (final roh in const LineSplitter().convert(inhalt)) {
    final z = _zeile(roh);
    if (z == null) continue;
    if (z.tag == 'CONC' || z.tag == 'CONT') {
      if (stapel.isEmpty) continue;
      // Die Fortsetzung gehört an den Eintrag EINE Ebene darüber, nicht
      // an den zuletzt gesehenen: Zwischen Wert und Fortsetzung kann ein
      // tieferer Eintrag stehen.
      final ziel = z.ebene - 1 < stapel.length ? stapel[z.ebene - 1] : stapel.last;
      ziel.wert += (z.tag == 'CONT' ? '\n' : '') + z.wert;
      continue;
    }
    final knoten = _Knoten(z.tag, z.wert, z.kennung);
    if (z.ebene == 0) {
      stapel
        ..clear()
        ..add(knoten);
      ergebnis.add(knoten);
      continue;
    }
    // Eine Datei mit übersprungenen Ebenen ist kaputt; sie an die
    // tiefstmögliche Stelle zu hängen ist besser als sie wegzuwerfen.
    while (stapel.length > z.ebene) {
      stapel.removeLast();
    }
    if (stapel.isEmpty) continue;
    stapel.last.kinder.add(knoten);
    stapel.add(knoten);
  }
  return ergebnis;
}

// ---------------------------------------------------------------------
// Daten und Namen
// ---------------------------------------------------------------------

const _monate = {
  'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6, //
  'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
};

/// Die Wörter, die eine Angabe zur Schätzung machen.
const _ungenau = {
  'ABT', 'ABOUT', 'CAL', 'EST', 'BEF', 'BEFORE', 'AFT', 'AFTER', //
  'BET', 'BETWEEN', 'FROM', 'TO', 'INT',
};

/// Deutet eine `DATE`-Zeile.
///
/// `datum` ist gesetzt, wenn die Angabe genau genug war: voller Tag,
/// Monat und Jahr, oder Monat und Jahr, oder ein reines Jahr. Fehlendes
/// wird auf den Ersten gesetzt – dieselbe Regel, nach der die App
/// Jahresangaben ohnehin speichert.
///
/// `ungenau` ist gesetzt, wenn etwas dastand, das sich nicht übernehmen
/// ließ. Beides zugleich gibt es nicht.
({DateTime? datum, bool ungenau}) deuteDatum(String roh) {
  var s = roh.trim().toUpperCase();
  if (s.isEmpty) return (datum: null, ungenau: false);
  // Vorangestellte Kalenderangabe, etwa `@#DGREGORIAN@ 12 MAY 1875`.
  if (s.startsWith('@#')) {
    final e = s.indexOf('@', 2);
    if (e > 0) s = s.substring(e + 1).trim();
  }
  final teile = s.split(RegExp(r'\s+'));
  if (teile.isEmpty) return (datum: null, ungenau: false);
  if (_ungenau.contains(teile.first)) return (datum: null, ungenau: true);
  // Doppeljahre („1750/51") und Zeitrechnungen vor Christus kann diese
  // App nicht führen.
  if (s.contains('/') || s.contains('B.C.') || teile.last == 'BC') {
    return (datum: null, ungenau: true);
  }
  int? jahr(String t) => int.tryParse(t);
  switch (teile.length) {
    case 1:
      final j = jahr(teile[0]);
      return j == null
          ? (datum: null, ungenau: true)
          : (datum: DateTime(j), ungenau: false);
    case 2:
      final m = _monate[teile[0]];
      final j = jahr(teile[1]);
      return (m == null || j == null)
          ? (datum: null, ungenau: true)
          : (datum: DateTime(j, m), ungenau: false);
    case 3:
      final t = jahr(teile[0]);
      final m = _monate[teile[1]];
      final j = jahr(teile[2]);
      if (t == null || m == null || j == null || t < 1 || t > 31) {
        return (datum: null, ungenau: true);
      }
      return (datum: DateTime(j, m, t), ungenau: false);
    default:
      return (datum: null, ungenau: true);
  }
}

/// Setzt einen Namen aus der GEDCOM-Form wieder zusammen.
///
/// `Anna /Meier/` wird zu „Anna Meier". Die Schrägstriche klammern den
/// Nachnamen; was davor und dahinter steht, gehört ebenfalls zum Namen
/// (Namenszusätze stehen bei manchen Programmen hinter dem Nachnamen).
/// `GIVN`/`SURN` gelten nur, wenn die Zeile selbst leer blieb – manche
/// Programme schreiben beides, und dann wäre es doppelt.
String deuteName(String roh, {String? givn, String? surn}) {
  final s = roh.trim();
  var zusammen = s;
  if (s.contains('/')) {
    final erste = s.indexOf('/');
    final zweite = s.indexOf('/', erste + 1);
    final vor = s.substring(0, erste).trim();
    final nach =
        (zweite > erste ? s.substring(erste + 1, zweite) : s.substring(erste + 1))
            .trim();
    final danach = zweite >= 0 ? s.substring(zweite + 1).trim() : '';
    zusammen = [vor, nach, danach].where((e) => e.isNotEmpty).join(' ');
  }
  if (zusammen.isEmpty) {
    zusammen = [givn?.trim() ?? '', surn?.trim() ?? '']
        .where((e) => e.isNotEmpty)
        .join(' ');
  }
  return zusammen.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------
// Der Durchgang
// ---------------------------------------------------------------------

/// Wie ein `FAMC`-Verweis zu lesen ist. GEDCOM hängt die Angabe an die
/// **Verbindung zur Familie**, nicht an den einzelnen Elternteil – ein
/// Kind, das nur von einem der beiden adoptiert wurde, lässt sich im
/// Format nicht ausdrücken.
Verwandtschaft _artAusPedi(String? pedi) => switch (pedi?.trim().toLowerCase()) {
      'adopted' => Verwandtschaft.adoptivelternteil,
      'foster' => Verwandtschaft.pflegeelternteil,
      _ => Verwandtschaft.elternteil,
    };

/// Die Ereignis-Tags, die sich auf eine Art dieser App abbilden lassen.
const _ereignisTags = {
  'MARR': Ereignisart.hochzeit,
  'RESI': Ereignisart.umzug,
  'OCCU': Ereignisart.beruf,
  'EDUC': Ereignisart.ausbildung,
  'GRAD': Ereignisart.ausbildung,
};

/// Tags, die diese App bewusst nicht führt und die deshalb auch nicht in
/// den Bericht müssen – sie stünden dort hundertfach und verdeckten das
/// Wesentliche.
const _stilleTags = {
  'HEAD', 'TRLR', 'SUBM', 'SUBN', 'CHAN', 'RIN', '_UID', 'UID', //
  'FAMC', 'FAMS', 'NAME', 'SEX', 'BIRT', 'DEAT',
};

/// Liest eine vollständige GEDCOM-Datei.
///
/// Wirft [GedcomAbbruchFehler], wenn die Datei unbrauchbar ist. Alles
/// andere – unbekannte Tags, ungenaue Daten, Kreise – landet in den
/// Hinweisen, und der Rest wird trotzdem übernommen. Eine fremde Datei
/// wegen eines einzigen Sondertags abzulehnen hieße, die brauchbaren
/// dreihundert Personen mit wegzuwerfen.
GedcomEingelesen liesGedcom(
  List<int> bytes, {
  required GedcomBezeichnungen texte,
}) {
  final inhalt = entziffere(bytes);
  final saetze = _datensaetze(inhalt);
  if (saetze.isEmpty || saetze.first.tag != 'HEAD') {
    throw const GedcomAbbruchFehler(GedcomAbbruch.keinKopf);
  }

  final hinweise = <GedcomHinweis>[];
  final personen = <GedcomImportPerson>[];
  final ereignisseJePerson = <String, List<GedcomEreignis>>{};
  final bekannt = <String>{};

  void ungenau(String wo, String wert) => hinweise
      .add((art: GedcomHinweisart.ungenauesDatum, einzelheit: '$wo: $wert'));

  // --- Personen -----------------------------------------------------
  for (final satz in saetze.where((s) => s.tag == 'INDI')) {
    final kennung = satz.kennung;
    if (kennung == null || !bekannt.add(kennung)) continue;

    final nameKnoten = satz.kind('NAME');
    var name = nameKnoten == null
        ? ''
        : deuteName(nameKnoten.wert,
            givn: nameKnoten.wertVon('GIVN'), surn: nameKnoten.wertVon('SURN'));
    if (name.isEmpty) {
      name = texte.ohneNamen;
      hinweise.add((art: GedcomHinweisart.ohneNamen, einzelheit: kennung));
    }

    DateTime? datumAus(_Knoten? e, String wo) {
      final roh = e?.wertVon('DATE');
      if (roh == null) return null;
      final d = deuteDatum(roh);
      if (d.ungenau) ungenau('$name – $wo', roh.trim());
      return d.datum;
    }

    final geburtKnoten = satz.kind('BIRT');
    final todKnoten = satz.kind('DEAT');
    final geburt = datumAus(geburtKnoten, 'BIRT');
    final tod = datumAus(todKnoten, 'DEAT');

    final ereignisse = <GedcomEreignis>[];

    // Geburts- und Sterbeort haben in dieser App keine eigene Spalte:
    // Geburt und Tod stehen als Datum an der Person. Der Ort ginge damit
    // verloren – gerade der, der am häufigsten in fremden Dateien steht.
    // Er wird deshalb als Ereignis geführt, mit dem Datum daneben, und
    // landet so auf Karte und Globus.
    void ortsEreignis(_Knoten? knoten, String beschriftung, DateTime? datum) {
      final ort = knoten?.wertVon('PLAC');
      if (ort == null) return;
      ereignisse.add((
        art: Ereignisart.sonstiges,
        datum: datum,
        ort: ort,
        notiz: beschriftung,
      ));
    }

    ortsEreignis(geburtKnoten, texte.geburtsort, geburt);
    ortsEreignis(todKnoten, texte.sterbeort, tod);

    for (final e in satz.kinder) {
      if (e.tag == 'CHR' || e.tag == 'BAPM') {
        ortsEreignis(e, texte.taufe, datumAus(e, e.tag));
        continue;
      }
      if (e.tag == 'BURI') {
        ortsEreignis(e, texte.bestattung, datumAus(e, e.tag));
        continue;
      }
      final art = _ereignisTags[e.tag];
      if (art != null) {
        final wert = e.wert.trim();
        ereignisse.add((
          art: art,
          datum: datumAus(e, e.tag),
          ort: e.wertVon('PLAC'),
          notiz: wert.isEmpty ? null : wert,
        ));
        continue;
      }
      if (!_stilleTags.contains(e.tag)) {
        hinweise.add((
          art: GedcomHinweisart.uebersprungen,
          einzelheit: '$name – ${e.tag}',
        ));
      }
    }

    // Dieselbe Liste, die auch in der Person steckt – absichtlich. Die
    // Hochzeit steht in GEDCOM an der Familie und ist erst weiter unten
    // zu haben; über diese Zuordnung findet sie zurück zur Person.
    ereignisseJePerson[kennung] = ereignisse;
    personen.add(GedcomImportPerson(
      kennung: kennung,
      name: name,
      geschlecht: switch (satz.wertVon('SEX')?.toUpperCase()) {
        'M' => Geschlecht.maennlich,
        'F' => Geschlecht.weiblich,
        _ => null,
      },
      geburt: geburt,
      tod: tod,
      ereignisse: ereignisse,
    ));
  }

  if (personen.isEmpty) {
    throw const GedcomAbbruchFehler(GedcomAbbruch.keinePersonen);
  }

  // Wie ein Kind seine Familie sieht: `2 PEDI adopted` steht beim Kind,
  // nicht bei der Familie. Deshalb erst hier einsammeln.
  final pediJeKindUndFamilie = <String, String>{};
  for (final satz in saetze.where((s) => s.tag == 'INDI')) {
    final kennung = satz.kennung;
    if (kennung == null) continue;
    for (final famc in satz.alle('FAMC')) {
      final fam = _verweis(famc.wert);
      final pedi = famc.wertVon('PEDI');
      if (fam != null && pedi != null) {
        pediJeKindUndFamilie['$kennung|$fam'] = pedi;
      }
    }
  }

  // --- Familien zurück auf Kanten -----------------------------------
  final namen = {for (final p in personen) p.kennung: p.name};
  final kanten = <Kante>[];
  final netz = Verwandtschaftsnetz(const []);

  void versuche(String a, String b, Verwandtschaft art) {
    final fehler = pruefeBeziehung(netz, a, b, art);
    if (fehler == Beziehungsfehler.schonVorhanden) return;
    if (fehler != null) {
      hinweise.add((
        art: GedcomHinweisart.kreisVerhindert,
        einzelheit: '${namen[a] ?? a} – ${namen[b] ?? b}',
      ));
      return;
    }
    final neu = art == Verwandtschaft.partner
        ? partnerKanteFuer(a, b)
        : kante(a, b, art);
    kanten.add(neu);
    // Gegen den fortgeschriebenen Stand geprüft, nicht gegen den
    // Anfangszustand: Zwei Kanten derselben Datei können gemeinsam einen
    // Kreis schließen, den keine für sich geschlossen hätte.
    netz.ergaenze(neu);
  }

  for (final satz in saetze.where((s) => s.tag == 'FAM')) {
    final eltern = [
      for (final tag in ['HUSB', 'WIFE'])
        for (final e in satz.alle(tag))
          if (_verweis(e.wert) case final id?)
            if (bekannt.contains(id)) id,
    ];
    for (var i = 0; i < eltern.length; i++) {
      for (var j = i + 1; j < eltern.length; j++) {
        versuche(eltern[i], eltern[j], Verwandtschaft.partner);
      }
    }
    for (final c in satz.alle('CHIL')) {
      final kind = _verweis(c.wert);
      if (kind == null || !bekannt.contains(kind)) continue;
      final art = _artAusPedi(
          satz.kennung == null ? null : pediJeKindUndFamilie['$kind|${satz.kennung}']);
      for (final e in eltern) {
        versuche(kind, e, art);
      }
    }
    // Die Hochzeit steht in GEDCOM an der Familie, in dieser App an der
    // Person. Sie wird deshalb beiden Partnern zugeschrieben – nicht
    // einem, denn welchem?
    final marr = satz.kind('MARR');
    if (marr != null && eltern.isNotEmpty) {
      final roh = marr.wertVon('DATE');
      DateTime? datum;
      if (roh != null) {
        final d = deuteDatum(roh);
        if (d.ungenau) ungenau('MARR', roh.trim());
        datum = d.datum;
      }
      final ort = marr.wertVon('PLAC');
      if (datum != null || ort != null) {
        for (final e in eltern) {
          ereignisseJePerson[e]?.add((
            art: Ereignisart.hochzeit,
            datum: datum,
            ort: ort,
            notiz: null,
          ));
        }
      }
    }
  }

  return GedcomEingelesen(
    personen: personen,
    kanten: kanten,
    hinweise: hinweise,
  );
}

/// Setzt die Kennungen der Datei auf die endgültigen der Datenbank um.
///
/// Der Grund, warum das eine eigene Funktion ist und nicht drei Zeilen im
/// Bildschirm: Eine **Partnerkante wird dabei neu ausgerichtet**. Ihre
/// gespeicherte Form hat die kleinere Kennung vorn (siehe
/// [partnerKanteFuer]) – nach dem Umsetzen ist das eine andere als
/// vorher. Bliebe die alte Reihenfolge stehen, entstünde eine Zeile, die
/// das Auflösen der Partnerschaft später nicht mehr findet, und niemand
/// sähe der Datenbank an, warum.
///
/// Kanten, deren Enden nicht in [neueKennungen] stehen, fallen weg.
List<Kante> mitNeuenKennungen(
  List<Kante> kanten,
  Map<String, String> neueKennungen,
) =>
    [
      for (final k in kanten)
        if (neueKennungen[k.personId] case final a?)
          if (neueKennungen[k.andereId] case final b?)
            if (k.art == Verwandtschaft.partner)
              partnerKanteFuer(a, b)
            else
              kante(a, b, k.art),
    ];

/// Zieht `@I1@` auf `I1` zusammen. Gibt `null` zurück, wenn dort kein
/// Verweis stand – manche Programme schreiben freien Text.
String? _verweis(String wert) {
  final s = wert.trim();
  if (!s.startsWith('@') || !s.endsWith('@') || s.length < 3) return null;
  return s.substring(1, s.length - 1);
}

// ---------------------------------------------------------------------
// Doppelte
// ---------------------------------------------------------------------

typedef Vergleichsperson = ({String kennung, String name, DateTime? geburt});

/// Ein Verdacht – kein Befund.
typedef Doppelverdacht = ({
  String neueKennung,
  String bestehendeKennung,
  String name,
});

String _vergleichbar(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Stellt zusammen, welche eingelesene Person einer bestehenden gleichen
/// **könnte**.
///
/// Gleicher Name und gleiches Geburtsjahr – oder gleicher Name und bei
/// beiden gar kein Geburtsjahr. Der zweite Fall ist der schwächere und
/// steht trotzdem mit dabei: Bei Urgroßeltern kennt kaum jemand das Jahr,
/// und genau dort passiert das doppelte Anlegen.
///
/// Diese Liste wird **angezeigt, nicht angewendet**. Zusammenführen ist
/// eine Entscheidung, die ein Mensch trifft – dafür gibt es den
/// Zusammenführen-Weg im Personen-Bildschirm.
List<Doppelverdacht> moeglicheDoppelte(
  List<Vergleichsperson> neue,
  List<Vergleichsperson> bestehende,
) {
  final nachName = <String, List<Vergleichsperson>>{};
  for (final b in bestehende) {
    nachName.putIfAbsent(_vergleichbar(b.name), () => []).add(b);
  }
  final ergebnis = <Doppelverdacht>[];
  for (final n in neue) {
    for (final b in nachName[_vergleichbar(n.name)] ?? const []) {
      final gleichesJahr = n.geburt?.year == b.geburt?.year;
      if (!gleichesJahr) continue;
      ergebnis.add((
        neueKennung: n.kennung,
        bestehendeKennung: b.kennung,
        name: n.name,
      ));
    }
  }
  return ergebnis;
}

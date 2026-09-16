/// Export nach GEDCOM 5.5.1 – dem Austauschformat der Ahnenforschung.
///
/// Der Grund für diese Datei ist nicht Vollständigkeit, sondern der
/// Ausgang: Ohne sie sind die eingetragenen Verwandtschaften in dieser
/// App gefangen. Fotos lassen sich immer noch kopieren, ein
/// Verwandtschaftsnetz nicht.
///
/// Geschrieben wird bewusst nur, was die App auch führt – Namen,
/// Geschlecht, Lebensdaten, Eltern-Kind- und Partnerbeziehungen. Felder
/// zu erfinden, die es hier nicht gibt, machte die Datei größer und die
/// Angaben unsicherer.
library;

import 'stammbaum.dart';
import 'verwandtschaftsgrad.dart';

/// Die Dateiendung des Formats.
const gedcomEndung = '.ged';

/// Dieselbe Endung ohne Punkt – so verlangt sie der Dateidialog.
const gedcomEndungOhnePunkt = 'ged';

/// Vorgeschlagener Dateiname im Speichern-Dialog.
const gedcomDateiname = 'stammbaum$gedcomEndung';

/// Was im Kopf der Datei als erzeugendes Programm steht. Kein
/// Oberflächentext – ein lesendes Programm wertet ihn aus, er darf sich
/// nicht mit der Sprache ändern.
const gedcomErzeuger = 'PhotoVault';

/// Hängt die Endung an, falls der Dialog sie nicht mitgeliefert hat.
String mitEndung(String pfad) =>
    pfad.toLowerCase().endsWith(gedcomEndung) ? pfad : '$pfad$gedcomEndung';

/// Eine Person, wie der Export sie braucht – ohne Datenbankklasse, damit
/// sich das Format ohne Datenbank prüfen lässt.
typedef GedcomPerson = ({
  String id,
  String name,
  Geschlecht? geschlecht,
  DateTime? geburt,
  DateTime? tod,
});

/// Die Monatskürzel, die GEDCOM vorschreibt – englisch und dreistellig,
/// unabhängig von der Oberflächensprache.
const _monate = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

String _datum(DateTime d) => '${d.day} ${_monate[d.month - 1]} ${d.year}';

/// Der GEDCOM-Wert für eine Elternart – `null` für die leibliche, die
/// im Format die Voreinstellung ist und deshalb nicht dasteht.
String? _pedi(Verwandtschaft? art) => switch (art) {
      Verwandtschaft.adoptivelternteil => 'adopted',
      Verwandtschaft.pflegeelternteil => 'foster',
      _ => null,
    };

/// Zerlegt einen Namen in die GEDCOM-Form `Vorname /Nachname/`.
///
/// Die App führt nur ein einziges Namensfeld – „Anna Meier" oder auch
/// „Oma". Als Nachname gilt deshalb das letzte Wort, sofern es mehr als
/// eines gibt; sonst bleibt der Nachname leer. Das ist eine Vermutung,
/// aber die einzige, die ohne zusätzliche Eingabe möglich ist, und sie
/// ist umkehrbar: Ein Programm, das die Datei liest, bekommt denselben
/// Text zurück.
String gedcomName(String name) {
  final teile = name.trim().split(RegExp(r'\s+'));
  if (teile.length < 2) return '$name //';
  final nach = teile.removeLast();
  return '${teile.join(' ')} /$nach/';
}

/// Eine Familie im Sinne von GEDCOM: ein Elternpaar (oder ein einzelner
/// Elternteil) und die gemeinsamen Kinder.
///
/// GEDCOM kennt Personen und Familien, nicht Kanten. Die Umrechnung ist
/// der eigentliche Inhalt dieses Exports: Kinder werden nach ihrer
/// **Elternmenge** gruppiert – wer dieselben Eltern hat, landet in
/// derselben Familie. Ein Paar ohne gemeinsame Kinder bekommt trotzdem
/// eine, sonst ginge die Partnerschaft verloren.
class GedcomFamilie {
  final List<String> eltern;
  final List<String> kinder;
  const GedcomFamilie(this.eltern, this.kinder);
}

/// Stellt die Familien aus dem Verwandtschaftsnetz zusammen.
List<GedcomFamilie> familien(
  Verwandtschaftsnetz netz,
  List<String> personen,
) {
  final nachEltern = <String, List<String>>{};
  final elternMengen = <String, List<String>>{};

  for (final id in personen) {
    final eltern = netz.eltern(id).toList()..sort();
    if (eltern.isEmpty) continue;
    final schluessel = eltern.join(' ');
    nachEltern.putIfAbsent(schluessel, () => []).add(id);
    elternMengen[schluessel] = eltern;
  }

  final ergebnis = <GedcomFamilie>[
    for (final e in nachEltern.entries)
      GedcomFamilie(elternMengen[e.key]!, e.value..sort()),
  ];

  // Paare, die in keiner der obigen Familien gemeinsam auftauchen.
  final schonPaar = <String>{
    for (final f in ergebnis)
      if (f.eltern.length == 2) f.eltern.join(' '),
  };
  final gesehen = <String>{};
  for (final id in personen) {
    for (final p in netz.partner(id)) {
      final paar = [id, p]..sort();
      final schluessel = paar.join(' ');
      if (!gesehen.add(schluessel)) continue;
      if (schonPaar.contains(schluessel)) continue;
      ergebnis.add(GedcomFamilie(paar, const []));
    }
  }
  return ergebnis;
}

/// Schreibt die vollständige GEDCOM-Datei.
///
/// [erzeuger] steht im Kopf und sagt dem lesenden Programm, woher die
/// Datei stammt.
String schreibeGedcom(
  List<GedcomPerson> personen,
  Verwandtschaftsnetz netz, {
  required String erzeuger,
  required String version,
}) {
  final zeilen = <String>[];
  final kennung = <String, String>{
    for (var i = 0; i < personen.length; i++) personen[i].id: 'I${i + 1}',
  };

  zeilen.addAll([
    '0 HEAD',
    '1 SOUR $erzeuger',
    '2 VERS $version',
    '1 GEDC',
    '2 VERS 5.5.1',
    '2 FORM LINEAGE-LINKED',
    // UTF-8 ist in 5.5.1 zugelassen und die einzige Kodierung, in der
    // deutsche Namen unbeschädigt ankommen.
    '1 CHAR UTF-8',
  ]);

  final fam = familien(netz, [for (final p in personen) p.id]);
  // Je Person: in welchen Familien sie Kind bzw. Elternteil ist.
  final alsKind = <String, List<int>>{};
  final alsElternteil = <String, List<int>>{};
  for (var i = 0; i < fam.length; i++) {
    for (final e in fam[i].eltern) {
      alsElternteil.putIfAbsent(e, () => []).add(i);
    }
    for (final k in fam[i].kinder) {
      alsKind.putIfAbsent(k, () => []).add(i);
    }
  }

  for (final p in personen) {
    final id = kennung[p.id]!;
    zeilen.add('0 @$id@ INDI');
    zeilen.add('1 NAME ${gedcomName(p.name)}');
    final sex = switch (p.geschlecht) {
      Geschlecht.weiblich => 'F',
      Geschlecht.maennlich => 'M',
      // GEDCOM kennt nur F, M und U („unknown"). „Divers" und „nicht
      // angegeben" landen beide auf U – das Format bietet nichts anderes,
      // und ein erfundener Wert würde von keinem Programm gelesen.
      _ => 'U',
    };
    zeilen.add('1 SEX $sex');
    if (p.geburt != null) {
      zeilen.add('1 BIRT');
      zeilen.add('2 DATE ${_datum(p.geburt!)}');
    }
    if (p.tod != null) {
      zeilen.add('1 DEAT');
      zeilen.add('2 DATE ${_datum(p.tod!)}');
    }
    for (final i in alsKind[p.id] ?? const <int>[]) {
      zeilen.add('1 FAMC @F${i + 1}@');
      // Adoptiv- und Pflegekanten. Ohne diese Zeile ginge beim Ausgeben
      // verloren, was die App eigens unterscheidet – und ein Rundlauf
      // durch Ausgeben und Wiedereinlesen käme mit leiblichen Eltern
      // zurück.
      //
      // GEDCOM hängt die Angabe an die Verbindung zur **Familie**, nicht
      // an den einzelnen Elternteil. Ein Kind, das nur von einem der
      // beiden adoptiert wurde, lässt sich im Format nicht ausdrücken;
      // dann bleibt die Zeile weg, statt eine Hälfte zur ganzen Wahrheit
      // zu erklären.
      final arten = {
        for (final e in fam[i].eltern) netz.elternArt(p.id, e),
      };
      final pedi = arten.length == 1 ? _pedi(arten.first) : null;
      if (pedi != null) zeilen.add('2 PEDI $pedi');
    }
    for (final i in alsElternteil[p.id] ?? const <int>[]) {
      zeilen.add('1 FAMS @F${i + 1}@');
    }
  }

  final geschlechter = {for (final p in personen) p.id: p.geschlecht};
  for (var i = 0; i < fam.length; i++) {
    zeilen.add('0 @F${i + 1}@ FAM');
    // HUSB und WIFE sind in GEDCOM an das Geschlecht gebunden. Wo es
    // fehlt, bekommt der erste Elternteil HUSB – willkürlich, aber
    // notwendig: Ein FAM-Datensatz ohne beide Rollen verlöre die
    // Zugehörigkeit ganz.
    final eltern = [...fam[i].eltern];
    final frauen = eltern.where((e) => geschlechter[e] == Geschlecht.weiblich);
    final rest = eltern.where((e) => geschlechter[e] != Geschlecht.weiblich);
    var husbGesetzt = false;
    for (final e in [...rest, ...frauen]) {
      final rolle = geschlechter[e] == Geschlecht.weiblich || husbGesetzt
          ? 'WIFE'
          : 'HUSB';
      if (rolle == 'HUSB') husbGesetzt = true;
      zeilen.add('1 $rolle @${kennung[e]}@');
    }
    for (final k in fam[i].kinder) {
      zeilen.add('1 CHIL @${kennung[k]}@');
    }
  }

  zeilen.add('0 TRLR');
  // GEDCOM schreibt Zeilenenden mit CR LF vor. Manche Programme lesen
  // auch LF, aber „manche" ist bei einem Austauschformat zu wenig.
  const ende = '\r\n';
  return zeilen.map((z) => z + ende).join();
}

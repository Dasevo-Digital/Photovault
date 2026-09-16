import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wacht über die Übersetzungsdateien.
///
/// Ein Schlüssel, den es nur auf Deutsch gibt, fällt sonst erst dem Nutzer
/// auf – und zwar als deutscher Satz mitten in einer englischen Oberfläche.
/// `flutter gen-l10n` meldet das zwar in `fehlende_uebersetzungen.txt`, aber
/// nur, wenn jemand hineinsieht.
void main() {
  Map<String, dynamic> lies(String pfad) =>
      jsonDecode(File(pfad).readAsStringSync()) as Map<String, dynamic>;

  /// Die eigentlichen Texte – ohne die `@`-Einträge, die nur Beschreibungen
  /// und Platzhalter-Angaben tragen.
  Set<String> schluessel(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  late Map<String, dynamic> de;
  late Map<String, dynamic> en;

  setUpAll(() {
    de = lies('lib/l10n/app_de.arb');
    en = lies('lib/l10n/app_en.arb');
  });

  test('beide Sprachen kennen dieselben Schlüssel', () {
    final nurDeutsch = schluessel(de).difference(schluessel(en));
    final nurEnglisch = schluessel(en).difference(schluessel(de));

    expect(nurDeutsch, isEmpty,
        reason: 'diese Texte fehlen auf Englisch: ${nurDeutsch.join(', ')}');
    expect(nurEnglisch, isEmpty,
        reason: 'diese Texte gibt es nur auf Englisch: ${nurEnglisch.join(', ')}');
  });

  test('kein Text ist leer geblieben', () {
    for (final arb in [de, en]) {
      for (final k in schluessel(arb)) {
        expect((arb[k] as String).trim(), isNotEmpty, reason: k);
      }
    }
  });

  test('gen-l10n meldet keine fehlende Übersetzung', () {
    // Die Datei wird bei jedem Erzeugungslauf neu geschrieben. Steht dort
    // etwas, ist die letzte Änderung nur halb angekommen.
    final datei = File('lib/l10n/fehlende_uebersetzungen.txt');
    if (!datei.existsSync()) return;
    final inhalt = jsonDecode(datei.readAsStringSync()) as Map<String, dynamic>;
    expect(inhalt, isEmpty,
        reason: 'noch nicht übersetzt: ${inhalt.values.join(', ')}');
  });

  /// Die Platzhalter eines Textbausteins.
  ///
  /// Nicht jede geschweifte Klammer ist einer: In `{geschlecht, select,
  /// w{Schwester} m{Bruder} other{Geschwister}}` ist `geschlecht` der
  /// Platzhalter – `Schwester` und `Bruder` sind übersetzter Text. Die
  /// erste Fassung dieses Wächters nahm alles, was in einer Klammer stand,
  /// und schlug deshalb bei jedem geschlechtsabhängigen Baustein Alarm.
  ///
  /// Unterschieden wird am Zeichen **vor** der Klammer: Eine öffnende
  /// Klammer direkt hinter einem Wortzeichen gehört zu einem ICU-Zweig
  /// (`w{…}`, `=1{…}`, `other{…}`), ihr Inhalt ist Text. Steht davor etwas
  /// anderes – Zeilenanfang, Leerzeichen, Bindestrich, eine weitere
  /// Klammer –, beginnt dort ein echter Platzhalter.
  Set<String> platzhalter(String text) {
    final wortzeichen = RegExp(r'[\w=]');
    final name = RegExp(r'^\s*(\w+)\s*[,}]');
    final gefunden = <String>{};
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '{') continue;
      if (i > 0 && wortzeichen.hasMatch(text[i - 1])) continue;
      final treffer = name.firstMatch(text.substring(i + 1));
      if (treffer != null) gefunden.add(treffer.group(1)!);
    }
    return gefunden;
  }

  test('gleiche Platzhalter in beiden Sprachen', () {
    // Ein Platzhalter, der in einer Sprache fehlt, erzeugt keinen
    // Übersetzungsfehler, sondern einen Satz mit einer Lücke – etwa
    // „Exportiert:" ohne die Dateinamen.
    for (final k in schluessel(de)) {
      expect(platzhalter(en[k] as String), platzhalter(de[k] as String),
          reason: 'unterschiedliche Platzhalter bei „$k"');
    }
  });

  test('Deutsch bleibt die Vorlage', () {
    // Wird die Vorlage vertauscht, entstehen englische Schlüsselnamen und
    // deutsche Texte landen in der Übersetzungsdatei – schwer rückgängig zu
    // machen, wenn es erst später auffällt.
    final konfig = File('l10n.yaml').readAsStringSync();
    expect(konfig, contains('template-arb-file: app_de.arb'));
    expect(de['@@locale'], 'de');
    expect(en['@@locale'], 'en');
  });
}

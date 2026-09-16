import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Wacht darüber, dass in den bereits umgestellten Dateien kein sichtbarer
/// Text mehr fest im Quelltext steht.
///
/// Warum das nötig ist: `flutter analyze` und `flutter gen-l10n` können das
/// nicht bemerken. Beide prüfen nur, was verwendet WIRD – ein Literal, das
/// nie durch [AppTexte] gegangen ist, sieht für sie aus wie jeder andere
/// String. Ein Durchgang gilt damit schnell als fertig, obwohl die Hälfte
/// der Beschriftungen noch deutsch ist; genau das ist beim
/// Einstellungs-Bildschirm passiert und erst beim nächsten Durchsehen
/// aufgefallen.
///
/// Das Verfahren ist bewusst grob: Gesucht wird nach einem String-Literal
/// direkt hinter `Text(` oder hinter einem der Benennungen, unter denen in
/// dieser App sichtbare Texte übergeben werden. Was dabei fälschlich
/// anschlägt, steht unten namentlich in [unbedenklich] – eine Ausnahme, die
/// man aufschreiben muss, fällt beim Lesen auf; eine Ausnahme, die die
/// Heuristik stillschweigend durchlässt, nicht.
void main() {
  /// Dateien, deren Durchgang abgeschlossen ist. Wächst mit jedem weiteren
  /// Durchgang – die noch nicht bearbeiteten stehen bewusst nicht drin,
  /// sonst wäre der Test von Anfang an rot und würde abgeschaltet.
  /// Seit Durchgang 4 ist die Oberfläche vollständig umgestellt – geprüft
  /// wird deshalb ganz `lib/`, statt eine Liste fertiger Dateien zu pflegen.
  /// Ausgenommen sind nur die Dateien, in denen deutscher Text bewusst
  /// stehen bleibt; jede einzelne mit Begründung.
  const ausgenommen = {
    // Das Schlagwort-Vokabular sind Daten, keine Oberfläche. Es steht in der
    // Datenbank und wird beim Sprachwechsel auf Wunsch mit übersetzt.
    'lib/services/ai_tagging_service.dart',
    // `ImportResult.error` wird protokolliert, nie angezeigt.
    'lib/services/import_service.dart',
    // Eine Aufstellung der gebrauchten Kommandozeilenwerkzeuge für
    // Entwickler; nirgends in der Oberfläche.
    'lib/services/platform/desktop_image_tools.dart',
    // Der Satzleser vergleicht EINGABEN gegen deutsche und englische
    // Wörter („Sommer", „letztes Jahr", „grün"). Das sind keine
    // Beschriftungen, sondern die Wörter, die der Nutzer tippt – sie durch
    // AppTexte zu schicken hiesse, dass die App in der englischen
    // Oberfläche kein deutsches „Sommer" mehr verstünde, obwohl beide
    // Sprachen nebeneinander vorkommen. Was ANGEZEIGT wird, entsteht in
    // search_screen.dart und geht dort durch AppTexte.
    'lib/services/suchsatz.dart',
    // Die Ländernamen sind der deutsche Teil eines zweisprachigen
    // Verzeichnisses, keine Beschriftung: Sie stehen dort neben ihrem
    // englischen Gegenstück, und welcher von beiden erscheint, entscheidet
    // `landAnzeige` an der Sprache der Oberfläche. In die ARB-Dateien
    // gehörten sie nicht – dort stünden 250 Schlüssel, die niemand je
    // einzeln anfasst, und der englische Teil käme trotzdem aus GeoNames.
    'lib/services/laendernamen.dart',
  };

  List<String> zuPruefen() {
    final aus = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // Einmal auf Schrägstriche bringen: Windows liefert Backslashes, und
      // damit ging weder der l10n-Ausschluss noch die Ausnahmeliste auf –
      // der Wächter meldete dort erzeugte Sprachdateien und das
      // Schlagwort-Vokabular als Fund.
      final pfad = e.path.replaceAll(r'\', '/');
      if (pfad.endsWith('.g.dart')) continue;
      if (pfad.contains('/l10n/')) continue; // Erzeugnisse und Sprachdateien
      if (ausgenommen.any(pfad.endsWith)) continue;
      aus.add(pfad);
    }
    aus.sort();
    return aus;
  }

  final fertig = zuPruefen();

  /// Literale, die zwar an einer sichtbaren Stelle stehen, aber in jeder
  /// Sprache gleich lauten. Jede Zeile ist eine bewusste Entscheidung.
  const unbedenklich = {
    // Zahl mit Einheit – die Einheiten sind international.
    '500 MB',
    '2 GB',
    '10 GB',
    // Der Produktname wird nicht übersetzt.
    'Photo Vault',
    r'Photo Vault $version',
    // Reine Fortschrittsanzeigen.
    r'${(progress * 100).toStringAsFixed(0)} %',
    r'${(_geoDataProgress * 100).toStringAsFixed(0)} %',
    // Kürzel, die in beiden Sprachen gleich lauten.
    'RGB',
    'LIVE',
    'ISO',
    'Esc',
    // Der Nachweis für die Kartenkacheln ist eine Lizenzauflage und muss
    // wörtlich so dastehen – übersetzt wäre er nicht mehr gültig.
    '© OpenStreetMap contributors',
    '© OpenStreetMap contributors © CARTO',
    '© OpenStreetMap contributors, SRTM | © opentopomap.org (CC-BY-SA)',
    // Eine Kopfzeile fuer eine Antwort, die diese App sich selbst gibt
    // (siehe `Offlinerueckfall`) – HTTP spricht englisch.
    'max-age=0',
    // Bezeichner, die nie jemand liest: Dateiname im Bibliotheksordner,
    // `heroTag` zweier Knöpfe, `ValueKey` dreier Bausteine.
    'vault.key',
    'import-rail',
    'import-bottom',
    'auto-analyse',
    'tonwertkurve-raster',
    r'uebersetzung-$titel',
    // Die Kennung eines Globuspunktes. Eigener Namensraum, weil die
    // Fotogruppen daneben nach Rasterzelle nummerieren und zwei Punkte
    // mit derselben Kennung einander ueberschrieben. Steht nirgends auf
    // dem Bildschirm.
    r'ereignis-${e.ereignis.id}',
    // Der Abspann des Ueberfluges. Ein Test muss seine Zahlen von denen
    // der Flugleiste unterscheiden koennen - beide zeigen "unterwegs".
    'gelaende-abspann',
  };

  /// Zeilen, deren Text nie ein Nutzer sieht.
  ///
  /// `debugPrint` landet im Protokoll. `StateError`/`ArgumentError`/`assert`
  /// melden einen Programmierfehler an den Entwickler – alles, was in dieser
  /// App wirklich beim Nutzer ankommt, wirft inzwischen einen eigenen Typ
  /// (siehe etwa `RestaurierungsGrund` oder `ModellDownloadFehler`) und wird
  /// erst im Bildschirm zu einem Satz.
  bool nurFuerEntwickler(String zeile) =>
      zeile.contains('debugPrint(') ||
      zeile.contains('StateError(') ||
      zeile.contains('ArgumentError(') ||
      zeile.contains('throw Exception(') ||
      zeile.contains('FormatException(') ||
      // Wie die uebrigen Ausnahmen: Der Text landet im Kachelmitschnitt
      // neben den Meldungen von dart:io, nicht in der Oberflaeche - und
      // die sind ebenfalls englisch und unuebersetzt.
      zeile.contains('ClientException(') ||
      zeile.contains('assert(');

  /// Stellen, an denen diese App sichtbaren Text übergibt.
  const benennungen = [
    'title', 'subtitle', 'content', 'label', 'labelText', 'hintText',
    'helperText', 'tooltip', 'message', 'loadingText', 'errorPrefix',
    'restartMessage', 'semanticLabel', 'confirmLabel', 'dialogTitle',
    'dialogMessage', 'description', 'emptyMessage', 'unavailableReason',
    'pendingLabel',
  ];

  final anfang = RegExp(r"\bText\(\s*(?=')|\b(?:" + benennungen.join('|') + r"):\s*(?=')");
  final literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'");

  /// Liefert die Literale an sichtbaren Stellen, mit Zeilennummer.
  List<(int, String)> sichtbareLiterale(String quelltext) {
    // Zeilenkommentare leeren, ohne die Zeilenzählung zu verschieben.
    final ohneKommentare = quelltext
        .split('\n')
        .map((z) => z.trimLeft().startsWith('//') ? '' : z)
        .join('\n');

    final gefunden = <(int, String)>[];
    for (final treffer in anfang.allMatches(ohneKommentare)) {
      var pos = treffer.end;
      final zeile = '\n'.allMatches(ohneKommentare.substring(0, pos)).length + 1;
      final teile = <String>[];
      // Dart klebt benachbarte Literale aneinander; für die Beurteilung
      // zählt der ganze Satz, nicht die einzelne Quelltextzeile.
      while (true) {
        final m = literal.matchAsPrefix(ohneKommentare, pos);
        if (m == null) break;
        teile.add(m.group(1)!);
        pos = m.end;
        final luecke = RegExp(r'\s*').matchAsPrefix(ohneKommentare, pos)!;
        if (luecke.end < ohneKommentare.length &&
            ohneKommentare[luecke.end] == '\'') {
          pos = luecke.end;
        } else {
          break;
        }
      }
      final text = teile.join();
      if (text.isNotEmpty) gefunden.add((zeile, text));
    }
    return gefunden;
  }

  /// Jeder Literal-Lauf der Datei, mit der Zeile seines Anfangs. Anders als
  /// [sichtbareLiterale] ohne Rücksicht darauf, wo er steht.
  List<(int, String)> alleLiterale(String quelltext) {
    final ohneKommentare = quelltext
        .split('\n')
        .map((z) => z.trimLeft().startsWith('//') ? '' : z)
        .join('\n');
    final gefunden = <(int, String)>[];
    var pos = 0;
    while (true) {
      final m = literal.allMatches(ohneKommentare, pos).firstOrNull;
      if (m == null) break;
      final zeile = '\n'.allMatches(ohneKommentare.substring(0, m.start)).length + 1;
      final teile = <String>[m.group(1)!];
      var ende = m.end;
      while (true) {
        final luecke = RegExp(r'\s*').matchAsPrefix(ohneKommentare, ende)!;
        if (luecke.end < ohneKommentare.length &&
            ohneKommentare[luecke.end] == '\'') {
          final m2 = literal.matchAsPrefix(ohneKommentare, luecke.end);
          if (m2 == null) break;
          teile.add(m2.group(1)!);
          ende = m2.end;
        } else {
          break;
        }
      }
      gefunden.add((zeile, teile.join()));
      pos = ende;
    }
    return gefunden;
  }

  /// Alles, was nach Sprache aussieht: mindestens drei Buchstaben am Stück,
  /// nachdem eingesetzte Werte entfernt wurden.
  /// Entfernt eingesetzte Ausdrücke. Der letzte Schritt fängt den Fall ab,
  /// dass ein Ausdruck selbst ein Anführungszeichen enthält – dann bricht
  /// die Literal-Erkennung mittendrin ab und lässt einen offenen `${…`
  /// stehen, dessen Bezeichner sonst als Text durchgingen.
  String ohneCode(String s) => s
      .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
      .replaceAll(RegExp(r'\$\w+'), '')
      .replaceAll(RegExp(r'\$\{.*', dotAll: true), '');

  bool traegtText(String s) => RegExp(r'[A-Za-zÄÖÜäöüß]{3,}').hasMatch(ohneCode(s));

  test('in den fertigen Dateien steht kein sichtbarer Text mehr fest', () {
    final reste = <String>[];
    for (final pfad in fertig) {
      final datei = File(pfad);
      for (final (zeile, text) in sichtbareLiterale(datei.readAsStringSync())) {
        if (!traegtText(text) || unbedenklich.contains(text)) continue;
        reste.add('$pfad:$zeile  „$text"');
      }
    }
    expect(reste, isEmpty,
        reason: 'nicht übersetzt:\n${reste.join('\n')}');
  });

  test('nirgends in den fertigen Dateien steht noch ein deutscher Satz', () {
    // Der Test darüber sieht nur benannte Stellen. Deutscher Text kommt aber
    // auch als positionelles Argument vor – `_slider('Belichtung', …)`,
    // `_modelHint(true, 'das CLIP-Modell', …)`. Die findet man nur an der
    // Sprache selbst: Umlaute, ß, oder ein deutsches Funktionswort.
    final deutsch = RegExp(
        r'[äöüÄÖÜß]|\b(der|die|das|und|nicht|kein|keine|für|von|wird|werden'
        r'|sind|eine|einen|auf|aus|noch|nur|zum|zur|beim|dem|den|des|oder'
        r'|wie|nach|bei|mit|dass|sich|schon|bereits|wurde|wurden)\b');
    final reste = <String>[];
    for (final pfad in fertig) {
      final quelltext = File(pfad).readAsStringSync();
      final zeilen = quelltext.split('\n');
      for (final (zeile, text) in alleLiterale(quelltext)) {
        // Ein mehrzeiliges debugPrint oder throw erkennt man an seiner
        // ERSTEN Zeile – die Fortsetzung darunter sieht für sich genommen
        // harmlos aus. Deshalb zählt auch die Zeile davor.
        if (nurFuerEntwickler(zeilen[zeile - 1]) ||
            (zeile > 1 && nurFuerEntwickler(zeilen[zeile - 2]))) {
          continue;
        }
        // Eingesetzte Ausdrücke sind Quelltext, kein Text für den Nutzer –
        // `${_conditionSummary(rule)}` ist deutsch benannt, aber nichts,
        // was jemand liest.
        final blank = ohneCode(text);
        if (blank.length < 4 || !deutsch.hasMatch(blank)) continue;
        if (unbedenklich.contains(text)) continue;
        reste.add('$pfad:$zeile  „$text"');
      }
    }
    expect(reste, isEmpty, reason: 'noch deutsch:\n${reste.join('\n')}');
  });

  test('in Bildschirmen und Bausteinen steht überhaupt kein lesbarer Text', () {
    // Die beiden Prüfungen darüber haben zusammen einen blinden Fleck: Die
    // erste sieht nur benannte Stellen, die zweite nur Text, den man an
    // Umlauten oder deutschen Funktionswörtern erkennt. `'Zuschneiden'` als
    // positionelles Argument hat beides nicht – und stand deshalb nach vier
    // Durchgängen immer noch deutsch im Bildeditor.
    //
    // Diese Prüfung dreht die Beweislast um: Unter `lib/screens/` und
    // `lib/widgets/` gibt es keinen Grund für eine lesbare Zeichenkette im
    // Quelltext. Was dort steht, ist entweder Oberfläche (dann gehört es in
    // die Sprachdateien) oder ein Bezeichner (dann steht es oben in
    // [unbedenklich], mit Begründung). Absichtlich nur diese beiden Ordner:
    // Unter `lib/services/` und `lib/db/` sind Zeichenketten normal – SQL,
    // Pfade, Spaltennamen –, dort wäre dieselbe Regel nur Lärm.
    final endungen = [
      '.dart', '.png', '.jpg', '.jpeg', '.json', '.onnx', '.zip',
      '.sqlite', '.txt', '.md', '.xmp', '.mp4', '.heic', '.svg', '.csv',
    ];
    final bezeichner = RegExp(r'^[a-z][A-Za-z0-9_]*$');
    final schreimodus = RegExp(r'^[A-Z0-9_+.\-]{1,10}$');

    /// Sieht die Zeichenkette aus, als läse ein Mensch sie?
    bool lesbar(String roh) {
      final text = ohneCode(roh).trim();
      if (text.length < 3) return false;
      if (text.startsWith('package:') ||
          text.startsWith('dart:') ||
          text.startsWith('assets/') ||
          text.startsWith('http') ||
          text.startsWith('com.') ||
          text.contains('/') ||
          text.contains('\\')) {
        return false;
      }
      if (endungen.any(text.endsWith)) return false;
      if (bezeichner.hasMatch(text) || schreimodus.hasMatch(text)) return false;
      return RegExp(r'[A-Za-zÄÖÜäöüß]{3,}').hasMatch(text);
    }

    final reste = <String>[];
    for (final pfad in fertig) {
      if (!pfad.startsWith('lib/screens/') && !pfad.startsWith('lib/widgets/')) {
        continue;
      }
      final quelltext = File(pfad).readAsStringSync();
      final zeilen = quelltext.split('\n');
      for (final (zeile, text) in alleLiterale(quelltext)) {
        final quelle = zeilen[zeile - 1];
        if (quelle.trimLeft().startsWith('import ') ||
            quelle.trimLeft().startsWith('export ') ||
            quelle.trimLeft().startsWith('part ')) {
          continue;
        }
        if (nurFuerEntwickler(quelle) ||
            (zeile > 1 && nurFuerEntwickler(zeilen[zeile - 2]))) {
          continue;
        }
        if (unbedenklich.contains(text) || !lesbar(text)) continue;
        reste.add('$pfad:$zeile  „$text"');
      }
    }
    expect(reste, isEmpty,
        reason: 'lesbarer Text fest im Quelltext:\n${reste.join('\n')}');
  });

  test('die ausgenommenen Dateien gibt es noch', () {
    // Eine Ausnahme für eine Datei, die es nicht mehr gibt, verdeckt beim
    // nächsten Umbenennen stillschweigend eine echte Lücke.
    for (final pfad in ausgenommen) {
      expect(File(pfad).existsSync(), isTrue, reason: '$pfad gibt es nicht mehr');
    }
  });

  test('die Ausnahmeliste ist nicht veraltet', () {
    // Eine Ausnahme, die es im Quelltext nicht mehr gibt, ist ein Loch für
    // den nächsten Text, der zufällig genauso lautet.
    final aller = fertig.map((p) => File(p).readAsStringSync()).join('\n');
    for (final ausnahme in unbedenklich) {
      expect(aller.contains(ausnahme), isTrue,
          reason: 'Ausnahme „$ausnahme" wird nicht mehr gebraucht');
    }
  });

  test('jeder Textschlüssel wird auch benutzt', () {
    // Ein Schlüssel, den niemand aufruft, heißt fast immer: Er wurde
    // angelegt, aber die Stelle im Quelltext nie umgestellt. Genau so sind
    // drei Texte deutsch geblieben, obwohl ihre Übersetzung längst dastand.
    final arb = jsonDecode(File('lib/l10n/app_de.arb').readAsStringSync())
        as Map<String, dynamic>;
    final quelltext = StringBuffer();
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (e.path.replaceAll(r'\', '/').contains('/l10n/')) continue; // die Erzeugnisse selbst
      quelltext.write(e.readAsStringSync());
    }
    final text = quelltext.toString();

    final ungenutzt = arb.keys
        .where((k) => !k.startsWith('@'))
        .where((k) => !text.contains('.$k'))
        .toList();
    expect(ungenutzt, isEmpty,
        reason: 'diese Texte ruft niemand ab: ${ungenutzt.join(', ')}');
  });
}

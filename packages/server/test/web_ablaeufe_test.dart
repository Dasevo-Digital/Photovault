import 'dart:io';

import 'package:test/test.dart';

/// Abläufe der Weboberfläche, die am Quelltext von `web/app.js` geprüft
/// werden – wie in web_test.dart: Ein Browser läuft in diesen Tests nicht.
void main() {
  late String app;
  setUpAll(() => app = File('web/app.js').readAsStringSync());

  /// Der Körper der Funktion [name] bis zur nächsten Funktion auf oberster
  /// Ebene.
  String funktion(String name) {
    final beginn = app.indexOf(RegExp('(async )?function $name\\('));
    expect(beginn, isNonNegative, reason: name);
    final ende = app.indexOf(RegExp(r'\n(async )?function '), beginn + 1);
    return app.substring(beginn, ende < 0 ? app.length : ende);
  }

  test('die Frist des Papierkorbs geht nur als 1 bis 3650 Tage hinaus', () {
    // Ein geleertes Feld „nach … Tagen“ schickte Number('') = 0, und der
    // Server leerte daraufhin den ganzen Papierkorb endgültig.
    final einstellungen = funktion('zeigeEinstellungen');
    expect(einstellungen, isNot(contains('tage: Number(tage.value)')));
    final senden = RegExp(
      r"sende\('papierkorbFristSetzen', \{[^}]*tage: (\w+)",
    ).allMatches(einstellungen).map((m) => m[1]).toSet();
    expect(senden, isNotEmpty);
    expect(senden, everyElement(isIn({'n', 'tageGesendet'})));
    expect(einstellungen, contains('n >= 1 && n <= 3650'));
  });

  test('„Papierkorb leeren“ löscht genau die gezeigten Aufnahmen', () {
    // Mit {alle: true} löschte der Server alles, was in dem Moment im
    // Papierkorb lag – auch, was ein Telefon inzwischen hineingelegt hatte
    // und was die Rückfrage nicht mitzählte.
    expect(app, isNot(contains('alle: true')));
    expect(
      funktion('endgueltigLoeschen'),
      contains('json: { ids: aufnahmen.map((a) => a.id) }'),
    );
    expect(
      funktion('zeigePapierkorb'),
      contains('endgueltigLoeschen(d.aufnahmen)'),
    );
  });

  test(
    'nach einem Fehler beim Nachladen geht es erst nach einer Pause weiter',
    () {
      // Die Fehlermeldung steht in #ende, das damit sichtbar blieb; das
      // finally rief ladeMehr sofort wieder auf – Hunderte Anfragen je
      // Sekunde, solange der Server weg war oder 503 sagte.
      final lade = funktion('ladeMehr');
      final sofort = lade.indexOf('setTimeout(ladeMehr)');
      expect(sofort, isNonNegative);
      expect(lade.substring(0, sofort), contains('if (!gescheitert)'));
      expect(lade, contains('2 ** l.fehlversuche'));
      expect(lade, contains('liste.fehlversuche = 0'));
    },
  );

  test('die Suche zählt erst nach einem gelungenen Abruf weiter', () {
    // `pos` rückte vor der Anfrage vor: Jeder Fehlschlag übersprang 300
    // Treffer, und offline lief die Liste bis zum Ende aller Kennungen.
    final abruf = app.indexOf("await api('/api/v1/aufnahmen/liste'");
    expect(abruf, isNonNegative);
    final mehr = app.lastIndexOf('const mehr = async () => {', abruf);
    final weiter = app.indexOf('pos += stueck.length', mehr);
    expect(weiter, greaterThan(abruf));
  });

  test('wer sich nach einer abgelaufenen Sitzung anmeldet, bekommt eine '
      'frische Seite', () {
    // Nach einem 401 zeigte zeigeAnmeldung das Formular, und die neue
    // Anmeldung rief nur starte() auf: Zeitleiste, Suchfilter und
    // Duplikate des vorigen Kontos blieben stehen.
    expect(funktion('starte'), contains('warAngemeldet = true;'));
    final nach = funktion('nachAnmeldung');
    final neu = nach.indexOf(
      'if (warAngemeldet) { location.reload(); return; }',
    );
    expect(neu, isNonNegative);
    expect(nach.indexOf('await starte();'), greaterThan(neu));
  });

  test('eine Seite der Zeitleiste von vor dem Leeren ändert nichts mehr', () {
    // leeren() liess die laufende Anfrage stehen: Die nächste Ansicht
    // bekam sie als ihre erste Seite, und hole() schrieb Lesezeichen und
    // Liste der alten Ordnung in die neue.
    final beginn = app.indexOf('const zeitleiste = {');
    final ende = app.indexOf('  async holeSeite(', beginn);
    final z = app.substring(beginn, ende);
    expect(z, contains('leeren() { this.stand++; this.lauf = null;'));
    final hole = z.substring(z.indexOf('async hole()'));
    final pruefung = hole.indexOf('if (stand !== this.stand) return d;');
    expect(pruefung, isNonNegative);
    expect(hole.indexOf('this.weiter = d.weiter'), greaterThan(pruefung));
  });

  test('Dialoge legen bei einem Doppelklick nichts doppelt an', () {
    // Die Dialoge bleiben während der Anfrage offen; zweimal Enter legte
    // zwei Links, Regeln, gemerkte Suchen oder Personen gleichen Namens an.
    expect(app, contains('if (laufendeFormulare.has(ziel)) return;'));
    for (final form in ['form-link', 'form-autoregel', 'form-merken']) {
      final beginn = app.indexOf("\$('$form').addEventListener('submit'");
      expect(beginn, isNonNegative, reason: form);
      final ende = app.indexOf('\n});', beginn);
      expect(
        app.substring(beginn, ende),
        contains('einmalZugleich('),
        reason: form,
      );
    }
    expect(
      funktion('gesichterFertig'),
      contains("einmalZugleich(\$('gesicht-dialog')"),
    );
  });

  test('nach dem Hochladen in ein geteiltes Album nur dort neu zeichnen', () {
    // Am Ende des Uploads zeichnete die Seite das Album neu, wo auch immer
    // man inzwischen war – auch unter einem offenen Betrachter, dessen
    // Index danach auf ein anderes Foto zeigte.
    final album = funktion('zeigeGeteiltesAlbum');
    expect(
      album,
      isNot(contains('n: gut })); await zeigeGeteiltesAlbum(id);')),
    );
    expect(
      album,
      contains(
        "if (wurzel === 'geteilt' && teil === id && offen < 0) "
        'await zeigeGeteiltesAlbum(id);',
      ),
    );
  });

  group('ungespeicherte Eingaben im Betrachter (#462)', () {
    /// Der Klick-Handler von [id]: eine Zeile oder bis zu seinem `});`.
    String klick(String id) {
      final beginn = app.indexOf("\$('$id').addEventListener('click'");
      expect(beginn, isNonNegative, reason: id);
      final zeile = app.substring(beginn, app.indexOf('\n', beginn));
      if (zeile.endsWith('});')) return zeile;
      return app.substring(beginn, app.indexOf('\n});', beginn));
    }

    test('Blättern, Schliessen, Ort setzen und Seitenwechsel fragen erst', () {
      // Jeder dieser Wege zeichnete die Angaben neu oder schloss den
      // Betrachter: Eine geänderte, nicht gespeicherte Beschreibung ging
      // still verloren.
      final blaettere = funktion('blaettere');
      expect(blaettere, contains('await eingabenFreigeben()'));
      expect(
        'oeffne(offen'.allMatches(app).length,
        'oeffne(offen'.allMatches(blaettere).length,
        reason: 'Blättern nur über blaettere()',
      );
      expect(
        funktion('schliesseBetrachter'),
        contains('(await eingabenFreigeben())) schliesse();'),
      );
      expect(app, isNot(contains("addEventListener('click', schliesse)")));
      expect(
        app,
        contains("\$('zu').addEventListener('click', schliesseBetrachter);"),
      );
      final wisch = funktion('wischEnde');
      expect(wisch, isNot(contains('oeffne(')));
      expect(wisch, isNot(contains('schliesse()')));
      expect(wisch, contains('schliesseBetrachter()'));
      // Die Tasten im Betrachter.
      final tasten = app.substring(
        app.indexOf('    if (offen >= 0) {\n      if (strg) return;'),
        app.indexOf("else if (taste === 'i' || taste === 'I')"),
      );
      expect(tasten, isNot(contains('schliesse()')));
      expect(tasten, isNot(contains('oeffne(')));
      expect(tasten, contains('await blaettere(1)'));
      // Dieselbe Esc schlösse sonst die Rückfrage gleich wieder.
      expect(
        tasten,
        contains(
          "if (taste === 'Escape') { e.preventDefault(); "
          'await schliesseBetrachter(); }',
        ),
      );
      // Ort setzen.
      expect(
        app,
        contains(
          'if (await eingabenFreigeben()) ortDialog([a], Boolean(d.ort), '
          'zeigeAngaben);',
        ),
      );
      // Verweise in den Angaben, Entwickeln, Diashow, Papierkorb.
      final verweis = funktion('verweisAusDemBetrachter');
      final frei = verweis.indexOf('await eingabenFreigeben()');
      expect(frei, greaterThan(verweis.indexOf('e.preventDefault()')));
      expect(verweis.indexOf('schliesse();'), greaterThan(frei));
      expect(funktion('verweise'), contains('verweisAusDemBetrachter(a)'));
      expect(funktion('zeigeAngaben'), contains('verweisAusDemBetrachter(v)'));
      for (final id in ['bearbeiten', 'diashow-knopf', 'weg', 'holen']) {
        expect(klick(id), contains('await eingabenFreigeben()'), reason: id);
      }
      expect(funktion('inDenKorb'), contains('await eingabenFreigeben()'));
      // Seitenwechsel: Zurück im Browser, ein Verweis, eine neue Adresse.
      expect(app, isNot(contains("addEventListener('hashchange', zeigeWeg)")));
      expect(
        app,
        contains("window.addEventListener('hashchange', wegGewechselt);"),
      );
      final weg = funktion('wegGewechselt');
      final zurueck = weg.indexOf(
        "history.replaceState(history.state, '', wegAdresse(gezeigterWeg));",
      );
      expect(zurueck, isNonNegative);
      expect(weg.indexOf('await eingabenFreigeben()'), greaterThan(zurueck));
      expect(weg, contains('if (!frei) return;'));
      expect(funktion('zeigeWeg'), contains('gezeigterWeg = location.hash;'));
      // Und der Tab: Der Browser warnt, solange etwas offen ist.
      final tab = app.indexOf("window.addEventListener('beforeunload'");
      expect(tab, isNonNegative);
      expect(
        app.substring(tab, app.indexOf('\n});', tab)),
        allOf(
          contains('if (!offeneEingaben().length) return;'),
          contains('e.preventDefault();'),
        ),
      );
    });

    test('mit der Einstellung wird gespeichert, sonst gefragt', () {
      // Speichern-Knopf, Verlassen des Felds und jeder Wechsel gehen über
      // denselben Befehl.
      expect("befehl('beschreibungSetzen'".allMatches(app), hasLength(1));
      final feld = funktion('beschreibungsfeld');
      expect(feld, contains("befehl('beschreibungSetzen'"));
      expect(feld, contains("text.addEventListener('blur'"));
      expect(
        feld,
        contains(
          'if (beschreibungSelbst && eingabe.geaendert()) eingabe.sichern()',
        ),
      );
      // Ein neu gezeichnetes Feld für dasselbe Foto behält den Entwurf.
      expect(feld, contains('text.value = entwurf ?? gespeichert;'));
      final frei = funktion('gibEingabenFrei');
      expect(frei, contains('if (e.selbst && beschreibungSelbst) {'));
      // Scheitert das Speichern: Meldung, und es bleibt beim Alten.
      expect(
        frei,
        contains(
          'try { await e.sichern(); } catch (x) { '
          'meldung(nichtGespeichert(x), true); return false; }',
        ),
      );
      expect(frei, contains('!(await frageNachEingabe(e))'));
      // Die Rückfrage: speichern, verwerfen oder abbrechen.
      final frage = funktion('frageNachEingabe');
      expect(frage, contains("\$('eingabe-verwerfen').onclick"));
      expect(frage, contains("\$('eingabe-abbrechen').onclick"));
      expect(frage, contains('await e.sichern(); fertig(true);'));
      final html = File('web/index.html').readAsStringSync();
      for (final id in [
        'eingabe-dialog',
        'eingabe-frage',
        'eingabe-meldung',
        'eingabe-abbrechen',
        'eingabe-verwerfen',
        'eingabe-sichern',
      ]) {
        expect(html, contains('id="$id"'), reason: id);
      }
      // Ein Kommentar geht nie von selbst hinaus.
      expect(funktion('kommentarBereich'), contains('selbst: false'));
      // Die Einstellung gilt für diesen Browser und ist zunächst aus.
      expect(
        app,
        contains("localStorage.getItem(BESCHREIBUNG_MERKER) === '1'"),
      );
      final einstellungen = funktion('zeigeEinstellungen');
      expect(
        einstellungen,
        contains("zeile('Beschreibung beim Verlassen automatisch speichern'"),
      );
      expect(
        einstellungen,
        contains("localStorage.setItem(BESCHREIBUNG_MERKER, an ? '1' : '0')"),
      );
    });

    test('die neuen Texte gibt es auch auf Englisch', () {
      final texte = File('web/texte.js').readAsStringSync();
      final deutsch = <String>{
        'Verwerfen',
        'Abbrechen',
        'Speichern',
        'Senden',
        'Die Beschreibung ist nicht gespeichert: {grund}',
        for (final m in RegExp(
          r"(?:frage|sichernText): '([^']+)'",
        ).allMatches(app))
          m[1]!,
        for (final m in RegExp(
          r"zeile\('(Beschreibung beim Verlassen[^']*)', '([^']+)'",
        ).allMatches(app)) ...[m[1]!, m[2]!],
      };
      expect(deutsch, hasLength(9));
      for (final d in deutsch) {
        expect(texte, contains("  '$d': '"), reason: d);
      }
    });
  });
}

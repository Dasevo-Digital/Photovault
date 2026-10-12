part of '../database.dart';

/// Einstellungen der App und der Ansichten.
extension EinstellungsAbfragen on AppDatabase {
  /// Alle Assets (gesperrt oder nicht – der PIN-Schutz gilt dem Ansehen des
  /// Inhalts, nicht dem endgültigen Löschen einer bereits im Papierkorb
  /// liegenden Datei), die vor [cutoff] in den Papierkorb verschoben wurden.
  /// Für den automatischen Papierkorb-Ablauf, siehe
  /// [LibraryState.purgeExpiredTrashIfDue].
  Future<List<AssetData>> expiredTrashAssets(DateTime cutoff) =>
      (select(assets)..where(
            (t) =>
                t.isTrashed.equals(true) &
                t.trashedAt.isSmallerThanValue(cutoff),
          ))
          .get();

  Future<TrashSettingsData?> trashSettingsRow() =>
      (select(trashSettings)..where((t) => t.id.equals(0))).getSingleOrNull();

  Future<void> setTrashAutoDeleteConfig({
    required bool enabled,
    int? afterDays,
  }) => into(trashSettings).insertOnConflictUpdate(
    TrashSettingsCompanion.insert(
      id: const Value(0),
      autoDeleteEnabled: Value(enabled),
      autoDeleteAfterDays: afterDays != null
          ? Value(afterDays)
          : const Value.absent(),
    ),
  );

  Future<void> setLastTrashPurgeAt(DateTime when) =>
      (update(trashSettings)..where((t) => t.id.equals(0))).write(
        TrashSettingsCompanion(lastPurgeAt: Value(when)),
      );

  /// Reaktiv statt einmalig gelesen, damit ein Theme-Wechsel in den
  /// Einstellungen sofort in main.dart ankommt, ohne App-Neustart.
  Stream<AppSettingsData?> watchAppSettings() =>
      (select(appSettings)..where((t) => t.id.equals(0))).watchSingleOrNull();

  Future<void> setAutoAnalyzeAfterImport(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          autoAnalyzeAfterImport: Value(an),
        ),
      );

  /// Einmalig gelesen (nicht als Stream): wird direkt nach einem Import
  /// abgefragt, um zu entscheiden, ob die Analyse anlaufen soll.
  /// Der überwachte Ordner samt Sandbox-Merkmal, oder null.
  Future<({String pfad, String? token})?> ueberwachterOrdner() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    final pfad = row?.watchedFolderPath;
    if (pfad == null || pfad.isEmpty) return null;
    return (pfad: pfad, token: row?.watchedFolderToken);
  }

  /// Setzt den überwachten Ordner; [pfad] = null schaltet die Überwachung ab.
  Future<void> setzeUeberwachtenOrdner({String? pfad, String? token}) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          watchedFolderPath: Value(pfad),
          watchedFolderToken: Value(token),
        ),
      );

  /// Allgemeine Gesichts-Ähnlichkeitsschwelle. Beim Schreiben werden die
  /// persönlichen Schwellen mitgezogen – sie hängen an dieser (siehe
  /// [rechneAlleSchwellenNeu]), sonst hätte der Regler für bereits
  /// gelernte Personen keine Wirkung mehr.
  Future<void> setFaceSimilarityThreshold(double wert) => transaction(() async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        id: const Value(0),
        faceSimilarityThreshold: Value(wert),
      ),
    );
    await rechneAlleSchwellenNeu(wert);
  });

  Future<double> faceSimilarityThresholdWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.faceSimilarityThreshold ?? 0.363;
  }

  /// Benennt Vokabelbegriffe und die zugehörigen Schlagwörter um – für das
  /// Angebot beim Sprachwechsel.
  ///
  /// [zuordnung] bildet alt auf neu ab und enthält **nur** Begriffe, die
  /// tatsächlich im Vokabular stehen; selbst hinzugefügte bleiben
  /// unangetastet.
  ///
  /// Drei Tabellen sind betroffen, und die dritte ist die, die man
  /// übersieht:
  ///
  ///  1. [AiTagVocabulary.term] – der Vokabeleintrag
  ///  2. [Tags.name] – der Schlagwort-Name. Alle Zuordnungen hängen an
  ///     [Tags.id] und wandern deshalb von selbst mit; es ist ein reines
  ///     Umbenennen, kein Umhängen.
  ///  3. [AutomationRules.aiTagTerm] – eine Textspalte, die exakt einem
  ///     Vokabelbegriff entsprechen muss. Bliebe sie stehen, hörte eine
  ///     Regel „wenn Hund erkannt" lautlos auf zu feuern.
  ///
  /// **Namenskollisionen** sind der Fall, an dem eine naive Fassung
  /// scheitert: Beide Namensspalten sind `unique`. Gibt es das Ziel schon
  /// (etwa ein von Hand angelegtes „Dog"), wird nicht umbenannt, sondern
  /// **verschmolzen** – die Zuordnungen des alten Schlagworts wandern auf
  /// das bestehende, das alte wird gelöscht. Ohne diesen Zweig bräche die
  /// ganze Umstellung mit einem Constraint-Fehler ab.
  ///
  /// Gibt die Anzahl tatsächlich umbenannter Begriffe zurück.
  Future<int> uebersetzeVokabular(Map<String, String> zuordnung) async {
    var geaendert = 0;
    await transaction(() async {
      for (final eintrag in zuordnung.entries) {
        final alt = eintrag.key;
        final neu = eintrag.value;
        if (alt == neu) continue;

        // --- Vokabular ---
        final vorhandenesVokabel = await (select(
          aiTagVocabulary,
        )..where((t) => t.term.equals(alt))).getSingleOrNull();
        if (vorhandenesVokabel == null) continue;

        final zielVokabel = await (select(
          aiTagVocabulary,
        )..where((t) => t.term.equals(neu))).getSingleOrNull();
        if (zielVokabel != null) {
          // Ziel gibt es schon – der alte Eintrag ist damit überflüssig.
          await (delete(
            aiTagVocabulary,
          )..where((t) => t.id.equals(vorhandenesVokabel.id))).go();
        } else {
          await (update(aiTagVocabulary)
                ..where((t) => t.id.equals(vorhandenesVokabel.id)))
              .write(AiTagVocabularyCompanion(term: Value(neu)));
        }

        // --- Schlagwort samt Zuordnungen ---
        final altesTag = await (select(
          tags,
        )..where((t) => t.name.equals(alt))).getSingleOrNull();
        if (altesTag != null) {
          final zielTag = await (select(
            tags,
          )..where((t) => t.name.equals(neu))).getSingleOrNull();
          if (zielTag == null) {
            await (update(tags)..where((t) => t.id.equals(altesTag.id))).write(
              TagsCompanion(name: Value(neu)),
            );
          } else {
            // Verschmelzen: Zuordnungen umhängen, dabei bereits
            // bestehende Paare nicht doppelt anlegen.
            final betroffene = await (select(
              assetTags,
            )..where((t) => t.tagId.equals(altesTag.id))).get();
            for (final zuweisung in betroffene) {
              await into(assetTags).insertOnConflictUpdate(
                AssetTagsCompanion.insert(
                  assetId: zuweisung.assetId,
                  tagId: zielTag.id,
                ),
              );
            }
            await (delete(
              assetTags,
            )..where((t) => t.tagId.equals(altesTag.id))).go();
            await (delete(
              automationRuleTags,
            )..where((t) => t.tagId.equals(altesTag.id))).go();
            await (delete(tags)..where((t) => t.id.equals(altesTag.id))).go();
          }
        }

        // --- Automatisierungsregeln ---
        await (update(automationRules)..where((t) => t.aiTagTerm.equals(alt)))
            .write(AutomationRulesCompanion(aiTagTerm: Value(neu)));

        geaendert++;
      }
    });
    return geaendert;
  }

  /// Begriffe im Vokabular, die NICHT aus der mitgelieferten
  /// Startbestückung stammen – sie bleiben beim Sprachwechsel unverändert
  /// und werden im Dialog gezählt.
  Future<int> zaehleEigeneVokabelbegriffe(Set<String> bekannte) async {
    final alle = await select(aiTagVocabulary).get();
    return alle.where((v) => !bekannte.contains(v.term)).length;
  }

  Future<void> setSprache(String sprache) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          sprache: Value(sprache),
        ),
      );

  Future<String> spracheWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.sprache ?? 'system';
  }

  Future<void> setThemeMode(String mode) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(id: const Value(0), themeMode: Value(mode)),
      );

  /// Ob die Karte in doppelter Auflösung zeichnet (siehe die Spalte).
  Future<bool> karteHochaufloesendWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    // Ohne Zeile gilt die Vorgabe – und die ist an.
    return row?.karteHochaufloesend ?? true;
  }

  Future<void> setzeKarteHochaufloesend(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          karteHochaufloesend: Value(an),
        ),
      );

  /// Die gemerkte Tageszeit der Geländeansicht.
  Future<Tageszeit> gelaendeStimmungWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return tageszeit(row?.gelaendeStimmungNr ?? lichtstimmungVorgabe.index);
  }

  Future<void> setzeGelaendeStimmung(Tageszeit zeit) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          gelaendeStimmungNr: Value(zeit.index),
        ),
      );

  /// Die Wanderobjekte eines Ausschnitts – aus der Bibliothek, sonst aus
  /// dem Netz.
  ///
  /// **Der Ausschnitt wird auf drei Nachkommastellen gerundet**, bevor er
  /// zum Schlüssel wird. Ohne diese Rundung wäre jede Abfrage neu: Der
  /// Ausschnitt einer Wanderung hängt an ihren Spurpunkten, und die
  /// gerundeten Grade unterscheiden sich in der zwölften Stelle, sobald
  /// jemand einen Punkt löscht. Drei Stellen sind rund hundert Meter –
  /// darunter lohnt kein zweiter Abruf.
  ///
  /// [holen] wird nur gerufen, wenn zu diesem Ausschnitt noch nie
  /// gefragt wurde. Liefert es `null` (kein Netz, Overpass gedrosselt),
  /// wird **nichts gemerkt**: Der Ausschnitt bleibt offen, und beim
  /// nächsten Öffnen wird es noch einmal versucht.
  Future<List<WanderpunkteData>> wanderpunkteFuer({
    required double sued,
    required double west,
    required double nord,
    required double ost,
    required Future<
      List<
        ({
          int osmId,
          int artNr,
          double breite,
          double laenge,
          String? name,
          double? hoehe,
        })
      >?
    >
    Function()
    holen,
  }) async {
    String r(double w) => w.toStringAsFixed(3);
    final schluessel = '${r(sued)},${r(west)},${r(nord)},${r(ost)}';

    Future<List<WanderpunkteData>> ausDerBibliothek() =>
        (select(wanderpunkte)..where(
              (t) =>
                  t.breite.isBiggerOrEqualValue(sued) &
                  t.breite.isSmallerOrEqualValue(nord) &
                  t.laenge.isBiggerOrEqualValue(west) &
                  t.laenge.isSmallerOrEqualValue(ost),
            ))
            .get();

    final schonGefragt = await (select(
      wanderabfragen,
    )..where((t) => t.kasten.equals(schluessel))).getSingleOrNull();
    if (schonGefragt != null) return ausDerBibliothek();

    final frisch = await holen();
    if (frisch == null) return ausDerBibliothek();

    await batch((b) {
      b.insertAllOnConflictUpdate(wanderpunkte, [
        for (final p in frisch)
          WanderpunkteCompanion.insert(
            osmId: Value(p.osmId),
            artNr: p.artNr,
            breite: p.breite,
            laenge: p.laenge,
            name: Value(p.name),
            hoehe: Value(p.hoehe),
          ),
      ]);
      b.insertAllOnConflictUpdate(wanderabfragen, [
        WanderabfragenCompanion.insert(
          kasten: schluessel,
          gefragtAm: DateTime.now(),
        ),
      ]);
    });
    return ausDerBibliothek();
  }

  /// Die gemerkte Auflage der Geländeansicht – Grund und Ebenen.
  Future<Gelaendekarte> gelaendeKarteWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    // Ohne Zeile gelten die Vorgaben, und die stehen genau einmal – an
    // den Spalten selbst.
    if (row == null) return const Gelaendekarte();
    return Gelaendekarte(
      grund: gelaendegrundAus(row.gelaendeGrundNr),
      wege: row.gelaendeWege,
      beschriftung: row.gelaendeBeschriftung,
      hoehenlinien: row.gelaendeHoehenlinien,
      wanderobjekte: row.gelaendeWanderobjekte,
    );
  }

  Future<void> setzeGelaendeKarte(Gelaendekarte karte) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          gelaendeGrundNr: Value(karte.grund.index),
          gelaendeWege: Value(karte.wege),
          gelaendeBeschriftung: Value(karte.beschriftung),
          gelaendeHoehenlinien: Value(karte.hoehenlinien),
          gelaendeWanderobjekte: Value(karte.wanderobjekte),
        ),
      );

  /// Ob Videos und Live Photos beim Schweben von selbst anlaufen.
  Future<bool> schwebeVorschauWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.schwebeVorschau ?? true;
  }

  Future<void> setzeSchwebeVorschau(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          schwebeVorschau: Value(an),
        ),
      );

  /// Die gemerkte Spaltenwahl der Listenansicht (siehe die Spalte).
  Future<Listenspaltenwahl> listenspaltenWahl() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return Listenspaltenwahl.ausText(row?.listenspalten);
  }

  Future<void> setzeListenspalten(Listenspaltenwahl wahl) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          listenspalten: Value(wahl.alsText()),
        ),
      );

  /// Die gemerkte Kachelstufe der Zeitleiste (siehe die Spalte).
  Future<int> zeitleisteKachelstufeWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.zeitleisteKachelstufe ?? zeitleisteKachelstufeVorgabe;
  }

  Future<void> setzeZeitleisteKachelstufe(int stufe) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          zeitleisteKachelstufe: Value(stufe),
        ),
      );

  /// Quadrate oder buendige Reihen – siehe [Zeitleistenform].
  Future<Zeitleistenform> zeitleisteFormWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return zeitleisteForm(row?.zeitleisteFormNr ?? zeitleisteFormVorgabe.index);
  }

  Future<void> setzeZeitleisteForm(Zeitleistenform form) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          zeitleisteFormNr: Value(form.index),
        ),
      );

  /// Wonach die Zeitleiste ordnet – siehe [Rastersortierung].
  Future<Rastersortierung> zeitleisteSortierungWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return rastersortierung(
      row?.zeitleisteSortierungNr ?? rastersortierungVorgabe.index,
    );
  }

  Future<void> setzeZeitleisteSortierung(Rastersortierung s) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          zeitleisteSortierungNr: Value(s.index),
        ),
      );

  /// Ob die Zeitleiste nach Tagen gliedert – siehe die Spalte.
  Future<bool> zeitleisteMitTagenWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.zeitleisteMitTagen ?? false;
  }

  Future<void> setzeZeitleisteMitTagen(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          zeitleisteMitTagen: Value(an),
        ),
      );

  /// Die gemerkte Stammbaum-Ansicht und die Person darin (siehe die
  /// Spalten). Beide `null`, solange niemand den Baum geöffnet hat.
  Future<({String? ansicht, String? person})> stammbaumZuletzt() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return (ansicht: row?.stammbaumAnsicht, person: row?.stammbaumPerson);
  }

  Future<void> setzeStammbaumZuletzt({
    required String ansicht,
    String? person,
  }) => into(appSettings).insertOnConflictUpdate(
    AppSettingsCompanion.insert(
      id: const Value(0),
      stammbaumAnsicht: Value(ansicht),
      stammbaumPerson: Value(person),
    ),
  );

  /// Wie der Lebensbaum zuletzt aussah – siehe die Spalten. Alles `null`,
  /// solange niemand etwas umgestellt hat.
  Future<
    ({
      String? richtung,
      String? stil,
      int? generationen,
      int? familieOben,
      int? familieUnten,
      String? familieKreis,
    })
  >
  lebensbaumZuletzt() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return (
      richtung: row?.lebensbaumRichtung,
      stil: row?.lebensbaumStil,
      generationen: row?.lebensbaumGenerationen,
      familieOben: row?.lebensbaumFamilieOben,
      familieUnten: row?.lebensbaumFamilieUnten,
      familieKreis: row?.lebensbaumFamilieKreis,
    );
  }

  /// Merkt sich den Lebensbaum. Was für die Familie nicht angegeben ist,
  /// bleibt, wie es war.
  Future<void> setzeLebensbaum({
    required String richtung,
    required String stil,
    required int generationen,
    int? familieOben,
    int? familieUnten,
    String? familieKreis,
  }) => into(appSettings).insertOnConflictUpdate(
    AppSettingsCompanion.insert(
      id: const Value(0),
      lebensbaumRichtung: Value(richtung),
      lebensbaumStil: Value(stil),
      lebensbaumGenerationen: Value(generationen),
      lebensbaumFamilieOben: familieOben == null
          ? const Value.absent()
          : Value(familieOben),
      lebensbaumFamilieUnten: familieUnten == null
          ? const Value.absent()
          : Value(familieUnten),
      lebensbaumFamilieKreis: familieKreis == null
          ? const Value.absent()
          : Value(familieKreis),
    ),
  );

  /// Die gemerkte Kartenansicht, als Text wie in der Spalte.
  Future<String?> kartenansicht() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.kartenansicht;
  }

  Future<void> setzeKartenansicht(String ansicht) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          kartenansicht: Value(ansicht),
        ),
      );

  /// Wie viele schwere Aufgaben gleichzeitig laufen dürfen (siehe die
  /// Spalte). Ohne gespeicherte Zeile gilt die Vorgabe eins.
  Future<int> maxGleichzeitigeAufgaben() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    // Eine Null oder ein negativer Wert käme nur aus einer von Hand
    // veränderten Datenbank – dann liefe gar nichts mehr, und niemand
    // fände den Grund. Eins ist die Untergrenze.
    final wert = row?.maxGleichzeitig ?? 1;
    return wert < 1 ? 1 : wert;
  }

  Future<void> setzeMaxGleichzeitigeAufgaben(int anzahl) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          maxGleichzeitig: Value(anzahl < 1 ? 1 : anzahl),
        ),
      );

  /// Der gespeicherte CARTO-Schlüssel, oder null.
  Future<String?> cartoSchluesselWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    final wert = row?.cartoSchluessel?.trim();
    return wert == null || wert.isEmpty ? null : wert;
  }

  /// Legt den CARTO-Schlüssel ab. Leer oder null löscht ihn wieder.
  ///
  /// Das Leeren muss ausdrücklich als `null` in der Spalte landen und
  /// nicht als leere Zeichenkette: Sonst hinge an der Kachel-Adresse ein
  /// `?key=` ohne Wert, und der Server antwortete mit dem Wasserzeichen
  /// statt mit einer Karte – also genau dem Zustand, den die
  /// Einstellung beheben soll.
  /// Die eigene Kartenquelle, oder null, wenn keine eingerichtet ist.
  ///
  /// Alles-oder-nichts: Fehlt Adresse, Namensnennung oder die
  /// Zustimmung, gibt es keine Quelle. Eine halb ausgefuellte Quelle
  /// waere schlimmer als keine – die Karte bliebe leer, und die
  /// Namensnennung ist eine Lizenzauflage, keine Kür.
  Future<Eigenkarte?> eigeneKarteWert() async {
    final row = await (select(
      appSettings,
    )..where((t) => t.id.equals(0))).getSingleOrNull();
    if (row == null) return null;
    return Eigenkarte.aus(
      name: row.eigeneKarteName,
      url: row.eigeneKarteUrl,
      nennung: row.eigeneKarteNennung,
      stufe: row.eigeneKarteStufe,
      zugestimmt: row.eigeneKarteZugestimmt,
    );
  }

  /// Legt die eigene Kartenquelle ab. `null` loescht sie wieder.
  Future<void> setzeEigeneKarteWert(Eigenkarte? karte) {
    String? sauber(String? w) {
      final t = w?.trim();
      return t == null || t.isEmpty ? null : t;
    }

    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        id: const Value(0),
        eigeneKarteName: Value(sauber(karte?.name)),
        eigeneKarteUrl: Value(sauber(karte?.url)),
        eigeneKarteNennung: Value(sauber(karte?.nennung)),
        eigeneKarteStufe: Value(karte?.stufe),
        eigeneKarteZugestimmt: Value(karte?.zugestimmt ?? false),
      ),
    );
  }

  Future<void> setzeCartoSchluesselWert(String? schluessel) {
    final wert = schluessel?.trim();
    return into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        id: const Value(0),
        cartoSchluessel: Value(wert == null || wert.isEmpty ? null : wert),
      ),
    );
  }

  Future<void> setzeUebersetzeSucheUndTags(bool an) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(0),
          translateSearchAndTags: Value(an),
        ),
      );
}

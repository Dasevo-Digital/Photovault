import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/exif_camera.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/verwandtschaftsgrad.dart';

import 'hilfen/quelltext.dart';

/// Die Befehlsschicht (packages/kern/lib/befehle): Jede Änderung durch den
/// Nutzer soll als Befehl laufen, damit sie sich später an einen Server
/// schicken lässt (Issue #86).
///
/// Geprüft wird dreierlei: dass jeder Befehl den Weg über JSON übersteht,
/// dass er wirkt wie der direkte Aufruf, den er ersetzt, und dass jede
/// Schreibmethode der Datenbank eingeordnet ist – samt der Zusage, dass,
/// was schon Befehl ist, niemand mehr direkt aufruft.
void main() {
  group('Befehle über JSON', () {
    /// Ein Beispiel je Art. Die Weiche in [artVon] ist erschöpfend: Eine
    /// neue Befehlsklasse ohne Beispiel hier kompiliert nicht.
    final beispiele = <Befehl<Object?>>[
      const FavoritSetzen(['a1', 'a2'], true),
      const BewertungSetzen(['a1'], 4),
      const FarbmarkeSetzen(['a1', 'a3'], null),
      const BeschreibungSetzen(['a2'], 'Am Strand – „mit Ü“'),
      const MarkierungenSetzen({
        'a1': (favorit: true, bewertung: 3, farbe: 'rot'),
        'a2': (favorit: false, bewertung: 0, farbe: null),
      }),
      const SchlagwortAnheften(['a1'], 'Strand', quelle: Tagquelle.ki),
      const SchlagwortAnheftenPerKennung('a1', 't1'),
      const SchlagwortLoesen('a1', 't1'),
      const SchlagwortAbnehmen(['a1', 'a2'], 'Strand'),
      const KiSchlagwoerterZuruecknehmen(),
      KiBegriffHinzufuegen('Leuchtturm', id: 1 << 41),
      const KiBegriffEntfernen(7),
      const VokabularUebersetzen({'Strand': 'Beach'}),
      AlbumAnlegen('al1', 'Sommer', DateTime(2026, 7, 1, 12, 30)),
      const AlbumFuellen('al1', ['a1', 'a2']),
      const AusAlbumNehmen('al1', ['a2'], albumLoeschen: true),
      const AlbumTitelbildSetzen('al1', null),
      const SucheMerken(
        's1',
        'Rote Fünfer',
        SearchFilters(query: 'Hafen', minRating: 5),
      ),
      const SucheVergessen('s1'),
      const PersonAnlegen('p1', 'Anna'),
      const GesichterZuordnen(['g1', 'g2'], 'p1'),
      const PersonenZusammenfuehren(behalten: 'p1', entfernen: 'p2'),
      const PersonTitelbildSetzen('p1', 'faces/g1.jpg'),
      const GesichterBeiseitelegen(['g3'], true),
      const ZuordnungLoesen('g1'),
      ZuordnungZuruecknehmen(
        gesichter: const [
          (id: 'g1', personId: null, ignoriert: false),
          (id: 'g2', personId: 'p2', ignoriert: true),
        ],
        personId: 'p1',
        personWarNeu: false,
        titelbildVorher: 'faces/g9.jpg',
        rueckmeldungenSeit: DateTime(2026, 10, 12, 9, 15, 30),
        allgemeineSchwelle: 0.42,
      ),
      const GesichtsEntscheidungenMerken('p1', [
        (faceId: 'g1', accepted: true, similarity: 0.61),
        (faceId: 'g2', accepted: false, similarity: 0.38),
      ], allgemeineSchwelle: 0.4),
      const GesichtsEntscheidungenVergessen('p1'),
      const VorschlaegeVerwerfen(['g4']),
      const GesichtssucheAusnehmen('a1', true),
      const BeziehungHinzufuegen('p1', 'p2', Verwandtschaft.partner),
      const BeziehungenHinzufuegen([
        (personId: 'p3', andereId: 'p1', art: Verwandtschaft.elternteil),
      ]),
      const BeziehungEntfernen('p1', 'p2', Verwandtschaft.partner),
      const ElternartAendern('p3', 'p1', Verwandtschaft.pflegeelternteil),
      LebensdatenSetzen('p1', geburt: DateTime(1950, 3, 4), tod: null),
      const GeschlechtSetzen('p1', Geschlecht.weiblich),
      EreignisHinzufuegen((
        id: 'e1',
        personId: 'p1',
        art: 'hochzeit',
        datum: DateTime(1975, 6, 7),
        ort: 'Kiel',
        notiz: null,
      )),
      const EreignisLoeschen('e1'),
      const EreignisortSetzen('e1', breite: 54.32, laenge: 10.13),
      GedcomUebernehmen(
        personen: [
          (
            id: 'p9',
            name: 'Hans',
            geschlecht: Geschlecht.maennlich,
            geburt: DateTime(1920),
            tod: DateTime(1990, 12, 31),
          ),
        ],
        kanten: const [
          (personId: 'p9', andereId: 'p1', art: Verwandtschaft.elternteil),
        ],
        ereignisse: const [
          (
            id: 'e9',
            personId: 'p9',
            art: 'geburt',
            datum: null,
            ort: 'Lübeck',
            notiz: 'laut Kirchenbuch',
          ),
        ],
      ),
      ReiseAnlegen(
        ReisenCompanion.insert(
          id: 'r1',
          name: 'Ostsee',
          von: DateTime(2025, 7, 1),
          bis: DateTime(2025, 7, 14, 18),
          angelegtAm: DateTime(2026, 1, 2, 3, 4, 5),
        ),
        const ['a1', 'a2'],
      ),
      ReiseAendern(
        'r1',
        const ReisenCompanion(notiz: Value(null), name: Value('Ostsee 2025')),
      ),
      const ReiseLoeschen('r1'),
      const ReisenZusammenfuehren('r1', ['r2', 'r3']),
      ReisetagnotizSetzen('r1', DateTime(2025, 7, 3), 'Regen'),
      const ReiseartSetzen('r1', 'wandern'),
      const AufnahmenDerReiseSetzen('r1', {'a1', 'a3'}),
      const ReisevorschlagVerwerfen('2025-07-01|2025-07-14'),
      AktivitaetAnlegen(
        AktivitaetenCompanion.insert(
          id: 'ak1',
          name: 'Gipfel',
          art: 'wandern',
          von: DateTime(2025, 7, 5, 8),
          bis: DateTime(2025, 7, 5, 16),
          angelegtAm: DateTime(2026),
        ),
        const ['a2'],
      ),
      AktivitaetAendern(
        'ak1',
        const AktivitaetenCompanion(reiseId: Value('r1')),
      ),
      const AktivitaetLoeschen('ak1'),
      const AufnahmenDerAktivitaetSetzen('ak1', {'a2'}),
      const AktivitaetsvorschlagVerwerfen('ak|2025-07-05'),
      const SpurLoeschen('s1'),
      ExportvorgabeSpeichern(
        ExportPresetsCompanion.insert(
          name: 'Web',
          erstelltAm: DateTime(2026, 2, 3),
          maxKante: const Value(2048),
          qualitaet: const Value(0.82),
        ),
      ),
      const ExportvorgabeLoeschen(3),
      EntwicklungsvorgabeSpeichern(
        const DevelopPresetsCompanion(id: Value(2), name: Value('Warm')),
      ),
      KameravorgabeSpeichern(
        const CameraPresetsCompanion(
          id: Value('k1'),
          autoFavorite: Value(true),
        ),
      ),
      const KameravorgabeSchlagwoerterSetzen('k1', ['t1', 't2']),
      const KameravorgabeLoeschen('k1'),
      RegelSpeichern(
        const AutomationRulesCompanion(
          id: Value('r1'),
          name: Value('Urlaub'),
          regionCenterLat: Value(null),
        ),
      ),
      const RegelSchlagwoerterSetzen('r1', []),
      const RegelLoeschen('r1'),
      const PapierkorbFristSetzen(an: true, tage: 30),
      const GesichtsschwelleSetzen(0.45),
      const AuswertenNachImportSetzen(false),
      const SucheUebersetzenSetzen(true),
      const AngabenSchuetzenSetzen(true),
      const OrtSetzen(['a1', 'a2'], 54.1, 10.9),
      const KameraangabenSetzen(
        'a1',
        CameraInfo(make: 'Canon', model: 'EOS R10', iso: 400, fNumber: 2.8),
      ),
      const BildbeschreibungSetzen('a1', 'Ein Hafen', deutsch: true),
      const JahrSchaetzen('a1', 1987),
      const DateinameSetzen('a1', 'IMG_0001.JPG'),
      const InDenPapierkorb(['a2']),
      const AusDemPapierkorb(['a2']),
      const DuplikateZusammenfuehren(behaltenId: 'a1', duplikatIds: ['a2']),
      const DuplikatgruppeIgnorieren(['a1', 'a2']),
      const DuplikatgruppeAufheben(['a1', 'a2']),
      const DuplikatAusnahmenLoeschen(),
      const SerieBilden('st1', ['a1', 'a2', 'a3'], 'a2'),
      const SerieAufloesen('st1'),
      const SerienvorschlagVerwerfen('a1|a2|a3'),
      const DokumentvorschlaegeVerwerfen(['a3']),
      const OrtsvorschlagVerwerfen('54.1|10.9'),
      const OrtsvorschlagUebernehmen(['a3'], 54.1, 10.9),
      const OrteAusSpurSetzen([
        (
          assetId: 'a1',
          breite: 47.4,
          laenge: 11.0,
          land: 'DE',
          region: null,
          ort: 'Garmisch',
        ),
      ]),
      ErinnerungMerken(
        erinnerungId: 'er1',
        titel: 'Vor zehn Jahren',
        tag: DateTime(2016, 10, 12),
        ids: const ['a1'],
      ),
      const ErinnerungVergessen('er1'),
      OrtsmarkeSetzen(
        OrtsmarkenCompanion.insert(
          art: 'land',
          schluessel: 'IS',
          name: 'Island',
          status: 'wunsch',
          angelegtAm: DateTime(2026, 5, 1),
        ),
      ),
      const OrtsmarkeLoeschen('land', 'IS'),
      const EntwicklungZuruecksetzen('a1'),
      MaskeneinstellungAendern(
        4,
        const DevelopMasksCompanion(
          label: Value('Himmel'),
          exposure: Value(0.3),
        ),
      ),
    ];

    String artVon(Befehl<Object?> b) => switch (b) {
      FavoritSetzen() => 'favoritSetzen',
      BewertungSetzen() => 'bewertungSetzen',
      FarbmarkeSetzen() => 'farbmarkeSetzen',
      BeschreibungSetzen() => 'beschreibungSetzen',
      MarkierungenSetzen() => 'markierungenSetzen',
      SchlagwortAnheften() => 'schlagwortAnheften',
      SchlagwortAnheftenPerKennung() => 'schlagwortAnheftenPerKennung',
      SchlagwortLoesen() => 'schlagwortLoesen',
      SchlagwortAbnehmen() => 'schlagwortAbnehmen',
      KiSchlagwoerterZuruecknehmen() => 'kiSchlagwoerterZuruecknehmen',
      KiBegriffHinzufuegen() => 'kiBegriffHinzufuegen',
      KiBegriffEntfernen() => 'kiBegriffEntfernen',
      VokabularUebersetzen() => 'vokabularUebersetzen',
      AlbumAnlegen() => 'albumAnlegen',
      AlbumFuellen() => 'albumFuellen',
      AusAlbumNehmen() => 'ausAlbumNehmen',
      AlbumTitelbildSetzen() => 'albumTitelbildSetzen',
      SucheMerken() => 'sucheMerken',
      SucheVergessen() => 'sucheVergessen',
      PersonAnlegen() => 'personAnlegen',
      GesichterZuordnen() => 'gesichterZuordnen',
      PersonenZusammenfuehren() => 'personenZusammenfuehren',
      PersonTitelbildSetzen() => 'personTitelbildSetzen',
      GesichterBeiseitelegen() => 'gesichterBeiseitelegen',
      ZuordnungLoesen() => 'zuordnungLoesen',
      ZuordnungZuruecknehmen() => 'zuordnungZuruecknehmen',
      GesichtsEntscheidungenMerken() => 'gesichtsEntscheidungenMerken',
      GesichtsEntscheidungenVergessen() => 'gesichtsEntscheidungenVergessen',
      VorschlaegeVerwerfen() => 'vorschlaegeVerwerfen',
      GesichtssucheAusnehmen() => 'gesichtssucheAusnehmen',
      BeziehungHinzufuegen() => 'beziehungHinzufuegen',
      BeziehungenHinzufuegen() => 'beziehungenHinzufuegen',
      BeziehungEntfernen() => 'beziehungEntfernen',
      ElternartAendern() => 'elternartAendern',
      LebensdatenSetzen() => 'lebensdatenSetzen',
      GeschlechtSetzen() => 'geschlechtSetzen',
      EreignisHinzufuegen() => 'ereignisHinzufuegen',
      EreignisLoeschen() => 'ereignisLoeschen',
      EreignisortSetzen() => 'ereignisortSetzen',
      GedcomUebernehmen() => 'gedcomUebernehmen',
      ReiseAnlegen() => 'reiseAnlegen',
      ReiseAendern() => 'reiseAendern',
      ReiseLoeschen() => 'reiseLoeschen',
      ReisenZusammenfuehren() => 'reisenZusammenfuehren',
      ReisetagnotizSetzen() => 'reisetagnotizSetzen',
      ReiseartSetzen() => 'reiseartSetzen',
      AufnahmenDerReiseSetzen() => 'aufnahmenDerReiseSetzen',
      ReisevorschlagVerwerfen() => 'reisevorschlagVerwerfen',
      AktivitaetAnlegen() => 'aktivitaetAnlegen',
      AktivitaetAendern() => 'aktivitaetAendern',
      AktivitaetLoeschen() => 'aktivitaetLoeschen',
      AufnahmenDerAktivitaetSetzen() => 'aufnahmenDerAktivitaetSetzen',
      AktivitaetsvorschlagVerwerfen() => 'aktivitaetsvorschlagVerwerfen',
      SpurLoeschen() => 'spurLoeschen',
      ExportvorgabeSpeichern() => 'exportvorgabeSpeichern',
      ExportvorgabeLoeschen() => 'exportvorgabeLoeschen',
      EntwicklungsvorgabeSpeichern() => 'entwicklungsvorgabeSpeichern',
      KameravorgabeSpeichern() => 'kameravorgabeSpeichern',
      KameravorgabeSchlagwoerterSetzen() => 'kameravorgabeSchlagwoerterSetzen',
      KameravorgabeLoeschen() => 'kameravorgabeLoeschen',
      RegelSpeichern() => 'regelSpeichern',
      RegelSchlagwoerterSetzen() => 'regelSchlagwoerterSetzen',
      RegelLoeschen() => 'regelLoeschen',
      PapierkorbFristSetzen() => 'papierkorbFristSetzen',
      GesichtsschwelleSetzen() => 'gesichtsschwelleSetzen',
      AuswertenNachImportSetzen() => 'auswertenNachImportSetzen',
      SucheUebersetzenSetzen() => 'sucheUebersetzenSetzen',
      AngabenSchuetzenSetzen() => 'angabenSchuetzenSetzen',
      OrtSetzen() => 'ortSetzen',
      KameraangabenSetzen() => 'kameraangabenSetzen',
      BildbeschreibungSetzen() => 'bildbeschreibungSetzen',
      JahrSchaetzen() => 'jahrSchaetzen',
      DateinameSetzen() => 'dateinameSetzen',
      InDenPapierkorb() => 'inDenPapierkorb',
      AusDemPapierkorb() => 'ausDemPapierkorb',
      DuplikateZusammenfuehren() => 'duplikateZusammenfuehren',
      DuplikatgruppeIgnorieren() => 'duplikatgruppeIgnorieren',
      DuplikatgruppeAufheben() => 'duplikatgruppeAufheben',
      DuplikatAusnahmenLoeschen() => 'duplikatAusnahmenLoeschen',
      SerieBilden() => 'serieBilden',
      SerieAufloesen() => 'serieAufloesen',
      SerienvorschlagVerwerfen() => 'serienvorschlagVerwerfen',
      DokumentvorschlaegeVerwerfen() => 'dokumentvorschlaegeVerwerfen',
      OrtsvorschlagVerwerfen() => 'ortsvorschlagVerwerfen',
      OrtsvorschlagUebernehmen() => 'ortsvorschlagUebernehmen',
      OrteAusSpurSetzen() => 'orteAusSpurSetzen',
      ErinnerungMerken() => 'erinnerungMerken',
      ErinnerungVergessen() => 'erinnerungVergessen',
      OrtsmarkeSetzen() => 'ortsmarkeSetzen',
      OrtsmarkeLoeschen() => 'ortsmarkeLoeschen',
      EntwicklungZuruecksetzen() => 'entwicklungZuruecksetzen',
      MaskeneinstellungAendern() => 'maskeneinstellungAendern',
    };

    test('jede Art hat ein Beispiel und ist zum Lesen eingetragen', () {
      expect({for (final b in beispiele) artVon(b)}, Befehl.arten.toSet());
      for (final b in beispiele) {
        expect(b.art, artVon(b));
      }
    });

    test('hin und zurück bleibt jeder Befehl derselbe', () {
      for (final b in beispiele) {
        final text = jsonEncode(b.alsJson());
        final zurueck = Befehl.ausJson(
          (jsonDecode(text) as Map).cast<String, Object?>(),
        );
        expect(zurueck.runtimeType, b.runtimeType);
        expect(jsonEncode(zurueck.alsJson()), text, reason: b.art);
      }
    });

    test('ein unbekannter Befehl ist ein Fehler, kein Stillschweigen', () {
      expect(
        () => Befehl.ausJson({'art': 'gibtEsNicht', 'werte': {}}),
        throwsFormatException,
      );
    });
  });

  group('Befehle wirken wie der direkte Aufruf', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      for (final id in ['a1', 'a2', 'a3']) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2025),
                importedAt: DateTime(2026),
              ),
            );
      }
    });
    tearDown(() => db.close());

    Future<AssetData> aufnahme(String id) async =>
        (await db.assetsByIds([id])).single;

    test(
      'Favorit, Sterne, Farbe und Beschreibung – einzeln und mehrere',
      () async {
        await db.fuehreAus(const FavoritSetzen(['a1'], true));
        await db.fuehreAus(const BewertungSetzen(['a1', 'a2'], 5));
        await db.fuehreAus(const FarbmarkeSetzen(['a2'], 'gruen'));
        await db.fuehreAus(const BeschreibungSetzen(['a2', 'a3'], 'Hafen'));
        final a1 = await aufnahme('a1');
        final a2 = await aufnahme('a2');
        final a3 = await aufnahme('a3');
        expect([a1.isFavorite, a1.rating, a1.colorLabel], [true, 5, null]);
        expect([a2.isFavorite, a2.rating, a2.colorLabel], [false, 5, 'gruen']);
        expect([a2.description, a3.description], ['Hafen', 'Hafen']);
        expect(a3.rating, 0);
      },
    );

    test('Markierungen stellen je Aufnahme den Stand davor her', () async {
      await db.fuehreAus(const FavoritSetzen(['a1', 'a2'], true));
      await db.fuehreAus(const BewertungSetzen(['a1', 'a2'], 4));
      await db.fuehreAus(
        const MarkierungenSetzen({
          'a1': (favorit: false, bewertung: 2, farbe: 'rot'),
          'a2': (favorit: true, bewertung: 0, farbe: null),
        }),
      );
      final a1 = await aufnahme('a1');
      final a2 = await aufnahme('a2');
      expect([a1.isFavorite, a1.rating, a1.colorLabel], [false, 2, 'rot']);
      expect([a2.isFavorite, a2.rating, a2.colorLabel], [true, 0, null]);
    });

    test('Schlagwörter: Hand schlägt KI, Abnehmen räumt auf', () async {
      await db.fuehreAus(
        const SchlagwortAnheften(['a1'], 'Strand', quelle: Tagquelle.ki),
      );
      await db.fuehreAus(const SchlagwortAnheften(['a1', 'a2'], 'Strand'));
      // Die Bilderkennung darf die Handvergabe nicht zurückholen.
      await db.fuehreAus(
        const SchlagwortAnheften(['a2'], 'Strand', quelle: Tagquelle.ki),
      );
      expect(await db.kiTagAnzahl(), 0);
      expect(await db.tragenSchlagwort(['a1', 'a2', 'a3'], 'Strand'), {
        'a1',
        'a2',
      });
      await db.fuehreAus(const SchlagwortAbnehmen(['a1', 'a2'], 'Strand'));
      expect(await db.tragenSchlagwort(['a1', 'a2'], 'Strand'), isEmpty);
      await db.fuehreAus(
        const SchlagwortAnheften(['a3'], 'Hafen', quelle: Tagquelle.ki),
      );
      expect(await db.fuehreAus(const KiSchlagwoerterZuruecknehmen()), 1);
    });

    test('Alben: anlegen, füllen, Titelbild, wieder herausnehmen', () async {
      await db.fuehreAus(AlbumAnlegen('al1', 'Sommer', DateTime(2026, 7, 1)));
      await db.fuehreAus(const AlbumFuellen('al1', ['a1', 'a2', 'a3']));
      await db.fuehreAus(const AlbumTitelbildSetzen('al1', 'a2'));
      await db.fuehreAus(const AusAlbumNehmen('al1', ['a3']));
      expect(await db.imAlbum('al1', ['a1', 'a2', 'a3']), {'a1', 'a2'});
      await db.fuehreAus(
        const AusAlbumNehmen('al1', ['a1'], albumLoeschen: true),
      );
      expect(await db.imAlbum('al1', ['a1', 'a2', 'a3']), isEmpty);
    });

    test(
      'Personen: anlegen, zuordnen, beiseitelegen, zusammenführen',
      () async {
        for (final g in ['g1', 'g2', 'g3']) {
          await db.insertFace(
            FacesCompanion.insert(
              id: g,
              assetId: 'a1',
              boxX: 0,
              boxY: 0,
              boxW: 0.1,
              boxH: 0.1,
            ),
          );
        }
        Future<Map<String, (String?, bool)>> stand() async => {
          for (final f in await db.select(db.faces).get())
            f.id: (f.personId, f.isIgnored),
        };
        await db.fuehreAus(const PersonAnlegen('p1', 'Anna'));
        await db.fuehreAus(const PersonAnlegen('p2', 'Anna B.'));
        await db.fuehreAus(const GesichterZuordnen(['g1', 'g2'], 'p1'));
        await db.fuehreAus(const GesichterZuordnen(['g3'], 'p2'));
        await db.fuehreAus(const GesichterBeiseitelegen(['g2'], true));
        expect(await stand(), {
          'g1': ('p1', false),
          'g2': (null, true),
          'g3': ('p2', false),
        });
        await db.fuehreAus(
          const PersonenZusammenfuehren(behalten: 'p1', entfernen: 'p2'),
        );
        await db.fuehreAus(const ZuordnungLoesen('g1'));
        expect(await stand(), {
          'g1': (null, false),
          'g2': (null, true),
          'g3': ('p1', false),
        });
        expect(
          [for (final p in await db.select(db.people).get()) p.id],
          ['p1'],
        );
      },
    );

    test('Stammbaum: Verwandtschaften, Lebensdaten, GEDCOM', () async {
      await db.fuehreAus(const PersonAnlegen('p1', 'Anna'));
      await db.fuehreAus(const PersonAnlegen('p2', 'Ben'));
      expect(
        await db.fuehreAus(
          const BeziehungHinzufuegen('p1', 'p2', Verwandtschaft.partner),
        ),
        isNull,
      );
      await db.fuehreAus(
        LebensdatenSetzen('p1', geburt: DateTime(1950, 3, 4), tod: null),
      );
      await db.fuehreAus(const GeschlechtSetzen('p1', Geschlecht.weiblich));
      await db.fuehreAus(
        GedcomUebernehmen(
          personen: [
            (
              id: 'p9',
              name: 'Hans',
              geschlecht: Geschlecht.maennlich,
              geburt: DateTime(1920),
              tod: null,
            ),
          ],
          kanten: const [
            (personId: 'p9', andereId: 'p1', art: Verwandtschaft.elternteil),
          ],
          ereignisse: const [
            (
              id: 'e9',
              personId: 'p9',
              art: 'geburt',
              datum: null,
              ort: 'Lübeck',
              notiz: null,
            ),
          ],
        ),
      );
      expect(
        await db.fuehreAus(
          const BeziehungEntfernen('p1', 'p2', Verwandtschaft.partner),
        ),
        isTrue,
      );
      final kanten = await db.select(db.personBeziehungen).get();
      expect(kanten, hasLength(1));
      final anna = (await db.select(db.people).get()).firstWhere(
        (p) => p.id == 'p1',
      );
      expect(anna.geburtsdatum, DateTime(1950, 3, 4));
      expect(geschlechtAusText(anna.geschlecht), Geschlecht.weiblich);
      final ereignisse = await db.select(db.lebensereignisse).get();
      expect([for (final e in ereignisse) e.ort], ['Lübeck']);
    });

    test(
      'Zeilen im Befehl: anlegen wie direkt, ändern nur das Gesetzte',
      () async {
        final reise = ReisenCompanion.insert(
          id: 'r1',
          name: 'Ostsee',
          von: DateTime(2025, 7, 1),
          bis: DateTime(2025, 7, 14, 18),
          notiz: const Value('Strandkorb'),
          angelegtAm: DateTime(2026, 1, 2, 3, 4, 5),
        );
        // Einmal über JSON, wie es ein Server bekäme.
        Befehl<Object?> ueberJson(Befehl<Object?> b) => Befehl.ausJson(
          (jsonDecode(jsonEncode(b.alsJson())) as Map).cast<String, Object?>(),
        );
        await db.fuehreAus(ueberJson(ReiseAnlegen(reise, const ['a1', 'a2'])));
        final direkt = AppDatabase(NativeDatabase.memory());
        addTearDown(direkt.close);
        await direkt.into(direkt.reisen).insert(reise);
        expect(
          (await db.select(db.reisen).getSingle()).toJson(),
          (await direkt.select(direkt.reisen).getSingle()).toJson(),
        );
        await db.fuehreAus(
          ueberJson(
            ReiseAendern(
              'r1',
              const ReisenCompanion(
                name: Value('Ostsee 2025'),
                notiz: Value(null),
              ),
            ),
          ),
        );
        final danach = await db.select(db.reisen).getSingle();
        expect(danach.name, 'Ostsee 2025');
        expect(danach.notiz, isNull, reason: 'null leert die Spalte');
        expect(danach.bis, DateTime(2025, 7, 14, 18), reason: 'nicht gesetzt');
        expect(
          {for (final a in await db.aufnahmenDerReise('r1')) a.id},
          {'a1', 'a2'},
        );
      },
    );

    test('Ort, Papierkorb und Serien', () async {
      await db.fuehreAus(const OrtSetzen(['a1', 'a2'], 54.1, 10.9));
      await db.fuehreAus(const OrtSetzen(['a2'], null, null));
      await db.fuehreAus(const InDenPapierkorb(['a3']));
      await db.fuehreAus(const SerieBilden('st1', ['a1', 'a2'], 'a2'));
      final a1 = await aufnahme('a1');
      final a2 = await aufnahme('a2');
      final a3 = await aufnahme('a3');
      expect([a1.latitude, a1.longitude], [54.1, 10.9]);
      expect([a2.latitude, a2.longitude], [null, null]);
      expect(a3.isTrashed, isTrue);
      expect(a3.trashedAt, isNotNull);
      expect([a1.stackId, a2.stackId, a2.isStackCover], ['st1', 'st1', true]);
      await db.fuehreAus(const AusDemPapierkorb(['a3']));
      await db.fuehreAus(const SerieAufloesen('st1'));
      expect((await aufnahme('a3')).isTrashed, isFalse);
      expect((await aufnahme('a1')).stackId, isNull);
    });

    test('jeder ausgeführte Befehl wird gemeldet, nach der Wirkung', () async {
      final gemeldet = <String>[];
      db.befehlsbeobachter.add((b) async {
        gemeldet.add('${b.art}:${(await aufnahme('a1')).rating}');
      });
      await db.fuehreAus(const BewertungSetzen(['a1'], 3));
      await pumpEventQueue();
      expect(gemeldet, ['bewertungSetzen:3']);
    });
  });

  /// Issue #107: Eine Zeile, die ein Befehl anlegt, hat auf jedem Gerät und
  /// auf dem Server dieselbe Kennung – auch wenn der Befehl offline auf
  /// einem Gerät vorweggenommen und erst später auf dem Server ausgeführt
  /// wird. Geprüft an zwei getrennten Datenbanken: Derselbe Befehl, über
  /// JSON weitergereicht, legt in beiden dieselbe Zeile an.
  group('Kennungen kommen aus dem Befehl', () {
    late AppDatabase hier, dort;
    setUp(() {
      hier = AppDatabase(NativeDatabase.memory());
      dort = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await hier.close();
      await dort.close();
    });

    Future<void> beide(Befehl<Object?> b) async {
      await hier.fuehreAus(b);
      await dort.fuehreAus(Befehl.ausJson(jsonDecode(jsonEncode(b.alsJson()))));
    }

    test('Export- und Entwicklungsvorgaben, KI-Begriffe', () async {
      await beide(
        ExportvorgabeSpeichern(
          ExportPresetsCompanion.insert(
            name: 'Web',
            erstelltAm: DateTime(2026, 10, 13),
          ),
        ),
      );
      await beide(
        EntwicklungsvorgabeSpeichern(
          DevelopPresetsCompanion.insert(
            name: 'Warm',
            erstelltAm: DateTime(2026, 10, 13),
          ),
        ),
      );
      await beide(KiBegriffHinzufuegen('Leuchtturm'));
      Future<List<int>> kennungen(AppDatabase db) async => [
        for (final v in await db.select(db.exportPresets).get()) v.id,
        for (final v in await db.select(db.developPresets).get()) v.id,
        for (final v in await db.select(db.aiTagVocabulary).get())
          if (v.term == 'Leuchtturm') v.id,
      ];
      final h = await kennungen(hier);
      expect(h, hasLength(3));
      expect(h, everyElement(greaterThanOrEqualTo(1 << 40)));
      expect(await kennungen(dort), h);
    });

    test('Schlagwörter: die Kennung folgt aus dem Namen', () async {
      await beide(const SchlagwortAnheften([], 'Leuchtturm'));
      expect(
        await hier.ensureTag('Leuchtturm'),
        schlagwortKennung('Leuchtturm'),
      );
      expect(
        await dort.ensureTag('Leuchtturm'),
        schlagwortKennung('Leuchtturm'),
      );
      expect(
        schlagwortKennung('Leuchtturm'),
        isNot(schlagwortKennung('Hafen')),
      );
    });
  });

  group('Jeder Schreibzugriff ist eingeordnet', () {
    final gefunden = _schreibmethoden();

    test('die Suche findet die Schreibmethoden', () {
      // Ein Riegel gegen einen Suchausdruck, der nach einer Umformatierung
      // nichts mehr findet – dann wäre der Rest dieser Gruppe grün, weil er
      // nichts prüft.
      expect(gefunden.length, greaterThan(150));
      expect(gefunden, contains('setFavorite'));
    });

    test('jede Schreibmethode steht in der Einordnung', () {
      final fehlt = gefunden.difference(_einordnung.keys.toSet());
      expect(
        fehlt,
        isEmpty,
        reason:
            'Neue Schreibmethode ohne Einordnung. Ist sie eine Änderung '
            'durch den Nutzer, gehört sie als Befehl nach '
            'packages/kern/lib/befehle; sonst in _einordnung unten.',
      );
    });

    test('die Einordnung nennt keine Methode, die es nicht mehr gibt', () {
      expect(_einordnung.keys.toSet().difference(gefunden), isEmpty);
    });

    test('was die App ändert, läuft als Befehl', () {
      // Eine Änderung durch den Nutzer, die noch kein Befehl ist, darf die
      // App nicht aufrufen – sonst ginge sie später am Server vorbei.
      final offen = [
        for (final e in _einordnung.entries)
          if (e.value == _Art.nutzer) e.key,
      ];
      final funde = <String>[];
      for (final datei in dartQuellen()) {
        final pfad = datei.path.replaceAll(r'\', '/');
        if (pfad.contains('/kern/lib/db/')) continue;
        final text = datei.readAsStringSync();
        for (final m in offen) {
          if (RegExp(r'\b\w*[dD]b\??\.' + m + r'\(').hasMatch(text)) {
            funde.add('$pfad $m');
          }
        }
      }
      expect(funde, isEmpty);
    });

    test('was ein Befehl ist, ruft niemand mehr direkt auf', () {
      final befehle = [
        for (final e in _einordnung.entries)
          if (e.value == _Art.befehl) e.key,
      ];
      final funde = <String>[];
      for (final datei in dartQuellen()) {
        final pfad = datei.path.replaceAll(r'\', '/');
        if (pfad.contains('/kern/lib/db/') ||
            pfad.contains('/kern/lib/befehle/')) {
          continue;
        }
        final zeilen = datei.readAsLinesSync();
        for (var i = 0; i < zeilen.length; i++) {
          for (final m in befehle) {
            // Über eine Datenbank: `db.`, `_db.`, `rasterDb.` … So wie die
            // Bibliothek heisst sie überall. Eine gleichnamige Methode
            // anderswo (LibraryState.setFaceSimilarityThreshold führt den
            // Befehl selbst aus) ist damit kein Fund.
            if (RegExp(r'\b\w*[dD]b\??\.' + m + r'\(').hasMatch(zeilen[i])) {
              funde.add('$pfad:${i + 1} $m');
            }
          }
        }
      }
      expect(funde, isEmpty);
    });
  });
}

/// Was eine Schreibmethode der Datenbank ist.
enum _Art {
  /// Als Befehl umgesetzt (packages/kern/lib/befehle) – nur noch über
  /// `fuehreAus` erreichbar.
  befehl,

  /// Eine Änderung durch den Nutzer, die (noch) kein Befehl ist. Die App
  /// ruft keine davon mehr auf, nur Tests – siehe „was die App ändert,
  /// läuft als Befehl“.
  nutzer,

  /// Eine Änderung, an der Dateien hängen (Import, Sperren, Bearbeitungen
  /// mit gerechnetem Ergebnis). Wie sie sich abgleicht, entscheidet erst
  /// das Protokoll für Dateien.
  datei,

  /// Ergebnis einer Auswertung; geht später als Ergebnis eines Auftrags
  /// an den Server, nicht als Befehl.
  ergebnis,

  /// Gilt nur auf diesem Rechner: Ansicht, Schlüssel, Warteschlangen,
  /// Sicherungsstand, Reparaturen am Dateibestand.
  lokal,
}

/// Die Einordnung aller Schreibmethoden in packages/kern/lib/db/abfragen.
const _einordnung = <String, _Art>{
  // Aufnahmen
  'setFavorite': _Art.befehl,
  'setFavoriteBulk': _Art.befehl,
  'setRating': _Art.befehl,
  'setRatingBulk': _Art.befehl,
  'setColorLabel': _Art.befehl,
  'setColorLabelBulk': _Art.befehl,
  'setDescription': _Art.befehl,
  'setDescriptionBulk': _Art.befehl,
  'setzeMarkierungen': _Art.befehl,
  'setLocation': _Art.befehl,
  'setLocationBulk': _Art.befehl,
  'setFileCreatedAt': _Art.nutzer,
  'setFileCreatedAtBulk': _Art.nutzer,
  // Verschiebt das Original in den Ordner des neuen Datums.
  'setAufnahmezeitpunkt': _Art.datei,
  'setCameraMetadata': _Art.befehl,
  'setAiCaptionVonHand': _Art.befehl,
  'setzeGeschaetztesJahr': _Art.befehl,
  'setOriginalFileName': _Art.befehl,
  'moveToTrash': _Art.befehl,
  'restoreFromTrash': _Art.befehl,
  'deleteAssetRows': _Art.datei,
  'insertAsset': _Art.datei,
  'setEditedAssetFile': _Art.datei,
  // Schlagwörter, Alben, Suchen
  'tagAsset': _Art.befehl,
  'tagAssetById': _Art.befehl,
  'tagAssetsBulk': _Art.befehl,
  'untagAsset': _Art.befehl,
  'nimmSchlagwortAb': _Art.befehl,
  'nimmKiTagsZurueck': _Art.befehl,
  'ensureTag': _Art.nutzer,
  'createAlbum': _Art.befehl,
  'addAssetsToAlbum': _Art.befehl,
  'removeAssetFromAlbum': _Art.befehl,
  'nimmAusAlbum': _Art.befehl,
  'setzeAlbumTitelbild': _Art.befehl,
  'createSavedSearch': _Art.befehl,
  'deleteSavedSearch': _Art.befehl,
  'addAiTagTerm': _Art.befehl,
  'removeAiTagTerm': _Art.befehl,
  'uebersetzeVokabular': _Art.befehl,
  // Duplikate und Serien
  'fuehreDuplikateZusammen': _Art.befehl,
  'hebeDuplikatgruppeAuf': _Art.befehl,
  'ignoriereDuplikatgruppe': _Art.befehl,
  'loescheDuplikatAusnahmen': _Art.befehl,
  'createStack': _Art.befehl,
  'unstackAssets': _Art.befehl,
  'verwirfSerienvorschlag': _Art.befehl,
  // Vorschläge, Erinnerungen, Orte
  'verwirfDokumentvorschlaege': _Art.befehl,
  'verwirfOrtsvorschlag': _Art.befehl,
  'uebernimmOrtsvorschlag': _Art.befehl,
  'merkeErinnerung': _Art.befehl,
  'vergissErinnerung': _Art.befehl,
  'setzeOrtsmarke': _Art.befehl,
  'loescheOrtsmarke': _Art.befehl,
  'setzeOrte': _Art.befehl,
  // Personen und Gesichter
  'createPerson': _Art.befehl,
  'assignFacesToPerson': _Art.befehl,
  'mergePeople': _Art.befehl,
  'setPersonCover': _Art.befehl,
  'setFacesIgnored': _Art.befehl,
  'loescheAlleUnbenanntenErkennungen': _Art.datei,
  'loescheGesicht': _Art.datei,
  'loeseZuordnung': _Art.befehl,
  'nimmZuordnungZurueck': _Art.befehl,
  'merkeGesichtsEntscheidungen': _Art.befehl,
  'vergissGesichtsEntscheidungen': _Art.befehl,
  'verwirfVorschlaege': _Art.befehl,
  'setzeGesichtssucheAusgenommen': _Art.befehl,
  'insertFace': _Art.datei,
  // Stammbaum
  'setzeGeschlecht': _Art.befehl,
  'setzeLebensdaten': _Art.befehl,
  'setzeEreignisort': _Art.befehl,
  'aendereElternart': _Art.befehl,
  'entferneBeziehung': _Art.befehl,
  'fuegeBeziehungHinzu': _Art.befehl,
  'fuegeBeziehungenHinzu': _Art.befehl,
  'fuegeEreignisHinzu': _Art.befehl,
  'loescheEreignis': _Art.befehl,
  'uebernehmeGedcom': _Art.befehl,
  // Reisen, Aktivitäten, Spuren
  'reiseAnlegen': _Art.befehl,
  'reiseAendern': _Art.befehl,
  'reiseLoeschen': _Art.befehl,
  'reisenZusammenfuehren': _Art.befehl,
  'setzeReisetagnotiz': _Art.befehl,
  'setzeReiseart': _Art.befehl,
  'aufnahmeAusReise': _Art.nutzer,
  'aufnahmenZurReise': _Art.nutzer,
  'setzeAufnahmenDerReise': _Art.befehl,
  'verwirfReisevorschlag': _Art.befehl,
  'aktivitaetAnlegen': _Art.befehl,
  'aktivitaetAendern': _Art.befehl,
  'aktivitaetLoeschen': _Art.befehl,
  'setzeAufnahmenDerAktivitaet': _Art.befehl,
  'verwirfAktivitaetsvorschlag': _Art.befehl,
  // Bringt die Punkte einer GPX-Datei mit – zehntausend Zeilen sind
  // kein Befehl, sondern eine Datei.
  'spurAnlegen': _Art.datei,
  'spurAendern': _Art.nutzer,
  'spurLoeschen': _Art.befehl,
  // Bearbeiten: Einstellungen sind Befehle, das gerechnete Bild eine Datei
  'resetDevelopSettings': _Art.befehl,
  'saveDevelopResult': _Art.datei,
  'createDevelopMask': _Art.datei,
  'updateDevelopMaskShape': _Art.datei,
  'updateDevelopMaskAdjustments': _Art.befehl,
  'deleteDevelopMask': _Art.datei,
  'saveVideoTrim': _Art.datei,
  'resetVideoTrim': _Art.datei,
  // Vorgaben der Bibliothek
  'upsertAutomationRule': _Art.befehl,
  'deleteAutomationRule': _Art.befehl,
  'setAutomationRuleTags': _Art.befehl,
  'upsertCameraPreset': _Art.befehl,
  'deleteCameraPreset': _Art.befehl,
  'setCameraPresetTags': _Art.befehl,
  'upsertDevelopPreset': _Art.befehl,
  'deleteDevelopPreset': _Art.nutzer,
  'upsertExportPreset': _Art.befehl,
  'deleteExportPreset': _Art.befehl,
  'setTrashAutoDeleteConfig': _Art.befehl,
  'setFaceSimilarityThreshold': _Art.befehl,
  'setAutoAnalyzeAfterImport': _Art.befehl,
  'setzeUebersetzeSucheUndTags': _Art.befehl,
  'setzeUebersetzeBeschreibungen': _Art.nutzer,
  // Gesperrter Ordner: Inhalte werden auf dem Gerät verschlüsselt
  'setAssetsLocked': _Art.datei,
  'hidePrivateMetadata': _Art.datei,
  'restorePrivateMetadata': _Art.datei,
  'setProtectPrivateMetadata': _Art.befehl,
  'verlegeProfilbilderVon': _Art.datei,
  // Ergebnisse der Auswertungen
  'saveEmbedding': _Art.ergebnis,
  'setzeVideoeinbettungen': _Art.ergebnis,
  'markVideobilderGeprueft': _Art.ergebnis,
  'markAiTagsScanned': _Art.ergebnis,
  'setAiCaption': _Art.ergebnis,
  'setAiCaptionDe': _Art.ergebnis,
  'setOcrResult': _Art.ergebnis,
  'setTranskript': _Art.ergebnis,
  'setSharpnessScore': _Art.ergebnis,
  'setLocationNames': _Art.ergebnis,
  'setLocationNamesBulk': _Art.ergebnis,
  'markDatumGeprueft': _Art.ergebnis,
  'markGpsGeprueft': _Art.ergebnis,
  'uebernimmFotoangabenFuerBewegtbild': _Art.ergebnis,
  'uebernimmVideoangaben': _Art.ergebnis,
  'setzeEreignisorte': _Art.ergebnis,
  'merkeVorschlaege': _Art.ergebnis,
  'setzeGesichtsschaerfe': _Art.ergebnis,
  'setzeGesichtsausschnitt': _Art.ergebnis,
  'deleteUnassignedFacesForAsset': _Art.ergebnis,
  'markFacesScanned': _Art.ergebnis,
  'linkAssets': _Art.ergebnis,
  'setzeDateiart': _Art.ergebnis,
  'updateThumbnailInfo': _Art.ergebnis,
  'clearDerivedContentData': _Art.ergebnis,
  'wanderpunkteFuer': _Art.ergebnis,
  // Nur dieser Rechner
  'setSprache': _Art.lokal,
  'setThemeMode': _Art.lokal,
  'setzeSchwebeVorschau': _Art.lokal,
  'setzeCartoSchluesselWert': _Art.lokal,
  'setzeEigeneKarteWert': _Art.lokal,
  'setzeGelaendeKarte': _Art.lokal,
  'setzeGelaendeStimmung': _Art.lokal,
  'setzeKarteHochaufloesend': _Art.lokal,
  'setzeKartenansicht': _Art.lokal,
  'setzeLebensbaum': _Art.lokal,
  'setzeStammbaumZuletzt': _Art.lokal,
  'setzeListenspalten': _Art.lokal,
  'setzeZeitleisteForm': _Art.lokal,
  'setzeZeitleisteKachelstufe': _Art.lokal,
  'setzeZeitleisteMitTagen': _Art.lokal,
  'setzeZeitleisteSortierung': _Art.lokal,
  'setzeMaxGleichzeitigeAufgaben': _Art.lokal,
  'setzeUeberwachtenOrdner': _Art.lokal,
  'setLastTrashPurgeAt': _Art.lokal,
  'merkeAufgabenlauf': _Art.lokal,
  'saveVaultKey': _Art.lokal,
  'clearVaultKey': _Art.lokal,
  'saveBackupKey': _Art.lokal,
  'clearBackupKey': _Art.lokal,
  'insertBackupRecord': _Art.lokal,
  'markBackedUp': _Art.lokal,
  'markAutoBackedUp': _Art.lokal,
  'setAutoBackupConfig': _Art.lokal,
  'setAutoBackupMaxMbPerRun': _Art.lokal,
  'setLastAutoBackupAt': _Art.lokal,
  'clearAutoBackupDestination': _Art.lokal,
  'createRestoreJob': _Art.lokal,
  'completeRestoreJob': _Art.lokal,
  'deleteRestoreJob': _Art.lokal,
  'markRestoreJobStatus': _Art.lokal,
  'requeueRestoreJob': _Art.lokal,
  'resetStuckRunningRestoreJobs': _Art.lokal,
  'updateRestoreJobProgress': _Art.lokal,
  'clearMissingDevelopedPath': _Art.lokal,
  'clearMissingFaceCropPath': _Art.lokal,
  'clearMissingPreviewPath': _Art.lokal,
  'clearMissingRestoredPath': _Art.lokal,
  'clearMissingThumbnailPath': _Art.lokal,
  'clearMissingTrimmedPath': _Art.lokal,
};

/// Die öffentlichen Methoden der Abfrage-Erweiterungen, die schreiben.
///
/// Gelesen wird der Quelltext: Kopf einer Methode auf der ersten
/// Einrückungsstufe, ihr Rumpf bis zum nächsten Kopf, und darin ein
/// schreibender Aufruf von drift.
Set<String> _schreibmethoden() {
  final kopf = RegExp(
    r'^  (?:Future<[^\n]*?>|Stream<[^\n]*?>|void|int|bool|String\??|'
    r'[A-Z][A-Za-z<>?, ]*)\s+([a-z][A-Za-z0-9]*)\s*\(',
    multiLine: true,
  );
  final schreibt = RegExp(
    r'\b(update|into|delete|customStatement|customUpdate|customInsert|batch|'
    r'transaction|insertOnConflictUpdate|replace|write)\(',
  );
  final namen = <String>{};
  final dateien = [
    ...Directory('packages/kern/lib/db/abfragen').listSync().whereType<File>(),
    File('packages/kern/lib/db/database.dart'),
  ].where((f) => f.path.endsWith('.dart'));
  for (final datei in dateien) {
    final text = datei.readAsStringSync();
    final koepfe = kopf.allMatches(text).toList();
    for (var i = 0; i < koepfe.length; i++) {
      final name = koepfe[i].group(1)!;
      if (name.startsWith('watch')) continue;
      final ende = i + 1 < koepfe.length ? koepfe[i + 1].start : text.length;
      if (schreibt.hasMatch(text.substring(koepfe[i].end, ende))) {
        namen.add(name);
      }
    }
  }
  return namen;
}

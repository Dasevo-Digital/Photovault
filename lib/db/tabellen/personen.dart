part of '../database.dart';

// Tabellen: Personen, Gesichter, Stammbaum.

@DataClassName('PersonData')
class People extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get coverFaceCropPath => text().nullable()();

  /// Persönliche Wiedererkennungs-Schwelle, abgeleitet aus den bisherigen
  /// Entscheidungen des Nutzers (siehe [FaceMatchFeedback] und
  /// face_threshold.dart). `null` = die allgemeine Schwelle gilt.
  ///
  /// Als gespeicherter Wert statt bei jedem Vorschlag neu gerechnet, damit
  /// die Zahl im Personen-Bildschirm dieselbe ist, nach der tatsächlich
  /// entschieden wurde – eine Schwelle, die sich zwischen Anzeige und
  /// Anwendung unterscheidet, wäre nicht erklärbar.
  RealColumn get similarityThreshold => real().nullable()();

  /// Lebensdaten – nur für den Stammbaum, und beide freiwillig.
  ///
  /// Als volles Datum und nicht als Jahreszahl: Bei Verwandten aus der
  /// eigenen Zeit kennt man den Tag, bei den Urgroßeltern oft nur das
  /// Jahr. Ein Feld, das nur Jahre aufnimmt, verlöre die genaue Angabe;
  /// eines für den Tag lässt sich mit dem 1. Januar füllen, wenn mehr
  /// nicht bekannt ist. Was davon angezeigt wird, entscheidet die
  /// Darstellung, nicht die Speicherung.
  DateTimeColumn get geburtsdatum => dateTime().nullable()();
  DateTimeColumn get sterbedatum => dateTime().nullable()();

  /// Geschlecht – ausschließlich für die Verwandtschaftsbezeichnungen.
  ///
  /// Ohne diese Angabe gibt es kein „Schwester", nur „Geschwister": Fast
  /// jede Bezeichnung im Deutschen wie im Englischen ist geschlechtsgebunden.
  /// `null` ist deshalb kein Mangel, sondern ein gültiger Zustand – dann
  /// erscheint die geschlechtsneutrale Form, und niemand muss eine Angabe
  /// machen, die er nicht kennt oder nicht machen will. Werte siehe
  /// `Geschlecht` in services/verwandtschaftsgrad.dart.
  TextColumn get geschlecht => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ein Ereignis im Leben einer Person – Hochzeit, Umzug, Berufsantritt.
///
/// Eigene Tabelle und nicht Spalten an [People]: Geburt und Tod gibt es
/// genau einmal, alles andere beliebig oft. Wer dreimal umgezogen ist,
/// hat drei Umzüge, und eine feste Spaltenzahl wäre entweder zu klein
/// oder meistens leer.
///
/// Geburt und Tod bleiben bewusst dort, wo sie sind: Sie stehen in fast
/// jeder Ansicht unter dem Namen, und sie hier ein zweites Mal zu führen
/// hiesse, zwei Wahrheiten zu haben.
class Lebensereignisse extends Table {
  TextColumn get id => text()();
  TextColumn get personId => text()();

  /// Siehe `Ereignisart` in services/lebenslauf.dart.
  TextColumn get art => text()();

  /// Freiwillig – manchmal weiß man nur, *dass* etwas war.
  DateTimeColumn get datum => dateTime().nullable()();
  TextColumn get ort => text().nullable()();
  TextColumn get notiz => text().nullable()();

  /// Der Ort als Koordinate, sobald er auflösbar war.
  ///
  /// **Zusätzlich zu [ort], nicht statt dessen.** Ein Ortsname, den der
  /// GeoNames-Auszug nicht kennt – ein untergegangenes Dorf, ein
  /// Gutshof, eine alte Schreibweise – bleibt als Text stehen und ist
  /// damit nicht verloren; er landet nur auf keiner Karte. Beide Felder
  /// zu koppeln hiesse, solche Einträge stillschweigend wegzuwerfen.
  ///
  /// Und getrennt von [ort] auch deshalb, weil die Zuordnung eine
  /// **Vermutung** ist: „Springfield" trifft in den USA über zwanzig Mal
  /// zu. Wer die Koordinate von Hand berichtigt, ändert diese Felder,
  /// ohne dass der aufgeschriebene Name sich ändert.
  RealColumn get ortBreite => real().nullable()();
  RealColumn get ortLaenge => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Der Stand eines Gesichts, bevor es zugeordnet wurde.
///
/// Wird von [AppDatabase.gesichtsstand] gelesen und von
/// [AppDatabase.nimmZuordnungZurueck] zurückgeschrieben.
typedef Gesichtsstand = ({String id, String? personId, bool ignoriert});

/// Eine Verwandtschaft zwischen zwei Personen – die Grundlage des
/// Stammbaums.
///
/// Eine Kantenliste statt Spalten wie „Mutter"/„Vater" an [People]. Feste
/// Spalten legen die Familienform fest, bevor der Nutzer sie beschreibt:
/// Zwei Elternteile passen, drei (Stief-, Pflegeeltern) passen nicht mehr,
/// und für Partner bräuchte es ohnehin eine eigene Struktur. Eine
/// Kantenliste beschreibt jede dieser Formen, ohne dass das Schema davon
/// wüsste.
///
/// [art] entscheidet, wie die beiden Enden zu lesen sind:
/// * `elternteil`: [andereId] ist ein Elternteil von [personId]. Gerichtet
///   – die Umkehrung ist „Kind" und ergibt sich aus derselben Zeile.
/// * `partner`: symmetrisch. Genau **eine** Zeile je Paar, mit der
///   kleineren Kennung in [personId] (siehe `partnerKanteFuer`). Zwei
///   Zeilen je Paar könnten auseinanderlaufen, und dann wäre nicht
///   entscheidbar, welche gilt.
class PersonBeziehungen extends Table {
  TextColumn get personId => text()();
  TextColumn get andereId => text()();
  TextColumn get art => text()();

  @override
  Set<Column> get primaryKey => {personId, andereId, art};
}

/// Eine festgehaltene Entscheidung über einen Wiedererkennungs-Vorschlag.
///
/// Bisher wurden Zuordnungen zwar übernommen, aber nicht ausgewertet: Wer
/// einen Vorschlag korrigierte, bekam beim nächsten Lauf denselben erneut.
/// Diese Tabelle ist das Gedächtnis dafür.
///
/// [similarity] ist der Wert **zum Entscheidungszeitpunkt** und der
/// eigentliche Grund für die Tabelle. Dass ein Gesicht zu einer Person
/// gehört, steht schon in [Faces.personId]; woran die Erkennung das hätte
/// merken können, steht nur hier.
///
/// Bewusst NICHT festgehalten wird das Überspringen eines Vorschlags:
/// "nicht jetzt" ist keine Aussage darüber, ob der Vorschlag richtig war,
/// und als Ablehnung gewertet würde es die Schwelle verderben.
@DataClassName('FaceMatchFeedbackData')
class FaceMatchFeedback extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personId => text()();
  TextColumn get faceId => text()();
  BoolColumn get accepted => boolean()();
  RealColumn get similarity => real()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Ein einzelnes erkanntes Gesicht innerhalb eines Assets (Bounding Box,
/// relativ 0..1). `personId` ist null, solange das Gesicht noch keiner
/// Person zugeordnet wurde. `embedding` ist nur gefüllt, wenn ein
/// Gesichts-Embedding-Modell installiert ist (siehe FaceEmbeddingService).
@DataClassName('FaceData')
class Faces extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()();
  TextColumn get personId => text().nullable()();
  RealColumn get boxX => real()();
  RealColumn get boxY => real()();
  RealColumn get boxW => real()();
  RealColumn get boxH => real()();
  TextColumn get cropRelativePath => text().nullable()();
  BlobColumn get embedding => blob().nullable()();

  /// Wahrscheinlichkeit "Augen offen" (0..1, siehe EyeStateService) – `null`
  /// heißt "noch nicht berechnet" (kein Landmark verfügbar, oder das
  /// Augen-Modell war zum Scan-Zeitpunkt nicht installiert), NICHT "Augen
  /// geschlossen".
  ///
  /// **Alle vor Fassung 63 berechneten Werte sind gelöscht.** Sie entstanden
  /// mit einer falschen Normierung (0..1 statt -1..1) und stimmten nicht:
  /// An der echten Bibliothek meldete das Modell für 64,5 % der grossen
  /// Gesichter „geschlossen"; fünf zufällig herausgegriffene Gesichter mit
  /// dem Wert 0,00 hatten allesamt die Augen offen, ein schlafendes Kind
  /// stand bei 0,98. Nachgesehen wurde an den gespeicherten Ausschnitten,
  /// nicht im Quelltext – im Quelltext sah die Zeile richtig aus.
  ///
  /// Der Wert wird deshalb nur noch dort gezeigt, wo das Gesicht daneben
  /// steht (siehe SerienvergleichScreen) und nicht mehr als Warnung ohne
  /// Bild: Eine Behauptung, die man nicht nachprüfen kann, gehört nicht in
  /// einen Ablauf, an dessen Ende gelöscht wird.
  RealColumn get eyeOpenScore => real().nullable()();

  /// Schärfe des Gesichtsausschnitts (Laplace-Varianz, siehe
  /// [gesichtsschaerfe]) – `null` heisst „noch nicht berechnet".
  ///
  /// **Warum am Gesicht und nicht am Foto.** [Assets.sharpnessScore] misst
  /// das ganze Bild. Ein Porträt mit unscharfem Gesicht vor scharfem Laub
  /// besteht diese Prüfung mühelos, und beim Sichten ist genau das die
  /// Aufnahme, die man aussortieren will.
  ///
  /// Gerechnet wird auf dem 160x160-Ausschnitt, der ohnehin entsteht – die
  /// Zahl kostet damit rund zwei Millisekunden je Gesicht und keinen
  /// zusätzlichen Dekodiervorgang.
  RealColumn get schaerfe => real().nullable()();

  /// Vom Nutzer beiseitegelegt: kein Gesicht (Plakat, Spiegelung, Statue)
  /// oder eine Person, die er nicht benennen will.
  ///
  /// Bewusst ein Merkmal statt eines Löschens. Löschen wäre endgültig und
  /// obendrein wirkungslos: Der nächste Gesichts-Scan fände dieselbe Stelle
  /// erneut und legte den Eintrag neu an. Ein beiseitegelegtes Gesicht
  /// verschwindet aus dem Raster und aus der automatischen Gruppierung,
  /// bleibt aber unter „Ignoriert" auffindbar und rückholbar.
  BoolColumn get isIgnored => boolean().withDefault(const Constant(false))();

  /// Wer hier vermutlich zu sehen ist – gerechnet, nicht bestaetigt.
  ///
  /// **Warum das in der Tabelle steht und nicht bei Bedarf gerechnet
  /// wird.** Die Rechnung ist ein Vergleich jedes Gesichts mit jedem
  /// Personenkern; an der echten Bibliothek sind das 14.065 mal 45
  /// Vergleiche ueber je 512 Zahlen. Das ist als Hintergrundlauf richtig
  /// aufgehoben und als Antwort auf „wie viel liegt an?" unbrauchbar.
  /// Mit der Spalte kostet die Zahl auf dem Gesundheitsbildschirm eine
  /// gewoehnliche Zaehlung.
  ///
  /// Vorschlag heisst Vorschlag: Zugeordnet wird erst, wenn jemand
  /// zugestimmt hat. Ein uebersehener Fehlvorschlag kostet eine falsche
  /// Zuordnung, und die faellt spaeter niemandem mehr auf.
  TextColumn get vorschlagPersonId => text().nullable()();

  /// Die Aehnlichkeit zum Kern dieser Person, zum Zeitpunkt der Rechnung.
  ///
  /// Wird beim Bestaetigen oder Ablehnen als Rueckmeldung festgehalten
  /// (siehe [Gesichtsrueckmeldungen]) – ohne den Wert liesse sich aus der
  /// Entscheidung keine Schwelle ableiten.
  RealColumn get vorschlagWert => real().nullable()();

  /// Wann zuletzt nach einem Vorschlag gesucht wurde – auch dann gesetzt,
  /// wenn nichts nahe genug lag.
  ///
  /// Ohne diese Marke waere „noch nicht geprueft" von „geprueft, nichts
  /// gefunden" nicht zu unterscheiden, und jeder Lauf faenge wieder bei
  /// allen 14.065 an.
  DateTimeColumn get vorschlagGeprueftAm => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

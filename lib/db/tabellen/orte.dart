part of '../database.dart';

// Tabellen: Reisen, Aktivitäten, Spuren und Orte.

/// Eine bestätigte Reise.
///
/// **Bestätigt** ist das entscheidende Wort. Erkannt werden Reisen aus
/// den Aufnahmen selbst (siehe services/reisen.dart); was hier steht, hat
/// ein Mensch angesehen und benannt. Ein Programm, das Reisen im
/// Hintergrund anlegt, füllt die Bibliothek mit Behauptungen – und eine
/// falsch benannte Reise fällt später niemandem mehr auf.
class Reisen extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Erste und letzte Aufnahme – abgeleitet, aber gespeichert: Die Liste
  /// soll nach Zeitraum sortieren können, ohne für jede Zeile ihre
  /// Aufnahmen nachzuschlagen.
  DateTimeColumn get von => dateTime()();
  DateTimeColumn get bis => dateTime()();

  TextColumn get notiz => text().nullable()();

  /// Was für eine Art Reise – als Name der Aufzählung [Reiseart].
  ///
  /// Einsatz, Dienstreise, Besuch: „Reise" trifft nicht jede, und in der
  /// Liste sähen sonst alle gleich aus.
  TextColumn get art => text().withDefault(Constant(reiseartVorgabe.kennung))();

  /// Das Titelbild. `null` heißt „nimm die erste Aufnahme" – und ist
  /// etwas anderes als ein gewähltes Bild, das später gelöscht wurde.
  TextColumn get titelbildAssetId => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Welche Aufnahme zu welcher Reise gehört.
///
/// Eine ausdrückliche Zuordnung und **nicht** „alles im Zeitraum": Wer
/// eine Aufnahme aus der Reise nimmt oder eine nachträglich importierte
/// hinzufügt, soll das behalten dürfen. Ein Zeitraum schluckte jedes
/// später eingelesene Bild stillschweigend mit.
class ReiseAufnahmen extends Table {
  TextColumn get reiseId => text()();
  TextColumn get assetId => text()();

  @override
  Set<Column> get primaryKey => {reiseId, assetId};
}

/// Was an einem Reisetag geschah – von Hand geschrieben.
///
/// **Warum es das braucht.** Die Reise war nach Tagen gegliedert, aber
/// ein Tagebuch besteht nicht aus Bildern allein. Es fehlte genau das,
/// was ein Tagebuch ausmacht: der Satz, den nur der Reisende schreiben
/// kann. Die Notiz an der Reise ([Reisen.notiz]) gab es schon, sie gilt
/// aber für die ganze Reise – und „am dritten Tag hat es geschüttet"
/// gehört an den dritten Tag.
///
/// **Der Tag als Datum ohne Uhrzeit** ist der Schlüssel, weil die
/// Kapitel genau so entstehen (siehe `reisetage`). Ein Eintrag ohne
/// Aufnahmen an diesem Tag bliebe unsichtbar – das ist gewollt: Das
/// Tagebuch folgt den Bildern, es führt keine eigene Zeitrechnung.
class Reisetagnotizen extends Table {
  TextColumn get reiseId => text()();

  /// Mitternacht des Tages, dem die Notiz gilt.
  DateTimeColumn get tag => dateTime()();

  /// Nicht `text`: Der Spaltenname wäre derselbe wie der Baustein
  /// `text()`, mit dem drift ihn beschreibt – der Getter riefe sich
  /// selbst auf, und die Erzeugung brach mit 3485 Fehlern ab, von denen
  /// keiner hier stand.
  TextColumn get notiz => text()();

  DateTimeColumn get geaendertAm => dateTime()();

  @override
  Set<Column> get primaryKey => {reiseId, tag};
}

/// Wo eine Reise oder Aktivität stattfand, in einer Zeile.
///
/// Alle drei Ortsangaben können fehlen: Eine Reise, deren Aufnahmen
/// keine Koordinate tragen, hat keinen Ort – und das ist etwas anderes
/// als „unbekannt". Die Übersicht lässt die Zeile dann weg, statt einen
/// Platzhalter hinzuschreiben.
///
/// [weitereOrte] zählt die Orte **neben** dem genannten. Ohne diese Zahl
/// sähe eine dreiwöchige Rundreise aus wie ein Wochenende an einem Ort:
/// Genannt wird der häufigste, und der ist bei einer Rundreise nur einer
/// von vielen.
typedef Ortsbezug = ({
  String? ort,
  String? region,
  String? land,
  int weitereOrte,
  int aufnahmen,
});

/// Ein abgelehnter Reisevorschlag.
///
/// Ohne dieses Gedächtnis käme derselbe Vorschlag bei jedem Start wieder
/// – und ein Vorschlag, den man dreimal wegwischen muss, ist eine
/// Belästigung. [schluessel] ist die Kennung der ersten Aufnahme des
/// Vorschlags (siehe `Reisevorschlag.schluessel`).
class VerworfeneReisen extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Eine bestätigte Aktivität – eine Wanderung, eine Radtour, ein
/// Ausflug.
///
/// **Sie steht für sich und *kann* zu einer Reise gehören.** Deshalb ist
/// [reiseId] nullable: Die Sonntagswanderung vor der Haustür braucht
/// keine Reise, und eine Tabelle, die eine verlangt, zwänge dazu, eine
/// zu erfinden.
///
/// Wie bei den Reisen gilt: **bestätigt.** Erkannt wird aus den
/// Aufnahmen (siehe services/aktivitaeten.dart); was hier steht, hat
/// jemand angesehen und benannt.
class Aktivitaeten extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Die Art, als Name der Aufzählung `Aktivitaetsart` – nicht als
  /// Index: Wer später eine Art dazwischenschiebt, verschöbe sonst alle
  /// gespeicherten Zeilen.
  TextColumn get art => text()();

  DateTimeColumn get von => dateTime()();
  DateTimeColumn get bis => dateTime()();

  TextColumn get notiz => text().nullable()();

  /// Die Reise, zu der sie gehört – oder `null`.
  TextColumn get reiseId => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Welche Aufnahme zu welcher Aktivität gehört – ausdrücklich, aus
/// demselben Grund wie bei [ReiseAufnahmen].
class AktivitaetAufnahmen extends Table {
  TextColumn get aktivitaetId => text()();
  TextColumn get assetId => text()();

  @override
  Set<Column> get primaryKey => {aktivitaetId, assetId};
}

/// Ein abgelehnter Aktivitätsvorschlag. [schluessel] ist die Kennung der
/// ersten Aufnahme des Vorschlags – wie bei [VerworfeneReisen].
class VerworfeneAktivitaeten extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Ein abgelehntes Buendel von Ortsvorschlaegen. [schluessel] ist die
/// kleinste Kennung der Gruppe – wie bei [VerworfeneReisen],
/// [VerworfeneAktivitaeten] und [VerworfeneSerien].
///
/// **Warum es die Tabelle braucht.** Der Vorschlag entsteht bei jedem
/// Aufruf neu aus den Daten; ohne Gedaechtnis stuende ein „nein" beim
/// naechsten Oeffnen wieder da. Und anders als bei Serien gibt es hier
/// keinen anderen Weg, ein Nein festzuhalten: Eine abgelehnte Aufnahme
/// bleibt genau das, was sie vorher war – unverortet.
class VerworfeneOrtsvorschlaege extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get verworfenAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Eine aufgezeichnete Spur – die GPX-Datei einer Wanderung oder
/// Radtour.
///
/// **Bis Fassung 55 wurde sie gelesen und weggeworfen.** Eine GPX-Datei
/// diente einmalig dazu, Fotos zu verorten, und war danach weg. Ohne sie
/// gibt es weder Linie noch Höhenprofil.
///
/// Die Kennzahlen stehen hier und werden **nicht** bei jeder Anzeige neu
/// gerechnet: Eine Spur mit zehntausend Punkten für eine Zeile in einer
/// Liste durchzurechnen, wäre derselbe Fehler wie bei den
/// Reise-Vorschaubildern.
class Spuren extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// Der Dateiname, aus dem sie kam – die einzige Herkunftsangabe, die
  /// eine GPX-Datei verlässlich hergibt.
  TextColumn get quelle => text()();

  /// Die Aktivität, zu der sie gehört – oder `null`.
  ///
  /// **Die Verbindung liegt hier und nicht an der Aktivität.** Eine
  /// Aktivität kann ohne Spur bestehen, eine Spur ohne Aktivität auch;
  /// wer die Spalte auf die ältere Tabelle legte, müsste sie dort
  /// nachträglich anbauen, damit sie meistens leer bleibt.
  TextColumn get aktivitaetId => text().nullable()();

  /// Die Reise, zu der sie gehört – oder `null`.
  ///
  /// **Eine zweite Spalte und keine gemeinsame.** Eine Spur gehört zu
  /// einer Aktivität *oder* zu einer Reise, und beides in einem Feld mit
  /// einer Artangabe daneben zu führen hiesse, bei jeder Abfrage zwei
  /// Bedingungen zu schreiben, wo eine reicht – und beim Vergessen der
  /// zweiten die Spuren der jeweils anderen Sorte mitzuzählen.
  TextColumn get reiseId => text().nullable()();

  /// Erster und letzter Zeitstempel – `null`, wenn die Datei keine
  /// führt (eine geplante Route etwa).
  DateTimeColumn get von => dateTime().nullable()();
  DateTimeColumn get bis => dateTime().nullable()();

  IntColumn get punktzahl => integer()();
  RealColumn get laengeKm => real()();

  /// Auf- und Abstieg in Metern – `null`, wenn kein Punkt eine Höhe
  /// trug. Null Meter Aufstieg und „keine Höhenangabe" sind zweierlei.
  RealColumn get aufstieg => real().nullable()();
  RealColumn get abstieg => real().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Die Punkte einer Spur, in der Reihenfolge der Datei.
class Spurpunkte extends Table {
  TextColumn get spurId => text()();

  /// Die laufende Nummer. Sie und nicht die Zeit ordnet die Punkte: Eine
  /// geplante Route hat gar keine Zeit, und eine Aufzeichnung mit zwei
  /// gleichen Zeitstempeln wäre sonst nicht mehr eindeutig.
  IntColumn get nummer => integer()();

  RealColumn get breite => real()();
  RealColumn get laenge => real()();
  RealColumn get hoehe => real().nullable()();
  DateTimeColumn get zeit => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {spurId, nummer};
}

/// Was beim Wandern zählt, aus OpenStreetMap – Gipfel, Hütten, Quellen.
///
/// **Warum das in der Bibliothek liegt und nicht nur im Arbeitsspeicher.**
/// Overpass wird ehrenamtlich betrieben und drosselt bei zu vielen
/// Anfragen. Eine Tour, die schon einmal angesehen wurde, soll niemanden
/// mehr fragen – auch nicht nach einem Neustart, und auch nicht ohne
/// Netz.
class Wanderpunkte extends Table {
  /// Die Kennung aus OpenStreetMap – damit derselbe Punkt aus zwei
  /// überlappenden Abfragen nicht zweimal im Bild steht.
  IntColumn get osmId => integer()();

  /// Die Art als Nummer aus `Wanderart`. Als Zahl und nicht als Name,
  /// wie überall hier: Ein Name aus einer älteren Fassung könnte einer
  /// sein, den es nicht mehr gibt.
  IntColumn get artNr => integer()();

  RealColumn get breite => real()();
  RealColumn get laenge => real()();
  TextColumn get name => text().nullable()();

  /// Die Höhe, wie sie in OpenStreetMap steht – **nicht** die aus dem
  /// Höhengitter. Eine eingetragene Gipfelhöhe ist vermessen; das Gitter
  /// kommt aus Kacheln und liegt bei einer Spitze regelmässig zu tief.
  RealColumn get hoehe => real().nullable()();

  @override
  Set<Column> get primaryKey => {osmId};
}

/// Welche Ausschnitte schon bei Overpass erfragt wurden.
///
/// **Getrennt von den Punkten, und das ist der Kern.** Ohne diese
/// Tabelle liesse sich „hier gibt es nichts" nicht von „hier wurde noch
/// nie gefragt" unterscheiden – ein Ausschnitt ohne einen einzigen
/// Gipfel würde bei jedem Öffnen neu erfragt.
class Wanderabfragen extends Table {
  /// Der Ausschnitt, gerundet auf drei Nachkommastellen – siehe
  /// `AppDatabase.wanderpunkteFuer`.
  TextColumn get kasten => text()();

  DateTimeColumn get gefragtAm => dateTime()();

  @override
  Set<Column> get primaryKey => {kasten};
}

/// Ein selbst gesetzter Haken auf der Weltkarte – ein Land, eine Region
/// oder ein Ort, den du besucht hast oder besuchen willst.
///
/// **Neben und nicht statt der Auswertung der Fotos.** Was die Kamera
/// belegt, wird weiterhin aus den Aufnahmen gezählt; diese Tabelle ist
/// für alles, wovon es kein Bild gibt: die Reise vor der ersten
/// Digitalkamera, der Zwischenstopp ohne Foto, das Ziel für nächstes
/// Jahr. Beides in einer Spalte zu führen hiesse, Beleg und Absicht zu
/// vermischen — und danach wäre nicht mehr entscheidbar, welche Zahl aus
/// welcher Quelle stammt.
///
/// [schluessel] ist je nach [art] verschieden: der ISO-Code („DE"), der
/// Regionscode („DE.02") oder Land, Region und Ort mit Strichen dazwischen
/// („DE|Bavaria|München") — dieselbe Bildung wie im Reisefortschritt, damit
/// gesetzte und gezählte Orte sich überhaupt treffen können.
class Ortsmarken extends Table {
  /// `land`, `region` oder `ort`.
  TextColumn get art => text()();

  TextColumn get schluessel => text()();

  /// Der Name zum Zeitpunkt des Setzens.
  ///
  /// Mitgeschrieben und nicht jedes Mal nachgeschlagen: Ohne den
  /// GeoNames-Datensatz gäbe es sonst eine Liste aus Codes.
  TextColumn get name => text()();

  RealColumn get breite => real().nullable()();
  RealColumn get laenge => real().nullable()();

  /// `besucht` oder `geplant`.
  TextColumn get status => text()();

  TextColumn get notiz => text().nullable()();

  DateTimeColumn get angelegtAm => dateTime()();

  /// Art und Schlüssel zusammen — ein Ort lässt sich nicht zweimal
  /// markieren, und das Aufheben einer Marke ist ein Löschen und kein
  /// Suchen nach der richtigen von mehreren Zeilen.
  @override
  Set<Column> get primaryKey => {art, schluessel};
}

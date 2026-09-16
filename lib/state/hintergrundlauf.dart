import 'dart:async';

import '../l10n/app_localizations.dart';

class ImportProgress {
  final int done;
  final int total;
  final String? currentFile;

  /// Gesetzt, sobald diese Fortschritts-Meldung eine tatsächlich neu
  /// importierte Datei betrifft (nicht bei Duplikaten/Fehlern) – für Aufrufer
  /// wie [ImportProgressSheet], die nach dem Import direkt in den
  /// Sichtungs-Modus (Culling) springen wollen, ohne die importierten Fotos
  /// erneut aus der DB abfragen zu müssen.
  final String? assetId;

  /// Ob genau diese Datei uebersprungen wurde, weil sie schon in der
  /// Bibliothek liegt.
  ///
  /// Sie wurde immer schon uebersprungen - nur sagte es niemand. Wer
  /// zweihundert Dateien hereinzieht und danach hundertachtzig Fotos
  /// vorfindet, sucht den Fehler bei sich.
  final bool duplikat;

  /// Ob diese Datei gar nicht hereinkam.
  final bool gescheitert;

  /// Wie viele Dinge wirklich getan wurden – nicht wie viele angesehen.
  ///
  /// **Warum es die Zahl gesondert braucht.** „N bearbeitet" ist die
  /// Zahl der angesehenen Dinge. Beim Ordnen der Ablage stand deshalb am
  /// Ende nichts, woraus man ablesen konnte, ob etwas verschoben wurde –
  /// aus dem Erstlauf-Bericht (A08): „Aufgabe lief ohne Fehlermeldung
  /// durch, genannt wurde nichts."
  ///
  /// `null` bei allen Läufen, bei denen angesehen und getan dasselbe
  /// ist; gesetzt wird sie am letzten `yield`.
  final int? getan;

  ImportProgress(
    this.done,
    this.total, {
    this.currentFile,
    this.assetId,
    this.duplikat = false,
    this.gescheitert = false,
    this.getan,
  });
}

/// Ein Nachholvorgang, der wirklich im Hintergrund läuft.
///
/// Bis hierher öffnete jede Aufgabe der Übersicht ein Fortschrittsfenster,
/// das den Bildschirm sperrte und sich nicht wegklicken liess – „im
/// Hintergrund" war daran nur der Name. Ein solcher Lauf hängt jetzt an
/// [LibraryState] statt am Bildschirm: Er überlebt das Wegnavigieren, und
/// mehrere Bildschirme können denselben Zustand anzeigen.
///
/// Bewusst veränderlich statt als unveränderliches Abbild je Ereignis: Ein
/// Lauf über 8000 Fotos meldet 8000 Fortschritte; jedes Mal ein neues Objekt
/// samt Karte anzulegen wäre reine Müllproduktion. Die Oberfläche liest die
/// Felder ohnehin erst im nächsten Aufbau.
class Hintergrundlauf {
  Hintergrundlauf({
    required this.schluessel,
    required this.titel,
    required this.leermeldung,
    required this.strom,
    this.bilanztext,
    this.rechenintensiv = false,
  });

  /// Woher die Arbeit kommt.
  ///
  /// Am Lauf und nicht beim Aufrufer, seit es die Schlange gibt: Zwischen
  /// Einreihen und Losgehen können Minuten liegen, und in dieser Zeit muss
  /// jemand die Anweisung halten. Ein Bildschirm, der inzwischen weg ist,
  /// kann es nicht.
  ///
  /// Eine Funktion und kein fertiger `Stream`: Ein Generator fängt erst
  /// beim Abonnieren an zu arbeiten, ein bereits erzeugter Strom hätte
  /// seine erste Datenbankabfrage schon beim Einreihen abgesetzt.
  final Stream<ImportProgress> Function() strom;

  /// Identifiziert die Aufgabe – dieselbe Kennung wie die Karte, die sie
  /// anzeigt. Verhindert zugleich, dass dieselbe Arbeit zweimal parallel
  /// startet.
  final String schluessel;

  /// Was gerade getan wird, in der Sprache der Oberfläche (z.B.
  /// „Bildbeschreibungen werden erzeugt").
  final String titel;

  /// Was statt „0 / 0" dasteht, wenn es nichts nachzuholen gab („Alle Fotos
  /// sind bereits durchsucht.").
  ///
  /// Am Lauf und nicht am Bildschirm: Der Lauf überlebt das Wegnavigieren,
  /// der Bildschirmzustand nicht – bei der Rückkehr wüsste sonst niemand
  /// mehr, welche der beiden Aktionen einer Karte gestartet wurde.
  final String leermeldung;

  /// Wie die Schlussbilanz heisst, wenn der Lauf eine [getan]-Zahl
  /// schickt.
  ///
  /// Eine Funktion und kein fertiger Satz: Die Zahlen stehen erst am
  /// Ende fest. Und sie kommt vom Bildschirm und nicht aus dem Zustand,
  /// weil nur dort die Sprache der Oberfläche bekannt ist – dasselbe
  /// Muster wie bei [leermeldung].
  final String Function(int getan, int gesamt)? bilanztext;

  /// Ob dieser Lauf zu den teuren Auswertungen gehört – entweder weil er
  /// ein KI-Modell in den Speicher holt oder weil die Hintergrundanalyse
  /// dieselbe Arbeit als eine ihrer Stufen erledigt. Nur solche Läufe
  /// warten aufeinander (siehe `LibraryState.maxGleichzeitig`).
  final bool rechenintensiv;

  int erledigt = 0;
  int gesamt = 0;
  String? datei;

  /// Gesetzt, sobald der Strom durch ist – gleich ob erfolgreich,
  /// abgebrochen oder mit Fehler. Der Eintrag bleibt danach stehen, damit
  /// das Ergebnis sichtbar wird; er verschwindet erst, wenn ihn jemand
  /// wegräumt (siehe `LibraryState.verwerfeLauf`).
  bool beendet = false;
  bool abgebrochen = false;
  Object? fehler;

  /// Wie viele Dinge der Lauf wirklich getan hat – siehe
  /// [ImportProgress.getan].
  int? getan;

  /// Das Abonnement des zugrunde liegenden `Stream<ImportProgress>`.
  ///
  /// Abbrechen heisst hier: das Abonnement kündigen. Ein `async*`-Generator
  /// hält dann bei seinem nächsten `yield` an und durchläuft seine
  /// `finally`-Blöcke – genau dort geben die Nachholvorgänge ihre geliehenen
  /// Modelle zurück. Ein Abbruchsschalter, den jede Schleife selbst abfragen
  /// müsste, wäre an jeder der 20 Stellen einzeln zu pflegen.
  StreamSubscription<ImportProgress>? abo;

  final Completer<void> _abschluss = Completer<void>();

  /// Wird erfüllt, sobald der Lauf endet – auf welchem Weg auch immer.
  ///
  /// Braucht es, weil ein gekündigtes Abonnement KEIN `onDone` mehr meldet:
  /// Ohne diesen gemeinsamen Endpunkt würde `LibraryState.starteAufgabe`
  /// nach einem Abbruch für immer auf ein Ereignis warten, das nicht mehr
  /// kommt.
  Future<void> get abschluss => _abschluss.future;

  /// Meldet das Ende. Mehrfaches Aufrufen ist erlaubt und folgenlos – Fehler
  /// und Abbruch können zeitlich zusammenfallen.
  void schliesseAb() {
    if (!_abschluss.isCompleted) _abschluss.complete();
  }

  /// Ob der Lauf schon einen Platz bekommen hat.
  ///
  /// Ein eingereihter Lauf steht in der Übersicht, hat aber noch kein
  /// Abonnement und verbraucht nichts. Siehe
  /// `LibraryState.reiheAufgabeEin`.
  bool gestartet = false;

  /// Eingereiht, aber noch nicht losgelaufen.
  bool get wartet => !gestartet && !beendet;

  /// Arbeitet gerade.
  bool get laeuft => gestartet && !beendet;

  /// Weder abgeschlossen noch abgebrochen – wartend **oder** laufend.
  ///
  /// Für alles, was nur wissen will, ob noch etwas offen ist: die
  /// Rückfrage beim Beenden zum Beispiel. Wer eingereihte Läufe hier
  /// ausliesse, verspräche „nichts läuft mehr" und wirft dann doch noch
  /// Arbeit weg.
  bool get offen => !beendet;

  /// Anteil 0..1, oder `null` solange die Gesamtzahl noch nicht feststeht –
  /// dann zeigt die Oberfläche einen unbestimmten Balken statt eines
  /// Balkens, der bei 0 klebt.
  double? get anteil {
    if (gesamt <= 0) return null;
    return (erledigt / gesamt).clamp(0.0, 1.0);
  }
}

/// Warum eine Aufgabe gerade nicht starten kann.
///
/// Eine Aufzählung statt eines fertigen Satzes: Dieser Zustand kennt keine
/// Oberflächensprache, und derselbe Grund wird an zwei Stellen angezeigt
/// (Aufgabenübersicht und Werkzeuge).
enum Startabweisung {
  /// Genau diese Arbeit läuft schon oder steht schon in der Schlange.
  ///
  /// **Der einzig verbliebene Grund.** Bis Fassung 2.2.3 gab es zwei
  /// weitere: eine andere schwere Aufgabe, und die laufende
  /// Hintergrundanalyse. Beide wiesen ab – wer zwei Dinge anstiess,
  /// bekam eine Meldung und musste sich das Ende des ersten merken.
  /// Seither wird stattdessen **eingereiht** (siehe
  /// `LibraryState.reiheAufgabeEin`); dieselbe Arbeit zweimal in die
  /// Schlange zu stellen bleibt sinnlos und wird weiter abgelehnt.
  laeuftBereits,
}

/// Der Grund als Satz in der Oberflächensprache.
///
/// Dasselbe Muster wie `analysestufeName`: Die Aufzählung bleibt sprachfrei,
/// die Zuordnung steht hier. Beide Einstiegspunkte (Aufgabenübersicht und
/// Werkzeuge) greifen darauf zu, damit derselbe Grund nicht zweimal
/// unterschiedlich formuliert wird.
String abweisungstext(AppTexte t, Startabweisung grund) => switch (grund) {
      Startabweisung.laeuftBereits => t.aufgLaeuftSchon,
    };

import 'dart:math' as math;
import 'dart:typed_data';

import 'clip_service.dart';

/// Ursprüngliches, festes Vokabular deutscher Alltagsbegriffe für
/// automatisches KI-Tagging – dient seit der Einführung eines editierbaren
/// Vokabulars (Einstellungen → KI-Tagging-Vokabular, Tabelle
/// `AiTagVocabulary`) nur noch als Startbestückung für die Migration auf
/// Schema v24 (siehe `AppDatabase._seedAiTagVocabulary`). Bewusst kein
/// zusätzliches, dediziertes Tagging-Modell: stattdessen wird das ohnehin
/// für die KI-Bildsuche installierte CLIP-Modell per Zero-Shot-
/// Klassifikation wiederverwendet (siehe [AiTaggingService]).
const List<String> defaultAiTagVocabulary = [
  'Baby', 'Kleinkind', 'Kind', 'Familie', 'Gruppe von Menschen', 'Porträt', 'Selfie',
  'Draußen', 'Drinnen', 'Natur', 'Wald', 'Berge', 'Strand', 'Meer', 'See', 'Fluss',
  'Garten', 'Spielplatz', 'Stadt', 'Straße', 'Zuhause',
  'Essen', 'Kuchen', 'Geburtstagstorte', 'Restaurant',
  'Tier', 'Hund', 'Katze', 'Vogel',
  'Auto', 'Fahrrad', 'Zug', 'Flugzeug', 'Boot',
  'Feier', 'Geburtstag', 'Weihnachten', 'Ostern', 'Urlaub', 'Hochzeit',
  'Schnee', 'Winter', 'Sommer', 'Herbst', 'Frühling', 'Sonnenuntergang', 'Nacht',
  'Blumen', 'Sport', 'Schwimmen', 'Wasser',
  'Bildschirmfoto', 'Dokument', 'Bauwerk', 'Kunst', 'Gruppenfoto',
];

/// Englische Entsprechung jedes Begriffs aus [defaultAiTagVocabulary] – für
/// das Angebot, das Vokabular beim Sprachwechsel mitzuziehen.
///
/// **Von Hand geprüft, nicht maschinell übersetzt.** Eine Datenmigration
/// darf nicht davon abhängen, ob ein 100-MB-Übersetzungsmodell installiert
/// ist, und sie muss vorhersagbar sein: „Aufnahme" oder „Bauwerk" kann eine
/// Maschine plausibel, aber unbrauchbar übersetzen.
///
/// Zwei Wörter sind bewusst gewählt und nicht die erste Wörterbuch-Antwort:
/// „Urlaub" wird zu *Vacation* statt *Holiday* und „Herbst" zu *Autumn*
/// statt *Fall* – die Begriffe werden am Ende gegen einen überwiegend
/// US-englisch trainierten Bildsuche-Encoder gerechnet, ausser bei *Fall*,
/// das dort mit „fallen" kollidiert.
const Map<String, String> aiTagVocabularyEnglisch = {
  'Baby': 'Baby',
  'Kleinkind': 'Toddler',
  'Kind': 'Child',
  'Familie': 'Family',
  'Gruppe von Menschen': 'Group of people',
  'Porträt': 'Portrait',
  'Selfie': 'Selfie',
  'Draußen': 'Outdoors',
  'Drinnen': 'Indoors',
  'Natur': 'Nature',
  'Wald': 'Forest',
  'Berge': 'Mountains',
  'Strand': 'Beach',
  'Meer': 'Sea',
  'See': 'Lake',
  'Fluss': 'River',
  'Garten': 'Garden',
  'Spielplatz': 'Playground',
  'Stadt': 'City',
  'Straße': 'Street',
  'Zuhause': 'Home',
  'Essen': 'Food',
  'Kuchen': 'Cake',
  'Geburtstagstorte': 'Birthday cake',
  'Restaurant': 'Restaurant',
  'Tier': 'Animal',
  'Hund': 'Dog',
  'Katze': 'Cat',
  'Vogel': 'Bird',
  'Auto': 'Car',
  'Fahrrad': 'Bicycle',
  'Zug': 'Train',
  'Flugzeug': 'Airplane',
  'Boot': 'Boat',
  'Feier': 'Celebration',
  'Geburtstag': 'Birthday',
  'Weihnachten': 'Christmas',
  'Ostern': 'Easter',
  'Urlaub': 'Vacation',
  'Hochzeit': 'Wedding',
  'Schnee': 'Snow',
  'Winter': 'Winter',
  'Sommer': 'Summer',
  'Herbst': 'Autumn',
  'Frühling': 'Spring',
  'Sonnenuntergang': 'Sunset',
  'Nacht': 'Night',
  'Blumen': 'Flowers',
  'Sport': 'Sports',
  'Schwimmen': 'Swimming',
  'Wasser': 'Water',
  'Bildschirmfoto': 'Screenshot',
  'Dokument': 'Document',
  'Bauwerk': 'Building',
  'Kunst': 'Art',
  'Gruppenfoto': 'Group photo',
};

/// Die Startbestückung in der gewünschten Sprache.
List<String> vokabularFuerSprache(String sprachcode) => sprachcode == 'en'
    ? [for (final t in defaultAiTagVocabulary) aiTagVocabularyEnglisch[t] ?? t]
    : defaultAiTagVocabulary;

/// Rückrichtung von [aiTagVocabularyEnglisch] – um zu erkennen, dass ein
/// Begriff bereits englisch ist (nach einem Sprachwechsel steht im
/// Vokabular „Beach" statt „Strand").
final Map<String, String> _englischeBegriffe = {
  for (final e in aiTagVocabularyEnglisch.entries) e.value: e.key,
};

/// Die Satzschablone, in der ein Begriff eingebettet wird.
///
/// Nicht Zierde, sondern der grösste einzelne Hebel dieser Datei: CLIP
/// wurde auf Bild-Text-Paaren aus dem Netz trainiert, und dort steht
/// neben einem Foto ein Satz, kein nacktes Substantiv. Ein Begriff im
/// Satz liegt deshalb näher an dem, was der Encoder kennt.
///
/// An 40 echten Fotos gemessen: allein diese Schablone hob die Güte von
/// F1 0,25 auf 0,41. Der Wortlaut ist der aus der CLIP-Veröffentlichung.
String schabloneFuer(String englisch) => 'a photo of ${englisch.toLowerCase()}.';

/// Der Text, der für [begriff] tatsächlich in den Text-Encoder geht.
///
/// Drei Stufen, in dieser Reihenfolge:
///
///  1. Die **von Hand geprüfte** Tabelle [aiTagVocabularyEnglisch]. Sie lag
///     bisher ungenutzt daneben – gebraucht wurde sie nur beim
///     Sprachwechsel, während für die Einbettung der deutsche Begriff roh
///     an einen englisch trainierten Encoder ging.
///  2. Ist der Begriff schon englisch (nach einem Sprachwechsel), bleibt er.
///  3. Sonst die Maschinenübersetzung, sofern eingeschaltet – für selbst
///     hinzugefügte Begriffe gibt es keine geprüfte Entsprechung.
///
/// Danach die Schablone. Ohne Übersetzung und ohne Schablone lag die Güte
/// bei F1 0,16 (zweite Stichprobe: 0,07), mit beidem und mittigem
/// Zuschnitt bei 0,48 (0,42).
Future<String> begriffFuerModell(
  String begriff,
  Future<String> Function(String)? insEnglische,
) async {
  final ausTabelle = aiTagVocabularyEnglisch[begriff];
  if (ausTabelle != null) return schabloneFuer(ausTabelle);
  if (_englischeBegriffe.containsKey(begriff)) return schabloneFuer(begriff);
  final uebersetzt = insEnglische == null ? begriff : await insEnglische(begriff);
  return schabloneFuer(uebersetzt);
}

/// Höchstens so viele Schlagwörter je Foto.
///
/// **Die Zahl ist der eigentliche Schutz.** Vorher gab es keine: Was über
/// der Schwelle lag, wurde vergeben. In der Bibliothek des Nutzers standen
/// dadurch **94.040 KI-Schlagwörter auf 7.400 Aufnahmen – 12,7 je Foto**,
/// mit Spitzen bei fünfzig. Fünf ist die Zahl, die ein Mensch beim
/// Betrachten eines Fotos auch nennen würde.
const kiTagsHoechstens = 5;

/// So viel der Gesamtwahrscheinlichkeit muss ein Begriff auf sich ziehen.
///
/// Bei einem Vokabular von 55 Begriffen kämen bei Gleichverteilung 1,8 %
/// auf jeden. Fünf Prozent heisst also: knapp das Dreifache dessen, was
/// blindes Raten ergäbe.
const kiTagMindestAnteil = 0.05;

/// Unter dieser Ähnlichkeit wird gar nichts vergeben.
///
/// Der Rang allein genügt nicht: Auch auf einem Foto, zu dem kein einziger
/// Begriff passt, gibt es einen besten. Ohne diesen Boden bekäme jedes
/// Foto seine fünf Schlagwörter, nur eben die am wenigsten falschen.
const kiTagUntergrenze = 0.20;

/// Die Temperatur der Softmax-Rechnung.
///
/// 100 ist der Wert aus der CLIP-Veröffentlichung selbst (dort als
/// gelernter `logit_scale`). Er ist kein Regler, sondern gehört zum
/// Modell: Kosinuswerte liegen zwischen etwa 0,15 und 0,35, und erst
/// dieser Faktor macht daraus Abstände, die eine Softmax trennen kann.
const _kiTagTemperatur = 100.0;

/// Welche Begriffe ein Foto bekommt – die Auswahlregel, getrennt vom
/// Modell und deshalb prüfbar.
///
/// **Warum nicht mehr eine feste Schwelle.** Bis hierher galt: Vergib
/// jeden Begriff mit einer Ähnlichkeit über 0,24. Das setzt voraus, dass
/// die Werte zwischen Begriffen vergleichbar sind – sie sind es nicht.
/// Manche Begriffe liegen für jedes Bild hoch, andere feuern nie. An der
/// echten Bibliothek abzulesen: „Bildschirmfoto" hing an 4.585 von 7.400
/// Aufnahmen, „Geburtstagstorte" an 4.050.
///
/// Richtig ist die Vorgehensweise aus der CLIP-Veröffentlichung selbst:
/// **rangieren statt schwellen.** Die Ähnlichkeiten gehen durch eine
/// Softmax über das GESAMTE Vokabular; damit zählt nicht mehr der
/// absolute Wert eines Begriffs, sondern wie sehr er die übrigen
/// aussticht. Ein Begriff, der überall mittelhoch liegt, sticht nirgends
/// aus.
///
/// Drei Bedingungen, alle drei müssen gelten:
///  1. höchstens [hoechstens] Begriffe,
///  2. Anteil an der Gesamtwahrscheinlichkeit mindestens [mindestAnteil],
///  3. Ähnlichkeit mindestens [untergrenze] – der Boden für Fotos, zu
///     denen schlicht nichts passt.
List<String> waehleTags(
  List<String> begriffe,
  List<double> naehe, {
  int hoechstens = kiTagsHoechstens,
  double mindestAnteil = kiTagMindestAnteil,
  double untergrenze = kiTagUntergrenze,
}) {
  assert(begriffe.length == naehe.length);
  if (begriffe.isEmpty) return const [];

  // Der grösste Wert wird abgezogen, bevor exponiert wird – sonst läuft
  // exp(100 * 0,35) über. Am Ergebnis der Softmax ändert das nichts.
  var groesste = naehe.first;
  for (final n in naehe) {
    if (n > groesste) groesste = n;
  }
  if (groesste < untergrenze) return const [];

  final gewichte = [
    for (final n in naehe) math.exp(_kiTagTemperatur * (n - groesste))
  ];
  final summe = gewichte.fold<double>(0, (a, b) => a + b);

  final rang = List<int>.generate(begriffe.length, (i) => i)
    ..sort((a, b) => naehe[b].compareTo(naehe[a]));

  final treffer = <String>[];
  for (final i in rang) {
    if (treffer.length >= hoechstens) break;
    if (naehe[i] < untergrenze) break;
    if (gewichte[i] / summe < mindestAnteil) break;
    treffer.add(begriffe[i]);
  }
  return treffer;
}

/// Ordnet einem Foto (über sein bereits berechnetes CLIP-Bild-Embedding)
/// automatisch Tags aus dem in den Einstellungen editierbaren Vokabular
/// (Tabelle `AiTagVocabulary`, siehe `AppDatabase.aiTagVocabularyTerms`) zu –
/// per Zero-Shot-Klassifikation: für jeden Begriff wird einmalig ein
/// CLIP-Text-Embedding berechnet (danach im Speicher gecacht) und dessen
/// Kosinus-Ähnlichkeit zum Bild-Embedding geprüft. Kein zusätzlicher
/// Modell-Download, keine zusätzliche Bild-Inferenz nötig – die
/// Bild-Embeddings liegen für jedes Foto ohnehin schon vor (siehe
/// LibraryState._postProcessNewAsset).
///
/// Die zugewiesenen Tags landen in denselben Tabellen wie manuell vergebene
/// Tags und lassen sich in der Info-Ansicht eines Fotos genauso entfernen
/// oder ergänzen – es gibt bewusst keine Unterscheidung "KI" vs. "manuell"
/// in der Datenbank, um das Datenmodell einfach zu halten.
class AiTaggingService {
  /// Pro-Begriff-Cache statt einer "alles oder nichts"-Vorberechnung: da
  /// sich das Vokabular jetzt zur Laufzeit ändern kann (Hinzufügen/Entfernen
  /// einzelner Begriffe in den Einstellungen), würde ein einmalig gefüllter
  /// Gesamt-Cache bei jeder Änderung ungültig. Entfernte Begriffe bleiben
  /// harmlos im Cache zurück (wenige Dutzend kurze Vektoren, vernachlässigbar).
  ///
  /// Bewusst unabhängig davon, WELCHE CLIP-Sitzung (siehe [ModellHalter] in
  /// LibraryState) den jeweiligen Begriff berechnet hat – die Vektoren
  /// bleiben auch nach einem Freigeben/Neuladen des Modells gültig.
  final Map<String, Float32List> _termEmbeddingCache = {};

  /// Liefert alle Begriffe aus [vocabulary], deren Kosinus-Ähnlichkeit zum
  /// gegebenen Bild-Embedding mindestens [threshold] beträgt. Der Standard
  /// orientiert sich an typischen CLIP-Zero-Shot-Ähnlichkeiten (deutlich
  /// niedriger als bei Gesichts-Embeddings üblich) – bewusst eher
  /// zurückhaltend gewählt, um zu viele falsche Tags zu vermeiden; ein
  /// zugewiesener Tag lässt sich in der Info-Ansicht jederzeit wieder
  /// entfernen.
  ///
  /// [clipText] wird als Parameter statt im Konstruktor übergeben, weil die
  /// zugrundeliegende ONNX-Sitzung jetzt bedarfsweise geladen/freigegeben
  /// wird (siehe LibraryState.clipTextHalter) statt für die ganze App-Laufzeit
  /// fest zu stehen. Gebraucht wird hier ausschliesslich der TEXT-Encoder:
  /// Das Bild-Embedding kommt fertig als [imageEmbedding] herein, nur die
  /// Vokabelbegriffe müssen noch eingebettet werden.
  /// [insEnglische] übersetzt einen Vokabelbegriff, bevor er eingebettet
  /// wird – das Vokabular ist deutsch, der Text-Encoder versteht aber nur
  /// Englisch. Fehlt die Funktion, bleibt es beim bisherigen Verhalten.
  ///
  /// Der Cache hängt weiterhin am **deutschen** Begriff: Er ist der
  /// Schlüssel, unter dem der Tag am Ende vergeben wird, und eine
  /// Übersetzung je Begriff genügt für die ganze Sitzung.
  Future<List<String>> suggestTags(
    ClipService clipText,
    Float32List imageEmbedding,
    List<String> vocabulary, {
    int hoechstens = kiTagsHoechstens,
    double mindestAnteil = kiTagMindestAnteil,
    double untergrenze = kiTagUntergrenze,
    Future<String> Function(String)? insEnglische,
  }) async {
    if (vocabulary.isEmpty) return const [];

    final naehe = <double>[];
    for (final term in vocabulary) {
      var embedding = _termEmbeddingCache[term];
      if (embedding == null) {
        final fuerModell = await begriffFuerModell(term, insEnglische);
        embedding = _termEmbeddingCache[term] = await clipText.embedText(fuerModell);
      }
      naehe.add(_cosine(imageEmbedding, embedding));
    }
    return waehleTags(vocabulary, naehe,
        hoechstens: hoechstens,
        mindestAnteil: mindestAnteil,
        untergrenze: untergrenze);
  }

  /// Verwirft die zwischengespeicherten Begriffs-Vektoren.
  ///
  /// Nötig, wenn die Übersetzungs-Einstellung umgelegt wird: Die Vektoren
  /// im Cache stammen dann von der jeweils anderen Sprache und würden die
  /// Umstellung bis zum nächsten Programmstart wirkungslos machen.
  void leereBegriffsCache() => _termEmbeddingCache.clear();

  double _cosine(Float32List a, Float32List b) {
    var dot = 0.0;
    final len = math.min(a.length, b.length);
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
    }
    return dot; // beide Vektoren sind bereits L2-normalisiert
  }
}

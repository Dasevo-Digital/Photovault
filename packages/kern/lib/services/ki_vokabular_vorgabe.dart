/// Die Startbestückung des KI-Schlagwortvokabulars – als reine Liste
/// ohne den CLIP-Dienst, damit die Datenbank sie beim Anlegen einsetzen
/// kann, ohne die ONNX Runtime zu kennen.
library;

/// Ursprüngliches, festes Vokabular deutscher Alltagsbegriffe für
/// automatisches KI-Tagging – dient seit der Einführung eines editierbaren
/// Vokabulars (Einstellungen → KI-Tagging-Vokabular, Tabelle
/// `AiTagVocabulary`) nur noch als Startbestückung für die Migration auf
/// Schema v24 (siehe `AppDatabase._seedAiTagVocabulary`). Bewusst kein
/// zusätzliches, dediziertes Tagging-Modell: stattdessen wird das ohnehin
/// für die KI-Bildsuche installierte CLIP-Modell per Zero-Shot-
/// Klassifikation wiederverwendet (siehe [AiTaggingService]).
const List<String> defaultAiTagVocabulary = [
  'Baby',
  'Kleinkind',
  'Kind',
  'Familie',
  'Gruppe von Menschen',
  'Porträt',
  'Selfie',
  'Draußen',
  'Drinnen',
  'Natur',
  'Wald',
  'Berge',
  'Strand',
  'Meer',
  'See',
  'Fluss',
  'Garten',
  'Spielplatz',
  'Stadt',
  'Straße',
  'Zuhause',
  'Essen',
  'Kuchen',
  'Geburtstagstorte',
  'Restaurant',
  'Tier',
  'Hund',
  'Katze',
  'Vogel',
  'Auto',
  'Fahrrad',
  'Zug',
  'Flugzeug',
  'Boot',
  'Feier',
  'Geburtstag',
  'Weihnachten',
  'Ostern',
  'Urlaub',
  'Hochzeit',
  'Schnee',
  'Winter',
  'Sommer',
  'Herbst',
  'Frühling',
  'Sonnenuntergang',
  'Nacht',
  'Blumen',
  'Sport',
  'Schwimmen',
  'Wasser',
  'Bildschirmfoto',
  'Dokument',
  'Bauwerk',
  'Kunst',
  'Gruppenfoto',
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

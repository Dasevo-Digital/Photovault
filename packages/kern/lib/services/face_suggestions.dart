/// Findet zu einer bereits benannten Person weitere Fotos: unbenannte
/// Gesichter, die ihren bekannten ähnlich genug sind.
///
/// Der Weg dorthin gab es bisher nur andersherum – man wählte Gesichter aus
/// und ordnete sie einer Person zu. Wer wissen wollte, ob Anna noch auf
/// weiteren Fotos ist, musste das Raster selbst durchsehen.
library;

import 'dart:typed_data';

import 'face_engine_service.dart';

/// Ein Vorschlag: dieses Gesicht könnte zu der Person gehören.
class Gesichtsvorschlag {
  final String faceId;
  final double aehnlichkeit;
  const Gesichtsvorschlag(this.faceId, this.aehnlichkeit);
}

/// Eingabe für [vorschlaegeFuerPerson] – ein einzelnes Argument, damit sich
/// der Aufruf an `compute()` übergeben lässt.
class VorschlagsEingabe {
  /// Die Embeddings der bereits zugeordneten Gesichter dieser Person.
  final List<Float32List> bekannt;

  /// Alle unbenannten Gesichter, die in Frage kommen.
  final Map<String, Float32List> kandidaten;

  /// Ab welcher Ähnlichkeit vorgeschlagen wird – die persönliche Schwelle
  /// der Person, sonst die allgemeine.
  final double schwelle;

  /// Wie viele Vorschläge höchstens. Mehr als eine Bildschirmfüllung will
  /// niemand am Stück durchsehen, und die schwächsten Treffer sind ohnehin
  /// die unzuverlässigsten.
  final int hoechstens;

  const VorschlagsEingabe({
    required this.bekannt,
    required this.kandidaten,
    required this.schwelle,
    this.hoechstens = 60,
  });
}

/// Wie viele bekannte Gesichter höchstens verglichen werden.
///
/// Ohne Deckel wächst die Arbeit mit dem Produkt aus beiden Mengen: Eine
/// Person mit 300 Fotos gegen 18.000 unbenannte Gesichter wären 5,4
/// Millionen Vektorvergleiche. Mit einer gleichmässig über den ganzen
/// Bestand gezogenen Stichprobe bleibt die Bandbreite an Aussehen erhalten
/// – anders als beim Abschneiden der ersten 40, die alle vom selben Tag
/// stammen könnten.
const int _hoechstensBekannte = 40;

/// Zieht [wieviele] Einträge gleichmässig verteilt aus [alle].
List<T> stichprobe<T>(List<T> alle, int wieviele) {
  if (alle.length <= wieviele) return alle;
  final schritt = alle.length / wieviele;
  return [for (var i = 0; i < wieviele; i++) alle[(i * schritt).floor()]];
}

/// Sucht die ähnlichsten unbenannten Gesichter, absteigend sortiert.
///
/// Verglichen wird gegen das **ähnlichste** bekannte Gesicht, nicht gegen
/// einen gemittelten Schwerpunkt. Der Grund ist derselbe wie bei „Ähnliche
/// mit auswählen": Ein Mensch sieht mit Brille, im Profil und zehn Jahre
/// jünger unterschiedlich aus. Der Mittelwert all dieser Bilder gleicht
/// keinem davon besonders, das nächstgelegene Einzelbild dagegen schon.
List<Gesichtsvorschlag> vorschlaegeFuerPerson(VorschlagsEingabe eingabe) {
  if (eingabe.bekannt.isEmpty || eingabe.kandidaten.isEmpty) return const [];
  final referenzen = stichprobe(eingabe.bekannt, _hoechstensBekannte);

  final treffer = <Gesichtsvorschlag>[];
  for (final eintrag in eingabe.kandidaten.entries) {
    var beste = -1.0;
    for (final referenz in referenzen) {
      final wert = FaceEngineService.cosineSimilarity(referenz, eintrag.value);
      if (wert > beste) beste = wert;
    }
    if (beste >= eingabe.schwelle) {
      treffer.add(Gesichtsvorschlag(eintrag.key, beste));
    }
  }

  treffer.sort((a, b) => b.aehnlichkeit.compareTo(a.aehnlichkeit));
  return treffer.length <= eingabe.hoechstens
      ? treffer
      : treffer.sublist(0, eingabe.hoechstens);
}

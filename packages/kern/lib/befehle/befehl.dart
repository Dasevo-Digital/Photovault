/// Änderungen durch den Nutzer als Befehle.
///
/// Ein Befehl beschreibt eine Änderung mit allem, was sie braucht –
/// Kennungen und Werte –, lässt sich als JSON speichern und verschicken und
/// wendet sich mit [Befehl.anwenden] auf eine Datenbank an. Dabei ruft er
/// genau die Abfrage, die die App vorher direkt aufgerufen hat; an der
/// Wirkung ändert sich nichts.
///
/// Ausgeführt wird er über [AppDatabase.fuehreAus]. Heute ist das ein
/// Umweg ohne eigene Wirkung. Mit einem Server (Issue #86) geht derselbe
/// Befehl zusätzlich an ihn, und der Server wendet ihn mit demselben Code
/// auf seine Kopie der Bibliothek an – statt dass zwei Datenbanken Zeile um
/// Zeile abgeglichen werden müssten.
///
/// Welche Schreibzugriffe Befehle sind und welche nicht (Ergebnisse von
/// Auswertungen, Einstellungen nur dieses Rechners), hält
/// `test/befehle_test.dart` fest.
///
/// **Kennungen (Issue #107).** Eine Zeile, die ein Befehl anlegt, bekommt
/// ihre Kennung aus dem Befehl – nicht aus der Datenbank, in der er
/// ausgeführt wird. Sonst bekäme dieselbe Zeile auf dem Gerät, das den
/// Befehl offline vorwegnimmt, eine andere Kennung als auf dem Server, und
/// ein späterer Befehl, der auf sie verweist, träfe dort eine andere Zeile.
/// Text-Kennungen bringt der Aufrufer mit (UUID); Schlagwörter leiten sie
/// aus dem Namen ab. Zahl-Kennungen zieht der Befehl beim Erzeugen
/// ([_neueZahlkennung]). Ausgenommen sind Zeilen, auf die kein Befehl
/// verweist (Rückmeldungen zur Gesichtserkennung) – die gleicht der
/// Abgleich selbst an –, und Zeilen, an denen Dateien hängen
/// (Entwicklungsverlauf, Masken); deren Weg entscheidet das Protokoll für
/// Dateien.
library;

import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../services/exif_camera.dart';
import '../services/search_filters.dart';
import '../services/stammbaum.dart';
import '../services/verwandtschaftsgrad.dart';

part 'alben.dart';
part 'aufnahmen.dart';
part 'ordnen.dart';
part 'personen.dart';
part 'reisen.dart';
part 'schlagwoerter.dart';
part 'stammbaum.dart';
part 'vorgaben.dart';
part 'zeilen.dart';

/// [T] ist, was die Änderung zurückgibt – meist nichts, manchmal eine
/// Zahl für die Rückmeldung („12 Schlagwörter zurückgenommen“).
sealed class Befehl<T> {
  const Befehl();

  /// Unter diesem Namen wird der Befehl gespeichert und verschickt.
  ///
  /// **Nie umbenennen:** Ein Server oder ein Gerät mit älterer Fassung muss
  /// ihn wiedererkennen. Ein geänderter Befehl bekommt einen neuen Namen.
  String get art;

  /// Die Werte als JSON-fähige Abbildung (Zeichenketten, Zahlen,
  /// Wahrheitswerte, Listen und Abbildungen davon).
  Map<String, Object?> get werte;

  /// Wendet den Befehl auf [db] an.
  Future<T> anwenden(AppDatabase db);

  Map<String, Object?> alsJson() => {'art': art, 'werte': werte};

  /// Liest einen Befehl aus [alsJson] zurück.
  static Befehl<Object?> ausJson(Map<String, Object?> json) {
    final art = json['art'];
    final lies = _arten[art];
    if (lies == null) throw FormatException('Unbekannter Befehl: $art');
    return lies((json['werte']! as Map).cast<String, Object?>());
  }

  /// Alle Arten, die [ausJson] kennt.
  static Iterable<String> get arten => _arten.keys;
}

const Map<String, Befehl<Object?> Function(Map<String, Object?>)> _arten = {
  'favoritSetzen': FavoritSetzen.aus,
  'bewertungSetzen': BewertungSetzen.aus,
  'farbmarkeSetzen': FarbmarkeSetzen.aus,
  'beschreibungSetzen': BeschreibungSetzen.aus,
  'markierungenSetzen': MarkierungenSetzen.aus,
  'schlagwortAnheften': SchlagwortAnheften.aus,
  'schlagwortAnheftenPerKennung': SchlagwortAnheftenPerKennung.aus,
  'schlagwortLoesen': SchlagwortLoesen.aus,
  'schlagwortAbnehmen': SchlagwortAbnehmen.aus,
  'kiSchlagwoerterZuruecknehmen': KiSchlagwoerterZuruecknehmen.aus,
  'kiBegriffHinzufuegen': KiBegriffHinzufuegen.aus,
  'kiBegriffEntfernen': KiBegriffEntfernen.aus,
  'vokabularUebersetzen': VokabularUebersetzen.aus,
  'albumAnlegen': AlbumAnlegen.aus,
  'albumFuellen': AlbumFuellen.aus,
  'ausAlbumNehmen': AusAlbumNehmen.aus,
  'albumTitelbildSetzen': AlbumTitelbildSetzen.aus,
  'sucheMerken': SucheMerken.aus,
  'sucheVergessen': SucheVergessen.aus,
  'personAnlegen': PersonAnlegen.aus,
  'gesichterZuordnen': GesichterZuordnen.aus,
  'personenZusammenfuehren': PersonenZusammenfuehren.aus,
  'personTitelbildSetzen': PersonTitelbildSetzen.aus,
  'gesichterBeiseitelegen': GesichterBeiseitelegen.aus,
  'zuordnungLoesen': ZuordnungLoesen.aus,
  'zuordnungZuruecknehmen': ZuordnungZuruecknehmen.aus,
  'gesichtsEntscheidungenMerken': GesichtsEntscheidungenMerken.aus,
  'gesichtsEntscheidungenVergessen': GesichtsEntscheidungenVergessen.aus,
  'vorschlaegeVerwerfen': VorschlaegeVerwerfen.aus,
  'gesichtssucheAusnehmen': GesichtssucheAusnehmen.aus,
  'beziehungHinzufuegen': BeziehungHinzufuegen.aus,
  'beziehungenHinzufuegen': BeziehungenHinzufuegen.aus,
  'beziehungEntfernen': BeziehungEntfernen.aus,
  'elternartAendern': ElternartAendern.aus,
  'lebensdatenSetzen': LebensdatenSetzen.aus,
  'geschlechtSetzen': GeschlechtSetzen.aus,
  'ereignisHinzufuegen': EreignisHinzufuegen.aus,
  'ereignisLoeschen': EreignisLoeschen.aus,
  'ereignisortSetzen': EreignisortSetzen.aus,
  'gedcomUebernehmen': GedcomUebernehmen.aus,
  'reiseAnlegen': ReiseAnlegen.aus,
  'reiseAendern': ReiseAendern.aus,
  'reiseLoeschen': ReiseLoeschen.aus,
  'reisenZusammenfuehren': ReisenZusammenfuehren.aus,
  'reisetagnotizSetzen': ReisetagnotizSetzen.aus,
  'reiseartSetzen': ReiseartSetzen.aus,
  'aufnahmenDerReiseSetzen': AufnahmenDerReiseSetzen.aus,
  'reisevorschlagVerwerfen': ReisevorschlagVerwerfen.aus,
  'aktivitaetAnlegen': AktivitaetAnlegen.aus,
  'aktivitaetAendern': AktivitaetAendern.aus,
  'aktivitaetLoeschen': AktivitaetLoeschen.aus,
  'aufnahmenDerAktivitaetSetzen': AufnahmenDerAktivitaetSetzen.aus,
  'aktivitaetsvorschlagVerwerfen': AktivitaetsvorschlagVerwerfen.aus,
  'spurLoeschen': SpurLoeschen.aus,
  'exportvorgabeSpeichern': ExportvorgabeSpeichern.aus,
  'exportvorgabeLoeschen': ExportvorgabeLoeschen.aus,
  'entwicklungsvorgabeSpeichern': EntwicklungsvorgabeSpeichern.aus,
  'kameravorgabeSpeichern': KameravorgabeSpeichern.aus,
  'kameravorgabeSchlagwoerterSetzen': KameravorgabeSchlagwoerterSetzen.aus,
  'kameravorgabeLoeschen': KameravorgabeLoeschen.aus,
  'regelSpeichern': RegelSpeichern.aus,
  'regelSchlagwoerterSetzen': RegelSchlagwoerterSetzen.aus,
  'regelLoeschen': RegelLoeschen.aus,
  'papierkorbFristSetzen': PapierkorbFristSetzen.aus,
  'gesichtsschwelleSetzen': GesichtsschwelleSetzen.aus,
  'auswertenNachImportSetzen': AuswertenNachImportSetzen.aus,
  'sucheUebersetzenSetzen': SucheUebersetzenSetzen.aus,
  'angabenSchuetzenSetzen': AngabenSchuetzenSetzen.aus,
  'ortSetzen': OrtSetzen.aus,
  'kameraangabenSetzen': KameraangabenSetzen.aus,
  'bildbeschreibungSetzen': BildbeschreibungSetzen.aus,
  'jahrSchaetzen': JahrSchaetzen.aus,
  'dateinameSetzen': DateinameSetzen.aus,
  'inDenPapierkorb': InDenPapierkorb.aus,
  'ausDemPapierkorb': AusDemPapierkorb.aus,
  'duplikateZusammenfuehren': DuplikateZusammenfuehren.aus,
  'duplikatgruppeIgnorieren': DuplikatgruppeIgnorieren.aus,
  'duplikatgruppeAufheben': DuplikatgruppeAufheben.aus,
  'duplikatAusnahmenLoeschen': DuplikatAusnahmenLoeschen.aus,
  'serieBilden': SerieBilden.aus,
  'serieAufloesen': SerieAufloesen.aus,
  'serienvorschlagVerwerfen': SerienvorschlagVerwerfen.aus,
  'dokumentvorschlaegeVerwerfen': DokumentvorschlaegeVerwerfen.aus,
  'ortsvorschlagVerwerfen': OrtsvorschlagVerwerfen.aus,
  'ortsvorschlagUebernehmen': OrtsvorschlagUebernehmen.aus,
  'orteAusSpurSetzen': OrteAusSpurSetzen.aus,
  'erinnerungMerken': ErinnerungMerken.aus,
  'erinnerungVergessen': ErinnerungVergessen.aus,
  'ortsmarkeSetzen': OrtsmarkeSetzen.aus,
  'ortsmarkeLoeschen': OrtsmarkeLoeschen.aus,
  'entwicklungZuruecksetzen': EntwicklungZuruecksetzen.aus,
  'maskeneinstellungAendern': MaskeneinstellungAendern.aus,
};

List<String> _kennungen(Object? werte) => (werte! as List).cast<String>();

DateTime? _zeitOderNichts(Object? wert) =>
    wert == null ? null : DateTime.parse(wert as String);

/// Eine Kennung für eine neue Zeile mit Zahl-Kennung: zufällig aus 2^44
/// Werten oberhalb von 2^40. Weit über allem, was die Datenbank selbst
/// hochzählt, und so gross, dass zwei Geräte nicht dieselbe ziehen.
int _neueZahlkennung() {
  final z = Random.secure();
  return (1 << 40) + ((z.nextInt(1 << 12) << 32) | z.nextInt(1 << 32));
}

/// [werte] mit einer `id`, falls sie noch keine haben (neue Zeile).
Map<String, Object?> _mitKennung(Map<String, Object?> werte) =>
    werte['id'] != null ? werte : {...werte, 'id': _neueZahlkennung()};

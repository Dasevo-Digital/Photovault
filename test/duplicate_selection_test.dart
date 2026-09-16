import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/duplicate_selection.dart';

/// Diese Regeln entscheiden, welche Fotos in den Papierkorb wandern –
/// entsprechend eng geprüft, besonders die Fälle, in denen NICHT gelöscht
/// werden darf.
AssetData foto(
  String id, {
  bool favorit = false,
  int bewertung = 0,
  double? schaerfe,
  int breite = 1000,
  int hoehe = 1000,
  int tagImJahr = 1,
}) {
  return AssetData(
    id: id,
    originalFileName: '$id.jpg',
    relativePath: 'originals/2026/01/$id.jpg',
    type: 'IMAGE',
    fileSizeBytes: 1000,
    checksum: id,
    fileCreatedAt: DateTime(2026, 1, tagImJahr),
    importedAt: DateTime(2026, 1, 1),
    isFavorite: favorit,
    isTrashed: false,
    facesScanned: false,
    aiCaptionScanned: false,
    aiCaptionEdited: false,
    aiTagsScanned: false,
    isStackCover: false,
    rating: bewertung,
    widthPx: breite,
    heightPx: hoehe,
    sharpnessScore: schaerfe,
    isLocked: false,
    faceScanExcluded: false,
    gpsGeprueft: false,
    datumGeschaetzt: false,
    datumGeprueft: false,
    ortGeerbt: false,
    videobilderGeprueft: false,
    ocrScanned: false,
    autoBackedUp: false,
    backedUp: false,
  );
}

void main() {
  group('bester der Gruppe', () {
    test('Favorit schlägt alles andere', () {
      final gewinner = besterDerGruppe([
        foto('scharf', schaerfe: 900, breite: 4000, hoehe: 3000),
        foto('favorit', favorit: true, schaerfe: 10, breite: 100, hoehe: 100),
      ]);
      expect(gewinner.id, 'favorit');
    });

    test('höhere Bewertung schlägt bessere Messwerte', () {
      final gewinner = besterDerGruppe([
        foto('scharf', schaerfe: 900),
        foto('bewertet', bewertung: 4, schaerfe: 20),
      ]);
      expect(gewinner.id, 'bewertet');
    });

    test('bei gleichem Rang entscheidet die Schärfe', () {
      final gewinner = besterDerGruppe([
        foto('unscharf', schaerfe: 50),
        foto('scharf', schaerfe: 800),
      ]);
      expect(gewinner.id, 'scharf');
    });

    test('fehlender Schärfe-Score gilt als schlechter, nicht als bester', () {
      final gewinner = besterDerGruppe([
        foto('ohne'),
        foto('mit', schaerfe: 30),
      ]);
      expect(gewinner.id, 'mit');
    });

    test('bei gleicher Schärfe entscheidet die Auflösung', () {
      final gewinner = besterDerGruppe([
        foto('klein', schaerfe: 100, breite: 800, hoehe: 600),
        foto('gross', schaerfe: 100, breite: 4000, hoehe: 3000),
      ]);
      expect(gewinner.id, 'gross');
    });

    test('ist bei gleichen Werten reproduzierbar (ältestes gewinnt)', () {
      final a = [foto('spaet', tagImJahr: 9), foto('frueh', tagImJahr: 2)];
      expect(besterDerGruppe(a).id, 'frueh');
      // Umgekehrte Eingabereihenfolge darf nichts ändern.
      expect(besterDerGruppe(a.reversed.toList()).id, 'frueh');
    });
  });

  group('zu löschende Fotos', () {
    test('behält genau eines und verwirft den Rest', () {
      final weg = zuLoeschendeDerGruppe([
        foto('a', schaerfe: 10),
        foto('b', schaerfe: 900),
        foto('c', schaerfe: 40),
      ]);
      expect(weg.map((e) => e.id), unorderedEquals(['a', 'c']));
    });

    test('rührt Gruppen mit mehreren ausgezeichneten Fotos NICHT an', () {
      // Zwei Favoriten: nicht entscheidbar, welcher überflüssig ist.
      final weg = zuLoeschendeDerGruppe([
        foto('fav1', favorit: true),
        foto('fav2', favorit: true),
        foto('normal'),
      ]);
      expect(weg, isEmpty);
    });

    test('Favorit plus Bewertung zählen beide als ausgezeichnet', () {
      final weg = zuLoeschendeDerGruppe([
        foto('fav', favorit: true),
        foto('bewertet', bewertung: 3),
      ]);
      expect(weg, isEmpty);
    });

    test('ein einzelnes ausgezeichnetes Foto blockiert nicht', () {
      final weg = zuLoeschendeDerGruppe([
        foto('fav', favorit: true),
        foto('normal1'),
        foto('normal2'),
      ]);
      expect(weg.map((e) => e.id), unorderedEquals(['normal1', 'normal2']));
    });

    test('Gruppe mit nur einem Foto ergibt nichts zu löschen', () {
      expect(zuLoeschendeDerGruppe([foto('allein')]), isEmpty);
    });
  });

  group('Vorschau über alle Gruppen', () {
    test('zählt übersprungene Gruppen getrennt', () {
      final v = berechneLoeschVorschau([
        [foto('a1', schaerfe: 5), foto('a2', schaerfe: 90)],
        [foto('f1', favorit: true), foto('f2', favorit: true)], // übersprungen
        [foto('c1', schaerfe: 10), foto('c2', schaerfe: 20), foto('c3', schaerfe: 30)],
      ]);

      expect(v.zuLoeschen.map((e) => e.id), unorderedEquals(['a1', 'c1', 'c2']));
      expect(v.uebersprungeneGruppen, 1);
    });

    test('leere Eingabe ergibt leere Vorschau', () {
      final v = berechneLoeschVorschau([]);
      expect(v.zuLoeschen, isEmpty);
      expect(v.uebersprungeneGruppen, 0);
    });
  });
}

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/ai_tagging_service.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/search_filters.dart';

/// Das Einhängen der Übersetzung – ohne die Modelle selbst, die in
/// `flutter test` nicht ladbar sind (Method-Channel).
///
/// Geprüft wird deshalb genau das, was ohne Modell schiefgehen kann: dass
/// abgeschaltet nichts passiert, dass das englische Original erhalten
/// bleibt, und dass die Suche beide Fassungen findet. Der Übersetzer
/// selbst wird durch eine Funktion ersetzt, die tut, was das Modell täte.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> lege(String id, {String? caption, String? deutsch}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'c_$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024, 1, 1),
          importedAt: DateTime(2024, 1, 1),
          aiCaption: Value(caption),
          aiCaptionDe: Value(deutsch),
        ));
    return id;
  }

  group('Einstellungen', () {
    test('beide Schalter stehen anfangs auf aus', () async {
      // Das Übersetzen ändert das Verhalten spürbar – die Zahl vergebener
      // Schlagwörter sinkt bei gleicher Schwelle deutlich. So etwas
      // gehört nicht stillschweigend eingeschaltet.
      expect(await db.uebersetzeBeschreibungen(), isFalse);
      expect(await db.uebersetzeSucheUndTags(), isFalse);
    });

    test('lassen sich unabhängig voneinander setzen', () async {
      await db.setzeUebersetzeBeschreibungen(true);
      expect(await db.uebersetzeBeschreibungen(), isTrue);
      expect(await db.uebersetzeSucheUndTags(), isFalse);

      await db.setzeUebersetzeSucheUndTags(true);
      await db.setzeUebersetzeBeschreibungen(false);
      expect(await db.uebersetzeBeschreibungen(), isFalse);
      expect(await db.uebersetzeSucheUndTags(), isTrue);
    });
  });

  group('Bildbeschreibung', () {
    test('ohne Übersetzung bleibt die deutsche Spalte leer', () async {
      final id = await lege('a');
      await db.setAiCaption(id, 'a dog on the beach');

      final asset = await db.assetById(id);
      expect(asset!.aiCaption, 'a dog on the beach');
      expect(asset.aiCaptionDe, isNull);
      expect(asset.aiCaptionScanned, isTrue);
    });

    test('mit Übersetzung bleibt das englische Original erhalten', () async {
      // Sonst hiesse ein späteres Abschalten der Übersetzung, das
      // Beschreibungsmodell über die ganze Bibliothek erneut laufen zu
      // lassen.
      final id = await lege('a');
      await db.setAiCaption(id, 'a dog on the beach', deutsch: 'ein Hund am Strand');

      final asset = await db.assetById(id);
      expect(asset!.aiCaption, 'a dog on the beach');
      expect(asset.aiCaptionDe, 'ein Hund am Strand');
    });
  });

  group('Suche über Bildunterschriften', () {
    Future<List<String>> suche(String text) async {
      final treffer = await db.searchAssets(
        SearchFilters(query: text, textMode: SearchTextMode.caption),
      );
      return treffer.map((a) => a.id).toList()..sort();
    }

    test('findet beide Fassungen', () async {
      // Wer die Übersetzung erst später einschaltet, hat Fotos mit nur
      // englischer und Fotos mit beiden Beschreibungen. Nur in einer zu
      // suchen liesse einen Teil der Bibliothek unauffindbar.
      await lege('nur_englisch', caption: 'a dog on the beach');
      await lege('beides', caption: 'a cat on the sofa', deutsch: 'eine Katze auf dem Sofa');

      expect(await suche('dog'), ['nur_englisch']);
      expect(await suche('Katze'), ['beides']);
      expect(await suche('cat'), ['beides']);
    });

    test('ein Foto ohne Beschreibung taucht nicht auf', () async {
      await lege('ohne');
      expect(await suche('Hund'), isEmpty);
    });
  });

  group('Schlagwort-Vokabular', () {
    // Geänderte Entscheidung (Version 1.4): Für Begriffe des
    // Standardvokabulars gilt jetzt die von Hand geprüfte Tabelle, nicht
    // die Maschine – und der Begriff geht in einer Satzschablone an den
    // Encoder. Beides gemessen: An 40 echten Fotos stieg die Güte von
    // F1 0,16 auf 0,48, an einer zweiten Stichprobe von 0,07 auf 0,42.
    // Die Maschine bleibt für selbst hinzugefügte Begriffe zuständig.

    test('der Cache hängt am deutschen Begriff, nicht an der Übersetzung', () async {
      // Der Tag wird unter dem deutschen Namen vergeben. Hinge der Cache
      // an der Übersetzung, käme bei abgeschalteter Übersetzung ein
      // anderer Schlüssel heraus und die Vektoren würden doppelt gerechnet.
      final dienst = AiTaggingService();
      final gefragt = <String>[];
      final bild = Float32List.fromList([1, 0, 0]);

      final tags = await dienst.suggestTags(
        _ClipAttrappe(gefragt),
        bild,
        ['Sonnenuntergang', 'Hund'],
        insEnglische: (t) async => 'sollte nicht gefragt werden',
      );

      expect(tags, ['Sonnenuntergang', 'Hund'],
          reason: 'vergeben wird der deutsche Begriff');
      expect(gefragt, ['a photo of sunset.', 'a photo of dog.'],
          reason: 'geprüfte Übersetzung, in der Schablone');

      // Zweiter Lauf: nichts wird erneut eingebettet.
      gefragt.clear();
      await dienst.suggestTags(
        _ClipAttrappe(gefragt), bild, ['Sonnenuntergang', 'Hund']);
      expect(gefragt, isEmpty);
    });

    test('ein selbst hinzugefügter Begriff geht weiterhin an die Maschine',
        () async {
      final dienst = AiTaggingService();
      final gefragt = <String>[];
      await dienst.suggestTags(
        _ClipAttrappe(gefragt),
        Float32List.fromList([1, 0, 0]),
        ['Ferienlager'],
        insEnglische: (t) async => 'summer camp',
      );
      expect(gefragt, ['a photo of summer camp.']);
    });

    test('ohne Übersetzerfunktion greift wenigstens die Schablone', () async {
      final dienst = AiTaggingService();
      final gefragt = <String>[];
      await dienst.suggestTags(
        _ClipAttrappe(gefragt),
        Float32List.fromList([1, 0, 0]),
        ['Ferienlager'],
      );
      expect(gefragt, ['a photo of ferienlager.']);
    });

    test('das Leeren des Caches erzwingt ein Neuberechnen', () async {
      // Beim Umlegen des Schalters unverzichtbar: Die Vektoren stammen
      // sonst noch aus der anderen Sprache und die Umstellung bliebe bis
      // zum nächsten Programmstart wirkungslos.
      final dienst = AiTaggingService();
      final gefragt = <String>[];
      final bild = Float32List.fromList([1, 0, 0]);

      await dienst.suggestTags(_ClipAttrappe(gefragt), bild, ['Ferienlager'],
          insEnglische: (t) async => 'summer camp');
      expect(gefragt, ['a photo of summer camp.']);

      dienst.leereBegriffsCache();
      gefragt.clear();
      await dienst.suggestTags(_ClipAttrappe(gefragt), bild, ['Ferienlager']);
      expect(gefragt, ['a photo of ferienlager.'],
          reason: 'jetzt ohne Übersetzung');
    });
  });
}

/// Ersetzt den CLIP-Text-Encoder: merkt sich, was eingebettet werden
/// sollte, und liefert immer denselben Vektor – die Ähnlichkeit ist hier
/// nicht der Prüfgegenstand.
///
/// Nur [embedText] wird gebraucht; `noSuchMethod` deckt den Rest ab, damit
/// dafür keine ONNX-Sitzung nötig ist (die in `flutter test` ohnehin nicht
/// ladbar wäre).
class _ClipAttrappe implements ClipService {
  _ClipAttrappe(this.gefragt);
  final List<String> gefragt;

  @override
  Future<Float32List> embedText(String text) async {
    gefragt.add(text);
    return Float32List.fromList([1, 0, 0]);
  }

  @override
  dynamic noSuchMethod(Invocation aufruf) => super.noSuchMethod(aufruf);
}

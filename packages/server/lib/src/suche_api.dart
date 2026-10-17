import 'dart:convert';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/bildsuche.dart';
import 'package:kern/services/search_filters.dart';
import 'package:shelf/shelf.dart';

import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'zeilen_json.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Die Bildsuche nach Inhalt für Geräte ohne eigenes Modell (das Telefon):
/// Der Server übersetzt den Suchtext ins Englische, wenn er das kann, und
/// bettet ihn mit dem Textteil von CLIP ein. Die Rangfolge rechnet das
/// Gerät selbst – mit den Einbettungen der Bilder, die es abgeglichen hat,
/// und denselben Filtern wie sonst.
///
/// Derselbe Weg wie in der Desktop-App (search_screen.dart), nur dass die
/// Modelle hier liegen.
class Suchapi {
  Suchapi(this.bibliotheken);

  final Bibliotheken bibliotheken;

  /// `{text}` → `{vektor, text}`; 404, wenn kein Textmodell da ist.
  Future<Response> text(Request anfrage) async {
    final k = jsonDecode(await anfrage.readAsString());
    final text = k is Map ? '${k['text'] ?? ''}'.trim() : '';
    if (text.isEmpty || text.length > 500) {
      return _json({'fehler': 'text fehlt'}, status: 400);
    }
    final b = (await bibliotheken.fuer(kontoVon(anfrage).id)).bibliothek;
    final halter = b.modelle.clipTextHalter;
    if (!halter.installiert) {
      return _json({'fehler': 'kein Modell für die Bildsuche'}, status: 404);
    }
    final englisch = await b.auswertungen.insEnglische(text);
    final vektor = await halter.mit((clip) => clip.embedText(englisch));
    return _json({'vektor': vektor, 'text': englisch});
  }

  /// `?text=…&art=inhalt|text` → `{aufnahmen}`: für den Browser, der
  /// keine Kopie der Bibliothek hat und die Rangfolge nicht selbst rechnen
  /// kann. `inhalt` sucht nach Bildinhalt (404 ohne Modell), `text` in
  /// Namen, Beschreibungen, Schlagwörtern, Orten und Personen – derselbe
  /// Weg wie auf dem Telefon.
  Future<Response> suche(Request anfrage) async {
    final q = anfrage.url.queryParameters;
    final text = (q['text'] ?? '').trim();
    if (text.isEmpty || text.length > 500) {
      return _json({'fehler': 'text fehlt'}, status: 400);
    }
    final b = (await bibliotheken.fuer(kontoVon(anfrage).id)).bibliothek;
    final db = b.db;
    final List<AssetData> funde;
    if (q['art'] == 'text') {
      final ids = await db.textfundstellen(text);
      funde = ids.isEmpty
          ? const []
          : await db.searchAssets(const SearchFilters(), restrictToIds: ids);
    } else {
      final halter = b.modelle.clipTextHalter;
      if (!halter.installiert) {
        return _json({'fehler': 'kein Modell für die Bildsuche'}, status: 404);
      }
      final englisch = await b.auswertungen.insEnglische(text);
      final vektor = await halter.mit((clip) => clip.embedText(englisch));
      if (vektor == null) {
        return _json({
          'fehler': 'Der Suchtext liess sich nicht einbetten',
        }, status: 500);
      }
      final erlaubt = (await db.searchAssetIds(const SearchFilters())).toSet();
      final rangfolge = rangfolgeDerBildsuche(
        vektor,
        suchkandidatenAus(
          await db.allEmbeddings(),
          await db.alleVideoeinbettungen(),
        ),
        erlaubt,
      );
      funde = await db.assetsByIds(rangfolge);
    }
    return _json({
      'aufnahmen': [for (final a in funde) zeileAlsJson(Rasterzeile.aus(a))],
    });
  }
}

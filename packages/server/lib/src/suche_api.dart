import 'dart:convert';
import 'dart:typed_data';

import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/suchlauf.dart';
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

  /// `?text=…&art=inhalt|text` und die Filter aus [Suchfilter]
  /// (`person`, `land`, `stadt`, `von`, `bis`, `art=bild|video`,
  /// `favoriten=1`, `kamera`) → `{aufnahmen}`: für den Browser, der keine
  /// Kopie der Bibliothek hat. `inhalt` sucht nach Bildinhalt (404 ohne
  /// Modell), `text` in Namen, Beschreibungen, Schlagwörtern, Orten und
  /// Personen – derselbe Weg wie auf dem Telefon (suchlauf.dart). Ohne
  /// Text, aber mit Filtern: alles, was sie erfüllt.
  Future<Response> suche(Request anfrage) async {
    final q = anfrage.url.queryParameters;
    final text = (q['text'] ?? '').trim();
    final filter = Suchfilter.ausParametern(anfrage.url.queryParametersAll);
    if ((text.isEmpty && filter.leer) || text.length > 500) {
      return _json({'fehler': 'text fehlt'}, status: 400);
    }
    final b = (await bibliotheken.fuer(kontoVon(anfrage).id)).bibliothek;
    final art = q['art'] == 'text' ? Suchart.text : Suchart.inhalt;
    List<double>? vektor;
    if (text.isNotEmpty && art == Suchart.inhalt) {
      final halter = b.modelle.clipTextHalter;
      if (!halter.installiert) {
        return _json({'fehler': 'kein Modell für die Bildsuche'}, status: 404);
      }
      final englisch = await b.auswertungen.insEnglische(text);
      vektor = await halter.mit((clip) => clip.embedText(englisch));
      if (vektor == null) {
        return _json({
          'fehler': 'Der Suchtext liess sich nicht einbetten',
        }, status: 500);
      }
    }
    final funde = await suchlauf(
      b.db,
      text: text,
      art: art,
      filter: filter,
      vektor: vektor == null ? null : Float32List.fromList(vektor),
    );
    return _json({
      'aufnahmen': [for (final a in funde) zeileAlsJson(Rasterzeile.aus(a))],
    });
  }

  /// Was sich in den Filtern wählen lässt (siehe [suchauswahl]), Länder
  /// in der Sprache der Oberfläche (`?sprache=de|en`).
  Future<Response> auswahl(Request anfrage) async {
    final b = (await bibliotheken.fuer(kontoVon(anfrage).id)).bibliothek;
    final sprache = anfrage.url.queryParameters['sprache'] == 'en'
        ? 'en'
        : 'de';
    final w = await suchauswahl(b.db);
    return _json({
      'personen': [
        for (final p in w.personen)
          {'id': p.id, 'name': p.name, 'bild': p.coverFaceCropPath},
      ],
      'orte': [
        for (final o in w.orte)
          {
            'land': o.land,
            'name': landAnzeige(o.land, sprache),
            'staedte': o.staedte,
          },
      ],
      'kameras': w.kameras,
    });
  }
}

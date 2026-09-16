import 'dart:convert';
import 'dart:io';

/// SentencePiece-Unigram-Tokenizer für die OPUS-MT/Marian-Übersetzungs-
/// modelle (siehe TranslationService, ModelCatalog).
///
/// Das dritte Tokenizer-Verfahren im Programm und das einzige, das nicht
/// auf BPE beruht: CLIP und ViT-GPT2 zerlegen nach Häufigkeit gelernter
/// Zeichenpaare, Unigram sucht stattdessen die **wahrscheinlichste**
/// Zerlegung eines Wortes über ein Wörterbuch mit Bewertungen. Das ist ein
/// Viterbi-Durchlauf, kein gieriges Zusammenfügen.
///
/// Alle Festlegungen hier sind gegen die echte `tokenizer.json` von
/// `Xenova/opus-mt-en-de` und gegen die Ausgabe der Bibliothek
/// `tokenizers` geprüft, nicht aus der Modellkarte übernommen. Zwei davon
/// hätte man nicht raten können:
///
///  * Ein unbekanntes Zeichen bekommt **id 2**, obwohl `<unk>` im
///    Vokabular an Position 1 steht. Das Modell führt seine eigene
///    `unk_id`, und die zeigt woanders hin.
///  * Der Normalisierer ist als `Precompiled` mit leerem Zeichenmap
///    eingetragen – also wirkungslos. (Die Referenzbibliothek stürzt an
///    genau diesem `null` sogar ab.) Es braucht deshalb keine
///    Unicode-Normalisierung.
class MarianTokenizer {
  MarianTokenizer._(this._pieces, this._scores, this._idByPiece, this.unkId)
      : _maxPieceLaenge = _pieces.fold(0, (m, p) => p.runes.length > m ? p.runes.length : m);

  final List<String> _pieces;
  final List<double> _scores;
  final Map<String, int> _idByPiece;
  final int _maxPieceLaenge;

  /// Kennung für ein Stück, das im Wörterbuch fehlt.
  final int unkId;

  /// Satzende. Marian hängt es an jede Eingabe an (TemplateProcessing in
  /// der `tokenizer.json`) und erzeugt es am Ende jeder Übersetzung.
  static const eosId = 0;

  /// Womit der Decoder startet – bei Marian das Füll-Token, nicht das
  /// Satzende (`decoder_start_token_id` in der `generation_config.json`).
  static const padId = 58100;

  /// Das Metaspace-Zeichen, mit dem SentencePiece Wortanfänge markiert.
  static const wortAnfang = '▁';

  int get vokabularGroesse => _pieces.length;

  static Future<MarianTokenizer> loadFromFile(String pfad) async =>
      fromJson(jsonDecode(await File(pfad).readAsString()) as Map<String, dynamic>);

  static MarianTokenizer fromJson(Map<String, dynamic> json) {
    final model = json['model'] as Map<String, dynamic>;
    final roh = model['vocab'] as List<dynamic>;

    final pieces = <String>[];
    final scores = <double>[];
    final idByPiece = <String, int>{};
    for (var i = 0; i < roh.length; i++) {
      final eintrag = roh[i] as List<dynamic>;
      final stueck = eintrag[0] as String;
      pieces.add(stueck);
      scores.add((eintrag[1] as num).toDouble());
      // Das erste Vorkommen gewinnt – doppelte Stücke gibt es nicht, aber
      // ein späteres dürfte ein früheres auch nicht überschreiben.
      idByPiece.putIfAbsent(stueck, () => i);
    }

    return MarianTokenizer._(
      pieces,
      scores,
      idByPiece,
      (model['unk_id'] as num?)?.toInt() ?? 1,
    );
  }

  /// Bewertung für ein unbekanntes Zeichen.
  ///
  /// Muss unter jeder echten Bewertung liegen, damit Unbekanntes nur dann
  /// gewählt wird, wenn es wirklich keine Zerlegung gibt. Die schlechtesten
  /// echten Stücke liegen bei -100.
  static const _unbekanntBewertung = -1e4;

  /// Zerlegt [text] in Modell-Kennungen, mit angehängtem Satzende.
  ///
  /// Der Weg entspricht der `tokenizer.json`: erst an Leerraum trennen
  /// (WhitespaceSplit), dann jedem Wort ein [wortAnfang] voranstellen
  /// (Metaspace mit `add_prefix_space`), dann je Wort die beste Zerlegung
  /// suchen. Mehrfache Leerzeichen fallen dabei weg – das ist nicht
  /// Nachlässigkeit, sondern genau das Verhalten der Vorlage.
  List<int> encode(String text) {
    final ids = <int>[];
    for (final wort in text.trim().split(RegExp(r'\s+'))) {
      if (wort.isEmpty) continue;
      ids.addAll(_zerlege('$wortAnfang$wort'));
    }
    ids.add(eosId);
    return ids;
  }

  /// Beste Zerlegung eines einzelnen Wortes (Viterbi).
  ///
  /// Gerechnet wird über Unicode-Zeichen, nicht über UTF-16-Einheiten:
  /// Ein Wort wie „café" oder ein Emoji würde sonst mitten in einem Zeichen
  /// getrennt.
  List<int> _zerlege(String wort) {
    final zeichen = wort.runes.toList(growable: false);
    final n = zeichen.length;
    if (n == 0) return const [];

    // beste[i] = Bewertung des besten Weges bis vor Position i.
    final beste = List<double>.filled(n + 1, double.negativeInfinity);
    final vorgaenger = List<int>.filled(n + 1, -1);
    final stueckId = List<int>.filled(n + 1, -1);
    beste[0] = 0;

    for (var i = 0; i < n; i++) {
      if (beste[i] == double.negativeInfinity) continue;
      final maxLaenge = (i + _maxPieceLaenge) > n ? n - i : _maxPieceLaenge;

      for (var l = 1; l <= maxLaenge; l++) {
        final kandidat = String.fromCharCodes(zeichen, i, i + l);
        final id = _idByPiece[kandidat];
        if (id == null) continue;
        final wert = beste[i] + _scores[id];
        if (wert > beste[i + l]) {
          beste[i + l] = wert;
          vorgaenger[i + l] = i;
          stueckId[i + l] = id;
        }
      }

      // Immer auch ein einzelnes unbekanntes Zeichen zulassen, sonst
      // liesse sich ein Wort mit einem fremden Zeichen gar nicht zerlegen
      // und die ganze Eingabe ginge verloren.
      final wert = beste[i] + _unbekanntBewertung;
      if (wert > beste[i + 1]) {
        beste[i + 1] = wert;
        vorgaenger[i + 1] = i;
        stueckId[i + 1] = unkId;
      }
    }

    final ids = <int>[];
    var pos = n;
    while (pos > 0) {
      ids.add(stueckId[pos]);
      pos = vorgaenger[pos];
    }
    return ids.reversed.toList();
  }

  /// Setzt Modell-Kennungen wieder zu Text zusammen.
  ///
  /// Sondertoken (Satzende, Füllzeichen) fallen weg; [wortAnfang] wird zum
  /// Leerzeichen, der führende entfällt.
  String decode(List<int> ids) {
    final puffer = StringBuffer();
    for (final id in ids) {
      if (id == eosId || id == padId) continue;
      if (id < 0 || id >= _pieces.length) continue;
      puffer.write(_pieces[id]);
    }
    return puffer.toString().replaceAll(wortAnfang, ' ').trim();
  }
}

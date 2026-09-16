import 'dart:convert';
import 'dart:io';

/// Byte-Level-BPE-Tokenizer für die Sprachhälfte von Florence-2 (BART-Art,
/// identisch zu GPT-2/RoBERTa).
///
/// Das vierte Zerlegeverfahren im Programm, und das erste, bei dem beide
/// Richtungen gebraucht werden: [ClipTokenizer] encodiert nur,
/// der frühere ViT-GPT2-Zerleger decodierte nur, [MarianTokenizer]
/// arbeitet nach
/// Unigram. Hier wird encodiert (die Aufgabenfrage an das Modell) **und**
/// decodiert (die erzeugte Beschreibung).
///
/// Der Unterschied zu CLIP ist klein, aber folgenreich: CLIP markiert das
/// Wortende mit `</w>`, GPT-2/BART das Wort**anfang**, indem das führende
/// Leerzeichen Teil des Tokens wird (als `Ġ`). Wer das verwechselt, bekommt
/// ein Vokabular voller Treffer und trotzdem Unsinn heraus.
class BartTokenizer {
  BartTokenizer._(this._vocab, this._idToToken, this._merges, this._byteEncoder,
      this._byteDecoder);

  final Map<String, int> _vocab;
  final Map<int, String> _idToToken;
  final Map<String, int> _merges;
  final Map<int, String> _byteEncoder;
  final Map<String, int> _byteDecoder;

  /// `<s>` – Satzanfang, zugleich das erzwungene erste Token der Ausgabe
  /// (`forced_bos_token_id` in der generation_config.json).
  static const bosId = 0;

  /// `<pad>`
  static const padId = 1;

  /// `</s>` – Satzende und zugleich Startzeichen des Decoders
  /// (`decoder_start_token_id`). Beides derselbe Wert, das ist kein
  /// Schreibfehler, sondern BART-Konvention.
  static const eosId = 2;

  /// Wie GPT-2 zerlegt, aber mit dem führenden Leerzeichen am Wort statt
  /// einer Endemarkierung.
  static final RegExp _splitPattern = RegExp(
    r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+",
    unicode: true,
  );

  final Map<String, List<String>> _bpeCache = {};

  static Future<BartTokenizer> loadFromFiles({
    required String vocabJsonPath,
    required String mergesTxtPath,
  }) async {
    final vocabRaw =
        jsonDecode(await File(vocabJsonPath).readAsString()) as Map<String, dynamic>;
    final vocab = vocabRaw.map((k, v) => MapEntry(k, v as int));
    final idToToken = <int, String>{
      for (final e in vocab.entries) e.value: e.key,
    };

    final merges = <String, int>{};
    var rang = 0;
    for (final zeile in await File(mergesTxtPath).readAsLines()) {
      final t = zeile.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      merges[t] = rang++;
    }

    final enc = _buildByteEncoder();
    return BartTokenizer._(
      vocab,
      idToToken,
      merges,
      enc,
      {for (final e in enc.entries) e.value: e.key},
    );
  }

  /// Die Zuordnung aller 256 Bytes auf druckbare Zeichen – dieselbe
  /// Tabelle wie bei CLIP und ViT-GPT2. Rein algorithmisch.
  static Map<int, String> _buildByteEncoder() {
    final bs = <int>[
      ...List.generate('~'.codeUnitAt(0) - '!'.codeUnitAt(0) + 1, (i) => '!'.codeUnitAt(0) + i),
      ...List.generate('¬'.codeUnitAt(0) - '¡'.codeUnitAt(0) + 1, (i) => '¡'.codeUnitAt(0) + i),
      ...List.generate('ÿ'.codeUnitAt(0) - '®'.codeUnitAt(0) + 1, (i) => '®'.codeUnitAt(0) + i),
    ];
    final bsSet = bs.toSet();
    final cs = List<int>.from(bs);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bsSet.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }
    return {for (var i = 0; i < bs.length; i++) bs[i]: String.fromCharCode(cs[i])};
  }

  List<String> _bpe(String token) {
    final zwischen = _bpeCache[token];
    if (zwischen != null) return zwischen;
    if (token.isEmpty) return const [];

    var wort = token.runes.map(String.fromCharCode).toList();
    while (wort.length > 1) {
      String? bestes;
      var besterRang = 1 << 30;
      for (var i = 0; i < wort.length - 1; i++) {
        final rang = _merges['${wort[i]} ${wort[i + 1]}'];
        if (rang != null && rang < besterRang) {
          besterRang = rang;
          bestes = '${wort[i]} ${wort[i + 1]}';
        }
      }
      if (bestes == null) break;
      final teile = bestes.split(' ');
      final neu = <String>[];
      var i = 0;
      while (i < wort.length) {
        if (i < wort.length - 1 && wort[i] == teile[0] && wort[i + 1] == teile[1]) {
          neu.add(teile[0] + teile[1]);
          i += 2;
        } else {
          neu.add(wort[i]);
          i++;
        }
      }
      wort = neu;
    }
    _bpeCache[token] = wort;
    return wort;
  }

  /// Zerlegt [text] in Kennungen, gerahmt von `<s>` und `</s>`.
  List<int> encode(String text) {
    final ids = <int>[bosId];
    for (final treffer in _splitPattern.allMatches(text)) {
      final wort = utf8
          .encode(treffer.group(0)!)
          .map((b) => _byteEncoder[b]!)
          .join();
      for (final stueck in _bpe(wort)) {
        final id = _vocab[stueck];
        if (id != null) ids.add(id);
      }
    }
    ids.add(eosId);
    return ids;
  }

  /// Setzt erzeugte Kennungen wieder zu Text zusammen. Sondertoken fallen
  /// weg – auch mittendrin, damit ein versehentlich erzeugtes `<s>` nicht
  /// den Rest zerstört.
  String decode(List<int> ids) {
    final puffer = StringBuffer();
    for (final id in ids) {
      if (id == bosId || id == eosId || id == padId) continue;
      final token = _idToToken[id];
      if (token != null) puffer.write(token);
    }
    final bytes = <int>[];
    for (final ch in puffer.toString().runes) {
      final byte = _byteDecoder[String.fromCharCode(ch)];
      if (byte != null) bytes.add(byte);
    }
    return utf8.decode(bytes, allowMalformed: true).trim();
  }
}

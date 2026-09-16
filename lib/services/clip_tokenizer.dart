import 'dart:convert';
import 'dart:io';

/// Byte-Level-BPE-Tokenizer, kompatibel zum Tokenizer von OpenAI-CLIP
/// (identischer Algorithmus wie bei GPT-2, aber mit `</w>`-Wortende-Marker
/// statt `Ġ`-Präfix). Erwartet die beiden Standard-Dateien, die zu jedem
/// CLIP-Modell auf HuggingFace mitgeliefert werden:
///
///   - vocab.json   (Token-String -> Integer-ID, ~49408 Einträge)
///   - merges.txt   (BPE-Merge-Regeln, eine Regel pro Zeile, sortiert nach Rang)
///
/// Diese Dateien werden bewusst NICHT mitgeliefert (zusammen mehrere hundert
/// KB bis 1 MB reiner Modell-Metadaten) – siehe README für die Bezugsquelle.
class ClipTokenizer {
  ClipTokenizer._(this._vocab, this._merges, this._byteEncoder);

  final Map<String, int> _vocab;
  final Map<String, int> _merges; // "tokenA tokenB" -> Rang (niedriger = zuerst mergen)
  final Map<int, String> _byteEncoder;

  static const contextLength = 77;

  static final RegExp _splitPattern = RegExp(
    r"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]+|[^\s\p{L}\p{N}]+",
    unicode: true,
    caseSensitive: false,
  );

  final Map<String, List<String>> _bpeCache = {};

  static Future<ClipTokenizer> loadFromFiles({
    required String vocabJsonPath,
    required String mergesTxtPath,
  }) async {
    final vocabRaw = jsonDecode(await File(vocabJsonPath).readAsString()) as Map<String, dynamic>;
    final vocab = vocabRaw.map((k, v) => MapEntry(k, v as int));

    final mergesLines = await File(mergesTxtPath).readAsLines();
    final merges = <String, int>{};
    var rank = 0;
    for (final line in mergesLines) {
      if (line.isEmpty || line.startsWith('#')) continue;
      merges[line.trim()] = rank++;
    }

    final byteEncoder = _buildByteEncoder();

    return ClipTokenizer._(vocab, merges, byteEncoder);
  }

  /// Baut die Byte<->Unicode-Zuordnung, die GPT-2/CLIP verwenden, damit jedes
  /// der 256 möglichen Bytes als druckbares Unicode-Zeichen dargestellt
  /// werden kann (notwendig, damit BPE auf beliebigen UTF-8-Text anwendbar
  /// ist). Rein algorithmisch, benötigt keine externen Daten.
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

  List<String> _byteEncodeWord(String word) {
    final utf8Bytes = utf8.encode(word);
    return utf8Bytes.map((b) => _byteEncoder[b]!).toList();
  }

  List<String> _bpe(String token) {
    final cached = _bpeCache[token];
    if (cached != null) return cached;

    if (token.isEmpty) return [];
    var word = token.characters().toList();
    word[word.length - 1] = '${word.last}</w>';

    Set<String> pairs(List<String> w) {
      final result = <String>{};
      for (var i = 0; i < w.length - 1; i++) {
        result.add('${w[i]} ${w[i + 1]}');
      }
      return result;
    }

    var currentPairs = pairs(word);
    while (currentPairs.isNotEmpty) {
      String? best;
      var bestRank = 1 << 30;
      for (final pair in currentPairs) {
        final rank = _merges[pair];
        if (rank != null && rank < bestRank) {
          bestRank = rank;
          best = pair;
        }
      }
      if (best == null) break;
      final parts = best.split(' ');
      final first = parts[0];
      final second = parts[1];
      final newWord = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 && word[i] == first && word[i + 1] == second) {
          newWord.add('$first$second');
          i += 2;
        } else {
          newWord.add(word[i]);
          i += 1;
        }
      }
      word = newWord;
      if (word.length == 1) break;
      currentPairs = pairs(word);
    }

    _bpeCache[token] = word;
    return word;
  }

  /// Wandelt einen Suchtext in eine feste 77-Token-Sequenz um (CLIPs
  /// Standard-Kontextlänge), inkl. Start-/End-Marker und Padding mit 0.
  List<int> encode(String text) {
    final startId = _vocab['<|startoftext|>']!;
    final endId = _vocab['<|endoftext|>']!;

    final ids = <int>[startId];
    for (final match in _splitPattern.allMatches(text.toLowerCase())) {
      final word = match.group(0)!;
      final byteEncoded = _byteEncodeWord(word).join();
      for (final piece in _bpe(byteEncoded)) {
        final id = _vocab[piece];
        if (id != null) ids.add(id);
      }
    }
    ids.add(endId);

    if (ids.length > contextLength) {
      return [...ids.sublist(0, contextLength - 1), endId];
    }
    return [...ids, ...List.filled(contextLength - ids.length, 0)];
  }
}

extension _Characters on String {
  /// Zerlegt einen bereits Byte-encodierten String in seine einzelnen
  /// (Unicode-)Zeichen, ohne Surrogate-Paare zu zerreißen.
  List<String> characters() => runes.map((r) => String.fromCharCode(r)).toList();
}

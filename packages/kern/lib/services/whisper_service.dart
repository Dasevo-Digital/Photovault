import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnxruntime_api/onnxruntime_api.dart';

import 'package:kern/services/modellthreads.dart';
import 'package:kern/services/whisper_mel.dart';

/// Was die Spracherkennung aus einem Video gehört hat.
typedef Transkript = ({String text, String? sprache});

/// Die Sprachen von Whisper in der Reihenfolge ihrer Token ab
/// [WhisperService.ersteSprache] – genau so in der `generation_config.json`
/// des Exports (`lang_to_id`, ohne Lücken).
const whisperSprachen = [
  'en', 'zh', 'de', 'es', 'ru', 'ko', 'fr', 'ja', 'pt', 'tr', 'pl', 'ca', //
  'nl', 'ar', 'sv', 'it', 'id', 'hi', 'fi', 'vi', 'he', 'uk', 'el', 'ms', //
  'cs', 'ro', 'da', 'hu', 'ta', 'no', 'th', 'ur', 'hr', 'bg', 'lt', 'la', //
  'mi', 'ml', 'cy', 'sk', 'te', 'fa', 'lv', 'bn', 'sr', 'az', 'sl', 'kn', //
  'et', 'mk', 'br', 'eu', 'is', 'hy', 'ne', 'mn', 'bs', 'kk', 'sq', 'sw', //
  'gl', 'mr', 'pa', 'si', 'km', 'sn', 'yo', 'so', 'af', 'oc', 'ka', 'be', //
  'tg', 'sd', 'gu', 'am', 'yi', 'lo', 'uz', 'fo', 'ht', 'ps', 'tk', 'nn', //
  'mt', 'sa', 'lb', 'my', 'bo', 'tl', 'mg', 'as', 'tt', 'haw', 'ln', 'ha', //
  'ba', 'jw', 'su',
];

/// Token, die das Original nie ausgibt (`suppress_tokens` der
/// `generation_config.json`): einzelne Satzzeichen und Symbole, die in
/// Untertiteln als Geräuschbeschreibung stehen, und die Steuerzeichen.
const _unterdrueckt = <int>{
  1, 2, 7, 8, 9, 10, 14, 25, 26, 27, 28, 29, 31, 58, 59, 60, 61, 62, 63, //
  90, 91, 92, 93, 359, 503, 522, 542, 873, 893, 902, 918, 922, 931, 1350, //
  1853, 1982, 2460, 2627, 3246, 3253, 3268, 3536, 3846, 3961, 4183, 4667, //
  6585, 6647, 7273, 9061, 9383, 10428, 10929, 11938, 12033, 12331, 12562, //
  13793, 14157, 14635, 15265, 15618, 16553, 16604, 18362, 18956, 20075, //
  21675, 22520, 26130, 26161, 26435, 28279, 29464, 31650, 32302, 32470, //
  36865, 42863, 47425, 49870, 50254, 50258, 50358, 50359, 50360, 50361, //
  50362,
};

/// Die Bytes hinter den Zeichen des Vokabulars (GPT-2, byte-level BPE).
///
/// Jedes Byte steht im Vokabular als druckbares Zeichen: die druckbaren
/// ASCII- und Latin-1-Zeichen als sie selbst, alle übrigen ab U+0100.
Map<int, int> whisperBytesAusZeichen() {
  final bytes = <int>[
    for (var b = 0x21; b <= 0x7E; b++) b,
    for (var b = 0xA1; b <= 0xAC; b++) b,
    for (var b = 0xAE; b <= 0xFF; b++) b,
  ];
  final zeichen = [...bytes];
  var n = 0;
  for (var b = 0; b < 256; b++) {
    if (!bytes.contains(b)) {
      bytes.add(b);
      zeichen.add(256 + n);
      n++;
    }
  }
  return {for (var i = 0; i < bytes.length; i++) zeichen[i]: bytes[i]};
}

/// Das Vokabular, nur in einer Richtung: von Token zu Text. Whisper
/// bekommt keinen Text, es gibt nur welchen aus – das Zerlegen in Token
/// braucht es nicht.
class WhisperVokabular {
  WhisperVokabular(Map<String, int> vokabular)
    : _token = {for (final e in vokabular.entries) e.value: e.key};

  final Map<int, String> _token;
  static final _bytes = whisperBytesAusZeichen();

  static Future<WhisperVokabular> lade(String pfad) async => WhisperVokabular(
    (jsonDecode(await File(pfad).readAsString()) as Map<String, dynamic>)
        .cast<String, int>(),
  );

  /// Der Text zu [ids]. Steuer- und Zeitmarken-Token fallen weg.
  String text(Iterable<int> ids) {
    final bytes = <int>[];
    for (final id in ids) {
      if (id >= WhisperService.textEnde) continue;
      for (final z in (_token[id] ?? '').runes) {
        final b = _bytes[z];
        if (b != null) bytes.add(b);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Wie stark sich ein Text komprimieren lässt – das Mass des Originals
/// für Wiederholungen. Über 2,4 hängt der Decoder in einer Schleife fest
/// („ლლლლლ…" auf reinem Rauschen) und das Stück wird verworfen.
double whisperKompression(String text) {
  final roh = utf8.encode(text);
  if (roh.isEmpty) return 0;
  return roh.length / ZLibCodec(level: 6).encode(roh).length;
}

/// Ob ein Stück verworfen wird: Das Modell hält es für Stille und ist sich
/// seiner Wörter nicht sicher, oder es wiederholt sich. Die Schwellen sind
/// die des Originals (`no_speech_threshold` 0,6, `logprob_threshold` -1,
/// `compression_ratio_threshold` 2,4).
bool whisperVerwerfen({
  required double keineSprache,
  required double mittlereLogWkt,
  required double kompression,
}) => (keineSprache > 0.6 && mittlereLogWkt < -1.0) || kompression > 2.4;

/// Spracherkennung mit **Whisper small** (OpenAI, Apache-2.0), als ONNX-Export
/// der onnx-community, 8-Bit-quantisiert.
///
/// Gewählt nach einer Messung mit gesprochenen Sätzen: base verhörte sich
/// im Deutschen bei Namen und Satzanfängen („Oma Gartot", „Erachtung"),
/// small traf sie. Englisch konnten beide.
///
/// Gierig decodiert, ohne Zeitmarken, in Stücken von 30 Sekunden – für die
/// Suche genügt der Wortlaut. Die Sprache bestimmt das Modell am ersten
/// Stück, das Sprache enthält, und behält sie für das ganze Video.
class WhisperService {
  WhisperService._(this._encoder, this._decoder, this._vokabular);

  final OrtSession _encoder;
  final OrtSession _decoder;
  final WhisperVokabular _vokabular;
  final _filter = whisperMelFilter();

  static const _lagen = 12;
  static const _koepfe = 12;
  static const _kopfBreite = 64;
  static const _encoderLaenge = 1500;

  static const textEnde = 50257;
  static const anfang = 50258;
  static const ersteSprache = 50259;
  static const transkribieren = 50359;
  static const keineSprache = 50362;
  static const ohneZeitmarken = 50363;

  /// Höchstens so viele Token je Stück – die Hälfte dessen, was der
  /// Decoder fasst, wie im Original.
  static const _hoechstensToken = 224;

  /// Unter diesem Pegel (Effektivwert, volle Aussteuerung = 1) ist ein
  /// Stück still und wird gar nicht erst gerechnet – rund -60 dB.
  static const stillePegel = 0.001;

  static const dateien = [
    'whisper_encoder.onnx',
    'whisper_decoder.onnx',
    'whisper_vocab.json',
  ];

  static bool isAvailable(String modelsDir) =>
      dateien.every((n) => File('$modelsDir/$n').existsSync());

  static Future<WhisperService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    return WhisperService._(
      await ort.createSession(
        '$modelsDir/whisper_encoder.onnx',
        options: modelloptionen(),
      ),
      await ort.createSession(
        '$modelsDir/whisper_decoder.onnx',
        options: modelloptionen(),
      ),
      await WhisperVokabular.lade('$modelsDir/whisper_vocab.json'),
    );
  }

  /// Transkribiert 16-kHz-Mono-PCM ([pcm], 16 Bit). `null`, wenn nichts
  /// darin als Sprache durchgeht.
  ///
  /// [abbruch] wird zwischen den Stücken gefragt: Ein langes Video soll
  /// das Beenden nicht minutenlang aufhalten.
  Future<Transkript?> transkribiere(
    Int16List pcm, {
    bool Function()? abbruch,
  }) async {
    int? sprache;
    final teile = <String>[];
    for (var von = 0; von < pcm.length; von += whisperStueck) {
      if (abbruch?.call() ?? false) break;
      final bis = math.min(von + whisperStueck, pcm.length);
      final stueck = Float32List(whisperStueck);
      var quadrate = 0.0;
      for (var i = von; i < bis; i++) {
        final w = pcm[i] / 32768.0;
        stueck[i - von] = w;
        quadrate += w * w;
      }
      if (math.sqrt(quadrate / math.max(1, bis - von)) < stillePegel) {
        continue;
      }
      final ergebnis = await _stueck(stueck, sprache);
      if (ergebnis == null) continue;
      sprache ??= ergebnis.sprache;
      if (ergebnis.text.isNotEmpty) teile.add(ergebnis.text);
    }
    if (teile.isEmpty) return null;
    return (
      text: teile.join(' '),
      sprache: sprache == null ? null : whisperSprachen[sprache - ersteSprache],
    );
  }

  /// Ein Stück von 30 Sekunden. `null`, wenn es verworfen wird.
  Future<({String text, int sprache})?> _stueck(
    Float32List audio,
    int? sprache,
  ) async {
    final offen = <OrtValue>{};
    Future<void> gib(OrtValue v) async {
      await v.dispose();
      offen.remove(v);
    }

    // Freigeben, ohne auf die Antwort zu warten. Das Plugin arbeitet alle
    // Aufrufe nacheinander auf einem Faden ab; ein späterer Aufruf sieht
    // die Freigabe also schon erledigt. Je Decoderschritt sind es rund
    // fünfzig – einzeln abgewartet kostete das unter Linux 150 ms je Wort.
    void lass(OrtValue v) {
      offen.remove(v);
      unawaited(v.dispose().catchError((Object _) {}));
    }

    try {
      final mel = await OrtValue.fromList(
        whisperLogMel(audio, filter: _filter),
        [1, whisperMelBaender, whisperRahmen],
      );
      offen.add(mel);
      final encAus = await _encoder.run({'input_features': mel});
      offen.addAll(encAus.values);
      await gib(mel);
      final zustand = encAus['last_hidden_state']!;

      // Leere Selbst-Aufmerksamkeit, Kreuz-Aufmerksamkeit in voller
      // Encoderlänge – dieselbe Eigenheit des zusammengeführten Decoders
      // wie bei Florence-2 (siehe florence_captioning_service.dart).
      var past = <String, OrtValue>{};
      for (var i = 0; i < _lagen; i++) {
        for (final kv in ['key', 'value']) {
          final d = await OrtValue.fromList(Float32List(0), [
            1,
            _koepfe,
            0,
            _kopfBreite,
          ]);
          final e = await OrtValue.fromList(
            Float32List(_koepfe * _encoderLaenge * _kopfBreite),
            [1, _koepfe, _encoderLaenge, _kopfBreite],
          );
          offen
            ..add(d)
            ..add(e);
          past['past_key_values.$i.decoder.$kv'] = d;
          past['past_key_values.$i.encoder.$kv'] = e;
        }
      }

      var mitCache = false;
      Future<List<double>> schritt(List<int> eingang) async {
        final ids = await OrtValue.fromList(Int64List.fromList(eingang), [
          1,
          eingang.length,
        ]);
        final flagge = await OrtValue.fromList([mitCache], [1]);
        offen
          ..add(ids)
          ..add(flagge);
        final aus = await _decoder.run({
          'input_ids': ids,
          'encoder_hidden_states': zustand,
          'use_cache_branch': flagge,
          ...past,
        });
        offen.addAll(aus.values);
        lass(ids);
        lass(flagge);
        final logitsTensor = aus['logits']!;
        final alle = await logitsTensor.asFlattenedList();
        lass(logitsTensor);
        final vokabular = alle.length ~/ eingang.length;
        final versatz = (eingang.length - 1) * vokabular;
        final logits = [
          for (var v = 0; v < vokabular; v++)
            (alle[versatz + v] as num).toDouble(),
        ];
        // Selbst-Aufmerksamkeit wächst mit jedem Schritt; die
        // Kreuz-Aufmerksamkeit entsteht im ersten und bleibt dann.
        final naechstes = <String, OrtValue>{};
        for (var i = 0; i < _lagen; i++) {
          for (final kv in ['key', 'value']) {
            lass(past['past_key_values.$i.decoder.$kv']!);
            naechstes['past_key_values.$i.decoder.$kv'] =
                aus['present.$i.decoder.$kv']!;
            if (mitCache) {
              naechstes['past_key_values.$i.encoder.$kv'] =
                  past['past_key_values.$i.encoder.$kv']!;
              lass(aus['present.$i.encoder.$kv']!);
            } else {
              lass(past['past_key_values.$i.encoder.$kv']!);
              naechstes['past_key_values.$i.encoder.$kv'] =
                  aus['present.$i.encoder.$kv']!;
            }
          }
        }
        past = naechstes;
        mitCache = true;
        return logits;
      }

      // Erster Schritt nur mit dem Anfangstoken: Daraus liest das
      // Original, ob überhaupt gesprochen wird und in welcher Sprache.
      final erste = await schritt([anfang]);
      final wkt = _softmax(erste);
      final stille = wkt[keineSprache];
      var gewaehlt = sprache;
      if (gewaehlt == null) {
        gewaehlt = ersteSprache;
        for (var s = 0; s < whisperSprachen.length; s++) {
          if (erste[ersteSprache + s] > erste[gewaehlt!]) {
            gewaehlt = ersteSprache + s;
          }
        }
      }

      var logits = await schritt([gewaehlt!, transkribieren, ohneZeitmarken]);
      final erzeugt = <int>[];
      var summeLogWkt = 0.0;
      for (var i = 0; i < _hoechstensToken; i++) {
        for (final t in _unterdrueckt) {
          logits[t] = double.negativeInfinity;
        }
        // Alles nach dem Textende sind Steuer- und Zeitmarken.
        for (var t = textEnde + 1; t < logits.length; t++) {
          logits[t] = double.negativeInfinity;
        }
        if (i == 0) {
          // Nicht mit einem Leerzeichen und nicht gleich mit dem Ende
          // beginnen (`begin_suppress_tokens`).
          logits[220] = double.negativeInfinity;
          logits[textEnde] = double.negativeInfinity;
        }
        var beste = 0;
        for (var t = 1; t < logits.length; t++) {
          if (logits[t] > logits[beste]) beste = t;
        }
        if (beste == textEnde) break;
        summeLogWkt += math.log(math.max(_softmax(logits)[beste], 1e-30));
        erzeugt.add(beste);
        // Eine Schleife früh erkennen: Was nach 48 Token schon so
        // wiederholt ist, wird am Ende ohnehin verworfen. Auf Rauschen
        // spart das gut drei Viertel der Rechenzeit.
        if (erzeugt.length >= 48 &&
            erzeugt.length % 16 == 0 &&
            whisperKompression(_vokabular.text(erzeugt)) > 2.4) {
          return null;
        }
        logits = await schritt([beste]);
      }

      for (final v in past.values) {
        await gib(v);
      }
      await gib(zustand);

      final text = _vokabular.text(erzeugt).trim();
      final verworfen = whisperVerwerfen(
        keineSprache: stille,
        mittlereLogWkt: erzeugt.isEmpty ? 0 : summeLogWkt / erzeugt.length,
        kompression: whisperKompression(text),
      );
      if (verworfen) return null;
      return (text: text, sprache: gewaehlt);
    } finally {
      for (final v in offen) {
        try {
          await v.dispose();
        } catch (_) {
          // Schon freigegeben oder Sitzung zu – bestmöglich.
        }
      }
    }
  }

  static List<double> _softmax(List<double> logits) {
    var hoechster = double.negativeInfinity;
    for (final l in logits) {
      if (l > hoechster) hoechster = l;
    }
    var summe = 0.0;
    final aus = List<double>.filled(logits.length, 0);
    for (var i = 0; i < logits.length; i++) {
      final e = logits[i] == double.negativeInfinity
          ? 0.0
          : math.exp(logits[i] - hoechster);
      aus[i] = e;
      summe += e;
    }
    for (var i = 0; i < aus.length; i++) {
      aus[i] /= summe;
    }
    return aus;
  }

  Future<void> dispose() async {
    await _encoder.close();
    await _decoder.close();
  }
}

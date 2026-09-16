import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'marian_tokenizer.dart';
import 'modellthreads.dart';

/// Welche Richtung ein [TranslationService] übersetzt.
enum Uebersetzungsrichtung {
  /// Für die Bildbeschreibungen: Das Beschreibungsmodell liefert nur
  /// Englisch.
  enDe('translate_en_de'),

  /// Für Suchanfragen und das Tag-Vokabular: Der CLIP-Text-Encoder
  /// versteht nur Englisch.
  deEn('translate_de_en');

  const Uebersetzungsrichtung(this.dateiPraefix);

  final String dateiPraefix;

  String get encoderDatei => '${dateiPraefix}_encoder.onnx';
  String get decoderDatei => '${dateiPraefix}_decoder.onnx';
}

/// Übersetzt kurze Texte on-device mit einem OPUS-MT/Marian-Modell.
///
/// Aufbau wie bei [FlorenceCaptioningService]: ein Encoder, der den Satz einmal
/// liest, und ein Decoder, der Wort für Wort erzeugt. Zwei Unterschiede,
/// beide gegen die echten ONNX-Dateien geprüft:
///
///  * **Kein Zwischenspeicher für die Aufmerksamkeit.** Der Decoder
///    bekommt in jedem Schritt die ganze bisher erzeugte Folge, statt
///    24 `past_key_values`-Tensoren weiterzureichen. Der zusammengeführte
///    Decoder mit Cache lässt sich im ersten Schritt gar nicht ausführen
///    (die Kreuz-Aufmerksamkeit stolpert über den leeren Cache), und für
///    Sätze dieser Länge – Bildunterschriften, Suchbegriffe – bringt er
///    ohnehin nichts: real gemessen 0,03–0,05 s pro Satz ohne ihn.
///  * **Der Decoder startet mit dem Füllzeichen**, nicht mit dem
///    Satzende. Das ist eine Marian-Eigenheit
///    (`decoder_start_token_id: 58100`), siehe [MarianTokenizer.padId].
///
/// Die Modelle sind optional; ohne sie bleibt alles beim bisherigen
/// Verhalten (englische Beschreibungen, englische Suche).
class TranslationService {
  TranslationService._(this._encoder, this._decoder, this._tokenizer, this.richtung);

  final OrtSession _encoder;
  final OrtSession _decoder;
  final MarianTokenizer _tokenizer;
  final Uebersetzungsrichtung richtung;

  /// Obergrenze für die Länge der Ausgabe. Bildunterschriften und
  /// Suchbegriffe liegen weit darunter; die Grenze verhindert nur, dass
  /// ein Modell, das sich verrennt, endlos weiterläuft.
  static const _maxSchritte = 64;

  static const _vokabularDatei = 'translate_vocab.json';

  static bool isAvailable(String modelsDir, Uebersetzungsrichtung richtung) {
    for (final name in [
      richtung.encoderDatei,
      richtung.decoderDatei,
      _vokabularDatei,
    ]) {
      if (!File('$modelsDir/$name').existsSync()) return false;
    }
    return true;
  }

  static Future<TranslationService> load(
    String modelsDir,
    Uebersetzungsrichtung richtung,
  ) async {
    final ort = OnnxRuntime();
    final encoder = await ort.createSession('$modelsDir/${richtung.encoderDatei}',
        options: modelloptionen());
    final decoder = await ort.createSession('$modelsDir/${richtung.decoderDatei}',
        options: modelloptionen());
    final tokenizer = await MarianTokenizer.loadFromFile('$modelsDir/$_vokabularDatei');
    return TranslationService._(encoder, decoder, tokenizer, richtung);
  }

  /// Übersetzt [text]. Leere Eingabe ergibt leere Ausgabe, ohne das Modell
  /// überhaupt zu bemühen.
  ///
  /// [liveTensors] verfolgt alle noch nicht freigegebenen `OrtValue`s über
  /// die gesamte Schleife – schlägt ein Aufruf mittendrin fehl, gibt der
  /// `finally`-Block alles frei, was zu dem Zeitpunkt offen war, statt
  /// native Tensor-Kennungen für immer liegen zu lassen. Dasselbe Muster
  /// wie in [FlorenceCaptioningService], und aus demselben Anlass: Dort war das
  /// ein Prüfbefund.
  Future<String> translate(String text) async {
    if (text.trim().isEmpty) return '';

    final liveTensors = <OrtValue>{};
    Future<void> freigeben(OrtValue v) async {
      await v.dispose();
      liveTensors.remove(v);
    }

    try {
      final eingabeIds = _tokenizer.encode(text);
      final laenge = eingabeIds.length;

      final inputIds = await OrtValue.fromList(Int64List.fromList(eingabeIds), [1, laenge]);
      final maske = await OrtValue.fromList(
        Int64List.fromList(List<int>.filled(laenge, 1)),
        [1, laenge],
      );
      liveTensors..add(inputIds)..add(maske);

      final encoderAusgabe = await _encoder.run({
        'input_ids': inputIds,
        'attention_mask': maske,
      });
      liveTensors.addAll(encoderAusgabe.values);
      await freigeben(inputIds);

      final hidden = encoderAusgabe['last_hidden_state']!;

      // Wird über alle Schritte unverändert wiederverwendet – ein OrtValue
      // kapselt nur eine native Kennung, mehrfaches Übergeben ist
      // unproblematisch.
      final erzeugt = <int>[];
      var abgebrochen = false;

      for (var schritt = 0; schritt < _maxSchritte; schritt++) {
        final folge = <int>[MarianTokenizer.padId, ...erzeugt];
        final decoderIds =
            await OrtValue.fromList(Int64List.fromList(folge), [1, folge.length]);
        liveTensors.add(decoderIds);

        final ausgabe = await _decoder.run({
          'encoder_attention_mask': maske,
          'input_ids': decoderIds,
          'encoder_hidden_states': hidden,
        });
        liveTensors.addAll(ausgabe.values);
        await freigeben(decoderIds);

        final logits = ausgabe['logits']!;
        final werte = await logits.asFlattenedList();

        // Die Logits decken die ganze bisherige Folge ab; massgeblich ist
        // nur der letzte Zeitschritt. Ohne diesen Versatz sagte das Modell
        // in jedem Schritt dasselbe erste Wort voraus.
        final vokabular = werte.length ~/ folge.length;
        final versatz = (folge.length - 1) * vokabular;

        var besteId = 0;
        var besterWert = double.negativeInfinity;
        for (var i = 0; i < vokabular; i++) {
          final wert = (werte[versatz + i] as num).toDouble();
          if (wert > besterWert) {
            besterWert = wert;
            besteId = i;
          }
        }

        // Alle Ausgaben dieses Schritts freigeben – anders als beim
        // Beschreibungsmodell lebt hier nichts davon weiter.
        for (final v in ausgabe.values) {
          await freigeben(v);
        }

        if (besteId == MarianTokenizer.eosId) {
          abgebrochen = true;
          break;
        }
        erzeugt.add(besteId);
      }

      // Ohne Satzende ist die Ausgabe abgeschnitten. Sie trotzdem
      // zurückzugeben ist besser als nichts – ein halber Satz ist als
      // Beschreibung noch brauchbar, und die Alternative wäre ein Fehler
      // für etwas, das der Nutzer nicht beeinflussen kann.
      if (!abgebrochen && erzeugt.isEmpty) return '';

      await freigeben(hidden);
      await freigeben(maske);

      return _tokenizer.decode(erzeugt);
    } finally {
      for (final v in liveTensors) {
        try {
          await v.dispose();
        } catch (_) {
          // Bereits freigegeben oder Sitzung inzwischen geschlossen.
        }
      }
    }
  }

  Future<void> dispose() async {
    await _encoder.close();
    await _decoder.close();
  }
}

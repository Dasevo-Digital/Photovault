import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'bart_tokenizer.dart';
import 'modellthreads.dart';

/// Bildvorverarbeitung laut `preprocessor_config.json` des Exports:
/// 768×768, ImageNet-Statistik, **kein** mittiger Zuschnitt
/// (`do_center_crop: false`) – anders als bei CLIP, wo genau das nötig ist.
/// Nicht aus der Modellkarte übernommen, sondern der Datei entnommen.
const _mean = [0.485, 0.456, 0.406];
const _std = [0.229, 0.224, 0.225];
const _bildGroesse = 768;

const _lagen = 6;
const _koepfe = 12;
const _kopfBreite = 64;

/// Token, die den nächsten Schritt zu einer Wiederholung machen würden.
///
/// Sperrt jedes Token, das dieselbe Folge von [n] Stücken ein zweites Mal
/// entstehen liesse. Ohne diese Bremse dreht gieriges Decodieren im
/// Kreis – das alte Modell lieferte in der Prüfstichprobe „eine Gruppe
/// von Männern in einem Raum mit einer Gruppe von Männern".
///
/// Als freie Funktion, weil es reine Rechnerei ist und sich so ohne
/// ONNX-Sitzung prüfen lässt. Der Wert 3 steht in der
/// `generation_config.json` des Modells.
Set<int> gesperrteToken(List<int> bisher, int n) {
  if (n < 2 || bisher.length < n) return const {};
  final praefix = bisher.sublist(bisher.length - (n - 1));
  final gesperrt = <int>{};
  for (var i = 0; i + n <= bisher.length; i++) {
    var passt = true;
    for (var k = 0; k < n - 1; k++) {
      if (bisher[i + k] != praefix[k]) {
        passt = false;
        break;
      }
    }
    if (passt) gesperrt.add(bisher[i + n - 1]);
  }
  return gesperrt;
}

/// Die Aufgabenfrage für eine gewöhnliche Bildunterschrift.
///
/// Florence-2 ist ein Mehrzweckmodell; welche Aufgabe es lösen soll, sagt
/// ihm ein Satz, keine Kennung. `<CAPTION>` ist nur die Kurzform, die die
/// Referenzbibliothek vor dem Zerlegen durch genau diesen Satz ersetzt.
const _aufgabe = 'What does the image describe?';

/// Bildunterschriften mit **Florence-2** (base-ft) statt ViT-GPT2.
///
/// Der Wechsel hat einen gemessenen Grund. An 40 echten Fotos aus einer
/// gewachsenen Bibliothek, von Hand beurteilt:
///
/// | | trifft | trifft halb | falsch |
/// |---|---|---|---|
/// | ViT-GPT2 | 11 | 18 | 11 |
/// | Florence-2 | 27 | 11 | 2 |
///
/// An einer zweiten, überschneidungsfreien Stichprobe dasselbe Bild
/// (7 gegen 27). ViT-GPT2 ist auf COCO trainiert und greift deshalb
/// bevorzugt zu COCO-Gegenständen: In der Prüfstichprobe erfand es eine
/// Katze, einen Hydranten, eine Fernbedienung und eine Krawatte, die
/// nirgends zu sehen waren.
///
/// Florence-2 liest ausserdem Schrift im Bild – Ladenschilder,
/// Ortstafeln, Aufschriften. Für eine Fotosammlung ist das mehr wert, als
/// es klingt.
///
/// **Der Preis:** vier Modelldateien statt zwei (275 statt 246 MB) und
/// rund fünfmal so viel Rechenzeit je Foto. Beides erträglich, weil die
/// Beschreibung ohnehin im Hintergrund läuft.
///
/// Die Ein-/Ausgabenamen sind gegen die heruntergeladenen ONNX-Dateien
/// geprüft (Python `onnxruntime`), nicht geraten – wie bei allen Modellen
/// hier.
class FlorenceCaptioningService {
  FlorenceCaptioningService._(
      this._vision, this._embed, this._encoder, this._decoder, this._tokenizer);

  final OrtSession _vision;
  final OrtSession _embed;
  final OrtSession _encoder;
  final OrtSession _decoder;
  final BartTokenizer _tokenizer;

  /// Florence-2 schreibt ganze Sätze; 30 Schritte wie beim Vorgänger
  /// reichten nicht. 64 deckt auch die längsten beobachteten Sätze ab.
  static const _maxNeueToken = 64;

  /// Verhindert die Endlosschleife, in die gieriges Decodieren gern
  /// läuft („eine Gruppe von Männern in einem Raum mit einer Gruppe von
  /// Männern"). Der Wert steht so in der `generation_config.json`.
  static const _keinWiederholtesNgram = 3;

  static const dateien = [
    'florence_vision.onnx',
    'florence_embed.onnx',
    'florence_encoder.onnx',
    'florence_decoder.onnx',
    'florence_vocab.json',
    'florence_merges.txt',
  ];

  static bool isAvailable(String modelsDir) =>
      dateien.every((n) => File('$modelsDir/$n').existsSync());

  static Future<FlorenceCaptioningService> load(String modelsDir) async {
    final ort = OnnxRuntime();
    return FlorenceCaptioningService._(
      await ort.createSession('$modelsDir/florence_vision.onnx',
          options: modelloptionen()),
      await ort.createSession('$modelsDir/florence_embed.onnx',
          options: modelloptionen()),
      await ort.createSession('$modelsDir/florence_encoder.onnx',
          options: modelloptionen()),
      await ort.createSession('$modelsDir/florence_decoder.onnx',
          options: modelloptionen()),
      await BartTokenizer.loadFromFiles(
        vocabJsonPath: '$modelsDir/florence_vocab.json',
        mergesTxtPath: '$modelsDir/florence_merges.txt',
      ),
    );
  }

  Float32List _pixel(img.Image decoded) {
    final skaliert = img.copyResize(decoded,
        width: _bildGroesse,
        height: _bildGroesse,
        interpolation: img.Interpolation.cubic);
    final chw = Float32List(3 * _bildGroesse * _bildGroesse);
    var i = 0;
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < _bildGroesse; y++) {
        for (var x = 0; x < _bildGroesse; x++) {
          final p = skaliert.getPixel(x, y);
          final wert = c == 0 ? p.r : (c == 1 ? p.g : p.b);
          chw[i++] = (wert / 255.0 - _mean[c]) / _std[c];
        }
      }
    }
    return chw;
  }

  /// Erzeugt eine englische Bildunterschrift.
  ///
  /// [liveTensors] verfolgt wie beim Vorgänger alle offenen `OrtValue`s
  /// über den ganzen Lauf: Bricht ein Schritt mitten in der Schleife ab,
  /// gibt der finally-Block frei, was noch offen ist, statt native
  /// Handles zu verlieren (Prüfrunden-Fund von damals).
  Future<String> generateCaption(img.Image decoded) async {
    final offen = <OrtValue>{};
    Future<void> gib(OrtValue v) async {
      await v.dispose();
      offen.remove(v);
    }

    try {
      // --- Bild -> Merkmale -------------------------------------------
      final pixel = await OrtValue.fromList(
          _pixel(decoded), [1, 3, _bildGroesse, _bildGroesse]);
      offen.add(pixel);
      final sicht = await _vision.run({'pixel_values': pixel});
      offen.addAll(sicht.values);
      await gib(pixel);
      final bildMerkmale = sicht['image_features']!;
      final bildRoh = await bildMerkmale.asFlattenedList();
      final bildLaenge = bildRoh.length ~/ 768;

      // --- Aufgabenfrage -> Einbettung --------------------------------
      final frageIds = _tokenizer.encode(_aufgabe);
      final frageTensor =
          await OrtValue.fromList(Int64List.fromList(frageIds), [1, frageIds.length]);
      offen.add(frageTensor);
      final frageAus = await _embed.run({'input_ids': frageTensor});
      offen.addAll(frageAus.values);
      await gib(frageTensor);
      final frageRoh = await frageAus['inputs_embeds']!.asFlattenedList();

      // Bild zuerst, dann Text – so fügt es auch die Referenz zusammen.
      final gesamt = bildLaenge + frageIds.length;
      final zusammen = Float32List(gesamt * 768);
      for (var i = 0; i < bildRoh.length; i++) {
        zusammen[i] = (bildRoh[i] as num).toDouble();
      }
      for (var i = 0; i < frageRoh.length; i++) {
        zusammen[bildRoh.length + i] = (frageRoh[i] as num).toDouble();
      }
      for (final v in sicht.values) {
        await gib(v);
      }
      for (final v in frageAus.values) {
        await gib(v);
      }

      final eingabe = await OrtValue.fromList(zusammen, [1, gesamt, 768]);
      final maske = await OrtValue.fromList(
          Int64List.fromList(List.filled(gesamt, 1)), [1, gesamt]);
      offen.add(eingabe);
      offen.add(maske);
      final encAus =
          await _encoder.run({'inputs_embeds': eingabe, 'attention_mask': maske});
      offen.addAll(encAus.values);
      await gib(eingabe);
      final encZustand = encAus['last_hidden_state']!;

      // --- Decoder ----------------------------------------------------
      // Der zusammengeführte Decoder stolpert im ersten Schritt über einen
      // LEEREN Kreuz-Aufmerksamkeits-Cache (dieselbe Stelle wie seinerzeit
      // bei OPUS-MT). Mit voller Encoderlänge statt Länge 0 läuft er – das
      // erspart die fünfte Modelldatei.
      var past = <String, OrtValue>{};
      for (var i = 0; i < _lagen; i++) {
        for (final kv in ['key', 'value']) {
          final d = await OrtValue.fromList(
              Float32List(0), [1, _koepfe, 0, _kopfBreite]);
          final e = await OrtValue.fromList(
              Float32List(_koepfe * gesamt * _kopfBreite),
              [1, _koepfe, gesamt, _kopfBreite]);
          offen.add(d);
          offen.add(e);
          past['past_key_values.$i.decoder.$kv'] = d;
          past['past_key_values.$i.encoder.$kv'] = e;
        }
      }

      final erzeugt = <int>[BartTokenizer.eosId, BartTokenizer.bosId];
      var mitCache = false;

      for (var schritt = 0; schritt < _maxNeueToken; schritt++) {
        final eingang = mitCache ? [erzeugt.last] : erzeugt;
        final idTensor =
            await OrtValue.fromList(Int64List.fromList(eingang), [1, eingang.length]);
        offen.add(idTensor);
        final embAus = await _embed.run({'input_ids': idTensor});
        offen.addAll(embAus.values);
        await gib(idTensor);
        final decEinbettung = embAus['inputs_embeds']!;

        final cacheFlagge = await OrtValue.fromList([mitCache], [1]);
        offen.add(cacheFlagge);
        final aus = await _decoder.run({
          'encoder_attention_mask': maske,
          'encoder_hidden_states': encZustand,
          'inputs_embeds': decEinbettung,
          'use_cache_branch': cacheFlagge,
          ...past,
        });
        offen.addAll(aus.values);
        await gib(cacheFlagge);
        await gib(decEinbettung);

        final logitsTensor = aus['logits']!;
        final logits = await logitsTensor.asFlattenedList();
        await gib(logitsTensor);

        final vokabular = logits.length ~/ eingang.length;
        final versatz = (eingang.length - 1) * vokabular;
        final gesperrt = gesperrteToken(erzeugt, _keinWiederholtesNgram);
        var besteId = 0;
        var besterWert = double.negativeInfinity;
        for (var v = 0; v < vokabular; v++) {
          if (gesperrt.contains(v)) continue;
          final wert = (logits[versatz + v] as num).toDouble();
          if (wert > besterWert) {
            besterWert = wert;
            besteId = v;
          }
        }

        // Der Decoder-Teil wächst mit jedem Schritt. Der Kreuz-Teil hängt
        // nur am Bild: Im ERSTEN Schritt rechnet ihn der Decoder aus, ab
        // dann liefert er dafür nur noch einen Platzhalter. Also einmal
        // übernehmen und danach festhalten – wer den Platzhalter
        // übernimmt, bekommt für jedes Foto denselben Satz.
        final naechstes = <String, OrtValue>{};
        for (var i = 0; i < _lagen; i++) {
          for (final kv in ['key', 'value']) {
            await gib(past['past_key_values.$i.decoder.$kv']!);
            naechstes['past_key_values.$i.decoder.$kv'] =
                aus['present.$i.decoder.$kv']!;
            if (mitCache) {
              naechstes['past_key_values.$i.encoder.$kv'] =
                  past['past_key_values.$i.encoder.$kv']!;
              await gib(aus['present.$i.encoder.$kv']!);
            } else {
              await gib(past['past_key_values.$i.encoder.$kv']!);
              naechstes['past_key_values.$i.encoder.$kv'] =
                  aus['present.$i.encoder.$kv']!;
            }
          }
        }
        past = naechstes;
        mitCache = true;

        if (besteId == BartTokenizer.eosId) break;
        erzeugt.add(besteId);
      }

      for (final v in past.values) {
        await gib(v);
      }
      await gib(encZustand);
      await gib(maske);

      return _tokenizer.decode(erzeugt.sublist(2));
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

  Future<void> dispose() async {
    await _vision.close();
    await _embed.close();
    await _encoder.close();
    await _decoder.close();
  }
}
